-- SPDX-License-Identifier: MIT
local SC, F = LivingFellows, FarmLifecycleFixture
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
    DesignationZoneAnimal = { getAllZones = function() return { zone } end,
        getZoneById = function(id) return id==42 and zone or nil end }
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
    zone.registered={bird}
    function zone:getAnimalsInZone()
        local rows=self.registered
        rows.size=function(self) return #self end
        return rows
    end
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
    function trough:getObjectIndex() return self.removed and -1 or 0 end
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
trough.feeder.removed = true
local removedHandled, removedReason = SC.FarmWork.update(worker, {}, job, {})
check(not removedHandled and removedReason == "animal_device_unavailable",
    "removing a trough invalidates its retained world reference")
trough.feeder.removed = false
F.container({ feed }) -- unmarked stock beside the trough is not permission
local handled, reason = SC.FarmWork.update(worker, {}, job, {})
check(handled == false and reason == "farm_supply_missing", "unmarked feed is left alone")
local _, source = F.addStorage("storage:feed", "farming", { feed })
handled, reason = SC.FarmWork.update(worker, {}, job, {})
check(handled and reason == "farm_supply_taken" and feed.container == worker.inventory,
    "marked feed is borrowed as the exact native item")
check(SC.FarmWork.isItemProtected(feed), "borrowed feed is reserved against other workers")
local requestAny,route=SC.Navigation.requestAny,nil
SC.Navigation.requestAny=function(subject,targets,mode,intent)
    route=intent return true,"farm_approaching"
end
SC.FarmWork.update(worker,{},job,{})
check(route and route.workReach==true and route.workCampOnly==true,
    "animal approach carries its validated bounded-transit permission into navigation")
SC.FarmWork.animalSupport.approach(worker,trough.feeder.square,trough.feeder)
check(route.workReach==false,"ordinary crop approaches retain camp-only travel")
SC.Navigation.requestAny=requestAny
local wasActive, cancelWork = SC.NativeActions.isWorkActive, SC.NativeActions.cancelWork
SC.NativeActions.isWorkActive = function() return true end
SC.NativeActions.cancelWork = function() return false, "native_cleanup_pending" end
local timedOut = { animalWork = { operation="animal_feed", before=0, startedAt=F.clock-120001 } }
handled, reason = A.update(worker, {}, job, {}, timedOut)
check(handled and reason=="native_cleanup_pending" and timedOut.animalWork~=nil
    and SC.FarmWork.isItemProtected(feed), "timeout retains ownership while native cleanup is pending")
local interruptedConfig=U.config
U.config=function(name) if name=="animalWorkEnabled" then return 0 end return interruptedConfig(name) end
handled,reason=A.update(worker,{},job,{},timedOut)
check(handled and reason=="native_cleanup_pending" and timedOut.animalWork~=nil,
    "disabling or interrupting chicken work also retains pending native cleanup")
U.config=interruptedConfig
local finishWork=SC.NativeActions.finishWork
SC.NativeActions.isWorkActive=function() return false end
SC.NativeActions.finishWork=function() return false,"native_hand_cleanup_pending" end
timedOut.animalWork.startedAt=F.clock
handled,reason=A.update(worker,{},job,{},timedOut)
check(handled and reason=="native_hand_cleanup_pending" and timedOut.animalWork~=nil,
    "completed effects wait for native hand restoration without releasing the job")
SC.NativeActions.finishWork=finishWork
SC.NativeActions.isWorkActive, SC.NativeActions.cancelWork = wasActive, cancelWork
check(SC.FarmWork.cancelActor(worker, "test_cancel") and feed.container == source,
    "cancellation returns the exact feed to its permitted source")
bird.modData.lfOddballGroupId = "story"
F.clock = F.clock + 1000
check(A.candidate(F.base) == nil, "Strange Folk animals suppress automatic pen work")
fresh(2, 1)
F.base.zones[1].x2 = 2
candidate=A.candidate(F.base)
check(candidate and A.allowsWorkReach(F.job("animal_water",2,2,candidate)),
    "a pen straddling the camp boundary can work through the bounded reach band")
