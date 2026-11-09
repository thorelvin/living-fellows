-- SPDX-License-Identifier: MIT

local checks = 0
local function check(value, message)
    checks = checks + 1
    assert(value, "check " .. tostring(checks) .. " failed: " .. tostring(message))
end

local SC = SurvivorCompanion
check(SC.Bootstrap.isInstalled() and Events.OnInitGlobalModData.count() == 1
        and Events.OnGameStart.count() == 1
        and Events.OnSave.count() == 1 and Events.OnMainMenuEnter.count() == 1,
    "bootstrap atomically owns one copy of each lifecycle hook: "
        .. tostring(SC.State.disabledReason))
check(Events.LoadGridsquare.count()==1 and Events.OnObjectAdded.count()==1,
    "mounted radio load/place hooks are owned by the bootstrap transaction")
-- OnPlayerGetDamage has two owners: the terminal lamp contract and the
-- bootstrap's own native damage note.
check(SC.TerminalLamp.isInstalled() and Events.OnPlayerGetDamage.count()==2
        and SC.TerminalLamp.install() and Events.OnPlayerGetDamage.count()==2,
    "terminal damage feedback is owned once through its production installer")
check(type(SC.Medical.noteNativeDamage)=="function"
        and Events.OnPlayerGetDamage.handlers[SC.Medical.noteNativeDamage]==true,
    "native damage notes are owned once by the bootstrap lifecycle")
check(SC.TerminalLockPhone.isInstalled() and SC.TerminalLockRadio.isInstalled()
        and Events.OnDeviceText.count()==1 and Events.OnFillWorldObjectContextMenu.count()==1
        and SC.TerminalLockPhone.install() and SC.TerminalLockRadio.install()
        and Events.OnDeviceText.count()==1 and Events.OnFillWorldObjectContextMenu.count()==1,
    "callback and escrow listeners are installed once through bootstrap")
do
    local previous=SC.TerminalHardware
    local loaded,placed
    SC.TerminalHardware={observeSquare=function(value) loaded=value end,
        observeObject=function(value) placed=value end}
    local square,object={},{}
    Events.LoadGridsquare.fire(square)
    Events.OnObjectAdded.fire(object)
    check(loaded==square and placed==object,"world load/place events dispatch their exact native radio candidates")
    SC.TerminalHardware=previous
end
check(SC.Factions.installs == 1 and SC.FactionContracts.installs == 1
        and SC.OddballRoomGuard.installs == 1
        and SC.OddballDistressRadio.installs == 1
        and SC.CompanionMap.installs == 1 and SC.BaseVisuals.installs == 1
        and SC.DiaryUI.installs == 1,
    "bootstrap owns the faction, encounter guard, minimap, base-visual, and diary hooks")
-- The diary context menu used to install itself at module load, outside the
-- install transaction: a failed bootstrap could not roll it back and a teardown
-- left the global event handler behind.
check(SC.DiaryUI.isInstalled(),
    "the diary context menu is owned by the bootstrap transaction, not self-installed")
check(SC.GridRadio.installs == 1,
    "the grid radio report hook is owned by the bootstrap transaction, not self-installed")

Events.OnGameStart.fire()
Events.OnGameStart.fire()
check(SC.UserOptions.loads == 2 and SC.Runtime.starts == 2
        and SC.Factions.installs == 1
        and SC.FactionContracts.installs == 1
        and SC.OddballRoomGuard.installs == 1
        and SC.OddballDistressRadio.installs == 1
        and SC.CompanionMap.installs == 1
        and SC.BaseVisuals.installs == 1 and SC.DiaryUI.installs == 1,
    "world starts do not duplicate long-lived hooks")

local removed, removeReason = SC.Bootstrap.remove()
check(removed and removeReason == "" and Events.OnInitGlobalModData.count() == 0
        and Events.OnGameStart.count() == 0
        and Events.OnSave.count() == 0 and Events.OnMainMenuEnter.count() == 0
        and not SC.Factions.installed and not SC.FactionContracts.installed
        and not SC.OddballRoomGuard.installed
        and not SC.OddballDistressRadio.installed
        and not SC.CompanionMap.installed and not SC.BaseVisuals.installed
        and not SC.DiaryUI.installed and not SC.GridRadio.installed,
    "bootstrap removal releases every lifecycle and contract hook")
check(Events.LoadGridsquare.count()==0 and Events.OnObjectAdded.count()==0,
    "radio load/place callbacks are removed with the bootstrap")
