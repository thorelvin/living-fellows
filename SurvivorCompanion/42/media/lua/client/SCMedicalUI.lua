-- SPDX-License-Identifier: MIT
-- A native companion can be treated by the vanilla other-player health panel,
-- but cannot answer the consent request used for two human players. Own the
-- short-lived movement hold while the local player checks or treats them.
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.MedicalUI = SC.MedicalUI or {}
local MedicalUI = SC.MedicalUI

-- The native panel blocks treatment past two tiles, so leave a little margin.
MedicalUI.RANGE = 1.9
MedicalUI.CHECK_TIMEOUT_MS = 20000

local session

local function call(object, method, ...)
    if not object then return nil end
    local ok, value = pcall(function(...) return object[method](object, ...) end, ...)
    return ok and value or nil
end

local function nowMs()
    if type(getTimestampMs) == "function" then
        local ok, value = pcall(getTimestampMs)
        if ok and tonumber(value) then return tonumber(value) end
    end
    return math.floor((os.clock and os.clock() or 0) * 1000)
end

local function isManagedCompanion(actor)
    if not actor or not SC.Actor or type(SC.Actor.isCompanion) ~= "function"
        or not SC.Registry then return false end
    local ok, companion = pcall(SC.Actor.isCompanion, actor)
    if not ok or companion ~= true then return false end
    local id = type(SC.Registry.idOf) == "function"
        and select(2, pcall(SC.Registry.idOf, actor)) or nil
    local record = id and type(SC.Registry.byId) == "function"
        and select(2, pcall(SC.Registry.byId, id)) or nil
    return type(record) == "table" and record.actor == actor
end

local function nearDoctor(actor, doctor)
    local actorSquare, doctorSquare = call(actor, "getSquare"), call(doctor, "getSquare")
    if not actorSquare or not doctorSquare
        or tonumber(call(actorSquare, "getZ")) ~= tonumber(call(doctorSquare, "getZ")) then
        return false
    end
    local distance = tonumber(call(doctor, "DistTo", actor))
    return distance ~= nil and distance <= MedicalUI.RANGE
end

function MedicalUI.availability(actor, doctor)
    if not isManagedCompanion(actor) or call(actor, "isDead") == true then
        return false, "UI_SC_Disabled_InvalidActor"
    end
    if not doctor then return false, "UI_SC_Disabled_NoPlayer" end
    if not nearDoctor(actor, doctor) then
        return false, "UI_SC_Disabled_TooFar", MedicalUI.RANGE
    end
    return true
end

local function healthWindow(actor)
    if not ISMedicalCheckAction then return nil end
    if type(ISMedicalCheckAction.getHealthWindowForPlayer) == "function" then
        local ok, window = pcall(ISMedicalCheckAction.getHealthWindowForPlayer, actor)
        return ok and window or nil
    end
    return ISMedicalCheckAction.HealthWindows
        and ISMedicalCheckAction.HealthWindows[actor] or nil
end

local function visible(window)
    if not window then return false end
    local value = call(window, "getIsVisible")
    if value == nil then value = call(window, "isVisible") end
    return value == true
end

local function hasNearbyZombie(state)
    if not SC.GameplayUtil or type(SC.GameplayUtil.squareMovingObjects) ~= "function"
        or type(SC.GameplayUtil.isZombie) ~= "function" or type(getCell) ~= "function" then
        return false
    end
    local cell = getCell()
    if not cell then return false end
    local actor = state.actor
    local x, y, z = tonumber(call(actor, "getX")), tonumber(call(actor, "getY")),
        tonumber(call(actor, "getZ"))
    if not x or not y or not z then return false end
    x, y, z = math.floor(x), math.floor(y), math.floor(z)
    for dx = -2, 2 do
        for dy = -2, 2 do
            local square = call(cell, "getGridSquare", x + dx, y + dy, z)
            local found = false
            pcall(SC.GameplayUtil.squareMovingObjects, square, function(value)
                if SC.GameplayUtil.isZombie(value)
                    and call(value, "isDead") ~= true then
                    local zx, zy = tonumber(call(value, "getX")),
                        tonumber(call(value, "getY"))
                    if zx and zy and (zx - x) * (zx - x) + (zy - y) * (zy - y) <= 4 then
                        found = true
                        return false
                    end
                end
            end, 12)
            if found then return true end
        end
    end
    return false
end

