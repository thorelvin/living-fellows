-- SPDX-License-Identifier: MIT
-- Focused behavior checks for the six remaining Phase 2 encounters.
local SC = SurvivorCompanion
local hour, now, nextAnimalId = 100, 1000, 0
local animals, onlineAnimals, actors = {}, {}, {}
local room = { getName = function() return "motelroom" end }
local outside = { getName = function() return "outside" end }

local function inventory()
    return { items = {} }
end
local function actor(x, y)
    return { x = x, y = y, z = 0, inv = inventory(),
        square = { x = x, y = y, z = 0, room = outside } }
end
local function group(id, member, site)
    local g = { id = id, standing = "Neutral", house = {
        bounds = { x1 = 0, x2 = 20, y1 = 0, y2 = 20 } },
        members = { { actorId = id } }, oddball = { id = id,
            site = site or { spawn = { x = 5, y = 5, z = 0 } } } }
    actors[id] = member
    return g
end
local function method(object, name, ...)
    if not object then return nil, false end
    local f = object[name]
    if type(f) == "function" then return f(object, ...), true end
    if name == "getRoom" then return object.room, true end
    if name == "getName" then return object.name, true end
    if name == "getContainer" then return object.container, true end
    if name == "getWorldAgeHours" then return hour, true end
    return nil, false
