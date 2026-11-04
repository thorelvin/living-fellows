-- SPDX-License-Identifier: MIT
-- Real quota accounting + incremental navigation at the highest load tier.
local SC, checks = SurvivorCompanion, 0
local U, N, Perf = SC.GameplayUtil, SC.Navigation, SC.Performance
local function check(value, message)
    checks = checks + 1
    assert(value, "navigation liveness check " .. checks .. ": " .. message)
end
local current, edgeCost = 100000, 4
function getTimestampMs() return current end
Perf._setClock(function() return current end)
SC.Config._values.performanceLoadEvaluationFrames = 15
SC.Config._values.performanceLoadChangeCooldownFrames = 15
SC.Config._values.performanceNavigationNodesPerFrame = 64
SC.Config._values.performanceUrgentUnitFloor = 96
SC.Config._values.navigationSliceBudgetMs = 3
Perf.reset()
for _ = 1, 45 do Perf.beginFrame(3, current) Perf.endFrame(10) end
check(Perf.loadLevel() == 3, "the fairness regression exercises actual load tier3")
local grid = {}
local function square(x, y)
    if x < 0 or x > 15 or y < 0 or y > 15 then return nil end
    local key = x .. ":" .. y
    if grid[key] then return grid[key] end
    local value = { x = x, y = y, z = 0 }
    function value:getX() return self.x end
    function value:getY() return self.y end
    function value:getZ() return self.z end
    function value:getObjects() return {} end
    function value:getSpecialObjects() return {} end
    function value:getMovingObjects() return {} end
    function value:isFree() return true end
    function value:isSolid() return false end
    function value:isSolidTrans() return false end
    function value:TreatAsSolidFloor() return true end
    grid[key] = value
    return value
end
local function actor(id, x, y)
    local value = { __class = "IsoPlayer", x = x + 0.5, y = y + 0.5, z = 0,
        square = square(x, y), data = { SC_Id = id } }
    function value:getSquare() return self.square end
    function value:getCurrentSquare() return self.square end
    function value:getModData() return self.data end
    function value:isDead() return false end
    return value
end
U.gridSquare = function(x, y, z) return (z or 0) == 0 and square(x, y) or nil end
U.stop = function() return true end
U.move = function(value, _, intent) value.lastIntent = intent return true end
SC.NativeActions.stopDirect = function() return true end
SC.Topology.classifyEdge = function()
    current = current + edgeCost
    return { traversable = true, cost = 1, affordance = "open" }
end
local critical, ordinary = actor("sc-nav-critical", 0, 0), actor("sc-nav-ordinary", 0, 2)
Perf.beginFrame(3, current)
local before = current
local criticalOkay, criticalReason = N.request(critical, square(12, 0), "walk",
    { action = "combat_approach", urgent = true })
local criticalState = N.peek(critical)
local criticalElapsed = current - before
check(criticalOkay and criticalReason == "path_searching"
        and criticalState.pathSearch.route.search.expanded == 1 and criticalElapsed <= 4,
    "a critical3ms slice uses one expansion with only one indivisible-edge overrun")
local ordinaryOkay, ordinaryReason = N.request(ordinary, square(12, 2), "walk",
    { action = "ordinary_route", stealthAvoidance = false })
local ordinaryState = N.peek(ordinary)
check(ordinaryOkay and ordinaryReason == "path_searching"
        and ordinaryState.pathSearch.route.search.expanded == 1,
    "the reserved ordinary decision can plan in the same frame after an urgent96-unit claim used one")
check(Perf.claimUnits("navigation", 220, false) == 20,
    "only the two consumed nodes remain charged against the load3 allowance of22")
Perf.endFrame(current - before)

-- Re-enter the same pending node after four seconds per dispatch. Processing
-- neighbors is real progress even though no new node has been expanded.
local frontier = ordinaryState.pathSearch.route
local startProgress = ordinaryState.pathSearch.progressAt
current = current + 4000
Perf.beginFrame(3, current)
N.request(ordinary, square(12, 2), "walk", { action = "ordinary_route", stealthAvoidance = false })
check(ordinaryState.pathSearch and ordinaryState.pathSearch.route == frontier
        and ordinaryState.pathSearch.route.search.expanded == 1
        and ordinaryState.pathSearch.progressAt > startProgress,
    "pending edge continuation renews the progress lease without a new expansion")
