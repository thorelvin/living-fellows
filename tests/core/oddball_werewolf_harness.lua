-- SPDX-License-Identifier: MIT
local SC = SurvivorCompanion
local dalton = { id = "dalton", x = 0, y = 0, z = 0 }
local player = { id = "player", x = 0, y = 1, z = 0 }
local zombie = { data = {} }
local hours = 0
local removed = 0
local planks = 2
local barricade = { planks = planks }
local door = { isDoor = true, barricade = barricade }
local group = { id = "dalton-group", standing = "Wary",
    lifecycle = "settled", members = { { actorId = "dalton", alive = true } },
    oddball = { id = "werewolf_dalton_reese", stage = "daytime",
        site = { spawn = { x = 0, y = 0, z = 0 },
            cellar = { x = 0, y = 0, z = -1 },
            cellarDoor = { x = 1, y = 0, z = -1, objectIndex = 0 },
            woods = { x = 20, y = 20, z = 0 } } } }
SC.NativeList = { size = function(list) return #list end,
    get = function(list, index) return list[index + 1] end }
SC.Registry = { byId = function(id)
    return id == "dalton" and { actor = dalton } or nil
end }
SC.Actor = { remove = function(actor)
    assert(actor == dalton)
    removed = removed + 1
    return true
end }
SC.Oddballs = { retire = function(_, reason)
    assert(reason == "turned")
    return true
end }
SC.Factions = { forceStanding = function(id, standing)
    assert(id == group.id)
    group.standing = standing
    return true
end }
SC.Navigation = { request = function(_, square, _, intent)
    assert(square and intent.action == "faction_dalton_shelter")
    return true, "walking"
end }
SC.GameplayUtil = {
    nowMs = function() return 1000 end,
    stableHash = function() return 0 end,
    isValidActor = function(actor) return actor ~= nil end,
    position = function(value) return value.x, value.y, value.z end,
    distance = function(a, b)
        local dx, dy, dz = a.x - b.x, a.y - b.y,
            (a.z or 0) - (b.z or 0)
        return math.sqrt(dx * dx + dy * dy + dz * dz)
    end,
    canSee = function() return false end,
    say = function(actor, line) actor.lastLine = line return true end,
    gridSquare = function(x, y, z)
        return x == 1 and y == 0 and z == -1
            and { objects = { door } } or { x = x, y = y, z = z }
    end,
    instanceOf = function(value, kind)
        return value == door and kind == "IsoDoor"
    end,
    modData = function(value) return value.data end,
    call = function(value, method)
        if method == "getWorldAgeHours" then return hours, true end
        if method == "getObjects" then return value.objects, true end
        if method == "getBarricadeOnSameSquare" then
            return value.barricade, true
        end
        if method == "getBarricadeOnOppositeSquare" then
            return nil, true
        end
        if method == "getNumPlanks" then return value.planks, true end
        return nil, false
    end,
}
getGameTime = function() return {} end
addZombiesInOutfit = function(x, y, z, count, outfit)
    assert(x == 0 and y == 0 and z == -1)
    assert(count == 1 and outfit == "Hunter")
    return { zombie }
end
local Werewolf = SC.OddballWerewolf
assert(Werewolf.onSpawn(group, dalton))
local turn = group.oddball.turnHour
assert(turn and turn >= 68)
hours = 19
assert(Werewolf.pulse(group, player))
assert(group.oddball.stage == "entering", tostring(group.oddball.stage))
assert(Werewolf.intentFor(dalton, player, {}, group).mode
    == "werewolf_walk")
assert(Werewolf.update(dalton, player, {},
    { mode = "werewolf_walk" }, group))
dalton.z = -1
assert(Werewolf.pulse(group, player))
assert(group.oddball.stage == "cellar")
player.z = -1
assert(Werewolf.canTalkThroughDoor(group, player))
hours = turn
assert(Werewolf.pulse(group, player))
assert(removed == 1 and group.lifecycle == "destroyed")
assert(zombie.data.lfDaltonReese == group.id)
print("Werewolf PASS: timed cellar walk, real boards, native zombie turn")
