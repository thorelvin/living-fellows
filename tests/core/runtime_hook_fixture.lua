-- SPDX-License-Identifier: MIT

local SC = SurvivorCompanion

local tickHandlers = {}
SC_RUNTIME_FIXTURE = {
    failTickAdd = false,
    failTickRemove = false,
    rejectTask = nil,
    bridgeThrows = false,
    restoreThrows = false,
    restoreResult = true,
    restoreReason = nil,
    prepareThrows = false,
    prepareResult = true,
    prepareReason = nil,
}
Events = {
    OnTick = {
        Add = function(callback)
            if SC_RUNTIME_FIXTURE.failTickAdd then error("injected OnTick add failure") end
            tickHandlers[callback] = true
        end,
        Remove = function(callback)
            if SC_RUNTIME_FIXTURE.failTickRemove then error("injected OnTick remove failure") end
            tickHandlers[callback] = nil
        end,
    },
}
function SC_RUNTIME_FIXTURE.tickCount()
    local count = 0
    for _ in pairs(tickHandlers) do count = count + 1 end
    return count
end

ISInventoryPage = {}
function ISInventoryPage.selectContainer(self, button)
    self.inventoryPane.inventory = button and button.inventory or nil
    return "selected"
end
function ISInventoryPage.setNewContainer(self, inventory)
    self.inventoryPane.inventory = inventory
    return "changed"
end

local localPlayer = {}
local playerModData = {}
function localPlayer:getModData() return playerModData end
function SC_RUNTIME_FIXTURE.setDocument(value) playerModData.SC_SaveV1 = value end
function SC_RUNTIME_FIXTURE.document() return playerModData.SC_SaveV1 end
function localPlayer:setHaloNote(message)
    self.haloNotes = (self.haloNotes or 0) + 1
    self.lastHalo = message
    self.haloMessages = self.haloMessages or {}
    self.haloMessages[#self.haloMessages + 1] = message
end
function getPlayer() return localPlayer end
function getText(key, detail)
    if key == "UI_SC_RuntimeDisabled_Provider" then
        return "TRANSLATED PROVIDER NOTICE: " .. tostring(detail)
    elseif key == "UI_SC_RuntimeDisabled_Multiplayer" then
        return "TRANSLATED MULTIPLAYER NOTICE"
    end
    return key
end

SC.Actor = {
    checkBridge = function()
        if SC_RUNTIME_FIXTURE.bridgeThrows then error("injected bridge exception") end
        return false, "fixture has no actor provider"
    end,
    disposeCalls = 0,
    disposeResult = true,
    resetCalls = 0,
    disposeAll = function()
        SC.Actor.disposeCalls = SC.Actor.disposeCalls + 1
        return SC.Actor.disposeResult, SC.Actor.disposeResult and nil or "injected native cleanup failure"
    end,
    reset = function() SC.Actor.resetCalls = SC.Actor.resetCalls + 1 end,
}
SC.Registry = {
    records = function() return {} end,
    resetCalls = 0,
    reset = function() SC.Registry.resetCalls = SC.Registry.resetCalls + 1 end,
}
SC.Scheduler = {
    registrations = {},
    resetCalls = 0,
    reset = function()
        SC.Scheduler.resetCalls = SC.Scheduler.resetCalls + 1
        SC.Scheduler.registrations = {}
    end,
    register = function(name)
        if SC_RUNTIME_FIXTURE.rejectTask == name then
            return false, "injected scheduler rejection: " .. tostring(name)
        end
        SC.Scheduler.registrations[name] = true
        return true
    end,
    tick = function() end,
    dueFor = function() return false end,
}
SC.Persistence = {
    restoreCalls = 0,
    saveCalls = 0,
    committed = false,
    restore = function()
        SC.Persistence.restoreCalls = SC.Persistence.restoreCalls + 1
        if SC_RUNTIME_FIXTURE.restoreThrows then error("injected restore exception") end
        SC.Persistence.committed = SC_RUNTIME_FIXTURE.restoreResult == true
        return SC_RUNTIME_FIXTURE.restoreResult, SC_RUNTIME_FIXTURE.restoreReason
    end,
    restorePulse = function() return true end,
    save = function()
        SC.Persistence.saveCalls = SC.Persistence.saveCalls + 1
        playerModData.SC_SaveV1 = { overwritten = true }
        return true
    end,
    prepareReset = function()
        if SC_RUNTIME_FIXTURE.prepareThrows then error("injected prepare-reset exception") end
        return SC_RUNTIME_FIXTURE.prepareResult, SC_RUNTIME_FIXTURE.prepareReason
    end,
    restoreStatus = function()
        return SC.Persistence.committed,
            SC.Persistence.committed and nil or SC_RUNTIME_FIXTURE.restoreReason
    end,
    resetCalls = 0,
    reset = function()
        SC.Persistence.resetCalls = SC.Persistence.resetCalls + 1
        SC.Persistence.committed = false
        return true
    end,
}
SC.Vehicle = {
    restoreForVehicle = function() return 0 end,
    resetCalls = 0,
    reset = function() SC.Vehicle.resetCalls = SC.Vehicle.resetCalls + 1 end,
}
SC.Spawn = {
    debugPulse = function() return false end,
    resetCalls = 0,
    reset = function() SC.Spawn.resetCalls = SC.Spawn.resetCalls + 1 end,
}
SC.Vitals = { summary = function() return {} end }
SC.Encounter = {
    opened = 0,
    onPlayerContainerOpened = function(container)
        if container ~= nil then SC.Encounter.opened = SC.Encounter.opened + 1 end
    end,
}
SC.Factions = {
    resetCalls = 0,
    reset = function() SC.Factions.resetCalls = SC.Factions.resetCalls + 1 end,
}
SC.FactionContracts = {
    resetCalls = 0,
    removeCalls = 0,
    reset = function() SC.FactionContracts.resetCalls = SC.FactionContracts.resetCalls + 1 end,
    removeHooks = function()
        SC.FactionContracts.removeCalls = SC.FactionContracts.removeCalls + 1
        return true
    end,
}
SC.Decision = {
    resetCalls = 0,
    resetMode = "success",
    resetAll = function()
        SC.Decision.resetCalls = SC.Decision.resetCalls + 1
        if SC.Decision.resetMode == "false" then
            return false, "injected decision reset rejection"
        elseif SC.Decision.resetMode == "throw" then
            error("injected decision reset exception")
        end
        return true
    end,
}
SC.Community = {
    resetCalls = 0,
    reset = function() SC.Community.resetCalls = SC.Community.resetCalls + 1 end,
}
SC.Diagnostics.resetCalls = 0
SC.Diagnostics.reportCalls = 0
SC.Diagnostics.reset = function()
    SC.Diagnostics.resetCalls = SC.Diagnostics.resetCalls + 1
    return true
end
SC.Diagnostics.report = function()
    SC.Diagnostics.reportCalls = SC.Diagnostics.reportCalls + 1
    return true
end
