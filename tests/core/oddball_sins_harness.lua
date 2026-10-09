-- SPDX-License-Identifier: MIT
local SC = SurvivorCompanion
local actors, groups = {}, {}
local function actor(id)
    local value = { id = id, x = 0, y = 0, z = 0, inv = { items = {} },
        medical = { health = 100, alive = true } }
    actors[id] = value
    return value
end
local player = actor("player")
local function group(id)
    local resident = actor(id)
    local value = { id = id, standing = "Neutral", members = {
        { actorId = resident.id } }, oddball = { id = id,
            site = { spawn = { x = 0, y = 0, z = 0 } } } }
    groups[id] = value
    return value, resident
end
local function add(inv, kind)
    local item = { kind = kind, container = inv }
    inv.items[#inv.items + 1] = item
    return item
end
SC.GameplayUtil = {
    idOf = function(value) return value.id end,
    isValidActor = function(value) return value ~= nil end,
    distance = function() return 1 end,
    canSee = function() return true end,
    position = function(value) return value.x, value.y, value.z end,
    gridSquare = function() return {} end,
    inventory = function(value) return value and value.inv end,
    inventoryItemsDeep = function(value) return value.items end,
    itemType = function(value) return value.kind end,
    addItem = add,
    stop = function() end,
    nowMs = function() return 1000 end,
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
        if name == "getContainer" then return value.container, true end
        if name == "getPrimaryHandItem" then return value.primary, true end
        if name == "getSecondaryHandItem" then return value.secondary, true end
        if name == "setPrimaryHandItem" then value.primary = (...) return true, true end
        if name == "getCategory" then return value.category, true end
        if name == "setName" then value.name = (...) return true, true end
        return nil, false
    end,
}
SC.Registry = { byId = function(id)
    return actors[id] and { actor = actors[id] }
end }
SC.Factions = { forceStanding = function(id, standing)
    groups[id].standing = standing
    return true
end }
SC.Medical = { assess = function(value) return value.medical end }
local Sins = SC.OddballSins

local bonnie = group("sin_gluttony_bonnie")
assert(Sins.onSpawn(bonnie, actors[bonnie.id]))
add(player.inv, "Base.CakeChocolate")
assert(Sins.action(bonnie, "trade_sweets", player))
assert(player.inv.items[1].kind == "Base.CannedPeaches")
assert(not Sins.action(bonnie, "trade_sweets", player))
assert(Sins.action(bonnie, "shoplift", player))
assert(bonnie.standing == "Hostile")

local lyman = group("sin_greed_lyman")
assert(Sins.onSpawn(lyman, actors[lyman.id]))
add(player.inv, "Base.Ring_Left_RingFinger_Gold")
assert(Sins.action(lyman, "trade_jewelry", player))
assert(player.inv.items[2].kind == "Base.Bullets9mmBox")

local harlan = group("sin_sloth_harlan")
assert(Sins.onSpawn(harlan, actors[harlan.id]))
add(player.inv, "Base.WaterBottle")
assert(Sins.action(harlan, "fetch_water", player))
assert(player.inv.items[3].kind == "Base.Key1")

local duane, duaneActor = group("sin_wrath_duane")
assert(Sins.onSpawn(duane, duaneActor))
player.primary = { kind = "Base.Pistol", category = "Weapon" }
assert(not Sins.action(duane, "challenge", player))
player.primary = nil
assert(Sins.action(duane, "challenge", player))
assert(duane.standing == "Hostile" and duane.oddball.stage == "duel")
duaneActor.medical.health = 40
assert(Sins.pulse(duane, player, 1000))
assert(duane.oddball.stage == "won" and duane.standing == "Trusted")
assert(Sins.canRecruit(duane))

local darlene = group("sin_pride_darlene")
assert(Sins.onSpawn(darlene, actors[darlene.id]))
assert(Sins.action(darlene, "ordinary_address", player))
assert(Sins.action(darlene, "royal_address", player))
assert(player.inv.items[5].kind == "Base.MakeupCase_Professional")
assert(not Sins.action(darlene, "royal_address", player))
print("Five Sins PASS: sweets, jewelry, water, duel, royal address")