check(Perf.claimUnits("navigation", 220, false) == 21,
    "a substantive zero-new-node continuation is charged one unit rather than free CPU")
Perf.endFrame(4)
current = current + 4000
Perf.beginFrame(3, current)
N.request(ordinary, square(12, 2), "walk", { action = "ordinary_route", stealthAvoidance = false })
check(ordinaryState.pathSearch and ordinaryState.pathSearch.route == frontier
        and current - ordinaryState.pathSearch.startedAt > 6500,
    "a genuinely advancing frontier survives beyond the idle lease instead of restarting")
Perf.endFrame(4)

-- Finish A* in the first dispatch, then make each evaluation edge expensive.
-- The completed search reports usedNodes0 on continuation while its scoring
-- cursor still advances and must renew exactly the same lease.
local evaluator = actor("sc-nav-evaluation", 0, 5)
SC.Topology.classifyEdge = function()
    local state = N.peek(evaluator)
    local route = state and state.pathSearch and state.pathSearch.route
    if route and route.search and route.search.complete then current = current + 4 end
    return { traversable = true, cost = 1, affordance = "open" }
end
Perf.beginFrame(3, current)
N.request(evaluator, square(10, 5), "walk",
    { action = "evaluation_route", stealthAvoidance = false })
local evaluationState = N.peek(evaluator)
local evaluationRoute = evaluationState.pathSearch and evaluationState.pathSearch.route
check(evaluationRoute and evaluationRoute.search.complete and evaluationRoute.pendingEvaluation,
    "the fixture reaches real completed-path evaluation under the slice deadline")
Perf.endFrame(4)
for _ = 1, 2 do
    local previousIndex = evaluationRoute.pendingEvaluation.index
    local previousProgress = evaluationState.pathSearch.progressAt
    current = current + 4000
    Perf.beginFrame(3, current)
    N.request(evaluator, square(10, 5), "walk",
        { action = "evaluation_route", stealthAvoidance = false })
    check(evaluationState.pathSearch and evaluationState.pathSearch.route == evaluationRoute
            and evaluationRoute.pendingEvaluation.index > previousIndex
            and evaluationState.pathSearch.progressAt > previousProgress,
        "completed-path evaluation progress renews the same frontier lease")
    check(Perf.claimUnits("navigation", 220, false) == 21,
        "completed-path scoring with zero expansions still consumes one quota unit")
    Perf.endFrame(4)
end
check(N._noteSearchSliceProgress({ route = {}, lastExpanded = 0 }, 0, 0, current) == false,
    "an untouched deadline yield is not fabricated search progress")

-- Claims cannot be settled twice, forged, or carried into a later frame.
Perf.beginFrame(3, current)
local granted, receipt = Perf.claimUnits("navigation", 10, false, true)
check(granted == 10 and Perf.claimUnits("navigation", 5, false) == 5,
    "a tracked claim coexists with another caller's reservation")
check(Perf.settleUnits(receipt, 2) == true and Perf.settleUnits(receipt, 0) == false
        and Perf.settleUnits({}, 0) == false,
    "only an issued receipt can refund its unused allowance exactly once")
check(Perf.claimUnits("navigation", 220, false) == 15,
    "settling one reservation cannot refund the other caller's five units")
Perf.endFrame(3)
Perf.beginFrame(3, current)
local _, expired = Perf.claimUnits("navigation", 10, false, true)
Perf.endFrame(3)
Perf.beginFrame(3, current)
Perf.claimUnits("navigation", 5, false)
check(Perf.settleUnits(expired, 0) == false
        and Perf.claimUnits("navigation", 220, false) == 17,
    "an old frame's receipt cannot alter a new frame's charged work")
Perf.endFrame(3)

-- Collision steering can cross a source-tile boundary while the planner is
-- stationary. Those nudges must not replace a useful same-owner frontier.
SC.Config._values.navigationProvisionalStepping = false
SC.Topology.classifyEdge = function()
    current = current + 4
    return { traversable = true, cost = 1, affordance = "open" }
