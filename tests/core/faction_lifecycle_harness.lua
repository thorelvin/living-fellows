-- SPDX-License-Identifier: MIT

local checks = 0
local function check(value, message)
    checks = checks + 1
    assert(value, "check " .. tostring(checks) .. " failed: " .. tostring(message))
end

local SC = SurvivorCompanion
local encounterContract = SC.Encounter.onPlayerContainerOpened
local uiRefreshContract = SC.UI.scheduledRefresh
local limits = {
    "factionContractHistoryLimit",
    "factionContractMemoryLimit",
    "factionContractPromiseLimit",
    "factionNotificationLimit",
    "factionNotificationFlagLimit",
}

local function noOwnedHooks()
    return (Events.OnWeaponHitCharacter == nil or Events.OnWeaponHitCharacter.count() == 0)
        and (Events.OnZombieDead == nil or Events.OnZombieDead.count() == 0)
        and not SC.Factions.hooksInstalled()
        and not SC.FactionContracts.hooksInstalled()
        and SC.CompanionMap.installed == false
end

local function testGroup()
    return {
        id = "fixture-household", lifecycle = "destroyed", members = {},
        house = { anchor = { x = 10, y = 10, z = 0 } },
        social = {
            schema = 2,
            access = { state = "threshold" },
            contract = {
                sequence = 1, offer = nil, history = {}, cooldownUntilHour = 0,
                active = {
                    id = "fixture-local-threat", kind = "local_threat",
                    status = "active", target = { x = 10, y = 10, z = 0 },
                    radius = 18, requiredKills = 10,
                    progress = { kills = 0, visited = true },
                },
            },
            memories = {}, promises = {}, dialogue = {}, trade = {},
            notifications = {}, notificationFlags = {}, notificationFlagOrder = {},
        },
    }
end

check(SC.Bootstrap.isInstalled()
        and Events.OnGameStart.count() == 1 and Events.OnSave.count() == 1
        and Events.OnMainMenuEnter.count() == 1
        and Events.OnWeaponHitCharacter.count() == 1
        and Events.OnZombieDead.count() == 1,
    "production modules bootstrap with exactly one copy of every owned hook")
check(SC.Factions.hooksInstalled() and SC.FactionContracts.hooksInstalled(),
    "production faction modules expose their installed hook state")

Events.OnGameStart.fire()
check(SC.Runtime.isTickAttached() and SC.Runtime.tasksRegistered()
        and Events.OnTick.count() == 1 and Events.OnZombieDead.count() == 1,
    "OnGameStart starts the real runtime without removing the contract hook")

local group = testGroup()
SC.Factions.list = function() return { group } end
local zombie = {
    getAttackedBy = function() return SC_TEST_PLAYER end,
}
Events.OnZombieDead.fire(zombie)
check(group.social.contract.active.progress.kills == 1
        and #group.social.memories == 1,
    "one matching zombie-death event produces exactly one local-threat increment")

local disposeBeforeSecondStart = SC_TEST_COUNTS.actorDispose
local ready, reason, operational = SC.Runtime.start()
check(ready == true and reason == "ready" and operational == true
        and SC_TEST_COUNTS.actorDispose == disposeBeforeSecondStart
        and Events.OnTick.count() == 1 and Events.OnZombieDead.count() == 1,
    "a second real Runtime.start is idempotent and preserves one callback")
Events.OnZombieDead.fire(zombie)
check(group.social.contract.active.progress.kills == 2
        and #group.social.memories == 2,
    "the callback still advances progress by exactly one after repeated start")

local removed, removeReason = SC.Bootstrap.remove()
check(removed and removeReason == "" and noOwnedHooks()
        and Events.OnGameStart.count() == 0 and Events.OnSave.count() == 0
        and Events.OnMainMenuEnter.count() == 0 and Events.OnTick.count() == 0,
    "bootstrap.remove releases lifecycle, tick, faction, contract, and map ownership")

check(SC.Bootstrap.install(), "bootstrap reinstalls after complete removal")
Events.OnGameStart.fire()
check(Events.OnZombieDead.count() == 1 and Events.OnWeaponHitCharacter.count() == 1
        and Events.OnTick.count() == 1,
    "a subsequent bootstrap and game start restore exactly one callback")