end
SC.GameplayUtil = {
    call = method,
    position = function(value)
        return value and value.x, value and value.y, value and value.z or 0
    end,
    squareOf = function(value) return value and value.square or value end,
    gridSquare = function(x, y, z)
        return { x = x, y = y, z = z,
            room = x <= 20 and y <= 20 and room or nil }
    end,
    isSafeSpawnSquare = function() return true end,
    canSee = function() return false end,
    nowMs = function() return now end,
    config = function() return true end,
    say = function(value, line) value.lastSaid = line return true end,
    inventory = function(value) return value and value.inv end,
    inventoryItemsDeep = function(value) return value.items end,
    itemType = function(value) return value.fullType end,
    addItem = function(value, kind)
        local item = { fullType = kind, container = value }
        value.items[#value.items + 1] = item
        return item
    end,
    transferItemVerified = function(source, destination, item)
        for i, value in ipairs(source.items) do
            if value == item then
                table.remove(source.items, i)
                destination.items[#destination.items + 1] = item
                item.container = destination
                return true
            end
        end
        return false
    end,
    instanceOf = function() return false end,
    hasMethod = function(value, name) return type(value[name]) == "function" end,
}
SC.Registry = { byId = function(id)
    return actors[id] and { actor = actors[id] }
end }
SC.Config = { get = function() return 4 end }
SC.FactionBehavior = { fortifyOddball = function() return true end }
SC.Factions = {
    forceStanding = function(id, standing)
        for _, g in pairs(SC_TEST_GROUPS) do
            if g.id == id then g.standing = standing end
        end
        return true
    end,
    adjustStanding = function(id, delta)
        for _, g in pairs(SC_TEST_GROUPS) do
            if g.id == id then g.reputation = (g.reputation or 0) + delta end
        end
        return true
    end,
}
SC.FactionRecruitment = { summary = function() return { status = "candidate" } end }
SC_TEST_GROUPS = {}
AnimalDefinitions = { getDef = function()
    return { getBreedByName = function(self, name) return name end }
end }
local animalCell = {}
function animalCell:getAnimals()
    self.scans = (self.scans or 0) + 1
    local loaded = {}
    for _, animal in pairs(animals) do
        if animal.inWorld then loaded[#loaded + 1] = animal end
    end
    return loaded
end
getCell = function() return animalCell end
getGameTime = function() return { getWorldAgeHours = function() return hour end } end
addAnimal = function(cell, x, y, z, kind, breed)
    nextAnimalId = nextAnimalId + 1
    local value = { x = x, y = y, z = z, kind = kind, breed = breed,
        id = nextAnimalId, onlineId = 100 + nextAnimalId, data = {} }
    local square = { getAnimals = function()
        return animals[value.id] == value and value.inWorld and { value } or {}
    end }
    function value:setCustomName(name) self.name = name end
    function value:setWild(wild) self.wild = wild end
    function value:getModData() return self.data end
    function value:addToWorld()
        self.inWorld = true
        animals[self.id], onlineAnimals[self.onlineId] = self, self
    end
    function value:getAnimalID() return self.id end
    function value:getOnlineID() return self.onlineId end
    function value:getAnimalType() return self.kind end
    function value:getBreed() return {
        getName = function() return self.breed end }
    end
    function value:getCustomName() return self.name end
    function value:getSquare()
        return animals[self.id] == self and self.inWorld and square or nil
    end
    function value:getHealth() return 100 end
    function value:pathToCharacter() end
    function value:pathToLocation() end
    return value
end
getAnimal = function(id)
    local animal = onlineAnimals[id]
    return animal and animals[animal.id] == animal and animal or nil
end

local player = actor(6, 5)
local gale = group("grocery_gale_mercer", actor(5, 5))
SC_TEST_GROUPS[#SC_TEST_GROUPS + 1] = gale
assert(SC.OddballGale.onSpawn(gale, actors[gale.id]))
assert(#actors[gale.id].inv.items == 4, "Gale's initial stock must be finite")
SC.OddballGale.onSpawn(gale, actors[gale.id])
assert(#actors[gale.id].inv.items == 4, "Gale must not duplicate gear")
assert(SC.OddballGale.action(gale, "shoplift", player, { count = 1 }))
assert(gale.oddball.stage == "warned", "one exact theft should warn")
assert(SC.OddballGale.action(gale, "shoplift", player, { count = 1 }))
assert(gale.standing == "Hostile", "second theft should turn Gale hostile")

local butch = group("butcher_ambrose_kittredge", actor(5, 5))
SC_TEST_GROUPS[#SC_TEST_GROUPS + 1] = butch
assert(SC.OddballButch.onSpawn(butch, actors[butch.id]))
player.square.room = { getName = function() return "storage" end }
SC.OddballButch.pulse(butch, player, now)
assert(butch.oddball.stage == "following_back", "back-room entry should trigger pursuit")
SC.OddballButch.pulse(butch, player, now + 2100)
assert(butch.standing == "Hostile", "Butch's pursuit should become real combat")
player.square.room = outside

local cecil = group("gunshop_cecil_haskins", actor(5, 5))
SC_TEST_GROUPS[#SC_TEST_GROUPS + 1] = cecil
player.x = 8
SC.OddballCecil.pulse(cecil, player, now)
assert(cecil.oddball.stage == "warned", "crossing Cecil's line should warn")
player.x = 13
SC.OddballCecil.pulse(cecil, player, now + 100)
assert(cecil.oddball.stage == "open", "backing off should comply")
player.x = 8
SC.OddballCecil.pulse(cecil, player, now + 200)
assert(cecil.standing == "Hostile", "second crossing should not reset the grace")
player.x = 6

local hollisSite = { spawn = { x = 5, y = 5, z = 0 },
    coop = { x = 7, y = 7, z = 0, enclosed = true } }
local hollis = group("duchess_hollis_burkett", actor(5, 5), hollisSite)
SC_TEST_GROUPS[#SC_TEST_GROUPS + 1] = hollis
assert(SC.OddballHollis.onSpawn(hollis, actors[hollis.id]))
assert(nextAnimalId == 1 and animals[1].name == "Duchess"
    and animals[1].wild == false, "Duchess must be a named tame vanilla sow")
local duchess = animals[1]
local duchessRecord = hollis.oddball.animals.slots[1]
assert(duchessRecord.id == 1 and duchessRecord.onlineId == 101,
    "persistent and online animal IDs must be stored separately")
duchessRecord.onlineId = nil
assert(SC.OddballAnimals.find(hollis, 1) == duchess
    and duchessRecord.onlineId == 101,
    "legacy id-only animal slots must migrate when the animal is loaded")
SC.OddballHollis.onSpawn(hollis, actors[hollis.id])
assert(nextAnimalId == 1, "Hollis must not duplicate Duchess")
animals[1] = nil
assert(SC.OddballAnimals.status(hollis, 1, player) == "unloaded",
    "an unloaded animal must not be pronounced dead")
SC.OddballHollis.onSpawn(hollis, actors[hollis.id])
assert(nextAnimalId == 1, "unloaded Duchess must never be cloned on load")
animals[1] = duchess
function duchess:getHealth() return 0 end
SC.OddballHollis.pulse(hollis, player, now)
assert(hollis.standing == "Hostile",
    "Duchess's confirmed death should change Hollis's standing")
assert(SC.OddballHollis.action(hollis, "animal_hurt", player))
assert(hollis.standing == "Hostile", "harming Duchess should provoke Hollis")

local partySite = { spawn = { x = 5, y = 5, z = 0 },
    partyDoor = { x = 5, y = 4, z = 0, objectIndex = 2, kind = "door" },
    partyWindow = { x = 6, y = 5, z = 0, objectIndex = 3, kind = "window" },
    coop = { x = 5, y = 6, z = 0, enclosed = true } }
local party = group("party_room12_delbert", actor(5, 5), partySite)
SC_TEST_GROUPS[#SC_TEST_GROUPS + 1] = party
assert(SC.OddballRoom12.onSpawn(party, actors[party.id]))
assert(#party.jobs == 2 and party.jobs[1].kind == "barricade"
    and party.jobs[2].kind == "barricade",
    "Room 12 should use real faction barricade jobs")
assert(nextAnimalId == 2 and animals[2].name == "Sweet Pea")
local sweetPeaRecord = party.oddball.animals.slots[1]
sweetPeaRecord.onlineId = duchessRecord.onlineId
assert(SC.OddballAnimals.find(party, 1) == animals[2]
    and sweetPeaRecord.onlineId == 102,
    "reused online IDs must not resolve to another group's animal")
animals[2].onlineId = -1
sweetPeaRecord.onlineId = nil
assert(SC.OddballAnimals.find(party, 1) == animals[2]
    and sweetPeaRecord.onlineId == nil,
    "single-player animals without online IDs must remain findable")
animals[2].onlineId = 102
for _, job in ipairs(party.jobs) do job.status = "completed" end
SC.OddballRoom12.pulse(party, player, now)
assert(party.oddball.stage == "party", "finished barricades should start the party")
SC.GameplayUtil.addItem(player.inv, "Base.Whiskey")
assert(SC.OddballRoom12.action(party, "trade_supplies", player))
assert(party.oddball.tradeCount == 1 and party.oddball.rewardIndex == 2,
    "party barter should consume a real item and deliver a finite reward")
player.square.room = room
SC.OddballRoom12.pulse(party, player, now + 100)
assert(party.standing == "Hostile", "breaking into Room 12 should end the truce")
player.square.room = outside

local rabbitPoints = {}
for i = 1, 10 do rabbitPoints[i] = { x = 5 + i, y = 8, z = 0 } end
local juneSite = { spawn = { x = 5, y = 5, z = 0 },
    animalSpawns = rabbitPoints, house = { bounds = {
        x1 = 0, x2 = 20, y1 = 0, y2 = 20 } } }
local june = group("ranger_june_whitlock", actor(5, 5), juneSite)
SC_TEST_GROUPS[#SC_TEST_GROUPS + 1] = june
assert(SC.OddballJune.onSpawn(june, actors[june.id]))
assert(nextAnimalId == 12, "June should get all ten rabbits")
for slot, rabbit in ipairs(june.oddball.animals.slots) do
    assert(animals[rabbit.id] and animals[rabbit.id].name == rabbit.name
        and animals[rabbit.id].wild == false,
        "every rabbit must retain its native ID and name")
end
local scansBefore = animalCell.scans or 0
for _, rabbit in ipairs(june.oddball.animals.slots) do
    animals[rabbit.id].onlineId = -1
    rabbit.onlineId = nil
end
for slot, rabbit in ipairs(june.oddball.animals.slots) do
    assert(SC.OddballAnimals.find(june, slot) == animals[rabbit.id],
        "single-player lookup must find every loaded rabbit")
end
assert((animalCell.scans or 0) == scansBefore + 1,
    "ten rabbit lookups should share one native loaded-cell scan")
for _, rabbit in ipairs(june.oddball.animals.slots) do
    animals[rabbit.id].onlineId = 100 + rabbit.id
end
SC.OddballJune.onSpawn(june, actors[june.id])
assert(nextAnimalId == 12, "reloading June must not clone rabbits")
assert(SC.OddballJune.action(june, "quiz_prompt", player))
local options = SC.OddballJune.menuOptions(june, player)
local right
for _, option in ipairs(options) do
    if option.id == "quiz_answer" and option.payload.answer == option.payload.slot then
        right = option
    end
end
assert(right, "June's quiz must include the rabbit's actual name")
assert(SC.OddballJune.action(june, right.id, player, right.payload))
assert(june.reputation == 7, "correct name should earn standing")
hour = 149
assert(SC.OddballAnimals.find(june, 7) ~= nil, "Juniper must be findable before escape")
SC.OddballJune.pulse(june, player, now)
assert(june.oddball.juniper and june.oddball.juniper.stage == "escaping",
    "Juniper should request a native path to a real distant tile: "
        .. tostring(june.oddball.spawnHour) .. ":"
        .. tostring(june.oddball.stage) .. ":"
        .. tostring(june.oddball.juniper and june.oddball.juniper.stage)
        .. ":" .. tostring(hour))
local juniper = animals[june.oddball.animals.slots[7].id]
juniper.x = june.oddball.juniper.target.x
juniper.y = june.oddball.juniper.target.y
SC.OddballJune.pulse(june, player, now + 100)
assert(june.oddball.juniper.stage == "lost",
    "June should report escape only after Juniper actually travels")
player.x, player.y = juniper.x, juniper.y
SC.OddballJune.pulse(june, player, now + 200)
assert(june.oddball.juniper.stage == "found" and june.reputation == 37,
    "finding the same native rabbit within three days should earn trust")
SC.OddballJune.pulse(june, player, now + 300)
assert(june.reputation == 37,
    "Juniper's rescue standing must be awarded exactly once")
player.x, player.y = 6, 5
assert(SC.OddballJune.action(june, "animal_hurt", player))
assert(june.standing == "Hostile", "June must defend her rabbits")
local adoptedGroup = group("adopted_hen_fixture", actor(5, 5))
local adoptedHen = addAnimal(animalCell, 8, 8, 0, "hen", "rhodeisland")
adoptedHen:setCustomName("Lucky")
adoptedHen:addToWorld()
assert(SC.OddballAnimals.adopt(adoptedGroup, 1, adoptedHen, "hen"))
local adoptedRecord = adoptedGroup.oddball.animals.slots[1]
assert(adoptedRecord.id == adoptedHen.id
    and adoptedRecord.onlineId == adoptedHen.onlineId
    and adoptedRecord.breed == "rhodeisland"
    and SC.OddballAnimals.find(adoptedGroup, 1) == adoptedHen,
    "adopted animals must save both native IDs and their breed")
print("Phase 2 encounter behavior PASS")
