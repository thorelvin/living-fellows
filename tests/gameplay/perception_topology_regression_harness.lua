-- SPDX-License-Identifier: MIT
-- Real topology/perception code with instrumented native-world boundaries.
local SC, checks = SurvivorCompanion, 0
local U, T, S, Scan = SC.GameplayUtil, SC.Topology, SC.Senses, SC.PerceptionScan
local function check(value, message)
    checks = checks + 1
    assert(value, "perception/topology regression " .. checks .. ": " .. message)
end
local current, calls = 100000, 0
function getTimestampMs() return current end
local nativeCall = U.call
U.call = function(...) calls = calls + 1 return nativeCall(...) end
local grid, zombies = {}, {}
local function square(x, y, z)
    z = z or 0
    local key = x .. ":" .. y .. ":" .. z
    if grid[key] then return grid[key] end
    local value = { x=x, y=y, z=z, objects={}, moving={}, portals={} }
    function value:getX() return self.x end
    function value:getY() return self.y end
    function value:getZ() return self.z end
    function value:getObjects() return self.objects end
    function value:getSpecialObjects() return self.objects end
    function value:getMovingObjects() return self.moving end
    function value:getVehicleContainer() return self.vehicle end
    function value:isSolid() return self.solid == true end
    function value:isSolidTrans() return false end
    function value:TreatAsSolidFloor() return true end
    function value:isFree() return not self.solid end
    function value:isBlockedTo(other) return self.blockAll == true end
    function value:getDoorTo(other) return self.portals[other] end
    function value:getRoom() return nil end
    function value:has() return false end
    function value:testPathFindAdjacent() return false end
    grid[key] = value
    return value
end
local list = { reads = 0 }
function list:size() return #zombies end
function list:get(index) self.reads = self.reads + 1 return zombies[index + 1] end
local cell = {}
function cell:getGridSquare(x, y, z) return square(math.floor(x), math.floor(y), math.floor(z)) end
function cell:getZombieList() return list end
function getCell() return cell end
local function actor(x, y, z, class)
    local value = { x=x, y=y, z=z or 0, __class=class or "IsoPlayer", data={} }
    function value:getX() return self.x end
    function value:getY() return self.y end
    function value:getZ() return self.z end
    function value:getSquare() return square(math.floor(self.x), math.floor(self.y), math.floor(self.z)) end
    function value:getModData() return self.data end
    function value:getHealth() return 100 end
    function value:isDead() return self.dead == true end
    function value:getVariableBoolean() return false end
    function value:CanSee(target) return target.hidden ~= true end
    return value
end
local observer, origin = actor(0.5, 0.5), square(0, 0)
local function readGrid()
    local passed = 0
    for x = 0, 4 do
        for y = 0, 4 do
            for _, delta in ipairs({{1,0},{0,1},{-1,0},{0,-1},{1,1},{1,-1},{-1,1},{-1,-1}}) do
                for _ = 1, 2 do
                    if T.classifyEdge(observer, square(x,y), square(x+delta[1],y+delta[2]), {}).traversable then
                        passed = passed + 1
                    end
                end
            end
        end
    end
    return passed
end
calls = 0
local plainResult = readGrid()
local plainCalls = calls
calls = 0
local batchedResult = T.withReadBatch(readGrid)
local batchCalls = calls
check(plainResult == 400 and batchedResult == plainResult, "batching preserves all eight-direction edge results")
check(batchCalls < plainCalls * 0.55 and T.lastBatch.hits > 0,
    "read batching removes repeated native topology work without changing passability")
local destination = square(1,0)
local door = { open = true, locked = false }
function door:IsOpen() return self.open end
function door:isLocked() return self.locked end
origin.portals[destination] = door
check(T.withReadBatch(T.classifyEdge, observer, origin, destination, {}).traversable,
    "open door is traversable in one read batch")
door.open, door.locked = false, true
check(not T.withReadBatch(T.classifyEdge, observer, origin, destination, {}).traversable,
    "a door locked between slices cannot retain cached passability")
origin.portals[destination] = nil
destination.vehicle = {}
check(T.withReadBatch(T.classifyEdge, observer, origin, destination, {}).affordance == "vehicle",
    "a newly parked vehicle is read in the next batch")
