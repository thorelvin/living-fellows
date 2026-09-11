-- SPDX-License-Identifier: MIT

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
if not SC.GameplayUtil and type(require) == "function" then pcall(require, "SCGameplayUtil") end

SC.NavTraversal = SC.NavTraversal or {}
local Traversal = SC.NavTraversal
local reservations = setmetatable({}, { __mode = "k" })

local function U()
    return SC.GameplayUtil
end

local function invoke(context, name, ...)
    local fn = type(context) == "table" and context[name] or nil
    if type(fn) ~= "function" then return nil end
    return fn(...)
end

function Traversal.reserve(object, actor, now)
    if not object then return true end
    local existing = reservations[object]
    if existing and existing.actor ~= actor and existing.expires > now then return false end
    reservations[object] = {
        actor = actor,
        expires = now + (U().config("navigationReservationMs") or 8000),
    }
    return true
end

function Traversal.release(object, actor)
    local existing = object and reservations[object]
    if existing and existing.actor == actor then reservations[object] = nil end
end

local function beginInteraction(actor, state, object, action, now, extra, executorOwned, context)
    if not Traversal.reserve(object, actor, now) then return false, "reserved" end
    local pending = state.pendingInteraction
    if not pending or pending.object ~= object or pending.action ~= action then
        if executorOwned then
            local movementIntent = U().copyShallow(extra)
            movementIntent.action = action
            movementIntent.object = object
            movementIntent.interaction = true
            movementIntent.targetSquare = U().squareOf(object)
            movementIntent.direction = invoke(
                context, "directionBetween", U().squareOf(actor), movementIntent.targetSquare)
            if not U().move(actor, "walk", movementIntent) then
                Traversal.release(object, actor)
                return false, "action_rejected"
            end
        end
        pending = { object = object, action = action, startedAt = now, extra = extra }
        state.pendingInteraction = pending
        return true, "interacting"
    end
    return true, "pending"
end

local function completeDoorInteraction(actor, state, object, action, fromSquare, toSquare, now, context)
    local utility = U()
    local pending = state.pendingInteraction
    if not pending or pending.object ~= object then return false, "missing_interaction" end
    if action == "open_door" and not invoke(context, "objectOpen", object) then
        local result, toggled = utility.call(object, "ToggleDoor", actor)
        if not toggled or result == false or not invoke(context, "objectOpen", object) then
            return false, "door_open_failed"
        end
    elseif action == "close_door" and invoke(context, "objectOpen", object) then
        local result, toggled = utility.call(object, "ToggleDoor", actor)
        if not toggled or result == false or invoke(context, "objectOpen", object) then
            return false, "door_close_failed"
        end
    end
    if action == "open_door" then
        state.openedDoors[#state.openedDoors + 1] = {
            object = object,
            fromSquare = fromSquare,
            toSquare = toSquare,
            openedAt = now,
            expires = now + (utility.config("navigationReservationMs") or 8000),
            passageKey = invoke(context, "actorPassageKey", actor, state),
        }
    else
        Traversal.release(object, actor)
    end
    state.pendingInteraction = nil
    return true, "done"
end

-- Explicit door commands share the same reservation, toggle and verified
-- postcondition as route traversal, but may request either open or closed.
function Traversal.interactDoor(actor, state, door, action, fromSquare, toSquare, now, context)
    if action ~= "open_door" and action ~= "close_door" then
        return false, "unsupported_door_action"
    end
    local desiredOpen = action == "open_door"
    if invoke(context, "objectOpen", door) == desiredOpen then
        return true, "already_set"
    end
    local obstructed, obstructedOk = U().call(door, "isObstructed")
    if obstructedOk and obstructed == true then return false, "obstructed_door" end
    if desiredOpen and invoke(context, "objectLocked", door)
        and not invoke(context, "actorCanUnlock", actor, door) then
        return false, "locked_door"
    end
    local ok, status = beginInteraction(actor, state, door, action, now, {
        fromSquare = fromSquare, toSquare = toSquare,
    }, false, context)
    if not ok then return false, status end
    return completeDoorInteraction(actor, state, door, action,
        fromSquare, toSquare, now, context)
end

