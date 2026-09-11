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
SC_TEST_REPORT = "NAVIGATION_STABILITY_REGRESSION_PASS checks=" .. tostring(checks)
