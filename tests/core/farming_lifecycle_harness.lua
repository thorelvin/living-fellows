-- SPDX-License-Identifier: MIT

local SC = SurvivorCompanion
local FarmWork = SC.FarmWork
local F = FarmLifecycleFixture
local checks = 0

local function check(condition, message)
    checks = checks + 1
    assert(condition, "farming lifecycle check " .. tostring(checks) .. " failed: " .. message)
end

local function fresh()
    FarmWork.reset()
    if SC.ActionSupervisor then SC.ActionSupervisor.reset(nil, "farm_fixture") end
    F.reset()
    farming_vegetableconf.props.Tomato.growBack = 2
end

local function seed(id)
    return F.item("Base.TomatoSeed", id, { category = "Food" })
end

local function can(id, amount)
    return F.item("Base.WateringCan", id, { fluidAmount = amount, fluidCapacity = 10 })
end

-- LF-01/LF-02: active ownership survives audits and a pending return cannot settle the job.
fresh()
local actor = F.actor("worker-a", 0, 1)
local plant = F.plant({ waterLvl = 20, waterNeeded = 60 })
F.square(1, 1, plant)
local waterCan = can(10, 2)
local farmStorage, farmContainer = F.addStorage("storage:farm", "farming", { waterCan })
local waterJob = F.job("water", 1, 1, { id = "job:water", actorId = actor.id, uses = 2 })
local handled, reason = FarmWork.update(actor, {}, waterJob, {})
check(handled == true and reason == "farm_supply_taken"
        and waterCan.container == actor.inventory,
    "watering borrows the exact marked can")
FarmWork.audit(F.base)
check(waterCan.container == actor.inventory and F.restoreCalls == 0
        and F.receipts[1].phase == "borrowed",
    "an audit never takes supply from its active farm owner")
FarmWork.update(actor, {}, waterJob, {})
plant.waterLvl = 70
F.native[actor].active = false
FarmWork.update(actor, {}, waterJob, {})
F.returnMode = "pending"
handled, reason = FarmWork.update(actor, {}, waterJob, {})
check(handled == true and reason == "base_storage_looting"
        and F.completedJobs == 0 and waterCan.container == actor.inventory
        and F.receipts[1].phase == "borrowed",
    "walking or looting on return is pending, not settled")
F.returnMode = "complete"
FarmWork.update(actor, {}, waterJob, {})
check(F.completedJobs == 1 and waterCan.container == farmContainer
        and F.receipts[1].phase == "returned",
    "the job completes only after exact return settlement")

-- LF-02 replant variant: the shovel must be home before sow borrows a seed.
fresh()
actor = F.actor("worker-a", 0, 1)
plant = F.plant({ state = "dead", harvestable = false })
F.square(1, 1, plant)
local shovel = F.item("Base.Shovel", 20, { tags = { DIG_PLOW = true } })
local tomatoSeed = seed(21)
farmStorage, farmContainer = F.addStorage("storage:farm", "farming", { shovel, tomatoSeed })
local replant = F.job("replant", 1, 1, {
    id = "job:replant", actorId = actor.id, cropType = "Tomato",
})
FarmWork.update(actor, {}, replant, {})
FarmWork.update(actor, {}, replant, {})
plant.state = "plow"
F.native[actor].active = false
FarmWork.update(actor, {}, replant, {})
F.returnMode = "pending"
FarmWork.update(actor, {}, replant, {})
check(shovel.container == actor.inventory and tomatoSeed.container == farmContainer,
    "a pending plow-tool return does not advance replanting")
