-- SPDX-License-Identifier: MIT

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion

SC.PerceptionScan = SC.PerceptionScan or {}
local Scan = SC.PerceptionScan
local scheduleCache = {}
local sharedNative = nil
local nativeGeneration = 0
local nativeSnapshotScratch = {}
local nativeSnapshotShared = nil
local nativeSnapshotEpoch = 1
local nativeSnapshotRetryAt = 0

local function bridgeValue()
    if type(_G) ~= "table" then return nil end
    return rawget(_G, "SCBridge")
end

-- Protocol 8 copies the mutable Java zombie list and its hot coordinates in a
-- single main-thread call. Success is coherent immediately; overflow/failure
-- falls through to the sliced Lua producer without publishing a partial list.
local function nativeBulkSnapshot(now, clock)
    local interval = math.max(50, math.floor(tonumber(
        SC.GameplayUtil.config("nativeZombieSnapshotIntervalMs")) or 250))
    if nativeSnapshotShared and now < (nativeSnapshotShared.nextAdvanceAt or 0) then
        return nativeSnapshotShared, 0, true, false
    end
    if now < nativeSnapshotRetryAt then return nil end
    local bridge = bridgeValue()
    if bridge == nil or not SC.Call or type(SC.Call.static) ~= "function" then return nil end
    local maximum = math.max(1, math.floor(tonumber(
        SC.GameplayUtil.config("nativeZombieSnapshotMaximum")) or 8192))
    local tracing = SC.Performance and type(SC.Performance.isTracing) == "function"
        and SC.Performance.isTracing() == true
    local started = tracing and clock() or nil
    local scope = tracing and SC.Performance.beginScope("perception.native-snapshot") or nil
    local called, count = SC.Call.static(
        bridge, "fillZombieSnapshot", nativeSnapshotScratch, maximum)
    if scope then
        SC.Performance.endScope(scope)
        SC.Performance.record("perception.native-snapshot", nil,
            math.max(0, clock() - started), math.max(0, tonumber(count) or 0), false)
    end
    count = called and tonumber(count) or nil
    if count == nil or count < 0 then
        nativeSnapshotRetryAt = now + interval
        return nil
    end
    count = math.floor(count)
    -- Publish the coherent buffer itself and rotate the scratch reference.
    -- Observers may drain an older snapshot while Java fills the next one;
    -- reading flat quadruples avoids allocating one Lua wrapper per zombie.
    local published = nativeSnapshotScratch
    nativeSnapshotScratch = {}
    nativeGeneration = nativeGeneration + 1
    nativeSnapshotShared = {
        generation = "bridge:" .. tostring(nativeSnapshotEpoch),
        list = published,
        liveCount = count,
        cycleCount = count,
        cursor = count,
        cycle = nativeGeneration,
        completedCycle = nativeGeneration,
        published = published,
        publishedCount = count,
        publishedFlat = true,
        build = published,
        completedAt = now,
        evidenceValid = true,
        evidenceCount = count,
        rejectedCycles = 0,
        nextAdvanceAt = now + interval,
    }
    return nativeSnapshotShared, count, false, true
end

