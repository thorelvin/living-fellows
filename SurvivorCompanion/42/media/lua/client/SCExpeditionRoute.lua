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

function Route.enabled()
    return SC.Config and SC.Config.get("expeditionRoadRoutingEnabled") == true
end

-- This is called only for review/dispatch and return replanning, never from a
-- frame tick. The native router returns a bounded geometry and explicit status.
function Route.plan(actor, target, continuingMission)
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
    local result = {}
    local called, accepted = SC.Call.static(bridge, "planRoadRoute", api,
        x, y, target.x, target.y, result)
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
    }, nil, result
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
    return true
end

function Route.withinCorridor(route, path)
    if type(route) ~= "table" or type(path) ~= "table" then return false end
    local index, points = route.index, route.points
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

function Route.descriptor(route, phase)
    if type(route) ~= "table" then return nil end
    return { version = 1, phase = phase,
        fingerprint = route.fingerprint, goal = route.goal }
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
end

return Route