fresh(2,1)
F.base.zones[1].x1,F.base.zones[1].x2=-40,-27
candidate=A.candidate(F.base)
check(candidate and A.allowsWorkReach(F.job("animal_water",2,2,candidate)),
    "the whole pen may reach exactly thirty tiles beyond camp")
F.base.zones[1].x2=-28
check(not A.allowsWorkReach(F.job("animal_water",2,2,candidate)),
    "changing the camp boundary immediately invalidates an old animal route")
check(A.candidate(F.base)==nil,"a pen with its far edge thirty-one tiles out is rejected")
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
local hutch = { x = 2, y = 2, z = 0, square = trough.square, occupants={} }
function hutch:getHutch() return self end
function hutch:getObjectIndex() return 0 end
function hutch:getMaxAnimals() return 20 end
function hutch:getMaxNestBox() return 0 end
function hutch:getAnimalInNestBox() return self.nestingBird end
function hutch:getNestBox() return nest end
function hutch:getAnimalInside() return { values = function() return self.occupants end,
    size = function() return #self.occupants end } end
function hutch:isDoorClosed() return self.closed==true end
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
do
    local farm, B = SC.FarmWork, SC.BaseLife
    local marker = farm.ITEM_MARKER
    local function inventorySearch(container, predicate)
        for _, item in ipairs(container.items) do
            if predicate(item) then return item end
            local nested = item:getInventory()
            local found = nested and inventorySearch(nested, predicate)
            if found then return found end
        end
    end
    worker2.inventory.getFirstEvalRecurse = inventorySearch
    local function selectEgg(item, target)
        nest.eggs = {item}
        target = target or F.job("animal_egg", 2, 2, candidate)
        local receipt = farm.animalSupport.receipt(worker2, target, "output", item, nil, "food")
        target.target.eggReceiptId = receipt.id
        SC.BaseLife.updateFarmReceipt(receipt.id, {phase="selected"})
        nest.eggs = {}
        return receipt, target
    end
    local function shell(id)
        local item=F.item("Base.Egg", id, {category="Food"})
        item.isFertilized=egg.isFertilized
        return item
    end
    -- Live selection and interleaving through the public job/cancellation paths.
    local originalStart = SC.NativeActions.startAnimal
    SC.NativeActions.startAnimal = SC.NativeActions.startFarm
    local function startEgg(item)
        nest.eggs = {item}
        local current = F.job("animal_egg", 2, 2, candidate)
        current.reservedBy = worker2.id
        local started, why = farm.update(worker2, {}, current, {})
        if why == "farm_previous_supplies_returned" then started, why = farm.update(worker2, {}, current, {}) end
        check(started and why == "farm_animal_egg_active", "farmer selects a real nest egg: "..tostring(why))
        local receipt = B.farmReceipt(current.target.eggReceiptId)
        check(receipt and receipt.phase=="selected" and item.modData[marker]==receipt.id, "selected exact egg is marked")
        return current, receipt
    end
    local player = F.actor("egg-collector", 2, 3)
    local stolen, spare = shell(2010), shell(2011)
    local live, liveReceipt = startEgg(stolen)
    nest.eggs = {spare}
    player.inventory:AddItem(stolen)
    check(farm.isItemProtected(stolen), "player egg carries the live reservation")
    check(farm.cancelActor(worker2,"egg_interrupted") and liveReceipt.phase=="consumed"
        and liveReceipt.blocker=="animal_egg_taken_elsewhere", "live cancel settles the missing egg")
    check(farm.canCancelJob(live.id) and not farm.isItemProtected(stolen)
        and stolen.modData[marker]==nil and player.inventory:contains(stolen) and #player.inventory.items==1
        and #nest.eggs==1 and nest.eggs[1]==spare, "cancel releases only the player's actual egg")
    local nextJob = F.job("animal_open", 2, 2, candidate)
    nextJob.target.operation = "animal_open"
    for pulse=1,3 do farm.update(worker2, {}, nextJob, {}) end
    check(nextJob.state=="completed", "same farmer completes the next chore after a cancelled egg")
    -- Finish an already-stopped grab in place, without cancelling or replaying pickup.
    local racing = shell(2012)
    local stopped, stoppedReceipt = startEgg(racing)
    F.native[worker2].active = false
    nest.eggs = {spare}
    player.inventory:AddItem(racing)
    local starts = #F.nativeStarts
    for pulse=1,4 do farm.update(worker2, {}, stopped, {}) end
    check(stopped.state=="completed" and stoppedReceipt.phase=="consumed" and #F.nativeStarts==starts
        and nest.eggs[1]==spare, "stopped grab completes without picking the replacement")
    SC.NativeActions.startAnimal = originalStart
    -- Uncertainty and the inclusive nest boundary.
    local absent = shell(2013)
    local pending = selectEgg(absent)
    local oldBox, oldCount, oldGet = hutch.getNestBox, nest.getEggsNb, nest.getEgg
    hutch.getNestBox = function() return nil end
    farm.audit(F.base)
    check(pending.phase=="selected","unloaded nest remains open")
    hutch.getNestBox = oldBox
    local streamed = zone.isFullyStreamed
    zone.isFullyStreamed = function() return false end
    farm.audit(F.base)
    check(pending.phase=="selected","unloaded hutch remains open")
    zone.isFullyStreamed = streamed
    for _, count in ipairs({-1,0.5,65}) do
        nest.getEggsNb = function() return count end
        farm.audit(F.base)
        check(pending.phase=="selected","out-of-range nest count remains open")
    end
    nest.getEggsNb = function() return 1 end
    nest.getEgg = function() error("unreadable egg slot") end
    farm.audit(F.base)
    check(pending.phase=="selected","failed nest slot remains open")
    nest.getEggsNb, nest.getEgg = oldCount, oldGet
    for index=1,64 do nest.eggs[index] = shell(3000+index) end
    F.actors[worker2.id] = nil
    farm.audit(F.base)
    check(pending.phase=="selected","unloaded farmer remains open")
    F.actors[worker2.id] = worker2
    worker2.inventory.getFirstEvalRecurse = function() error("inventory unavailable") end
    farm.audit(F.base)
    check(pending.phase=="selected","unreadable farmer inventory remains open")
    worker2.inventory.getFirstEvalRecurse = inventorySearch
    local unreadable = shell(2014)
    unreadable.getModData = function() return nil end
    worker2.inventory:AddItem(unreadable)
    farm.audit(F.base)
    check(pending.phase=="selected","partially readable farmer inventory remains open")
    worker2.inventory:Remove(unreadable)
    farm.audit(F.base)
    check(pending.phase=="consumed" and pending.blocker=="animal_egg_taken_elsewhere" and #nest.eggs==64,
        "fully readable 64-egg nest settles only the missing egg")
    -- 0.27.54 reconstructed ordinary items with a new native ID and preserved ModData.
    local carryEgg = shell(2015)
    local cargo, cargoJob = selectEgg(carryEgg)
    local storage = F.storageContainers["storage:eggs"]
    local bag = F.container()
    function bag:getOutermostContainer() return worker2.inventory end
    for index=1,257 do worker2.inventory:AddItem(F.item("Base.Pencil",4000+index)) end
    worker2.inventory:AddItem(F.item("Base.Bag",5000,{inventory=bag}))
    bag:AddItem(carryEgg)
    carryEgg.nativeId=5015
    local realDeposit = SC.BaseWork.restoreDepositToStorage
    SC.BaseWork.restoreDepositToStorage=F.realBaseWork.restoreDepositToStorage
    storage.full=true
    farm.audit(F.base)
    check(cargo.phase=="carried" and bag:contains(carryEgg) and #storage.items==0,
        "proven cargo remains carried when the food shelf is full")
    storage.full=false
    farm.audit(F.base)
    check(cargo.phase=="delivered" and storage:contains(carryEgg) and not bag:contains(carryEgg)
        and carryEgg.modData[marker]==nil, "old marked egg in a nested bag beyond the audit sample is delivered")
    farm.audit(F.base)
    check(#storage.items==1, "repeated audit does not duplicate carried eggs")
    local currentEgg, impostor=shell(2016),shell(2017)
    local owned, exactJob=selectEgg(currentEgg)
    exactJob.target.eggStableId=U.itemStableId(currentEgg,true)
    impostor.modData[marker]=owned.id
    worker2.inventory:AddItem(impostor)
    table.remove(worker2.inventory.items)
    table.insert(worker2.inventory.items,1,impostor) -- Within the generic audit's 256-item sample.
    farm.audit(F.base)
    check(owned.phase=="selected" and worker2.inventory:contains(impostor)
        and #storage.items==1, "wrong stable identity cannot deliver through the generic audit")
    worker2.inventory:Remove(impostor)
    currentEgg.modData[marker]=nil
    currentEgg.nativeId=5016
    worker2.inventory:AddItem(currentEgg)
    farm.audit(F.base)
    check(owned.phase=="selected" and worker2.inventory:contains(currentEgg),
        "unmarked original with a reconstructed native ID stays unresolved")
    worker2.inventory:Remove(currentEgg)
    farm.audit(F.base)
    check(owned.phase=="consumed", "missing original settles after ambiguous cargo clears")
    local legacyOne,legacyTwo=shell(6200),shell(6201)
    local duplicate=selectEgg(legacyOne)
    legacyTwo.modData[marker]=duplicate.id
    worker2.inventory:AddItem(legacyOne)
    worker2.inventory:AddItem(legacyTwo)
    farm.audit(F.base)
    check(duplicate.phase=="selected" and worker2.inventory:contains(legacyOne)
        and worker2.inventory:contains(legacyTwo) and #storage.items==1,
        "ambiguous legacy egg markers cannot deliver either egg")
    worker2.inventory:Remove(legacyTwo)
    farm.audit(F.base)
    check(duplicate.phase=="delivered" and storage:contains(legacyOne),
        "unique original legacy cargo can be delivered once ambiguity clears")
    SC.BaseWork.restoreDepositToStorage=realDeposit

    -- Actual stable document round trip and public farm-zone removal, with a
    -- 0.27.54 selection (no new identity field or in-memory action).
    local real = F.realBaseLife
    SC.BaseLife = real
    real.reset()
    local square=F.squares["2:2:0"]
    check(real.create(square,"Egg camp"),"create a persisted egg camp")
    check(real.beginZone("farm",square),"start persisted farm zone")
    local added, farmZone=real.finishZone(square,"Egg farm")
    check(added,"finish persisted farm zone: "..tostring(farmZone))
    local target={}
    for k,v in pairs(candidate) do target[k]=v end
    target.zoneId=farmZone.id
    local queued, oldJob=real.enqueueJob({type="farm",target=target})
    check(queued,"enqueue persisted egg chore")
    local oldEgg=shell(2018)
    local legacy=selectEgg(oldEgg,oldJob)
    local snapshot=real.export()
    real.reset()
    A.reset()
    local loaded, why=real.restore(snapshot)
    check(loaded,"restore selected egg save: "..tostring(why))
    local savedJob,savedReceipt=real.job(oldJob.id),real.farmReceipt(legacy.id)
    check(savedReceipt.phase=="selected" and savedJob.target.eggReceiptId==legacy.id
        and not real.removeZone(farmZone.id), "restored selection blocks zone removal before the audit")
    for pulse=1,4 do farm.audit(real.active()) end
    check(savedReceipt.phase=="consumed" and savedReceipt.blocker=="animal_egg_taken_elsewhere",
        "restored farm audit settles original missing selection")
    local allocated=real.allocateFarmReceipt({actorId=worker2.id,jobId="job:999",kind="output",
        phase="carried",nativeId=6020,itemType="Base.Egg",destinationCategory="food"})
    check(allocated and not real.farmReceipt(legacy.id), "next allocation prunes the old terminal receipt")
    savedJob.reservedBy=worker2.id
    for pulse=1,3 do farm.update(worker2,{},savedJob,{}) end
    check(savedJob.state=="completed","pruned proof still completes the original restored chore")
    check(real.removeZone(farmZone.id) and not real.job(savedJob.id), "restored farm zone and its chore can be removed")
    SC.BaseLife=B
    nest.eggs={egg}
    A.reset()
    A.candidate(F.base)
end
local oldConfig = U.config
U.config = function(name)
    if name == "animalCloseEnabled" then return 1 end
    return oldConfig(name)
end
check(A.hutchOperation(20.25, false, 0, 3) == nil, "birds outside retain the dusk grace period")
check(A.hutchOperation(20.25, false, 3, 3) == "animal_close", "all birds inside permits dusk closing")
check(A.hutchOperation(21.1, false, 0, 3) == nil, "grace expiry cannot lock birds out")
check(A.hutchOperation(23, false, nil, 3) == nil, "unknown occupancy cannot authorize closing")
check(A.hutchOperation(7, true, 3, 3) == "animal_open", "native dawn opens a closed hutch")
check(A.hutchOperation(10, false, 0, 3) == nil, "already open is an idempotent no-op")
local anotherBird=setmetatable({}, {__index=bird})
function anotherBird:getAnimalID() return 101 end
local anotherHutch=setmetatable({occupants={anotherBird}}, {__index=hutch})
function anotherHutch:getAnimalInNestBox() return nil end
hutch.occupants={bird}
zone.registered={bird,anotherBird}
local roost={complete=true,animals={{id=100},{id=101}},members={[100]=bird,[101]=anotherBird},
    native=zone,hutches={hutch,anotherHutch},flockIds={100,101},rosterVerified=true}
check(A.roostReady(roost,true),"birds sheltered across two hutches can close either door")
hutch.occupants={} hutch.nestingBird=bird
check(A.roostReady(roost,true),"a laying hen in a nesting box is sheltered even outside the roost map")
hutch.occupants={bird} hutch.nestingBird=nil
anotherHutch.occupants={}
check(not A.roostReady(roost,true),"one late bird keeps both hutch doors open")
anotherHutch.occupants={anotherBird}
zone.registered={bird,anotherBird,{}}
check(not A.roostReady(roost,true),"a new outside bird invalidates the closing commit")
zone.registered={bird}
hutch.occupants={}
F.hour=7
local staleJob=F.job("animal_close",2,2,candidate)
staleJob.target.operation="animal_close"
local staleState={}
local beforeStarts=F.nativeStarts
local waiting,why=A.update(worker2,{},staleJob,{},staleState)
check(waiting and staleState.animalReturn and F.nativeStarts==beforeStarts,
    "dawn supersedes an unfinished night-close job without toggling the door")
A.update(worker2,{},staleJob,{},staleState)
F.hour=22
local dayState={}
local dayHandled= A.update(worker2,{},job,{},dayState)
check(dayHandled and dayState.animalReturn and F.nativeStarts==beforeStarts,
    "daytime egg work yields and settles at night instead of reserving the hutch forever")
local previousJobs=F.base.jobs
F.base.jobs={{id="old:egg",type="farm",state="blocked",target=job.target}}
hutch.occupants={bird}
local doorCandidate=A.candidate(F.base)
check(doorCandidate and doorCandidate.operation=="animal_close",
    "an idle blocked egg job cannot prevent nighttime door work")
F.base.jobs=previousJobs
hutch.occupants={} F.hour=7
U.config = oldConfig
local nestOnlyBird=setmetatable({}, {__index=bird})
function nestOnlyBird:getAnimalID() return 102 end
hutch.nestingBird=nestOnlyBird
nest.eggs={}
F.clock=F.clock+1000
check(A.candidate(F.base)==nil,"empty native nests are never indexed")
check(F.base.farm.animals.zones["42"].hens==2,"nesting hens remain included in the persisted flock census")
hutch.nestingBird=nil
F.hour=22
F.base.jobs={}
U.config=function(name) if name=="animalCloseEnabled" then return 1 end return oldConfig(name) end
F.clock=F.clock+1000
check(A.candidate(F.base)==nil and #F.base.farm.animals.zones["42"].flockIds==2,
    "a formerly seen bird missing from both the zone set and tiles stays in the saved flock")
A.reset() -- Reload discards native references, not the persisted identities.
check(A.candidate(F.base)==nil,"reload cannot shrink the flock and lock a missing bird outside")
hutch.occupants={bird} hutch.nestingBird=nestOnlyBird
F.clock=F.clock+1000
check(A.candidate(F.base).operation=="animal_close","the exact missing bird returning permits closing")
function nestOnlyBird:getHealth() return 0 end
hutch.nestingBird=nil
F.clock=F.clock+1000
check(A.candidate(F.base).operation=="animal_close"
    and #F.base.farm.animals.zones["42"].flockIds==1,
    "a positively observed death retires its identity without reconstructing an animal")
local reloadBird=setmetatable({health=100},{__index=bird})
function reloadBird:getAnimalID() return 103 end
function reloadBird:getHealth() return self.health end
hutch.nestingBird=reloadBird
A.candidate(F.base)
reloadBird.health=0
A.reset()
check(A.candidate(F.base)==nil and #F.base.farm.animals.zones["42"].flockIds==1,
    "an observed dead bird after reload retires its ID while its occupied nest still blocks closing")
hutch.nestingBird=nil
check(A.candidate(F.base).operation=="animal_close","native removal of the dead occupant releases closing")
F.base.farm.animals.zones["42"].flockIds={100,100}
A.reset()
check(A.candidate(F.base)==nil,"ambiguous saved identities prohibit automatic closing")
zone,bird,trough=fresh()
for index=1,8 do F.base.farm.animals.zones[tostring(index)]={flockIds={index}} end
local capped,capReason=A.candidate(F.base)
check(capped==nil and capReason=="animal_zone_limit"
    and F.base.farm.animals.zones["1"].flockIds[1]==1,
    "the zone limit never evicts retained flock safety evidence")
U.config=oldConfig
local target=A.flockTarget(20)
check(target.hens==16 and target.roosters==2 and target.reserve==2,
    "all rooster and reserve slots are excluded from the hen target")
target=A.flockTarget(16)
check(target.hens==12 and target.roosters==2 and target.reserve==2,
    "threshold boundary reserves the extra rooster without overbooking")
check(A.flockTarget(3)==nil,"a tiny hutch does not erase the minimum flock or reserve")
local flock={capacity=20,complete=true,hens=2,roosters=1,chicks=0}
check(not A.breedingPlan(flock).verified,"missing native feed forecast cannot permit breeding")
local plan=A.breedingPlan(flock,{verified=true,stock=100,dailyPerBird=1})
check(plan.verified and plan.retain==14,"verified supplies limit future hens and roost headroom")
local low=A.breedingPlan(flock,{verified=true,stock=6,dailyPerBird=1})
check(low.retain==0 and not low.feedEnough and low.hens==2 and low.roosters==1,
    "feed shortage pauses breeding without reducing the protected minimum flock")
low=A.breedingPlan(flock,{verified=true,stock=9,dailyPerBird=1})
check(low.feedEnough and low.retain==0,"supplies for the current flock do not authorize unfunded chicks")
flock.chicks=2
plan=A.breedingPlan(flock,{verified=true,stock=100,dailyPerBird=1})
check(plan.retain==12,"chicks already in the pen reserve future hen capacity")
local kept=A.eggRetention({verified=true,retain=2},{99,5,42},true)
check(kept["5"] and kept["42"] and not kept["99"],"retention is stable by exact native egg identity")
check(A.eggRetention(plan,{5,5},true)==nil,"duplicate egg identities prohibit selection")
check(A.eggRetention(plan,{5},false)==nil,"unfinished egg census cannot authorize collection")
local choices={}
for id=1,16 do choices[A.choose("farmer:"..id,crop,animal)]=true end
check(choices[crop] and choices[animal],"crop work and animal work can both win deterministic selection")
local oldCullConfig=U.config
U.config=function(name) if name=="animalCullEnabled" then return 1 end return oldCullConfig(name) end
local function adult(id,female,age)
    return {id=id,female=female,age=age,baby=false,oddball=false,held=false,led=false,
        wild=false,cullKnown=true,laying=female==true,name=""}
end
local birds={adult(1,false,200),adult(2,false,100),adult(3,true,80),adult(4,true,180),adult(5,true,160)}
local census={complete=true,hens=3,roosters=2,chicks=0,animals=birds,auditedAt=F.clock}
local cullTarget={verified=true,hens=2,roosters=1}
local evidence={populationComplete=true,safe=true,daylight=true,toolsVerified=true,
    outputCapacityVerified=true,claimAvailable=true,counters={}}
check(A.cullPlan(census,cullTarget,evidence)==1,"surplus roosters precede hens, oldest first")
for _,field in ipairs({"held","led","wild","oddball"}) do
    birds[1][field]=true
    check(A.cullPlan(census,cullTarget,evidence)==2,field.." bird is excluded")
    birds[1][field]=false
end
birds[1].name="Player's rooster"
check(A.cullPlan(census,cullTarget,evidence)==2,"player naming protects the exact animal")
birds[1].name="" birds[1].cullKnown=false
check(A.cullPlan(census,cullTarget,evidence)==2,"unknown ownership evidence protects the animal")
birds[1].cullKnown=true birds[1].baby=true
check(A.cullPlan(census,cullTarget,evidence)==2,"chicks cannot be culled")
birds[1].baby=false
for _,field in ipairs({"safe","daylight","toolsVerified","outputCapacityVerified","populationComplete","claimAvailable"}) do
    evidence[field]=false
    check(A.cullPlan(census,cullTarget,evidence)==nil,"missing "..field.." stops cull admission")
    evidence[field]=true
end
evidence.counters={cullDay=4,culls=1}
check(A.cullPlan(census,cullTarget,evidence)==nil,"saved daily counter prevents a second proposal after reload")
check(A.cullsToday(evidence.counters,120)==0,"a later game day releases the daily allowance")
check(A.cullsToday({cullDay=9,culls=1},100)==nil,"future or ambiguous counters cannot reset to zero")
check(A.cullsToday("invalid",100)==nil,"malformed saved counter refuses admission")
check(A.cullPlan({},cullTarget,evidence)==nil,"incomplete population data cannot propose a bird")
evidence.counters={} census.roosters=1 table.remove(birds,2)
birds[3].laying=false
check(A.cullPlan(census,cullTarget,evidence)==4,"past-laying hens precede laying hens")
census.hens=2 table.remove(birds,4)
check(A.cullPlan(census,cullTarget,evidence)==nil,"the last rooster and minimum hens are protected")
U.config=oldCullConfig
-- An active job must renew its audit even when earlier scans exhaust the frame.
fresh(2,1)
candidate=A.candidate(F.base)
local auditWorker=F.actor("audit-worker",1,1)
local auditJob=F.job(candidate.operation,candidate.x,candidate.y,candidate)
auditJob.reservedBy=auditWorker.id
F.clock=F.clock+30001
local rescued=0
SC.Performance={preciseNowMs=function() return 0 end,remainingBudgetMs=function() return 0 end,
    claimUnits=function(_,requested,urgent)
        if urgent then rescued=rescued+1 return math.min(1,requested) end return 0
    end}
local auditReason
for _=1,20 do
    _,auditReason=A.update(auditWorker,{},auditJob,{}, {})
    F.clock=F.clock+501
    if auditReason~="animal_audit_pending" then break end
end
check(rescued>0 and auditReason~="animal_audit_pending","assigned audit makes bounded progress despite an exhausted frame")
fresh(2,1)
candidate=nil
for _=1,20 do
    candidate=A.candidate(F.base)
    F.clock=F.clock+501
    if candidate then break end
end
check(candidate~=nil,"admission census also makes bounded progress despite an exhausted frame")
SC.Performance=nil
local bagZone,_,bagTrough=fresh()
bagTrough.water=100
local feeder=bagTrough.feeder
function feeder:getMaxFeed() return 25 end
local bag=F.item("Base.AnimalFeedBag",991)
function bag:getAnimalFeedType() return "AnimalFeed" end
function bag:getCurrentUses() return 100 end
F.addStorage("feed-bags","farming",{bag})
local bagTarget=A.candidate(F.base)
check(bagTarget and bagTarget.operation=="animal_feed" and bagTarget.high==22.5,"vanilla-sized trough refill is admitted")
local bagActor=F.actor("bag-feeder",2,3)
local bagJob=F.job("animal_feed",3,2,bagTarget)
local bagState={}
feeder.feed=20
local bagOkay,bagWhy=A.update(bagActor,{},bagJob,{},bagState)
check(bagOkay and bagState.animalReturn,"an adequately fed trough finishes when another whole bag will not fit: "..tostring(bagWhy))
A.update(bagActor,{},bagJob,{},bagState)
check(bagJob.state=="completed" and feeder.feed==20 and bag:getContainer()~=bagActor.inventory,
    "partial refill completes without moving or consuming the spare bag")
print("ANIMAL_WORK_PASS checks=" .. checks)
