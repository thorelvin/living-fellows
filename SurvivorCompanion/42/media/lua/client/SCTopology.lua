-- SPDX-License-Identifier: MIT

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
if not SC.GameplayUtil and type(require) == "function" then pcall(require, "SCGameplayUtil") end

SC.Topology = SC.Topology or {}
local Topology = SC.Topology

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

function Topology.objectOpen(object)
    if object == nil then return false end
    local value, ok = U().call(object, "IsOpen")
    if ok then return value == true end
    value, ok = U().call(object, "isOpen")
    return ok and value == true
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

    -- getDoorTo() remains authoritative for an opened gate even when the
    -- collision-only isDoorTo() predicate has already gone false. Checking the
    -- concrete object first prevents an open gate from being mistaken for the
    -- adjacent hoppable fence segment.
    local door, doorOk = U().call(fromSquare, "getDoorTo", toSquare)
    if doorOk and door ~= nil then return door, "door" end
    local doorTo, doorToOk = U().call(fromSquare, "isDoorTo", toSquare)
    if doorToOk and doorTo == true then
        door, doorOk = U().call(owner, "getDoor", north)
        return doorOk and door or nil, "door"
    end
    local windowTo, windowToOk = U().call(fromSquare, "isWindowTo", toSquare)
    if windowToOk and windowTo == true then
        local window, windowOk = U().call(owner, "getWindow", north)
        if windowOk and window ~= nil then return window, "window" end
        window, windowOk = U().call(owner, "getThumpableWindow", north)
        if windowOk and window ~= nil then return window, "window" end
        local frame, frameOk = U().call(owner, "getWindowFrame", north)
        if frameOk and frame ~= nil then return frame, "window_frame" end
        return nil, "window"
    end
    local hoppable, hopOk = U().call(fromSquare, "isHoppableTo", toSquare)
    if hopOk and hoppable == true then
        local fence, fenceOk = U().call(fromSquare, "getHoppableTo", toSquare)
        if not fenceOk or fence == nil then
            fence, fenceOk = U().call(fromSquare, "getWallHoppableTo", toSquare)
        end
        return fenceOk and fence or nil, "fence"
    end
    if U().edgeBlocked(fromSquare, toSquare) then return nil, "blocked" end
    return nil, "open"
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

function Topology.classifyEdge(actor, fromSquare, toSquare, options)
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
        for _, leg in ipairs(legs) do
            local edge = Topology.classifyEdge(actor, leg[1], leg[2], options)
            if edge.traversable ~= true or edge.affordance ~= "open" then
                result.affordance, result.reason = "diagonal", "diagonal_corner"
                return result
            end
        end
        result.traversable = true
        result.affordance = "diagonal_open"
        result.reason = "traversable"
        result.cost = math.sqrt(2)
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
    result.object, result.affordance = object, kind
    if kind == "invalid" or kind == "blocked" or kind == "diagonal" then
        result.reason = kind == "diagonal" and "diagonal_corner" or "blocked_edge"
        return result
    end
    local thumpable, thumpableKind = thumpableBlocker(actor, fromSquare, toSquare)
    if thumpable ~= nil then
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
        if Topology.objectLocked(object) and not Topology.objectOpen(object) then
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
        result.cost, result.requiresNative = 2.5, true
    elseif kind == "stairs" then
        if not (Topology.squareHasStairs(fromSquare)
            or Topology.squareHasStairs(toSquare)) then
            result.reason = "stairs_not_confirmed" return result
        end
        result.cost, result.requiresNative = 3, true
    else
        result.cost = 1
    end
    result.traversable, result.reason = true, "traversable"
    result.static = not result.dynamic
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
function Topology.reachableEscapeSquares(actor, origin, options)
    options = type(options) == "table" and options or {}
    local radius = math.max(1, math.floor(tonumber(options.radius) or 5))
    local nodeBudget = math.max(4, math.floor(tonumber(options.nodeBudget) or 64))
    local exitLimit = math.max(1, math.floor(tonumber(options.exitLimit) or 16))
    local ox, oy, oz = floorPosition(origin)
    if ox == nil then return {}, {}, { processed = 0, signature = "invalid" } end
    local queue = { { square = origin, distance = 0, cost = 0 } }
    local head, processed = 1, 0
    local visited = {}
    visited[U().squareKey(origin) or tostring(origin)] = true
    local reachable, exits = {}, {}
    while head <= #queue and processed < nodeBudget do
        local current = queue[head]
        head = head + 1
        processed = processed + 1
        if current.distance < radius then
            local cx, cy, cz = floorPosition(current.square)
            for _, offset in ipairs(cardinalOffsets) do
                if processed + #queue - head + 1 >= nodeBudget then break end
                local square = U().gridSquare(cx + offset[1], cy + offset[2], cz)
                local key = square and U().squareKey(square) or nil
                if key and not visited[key] then
                    local edge = Topology.classifyEdge(actor, current.square, square, options)
                    if edge.traversable == true then
                        -- A wall can reject one directed approach to a square
                        -- which remains reachable around the other side. Mark a
                        -- node visited only after an admissible edge reaches it.
                        visited[key] = true
                        local node = {
                            square = square,
                            distance = current.distance + 1,
                            traversalCost = (tonumber(current.traversalCost)
                                or tonumber(current.cost) or 0)
                                + (tonumber(edge.cost) or 1),
                            requiresNative = edge.requiresNative == true,
                            via = edge,
                        }
                        queue[#queue + 1] = node
                        reachable[#reachable + 1] = node
                        if edge.affordance ~= "open" and #exits < exitLimit then
                            exits[#exits + 1] = {
                                kind = edge.affordance, square = square,
                                fromSquare = current.square, object = edge.object,
                                distance = node.distance, requiresNative = edge.requiresNative,
                            }
                        end
                    end
                end
            end
        end
    end
    return reachable, exits, {
        processed = processed,
        signature = Topology.localSignature(actor, origin),
        originKey = U().squareKey(origin),
    }
end

return Topology