function MedicalUI.close(reason)
    local state = session
    if not state then return true, "not_open" end
    session = nil
    local window = healthWindow(state.actor)
    if window and visible(window) and state.phase == "open" then
        call(window, "removeFromUIManager")
        if window.nested then call(window.nested, "tryStopReceivingBodyDamageUpdates") end
    end
    if state.phase == "checking" and ISTimedActionQueue
        and type(ISTimedActionQueue.hasAction) == "function"
        and ISTimedActionQueue.hasAction(state.action) then
        call(state.action, "forceCancel")
    end
    if state.ownsStay and SC.Commands
        and type(SC.Commands.endTemporaryStay) == "function" then
        pcall(SC.Commands.endTemporaryStay, state.actor, state.stayToken)
    end
    return true, reason or "closed"
end

function MedicalUI.maintain()
    local state = session
    if not state then return end
    local actor, doctor = state.actor, state.doctor
    if not isManagedCompanion(actor) or call(actor, "isDead") == true
        or call(doctor, "isDead") == true or not nearDoctor(actor, doctor)
        or (SC.Commands and type(SC.Commands.isTemporaryStay) == "function"
            and SC.Commands.isTemporaryStay(actor) ~= true) then
        MedicalUI.close("interrupted")
        return
    end
    local now = nowMs()
    if now - (state.lastThreatCheckAt or 0) > 350 then
        state.lastThreatCheckAt = now
        if hasNearbyZombie(state) then
            MedicalUI.close("threat")
            return
        end
    end
    local window = healthWindow(actor)
    if window and visible(window) and window.nested
        and window.nested.character == actor
        and window.nested.otherPlayer == doctor then
        state.phase = "open"
        state.window = window
    elseif state.phase == "open" then
        MedicalUI.close("window_closed")
    elseif now - state.startedAt > MedicalUI.CHECK_TIMEOUT_MS
        or (now - state.startedAt > 1000 and ISTimedActionQueue
            and type(ISTimedActionQueue.hasAction) == "function"
            and not ISTimedActionQueue.hasAction(state.action)) then
        MedicalUI.close("check_interrupted")
    end
end

function MedicalUI.open(actor, doctor)
    local available, reason, argument = MedicalUI.availability(actor, doctor)
    if not available then return false, reason, argument end
    if type(require) == "function" then
        if not ISHealthPanel then pcall(require, "XpSystem/ISUI/ISHealthPanel") end
        if not ISMedicalCheckAction then
            pcall(require, "TimedActions/ISMedicalCheckAction")
        end
        if not ISTimedActionQueue then
            pcall(require, "TimedActions/ISTimedActionQueue")
        end
    end
    if not ISMedicalCheckAction or type(ISMedicalCheckAction.new) ~= "function"
        or not ISTimedActionQueue or type(ISTimedActionQueue.add) ~= "function"
        or not SC.Commands or type(SC.Commands.beginTemporaryStay) ~= "function" then
        return false, "UI_SC_Disabled_HealthUnavailable"
    end
    if session and session.actor == actor and session.doctor == doctor then
        MedicalUI.maintain()
        if session then return true, "health_opened" end
    end
    MedicalUI.close("replaced")
    -- The borrowed loot pane has its own stay token. Put it back before taking
    -- medical ownership so closing that pane cannot release the patient early.
    if SC.UI and type(SC.UI.restoreInventory) == "function" then
        SC.UI.restoreInventory()
    end
    local okStay, token, reason = pcall(SC.Commands.beginTemporaryStay,
        actor, "companion_medical_check")
    if not okStay or type(token) ~= "table" or reason == "already_held" then
        return false, "UI_SC_Disabled_HealthUnavailable"
    end
    local okAction, action = pcall(ISMedicalCheckAction.new,
        ISMedicalCheckAction, doctor, actor)
    if not okAction or not action then
        SC.Commands.endTemporaryStay(actor, token)
        return false, "UI_SC_Disabled_HealthUnavailable"
    end
    session = { actor = actor, doctor = doctor, stayToken = token,
        ownsStay = true, action = action, startedAt = nowMs(),
        lastThreatCheckAt = 0, phase = "checking" }
    local okQueued, queued = pcall(ISTimedActionQueue.add, action)
    if not okQueued or queued == nil then
        MedicalUI.close("queue_failed")
        return false, "UI_SC_Disabled_HealthUnavailable"
    end
    return true, "health_opened"
end

function MedicalUI.current()
    return session
end

return MedicalUI
