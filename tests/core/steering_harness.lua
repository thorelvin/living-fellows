-- SPDX-License-Identifier: MIT

local SC = SurvivorCompanion
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
local squareLoaded = true
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
function screenToIsoX() return cursorX end
function screenToIsoY() return cursorY end
function isKeyDown(key) return key == 27 and held end
function getText(key) return key end
function getCell()
    return {
        getGridSquare = function(_, x, y, z)
            if not squareLoaded then return nil end
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

print("STEERING_KAHLUA_PASS checks=" .. tostring(checks))
