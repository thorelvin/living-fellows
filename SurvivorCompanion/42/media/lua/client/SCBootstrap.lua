-- SPDX-License-Identifier: MIT

require "SCNamespace"
require "SCConfig"
require "SCDiagnostics"
require "SCNet"
require "SCRegistry"
require "SCVitals"
require "SCScheduler"
require "SCNativeActions"
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

local requiredModules = {
    "Performance",
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
    if type(SC.Encounter.onPlayerContainerOpened) ~= "function" then
        SC.Encounter.onPlayerContainerOpened = function(container)
            return SC.Encounter.markPlayerOpened(container)
        end
    end
    if type(SC.UI.scheduledRefresh) ~= "function" then
        SC.UI.scheduledRefresh = function()
            return SC.UI.refresh()
        end
    end
    if SC.Factions and type(SC.Factions.installHooks) == "function" then
        SC.Factions.installHooks()
    end
    if SC.FactionContracts and type(SC.FactionContracts.installHooks) == "function" then
        SC.FactionContracts.installHooks()
    end
    if SC.CompanionMap and type(SC.CompanionMap.install) == "function" then
        SC.CompanionMap.install()
    end
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
    installContracts()
    SC.Runtime.start()
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
    installContracts()
    if Events == nil or Events.OnGameStart == nil or Events.OnSave == nil
        or Events.OnMainMenuEnter == nil then
        return false, "required Project Zomboid lifecycle events are unavailable"
    end
    Events.OnGameStart.Add(onGameStart)
    Events.OnSave.Add(onSave)
    Events.OnMainMenuEnter.Add(onMainMenuEnter)
    installed = true
    SC.Modules.bootstrap = true
    return true
end

function bootstrap.remove()
    if not installed then return end
    SC.Runtime.reset(true)
    if SC.Factions and type(SC.Factions.removeHooks) == "function" then
        SC.Factions.removeHooks()
    end
    if SC.CompanionMap and type(SC.CompanionMap.remove) == "function" then
        SC.CompanionMap.remove()
    end
    if Events ~= nil then
        if Events.OnGameStart ~= nil then Events.OnGameStart.Remove(onGameStart) end
        if Events.OnSave ~= nil then Events.OnSave.Remove(onSave) end
        if Events.OnMainMenuEnter ~= nil then Events.OnMainMenuEnter.Remove(onMainMenuEnter) end
    end
    installed = false
    SC.Modules.bootstrap = nil
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
