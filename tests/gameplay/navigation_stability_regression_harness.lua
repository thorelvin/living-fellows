-- SPDX-License-Identifier: MIT
-- Standalone real-Kahlua regression: production route repair and incremental A*.
local SC, checks = SurvivorCompanion, 0
local N, P, U = SC.Navigation, SC.PathSearch, SC.GameplayUtil
local function check(value, message)
    checks = checks + 1
    assert(value, "navigation stability regression " .. checks .. ": " .. message)
end
local grid = {}
local function square(x, y, z)
    z = z or 0
    if z ~= 0 or math.abs(x) > 300 or math.abs(y) > 8 then return nil end
    local key = tostring(x) .. ":" .. tostring(y) .. ":" .. tostring(z)
    if grid[key] then return grid[key] end
    local value = { x = x, y = y, z = z, objects = {}, moving = {} }
    function value:getX() return self.x end
    function value:getY() return self.y end
    function value:getZ() return self.z end
    function value:getObjects() return self.objects end
    function value:getSpecialObjects() return self.objects end
    function value:getMovingObjects() return self.moving end
    function value:isFree() return true end
    function value:isSolid() return false end
    function value:isSolidTrans() return false end
    function value:TreatAsSolidFloor() return true end
    grid[key] = value
    return value
end
local cell = { getGridSquare = function(_, x, y, z) return square(x, y, z) end }
function getCell() return cell end
local actor = { __class = "IsoPlayer", x = 0.5, y = 0.5, data = {} }
function actor:getX() return self.x end
function actor:getY() return self.y end
function actor:getZ() return 0 end
function actor:getSquare() return square(math.floor(self.x), math.floor(self.y)) end
function actor:getCurrentSquare() return self:getSquare() end
function actor:getModData() return self.data end
function actor:isDead() return false end
SC.Config._values.movementRecorderEnabled = true
local edgeCalls, edgeDelay, elapsed = 0, 0, 0
-- These tests isolate search bookkeeping from physical obstacle classification;
-- the separate traversal suite exercises the real world-edge implementation.
SC.Topology.classifyEdge = function(_, from, to)
    edgeCalls, elapsed = edgeCalls + 1, elapsed + edgeDelay
    return { traversable = true, cost = from.x ~= to.x and from.y ~= to.y and math.sqrt(2) or 1 }
