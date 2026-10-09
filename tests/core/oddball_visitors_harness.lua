-- SPDX-License-Identifier: MIT
local SC = SurvivorCompanion
local function actor(id, x, y)
    return { id = id, x = x, y = y, z = 0, inv = { items = {} } }
end
local leader, believer1, believer2 = actor("leader", 0, 0),
    actor("believer1", 1, 0), actor("believer2", 0, 1)
local player = actor("player", 1, 1)
local actors = { leader = leader, believer1 = believer1, believer2 = believer2 }
local cache = { items = {} }
local hours = 23
local visible = true
local removed = 0
local group = { id = "fellowship", standing = "Wary",
    lifecycle = "settled", house = { bounds = { x1 = 0, y1 = 0,
        x2 = 5, y2 = 5 }, anchor = { x = 0, y = 0 } },
    members = { { actorId = "leader" }, { actorId = "believer1" },
        { actorId = "believer2" } },
    oddball = { id = "silver_visitors_fellowship", stage = "waiting",
        site = { woods = { x = 20, y = 20, z = 0 },
            cache = { x = 2, y = 2, z = 0, objectIndex = 0 },
            memberSpawns = { { x = 0, y = 0, z = 0 },
                { x = 1, y = 0, z = 0 },
                { x = 0, y = 1, z = 0 } } } } }
SC.Registry = { byId = function(id)
    return actors[id] and { actor = actors[id] } or nil
end }
SC.Actor = { remove = function(value)
    assert(value ~= player)
    removed = removed + 1
    return true
end }
SC.Factions = {
    resolveQuestContainer = function(locator)
        assert(locator.x == 2 and locator.y == 2)
        return cache, nil, locator
    end,
    forceStanding = function(_, standing)
        group.standing = standing
        return true
    end,
}
SC.Oddballs = { retire = function(_, reason)
    assert(reason == "vanished_in_woods")
    return true
end }
SC.Navigation = { request = function(_, square, _, intent)
    assert(square and intent.action == "faction_visitors_woods")
    return true, "walking"
end }
SC.GameplayUtil = {
    nowMs = function() return 1000 end,
    isValidActor = function(value) return value ~= nil end,
    position = function(value) return value.x, value.y, value.z end,
    distance = function(a, b)
        return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
    end,
    canSee = function(observer, value)
        return visible and observer == player and value ~= player
    end,
    say = function(value, line) value.lastLine = line return true end,
    gridSquare = function(x, y, z) return { x = x, y = y, z = z } end,
    isSafeSpawnSquare = function() return true end,
    inventory = function(value) return value.inv end,
    inventoryItemsDeep = function(inv) return inv.items end,
    itemType = function(item) return item.kind end,
    modData = function(item)
        item.data = item.data or {}
        return item.data
    end,
    addItem = function(inv, kind)
        local item = { kind = kind, container = inv }
        inv.items[#inv.items + 1] = item
        return item
    end,
    call = function(value, method)
        if method == "getContainer" then return value.container, true end
        if method == "getWorldAgeHours" then return hours, true end
        return nil, false
    end,
    transferItemVerified = function(source, destination, item)
        for index, existing in ipairs(source.items) do
            if existing == item then
                table.remove(source.items, index)
                destination.items[#destination.items + 1] = item
                item.container = destination
                return true
            end
        end
        return false
    end,
}
getGameTime = function() return {} end
local Visitors = SC.OddballVisitors
assert(Visitors.onSpawn(group, leader))
assert(#leader.inv.items == 4)
local radio = SC.GameplayUtil.addItem(player.inv, "Base.HamRadio1")
local battery1 = SC.GameplayUtil.addItem(player.inv, "Base.Battery")
local battery2 = SC.GameplayUtil.addItem(player.inv, "Base.Battery")
assert(Visitors.action(group, "give_radio", player))
assert(Visitors.action(group, "give_battery", player))
assert(Visitors.action(group, "give_battery", player))
assert(radio.container == leader.inv and battery1.container == leader.inv
    and battery2.container == leader.inv)
assert(#player.inv.items == 0 and group.oddball.stage == "ready")
assert(Visitors.pulse(group, player, 1000))
assert(group.oddball.stage == "marching")
assert(Visitors.intentFor(leader, player, {}, group).mode == "visitors_march")
assert(Visitors.update(leader, player, {}, { mode = "visitors_march" }, group))
leader.x, leader.y = 20, 20
believer1.x, believer1.y = 21, 20
believer2.x, believer2.y = 20, 21
player.x, player.y = 1, 1
assert(Visitors.pulse(group, player, 2000))
assert(group.oddball.stage == "vigil")
visible = false
assert(Visitors.pulse(group, player, 123000))
assert(group.lifecycle == "destroyed" and removed == 3)
assert(#cache.items == 7,
    "four original supplies and three exact beacon parts left behind")
assert(cache.items[5] == radio or cache.items[6] == radio
    or cache.items[7] == radio)
print("Visitors PASS: exact beacon parts, night walk, real cache, unseen exit")
