-- SPDX-License-Identifier: MIT

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion

SC.NativeVisualActions = SC.NativeVisualActions or {}
local Visual = SC.NativeVisualActions
local context

function Visual.configure(value)
    assert(type(value) == "table", "native visual context is required")
    context = value
    return Visual
end

local function invoke(object, name, ...)
    return context.invoke(object, name, ...)
end

function Visual.handSignal(actor, intent, provider)
    local requestedEmote = intent.emote or "freeze"
    local emote = context.emoteAliases[requestedEmote] or requestedEmote
    if context.humanEmotes[requestedEmote] ~= true then return false, "unsupported human emote" end
    local handled, reason = context.useProvider(provider, "emote", actor, emote, intent)
    if handled ~= nil then return handled, reason end
    if not provider.directNative then return false, reason end
    local lowered, lowerReason = context.setWeaponReady(actor, false)
    if not lowered then return false, lowerReason end
    local played, failure = invoke(actor, "playEmote", emote)
    if not played then return false, failure end
    return true, "hand_signal_started"
end

function Visual.roomSweep(actor, intent, provider)
    local handled, reason = context.useProvider(provider, "look", actor, intent)
    if handled ~= nil then return handled, reason end
    if not provider.directNative then return false, reason end

    local ready, readyReason = context.setWeaponReady(actor, intent.weaponReady == true,
        intent.targetSquare)
    if not ready then return false, readyReason end

    local x, y = context.position(actor)
    if x == nil then return false, "actor position is unavailable for room sweep" end
    local forwardX, forwardY = tonumber(intent.sweepForwardX), tonumber(intent.sweepForwardY)
    local forwardXOk, forwardYOk = context.finite(forwardX), context.finite(forwardY)
    if not forwardXOk or not forwardYOk then
        forwardXOk, forwardX = invoke(actor, "getForwardDirectionX")
        forwardYOk, forwardY = invoke(actor, "getForwardDirectionY")
    end
    if not forwardXOk or not forwardYOk or not context.finite(forwardX)
        or not context.finite(forwardY)
        or (forwardX * forwardX + forwardY * forwardY) < 0.000001 then
        forwardX, forwardY = 1, 0
    end
    local side = intent.sweepSide == "right" and -1 or 1
    local lookX, lookY = -forwardY * side, forwardX * side
    local requested, turningRequested = invoke(
        actor, "faceLocationF", x + lookX * 2, y + lookY * 2)
    if not requested or turningRequested ~= true then
        return false, "native room-check facing request was rejected"
    end

    local turningOk, turning = invoke(actor, "isTurning")
    local afterXOk, afterX = invoke(actor, "getForwardDirectionX")
    local afterYOk, afterY = invoke(actor, "getForwardDirectionY")
    local facing = afterXOk and afterYOk and context.finite(afterX)
        and context.finite(afterY) and (afterX * lookX + afterY * lookY) >= 0.75
    if (not turningOk or turning ~= true) and not facing then
        return false, "native room-check facing did not start"
    end
    return true, "room_sweep_facing_started"
end

function Visual.faceTarget(actor, intent, provider, successReason)
    local handled, reason = context.useProvider(provider, "look", actor, intent)
    if handled ~= nil then return handled, reason end
    if not provider.directNative then return false, reason end
    local target = intent.targetPosition or intent.targetSquare or intent
    local x, y = context.position(target)
    if x == nil then return false, "alert facing target is unavailable" end
    if context.centerTargetOnTile(
        intent, intent.targetSquare ~= nil and intent.targetPosition == nil) then
        x, y = x + 0.5, y + 0.5
    end
    if intent.weaponReady ~= nil then
        local ready, readyReason = context.setWeaponReady(
            actor, intent.weaponReady == true, target)
        if not ready then return false, readyReason end
    end
    local requested, turningRequested = invoke(actor, "faceLocationF", x, y)
    if not requested or turningRequested ~= true then
        return false, "native alert facing request was rejected"
    end
    local actorX, actorY = context.position(actor)
    if actorX == nil then return false, "actor position is unavailable for alert facing" end
    local forwardXOk, forwardX = invoke(actor, "getForwardDirectionX")
    local forwardYOk, forwardY = invoke(actor, "getForwardDirectionY")
    local dx, dy = x - actorX, y - actorY
    local length = math.sqrt(dx * dx + dy * dy)
    local facing = length <= 0.001 or (forwardXOk and forwardYOk
        and context.finite(forwardX) and context.finite(forwardY)
        and (forwardX * dx + forwardY * dy) / length >= 0.75)
    local turningOk, turning = invoke(actor, "isTurning")
    if (not turningOk or turning ~= true) and not facing then
        return false, "native alert facing did not start"
    end
    return true, successReason or "facing_started"
end

function Visual.syncPlayerPosture(actor, intent)
    local sneaking = intent.sneaking == true
    local stopped = context.stopDirect(actor, { preservePosture = true })
    if stopped ~= true then return false, "copy_posture_stop_rejected" end
    local checked, actual = invoke(actor, "isSneaking")
    if not checked or actual ~= sneaking then
        local setOk, setResult = invoke(actor, "setSneaking", sneaking)
        if not setOk or setResult == false then return false, "copy_posture_rejected" end
        checked, actual = invoke(actor, "isSneaking")
    end
    if checked and actual ~= sneaking then return false, "copy_posture_not_verified" end
    return true, sneaking and "copy_posture_crouched" or "copy_posture_standing"
end

function Visual.conversationPose(actor, intent, provider)
    local faced, facingReason = Visual.faceTarget(
        actor, intent, provider, "conversation_facing_started")
    if not faced then return false, facingReason end
    if type(intent.emote) ~= "string" or intent.emote == "" then return true, facingReason end
    local gestured, gestureReason = Visual.handSignal(actor, intent, provider)
    if not gestured then return false, gestureReason end
    return true, "conversation_pose_started"
end

return Visual