function Traversal.handleDoor(actor, state, door, fromSquare, toSquare, now, context)
    if invoke(context, "objectOpen", door) then return true end
    local obstructed, obstructedOk = U().call(door, "isObstructed")
    if obstructedOk and obstructed == true then return false, "obstructed_door" end
    if invoke(context, "objectLocked", door)
        and not invoke(context, "actorCanUnlock", actor, door) then
        return false, "locked_door"
    end
    local ok, status = beginInteraction(actor, state, door, "open_door", now, {
        fromSquare = fromSquare, toSquare = toSquare,
    }, false, context)
    if not ok then return false, status end
    local complete, completeStatus = completeDoorInteraction(
        actor, state, door, "open_door", fromSquare, toSquare, now, context)
    if not complete then return false, completeStatus end
    if completeStatus ~= "done" then return nil, completeStatus end
    return true
end

local function completeWindowAction(actor, state, window, action, now, context)
    local utility = U()
    local pending = state.pendingInteraction
    if not pending or pending.object ~= window then return false, "missing_interaction" end
    local delays = {
        open_window = utility.config("windowOpenMs") or 1300,
        smash_window = utility.config("windowSmashMs") or 900,
        remove_glass = utility.config("windowGlassRemovalMs") or 1400,
    }
    local verified = action == "open_window" and invoke(context, "objectOpen", window)
        or action == "smash_window" and invoke(context, "windowSmashed", window)
        or action == "remove_glass" and invoke(context, "windowGlassRemoved", window)
    if not verified then
        -- The adapter already submitted the native event. Re-submitting here or
        -- toggling the object directly races the animation and duplicates effects.
        if now - pending.startedAt < math.max(3500, (delays[action] or 500) + 1500) then
            return nil, "traversal_starting:" .. action
        end
        Traversal.release(window, actor)
        state.pendingInteraction = nil
        return false, action .. "_verification_timeout"
    end
    state.pendingInteraction = nil
    return true, "done"
end

function Traversal.handleWindow(actor, state, window, fromSquare, toSquare, now, intent, context)
    local utility = U()
    local pending = state.pendingInteraction
    if pending and pending.object == window then
        local complete, status = completeWindowAction(actor, state, window, pending.action, now, context)
        if complete ~= true then return complete, status end
    end
    if invoke(context, "objectBarricaded", window) then return false, "barricaded_window" end
    if invoke(context, "windowInvincible", window)
        and not invoke(context, "objectOpen", window) then return false, "invincible_window" end
    local arrival = invoke(context, "threatArrivalMs", intent, fromSquare) or math.huge
    local action
    if invoke(context, "objectOpen", window) then
        action = "climb_window"
    elseif invoke(context, "windowSmashed", window) then
        if invoke(context, "windowGlassRemoved", window) then
            action = "climb_window"
        elseif arrival > (utility.config("windowGlassRemovalMs") or 1400)
            + (utility.config("windowClimbMs") or 1300) then
            action = "remove_glass"
        else
            action = "climb_window_emergency"
        end
    elseif not invoke(context, "objectLocked", window)
        and arrival > (utility.config("windowOpenMs") or 1300)
            + (utility.config("windowClimbMs") or 1300) then
        action = "open_window"
    else
        action = "smash_window"
    end

    if action == "climb_window" or action == "climb_window_emergency" then
        if not invoke(context, "canClimbThrough", window, actor)
            and action ~= "climb_window_emergency" then
            return false, "unsafe_window_frame"
        end
        if not Traversal.reserve(window, actor, now) then return false, "reserved" end
        local accepted = utility.move(actor, intent and intent.mode or "walk", {
            action = action,
            object = window,
            fromSquare = fromSquare,
            toSquare = toSquare,
            nextSquare = toSquare,
            targetSquare = toSquare,
            direction = invoke(context, "directionBetween", fromSquare, toSquare),
            acceptsInjury = action == "climb_window_emergency",
            supervisorToken = intent and intent.supervisorToken,
        })
        if not accepted then
            Traversal.release(window, actor)
            return false, "action_rejected"
        end
        return nil, "climbing"
    end

    local ok, status = beginInteraction(actor, state, window, action, now, {
        fromSquare = fromSquare, toSquare = toSquare,
        supervisorToken = intent and intent.supervisorToken,
    }, true, context)
    if not ok then return false, status end
    local complete, completeStatus = completeWindowAction(actor, state, window, action, now, context)
    if complete == false then return false, completeStatus end
    if complete == nil then return nil, completeStatus end
    return nil, "reconsider_window"