end
local nudged = actor("sc-nav-crowd-drift", 3, 8)
local driftGoal = square(14, 8)
local function requestDrift(value, goal, intent)
    current = current + 100
    Perf.beginFrame(3, current)
    local accepted, reason = N.request(value, goal, "walk", intent or { action = "drift_route" })
    Perf.endFrame(4)
    return accepted, reason
end
requestDrift(nudged, driftGoal)
local driftState = N.peek(nudged)
local originalPending = driftState.pathSearch
check(originalPending ~= nil, "the crowd fixture begins with an actual sliced search")
for _, point in ipairs({ {4,8}, {3,9}, {2,8}, {3,7}, {4,9}, {3,8},
        {4,8}, {3,9}, {2,8}, {3,7}, {4,9}, {3,8} }) do
    nudged.x, nudged.y, nudged.square = point[1] + 0.5, point[2] + 0.5,
        square(point[1], point[2])
    requestDrift(nudged, driftGoal)
    check(driftState.pathSearch == originalPending,
        "one-tile crowd nudges preserve the exact original frontier")
end
check(driftState.pathSearch.route.search.expanded > 1 and driftState.routeReplanCount == 1,
    "retained drift accumulates work instead of repeatedly paying for its first node")
nudged.x, nudged.y, nudged.square = 5.5, 8.5, square(5,8)
requestDrift(nudged, driftGoal)
check(driftState.pathSearch ~= originalPending
        and driftState.pathSearch.route.startSquare == nudged.square,
    "two-tile displacement restarts from the actor rather than cumulatively walking the anchor away")
local newPending = driftState.pathSearch
check(N._searchSourceIdentity(driftState, {x=5,y=8,z=1}) ~= newPending.anchorKey,
    "floor changes cannot retain a nearby old-floor source")
driftState.provisionalAdvances = 1
check(N._searchSourceIdentity(driftState, square(8,8)) == newPending.anchorKey,
    "one intentional provisional pulse retains a source inside its configured reach")
check(N._searchSourceIdentity(driftState, square(9,8)) ~= newPending.anchorKey
        and N._searchSourceIdentity(driftState, {x=5,y=8,z=1}) ~= newPending.anchorKey,
    "a prior provisional pulse does not exempt large displacement or a floor change")
driftState.provisionalAdvances = 0
requestDrift(nudged, driftGoal, { action = "new_route_owner" })
check(driftState.pathSearch ~= newPending,
    "a new owner still replaces a retained frontier for the same coordinates")
newPending = driftState.pathSearch
requestDrift(nudged, driftGoal, { action = "new_route_owner", draggingBody = true })
check(driftState.pathSearch ~= newPending
        and driftState.pathSearch.route.pathOptions.draggingBody == true,
    "hauling policy changes still replace the ordinary frontier")
N.cancel(nudged, "crowd_fixture_complete")

local joining = actor("sc-nav-crowd-join", 3, 10)
requestDrift(joining, square(14,10))
local joinState = N.peek(joining)
local joinPending = joinState.pathSearch
joining.x, joining.y, joining.square = 3.5, 11.5, square(3,11)
SC.Topology.classifyEdge = function(_, from, to)
    return { traversable = true, cost = 1,
        affordance = from.x ~= to.x and from.y ~= to.y and "diagonal_open" or "open" }
end
local joinAccepted, joinReason = requestDrift(joining, square(14,10))
local dispatched = joinState.path and joinState.path[joinState.pathIndex]
check(joinAccepted and joinState.pathSearch == nil and joinPending.route.complete
        and (joinState.routeReuseCount or 0) > 0 and dispatched
        and math.abs(dispatched.x - joining.square.x) <= 1
        and math.abs(dispatched.y - joining.square.y) <= 1,
    "the completed original frontier joins a freshly validated adjacent suffix before moving: "
        .. tostring(joinReason) .. " complete=" .. tostring(joinPending.route.complete)
        .. " pending=" .. tostring(joinState.pathSearch ~= nil)
        .. " reused=" .. tostring(joinState.routeReuseCount)
        .. " next=" .. tostring(dispatched))
