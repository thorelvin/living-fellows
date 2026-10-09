-- SPDX-License-Identifier: MIT
local SC = SurvivorCompanion
local function actor(id, x)
    return { id = id, x = x, y = 0, z = 0, inv = { items = {} } }
end
local coy, dale, player, fellow = actor("coy", 0), actor("dale", 1),
    actor("player", 2), actor("fellow", 3)
local actors = { coy = coy, dale = dale, fellow = fellow }
local worn = false
local group = { id = "still", standing = "Wary",
    members = { { actorId = "coy" }, { actorId = "dale" } },
    oddball = { id = "bledsoe_brothers_still", stage = "unmet" } }
SC.Registry = {
    byId = function(id)
        return actors[id] and { actor = actors[id],
            recruited = id == "fellow" } or nil
    end,
    living = function() return { fellow } end,
}
SC.Commands = { peek = function(actor)
    return actor == fellow and { ritual = { id = "bourbon_blessing" } }
        or nil
end }
SC.NativeList = { size = function(list) return #list end,
    get = function(list, index) return list[index + 1] end }
SC.Factions = { forceStanding = function(id, standing)
    assert(id == group.id)
    group.standing = standing
    return true
end }
SC.GameplayUtil = {
    nowMs = function() return 1000 end,
    idOf = function(value) return value.id end,
    isValidActor = function(value) return value ~= nil end,
    position = function(value) return value.x, value.y, value.z end,
    distance = function(a, b) return math.abs(a.x - b.x) end,
    canSee = function() return true end,
    say = function(value, line) value.lastLine = line return true end,
    inventory = function(value) return value.inv end,
    inventoryItemsDeep = function(inv) return inv.items end,
    itemType = function(item) return item.kind end,
    addItem = function(inv, kind)
        local item = { kind = kind, container = inv }
        inv.items[#inv.items + 1] = item
        return item
    end,
    call = function(value, method)
        if method == "getContainer" then return value.container, true end
        if method == "getOutfitName" then return nil, true end
        if method == "getWornItems" then
            return value == fellow and worn and {
                { item = { kind = "Base.Shirt_Police" } } } or {}, true
        end
        if method == "getItem" then return value.item, true end
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
local Bledsoe = SC.OddballBledsoe
assert(Bledsoe.onSpawn(group, coy) and #coy.inv.items == 6)
local sugar = SC.GameplayUtil.addItem(player.inv, "Base.Sugar")
local corn = SC.GameplayUtil.addItem(player.inv, "Base.Cornmeal2")
assert(Bledsoe.action(group, "trade_mash", player))
assert(sugar.container == coy.inv and corn.container == coy.inv)
assert(player.inv.items[1].kind == "Base.Whiskey")
assert(Bledsoe.pulse(group, player, 1000))
assert(group.oddball.blessed and fellow.lastLine:find("Bless", 1, true))
worn = true
assert(Bledsoe.pulse(group, player, 6000))
assert(group.standing == "Hostile")
print("Bledsoe PASS: exact whiskey trade, real ritual, worn law outfit hostility")
