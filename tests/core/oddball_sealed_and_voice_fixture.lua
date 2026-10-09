-- SPDX-License-Identifier: MIT
SurvivorCompanion = { GameplayUtil = {}, Registry = {}, Factions = {},
    NativeList = {}, Navigation = {}, OddballRoomGuard = {}, Diagnostics = {} }
local SC = SurvivorCompanion
local U = SC.GameplayUtil
SealedVoiceFixture = { now = 1000, zombies = {}, groups = {}, released = 0,
    sounds = {}, lines = {}, clicks = {}, routes = {} }
local F = SealedVoiceFixture
local door = { __class = "IsoDoor", open = false, locked = false }
F.door = door
function door:IsOpen() return self.open end
function door:isLocked() return self.locked end
function door:setLocked(value) self.locked = value end
function door:setLockedByKey(value) self.lockedByKey = value end
F.player = { x = 10, y = 11, z = 0 }
function getSpecificPlayer() return F.player end
Events = { OnObjectLeftMouseButtonDown = {} }
function Events.OnObjectLeftMouseButtonDown.Add(callback)
    F.clicks[#F.clicks + 1] = callback
end
function Events.OnObjectLeftMouseButtonDown.Remove(callback)
    for index, stored in ipairs(F.clicks) do
        if stored == callback then table.remove(F.clicks, index); break end
    end
end
function U.call(object, method, ...)
    local functionValue = object and object[method]
    if type(functionValue) ~= "function" then return nil, false end
    return functionValue(object, ...), true
end
function U.instanceOf(object, class) return object and object.__class == class end
function U.position(object) return object.x, object.y, object.z end
function U.distance(left, right)
    local x, y = U.position(left)
    local a, b = U.position(right)
    return math.sqrt((x - a) ^ 2 + (y - b) ^ 2)
end
function U.canSee() return true end
function U.isValidActor(actor) return actor ~= nil end
function U.isSafeSpawnSquare(square) return square ~= nil end
function U.modData(object)
    object.data = object.data or {}
    return object.data
end
function U.say(actor, line)
    F.lines[#F.lines + 1] = { actor = actor, line = line }
    return true
end
function U.nowMs() return F.now end
function U.squareOf(value) return value end
function U.gridSquare(x, y, z)
    local square = { x = x, y = y, z = z }
    function square:getRoom() return nil end
    function square:getObjects()
        return self.x == 10 and self.y == 10 and { door } or {}
    end
    return square
end
function SC.NativeList.get(list, index) return list[index + 1] end
function SC.Factions.list() return F.groups end
function SC.Registry.byId(id) return F.records[id] end
function SC.OddballRoomGuard.release() F.released = F.released + 1 end
function SC.Diagnostics.report() return true end
function SC.Navigation.request(actor, target, pace, options)
    F.routes[#F.routes + 1] = { actor = actor, target = target,
        pace = pace, options = options }
    return true, "retreat_requested"
end
function addZombiesInOutfit(x, y, z, count, outfit)
    local list = {}
    for _ = 1, count do
        local zombie = { x = x, y = y, z = z, outfit = outfit }
        F.zombies[#F.zombies + 1] = zombie
        list[#list + 1] = zombie
    end
    return list
end
local function actor(id, x, y)
    local value = { id = id, x = x, y = y, z = 0 }
    function value:playSound(name)
        F.sounds[#F.sounds + 1] = name
        return 1
    end
    return value
end
F.records = {
    caleb = { actor = actor("caleb", 10, 11) },
    vera = { actor = actor("vera", 20, 20) },
}
F.caleb = { id = "sealed-group", members = { { actorId = "caleb" } },
    oddball = { id = "survivalist_locked_horde", site = {
        roomDoor = { x = 10, y = 10, z = 0, objectIndex = 0 },
        hordeSpawns = { { x = 10, y = 9, z = 0 },
            { x = 11, y = 9, z = 0 }, { x = 10, y = 8, z = 0 },
            { x = 11, y = 8, z = 0 } } } } }
F.vera = { id = "voice-group", members = { { actorId = "vera" } },
    oddball = { id = "voice_actor_vera_quill" } }
F.groups = { F.caleb, F.vera }
