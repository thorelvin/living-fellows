-- SPDX-License-Identifier: MIT

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
if not SC.GameplayUtil and type(require) == "function" then pcall(require, "SCGameplayUtil") end
if not SC.Call and type(require) == "function" then pcall(require, "SCCall") end

SC.Topology = SC.Topology or {}
local Topology = SC.Topology
local readBatch = nil

-- A batch is a synchronous, read-only graph slice, never a saved path or a TTL
-- cache. The world is read again after returning/yielding, so a door toggle,
-- vehicle, construction change, or actor permission cannot survive into a later
-- movement decision as cached passability. Callers must not mutate the world
-- inside the callback; traversal execution always runs outside these batches.
function Topology.withReadBatch(callback, ...)
    if readBatch then return callback(...) end
    local batch = { edges = {}, hazards = {}, count = 0, hits = 0 }
    readBatch = batch
    local results = SC.Call.pack(pcall(callback, ...))
    readBatch = nil
    Topology.lastBatch = { classifications = batch.count, hits = batch.hits }
    if not results[1] then error(results[2], 0) end
    return SC.Call.unpack(results, 2, results.n)
end

-- Build 42.20.4 exposes many sprites, but they reduce to this finite set of
-- pathing conditions at the player-collision boundary.  Keeping the catalogue
-- next to the classifier makes additions auditable instead of accumulating as
-- unrelated stuck-recovery exceptions.  "native" means that Lua may choose the
-- edge, while the stock player/path state owns its animation and collision.
Topology.OBSTACLE_CATALOG = {
    { id = "unloaded_square", passage = "wait_for_chunk" },
    { id = "missing_floor", passage = "blocked" },
    { id = "solid_square", passage = "blocked" },
    { id = "solid_transparent", passage = "blocked" },
    { id = "cardinal_wall", passage = "blocked" },
    { id = "diagonal_corner", passage = "cardinal_detour" },
    { id = "open_door_or_gate", passage = "native" },
    { id = "closed_unlocked_door_or_gate", passage = "open_then_native" },
    { id = "key_locked_door_or_gate", passage = "unlock_then_native" },
    { id = "other_locked_door_or_gate", passage = "detour" },
    { id = "barricaded_door_or_gate", passage = "detour" },
    { id = "obstructed_door_or_gate", passage = "detour" },
    { id = "open_window", passage = "native_climb" },
    { id = "closed_unlocked_window", passage = "open_then_native_climb" },
    { id = "locked_window", passage = "smash_clear_climb" },
    { id = "smashed_window_with_glass", passage = "clear_then_native_climb" },
    { id = "smashed_window_clear", passage = "native_climb" },
    { id = "barricaded_window", passage = "detour" },
    { id = "invincible_window", passage = "detour" },
    { id = "empty_window_frame", passage = "native_climb" },
    { id = "low_fence", passage = "native_vault" },
    { id = "tall_hoppable_wall", passage = "native_climb_if_capable" },
    { id = "non_hoppable_wall_or_fence", passage = "detour" },
    { id = "stairs", passage = "native" },
    { id = "sloped_surface", passage = "native" },
    { id = "sheet_rope", passage = "native_climb" },
    { id = "water", passage = "blocked" },
    { id = "fire", passage = "avoid_or_emergency" },
    { id = "broken_glass", passage = "costly" },
    { id = "explosive_trap", passage = "avoid_or_emergency" },
    { id = "tree", passage = "detour" },
    { id = "bush", passage = "costly" },
    { id = "vehicle", passage = "detour_polygon" },
    { id = "full_square_object", passage = "detour" },
    { id = "thumpable_construction", passage = "detour" },
    { id = "pushable_object", passage = "detour" },
    { id = "living_actor", passage = "yield_or_detour" },
    { id = "safehouse_boundary", passage = "policy_block" },
}

function Topology.obstacleTypeCount()
    return #Topology.OBSTACLE_CATALOG
end

local function U()
    return SC.GameplayUtil
end

local function floorPosition(value)
    local x, y, z = U().position(value)
    if x == nil then return nil end
    return math.floor(x), math.floor(y), math.floor(z or 0)
end

local function callBoolean(value, methodName, ...)
    local result, ok = U().call(value, methodName, ...)
    return ok and result == true
end

local function enumValue(enumName, key)
    local root = type(_G) == "table" and rawget(_G, enumName) or nil
    if root == nil then return nil end
    local ok, value = pcall(function() return root[key] end)
    return ok and value or nil
end

