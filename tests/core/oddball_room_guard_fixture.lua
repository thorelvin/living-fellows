-- SPDX-License-Identifier: MIT
-- Minimal native-shaped world for SCOddballRoomGuard's Kahlua regression.

local SC = SurvivorCompanion
SC.GameplayUtil = {}
local U = SC.GameplayUtil

RoomGuardFixture = {
    squares = {}, localPlayers = {}, multiplier = 1, now = 0,
    gridReads = 0,
}
local F = RoomGuardFixture

function F.key(x, y, z)
    return tostring(x) .. ":" .. tostring(y) .. ":" .. tostring(z)
end

function F.square(x, y, z, room)
    local square = { x = x, y = y, z = z, room = room,
        objects = {}, specialObjects = {} }
    function square:getRoom() return self.room end
    function square:getObjects() return self.objects end
    function square:getSpecialObjects() return self.specialObjects end
    F.squares[F.key(x, y, z)] = square
    return square
end

function F.opening(class, square, north, kind)
    local object = { __class = class, square = square, north = north,
        kind = kind, health = 42, sprite = "untouched" }
    function object:getSquare() return self.square end
    function object:getNorth() return self.north end
    function object:isNorth() return self.north end
    function object:isDoor() return self.kind == "door" end
    function object:isWindowN() return self.kind == "windowN" end
    function object:isWindowW() return self.kind == "windowW" end
    -- Deliberately no getOppositeSquare(): B42.21 does not expose it on these.
    return object
end

function F.group(id, spawn, vestry)
    return { id = id, oddball = {
        id = vestry and "wedding_lonnie_tackett" or "window_spiffo_kevin",
        spawned = true,
        site = { kind = "resident", spawn = spawn, vestry = vestry,
            house = { bounds = { x1 = 9, x2 = 13, y1 = 9, y2 = 13 } } },
    } }
end

function F.zombie()
    local zombie = { zombie = true, thumpReads = 0 }
    function zombie:getThumpTarget()
        self.thumpReads = self.thumpReads + 1
        return self.target
    end
    function zombie:setThumpTarget(value) self.target = value end
    return zombie
end

function U.gridSquare(x, y, z)
    F.gridReads = F.gridReads + 1
    return F.squares[F.key(x, y, z)]
end

function U.call(object, method, ...)
    if object == nil or type(object[method]) ~= "function" then
        return nil, false
    end
    local ok, value = pcall(object[method], object, ...)
    if not ok then return nil, false end
    return value, true
end

function U.instanceOf(object, class)
    return object ~= nil and object.__class == class
end

function U.squareObjects(square, callback)
    for _, object in ipairs(square.objects) do callback(object) end
end

function U.squareSpecialObjects(square, callback)
    for _, object in ipairs(square.specialObjects) do callback(object) end
end

function U.position(value)
    return value.x, value.y, value.z or 0
end

function U.isZombie(value)
    return value.zombie == true and value.alife ~= true
end

function U.nowMs() return F.now end

function getGameTime()
    return { getMultiplier = function() return F.multiplier end }
end

function getNumActivePlayers() return #F.localPlayers end
function getSpecificPlayer(index) return F.localPlayers[index + 1] end

Events = { OnZombieUpdate = { callbacks = {} } }
function Events.OnZombieUpdate.Add(callback)
    table.insert(Events.OnZombieUpdate.callbacks, callback)
end
function Events.OnZombieUpdate.Remove(callback)
    for index, saved in ipairs(Events.OnZombieUpdate.callbacks) do
        if saved == callback then
            table.remove(Events.OnZombieUpdate.callbacks, index)
            return
        end
    end
end
