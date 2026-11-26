-- SPDX-License-Identifier: MIT
-- Real planner/cache/traffic regressions from the Main Camp ten-minute soak.
local SC, checks = SurvivorCompanion, 0
local N, R, T, U = SC.Navigation, SC.WorkRoutes, SC.NavTraffic, SC.GameplayUtil
local function check(value, message)
    checks = checks + 1
    assert(value, "storage route/yield " .. checks .. ": " .. message)
end
local grid, blocked, edgeCalls = {}, false, 0
local function square(x, y, z)
    z = z or 0
    if math.abs(x) > 30 or math.abs(y) > 10 or z ~= 0 then return nil end
    local key = x .. ":" .. y .. ":" .. z
    if grid[key] then return grid[key] end
    local s = { x = x, y = y, z = z, moving = {}, objects = {} }
    function s:getX() return self.x end
    function s:getY() return self.y end
    function s:getZ() return self.z end
    function s:getObjects() return self.objects end
    function s:getSpecialObjects() return self.objects end
    function s:getMovingObjects() return self.moving end
    function s:isFree() return true end
    function s:isSolid() return false end
    function s:isSolidTrans() return false end
    function s:TreatAsSolidFloor() return true end
    grid[key] = s
    return s
end
function getCell() return { getGridSquare = function(_, x, y, z) return square(x, y, z) end } end
local function actor(id, x, y)
    local a = { __class = "IsoPlayer", id = id, x = x or 0.5, y = y or 0.5,
        data = { SC_CommandSerial = 7 } }
    function a:getX() return self.x end
    function a:getY() return self.y end
    function a:getZ() return 0 end
    function a:getSquare() return square(math.floor(self.x), math.floor(self.y)) end
    function a:getCurrentSquare() return self:getSquare() end
    function a:getModData() return self.data end
    function a:isDead() return false end
    return a
end
SC.Actor = {
    isCompanion = function() return true end,
    stop = function(a) a.stops = (a.stops or 0) + 1 return true end,
    setMovement = function(a, _, intent) a.lastMove = intent return true end,
}
SC.Topology.classifyEdge = function(_, from, to)
    edgeCalls = edgeCalls + 1
    local closed = blocked and from.x == 1 and from.y == 0 and to.x == 2 and to.y == 0
    return { traversable = not closed, reason = closed and "door_locked" or nil,
        cost = from.x ~= to.x and from.y ~= to.y and math.sqrt(2) or 1 }
end

-- The same expedition threshold can become passable while the crew waits.
do
    local scout = actor("waiting-site-entry", 1.5, 0.5)
    local outside, inside = square(1, 0), square(2, 0)
    local state = {}
    local intent = { action = "expedition_enter_site", preferVerifiedPath = true,
        expeditionEntryPortal = true, expeditionEntryFrom = outside }
    blocked = true
    N._seedVerifiedRoute(scout, state, outside, inside, intent, SC_TEST_CLOCK)
    check(state.path == nil and state.verifiedPathAttemptKey ~= nil,
        "a locked threshold supplies no direct route")
    blocked = false
    N._seedVerifiedRoute(scout, state, outside, inside, intent, SC_TEST_CLOCK + 12000)
    check(state.path and #state.path == 2 and state.path[1] == outside and state.path[2] == inside,
        "the same selected threshold is revalidated after it opens")
end

