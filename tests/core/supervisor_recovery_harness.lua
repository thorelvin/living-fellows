-- SPDX-License-Identifier: MIT
--
-- Regression coverage for the 0.25.5 residual-risk hardening:
--   1. actor retirement never strands supervisor state (Kahlua weak tables are
--      a no-op, so every retirement path must hit the explicit release);
--   2. an owner whose rollback verifier never succeeds is force-released after a
--      bounded quarantine instead of owning the actor forever;
--   3. urgent dispatch during begin() is reported as a deferral, not a refusal.

local SC = SurvivorCompanion
local Supervisor = SC.ActionSupervisor

local assertions = 0
local function check(condition, message)
    assertions = assertions + 1
    if not condition then
        error("SUPERVISOR_RECOVERY_TEST_FAILED: " .. tostring(message))
    end
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

local quarantineMs = SC.Config.get("actionRollbackQuarantineMs") or 5000
local rollbackAttempts = SC.Config.get("actionRollbackMaxAttempts") or 4
local rollbackRetryMs = SC.Config.get("actionRollbackRetryMs") or 250

-- ---------------------------------------------------------------------------
-- 1. Deferral vocabulary
-- ---------------------------------------------------------------------------
Supervisor.reset(nil, "recovery_fixture")

check(Supervisor.isDeferredStatus("urgent_dispatched:flee") == true
        and Supervisor.isDeferredStatus("actor_owned_after_urgent_dispatch:work:chop") == true
        and Supervisor.isDeferredStatus("actor_owned_after_preemption:survival:flee") == true,
    "every urgent/preemption status is classified as a deferral")
check(Supervisor.isDeferredStatus("actor_owned_by:work:chop") == false
        and Supervisor.isDeferredStatus("retry_exhausted") == false
        and Supervisor.isDeferredStatus("external_action_owned:native:sit:animating") == false
        and Supervisor.isDeferredStatus(nil) == false
        and Supervisor.isDeferredStatus(42) == false,
    "a genuine refusal is never classified as a deferral")
check(Supervisor.containsDeferredStatus(
        "vehicle_transaction_rejected:urgent_dispatched:flee") == true
        and Supervisor.containsDeferredStatus("deferred:actor_owned_after_preemption:x") == true,
    "a deferral survives being wrapped in an adapter vocabulary")
check(Supervisor.containsDeferredStatus("vehicle_transaction_rejected:retry_exhausted") == false,
    "wrapping does not make a refusal look like a deferral")