end

function Traversal.handleWindowFrame(actor, frame, fromSquare, toSquare, now, intent, context)
    local utility = U()
    if not invoke(context, "canClimbThrough", frame, actor) then
        return false, "blocked_window_frame"
    end
    if not Traversal.reserve(frame, actor, now) then return false, "reserved" end
    local accepted = utility.move(actor, intent and intent.mode or "walk", {
        action = "climb_window",
        object = frame,
        fromSquare = fromSquare,
        toSquare = toSquare,
        nextSquare = toSquare,
        targetSquare = toSquare,
        direction = invoke(context, "directionBetween", fromSquare, toSquare),
        emptyFrame = true,
        supervisorToken = intent and intent.supervisorToken,
    })
    if not accepted then
        Traversal.release(frame, actor)
        return false, "action_rejected"
    end
    return nil, "climbing_frame"
end

function Traversal.doorGeometry(entry, value)
    local utility = U()
    if type(entry) ~= "table" or not entry.fromSquare or not entry.toSquare then return nil end
    local fx, fy, fz = utility.position(entry.fromSquare)
    local tx, ty, tz = utility.position(entry.toSquare)
    local vx, vy, vz = utility.position(value)
    if fx == nil or tx == nil or vx == nil or math.floor(fz or 0) ~= math.floor(tz or 0)
        or math.floor(vz or 0) ~= math.floor(fz or 0) then return nil end
    local dx, dy = tx - fx, ty - fy
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 0.5 then return nil end
    dx, dy = dx / length, dy / length
    local thresholdX = (fx + tx) * 0.5 + 0.5
    local thresholdY = (fy + ty) * 0.5 + 0.5
    local offsetX, offsetY = vx - thresholdX, vy - thresholdY
    return offsetX * dx + offsetY * dy,
        math.abs(offsetX * -dy + offsetY * dx), dx, dy
end

function Traversal.occupiesDoorway(value, entry)
    local progress, lateral = Traversal.doorGeometry(entry, value)
    if progress == nil then return false end
    local clearance = U().config("doorClearanceDistance") or 0.38
    return math.abs(progress) < clearance and lateral <= 0.55
end

function Traversal.alignDoorApproach(actor, fromSquare, toSquare, intent, affordance, context)
    local utility = U()
    local entry = { fromSquare = fromSquare, toSquare = toSquare }
    local progress, lateral, forwardX, forwardY = Traversal.doorGeometry(entry, actor)
    if progress == nil then return false, "door_geometry_unavailable" end
    local tolerance = utility.config("navigationDoorApproachLateralTolerance") or 0.18
    if lateral <= tolerance then return true, "door_approach_aligned" end

    local fromX, fromY, fromZ = utility.position(fromSquare)
    local toX, toY = utility.position(toSquare)
    local actorX, actorY = utility.position(actor)
    if fromX == nil or toX == nil or actorX == nil then
        return false, "door_approach_position_unavailable"
    end
    local thresholdX = (fromX + toX) * 0.5 + 0.5
    local thresholdY = (fromY + toY) * 0.5 + 0.5
    local setback = utility.config("doorClearanceDistance") or 0.38
    local desiredProgress = math.min(progress, -setback)
    local targetX = thresholdX + forwardX * desiredProgress
    local targetY = thresholdY + forwardY * desiredProgress
    local prefix = affordance == "fence" and "fence" or "door"
    local alignmentIntent = {
        action = prefix .. "_approach",
        dx = targetX - actorX,
        dy = targetY - actorY,
        targetPosition = { x = targetX, y = targetY, z = fromZ or 0 },
        targetKind = "world",
        movementArrivalTolerance = math.min(0.08, tolerance * 0.5),
        movementTargetTtlMs = 750,
        direct = true,
        collisionValidated = true,
        doorwayAlignment = affordance ~= "fence",
        fenceAlignment = affordance == "fence",
        weaponReady = false,
        supervisorToken = intent and intent.supervisorToken,
    }
    local accepted, reason = utility.move(actor, "walk", alignmentIntent)
    if accepted ~= true then return false, reason or "door_approach_rejected" end
    invoke(context, "record", actor, prefix .. "_approach", {
        targetSquare = alignmentIntent.targetPosition,
        nextSquare = toSquare,
        status = "aligning_to_threshold",
    })
    return nil, "aligning_" .. prefix .. "_approach"
