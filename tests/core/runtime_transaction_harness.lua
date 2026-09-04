-- SPDX-License-Identifier: MIT

local checks = 0
local function check(value, message)
    checks = checks + 1
    assert(value, "check " .. tostring(checks) .. " failed: " .. tostring(message))
end

local SC = SurvivorCompanion
local fixture = SC_RUNTIME_FIXTURE
local prior = {
    schema = 999,
    companions = { alpha = { id = "alpha", sentinel = "must-survive" } },
    nested = { one = { two = "exact" } },
}
fixture.setDocument(prior)

local function assertBlockedStart(label, configure, restoreConfigure)
    if configure then configure() end
    if restoreConfigure then restoreConfigure() end
    local saveCalls = SC.Persistence.saveCalls
    local resets = SC.Persistence.resetCalls
    local ready, reason, operational = SC.Runtime.start()
    check(ready == false and operational == false and reason ~= nil,
        label .. " is a fatal, checked startup failure")
    local saved, saveReason = SC.Runtime.save()
    check(saved == false
            and string.find(tostring(saveReason), "blocked", 1, true) ~= nil
            and SC.Persistence.saveCalls == saveCalls,
        label .. " keeps OnSave fail-closed before restore commit")
    check(fixture.document() == prior
            and fixture.document().companions.alpha.sentinel == "must-survive"
            and SC.Persistence.resetCalls == resets,
        label .. " preserves the exact nonempty prior save document")
end

fixture.bridgeThrows = true
assertBlockedStart("bridge exception")
fixture.bridgeThrows = false

fixture.rejectTask = "vitals"
assertBlockedStart("scheduler rejection")
fixture.rejectTask = nil

local inventoryPage = ISInventoryPage
ISInventoryPage = nil
assertBlockedStart("container-hook installation failure")
ISInventoryPage = inventoryPage

fixture.failTickAdd = true
assertBlockedStart("tick attachment failure")
fixture.failTickAdd = false
check(fixture.tickCount() == 0 and not SC.Runtime.isTickAttached()
        and not SC.Runtime.tasksRegistered(),
    "failed startup phases leave no partial tick or scheduler ownership")

fixture.restoreResult = false
fixture.restoreReason = "unsupported schema fixture"
local restoreCalls = SC.Persistence.restoreCalls
assertBlockedStart("restore rejection")
check(SC.Persistence.restoreCalls == restoreCalls + 1,
    "restore rejection was reached only after infrastructure preflight")
assertBlockedStart("repeated restore rejection")
check(SC.Persistence.restoreCalls == restoreCalls + 2 and fixture.document() == prior,
    "repeated startup cannot clear the blocked persistence document")

fixture.restoreResult = true
fixture.restoreReason = nil
local ready, reason, operational = SC.Runtime.start()
check(ready == false and operational == true
        and reason == "fixture has no actor provider",
    "provider unavailability remains operational after restore commits")
check(SC.Runtime.isTickAttached() and SC.Runtime.tasksRegistered()
        and fixture.tickCount() == 1,
    "successful startup publishes exactly one tick and task set")

local disposals = SC.Actor.disposeCalls
local registryResets = SC.Registry.resetCalls
local persistenceResets = SC.Persistence.resetCalls
fixture.failTickRemove = true
local reset, resetReason = SC.Runtime.reset(true)
check(reset == false
        and SC.Actor.disposeCalls == disposals
        and SC.Registry.resetCalls == registryResets
        and SC.Persistence.resetCalls == persistenceResets,
    "tick-removal failure stops teardown before native and Lua ownership changes")
check(SC.Runtime.isTickAttached() and fixture.tickCount() == 1,
    "failed tick teardown retains the live callback for a checked retry")
fixture.failTickRemove = false

fixture.prepareResult = false
fixture.prepareReason = "injected pending-ticket refusal"
reset, resetReason = SC.Runtime.reset(true)
check(reset == false
        and string.find(tostring(resetReason), "pending-ticket refusal", 1, true) ~= nil
        and SC.Actor.disposeCalls == disposals
        and SC.Registry.resetCalls == registryResets
        and SC.Persistence.resetCalls == persistenceResets,
    "persistence cancellation refusal retains actor, registry, and persistence references")
