-- SPDX-License-Identifier: MIT
-- Home-trip sheet. Only update() may ask the backend to plan a route.
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.UIHomeTrip = SC.UIHomeTrip or {}
local HomeUI = SC.UIHomeTrip
local GROUPS = { "alpha", "bravo", "charlie" }

local function tr(key, ...) return SC.UI.text(key, ...) end
local function viewer()
    return type(getSpecificPlayer) == "function" and getSpecificPlayer(0) or nil
end
local function metrics(detail) return detail.metrics or SC.UI.layoutMetrics() end
local function note(key, argument)
    local player = viewer()
    if not player then return end
    if SC.GameplayUtil and SC.GameplayUtil.call then
        SC.GameplayUtil.call(player, "setHaloNote", tr(key, argument))
    elseif type(player.setHaloNote) == "function" then
        pcall(player.setHaloNote, player, tr(key, argument))
    end
end
local function nameOf(record)
    if type(record) ~= "table" then return tr("UI_SC_HomeTrip_Member") end
    local identity = record.identity or {}
    local name = identity.forename and (identity.forename
        .. (identity.surname and (" " .. identity.surname) or ""))
        or record.name or record.fullName
    if not name or name == "" or string.match(tostring(name), "^sc%-") then
        name = SC.GameplayUtil and SC.GameplayUtil.nameOf and record.actor
            and SC.GameplayUtil.nameOf(record.actor) or nil
    end
    return name and not string.match(tostring(name), "^sc%-") and name
        or tr("UI_SC_HomeTrip_Member")
end
local function recordFor(value)
    if type(value) ~= "table" then return nil end
    if value.actor ~= nil then return value end
    return SC.Registry and type(SC.Registry.byId) == "function" and value.id
        and SC.Registry.byId(value.id) or value
