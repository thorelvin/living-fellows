-- SPDX-License-Identifier: MIT

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion

SC.NativeTraversalActions = SC.NativeTraversalActions or {}
local Traversal = SC.NativeTraversalActions
local context
local pending = setmetatable({}, { __mode = "k" })
local lastWallClimbReactionAt = -math.huge

function Traversal.configure(value)
    assert(type(value) == "table", "native traversal context is required")
    context = value
    return Traversal
end

local function invoke(object, name, ...)
    return context.invoke(object, name, ...)
end

local function useProvider(provider, operation, ...)
    return context.useProvider(provider, operation, ...)
end

local function nowMs()
    return SC.GameplayUtil and SC.GameplayUtil.nowMs() or getTimestampMs()
end

local function config(name, fallback)
    return SC.Config and tonumber(SC.Config.get(name)) or fallback
end

local function climbing(actor)
    local observed, active = invoke(actor, "isCompanionTraversalActive")
    if observed and type(active) == "boolean" then return active end
    -- B42's isClimbing() is a legacy boolean, not a StateMachine query.
    -- Fence/wall/window states set their own animation variables without
    -- setting that field, so observing only it cancels genuine vaults.
    local _, nativeState = invoke(actor, "getCurrentState")
    local stateName = SC.GameplayUtil and SC.GameplayUtil.objectLabel(nativeState) or tostring(nativeState)
    local _, actionState = invoke(actor, "getCompanionActionStateName")
    local names = string.lower(tostring(stateName) .. ":" .. tostring(actionState))
    for _, name in ipairs({ "climboverfence", "climboverwall", "climbthroughwindow",
        "climbfence", "climbwall", "climbwindow", "climbsheetrope",
        "climbdownsheetrope", "climbrope", "climbdownrope" }) do
        if string.find(names, name, 1, true) then return true end
    end
    local ok, value = invoke(actor, "isClimbing")
    if ok and value == true then return true end
    ok, value = invoke(actor, "isClimbingRope")
    return ok and value == true
end

local function position(actor)
    local _, x = invoke(actor, "getX")
    local _, y = invoke(actor, "getY")
    local _, z = invoke(actor, "getZ")
    return tonumber(x), tonumber(y), tonumber(z)
end

local function effectDone(record)
    local methodName = ({ open_window = "IsOpen", smash_window = "isSmashed",
        remove_glass = "isGlassRemoved" })[record.action]
    if not methodName then return false end
    local ok, result = invoke(record.object, methodName)
    return ok and result == true
end

-- A climb submitted through an open window may sit in the native event queue
-- for a frame or two.  Re-read the portal before the animation owns the actor;
-- another survivor can close the window during that gap.  Unknown native state
-- remains admissible so compatibility adapters without every getter do not fail
-- closed on an observation we could not make.
local function windowClimbStillValid(record)
    if record.action ~= "climb_window" or record.object == nil then return true end
    if record.hoppableThumpable == true then
        local observed, climbable = invoke(record.object, "canClimbOver", record.actor)
        return not observed or climbable == true
    end
    local openObserved, open = invoke(record.object, "IsOpen")
    if not openObserved then openObserved, open = invoke(record.object, "isOpen") end
    if openObserved and open == true then return true end
    local smashedObserved, smashed = invoke(record.object, "isSmashed")
    if smashedObserved and smashed == true then
        local glassObserved, glassRemoved = invoke(record.object, "isGlassRemoved")
        return not glassObserved or glassRemoved == true
    end
    if openObserved and smashedObserved then return false end
    return true
end

local function windowAnimationActive(actor, action)
    if action == "remove_glass" then return false end
    local observed, active = invoke(actor, "isCompanionTraversalActive")
    if observed and type(active) == "boolean" then return active end
    local flag = action == "open_window" and "bOpenWindow" or "bSmashWindow"
    local ok, value = invoke(actor, "getVariableBoolean", flag)
    if ok and value == true then return true end
    local _, nativeState = invoke(actor, "getCurrentState")
    local stateName = SC.GameplayUtil and SC.GameplayUtil.objectLabel(nativeState) or tostring(nativeState)
    local _, actionState = invoke(actor, "getCompanionActionStateName")
    local names = string.lower(tostring(stateName) .. ":" .. tostring(actionState))
    return string.find(names, "openwindow", 1, true) ~= nil
        or string.find(names, "smashwindow", 1, true) ~= nil
end