end

function Traversal.handleFence(actor, object, fromSquare, toSquare, intent, context)
    local utility = U()
    local tall, tallOk = utility.call(object, "isTallHoppable")
    local action = tallOk and tall == true and "climb_wall" or "climb_fence"
    local climbIntent = {
        action = action,
        object = object,
        fromSquare = fromSquare,
        targetSquare = toSquare,
        nextSquare = toSquare,
        direction = invoke(context, "directionBetween", fromSquare, toSquare),
        nativeAffordance = "fence",
        humanAnimationOnly = true,
        supervisorToken = intent and intent.supervisorToken,
    }
    local accepted, reason = utility.move(actor, "walk", climbIntent)
    if accepted ~= true then return false, reason or (action .. "_rejected") end
    invoke(context, "record", actor, "fence_climb", {
        targetSquare = toSquare,
        nextSquare = toSquare,
        status = action,
    })
    return true, action == "climb_wall" and "climbing_wall" or "climbing_fence"
end

function Traversal.nearbyOpenedDoor(state, actor, context)
    for _, entry in ipairs(state.openedDoors or {}) do
        local progress, cross = Traversal.doorGeometry(entry, actor)
        if invoke(context, "objectOpen", entry.object) and progress ~= nil
            and math.abs(progress) <= 1.15 and cross <= 1.15 then return entry end
    end
    return nil
end

local function actorClearOfDoorway(actor, entry)
    local progress = Traversal.doorGeometry(entry, actor)
    return progress ~= nil and progress >= (U().config("doorClearanceDistance") or 0.38)
end

local function safeToCloseDoor(entry, snapshot, actor, context)
    local utility = U()
    if not actorClearOfDoorway(actor, entry) then return false end
    if entry.passageKey and invoke(context, "passageActive", entry.passageKey, utility.nowMs()) then
        return false
    end
    if type(snapshot) ~= "table" then return true end
    for index = 1, math.min(#(snapshot.threats or {}), 12) do
        if utility.distanceSq(entry.object, snapshot.threats[index].actor) <= 4 then return false end
    end
    for _, ally in ipairs(snapshot.allies or {}) do
        local other = ally and (ally.actor or ally) or nil
        if other and other ~= actor and Traversal.occupiesDoorway(other, entry) then return false end
    end
    local player = snapshot.player
    player = type(player) == "table" and (player.actor or player) or nil
    if player and player ~= actor and Traversal.occupiesDoorway(player, entry) then return false end
    return true
end

function Traversal.closeOwnedDoors(actor, state, now, snapshot, context)
    local utility = U()
    local write = 1
    for index = 1, #state.openedDoors do
        local entry = state.openedDoors[index]
        local keep = true
        if now >= entry.expires then
            Traversal.release(entry.object, actor)
            keep = false
        elseif invoke(context, "objectOpen", entry.object)
            and not invoke(context, "sameSquare", utility.squareOf(actor), entry.fromSquare)
            and utility.distance(actor, entry.toSquare) <= 2.75
            and now - entry.openedAt >= (utility.config("doorCloseDelayMs") or 700)
            and now >= (state.recoveryDoorHoldUntil or 0)
            and safeToCloseDoor(entry, snapshot, actor, context) then
            local result, toggled = utility.call(entry.object, "ToggleDoor", actor)
            if toggled and result ~= false and not invoke(context, "objectOpen", entry.object) then
                Traversal.release(entry.object, actor)
                keep = false
            end
        elseif not invoke(context, "objectOpen", entry.object) then
            Traversal.release(entry.object, actor)
            keep = false
        end
        if keep then state.openedDoors[write] = entry write = write + 1 end
    end
    for index = #state.openedDoors, write, -1 do state.openedDoors[index] = nil end
end

function Traversal.releaseState(actor, state)
    if type(state) ~= "table" then return end
    for _, entry in ipairs(state.openedDoors or {}) do
        Traversal.release(entry.object, actor)
    end
    if state.pendingInteraction then Traversal.release(state.pendingInteraction.object, actor) end
end

function Traversal.reset()
    reservations = setmetatable({}, { __mode = "k" })
end

function Traversal.releaseActor(actor)
    if actor == nil then return false end
    for object, reservation in pairs(reservations) do
        if reservation and reservation.actor == actor then reservations[object] = nil end
    end
    return true
end

return Traversal
