-- SPDX-License-Identifier: MIT
local SC, T = SurvivorCompanion, SC_REFUEL_TEST
local Refuel = SC.VehicleRefuel
local checks = 0
local function check(value, message)
    checks = checks + 1
    assert(value, "vehicle refuel check " .. checks .. ": " .. message)
end
local function update(job)
    return Refuel.update(T.actor, {}, job)
end

local mixed = T.item(1, 10, true)
T.storage.container.items = { mixed }
local mixedReason = select(2, Refuel.queue(T.car.id, true))
check(Refuel.gasAmount(mixed) == 0 and mixedReason == "base_gasoline_missing",
    "mixed fuel is never placed into a car: " .. tostring(mixedReason))
local memorialFuel = T.item(2, 10)
T.memorial.container.items = { memorialFuel }
check(select(2, Refuel.queue(T.car.id, true)) == "base_gasoline_missing",
    "memorial stock is excluded")
local can = T.item(3, 12)
T.storage.container.items = { can }
T.storage.reserve = 1
check(select(2, Refuel.queue(T.car.id, true)) == "base_gasoline_missing",
    "marked reserve cannot be borrowed")
T.storage.reserve = 0

T.part.current = 30
check(select(2, Refuel.queue(T.car.id, false)) ==
    "car_above_auto_refuel_threshold", "automatic threshold is below half")
local queued, manual = Refuel.queue(T.car.id, true)
check(queued and manual.priority == 5 and manual.target.manual == true,
    "manual order works above the automatic threshold")
T.base.jobs = {}
T.part.current = 20
check(Refuel.audit() == true and #T.base.jobs == 1,
    "automatic audit queues one parked car below half")
local job = T.base.jobs[1]
check(job.priority == 2 and job.target.manual == false,
    "automatic work remains an ordinary base chore")
check(Refuel.queue(T.car.id, true) == true and job.priority == 5
    and job.target.manual == true and #T.base.jobs == 1,
    "manual command upgrades the existing chore")

local working, reason = update(job)
check(working and reason == "car_refuel_can_carried"
    and T.actor.inventory.items[1] == can
    and can.data.LF_RefuelJobId == job.id
    and job.target.sourceStorageId == T.storage.id,
    "the exact saved can moves to the worker")
check(Refuel.releaseAffinity(T.actor, job) == false,
    "a carrying worker cannot lose the receipt to another worker")
check(Refuel.canContinue(T.actor, T.car, T.part, can, job.id) == true,
    "native work is valid at the fuel-side square")
T.clock(T.clock() + 90001)
working, reason = update(job)
check(not working and reason == "car_refuel_carrying_timeout"
    and job.target.stageStartedAt == nil
    and T.actor.inventory.items[1] == can
    and can.data.LF_RefuelJobId == job.id,
    "a timed-out carrying attempt retains its exact can and renews on retry")
T.clock(T.clock() + 200000)
local savedPosition, savedGrid, savedNavigation = SC.GameplayUtil.position,
    SC.GameplayUtil.gridSquare, SC.Navigation.requestAny
local actorX, actorY = 13.5, 10.5
SC.GameplayUtil.position = function(value)
    if value == T.actor then return actorX, actorY, 0 end
    return savedPosition(value)
end
SC.GameplayUtil.gridSquare = function(x, y, z)
    return { x = x, y = y, z = z }
end
SC.Navigation.requestAny = function(_, goals, _, intent)
    check(#goals > 0 and intent.arrivalDistance == 0.15,
        "fuel navigation uses precise terminal arrival")
    for _, goal in ipairs(goals) do
        local centreX, centreY = goal.x + 0.5, goal.y + 0.5
        check(math.sqrt((centreX - 10) ^ 2 + (centreY - 10) ^ 2)
            + intent.arrivalDistance <= 1.600001,
            "every accepted terminal goal lies within fuel range")
    end
    actorX, actorY = goals[1].x + 0.5, goals[1].y + 0.5
    return true, "arrived"
end
working, reason = update(job)
check(working and reason == "arrived"
    and Refuel.atFuelSide(T.actor, T.car, T.part) == true,
    "a worker outside fuel range reaches a usable fuel-side goal")
SC.GameplayUtil.position, SC.GameplayUtil.gridSquare, SC.Navigation.requestAny =
    savedPosition, savedGrid, savedNavigation
working, reason = update(job)
check(working and reason == "car_refuel_action_started" and T.nativeActive(),
    "the worker starts one native fueling action")
T.finishAction(12)
working, reason = update(job)
check(working and reason == "car_refuel_verified" and T.part.current == 32
    and can.fluid.amount == 0 and job.target.stage == "returning",
    "tank gain and can loss must agree before return")
T.clock(T.clock() + 90001)
working, reason = update(job)
check(not working and reason == "car_refuel_returning_timeout"
    and job.target.stageStartedAt == nil and T.actor.inventory.items[1] == can,
    "a timed-out return retains the same can")
T.clock(T.clock() + 200000)
T.deferReturn(true)
working, reason = update(job)
check(working and reason == "approaching_base_storage"
    and can.data.LF_RefuelJobId == job.id,
    "accepted return approach keeps ownership")
T.deferReturn(false)
T.rejectReturn(true)
working, reason, _, done = update(job)
check(working and done and reason == "car_refuel_fuel_exhausted"
    and T.storage.container.items[1] == can
    and #T.actor.inventory.items == 0
    and can.data.LF_RefuelJobId == nil,
    "a rejected storage pose still returns the exact can from a verified use square")
T.rejectReturn(false)

T.base.jobs = {}
can.fluid.amount = 10
T.part.current = 15
local again, interrupted = Refuel.queue(T.car.id, true)
check(again, "second order can start")
update(interrupted)
update(interrupted)
T.finishAction(4)
T.resetNative() -- a load loses transient native action state
working, reason = update(interrupted)
check(working and reason == "car_refuel_verified"
    and interrupted.target.stage == "returning",
    "saved readings reconcile partial fuel after reload")
check(Refuel.cancel(T.actor, interrupted) == true
    and T.storage.container.items[1] == can
    and can.fluid.amount == 6 and T.part.current == 19
    and can.data.LF_RefuelJobId == nil,
    "cancellation returns the same partially used can without duplication")

T.base.jobs = {}
can.fluid.amount = 10
T.part.current = 10
local third, uncertain = Refuel.queue(T.car.id, true)
check(third, "uncertain case queues")
update(uncertain)
update(uncertain)
T.finishAction(4)
T.part.current = 18 -- an unexplained tank change cannot be claimed as ours
working, reason, done = update(uncertain)
check(not working and done and reason == "car_refuel_conservation_uncertain"
    and can.data.LF_RefuelJobId == uncertain.id
    and T.actor.inventory.items[1] == can,
    "uncertain amount keeps both the exact can and receipt")

T.car.engine = true
check(select(2, Refuel.eligible(T.car, true)) == "car_engine_on",
    "running engines are excluded")
T.car.engine = false
SC.TaxiCab = { isOwned = function(value) return value == T.car end }
check(select(2, Refuel.eligible(T.car, true)) == "service_cab_reserved",
    "service taxi is excluded")
print("VEHICLE_REFUEL_PASS checks=" .. tostring(checks))