check(not SC.TerminalLockPhone.isInstalled() and not SC.TerminalLockRadio.isInstalled()
        and Events.OnDeviceText.count()==0 and Events.OnFillWorldObjectContextMenu.count()==0,
    "teardown releases callback and escrow listeners")
check(not SC.TerminalLamp.isInstalled() and Events.OnPlayerGetDamage.count()==0,
    "terminal damage feedback is removed with the bootstrap")

local optionLoad = SC.UserOptions.load
SC.UserOptions.load = nil
local optionsInstalled, optionsReason = SC.Bootstrap.install()
check(not optionsInstalled
        and string.find(tostring(optionsReason), "SCUserOptions.load", 1, true)
        and Events.OnGameStart.count() == 0 and not SC.Factions.installed,
    "bootstrap rejects an incomplete user options contract before acquiring hooks")
SC.UserOptions.load = optionLoad

local damageNote = SC.Medical.noteNativeDamage
SC.Medical.noteNativeDamage = nil
local damageInstalled, damageReason = SC.Bootstrap.install()
check(not damageInstalled and tostring(damageReason):find("SCMedical.noteNativeDamage",1,true)
        and Events.OnPlayerGetDamage.count()==0 and Events.OnGameStart.count()==0,
    "a missing native-damage callback rejects bootstrap before any hooks are acquired")
SC.Medical.noteNativeDamage = damageNote

Events.OnSave.failAdd = true
local installed, reason = SC.Bootstrap.install()
check(not installed and string.find(tostring(reason), "OnSave hook failed", 1, true)
        and not SC.Bootstrap.isInstalled() and Events.OnGameStart.count() == 0
        and Events.OnSave.count() == 0 and not SC.Factions.installed
        and not SC.FactionContracts.installed and not SC.CompanionMap.installed
        and not SC.OddballRoomGuard.installed
        and not SC.OddballDistressRadio.installed
        and not SC.BaseVisuals.installed and not SC.DiaryUI.installed,
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
        and Events.OnInitGlobalModData.count() == 1
        and Events.OnGameStart.count() == 1 and Events.OnSave.count() == 1
        and Events.OnMainMenuEnter.count() == 1
        and Events.LoadGridsquare.count()==1 and Events.OnObjectAdded.count()==1
        and SC.TerminalLamp.isInstalled() and Events.OnPlayerGetDamage.count()==2
        and Events.OnPlayerGetDamage.handlers[SC.Medical.noteNativeDamage]==true
        and SC.Factions.installed and SC.FactionContracts.installed
        and SC.OddballRoomGuard.installed
        and SC.OddballDistressRadio.installed
        and SC.CompanionMap.installed and SC.BaseVisuals.installed
        and SC.DiaryUI.installed
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

check(SC.Bootstrap.install(), "terminal damage callback removal fixture installs")
-- Fail only the lamp's callback. The bootstrap's native damage note on the same
-- event is removed first and must come back with the rollback.
Events.OnPlayerGetDamage.failRemove=function(callback)
    return callback~=SC.Medical.noteNativeDamage
end
removed,removeReason=SC.Bootstrap.remove()
check(not removed and allOwned()
        and string.find(tostring(removeReason),"terminal damage feedback",1,true),
    "a failed terminal damage callback removal retains its ownership and rolls back")
Events.OnPlayerGetDamage.failRemove=false
check(SC.Bootstrap.remove() and Events.OnPlayerGetDamage.count()==0,
    "terminal damage callback removal can be retried without orphaned events")

for _, entry in ipairs({
    { name = "OnMainMenuEnter", event = Events.OnMainMenuEnter },
    { name = "OnSave", event = Events.OnSave },
    { name = "OnGameStart", event = Events.OnGameStart },
    { name = "OnInitGlobalModData", event = Events.OnInitGlobalModData },
    { name = "LoadGridsquare", event = Events.LoadGridsquare },
    { name = "OnObjectAdded", event = Events.OnObjectAdded },
    { name = "OnPlayerGetDamage", event = Events.OnPlayerGetDamage },
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
    { name = "encounter room guard", owner = SC.OddballRoomGuard },
    { name = "rescue distress radio", owner = SC.OddballDistressRadio },
    { name = "faction contracts", owner = SC.FactionContracts },
    { name = "companion minimap", owner = SC.CompanionMap },
    { name = "base visuals", owner = SC.BaseVisuals },
    { name = "diary context menu", owner = SC.DiaryUI },
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
