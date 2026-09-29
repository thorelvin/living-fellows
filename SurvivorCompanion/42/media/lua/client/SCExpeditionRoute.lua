-- SPDX-License-Identifier: MIT
-- Map streets guide the next loaded leg; Navigation alone moves the actor.
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.ExpeditionRoute = SC.ExpeditionRoute or {}
local Route = SC.ExpeditionRoute

local function distance(x, y, point)
    return math.sqrt((x - point.x)^2 + (y - point.y)^2)
end

local function parseGeometry(value)
    if type(value) ~= "string" or #value > 65536 then return nil end
    local points = {}
    for item in string.gmatch(value, "[^;]+") do
        local sx, sy, widthText, junctionText, street =
            item:match("^([^,]+),([^,]+),([^,]+),([^,]+),(.*)$")
        if sx == nil then
            sx, sy, street = item:match("^([^,]+),([^,]+),(.*)$")
        end
        local x, y = tonumber(sx), tonumber(sy)
        local width = widthText and tonumber(widthText) or 0
        if not x or not y or x ~= x or y ~= y
            or x < 0 or y < 0 or x > 30000 or y > 30000
            or not width or width ~= width or width < 0 or width > 64
            or (junctionText ~= nil and junctionText ~= "0"
                and junctionText ~= "1")
            or not street or #street > 128 then return nil end
        points[#points + 1] = { x = x, y = y, street = street,
            width = width, junction = junctionText == "1" }
        if #points > 512 then return nil end
    end
    if #points < 2 then return nil end
    -- Break a long mapped street into bounded lane runs. Original junctions
    -- remain explicit centerline points; inserted anchors are ordinary road.
    local expanded = { points[1] }
    for index = 2, #points do
        local first, last = points[index - 1], points[index]
        local dx, dy = last.x - first.x, last.y - first.y
        local length = math.sqrt(dx * dx + dy * dy)
        if last.width >= 6 and length > 48 then
            local runs = math.ceil(length / 36)
            if #expanded + runs + (#points - index) <= 512 then
                for part = 1, runs - 1 do
                    local t = part / runs
                    expanded[#expanded + 1] = {
                        x = first.x + dx * t, y = first.y + dy * t,
                        street = last.street, width = last.width,
                        junction = false,
                    }
                end
            end
        end
        expanded[#expanded + 1] = last
    end
    return expanded
end

local function segmentDistance(x, y, first, last)
    local dx, dy = last.x - first.x, last.y - first.y
    local lengthSq = dx * dx + dy * dy
    local t = lengthSq > 0 and math.max(0, math.min(1,
        ((x - first.x) * dx + (y - first.y) * dy) / lengthSq)) or 0
    return math.sqrt((x - first.x - t * dx)^2
        + (y - first.y - t * dy)^2)
end

local function validAvoidance(value)
    return type(value) == "table"
        and type(value.x) == "number" and value.x == value.x
        and type(value.y) == "number" and value.y == value.y
        and type(value.radius) == "number" and value.radius == value.radius
        and value.x >= 0 and value.x <= 30000
        and value.y >= 0 and value.y <= 30000
        and value.radius >= 4 and value.radius <= 32
end

function Route.enabled()
    return SC.Config and SC.Config.get("expeditionRoadRoutingEnabled") == true
end

-- This is called only for review/dispatch and return replanning, never from a
-- frame tick. The native router returns a bounded geometry and explicit status.
function Route.plan(actor, target, continuingMission, avoidance)
    if not Route.enabled() and continuingMission ~= true then
        return nil, "road_routing_unavailable"
    end
    if actor == nil or type(target) ~= "table" or target.z ~= 0 then
        return nil, "invalid_road_target"
    end
    local x, y, z = SC.GameplayUtil.position(actor)
    if x == nil or y == nil or z ~= 0 then
        return nil, "road_source_unavailable"
    end
    local api = SC.Factions and SC.Factions.streetDataApi
        and SC.Factions.streetDataApi() or nil
    if api == nil then return nil, "DATA_NOT_READY" end
    local bridge = type(_G) == "table" and rawget(_G, "SCBridge") or nil
    if bridge == nil or SC.Call == nil then
        return nil, "road_bridge_unavailable"
    end
    if avoidance ~= nil and not validAvoidance(avoidance) then
        return nil, "invalid_road_avoidance"
    end
    local result = {}
    local called, accepted
    if avoidance ~= nil then
        called, accepted = SC.Call.static(bridge,
            "planRoadRouteAvoiding", api, x, y, target.x, target.y,
            avoidance.x, avoidance.y, avoidance.radius, result)
    else
        called, accepted = SC.Call.static(bridge, "planRoadRoute", api,
            x, y, target.x, target.y, result)
    end
    if not called or accepted ~= true then
        return nil, "road_bridge_failed"
    end
    if result.status ~= "READY" then
        return nil, result.status or "road_plan_failed", result
    end
    local points = parseGeometry(result.geometry)
    if not points then return nil, "road_geometry_invalid", result end
    local fingerprint = result.fingerprint
    if type(fingerprint) ~= "string" or #fingerprint > 32 then
        return nil, "road_fingerprint_invalid", result
    end
    return {
        points = points, index = 1, fingerprint = fingerprint,
        roadLength = tonumber(result.roadLength) or 0,
        inferredJunctions = tonumber(result.inferredJunctions) or 0,
        elapsedMs = tonumber(result.elapsedMs) or 0,
        goal = { x = target.x, y = target.y, z = target.z },
        avoidance = avoidance and { x = avoidance.x, y = avoidance.y,
            radius = avoidance.radius } or nil,
    }, nil, result
end

-- Use the leader's fresh visual contacts. A horde elsewhere in sight need not
-- divert a road journey; one contact must be near the road section ahead.
function Route.visibleHorde(route, actor, snapshot, livingCount, now, maxThreats)
    if type(route) ~= "table" or type(route.points) ~= "table"
        or type(route.index) ~= "number" or route.index > #route.points
        or type(snapshot) ~= "table" or snapshot.valid ~= true
        or type(snapshot.threats) ~= "table"
        or type(livingCount) ~= "number" or livingCount < 1
        or type(now) ~= "number"
        or type(snapshot.reflexTime) ~= "number"
        or now - snapshot.reflexTime < 0
        or now - snapshot.reflexTime > 2000 then return nil end
    local first = route.points[math.max(1, route.index - 1)]
    local last = route.points[route.index]
    if route.index <= 1 then
        local x, y = SC.GameplayUtil.position(actor)
        if x == nil or y == nil then return nil end
        first = { x = x, y = y }
    end
    if first == nil or last == nil then return nil end
    local seen = {}
    for _, threat in ipairs(snapshot.threats) do
        if threat.visible == true and threat.obstructed ~= true
            and type(threat.x) == "number" and type(threat.y) == "number"
            and threat.x == threat.x and threat.y == threat.y
            and threat.x >= 0 and threat.x <= 30000
            and threat.y >= 0 and threat.y <= 30000 then
            seen[#seen + 1] = threat
        end
    end
    local threshold = tonumber(maxThreats) or livingCount * 3
    if #seen <= threshold then return nil end
    local cluster, bestGap
    -- A lone zombie beside the road must not mask a larger group a little
    -- farther along it. Test each road-near contact as a possible group center.
    for _, center in ipairs(seen) do
        local gap = segmentDistance(center.x, center.y, first, last)
        if gap <= 18 then
            local nearby = {}
            for _, threat in ipairs(seen) do
                if math.sqrt((threat.x - center.x)^2
                        + (threat.y - center.y)^2) <= 18 then
                    nearby[#nearby + 1] = threat
                end
            end
            if #nearby > threshold
                and (bestGap == nil or gap < bestGap) then
                cluster, bestGap = nearby, gap
            end
        end
    end
    -- The threshold belongs to the group on this road, not to unrelated
    -- contacts elsewhere in the leader's visual range.
    if cluster == nil then return nil end
    local x, y = 0, 0
    for _, threat in ipairs(cluster) do
        x, y = x + threat.x, y + threat.y
    end
    x, y = x / #cluster, y / #cluster
    local radius = 8
    for _, threat in ipairs(cluster) do
        radius = math.max(radius, math.sqrt((threat.x - x)^2
            + (threat.y - y)^2) + 5)
    end
    return { x = x, y = y, radius = math.min(24, radius),
        seen = #cluster }
end

-- Advance only when the leader reaches a street vertex. A source/exit access
-- leg may leave the street, but ordinary road legs aim at the next vertex.
function Route.target(route, actor, snapshot)
    if type(route) ~= "table" or type(route.points) ~= "table"
        or type(route.index) ~= "number" then return nil end
    local x, y = SC.GameplayUtil.position(actor)
    if x == nil or y == nil then return nil end
    while route.index <= #route.points
        and distance(x, y, route.points[route.index]) <= 4 do
        local reached = route.points[route.index]
        if reached.junction == true then
            local nextPoint = route.points[route.index + 1]
            route.passedJunction = {
                x = reached.x, y = reached.y, z = 0,
                street = nextPoint and nextPoint.street ~= ""
                    and nextPoint.street or reached.street,
            }
        end
        route.index = route.index + 1
        route.laneStage = nil
        route.laneIndex = nil
    end
    local point = route.points[route.index]
    if point then
        local previous = route.points[route.index - 1]
        if previous and (point.width or 0) >= 6 then
            local dx, dy = point.x - previous.x, point.y - previous.y
            local length = math.sqrt(dx * dx + dy * dy)
            if length >= 24 then
                route.laneChoices = route.laneChoices or {}
                if route.laneChoices[route.index] == nil then
                    route.laneChoices[route.index] =
                        type(ZombRand) == "function" and ZombRand(3) - 1
                        or math.random(3) - 2
                end
                local side = route.laneChoices[route.index]
                if side ~= 0 then
                    if route.laneIndex ~= route.index then
                        route.laneIndex, route.laneStage = route.index, 1
                    end
                    local offset = side * math.min(2.75,
                        point.width * 0.28, point.width * 0.5 - 1.25)
                    while route.laneStage <= 2 do
                        local fraction = route.laneStage == 1 and 0.22 or 0.78
                        local lane = {
                            x = previous.x + dx * fraction - dy / length * offset,
                            y = previous.y + dy * fraction + dx / length * offset,
                        }
                        local center = {
                            x = previous.x + dx * fraction,
                            y = previous.y + dy * fraction,
                        }
                        local towardThreat = false
                        for _, threat in ipairs(type(snapshot) == "table"
                                and snapshot.threats or {}) do
                            if threat.visible == true and threat.obstructed ~= true
                                and type(threat.x) == "number"
                                and type(threat.y) == "number"
                                and distance(lane.x, lane.y, threat) < 12
                                and distance(lane.x, lane.y, threat)
                                    < distance(center.x, center.y, threat) then
                                towardThreat = true
                                break
                            end
                        end
                        if towardThreat then
                            route.laneStage = 3
                            break
                        end
                        local lx, ly = math.floor(lane.x + 0.5),
                            math.floor(lane.y + 0.5)
                        local world = type(getWorld) == "function" and getWorld() or nil
                        local cell = world and world:getCell() or nil
                        local square = cell and cell:getGridSquare(lx, ly, 0) or nil
                        if distance(x, y, lane) > 2.5 and (square == nil
                            or SC.GameplayUtil.isSquareFree(square)) then
                            return { x = lx, y = ly, z = 0 }
                        end
                        route.laneStage = route.laneStage + 1
                    end
                end
            end
        end
        return { x = math.floor(point.x + 0.5),
            y = math.floor(point.y + 0.5), z = 0 }
    end
    return route.goal
end

function Route.skipLane(route)
    if type(route) ~= "table" or route.laneIndex ~= route.index
        or route.laneStage == nil or route.laneStage > 2 then return false end
    route.laneStage = 3
    return true
end

function Route.takeJunction(route)
    if type(route) ~= "table" then return nil end
    local crossed = route.passedJunction
    route.passedJunction = nil
    return crossed
end

function Route.formationSegment(route, actor)
    if type(route) ~= "table" or type(route.index) ~= "number"
        or type(route.points) ~= "table" or actor == nil then return nil end
    local first, last = route.points[route.index - 1],
        route.points[route.index]
    if not first or not last or (last.width or 0) < 6 then return nil end
    local dx, dy = last.x - first.x, last.y - first.y
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 14 then return nil end
    local x, y = SC.GameplayUtil.position(actor)
    if x == nil or y == nil
        or segmentDistance(x, y, first, last) > last.width * 0.5 then
        return nil
    end
    local along = ((x - first.x) * dx + (y - first.y) * dy) / length
    if along < 5 or along > length - 5 then return nil end
    return { first = first, last = last, width = last.width,
        forwardX = dx / length, forwardY = dy / length }
end

-- A nearby road entry must have a loaded local path before the squad leaves.
-- A distant one (the native router allows up to 100 tiles off-road) cannot be
-- streamed yet; the leader walks it in loaded local legs like the final
-- approach, and each leg is still checked against any avoided horde.
local LOCAL_ENTRY_CHECK = 45

function Route.verifyEntry(route, actor)
    if type(route) ~= "table" or type(route.points) ~= "table"
        or actor == nil then return false, "NO_ENTRY_CANDIDATE" end
    local entry = route.points[1]
    local ax, ay = SC.GameplayUtil.position(actor)
    if ax ~= nil and ay ~= nil and entry ~= nil
        and distance(ax, ay, entry) > LOCAL_ENTRY_CHECK then
        return true
    end
    local world = type(getWorld) == "function" and getWorld() or nil
    local cell = world and world:getCell() or nil
    local source = actor:getCurrentSquare()
    local destination = cell and cell:getGridSquare(
        math.floor(entry.x + 0.5), math.floor(entry.y + 0.5), 0) or nil
    if source == nil or destination == nil
        or SC.Navigation == nil or SC.Navigation.findPath == nil
        or not SC.GameplayUtil.isSquareFree(destination) then
        return false, "NO_ENTRY_CANDIDATE"
    end
    local path = SC.Navigation.findPath(source, destination,
        { actor = actor, nodeBudget = 2500 })
    if path == nil or #path < 1 or #path > 100 then
        return false, "NO_ENTRY_CANDIDATE"
    end
    if route.avoidance ~= nil then
        for _, square in ipairs(path) do
            local x, y = SC.GameplayUtil.position(square)
            if x == nil or y == nil
                or distance(x, y, route.avoidance)
                    <= route.avoidance.radius + 2 then
                return false, "LOCAL_ACCESS_BLOCKED"
            end
        end
    end
    return true
end

function Route.withinCorridor(route, path)
    if type(route) ~= "table" or type(path) ~= "table" then return false end
    local index, points = route.index, route.points
    if route.avoidance ~= nil then
        for _, square in ipairs(path) do
            local x, y = SC.GameplayUtil.position(square)
            if x == nil or y == nil
                or distance(x, y, route.avoidance)
                    <= route.avoidance.radius + 2 then return false end
        end
    end
    if index <= 1 or index > #points then return true end
    local first, last = points[index - 1], points[index]
    -- Combat or a blocked verge can briefly push the leader off the mapped
    -- street. Let a verified exterior path curve back toward it; the ordinary
    -- road corridor resumes as soon as the leader is near the centerline.
    local startX, startY = SC.GameplayUtil.position(path[1])
    local startOffset = startX and startY
        and segmentDistance(startX, startY, first, last) or 0
    local reentryWidth = startX and startY and math.min(24,
        math.max(12, startOffset + 8)) or 12
    for _, square in ipairs(path) do
        local x, y = SC.GameplayUtil.position(square)
        if x == nil or y == nil
            or segmentDistance(x, y, first, last) > reentryWidth then
            return false
        end
    end
    if startOffset > 12 then
        local endX, endY = SC.GameplayUtil.position(path[#path])
        if not endX or not endY or segmentDistance(endX, endY,
                first, last) >= startOffset - 1 then return false end
    end
    return true
end

-- Only the access legs may enter a building. Search expeditions must not use
-- their broader site-access permission while traversing intermediate roads.
function Route.allowInteriorAccess(route, kind, phase, leaderInRoom)
    if route == nil then
        return phase == "inbound"
            or kind == "search" and phase == "outbound"
    end
    if type(route.points) ~= "table" or type(route.index) ~= "number" then
        return false
    end
    if route.index <= 1 then
        return leaderInRoom == true
    end
    if route.index > #route.points then
        return true
    end
    return phase == "inbound" and leaderInRoom == true
end

function Route.descriptor(route, phase)
    if type(route) ~= "table" then return nil end
    return { version = 1, phase = phase,
        fingerprint = route.fingerprint, goal = route.goal,
        avoidance = route.avoidance }
end

function Route.validDescriptor(value)
    local function tile(number)
        return type(number) == "number" and number == number
            and number >= 0 and number <= 30000
            and number == math.floor(number)
    end
    return type(value) == "table" and value.version == 1
        and (value.phase == "outbound" or value.phase == "inbound")
        and type(value.fingerprint) == "string"
        and #value.fingerprint > 0 and #value.fingerprint <= 32
        and type(value.goal) == "table"
        and tile(value.goal.x) and tile(value.goal.y)
        and value.goal.z == 0
        and (value.avoidance == nil or validAvoidance(value.avoidance))
end

return Route