N.cancel(joining, "join_fixture_complete")

SC.Topology.classifyEdge = function()
    current = current + 4
    return { traversable = true, cost = 1, affordance = "open" }
end
local walled = actor("sc-nav-crowd-wall", 8, 11)
requestDrift(walled, square(14,11))
local wallState = N.peek(walled)
local wallPending = wallState.pathSearch
walled.x, walled.y, walled.square = 8.5, 12.5, square(8,12)
SC.Topology.classifyEdge = function(_, from)
    return { traversable = from ~= walled.square, cost = 1, affordance = "open" }
end
local wallAccepted, wallReason = requestDrift(walled, square(14,11))
check(wallAccepted and wallReason == "path_deviation_replan"
        and wallPending.route.complete and wallState.path == nil
        and wallState.pathSearch == nil and wallState.nextRepathAt == 0
        and walled.lastIntent == nil and wallState.nativeLease == nil,
    "a geometrically nearby source behind a wall cannot execute or native-fallback through an unsafe join")
SC.Topology.classifyEdge = function()
    current = current + 4
    return { traversable = false, cost = 1, affordance = "open" }
end
requestDrift(walled, square(14,11))
check(wallState.pathSearch and wallState.pathSearch.route.startSquare == walled.square,
    "the rejected join starts its next bounded search at the actual current square")
N.cancel(walled, "wall_fixture_complete")

-- Exact suffix matches still validate their next edge against current camp
-- admission. A camp redraw cannot be bypassed by joining an old search.
local priorBase = SC.BaseLife
SC.BaseLife = { admitsWork = function() return false end }
local policyState = { path = { square(1,1), square(2,1), square(3,1) }, pathIndex = 2 }
local policyIntent = { action = "drift_route", workCampOnly = true }
check(N._joinCompletedSearchPath(ordinary, policyState, square(2,1),
        { startSquare = square(1,1) }, policyIntent, current) == false
        and policyState.path == nil and policyIntent.pathSearchReason == "path_deviation",
    "a completed drift join rechecks work-square admission even when the actor exactly matches a suffix node")
SC.BaseLife = priorBase

SC.Topology.classifyEdge = function(_, from, to)
    return { traversable = true, cost = 1,
        affordance = from.x ~= to.x and from.y ~= to.y and "diagonal_open" or "open" }
end
local haulState = { path = { square(3,8), square(4,8), square(5,8), square(6,8) }, pathIndex = 2 }
check(N._joinCompletedSearchPath(ordinary, haulState, square(4,9),
        { startSquare = square(3,8) }, { action = "drag_body", draggingBody = true }, current)
        and haulState.path[haulState.pathIndex] == square(4,8),
    "a completed hauling frontier joins only a cardinal-adjacent suffix")
SC.BaseLife = { admitsWork = function(value) return value ~= square(3,2) end }
check(N._suffixWorkAdmitted(square(2,2), square(3,1), {workCampOnly=true}) == false,
    "a diagonal join cannot cross an intermediate corner square outside camp")
SC.BaseLife = priorBase

