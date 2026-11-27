-- SPDX-License-Identifier: MIT

local SC = LivingFellows
local checks = 0
local function check(value, message)
    checks = checks + 1
    assert(value, "steering check " .. tostring(checks) .. " failed: " .. tostring(message))
end

local function actorAt(id, x, y, z)
    local actor = { id = id, x = x, y = y, z = z or 0, halo = nil }
    function actor:getX() return self.x end
    function actor:getY() return self.y end
    function actor:getZ() return self.z end
    function actor:setHaloNote(text) self.halo = text end
    return actor
end

local actor = actorAt("a", 10, 10, 0)
local other = actorAt("b", 12, 12, 0)
local player = actorAt("player", 0, 0, 0)
local selected = actor
local held = false
local cursorX, cursorY = 15.25, 13.75
local cursorFloor
local squareLoaded = true
local fixedSquares
local moves = {}
local stops = 0
local stopMode = "success"
local haloWrites = 0

function player:setHaloNote(text)
    self.halo = text
    haloWrites = haloWrites + 1
end

function getSpecificPlayer(index) return index == 0 and player or nil end
function getMouseX() return 100 end
function getMouseY() return 200 end
function screenToIsoX(_, _, _, z) return cursorX + (cursorFloor and (z - cursorFloor) * 1.5 or 0) end
function screenToIsoY(_, _, _, z) return cursorY + (cursorFloor and (z - cursorFloor) * 1.5 or 0) end
function isKeyDown(key) return key == 27 and held end
function getText(key) return key end
function getCell()
    return {
        getGridSquare = function(_, x, y, z)
            if not squareLoaded then return nil end
            if fixedSquares then return fixedSquares[x .. ":" .. y .. ":" .. z] end
            return { x = x, y = y, z = z }
        end,
    }
end