end
local context = { action = "follow_formation", followRecovery = true }
local function line(first, last)
    local path = {}
    for x = first, last do path[#path + 1] = square(x, 0) end
    return path
end
local function state(path, index)
    return { path = path, pathIndex = index or 2, pathGoalSquare = path[#path],
        blockedEdges = {}, blockedSquares = {}, routeMemory = {} }
end
local route = state(line(0, 3))
route.routeCrossTrack, route.routeProjection, route.lastRouteProjection = 4, 9, 9
route.crossTrackSince, route.reverseProgressSince = 100, 100
check(N._repairMovingPathForTests(actor, route, square(0, 0), square(2, 0), context, 1000),
    "D to unconsumed C repairs without rebuilding")
check(#route.path == 3 and route.path[3] == square(2, 0) and route.pathIndex == 2
    and route.lastRouteRepairKind == "trimmed" and route.lastRouteRepairTrimmed == 1,
    "existing C trims D instead of creating A B C D C")
check(route.routeCrossTrack == nil and route.lastRouteProjection == nil
    and route.crossTrackSince == nil and route.reverseProgressSince == nil,
    "repair clears projection and instability history from the old segment")
for cycle = 1, 100 do
    local goal = cycle % 2 == 1 and square(3, 0) or square(2, 0)
    check(N._repairMovingPathForTests(actor, route, square(0, 0), goal, context, 1000 + cycle),
        "oscillating C/D goal remains repairable")
    local unique = {}
    for _, node in ipairs(route.path) do
        check(not unique[node], "oscillating goal never repeats a retained node")
        unique[node] = true
    end
    check(#route.path <= 4 and route.path[#route.path] == goal and route.pathIndex == 2,
        "100 moving-goal repairs do not grow the path or move its active edge")
end
local consumed = state(line(0, 10), 9)
check(N._repairMovingPathForTests(actor, consumed, square(7, 0), square(11, 0), context, 1200)
    and #consumed.path == 5 and consumed.path[1] == square(7, 0)
    and consumed.path[2] == square(8, 0) and consumed.pathIndex == 2
    and consumed.lastRouteRepairCompacted == 7,
    "consumed prefix compacts while preserving predecessor and exact next edge")
local backwards = state(line(0, 3), 4)
local originalPath = backwards.path
check(not N._repairMovingPathForTests(actor, backwards, square(2, 0), square(1, 0), context, 1300)
    and backwards.path == originalPath and #backwards.path == 4,
    "consumed/behind goal is not appended as a retracing repair")
SC.Config._values.navigationMovingRouteMaxNodes = 8
local capped = state(line(0, 7))
check(not N._repairMovingPathForTests(actor, capped, square(0, 0), square(8, 0), context, 1400)
    and #capped.path == 8 and capped.pathGoalSquare == square(7, 0),
    "tail extension exceeding retained path cap fails atomically for normal replanning")
local compactCap = state(line(0, 10), 9)
check(N._repairMovingPathForTests(actor, compactCap, square(7, 0), square(11, 0), context, 1400),
    "consumed history does not falsely exhaust retained path cap")
SC.Config._values.navigationMovingRouteMaxNodes = nil
local projected = state(line(0, 3))
projected.routeCrossTrack, projected.lastRouteProjection, projected.nativeLease = 4, 7, {}
N._correctRouteProjectionForTests(actor, projected, square(0, 0), context, 1500)
check(projected.routeCrossTrack == nil and projected.lastRouteProjection == nil,
    "native-owned path cannot report stale Lua cross-track evidence")
projected.nativeLease = nil
actor.x = 0.9
N._correctRouteProjectionForTests(actor, projected, square(0, 0), context, 1600)
projected.pathIndex, projected.reverseProgressSince, actor.x = 3, 1, 1.6
check(N._correctRouteProjectionForTests(actor, projected, square(1, 0), context, 2000)
    and projected.path ~= nil and projected.reverseProgressSince == nil,
    "new segment cannot inherit old projection reverse-progress timeout")
actor.x = 0.5
local oldPeek = N.peek
N.peek = function() return route end
local report = SC.Locomotion.report(actor)
N.peek = oldPeek
check(string.find(report, "Event window: last 30 seconds", 1, true)
    and string.find(report, "Path stability (since navigation reset)", 1, true),
    "event time window and cumulative navigation counters are explicitly distinct")
check(string.find(report, "trimmed=1", 1, true) and string.find(report, "appended=1", 1, true)
    and string.find(report, "cross-track unavailable", 1, true),
    "repair events retain kind/count details and missing projection is not fabricated zero")

-- Deadline expiry inside a node must retain unprocessed neighbors, not mark the
-- node closed and silently lose edges. Compare its result with unlimited A*.
local nodes = { A = { id = "A" }, B = { id = "B" }, C = { id = "C" }, D = { id = "D" } }
local links = { A = { "B", "C", "D" }, B = { "D" }, C = { "D" }, D = {} }
local costs = { A = { B = 1, C = 2, D = 9 }, B = { D = 4 }, C = { D = 1 } }
local graphCalls, neighborCalls, clockValue, costPerEdge = {}, {}, 0, 2
local adapter = {
    sameSquare = function(a, b) return a == b end,
    key = function(node) return node.id end,
    heuristic = function() return 0 end,
    neighbors = function(node)
        neighborCalls[node.id] = (neighborCalls[node.id] or 0) + 1
        local result = {}
        for _, id in ipairs(links[node.id]) do result[#result + 1] = nodes[id] end
        return result
    end,
    edge = function(a, b)
        local key = a.id .. b.id
        graphCalls[key] = (graphCalls[key] or 0) + 1
        clockValue = clockValue + costPerEdge
        return true, costs[a.id][b.id]
    end,
}
local options = { nodeBudget = 20, sliceBudgetMs = 3, clock = function() return clockValue end }
local job = P.new(nodes.A, nodes.D, options, adapter)
local status, path, reason, expanded, used = P.resume(job, 100)
check(status == "pending" and job.lastYieldReason == "deadline" and used == 1
    and job.pendingExpansion and job.pendingExpansion.index == 3 and clockValue == 4,
    "two expensive edges yield mid-node at deadline before third edge runs")
local slices = 1
while status == "pending" and slices < 30 do
    local before = clockValue
    status, path, reason, expanded, used = P.resume(job, 100)
    check(clockValue - before <= 4, "slice overshoot is bounded to one indivisible edge query")
    slices = slices + 1
end
check(status == "complete" and #path == 3 and path[2] == nodes.C and job.nodes.D.g == 3,
    "time-sliced A* preserves the optimal route through the last pending neighbors")
check(neighborCalls.A == 1 and graphCalls.AB == 1 and graphCalls.AC == 1 and graphCalls.AD == 1,
    "resuming a node does not repeat its native neighbor/edge calls")
costPerEdge = 0
local baseline = P.new(nodes.A, nodes.D, { nodeBudget = 20 }, adapter)
local baselineStatus, baselinePath = P.resume(baseline, 100)
check(baselineStatus == status and baseline.nodes.D.g == job.nodes.D.g
    and baselinePath[2] == path[2], "deadline and unrestricted searches produce the same optimum")
local budgetJob = P.new(nodes.A, nodes.D, { nodeBudget = 1, sliceBudgetMs = 1,
    clock = function() return clockValue end }, adapter)
costPerEdge = 2
status = P.resume(budgetJob, 1)
check(status == "pending" and budgetJob.pendingExpansion and budgetJob.expanded == 1,
    "deadline does not prematurely fail a partially expanded final-budget node")
for _ = 1, 8 do
    if status ~= "pending" then break end
    status = P.resume(budgetJob, 1)
end
check(status == "failed" and budgetJob.reason == "budget" and budgetJob.nodes.D ~= nil,
    "node-budget failure occurs only after every remaining neighbor was processed")
local staleClock = 0
local staleJob = P.new(nodes.A, nodes.D, { nodeBudget = 20 }, adapter)
for index = 1, 30 do
    P.heapPush(staleJob.open, { key = "A", f = -1, h = -1, seq = index })
end
local staleCount = #staleJob.open
status = P.resume(staleJob, 100, P.newSlice({ sliceBudgetMs = 3,
    clock = function() staleClock = staleClock + 1 return staleClock end }))
check(status == "pending" and staleJob.lastYieldReason == "deadline"
    and #staleJob.open >= staleCount - 3 and staleJob.expanded == 0,
    "lazy-deleted heap entries are time bounded even though they consume no node quota")
local correctedClock = 100
local correctedSlice = P.newSlice({ clock = function() return correctedClock end, sliceBudgetMs = 2 })
correctedClock = 90
check(P.sliceExpired(correctedSlice), "backward wall-clock adjustment yields instead of extending frame budget")

-- Production route wrapper: one deadline and one topology-read batch per slice,
-- including primary/alternative transition work. Actual clocks are not modified.
elapsed, edgeDelay, edgeCalls = 0, 0.6, 0
local savedBatch, batchCalls, insideBatch = SC.Topology.withReadBatch, 0, false
SC.Topology.withReadBatch = function(callback, ...)
    batchCalls, insideBatch = batchCalls + 1, true
    local values = { callback(...) }
    insideBatch = false
    return unpack(values, 1, 6)
end
local oldClassify = SC.Topology.classifyEdge
SC.Topology.classifyEdge = function(...)
    check(insideBatch, "all route edge reads stay inside the slice-local topology batch")
    return oldClassify(...)
end
local routeJob = N.beginPathSearch(square(0, 0), square(7, 0), { threats = {}, allies = {} }, {
    nodeBudget = 80, alternatives = true, sliceBudgetMs = 2, clock = function() return elapsed end,
})
status, slices = "pending", 0
local deadlineSeen = false
while status == "pending" and slices < 500 do
    local before = elapsed
    status, path = N.resumePathSearch(routeJob, 1000)
    check(elapsed - before < 2.61, "primary and alternative jobs cannot each replenish slice time")
    deadlineSeen = deadlineSeen or routeJob.lastYieldReason == "deadline"
    slices = slices + 1
end
check(status == "complete" and path[1] == square(0, 0) and path[#path] == square(7, 0)
    and slices > 1 and deadlineSeen and routeJob.attempt > 1,
    "production alternative-route job completes across bounded real-time slices")
check(batchCalls == slices and not insideBatch, "each resumed route releases its topology read batch")
SC.Topology.withReadBatch, SC.Topology.classifyEdge = savedBatch, oldClassify
edgeDelay = 0
local baselineReport = N.evaluateRoutes(square(0, 0), square(7, 0),
    { threats = {}, allies = {} }, { nodeBudget = 80 })
check(routeJob.report.candidateCount == baselineReport.candidateCount
    and routeJob.report.selectedScore == baselineReport.selectedScore,
    "incremental scoring preserves synchronous route ranking and total cost")

-- Route completion must publish work already performed inside the sliced
-- evaluation. A long path with live threat/ally references used to multiply
-- native position reads per node, then rebuild danger/signature/vegetation once
-- more after the search returned complete.
local savedPosition, savedDistanceSq = U.position, U.distanceSq
local completionThreat = { x = 12.5, y = 0.5, z = 0 }
local completionAlly = { x = 4.5, y = 0.5, z = 0 }
local completionPlayer = { x = 2.5, y = 0.5, z = 0 }
local actorPositionReads, distanceCalls = 0, 0
U.position = function(value)
    if value == completionThreat or value == completionAlly or value == completionPlayer then
        actorPositionReads = actorPositionReads + 1
        elapsed = elapsed + 0.2
    end
    return savedPosition(value)
end
U.distanceSq = function(...)
    distanceCalls = distanceCalls + 1
    elapsed = elapsed + 0.2
    return savedDistanceSq(...)
end
local bushProperties = { has = function() return true end }
local bushSprite = { getProperties = function() return bushProperties end }
square(20, 0).objects = { { getSprite = function() return bushSprite end } }
local completionClassify = SC.Topology.classifyEdge
SC.Topology.classifyEdge = function(_, from, to)
    elapsed = elapsed + 0.45
    if to.y ~= 0 then return { traversable = false, reason = "test_corridor" } end
    return { traversable = true, cost = 1 }
end
elapsed = 0
local completionSnapshot = {
    threats = { { actor = completionThreat, visible = true } },
    allies = { { actor = completionAlly } },
    player = { actor = completionPlayer },
}
local completionJob = N.beginPathSearch(square(0, 0), square(30, 0),
    completionSnapshot, { nodeBudget = 180, sliceBudgetMs = 2,
        clock = function() return elapsed end })
local capturedReads = actorPositionReads
local completionStatus, completionPath, completionSlices = "pending", nil, 0
while completionStatus == "pending" and completionSlices < 500 do
    local before = elapsed
    completionStatus, completionPath = N.resumePathSearch(completionJob, 1000)
    check(elapsed - before <= 2.5,
        "completion scoring cannot append an unsliced native-call tail")
    completionSlices = completionSlices + 1
end
local selected = completionJob.report and completionJob.report.routes[1]
check(completionStatus == "complete" and completionPath[#completionPath] == square(30, 0)
        and completionSlices > 1,
    "advancing-clock route completes through bounded search/evaluation slices")
check(capturedReads == 0 and actorPositionReads == 3 and distanceCalls == 0,
    "threat, ally, and player coordinates are captured once inside slices, not at construction or per node")
check(completionJob.report.selectedDanger == selected.danger
        and completionJob.report.selectedSignature == selected.signature
        and completionJob.report.selectedEmergencyVegetation == true
        and selected.emergencyVegetation == true
        and selected.signature == "0:0:0>1:0:0>2:0:0>3:0:0>4:0:0>5:0:0>6:0:0>7:0:0>8:0:0>9:0:0>10:0:0>11:0:0>12:0:0>13:0:0>14:0:0>15:0:0>16:0:0>17:0:0>18:0:0>19:0:0>20:0:0>21:0:0>22:0:0>23:0:0>24:0:0>25:0:0>26:0:0>27:0:0>28:0:0>29:0:0>30:0:0",
    "selected danger, signature, and vegetation evidence are carried from sliced evaluation")
U.position, U.distanceSq = savedPosition, savedDistanceSq
SC.Topology.classifyEdge = completionClassify
square(20, 0).objects = {}

-- Indoor emergency movement already owns a strictly validated, ranked local
-- escape from Senses. It must not run the synchronous 160-node outdoor search
-- before returning that square.
local retreatEdgeCalls = 0
local retreatClassify = SC.Topology.classifyEdge
SC.Topology.classifyEdge = function(...)
    retreatEdgeCalls = retreatEdgeCalls + 1
    return retreatClassify(...)
end
local localEscape = square(1, 0)
local retreatTarget, retreatPlan = N.retreatTarget(actor, {
    time = 9000,
    escapeSquares = { { square = localEscape, danger = 0, distance = 1,
        traversalCost = 1, outdoors = false } },
})
check(retreatTarget == localEscape and retreatPlan.source == "validated_local_escape"
        and retreatPlan.validated == true and retreatEdgeCalls == 0,
    "indoor retreat returns the validated local escape without synchronous egress search")
SC.Topology.classifyEdge = retreatClassify

-- More than sixteen dynamic portals may cap recurring cache validation, but
-- must never truncate the reachable escape flood-fill itself.
local portalObjects = {}
local portalClassify = SC.Topology.classifyEdge
SC.Topology.classifyEdge = function(_, from, to)
    local key = tostring(from.x) .. ":" .. tostring(from.y) .. ">"
        .. tostring(to.x) .. ":" .. tostring(to.y)
    portalObjects[key] = portalObjects[key] or {}
    return { traversable = true, cost = 1, affordance = "door",
        object = portalObjects[key], requiresNative = true }
end
local manyPortalJob = SC.Topology.newEscapeSearch(actor, square(0, 0), {
    radius = 10, nodeBudget = 40, exitLimit = 40,
})
local reachable, _, manyPortalMeta = SC.Topology.resumeEscapeSearch(manyPortalJob, 500)
check(manyPortalMeta.complete == true and #reachable == 39
        and #manyPortalJob.portals == 16
        and manyPortalMeta.portalValidationTruncated == true,
    "the seventeenth portal caps validation metadata without truncating escape reachability")
SC.Topology.classifyEdge = portalClassify

-- 0.25.5 playtest, dense forest: one companion replanned the same square
-- twenty-four times and never moved on. Any motion over a fifth of a tile
-- zeroed the recovery attempt ladder, and collision jitter inside a thicket is
-- motion, so recovery restarted at its first step forever and never reached
-- the lateral-clearance or terminal steps that exist for exactly this.
do
    local anchored = { stuckAttempts = 2,
        recoveryAnchorX = 10, recoveryAnchorY = 10, recoveryAnchorZ = 0 }
    check(N._recoveryAnchorClearedForTests(anchored, 10.3, 10.2, 0) == false,
        "collision jitter inside the anchor radius is not progress")
    check(N._recoveryAnchorClearedForTests(anchored, 12.5, 10, 0) == true,
        "leaving the anchor radius is progress")
    check(N._recoveryAnchorClearedForTests(anchored, 10, 10, 1) == true,
        "a different floor is always progress")
    check(N._recoveryAnchorClearedForTests({}, 10, 10, 0) == true,
        "an unanchored state is never held back")

    local savedX, savedY = actor.x, actor.y
    local jitter = { stuckAttempts = 2,
        recoveryAnchorX = 10, recoveryAnchorY = 10, recoveryAnchorZ = 0 }
    actor.x, actor.y = 10.3, 10.2
    check(N._resetRecoveryLadder(actor, jitter, true) == false
            and jitter.stuckAttempts == 2 and jitter.recoveryAnchorX == 10,
        "a goal change raised while the companion is still stuck keeps its ladder")
    actor.x, actor.y = 12.5, 10
    check(N._resetRecoveryLadder(actor, jitter, true) == true
            and jitter.stuckAttempts == 0 and jitter.recoveryAnchorX == nil,
        "the ladder clears once the companion has actually got away")
    local arrival = { stuckAttempts = 3,
        recoveryAnchorX = 10, recoveryAnchorY = 10, recoveryAnchorZ = 0 }
    actor.x, actor.y = 10.1, 10.1
    check(N._resetRecoveryLadder(actor, arrival) == true and arrival.stuckAttempts == 0
            and arrival.recoveryAnchorX == nil,
        "an ungated reset -- arrival, or a genuinely new episode -- clears the ladder")

    -- The reset the playtest actually hit: ordinary motion bookkeeping.
    local shuffling = { stuckAttempts = 2, lastX = 10, lastY = 10, lastZ = 0,
        recoveryAnchorX = 10, recoveryAnchorY = 10, recoveryAnchorZ = 0 }
    actor.x, actor.y = 10.3, 10.2
    check(N._updateProgressForTests(actor, shuffling, 1000) == true
            and shuffling.stuckAttempts == 2,
        "shuffling on the spot registers as motion without crediting the recovery ladder")
    actor.x, actor.y = 13, 10
    check(N._updateProgressForTests(actor, shuffling, 1100) == true
            and shuffling.stuckAttempts == 0 and shuffling.recoveryAnchorX == nil,
        "walking clear of the anchor credits the ladder as it always did")
    actor.x, actor.y = savedX, savedY
end

-- The same playtest stood still before taking its first step in woodland. The
-- route search asks whether a square holds a tree for every neighbour of every
-- expanded node, and each of those asks again for its own eight-square
-- clearance, so one slice re-read the same squares dozens of times and spent
-- its whole 2 ms budget doing it.
do
    local probes = 0
    local wooded = square(20, 3)
    function wooded:HasTree() probes = probes + 1 return true end
    SC.Topology.withReadBatch(function()
        check(SC.Topology.squareHasTree(wooded) == true, "a wooded square reads as a tree")
        SC.Topology.squareHasTree(wooded)
        SC.Topology.squareHasTree(wooded)
    end)
    check(probes == 1,
        "one tree read per square per search slice, not one per edge: probes=" .. tostring(probes))
    local batched = probes
    SC.Topology.squareHasTree(wooded)
    SC.Topology.squareHasTree(wooded)
    check(probes == batched + 2,
        "outside a batch every tree read still reaches the world: probes=" .. tostring(probes))

    local clearanceProbes = 0
    local centre, neighbour = square(40, 3), square(41, 3)
    function neighbour:HasTree() clearanceProbes = clearanceProbes + 1 return true end
    local first = N._treeClearanceCostForTests(centre)
    local second = N._treeClearanceCostForTests(centre)
    check(first > 0 and second == first and clearanceProbes == 1,
        "neighbouring-tree clearance is computed once and cached like the vehicle clearance beside it: probes="
            .. tostring(clearanceProbes) .. " cost=" .. tostring(first))
end

-- A cross-floor goal is handed to the engine whole, so when it comes back with
-- nothing the blocker record could not say whether the handoff had even been
-- attempted -- the 21 September playtest shows companions idle upstairs with
-- no native path and nothing on their own floor to classify. The record now
-- carries which route the request took, what the engine did with its lease,
-- and where the companion was ultimately trying to get to.
do
    local captured
    local realDiagnostic = U.diagnostic
    U.diagnostic = function(subsystem, _, message)
        if subsystem == "navigation-blocker" then captured = message end
    end
    local goal = square(6, 0)
    local handedOff = {
        pathReason = "native_multi_level", goalSquare = goal,
        lastMovementReason = "native_path_failed",
        blockedEdges = {}, blockedSquares = {}, routeMemory = {},
        lastAttemptFrom = square(0, 0), lastAttemptTo = square(1, 0),
        nativeLease = {
            reason = "native_multi_level", affordance = "multi_level",
            startedAt = 500, expires = 900,
            fromSquare = square(0, 0), toSquare = goal,
        },
    }
    N._recordBlockerForTests(actor, handedOff, "unknown", nil, square(1, 0),
        nil, "stop_and_replan", 1500)
    local handedOffMessage = captured
    captured = nil
    local ordinary = {
        blockedEdges = {}, blockedSquares = {}, routeMemory = {},
        lastAttemptFrom = square(0, 0), lastAttemptTo = square(1, 0),
    }
    N._recordBlockerForTests(actor, ordinary, "unknown", nil, square(1, 0),
        nil, "stop_and_replan", 1500)
    local ordinaryMessage = captured
    U.diagnostic = realDiagnostic

    check(handedOffMessage ~= nil
            and string.find(handedOffMessage, "route=native_multi_level", 1, true) ~= nil,
        "a blocker record names the route the request took: " .. tostring(handedOffMessage))
    check(string.find(handedOffMessage,
            "lease=native_multi_level:multi_level:1000ms:expired", 1, true) ~= nil,
        "a blocker record names what the engine did with its lease: "
            .. tostring(handedOffMessage))
    check(string.find(handedOffMessage, "goal=" .. tostring(U.squareKey(goal)), 1, true) ~= nil,
        "a blocker record names the goal the companion could not reach: "
            .. tostring(handedOffMessage))
    check(ordinaryMessage ~= nil
            and string.find(ordinaryMessage, "route=none", 1, true) ~= nil
            and string.find(ordinaryMessage, "lease=none", 1, true) ~= nil
            and string.find(ordinaryMessage, "goal=none", 1, true) ~= nil,
        "an ordinary same-floor blocker says so plainly: " .. tostring(ordinaryMessage))
end

-- 0.25.5 playtest: 126 of 171 blockers came back as an unknown obstacle with
-- low confidence, and only 7 as vegetation across a session spent in woodland.
do
    -- A tree supplied by a tile mod: the square's own flag stays down, and the
    -- tile carries the property that makes the game treat it as a tree.
    local modded = square(24, 3)
    function modded:HasTree() return false end
    local trunk = {}
    function trunk:getSprite()
        return { getProperties = function()
            return { Is = function(_, name) return name == "tree" end }
        end }
    end
    modded.objects[#modded.objects + 1] = trunk
    check(SC.Topology.squareHasTree(modded) == true,
        "a tree supplied by a mod is still a tree")
    local bare = square(26, 3)
    function bare:HasTree() return false end
    check(SC.Topology.squareHasTree(bare) == false, "open ground is not a tree")

    -- A forest is undergrowth as well as trunks.
    local leafySquare = square(31, 3)
    function leafySquare:hasBush() return true end
    local leafy = N._classifyMovementBlockerForTests(actor, square(30, 3),
        leafySquare, "movement_rejected")
    check(leafy.type == "vegetation" and leafy.bush == true,
        "undergrowth is vegetation, not an unknown obstacle: " .. tostring(leafy.type))

    -- The engine failing to produce a route is not an obstacle on this edge.
    local routed = N._classifyMovementBlockerForTests(actor, square(28, 3),
        square(29, 3), "native_path_failed")
    check(routed.type == "native_route" and routed.confidence == "high"
            and routed.passageOnly == true,
        "a native routing failure is reported as routing, and never blacklists the edge: "
            .. tostring(routed.type) .. "/" .. tostring(routed.passageOnly))
end

-- 25 September playtest: five of eight navigation records said route=budget on
-- nine- and ten-tile follow goals in dense forest. A flat ceiling assumes a
-- route costs about one expansion per tile, which holds in the open and not in
-- woodland, where most neighbours are trees and the frontier has to snake.
do
    local base = SC.Config.get("runtime", "navigationNodeBudget") or 220
    check(N._derivedNodeBudget(nil) == base and N._derivedNodeBudget(0) == base
            and N._derivedNodeBudget(-3) == base,
        "an unmeasurable reach keeps the flat budget")
    check(N._derivedNodeBudget(2) == base,
        "a hop shorter than the flat budget does not shrink it")
    local ten = N._derivedNodeBudget(10)
    check(ten == 600 and ten > base,
        "a ten-tile goal is allowed the area it may have to sweep: " .. tostring(ten))
    local ceiling = SC.Config.get("runtime", "navigationNodeBudgetMaximum") or 1200
    check(N._derivedNodeBudget(400) == ceiling,
        "an impossible goal still gives up at the ceiling: "
            .. tostring(N._derivedNodeBudget(400)))

    -- Running out of expansions is not proof the goal is unreachable.
    local retryJob = {
        startSquare = square(0, 0), goalSquare = square(20, 0), pathOptions = {},
    }
    check(N._startBudgetRetrySearch(retryJob) == true
            and retryJob.budgetRetried == true and retryJob.phase == "primary"
            and retryJob.search ~= nil,
        "a budget-exhausted route is retried instead of reported unreachable")
    check(retryJob.search.nodeBudget
            >= (SC.Config.get("runtime", "navigationBudgetRetryNodeBudget") or 2400),
        "the retry is given room to finish: " .. tostring(retryJob.search.nodeBudget))
    check(N._startBudgetRetrySearch(retryJob) == false,
        "a second exhaustion is a real answer and is not retried again")

    -- Through a real job, not the helpers: the reach has to reach the search.
    local wired = N.beginPathSearch(square(0, 0), square(20, 0), nil, {})
    check(wired.search ~= nil and wired.search.nodeBudget == N._derivedNodeBudget(20),
        "a new route job takes the budget its reach earns: "
            .. tostring(wired.search and wired.search.nodeBudget)
            .. " vs " .. tostring(N._derivedNodeBudget(20)))

    -- Squeeze the derived budget rather than pinning one: a pinned budget is a
    -- caller's explicit answer and must not be overridden.
    local savedBudget = SC.Config._values.navigationNodeBudget
    local savedCeiling = SC.Config._values.navigationNodeBudgetMaximum
    SC.Config._values.navigationNodeBudget = 1
    SC.Config._values.navigationNodeBudgetMaximum = 1
    local exhausted = N.beginPathSearch(square(0, 0), square(60, 0), nil, {})
    local exhaustedStatus, exhaustedSlices = "pending", 0
    while exhaustedStatus == "pending" and exhaustedSlices < 300 do
        exhaustedStatus = select(1, N.resumePathSearch(exhausted, 1000))
        exhaustedSlices = exhaustedSlices + 1
    end
    SC.Config._values.navigationNodeBudget = savedBudget
    SC.Config._values.navigationNodeBudgetMaximum = savedCeiling
    check(exhausted.budgetRetried == true and exhaustedStatus == "complete",
        "a search that ran out of nodes retries and completes instead of reporting no route: "
            .. tostring(exhaustedStatus) .. "/" .. tostring(exhausted.budgetRetried))
    local pinned = { startSquare = square(0, 0), goalSquare = square(9, 0),
        pathOptions = { nodeBudget = 12 } }
    check(N._startBudgetRetrySearch(pinned) == false,
        "a caller that pinned its own budget is never overridden by the retry")
end

-- Playtest 25 September: a companion three tiles from its goal exhausted its
-- whole node budget and reported no route, then did it again, standing still
-- between attempts. A search that cannot reach the goal still knows the closest
-- ground it did reach; walking there is progress and leaves the next attempt a
-- shorter problem. Squeeze both the first budget and the retry so the search
-- genuinely runs out twice, which is the only way to reach this branch.
do
    local savedBudget = SC.Config._values.navigationNodeBudget
    local savedCeiling = SC.Config._values.navigationNodeBudgetMaximum
    local savedRetry = SC.Config._values.navigationBudgetRetryNodeBudget
    local savedGain = SC.Config._values.navigationPartialRouteMinimumGain
    SC.Config._values.navigationNodeBudget = 6
    SC.Config._values.navigationNodeBudgetMaximum = 6
    SC.Config._values.navigationBudgetRetryNodeBudget = 6

    local function runToEnd(goalX)
        local job = N.beginPathSearch(square(0, 0), square(goalX, 0), nil, {})
        local status, path, reason, slices = "pending", nil, nil, 0
        while status == "pending" and slices < 300 do
            status, path, reason = N.resumePathSearch(job, 1000)
            slices = slices + 1
        end
        return job, status, path, reason
    end

    local job, status, path, reason = runToEnd(60)
    local endpoint = type(path) == "table" and path[#path] or nil
    check(job.budgetRetried == true and status == "complete" and reason == "partial"
            and type(path) == "table" and #path >= 3,
        "a search that runs out twice hands back the closest ground it reached: "
            .. tostring(status) .. "/" .. tostring(reason)
            .. "/" .. tostring(type(path) == "table" and #path or path))
    check(endpoint ~= nil and endpoint:getX() > 0 and endpoint:getX() < 60,
        "a partial route ends nearer the goal than the start and short of the goal: "
            .. tostring(endpoint ~= nil and endpoint:getX()))

    -- The gain floor is what stops a route going nowhere being walked.
    SC.Config._values.navigationPartialRouteMinimumGain = 500
    local _, starvedStatus, starvedPath, starvedReason = runToEnd(60)
    SC.Config._values.navigationPartialRouteMinimumGain = savedGain
    check(starvedStatus == "failed" and starvedPath == nil and starvedReason == "budget",
        "a partial route that closes too little of the gap is still a failure: "
            .. tostring(starvedStatus) .. "/" .. tostring(starvedReason))

    SC.Config._values.navigationNodeBudget = savedBudget
    SC.Config._values.navigationNodeBudgetMaximum = savedCeiling
    SC.Config._values.navigationBudgetRetryNodeBudget = savedRetry

    -- Review R4: the hold flag recorded two different things at once. It means
    -- "this search's stale pulse was cancelled", which is why an ordinary
    -- waiting pass does not stop again -- but provisional movement issued
    -- afterwards is live input under that same flag, so returning to a wait
    -- silently declined to stop it.
    do
        local hold = N._holdForPathSearchForTests
        local previousNative = SC.NativeActions
        local stops = 0
        SC.NativeActions = { stopDirect = function() stops = stops + 1 return true end }

        local waiting = { pathSearchHolding = true }
        check(hold(actor, waiting) == true and stops == 0,
            "an ordinary waiting pass does not stop an actor that is already held")

        local moving = { pathSearchHolding = true, provisionalMoving = true }
        local held = hold(actor, moving)
        check(held == true and stops == 1 and moving.provisionalMoving == nil,
            "returning to a search hold stops outstanding provisional movement exactly once")
        check(hold(actor, moving) == true and stops == 1,
            "further stationary waiting does not stop again")

        SC.NativeActions = { stopDirect = function() stops = stops + 1 return false end }
        local refused = { pathSearchHolding = nil, provisionalMoving = true }
        check(hold(actor, refused) == false and refused.pathSearchHolding == false,
            "a refused stop is not reported as an acquired hold")
        SC.NativeActions = previousNative
    end

    -- Review R5: a provisional advance moves the actor on purpose while the
    -- search runs. Measuring the search against where the actor now stands
    -- discarded the very progress the advance was meant to overlap with.
    do
        local identity = N._searchSourceIdentity
        local here = SC.GameplayUtil.squareKey(square(0, 0))
        check(identity({}, square(0, 0)) == tostring(here),
            "a search with no anchor is identified by the actor's own square")
        check(identity({ pathSearch = { anchorKey = "9:9:0" }, provisionalAdvances = 0 },
                square(0, 0)) == tostring(here),
            "an anchor is not used until a provisional advance has actually moved the actor")
        check(identity({ pathSearch = { anchorKey = "9:9:0" }, provisionalAdvances = 1 },
                square(0, 0)) == "9:9:0",
            "a search that the actor has advanced under keeps its original anchor as its identity")
    end

    -- Playtest 26 September: one companion spent twelve minutes wedged in a
    -- chair and another eighteen minutes against a flowerpot, neither moving a
    -- tile. The engine path failed, we replanned, it failed again -- 54 and 35
    -- records from one position. The recovery ladder was never reached, because
    -- the native-failure branch returned before it.
    do
        local streakState = {}
        local stuckActor = { __class = "IsoPlayer", x = 4.3, y = 7.8, data = {} }
        function stuckActor:getX() return self.x end
        function stuckActor:getY() return self.y end
        function stuckActor:getZ() return 0 end
        function stuckActor:getModData() return self.data end
        function stuckActor:isDead() return false end

        check(N._noteNativeFailureStuck(stuckActor, streakState, 1000) == false,
            "one engine failure is not being stuck")
        check(N._noteNativeFailureStuck(stuckActor, streakState, 2000) == false,
            "two failures from the same spot is not yet being stuck")
        check(N._noteNativeFailureStuck(stuckActor, streakState, 3000) == true,
            "a third failure from ground the companion has not left is stuck")

        -- Sub-tile movement counts: being wedged never changes the square.
        stuckActor.x = 4.9
        check(N._noteNativeFailureStuck(stuckActor, streakState, 4000) == false,
            "moving within the tile restarts the count")
        check(N._noteNativeFailureStuck(stuckActor, streakState, 5000) == false
                and N._noteNativeFailureStuck(stuckActor, streakState, 6000) == true,
            "the count builds again from the new position")

        N._clearNativeFailureStreak(streakState)
        check(N._noteNativeFailureStuck(stuckActor, streakState, 7000) == false,
            "real progress clears the streak")

        local saved = SC.Config._values.navigationNativeFailureStuckAttempts
        SC.Config._values.navigationNativeFailureStuckAttempts = 1
        local eager = {}
        check(N._noteNativeFailureStuck(stuckActor, eager, 8000) == false
                and N._noteNativeFailureStuck(stuckActor, eager, 9000) == true,
            "the threshold is configurable")
        SC.Config._values.navigationNativeFailureStuckAttempts = saved
    end

    -- Playtest: a companion on the far side of a house stood against the wall
    -- while the player was audible on the other side. Going round means
    -- exploring away from the goal first, which a distance-led search does last
    -- and a modest budget never reaches. After a couple of honest failures for
    -- the same goal, spend properly once.
    do
        local detourState = {}
        local goal = square(40, 0)
        check(N._noteBudgetFailure(detourState, goal, 1000) == 1,
            "the first failure for a goal is counted")
        check(N._noteBudgetFailure(detourState, goal, 2000) == 2,
            "and the second")
        -- A different goal starts its own count: this is about one destination
        -- being awkward, not about a companion having a bad day.
        check(N._noteBudgetFailure(detourState, square(41, 0), 3000) == 1,
            "a different goal counts separately")
        -- Back to the awkward goal: the count starts again from one, so it
        -- takes two more failures to earn the bigger budget.
        check(N._noteBudgetFailure(detourState, goal, 4000) == 1,
            "returning to the awkward goal starts its count afresh")
        check(N._noteBudgetFailure(detourState, goal, 5000) == 2,
            "and reaches the threshold on the second")

        local derived = N._derivedNodeBudget(20)
        local fresh = {}
        check(N._detourNodeBudget(fresh, derived) == derived,
            "a goal that has not failed keeps the ordinary budget")
        check(N._detourNodeBudget(detourState, derived) > derived,
            "a goal that keeps failing is given room to go round: "
                .. tostring(N._detourNodeBudget(detourState, derived)))

        -- Real progress clears it, so one awkward corner does not make every
        -- later route expensive.
        N._clearBudgetFailures(detourState)
        check(N._detourNodeBudget(detourState, derived) == derived,
            "arriving somewhere resets the escalation")

        -- A caller that pinned its own ceiling asked for exactly that.
        local pinned = N._detourPathOptions({ budgetFailureCount = 9 },
            { nodeBudget = 12 }, square(0, 0), square(20, 0))
        check(pinned.nodeBudget == 12,
            "a pinned budget is never raised behind the caller's back")
    end

    -- A search that never left its start square has nothing to offer.
    check(P.partialPath({ bestKey = "0:0:0", startKey = "0:0:0" }, 0) == nil,
        "a search still on its start square offers no partial route")
    check(P.partialPath(nil, 0) == nil and P.partialPath({}, 0) == nil,
        "the partial route helper tolerates an absent search")
end

-- Playtest: a companion smashed a window and climbed straight through it,
-- glass and all, beside a player who was clearing theirs by hand. IsoWindow
-- keeps its smashed state in the same `destroyed` flag the generic "is this
-- opening passable" test reads as open, so the glass branch was unreachable.
do
    local pane = {}
    local function windowContext(smashed, glassRemoved, open, locked)
        return {
            windowSmashed = function() return smashed end,
            windowGlassRemoved = function() return glassRemoved end,
            objectOpen = function() return open end,
            objectLocked = function() return locked == true end,
        }
    end
    check(SC.NavTraversal.chooseWindowAction(pane, math.huge,
            windowContext(true, false, true)) == "remove_glass",
        "a smashed window reporting itself open still has its glass cleared first")
    check(SC.NavTraversal.chooseWindowAction(pane, math.huge,
            windowContext(true, false, false)) == "remove_glass",
        "a smashed window with glass clears it when there is time")
    check(SC.NavTraversal.chooseWindowAction(pane, 200,
            windowContext(true, false, true)) == "climb_window_emergency",
        "a threat arriving first still buys the injury deliberately")
    check(SC.NavTraversal.chooseWindowAction(pane, math.huge,
            windowContext(true, true, true)) == "climb_window",
        "a smashed window whose glass is gone is simply climbed")
    check(SC.NavTraversal.chooseWindowAction(pane, math.huge,
            windowContext(false, false, true)) == "climb_window",
        "an ordinary open window is simply climbed")
    check(SC.NavTraversal.chooseWindowAction(pane, math.huge,
            windowContext(false, false, false)) == "open_window",
        "a closed unlocked window is opened when there is time")
    check(SC.NavTraversal.chooseWindowAction(pane, math.huge,
            windowContext(false, false, false, true)) == "smash_window",
        "a locked window is smashed")
    check(SC.NavTraversal.chooseWindowAction(pane, 200,
            windowContext(false, false, false)) == "smash_window",
        "a closed window with a threat inbound is smashed rather than opened")
end

-- Planning holds the companion still, which is invisible on open ground and
-- seconds of standing in woodland. Heading at the goal while the route is
-- worked out is only safe on ground already proved open, and only briefly.
do
    local savedFlag = SC.Config._values.navigationProvisionalStepping
    local savedX, savedY = actor.x, actor.y
    actor.x, actor.y = 0.5, 0.5
    local advanceState = { blockedEdges = {}, blockedSquares = {}, routeMemory = {} }

    SC.Config._values.navigationProvisionalStepping = false
    check(N._provisionalAdvance(actor, advanceState, square(8, 0), {}, 1000) == nil,
        "the advance stays off until it is asked for")

    SC.Config._values.navigationProvisionalStepping = true
    local dx, dy, aim = N._provisionalAdvance(actor, advanceState, square(8, 0), {}, 1000)
    check(dx ~= nil and dx > 0 and math.abs(dy) < 0.001 and aim ~= nil,
        "an open bearing produces a vector toward the goal: "
            .. tostring(dx) .. "," .. tostring(dy))
    local reach = SC.Config.get("runtime", "navigationProvisionalReach") or 3
    check(math.sqrt(dx * dx + dy * dy) <= reach + 0.001,
        "the advance never reaches past its bound: " .. tostring(math.sqrt(dx * dx + dy * dy)))

    check(N._provisionalAdvance(actor, advanceState, square(0, 0), {}, 1000) == nil,
        "a goal already underfoot is not worth advancing toward")

    advanceState.provisionalAdvances = SC.Config.get("runtime",
        "navigationProvisionalAdvanceLimit") or 3
    check(N._provisionalAdvance(actor, advanceState, square(8, 0), {}, 1000) == nil,
        "the advance stops after its bounded number of attempts")
    advanceState.provisionalAdvances = 0

    -- A bearing the ground does not support falls back to waiting, as before.
    local savedSegment = SC.Topology.classifyEdge
    SC.Topology.classifyEdge = function(_, from, to)
        if to ~= nil and to.x ~= nil and to.x > 0 then
            return { traversable = false, reason = "blocked" }
        end
        return { traversable = true, cost = 1 }
    end
    check(N._provisionalAdvance(actor, advanceState, square(8, 0), {}, 1000) == nil,
        "a blocked bearing waits for the route instead of walking into it")
    SC.Topology.classifyEdge = savedSegment

    SC.Config._values.navigationProvisionalStepping = savedFlag
    actor.x, actor.y = savedX, savedY
end

-- Playtest: companions moved a tile at a time in forest. Each short follow
-- step fell through to a full search, because the straight-line shortcut
-- compared the whole edge cost against bare floor and a woodland edge is never
-- free. Undergrowth is subtracted now; a fence still sends it to the planner.
do
    local bushy = square(52, 4)
    function bushy:hasBush() return true end
    local from = square(51, 4)
    local passable, cost, _, _, _, hasBush, foliage =
        N._passableEdgeForTests(from, bushy, 1, { now = 1000 })
    check(passable == true and hasBush == true and (tonumber(foliage) or 0) > 0,
        "a bushy edge is passable and reports what the undergrowth costs: "
            .. tostring(cost) .. "/" .. tostring(foliage))
    check((tonumber(cost) or 0) - (tonumber(foliage) or 0) <= 1.001,
        "with the undergrowth taken off, a bushy edge costs bare floor: "
            .. tostring((tonumber(cost) or 0) - (tonumber(foliage) or 0)))

    local plain = square(54, 4)
    local plainFrom = square(53, 4)
    local _, plainCost, _, _, _, _, plainFoliage =
        N._passableEdgeForTests(plainFrom, plain, 1, { now = 1000 })
    check((tonumber(plainFoliage) or 0) == 0 and (tonumber(plainCost) or 0) <= 1.001,
        "open ground carries no undergrowth share: " .. tostring(plainFoliage))

    -- The shortcut itself: a line through undergrowth resolves without the
    -- planner, which is what stops the tile-at-a-time stepping in woods.
    local leafyMiddle = square(57, 4)
    function leafyMiddle:hasBush() return true end
    local throughBushes = N._fastOpenRouteForTests(square(56, 4), square(58, 4),
        { now = 1000 })
    check(type(throughBushes) == "table" and #throughBushes == 3,
        "a straight line through undergrowth is taken without planning: "
            .. tostring(throughBushes and #throughBushes
                or select(2, N._fastOpenRouteForTests(square(56, 4), square(58, 4),
                    { now = 1000 }))))
end

-- Playtest: companions in combat walked into fences and windows and kept
-- walking. Combat steers by a probe under half a tile, which lands back inside
-- the actor's own square, so the edge where a fence actually sits was never
-- examined and the native clearance test does not report one.
do
    local savedEdge = SC.Topology.classifyEdge
    local savedX, savedY = actor.x, actor.y
    actor.x, actor.y = 60.5, 4.5
    local quarry = { x = 64.5, y = 4.5 }
    function quarry:getX() return self.x end
    function quarry:getY() return self.y end
    function quarry:getZ() return 0 end
    function quarry:isDead() return false end
    function quarry:getSquare() return square(64, 4) end

    -- Open ground first: a vector toward the target, as before.
    local openX = N.combatVector(actor, quarry, "approach", nil)
    check(openX ~= nil and openX > 0,
        "an unobstructed approach still steers straight at the target: " .. tostring(openX))

    -- Now put a fence on every edge leaving the actor's tile.
    local savedBarrier = SC.Topology.barrierBetween
    SC.Topology.barrierBetween = function(from, to)
        if from ~= nil and to ~= nil and from.x == 60 and from.y == 4 then
            return {}, "fence"
        end
        return nil, "open"
    end
    local fencedX, _, _, fencedReason = N.combatVector(actor, quarry, "approach", nil)
    SC.Topology.barrierBetween = savedBarrier
    check(fencedX == nil and type(fencedReason) == "string"
            and string.sub(fencedReason, 1, 8) == "barrier:",
        "a fence across the approach is reported as something to climb, not a dead end: "
            .. tostring(fencedReason))
    actor.x, actor.y = savedX, savedY
end

SC_TEST_REPORT = "NAVIGATION_STABILITY_REGRESSION_PASS checks=" .. tostring(checks)
