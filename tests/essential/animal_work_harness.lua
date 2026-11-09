-- SPDX-License-Identifier: MIT
local SC, F = SurvivorCompanion, FarmLifecycleFixture
local A, U = SC.AnimalWork, SC.GameplayUtil
local checks = 0
local function check(okay, message)
    checks = checks + 1
    assert(okay, "chicken check " .. checks .. ": " .. message)
end
local function fresh(width, height)
    SC.FarmWork.reset()
    F.reset()
    SC.Performance = nil
    F.base.farm.animals = { version = 1, zones = {} }
    SC.BaseLife.animalDocument = function() return F.base.farm.animals end
    local zone = { x = 2, y = 2, z = 0, width = width or 1, height = height or 1 }
    function zone:getId() return 42 end
    function zone:getX() return self.x end
    function zone:getY() return self.y end
    function zone:getZ() return self.z end
    function zone:getW() return self.width end
    function zone:getH() return self.height end
    function zone:isFullyStreamed() return true end
    function zone:getHutchs() return {} end
    function zone:getTroughs() return self.troughs or {} end
    DesignationZoneAnimal = { getAllZones = function() return { zone } end }
    local bird = { modData = {} }
    function bird:getAnimalID() return 100 end
    function bird:getAnimalType() return "hen" end
    function bird:getModData() return self.modData end
    function bird:getHealth() return 100 end
    function bird:isBaby() return false end
    function bird:getCustomName() return "" end
    function bird:isHeld() return false end
    function bird:getAge() return 100 end
    function bird:getData() return { isFemale = function() return true end } end
    for x = 2, 1 + zone.width do for y = 2, 1 + zone.height do
        local square = F.square(x, y)
        function square:getAnimals() return x == 2 and y == 2 and { bird } or {} end
    end end
    local trough = { x = 2, y = 2, z = 0, water = 0, feed = 0, container = F.container() }
    trough.square = F.squares["2:2:0"]
    function trough:getWater() return self.water end
    function trough:getMaxWater() return 100 end
    function trough:getCurrentFeedAmount() return self.feed end
    function trough:getMaxFeed() return 100 end
    function trough:getContainer() return self.container end
    function trough:getSquare() return self.square end
    zone.troughs = { trough }
    return zone, bird, trough
end
local zone, bird, trough = fresh()
local candidate = A.candidate(F.base)
check(candidate and candidate.operation == "animal_water", "empty trough prioritises water")
trough.water = 100
F.clock = F.clock + 1000
candidate = A.candidate(F.base)
check(candidate and candidate.operation == "animal_feed", "fed water exposes feed work")
local feed = F.item("Base.AnimalFeedBag", 50)
function feed:getAnimalFeedType() return "AnimalFeed" end
function feed:getCurrentUses() return 20 end
check(A.isFeed(feed) and A.feedAmount(feed) == 2, "uses follow native feed accounting")
check(SC.FarmWork.isFarmingSupply(feed), "dedicated feed routes to farming storage")
check(not A.isFeed(F.item("Base.Bleach", 51)), "unclassified items are not donated")
local worker = F.actor("farmer", 2, 3)
local job = F.job("animal_feed", 2, 2, candidate)
F.container({ feed }) -- unmarked stock beside the trough is not permission
local handled, reason = SC.FarmWork.update(worker, {}, job, {})
check(handled == false and reason == "farm_supply_missing", "unmarked feed is left alone")
local _, source = F.addStorage("storage:feed", "farming", { feed })
handled, reason = SC.FarmWork.update(worker, {}, job, {})
check(handled and reason == "farm_supply_taken" and feed.container == worker.inventory,
    "marked feed is borrowed as the exact native item")
check(SC.FarmWork.isItemProtected(feed), "borrowed feed is reserved against other workers")
check(SC.FarmWork.cancelActor(worker, "test_cancel") and feed.container == source,
    "cancellation returns the exact feed to its permitted source")
bird.modData.lfOddballGroupId = "story"
F.clock = F.clock + 1000
check(A.candidate(F.base) == nil, "Strange Folk animals suppress automatic pen work")
fresh(2, 1)
F.base.zones[1].x2 = 2
check(A.candidate(F.base) == nil, "a pen crossing the camp-area union is rejected")
fresh(16, 16)
check(A.candidate(F.base) == nil, "256-tile audit yields after sixteen squares")
fresh(17, 16)
check(A.candidate(F.base) == nil, "oversized pen fails closed")
local crop, animal = {}, {}
getGameTime = function() return { getWorldAgeHours = function() return 100 end } end
local choice = A.choose("farmer", crop, animal)
check(A.choose("farmer", crop, animal) == choice, "choice survives identical clock and identity")
print("ANIMAL_WORK_PASS checks=" .. checks)
