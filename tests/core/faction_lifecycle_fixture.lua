-- SPDX-License-Identifier: MIT

local SC = SurvivorCompanion

local function event(name)
    local value = { name = name, handlers = {}, failAdd = false }
    function value.Add(callback)
        if value.failAdd then error("injected " .. name .. " Add failure") end
        value.handlers[#value.handlers + 1] = callback
    end
    function value.Remove(callback)
        for index = #value.handlers, 1, -1 do
            if value.handlers[index] == callback then table.remove(value.handlers, index) end
        end
    end
    function value.count()
        return #value.handlers
    end
    function value.fire(...)
        local snapshot = {}
        for index, callback in ipairs(value.handlers) do snapshot[index] = callback end
        for _, callback in ipairs(snapshot) do callback(...) end
    end
    return value
end

Events = {
    OnGameStart = event("OnGameStart"),
    OnSave = event("OnSave"),
    OnMainMenuEnter = event("OnMainMenuEnter"),
    OnTick = event("OnTick"),
    OnWeaponHitCharacter = event("OnWeaponHitCharacter"),
    OnZombieDead = event("OnZombieDead"),
}

SC_TEST_PLAYER = {
    notes = {},
    setHaloNote = function(self, message)
        self.notes[#self.notes + 1] = tostring(message)
        return true
    end,
}
function getPlayer() return SC_TEST_PLAYER end

SC_TEST_COUNTS = {
    actorDispose = 0,
    actorReset = 0,
    persistenceRestore = 0,
    schedulerReset = 0,
}

local configValues = {
    factionContractHistoryLimit = 32,
    factionContractMemoryLimit = 64,
    factionContractPromiseLimit = 24,
    factionNotificationLimit = 24,
    factionNotificationFlagLimit = 96,
    productionSpawnCheckIntervalMs = 10000,
    factionPulseIntervalMs = 1000,
    baseAuditIntervalMs = 1000,
    infectionCrisisIntervalMs = 1000,
    communityPulseIntervalMs = 1000,
    persistenceIntervalMs = 10000,
    movementIntervalMs = 100,
    disabledNoticeCooldownMs = 1000,
}

SC.Config = {
    get = function(key) return configValues[key] end,
    refreshSandbox = function() return true end,
    testSet = function(key, value) configValues[key] = value end,
}

SC.Diagnostics = {
    reports = {},
    report = function(subsystem, actorId, message, detail)
        SC.Diagnostics.reports[#SC.Diagnostics.reports + 1] = {
            subsystem = subsystem, actorId = actorId,
            message = message, detail = detail,
        }
    end,
    guard = function(_, _, callback, ...)
        local ok, a, b, c = pcall(callback, ...)
        if not ok then return false, a end
        return true, a, b, c
    end,
    reset = function() SC.Diagnostics.reports = {} end,
}

SC.GameplayUtil = {
    call = function(object, methodName, ...)
        if object == nil or type(object[methodName]) ~= "function" then
            return nil, false, "method unavailable"
        end
        local ok, a, b, c = pcall(object[methodName], object, ...)
        if not ok then return nil, false, tostring(a) end
        return a, true, b, c
    end,
    distance = function() return 0 end,
    nowMs = function() return SC_TEST_CLOCK end,
}

SC.Performance = { record = function() return true end }
SC.Transaction = SC.Transaction or {}
SC.Registry = {
    records = function() return {} end,
    byId = function() return nil end,
    reset = function() return true end,
}
SC.Vitals = { summary = function() return {} end }
SC.Scheduler = {
    tasks = {},
    reset = function()
        SC_TEST_COUNTS.schedulerReset = SC_TEST_COUNTS.schedulerReset + 1
        SC.Scheduler.tasks = {}
        return true
    end,
    register = function(name, interval, priority, callback, options)
        SC.Scheduler.tasks[name] = {
            interval = interval, priority = priority,
            callback = callback, options = options,
        }
        return true
    end,
    dueFor = function() return false end,
    tick = function() return true end,
}
SC.NativeActions = {}
SC.ActionSupervisor = { reset = function() return true end }
SC.Actor = {
    checkBridge = function() return true, "ready" end,
    disposeAll = function()
        SC_TEST_COUNTS.actorDispose = SC_TEST_COUNTS.actorDispose + 1
        return true
    end,
    reset = function()
        SC_TEST_COUNTS.actorReset = SC_TEST_COUNTS.actorReset + 1
        return true
    end,
    cancelSpawn = function() return true end,
}
SC.Persistence = {
    restore = function()
        SC_TEST_COUNTS.persistenceRestore = SC_TEST_COUNTS.persistenceRestore + 1
        return true
    end,
    save = function() return true end,
    restorePulse = function() return true end,
    reset = function() return true end,
}
SC.Vehicle = {
    reset = function() return true end,
    restorePulse = function() return true end,
    restoreForVehicle = function() return true end,
}
SC.Spawn = {
    reset = function() return true end,
    productionPulse = function() return true end,
    pollPending = function() return nil end,
}

local function resettable()
    return { reset = function() return true end }
end

for _, name in ipairs({
    "Background", "Dialogue", "Trade", "FactionLife", "FactionWorld",
    "FactionBehavior", "ZombieTargeting", "Locomotion", "Senses", "Navigation",
    "Positioning", "Combat", "Medical", "Logistics", "Needs", "Downtime",
    "Personality", "PersonalItems", "Relationship", "Objectives", "Journal",
    "BaseLife", "BaseWork", "InfectionCrisis", "LifeEvents", "Community",
    "Autonomy", "Commands", "FactionRecruitment", "Decision", "Support",
    "UIContext",
}) do
    SC[name] = SC[name] or resettable()
end
SC.Decision.resetAll = function() return true end
SC.Encounter = {
    markPlayerOpened = function() return true end,
    onPlayerContainerOpened = function() return true end,
}
SC.UI = {
    refresh = function() return true end,
    scheduledRefresh = function() return true end,
    reset = function() return true end,
}

SC.CompanionMap = { installed = false, installs = 0, removes = 0, failInstall = false }
function SC.CompanionMap.install()
    if SC.CompanionMap.installed then return true end
    if SC.CompanionMap.failInstall then return false, "injected map install failure" end
    SC.CompanionMap.installed = true
    SC.CompanionMap.installs = SC.CompanionMap.installs + 1
    return true
end
function SC.CompanionMap.remove()
    if SC.CompanionMap.installed then SC.CompanionMap.removes = SC.CompanionMap.removes + 1 end
    SC.CompanionMap.installed = false
    return true
end
function SC.CompanionMap.isInstalled() return SC.CompanionMap.installed end

ISInventoryPage = {
    selectContainer = function() return true end,
    setNewContainer = function() return true end,
}
