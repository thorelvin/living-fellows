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
T.deferDeposit(true)
local pending, pendingReason, terminal = Unload.update(T.actor, T.base, job)
check(not pending and pendingReason == "approaching_base_storage"
        and terminal ~= true and T.inventory.items[1] == first,
    "walking to storage keeps job and cargo rather than blocking it")
T.car.stationary = false
T.deferDeposit(false)
working, reason = Unload.update(T.actor, T.base, job)
check(working and reason == "car_item_stored" and T.storage.items[1] == first
        and first.data.LF_CarUnloadJob == nil,
    "car moving after pickup does not strand already-carried cargo")
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
        and second.data.LF_CarUnloadJob == nil,
    "cancelling returns the exact carried item to the native trunk")
check(Unload.cancel(nil, nextJob) == false,
    "missing assigned worker cannot silently discard a recovery receipt")

T.base.jobs = {}
check(Unload.audit() == true and #T.base.jobs == 1,
    "automatic audit queues loaded parked car once")
T.car.stationary = false
check(Unload.eligible(T.car) == false,
    "moving vehicle is excluded from base unloading")
print("VEHICLE_UNLOAD_PASS checks=" .. tostring(checks))
