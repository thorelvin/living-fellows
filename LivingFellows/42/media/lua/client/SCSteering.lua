-- SPDX-License-Identifier: MIT

if type(require) == "function" then
    pcall(require, "SCNamespace")
    pcall(require, "SCCall")
end

LivingFellows = LivingFellows or {}
local SC = LivingFellows
SC.Steering = SC.Steering or {}
local Steering = SC.Steering

local session = Steering._session
local nextUpdateAt = Steering._nextUpdateAt or -math.huge
local keyWasHeld = Steering._keyWasHeld or false
local busyNotified = Steering._busyNotified or false
local cursorNotified = Steering._cursorNotified or false
local reason = Steering._reason or "idle"
local releaseRetryAt = Steering._releaseRetryAt or -math.huge

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
        if not ok then return nil end
        key = tonumber(key)
        return key and key > 0 and key or nil
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

local function gridSquare(cell, x, y, z)
    local okay, square = method(cell, "getGridSquare", x, y, z)
    if okay then return square end
end

local function solidFloor(square)
    local okay, solid = method(square, "TreatAsSolidFloor")
    return okay and solid == true
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
    if cell == nil then return nil, "cursor_unavailable" end
    return {
        x = tonumber(worldX), y = tonumber(worldY), z = az,
        dx = tonumber(worldX) - ax, dy = tonumber(worldY) - ay, cell = cell,
        square = gridSquare(cell, math.floor(worldX), math.floor(worldY), math.floor(az)),
    }
end

-- The polygon map blocks leaving a native top tread on its own floor.
-- Only a cursor aimed past that tread's uphill edge may select the adjoining
-- upper landing. A cursor over an arbitrary floor cannot request a crossing.
local function uphill(square)
    local north, topNorth = method(square, "HasStairTopNorth")
    if north and topNorth == true then return 0, -1 end
    local west, topWest = method(square, "HasStairTopWest")
    if west and topWest == true then return -1, 0 end
end

local function stairLanding(target)
    local x = math.floor(target.x - target.dx)
    local y = math.floor(target.y - target.dy)
    local z = math.floor(target.z)
    local tread = gridSquare(target.cell, x, y, z)
    local dx, dy = uphill(tread)
    if dx == nil and target.z - z < 0.05 and not solidFloor(tread) then
        -- The actor can already be at upper height over the open stair mouth.
        -- In that case the real top tread is still directly beneath it.
        z = z - 1
        dx, dy = uphill(gridSquare(target.cell, x, y, z))
    end
    if dx == nil then return nil end
    local forward = target.dx * dx + target.dy * dy
    local sideways = math.abs(target.dx * dy - target.dy * dx)
    if forward > sideways and (target.x - x) * dx + (target.y - y) * dy > 0 then
        return { x = x + dx, y = y + dy, z = z + 1, dx = dx, dy = dy, cell = target.cell }
    end
end

local function freeFloor(actor, cell, x, y, z)
    local square = gridSquare(cell, x, y, z)
    local utility = SC.GameplayUtil
    if solidFloor(square) and utility and utility.isSquareFree(square)
        and not utility.movingBlocker(square, actor) and not utility.safehouseBlocker(square, actor) then
        return square
    end
end

local function freeLanding(actor, landing)
    local treadX, treadY = landing.x - landing.dx, landing.y - landing.dy
    local x, y, z = actorPosition(actor)
    if x == nil or z < landing.z - 1 or z > landing.z + 0.05 then return nil end
    local treadZ = landing.z - 1
    local top = gridSquare(landing.cell, treadX, treadY, treadZ)
    local dx, dy = uphill(top)
    if dx ~= landing.dx or dy ~= landing.dy then return nil end
    x, y = math.floor(x), math.floor(y)
    local offset = (x - treadX) * dx + (y - treadY) * dy
    if offset < -3 or offset > 1 or (x - treadX) * dy ~= (y - treadY) * dx then return nil end
    -- A native route from a partial stair height can back onto the lower
    -- approach before starting up. Verify each tread between us and the top.
    for step = 1, math.min(-offset, 2) do
        local lowerX, lowerY = treadX - dx * step, treadY - dy * step
        local lower = gridSquare(landing.cell, lowerX, lowerY, treadZ)
        local matched, same = method(top, "isSameStaircase", lowerX, lowerY, treadZ)
        local aligned, hasStairs = method(lower, dx == 0 and "HasStairsNorth" or "HasStairsWest")
        if not matched or same ~= true or not aligned or hasStairs ~= true then return nil end
    end
    if offset == -3 and (math.floor(z) ~= treadZ
        or not freeFloor(actor, landing.cell, x, y, treadZ)) then
        return nil
    end
    return freeFloor(actor, landing.cell, landing.x, landing.y, landing.z)
end

local function reachedLanding(actor, landing)
    local x, y, z = actorPosition(actor)
    return x ~= nil and math.floor(z) == landing.z and z - landing.z <= 0.05
        and (x - landing.x - 0.5)^2 + (y - landing.y - 0.5)^2 <= 0.35^2
end

local function aimsDownhill(target, landing)
    if not target or not target.square then return false end
    local downhill = -target.dx * landing.dx - target.dy * landing.dy
    local sideways = math.abs(target.dx * landing.dy - target.dy * landing.dx)
    return downhill > 0.35 and downhill > sideways
end

local function stopActor(actor)
    if SC.Actor and type(SC.Actor.stop) == "function" then
        local ok, stopped = pcall(SC.Actor.stop, actor)
        if not ok then return false, tostring(stopped) end
        return stopped == true, stopped == true and "steering_stopped"
            or "steering_stop_rejected"
    end
    return false, "actor_stop_unavailable"
