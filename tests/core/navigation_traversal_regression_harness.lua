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
local counterWindowSide, counterEscapeWindow
do
    local worker = actor()
    local windowSide = square(80, 80)
    local otherSide = square(80, 79)
    local tableObject = { __class = "IsoObject" }
    function tableObject:getSurfaceOffset() return 16 end
    windowSide.objects[1] = tableObject
    check(U.isSquareFree(windowSide) == true
            and N.standingSquareClear(worker, windowSide) == false,
        "a partial table is not a valid standing tile for guard or window watch")
    local stoolSide = square(81, 80)
    local stoolProperties = {}
    function stoolProperties:Val(name)
        if name == "Surface" then return "28" end
    end
    local stoolSprite = {}
    function stoolSprite:getProperties() return stoolProperties end
    local stoolObject = { __class = "IsoObject" }
    function stoolObject:getSprite() return stoolSprite end
    stoolSide.objects[1] = stoolObject
    check(U.isSquareFree(stoolSide) == true
            and N.standingSquareClear(worker, stoolSide) == false,
        "a stool with only the sprite Surface property blocks a standing tile")
    function stoolSide:getCell() return {} end
    function stoolSide:getChunk() return {} end
    function stoolSide:isSafeToSpawn() return true end
    check(U.isSafeSpawnSquare(stoolSide) == true
            and U.isClearActorSpawnSquare(stoolSide) == false,
        "a native-safe stool square cannot hold a standing or floor-sitting encounter actor")
    local openFloor = square(81, 81)
    function openFloor:getCell() return {} end
    function openFloor:getChunk() return {} end
    function openFloor:isSafeToSpawn() return true end
    check(U.isClearActorSpawnSquare(openFloor) == true,
        "bare floor remains eligible for encounter placement")
    local room = {}
    function stoolSide:getRoom() return room end
    function openFloor:getRoom() return room end
    local oldGroundGrid, oldGroundRequest, oldGroundMove =
        U.gridSquare, N.requestAny, U.move
    local selected, offered, standRequested
    U.gridSquare = function(x, y, z)
        if x == 81 and y == 81 and z == 0 then return openFloor end
    end
    N.requestAny = function(_, candidates)
        offered = candidates
        for _, candidate in ipairs(candidates) do
            if candidate.unreachable ~= true then
                selected = candidate
                return true, "path_requested", candidate
            end
        end
        selected = nil
        return false, "no_reachable_interaction_target"
    end
    U.move = function(_, _, intent)
        standRequested = intent.action
        return true
    end
    worker.square, worker.groundSit = stoolSide, true
    function worker:isSitOnGround() return self.groundSit end
    local seatedClear, seatedReason = U.ensureGroundPoseLocation(worker)
    check(seatedClear == false and standRequested == "stand_ground"
            and seatedReason == "standing_from_obstructed_ground_pose",
        "a saved floor pose under a stool first requests a native stand")
    worker.groundSit = false
    local walkingClear, walkingReason = U.ensureGroundPoseLocation(worker)
    check(walkingClear == false and selected == openFloor
            and walkingReason == "moving_to_clear_ground_pose",
        "the actor routes to clear floor in the same room before sitting again")
    local earlier = square(80, 79)
    function earlier:getCell() return {} end
    function earlier:getChunk() return {} end
    function earlier:isSafeToSpawn() return true end
    function earlier:getRoom() return room end
    U.gridSquare = function(x, y, z)
        if z ~= 0 then return nil end
        if x == 80 and y == 79 then return earlier end
        if x == 81 and y == 81 then return openFloor end
    end
    selected = nil
    U.ensureGroundPoseLocation(worker)
    check(selected == openFloor,
        "ground-pose recovery keeps one target when a different floor tile opens")
    openFloor.unreachable = true
    selected = nil
    U.ensureGroundPoseLocation(worker)
    check(selected == earlier and offered and #offered >= 2,
        "ground-pose recovery offers alternate same-room floor when its first target is unreachable")
    openFloor.unreachable = nil
    worker.square = openFloor
    check(U.ensureGroundPoseLocation(worker) == true,
        "the floor pose may begin once the actor reaches clear floor")
    worker.square = stoolSide
    selected = nil
    U.ensureGroundPoseLocation(worker)
    check(selected == earlier,
        "recovery forgets its old target after reaching clear floor")
    U.gridSquare, N.requestAny, U.move = oldGroundGrid,
        oldGroundRequest, oldGroundMove
    worker.square = square(0, 0)
    counterWindowSide = square(82, 80)
    local counter = { __class = "IsoObject" }
    function counter:getContainer() return {} end
    counterEscapeWindow = { __class = "IsoWindow" }
    function counterEscapeWindow:IsOpen() return true end
    counterWindowSide.objects[1], counterWindowSide.objects[2] =
        counterEscapeWindow, counter
    check(U.isSquareFree(counterWindowSide) == true
            and U.squareOccupyingObject(counterWindowSide) == counter
            and N.standingSquareClear(worker, counterWindowSide) == false,
        "a kitchen counter covering a window disqualifies its watch position")
    local oldGridSquare, oldLoadedSquare = U.gridSquare, U.loadedSquare
    U.gridSquare = function(x, y)
        if x == 80 and y == 79 then return otherSide end
        return nil
    end
    U.loadedSquare = function(value)
        if value == windowSide then return windowSide end
        return oldLoadedSquare(value)
    end
    local window = {}
    function window:getNorth() return true end
    local chosen = N.barricadeWorkSquare(worker, window, windowSide)
    local blocked, reason = N.barricadeWorkSquare(worker, window, windowSide, "same")
    local explicit = N.barricadeWorkSquare(worker, window, windowSide, "opposite")
    U.gridSquare, U.loadedSquare = oldGridSquare, oldLoadedSquare
    check(chosen == otherSide and explicit == otherSide
            and blocked == nil and reason == "work_side_blocked",
        "barricade approaches only a clear side and respects an explicitly selected side")
end
local provider = { directNative = true }
do
    local escaping = actor()
    escaping.square, escaping.x, escaping.y = counterWindowSide, 82.5, 80.5
    local queued = T.window(escaping, "climb_window", {
        object = counterEscapeWindow, fromSquare = counterWindowSide,
        toSquare = square(82, 79),
    }, provider)
    check(queued == true and escaping.event == true,
        "a counter-covered window remains a native escape route")
    T.reset(escaping)
