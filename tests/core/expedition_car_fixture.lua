-- SPDX-License-Identifier: MIT
SurvivorCompanion = {}
local SC = SurvivorCompanion
CAR_TEST = { now = 0, routeCalls = {}, driveCalls = 0, zones = {},
    cars = {}, ready = true, startBlocked = false, key = true }
local T = CAR_TEST
SC.Call = { method = function(object, name, ...)
    if not object or type(object[name]) ~= "function" then return false end
    local ok, value = pcall(object[name], object, ...)
    return ok, value
end }
SC.BaseLife = {
    active = function() return { zones = T.zones } end,
    parkingZoneValid = function(zone)
        return zone.kind == "parking" and zone.z == 0
            and zone.x1 >= 90 and zone.x2 <= 120
    end,
}
SC.Registry = { idOf = function(actor) return actor.id end }
SC.Actor = { isCompanion = function(actor) return actor and actor.id ~= nil end }
SC.GameplayUtil = {
    position = function(actor) return actor.x, actor.y, actor.z end,
    nativeHealth = function() return T.health or 100 end,
    inventory = function(actor) return actor and actor.inventory end,
    inventoryItemsDeep = function(inventory) return inventory.items end,
    transferItemVerified = function(source, target, item)
        for index, value in ipairs(source.items) do
            if value == item then
                table.remove(source.items, index)
                target.items[#target.items + 1] = item
                item.container = target
                return true
            end
        end
        return false
    end,
}
SC.Vehicle = {
    loadedVehicles = function() return T.cars end,
    loadedBySqlId = function(id)
        for _, car in ipairs(T.cars) do
            if car:getSqlId() == id then return car end
        end
    end,
    isStationary = function() return T.ready end,
    boardingSquares = function(actor, _, seat)
        if T.doorBlocked == seat then
            return nil, nil, T.doorReason or "door_inaccessible"
        end
        return { { x = actor.x, y = actor.y, z = actor.z } }, seat
    end,
    isNativeSeated = function(actor)
        return actor.car ~= nil, actor.car, actor.seat
    end,
    beginBoarding = function(_, _, seat)
        return { seat = seat, supervisorToken = {} }
    end,
    preflightBoard = function(actor, car, seat)
        return { actorId = actor.id, vehicle = car, seat = seat }
    end,
    boardDriver = function(actor, car)
        actor.car, actor.seat = car, 0
        car.occupied[0] = actor
        return true
    end,
    board = function(actor, car, seat)
        actor.car, actor.seat = car, seat
        car.occupied[seat] = actor
        return true
    end,
    exit = function(actor)
        if T.exitBlocked == actor.seat then return false, "exit_blocked" end
        if actor.car then actor.car.occupied[actor.seat] = nil end
        actor.car, actor.seat = nil, nil
        return true
    end,
    recoverDriverKeyAfterExit = function() return true end,
    safeExitSquares = function(_, seat)
        if T.exitBlocked == seat then return nil, "exit_blocked" end
        return { { x = 104, y = 102, z = 0 } }
    end,
}
SC.Driving = {
    hasKey = function(actor)
        if T.key ~= nil then return T.key end
        for _, item in ipairs(actor.inventory and actor.inventory.items or {}) do
            if item:getKeyId() == 44 then return true end
        end
        return false
    end,
    drive = function(_, goal)
        if T.startBlocked then return false, "start_failed" end
        T.driveCalls = T.driveCalls + 1
        T.lastGoal = goal
        return true
    end,
    jobStatus = function() return T.driveStatus end,
    approach = function(_, goal)
        T.approaches = (T.approaches or 0) + 1
        T.approachGoal = goal
        T.driveStatus = { phase = "approaching" }
        return true
    end,
    isDriving = function() return false end,
    release = function() return true end,
}
SC.ExpeditionRoute = {
    planFromPoint = function(origin, destination)
        T.routeCalls[#T.routeCalls + 1] = { origin = origin,
            destination = destination }
        if T.routeFailure then return nil, T.routeFailure end
        return { points = { { x = origin.x, y = origin.y, street = "Road" },
                { x = destination.x, y = destination.y, street = "Road" } },
            roadLength = T.distance or 60, inferredJunctions = 0 }, nil,
            { entryX = T.entryX or 103, entryY = T.entryY or 102,
              exitX = destination.x, exitY = destination.y }
    end,
}
SC.Navigation = { requestAny = function() return true end }
SC.ExpeditionPrototype = { current = function() return T.mission end }
function getSpecificPlayer() return T.player end
local squares = {}
function getCell()
    return { getGridSquare = function(_, x, y, z)
        local key = tostring(x) .. ":" .. tostring(y) .. ":" .. tostring(z)
        if not squares[key] then
            squares[key] = {
                isSolid = function() return false end,
                isSolidTrans = function() return false end,
                getVehicleContainer = function() return nil end,
                isSomethingTo = function() return T.accessBlocked == true end,
            }
        end
        return squares[key]
    end }
end

local part = { getCondition = function() return 90 end,
    getInventoryItem = function() return {} end,
    getContainerContentAmount = function() return T.fuel or 10 end }
function T.car(id, x, y)
    local car = { id = id or 44, x = x or 102, y = y or 102,
        z = 0, occupied = {}, script = "Base.CarNormal" }
    function car:getSqlId() return self.id end
    function car:getScriptName() return self.script end
    function car:getX() return self.x end
    function car:getY() return self.y end
    function car:getZ() return self.z end
    function car:getAngleZ() return self.heading or 0 end
    function car:getMaxPassengers() return 4 end
    function car:getKeyId() return 44 end
    function car:isSeatInstalled(seat)
        return seat < (T.installedSeats or 4)
    end
    function car:getCharacter(seat) return self.occupied[seat] end
    function car:getPartById() return part end
    function car:getPoly()
        local inset = T.polyOffset or 0
        return { x1 = self.x - 1 + inset, y1 = self.y - 1,
            x2 = self.x + 1 + inset, y2 = self.y - 1,
            x3 = self.x + 1 + inset, y3 = self.y + 1,
            x4 = self.x - 1 + inset, y4 = self.y + 1 }
    end
    function car:isHotwired() return false end
    function car:isKeysInIgnition() return false end
    return car
end

T.zone = { id = "zone:42", kind = "parking", name = "Driveway",
    x1 = 100, y1 = 100, x2 = 110, y2 = 110, z = 0 }
T.zones = { { id = "zone:1", kind = "area",
    x1 = 90, y1 = 90, x2 = 110, y2 = 110, z = 0 }, T.zone }
T.cars = { T.car() }
T.team = { { id = "leader", actor = { id = "leader", x = 5, y = 5, z = 1,
    isDead = function() return false end } },
    { id = "mate", actor = { id = "mate", x = 6, y = 5, z = 1,
    isDead = function() return false end } } }
T.team[1].actor.inventory = { items = {} }
T.team[2].actor.inventory = { items = {} }
for _, member in ipairs(T.team) do
    function member.actor:getX() return self.x end
    function member.actor:getY() return self.y end
end
return T