local function squareHasFlag(square, flagName)
    if square == nil then return false end
    local flag = enumValue("IsoFlagType", flagName)
    if flag ~= nil then
        local value, ok = U().call(square, "has", flag)
        if ok then return value == true end
        local properties, propertiesOk = U().call(square, "getProperties")
        if propertiesOk and properties ~= nil then
            value, ok = U().call(properties, "has", flag)
            if ok then return value == true end
        end
    end
    local value, ok = U().call(square, "has", flagName)
    return ok and value == true
end

local function floorHasFlag(square, flagName)
    if square == nil then return false end
    local floor, floorOk = U().call(square, "getFloor")
    local flag = enumValue("IsoFlagType", flagName)
    if floorOk and floor ~= nil and flag ~= nil then
        local value, ok = U().call(floor, "hasProperty", flag)
        if ok then return value == true end
        local properties, propertiesOk = U().call(floor, "getProperties")
        if propertiesOk and properties ~= nil then
            value, ok = U().call(properties, "has", flag)
            if ok then return value == true end
        end
    end
    -- Headless fixtures and older/custom squares may expose only the aggregate
    -- flag. Production prefers the floor object above so a bridge built over
    -- water is not confused with the water tile it covers.
    return not floorOk and squareHasFlag(square, flagName)
end

function Topology.squareIsWater(square)
    return floorHasFlag(square, "water")
end

function Topology.squareHasSlope(square)
    return callBoolean(square, "hasSlopedSurface")
end

function Topology.squareHasTree(square)
    if square == nil then return false end
    local tree, observed = U().call(square, "HasTree")
    if observed then return tree == true end
    tree, observed = U().call(square, "getTree")
    if observed and tree ~= nil then return true end
    local found = false
    U().squareObjects(square, function(object)
        if U().instanceOf(object, "IsoTree") then found = true return false end
        local name, nameOk = U().call(object, "getObjectName")
        if nameOk and string.lower(tostring(name or "")) == "tree" then
            found = true
            return false
        end
    end, 32)
    return found
end

function Topology.squareHasSheetRope(square)
    if square == nil then return false end
    local rope, ok = U().call(square, "getSheetRope")
    if ok then return rope ~= nil end
    if type(square) == "table" then return square.haveSheetRope == true end
    return false
end

function Topology.squareHazards(square)
    if readBatch and readBatch.hazards[square] then return readBatch.hazards[square] end
    local hazards = {}
    if square == nil then return hazards end
    if squareHasFlag(square, "burning") then hazards.fire = true end
    local fire, fireOk = U().call(square, "getFire")
    if fireOk and fire ~= nil then hazards.fire = true end
    local glass, glassOk = U().call(square, "getBrokenGlass")
    if glassOk and glass ~= nil then hazards.brokenGlass = true end
    U().squareObjects(square, function(object)
        if U().instanceOf(object, "IsoFire") then hazards.fire = true
        elseif U().instanceOf(object, "IsoBrokenGlass") then hazards.brokenGlass = true
        elseif U().instanceOf(object, "IsoTrap") then hazards.explosiveTrap = true end
    end, 64)
    if readBatch then readBatch.hazards[square] = hazards end
    return hazards
end

function Topology.objectOpen(object)
    if object == nil then return false end
    if callBoolean(object, "isDestroyed") then return true end
    local value, ok = U().call(object, "IsOpen")
    if ok then return value == true end
    value, ok = U().call(object, "isOpen")
    return ok and value == true
end

function Topology.actorCanUnlock(actor, object)
    if actor == nil or object == nil then return false end
    if callBoolean(object, "isPermaLocked") or callBoolean(object, "isLockedByCode") then
        return false
    end
    local code, codeOk = U().call(object, "getLockedByCode")
    if codeOk and type(code) == "number" and code > 0 then return false end
    local keyId, keyOk = U().call(object, "getKeyId")
    if not keyOk or type(keyId) ~= "number" or keyId < 0 then return false end
    local inventory = U().inventory(actor)
    local key, hasKey = U().call(inventory, "haveThisKeyId", keyId)
    return hasKey and key ~= nil and key ~= false
end

function Topology.objectLocked(object)
    if object == nil then return false end
    local value, ok = U().call(object, "isLocked")
    if ok and value == true then return true end
    value, ok = U().call(object, "isPermaLocked")
    if ok and value == true then return true end
    for _, methodName in ipairs({ "isLockedByKey", "isLockedByPadlock", "isLockedByCode" }) do
        value, ok = U().call(object, methodName)
        if ok and value == true then return true end
    end
    value, ok = U().call(object, "getLockedByCode")
    if ok and type(value) == "number" and value > 0 then return true end
    local data = U().modData(object)
    return type(data) == "table" and data.CustomLock == true
end

