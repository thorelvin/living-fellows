-- SPDX-License-Identifier: MIT

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
if not SC.GameplayUtil and type(require) == "function" then pcall(require, "SCGameplayUtil") end
if not SC.Topology and type(require) == "function" then pcall(require, "SCTopology") end
if not SC.Performance and type(require) == "function" then pcall(require, "SCPerformance") end
if not SC.PathSearch and type(require) == "function" then pcall(require, "SCPathSearch") end
if not SC.NavTraffic and type(require) == "function" then pcall(require, "SCNavTraffic") end
if not SC.NavTraversal and type(require) == "function" then pcall(require, "SCNavTraversal") end
if not SC.WorkRoutes and type(require) == "function" then pcall(require, "SCWorkRoutes") end

SC.Navigation = SC.Navigation or {}
local Navigation = SC.Navigation
local states = setmetatable({}, { __mode = "k" })
local curtainTimes = setmetatable({}, { __mode = "k" })
local squareEvidenceClasses = {
    static_square = true,
    dynamic_square = true,
}

local function U()
    return SC.GameplayUtil
end

local function P()
    return SC.PathSearch
end

local function T()
    return SC.NavTraffic
end

local function V()
    return SC.NavTraversal
end

local function recordMovement(actor, kind, fields)
    if SC.Locomotion and type(SC.Locomotion.recordNavigation) == "function" then
        SC.Locomotion.recordNavigation(actor, kind, fields)
    end
end

local function actionSupervisor()
    if type(SC.ActionSupervisor) == "table" then return SC.ActionSupervisor end
    return nil
end

local function supervisedToken(intent)
    local token = type(intent) == "table" and intent.supervisorToken or nil
    local service = actionSupervisor()
    if token and service and type(service.isCurrent) == "function"
        and service.isCurrent(token) then return service, token end
    return service, nil
end

-- Reject a competing route before it can mutate the active owner's path,
-- threshold sweep, reservations, or recovery timers.  Locomotion performs the
-- same permission check immediately before dispatch, but that is deliberately
-- too late for Navigation's state machine: a denied request may already have
-- cleared room-entry state while calculating its own route.
--
-- Urgent requests still reach Locomotion so its existing preemption/urgent-
-- queue policy remains the single authority for survival movement.
local function navigationOwnershipPermission(actor, intent)
    local service = actionSupervisor()
    if type(service) ~= "table" or type(service.movementPermission) ~= "function" then
        return true
    end
    local request = type(intent) == "table" and intent or {}
    local permitted, reason = service.movementPermission(
        actor, tostring(request.action or "move"), request)
    if permitted == true then return true end
    if request.urgent == true or request.emergency == true
        or request.survivalCritical == true then return true end
    return false, reason or "action_owned"
end

local function tokenSerial(intent)
    local _, token = supervisedToken(intent)
    return token and tonumber(token.serial) or nil
end

local function stateFor(actor)
    local state = states[actor]
    if not state then
        state = {
            path = nil,
            pathGoalSquare = nil,
            pathIndex = 1,
            openedDoors = {},
            indoorTrail = {},
            trailIndex = {},
            stuckAttempts = 0,
            blockedEdges = {},
            blockedSquares = {},
            routeMemory = {},
            blockerHistory = {},
            lastProgressAt = U().nowMs(),
        }
        states[actor] = state
    end
    return state
end

local function sameSquare(a, b)
    if a == b and a ~= nil then return true end
    local utility = U()
    local ax, ay, az = utility.position(a)
    local bx, by, bz = utility.position(b)
    return ax and bx and math.floor(ax) == math.floor(bx)
        and math.floor(ay) == math.floor(by)
        and math.floor(az or 0) == math.floor(bz or 0)
end

local function differentFloor(a, b)
    local _, _, az = U().position(a)
    local _, _, bz = U().position(b)
    return az ~= nil and bz ~= nil and math.floor(az) ~= math.floor(bz)
end

local function adjacentStep(a, b)
    local ax, ay, az = U().position(a)
    local bx, by, bz = U().position(b)
    if ax == nil or bx == nil then return false end
    local dx, dy = math.abs(math.floor(ax) - math.floor(bx)),
        math.abs(math.floor(ay) - math.floor(by))
    local dz = math.abs(math.floor(az or 0) - math.floor(bz or 0))
    if dz == 0 then return dx <= 1 and dy <= 1 end
    return dz == 1 and dx + dy <= 1
end

local function squareKey(square)
    return U().squareKey(square)
end

local function edgeKey(fromSquare, toSquare)
    local fromKey, toKey = squareKey(fromSquare), squareKey(toSquare)
    if not fromKey or not toKey then return nil end
    return fromKey .. ">" .. toKey
end

local function blockerDuration(evidenceClass)
    if evidenceClass == "unknown" then
        return U().config("navigationUnknownBlockedEdgeMs") or 500
    end
    if evidenceClass == "dynamic" or evidenceClass == "dynamic_square" then
        return U().config("navigationDynamicBlockedEdgeMs") or 750
    end
    return U().config("navigationBlockedEdgeMs") or 4500
end

local function blacklistEdge(state, fromSquare, toSquare, blockerType, object, now,
        evidenceClass, confidence)
    local key = edgeKey(fromSquare, toSquare)
    if not key then return nil end
    state.blockedEdges = state.blockedEdges or {}
    local duration = blockerDuration(evidenceClass)
    state.blockedEdges[key] = {
        type = blockerType or "unknown",
        object = object,
        square = toSquare,
        evidenceClass = evidenceClass or "unknown",
        confidence = confidence or "low",
        expires = now + duration,
    }
    local count, oldestKey, oldestExpiry = 0, nil, math.huge
    for candidateKey, candidate in pairs(state.blockedEdges) do
        count = count + 1
        local expiry = tonumber(candidate.expires) or 0
        if expiry < oldestExpiry then oldestKey, oldestExpiry = candidateKey, expiry end
    end
    if count > 64 and oldestKey then state.blockedEdges[oldestKey] = nil end
    return key
end

local function sweepBlockedEdges(state, now)
    for key, entry in pairs(state.blockedEdges or {}) do
        if (tonumber(entry.expires) or 0) <= now then state.blockedEdges[key] = nil end
    end
    for key, entry in pairs(state.blockedSquares or {}) do
        if (tonumber(entry.expires) or 0) <= now then state.blockedSquares[key] = nil end
    end
end

local function blacklistSquare(state, square, blockerType, object, now,
        evidenceClass, confidence)
    local key = squareKey(square)
    if not key then return nil end
    state.blockedSquares = state.blockedSquares or {}
    local duration = blockerDuration(evidenceClass)
    state.blockedSquares[key] = {
        type = blockerType or "unknown", object = object,
        evidenceClass = evidenceClass or "unknown",
        confidence = confidence or "low", expires = now + duration,
    }
    local count, oldestKey, oldestExpiry = 0, nil, math.huge
    for candidateKey, candidate in pairs(state.blockedSquares) do
        count = count + 1
        local expiry = tonumber(candidate.expires) or 0
        if expiry < oldestExpiry then oldestKey, oldestExpiry = candidateKey, expiry end
    end
    if count > 32 and oldestKey then state.blockedSquares[oldestKey] = nil end
    return key
end

local function squareBlacklistEntry(blockedSquares, square, now)
    local key = squareKey(square)
    local entry = key and type(blockedSquares) == "table" and blockedSquares[key] or nil
    if entry and (tonumber(entry.expires) or 0) > (now or U().nowMs()) then return entry end
    if entry and key then blockedSquares[key] = nil end
    return nil
end

local function edgeBlacklistEntry(blockedEdges, fromSquare, toSquare, now)
    local key = edgeKey(fromSquare, toSquare)
    local entry = key and type(blockedEdges) == "table" and blockedEdges[key] or nil
    if entry and (tonumber(entry.expires) or 0) > (now or U().nowMs()) then return entry end
    if entry and key then blockedEdges[key] = nil end
    return nil
end