-- A full shelf sends ordinary Logistics to a marked floor. Its floor survey
-- must lend the proved path to the real drop transaction without replanning.
do
    local previousBase, previousMedicKit = SC.BaseLife, SC.MedicKit
    local previousStatus, previousRoom = SC.Logistics.status, U.containerHasRoom
    local previousTargets, previousClock = N.interactionTargets, SC_TEST_CLOCK
    local worker = actor("overflow-worker")
    local floorTile, endpoint = square(8, 0), square(7, 0)
    local cabinetSquare = square(2, 2)
    local cabinet, cargo = {}, {}
    function cargo:getID() return 117 end
    function cargo:getFullType() return "Base.DuctTape" end
    local root = { items = { cargo } }
    function root:contains(item) return item == cargo end
    function worker:getInventory() return root end

    local base = { id = "overflow-fixture", zones = { { id = "marked-floor",
        kind = "sorting_floor", x1 = 8, x2 = 8, y1 = 0, y2 = 0, z = 0 } } }
    local row = { id = "full-cabinet", category = "general" }
    SC.BaseLife = {
        active = function() return base end,
        isInside = function() return true end,
        storageRows = function(category) return category == "general" and { row } or {} end,
        resolveContainer = function(storage)
            if storage == row then return cabinet, cabinetSquare end
        end,
    }
    SC.MedicKit = { busy = function() return false end }
    SC.Logistics.status = function()
        return { shouldUnload = true, inventory = root,
            surplus = { item = cargo, category = "general", source = root } }
    end
    U.containerHasRoom = function(container)
        check(container == cabinet, "ordinary logistics found the full camp cabinet")
        return false, "destination_full"
    end
    N.interactionTargets = function(_, object)
        check(object == floorTile, "real navigation surveys the marked floor instead of full storage")
        return { endpoint }
    end

    local searches, search = 0, SC.PathSearch.new
    SC.PathSearch.new = function(...)
        searches = searches + 1
        return search(...)
    end
    local seen, request = {}, N.requestAny
    N.requestAny = function(worker, candidates, mode, intent)
        seen.receipt, seen.owner, seen.token = intent.interactionRouteReceipt,
            intent.interactionRouteOwner, intent.supervisorToken
        seen.before = searches
        seen.accepted, seen.reason = request(worker, candidates, mode, intent)
        seen.after = searches
        return seen.accepted, seen.reason
    end
    for _ = 1, 50 do
        local accepted, reason = SC.Logistics.update(worker, nil, { snapshot = {} })
        if seen.receipt then break end
        check(accepted and reason == "storage_route_pending",
            "real logistics keeps the exact cargo during a pending floor survey: " .. tostring(reason))
        SC_TEST_CLOCK = SC_TEST_CLOCK + 100
    end
    check(seen.before and seen.before > 0 and seen.receipt and seen.token
            and seen.token.owner == "logistics" and seen.token.action == "logistics_drop",
        "ordinary logistics creates its floor transaction and route")
    check(seen.receipt.used and seen.receipt.ownerState == seen.owner,
        "ordinary movement consumes the surveyed route under its exact owner: "
            .. tostring(seen.receipt.failure))
    local state = N.peek(worker)
    check(seen.accepted and state and state.pathReason == "interaction_route_receipt"
            and state.path == seen.receipt.path and state.multiGoalSelected == endpoint,
        "movement adopts the surveyed standing path: " .. tostring(seen.reason))
    check(seen.before == seen.after and root:contains(cargo),
        "approach avoids a second path search and retains the cargo")
    N.cancel(worker, "floor_receipt_transaction_fixture")
    SC.ActionSupervisor.cancel(worker, "floor_receipt_transaction_fixture", nil, true)
    SC.BaseLife, SC.MedicKit = previousBase, previousMedicKit
    SC.Logistics.status, U.containerHasRoom = previousStatus, previousRoom
    N.interactionTargets, SC_TEST_CLOCK = previousTargets, previousClock
    SC.PathSearch.new, N.requestAny = search, request
end