check(SC.Bootstrap.remove() and noOwnedHooks(),
    "second bootstrap removal returns every long-lived hook to zero")

local hitEvent = Events.OnWeaponHitCharacter
Events.OnWeaponHitCharacter = nil
local installed, installReason = SC.Factions.installHooks()
check(installed == false
        and string.find(tostring(installReason), "unavailable", 1, true) ~= nil
        and SC.Factions.hooksInstalled() == false,
    "faction hook installation reports a missing event and remains uninstalled")
Events.OnWeaponHitCharacter = hitEvent
check(SC.Factions.installHooks() and SC.Factions.hooksInstalled()
        and hitEvent.count() == 1 and SC.Factions.installHooks() and hitEvent.count() == 1,
    "faction hook installation is truthful, queryable, and idempotent")
local hitRemove = hitEvent.Remove
hitEvent.Remove = nil
local hitRemoved, hitRemoveReason = SC.Factions.removeHooks()
check(hitRemoved == false
        and string.find(tostring(hitRemoveReason), "unavailable", 1, true) ~= nil
        and SC.Factions.hooksInstalled() and hitEvent.count() == 1,
    "failed faction hook removal preserves ownership state")
hitEvent.Remove = hitRemove
check(SC.Factions.removeHooks() and not SC.Factions.hooksInstalled()
        and hitEvent.count() == 0 and SC.Factions.removeHooks(),
    "faction hook removal clears its callback and is idempotent")

local zombieEvent = Events.OnZombieDead
Events.OnZombieDead = nil
installed, installReason = SC.FactionContracts.installHooks()
check(installed == false
        and string.find(tostring(installReason), "unavailable", 1, true) ~= nil
        and SC.FactionContracts.hooksInstalled() == false,
    "contract hook installation reports a missing event and remains uninstalled")
Events.OnZombieDead = zombieEvent
check(SC.FactionContracts.installHooks() and SC.FactionContracts.hooksInstalled()
        and zombieEvent.count() == 1
        and SC.FactionContracts.installHooks() and zombieEvent.count() == 1,
    "contract hook installation is truthful, queryable, and idempotent")
local zombieRemove = zombieEvent.Remove
zombieEvent.Remove = nil
local zombieRemoved, zombieRemoveReason = SC.FactionContracts.removeHooks()
check(zombieRemoved == false
        and string.find(tostring(zombieRemoveReason), "unavailable", 1, true) ~= nil
        and SC.FactionContracts.hooksInstalled() and zombieEvent.count() == 1,
    "failed contract hook removal preserves ownership state")
zombieEvent.Remove = zombieRemove
check(SC.FactionContracts.removeHooks() and not SC.FactionContracts.hooksInstalled()
        and zombieEvent.count() == 0 and SC.FactionContracts.removeHooks(),
    "contract hook removal clears its callback and is idempotent")

for _, key in ipairs(limits) do
    SC.Config.testSet(key, 1)
    check(SC.FactionContracts.validateConfiguration() == true,
        key .. " accepts the configured minimum")
    SC.Config.testSet(key, 4096)
    check(SC.FactionContracts.validateConfiguration() == true,
        key .. " accepts the configured maximum")
    for _, invalid in ipairs({ 0, 4097, 1.5, math.huge, -math.huge }) do
        SC.Config.testSet(key, invalid)
        local valid, validationReason = SC.FactionContracts.validateConfiguration()
        check(valid == false
                and string.find(tostring(validationReason), key, 1, true) ~= nil,
            key .. " rejects an invalid configured boundary")
    end
    SC.Config.testSet(key, 2)
end

local boundaryGroup = testGroup()
boundaryGroup.social.contract.active = nil
local arrayCases = {
    { key = "factionContractHistoryLimit", list = boundaryGroup.social.contract.history },
    { key = "factionContractMemoryLimit", list = boundaryGroup.social.memories },
    { key = "factionContractPromiseLimit", list = boundaryGroup.social.promises },
    { key = "factionNotificationLimit", list = boundaryGroup.social.notifications },
    { key = "factionNotificationFlagLimit", list = boundaryGroup.social.notificationFlagOrder },
}
for _, spec in ipairs(arrayCases) do
    for _, row in ipairs(arrayCases) do
        while #row.list > 0 do table.remove(row.list) end
    end
    spec.list[1], spec.list[2] = {}, {}
    check(SC.FactionContracts.validate(boundaryGroup) == true,
        spec.key .. " validation accepts exactly the configured limit")
    spec.list[3] = {}
    check(SC.FactionContracts.validate(boundaryGroup) == false,
        spec.key .. " validation rejects one entry over the configured limit")
