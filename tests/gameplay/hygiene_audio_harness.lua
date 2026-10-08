-- SPDX-License-Identifier: MIT

local sc = SurvivorCompanion
local needs, utility = sc.Needs, sc.GameplayUtil
local oldNative = sc.NativeActions
local native, navigation = oldNative or {}, sc.Navigation
sc.NativeActions = native
local saved = {
    nowMs = utility.nowMs,
    actorState = utility.actorState,
    isValidActor = utility.isValidActor,
    position = utility.position,
    sameSquare = utility.sameSquare,
    move = utility.move,
    byId = sc.Registry.byId,
    visualStatus = native.visualStatus,
    clearVisual = native.clearVisual,
    cancelVisual = native.cancelVisual,
    cancelNeeds = native.cancelNeeds,
    furnitureStatus = native.furnitureStatus,
    leaveFurniture = native.leaveFurniture,
    navCancel = navigation.cancel,
    say = sc.Dialogue.say,
}

local now, playCount, stopCount, visualState = 1000, 0, 0, "active"
local lastHandle, nextHandle = nil, 100
local square = {}
local actor = {
    getVehicle = function() return nil end,
    isFemale = function() return false end,
    isSittingOnFurniture = function() return true end,
    playSound = function(_, name)
        assert(name == "LFUrinate", "relief should play the registered game sound")
        playCount = playCount + 1
        nextHandle = nextHandle + 1
        return nextHandle
    end,
    stopOrTriggerSound = function(_, handle)
        stopCount = stopCount + 1
        lastHandle = handle
        return true
    end,
}
local runtime = { needs = {} }
local function routeTask()
    runtime.needs.nextPeeRetryAt = 0
    runtime.needs.pee = { square = square, startedAt = now,
        lastX = 5, lastY = 5, lastProgressAt = now,
        style = "pee_stand" }
end

utility.nowMs = function() return now end
utility.actorState = function(candidate)
    if candidate == actor then return runtime end
    return saved.actorState(candidate)
end
utility.isValidActor = function(candidate)
    return candidate == actor or saved.isValidActor(candidate)
end
utility.position = function(candidate)
    if candidate == actor then return 5, 5, 0 end
    return saved.position(candidate)
end
utility.sameSquare = function(candidate, target)
    if candidate == actor then return target == square end
    return saved.sameSquare(candidate, target)
end
local moveAccepted = true
utility.move = function(candidate, _, options)
    if candidate == actor then
        assert(options.action == "pee_stand" and options.durationMs == 6000,
            "standing relief should request a six-second visual")
        return moveAccepted, moveAccepted and "accepted" or "rejected"
    end
    return saved.move(candidate, _, options)
end
sc.Registry.byId = function() return nil end
native.visualStatus = function() return visualState end
native.clearVisual = function() return true end
native.cancelVisual = function() return true end
native.cancelNeeds = function() return true end
native.furnitureStatus = function() return "entered" end
native.leaveFurniture = function() return true end
navigation.cancel = function() return true end
sc.Dialogue.say = function() return true end

routeTask()
moveAccepted = false
assert(select(1, needs.update(actor, nil, runtime)) == false and playCount == 0,
    "a rejected relief action must remain silent")

routeTask()
moveAccepted = true
local started, startReason = needs.update(actor, nil, runtime)
assert(started == true
    and runtime.needs.pee.phase == "animating" and playCount == 1,
    "accepted standing relief should start exactly one sound: "
        .. tostring(started) .. ":" .. tostring(startReason) .. ":"
        .. tostring(runtime.needs.pee and runtime.needs.pee.phase)
        .. ":" .. tostring(playCount))
assert(select(1, needs.update(actor, nil, runtime)) == true and playCount == 1,
    "each update of the same relief action must not replay sound")
visualState = "completed"
assert(select(1, needs.update(actor, nil, runtime)) == true
    and runtime.needs.pee == nil and stopCount == 1 and lastHandle == 101,
    "completed relief should stop its original handle")

