-- SPDX-License-Identifier: MIT
-- Small game-UI stand-ins for the active-expedition zoom control.
SurvivorCompanion = {
    UI = {
        text = function(key, value)
            if key == "UI_SC_Info_Message" then return tostring(value) end
            if key == "UI_SC_Expedition_ViewZoomValue" then
                return "Zoom: " .. tostring(value) .. "%"
            end
            if key == "UI_SC_Expedition_Phase_searching" then
                return "searching for supplies"
            end
            if key == "UI_SC_Expedition_NearbyStatus" then
                return "Leader nearby. Mission phase: " .. tostring(value) .. "."
            end
            return key
        end,
        layoutMetrics = function()
            return { fontHeight = 16, infoLineHeight = 20,
                buttonHeight = 26 }
        end,
    },
}

local leader = { name = "Leader" }
local player = { name = "Player" }
local slot = nil
local mission = { leader = { actor = leader }, radioSession = "trip-1" }
local view = { leaderName = "Leader", plannedSite = "Farm" }
local zoom = { min = 0.5, max = 2.0, target = 1.25 }
local changes = {}
local setterWorks = true
local readerWorks = true
local viewOwner = "expedition"
local debrief, pendingReports

ExpeditionZoomFixture = {
    leader = leader, mission = mission, view = view,
    zoom = zoom, changes = changes,
    join = function() slot = leader end,
    leave = function() slot = nil end,
    endTrip = function() mission = nil end,
    startTrip = function() mission = {
        leader = { actor = leader }, radioSession = "trip-2" } end,
    setSetterWorks = function(value) setterWorks = value end,
    setReaderWorks = function(value) readerWorks = value end,
    setOwner = function(value) viewOwner = value end,
    setDebrief = function(value) debrief = value end,
    setPendingReports = function(value) pendingReports = value end,
}

SurvivorCompanion.ViewSession = {
    owner = function() return viewOwner end,
}

getSpecificPlayer = function(index)
    if index == 0 then return player end
    if index == 1 then return slot end
end

SurvivorCompanion.ExpeditionPrototype = {
    current = function() return mission end,
    lastDebrief = function() return debrief end,
    pendingDeliveryReports = function() return pendingReports or {} end,
    describeForPlayer = function(viewer)
        assert(viewer == player)
        return view
    end,
}

SurvivorCompanion.ExpeditionIntegration = {
    summary = function(record) return record.summary end,
}
SurvivorCompanion.UI.baseFailureReason = function(reason) return reason end

SCBridge = {
    readExpeditionZoom = function(out)
        if not readerWorks then return false end
        out.min, out.max, out.target = zoom.min, zoom.max, zoom.target
        return true
    end,
    setExpeditionZoomStep = function(step)
        if not setterWorks then return false end
        changes[#changes + 1] = step
        zoom.target = zoom.min + (zoom.max - zoom.min) * (step - 1) / 9
        return true
    end,
}

UIFont = { Small = 1 }
ISLabel = {}
function ISLabel:new(_, _, _, name)
    return setmetatable({ name = name }, { __index = self })
end
function ISLabel:initialise() end
function ISLabel:setName(name) self.name = name end

ISButton = {}
function ISButton:new() return setmetatable({}, { __index = self }) end
function ISButton:initialise() end
ISComboBox = {}
function ISComboBox:new()
    return setmetatable({ options = {} }, { __index = self })
end
function ISComboBox:initialise() end
function ISComboBox:instantiate() end
function ISComboBox:addOptionWithData(label, data)
    self.options[#self.options + 1] = { label = label, data = data }
end

ISSliderPanel = {}
function ISSliderPanel:new(x, y, width, height, target, onChange)
    return setmetatable({ x = x, y = y, width = width,
        height = height, target = target, onChange = onChange },
        { __index = self })
end
function ISSliderPanel:initialise() end
function ISSliderPanel:instantiate() end
function ISSliderPanel:setDoButtons(value) self.doButtons = value end
function ISSliderPanel:setValues(minimum, maximum, step)
    self.minimum, self.maximum, self.step = minimum, maximum, step
end
function ISSliderPanel:setCurrentValue(value, ignoreChange)
    self.currentValue = math.max(self.minimum,
        math.min(self.maximum, math.floor(value + 0.5)))
    if not ignoreChange then
        self.onChange(self.target, self.currentValue, self)
    end
end
