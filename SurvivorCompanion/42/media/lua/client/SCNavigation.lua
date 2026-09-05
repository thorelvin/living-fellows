-- SPDX-License-Identifier: MIT

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
if not SC.GameplayUtil and type(require) == "function" then pcall(require, "SCGameplayUtil") end
if not SC.Performance and type(require) == "function" then pcall(require, "SCPerformance") end

SC.Navigation = SC.Navigation or {}
local Navigation = SC.Navigation
local states = setmetatable({}, { __mode = "k" })
local reservations = setmetatable({}, { __mode = "k" })
local curtainTimes = setmetatable({}, { __mode = "k" })
local chokeReservations = {}
local chokeWaiters = setmetatable({}, { __mode = "k" })
local trafficSequence = 0
local nextChokeSweepAt = 0
local stepReservations = {}
local nextStepSweepAt = 0

local function U()
    return SC.GameplayUtil
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

local function adjacentStep(a, b)
    local ax, ay, az = U().position(a)
    local bx, by, bz = U().position(b)
    if ax == nil or bx == nil then return false end
    local dx, dy = math.abs(math.floor(ax) - math.floor(bx)),
        math.abs(math.floor(ay) - math.floor(by))
    local dz = math.abs(math.floor(az or 0) - math.floor(bz or 0))
    return dx + dy <= 1 and dz <= 1
end

local function squareKey(square)
    return U().squareKey(square)
end

local function edgeKey(fromSquare, toSquare)
    local fromKey, toKey = squareKey(fromSquare), squareKey(toSquare)
    if not fromKey or not toKey then return nil end
    return fromKey .. ">" .. toKey
end

