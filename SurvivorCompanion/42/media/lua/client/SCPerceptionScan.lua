-- SPDX-License-Identifier: MIT

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion

SC.PerceptionScan = SC.PerceptionScan or {}
local Scan = SC.PerceptionScan
local scheduleCache = {}

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
end

return Scan
