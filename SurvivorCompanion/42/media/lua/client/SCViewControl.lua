-- SPDX-License-Identifier: MIT

if type(require) == "function" then
    pcall(require, "SCNamespace")
    pcall(require, "SCCall")
end

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.ViewControl = SC.ViewControl or {}
local View = SC.ViewControl

local ZERO_EPSILON = 0.01
local MAX_FRAME_MS = 100
local state = View._state or {
    currentX = 0,
    currentY = 0,
    lastAt = nil,
    wroteOffset = false,
    keyWasHeld = false,
    reason = "idle",
    failure = nil,
    watchId = nil,
    watchActor = nil,
}
View._state = state

local function nowMs()
    if SC.GameplayUtil and type(SC.GameplayUtil.nowMs) == "function" then
        local ok, value = pcall(SC.GameplayUtil.nowMs)
        if ok and tonumber(value) then return tonumber(value) end
    end
    if type(getTimestampMs) == "function" then
        local ok, value = pcall(getTimestampMs)
        if ok and tonumber(value) then return tonumber(value) end
    end
    return 0
end

local function method(object, name, ...)
    if SC.Call and type(SC.Call.method) == "function" then
        return SC.Call.method(object, name, ...)
    end
    if object == nil or type(object[name]) ~= "function" then return false end
    return pcall(object[name], object, ...)
end

local function position(object, axis)
    local called, value = method(object, "get" .. axis)
    return called and tonumber(value) or nil
end

local function activePlayer()
    if type(getSpecificPlayer) == "function" then
        local ok, player = pcall(getSpecificPlayer, 0)
        if ok and player ~= nil then return player end
    end
    if type(getPlayer) == "function" then
        local ok, player = pcall(getPlayer)
        if ok then return player end
    end
    return nil
end

local function selectedActor()
    if SC.UI and type(SC.UI.selectedActor) == "function" then
        local ok, actor = pcall(SC.UI.selectedActor)
        if ok then return actor end
    end
    return nil
end

local function watchedActor()
    if state.watchId ~= nil and SC.Registry and type(SC.Registry.byId) == "function" then
        local ok, record = pcall(SC.Registry.byId, state.watchId)
        if not ok or type(record) ~= "table" or record.actor == nil
            or (type(record.runtime) == "table" and record.runtime.inactive == true) then
            return nil
        end
        if type(SC.Registry.isActive) == "function" then
            local activeOk, active = pcall(SC.Registry.isActive, record.actor, state.watchId)
            if not activeOk or active ~= true then return nil end
        end
        if SC.Actor and type(SC.Actor.isCompanion) == "function" then
            local companionOk, companion = pcall(SC.Actor.isCompanion, record.actor)
            if not companionOk or companion ~= true then return nil end
        end
        state.watchActor = record.actor
        return record.actor
    end
    if state.watchActor ~= nil and SC.Actor and type(SC.Actor.isCompanion) == "function" then
        local ok, active = pcall(SC.Actor.isCompanion, state.watchActor)
        if not ok or active ~= true then return nil end
    end
    return state.watchActor
end

local function configuredKey()
    if SC.UI and type(SC.UI.peekHotkey) == "function" then
        local ok, key = pcall(SC.UI.peekHotkey)
        if ok then
            key = tonumber(key)
            return key and key > 0 and key or nil
        end
    end
    return SC.UI and tonumber(SC.UI.DEFAULT_PEEK_HOTKEY) or nil
end

local function keyHeld()
    local key = configuredKey()
    if key == nil or type(isKeyDown) ~= "function" then return false end
    local ok, held = pcall(isKeyDown, key)
    return ok and held == true
end

local function showFailure(player, reason)
    local key = reason == "no_selection" and "UI_SC_Peek_NoSelection"
        or (reason == "other_floor" and "UI_SC_Peek_OtherFloor"
        or (reason == "too_far" and "UI_SC_Peek_TooFar" or nil))
    if key == nil then return end
    local text = type(getText) == "function" and getText(key) or key
    method(player, "setHaloNote", text)
end

local function targetOffset(player, actor)
    if player == nil then return nil, nil, "no_player" end
    if actor == nil then return nil, nil, "no_selection" end
    if actor == player then return nil, nil, "no_selection" end
    local deadCalled, dead = method(actor, "isDead")
    if deadCalled and dead == true then return nil, nil, "unavailable" end
    local px, py, pz = position(player, "X"), position(player, "Y"), position(player, "Z")
    local ax, ay, az = position(actor, "X"), position(actor, "Y"), position(actor, "Z")
    if px == nil or py == nil or pz == nil or ax == nil or ay == nil or az == nil then
        return nil, nil, "unavailable"
    end
    if math.abs(az - pz) > 0.1 then return nil, nil, "other_floor" end
    local dx, dy = ax - px, ay - py
    local distance = math.sqrt(dx * dx + dy * dy)
    local maximum = tonumber(SC.Config and SC.Config.get
        and SC.Config.get("viewPeekMaximumDistance")) or 16
    maximum = math.max(1, math.min(16, maximum))
    if distance > maximum then return nil, nil, "too_far" end
    return dx, dy, "active"
