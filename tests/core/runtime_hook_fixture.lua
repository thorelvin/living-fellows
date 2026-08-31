-- SPDX-License-Identifier: MIT

local SC = SurvivorCompanion

local tickHandlers = {}
Events = {
    OnTick = {
        Add = function(callback) tickHandlers[callback] = true end,
        Remove = function(callback) tickHandlers[callback] = nil end,
    },
}

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
    checkBridge = function() return false, "fixture has no actor provider" end,
    disposeCalls = 0,
    disposeAll = function()
        SC.Actor.disposeCalls = SC.Actor.disposeCalls + 1
        return true
    end,
    reset = function() end,
}
SC.Registry = {
    records = function() return {} end,
    reset = function() end,
}
SC.Scheduler = {
    reset = function() end,
    register = function() return true end,
    tick = function() end,
    dueFor = function() return false end,
}
SC.Persistence = {
    restore = function() return true end,
    restorePulse = function() return true end,
    save = function() return true end,
    reset = function() end,
}
SC.Vehicle = {
    restoreForVehicle = function() return 0 end,
    reset = function() end,
}
SC.Spawn = {
    debugPulse = function() return false end,
    reset = function() end,
}
SC.Vitals = { summary = function() return {} end }
SC.Encounter = {
    opened = 0,
    onPlayerContainerOpened = function(container)
        if container ~= nil then SC.Encounter.opened = SC.Encounter.opened + 1 end
    end,
}
