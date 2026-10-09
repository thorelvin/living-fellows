-- SPDX-License-Identifier: MIT
local SC = SurvivorCompanion
local function actor(id, x)
    return { id = id, x = x, y = 0, z = 0, inv = { items = {} } }
end
local king, jerry, otis, player = actor("king", 0), actor("jerry", 1),
    actor("otis", 2), actor("player", 2)
local actors = { king = king, jerry = jerry, otis = otis }
local calls = {}
local group = { id = "bar", standing = "Wary", members = {
    { actorId = "king", alive = true },
    { actorId = "jerry", alive = true },
    { actorId = "otis", alive = true } },
    oddball = { id = "tupelo_boys", stage = "unmet" } }
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
    ask = function() calls[#calls + 1] = "ask" return true end,
    startTrial = function() calls[#calls + 1] = "trial" return true end,
}
SC.GameplayUtil = {
    nowMs = function() return 1000 end,
    isValidActor = function(value) return value ~= nil end,
    position = function(value) return value.x, value.y, value.z end,
    distance = function(a, b) return math.abs(a.x - b.x) end,
    canSee = function() return true end,
    inventory = function(value) return value.inv end,
    inventoryItemsDeep = function(inv) return inv.items end,
    itemType = function(item) return item.kind end,
    addItem = function(inv, kind)
        local item = { kind = kind, container = inv }
        inv.items[#inv.items + 1] = item
        return item
    end,
    call = function(item, method, ...)
        if method == "getContainer" then return item.container, true end
        if method == "setCurrentAmmoCount" then item.ammo = (...) end
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
    say = function(value, line) value.lastLine = line return true end,
}
local Tupelo = SC.OddballTupelo
assert(Tupelo.onSpawn(group, king))
assert(Tupelo.onSpawn(group, jerry))
assert(Tupelo.onSpawn(group, otis))
assert(king.inv.items[1].kind == "Base.Pistol"
    and king.inv.items[1].ammo == 10)
assert(otis.inv.items[1].kind == "Base.GuitarAcoustic")
local magazine = SC.GameplayUtil.addItem(player.inv,
    "Base.Magazine_Music")
assert(Tupelo.action(group, "offer_music", player))
assert(magazine.container == king.inv and #player.inv.items == 0)
assert(group.oddball.blessing and group.standing == "Trusted")
assert(group.oddball.recruitmentCandidateKey == "member-2")
assert(not Tupelo.action(group, "offer_music", player))
assert(Tupelo.canRecruit(group))
assert(Tupelo.action(group, "recruit", player))
assert(calls[1] == "ask" and calls[2] == "trial")
assert(Tupelo.onZombieDead(group, {}, jerry))
assert(jerry.lastLine:find("Keep the beat", 1, true))
print("Tupelo PASS: real music blessing, armed defense, named recruitment")
