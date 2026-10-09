-- SPDX-License-Identifier: MIT
local SC = SurvivorCompanion
local knight = { id = "dwight", x = 0, y = 0, z = 0,
    inv = { items = {} } }
local player = { id = "player", x = 1, y = 0, z = 0 }
local member = { actorId = "dwight", hibernated = false }
local group = { id = "knight-group", standing = "Neutral",
    members = { member }, oddball = { id = "knight_sir_dwight",
        stage = "unmet", site = { kind = "roamer",
            spawn = { x = 0, y = 0, z = 0 },
            house = { id = "gas", anchor = { x = 0, y = 0, z = 0 },
                bounds = {} } } } }
local visible, zombies = true, 0
local poses, searches, hibernations = {}, {}, 0
SC.GameplayUtil = {
    nowMs = function() return 1000 end,
    isValidActor = function(value) return value ~= nil end,
    position = function(value) return value.x, value.y, value.z end,
    distance = function(a, b)
        return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
    end,
    canSee = function() return visible end,
    inventory = function(value) return value.inv end,
    inventoryItemsDeep = function(inv) return inv.items end,
    itemType = function(item) return item.kind end,
    addItem = function(inv, kind)
        local item = { kind = kind }
        inv.items[#inv.items + 1] = item
        return item
    end,
    gridSquare = function(x, y, z) return { x = x, y = y, z = z } end,
    instanceOf = function(value, kind) return kind == "IsoZombie" end,
    call = function(value, method, ...)
        if method == "getMovingObjects" then
            local list = {}
            if value.x == group.oddball.site.spawn.x
                and value.y == group.oddball.site.spawn.y then
                for index = 1, zombies do list[index] = {} end
            end
            return list, true
        end
        return true, true
    end,
    say = function(actor, line) actor.lastLine = line return true end,
}
SC.NativeList = { size = function(list) return #list end,
    get = function(list, index) return list[index + 1] end }
SC.Registry = { byId = function(id)
    return id == "dwight" and not member.hibernated
        and { actor = knight } or nil
end }
SC.Actor = { setMovement = function(actor, mode, intent)
    assert(actor == knight and intent.action)
    poses[#poses + 1] = intent.action
    return true
end }
SC.Factions = { hibernateOddballRoamer = function(id)
    assert(id == group.id)
    member.hibernated = true
    hibernations = hibernations + 1
    return true
end, forceStanding = function() return true end }
SC.Oddballs = { findKnightSite = function(_, stage, previous)
    searches[#searches + 1] = stage
    local x = stage * 70
    return { room = stage == 2 and "bedroom" or "basement",
        spawn = { x = x, y = 0, z = stage == 3 and -1 or 0 },
        house = { id = "scene" .. stage,
            anchor = { x = x, y = 0, z = 0 }, bounds = {} } }
end }
local Dwight = SC.OddballDwight
assert(Dwight.onSpawn(group, knight))
assert(knight.inv.items[1].kind == "Base.Sword")
assert(Dwight.update(knight, player, {},
    Dwight.intentFor(knight, player, {}, group), group))
assert(poses[1] == "sit_ground")
assert(Dwight.action(group, "wake_knight", player))
visible = false
Dwight.pulse(group, player, 1000)
assert(Dwight.pulse(group, player, 32000))
assert(member.hibernated and group.oddball.awaitingStageSite)
Dwight.pulse(group, player, 33000)
assert(group.oddball.stage == "arriving" and searches[1] == 2)
member.hibernated = false
knight.x, player.x = 140, 141
visible = true
assert(Dwight.onSpawn(group, knight))
assert(group.oddball.visit == 2)
assert(Dwight.action(group, "wake_knight", player))
visible = false
Dwight.pulse(group, player, 34000)
Dwight.pulse(group, player, 65000)
assert(member.hibernated and hibernations == 2)
Dwight.pulse(group, player, 66000)
assert(group.oddball.stage == "arriving" and searches[2] == 3)
member.hibernated = false
knight.x, knight.z = 210, -1
player.x, player.z = 211, -1
zombies = 3
visible = true
assert(Dwight.onSpawn(group, knight))
assert(group.oddball.visit == 3)
assert(not Dwight.canRecruit(group))
zombies = 0
assert(Dwight.pulse(group, player, 67000))
assert(Dwight.canRecruit(group))
assert(poses[#poses] == "stand_ground")
print("Dwight PASS: real sword, rest pose, three scenes, rescue gate")
