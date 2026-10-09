-- SPDX-License-Identifier: MIT
local SC = SurvivorCompanion
local hour = 24
local doctrine = "close_defense"
local crouched = false
local player = { id = "player", x = 2, y = 0, z = 0,
    inv = { items = {} } }
local mose = { id = "mose", x = 0, y = 0, z = 0,
    inv = { items = {} } }
local group = { id = "mose-group", standing = "Neutral",
    members = { { actorId = "mose" } },
    oddball = { id = "sniper_old_mose_calloway", stage = "unmet",
        site = { spawn = { x = 0, y = 0, z = 0 } } } }
local retired
SC.GameplayUtil = {
    nowMs = function() return 1000 end,
    isValidActor = function(value) return value ~= nil end,
    position = function(value) return value.x, value.y, value.z end,
    distance = function(a, b)
        return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
    end,
    canSee = function() return true end,
    inventory = function(value) return value.inv end,
    inventoryItemsDeep = function(inv) return inv.items end,
    itemType = function(item) return item.kind end,
    addItem = function(inv, kind)
        local item = { kind = kind, container = inv, data = {} }
        inv.items[#inv.items + 1] = item
        return item
    end,
    modData = function(item) return item.data end,
    config = function() return false end,
    call = function(value, method, ...)
        if method == "getWorldAgeHours" then return hour, true end
        if method == "isSneaking" or method == "isCrouching" then
            return crouched, true end
        if method == "getContainer" then return value.container, true end
        if method == "isDead" then return value.dead == true, true end
        if method == "setName" then value.name = (...) return true, true end
        if method == "playSound" then value.sound = (...) return true, true end
        return true, true
    end,
    transferItemVerified = function(from, to, item)
        local found
        for index, current in ipairs(from.items) do
            if current == item then found = index; break end
        end
        if not found then return false end
        table.remove(from.items, found)
        to.items[#to.items + 1] = item
        item.container = to
        return true
    end,
    say = function(value, line) value.lastLine = line return true end,
}
SC.Registry = { byId = function(id)
    return id == "mose" and { actor = mose } or nil
end }
SC.Commands = { teamCombatDoctrine = function() return doctrine end }
SC.Factions = { forceStanding = function(id, standing)
    assert(id == group.id)
    group.standing = standing
    return true
end }
SC.Actor = { endLife = function(actor)
    assert(actor == mose)
    actor.dead = true
    return true
end }
SC.Oddballs = { retire = function(value, reason)
    assert(value == group)
    retired = reason
    return true
end }
getGameTime = function() return {} end

local Mose = SC.OddballMose
assert(Mose.onSpawn(group, mose))
assert(mose.inv.items[1].kind == "Base.HuntingRifle")
assert(Mose.pulse(group, player, 1000))
assert(group.oddball.firstSeenDay == 1 and mose.sound == "MSR788Shoot")
assert(not Mose.action(group, "stealth_yield", player))
doctrine, crouched = "stealth", true
assert(Mose.action(group, "stealth_yield", player))
assert(group.oddball.stage == "yielded")
assert(player.inv.items[1].kind == "Base.HuntingRifle")
assert(#mose.inv.items == 1, "ammunition stays with Mose")

-- A separate seven-day outcome keeps the exact rifle and note on his corpse.
group.oddball.stage = "watching"
group.oddball.firstSeenDay = 1
group.oddball.notePlaced = nil
group.oddball.rifleSeeded = nil
mose.dead = false
mose.inv = { items = {} }
assert(Mose.onSpawn(group, mose))
hour = 24 * 8
assert(Mose.pulse(group, player, 2000))
assert(group.oddball.stage == "dying")
assert(#mose.inv.items == 3, "ammo, rifle, and one real note remain")
assert(Mose.pulse(group, player, 3000))
assert(retired == "dead_of_age")
assert(group.oddball.notePlaced == true)
print("Mose PASS: stealth surrender, rifle transfer, warning, seven-day corpse note")
