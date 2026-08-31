-- SPDX-License-Identifier: MIT

local SC = SurvivorCompanion
local Supervisor = SC.ActionSupervisor

local assertions = 0
local function check(condition, message)
    assertions = assertions + 1
    if not condition then error("ACTION_SUPERVISOR_TEST_FAILED: " .. tostring(message)) end
end

local function testActor(id)
    local value = { id = id, x = 10, y = 10, z = 0 }
    function value:getX() return self.x end
    function value:getY() return self.y end
    function value:getZ() return self.z end
    return value
end

Supervisor.reset(nil, "fixture")
local actor = testActor("supervisor-a")
local cancelled = 0
local work = assert(Supervisor.begin(actor, {
    owner = "scavenge", action = "loot_container", targetKey = "container:1",
    priority = Supervisor.Priority.WORK, interruptible = true,
    allowedActions = { loot_container = true },
    onCancel = function(_, reason)
        cancelled = cancelled + 1
        return true, reason
    end,
}))
check(Supervisor.current(actor) == work and work.phase == "selected",
    "begin creates one actor-wide owner")
local duplicate, duplicateReason = Supervisor.begin(actor, {
    owner = "scavenge", action = "loot_container", targetKey = "container:1",
    priority = Supervisor.Priority.WORK,
})
check(duplicate == work and duplicateReason == "already_active",
    "same action reuses its token")
local rejected, rejectedReason = Supervisor.begin(actor, {
    owner = "downtime", action = "read", priority = Supervisor.Priority.DOWNTIME,
})
check(rejected == nil and string.find(rejectedReason, "actor_owned_by", 1, true) ~= nil,
    "lower-priority action cannot replace an owner")
local urgent = assert(Supervisor.begin(actor, {
    owner = "combat", action = "escape", priority = Supervisor.Priority.SURVIVAL,
    interruptible = true,
}))
check(cancelled == 1 and Supervisor.current(actor) == urgent,
    "survival pre-emption invokes rollback before ownership transfer")
check(Supervisor.complete(urgent, "safe") == true and Supervisor.current(actor) == nil,
    "completion releases actor ownership")

local resource = {}
local transaction = assert(Supervisor.begin(actor, {
    owner = "medical", action = "replace_dirty_bandage", targetKey = "arm:left",
    priority = Supervisor.Priority.NEEDS, requiresVisual = true,
}))
check(Supervisor.reserve(transaction, resource, "bandage") == true
    and Supervisor.reservationCount(actor) == 1, "reservation belongs to action token")
check(not Supervisor.transition(transaction, "committing"),
    "commit is rejected before required visual verification")
check(Supervisor.transition(transaction, "animating") == true,
    "transaction enters protected visual phase")
actor.x = actor.x + 0.4
Supervisor.update(actor)
local movedSnapshot = Supervisor.snapshot(actor)
check(movedSnapshot and movedSnapshot.protectedPose == true,
    "protected pose remains observable after displacement violation")
check(Supervisor.markVisualVerified(transaction) == true
    and Supervisor.transition(transaction, "committing") == true,
    "verified visual permits one commit phase")
check(Supervisor.transition(transaction, "verifying") == true
    and Supervisor.complete(transaction, "bandaged", { verified = true }) == true,
    "verified transaction reaches one terminal result")
check(Supervisor.reservationCount(actor) == 0 and Supervisor.leakedReservations() == 0,
    "terminal action releases every supervisor reservation")
check(not Supervisor.complete(transaction, "again"), "terminal token cannot commit twice")

local failure = assert(Supervisor.begin(actor, {
    owner = "logistics", action = "wear_armor", targetKey = "vest:1",
    priority = Supervisor.Priority.WORK, retryCategory = "transaction",
}))
check(Supervisor.fail(failure, "verification_failed") == true,
    "failure reaches a terminal state")
local retry = Supervisor.retryStatus(actor, "wear_armor", "vest:1", "transaction")
check(retry and retry.attempts == 1 and retry.remainingMs > 0,
    "failure creates a bounded retry record")
local cooled, cooledReason = Supervisor.begin(actor, {
    owner = "logistics", action = "wear_armor", targetKey = "vest:1",
    priority = Supervisor.Priority.WORK, retryCategory = "transaction",
})
check(cooled == nil and cooledReason == "retry_cooldown",
    "unchanged failure cannot restart every scheduler tick")
local cooledAny, cooledAnyReason = Supervisor.begin(actor, {
    owner = "logistics", action = "wear_armor", targetKey = "vest:1",
    priority = Supervisor.Priority.WORK, retryCategory = "*",
})
check(cooledAny == nil and cooledAnyReason == "retry_cooldown",
    "transaction start can honor any active failure category for its target")
local cooledDefault, cooledDefaultReason = Supervisor.begin(actor, {
    owner = "logistics", action = "wear_armor", targetKey = "vest:1",
    priority = Supervisor.Priority.WORK,
})
check(cooledDefault == nil and cooledDefaultReason == "retry_cooldown",
    "default transaction retry policy cannot bypass a differently classified failure")
SC_TEST_CLOCK = SC_TEST_CLOCK + (SC.Config.get("actionRetryBaseMs") or 1500) + 1
check(Supervisor.begin(actor, {
    owner = "logistics", action = "wear_armor", targetKey = "vest:1",
    priority = Supervisor.Priority.WORK, retryCategory = "transaction",
}) ~= nil, "action becomes eligible after its bounded cooldown")
Supervisor.reset(actor, "fixture_done")

local timeoutActor = testActor("supervisor-timeout")
local timeoutCancelled = 0
local timeout = assert(Supervisor.begin(timeoutActor, {
    owner = "work", action = "approach_job", phase = "approaching",
    priority = Supervisor.Priority.WORK, deadlines = { approaching = 10 },
    onCancel = function() timeoutCancelled = timeoutCancelled + 1 return true end,
}))
SC_TEST_CLOCK = SC_TEST_CLOCK + 11
Supervisor.update(timeoutActor)
check(timeoutCancelled == 1 and not Supervisor.isCurrent(timeout),
    "phase timeout invokes cancellation and releases the owner")
local timeoutHistory = Supervisor.history(timeoutActor, 4)
check(#timeoutHistory > 0 and timeoutHistory[#timeoutHistory].phase == "failed",
    "public bounded history records terminal timeout evidence")
local timeoutSummary = Supervisor.summary(timeoutActor)
local supervisorHealth = Supervisor.health()
check(timeoutSummary.active == false
        and timeoutSummary.lastFailure.action == "approach_job"
        and timeoutSummary.lastFailure.failureCategory ~= nil
        and timeoutSummary.retry.remainingMs > 0,
    "public action summary exposes the latest stable failure and retry window")
check(supervisorHealth.active == 0 and supervisorHealth.reservations == 0
        and supervisorHealth.leakedReservations == 0
        and supervisorHealth.coolingDown >= 1
        and supervisorHealth.invariantViolations >= 1,
    "public supervisor health reports bounded retries, invariants, and reservation leaks")

print("ACTION_SUPERVISOR_PASS assertions=" .. tostring(assertions))
