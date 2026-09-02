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
require "SCZombieAttack"
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
local cleanupPending = false
local lifecycleOwned = {}

-- Build 42's Kahlua environment does not consistently publish Lua's global
-- next(). Use portable iteration for lifecycle ownership checks.
local function tableHasEntries(value)
    if type(value) ~= "table" then return false end
    for _ in pairs(value) do return true end
    return false
end

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

-- Module presence alone is not a usable startup contract. These are the
-- narrow entry points bootstrap owns directly; fail before acquiring any
-- global event if a partial load or incompatible module replaced one.
local requiredFunctions = {
    { "Config", "refreshSandbox" },
    { "Diagnostics", "report" },
    { "Runtime", "start" },
    { "Runtime", "reset" },
    { "Runtime", "save" },
    { "Runtime", "onMainMenuEnter" },
    { "Factions", "installHooks" },
    { "Factions", "removeHooks" },
    { "Factions", "hooksInstalled" },
    { "FactionContracts", "installHooks" },
    { "FactionContracts", "removeHooks" },
    { "FactionContracts", "hooksInstalled" },
    { "CompanionMap", "install" },
    { "CompanionMap", "remove" },
    { "CompanionMap", "isInstalled" },
    { "Encounter", "onPlayerContainerOpened" },
    { "UI", "scheduledRefresh" },
}

local function validateModules()
    for _, name in ipairs(requiredModules) do
        if type(SC[name]) ~= "table" then
            return false, "required module is unavailable: SC" .. name
        end
    end
    for _, contract in ipairs(requiredFunctions) do
        local owner = SC[contract[1]]
        if type(owner) ~= "table" or type(owner[contract[2]]) ~= "function" then
            return false, "required module function is unavailable: SC"
                .. contract[1] .. "." .. contract[2]
        end
    end
    return true
end

local contractDefinitions = {
    { name = "faction combat", owner = function() return SC.Factions end,
        install = "installHooks", remove = "removeHooks", state = "hooksInstalled" },
    { name = "faction contracts", owner = function() return SC.FactionContracts end,
        install = "installHooks", remove = "removeHooks", state = "hooksInstalled" },
    { name = "companion minimap", owner = function() return SC.CompanionMap end,
        install = "install", remove = "remove", state = "isInstalled" },
}

local function contractState(contract)
    local owner = contract.owner()
    local callback = owner and owner[contract.state]
    if type(callback) ~= "function" then return false end
    local called, value = pcall(callback)
    return called and value == true
end

local function allContractsInstalled()
    for _, contract in ipairs(contractDefinitions) do
        if not contractState(contract) then return false end
    end
    return true
end

local function anyContractInstalled()
    for _, contract in ipairs(contractDefinitions) do
        if contractState(contract) then return true end
    end
    return false
end