function Topology.objectBarricaded(object)
    if object == nil then return false end
    local value, ok = U().call(object, "isBarricaded")
    if ok and value == true then return true end
    local barricade, barricadeOk = U().call(object, "getBarricadeForCharacter", nil)
    return barricadeOk and barricade ~= nil
end

function Topology.windowSmashed(object)
    return callBoolean(object, "isSmashed")
end

function Topology.windowGlassRemoved(object)
    return callBoolean(object, "isGlassRemoved")
end

function Topology.windowInvincible(object)
    return callBoolean(object, "isInvincible")
end

local function verifiedClimbability(object, actor)
    if object == nil then return false, false end
    local value, ok = U().call(object, "canClimbThrough", actor)
    if ok then return value == true, true end
    value, ok = U().call(object, "canClimbThrough", nil)
    if ok then return value == true, true end
    return false, false
end

function Topology.canClimbThrough(object, actor)
    return verifiedClimbability(object, actor)
end

function Topology.objectStateSignature(object)
    if object == nil then return "none" end
    return table.concat({
        Topology.objectOpen(object) and "open" or "closed",
        Topology.objectLocked(object) and "locked" or "unlocked",
        Topology.objectBarricaded(object) and "barricaded" or "clear",
        Topology.windowSmashed(object) and "smashed" or "intact",
        Topology.windowGlassRemoved(object) and "glass-removed" or "glass-present",
    }, ":")
end

function Topology.squareHasStairs(square)
    if square == nil then return false end
    local value, ok = U().call(square, "HasStairs")
    if ok then return value == true end
    value, ok = U().call(square, "hasStairs")
    if ok then return value == true end
    local found = false
    U().squareObjects(square, function(object)
        local stairs, stairsOk = U().call(object, "isStairsObject")
        if stairsOk and stairs == true then found = true return false end
        local objectType, typeOk = U().call(object, "getType")
        if typeOk and string.find(string.lower(tostring(objectType or "")),
            "stairs", 1, true) then found = true return false end
    end, 24)
    return found
end

function Topology.squareHasLevelTransition(square)
    return Topology.squareHasStairs(square) or Topology.squareHasSlope(square)
        or Topology.squareHasSheetRope(square)
end

local function cardinalDirection(fromSquare, toSquare)
    local fx, fy = floorPosition(fromSquare)
    local tx, ty = floorPosition(toSquare)
    if fx == nil or tx == nil then return nil end
    local key
    if tx > fx and ty == fy then key = "E"
    elseif tx < fx and ty == fy then key = "W"
    elseif ty > fy and tx == fx then key = "S"
    elseif ty < fy and tx == fx then key = "N" end
    return key and enumValue("IsoDirections", key) or nil
end

local function edgeOwner(fromSquare, toSquare)
    local fx, fy = floorPosition(fromSquare)
    local tx, ty = floorPosition(toSquare)
    if fx == nil or tx == nil then return nil end
    local owner, north = fromSquare, nil
    if ty < fy then north = true
    elseif ty > fy then owner, north = toSquare, true
    elseif tx < fx then north = false
    elseif tx > fx then owner, north = toSquare, false
    else return nil end
    return owner, north
end