end

for _, key in ipairs(limits) do SC.Config.testSet(key, 2) end
SC.Config.testSet("factionContractMemoryLimit", 0)
installed, installReason = SC.FactionContracts.installHooks()
check(installed == false
        and string.find(tostring(installReason), "factionContractMemoryLimit", 1, true) ~= nil
        and zombieEvent.count() == 0 and not SC.FactionContracts.hooksInstalled(),
    "contract hook startup validates configured limits before acquiring the event")
SC.Config.testSet("factionContractMemoryLimit", 2)

local saveEvent = Events.OnSave
Events.OnSave = nil
installed, installReason = SC.Bootstrap.install()
check(installed == false
        and string.find(tostring(installReason), "lifecycle events", 1, true) ~= nil
        and noOwnedHooks(),
    "missing lifecycle events leave every long-lived hook unowned")
Events.OnSave = saveEvent

local missingZombieEvent = Events.OnZombieDead
Events.OnZombieDead = nil
installed, installReason = SC.Bootstrap.install()
check(installed == false
        and string.find(tostring(installReason), "OnZombieDead", 1, true) ~= nil
        and noOwnedHooks()
        and SC.Encounter.onPlayerContainerOpened == encounterContract
        and SC.UI.scheduledRefresh == uiRefreshContract,
    "a missing contract event rolls back the previously acquired faction hook")
Events.OnZombieDead = missingZombieEvent

SC.Config.testSet("factionContractMemoryLimit", 0)
installed, installReason = SC.Bootstrap.install()
check(installed == false
        and string.find(tostring(installReason), "factionContractMemoryLimit", 1, true) ~= nil
        and noOwnedHooks()
        and SC.Encounter.onPlayerContainerOpened == encounterContract
        and SC.UI.scheduledRefresh == uiRefreshContract,
    "invalid contract limits abort bootstrap and roll back the faction hook")
SC.Config.testSet("factionContractMemoryLimit", 2)

Events.OnZombieDead.failAdd = true
installed, installReason = SC.Bootstrap.install()
check(installed == false
        and string.find(tostring(installReason), "faction contracts", 1, true) ~= nil
        and noOwnedHooks()
        and SC.Encounter.onPlayerContainerOpened == encounterContract
        and SC.UI.scheduledRefresh == uiRefreshContract,
    "failed contract installation rolls back hooks without mutating module contracts")
Events.OnZombieDead.failAdd = false

Events.OnSave.failAdd = true
installed, installReason = SC.Bootstrap.install()
check(installed == false
        and string.find(tostring(installReason), "OnSave hook failed", 1, true) ~= nil
        and noOwnedHooks() and Events.OnGameStart.count() == 0
        and SC.Encounter.onPlayerContainerOpened == encounterContract
        and SC.UI.scheduledRefresh == uiRefreshContract,
    "partial lifecycle Add failure rolls back every acquired production hook")
Events.OnSave.failAdd = false

SC.CompanionMap.failInstall = true
installed, installReason = SC.Bootstrap.install()
check(installed == false
        and string.find(tostring(installReason), "companion minimap", 1, true) ~= nil
        and noOwnedHooks()
        and SC.Encounter.onPlayerContainerOpened == encounterContract
        and SC.UI.scheduledRefresh == uiRefreshContract,
    "failed final contract installation rolls back earlier hooks and preserves contracts")
SC.CompanionMap.failInstall = false

check(SC.Bootstrap.install() and SC.Bootstrap.remove() and noOwnedHooks(),
    "bootstrap remains reinstallable after every injected lifecycle failure")

print("FACTION_LIFECYCLE_KAHLUA_PASS checks=" .. tostring(checks))