end
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
local thumpableFenceActor, thumpableFence = actor(), {}
function thumpableFence:canClimbOver(candidate) return candidate == thumpableFenceActor end
function thumpableFenceActor:climbThroughWindow(object)
    self.climbedObject = object
    return self:request()
end
check(T.window(thumpableFenceActor, "climb_window", {
        object = thumpableFence, hoppableThumpable = true,
        fromSquare = thumpableFenceActor.square, toSquare = square(1, 0),
    }, provider)
        and thumpableFenceActor.climbedObject == thumpableFence
        and thumpableFenceActor.contextualAction == nil,
    "hoppable IsoThumpables use ISClimbThroughWindow's native entry, never the player's contextual hook")
T.reset(thumpableFenceActor)
local lowFenceActor = actor()
lowFenceActor.running, lowFenceActor.sprinting = true, true
function lowFenceActor:setRunning(value) self.running = value == true end
function lowFenceActor:setSprinting(value) self.sprinting = value == true end
function lowFenceActor:isRunning() return self.running == true end
function lowFenceActor:isSprinting() return self.sprinting == true end
function lowFenceActor:hopFence(direction, testOnly)
    if testOnly == true then
        self.lowFenceTests = (self.lowFenceTests or 0) + 1
        return true
    end
    self.contextualHop = true
    return true
end
function lowFenceActor:climbOverFence(direction)
    self.lowFenceDirection = direction
    self.runningAtFence = self:isRunning()
    self.sprintingAtFence = self:isSprinting()
    return self:request()
end
check(T.fence(lowFenceActor, "climb_fence", {
        direction = "east", fromSquare = lowFenceActor.square, toSquare = square(1, 0),
    }, provider)
        and lowFenceActor.lowFenceTests == 1
        and lowFenceActor.lowFenceDirection == IsoDirections.E
        and lowFenceActor.runningAtFence == false
        and lowFenceActor.sprintingAtFence == false
        and lowFenceActor.contextualHop == nil and lowFenceActor.contextualAction == nil,
    "low fences submit a walking climbOverFence, never a risky running vault or contextual hook")
T.reset(lowFenceActor)
local strafingActor = actor()
strafingActor.actionState = "Strafe"
function strafingActor:getCompanionActionStateName() return self.actionState end
check(T.fence(strafingActor, "climb_wall", {
        direction = "east", fromSquare = strafingActor.square, toSquare = square(1, 0),
    }, provider) == true
        and strafingActor.calls == 0 and T.activityStatus(strafingActor) == "active",
    "a climb requested from a pose without a stock climb transition keeps ownership without a discarded event")
current = current + 400
check(T.poll(strafingActor) == "starting" and strafingActor.calls == 0,
    "the deferred climb waits while the stock graph cannot consume its event")
strafingActor.actionState = "idle"
current = current + 100
check(T.poll(strafingActor) == "starting" and strafingActor.calls == 1 and strafingActor.event,
    "the deferred climb is submitted once the stock graph reaches an accepting state")
T.poll(strafingActor)
check(strafingActor.calls == 1, "a submitted deferred climb is never resubmitted")
current = current + 1400
check(T.poll(strafingActor) == "starting",
    "a late deferred submission receives a fresh native start lease")
T.reset(strafingActor)
local bumpedActor = actor()
function bumpedActor:getCompanionActionStateName() return "bumped" end
T.fence(bumpedActor, "climb_fence", { direction = "east",
    fromSquare = bumpedActor.square, toSquare = square(1, 0) }, provider)
current = current + 1600
local bumpedPhase, bumpedReason = T.poll(bumpedActor)
check(bumpedPhase == "failed" and bumpedActor.calls == 0
        and bumpedReason == "traversal_start_timeout:climb_fence",
    "a pose that never accepts the climb times out within the start lease without submitting")
T.reset(bumpedActor)
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

do
    local oldGridSquare = U.gridSquare
    local oldBarrierBetween = SC.Topology.barrierBetween
    local source, east, north, upstairs = square(0, 0), square(1, 0),
        square(0, -1), square(3, 3, 1)
    local eastDoor = { opened = false }
    function eastDoor:IsOpen() return self.opened end
    function eastDoor:IsLocked() return false end
    function eastDoor:ToggleDoor() self.opened = not self.opened return true end
    local northDoor = { IsOpen = function() return false end }
    U.gridSquare = function(x, y, z)
        if z ~= 0 then return nil end
        if x == 0 and y == 0 then return source end
        if x == 1 and y == 0 then return east end
        if x == 0 and y == -1 then return north end
        return nil
    end
    SC.Topology.barrierBetween = function(from, to)
        if from == source and to == east then return eastDoor, "door" end
        if from == source and to == north then return northDoor, "door" end
        return nil, "open"
    end
    local follower = actor()
    follower.square = source
    function follower:isCompanionPathBlockedByDoor() return true end
    function follower:getForwardDirection() return { x = 1, y = 0 } end
    local found, from, to = N.nativeHeldDoorAtActor(follower,
        { pathNextX = 1.5, pathNextY = 0.5 })
    check(found == eastDoor and from == source and to == east,
        "native door hold selects the closed doorway along the actual path step")
    found = N.nativeHeldDoorAtActor(follower, {})
    check(found == eastDoor,
        "native door hold can use actor facing before a cross-floor waypoint is exposed")
    follower.isCompanionPathBlockedByDoor = function() return false end
    check(N.nativeHeldDoorAtActor(follower, {}) == nil,
        "a nearby door alone never interrupts an unblocked native route")
    follower.isCompanionPathBlockedByDoor = function() return true end
    local oldActions = SC.NativeActions
    SC.NativeActions = {
        pathTelemetry = function()
            return { available = true, active = true, pending = false,
                status = "moving", pathNextIsSet = true,
                pathNextX = 1.5, pathNextY = 0.5 }
        end,
        stopDirect = function(value) value.stopped = true return true end,
    }
    local state = { openedDoors = {}, nativeLease = {
        targets = { upstairs }, fromSquare = source, toSquare = upstairs,
        ultimateGoal = upstairs, affordance = "multi_level",
        startedAt = current, expires = current + 6000,
        positionProgressAt = current - 500, progressSquareKey = "0:0:0",
        lastWorldX = follower.x, lastWorldY = follower.y, lastWorldZ = follower.z,
    } }
    local phase = N._maintainNativeLeaseForTests(follower, state, upstairs, current)
    check(phase == "active" and eastDoor.opened and state.nativeLease ~= nil,
        "cross-floor follow opens the held first-floor door without dropping movement")
    SC.NativeActions = oldActions
    SC.Topology.barrierBetween = oldBarrierBetween
    U.gridSquare = oldGridSquare