-- Return the concrete boundary object and a topology kind. Only cardinal edges
-- are legal: allowing diagonal adjacency here lets escape/path probes cut across
-- the solid corner made by two walls or a wall and a locked door.
function Topology.barrierBetween(fromSquare, toSquare)
    if fromSquare == nil or toSquare == nil then return nil, "invalid" end
    local fx, fy, fz = floorPosition(fromSquare)
    local tx, ty, tz = floorPosition(toSquare)
    if fx == nil or tx == nil then return nil, "invalid" end
    local dx, dy = math.abs(tx - fx), math.abs(ty - fy)
    if fz ~= tz then
        if dx + dy > 1 then return nil, "invalid" end
        return nil, "stairs"
    end
    if dx + dy == 0 then return nil, "same" end
    if dx + dy ~= 1 then return nil, "diagonal" end
    local owner, north = edgeOwner(fromSquare, toSquare)
    if owner == nil then return nil, "invalid" end

    -- Concrete edge getters remain authoritative for opened/modded objects even
    -- when their collision-only predicates have already gone false.
    local window, windowOk = U().call(fromSquare, "getWindowTo", toSquare)
    if windowOk and window ~= nil then return window, "window" end
    window, windowOk = U().call(fromSquare, "getWindowThumpableTo", toSquare)
    if windowOk and window ~= nil then return window, "window" end
    local frame, frameOk = U().call(fromSquare, "getWindowFrameTo", toSquare)
    if frameOk and frame ~= nil then return frame, "window_frame" end

    -- getDoorTo() remains authoritative for an opened gate even when the
    -- collision-only isDoorTo() predicate has already gone false. Checking the
    -- concrete object first prevents an open gate from being mistaken for the
    -- adjacent hoppable fence segment.
    local door, doorOk = U().call(fromSquare, "getDoorTo", toSquare)
    if doorOk and door ~= nil then return door, "door" end
    -- Multi-tile garage doors and some modded gates are published on their
    -- owning edge without participating in getDoorTo()/isDoorTo(). These are
    -- still ordinary doors for pathing and use the same open/lock policy.
    local garage, garageOk = U().call(owner, "getGarageDoor", north)
    if garageOk and garage ~= nil then return garage, "door" end
    local contextual, contextualOk = U().call(owner, "getDoorOrWindow", north)
    if contextualOk and contextual ~= nil then
        local isWindow, windowObserved = U().call(contextual, "isWindow")
        if U().instanceOf(contextual, "IsoWindow")
            or windowObserved and isWindow == true then
            return contextual, "window"
        end
        local isDoor, doorObserved = U().call(contextual, "isDoor")
        if U().instanceOf(contextual, "IsoDoor")
            or doorObserved and isDoor == true then
            return contextual, "door"
        end
    end
    local doorTo, doorToOk = U().call(fromSquare, "isDoorTo", toSquare)
    if doorToOk and doorTo == true then
        door, doorOk = U().call(owner, "getDoor", north)
        return doorOk and door or nil, "door"
    end
    local windowTo, windowToOk = U().call(fromSquare, "isWindowTo", toSquare)
    if windowToOk and windowTo == true then
        window, windowOk = U().call(owner, "getWindow", north)
        if windowOk and window ~= nil then return window, "window" end
        window, windowOk = U().call(owner, "getThumpableWindow", north)
        if windowOk and window ~= nil then return window, "window" end
        frame, frameOk = U().call(owner, "getWindowFrame", north)
        if frameOk and frame ~= nil then return frame, "window_frame" end
        return nil, "window"
    end
    -- Player context handling checks concrete hoppable objects as well as the
    -- low-fence predicate. Tall sports/football fences may be exposed only by
    -- getWallHoppableTo(): requiring isHoppableTo() first makes the planner
    -- reject an edge that the player's E action can climb.
    local fence, fenceOk = U().call(fromSquare, "getHoppableThumpableTo", toSquare)
    if not fenceOk or fence == nil then
        fence, fenceOk = U().call(fromSquare, "getHoppableTo", toSquare)
    end
    if not fenceOk or fence == nil then
        fence, fenceOk = U().call(fromSquare, "getWallHoppableTo", toSquare)
    end
    if fenceOk and fence ~= nil then return fence, "fence" end
    local hoppable, hopOk = U().call(fromSquare, "isHoppableTo", toSquare)
    if hopOk and hoppable == true then return nil, "fence" end
    -- Do not invoke the broader player wall probe for ordinary open floor.
    -- This function runs for every cardinal A-star neighbor; the native probe
    -- is both substantially more expensive than isBlockedTo() and meaningful
    -- only when the normal movement edge is actually blocked.
    if not U().edgeBlocked(fromSquare, toSquare) then return nil, "open" end
    -- Build 42 has a square-local wall affordance which is safe to query while
    -- A-star evaluates a remote edge. Unlike actor:canClimbOverWall(), it does
    -- not accidentally test whatever happens to be in front of the companion.
    local direction = cardinalDirection(fromSquare, toSquare)
    local wallHoppable, wallHoppableOk = U().call(
        fromSquare, "isPlayerAbleToHopWallTo", direction, toSquare)
    if wallHoppableOk and wallHoppable == true then return nil, "fence" end
    return nil, "blocked"
end

local function thumpableBlocker(actor, fromSquare, toSquare)
    local found, kind
    local function inspect(object, ownerSquare)
        local moved, movedOk = U().call(object, "isMovedThumpable")
        if ownerSquare == toSquare and movedOk and moved == true then
            found, kind = object, "moved_object" return false
        end
        local blockAll, blockOk = U().call(object, "isBlockAllTheSquare")
        if ownerSquare == toSquare and blockOk and blockAll == true then
            found, kind = object, "full_square_thumpable" return false
        end
        if not U().instanceOf(object, "IsoThumpable") then return end
        local door, doorOk = U().call(object, "isDoor")
        local window, windowOk = U().call(object, "isWindow")
        local pass, passOk = U().call(object, "isCanPassThrough")
        if (not doorOk or door ~= true) and (not windowOk or window ~= true)
            and (not passOk or pass ~= true) then
            local collides, collisionOk = U().call(
                object, "TestCollide", actor, fromSquare, toSquare)
            if collisionOk and collides == true then
                found, kind = object, "wall_thumpable" return false
            end
        end
    end
    U().squareSpecialObjects(fromSquare, function(object)
        return inspect(object, fromSquare)
    end, 48)
    if found == nil then
        U().squareSpecialObjects(toSquare, function(object)
            return inspect(object, toSquare)
        end, 48)
    end
    return found, kind
