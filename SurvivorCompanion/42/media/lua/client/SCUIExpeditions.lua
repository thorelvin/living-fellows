-- SPDX-License-Identifier: MIT
-- Private test-build expedition planner. Draft changes do not issue commands.
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.UIExpeditions = SC.UIExpeditions or {}
local Planner = SC.UIExpeditions

local GROUPS = {
    { value = "alpha", key = "UI_SC_Select_GroupAlpha" },
    { value = "bravo", key = "UI_SC_Select_GroupBravo" },
    { value = "charlie", key = "UI_SC_Select_GroupCharlie" },
}
local STYLES = {
    { value = "stealth", key = "UI_SC_Doctrine_Stealth" },
    { value = "close_defense", key = "UI_SC_Doctrine_CloseDefense" },
    { value = "weapons_free", key = "UI_SC_Expedition_Aggressive" },
}
local TRAVEL = {
    { value = "road", key = "UI_SC_Expedition_RoadTravel" },
    { value = "straight", key = "UI_SC_Expedition_StraightTravel" },
    { value = "drive", key = "UI_SC_Expedition_DriveCar" },
}
local TIMES = {
    { value = 1, key = "UI_SC_Expedition_OneHour" },
    { value = 2, key = "UI_SC_Expedition_TwoHours" },
    { value = 4, key = "UI_SC_Expedition_FourHours" },
    { value = 8, key = "UI_SC_Expedition_EightHours" },
}
local CATEGORIES = {
    { value = "useful", key = "UI_SC_Expedition_EverythingUseful" },
    { value = "food", key = "UI_SC_Expedition_Food" },
    { value = "water", key = "UI_SC_Expedition_Water" },
    { value = "medicine", key = "UI_SC_Expedition_Medicine" },
    { value = "ammunition", key = "UI_SC_Expedition_Ammunition" },
    { value = "tools", key = "UI_SC_Expedition_Tools" },
    { value = "clothing", key = "UI_SC_Expedition_Clothing" },
}
local QUANTITIES = {
    { value = 1, label = "1" }, { value = 2, label = "2" },
    { value = 4, label = "4" }, { value = 8, label = "8" },
}
-- A building usually sits well within this of its street; name longer
-- off-road stretches in the review.
local OFF_ROAD_NOTE = 25
local ZOOM_STEPS = 10

local function tr(key, ...)
    return SC.UI.text(key, ...)
end

-- getText returns the key itself for a missing entry. A phase without its own
-- phrase falls back to the plain "leader nearby" line, never a raw key.
local function observedPhaseText(phase)
    local key = "UI_SC_Expedition_Phase_" .. tostring(phase)
    local value = tr(key)
    if type(value) ~= "string" or value == "" or value == key then return nil end
    return value
end

local function feedback(detail, message, success)
    detail.feedback = message
    detail.feedbackSuccess = success == true
    local now = SC.GameplayUtil and SC.GameplayUtil.nowMs
        and SC.GameplayUtil.nowMs() or 0
    detail.feedbackUntil = now + 6000
    detail.feedbackWrapKey, detail.feedbackWrapLines = nil, nil
end

local function joinedExpeditionView(mission)
    return mission ~= nil and mission.leader ~= nil
        and mission.leader.actor ~= nil
        and (SC.ViewSession == nil
            or type(SC.ViewSession.owner) ~= "function"
            or SC.ViewSession.owner() == "expedition")
        and type(getSpecificPlayer) == "function"
        and getSpecificPlayer(1) == mission.leader.actor
end

local function readExpeditionZoom(mission)
    if not joinedExpeditionView(mission) or SCBridge == nil
        or SCBridge.readExpeditionZoom == nil then
        return nil
    end
    local values = {}
    local called, ready = pcall(SCBridge.readExpeditionZoom, values)
    if not called or ready ~= true then return nil end
    local minimum = tonumber(values.min)
    local maximum = tonumber(values.max)
    local target = tonumber(values.target)
    if minimum == nil or maximum == nil or target == nil
        or minimum ~= minimum or maximum ~= maximum or target ~= target
        or minimum >= maximum then return nil end
    return { min = minimum, max = maximum, target = target }
end

local function zoomStep(values)
    local fraction = (values.target - values.min) / (values.max - values.min)
    return math.max(1, math.min(ZOOM_STEPS,
        math.floor(fraction * (ZOOM_STEPS - 1) + 0.5) + 1))
end

local function zoomPercent(value)
    return math.floor(value * 100 + 0.5)
end

local function setZoomLabel(slider, target)
    local label = slider and slider.scZoomLabel
    if label == nil then return end
    local name = tr("UI_SC_Expedition_ViewZoomValue", zoomPercent(target))
    if type(label.setName) == "function" then label:setName(name)
    else label.name = name end
end

