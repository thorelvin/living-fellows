-- SPDX-License-Identifier: MIT
-- Shared native mattress segments and safe entry geometry.
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.BedGeometry = SC.BedGeometry or {}
local Geometry = SC.BedGeometry
local function U() return SC.GameplayUtil end

function Geometry.entry(bed, actor)
    if not bed then return nil, nil, "bed_missing" end
    local function gridNumber(value)
        if type(value) == "number" then return value end
        return value ~= nil and tonumber(tostring(value)) or nil
    end
    local function cardinal(value)
        local text = value ~= nil and tostring(value) or nil
        return (text == "N" or text == "S" or text == "W"
            or text == "E") and text or nil
    end
    -- SeatingManager is a Java class in game, not necessarily a Lua table.
    local managerOk, manager = pcall(function()
        return SeatingManager.getInstance()
    end)
    if not managerOk or not manager then
        return nil, nil, "seating_manager_unavailable"
    end
    local sprite = select(1, U().call(bed, "getSprite"))
    local grid = sprite and select(1, U().call(sprite, "getSpriteGrid"))
    local square = U().squareOf(bed)
    if not grid or not square then
        return nil, nil, "bed_sprite_grid_unavailable"
    end
    local facing = cardinal(select(1,
        U().call(manager, "getFacingDirection", bed)))
    if not facing then return nil, nil, "bed_facing_unavailable" end
    local gx = gridNumber(select(1, U().call(grid,
        "getSpriteGridPosX", sprite)))
    local gy = gridNumber(select(1, U().call(grid,
        "getSpriteGridPosY", sprite)))
    if gx == nil or gy == nil then
        return nil, nil, "bed_grid_position_unavailable"
    end
    local dx, dy = 0, 0
    if facing == "N" and gy == 0 then dy = 1
    elseif facing == "S" and gy == 1 then dy = -1
    elseif facing == "W" and gx == 0 then dx = 1
    elseif facing == "E" and gx == 1 then dx = -1 end
    local x, y, z = U().position(square)
    if x == nil or y == nil then
        return nil, nil, "bed_square_unavailable"
    end
    local function matchingHalf(tile, targetGX, targetGY)
        local objects = tile and select(1, U().call(tile, "getObjects"))
        if not objects or not SC.NativeList then return nil end
        for index = 0, SC.NativeList.size(objects) - 1 do
            local candidate = SC.NativeList.get(objects, index)
            local candidateSprite = select(1,
                U().call(candidate, "getSprite"))
            if candidateSprite
                and select(1, U().call(candidateSprite,
                    "getSpriteGrid")) == grid
                and gridNumber(select(1, U().call(grid,
                    "getSpriteGridPosX", candidateSprite))) == targetGX
                and gridNumber(select(1, U().call(grid,
                    "getSpriteGridPosY", candidateSprite))) == targetGY then
                return candidate
            end
        end
        return nil
    end
    local function clearForActor(tile)
        if not tile then return false end
        local clear, reason = U().isClearActorSpawnSquare(tile)
        if not clear and actor and U().squareOf(actor) == tile
            and (reason == "occupied" or reason == "unsafe_to_spawn")
            and U().squareOccupyingObject(tile) == nil then
            local moving = select(1, U().call(tile, "getMovingObjects"))
            clear = moving and SC.NativeList
                and SC.NativeList.size(moving) == 1
                and SC.NativeList.get(moving, 0) == actor
        end
        return clear == true
    end
    local function tileFacing(object)
        local objectSprite = select(1, U().call(object, "getSprite"))
        local properties = select(1, U().call(object, "getProperties"))
            or select(1, U().call(objectSprite, "getProperties"))
        return cardinal(select(1, U().call(properties, "get", "Facing")))
    end
    -- Four-sprite double beds can report W/E for their pillow-row Seating
    -- Manager segments even though the mattress is laid out north-south.
    -- Their foot-row segments face S and run the correct lengthwise native
    -- clip. Select an accessible side of that foot row; after OnBedStarted,
    -- the bedridden action aligns its settled anchor to the pillow row.
    local originX, originY = x - gx, y - gy
    if gx >= 0 and gx <= 1 and gy >= 0 and gy <= 1
        and tileFacing(bed) == "S" then
        local room = select(1, U().call(square, "getRoom"))
        local headLeft = matchingHalf(U().gridSquare(originX,
            originY, z or 0), 0, 0)
        local headRight = matchingHalf(U().gridSquare(originX + 1,
            originY, z or 0), 1, 0)
        local footLeft = matchingHalf(U().gridSquare(originX,
            originY + 1, z or 0), 0, 1)
        local footRight = matchingHalf(U().gridSquare(originX + 1,
            originY + 1, z or 0), 1, 1)
        if headLeft and headRight and footLeft and footRight
            and tileFacing(headLeft) == "S"
            and tileFacing(headRight) == "S"
            and tileFacing(footLeft) == "S"
            and tileFacing(footRight) == "S" then
            local sides = {
                { footLeft, originX - 0.3, originY + 1.5,
                    originX, "HeadRight" },
                { footRight, originX + 2.3, originY + 1.5,
                    originX + 1, "HeadLeft" },
            }
            for _, side in ipairs(sides) do
                local tile = U().gridSquare(math.floor(side[2]),
                    math.floor(side[3]), z or 0)
                local sideFacing = cardinal(select(1,
                    U().call(manager, "getFacingDirection", side[1])))
                if sideFacing == "S" and tile
                    and select(1, U().call(tile, "getRoom")) == room
                    and clearForActor(tile) then
                    return side[1], { x = side[2], y = side[3],
                        z = z or 0, facing = "S", entryKind = side[5],
                        pillow = { x = side[4], y = originY,
                            z = z or 0 } }, "entry"
                end
            end
            return nil, nil, "bed_entry_blocked"
        end
    end
    if dx ~= 0 or dy ~= 0 then
        local neighbor = U().gridSquare(x + dx, y + dy, z or 0)
        local normalized = matchingHalf(neighbor, gx + dx, gy + dy)
        if not normalized then
            return nil, nil, "bed_other_half_unavailable"
        end
        bed, square = normalized, neighbor
        x, y, z = U().position(square)
        gx, gy = gx + dx, gy + dy
    end
    -- ISGetOnBedAction reads the direction from the normalized object again.
    -- A double bed may report a different direction on its other segment.
    facing = cardinal(select(1,
        U().call(manager, "getFacingDirection", bed)))
    if not facing then return nil, nil, "bed_facing_unavailable" end
    -- A missing half means the sprite grid is damaged or not a two-tile bed.
    -- The native action can otherwise report OnBed while placing the body in
    -- empty floor. This check uses the grid rather than tile Facing because
    -- some valid hospital beds have different directions in those two data.
    local paired = false
    for _, offset in ipairs({ { -1, 0 }, { 1, 0 },
            { 0, -1 }, { 0, 1 } }) do
        if matchingHalf(U().gridSquare(x + offset[1], y + offset[2],
                z or 0), gx + offset[1], gy + offset[2]) then
            paired = true
            break
        end
    end
    if not paired then return nil, nil, "bed_other_half_unavailable" end
    local candidates
    if facing == "N" or facing == "S" then
        local footY = facing == "N" and y - 0.5 or y + 1.5
        candidates = {
            { x - 0.3, y + 0.5,
                facing == "N" and "HeadLeft" or "HeadRight" },
            { x + 1.3, y + 0.5,
                facing == "N" and "HeadRight" or "HeadLeft" },
            { x - 0.3, footY,
                facing == "N" and "FootLeft" or "FootRight" },
            { x + 1.3, footY,
                facing == "N" and "FootRight" or "FootLeft" },
            { x + 0.5, facing == "N" and y - 1.3
                or y + 2.3, "Foot" },
        }
    else
        local footX = facing == "W" and x - 0.5 or x + 1.5
        candidates = {
            { x + 0.5, y - 0.3,
                facing == "W" and "HeadRight" or "HeadLeft" },
            { x + 0.5, y + 1.3,
                facing == "W" and "HeadLeft" or "HeadRight" },
            { footX, y - 0.3,
                facing == "W" and "FootRight" or "FootLeft" },
            { footX, y + 1.3,
                facing == "W" and "FootLeft" or "FootRight" },
            { facing == "W" and x - 1.3 or x + 2.3,
                y + 0.5, "Foot" },
        }
    end
    local room = select(1, U().call(square, "getRoom"))
    local actorX, actorY
    if actor then actorX, actorY = U().position(actor) end
    local best, bestRank, bestDistance
    for index, point in ipairs(candidates) do
        local tile = U().gridSquare(math.floor(point[1]),
            math.floor(point[2]), z or 0)
        if tile and select(1, U().call(tile, "getRoom")) == room then
            if clearForActor(tile) then
                local distance = actorX and actorY
                    and (actorX - point[1]) ^ 2
                        + (actorY - point[2]) ^ 2 or 0
                local rank = index <= 2 and 1 or index <= 4 and 2 or 3
                if not bestRank or rank < bestRank
                    or (rank == bestRank and distance < bestDistance) then
                    best, bestRank, bestDistance = point, rank, distance
                end
            end
        end
    end
    if not best then return nil, nil, "bed_entry_blocked" end
    return bed, { x = best[1], y = best[2], z = z or 0,
        facing = facing, entryKind = best[3] }, "entry"
end

return Geometry
