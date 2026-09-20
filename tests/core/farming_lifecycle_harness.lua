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
original.inventory:AddItem(oldItem)
original.inventory:AddItem(tomato)
F.square(1, 1, nil)
F.addStorage("storage:food", "food", {})
resumed = F.job("harvest", 1, 1, {
    id = "job:resume-original", actorId = original.id, cropType = "Tomato",
    harvestStarted = true, harvestActorId = original.id, harvestBeforeIds = "|50|",
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

print("FARMING_LIFECYCLE_PASS checks=" .. tostring(checks))
