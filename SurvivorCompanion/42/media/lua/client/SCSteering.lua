-- SPDX-License-Identifier: MIT

if type(require) == "function" then
    pcall(require, "SCNamespace")
    pcall(require, "SCCall")
end

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.Steering = SC.Steering or {}
local Steering = SC.Steering

local session = Steering._session
local nextUpdateAt = Steering._nextUpdateAt or -math.huge
local keyWasHeld = Steering._keyWasHeld or false
local busyNotified = Steering._busyNotified or false
local reason = Steering._reason or "idle"

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

local function selectedActor()
    if SC.UI and type(SC.UI.selectedActor) == "function" then
        local ok, actor = pcall(SC.UI.selectedActor)
        if ok and actor ~= nil and SC.Actor and type(SC.Actor.isCompanion) == "function" then
            local validOk, valid = pcall(SC.Actor.isCompanion, actor)
            if validOk and valid == true then return actor end
        end
    end
    return nil
end

local function configuredKey()
    if SC.UI and type(SC.UI.steerHotkey) == "function" then
        local ok, key = pcall(SC.UI.steerHotkey)
        if ok and tonumber(key) and tonumber(key) > 0 then return tonumber(key) end
    end
    return SC.UI and tonumber(SC.UI.DEFAULT_STEER_HOTKEY) or nil
end

local function keyHeld()
    local key = configuredKey()
    if key == nil or type(isKeyDown) ~= "function" then return false end
    local ok, held = pcall(isKeyDown, key)
    return ok and held == true
end

local function showFailure(code)
    local keys = {
        no_selection = "UI_SC_Steer_NoSelection",
        cursor_unavailable = "UI_SC_Steer_NoCursor",
        actor_busy = "UI_SC_Steer_Busy",
    }
    local key = keys[code]
    if key == nil then return end
    local player
    if type(getSpecificPlayer) == "function" then
        local ok, value = pcall(getSpecificPlayer, 0)
        if ok then player = value end
    end
    if player == nil and type(getPlayer) == "function" then
        local ok, value = pcall(getPlayer)
        if ok then player = value end
    end
    local text = type(getText) == "function" and getText(key) or key
    method(player, "setHaloNote", text)
end

local function finite(value)
    value = tonumber(value)
    return value ~= nil and value == value and value ~= math.huge and value ~= -math.huge
end

local function actorPosition(actor)
    local xOk, x = method(actor, "getX")
    local yOk, y = method(actor, "getY")
    local zOk, z = method(actor, "getZ")
    if xOk and yOk and zOk and finite(x) and finite(y) and finite(z) then
        return tonumber(x), tonumber(y), tonumber(z)
    end
    return nil
end

local function cursorTarget(actor)
    if type(getMouseX) ~= "function" or type(getMouseY) ~= "function"
        or type(screenToIsoX) ~= "function" or type(screenToIsoY) ~= "function" then
        return nil, "cursor_unavailable"
    end
    local ax, ay, az = actorPosition(actor)
    if ax == nil then return nil, "actor_unavailable" end
    local mouseOkX, mouseX = pcall(getMouseX)
    local mouseOkY, mouseY = pcall(getMouseY)
    if not mouseOkX or not mouseOkY then return nil, "cursor_unavailable" end
    local xOk, worldX = pcall(screenToIsoX, 0, mouseX, mouseY, az)
    local yOk, worldY = pcall(screenToIsoY, 0, mouseX, mouseY, az)
    if not xOk or not yOk or not finite(worldX) or not finite(worldY) then
        return nil, "cursor_unavailable"
    end
    local cell
    if type(getCell) == "function" then
        local cellOk, value = pcall(getCell)
        if cellOk then cell = value end
    end
    local squareOk, square = method(cell, "getGridSquare",
        math.floor(worldX), math.floor(worldY), math.floor(az))
    if not squareOk or square == nil then return nil, "cursor_unavailable" end
    return {
        x = tonumber(worldX), y = tonumber(worldY), z = az,
        dx = tonumber(worldX) - ax, dy = tonumber(worldY) - ay,
        square = square,
    }
end

local function stopActor(actor)
    if SC.Actor and type(SC.Actor.stop) == "function" then
        local ok, stopped = pcall(SC.Actor.stop, actor)
        return ok and stopped == true
    end
    return false
end

local function onCancelled(actor)
    stopActor(actor)
    return true, "steering_stopped"
end

local function release(code)
    local current = session
    session = nil
    Steering._session = nil
    nextUpdateAt = -math.huge
    Steering._nextUpdateAt = nextUpdateAt
    reason = code or "idle"
    Steering._reason = reason
    if current == nil then return true end
    local supervisor = SC.ActionSupervisor
    if supervisor and type(supervisor.isCurrent) == "function"
        and supervisor.isCurrent(current.token) then
        local cancelled, cancelReason = supervisor.cancel(
            current.actor, code or "steer_released", nil, false)
        return cancelled == true, cancelReason
    end
    return true, "ownership_already_released"