SC.UI = {
    DEFAULT_STEER_HOTKEY = 27,
    steerHotkey = function() return 27 end,
    selectedActor = function() return selected end,
}
SC.Actor = {
    isCompanion = function(candidate) return candidate == actor or candidate == other end,
    setMovement = function(candidate, mode, intent)
        local permitted = SC.ActionSupervisor.movementPermission(candidate, intent.action, intent)
        if permitted ~= true then return false, "unsupervised" end
        moves[#moves + 1] = { actor = candidate, mode = mode, intent = intent }
        return true, "moving"
    end,
    stop = function()
        stops = stops + 1
        if stopMode == "throw" then error("fixture stop failure") end
        if stopMode == "reject" then return false end
        return true
    end,
}

local Steering = SC.Steering
local rawBegin = SC.ActionSupervisor.begin
local acquisitions = 0
SC.ActionSupervisor.begin = function(...)
    acquisitions = acquisitions + 1
    return rawBegin(...)
end
Steering.reset()
held = true
local started = Steering.update()
local token = SC.ActionSupervisor.current(actor)
local first = moves[#moves]
check(started == true and token ~= nil and token.owner == "player_control"
        and token.action == "steer" and token.priority == SC.ActionSupervisor.Priority.PLAYER,
    "hold acquires the selected actor through the player-priority supervisor owner")
check(first.actor == actor and first.mode == "walk"
        and first.intent.supervisorToken == token and first.intent.movementTarget == true,
    "cursor movement carries the current ownership token into the ordinary movement path")
check(math.abs(first.intent.targetPosition.x - cursorX) < 0.001
        and math.abs(first.intent.targetPosition.y - cursorY) < 0.001
        and math.abs(first.intent.dx - 5.25) < 0.001,
    "steering feeds the exact cursor point and actor-relative vector to bounded movement")

local lower, lowerReason = SC.ActionSupervisor.begin(actor, {
    owner = "work", action = "test_work", priority = SC.ActionSupervisor.Priority.WORK,
})
check(lower == nil and tostring(lowerReason):find("actor_owned_by", 1, true) ~= nil,
    "a lower-priority owner cannot overlap active steering")

local emergency = SC.ActionSupervisor.begin(actor, {
    owner = "survival", action = "escape", priority = SC.ActionSupervisor.Priority.SURVIVAL,
    phase = "approaching", deadlines = { approaching = 0 },
})
check(emergency ~= nil and stops == 1 and not SC.ActionSupervisor.isCurrent(token),
    "survival ownership preempts steering and its cancellation stops the old vector")
local stopsAfterPreemption = stops
Steering.update()
check(stops == stopsAfterPreemption and SC.ActionSupervisor.current(actor) == emergency,
    "detecting stale steering ownership never stops the new emergency owner")

SC.ActionSupervisor.cancel(actor, "test_complete", nil, true)
SC_TEST_CLOCK = SC_TEST_CLOCK + 100
Steering.update()
check(SC.ActionSupervisor.current(actor).owner == "player_control",
    "held steering reacquires only after the higher-priority owner releases")
held = false
Steering.update()
check(SC.ActionSupervisor.current(actor) == nil and stops == stopsAfterPreemption + 1,
    "key release cancels the steering token and stops movement")

held = true
selected = actor
SC_TEST_CLOCK = SC_TEST_CLOCK + 100
Steering.update()
selected = other
SC_TEST_CLOCK = SC_TEST_CLOCK + 100
Steering.update()
check(SC.ActionSupervisor.current(actor) == nil
        and SC.ActionSupervisor.current(other).owner == "player_control"
        and moves[#moves].actor == other,
    "changing roster selection releases the old actor before steering the new one")

squareLoaded = false
SC_TEST_CLOCK = SC_TEST_CLOCK + 100
local cursorAccepted, cursorReason = Steering.update()
local acquisitionsAfterInvalid = acquisitions
local stopsAfterInvalid = stops
local haloWritesAfterInvalid = haloWrites
check(cursorAccepted == false and cursorReason == "cursor_unavailable"
        and SC.ActionSupervisor.current(other) == nil,
    "unloaded cursor ground releases ownership instead of driving blind")
check(player.halo == "UI_SC_Steer_NoCursor",
    "an unavailable cursor target is explained to the player")
for _ = 1, 100 do Steering.update() end
check(acquisitions == acquisitionsAfterInvalid and stops == stopsAfterInvalid
        and haloWrites == haloWritesAfterInvalid,
    "an unchanged invalid cursor is throttled without reacquiring, stopping, or spamming")

held = false
Steering.update()
held = true
SC_TEST_CLOCK = SC_TEST_CLOCK + 100
local initialInvalidAcquisitions = acquisitions
Steering.update()
check(acquisitions == initialInvalidAcquisitions
        and SC.ActionSupervisor.current(other) == nil,
    "an initially invalid cursor is validated before player-control ownership is acquired")
squareLoaded = true
SC_TEST_CLOCK = SC_TEST_CLOCK + 100
Steering.update()
check(SC.ActionSupervisor.current(other).owner == "player_control"
        and acquisitions == initialInvalidAcquisitions + 1,
    "valid steering resumes within one bounded cadence while the key remains held")

held = false
Steering.update()

local acquisitionsBeforeDisabled = acquisitions
local movesBeforeDisabled = #moves
SC.UI.steerHotkey = function() return 0 end
selected = actor
held = true
SC_TEST_CLOCK = SC_TEST_CLOCK + 100
Steering.update()
check(acquisitions == acquisitionsBeforeDisabled and #moves == movesBeforeDisabled
        and SC.ActionSupervisor.current(actor) == nil,
    "an explicitly unbound Steer key never falls back to the default binding")
SC.UI.steerHotkey = function() error("key lookup unavailable") end
SC_TEST_CLOCK = SC_TEST_CLOCK + 100
Steering.update()
check(acquisitions == acquisitionsBeforeDisabled and #moves == movesBeforeDisabled
        and SC.ActionSupervisor.current(actor) == nil,
    "a failed Steer key lookup never activates the registered default")
SC.UI.steerHotkey = nil
SC_TEST_CLOCK = SC_TEST_CLOCK + 100
Steering.update()
check(SC.ActionSupervisor.current(actor) ~= nil,
    "an absent key API still uses the registered default binding")

stopMode = "reject"
held = false
local releaseAccepted, releaseReason = Steering.update()
check(releaseAccepted == false and releaseReason == "steering_stop_rejected"
        and SC.ActionSupervisor.current(actor) ~= nil
        and Steering.status().actor == actor,
    "a rejected movement stop retains both supervisor ownership and the steering session")
selected = other
held = true
SC_TEST_CLOCK = SC_TEST_CLOCK + 100
Steering.update()
check(SC.ActionSupervisor.current(actor) ~= nil
        and SC.ActionSupervisor.current(other) == nil,
    "a new selection cannot acquire while the old steering stop remains unverified")
stopMode = "throw"
SC_TEST_CLOCK = SC_TEST_CLOCK + 100
Steering.update()
check(SC.ActionSupervisor.current(actor) ~= nil
        and SC.ActionSupervisor.current(other) == nil,
    "a throwing stop adapter also retains the old exclusion obligation")
stopMode = "success"
SC_TEST_CLOCK = SC_TEST_CLOCK + 100
Steering.update()
check(SC.ActionSupervisor.current(actor) == nil
        and SC.ActionSupervisor.current(other) ~= nil
        and Steering.status().actor == other,
    "a later verified stop releases exactly once and permits the selected actor to acquire")

held = false
Steering.update()
selected = nil
held = true
SC_TEST_CLOCK = SC_TEST_CLOCK + 100
Steering.update()
check(player.halo == "UI_SC_Steer_NoSelection" and Steering.status().reason == "no_selection",
    "holding steer without a selected companion gives one explicit refusal")

local function stairSquare(x, y, z, kind, solid)
    local square = { x = x, y = y, z = z }
    function square:HasStairTopNorth() return kind == "north" end
    function square:HasStairTopWest() return kind == "west" end
    function square:HasStairsNorth() return kind == "north" or kind == "north-lower" end
    function square:HasStairsWest() return kind == "west" or kind == "west-lower" end
    function square:isSameStaircase(otherX, otherY, otherZ)
        local other = fixedSquares[otherX .. ":" .. otherY .. ":" .. otherZ]
        return other ~= nil and otherZ == z and (kind == "north" and otherX == x
            and otherY >= y and otherY <= y + 2 and other:HasStairsNorth()
            or kind == "west" and otherY == y and otherX >= x and otherX <= x + 2
            and other:HasStairsWest())
    end
    function square:TreatAsSolidFloor() return solid == true end
    fixedSquares[x .. ":" .. y .. ":" .. z] = square
    return square
end

local function tick()
    SC_TEST_CLOCK = SC_TEST_CLOCK + 100
    return Steering.update()
end

SC.GameplayUtil = SC.GameplayUtil or {}
SC.GameplayUtil.isSquareFree = function(square) return square.blocked ~= true end
SC.GameplayUtil.movingBlocker = function(square) return square.occupant end
SC.GameplayUtil.safehouseBlocker = function() return false end
fixedSquares = {}
stairSquare(10, 10, 0, "north")
stairSquare(10, 11, 0, "north-lower")
stairSquare(10, 12, 0, "north-lower")
stairSquare(10, 13, 0, nil, true)
local upper = stairSquare(10, 9, 1, nil, true)
local hall = stairSquare(10, 8, 1, nil, true)
selected, actor.x, actor.y, actor.z = actor, 10.5, 10.4, 0.84
cursorX, cursorY, cursorFloor = 10.70, 8.65, 1
check(tick() == true and Steering.status().active,
    "a cursor projected at the fractional tread reaches the upper landing with no planar destination")
local climbing = SC.ActionSupervisor.current(actor)
local climb = moves[#moves].intent
check(climb.enginePath == true and climb.targetSquare == upper
        and climb.movementTarget == nil and climb.supervisorToken == climbing,
    "the exact steering owner gives the native route only the adjacent solid upper landing")

local beforeAlignmentStops = stops
actor.y, actor.z = 11.05, 0.75
check(tick() and moves[#moves].intent.targetSquare == upper,
    "the engine may back onto the same middle tread before resuming its ascent")
actor.y, actor.z = 12.1, 0.35
check(tick() and moves[#moves].intent.targetSquare == upper and stops == beforeAlignmentStops,
    "native alignment may use the contiguous bottom tread under the same lease")
actor.y, actor.z, cursorX, cursorY = 10.05, 0.98, 17, 15
check(tick() and moves[#moves].intent.targetSquare == upper
        and SC.ActionSupervisor.current(actor) == climbing,
    "changing cursor projection during ascent leaves the verified native crossing in charge")
actor.y, actor.z = 9.5, 0.99
check(tick() and moves[#moves].intent.targetSquare == upper,
    "the destination tile does not complete the crossing below its floor height")
actor.z, cursorX, cursorY = 1, 10.6, 8.5
check(tick() and moves[#moves].intent.movementTarget == true
        and moves[#moves].intent.targetSquare == hall and SC.ActionSupervisor.current(actor) == climbing,
    "upright at the upper landing restores ordinary cursor steering under the same token")
cursorFloor = nil

actor.y, actor.z, cursorY = 10.5, 0.83, 8.7
check(tick() and moves[#moves].intent.targetSquare == upper,
    "the existing lease can start a later crossing")
actor.y, actor.z = 13.1, 0
check(tick() and moves[#moves].intent.targetSquare == upper and stops == beforeAlignmentStops,
    "all three matching treads admit the single clear lower approach tile for native alignment")
actor.y = 14.1
local afterDetourMoves = #moves
local detour, detourReason = tick()
check(not detour and detourReason == "steer_stair_landing_blocked" and #moves == afterDetourMoves
        and SC.ActionSupervisor.current(actor) == climbing,
    "leaving the exact stair footprint stops the native route without dropping steering ownership")

held = false
tick()
local before = #moves
held, actor.y, actor.z, cursorX, cursorY = true, 10.5, 0.82, 11.4, 10.3
local side = stairSquare(11, 10, 0, nil, true)
check(tick() and #moves == before + 1 and moves[#moves].intent.targetSquare == side
        and moves[#moves].intent.enginePath == nil,
    "a sideways cursor on the last stair uses ordinary planar rules")
upper.occupant = {}
before = #moves
cursorX, cursorY = 10.55, 8.65
local heldAtStair = SC.ActionSupervisor.current(actor)
local crowded, crowdedReason = tick()
check(not crowded and crowdedReason == "steer_stair_landing_blocked" and #moves == before
        and SC.ActionSupervisor.current(actor) == heldAtStair,
    "a crowded landing cannot take over movement or detach the held steering lease")
upper.occupant = nil
check(tick() and moves[#moves].intent.targetSquare == upper,
    "a held cursor can start the native crossing once the landing clears")
upper.blocked = true
local crossingStops = stops
before = #moves
local unsafe, unsafeReason = tick()
check(not unsafe and unsafeReason == "steer_stair_landing_blocked"
        and #moves == before and stops == crossingStops + 1
        and SC.ActionSupervisor.current(actor) == heldAtStair,
    "an obstruction during a crossing stops the native path before discarding its target")
upper.blocked = nil
check(tick() and moves[#moves].intent.enginePath == true, "the verified landing is available again")
local downhill = stairSquare(10, 11, 0, nil, true)
cursorX, cursorY = 10.6, 11.6
stopMode = "reject"
before = #moves
local reversing, reversingReason = tick()
check(not reversing and reversingReason == "steering_stop_rejected" and #moves == before
        and SC.ActionSupervisor.current(actor) == heldAtStair,
    "a rejected uphill stop does not issue competing downhill movement")
stopMode = "success"
check(tick() and moves[#moves].intent.targetSquare == downhill
        and moves[#moves].intent.enginePath == nil and SC.ActionSupervisor.current(actor) == heldAtStair,
    "deliberate loaded downhill aim cancels the native crossing and resumes manual motion")

stairSquare(20, 20, -1, "west")
local basementExit = stairSquare(19, 20, 0, nil, true)
actor.x, actor.y, actor.z, cursorX, cursorY = 20.52, 20.51, 0, 18.5, 20.6
check(tick() and moves[#moves].intent.targetSquare == basementExit
        and moves[#moves].intent.enginePath == true,
    "a west basement stair can finish when the body already reaches upper height over the open mouth")
local stopsDuringCrossing = stops
held = false
check(tick() and SC.ActionSupervisor.current(actor) == nil and stops == stopsDuringCrossing + 1,
    "releasing the key on the stair uses the same verified native stop")

held, actor.x, actor.y, actor.z = true, 21.5, 20.5, 0
before = #moves
local missing, missingReason = tick()
check(not missing and missingReason == "cursor_unavailable" and #moves == before
        and SC.ActionSupervisor.current(actor) == nil,
    "an upper floor near a non-stair tile cannot manufacture a native crossing")
held = false
tick()

local pathActor = actorAt("path", 10.5, 10.5, 0.8)
local nativePath = { starts = 0, status = "none", shouldMove = true }
function nativePath:isTargetLocation(x, y, z)
    return x == 10.5 and y == 9.5 and z == 1
end
function nativePath:shouldBeMoving() return self.shouldMove end
function pathActor:getPathFindBehavior2() return nativePath end
function pathActor:getCompanionPathStatus() return nativePath.status end
function pathActor:setIsAiming() end
function pathActor:pathToLocationF()
    nativePath.starts = nativePath.starts + 1
    nativePath.status = "pending"
    nativePath.shouldMove = false
end

local nativeIntent = { action = "steer", enginePath = true, targetSquare = upper }
local provider = { directNative = true }
local reissued, reissueReason = SC.NativeActions.dispatch(pathActor, "walk", nativeIntent, provider)
check(reissued and reissueReason == "path_started" and nativePath.starts == 1,
    "a stopped stair path can restart even when PFB retains the target and reports motion")
local pending, pendingReason = SC.NativeActions.dispatch(pathActor, "walk", nativeIntent, provider)
check(pending and pendingReason == "path_continues" and nativePath.starts == 1,
    "a pending native stair path stays in progress while PFB reports no motion")

print("STEERING_KAHLUA_PASS checks=" .. tostring(checks))