end

local function classifyEdge(actor, fromSquare, toSquare, options)
    options = type(options) == "table" and options or {}
    local result = {
        traversable = false, affordance = "invalid", reason = "invalid_edge",
        object = nil, static = true, dynamic = false,
        cost = math.huge, requiresNative = false,
        fromSquare = fromSquare, toSquare = toSquare,
    }
    if fromSquare == nil or toSquare == nil then return result end
    local fx, fy, fz = floorPosition(fromSquare)
    local tx, ty, tz = floorPosition(toSquare)
    if fx == nil or tx == nil then return result end
    local dx, dy = math.abs(tx - fx), math.abs(ty - fy)
    if fz == tz and dx == 1 and dy == 1 then
        -- Diagonal movement is safe only when the complete two-tile-wide corner
        -- is open. Requiring both possible cardinal decompositions prevents
        -- corner cutting through walls, doors, windows, fences, vehicles or
        -- occupied geometry while allowing a human-looking 45-degree stride in
        -- genuinely open space.
        local horizontal = U().gridSquare(tx, fy, fz)
        local vertical = U().gridSquare(fx, ty, fz)
        if horizontal == nil or vertical == nil then
            result.affordance, result.reason = "diagonal", "diagonal_corner"
            return result
        end
        local legs = {
            { fromSquare, horizontal }, { horizontal, toSquare },
            { fromSquare, vertical }, { vertical, toSquare },
        }
        local diagonalHazardCost = 0
        local diagonalHazards = {}
        for _, leg in ipairs(legs) do
            local edge = Topology.classifyEdge(actor, leg[1], leg[2], options)
            if edge.traversable ~= true or edge.affordance ~= "open" then
                result.affordance, result.reason = "diagonal", "diagonal_corner"
                return result
            end
            diagonalHazardCost = math.max(diagonalHazardCost,
                math.max(0, (tonumber(edge.cost) or 1) - 1))
            for hazard, present in pairs(edge.hazards or {}) do
                if present == true then diagonalHazards[hazard] = true end
            end
        end
        result.traversable = true
        result.affordance = "diagonal_open"
        result.reason = "traversable"
        result.cost = math.sqrt(2) + diagonalHazardCost
        result.hazards = diagonalHazards
        result.static = true
        return result
    end
    if fz == tz and dx + dy ~= 1 then
        result.affordance = dx + dy == 0
            and "same" or "diagonal"
        result.reason = result.affordance == "diagonal"
            and "diagonal_corner" or "same_square"
        return result
    end
    if Topology.squareIsWater(toSquare) then
        result.affordance, result.reason = "water", "water_terrain"
        return result
    end
    -- The stock player pathfinder rejects tree-occupied destinations even
    -- though the broad square-free probe can admit them. Treat the trunk cell
    -- as a detour and retain only the existing clearance cost for neighbours.
    if Topology.squareHasTree(toSquare) then
        result.affordance, result.reason = "tree", "tree_occupied"
        return result
    end
    local hazards = Topology.squareHazards(toSquare)
    result.hazards = hazards
    local hazardCost = 0
    if hazards.fire then
        if options.allowHazards ~= true then
            result.affordance, result.reason = "fire", "fire_hazard"
            return result
        end
        hazardCost = hazardCost
            + (tonumber(U().config("navigationFireEmergencyPenalty")) or 80)
    end
    if hazards.explosiveTrap then
        if options.allowHazards ~= true then
            result.affordance, result.reason = "trap", "explosive_trap_hazard"
            return result
        end
        hazardCost = hazardCost
            + (tonumber(U().config("navigationExplosiveTrapEmergencyPenalty")) or 60)
    end
    if hazards.brokenGlass then
        hazardCost = hazardCost
            + (tonumber(U().config("navigationBrokenGlassPenalty")) or 8)
    end
    local vehicle, vehicleOk = U().call(toSquare, "getVehicleContainer")
    if vehicleOk and vehicle ~= nil then
        result.affordance, result.reason, result.object =
            "vehicle", "vehicle_footprint", vehicle
        return result
    end
    if not U().isSquareFree(toSquare) then
        result.affordance, result.reason = "blocked", "square_blocked"
        return result
    end
    if options.ignoreSafehouse ~= true and U().safehouseBlocker(toSquare, actor) then
        result.affordance, result.reason = "policy", "safehouse_boundary"
        return result
    end

    local object, kind = Topology.barrierBetween(fromSquare, toSquare)
    if kind == "open" and (Topology.squareHasSlope(fromSquare)
        or Topology.squareHasSlope(toSquare)) then kind = "slope" end
    result.object, result.affordance = object, kind
    if kind == "invalid" or kind == "blocked" or kind == "diagonal" then
        result.reason = kind == "diagonal" and "diagonal_corner" or "blocked_edge"
        return result
    end
    local thumpable, thumpableKind = thumpableBlocker(actor, fromSquare, toSquare)
    -- A player-built hoppable IsoThumpable still reports collision. Once the
    -- edge getters have positively identified that exact object as a door,
    -- window or fence, its collision is the traversal affordance—not a second
    -- wall layered over it.
    local recognizedTraversalObject = thumpable ~= nil and object ~= nil
        and thumpable == object and (kind == "door" or kind == "window"
            or kind == "window_frame" or kind == "fence")
    if thumpable ~= nil and not recognizedTraversalObject then
        result.object, result.affordance, result.reason = thumpable,
            thumpableKind or "thumpable", thumpableKind or "thumpable_collision"
        return result
    end

    if kind == "open" then
        local nativeBlocked, nativeOk = U().call(fromSquare, "testPathFindAdjacent", actor,
            tx - fx, ty - fy, tz - fz)
        if nativeOk and nativeBlocked == true then
            result.affordance, result.reason = "blocked", "native_directional_edge"
            return result
        end
    end

    if kind == "door" then
        if object == nil then result.reason = "door_object_missing" return result end
        if Topology.objectBarricaded(object) then
            result.reason = "door_barricaded" return result
        end
        local obstructed, obstructedOk = U().call(object, "isObstructed")
        if obstructedOk and obstructed == true then
            result.reason = "door_obstructed" return result
        end
        if Topology.objectLocked(object) and not Topology.objectOpen(object)
            and not Topology.actorCanUnlock(actor, object) then
            result.reason = "door_locked" return result
        end
        result.cost = Topology.objectOpen(object) and 1 or 2.2
        result.requiresNative = not Topology.objectOpen(object)
    elseif kind == "window" then
        if object == nil then result.reason = "window_object_missing" return result end
        if Topology.objectBarricaded(object) then result.reason = "window_barricaded" return result end
        if Topology.windowInvincible(object) and not Topology.objectOpen(object) then
            result.reason = "window_invincible" return result
        end
        local climbable, verified = verifiedClimbability(object, actor)
        if not verified then result.reason = "window_climbability_unknown" return result end
        if not climbable then result.reason = "window_not_climbable" return result end
        result.cost = Topology.objectOpen(object) and 2.5
            or (Topology.windowSmashed(object) and 4 or 5)
        result.requiresNative = true
    elseif kind == "window_frame" then
        if object == nil then result.reason = "window_frame_blocked" return result end
        local climbable, verified = verifiedClimbability(object, actor)
        if not verified then result.reason = "window_frame_climbability_unknown" return result end
        if not climbable then result.reason = "window_frame_blocked" return result end
        result.cost, result.requiresNative = 2.5, true
    elseif kind == "fence" then
        local tall, tallOk = U().call(object, "isTallHoppable")
        if tallOk and tall == true then
            -- canClimbOverWall(direction) is relative to the actor's current
            -- square. Calling it while A-star evaluates a distant fence tests
            -- an unrelated edge and rejects valid routes. Keep the concrete
            -- tall wall in the route; the adjacent traversal dispatch repeats
            -- the stock player capability check immediately before climbing.
            result.cost = 4.5
        else
            result.cost = 2.5
        end
        result.requiresNative = true
    elseif kind == "stairs" then
        if not (Topology.squareHasStairs(fromSquare)
            or Topology.squareHasStairs(toSquare)) then
            result.reason = "stairs_not_confirmed" return result
        end
        result.cost, result.requiresNative = 3, true
    elseif kind == "slope" then
        result.cost, result.requiresNative = 2, true
    else
        result.cost = 1
    end
    result.cost = result.cost + hazardCost
    result.traversable, result.reason = true, "traversable"
    result.static = not result.dynamic
    return result
