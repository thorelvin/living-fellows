-- SPDX-License-Identifier: MIT

require "SCNamespace"
require "SCCall"
require "SCStableValue"
require "SCTransaction"
require "SCNativeList"
require "SCConfig"
require "SCDiagnostics"
require "SCNet"
require "SCRegistry"
require "SCVitals"
require "SCScheduler"
require "SCNativeActions"
require "SCActionSupervisor"
require "SCBackground"
require "SCActor"
require "SCPersistence"
require "SCVehicle"
require "SCSpawn"

require "SCGameplayUtil"
require "SCLocomotion"
require "SCDialogue"
require "SCFactions"
require "SCTrade"
require "SCFactionLife"
require "SCFactionContracts"
require "SCFactionWorld"
require "SCFactionBehavior"
require "SCZombieTargeting"
require "SCSenses"
require "SCNavigation"
require "SCPositioning"
require "SCCombat"
require "SCMedical"
require "SCEncounter"
require "SCLogistics"
require "SCNeeds"
require "SCDowntime"
require "SCPersonality"
require "SCPersonalItems"
require "SCRelationship"
require "SCObjectives"
require "SCJournal"
require "SCBaseLife"
require "SCBaseWork"
require "SCInfectionCrisis"
require "SCLifeEvents"
require "SCCommunity"
require "SCAutonomy"
require "SCCommands"
require "SCFactionRecruitment"
require "SCDecision"
require "SCSupport"
require "SCUI"
require "SCUIContext"
require "SCCompanionMap"
require "ISUI/ISInventoryPage"
require "SCRuntime"

local SC = SurvivorCompanion
SC.Bootstrap = SC.Bootstrap or {}

local bootstrap = SC.Bootstrap
local installed = false
local contractsInstalled = false
local encounterFallback = nil
local uiFallback = nil

local requiredModules = {
    "Call", "StableValue", "Transaction", "NativeList", "Config", "Diagnostics",
    "Registry", "Vitals", "Scheduler", "NativeActions", "Performance",
    "ActionSupervisor", "Actor", "Persistence", "Vehicle", "Spawn", "GameplayUtil",
    "Background", "Dialogue", "Factions", "Trade", "FactionLife", "FactionContracts", "FactionWorld",
    "FactionBehavior", "ZombieTargeting",
    "Locomotion", "Senses", "Navigation", "Positioning", "Combat", "Medical", "Encounter",
    "Logistics", "Needs", "Downtime", "Personality", "PersonalItems", "Relationship",
    "Objectives", "Journal", "BaseLife", "BaseWork", "InfectionCrisis",
    "LifeEvents", "Community", "Autonomy",
    "Commands", "FactionRecruitment", "Decision", "Support", "UI", "UIContext",
    "CompanionMap",
}

local function validateModules()
    for _, name in ipairs(requiredModules) do
        if type(SC[name]) ~= "table" then
            return false, "required module is unavailable: SC" .. name
        end
    end
    return true
end