end
local function captureRecords(records)
    local result = {}
    for _, record in ipairs(records or {}) do
        local captured = {}
        for key, value in pairs(record) do captured[key] = value end
        result[#result + 1] = captured
    end
    return result
end
local function sameMembers(left, right)
    if #left ~= #right then return false end
    local members = {}
    for _, record in ipairs(left) do members[record.id] = record end
    for _, record in ipairs(right) do
        local previous = members[record.id]
        if not previous or previous.actor ~= record.actor then return false end
    end
    return true
end
local function displayName(value)
    if type(value) == "table" then return nameOf(value) end
    if type(value) == "string" and value ~= "" and not string.match(value, "^sc%-") then return value end
    local record = value and SC.Registry and SC.Registry.byId and SC.Registry.byId(value)
    return nameOf(record)
end
local function displayNames(values)
    local names = {}
    for _, value in ipairs(values or {}) do names[#names + 1] = displayName(value) end
    return table.concat(names, ", ")
end
local function reasonText(reason, argument)
    if type(reason) == "table" then
        return reason.message or reasonText(reason.reason or reason.code,
            reason.name or reason.argument)
    end
    local home = SC.HomeTrip
    if home and type(home.reasonText) == "function" then
        return home.reasonText(reason, argument)
    end
    if home and type(home.reason) == "function" then
        return home.reason(reason, argument)
    end
    local keys = { squad_too_large = "TooMany", too_many = "TooMany",
        no_camp = "NoCamp", leader_missing = "LeaderUnavailable",
        roster_empty = "Nobody", squad_empty = "Nobody",
        home_trip_active = "NoViewTrip", home_review_changed = "ReviewChanged", unavailable = "Unavailable",
        home_radio_needed = "RadioNeeded", home_radio_busy = "RadioBusy", home_radio_stale = "RadioStale",
        home_radio_no_ack = "RadioNoAck", home_radio_unavailable = "RadioUnavailable",
        home_radio_already_holding = "RadioAlreadyHolding", home_radio_not_stopped = "RadioNotStopped",
        home_radio_recall_stopping = "RadioRecallStopping",
        home_radio_received = "RadioReceived", home_radio_returning = "RadioReturning",
        home_radio_holding = "RadioHolding", home_radio_resumed = "RadioResumed", home_radio_status = "RadioStatusReply" }
    if keys[reason] then return tr("UI_SC_HomeTrip_" .. keys[reason], argument) end
    if type(reason) == "string" and string.match(reason, "^UI_SC_") then
        return tr(reason, argument)
    end
    -- Unknown backend codes must not leak into a player's review.
    return tr("UI_SC_HomeTrip_Unavailable")
end
HomeUI.reasonText = reasonText

local function selectionRecords(detail, selection)
    if selection.records then return selection.records end
    if selection.group then
        local records = {}
        for _, entry in ipairs(detail.root and detail.root.roster
                and detail.root.roster.items or {}) do
            local row = entry.item
            if row then
                local registered = SC.Registry and SC.Registry.byId and SC.Registry.byId(row.id)
                local record = registered or recordFor(row)
                local command = record and record.actor and SC.Commands and SC.Commands.peekExisting
                    and SC.Commands.peekExisting(record.actor)
                local group, recruited = row.group, row.recruited
                if command then group, recruited = command.group, command.recruited end
                if group == selection.group and recruited == true then records[#records + 1] = record end
            end
        end
        return records
    end
    local record = recordFor(selection.record or selection.row)
    return record and { record } or {}
end

local function roster(detail, selection)
    local records = selectionRecords(detail, selection)
    if SC.HomeTrip and type(SC.HomeTrip.roster) == "function" then
        local result = SC.HomeTrip.roster({ records = records,
            leaderId = selection.leaderId, travelMode = selection.travelMode,
            vehicle = selection.vehicle, vehicleSqlId = selection.vehicleSqlId,
            player = viewer() })
        if result then
            result.records = result.eligibleRecords or result.records or {}
            result.exclusions = result.exclusions or {}
            return result
        end
    end
    local result = { records = {}, exclusions = {} }
    for _, record in ipairs(records) do
        local state = SC.Commands and SC.Commands.describe
            and SC.Commands.describe(record.id, viewer()) or record
        local order = state and state.order
        local excluded = state and (state.recruited == false
            or state.alive == false or state.expeditionAway == true
            or state.insideCamp == true
            or order and order ~= "follow" and order ~= "regroup")
        if excluded then
            result.exclusions[#result.exclusions + 1] = { record = record,
                name = nameOf(record), reason = "not_following" }
        else result.records[#result.records + 1] = record end
    end
    return result
end

local function currentSelection(detail)
    local sheet = detail.homeTripSheet
    return { records = selectionRecords(detail, sheet.selection),
        leaderId = sheet.selection.leaderId,
        travelMode = sheet.selection.travelMode or "road",
        vehicle = sheet.selection.vehicle, vehicleSqlId = sheet.selection.vehicleSqlId }
end

local function invalidate(detail)
    local sheet = detail.homeTripSheet
    sheet.review, sheet.pending = nil, true
    sheet.sendPending = nil
    sheet.reviewNotice = nil
    sheet.reviewAvailabilityKey = nil
    sheet.revision = (sheet.revision or 0) + 1
end

-- Keep the roster shown when the action was chosen until an explicit update
-- can replace its preview. A queued departure cannot inherit new group members.
local function refreshGroupSelection(detail)
    local sheet = detail.homeTripSheet
    if not sheet.selection.group then return false end
    local current = selectionRecords(detail, { group = sheet.selection.group })
    if sameMembers(sheet.selection.records or {}, current) then return false end
    sheet.selection.records = captureRecords(current)
    invalidate(detail)
    sheet.availabilityKey = nil
    sheet.reviewNotice = reasonText("home_review_changed")
    return true
end

local function availabilityKey(selection, status)
    local home = SC.HomeTrip
    local carKey = selection.travelMode == "drive" and home and home.reviewKey and home.reviewKey(selection) or nil
    local parts = { tostring(status and status.blocker), tostring(status and status.canStart),
        tostring(selection.leaderId), tostring(selection.travelMode),
        tostring(status and status.camp and status.camp.fingerprint),
        tostring(selection.vehicleSqlId), tostring(carKey) }
    local members, exclusions = {}, {}
    for _, record in ipairs(status and status.records or selection.records or {}) do
        members[#members + 1] = tostring(record.id) .. "=" .. tostring(record.actor)
    end
    for _, exclusion in ipairs(status and status.exclusions or {}) do
        exclusions[#exclusions + 1] = tostring(exclusion.id or exclusion.record and exclusion.record.id)
            .. ":" .. tostring(exclusion.reason)
    end
    table.sort(members)
    table.sort(exclusions)
    parts[#parts + 1] = table.concat(members, ",")
    parts[#parts + 1] = table.concat(exclusions, ",")
    return table.concat(parts, ":")
end

-- Public, explicit invalidation is also useful if a caller changes the roster.
function HomeUI.invalidate(detail)
    if detail and detail.homeTripSheet then invalidate(detail) end
end

function HomeUI.openSheet(selection)
    selection = selection or {}
    local preferred = selection.record or selection.row
        or selection.records and selection.records[1]
    local root = SC.UI.open("groups", preferred and preferred.id)
    if not root or not root.detail then return false end
    local detail = root.detail
    local chosen = { record = selection.record or selection.row,
        records = selection.records, group = selection.group,
        leaderId = selection.leaderId,
        travelMode = selection.travelMode == "drive" and "drive"
            or selection.travelMode == "straight" and "straight" or "road",
        vehicle = selection.vehicle, vehicleSqlId = selection.vehicleSqlId or selection.sqlId }
    if not chosen.record and not chosen.records and not chosen.group then
        chosen.record = recordFor(root.selectedRow)
    end
    if chosen.group then chosen.records = captureRecords(selectionRecords(detail, chosen))
    elseif chosen.records then chosen.records = captureRecords(chosen.records)
    elseif chosen.record then chosen.record = captureRecords({ chosen.record })[1] end
    local crew = roster(detail, chosen)
    if chosen.leaderId == nil and crew.records[1] then
        chosen.leaderId = crew.records[1].id
    end
    detail.homeTripSheet = { selection = chosen,
        singleRecord = recordFor(preferred or root.selectedRow),
        leaderExplicit = selection.leaderId ~= nil,
        vehicleLabel = selection.vehicleName }
    for _, record in ipairs(selectionRecords(detail, chosen)) do
        if record.id == chosen.leaderId then
            detail.homeTripSheet.leaderName = nameOf(record)
        end
    end
    detail.feedback, detail.feedbackUntil = nil, nil
    invalidate(detail)
    detail:rebuild()
    return true
end

-- Called from the scheduled UI update, outside drawing and rebuilding. A
-- selector burst replaces one pending request; at most one bounded draft runs.
function HomeUI.update(detail)
    local sheet = detail and detail.homeTripSheet
    if not sheet then return false end
    if detail.tab ~= "groups" then sheet.sendPending = nil; return false end
    local home = SC.HomeTrip
    refreshGroupSelection(detail)
    local selection = currentSelection(detail)
    if sheet.pending and selection.travelMode == "drive" then
        local car = SC.ExpeditionCar
        local crew = roster(detail, sheet.selection)
        sheet.cars = car and car.fieldCandidates and car.fieldCandidates(crew.records, viewer()) or {}
        if not selection.vehicle and selection.vehicleSqlId == nil then
            local preferred
            for _, candidate in ipairs(sheet.cars) do
                if not preferred or candidate.canUse == true then preferred = candidate end
                if candidate.canUse == true then break end
            end
            if preferred then
                sheet.selection.vehicle, sheet.selection.vehicleSqlId = preferred.vehicle, preferred.sqlId
                sheet.vehicleLabel = preferred.name
                selection = currentSelection(detail)
            end
        end
    end
    local status = home and home.eligibility and home.eligibility(selection)
    local currentKey = availabilityKey(selection, status)
    if sheet.availabilityKey ~= nil and sheet.availabilityKey ~= currentKey then
        invalidate(detail)
        if selection.travelMode == "drive" then
            local car, crew = SC.ExpeditionCar, roster(detail, sheet.selection)
            sheet.cars = car and car.fieldCandidates and car.fieldCandidates(crew.records, viewer()) or {}
        end
    end
    sheet.availabilityKey = currentKey
    if sheet.sendPending then
        sheet.sendPending = nil
        HomeUI.commitDeparture(detail, selection)
        return true
    end
    if not sheet.pending then return false end
    sheet.pending = false
    local ok, review = false, nil
    if home and type(home.draft) == "function" then
        ok, review = pcall(home.draft, selection)
    end
    sheet.review = ok and type(review) == "table" and review
        or { canStart = false, blocker = "unavailable" }
    -- The review key owns the requested mode; its route can fall back to straight.
    sheet.reviewAvailabilityKey = availabilityKey(selection, status)
    sheet.availabilityKey = sheet.reviewAvailabilityKey
    detail:rebuild(true)
    return true
end

function HomeUI.whoOptions(detail)
    local sheet, options = detail.homeTripSheet, {}
    local selection = sheet.selection
    if sheet.singleRecord then
        local single = roster(detail, { record = sheet.singleRecord,
            travelMode = selection.travelMode, vehicle = selection.vehicle,
            vehicleSqlId = selection.vehicleSqlId })
        local blocked = #single.records == 0 and single.exclusions[1]
        local reason = blocked and reasonText(blocked.reason or blocked.blocker,
            blocked.name or nameOf(sheet.singleRecord)) or nil
        options[#options + 1] = { value = "single", label = nameOf(sheet.singleRecord),
            record = sheet.singleRecord, disabled = reason ~= nil, reason = reason }
    end
    for _, group in ipairs(GROUPS) do
        local result = roster(detail, { group = group,
            travelMode = selection.travelMode, vehicle = selection.vehicle,
            vehicleSqlId = selection.vehicleSqlId })
        if #result.records > 0 or #result.exclusions > 0
            or sheet.selection.group == group then
            local label = tr("UI_SC_Select_Group" .. string.upper(string.sub(group, 1, 1))
                .. string.sub(group, 2))
            local blocked = #result.records > 4 and tr("UI_SC_HomeTrip_TooMany")
                or #result.records == 0 and tr("UI_SC_HomeTrip_Nobody") or nil
            options[#options + 1] = { value = group, group = group,
                records = captureRecords(selectionRecords(detail, { group = group })),
                label = tr("UI_SC_HomeTrip_GroupCrew", label, #result.records, displayNames(result.records)),
                disabled = blocked ~= nil, reason = blocked }
        end
    end
    return options
end

function HomeUI.onSelect(detail, combo)
    local sheet = detail.homeTripSheet
    if not sheet then return end
    local option = combo:getOptionData(combo.selected)
    if not option then return end
    if option.disabled then
        combo.selected = combo.scSelected
        combo.tooltip = option.reason
        return
    end
    if combo.scHomeField == "who" then
        sheet.selection.group = option.group
        sheet.selection.record = option.record
        sheet.selection.records = option.records and captureRecords(option.records) or nil
        if not sheet.leaderExplicit then
            local crew = roster(detail, sheet.selection)
            sheet.selection.leaderId = crew.records[1] and crew.records[1].id
            sheet.leaderName = crew.records[1] and nameOf(crew.records[1]) or nil
        end
    else
        sheet.selection[combo.scHomeField] = option.value
        if combo.scHomeField == "vehicleSqlId" then
            sheet.selection.vehicle, sheet.vehicleLabel = option.vehicle, option.name or option.label
        end
        if combo.scHomeField == "leaderId" then
            sheet.leaderExplicit, sheet.leaderName = true, option.label
        end
    end
    invalidate(detail)
    detail:rebuild(true)
end

-- Vanilla shares a popup between selectors. This wrapper only changes the
-- colour during this one disabled row's native draw, then restores it.
local function decoratePopup(combo)
    local popup = combo.popup
    if not popup or popup.scHomeRowDrawing or type(popup.doDrawItem) ~= "function" then return end
    local original = popup.doDrawItem
    popup.scHomeRowDrawing = true
    popup.doDrawItem = function(self, y, item, alternate)
        local parent = self.parentCombo
        local option = parent and parent.scHomeField
            and parent:getOptionData(item.index) or nil
        local colour = parent and parent.textColor
        if option and option.disabled and colour then
            parent.textColor = { r = 0.48, g = 0.49, b = 0.46, a = colour.a }
        end
        local result = original(self, y, item, alternate)
        if parent and colour then parent.textColor = colour end
        return result
    end
end

local function addSelector(detail, panel, y, key, field, selected, options)
    local m = metrics(detail)
    y = detail:addInformationLine(panel, y, "UI_SC_Info_Message", tr(key))
    local width = math.max(72, panel:getWidth() - 28)
    local combo = ISComboBox:new(8, y, width, m.buttonHeight, detail, HomeUI.onSelect)
    combo:initialise()
    combo:instantiate()
    combo.scHomeField = field
    combo.backgroundColor = { r = 0.035, g = 0.04, b = 0.035, a = 0.78 }
    local found = false
    for index, option in ipairs(options) do
        combo:addOptionWithData(SC.UI.fitText(UIFont.Small, option.label,
            math.max(40, width - 28)), option, option.reason or option.label)
        if option.value == selected then combo.selected, found = index, true end
    end
    if not found then
        local label = field == "leaderId" and tr("UI_SC_HomeTrip_LeaderUnavailable",
            detail.homeTripSheet.leaderName or tr("UI_SC_HomeTrip_Member"))
            or field == "vehicleSqlId" and tr("UI_SC_HomeTrip_CarSelectionUnavailable",
                detail.homeTripSheet.vehicleLabel or tr("UI_SC_HomeTrip_Car"))
            or tr("UI_SC_HomeTrip_SelectionUnavailable")
        combo:addOptionWithData(label, { value = selected, label = label,
            disabled = true, reason = label }, label)
        combo.selected = #combo.options
    end
    combo.scSelected = combo.selected
    decoratePopup(combo)
    panel:addChild(combo)
    return y + m.buttonHeight + 5
end

local function addButton(detail, panel, x, y, width, key, action, enabled, reason)
    local label, m = tr(key), metrics(detail)
    local button = ISButton:new(x, y, width, m.buttonHeight,
        SC.UI.fitText(UIFont.Small, label, math.max(32, width - 12)),
        detail, HomeUI.onButton)
    button:initialise()
    button.backgroundColor = { r = 0.12, g = 0.13, b = 0.12, a = 0.78 }
    button.scHomeAction, button.enable = action, enabled ~= false
    if button.setEnable then button:setEnable(enabled ~= false) end
    button.tooltip = enabled == false and reason or label
    panel:addChild(button)
    return button
end

function HomeUI.clearFooter(detail)
    for _, control in ipairs(detail.homeTripFooter or {}) do
        if detail.removeChild then detail:removeChild(control) end
    end
    detail.homeTripFooter = nil
end

local function sheetBlocker(detail, crew)
    local sheet, review = detail.homeTripSheet, detail.homeTripSheet.review
    if sheet.sendPending then return tr("UI_SC_HomeTrip_CheckingDeparture") end
    if sheet.pending then return tr("UI_SC_HomeTrip_Planning") end
    if #crew.records > 4 then return tr("UI_SC_HomeTrip_TooMany") end
    if #crew.records == 0 then return tr("UI_SC_HomeTrip_Nobody") end
    local found = false
    for _, record in ipairs(crew.records) do
        if record.id == sheet.selection.leaderId then found = true end
    end
    if not found then return tr("UI_SC_HomeTrip_LeaderUnavailable",
        sheet.leaderName or tr("UI_SC_HomeTrip_Member")) end
    if review and review.blocker then return reasonText(review.blocker,
        review.reasonArgument or sheet.leaderName) end
    if not review or review.canStart ~= true or not SC.HomeTrip
        or type(SC.HomeTrip.start) ~= "function" then return tr("UI_SC_HomeTrip_Unavailable") end
    local home = SC.HomeTrip
    local status = home and home.eligibility and home.eligibility(currentSelection(detail))
    if status and status.canStart == false then
        return reasonText(status.blocker or status.reason, sheet.leaderName)
    end
    return nil
end

local function addFooter(detail, panel, blocker)
    HomeUI.clearFooter(detail)
    local m = metrics(detail)
    local lines = blocker and SC.UI.wrapText(UIFont.Small, blocker,
        math.max(64, panel:getWidth() - 24)) or {}
    local height = (#lines * m.infoLineHeight) + m.buttonHeight + 12
    local originalHeight = panel:getHeight()
    local top = math.max(m.buttonHeight + 12, originalHeight - height)
    if panel.setHeight then panel:setHeight(top) end
    local footer = {}
    local y = top + 5
    for _, line in ipairs(lines) do
        local label = ISLabel:new(8, y, m.fontHeight, line,
            0.95, 0.43, 0.39, 1, UIFont.Small, true)
        label:initialise()
        label.scHomeBlocker, label.tooltip = true, blocker
        detail:addChild(label)
        footer[#footer + 1] = label
        y = y + m.infoLineHeight
    end
    local width = math.max(36, (panel:getWidth() - 28) / 2)
    footer[#footer + 1] = addButton(detail, detail, 8, y, width,
        "UI_SC_HomeTrip_Back", "back", true)
    footer[#footer + 1] = addButton(detail, detail, 12 + width, y, width,
        "UI_SC_HomeTrip_Send", "send", blocker == nil, blocker)
    detail.homeTripFooter = footer
end

function HomeUI.timeText(hours)
    local value = math.max(0, tonumber(hours) or 0)
    if value < 0.4 then return tr("UI_SC_HomeTrip_Minutes", math.max(1, math.floor(value * 60 + 0.5))) end
    if value < 0.75 then return tr("UI_SC_HomeTrip_HalfHour") end
    if value < 1.5 then return tr("UI_SC_HomeTrip_OneHour") end
    return tr("UI_SC_HomeTrip_Hours", math.floor(value + 0.5))
end

function HomeUI.buildSheet(detail, panel)
    local sheet = detail.homeTripSheet
    if not sheet then return nil end
    local crew = roster(detail, sheet.selection)
    local y = detail:addSection(panel, 7, "UI_SC_HomeTrip_Sheet")
    y = addSelector(detail, panel, y, "UI_SC_HomeTrip_Who", "who",
        sheet.selection.group or "single", HomeUI.whoOptions(detail))
    local leaders = {}
    for _, record in ipairs(crew.records) do
        leaders[#leaders + 1] = { value = record.id, label = nameOf(record) }
    end
    y = addSelector(detail, panel, y, "UI_SC_HomeTrip_Leader", "leaderId",
        sheet.selection.leaderId, leaders)
    y = addSelector(detail, panel, y, "UI_SC_HomeTrip_How", "travelMode",
        sheet.selection.travelMode, {
            { value = "road", label = tr("UI_SC_HomeTrip_Way_Road") },
            { value = "straight", label = tr("UI_SC_HomeTrip_Way_Straight") },
            { value = "drive", label = tr("UI_SC_HomeTrip_Way_Drive") },
        })
    if sheet.selection.travelMode == "drive" then
        local cars = {}
        for _, candidate in ipairs(sheet.cars or {}) do
            local name = candidate.name or tr("UI_SC_HomeTrip_Car")
            if candidate.yourCar then name = tr("UI_SC_HomeTrip_YourCar", name) end
            local reason = candidate.canUse == false and reasonText(candidate.reason or "unavailable", name) or nil
            local label = reason and tr("UI_SC_HomeTrip_CarBlocked", name, reason)
                or tr("UI_SC_HomeTrip_CarChoice", name, candidate.seats or 0,
                    math.floor(tonumber(candidate.fuelPercent) or 0))
            cars[#cars + 1] = { value = candidate.sqlId, vehicle = candidate.vehicle,
                name = candidate.name, label = label, disabled = candidate.canUse == false, reason = reason }
        end
        y = addSelector(detail, panel, y, "UI_SC_HomeTrip_Car", "vehicleSqlId",
            sheet.selection.vehicleSqlId, cars)
        if #cars == 0 then y = detail:addInformationLine(panel, y, "UI_SC_Info_Message", tr("UI_SC_HomeTrip_NoCars")) end
    end
    for _, exclusion in ipairs(crew.exclusions) do
        y = detail:addInformationLine(panel, y, "UI_SC_Info_Message",
            tr("UI_SC_HomeTrip_Excluded", exclusion.name or nameOf(exclusion.record),
                reasonText(exclusion.reason or exclusion.blocker, exclusion.name)))
    end
    y = detail:addSection(panel, y + 3, "UI_SC_HomeTrip_Review")
    if sheet.reviewNotice then
        y = detail:addInformationLine(panel, y, "UI_SC_Info_Message", sheet.reviewNotice)
    end
    y = detail:addInformationLine(panel, y, "UI_SC_Info_Message",
        tr("UI_SC_HomeTrip_CrewReview", displayNames(crew.records)))
    local review = sheet.review
    local reviewedTravelMode = review and review.travelMode or sheet.selection.travelMode
    if sheet.selection.travelMode == "drive" and review and review.car then
        local car = review.car
        y = detail:addInformationLine(panel, y, "UI_SC_Info_Message", tr("UI_SC_HomeTrip_SeatCheck",
            tonumber(car.seatCount) or tonumber(car.seats) or 0, car.neededSeats or #crew.records))
        if tonumber(car.fuelPercent) then
            y = detail:addInformationLine(panel, y, "UI_SC_Info_Message",
                tonumber(car.requiredFuelPercent) and tr("UI_SC_HomeTrip_FuelCheck",
                    math.floor(car.fuelPercent), math.ceil(car.requiredFuelPercent))
                    or tr("UI_SC_HomeTrip_FuelKnown", math.floor(car.fuelPercent)))
        end
        if car.keyHolderName then
            y = detail:addInformationLine(panel, y, "UI_SC_Info_Message", tr("UI_SC_HomeTrip_KeyHolder", car.keyHolderName))
        end
    end
    if sheet.pending then
        y = detail:addInformationLine(panel, y, "UI_SC_Info_Message", tr("UI_SC_HomeTrip_Planning"))
    elseif review and tonumber(review.distance) then
        local routeText
        if reviewedTravelMode == "drive" then
            routeText = tr("UI_SC_HomeTrip_RouteDrive", math.floor(review.distance + 0.5), HomeUI.timeText(review.estimatedHours))
        elseif reviewedTravelMode == "road" and #(review.streets or {}) > 0 then
            routeText = tr("UI_SC_HomeTrip_RouteVia", math.floor(review.distance + 0.5),
                table.concat(review.streets, " > "), HomeUI.timeText(review.estimatedHours))
        else
            routeText = tr(reviewedTravelMode == "road" and "UI_SC_HomeTrip_RouteRoad"
                or "UI_SC_HomeTrip_RouteStraight", math.floor(review.distance + 0.5),
                HomeUI.timeText(review.estimatedHours))
        end
        y = detail:addInformationLine(panel, y, "UI_SC_Info_Message", routeText)
        if review.routeFallback then
            y = detail:addInformationLine(panel, y, "UI_SC_Info_Message", tr("UI_SC_HomeTrip_RoadFallback"))
        end
        if sheet.selection.travelMode ~= "drive" and (tonumber(review.estimatedHours) or 0) > 2 then
            y = detail:addInformationLine(panel, y, "UI_SC_Info_Message", tr("UI_SC_HomeTrip_LongWalk"))
        end
    end
    if sheet.selection.travelMode == "drive" and review and review.homeStop then
        local stop = review.homeStop
        y = detail:addInformationLine(panel, y, "UI_SC_Info_Message",
            tr(stop.kind == "roadside" and "UI_SC_HomeTrip_RoadsideReview"
                or (stop.provisional or stop.clearanceOnArrival) and "UI_SC_HomeTrip_ParkingExpected"
                or "UI_SC_HomeTrip_ParkingReview",
                stop.label or tr("UI_SC_HomeTrip_CampRoadside")))
        if stop.kind == "roadside" and (stop.provisional or stop.clearanceOnArrival) then
            y = detail:addInformationLine(panel, y, "UI_SC_Info_Message", tr("UI_SC_HomeTrip_ClearanceOnArrival"))
        end
    end
    y = detail:addInformationLine(panel, y, "UI_SC_Info_Message", tr("UI_SC_HomeTrip_ArrivalReview"))
    y = detail:addInformationLine(panel, y, "UI_SC_Info_Message", tr("UI_SC_HomeTrip_ViewReview",
        sheet.leaderName or tr("UI_SC_HomeTrip_Member")))
    y = detail:addInformationLine(panel, y, "UI_SC_Info_Message", tr("UI_SC_HomeTrip_RecallNear"))
    addFooter(detail, panel, sheetBlocker(detail, crew))
    return y
end

-- The click queues intent; the normal update performs departure outside UI
-- callbacks. Its availability check above cancels intent before any new draft.
function HomeUI.commitDeparture(detail, selection)
    local sheet, home = detail.homeTripSheet, SC.HomeTrip
    if not sheet or sheetBlocker(detail, roster(detail, sheet.selection)) then
        detail:rebuild(true)
        return false
    end
    local ok, accepted, reason = pcall(home.start, selection, sheet.review)
    if ok and accepted == true then
        local name = sheet.selection.group and tr("UI_SC_Select_Group"
            .. string.upper(string.sub(sheet.selection.group, 1, 1)) .. string.sub(sheet.selection.group, 2))
            or sheet.leaderName or tr("UI_SC_HomeTrip_Member")
        note("UI_SC_HomeTrip_Departed", name)
        detail.homeTripSheet = nil
        HomeUI.clearFooter(detail)
    else
        if ok and reason == "home_review_changed" then
            invalidate(detail)
            sheet.reviewNotice = reasonText(reason)
        else
            sheet.review = { canStart = false, blocker = ok and reason or "unavailable" }
        end
    end
    detail:rebuild(true)
    return ok and accepted == true
end

function HomeUI.onButton(detail, button)
    local action, home = button.scHomeAction, SC.HomeTrip
    if action == "back" then
        detail.homeTripSheet = nil
        HomeUI.clearFooter(detail)
    elseif action == "send" then
        local sheet = detail.homeTripSheet
        if not sheet or sheet.pending or sheet.sendPending then return end
        if refreshGroupSelection(detail) then detail:rebuild(true); return end
        local selection = currentSelection(detail)
        local status = home and home.eligibility and home.eligibility(selection)
        -- A group can change between the scheduled preview and this click.
        -- Never silently send a newly eligible member or a surviving subset.
        if sheet.reviewAvailabilityKey ~= availabilityKey(selection, status) then
            invalidate(detail)
            detail:rebuild(true)
            return
        end
        if sheetBlocker(detail, roster(detail, sheet.selection)) then return end
        sheet.sendPending = true
    elseif action == "dismiss" and home and home.dismiss then home.dismiss()
    elseif action == "radio" then
        return HomeUI.onRadioButton(detail, button)
    elseif action == "call_off" and home and home.cancel then
        -- The action rechecks physical proximity; camera observation is never authority.
        local view = home.describe and home.describe(viewer())
        local allowed = home.canRecall and home.canRecall(viewer())
            or not home.canRecall and view and view.canRecall == true
        if not allowed then return end
        local accepted = home.cancel(viewer())
        if accepted == true then note("UI_SC_HomeTrip_CalledOff") end
    elseif action == "group" then
        return HomeUI.openSheet({ group = button.scHomeGroup, records = button.scHomeRecords })
    end
    detail:rebuild(true)
end

function HomeUI.addGroupOrder(detail, panel, y, group)
    local result = roster(detail, { group = group })
    local status = SC.HomeTrip and SC.HomeTrip.eligibility
        and SC.HomeTrip.eligibility({ records = result.records }) or nil
    local reason = #result.records > 4 and tr("UI_SC_HomeTrip_TooMany")
        or #result.records == 0 and tr("UI_SC_HomeTrip_Nobody")
        or status and not status.canStart and reasonText(status.blocker or status.reason) or nil
    local button = addButton(detail, panel, 8, y, math.max(72, panel:getWidth() - 28),
        "UI_SC_HomeTrip_GroupOrder", "group", reason == nil, reason)
    button.scHomeGroup = group
    button.scHomeRecords = captureRecords(selectionRecords(detail, { group = group }))
    return y + metrics(detail).buttonHeight + 4
end

local function clockText(value)
    if type(value) ~= "number" then return tostring(value or "") end
    -- Trip timestamps are world ages. Their zero is the world's starting
    -- clock time, which may be 07:00 rather than midnight. Apply today's
    -- age-to-clock offset to historical entries before wrapping the day.
    local clockHour = value
    if type(getGameTime) == "function" then
        local okay, age, timeOfDay = pcall(function()
            local gameTime = getGameTime()
            return tonumber(gameTime:getWorldAgeHours()), tonumber(gameTime:getTimeOfDay())
        end)
        if okay and age and timeOfDay and age == age and age < math.huge
            and age >= 0 and timeOfDay == timeOfDay and timeOfDay >= 0 and timeOfDay <= 24 then
            clockHour = value + timeOfDay - age
        end
    end
    local minutes = math.floor(clockHour * 60 + 0.5)
    -- Kahlua's remainder can stay negative for an earlier-day timestamp.
    minutes = minutes - math.floor(minutes / (24 * 60)) * (24 * 60)
    local hour = math.floor(minutes / 60)
    return string.format("%02d:%02d", hour, minutes - hour * 60)
end

local radioChoices = {
    { "come_back", "RadioComeBack" }, { "hold", "RadioHold" },
    { "status", "RadioStatus" }, { "push_on", "RadioPushOn" },
}

function HomeUI.onRadioButton(detail, button)
    local home, primary = SC.HomeTrip, viewer()
    local view = home and home.describe and home.describe(primary) or nil
    local radio = home and home.radioState and home.radioState(primary) or nil
    local verb, reason = button.scHomeRadioVerb, nil
    local choice = radio and radio.actions and radio.actions[verb]
    if not view or view.active ~= true or not button.scHomeTripId
        or button.scHomeTripId ~= view.tripId then
        reason = "home_radio_stale"
    elseif radio and radio.pending then reason = "home_radio_busy"
    elseif not home.requestRadio or not choice or choice.enabled ~= true then
        reason = choice and choice.reason or "home_radio_unavailable"
    else
        local accepted
        accepted, reason = home.requestRadio(primary, verb, button.scHomeTripId)
        if accepted == true then
            detail.homeRadioNotice = nil
            detail:rebuild(true)
            return true
        end
        reason = reason or "home_radio_unavailable"
    end
    -- Queuing is not acknowledgement. Home owns reply notes and applies the
    -- command only after the native radio exchange has been verified.
    detail.homeRadioNotice = { tripId = view and view.tripId, reason = reason,
        replyId = radio and radio.lastReply and radio.lastReply.id }
    detail:rebuild(true)
    return false
end

local function radioReportText(radio)
    local report = radio and radio.report
    if not report or type(report.at) ~= "number" or report.at ~= report.at
        or report.at < 0 or report.at == math.huge then return nil end
    local states = { holding = "Holding", blocked = "Blocked", stopped = "Blocked",
        recalling = "ComingBack", coming_back = "ComingBack", returning = "ComingBack", inbound = "Walking",
        walking = "Walking", resuming = "Resuming", resting = "Resting",
        driving = "Driving", driving_home = "Driving", driving_out = "Driving", parking_home = "ParkingShort",
        stopping = "RadioStopping",
        home_wait = "Arriving", arriving = "Arriving" }
    local state = tr("UI_SC_HomeTrip_" .. (states[report.state] or "RadioReceived"))
    if report.state == "holding" and type(report.holdingAt) == "number"
        and report.holdingAt == report.holdingAt and report.holdingAt >= 0 and report.holdingAt <= report.at then
        state = tr("UI_SC_HomeTrip_RadioHoldingSince", clockText(report.holdingAt))
    end
    local place = report.place or tr("UI_SC_HomeTrip_LastKnownPlace")
    local distance = tonumber(report.distance)
    if distance and distance == distance and distance >= 0 and distance < math.huge then
        return tr("UI_SC_HomeTrip_RadioReportDistance", clockText(report.at), state,
            place, math.floor(distance + 0.5))
    end
    return tr("UI_SC_HomeTrip_RadioReport", clockText(report.at), state, place)
end

local function buildRadio(detail, panel, y, view)
    local radio = view.radio or {}
    local driveRecallHint = view.travelMode == "drive" and tr("UI_SC_HomeTrip_RadioDriveRecallHint") or nil
    if driveRecallHint then
        y = detail:addInformationLine(panel, y, "UI_SC_Info_Message", driveRecallHint)
    end
    if radio.pending then
        y = detail:addInformationLine(panel, y, "UI_SC_Info_Message",
            tr("UI_SC_HomeTrip_RadioCalling", displayName(radio.pending.leaderName or view.leaderName)))
    end
    local reasons, seen = {}, {}
    for _, choice in ipairs(radioChoices) do
        local verb, suffix = choice[1], choice[2]
        if verb ~= "push_on" or radio.blocked == true or radio.holding == true then
            local availability = radio.actions and radio.actions[verb]
            local reason = radio.pending and "home_radio_busy"
                or availability and availability.reason or "home_radio_unavailable"
            local enabled = not radio.pending and view.tripId ~= nil
                and availability and availability.enabled == true
            local button = addButton(detail, panel, 8, y, math.max(72, panel:getWidth() - 28),
                "UI_SC_HomeTrip_" .. suffix, "radio", enabled == true, reasonText(reason))
            button.scHomeRadioVerb, button.scHomeTripId = verb, view.tripId
            if verb == "come_back" and enabled and driveRecallHint then button.tooltip = driveRecallHint end
            y = y + metrics(detail).buttonHeight + 7
            if not enabled then
                local text = reasonText(reason)
                if not seen[text] then reasons[#reasons + 1], seen[text] = text, true end
            end
        end
    end
    for _, text in ipairs(reasons) do
        y = detail:addInformationLine(panel, y, "UI_SC_Info_Message", text)
    end
    local notice = detail.homeRadioNotice
    if notice and notice.tripId == view.tripId and not radio.pending
        and notice.replyId == (radio.lastReply and radio.lastReply.id) then
        y = detail:addInformationLine(panel, y, "UI_SC_Info_Message",
            tr("UI_SC_HomeTrip_RadioCallRefused", reasonText(notice.reason)))
    elseif radio.lastReply and not radio.pending then
        y = detail:addInformationLine(panel, y, "UI_SC_Info_Message",
            tr("UI_SC_HomeTrip_RadioReply", reasonText(radio.lastReply.reason
                or (radio.lastReply.acknowledged and "home_radio_received" or "home_radio_no_ack"))))
    end
    if view.travelMode == "drive" and (radio.lastReply and radio.lastReply.verb == "come_back"
            and radio.lastReply.acknowledged == true or radio.report and radio.report.state == "returning") then
        y = detail:addInformationLine(panel, y, "UI_SC_Info_Message", tr("UI_SC_HomeTrip_RadioDriveReturning"))
    end
    return y
end

local function cardState(view)
    if view.observed ~= true then
        local report = view.radio and view.radio.report
        if report and type(report.at) == "number" and (not view.lastSeenAt or report.at >= view.lastSeenAt) then
            local text = radioReportText(view.radio)
            if text then return text end
        end
        if view.lastSeenAt then return tr("UI_SC_HomeTrip_LastSeen", clockText(view.lastSeenAt),
            view.lastSeenPlace or tr("UI_SC_HomeTrip_LastKnownPlace"),
            math.floor(tonumber(view.lastSeenDistance) or 0)) end
        return tr("UI_SC_HomeTrip_Away")
    end
    if view.statusText then return view.statusText end
    local state = view.state or view.observedPhase or "walking"
    if state == "blocked" or state == "stopped" then
        return view.blocker and reasonText(view.blocker) or tr("UI_SC_HomeTrip_Blocked")
    end
    if state == "holding" then return tr("UI_SC_HomeTrip_Holding") end
    if state == "stopping" then return tr("UI_SC_HomeTrip_RadioStopping") end
    if view.vehicleState and state ~= "recalling" and state ~= "coming_back" and state ~= "resuming" then
        local carStates = { walking_to_car = "WalkingToCar", boarding_out = "Boarding", boarding_home = "Boarding",
            driving_home = "Driving", driving_out = "Driving", parking_home = "Parking", parking = "Parking", home_wait = "Arriving",
            abandoned = "CarAbandoned" }
        local carKey = carStates[view.vehicleState]
        if carKey == "Driving" and tonumber(view.distance) then
            return tr("UI_SC_HomeTrip_DrivingDistance", math.floor(view.distance + 0.5))
        end
        if carKey then return tr("UI_SC_HomeTrip_" .. carKey, view.vehicleName or tr("UI_SC_HomeTrip_Car")) end
    end
    local keys = { inbound = "Walking", walking = "Walking", home_wait = "Arriving",
        arriving = "Arriving", holding = "Holding", blocked = "Blocked",
        resuming = "Resuming", recalling = "ComingBack", coming_back = "ComingBack",
        resting = "Resting", stopped = "Blocked" }
    local key = keys[state]
    if key == "Walking" and tonumber(view.distance) then
        return tr("UI_SC_HomeTrip_WalkingDistance", math.floor(view.distance + 0.5))
    end
    if key == "Blocked" and view.blocker then return reasonText(view.blocker) end
    return tr("UI_SC_HomeTrip_" .. (key or "Walking"))
end
HomeUI.cardState = cardState

function HomeUI.rosterActivity(view)
    if view and view.observed == true then
        if view.state == "blocked" or view.state == "stopped" then return "UI_SC_HomeTrip_Stopped" end
        if view.state == "recalling" or view.state == "coming_back" then return "UI_SC_HomeTrip_ComingBack" end
        if view.state == "resuming" then return "UI_SC_HomeTrip_Resuming" end
        if view.state == "holding" then return "UI_SC_HomeTrip_Holding" end
        if view.state == "stopping" then return "UI_SC_HomeTrip_RadioStopping" end
        local states = { driving_home = "Driving", driving_out = "Driving",
            boarding_out = "BoardingShort", boarding_home = "BoardingShort", parking_home = "ParkingShort", parking = "ParkingShort",
            home_wait = "Arriving" }
        if states[view.vehicleState] then return "UI_SC_HomeTrip_" .. states[view.vehicleState] end
    end
    return "UI_SC_HomeTrip_Walking"
end

local function addRestockReport(detail, panel, y, summary)
    if not summary then return y end
    local totals, rows = {}, {}
    for _, member in ipairs(summary.members or {}) do
        for category, count in pairs(member.restocked or {}) do
            totals[category] = (totals[category] or 0) + count
        end
    end
    for _, choice in ipairs({ { "food", "Food" }, { "water", "Water" },
            { "medicine", "Medicine" }, { "ammunition", "Ammunition" } }) do
        if (totals[choice[1]] or 0) > 0 then
            rows[#rows + 1] = tr("UI_SC_HomeTrip_RestockCount", totals[choice[1]],
                tr("UI_SC_Expedition_" .. choice[2]))
        end
    end
    if #rows > 0 then
        y = detail:addInformationLine(panel, y, "UI_SC_Info_Message",
            tr("UI_SC_HomeTrip_Restocked", table.concat(rows, ", ")))
    end
    if summary.complete ~= true then
        y = detail:addInformationLine(panel, y, "UI_SC_Info_Message", tr("UI_SC_HomeTrip_RestockPending"))
    elseif #rows == 0 then
        y = detail:addInformationLine(panel, y, "UI_SC_Info_Message", tr("UI_SC_HomeTrip_RestockNone"))
    end
    for _, member in ipairs(summary.members or {}) do
        for category, amount in pairs(member.shortages or {}) do
            y = detail:addInformationLine(panel, y, "UI_SC_Info_Message",
                tr("UI_SC_Expedition_RestockShortage", displayName(member.name or member.id),
                    category, amount))
        end
    end
    return y
end

function HomeUI.buildCard(detail, panel, y, context)
    local home = SC.HomeTrip
    local view = home and home.describe and home.describe(viewer()) or nil
    if not view then return y, false end
    if view.debrief then
        local report = type(view.debrief) == "table" and view.debrief or view
        local arrived = report.endReason == nil or report.endReason == "home"
        local integration = SC.ExpeditionIntegration
        local summary = report.integration and integration and integration.summary
            and integration.summary(report.integration) or nil
        local handoverComplete = summary and summary.complete == true
        local onDuty = handoverComplete and #(summary.members or {}) > 0
        for _, member in ipairs(summary and summary.members or {}) do
            if member.cleanupDone ~= true or member.dutyDone ~= true then
                handoverComplete, onDuty = false, false
            elseif member.dutyReason ~= "base_duty_resumed" then onDuty = false end
        end
        local summaryKey = onDuty and "UI_SC_HomeTrip_DebriefDuty"
            or summary and not handoverComplete and "UI_SC_HomeTrip_DebriefPending"
            or "UI_SC_HomeTrip_Debrief"
        y = detail:addSection(panel, y, arrived and "UI_SC_HomeTrip_Home" or "UI_SC_HomeTrip_CalledOff")
        y = detail:addInformationLine(panel, y, "UI_SC_Info_Message",
            report.summaryText or (arrived and tr(summaryKey, clockText(report.at),
                displayNames(report.memberNames or report.names or view.memberNames))
                or tr("UI_SC_HomeTrip_CalledOff")))
        if report.restockText then y = detail:addInformationLine(panel, y,
            "UI_SC_Info_Message", report.restockText) end
        if #(report.casualties or {}) > 0 then
            y = detail:addInformationLine(panel, y, "UI_SC_Info_Message",
                tr("UI_SC_HomeTrip_Casualties", displayNames(report.casualties)))
        end
        if arrived and report.vehicleState == "abandoned" then
            y = detail:addInformationLine(panel, y, "UI_SC_Info_Message",
                tr("UI_SC_HomeTrip_CarAbandonedDebrief", report.vehicleName or tr("UI_SC_HomeTrip_Car")))
        elseif arrived and report.vehicleState == "home_wait" and report.homeStop then
            y = detail:addInformationLine(panel, y, "UI_SC_Info_Message",
                tr(report.homeStop.kind == "roadside" and "UI_SC_HomeTrip_RoadsideDebrief" or "UI_SC_HomeTrip_ParkingDebrief",
                    report.homeStop.label or tr("UI_SC_HomeTrip_CampRoadside")))
        end
        if arrived and report.vehicleIssue then
            y = detail:addInformationLine(panel, y, "UI_SC_Info_Message",
                tr("UI_SC_HomeTrip_CarIssue", reasonText(report.vehicleIssue)))
        end
        if arrived and summary then
            if (tonumber(summary.trunkPending) or 0) > 0 then
                local roadside = report.homeStop and report.homeStop.kind == "roadside"
                y = detail:addInformationLine(panel, y, "UI_SC_Info_Message",
                    tr(report.vehicleState == "abandoned" and "UI_SC_HomeTrip_AbandonedCargoPending"
                        or roadside and "UI_SC_HomeTrip_RoadsideCargoPending" or "UI_SC_HomeTrip_TrunkPending"))
            end
            local stored = 0
            for _, item in ipairs(summary.items or {}) do
                if item.carrierKind == "trunk" and item.stored == true then stored = stored + 1 end
            end
            if stored > 0 then
                y = detail:addInformationLine(panel, y, "UI_SC_Info_Message", tr("UI_SC_HomeTrip_TrunkStored", stored))
            end
        end
        if arrived then y = addRestockReport(detail, panel, y, summary) end
        addButton(detail, panel, 8, y, math.max(72, panel:getWidth() - 28),
            "UI_SC_HomeTrip_Dismiss", "dismiss", true)
        return y + metrics(detail).buttonHeight + 7, false
    end
    if view.active ~= true then return y, false end
    y = detail:addSection(panel, y, "UI_SC_HomeTrip_Trip")
    y = detail:addInformationLine(panel, y, "UI_SC_Info_Message",
        tr("UI_SC_HomeTrip_Crew", displayNames(view.memberNames), displayName(view.leaderName)))
    if view.at then
        y = detail:addInformationLine(panel, y, "UI_SC_Info_Message",
            tr("UI_SC_HomeTrip_TravelSince", tr(view.travelMode == "straight"
                and "UI_SC_HomeTrip_Way_Straight" or view.travelMode == "drive"
                and "UI_SC_HomeTrip_Way_Drive" or "UI_SC_HomeTrip_Way_Road"), clockText(view.at)))
    end
    y = detail:addInformationLine(panel, y, "UI_SC_Info_Message", cardState(view))
    if view.observed == true and view.vehicleIssue then
        y = detail:addInformationLine(panel, y, "UI_SC_Info_Message",
            tr("UI_SC_HomeTrip_CarIssue", reasonText(view.vehicleIssue)))
    end
    if view.observed == true then
        local radioReport = radioReportText(view.radio)
        if radioReport then y = detail:addInformationLine(panel, y, "UI_SC_Info_Message", radioReport) end
    end
    y = buildRadio(detail, panel, y, view)
    local canRecall = home.canRecall and home.canRecall(viewer())
        or not home.canRecall and view.canRecall == true
    if canRecall then
        addButton(detail, panel, 8, y, math.max(72, panel:getWidth() - 28),
            "UI_SC_HomeTrip_CallOff", "call_off", true)
        y = y + metrics(detail).buttonHeight + 7
    else
        y = detail:addInformationLine(panel, y, "UI_SC_Info_Message", tr("UI_SC_HomeTrip_RecallNear"))
    end
    if SC.UIExpeditions and SC.UIExpeditions.buildViewZoom then
        y = SC.UIExpeditions.buildViewZoom(detail, panel, y)
    end
    if context == "expeditions" then
        y = detail:addInformationLine(panel, y, "UI_SC_Info_Message", tr("UI_SC_HomeTrip_PlanningBlocked"))
    end
    return y, true
end

function HomeUI.buildOrders(detail, panel, y, row)
    local home = SC.HomeTrip
    if not row or not home or not home.isMemberId or not home.isMemberId(row.id) then return y, false end
    local canRecall = home.canRecall and home.canRecall(viewer()) == true
    if canRecall then
        addButton(detail, panel, 8, y, math.max(72, panel:getWidth() - 28),
            "UI_SC_HomeTrip_CallOff", "call_off", true)
        return y + metrics(detail).buttonHeight + 7, true
    end
    return detail:addInformationLine(panel, y, "UI_SC_Info_Message",
        tr("UI_SC_HomeTrip_OrdersAway")), true
end

function HomeUI.viewStructureSignature()
    local home = SC.HomeTrip
    local view = home and home.describe and home.describe(viewer()) or nil
    if not view then return "home:idle" end
    local report = type(view.debrief) == "table" and view.debrief or {}
    local parts = { "home", tostring(view.active), tostring(view.state),
        tostring(view.observed), tostring(view.distance), tostring(view.lastSeenAt),
        tostring(view.lastSeenDistance), tostring(view.canRecall), tostring(view.leaderName),
        tostring(view.blocker), tostring(report.at), tostring(view.debrief ~= nil),
        tostring(view.vehicleState), tostring(view.vehicleName), tostring(view.vehicleIssue),
        tostring(report.vehicleState), tostring(report.vehicleIssue),
        tostring(report.homeStop and report.homeStop.kind), tostring(report.homeStop and report.homeStop.label) }
    local radio = view.radio or {}
    local pending, reply, received = radio.pending or {}, radio.lastReply or {}, radio.report or {}
    for _, value in ipairs({ tostring(view.tripId), tostring(radio.holding), tostring(radio.blocked),
            tostring(pending.id), tostring(pending.verb), tostring(pending.leaderName),
            tostring(reply.id), tostring(reply.verb), tostring(reply.reason), tostring(reply.acknowledged),
            tostring(received.at), tostring(received.place), tostring(received.distance), tostring(received.state),
            tostring(received.holdingAt) }) do
        parts[#parts + 1] = value
    end
    for _, choice in ipairs(radioChoices) do
        local availability = radio.actions and radio.actions[choice[1]] or {}
        parts[#parts + 1] = tostring(availability.enabled)
        parts[#parts + 1] = tostring(availability.reason)
    end
    for _, member in ipairs(report.integration and report.integration.members or {}) do
        parts[#parts + 1] = tostring(member.id)
        parts[#parts + 1] = tostring(member.cleanupDone)
        parts[#parts + 1] = tostring(member.dutyDone)
        parts[#parts + 1] = tostring(member.dutyReason)
        for _, category in ipairs({ "food", "water", "medicine", "ammunition" }) do
            parts[#parts + 1] = tostring(member.restocked and member.restocked[category])
            parts[#parts + 1] = tostring(member.shortages and member.shortages[category])
        end
    end
    for _, item in ipairs(report.integration and report.integration.items or {}) do
        parts[#parts + 1] = tostring(item.nativeId)
        parts[#parts + 1] = tostring(item.stored)
        parts[#parts + 1] = tostring(item.released)
        parts[#parts + 1] = tostring(item.reason)
    end
    return table.concat(parts, ":")
end