end

function Topology.classifyEdge(actor, fromSquare, toSquare, options)
    if not readBatch or fromSquare == nil or toSquare == nil then
        return classifyEdge(actor, fromSquare, toSquare, options)
    end
    if readBatch.count >= 2048 then return classifyEdge(actor, fromSquare, toSquare, options) end
    options = type(options) == "table" and options or {}
    local policy = (options.allowHazards == true and "hazards:" or "safe:")
        .. (options.ignoreSafehouse == true and "public" or "permission")
    local owner = actor or false
    local actors = readBatch.edges
    actors[owner] = actors[owner] or {}
    local origins = actors[owner]
    origins[fromSquare] = origins[fromSquare] or {}
    local destinations = origins[fromSquare]
    destinations[toSquare] = destinations[toSquare] or {}
    local policies = destinations[toSquare]
    if policies[policy] then
        readBatch.hits = readBatch.hits + 1
        return policies[policy]
    end
    local result = classifyEdge(actor, fromSquare, toSquare, options)
    if readBatch.count < 2048 then
        policies[policy] = result
        readBatch.count = readBatch.count + 1
    end
    return result
end

local cardinalOffsets = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

function Topology.localSignature(actor, origin)
    local x, y, z = floorPosition(origin)
    if x == nil then return "invalid" end
    local parts = { U().squareKey(origin) or (tostring(x) .. ":" .. tostring(y) .. ":" .. tostring(z)) }
    for _, offset in ipairs(cardinalOffsets) do
        local square = U().gridSquare(x + offset[1], y + offset[2], z)
        local edge = Topology.classifyEdge(actor, origin, square, {})
        parts[#parts + 1] = tostring(edge.affordance) .. ":" .. tostring(edge.reason)
            .. ":" .. Topology.objectStateSignature(edge.object)
    end
    return table.concat(parts, "|")
end

-- Bounded cardinal flood-fill used by combat escape planning. It returns only
-- squares that can be reached under the same edge policy as Navigation.
function Topology.newEscapeSearch(actor, origin, options)
    options = type(options) == "table" and options or {}
    local ox, oy, oz = floorPosition(origin)
    local job = {
        actor = actor, origin = origin, options = options,
        radius = math.max(1, math.floor(tonumber(options.radius) or 5)),
        nodeBudget = math.max(4, math.floor(tonumber(options.nodeBudget) or 64)),
        exitLimit = math.max(1, math.floor(tonumber(options.exitLimit) or 16)),
        queue = {}, head = 1, processed = 0, edgeChecks = 0,
        visited = {}, reachable = {}, exits = {}, portals = {}, portalSeen = {},
        originKey = U().squareKey(origin),
        complete = ox == nil,
    }
    if ox ~= nil then
        job.queue[1] = { square = origin, distance = 0, cost = 0, nextEdge = 1 }
        job.visited[job.originKey or tostring(origin)] = true
    end
    return job
end

function Topology.escapeSearchValid(job, deadline, clock)
    if type(job) ~= "table" then return false end
    clock = type(clock) == "function" and clock or U().nowMs
    local portals = job.portals or {}
    local index = math.max(1, math.floor(tonumber(job.validationIndex) or 1))
    local used = 0
    while index <= #portals do
        -- Portal verification is part of the same cooperative frame budget as
        -- edge expansion. Preserve its cursor rather than rescanning an
        -- expensive prefix whenever the deadline is reached.
        if deadline and used > 0 and clock() >= deadline then
            job.validationIndex = index
            return true, false, used
        end
        local portal = portals[index]
        local object = Topology.barrierBetween(portal.fromSquare, portal.toSquare)
        if object ~= portal.object
            or Topology.objectStateSignature(object) ~= portal.signature then
            job.validationIndex = 1
            return false, true, used + 1
        end
        index, used = index + 1, used + 1
    end
    job.validationIndex = 1
    return true, true, used
end

local function advanceEscapeSearch(job, edgeQuota, deadline, clock)
    local used = 0
    edgeQuota = math.max(1, math.floor(tonumber(edgeQuota) or 24))
    clock = type(clock) == "function" and clock or U().nowMs
    local valid, validationComplete, validationUsed =
        Topology.escapeSearchValid(job, deadline, clock)
    validationUsed = tonumber(validationUsed) or 0
    if not valid then
        job.complete, job.invalidated = true, true
        return {}, {}, { used = validationUsed, edgeUsed = 0,
            processed = job.processed, complete = true, invalidated = true }
    end
    if validationComplete ~= true or validationUsed >= edgeQuota then
        return job.reachable, job.exits, { used = validationUsed, edgeUsed = 0,
            processed = job.processed, edgeChecks = job.edgeChecks,
            complete = false, validationPending = true, originKey = job.originKey }
    end
    local edgeQuotaRemaining = edgeQuota - validationUsed
    while not job.complete and job.head <= #job.queue and used < edgeQuotaRemaining do
        -- Always establish the four immediate cardinal options on a fresh
        -- emergency. Deeper geometry yields without postponing close defense.
        if deadline and used > 0 and job.edgeChecks >= 4 and clock() >= deadline then break end
        local current = job.queue[job.head]
        job.processed = math.max(job.processed, job.head)
        if current.distance < job.radius and current.nextEdge <= #cardinalOffsets then
            local cx, cy, cz = floorPosition(current.square)
            local offset = cardinalOffsets[current.nextEdge]
            current.nextEdge = current.nextEdge + 1
            used, job.edgeChecks = used + 1, job.edgeChecks + 1
            if cx ~= nil then
                local square = U().gridSquare(cx + offset[1], cy + offset[2], cz)
                local key = square and U().squareKey(square) or nil
                if key and not job.visited[key] then
                    local edge = Topology.classifyEdge(job.actor, current.square, square, job.options)
                    if edge.traversable == true then
                        if edge.object and not job.portalSeen[edge.object] then
                            -- A continuation cannot retain an opening that was
                            -- closed/locked/removed between its bounded slices.
                            -- Limit recurring validation work, not the flood fill.
                            -- Dense door/fence layouts may contain more portals;
                            -- the selected route is always revalidated edge by
                            -- edge before use, so an untracked portal must not
                            -- truncate reachable escape space.
                            if #job.portals < 16 then
                                job.portalSeen[edge.object] = true
                                job.portals[#job.portals + 1] = {
                                    object = edge.object, fromSquare = current.square,
                                    toSquare = square,
                                    signature = Topology.objectStateSignature(edge.object),
                                }
                            else
                                job.portalValidationTruncated = true
                            end
                        end
                        -- A wall can reject one directed approach to a square
                        -- which remains reachable around the other side. Mark a
                        -- node visited only after an admissible edge reaches it.
                        job.visited[key] = true
                        local node = {
                            square = square,
                            x = cx + offset[1], y = cy + offset[2], z = cz,
                            parent = current,
                            fromSquare = current.square,
                            distance = current.distance + 1,
                            traversalCost = (tonumber(current.traversalCost)
                                or tonumber(current.cost) or 0)
                                + (tonumber(edge.cost) or 1),
                            requiresNative = edge.requiresNative == true,
                            via = edge, nextEdge = 1,
                        }
                        job.queue[#job.queue + 1] = node
                        job.reachable[#job.reachable + 1] = node
                        if edge.affordance ~= "open" and #job.exits < job.exitLimit then
                            job.exits[#job.exits + 1] = {
                                kind = edge.affordance, square = square,
                                fromSquare = current.square, object = edge.object,
                                distance = node.distance, requiresNative = edge.requiresNative,
                            }
                        end
                    end
                end
            end
        else
            job.head = job.head + 1
        end
        if #job.queue >= job.nodeBudget then job.complete = true end
    end
    if job.head > #job.queue then job.complete = true end
    return job.reachable, job.exits, {
        processed = job.processed, edgeChecks = job.edgeChecks,
        used = used + validationUsed, edgeUsed = used,
        complete = job.complete, originKey = job.originKey,
        portalValidationTruncated = job.portalValidationTruncated == true,
    }
end

function Topology.resumeEscapeSearch(job, edgeQuota, deadline, clock)
    return Topology.withReadBatch(advanceEscapeSearch, job, edgeQuota, deadline, clock)
end

function Topology.reachableEscapeSquares(actor, origin, options)
    local job = Topology.newEscapeSearch(actor, origin, options)
    local raw, exits, meta = Topology.resumeEscapeSearch(job, job.nodeBudget * 4)
    meta.signature = Topology.localSignature(actor, origin)
    return raw, exits, meta
end

-- A flood-fill continuation is only a planning cache. Before Senses exposes a
-- square as an actionable retreat destination, re-read every edge in that
-- node's parent chain without the batch memo. This catches a car, wall, door or
-- construction inserted after an earlier slice and gives one coherent
-- main-thread validation of the route actually selected for use.
function Topology.validateEscapeNode(actor, node, options)
    if type(node) ~= "table" or node.square == nil then return false, "invalid_node", 0 end
    local chain, cursor, guard = {}, node, 0
    while cursor and cursor.parent do
        guard = guard + 1
        if guard > 16 then return false, "parent_cycle", guard end
        chain[#chain + 1] = cursor
        cursor = cursor.parent
    end
    if #chain == 0 then return false, "no_route", 0 end
    local checked = 0
    for index = #chain, 1, -1 do
        local step = chain[index]
        local fromSquare = step.fromSquare
            or (step.parent and step.parent.square) or nil
        local edge = classifyEdge(actor, fromSquare, step.square, options)
        checked = checked + 1
        if edge.traversable ~= true then
            return false, edge.reason or "blocked", checked
        end
    end
    return true, "traversable", checked
end

return Topology
