-- SPDX-License-Identifier: MIT
-- Uses real SCUI.describeEntry/projectExpeditionRow, loaded by the native UI
-- fixture runner. The card's view knowledge must reach roster facts without
-- becoming physical Follow/Regroup authority or revealing distant followers.
local SC, UI = SurvivorCompanion, SurvivorCompanion.UI
local previous = { home = SC.HomeTrip, expedition = SC.ExpeditionPrototype,
    view = SC.ViewSession, commands = SC.Commands, registry = SC.Registry,
    names = SC.Names, players = getSpecificPlayer, homeUi = SC.UIHomeTrip,
    field = SC.FieldWork, positioning = SC.Positioning }
local primary = {}
local function actor(name, health, distance)
    return { getFullName = function() return name end,
        getBodyDamage = function() return { getHealth = function() return health end } end,
        distance = distance }
end
local leader = actor("Home One", 86, 162)
local follower = actor("Home Two", 72, 180)
function primary:DistTo(subject) return subject.distance end
local records = {
    leader = { id = "home-leader", actor = leader, recruited = true, group = "alpha" },
    follower = { id = "home-follower", actor = follower, recruited = true, group = "alpha" },
}
local active = { leader = { id = records.leader.id, actor = leader } }
local slot, owner, physicalNear = leader, "expedition", false
local homeView = { observed = true }
local reads = {}
getSpecificPlayer = function(index) return index == 0 and primary or index == 1 and slot or nil end
SC.Names = nil
SC.Registry = { byId = function(id)
    return id == records.leader.id and records.leader or id == records.follower.id and records.follower or nil
end }
SC.Commands = { issue = function() error("an observation cannot dispatch an order") end,
    describe = function(id, player)
        assert(player == primary)
        reads[id] = (reads[id] or 0) + 1
        return { recruited = true, available = true, alive = true, group = "alpha" }
    end }
SC.ExpeditionPrototype = {
    isMemberId = function(id) return id == records.leader.id or id == records.follower.id end,
    playerCanObserve = function(subject, player) return physicalNear and subject == leader and player == primary end,
    memberName = function(id) return id == records.leader.id and "Home One" or "Home Two" end,
}
SC.ViewSession = { owner = function() return owner end }
SC.HomeTrip = {
    current = function() return active end,
    isMemberId = function(id) return active ~= nil and SC.ExpeditionPrototype.isMemberId(id) end,
    describe = function() return homeView end,
    canRecall = function(player) return physicalNear and player == primary, "home_out_of_earshot" end,
    reasonText = function(reason) return reason end,
}

local row = UI.describeEntry(records.leader, primary)
assert(row.actor == leader and row.health == 86 and row.distance == 162 and row.available == true,
    "the home leader's joined second view preserves measured health and distance in the roster")
assert(reads[records.leader.id] == 1 and row.expeditionMember
    and row.order == "UI_SC_HomeTrip_GoingHome" and row.activity == "UI_SC_HomeTrip_Walking",
    "observed home facts keep the traveller presentation")
local homeUi = SC.UIHomeTrip
homeView.vehicleState = "driving_home"
SC.UIHomeTrip = { rosterActivity = function(view)
    assert(view == homeView, "roster phase uses the observation-filtered home view model")
    return "UI_SC_HomeTrip_Driving"
end }
row = UI.describeEntry(records.leader, primary)
assert(row.activity == "UI_SC_HomeTrip_Driving" and row.health == 86 and row.distance == 162,
    "an observed home driver's roster row uses the drive phase while retaining measured facts")
SC.UIHomeTrip, homeView.vehicleState = homeUi, nil
assert(not SC.ExpeditionPrototype.playerCanObserve(leader, primary)
    and not UI.commandAvailability(row, "regroup", nil),
    "second-view roster facts never grant a remote physical recall")
local hidden = UI.describeEntry(records.follower, primary)
assert(hidden.actor == nil and hidden.health == nil and hidden.distance == nil
    and hidden.activity == "UI_SC_HomeTrip_WithGroup" and reads[records.follower.id] == nil,
    "a distant follower does not inherit the leader camera's health or location observation")

