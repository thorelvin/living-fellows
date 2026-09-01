-- SPDX-License-Identifier: MIT

local SC = SurvivorCompanion
local Supervisor = SC.ActionSupervisor

local assertions = 0
local function check(condition, message)
    assertions = assertions + 1
    if not condition then error("ACTION_SUPERVISOR_TEST_FAILED: " .. tostring(message)) end
end

local function testActor(id)
    local value = { id = id, x = 10, y = 10, z = 0, modData = {}, dead = false }
    function value:getX() return self.x end
    function value:getY() return self.y end
    function value:getZ() return self.z end
    function value:getModData() return self.modData end
    function value:isDead() return self.dead == true end
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

local invalidOrder = assert(Supervisor.begin(actor, {
    owner = "test", action = "invalid_order", ignoreRetry = true,
}))
local invalidAccepted, invalidReason = Supervisor.transition(invalidOrder, "verifying")
check(invalidAccepted ~= true
        and invalidReason == "illegal_phase_transition:selected:verifying",
    "the explicit phase graph rejects verification before commit")
Supervisor.cancel(actor, "invalid_order_fixture", nil, true)

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
local physicalCommits = 0
local committed, commitReason, commitReceipt = Supervisor.commit(transaction, function()
    physicalCommits = physicalCommits + 1
    return true, "bandage_effect_committed", { mutation = "bandage", serial = 1 }
end)
check(committed == true and commitReason == "bandage_effect_committed"
        and commitReceipt.mutation == "bandage" and physicalCommits == 1,
    "commit receipt records one accepted physical mutation")
local duplicateCommit, duplicateCommitReason = Supervisor.commit(transaction, function()
    physicalCommits = physicalCommits + 1
    return true
end)
check(duplicateCommit ~= true and duplicateCommitReason == "commit_already_attempted"
        and physicalCommits == 1,
    "the exactly-once commit API never invokes a second mutation")
check(Supervisor.transition(transaction, "verifying") == true
    and Supervisor.complete(transaction, "bandaged", { verified = true }) == true,
    "verified transaction reaches one terminal result")
check(Supervisor.reservationCount(actor) == 0 and Supervisor.leakedReservations() == 0,
    "terminal action releases every supervisor reservation")
check(not Supervisor.complete(transaction, "again"), "terminal token cannot commit twice")

local urgentActor = testActor("supervisor-urgent")
local commitOwner = assert(Supervisor.begin(urgentActor, {
    owner = "medical", action = "apply_treatment", targetKey = "patient:1",
    priority = Supervisor.Priority.NEEDS, interruptible = true,
}))
check(Supervisor.transition(commitOwner, "committing") == true,
    "urgent queue fixture enters its non-cancellable phase")
local urgentDispatches = 0
local queued, queueReason = Supervisor.queueUrgent(urgentActor, {
    owner = "locomotion", action = "combat_retreat",
    priority = Supervisor.Priority.SURVIVAL,
    dispatch = function(_, queuedIntent)
        urgentDispatches = urgentDispatches + 1
        return true, "retreat_dispatched", { serial = queuedIntent.serial }
    end,
})
check(queued == true and queueReason == "urgent_queued"
        and urgentDispatches == 0
        and Supervisor.urgentStatus(urgentActor).state == "queued",
    "one bounded urgent intent waits instead of overwriting a commit owner")
local secondUrgent, secondUrgentReason = Supervisor.queueUrgent(urgentActor, {
    owner = "combat", action = "shove", dispatch = function() return true end,
})
check(secondUrgent ~= true and secondUrgentReason == "urgent_queue_occupied",
    "the per-actor urgent queue is bounded to one intent")
check(Supervisor.commit(commitOwner, { mutation = "treatment" }) == true
        and Supervisor.transition(commitOwner, "verifying") == true
        and Supervisor.complete(commitOwner, "verified") == true,
    "the original commit finishes through its legal receipt and verification")
local dispatchedUrgent = Supervisor.urgentStatus(urgentActor)
check(urgentDispatches == 1 and dispatchedUrgent.state == "dispatched"
        and dispatchedUrgent.reason == "retreat_dispatched",
    "the queued urgent intent is eventually dispatched and observable")

local externalActor = testActor("supervisor-external")
local originalActivityStatus = SC.NativeActions.activityStatus
SC.NativeActions.activityStatus = function(candidate)
    if candidate == externalActor then
        return "active", "native", "third_party_timed_action", SC_TEST_CLOCK, {}
    end
    return originalActivityStatus(candidate)
end
local externalToken, externalReason, externalSnapshot = Supervisor.begin(externalActor, {
    owner = "work", action = "loot_container", ignoreRetry = true,
})
check(externalToken == nil
        and string.find(externalReason, "external_action_owned:native:third_party_timed_action", 1, true) == 1
        and externalSnapshot.external == true,
    "begin refuses an unknown native or third-party timed-action owner")
SC.NativeActions.activityStatus = originalActivityStatus

local combatActor = testActor("supervisor-combat-unowned")
local combatAuthorized, combatReason = SC.Locomotion.authorize(combatActor, "walk", {
    action = "attack_melee", urgent = true,
})
check(combatAuthorized == true and combatReason == "interact",
    "an unowned production combat action needs no supervisorToken")

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