destination.vehicle = nil
destination.objects = { { __class = "IsoTrap" } }
T.withReadBatch(function()
    check(not T.classifyEdge(observer, origin, destination, {}).traversable
            and T.classifyEdge(observer, origin, destination, {allowHazards=true}).traversable,
        "emergency hazard policy never shares an ordinary-safe memo entry")
end)
destination.objects = {}
check(not pcall(T.withReadBatch, function()
    T.classifyEdge(observer, origin, destination, {})
    error("fixture interruption")
end), "a failed read slice propagates failure")
destination.solid = true
check(not T.classifyEdge(observer, origin, destination, {}).traversable,
    "failure releases its memo before the next world read")
destination.solid = false

local job = T.newEscapeSearch(observer, origin, {nodeBudget=64, radius=5})
local timeReads = 0
local raw, exits, meta = T.resumeEscapeSearch(job, 24, 1, function()
    timeReads = timeReads + 1 return 100
end)
check(meta.used == 4 and #raw == 4 and not meta.complete,
    "expired emergency deadline still establishes four neighbors, then yields")
local pulses = 1
repeat
    raw, exits, meta = T.resumeEscapeSearch(job, 24)
    check(meta.used <= 24, "each escape continuation respects its edge quota")
    pulses = pulses + 1
until meta.complete or pulses > 20
check(meta.complete and #raw > 20 and pulses > 1, "bounded continuations complete a useful deeper escape map")
local deepNode
for _, node in ipairs(raw) do
    if (tonumber(node.distance) or 0) >= 2 then deepNode = node break end
end
check(deepNode ~= nil and T.validateEscapeNode(observer, deepNode, {}),
    "a completed escape node retains a live-verifiable parent route")

local function routeNode(parent, x, y, distance)
    return {
        square = square(x, y), x = x, y = y, z = 0,
        fromSquare = parent.square, parent = parent,
        distance = distance, traversalCost = distance,
    }
end
local corridorRoot = { square = origin, x = 0, y = 0, z = 0, distance = 0 }
local exposedOne = routeNode(corridorRoot, 1, 0, 1)
local exposedTwo = routeNode(exposedOne, 1, 1, 2)
local exposedThree = routeNode(exposedTwo, 1, 2, 3)
local exposedFour = routeNode(exposedThree, 1, 3, 4)
local exposedEnd = routeNode(exposedFour, 0, 3, 5)
local shelteredOne = routeNode(corridorRoot, -1, 0, 1)
local shelteredTwo = routeNode(shelteredOne, -1, -1, 2)
local shelteredThree = routeNode(shelteredTwo, -1, -2, 3)
local shelteredFour = routeNode(shelteredThree, -1, -3, 4)
local shelteredEnd = routeNode(shelteredFour, 0, -3, 5)
local corridorState = {
    escapeImmediateCount = 1,
    escapeTopology = {
        raw = { exposedEnd, shelteredEnd }, exits = {}, complete = true,
        originKey = U.squareKey(origin), signature = "corridor-fixture",
        computedAt = current, processed = 10,
    },
}
local corridorThreat = actor(5, 0, 0, "IsoZombie")
local savedValidatedCandidateLimit = SC.Config._overrides.escapeValidatedCandidateLimit
SC.Config._overrides.escapeValidatedCandidateLimit = 2
local corridorCandidates = S._collectEscapeSquaresForTests(observer, {
    { actor = corridorThreat, x = 5, y = 0, z = 0 },
}, corridorState, current, 1)
SC.Config._overrides.escapeValidatedCandidateLimit = savedValidatedCandidateLimit
check(#corridorCandidates == 2
        and corridorCandidates[1].square == shelteredEnd.square
        and corridorCandidates[1].danger == 0
        and corridorCandidates[1].corridorDanger == 0
        and corridorCandidates[2].danger == 0
        and corridorCandidates[2].corridorDanger == 1,
    "escape scoring rejects an empty endpoint whose actual parent corridor brushes a zombie")

deepNode.square.vehicle = {}
check(not T.validateEscapeNode(observer, deepNode, {}),
    "a vehicle inserted on an earlier escape result invalidates that route")
local blockerState = {
    escapeImmediateCount = 1,
    escapeTopology = {
        raw = { deepNode }, exits = {}, complete = true,
        originKey = U.squareKey(origin), signature = "fixture", computedAt = current,
        processed = 1,
    },
}
local blockedCandidates = S._collectEscapeSquaresForTests(observer,
    { { actor = actor(-1, 0.5, 0, "IsoZombie"), x = -1, y = 0.5, z = 0 } },
    blockerState, current, 1)
check(#blockedCandidates == 0,
    "a stale cached escape square is never exposed after blocker insertion")
deepNode.square.vehicle = nil

local doorA, doorB = { open = true, locked = false }, { open = true, locked = false }
function doorA:IsOpen() return self.open end
function doorA:isLocked() return self.locked end
function doorB:IsOpen() return self.open end
function doorB:isLocked() return self.locked end
local corridorMiddle, corridorEnd = square(1, 0), square(2, 0)
origin.portals[corridorMiddle], corridorMiddle.portals[corridorEnd] = doorA, doorB
local rootNode = { square = origin }
local middleNode = { square = corridorMiddle, fromSquare = origin, parent = rootNode }
local endNode = { square = corridorEnd, fromSquare = corridorMiddle, parent = middleNode }
local portalJob = {
    portals = {
        { object = doorA, fromSquare = origin, toSquare = corridorMiddle,
            signature = T.objectStateSignature(doorA) },
        { object = doorB, fromSquare = corridorMiddle, toSquare = corridorEnd,
            signature = T.objectStateSignature(doorB) },
    },
}
local validationClockReads = 0
local valid, validationComplete = T.escapeSearchValid(portalJob, 1, function()
    validationClockReads = validationClockReads + 1
    return validationClockReads
end)
check(valid and not validationComplete,
    "two-portal cache validation yields with a resumable deadline cursor")
doorA.open, doorA.locked = false, true
valid, validationComplete = T.escapeSearchValid(portalJob)
check(valid and validationComplete and not T.validateEscapeNode(observer, endNode, {}),
    "final selected-route validation catches an early portal changed across validation slices")
doorA.open, doorA.locked = true, false
origin.portals[corridorMiddle], corridorMiddle.portals[corridorEnd] = nil, nil
local inner, outer = square(1,0), square(2,0)
door.open, door.locked = true, false
inner.portals[outer] = door
local changingJob = T.newEscapeSearch(observer, origin, {nodeBudget=64, radius=5})
T.resumeEscapeSearch(changingJob, 8)
check(#changingJob.portals == 1, "an escape continuation tracks the actual door beyond its origin")
door.open, door.locked = false, true
raw, exits, meta = T.resumeEscapeSearch(changingJob, 8)
check(meta.invalidated and #raw == 0 and not T.escapeSearchValid(changingJob),
    "a deeper door closed between escape slices invalidates the partial route")
inner.portals[outer] = nil

local runtime = {}
local quiet = S.snapshot(observer, nil, runtime)
check(quiet.threatCount == 0 and #quiet.escapeSquares == 0 and runtime.senses.escapeSearch == nil,
    "quiet companions skip combat escape geometry entirely")
-- Off-axis 20-tile contacts were outside the old radius and starved by near/ray
-- grid scheduling. Native-list discovery must reach them without weakening LOS.
for index = 1, 160 do zombies[index] = actor(100 + index, 100, 0, "IsoZombie") end
local distant = actor(12.5,16.5,0,"IsoZombie")
local hidden = actor(20.5,0.5,0,"IsoZombie") hidden.hidden = true
local upstairs = actor(0.5,20.5,1,"IsoZombie")
local tooFar = actor(25.5,0.5,0,"IsoZombie")
zombies[161], zombies[162], zombies[163], zombies[164] = distant, hidden, upstairs, tooFar
local seenAt, snapshot = nil, quiet
for pulse = 1, 5 do
    current = current + 100
    local before = list.reads
    snapshot = S.refreshImmediate(observer, nil, snapshot, runtime)
    check(list.reads - before <= 64, "native distant discovery is cursor-bounded per reflex")
    for _, threat in ipairs(snapshot.threats) do
        check(threat.actor ~= hidden and threat.actor ~= upstairs and threat.actor ~= tooFar,
            "walls, floors, and visual radius remain strict")
        if threat.actor == distant then seenAt = seenAt or pulse * 100 end
    end
end
check(seenAt ~= nil and seenAt <= 300, "off-axis twenty-tile zombie is acquired within three bounded pulses")
check((snapshot.heardThreatCount or 0) == 0, "extended sight does not extend distant hearing")
distant.hidden = true
current = current + 100
snapshot = S.refreshImmediate(observer, nil, snapshot, runtime)
check(snapshot.threatCount == 0, "a newly blocked visual contact is removed on the next reflex")

-- The LOS budget is applied as a resumable candidate window. A dozen closer
-- contacts behind a wall must not permanently mask the visible thirteenth one
-- every time the native list wraps.
local occluded = {}
for index = 1, 12 do
    occluded[index] = actor(index, 0.5, 0, "IsoZombie")
    occluded[index].hidden = true
end
local visibleTail = actor(20.5, 0.5, 0, "IsoZombie")
zombies = occluded
zombies[13] = visibleTail
local starvationRuntime = {}
current = current + 100
local starvationSnapshot = S.snapshot(observer, nil, starvationRuntime)
check(starvationSnapshot.threatCount == 0,
    "the first bounded LOS window contains only the nearer occluded contacts")
current = current + 100
starvationSnapshot = S.refreshImmediate(observer, nil, starvationSnapshot, starvationRuntime)
local tailSeen = false
for _, threat in ipairs(starvationSnapshot.threats or {}) do
    if threat.actor == visibleTail then tailSeen = true end
end
check(tailSeen and starvationRuntime.senses.nativeDiscovery.pending == 0,
    "a visible candidate behind a full occluded window is resumed, not starved")

-- More established contacts than the LOS slice may contain must not blink out.
-- The actual combat target is reserved even when it is not the nearest record,
-- while the remaining validation tail resumes ahead of already checked actors.
local crowd, crowdRecords = {}, {}
for index = 1, 24 do
    local angle = index * math.pi * 2 / 24
    local range = 5 + index * 0.4
    crowd[index] = actor(observer.x + math.cos(angle) * range,
        observer.y + math.sin(angle) * range, 0, "IsoZombie")
    local dx, dy = crowd[index].x - observer.x, crowd[index].y - observer.y
    local distanceSq = dx * dx + dy * dy
    crowdRecords[index] = {
        actor = crowd[index], square = crowd[index]:getSquare(),
        x = crowd[index].x, y = crowd[index].y, z = 0,
        distanceSq = distanceSq, distance = math.sqrt(distanceSq),
        visible = true, obstructed = false, score = 40 - index,
        attacking = false, targeting = false, grounded = false,
        posture = "standing", visualValidatedAt = current,
    }
end
zombies = crowd
local crowdSnapshot = {
    valid = true, time = current, threats = crowdRecords,
    stealthThreats = crowdRecords, groundedThreats = {},
    immediateAttackers = {}, fencedThreats = {}, nearestThreat = crowdRecords[1],
    threatCount = #crowdRecords, pressure = #crowdRecords * 0.35,
    escapeSquares = {}, exits = {}, sounds = {}, allies = {}, protectedActors = {},
    player = { available = false, danger = 0 },
}
local crowdRuntime = { senses = { current = crowdSnapshot }, combatTarget = crowd[24] }
local originalObserverCanSee = observer.CanSee
function observer:CanSee(target)
    target.losChecks = (target.losChecks or 0) + 1
    return originalObserverCanSee(self, target)
end
crowd[24].hidden = true
current = current + 100
crowdSnapshot = S.refreshImmediate(observer, nil, crowdSnapshot, crowdRuntime)
local hiddenCommittedRetained = false
local resumedActor
for _, record in ipairs(crowdSnapshot.threats or {}) do
    if record.actor == crowd[24] then hiddenCommittedRetained = true end
    if record.visualDeferred == true then resumedActor = resumedActor or record.actor end
end
check(not hiddenCommittedRetained and (crowd[24].losChecks or 0) == 1,
    "a non-nearest committed combat target is force-revalidated in the same pulse")
check(crowdSnapshot.threatCount == 23 and resumedActor ~= nil
        and crowdSnapshot.reflexVisualDeferred > 0,
    "fresh established contacts survive one bounded deferred LOS pulse without flicker")
local resumedBefore = resumedActor.losChecks or 0
crowdRuntime.combatTarget = nil
current = current + 100
crowdSnapshot = S.refreshImmediate(observer, nil, crowdSnapshot, crowdRuntime)
check((resumedActor.losChecks or 0) > resumedBefore,
    "the persistent LOS queue resumes its deferred tail before recycling checked contacts")

local closeActors, closeRecords = {}, {}
for index = 1, 13 do
    local angle = index * math.pi * 2 / 13
    closeActors[index] = actor(observer.x + math.cos(angle) * 1.4,
        observer.y + math.sin(angle) * 1.4, 0, "IsoZombie")
    closeRecords[index] = {
        actor = closeActors[index], square = closeActors[index]:getSquare(),
        x = closeActors[index].x, y = closeActors[index].y, z = 0,
        distanceSq = 1.96, distance = 1.4, visible = true, obstructed = false,
        attacking = false, targeting = false, grounded = false,
        posture = "standing", score = 50 - index, visualValidatedAt = current,
    }
end
zombies = closeActors
local closeSnapshot = {
    valid = true, time = current, threats = closeRecords, stealthThreats = closeRecords,
    groundedThreats = {}, immediateAttackers = closeRecords, fencedThreats = {},
    nearestThreat = closeRecords[1], threatCount = 13, pressure = 19.5,
    escapeSquares = {}, exits = {}, sounds = {}, allies = {}, protectedActors = {},
    player = { available = false, danger = 0 },
}
local closeRuntime = { senses = { current = closeSnapshot } }
current = current + 100
closeSnapshot = S.refreshImmediate(observer, nil, closeSnapshot, closeRuntime)
check((closeActors[13].losChecks or 0) == 0
        and #(closeRuntime.senses.visualValidationQueue or {}) >= 1,
    "the urgent hard cap defers rather than drops contact thirteen")
current = current + 100
closeSnapshot = S.refreshImmediate(observer, nil, closeSnapshot, closeRuntime)
check((closeActors[13].losChecks or 0) > 0,
    "deferred urgent contacts rotate ahead of the sustained immediate set")

local established, establishedRecords, newcomers = {}, {}, {}
for index = 1, 20 do
    local angle = index * math.pi * 2 / 20
    local range = 6 + index * 0.2
    established[index] = actor(observer.x + math.cos(angle) * range,
        observer.y + math.sin(angle) * range, 0, "IsoZombie")
    establishedRecords[index] = {
        actor = established[index], square = established[index]:getSquare(),
        x = established[index].x, y = established[index].y, z = 0,
        distanceSq = range * range, distance = range,
        visible = true, obstructed = false, attacking = false, targeting = false,
        grounded = false, posture = "standing", score = 60 - index,
        visualValidatedAt = current,
    }
end
for index = 1, 20 do
    local angle = (index + 0.5) * math.pi * 2 / 20
    local range = 13 + index * 0.2
    newcomers[index] = actor(observer.x + math.cos(angle) * range,
        observer.y + math.sin(angle) * range, 0, "IsoZombie")
end
established[20].x, established[20].y = observer.x + 1.2, observer.y
square(1, 0).moving = { established[20] }
zombies = {}
for _, value in ipairs(established) do zombies[#zombies + 1] = value end
for _, value in ipairs(newcomers) do zombies[#zombies + 1] = value end
local mixedSnapshot = {
    valid = true, time = current, threats = establishedRecords,
    stealthThreats = establishedRecords, groundedThreats = {},
    immediateAttackers = {}, fencedThreats = {}, nearestThreat = establishedRecords[1],
    threatCount = 20, pressure = 7, escapeSquares = {}, exits = {}, sounds = {},
    allies = {}, protectedActors = {}, player = { available = false, danger = 0 },
}
local mixedRuntime = { senses = { current = mixedSnapshot } }
local movedChecks = established[20].losChecks or 0
local establishedSet, hadDeferredEstablished, acquiredNew = {}, false, false
local minimumEstablishedRetained = #established
for _, value in ipairs(established) do establishedSet[value] = true end
for pulse = 1, 5 do
    current = current + 100
    mixedSnapshot = S.refreshImmediate(observer, nil, mixedSnapshot, mixedRuntime)
    local retainedThisPulse = 0
    for _, record in ipairs(mixedSnapshot.threats or {}) do
        if establishedSet[record.actor] then
            retainedThisPulse = retainedThisPulse + 1
            if record.visualDeferred == true then hadDeferredEstablished = true end
        end
        for _, newcomer in ipairs(newcomers) do
            if record.actor == newcomer then acquiredNew = true break end
        end
    end
    minimumEstablishedRetained = math.min(minimumEstablishedRetained, retainedThisPulse)
end
local allEstablishedValidated = true
for _, value in ipairs(established) do
    if (value.losChecks or 0) <= 0 then allEstablishedValidated = false break end
end
check((established[20].losChecks or 0) > movedChecks,
    "an established ordinary contact entering melee is promoted to urgent that pulse")
check(hadDeferredEstablished and acquiredNew and allEstablishedValidated
        and minimumEstablishedRetained >= 16,
    "mixed contacts retain most established pressure and give every old and new cohort fair LOS turns")
square(1, 0).moving = {}

local dense = {}
for index = 1, 200 do dense[index] = actor(0.75, 0.75, 0, "IsoZombie") end
zombies, origin.moving = dense, dense
local denseSnapshot = {
    valid = true, time = current, threats = {}, stealthThreats = {},
    groundedThreats = {}, immediateAttackers = {}, fencedThreats = {},
    threatCount = 0, pressure = 0, escapeSquares = {}, exits = {}, sounds = {},
    allies = {}, protectedActors = {}, player = { available = false, danger = 0 },
}
local denseRuntime = { senses = { current = denseSnapshot } }
local denseReads = list.reads
current = current + 100
denseSnapshot = S.refreshImmediate(observer, nil, denseSnapshot, denseRuntime)
local denseLos = 0
for _, value in ipairs(dense) do denseLos = denseLos + (value.losChecks or 0) end
check(denseLos <= 12 and list.reads - denseReads <= 64
        and #(denseRuntime.senses.visualValidationQueue or {}) <= 64,
    "two hundred close candidates keep LOS, discovery, and deferred queues hard-bounded")
origin.moving = {}

local clutter = {}
for index = 1, 60 do clutter[index] = actor(0.7, 0.7, 0, "IsoPlayer") end
local clutterAttacker = actor(1.1, 0.5, 0, "IsoZombie")
clutter[#clutter + 1] = clutterAttacker
zombies, origin.moving = {}, clutter
local clutterSnapshot = {
    valid = true, time = current, threats = {}, stealthThreats = {},
    groundedThreats = {}, immediateAttackers = {}, fencedThreats = {},
    threatCount = 0, pressure = 0, escapeSquares = {}, exits = {}, sounds = {},
    allies = {}, protectedActors = {}, player = { available = false, danger = 0 },
}
local clutterRuntime = { senses = { current = clutterSnapshot } }
current = current + 100
clutterSnapshot = S.refreshImmediate(observer, nil, clutterSnapshot,
    clutterRuntime)
check(clutterSnapshot.threatCount == 0,
    "a crowded square respects its per-pulse moving-object cap")
current = current + 100
clutterSnapshot = S.refreshImmediate(observer, nil, clutterSnapshot,
    clutterRuntime)
check(clutterSnapshot.threatCount == 1
        and clutterSnapshot.threats[1].actor == clutterAttacker,
    "the per-square object cursor reaches an attacker behind irrelevant bodies next pulse")
origin.moving = {}
observer.CanSee = originalObserverCanSee

local heard = actor(2,0.5,0,"IsoZombie") heard.hidden = true
zombies = { heard }
current = current + 100
snapshot = S.refreshImmediate(observer, nil, snapshot, runtime)
check(snapshot.threatCount == 0 and snapshot.heardThreatCount == 1
        and snapshot.heardThreats[1].actor == nil and snapshot.heardThreats[1].square == nil,
    "nearby hidden noise remains non-targetable hearing information")
local deadlineState, reads = {}, list.reads
for index = 1, 160 do zombies[index] = actor(100+index,100,0,"IsoZombie") end
local results, limited = Scan.nativeCandidates(observer, deadlineState, 24, 64, 1, function() return 100 end)
check(limited.processed == 4 and list.reads - reads == 4 and #results == 0,
    "native discovery also observes an elapsed-time deadline with bounded minimum progress")

-- A sequential cursor gave a target at the tail of a 1000-zombie cell list a
-- roughly 25-second worst case when every slice hit its time limit. The shared
-- outside-in roster must discover that tail under the very first costly slice.
Scan.reset()
zombies = {}
for index = 1, 999 do zombies[index] = actor(100 + index, 100, 0, "IsoZombie") end
local lateTarget = actor(12.5, 16.5, 0, "IsoZombie")
zombies[1000] = lateTarget
local costlyNow, costlyReads = 1000, list.reads
local function advancingClock()
    costlyNow = costlyNow + 0.25
    return costlyNow
end
local lateResults, lateMeta = Scan.nativeCandidates(observer, {}, 24, 64,
    costlyNow + 0.5, advancingClock)
local lateSeen = false
for _, candidate in ipairs(lateResults) do
    if candidate == lateTarget then lateSeen = true break end
end
check(lateSeen and lateMeta.processed == 4 and list.reads - costlyReads == 4
        and lateMeta.complete == false,
    "a late relevant zombie in a 1000-entry list is acquired in one bounded costly slice")

-- Reaching the end with more candidates than one LOS window used to reset the
-- cursor to zero before the tail drained, so completion was never observable.
Scan.reset()
zombies = {}
for index = 1, 40 do zombies[index] = actor(3 + index * 0.05, 1, 0, "IsoZombie") end
local completionState, completionMeta, sawEndWithTail = {}, nil, false
for pulse = 1, 6 do
    current = current + 100
    _, completionMeta = Scan.nativeCandidates(observer, completionState, 24, 64)
    if completionMeta.endReached and completionMeta.pending > 0 then
        sawEndWithTail = true
    end
    if completionMeta.complete then break end
end
check(sawEndWithTail and completionMeta.complete and completionMeta.listComplete
        and completionMeta.pending == 0 and completionMeta.cursor == 40,
    "native completion remains pending until the observer drains the final candidate tail")

-- The producer must be free to lap observers without invalidating an adopted
-- immutable roster. Exercise two observers at deliberately different cadences.
Scan.reset()
zombies = {}
for index = 1, 400 do
    zombies[index] = actor(3 + (index % 20) * 0.02,
        2 + (math.floor(index / 20) % 20) * 0.02, 0, "IsoZombie")
end
local fastState, slowState = {}, {}
local fastSeen, slowSeen, fastCount, slowCount = {}, {}, 0, 0
local fastCompletedCycle, slowCompletedCycle = 0, 0
for pulse = 1, 900 do
    current = current + 100
    local fastResult, fastMeta = Scan.nativeCandidates(observer, fastState, 24, 64)
    for _, candidate in ipairs(fastResult) do
        if not fastSeen[candidate] then fastSeen[candidate], fastCount = true, fastCount + 1 end
    end
    if fastMeta.complete then fastCompletedCycle = math.max(fastCompletedCycle, fastMeta.cycle or 0) end
    if pulse % 4 == 0 then
        local slowResult, slowMeta = Scan.nativeCandidates(observer, slowState, 24, 64)
        for _, candidate in ipairs(slowResult) do
            if not slowSeen[candidate] then slowSeen[candidate], slowCount = true, slowCount + 1 end
        end
        if slowMeta.complete then slowCompletedCycle = math.max(slowCompletedCycle, slowMeta.cycle or 0) end
    end
    check(not fastState.nativeCandidateQueue or #fastState.nativeCandidateQueue <= 64,
        "fast observer retains the native candidate queue hard cap")
    check(not slowState.nativeCandidateQueue or #slowState.nativeCandidateQueue <= 64,
        "slow observer retains the native candidate queue hard cap")
    if fastCount == 400 and slowCount == 400
        and fastCompletedCycle >= 2 and slowCompletedCycle >= 2 then break end
end
check(fastCount == 400 and slowCount == 400
        and fastCompletedCycle >= 2 and slowCompletedCycle >= 2,
    "producer cycles may pass observers at different cadences without losing roster tails")

-- scanComplete is an evidence claim: producer discovery and the per-observer LOS
-- queue must both be complete in the currently published cycle.
Scan.reset()
local savedLosPerSlice = SC.Config._overrides.perceptionNativeLosPerSlice
local savedVisualPerSlice = SC.Config._overrides.perceptionVisualChecksPerSlice
SC.Config._overrides.perceptionNativeLosPerSlice = 32
SC.Config._overrides.perceptionVisualChecksPerSlice = 4
zombies = {}
for index = 1, 48 do zombies[index] = actor(4 + index * 0.01, 2, 0, "IsoZombie") end
local coverageRuntime, coverageSnapshot = {}, nil
current = current + 100
coverageSnapshot = S.snapshot(observer, nil, coverageRuntime)
check(coverageSnapshot.nativeDiscovery.complete ~= true
        and coverageSnapshot.scanDiscoveryComplete ~= true
        and coverageSnapshot.scanComplete == false,
    "unfinished native discovery is never advertised as complete room coverage")
local sawDeferredCompleteDiscovery = false
for pulse = 1, 80 do
    current = current + 100
    coverageSnapshot = S.snapshot(observer, nil, coverageRuntime)
    if coverageSnapshot.scanDiscoveryComplete == true
        and coverageSnapshot.visualDeferred > 0 then
        sawDeferredCompleteDiscovery = true
        check(coverageSnapshot.scanVisualComplete == false
                and coverageSnapshot.scanComplete == false,
            "pending LOS validation blocks complete room coverage")
        break
    end
end
SC.Config._overrides.perceptionNativeLosPerSlice = savedLosPerSlice
SC.Config._overrides.perceptionVisualChecksPerSlice = savedVisualPerSlice
check(sawDeferredCompleteDiscovery,
    "room-coverage fixture reaches complete discovery with a deliberately deferred LOS tail")

-- Cancelling danger must also cancel its partial topology result. Otherwise a
-- returning threat inside the cache TTL would treat a four-edge prefix as a
-- complete escape map.
zombies = { actor(1.5, 0.5, 0, "IsoZombie") }
local interruptedRuntime = {}
current = current + 100
local dangerSnapshot = S.snapshot(observer, nil, interruptedRuntime)
local partialJob = interruptedRuntime.senses.escapeSearch
check(partialJob ~= nil and interruptedRuntime.senses.escapeTopology.complete ~= true,
    "threatened escape planning exposes a partial bounded continuation")
zombies[1].dead = true
current = current + 100
local calmSnapshot = S.snapshot(observer, nil, interruptedRuntime)
check(calmSnapshot.threatCount == 0 and interruptedRuntime.senses.escapeSearch == nil
        and interruptedRuntime.senses.escapeTopology == nil,
    "calm cancellation discards partial escape geometry")
zombies = { actor(1.5, 0.5, 0, "IsoZombie") }
current = current + 100
S.snapshot(observer, nil, interruptedRuntime)
check(interruptedRuntime.senses.escapeSearch ~= partialJob,
    "returning danger starts a newly verified escape search")

zombies = {}
for index = 1, 160 do zombies[index] = actor(100+index,100,0,"IsoZombie") end
zombies[161], distant.hidden = distant, false
local party, partyStates, partySnapshots, partySeen = {}, {}, {}, {}
for index = 1, 4 do
    party[index], partyStates[index] = actor(0.5,0.5), {}
    partySnapshots[index] = S.snapshot(party[index], nil, partyStates[index])
    check(partySnapshots[index].discoveryMode == "native_cursor"
            and partySnapshots[index].scanCoverage.native == true,
        "native discovery avoids allocating the old square schedule for each companion")
end
local partyPeak = 0
for pulse = 1, 3 do
    current = current + 100
    local before = list.reads
    for index = 1, 4 do
        partySnapshots[index] = S.refreshImmediate(party[index], nil,
            partySnapshots[index], partyStates[index])
        for _, threat in ipairs(partySnapshots[index].threats) do
            if threat.actor == distant then partySeen[index] = true end
        end
    end
    partyPeak = math.max(partyPeak, list.reads - before)
end
check(partySeen[1] and partySeen[2] and partySeen[3] and partySeen[4] and partyPeak <= 64,
    "four companions share one native-list chunk while retaining independent perception")
U.call = nativeCall
SC_TEST_REPORT = "PERCEPTION_TOPOLOGY_REGRESSION_PASS checks=" .. checks
    .. " native_boundary_calls=" .. plainCalls .. "->" .. batchCalls
    .. " detection_20m_ms=" .. tostring(seenAt) .. " escape_pulses=" .. pulses
    .. " four_actor_peak_native_reads=" .. partyPeak
