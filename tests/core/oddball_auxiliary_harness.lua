-- SPDX-License-Identifier: MIT
local SC = SurvivorCompanion
local function actor(id, x)
    return { id = id, x = x, y = 0, z = 0, inv = { items = {} } }
end
local dorothy, evelyn, opal, player = actor("dorothy", 0),
    actor("evelyn", 1), actor("opal", 2), actor("player", 2)
local actors = { dorothy = dorothy, evelyn = evelyn, opal = opal }
local group = { id = "auxiliary", standing = "Wary", members = {
    { actorId = "dorothy", alive = true },
    { actorId = "evelyn", alive = true },
    { actorId = "opal", alive = true } },
    oddball = { id = "rosewood_auxiliary", stage = "unmet" } }
local requested = {}
SC.Registry = { byId = function(id)
    return actors[id] and { actor = actors[id] } or nil
end }
SC.Factions = { forceStanding = function(id, standing)
    assert(id == group.id)
    group.standing = standing
    return true
end }
SC.FactionRecruitment = {
    summary = function() return { status = "available" } end,
    ask = function() requested[#requested + 1] = "ask" return true end,
    startTrial = function() requested[#requested + 1] = "trial" return true end,
}
SC.GameplayUtil = {
    isValidActor = function(value) return value ~= nil end,
    position = function(value) return value.x, value.y, value.z end,
    distance = function(a, b) return math.abs(a.x - b.x) end,
    canSee = function() return true end,
    say = function(value, line) value.lastLine = line return true end,
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
        return true, true
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
}
local Auxiliary = SC.OddballAuxiliary
assert(Auxiliary.onSpawn(group, dorothy))
assert(Auxiliary.onSpawn(group, evelyn))
assert(Auxiliary.onSpawn(group, opal))
assert(dorothy.inv.items[1].kind == "Base.RollingPin")
assert(evelyn.inv.items[1].kind == "Base.Pan")
for _ = 1, 2 do
    local flour = SC.GameplayUtil.addItem(player.inv, "Base.Flour2")
    local sugar = SC.GameplayUtil.addItem(player.inv, "Base.Sugar")
    assert(Auxiliary.action(group, "buy_bake", player))
    assert(flour.container == dorothy.inv and sugar.container == dorothy.inv)
end
assert(#player.inv.items == 2 and player.inv.items[1].kind == "Base.Pie")
assert(group.standing == "Trusted" and Auxiliary.canRecruit(group))
assert(group.oddball.recruitmentCandidateKey == "member-3")
assert(Auxiliary.action(group, "recruit", player))
assert(requested[1] == "ask" and requested[2] == "trial")
assert(Auxiliary.action(group, "hurt", player))
assert(group.standing == "Hostile")
for _, value in ipairs({ dorothy, evelyn, opal }) do
    assert(value.lastLine:find("manners", 1, true))
end
print("Auxiliary PASS: real bake trade, Opal candidate, collective defense")