end

local function acquire(actor)
    local supervisor = SC.ActionSupervisor
    if type(supervisor) ~= "table" or type(supervisor.begin) ~= "function" then
        return nil, "supervisor_unavailable"
    end
    local token, acquireReason = supervisor.begin(actor, {
        owner = "player_control",
        action = "steer",
        priority = supervisor.Priority and supervisor.Priority.PLAYER or 400,
        phase = "approaching",
        targetKey = "cursor",
        targetLabel = "player cursor",
        ignoreRetry = true,
        interruptible = true,
        deadlines = { approaching = 0 },
        allowedActions = { steer = true },
        allowedMovementPhases = { approaching = true },
        onCancel = onCancelled,
        metadata = { source = "hold_key" },
    })
    if token == nil then return nil, acquireReason or "actor_busy" end
    session = { actor = actor, token = token }
    Steering._session = session
    return session, acquireReason
end

local function drive(current, target)
    if SC.Actor == nil or type(SC.Actor.setMovement) ~= "function" then
        return false, "actor_movement_unavailable"
    end
    local called, accepted, movementReason = pcall(SC.Actor.setMovement,
        current.actor, "walk", {
        action = "steer",
        dx = target.dx,
        dy = target.dy,
        targetPosition = { x = target.x, y = target.y, z = target.z },
        targetSquare = target.square,
        movementTarget = true,
        movementArrivalTolerance = tonumber(SC.Config and SC.Config.get
            and SC.Config.get("steeringArrivalDistance")) or 0.25,
        movementTargetTtlMs = tonumber(SC.Config and SC.Config.get
            and SC.Config.get("steeringTargetTtlMs")) or 250,
        continuousSteering = true,
        supervisorToken = current.token,
    })
    if not called then return false, tostring(accepted) end
    local supervisor = SC.ActionSupervisor
    if accepted == true and supervisor and type(supervisor.progress) == "function" then
        supervisor.progress(current.token,
            string.format("cursor:%d,%d", math.floor(target.x), math.floor(target.y)), {
                x = target.x, y = target.y,
            })
    end
    return accepted == true, movementReason
end

function Steering.update()
    local held = keyHeld()
    local actor = held and selectedActor() or nil
    if not held then
        keyWasHeld = false
        busyNotified = false
        Steering._keyWasHeld = false
        Steering._busyNotified = false
        if session ~= nil then return release("steer_key_released") end
        reason = "idle"
        Steering._reason = reason
        return true
    end

    if actor == nil then
        if not keyWasHeld then showFailure("no_selection") end
        keyWasHeld = true
        Steering._keyWasHeld = true
        if session ~= nil then release("steer_selection_lost") end
        reason = "no_selection"
        Steering._reason = reason
        return false, reason
    end
    keyWasHeld = true
    Steering._keyWasHeld = true

    local supervisor = SC.ActionSupervisor
    if session ~= nil and (session.actor ~= actor
        or type(supervisor) ~= "table" or type(supervisor.isCurrent) ~= "function"
        or supervisor.isCurrent(session.token) ~= true) then
        local changed = session.actor ~= actor
        release(changed and "steer_selection_changed" or "steer_ownership_lost")
    end
    if session == nil then
        local acquired, acquireReason = acquire(actor)
        if acquired == nil then
            reason = "actor_busy"
            Steering._reason = reason
            if not busyNotified then
                showFailure("actor_busy")
                busyNotified = true
                Steering._busyNotified = true
            end
            return false, acquireReason
        end
        busyNotified = false
        Steering._busyNotified = false
    end

    local now = nowMs()
    if now < nextUpdateAt then return true, "steering_held" end
    local interval = tonumber(SC.Config and SC.Config.get
        and SC.Config.get("steeringUpdateIntervalMs")) or 80
    nextUpdateAt = now + math.max(25, math.min(250, interval))
    Steering._nextUpdateAt = nextUpdateAt
    local target, targetReason = cursorTarget(session.actor)
    if target == nil then
        showFailure("cursor_unavailable")
        release("cursor_unavailable")
        return false, targetReason
    end
    local accepted, movementReason = drive(session, target)
    reason = accepted and "active" or tostring(movementReason or "movement_rejected")
    Steering._reason = reason
    return accepted, movementReason
end

function Steering.status()
    return {
        active = session ~= nil and reason == "active",
        held = keyWasHeld,
        reason = reason,
        actor = session and session.actor or nil,
        token = session and session.token or nil,
    }
end

function Steering.reset()
    release("steering_reset")
    session = nil
    keyWasHeld = false
    busyNotified = false
    nextUpdateAt = -math.huge
    reason = "idle"
    Steering._session = nil
    Steering._keyWasHeld = false
    Steering._busyNotified = false
    Steering._nextUpdateAt = nextUpdateAt
    Steering._reason = reason
    return true
end

return Steering