end

local function bridgeCall(name, ...)
    local bridge = type(_G) == "table" and rawget(_G, "SCBridge") or SCBridge
    if SC.Call == nil or type(SC.Call.static) ~= "function" then
        return false, "call adapter unavailable"
    end
    return SC.Call.static(bridge, name, ...)
end

local function writeOffset(x, y)
    local called, accepted = bridgeCall("setViewOffset", x, y)
    if not called or accepted ~= true then
        state.failure = tostring(called and accepted or accepted or "view bridge unavailable")
        state.reason = "bridge_failure"
        return false
    end
    state.failure = nil
    state.wroteOffset = true
    return true
end

local function clearOffset()
    if not state.wroteOffset then return true end
    local called, accepted = bridgeCall("clearViewOffset")
    if not called or accepted ~= true then
        state.failure = tostring(called and accepted or accepted or "view bridge unavailable")
        state.reason = "bridge_failure"
        return false
    end
    state.failure = nil
    state.wroteOffset = false
    return true
end

function View.update()
    local now = nowMs()
    local elapsed = state.lastAt == nil and 0 or math.max(0, math.min(MAX_FRAME_MS, now - state.lastAt))
    state.lastAt = now

    local held = keyHeld()
    local player = activePlayer()
    local targetX, targetY, reason = nil, nil, "released"
    local watching = state.watchId ~= nil or state.watchActor ~= nil
    if held then
        targetX, targetY, reason = targetOffset(player, selectedActor())
    elseif watching then
        targetX, targetY, reason = targetOffset(player, watchedActor())
        if reason ~= "active" then
            state.watchId, state.watchActor = nil, nil
            watching = false
            showFailure(player, reason)
        end
    end
    if held and not state.keyWasHeld and reason ~= "active" then showFailure(player, reason) end
    state.keyWasHeld = held

    targetX = targetX or 0
    targetY = targetY or 0
    local easeMs = tonumber(SC.Config and SC.Config.get and SC.Config.get("viewPeekEaseMs")) or 180
    easeMs = math.max(50, math.min(1000, easeMs))
    local alpha = elapsed <= 0 and 0 or 1 - math.exp(-elapsed / easeMs)
    state.currentX = state.currentX + (targetX - state.currentX) * alpha
    state.currentY = state.currentY + (targetY - state.currentY) * alpha

    local returning = targetX == 0 and targetY == 0
    if returning and math.abs(state.currentX) <= ZERO_EPSILON
        and math.abs(state.currentY) <= ZERO_EPSILON then
        state.currentX, state.currentY = 0, 0
        if clearOffset() then state.reason = held and reason or "idle" end
        return true
    end
    if writeOffset(state.currentX, state.currentY) then
        state.reason = returning and (held and reason or "returning") or "active"
        return true
    end
    return false, state.failure
end

function View.watch(companionId, actor)
    if type(companionId) ~= "string" then
        actor, companionId = companionId, nil
    end
    if actor == nil and companionId ~= nil and SC.Registry
        and type(SC.Registry.byId) == "function" then
        local ok, record = pcall(SC.Registry.byId, companionId)
        if ok and type(record) == "table" then actor = record.actor end
    end
    if actor == nil then return false, "no_selection" end
    if SC.Actor and type(SC.Actor.isCompanion) == "function" then
        local ok, valid = pcall(SC.Actor.isCompanion, actor)
        if not ok or valid ~= true then return false, "invalid_companion" end
    end
    local player = activePlayer()
    local _, _, reason = targetOffset(player, actor)
    if reason ~= "active" then
        showFailure(player, reason)
        return false, reason
    end
    state.watchId = companionId
    state.watchActor = actor
    state.reason = "watching"
    return true, "watching"
end

function View.stopWatching()
    local active = state.watchId ~= nil or state.watchActor ~= nil
    state.watchId, state.watchActor = nil, nil
    if active then state.reason = "returning" end
    return active, active and "watch_stopped" or "not_watching"
end

function View.status()
    return {
        active = state.reason == "active",
        returning = state.reason == "returning",
        reason = state.reason,
        failure = state.failure,
        x = state.currentX,
        y = state.currentY,
        watching = state.watchId ~= nil or state.watchActor ~= nil,
        watchId = state.watchId,
        watchActor = state.watchActor,
    }
end

function View.reset()
    clearOffset()
    state.currentX, state.currentY = 0, 0
    state.lastAt = nil
    state.wroteOffset = false
    state.keyWasHeld = false
    state.reason = "idle"
    state.failure = nil
    state.watchId = nil
    state.watchActor = nil
    return true
end

return View
