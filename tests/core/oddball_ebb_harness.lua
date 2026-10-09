-- SPDX-License-Identifier: MIT
local SC = SurvivorCompanion
local hour, visible, hiddenCalls = 5 * 24 + 19, true, 0
local function inventory() return { items = {} } end
local merchant = { id = "ebb", x = 0, y = 0, z = 0, inv = inventory() }
local player = { id = "player", x = 1, y = 0, z = 0, inv = inventory() }
local group = { id = "ebb-group", standing = "Wary",
    members = { { actorId = "ebb", hibernated = false } },
    oddball = { id = "peddler_mister_ebb", stage = "unmet",
        site = { kind = "roamer", spawn = { x = 0, y = 0, z = 0 } } } }
local function add(inv, kind)
    local item = { kind = kind, container = inv }
    inv.items[#inv.items + 1] = item
    return item
end
SC.GameplayUtil = {
    idOf = function(value) return value.id end,
    isValidActor = function(value) return value ~= nil end,
    distance = function(a, b)
        return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
    end,
    canSee = function() return visible end,
    position = function(value) return value.x, value.y, value.z end,
    inventory = function(value) return value and value.inv end,
    inventoryItemsDeep = function(value) return value.items end,
    itemType = function(value) return value.kind end,
    addItem = add,
    gridSquare = function() return {} end,
    isSafeSpawnSquare = function() return true end,
    say = function(value, line) value.lastLine = line return true end,
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
    call = function(value, name, ...)
        if not value then return nil, false end
        if name == "getWorldAgeHours" then return hour, true end
        if name == "getTimeOfDay" then return hour % 24, true end
        if name == "getContainer" then return value.container, true end
        if name == "setSecondaryHandItem" then value.secondary = (...) return true, true end
        return nil, false
    end,
}
SC.Registry = { byId = function(id)
    return id == "ebb" and not group.members[1].hibernated
        and { actor = merchant } or nil
end }
SC.Factions = { hibernateOddballRoamer = function(id)
    assert(id == group.id)
    hiddenCalls = hiddenCalls + 1
    group.members[1].hibernated = true
    group.oddball.site.wake = { x = merchant.x, y = merchant.y, z = 0 }
    return true
end }
SC.Oddballs = { findEbbSite = function()
    return { spawn = { x = 200, y = 0, z = 0 }, room = "bait shop" }
end }
getGameTime = function() return {} end

local Ebb = SC.OddballEbb
assert(Ebb.onSpawn(group, merchant))
assert(group.oddball.stage == "trading")
assert(#merchant.inv.items == 2, "lantern plus one real stock item")
add(player.inv, "Base.Money")
add(player.inv, "Base.Money")
assert(Ebb.action(group, "buy_stock", player))
assert(group.oddball.stockSold == true)
assert(#player.inv.items == 1 and player.inv.items[1].kind == "Base.RedDot")
assert(not Ebb.action(group, "buy_stock", player), "one stock per visit")

visible = false
assert(Ebb.pulse(group, player, 1000))
assert(Ebb.pulse(group, player, 62000))
assert(hiddenCalls == 1 and group.members[1].hibernated)
assert(group.oddball.stage == "away")
hour = 11 * 24 + 19
assert(Ebb.pulse(group, player, 63000))
assert(group.oddball.site.wake.x == 200, "same actor must wake elsewhere")
assert(group.oddball.nextVisitDay == 16)
group.members[1].hibernated = false
merchant.x = 200
player.x = 201
assert(Ebb.onSpawn(group, merchant))
assert(group.oddball.visitSerial == 2)
assert(Ebb.action(group, "hurt", player))
assert(group.oddball.priceMultiplier == 1.5)
print("Ebb PASS: exact trade, hidden departure, saved relocation, scarred pricing")
