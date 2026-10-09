-- SPDX-License-Identifier: MIT
local SC = SurvivorCompanion
local function actor(id, x)
    return { id = id, x = x, y = 0, z = 0, inv = { items = {} } }
end
local pest, bolt, player, fellow = actor("pest", 0), actor("bolt", 10),
    actor("player", 1), actor("fellow", 2)
local groups = {
    pestGroup = { id = "pestGroup", standing = "Wary",
        lifecycle = "settled", members = { { actorId = "pest", alive = true } },
        oddball = { id = "doctor_pest", stage = "feud",
            rivalGroupId = "boltGroup" } },
    boltGroup = { id = "boltGroup", standing = "Wary",
        lifecycle = "settled", members = { { actorId = "bolt", alive = true } },
        oddball = { id = "bluegrass_bolt", stage = "feud",
            rivalGroupId = "pestGroup" } },
}
local actors = { pest = pest, bolt = bolt, fellow = fellow }
SC.Registry = {
    byId = function(id)
        return actors[id] and { actor = actors[id],
            recruited = id == "fellow" } or nil
    end,
    living = function() return { fellow } end,
}
SC.Commands = { peek = function(actor)
    return actor == fellow and { personalityProfile = {
        archetype = "caring", compassion = 90 } } or nil
end }
SC.Factions = {
    group = function(id) return groups[id] end,
    forceStanding = function(id, standing)
        groups[id].standing = standing
        return true
    end,
}
SC.GameplayUtil = {
    nowMs = function() return 1000 end,
    isValidActor = function(value) return value ~= nil end,
    idOf = function(value) return value.id end,
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
    call = function(value, method, ...)
        if method == "getContainer" then return value.container, true end
        if method == "setName" then value.name = (...) end
        return true, true
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
local Rivals = SC.OddballRivals
assert(Rivals.onSpawn(groups.pestGroup, pest))
assert(Rivals.onSpawn(groups.boltGroup, bolt))
assert(pest.inv.items[1].kind == "Base.KnapsackSprayer")
assert(bolt.inv.items[1].kind == "Base.Glasses_Aviators")
assert(Rivals.action(groups.pestGroup, "ask_clipping", player))
assert(#player.inv.items == 1 and player.inv.items[1].data.lfRivalClipping)
assert(Rivals.action(groups.pestGroup, "take_side", player))
local intent = Rivals.intentFor(pest, player, {}, groups.pestGroup)
assert(intent.mode == "hostile" and intent.humanThreat.actor == bolt)
assert(Rivals.action(groups.pestGroup, "show_clipping", player))
assert(groups.pestGroup.oddball.stage == "mediated"
    and groups.boltGroup.oddball.stage == "mediated")
assert(groups.pestGroup.standing == "Trusted"
    and groups.boltGroup.standing == "Trusted")
assert(Rivals.canRecruit(groups.pestGroup))
assert(Rivals.action(groups.pestGroup, "claim_gear", player))
assert(player.inv.items[2].kind == "Base.KnapsackSprayer")
groups.pestGroup.oddball.stage = "feud"
groups.boltGroup.oddball.stage = "feud"
assert(Rivals.action(groups.pestGroup, "mediate_caring", player))
assert(fellow.lastLine:find("enough dead", 1, true))
print("Rivals PASS: separate factions, real hostility, clipping and caring mediation")