-- Native movement enters the final square before necessarily settling near
-- its centre. A verified expedition entry is complete on the exact tile.
do
    local previousExpedition = SC.ExpeditionPrototype
    local scout = actor("return-entry-worker", 5.98, 0.5)
    local endpoint = square(6, 0)
    local path = { square(4, 0), square(5, 0), endpoint }
    local receipt = { used = true, path = path }
    local navigation = N._stateForTests(scout)
    navigation.goalSquare, navigation.goalAction = endpoint, "ordered_move"
    navigation.path, navigation.pathGoalSquare, navigation.pathIndex = path, endpoint, 3
    navigation.pathStealthAvoidance = false
    local confirmed = false
    SC.ExpeditionPrototype = { stalledReturnReceiptFor = function(actor, destination)
        if confirmed and actor == scout and destination == endpoint then return receipt end
    end }
    local intent = { action = "ordered_move", arrivalDistance = 0.35, requireSameSquare = true,
        stalledReturnReceipt = receipt }
    confirmed = true
    local accepted, status = N.request(scout, endpoint, "walk", intent)
    check(accepted and status ~= "arrived" and navigation.path == path,
        "a verified return keeps moving while still on the adjacent square: "
            .. tostring(accepted) .. "/" .. tostring(status) .. "/" .. tostring(navigation.path == path))
    scout.x, scout.y = 6.02, 0.02
    confirmed = false
    accepted, status = N.request(scout, endpoint, "walk", intent)
    check(not accepted and status == "return_entry_owner_changed",
        "a withdrawn receipt cannot complete just inside its old tile")
    scout.x, scout.y = 6.5, 0.5
    accepted, status = N.request(scout, endpoint, "walk", intent)
    check(not accepted and status == "return_entry_owner_changed",
        "a withdrawn receipt cannot complete via generic centre arrival")
    scout.x, scout.y = 6.02, 0.02
    confirmed = true
    accepted, status = N.request(scout, endpoint, "walk", intent)
    check(accepted and status == "arrived" and navigation.path == nil,
        "an owned verified route completes at the edge of its exact loaded destination: " .. tostring(status))
    N.cancel(scout, "return_entry_fixture")
    SC.ExpeditionPrototype = previousExpedition
end

local worker = actor("route-worker")
local owner, object = {}, { target = square(3, 0) }
function object:getSquare() return self.target end
local normalTargets = N.interactionTargets
N.interactionTargets = function(_, value) return { value.target } end
local selected, reason, receipt
for _ = 1, 60 do
    selected, reason, receipt = N.selectInteraction(worker, owner, "deposit:test", {
        { id = "shelf", object = object },
    }, { retainRoute = true, nodeQuota = 32 })
    if selected then break end