local function newSharedNative(list, count)
    nativeGeneration = nativeGeneration + 1
    return {
        generation = nativeGeneration,
        list = list,
        liveCount = count,
        cycleCount = count,
        cursor = 0,
        cycle = nativeGeneration,
        completedCycle = 0,
        published = {},
        publishedCount = 0,
        build = {},
        buildSeen = {},
        verification = nil,
        verificationCount = nil,
        completedAt = nil,
        evidenceValid = false,
        evidenceCount = nil,
        evidenceInvalidatedAt = nil,
        rejectedCycles = 0,
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

local function sameRoster(left, right, count)
    if type(left) ~= "table" or type(right) ~= "table"
        or #left ~= count or #right ~= count then return false end
    local identities = {}
    for _, entry in ipairs(left) do identities[entry.actor] = true end
    for _, entry in ipairs(right) do
        if not identities[entry.actor] then return false end
        identities[entry.actor] = nil
    end
    -- Both inputs are de-duplicated while they are built and their lengths
    -- already match, so membership of every right-side actor proves equality.
    -- Avoid relying on the optional global next() in stripped Kahlua fixtures.
    return true
end

local function invalidateEvidence(shared, now)
    shared.evidenceValid = false
    shared.evidenceInvalidatedAt = now
end

local function advanceSharedNative(list, count, maximum, deadline, clock, now)
    if sharedNative == nil or sharedNative.list ~= list then
        sharedNative = newSharedNative(list, count)
    end
    local shared = sharedNative
    if shared.liveCount ~= count then
        -- A changed native population invalidates negative evidence
        -- immediately. Time alone does not: the old one-second expiry created
        -- a long danger_check_pending window during every unchanged rescan.
        invalidateEvidence(shared, now)
    end
    shared.liveCount = count
    if count == 0 and (shared.cycleCount ~= 0 or shared.cursor > 0
        or #shared.build > 0) then
        -- Zero is not ordinary churn: the engine has authoritatively emptied
        -- the live roster, so retaining an in-flight populated snapshot would
        -- manufacture threats that no longer exist.
        shared.cycleCount, shared.cursor = 0, 0
        shared.build, shared.buildSeen = {}, {}
        shared.verification, shared.verificationCount = nil, nil
        shared.nextAdvanceAt = now
    end
    -- A completed roster may be held briefly to avoid needless rescans. If the
    -- next cycle has not consumed anything yet, a size change is fresh work,
    -- not churn inside a cycle, and should wake the producer immediately.
    if shared.cursor == 0 and #shared.build == 0 and count ~= shared.cycleCount then
        shared.cycleCount = count
        shared.nextAdvanceAt = now
        shared.published, shared.publishedCount = {}, 0
        shared.completedCycle = 0
        shared.verification, shared.verificationCount = nil, nil
    end
    if now < (shared.nextAdvanceAt or 0) then return 0, true, false end

    local processed = 0
    local limit = math.min(math.max(1, shared.cycleCount), 128,
        math.max(1, math.floor(tonumber(maximum) or 64)))
    while processed < limit and shared.cursor < shared.cycleCount do
        -- Four entries are the bounded forward-progress floor used throughout
        -- the sliced perception/topology jobs. The wall-clock deadline is
        -- checked after that floor and after every subsequent native read.
        if deadline and processed >= 4 and clock() >= deadline then break end
        local index = nativeIndex(shared.cursor, shared.cycleCount)
        local value, found = SC.NativeList.get(list, index)
        shared.cursor = shared.cursor + 1
        processed = processed + 1
        if found and value ~= nil and not shared.buildSeen[value] then
            shared.buildSeen[value] = true
            local x, y, z = SC.GameplayUtil.position(value)
            shared.build[#shared.build + 1] = {
                actor = value, index = index, x = x, y = y, z = z,
            }
        end
    end

    local passEnded = shared.cursor >= shared.cycleCount
    local published = false
    if passEnded then
        local coherent = #shared.build == shared.cycleCount and count == shared.cycleCount
        local verificationReady = coherent
            and shared.verificationCount == shared.cycleCount
            and type(shared.verification) == "table"
        local rosterMatches = verificationReady
            and sameRoster(shared.verification, shared.build, shared.cycleCount)
        -- A non-empty live Java list is mutable across slices. Certify absence
        -- only after two complete passes observe the same identity set. A
        -- duplicate/missing index or a changed count invalidates verification,
        -- but the just-read build remains available as best-effort preview.
        if shared.cycleCount == 0 and count == 0 then
            published = true
        elseif rosterMatches then
            published = true
        elseif coherent then
            if verificationReady then
                -- A same-sized native list can still have changed identities
                -- between slices. Once a complete pass disagrees with its
                -- verification pass, the previously published negative proof
                -- is no longer safe even though the Java list count is equal.
                invalidateEvidence(shared, now)
                shared.rejectedCycles = (shared.rejectedCycles or 0) + 1
            end
            shared.verification = shared.build
            shared.verificationCount = shared.cycleCount
        else
            invalidateEvidence(shared, now)
            shared.verification, shared.verificationCount = nil, nil
            shared.rejectedCycles = (shared.rejectedCycles or 0) + 1
        end
        if published then
            shared.published = shared.build
            shared.publishedCount = shared.cycleCount
            shared.completedCycle = shared.cycle
            shared.completedAt = now
            shared.evidenceValid = true
            shared.evidenceCount = count
            shared.evidenceInvalidatedAt = nil
            shared.verification, shared.verificationCount = nil, nil
        end
        nativeGeneration = nativeGeneration + 1
        shared.cycle = nativeGeneration
        shared.build = {}
        shared.buildSeen = {}
        shared.cursor = 0
        shared.cycleCount = count
    end
    local interval = published
        and math.max(250, tonumber(SC.GameplayUtil.config(
            "perceptionNativeCompletedHoldMs")) or 1000)
        or math.max(16, tonumber(SC.GameplayUtil.config(
            "perceptionNativeSharedPulseMs")) or 50)
    shared.nextAdvanceAt = now + interval
    return processed, false, published
end

local function resetActorNativeState(state, generation)
    state.nativeSharedGeneration = generation
    state.nativeRosterCycle = nil
    state.nativeRosterSource = nil
    state.nativeRosterCount = nil
    state.nativeRosterFlat = nil
    state.nativeRosterCursor = 1
    state.nativeRosterComplete = false
    state.nativeLastCompleteCycle = nil
    state.nativePreviewCycle = nil
    state.nativePreviewCursor = 1
    state.nativeDeliveredCycle = nil
    state.nativeDeliveredSeen = nil
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
    clock = type(clock) == "function" and clock or U.nowMs
    local now = clock()
    local shared, processed, reused, globalCompleted = nativeBulkSnapshot(now, clock)
    local list, count
    if shared ~= nil then
        list, count = shared.list, shared.liveCount
    else
        local available
        list, available = U.call(U.cell(), "getZombieList")
        if not available or list == nil or not SC.NativeList then return nil end
        count = SC.NativeList.size(list)
        processed, reused, globalCompleted = advanceSharedNative(
            list, count, maximum, deadline, clock, now)
        shared = sharedNative
    end
    local x, y, z = U.position(actor)
    if x == nil then return {}, { processed = 0, complete = true, count = count } end
    if state.nativeSharedGeneration ~= shared.generation then
        resetActorNativeState(state, shared.generation)
    elseif state.nativeScanCount ~= nil and state.nativeScanCount ~= count then
        -- A stable list object may change size between observer pulses. Its old
        -- roster cursor and delivered set describe a different population and
        -- can otherwise collide with the producer's monotonically reused cycle
        -- number, skipping the first entries of the replacement roster.
        resetActorNativeState(state, shared.generation)
    end
    if count == 0 then
        -- An empty live list is authoritative absence. Do not make observers
        -- drain a previously published populated roster before accepting it.
        state.nativeRosterCycle = shared.completedCycle > 0 and shared.completedCycle or nil
        state.nativeRosterSource = shared.published
        state.nativeRosterCount = 0
        state.nativeRosterFlat = shared.publishedFlat == true
        state.nativeRosterCursor = 1
        state.nativeRosterComplete = shared.completedCycle > 0
        state.nativeLastCompleteCycle = state.nativeRosterCycle
        state.nativeCandidateQueue, state.nativeCandidateIndex = nil, nil
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
    if count > 0 and shared.completedCycle > 0
        and state.nativeRosterCycle ~= shared.completedCycle
        and (state.nativeRosterCycle == nil or state.nativeRosterComplete == true) then
        local previewMatches = state.nativeDeliveredCycle == shared.completedCycle
        state.nativeRosterCycle = shared.completedCycle
        state.nativeRosterSource = shared.published
        state.nativeRosterCount = shared.publishedCount
        state.nativeRosterFlat = shared.publishedFlat == true
        state.nativeRosterCursor = 1
        state.nativeRosterComplete = false
        if not previewMatches then
            state.nativeDeliveredCycle = shared.completedCycle
            state.nativeDeliveredSeen = {}
            state.nativeCandidateQueue, state.nativeCandidateIndex = {}, 1
            queue = state.nativeCandidateQueue
        end
    end

    -- Once adopted, this observer owns an immutable roster reference.  The
    -- producer may publish several newer cycles while a slow observer drains
    -- it; that must not invalidate the observer's cursor or queued tail.
    local coherent = count > 0 and state.nativeRosterComplete ~= true
        and tonumber(state.nativeRosterCycle) ~= nil
        and type(state.nativeRosterSource) == "table"
    local source, sourceCount, sourceFlat, cursor
    if coherent then
        -- Keep the exact completed roster alive while this observer drains it;
        -- another global cycle may finish meanwhile without invalidating the
        -- completion proof or dropping a queued tail.
        source = state.nativeRosterSource
        sourceCount = tonumber(state.nativeRosterCount) or #source
        sourceFlat = state.nativeRosterFlat == true
        cursor = math.max(1, math.floor(tonumber(state.nativeRosterCursor) or 1))
    else
        if state.nativePreviewCycle ~= shared.cycle then
            state.nativePreviewCycle = shared.cycle
            state.nativePreviewCursor = 1
            state.nativeDeliveredCycle = shared.cycle
            state.nativeDeliveredSeen = {}
        end
        -- The first coherent pass is useful for threat discovery immediately,
        -- even though absence is not certified until the matching second pass.
        -- Its cycle number is the one now being verified, allowing the observer
        -- queue to carry over when that second pass publishes the same roster.
        source = count == 0 and {} or shared.verification or shared.build
        sourceCount = #source
        sourceFlat = false
        cursor = math.max(1, math.floor(tonumber(state.nativePreviewCursor) or 1))
    end

    local radiusSq = math.max(1, tonumber(radius) or 24) ^ 2
    local queued = setmetatable({}, { __mode = "k" })
    for _, value in ipairs(queue) do queued[value] = true end
    local additions, distances = {}, setmetatable({}, { __mode = "k" })
    local inspected = 0
    while cursor <= sourceCount and inspected < queryLimit
        and #queue + #additions < queueCap do
        if deadline and inspected >= 4 and clock() >= deadline then break end
        local entry = sourceFlat and nil or source[cursor]
        local flatBase = sourceFlat and ((cursor - 1) * 4 + 1) or nil
        local value = sourceFlat and source[flatBase]
            or type(entry) == "table" and entry.actor or entry
        cursor = cursor + 1
        inspected = inspected + 1
        if value ~= nil and not queued[value]
            and not (state.nativeDeliveredSeen and state.nativeDeliveredSeen[value]) then
            local zx = sourceFlat and tonumber(source[flatBase + 1])
                or type(entry) == "table" and entry.x or nil
            local zy = sourceFlat and tonumber(source[flatBase + 2])
                or type(entry) == "table" and entry.y or nil
            local zz = sourceFlat and tonumber(source[flatBase + 3])
                or type(entry) == "table" and entry.z or nil
            if zx == nil then zx, zy, zz = U.position(value) end
            if zx and math.floor(zz or 0) == math.floor(z or 0) then
                local dx, dy = zx - x, zy - y
                local distanceSq = dx * dx + dy * dy
                if distanceSq <= radiusSq then
                    queued[value] = true
                    additions[#additions + 1] = value
                    distances[value] = {
                        distanceSq = distanceSq,
                        index = sourceFlat and (cursor - 1)
                            or type(entry) == "table" and entry.index or cursor,
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
        state.nativeDeliveredSeen = state.nativeDeliveredSeen or {}
        state.nativeDeliveredSeen[queue[queueIndex]] = true
        queueIndex = queueIndex + 1
    end
    state.nativeCandidateQueue, state.nativeCandidateIndex = queue, queueIndex
    local queuePending = math.max(0, #queue - queueIndex + 1)
    if coherent and cursor > sourceCount and queuePending == 0 then
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
        and shared.evidenceValid == true
        and shared.evidenceCount == count
    local sourceRemaining = coherent and math.max(0, sourceCount - cursor + 1) or 0
    local pending = queuePending + sourceRemaining
    local reportedCursor = count == 0 and 0
        or complete and (state.nativeRosterCount or #state.nativeRosterSource)
        or shared.cursor
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
        sourceCount = count == 0 and 0
            or complete and (state.nativeRosterCount or #state.nativeRosterSource)
            or shared.cycleCount,
        cursor = reportedCursor,
        globalCursor = shared.cursor,
        evaluated = #result,
        inspected = inspected,
        pending = pending,
        previewPending = coherent and 0 or math.max(0, sourceCount - cursor + 1),
        listComplete = complete,
        endReached = complete or shared.completedCycle > 0,
        globalCompleted = globalCompleted,
        evidenceValid = shared.evidenceValid == true,
        evidenceCount = shared.evidenceCount,
        evidenceInvalidatedAt = shared.evidenceInvalidatedAt,
        rejectedCycles = shared.rejectedCycles or 0,
        verificationPending = shared.verification ~= nil,
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
    nativeSnapshotShared = nil
    nativeSnapshotScratch = {}
    nativeSnapshotRetryAt = 0
    nativeSnapshotEpoch = nativeSnapshotEpoch + 1
    -- Do not reuse an epoch: actor runtimes can outlive a global world/reset
    -- pulse and must discard any cursor that belonged to the old roster.
    nativeGeneration = nativeGeneration + 1
end

return Scan
