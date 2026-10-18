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
-- A dormant worker keeps its registry record; one who died has none, and its
-- unload must not stay unclaimable and uncancellable for good.
local registered = { missing_worker = true }
SC.Registry = { byId = function(id) return registered[id] and {} or nil end }
check(Unload.cancel(nil, nextJob) == false
        and Unload.releaseAffinity(nil, nextJob) == false
        and nextJob.assignedId == "missing_worker",
    "an unloaded worker keeps its unload assignment")
nextJob.assignedId = "dead_worker"
check(Unload.releaseAffinity(nil, nextJob) == true and nextJob.assignedId == nil,
    "a dead worker's unload can be claimed by another resident")
nextJob.assignedId = "dead_worker"
check(Unload.cancel(nil, nextJob) == true and nextJob.assignedId == nil,
    "a dead worker's unload can be cancelled")
SC.Registry = nil
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
T.car.stationary = true

-- A receipt inside a nested bag must still be rooted in this exact trunk.
local receipt = T.item("expedition-receipt")
local bag = T.item("expedition-bag")
local nested = { items = { receipt },
    getContainingItem = function() return bag end }
receipt.container, bag.container = nested, T.trunk
T.trunk.items = { bag }
local exactState = {}
local taking, takeReason = Unload.takeExact(T.actor, T.car.id,
    receipt, exactState, nested)
check(taking and takeReason == "car_trunk_looting"
        and receipt.container == nested,
    "nested exact trunk receipt begins a native loot pose")
T.visual("completed")
taking, takeReason = Unload.takeExact(T.actor, T.car.id,
    receipt, exactState, nested)
check(taking and takeReason == "car_item_carried"
        and receipt.container == T.inventory,
    "nested exact receipt transfers only after the pose completes")
local other = { items = { bag } }
bag.container = other
T.trunk.items = {}
local escaped = T.item("escaped-receipt")
escaped.container, nested.items = nested, { escaped }
taking, takeReason = Unload.takeExact(T.actor, T.car.id,
    escaped, {}, nested)
check(not taking and takeReason == "car_trunk_item_changed",
    "moving its whole bag outside the trunk cannot transfer the receipt")

local reserved, ordinary = T.item("reserved"), T.item("ordinary")
T.trunk.items = { reserved, ordinary }
reserved.container, ordinary.container = T.trunk, T.trunk
SC.ExpeditionPrototype = { receiptPending = function(item)
    return item == reserved end }
T.base.jobs = {}
check(Unload.rows()[1].count == 1,
    "the normal car job counts only cargo outside expedition receipts")
local regularQueued, regularJob = Unload.queue(T.car.id)
check(regularQueued == true, "ordinary cargo remains available to the car job")
working, reason = Unload.update(T.actor, T.base, regularJob)
check(working and reason == "car_trunk_looting",
    "the normal job chooses unrelated cargo instead of the receipt")
T.visual("completed")
working, reason = Unload.update(T.actor, T.base, regularJob)
check(working and reason == "car_item_carried"
        and ordinary.container == T.inventory and reserved.container == T.trunk,
    "the pending expedition receipt remains in the trunk")
Unload.update(T.actor, T.base, regularJob)
local done, _, _, complete = Unload.update(T.actor, T.base, regularJob)
check(done and complete and reserved.container == T.trunk,
    "the general car job completes without taking the reserved receipt")
T.base.jobs = {}
check(select(2, Unload.queue(T.car.id)) == "car_trunk_empty_or_reserved",
    "manual general unload cannot claim a trunk of only expedition receipts")

SC.TaxiCab = { isOwned = function(value) return value == T.car end }
check(select(2, Unload.eligible(T.car)) == "service_cab_reserved"
        and #Unload.rows() == 0,
    "Markus's cab stays out of parked-car unloading")
check(select(2, Unload.queue(T.car.id)) == "service_cab_reserved",
    "manual unload cannot strip the service cab")
print("VEHICLE_UNLOAD_PASS checks=" .. tostring(checks))