local function cancelNative(actor, record, current)
    if current < (record.cancelNextAt or 0) then return false end
    record.cancelNextAt = current + 250
    local methodName = "cancelCompanionStuckClimb"
    if SC.GameplayUtil and SC.GameplayUtil.hasMethod(actor, "cancelCompanionTraversal") then
        methodName = "cancelCompanionTraversal"
    elseif record.effectOnly then
        -- The legacy climb-only adapter cannot cancel window opening/smashing.
        return false
    end
    local ok, cancelled = invoke(actor, methodName)
    return ok and cancelled == true
end

-- Tall-wall success and struggle are separate vanilla rolls. Keep the values
-- captured at dispatch so the reaction still matches the animation after
-- ClimbOverWallState clears its variables on exit. Speech is deliberately a
-- terminal side effect: it never owns movement and cannot delay urgent combat.
local function considerWallClimbReaction(record, current)
    if record.action ~= "climb_wall" or record.reactionConsidered == true
        or (record.phase ~= "completed" and record.phase ~= "failed") then return end
    record.reactionConsidered = true
    local outcome = record.wallClimbOutcome
    if outcome ~= "success" and outcome ~= "struggle" and outcome ~= "fail" then return end

    local commands = SC.Commands
    local state
    if type(commands) == "table" and type(commands.peek) == "function" then
        local ok, value = pcall(commands.peek, record.actor)
        if ok and type(value) == "table" then state = value end
    end
    if type(state) ~= "table" or state.recruited ~= true or state.order == "retreat" then return end
    local token = record.supervisorToken
    local critical = SC.ActionSupervisor and SC.ActionSupervisor.Priority
        and tonumber(SC.ActionSupervisor.Priority.COMBAT_RESCUE) or 500
    if type(token) == "table" and (tonumber(token.priority) or 0) >= critical then return end

    local dialogue = SC.Dialogue
    local utility = SC.GameplayUtil
    if type(dialogue) ~= "table" or type(dialogue.say) ~= "function"
        or type(utility) ~= "table" or type(utility.stableHash) ~= "function" then return end
    local actorGap = config("wallClimbReactionActorCooldownMs", 10000)
    if type(dialogue.lastSpokenAt) == "function"
        and current - (tonumber(dialogue.lastSpokenAt(record.actor)) or -math.huge)
            < actorGap then return end
    if current - lastWallClimbReactionAt
        < config("wallClimbReactionGroupCooldownMs", 3000) then return end

    local chance = math.max(0, math.min(100,
        config("wallClimbReactionChancePercent", 35)))
    local salt = tostring(utility.idOf(record.actor)) .. ":wall-climb:"
        .. outcome .. ":" .. tostring(record.startedAt)
    if utility.stableHash(salt) % 100 >= chance then return end
    local topic = "traversal.wall." .. outcome
    local spoken = dialogue.say(record.actor, topic, nil, nil, {
        state = state, recentLimit = 4, salt = salt,
    })
    if spoken == true then lastWallClimbReactionAt = current end
end