check(SC.Runtime.isTickAttached() and fixture.tickCount() == 1,
    "persistence preflight failure transactionally restores runtime infrastructure")

fixture.prepareResult = true
fixture.prepareReason = nil
check(SC.Runtime.reset(true) == true
        and SC.Actor.disposeCalls == disposals + 1
        and SC.Registry.resetCalls == registryResets + 1
        and SC.Persistence.resetCalls == persistenceResets + 1,
    "teardown retry commits only after every preflight succeeds")

-- A gameplay subsystem may reject reset while it still owns an action token.
-- Continue resetting independent gameplay peers, but preserve the actor,
-- registry, and diagnostics ledgers and report a checked retryable failure.
ready, reason, operational = SC.Runtime.start()
check(operational == true, "runtime restarts for subsystem-reset rejection fixture")
local factionResets = SC.Factions.resetCalls
local communityResets = SC.Community.resetCalls
local actorResets = SC.Actor.resetCalls
registryResets = SC.Registry.resetCalls
local diagnosticResets = SC.Diagnostics.resetCalls
local diagnosticReports = SC.Diagnostics.reportCalls
SC.Decision.resetMode = "false"
reset, resetReason = SC.Runtime.reset(true)
check(reset == false
        and string.find(tostring(resetReason), "decision reset rejection", 1, true) ~= nil
        and SC.Factions.resetCalls == factionResets + 1
        and SC.Community.resetCalls == communityResets + 1,
    "false subsystem reset is reported after best-effort peer cleanup")
check(SC.Actor.resetCalls == actorResets
        and SC.Registry.resetCalls == registryResets
        and SC.Diagnostics.resetCalls == diagnosticResets
        and SC.Diagnostics.reportCalls > diagnosticReports,
    "subsystem rejection preserves ownership and diagnostic evidence")
SC.Decision.resetMode = "success"
check(SC.Runtime.reset(true) == true,
    "subsystem-reset rejection remains retryable")

ready, reason, operational = SC.Runtime.start()
check(operational == true, "runtime restarts for subsystem-reset exception fixture")
actorResets = SC.Actor.resetCalls
registryResets = SC.Registry.resetCalls
diagnosticResets = SC.Diagnostics.resetCalls
SC.Decision.resetMode = "throw"
local menuReset, menuReason = SC.Runtime.onMainMenuEnter()
check(menuReset == false
        and tostring(menuReason) ~= ""
        and string.find(tostring(menuReason),
            "runtime subsystem reset was incomplete", 1, true) ~= nil
        and string.find(tostring(menuReason), "decision:", 1, true) ~= nil
        and SC.Actor.resetCalls == actorResets
        and SC.Registry.resetCalls == registryResets
        and SC.Diagnostics.resetCalls == diagnosticResets,
    "main-menu teardown propagates a subsystem reset exception without erasing evidence")
SC.Decision.resetMode = "success"
check(SC.Runtime.reset(true) == true,
    "exceptional subsystem teardown remains retryable")

do
    -- A transient native-health dip must be tolerated for a bounded window so a
    -- teleport-recovered companion is not despawned before its native state settles
    -- (playtest: "teleported to me, then a health-check despawned her, body never
    -- came back"). Only a persistent failure past the grace window removes the actor.
    local decide = SC.Runtime._healthGateDecisionForTests
    check(type(decide) == "function", "runtime exposes the health-gate decision seam")
    local runtimeState = {}
    check(decide(runtimeState, 1000, 1500) == "defer"
            and runtimeState.healthFailingSince == 1000,
        "first native-health failure is deferred, not an immediate removal")
    check(decide(runtimeState, 2000, 1500) == "defer"
            and runtimeState.healthFailingSince == 1000,
        "a native-health failure within the grace window keeps deferring")
    check(decide(runtimeState, 2600, 1500) == "remove"
            and runtimeState.healthFailingSince == nil,
        "a native-health failure that persists past the grace window removes the actor")
    local recovering = { healthFailingSince = 500 }
    recovering.healthFailingSince = nil
    check(decide(recovering, 3000, 1500) == "defer"
            and recovering.healthFailingSince == 3000,
        "a cleared failure marker restarts the tolerance window on the next dip")
end

print("RUNTIME_TRANSACTION_KAHLUA_PASS checks=" .. tostring(checks))