end
check(selected and receipt and receipt.path[#receipt.path] == object.target,
    "a storage survey returns its actual proved route rather than discarding it")
check(receipt.ownerState == owner and receipt.actor == worker and receipt.object == object,
    "receipt retains exact actor, runtime owner and world object identities")
local function copyReceipt()
    local copy = {}
    for key, value in pairs(receipt) do
        if key ~= "used" and key ~= "invalidated" and key ~= "failure" then copy[key] = value end
    end
    return copy
end
local function routeState()
    return { blockedEdges = {}, blockedSquares = {}, routeMemory = {} }
end
local function intent(copy)
    return { action = "move_to_base_storage", object = object,
        interactionRouteReceipt = copy, interactionRouteOwner = owner,
        goalCandidates = { object.target, square(3, 1) } }
end
local searches, oldNew = 0, SC.PathSearch.new
SC.PathSearch.new = function(...)
    searches = searches + 1
    return oldNew(...)
end
local before = searches
local accepted = N.requestAny(worker, { square(3, 1), object.target }, "walk", intent(receipt))
local actual = N.peek(worker)
check(accepted and actual.pathReason == "interaction_route_receipt" and searches == before,
    "physical multi-target approach adopts the surveyed path without another A-star search")
check(actual.path[#actual.path] == object.target and actual.multiGoalSelected == object.target,
    "receipt endpoint stays the owned interaction goal even when offered after another tile")
check(receipt.used == true, "a receipt is consumed once")
N.cancel(worker, "fixture_reset")

local function reject(change, message)
    local copy, request, state = copyReceipt(), nil, routeState()
    request = intent(copy)
    change(copy, request, state)
    check(not N._adoptInteractionRoute(worker, state, worker:getSquare(), object.target,
        request, SC_TEST_CLOCK) and state.path == nil, message)
end
reject(function(_, request) request.interactionRouteOwner = {} end,
    "another job runtime cannot consume the receipt")
reject(function(copy) copy.actor = actor("other") end, "another actor cannot consume the receipt")
reject(function(_, request) request.object = {} end, "a replacement destination object invalidates the receipt")
reject(function(copy) copy.commandSerial = 6 end, "a newer player command invalidates the receipt")
reject(function(copy) copy.expiresAt = SC_TEST_CLOCK - 1 end, "expired receipt is rejected")
reject(function(_, request) request.goalCandidates = { square(3, 1) } end,
    "removed interaction endpoint is rejected")
reject(function(copy) copy.source = square(1, 0) end, "a moved source requires a fresh or repaired route")
reject(function(_, _, state) state.nativeLease = { foreign = true } end,
    "a receipt does not replace a live native movement lease")
local supervisor = SC.ActionSupervisor
SC.ActionSupervisor = { isCurrent = function(token) return token.current == true end,
    movementPermission = function(_, _, request)
        return request.supervisorToken == nil or request.supervisorToken.phase ~= "committing"
    end }
reject(function(_, request) request.supervisorToken = { actor = worker, current = false } end,
    "a stale supervisor token cannot adopt a receipt")
local token = { actor = worker, current = true, phase = "approaching", serial = 8 }
local copy, state = copyReceipt(), routeState()
local request = intent(copy)
request.supervisorToken = token
check(N._adoptInteractionRoute(worker, state, worker:getSquare(), object.target,
    request, SC_TEST_CLOCK), "the current physical action owner may consume the receipt")
blocked = true
reject(function() end, "a newly locked edge rejects the receipt before movement")
blocked = false
local base = SC.BaseLife
SC.BaseLife = { admitsWork = function() return false end }
reject(function(_, value) value.workCampOnly = true end,
    "changed camp admission rejects the route prefix")
SC.BaseLife = base

local searchWorker, searchOwner, compartment = actor("building-search"), {}, {}
local searchChoices = { { id = "station-shelf", object = object, container = compartment, tier = 1 } }
local searchOptions = { expeditionScavenge = true, maxChoices = 4, targetsPerChoice = 8,
    nodeBudget = 300, nodeQuota = 24, retainRoute = true }
local function surveySearch(runtime, key, mover)
    return N.selectInteraction(mover or searchWorker, runtime, key, searchChoices, searchOptions)
end
local performance, resume = SC.Performance, N.resumePathSearch
local deadline, grant, calls, charged, frame = 0, 0, 0, 0, 1
local surveyPerformance = setmetatable({
    frameId = function() return frame end,
    remainingBudgetMs = function() return deadline end,
    claimUnits = function(kind, requested, urgent, tracked)
        check(kind == "navigation" and requested == 24 and not urgent and tracked,
            "the building survey shares the ordinary navigation expansion budget")
        return grant, grant > 0 and "search-claim" or nil
    end,
    settleUnits = function(claim, used)
        check(claim == "search-claim" and used > 0 and used <= grant,
            "the search settles only its consumed capacity")
        charged = charged + used
    end,
}, { __index = performance })
SC.Performance = surveyPerformance
N.resumePathSearch = function(job, quota)
    calls = calls + 1
    check(quota == grant and job.pathOptions.sliceBudgetMs == math.max(1, deadline),
        "each resume uses the granted nodes and current frame time")
    return resume(job, quota)
end
before = searches
local result, why = surveySearch(searchOwner, "police-search")
check(not result and why == "pending" and searches == before,
    "a spent frame with no navigation quota starts no search")
deadline = 1.25
result, why = surveySearch(searchOwner, "police-search")
check(not result and why == "pending" and calls == 0,
    "zero available navigation nodes do not resume the search")
local pendingOwner, time = {}, SC_TEST_CLOCK
result, why = surveySearch(pendingOwner, "elapsed-search")
check(not result and why == "pending", "an exhausted quota still retains a pending survey")
SC_TEST_CLOCK = time + 3001
result, why = surveySearch(pendingOwner, "elapsed-search")
check(not result and why == "unknown" and calls == 0,
    "three seconds of waiting defer the source without claiming a route is unreachable")
SC_TEST_CLOCK = time
deadline, grant = 0, 1
result, why = surveySearch(searchOwner, "police-search")
check(not result and why == "pending" and calls == 1 and charged == 1,
    "a busy frame still advances one timed survey slice from the shared navigation quota")
local secondSearchWorker, secondSearchOwner = actor("building-search-peer"), {}
result, why = surveySearch(secondSearchOwner, "peer-search", secondSearchWorker)
check(not result and why == "pending" and calls == 1 and secondSearchOwner.navigationChoice.job == nil,
    "a second searcher waits once the frame's survey slice is granted")
frame = frame + 1
result, why = surveySearch(secondSearchOwner, "peer-search", secondSearchWorker)
check(not result and why == "pending" and calls == 2 and charged == 2,
    "a different searcher can use a tracked slice on the next busy frame")
local searchReceipt
deadline = 1.25
grant = 24
for _ = 1, 30 do
    frame = frame + 1
    result, why, searchReceipt = surveySearch(searchOwner, "police-search")
    if result then break end
end
SC.Performance, N.resumePathSearch = performance, resume
check(result == searchChoices[1] and searchReceipt and searchReceipt.container == compartment
    and searchReceipt.expeditionScavenge == true and charged > 0,
    "the bounded survey retains the chosen exact compartment and route")

do
    local startedAt = SC_TEST_CLOCK
    local slowOwner, cappedOwner, stalledOwner, movedOwner = {}, {}, {}, {}
    local resumes, finishAt = 0, 5
    SC.Performance, grant = surveyPerformance, 1
    N.resumePathSearch = function(job)
        resumes = resumes + 1
        job.progressSerial = resumes
        if resumes == finishAt then
            return "complete", { job.startSquare, square(1, 0), square(2, 0), job.goalSquare },
                nil, resumes, nil, 1
        end
        return "pending", nil, "searching", resumes, nil, 1
    end
    local function at(runtime, key, elapsed)
        SC_TEST_CLOCK, frame = startedAt + elapsed, frame + 1
        return surveySearch(runtime, key)
    end
    for index = 0, 3 do
        local winner, outcome = at(slowOwner, "slow-search", index * 1000)
        check(not winner and outcome == "pending", "progress keeps the same loaded Search frontier past three seconds")
    end
    local winner, outcome, proof = at(slowOwner, "slow-search", 4000)
    check(winner == searchChoices[1] and outcome == "selected" and proof and proof.container == compartment,
        "a busy but progressing Search obtains the exact route receipt")

    resumes, finishAt = 0, nil
    for index = 0, 11 do
        local _, outcome = at(cappedOwner, "bounded-slow-search", index * 1000)
        check(outcome == "pending", "live progress admits no more than the bounded Search window")
    end
    local _, cap = at(cappedOwner, "bounded-slow-search", 12000)
    check(cap == "unknown" and resumes == 12, "an indeterminate Search ends even with continuous progress")

    resumes = 0
    at(stalledOwner, "stalled-search", 0)
    local _, stalled = at(stalledOwner, "stalled-search", 3001)
    check(stalled == "unknown" and resumes == 1, "a stalled started Search keeps the three-second idle bound")

    resumes = 0
    at(movedOwner, "moved-search", 0)
    at(movedOwner, "moved-search", 2000)
    searchWorker.x = searchWorker.x + 1
    local _, moved = at(movedOwner, "moved-search", 3000)
    check(moved == "unknown" and resumes == 2, "changing the origin cannot extend an old Search frontier")
    searchWorker.x = searchWorker.x - 1
    SC_TEST_CLOCK, SC.Performance, N.resumePathSearch = startedAt, performance, resume
end

local searchToken = { actor = searchWorker, owner = "encounter", action = "scavenge",
    current = true, phase = "approaching", serial = 9 }
SC.ActionSupervisor = {
    isCurrent = function(value) return value.current == true end,
    movementPermission = function() return true end,
}
searchReceipt.scavengeMissionId, searchReceipt.boundToken = "police", searchToken
local function searchIntent(proof)
    return { action = "move_to_scavenge", object = object, container = compartment,
        scavengeMissionId = "police", supervisorToken = searchToken,
        requireSameSquare = true, preferVerifiedPath = true,
        interactionRouteReceipt = proof, interactionRouteOwner = searchOwner }
end
local function rejectSearch(change, candidates, why)
    local proof = {}
    for key, value in pairs(searchReceipt) do proof[key] = value end
    local request = searchIntent(proof)
    change(proof, request)
    local beforeSearch = searches
    local moved, reason = N.requestAny(searchWorker, candidates, "walk", request)
    check(not moved and reason == "scavenge_route_invalidated" and proof.invalidated
        and searches == beforeSearch, why)
end
local contact = { object.target }
rejectSearch(function() end, { square(3, 1) }, "Search drops a receipt for a missing standing tile")
rejectSearch(function(_, request) request.scavengeMissionId = "other" end, contact,
    "a different mission cannot use the proof or start a new plan")
rejectSearch(function(_, request) request.container = {} end, contact,
    "another compartment on the same object requires its own proof")
rejectSearch(function(proof) proof.expiresAt = SC_TEST_CLOCK - 1 end, contact,
    "an expired Search receipt does not trigger a duplicate plan")
blocked = true
rejectSearch(function() end, contact, "a new locked prefix rejects the receipt before a new plan")
blocked = false
N.cancel(searchWorker, "scavenge_fixture_reset")
before = searches
accepted = N.requestAny(searchWorker, { square(2, 1), object.target }, "walk", searchIntent(searchReceipt))
actual = N.peek(searchWorker)
check(accepted and actual.pathReason == "interaction_route_receipt" and searchReceipt.used
    and actual.multiGoalSelected == object.target and searches == before,
    "the Search consumes its proof once and starts movement toward the proved endpoint")
check(R.key(searchWorker, object.target, searchIntent(searchReceipt)) == nil,
    "the Search proof leaves the shared camp route cache untouched")
N.cancel(searchWorker, "scavenge_fixture_reset")
SC.ActionSupervisor = supervisor
SC.ActionSupervisor = supervisor

-- Candidate-set caching learns a different endpoint than the nearest tile.
R.reset()
local path = { square(0, 0), square(0, 1), square(1, 1), square(2, 1), square(3, 1) }
local cacheIntent = { action = "move_to_base_storage", object = object }
local routeKey = R.key(worker, square(3, 1), cacheIntent)
check(R.record(routeKey, path, SC_TEST_CLOCK), "learned storage detour is recorded")
local cached, entry, endpoint = R.lookupCandidates(worker, worker:getSquare(),
    { object.target, square(3, 1) }, cacheIntent, { actor = worker, now = SC_TEST_CLOCK }, SC_TEST_CLOCK)
check(cached and entry and endpoint == square(3, 1),
    "multi-target lookup finds the cached offered endpoint instead of repeating selection")
check(R.lookupCandidates(worker, worker:getSquare(), { object.target }, cacheIntent,
    { actor = worker }, SC_TEST_CLOCK) == nil, "cache cannot use an endpoint removed from the candidate set")
check(R.lookupCandidates(worker, worker:getSquare(), { square(3, 1) },
    { action = "combat_approach", urgent = true }, { actor = worker }, SC_TEST_CLOCK) == nil,
    "combat cannot use stationary-storage cache shortcuts")
local fast = N._fastOpenRouteForRequest
N._fastOpenRouteForRequest = function() return nil end
before = searches
accepted = N.requestAny(worker, { object.target, square(3, 1) }, "walk", cacheIntent)
actual = N.peek(worker)
check(accepted and actual.pathReason == "work_route_cache" and searches == before
    and actual.pathGoalSquare == square(3, 1),
    "requestAny physically follows the cached alternate endpoint without starting A-star")
N._fastOpenRouteForRequest = fast
N.cancel(worker, "fixture_cache_done")
R.reset()

-- Passage sessions retain the recipient's bay until the requester passes.
local first, second = actor("first", 0.5, 0.5), actor("second", 1.5, 0.5)
local firstState, secondState = N._stateForTests(first), N._stateForTests(second)
firstState.routeTargetSignature = "shelf"
local function beginSession()
    T.cancelYield(first, "fixture_reset")
    first.x, first.y, second.x, second.y = 0.5, 0.5, 1.5, 0.5
    return T.beginYield(first, second, firstState, secondState, square(1, 1),
        square(1, 0), { action = "move_to_base_storage" }, SC_TEST_CLOCK, true)
end
local session, fresh = beginSession()
check(session and fresh and secondState.crowdMove.yieldSession == session,
    "a clearance request creates one shared passage session")
SC_TEST_CLOCK = SC_TEST_CLOCK + 3000
local retained, restarted = T.beginYield(first, second, firstState, secondState,
    square(2, 1), square(1, 0), {}, SC_TEST_CLOCK, true)
check(retained == session and not restarted and retained.clearance == square(1, 1),
    "waiting beyond the old deadlock threshold retains the same bay and deadline")
second.x, second.y = 1.5, 1.5
local held, heldReason = N.serviceCrowdYield(second, {})
check(held and heldReason == "holding_clearance_for_passage" and secondState.crowdMove ~= nil,
    "a worker waits in its clearance bay rather than immediately blocking the passage again")
first.x = 1.5
check(T.pollYield(first, SC_TEST_CLOCK, {}) == nil and session.endReason == "passed"
    and secondState.crowdMove == nil, "physical passage releases the recipient")
session = beginSession()
first.data.SC_CommandSerial = 8
check(T.pollYield(second, SC_TEST_CLOCK, {}) == nil and session.endReason == "owner_changed",
    "a player order ends the temporary clearance obligation")
first.data.SC_CommandSerial = 7
session = beginSession()
check(T.pollYield(first, SC_TEST_CLOCK, { immediateCount = 1 }) == nil
    and secondState.crowdMove == nil, "danger releases the clearance session")
session = beginSession()
check(T.pollYield(first, session.expiresAt, {}) == nil, "a blocked passing bay cannot hold either actor forever")
session = beginSession()
T.cancel(first, firstState)
check(secondState.crowdMove == nil and T.pollYield(second, SC_TEST_CLOCK, {}) == nil,
    "navigation cancellation releases both sides of the session")

SC.ActionSupervisor = { isCurrent = function(value) return value.current == true end,
    movementPermission = function(_, _, value)
        return value.supervisorToken ~= nil and value.supervisorToken.phase == "approaching"
    end }
local ownerToken = { actor = second, current = true, phase = "committing" }
secondState.lastApproachRequest = { intent = { supervisorToken = ownerToken } }
session = beginSession()
second.x, second.y = 1.5, 1.5
local stops = second.stops or 0
check(not N.serviceCrowdYield(second, {}) and (second.stops or 0) == stops,
    "clearance does not stop or move a protected committing transaction")
ownerToken.phase = "approaching"
held, heldReason = N.serviceCrowdYield(second, {})
check(held and heldReason == "holding_clearance_for_passage",
    "a resumed approach lends its existing owner token to the temporary clearance move")
SC.ActionSupervisor = supervisor
T.cancelYield(first, "fixture_done")

-- A requester can end the passage before the recipient gets another turn.
-- Revocation must reach the physical route, without stopping a newer owner.
local function physicalSession()
    N.cancel(second, "fixture_new_physical_session")
    firstState, secondState = N._stateForTests(first), N._stateForTests(second)
    firstState.routeTargetSignature = "shelf"
    first.data.SC_CommandSerial, second.data.SC_CommandSerial = 7, 7
    local value = beginSession()
    for _ = 1, 4 do
        N.serviceCrowdYield(second, {})
        SC_TEST_CLOCK = SC_TEST_CLOCK + 100
    end
    check(N.peek(second) and N.peek(second).goalAction == "crowd_yield_order",
        "the recipient first receives a physical clearance movement request")
    return value
end
for _, ending in ipairs({ "danger", "owner_changed", "expired", "navigation_cancelled" }) do
    session = physicalSession()
    local stopsBefore = second.stops or 0
    if ending == "danger" then
        T.pollYield(first, SC_TEST_CLOCK, { immediateCount = 1 })
    elseif ending == "owner_changed" then
        first.data.SC_CommandSerial = 8
        T.pollYield(first, SC_TEST_CLOCK, {})
    elseif ending == "expired" then
        T.pollYield(first, session.expiresAt, {})
    else
        T.cancel(first, firstState)
    end
    N.serviceCrowdYield(second, { immediateCount = 1 })
    check(N.peek(second) == nil and (second.stops or 0) > stopsBefore,
        "requester " .. ending .. " revokes the recipient's exact physical clearance route")
end

session = physicalSession()
local newerToken = { actor = second, phase = "committing", current = true }
SC.ActionSupervisor = {
    current = function() return newerToken end,
    isCurrent = function(value) return value == newerToken end,
    movementPermission = function() return true end,
}
local stopsBefore = second.stops or 0
T.pollYield(first, SC_TEST_CLOCK, { immediateCount = 1 })
N.serviceCrowdYield(second, {})
check(N.peek(second) ~= nil and secondState.endedCrowdYield ~= nil
        and (second.stops or 0) == stopsBefore,
    "a teardown cannot stop a newer transaction even if it allows the action name")
SC.ActionSupervisor = supervisor
N.request(second, square(2, 1), "walk", { action = "base_guard_patrol" })
stopsBefore = second.stops or 0
N.serviceCrowdYield(second, {})
check(N.peek(second) and N.peek(second).goalAction == "base_guard_patrol"
        and secondState.endedCrowdYield == nil and (second.stops or 0) == stopsBefore,
    "deferred teardown discards stale proof after another physical route takes ownership")
N.cancel(second, "fixture_done")

-- Repeated conflict speech is separate from routing and needs sustained clear.
local speech = 0
SC.Dialogue = { register = function() end, say = function() speech = speech + 1 return true, "line" end }
SC.Commands = { peek = function() return { recruited = true } end }
SC.Banter.reset()
SC_TEST_CLOCK = 100000
check(SC.Banter.crowdYield(first, second, SC_TEST_CLOCK), "the first accepted clearance request speaks")
SC_TEST_CLOCK = SC_TEST_CLOCK + 8001
check(not SC.Banter.crowdYield(first, second, SC_TEST_CLOCK) and speech == 1,
    "the same blockage does not repeat its bark every eight seconds")
SC_TEST_CLOCK = 130000
check(SC.Banter.crowdYield(first, second, SC_TEST_CLOCK) and speech == 2,
    "a continuing blockage can remind the player after thirty seconds")
SC.Banter.crowdYieldClear(first, 138000)
SC.Banter.crowdYieldClear(first, 139000)
check(not SC.Banter.crowdYield(first, second, 139001),
    "one second of clearance cannot reset the episode")
for at = 140000, 143000, 500 do SC.Banter.crowdYieldClear(first, at) end
check(SC.Banter.crowdYield(first, second, 143001) and speech == 3,
    "three sustained clear seconds permit a genuinely new clearance request")
N.interactionTargets, SC.PathSearch.new = normalTargets, oldNew
SC_TEST_REPORT = "STORAGE_ROUTE_YIELD_REGRESSION_PASS checks=" .. checks
