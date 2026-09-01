-- SPDX-License-Identifier: MIT

local checks = 0
local function check(value, message)
    checks = checks + 1
    assert(value, "check " .. tostring(checks) .. " failed: " .. tostring(message))
end

local SC = SurvivorCompanion
local originalSelect = ISInventoryPage.selectContainer
local originalSetNew = ISInventoryPage.setNewContainer

SC.Runtime.start()
local disposalsAfterFirstStart = SC.Actor.disposeCalls
local generationAfterFirstStart = SC.State.generation
SC.Runtime.start()
check(SC.Actor.disposeCalls == disposalsAfterFirstStart
        and SC.Persistence.restoreCalls == 1
        and SC.State.generation == generationAfterFirstStart
        and SC.FactionContracts.removeCalls == 0
        and SC.FactionContracts.resetCalls == 0,
    "repeated same-world start preserves actors and performs no second initialization")
check(SC.Runtime.reset(true) == true,
    "explicit world boundary resets an idempotently started runtime")
SC_TEST_CLOCK = 32001
isClient = function() return true end
SC.Runtime.start()
isClient = function() return false end
local ownSelect = ISInventoryPage.selectContainer
local ownSetNew = ISInventoryPage.setNewContainer
local state = SC.Runtime.containerHookState()
check(state.selectInstalled and state.setNewInstalled,
    "runtime owns both inventory-page wrappers after start")
local fixturePlayer = getPlayer()
check(fixturePlayer.haloNotes == 2
    and string.find(fixturePlayer.haloMessages[1], "TRANSLATED PROVIDER NOTICE", 1, true) ~= nil
    and fixturePlayer.haloMessages[2] == "TRANSLATED MULTIPLAYER NOTICE",
    "provider and multiplayer failures emit translated rate-limited in-game notices")

local page = { onCharacter = false, inventoryPane = {} }
local container = {}
check(ownSelect(page, { inventory = container }) == "selected" and SC.Encounter.opened == 1,
    "select wrapper preserves the original result and emits the narrow signal")
check(ownSetNew(page, container) == "changed" and SC.Encounter.opened == 2,
    "set-new wrapper preserves the original result and emits the narrow signal")

local newerSelect = function(self, button)
    self.newerWrapperCalled = true
    return ownSelect(self, button)
end
ISInventoryPage.selectContainer = newerSelect
local disposalsBeforeReset = SC.Actor.disposeCalls
local blockedReset, blockedReason = SC.Runtime.reset(true)
state = SC.Runtime.containerHookState()
check(blockedReset == false
        and string.find(tostring(blockedReason), "wrapper chain changed", 1, true) ~= nil
        and SC.Actor.disposeCalls == disposalsBeforeReset,
    "foreign wrapper ownership blocks teardown before native or Lua state changes")
check(ISInventoryPage.selectContainer == newerSelect and state.selectDeferred,
    "reset never clobbers a wrapper installed later by another mod")
check(ISInventoryPage.setNewContainer == ownSetNew and state.setNewInstalled,
    "teardown preflight leaves every owned wrapper installed on chain conflict")

ISInventoryPage.selectContainer = ownSelect
disposalsBeforeReset = SC.Actor.disposeCalls
SC.Runtime.reset(true)
state = SC.Runtime.containerHookState()
check(SC.Actor.disposeCalls == disposalsBeforeReset + 1,
    "cleanup retry disposes native actors after wrapper ownership is restored")
check(ISInventoryPage.selectContainer == originalSelect and not state.selectInstalled
    and not state.selectDeferred,
    "deferred removal completes after the newer owner releases the method chain")

SC.Runtime.start()
local generationBeforeFailure = SC.State.generation
local registryResetsBeforeFailure = SC.Registry.resetCalls
local actorResetsBeforeFailure = SC.Actor.resetCalls
local persistenceResetsBeforeFailure = SC.Persistence.resetCalls
SC.Actor.disposeResult = false
local failedReset, failedReason = SC.Runtime.reset(true)
check(failedReset == false
    and string.find(tostring(failedReason), "injected native cleanup failure", 1, true) ~= nil,
    "unverified native teardown fails the reset transaction")
check(SC.State.generation == generationBeforeFailure
    and SC.Registry.resetCalls == registryResetsBeforeFailure
    and SC.Actor.resetCalls == actorResetsBeforeFailure
    and SC.Persistence.resetCalls == persistenceResetsBeforeFailure,
    "failed native teardown preserves registry, actor, persistence, and generation state")
check(SC.State.active == false
    and string.find(tostring(SC.State.disabledReason), "native companion teardown", 1, true) ~= nil,
    "failed native teardown disables runtime with an actionable reason")
SC.Actor.disposeResult = true
check(SC.Runtime.reset(true) == true
    and SC.Registry.resetCalls == registryResetsBeforeFailure + 1
    and SC.Actor.resetCalls == actorResetsBeforeFailure + 1,
    "verified cleanup retry allows the reset transaction to commit")

print("RUNTIME_HOOK_KAHLUA_PASS checks=" .. tostring(checks))