local function rollbackContracts(acquired)
    local failures = {}
    for index = #acquired, 1, -1 do
        local item = acquired[index]
        local owner = item.owner()
        local callback = owner and owner[item.remove]
        local called, ok, reason
        if type(callback) == "function" then
            called, ok, reason = pcall(callback)
        else
            called, ok, reason = false, false, "remover unavailable"
        end
        if not called or ok == false or contractState(item) then
            failures[#failures + 1] = item.name .. ": "
                .. tostring(not called and ok or reason
                    or "rollback postcondition failed")
        end
    end
    contractsInstalled = allContractsInstalled()
    return #failures == 0, table.concat(failures, "; ")
end

local function installContracts()
    local acquired = {}
    for _, contract in ipairs(contractDefinitions) do
        local owner = contract.owner()
        if not contractState(contract) then
            local callback = owner and owner[contract.install]
            if type(callback) ~= "function" then
                local rolledBack, rollbackReason = rollbackContracts(acquired)
                return false, contract.name .. " installer is unavailable"
                    .. (rolledBack and "" or "; rollback incomplete: "
                        .. tostring(rollbackReason))
            end
            local called, ok, reason = pcall(callback)
            if not called or ok ~= true or not contractState(contract) then
                local rolledBack, rollbackReason = rollbackContracts(acquired)
                return false, contract.name .. " hook failed: "
                    .. tostring(called and reason or ok)
                    .. (rolledBack and "" or "; rollback incomplete: "
                        .. tostring(rollbackReason))
            end
            acquired[#acquired + 1] = contract
        end
    end
    contractsInstalled = allContractsInstalled()
    return contractsInstalled, contractsInstalled and nil
        or "one or more runtime contracts failed their installation postcondition"
end

local function removeContracts()
    local failures = {}
    for index = #contractDefinitions, 1, -1 do
        local contract = contractDefinitions[index]
        local owner = contract.owner()
        local callback = owner and owner[contract.remove]
        if type(callback) == "function" then
            local called, ok, reason = pcall(callback)
            if not called or ok == false or contractState(contract) then
                failures[#failures + 1] = contract.name .. ": "
                    .. tostring(not called and ok or reason or "removal postcondition failed")
            end
        else
            failures[#failures + 1] = contract.name .. ": remover unavailable"
        end
    end
    contractsInstalled = allContractsInstalled()
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

local lifecycleDefinitions = {
    { event = function() return Events and Events.OnGameStart end,
        callback = onGameStart, name = "OnGameStart" },
    { event = function() return Events and Events.OnSave end,
        callback = onSave, name = "OnSave" },
    { event = function() return Events and Events.OnMainMenuEnter end,
        callback = onMainMenuEnter, name = "OnMainMenuEnter" },
}

-- A failed install rollback is not an installed bootstrap. Keep the exact
-- callback ownership separately so a later install/remove can finish cleanup
-- without falsely returning success from the ordinary `installed` fast path.
local function cleanupPartialInstall()
    local failures = {}
    for index = #lifecycleDefinitions, 1, -1 do
        local entry = lifecycleDefinitions[index]
        if lifecycleOwned[entry.name] == true then
            local event = entry.event()
            local called, reason = pcall(event.Remove, entry.callback)
            if called then
                lifecycleOwned[entry.name] = nil
            else
                failures[#failures + 1] = entry.name .. ": " .. tostring(reason)
            end
        end
    end
    local contractsRemoved, contractReason = removeContracts()
    if not contractsRemoved then
        failures[#failures + 1] = tostring(contractReason)
    end
    cleanupPending = #failures > 0 or tableHasEntries(lifecycleOwned)
        or anyContractInstalled()
    installed = false
    SC.Modules.bootstrap = nil
    return not cleanupPending, table.concat(failures, "; ")
end

function bootstrap.install()
    if installed then return true end
    if cleanupPending or tableHasEntries(lifecycleOwned) or anyContractInstalled() then
        local cleaned, cleanupReason = cleanupPartialInstall()
        if not cleaned then
            return false, "prior partial bootstrap install could not be cleaned: "
                .. tostring(cleanupReason)
        end
    end
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
    if not contractsOk then
        local cleaned, cleanupReason = cleanupPartialInstall()
        if not cleaned then
            contractsReason = tostring(contractsReason) .. "; cleanup incomplete: "
                .. tostring(cleanupReason)
        end
        return false, contractsReason
    end
    local added = {}
    for _, entry in ipairs(lifecycleDefinitions) do
        local event = entry.event()
        local ok, addReason = pcall(event.Add, entry.callback)
        if not ok then
            local rollbackFailures = {}
            for index = #added, 1, -1 do
                local prior = added[index]
                local priorEvent = prior.event()
                local removed, removeReason = pcall(priorEvent.Remove, prior.callback)
                if removed then
                    lifecycleOwned[prior.name] = nil
                else
                    rollbackFailures[#rollbackFailures + 1] = prior.name .. ": "
                        .. tostring(removeReason)
                end
            end
            local contractsRemoved, contractRemoveReason = removeContracts()
            if not contractsRemoved then
                rollbackFailures[#rollbackFailures + 1] = tostring(contractRemoveReason)
            end
            if #rollbackFailures > 0 then
                cleanupPending = true
                installed = false
                SC.Modules.bootstrap = nil
                return false, entry.name .. " hook failed: " .. tostring(addReason)
                    .. "; rollback incomplete: " .. table.concat(rollbackFailures, "; ")
            end
            cleanupPending = false
            return false, entry.name .. " hook failed: " .. tostring(addReason)
        end
        added[#added + 1] = entry
        lifecycleOwned[entry.name] = true
    end
    installed = true
    cleanupPending = false
    SC.Modules.bootstrap = true
    return true
end

function bootstrap.remove()
    if not installed then
        if cleanupPending or tableHasEntries(lifecycleOwned) or anyContractInstalled() then
            return cleanupPartialInstall()
        end
        return true
    end
    local removed = {}
    local function restoreRemovedLifecycle()
        local failures = {}
        for index = #removed, 1, -1 do
            local entry = removed[index]
            local event = entry.event()
            local called, reason = pcall(event.Add, entry.callback)
            if called then
                lifecycleOwned[entry.name] = true
            else
                failures[#failures + 1] = entry.name .. ": " .. tostring(reason)
            end
        end
        return #failures == 0, table.concat(failures, "; ")
    end

    for index = #lifecycleDefinitions, 1, -1 do
        local entry = lifecycleDefinitions[index]
        local event = entry.event()
        local called, reason = pcall(event.Remove, entry.callback)
        if not called then
            local restored, restoreReason = restoreRemovedLifecycle()
            return false, entry.name .. " removal failed: " .. tostring(reason)
                .. (restored and "" or "; lifecycle rollback failed: "
                    .. tostring(restoreReason))
        end
        removed[#removed + 1] = entry
        lifecycleOwned[entry.name] = nil
    end

    local contractsOk, contractsReason = removeContracts()
    if not contractsOk then
        contractsInstalled = false
        local restoredContracts, restoreContractsReason = installContracts()
        local restoredLifecycle, restoreLifecycleReason = restoreRemovedLifecycle()
        local detail = tostring(contractsReason)
        if not restoredContracts then
            detail = detail .. "; contract rollback failed: "
                .. tostring(restoreContractsReason)
        end
        if not restoredLifecycle then
            detail = detail .. "; lifecycle rollback failed: "
                .. tostring(restoreLifecycleReason)
        end
        return false, detail
    end

    -- Runtime teardown is the final commit boundary. No callback ownership is
    -- published as released until native/Lua world state has also reset. A
    -- failed reset restores every long-lived hook so cleanup can be retried.
    local resetCalled, resetOk, resetReason = pcall(SC.Runtime.reset, true)
    if not resetCalled or resetOk ~= true then
        contractsInstalled = false
        local restoredContracts, restoreContractsReason = installContracts()
        local restoredLifecycle, restoreLifecycleReason = restoreRemovedLifecycle()
        local detail = "runtime reset failed; bootstrap ownership restored: "
            .. tostring(resetCalled and resetReason or resetOk)
        if not restoredContracts then
            detail = detail .. "; contract rollback failed: "
                .. tostring(restoreContractsReason)
        end
        if not restoredLifecycle then
            detail = detail .. "; lifecycle rollback failed: "
                .. tostring(restoreLifecycleReason)
        end
        return false, detail
    end
    installed = false
    cleanupPending = false
    lifecycleOwned = {}
    SC.Modules.bootstrap = nil
    return true, ""
end

function bootstrap.isInstalled()
    return installed and not cleanupPending
end

function bootstrap.cleanupPending()
    return cleanupPending
end

local ok, reason = bootstrap.install()
if not ok then
    SC.State.disabledReason = reason
    SC.Diagnostics.report("bootstrap", nil, "bootstrap installation failed", reason)
end

return bootstrap
