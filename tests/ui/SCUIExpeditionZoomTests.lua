-- SPDX-License-Identifier: MIT
local Planner = SurvivorCompanion.UIExpeditions
local fixture = ExpeditionZoomFixture
assert(Planner ~= nil)

local function newPanel(width)
    local panel = { width = width, children = {} }
    function panel:getWidth() return self.width end
    function panel:addChild(child)
        self.children[#self.children + 1] = child
    end
    return panel
end

local function newDetail()
    local detail = { metrics = { fontHeight = 16, infoLineHeight = 20,
        buttonHeight = 26 }, lines = {} }
    function detail:addSection(_, y, key)
        self.lines[#self.lines + 1] = "section:" .. tostring(key)
        return y + 20
    end
    function detail:addInformationLine(_, y, _, value)
        self.lines[#self.lines + 1] = value
        return y + 20
    end
    return detail
end

local detail = newDetail()
local pendingPanel = newPanel(132)
local pendingSignature = Planner.viewStructureSignature()
Planner.build(detail, pendingPanel)
assert(detail.expeditionZoomSlider == nil,
    "pending slot 1 must not show a usable slider")
assert(detail.lines[#detail.lines] == "UI_SC_Expedition_ViewZoomPending")
assert(detail.lines[#detail.lines - 1] == "UI_SC_Expedition_AwayStatus",
    "a remote expedition keeps its phase private")

fixture.view.leaderVisible = true
fixture.view.visibleMembers = 1
fixture.view.observedPhase = "searching"
local nearbySignature = Planner.viewStructureSignature()
local nearbyDetail = newDetail()
Planner.build(nearbyDetail, newPanel(132))
assert(nearbySignature ~= pendingSignature
    and nearbyDetail.lines[#nearbyDetail.lines - 1]
        == "Leader nearby. Mission phase: searching for supplies.",
    "seeing the leader replaces the misleading away message with observed phase")
fixture.view.leaderVisible = nil
fixture.view.visibleMembers = nil
fixture.view.observedPhase = nil

fixture.join()
fixture.setOwner("base_watch")
local baseWatchPanel = newPanel(132)
Planner.build(detail, baseWatchPanel)
assert(detail.expeditionZoomSlider == nil,
    "a stale mission must not show zoom while Base Watch owns slot 1")
fixture.setOwner("expedition")
local readySignature = Planner.viewStructureSignature()
assert(readySignature ~= pendingSignature,
    "the roster refresh must rebuild the tab when slot 1 joins")
local panel = newPanel(132)
local original = fixture.zoom.target
Planner.build(detail, panel)
local slider = detail.expeditionZoomSlider
assert(slider ~= nil and slider.width == 104 and slider.doButtons == false,
    "slider should be horizontal and fit the narrow detail pane")
assert(slider.minimum == 1 and slider.maximum == 10 and slider.step == 1,
    "there must be exactly ten selectable positions")
assert(slider.currentValue == 6,
    "initial slider position must be nearest to the live zoom")
assert(slider.scZoomLabel.name == "Zoom: 125%"
    and fixture.zoom.target == original and #fixture.changes == 0,
    "opening the tab must retain and display actual camera zoom")

local targets = {}
for step = 1, 10 do
    slider:setCurrentValue(step, false)
    targets[#targets + 1] = fixture.zoom.target
    assert(fixture.changes[#fixture.changes] == step)
end
assert(#fixture.changes == 10 and targets[1] == fixture.zoom.min
    and targets[10] == fixture.zoom.max,
    "all ten endpoints and intermediate zoom choices must reach native bridge")
for step = 2, 10 do
    assert(targets[step] > targets[step - 1],
        "native steps must map to distinct, evenly ordered magnifications")
end
slider:setCurrentValue(10, false)
assert(#fixture.changes == 10,
    "repeated callbacks at the same step must not call the bridge")
assert(slider.scZoomLabel.name == "Zoom: 200%")

fixture.zoom.target = 1.5
assert(Planner.refreshZoom(detail) == true)
assert(slider.scZoomLabel.name == "Zoom: 150%"
    and slider.currentValue == 7,
    "external camera zoom must update the label and slider")

fixture.setSetterWorks(false)
slider:setCurrentValue(8, false)
assert(slider.currentValue == 7 and #fixture.changes == 10,
    "a rejected zoom change must restore the prior slider position")
fixture.setSetterWorks(true)

fixture.setReaderWorks(false)
assert(Planner.viewStructureSignature() == readySignature,
    "structural checks must not repeatedly call the native zoom reader")
assert(Planner.refreshZoom(detail) == false)
fixture.setReaderWorks(true)
local unavailablePanel = newPanel(132)
fixture.setReaderWorks(false)
Planner.build(detail, unavailablePanel)
assert(detail.expeditionZoomSlider == nil,
    "joining before the native zoom buffer is ready should show status")
fixture.setReaderWorks(true)
assert(Planner.refreshZoom(detail) == false,
    "the tab must rebuild as soon as native zoom becomes readable")
fixture.leave()
assert(Planner.viewStructureSignature() == pendingSignature,
    "released slot must return to pending state during a live mission")
fixture.endTrip()
assert(Planner.viewStructureSignature() == "expedition:idle",
    "mission completion must remove the active zoom control")

local latest = { tripId = "recent", items = { { stored = true } },
    members = {}, summary = { requested = 1, collected = 1,
        broughtBack = 1, stored = 1, pending = 0,
        items = { { itemType = "Base.Hammer", finderName = "Alice",
            carrierName = "Alice", stored = true } }, members = {} } }
local older = { tripId = "older", summary = { requested = 1,
    collected = 1, broughtBack = 1, stored = 0, pending = 1,
    items = { { itemType = "Base.Nails", finderName = "Bob",
        carrierName = "Bob", reason = "matching_storage_full" } },
    members = {} } }
fixture.setDebrief({ integration = latest })
fixture.setPendingReports({ { tripId = "recent", summary = latest.summary },
    older })
local reportSignature = Planner.viewStructureSignature()
local reportDetail = newDetail()
Planner.build(reportDetail, newPanel(132))
local counts, earlier = 0, 0
for _, line in ipairs(reportDetail.lines) do
    if line == "UI_SC_Expedition_DeliveryCounts" then counts = counts + 1 end
    if line == "section:UI_SC_Expedition_OlderPendingDeliveries" then
        earlier = earlier + 1
    end
end
assert(reportSignature ~= "expedition:idle" and counts == 2
    and earlier == 1,
    "the latest debrief and earlier unfinished delivery remain visible once")
fixture.startTrip()
local nextTripDetail = newDetail()
Planner.build(nextTripDetail, newPanel(132))
local previousShown = false
for _, line in ipairs(nextTripDetail.lines) do
    if line == "section:UI_SC_Expedition_OlderPendingDeliveries" then
        previousShown = true
    end
end
assert(previousShown and Planner.viewStructureSignature() ~= reportSignature,
    "a subsequent expedition keeps earlier pending supplies in the tab")

print("SCUI expedition zoom tests passed")