F.returnMode = "complete"
FarmWork.update(actor, {}, replant, {})
FarmWork.update(actor, {}, replant, {})
FarmWork.update(actor, {}, replant, {})
check(F.nativeStarts[#F.nativeStarts].intent.operation == "sow"
        and F.nativeStarts[#F.nativeStarts].intent.item == tomatoSeed
        and shovel.container == farmContainer,
    "replant sowing receives the seed only after the shovel is returned")

-- LF-03: retain a selected barrel while the actor approaches it over many updates.
fresh()
actor = F.actor("worker-a", 0, 1)
plant = F.plant({ waterLvl = 10, waterNeeded = 60 })
F.square(1, 1, plant)
local sourceSquare = F.square(2, 0, nil)
local barrel = F.waterSource(sourceSquare, true)
local emptyCan = can(30, 0)
F.addStorage("storage:farm", "farming", { emptyCan })
local refill = F.job("water", 1, 1, { id = "job:refill", actorId = actor.id, uses = 3 })
FarmWork.update(actor, {}, refill, {})
handled, reason = FarmWork.update(actor, {}, refill, {})
local requestsAfterSelection = #F.navigationRequests
check(handled == true and reason == "farm_approaching" and requestsAfterSelection == 1,
    "an empty can selects a usable water source and begins approach")
handled, reason = FarmWork.update(actor, {}, refill, {})
check(handled == true and reason == "farm_approaching"
        and #F.navigationRequests == requestsAfterSelection + 1
        and F.navigationRequests[#F.navigationRequests].square == sourceSquare,
    "the selected water source survives subsequent approach updates")
local secondSourceSquare = F.square(3, 0, nil)
F.waterSource(secondSourceSquare, true)
barrel.fluidAmount = 0
handled, reason = FarmWork.update(actor, {}, refill, {})
check(handled == true and reason == "farm_approaching"
        and F.navigationRequests[#F.navigationRequests].square == secondSourceSquare,
    "an exhausted selected source resumes bounded scanning at the next source")

-- LF-04: cancelling a supply-free harvest stops its live native action.
fresh()
actor = F.actor("worker-a", 0, 1)
plant = F.plant()
F.square(1, 1, plant)
F.addStorage("storage:food", "food", {})
local harvest = F.job("harvest", 1, 1, {
    id = "job:harvest", actorId = actor.id, cropType = "Tomato",
})
FarmWork.update(actor, {}, harvest, {})
check(F.native[actor] and F.native[actor].active == true,
    "harvest starts without borrowed supply")
local cancelled = FarmWork.cancelJob(harvest.id, "test_cancel")
check(cancelled == true and F.nativeCancels == 1 and F.native[actor] == nil,
    "harvest cancellation verifies the native action is stopped")

fresh()
actor = F.actor("worker-a", 0, 1)
plant = F.plant()
local completedHarvestSquare = F.square(1, 1, plant)
local foodStorage, foodContainer = F.addStorage("storage:food", "food", {})
harvest = F.job("harvest", 1, 1, {
    id = "job:completed-harvest", actorId = actor.id, cropType = "Tomato",
})
FarmWork.update(actor, {}, harvest, {})
local cancelledTomato = F.item("Base.Tomato", 32, { category = "Food" })
actor.inventory:AddItem(cancelledTomato)
F.native[actor].active = false
completedHarvestSquare.plant = nil
cancelled, reason = FarmWork.cancelJob(harvest.id, "test_cancel_after_completion")
check(cancelled == false and reason == "farm_recovery_pending"
        and F.receipts[1].phase == "recovery"
        and cancelledTomato.modData.LF_FarmReceiptId == F.receipts[1].id,
    "cancellation reconciles a just-completed harvest before releasing tracking")
FarmWork.audit(F.base)
cancelled = FarmWork.cancelJob(harvest.id, "test_cancel_after_recovery")
check(cancelled == true and cancelledTomato.container == foodContainer
        and F.receipts[1].phase == "delivered",
    "a reconciled cancelled harvest recovers its exact output before cancellation settles")

-- LF-05: a resumed checkpoint can only reconcile against its original actor.
fresh()
local original = F.actor("worker-a", 0, 1)
local replacement = F.actor("worker-b", 0, 1)
local axe = F.item("Base.Axe", 40)
local personalFood = F.item("Base.CannedBeans", 41, { category = "Food" })
replacement.inventory:AddItem(axe)
replacement.inventory:AddItem(personalFood)
F.square(1, 1, nil)
F.addStorage("storage:food", "food", {})
local resumed = F.job("harvest", 1, 1, {
    id = "job:resumed", actorId = replacement.id, cropType = "Tomato",
    harvestStarted = true, harvestActorId = original.id, harvestBeforeIds = "|1|",
})
handled, reason = FarmWork.update(replacement, {}, resumed, {})
check(handled == false and reason == "farm_harvest_actor_mismatch"
        and #F.receipts == 0 and axe.modData.LF_FarmReceiptId == nil
        and personalFood.modData.LF_FarmReceiptId == nil,
    "a replacement worker's inventory is never classified as harvest output")
local modifier, eligible = FarmWork.jobModifier(replacement.id, resumed, nil,
    { actor = replacement })
check(eligible == false and modifier == 0,
    "a saved harvest checkpoint remains reserved logically for its original actor")

-- LF-06: reconcile original-worker produce before the missing-plant guard.
fresh()
original = F.actor("worker-a", 0, 1)
local oldItem = F.item("Base.Hammer", 50)
local tomato = F.item("Base.Tomato", 51, { category = "Food" })
oldItem.modData.LF_ItemStableId = "saved-old-item"
tomato.modData.LF_ItemStableId = "harvest-output-item"
original.inventory:AddItem(oldItem)
original.inventory:AddItem(tomato)
F.square(1, 1, nil)
F.addStorage("storage:food", "food", {})
resumed = F.job("harvest", 1, 1, {
    id = "job:resume-original", actorId = original.id, cropType = "Tomato",
    harvestStarted = true, harvestActorId = original.id,
    harvestBaselineVersion = 1, harvestBeforeStableIds = "|saved-old-item|",
})
handled, reason = FarmWork.update(original, {}, resumed, {})
check(handled == true and reason == "farm_harvest_recovered" and #F.receipts == 1
        and F.receipts[1].kind == "output" and F.receipts[1].nativeId == 51,
    "a completed harvest reconciles exact plausible output even when the plant vanished")
check(oldItem.modData.LF_FarmReceiptId == nil and tomato.modData.LF_FarmReceiptId ~= nil,
    "harvest recovery excludes pre-existing personal inventory")

-- LF-07: a rotating cursor prevents early unavailable receipts starving later work.
fresh()
actor = F.actor("worker-a", 0, 1)
F.square(1, 1, nil)
local validStorage, validContainer = F.addStorage("storage:valid", "farming", {})
for index = 1, 5 do
    local item = F.item("Base.Tool" .. tostring(index), 60 + index)
    actor.inventory:AddItem(item)
    item.modData.LF_FarmReceiptId = "farm-receipt:" .. tostring(index)
    F.receipts[#F.receipts + 1] = {
        id = item.modData.LF_FarmReceiptId, jobId = "job:gone", actorId = actor.id,
        kind = "borrowed", itemType = item.fullType,
        sourceStorageId = index == 5 and validStorage.id or "storage:missing" .. tostring(index),
        phase = "recovery",
    }
end
FarmWork.audit(F.base)
FarmWork.audit(F.base)
check(F.receipts[5].phase == "returned" and #validContainer.items == 1,
    "failed early recoveries cannot starve a later recoverable receipt")

-- LF-08: physical plot identity, not zone identity, owns exclusivity.
fresh()
plant = F.plant()
F.square(1, 1, plant)
F.addStorage("storage:food", "food", {})
F.base.zones = {
    { id = "zone:area", kind = "area", x1 = 0, y1 = 0, x2 = 3, y2 = 3, z = 0 },
    { id = "zone:farm-a", kind = "farm", x1 = 1, y1 = 1, x2 = 1, y2 = 1, z = 0 },
    { id = "zone:farm-b", kind = "farm", x1 = 1, y1 = 1, x2 = 1, y2 = 1, z = 0 },
}
FarmWork.audit(F.base)
FarmWork.audit(F.base)
check(#F.base.jobs == 1,
    "overlapping farm zones enqueue at most one mutation job for a physical plot")
local originalZone = F.base.jobs[1].target.zoneId
FarmWork.cancelZone(originalZone)
check(F.base.jobs[1].target.zoneId ~= originalZone,
    "removing one overlapping zone rehomes the still-valid plot job")

-- LF-09: destructive harvest rechecks the live seed-preservation condition.
fresh()
farming_vegetableconf.props.Tomato.growBack = nil
plant = F.plant({ hasSeeds = false })
F.square(1, 1, plant)
local seeds = { seed(71), seed(72), seed(73) }
local seedStorage, seedContainer = F.addStorage("storage:farm", "farming", seeds)
F.addStorage("storage:food", "food", {})
local queued, guardedHarvest = FarmWork.audit(F.base)
check(queued == true and guardedHarvest.target.cropType == "Tomato",
    "scan records crop identity on a protected harvest")
seedContainer.items = {}
actor = F.actor("worker-a", 0, 1)
guardedHarvest.state, guardedHarvest.reservedBy = "active", actor.id
handled, reason = FarmWork.update(actor, {}, guardedHarvest, {})
check(handled == false and reason == "farm_seed_reserve_changed"
        and #F.nativeStarts == 0 and plant.harvestable == true,
    "harvest cannot start after its protective seed reserve disappears")

-- LF-11: farm startup must acquire WORK ownership before stopping movement,
-- equipping supply, or queueing a native action.
fresh()
actor = F.actor("worker-a", 0, 1)
plant = F.plant({ state = "plow", harvestable = false })
F.square(1, 1, plant)
tomatoSeed = seed(80)
F.addStorage("storage:farm", "farming", { tomatoSeed })
local sowJob = F.job("sow", 1, 1, {
    id = "job:steering-race", actorId = actor.id, cropType = "Tomato",
})
FarmWork.update(actor, {}, sowJob, {})
local playerToken = assert(SC.ActionSupervisor.begin(actor, {
    owner = "player_control", action = "steer",
    priority = SC.ActionSupervisor.Priority.PLAYER,
    phase = "approaching", deadlines = { approaching = 0 }, ignoreRetry = true,
}))
handled, reason = FarmWork.update(actor, {}, sowJob, {})
check(handled == false and string.find(tostring(reason), "actor_owned_by", 1, true) ~= nil
        and #F.nativeStarts == 0 and F.nativeStops == 0
        and SC.ActionSupervisor.isCurrent(playerToken),
    "a current steering owner blocks farm stop/equip/queue side effects")
SC.ActionSupervisor.cancel(actor, "fixture_release", nil, true)
handled, reason = FarmWork.update(actor, {}, sowJob, {})
check(handled == true and reason == "farm_sow_started"
        and #F.nativeStarts == 1 and F.nativeStops == 1
        and SC.ActionSupervisor.current(actor) == nil,
    "farm startup acquires, commits, verifies, and releases one WORK transaction")

-- LF-18: seed reserve counts only plots still covered by the current Farm-zone
-- union, while overlapping coverage and failed removal remain intact.
fresh()
farming_vegetableconf.props.Tomato.growBack = nil
F.base.zones = {
    { id = "zone:area", kind = "area", x1 = 0, y1 = 0, x2 = 30, y2 = 30, z = 0 },
    { id = "zone:farm-a", kind = "farm", x1 = 1, y1 = 1, x2 = 1, y2 = 1, z = 0 },
    { id = "zone:farm-b", kind = "farm", x1 = 2, y1 = 1, x2 = 2, y2 = 1, z = 0 },
}
F.square(1, 1, F.plant({ hasSeeds = false }))
F.square(2, 1, F.plant({ hasSeeds = false }))
FarmWork.audit(F.base)
check(FarmWork._nonGrowbackPlotsForTests("Tomato") == 2,
    "seed reserve census records both currently zoned non-growback plots")
table.remove(F.base.zones, 2)
FarmWork.zoneRemoved("zone:farm-a")
check(FarmWork._nonGrowbackPlotsForTests("Tomato") == 1,
    "successful zone removal prunes an uncovered plot from the seed reserve")

fresh()
farming_vegetableconf.props.Tomato.growBack = nil
F.base.zones = {
    { id = "zone:area", kind = "area", x1 = 0, y1 = 0, x2 = 30, y2 = 30, z = 0 },
    { id = "zone:farm-a", kind = "farm", x1 = 1, y1 = 1, x2 = 1, y2 = 1, z = 0 },
    { id = "zone:farm-b", kind = "farm", x1 = 1, y1 = 1, x2 = 1, y2 = 1, z = 0 },
}
F.square(1, 1, F.plant({ hasSeeds = false }))
FarmWork.audit(F.base)
table.remove(F.base.zones, 2)
FarmWork.zoneRemoved("zone:farm-a")
check(FarmWork._nonGrowbackPlotsForTests("Tomato") == 1,
    "removing one overlapping Farm zone preserves the plot covered by another")
local blockedZoneJob = F.job("harvest", 1, 1, {
    id = "job:blocked-zone-remove", zoneId = "zone:farm-b", actorId = "gone",
    cropType = "Tomato",
})
F.receipts[#F.receipts + 1] = {
    id = "farm-receipt:blocked", jobId = blockedZoneJob.id,
    kind = "output", phase = "recovery",
}
local removed, removeReason = FarmWork.cancelZone("zone:farm-b")
check(removed == false and removeReason == "farm_recovery_pending"
        and FarmWork._nonGrowbackPlotsForTests("Tomato") == 1,
    "a rejected zone removal does not prune seed-reserve observations early")
F.base = { zones = {
    { id = "zone:new-area", kind = "area", x1 = 10, y1 = 10, x2 = 20, y2 = 20, z = 0 },
    { id = "zone:new-farm", kind = "farm", x1 = 11, y1 = 11, x2 = 11, y2 = 11, z = 0 },
}, jobs = {}, storages = {}, farm = { recoveryCursor = 1 } }
check(FarmWork._nonGrowbackPlotsForTests("Tomato") == 0,
    "switching bases invalidates the former base's known-plot cache")

-- LF-19: storage searches and seed census continue beyond the first bounded
-- slice, restart on mutation, and never turn an incomplete scan into absence.
fresh()
F.itemBudget = 80
actor = F.actor("worker-a", 0, 1)
plant = F.plant({ state = "plow", harvestable = false })
F.square(1, 1, plant)
local deepItems = {}
for index = 1, 80 do deepItems[index] = F.item("Base.Junk" .. tostring(index), 100 + index) end
tomatoSeed = seed(181)
deepItems[81] = tomatoSeed
F.addStorage("storage:deep", "farming", deepItems)
sowJob = F.job("sow", 1, 1, {
    id = "job:deep-seed", actorId = actor.id, cropType = "Tomato",
})
handled, reason = FarmWork.update(actor, {}, sowJob, {})
check(handled == true and reason == "farm_supply_scanning"
        and tomatoSeed.container ~= actor.inventory,
    "the first bounded storage slice reports incomplete rather than missing")
handled, reason = FarmWork.update(actor, {}, sowJob, {})
check(handled == true and reason == "farm_supply_taken"
        and tomatoSeed.container == actor.inventory,
    "the next slice finds and borrows an exact supply at position 81")

fresh()
F.itemBudget = 80
local censusItems = {}
for index = 1, 80 do censusItems[index] = F.item("Base.CensusJunk" .. tostring(index), 300 + index) end
censusItems[81], censusItems[82], censusItems[83] = seed(381), seed(382), seed(383)
local _, censusContainer = F.addStorage("storage:census", "farming", censusItems)
local count, complete = FarmWork._seedCountForTests("Tomato")
check(count == nil and complete == false,
    "seed reserve census exposes its incomplete first slice")
count, complete = FarmWork._seedCountForTests("Tomato")
check(count == 3 and complete == true,
    "completed seed census includes every seed beyond the old 80-item prefix: count="
        .. tostring(count) .. " complete=" .. tostring(complete))
local addedSeed = seed(384)
count, complete = FarmWork._seedCountForTests("Tomato")
check(count == nil and complete == false,
    "a new bounded census begins without reusing a stale completed count")
censusContainer:AddItem(addedSeed)
count, complete = FarmWork._seedCountForTests("Tomato")
check(count == nil and complete == false,
    "container mutation invalidates and restarts the bounded seed census")
count, complete = FarmWork._seedCountForTests("Tomato")
check(count == 4 and complete == true,
    "the restarted census converges on the mutated exact count")

fresh()
F.itemBudget = 80
local replacedItems = {}
for index = 1, 80 do
    replacedItems[index] = F.item("Base.EndpointJunk" .. tostring(index), 500 + index)
end
F.addStorage("storage:endpoint", "farming", replacedItems)
count, complete = FarmWork._seedCountForTests("Tomato")
check(count == nil and complete == false,
    "an endpoint census can pause exactly at the old container boundary")
local replacementItems = { seed(700) }
for index = 2, 80 do
    replacementItems[index] = F.item("Base.ReplacementJunk" .. tostring(index), 700 + index)
end
F.storageContainers["storage:endpoint"] = F.container(replacementItems)
count, complete = FarmWork._seedCountForTests("Tomato")
check(count == nil and complete == false,
    "replacing a marked container with the same-sized endpoint restarts the census")
count, complete = FarmWork._seedCountForTests("Tomato")
check(count == 1 and complete == true,
    "the restarted endpoint census includes items before the old cursor")

-- LF-26/LF-30: harvest attribution scans the complete inventory tree and uses
-- persistence-stable item identities instead of runtime native ids.
fresh()
F.itemBudget = 80
actor = F.actor("worker-a", 0, 1)
plant = F.plant()
local largeHarvestSquare = F.square(1, 1, plant)
F.addStorage("storage:food", "food", {})
local nestedOld = F.item("Base.Tomato", 9001, { category = "Food" })
local bag = F.item("Base.Bag", 9002, { inventory = F.container({ nestedOld }) })
for index = 1, 255 do actor.inventory:AddItem(F.item("Base.Old" .. tostring(index), 9002 + index)) end
actor.inventory:AddItem(bag)
harvest = F.job("harvest", 1, 1, {
    id = "job:large-harvest", actorId = actor.id, cropType = "Tomato",
})
for _ = 1, 4 do handled, reason = FarmWork.update(actor, {}, harvest, {}) end
check(F.native[actor] and F.native[actor].active == true
        and harvest.target.harvestBaselineVersion == 1,
    "a resumable baseline reaches all root items and nested bags before harvest starts")
local lateTomato = F.item("Base.Tomato", 9999, { category = "Food" })
actor.inventory:AddItem(lateTomato)
F.native[actor].active = false
largeHarvestSquare.plant = nil
handled, reason = FarmWork.update(actor, {}, harvest, {})
check(handled == true and harvest.target.harvestStarted == true
        and lateTomato.modData.LF_FarmReceiptId == nil,
    "an incomplete post-harvest census preserves its checkpoint and attributes nothing early")
for _ = 1, 4 do
    handled, reason = FarmWork.update(actor, {}, harvest, {})
    if lateTomato.modData.LF_FarmReceiptId ~= nil then break end
end
check(lateTomato.modData.LF_FarmReceiptId ~= nil
        and nestedOld.modData.LF_FarmReceiptId == nil
        and harvest.target.harvestStarted == nil,
    "the completed full census adopts only the new plausible output after the old 256-item limit: "
        .. tostring(reason) .. " late=" .. tostring(lateTomato.modData.LF_FarmReceiptId)
        .. " old=" .. tostring(nestedOld.modData.LF_FarmReceiptId)
        .. " started=" .. tostring(harvest.target.harvestStarted))

fresh()
original = F.actor("worker-a", 0, 1)
local legacyTomato = F.item("Base.Tomato", 17, { category = "Food" })
original.inventory:AddItem(legacyTomato)
F.square(1, 1, nil)
F.addStorage("storage:food", "food", {})
resumed = F.job("harvest", 1, 1, {
    id = "job:legacy-baseline", actorId = original.id, cropType = "Tomato",
    harvestStarted = true, harvestActorId = original.id, harvestBeforeIds = "|16|",
})
handled, reason = FarmWork.update(original, {}, resumed, {})
check(handled == false and reason == "farm_harvest_baseline_unresolved"
        and legacyTomato.modData.LF_FarmReceiptId == nil,
    "a count/native-id legacy checkpoint fails closed instead of adopting old inventory")

-- LF-27: output storage honours deposit policy in normal recovery; borrowed
-- exact returns remain a distinct contract.
fresh()
actor = F.actor("worker-a", 0, 1)
local recoveredTomato = F.item("Base.Tomato", 10001, { category = "Food" })
actor.inventory:AddItem(recoveredTomato)
local rejectedStorage, rejectedContainer = F.addStorage("storage:no-deposit", "food", {})
rejectedStorage.deposits = false
local acceptedStorage, acceptedContainer = F.addStorage("storage:deposit", "food", {})
recoveredTomato.modData.LF_FarmReceiptId = "farm-receipt:deposit-policy"
F.receipts[#F.receipts + 1] = {
    id = recoveredTomato.modData.LF_FarmReceiptId, jobId = "job:gone",
    actorId = actor.id, kind = "output", itemType = "Base.Tomato",
    destinationCategory = "food", phase = "recovery",
}
FarmWork.audit(F.base)
check(recoveredTomato.container == acceptedContainer and #rejectedContainer.items == 0
        and F.receipts[1].phase == "delivered",
    "farm output recovery skips a marked container with deposits disabled")

-- LF-28: successful sow consumption is terminal and cancellation must not try
-- to return the now-consumed exact seed.
fresh()
actor = F.actor("worker-a", 0, 1)
plant = F.plant({ state = "plow", harvestable = false })
F.square(1, 1, plant)
tomatoSeed = seed(11001)
F.addStorage("storage:farm", "farming", { tomatoSeed })
sowJob = F.job("sow", 1, 1, {
    id = "job:cancel-consumed-sow", actorId = actor.id, cropType = "Tomato",
})
FarmWork.update(actor, {}, sowJob, {})
FarmWork.update(actor, {}, sowJob, {})
plant.state, plant.typeOfSeed = "seeded", "Tomato"
actor.inventory:Remove(tomatoSeed)
F.native[actor].active = false
cancelled, reason = FarmWork.cancelJob(sowJob.id, "cancel_after_sow")
check(cancelled == true and F.receipts[1].phase == "consumed"
        and F.receipts[1].blocker == nil,
    "cancelling after proven sow settles the consumed seed instead of reporting it missing")

-- LF-29: harvest authorization counts only usable seeds after both per-storage
-- reserve and protected receipt ownership.
fresh()
local reserveSeeds = { seed(12001), seed(12002), seed(12003) }
local reserveStorage = F.addStorage("storage:reserved-seeds", "farming", reserveSeeds)
reserveStorage.reserve = 2
count, complete = FarmWork._seedCountForTests("Tomato")
check(count == 1 and complete == true,
    "seed availability subtracts the storage reserve from the complete census")
reserveSeeds[1].modData.LF_FarmReceiptId = "farm-receipt:protected-seed"
F.receipts[#F.receipts + 1] = {
    id = reserveSeeds[1].modData.LF_FarmReceiptId, jobId = "job:other",
    actorId = "other", kind = "borrowed", itemType = "Base.TomatoSeed", phase = "borrowed",
}
count, complete = FarmWork._seedCountForTests("Tomato")
check(count == 0 and complete == true,
    "protected committed seeds are excluded before the reserve is applied")

-- LF-34: a terminal night/threat return state belongs to one attempt only.
-- Dawn or Retry must create a fresh runtime phase instead of replaying the old
-- blocker forever.
fresh()
F.hour = 23
actor = F.actor("worker-a", 30, 1)
plant = F.plant()
F.square(31, 1, plant)
F.addStorage("storage:food", "food", {})
F.base.zones[#F.base.zones + 1] = {
    id = "zone:remote-farm", kind = "farm",
    x1 = 31, y1 = 1, x2 = 31, y2 = 1, z = 0,
}
harvest = F.job("harvest", 31, 1, {
    id = "job:night-retry", actorId = actor.id, cropType = "Tomato",
    zoneId = "zone:remote-farm",
})
handled, reason = FarmWork.update(actor, {}, harvest, {})
check(handled == false and reason == "farm_outside_night" and #F.nativeStarts == 0,
    "remote farm work blocks once at night")
F.hour = 9
handled, reason = FarmWork.update(actor, {}, harvest, {})
check(handled == true and reason == "farm_harvest_started" and #F.nativeStarts == 1,
    "the same farm job starts from a fresh phase after dawn")

fresh()
actor = F.actor("worker-a", 0, 1)
plant = F.plant()
F.square(1, 1, plant)
F.addStorage("storage:food", "food", {})
harvest = F.job("harvest", 1, 1, {
    id = "job:threat-retry", actorId = actor.id, cropType = "Tomato",
})
handled, reason = FarmWork.update(actor, {}, harvest, {
    snapshot = { threats = { { distanceSq = 4 } } },
})
check(handled == false and reason == "unsafe_area" and #F.nativeStarts == 0,
    "a nearby threat blocks the current farm attempt")
handled, reason = FarmWork.update(actor, {}, harvest, { snapshot = { threats = {} } })
check(handled == true and reason == "farm_harvest_started" and #F.nativeStarts == 1,
    "Retry after the threat clears starts from a fresh phase")

-- LF-35/LF-39: receipt pressure may split one harvest across recovery passes.
-- Every output remains attributed, the job stays open until all are deposited,
-- and both checkpoint installation and removal invalidate a scheduled save.
fresh()
F.receiptLimit = 1
actor = F.actor("worker-a", 0, 1)
plant = F.plant()
F.square(1, 1, plant)
local cappedFoodStorage, cappedFoodContainer = F.addStorage("storage:food", "food", {})
harvest = F.job("harvest", 1, 1, {
    id = "job:capped-harvest", actorId = actor.id, cropType = "Tomato",
})
local revisionBefore = F.revision
handled, reason = FarmWork.update(actor, {}, harvest, {})
local revisionWithCheckpoint = F.revision
check(handled == true and reason == "farm_harvest_started"
        and revisionWithCheckpoint > revisionBefore
        and harvest.target.harvestStarted == true,
    "installing a harvest ownership checkpoint bumps save consistency")
local firstTomato = F.item("Base.Tomato", 13001, { category = "Food" })
local secondTomato = F.item("Base.Tomato", 13002, { category = "Food" })
actor.inventory:AddItem(firstTomato)
actor.inventory:AddItem(secondTomato)
plant.harvestable = false
F.native[actor].active = false
handled, reason = FarmWork.update(actor, {}, harvest, {})
check(handled == true and reason == "farm_harvest_receipt_wait"
        and F.completedJobs == 0 and #F.receipts == 1
        and firstTomato.modData.LF_FarmReceiptId ~= nil
        and secondTomato.modData.LF_FarmReceiptId == nil,
    "a full receipt ledger pauses after the accounted prefix without completing")
for _ = 1, 10 do
    FarmWork.update(actor, {}, harvest, {})
    if F.completedJobs > 0 then break end
end
check(F.completedJobs == 1 and #F.receipts == 2
        and #cappedFoodContainer.items == 2
        and firstTomato.modData.LF_FarmReceiptId == nil
        and secondTomato.modData.LF_FarmReceiptId == nil
        and harvest.target.harvestStarted == nil
        and F.revision > revisionWithCheckpoint,
    "partial receipt allocation resumes, deposits every output, then clears the checkpoint")

print("FARMING_LIFECYCLE_PASS checks=" .. tostring(checks))
