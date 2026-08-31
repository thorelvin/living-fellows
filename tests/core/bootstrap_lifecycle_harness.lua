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

print("BOOTSTRAP_LIFECYCLE_KAHLUA_PASS checks=" .. tostring(checks))