local function deliverySignature(expedition)
    local parts, seen = {}, {}
    local debrief = expedition and expedition.lastDebrief
        and expedition.lastDebrief() or nil
    local latest = debrief and debrief.integration
    local function append(record)
        if not record or seen[record.tripId] then return end
        seen[record.tripId] = true
        parts[#parts + 1] = record.tripId
        for _, row in ipairs(record.items or {}) do
            parts[#parts + 1] = row.stored and "stored"
                or row.reason or "pending"
        end
        for _, member in ipairs(record.members or {}) do
            parts[#parts + 1] = member.dutyReason or "restocking"
        end
    end
    append(latest)
    for _, report in ipairs(expedition and expedition.pendingDeliveryReports
            and expedition.pendingDeliveryReports() or {}) do
        if report.summary and not seen[report.tripId] then
            parts[#parts + 1] = report.tripId
            for _, row in ipairs(report.summary.items) do
                parts[#parts + 1] = row.stored and "stored"
                    or row.reason or "pending"
            end
        end
    end
    return table.concat(parts, ":")
end

function Planner.viewStructureSignature()
    local expedition = SC.ExpeditionPrototype
    local mission = expedition and type(expedition.current) == "function"
        and expedition.current() or nil
    if mission == nil then
        local signature = deliverySignature(expedition)
        return signature == "" and "expedition:idle"
            or "expedition:idle:" .. signature
    end
    local viewer = type(getSpecificPlayer) == "function"
        and getSpecificPlayer(0) or nil
    local view = expedition and type(expedition.describeForPlayer) == "function"
        and expedition.describeForPlayer(viewer) or nil
    local request = view and view.helpRequest or nil
    return table.concat({ "expedition", tostring(mission.radioSession or mission),
        joinedExpeditionView(mission) and "joined" or "pending",
        tostring(view and view.plannedSite or ""),
        tostring(view and view.observedPhase or ""),
        tostring(view and view.visibleMembers or 0),
        tostring(view and view.supplyProgress
            and view.supplyProgress.collected or ""),
        tostring(view and view.supplyProgress
            and view.supplyProgress.at or ""),
        tostring(view and view.delivery and view.delivery.broughtBack or ""),
        tostring(view and view.delivery and view.delivery.stored or ""),
        tostring(view and view.delivery and view.delivery.pending or ""),
        deliverySignature(expedition),
        tostring(request and request.mode or ""),
        tostring(request and request.shelter or ""),
        tostring(request and request.x or ""),
        tostring(request and request.y or ""),
    }, ":")
end

function Planner.refreshZoom(detail)
    local slider = detail and detail.expeditionZoomSlider
    local expedition = SC.ExpeditionPrototype
    local mission = expedition and type(expedition.current) == "function"
        and expedition.current() or nil
    if slider == nil then
        -- The native view may join before its zoom framebuffer is ready.
        -- Rebuild once it becomes readable, without polling it for an idle tab.
        return not (joinedExpeditionView(mission)
            and readExpeditionZoom(mission) ~= nil)
    end
    local values = readExpeditionZoom(mission)
    if values == nil then return false end
    setZoomLabel(slider, values.target)
    if slider.dragInside ~= true then
        local step = zoomStep(values)
        slider.scZoomStep = step
        slider:setCurrentValue(step, true)
    end
    return true
end

function Planner.onZoomSliderChange(detail, value, slider)
    if slider == nil or slider.scZoomStep == nil then return end
    local step = math.max(1, math.min(ZOOM_STEPS,
        math.floor((tonumber(value) or slider.scZoomStep) + 0.5)))
    if step == slider.scZoomStep then return end
    local mission = SC.ExpeditionPrototype and SC.ExpeditionPrototype.current
        and SC.ExpeditionPrototype.current() or nil
    if not joinedExpeditionView(mission) or SCBridge == nil
        or SCBridge.setExpeditionZoomStep == nil then
        slider:setCurrentValue(slider.scZoomStep, true)
        return
    end
    local called, changed = pcall(SCBridge.setExpeditionZoomStep, step)
    if not called or changed ~= true then
        slider:setCurrentValue(slider.scZoomStep, true)
        feedback(detail, tr("UI_SC_Expedition_ViewZoomUnavailable"), false)
        return
    end
    slider.scZoomStep = step
    local values = readExpeditionZoom(mission)
    if values then setZoomLabel(slider, values.target)
    else
        local target = slider.scZoomMin + (slider.scZoomMax
            - slider.scZoomMin) * (step - 1) / (ZOOM_STEPS - 1)
        setZoomLabel(slider, target)
    end
end

local function addZoomSlider(detail, panel, y, values)
    local metrics = detail.metrics or SC.UI.layoutMetrics()
    y = detail:addSection(panel, y + 8, "UI_SC_Expedition_ViewZoom")
    local label = ISLabel:new(8, y, metrics.fontHeight,
        tr("UI_SC_Expedition_ViewZoomValue", zoomPercent(values.target)),
        0.88, 0.89, 0.83, 1, UIFont.Small, true)
    label:initialise()
    panel:addChild(label)
    y = y + metrics.infoLineHeight
    local width = math.max(36, panel:getWidth() - 28)
    local slider = ISSliderPanel:new(8, y, width,
        metrics.buttonHeight, detail, Planner.onZoomSliderChange)
    slider:initialise()
    slider:instantiate()
    slider:setDoButtons(false)
    slider:setValues(1, ZOOM_STEPS, 1, 1, true)
    slider.scZoomStep = zoomStep(values)
    slider.scExpeditionZoomSlider = true
    slider.scZoomMin, slider.scZoomMax = values.min, values.max
    slider.scZoomLabel = label
    slider:setCurrentValue(slider.scZoomStep, true)
    slider.tooltip = tr("UI_SC_Expedition_ViewZoomTip")
    panel:addChild(slider)
    detail.expeditionZoomSlider = slider
    return y + metrics.buttonHeight + 7
end

local function squadRows(detail, group)
    local result = {}
    local items = detail.root and detail.root.roster
        and detail.root.roster.items or {}
    for _, item in ipairs(items) do
        local row = item.item
        if row and row.group == group and row.recruited == true
            and row.alive ~= false and row.available ~= false
            and row.id and row.actor then
            result[#result + 1] = row
        end
    end
    return result
end

local function selectedPlace(draft)
    for _, place in ipairs(draft.places or {}) do
        if place.id == draft.placeId then return place end
    end
    return nil
end

local function optionLabel(option)
    return option.label or tr(option.key)
end

local function onSelect(detail, combo)
    local option = combo:getOptionData(combo.selected)
    if not option then return end
    local draft = detail.expeditionDraft
    draft[combo.scField] = option.value
    draft.preview, draft.previewError = nil, nil
    if combo.scField == "group" then
        draft.leaderId = nil
        local preferred = SC.ExpeditionCar and
            SC.ExpeditionCar.preference(draft.group) or nil
        draft.parkingZoneId = preferred and preferred.zoneId or nil
        draft.vehicleSqlId = preferred and preferred.sqlId or nil
    end
    if combo.scField == "parkingZoneId" then draft.vehicleSqlId = nil end
    if (combo.scField == "parkingZoneId"
        or combo.scField == "vehicleSqlId") and SC.ExpeditionCar then
        SC.ExpeditionCar.setPreference(draft.group, draft.parkingZoneId,
            draft.vehicleSqlId)
    end
    if combo.scField == "group" or combo.scField == "leaderId"
        or combo.scField == "kind" then
        draft.placesLoaded, draft.placeId = false, nil
        draft.placePage = 1
    end
    draft.review = false
    detail:rebuild(true)
end

local function addSelector(detail, panel, y, titleKey, field, options)
    local metrics = detail.metrics or SC.UI.layoutMetrics()
    y = detail:addInformationLine(panel, y, "UI_SC_Info_Message", tr(titleKey))
    local width = math.max(100, panel:getWidth() - 28)
    local combo = ISComboBox:new(8, y, width,
        metrics.buttonHeight, detail, onSelect)
    combo:initialise()
    combo:instantiate()
    combo.scField = field
    for index, option in ipairs(options) do
        local label = optionLabel(option)
        combo:addOptionWithData(SC.UI.fitText(UIFont.Small, label,
            math.max(40, width - 28)), option, label)
        if option.value == detail.expeditionDraft[field] then
            combo.selected = index
        end
    end
    panel:addChild(combo)
    return y + metrics.buttonHeight + 7
end

local function addButton(detail, panel, y, key, action)
    local metrics = detail.metrics or SC.UI.layoutMetrics()
    local width = math.max(100, panel:getWidth() - 28)
    local title = tr(key)
    local button = ISButton:new(8, y, width,
        metrics.buttonHeight, SC.UI.fitText(UIFont.Small, title,
            math.max(40, width - 16)), detail, Planner.onButton)
    button:initialise()
    button.backgroundColor = { r = 0.12, g = 0.13, b = 0.12, a = 0.78 }
    button.scExpeditionAction = action
    button.tooltip = title
    panel:addChild(button)
    return y + metrics.buttonHeight + 7
end

local function currentTeam(detail)
    local draft = detail.expeditionDraft
    local player = type(getSpecificPlayer) == "function"
        and getSpecificPlayer(0) or nil
    local rows = squadRows(detail, draft.group)
    if #rows < 1 then return nil, "squad_empty" end
    if #rows > 4 then return nil, "squad_too_large" end
    local records = {}
    local leader
    for _, row in ipairs(rows) do
        local record = SC.Registry and SC.Registry.byId(row.id)
        local state = SC.Commands and SC.Commands.describe(row.id, player)
        if not record or not record.actor or not state
            or state.recruited ~= true or state.group ~= draft.group
            or state.alive == false or state.available == false then
            return nil, "squad_changed"
        end
        if row.id == draft.leaderId then leader = record
        else records[#records + 1] = record end
    end
    if not leader then return nil, "leader_unavailable" end
    table.insert(records, 1, leader)
    return records
end

local function gearMessage(reason, name)
    if reason == "fishing_rod_missing" then
        return tr("UI_SC_Expedition_FishingRodMissing", name or "?")
    end
    if reason == "fishing_bait_missing" then
        return tr("UI_SC_Expedition_FishingBaitMissing", name or "?")
    end
    return reason
end

local function dispatch(detail)
    local draft = detail.expeditionDraft
    if not selectedPlace(draft) then return false, "destination_changed" end
    local expedition = SC.ExpeditionPrototype
    if not expedition or type(expedition.startAtPlace) ~= "function"
        or SCSplitScreenProbe == nil then
        return false, "local_view_unavailable"
    end
    if expedition.current() then return false, "expedition_already_active" end
    local records, reason = currentTeam(detail)
    if not records then return false, reason end
    local options = { turnHomeAfterHours = draft.hours,
        doctrine = draft.style, travelMode = draft.travelMode,
        restockBaseDuty = draft.restockBaseDuty == true,
        parkingZoneId = draft.parkingZoneId,
        vehicleSqlId = draft.vehicleSqlId }
    if draft.kind == "search" or draft.kind == "fish" then
        options.request = { category = draft.kind == "fish" and "fish"
                or draft.category,
            quantity = draft.quantity }
    end
    local ok, accepted, result, memberName
    if draft.kind == "fish" then
        ok, accepted, result, memberName = pcall(expedition.startAtFishingBank,
            records, draft.placeId, options)
    else
        ok, accepted, result = pcall(expedition.startAtPlace, records,
            draft.placeId, draft.kind, options)
    end
    if not ok or accepted ~= true then
        return false, ok and gearMessage(result, memberName)
            or tostring(accepted)
    end
    return true
end

function Planner.onButton(detail, button)
    local draft = detail.expeditionDraft
    local action = button.scExpeditionAction
    if action == "refresh_cars" then
        draft.review = false
    elseif action == "refresh" or action == "next_places"
        or action == "previous_places" then
        if action == "next_places" then
            draft.placePage = math.min(128, (draft.placePage or 1) + 1)
        elseif action == "previous_places" then
            draft.placePage = math.max(1, (draft.placePage or 1) - 1)
        end
        local candidates = draft.kind == "fish"
            and SC.ExpeditionPrototype.fishingBankCandidates
            or SC.ExpeditionPrototype.placeCandidates
        -- Paging reuses the last shoreline scan; only Refresh asks for a new one.
        local places, reason, total = candidates(
            draft.leaderId, draft.placePage or 1, action == "refresh")
        if places and #places == 0 and (draft.placePage or 1) > 1 then
            draft.placePage = draft.placePage - 1
            places, reason, total = candidates(
                draft.leaderId, draft.placePage)
        end
        draft.places = places or {}
        draft.placesTotal = total or 0
        draft.placeError = places and nil or reason
        if not selectedPlace(draft) then draft.placeId = nil end
        draft.review = false
    elseif action == "review" then
        local team, reason = currentTeam(detail)
        if not team or not selectedPlace(draft) then
            local message = not team and tr("UI_SC_Expedition_Failed", reason)
                or draft.kind == "fish" and tr((draft.placesTotal or 0) == 0
                    and "UI_SC_Expedition_NoFishingBanks"
                    or "UI_SC_Expedition_SelectBankFirst")
                or tr("UI_SC_Expedition_Failed", "destination_required")
            feedback(detail, message, false)
            detail:rebuild(true)
            return
        end
        if draft.kind == "fish" then
            local ready, gearReason, memberName =
                SC.ExpeditionPrototype.fishingGearStatus(team)
            if not ready then
                feedback(detail, gearMessage(gearReason, memberName), false)
                detail:rebuild(true)
                return
            end
        end
        if draft.travelMode == "drive" then
            draft.preview, draft.previewError =
                SC.ExpeditionPrototype.previewDrive(team,
                    selectedPlace(draft), draft.kind == "fish",
                    draft.parkingZoneId, draft.vehicleSqlId)
        else
            local preview = draft.kind == "fish"
                and SC.ExpeditionPrototype.previewAtFishingBank
                or SC.ExpeditionPrototype.previewAtPlace
            draft.preview, draft.previewError = preview(
                team[1], selectedPlace(draft), draft.travelMode)
        end
        draft.review = true
    elseif action == "edit" then
        draft.review = false
    elseif action == "launch" then
        local ok, reason = dispatch(detail)
        feedback(detail, ok and tr("UI_SC_Expedition_Departed")
            or tr("UI_SC_Expedition_Failed", reason), ok)
        if ok then draft.review = false end
    end
    detail:rebuild(true)
end

local function addDeliveryItems(detail, panel, y, report)
    y = detail:addInformationLine(panel, y, "UI_SC_Info_Message",
        tr("UI_SC_Expedition_DeliveryCounts", report.requested,
            report.collected, report.broughtBack,
            report.stored, report.pending))
    for _, row in ipairs(report.items) do
        y = detail:addInformationLine(panel, y,
            "UI_SC_Info_Message", tr("UI_SC_Expedition_DeliveryItem",
                row.itemType, row.finderName,
                row.carrierKind == "trunk"
                    and (row.carrierName == "Car trunk"
                        and tr("UI_SC_Expedition_TrunkOnly")
                        or tr("UI_SC_Expedition_TrunkCarrier",
                            row.carrierName or "?"))
                    or row.carrierName or "?",
                row.stored and tr("UI_SC_Expedition_Stored")
                    or row.reason and SC.UI.baseFailureReason(row.reason)
                    or tr("UI_SC_Expedition_Pending")))
    end
    for _, member in ipairs(report.members) do
        for category, amount in pairs(member.shortages) do
            y = detail:addInformationLine(panel, y,
                "UI_SC_Info_Message", tr(
                    "UI_SC_Expedition_RestockShortage",
                    member.name, category, amount))
        end
    end
    return y
end

local function addReturnReports(detail, panel, y, expedition)
    local debrief = expedition and expedition.lastDebrief
        and expedition.lastDebrief() or nil
    local latest = debrief and debrief.integration
    if latest and SC.ExpeditionIntegration then
        local summary = SC.ExpeditionIntegration.summary(latest)
        if summary then
            y = detail:addSection(panel, y + 4,
                "UI_SC_Expedition_Debrief")
            y = addDeliveryItems(detail, panel, y, summary)
        end
    end
    if debrief and debrief.abandonedCarAt then
        y = detail:addInformationLine(panel, y, "UI_SC_Info_Message",
            tr("UI_SC_Expedition_CarAbandoned",
                math.floor(debrief.abandonedCarAt.x),
                math.floor(debrief.abandonedCarAt.y)))
    end
    local older
    for _, report in ipairs(expedition and expedition.pendingDeliveryReports
            and expedition.pendingDeliveryReports() or {}) do
        if report.summary and (not latest
            or report.tripId ~= latest.tripId) then
            if not older then
                y = detail:addSection(panel, y + 4,
                    "UI_SC_Expedition_OlderPendingDeliveries")
                older = true
            end
            y = addDeliveryItems(detail, panel, y, report.summary)
        end
    end
    return y
end

function Planner.build(detail, panel)
    detail.expeditionZoomSlider = nil
    local draft = detail.expeditionDraft
    if not draft then
        draft = { kind = "scout", style = "stealth", hours = 2,
            travelMode = "road",
            restockBaseDuty = false,
            category = "food", quantity = 4, places = {}, placePage = 1 }
        detail.expeditionDraft = draft
        local row = detail.root and detail.root.selectedRow
        draft.group = row and row.group or "alpha"
        if draft.group ~= "alpha" and draft.group ~= "bravo"
            and draft.group ~= "charlie" then draft.group = "alpha" end
        local preferred = SC.ExpeditionCar and
            SC.ExpeditionCar.preference(draft.group) or nil
        draft.parkingZoneId = preferred and preferred.zoneId or nil
        draft.vehicleSqlId = preferred and preferred.sqlId or nil
    end
    local y = detail:addSection(panel, 7, "UI_SC_Tab_Expeditions")
    local expedition = SC.ExpeditionPrototype
    if expedition and expedition.current and expedition.current() then
        local mission = expedition.current()
        local view = expedition.describeForPlayer(getSpecificPlayer(0))
        y = detail:addInformationLine(panel, y, "UI_SC_Info_Message",
            tr("UI_SC_Expedition_Active", view and view.leaderName or "?"))
        if view and view.plannedSite then
            y = detail:addInformationLine(panel, y, "UI_SC_Info_Message",
                tr("UI_SC_Expedition_PlannedDestination", view.plannedSite))
        end
        if view and view.vehicleState then
            y = detail:addInformationLine(panel, y, "UI_SC_Info_Message",
                tr("UI_SC_Expedition_CarState", view.vehicleState))
        end
        if view and view.vehicleIssue then
            y = detail:addInformationLine(panel, y, "UI_SC_Info_Message",
                tr("UI_SC_Expedition_CarIssue", view.vehicleIssue))
        end
        if view and view.supplyProgress then
            local progress = view.supplyProgress
            y = detail:addInformationLine(panel, y, "UI_SC_Info_Message",
                tr(progress.source == "radio"
                    and "UI_SC_Expedition_RadioProgress"
                    or progress.partial
                    and "UI_SC_Expedition_VisibleProgressPartial"
                    or "UI_SC_Expedition_VisibleProgress",
                    progress.collected, progress.requested,
                    progress.at and string.format("%.1f", progress.at) or ""))
        end
        if view and view.delivery then
            local report = view.delivery
            y = detail:addInformationLine(panel, y, "UI_SC_Info_Message",
                tr("UI_SC_Expedition_DeliveryCounts", report.requested,
                    report.collected, report.broughtBack,
                    report.stored, report.pending))
        end
        if view and view.helpRequest then
            local request = view.helpRequest
            if request.shelter then
                y = detail:addInformationLine(panel, y, "UI_SC_Info_Message",
                    tr("UI_SC_Expedition_ShelterRequest", view.leaderName,
                        math.floor(request.x), math.floor(request.y)))
            else
                y = detail:addInformationLine(panel, y, "UI_SC_Info_Message",
                    tr("UI_SC_Expedition_HelpRequest", view.leaderName,
                        math.floor(request.x), math.floor(request.y),
                        tr("UI_SC_Expedition_Help_" .. request.mode)))
            end
        elseif view and view.observedPhase
            and observedPhaseText(view.observedPhase) then
            y = detail:addInformationLine(panel, y, "UI_SC_Info_Message",
                tr("UI_SC_Expedition_NearbyStatus",
                    observedPhaseText(view.observedPhase)))
        elseif view and view.leaderVisible then
            y = detail:addInformationLine(panel, y, "UI_SC_Info_Message",
                tr("UI_SC_Expedition_LeaderNearby"))
        elseif view and (tonumber(view.visibleMembers) or 0) > 0 then
            y = detail:addInformationLine(panel, y, "UI_SC_Info_Message",
                tr("UI_SC_Expedition_MemberNearby"))
        else
            y = detail:addInformationLine(panel, y, "UI_SC_Info_Message",
                tr("UI_SC_Expedition_AwayStatus"))
        end
        local zoom = readExpeditionZoom(mission)
        if zoom then
            y = addZoomSlider(detail, panel, y, zoom)
        else
            y = detail:addInformationLine(panel, y, "UI_SC_Info_Message",
                tr(joinedExpeditionView(mission)
                    and "UI_SC_Expedition_ViewZoomUnavailable"
                    or "UI_SC_Expedition_ViewZoomPending"))
        end
        return addReturnReports(detail, panel, y, expedition)
    end
    y = detail:addInformationLine(panel, y, "UI_SC_Info_Message",
        tr("UI_SC_Expedition_TestBuild"))
    y = addReturnReports(detail, panel, y, expedition)
    if not expedition or not expedition.placeCandidates
        or not expedition.fishingBankCandidates
        or SCSplitScreenProbe == nil then
        return detail:addInformationLine(panel, y, "UI_SC_Info_Message",
            tr("UI_SC_Expedition_Unavailable"))
    end
    local initialMembers = squadRows(detail, draft.group)
    if #initialMembers > 0 then
        local found = false
        for _, row in ipairs(initialMembers) do
            if row.id == draft.leaderId then found = true break end
        end
        if not found then draft.leaderId = initialMembers[1].id end
    end
    if not draft.placesLoaded then
        local candidates = draft.kind == "fish"
            and expedition.fishingBankCandidates
            or expedition.placeCandidates
        local places, reason, total = candidates(
            draft.leaderId, draft.placePage or 1)
        draft.places, draft.placeError = places or {}, places and nil or reason
        draft.placesTotal = total or 0
        draft.placesLoaded = true
    end
    if draft.review then
        local place = selectedPlace(draft)
        local team = squadRows(detail, draft.group)
        local leaderName = "?"
        for _, row in ipairs(team) do
            if row.id == draft.leaderId then leaderName = row.name break end
        end
        local styleName = draft.style
        for _, style in ipairs(STYLES) do
            if style.value == draft.style then styleName = optionLabel(style) break end
        end
        y = detail:addSection(panel, y + 4, "UI_SC_Expedition_Review")
        y = detail:addInformationLine(panel, y, "UI_SC_Info_Message",
            tr("UI_SC_Expedition_Summary", draft.kind, draft.group,
                leaderName, #team,
                place and place.label or "?", draft.hours,
                styleName))
        if draft.kind == "fish" then
            y = detail:addInformationLine(panel, y, "UI_SC_Info_Message",
                tr("UI_SC_Expedition_FishRequest", draft.quantity))
        elseif draft.kind == "search" then
            local categoryName = draft.category
            for _, option in ipairs(CATEGORIES) do
                if option.value == draft.category then
                    categoryName = optionLabel(option)
                    break
                end
            end
            y = detail:addInformationLine(panel, y, "UI_SC_Info_Message",
                tr("UI_SC_Expedition_SearchRequest", categoryName,
                    draft.quantity))
        end
        y = detail:addInformationLine(panel, y, "UI_SC_Info_Message",
            tr("UI_SC_Expedition_TravelSummary",
                draft.travelMode == "straight"
                    and tr("UI_SC_Expedition_StraightTravel")
                    or draft.travelMode == "drive"
                    and tr("UI_SC_Expedition_DriveCar")
                    or tr("UI_SC_Expedition_RoadTravel")))
        if draft.travelMode == "drive" then
            y = detail:addInformationLine(panel, y, "UI_SC_Info_Message",
                tr("UI_SC_Expedition_DriveOneX"))
            if draft.preview then
                y = detail:addInformationLine(panel, y, "UI_SC_Info_Message",
                    tr("UI_SC_Expedition_ChosenCar",
                        draft.preview.carName or "Car",
                        draft.preview.carSqlId or "?"))
                y = detail:addInformationLine(panel, y, "UI_SC_Info_Message",
                    tr("UI_SC_Expedition_DriveFuel",
                        draft.preview.fuel or "?",
                        draft.preview.fuelRequired or "?"))
            end
        end
        if place and place.knowledge == "map_metadata_unconfirmed" then
            y = detail:addInformationLine(panel, y, "UI_SC_Info_Message",
                tr("UI_SC_Expedition_MapUnconfirmed"))
        elseif place and place.knowledge == "map_water_unconfirmed" then
            y = detail:addInformationLine(panel, y, "UI_SC_Info_Message",
                tr("UI_SC_Expedition_FishingShoreUnconfirmed"))
        end
        if draft.preview then
            local itinerary = draft.preview.mode == "road"
                and table.concat(draft.preview.streets or {}, " > ")
                or tr("UI_SC_Expedition_LocalRoute")
            if #itinerary > 160 then itinerary = itinerary:sub(1, 157) .. "..." end
            y = detail:addInformationLine(panel, y, "UI_SC_Info_Message",
                tr("UI_SC_Expedition_RoutePreview",
                    draft.preview.distance, itinerary))
            if (draft.preview.offRoadStart or 0) >= OFF_ROAD_NOTE then
                y = detail:addInformationLine(panel, y, "UI_SC_Info_Message",
                    tr("UI_SC_Expedition_RouteOffRoadStart",
                        draft.preview.offRoadStart))
            end
            if (draft.preview.offRoadEnd or 0) >= OFF_ROAD_NOTE then
                y = detail:addInformationLine(panel, y, "UI_SC_Info_Message",
                    tr("UI_SC_Expedition_RouteOffRoadEnd",
                        draft.preview.offRoadEnd))
            end
            if draft.preview.provisional then
                y = detail:addInformationLine(panel, y, "UI_SC_Info_Message",
                    tr("UI_SC_Expedition_RouteProvisional"))
            end
        elseif draft.previewError then
            y = detail:addInformationLine(panel, y, "UI_SC_Info_Message",
                tr("UI_SC_Expedition_Failed", draft.previewError))
        end
        y = detail:addInformationLine(panel, y, "UI_SC_Info_Message",
            tr("UI_SC_Expedition_RadioHint"))
        y = detail:addInformationLine(panel, y, "UI_SC_Info_Message",
            tr("UI_SC_Expedition_RestockChoice",
                draft.restockBaseDuty and tr("UI_SC_Expedition_Yes")
                    or tr("UI_SC_Expedition_No")))
        y = addButton(detail, panel, y + 4, "UI_SC_Expedition_Edit", "edit")
        return addButton(detail, panel, y, "UI_SC_Expedition_Launch", "launch")
    end
    y = addSelector(detail, panel, y + 4, "UI_SC_Expedition_Squad", "group", GROUPS)
    local members = squadRows(detail, draft.group)
    if #members == 0 then
        y = detail:addInformationLine(panel, y, "UI_SC_Info_Message",
            tr("UI_SC_Expedition_NoMembers"))
    elseif #members > 4 then
        y = detail:addInformationLine(panel, y, "UI_SC_Info_Message",
            tr("UI_SC_Expedition_TooMany"))
    end
    local leaderOptions = {}
    for _, row in ipairs(members) do
        leaderOptions[#leaderOptions + 1] = { value = row.id, label = row.name }
    end
    if #leaderOptions > 0 then
        local present = false
        for _, option in ipairs(leaderOptions) do
            if option.value == draft.leaderId then present = true break end
        end
        if not present then draft.leaderId = leaderOptions[1].value end
        y = addSelector(detail, panel, y, "UI_SC_Expedition_Leader",
            "leaderId", leaderOptions)
    end
    y = addSelector(detail, panel, y, "UI_SC_Expedition_Task", "kind", {
        { value = "scout", key = "UI_SC_Expedition_Scout" },
        { value = "search", key = "UI_SC_Expedition_Search" },
        { value = "fish", key = "UI_SC_Expedition_Fish" },
    })
    if draft.kind == "search" then
        y = addSelector(detail, panel, y, "UI_SC_Expedition_Supplies",
            "category", CATEGORIES)
    end
    if draft.kind == "search" or draft.kind == "fish" then
        y = addSelector(detail, panel, y, "UI_SC_Expedition_Quantity",
            "quantity", QUANTITIES)
        y = addSelector(detail, panel, y,
            "UI_SC_Expedition_RestockBaseDuty", "restockBaseDuty", {
                { value = false, key = "UI_SC_Expedition_No" },
                { value = true, key = "UI_SC_Expedition_Yes" },
            })
    end
    y = addSelector(detail, panel, y, "UI_SC_Expedition_TurnHome",
        "hours", TIMES)
    y = addSelector(detail, panel, y, "UI_SC_Expedition_Combat",
        "style", STYLES)
    y = addSelector(detail, panel, y, "UI_SC_Expedition_Travel",
        "travelMode", TRAVEL)
    if draft.travelMode == "drive" then
        local areas = SC.ExpeditionCar and SC.ExpeditionCar.parkingAreas()
            or {}
        local areaOptions = { { value = nil,
            key = "UI_SC_Expedition_AnyParking" } }
        local selectedArea
        for _, area in ipairs(areas) do
            areaOptions[#areaOptions + 1] = { value = area.id,
                label = area.name or ("Parking " .. tostring(area.id)) }
            if area.id == draft.parkingZoneId then selectedArea = area end
        end
        if draft.parkingZoneId ~= nil and not selectedArea then
            areaOptions[#areaOptions + 1] = {
                value = draft.parkingZoneId,
                label = tr("UI_SC_Expedition_ParkingMissing"),
            }
        end
        y = addSelector(detail, panel, y, "UI_SC_Expedition_ParkingArea",
            "parkingZoneId", areaOptions)
        local cars = SC.ExpeditionCar and
            SC.ExpeditionCar.parkedCars(draft.parkingZoneId) or {}
        table.sort(cars, function(a, b)
            if a.name ~= b.name then return a.name < b.name end
            return a.sqlId < b.sqlId
        end)
        local carOptions = { { value = nil,
            key = "UI_SC_Expedition_AnyVehicle" } }
        local chosenPresent = false
        for _, car in ipairs(cars) do
            carOptions[#carOptions + 1] = { value = car.sqlId,
                label = tr("UI_SC_Expedition_CarOption", car.name,
                    car.sqlId, car.seats, car.zone.name or car.zone.id) }
            if car.sqlId == draft.vehicleSqlId then chosenPresent = true end
        end
        if draft.vehicleSqlId ~= nil and not chosenPresent then
            carOptions[#carOptions + 1] = { value = draft.vehicleSqlId,
                label = tr("UI_SC_Expedition_CarMissing",
                    draft.vehicleSqlId) }
        end
        y = addSelector(detail, panel, y, "UI_SC_Expedition_Vehicle",
            "vehicleSqlId", carOptions)
        y = addButton(detail, panel, y,
            "UI_SC_Expedition_RefreshCars", "refresh_cars")
    end
    local places = { { value = nil, key = draft.kind == "fish"
        and "UI_SC_Expedition_SelectBank"
        or "UI_SC_Expedition_SelectPlace" } }
    for _, place in ipairs(draft.places) do
        local suffix = place.street and (" - " .. place.street) or ""
        places[#places + 1] = { value = place.id,
            label = place.label .. suffix .. " (" .. tostring(place.distance or "?") .. " tiles)" }
    end
    y = addSelector(detail, panel, y, draft.kind == "fish"
        and "UI_SC_Expedition_FishingDestination"
        or "UI_SC_Expedition_Destination",
        "placeId", places)
    local first = (#draft.places > 0) and ((draft.placePage or 1) - 1) * 32 + 1 or 0
    local last = first > 0 and first + #draft.places - 1 or 0
    y = detail:addInformationLine(panel, y, "UI_SC_Info_Message",
        tr(draft.kind == "fish" and "UI_SC_Expedition_BankPage"
            or "UI_SC_Expedition_PlacePage", first, last,
            draft.placesTotal or 0))
    if draft.kind == "fish" and (draft.placesTotal or 0) == 0
        and not draft.placeError then
        y = detail:addInformationLine(panel, y, "UI_SC_Info_Message",
            tr("UI_SC_Expedition_NoFishingBanks"))
    end
    if (draft.placePage or 1) > 1 then
        y = addButton(detail, panel, y, "UI_SC_Expedition_PreviousPlaces",
            "previous_places")
    end
    if last < (draft.placesTotal or 0) then
        y = addButton(detail, panel, y, "UI_SC_Expedition_NextPlaces",
            "next_places")
    end
    if draft.placeError then
        y = detail:addInformationLine(panel, y, "UI_SC_Info_Message",
            tr("UI_SC_Expedition_Failed", draft.placeError))
    elseif selectedPlace(draft)
        and selectedPlace(draft).knowledge == "map_metadata_unconfirmed" then
        y = detail:addInformationLine(panel, y, "UI_SC_Info_Message",
            tr("UI_SC_Expedition_MapUnconfirmed"))
    elseif selectedPlace(draft)
        and selectedPlace(draft).knowledge == "map_water_unconfirmed" then
        y = detail:addInformationLine(panel, y, "UI_SC_Info_Message",
            tr("UI_SC_Expedition_FishingShoreUnconfirmed"))
    end
    y = addButton(detail, panel, y, draft.kind == "fish"
        and "UI_SC_Expedition_RefreshBanks"
        or "UI_SC_Expedition_Refresh", "refresh")
    return addButton(detail, panel, y, "UI_SC_Expedition_Review", "review")
end

return Planner
