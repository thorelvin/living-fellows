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
    ArrayList = { new = function()
        local list = { rows = {} }
        function list:addAll(values) for _, item in ipairs(values) do self.rows[#self.rows+1] = item end end
        function list:size() return #self.rows end
        function list:get(index) return self.rows[index+1] end
        return list
    end }
    getGameTime = function() return { getWorldAgeHours = function() return 100 end,
        getTimeOfDay = function() return F.hour end } end
    F.base.farm.animals = { version = 1, zones = {} }
    SC.BaseLife.animalDocument = function() return F.base.farm.animals end
    local zone = { x = 2, y = 2, z = 0, width = width or 2, height = height or 1 }
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
    function bird:canBePutInHutch() return true end
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
    local feeder = setmetatable({ x=3,y=2,z=0,water=0,feed=0,
        container=F.container(),square=F.squares["3:2:0"] }, { __index=trough })
    trough.feeder=feeder
    zone.troughs = { trough, feeder }
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
local fruit = F.item("Base.Apple", 52)
function fruit:getAnimalFeedType() return "Fruits" end
function fruit:getCurrentUses() return 1 end
function fruit:getHungerChange() return -0.12 end
check(A.feedAmount(fruit) == 0.12, "food feed uses hunger rather than inherited item uses")
check(SC.FarmWork.isFarmingSupply(feed), "dedicated feed routes to farming storage")
check(not A.isFeed(F.item("Base.Bleach", 51)), "unclassified items are not donated")
local worker = F.actor("farmer", 2, 3)
local job = F.job("animal_feed", 2, 2, candidate)
check(A.allowsWorkReach(job), "validated camp pen permits bounded travel between camp areas")
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

zone, bird, trough = fresh()
local egg = F.item("Base.Egg", 80, { category = "Food" })
function egg:isFertilized() return self.fertile == true end
local nest = { eggs = { egg } }
function nest:getEgg(index)
    assert(index>=0 and index<#self.eggs,"native nest index out of range")
    return self.eggs[index + 1]
end
function nest:getEggsNb() return #self.eggs end
local hutch = { x = 2, y = 2, z = 0, square = trough.square }
function hutch:getHutch() return self end
function hutch:getMaxAnimals() return 20 end
function hutch:getMaxNestBox() return 0 end
function hutch:getNestBox() return nest end
function hutch:getAnimalInside() return { values = function() return {} end,
    size = function() return 0 end } end
function zone:getHutchs() return { hutch } end
trough.water, trough.feed, trough.feeder.feed = 100, 0, 100
candidate = A.candidate(F.base)
check(candidate and candidate.operation == "animal_egg", "nest work uses the native zero-based box")
egg.fertile = true
check(A.keepEgg({}, egg), "unproven breeding protects fertilised eggs")
egg.fertile = false
check(not A.keepEgg({}, egg), "unfertilised egg can be collected")
local worker2 = F.actor("farmer2", 2, 3)
SC.BaseLife.resident = function() return { role = "farmer", duty = true } end
SC.WorkTransport = { hasRoom = function(container, actor)
    return actor ~= nil and container ~= nil and container.full ~= true
end }
job = F.job("animal_egg", 2, 2, candidate)
local result, reason = SC.FarmWork.update(worker2, {}, job, {})
check(not result and reason == "farm_food_storage_missing" and nest.eggs[1] == egg,
    "missing food destination leaves the exact egg in the nest: " .. tostring(reason))
F.addStorage("storage:eggs", "food", {})
local marked, receipt = SC.FarmWork.animalSupport.receipt(worker2, job, "output", egg, nil, "food")
check(marked ~= nil, "selected egg can acquire an exact persistent receipt")
SC.BaseLife.updateFarmReceipt(receipt and receipt.id or marked.id, { phase = "selected" })
check(A.recoverReceipt(marked) and marked.phase == "consumed" and nest.eggs[1] == egg,
    "reload reconciliation releases an unpicked egg without cloning or removing it")
local oldConfig = U.config
U.config = function(name)
    if name == "animalCloseEnabled" then return 1 end
    return oldConfig(name)
end
check(A.hutchOperation(20.25, false, 0, 3) == nil, "birds outside retain the dusk grace period")
check(A.hutchOperation(20.25, false, 3, 3) == "animal_close", "all birds inside permits dusk closing")
check(A.hutchOperation(21.1, false, 0, 3) == "animal_close", "grace expiry permits closing")
check(A.hutchOperation(7, true, 3, 3) == "animal_open", "native dawn opens a closed hutch")
check(A.hutchOperation(10, false, 0, 3) == nil, "already open is an idempotent no-op")
U.config = oldConfig
nest.eggs={}
F.clock=F.clock+1000
check(A.candidate(F.base)==nil,"empty native nests are never indexed")
print("ANIMAL_WORK_PASS checks=" .. checks)
