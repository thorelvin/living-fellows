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
