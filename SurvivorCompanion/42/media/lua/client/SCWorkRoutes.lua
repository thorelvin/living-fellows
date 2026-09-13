-- SPDX-License-Identifier: MIT

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
if not SC.GameplayUtil and type(require) == "function" then pcall(require, "SCGameplayUtil") end
if not SC.Topology and type(require) == "function" then pcall(require, "SCTopology") end
if not SC.Performance and type(require) == "function" then pcall(require, "SCPerformance") end

SC.WorkRoutes = SC.WorkRoutes or {}
local Routes = SC.WorkRoutes
local routes = {}
local entryCount = 0
local serial = 0
local totals = {
    lookups = 0, hits = 0, misses = 0, records = 0,
    evictions = 0, invalidations = 0, repairs = 0,
}

-- These requests have fixed, non-tactical destinations. They may use the
-- proven open-line shortcut without changing stealth, escape or combat policy.
-- Only the repeated work subset is eligible for shared route memory.
local stationaryFastActions = {
    move_to_gather_item = true,
    move_to_gather_destination = true,
    move_to_base_storage = true,
    move_to_base_build = true,
    move_to_camp_storage = true,
    move_to_water_source = true,
    move_to_seat = true,
    return_to_base = true,
    base_guard_patrol = true,
}
local workRouteClasses = {
    move_to_gather_destination = "storage",
    move_to_base_storage = "storage",
    move_to_camp_storage = "storage",
    move_to_base_build = "build",
    return_to_base = "rally",
    base_guard_patrol = "patrol",
}

local function U()
    return SC.GameplayUtil
end

local function N()
    return SC.Navigation
end

function Routes.count(name, amount)
    if SC.Performance and type(SC.Performance.count) == "function" then
        SC.Performance.count(name, amount or 1)
    end
end

function Routes.stationaryFastRouteRequested(intent)
    intent = type(intent) == "table" and intent or {}
    if intent.stationaryFastRoute == false or intent.stealthAvoidance == true
        or intent.urgent == true or intent.emergency == true
        or intent.survivalCritical == true or intent.movingTarget == true
        or intent.followRecovery == true or intent.player ~= nil then return false end
    if intent.stationaryFastRoute == true then return true end
    return stationaryFastActions[tostring(intent.action or "")] == true
end

local function activeBaseRouteScope()
    local base = SC.BaseLife and type(SC.BaseLife.active) == "function"
        and SC.BaseLife.active() or nil
    return type(base) == "table" and tostring(base.id or "world") or "world"
end

function Routes.key(actor, goalSquare, intent)
    intent = type(intent) == "table" and intent or {}
    local routeClass = intent.workRouteClass
        or workRouteClasses[tostring(intent.action or "")]
    if intent.workRoute ~= true and routeClass == nil then return nil end
    if U().config("navigationWorkRouteEnabled") == false
        or not Routes.stationaryFastRouteRequested(intent)
        or not U().isCompanion(actor) then return nil end
    local goalKey = U().squareKey(goalSquare)
    if goalKey == nil then return nil end
    return activeBaseRouteScope() .. "|" .. tostring(routeClass or "work")
        .. "|" .. (intent.workCampOnly == true and "camp" or "normal")
        .. "|" .. goalKey
end