-- Exercise the actual roster draw: a hidden traveller gets one localized
-- Away summary, while an observed expedition leader keeps measured values.
do
    local originalText=UI.text
    UI.text=function(key,first,second)
        if key=="UI_SC_Value_Unknown" then return "Unknown" end
        if key=="UI_FriendState_Away" then return "Away" end
        if key=="UI_SC_Value_Health" then return tostring(first).."%" end
        if key=="UI_SC_Value_Distance" then return tostring(first).." meters" end
        if key=="UI_SC_Roster_HealthDistance" then return first.." | "..second end
        return key
    end
    for _,case in ipairs({{}, {value=math.huge}, {value=-math.huge}, {value=0/0}, {value="unavailable"}}) do
        assert(UI.healthText(case.value)=="Unknown" and UI.distanceText(case.value)=="Unknown",
            "missing or nonfinite roster values have no attached percent or distance units")
    end
    assert(UI.healthText(86)=="86%" and UI.distanceText(162)=="162.0 meters",
        "known finite roster values retain their existing units and precision")
    local drawn={}
    local roster=setmetatable({selected=0,metrics={rosterItemHeight=90,lineHeight=20}},
        {__index=assert(BasePolicyFixture.classes.SCUIRoster)})
    function roster:getWidth() return 420 end
    function roster:drawRect() end
    function roster:drawRectBorder() end
    function roster:drawText(text) drawn[#drawn+1]=text end
    roster:doDrawItem(0,{item=hidden,index=1},false)
    assert(drawn[2]=="Away", "the actual hidden follower row renders the existing translated Away summary")
    drawn={}
    roster:doDrawItem(0,{item=row,index=1},false)
    assert(drawn[2]=="86% | 162.0 meters",
        "an observed expedition member keeps on-screen health and distance rather than being labeled Away")
    UI.text=originalText
end

slot = nil
hidden = UI.describeEntry(records.leader, primary)
assert(hidden.health == nil and hidden.distance == nil, "a released or pending home view reveals no live roster facts")
slot, owner = leader, "base_watch"
hidden = UI.describeEntry(records.leader, primary)
assert(hidden.health == nil and hidden.distance == nil, "a different view owner cannot supply home roster observation")
owner, slot = "expedition", follower
hidden = UI.describeEntry(records.leader, primary)
assert(hidden.health == nil and hidden.distance == nil, "a mismatched second-slot actor is not observation of the old home leader")
active.leader = { id = records.follower.id, actor = follower }
row = UI.describeEntry(records.follower, primary)
assert(row.health == 72 and row.distance == 180,
    "after a home leader handoff only the newly joined leader supplies live roster facts")
assert(not UI.homeTripViewObserves(follower, records.follower.id, {}),
    "home view observation belongs to the primary viewer only")

active, slot = nil, leader
hidden = UI.describeEntry(records.leader, primary)
assert(hidden.health == nil and hidden.distance == nil,
    "ordinary expeditions keep their existing roster observation boundary")
physicalNear = true
row = UI.describeEntry(records.leader, primary)
assert(row.health == 86 and row.distance == 162, "physical observation still supplies the existing expedition roster facts")

-- The saved field-work status has no group owner. A selected home traveller
-- must not inherit its controls, while other companions retain that access.
local fieldReads, rows = 0, {}
SC.FieldWork = { status = function()
    fieldReads = fieldReads + 1
    return { kind = "chop", phase = "paused", completed = 2, carId = 46, blocker = "car_trunk_full" }
end }
SC.Positioning = nil
SC.UIHomeTrip = { buildCard = function(_, _, y) rows.homeCard = true return y + 20, true end,
    addGroupOrder = function(_, _, y) return y + 20 end }
local detail = setmetatable({ root = {} }, { __index = BasePolicyFixture.classes.SCUIDetail })
function detail:addSection(_, y) return y + 20 end
function detail:addInformationLine(_, y, key) rows[key] = true return y + 20 end
function detail:addCommand(_, y, _, command) rows[command] = true return y + 20 end
function detail:addCommandSelector(_, y) return y + 20 end
function detail:addSignal(_, y) return y + 20 end
active = { leader = { id = records.leader.id, actor = leader } }
detail.root.selectedRow = records.leader
detail:buildGroups({}, records.leader)
assert(rows.homeCard and fieldReads == 0 and not rows.UI_SC_Field_Status
    and not rows.stop_field_work and not rows.resume_field_work,
    "selected home travellers never show an unrelated global field-work status or Stop/Resume controls")
rows = {}
local other = { id = "other-member", actor = actor("Other Crew", 90, 1), recruited = true, group = "bravo" }
detail.root.selectedRow = other
detail:buildGroups({}, other)
assert(fieldReads == 1 and rows.UI_SC_Field_Status and rows.stop_field_work and rows.resume_field_work,
    "other companions retain global field-work status and controls while a home trip is active")

active = nil
local pendingHome = { [records.leader.id] = true }
SC.ExpeditionPrototype.pendingHomeMember = function(id) return pendingHome[id] == true end
rows = {}
local unavailable = { id = records.leader.id, recruited = true, available = false, group = "alpha" }
detail.root.selectedRow = unavailable
detail:buildGroups({}, unavailable)
assert(fieldReads == 1 and not rows.UI_SC_Field_Status and not rows.stop_field_work and not rows.resume_field_work,
    "selected pending home crew hide unrelated field work after the active trip has ended")
rows = {}
detail.root.selectedRow = other
detail:buildGroups({}, other)
assert(fieldReads == 2 and rows.UI_SC_Field_Status and rows.stop_field_work and rows.resume_field_work,
    "pending home handover leaves unrelated companions' field-work controls available")
pendingHome[records.leader.id] = false
rows = {}
detail.root.selectedRow = records.leader
detail:buildGroups({}, records.leader)
assert(fieldReads == 3 and rows.UI_SC_Field_Status and rows.stop_field_work and rows.resume_field_work,
    "finished home handover restores the selected companion's original field-work controls")

SC.HomeTrip, SC.ExpeditionPrototype, SC.ViewSession = previous.home, previous.expedition, previous.view
SC.Commands, SC.Registry, SC.Names, getSpecificPlayer = previous.commands, previous.registry, previous.names, previous.players
SC.UIHomeTrip, SC.FieldWork, SC.Positioning = previous.homeUi, previous.field, previous.positioning
SC_TEST_REPORT = (SC_TEST_REPORT or "") .. "; Home observation PASS: exact viewed leader has live facts; hidden followers, foreign views and physical recall remain guarded"
