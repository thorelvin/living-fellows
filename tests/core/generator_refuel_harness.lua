-- SPDX-License-Identifier: MIT
local SC, T = SurvivorCompanion, SC_GENERATOR_REFUEL_TEST
local Refuel = SC.GeneratorRefuel
local checks = 0
local function check(value, message)
    checks = checks + 1
    assert(value, "generator refuel check " .. checks .. ": " .. message)
end
local function update(job)
    return Refuel.update(T.actor, {}, job)
end

local mixed = T.item(1, 10, true)
T.storage.container.items = { mixed }
check(Refuel.queue(T.generator, true) == false
    and SC.BaseFuel.gasAmount(mixed) == 0,
    "mixed fluid never reaches the stock generator action")
T.storage.container.items = {}
T.memorial.container.items = { T.item(2, 10) }
check(select(2, Refuel.queue(T.generator, true)) == "base_gasoline_missing",
    "memorial fuel is excluded")
local can = T.item(3, 12)
T.storage.container.items = { can }
T.storage.reserve = 1
check(select(2, Refuel.queue(T.generator, true)) == "base_gasoline_missing",
    "storage reserve is respected")
T.storage.reserve = 0
local heldCan = T.item(4, 12)
T.storage.container.items = { can, heldCan }
T.storage.reserve = 1
local other = { id = "other-job", type = "refuel_vehicle", state = "active",
    target = { itemId = can:getID() } }
