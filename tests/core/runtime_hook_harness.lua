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
SC.Runtime.start()
check(SC.FactionContracts.removeCalls == 0 and SC.FactionContracts.resetCalls == 2,
    "per-world runtime reset clears contract state without removing bootstrap-owned hooks")
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
SC.Runtime.reset(true)
state = SC.Runtime.containerHookState()
check(SC.Actor.disposeCalls == disposalsBeforeReset + 1,
    "world reset disposes native actors before clearing Lua ownership")
check(ISInventoryPage.selectContainer == newerSelect and state.selectDeferred,
    "reset never clobbers a wrapper installed later by another mod")
check(ISInventoryPage.setNewContainer == originalSetNew and not state.setNewInstalled
    and not state.setNewDeferred,
    "runtime restores a method only while it still owns that method")

ISInventoryPage.selectContainer = ownSelect
disposalsBeforeReset = SC.Actor.disposeCalls
SC.Runtime.reset(true)
state = SC.Runtime.containerHookState()
check(SC.Actor.disposeCalls == disposalsBeforeReset + 1,
    "every world reset repeats native teardown without relying on stale Lua state")
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
