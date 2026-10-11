-- SPDX-License-Identifier: MIT
-- Companion driving at low speed. The native bridge presses the car's own
-- pedals and wheel every frame (SCCompanionDriver) and stops for anything its
-- lane scan finds ahead. SCVehicle owns getting in and out of the seat. Nothing
-- calls this module on its own yet: it is the base the driving systems build on.
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.Driving = SC.Driving or {}
local Driving = SC.Driving

local function bridge()
    local api = type(_G) == "table" and rawget(_G, "SCBridge") or nil
    if api == nil or SC.Call == nil then return nil end
    return api
end

local function lastFailure(api, fallback)
    local ok, reason = SC.Call.static(api, "getLastFailure")
    if ok and type(reason) == "string" and reason ~= "" then return reason end
    return tostring(fallback or "native driving call failed")
end

local function call(name, ...)
    local api = bridge()
    if api == nil then return false, "driving bridge is unavailable" end
    local ok, accepted = SC.Call.static(api, name, ...)
    if not ok then return false, tostring(accepted) end
    if accepted ~= true then return false, lastFailure(api) end
    return true
end

local function method(object, name, ...)
    if object == nil then return false, nil end
    return SC.Call.method(object, name, ...)
end

local function vehicleOf(actor)
    local ok, vehicle = method(actor, "getVehicle")
    return ok and vehicle or nil
end

function Driving.available()
    local api = bridge()
    if api == nil then return false end
    for _, name in ipairs({ "driveStart", "driveSet", "driveStop", "driveStatus", "scanLane",
        "driveFollow", "driveTurnAround" }) do
        local ok, callback = pcall(function() return api[name] end)
        if not ok or callback == nil then return false end
    end
    return true
end

-- True when the companion sits in seat zero of its car.
function Driving.isDriver(actor)
    local vehicle = vehicleOf(actor)
    if vehicle == nil then return false end
    local ok, driver = method(vehicle, "getDriver")
    return ok and driver == actor
end

-- The companion carries this car's key. Without one the car starts only when
-- it is hot-wired, has keys in the ignition, or the sandbox allows easy use.
function Driving.hasKey(actor, vehicle)
    vehicle = vehicle or vehicleOf(actor)
    local keyOk, keyId = method(vehicle, "getKeyId")
    local inventoryOk, inventory = method(actor, "getInventory")
    if not keyOk or not inventoryOk or inventory == nil or type(keyId) ~= "number" then
        return false
    end
    local found, item = method(inventory, "haveThisKeyId", keyId)
    return found and item ~= nil
end

-- Gets into the driver's seat through SCVehicle's verified boarding.
function Driving.takeWheel(actor, vehicle, intent)
    if SC.Vehicle == nil or type(SC.Vehicle.boardDriver) ~= "function" then
        return false, "vehicle boarding is unavailable"
    end
    return SC.Vehicle.boardDriver(actor, vehicle, intent)
end

-- Puts the seated driver under bridge control, held still.
function Driving.start(actor)
    if not Driving.isDriver(actor) then return false, "companion is not in the driver's seat" end
    return call("driveStart", actor, Driving.hasKey(actor) == true)
end

-- Cruise at a low speed (km/h, capped natively) with steering in [-1, 1],
-- where -1 is the player's left key. Obstacle braking stays on unless the
-- caller passes false.
function Driving.cruise(actor, kmh, steering, brakeForObstacles)
    local speed = tonumber(kmh) or 0
    local steer = tonumber(steering) or 0
    return call("driveSet", actor, steer, speed, brakeForObstacles ~= false)
end

function Driving.hold(actor)
    return call("driveSet", actor, 0, 0, true)
end

-- Lets go of the wheel and parks. Safe when not driving.
function Driving.release(actor)
    return call("driveStop", actor)
end

-- The expedition road planner's route from where the car stands to a target.
function Driving.planRoute(actor, target)
    if SC.ExpeditionRoute == nil or type(SC.ExpeditionRoute.plan) ~= "function" then
        return nil, "road planner is unavailable"
    end
    return SC.ExpeditionRoute.plan(actor, target, true)
end

-- The bridge's route text, "x,y,width;...", from route points. Bounded.
function Driving.routeText(points)
    if type(points) ~= "table" then return nil, "route has no points" end
    local parts = {}
    for index, point in ipairs(points) do
        if index > 512 then return nil, "route has too many points" end
        local x = type(point) == "table" and tonumber(point.x) or nil
        local y = type(point) == "table" and tonumber(point.y) or nil
        if not x or not y then return nil, "route point " .. index .. " is invalid" end
        parts[#parts + 1] = string.format("%.2f,%.2f,%.1f", x, y, tonumber(point.width) or 0)
    end
    if #parts < 2 then return nil, "route has fewer than two points" end
    return table.concat(parts, ";")
end

-- Drives a route: the planner's table, or a plain list of {x, y, width}
-- points. The bridge keeps right, slides round wrecks in the lane, stops when
-- the road is blocked edge to edge, and stops at the end.
function Driving.followRoute(actor, route, kmh)
    local points = type(route) == "table" and (route.points or route) or nil
    local text, why = Driving.routeText(points)
    if not text then return false, why end
    return call("driveFollow", actor, text, tonumber(kmh) or 10)
end

-- Turns round with a three-point turn; with followBack, drives the route back.
function Driving.turnAround(actor, followBack)
    return call("driveTurnAround", actor, followBack == true)
end

function Driving.status(actor)
    local api = bridge()
    if api == nil then return nil, "driving bridge is unavailable" end
    local out = {}
    local ok, accepted = SC.Call.static(api, "driveStatus", actor, out)
    if not ok then return nil, tostring(accepted) end
    if accepted ~= true then return nil, lastFailure(api) end
    return out
end

-- One lane scan for the car the companion sits in, lookAhead tiles past the
-- front bumper. Read-only.
function Driving.scanLane(actor, lookAhead)
    local api = bridge()
    if api == nil then return nil, "driving bridge is unavailable" end
    local out = {}
    local ok, accepted = SC.Call.static(api, "scanLane", actor, tonumber(lookAhead) or 0, out)
    if not ok then return nil, tostring(accepted) end
    if accepted ~= true then return nil, lastFailure(api) end
    return out
end

return Driving
