-- SPDX-License-Identifier: MIT
-- Loaded before and after SCUIHomeTrip: first install the small UI fixture,
-- then exercise the actual sheet, selectors, fixed footer and card callbacks.
if SCHomeTripUITestFixture == nil then
    SCHomeTripUITestFixture = { plans = 0, starts = 0, recalls = 0, records = {} }
    local f = SCHomeTripUITestFixture
    function require() end
    UIFont = { Small = 1 }
    local strings = {
        Who = "Who", Leader = "Leader", How = "How", Sheet = "Send home",
        Review = "Review", Send = "Send home", Back = "Back", Dismiss = "Dismiss",
        CallOff = "Call off trip", CalledOff = "Trip home called off.",
        RadioComeBack = "Radio: Come back", RadioHold = "Radio: Hold", RadioStatus = "Radio: Status",
        RadioDriveRecallHint = "Come back stops the car safely, then returns the crew on foot. The car and trunk cargo stay behind.",
        RadioDriveReturning = "The crew will return on foot after stopping safely. The car and trunk cargo stay behind.",
        RadioPushOn = "Radio: Push on", RadioCalling = "Calling %1. Waiting for a reply...",
        RadioReply = "Radio reply: %1", RadioReport = "Radio %1: %2 Near %3.",
        RadioCallRefused = "Call not sent: %1", RadioHoldingSince = "Holding since %1.",
        RadioStopping = "Stopping safely.",
        RadioReportDistance = "Radio %1: %2 Near %3, about %4 m from camp.",
        RadioUnavailable = "No radio link. Check both equipped radios, their power, channel and range.",
        RadioBusy = "Waiting for the current radio call to finish.",
        RadioStale = "The trip changed. Check the current crew before calling again.",
        RadioNoAck = "No reply received. The order has not been confirmed.",
        RadioRecallStopping = "Wait for the car to stop and everyone to get out before holding.",
        RadioReceived = "Report received.", LastKnownPlace = "their last known position",
        TooMany = "Send up to four.", Nobody = "Nobody eligible is following.",
        Planning = "Planning route...", CheckingDeparture = "Checking departure...",
        Unavailable = "The companion view is unavailable.",
        LeaderUnavailable = "%1 cannot lead. Choose an eligible member.",
        SelectionUnavailable = "Selection unavailable", Member = "A companion",
        Way_Road = "Walk, follow roads", Way_Straight = "Walk straight", Way_Drive = "Drive",
        Car = "Car", YourCar = "%1 (your car)", CarChoice = "%1: %2 seats, fuel %3%%",
        CarBlocked = "%1: %2", CarSelectionUnavailable = "%1 is unavailable. Choose a car within 30 m of the leader.",
        NoCars = "No cars within 30 m of the leader.", SeatCheck = "Car check: %1 seats; %2 needed.",
        FuelCheck = "Fuel %1%%; about %2%% needed.", FuelKnown = "Fuel %1%%.", KeyHolder = "Key: %1 has it.",
        RouteDrive = "About %1 m by road. %2 driving.",
        ParkingReview = "Parking: %1. Camp duty unloads the trunk.",
        ParkingExpected = "Expected parking: %1. They check clearance on arrival.",
        ClearanceOnArrival = "They check that the stopping place is clear on arrival.",
        RoadsideReview = "Roadside stop: %1, then walk into camp. The trunk stays loaded until the car is in camp parking.",
        CampRoadside = "the road outside camp", WalkingToCar = "Walking to %1.", Boarding = "Boarding %1.",
        Driving = "Driving home.", DrivingDistance = "Driving home. About %1 m to go.", Parking = "Parking %1.",
        CarAbandoned = "%1 cannot continue. Walking home.", CarIssue = "Car: %1",
        ReviewChanged = "The crew, car or stopping place changed. Review the trip again before sending.",
        ParkingDebrief = "Car parked in %1.", RoadsideDebrief = "Car left at %1.",
        CarAbandonedDebrief = "%1 could not continue. The crew walked home.",
        TrunkPending = "Trunk unloading waits until you are near camp.",
        RoadsideCargoPending = "Move the car into camp parking to unload the trunk.",
        AbandonedCargoPending = "Cargo remains with the car. Recover it and move it into camp parking to unload.",
        TrunkStored = "%1 cargo items stored.",
        PlayerSeated = "You are seated in this car. Get out first.",
        GroupCount = "%1 (%2)", Excluded = "%1 stays: %2",
        GroupCrew = "%1 (%2): %3", CrewReview = "Travellers: %1.",
        RouteRoad = "About %1 m by road. %2 on foot.",
        RouteStraight = "About %1 m straight to camp. %2 on foot.",
        Minutes = "about %1 minutes", Hours = "about %1 hours",
        HalfHour = "about half an hour", OneHour = "about an hour",
        ArrivalReview = "On arrival: hand in surplus and restock, then base duty. This work waits until you are near camp.",
        ViewReview = "The second view follows %1 until they are home. Base Watch and expeditions wait until then.",
        RecallNear = "Follow or Regroup when you are near them to call off the trip.",
        RoadFallback = "No road route found. Walking straight.",
        LongWalk = "Long walk: they may stop to eat, drink or sleep on the way.",
        Crew = "%1. %2 leads.", WalkingDistance = "Walking home. About %1 m to go.",
        Walking = "Walking home.", Arriving = "Arriving at camp.",
        Holding = "Holding.", Blocked = "Stopped on the way home.",
        Resuming = "Resuming the trip home.", ComingBack = "Coming back to you.",
        Resting = "Resting on the way home.", Away = "Away. Last report is unchanged.",
        LastSeen = "Last seen %1 near %2, about %3 m from camp.",
        PlanningBlocked = "Planning is unavailable until they are home.",
        OrdersAway = "On a trip home. Use the radio controls in Squad, or get near them to call off the trip.",
        TravelSince = "%1; left at %2.",
        RestockCount = "%1 %2", Restocked = "Restocked: %1.",
        RestockPending = "Camp work waits until you are near. They hand in surplus and restock, then return to base duty.",
        RestockNone = "Restocked: no supplies collected.",
        Debrief = "Home at %1: %2.", DebriefDuty = "Home at %1: %2. Now on base duty.",
        DebriefPending = "Home at %1: %2. Camp handover pending.", Home = "Home", Trip = "Trip home",
    }
    local function tr(key, ...)
        if key == "UI_SC_Info_Message" then return tostring((...)) end
        if key == "UI_SC_Expedition_Water" then return "Water" end
        local value = strings[string.gsub(key, "^UI_SC_HomeTrip_", "")] or key
        for index, argument in ipairs({ ... }) do
            local replacement = tostring(argument)
            value = string.gsub(value, "%%" .. index, function() return replacement end)
        end
        value = string.gsub(value, "%%%%", function() return "%" end)
        return value
    end
    local function wrap(_, value, maximum)
        local lines, current = {}, ""
        for word in string.gmatch(tostring(value), "%S+") do
            local candidate = current == "" and word or current .. " " .. word
            if #candidate * 8 > maximum and current ~= "" then
                lines[#lines + 1], current = current, word
            else current = candidate end
        end
        if current ~= "" then lines[#lines + 1] = current end
        return lines
    end
    SurvivorCompanion = { UI = { text = tr, wrapText = wrap,
        layoutMetrics = function() return { fontHeight = 16, infoLineHeight = 21, buttonHeight = 28 } end,
        fitText = function(_, value, width)
            if #value * 8 <= width then return value end
            return string.sub(value, 1, math.max(1, math.floor(width / 8) - 3)) .. "..."
        end,
        open = function() return f.root end },
        Registry = { byId = function(id) return f.records[id] end },
        ExpeditionCar = { fieldCandidates = function()
            f.carScans = (f.carScans or 0) + 1
            return f.cars or {}
        end } }
    local player = {}
    f.player, f.halos = player, {}
    function player:setHaloNote(text) f.halos[#f.halos + 1] = text end
    function getSpecificPlayer() return player end
    local function panel(width, height)
        local result = { width = width, height = height, childrenInOrder = {} }
        function result:getWidth() return self.width end
        function result:getHeight() return self.height end
        function result:setHeight(value) self.height = value end
        function result:addChild(child) self.childrenInOrder[#self.childrenInOrder + 1] = child end
        function result:removeChild(child)
            for index, value in ipairs(self.childrenInOrder) do
                if child == value then table.remove(self.childrenInOrder, index) return end
            end
        end
        return result
    end
    f.panel = panel
    ISLabel = {}
    function ISLabel:new(x, y, height, text, r, g, b)
        return setmetatable({ x = x, y = y, height = height, name = text,
            width = #text * 8, r = r, g = g, b = b }, { __index = self })
    end
    function ISLabel:initialise() end
    ISButton = {}
    function ISButton:new(x, y, width, height, text, target, callback)
        return setmetatable({ x = x, y = y, width = width, height = height,
            title = text, target = target, callback = callback }, { __index = self })
    end
    function ISButton:initialise() end
    function ISButton:setEnable(value) self.enable = value end
    ISComboBox = {}
    function ISComboBox:new(x, y, width, height, target, callback)
        return setmetatable({ x = x, y = y, width = width, height = height,
            options = {}, selected = 1, target = target, callback = callback,
            textColor = { r = 1, g = 1, b = 1, a = 1 },
            popup = { doDrawItem = function(self, value)
                f.drawColour = self.parentCombo.textColor.r
                return value + 20
            end } }, { __index = self })
    end
    function ISComboBox:initialise() self.popup.parentCombo = self end
    function ISComboBox:instantiate() end
    function ISComboBox:addOptionWithData(label, data, tooltip)
        self.options[#self.options + 1] = { label = label, data = data, tooltip = tooltip }
    end
    function ISComboBox:getOptionData(index) return self.options[index] and self.options[index].data end
    function f.detail(count)
        f.records = {}
        local detail = panel(234, 493)
        detail.tab, detail.metrics = "groups", SurvivorCompanion.UI.layoutMetrics()
        detail.root = { detail = detail, roster = { items = {} } }
        for index = 1, count do
            local record = { id = "member-" .. index, name = "Crew " .. index,
                actor = {}, recruited = true, group = "alpha", eligible = true }
            f.records[record.id] = record
            detail.root.roster.items[index] = { item = record }
            detail.root.selectedRow = detail.root.selectedRow or record
        end
        f.root = detail.root
        function detail:rebuild() self.rebuilds = (self.rebuilds or 0) + 1 end
        function detail:addInformationLine(target, y, key, value)
            for _, line in ipairs(wrap(1, tr(key, value), target.width - 32)) do
                target:addChild(ISLabel:new(8, y, 16, line))
                y = y + 21
            end
            return y
        end
        function detail:addSection(target, y, key)
            self:addInformationLine(target, y, "UI_SC_Info_Message", tr(key))
            return y + 26
        end
        return detail
    end
    SurvivorCompanion.HomeTrip = {
        roster = function(selection)
            local result = { records = {}, exclusions = {} }
            local selectedCar = selection.vehicle
            if not selectedCar and selection.vehicleSqlId ~= nil then
                for _, candidate in ipairs(f.cars or {}) do
                    if candidate.sqlId == selection.vehicleSqlId then selectedCar = candidate.vehicle break end
                end
            end
            local selectedParked = selection.travelMode == "drive" and selectedCar
                and selectedCar.stationary ~= false
            for _, record in ipairs(selection.records or {}) do
                local registered = f.records[record.id]
                local eligible = registered and registered.actor == record.actor and registered.eligible
                local seatedCar = record.actor and record.actor.vehicle
                local seatedEligible = not seatedCar or selectedParked and seatedCar == selectedCar
                if eligible and seatedEligible then result.records[#result.records + 1] = record
                else result.exclusions[#result.exclusions + 1] = { record = record,
                    name = record.name, reason = seatedEligible and "not_following" or "home_member_seated" } end
            end
            return result
        end,
        eligibility = function(selection)
            local result = SurvivorCompanion.HomeTrip.roster(selection)
            result.blocker = f.blocker or selection.travelMode == "drive" and f.carBlocker
                or #result.records > 4 and "squad_too_large"
                or #result.records == 0 and "roster_empty" or nil
            result.canStart = result.blocker == nil
            return result
        end,
        reviewKey = function(selection)
            return tostring(selection.travelMode or "road") .. ":" .. tostring(selection.vehicleSqlId)
                .. ":" .. tostring(f.carRevision or 0)
                .. ":" .. tostring(f.campRevision or 0)
        end,
        draft = function(selection)
            f.plans = f.plans + 1
            local result = SurvivorCompanion.HomeTrip.eligibility(selection)
            result.distance, result.estimatedHours = 200, 1
            result.requestedTravelMode = selection.travelMode or "road"
            result.routeFallback = f.fallback == true and result.requestedTravelMode == "road"
            result.travelMode = result.routeFallback and "straight" or result.requestedTravelMode
            result.reviewKey = SurvivorCompanion.HomeTrip.reviewKey(selection)
            if selection.travelMode == "drive" then
                result.car, result.homeStop = f.carReview, f.homeStop
            end
            return result
        end,
        start = function(selection, reviewedDraft)
            f.starts, f.startedIds, f.startedActors = f.starts + 1, {}, {}
            f.startedVehicle, f.startedReview = selection.vehicle, reviewedDraft
            if f.startReject then return false, f.startReject end
            if reviewedDraft and reviewedDraft.reviewKey ~= SurvivorCompanion.HomeTrip.reviewKey(selection) then
                return false, "home_review_changed"
            end
            f.startedTravelMode = reviewedDraft and reviewedDraft.travelMode
            for _, record in ipairs(SurvivorCompanion.HomeTrip.roster(selection).records) do
                f.startedIds[#f.startedIds + 1] = record.id
                f.startedActors[#f.startedActors + 1] = record.actor
            end
            return true
        end,
        describe = function() return f.view end,
        canRecall = function() return f.near == true end,
        cancel = function() f.recalls = f.recalls + 1 return true end,
        isMemberId = function(id) return f.view and f.view.active and f.records[id] ~= nil end,
        dismiss = function() f.view = nil end,
    }
    return
end

local f, HomeUI = SCHomeTripUITestFixture, SurvivorCompanion.UIHomeTrip
local function control(panel, field, value)
    for _, child in ipairs(panel.childrenInOrder) do
        if child[field] == value then return child end
    end
end
local function footer(detail, action) return control(detail, "scHomeAction", action) end
local function joinedText(panel)
    local values = {}
    for _, child in ipairs(panel.childrenInOrder) do
        if child.name then values[#values + 1] = child.name end
    end
    return table.concat(values, " ")
end
local function build(detail)
    HomeUI.clearFooter(detail)
    local panel = f.panel(234, 440)
    HomeUI.buildSheet(detail, panel)
    return panel
end

for _, count in ipairs({ 1, 3, 5 }) do
    local detail = f.detail(count)
    local plans = f.plans
    assert(HomeUI.openSheet(count == 1 and { record = detail.root.selectedRow } or { group = "alpha" }))
    local pending = build(detail)
    assert(f.plans == plans and not footer(detail, "send").enable,
        "opening and drawing must keep Send disabled without planning a route")
    assert(control(pending, "scHomeField", "who") and control(pending, "scHomeField", "leaderId")
        and control(pending, "scHomeField", "travelMode"), "the same sheet always has Who, Leader and How")
    assert(#control(pending, "scHomeField", "travelMode").options == 3,
        "phase two offers driving alongside both walking choices")
    assert(HomeUI.update(detail) and f.plans == plans + 1)
    assert(not HomeUI.update(detail) and f.plans == plans + 1, "one invalidation plans once")
    local panel = build(detail)
    assert(f.plans == plans + 1, "rebuilding never replans")
    local send, back = footer(detail, "send"), footer(detail, "back")
    assert(send.enable == (count <= 4), "the actual eligible crew limit disables a group of five")
    assert(back and back.enable and send.y + send.height <= 440 and back.y + back.height <= 440,
        "Back and Send remain visible on the narrow 1280x720 dock")
    assert(send.x + send.width <= 234 and back.x >= 0, "fixed actions fit within the detail panel")
    local text = joinedText(panel)
    assert(string.find(text, "On arrival:", 1, true) and string.find(text, "Base Watch", 1, true)
        and not string.find(text, "...", 1, true), "review prose is fully wrapped without truncation")
    for _, child in ipairs(panel.childrenInOrder) do
        assert(not child.name or child.x + child.width <= 234 - 16, "review lines fit the narrow panel")
    end
    if count == 5 then
        local who = control(panel, "scHomeField", "who")
        local group
        for index, option in ipairs(who.options) do
            if option.data.value == "alpha" then group = index end
        end
        assert(who.options[group].data.disabled and who.options[group].tooltip == "Send up to four.")
        who.popup:doDrawItem(0, { index = group }, false)
        assert(f.drawColour < 0.6 and who.textColor.r == 1, "unavailable crew is greyed only during its native row draw")
        local blocker = control(detail, "scHomeBlocker", true)
        assert(blocker and blocker.r > blocker.g and blocker.tooltip == "Send up to four.",
            "negative control: removing the red blocker must fail even when Send is disabled")
        HomeUI.onButton(detail, send)
        assert(f.starts == 0, "negative control: five eligible companions cannot dispatch")
    end
end

local detail = f.detail(5)
f.records["member-4"].eligible, f.records["member-5"].eligible = false, false
HomeUI.openSheet({ group = "alpha" })
HomeUI.update(detail)
local panel = build(detail)
assert(footer(detail, "send").enable, "a five-person group with only three eligible members can send its eligible crew")
assert(string.find(joinedText(panel), "Crew 4 stays:", 1, true)
    and string.find(joinedText(panel), "Crew 5 stays:", 1, true), "excluded companions are named explicitly")

detail = f.detail(3)
HomeUI.openSheet({ group = "alpha", leaderId = "member-2" })
HomeUI.update(detail)
f.records["member-2"].eligible = false
HomeUI.invalidate(detail)
HomeUI.update(detail)
panel = build(detail)
assert(detail.homeTripSheet.selection.leaderId == "member-2" and not footer(detail, "send").enable,
    "a lost explicit leader must remain selected and blocked")
assert(string.find(footer(detail, "send").tooltip, "Crew 2", 1, true), "the invalid leader blocker names the chosen companion")

detail = f.detail(1)
f.blocker = "unavailable"
HomeUI.openSheet({ record = detail.root.selectedRow })
HomeUI.update(detail)
panel = build(detail)
assert(not footer(detail, "send").enable and control(detail, "scHomeBlocker", true),
    "a backend blocker has both a visible red explanation and a disabled action")
HomeUI.onButton(detail, footer(detail, "send"))
assert(f.starts == 0, "a direct disabled-button callback still cannot start")
f.blocker = nil
HomeUI.invalidate(detail)
HomeUI.update(detail)
panel = build(detail)
local how, before = control(panel, "scHomeField", "travelMode"), f.plans
how.selected = 2
HomeUI.onSelect(detail, how)
assert(f.plans == before and detail.homeTripSheet.pending, "selection changes queue planning outside the callback")
assert(not footer(detail, "send").enable or detail.homeTripSheet.review == nil)
HomeUI.update(detail)
assert(f.plans == before + 1 and detail.homeTripSheet.selection.travelMode == "straight")
HomeUI.onButton(detail, { scHomeAction = "back" })
assert(not detail.homeTripSheet and not detail.homeTripFooter, "Back clears the sheet and fixed footer")
f.fallback = true
HomeUI.openSheet({ record = detail.root.selectedRow })
HomeUI.update(detail)
panel = build(detail)
assert(detail.homeTripSheet.selection.travelMode == "road"
    and detail.homeTripSheet.review.travelMode == "straight"
    and string.find(joinedText(panel), "200 m straight to camp", 1, true)
    and string.find(joinedText(panel), "No road route found", 1, true),
    "road fallback preserves the reviewed request and describes the effective straight route")
HomeUI.onButton(detail, footer(detail, "send"))
assert(f.starts == 0 and detail.homeTripSheet.sendPending, "Send queues departure outside the click callback")
HomeUI.update(detail)
assert(f.starts == 1 and f.startedTravelMode == "straight" and not detail.homeTripSheet,
    "the first Send dispatches the reviewed fallback exactly once and returns to Squad")
f.fallback = false

for _, change in ipairs({
    { name = "excluded member", before = { true, true, true, false }, after = { true, true, false, false },
        ids = "member-1,member-2" },
    { name = "newly eligible member", before = { true, true, false, false }, after = { true, true, true, false },
        ids = "member-1,member-2,member-3" },
    { name = "same-size replacement", before = { true, true, true, false }, after = { true, true, false, true },
        ids = "member-1,member-2,member-4" },
}) do
    detail = f.detail(4)
    for index, eligible in ipairs(change.before) do f.records["member-" .. index].eligible = eligible end
    HomeUI.openSheet({ group = "alpha", leaderId = "member-1" })
    HomeUI.update(detail)
    panel = build(detail)
    local starts, plans = f.starts, f.plans
    assert(footer(detail, "send").enable)
    for index, eligible in ipairs(change.after) do f.records["member-" .. index].eligible = eligible end
    -- No scheduled update, rebuild or explicit invalidation before the click.
    HomeUI.onButton(detail, footer(detail, "send"))
    assert(f.starts == starts and f.plans == plans and detail.homeTripSheet.pending
        and detail.homeTripSheet.review == nil,
        "roster changes between review and Send require a fresh review before dispatch: " .. change.name)
    panel = build(detail)
    assert(not footer(detail, "send").enable and f.plans == plans,
        "changed roster stays disabled without route planning in the click or rebuild")
    assert(HomeUI.update(detail) and f.plans == plans + 1)
    panel = build(detail)
    assert(footer(detail, "send").enable and detail.homeTripSheet.selection.leaderId == "member-1")
    HomeUI.onButton(detail, footer(detail, "send"))
    assert(f.starts == starts and detail.homeTripSheet.sendPending)
    HomeUI.update(detail)
    assert(f.starts == starts + 1 and table.concat(f.startedIds, ",") == change.ids,
        "only the newly reviewed eligible roster dispatches: " .. change.name)
end

-- A context menu owns the identities its group row displayed, including when
-- the Registry reuses an ID before the Home sheet can be opened or confirmed.
do
    detail = f.detail(3)
    local captured = { f.records["member-1"], f.records["member-2"] }
    HomeUI.openSheet({ group = "alpha", records = captured, leaderId = "member-1" })
    assert(#detail.homeTripSheet.selection.records == 2,
        "opening a captured group does not immediately substitute the current group")
    local starts, plans = f.starts, f.plans
    HomeUI.update(detail)
    assert(f.starts == starts and f.plans == plans + 1
        and #detail.homeTripSheet.selection.records == 3,
        "the scheduled preview refreshes changed group membership without dispatching")
    panel = build(detail)
    assert(string.find(joinedText(panel), "Crew 3", 1, true) and footer(detail, "send").enable)
end

for _, replaceInPlace in ipairs({ false, true }) do
    detail = f.detail(2)
    HomeUI.openSheet({ group = "alpha", leaderId = "member-1" })
    HomeUI.update(detail)
    panel = build(detail)
    local original = f.records["member-2"]
    local originalActor, replacement = original.actor, {}
    local starts, plans = f.starts, f.plans
    if replaceInPlace then original.actor = replacement
    else
        f.records[original.id] = { id = original.id, name = original.name,
            actor = replacement, recruited = true, group = "alpha", eligible = true }
    end
    assert(detail.homeTripSheet.selection.records[2].actor == originalActor,
        "the reviewed actor identity survives Registry record mutation")
    HomeUI.onButton(detail, footer(detail, "send"))
    assert(f.starts == starts and f.plans == plans and detail.homeTripSheet.pending,
        "a same-ID actor replacement refreshes the review before sending")
    HomeUI.update(detail)
    panel = build(detail)
    assert(f.starts == starts and f.plans == plans + 1
        and detail.homeTripSheet.selection.records[2].actor == replacement)
    HomeUI.onButton(detail, footer(detail, "send"))
    HomeUI.update(detail)
    assert(f.starts == starts + 1 and f.startedActors[2] == replacement,
        "the replacement actor leaves only after the refreshed roster is confirmed")
end

do
    detail = f.detail(2)
    HomeUI.openSheet({ group = "alpha", leaderId = "member-1" })
    HomeUI.update(detail)
    panel = build(detail)
    local starts = f.starts
    HomeUI.onButton(detail, footer(detail, "send"))
    local departed = f.records["member-2"].actor
    local oldCommands = SurvivorCompanion.Commands
    SurvivorCompanion.Commands = { peekExisting = function(actor)
        return { recruited = true, group = actor == departed and "bravo" or "alpha" }
    end }
    HomeUI.update(detail)
    assert(f.starts == starts and not detail.homeTripSheet.sendPending
        and #detail.homeTripSheet.selection.records == 1,
        "a fresh command group change cancels queued departure even before roster rows refresh")
    SurvivorCompanion.Commands = oldCommands
end

detail = f.detail(1)
HomeUI.openSheet({ record = detail.root.selectedRow })
HomeUI.update(detail)
panel = build(detail)
local starts, plans = f.starts, f.plans
f.blocker = "unavailable"
HomeUI.onButton(detail, footer(detail, "send"))
assert(f.starts == starts and f.plans == plans and detail.homeTripSheet.pending,
    "availability changes between review and Send invalidate the reviewed departure")
HomeUI.update(detail)
panel = build(detail)
assert(not footer(detail, "send").enable and control(detail, "scHomeBlocker", true))
f.blocker = nil
HomeUI.onButton(detail, footer(detail, "send"))
assert(f.starts == starts and detail.homeTripSheet.pending,
    "restored availability still needs a fresh review before dispatch")
HomeUI.update(detail)
panel = build(detail)
assert(footer(detail, "send").enable)
HomeUI.onButton(detail, { scHomeAction = "back" })

-- Drive selection is populated only by the scheduled update. A right-click
-- preselection must survive even when another usable car is closer.
local lockedCar, usableCar, otherCar = {}, {}, {}
f.cars = {
    { vehicle = lockedCar, sqlId = 10, name = "Locked van", distance = 2,
        seats = 4, fuelPercent = 50, canUse = false, reason = "UI_SC_HomeTrip_PlayerSeated" },
    { vehicle = usableCar, sqlId = 20, name = "Estate", distance = 4,
        seats = 4, fuelPercent = 65, canUse = true, yourCar = true },
    { vehicle = otherCar, sqlId = 30, name = "Pickup", distance = 7,
        seats = 3, fuelPercent = 40, canUse = true },
}
f.carReview = { seatCount = 4, neededSeats = 3, fuelPercent = 65, requiredFuelPercent = 8,
    keyHolderName = "Crew 2" }
f.homeStop = { kind = "parking", label = "West parking", provisional = true }
detail = f.detail(3)
local scans, plans = f.carScans or 0, f.plans
HomeUI.openSheet({ group = "alpha", travelMode = "drive" })
build(detail)
assert((f.carScans or 0) == scans and f.plans == plans,
    "opening and drawing drive choices never scan cars or plan routes")
HomeUI.update(detail)
assert(f.carScans == scans + 1 and detail.homeTripSheet.selection.vehicle == usableCar
    and detail.homeTripSheet.selection.vehicleSqlId == 20,
    "Drive initially chooses the nearest usable candidate rather than a nearer disabled car")
panel = build(detail)
local carCombo = control(panel, "scHomeField", "vehicleSqlId")
assert(#carCombo.options == 3 and carCombo:getOptionData(1).disabled
    and carCombo.options[1].tooltip == "You are seated in this car. Get out first."
    and string.find(carCombo.options[2].tooltip, "your car", 1, true),
    "usable and disabled cars retain readable seat/fuel, ownership and blocker details")
local driveText = joinedText(panel)
assert(string.find(driveText, "4 seats; 3 needed", 1, true)
    and string.find(driveText, "Fuel 65%; about 8% needed", 1, true)
    and string.find(driveText, "Key: Crew 2", 1, true)
    and string.find(driveText, "200 m by road", 1, true)
    and string.find(driveText, "driving", 1, true)
    and string.find(driveText, "Expected parking: West parking", 1, true)
    and string.find(driveText, "check clearance on arrival", 1, true),
    "the drive review shows car checks, road ETA and provisional parking without guaranteeing clearance")
assert(footer(detail, "send").enable and footer(detail, "send").y + footer(detail, "send").height <= 440,
    "the drive sheet keeps Send visible at the narrow dock size")
assert(f.carScans == scans + 1 and f.plans == plans + 1,
    "rebuilding a drive review never rescans candidates or replans")
carCombo.selected = 1
HomeUI.onSelect(detail, carCombo)
assert(detail.homeTripSheet.selection.vehicle == usableCar and not detail.homeTripSheet.pending,
    "a disabled car cannot replace the reviewed selection")
local reviewed = detail.homeTripSheet.review
local starts = f.starts
HomeUI.onButton(detail, footer(detail, "send"))
HomeUI.onButton(detail, { scHomeAction = "send" })
panel = build(detail)
assert(f.starts == starts and f.plans == plans + 1 and detail.homeTripSheet.sendPending
    and not footer(detail, "send").enable
    and string.find(footer(detail, "send").tooltip, "Checking departure", 1, true),
    "one Send click visibly queues departure and duplicate callbacks cannot dispatch or plan")
HomeUI.update(detail)
assert(f.starts == starts + 1 and f.startedVehicle == usableCar and f.startedReview == reviewed
    and f.plans == plans + 1 and not detail.homeTripSheet,
    "the scheduled departure passes the exact reviewed car and draft without another UI route plan")

for _, allSeated in ipairs({ true, false }) do
    detail = f.detail(3)
    for index = 1, 3 do
        if allSeated or index == 2 then f.records["member-" .. index].actor.vehicle = usableCar end
    end
    HomeUI.openSheet({ group = "alpha", travelMode = "drive",
        vehicle = allSeated and usableCar or nil, vehicleSqlId = 20 })
    HomeUI.update(detail)
    panel = build(detail)
    assert(footer(detail, "send").enable
        and #control(panel, "scHomeField", "leaderId").options == 3
        and string.find(joinedText(panel), "Travellers: Crew 1, Crew 2, Crew 3.", 1, true)
        and not string.find(joinedText(panel), "stays:", 1, true),
        "the selected parked car keeps every seated traveller in the crew and leader review")
    local who = control(panel, "scHomeField", "who")
    for index, option in ipairs(who.options) do
        assert(not option.data.disabled, "single and group choices retain the selected-car eligibility")
        if option.data.value == "single" then who.selected = index end
    end
    HomeUI.onSelect(detail, who)
    HomeUI.update(detail)
    panel = build(detail)
    assert(footer(detail, "send").enable
        and #control(panel, "scHomeField", "leaderId").options == 1
        and detail.homeTripSheet.selection.vehicleSqlId == 20,
        "switching to a single seated driver preserves the car and drive context")
    who = control(panel, "scHomeField", "who")
    for index, option in ipairs(who.options) do
        if option.data.value == "alpha" then who.selected = index end
    end
    HomeUI.onSelect(detail, who)
    HomeUI.update(detail)
    panel = build(detail)
    local starts = f.starts
    HomeUI.onButton(detail, footer(detail, "send"))
    HomeUI.update(detail)
    assert(f.starts == starts + 1 and table.concat(f.startedIds, ",") == "member-1,member-2,member-3"
        and not detail.homeTripSheet,
        "both all-seated and mixed crews dispatch exactly the travellers shown in the drive review")

    HomeUI.openSheet({ group = "alpha", travelMode = "road", vehicle = usableCar, vehicleSqlId = 20 })
    HomeUI.update(detail)
    panel = build(detail)
    assert(footer(detail, "send").enable == (not allSeated)
        and #detail.homeTripSheet.review.records == (allSeated and 0 or 2)
        and string.find(joinedText(panel), "Crew 2 stays:", 1, true),
        "walking still excludes seated crew even when a parked car is selected")
    HomeUI.onButton(detail, { scHomeAction = "back" })
end

for _, when in ipairs({ "before click", "after click" }) do
    detail = f.detail(3)
    HomeUI.openSheet({ group = "alpha", travelMode = "drive", vehicle = otherCar,
        vehicleSqlId = 30, vehicleName = "Pickup" })
    HomeUI.update(detail)
    panel = build(detail)
    assert(detail.homeTripSheet.selection.vehicle == otherCar,
        "right-click car preselection is retained over the nearest usable car")
    local starts, plans = f.starts, f.plans
    if when == "after click" then HomeUI.onButton(detail, footer(detail, "send")) end
    f.carRevision = (f.carRevision or 0) + 1
    if when == "before click" then
        HomeUI.onButton(detail, footer(detail, "send"))
        assert(detail.homeTripSheet.pending and f.plans == plans,
            "a changed car invalidates the review without planning inside Send")
    end
    HomeUI.update(detail)
    assert(f.starts == starts and f.plans == plans + 1 and not detail.homeTripSheet.sendPending
        and detail.homeTripSheet.selection.vehicle == otherCar,
        "a car change " .. when .. " requires another review and never silently chooses another car")
    HomeUI.onButton(detail, { scHomeAction = "send" })
    detail.tab = "orders"
    HomeUI.update(detail)
    assert(f.starts == starts and not detail.homeTripSheet.sendPending,
        "leaving the sheet cancels a queued departure")
    detail.tab = "groups"
    HomeUI.onButton(detail, { scHomeAction = "back" })
end

detail = f.detail(3)
f.carBlocker = "UI_SC_HomeTrip_PlayerSeated"
HomeUI.openSheet({ group = "alpha", travelMode = "drive", vehicle = otherCar,
    vehicleSqlId = 30, vehicleName = "Pickup" })
f.cars = { f.cars[2] }
HomeUI.update(detail)
panel = build(detail)
carCombo = control(panel, "scHomeField", "vehicleSqlId")
assert(detail.homeTripSheet.selection.vehicleSqlId == 30
    and carCombo:getOptionData(carCombo.selected).disabled and not footer(detail, "send").enable,
    "a missing selected car stays named and blocked instead of switching to a different car")
f.carBlocker = nil
f.homeStop = { kind = "roadside", label = "South road", clearanceOnArrival = true }
HomeUI.invalidate(detail)
HomeUI.update(detail)
panel = build(detail)
assert(string.find(joinedText(panel), "Roadside stop: South road", 1, true)
    and string.find(joinedText(panel), "trunk stays loaded", 1, true)
    and string.find(joinedText(panel), "check that the stopping place is clear", 1, true),
    "roadside review warns that camp parking is required before trunk unloading")
HomeUI.onButton(detail, { scHomeAction = "back" })
f.cars, f.carReview, f.homeStop, f.carRevision = nil, nil, nil, nil

detail = f.detail(3)
HomeUI.openSheet({ group = "alpha", leaderId = "member-1" })
HomeUI.update(detail)
local starts, plans = f.starts, f.plans
HomeUI.onButton(detail, { scHomeAction = "send" })
f.records["member-3"].eligible = false
HomeUI.update(detail)
assert(f.starts == starts and f.plans == plans + 1 and not detail.homeTripSheet.sendPending,
    "a roster change after Send cancels queued departure before returning to the new crew review")
f.startReject = "home_review_changed"
HomeUI.onButton(detail, { scHomeAction = "send" })
HomeUI.update(detail)
assert(f.starts == starts + 1 and detail.homeTripSheet.pending and detail.homeTripSheet.reviewNotice,
    "a final native car or stopping-place change returns to review rather than silently departing")
HomeUI.update(detail)
panel = build(detail)
assert(f.starts == starts + 1 and string.find(joinedText(panel), "Review the trip again", 1, true),
    "a fresh preview after final revalidation still requires another Send click")
f.startReject = nil
HomeUI.onButton(detail, { scHomeAction = "back" })

f.view = { active = true, observed = true, memberNames = { "Crew 1" }, leaderName = "Crew 1",
    distance = 200, state = "walking", at = 14.5, travelMode = "road", canRecall = true }
f.near = false
panel = f.panel(234, 440)
local _, active = HomeUI.buildCard(detail, panel, 7, "expeditions")
assert(active and not control(panel, "scHomeAction", "call_off"),
    "second-view observation and even a stale view.canRecall never grant physical recall authority")
assert(string.find(joinedText(panel), "14:30", 1, true)
    and string.find(joinedText(panel), "Planning is unavailable", 1, true))
HomeUI.onButton(detail, { scHomeAction = "call_off" })
assert(f.recalls == 0, "a remote direct callback cannot recall")
f.near = true
panel = f.panel(234, 440)
HomeUI.buildCard(detail, panel, 7, "groups")
assert(control(panel, "scHomeAction", "call_off"), "physical proximity exposes recall")
HomeUI.onButton(detail, { scHomeAction = "call_off" })
assert(f.recalls == 1)
f.near = false
panel = f.panel(234, 440)
local _, handled = HomeUI.buildOrders(detail, panel, 7, detail.root.selectedRow)
assert(handled and not control(panel, "scHomeAction", "call_off")
    and string.find(joinedText(panel), "radio controls in Squad", 1, true)
    and string.find(joinedText(panel), "get near", 1, true), "remote Orders screen explains radio and physical recall")
for _, state in ipairs({ "walking", "inbound", "home_wait", "holding", "blocked", "resuming", "coming_back", "resting" }) do
    f.view.state = state
    assert(not string.find(HomeUI.cardState(f.view), "UI_SC_", 1, true), "each walking card state has readable text")
end
f.view.travelMode, f.view.vehicleName, f.view.vehicleState, f.view.state = "drive", "Estate", "driving_home", "driving_home"
assert(HomeUI.cardState(f.view) == "Driving home. About 200 m to go."
    and HomeUI.rosterActivity(f.view) == "UI_SC_HomeTrip_Driving",
    "observed drive phase reaches both the trip card and roster activity")
local driveSignature = HomeUI.viewStructureSignature()
f.view.vehicleState, f.view.state = "parking_home", "parking_home"
assert(HomeUI.cardState(f.view) == "Parking Estate." and HomeUI.rosterActivity(f.view) == "UI_SC_HomeTrip_ParkingShort"
    and HomeUI.viewStructureSignature() ~= driveSignature,
    "actual parking_home phase reaches the card and roster and refreshes without a distance change")
f.view.state = "blocked"
assert(HomeUI.cardState(f.view) == "Stopped on the way home."
    and HomeUI.rosterActivity(f.view) == "UI_SC_HomeTrip_Stopped",
    "a blocked trip is never presented as continuing to park or drive")
f.view.state = "recalling"
assert(HomeUI.cardState(f.view) == "Coming back to you.", "recall overrides an old observed car phase")
f.view.state, f.view.vehicleState = "abandoned", "abandoned"
assert(HomeUI.cardState(f.view) == "Estate cannot continue. Walking home.",
    "an abandoned car is distinguished from a parked car")
f.view.observed = false
assert(HomeUI.cardState(f.view) == "Away. Last report is unchanged.",
    "hidden car failures and exact phases do not appear without observation")
f.view.vehicleState = nil
f.view.observed, f.view.state, f.view.distance = false, "blocked", 37
assert(HomeUI.cardState(f.view) == "Away. Last report is unchanged.",
    "unobserved phase and exact distance never appear in the card")
f.view.lastSeenAt, f.view.lastSeenDistance, f.view.lastSeenPlace = 14.25, 200, "Main Street"
assert(HomeUI.cardState(f.view) == "Last seen 14:15 near Main Street, about 200 m from camp.",
    "out-of-sight card uses the dated observed distance rather than the current hidden distance")
f.view = { debrief = { names = { "Crew 1" }, at = 15.25, endReason = "home" } }
panel = f.panel(234, 440)
HomeUI.buildCard(detail, panel, 7)
assert(string.find(joinedText(panel), "15:15: Crew 1", 1, true) and control(panel, "scHomeAction", "dismiss"))
SurvivorCompanion.ExpeditionIntegration = { summary = function(report) return report end }
f.view.debrief.integration = { complete = false, members = { { id = "member-1",
    cleanupDone = false, dutyDone = false, restocked = { water = 2 }, shortages = {} } } }
panel = f.panel(234, 440)
HomeUI.buildCard(detail, panel, 7)
assert(string.find(joinedText(panel), "Restocked: 2 Water.", 1, true)
    and string.find(joinedText(panel), "Camp work waits", 1, true)
    and string.find(joinedText(panel), "Camp handover pending", 1, true)
    and not string.find(joinedText(panel), "Now on base duty", 1, true),
    "debrief distinguishes verified supplies collected from queued restocking")
local signature = HomeUI.viewStructureSignature()
f.view.debrief.integration.members[1].restocked.water = 3
assert(HomeUI.viewStructureSignature() ~= signature, "verified restock progress refreshes the debrief")
local member = f.view.debrief.integration.members[1]
f.view.debrief.integration.complete, member.dutyDone, member.dutyReason = true, true, "base_duty_resumed"
panel = f.panel(234, 440)
HomeUI.buildCard(detail, panel, 7)
assert(not string.find(joinedText(panel), "Now on base duty", 1, true),
    "a completed flag cannot claim base duty while cleanup is unfinished")
member.cleanupDone = true
panel = f.panel(234, 440)
HomeUI.buildCard(detail, panel, 7)
assert(string.find(joinedText(panel), "Now on base duty", 1, true),
    "verified cleanup and duty completion allow the base-duty debrief")
member.dutyReason = "new_player_order"
panel = f.panel(234, 440)
HomeUI.buildCard(detail, panel, 7)
assert(not string.find(joinedText(panel), "Now on base duty", 1, true),
    "a settled obligation superseded by another order never claims base duty")
local report, integration = f.view.debrief, f.view.debrief.integration
report.vehicleState, report.vehicleName = "home_wait", "Estate"
report.homeStop = { kind = "parking", label = "West parking" }
integration.complete, integration.trunkPending = false, 2
integration.items = {
    { nativeId = 100, carrierKind = "trunk", stored = true },
    { nativeId = 101, carrierKind = "trunk", stored = false, released = true },
    { nativeId = 102, carrierKind = "trunk", stored = false },
    { nativeId = 103, carrierKind = "member", stored = true },
}
panel = f.panel(234, 440)
HomeUI.buildCard(detail, panel, 7)
assert(string.find(joinedText(panel), "Car parked in West parking", 1, true)
    and string.find(joinedText(panel), "Trunk unloading waits", 1, true)
    and string.find(joinedText(panel), "1 cargo items stored", 1, true)
    and not string.find(joinedText(panel), "Now on base duty", 1, true),
    "debrief reports actual parking, pending cargo and verified trunk deposits without counting released items")
local cargoSignature = HomeUI.viewStructureSignature()
integration.items[3].stored = true
assert(HomeUI.viewStructureSignature() ~= cargoSignature,
    "a verified trunk receipt refreshes the debrief even when crew duty flags are unchanged")
report.homeStop = { kind = "roadside", label = "South road" }
panel = f.panel(234, 440)
HomeUI.buildCard(detail, panel, 7)
assert(string.find(joinedText(panel), "Car left at South road", 1, true)
    and string.find(joinedText(panel), "Move the car into camp parking", 1, true),
    "an actual roadside arrival keeps trunk unloading conditional on camp parking")
report.vehicleState = "abandoned"
panel = f.panel(234, 440)
HomeUI.buildCard(detail, panel, 7)
assert(string.find(joinedText(panel), "Estate could not continue. The crew walked home", 1, true)
    and string.find(joinedText(panel), "Recover it", 1, true)
    and not string.find(joinedText(panel), "Car left at South road", 1, true)
    and not string.find(joinedText(panel), "Car parked", 1, true),
    "an abandoned car never inherits a planned parking or roadside arrival claim")
report.vehicleState, integration.trunkPending = nil, 0
panel = f.panel(234, 440)
HomeUI.buildCard(detail, panel, 7)
assert(not string.find(joinedText(panel), "Car parked", 1, true)
    and not string.find(joinedText(panel), "Car left at", 1, true),
    "a stopping-place plan without an actual car arrival state is not a parking receipt")
f.view.debrief.endReason = "recalled_nearby"
panel = f.panel(234, 440)
HomeUI.buildCard(detail, panel, 7)
assert(not string.find(joinedText(panel), "base duty", 1, true), "recall debrief never claims camp arrival")
HomeUI.onButton(detail, { scHomeAction = "dismiss" })
assert(f.view == nil)

-- World age starts at zero even when the game starts at 07:00. Clock labels
-- must use the current local offset for departure, observations and history.
local previousGameTime = getGameTime
local currentAge, currentClock = 8, 15
getGameTime = function() return {
    getWorldAgeHours = function() return currentAge end,
    getTimeOfDay = function() return currentClock end,
} end
f.view = { active = true, observed = true, memberNames = { "Crew 1" }, leaderName = "Crew 1",
    distance = 200, state = "walking", at = 8, travelMode = "road" }
panel = f.panel(234, 440)
HomeUI.buildCard(detail, panel, 7)
assert(string.find(joinedText(panel), "left at 15:00", 1, true),
    "departure world age 8 displays local 15:00 after a non-midnight world start")
assert(HomeUI.timeText(1) == "about an hour", "clock offsets never change elapsed travel estimates")
f.view.observed, f.view.lastSeenAt, f.view.lastSeenDistance, f.view.lastSeenPlace = false, 7.5, 200, "Main Street"
assert(HomeUI.cardState(f.view) == "Last seen 14:30 near Main Street, about 200 m from camp.",
    "a historical observation uses its timestamp rather than the current local clock")
currentAge, currentClock, f.view.lastSeenAt = 18, 1, 16.75
assert(HomeUI.cardState(f.view) == "Last seen 23:45 near Main Street, about 200 m from camp.",
    "an observation before midnight keeps its previous-day clock label")
f.view.lastSeenAt = 17.5
assert(HomeUI.cardState(f.view) == "Last seen 00:30 near Main Street, about 200 m from camp.",
    "an observation after midnight wraps with the same world-start offset")
f.view = { debrief = { names = { "Crew 1" }, at = 16.75, endReason = "home" } }
panel = f.panel(234, 440)
HomeUI.buildCard(detail, panel, 7)
assert(string.find(joinedText(panel), "Home at 23:45", 1, true),
    "arrival debrief uses local clock time across midnight")
currentAge, currentClock, f.view.debrief.at = 42, 1, 8
panel = f.panel(234, 440)
HomeUI.buildCard(detail, panel, 7)
assert(string.find(joinedText(panel), "Home at 15:00", 1, true),
    "a debrief from an earlier day retains the original local hour")
getGameTime = function() return { getWorldAgeHours = function() return currentAge end } end
panel = f.panel(234, 440)
HomeUI.buildCard(detail, panel, 7)
assert(string.find(joinedText(panel), "Home at 08:00", 1, true),
    "a missing clock API preserves the safe world-age clock fallback")
getGameTime, f.view = previousGameTime, nil

do
    local home = SurvivorCompanion.HomeTrip
    local oldState, oldRequest, oldReason = home.radioState, home.requestRadio, home.reasonText
    local calls, primary, queuedId = {}, f.player, 0
    local reasons = {
        missing_radio = "You and the leader need equipped two-way radios.",
        radio_off = "The leader's radio is switched off.",
        wrong_channel = "Both radios must use the same channel.",
        out_of_range = "The leader is outside radio range.",
        home_radio_busy = "Waiting for the current radio call to finish.",
        home_radio_stale = "The trip changed. Check the current crew before calling again.",
        home_radio_no_ack = "No reply received. The order has not been confirmed.",
        home_radio_received = "Report received.",
        home_radio_holding = "The crew is holding at the reported position.",
        home_radio_unavailable = "No radio link. Check both equipped radios, their power, channel and range.",
        home_radio_recall_stopping = "Wait for the car to stop and everyone to get out before holding.",
    }
    home.reasonText = function(reason) return reasons[reason] or "Radio order unavailable." end
    home.radioState = function() return f.view and f.view.radio end
    home.requestRadio = function(player, verb, tripId)
        calls[#calls + 1] = { player = player, verb = verb, tripId = tripId }
        if f.radioReject then return false, f.radioReject end
        queuedId = queuedId + 1
        f.view.radio.pending = { id = queuedId, verb = verb, leaderName = f.view.leaderName }
        return true
    end
    local detail = f.detail(3)
    local function readyRadio()
        return { actions = { come_back = { enabled = true }, hold = { enabled = true },
            status = { enabled = true }, push_on = { enabled = true } } }
    end
    local function card()
        local panel = f.panel(234, 440)
        local bottom = HomeUI.buildCard(detail, panel, 7, "groups")
        return panel, bottom
    end
    local function button(panel, verb) return control(panel, "scHomeRadioVerb", verb) end
    local plans, starts, scans, halos, recalls = f.plans, f.starts, f.carScans, #f.halos, f.recalls
    f.near = false
    f.view = { active = true, tripId = "home-session-1", observed = false,
        memberNames = { "Crew 1", "Crew 2", "Crew 3" }, leaderName = "Crew 1",
        distance = 37, state = "blocked", travelMode = "road", radio = readyRadio() }
    f.view.radio = nil
    local unavailable = card()
    for _, verb in ipairs({ "come_back", "hold", "status" }) do
        assert(button(unavailable, verb) and not button(unavailable, verb).enable,
            "Home radio actions remain visible while the link service is unavailable")
    end
    f.view.radio = readyRadio()
    for _, reason in ipairs({ "missing_radio", "radio_off", "wrong_channel", "out_of_range" }) do
        for _, action in pairs(f.view.radio.actions) do action.enabled, action.reason = false, reason end
        local panel, bottom = card()
        for _, verb in ipairs({ "come_back", "hold", "status" }) do
            local item = button(panel, verb)
            assert(item and item.enable == false and item.tooltip == reasons[reason],
                "Home radio keeps every remote action visible with its current link refusal: " .. reason)
            assert(item.x >= 0 and item.x + item.width <= panel.width and item.y + item.height <= bottom,
                "Home radio controls stay inside the narrow docking panel's measured content")
        end
        assert(string.find(joinedText(panel), reasons[reason], 1, true)
            and not string.find(joinedText(panel), "UI_SC_", 1, true),
            "Home radio link refusal is visible and readable without hovering")
        assert(not button(panel, "push_on"), "an unseen blocker does not expose a Push on order")
        HomeUI.onButton(detail, button(panel, "come_back"))
        assert(#calls == 0, "a disabled Home radio callback rechecks current availability")
    end
    f.view.radio = readyRadio()
    f.view.radio.actions.hold = { enabled = false, reason = "home_radio_recall_stopping" }
    local stopping = card()
    assert(button(stopping, "come_back").enable and button(stopping, "status").enable
        and button(stopping, "hold").enable == false
        and button(stopping, "hold").tooltip == reasons.home_radio_recall_stopping,
        "safe recall stopping disables only Hold with a readable wait for unseating")
    HomeUI.onButton(detail, button(stopping, "hold"))
    assert(#calls == 0, "a Hold callback cannot bypass safe recall stopping availability")
    f.view.radio = readyRadio()
    local panel = card()
    local recallButton = button(panel, "come_back")
    assert(recallButton.enable and not control(panel, "scHomeAction", "call_off"),
        "remote radio recall is separate from physical near Call off")
    assert(HomeUI.onButton(detail, recallButton) == true and #calls == 1
        and calls[1].player == primary and calls[1].verb == "come_back"
        and calls[1].tripId == "home-session-1" and f.recalls == recalls,
        "Come back queues only the radio request for the exact reviewed trip")
    assert(#f.halos == halos and f.view.state == "blocked" and not f.view.radio.report,
        "queued Home radio does not announce or invent delivery, a report or a successful recall")
    panel = card()
    for _, verb in ipairs({ "come_back", "hold", "status" }) do
        assert(button(panel, verb).enable == false, "one pending Home radio call disables every radio action")
    end
    assert(string.find(joinedText(panel), "Calling Crew 1. Waiting for a reply", 1, true),
        "Home radio shows the addressed leader and waits for the actual reply")
    HomeUI.onButton(detail, recallButton)
    assert(#calls == 1 and #f.halos == halos, "a repeated or stale click cannot queue a second pending Home call")
    f.view.radio.pending = nil
    f.view.radio.lastReply = { id = 1, verb = "come_back", reason = "home_radio_no_ack", acknowledged = false }
    panel = card()
    assert(string.find(joinedText(panel), "No reply received", 1, true)
        and not string.find(joinedText(panel), "Call not sent", 1, true)
        and not string.find(HomeUI.cardState(f.view), "Coming back", 1, true),
        "a native unacknowledged reply supersedes an older busy notice and never appears as coming back")
    -- Replace the trip while its old button remains reachable. The new trip
    -- must not receive an order intended for the previous leader/session.
    f.view.tripId, f.view.radio = "home-session-2", readyRadio()
    HomeUI.onButton(detail, recallButton)
    assert(#calls == 1 and detail.homeRadioNotice.reason == "home_radio_stale",
        "a stale Home radio button refuses a replacement trip before requesting a call")
    panel = card()
    local statusButton = button(panel, "status")
    f.view.radio.actions.status.enabled, f.view.radio.actions.status.reason = false, "out_of_range"
    HomeUI.onButton(detail, statusButton)
    assert(#calls == 1 and detail.homeRadioNotice.reason == "out_of_range",
        "a link that changes after rendering is rechecked before Home radio queues")
    f.view.radio = readyRadio()
    f.radioReject = "home_radio_stale"
    panel = card()
    HomeUI.onButton(detail, button(panel, "status"))
    assert(#calls == 2 and detail.homeRadioNotice.reason == "home_radio_stale" and #f.halos == halos,
        "a final backend radio refusal remains readable and never emits a success note")
    f.radioReject = nil
    f.view.radio.blocked = true
    panel = card()
    assert(button(panel, "push_on") and button(panel, "hold"),
        "a known blocked report exposes both Push on and Hold")
    f.view.radio.blocked, f.view.radio.holding = false, true
    panel = card()
    assert(button(panel, "push_on"), "an accepted Hold exposes Push on for normal resumption")
    for _, verb in ipairs({ "hold", "status", "push_on" }) do
        f.view.radio = readyRadio()
        f.view.radio.holding = verb == "push_on"
        panel = card()
        local before = #calls
        assert(HomeUI.onButton(detail, button(panel, verb)) == true and #calls == before + 1
            and calls[#calls].verb == verb and calls[#calls].tripId == "home-session-2"
            and #f.halos == halos, "each Home radio action queues its exact verb without claiming acknowledgement: " .. verb)
        HomeUI.onButton(detail, button(panel, verb))
        assert(#calls == before + 1, "a second click cannot duplicate a queued Home radio verb: " .. verb)
    end
    f.view.radio.pending = nil
    f.view.observed, f.view.state, f.view.vehicleState = true, "holding", "driving_home"
    assert(HomeUI.cardState(f.view) == "Holding."
        and HomeUI.rosterActivity(f.view) == "UI_SC_HomeTrip_Holding",
        "actual holding overrides an old driving phase on both Home surfaces")
    f.view.state = "stopping"
    assert(HomeUI.cardState(f.view) == "Stopping safely."
        and HomeUI.rosterActivity(f.view) == "UI_SC_HomeTrip_RadioStopping",
        "actual safe stopping overrides an old driving phase on both Home surfaces")
    f.view.observed, f.view.state = false, "walking"
    f.view.radio.report = { at = 14.5, state = "holding", place = "Main Street", distance = 200 }
    f.view.radio.lastReply = { id = 2, verb = "status", reason = "home_radio_received", acknowledged = true }
    detail.homeRadioNotice = nil
    panel = card()
    assert(HomeUI.cardState(f.view) == "Radio 14:30: Holding. Near Main Street, about 200 m from camp."
        and string.find(joinedText(panel), "Radio reply: Report received", 1, true),
        "an acknowledged Status shows only the dated reported position, distance and state")
    f.view.radio.report.holdingAt = 14.25
    assert(string.find(HomeUI.cardState(f.view), "Holding since 14:15", 1, true),
        "a later radio Status retains the actual accepted Hold time")
    for _, state in ipairs({ "stopping", "returning", "driving", "blocked", "walking" }) do
        f.view.radio.report.state = state
        local text = HomeUI.cardState(f.view)
        assert(not string.find(text, "UI_SC_", 1, true) and not string.find(text, "Report received", 1, true),
            "each actual production radio report state has meaningful readable text: " .. state)
    end
    f.view.radio.report.state = "holding"
    f.view.lastSeenAt, f.view.lastSeenPlace, f.view.lastSeenDistance = 14.75, "Camp Road", 100
    assert(HomeUI.cardState(f.view) == "Last seen 14:45 near Camp Road, about 100 m from camp.",
        "a newer direct observation takes precedence over an older radio report")
    f.view.lastSeenAt, f.view.radio.report.distance = nil, nil
    assert(not string.find(HomeUI.cardState(f.view), "37", 1, true)
        and not string.find(HomeUI.cardState(f.view), "0 m", 1, true),
        "a radio report without a distance never substitutes the hidden runtime distance or a fabricated zero")
    local signature = HomeUI.viewStructureSignature()
    f.view.radio.actions.hold.reason = "radio_off"
    assert(HomeUI.viewStructureSignature() ~= signature, "radio availability changes refresh the Home card")
    signature = HomeUI.viewStructureSignature()
    f.view.radio.lastReply.id = 3
    assert(HomeUI.viewStructureSignature() ~= signature, "a new radio reply refreshes the Home card")
    signature = HomeUI.viewStructureSignature()
    f.view.radio.pending = { id = 3, verb = "status", leaderName = "Crew 1" }
    assert(HomeUI.viewStructureSignature() ~= signature, "a queued Home radio call refreshes the waiting state")
    f.near = true
    panel = card()
    assert(control(panel, "scHomeAction", "call_off").enable == true,
        "radio busy does not remove the independently authorized physical near recall")
    f.view.travelMode, f.view.radio = "drive", readyRadio()
    panel = card()
    local driveHint = "Come back stops the car safely, then returns the crew on foot. The car and trunk cargo stay behind."
    assert(string.find(joinedText(panel), driveHint, 1, true)
        and button(panel, "come_back").tooltip == driveHint,
        "Drive radio Come back discloses the walk back and retained trunk cargo before clicking")
    f.view.radio.actions.come_back.enabled, f.view.radio.actions.come_back.reason = false, "out_of_range"
    panel = card()
    assert(button(panel, "come_back").tooltip == reasons.out_of_range,
        "a disabled Drive recall keeps its current link refusal as the tooltip")
    f.view.radio = readyRadio()
    f.view.radio.pending = { id = 4, verb = "come_back", leaderName = "Crew 1" }
    panel = card()
    assert(not string.find(joinedText(panel), "The crew will return on foot", 1, true),
        "pending Drive radio recall does not claim the return order was accepted")
    f.view.radio.pending = nil
    f.view.radio.lastReply = { id = 4, verb = "come_back", acknowledged = false, reason = "home_radio_no_ack" }
    panel = card()
    assert(not string.find(joinedText(panel), "The crew will return on foot", 1, true),
        "unacknowledged Drive radio recall does not claim a walk back")
    f.view.radio.lastReply.acknowledged = true
    f.view.radio.lastReply.reason = "home_radio_received"
    panel = card()
    assert(string.find(joinedText(panel), "The crew will return on foot after stopping safely", 1, true)
        and not string.find(joinedText(panel), "cargo delivered", 1, true),
        "acknowledged Drive recall explains the safe stop and walk without claiming cargo delivery")
    f.view.radio.lastReply = { id = 5, verb = "status", acknowledged = true, reason = "home_radio_received" }
    f.view.radio.report = { at = 15, state = "returning", place = "Main Street", distance = 200 }
    panel = card()
    assert(string.find(joinedText(panel), "The crew will return on foot", 1, true),
        "a later acknowledged returning Status preserves the Drive recall disclosure")
    f.view.travelMode = "road"
    panel = card()
    assert(not string.find(joinedText(panel), "trunk cargo stay behind", 1, true)
        and button(panel, "come_back").tooltip == "Radio: Come back",
        "walking radio recall keeps its existing wording without a car claim")
    assert(f.plans == plans and f.starts == starts and f.carScans == scans,
        "building and clicking Home radio controls never plans routes or dispatches a home trip")
    home.radioState, home.requestRadio, home.reasonText = oldState, oldRequest, oldReason
    f.view, f.near = nil, false
end
print("HOME_TRIP_UI_PASS")