end

local function clearLanding(active)
    local stopped, why = stopActor(active.actor)
    if stopped then active.landing = nil end
    return stopped, why
end

local function onCancelled(actor)
    return stopActor(actor)
end

local function release(code, preserveDeadline)
    local current = session
    local releaseReason = "ownership_already_released"
    reason = code or "idle"
    Steering._reason = reason
    if current == nil then return true end
    local supervisor = SC.ActionSupervisor
    if supervisor and type(supervisor.isCurrent) == "function"
        and supervisor.isCurrent(current.token) then
        if nowMs() < releaseRetryAt then return false, "steering_release_pending" end
        local cancelled, cancelReason = supervisor.cancel(
            current.actor, code or "steer_released", nil, false)
        if cancelled ~= true then
            releaseRetryAt = nowMs() + math.max(25, tonumber(SC.Config and SC.Config.get
                and SC.Config.get("steeringCancelRetryMs")) or 100)
            Steering._releaseRetryAt = releaseRetryAt
            reason = cancelReason or "steering_release_pending"
            Steering._reason = reason
            return false, reason
        end
        releaseReason = cancelReason or "steering_released"
    end
    if session == current then
        session = nil
        Steering._session = nil
    end
    releaseRetryAt = -math.huge
    Steering._releaseRetryAt = releaseRetryAt
    if preserveDeadline ~= true then
        nextUpdateAt = -math.huge
        Steering._nextUpdateAt = nextUpdateAt
    end
    return true, releaseReason
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
    if token == nil then
        if supervisor.containsDeferredStatus
            and supervisor.containsDeferredStatus(acquireReason) then
            -- Urgent survival work was dispatched for this actor during begin(); the
    -- companion is committed to it this cycle.  That is the urgent succeeding,
    -- not this action failing, so report a deferral the decision layer can
    -- recognise instead of a refusal that would cool the target down.
            return nil, "deferred:" .. tostring(acquireReason)
        end
        return nil, acquireReason or "actor_busy"
    end
    session = { actor = actor, token = token }
    Steering._session = session
    return session, acquireReason
end

local function drive(current, target, landingSquare)
    if SC.Actor == nil or type(SC.Actor.setMovement) ~= "function" then
        return false, "actor_movement_unavailable"
    end
    local intent
    if landingSquare then
        intent = { action = "steer", targetSquare = landingSquare, enginePath = true,
            supervisorToken = current.token }
    else
        intent = {
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
        }
    end
    local called, accepted, movementReason = pcall(SC.Actor.setMovement,
        current.actor, "walk", intent)
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

local function driveLanding(active, landing, current)
    local square = freeLanding(active.actor, landing)
    if not square or current >= (landing.expires or math.huge) then
        local failure = square and "steer_stair_landing_timed_out" or "steer_stair_landing_blocked"
        local stopped, why = clearLanding(active)
        reason = stopped and failure or why
        Steering._reason = reason
        return false, reason
    end
    landing.expires = landing.expires or current + 8000
    active.landing = landing
    local accepted, why = drive(active, landing, square)
    reason = accepted and "active" or tostring(why or "movement_rejected")
    Steering._reason = reason
    return accepted, why
end

function Steering.update()
    local held = keyHeld()
    local actor = held and selectedActor() or nil
    if not held then
        keyWasHeld = false
        busyNotified = false
        cursorNotified = false
        Steering._keyWasHeld = false
        Steering._busyNotified = false
        Steering._cursorNotified = false
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
        local released, releaseReason = release(
            changed and "steer_selection_changed" or "steer_ownership_lost")
        if released ~= true then return false, releaseReason end
    end
    local current = nowMs()
    if current < nextUpdateAt then return session ~= nil, session and "steering_held" or reason end
    local interval = tonumber(SC.Config and SC.Config.get
        and SC.Config.get("steeringUpdateIntervalMs")) or 80
    nextUpdateAt = current + math.max(25, math.min(250, interval))
    Steering._nextUpdateAt = nextUpdateAt
    local target, targetReason = cursorTarget(actor)
    if session and session.landing then
        if reachedLanding(actor, session.landing) then
            session.landing = nil
        elseif aimsDownhill(target, session.landing) then
            local stopped, why = clearLanding(session)
            if not stopped then
                reason, Steering._reason = why, why
                return false, why
            end
        else
            return driveLanding(session, session.landing, current)
        end
    end
    local landing = target and stairLanding(target)
    if target == nil or not target.square and not landing then
        if not cursorNotified then showFailure("cursor_unavailable") end
        cursorNotified = true
        Steering._cursorNotified = true
        if session ~= nil then release("cursor_unavailable", true) end
        reason = "cursor_unavailable"
        Steering._reason = reason
        return false, targetReason or "cursor_unavailable"
    end
    cursorNotified = false
    Steering._cursorNotified = false

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

    if landing then return driveLanding(session, landing, current) end
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
    local released, releaseReason = release("steering_reset")
    if released ~= true then return false, releaseReason end
    session = nil
    keyWasHeld = false
    busyNotified = false
    cursorNotified = false
    nextUpdateAt = -math.huge
    reason = "idle"
    Steering._session = nil
    Steering._keyWasHeld = false
    Steering._busyNotified = false
    Steering._cursorNotified = false
    Steering._nextUpdateAt = nextUpdateAt
    Steering._reason = reason
    releaseRetryAt = -math.huge
    Steering._releaseRetryAt = releaseRetryAt
    return true
end

return Steering
