-- SPDX-License-Identifier: MIT
local SC = SurvivorCompanion
local playerInventory = { items = {} }
local velmaInventory = { items = {} }
local cache = { items = {} }
local player = { id = "player", x = 1, y = 0, z = 0,
    inv = playerInventory }
local velma = { id = "velma", x = 0, y = 0, z = 0,
    inv = velmaInventory }
local group = { id = "velma-group", standing = "Neutral",
    members = { { actorId = "velma" } },
    oddball = { id = "seer_aunt_velma_crisp", stage = "unmet",
        site = { spawn = { x = 0, y = 0, z = 0 } } } }
local coffee = { kind = "Base.Coffee2", container = playerInventory }
playerInventory.items[1] = coffee
local house = { id = "cache-house", anchor = { x = 50, y = 50, z = 0 },
    bounds = {}, questContainer = { x = 50, y = 50, z = 0 } }
local searchCount = 0
SC.GameplayUtil = {
    isValidActor = function(value) return value ~= nil end,
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
    transferItemVerified = function(source, destination, item)
        local found
        for index, current in ipairs(source.items) do
            if current == item then found = index; break end
        end
        if not found then return false end
        table.remove(source.items, found)
        destination.items[#destination.items + 1] = item
        item.container = destination
        return true
    end,
    modData = function(item) return item.data end,
    say = function(actor, line) actor.lastLine = line return true end,
    stableHash = function() return 3 end,
    call = function(object, method, ...)
        if method == "getContainer" then return object.container, true end
        return nil, false
    end,
}
SC.Registry = { byId = function(id)
    return id == "velma" and { actor = velma } or nil
end }
SC.Factions = {
    findHouse = function(_, options)
        searchCount = searchCount + 1
        assert(options.purpose == "quest" and options.sampleBudget == 48)
        return house
    end,
    resolveQuestContainer = function() return cache end,
    describeLocation = function()
        return { address = "House 12 tiles NW of Main Street" }
    end,
    forceStanding = function() return true end,
}
local Velma = SC.OddballVelma
assert(Velma.onSpawn(group, velma))
assert(velmaInventory.items[1].kind == "Base.TarotCardDeck")
assert(Velma.pulse(group, player))
local options = Velma.menuOptions(group, player)
assert(options[1].enabled == true)
assert(Velma.action(group, "read_cards", player))
assert(group.oddball.stage == "reading_complete")
assert(#playerInventory.items == 0 and #velmaInventory.items == 2)
assert(#cache.items == 1 and cache.items[1].data.lfVelmaCacheGroupId == group.id)
assert(group.oddball.cacheAddress == "House 12 tiles NW of Main Street")
assert(Velma.canRecruit(group))
assert(Velma.action(group, "repeat_reading", player))
assert(not Velma.action(group, "read_cards", player))
assert(#cache.items == 1 and searchCount == 1,
    "one reading cannot duplicate the cache")
print("Velma PASS: verified payment, real cache container, exact address, no repeat")
