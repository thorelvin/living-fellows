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

local function cardinalDirection(name)
    local directions = type(_G) == "table" and rawget(_G, "IsoDirections") or nil
    local key = ({ north = "N", south = "S", east = "E", west = "W" })[
        string.lower(tostring(name or ""))]
    if directions == nil or key == nil then return nil end
    local ok, value = pcall(function() return directions[key] end)
    return ok and value or nil
end

function Traversal.alignWindowApproach(actor, fromSquare, toSquare, intent, context)
    local utility = U()
    local entry = { fromSquare = fromSquare, toSquare = toSquare }
    local progress, lateral, forwardX, forwardY = Traversal.doorGeometry(entry, actor)
    if progress == nil then return false, "window_geometry_unavailable" end
    local lateralTolerance = utility.config("navigationWindowApproachLateralTolerance") or 0.10
    local normalTolerance = utility.config("navigationWindowApproachNormalTolerance") or 0.12
    local setback = utility.config("navigationWindowApproachSetback") or 0.38
    if lateral <= lateralTolerance and math.abs(progress + setback) <= normalTolerance then
        -- ISClimbThroughWindow waits until faceDirection has finished before it
        -- submits the native climb. Do the same for companions so the animation
        -- never begins sideways or from the opposite face of the portal.
        local name = invoke(context, "directionBetween", fromSquare, toSquare)
        local direction = cardinalDirection(name)
        if direction ~= nil then
            utility.call(actor, "faceDirection", direction)
            local turning, observed = utility.call(actor, "shouldBeTurning")
            if observed and turning == true then
                invoke(context, "record", actor, "window_approach", {
                    targetSquare = toSquare, status = "turning_to_window",
                })
                return nil, "turning_window_approach"
            end
        end
        return true, "window_approach_aligned"
    end

    local fromX, fromY, fromZ = utility.position(fromSquare)
    local toX, toY = utility.position(toSquare)
    local actorX, actorY = utility.position(actor)
    if fromX == nil or toX == nil or actorX == nil then
        return false, "window_approach_position_unavailable"
    end
    local thresholdX = (fromX + toX) * 0.5 + 0.5
    local thresholdY = (fromY + toY) * 0.5 + 0.5
    local targetX = thresholdX - forwardX * setback
    local targetY = thresholdY - forwardY * setback
    local alignmentIntent = {
        action = "window_approach",
        dx = targetX - actorX,
        dy = targetY - actorY,
        targetPosition = { x = targetX, y = targetY, z = fromZ or 0 },
        targetKind = "world",
        movementArrivalTolerance = math.min(0.06, lateralTolerance * 0.5),
        movementTargetTtlMs = 1000,
        direct = true,
        collisionValidated = true,
        doorwayAlignment = true,
        windowAlignment = true,
        weaponReady = false,
        supervisorToken = intent and intent.supervisorToken,
    }
    local accepted, reason = utility.move(actor, "walk", alignmentIntent)
    if accepted ~= true then return false, reason or "window_approach_rejected" end
    invoke(context, "record", actor, "window_approach", {
        targetSquare = alignmentIntent.targetPosition,
        nextSquare = toSquare,
        status = "aligning_to_window",
    })
    return nil, "aligning_window_approach"
end