local function installContracts()
    if contractsInstalled then return true end
    if type(SC.Encounter.onPlayerContainerOpened) ~= "function" then
        encounterFallback = function(container)
            return SC.Encounter.markPlayerOpened(container)
        end
        SC.Encounter.onPlayerContainerOpened = encounterFallback
    end
    if type(SC.UI.scheduledRefresh) ~= "function" then
        uiFallback = function()
            return SC.UI.refresh()
        end
        SC.UI.scheduledRefresh = uiFallback
    end

    local acquired = {}
    local installers = {
        { name = "faction combat", owner = SC.Factions, install = "installHooks",
            remove = "removeHooks" },
        { name = "faction contracts", owner = SC.FactionContracts, install = "installHooks",
            remove = "removeHooks" },
        { name = "companion minimap", owner = SC.CompanionMap, install = "install",
            remove = "remove" },
    }
    for _, contract in ipairs(installers) do
        local callback = contract.owner and contract.owner[contract.install]
        if type(callback) ~= "function" then
            for index = #acquired, 1, -1 do
                local item = acquired[index]
                pcall(item.owner[item.remove])
            end
            return false, contract.name .. " installer is unavailable"
        end
        local called, ok, reason = pcall(callback)
        if not called or ok ~= true then
            for index = #acquired, 1, -1 do
                local item = acquired[index]
                pcall(item.owner[item.remove])
            end
            return false, contract.name .. " hook failed: " .. tostring(called and reason or ok)
        end
        acquired[#acquired + 1] = contract
    end
    contractsInstalled = true
    return true
end

local function removeContracts()
    local failures = {}
    local removers = {
        { name = "companion minimap", owner = SC.CompanionMap, callback = "remove" },
        { name = "faction contracts", owner = SC.FactionContracts, callback = "removeHooks" },
        { name = "faction combat", owner = SC.Factions, callback = "removeHooks" },
    }
    for _, contract in ipairs(removers) do
        local callback = contract.owner and contract.owner[contract.callback]
        if type(callback) == "function" then
            local called, ok, reason = pcall(callback)
            if not called or ok == false then
                failures[#failures + 1] = contract.name .. ": "
                    .. tostring(called and reason or ok)
            end
        end
    end
    if encounterFallback ~= nil and SC.Encounter.onPlayerContainerOpened == encounterFallback then
        SC.Encounter.onPlayerContainerOpened = nil
    end
    if uiFallback ~= nil and SC.UI.scheduledRefresh == uiFallback then
        SC.UI.scheduledRefresh = nil
    end
    encounterFallback, uiFallback = nil, nil
    contractsInstalled = #failures > 0
    return #failures == 0, table.concat(failures, "; ")
end

local function onGameStart()
    if SC.Config and type(SC.Config.refreshSandbox) == "function" then
        SC.Config.refreshSandbox()
    end
    local valid, reason = validateModules()
    if not valid then
        SC.State.active = false
        SC.State.disabledReason = reason
        SC.Diagnostics.report("bootstrap", nil, "module contract failed", reason)
        return
    end
    local contractsOk, contractsReason = installContracts()
    if not contractsOk then
        SC.State.active = false
        SC.State.disabledReason = contractsReason
        SC.Diagnostics.report("bootstrap", nil, "runtime contracts failed", contractsReason)
        return
    end
    local _, runtimeReason, operational = SC.Runtime.start()
    if operational == false then
        SC.State.active = false
        SC.State.disabledReason = runtimeReason
        SC.Diagnostics.report("bootstrap", nil, "runtime start failed", runtimeReason)
    end
end

local function onSave()
    local ok, reason = SC.Runtime.save()
    if not ok then SC.Diagnostics.report("persistence", nil, "OnSave failed", reason) end
end

local function onMainMenuEnter()
    SC.Runtime.onMainMenuEnter()
end

function bootstrap.install()
    if installed then return true end
    local valid, reason = validateModules()
    if not valid then return false, reason end
    if Events == nil or Events.OnGameStart == nil or Events.OnSave == nil
        or Events.OnMainMenuEnter == nil
        or type(Events.OnGameStart.Add) ~= "function"
        or type(Events.OnGameStart.Remove) ~= "function"
        or type(Events.OnSave.Add) ~= "function"
        or type(Events.OnSave.Remove) ~= "function"
        or type(Events.OnMainMenuEnter.Add) ~= "function"
        or type(Events.OnMainMenuEnter.Remove) ~= "function" then
        return false, "required Project Zomboid lifecycle events are unavailable"
    end
    local contractsOk, contractsReason = installContracts()
    if not contractsOk then return false, contractsReason end
    local added = {}
    for _, entry in ipairs({
        { event = Events.OnGameStart, callback = onGameStart, name = "OnGameStart" },
        { event = Events.OnSave, callback = onSave, name = "OnSave" },
        { event = Events.OnMainMenuEnter, callback = onMainMenuEnter,
            name = "OnMainMenuEnter" },
    }) do
        local ok, addReason = pcall(entry.event.Add, entry.callback)
        if not ok then
            for index = #added, 1, -1 do
                pcall(added[index].event.Remove, added[index].callback)
            end
            removeContracts()
            return false, entry.name .. " hook failed: " .. tostring(addReason)
        end
        added[#added + 1] = entry
    end
    installed = true
    SC.Modules.bootstrap = true
    return true
end

function bootstrap.remove()
    if not installed then return true end
    local failures = {}
    local resetOk, resetReason = SC.Runtime.reset(true)
    if resetOk == false then failures[#failures + 1] = tostring(resetReason) end
    if Events ~= nil then
        for _, entry in ipairs({
            { event = Events.OnMainMenuEnter, callback = onMainMenuEnter },
            { event = Events.OnSave, callback = onSave },
            { event = Events.OnGameStart, callback = onGameStart },
        }) do
            if entry.event ~= nil and type(entry.event.Remove) == "function" then
                local ok, removeReason = pcall(entry.event.Remove, entry.callback)
                if not ok then failures[#failures + 1] = tostring(removeReason) end
            end
        end
    end
    local contractsOk, contractsReason = removeContracts()
    if not contractsOk then failures[#failures + 1] = contractsReason end
    installed = false
    SC.Modules.bootstrap = nil
    return #failures == 0, table.concat(failures, "; ")
end

function bootstrap.isInstalled()
    return installed
end

local ok, reason = bootstrap.install()
if not ok then
    SC.State.disabledReason = reason
    SC.Diagnostics.report("bootstrap", nil, "bootstrap installation failed", reason)
end

return bootstrap
