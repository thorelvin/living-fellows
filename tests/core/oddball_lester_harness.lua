-- SPDX-License-Identifier: MIT
local SC = SurvivorCompanion
local function inventory() return { items = {} } end
local husband = { id = "husband", x = 1, y = 1, z = 0, inv = inventory() }
local wife = { id = "wife", x = 3, y = 2, z = 0, inv = inventory() }
local player = { id = "player", x = 4, y = 0, z = 0, inv = inventory() }
local door = { open = false }
local doorSquare = { x = 4, y = 1, z = 0, objects = { door } }
local group = { id = "voss-house", standing = "Wary",
    members = { { actorId = "husband" }, { actorId = "wife" } },
    house = { bounds = { x1 = 0, y1 = 1, x2 = 6, y2 = 6 },
        openings = { { x = 4, y = 1, z = 0, objectIndex = 0,
            kind = "door" } } },
    oddball = { id = "slot_lester_voss", stage = "unmet",
        site = { spawn = { x = 1, y = 1, z = 0 },
            slotDoor = { x = 4, y = 1, z = 0, objectIndex = 0 },
            slotOutside = { x = 4, y = 0, z = 0 } } } }
local ended = 0
SC.NativeList = { size = function(list) return #list end,
    get = function(list, index) return list[index + 1] end }
SC.Registry = { byId = function(id)
    if id == "husband" then return { actor = husband } end
    if id == "wife" then return { actor = wife } end
end }
SC.Actor = { endLife = function(actor)
    assert(actor == husband)
    ended = ended + 1
    return true
end }
SC.Factions = { forceStanding = function(id, standing)
    assert(id == group.id)
    group.standing = standing
    return true
end }
SC.FactionBehavior = { fortifyOddball = function(actor, faction)
    assert(actor == wife and faction == group)
    return true, "working"
end }
SC.GameplayUtil = {
    isValidActor = function(actor) return actor ~= nil end,
    position = function(object) return object.x, object.y, object.z end,
    distance = function(a, b)
        return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
    end,
    squareOf = function(actor)
        return { room = actor == player and actor.y > 0 or false }
    end,
    gridSquare = function(x, y)
        return x == 4 and y == 1 and doorSquare or nil
    end,
    instanceOf = function(object, kind)
        return object == door and kind == "IsoDoor"
    end,
    call = function(object, method, ...)
        if method == "getObjects" then return object.objects, true end
        if method == "getRoom" then return object.room and {} or nil, true end
        if method == "IsOpen" then return object.open, true end
        if method == "getContainer" then return object.container, true end
        if method == "setName" then object.name = (...) return true, true end
        return nil, false
    end,
    inventory = function(actor) return actor.inv end,
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
    transferItemVerified = function(source, destination, item)
        for index, current in ipairs(source.items) do
            if current == item then
                table.remove(source.items, index)
                destination.items[#destination.items + 1] = item
                item.container = destination
                return true
            end
        end
        return false
    end,
    canSee = function(observer, actor)
        return observer == player and actor == wife and player.y > 0
    end,
    say = function(actor, line) actor.lastLine = line return true end,
    config = function() return true end,
}
local Lester = SC.OddballLester
assert(Lester.onSpawn(group, husband))
assert(Lester.onSpawn(group, wife))
assert(#group.jobs == 1 and group.jobs[1].kind == "barricade")
assert(husband.inv.items[1].name:find("Martha", 1, true))
assert(Lester.pulse(group, player))
assert(ended == 1 and Lester.canTalkThroughSlot(group, player))
assert(Lester.pulse(group, player) and ended == 1,
    "native husband death requested once")
assert(Lester.intentFor(wife, player, {}, group).mode == "lester_fortify")
assert(Lester.update(wife, player, {}, { mode = "lester_fortify" }, group))
for _ = 1, 10 do
    SC.GameplayUtil.addItem(player.inv, "Base.CannedBeans")
    local before = #player.inv.items
    assert(Lester.action(group, "slot_trade", player))
    assert(#player.inv.items == before,
        "exact payment exchanged for one exact stocked item")
end
assert(group.oddball.trades == 10 and group.oddball.stage == "quiet")
assert(not Lester.action(group, "slot_trade", player))
door.open = true
assert(not Lester.canTalkThroughSlot(group, player),
    "opening the real door closes the slot UI")
player.y = 2
assert(Lester.pulse(group, player) and group.oddball.revealed)
assert(Lester.action(group, "ask_lester", player))
print("Lester PASS: real barricade job, one death, ten exact trades, door reveal")