-- Native window/fence states stop as soon as the collision capsule crosses the
-- tile boundary. Player input immediately supplies the remaining step, but an
-- AI actor can remain with its feet inside the frame while its next decision is
-- pending. Finish that same short step under the traversal's existing owner.
function Traversal.clearTraversalExit(actor, record, now, context)
    if type(record) ~= "table" or record.effectOnly == true or record.rope == true then
        return true, "traversal_exit_not_required"
    end
    local action = tostring(record.action or "")
    if action ~= "climb_window" and action ~= "climb_window_emergency"
        and action ~= "climb_fence" and action ~= "climb_wall" then
        return true, "traversal_exit_not_required"
    end

    local utility = U()
    local progress, lateral, forwardX, forwardY = Traversal.doorGeometry(record, actor)
    local toX, toY, toZ = utility.position(record.toSquare)
    local actorX, actorY, actorZ = utility.position(actor)
    if progress == nil or toX == nil or actorX == nil then
        return true, "traversal_exit_geometry_unavailable"
    end
    if math.floor(actorX) ~= math.floor(toX) or math.floor(actorY) ~= math.floor(toY)
        or math.floor(actorZ or 0) ~= math.floor(toZ or 0) then
        return false, "traversal_destination_not_reached"
    end

    local clearance = math.max(0.10,
        tonumber(utility.config("navigationTraversalExitClearance")) or 0.38)
    local tolerance = math.max(0.02,
        tonumber(utility.config("navigationTraversalExitTolerance")) or 0.08)
    if progress >= clearance - tolerance and lateral <= tolerance then
        return true, "traversal_exit_clear"
    end

    now = tonumber(now) or utility.nowMs()
    record.exitStartedAt = record.exitStartedAt or now
    record.exitDeadline = record.exitDeadline or (record.exitStartedAt
        + (tonumber(utility.config("navigationTraversalExitTimeoutMs")) or 2000))
    if now >= record.exitDeadline then
        -- A successful native crossing must never become an unbounded owner.
        -- The retained route can still pull the actor away on its next edge.
        return true, "traversal_exit_timeout"
    end

    local fromX, fromY = utility.position(record.fromSquare)
    if fromX == nil then return true, "traversal_exit_origin_unavailable" end
    local thresholdX = (fromX + toX) * 0.5 + 0.5
    local thresholdY = (fromY + toY) * 0.5 + 0.5
    local targetX = thresholdX + forwardX * clearance
    local targetY = thresholdY + forwardY * clearance
    local movementIntent = {
        action = "traversal_exit",
        dx = targetX - actorX,
        dy = targetY - actorY,
        targetPosition = { x = targetX, y = targetY, z = toZ or actorZ or 0 },
        targetKind = "world",
        movementArrivalTolerance = math.min(0.06, tolerance),
        movementTargetTtlMs = 1000,
        direct = true,
        collisionValidated = true,
        doorwayAlignment = true,
        traversalExit = true,
        weaponReady = false,
        supervisorToken = record.supervisorToken,
    }
    local accepted, reason = utility.move(actor, record.mode or "walk", movementIntent)
    invoke(context, "record", actor, "traversal_exit", {
        targetSquare = movementIntent.targetPosition,
        nextSquare = record.toSquare,
        status = accepted == true and "clearing_portal" or tostring(reason or "rejected"),
    })
    -- Retry a rejected pulse until the short deadline. This retains the native
    -- traversal reservation but cannot trap the actor indefinitely.
    return nil, accepted == true and "clearing_traversal_exit"
        or "traversal_exit_retry"
end

function Traversal.handleFence(actor, object, fromSquare, toSquare, intent, context)
    local utility = U()
    local isHoppable, hoppableObserved = utility.call(object, "isHoppable")
    local canClimb, climbObserved = utility.call(object, "canClimbOver", actor)
    if object ~= nil and utility.instanceOf(object, "IsoThumpable")
        and hoppableObserved and isHoppable == true
        and climbObserved and canClimb == true then
        -- The player's E action routes hoppable IsoThumpable objects through
        -- the contextual ClimbThroughWindow action, not hopFence/climbOverWall.
        -- This covers player-built and modded climbable fence objects whose
        -- collision stays active while their contextual climb is legal.
        local climbIntent = {
            action = "climb_window",
            object = object,
            fromSquare = fromSquare,
            targetSquare = toSquare,
            nextSquare = toSquare,
            direction = invoke(context, "directionBetween", fromSquare, toSquare),
            nativeAffordance = "fence",
            hoppableThumpable = true,
            humanAnimationOnly = true,
            supervisorToken = intent and intent.supervisorToken,
        }
        local accepted, reason = utility.move(actor, "walk", climbIntent)
        if accepted ~= true then return false, reason or "thumpable_climb_rejected" end
        invoke(context, "record", actor, "fence_climb", {
            targetSquare = toSquare,
            nextSquare = toSquare,
            status = "climb_thumpable",
        })
        return true, "climbing_thumpable"
    end
    local tall, tallOk = utility.call(object, "isTallHoppable")
    local direction = invoke(context, "directionBetween", fromSquare, toSquare)
    local nativeDirection = cardinalDirection(direction)
    if (not tallOk or object == nil) and nativeDirection ~= nil then
        -- This is the same final affordance test used by the player's E action.
        -- It is deliberately only a dispatch-time fallback: arbitrary A-star
        -- nodes are not necessarily adjacent to the actor and cannot safely use
        -- the character-relative canClimbOverWall check.
        local climbable, climbableOk = utility.call(
            actor, "canClimbOverWall", nativeDirection)
        if climbableOk and climbable == true then tall, tallOk = true, true end
    end
    local action = tallOk and tall == true and "climb_wall" or "climb_fence"
    local climbIntent = {
        action = action,
        object = object,
        fromSquare = fromSquare,
        targetSquare = toSquare,
        nextSquare = toSquare,
        direction = direction,
        nativeAffordance = "fence",
        objectlessFenceFallback = object == nil,
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
