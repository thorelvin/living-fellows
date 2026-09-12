-- SPDX-License-Identifier: MIT
-- Standalone/last harness: real traversal, geometry, blocker and micro-steering modules.
local SC, checks = SurvivorCompanion, 0
local U, N, T = SC.GameplayUtil, SC.Navigation, SC.NativeTraversalActions
local function check(value, message)
    checks = checks + 1
    assert(value, "navigation traversal regression " .. checks .. ": " .. message)
end
local current = 900000
local oldClock = getTimestampMs
function getTimestampMs() return current end
IsoDirections = { N = "N", S = "S", E = "E", W = "W" }
local function square(x, y, z)
    local value = { x = x, y = y, z = z or 0, moving = {}, objects = {} }
    function value:getX() return self.x end
    function value:getY() return self.y end
    function value:getZ() return self.z end
    function value:getMovingObjects() return self.moving end
    function value:getObjects() return self.objects end
    function value:getSpecialObjects() return self.objects end
    function value:TreatAsSolidFloor() return true end
    function value:isSolid() return false end
    function value:isSolidTrans() return false end
    function value:isFree() return true end
    return value
end
local function actor()
    local value = { __class = "IsoPlayer", x = 0.5, y = 0.5, z = 0,
        square = square(0, 0), calls = 0, cancelAllowed = true }
    function value:getX() return self.x end
    function value:getY() return self.y end
    function value:getZ() return self.z end
    function value:getSquare() return self.square end
    function value:getCurrentSquare() return self.square end
    function value:getModData() return {} end
    function value:getVariableBoolean(name) return self[name] == true end
    function value:getCurrentState() return self.nativeState end
    function value:isDead() return false end
    function value:isClimbing() return self.climbing == true end
    function value:isClimbingRope() return self.climbing == true end
    function value:isCompanionMovementClear() return true end
    function value:isCollidable() return self.collidable ~= false end
    function value:canClimbOverWall() return true end
    function value:canClimbSheetRope() return true end
    function value:canClimbDownSheetRope() return true end
    function value:request()
        self.calls = self.calls + 1
        if self.reject then return false end
        self.event = true
    end
    function value:hopFence(_, testOnly)
        if testOnly == true then
            self.hopTests = (self.hopTests or 0) + 1
            return not self.reject
        end
        return self:request()
    end
    value.climbOverFence, value.climbOverWall = value.request, value.request
    value.climbThroughWindow, value.climbSheetRope = value.request, value.request
    function value:triggerContextualAction(action, object)
        self.contextualAction, self.contextualObject = action, object
        return self:request()
    end
    function value:climbThroughWindowFrame(...)
        self.frameClimb = true
        return self:request(...)
    end
    value.climbDownSheetRope, value.openWindow, value.smashWindow = value.request, value.request, value.request
    function value:cancelCompanionTraversal()
        if not self.cancelAllowed then return false end
        self.event, self.climbing = nil, false
        return true
    end
    return value
end
T.configure({
    invoke = function(object, name, ...)
        if object == nil or type(object[name]) ~= "function" then return false, "unavailable:" .. name end
        return true, object[name](object, ...)
    end,
    useProvider = function() return nil end,
    stopDirect = function(value) value.stopped = true return true end,
})
local provider = { directNative = true }
for _, action in ipairs({ "climb_fence", "climb_wall", "climb_window",
    "climb_sheet_rope", "climb_down_sheet_rope" }) do
    local value, object = actor(), {}
    local intent = { object = object, direction = "east", fromSquare = value.square,
        toSquare = square(1, 0) }
    local handler = action == "climb_window" and T.window
        or (action == "climb_fence" or action == "climb_wall") and T.fence or T.sheetRope
    local accepted = handler(value, action, intent, provider)
    check(accepted and value.event and not value.climbing, action .. " accepts a queued event")
    check(T.activityStatus(value) == "active", action .. " owns actor while starting")
    handler(value, action, intent, provider)
    check(value.calls == 1, action .. " does not submit duplicate event")
    current = current + 100
    value.nativeState = { __class = ({ climb_fence = "ClimbOverFenceState",
        climb_wall = "ClimbOverWallState", climb_window = "ClimbThroughWindowState",
        climb_sheet_rope = "ClimbSheetRopeState", climb_down_sheet_rope = "ClimbDownSheetRopeState" })[action] }
    check(T.poll(value) == "active" and not value:isClimbing(),
        action .. " observes real native state even when legacy climbing field stays false")
    current = current + 1600
    check(T.poll(value) == "active" and value.event,
        action .. " cannot time out startup after genuine native entry")
    value.nativeState, value.x = nil, 1.5
    current = current + 100
    check(T.poll(value) == "completed", action .. " verifies later displacement and exit")
    T.reset(value)