T.base.jobs[#T.base.jobs + 1] = other
can.data.LF_RefuelJobId = other.id
check(SC.BaseFuel.sourceCan(nil) == nil,
    "another refuel job cannot consume the reserved last can")
T.base.jobs[#T.base.jobs] = nil
check(select(3, SC.BaseFuel.sourceCan(nil)) == can,
    "a marker whose job has gone no longer hides the last can")
can.data.LF_RefuelJobId = nil
T.storage.container.items = { can }
T.storage.reserve = 0

T.generator.fuel = 60
check(select(2, Refuel.queue(T.generator, false)) ==
    "generator_above_auto_refuel_threshold",
    "automatic work starts only below half")
T.generator.activated = false
T.generator.fuel = 20
check(select(2, Refuel.queue(T.generator, false)) == "generator_not_running",
    "an idle spare is not automatically fueled")
check(Refuel.audit() == false and #T.base.jobs == 0,
    "automatic scan skips an idle generator")
T.generator.activated = true
check(Refuel.audit() == true and #T.base.jobs == 1,
    "bounded scan discovers a running generator")
local job = T.base.jobs[1]
check(job.type == "refuel_generator" and job.priority == 2
    and job.target.objectId == "object:1", "automatic job saves exact identity")
check(Refuel.queue(T.generator, true) == true and #T.base.jobs == 1
    and job.priority == 5 and job.target.manual == true,
    "manual command upgrades the existing job")

local working, reason = update(job)
check(working and reason == "generator_refuel_can_carried"
    and T.actor.inventory.items[1] == can
    and can.data.LF_RefuelJobId == job.id,
    "worker owns the exact can")
check(Refuel.releaseAffinity(T.actor, job) == false,
    "carrying work cannot be reassigned")
working, reason = update(job)
check(working and reason == "generator_refuel_action_started"
    and T.nativeActive()
    and Refuel.canContinue(T.actor, T.generator, can, job.id),
    "native action starts at direct access")
T.generator.fuel = T.generator.fuel - 2 -- running burn before completion
T.finishAction()
working, reason = update(job)
check(working and reason == "generator_refuel_verified"
    and T.generator.fuel == 30 and can.fluid.amount == 0,
    "atomic receipt verifies transfer despite earlier running burn")
working, reason, _, done = update(job)
check(working and done and reason == "generator_refuel_fuel_exhausted"
    and T.storage.container.items[1] == can
    and #T.actor.inventory.items == 0
    and can.data.LF_RefuelJobId == nil,
    "partly completed job returns the same can")

T.base.jobs = {}
T.generator.activated = false
T.generator.fuel = 94
can.fluid.amount = 10
local accepted, manual = Refuel.queue(T.generator, true)
check(accepted, "manual job also works on an off generator")
update(manual)
update(manual)
T.finishAction()
working, reason = update(manual)
check(working and reason == "generator_refuel_verified"
    and T.generator.fuel == 100 and can.fluid.amount == 4,
    "stock action transfers only tank capacity")
working, reason, _, done = update(manual)
check(working and done and reason == "generator_full"
    and T.storage.container.items[1] == can,
    "full generator stops even when can still has fuel")

T.base.jobs = {}
T.generator.fuel = 85
can.fluid.amount, heldCan.fluid.amount = 8, 10
T.storage.container.items = { can, heldCan }
local _, multi = Refuel.queue(T.generator, true)
update(multi)
update(multi)
T.finishAction()
update(multi)
working, reason, _, done = update(multi)
check(working and not done and reason == "generator_refuel_next_can"
    and T.generator.fuel == 93 and can.fluid.amount == 0,
    "a partly filled generator requests another stored can")
update(multi)
update(multi)
T.finishAction()
update(multi)
working, reason, _, done = update(multi)
check(working and done and reason == "generator_full"
    and T.generator.fuel == 100 and heldCan.fluid.amount == 3
    and heldCan.data.LF_RefuelJobId == nil,
    "second can completes the same job and returns its residual fuel")

T.base.jobs = {}
T.storage.container.items = { can }
T.generator.fuel = 15
can.fluid.amount = 8
local _, interrupted = Refuel.queue(T.generator, true)
update(interrupted)
update(interrupted)
T.resetNative() -- queued stock actions do not survive a load
working, reason = update(interrupted)
check(working and reason == "generator_refuel_retry"
    and interrupted.target.stage == "carrying" and can.fluid.amount == 8,
    "reload before transfer resumes without spending fuel")
check(Refuel.cancel(T.actor, interrupted) == true
    and T.storage.container.items[1] == can
    and can.data.LF_RefuelJobId == nil,
    "cancellation returns the can")

T.base.jobs = {}
T.generator.fuel = 15
can.fluid.amount = 8
local _, uncertain = Refuel.queue(T.generator, true)
update(uncertain)
update(uncertain)
T.finishAction(false)
T.resetNative()
local fuelBefore = T.generator.fuel
working, reason, done = update(uncertain)
check(working and not done and reason == "generator_refuel_returning_can"
    and uncertain.target.stage == "returning"
    and uncertain.target.finishReason == "generator_refuel_receipt_uncertain"
    and can.data.LF_RefuelJobId == uncertain.id
    and T.actor.inventory.items[1] == can and T.generator.fuel == fuelBefore,
    "a missing receipt takes the can home rather than repeating a transfer")
local function stored(item)
    for _, value in ipairs(T.storage.container.items) do
        if value == item then return true end
    end
    return false
end
T.storage.container.items = {}
check(Refuel.cancel(T.actor, uncertain) == true and stored(can)
    and can.data.LF_RefuelJobId == nil,
    "cancelling on the way home still returns the can")
uncertain.target.stage, uncertain.target.sourceStorageId = "refueling", T.storage.id
uncertain.target.itemId, uncertain.target.canBefore = can:getID(), 99
can.data.LF_RefuelJobId = uncertain.id
T.actor.inventory.items, T.storage.container.items = { can }, {}
check(Refuel.cancel(T.actor, uncertain) == true and stored(can)
    and can.data.LF_RefuelJobId == nil,
    "the player can cancel a pour whose receipt does not add up, and the can goes home")
local registered = { worker = true }
SC.Registry = { byId = function(id) return registered[id] and {} or nil end }
uncertain.target.stage, uncertain.target.sourceStorageId = "carrying", T.storage.id
uncertain.target.itemId, uncertain.assignedId, uncertain.reservedBy = 99, "worker", "worker"
check(Refuel.cancel(nil, uncertain) == false
    and Refuel.releaseAffinity(nil, uncertain) == false,
    "an unloaded worker keeps its generator receipt")
uncertain.assignedId, uncertain.reservedBy = "ghost", "ghost"
check(Refuel.releaseAffinity(nil, uncertain) == true
    and uncertain.assignedId == nil and uncertain.target.stage == nil,
    "a dead worker's generator receipt is released for another resident")
SC.Registry = nil
T.base.jobs = {}
SC.BaseFuel.clearMark(can, uncertain.id)
T.actor.inventory.items = {}
T.storage.container.items = { can }
T.generator.activated = true
T.generator.fuel = 15
can.fluid.amount = 8

T.moveGenerator(16, 10)
Refuel.reset()
check(Refuel.audit() == true and #T.base.jobs == 1,
    "six-tile base band includes an outdoor generator")
T.base.jobs = {}
T.moveGenerator(17, 10)
Refuel.reset()
check(Refuel.audit() == false and #T.base.jobs == 0,
    "generator beyond the nearby band is left alone")

print("GENERATOR_REFUEL_PASS checks=" .. tostring(checks))
