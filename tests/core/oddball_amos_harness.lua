-- SPDX-License-Identifier: MIT
local SC = SurvivorCompanion
local priest = { id = "amos", x = 0, y = 0, z = 0,
    inv = { items = {} } }
local player = { id = "player", x = 2, y = 0, z = 0,
    inv = { items = {} } }
local group = { id = "church-group", standing = "Wary",
    members = { { actorId = "amos" } },
    oddball = { id = "preacher_reverend_amos", stage = "unmet",
        site = { spawn = { x = 0, y = 0, z = 0 } } } }
local threatened = true
SC.GameplayUtil = {
    nowMs = function() return 1000 end,
    isValidActor = function(v) return v ~= nil end,
    position = function(v) return v.x, v.y, v.z end,
    distance = function(a, b)
        return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
    end,
    canSee = function() return true end,
    inventory = function(v) return v.inv end,
    inventoryItemsDeep = function(inv) return inv.items end,
    itemType = function(item) return item.kind end,
    addItem = function(inv, kind)
        local item = { kind = kind, container = inv }
        inv.items[#inv.items + 1] = item
        return item
    end,
    gridSquare = function(x, y, z) return { x = x, y = y, z = z } end,
    isZombie = function(v) return v.zombie == true end,
    config = function() return false end,
    call = function(v, method)
        if method == "getContainer" then return v.container, true end
        if method == "getMovingObjects" then
            return threatened and v.x == player.x and v.y == player.y
                and { { zombie = true } } or {}, true
        end
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
    say = function(v, line) v.lastLine = line return true end,
}
SC.NativeList = { size = function(list) return #list end,
    get = function(list, index) return list[index + 1] end }
SC.Registry = { byId = function(id)
    return id == "amos" and { actor = priest } or nil
end }
SC.Factions = { forceStanding = function(id, standing)
    assert(id == group.id)
    group.standing = standing
    return true
end }
local Amos = SC.OddballAmos
assert(Amos.onSpawn(group, priest))
assert(group.standing == "Trusted")
assert(priest.inv.items[1].kind == "Base.DoubleBarrelShotgun")
assert(#priest.inv.items == 4)
assert(Amos.pulse(group, player, 1000))
assert(Amos.intentFor(priest, player, {}, group).mode == "amos_support")
local canned = SC.GameplayUtil.addItem(player.inv, "Base.CannedPeaches")
assert(Amos.menuOptions(group, player)[1].enabled)
assert(Amos.action(group, "tithe_food", player))
assert(canned.container == priest.inv)
assert(#player.inv.items == 1 and player.inv.items[1].kind
    == "Base.ShotgunShellsBox")
assert(#priest.inv.items == 4,
    "one food received and one exact shell box delivered")
assert(Amos.onZombieDead(group, {}, priest))
assert(string.find(priest.lastLine, "judged", 1, true))
threatened = false
assert(Amos.pulse(group, player, 6000))
assert(Amos.intentFor(priest, player, {}, group).mode == "amos_church")
print("Amos PASS: real shotgun, local support, exact tithe trade, combat sermon")
