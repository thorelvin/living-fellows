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
fixture.view.observedPhase = "phase_without_phrase"
local untranslatedDetail = newDetail()
Planner.build(untranslatedDetail, newPanel(132))
assert(untranslatedDetail.lines[#untranslatedDetail.lines - 1]
        == "UI_SC_Expedition_LeaderNearby",
    "a phase without its own phrase shows the plain nearby line, not a raw key")
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

-- Registry records have identity fields, not necessarily a top-level name.
-- Exercise the actual review and launch callbacks, including legacy reports
-- whose saved name strings were internal companion ids.
fixture.endTrip()
local id = "sc-1.792185651862E9-2-990140"
local record = { id = id, actor = { name = "Actor Name" },
    identity = { forename = "  Tess ", surname = "Nolan " } }
SurvivorCompanion.Registry = { byId = function(value)
    return value == id and record or nil
end }
SurvivorCompanion.Commands = { describe = function()
    return { recruited = true, group = "alpha", alive = true, available = true }
end }
SurvivorCompanion.GameplayUtil = { nameOf = function(actor) return actor.name end }
local originalText = SurvivorCompanion.UI.text
SurvivorCompanion.UI.text = function(key, ...)
    local values = { ... }
    if key == "UI_SC_Expedition_SquadMember" then return "A squad member" end
    for index, value in ipairs(values) do values[index] = tostring(value) end
    return key .. (#values > 0 and (":" .. table.concat(values, "|")) or "")
end
SurvivorCompanion.UI.fitText = function(_, value) return value end
SCSplitScreenProbe = {}
local expedition = SurvivorCompanion.ExpeditionPrototype
local gearReason, gearMember = "fishing_rod_missing", id
expedition.fishingGearStatus = function() return false, gearReason, gearMember end
expedition.startAtPlace = function() return false end
expedition.startAtFishingBank = function() return false, gearReason, gearMember end
expedition.placeCandidates = function() return {} end
expedition.fishingBankCandidates = function() return {} end
local gearDetail = newDetail()
gearDetail.root = { roster = { items = { { item = { id = id, actor = record.actor,
    name = id, group = "alpha", recruited = true } } } } }
gearDetail.expeditionDraft = { kind = "fish", group = "alpha", leaderId = id,
    placeId = "bank", places = { { id = "bank", label = "River bank" } },
    placesLoaded = true, placesTotal = 1, travelMode = "road" }
function gearDetail:rebuild() end
Planner.onButton(gearDetail, { scExpeditionAction = "launch" })
assert(gearDetail.feedback == "UI_SC_Expedition_Failed:UI_SC_Expedition_FishingRodMissing:Tess Nolan",
    "a missing-rod footer resolves the registry identity instead of showing its id")
for reason, key in pairs({
    local_view_restore_bridge_unavailable = "UI_SC_View_BridgeUpdateRequired",
    local_view_restore_event_unavailable = "UI_SC_View_RenderUnavailable",
}) do
    gearReason = reason
    Planner.onButton(gearDetail, { scExpeditionAction = "launch" })
    assert(gearDetail.feedback == "UI_SC_Expedition_Failed:" .. key
        and not gearDetail.feedbackSuccess,
        "expedition capability failures explain the missing update or render event")
end
record.identity = nil
record.name = "Mara Ellis"
gearReason = "fishing_bait_missing"
Planner.onButton(gearDetail, { scExpeditionAction = "launch" })
assert(gearDetail.feedback == "UI_SC_Expedition_Failed:UI_SC_Expedition_FishingBaitMissing:Mara Ellis",
    "a record without identity fields uses its saved human name")
record.name = id
Planner.onButton(gearDetail, { scExpeditionAction = "launch" })
assert(gearDetail.feedback == "UI_SC_Expedition_Failed:UI_SC_Expedition_FishingBaitMissing:Actor Name",
    "an invalid saved name falls back to the actor's own name")
record.actor.name = id
Planner.onButton(gearDetail, { scExpeditionAction = "launch" })
assert(gearDetail.feedback == "UI_SC_Expedition_Failed:UI_SC_Expedition_FishingBaitMissing:A squad member",
    "a missing human identity uses a readable fallback and never an internal id")
record.identity = { forename = "Tess", surname = "Nolan" }
gearReason, gearMember = "fishing_rod_missing", record
Planner.onButton(gearDetail, { scExpeditionAction = "launch" })
assert(gearDetail.feedback == "UI_SC_Expedition_Failed:UI_SC_Expedition_FishingRodMissing:Tess Nolan",
    "the gear status may also return the affected member record")
gearMember = id
Planner.onButton(gearDetail, { scExpeditionAction = "launch" })
assert(string.find(gearDetail.feedback, "Tess Nolan", 1, true)
        and not string.find(gearDetail.feedback, id, 1, true),
    "launch rejection resolves the same name before wrapping the footer")

fixture.setDebrief(nil)
fixture.setPendingReports({})
local namingPanel = newPanel(300)
Planner.build(gearDetail, namingPanel)
local leaderOption
for _, child in ipairs(namingPanel.children) do
    if child.scField == "leaderId" then leaderOption = child.options[1] end
end
assert(leaderOption and leaderOption.label == "Tess Nolan"
        and leaderOption.data.value == id,
    "leader selectors show a real name while preserving the exact internal selection id")
expedition.fishingGearStatus = function()
    error("review must allow automatic preparation instead of requiring carried gear")
end
expedition.previewAtFishingBank = function() return { mode = "straight", distance = 10 } end
Planner.onButton(gearDetail, { scExpeditionAction = "review" })
assert(gearDetail.expeditionDraft.review, "fishing review never refuses missing carried gear")
gearDetail.lines = {}
Planner.build(gearDetail, newPanel(300))
assert(string.find(table.concat(gearDetail.lines, "\n"),
    "UI_SC_Expedition_FishingPreparationPlan", 1, true),
    "fishing review explains automatic collection from shared camp storage")
local preparationVisible = true
expedition.startAtFishingBank = function()
    fixture.startTrip()
    local trip = expedition.current()
    trip.leader.id = id
    trip.scout = { fishingPreparation = { reason = "fishing_preparing_rod" } }
    fixture.view.preparation = preparationVisible and "fishing_preparing_rod" or nil
    fixture.view.preparationMemberId = preparationVisible and id or nil
    return true
end
Planner.onButton(gearDetail, { scExpeditionAction = "launch" })
assert(gearDetail.feedbackSuccess and gearDetail.feedback
        == "UI_SC_Expedition_FishingPreparingRod:Tess Nolan",
    "accepted fishing preparation must not claim the squad has already departed")
fixture.endTrip()
preparationVisible = false
Planner.onButton(gearDetail, { scExpeditionAction = "launch" })
assert(gearDetail.feedbackSuccess and gearDetail.feedback
        == "UI_SC_Expedition_FishingPreparingRod:Tess Nolan",
    "launch feedback uses the known accepted plan even when the leader is unseen")
local unseen = newDetail()
Planner.build(unseen, newPanel(300))
local unseenText = table.concat(unseen.lines, "\n")
assert(string.find(unseenText, "UI_SC_Expedition_AwayStatus", 1, true)
        and not string.find(unseenText, "UI_SC_Expedition_FishingPreparingRod", 1, true),
    "the active tab still keeps an unobserved leader's preparation private")
fixture.view.preparationMemberId = id
local previousPreparationSignature
for _, phase in ipairs({
    { "fishing_preparing_rod", "UI_SC_Expedition_FishingPreparingRod" },
    { "fishing_preparing_bait", "UI_SC_Expedition_FishingPreparingBait" },
    { "fishing_rod_missing", "UI_SC_Expedition_FishingRodWaiting" },
    { "fishing_bait_missing", "UI_SC_Expedition_FishingBaitWaiting" },
}) do
    fixture.view.preparation = phase[1]
    local signature = Planner.viewStructureSignature()
    assert(signature ~= previousPreparationSignature, "preparation changes refresh the tab")
    previousPreparationSignature = signature
    local preparation = newDetail()
    Planner.build(preparation, newPanel(300))
    local text = table.concat(preparation.lines, "\n")
    assert(string.find(text, phase[2] .. ":Tess Nolan", 1, true)
            and not string.find(text, id, 1, true)
            and not string.find(text, "UI_SC_Expedition_AwayStatus", 1, true),
        "active gear collection or waiting has a named status rather than an away message")
end
fixture.view.preparation, fixture.view.preparationMemberId = nil, nil
assert(Planner.viewStructureSignature() ~= previousPreparationSignature,
    "finishing preparation restores ordinary expedition status")
fixture.view.leaderName = id
local activeNames = newDetail()
Planner.build(activeNames, newPanel(300))
assert(string.find(table.concat(activeNames.lines, "\n"), "Tess Nolan", 1, true)
        and not string.find(table.concat(activeNames.lines, "\n"), id, 1, true),
    "active expedition summaries resolve old leader-name ids")
fixture.endTrip()
fixture.setPendingReports({ { tripId = "legacy-names", summary = {
    requested = 1, collected = 1, broughtBack = 1, stored = 0, pending = 1,
    items = { { itemType = "Base.Hammer", finderName = id, carrierName = id } },
    members = { { id = id, name = id, shortages = { food = 1 } } },
} } })
local deliveryNames = newDetail()
deliveryNames.expeditionDraft={kind="scout",group="alpha",placesLoaded=true,places={},showReports=true}
Planner.build(deliveryNames, newPanel(300))
local deliveryText = table.concat(deliveryNames.lines, "\n")
assert(string.find(deliveryText, "Tess Nolan", 1, true)
        and not string.find(deliveryText, id, 1, true),
    "legacy finder, carrier and restock reports never expose companion ids")
fixture.setPendingReports({})
local woodDetail = newDetail()
woodDetail.root = gearDetail.root
woodDetail.rebuild = function() end
woodDetail.expeditionDraft = { kind = "wood", group = "alpha", leaderId = id,
    travelMode = "road", restockBaseDuty = false }
local previewCalls, launchOptions = 0, nil
expedition.previewWoodCollection = function(records, options)
    assert(records[1] == record and options.request.quantity == 12,
        "wood uses the actual crew and defaults to twelve logs")
    previewCalls = previewCalls + 1
    if previewCalls == 1 then return nil, "forest_scan_pending" end
    return { mode = "road", distance = 90,
        site = { id = "forest-test", label = "Woodland northeast of camp" } }
end
expedition.placeCandidates = function() error("wood finds woodland automatically") end
expedition.startWoodCollection = function(records, options)
    assert(records[1] == record)
    launchOptions = options
    return true
end
local woodPanel = newPanel(400)
Planner.build(woodDetail, woodPanel)
assert(woodDetail.expeditionDraft.previewError == "forest_scan_pending",
    "a bounded woodland scan stays pending")
local quantityCombo
for _, child in ipairs(woodPanel.children) do
    if child.scField == "woodQuantity" then quantityCombo = child end
    assert(child.scField ~= "quantity" and child.scField ~= "placeId",
        "wood has its own quantity and no manual destination selector")
end
assert(quantityCombo and #quantityCombo.options == 7,
    "wood offers six log counts and full load")
assert(quantityCombo.options[quantityCombo.selected].data.value == 12,
    "the displayed default matches the twelve-log launch request")
local choices = { 1, 2, 4, 8, 12, 24, "full" }
for index, expected in ipairs(choices) do
    assert(quantityCombo.options[index].data.value == expected)
end
assert(Planner.refreshForestPreview(woodDetail)
        and woodDetail.expeditionDraft.forestSite.id == "forest-test",
    "later bounded slices provide a readable automatic forest destination")
Planner.onButton(woodDetail, { scExpeditionAction = "review" })
woodDetail.lines = {}
Planner.build(woodDetail, newPanel(400))
local woodReview = table.concat(woodDetail.lines, "\n")
assert(string.find(woodReview, "UI_SC_Expedition_WoodCountPlan:12", 1, true)
        and string.find(woodReview, "UI_SC_Expedition_WoodEquipmentPlan", 1, true),
    "review explains the quantity and automatic axe/storage plan")
Planner.onButton(woodDetail, { scExpeditionAction = "launch" })
assert(launchOptions.request.mode == "count" and launchOptions.request.quantity == 12
        and launchOptions.restockBaseDuty == false,
    "count launch preserves the independent restock setting")
woodDetail.expeditionDraft.woodQuantity = "full"
Planner.onButton(woodDetail, { scExpeditionAction = "launch" })
assert(launchOptions.request.mode == "full" and launchOptions.request.quantity == nil,
    "full load uses its explicit request mode")
fixture.startTrip()
expedition.current().scout = { kind = "wood", wood = { preparation = true,
    preparationReason = "wood_axe_missing" } }
fixture.view.kind, fixture.view.preparation = "wood", "wood_axe_missing"
fixture.view.woodProgress = { collected = 2, carried = 1, stored = 0 }
local woodSignature = Planner.viewStructureSignature()
fixture.view.woodProgress.carried = 2
assert(Planner.viewStructureSignature() ~= woodSignature,
    "physical cargo changes refresh the wood display even in the same phase")
local preparingWood = newDetail()
Planner.build(preparingWood, newPanel(400))
assert(string.find(table.concat(preparingWood.lines, "\n"),
        "UI_SC_Expedition_WoodAxeWaiting", 1, true),
    "wood preparation explains missing axes without claiming departure")
fixture.endTrip()
fixture.view.kind, fixture.view.preparation, fixture.view.woodProgress = nil, nil, nil
fixture.setPendingReports({ { tripId = "wood-delivery", summary = {
    kind = "wood", version = 2, tripId = "wood-delivery", requested = 12,
    collected = 3, carried = 2, returned = 3, stored = 1, pending = 2,
    deliveryPending = true, items = {}, members = {},
} } })
local retryTrip
expedition.retryDelivery = function(tripId)
    retryTrip = tripId
    return true, "delivery_retry_queued"
end
local delivery = newDetail()
delivery.root, delivery.rebuild = gearDetail.root, function() end
delivery.expeditionDraft = { kind = "scout", group = "alpha", placesLoaded = true, places = {}, showReports = true }
local deliveryPanel = newPanel(400)
Planner.build(delivery, deliveryPanel)
assert(string.find(table.concat(delivery.lines, "\n"),
        "UI_SC_Expedition_WoodDeliveryCounts:3|2|1|2", 1, true),
    "the delivery report separates collected, carried, stored and pending")
for _, child in ipairs(deliveryPanel.children) do
    if child.scExpeditionAction == "retry_delivery" then Planner.onButton(delivery, child) end
end
assert(retryTrip == "wood-delivery" and delivery.feedbackSuccess,
    "manual delivery retry retains the exact trip identity")
fixture.setDebrief({ kind = "wood", endReason = "forest_no_mature_trees",
    carFailure = { reason = "route_blocked" } })
fixture.setPendingReports({ { tripId = "wood-cargo", summary = {
    kind = "wood", version = 2, tripId = "wood-cargo", requested = 2,
    collected = 1, carried = 0, stored = 0, pending = 1,
    items = { { itemType = "Base.Log", finderName = "Tess Nolan",
        carrierName = "Tess Nolan", reason = "cargo_pending" } }, members = {},
} } })
delivery.lines = {}
Planner.build(delivery, newPanel(400))
local partialWoodText = table.concat(delivery.lines, "\n")
assert(string.find(partialWoodText, "UI_SC_Expedition_WoodForestEmpty", 1, true)
        and string.find(partialWoodText, "UI_SC_Expedition_WoodCargoPending", 1, true)
        and string.find(partialWoodText, "UI_SC_Expedition_WoodLog", 1, true)
        and string.find(partialWoodText, "UI_SC_Expedition_CarFailure", 1, true)
        and not string.find(partialWoodText, "Base.Log", 1, true),
    "partial wood debriefs explain empty woodland and pending cargo with readable log names")
SurvivorCompanion.UI.text = originalText
print("SCUI expedition zoom, wood controls and companion-name tests passed")