local function blacklistEdge(state, fromSquare, toSquare, blockerType, object, now, dynamic)
    local key = edgeKey(fromSquare, toSquare)
    if not key then return nil end
    state.blockedEdges = state.blockedEdges or {}
    local duration = dynamic and (U().config("navigationDynamicBlockedEdgeMs") or 1100)
        or (U().config("navigationBlockedEdgeMs") or 4500)
    state.blockedEdges[key] = {
        type = blockerType or "unknown",
        object = object,
        square = toSquare,
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
end

local function edgeBlacklistEntry(blockedEdges, fromSquare, toSquare, now)
    local key = edgeKey(fromSquare, toSquare)
    local entry = key and type(blockedEdges) == "table" and blockedEdges[key] or nil
    if entry and (tonumber(entry.expires) or 0) > (now or U().nowMs()) then return entry end
    if entry and key then blockedEdges[key] = nil end
    return nil
end

local function recordBlocker(actor, state, blockerType, object, square, actorState, recovery, now)
    local entry = {
        type = blockerType or "unknown",
        object = object,
        objectLabel = U().objectLabel(object),
        square = square,
        squareKey = squareKey(square) or "unknown",
        actorState = actorState or "none",
        recoveryResult = recovery or "pending",
        time = now or U().nowMs(),
    }
    state.lastBlocker = entry
    recordMovement(actor, "blocker", {
        blocker = entry.type, recovery = entry.recoveryResult,
        targetSquare = entry.square, status = entry.actorState,
        detail = entry.objectLabel,
    })
    state.blockerHistory = state.blockerHistory or {}
    state.blockerHistory[#state.blockerHistory + 1] = entry
    while #state.blockerHistory > 8 do table.remove(state.blockerHistory, 1) end
    U().diagnostic("navigation-blocker", actor,
        "type=" .. tostring(entry.type)
        .. " object=" .. tostring(entry.objectLabel)
        .. " square=" .. tostring(entry.squareKey)
        .. " state=" .. tostring(entry.actorState)
        .. " recovery=" .. tostring(entry.recoveryResult))
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
    if math.abs(dx) >= math.abs(dy) then return dx >= 0 and "east" or "west" end
    return dy >= 0 and "south" or "north"
end

local function barrierBetween(fromSquare, toSquare)
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
    local utility = U()
    local value, ok = utility.call(object, "IsOpen")
    if ok then return value == true end
    value, ok = utility.call(object, "isOpen")
    return ok and value == true
end

local function objectLocked(object)
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
    local utility = U()
    local value, ok = utility.call(object, "isBarricaded")
    if ok and value then return true end
    local barricade, barricadeOk = utility.call(object, "getBarricadeForCharacter", nil)
    return barricadeOk and barricade ~= nil
end

local function windowSmashed(window)
    local value, ok = U().call(window, "isSmashed")
    return ok and value == true
end

local function windowGlassRemoved(window)
    local value, ok = U().call(window, "isGlassRemoved")
    return ok and value == true
end

local function windowInvincible(window)
    local value, ok = U().call(window, "isInvincible")
    return ok and value == true
end

local function canClimbThrough(object, actor)
    local value, ok = U().call(object, "canClimbThrough", actor)
    if ok then return value == true end
    value, ok = U().call(object, "canClimbThrough", nil)
    return not ok or value == true
end

local function objectStateSignature(object)
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
    if not entry then return 0 end
    if (tonumber(entry.expires) or 0) <= (now or U().nowMs())
        or entry.objectState ~= objectStateSignature(entry.object) then
        memory[key] = nil
        return 0
    end
    if entry.success == true then
        return -(U().config("navigationRouteMemorySuccessBonus") or 0.25)
    end
    return U().config("navigationRouteMemoryFailurePenalty") or 4.5
end

local function reserve(object, actor, now)
    if not object then return true end
    local existing = reservations[object]
    if existing and existing.actor ~= actor and existing.expires > now then return false end
    reservations[object] = {
        actor = actor,
        expires = now + (U().config("navigationReservationMs") or 8000),
    }
    return true
end

local function release(object, actor)
    local existing = object and reservations[object]
    if existing and existing.actor == actor then reservations[object] = nil end
end

local function squareHasStairs(square)
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

local function squareIsOutdoor(square)
    if not square then return false end
    local room, ok = U().call(square, "getRoom")
    return ok and room == nil
end

local function squareHasTree(square)
    if not square then return false end
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
    if utility.isSquareFree(requestedSquare) and not squareHasTree(requestedSquare) then
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
                    if square and utility.isSquareFree(square) and not squareHasTree(square) then
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
    if not square then return 0 end
    local utility = U()
    if squareHasTree(square) then return utility.config("navigationTreePenalty") or 12 end
    return squareHasBush(square) and (utility.config("navigationBushPenalty") or 5.5) or 0
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
    if edgeBlacklistEntry(options.blockedEdges, fromSquare, toSquare, options.now) then
        return false, math.huge, "blacklisted_edge"
    end
    if not utility.isSquareFree(toSquare) then return false, math.huge end
    if utility.safehouseBlocker(toSquare, options.actor) then
        return false, math.huge, "safehouse_boundary"
    end
    local object, kind = barrierBetween(fromSquare, toSquare)
    if kind == "blocked" or kind == "invalid" then return false, math.huge end
    local thumpable, thumpableKind = edgeThumpableBlocker(
        fromSquare, toSquare, options.actor)
    if thumpable then return false, math.huge, thumpableKind, thumpable end
    local fx, fy, fz = utility.position(fromSquare)
    local tx, ty, tz = utility.position(toSquare)
    if fx ~= nil and tx ~= nil and utility.hasMethod(fromSquare, "testPathFindAdjacent") then
        local nativeBlocked, nativeOk = utility.call(fromSquare, "testPathFindAdjacent",
            options.actor, math.floor(tx - fx), math.floor(ty - fy), math.floor((tz or 0) - (fz or 0)))
        if nativeOk and nativeBlocked == true and kind == "open" then
            return false, math.huge, "native_directional_edge"
        end
    end
    local baseCost
    if kind == "door" then
        if not object then return false, math.huge end
        if objectLocked(object) and not objectOpen(object) then return false, math.huge end
        baseCost = objectOpen(object) and 1 or 2.2
    elseif kind == "window" then
        if not object or objectBarricaded(object) then return false, math.huge end
        if windowInvincible(object) and not objectOpen(object) then return false, math.huge end
        baseCost = objectOpen(object) and 2.5 or (windowSmashed(object) and 4 or 5)
    elseif kind == "window_frame" then
        if not object or not canClimbThrough(object, options.actor) then return false, math.huge end
        baseCost = 2.5
    elseif kind == "fence" then
        baseCost = 2.5
    elseif kind == "stairs" then
        if not (squareHasStairs(fromSquare) or squareHasStairs(toSquare)) then
            return false, math.huge
        end
        baseCost = 3
    else
        baseCost = 1
    end
    local scale = tonumber(vegetationScale)
    if scale == nil then scale = 1 end
    local crowdCost = 0
    if options.allowOccupiedGoal ~= true then
        local moving = utility.movingBlocker(toSquare, options.actor)
        if moving then crowdCost = utility.config("navigationCrowdPenalty") or 9 end
    end
    return true, math.max(0.25, baseCost
        + squareVegetationCost(toSquare) * math.max(0, scale)
        + treeClearanceCost(toSquare) + crowdCost
        + routeMemoryAdjustment(options.routeMemory, fromSquare, toSquare, options.now))
end

local function heuristic(square, goal)
    local utility = U()
    local x, y, z = utility.position(square)
    local gx, gy, gz = utility.position(goal)
    if not x or not gx then return math.huge end
    return math.abs(x - gx) + math.abs(y - gy) + math.abs((z or 0) - (gz or 0)) * 4
end

local function neighbors(square, goal, rotation)
    local utility = U()
    local x, y, z = utility.position(square)
    if not x then return {} end
    local result = {}
    local cardinal = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
    local offset = math.floor(tonumber(rotation) or 0) % #cardinal
    for step = 1, #cardinal do
        local delta = cardinal[((step - 1 + offset) % #cardinal) + 1]
        local other = utility.gridSquare(x + delta[1], y + delta[2], z)
        if other then result[#result + 1] = other end
    end
    local _, _, goalZ = utility.position(goal)
    if goalZ and math.floor(goalZ) ~= math.floor(z or 0) and squareHasStairs(square) then
        local direction = goalZ > z and 1 or -1
        local vertical = utility.gridSquare(x, y, z + direction)
        if vertical then result[#result + 1] = vertical end
        for _, delta in ipairs(cardinal) do
            vertical = utility.gridSquare(x + delta[1], y + delta[2], z + direction)
            if vertical then result[#result + 1] = vertical end
        end
    end
    return result
end

local function reconstruct(nodes, goalKey)
    local reverse, key = {}, goalKey
    while key do
        local node = nodes[key]
        if not node then break end
        reverse[#reverse + 1] = node.square
        key = node.parent
    end
    local path = {}
    for index = #reverse, 1, -1 do path[#path + 1] = reverse[index] end
    return path
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
        local source = threat.actor or threat.square or threat
        local distanceSq = utility.distanceSq(square, source)
        if distanceSq == math.huge then return end
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

-- Binary min-heap for the A* open set (review 3.3), replacing the O(N) lowest-f
-- linear scan + O(N) table.remove that made each expansion O(N) and the search
-- O(N^2). Entries are { key, f, h, seq } and are ordered by f, then h, then a
-- stable insertion sequence so ties resolve exactly as the old scan did (the
-- earliest-inserted node among equal f/h wins), keeping produced paths identical.
-- Improvements push a fresh entry that reuses the node's original seq and leave the
-- superseded entry in place (lazy deletion); the popper drops any entry whose
-- priority no longer matches its node, or whose node is already closed.
local function heapEntryLess(a, b)
    if a.f ~= b.f then return a.f < b.f end
    if a.h ~= b.h then return a.h < b.h end
    return a.seq < b.seq
end

local function heapPush(heap, entry)
    heap[#heap + 1] = entry
    local child = #heap
    while child > 1 do
        local parent = math.floor(child / 2)
        if heapEntryLess(heap[child], heap[parent]) then
            heap[child], heap[parent] = heap[parent], heap[child]
            child = parent
        else
            break
        end
    end
end

local function heapPop(heap)
    local size = #heap
    if size == 0 then return nil end
    local top = heap[1]
    local last = heap[size]
    heap[size] = nil
    size = size - 1
    if size > 0 then
        heap[1] = last
        local parent = 1
        while true do
            local left, right = parent * 2, parent * 2 + 1
            local smallest = parent
            if left <= size and heapEntryLess(heap[left], heap[smallest]) then smallest = left end
            if right <= size and heapEntryLess(heap[right], heap[smallest]) then smallest = right end
            if smallest == parent then break end
            heap[parent], heap[smallest] = heap[smallest], heap[parent]
            parent = smallest
        end
    end
    return top
end

local function newBoundedPathJob(startSquare, goalSquare, options)
    if sameSquare(startSquare, goalSquare) then
        return {
            complete = true, path = { startSquare }, reason = nil, expanded = 0,
            startSquare = startSquare, goalSquare = goalSquare, options = options or {},
        }
    end
    local utility = U()
    options = type(options) == "table" and options or {}
    local nodeBudget = tonumber(options.nodeBudget)
        or utility.config("navigationNodeBudget") or 220
    local penalties = type(options.penalties) == "table" and options.penalties or {}
    local startKey = squareKey(startSquare)
    local goalKey = squareKey(goalSquare)
    if not startKey or not goalKey then
        return {
            complete = true, path = nil, reason = "invalid_square", expanded = 0,
            startSquare = startSquare, goalSquare = goalSquare, options = options,
        }
    end
    local startH = heuristic(startSquare, goalSquare)
    local nodes = {
        [startKey] = { square = startSquare, g = 0, h = startH, f = startH,
            parent = nil, seq = 0 },
    }
    return {
        complete = false,
        path = nil,
        reason = nil,
        startSquare = startSquare,
        goalSquare = goalSquare,
        startKey = startKey,
        goalKey = goalKey,
        nodeBudget = nodeBudget,
        options = options,
        penalties = penalties,
        nodes = nodes,
        open = { { key = startKey, f = startH, h = startH, seq = 0 } },
        seqCounter = 0,
        closed = {},
        expanded = 0,
    }
end

local function resumeBoundedPathJob(job, expansionQuota)
    if type(job) ~= "table" then return "failed", nil, "invalid_job", 0, 0 end
    if job.complete then
        return job.path and "complete" or "failed", job.path, job.reason, job.expanded or 0, 0
    end
    local quota = math.max(1, math.floor(tonumber(expansionQuota) or job.nodeBudget or 1))
    local used = 0
    while #job.open > 0 and job.expanded < job.nodeBudget and used < quota do
        local entry = heapPop(job.open)
        if entry == nil then break end
        local bestKey = entry.key
        local node = job.nodes[bestKey]
        -- Drop a stale/duplicate heap entry: one whose node was closed already, or
        -- whose priority the node has since improved past (a superseded entry left
        -- behind by lazy deletion). Skipping does not consume the expansion quota.
        if node ~= nil and not job.closed[bestKey]
            and entry.f == node.f and entry.h == node.h then
            if bestKey == job.goalKey then
                job.complete = true
                job.path = reconstruct(job.nodes, bestKey)
                return "complete", job.path, nil, job.expanded, used
            end
            job.closed[bestKey] = true
            job.expanded = job.expanded + 1
            used = used + 1
            local current = node
            for _, otherSquare in ipairs(neighbors(
                current.square, job.goalSquare, job.options.neighborRotation)) do
                local otherKey = squareKey(otherSquare)
                if otherKey and not job.closed[otherKey] then
                    local edgeOptions = job.options
                    edgeOptions.allowOccupiedGoal = otherKey == job.goalKey
                    local passable, cost = passableEdge(
                        current.square, otherSquare, job.options.vegetationScale, edgeOptions)
                    if passable then
                        local dynamicPenalty = 0
                        if type(job.options.squarePenalty) == "function" then
                            local value = tonumber(job.options.squarePenalty(otherSquare, current.square))
                            if value and value == value and value > 0 and value < math.huge then
                                dynamicPenalty = value
                            end
                        end
                        local tentative = current.g + cost + (tonumber(job.penalties[otherKey]) or 0)
                            + dynamicPenalty
                        local known = job.nodes[otherKey]
                        if not known or tentative < known.g then
                            -- Reuse the node's original insertion sequence on an
                            -- improvement so ties keep resolving by first-seen order
                            -- (parity with the previous linear scan).
                            local seq = known and known.seq
                            if seq == nil then
                                job.seqCounter = job.seqCounter + 1
                                seq = job.seqCounter
                            end
                            local h = heuristic(otherSquare, job.goalSquare)
                            local fScore = tentative + h
                            job.nodes[otherKey] = {
                                square = otherSquare,
                                g = tentative,
                                h = h,
                                f = fScore,
                                parent = bestKey,
                                seq = seq,
                            }
                            heapPush(job.open, { key = otherKey, f = fScore, h = h, seq = seq })
                        end
                    end
                end
            end
        end
    end
    if #job.open == 0 or job.expanded >= job.nodeBudget then
        job.complete = true
        job.reason = job.expanded >= job.nodeBudget and "budget" or "unreachable"
        return "failed", nil, job.reason, job.expanded, used
    end
    return "pending", nil, "searching", job.expanded, used
end

local function boundedPath(startSquare, goalSquare, options)
    local job = newBoundedPathJob(startSquare, goalSquare, options)
    local status, path, reason, expanded = resumeBoundedPathJob(job, job.nodeBudget or 1)
    if status == "pending" then return nil, "budget", expanded end
    return path, reason, expanded
end

local function egressNeighbors(square)
    local utility = U()
    local x, y, z = utility.position(square)
    if not x then return {} end
    local result = {}
    local cardinal = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
    for _, delta in ipairs(cardinal) do
        local other = utility.gridSquare(x + delta[1], y + delta[2], z)
        if other then result[#result + 1] = other end
    end
    if squareHasStairs(square) then
        for _, dz in ipairs({ -1, 1 }) do
            local vertical = utility.gridSquare(x, y, z + dz)
            if vertical then result[#result + 1] = vertical end
            for _, delta in ipairs(cardinal) do
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
    local nodes = { [startKey] = { square = startSquare, g = 0, parent = nil } }
    local open, inOpen, closed = { startKey }, { [startKey] = true }, {}
    local expanded = 0
    local nodeBudget = U().config("navigationEgressNodeBudget") or 160

    while #open > 0 and expanded < nodeBudget do
        local bestIndex, bestKey, bestCost = 1, open[1], math.huge
        for index, key in ipairs(open) do
            local cost = nodes[key].g
            if cost < bestCost then bestIndex, bestKey, bestCost = index, key, cost end
        end
        table.remove(open, bestIndex)
        inOpen[bestKey] = nil
        local current = nodes[bestKey]
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
                        nodes[otherKey] = { square = otherSquare, g = tentative, parent = bestKey }
                        if not inOpen[otherKey] then
                            open[#open + 1] = otherKey
                            inOpen[otherKey] = true
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

local function routeDanger(path, snapshot, options)
    if type(path) ~= "table" or type(snapshot) ~= "table" then return 0 end
    options = type(options) == "table" and options or {}
    if options.stealthAvoidance == true then
        local exposure = 0
        for index = 2, #path do
            exposure = exposure + stealthThreatPenalty(path[index], snapshot)
        end
        return exposure
    end
    if type(snapshot.threats) ~= "table" then return 0 end
    local danger = 0
    for index = 2, math.min(#path, 6) do
        local square = path[index]
        for threatIndex = 1, math.min(#snapshot.threats, 16) do
            local threat = snapshot.threats[threatIndex]
            local distanceSq = U().distanceSq(square, threat.actor or threat.square)
            if distanceSq <= 2.25 then danger = danger + 5
            elseif distanceSq <= 6.25 then danger = danger + 2
            elseif distanceSq <= 12.25 then danger = danger + 0.5 end
        end
    end
    return danger
end

local function routeCrowding(path, snapshot)
    if type(path) ~= "table" or type(snapshot) ~= "table" then return 0 end
    local actors = {}
    for _, ally in ipairs(snapshot.allies or {}) do
        if ally.actor then actors[#actors + 1] = ally.actor end
    end
    if type(snapshot.player) == "table" and snapshot.player.actor then
        actors[#actors + 1] = snapshot.player.actor
    end
    local crowding = 0
    for index = 2, math.min(#path, 7) do
        for _, other in ipairs(actors) do
            local distanceSq = U().distanceSq(path[index], other)
            if distanceSq <= 0.81 then crowding = crowding + 2
            elseif distanceSq <= 2.25 then crowding = crowding + 0.5 end
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
    local cost = 0
    for index = 2, #path do
        local passable, edgeCost = passableEdge(path[index - 1], path[index])
        if not passable then return math.huge end
        cost = cost + edgeCost
    end
    return cost
end

local function routeSignature(path)
    local parts = {}
    for _, square in ipairs(path or {}) do parts[#parts + 1] = tostring(squareKey(square)) end
    return table.concat(parts, ">")
end

local function routeEvaluation(path, snapshot, originalIndex, options)
    local traversal = routeTraversalCost(path)
    local danger = routeDanger(path, snapshot, options)
    local crowding = routeCrowding(path, snapshot)
    local turns = routeTurns(path)
    return {
        path = path,
        originalIndex = originalIndex,
        traversal = traversal,
        danger = danger,
        crowding = crowding,
        turns = turns,
        score = traversal + danger * (options and options.stealthAvoidance and 1 or 4)
            + crowding * 2 + turns * 0.15,
    }
end

local function chooseFollowRoute(startSquare, goalSquare, snapshot, pathOptions)
    local utility = U()
    pathOptions = type(pathOptions) == "table" and pathOptions or {}
    local primary, reason, expanded = boundedPath(startSquare, goalSquare, pathOptions)
    if not primary then return nil, reason, expanded, nil end
    local candidates = { routeEvaluation(primary, snapshot, 1, pathOptions) }
    local signatures = { [routeSignature(primary)] = true }
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
            local signature = alternative and routeSignature(alternative) or nil
            if alternative and signature and not signatures[signature] then
                signatures[signature] = true
                candidates[#candidates + 1] = routeEvaluation(
                    alternative, snapshot, #candidates + 1, pathOptions)
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
    local previous = job.candidates[#job.candidates] and job.candidates[#job.candidates].path or nil
    if not previous then return false end
    local diversity = utility.config("navigationRouteDiversityPenalty") or 3.5
    for index = 2, math.min(#previous - 1, 12) do
        local key = squareKey(previous[index])
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

local function resumeRouteSearch(job, expansionQuota)
    if type(job) ~= "table" then return "failed", nil, "invalid_job", 0, nil, 0 end
    if job.complete then
        return job.path and "complete" or "failed", job.path, job.reason,
            job.totalExpanded or 0, job.report, 0
    end
    local remaining = math.max(1, math.floor(tonumber(expansionQuota) or 1))
    local totalUsed, transitions = 0, 0
    while remaining > 0 and not job.complete and transitions < 8 do
        transitions = transitions + 1
        local status, path, reason, expanded, used = resumeBoundedPathJob(job.search, remaining)
        used = math.max(0, tonumber(used) or 0)
        totalUsed = totalUsed + used
        remaining = remaining - used
        if status == "pending" then
            return "pending", nil, "searching", job.totalExpanded + expanded, nil, totalUsed
        end

        job.totalExpanded = job.totalExpanded + (tonumber(expanded) or 0)
        if job.phase == "primary" then
            if status ~= "complete" or not path then
                finalizeRouteSearch(job, reason or "unreachable")
            elseif not job.alternatives then
                job.candidates[1] = routeEvaluation(path, job.snapshot, 1, job.pathOptions)
                job.signatures[routeSignature(path)] = true
                finalizeRouteSearch(job)
            else
                job.candidates[1] = routeEvaluation(path, job.snapshot, 1, job.pathOptions)
                job.signatures[routeSignature(path)] = true
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
            if status == "complete" and path then
                local signature = routeSignature(path)
                if not job.signatures[signature] then
                    job.signatures[signature] = true
                    job.candidates[#job.candidates + 1] = routeEvaluation(
                        path, job.snapshot, #job.candidates + 1, job.pathOptions)
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

local function beginInteraction(actor, state, object, action, now, extra, executorOwned)
    if not reserve(object, actor, now) then return false, "reserved" end
    local pending = state.pendingInteraction
    if not pending or pending.object ~= object or pending.action ~= action then
        if executorOwned then
            local movementIntent = U().copyShallow(extra)
            movementIntent.action = action
            movementIntent.object = object
            movementIntent.interaction = true
            movementIntent.targetSquare = U().squareOf(object)
            movementIntent.direction = directionBetween(U().squareOf(actor), movementIntent.targetSquare)
            if not U().move(actor, "walk", movementIntent) then
                release(object, actor)
                return false, "action_rejected"
            end
        end
        pending = { object = object, action = action, startedAt = now, extra = extra }
        state.pendingInteraction = pending
        return true, "interacting"
    end
    return true, "pending"
end

local function completeDoorInteraction(actor, state, object, action, fromSquare, toSquare, now)
    local utility = U()
    local pending = state.pendingInteraction
    if not pending or pending.object ~= object then return false, "missing_interaction" end
    if action == "open_door" and not objectOpen(object) then
        local result, toggled = utility.call(object, "ToggleDoor", actor)
        if not toggled or result == false or not objectOpen(object) then return false, "door_open_failed" end
    elseif action == "close_door" and objectOpen(object) then
        local result, toggled = utility.call(object, "ToggleDoor", actor)
        if not toggled or result == false or objectOpen(object) then return false, "door_close_failed" end
    end
    if action == "open_door" then
        state.openedDoors[#state.openedDoors + 1] = {
            object = object,
            fromSquare = fromSquare,
            toSquare = toSquare,
            openedAt = now,
            expires = now + (utility.config("navigationReservationMs") or 8000),
        }
    else
        release(object, actor)
    end
    state.pendingInteraction = nil
    return true, "done"
end

local function handleDoor(actor, state, door, fromSquare, toSquare, now)
    if objectOpen(door) then return true end
    local obstructed, obstructedOk = U().call(door, "isObstructed")
    if obstructedOk and obstructed == true then return false, "obstructed_door" end
    if objectLocked(door) then return false, "locked_door" end
    local ok, status = beginInteraction(actor, state, door, "open_door", now, {
        fromSquare = fromSquare, toSquare = toSquare,
    }, false)
    if not ok then return false, status end
    local complete, completeStatus = completeDoorInteraction(actor, state, door, "open_door", fromSquare, toSquare, now)
    if not complete then return false, completeStatus end
    if completeStatus ~= "done" then return nil, completeStatus end
    return true
end

local function completeWindowAction(actor, state, window, action, now)
    local utility = U()
    local pending = state.pendingInteraction
    if not pending or pending.object ~= window then return false, "missing_interaction" end
    local delays = {
        open_window = utility.config("windowOpenMs") or 1300,
        smash_window = utility.config("windowSmashMs") or 900,
        remove_glass = utility.config("windowGlassRemovalMs") or 1400,
    }
    if now - pending.startedAt < (delays[action] or 500) then return nil, "interacting" end
    if action == "open_window" and not objectOpen(window) then
        utility.call(actor, "openWindow", window)
        if not objectOpen(window) then
            local _, toggled = utility.call(window, "ToggleWindow", actor)
            if not toggled or not objectOpen(window) then
                return false, "window_open_failed"
            end
        end
    elseif action == "smash_window" and not windowSmashed(window) then
        utility.call(actor, "smashWindow", window)
        if not windowSmashed(window) then
            local _, direct = utility.call(window, "smashWindow", false, false)
            if not direct or not windowSmashed(window) then
                return false, "window_smash_failed"
            end
        end
    elseif action == "remove_glass" and windowSmashed(window) and not windowGlassRemoved(window) then
        local _, removed = utility.call(window, "removeBrokenGlass")
        if not removed or not windowGlassRemoved(window) then
            return false, "glass_removal_failed"
        end
    end
    state.pendingInteraction = nil
    return true, "done"
end

local function handleWindow(actor, state, window, fromSquare, toSquare, now, intent)
    local utility = U()
    if objectBarricaded(window) then return false, "barricaded_window" end
    if windowInvincible(window) and not objectOpen(window) then return false, "invincible_window" end
    local arrival = threatArrivalMs(intent, fromSquare)
    local action
    if objectOpen(window) then
        action = "climb_window"
    elseif windowSmashed(window) then
        if windowGlassRemoved(window) then
            action = "climb_window"
        elseif arrival > (utility.config("windowGlassRemovalMs") or 1400) + (utility.config("windowClimbMs") or 1300) then
            action = "remove_glass"
        else
            action = "climb_window_emergency"
        end
    elseif not objectLocked(window)
        and arrival > (utility.config("windowOpenMs") or 1300) + (utility.config("windowClimbMs") or 1300) then
        action = "open_window"
    else
        -- An intact window is never a climb target. Even under pressure it
        -- must first be opened or smashed; Build 42 then validates the frame.
        action = "smash_window"
    end

    if action == "climb_window" or action == "climb_window_emergency" then
        if not canClimbThrough(window, actor) and action ~= "climb_window_emergency" then
            return false, "unsafe_window_frame"
        end
        if not reserve(window, actor, now) then return false, "reserved" end
        local accepted = utility.move(actor, intent and intent.mode or "walk", {
            action = action,
            object = window,
            fromSquare = fromSquare,
            toSquare = toSquare,
            nextSquare = toSquare,
            targetSquare = toSquare,
            direction = directionBetween(fromSquare, toSquare),
            acceptsInjury = action == "climb_window_emergency",
            supervisorToken = intent and intent.supervisorToken,
        })
        if not accepted then
            release(window, actor)
            return false, "action_rejected"
        end
        return nil, "climbing"
    end

    local ok, status = beginInteraction(actor, state, window, action, now, {
        fromSquare = fromSquare, toSquare = toSquare,
        supervisorToken = intent and intent.supervisorToken,
    }, true)
    if not ok then return false, status end
    local complete, completeStatus = completeWindowAction(actor, state, window, action, now)
    if complete == false then return false, completeStatus end
    if complete == nil then return nil, completeStatus end
    return nil, "reconsider_window"
end

local function handleWindowFrame(actor, frame, fromSquare, toSquare, now, intent)
    local utility = U()
    if not canClimbThrough(frame, actor) then return false, "blocked_window_frame" end
    if not reserve(frame, actor, now) then return false, "reserved" end
    local accepted = utility.move(actor, intent and intent.mode or "walk", {
        action = "climb_window",
        object = frame,
        fromSquare = fromSquare,
        toSquare = toSquare,
        nextSquare = toSquare,
        targetSquare = toSquare,
        direction = directionBetween(fromSquare, toSquare),
        emptyFrame = true,
        supervisorToken = intent and intent.supervisorToken,
    })
    if not accepted then release(frame, actor) return false, "action_rejected" end
    return nil, "climbing_frame"
end

local function doorGeometry(entry, value)
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

local function actorClearOfDoorway(actor, entry)
    local progress = doorGeometry(entry, actor)
    return progress ~= nil
        and progress >= (U().config("doorClearanceDistance") or 0.38)
end

local function occupiesDoorway(value, entry)
    local progress, lateral = doorGeometry(entry, value)
    if progress == nil then return false end
    local clearance = U().config("doorClearanceDistance") or 0.38
    return math.abs(progress) < clearance and lateral <= 0.55
end

local function nearbyOpenedDoor(state, actor)
    for _, entry in ipairs(state.openedDoors or {}) do
        local progress, cross = doorGeometry(entry, actor)
        if objectOpen(entry.object) and progress ~= nil and math.abs(progress) <= 1.15
            and cross <= 1.15 then return entry end
    end
    return nil
end

local function safeToCloseDoor(entry, snapshot, actor)
    local utility = U()
    -- getSquare() changes as soon as the character centre crosses the tile edge.
    -- Keep the door open until the actor's continuous world position has cleared
    -- the leaf, otherwise it can close through the companion's collision capsule.
    if not actorClearOfDoorway(actor, entry) then return false end
    if type(snapshot) ~= "table" then return true end
    for index = 1, math.min(#(snapshot.threats or {}), 12) do
        if utility.distanceSq(entry.object, snapshot.threats[index].actor) <= 4 then return false end
    end
    for _, ally in ipairs(snapshot.allies or {}) do
        local other = ally and (ally.actor or ally) or nil
        if other and other ~= actor and occupiesDoorway(other, entry) then return false end
    end
    local player = snapshot.player
    player = type(player) == "table" and (player.actor or player) or nil
    if player and player ~= actor and occupiesDoorway(player, entry) then return false end
    return true
end

local function closeOwnedDoors(actor, state, now, snapshot)
    local utility = U()
    local write = 1
    for index = 1, #state.openedDoors do
        local entry = state.openedDoors[index]
        local keep = true
        if now >= entry.expires then
            release(entry.object, actor)
            keep = false
        elseif objectOpen(entry.object)
            and not sameSquare(utility.squareOf(actor), entry.fromSquare)
            and utility.distance(actor, entry.toSquare) <= 2.75
            and now - entry.openedAt >= (utility.config("doorCloseDelayMs") or 700)
            and now >= (state.recoveryDoorHoldUntil or 0)
            and safeToCloseDoor(entry, snapshot, actor) then
            local result, toggled = utility.call(entry.object, "ToggleDoor", actor)
            if toggled and result ~= false and not objectOpen(entry.object) then
                release(entry.object, actor)
                keep = false
            end
        elseif not objectOpen(entry.object) then
            release(entry.object, actor)
            keep = false
        end
        if keep then state.openedDoors[write] = entry write = write + 1 end
    end
    for index = #state.openedDoors, write, -1 do state.openedDoors[index] = nil end
end

local function releaseChoke(state, actor)
    local released = state and type(state.chokeReservationKeys) == "table"
        and #state.chokeReservationKeys > 0
    for _, key in ipairs(state and state.chokeReservationKeys or {}) do
        local entry = chokeReservations[key]
        if entry and entry.actor == actor then chokeReservations[key] = nil end
    end
    chokeWaiters[actor] = nil
    if state then
        state.chokeReservationKeys = nil
        state.chokeQueueOwner = nil
        state.chokeQueueSince = nil
    end
    if released then recordMovement(actor, "choke_released", { status = "corridor_clear" }) end
end

local function extendChoke(state, actor, untilAt)
    for _, key in ipairs(state and state.chokeReservationKeys or {}) do
        local entry = chokeReservations[key]
        if entry and entry.actor == actor then
            entry.expires = math.max(tonumber(entry.expires) or 0, tonumber(untilAt) or 0)
        end
    end
end

local function chokeEdgeKey(first, second)
    local firstKey, secondKey = squareKey(first), squareKey(second)
    if not firstKey or not secondKey then return nil end
    if firstKey > secondKey then firstKey, secondKey = secondKey, firstKey end
    return "edge:" .. firstKey .. "<>" .. secondKey
end

local movementPriority

local function waiterOverlaps(keys, waiter)
    if type(waiter) ~= "table" or type(waiter.keys) ~= "table" then return false end
    local wanted = {}
    for _, key in ipairs(keys or {}) do wanted[key] = true end
    for _, key in ipairs(waiter.keys) do if wanted[key] then return true end end
    return false
end

local function waiterBefore(first, second)
    if second == nil then return true end
    if first.priority ~= second.priority then return first.priority > second.priority end
    if first.ticket ~= second.ticket then return first.ticket < second.ticket end
    return tostring(first.id) < tostring(second.id)
end

local function bestChokeWaiter(keys, now)
    local best
    for candidate, waiter in pairs(chokeWaiters) do
        if not waiter or waiter.expires <= now then
            chokeWaiters[candidate] = nil
        elseif waiterOverlaps(keys, waiter) and waiterBefore(waiter, best) then
            best = waiter
        end
    end
    return best
end

local function reserveChokeCorridor(sourceSquare, nextSquare, afterSquare, actor, state, intent, now)
    if now >= nextChokeSweepAt then
        for key, entry in pairs(chokeReservations) do
            if not entry or entry.expires <= now then chokeReservations[key] = nil end
        end
        nextChokeSweepAt = now + 5000
    end
    local keys, seen = {}, {}
    local function add(key)
        if key and not seen[key] then seen[key] = true keys[#keys + 1] = key end
    end
    add(chokeEdgeKey(sourceSquare, nextSquare))
    add(nextSquare and "square:" .. tostring(squareKey(nextSquare)) or nil)
    if (U().config("navigationChokeCorridorNodes") or 3) >= 3 then
        add(chokeEdgeKey(nextSquare, afterSquare))
        add(afterSquare and "square:" .. tostring(squareKey(afterSquare)) or nil)
    end
    if #keys == 0 then return false end
    local owner
    for _, key in ipairs(keys) do
        local existing = chokeReservations[key]
        if existing and existing.actor ~= actor and existing.expires > now then
            owner = existing.actor
            break
        end
    end
    local waiting = chokeWaiters[actor]
    if owner then
        if not waiting then
            trafficSequence = trafficSequence + 1
            waiting = {
                actor = actor, id = tostring(U().idOf(actor)), ticket = trafficSequence,
                since = now,
            }
        end
        waiting.keys = keys
        waiting.priority = movementPriority(intent)
        waiting.expires = now + (U().config("navigationTrafficWaiterMs") or 5000)
        chokeWaiters[actor] = waiting
        if state.chokeQueueOwner ~= owner then
            recordMovement(actor, "choke_queued", {
                status = "waiting_for:" .. tostring(U().idOf(owner)),
                nextSquare = nextSquare,
            })
        end
        state.chokeQueueOwner = owner
        state.chokeQueueSince = state.chokeQueueSince or now
        return false, owner
    end
    local retained = type(state.chokeReservationKeys) == "table"
        and #state.chokeReservationKeys == #keys
    if retained then
        local currentKeys = {}
        for _, key in ipairs(state.chokeReservationKeys) do currentKeys[key] = true end
        for _, key in ipairs(keys) do
            local entry = chokeReservations[key]
            if not currentKeys[key] or not entry or entry.actor ~= actor then
                retained = false
                break
            end
        end
    end
    if retained then
        local expiry = now + (U().config("navigationChokeReservationMs") or 1400)
        for _, key in ipairs(keys) do chokeReservations[key].expires = expiry end
        chokeWaiters[actor] = nil
        state.chokeQueueOwner, state.chokeQueueSince = nil, nil
        return true
    end
    local best = bestChokeWaiter(keys, now)
    if best and best.actor ~= actor then
        state.chokeQueueOwner = best.actor
        state.chokeQueueSince = state.chokeQueueSince or now
        return false, best.actor
    end
    releaseChoke(state, actor)
    local expiry = now + (U().config("navigationChokeReservationMs") or 1400)
    local priority = movementPriority(intent)
    local id = tostring(U().idOf(actor))
    for _, key in ipairs(keys) do
        chokeReservations[key] = {
            actor = actor, id = id, priority = priority, expires = expiry,
        }
    end
    state.chokeReservationKeys = keys
    state.chokeQueueOwner = nil
    state.chokeQueueSince = nil
    recordMovement(actor, "choke_acquired", {
        status = "keys:" .. tostring(#keys), nextSquare = nextSquare,
    })
    return true
end

movementPriority = function(intent)
    if type(intent) ~= "table" then return 10 end
    if intent.urgent == true then return 100 end
    if tonumber(intent.movementPriority) then return tonumber(intent.movementPriority) end
    local action = tostring(intent.action or "")
    if string.find(action, "retreat", 1, true) or string.find(action, "rescue", 1, true)
        or string.find(action, "combat", 1, true) then return 80 end
    if string.find(action, "medical", 1, true) then return 70 end
    if string.find(action, "conversation", 1, true) then return 30 end
    if string.find(action, "follow", 1, true) or action == "regroup" then return 20 end
    return 40
end

local function releaseStep(state, actor)
    local key = state and state.stepReservationKey or nil
    local reservation = key and stepReservations[key] or nil
    if reservation and reservation.actor == actor then stepReservations[key] = nil end
    if state then state.stepReservationKey = nil end
end

local function reserveStep(square, actor, state, intent, now)
    if now >= nextStepSweepAt then
        for key, entry in pairs(stepReservations) do
            if not entry or entry.expires <= now then stepReservations[key] = nil end
        end
        nextStepSweepAt = now + 3000
    end
    local key = squareKey(square)
    if not key then return false end
    local priority = movementPriority(intent)
    local id = tostring(U().idOf(actor))
    local existing = stepReservations[key]
    if existing and existing.actor ~= actor and existing.expires > now then
        if state.stepQueueOwner ~= existing.actor then
            recordMovement(actor, "step_queued", {
                status = "waiting_for:" .. tostring(existing.id), nextSquare = square,
            })
        end
        state.stepQueueOwner = existing.actor
        state.stepQueueSince = state.stepQueueSince or now
        return false, existing.actor
    end
    releaseStep(state, actor)
    stepReservations[key] = {
        actor = actor,
        id = id,
        priority = priority,
        expires = now + (U().config("navigationStepReservationMs") or 450),
    }
    state.stepReservationKey = key
    state.stepQueueOwner = nil
    state.stepQueueSince = nil
    return true
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
    local spacing = utility.config("navigationPersonalSpace") or 0.9
    local spacingSq = spacing * spacing
    for _, ally in ipairs(snapshot.allies or {}) do
        if ally.actor and ally.actor ~= actor and utility.sameFloor(ally.actor, nextSquare)
            and utility.distanceSq(ally.actor, nextSquare) < spacingSq then return ally.actor end
    end
    local player = snapshot.player
    if type(player) == "table" and player.actor and player.actor ~= actor
        and utility.sameFloor(player.actor, nextSquare)
        and utility.distanceSq(player.actor, nextSquare) < spacingSq then return player.actor end
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
        if square and utility.isSquareFree(square) and not utility.edgeBlocked(sourceSquare, square)
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

    local key = "room-entry:" .. tostring(squareKey(sourceSquare))
        .. ":" .. tostring(squareKey(nextSquare))
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
    local stair = kind == "stairs" or squareHasStairs(sourceSquare) or squareHasStairs(nextSquare)
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

local function clearMovementTransients(actor, state)
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
    state.pathGoalSquare = nil
    state.nativeLease = nil
end

local function updateProgress(actor, state, now)
    local utility = U()
    local x, y, z = utility.position(actor)
    if not x then return false end
    local currentSquare = utility.squareOf(actor)
    if currentSquare and state.lastAttemptFrom and state.lastAttemptTo
        and sameSquare(currentSquare, state.lastAttemptTo) then
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
            or context.player ~= nil)
end

local function goalResetDistance(context)
    if isMovingTargetIntent(context) then
        return U().config("navigationMovingGoalResetDistance") or 1.5
    end
    return U().config("navigationGoalResetDistance") or 3.0
end
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

local function beginNativeLease(state, targets, fromSquare, toSquare, ultimateGoal,
        now, reason, multiGoal, movingTarget)
    local list = nativeTargets(targets)
    local leaseMs = movingTarget and (U().config("navigationMovingLeaseMs") or 2500)
        or (U().config("navigationNativeLeaseMs") or 6500)
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
    }
end

local function nativeLeaseArrival(actor, lease)
    local arrival = U().config("navigationArrivalDistance") or 0.6
    for _, target in ipairs(lease and lease.targets or {}) do
        if U().distance(actor, target) <= arrival or sameSquare(U().squareOf(actor), target) then
            return target
        end
    end
    return nil
end

local function maintainNativeLease(actor, state, goalSquare, now)
    local lease = state.nativeLease
    if not lease then return nil, nil end
    if lease.ultimateGoalKey and squareKey(goalSquare) ~= lease.ultimateGoalKey
        and lease.ultimateGoal and U().distance(lease.ultimateGoal, goalSquare)
            >= goalResetDistance(lease) then
        state.nativeLease = nil
        return "cancelled", "native_goal_changed"
    end
    local arrived = nativeLeaseArrival(actor, lease)
    if arrived then
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
            state.lastAttemptFrom = U().squareOf(actor) or lease.fromSquare
            state.lastAttemptTo = nextSquare
        end
    end
    if now <= lease.expires and (actorState ~= nil or telemetry.active == true) then
        extendChoke(state, actor, lease.expires)
        lease.lastActiveAt = now
        state.lastProgressAt = now
        local status = actorState and "native_animation_" .. tostring(actorState)
            or telemetry.turningToObstacle and "native_turning_to_obstacle"
            or telemetry.pending and "native_path_pending" or "native_path_owned"
        return "active", status
    end
    if now - lease.startedAt < (U().config("navigationNativeStartGraceMs") or 650) then
        state.lastProgressAt = now
        return "active", "native_path_starting"
    end
    state.nativeLease = nil
    return "failed", now > lease.expires and "native_path_timeout" or "native_path_failed"
end

local function classifyMovementBlocker(actor, fromSquare, toSquare, movementReason)
    local utility = U()
    local actorState, stateObject = utility.movementStateBlocker(actor)
    if actorState then
        return { type = "actor_state", object = stateObject, actorState = actorState,
            square = fromSquare, dynamic = true }
    end
    local collided, ok = utility.call(actor, "isCollidedWithVehicle")
    if ok and collided == true then
        return { type = "vehicle", square = toSquare or fromSquare }
    end
    collided, ok = utility.call(actor, "isCollidedWithDoor")
    if ok and collided == true then
        local object = select(1, utility.call(actor, "getCollidedObject"))
        return { type = "door", object = object, square = toSquare or fromSquare }
    end
    local object, objectOk = utility.call(actor, "getCollidedObject")
    if objectOk and object ~= nil then
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
    local static, staticKind = utility.squareStaticBlocker(toSquare)
    if static then return { type = staticKind, object = static, square = toSquare } end
    local thumpable, thumpableKind = edgeThumpableBlocker(fromSquare, toSquare, actor)
    if thumpable then return { type = thumpableKind, object = thumpable, square = toSquare } end
    local moving, movingKind = utility.movingBlocker(toSquare, actor)
    if moving then return { type = movingKind, object = moving, square = toSquare, dynamic = true } end
    if squareHasStairs(fromSquare) or squareHasStairs(toSquare) then
        return { type = "stairs_or_slope", square = toSquare }
    end
    local reason = string.lower(tostring(movementReason or ""))
    if string.find(reason, "continuous_collision", 1, true) then
        return { type = "continuous_geometry", square = toSquare }
    end
    collided, ok = utility.call(actor, "isCollidedThisFrame")
    if ok and collided == true then return { type = "world_collision", square = toSquare } end
    return { type = "unknown", square = toSquare or fromSquare }
end

local function rememberFailure(actor, state, fromSquare, toSquare, reason, now, recovery)
    local blocker = classifyMovementBlocker(actor, fromSquare, toSquare, reason)
    local object, kind = barrierBetween(fromSquare, toSquare)
    rememberRouteEdge(state, fromSquare, toSquare, false,
        blocker.type or kind, blocker.object or object, now)
    if blocker.type ~= "actor_state" and fromSquare and toSquare then
        blacklistEdge(state, fromSquare, toSquare, blocker.type, blocker.object, now, blocker.dynamic)
    end
    recordBlocker(actor, state, blocker.type, blocker.object, blocker.square,
        blocker.actorState, recovery or "edge_blacklisted", now)
    state.path = nil
    state.pathGoalSquare = nil
    state.pathIndex = 1
    state.nextRepathAt = 0
    return blocker
end

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
        if (actorState == "wall_collision_state" or actorState == "climbing")
            and elapsed >= stuckThreshold
            and now >= (state.nextActorStateRecoveryAt or 0) then
            if SC.NativeActions and type(SC.NativeActions.stopDirect) == "function" then
                pcall(SC.NativeActions.stopDirect, actor, { preservePosture = true })
            else
                utility.stop(actor)
            end
            if actorState == "climbing" and actorSquare and state.lastAttemptTo then
                blacklistEdge(state, actorSquare, state.lastAttemptTo,
                    "actor_state", nil, now, false)
            end
            state.path = nil
            state.pathGoalSquare = nil
            state.pathSearch = nil
            state.pathIndex = 1
            state.nextRepathAt = 0
            state.nextActorStateRecoveryAt = now + grace
            activelyRecovered = true
            recovery = actorState == "climbing" and "cancelled_stuck_climb"
                or "cancelled_stale_wall_collision"
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
        return true, true, "waiting_" .. tostring(actorState)
    end
    if state.actorStateName ~= nil then
        state.actorStateName = nil
        state.actorStateSince = nil
        state.nextActorStateRecoveryAt = nil
        state.nextActorStateDiagnosticAt = nil
        -- Clearing a native animation is genuine progress. Without this reset,
        -- the generic stuck timer can immediately fire in the same update.
        state.lastProgressAt = now
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
        return true, false, beginTerminalEpisode(actor, state, actorSquare,
            goalSquare, intent, preview, now)
    end
    local failedFrom = state.lastAttemptFrom or actorSquare
    local failedTo = state.lastAttemptTo or goalSquare
    local blocker = classifyMovementBlocker(actor, failedFrom, failedTo, state.lastMovementReason)
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
        blacklistEdge(state, failedFrom, failedTo, blocker.type, blocker.object, now, blocker.dynamic)
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
    state.trafficPriority = movementPriority(intent)
    state.trafficAction = type(intent) == "table" and intent.action or "move"
    sweepBlockedEdges(state, now)
    observeSquare(state, sourceSquare)
    local requestIntent = utility.copyShallow(intent)
    requestIntent.targetSquare = goalSquare
    requestIntent.requestedGoalSquare = requestedGoalSquare
    requestIntent.goalAdjustedForObstacle = goalAdjusted == true
    requestIntent.direction = directionBetween(sourceSquare, goalSquare)
    requestIntent.mode = movementMode or requestIntent.mode or "walk"
    requestIntent.stealthAvoidance = stealthAvoidanceRequested(
        actor, requestIntent.mode, requestIntent)
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

    if utility.distance(actor, goalSquare) <= (utility.config("navigationArrivalDistance") or 0.6)
        or sameSquare(sourceSquare, goalSquare) then
        state.goalSquare = goalSquare
        state.goalAction = requestIntent.action
        state.path = nil
        state.pathGoalSquare = nil
        state.pathIndex = 1
        state.arrivedAt = now
        state.stuckAttempts = 0
        state.actionTokenSerial = currentTokenSerial
        state.routeTargetSignature = currentTargetSignature
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
        or (previousTargetSignature ~= nil
            and previousTargetSignature ~= currentTargetSignature)
    if goalChanged then
        local previousGoal = state.goalSquare
        local previousAction = tostring(state.goalAction or "")
        local requestedAction = tostring(requestIntent.action or "")
        local goalShift = previousGoal and utility.distance(previousGoal, goalSquare) or math.huge
        local materialGoalChange = previousGoal == nil
            or previousAction ~= requestedAction
            or goalShift >= (utility.config("navigationGoalResetDistance") or 3.0)
            or ownershipChanged
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
            clearTerminalEpisode(actor, state, "route_owner_or_goal_changed", now)
        end
    elseif ownershipChanged then
        clearMovementTransients(actor, state)
        state.path = nil
        state.pathGoalSquare = nil
        state.pathIndex = 1
        state.nextRepathAt = 0
        clearTerminalEpisode(actor, state, "route_owner_changed", now)
    end
    state.actionTokenSerial = currentTokenSerial
    state.routeTargetSignature = currentTargetSignature

    local terminal, terminalReason = terminalEpisodeActive(
        actor, state, sourceSquare, goalSquare, requestIntent, now)
    if terminal then
        return false, terminalReason
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

    local snapshot = requestIntent.snapshot
    local currentThreats = type(snapshot) == "table" and type(snapshot.stealthThreats) == "table"
        and #snapshot.stealthThreats
        or (type(snapshot) == "table" and type(snapshot.threats) == "table"
            and #snapshot.threats or 0)
    local rememberedThreat = type(snapshot) == "table"
        and type(snapshot.lastKnownDanger) == "table"
    local pathGoalDrifted = state.path and state.pathGoalSquare
        and utility.distance(state.pathGoalSquare, goalSquare)
            >= (utility.config("navigationGoalResetDistance") or 3.0)
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
        local pathOptions = {
            actor = actor,
            blockedEdges = state.blockedEdges,
            routeMemory = state.routeMemory,
            now = now,
            vegetationScale = requestIntent.urgent == true
                and (utility.config("navigationEmergencyVegetationScale") or 0.2) or 1,
        }
        if requestIntent.stealthAvoidance then
            pathOptions.stealthAvoidance = true
            pathOptions.nodeBudget = utility.config("navigationStealthNodeBudget") or 320
            pathOptions.squarePenalty = function(square)
                return stealthThreatPenalty(square, requestIntent.snapshot)
            end
        end
        local planningGoal = goalSquare
        if state.pathSearch and state.pathSearch.route
            and state.pathSearch.route.startKey == squareKey(sourceSquare)
            and utility.distance(state.pathSearch.route.goalSquare, goalSquare)
                < (utility.config("navigationGoalResetDistance") or 3.0)
            and state.pathSearch.stealthAvoidance == (requestIntent.stealthAvoidance == true)
            and state.pathSearch.followRouting == (followRouting == true) then
            planningGoal = state.pathSearch.route.goalSquare
        end
        local searchKey = tostring(squareKey(sourceSquare)) .. ">" .. tostring(squareKey(planningGoal))
            .. ":" .. tostring(requestIntent.stealthAvoidance == true)
            .. ":" .. tostring(followRouting == true)
        if not state.pathSearch or state.pathSearch.key ~= searchKey then
            state.pathSearch = {
                key = searchKey,
                route = newRouteSearchJob(sourceSquare, planningGoal, requestIntent.snapshot,
                    pathOptions, followRouting),
                startedAt = now,
                stealthAvoidance = requestIntent.stealthAvoidance == true,
                followRouting = followRouting == true,
            }
        end
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
        if SC.Performance and type(SC.Performance.record) == "function" then
            SC.Performance.record("navigation", utility.idOf(actor),
                utility.nowMs() - searchStarted, usedNodes or 0, false)
        end
        state.pathReason = reason
        state.expandedNodes = expanded
        if searchStatus == "pending" then
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

        state.pathSearch = nil
        state.path = path
        state.pathGoalSquare = path and planningGoal or nil
        state.pathStealthAvoidance = requestIntent.stealthAvoidance
        state.stealthRouteExposure = path and routeDanger(path, requestIntent.snapshot, pathOptions) or nil
        state.nextStealthRepathAt = requestIntent.stealthAvoidance
            and now + (utility.config("navigationStealthRepathMs") or 1800) or nil
        state.pathEmergencyVegetation = requestIntent.urgent == true and pathHasBush(path)
        state.pathIndex = path and 2 or 1
        state.routeCandidateCount = routeReport and routeReport.candidateCount or (path and 1 or 0)
        state.routeSelectedIndex = routeReport and routeReport.selectedOriginalIndex or 1
        state.routeSelectedScore = routeReport and routeReport.selectedScore or nil
        state.routeEvaluations = routeReport and routeReport.routes or nil
        state.nextRepathAt = now + (utility.config("navigationRepathMs") or 900)
    end

    local nextSquare, afterSquare
    if state.path then
        while state.pathIndex <= #state.path and sameSquare(sourceSquare, state.path[state.pathIndex]) do
            state.pathIndex = state.pathIndex + 1
        end
        nextSquare = state.path[state.pathIndex]
        afterSquare = state.path[state.pathIndex + 1]
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
        -- Native bridge pathing remains the bounded-search fallback for distant
        -- goals and complex stair geometry; destination validity is still owned here.
        requestIntent.action = requestIntent.action or "path"
        requestIntent.targetSquare = goalSquare
        requestIntent.enginePath = true
        requestIntent.pathSearchReason = state.pathReason
        requestIntent.nextSquare = goalSquare
        state.lastAttemptFrom, state.lastAttemptTo = sourceSquare, goalSquare
        local moved, movementReason = utility.move(actor, requestIntent.mode, requestIntent)
        state.lastMovementReason = movementReason
        if not moved then
            rememberFailure(actor, state, sourceSquare, goalSquare,
                movementReason or "engine_path_rejected", now, "engine_replan")
            return false, "engine_path_rejected"
        end
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
            goalSquare, now, "engine_goal", false, isMovingTargetIntent(requestIntent))
        return true, "engine_path"
    end

    local barrier, kind = barrierBetween(sourceSquare, nextSquare)
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
    configureTacticalRetreat(actor, sourceSquare, nextSquare, afterSquare, kind, requestIntent)

    local blocker = not requestIntent.urgent
        and personalSpaceBlocker(actor, nextSquare, requestIntent.snapshot) or nil
    local blockerType = blocker and (utility.isCompanion(blocker)
        and "companion_crowd" or "player_crowd") or nil
    if not blocker then blocker, blockerType = utility.movingBlocker(nextSquare, actor) end
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
            blacklistEdge(state, sourceSquare, nextSquare, blockerType, blocker, now, true)
            recordBlocker(actor, state, blockerType, blocker, nextSquare, nil,
                "lateral_yield", now)
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
    if kind == "open" and (squareNearTree(sourceSquare) or squareNearTree(nextSquare)) then
        -- Let Build 42's path behavior steer the collision capsule through the
        -- remaining clearance instead of manually pushing toward the tile centre.
        requestIntent.direct = false
        requestIntent.enginePath = true
        requestIntent.vegetationClearance = true
    end
    if kind == "door" or kind == "stairs" or kind == "fence" then
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
        rememberFailure(actor, state, sourceSquare, nextSquare,
            movementReason or "movement_rejected", now, "direct_replan")
        return false, "movement_rejected"
    end
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
                and "vegetation_corridor" or "native_edge", false,
            isMovingTargetIntent(requestIntent))
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

-- Return human-usable positions around a world object/square.  The candidates
-- are deliberately independent of reachability; the native nearest-of-many
-- request can reject an enclosed side without forcing Lua to retry that side.
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
        local interactionEdgeClear = square and (not cardinal
            or not utility.edgeBlocked(square, centre))
        if key and not seen[key] and interactionEdgeClear
            and utility.isSquareFree(square)
            and not utility.safehouseBlocker(square, actor) then
            seen[key] = true
            candidates[#candidates + 1] = square
        end
    end
    if #candidates == 0 and utility.isSquareFree(centre)
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
    local service, token = supervisedToken(intent)
    local valid, seen = {}, {}
    for _, candidate in ipairs(type(candidates) == "table" and candidates or {}) do
        local square = utility.squareOf(candidate) or candidate
        local key = square and squareKey(square) or nil
        if key and not seen[key] and utility.isSquareFree(square)
            and not utility.safehouseBlocker(square, actor) then
            seen[key] = true
            valid[#valid + 1] = square
        end
    end
    if #valid == 0 then return false, "no_interaction_targets" end
    local arrival = tonumber(intent.arrivalDistance) or 0.85
    for _, square in ipairs(valid) do
        if utility.distance(actor, square) <= arrival or sameSquare(utility.squareOf(actor), square) then
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
    state.actionTokenSerial = currentTokenSerial
    state.routeTargetSignature = routeTargetSignature(valid[1], intent)
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

    if now >= (state.nativeMultiUnavailableUntil or 0) and SC.NativeActions
        and type(SC.NativeActions.pathToNearest) == "function" then
        local started, reason = SC.NativeActions.pathToNearest(actor, valid, movementMode or "walk")
        if started then
            state.goalSquare, state.goalAction = valid[1], intent.action
            state.lastAttemptFrom, state.lastAttemptTo = utility.squareOf(actor), valid[1]
            beginNativeLease(state, valid, state.lastAttemptFrom, valid[1],
                valid[1], now, "nearest_interaction", true)
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
        local ok, status = beginInteraction(actor, state, object, action, now, options, false)
        if not ok then return false, status end
        return completeDoorInteraction(actor, state, object, action, utility.squareOf(actor), objectSquare, now)
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
    if not state then return false end
    for _, entry in ipairs(state.openedDoors or {}) do release(entry.object, actor) end
    if state.pendingInteraction then release(state.pendingInteraction.object, actor) end
    releaseStep(state, actor)
    releaseChoke(state, actor)
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
    report.stealthExposure = path and routeDanger(path, snapshot, pathOptions) or nil
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
        reservations = setmetatable({}, { __mode = "k" })
        curtainTimes = setmetatable({}, { __mode = "k" })
        chokeReservations = {}
        chokeWaiters = setmetatable({}, { __mode = "k" })
        trafficSequence = 0
        nextChokeSweepAt = 0
        stepReservations = {}
        nextStepSweepAt = 0
    end
end

return Navigation