-- Marked-car pickup uses the same bounded camp admission as storage return.
-- Keep real incremental frontiers alive long enough to finish an indoor door
-- detour, while retaining the ordinary idle lease and all native-path policy.
do
    local savedBase, savedTopology = SC.BaseLife, SC.Topology.classifyEdge
    local created = {}
    SC.BaseLife = {admitsWork=function() return true end}
    SC.Topology.classifyEdge = function()
        current = current + 4
        return {traversable=true,cost=1,affordance="open"}
    end
    local function requestAt(value, goal, intent, at)
        current = at or current + 100
        Perf.beginFrame(3, current)
        local accepted, reason = N.request(value, goal, "walk", intent)
        Perf.endFrame(4)
        return accepted, reason
    end
    local function trunkIntent(camp,reach)
        return {action="move_to_car_trunk",workCampOnly=camp,workReach=reach,
            requireSameSquare=true,arrivalDistance=.35,stealthAvoidance=false}
    end
    local function fixture(id,intent,goalX)
        local value,goal=actor(id,0,4),square(goalX or 12,4)
        created[#created+1]=value
        local accepted,reason=requestAt(value,goal,intent)
        local state=N.peek(value)
        check(accepted and reason=="path_searching" and state.pathSearch,
            "the trunk deadline fixture begins with the actual bounded incremental planner")
        return value,goal,state,state.pathSearch
    end
    local intent=trunkIntent(true,true)
    local worker,goal,state,pending=fixture("sc-camp-trunk-productive",intent,4)
    for _,age in ipairs({6000,12000,18000,24000,30000,36000}) do
        local accepted,reason=requestAt(worker,goal,intent,pending.startedAt+age)
        check(accepted and reason=="path_searching" and state.pathSearch==pending
            and pending.workCampOnly==true and pending.workReach==true
            and state.nativeLease==nil and pending.route.lastSliceBudgetMs==3,
            "productive camp-trunk edge work retains the same 3ms frontier at age "..age)
    end
    local finished=false
    for _=1,200 do
        requestAt(worker,goal,intent,current+100)
        if state.pathSearch==nil then finished=true break end
    end
    check(finished and pending.route.complete and state.path and state.routeReplanCount==1
        and current-pending.startedAt>30000 and current-pending.startedAt<75000
        and state.nativeLease==nil and state.arrivedAt==nil
        and worker.lastIntent and worker.lastIntent.enginePath~=true,
        "productive camp trunk search completes its real route after30s and before75s without native bypass or restart")

    local idle,idleGoal,idleState,idlePending=fixture("sc-camp-trunk-idle",intent)
    check(not N._pathSearchOverdue(idlePending,idlePending.startedAt+6500)
        and N._pathSearchOverdue(idlePending,idlePending.startedAt+6501),
        "camp trunk extension leaves the exact6.5s idle lease unchanged")
    local accepted,reason=requestAt(idle,idleGoal,intent,idlePending.startedAt+6501)
    check(not accepted and reason=="path_blocked:budget_exhausted"
        and idleState.pathSearch==nil and idleState.nativeLease==nil and idle.lastIntent==nil,
        "a genuinely idle camp trunk search still expires without bypassing camp policy")

    local bounded,boundedGoal,boundedState,boundedPending=fixture("sc-camp-trunk-hard",intent)
    for age=6000,72000,6000 do
        accepted,reason=requestAt(bounded,boundedGoal,intent,boundedPending.startedAt+age)
        check(accepted and reason=="path_searching" and boundedState.pathSearch==boundedPending,
            "real work renews the idle lease without removing the75s hard ceiling")
    end
    check(not N._pathSearchOverdue(boundedPending,boundedPending.startedAt+75000)
        and N._pathSearchOverdue(boundedPending,boundedPending.startedAt+75001),
        "the extended camp trunk hard limit is exactly75s while recent edge work remains productive")
    accepted,reason=requestAt(bounded,boundedGoal,intent,boundedPending.startedAt+75001)
    check(not accepted and reason=="path_blocked:budget_exhausted"
        and boundedState.pathSearch==nil and boundedState.pathFailure.failureClass=="budget_exhausted"
        and boundedState.nativeLease==nil and bounded.lastIntent==nil,
        "productive camp trunk work still stops at75s and never uses an opaque native route")

    for index,flags in ipairs({{false,false},{true,false},{false,true}}) do
        local ordinaryIntent=trunkIntent(flags[1],flags[2])
        local ordinary,ordinaryGoal,ordinaryState,ordinaryPending=
            fixture("sc-trunk-ordinary-"..index,ordinaryIntent)
        for age=6000,30000,6000 do
            accepted,reason=requestAt(ordinary,ordinaryGoal,ordinaryIntent,ordinaryPending.startedAt+age)
            check(accepted and reason=="path_searching" and ordinaryState.pathSearch==ordinaryPending,
                "a trunk action without both camp-work proofs retains its original productive allowance")
        end
        accepted,reason=requestAt(ordinary,ordinaryGoal,ordinaryIntent,ordinaryPending.startedAt+30001)
        check(ordinaryState.pathSearch==nil and ordinaryState.pathFailure.failureClass=="budget_exhausted"
            and (flags[1] and not accepted and ordinaryState.nativeLease==nil
                or not flags[1] and accepted and ordinaryState.nativeLease~=nil),
            "ordinary or partially flagged trunk work keeps its30s hard limit and existing native policy")
    end
    check(N._pathSearchOverdue({action="field_travel",workCampOnly=true,workReach=true,
        startedAt=0,progressAt=30000},30001)
        and N._pathSearchOverdue({action="follow_formation",workCampOnly=true,workReach=true,
            followRouting=true,startedAt=0,progressAt=5000},5001),
        "work flags do not extend a different field action or the existing bounded Follow search")

    local revoked,revokedGoal,revokedState,revokedPending=fixture("sc-trunk-policy-revoked",intent)
    for age=6000,36000,6000 do
        requestAt(revoked,revokedGoal,intent,revokedPending.startedAt+age)
    end
    accepted,reason=requestAt(revoked,revokedGoal,trunkIntent(false,false),current+100)
    check(accepted and reason=="engine_path" and revokedState.pathSearch==nil
        and revokedPending.workCampOnly==false and revokedPending.workReach==false,
        "dropping camp-work intent revokes the longer allowance on a retained frontier")

    local claimed,claimedGoal,claimedState,claimedPending=
        fixture("sc-trunk-policy-claimed",trunkIntent(false,false))
    for age=6000,30000,6000 do
        requestAt(claimed,claimedGoal,trunkIntent(false,false),claimedPending.startedAt+age)
    end
    accepted,reason=requestAt(claimed,claimedGoal,intent,claimedPending.startedAt+30001)
    check(not accepted and reason=="path_blocked:budget_exhausted" and claimedState.pathSearch==nil
        and claimedPending.workCampOnly==false and claimedPending.workReach==false
        and claimedState.nativeLease==nil,
        "later flags cannot grant75s to an old frontier created without bounded camp admission")
    for _,value in ipairs(created) do N.cancel(value,"camp_trunk_search_fixture_complete") end
    SC.BaseLife,SC.Topology.classifyEdge=savedBase,savedTopology
end

-- Exercise the real request -> sliced search -> exhausted-budget -> native
-- lease chain. The native movement adapter remains the fixture's receipt;
-- neither the pending frontier nor Navigation.request is replaced by a mock.
do
    local priorHome, priorTopology, savedBase = SC.HomeTrip, SC.Topology.classifyEdge, SC.BaseLife
    local homeActive, changedCamp
    local created = {}
    local function homeFixture(id, y)
        local value = actor(id, 0, y or 13)
        local core = square(12, y or 13)
        created[#created + 1] = value
        homeActive = { leader = { actor = value }, testWaypoint = {x=core.x,y=core.y,z=0},
            scout = {kind="home",phase="inbound",home={camp={core={x=core.x,y=core.y,z=0}}}} }
        changedCamp = false
        return value, core
    end
    SC.HomeTrip = {
        current = function() return homeActive end,
        finalApproachFor = function(value) return homeActive and homeActive.leader.actor == value end,
        campUnchanged = function(camp) return not changedCamp and homeActive and camp == homeActive.scout.home.camp end,
    }
    SC.Topology.classifyEdge = function()
        current = current + 4
        return {traversable=true,cost=1,affordance="open"}
    end
    local function requestAt(value, goal, intent, at)
        current = at or current + 100
        Perf.beginFrame(3, current)
        local accepted, reason = N.request(value, goal, "walk", intent)
        Perf.endFrame(4)
        return accepted, reason
    end
    local function homeIntent()
        return {action="ordered_move",expeditionHomeApproach=true,arrivalDistance=.35,
            requireSameSquare=true,stealthAvoidance=false}
    end
    local homeActor, core = homeFixture("sc-home-early-native")
    local intent = homeIntent()
    local accepted, reason = requestAt(homeActor, core, intent)
    local state = N.peek(homeActor)
    local pending = state.pathSearch
    check(accepted and reason == "path_searching" and pending and pending.homeFinalApproach == true
            and state.nativeLease == nil and state.arrivedAt == nil,
        "only the verified Home core approach begins with the shorter actual sliced search")
    check(not N._pathSearchOverdue(pending, pending.startedAt + 6000)
            and N._pathSearchOverdue(pending, pending.startedAt + 6001),
        "the Home allowance clamps both idle lease and hard ceiling to six seconds")
    accepted, reason = requestAt(homeActor, core, intent, pending.startedAt + 6001)
    check(accepted and reason == "engine_path" and state.pathSearch == nil
            and state.pathFailure.failureClass == "budget_exhausted" and state.pathFailure.nativeFallbackAllowed == true
            and homeActor.lastIntent.enginePath == true and state.nativeLease
            and state.nativeLease.ultimateGoal == core and state.nativeLease.arrivalDistance == .35
            and state.nativeLease.requireSameSquare == true and state.routeReplanCount == 1
            and state.arrivedAt == nil and homeActor.x == .5 and homeActor.y == 13.5,
        "the elapsed Home search becomes the existing native-owned exact arrival path without restarting or claiming arrival")

    local ordinaryActor, ordinaryGoal = homeFixture("sc-ordinary-full-search", 12)
    local ordinaryIntent = {action="ordered_move",stealthAvoidance=false}
    requestAt(ordinaryActor, ordinaryGoal, ordinaryIntent)
    local ordinaryPending = N.peek(ordinaryActor).pathSearch
    for _, age in ipairs({6001,12002,18003,24004,29999}) do
        accepted, reason = requestAt(ordinaryActor, ordinaryGoal, ordinaryIntent, ordinaryPending.startedAt + age)
        check(accepted and reason == "path_searching" and N.peek(ordinaryActor).pathSearch == ordinaryPending
                and ordinaryPending.homeFinalApproach == false and ordinaryActor.lastIntent == nil,
            "an ordinary productive search retains the original thirty-second allowance at age " .. age)
    end
    accepted, reason = requestAt(ordinaryActor, ordinaryGoal, ordinaryIntent, ordinaryPending.startedAt + 30001)
    check(accepted and reason == "engine_path" and N.peek(ordinaryActor).nativeLease ~= nil,
        "the ordinary thirty-second search still hands its exhausted budget to normal native pathing")

    local selected, selectedCore = homeFixture("sc-home-selected", 11)
    local wrongActor = actor("sc-home-spoofed", 0, 11)
    created[#created + 1] = wrongActor
    requestAt(wrongActor, selectedCore, homeIntent())
    local wrongPending = N.peek(wrongActor).pathSearch
    check(wrongPending and wrongPending.homeFinalApproach == false,
        "a claimed Home hint for a different actor cannot shorten that actor's search")
    accepted, reason = requestAt(wrongActor, selectedCore, homeIntent(), wrongPending.startedAt + 6001)
    check(accepted and reason == "path_searching" and N.peek(wrongActor).pathSearch == wrongPending,
        "a spoofed actor receives no early native fallback")
    requestAt(selected, square(11,11), homeIntent())
    local wrongGoalPending = N.peek(selected).pathSearch
    check(wrongGoalPending and wrongGoalPending.homeFinalApproach == false,
        "a Home leader's hint for a different goal cannot shorten the search")
    check(not N._homeApproachSearchForRequest(selected, selected.square, selectedCore, square(11,11), homeIntent(), selectedCore),
        "an adjusted effective goal must still be the exact captured Home core")
    check(not N._homeApproachSearchForRequest(selected, selected.square, selectedCore, selectedCore, homeIntent(), square(11,11)),
        "a retained planning goal must also be the exact captured Home core")
    check(N._homeApproachSearchForRequest(selected, selected.square, selectedCore, selectedCore, homeIntent(), selectedCore),
        "all three exact core goals admit the selected nearby Home leader")

    local reused, reusedCore = homeFixture("sc-home-revoked", 10)
    requestAt(reused, reusedCore, homeIntent())
    local reusedPending = N.peek(reused).pathSearch
    check(reusedPending.homeFinalApproach == true, "the stale-hint fixture begins with verified admission")
    requestAt(reused, reusedCore, ordinaryIntent)
    check(N.peek(reused).pathSearch == reusedPending and reusedPending.homeFinalApproach == false,
        "reusing the frontier for an ordinary order removes the previous Home-only deadline")
    changedCamp = true
    check(not N._homeApproachSearchForRequest(reused, reused.square, reusedCore, reusedCore, homeIntent(), reusedCore),
        "a changed captured camp rejects the early fallback allowance")
    changedCamp = false
    reused.z = .2
    check(not N._homeApproachSearchForRequest(reused, reused.square, reusedCore, reusedCore, homeIntent(), reusedCore),
        "an actor lifted off the ground cannot receive the final ground-floor allowance")
    reused.z = 0

    local boundary, boundaryCore = homeFixture("sc-home-approach-range", 6)
    boundary.x, boundary.y = boundaryCore.x - 18, boundaryCore.y
    boundary.square = {x=boundary.x,y=boundary.y,z=0}
    check(N._homeApproachSearchForRequest(boundary, boundary.square, boundaryCore, boundaryCore, homeIntent(), boundaryCore),
        "the exact eighteen-metre final-approach boundary admits the bounded Home search")
    boundary.x = boundary.x - .001
    boundary.square = {x=math.floor(boundary.x),y=boundary.y,z=0}
    check(not N._homeApproachSearchForRequest(boundary, boundary.square, boundaryCore, boundaryCore, homeIntent(), boundaryCore),
        "a Home core waypoint beyond eighteen metres keeps the ordinary search allowance")

    local worker, workCore = homeFixture("sc-home-work-policy", 9)
    SC.BaseLife = {admitsWork=function() return true end}
    local workIntent = homeIntent() workIntent.workCampOnly = true
    requestAt(worker, workCore, workIntent)
    local workState, workPending = N.peek(worker), N.peek(worker).pathSearch
    check(workPending and workPending.homeFinalApproach == false,
        "work-area requests never inherit a Home-only early native allowance")
    accepted, reason = requestAt(worker, workCore, workIntent, workPending.startedAt + 30001)
    check(not accepted and reason == "path_blocked:budget_exhausted" and workState.nativeLease == nil
            and worker.lastIntent == nil,
        "even an exhausted search cannot bypass the existing workCampOnly native-path barrier")

    local lockedActor, lockedCore = homeFixture("sc-home-locked-room", 8)
    requestAt(lockedActor, lockedCore, homeIntent())
    local lockedPending = N.peek(lockedActor).pathSearch
    function lockedCore:getRoomIDString() return "home-locked-test" end
    local locked = N._lockedRoomsForTests()
    locked["home-locked-test"] = {expires=current+100000,door={isOpen=function() return false end,
        isLocked=function() return true end,isPermaLocked=function() return true end}}
    accepted, reason = requestAt(lockedActor, lockedCore, homeIntent(), lockedPending.startedAt + 6001)
    check(not accepted and reason == "path_blocked:door_locked" and N.peek(lockedActor).nativeLease == nil
            and lockedActor.lastIntent == nil,
        "a known locked room still refuses native pathing at the Home search deadline")
    locked["home-locked-test"], lockedCore.getRoomIDString = nil, nil

    local staticActor, staticCore = homeFixture("sc-home-static-block", 7)
    SC.Topology.classifyEdge = function()
        current = current + 4
        return {traversable=false,affordance="wall",reason="blocked_edge"}
    end
    for _ = 1, 12 do
        accepted, reason = requestAt(staticActor, staticCore, homeIntent())
        if not accepted then break end
    end
    local staticState = N.peek(staticActor)
    check(not accepted and staticState.pathFailure and staticState.pathFailure.failureClass == "blocked_static"
            and staticState.pathFailure.nativeFallbackAllowed == false and staticState.nativeLease == nil
            and staticActor.lastIntent == nil,
        "a proven static failure is not relabelled as Home budget exhaustion or opaque native pathing")
    for _, value in ipairs(created) do N.cancel(value, "home_search_fixture_complete") end
    SC.HomeTrip, SC.Topology.classifyEdge, SC.BaseLife = priorHome, priorTopology, savedBase
end
SC_TEST_REPORT = "NAVIGATION_LIVENESS_PASS checks=" .. checks