-- ---------------------------------------------------------------------------
-- 2. Bounded force-release out of rollback quarantine
-- ---------------------------------------------------------------------------
do
    local actor = testActor("supervisor-quarantine")
    local cancelCalls = 0
    local token = assert(Supervisor.begin(actor, {
        owner = "work", action = "saw_logs", targetKey = "log:1",
        ignoreRetry = true, interruptible = true,
        -- An owner whose rollback hook fails hard every time and whose
        -- postcondition can never be verified: the exact shape that used to
        -- strand the actor for the rest of the session. A verifier must be
        -- present, because that is what makes the supervisor retain (rather
        -- than abandon) the rollback obligation.
        onCancel = function()
            cancelCalls = cancelCalls + 1
            error("injected rollback failure")
        end,
        cancelVerified = function() return false, "never_verified" end,
    }))
    local resource = {}
    check(Supervisor.reserve(token, resource, "saw") == true,
        "the quarantine fixture owner holds a reservation")

    -- Drive the rollback obligation to exhaustion.
    Supervisor.cancel(actor, "quarantine_fixture", nil, true)
    for _ = 1, rollbackAttempts + 2 do
        SC_TEST_CLOCK = SC_TEST_CLOCK + rollbackRetryMs + 1
        Supervisor.update(actor)
    end
    local quarantined = Supervisor.health()
    check(quarantined.rollbackQuarantined == 1 and cancelCalls >= 1,
        "an unverifiable rollback reaches supervisor quarantine and is counted")
    check(Supervisor.current(actor) == token,
        "the quarantined owner still holds the actor before the grace window ends")

    local snapshotDuring = Supervisor.quarantineSnapshot()
    check(#snapshotDuring.owners == 1
            and snapshotDuring.owners[1].action == "saw_logs"
            and (tonumber(snapshotDuring.owners[1].attempts) or 0) >= rollbackAttempts,
        "Support can name the owner sitting in supervisor quarantine")

    -- A native action still in progress must keep the release fail-closed:
    -- releasing supervisor ownership over a live vanilla action would let a
    -- second owner stack on top of it.
    local nativeBusy = true
    local realStatus = SC.NativeActions and SC.NativeActions.activityStatus or nil
    if SC.NativeActions then
        SC.NativeActions.activityStatus = function()
            if nativeBusy then return "animating", "native", "sit", SC_TEST_CLOCK end
            return "none"
        end
    end
    SC_TEST_CLOCK = SC_TEST_CLOCK + quarantineMs + 1
    local heldOk, heldReason = Supervisor.update(actor)
    check(heldOk == false and heldReason == "rollback_quarantined_native_busy"
            and Supervisor.current(actor) == token,
        "force-release fails closed while a native action still owns the body")

    nativeBusy = false
    SC_TEST_CLOCK = SC_TEST_CLOCK + 1
    local released = Supervisor.update(actor)
    if SC.NativeActions then SC.NativeActions.activityStatus = realStatus end

    check(released == true and Supervisor.current(actor) == nil,
        "an exhausted rollback is force-released once the native layer is idle")
    check(Supervisor.reservationCount(actor) == 0
            and Supervisor.leakedReservations() == 0,
        "force-release returns the quarantined owner reservations")

    local after = Supervisor.health()
    check(after.rollbackQuarantined == 0 and after.forceReleases == 1,
        "health reports the quarantine cleared and the force-release recorded")

    local snapshotAfter = Supervisor.quarantineSnapshot()
    local sawForceRelease = false
    for _, entry in ipairs(snapshotAfter.events) do
        if entry.event == "rollback_force_released" then sawForceRelease = true end
    end
    check(#snapshotAfter.owners == 0 and sawForceRelease,
        "Support reports the force-release exactly once, not a standing quarantine")

    -- The actor must be usable again, and the failed owner must have taken a
    -- retry penalty rather than being free to re-quarantine immediately.
    local reuse = assert(Supervisor.begin(actor, {
        owner = "downtime", action = "read", ignoreRetry = true,
    }))
    check(Supervisor.isCurrent(reuse), "a force-released actor accepts new work")
    check(Supervisor.complete(reuse, "done") == true,
        "the replacement owner completes normally")
    local penalised = Supervisor.begin(actor, {
        owner = "work", action = "saw_logs", targetKey = "log:1",
    })
    check(penalised == nil,
        "the owner that had to be force-released backs off instead of retrying immediately")
end

-- Normal verified cancellation must still complete with no force-release.
do
    Supervisor.reset(nil, "recovery_normal_cancel")
    local actor = testActor("supervisor-normal-cancel")
    local rolledBack = false
    local token = assert(Supervisor.begin(actor, {
        owner = "work", action = "chop", ignoreRetry = true, interruptible = true,
        onCancel = function() rolledBack = true return true end,
        cancelVerified = function() return rolledBack end,
    }))
    Supervisor.reserve(token, {}, "axe")
    check(Supervisor.cancel(actor, "normal_cancel", nil, true) == true
            and Supervisor.current(actor) == nil
            and Supervisor.leakedReservations() == 0,
        "a verified cancel still completes directly")
    local health = Supervisor.health()
    check(health.forceReleases == 0 and health.rollbackQuarantined == 0,
        "a healthy cancel never reports a force-release")
end

-- ---------------------------------------------------------------------------
-- 3. Leak evidence is nameable, and tracked actors are enumerable
-- ---------------------------------------------------------------------------
do
    Supervisor.reset(nil, "recovery_leak_detail")
    local actor = testActor("supervisor-leak-detail")
    local token = assert(Supervisor.begin(actor, {
        owner = "logistics", action = "loot_container", targetKey = "crate:1",
        targetLabel = "crate", ignoreRetry = true,
    }))
    Supervisor.reserve(token, "crate:1", "source_container")
    check(Supervisor.leakedReservations() == 0,
        "a live owner reservation is not a leak")

    local tracked = Supervisor.trackedActors()
    local found = false
    for _, value in ipairs(tracked) do if value == actor then found = true end end
    check(found, "trackedActors enumerates actors the supervisor still holds state for")

    check(Supervisor.releaseActor(actor, "retired") == true
            and Supervisor.actorStateCount(actor) == 0
            and Supervisor.leakedReservations() == 0
            and #Supervisor.leakedReservationDetails() == 0,
        "explicit release clears every map for a retired actor")
end

print("SUPERVISOR_RECOVERY_PASS assertions=" .. tostring(assertions))