-- Native traversal requests queue action events. A false isClimbing result in
-- the dispatch frame is not a rejection; retain ownership until a later update
-- observes entry, completion, or a bounded failure.
function Traversal.poll(actor, current)
    local record = pending[actor]
    if not record then return "none", nil, nil end
    current = tonumber(current) or nowMs()
    if record.phase == "completed" or record.phase == "failed"
        or record.phase == "cancelled" then
        if current - (record.finishedAt or current) > 2000 then pending[actor] = nil end
        return record.phase, record.reason, record
    end
    local active = climbing(actor)
    if not active and record.phase == "starting"
        and not windowClimbStillValid(record) then
        if cancelNative(actor, record, current) then
            record.phase = "cancelled"
            record.reason = "traversal_portal_changed:" .. record.action
        else
            record.reason = "traversal_cancel_pending:" .. record.action
        end
    elseif record.effectOnly then
        record.effectVerified = record.effectVerified or effectDone(record)
        if windowAnimationActive(actor, record.action) then
            record.phase, record.observedAt = "active", record.observedAt or current
            record.reason = "traversal_active:" .. record.action
        elseif record.effectVerified and (record.observedAt or record.action == "remove_glass") then
            record.phase, record.reason = "completed", "traversal_effect_verified"
        elseif record.observedAt then
            record.phase, record.reason = "failed", "traversal_exited_without_effect:" .. record.action
        end
    elseif active then
        record.phase = "active"
        record.observedAt = record.observedAt or current
        record.reason = "traversal_active:" .. record.action
    elseif record.observedAt then
        local x, y, z = position(actor)
        local moved = x and record.x and ((x - record.x)^2 + (y - record.y)^2 > 0.04
            or math.abs((z or 0) - (record.z or 0)) > 0.1)
        local tx, ty, tz = position(record.toSquare)
        local destinationReached = record.rope == true or record.toSquare == nil
            or (x and tx and math.floor(x) == math.floor(tx)
                and math.floor(y) == math.floor(ty)
                and math.floor(z or 0) == math.floor(tz or 0))
        record.phase = moved and destinationReached and "completed" or "failed"
        record.reason = not moved and "traversal_exited_without_progress"
            or destinationReached and "traversal_completed"
            or "traversal_exited_without_destination"
    elseif record.toSquare and current >= record.startDeadline then
        -- A low-frequency observer can miss a whole short animation. Actual
        -- arrival across the requested boundary is also authoritative evidence.
        local x, y, z = position(actor)
        local tx, ty, tz = position(record.toSquare)
        local fx, fy, fz = position(record.fromSquare)
        local differentCell = fx and tx and (math.floor(fx) ~= math.floor(tx)
            or math.floor(fy) ~= math.floor(ty) or math.floor(fz or 0) ~= math.floor(tz or 0))
        local ropeArrival = record.rope and x and record.x
            and math.floor(z or 0) ~= math.floor(record.z or 0)
            and (x - record.x)^2 + (y - record.y)^2 <= 1
        if differentCell and x and record.x
            and ((math.floor(x) == math.floor(tx) and math.floor(y) == math.floor(ty)) or ropeArrival)
            and math.floor(z or 0) == math.floor(tz or 0)
            and ((x - record.x)^2 + (y - record.y)^2 > 0.04
                or math.abs((z or 0) - (record.z or 0)) > 0.1) then
            if cancelNative(actor, record, current) then
                record.phase, record.reason = "completed", "traversal_destination_verified"
            else record.reason = "traversal_cancel_pending:" .. record.action end
        end
    end
    if record.phase == "starting" and current >= record.startDeadline then
        if cancelNative(actor, record, current) then
            record.phase = record.effectVerified and "completed" or "failed"
            record.reason = record.effectVerified and "traversal_effect_verified_after_cancel"
                or "traversal_start_timeout:" .. record.action
        else record.reason = "traversal_cancel_pending:" .. record.action end
    elseif record.phase == "active" and current >= record.finishDeadline then
        if cancelNative(actor, record, current) then
            record.phase = record.effectVerified and "completed" or "failed"
            record.reason = record.effectVerified and "traversal_effect_verified_after_cancel"
                or "traversal_state_timeout:" .. record.action
        else
            -- Keep ownership if native state could not be safely released.
            record.reason = "traversal_cancel_pending:" .. record.action
        end
    end
    if record.phase == "completed" or record.phase == "failed"
        or record.phase == "cancelled" then
        record.finishedAt = current
        if record.phase ~= "cancelled" then considerWallClimbReaction(record, current) end
    end
    return record.phase, record.reason, record
end

function Traversal.activityStatus(actor, current)
    local phase, reason, record = Traversal.poll(actor, current)
    if phase == "starting" or phase == "active" then
        return "active", "traversal", record.action, record.startedAt, record
    end
    return "none", nil, nil, nil, record
end

function Traversal.cancel(actor, reason)
    local phase, _, record = Traversal.poll(actor)
    if phase == "active" then
        -- Opening/smashing a window has no cross-boundary motion and can yield
        -- to survival combat.  Once a climb owns the capsule, cancellation is
        -- unsafe and the urgent action must wait for the short native traversal.
        if not record.effectOnly or not cancelNative(actor, record, nowMs()) then
            return false, "traversal_active"
        end
    end
    if phase == "starting" and not cancelNative(actor, record, nowMs()) then
        return false, "traversal_starting"
    end
    pending[actor] = nil
    return true, reason or "traversal_cleared"
end

function Traversal.reset(actor)
    if actor then pending[actor] = nil
    else
        pending = setmetatable({}, { __mode = "k" })
        lastWallClimbReactionAt = -math.huge
    end
end

local function existingRequest(actor, action, object)
    local phase, reason, record = Traversal.poll(actor)
    if not record then return nil end
    if phase == "starting" or phase == "active" then
        return record.action == action and record.object == object,
            record.action == action and (reason or "traversal_starting") or "traversal_owned"
    end
    if record.action == action and record.object == object and phase == "failed" then
        return false, reason
    end
    pending[actor] = nil
    return nil
end