local function recordBlocker(actor, state, blockerType, object, square, actorState, recovery, now,
        evidenceClass, confidence)
    local entry = {
        type = blockerType or "unknown",
        object = object,
        objectLabel = U().objectLabel(object),
        square = square,
        squareKey = squareKey(square) or "unknown",
        actorState = actorState or "none",
        recoveryResult = recovery or "pending",
        evidenceClass = evidenceClass or "unknown",
        confidence = confidence or "low",
        time = now or U().nowMs(),
    }
    local ax, ay, az = U().position(actor)
    local nativeState = select(1, U().call(actor, "getCurrentState"))
    local actionState = select(1, U().call(actor, "getCompanionActionStateName"))
    local nextAction = select(1, U().call(actor, "getCompanionNextActionStateName"))
    local animations = select(1, U().call(actor, "getCompanionActiveAnimationNames"))
    local telemetry = {}
    if SC.NativeActions and type(SC.NativeActions.pathTelemetry) == "function" then
        local ok, value = pcall(SC.NativeActions.pathTelemetry, actor)
        if ok and type(value) == "table" then telemetry = value end
    end
    local geometry = state.nativeLease or {
        fromSquare = state.lastAttemptFrom, toSquare = state.lastAttemptTo,
    }
    local progress, lateral = V().doorGeometry(geometry, actor)
    entry.failureReason = state.lastMovementReason
    entry.nativeState = U().objectLabel(nativeState)
    entry.actionState = tostring(actionState or "unknown")
    entry.diagnostic = " pos=" .. string.format("%.3f,%.3f,%.2f", ax or -1, ay or -1, az or -1)
        .. " fsm=" .. entry.nativeState .. " action=" .. entry.actionState
        .. " nextAction=" .. tostring(nextAction or "unknown")
        .. " anim=" .. string.sub(tostring(animations or "unknown"), 1, 160)
        .. " path=" .. tostring(telemetry.status or "unavailable") .. ":"
        .. tostring(telemetry.active) .. "/" .. tostring(telemetry.pending)
        .. " pathNext=" .. tostring(telemetry.pathNextIsSet) .. ":"
        .. tostring(telemetry.pathNextX) .. "," .. tostring(telemetry.pathNextY)
        .. " collided=" .. tostring(select(1, U().call(actor, "isCollidedThisFrame")))
        .. "/door:" .. tostring(select(1, U().call(actor, "isCollidedWithDoor")))
        .. "/polygon:" .. tostring(select(1, U().call(actor, "isCollidedWithVehicle")))
        .. " objectOpen=" .. tostring(select(1, U().call(object, "IsOpen")))
        .. " portal=" .. string.format("%.3f/%.3f", progress or -99, lateral or -99)
        .. " reason=" .. string.sub(tostring(entry.failureReason or "unknown"), 1, 120)
    local beforeStop = state.lastNativeFailureTelemetry
    if beforeStop and entry.time - beforeStop.at <= 1000 then
        entry.beforeStop = beforeStop
        entry.diagnostic = entry.diagnostic .. " beforeStop=" .. beforeStop.summary
        state.lastNativeFailureTelemetry = nil
    end
    state.lastBlocker = entry
    recordMovement(actor, "blocker", {
        blocker = entry.type, recovery = entry.recoveryResult,
        targetSquare = entry.square, status = entry.actorState,
        detail = entry.objectLabel .. ":" .. entry.evidenceClass .. ":" .. entry.confidence,
    })
    state.blockerHistory = state.blockerHistory or {}
    state.blockerHistory[#state.blockerHistory + 1] = entry
    while #state.blockerHistory > 8 do table.remove(state.blockerHistory, 1) end
    U().diagnostic("navigation-blocker", actor,
        "type=" .. tostring(entry.type)
        .. " object=" .. tostring(entry.objectLabel)
        .. " square=" .. tostring(entry.squareKey)
        .. " state=" .. tostring(entry.actorState)
        .. " evidence=" .. tostring(entry.evidenceClass)
        .. " confidence=" .. tostring(entry.confidence)
        .. " recovery=" .. tostring(entry.recoveryResult) .. entry.diagnostic)
    return entry
end

local function targetSquare(target)
    local utility = U()
    local square = utility.loadedSquare(target)
    if square then return square end
    return nil
end

local function directionBetween(fromSquare, toSquare)
    local fx, fy, fz = U().position(fromSquare)
    local tx, ty, tz = U().position(toSquare)
    if not fx or not tx then return nil end
    if math.floor(tz or 0) > math.floor(fz or 0) then return "up" end
    if math.floor(tz or 0) < math.floor(fz or 0) then return "down" end
    local dx, dy = tx - fx, ty - fy
    if math.abs(dx) > 0 and math.abs(dy) > 0 then
        if dx > 0 then return dy > 0 and "southeast" or "northeast" end
        return dy > 0 and "southwest" or "northwest"
    end
    if math.abs(dx) >= math.abs(dy) then return dx >= 0 and "east" or "west" end
    return dy >= 0 and "south" or "north"
end

local function barrierBetween(fromSquare, toSquare)
    if SC.Topology and type(SC.Topology.barrierBetween) == "function" then
        return SC.Topology.barrierBetween(fromSquare, toSquare)
    end
    local utility = U()
    if not fromSquare or not toSquare then return nil, "invalid" end
    local fx, fy, fz = utility.position(fromSquare)
    local tx, ty, tz = utility.position(toSquare)
    if not fx or not tx then return nil, "invalid" end
    if math.floor(fz or 0) ~= math.floor(tz or 0) then return nil, "stairs" end

    local owner, north = fromSquare, nil
    if ty < fy then north = true
    elseif ty > fy then owner, north = toSquare, true
    elseif tx < fx then north = false
    elseif tx > fx then owner, north = toSquare, false
    else return nil, "same" end

    local doorTo, doorToOk = utility.call(fromSquare, "isDoorTo", toSquare)
    if doorToOk and doorTo then
        local door, doorOk = utility.call(owner, "getDoor", north)
        if doorOk then return door, "door" end
        return nil, "door"
    end
    local windowTo, windowToOk = utility.call(fromSquare, "isWindowTo", toSquare)
    if windowToOk and windowTo then
        local window, windowOk = utility.call(owner, "getWindow", north)
        if windowOk and window ~= nil then return window, "window" end
        window, windowOk = utility.call(owner, "getThumpableWindow", north)
        if windowOk and window ~= nil then return window, "window" end
        local frame, frameOk = utility.call(owner, "getWindowFrame", north)
        if frameOk and frame ~= nil then return frame, "window_frame" end
        return nil, "window"
    end
    local hoppable, hopOk = utility.call(fromSquare, "isHoppableTo", toSquare)
    if hopOk and hoppable then return nil, "fence" end
    if utility.edgeBlocked(fromSquare, toSquare) then return nil, "blocked" end
    return nil, "open"
end

local function objectOpen(object)
    if SC.Topology and type(SC.Topology.objectOpen) == "function" then
        return SC.Topology.objectOpen(object)
    end
    local utility = U()
    local value, ok = utility.call(object, "IsOpen")
    if ok then return value == true end
    value, ok = utility.call(object, "isOpen")
    return ok and value == true
end

local function objectLocked(object)
    if SC.Topology and type(SC.Topology.objectLocked) == "function" then
        return SC.Topology.objectLocked(object)
    end
    local utility = U()
    local value, ok = utility.call(object, "isLocked")
    if ok and value == true then return true end
    value, ok = utility.call(object, "isPermaLocked")
    if ok and value == true then return true end
    for _, methodName in ipairs({ "isLockedByKey", "isLockedByPadlock", "isLockedByCode" }) do
        value, ok = utility.call(object, methodName)
        if ok and value == true then return true end
    end
    value, ok = utility.call(object, "getLockedByCode")
    if ok and type(value) == "number" and value > 0 then return true end
    local data = utility.modData(object)
    return type(data) == "table" and data.CustomLock == true
end

local function actorCanUnlock(actor, object)
    if SC.Topology and type(SC.Topology.actorCanUnlock) == "function" then
        return SC.Topology.actorCanUnlock(actor, object)
    end
    return false
end

local function edgeThumpableBlocker(fromSquare, toSquare, actor)
    local utility = U()
    local found, kind
    local function inspect(object, ownerSquare)
        local moved, movedOk = utility.call(object, "isMovedThumpable")
        if ownerSquare == toSquare and movedOk and moved == true then
            found, kind = object, "moved_object" return false
        end
        local blockAll, blockOk = utility.call(object, "isBlockAllTheSquare")
        if ownerSquare == toSquare and blockOk and blockAll == true then
            found, kind = object, "full_square_thumpable" return false
        end
        if not utility.instanceOf(object, "IsoThumpable") then return end
        local door, doorOk = utility.call(object, "isDoor")
        local window, windowOk = utility.call(object, "isWindow")
        local pass, passOk = utility.call(object, "isCanPassThrough")
        if (not doorOk or door ~= true) and (not windowOk or window ~= true)
            and (not passOk or pass ~= true) then
            local collides, collisionOk = utility.call(
                object, "TestCollide", actor, fromSquare, toSquare)
            if collisionOk and collides == true then
                found, kind = object, "wall_thumpable"
                return false
            end
        end
    end
    utility.squareSpecialObjects(fromSquare, function(object)
        return inspect(object, fromSquare)
    end, 48)
    if not found then
        utility.squareSpecialObjects(toSquare, function(object)
            return inspect(object, toSquare)
        end, 48)
    end
    return found, kind
end

local function objectBarricaded(object)
    if SC.Topology and type(SC.Topology.objectBarricaded) == "function" then
        return SC.Topology.objectBarricaded(object)
    end
    local utility = U()
    local value, ok = utility.call(object, "isBarricaded")
    if ok and value then return true end
    local barricade, barricadeOk = utility.call(object, "getBarricadeForCharacter", nil)
    return barricadeOk and barricade ~= nil
end

local function windowSmashed(window)
    if SC.Topology and type(SC.Topology.windowSmashed) == "function" then
        return SC.Topology.windowSmashed(window)
    end
    local value, ok = U().call(window, "isSmashed")
    return ok and value == true
end

local function windowGlassRemoved(window)
    if SC.Topology and type(SC.Topology.windowGlassRemoved) == "function" then
        return SC.Topology.windowGlassRemoved(window)
    end
    local value, ok = U().call(window, "isGlassRemoved")
    return ok and value == true
end

local function windowInvincible(window)
    if SC.Topology and type(SC.Topology.windowInvincible) == "function" then
        return SC.Topology.windowInvincible(window)
    end
    local value, ok = U().call(window, "isInvincible")
    return ok and value == true
end

local function canClimbThrough(object, actor)
    if SC.Topology and type(SC.Topology.canClimbThrough) == "function" then
        return SC.Topology.canClimbThrough(object, actor)
    end
    local value, ok = U().call(object, "canClimbThrough", actor)
    if ok then return value == true end
    value, ok = U().call(object, "canClimbThrough", nil)
    return not ok or value == true
end

local function objectStateSignature(object)
    if SC.Topology and type(SC.Topology.objectStateSignature) == "function" then
        return SC.Topology.objectStateSignature(object)
    end
    if object == nil then return "none" end
    return table.concat({
        objectOpen(object) and "open" or "closed",
        objectLocked(object) and "locked" or "unlocked",
        objectBarricaded(object) and "barricaded" or "clear",
        windowSmashed(object) and "smashed" or "intact",
        windowGlassRemoved(object) and "glass-removed" or "glass-present",
    }, ":")
end

local function rememberRouteEdge(state, fromSquare, toSquare, success, kind, object, now)
    local key = edgeKey(fromSquare, toSquare)
    if not key then return end
    state.routeMemory = state.routeMemory or {}
    local duration = success and (U().config("navigationRouteMemorySuccessMs") or 30000)
        or (U().config("navigationRouteMemoryFailureMs") or 8000)
    state.routeMemory[key] = {
        success = success == true,
        kind = kind or "open",
        object = object,
        objectState = objectStateSignature(object),
        expires = now + duration,
    }
    local count, oldestKey, oldestExpiry = 0, nil, math.huge
    for candidateKey, entry in pairs(state.routeMemory) do
        count = count + 1
        local expiry = tonumber(entry.expires) or 0
        if expiry < oldestExpiry then oldestKey, oldestExpiry = candidateKey, expiry end
    end
    if count > 96 and oldestKey then state.routeMemory[oldestKey] = nil end
end

local function routeMemoryAdjustment(memory, fromSquare, toSquare, now)
    local key = edgeKey(fromSquare, toSquare)
    local entry = key and type(memory) == "table" and memory[key] or nil
    if not entry then return 0, 0 end
    if (tonumber(entry.expires) or 0) <= (now or U().nowMs())
        or entry.objectState ~= objectStateSignature(entry.object) then
        memory[key] = nil
        return 0, 0
    end
    if entry.success == true then
        -- Familiar routes are a secondary preference only. Discounting their G
        -- cost made the octile heuristic overestimate the remaining discounted
        -- path and invalidated A*'s shortest-path guarantee.
        return 0, math.max(0,
            tonumber(U().config("navigationRouteMemorySuccessBonus")) or 0.25)
    end
    return U().config("navigationRouteMemoryFailurePenalty") or 4.5, 0
end

local function reserve(object, actor, now)
    return V().reserve(object, actor, now)
end

local function release(object, actor)
    return V().release(object, actor)
end

local function squareHasStairs(square)
    if SC.Topology and type(SC.Topology.squareHasStairs) == "function" then
        return SC.Topology.squareHasStairs(square)
    end
    local utility = U()
    local value, ok = utility.call(square, "HasStairs")
    if ok then return value == true end
    value, ok = utility.call(square, "hasStairs")
    if ok then return value == true end
    local found = false
    utility.squareObjects(square, function(object)
        local stairs, stairsOk = utility.call(object, "isStairsObject")
        if stairsOk and stairs then found = true return false end
        local objectType, typeOk = utility.call(object, "getType")
        if typeOk and string.find(string.lower(tostring(objectType)), "stairs", 1, true) then
            found = true
            return false
        end
    end, 24)
    return found
end

local function squareHasSlope(square)
    if SC.Topology and type(SC.Topology.squareHasSlope) == "function" then
        return SC.Topology.squareHasSlope(square)
    end
    local value, ok = U().call(square, "hasSlopedSurface")
    return ok and value == true
end

function Navigation.edgeAffordance(fromSquare, toSquare)
    if not fromSquare or not toSquare or sameSquare(fromSquare, toSquare) then return nil end
    local object, kind = barrierBetween(fromSquare, toSquare)
    if kind == "open" and (squareHasStairs(fromSquare) or squareHasStairs(toSquare)
        or differentFloor(fromSquare, toSquare)) then kind = "stairs"
    elseif kind == "open" and (squareHasSlope(fromSquare) or squareHasSlope(toSquare)) then
        kind = "slope"
    end
    if kind ~= "door" and kind ~= "window" and kind ~= "window_frame"
        and kind ~= "stairs" and kind ~= "slope" and kind ~= "fence" then
        return nil
    end
    local key
    if kind == "door" and object ~= nil then
        key = "door:" .. tostring(object) .. ":" .. tostring(directionBetween(fromSquare, toSquare))
    else
        key = tostring(kind) .. ":" .. tostring(edgeKey(fromSquare, toSquare))
    end
    return {
        key = key,
        kind = kind,
        object = object,
        fromSquare = fromSquare,
        toSquare = toSquare,
        direction = directionBetween(fromSquare, toSquare),
    }
end

local function squareIsOutdoor(square)
    if not square then return false end
    local room, ok = U().call(square, "getRoom")
    return ok and room == nil
end

local function squareHasTree(square)
    if not square then return false end
    if SC.Topology and type(SC.Topology.squareHasTree) == "function" then
        return SC.Topology.squareHasTree(square)
    end
    local utility = U()
    local tree, treeOk = utility.call(square, "HasTree")
    if treeOk then return tree == true end
    tree, treeOk = utility.call(square, "getTree")
    if treeOk and tree ~= nil then return true end
    local found = false
    utility.squareObjects(square, function(object)
        if utility.instanceOf(object, "IsoTree") then found = true return false end
        local name, nameOk = utility.call(object, "getObjectName")
        if nameOk and string.lower(tostring(name or "")) == "tree" then
            found = true
            return false
        end
    end, 32)
    return found
end

local treeNeighborOffsets = {
    { -1, -1 }, { 0, -1 }, { 1, -1 },
    { -1, 0 },              { 1, 0 },
    { -1, 1 },  { 0, 1 },   { 1, 1 },
}

local function treeClearanceCost(square)
    if not square then return 0 end
    local utility = U()
    local x, y, z = utility.position(square)
    if x == nil then return 0 end
    local count = 0
    for _, offset in ipairs(treeNeighborOffsets) do
        if squareHasTree(utility.gridSquare(x + offset[1], y + offset[2], z)) then
            count = count + 1
        end
    end
    return count * (utility.config("navigationTreeClearancePenalty") or 4)
end

local function squareNearTree(square)
    if not square then return false end
    if squareHasTree(square) then return true end
    local utility = U()
    local x, y, z = utility.position(square)
    if x == nil then return false end
    for _, offset in ipairs(treeNeighborOffsets) do
        if squareHasTree(utility.gridSquare(x + offset[1], y + offset[2], z)) then return true end
    end
    return false
end

local function squareVehicle(square)
    if not square then return nil end
    local vehicle, ok = U().call(square, "getVehicleContainer")
    return ok and vehicle or nil
end

local function vehicleClearanceCost(square)
    if not square then return 0 end
    local utility = U()
    local x, y, z = utility.position(square)
    if x == nil then return 0 end
    local cacheKey = squareKey(square)
    local cached = cacheKey and SC.Performance
        and type(SC.Performance.cacheGet) == "function"
        and SC.Performance.cacheGet("navigation-vehicle-clearance", cacheKey,
            utility.nowMs()) or nil
    if cached ~= nil then return cached end
    local count = 0
    for _, offset in ipairs(treeNeighborOffsets) do
        if squareVehicle(utility.gridSquare(x + offset[1], y + offset[2], z)) then
            count = count + 1
        end
    end
    local cost = count * (utility.config("navigationVehicleClearancePenalty") or 2)
    if cacheKey and SC.Performance and type(SC.Performance.cachePut) == "function" then
        SC.Performance.cachePut("navigation-vehicle-clearance", cacheKey, cost,
            utility.config("navigationClearanceCacheMs") or 500, utility.nowMs())
    end
    return cost
end

local function squareNearVehicle(square)
    if not square then return false end
    if squareVehicle(square) then return true end
    return vehicleClearanceCost(square) > 0
end

local function treeEscapeDirection(actorSquare, actor, goalSquare)
    if not actorSquare then return nil end
    local utility = U()
    local x, y, z = utility.position(actorSquare)
    if x == nil then return nil end
    local actorX, actorY = utility.position(actor)
    local awayX, awayY, found = 0, 0, false
    local offsets = {
        { 0, 0 },
        { -1, -1 }, { 0, -1 }, { 1, -1 },
        { -1, 0 },              { 1, 0 },
        { -1, 1 },  { 0, 1 },   { 1, 1 },
    }
    for _, offset in ipairs(offsets) do
        local treeSquare = utility.gridSquare(x + offset[1], y + offset[2], z)
        if squareHasTree(treeSquare) then
            found = true
            if offset[1] == 0 and offset[2] == 0 then
                awayX = awayX + ((actorX or (x + 0.5)) - (x + 0.5))
                awayY = awayY + ((actorY or (y + 0.5)) - (y + 0.5))
            else
                local length = math.sqrt(offset[1] * offset[1] + offset[2] * offset[2])
                awayX = awayX - offset[1] / length
                awayY = awayY - offset[2] / length
            end
        end
    end
    if not found then return nil end
    if awayX * awayX + awayY * awayY < 0.04 then
        local gx, gy = utility.position(goalSquare)
        awayX, awayY = x - (gx or x), y - (gy or y)
        if awayX * awayX + awayY * awayY < 0.04 then awayX, awayY = -1, 0 end
    end
    if math.abs(awayX) >= math.abs(awayY) then return awayX >= 0 and 1 or -1, 0 end
    return 0, awayY >= 0 and 1 or -1
end

local function resolveFollowGoal(sourceSquare, requestedSquare, intent)
    if not requestedSquare then return nil, false end
    local utility = U()
    local function suitable(square)
        if not square or not utility.isSquareFree(square) or squareHasTree(square) then
            return false
        end
        if SC.Topology and type(SC.Topology.squareIsWater) == "function"
            and SC.Topology.squareIsWater(square) then return false end
        if SC.Topology and type(SC.Topology.squareHazards) == "function" then
            local hazards = SC.Topology.squareHazards(square)
            if hazards.fire or hazards.explosiveTrap then return false end
        end
        return true
    end
    if suitable(requestedSquare) then
        return requestedSquare, false
    end
    local action = type(intent) == "table" and tostring(intent.action or "") or ""
    local formation = type(intent) == "table" and intent.followRecovery == true
        or action == "follow_formation" or action == "regroup"
    if not formation then return nil, false end
    local gx, gy, gz = utility.position(requestedSquare)
    if gx == nil then return nil, false end
    local best, bestScore
    for radius = 1, 2 do
        for dx = -radius, radius do
            for dy = -radius, radius do
                if math.max(math.abs(dx), math.abs(dy)) == radius then
                    local square = utility.gridSquare(gx + dx, gy + dy, gz)
                    if suitable(square) then
                        local score = (math.abs(dx) + math.abs(dy)) * 4
                            + treeClearanceCost(square) * 2
                            + utility.distance(sourceSquare, square) * 0.05
                        if bestScore == nil or score < bestScore then
                            best, bestScore = square, score
                        end
                    end
                end
            end
        end
    end
    return best, best ~= nil
end

local function squareHasBush(square)
    if not square then return false end
    local utility = U()
    local foundBush = false
    utility.squareObjects(square, function(object)
        local sprite, spriteOk = utility.call(object, "getSprite")
        if not spriteOk or sprite == nil then return end
        local properties, propertiesOk = utility.call(sprite, "getProperties")
        if not propertiesOk or properties == nil then return end
        local flag = type(IsoFlagType) == "table" and IsoFlagType.canBeCut or "canBeCut"
        local cuttable, cuttableOk = utility.call(properties, "has", flag)
        if cuttableOk and cuttable == true then foundBush = true return false end
    end, 32)
    return foundBush
end

local function squareVegetationCost(square)
    if not square then return 0, false end
    local utility = U()
    if squareHasTree(square) then
        return utility.config("navigationTreePenalty") or 12, false
    end
    local bush = squareHasBush(square)
    return bush and (utility.config("navigationBushPenalty") or 5.5) or 0, bush
end

local function pathHasBush(path)
    for index = 2, #(path or {}) do
        if squareHasBush(path[index]) then return true end
    end
    return false
end

local function insideSecureBase(actor, snapshot)
    if type(SC.BaseLife) ~= "table" or type(SC.BaseLife.isInside) ~= "function" then return false end
    local ok, inside = pcall(SC.BaseLife.isInside, actor)
    if not ok or inside ~= true then return false end
    snapshot = type(snapshot) == "table" and snapshot or {}
    return (tonumber(snapshot.threatCount) or #(snapshot.threats or {})) == 0
        and (tonumber(snapshot.immediateCount) or #(snapshot.immediateAttackers or {})) == 0
end

local function poorSight(actor, sourceSquare, nextSquare, afterSquare, intent)
    if insideSecureBase(actor, intent and intent.snapshot) then return false end
    local dark, darkOk = U().call(actor, "tooDarkToRead")
    if darkOk and dark == true then return true end
    if squareVegetationCost(nextSquare) > 0 or squareVegetationCost(afterSquare) > 0 then return true end
    if afterSquare ~= nil and not U().canSee(actor, afterSquare) then return true end
    return false
end

local function stopAndObserve(actor, target, intent)
    local utility = U()
    if not utility.stop(actor) then return false end
    if insideSecureBase(actor, intent and intent.snapshot) then return true end
    local accepted = utility.move(actor, "walk", {
        action = "ready_weapon",
        targetSquare = target,
        facingTarget = target,
        stableFacing = true,
        weaponReady = true,
        humanAnimationOnly = true,
        supervisorToken = intent and intent.supervisorToken,
    })
    return accepted == true
end

local function rebuildTrailIndex(state)
    state.trailIndex = {}
    for index, square in ipairs(state.indoorTrail or {}) do
        local key = squareKey(square)
        if key then state.trailIndex[key] = index end
    end
end

local function appendTrailSquare(state, square)
    local key = squareKey(square)
    if not key then return end
    local existing = state.trailIndex[key]
    if existing then
        for index = #state.indoorTrail, existing + 1, -1 do
            state.indoorTrail[index] = nil
        end
        rebuildTrailIndex(state)
        return
    end
    state.indoorTrail[#state.indoorTrail + 1] = square
    state.trailIndex[key] = #state.indoorTrail
    local limit = U().config("navigationBreadcrumbLimit") or 64
    while #state.indoorTrail > limit do
        -- Keep a known exterior threshold whenever possible. Once indoors, the
        -- second-oldest breadcrumb is less valuable than the verified doorway.
        local removeAt = squareIsOutdoor(state.indoorTrail[1]) and 2 or 1
        table.remove(state.indoorTrail, removeAt)
    end
    rebuildTrailIndex(state)
end

local function observeSquare(state, square)
    local key = squareKey(square)
    if not key or key == state.lastObservedKey then return end
    if squareIsOutdoor(square) then
        state.lastOutdoorSquare = square
        state.indoorTrail = {}
        state.trailIndex = {}
        state.wasIndoor = false
        state.egressPath = nil
        state.egressTarget = nil
    else
        if not state.wasIndoor then
            state.indoorTrail = {}
            state.trailIndex = {}
            state.nextEgressScanAt = 0
            if state.lastOutdoorSquare then appendTrailSquare(state, state.lastOutdoorSquare) end
        end
        state.wasIndoor = true
        appendTrailSquare(state, square)
    end
    state.lastObservedKey = key
end

local function passableEdge(fromSquare, toSquare, vegetationScale, options)
    local utility = U()
    options = type(options) == "table" and options or {}
    local blockedEdge = edgeBlacklistEntry(
        options.blockedEdges, fromSquare, toSquare, options.now)
    if blockedEdge then
        return false, math.huge,
            "blacklisted_" .. tostring(blockedEdge.evidenceClass or "edge")
    end
    local blockedSquare = squareBlacklistEntry(options.blockedSquares, toSquare, options.now)
    if blockedSquare then
        return false, math.huge,
            "blacklisted_" .. tostring(blockedSquare.evidenceClass or "square")
    end
    local topology = SC.Topology and type(SC.Topology.classifyEdge) == "function"
        and SC.Topology.classifyEdge(options.actor, fromSquare, toSquare, options) or nil
    local baseCost
    if topology ~= nil then
        if topology.traversable ~= true then
            return false, math.huge, topology.reason or topology.affordance,
                topology.object
        end
        baseCost = tonumber(topology.cost) or 1
    else
        -- Compatibility fallback for unusual partial-load environments. Normal
        -- production and every supported harness load SCTopology first.
        if squareVehicle(toSquare) then return false, math.huge, "vehicle_footprint" end
        if not utility.isSquareFree(toSquare) then return false, math.huge, "square_blocked" end
        if utility.safehouseBlocker(toSquare, options.actor) then
            return false, math.huge, "safehouse_boundary"
        end
        local object, kind = barrierBetween(fromSquare, toSquare)
        if kind == "blocked" or kind == "invalid" or kind == "diagonal" then
            return false, math.huge, kind
        end
        local thumpable, thumpableKind = edgeThumpableBlocker(
            fromSquare, toSquare, options.actor)
        if thumpable then return false, math.huge, thumpableKind, thumpable end
        if kind == "door" then
            if not object or objectBarricaded(object)
                or objectLocked(object) and not objectOpen(object)
                    and not actorCanUnlock(options.actor, object) then
                return false, math.huge, "door_blocked", object
            end
            baseCost = objectOpen(object) and 1 or 2.2
        elseif kind == "window" then
            if not object or objectBarricaded(object)
                or windowInvincible(object) and not objectOpen(object) then
                return false, math.huge, "window_blocked", object
            end
            baseCost = objectOpen(object) and 2.5 or (windowSmashed(object) and 4 or 5)
        elseif kind == "window_frame" then
            if not object or not canClimbThrough(object, options.actor) then
                return false, math.huge, "window_frame_blocked", object
            end
            baseCost = 2.5
        elseif kind == "fence" then
            baseCost = 2.5
        elseif kind == "stairs" then
            if not (squareHasStairs(fromSquare) or squareHasStairs(toSquare)) then
                return false, math.huge, "stairs_not_confirmed"
            end
            baseCost = 3
        elseif kind == "slope" then
            baseCost = 2
        else
            baseCost = 1
        end
    end
    local scale = tonumber(vegetationScale)
    if scale == nil then scale = 1 end
    local crowdCost = 0
    if options.allowOccupiedGoal ~= true then
        local moving, movingKind = utility.movingBlocker(toSquare, options.actor)
        if movingKind == "pushable_object" then
            return false, math.huge, "pushable_object", moving
        end
        if moving then crowdCost = utility.config("navigationCrowdPenalty") or 9 end
    end
    local memoryPenalty, familiarity = routeMemoryAdjustment(
        options.routeMemory, fromSquare, toSquare, options.now)
    local vegetationCost, hasBush = squareVegetationCost(toSquare)
    return true, math.max(0.25, baseCost
        + vegetationCost * math.max(0, scale)
        + treeClearanceCost(toSquare) + vehicleClearanceCost(toSquare) + crowdCost
        + memoryPenalty), nil, nil, familiarity, hasBush
end

local function heuristic(square, goal)
    local utility = U()
    local x, y, z = utility.position(square)
    local gx, gy, gz = utility.position(goal)
    if not x or not gx then return math.huge end
    local dx, dy = math.abs(x - gx), math.abs(y - gy)
    local diagonal = math.min(dx, dy)
    -- Octile distance is admissible for the 8-connected grid below (cardinal
    -- cost 1, diagonal cost sqrt(2)); Manhattan would overestimate and could
    -- discard the natural straight diagonal route.
    return dx + dy + (math.sqrt(2) - 2) * diagonal
        + math.abs((z or 0) - (gz or 0)) * 4
end

local cardinalOffsets = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
local diagonalOffsets = { { 1, 1 }, { -1, 1 }, { -1, -1 }, { 1, -1 } }
local verticalOffsets = { -1, 1 }

local function neighbors(square, goal, rotation)
    local utility = U()
    local x, y, z = utility.position(square)
    if not x then return {} end
    local result = {}
    local offset = math.floor(tonumber(rotation) or 0) % #cardinalOffsets
    for step = 1, #cardinalOffsets do
        local delta = cardinalOffsets[((step - 1 + offset) % #cardinalOffsets) + 1]
        local other = utility.gridSquare(x + delta[1], y + delta[2], z)
        if other then result[#result + 1] = other end
    end
    for step = 1, #diagonalOffsets do
        local delta = diagonalOffsets[((step - 1 + offset) % #diagonalOffsets) + 1]
        local other = utility.gridSquare(x + delta[1], y + delta[2], z)
        if other then result[#result + 1] = other end
    end
    -- Do not invent vertical graph edges. Build 42 stairs occupy several tiles and
    -- their upper endpoint depends on orientation; a same-X/Y z+1 edge is not a
    -- reliable representation. Production hands every cross-floor goal to the
    -- native PathFindBehavior2 route below, which owns the real stair affordance.
    return result
end

local function reconstruct(nodes, goalKey)
    return P().reconstruct(nodes, goalKey)
end

local function stealthAvoidanceRequested(actor, movementMode, intent)
    if type(intent) == "table" then
        if intent.urgent == true or intent.ignoreStealthAvoidance == true then return false end
        if intent.stealthAvoidance ~= nil then return intent.stealthAvoidance == true end
    end
    if movementMode == "sneak" then return true end
    if SC.Commands and type(SC.Commands.peek) == "function" then
        local ok, commands = pcall(SC.Commands.peek, actor)
        if ok and type(commands) == "table" then
            return commands.combatDoctrine == "stealth" or commands.weaponPriority == "quiet"
        end
    end
    return false
end

local function stealthThreatPenalty(square, snapshot)
    if not square or type(snapshot) ~= "table" then return 0 end
    local utility = U()
    local squareX, squareY, squareZ = utility.position(square)
    if squareX == nil then return 0 end
    local visibleRadius = math.max(1,
        tonumber(utility.config("navigationStealthVisibleRadius")) or 10)
    local obstructedRadius = math.max(1,
        tonumber(utility.config("navigationStealthObstructedRadius")) or 6)
    local closeRadius = math.max(0.5,
        tonumber(utility.config("navigationStealthCloseRadius")) or 4)
    local basePenalty = math.max(0,
        tonumber(utility.config("navigationStealthThreatPenalty")) or 36)
    local closePenalty = math.max(0,
        tonumber(utility.config("navigationStealthClosePenalty")) or 90)
    local total = 0

    local function addThreat(threat, remembered)
        if type(threat) ~= "table" then return end
        local threatX, threatY, threatZ = tonumber(threat.x), tonumber(threat.y), tonumber(threat.z)
        if threatX == nil then
            threatX, threatY, threatZ = utility.position(threat.actor or threat.square or threat)
        end
        if threatX == nil then return end
        local dx, dy = squareX - threatX, squareY - threatY
        local dz = (squareZ or 0) - (threatZ or 0)
        local distanceSq = dx * dx + dy * dy + dz * dz * 9
        local distance = math.sqrt(math.max(0, distanceSq))
        local radius = threat.obstructed == true and obstructedRadius or visibleRadius
        if remembered == true then radius = math.min(radius, obstructedRadius) end
        if distance >= radius then return end
        local proximity = (radius - distance) / radius
        local penalty = basePenalty * proximity
        if distance < closeRadius then
            penalty = penalty + closePenalty * ((closeRadius - distance) / closeRadius + 0.25)
        end
        if threat.attacking == true then penalty = penalty * 1.25 end
        total = total + penalty
    end

    local threats = type(snapshot.stealthThreats) == "table" and snapshot.stealthThreats
        or (type(snapshot.threats) == "table" and snapshot.threats or {})
    for index = 1, math.min(#threats, 24) do addThreat(threats[index], false) end
    -- Outer perception is sampled over successive scans. Preserve the strongest
    -- recent contact during a sampling gap without double-counting a live list.
    if #threats == 0 and type(snapshot.lastKnownDanger) == "table" then
        addThreat(snapshot.lastKnownDanger, true)
    end
    return total
end

-- review 3.5: a stealth-avoidance search runs across several frames on a snapshot
-- captured once at request time. The threat entries carry live actor references, so
-- their positions stay current, but a contact that dies or leaves mid-search would
-- otherwise keep bending the route until the search finishes. Keep a small overlay
-- of just those threats and refresh it on a bounded cadence during the search,
-- dropping any whose actor is no longer a valid, living danger. A remembered or
-- square-only contact (no live actor) is retained as recorded.
local function buildStealthOverlay(snapshot)
    local overlay = { threats = {}, refreshedAt = nil }
    local source = type(snapshot) == "table"
        and (type(snapshot.stealthThreats) == "table" and snapshot.stealthThreats
            or (type(snapshot.threats) == "table" and snapshot.threats or {}))
        or {}
    for index = 1, math.min(#source, 24) do
        overlay.threats[#overlay.threats + 1] = U().copyShallow(source[index])
    end
    if type(snapshot) == "table" then overlay.lastKnownDanger = snapshot.lastKnownDanger end
    return overlay
end

local function refreshStealthOverlay(overlay, now)
    if type(overlay) ~= "table" or type(overlay.threats) ~= "table" then return false end
    local numericNow = tonumber(now)
    if numericNow ~= nil and overlay.refreshedAt ~= nil
        and numericNow - overlay.refreshedAt
            < (U().config("navigationStealthOverlayRefreshMs") or 250) then
        return false
    end
    if numericNow ~= nil then overlay.refreshedAt = numericNow end
    local utility = U()
    local kept = {}
    for _, threat in ipairs(overlay.threats) do
        local actor = type(threat) == "table" and threat.actor or nil
        if actor == nil or (utility.isValidActor(actor) and not utility.isDead(actor)) then
            local x, y, z = utility.position(actor or threat.square or threat)
            if x ~= nil then threat.x, threat.y, threat.z = x, y, z end
            kept[#kept + 1] = threat
        end
    end
    overlay.threats = kept
    return true
end

-- Binary min-heap for the A* open set (review 3.3), replacing the O(N) lowest-f
-- linear scan + O(N) table.remove that made each expansion O(N) and the search
-- O(N^2). Entries are { key, f, h, familiarity, seq } and are ordered by f,
-- then h, then successful route-memory familiarity, then a stable insertion
-- sequence. Familiarity never changes the primary path cost.
-- Improvements push a fresh entry that reuses the node's original seq and leave the
-- superseded entry in place (lazy deletion); the popper drops any entry whose
-- priority no longer matches its node, or whose node is already closed.
local function heapPush(heap, entry)
    return P().heapPush(heap, entry)
end

local function heapPop(heap)
    return P().heapPop(heap)
end

local pathSearchAdapter = {
    sameSquare = sameSquare,
    key = squareKey,
    heuristic = heuristic,
    neighbors = function(square, goal, options)
        return neighbors(square, goal, options and options.neighborRotation)
    end,
    edge = function(fromSquare, toSquare, options, allowOccupiedGoal)
        options = type(options) == "table" and options or {}
        if type(options.squareAdmission) == "function" then
            local admitted, allowed = pcall(options.squareAdmission, toSquare, fromSquare)
            if not admitted or allowed ~= true then
                return false, nil, "outside_admitted_area"
            end
        end
        options.allowOccupiedGoal = allowOccupiedGoal == true
        return passableEdge(fromSquare, toSquare, options.vegetationScale, options)
    end,
    nodeBudget = function()
        return U().config("navigationNodeBudget") or 220
    end,
}

local function newBoundedPathJob(startSquare, goalSquare, options)
    return P().new(startSquare, goalSquare, options, pathSearchAdapter)
end

local function resumeBoundedPathJob(job, expansionQuota, slice)
    return P().resume(job, expansionQuota, slice)
end

local function boundedPath(startSquare, goalSquare, options)
    local job = newBoundedPathJob(startSquare, goalSquare, options)
    local status, path, reason, expanded = resumeBoundedPathJob(job, job.nodeBudget or 1)
    if status == "pending" then return nil, "budget", expanded end
    return path, reason, expanded
end

local function nearestGridCoordinate(value)
    if value >= 0 then return math.floor(value + 0.5) end
    return math.ceil(value - 0.5)
end

-- Common follow requests are short and cross completely open ground. Prove the
-- octile-straight route edge by edge before starting the resumable A-star job.
-- If any edge is blocked, hazardous, crowded or more expensive than open floor,
-- abandon this shortcut and let the full planner choose a detour.
local function fastOpenRouteWithinBatch(startSquare, goalSquare, options)
    options = type(options) == "table" and options or {}
    if options.stealthAvoidance == true or type(options.squarePenalty) == "function" then
        return nil, "scored_route_required"
    end
    local sx, sy, sz = U().position(startSquare)
    local gx, gy, gz = U().position(goalSquare)
    if sx == nil or gx == nil or math.floor(sz or 0) ~= math.floor(gz or 0) then
        return nil, "fast_route_floor_mismatch"
    end
    sx, sy, sz = math.floor(sx), math.floor(sy), math.floor(sz or 0)
    gx, gy = math.floor(gx), math.floor(gy)
    local dx, dy = gx - sx, gy - sy
    local steps = math.max(math.abs(dx), math.abs(dy))
    local maximum = math.floor(tonumber(options.maximumSteps)
        or tonumber(U().config("navigationFastFollowMaxSteps")) or 24)
    if steps <= 0 then return { startSquare }, nil end
    if maximum <= 0 or steps > maximum then return nil, "fast_route_out_of_range" end

    local path, current = { startSquare }, startSquare
    local previousX, previousY = sx, sy
    for step = 1, steps do
        local nextX = nearestGridCoordinate(sx + dx * step / steps)
        local nextY = nearestGridCoordinate(sy + dy * step / steps)
        local deltaX, deltaY = math.abs(nextX - previousX), math.abs(nextY - previousY)
        if deltaX > 1 or deltaY > 1 or deltaX + deltaY == 0 then
            return nil, "fast_route_invalid_step"
        end
        local nextSquare = U().gridSquare(nextX, nextY, sz)
        if nextSquare == nil then return nil, "fast_route_square_unavailable" end
        if type(options.squareAdmission) == "function" then
            local observed, admitted = pcall(options.squareAdmission, nextSquare, current)
            if not observed or admitted ~= true then return nil, "outside_admitted_area" end
        end
        options.allowOccupiedGoal = step == steps and options.allowOccupiedFinal ~= false
        local passable, cost = passableEdge(
            current, nextSquare, options.vegetationScale, options)
        local openCost = deltaX == 1 and deltaY == 1 and math.sqrt(2) or 1
        if passable ~= true or tonumber(cost) == nil or cost > openCost + 0.001 then
            return nil, "fast_route_requires_planner"
        end
        path[#path + 1] = nextSquare
        current, previousX, previousY = nextSquare, nextX, nextY
    end
    if not sameSquare(current, goalSquare) then return nil, "fast_route_goal_missed" end
    return path, nil
end

local function fastOpenRoute(startSquare, goalSquare, options)
    if SC.Topology and type(SC.Topology.withReadBatch) == "function" then
        return SC.Topology.withReadBatch(
            fastOpenRouteWithinBatch, startSquare, goalSquare, options)
    end
    return fastOpenRouteWithinBatch(startSquare, goalSquare, options)
end
Navigation._fastOpenRouteForRequest = fastOpenRoute
Navigation._fastOpenRouteForTests = fastOpenRoute

Navigation._fastOpenRouteWithinBatchForWorkRoutes = fastOpenRouteWithinBatch
Navigation._passableEdgeForWorkRoutes = passableEdge
Navigation._sameSquareForWorkRoutes = sameSquare
Navigation._adjacentStepForWorkRoutes = adjacentStep
Navigation.workRouteStats = function()
    return SC.WorkRoutes and SC.WorkRoutes.snapshot() or { entries = 0 }
end
Navigation._workRouteForTests = function(...)
    return SC.WorkRoutes.lookup(...)
end
Navigation._recordWorkRouteForTests = function(...)
    return SC.WorkRoutes.record(...)
end
Navigation._resetWorkRoutesForTests = function()
    return SC.WorkRoutes.reset()
end
local function followTrackRouteWithinBatch(startSquare, goalSquare, track, options)
    if type(track) ~= "table" or track[1] == nil then return nil, "track_unavailable" end
    options = type(options) == "table" and options or {}
    if options.stealthAvoidance == true or type(options.squarePenalty) == "function" then
        return nil, "scored_route_required"
    end
    local maximum = math.max(2,
        math.floor(tonumber(U().config("formationTrackMaxSquares")) or 48))
    if #track > maximum then return nil, "track_too_long" end

    -- Open ground does not require literal breadcrumb replay. This is both a
    -- loop eraser and a string pull: a companion following a player around a
    -- circle takes the proven-clear chord to the current formation goal.
    local direct = fastOpenRouteWithinBatch(startSquare, goalSquare, options)
    if direct ~= nil then return direct, nil end

    -- When a portal blocks that chord, join a reachable point on the retained
    -- player track. Trying only the geometrically nearest point strands an actor
    -- on the wrong side of a fence/window because every nearby breadcrumb is
    -- beyond the barrier. Probe a bounded set, while always including the oldest
    -- retained approach point so the exact player crossing remains recoverable.
    local candidates = {}
    for index = 1, #track do
        local distance = U().distance(startSquare, track[index])
        candidates[#candidates + 1] = { index = index, distance = distance }
    end
    table.sort(candidates, function(left, right)
        if left.distance ~= right.distance then return left.distance < right.distance end
        return left.index < right.index
    end)
    local candidateLimit = math.max(1,
        math.floor(tonumber(U().config("formationTrackJoinCandidates")) or 12))
    local attempted, bestReason = {}, "track_join_blocked"

    local function routeFrom(joinIndex)
        attempted[joinIndex] = true
        local path, reason = fastOpenRouteWithinBatch(
            startSquare, track[joinIndex], options)
        if path == nil then return nil, reason or "track_join_blocked" end
        local current = path[#path]
        for index = joinIndex + 1, #track do
            local nextSquare = track[index]
            if nextSquare ~= nil and not sameSquare(current, nextSquare) then
                if not adjacentStep(current, nextSquare) then
                    return nil, "track_sample_gap"
                end
                options.allowOccupiedGoal = index == #track
                local passable = passableEdge(
                    current, nextSquare, options.vegetationScale, options)
                if passable ~= true then return nil, "track_edge_changed" end
                path[#path + 1] = nextSquare
                current = nextSquare
                if #path > maximum + 1 then return nil, "track_route_too_long" end
            end
        end
        if not sameSquare(current, goalSquare) then return nil, "track_goal_changed" end
        return path, nil
    end

    for rank = 1, math.min(#candidates, candidateLimit) do
        local path, reason = routeFrom(candidates[rank].index)
        if path ~= nil then return path, nil end
        bestReason = reason or bestReason
    end
    if not attempted[1] then
        local path, reason = routeFrom(1)
        if path ~= nil then return path, nil end
        bestReason = reason or bestReason
    end
    return nil, bestReason
end

local function followTrackRoute(startSquare, goalSquare, track, options)
    if SC.Topology and type(SC.Topology.withReadBatch) == "function" then
        return SC.Topology.withReadBatch(
            followTrackRouteWithinBatch, startSquare, goalSquare, track, options)
    end
    return followTrackRouteWithinBatch(startSquare, goalSquare, track, options)
end
Navigation._followTrackRouteForRequest = followTrackRoute
Navigation._followTrackRouteForTests = followTrackRoute

local function actualOpenSegmentWithinBatch(actor, targetX, targetY, targetZ, options)
    local actorX, actorY, actorZ = U().position(actor)
    if actorX == nil or targetX == nil
        or math.floor(actorZ or 0) ~= math.floor(targetZ or 0) then return false end
    local distance = math.sqrt((targetX - actorX)^2 + (targetY - actorY)^2)
    local samples = math.max(1, math.ceil(distance / 0.20))
    local previous = U().gridSquare(math.floor(actorX), math.floor(actorY),
        math.floor(actorZ or 0))
    if previous == nil then return false end
    options = U().copyShallow(options)
    options.allowOccupiedGoal = false
    for sample = 1, samples do
        local ratio = sample / samples
        local square = U().gridSquare(
            math.floor(actorX + (targetX - actorX) * ratio),
            math.floor(actorY + (targetY - actorY) * ratio),
            math.floor(targetZ or 0))
        if square == nil then return false end
        if not sameSquare(previous, square) then
            local passable = passableEdge(previous, square,
                options.vegetationScale, options)
            if passable ~= true then return false end
            previous = square
        end
    end
    return true
end

local function actualOpenSegment(actor, targetX, targetY, targetZ, options)
    if SC.Topology and type(SC.Topology.withReadBatch) == "function" then
        return SC.Topology.withReadBatch(actualOpenSegmentWithinBatch,
            actor, targetX, targetY, targetZ, options)
    end
    return actualOpenSegmentWithinBatch(actor, targetX, targetY, targetZ, options)
end
Navigation._actualOpenSegmentForTests = actualOpenSegment

-- Aim manual follow movement several proven-open tiles ahead. The route and
-- first-square reservation remain authoritative; only the movement vector is
-- blended. This removes the tile-centre staircase and its abrupt 45/90-degree
-- turns without cutting a wall, closed portal, vehicle or hazardous edge.
local function continuousFollowVector(actor, state, sourceSquare, intent)
    if not actor or type(state) ~= "table" or type(state.path) ~= "table"
        or type(intent) ~= "table" then return nil end
    if intent.action ~= "follow_formation" and intent.action ~= "regroup" then return nil end
    local first = math.max(2, math.floor(tonumber(state.pathIndex) or 2))
    if state.path[first] == nil then return nil end
    local lookahead = math.max(1, math.floor(tonumber(
        U().config("navigationContinuousFollowLookahead")) or 6))
    local last = math.min(#state.path, first + lookahead - 1)
    local openLast, previous = first - 1, sourceSquare
    for index = first, last do
        local candidate = state.path[index]
        if candidate == nil or Navigation.edgeAffordance(previous, candidate) ~= nil then break end
        openLast, previous = index, candidate
    end
    if openLast < first then return nil end

    local options = {
        actor = actor,
        blockedEdges = state.blockedEdges,
        blockedSquares = state.blockedSquares,
        routeMemory = state.routeMemory,
        allowHazards = intent.urgent == true,
        allowOccupiedFinal = false,
        now = U().nowMs(),
    }
    for index = openLast, first, -1 do
        local candidate = state.path[index]
        local route = fastOpenRoute(sourceSquare, candidate, options)
        if route ~= nil then
            local targetX, targetY, targetZ = U().position(candidate)
            targetX, targetY = targetX and targetX + 0.5, targetY and targetY + 0.5
            local intercept = index == #state.path and intent.interceptPosition or nil
            if type(intercept) == "table" and tonumber(intercept.x)
                and tonumber(intercept.y)
                and math.floor(intercept.x) == math.floor(targetX or math.huge)
                and math.floor(intercept.y) == math.floor(targetY or math.huge)
                and math.floor(intercept.z or targetZ or 0) == math.floor(targetZ or 0) then
                targetX, targetY, targetZ = intercept.x, intercept.y, intercept.z or targetZ
            end
            local actorX, actorY = U().position(actor)
            if actorX ~= nil and targetX ~= nil
                and actualOpenSegment(actor, targetX, targetY, targetZ, options) then
                return targetX - actorX, targetY - actorY, candidate, index
            end
        end
    end
    return nil
end
Navigation._continuousFollowVectorForTests = continuousFollowVector
Navigation._continuousFollowVectorForRequest = continuousFollowVector

local function egressNeighbors(square)
    local utility = U()
    local x, y, z = utility.position(square)
    if not x then return {} end
    local result = {}
    for _, delta in ipairs(cardinalOffsets) do
        local other = utility.gridSquare(x + delta[1], y + delta[2], z)
        if other then result[#result + 1] = other end
    end
    if squareHasStairs(square) then
        for _, dz in ipairs(verticalOffsets) do
            local vertical = utility.gridSquare(x, y, z + dz)
            if vertical then result[#result + 1] = vertical end
            for _, delta in ipairs(cardinalOffsets) do
                vertical = utility.gridSquare(x + delta[1], y + delta[2], z + dz)
                if vertical then result[#result + 1] = vertical end
            end
        end
    end
    return result
end

local function withinEgressRadius(startSquare, square)
    local utility = U()
    local sx, sy, sz = utility.position(startSquare)
    local x, y, z = utility.position(square)
    if not sx or not x then return false end
    local radius = utility.config("navigationEgressRadius") or 18
    return math.abs(x - sx) + math.abs(y - sy) + math.abs((z or 0) - (sz or 0)) * 4 <= radius
end

local function boundedOutdoorPath(startSquare, vegetationScale)
    if not startSquare then return nil, "invalid_square", 0 end
    if squareIsOutdoor(startSquare) then return { startSquare }, nil, 0 end
    local startKey = squareKey(startSquare)
    if not startKey then return nil, "invalid_square", 0 end
    local nodes = {
        [startKey] = { square = startSquare, g = 0, f = 0, h = 0, parent = nil, seq = 0 },
    }
    local open, closed = { { key = startKey, f = 0, h = 0, seq = 0 } }, {}
    local seqCounter = 0
    local expanded = 0
    local nodeBudget = U().config("navigationEgressNodeBudget") or 160

    while #open > 0 and expanded < nodeBudget do
        local entry = heapPop(open)
        local bestKey = entry and entry.key or nil
        local current = bestKey and nodes[bestKey] or nil
        -- Dijkstra is still the right search for "nearest outdoor square"; use the
        -- same heap/lazy-deletion machinery as A* so the bounded scan is O(E log V)
        -- instead of repeatedly linearly scanning and removing from the open list.
        if current and not closed[bestKey] and entry.f == current.g then
            if bestKey ~= startKey and squareIsOutdoor(current.square) then
                return reconstruct(nodes, bestKey), nil, expanded
            end
            closed[bestKey] = true
            expanded = expanded + 1
            for _, otherSquare in ipairs(egressNeighbors(current.square)) do
                local otherKey = squareKey(otherSquare)
                if otherKey and not closed[otherKey] and withinEgressRadius(startSquare, otherSquare) then
                    local passable, cost = passableEdge(
                        current.square, otherSquare, vegetationScale)
                    if passable then
                        local tentative = current.g + cost
                        local known = nodes[otherKey]
                        if not known or tentative < known.g then
                            local seq = known and known.seq
                            if seq == nil then
                                seqCounter = seqCounter + 1
                                seq = seqCounter
                            end
                            nodes[otherKey] = {
                                square = otherSquare, g = tentative, f = tentative,
                                h = 0, parent = bestKey, seq = seq,
                            }
                            heapPush(open, {
                                key = otherKey, f = tentative, h = 0, seq = seq,
                            })
                        end
                    end
                end
            end
        end
    end
    return nil, expanded >= nodeBudget and "budget" or "no_loaded_outdoor_route", expanded
end

local function reversedTrailPath(state, currentSquare)
    local trail = state.indoorTrail or {}
    if #trail < 2 or not sameSquare(trail[#trail], currentSquare) then return nil end
    local path = { currentSquare }
    local previous = currentSquare
    for index = #trail - 1, 1, -1 do
        local square = trail[index]
        local passable = passableEdge(previous, square)
        if not passable then return nil end
        path[#path + 1] = square
        previous = square
    end
    return path
end

local function refreshEgress(state, currentSquare, now)
    if squareIsOutdoor(currentSquare) then
        state.egressPath, state.egressTarget, state.egressReason = nil, nil, "already_outdoors"
        return
    end
    if now < (state.nextEgressScanAt or 0) then return end
    local path, reason, expanded = boundedOutdoorPath(currentSquare, 1)
    local emergency = pathHasBush(path)
    if not path then
        path, reason, expanded = boundedOutdoorPath(currentSquare,
            U().config("navigationEmergencyVegetationScale") or 0.2)
        emergency = pathHasBush(path)
    end
    state.egressPath = path
    state.egressTarget = path and path[#path] or nil
    state.egressEmergencyVegetation = emergency == true
    state.egressReason = reason
    state.egressExpandedNodes = expanded
    state.nextEgressScanAt = now + (U().config("navigationEgressRefreshMs") or 2500)
end

local function routePoint(value, remembered)
    if value == nil then return nil end
    local record = type(value) == "table" and value or nil
    local x = record and tonumber(record.x) or nil
    local y = record and tonumber(record.y) or nil
    local z = record and tonumber(record.z) or nil
    if x == nil or y == nil then
        x, y, z = U().position(record and (record.actor or record.square) or value)
    end
    if x == nil or y == nil then return nil end
    return {
        x = x, y = y, z = z or 0,
        obstructed = record and record.obstructed == true or false,
        attacking = record and record.attacking == true or false,
        remembered = remembered == true,
    }
end

-- Capture each moving actor once, cooperatively, before evaluating route nodes.
-- Scoring then compares plain numbers instead of multiplying Kahlua-to-Java
-- getX/getY/getZ calls by path length and crowd size.
local function newRouteEvaluationContext(snapshot, options)
    snapshot = type(snapshot) == "table" and snapshot or {}
    options = type(options) == "table" and options or {}
    local dangerSnapshot = options.stealthOverlay or snapshot
    return {
        threats = {}, allies = {}, stealthAvoidance = options.stealthAvoidance == true,
        visibleRadius = math.max(1, tonumber(U().config("navigationStealthVisibleRadius")) or 10),
        obstructedRadius = math.max(1, tonumber(U().config("navigationStealthObstructedRadius")) or 6),
        closeRadius = math.max(0.5, tonumber(U().config("navigationStealthCloseRadius")) or 4),
        basePenalty = math.max(0, tonumber(U().config("navigationStealthThreatPenalty")) or 36),
        closePenalty = math.max(0, tonumber(U().config("navigationStealthClosePenalty")) or 90),
        snapshot = snapshot, dangerSnapshot = dangerSnapshot,
        stage = "threats", index = 1, ready = false,
    }
end

local function resumeRouteEvaluationContext(context, slice)
    if context.ready == true then return true end
    if context.source == nil then
        context.source = type(context.dangerSnapshot.threats) == "table"
            and context.dangerSnapshot.threats
            or (type(context.snapshot.threats) == "table" and context.snapshot.threats or {})
        context.threatLimit = context.stealthAvoidance and 24 or 16
    end
    while context.stage == "threats"
        and context.index <= math.min(#context.source, context.threatLimit) do
        if slice and P().sliceExpired(slice) then return false end
        local point = routePoint(context.source[context.index], false)
        if point then context.threats[#context.threats + 1] = point end
        context.index = context.index + 1
    end
    if context.stage == "threats" then
        if #context.source == 0 and type(context.dangerSnapshot.lastKnownDanger) == "table" then
            if slice and P().sliceExpired(slice) then return false end
            local point = routePoint(context.dangerSnapshot.lastKnownDanger, true)
            if point then context.threats[1] = point end
        end
        context.stage, context.index = "allies", 1
        context.source = type(context.snapshot.allies) == "table"
            and context.snapshot.allies or {}
    end
    while context.stage == "allies" and context.index <= #context.source do
        if slice and P().sliceExpired(slice) then return false end
        local point = routePoint(context.source[context.index], false)
        if point then context.allies[#context.allies + 1] = point end
        context.index = context.index + 1
    end
    if context.stage == "allies" then
        context.stage = "player"
    end
    if context.stage == "player" then
        local player = context.snapshot.player
        if type(player) == "table" and player.actor then
            if slice and P().sliceExpired(slice) then return false end
            local point = routePoint(player, false)
            if point then context.allies[#context.allies + 1] = point end
        end
        context.stage = "complete"
    end
    context.ready, context.source = true, nil
    context.snapshot, context.dangerSnapshot = nil, nil
    return true
end

local function routeEvaluationContext(snapshot, options)
    local context = newRouteEvaluationContext(snapshot, options)
    resumeRouteEvaluationContext(context)
    return context
end

local function pointDistanceSq(x, y, z, point)
    local dx, dy, dz = x - point.x, y - point.y, (z or 0) - (point.z or 0)
    return dx * dx + dy * dy + dz * dz * 9
end

local function routeDangerAt(x, y, z, context)
    if x == nil or type(context) ~= "table" then return 0 end
    local total = 0
    if context.stealthAvoidance == true then
        for _, threat in ipairs(context.threats or {}) do
            local distance = math.sqrt(math.max(0, pointDistanceSq(x, y, z, threat)))
            local radius = threat.obstructed and context.obstructedRadius or context.visibleRadius
            if threat.remembered then radius = math.min(radius, context.obstructedRadius) end
            if distance < radius then
                local penalty = context.basePenalty * ((radius - distance) / radius)
                if distance < context.closeRadius then
                    penalty = penalty + context.closePenalty
                        * ((context.closeRadius - distance) / context.closeRadius + 0.25)
                end
                if threat.attacking then penalty = penalty * 1.25 end
                total = total + penalty
            end
        end
        return total
    end
    for _, threat in ipairs(context.threats or {}) do
        local distanceSq = pointDistanceSq(x, y, z, threat)
        if distanceSq <= 2.25 then total = total + 5
        elseif distanceSq <= 6.25 then total = total + 2
        elseif distanceSq <= 12.25 then total = total + 0.5 end
    end
    return total
end

local function routeDanger(path, snapshot, options, context)
    if type(path) ~= "table" or type(snapshot) ~= "table" then return 0 end
    options = type(options) == "table" and options or {}
    context = context or routeEvaluationContext(snapshot, options)
    local last = options.stealthAvoidance == true and #path or math.min(#path, 6)
    local danger = 0
    for index = 2, last do
        local x, y, z = U().position(path[index])
        danger = danger + routeDangerAt(x, y, z, context)
    end
    return danger
end

local function routeCrowding(path, snapshot, context)
    if type(path) ~= "table" or type(snapshot) ~= "table" then return 0 end
    context = context or routeEvaluationContext(snapshot, {})
    local crowding = 0
    for index = 2, math.min(#path, 7) do
        local x, y, z = U().position(path[index])
        if x ~= nil then
            for _, other in ipairs(context.allies or {}) do
                local distanceSq = pointDistanceSq(x, y, z, other)
                if distanceSq <= 0.81 then crowding = crowding + 2
                elseif distanceSq <= 2.25 then crowding = crowding + 0.5 end
            end
        end
    end
    return crowding
end

local function routeTurns(path)
    if type(path) ~= "table" or #path < 3 then return 0 end
    local turns, lastX, lastY, lastZ = 0, nil, nil, nil
    for index = 2, #path do
        local ax, ay, az = U().position(path[index - 1])
        local bx, by, bz = U().position(path[index])
        if ax and bx then
            local dx, dy, dz = bx - ax, by - ay, (bz or 0) - (az or 0)
            if lastX ~= nil and (dx ~= lastX or dy ~= lastY or dz ~= lastZ) then
                turns = turns + 1
            end
            lastX, lastY, lastZ = dx, dy, dz
        end
    end
    return turns
end

local function routeTraversalCost(path)
    if type(path) ~= "table" then return math.huge end
    local cost, hasBush = 0, false
    for index = 2, #path do
        local passable, edgeCost, _, _, _, edgeHasBush =
            passableEdge(path[index - 1], path[index])
        if not passable then return math.huge end
        cost = cost + edgeCost
        hasBush = hasBush or edgeHasBush == true
    end
    return cost, hasBush
end

local function routeSignature(path)
    local parts = {}
    for _, square in ipairs(path or {}) do parts[#parts + 1] = tostring(squareKey(square)) end
    return table.concat(parts, ">")
end

local function routeEvaluation(path, snapshot, originalIndex, options)
    local context = routeEvaluationContext(snapshot, options)
    local traversal, hasBush = routeTraversalCost(path)
    local danger = routeDanger(path,
        options and options.stealthOverlay or snapshot, options, context)
    local crowding = routeCrowding(path, snapshot, context)
    local turns = routeTurns(path)
    return {
        path = path,
        originalIndex = originalIndex,
        traversal = traversal,
        danger = danger,
        crowding = crowding,
        turns = turns,
        signature = routeSignature(path),
        emergencyVegetation = hasBush == true,
        score = traversal + danger * (options and options.stealthAvoidance and 1 or 4)
            + crowding * 2 + turns * 0.15,
    }
end

-- The incremental route chooser must time-slice scoring as well as A*. In
-- particular, rechecking traversal cost can otherwise issue a whole path's
-- worth of native obstacle queries after its search deadline has expired.
local function resumeRouteEvaluation(job, path, originalIndex, slice)
    if not resumeRouteEvaluationContext(job.evaluationContext, slice) then return nil end
    local evaluation = job.pendingEvaluation
    if not evaluation then
        local firstX, firstY, firstZ = U().position(path[1])
        evaluation = { path = path, originalIndex = originalIndex, index = 2,
            traversal = 0, danger = 0, crowding = 0, turns = 0,
            context = job.evaluationContext,
            previousX = firstX, previousY = firstY, previousZ = firstZ,
            signatureParts = { tostring(squareKey(path[1])) },
            emergencyVegetation = false }
        job.pendingEvaluation = evaluation
    end
    local options = job.pathOptions or {}
    while evaluation.index <= #path do
        if P().sliceExpired(slice) then return nil end
        local index = evaluation.index
        local previous, square = path[index - 1], path[index]
        if evaluation.traversal < math.huge then
            local passable, cost, _, _, _, hasBush = passableEdge(previous, square)
            evaluation.traversal = passable and evaluation.traversal + cost or math.huge
            evaluation.emergencyVegetation = evaluation.emergencyVegetation
                or hasBush == true
        end
        local bx, by, bz = U().position(square)
        if options.stealthAvoidance == true or index <= 6 then
            evaluation.danger = evaluation.danger
                + routeDangerAt(bx, by, bz, evaluation.context)
        end
        if index <= 7 and bx ~= nil then
            for _, other in ipairs(evaluation.context.allies or {}) do
                local distanceSq = pointDistanceSq(bx, by, bz, other)
                if distanceSq <= 0.81 then evaluation.crowding = evaluation.crowding + 2
                elseif distanceSq <= 2.25 then evaluation.crowding = evaluation.crowding + 0.5 end
            end
        end
        if evaluation.previousX and bx then
            local dx, dy, dz = bx - evaluation.previousX, by - evaluation.previousY,
                (bz or 0) - (evaluation.previousZ or 0)
            if evaluation.lastX ~= nil and (dx ~= evaluation.lastX
                or dy ~= evaluation.lastY or dz ~= evaluation.lastZ) then
                evaluation.turns = evaluation.turns + 1
            end
            evaluation.lastX, evaluation.lastY, evaluation.lastZ = dx, dy, dz
        end
        evaluation.previousX, evaluation.previousY, evaluation.previousZ = bx, by, bz
        local key = bx ~= nil and (tostring(math.floor(bx)) .. ":"
            .. tostring(math.floor(by)) .. ":" .. tostring(math.floor(bz or 0)))
            or tostring(squareKey(square))
        evaluation.signatureParts[#evaluation.signatureParts + 1] = key
        evaluation.index = index + 1
    end
    job.pendingEvaluation = nil
    return { path = path, originalIndex = originalIndex, traversal = evaluation.traversal,
        danger = evaluation.danger, crowding = evaluation.crowding, turns = evaluation.turns,
        signature = table.concat(evaluation.signatureParts, ">"),
        nodeKeys = evaluation.signatureParts,
        emergencyVegetation = evaluation.emergencyVegetation == true,
        score = evaluation.traversal + evaluation.danger * (options.stealthAvoidance and 1 or 4)
            + evaluation.crowding * 2 + evaluation.turns * 0.15 }
end

local function chooseFollowRoute(startSquare, goalSquare, snapshot, pathOptions)
    local utility = U()
    pathOptions = type(pathOptions) == "table" and pathOptions or {}
    local primary, reason, expanded = boundedPath(startSquare, goalSquare, pathOptions)
    if not primary then return nil, reason, expanded, nil end
    local primaryEvaluation = routeEvaluation(primary, snapshot, 1, pathOptions)
    local candidates = { primaryEvaluation }
    local signatures = { [primaryEvaluation.signature] = true }
    local minimumLength = utility.config("navigationAlternativeMinLength") or 6
    local maximum = math.max(1, math.min(3,
        math.floor(tonumber(utility.config("navigationAlternativeRoutes")) or 3)))
    local totalExpanded = expanded or 0

    if #primary >= minimumLength and maximum > 1 then
        local penalties = {}
        local diversity = utility.config("navigationRouteDiversityPenalty") or 3.5
        for attempt = 2, maximum do
            local previous = candidates[#candidates].path
            for index = 2, math.min(#previous - 1, 12) do
                local key = squareKey(previous[index])
                if key then penalties[key] = (penalties[key] or 0) + diversity end
            end
            local alternativeOptions = U().copyShallow(pathOptions)
            alternativeOptions.nodeBudget = utility.config("navigationAlternativeNodeBudget") or 80
            alternativeOptions.neighborRotation = attempt - 1
            alternativeOptions.penalties = penalties
            local alternative, _, alternativeExpanded = boundedPath(startSquare, goalSquare, alternativeOptions)
            totalExpanded = totalExpanded + (alternativeExpanded or 0)
            local evaluation = alternative and routeEvaluation(
                alternative, snapshot, #candidates + 1, pathOptions) or nil
            if evaluation and not signatures[evaluation.signature] then
                signatures[evaluation.signature] = true
                candidates[#candidates + 1] = evaluation
            end
        end
    end

    table.sort(candidates, function(a, b)
        if a.score == b.score then return a.originalIndex < b.originalIndex end
        return a.score < b.score
    end)
    local selected = candidates[1]
    return selected.path, nil, totalExpanded, {
        candidateCount = #candidates,
        selectedOriginalIndex = selected.originalIndex,
        selectedScore = selected.score,
        selectedDanger = selected.danger,
        selectedSignature = selected.signature,
        selectedEmergencyVegetation = selected.emergencyVegetation == true,
        routes = candidates,
    }
end

local function finalizeRouteSearch(job, reason)
    job.complete = true
    job.reason = reason
    if #job.candidates > 0 then
        table.sort(job.candidates, function(left, right)
            if left.score == right.score then return left.originalIndex < right.originalIndex end
            return left.score < right.score
        end)
        local selected = job.candidates[1]
        job.path = selected.path
        job.reason = nil
        job.report = {
            candidateCount = #job.candidates,
            selectedOriginalIndex = selected.originalIndex,
            selectedScore = selected.score,
            selectedDanger = selected.danger,
            selectedSignature = selected.signature,
            selectedEmergencyVegetation = selected.emergencyVegetation == true,
            routes = job.candidates,
        }
    end
    return job
end

local function newRouteSearchJob(startSquare, goalSquare, snapshot, pathOptions, alternatives)
    pathOptions = type(pathOptions) == "table" and pathOptions or {}
    return {
        startSquare = startSquare,
        goalSquare = goalSquare,
        startKey = squareKey(startSquare),
        goalKey = squareKey(goalSquare),
        snapshot = snapshot,
        pathOptions = pathOptions,
        evaluationContext = newRouteEvaluationContext(snapshot, pathOptions),
        alternatives = alternatives == true,
        phase = "primary",
        search = newBoundedPathJob(startSquare, goalSquare, pathOptions),
        candidates = {},
        signatures = {},
        penalties = {},
        attempt = 1,
        totalExpanded = 0,
        complete = false,
    }
end

local function startAlternativeSearch(job)
    local utility = U()
    local previousEvaluation = job.candidates[#job.candidates]
    local previous = previousEvaluation and previousEvaluation.path or nil
    if not previous then return false end
    local diversity = utility.config("navigationRouteDiversityPenalty") or 3.5
    for index = 2, math.min(#previous - 1, 12) do
        local key = previousEvaluation.nodeKeys and previousEvaluation.nodeKeys[index]
            or squareKey(previous[index])
        if key then job.penalties[key] = (job.penalties[key] or 0) + diversity end
    end
    local options = utility.copyShallow(job.pathOptions)
    options.nodeBudget = utility.config("navigationAlternativeNodeBudget") or 80
    options.neighborRotation = job.attempt - 1
    options.penalties = job.penalties
    job.search = newBoundedPathJob(job.startSquare, job.goalSquare, options)
    job.phase = "alternative"
    return true
end

local function resumeRouteSearchSlice(job, expansionQuota)
    if type(job) ~= "table" then return "failed", nil, "invalid_job", 0, nil, 0 end
    if job.complete then
        return job.path and "complete" or "failed", job.path, job.reason,
            job.totalExpanded or 0, job.report, 0
    end
    local slice = P().newSlice(job.pathOptions, U().config("navigationSliceBudgetMs") or 2)
    job.lastYieldReason = nil
    -- Refresh the stealth danger overlay before this slice so later-expanded nodes
    -- score against threats that are still live (review 3.5). Bounded and throttled.
    if type(job.pathOptions) == "table" and job.pathOptions.stealthOverlay ~= nil then
        refreshStealthOverlay(job.pathOptions.stealthOverlay, U().nowMs())
    end
    local remaining = math.max(1, math.floor(tonumber(expansionQuota) or 1))
    local totalUsed, transitions = 0, 0
    while remaining > 0 and not job.complete and transitions < 8 do
        if P().sliceExpired(slice) then
            job.lastYieldReason = "deadline"
            return "pending", nil, "searching", job.totalExpanded
                + (job.search and job.search.expanded or 0), nil, totalUsed
        end
        transitions = transitions + 1
        local status, path, reason, expanded, used = resumeBoundedPathJob(job.search, remaining, slice)
        used = math.max(0, tonumber(used) or 0)
        totalUsed = totalUsed + used
        remaining = remaining - used
        if status == "pending" then
            job.lastYieldReason = job.search.lastYieldReason or "quota"
            return "pending", nil, "searching", job.totalExpanded + expanded, nil, totalUsed
        end

        -- A completed search retains its result. Resume its cheap completion on
        -- the next slice instead of scoring alternatives after a costly edge.
        if P().sliceExpired(slice) then
            job.lastYieldReason = "deadline"
            return "pending", nil, "searching", job.totalExpanded + expanded, nil, totalUsed
        end

        local evaluation
        if status == "complete" and path then
            evaluation = resumeRouteEvaluation(job, path,
                job.phase == "primary" and 1 or #job.candidates + 1, slice)
            if not evaluation then
                job.lastYieldReason = "deadline"
                return "pending", nil, "searching", job.totalExpanded + expanded, nil, totalUsed
            end
        end

        job.totalExpanded = job.totalExpanded + (tonumber(expanded) or 0)
        if job.phase == "primary" then
            if status ~= "complete" or not path then
                job.failure = {
                    failureClass = job.search.failureClass or "blocked_static",
                    nativeFallbackAllowed = job.search.nativeFallbackAllowed == true,
                    rejections = job.search.rejections or {},
                }
                finalizeRouteSearch(job, reason or "unreachable")
            elseif not job.alternatives then
                job.candidates[1] = evaluation
                job.signatures[evaluation.signature] = true
                finalizeRouteSearch(job)
            else
                job.candidates[1] = evaluation
                job.signatures[evaluation.signature] = true
                local minimumLength = U().config("navigationAlternativeMinLength") or 6
                local maximum = math.max(1, math.min(3,
                    math.floor(tonumber(U().config("navigationAlternativeRoutes")) or 3)))
                job.maximumAttempts = maximum
                job.attempt = 2
                if #path < minimumLength or maximum <= 1 or not startAlternativeSearch(job) then
                    finalizeRouteSearch(job)
                end
            end
        else
            if status == "complete" and path and evaluation then
                if not job.signatures[evaluation.signature] then
                    job.signatures[evaluation.signature] = true
                    job.candidates[#job.candidates + 1] = evaluation
                end
            end
            job.attempt = job.attempt + 1
            if job.attempt > (job.maximumAttempts or 1) or not startAlternativeSearch(job) then
                finalizeRouteSearch(job)
            end
        end

        -- A start-square completion may use zero expansions. State transitions
        -- above still make progress, but do not spin after the route is final.
        if used == 0 and not job.complete and job.search and not job.search.complete then break end
    end
    if job.complete then
        return job.path and "complete" or "failed", job.path, job.reason,
            job.totalExpanded, job.report, totalUsed
    end
    return "pending", nil, "searching", job.totalExpanded, nil, totalUsed
end

local function resumeRouteSearch(job, expansionQuota)
    if SC.Topology and type(SC.Topology.withReadBatch) == "function" then
        return SC.Topology.withReadBatch(resumeRouteSearchSlice, job, expansionQuota)
    end
    return resumeRouteSearchSlice(job, expansionQuota)
end

local function chooseRememberedEgress(state, currentSquare, now, snapshot)
    refreshEgress(state, currentSquare, now)
    local computed = state.egressPath
    local breadcrumb = reversedTrailPath(state, currentSquare)
    local computedOutdoor = computed and squareIsOutdoor(computed[#computed])
    local breadcrumbOutdoor = breadcrumb and squareIsOutdoor(breadcrumb[#breadcrumb])
    if computedOutdoor and breadcrumbOutdoor then
        local computedDanger = routeDanger(computed, snapshot)
        local breadcrumbDanger = routeDanger(breadcrumb, snapshot)
        if #breadcrumb + breadcrumbDanger * 4 < #computed + computedDanger * 4 then
            return breadcrumb[#breadcrumb], {
                source = "entry_route", path = breadcrumb, outdoors = true, danger = breadcrumbDanger,
                emergencyVegetation = pathHasBush(breadcrumb),
            }
        end
        return computed[#computed], {
            source = "shortest_outdoor", path = computed, outdoors = true, danger = computedDanger,
            emergencyVegetation = state.egressEmergencyVegetation == true,
        }
    end
    if computedOutdoor then
        return computed[#computed], {
            source = "shortest_outdoor", path = computed, outdoors = true,
            danger = routeDanger(computed, snapshot),
            emergencyVegetation = state.egressEmergencyVegetation == true,
        }
    end
    if breadcrumb then
        return breadcrumb[#breadcrumb], {
            source = breadcrumbOutdoor and "entry_route" or "backtrack",
            path = breadcrumb,
            outdoors = breadcrumbOutdoor == true,
            danger = routeDanger(breadcrumb, snapshot),
            emergencyVegetation = pathHasBush(breadcrumb),
        }
    end
    return nil, { source = "none", reason = state.egressReason or "no_remembered_egress" }
end

local function threatArrivalMs(intent, square)
    local utility = U()
    local snapshot = intent and intent.snapshot
    if type(snapshot) ~= "table" or type(snapshot.threats) ~= "table" then return math.huge end
    local nearest = math.huge
    for index = 1, math.min(#snapshot.threats, 12) do
        local threat = snapshot.threats[index]
        local distance = utility.distance(square, threat.actor or threat.square)
        if distance < nearest then nearest = distance end
    end
    if nearest == math.huge then return nearest end
    return math.max(0, (nearest - 0.8) / 1.05 * 1000)
end

local function doorGeometry(entry, value)
    return V().doorGeometry(entry, value)
end

local function actorClearOfDoorway(actor, entry)
    local progress = doorGeometry(entry, actor)
    return progress ~= nil
        and progress >= (U().config("doorClearanceDistance") or 0.38)
end

local function occupiesDoorway(value, entry)
    return V().occupiesDoorway(value, entry)
end

local trafficContext
local traversalContext = {
    objectOpen = objectOpen,
    objectLocked = objectLocked,
    actorCanUnlock = actorCanUnlock,
    objectBarricaded = objectBarricaded,
    windowSmashed = windowSmashed,
    windowGlassRemoved = windowGlassRemoved,
    windowInvincible = windowInvincible,
    canClimbThrough = canClimbThrough,
    directionBetween = directionBetween,
    threatArrivalMs = threatArrivalMs,
    sameSquare = sameSquare,
    record = recordMovement,
    actorPassageKey = function(actor, state) return T().actorPassageKey(actor, state) end,
    passageActive = function(key, now)
        return T().activePassageKey(key, now, trafficContext)
    end,
}

local function handleDoor(actor, state, door, fromSquare, toSquare, now)
    return V().handleDoor(actor, state, door, fromSquare, toSquare, now, traversalContext)
end

local function handleWindow(actor, state, window, fromSquare, toSquare, now, intent)
    local aligned, status = V().alignWindowApproach(
        actor, fromSquare, toSquare, intent, traversalContext)
    if aligned ~= true then return aligned, status end
    return V().handleWindow(
        actor, state, window, fromSquare, toSquare, now, intent, traversalContext)
end

local function handleWindowFrame(actor, frame, fromSquare, toSquare, now, intent)
    local aligned, status = V().alignWindowApproach(
        actor, fromSquare, toSquare, intent, traversalContext)
    if aligned ~= true then return aligned, status end
    return V().handleWindowFrame(
        actor, frame, fromSquare, toSquare, now, intent, traversalContext)
end

local function alignDoorApproach(actor, fromSquare, toSquare, intent, affordance)
    return V().alignDoorApproach(
        actor, fromSquare, toSquare, intent, affordance, traversalContext)
end

local function handleFence(actor, object, fromSquare, toSquare, intent)
    return V().handleFence(actor, object, fromSquare, toSquare, intent, traversalContext)
end
Navigation._handleFenceForRequest = handleFence

trafficContext = {
    record = recordMovement,
    doorGeometry = doorGeometry,
    occupiesDoorway = occupiesDoorway,
    sameSquare = sameSquare,
    differentFloor = differentFloor,
    squareHasStairs = squareHasStairs,
    squareHasSlope = squareHasSlope,
    edgeAffordance = Navigation.edgeAffordance,
    squareKey = squareKey,
}

function Navigation.observeGroupPassage(leader, edge, cohort, roster, current)
    return T().observeGroupPassage(
        leader, edge, cohort, roster, current, trafficContext)
end

-- Positioning keeps a fireteam in its ordered column until every nearby member
-- has cleared the same portal. This query deliberately exposes only the active
-- bit: passage ownership and mutation remain inside Navigation.
function Navigation.groupPassageActive(edge, cohort, current)
    return T().groupPassageActive(edge, cohort, current, trafficContext)
end

local function ensureGroupPassage(actor, state, sourceSquare, nextSquare, kind, intent, now)
    local admitted = T().ensureGroupPassage(
        actor, state, sourceSquare, nextSquare, kind, intent, now, trafficContext)
    if admitted == true then return true end
    if not stopAndObserve(actor, nextSquare, intent) then
        return false, "group_passage_stop_rejected"
    end
    return nil, "holding_group_passage"
end

local function markActorPassage(actor, state, now)
    return T().markActorPassage(actor, state, now, trafficContext)
end
Navigation._ensureGroupPassageForRequest = ensureGroupPassage
Navigation._markActorPassageForRequest = markActorPassage

local function nearbyOpenedDoor(state, actor)
    return V().nearbyOpenedDoor(state, actor, traversalContext)
end

local function closeOwnedDoors(actor, state, now, snapshot)
    return V().closeOwnedDoors(actor, state, now, snapshot, traversalContext)
end

local function releaseChoke(state, actor)
    return T().releaseChoke(state, actor, trafficContext)
end

local function extendChoke(state, actor, untilAt)
    return T().extendChoke(state, actor, untilAt)
end

local movementPriority

local function reserveChokeCorridor(sourceSquare, nextSquare, afterSquare, actor, state, intent, now)
    return T().reserveChoke(
        sourceSquare, nextSquare, afterSquare, actor, state, intent, now, trafficContext)
end

movementPriority = function(intent)
    return T().priority(intent)
end

local function releaseStep(state, actor)
    return T().releaseStep(state, actor)
end

local function reserveStep(square, actor, state, intent, now)
    return T().reserveStep(square, actor, state, intent, now, trafficContext)
end

local function hasRightOfWay(actor, intent, blocker)
    local ownPriority = movementPriority(intent)
    local otherState = blocker and states[blocker] or nil
    local otherPriority = otherState and tonumber(otherState.trafficPriority) or 10
    if ownPriority ~= otherPriority then return ownPriority > otherPriority end
    return tostring(U().idOf(actor)) < tostring(U().idOf(blocker))
end

local function personalSpaceBlocker(actor, nextSquare, snapshot)
    if type(snapshot) ~= "table" then return nil end
    local utility = U()
    local tx, ty = utility.position(nextSquare)
    if tx == nil then return nil end
    local spacing = utility.config("navigationBodyClearance") or 0.5
    for _, ally in ipairs(snapshot.allies or {}) do
        if ally.actor and ally.actor ~= actor and utility.sameFloor(ally.actor, nextSquare)
            and utility.bodyBlocksSegment(ally.actor, actor, tx + 0.5, ty + 0.5, spacing)
            then return ally.actor end
    end
    local player = snapshot.player
    if type(player) == "table" and player.actor and player.actor ~= actor
        and utility.sameFloor(player.actor, nextSquare)
        and utility.bodyBlocksSegment(player.actor, actor, tx + 0.5, ty + 0.5, spacing)
        then return player.actor end
    return nil
end

local function lateralYield(actor, state, sourceSquare, nextSquare, intent, now)
    local utility = U()
    local sx, sy, sz = utility.position(sourceSquare)
    local nx, ny = utility.position(nextSquare)
    if not sx or not nx then return false end
    local dx, dy = nx - sx, ny - sy
    if dx * dx + dy * dy < 0.25 then return false end
    local candidates = {
        utility.gridSquare(sx - dy, sy + dx, sz),
        utility.gridSquare(sx + dy, sy - dx, sz),
    }
    if utility.stableHash(utility.idOf(actor)) % 2 == 1 then
        candidates[1], candidates[2] = candidates[2], candidates[1]
    end
    for _, square in ipairs(candidates) do
        local hazards = SC.Topology and type(SC.Topology.squareHazards) == "function"
            and SC.Topology.squareHazards(square) or {}
        local water = SC.Topology and type(SC.Topology.squareIsWater) == "function"
            and SC.Topology.squareIsWater(square)
        if square and utility.isSquareFree(square) and not water
            and not hazards.fire and not hazards.explosiveTrap
            and not utility.edgeBlocked(sourceSquare, square)
            and not personalSpaceBlocker(actor, square, intent.snapshot)
            and reserveStep(square, actor, state, intent, now) then
            local accepted = utility.move(actor, "walk", {
                action = "right_of_way_yield",
                nextSquare = square,
                targetSquare = square,
                direction = directionBetween(sourceSquare, square),
                direct = true,
                collisionValidated = true,
                yieldFor = state.yieldBlocker,
                supervisorToken = intent and intent.supervisorToken,
            })
            if accepted then
                state.path = nil
                state.pathGoalSquare = nil
                state.nextRepathAt = 0
                state.yieldSince = nil
                state.yieldBlocker = nil
                return true
            end
        end
    end
    return false
end

local function turnAt(sourceSquare, nextSquare, afterSquare)
    if not sourceSquare or not nextSquare or not afterSquare then return nil end
    local sx, sy, sz = U().position(sourceSquare)
    local nx, ny, nz = U().position(nextSquare)
    local ax, ay, az = U().position(afterSquare)
    if not sx or not nx or not ax or math.floor(sz or 0) ~= math.floor(nz or 0)
        or math.floor(nz or 0) ~= math.floor(az or 0) then return nil end
    local firstX, firstY = nx - sx, ny - sy
    local secondX, secondY = ax - nx, ay - ny
    local cross = firstX * secondY - firstY * secondX
    if math.abs(cross) < 0.5 then return nil end
    return cross > 0 and "right" or "left"
end

local function wallBehind(sourceSquare, facingTarget)
    local utility = U()
    local sx, sy, sz = utility.position(sourceSquare)
    local tx, ty = utility.position(facingTarget)
    if not sx or not tx then return false, nil end
    local dx, dy = tx - sx, ty - sy
    local behindX, behindY = 0, 0
    if math.abs(dx) >= math.abs(dy) then behindX = dx >= 0 and -1 or 1
    else behindY = dy >= 0 and -1 or 1 end
    local behind = utility.gridSquare(sx + behindX, sy + behindY, sz)
    if not behind then return true, nil end
    return utility.edgeBlocked(sourceSquare, behind) or not utility.isSquareFree(behind), behind
end

local function stairCrowded(actor, nextSquare, snapshot)
    if type(snapshot) ~= "table" then return false end
    local utility = U()
    local spacing = utility.config("navigationStairSpacing") or 1.75
    local spacingSq = spacing * spacing
    for _, ally in ipairs(snapshot.allies or {}) do
        if ally.actor and ally.actor ~= actor and utility.sameFloor(ally.actor, nextSquare)
            and utility.distanceSq(ally.actor, nextSquare) <= spacingSq then return true end
    end
    local player = snapshot.player
    if type(player) == "table" and player.available and player.actor
        and utility.sameFloor(player.actor, nextSquare)
        and utility.distanceSq(player.actor, nextSquare) <= spacingSq then return true end
    return false
end

local function roomOf(square)
    local room, ok = U().call(square, "getRoom")
    return ok and room or nil
end

local function checkRoomEntry(actor, state, sourceSquare, nextSquare, intent, now)
    local utility = U()
    local sourceRoom, destinationRoom = roomOf(sourceSquare), roomOf(nextSquare)
    local entering = destinationRoom ~= nil and destinationRoom ~= sourceRoom
    if not entering or intent.urgent == true then
        state.roomEntryKey = nil
        state.roomEntryObserveUntil = nil
        state.roomEntrySweepPhase = nil
        return true, "no_room_entry"
    end

    -- Key the observation to the room transition, not one exact threshold
    -- tile. Double-wide openings legitimately alternate between adjacent route
    -- edges and must share the sweep already in progress.
    local key = "room-entry:" .. tostring(sourceRoom or "outside")
        .. ">" .. tostring(destinationRoom)
    if state.roomEntryKey ~= key then
        state.roomEntryKey = key
        state.roomEntryObserveUntil = now
            + (utility.config("navigationRoomEntryObserveMs") or 450)
        state.roomEntrySweepPhase = 0
    end
    if now < (state.roomEntryObserveUntil or 0) then
        if not stopAndObserve(actor, nextSquare, intent) then
            return false, "room_entry_stop_rejected"
        end
        return nil, "checking_room_entry"
    end

    local phase = tonumber(state.roomEntrySweepPhase) or 0
    if phase < 2 then
        if not utility.stop(actor) then return false, "room_entry_sweep_stop_rejected" end
        local sx, sy = utility.position(sourceSquare)
        local nx, ny = utility.position(nextSquare)
        if sx == nil or sy == nil or nx == nil or ny == nil then
            return false, "room_entry_direction_unavailable"
        end
        local dx, dy = nx - sx, ny - sy
        local length = math.sqrt(dx * dx + dy * dy)
        if length < 0.001 then dx, dy, length = 1, 0, 1 end
        local side = phase == 0 and "left" or "right"
        local accepted = utility.move(actor, "walk", {
            action = "room_sweep",
            sweepSide = side,
            sweepForwardX = dx / length,
            sweepForwardY = dy / length,
            targetSquare = nextSquare,
            stableFacing = true,
            roomEntryCheck = true,
            weaponReady = not insideSecureBase(actor, intent.snapshot),
            supervisorToken = intent and intent.supervisorToken,
        })
        if not accepted then return false, "room_entry_" .. side .. "_sweep_rejected" end
        state.roomEntrySweepPhase = phase + 1
        return nil, "checking_room_entry_" .. side
    end
    intent.roomEntryChecked = true
    return true, "room_entry_clear"
end

local function tacticalStep(actor, state, sourceSquare, nextSquare, afterSquare, kind, intent, now)
    local utility = U()
    local urgent = intent.urgent == true
    local stair = kind == "stairs" or kind == "slope"
        or squareHasStairs(sourceSquare) or squareHasStairs(nextSquare)
        or squareHasSlope(sourceSquare) or squareHasSlope(nextSquare)
    local choke = stair or kind == "door" or kind == "fence"
    local chokeAccepted, chokeOwner = true, nil
    if choke and not urgent then
        chokeAccepted, chokeOwner = reserveChokeCorridor(
            sourceSquare, nextSquare, afterSquare, actor, state, intent, now)
    end
    if choke and not urgent and not chokeAccepted then
        if not stopAndObserve(actor, nextSquare, intent) then
            return false, "choke_reservation_stop_rejected"
        end
        state.chokeQueueSince = state.chokeQueueSince or now
        state.chokeQueueOwner = chokeOwner
        return nil, "holding_choke_queue"
    end
    if not choke then
        state.chokeQueueSince = nil
        releaseChoke(state, actor)
    end
    local roomEntryAccepted, roomEntryStatus = checkRoomEntry(
        actor, state, sourceSquare, nextSquare, intent, now)
    if roomEntryAccepted ~= true then return roomEntryAccepted, roomEntryStatus end
    if stair then
        local key = "stair:" .. tostring(squareKey(nextSquare))
        if not urgent and state.onStairSequence ~= true then
            state.stairObserveKey = key
            state.stairObserveUntil = now + (utility.config("navigationStairObserveMs") or 450)
        end
        state.onStairSequence = true
        if not urgent and now < (state.stairObserveUntil or 0) then
            if not stopAndObserve(actor, afterSquare or nextSquare, intent) then
                return false, "stair_observe_stop_rejected"
            end
            return nil, "checking_stair_landing"
        end
        local crowded = stairCrowded(actor, nextSquare, intent.snapshot)
        if crowded and not urgent then
            state.stairSpacingSince = state.stairSpacingSince or now
            if now - state.stairSpacingSince < (utility.config("navigationChokeReservationMs") or 1400) then
                if not stopAndObserve(actor, afterSquare or nextSquare, intent) then
                    return false, "stair_spacing_stop_rejected"
                end
                return nil, "holding_stair_spacing"
            end
        else
            state.stairSpacingSince = nil
        end
        intent.tacticalStair = true
        intent.keepFacing = true
        intent.facingTarget = afterSquare or nextSquare
        intent.mode = "walk"
        intent.weaponReady = not insideSecureBase(actor, intent.snapshot)
    else
        state.onStairSequence = false
        state.stairObserveKey = nil
        state.stairObserveUntil = nil
        state.stairSpacingSince = nil
    end

    local turn = turnAt(sourceSquare, nextSquare, afterSquare)
    local blind = turn ~= nil and not utility.canSee(actor, afterSquare)
    if blind then
        local key = "corner:" .. tostring(squareKey(nextSquare)) .. ":" .. tostring(squareKey(afterSquare))
        if not urgent and state.cornerObserveKey ~= key then
            state.cornerObserveKey = key
            state.cornerObserveUntil = now + (utility.config("navigationCornerObserveMs") or 350)
        end
        if not urgent and now < (state.cornerObserveUntil or 0) then
            if not stopAndObserve(actor, afterSquare, intent) then
                return false, "corner_observe_stop_rejected"
            end
            return nil, "checking_blind_corner"
        end
        local backed, behind = wallBehind(sourceSquare, afterSquare)
        intent.tacticalCorner = true
        intent.tacticalStrafe = true
        intent.keepFacing = true
        intent.facingTarget = afterSquare
        intent.cornerTurn = turn
        intent.wallAtBack = backed
        intent.wallSquare = behind
        intent.mode = "sneak"
        intent.weaponReady = not insideSecureBase(actor, intent.snapshot)
    else
        state.cornerObserveKey = nil
        state.cornerObserveUntil = nil
    end
    return true, stair and "tactical_stair" or (blind and "tactical_corner" or "normal")
end

local function configureTacticalRetreat(actor, sourceSquare, nextSquare, afterSquare, kind, intent)
    local action = tostring(intent.action or "")
    if action ~= "combat_retreat" and action ~= "ordered_retreat" then return false end
    if intent.survivalCritical == true then
        -- An overrun is an escape, not a fighting withdrawal. Turning toward
        -- the route lets vanilla use the run blend instead of a slower aimed
        -- backstep while the companion is already being overwhelmed.
        intent.tacticalRetreat = nil
        intent.tacticalStrafe = nil
        intent.keepFacing = nil
        intent.facingTarget = nil
        intent.weaponReady = false
        return false
    end

    -- Backward movement is reserved for flat, visible, obstacle-free ground.
    -- At a choke point the companion must watch its feet, turn normally and
    -- let the door/window/stair/vegetation animation own the crossing.
    local snapshot = type(intent.snapshot) == "table" and intent.snapshot or {}
    local threat = intent.awayFrom or intent.facingTarget
    local immediate = tonumber(snapshot.closeImmediateCount)
        or tonumber(snapshot.immediateCount) or #(snapshot.immediateAttackers or {})
    local unsafe = kind ~= "open" or squareHasStairs(sourceSquare) or squareHasStairs(nextSquare)
        or squareHasBush(sourceSquare) or squareHasBush(nextSquare)
        or squareNearTree(sourceSquare) or squareNearTree(nextSquare)
        or squareNearVehicle(sourceSquare) or squareNearVehicle(nextSquare)
        or snapshot.encircled == true
        or immediate > (U().config("combatTacticalRetreatMaxImmediate") or 1)
    local distance = threat and U().distance(actor, threat) or math.huge
    unsafe = unsafe or threat == nil or not U().sameFloor(actor, threat)
        or not U().canSee(actor, threat)
        or distance < (U().config("combatTacticalRetreatMinDistance") or 1.45)
        or distance > (U().config("combatTacticalRetreatMaxDistance") or 6.5)
        or U().edgeBlocked(sourceSquare, nextSquare)
        or turnAt(sourceSquare, nextSquare, afterSquare) ~= nil

    if unsafe then
        intent.tacticalRetreat = nil
        intent.tacticalStrafe = nil
        intent.keepFacing = nil
        intent.facingTarget = nil
        intent.weaponReady = false
        return false
    end
    intent.tacticalRetreat = true
    intent.tacticalStrafe = true
    intent.keepFacing = true
    intent.facingTarget = threat
    intent.weaponReady = true
    intent.mode = "walk"
    return true
end

local function changedGoal(state, goalSquare)
    return not state.goalSquare or not sameSquare(state.goalSquare, goalSquare)
end

-- Collision recovery must temporarily own a fixed nearby destination. Without
-- this waypoint, Follow replaces the lateral escape square with the leader's
-- freshly sampled position every update and can pull the actor straight back
-- into the fence or corner it is trying to clear.
local function selectRecoveryWaypoint(actor, state, actorSquare, goalSquare, intent, now)
    local utility = U()
    local x, y, z = utility.position(actorSquare)
    if x == nil then return nil end
    local reference = state.lastAttemptTo or goalSquare
    local rx, ry = utility.position(reference)
    local dx, dy = (rx or x) - x, (ry or y) - y
    local forwardX, forwardY
    if math.abs(dx) >= math.abs(dy) then
        forwardX, forwardY = dx >= 0 and 1 or -1, 0
    else
        forwardX, forwardY = 0, dy >= 0 and 1 or -1
    end
    local offsets = {
        { -forwardY, forwardX }, { forwardY, -forwardX },
        { -forwardX, -forwardY }, { forwardX, forwardY },
    }
    if utility.stableHash(utility.idOf(actor)) % 2 == 1 then
        offsets[1], offsets[2] = offsets[2], offsets[1]
    end
    for _, offset in ipairs(offsets) do
        local square = utility.gridSquare(x + offset[1], y + offset[2], z)
        if square then
            local _, kind = barrierBetween(actorSquare, square)
            if kind == "open" and select(1, passableEdge(actorSquare, square)) == true
                and utility.isSquareFree(square)
                and not utility.edgeBlocked(actorSquare, square)
                and not personalSpaceBlocker(actor, square, intent and intent.snapshot) then
                state.recoveryWaypoint = square
                state.recoveryWaypointExpires = now
                    + (utility.config("navigationRecoveryWaypointMs") or 5000)
                return square
            end
        end
    end
    return nil
end
Navigation._selectRecoveryWaypointForRequest = selectRecoveryWaypoint
Navigation._selectRecoveryWaypointForTests = selectRecoveryWaypoint

local function activeRecoveryWaypoint(actor, state, now, intent)
    local square = state and state.recoveryWaypoint
    if square == nil then return nil end
    local utility = U()
    local actorSquare = utility.squareOf(actor)
    local expires = tonumber(state.recoveryWaypointExpires) or 0
    local valid = actorSquare ~= nil and now <= expires
        and utility.sameFloor(actorSquare, square)
        and utility.isSquareFree(square)
        and not personalSpaceBlocker(actor, square, intent and intent.snapshot)
    if valid and not sameSquare(actorSquare, square)
        and not utility.arrived(actor, square, {
            targetKind = "square",
            distance = utility.config("navigationArrivalDistance") or 0.6,
        }) then
        return square
    end
    state.recoveryWaypoint = nil
    state.recoveryWaypointExpires = nil
    state.recoveryWaypointReason = nil
    return nil
end
Navigation._activeRecoveryWaypointForRequest = activeRecoveryWaypoint
Navigation._activeRecoveryWaypointForTests = activeRecoveryWaypoint

local function resetRouteProjection(state)
    state.routeCrossTrack, state.routeProjection, state.lastRouteProjection = nil, nil, nil
    state.crossTrackSince, state.reverseProgressSince = nil, nil
    state.routeProjectionSegment, state.routeProjectionAt = nil, nil
end
-- The large request dispatcher is at Kahlua's 60-upvalue ceiling. Share this
-- through its existing SC upvalue instead of capturing one more local helper.
Navigation._resetRouteProjection = resetRouteProjection

local function clearMovementTransients(actor, state)
    resetRouteProjection(state)
    if state.nativeLease and SC.NativeActions
        and type(SC.NativeActions.stopDirect) == "function" then
        pcall(SC.NativeActions.stopDirect, actor, { preservePosture = true })
    end
    if state.pendingInteraction then release(state.pendingInteraction.object, actor) end
    state.pendingInteraction = nil
    releaseStep(state, actor)
    releaseChoke(state, actor)
    state.yieldSince = nil
    state.yieldBlocker = nil
    state.cornerObserveKey = nil
    state.cornerObserveUntil = nil
    state.roomEntryKey = nil
    state.roomEntryObserveUntil = nil
    state.roomEntrySweepPhase = nil
    state.stairObserveKey = nil
    state.stairObserveUntil = nil
    state.stairSpacingSince = nil
    state.onStairSequence = false
    state.pathSearch = nil
    state.pathSearchHolding = nil
    state.pathGoalSquare = nil
    state.nativeLease = nil
    state.openDoorDirectKey = nil
    state.openDoorDirectUntil = nil
    state.openDoorRetryKey = nil
    state.openDoorRetryAttempts = nil
end

local function holdForPathSearch(actor, state)
    if state.pathSearchHolding == true then return true end
    local stopped = false
    if SC.NativeActions and type(SC.NativeActions.stopDirect) == "function" then
        local ok, result = pcall(SC.NativeActions.stopDirect, actor, { preservePosture = true })
        stopped = ok and result == true
    else
        stopped = U().stop(actor) == true
    end
    state.pathSearchHolding = stopped
    return stopped
end

local function updateProgress(actor, state, now)
    local utility = U()
    local x, y, z = utility.position(actor)
    if not x then return false end
    local currentSquare = utility.squareOf(actor)
    if currentSquare and state.lastAttemptFrom and state.lastAttemptTo
        and sameSquare(currentSquare, state.lastAttemptTo) then
        if state.openDoorDirectKey
            == edgeKey(state.lastAttemptFrom, state.lastAttemptTo) then
            state.openDoorDirectKey = nil
            state.openDoorDirectUntil = nil
            state.openDoorRetryKey = nil
            state.openDoorRetryAttempts = nil
        end
        local object, kind = barrierBetween(state.lastAttemptFrom, state.lastAttemptTo)
        rememberRouteEdge(state, state.lastAttemptFrom, state.lastAttemptTo,
            true, kind, object, now)
        state.lastAttemptFrom, state.lastAttemptTo = nil, nil
        state.lastMovementReason = nil
    end
    if not state.lastX then
        state.lastX, state.lastY, state.lastZ = x, y, z
        state.lastProgressAt = now
        return true
    end
    local dx, dy, dz = x - state.lastX, y - state.lastY, (z or 0) - (state.lastZ or 0)
    if dx * dx + dy * dy + dz * dz >= 0.04 then
        state.lastX, state.lastY, state.lastZ = x, y, z
        state.lastProgressAt = now
        state.stuckAttempts = 0
        return true
    end
    return false
end

local function pathTelemetry(actor)
    if SC.NativeActions and type(SC.NativeActions.pathTelemetry) == "function" then
        local ok, telemetry = pcall(SC.NativeActions.pathTelemetry, actor)
        if ok and type(telemetry) == "table" then return telemetry end
    end
    local behavior, behaviorOk = U().call(actor, "getPathFindBehavior2")
    if not behaviorOk or behavior == nil then return { available = false } end
    local result = { available = true, behavior = behavior }
    local checks = {
        shouldBeMoving = "shouldBeMoving",
        hasStartedMoving = "hasStartedMoving",
        turningToObstacle = "isTurningToObstacle",
        movingUsingPathFind = "isMovingUsingPathFind",
    }
    for key, methodName in pairs(checks) do
        local value, ok = U().call(behavior, methodName)
        if ok then result[key] = value == true end
    end
    result.active = result.movingUsingPathFind == true or result.turningToObstacle == true
        or (result.movingUsingPathFind == nil and result.shouldBeMoving == true)
    result.pending = result.active == true and result.hasStartedMoving == false
    return result
end

local function nativeTargets(targets)
    if type(targets) ~= "table" then return {} end
    if targets[1] ~= nil then return targets end
    return { targets }
end

-- A moving target (following the player) must not commit to a long native path
-- toward a goal captured when the lease began: when the leader turns, the actor
-- otherwise keeps running toward the stale goal until it drifts far enough away or
-- the lease times out (seen in playtests as "I turn, the companion keeps running
-- straight into a wall"). Such a lease re-aims on a much smaller goal drift and
-- expires much sooner so it tracks the leader instead of overshooting.
local function isMovingTargetIntent(context)
    return type(context) == "table"
        and (context.movingTarget == true or context.followRecovery == true
            or context.player ~= nil or context.action == "follow_formation"
            or context.action == "regroup")
end

local function goalResetDistance(context)
    if isMovingTargetIntent(context) then
        return U().config("navigationMovingGoalResetDistance") or 1.5
    end
    return U().config("navigationGoalResetDistance") or 3.0
end

local function goalsShareHeading(actor, oldGoal, newGoal)
    local ax, ay, az = U().position(actor)
    local ox, oy, oz = U().position(oldGoal)
    local nx, ny, nz = U().position(newGoal)
    if ax == nil or ox == nil or nx == nil
        or math.floor(az or 0) ~= math.floor(oz or 0)
        or math.floor(az or 0) ~= math.floor(nz or 0) then return false end
    local odx, ody, ndx, ndy = ox - ax, oy - ay, nx - ax, ny - ay
    local oldLength = math.sqrt(odx * odx + ody * ody)
    local newLength = math.sqrt(ndx * ndx + ndy * ndy)
    if oldLength <= 0.6 or newLength <= 0.6 then return false end
    return (odx * ndx + ody * ndy) / (oldLength * newLength) >= 0.35
end

local function pathSearchBounds(pending)
    local leaseMs = tonumber(U().config("navigationPathSearchLeaseMs")) or 6500
    local hardMs = tonumber(U().config("navigationPathSearchHardMs")) or 30000
    if type(pending) == "table" and pending.followRouting == true then
        leaseMs = math.min(leaseMs,
            tonumber(U().config("navigationFollowPathSearchLeaseMs")) or 2500)
        hardMs = math.min(hardMs,
            tonumber(U().config("navigationFollowPathSearchHardMs")) or 5000)
    end
    return leaseMs, math.max(leaseMs, hardMs)
end

-- The actor is deliberately stationary while incremental A* yields. Let a
-- forward-moving formation goal drift a few tiles without discarding that whole
-- frontier; the completed route is repaired to the latest goal immediately.
local function usefulPendingMovingSearch(actor, state, goalSquare, context, now)
    local pending = state and state.pathSearch
    local route = pending and pending.route
    local oldGoal = route and route.goalSquare
    if oldGoal == nil or not isMovingTargetIntent(context) then return false end
    local startedAt = tonumber(pending.startedAt)
    local progressAt = tonumber(pending.progressAt) or startedAt
    local leaseMs, hardMs = pathSearchBounds(pending)
    if startedAt == nil or progressAt == nil or now - startedAt < 0
        or now - progressAt < 0 or now - progressAt > leaseMs
        or now - startedAt > hardMs then
        return false
    end
    local sourceSquare = U().squareOf(actor)
    if sourceSquare == nil or route.startKey ~= squareKey(sourceSquare) then return false end
    local ox, oy, oz = U().position(oldGoal)
    local nx, ny, nz = U().position(goalSquare)
    if ox == nil or nx == nil or math.floor(oz or 0) ~= math.floor(nz or 0) then
        return false
    end
    local drift = math.abs(math.floor(nx) - math.floor(ox))
        + math.abs(math.floor(ny) - math.floor(oy))
    local limit = math.max(1,
        math.floor(tonumber(U().config("navigationMovingRouteRepairDistance")) or 4))
    return drift <= limit and goalsShareHeading(actor, oldGoal, goalSquare)
end
Navigation._usefulPendingMovingSearchForRequest = usefulPendingMovingSearch
Navigation._usefulPendingMovingSearchForTests = usefulPendingMovingSearch

-- A formation destination moves a little on nearly every leader sample. Rebuilding
-- a complete A* frontier for each small drift wastes the already-valid route and
-- creates visible search pauses. Trim to an existing unconsumed goal, or safely
-- extend the endpoint with a short cardinal tail. Never append a retracing loop.
local function tryRepairMovingPath(actor, state, sourceSquare, goalSquare, context, now)
    if not isMovingTargetIntent(context) or type(state.path) ~= "table"
        or #state.path == 0 or not state.pathGoalSquare then return false end
    local utility = U()
    local oldX, oldY, oldZ = utility.position(state.pathGoalSquare)
    local goalX, goalY, goalZ = utility.position(goalSquare)
    local sourceX, sourceY = utility.position(sourceSquare)
    if oldX == nil or goalX == nil or sourceX == nil
        or math.floor(oldZ or 0) ~= math.floor(goalZ or 0) then return false end
    oldX, oldY = math.floor(oldX), math.floor(oldY)
    goalX, goalY = math.floor(goalX), math.floor(goalY)
    local manhattan = math.abs(goalX - oldX) + math.abs(goalY - oldY)
    local limit = math.max(1,
        math.floor(utility.config("navigationMovingRouteRepairDistance") or 4))
    if manhattan == 0 or manhattan > limit then return false end

    local oldVectorX, oldVectorY = oldX - sourceX, oldY - sourceY
    local newVectorX, newVectorY = goalX - sourceX, goalY - sourceY
    local oldLength = math.sqrt(oldVectorX * oldVectorX + oldVectorY * oldVectorY)
    local newLength = math.sqrt(newVectorX * newVectorX + newVectorY * newVectorY)
    if oldLength > 0.75 and newLength > 0.75
        and oldVectorX * newVectorX + oldVectorY * newVectorY < 0 then return false end

    local startedAt = utility.nowMs()
    local current = state.path[#state.path]
    if not sameSquare(current, state.pathGoalSquare) then return false end
    local activeIndex = math.max(2, math.floor(tonumber(state.pathIndex) or 2))
    local firstRetained = math.min(#state.path, activeIndex - 1)
    local maximumNodes = math.max(8,
        math.floor(tonumber(utility.config("navigationMovingRouteMaxNodes")) or 256))
    -- Keep one predecessor for continuous segment projection, not the entire
    -- route history. Decline oversized legacy tails and let normal replanning
    -- recover rather than spending an unbounded frame scanning them.
    if #state.path - firstRetained + 1 > maximumNodes then return false end
    local existingGoal
    for index = firstRetained, #state.path do
        if sameSquare(state.path[index], goalSquare) then
            if index < activeIndex then return false end
            existingGoal = index
            break
        end
    end
    local function commitRepair(tail, lastRetained, kind)
        local oldCount = #state.path
        local repaired = {}
        for index = firstRetained, lastRetained do
            repaired[#repaired + 1] = state.path[index]
        end
        for _, square in ipairs(tail) do repaired[#repaired + 1] = square end
        if #repaired > maximumNodes then return false end
        state.path = repaired
        state.pathIndex = activeIndex - firstRetained + 1
        state.pathGoalSquare = goalSquare
        resetRouteProjection(state)
        state.routeRepairCount = (state.routeRepairCount or 0) + 1
        state.lastRouteRepairAt, state.lastRouteRepairKind = now, kind
        state.lastRouteRepairAppended = #tail
        state.lastRouteRepairTrimmed = oldCount - lastRetained
        state.lastRouteRepairCompacted = firstRetained - 1
        recordMovement(actor, "route_repaired", {
            status = kind, targetSquare = goalSquare,
            detail = "nodes=" .. tostring(#repaired) .. " appended=" .. tostring(#tail)
                .. " trimmed=" .. tostring(oldCount - lastRetained)
                .. " compacted=" .. tostring(firstRetained - 1),
        })
        if SC.Performance and type(SC.Performance.record) == "function" then
            SC.Performance.record("navigation.repair", utility.idOf(actor),
                utility.nowMs() - startedAt, #tail, false)
        end
        return true
    end
    if existingGoal then return commitRepair({}, existingGoal, "trimmed") end
    local repairSlice = P().newSlice({ clock = utility.nowMs },
        utility.config("navigationSliceBudgetMs") or 2)
    local tail, seen = {}, {}
    for index = firstRetained, #state.path do
        local key = squareKey(state.path[index])
        if key then seen[key] = true end
    end
    for _ = 1, limit do
        if sameSquare(current, goalSquare) then break end
        local cx, cy, cz = utility.position(current)
        if cx == nil then return false end
        cx, cy = math.floor(cx), math.floor(cy)
        local candidates = {}
        if goalX ~= cx then
            candidates[#candidates + 1] = utility.gridSquare(
                cx + (goalX > cx and 1 or -1), cy, cz)
        end
        if goalY ~= cy then
            candidates[#candidates + 1] = utility.gridSquare(
                cx, cy + (goalY > cy and 1 or -1), cz)
        end
        local best, bestScore
        for _, candidate in ipairs(candidates) do
            if P().sliceExpired(repairSlice) then return false end
            local key = squareKey(candidate)
            if candidate and not seen[key] then
                local passable, cost = passableEdge(current, candidate,
                    context.urgent == true
                        and (utility.config("navigationEmergencyVegetationScale") or 0.2) or 1, {
                        actor = actor,
                        blockedEdges = state.blockedEdges,
                        blockedSquares = state.blockedSquares,
                        routeMemory = state.routeMemory,
                        now = now,
                        allowOccupiedGoal = sameSquare(candidate, goalSquare),
                    })
                local score = passable and (cost + heuristic(candidate, goalSquare)) or math.huge
                if score < (bestScore or math.huge) then best, bestScore = candidate, score end
            end
        end
        if not best then return false end
        tail[#tail + 1] = best
        seen[squareKey(best)] = true
        current = best
    end
    if not sameSquare(current, goalSquare) then return false end
    return commitRepair(tail, #state.path, "extended")
end

-- Native collision steering may place the actor beside (or farther along) the
-- Lua path. Rejoin a validated nearby suffix instead of discarding the route and
-- starting another whole search.
local function tryReusePathSuffix(actor, state, sourceSquare, context, now)
    if type(state.path) ~= "table" then return false end
    local startIndex = math.max(2, tonumber(state.pathIndex) or 2)
    local finishIndex = math.min(#state.path, startIndex
        + math.max(1, math.floor(U().config("navigationRouteSuffixLookahead") or 8)))
    local selected, exact
    for index = startIndex, finishIndex do
        if sameSquare(sourceSquare, state.path[index]) then
            selected, exact = index + 1, true
            break
        end
    end
    if not selected then
        -- Several consecutive suffix tiles can be adjacent once diagonal steps
        -- are legal. Prefer the furthest validated one so a collision detour does
        -- not make the companion step backwards before resuming the route.
        for index = finishIndex, startIndex, -1 do
            local candidate = state.path[index]
            if adjacentStep(sourceSquare, candidate) then
                local passable = passableEdge(sourceSquare, candidate,
                    context.urgent == true
                        and (U().config("navigationEmergencyVegetationScale") or 0.2) or 1, {
                        actor = actor,
                        blockedEdges = state.blockedEdges,
                        blockedSquares = state.blockedSquares,
                        routeMemory = state.routeMemory,
                        now = now,
                        allowOccupiedGoal = index == #state.path,
                    })
                if passable then selected = index break end
            end
        end
    end
    if not selected then return false end
    releaseStep(state, actor)
    state.pathIndex = selected
    resetRouteProjection(state)
    state.routeReuseCount = (state.routeReuseCount or 0) + 1
    state.lastRouteReuseAt = now
    recordMovement(actor, "route_suffix_reused", {
        status = exact and "exact" or "adjacent", nextSquare = state.path[selected],
        detail = "index=" .. tostring(selected),
    })
    if SC.Performance and type(SC.Performance.record) == "function" then
        SC.Performance.record("navigation.reuse", U().idOf(actor), 0, 1, false)
    end
    return true
end

local function correctRouteProjection(actor, state, sourceSquare, context, now)
    if type(state.path) ~= "table" or not state.path[state.pathIndex or 2]
        or state.nativeLease or state.pendingInteraction then
        resetRouteProjection(state)
        return true
    end
    local index = math.max(2, tonumber(state.pathIndex) or 2)
    local previous, following = state.path[index - 1], state.path[index]
    if Navigation.edgeAffordance(previous, following) then
        resetRouteProjection(state)
        return true
    end
    local segment = tostring(squareKey(previous)) .. ">" .. tostring(squareKey(following))
    if state.routeProjectionSegment ~= segment then resetRouteProjection(state) end
    state.routeProjectionSegment = segment
    local utility = U()
    local ax, ay = utility.position(actor)
    local px, py = utility.position(previous)
    local nx, ny = utility.position(following)
    if ax == nil or px == nil or nx == nil then resetRouteProjection(state) return true end
    px, py, nx, ny = px + 0.5, py + 0.5, nx + 0.5, ny + 0.5
    local dx, dy = nx - px, ny - py
    local lengthSq = dx * dx + dy * dy
    if lengthSq < 0.01 then resetRouteProjection(state) return true end
    local projection = ((ax - px) * dx + (ay - py) * dy) / lengthSq
    local clamped = math.max(0, math.min(1, projection))
    local closestX, closestY = px + dx * clamped, py + dy * clamped
    local crossTrack = math.sqrt((ax - closestX) ^ 2 + (ay - closestY) ^ 2)
    state.routeCrossTrack = crossTrack
    state.routeProjection = projection
    state.routeProjectionAt = now

    if projection > 1.05 and index < #state.path then
        local oldIndex = index
        while index < #state.path do
            local candidate = state.path[index + 1]
            if not candidate or utility.distance(actor, candidate) > 1.15 then break end
            index = index + 1
        end
        state.pathIndex = math.max(oldIndex + 1, index)
        state.routeOvershootCount = (state.routeOvershootCount or 0) + 1
        state.lastRouteOvershootAt = now
        resetRouteProjection(state)
        recordMovement(actor, "route_overshoot", {
            status = "advanced_suffix", nextSquare = state.path[state.pathIndex],
            detail = "index=" .. tostring(state.pathIndex)
                .. " cross-track=" .. string.format("%.2f", crossTrack),
        })
        return true
    end

    local crossLimit = tonumber(utility.config("navigationRouteCrossTrackDistance")) or 0.75
    if crossTrack > crossLimit then
        state.crossTrackSince = state.crossTrackSince or now
    else
        state.crossTrackSince = nil
    end
    if state.lastRouteProjection ~= nil and projection < state.lastRouteProjection - 0.12 then
        state.reverseProgressSince = state.reverseProgressSince or now
    elseif projection >= (state.lastRouteProjection or -math.huge) then
        state.reverseProgressSince = nil
    end
    state.lastRouteProjection = projection
    local unstableMs = tonumber(utility.config("navigationRouteInstabilityMs")) or 350
    if (state.crossTrackSince and now - state.crossTrackSince >= unstableMs)
        or (state.reverseProgressSince and now - state.reverseProgressSince >= unstableMs) then
        local reason = state.crossTrackSince and "cross_track" or "reverse_progress"
        releaseStep(state, actor)
        state.path, state.pathGoalSquare, state.pathSearch = nil, nil, nil
        state.pathIndex, state.nextRepathAt = 1, 0
        state.routeRestartCount = (state.routeRestartCount or 0) + 1
        state.lastRouteRestartAt, state.lastRouteRestartReason = now, reason
        resetRouteProjection(state)
        recordMovement(actor, "route_restarted", {
            status = reason, detail = "cross-track=" .. string.format("%.2f", crossTrack),
        })
        return false
    end
    return true
end
Navigation._repairMovingPathForTests = tryRepairMovingPath
Navigation._reusePathSuffixForTests = tryReusePathSuffix
Navigation._correctRouteProjectionForTests = correctRouteProjection
-- Test seam (follow tracking): a moving target must re-plan on a much smaller goal
-- drift than a static goal so a following companion turns with the leader.
Navigation._goalResetDistanceForTests = goalResetDistance

-- Test seam (occupied-goal handling, review 3.2): static traversability and dynamic
-- occupancy are separate -- a mover adds crowd cost (and none when the goal is
-- allowed to be occupied), while a static blocker is always impassable.
Navigation._passableEdgeForTests = passableEdge

-- Test seams (heap A*, review 3.3): the open-set min-heap must drain in exact
-- (f, h, seq) order so the search keeps producing the same paths as the old scan.
Navigation._heapPushForTests = heapPush
Navigation._heapPopForTests = heapPop

-- Test seams (stealth danger overlay, review 3.5): a long search's overlay prunes
-- dead/departed threats on a throttled cadence instead of scoring a frozen snapshot.
Navigation._buildStealthOverlayForTests = buildStealthOverlay
Navigation._refreshStealthOverlayForTests = refreshStealthOverlay
Navigation._stealthThreatPenaltyForTests = stealthThreatPenalty

local function rotatedVector(x, y, radians)
    local cosine, sine = math.cos(radians), math.sin(radians)
    return x * cosine - y * sine, x * sine + y * cosine
end

-- Combat spacing runs on a player-like reflex cadence and must not wait for A*.
-- Probe a short continuous step, then try deterministic nearby headings. The
-- actor's stable side preference prevents alternating left/right around the same
-- obstacle on consecutive combat ticks.
function Navigation.combatVector(actor, target, kind, snapshot)
    local utility = U()
    local ax, ay, az = utility.position(actor)
    local tx, ty = utility.position(target)
    if ax == nil or tx == nil then return nil, nil, false, "position_unavailable" end
    local towardX, towardY = tx - ax, ty - ay
    local length = math.sqrt(towardX * towardX + towardY * towardY)
    if length < 0.001 then return nil, nil, false, "overlapping_target" end
    towardX, towardY = towardX / length, towardY / length
    local side = utility.stableHash(utility.idOf(actor)) % 2 == 0 and 1 or -1
    local baseX, baseY = towardX, towardY
    if kind == "backstep" then
        baseX, baseY = -towardX, -towardY
    elseif kind == "kite" then
        baseX, baseY = -towardY * side, towardX * side
    end
    local angles = kind == "kite"
        and { 0, math.rad(45), -math.rad(45), math.pi }
        or { 0, side * math.rad(45), -side * math.rad(45),
            side * math.rad(90), -side * math.rad(90) }
    local probeDistance = math.max(0.1,
        tonumber(utility.config("combatSteeringProbeDistance")) or 0.45)
    local sourceSquare = utility.squareOf(actor)
    local nativeProbeAvailable = utility.hasMethod(actor, "isCompanionMovementClear")
    local best, bestCost
    local threats = type(snapshot) == "table" and snapshot.threats or nil
    for index, angle in ipairs(angles) do
        local dx, dy = rotatedVector(baseX, baseY, angle)
        local toX, toY = ax + dx * probeDistance, ay + dy * probeDistance
        local clear = true
        if nativeProbeAvailable then
            local nativeClear, called = utility.call(
                actor, "isCompanionMovementClear", toX, toY, az or 0)
            clear = called and nativeClear == true
        end
        local destination = utility.gridSquare(math.floor(toX), math.floor(toY), az or 0)
        if clear and sourceSquare and destination and not sameSquare(sourceSquare, destination) then
            clear = select(1, passableEdge(sourceSquare, destination, 1, {
                actor = actor, now = utility.nowMs(), allowOccupiedGoal = false,
            })) == true
        end
        local danger = index * 0.001
        if clear and type(threats) == "table" then
            for threatIndex = 1, math.min(#threats, 12) do
                local threat = threats[threatIndex]
                local other = threat and threat.actor
                if other and not utility.isDead(other) and utility.sameFloor(actor, other)
                    and not (kind == "approach" and other == target) then
                    local ox, oy = utility.position(other)
                    if ox then
                        local before = math.sqrt((ox - ax)^2 + (oy - ay)^2)
                        local after = math.sqrt((ox - toX)^2 + (oy - toY)^2)
                        if utility.bodyBlocksSegment(other, actor, toX, toY, 0.6)
                            or (before < 1.3 and after < before - 0.05)
                            or (other == target and after < before - 0.02) then
                            clear = false
                            break
                        end
                        danger = danger + math.max(0, 2.25 - after)^2
                    end
                end
            end
        end
        if clear and (best == nil or danger < bestCost) then
            best, bestCost = { x = dx, y = dy, index = index }, danger
            if threats == nil then break end
        end
    end
    if best then
        if best.index > 1 then
            local state = stateFor(actor)
            state.combatSteerCount = (state.combatSteerCount or 0) + 1
            state.lastCombatSteerAt = utility.nowMs()
            state.lastCombatSteerKind = kind
            recordMovement(actor, "combat_micro_steer", {
                action = kind, candidate = best.index,
            })
        end
        return best.x, best.y, best.index > 1, best.index > 1 and "steered" or "direct"
    end
    return nil, nil, false, "no_clear_alternative"
end

local function beginNativeLease(state, targets, fromSquare, toSquare, ultimateGoal,
        now, reason, multiGoal, movingTarget, affordance, actor, intent)
    local list = nativeTargets(targets)
    local leaseMs = affordance == "multi_level"
        and (U().config("navigationMultiLevelLeaseMs") or 30000)
        or (movingTarget and (U().config("navigationMovingLeaseMs") or 2500)
            or (U().config("navigationNativeLeaseMs") or 6500))
    local worldX, worldY, worldZ = U().position(actor or fromSquare)
    local _, goalDistance = U().arrived(actor or fromSquare, ultimateGoal, {
        targetKind = "square", distance = 0,
    })
    state.nativeLease = {
        targets = list,
        fromSquare = fromSquare,
        toSquare = toSquare,
        ultimateGoal = ultimateGoal,
        ultimateGoalKey = squareKey(ultimateGoal),
        startedAt = now,
        expires = now + leaseMs,
        reason = reason or "native_corridor",
        multiGoal = multiGoal == true,
        movingTarget = movingTarget == true,
        affordance = affordance,
        progressSquareKey = squareKey(fromSquare),
        progressAt = now,
        positionProgressAt = now,
        activityHeartbeatAt = now,
        lastWorldX = worldX,
        lastWorldY = worldY,
        lastWorldZ = worldZ,
        lastGoalDistance = goalDistance,
        leaseMs = leaseMs,
        cohortKey = intent and intent.cohortKey,
        cqbRole = intent and intent.cqbRole,
        groupParticipants = intent and intent.groupParticipants,
        urgent = intent and intent.urgent == true,
        supervisorToken = intent and intent.supervisorToken,
    }
end

local function nativeLeaseArrival(actor, lease)
    local arrival = U().config("navigationArrivalDistance") or 0.6
    for _, target in ipairs(lease and lease.targets or {}) do
        local reached = U().arrived(actor, target, {
            targetKind = "square", distance = arrival,
        })
        -- getSquare() changes immediately as the character centre crosses the
        -- tile boundary. At a door that is too early: stopping PathFindBehavior2
        -- there leaves half the collision capsule in the leaf and the next pulse
        -- walks back to retry. Require continuous clearance through the door plane.
        if reached and lease.affordance == "door"
            and not actorClearOfDoorway(actor, lease) then reached = false end
        if reached then
            return target
        end
    end
    return nil
end

-- PathFindBehavior2 may need several frames before it publishes an active path.
-- A running leader can move the formation goal beyond the normal drift threshold
-- during that startup window. Keep the just-issued path when both goals are still
-- ahead in the same general direction; a turn or reversal still cancels at once.
local function usefulMovingGoalDuringStart(actor, lease, goalSquare, now)
    if not lease or lease.movingTarget ~= true then return false end
    local telemetry = pathTelemetry(actor)
    local grace = (telemetry.pending == true or lease.wasPending == true)
        and (tonumber(U().config("navigationNativePendingMs")) or 6500)
        or (tonumber(U().config("navigationNativeStartGraceMs")) or 650)
    if now - (tonumber(lease.startedAt) or now) >= grace then return false end
    return goalsShareHeading(actor, lease.ultimateGoal, goalSquare)
end

local function maintainNativeLease(actor, state, goalSquare, now)
    local lease = state.nativeLease
    if not lease then return nil, nil end
    local goalMoved = lease.ultimateGoalKey and squareKey(goalSquare) ~= lease.ultimateGoalKey
        and lease.ultimateGoal and U().distance(lease.ultimateGoal, goalSquare)
            >= goalResetDistance(lease)
    if goalMoved and not usefulMovingGoalDuringStart(actor, lease, goalSquare, now) then
        -- Cancelling only the Lua lease leaves PathFindBehavior2 running toward
        -- its old destination while the replacement A* search yields over later
        -- frames. Stop the engine-owned path first so a follower cannot walk far
        -- away in a straight line during recalculation.
        if SC.NativeActions and type(SC.NativeActions.stopDirect) == "function" then
            pcall(SC.NativeActions.stopDirect, actor, { preservePosture = true })
        end
        state.nativeLease = nil
        return "cancelled", "native_goal_changed"
    elseif goalMoved then
        lease.deferredGoalSquare = goalSquare
        lease.deferredGoalKey = squareKey(goalSquare)
    end
    if lease.nativePaused == true then
        if now < (tonumber(lease.passagePausedUntil) or 0) then
            return "active", "holding_stair_passage"
        end
        state.nativeLease = nil
        return "cancelled", "native_stair_admission_retry"
    end
    local arrived = nativeLeaseArrival(actor, lease)
    if arrived then
        markActorPassage(actor, state, now)
        rememberRouteEdge(state, lease.fromSquare,
            lease.multiGoal and arrived or lease.toSquare,
            true, lease.reason, nil, now)
        if SC.NativeActions and type(SC.NativeActions.stopDirect) == "function" then
            pcall(SC.NativeActions.stopDirect, actor, { preservePosture = true })
        end
        state.nativeLease = nil
        state.lastProgressAt = now
        return "arrived", arrived
    end
    if lease.affordance == "door" then
        local currentDoor, currentKind = barrierBetween(lease.fromSquare, lease.toSquare)
        if currentKind == "door" and currentDoor ~= nil and not objectOpen(currentDoor) then
            -- The edge was validated while open, but doors are mutable.  Stop the
            -- stale engine path immediately and retain the Lua route so this same
            -- request can reopen/reclassify the threshold without a stall timeout
            -- or a false static-edge blacklist.
            if SC.NativeActions and type(SC.NativeActions.stopDirect) == "function" then
                pcall(SC.NativeActions.stopDirect, actor, { preservePosture = true })
            end
            state.nativeLease = nil
            state.openDoorDirectKey, state.openDoorDirectUntil = nil, nil
            state.openDoorRetryKey, state.openDoorRetryAttempts = nil, nil
            state.nextRepathAt = 0
            state.lastProgressAt = now
            recordMovement(actor, "portal_state_changed", {
                blocker = "door", status = "door_closed_during_native_path",
                targetSquare = lease.toSquare,
            })
            return "cancelled", "door_closed_retry"
        end
    end
    local currentSquare = U().squareOf(actor)
    local currentKey = squareKey(currentSquare)
    local progressed = false
    if currentKey and currentKey ~= lease.progressSquareKey then
        lease.progressSquareKey = currentKey
        progressed = true
        markActorPassage(actor, state, now)
    end
    local worldX, worldY, worldZ = U().position(actor)
    local progressDistance = tonumber(U().config("navigationProgressDistance")) or 0.08
    if worldX and lease.lastWorldX then
        local dx, dy = worldX - lease.lastWorldX, worldY - lease.lastWorldY
        if dx * dx + dy * dy >= progressDistance * progressDistance
            or math.abs((worldZ or 0) - (lease.lastWorldZ or 0)) >= 0.1 then
            progressed = true
        end
    end
    local _, goalDistance = U().arrived(actor, lease.ultimateGoal, {
        targetKind = "square", distance = 0,
    })
    local goalProgress = tonumber(U().config("navigationGoalProgressDistance")) or 0.05
    if goalDistance < math.huge and lease.lastGoalDistance
        and goalDistance <= lease.lastGoalDistance - goalProgress then
        progressed = true
    end
    local actorState = U().movementStateBlocker(actor)
    local telemetry = pathTelemetry(actor)
    lease.telemetry = telemetry
    if telemetry.pathNextIsSet == true and telemetry.pathNextX ~= nil
        and telemetry.pathNextY ~= nil then
        local _, _, actorZ = U().position(actor)
        local nextSquare = U().gridSquare(math.floor(telemetry.pathNextX),
            math.floor(telemetry.pathNextY), actorZ or 0)
        if nextSquare then
            lease.nativeNextSquare = nextSquare
            local nextKey = squareKey(nextSquare)
            if nextKey and nextKey ~= lease.nativeNextKey then progressed = true end
            lease.nativeNextKey = nextKey
            state.lastAttemptFrom = U().squareOf(actor) or lease.fromSquare
            state.lastAttemptTo = nextSquare
            if lease.affordance == "multi_level" and currentSquare
                and nextKey ~= currentKey
                and (squareHasStairs(currentSquare) or squareHasStairs(nextSquare)
                    or differentFloor(currentSquare, nextSquare)) then
                local accepted, passageStatus = ensureGroupPassage(actor, state,
                    currentSquare, nextSquare, "stairs", {
                        cohortKey = lease.cohortKey,
                        cqbRole = lease.cqbRole,
                        groupParticipants = lease.groupParticipants,
                        urgent = lease.urgent,
                        supervisorToken = lease.supervisorToken,
                    }, now)
                if accepted ~= true then
                    if accepted == false then
                        if SC.NativeActions
                            and type(SC.NativeActions.stopDirect) == "function" then
                            pcall(SC.NativeActions.stopDirect, actor, {
                                preservePosture = true,
                            })
                        end
                        state.nativeLease = nil
                        return "failed", passageStatus or "stair_passage_stop_rejected"
                    end
                    lease.nativePaused = true
                    lease.passagePausedUntil = now
                        + (tonumber(U().config("navigationPassageYieldMs")) or 500)
                    return "active", passageStatus or "holding_stair_passage"
                end
                lease.nativePaused, lease.passagePausedUntil = nil, nil
            end
        end
    end
    if progressed then
        lease.progressAt = now
        lease.positionProgressAt = now
        lease.lastWorldX, lease.lastWorldY, lease.lastWorldZ = worldX, worldY, worldZ
        lease.lastGoalDistance = goalDistance
        lease.expires = now + (tonumber(lease.leaseMs)
            or U().config("navigationNativeLeaseMs") or 6500)
        state.lastProgressAt = now
    end
    if actorState ~= nil or telemetry.active == true then
        lease.activityHeartbeatAt = now
    end
    local pendingGrace = tonumber(U().config("navigationNativePendingMs")) or 6500
    local nativePending = telemetry.pending == true or telemetry.status == "pending"
    if nativePending and now - (tonumber(lease.startedAt) or now) <= pendingGrace then
        lease.wasPending = true
        lease.expires = math.max(tonumber(lease.expires) or 0,
            (tonumber(lease.startedAt) or now) + pendingGrace)
        extendChoke(state, actor, lease.expires)
        lease.lastActiveAt = now
        return "active", "native_path_pending"
    elseif lease.wasPending == true then
        -- Ready/moving is a new phase: give native movement its normal no-progress
        -- allowance instead of charging the route-search time against it.
        lease.wasPending = nil
        if lease.deferredGoalSquare ~= nil then
            lease.ultimateGoal = lease.deferredGoalSquare
            lease.ultimateGoalKey = lease.deferredGoalKey
            lease.deferredGoalSquare, lease.deferredGoalKey = nil, nil
        end
        lease.positionProgressAt = now
        lease.lastWorldX, lease.lastWorldY, lease.lastWorldZ = worldX, worldY, worldZ
        lease.lastGoalDistance = goalDistance
        lease.expires = now + (tonumber(lease.leaseMs)
            or U().config("navigationNativeLeaseMs") or 6500)
        state.lastProgressAt = now
    end
    local startGrace = tonumber(U().config("navigationNativeStartGraceMs")) or 650
    local stallMs = lease.affordance == "multi_level"
        and (tonumber(U().config("navigationMultiLevelStallMs")) or 3000)
        or (tonumber(U().config("navigationNativeStallMs")) or 1400)
    if telemetry.turningToObstacle == true then
        stallMs = math.max(stallMs,
            tonumber(U().config("navigationNativeTurnGraceMs")) or 900)
    end
    local noProgressFor = now - (tonumber(lease.positionProgressAt) or lease.startedAt)
    if now <= lease.expires and noProgressFor <= stallMs
        and (actorState ~= nil or telemetry.active == true) then
        extendChoke(state, actor, lease.expires)
        lease.lastActiveAt = now
        local status = actorState and "native_animation_" .. tostring(actorState)
            or telemetry.turningToObstacle and "native_turning_to_obstacle"
            or telemetry.pending and "native_path_pending" or "native_path_owned"
        return "active", status
    end
    if now - lease.startedAt < startGrace then
        return "active", "native_path_starting"
    end
    -- stopDirect clears the route and often returns the FSM to idle. Preserve
    -- the failing native evidence before cleanup makes the blocker log lie.
    state.lastNativeFailureTelemetry = {
        at = now, status = telemetry.status, active = telemetry.active,
        pathNextIsSet = telemetry.pathNextIsSet, pathNextX = telemetry.pathNextX,
        pathNextY = telemetry.pathNextY,
        summary = tostring(telemetry.status or "unavailable") .. ":"
            .. tostring(telemetry.active) .. "/" .. tostring(telemetry.pending)
            .. ":next=" .. tostring(telemetry.pathNextIsSet) .. ":"
            .. tostring(telemetry.pathNextX) .. "," .. tostring(telemetry.pathNextY)
            .. ":fsm=" .. string.sub(U().objectLabel(select(1, U().call(actor, "getCurrentState"))), 1, 80),
    }
    if SC.NativeActions and type(SC.NativeActions.stopDirect) == "function" then
        pcall(SC.NativeActions.stopDirect, actor, { preservePosture = true })
    end
    state.nativeLease = nil
    local openDoor, openDoorKind = barrierBetween(lease.fromSquare, lease.toSquare)
    if lease.affordance == "door" and openDoorKind == "door"
        and objectOpen(openDoor) then
        local retryKey = edgeKey(lease.fromSquare, lease.toSquare)
        if state.openDoorRetryKey ~= retryKey then
            state.openDoorRetryKey = retryKey
            state.openDoorRetryAttempts = 0
        end
        state.openDoorRetryAttempts = (tonumber(state.openDoorRetryAttempts) or 0) + 1
        local maximum = math.max(1, math.floor(tonumber(U().config(
            "navigationOpenDoorDirectAttempts")) or 2))
        if state.openDoorRetryAttempts > maximum then
            state.openDoorDirectKey, state.openDoorDirectUntil = nil, nil
            return "failed", "open_door_direct_retry_exhausted"
        end
        state.openDoorDirectKey = retryKey
        state.openDoorDirectUntil = now
            + (tonumber(U().config("navigationOpenDoorDirectFallbackMs")) or 2000)
        return "cancelled", "open_door_direct_retry"
    end
    return "failed", noProgressFor > stallMs and "native_path_stalled"
        or now > lease.expires and "native_path_timeout" or "native_path_failed"
end
Navigation._maintainNativeLeaseForTests = maintainNativeLease
Navigation._nativeLeaseArrivalForTests = nativeLeaseArrival

local function classifyMovementBlocker(actor, fromSquare, toSquare, movementReason)
    local utility = U()
    local actorState, stateObject = utility.movementStateBlocker(actor)
    if actorState then
        return { type = "actor_state", object = stateObject, actorState = actorState,
            square = fromSquare, dynamic = true }
    end
    -- The selected route edge is durable evidence; collision flags may survive
    -- one or more frames after brushing a parked car beside a gate or fence. Give
    -- the actual portal precedence so recovery does not repeatedly relabel the
    -- same fence edge as a vehicle and blacklist the wrong tile.
    local barrier, barrierKind = barrierBetween(fromSquare, toSquare)
    if barrierKind == "open" and (squareHasSlope(fromSquare) or squareHasSlope(toSquare)) then
        barrierKind = "slope"
    end
    if barrierKind == "door" and not objectOpen(barrier) then
        return { type = "door", object = barrier, square = toSquare or fromSquare }
    end
    if barrierKind == "fence" or barrierKind == "stairs"
        or barrierKind == "slope" then
        return { type = barrierKind, object = barrier, square = toSquare or fromSquare }
    end
    local collided, ok = utility.call(actor, "isCollidedWithVehicle")
    -- Despite its name, Build 42 sets this flag for ANY PolygonalMap2
    -- position correction, including walls and door geometry. A vehicle
    -- classification requires an actual overlapping vehicle object.
    local polygonCollision = ok and collided == true
    if polygonCollision then
        local vehicle = squareVehicle(toSquare) or squareVehicle(fromSquare)
        if vehicle then
            return { type = "vehicle", object = vehicle, square = toSquare or fromSquare }
        end
    end
    collided, ok = utility.call(actor, "isCollidedWithDoor")
    if ok and collided == true then
        local object = select(1, utility.call(actor, "getCollidedObject"))
        return { type = "door", object = object or barrier, square = toSquare or fromSquare,
            evidenceClass = objectOpen(object or barrier) and "unknown" or nil,
            confidence = objectOpen(object or barrier) and "low" or nil }
    end
    local object, objectOk = utility.call(actor, "getCollidedObject")
    if objectOk and object ~= nil then
        if barrierKind == "door" and object == barrier and objectOpen(object) then
            return { type = "door", object = object, square = toSquare,
                evidenceClass = "unknown", confidence = "low" }
        end
        local moved, movedOk = utility.call(object, "isMovedThumpable")
        local blockAll, blockOk = utility.call(object, "isBlockAllTheSquare")
        if (movedOk and moved == true) or (blockOk and blockAll == true)
            or utility.instanceOf(object, "IsoThumpable") then
            return { type = moved == true and "moved_object" or "thumpable",
                object = object, square = toSquare or utility.squareOf(object) or fromSquare }
        end
        if utility.instanceOf(object, "IsoTree") then
            return { type = "vegetation", object = object, square = utility.squareOf(object) or toSquare }
        end
        return { type = "world_object", object = object, square = toSquare or fromSquare }
    end
    -- Collision flags are transient.  If the failed edge itself is a known door,
    -- retain that stronger topology evidence instead of publishing `unknown` and
    -- applying generic recovery to a doorway problem.
    local static, staticKind = utility.squareStaticBlocker(toSquare)
    if static then return { type = staticKind, object = static, square = toSquare } end
    local thumpable, thumpableKind = edgeThumpableBlocker(fromSquare, toSquare, actor)
    if thumpable then return { type = thumpableKind, object = thumpable, square = toSquare } end
    local moving, movingKind = utility.movingBlocker(toSquare, actor, { swept = true })
    if moving then return { type = movingKind, object = moving, square = toSquare, dynamic = true } end
    if barrierKind == "door" then
        return { type = "door", object = barrier, square = toSquare or fromSquare,
            evidenceClass = "unknown", confidence = "low", passageOnly = true }
    end
    if polygonCollision then
        return { type = "continuous_geometry", square = toSquare or fromSquare,
            evidenceClass = "unknown", confidence = "low" }
    end
    if squareHasStairs(fromSquare) or squareHasStairs(toSquare)
        or squareHasSlope(fromSquare) or squareHasSlope(toSquare) then
        return { type = "stairs_or_slope", square = toSquare }
    end
    if squareHasTree(toSquare) or squareNearTree(toSquare)
        or squareHasTree(fromSquare) or squareNearTree(fromSquare) then
        return { type = "vegetation", square = toSquare or fromSquare,
            nearTree = true }
    end
    local reason = string.lower(tostring(movementReason or ""))
    if string.find(reason, "continuous_collision", 1, true) then
        return { type = "continuous_geometry", square = toSquare }
    end
    collided, ok = utility.call(actor, "isCollidedThisFrame")
    if ok and collided == true then return { type = "world_collision", square = toSquare } end
    return { type = "unknown", square = toSquare or fromSquare }
end
Navigation._classifyMovementBlockerForTests = classifyMovementBlocker

local function addBlockerEvidence(blocker)
    blocker = type(blocker) == "table" and blocker or { type = "unknown" }
    if blocker.evidenceClass then return blocker end
    local kind = blocker.type or "unknown"
    local blockAllValue, blockAllOk = nil, false
    if blocker.object then
        blockAllValue, blockAllOk = U().call(blocker.object, "isBlockAllTheSquare")
    end
    local blockAll = blockAllOk and blockAllValue == true
    if kind == "actor_state" then
        blocker.evidenceClass, blocker.confidence = "actor_state", "high"
    elseif string.find(kind, "_crowd", 1, true) then
        blocker.evidenceClass, blocker.confidence = "dynamic", "high"
    elseif kind == "vehicle" or kind == "moved_object" or kind == "pushable_object"
        or kind == "player" or kind == "companion" or kind == "zombie" then
        blocker.evidenceClass, blocker.confidence = "dynamic_square", "high"
    elseif kind == "full_square_thumpable" or kind == "full_square_object"
        or (kind == "thumpable" and blockAll) then
        blocker.evidenceClass, blocker.confidence = "static_square", "high"
    elseif kind == "door" or kind == "fence" or kind == "stairs" or kind == "slope"
        or kind == "stairs_or_slope" or kind == "thumpable"
        or kind == "vegetation" then
        blocker.evidenceClass, blocker.confidence = "static_edge", "high"
    elseif kind == "safehouse" or kind == "policy" then
        blocker.evidenceClass, blocker.confidence = "policy", "high"
    else
        blocker.evidenceClass, blocker.confidence = "unknown", "low"
    end
    return blocker
end

local function rememberFailure(actor, state, fromSquare, toSquare, reason, now, recovery)
    state.lastMovementReason = reason
    state.lastAttemptFrom, state.lastAttemptTo = fromSquare, toSquare
    local blocker = addBlockerEvidence(
        classifyMovementBlocker(actor, fromSquare, toSquare, reason))
    local object, kind = barrierBetween(fromSquare, toSquare)
    rememberRouteEdge(state, fromSquare, toSquare, false,
        blocker.type or kind, blocker.object or object, now)
    if blocker.confidence == "low" then
        local remembered = state.routeMemory and state.routeMemory[edgeKey(fromSquare, toSquare)]
        if remembered then remembered.expires = now + blockerDuration("unknown") end
    end
    if blocker.type ~= "actor_state" and fromSquare and toSquare then
        blacklistEdge(state, fromSquare, toSquare, blocker.type, blocker.object, now,
            blocker.evidenceClass, blocker.confidence)
    end
    if squareEvidenceClasses[blocker.evidenceClass] and adjacentStep(fromSquare, toSquare) then
        -- A collision capsule can fail on an otherwise topologically open tile
        -- beside a vehicle or moveable. Blocking only the directed edge lets A*
        -- choose the same bad tile from another side on its next search.
        blacklistSquare(state, blocker.square or toSquare, blocker.type,
            blocker.object, now, blocker.evidenceClass, blocker.confidence)
    end
    recordBlocker(actor, state, blocker.type, blocker.object, blocker.square,
        blocker.actorState, recovery or "edge_blacklisted", now,
        blocker.evidenceClass, blocker.confidence)
    if state.activeWorkRoute then
        SC.WorkRoutes.invalidate(state.activeWorkRoute, now,
            reason or blocker.type or "movement_failed")
        state.activeWorkRoute = nil
    end
    state.path = nil
    state.pathGoalSquare = nil
    state.pathSearch = nil
    state.pathSearchHolding = nil
    state.pathIndex = 1
    state.nextRepathAt = 0
    return blocker
end
Navigation._rememberFailureForTests = rememberFailure

local function topologySignatureAt(actor, centre)
    local utility = U()
    local x, y, z = utility.position(centre)
    if x == nil then return "unloaded" end
    local parts = {}
    local offsets = { { 0, 0 }, { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }
    for _, offset in ipairs(offsets) do
        local square = utility.gridSquare(x + offset[1], y + offset[2], z)
        if not square then
            parts[#parts + 1] = tostring(offset[1]) .. "," .. tostring(offset[2]) .. "=missing"
        else
            local static, staticKind = utility.squareStaticBlocker(square)
            local edgeObject, edgeKind
            if offset[1] == 0 and offset[2] == 0 then
                edgeKind = "centre"
            else
                edgeObject, edgeKind = barrierBetween(centre, square)
            end
            local affordance = ""
            if edgeObject ~= nil then
                affordance = ":open=" .. tostring(objectOpen(edgeObject))
                    .. ":locked=" .. tostring(objectLocked(edgeObject))
                    .. ":barricaded=" .. tostring(objectBarricaded(edgeObject))
            end
            parts[#parts + 1] = tostring(offset[1]) .. "," .. tostring(offset[2])
                .. "=" .. tostring(edgeKind or "open") .. affordance
                .. ":static=" .. tostring(staticKind or (static and "blocked" or "none"))
                .. ":safehouse=" .. tostring(utility.safehouseBlocker(square, actor) == true)
        end
    end
    return table.concat(parts, "|")
end

local function topologySignature(actor, sourceSquare, goalSquare)
    return tostring(squareKey(sourceSquare)) .. "{" .. topologySignatureAt(actor, sourceSquare)
        .. "}>" .. tostring(squareKey(goalSquare)) .. "{"
        .. topologySignatureAt(actor, goalSquare) .. "}"
end

local function routeTargetSignature(goalSquare, intent)
    intent = type(intent) == "table" and intent or {}
    local moving = intent.movingTarget == true or intent.followRecovery == true
        or intent.player ~= nil or intent.action == "follow_formation"
        or intent.action == "regroup"
    local semanticTarget = intent.container or intent.object or intent.vehicle
        or intent.player or intent.item or "none"
    local explicit = intent.targetSignature or intent.capabilitySignature
        or intent.commandSerial or "none"
    return tostring(intent.action or "move") .. "|"
        .. (moving and "moving" or tostring(squareKey(goalSquare))) .. "|"
        .. tostring(semanticTarget) .. "|" .. tostring(intent.item or "none")
        .. "|" .. tostring(explicit) .. "|token=" .. tostring(tokenSerial(intent) or "none")
end

local function clearTerminalEpisode(actor, state, reason, now)
    if state.terminalGoalKey ~= nil then
        recordMovement(actor, "terminal_cleared", {
            status = reason or "changed", targetSquare = state.goalSquare,
            blocker = state.terminalBlockerType,
        })
    end
    state.terminalGoalKey = nil
    state.terminalReason = nil
    state.terminalAt = nil
    state.terminalRetryAt = nil
    state.terminalTargetSignature = nil
    state.terminalTopologySignature = nil
    state.terminalActorSquareKey = nil
    state.terminalBlockerType = nil
    state.terminalAttempt = nil
    state.stuckAttempts = 0
    state.actorStateRecoveryAttempts = 0
    state.lastProgressAt = now or U().nowMs()
end

local function beginTerminalEpisode(actor, state, sourceSquare, goalSquare, intent,
        blocker, now)
    local blockerType = blocker and blocker.type or "unknown"
    state.terminalGoalKey = squareKey(goalSquare)
    state.terminalReason = "recovery_exhausted:" .. tostring(blockerType)
    state.terminalAt = now
    state.terminalRetryAt = now + (U().config("navigationTerminalRetryMs") or 8000)
    state.terminalTargetSignature = routeTargetSignature(goalSquare, intent)
    state.terminalTopologySignature = topologySignature(actor, sourceSquare, goalSquare)
    state.terminalActorSquareKey = squareKey(sourceSquare)
    state.terminalBlockerType = blockerType
    state.terminalAttempt = state.stuckAttempts
    recordBlocker(actor, state, blockerType, blocker and blocker.object,
        blocker and blocker.square or goalSquare, blocker and blocker.actorState,
        "recovery_exhausted", now)
    recordMovement(actor, "terminal_failure", {
        blocker = blockerType, recovery = "exhausted",
        targetSquare = goalSquare, status = state.terminalReason,
        detail = "attempt=" .. tostring(state.stuckAttempts),
    })
    local service, token = supervisedToken(intent)
    if service and token then
        if type(service.transition) == "function" then
            service.transition(token, "recovering", {
                blocker = blockerType, attempt = state.stuckAttempts,
            })
        end
        if type(service.progress) == "function" then
            service.progress(token, "recovery_exhausted:" .. tostring(state.stuckAttempts), {
                blocker = blockerType,
            })
        end
    end
    return state.terminalReason
end

local function terminalEpisodeActive(actor, state, sourceSquare, goalSquare, intent, now)
    if state.terminalGoalKey ~= squareKey(goalSquare) then return false end
    local reason
    if state.terminalTargetSignature ~= routeTargetSignature(goalSquare, intent) then
        reason = "target_changed"
    elseif state.terminalActorSquareKey ~= squareKey(sourceSquare) then
        reason = "actor_repositioned"
    elseif state.terminalTopologySignature ~= topologySignature(actor, sourceSquare, goalSquare) then
        reason = "topology_changed"
    elseif now >= (state.terminalRetryAt or math.huge) then
        reason = "retry_due"
    end
    if reason then
        clearTerminalEpisode(actor, state, reason, now)
        return false
    end
    return true, state.terminalReason or "recovery_exhausted:unknown"
end

local function recoverFromStuck(actor, state, goalSquare, movementMode, intent, now)
    local utility = U()
    local actorSquare = utility.squareOf(actor)
    local actorState = utility.movementStateBlocker(actor)
    if actorState then
        if state.actorStateName ~= actorState then
            state.actorStateName = actorState
            state.actorStateSince = now
            state.nextActorStateDiagnosticAt = 0
            state.nextActorStateRecoveryAt = 0
            state.actorStateRecoveryAttempts = 0
        end
        local elapsed = now - (state.actorStateSince or now)
        local grace = utility.config("navigationActorStateGraceMs") or 900
        local timeout = math.max(grace,
            utility.config("navigationActorStateTimeoutMs") or 12000)
        local recovery = "waiting_for_native_animation"
        local activelyRecovered = false
        -- A native locomotion state that outlives its edge otherwise loops
        -- waiting_for_native_animation -> actor_state_timeout forever:
        -- CollideWithWallState survives after its failed edge was discarded, and a
        -- non-local companion teleported mid-climb never finishes the climb, so
        -- isClimbing() stays true and it stands frozen at the obstacle (seen in
        -- playtests as a companion stuck for minutes after teleporting to follow).
        -- Cancel the stale movement owner and force a repath. Wall collisions clear
        -- quickly (short grace); a genuine fence/wall climb is longer, so only
        -- intervene for "climbing" after the full timeout, and blacklist the
        -- unfinished climb edge (temporary) so the repath routes around it instead
        -- of re-queuing the same stuck climb.
        local stuckThreshold = actorState == "climbing" and timeout or grace
        if (actorState == "wall_collision_state" or actorState == "bumped_state"
                or actorState == "climbing")
            and elapsed >= stuckThreshold
            and now >= (state.nextActorStateRecoveryAt or 0) then
            local cancelled = false
            if actorState == "climbing" then
                state.actorStateRecoveryAttempts =
                    (state.actorStateRecoveryAttempts or 0) + 1
                if SC.NativeActions
                    and type(SC.NativeActions.cancelStuckClimb) == "function" then
                    local ok, result = pcall(SC.NativeActions.cancelStuckClimb, actor)
                    cancelled = ok and result == true
                end
            else
                if SC.NativeActions and type(SC.NativeActions.stopDirect) == "function" then
                    local ok, result = pcall(SC.NativeActions.stopDirect, actor,
                        { preservePosture = true })
                    cancelled = ok and result == true
                else
                    cancelled = utility.stop(actor) == true
                end
            end
            state.nextActorStateRecoveryAt = now + grace
            if cancelled then
                if actorState == "climbing" and actorSquare and state.lastAttemptTo then
                    blacklistEdge(state, actorSquare, state.lastAttemptTo,
                        "actor_state", nil, now, "static_edge", "medium")
                end
                state.path = nil
                state.pathGoalSquare = nil
                state.pathSearch = nil
                state.pathIndex = 1
                state.nextRepathAt = 0
                state.lastProgressAt = now
                if actorState == "bumped_state" and actorSquare then
                    local waypoint = SC.Navigation._selectRecoveryWaypointForRequest(
                        actor, state, actorSquare, goalSquare, intent, now)
                    state.recoveryWaypointReason = waypoint and "bumped_state" or nil
                end
                activelyRecovered = true
                if actorState == "climbing" then
                    recovery = "cancelled_stuck_climb"
                elseif actorState == "bumped_state" then
                    recovery = "cancelled_stale_bump"
                else
                    recovery = "cancelled_stale_wall_collision"
                end
                recordBlocker(actor, state, "actor_state", nil, actorSquare,
                    actorState, recovery, now)
                state.nextActorStateDiagnosticAt = now + 2000
            elseif actorState == "climbing" then
                recovery = "stuck_climb_cancel_rejected"
                local maximum = math.max(1,
                    tonumber(utility.config("navigationRecoveryAttempts")) or 3)
                if state.actorStateRecoveryAttempts >= maximum then
                    state.stuckAttempts = maximum + 1
                    return true, false, beginTerminalEpisode(actor, state, actorSquare,
                        goalSquare, intent, {
                            type = "actor_state", square = actorSquare,
                            actorState = actorState,
                        }, now)
                end
            end
        elseif elapsed >= timeout then
            recovery = "actor_state_timeout"
        end
        if now >= (state.nextActorStateDiagnosticAt or 0) then
            recordBlocker(actor, state, "actor_state", nil, actorSquare,
                actorState, recovery, now)
            state.nextActorStateDiagnosticAt = now + 2000
        end
        if elapsed >= timeout and not activelyRecovered then
            return true, false, "actor_state_timeout:" .. tostring(actorState)
        end
        if activelyRecovered then return true, true, recovery end
        return true, true, "waiting_" .. tostring(actorState)
    end
    if state.actorStateName ~= nil then
        state.actorStateName = nil
        state.actorStateSince = nil
        state.nextActorStateRecoveryAt = nil
        state.nextActorStateDiagnosticAt = nil
        state.actorStateRecoveryAttempts = nil
        -- Clearing a native animation is genuine progress. Without this reset,
        -- the generic stuck timer can immediately fire in the same update.
        state.lastProgressAt = now
    end
    if state.pathSearch ~= nil then
        local startedAt = tonumber(state.pathSearch.startedAt) or now
        local progressAt = tonumber(state.pathSearch.progressAt) or startedAt
        local searchAge = now - startedAt
        local stalledFor = now - progressAt
        local searchLease, hardLimit = pathSearchBounds(state.pathSearch)
        if searchAge >= 0 and stalledFor >= 0 and stalledFor <= searchLease
            and searchAge <= hardLimit then
            -- holdForPathSearch intentionally makes the actor idle. Planning is
            -- still live work, not evidence for collision recovery.
            return false, nil, nil
        end
        state.lastMovementReason = searchAge > hardLimit and "path_search_timeout:hard_limit"
            or "path_search_stalled:"
                .. tostring(state.pathSearchYieldReason or "unknown")
    end
    local nearbyDoor = nearbyOpenedDoor(state, actor)
    local treeAwayX, treeAwayY = treeEscapeDirection(actorSquare, actor, goalSquare)
    local preview = classifyMovementBlocker(actor, state.lastAttemptFrom or actorSquare,
        state.lastAttemptTo or goalSquare, state.lastMovementReason)
    local telemetry = pathTelemetry(actor)
    local stuckDelay = utility.config("navigationStuckMs") or 2200
    if nearbyDoor or treeAwayX ~= nil or preview.type == "vehicle"
        or preview.type == "thumpable" or preview.type == "moved_object" then
        stuckDelay = math.min(stuckDelay,
            utility.config("navigationObstacleStuckMs") or 900)
    end
    if preview.dynamic == true then stuckDelay = math.min(stuckDelay, 750) end
    if preview.type == "stairs_or_slope" or telemetry.turningToObstacle == true
        or telemetry.pending == true then
        stuckDelay = math.max(stuckDelay,
            utility.config("navigationNativeTurnGraceMs") or 3200)
    end
    if now - (state.lastProgressAt or now) < stuckDelay then
        return false, nil, nil
    end
    state.stuckAttempts = (state.stuckAttempts or 0) + 1
    state.lastProgressAt = now
    clearMovementTransients(actor, state)
    state.path = nil
    state.pathGoalSquare = nil
    state.pathIndex = 1
    state.nextRepathAt = 0
    local maximum = utility.config("navigationRecoveryAttempts") or 3
    if state.stuckAttempts > maximum then
        state.recoveryWaypoint = nil
        state.recoveryWaypointExpires = nil
        state.recoveryWaypointReason = nil
        local terminalGoal = type(intent) == "table" and intent.requestedGoalSquare
            or goalSquare
        state.goalSquare = terminalGoal
        state.routeTargetSignature = routeTargetSignature(terminalGoal, intent)
        return true, false, beginTerminalEpisode(actor, state, actorSquare,
            terminalGoal, intent, preview, now)
    end
    local failedFrom = state.lastAttemptFrom or actorSquare
    local failedTo = state.lastAttemptTo or goalSquare
    local blocker = addBlockerEvidence(
        classifyMovementBlocker(actor, failedFrom, failedTo, state.lastMovementReason))
    local service, token = supervisedToken(intent)
    if service and token then
        if type(service.transition) == "function" then
            service.transition(token, "recovering", {
                blocker = blocker.type, attempt = state.stuckAttempts,
            })
        end
        if type(service.progress) == "function" then
            service.progress(token, "recovery:" .. tostring(state.stuckAttempts)
                .. ":" .. tostring(blocker.type), {
                    blocker = blocker.type, attempt = state.stuckAttempts,
                })
        end
    end
    if blocker.type ~= "actor_state" then
        blacklistEdge(state, failedFrom, failedTo, blocker.type, blocker.object, now,
            blocker.evidenceClass, blocker.confidence)
    end
    if state.stuckAttempts <= 1 then
        if nearbyDoor then
            state.recoveryDoorHoldUntil = now + stuckDelay
                + (utility.config("doorCloseDelayMs") or 700)
        end
        recordBlocker(actor, state, blocker.type, blocker.object, blocker.square,
            blocker.actorState, "stop_and_replan", now)
        if not utility.stop(actor) then return true, false, "recovery_stop_rejected" end
        return true, true, "recovering_stop"
    end
    local x, y, z = utility.position(actorSquare)
    if x == nil then return true, false, "recovery_square_unavailable" end

    if nearbyDoor then
        state.recoveryDoorHoldUntil = now + stuckDelay
            + (utility.config("doorCloseDelayMs") or 700)
    end

    local forwardX, forwardY
    if treeAwayX ~= nil then
        forwardX, forwardY = treeAwayX, treeAwayY
    elseif nearbyDoor then
        local _, _, doorX, doorY = doorGeometry(nearbyDoor, actor)
        forwardX, forwardY = doorX, doorY
    else
        local gx, gy = utility.position(goalSquare)
        local dx, dy = (gx or x) - x, (gy or y) - y
        if math.abs(dx) >= math.abs(dy) then
            forwardX, forwardY = dx >= 0 and 1 or -1, 0
        else
            forwardX, forwardY = 0, dy >= 0 and 1 or -1
        end
    end
    local offsets
    if treeAwayX ~= nil then
        offsets = {
            { forwardX, forwardY }, { -forwardY, forwardX },
            { forwardY, -forwardX }, { -forwardX, -forwardY },
        }
    else
        offsets = {
            { -forwardY, forwardX }, { forwardY, -forwardX },
            { -forwardX, -forwardY }, { forwardX, forwardY },
        }
    end
    if treeAwayX == nil and utility.stableHash(utility.idOf(actor)) % 2 == 1 then
        offsets[1], offsets[2] = offsets[2], offsets[1]
    end
    local candidates, seen = {}, {}
    for _, offset in ipairs(offsets) do
        local square = utility.gridSquare(x + offset[1], y + offset[2], z)
        local key = square and squareKey(square) or nil
        if key and not seen[key] then
            seen[key] = true
            candidates[#candidates + 1] = square
        end
    end
    for _, square in ipairs(candidates) do
        local _, kind = barrierBetween(actorSquare, square)
        local passable = square and select(1, passableEdge(actorSquare, square)) == true
        if square and kind == "open" and passable and utility.isSquareFree(square)
            and not utility.edgeBlocked(actorSquare, square)
            and not personalSpaceBlocker(actor, square, intent and intent.snapshot)
            and reserveStep(square, actor, state, intent or {}, now) then
            local accepted = utility.move(actor, "walk", {
                action = "collision_recovery",
                nextSquare = square,
                targetSquare = square,
                direction = directionBetween(actorSquare, square),
                direct = true,
                collisionValidated = true,
                doorwayRecovery = nearbyDoor ~= nil,
                treeRecovery = treeAwayX ~= nil,
                supervisorToken = intent and intent.supervisorToken,
            })
            if accepted then
                state.recoveryWaypoint = square
                state.recoveryWaypointExpires = now
                    + (utility.config("navigationRecoveryWaypointMs") or 5000)
                state.recoveryWaypointReason = "lateral_clearance"
                recordBlocker(actor, state, blocker.type, blocker.object, blocker.square,
                    blocker.actorState, "lateral_clearance", now)
                return true, true, "recovering_" .. tostring(blocker.type)
            end
            releaseStep(state, actor)
        end
    end
    local actorDistance = utility.distance(actor, goalSquare)
    if intent and intent.followRecovery and actorDistance >= (utility.config("followRecoveryDistance") or 42)
        and not utility.canSee(intent.player, actor) then
        local accepted = utility.move(actor, "jog", {
            action = "offscreen_safe_recovery",
            targetSquare = goalSquare,
            nextSquare = goalSquare,
            direction = directionBetween(actorSquare, goalSquare),
            requireLoaded = true,
            requireUnseen = true,
            lastResort = true,
            supervisorToken = intent and intent.supervisorToken,
        })
        if accepted then return true, true, "recovering_offscreen" end
    end
    recordBlocker(actor, state, blocker.type, blocker.object, blocker.square,
        blocker.actorState, "recovery_rejected", now)
    return true, false, "recovery_action_rejected"
end
Navigation._recoverFromStuckForTests = recoverFromStuck

local function nativeVerificationFailure(reason)
    local text = string.lower(tostring(reason or ""))
    return string.find(text, "did not retain", 1, true) ~= nil
        or string.find(text, "did not become active", 1, true) ~= nil
        or string.find(text, "verification", 1, true) ~= nil
end

local function scheduleNativeRetry(state, goalSquare, reason, now)
    if not nativeVerificationFailure(reason) then return false end
    local key = squareKey(goalSquare)
    if state.nativeRetryGoalKey ~= key then
        state.nativeRetryGoalKey, state.nativeRetryCount = key, 0
    end
    if (state.nativeRetryCount or 0) >= 1 then return false end
    state.nativeRetryCount = (state.nativeRetryCount or 0) + 1
    state.nativeRetryAt = now + (U().config("navigationNativeRetryMs") or 500)
    return true
end
Navigation._scheduleNativeRetryForRequest = scheduleNativeRetry

local function requestMultiLevelPath(actor, state, sourceSquare, goalSquare,
        requestIntent, now, service, token)
    if not differentFloor(sourceSquare, goalSquare) then return nil end
    local utility = U()
    -- PathFindBehavior2 can route toward stairs, but the stock sheet-rope
    -- transition is a character action rather than an ordinary path edge. If
    -- the companion is already standing on a valid rope square, hand the whole
    -- vertical move to the same native climb state a player uses.
    if SC.Topology and type(SC.Topology.squareHasSheetRope) == "function"
        and SC.Topology.squareHasSheetRope(sourceSquare) then
        local _, _, sourceZ = utility.position(sourceSquare)
        local _, _, goalZ = utility.position(goalSquare)
        local down = tonumber(goalZ) < tonumber(sourceZ)
        local check = down and "canClimbDownSheetRope" or "canClimbSheetRope"
        local climbable, checked = utility.call(actor, check, sourceSquare)
        if checked and climbable == true then
            releaseStep(state, actor)
            releaseChoke(state, actor)
            state.path = nil
            state.pathGoalSquare = nil
            state.pathSearch = nil
            state.pathIndex = 1
            state.pathReason = "native_sheet_rope"
            requestIntent.action = down and "climb_down_sheet_rope" or "climb_sheet_rope"
            requestIntent.targetSquare = goalSquare
            requestIntent.nextSquare = goalSquare
            requestIntent.nativeAffordance = "sheet_rope"
            requestIntent.mode = "walk"
            requestIntent.weaponReady = false
            state.lastAttemptFrom, state.lastAttemptTo = sourceSquare, sourceSquare
            local moved, movementReason = utility.move(actor, "walk", requestIntent)
            state.lastMovementReason = movementReason
            if moved then
                state.lastProgressAt = now
                SC.WorkRoutes.noteFirstMotion(actor, state, now, "native_sheet_rope")
                return true, true, down and "sheet_rope_descent"
                    or "sheet_rope_climb"
            end
            return true, false, movementReason or "sheet_rope_action_rejected"
        end
    end
    -- The native engine, also used by zombies' PathFindState, knows the actual
    -- oriented multi-tile stair geometry. The bounded Lua planner deliberately
    -- stays two-dimensional here: synthetic z edges selected false landings and
    -- caused approach/replan loops at basements, upper floors and attics.
    releaseStep(state, actor)
    releaseChoke(state, actor)
    state.path = nil
    state.pathGoalSquare = nil
    state.pathSearch = nil
    state.pathIndex = 1
    state.pathReason = "native_multi_level"
    requestIntent.targetSquare = goalSquare
    requestIntent.nextSquare = goalSquare
    requestIntent.enginePath = true
    requestIntent.multiLevelPath = true
    requestIntent.nativeAffordance = "multi_level"
    requestIntent.weaponReady = false
    state.lastAttemptFrom, state.lastAttemptTo = sourceSquare, goalSquare
    local moved, movementReason = utility.move(actor, requestIntent.mode, requestIntent)
    state.lastMovementReason = movementReason
    if not moved then
        if scheduleNativeRetry(state, goalSquare, movementReason, now) then
            return true, true, "native_verification_retry"
        end
        rememberFailure(actor, state, sourceSquare, goalSquare,
            movementReason or "multi_level_path_rejected", now,
            "native_multi_level_replan")
        return true, false, "multi_level_path_rejected"
    end
    SC.WorkRoutes.noteFirstMotion(actor, state, now, "native_multi_level")
    if service and token then
        if token.phase == "recovering" and type(service.transition) == "function" then
            service.transition(token, "approaching", { strategy = "native_multi_level" })
        end
        if type(service.progress) == "function" then
            service.progress(token, "multi_level:" .. tostring(squareKey(sourceSquare))
                .. ">" .. tostring(squareKey(goalSquare)), {
                    strategy = "native_multi_level",
                })
        end
    end
    beginNativeLease(state, { goalSquare }, sourceSquare, goalSquare,
        goalSquare, now, "multi_level_goal", false,
        isMovingTargetIntent(requestIntent), "multi_level", actor, requestIntent)
    return true, true, "multi_level_path"
end
Navigation._requestMultiLevelPath = requestMultiLevelPath

function Navigation._maintainTraversalForRequest(actor, state, sourceSquare, now)
    local nativeTraversal = SC.NativeTraversalActions
    if nativeTraversal and type(nativeTraversal.poll) == "function" then
        local phase, traversalReason, traversal = nativeTraversal.poll(actor, now)
        if phase == "starting" or phase == "active" then
            state.lastProgressAt = now
            return true, true, traversalReason or "traversal_starting"
        elseif traversal and (phase == "failed" or phase == "completed"
            or phase == "cancelled") then
            if phase == "completed" and not traversal.effectOnly then
                local cleared, clearReason = SC.NavTraversal.clearTraversalExit(
                    actor, traversal, now, { record = recordMovement })
                if cleared == nil then
                    state.lastProgressAt = now
                    return true, true, clearReason or "clearing_traversal_exit"
                elseif cleared == false then
                    nativeTraversal.reset(actor)
                    SC.NavTraversal.release(traversal.object, actor)
                    rememberFailure(actor, state, traversal.fromSquare or sourceSquare,
                        traversal.toSquare or sourceSquare, clearReason, now,
                        "traversal_exit_replan")
                    return true, false, clearReason
                end
            end
            nativeTraversal.reset(actor)
            SC.NavTraversal.release(traversal.object, actor)
            if phase == "failed" then
                state.pendingInteraction = nil
                rememberFailure(actor, state, traversal.fromSquare or sourceSquare,
                    traversal.toSquare or sourceSquare, traversalReason, now, "traversal_replan")
                return true, false, traversalReason
            elseif phase == "cancelled" then
                -- A queued window climb observed the window close before native
                -- entry. Keep the already-validated route and immediately let the
                -- current request choose open/smash/replan for the new portal state.
                state.pendingInteraction = nil
                state.nextRepathAt = 0
                state.lastProgressAt = now
                recordMovement(actor, "portal_state_changed", {
                    blocker = "window", status = traversalReason,
                    targetSquare = traversal.toSquare,
                })
            elseif not traversal.effectOnly then
                -- The route was already validated across this affordance. Keep
                -- its remaining suffix so the actor walks on immediately instead
                -- of standing still for a second A-star search after every climb.
                state.nativeLease = nil
                state.lastAttemptFrom = traversal.fromSquare or sourceSquare
                state.lastAttemptTo = traversal.toSquare or sourceSquare
                state.lastProgressAt = now
            end
        end
    end
    return false
end

function Navigation.request(actor, target, movementMode, intent)
    local utility = U()
    if not utility or not utility.isValidActor(actor) then return false, "invalid_actor" end
    local sourceSquare = utility.squareOf(actor)
    local requestedGoalSquare = targetSquare(target)
    if not sourceSquare then return false, "invalid_source" end
    local goalSquare, goalAdjusted = resolveFollowGoal(sourceSquare, requestedGoalSquare, intent)
    if not goalSquare then return false, "invalid_destination" end
    local permitted, permissionReason = navigationOwnershipPermission(actor, intent)
    if permitted ~= true then return false, permissionReason end

    local now = utility.nowMs()
    local state = stateFor(actor)
    local traversalHandled, traversalAccepted, traversalReason =
        SC.Navigation._maintainTraversalForRequest(actor, state, sourceSquare, now)
    if traversalHandled then return traversalAccepted, traversalReason end
    local recoveryGoal = SC.Navigation._activeRecoveryWaypointForRequest(
        actor, state, now, intent)
    if recoveryGoal then
        goalSquare = recoveryGoal
        goalAdjusted = true
    end
    SC.Navigation._markActorPassageForRequest(actor, state, now)
    state.trafficPriority = movementPriority(intent)
    state.trafficAction = type(intent) == "table" and intent.action or "move"
    sweepBlockedEdges(state, now)
    observeSquare(state, sourceSquare)
    local requestIntent = utility.copyShallow(intent)
    requestIntent.targetSquare = goalSquare
    requestIntent.requestedGoalSquare = requestedGoalSquare
    requestIntent.goalAdjustedForObstacle = goalAdjusted == true
    requestIntent.recoveryWaypoint = recoveryGoal ~= nil
    requestIntent.direction = directionBetween(sourceSquare, goalSquare)
    requestIntent.mode = movementMode or requestIntent.mode or "walk"
    requestIntent.stealthAvoidance = stealthAvoidanceRequested(
        actor, requestIntent.mode, requestIntent)
    local requestedWorkRouteKey = SC.WorkRoutes.key(actor, goalSquare, requestIntent)
    local currentTokenSerial = tokenSerial(requestIntent)
    local currentTargetSignature = routeTargetSignature(goalSquare, requestIntent)
    local previousTokenSerial = state.actionTokenSerial
    local previousTargetSignature = state.routeTargetSignature
    state.stealthAvoidance = requestIntent.stealthAvoidance == true
    closeOwnedDoors(actor, state, now, requestIntent.snapshot)
    local progressed = updateProgress(actor, state, now)
    local service, token = supervisedToken(requestIntent)
    if progressed and service and token then
        if token.phase == "recovering" and type(service.transition) == "function" then
            service.transition(token, "approaching", {
                square = squareKey(sourceSquare), resumed = true,
            })
        end
        if type(service.progress) == "function" then
            service.progress(token, "square:" .. tostring(squareKey(sourceSquare)), {
                target = squareKey(goalSquare),
            })
        end
    end

    local reachedGoal = utility.arrived(actor, goalSquare, {
        targetKind = "square",
        distance = utility.config("navigationArrivalDistance") or 0.6,
    })
    if reachedGoal and state.nativeLease and state.nativeLease.affordance == "door"
        and not actorClearOfDoorway(actor, state.nativeLease) then reachedGoal = false end
    if reachedGoal then
        if requestedWorkRouteKey ~= nil and state.workRouteKey == requestedWorkRouteKey
            and type(state.path) == "table" and state.pathIndex >= #state.path then
            if state.activeWorkRoute then
                state.activeWorkRoute.successes =
                    (tonumber(state.activeWorkRoute.successes) or 0) + 1
                state.activeWorkRoute.failures = 0
                state.activeWorkRoute.retryAt = nil
                state.activeWorkRoute.lastUsedAt = now
            elseif state.pathReason ~= "fast_stationary_route"
                and state.pathReason ~= "fast_open_route" then
                SC.WorkRoutes.record(requestedWorkRouteKey, state.path, now)
            end
        end
        state.goalSquare = goalSquare
        state.goalAction = requestIntent.action
        state.path = nil
        state.pathGoalSquare = nil
        state.pathIndex = 1
        state.arrivedAt = now
        state.stuckAttempts = 0
        state.actionTokenSerial = currentTokenSerial
        state.routeTargetSignature = currentTargetSignature
        state.workRouteKey = requestedWorkRouteKey
        state.activeWorkRoute = nil
        state.firstMotionRequestedAt = nil
        clearTerminalEpisode(actor, state, "arrived", now)
        clearMovementTransients(actor, state)
        if not utility.stop(actor) then return false, "arrival_stop_rejected" end
        if poorSight(actor, sourceSquare, goalSquare, nil, requestIntent) then
            local ready = utility.move(actor, "walk", {
                action = "ready_weapon", targetSquare = goalSquare,
                facingTarget = goalSquare, weaponReady = true,
                humanAnimationOnly = true,
                supervisorToken = requestIntent.supervisorToken,
            })
            if ready ~= true then return false, "arrival_ready_rejected" end
        end
        if service and token and type(service.progress) == "function" then
            service.progress(token, "arrived:" .. tostring(squareKey(goalSquare)), {
                target = squareKey(goalSquare),
            })
        end
        return true, "arrived"
    end

    local goalChanged = changedGoal(state, goalSquare)
    local ownershipChanged = previousTokenSerial ~= currentTokenSerial
        or (requestIntent.recoveryWaypoint ~= true
            and previousTargetSignature ~= nil
            and previousTargetSignature ~= currentTargetSignature)
    if goalChanged then
        local previousGoal = state.goalSquare
        local previousAction = tostring(state.goalAction or "")
        local requestedAction = tostring(requestIntent.action or "")
        local goalShift = previousGoal and utility.distance(previousGoal, goalSquare) or math.huge
        local retainPendingSearch = SC.Navigation._usefulPendingMovingSearchForRequest(
            actor, state, goalSquare, requestIntent, now)
        local materialGoalChange = ownershipChanged
            or (requestIntent.recoveryWaypoint ~= true
                and (previousGoal == nil
                    or previousAction ~= requestedAction
                    or (goalShift >= goalResetDistance(requestIntent)
                        and not retainPendingSearch)))
        state.goalSquare = goalSquare
        state.goalAction = requestIntent.action
        if state.terminalGoalKey ~= nil and state.terminalGoalKey ~= squareKey(goalSquare)
            and (requestIntent.movingTarget == true or requestIntent.followRecovery == true
                or requestIntent.player ~= nil) then
            clearTerminalEpisode(actor, state, "moving_target_changed", now)
        end
        if materialGoalChange then
            clearMovementTransients(actor, state)
            state.path = nil
            state.pathGoalSquare = nil
            state.pathIndex = 1
            state.nextRepathAt = 0
            state.stuckAttempts = 0
            state.lastProgressAt = now
            state.firstMotionRequestedAt = now
            state.lastPlanDurationMs = nil
            state.workRouteKey = requestedWorkRouteKey
            state.activeWorkRoute = nil
            clearTerminalEpisode(actor, state, "route_owner_or_goal_changed", now)
        end
    elseif ownershipChanged then
        clearMovementTransients(actor, state)
        state.path = nil
        state.pathGoalSquare = nil
        state.pathIndex = 1
        state.nextRepathAt = 0
        state.firstMotionRequestedAt = now
        state.lastPlanDurationMs = nil
        state.workRouteKey = requestedWorkRouteKey
        state.activeWorkRoute = nil
        clearTerminalEpisode(actor, state, "route_owner_changed", now)
    end
    if state.workRouteKey ~= requestedWorkRouteKey then
        state.workRouteKey = requestedWorkRouteKey
        state.activeWorkRoute = nil
    end
    state.actionTokenSerial = currentTokenSerial
    state.routeTargetSignature = currentTargetSignature

    local terminal, terminalReason = terminalEpisodeActive(
        actor, state, sourceSquare, goalSquare, requestIntent, now)
    if terminal then
        return false, terminalReason
    end

    if now < (tonumber(state.nativeRetryAt) or 0) then
        return true, "native_verification_cooldown"
    end

    local leaseState, leaseStatus = maintainNativeLease(actor, state, goalSquare, now)
    if leaseState == "active" then return true, leaseStatus or "native_path_owned" end
    if leaseState == "failed" then
        local fromSquare = state.lastAttemptFrom or sourceSquare
        local toSquare = state.lastAttemptTo or goalSquare
        rememberFailure(actor, state, fromSquare, toSquare,
            leaseStatus or "native_path_failed", now, "native_edge_replan")
        return false, leaseStatus or "native_path_failed"
    end

    local recovering, recoveryAccepted, recoveryStatus = recoverFromStuck(
        actor,
        state,
        goalSquare,
        movementMode,
        requestIntent,
        now
    )
    if recovering then
        return recoveryAccepted == true, recoveryStatus or "recovering"
    end

    local multiLevelHandled, multiLevelAccepted, multiLevelStatus =
        SC.Navigation._requestMultiLevelPath(
        actor, state, sourceSquare, goalSquare, requestIntent, now, service, token)
    if multiLevelHandled then return multiLevelAccepted, multiLevelStatus end

    local snapshot = requestIntent.snapshot
    local currentThreats = type(snapshot) == "table" and type(snapshot.stealthThreats) == "table"
        and #snapshot.stealthThreats
        or (type(snapshot) == "table" and type(snapshot.threats) == "table"
            and #snapshot.threats or 0)
    local rememberedThreat = type(snapshot) == "table"
        and type(snapshot.lastKnownDanger) == "table"
    local movingPathChanged = state.path and state.pathGoalSquare
        and isMovingTargetIntent(requestIntent)
        and not sameSquare(state.pathGoalSquare, goalSquare)
    local movingPathRepaired = movingPathChanged and tryRepairMovingPath(
        actor, state, sourceSquare, goalSquare, requestIntent, now)
    local pathGoalDrifted = state.path and state.pathGoalSquare
        and utility.distance(state.pathGoalSquare, goalSquare)
            >= goalResetDistance(requestIntent)
    if movingPathChanged and not movingPathRepaired and not pathGoalDrifted
        and utility.distance(actor, state.pathGoalSquare)
            <= goalResetDistance(requestIntent) + 0.75 then
        -- Near the old endpoint, a one-tile reversal/turn that cannot be safely
        -- appended is already material. Following the stale tail here creates the
        -- visible "one step back, one step forward" loop.
        pathGoalDrifted = true
    end
    if pathGoalDrifted then
        -- Follow targets commonly move by less than the reset threshold per AI
        -- update. Compare against the destination this route was actually built
        -- for so many small shifts cannot leave a companion following a stale
        -- path indefinitely.
        state.path = nil
        state.pathGoalSquare = nil
        state.pathSearch = nil
        state.pathIndex = 1
        state.nextRepathAt = 0
    elseif state.path and state.pathStealthAvoidance ~= requestIntent.stealthAvoidance then
        state.path = nil
        state.pathGoalSquare = nil
        state.pathSearch = nil
        state.pathIndex = 1
        state.nextRepathAt = 0
    elseif state.path and requestIntent.stealthAvoidance
        and (currentThreats > 0 or rememberedThreat)
        and now >= (state.nextStealthRepathAt or 0) then
        -- Moving zombies invalidate a previously safe corridor. A bounded refresh
        -- keeps stealth travel responsive without recomputing on every AI tick.
        state.path = nil
        state.pathGoalSquare = nil
        state.pathSearch = nil
        state.pathIndex = 1
        state.nextRepathAt = 0
    end

    if not state.path and now >= (state.nextRepathAt or 0) then
        local followRouting = requestIntent.followRecovery == true
            or requestIntent.action == "follow_formation" or requestIntent.action == "regroup"
        -- A moving formation goal values first response over route diversity. The
        -- old code waited for up to two optional alternatives after the primary
        -- route was already usable, adding several follow ticks of visible delay.
        local evaluateAlternatives = followRouting and not isMovingTargetIntent(requestIntent)
        local pathOptions = {
            actor = actor,
            blockedEdges = state.blockedEdges,
            blockedSquares = state.blockedSquares,
            routeMemory = state.routeMemory,
            now = now,
            vegetationScale = requestIntent.urgent == true
                and (utility.config("navigationEmergencyVegetationScale") or 0.2) or 1,
            -- Ordinary travel never enters active fire or a live trap. A
            -- survival-critical route may do so only at a deliberately large
            -- cost when topology finds no safe alternative.
            allowHazards = requestIntent.urgent == true,
        }
        if requestIntent.workCampOnly == true then
            pathOptions.squareAdmission = function(square)
                return SC.BaseLife and type(SC.BaseLife.isInside) == "function"
                    and SC.BaseLife.isInside(square) == true
            end
        end
        if requestIntent.stealthAvoidance then
            pathOptions.stealthAvoidance = true
            pathOptions.nodeBudget = utility.config("navigationStealthNodeBudget") or 320
            -- Score against a small refreshable overlay rather than the frozen
            -- request snapshot, so a threat that dies or leaves during this
            -- multi-frame search stops distorting the route (review 3.5).
            local overlay = buildStealthOverlay(requestIntent.snapshot)
            pathOptions.stealthOverlay = overlay
            pathOptions.squarePenalty = function(square)
                return stealthThreatPenalty(square, overlay)
            end
        end
        local stationaryRouting = SC.WorkRoutes.stationaryFastRouteRequested(requestIntent)
        if (followRouting or stationaryRouting or requestedWorkRouteKey ~= nil)
            and state.pathSearch == nil then
            local immediatePath, immediateReason, cachedEntry
            if requestIntent.formationMode == "trail"
                and type(requestIntent.followTrack) == "table" then
                immediatePath = SC.Navigation._followTrackRouteForRequest(
                    sourceSquare, goalSquare, requestIntent.followTrack, pathOptions)
                if immediatePath ~= nil then immediateReason = "player_track_route" end
            end
            if immediatePath == nil then
                if stationaryRouting then
                    pathOptions.maximumSteps = utility.config(
                        "navigationStationaryFastRouteMaximumSteps") or 24
                    SC.WorkRoutes.count("navigation.stationary-fast.lookups")
                end
                immediatePath = SC.Navigation._fastOpenRouteForRequest(
                    sourceSquare, goalSquare, pathOptions)
                if immediatePath ~= nil then
                    immediateReason = stationaryRouting
                        and "fast_stationary_route" or "fast_open_route"
                    if stationaryRouting then
                        SC.WorkRoutes.count("navigation.stationary-fast.hits")
                    end
                elseif stationaryRouting then
                    SC.WorkRoutes.count("navigation.stationary-fast.misses")
                end
            end
            if immediatePath == nil and requestedWorkRouteKey ~= nil then
                immediatePath, cachedEntry = SC.WorkRoutes.lookup(
                    actor, sourceSquare, requestedWorkRouteKey, pathOptions, now)
                if immediatePath ~= nil then immediateReason = "work_route_cache" end
            end
            if immediatePath ~= nil then
                state.path = immediatePath
                state.pathFailure = nil
                state.pathGoalSquare = goalSquare
                state.pathStealthAvoidance = false
                state.pathEmergencyVegetation = false
                state.pathIndex = 2
                state.pathSearchHolding = nil
                state.pathReason = immediateReason
                state.activeWorkRoute = cachedEntry
                state.workRouteKey = requestedWorkRouteKey
                state.expandedNodes = 0
                state.lastPlanDurationMs = 0
                state.routeCandidateCount = 1
                state.routeSelectedIndex = 1
                state.routeSelectedScore = nil
                state.routeEvaluations = nil
                state.lastProgressAt = now
                state.nextRepathAt = now
                    + (utility.config("navigationRepathMs") or 900)
                state.routeReplanCount = (state.routeReplanCount or 0) + 1
                SC.Navigation._resetRouteProjection(state)
            end
        end
        if not state.path then
            local planningGoal = goalSquare
        if state.pathSearch and state.pathSearch.route
            and state.pathSearch.route.startKey == squareKey(sourceSquare)
            and (utility.distance(state.pathSearch.route.goalSquare, goalSquare)
                    < goalResetDistance(requestIntent)
                or SC.Navigation._usefulPendingMovingSearchForRequest(
                    actor, state, goalSquare, requestIntent, now))
            and state.pathSearch.stealthAvoidance == (requestIntent.stealthAvoidance == true)
            and state.pathSearch.followRouting == (followRouting == true)
            and state.pathSearch.alternatives == (evaluateAlternatives == true) then
            planningGoal = state.pathSearch.route.goalSquare
        end
        local searchKey = tostring(squareKey(sourceSquare)) .. ">" .. tostring(squareKey(planningGoal))
            .. ":" .. tostring(requestIntent.stealthAvoidance == true)
            .. ":" .. tostring(followRouting == true)
            .. ":" .. tostring(evaluateAlternatives == true)
        if not state.pathSearch or state.pathSearch.key ~= searchKey then
            state.pathSearch = {
                key = searchKey,
                route = newRouteSearchJob(sourceSquare, planningGoal, requestIntent.snapshot,
                    pathOptions, evaluateAlternatives),
                startedAt = now,
                progressAt = now,
                lastExpanded = 0,
                stealthAvoidance = requestIntent.stealthAvoidance == true,
                followRouting = followRouting == true,
                alternatives = evaluateAlternatives == true,
            }
            state.routeReplanCount = (state.routeReplanCount or 0) + 1
            state.pathSearchHolding = nil
            state.activeWorkRoute = nil
            SC.WorkRoutes.count("navigation.astar.started")
        end
        -- A direct MoveForward pulse from the discarded route otherwise remains
        -- active while this Lua search yields. Acquire a stationary, posture-safe
        -- hold once per search; the first completed route can start immediately.
        holdForPathSearch(actor, state)
        local requestedNodes = tonumber(pathOptions.nodeBudget)
            or utility.config("navigationNodeBudget") or 220
        local grantedNodes = requestedNodes
        if SC.Performance and type(SC.Performance.claimUnits) == "function" then
            grantedNodes = SC.Performance.claimUnits(
                "navigation", requestedNodes, requestIntent.urgent == true)
        end
        if grantedNodes <= 0 then
            if SC.Performance and type(SC.Performance.markYield) == "function" then
                SC.Performance.markYield("navigation", utility.idOf(actor), 0)
            end
            state.pathReason = "path_search_deferred"
            return true, "path_search_deferred"
        end
        local searchStarted = utility.nowMs()
        local searchStatus, path, reason, expanded, routeReport, usedNodes =
            resumeRouteSearch(state.pathSearch.route, grantedNodes)
        local search = state.pathSearch
        local expandedCount = tonumber(expanded) or 0
        if search and (expandedCount > (tonumber(search.lastExpanded) or -1)
                or (tonumber(usedNodes) or 0) > 0) then
            search.lastExpanded = math.max(expandedCount,
                tonumber(search.lastExpanded) or 0)
            search.progressAt = now
        end
        if SC.Performance and type(SC.Performance.record) == "function" then
            SC.Performance.record("navigation", utility.idOf(actor),
                utility.nowMs() - searchStarted, usedNodes or 0, false)
        end
        SC.WorkRoutes.count("navigation.astar.nodes", tonumber(usedNodes) or 0)
        state.pathReason = reason
        state.pathSearchYieldReason = state.pathSearch.route.lastYieldReason
        state.expandedNodes = expanded
        if searchStatus == "pending" then
            SC.WorkRoutes.count("navigation.astar.yields")
            if SC.Performance and type(SC.Performance.markYield) == "function" then
                SC.Performance.markYield("navigation", utility.idOf(actor), usedNodes or 0)
            end
            if service and token and type(service.progress) == "function" then
                service.progress(token, "path_search:" .. tostring(expanded or 0), {
                    expanded = expanded, target = squareKey(planningGoal),
                })
            end
            return true, "path_searching"
        end

        local completedSearch = state.pathSearch and state.pathSearch.route or nil
        local completedSearchStartedAt = state.pathSearch and state.pathSearch.startedAt or now
        state.pathSearch = nil
        state.pathSearchHolding = nil
        state.lastProgressAt = now
        state.path = path
        state.lastPlanDurationMs = math.max(0, now - completedSearchStartedAt)
        SC.WorkRoutes.count(path and "navigation.astar.completed"
            or "navigation.astar.failed")
        SC.Navigation._resetRouteProjection(state)
        state.pathFailure = path and nil or (completedSearch and completedSearch.failure or {
            failureClass = reason == "budget" and "budget_exhausted" or "blocked_static",
            nativeFallbackAllowed = reason == "budget",
            rejections = {},
        })
        state.pathGoalSquare = path and planningGoal or nil
        state.pathStealthAvoidance = requestIntent.stealthAvoidance
        state.stealthRouteExposure = path and routeReport
            and routeReport.selectedDanger or nil
        state.nextStealthRepathAt = requestIntent.stealthAvoidance
            and now + (utility.config("navigationStealthRepathMs") or 1800) or nil
        state.pathEmergencyVegetation = requestIntent.urgent == true and routeReport
            and routeReport.selectedEmergencyVegetation == true
        state.pathIndex = path and 2 or 1
        state.routeCandidateCount = routeReport and routeReport.candidateCount or (path and 1 or 0)
        state.routeSelectedIndex = routeReport and routeReport.selectedOriginalIndex or 1
        state.routeSelectedScore = routeReport and routeReport.selectedScore or nil
        state.routeEvaluations = routeReport and routeReport.routes or nil
        state.nextRepathAt = now + (utility.config("navigationRepathMs") or 900)
        end
    end

    local nextSquare, afterSquare
    if state.path then
        SC.Navigation._correctRouteProjectionForTests(actor, state, sourceSquare, requestIntent, now)
    end
    if state.path then
        while state.pathIndex <= #state.path and sameSquare(sourceSquare, state.path[state.pathIndex]) do
            state.pathIndex = state.pathIndex + 1
            SC.Navigation._resetRouteProjection(state)
        end
        nextSquare = state.path[state.pathIndex]
        afterSquare = state.path[state.pathIndex + 1]
        if nextSquare and not adjacentStep(sourceSquare, nextSquare)
            and tryReusePathSuffix(actor, state, sourceSquare, requestIntent, now) then
            while state.pathIndex <= #state.path
                and sameSquare(sourceSquare, state.path[state.pathIndex]) do
                state.pathIndex = state.pathIndex + 1
            end
            nextSquare = state.path[state.pathIndex]
            afterSquare = state.path[state.pathIndex + 1]
        end
        if nextSquare and not adjacentStep(sourceSquare, nextSquare) then
            -- A native local detour can move the actor off the Lua path while
            -- clearing a collision capsule. Discard that stale edge instead of
            -- issuing a non-adjacent manual step through world geometry.
            releaseStep(state, actor)
            state.path = nil
            state.pathGoalSquare = nil
            state.pathSearch = nil
            state.pathIndex = 1
            state.nextRepathAt = 0
            nextSquare, afterSquare = nil, nil
            requestIntent.pathSearchReason = "path_deviation"
        end
    end

    -- Cached coordinates remain candidates: the route service re-runs full
    -- topology and policy immediately before every retained edge.
    if nextSquare and state.activeWorkRoute then
        local stillPassable, changedReason = SC.WorkRoutes.validateNext(
            actor, state, sourceSquare, nextSquare, goalSquare, requestIntent, now)
        if stillPassable ~= true then
            state.path, state.pathGoalSquare, state.pathSearch = nil, nil, nil
            state.pathIndex, state.nextRepathAt = 1, 0
            state.activeWorkRoute = nil
            state.pathReason = "work_route_changed:"
                .. tostring(changedReason or "route_edge_changed")
            recordMovement(actor, "work_route_changed", {
                status = changedReason or "route_edge_changed",
                targetSquare = goalSquare, nextSquare = nextSquare,
            })
            return true, "work_route_changed"
        end
    end
    if poorSight(actor, sourceSquare, nextSquare or goalSquare, afterSquare, requestIntent) then
        state.weaponReadyUntil = now + (utility.config("navigationWeaponReadyHoldMs") or 1200)
    end
    requestIntent.weaponReady = not insideSecureBase(actor, requestIntent.snapshot)
        and now < (state.weaponReadyUntil or 0)
    if requestIntent.weaponReady and requestIntent.mode == "run" then requestIntent.mode = "walk" end

    local emergencyBushStep = requestIntent.urgent == true
        and (squareHasBush(sourceSquare) or squareHasBush(nextSquare))
    if emergencyBushStep then
        requestIntent.emergencyVegetation = true
        requestIntent.weaponReady = false
        requestIntent.mode = "walk"
    end

    if not nextSquare then
        if requestIntent.pathSearchReason == "path_deviation" then
            return true, "path_deviation_replan"
        end
        -- Native pathing is a deliberate fallback for an exhausted bounded
        -- search or an edge which specifically needs the engine. A proven
        -- static/policy failure must not become an opaque engine path.
        local failure = state.pathFailure
        local allowNative = requestIntent.workCampOnly ~= true and (state.pathReason == "budget"
            or sameSquare(sourceSquare, goalSquare)
            or (type(failure) == "table" and failure.nativeFallbackAllowed == true)
            or requestIntent.nativeAffordance ~= nil)
        if not allowNative then
            local failureClass = type(failure) == "table" and failure.failureClass
                or "blocked_static"
            state.nextRepathAt = now
                + (utility.config("navigationTerminalRetryMs") or 8000)
            recordMovement(actor, "path_terminal", {
                status = failureClass,
                targetSquare = goalSquare,
                detail = state.pathReason,
            })
            return false, "path_blocked:" .. tostring(failureClass)
        end
        requestIntent.action = requestIntent.action or "path"
        requestIntent.targetSquare = goalSquare
        requestIntent.enginePath = true
        requestIntent.pathSearchReason = state.pathReason
        requestIntent.nextSquare = goalSquare
        state.lastAttemptFrom, state.lastAttemptTo = sourceSquare, goalSquare
        local moved, movementReason = utility.move(actor, requestIntent.mode, requestIntent)
        state.lastMovementReason = movementReason
        if not moved then
            if SC.Navigation._scheduleNativeRetryForRequest(
                state, goalSquare, movementReason, now) then
                return true, "native_verification_retry"
            end
            rememberFailure(actor, state, sourceSquare, goalSquare,
                movementReason or "engine_path_rejected", now, "engine_replan")
            return false, "engine_path_rejected"
        end
        SC.WorkRoutes.noteFirstMotion(actor, state, now, "engine_path")
        if service and token then
            if token.phase == "recovering" and type(service.transition) == "function" then
                service.transition(token, "approaching", { strategy = "engine_path" })
            end
            if type(service.progress) == "function" then
                service.progress(token, "move:" .. tostring(squareKey(sourceSquare))
                    .. ">" .. tostring(squareKey(goalSquare)), {
                        strategy = "engine_path",
                    })
            end
        end
        beginNativeLease(state, { goalSquare }, sourceSquare, goalSquare,
            goalSquare, now, "engine_goal", false,
            isMovingTargetIntent(requestIntent), nil, actor, requestIntent)
        return true, "engine_path"
    end

    local barrier, kind = barrierBetween(sourceSquare, nextSquare)
    if requestIntent.workCampOnly == true
        and (not SC.BaseLife or type(SC.BaseLife.isInside) ~= "function"
            or SC.BaseLife.isInside(nextSquare) ~= true) then
        state.path, state.pathGoalSquare, state.pathSearch = nil, nil, nil
        return false, "work_path_outside_camp"
    end
    if kind == "open" then
        local edge = SC.Navigation.edgeAffordance(sourceSquare, nextSquare)
        if edge and edge.kind == "slope" then kind = "slope" end
    end
    if kind == "diagonal" then
        local diagonal = SC.Topology and type(SC.Topology.classifyEdge) == "function"
            and SC.Topology.classifyEdge(actor, sourceSquare, nextSquare, {
                blockedEdges = state.blockedEdges,
                blockedSquares = state.blockedSquares,
                routeMemory = state.routeMemory,
                now = now,
                allowHazards = requestIntent.urgent == true,
            }) or nil
        if not diagonal or diagonal.traversable ~= true
            or diagonal.affordance ~= "diagonal_open" then
            rememberFailure(actor, state, sourceSquare, nextSquare,
                "diagonal_corner", now, "map_replan")
            return false, "diagonal_corner"
        end
        -- Execution can use the ordinary normalized MoveForward vector once the
        -- topology service has proved the whole corner clear.
        barrier, kind = nil, "open"
        requestIntent.diagonalStep = true
    end
    local passageAccepted, passageStatus = SC.Navigation._ensureGroupPassageForRequest(
        actor, state, sourceSquare, nextSquare, kind, requestIntent, now)
    if passageAccepted ~= true then
        return passageAccepted == false and false or true,
            passageStatus or "holding_group_passage"
    end
    if kind == "door" then
        if not barrier then return false, "missing_door" end
        local canCross, status = handleDoor(actor, state, barrier, sourceSquare, nextSquare, now)
        if canCross == false then
            rememberFailure(actor, state, sourceSquare, nextSquare, status, now, "door_replan")
            return false, status
        elseif canCross == nil then
            return true, status
        end
    elseif kind == "window" then
        if not barrier then return false, "missing_window" end
        local canCross, status = handleWindow(actor, state, barrier, sourceSquare, nextSquare, now, requestIntent)
        if canCross == false then
            rememberFailure(actor, state, sourceSquare, nextSquare, status, now, "window_replan")
            return false, status
        end
        return true, status
    elseif kind == "window_frame" then
        if not barrier then return false, "missing_window_frame" end
        local canCross, status = handleWindowFrame(
            actor, barrier, sourceSquare, nextSquare, now, requestIntent)
        if canCross == false then
            rememberFailure(actor, state, sourceSquare, nextSquare, status, now, "window_frame_replan")
            return false, status
        end
        return true, status
    elseif kind == "blocked" or kind == "invalid" then
        rememberFailure(actor, state, sourceSquare, nextSquare, "edge_blocked", now, "map_replan")
        return false, "edge_blocked"
    end

    local tacticalAccepted, tacticalStatus = tacticalStep(
        actor, state, sourceSquare, nextSquare, afterSquare, kind, requestIntent, now
    )
    if tacticalAccepted == false then return false, tacticalStatus end
    if tacticalAccepted == nil then return true, tacticalStatus end
    if kind == "door" or kind == "fence" then
        local aligned, alignmentStatus = alignDoorApproach(
            actor, sourceSquare, nextSquare, requestIntent, kind)
        if aligned == false then
            rememberFailure(actor, state, sourceSquare, nextSquare,
                alignmentStatus or (kind .. "_approach_rejected"), now,
                kind .. "_alignment_replan")
            return false, alignmentStatus or (kind .. "_approach_rejected")
        elseif aligned == nil then
            return true, alignmentStatus or ("aligning_" .. kind .. "_approach")
        end
    end
    if kind == "fence" then
        local climbed, climbStatus = SC.Navigation._handleFenceForRequest(
            actor, barrier, sourceSquare, nextSquare, requestIntent)
        if climbed ~= true then
            rememberFailure(actor, state, sourceSquare, nextSquare,
                climbStatus or "fence_climb_rejected", now, "fence_replan")
            return false, climbStatus or "fence_climb_rejected"
        end
        return true, climbStatus
    end
    configureTacticalRetreat(actor, sourceSquare, nextSquare, afterSquare, kind, requestIntent)

    local blocker = not requestIntent.urgent
        and personalSpaceBlocker(actor, nextSquare, requestIntent.snapshot) or nil
    local blockerType = blocker and (utility.isCompanion(blocker)
        and "companion_crowd" or "player_crowd") or nil
    if not blocker then blocker, blockerType = utility.movingBlocker(nextSquare, actor, { swept = true }) end
    if blocker then
        if state.yieldBlocker ~= blocker then
            state.yieldBlocker = blocker
            state.yieldSince = now
            recordMovement(actor, "traffic_blocked", {
                blocker = blockerType, nextSquare = nextSquare,
                status = "blocked_by:" .. tostring(utility.idOf(blocker)),
            })
        end
        local waited = now - (state.yieldSince or now)
        local forced = state.forcedYieldFor
        local forcedActive = forced == blocker and not utility.isDead(forced)
            and utility.sameFloor(actor, forced)
            and utility.distanceSq(actor, forced) <= 9
        if forcedActive then
            state.yieldBlocker = forced
            if lateralYield(actor, state, sourceSquare, nextSquare, requestIntent, now) then
                recordMovement(actor, "forced_yield", {
                    status = "yielded_for:" .. tostring(utility.idOf(forced)),
                    nextSquare = nextSquare,
                })
                state.forcedYieldFor = nil
                return true, "yielding_to_higher_priority"
            end
            if not utility.stop(actor) then return false, "forced_yield_stop_rejected" end
            return true, "holding_forced_yield"
        elseif forced then
            state.forcedYieldFor = nil
        end
        local companionBlocker = utility.isCompanion(blocker)
        local ownRightOfWay = companionBlocker and hasRightOfWay(actor, requestIntent, blocker)
        if ownRightOfWay and waited < (utility.config("navigationTrafficDeadlockMs") or 2200) then
            local otherState = stateFor(blocker)
            if otherState.forcedYieldFor ~= actor then
                otherState.forcedYieldFor = actor
                recordMovement(actor, "yield_requested", {
                    status = "asked:" .. tostring(utility.idOf(blocker)),
                    nextSquare = nextSquare,
                })
                recordMovement(blocker, "yield_received", {
                    status = "requested_by:" .. tostring(utility.idOf(actor)),
                })
            end
            if not utility.stop(actor) then return false, "traffic_priority_stop_rejected" end
            return true, "waiting_for_companion_yield"
        end
        if waited >= (utility.config("navigationYieldMs") or 900)
            and lateralYield(actor, state, sourceSquare, nextSquare, requestIntent, now) then
            blacklistEdge(state, sourceSquare, nextSquare, blockerType, blocker, now,
                "dynamic_square", "high")
            recordBlocker(actor, state, blockerType, blocker, nextSquare, nil,
                "lateral_yield", now, "dynamic_square", "high")
            return true, "yielding_personal_space"
        end
        if not utility.stop(actor) then return false, "personal_space_stop_rejected" end
        return true, "holding_personal_space"
    end
    state.yieldSince = nil
    state.yieldBlocker = nil
    state.forcedYieldFor = nil
    if not requestIntent.urgent and not reserveStep(nextSquare, actor, state, requestIntent, now) then
        if not utility.stop(actor) then return false, "right_of_way_stop_rejected" end
        return true, "yielding_right_of_way"
    end

    requestIntent.action = requestIntent.action or "move"
    requestIntent.nextSquare = nextSquare
    requestIntent.direction = directionBetween(sourceSquare, nextSquare)
    requestIntent.path = state.path
    requestIntent.pathIndex = state.pathIndex
    local nextDistance = utility.distance(actor, nextSquare)
    if nextDistance <= (utility.config("navigationMicroDistance") or 1.45)
        and not utility.edgeBlocked(sourceSquare, nextSquare) and kind == "open" then
        requestIntent.direct = true
        requestIntent.collisionValidated = true
    else
        requestIntent.direct = false
    end
    if kind == "open" and (squareNearTree(sourceSquare) or squareNearTree(nextSquare)
        or squareNearVehicle(sourceSquare) or squareNearVehicle(nextSquare)) then
        -- Let Build 42's path behavior steer the collision capsule through the
        -- remaining clearance instead of manually pushing toward the tile centre.
        requestIntent.direct = false
        requestIntent.enginePath = true
        requestIntent.vegetationClearance = squareNearTree(sourceSquare)
            or squareNearTree(nextSquare)
        requestIntent.vehicleClearance = squareNearVehicle(sourceSquare)
            or squareNearVehicle(nextSquare)
    end
    if kind == "open" and requestIntent.direct == true
        and requestIntent.enginePath ~= true then
        local aimX, aimY, aimSquare = SC.Navigation._continuousFollowVectorForRequest(
            actor, state, sourceSquare, requestIntent)
        if aimX ~= nil then
            requestIntent.dx, requestIntent.dy = aimX, aimY
            requestIntent.continuousFollow = true
            requestIntent.continuousAimSquare = aimSquare
        end
    end
    if now > (tonumber(state.openDoorDirectUntil) or 0) then
        state.openDoorDirectKey = nil
        state.openDoorDirectUntil = nil
    end
    local openDoorFallback = kind == "door" and objectOpen(barrier)
        and state.openDoorDirectKey == edgeKey(sourceSquare, nextSquare)
        and now <= (tonumber(state.openDoorDirectUntil) or 0)
    if openDoorFallback then
        requestIntent.direct = true
        requestIntent.collisionValidated = true
        requestIntent.openDoorFallback = true
        requestIntent.enginePath = nil
        requestIntent.nativeAffordance = nil
    elseif kind == "door" or kind == "stairs" or kind == "slope" or kind == "fence" then
        -- Once Lua has approved the affordance and any explicit door action,
        -- let PathFindBehavior2 own the complete collision capsule transition.
        -- Reclaiming it as a one-tile MoveForward step is what caused doorway,
        -- stair and fence oscillation in earlier playtests.
        requestIntent.direct = false
        requestIntent.enginePath = true
        requestIntent.nativeAffordance = kind
    end
    if emergencyBushStep then
        -- Build 42 owns collision, slowdown and bush animation for this edge.
        -- Tactical strafe resumes automatically after both squares are clear.
        requestIntent.direct = false
        requestIntent.enginePath = true
        requestIntent.vegetationClearance = true
    end
    state.lastAttemptFrom, state.lastAttemptTo = sourceSquare, nextSquare
    local moved, movementReason = utility.move(actor, requestIntent.mode, requestIntent)
    state.lastMovementReason = movementReason
    if not moved then
        if requestIntent.enginePath == true
            and SC.Navigation._scheduleNativeRetryForRequest(
                state, nextSquare, movementReason, now) then
            return true, "native_verification_retry"
        end
        rememberFailure(actor, state, sourceSquare, nextSquare,
            movementReason or "movement_rejected", now, "direct_replan")
        return false, "movement_rejected"
    end
    SC.WorkRoutes.noteFirstMotion(actor, state, now, state.pathReason or "route_step")
    if service and token then
        if token.phase == "recovering" and type(service.transition) == "function" then
            service.transition(token, "approaching", { strategy = "route_step" })
        end
        if type(service.progress) == "function" then
            service.progress(token, "move:" .. tostring(squareKey(sourceSquare))
                .. ">" .. tostring(squareKey(nextSquare)), {
                    strategy = requestIntent.enginePath == true and "native_edge" or "direct",
                })
        end
    end
    if requestIntent.enginePath == true then
        beginNativeLease(state, { nextSquare }, sourceSquare, nextSquare,
            goalSquare, now, requestIntent.vegetationClearance
                and "vegetation_corridor"
                or requestIntent.vehicleClearance and "vehicle_corridor"
                or "native_edge", false,
            isMovingTargetIntent(requestIntent), requestIntent.nativeAffordance,
            actor, requestIntent)
        extendChoke(state, actor, state.nativeLease and state.nativeLease.expires)
    end
    return true, "moving"
end

local function approachScore(actor, square, options)
    local utility = U()
    local score = utility.distance(actor, square)
    local blocker = utility.movingBlocker(square, actor)
    if blocker then score = score + (utility.config("navigationCrowdPenalty") or 9) end
    if type(options) == "table" and options.stealthAvoidance == true then
        score = score + stealthThreatPenalty(square, options.snapshot)
    end
    return score
end

local function directInteractionEdge(actor, square, centre)
    local object, kind = barrierBetween(square, centre)
    if kind == "open" then return true end
    -- An open door is clear line-of-contact. Closed doors, walls, windows and
    -- fences are traversal boundaries, not valid positions from which to use an
    -- object on the other side.
    return kind == "door" and object ~= nil and objectOpen(object) == true
end

-- Return human-usable positions around a world object/square. Fixed world
-- interactions can request cardinal, line-of-contact candidates so a nearby
-- square across a wall is never mistaken for a usable side of the object.
function Navigation.interactionTargets(actor, objectOrSquare, options)
    local utility = U()
    options = type(options) == "table" and options or {}
    local centre = utility.squareOf(objectOrSquare) or objectOrSquare
    local x, y, z = utility.position(centre)
    if x == nil then return {} end
    local candidates, seen = {}, {}
    local offsets = {
        { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 },
        { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 },
    }
    for _, offset in ipairs(offsets) do
        local square = utility.gridSquare(x + offset[1], y + offset[2], z)
        local key = square and squareKey(square) or nil
        local cardinal = math.abs(offset[1]) + math.abs(offset[2]) == 1
        local interactionEdgeClear = square ~= nil
        if interactionEdgeClear and cardinal then
            if options.requireDirectAccess == true then
                interactionEdgeClear = directInteractionEdge(actor, square, centre)
            else
                interactionEdgeClear = not utility.edgeBlocked(square, centre)
            end
        elseif interactionEdgeClear and options.requireDirectAccess == true then
            -- A player can use a corner counter diagonally when both complete
            -- cardinal decompositions around that corner are open. Requiring
            -- all four legs prevents interaction through either adjacent wall.
            local horizontal = utility.gridSquare(x + offset[1], y, z)
            local vertical = utility.gridSquare(x, y + offset[2], z)
            interactionEdgeClear = horizontal ~= nil and vertical ~= nil
                and directInteractionEdge(actor, square, horizontal)
                and directInteractionEdge(actor, horizontal, centre)
                and directInteractionEdge(actor, square, vertical)
                and directInteractionEdge(actor, vertical, centre)
        end
        if key and not seen[key] and interactionEdgeClear
            and utility.isSquareFree(square)
            and not utility.safehouseBlocker(square, actor) then
            seen[key] = true
            candidates[#candidates + 1] = square
        end
    end
    if #candidates == 0 and options.requireDirectAccess ~= true
        and utility.isSquareFree(centre)
        and not utility.safehouseBlocker(centre, actor) then
        candidates[1] = centre
    end
    table.sort(candidates, function(first, second)
        local firstScore, secondScore = approachScore(actor, first, options),
            approachScore(actor, second, options)
        if firstScore == secondScore then return tostring(squareKey(first)) < tostring(squareKey(second)) end
        return firstScore < secondScore
    end)
    local maximum = math.max(1, tonumber(options.maximum) or 8)
    while #candidates > maximum do table.remove(candidates) end
    return candidates
end

local function multiGoalKey(candidates, action)
    local keys = {}
    for _, square in ipairs(candidates or {}) do keys[#keys + 1] = squareKey(square) end
    table.sort(keys)
    return tostring(action or "approach") .. ":" .. table.concat(keys, "|")
end

function Navigation.requestAny(actor, candidates, movementMode, intent)
    local utility = U()
    if not utility or not utility.isValidActor(actor) then return false, "invalid_actor" end
    intent = utility.copyShallow(intent)
    local permitted, permissionReason = navigationOwnershipPermission(actor, intent)
    if permitted ~= true then return false, permissionReason end
    local traversalHandled, traversalAccepted, traversalReason =
        SC.Navigation._maintainTraversalForRequest(actor, stateFor(actor),
            utility.squareOf(actor), utility.nowMs())
    if traversalHandled then return traversalAccepted, traversalReason end
    local service, token = supervisedToken(intent)
    local valid, seen = {}, {}
    for _, candidate in ipairs(type(candidates) == "table" and candidates or {}) do
        local square = utility.squareOf(candidate) or candidate
        local key = square and squareKey(square) or nil
        local admitted = intent.workCampOnly ~= true
            or (SC.BaseLife and type(SC.BaseLife.isInside) == "function"
                and SC.BaseLife.isInside(square) == true)
        if key and admitted and not seen[key] and utility.isSquareFree(square)
            and not utility.safehouseBlocker(square, actor) then
            seen[key] = true
            valid[#valid + 1] = square
        end
    end
    if #valid == 0 then return false, "no_interaction_targets" end
    local arrival = tonumber(intent.arrivalDistance) or 0.85
    for _, square in ipairs(valid) do
        local arrived = intent.requireSameSquare == true
            and utility.sameSquare(actor, square)
            or intent.requireSameSquare ~= true and utility.arrived(actor, square, {
                targetKind = "square", distance = arrival,
            })
        if arrived then
            local existing = states[actor]
            if existing then
                if existing.nativeLease and SC.NativeActions
                    and type(SC.NativeActions.stopDirect) == "function" then
                    pcall(SC.NativeActions.stopDirect, actor, { preservePosture = true })
                end
                existing.nativeLease = nil
                existing.multiGoalKey, existing.multiGoalSelected = nil, nil
            end
            if service and token and type(service.progress) == "function" then
                service.progress(token, "arrived:" .. tostring(squareKey(square)), {
                    target = squareKey(square), multiGoal = true,
                })
            end
            return true, "arrived", square
        end
    end

    table.sort(valid, function(first, second)
        local firstScore, secondScore = approachScore(actor, first, intent),
            approachScore(actor, second, intent)
        if firstScore == secondScore then return tostring(squareKey(first)) < tostring(squareKey(second)) end
        return firstScore < secondScore
    end)
    local now, state = utility.nowMs(), stateFor(actor)
    local key = multiGoalKey(valid, intent.action)
    local currentTokenSerial = token and tonumber(token.serial) or nil
    if state.actionTokenSerial ~= currentTokenSerial
        or (state.multiGoalOwnerKey ~= nil and state.multiGoalOwnerKey ~= key) then
        if state.nativeLease then clearMovementTransients(actor, state) end
        state.multiGoalSelected = nil
    end
    state.multiGoalOwnerKey = key
    state.multiGoalFailures = state.multiGoalFailures or {}
    for failedKey, expiry in pairs(state.multiGoalFailures) do
        if expiry <= now then state.multiGoalFailures[failedKey] = nil end
    end

    if state.nativeLease and state.nativeLease.multiGoalKey == key then
        local leaseState, leaseStatus = maintainNativeLease(actor, state,
            state.nativeLease.ultimateGoal or valid[1], now)
        if leaseState == "active" then return true, leaseStatus end
        if leaseState == "arrived" then return true, "arrived", leaseStatus end
        if leaseState == "failed" then state.nativeMultiUnavailableUntil = now + 5000 end
    elseif state.nativeLease and state.multiGoalKey ~= key then
        clearMovementTransients(actor, state)
    end

    if intent.workCampOnly ~= true and intent.cohortKey == nil and intent.object == nil
        and now >= (state.nativeMultiUnavailableUntil or 0) and SC.NativeActions
        and type(SC.NativeActions.pathToNearest) == "function" then
        local started, reason = SC.NativeActions.pathToNearest(actor, valid, movementMode or "walk")
        if started then
            state.actionTokenSerial = currentTokenSerial
            state.routeTargetSignature = routeTargetSignature(valid[1], intent)
            state.goalSquare, state.goalAction = valid[1], intent.action
            state.lastAttemptFrom, state.lastAttemptTo = utility.squareOf(actor), valid[1]
            beginNativeLease(state, valid, state.lastAttemptFrom, valid[1],
                valid[1], now, "nearest_interaction", true, false, nil,
                actor, intent)
            state.nativeLease.multiGoalKey = key
            if service and token then
                if type(service.transition) == "function" then
                    service.transition(token, "approaching", {
                        strategy = "nearest_interaction", candidates = #valid,
                    })
                end
                if type(service.progress) == "function" then
                    service.progress(token, "nearest_path_started:" .. key, {
                        candidates = #valid,
                    })
                end
            end
            return true, reason or "nearest_path_started"
        end
        state.nativeMultiUnavailableUntil = now + 5000
        state.nativeMultiFailure = reason
    end

    local lastReason = "no_reachable_interaction_target"
    if state.multiGoalKey == key and state.multiGoalSelected then
        table.sort(valid, function(first, second)
            if first == state.multiGoalSelected then return true end
            if second == state.multiGoalSelected then return false end
            return approachScore(actor, first, intent) < approachScore(actor, second, intent)
        end)
    end
    for _, square in ipairs(valid) do
        local squareId = squareKey(square)
        if not state.multiGoalFailures[squareId] then
            intent.multiGoalFallback = true
            intent.goalCandidates = valid
            state.multiGoalKey, state.multiGoalSelected = key, square
            local accepted, reason = Navigation.request(actor, square,
                movementMode or "walk", intent)
            if accepted then return true, reason, square end
            state.multiGoalFailures[squareId] = now
                + (utility.config("navigationRouteMemoryFailureMs") or 8000)
            if state.multiGoalSelected == square then state.multiGoalSelected = nil end
            lastReason = reason or lastReason
        end
    end
    return false, lastReason
end

function Navigation.interact(actor, object, action, options)
    local utility = U()
    if not utility or not utility.isValidActor(actor) or not object then return false, "invalid_target" end
    local objectSquare = utility.squareOf(object)
    if not objectSquare or utility.distance(actor, objectSquare) > 1.75 then return false, "not_adjacent" end
    local now = utility.nowMs()
    local state = stateFor(actor)
    if action == "open_door" or action == "close_door" then
        local desiredOpen = action == "open_door"
        if objectOpen(object) == desiredOpen then return true, "already_set" end
        if desiredOpen and objectLocked(object) then return false, "locked_door" end
        if not V() or type(V().interactDoor) ~= "function" then
            return false, "traversal_unavailable"
        end
        return V().interactDoor(actor, state, object, action,
            utility.squareOf(actor), objectSquare, now, traversalContext)
    end
    if action == "open_curtain" or action == "close_curtain" then
        local desiredOpen = action == "open_curtain"
        local nextAllowed = curtainTimes[object] or 0
        if now < nextAllowed then return false, "curtain_cooldown" end
        if objectOpen(object) == desiredOpen then return true, "already_set" end
        if not reserve(object, actor, now) then return false, "reserved" end
        local result, toggled = utility.call(object, "ToggleDoor", actor)
        if not toggled or result == false or objectOpen(object) ~= desiredOpen then
            release(object, actor)
            return false, "curtain_failed"
        end
        curtainTimes[object] = now + (utility.config("curtainCooldownMs") or 6000)
        release(object, actor)
        return true, "done"
    end
    local accepted = utility.move(actor, options and options.mode or "walk", {
        action = action,
        object = object,
        targetSquare = objectSquare,
        direction = directionBetween(utility.squareOf(actor), objectSquare),
        interaction = true,
        options = options,
        supervisorToken = options and options.supervisorToken,
    })
    if not accepted then return false, "action_rejected" end
    return true, "delegated"
end

function Navigation.cancel(actor, reason)
    local utility = U()
    local state = actor and states[actor]
    T().cancel(actor, state, trafficContext)
    if not state then return false end
    V().releaseState(actor, state)
    states[actor] = nil
    utility.stop(actor)
    return true, reason or "cancelled"
end

function Navigation.peek(actor)
    return actor and states[actor] or nil
end

function Navigation.status(actor)
    local state = actor and states[actor] or nil
    if not state then return { active = false, phase = "idle" } end
    local blocker = state.lastBlocker
    local current = U().nowMs()
    return {
        active = state.goalSquare ~= nil,
        phase = state.terminalGoalKey and "failed"
            or (state.actorStateName and "waiting")
            or (state.stuckAttempts or 0) > 0 and "recovering"
            or state.nativeLease and "native_path"
            or state.pathSearch and "planning" or "moving",
        action = state.goalAction,
        target = squareKey(state.goalSquare),
        actionTokenSerial = state.actionTokenSerial,
        stuckAttempts = state.stuckAttempts or 0,
        terminalReason = state.terminalReason,
        terminalRetryMs = state.terminalRetryAt
            and math.max(0, state.terminalRetryAt - current) or nil,
        blockerType = blocker and blocker.type or nil,
        blockerSquare = blocker and blocker.squareKey or nil,
        blockerEvidenceClass = blocker and blocker.evidenceClass or nil,
        blockerConfidence = blocker and blocker.confidence or nil,
        pathFailureClass = state.pathFailure and state.pathFailure.failureClass or nil,
        nativeFallbackAllowed = state.pathFailure
            and state.pathFailure.nativeFallbackAllowed == true or nil,
        pathReason = state.pathReason,
        expandedNodes = state.expandedNodes or 0,
        lastPlanDurationMs = state.lastPlanDurationMs,
        lastFirstMotionMs = state.lastFirstMotionMs,
        lastFirstMotionStrategy = state.lastFirstMotionStrategy,
        workRouteCached = state.activeWorkRoute ~= nil,
        actorState = blocker and blocker.actorState or state.actorStateName,
        recoveryResult = blocker and blocker.recoveryResult or nil,
    }
end

function Navigation.findPath(sourceSquare, destinationSquare, options)
    return boundedPath(sourceSquare, destinationSquare, options)
end

-- Test/debug contract for the same resumable search used by production
-- movement. Callers own the returned job and may advance it with a bounded
-- number of node expansions per frame.
function Navigation.beginPathSearch(sourceSquare, destinationSquare, snapshot, options)
    options = type(options) == "table" and options or {}
    return newRouteSearchJob(sourceSquare, destinationSquare, snapshot, options,
        options.alternatives == true)
end

function Navigation.resumePathSearch(job, nodeQuota)
    return resumeRouteSearch(job, nodeQuota)
end

function Navigation.evaluateRoutes(sourceSquare, destinationSquare, snapshot, options)
    local pathOptions = U().copyShallow(options)
    if pathOptions.stealthAvoidance == true then
        pathOptions.nodeBudget = pathOptions.nodeBudget
            or U().config("navigationStealthNodeBudget") or 320
        pathOptions.squarePenalty = function(square)
            return stealthThreatPenalty(square, snapshot)
        end
    end
    local path, reason, expanded, report = chooseFollowRoute(
        sourceSquare, destinationSquare, snapshot, pathOptions)
    report = report or {
        candidateCount = path and 1 or 0,
        selectedOriginalIndex = path and 1 or nil,
        routes = {},
    }
    report.path = path
    report.reason = reason
    report.expandedNodes = expanded
    report.stealthAvoidance = pathOptions.stealthAvoidance == true
    report.stealthExposure = path and report.selectedDanger or nil
    report.emergencyVegetation = path
        and report.selectedEmergencyVegetation == true or false
    return report
end

function Navigation.findOutdoorPath(sourceSquare, options)
    local scale = type(options) == "table" and options.vegetationScale or nil
    return boundedOutdoorPath(sourceSquare, scale)
end

function Navigation.rememberPosition(actor)
    local utility = U()
    if not utility or not utility.isValidActor(actor) then return false, "invalid_actor" end
    local state = stateFor(actor)
    observeSquare(state, utility.squareOf(actor))
    return true, state.wasIndoor and "indoors" or "outdoors"
end

function Navigation.retreatTarget(actor, snapshot)
    local utility = U()
    if not utility or not utility.isValidActor(actor) then return nil, { source = "none", reason = "invalid_actor" } end
    local currentSquare = utility.squareOf(actor)
    local state = stateFor(actor)
    observeSquare(state, currentSquare)
    -- Senses has already ranked and live-validated these local topology nodes.
    -- In an indoor combat pulse, use one immediately rather than synchronously
    -- running the up-to-160-node outdoor Dijkstra (and possibly its vegetation
    -- retry) before the companion is allowed to move away from a bite.
    if currentSquare and not squareIsOutdoor(currentSquare)
        and type(snapshot) == "table" and type(snapshot.escapeSquares) == "table" then
        for _, candidate in ipairs(snapshot.escapeSquares) do
            if type(candidate) == "table" and candidate.square ~= nil
                and utility.isSquareFree(candidate.square) then
                return candidate.square, {
                    source = "validated_local_escape",
                    danger = tonumber(candidate.danger) or 0,
                    outdoors = candidate.outdoors == true,
                    distance = tonumber(candidate.distance),
                    traversalCost = tonumber(candidate.traversalCost),
                    snapshotTime = snapshot.time,
                    validated = true,
                }
            end
        end
    end
    local target, plan = chooseRememberedEgress(state, currentSquare, utility.nowMs(), snapshot)
    if target then
        plan.snapshotTime = type(snapshot) == "table" and snapshot.time or nil
        return target, plan
    end
    return nil, plan
end

function Navigation.reset(actor)
    if actor then
        Navigation.cancel(actor, "reset")
    else
        states = setmetatable({}, { __mode = "k" })
        curtainTimes = setmetatable({}, { __mode = "k" })
        SC.WorkRoutes.reset()
        T().reset()
        V().reset()
    end
end

return Navigation
