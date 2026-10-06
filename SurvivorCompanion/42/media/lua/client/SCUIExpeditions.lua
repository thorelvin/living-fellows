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

local function tr(key, ...)
    return SC.UI.text(key, ...)
end

local function feedback(detail, message, success)
    detail.feedback = message
    detail.feedbackSuccess = success == true
    local now = SC.GameplayUtil and SC.GameplayUtil.nowMs
        and SC.GameplayUtil.nowMs() or 0
    detail.feedbackUntil = now + 6000
    detail.feedbackWrapKey, detail.feedbackWrapLines = nil, nil
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
    if combo.scField == "group" then draft.leaderId = nil end
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
        doctrine = draft.style, travelMode = draft.travelMode }
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
    if action == "refresh" or action == "next_places"
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
        local preview = draft.kind == "fish"
            and SC.ExpeditionPrototype.previewAtFishingBank
            or SC.ExpeditionPrototype.previewAtPlace
        draft.preview, draft.previewError = preview(
            team[1], selectedPlace(draft), draft.travelMode)
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

function Planner.build(detail, panel)
    local draft = detail.expeditionDraft
    if not draft then
        draft = { kind = "scout", style = "stealth", hours = 2,
            travelMode = "road",
            category = "food", quantity = 4, places = {}, placePage = 1 }
        detail.expeditionDraft = draft
        local row = detail.root and detail.root.selectedRow
        draft.group = row and row.group or "alpha"
        if draft.group ~= "alpha" and draft.group ~= "bravo"
            and draft.group ~= "charlie" then draft.group = "alpha" end
    end
    local y = detail:addSection(panel, 7, "UI_SC_Tab_Expeditions")
    local expedition = SC.ExpeditionPrototype
    if expedition and expedition.current and expedition.current() then
        local view = expedition.describeForPlayer(getSpecificPlayer(0))
        y = detail:addInformationLine(panel, y, "UI_SC_Info_Message",
            tr("UI_SC_Expedition_Active", view and view.leaderName or "?"))
        if view and view.plannedSite then
            y = detail:addInformationLine(panel, y, "UI_SC_Info_Message",
                tr("UI_SC_Expedition_PlannedDestination", view.plannedSite))
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
        else
            y = detail:addInformationLine(panel, y, "UI_SC_Info_Message",
                tr("UI_SC_Expedition_AwayStatus"))
        end
        return y
    end
    y = detail:addInformationLine(panel, y, "UI_SC_Info_Message",
        tr("UI_SC_Expedition_TestBuild"))
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
                    or tr("UI_SC_Expedition_RoadTravel")))
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
    end
    y = addSelector(detail, panel, y, "UI_SC_Expedition_TurnHome",
        "hours", TIMES)
    y = addSelector(detail, panel, y, "UI_SC_Expedition_Combat",
        "style", STYLES)
    y = addSelector(detail, panel, y, "UI_SC_Expedition_Travel",
        "travelMode", TRAVEL)
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
