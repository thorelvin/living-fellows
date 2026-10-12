-- SPDX-License-Identifier: MIT
local SC, T = SurvivorCompanion, SC_VEHICLE_UNLOAD_TEST
local Unload = SC.VehicleUnload
local checks = 0
local function check(ok, message)
    checks = checks + 1
    assert(ok, "vehicle unload check " .. tostring(checks) .. ": " .. message)
end

local first = T.item("first")
T.trunk.items[1] = first
check(Unload.eligible(T.car) == true, "stationary parked car is eligible")
local rows = Unload.rows()
check(#rows == 1 and rows[1].count == 1,
    "parked car row shows the exact trunk count")
local queued, job = Unload.queue(T.car.id)
check(queued and job.type == "unload_vehicle" and job.target.vehicleId == T.car.id,
    "manual order creates a specific car job")
check(Unload.queue(T.car.id) == false, "duplicate car job is refused")

local working, reason = Unload.update(T.actor, T.base, job)
check(working and reason == "car_trunk_looting" and T.visual() == "active"
        and T.trunk.items[1] == first,
    "worker visibly opens trunk before item identity moves")
T.visual("completed")
working, reason = Unload.update(T.actor, T.base, job)
check(working and reason == "car_item_carried"
        and T.inventory.items[1] == first and #T.trunk.items == 0
        and first.data.LF_CarUnloadJob == job.id,
    "exact item moves to worker with a recovery marker")
check(Unload.releaseAffinity(T.actor, job) == false
        and job.assignedId == T.actor.id,
    "carried cargo keeps its original recovery owner")
T.deferDeposit(true)
local pending, pendingReason, terminal = Unload.update(T.actor, T.base, job)
check(pending and pendingReason == "approaching_base_storage"
        and terminal ~= true and T.inventory.items[1] == first,
    "accepted storage approach keeps the lease and marked cargo")
T.car.stationary = false
T.deferDeposit(false)
T.falseDelivery(true)
local unverified, unverifiedReason, unverifiedTerminal =
    Unload.update(T.actor, T.base, job)
check(not unverified and unverifiedTerminal
        and unverifiedReason == "car_delivery_unverified"
        and first.data.LF_CarUnloadJob == job.id
        and T.inventory.items[1] == first,
    "a claimed delivery without exact item ownership keeps recovery cargo")
T.falseDelivery(false)
T.visualDeposit(true)
working, reason = Unload.update(T.actor, T.base, job)
check(working and reason == "base_storage_looting"
        and T.inventory.items[1] == first and T.storage.items[1] == nil
        and first.data.LF_CarUnloadJob == job.id,
    "starting shelf animation is progress, not delivery")
working, reason = Unload.update(T.actor, T.base, job)
check(working and reason == "base_storage_looting"
        and first.data.LF_CarUnloadJob == job.id,
    "active shelf animation retains recovery ownership")
T.visual("completed")
working, reason = Unload.update(T.actor, T.base, job)
check(working and reason == "car_item_stored" and T.storage.items[1] == first
        and #T.inventory.items == 0 and first.data.LF_CarUnloadJob == nil,
    "car moving after pickup does not strand already-carried cargo")
T.visualDeposit(false)
T.car.stationary = true
local finished, finishReason, _, complete = Unload.update(T.actor, T.base, job)
check(finished and complete and finishReason == "car_trunk_unloaded",
    "job completes after an empty trunk is verified")

T.base.jobs = {}
local second = T.item("second")
T.trunk.items[1] = second
local queuedAgain, nextJob = Unload.queue(T.car.id)
check(queuedAgain, "new cargo can queue a new job")
Unload.update(T.actor, T.base, nextJob)
T.visual("completed")
Unload.update(T.actor, T.base, nextJob)
local cancelled = Unload.cancel(T.actor, nextJob)
check(cancelled and T.trunk.items[1] == second and #T.inventory.items == 0
        and second.data.LF_CarUnloadJob == nil and nextJob.assignedId == nil,
    "cancelling returns the exact carried item to the native trunk")
nextJob.assignedId = "missing_worker"
check(Unload.cancel(nil, nextJob) == false,
    "missing assigned worker cannot silently discard a recovery receipt")
nextJob.assignedId = nil

-- A blocked old order may be cancelled after the actor has started a newer
-- native visual for another order. Its historical assignment is not ownership.
T.base.jobs = {}
T.trunk.items = { T.item("third") }
SC.NativeActions.clearVisual()
local queuedOld, oldJob = Unload.queue(T.car.id)
check(queuedOld, "old order queues for cancellation isolation")
Unload.update(T.actor, T.base, oldJob)
local oldToken = T.token()
T.visual("interrupted")
local newerJob = { id = "newer_job", target = oldJob.target }
Unload.update(T.actor, T.base, newerJob)
local newerToken = T.token()
check(newerToken ~= oldToken and newerToken ~= nil,
    "new order owns a distinct native visual token")
check(Unload.cancel(T.actor, oldJob) == true and T.token() == newerToken
        and T.visual() == "active" and oldJob.assignedId == nil,
    "cancelling old order preserves the new order's visual and runtime")
check(Unload.cancel(T.actor, newerJob) == true and T.visual() == "none",
    "current order cancels only its own visual")

-- Capacity is checked before the loot pose, so a heavy first item cannot
-- starve lighter cargo that the same worker can carry.
T.base.jobs = {}
local heavy, light = T.item("heavy"), T.item("light")
heavy.weight, light.weight = 5, 1
T.trunk.items = { heavy, light }
T.capacity(2)
local queuedMixed, mixedJob = Unload.queue(T.car.id)
check(queuedMixed, "mixed-weight trunk queues")
working, reason = Unload.update(T.actor, T.base, mixedJob)
check(working and reason == "car_trunk_looting", "light item starts loading")
T.visual("completed")
working, reason = Unload.update(T.actor, T.base, mixedJob)
check(working and reason == "car_item_carried" and T.inventory.items[1] == light
        and T.trunk.items[1] == heavy,
    "worker skips uncarryable first item")
working, reason = Unload.update(T.actor, T.base, mixedJob)
check(working and reason == "car_item_stored" and T.storage.items[2] == light,
    "lighter item reaches marked storage")
local blocked, blocker, capacityTerminal = Unload.update(T.actor, T.base, mixedJob)
check(not blocked and capacityTerminal and blocker == "car_unload_worker_capacity"
        and T.visual() == "none" and T.trunk.items[1] == heavy,
    "all-heavy remainder reports worker capacity before another animation")
T.capacity(nil)

T.base.jobs = {}
check(Unload.audit() == true and #T.base.jobs == 1,
    "automatic audit queues loaded parked car once")
T.car.stationary = false
check(Unload.eligible(T.car) == false,
    "moving vehicle is excluded from base unloading")
print("VEHICLE_UNLOAD_PASS checks=" .. tostring(checks))
