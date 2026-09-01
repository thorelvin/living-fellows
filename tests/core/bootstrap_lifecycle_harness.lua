-- SPDX-License-Identifier: MIT

local checks = 0
local function check(value, message)
    checks = checks + 1
    assert(value, "check " .. tostring(checks) .. " failed: " .. tostring(message))
end

local SC = SurvivorCompanion
check(SC.Bootstrap.isInstalled() and Events.OnGameStart.count() == 1
        and Events.OnSave.count() == 1 and Events.OnMainMenuEnter.count() == 1,
    "bootstrap atomically owns one copy of each lifecycle hook")
check(SC.Factions.installs == 1 and SC.FactionContracts.installs == 1
        and SC.CompanionMap.installs == 1,
    "bootstrap owns the long-lived faction and minimap hooks")

Events.OnGameStart.fire()
Events.OnGameStart.fire()
check(SC.Runtime.starts == 2 and SC.Factions.installs == 1
        and SC.FactionContracts.installs == 1 and SC.CompanionMap.installs == 1,
    "world starts do not duplicate long-lived hooks")

local removed, removeReason = SC.Bootstrap.remove()
check(removed and removeReason == "" and Events.OnGameStart.count() == 0
        and Events.OnSave.count() == 0 and Events.OnMainMenuEnter.count() == 0
        and not SC.Factions.installed and not SC.FactionContracts.installed
        and not SC.CompanionMap.installed,
    "bootstrap removal releases every lifecycle and contract hook")

Events.OnSave.failAdd = true
local installed, reason = SC.Bootstrap.install()
check(not installed and string.find(tostring(reason), "OnSave hook failed", 1, true)
        and not SC.Bootstrap.isInstalled() and Events.OnGameStart.count() == 0
        and Events.OnSave.count() == 0 and not SC.Factions.installed
        and not SC.FactionContracts.installed and not SC.CompanionMap.installed,
    "partial lifecycle installation rolls back every acquired hook")

Events.OnSave.failAdd = false
check(SC.Bootstrap.install() and SC.Bootstrap.remove(),
    "bootstrap can install cleanly after a rolled-back failure")

-- A rollback failure must never reuse the fully-installed fast path. The
-- partial faction hook remains explicitly cleanup-pending until its remover
-- succeeds, and repeated install calls stay failed without adding callbacks.
Events.OnSave.failAdd = true
SC.Factions.failRemove = true
installed, reason = SC.Bootstrap.install()
check(not installed and SC.Bootstrap.cleanupPending()
        and not SC.Bootstrap.isInstalled() and SC.Factions.installed
        and Events.OnGameStart.count() == 0 and Events.OnSave.count() == 0,
    "failed install rollback is observable without claiming full installation")
local repeated, repeatedReason = SC.Bootstrap.install()
check(not repeated and string.find(tostring(repeatedReason),
        "prior partial bootstrap install", 1, true) ~= nil
        and not SC.Bootstrap.isInstalled() and Events.OnGameStart.count() == 0,
    "repeated install cannot bypass unresolved partial-hook cleanup")
SC.Factions.failRemove = false
Events.OnSave.failAdd = false
check(SC.Bootstrap.install() and SC.Bootstrap.isInstalled()
        and not SC.Bootstrap.cleanupPending() and SC.Bootstrap.remove(),
    "bootstrap cleans a prior partial install before acquiring a complete set")

local function allOwned()
    return SC.Bootstrap.isInstalled()
        and Events.OnGameStart.count() == 1 and Events.OnSave.count() == 1
        and Events.OnMainMenuEnter.count() == 1
        and SC.Factions.installed and SC.FactionContracts.installed
        and SC.CompanionMap.installed
end

check(SC.Bootstrap.install(), "bootstrap installs for removal failure matrix")
SC.Runtime.worldSentinel = { value = "runtime-reset-boundary" }
local liveSentinel = SC.Runtime.worldSentinel
SC.Runtime.failReset = true
removed, removeReason = SC.Bootstrap.remove()
check(not removed and string.find(tostring(removeReason), "runtime reset failed", 1, true)
        and allOwned() and SC.Runtime.worldSentinel == liveSentinel,
    "failed runtime reset retains every bootstrap-owned callback and contract")
SC.Runtime.failReset = false
check(SC.Bootstrap.remove(), "bootstrap removal retries after runtime reset failure")

for _, entry in ipairs({
    { name = "OnMainMenuEnter", event = Events.OnMainMenuEnter },
    { name = "OnSave", event = Events.OnSave },
    { name = "OnGameStart", event = Events.OnGameStart },
}) do
    check(SC.Bootstrap.install(), entry.name .. " removal fixture installs")
    SC.Runtime.worldSentinel = { value = entry.name }
    local sentinel = SC.Runtime.worldSentinel
    local resetsBeforeFailure = SC.Runtime.resets
    entry.event.failRemove = true
    removed, removeReason = SC.Bootstrap.remove()
    check(not removed
            and string.find(tostring(removeReason), entry.name, 1, true) ~= nil
            and allOwned() and SC.Runtime.resets == resetsBeforeFailure
            and SC.Runtime.worldSentinel == sentinel,
        entry.name .. " removal failure rolls lifecycle ownership back exactly")
    entry.event.failRemove = false
    check(SC.Bootstrap.remove(), entry.name .. " removal retry releases all ownership")
end

for _, entry in ipairs({
    { name = "faction combat", owner = SC.Factions },
    { name = "faction contracts", owner = SC.FactionContracts },
    { name = "companion minimap", owner = SC.CompanionMap },
}) do
    check(SC.Bootstrap.install(), entry.name .. " removal fixture installs")
    SC.Runtime.worldSentinel = { value = entry.name }
    local sentinel = SC.Runtime.worldSentinel
    local resetsBeforeFailure = SC.Runtime.resets
    entry.owner.failRemove = true
    removed, removeReason = SC.Bootstrap.remove()
    check(not removed
            and string.find(tostring(removeReason), entry.name, 1, true) ~= nil
            and allOwned() and SC.Runtime.resets == resetsBeforeFailure
            and SC.Runtime.worldSentinel == sentinel,
        entry.name .. " removal failure restores lifecycle and contract ownership")
    entry.owner.failRemove = false
    check(SC.Bootstrap.remove(), entry.name .. " removal retry releases all ownership")
end

print("BOOTSTRAP_LIFECYCLE_KAHLUA_PASS checks=" .. tostring(checks))
