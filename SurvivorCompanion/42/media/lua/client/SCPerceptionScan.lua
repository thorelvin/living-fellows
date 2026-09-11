-- SPDX-License-Identifier: MIT

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion

SC.PerceptionScan = SC.PerceptionScan or {}
local Scan = SC.PerceptionScan
local scheduleCache = {}
local sharedNative = nil
local nativeGeneration = 0

local function newSharedNative(list, count)
    nativeGeneration = nativeGeneration + 1
    return {
        generation = nativeGeneration,
        list = list,
        count = count,
        cursor = 0,
        cycle = nativeGeneration,
        completedCycle = 0,
        published = {},
        build = {},
        nextAdvanceAt = 0,
    }
end

-- A list-order cursor that alternates from the beginning and end avoids the
-- old worst case where a newly relevant zombie near the tail of a busy cell
-- list waited for every earlier entry. It still visits every index exactly
-- once, so completion retains a clear and testable meaning.
local function nativeIndex(cursor, count)
    local pair = math.floor(cursor / 2)
    if cursor % 2 == 0 then return pair end
    return count - pair - 1
end

local function advanceSharedNative(list, count, maximum, deadline, clock, now)
    if sharedNative == nil or sharedNative.list ~= list or sharedNative.count ~= count then
        sharedNative = newSharedNative(list, count)
    end
    local shared = sharedNative
    if now < (shared.nextAdvanceAt or 0) then return 0, true, false end

    local processed = 0
    local limit = math.min(count, 128,
        math.max(1, math.floor(tonumber(maximum) or 64)))
    while processed < limit and shared.cursor < count do
        -- Four entries are the bounded forward-progress floor used throughout
        -- the sliced perception/topology jobs. The wall-clock deadline is
        -- checked after that floor and after every subsequent native read.
        if deadline and processed >= 4 and clock() >= deadline then break end
        local index = nativeIndex(shared.cursor, count)
        local value, found = SC.NativeList.get(list, index)
        shared.cursor = shared.cursor + 1
        processed = processed + 1
        if found and value ~= nil then
            local x, y, z = SC.GameplayUtil.position(value)
            shared.build[#shared.build + 1] = {
                actor = value, index = index, x = x, y = y, z = z,
            }
        end
    end

    local completed = shared.cursor >= count
    if completed then
        shared.published = shared.build
        shared.completedCycle = shared.cycle
        nativeGeneration = nativeGeneration + 1
        shared.cycle = nativeGeneration
        shared.build = {}
        shared.cursor = 0
    end
    local interval = completed
        and math.max(250, tonumber(SC.GameplayUtil.config(
            "perceptionNativeCompletedHoldMs")) or 1000)
        or math.max(16, tonumber(SC.GameplayUtil.config(
            "perceptionNativeSharedPulseMs")) or 50)
    shared.nextAdvanceAt = now + interval
    return processed, false, completed
end

local function resetActorNativeState(state, generation)
    state.nativeSharedGeneration = generation
    state.nativeRosterCycle = nil
    state.nativeRosterSource = nil
    state.nativeRosterCursor = 1
    state.nativeRosterComplete = false
    state.nativeLastCompleteCycle = nil
    state.nativePreviewCycle = nil
    state.nativePreviewCursor = 1
    state.nativeCandidateQueue = nil
    state.nativeCandidateIndex = nil
end

local function compactCandidateQueue(state)
    local queue = state.nativeCandidateQueue
    local index = math.max(1, math.floor(tonumber(state.nativeCandidateIndex) or 1))
    if type(queue) ~= "table" or index > #queue then
        state.nativeCandidateQueue, state.nativeCandidateIndex = {}, 1
        return state.nativeCandidateQueue
    end
    if index > 1 then
        local compact = {}
        for current = index, #queue do compact[#compact + 1] = queue[current] end
        queue = compact
        state.nativeCandidateQueue, state.nativeCandidateIndex = queue, 1
    end
    return queue
end