routeTask()
visualState = "active"
needs.update(actor, nil, runtime)
assert(playCount == 2, "a new relief action should start a new sound")
needs.cancel(actor, "unsafe")
assert(runtime.needs.pee == nil and stopCount == 2 and lastHandle == 102,
    "cancellation should stop sound immediately and once")
needs.cancel(actor, "unsafe")
assert(stopCount == 2, "repeat cancellation must not stop the handle twice")

runtime.needs.pee = { phase = "seating", seatingAt = now }
needs.update(actor, nil, runtime)
assert(runtime.needs.pee.phase == "seated" and playCount == 3,
    "seated relief should start sound only after the seat is entered")
now = now + 6001
needs.update(actor, nil, runtime)
assert(runtime.needs.pee == nil and stopCount == 3 and lastHandle == 103,
    "seated relief should stop sound when its six seconds end")

-- The Base Watch leader never takes the outdoor fallback: four seconds
-- outside hands the camp's second view to someone else. Without a usable
-- toilet it skips the break and waits for the next one.
local outdoorSquare = {
    getRoom = function() return nil end,
    getMovingObjects = function() return {} end,
}
local hygiene = { state = { downtime = { nextPeeHour = 90 } } }
local oldWatch, oldGetGameTime = sc.BaseWatch, getGameTime
local leading = false
sc.BaseWatch = { isLeader = function(candidate) return leading and candidate == actor end }
getGameTime = function() return { getWorldAgeHours = function() return 100 end } end
sc.Registry.byId = function() return hygiene end
actor.square = outdoorSquare
local oldRequest = navigation.request
navigation.request = function() return true, "moving" end
needs.reset(actor)
runtime.needs = {}
local stepped, steppedReason = needs.update(actor, nil, runtime)
assert(runtime.needs.pee ~= nil and runtime.needs.pee.square == outdoorSquare,
    "control: an ordinary companion takes the outdoor spot: "
        .. tostring(stepped) .. ":" .. tostring(steppedReason))
needs.cancel(actor, "test_reset")
runtime.needs.nextPeeRetryAt = 0
leading = true
local held, heldReason = needs.update(actor, nil, runtime)
assert(held == false and heldReason == "bathroom_watcher_stays_indoors"
    and runtime.needs.pee == nil and hygiene.state.downtime.nextPeeHour > 100,
    "the Base Watch leader skips a break rather than step outdoors: "
        .. tostring(held) .. ":" .. tostring(heldReason))
hygiene.state.downtime.nextPeeHour = 90
runtime.needs.nextPeeRetryAt = 0
runtime.needs.pee = { toilet = { object = {}, targets = { {} } }, startedAt = now,
    lastX = 5, lastY = 5, lastProgressAt = now - 7000, sits = false, style = "pee_stand" }
local stalled, stalledReason = needs.update(actor, nil, runtime)
assert(stalled == false and stalledReason == "bathroom_watcher_stays_indoors"
    and runtime.needs.pee == nil and hygiene.state.downtime.nextPeeHour > 100,
    "a stalled toilet route never sends the Base Watch leader outdoors: "
        .. tostring(stalled) .. ":" .. tostring(stalledReason))
actor.square = nil
navigation.request = oldRequest
sc.BaseWatch, getGameTime = oldWatch, oldGetGameTime
sc.Registry.byId = function() return nil end

needs.reset(actor)
utility.nowMs, utility.actorState, utility.isValidActor,
    utility.position, utility.sameSquare, utility.move =
    saved.nowMs, saved.actorState, saved.isValidActor,
    saved.position, saved.sameSquare, saved.move
sc.Registry.byId = saved.byId
native.visualStatus, native.clearVisual, native.cancelVisual,
    native.cancelNeeds, native.furnitureStatus, native.leaveFurniture =
    saved.visualStatus, saved.clearVisual, saved.cancelVisual,
    saved.cancelNeeds, saved.furnitureStatus, saved.leaveFurniture
navigation.cancel, sc.Dialogue.say = saved.navCancel, saved.say
sc.NativeActions = oldNative
print("HYGIENE_AUDIO_PASS checks=12")