local function retainRequest(actor, action, intent, startedReason, effectOnly)
    local current = nowMs()
    local x, y, z = position(actor)
    local rope = action == "climb_sheet_rope" or action == "climb_down_sheet_rope"
    local active = effectOnly and windowAnimationActive(actor, action) or not effectOnly and climbing(actor)
    pending[actor] = {
        actor = actor,
        action = action, object = intent.object, fromSquare = intent.fromSquare,
        toSquare = intent.toSquare or intent.nextSquare or intent.targetSquare,
        mode = intent.mode or "walk", supervisorToken = intent.supervisorToken,
        phase = active and "active" or "starting", startedAt = current,
        observedAt = active and current or nil, x = x, y = y, z = z,
        effectOnly = effectOnly == true, rope = rope,
        hoppableThumpable = intent.hoppableThumpable == true,
        startDeadline = current + config("nativeTraversalStartTimeoutMs", effectOnly and 3500 or 1500),
        finishDeadline = current + config("nativeTraversalTimeoutMs", rope and 30000 or 15000),
        reason = active and startedReason or "traversal_starting:" .. action,
    }
    if effectOnly then pending[actor].effectVerified = effectDone(pending[actor]) end
    if effectOnly and action == "remove_glass" and pending[actor].effectVerified then
        pending[actor].phase, pending[actor].finishedAt = "completed", current
        pending[actor].reason = startedReason
    end
    return true, pending[actor].reason
end

function Traversal.window(actor, action, intent, provider)
    local object = intent.object
    if object == nil then return false, "window action has no object" end
    local existing, existingReason = existingRequest(actor, action, object)
    if existing ~= nil then return existing, existingReason end
    local handled, reason = useProvider(provider, "window", actor, action, object, intent)
    if handled ~= nil then return handled, reason end
    if not provider.directNative then return false, reason end
    if effectDone({ action = action, object = object }) then
        return true, action == "open_window" and "window_opened"
            or action == "smash_window" and "window_smashed" or "glass_removed"
    end
    if context.stopDirect(actor) ~= true then return false, "window action could not acquire stationary actor" end

    if action == "open_window" then
        local started, failure = invoke(actor, "openWindow", object)
        if not started or failure == false then return false, failure or "native window open rejected" end
        return retainRequest(actor, action, intent, "window_opened", true)
    elseif action == "smash_window" then
        local started, failure = invoke(actor, "smashWindow", object)
        if not started or failure == false then return false, failure or "native window smash rejected" end
        return retainRequest(actor, action, intent, "window_smashed", true)
    elseif action == "remove_glass" then
        local started, failure = invoke(object, "removeBrokenGlass")
        if not started then return false, failure end
        return retainRequest(actor, action, intent, "glass_removed", true)
    end

    local started, failure
    if intent.hoppableThumpable == true then
        -- The stock E action submits a hoppable IsoThumpable through the
        -- contextual ClimbThroughWindow entry point. That state owns its object
        -- geometry and animation offsets better than treating it as a low fence.
        started, failure = invoke(
            actor, "triggerContextualAction", "ClimbThroughWindow", object)
        if started and failure == false then
            return false, "contextual thumpable climb was rejected"
        end
    end
    if not started then
        local methodName = intent.emptyFrame == true
            and "climbThroughWindowFrame" or "climbThroughWindow"
        started, failure = invoke(actor, methodName, object)
    end
    if not started or failure == false then return false, failure or "native window climb rejected" end
    return retainRequest(actor, action, intent, "window_climb_started")
end

local function fenceDirection(intent)
    local name = string.lower(tostring(intent and intent.direction or ""))
    local key = ({ north = "N", south = "S", east = "E", west = "W" })[name]
    local directions = type(_G) == "table" and rawget(_G, "IsoDirections") or nil
    if key == nil or directions == nil then return nil end
    local ok, value = pcall(function() return directions[key] end)
    return ok and value or nil
end