-- Build 42 IsoGameCharacter.CanSee is a direct LosUtil.lineClear query; there
-- is no ten-tile visual range there. Discover real native zombie candidates
-- instead of spending most of an extended-range scan on empty grid squares.
--
-- The expensive Java list traversal and candidate position reads are shared by
-- all companions. Each actor independently applies its radius/floor filter and
-- SCSenses proves current distance/floor/LOS before admitting a visual threat,
-- so sharing discovery never shares perception.
function Scan.nativeCandidates(actor, state, radius, maximum, deadline, clock)
    local U = SC.GameplayUtil
    local list, available = U.call(U.cell(), "getZombieList")
    if not available or list == nil or not SC.NativeList then return nil end
    clock = type(clock) == "function" and clock or U.nowMs
    local now = clock()
    local count = SC.NativeList.size(list)
    local x, y, z = U.position(actor)
    if x == nil then return {}, { processed = 0, complete = true, count = count } end

    local processed, reused, globalCompleted = advanceSharedNative(
        list, count, maximum, deadline, clock, now)
    local shared = sharedNative
    if state.nativeSharedGeneration ~= shared.generation then
        resetActorNativeState(state, shared.generation)
    end

    local queue = compactCandidateQueue(state)
    local queueCap = math.max(16, math.min(128,
        math.floor(tonumber(U.config("perceptionNativeCandidateQueueHardCap")) or 64)))
    local queryLimit = math.max(16, math.min(256,
        math.floor(tonumber(U.config("perceptionNativeRosterQueryPerSlice")) or 128)))
    local candidateLimit = math.min(32, math.max(1,
        math.floor(tonumber(U.config("perceptionNativeLosPerSlice")) or 12)))

    -- A newly published complete roster supersedes previews from that cycle.
    -- Re-reading it is Lua-local (no duplicate Java list traversal) and lets
    -- completion mean that this observer inspected the whole coherent roster.
    if shared.completedCycle > 0 and state.nativeRosterCycle ~= shared.completedCycle
        and (state.nativeRosterCycle == nil or state.nativeRosterComplete == true) then
        state.nativeRosterCycle = shared.completedCycle
        state.nativeRosterSource = shared.published
        state.nativeRosterCursor = 1
        state.nativeRosterComplete = false
        state.nativeCandidateQueue, state.nativeCandidateIndex = {}, 1
        queue = state.nativeCandidateQueue
    end

    -- Once adopted, this observer owns an immutable roster reference.  The
    -- producer may publish several newer cycles while a slow observer drains
    -- it; that must not invalidate the observer's cursor or queued tail.
    local coherent = state.nativeRosterComplete ~= true
        and tonumber(state.nativeRosterCycle) ~= nil
        and type(state.nativeRosterSource) == "table"
    local source, cursor
    if coherent then
        -- Keep the exact completed roster alive while this observer drains it;
        -- another global cycle may finish meanwhile without invalidating the
        -- completion proof or dropping a queued tail.
        source = state.nativeRosterSource
        cursor = math.max(1, math.floor(tonumber(state.nativeRosterCursor) or 1))
    else
        if state.nativePreviewCycle ~= shared.cycle then
            state.nativePreviewCycle = shared.cycle
            state.nativePreviewCursor = 1
        end
        source = shared.build
        cursor = math.max(1, math.floor(tonumber(state.nativePreviewCursor) or 1))
    end

    local radiusSq = math.max(1, tonumber(radius) or 24) ^ 2
    local queued = setmetatable({}, { __mode = "k" })
    for _, value in ipairs(queue) do queued[value] = true end
    local additions, distances = {}, setmetatable({}, { __mode = "k" })
    local inspected = 0
    while cursor <= #source and inspected < queryLimit
        and #queue + #additions < queueCap do
        if deadline and inspected >= 4 and clock() >= deadline then break end
        local entry = source[cursor]
        local value = type(entry) == "table" and entry.actor or entry
        cursor = cursor + 1
        inspected = inspected + 1
        if value ~= nil and not queued[value] then
            local zx = type(entry) == "table" and entry.x or nil
            local zy = type(entry) == "table" and entry.y or nil
            local zz = type(entry) == "table" and entry.z or nil
            if zx == nil then zx, zy, zz = U.position(value) end
            if zx and math.floor(zz or 0) == math.floor(z or 0) then
                local dx, dy = zx - x, zy - y
                local distanceSq = dx * dx + dy * dy
                if distanceSq <= radiusSq then
                    queued[value] = true
                    additions[#additions + 1] = value
                    distances[value] = {
                        distanceSq = distanceSq,
                        index = type(entry) == "table" and entry.index or cursor,
                    }
                end
            end
        end
    end
    table.sort(additions, function(left, right)
        local leftDistance = distances[left] or {}
        local rightDistance = distances[right] or {}
        if leftDistance.distanceSq == rightDistance.distanceSq then
            return (leftDistance.index or math.huge) < (rightDistance.index or math.huge)
        end
        return (leftDistance.distanceSq or math.huge)
            < (rightDistance.distanceSq or math.huge)
    end)
    for _, value in ipairs(additions) do queue[#queue + 1] = value end

    if coherent then state.nativeRosterCursor = cursor
    else state.nativePreviewCursor = cursor end

    local result = {}
    local queueIndex = math.max(1, math.floor(tonumber(state.nativeCandidateIndex) or 1))
    while #result < candidateLimit and queueIndex <= #queue do
        result[#result + 1] = queue[queueIndex]
        queueIndex = queueIndex + 1
    end
    state.nativeCandidateQueue, state.nativeCandidateIndex = queue, queueIndex
    local queuePending = math.max(0, #queue - queueIndex + 1)
    if coherent and cursor > #source and queuePending == 0 then
        state.nativeRosterComplete = true
        state.nativeLastCompleteCycle = state.nativeRosterCycle
    end
    if queuePending == 0 then
        state.nativeCandidateQueue, state.nativeCandidateIndex = nil, nil
    end

    local observerCycle = tonumber(state.nativeRosterCycle) or 0
    local complete = observerCycle > 0 and state.nativeRosterComplete == true
        and state.nativeLastCompleteCycle == observerCycle
    local freshComplete = complete and observerCycle == shared.completedCycle
    local sourceRemaining = coherent and math.max(0, #source - cursor + 1) or 0
    local pending = queuePending + sourceRemaining
    local reportedCursor = complete and count or shared.cursor
    state.nativeScanCursor = reportedCursor
    state.nativeScanList, state.nativeScanAt = list, now
    state.nativeScanCount = count
    state.nextNativeScanAt = shared.nextAdvanceAt
    state.nativeScanResult = result
    state.nativeScanMeta = {
        processed = processed,
        complete = complete,
        freshComplete = freshComplete,
        reused = reused,
        count = count,
        cursor = reportedCursor,
        globalCursor = shared.cursor,
        evaluated = #result,
        inspected = inspected,
        pending = pending,
        previewPending = coherent and 0 or math.max(0, #source - cursor + 1),
        listComplete = complete,
        endReached = shared.completedCycle > 0,
        globalCompleted = globalCompleted,
        cycle = observerCycle,
        publishedCycle = shared.completedCycle,
        generation = shared.generation,
    }
    return result, state.nativeScanMeta
end

local function addOffset(offsets, seen, dx, dy, budget, band, dz)
    if #offsets >= budget then return false end
    local key = tostring(dx) .. ":" .. tostring(dy) .. ":" .. tostring(dz or 0)
    if seen[key] then return true end
    seen[key] = true
    offsets[#offsets + 1] = {
        x = dx, y = dy, z = dz, d2 = dx * dx + dy * dy, band = band,
    }
    return true
end

local function schedule(radius)
    local key = tostring(radius)
    if scheduleCache[key] then return scheduleCache[key] end
    local priority, buckets = {}, { {}, {}, {}, {}, {}, {}, {}, {} }
    local nearRadius = math.min(4, radius)
    for distance = 0, radius do
        for dx = -distance, distance do
            for dy = -distance, distance do
                if math.max(math.abs(dx), math.abs(dy)) == distance then
                    local band = distance <= nearRadius and "near"
                        or (dx == 0 or dy == 0) and "ray" or "outer"
                    local entry = { x = dx, y = dy, d2 = dx * dx + dy * dy, band = band }
                    if band == "near" or band == "ray" then priority[#priority + 1] = entry end
                    local selector = ((dx * 31 + dy * 17 + distance * 13) % 8 + 8) % 8
                    buckets[selector + 1][#buckets[selector + 1] + 1] = entry
                end
            end
        end
    end

    local coverage, index, remaining = {}, 1, (radius * 2 + 1) ^ 2
    while remaining > 0 do
        for bucket = 1, 8 do
            local entry = buckets[bucket][index]
            if entry then
                coverage[#coverage + 1] = entry
                remaining = remaining - 1
            end
        end
        index = index + 1
    end

    local vertical = {}
    for distance = 0, 2 do
        for dx = -distance, distance do
            for dy = -distance, distance do
                if math.max(math.abs(dx), math.abs(dy)) == distance then
                    for _, dz in ipairs({ -1, 1 }) do
                        vertical[#vertical + 1] = {
                            x = dx, y = dy, z = dz, d2 = dx * dx + dy * dy,
                            band = "vertical",
                        }
                    end
                end
            end
        end
    end
    local value = { priority = priority, coverage = coverage, vertical = vertical }
    scheduleCache[key] = value
    return value
end

function Scan.nextOffsets(state, radius, squareBudget)
    local verticalBudget = math.min(24, math.floor(squareBudget * 0.12))
    local horizontalBudget = math.max(0, squareBudget - verticalBudget)
    local plan = schedule(radius)
    local offsets, seen = {}, {}

    local priorityBudget = math.min(#plan.priority, math.floor(horizontalBudget * 0.70))
    for index = 1, priorityBudget do
        local entry = plan.priority[index]
        addOffset(offsets, seen, entry.x, entry.y, horizontalBudget, entry.band)
    end

    local horizontalCursor = math.floor(tonumber(state.scanCoverageCursor) or 1)
    if horizontalCursor < 1 or horizontalCursor > #plan.coverage then horizontalCursor = 1 end
    local horizontalWrapped, examined = false, 0
    while #offsets < horizontalBudget and examined < #plan.coverage do
        local entry = plan.coverage[horizontalCursor]
        horizontalCursor = horizontalCursor + 1
        examined = examined + 1
        if horizontalCursor > #plan.coverage then
            horizontalCursor = 1
            horizontalWrapped = true
        end
        addOffset(offsets, seen, entry.x, entry.y, horizontalBudget, entry.band)
    end
    state.scanCoverageCursor = horizontalCursor

    local verticalCursor = math.floor(tonumber(state.scanVerticalCursor) or 1)
    if verticalCursor < 1 or verticalCursor > #plan.vertical then verticalCursor = 1 end
    local verticalWrapped = false
    for _ = 1, verticalBudget do
        local entry = plan.vertical[verticalCursor]
        addOffset(offsets, seen, entry.x, entry.y, squareBudget, entry.band, entry.z)
        verticalCursor = verticalCursor + 1
        if verticalCursor > #plan.vertical then
            verticalCursor = 1
            verticalWrapped = true
        end
    end
    state.scanVerticalCursor = verticalCursor
    return offsets, {
        horizontalCursor = horizontalCursor,
        horizontalWrapped = horizontalWrapped,
        horizontalExamined = examined,
        horizontalTotal = #plan.coverage,
        verticalCursor = verticalCursor,
        verticalWrapped = verticalWrapped,
        verticalTotal = #plan.vertical,
        priorityCount = priorityBudget,
    }
end

function Scan.newJob(state, actorSquare, originX, originY, originZ, radius, squareBudget)
    state.scanPhase = ((state.scanPhase or -1) + 1) % 8
    local offsets, coverage = Scan.nextOffsets(state, radius, squareBudget)
    return {
        phase = state.scanPhase,
        originSquare = actorSquare,
        originX = originX, originY = originY, originZ = originZ,
        radius = radius, squareBudget = squareBudget,
        offsets = offsets, coverage = coverage, index = 1,
        scannedSquares = 0, outerSampled = 0,
        threats = {}, immediate = {}, fenced = {}, stealthThreats = {},
        seen = setmetatable({}, { __mode = "k" }),
    }
end

function Scan.invalid(job, originX, originY, originZ, radius, squareBudget, rebaseDistance)
    if type(job) ~= "table" or job.index > #(job.offsets or {}) then
        return true, "complete", 0
    end
    if job.originZ ~= originZ then return true, "floor", 0 end
    if job.radius ~= radius or job.squareBudget ~= squareBudget then
        return true, "configuration", 0
    end
    local dx, dy = (originX or 0) - (job.originX or 0), (originY or 0) - (job.originY or 0)
    local distanceSq = dx * dx + dy * dy
    local threshold = math.max(0.25, tonumber(rebaseDistance) or 2.0)
    if distanceSq >= threshold * threshold then
        return true, "movement", math.sqrt(distanceSq)
    end
    return false, nil, math.sqrt(distanceSq)
end

function Scan.reset()
    scheduleCache = {}
    sharedNative = nil
    -- Do not reuse an epoch: actor runtimes can outlive a global world/reset
    -- pulse and must discard any cursor that belonged to the old roster.
    nativeGeneration = nativeGeneration + 1
end

return Scan
