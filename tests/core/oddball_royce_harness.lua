-- SPDX-License-Identifier: MIT
local SC = SurvivorCompanion
local visible = true
local thief = { id = "royce", x = 0, y = 0, z = 0,
    inv = { items = {} } }
local player = { id = "player", x = 1, y = 0, z = 0,
    inv = { items = {} } }
local pack = { items = {} }
local companion = { id = "fellow", x = 1, y = 0, z = 0,
    inv = { items = {} } }
local hammer = { kind = "Base.Hammer", container = pack, data = {} }
pack.items[1] = hammer
local member = { actorId = "royce", hibernated = false }
local site = { kind = "roamer", spawn = { x = 0, y = 0, z = 0 },
    stashEntry = { x = 10, y = 0, z = 0 },
    stashSpawns = { { x = 10, y = 1, z = 0 },
        { x = 11, y = 1, z = 0 }, { x = 12, y = 1, z = 0 } },
    house = { id = "stash", anchor = { x = 10, y = 0, z = 0 },
        bounds = {} } }
local group = { id = "royce-group", standing = "Neutral",
    members = { member }, oddball = { id = "trickster_lucky_royce",
        stage = "unmet", site = site } }
local spawned = {}
local horde = {}
local siteSerial = 0
SC.GameplayUtil = {
    nowMs = function() return 1000 end,
    isValidActor = function(v) return v ~= nil end,
    idOf = function(v) return v.id end,
    position = function(v) return v.x, v.y, v.z end,
    distance = function(a, b)
        return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
    end,
    canSee = function() return visible end,
    inventory = function(v) return v.inv end,
    inventoryItemsDeep = function(inv)
        return inv == companion.inv and pack.items or inv.items
    end,
    itemType = function(item) return item.kind end,
    modData = function(item) return item.data end,
    isZombie = function(item) return item.zombie == true end,
    config = function() return false end,
    gridSquare = function(x, y, z) return { x = x, y = y, z = z } end,
    isSafeSpawnSquare = function() return true end,
    call = function(v, method)
        if method == "getContainer" then return v.container, true end
        if method == "getMovingObjects" then
            local list = {}
            for _, zombie in ipairs(spawned) do
                if zombie.x == v.x and zombie.y == v.y then
                    list[#list + 1] = zombie
                end
            end
            return list, true
        end
        if method == "getZombieList" then return horde, true end
        return nil, false
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
    say = function(actor, line) actor.lastLine = line return true end,
}
SC.NativeList = { size = function(list) return #list end,
    get = function(list, index) return list[index + 1] end }
SC.Registry = { living = function() return { companion } end,
    byId = function(id)
        if id == "royce" and not member.hibernated then
            return { actor = thief } end
        if id == "fellow" then return { actor = companion, recruited = true } end
        return nil
    end }
SC.Factions = { hibernateOddballRoamer = function(id)
    assert(id == group.id)
    member.hibernated = true
    return true
end, forceStanding = function() return true end }
SC.Oddballs = { findRoamerLandmark = function()
    siteSerial = siteSerial + 1
    local x = siteSerial * 200
    return { spawn = { x = x, y = 0, z = 0 },
        house = { id = "road" .. siteSerial,
            anchor = { x = x, y = 0, z = 0 }, bounds = {} } }
end }
addZombiesInOutfit = function(x, y, z)
    local zombie = { x = x, y = y, z = z, zombie = true, data = {} }
    spawned[#spawned + 1] = zombie
    return { zombie }
end
getCell = function() return {} end

local Royce = SC.OddballRoyce
assert(Royce.onSpawn(group, thief))
assert(Royce.action(group, "follow_stash", player))
player.x, companion.x, thief.x = 10, 10, 10
assert(Royce.pulse(group, player, 1000))
assert(group.oddball.stashSpawned == 3)
assert(group.oddball.stolen == true)
assert(hammer.container == thief.inv)
assert(hammer.data.lfRoyceStolenGroupId == group.id)
assert(#thief.inv.items == 1 and #pack.items == 0)
visible = false
Royce.pulse(group, player, 2000)
Royce.pulse(group, player, 48000)
assert(member.hibernated and group.oddball.awaitingStageSite)
Royce.pulse(group, player, 49000)
assert(group.oddball.stage == "arriving")
member.hibernated = false
thief.x, player.x, companion.x = 200, 201, 201
visible = true
assert(Royce.onSpawn(group, thief))
assert(group.oddball.visit == 2)
local dollar = { kind = "Base.Money", container = player.inv, data = {} }
player.inv.items[1] = dollar
assert(Royce.action(group, "buy_back", player))
assert(hammer.container == player.inv and dollar.container == thief.inv)
assert(#pack.items == 0, "the stolen item is not duplicated")
assert(Royce.action(group, "accept_apology", player))
visible = false
Royce.pulse(group, player, 50000)
Royce.pulse(group, player, 96000)
Royce.pulse(group, player, 97000)
member.hibernated = false
thief.x, player.x = 400, 401
visible = true
assert(Royce.onSpawn(group, thief))
assert(group.oddball.visit == 3)
for index = 1, 6 do
    horde[index] = { x = 420 + index, y = 0, z = 0 }
end
assert(Royce.pulse(group, player, 98000))
assert(group.oddball.stage == "warned")
assert(Royce.canRecruit(group))
print("Royce PASS: bounded stash, one exact theft, buyback, three meetings, real horde")
