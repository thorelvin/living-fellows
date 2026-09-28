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
        local sx, sy, street = item:match("^([^,]+),([^,]+),(.*)$")
        local x, y = tonumber(sx), tonumber(sy)
        if not x or not y or x ~= x or y ~= y
            or x < 0 or y < 0 or x > 30000 or y > 30000
            or not street or #street > 128 then return nil end
        points[#points + 1] = { x = x, y = y, street = street }
        if #points > 512 then return nil end
    end
    return #points >= 2 and points or nil
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
function Route.visibleHorde(route, actor, snapshot, livingCount, now)
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
    if #seen <= livingCount * 3 then return nil end
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
            if #nearby > livingCount * 3
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
function Route.target(route, actor)
    if type(route) ~= "table" or type(route.points) ~= "table"
        or type(route.index) ~= "number" then return nil end
    local x, y = SC.GameplayUtil.position(actor)
    if x == nil or y == nil then return nil end
    while route.index <= #route.points
        and distance(x, y, route.points[route.index]) <= 4 do
        route.index = route.index + 1
    end
    local point = route.points[route.index]
    if point then
        return { x = math.floor(point.x + 0.5),
            y = math.floor(point.y + 0.5), z = 0 }
    end
    return route.goal
end

function Route.verifyEntry(route, actor)
    if type(route) ~= "table" or type(route.points) ~= "table"
        or actor == nil then return false, "NO_ENTRY_CANDIDATE" end
    local entry = route.points[1]
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
    for _, square in ipairs(path) do
        local x, y = SC.GameplayUtil.position(square)
        if x == nil or y == nil
            or segmentDistance(x, y, first, last) > 12 then
            return false
        end
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