end
local overshootActor = actor()
local overshootFrom, overshootTo = overshootActor.square, square(1, 0)
check(T.fence(overshootActor, "climb_fence", {
    direction = "east", fromSquare = overshootFrom, toSquare = overshootTo,
}, provider) == true, "overshoot traversal starts")
overshootActor.nativeState = { __class = "ClimbOverFenceState" }
current = current + 100
check(T.poll(overshootActor) == "active", "overshoot traversal enters native state")
overshootActor.nativeState, overshootActor.x = nil, 2.3
current = current + 100
local overshootPhase, _, overshootRecord = T.poll(overshootActor)
check(overshootPhase == "completed" and overshootRecord.destinationVerifiedAt ~= nil
        and SC.NavTraversal.clearTraversalExit(
            overshootActor, overshootRecord, current, {}) == true,
    "crossing the requested boundary remains success when root motion lands beyond one tile")
T.reset(overshootActor)
local timeoutActor = actor()
T.fence(timeoutActor, "climb_fence", { direction = "east" }, provider)
timeoutActor.cancelAllowed = false
current = current + 1600
check(T.poll(timeoutActor) == "starting" and T.activityStatus(timeoutActor) == "active",
    "timeout retains ownership if native pending event cannot be cancelled")
timeoutActor.cancelAllowed = true
current = current + 300
check(T.poll(timeoutActor) == "failed" and not timeoutActor.event,
    "timeout only releases ownership after native cancellation")
T.reset(timeoutActor)
local rejectedActor = actor()
rejectedActor.reject = true
check(not T.fence(rejectedActor, "climb_fence", { direction = "east" }, provider)
    and T.poll(rejectedActor) == "none", "explicit native rejection has no pending owner")
local objectlessFenceActor = actor()
function objectlessFenceActor:hopFence()
    self.incorrectLowFenceCalls = (self.incorrectLowFenceCalls or 0) + 1
    return false
end
function objectlessFenceActor:climbOverFence(direction)
    self.objectlessFenceDirection = direction
    return self:request()
end
check(T.fence(objectlessFenceActor, "climb_fence", {
        direction = "east", objectlessFenceFallback = true,
        fromSquare = objectlessFenceActor.square, toSquare = square(1, 0),
    }, provider)
        and objectlessFenceActor.objectlessFenceDirection == IsoDirections.E
        and objectlessFenceActor.incorrectLowFenceCalls == nil,
    "an objectless square fence uses the engine's matching inherited climb entry point")
T.reset(objectlessFenceActor)
local incapableWallActor = actor()
function incapableWallActor:canClimbOverWall() return false end
check(not T.fence(incapableWallActor, "climb_wall", { direction = "east" }, provider)
    and T.poll(incapableWallActor) == "none",
    "adjacent tall-wall dispatch still rejects a character that cannot climb")
local companionWallActor = actor()
function companionWallActor:climbCompanionOverWall(direction)
    self.companionWallDirection = direction
    return self:request()
end
function companionWallActor:climbOverWall()
    self.incorrectInheritedWallCall = true
    return false