function Traversal.fence(actor, action, intent, provider)
    local existing, existingReason = existingRequest(actor, action, intent.object)
    if existing ~= nil then return existing, existingReason end
    local direction = fenceDirection(intent)
    if direction == nil then return false, "fence direction is unavailable" end
    local handled, reason = useProvider(provider, "fence", actor, action,
        intent.object, direction, intent)
    if handled ~= nil then return handled, reason end
    if not provider.directNative then return false, reason end
    if context.stopDirect(actor) ~= true then
        return false, "fence climb could not acquire stationary actor"
    end

    local wallClimbOutcome
    if action == "climb_wall" then
        local checked, climbable = invoke(actor, "canClimbOverWall", direction)
        if not checked then return false, "native tall-wall climb check is unavailable" end
        if climbable ~= true then return false, "native tall wall is not climbable" end
        -- Native companions are intentionally non-local IsoPlayers. Their
        -- bridge entry grants only ClimbOverWallState.setParams() the temporary
        -- local context it needs to roll vanilla success/struggle/fail. Ordinary
        -- IsoPlayers and compatibility adapters retain the inherited fallback.
        local invoked, started = invoke(actor, "climbCompanionOverWall", direction)
        if not invoked then invoked, started = invoke(actor, "climbOverWall", direction) end
        if not invoked then return false, started or "native tall-wall climb failed" end
        if started == false then return false, "native tall-wall climb was rejected" end
        local successObserved, success = invoke(actor, "isClimbOverWallSuccess")
        local struggleObserved, struggle = invoke(actor, "isClimbOverWallStruggle")
        if successObserved and type(success) == "boolean"
            and struggleObserved and type(struggle) == "boolean" then
            wallClimbOutcome = success ~= true and "fail"
                or struggle == true and "struggle" or "success"
        end
    else
        if intent.objectlessFenceFallback == true then
            -- IsoGameCharacter.climbOverFence() validates objectless square
            -- affordances with isPlayerAbleToHopWallTo(). IsoPlayer:hopFence()
            -- checks only the low-fence HoppableN/HoppableW flags and rejects
            -- these otherwise valid edges. Mirror the engine's matching entry
            -- point and retain it under the same bounded startup verification.
            local invoked, failure = invoke(actor, "climbOverFence", direction)
            if not invoked or failure == false then
                return false, failure or "native objectless fence climb failed"
            end
            return retainRequest(actor, action, intent, "fence_climb_started")
        end
        -- IsoPlayer's context key does not call the inherited climb method
        -- directly. hopFence(test=true) validates the exact edge, then
        -- hopFence(test=false) submits the native state. Mirror that path when
        -- it is exposed, retaining the inherited method only for adapters.
        local tested, hoppable = invoke(actor, "hopFence", direction, true)
        if tested then
            if hoppable ~= true then return false, "native fence is not hoppable" end
            local invoked, started = invoke(actor, "hopFence", direction, false)
            if not invoked or started == false then
                return false, started or "native fence hop failed"
            end
        else
            local invoked, failure = invoke(actor, "climbOverFence", direction)
            if not invoked or failure == false then
                return false, failure or "native fence climb failed"
            end
        end
    end
    local retained, retainReason = retainRequest(actor, action, intent,
        action == "climb_wall" and "wall_climb_started" or "fence_climb_started")
    if retained and wallClimbOutcome and pending[actor] then
        pending[actor].wallClimbOutcome = wallClimbOutcome
    end
    return retained, retainReason
end

function Traversal.sheetRope(actor, action, intent, provider)
    local existing, existingReason = existingRequest(actor, action, intent.object)
    if existing ~= nil then return existing, existingReason end
    local down = action == "climb_down_sheet_rope"
    local handled, reason = useProvider(provider, "sheetRope", actor, action, down, intent)
    if handled ~= nil then return handled, reason end
    if not provider.directNative then return false, reason end
    if context.stopDirect(actor) ~= true then
        return false, "sheet-rope climb could not acquire stationary actor"
    end
    local squareOk, square = invoke(actor, "getCurrentSquare")
    if not squareOk or square == nil then return false, "actor square is unavailable" end
    local check = down and "canClimbDownSheetRope" or "canClimbSheetRope"
    local checked, climbable = invoke(actor, check, square)
    if not checked then return false, "native sheet-rope climb check is unavailable" end
    if climbable ~= true then return false, "native sheet rope is not climbable" end
    local methodName = down and "climbDownSheetRope" or "climbSheetRope"
    local invoked, failure = invoke(actor, methodName)
    if not invoked or failure == false then return false, failure or "native sheet-rope climb failed" end
    return retainRequest(actor, action, intent,
        down and "sheet_rope_descent_started" or "sheet_rope_climb_started")
end

function Traversal.setDowned(actor, downed, provider)
    local handled, reason = useProvider(provider, "setDowned", actor, downed)
    if handled ~= nil then return handled, reason end
    if not provider.directNative then return false, reason end
    if downed then context.stopDirect(actor) end
    local setOk, failure = invoke(actor, "setKnockedDown", downed)
    if not setOk then return false, failure end
    local checkOk, current = invoke(actor, "isKnockedDown")
    if not checkOk or current ~= downed then
        return false, "native downed state was not retained"
    end
    return true, downed and "downed" or "recovered"
end

return Traversal
