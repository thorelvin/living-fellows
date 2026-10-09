-- SPDX-License-Identifier: MIT
local SC = SurvivorCompanion
local actors, groups, zombies = {}, {}, 0
local function actor(id)
    local value = { id = id, x = 0, y = 0, z = 0, inv = { items = {} } }
    actors[id] = value
    return value
end
local player = actor("player")
local function group(id)
    local resident = actor(id)
    local value = { id = id, standing = "Wary", discovered = true,
        members = { { actorId = id } }, oddball = {
            id = "christmas_kris_kimbrough", stage = "list",
            site = { spawn = { x = 0, y = 0, z = 0 },
                elvesRoom = { x = 4, y = 4, z = 0 } } } }
    groups[#groups + 1] = value
    return value, resident
end
SC.GameplayUtil = {
    isValidActor = function(value) return value ~= nil end,
    distance = function() return 1 end,
    canSee = function() return true end,
    position = function(value) return value.x, value.y, value.z end,
    gridSquare = function() return {} end,
    isSafeSpawnSquare = function() return true end,
    stableHash = function() return 3 end,
    inventory = function(value) return value and value.inv end,
    inventoryItemsDeep = function(value) return value.items end,
    itemType = function(value) return value.kind end,
    addItem = function(inv, kind)
        local item = { kind = kind, inv = kind == "Base.Present_Medium"
            and { items = {} } or nil }
        inv.items[#inv.items + 1] = item
        return item
    end,
    transferItemVerified = function(source, destination, item)
        for index, value in ipairs(source.items) do
            if value == item then
                table.remove(source.items, index)
                destination.items[#destination.items + 1] = item
                return true
            end
        end
        return false
    end,
    call = function(value, name)
        if not value then return nil, false end
        if name == "getInventory" then return value.inv, true end
        return nil, false
    end,
    say = function(value, line) value.lastLine = line return true end,
}
SC.Registry = { byId = function(id)
    return actors[id] and { actor = actors[id] }
end }
SC.Factions = {
    list = function() return groups end,
    forceStanding = function() return true end,
}
addZombiesInOutfit = function(x, y, z, count, outfit)
    assert(x == 4 and y == 4 and z == 0 and count == 2)
    assert(outfit == "SantaGreen")
    zombies = zombies + count
    return count
end

local Kris = SC.OddballKris
local nice = group("kris-nice")
assert(Kris.action(nice, "check_list", player))
assert(nice.oddball.judgment == "nice" and nice.oddball.listChecked)
assert(#player.inv.items == 1 and player.inv.items[1].kind == "Base.Present_Medium")
assert(#player.inv.items[1].inv.items == 1, "present must contain a useful item")
assert(not Kris.action(nice, "check_list", player), "one gift per encounter")

local offenseGroup = { id = "known-raid", standing = "Hostile",
    discovered = true, offenses = { { kind = "theft", forgiven = false } } }
groups[#groups + 1] = offenseGroup
local naughty = group("kris-naughty")
assert(Kris.action(naughty, "check_list", player))
assert(naughty.oddball.judgment == "naughty")
assert(player.inv.items[2].kind == "Base.Charcoal")
assert(zombies == 2 and naughty.oddball.elvesReleased)
assert(not Kris.action(naughty, "check_list", player))
assert(zombies == 2, "elves must never respawn")
print("Kris PASS: one wrapped useful present, historical offenses, coal, two elves")