end
check(T.fence(companionWallActor, "climb_wall", {
        direction = "east", fromSquare = companionWallActor.square,
        toSquare = square(1, 0),
    }, provider)
        and companionWallActor.companionWallDirection == IsoDirections.E
        and companionWallActor.incorrectInheritedWallCall == nil,
    "native companions use the bridge entry that preserves vanilla wall-climb outcomes")
T.reset(companionWallActor)

local reactionTopics, reactionState = {}, {
    recruited = true, order = "follow", stress = 12, morale = 60,
    personalityProfile = { archetype = "practical" },
}
local savedDialogue = SC.Dialogue
local savedCommandPeek = SC.Commands.peek
local reactionOverrides = SC.Config._overrides
local savedReactionChance = reactionOverrides.wallClimbReactionChancePercent
local savedReactionActorGap = reactionOverrides.wallClimbReactionActorCooldownMs
local savedReactionGroupGap = reactionOverrides.wallClimbReactionGroupCooldownMs
SC.Dialogue = {
    lastSpokenAt = function() return -math.huge end,
    say = function(_, topic)
        reactionTopics[#reactionTopics + 1] = topic
        return true
    end,
}
SC.Commands.peek = function() return reactionState end
reactionOverrides.wallClimbReactionChancePercent = 100
reactionOverrides.wallClimbReactionActorCooldownMs = 0
reactionOverrides.wallClimbReactionGroupCooldownMs = 0

local function finishWallOutcome(success, struggle)
    local value, destination = actor(), square(1, 0)
    function value:climbCompanionOverWall(direction)
        self.companionWallDirection = direction
        return self:request()
    end
    function value:isClimbOverWallSuccess() return success end
    function value:isClimbOverWallStruggle() return struggle end
    check(T.fence(value, "climb_wall", {
            direction = "east", fromSquare = value.square, toSquare = destination,
        }, provider), "outcome-aware wall climb starts")
    value.nativeState = { __class = "ClimbOverWallState" }
    current = current + 100
    check(T.poll(value) == "active", "outcome-aware wall climb enters native state")
    value.nativeState = nil
    if success then value.x = 1.5 end
    current = current + 100
    local terminal = T.poll(value)
    local spoken = #reactionTopics
    T.poll(value)
    check(#reactionTopics == spoken, "a completed wall attempt considers its reaction only once")
    T.reset(value)
    return terminal
end

check(finishWallOutcome(true, false) == "completed"
        and reactionTopics[#reactionTopics] == "traversal.wall.success",
    "a clean vanilla wall success selects the success voice pool")
check(finishWallOutcome(true, true) == "completed"
        and reactionTopics[#reactionTopics] == "traversal.wall.struggle",
    "a successful vanilla struggle selects the struggle voice pool")
check(finishWallOutcome(false, true) == "failed"
        and reactionTopics[#reactionTopics] == "traversal.wall.fail",
    "vanilla failure takes precedence over its separate struggle roll")
local priorReactionCount = #reactionTopics
reactionOverrides.wallClimbReactionChancePercent = 0
finishWallOutcome(true, false)
check(#reactionTopics == priorReactionCount,
    "high-wall voice reactions remain random rather than firing every time")
reactionOverrides.wallClimbReactionChancePercent = 100
reactionState.order = "retreat"
finishWallOutcome(true, false)
check(#reactionTopics == priorReactionCount,
    "retreat traversal suppresses cosmetic wall chatter so survival keeps priority")
reactionOverrides.wallClimbReactionChancePercent = savedReactionChance
reactionOverrides.wallClimbReactionActorCooldownMs = savedReactionActorGap
reactionOverrides.wallClimbReactionGroupCooldownMs = savedReactionGroupGap
SC.Commands.peek = savedCommandPeek
SC.Dialogue = savedDialogue
T.reset()

local lateActor, lateDestination = actor(), square(1, 0)
T.fence(lateActor, "climb_fence", { direction = "east", toSquare = lateDestination,
    fromSquare = lateActor.square }, provider)
lateActor.x = 1.5
current = current + 200
check(T.poll(lateActor) == "starting" and lateActor.event,
    "destination motion cannot cancel a delayed native climb before its startup lease")
current = current + 1400
check(T.poll(lateActor) == "completed" and not lateActor.event,
    "missed short animation verifies destination only after its startup lease")
T.reset(lateActor)
local frameActor = actor()
check(T.window(frameActor, "climb_window", { object = {}, emptyFrame = true,
        fromSquare = frameActor.square, toSquare = square(1, 0) }, provider)
        and frameActor.frameClimb == true,
    "empty window frames use the engine's dedicated climbThroughWindowFrame entry point")
T.reset(frameActor)
local contextualFenceActor, contextualFence = actor(), {}
function contextualFence:canClimbOver(candidate) return candidate == contextualFenceActor end
check(T.window(contextualFenceActor, "climb_window", {
        object = contextualFence, hoppableThumpable = true,
        fromSquare = contextualFenceActor.square, toSquare = square(1, 0),
    }, provider)
        and contextualFenceActor.contextualAction == "ClimbThroughWindow"
        and contextualFenceActor.contextualObject == contextualFence,
    "hoppable IsoThumpables use the player's contextual ClimbThroughWindow entry point")
T.reset(contextualFenceActor)
local sameSideActor = actor()
T.fence(sameSideActor, "climb_fence", { direction = "east", toSquare = square(1, 0),
    fromSquare = sameSideActor.square }, provider)
sameSideActor.x = 0.8
current = current + 200
check(T.poll(sameSideActor) == "starting", "small same-side motion cannot prove a completed crossing")
T.cancel(sameSideActor)
local windowActor, window = actor(), { opened = false }
function window:IsOpen() return self.opened end
check(T.window(windowActor, "open_window", { object = window }, provider), "window opening queues")
T.window(windowActor, "open_window", { object = window }, provider)
check(windowActor.calls == 1 and T.activityStatus(windowActor) == "active", "window waits without retoggling")
windowActor.bOpenWindow, windowActor.nativeState = true, { __class = "OpenWindowState" }
current = current + 100
check(T.poll(windowActor) == "active", "window animation enters on later native update")
window.opened = true
current = current + 100
check(T.poll(windowActor) == "active", "mid-animation window effect retains native ownership")
check(not T.window(windowActor, "climb_window", { object = window }, provider)
    and windowActor.calls == 1, "next climb refused through window animation tail")
windowActor.bOpenWindow = false
check(T.poll(windowActor) == "active", "native state still owns tail after animation flag clears")
windowActor.nativeState = nil
check(T.poll(windowActor) == "completed", "window completion verifies actual effect")
T.reset(windowActor)
local interruptedWindowActor, interruptedWindow = actor(), { opened = false }
function interruptedWindow:IsOpen() return self.opened end
T.window(interruptedWindowActor, "open_window", { object = interruptedWindow }, provider)
interruptedWindowActor.bOpenWindow = true
interruptedWindowActor.nativeState = { __class = "OpenWindowState" }
check(T.poll(interruptedWindowActor) == "active"
        and T.cancel(interruptedWindowActor, "combat_priority") == true
        and T.poll(interruptedWindowActor) == "none"
        and not interruptedWindowActor.event,
    "survival combat may cancel window preparation before any boundary crossing")
local protectedClimbActor, protectedClimbWindow = actor(), { opened = true }
function protectedClimbWindow:IsOpen() return self.opened end
function protectedClimbWindow:isSmashed() return false end
T.window(protectedClimbActor, "climb_window", {
    object = protectedClimbWindow, fromSquare = protectedClimbActor.square,
    toSquare = square(1, 0),
}, provider)
protectedClimbActor.nativeState = { __class = "ClimbThroughWindowState" }
check(T.poll(protectedClimbActor) == "active"
        and T.cancel(protectedClimbActor, "combat_priority") == false
        and T.poll(protectedClimbActor) == "active",
    "an already-active boundary crossing remains protected so urgent combat queues safely")
protectedClimbActor.nativeState, protectedClimbActor.x = nil, 1.5
check(T.poll(protectedClimbActor) == "completed",
    "protected crossing releases combat ownership immediately after verified arrival")
T.reset(protectedClimbActor)
local closingWindowActor, closingWindowDestination = actor(), square(1, 0)
local closingWindow = { opened = true, smashed = false, glassRemoved = false }
function closingWindow:IsOpen() return self.opened end
function closingWindow:isSmashed() return self.smashed end
function closingWindow:isGlassRemoved() return self.glassRemoved end
T.window(closingWindowActor, "climb_window", {
    object = closingWindow, fromSquare = closingWindowActor.square,
    toSquare = closingWindowDestination,
}, provider)
closingWindow.opened = false
local closingPhase, closingReason = T.poll(closingWindowActor)
local closingWindowState = {
    path = { closingWindowActor.square, closingWindowDestination },
    pathIndex = 2, openedDoors = {},
}
local closingHandled = N._maintainTraversalForRequest(
    closingWindowActor, closingWindowState, closingWindowActor.square, current)
check(closingPhase == "cancelled"
        and closingReason == "traversal_portal_changed:climb_window"
        and closingHandled == false and closingWindowState.path ~= nil
        and closingWindowState.blockedEdges == nil and not closingWindowActor.event,
    "a window closed before native climb entry is reclassified without timeout or blacklist")
local earlyWindowActor, earlyWindow = actor(), { IsOpen = function() return true end }
T.window(earlyWindowActor, "open_window", { object = earlyWindow }, provider)
check(T.activityStatus(earlyWindowActor) == "none" and not earlyWindowActor.event
    and earlyWindowActor.calls == 0, "already-open window never queues a redundant native event")
T.reset(earlyWindowActor)
local ownedActor, ownedDestination = actor(), square(1, 0)
local ownedState = {
    path = { ownedActor.square, ownedDestination }, pathIndex = 2, openedDoors = {},
}
T.fence(ownedActor, "climb_fence", { direction = "east", fromSquare = ownedActor.square,
    toSquare = ownedDestination }, provider)
local handled, accepted = N._maintainTraversalForRequest(ownedActor, ownedState, ownedActor.square, current)
check(handled and accepted and ownedState.path and not ownedState.blockedEdges,
    "navigation preserves path and avoids blacklist while a traversal is queued")
ownedActor.nativeState = { __class = "ClimbOverFenceState" }
current = current + 1800
handled, accepted = N._maintainTraversalForRequest(ownedActor, ownedState, ownedActor.square, current)
check(handled and accepted and ownedState.path and not ownedState.blockedEdges,
    "navigation waits through actual fence state despite false legacy field and expired start deadline")
ownedActor.nativeState, ownedActor.x = nil, 1.5
check(not N._maintainTraversalForRequest(ownedActor, ownedState, ownedDestination, current + 100)
    and ownedState.path and ownedState.path[2] == ownedDestination
    and ownedState.pathIndex == 2 and T.poll(ownedActor) == "none",
    "navigation consumes verified traversal once and preserves its validated route suffix")
local bridgeActor = actor()
function bridgeActor:isCompanionTraversalActive() return self.bridgeTraversal == true end
T.fence(bridgeActor, "climb_fence", { direction = "east" }, provider)
bridgeActor.bridgeTraversal = true
current = current + 1600
check(T.poll(bridgeActor) == "active" and not bridgeActor:isClimbing(),
    "bridge root/substate traversal observer is authoritative with legacy field false")
bridgeActor.bridgeTraversal, bridgeActor.x = false, 1.5
check(T.poll(bridgeActor) == "completed", "bridge traversal exit releases completed ownership")
T.reset(bridgeActor)
local oldNativeActions = SC.NativeActions
local stalledActor, stalledTarget = actor(), square(2, 0)
stalledActor.nativeState = { __class = "PlayerMovementState" }
SC.NativeActions = {
    pathTelemetry = function(value)
        return { available = true, active = not value.stopped, status = value.stopped and "none" or "moving",
            pending = false, pathNextIsSet = false, pathNextX = 2.5, pathNextY = 0.5 }
    end,
    stopDirect = function(value) value.stopped, value.nativeState = true, { __class = "IdleState" } return true end,
}
local stalledState = { openedDoors = {}, nativeLease = {
    targets = { stalledTarget }, fromSquare = stalledActor.square, toSquare = stalledTarget,
    ultimateGoal = stalledTarget, startedAt = current - 2000, expires = current + 6000,
    positionProgressAt = current - 2000, progressSquareKey = "0:0:0",
    lastWorldX = stalledActor.x, lastWorldY = stalledActor.y, lastWorldZ = stalledActor.z,
} }
check(N._maintainNativeLeaseForTests(stalledActor, stalledState, stalledTarget, current) == "failed"
    and stalledActor.stopped and stalledState.lastNativeFailureTelemetry.status == "moving",
    "failed native lease preserves moving telemetry before stop clears path state")
N._rememberFailureForTests(stalledActor, stalledState, stalledActor.square, stalledTarget,
    "native_path_stalled", current, "audit")
check(stalledState.lastBlocker.diagnostic:find("beforeStop=moving", 1, true)
    and stalledState.lastBlocker.diagnostic:find("PlayerMovementState", 1, true)
    and stalledState.lastNativeFailureTelemetry == nil,
    "blocker consumes pre-stop FSM/path evidence exactly once")
SC.NativeActions = oldNativeActions

local mover, destination = actor(), square(1, 0)
local oldBarrier = SC.Topology.barrierBetween
local door = { IsOpen = function() return true end }
SC.Topology.barrierBetween = function() return door, "door" end
local blocker = N._classifyMovementBlockerForTests(mover, mover.square, destination, "native_path_stalled")
check(blocker.type == "door" and blocker.confidence == "low" and blocker.evidenceClass == "unknown",
    "merely attempting an open door is not a high-confidence static collision")
function mover:isCollidedWithVehicle() return true end
blocker = N._classifyMovementBlockerForTests(mover, mover.square, destination, "native_path_stalled")
check(blocker.type == "door" and blocker.confidence == "low",
    "misnamed native vehicle flag from a static polygon correction does not invent a parked car")
local actualVehicle = { __class = "BaseVehicle" }
function destination:getVehicleContainer() return actualVehicle end
blocker = N._classifyMovementBlockerForTests(mover, mover.square, destination, "native_path_stalled")
check(blocker.type == "vehicle" and blocker.object == actualVehicle,
    "real overlapping vehicle still supplies authoritative vehicle evidence")
destination.getVehicleContainer, mover.isCollidedWithVehicle = nil, nil
local failedState = { openedDoors = {} }
N._rememberFailureForTests(mover, failedState, mover.square, destination,
    "native_path_stalled", current, "audit")
local edge = failedState.blockedEdges["0:0:0>1:0:0"]
check(edge and edge.expires - current <= 500,
    "uncertain open-door failure only uses short retry cooldown")
check(failedState.lastBlocker.diagnostic:find("pos=", 1, true)
    and failedState.lastBlocker.diagnostic:find("fsm=", 1, true)
    and failedState.lastBlocker.diagnostic:find("native_path_stalled", 1, true),
    "bounded blocker event preserves coordinates, real state and failure reason")
SC.Topology.barrierBetween = oldBarrier
local debris = { __class = "ZombieGiblets", isCollidable = function() return false end }
destination.moving = { debris }
check(U.movingBlocker(destination, mover) == nil, "noncollidable giblets are not traffic")
debris.isCollidable = nil
check(U.movingBlocker(destination, mover) == nil, "particles without collision getter are not actors")
local other = actor()
other.x, other.y = 1.5, 0.99
destination.moving = { other }
check(U.movingBlocker(destination, mover, { swept = true, clearance = 0.4 }) == nil,
    "off-corridor body leaves a valid doorway lane")
other.y = 0.5
check(U.movingBlocker(destination, mover, { swept = true }) == other,
    "body in swept path still blocks")
other.x, other.y = 0.45, 0.5
check(not U.bodyBlocksSegment(other, mover, 1.0, 0.5, 0.5),
    "already-overlapping bodies may separate")
destination.moving = { { __class = "IsoPushableObject" } }
check(select(2, U.movingBlocker(destination, mover)) == "pushable_object",
    "colliding pushables remain blockers")

local oldMove, oldGrid, oldPosition = U.move, U.gridSquare, U.position
U.move = function(value, mode, intent) value.lastIntent = intent return true end
for _, goal in ipairs({ square(1, 0), square(-1, 0), square(0, 1), square(0, -1) }) do
    mover.x, mover.y = goal.x ~= 0 and 0.5 or 0.75, goal.y ~= 0 and 0.5 or 0.75
    local aligned = SC.NavTraversal.alignDoorApproach(mover, square(0, 0), goal, {}, "door", {})
    local intent = mover.lastIntent
    check(aligned == nil and intent.targetKind == "world"
        and intent.movementArrivalTolerance < 0.18 and intent.movementTargetTtlMs == 750,
        "door alignment sends a bounded exact endpoint in every orientation")
end
for _, goal in ipairs({ square(1, 0), square(-1, 0), square(0, 1), square(0, -1) }) do
    mover.x, mover.y = goal.x ~= 0 and 0.5 or 0.75, goal.y ~= 0 and 0.5 or 0.75
    mover.lastIntent = nil
    local aligned = SC.NavTraversal.alignWindowApproach(mover, square(0, 0), goal, {}, {
        directionBetween = function() return goal.x > 0 and "east" or goal.x < 0 and "west"
            or goal.y > 0 and "south" or "north" end,
    })
    local intent = mover.lastIntent
    check(aligned == nil and intent.action == "window_approach"
        and intent.windowAlignment == true and intent.targetKind == "world"
        and intent.movementArrivalTolerance <= 0.06,
        "window alignment stages an exact source-side endpoint in every orientation")
end
for _, goal in ipairs({ square(1, 0), square(-1, 0), square(0, 1), square(0, -1) }) do
    local from = square(0, 0)
    mover.x = goal.x > 0 and 1.02 or goal.x < 0 and -0.02 or 0.5
    mover.y = goal.y > 0 and 1.02 or goal.y < 0 and -0.02 or 0.5
    mover.lastIntent = nil
    local record = { action = "climb_fence", fromSquare = from, toSquare = goal,
        mode = "walk", supervisorToken = { serial = 7 } }
    local cleared = SC.NavTraversal.clearTraversalExit(mover, record, current, {})
    local intent = mover.lastIntent
    local progress, lateral = SC.NavTraversal.doorGeometry(record, intent.targetPosition)
    check(cleared == nil and intent.action == "traversal_exit"
        and intent.traversalExit == true and intent.direct == true
        and progress >= 0.37 and lateral <= 0.001
        and intent.supervisorToken == record.supervisorToken,
        "window and fence exits take a bounded step fully through every portal orientation")
    mover.x, mover.y = intent.targetPosition.x, intent.targetPosition.y
    check(SC.NavTraversal.clearTraversalExit(mover, record, current + 100, {}) == true,
        "portal exit clearance completes only after the actor's feet clear the frame")
end

local fastGrid = {}
for x = 0, 5 do
    for y = 0, 3 do fastGrid[tostring(x) .. ":" .. tostring(y)] = square(x, y) end
end
U.gridSquare = function(x, y)
    return fastGrid[tostring(math.floor(x)) .. ":" .. tostring(math.floor(y))]
end
local fastPath = N._fastOpenRouteForTests(
    fastGrid["0:0"], fastGrid["5:3"], { actor = mover, now = current })
check(fastPath and #fastPath == 6 and fastPath[1] == fastGrid["0:0"]
        and fastPath[#fastPath] == fastGrid["5:3"],
    "short open follow routes are fully validated and available in the first decision pulse")
fastGrid["2:1"].HasTree = function() return true end
local treeEdge = SC.Topology.classifyEdge(mover, fastGrid["1:1"], fastGrid["2:1"], {})
check(treeEdge.traversable ~= true and treeEdge.affordance == "tree"
        and treeEdge.reason == "tree_occupied",
    "a tree trunk square is a non-passable detour, not merely costly terrain")
fastGrid["2:1"].HasTree = nil
fastGrid["3:2"].isSolid = function() return true end
fastGrid["3:2"].isFree = function() return false end
check(N._fastOpenRouteForTests(
        fastGrid["0:0"], fastGrid["5:3"], { actor = mover, now = current }) == nil,
    "the immediate follow route fails closed so A-star can plan around an obstruction")
fastGrid["3:2"].isSolid = function() return false end
fastGrid["3:2"].isFree = function() return true end
local playerTrack = {
    fastGrid["2:0"], fastGrid["2:1"], fastGrid["2:2"], fastGrid["3:2"],
}
local trackPath = N._followTrackRouteForTests(
    fastGrid["0:0"], fastGrid["3:2"], playerTrack, { actor = mover, now = current })
check(trackPath and #trackPath == 4 and trackPath[2] ~= fastGrid["2:0"]
        and trackPath[#trackPath] == fastGrid["3:2"],
    "an open player track is string-pulled into a direct chord instead of replaying a bend")
local trackFence = { isTallHoppable = function() return false end }
for y = 0, 3 do
    local left, right = fastGrid["0:" .. tostring(y)], fastGrid["1:" .. tostring(y)]
    function left:getHoppableTo(other) return other == right and trackFence or nil end
end
local portalTrack = {
    fastGrid["0:0"], fastGrid["1:0"], fastGrid["1:1"],
    fastGrid["1:2"], fastGrid["1:3"], fastGrid["2:3"],
}
local portalPath = N._followTrackRouteForTests(
    fastGrid["0:3"], fastGrid["2:3"], portalTrack,
    { actor = mover, now = current })
local crossedAtPlayerPortal = false
for index = 2, #(portalPath or {}) do
    if portalPath[index - 1] == fastGrid["0:0"]
        and portalPath[index] == fastGrid["1:0"] then
        crossedAtPlayerPortal = true
        break
    end
end
check(portalPath and crossedAtPlayerPortal,
    "a follower on the wrong side of a fence joins the reachable old approach and replays the player's portal")
for y = 0, 3 do fastGrid["0:" .. tostring(y)].getHoppableTo = nil end
mover.square, mover.x, mover.y = fastGrid["0:0"], 0.5, 0.5
local aimX, aimY, aimSquare = N._continuousFollowVectorForTests(mover, {
    path = fastPath, pathIndex = 2, blockedEdges = {}, blockedSquares = {}, routeMemory = {},
}, fastGrid["0:0"], { action = "follow_formation" })
check(aimX and aimY and aimSquare == fastGrid["5:3"]
        and math.abs(aimX) > 1 and math.abs(aimY) > 1,
    "continuous follow aims down a proven-open route instead of steering at each tile centre")
U.move = oldMove
-- No world scan is needed: only the existing bounded close-threat snapshot.
U.gridSquare = function() return nil end
mover.x, mover.y = 0, 0
local target, rear = actor(), actor()
target.x, target.y = 1, 0
rear.x, rear.y = -0.65, 0
local dx, dy = N.combatVector(mover, target, "backstep", {
    threats = { { actor = target }, { actor = rear } },
})
check(dx == nil or not U.bodyBlocksSegment(rear, mover, dx * 0.45, dy * 0.45, 0.6),
    "backstep does not enter the second zombie's body")
U.gridSquare = oldGrid
getTimestampMs = oldClock
T.reset()
SC_TEST_REPORT = "NAVIGATION_TRAVERSAL_REGRESSION_PASS checks=" .. checks