local function pointCount(points)
    return type(points) == "table" and math.floor(#points / 3) or 0
end

local function point(points, index)
    local offset = (index - 1) * 3
    return points[offset + 1], points[offset + 2], points[offset + 3]
end

local function pointKey(x, y, z)
    if x == nil or y == nil then return nil end
    return tostring(math.floor(x)) .. ":" .. tostring(math.floor(y))
        .. ":" .. tostring(math.floor(z or 0))
end

local function coordinates(path, maximum)
    if type(path) ~= "table" or #path < 3 or #path > maximum then return nil end
    local points, previous = {}, nil
    for _, square in ipairs(path) do
        local x, y, z = U().position(square)
        if x == nil then return nil end
        x, y, z = math.floor(x), math.floor(y), math.floor(z or 0)
        local key = pointKey(x, y, z)
        if key ~= previous then
            points[#points + 1], points[#points + 2], points[#points + 3] = x, y, z
            previous = key
        end
    end
    if pointCount(points) < 3 then return nil end
    return points
end

local function removeEntry(entry, evicted)
    local bucket = entry and routes[entry.bucketKey] or nil
    if not bucket then return false end
    for index, candidate in ipairs(bucket) do
        if candidate == entry then
            table.remove(bucket, index)
            entryCount = math.max(0, entryCount - 1)
            if #bucket == 0 then routes[entry.bucketKey] = nil end
            if evicted then
                totals.evictions = totals.evictions + 1
                Routes.count("navigation.work-route.evictions")
            end
            return true
        end
    end
    return false
end

local function enforceLimit()
    local maximum = math.max(1, math.floor(tonumber(
        U().config("navigationWorkRouteMaximum")) or 32))
    while entryCount > maximum do
        local oldest = nil
        for _, bucket in pairs(routes) do
            for _, entry in ipairs(bucket) do
                if oldest == nil or (tonumber(entry.lastUsedAt) or 0)
                    < (tonumber(oldest.lastUsedAt) or 0) then oldest = entry end
            end
        end
        if oldest == nil or not removeEntry(oldest, true) then break end
    end
end

function Routes.record(key, path, now)
    if key == nil then return false end
    local maximumSquares = math.max(3, math.floor(tonumber(
        U().config("navigationWorkRouteMaximumSquares")) or 192))
    local points = coordinates(path, maximumSquares)
    if points == nil then return false end
    local firstX, firstY, firstZ = point(points, 1)
    local startKey = pointKey(firstX, firstY, firstZ)
    local bucket = routes[key]
    if bucket == nil then bucket = {} routes[key] = bucket end
    local entry = nil
    for _, candidate in ipairs(bucket) do
        if candidate.startKey == startKey then entry = candidate break end
    end
    if entry == nil then
        local variants = math.max(1, math.floor(tonumber(
            U().config("navigationWorkRouteVariants")) or 3))
        if #bucket >= variants then
            local oldest = bucket[1]
            for index = 2, #bucket do
                if (tonumber(bucket[index].lastUsedAt) or 0)
                    < (tonumber(oldest.lastUsedAt) or 0) then oldest = bucket[index] end
            end
            removeEntry(oldest, true)
            bucket = routes[key]
            if bucket == nil then bucket = {} routes[key] = bucket end
        end
        serial = serial + 1
        entry = { serial = serial, bucketKey = key }
        bucket[#bucket + 1] = entry
        entryCount = entryCount + 1
    end
    entry.points = points
    entry.startKey = startKey
    local goalX, goalY, goalZ = point(points, pointCount(points))
    entry.goalKey = pointKey(goalX, goalY, goalZ)
    entry.lastUsedAt = now
    entry.recordedAt = now
    entry.retryAt = nil
    entry.failures = 0
    entry.successes = (tonumber(entry.successes) or 0) + 1
    totals.records = totals.records + 1
    Routes.count("navigation.work-route.records")
    enforceLimit()
    return true
end

function Routes.invalidate(entry, now, reason)
    if type(entry) ~= "table" then return end
    entry.failures = (tonumber(entry.failures) or 0) + 1
    entry.lastFailure = tostring(reason or "route_changed")
    entry.retryAt = now + (U().config("navigationWorkRouteRetryMs") or 1500)
    totals.invalidations = totals.invalidations + 1
    Routes.count("navigation.work-route.invalidations")
    if entry.failures >= 3 then removeEntry(entry, true) end
end

local function resolveSuffix(entry, firstIndex)
    local path = {}
    for index = firstIndex, pointCount(entry.points) do
        local x, y, z = point(entry.points, index)
        local square = U().gridSquare(x, y, z)
        if square == nil then return nil, "route_square_unloaded" end
        if path[#path] == nil or not N()._sameSquareForWorkRoutes(path[#path], square) then
            path[#path + 1] = square
        end
    end
    return path, nil
end

local function validatePrefix(path, options)
    local maximum = math.max(1, math.floor(tonumber(
        U().config("navigationWorkRouteValidationEdges")) or 4))
    for index = 2, math.min(#path, maximum + 1) do
        local fromSquare, toSquare = path[index - 1], path[index]
        if not N()._adjacentStepForWorkRoutes(fromSquare, toSquare) then
            return false, "route_gap"
        end
        if type(options.squareAdmission) == "function" then
            local observed, admitted = pcall(options.squareAdmission, toSquare, fromSquare)
            if not observed or admitted ~= true then return false, "outside_admitted_area" end
        end
        options.allowOccupiedGoal = index == #path
        local passable, _, reason = N()._passableEdgeForWorkRoutes(
            fromSquare, toSquare, options.vegetationScale, options)
        if passable ~= true then return false, reason or "route_edge_changed" end
    end
    return true
end

local function lookupWithinBatch(actor, sourceSquare, key, options, now)
    totals.lookups = totals.lookups + 1
    Routes.count("navigation.work-route.lookups")
    local bucket = routes[key]
    if bucket == nil then
        totals.misses = totals.misses + 1
        Routes.count("navigation.work-route.misses")
        return nil, nil, "route_unknown"
    end
    local sx, sy, sz = U().position(sourceSquare)
    if sx == nil then return nil, nil, "route_source_unavailable" end
    sx, sy, sz = math.floor(sx), math.floor(sy), math.floor(sz or 0)
    local ageLimit = math.max(1000, tonumber(
        U().config("navigationWorkRouteMaximumAgeMs")) or 1800000)
    local joinMaximum = math.max(0, math.floor(tonumber(
        U().config("navigationWorkRouteJoinMaximumSteps")) or 12))
    local attempts = math.max(1, math.floor(tonumber(
        U().config("navigationWorkRouteJoinCandidates")) or 2))
    local candidates, expired = {}, {}
    for _, entry in ipairs(bucket) do
        if now - (tonumber(entry.recordedAt) or now) > ageLimit then
            expired[#expired + 1] = entry
        elseif now >= (tonumber(entry.retryAt) or 0) then
            -- Keep only the best few joins per variant. Building and sorting a
            -- candidate table for every nearby point made cache lookup itself
            -- allocate heavily on long, looping routes.
            local bestIndices, bestDistances = {}, {}
            for index = 1, pointCount(entry.points) do
                local x, y, z = point(entry.points, index)
                if z == sz then
                    local distance = math.max(math.abs(x - sx), math.abs(y - sy))
                    if distance <= joinMaximum then
                        local rank = 1
                        while rank <= #bestDistances
                            and (bestDistances[rank] < distance
                                or (bestDistances[rank] == distance
                                    and bestIndices[rank] > index)) do
                            rank = rank + 1
                        end
                        if rank <= attempts then
                            table.insert(bestIndices, rank, index)
                            table.insert(bestDistances, rank, distance)
                            if #bestIndices > attempts then
                                table.remove(bestIndices)
                                table.remove(bestDistances)
                            end
                        end
                    end
                end
            end
            for rank = 1, #bestIndices do
                candidates[#candidates + 1] = {
                    entry = entry,
                    index = bestIndices[rank],
                    distance = bestDistances[rank],
                }
            end
        end
    end
    for _, entry in ipairs(expired) do removeEntry(entry, true) end
    table.sort(candidates, function(left, right)
        if left.distance ~= right.distance then return left.distance < right.distance end
        if left.index ~= right.index then return left.index > right.index end
        return left.entry.serial < right.entry.serial
    end)
    local attempted = {}
    for rank = 1, math.min(#candidates, attempts) do
        local candidate = candidates[rank]
        local entry = candidate.entry
        local signature = tostring(entry.serial) .. ":" .. tostring(candidate.index)
        if not attempted[signature] then
            attempted[signature] = true
            local suffix = resolveSuffix(entry, candidate.index)
            if suffix ~= nil and suffix[1] ~= nil then
                local joined
                if N()._sameSquareForWorkRoutes(sourceSquare, suffix[1]) then
                    joined = { sourceSquare }
                else
                    local joinOptions = U().copyShallow(options)
                    joinOptions.maximumSteps = joinMaximum
                    joined = N()._fastOpenRouteWithinBatchForWorkRoutes(
                        sourceSquare, suffix[1], joinOptions)
                end
                if joined ~= nil then
                    for index = 1, #suffix do
                        if not N()._sameSquareForWorkRoutes(joined[#joined], suffix[index]) then
                            joined[#joined + 1] = suffix[index]
                        end
                    end
                    local valid, reason = validatePrefix(joined, options)
                    if valid then
                        entry.lastUsedAt = now
                        entry.hits = (tonumber(entry.hits) or 0) + 1
                        totals.hits = totals.hits + 1
                        if candidate.index > 1 or candidate.distance > 0 then
                            totals.repairs = totals.repairs + 1
                            Routes.count("navigation.work-route.repairs")
                        end
                        Routes.count("navigation.work-route.hits")
                        return joined, entry, nil
                    end
                    entry.lastLookupFailure = reason
                end
            end
        end
    end
    totals.misses = totals.misses + 1
    Routes.count("navigation.work-route.misses")
    return nil, nil, #candidates == 0 and "route_join_unavailable"
        or "route_validation_failed"
end

function Routes.lookup(actor, sourceSquare, key, options, now)
    if SC.Topology and type(SC.Topology.withReadBatch) == "function" then
        return SC.Topology.withReadBatch(
            lookupWithinBatch, actor, sourceSquare, key, options, now)
    end
    return lookupWithinBatch(actor, sourceSquare, key, options, now)
end

function Routes.validateNext(actor, state, sourceSquare, nextSquare, goalSquare, intent, now)
    intent = type(intent) == "table" and intent or {}
    if intent.workCampOnly == true and (not SC.BaseLife
        or type(SC.BaseLife.isInside) ~= "function"
        or SC.BaseLife.isInside(nextSquare) ~= true) then
        Routes.invalidate(state.activeWorkRoute, now, "outside_admitted_area")
        return false, "outside_admitted_area"
    end
    local options = {
        actor = actor,
        blockedEdges = state.blockedEdges,
        blockedSquares = state.blockedSquares,
        routeMemory = state.routeMemory,
        now = now,
        allowHazards = false,
        allowOccupiedGoal = N()._sameSquareForWorkRoutes(nextSquare, goalSquare),
    }
    local passable, _, reason = N()._passableEdgeForWorkRoutes(
        sourceSquare, nextSquare, 1, options)
    if passable == true then return true end
    Routes.invalidate(state.activeWorkRoute, now, reason or "route_edge_changed")
    return false, reason or "route_edge_changed"
end

function Routes.noteFirstMotion(actor, state, now, strategy)
    local startedAt = tonumber(state and state.firstMotionRequestedAt)
    if startedAt == nil then return end
    local elapsed = math.max(0, now - startedAt)
    state.lastFirstMotionMs = elapsed
    state.lastFirstMotionStrategy = tostring(strategy or state.pathReason or "route")
    state.firstMotionRequestedAt = nil
    Routes.count("navigation.first-motion.count")
    if SC.Performance and type(SC.Performance.record) == "function" then
        SC.Performance.record("navigation.first-motion", nil, elapsed, 1, false)
    end
end

function Routes.snapshot()
    local buckets = 0
    for _ in pairs(routes) do buckets = buckets + 1 end
    return {
        entries = entryCount, buckets = buckets,
        lookups = totals.lookups, hits = totals.hits,
        misses = totals.misses, records = totals.records,
        evictions = totals.evictions, invalidations = totals.invalidations,
        repairs = totals.repairs,
    }
end

function Routes.reset()
    routes = {}
    entryCount = 0
    serial = 0
    totals = {
        lookups = 0, hits = 0, misses = 0, records = 0,
        evictions = 0, invalidations = 0, repairs = 0,
    }
    return true
end

return Routes