local exhaustionActor = testActor("supervisor-exhaustion")
local exhaustionAction, exhaustionTarget = "stable_failure", "target:stable"
local maximumAttempts = tonumber(SC.Config.get("actionRetryMaxAttempts")) or 4
check(maximumAttempts == 4, "retry exhaustion fixture uses the configured four attempts")
for attempt = 1, maximumAttempts do
    local attemptToken, attemptReason = Supervisor.begin(exhaustionActor, {
        owner = "test", action = exhaustionAction, targetKey = exhaustionTarget,
        retryCategory = "transaction",
    })
    check(attemptToken ~= nil, "configured retry attempt " .. tostring(attempt)
        .. " begins after its prior cooldown: " .. tostring(attemptReason))
    check(Supervisor.fail(attemptToken, "verification_failed") == true,
        "configured retry attempt " .. tostring(attempt) .. " records failure")
    local attemptStatus = Supervisor.retryStatus(exhaustionActor,
        exhaustionAction, exhaustionTarget, "transaction")
    check(attemptStatus and attemptStatus.attempts == attempt,
        "retry ledger counts attempt " .. tostring(attempt))
    if attempt < maximumAttempts then
        SC_TEST_CLOCK = (tonumber(attemptStatus.retryAt) or SC_TEST_CLOCK) + 1
    end
end
local exhaustedToken, exhaustedReason = Supervisor.begin(exhaustionActor, {
    owner = "test", action = exhaustionAction, targetKey = exhaustionTarget,
    retryCategory = "transaction",
})
check(exhaustedToken == nil and exhaustedReason == "retry_exhausted",
    "the configured fourth failure is terminal until an explicit reset")
local priorGeneration = Supervisor.retryResetStatus(exhaustionActor).generation
local cleared, resetReceipt = Supervisor.resetRetry(exhaustionActor,
    "target_generation_changed", exhaustionAction, exhaustionTarget)
check(cleared == 1 and resetReceipt.generation == priorGeneration + 1
        and resetReceipt.reason == "target_generation_changed",
    "retry reset is explicit, generation-stamped, and reasoned")
local afterReset = assert(Supervisor.begin(exhaustionActor, {
    owner = "test", action = exhaustionAction, targetKey = exhaustionTarget,
    retryCategory = "transaction",
}))
Supervisor.cancel(exhaustionActor, "reset_fixture_done", nil, true)
check(not Supervisor.isCurrent(afterReset), "explicit reset makes a fresh attempt eligible")

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
check(timeoutSummary.lastFailure.failureCategory ~= "unknown",
    "terminal stable failures never expose an unknown category")
check(supervisorHealth.active == 0 and supervisorHealth.reservations == 0
        and supervisorHealth.leakedReservations == 0
        and supervisorHealth.coolingDown >= 1
        and supervisorHealth.invariantViolations >= 1,
    "public supervisor health reports bounded retries, invariants, and reservation leaks")

local provider = {
    testOnly = true,
    isActor = function(_, candidate) return candidate ~= nil end,
    remove = function() return true end,
    retireDead = function() return true end,
}
check(SC.Actor._setProviderForTests(provider) == true,
    "actor cleanup fixture installs its bounded provider")
local removeActor = testActor("remove-cleanup")
removeActor.modData.SC_Id = "sc-remove-cleanup"
assert(SC.Registry.register(removeActor, { id = removeActor.modData.SC_Id }))
local removeCancelled = 0
local removeToken = assert(Supervisor.begin(removeActor, {
    owner = "work", action = "remove_cleanup", ignoreRetry = true,
    onCancel = function() removeCancelled = removeCancelled + 1 return true end,
}))
local removeResource = {}
Supervisor.reserve(removeToken, removeResource, "remove-resource")
check(SC.Actor.remove(removeActor) == true
        and removeCancelled == 1 and Supervisor.current(removeActor) == nil
        and Supervisor.reservationCount(removeActor) == 0
        and Supervisor.leakedReservations() == 0,
    "actor removal cancels ownership and releases reservations exactly once")

local deadActor = testActor("death-cleanup")
deadActor.dead = true
deadActor.modData.SC_Id = "sc-death-cleanup"
assert(SC.Registry.register(deadActor, { id = deadActor.modData.SC_Id }))
local deathCancelled = 0
local deathToken = assert(Supervisor.begin(deadActor, {
    owner = "medical", action = "death_cleanup", ignoreRetry = true,
    onCancel = function() deathCancelled = deathCancelled + 1 return true end,
}))
Supervisor.reserve(deathToken, {}, "death-resource")
check(SC.Actor.retireDead(deadActor) == true
        and deathCancelled == 1 and Supervisor.current(deadActor) == nil
        and Supervisor.reservationCount(deadActor) == 0
        and Supervisor.leakedReservations() == 0,
    "permanent death cleanup releases actor-wide ownership and reservations")

local unloadActor = testActor("unload-cleanup")
unloadActor.modData.SC_Id = "sc-unload-cleanup"
assert(SC.Registry.register(unloadActor, { id = unloadActor.modData.SC_Id }))
local unloadCancelled = 0
local unloadToken = assert(Supervisor.begin(unloadActor, {
    owner = "downtime", action = "unload_cleanup", ignoreRetry = true,
    onCancel = function() unloadCancelled = unloadCancelled + 1 return true end,
}))
Supervisor.reserve(unloadToken, {}, "unload-resource")
check(SC.Actor.disposeAll() == true
        and unloadCancelled == 1 and Supervisor.current(unloadActor) == nil
        and Supervisor.reservationCount(unloadActor) == 0
        and Supervisor.leakedReservations() == 0,
    "world unload clears every per-actor owner before provider disposal")
SC.Registry.reset()

print("ACTION_SUPERVISOR_PASS assertions=" .. tostring(assertions))