end

local mover, destination = actor(), square(1, 0)
local oldBarrier = SC.Topology.barrierBetween
local door = { IsOpen = function() return true end }
SC.Topology.barrierBetween = function() return door, "door" end
local blocker = N._classifyMovementBlockerForTests(mover, mover.square, destination, "native_path_stalled")
check(blocker.type == "open_door_threshold" and blocker.confidence == "low"
        and blocker.evidenceClass == "unknown" and blocker.passageOnly == true,
    "merely attempting an open door is a retryable threshold, not a static collision")
function mover:isCollidedWithVehicle() return true end
blocker = N._classifyMovementBlockerForTests(mover, mover.square, destination, "native_path_stalled")
check(blocker.type == "open_door_threshold" and blocker.confidence == "low",
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
local edge = failedState.blockedEdges
    and failedState.blockedEdges["0:0:0>1:0:0"] or nil
check(edge == nil,
    "uncertain open-door failure is not written into the route blacklist")
check(failedState.lastBlocker.diagnostic:find("pos=", 1, true)
    and failedState.lastBlocker.diagnostic:find("fsm=", 1, true)
    and failedState.lastBlocker.diagnostic:find("native_path_stalled", 1, true),
    "bounded blocker event preserves coordinates, real state and failure reason")

do
    -- Build 42.20.4 rolls a climb from the actor, never from the edge, so a
    -- companion that cannot clear one fence panel cannot clear its neighbour
    -- either. The 16-per-session fence walk in the 0.22.35 playtest was exactly
    -- that: a short per-edge cooldown, a step sideways, and another attempt.
    local fence = { isTallHoppable = function() return true end }
    local priorFenceBarrier = SC.Topology.barrierBetween
    SC.Topology.barrierBetween = function() return fence, "fence" end
    local climber = actor()
    local climbState, holds = { openedDoors = {} }, {}
    for index = 1, 3 do
        local panel = square(index, 3)
        N._rememberFailureForTests(climber, climbState, climber.square, panel,
            "traversal_exited_without_destination", current, "traversal_replan")
        local entry = climbState.blockedEdges["0:0:0>" .. index .. ":3:0"]
        holds[index] = entry and entry.expires - current or -1
    end
    check(holds[1] == 4500 and holds[2] == 4500 and holds[3] == 120000,
        "a third exit-without-arrival holds the edge long enough to abandon the fence line")
    N._rememberFailureForTests(climber, climbState, climber.square, square(4, 3),
        "native_path_failed", current, "audit")
    N._rememberFailureForTests(climber, climbState, climber.square, square(5, 3),
        "traversal_exited_without_progress", current, "traversal_replan")
    local afterReset = climbState.blockedEdges["0:0:0>5:3:0"]
    check(climbState.traversalFailures == 1
            and afterReset and afterReset.expires - current == 4500,
        "an unrelated failure clears the streak so ordinary retries stay short")
    SC.Topology.barrierBetween = priorFenceBarrier
end

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
do
    local oldPeek, oldCommands, oldActive, oldInside, oldAlert = U.peekActorState,
        SC.Commands.peek, SC.BaseLife.active, SC.BaseLife.isInside, SC.BaseAlert
    local oldGrid, oldClassify = U.gridSquare, SC.Topology.classifyEdge
    local player, worker = actor(), actor()
    function player:isAiming() return self.aiming == true end
    function player:isAttacking() return self.attacking == true end
    local snapshot = { valid = true, time = current, threatCount = 0,
        scanComplete = true, scanDiscoveryComplete = true, scanVisualComplete = true,
        threats = {}, immediateAttackers = {}, heardThreats = {},
        player = { actor = player, danger = 0 } }
    local runtime = { senses = { current = snapshot } }
    U.peekActorState = function(value) return value == worker and runtime or nil end
    local alarm, active, commandReads = nil, {}, 0
    worker.data, worker.inventory = { SC_Order = "base_duty", SC_CommandSerial = 17 },
        { "Base.Axe", "Base.WaterBottle" }
    function worker:getModData() return self.data end
    SC.Commands.peek = function()
        commandReads = commandReads + 1
        error("slice admission must not initialize commands or companion gear")
    end
    SC.BaseLife.active = function() return active end
    SC.BaseLife.isInside = function(value) return value.inside ~= false end
    SC.BaseAlert = { peek = function() return alarm end }
    local source, goal = square(400, 0), square(409, 9)
    worker.x, worker.y, worker.square = 400.5, 0.5, source
    local job = N.beginPathSearch(source, goal, nil, { actor = worker, nodeBudget = 100 })
    check(N._routeSearchSliceBudget(job) == 5,
        "a fresh complete cached observation permits a5ms quiet-base resident slice without work metadata")
    check(commandReads == 0 and #worker.inventory == 2 and worker.inventory[1] == "Base.Axe"
            and worker.inventory[2] == "Base.WaterBottle" and worker.data.SC_CommandSerial == 17
            and runtime.commands == nil,
        "slice admission leaves fresh command state and carried gear unchanged without Commands.peek")
    local oldModData = worker.getModData
    worker.getModData = nil
    check(N._routeSearchSliceBudget(job) == 3,
        "unavailable persisted actor data keeps the ordinary planning budget")
    worker.getModData, worker.data.SC_Order = oldModData, nil
    check(N._routeSearchSliceBudget(job) == 3,
        "missing persisted base duty cannot initialize commands to claim quiet planning time")
    worker.data.SC_Order = "base_duty"
    do
        local oldRegistryActor = SC.Actor._isRegistryActor
        SC.Actor._isRegistryActor = function(value) return value == worker end
        local registered = SC.Registry.register(worker,
            { id = "sc-quiet-budget-registered", recruited = true })
        SC.Actor._isRegistryActor = oldRegistryActor
        check(registered ~= nil, "quiet planning regression uses a real registered companion record")
        registered.runtime = runtime
        U.peekActorState = function() return nil end
        check(SC.Senses.cached(worker) == nil
                and SC.Senses.cached(worker, registered.runtime) == snapshot
                and N._routeSearchSliceBudget(job) == 5,
            "a resident with only Registry.record.runtime receives quiet planning time without a weak runtime")
        registered.runtime = {}
        U.peekActorState = function() return runtime end
        check(N._routeSearchSliceBudget(job) == 3,
            "a registered resident cannot substitute a weak runtime for its missing real observation")
        registered.runtime = runtime
        local impostor = actor()
        function impostor:getModData() return { SC_Id = registered.id, SC_Order = "base_duty" } end
        job.pathOptions.actor = impostor
        local collisionBudget, collisionReason = N._routeSearchSliceBudget(job)
        check(collisionBudget == 3 and collisionReason == "runtime_identity_mismatch",
            "a colliding companion id cannot borrow another actor's safe registered observation")
        job.pathOptions.actor = worker
        SC.Registry.unregister(worker)
        U.peekActorState = function(value) return value == worker and runtime or nil end
        check(N._routeSearchSliceBudget(job) == 5,
            "an unregistered actor retains the ordinary weak-runtime fallback")
    end
    snapshot.time = current - 1501
    check(N._routeSearchSliceBudget(job) == 3, "a stale real Senses observation restores the3ms budget")
    snapshot.time, snapshot.scanVisualComplete = current, false
    check(N._routeSearchSliceBudget(job) == 3, "an incomplete visual scan cannot enable quiet-base time")
    snapshot.scanVisualComplete, runtime.senses.current = true, nil
    check(N._routeSearchSliceBudget(job) == 3, "missing cached senses cannot enable quiet-base time")
    runtime.senses.current = snapshot
    for _, field in ipairs({ "humanThreat", "lastHeardDanger", "lastKnownDanger" }) do
        snapshot[field] = {}
        check(N._routeSearchSliceBudget(job) == 3, "cached " .. field .. " restores the combat budget")
        snapshot[field] = nil
    end
    for _, field in ipairs({ "threatCount", "immediateCount", "heardThreatCount", "pressure" }) do
        snapshot[field] = 1
        check(N._routeSearchSliceBudget(job) == 3, "cached " .. field .. " rejects the quiet bonus")
        snapshot[field] = 0
    end
    snapshot.threats[1] = {}
    check(N._routeSearchSliceBudget(job) == 3, "a populated threat list cannot be hidden by a zero count")
    snapshot.threats[1] = nil
    worker.inside = false
    check(N._routeSearchSliceBudget(job) == 3, "leaving camp restores the ordinary budget")
    worker.inside, goal.inside = true, false
    check(N._routeSearchSliceBudget(job) == 3, "a work goal outside camp cannot claim quiet-base time")
    goal.inside, source.inside = true, false
    check(N._routeSearchSliceBudget(job) == 3, "a search originating outside camp keeps its normal budget")
    source.inside, active = true, nil
    check(N._routeSearchSliceBudget(job) == 3, "no active camp keeps the normal budget")
    active, worker.data.SC_Order = {}, "follow"
    check(N._routeSearchSliceBudget(job) == 3, "a following companion cannot claim resident planning time")
    worker.data.SC_Order = "base_duty"
    for _, field in ipairs({ "urgent", "emergency", "survivalCritical", "stealthAvoidance" }) do
        job.pathOptions[field] = true
        check(N._routeSearchSliceBudget(job) == 3, field .. " navigation keeps the normal budget")
        job.pathOptions[field] = nil
    end
    job.pathOptions.action = "combat_approach"
    check(N._routeSearchSliceBudget(job) == 3, "a combat action keeps the normal budget even without urgent metadata")
    job.pathOptions.action, player.aiming = nil, true
    check(N._routeSearchSliceBudget(job) == 3, "player aiming immediately removes quiet-base time")
    player.aiming, player.attacking = false, true
    check(N._routeSearchSliceBudget(job) == 3, "player attacking immediately removes quiet-base time")
    player.attacking, job.pathOptions.sliceBudgetMs = false, 2
    check(N._routeSearchSliceBudget(job) == 2, "an explicit smaller slice remains a cap in quiet camp")
    job.pathOptions.sliceBudgetMs, alarm = 10, {}
    check(N._routeSearchSliceBudget(job) == 3, "an explicit larger cap cannot override a camp alarm")
    alarm, job.pathOptions.sliceBudgetMs = nil, nil
    local grid, tick = {}, 0
    U.gridSquare = function(x, y)
        if x < 400 or x > 409 or y < 0 or y > 9 then return nil end
        local key = x .. ":" .. y
        grid[key] = grid[key] or square(x, y)
        return grid[key]
    end
    SC.Topology.classifyEdge = function() return { traversable = true, cost = 1, affordance = "open" } end
    job.pathOptions.clock = function() tick = tick + 1 return tick end
    local status = N.resumePathSearch(job, 100)
    check(status == "pending" and job.lastSliceBudgetMs == 5,
        "a real resumable frontier uses the selected quiet-base5ms deadline")
    local frontier = job.search
    alarm = {}
    status = N.resumePathSearch(job, 100)
    check(status == "pending" and job.search == frontier and job.lastSliceBudgetMs == 3,
        "an alarm entering the same pending job switches its next slice to3ms without losing the frontier")
    local state = N._stateForTests(worker)
    state.pathSearch = { route = job, startedAt = current }
    check(N.status(worker).searchSliceBudgetMs == 3,
        "live navigation status exposes the actual pending search deadline")
    check(commandReads == 0, "every adaptive resume remains independent of command initialization")
    N.cancel(worker, "test_finished")
    U.peekActorState, SC.Commands.peek, SC.BaseLife.active, SC.BaseLife.isInside, SC.BaseAlert =
        oldPeek, oldCommands, oldActive, oldInside, oldAlert
    U.gridSquare, SC.Topology.classifyEdge = oldGrid, oldClassify
end
for _, goal in ipairs({ square(1, 0), square(-1, 0), square(0, 1), square(0, -1) }) do
    mover.x, mover.y = goal.x ~= 0 and 0.5 or 0.75, goal.y ~= 0 and 0.5 or 0.75
    local aligned = SC.NavTraversal.alignDoorApproach(mover, square(0, 0), goal, {}, "door", {})
    local intent = mover.lastIntent
    check(aligned == nil and intent.targetKind == "world"
        and intent.movementArrivalTolerance < 0.18 and intent.movementTargetTtlMs == 750,
        "door alignment sends a bounded exact endpoint in every orientation")
    local token = { serial = 12 }
    SC.NavTraversal.alignDoorApproach(mover, square(0, 0), goal,
        { draggingBody = true, supervisorToken = token }, "door", {})
    check(mover.lastIntent.draggingBody == true
            and mover.lastIntent.supervisorToken == token
            and mover.lastIntent.weaponReady == false,
        "door alignment preserves the hauler's backward pose and action owner in every orientation")
end
do
    mover.x, mover.y, mover.lastIntent = 0.5, 0.5, nil
    mover.facingX, mover.facingY = 0, -1
    function mover:getForwardDirectionX() return self.facingX end
    function mover:getForwardDirectionY() return self.facingY end
    function mover:faceLocationF(x, y)
        self.facingTarget = { x = x, y = y }
        return true
    end
    local facingState = {}
    local source, destination = square(0, 0), square(1, 0)
    local aligned, status = SC.NavTraversal.alignDoorApproach(
        mover, source, destination, { action = "follow_formation" },
        "door", {}, facingState)
    check(aligned == nil and status == "turning_door_approach"
            and mover.facingTarget and mover.facingTarget.x > mover.x,
        "a sideways follower faces through the opening before crossing")
    mover.facingX, mover.facingY = 1, 0
    check(SC.NavTraversal.alignDoorApproach(
            mover, source, destination, { action = "follow_formation" },
            "door", {}, facingState) == true,
        "the aligned follower immediately hands crossing to native movement")
    mover.facingX, mover.facingY = 0, -1
    SC.NavTraversal.alignDoorApproach(mover, source, destination,
        { action = "regroup" }, "door", {}, facingState)
    facingState.doorFacingUntil = 0
    check(SC.NavTraversal.alignDoorApproach(mover, source, destination,
            { action = "regroup" }, "door", {}, facingState) == true,
        "door facing timeout cannot hold a regrouping companion forever")
    mover.facingTarget = nil
    check(SC.NavTraversal.alignDoorApproach(mover, source, destination,
            { action = "regroup", draggingBody = true }, "door", {}, {}) == true
            and mover.facingTarget == nil,
        "a centered hauler is not turned toward the door by regroup alignment")
end

do
    local hauler, body = actor(), actor()
    hauler.x, hauler.y, hauler.square = 1.5, 0.5, square(1, 0)
    body.x, body.y = 0.8, 0.5
    function hauler:isDraggingCorpse() return true end
    function hauler:getGrapplingTarget() return self.body end
    hauler.body = body
    local door = { open = true, toggles = 0 }
    function door:ToggleDoor() self.open = not self.open self.toggles = self.toggles + 1 end
    local state = { openedDoors = { { object = door,
        fromSquare = square(0, 0), toSquare = hauler.square,
        openedAt = current - 1000, expires = current + 8000 } } }
    local context = {
        objectOpen = function(value) return value.open end,
        sameSquare = U.sameSquare,
    }
    SC.NavTraversal.reserve(door, hauler, current)
    SC.NavTraversal.closeOwnedDoors(hauler, state, current, nil, context)
    check(door.toggles == 0 and #state.openedDoors == 1
            and SC.NavTraversal.reserve(door, actor(), current) == false,
        "a carrier crossing the door cannot close it onto its trailing corpse or release ownership")
    body.x = 1.2
    SC.NavTraversal.closeOwnedDoors(hauler, state, current, nil, context)
    check(door.toggles == 0,
        "the corpse must reach the existing doorway clearance before closure")
    hauler.body = nil
    SC.NavTraversal.closeOwnedDoors(hauler, state, current, nil, context)
    check(door.toggles == 0,
        "a temporarily unavailable grapple target keeps the door open")
    hauler.body, body.x = body, 1.5
    SC.NavTraversal.closeOwnedDoors(hauler, state, current, nil, context)
    check(door.toggles == 1 and #state.openedDoors == 0
            and SC.NavTraversal.reserve(door, actor(), current) == true,
        "the door closes and releases ownership after the carrier and corpse both clear it")
    local owner = actor()
    owner.x, owner.y, owner.square = 1.5, 0.5, square(1, 0)
    for _, direction in ipairs({ 1, -1 }) do
        hauler.x = direction == 1 and 1.5 or 0.5
        body.x = direction == 1 and 0.5 or 1.5
        door.open, door.toggles = true, 0
        state.openedDoors = { { object = door, fromSquare = square(0, 0),
            toSquare = owner.square, openedAt = current - 1000, expires = current + 8000 } }
        SC.NavTraversal.closeOwnedDoors(owner, state, current,
            { allies = { { actor = hauler } } }, context)
        check(door.toggles == 0 and #state.openedDoors == 1,
            "another resident cannot close a door across an allied grapple in either travel direction")
        body.x = hauler.x
        SC.NavTraversal.closeOwnedDoors(owner, state, current,
            { allies = { { actor = hauler } } }, context)
        check(door.toggles == 1 and #state.openedDoors == 0,
            "a resident can close the door once the allied carrier and body both clear either side")
    end
end
mover.x, mover.y, mover.lastIntent = 0.5, 0.20, nil
local fenceAligned = SC.NavTraversal.alignDoorApproach(
    mover, square(0, 0), square(0, 1), {}, "fence", {})
check(fenceAligned == nil and mover.lastIntent.action == "fence_approach"
        and math.abs(mover.lastIntent.targetPosition.y - 0.62) < 0.001,
    "a centred fighter first walks to the fence before native hop preflight")
mover.y, mover.lastIntent = 0.62, nil
check(SC.NavTraversal.alignDoorApproach(
        mover, square(0, 0), square(0, 1), {}, "fence", {}) == true
        and mover.lastIntent == nil,
    "the fence hop is submitted only from its aligned source-side setback")
do
    local source, crossing, after = square(240, 0), square(241, 0), square(242, 0)
    local north, south = square(240, -1), square(240, 1)
    local oldBarrier, oldGrid = SC.Topology.barrierBetween, U.gridSquare
    SC.Topology.barrierBetween = function(from, to)
        if from == source and to == crossing then return {}, "fence" end
        return nil, "open"
    end
    U.gridSquare = function(x, y)
        if x == 240 and y == -1 then return north end
        if x == 240 and y == 1 then return south end
        return nil
    end
    local oldStop = U.stop
    U.stop = function() return true end
    local first, second = actor(), actor()
    first.x, first.y, first.square = 240.5, 0.5, source
    second.x, second.y, second.square = 240.4, 0.5, source
    local approach = { action = "combat_approach", urgent = true, snapshot = {} }
    local firstAccepted = N._tacticalStepForTests(first, { openedDoors = {} },
        source, crossing, after, "fence", approach, current)
    local secondState = { openedDoors = {} }
    local secondAccepted, secondStatus = N._tacticalStepForTests(second,
        secondState, source, crossing, after, "fence", approach, current)
    check(firstAccepted == true and secondAccepted == nil
            and secondStatus == "holding_choke_queue"
            and second.lastIntent.action ~= "right_of_way_yield"
            and secondState.yieldBlocker == nil,
        "urgent combat approaches queue at a fence, the waiting fighter holding first: "
            .. tostring(secondStatus))
    current = current + 900
    second.lastIntent = nil
    local yielded, yieldStatus = N._tacticalStepForTests(second,
        secondState, source, crossing, after, "fence", approach, current)
    check(yielded == nil and yieldStatus == "yielding_combat_choke"
            and second.lastIntent.action == "right_of_way_yield",
        "after the right-of-way wait the queued fighter moves aside")
    current = current + 100
    second.lastIntent = nil
    local again, againStatus = N._tacticalStepForTests(second,
        secondState, source, crossing, after, "fence", approach, current)
    check(again == nil and againStatus == "holding_choke_queue"
            and second.lastIntent.action ~= "right_of_way_yield",
        "the next sidestep waits again instead of jittering every tick: "
            .. tostring(againStatus))
    SC.NavTraffic.reset()
    SC.Topology.barrierBetween, U.gridSquare, U.stop = oldBarrier, oldGrid, oldStop
end
do
    -- The choke reservation is the only tactical pause a combat rush keeps.
    -- Stopping at every stair landing and blind corner left a companion
    -- rushing to a zombie on the player standing still on the way.
    local oldCanSee, oldStop = U.canSee, U.stop
    U.canSee = function() return false end
    U.stop = function() return true end
    local rush = { action = "combat_approach", urgent = true, snapshot = {} }
    local stairFoot, stairStep, stairTop = square(250, 0), square(251, 0), square(252, 0)
    local rusher = actor()
    rusher.x, rusher.y, rusher.square = 250.5, 0.5, stairFoot
    local stairAccepted, stairStatus = N._tacticalStepForTests(rusher,
        { openedDoors = {} }, stairFoot, stairStep, stairTop, "stairs", rush, current)
    check(stairAccepted == true and stairStatus == "tactical_stair",
        "a combat rush takes a free stair without the landing pause: "
            .. tostring(stairStatus))
    local corner, turn, around = square(260, 0), square(261, 0), square(261, 1)
    rusher.x, rusher.square = 260.5, corner
    local cornerAccepted, cornerStatus = N._tacticalStepForTests(rusher,
        { openedDoors = {} }, corner, turn, around, nil, rush, current)
    check(cornerAccepted == true and cornerStatus == "tactical_corner",
        "a combat rush rounds a blind corner without the corner pause: "
            .. tostring(cornerStatus))
    local walker = actor()
    walker.x, walker.y, walker.square = 270.5, 0.5, square(270, 0)
    local walk = { action = "follow_formation", snapshot = {} }
    local walkAccepted, walkStatus = N._tacticalStepForTests(walker,
        { openedDoors = {} }, walker.square, square(271, 0), square(272, 0),
        "stairs", walk, current)
    check(walkAccepted == nil and walkStatus == "checking_stair_landing",
        "an ordinary walk still checks the stair landing: " .. tostring(walkStatus))
    SC.NavTraffic.reset()
    U.canSee, U.stop = oldCanSee, oldStop
end
do
    local source, crossing, after = square(280, 0), square(281, 0), square(282, 0)
    local left, right, back = square(280, 1), square(280, -1), square(279, 0)
    local oldBarrier, oldClassify, oldHash = SC.Topology.barrierBetween,
        SC.Topology.classifyEdge, U.stableHash
    local oldStop, priorGrid = U.stop, U.gridSquare
    SC.Topology.barrierBetween = function() return nil, "open" end
    SC.Topology.classifyEdge = function(_, _, destination)
        return { traversable = true, cost = 1,
            affordance = destination == left and "fence" or "open" }
    end
    U.stableHash = function() return 0 end
    U.stop = function() return true end
    U.gridSquare = function(x, y)
        if x == 280 and y == 1 then return left end
        if x == 280 and y == -1 then return right end
        if x == 279 and y == 0 then return back end
    end
    local first, second = actor(), actor()
    first.x, first.square = 280.5, source
    second.x, second.square = 280.4, source
    local intent = { action = "combat_approach", urgent = true,
        draggingBody = true, snapshot = {} }
    N._tacticalStepForTests(first, { openedDoors = {} }, source,
        crossing, after, "door", intent, current)
    local state = { openedDoors = {} }
    local held, status = N._tacticalStepForTests(second, state, source,
        crossing, after, "door", intent, current)
    check(held == nil and status == "holding_choke_queue" and second.lastIntent == nil,
        "a queued hauler holds its grapple pose instead of issuing ready-weapon")
    current = current + 900
    N._tacticalStepForTests(second, state, source, crossing, after,
        "door", intent, current)
    check(second.lastIntent and second.lastIntent.action == "right_of_way_yield"
            and second.lastIntent.draggingBody == true
            and second.lastIntent.nextSquare == right,
        "a hauler yields backward onto an open edge instead of choosing a fence edge")
    SC.NavTraffic.reset()
    second.lastIntent = nil
    -- Both side edges need a climb. The second recovery must use the clear
    -- tile behind, retaining the body pose through the local maneuver.
    SC.Topology.classifyEdge = function(_, _, destination)
        return { traversable = true, cost = 1,
            affordance = (destination == left or destination == right) and "fence" or "open" }
    end
    local recoveryState = { openedDoors = {}, blockedEdges = {}, blockedSquares = {},
        routeMemory = {}, nativeRecoveryDue = true, stuckAttempts = 1,
        lastProgressAt = current - 6000, lastAttemptFrom = source,
        lastAttemptTo = crossing }
    local handled, accepted = N._recoverFromStuckForTests(second, recoveryState,
        after, "walk", { action = "drag_body", draggingBody = true }, current)
    check(handled == true and accepted == true and second.lastIntent
            and second.lastIntent.action == "collision_recovery"
            and second.lastIntent.draggingBody == true
            and second.lastIntent.nextSquare == back,
        "collision recovery preserves backward hauling and rejects climb-only side edges")
    SC.NavTraffic.reset()
    SC.Topology.barrierBetween, SC.Topology.classifyEdge, U.stableHash =
        oldBarrier, oldClassify, oldHash
    second.lastIntent = nil
    function second:tooDarkToRead() return true end
    second.x, second.y = source.x + 0.5, source.y + 0.5
    local arrived, arrivalStatus = N.request(second, source, "walk",
        { action = "drag_body", draggingBody = true })
    check(arrived == true and arrivalStatus == "arrived" and second.lastIntent == nil,
        "arriving with a corpse in darkness does not replace the grapple with an aimed pose")
    N.cancel(second, "test_finished")
    U.stop, U.gridSquare = oldStop, priorGrid
end
do
    local oldGrid, oldClassify = U.gridSquare, SC.Topology.classifyEdge
    local oldCompanion, oldStopDirect = U.isCompanion, SC.NativeActions.stopDirect
    local grid = {}
    for x = 300, 303 do
        for y = 0, 3 do grid[x .. ":" .. y] = square(x, y) end
    end
    U.gridSquare = function(x, y) return grid[x .. ":" .. y] end
    local diagonalCalls, delay = 0, false
    SC.Topology.classifyEdge = function(_, from, to)
        if delay then current = current + 1 end
        local diagonal = from.x ~= to.x and from.y ~= to.y
        if diagonal then diagonalCalls = diagonalCalls + 1 end
        return { traversable = true, cost = diagonal and math.sqrt(2) or 1,
            affordance = diagonal and "diagonal_open" or "open" }
    end
    local source, goal = grid["300:0"], grid["302:2"]
    local normal = N.findPath(source, goal, { nodeBudget = 100 })
    check(normal and #normal == 3 and diagonalCalls > 0,
        "ordinary navigation retains its direct diagonal route")
    diagonalCalls = 0
    local hauling = N.findPath(source, goal, { nodeBudget = 100, draggingBody = true })
    local cardinal = hauling ~= nil
    for index = 2, #(hauling or {}) do
        cardinal = cardinal and math.abs(hauling[index].x - hauling[index - 1].x)
            + math.abs(hauling[index].y - hauling[index - 1].y) == 1
    end
    check(cardinal and #hauling == 5 and diagonalCalls == 0,
        "hauling A-star emits cardinal edges without any expensive diagonal classifications")
    local allowed, _, haulReason = N._passableEdgeForTests(source, grid["301:1"], 1,
        { draggingBody = true })
    check(allowed == false and haulReason == "drag_non_cardinal",
        "a drifted haul route cannot dispatch a diagonal even when world topology calls it open")
    local worker = actor()
    worker.x, worker.y, worker.square = 300.5, 0.5, source
    U.isCompanion = function() return true end
    local cacheIntent = { action = "move_to_base_storage", workRoute = true }
    check(SC.WorkRoutes.key(worker, goal, cacheIntent) ~= nil,
        "ordinary base storage routes remain eligible for route memory")
    cacheIntent.draggingBody = true
    check(SC.WorkRoutes.key(worker, goal, cacheIntent) == nil,
        "hauling cannot reuse a cached ordinary diagonal work route")
    SC.NativeActions.stopDirect = function() return true end
    delay = true
    N.request(worker, goal, "walk", { action = "haul_mode_test" })
    local state = N._stateForTests(worker)
    local normalSearch = state.pathSearch
    check(normalSearch ~= nil, "a sliced ordinary search is retained for the mode-change regression")
    local oldSignature = state.routeTargetSignature
    N.request(worker, goal, "walk", { action = "haul_mode_test", draggingBody = true })
    check(state.pathSearch and state.pathSearch ~= normalSearch
            and state.pathSearch.key ~= normalSearch.key
            and state.pathSearch.route.pathOptions.draggingBody == true
            and state.routeTargetSignature ~= oldSignature,
        "beginning a haul replaces the ordinary frontier and movement identity even for the same goal")
    local haulSignature = state.routeTargetSignature
    N.cancel(worker, "test_finished")
    delay = false
    -- Drift one tile beside a retained cardinal route. Its old next waypoint
    -- is diagonal, while a later suffix tile is cardinal-adjacent.
    local drift = grid["301:1"]
    worker.x, worker.y, worker.square = 301.5, 1.5, drift
    state = N._stateForTests(worker)
    state.goalSquare, state.goalAction, state.routeTargetSignature = goal, "haul_mode_test", haulSignature
    state.path, state.pathIndex, state.pathGoalSquare =
        { source, grid["301:0"], grid["302:0"], grid["302:1"], goal }, 3, goal
    state.pathStealthAvoidance = false
    state.nextRepathAt, state.lastProgressAt = current + 10000, current
    worker.lastIntent = nil
    local accepted = N.request(worker, goal, "walk",
        { action = "haul_mode_test", draggingBody = true })
    check(accepted == true and worker.lastIntent and worker.lastIntent.nextSquare
            and math.abs(worker.lastIntent.nextSquare.x - drift.x)
                + math.abs(worker.lastIntent.nextSquare.y - drift.y) == 1
            and (state.routeReuseCount or 0) > 0,
        "a drifted hauler rejoins a cardinal-adjacent suffix before dispatching movement")
    N.cancel(worker, "test_finished")
    for x = 300, 308 do
        for y = 0, 7 do grid[x .. ":" .. y] = square(x, y) end
    end
    SC.Topology.classifyEdge = function(_, from, to)
        local crossesWall = math.min(from.x, to.x) == 303 and math.max(from.x, to.x) == 304
            and from.y > 0 and from.y < 7
        return { traversable = not crossesWall, cost = 1,
            affordance = crossesWall and "blocked" or "open" }
    end
    local function detour(octile)
        local job = N.beginPathSearch(grid["300:3"], grid["307:3"], nil,
            { draggingBody = true, nodeBudget = 300 })
        if octile then
            local search = job.search
            search.adapter.heuristic = function(first, last)
                local dx, dy = math.abs(first.x - last.x), math.abs(first.y - last.y)
                return dx + dy + (math.sqrt(2) - 2) * math.min(dx, dy)
            end
            local h = search.adapter.heuristic(search.startSquare, search.goalSquare)
            search.nodes[search.startKey].h, search.nodes[search.startKey].f = h, h
            search.open[1].h, search.open[1].f = h, h
        end
        local status, path, _, expanded = N.resumePathSearch(job, 300)
        return status, path, expanded
    end
    local oldStatus, oldPath, oldExpanded = detour(true)
    local newStatus, newPath, newExpanded = detour(false)
    check(oldStatus == "complete" and newStatus == "complete" and #oldPath == #newPath
            and newExpanded < oldExpanded,
        "Manhattan reaches the same optimal doorway detour with fewer expansions than octile: "
            .. tostring(newExpanded) .. " < " .. tostring(oldExpanded))
    SC_TEST_HAUL_HEURISTIC = "octile=" .. tostring(oldExpanded)
        .. " manhattan=" .. tostring(newExpanded) .. " pathTiles=" .. tostring(#newPath)
    U.gridSquare, SC.Topology.classifyEdge = oldGrid, oldClassify
    U.isCompanion, SC.NativeActions.stopDirect = oldCompanion, oldStopDirect
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
do
    local from, to = fastGrid["1:1"], fastGrid["2:1"]
    local genericFence = {}
    function from:getHoppableTo(other) return other == to and genericFence or nil end
    function from:isHoppableTo() return false end
    function from:isPlayerAbleToHopWallTo() return false end
    local blocked = SC.Topology.classifyEdge(mover, from, to, {})
    check(blocked.affordance == "fence" and blocked.traversable ~= true
            and blocked.reason == "fence_not_hoppable",
        "a generic fence rejected by both player hop probes becomes a detour")
    function from:isHoppableTo() return true end
    local low = SC.Topology.classifyEdge(mover, from, to, {})
    check(low.traversable == true and low.cost == 2.5,
        "positive low-fence evidence remains a valid crossing")
    function from:isHoppableTo() return false end
    function from:isPlayerAbleToHopWallTo() return true end
    local tall = SC.Topology.classifyEdge(mover, from, to, {})
    check(tall.traversable == true and tall.cost == 4.5,
        "positive wall-hop evidence remains a native climb")
    from.getHoppableTo, from.isHoppableTo, from.isPlayerAbleToHopWallTo = nil, nil, nil
end
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
local scavengeAimX, scavengeAimY, scavengeAimSquare = N._continuousFollowVectorForTests(mover, {
    path = fastPath, pathIndex = 2, blockedEdges = {}, blockedSquares = {}, routeMemory = {},
}, fastGrid["0:0"], { action = "move_to_scavenge", continuousApproach = true })
check(scavengeAimX and scavengeAimY and scavengeAimSquare == fastGrid["5:3"]
        and math.abs(scavengeAimX) > 1 and math.abs(scavengeAimY) > 1,
    "a continuous scavenging approach aims down the proven-open route instead of steering at each tile centre")
local tacticalAim = N._continuousFollowVectorForTests(mover, {
    path = fastPath, pathIndex = 2, blockedEdges = {}, blockedSquares = {}, routeMemory = {},
}, fastGrid["0:0"], { action = "move_to_scavenge" })
check(tacticalAim == nil,
    "a scavenging route must explicitly opt into continuous look-ahead steering")
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

local crowdedFrom, crowdedTo = square(0, 0), square(1, 0)
local crowdedWalker, friendly, zombie = actor(), actor(), actor()
crowdedWalker.square = crowdedFrom
friendly.square, friendly.x, friendly.y = crowdedTo, 1.5, 0.5
zombie.square, zombie.x, zombie.y = crowdedTo, 1.5, 0.5
function zombie:isZombie() return true end
local oldCompanion = U.isCompanion
U.isCompanion = function(value)
    return value == friendly or oldCompanion(value)
end
crowdedTo.moving = { friendly, zombie }
function crowdedTo:isFree() return false end
local found, kind = U.movingBlocker(crowdedTo, crowdedWalker,
    { preferNonFriendly = true })
check(found == zombie and kind == "zombie_crowd",
    "a friendly first in native occupancy does not mask a zombie")
local oldBridge = SCBridge
SCBridge = { fillEdgeFacts = function(_, _, toSquare, out)
    for key in pairs(out) do out[key] = nil end
    out.squareFree, out.barrierKind = toSquare ~= crowdedTo, "open"
    out.tree, out.fire, out.brokenGlass = false, false, false
    return true
end }
local mixedEdge = SC.Topology.withReadBatch(SC.Topology.classifyEdge,
    crowdedWalker, crowdedFrom, crowdedTo)
check(mixedEdge.traversable == false,
    "mixed friendly and zombie occupancy is not an open route")
crowdedTo.moving = { zombie, friendly }
mixedEdge = SC.Topology.withReadBatch(SC.Topology.classifyEdge,
    crowdedWalker, crowdedFrom, crowdedTo)
check(mixedEdge.traversable == false,
    "mixed occupancy blocks the route in either enumeration order")
U.isCompanion = oldCompanion
crowdedTo.moving = { friendly, zombie }
mixedEdge = SC.Topology.withReadBatch(SC.Topology.classifyEdge,
    crowdedWalker, crowdedFrom, crowdedTo)
check(mixedEdge.traversable == false,
    "player and zombie sharing a square also remain blocked")
U.isCompanion = function(value)
    return value == friendly or oldCompanion(value)
end
local pushable = { __class = "IsoPushableObject" }
function pushable:isCollidable() return true end
crowdedTo.moving = { friendly, pushable }
mixedEdge = SC.Topology.withReadBatch(SC.Topology.classifyEdge,
    crowdedWalker, crowdedFrom, crowdedTo)
check(mixedEdge.traversable == false,
    "a colliding pushable behind a friendly cannot become traffic")
crowdedTo.moving = { friendly, zombie }
fastGrid["1:0"] = crowdedTo
check(N._fastOpenRouteForTests(fastGrid["0:0"], fastGrid["2:0"],
        { actor = crowdedWalker, now = current }) == nil,
    "the fast open-route path rejects mixed disallowed occupancy")
crowdedTo.moving = { friendly }
mixedEdge = SC.Topology.withReadBatch(SC.Topology.classifyEdge,
    crowdedWalker, crowdedFrom, crowdedTo)
check(mixedEdge.traversable == true,
    "a friendly-only crowd remains dynamic traffic")
SCBridge = oldBridge
U.isCompanion = oldCompanion

local yieldState = { yieldBlocker = friendly, yieldSince = current - 3100,
    lastAttemptTo = crowdedTo, lastProgressAt = current - 5000 }
local recovering = N._recoverFromStuckForTests(crowdedWalker, yieldState,
    square(3, 0), "walk", { action = "follow_formation" }, current)
check(recovering == false and yieldState.yieldSince ~= nil,
    "generic recovery gives a known crowd blocker its detour deadline")
U.gridSquare = oldGrid
getTimestampMs = oldClock
T.reset()
SC_TEST_REPORT = "NAVIGATION_TRAVERSAL_REGRESSION_PASS checks=" .. checks
    .. " haulHeuristic=" .. tostring(SC_TEST_HAUL_HEURISTIC)
