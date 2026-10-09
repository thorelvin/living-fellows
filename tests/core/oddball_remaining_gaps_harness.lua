-- SPDX-License-Identifier: MIT
-- Exercise the real inventory, work-intent, and one-shot wake transitions.
local SC = SurvivorCompanion
local now = 1000
local checks = 0
local function check(value, reason)
    checks = checks + 1
    assert(value, "remaining gap " .. checks .. ": " .. reason)
end
local function inventory()
    local bag = { items = {} }
    function bag:Remove(item)
        for index, existing in ipairs(self.items) do
            if existing == item then
                table.remove(self.items, index)
                item.container = nil
                return true
            end
        end
        return false
    end
    return bag
end
local function add(bag, kind)
    local item = { kind = kind, container = bag, data = {}, condition = 10 }
    function item:getContainer() return self.container end
    function item:getCondition() return self.condition end
    function item:setCondition(value) self.condition = value end
    bag.items[#bag.items + 1] = item
    return item
end
local U = {}
SC.GameplayUtil = U
function U.call(object, method, ...)
    local f = object and object[method]
    if type(f) ~= "function" then return nil, false end
    return f(object, ...), true
end
function U.inventory(actor) return actor and actor.inv end
function U.inventoryItemsDeep(bag) return bag and bag.items or {} end
function U.addItem(bag, kind) return bag and add(bag, kind) end
function U.itemType(item) return item and item.kind end
function U.modData(item) return item and item.data end
function U.nowMs() return now end
function U.isValidActor(actor) return actor ~= nil end
function U.idOf(actor) return actor and actor.id end
function U.position(actor) return actor.x, actor.y, actor.z end
function U.distance(a, b)
    return math.sqrt((a.x - b.x)^2 + (a.y - b.y)^2
        + ((a.z - b.z) * 3)^2)
end
function U.canSee() return true end
function U.say(actor, line) actor.line = line end
function U.consumeItem(bag, item) return bag:Remove(item) end
function U.inventoryContains(bag, item)
    for _, other in ipairs(bag.items) do
        if other == item then return true end
    end
    return false
end
function U.transferItemVerified(source, target, item)
    if not source or not target or item.container ~= source then return false end
    if target.reject == item.kind then return false end
    if not source:Remove(item) then return false end
    target.items[#target.items + 1] = item
    item.container = target
    return true
end
local grave = { x = 10, y = 10, z = 0, dug = false }
local partner = { x = 9, y = 10, z = 0, dug = false }
function U.gridSquare(x, y, z)
    if x == 10 and y == 10 and z == 0 then return grave end
    if x == 9 and y == 10 and z == 0 then return partner end
end
function U.squareSpecialObjects(square, callback)
    if square.dug then callback({ getName = function() return "EmptyGraves" end }) end
end
local lastIntent, attackCount = nil, 0
function U.move(actor, mode, intent)
    lastIntent = intent
    if intent.action == "attack_melee" then attackCount = attackCount + 1 end
    return true
end
local actors = {}
SC.Registry = {
    byId = function(id) return actors[id] end,
    living = function()
        local result = {}
        for _, record in pairs(actors) do result[#result + 1] = record.actor end
        return result
    end,
}
local residents = {}
SC.BaseLife = { resident = function(id) return residents[id] end }
local standings = {}
SC.Factions = {
    adjustStanding = function(id, amount)
        standings[id] = (standings[id] or 0) + amount
        return true
    end,
    forceStanding = function(id, standing)
        standings[id] = standing
        return true
    end,
}
local workActive = false
SC.NativeActions = {
    isWorkActive = function() return workActive end,
    workKind = function() return "dig_grave" end,
    finishWork = function() return true end,
    leaveSeating = function(actor) actor.leftBed = true; return true end,
}
local function actor(id, x, y)
    local a = { id = id, x = x, y = y, z = 0, inv = inventory() }
    function a:setPrimaryHandItem(item) self.hand = item end
    function a:setAsleep(value) self.asleep = value end
    function a:isOnBed() return self.onBed == true end
    actors[id] = { actor = a }
    return a
end
local player = actor("player", 10, 11)
local merle = actor("merle", 10, 10)
local group = { id = "merle-scene", members = { { actorId = "merle" } },
    oddball = { id = "digger_merle_lusby",
        site = { grave = { x = 10, y = 10, z = 0 },
            spawn = { x = 10, y = 10, z = 0 } } } }
check(SC.OddballMerle.onSpawn(group, merle), "Merle spawns with own shovel")
check(#merle.inv.items == 1 and merle.inv.items[1].condition == 3,
    "one worn original shovel")
local spare = add(player.inv, "Base.Shovel")
spare.condition = 2
check(SC.OddballMerle.menuOptions(group, player)[2].enabled == false,
    "a worse shovel cannot trigger the faster dig")
spare.condition = 10
local options = SC.OddballMerle.menuOptions(group, player)
check(options[2].enabled == true, "shovel-help option is reachable")
check(SC.OddballMerle.action(group, "lend_shovel", player),
    "player can lend a second shovel")
check(spare.container == merle.inv and merle.hand == spare,
    "real shovel changes owner and hand")
workActive = true
check(SC.OddballMerle.update(merle, player, nil,
    { mode = "merle_dig" }, group), "native grave dig starts")
check(lastIntent.action == "dig_grave" and lastIntent.durationTicks == 75
    and lastIntent.tool == spare, "loan halves native grave action")
workActive = false
grave.dug, partner.dug = true, true
check(SC.OddballMerle.pulse(group, player), "completed grave checked")
check(group.oddball.stage == "gold_found", "gold waits for actual grave")
player.inv.reject = "Base.Shovel"
check(not SC.OddballMerle.action(group, "claim_gold", player)
    and group.oddball.goldClaimed ~= true,
    "rejected shovel return does not consume gold claim")
local pendingGold = false
for _, item in ipairs(merle.inv.items) do
    if item.data.lfMerleGold == true then pendingGold = true end
end
check(pendingGold and spare.container == merle.inv,
    "failed reward transfer restores both items")
player.inv.reject = nil
check(SC.OddballMerle.action(group, "claim_gold", player),
    "reward and shovel returned")
check(spare.container == player.inv and group.oddball.goldClaimed == true,
    "loan is back with player")

local second = actor("merle-2", 10, 10)
local secondGroup = { id = "merle-scene-2",
    members = { { actorId = "merle-2" } },
    oddball = { id = "digger_merle_lusby",
        site = { grave = { x = 10, y = 10, z = 0 },
            spawn = { x = 10, y = 10, z = 0 } } } }
grave.dug, partner.dug = false, false
SC.OddballMerle.onSpawn(secondGroup, second)
local helper = actor("helper", 11, 10)
actors.helper.recruited = true
residents.helper = { role = "corpsekeeper" }
workActive = true
check(SC.OddballMerle.update(second, player, nil,
    { mode = "merle_dig" }, secondGroup), "gravekeeper assists")
check(lastIntent.durationTicks == 75,
    "nearby recruited corpsekeeper speeds real digging")
residents.helper = nil

local dancer = actor("dancer", 10, 10)
local dancerGroup = { id = "dancer-scene", members = { { actorId = "dancer" } },
    oddball = { id = "sleeping_it_off", stage = "sleeping" } }
add(dancer.inv, "Base.BeerEmpty")
local wakeOptions = SC.OddballSleeper.menuOptions(dancerGroup, player)
check(#wakeOptions == 2 and wakeOptions[2].id == "wake_rough",
    "loud wake is offered next to gentle wake")
check(SC.OddballSleeper.action(dancerGroup, "wake_rough", player),
    "shout triggers rough wake")
check(dancerGroup.oddball.stage == "startled"
    and standings[dancerGroup.id] == -12 and dancer.leftBed,
    "rough wake stands dancer and costs a little trust")
local startle = SC.OddballSleeper.intentFor(dancer, player, {}, dancerGroup)
check(startle.mode == "dancer_startled_swing", "one-shot intent selected")
check(SC.OddballSleeper.update(dancer, player, nil, startle, dancerGroup),
    "native bottle swing accepted")
check(attackCount == 1 and lastIntent.weapon.kind == "Base.SmashedBottle"
    and lastIntent.target == player and dancerGroup.oddball.stage == "bag_quest",
    "one real weapon swing then calm down")
SC.OddballSleeper.update(dancer, player, nil, startle, dancerGroup)
check(attackCount == 1, "old intent cannot repeat swing")
local secondDancer = actor("dancer-2", 10, 10)
local secondDancerGroup = { id = "dancer-scene-2",
    members = { { actorId = "dancer-2" } },
    oddball = { id = "sleeping_it_off", stage = "sleeping" } }
add(secondDancer.inv, "Base.BeerEmpty")
check(SC.OddballSleeper.action(secondDancerGroup, "hurt", player),
    "an actual hit uses same startle path")
now = now + 3100
SC.OddballSleeper.pulse(secondDancerGroup, player, now)
check(secondDancerGroup.oddball.stage == "bag_quest",
    "expired startle never traps dancer in combat")
print("ODDBALL_REMAINING_GAPS_PASS checks=" .. checks)
