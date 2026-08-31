-- SPDX-License-Identifier: MIT

local SC = SurvivorCompanion

local function event()
    local value = { handlers = {}, failAdd = false }
    function value.Add(callback)
        if value.failAdd then error("injected lifecycle Add failure") end
        value.handlers[callback] = true
    end
    function value.Remove(callback) value.handlers[callback] = nil end
    function value.count()
        local count = 0
        for _ in pairs(value.handlers) do count = count + 1 end
        return count
    end
    function value.fire()
        for callback in pairs(value.handlers) do callback() end
    end
    return value
end

Events = {
    OnGameStart = event(), OnSave = event(), OnMainMenuEnter = event(),
    OnWeaponHitCharacter = event(), OnZombieDead = event(),
}

SC.Config = { refreshSandbox = function() return true end }
SC.Diagnostics = { report = function() end }
SC.Encounter = { markPlayerOpened = function() return true end }
SC.UI = { refresh = function() return true end }
SC.Runtime = {
    starts = 0, resets = 0,
    start = function()
        SC.Runtime.starts = SC.Runtime.starts + 1
        return true, nil, true
    end,
    save = function() return true end,
    reset = function()
        SC.Runtime.resets = SC.Runtime.resets + 1
        return true
    end,
    onMainMenuEnter = function() return true end,
}

local required = {
    "Call", "StableValue", "Transaction", "NativeList", "Registry", "Vitals",
    "Scheduler", "NativeActions", "Performance", "ActionSupervisor", "Actor",
    "Persistence", "Vehicle", "Spawn", "GameplayUtil",
    "Background", "Dialogue", "Trade", "FactionLife",
    "FactionWorld", "FactionBehavior", "ZombieTargeting", "Locomotion", "Senses",
    "Navigation", "Positioning", "Combat", "Medical", "Logistics", "Needs", "Downtime",
    "Personality", "PersonalItems", "Relationship", "Objectives", "Journal", "BaseLife",
    "BaseWork", "InfectionCrisis", "LifeEvents", "Community", "Autonomy", "Commands",
    "FactionRecruitment", "Decision", "Support", "UIContext",
}
for _, name in ipairs(required) do SC[name] = SC[name] or {} end

local function ownedHooks()
    local value = { installed = false, installs = 0, removes = 0 }
    function value.installHooks()
        if value.installed then return true end
        value.installed = true
        value.installs = value.installs + 1
        return true
    end
    function value.removeHooks()
        if value.installed then value.removes = value.removes + 1 end
        value.installed = false
        return true
    end
    return value
end

SC.Factions = ownedHooks()
SC.FactionContracts = ownedHooks()
SC.CompanionMap = { installed = false, installs = 0, removes = 0 }
function SC.CompanionMap.install()
    if SC.CompanionMap.installed then return true end
    SC.CompanionMap.installed = true
    SC.CompanionMap.installs = SC.CompanionMap.installs + 1
    return true
end
function SC.CompanionMap.remove()
    if SC.CompanionMap.installed then SC.CompanionMap.removes = SC.CompanionMap.removes + 1 end
    SC.CompanionMap.installed = false
    return true
end
