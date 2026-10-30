-- SPDX-License-Identifier: MIT
-- Shared native mattress segments and safe entry geometry.
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.BedGeometry = SC.BedGeometry or {}
local Geometry = SC.BedGeometry
local function U() return SC.GameplayUtil end

local function gridNumber(value)
    if type(value) == "number" then return value end
    return value ~= nil and tonumber(tostring(value)) or nil
end

-- Sleep preference is independent of ordinary seating: a couch remains a
-- reading seat until the sleep selector deliberately requests it as backup.
function Geometry.sleepPriority(object)
    local sprite = select(1, U().call(object, "getSprite"))
    local props = select(1, U().call(object, "getProperties"))
        or select(1, U().call(sprite, "getProperties"))
    local bedType = select(1, U().call(props, "get", "BedType"))
    if bedType == nil then return nil end
    local text = string.lower(tostring(select(1, U().call(props, "get", "GroupName")) or "")
        .. " " .. tostring(select(1, U().call(props, "get", "CustomName")) or "")
        .. " " .. tostring(select(1, U().call(object, "getName")) or ""))
    if text:find("sleeping bag", 1, true) then return 2 end
    if text:find("couch", 1, true) or text:find("sofa", 1, true) then
        local ok, manager = pcall(function() return SeatingManager.getInstance() end)
        local count = ok and select(1, U().call(manager, "getTilePositionCount", object)) or nil
        if (tonumber(count) or 0) > 0 then
            return 3
        end
        return nil
    end
    if text:find("bed", 1, true) or text:find("bunk", 1, true)
        or text:find("mattress", 1, true) or text:find("cot", 1, true)
        or text:find("stretcher", 1, true) then return 1 end
    return nil
end

-- A sprite grid belongs to the furniture type, not to one placed bed, so two
-- identical beds side by side share it. Position within the grid tells them apart.
local function segmentAt(tile, grid, targetGX, targetGY)
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

-- Every tile of the one bed `bed` belongs to. Entry maps them all onto a single
-- mattress, so a claim on any one tile has to count for the whole bed.
function Geometry.segments(bed)
    local sprite = bed and select(1, U().call(bed, "getSprite"))
    local grid = sprite and select(1, U().call(sprite, "getSpriteGrid"))
    local square = bed and U().squareOf(bed)
    local result = {}
    if grid and square then
        local gx = gridNumber(select(1, U().call(grid, "getSpriteGridPosX", sprite)))
        local gy = gridNumber(select(1, U().call(grid, "getSpriteGridPosY", sprite)))
        local x, y, z = U().position(square)
        if gx ~= nil and gy ~= nil and x ~= nil and y ~= nil then
            local width = gridNumber(select(1, U().call(grid, "getWidth"))) or 2
            local height = gridNumber(select(1, U().call(grid, "getHeight"))) or 2
            for targetGY = 0, math.min(height, 4) - 1 do
                for targetGX = 0, math.min(width, 4) - 1 do
                    local segment = segmentAt(U().gridSquare(x - gx + targetGX,
                        y - gy + targetGY, z or 0), grid, targetGX, targetGY)
                    if segment then result[#result + 1] = segment end
                end
            end
        end
    end
    if #result == 0 and bed then result[1] = bed end
    return result
end

-- Someone other than `actor` lying on any tile of this bed. Native
-- isFurnitureOccupied reads only its own tile and only counts an Idle sitting
-- pose, so it cannot answer this for a body lying on the other half.
function Geometry.occupant(bed, actor)
    local couch = Geometry.sleepPriority(bed) == 3
    for _, segment in ipairs(Geometry.segments(bed)) do
        local moving = select(1, U().call(U().squareOf(segment), "getMovingObjects"))
        if moving and SC.NativeList then
            for index = 0, SC.NativeList.size(moving) - 1 do
                local body = SC.NativeList.get(moving, index)
                if body ~= actor and (select(1, U().call(body, "isOnBed")) == true
                    or couch and select(1, U().call(body, "isSittingOnFurniture")) == true) then
                    return body
                end
            end
        end
    end
    return nil
end

function Geometry.entry(bed, actor)
    if not bed then return nil, nil, "bed_missing" end
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
    local function tileFacing(object)
        local objectSprite = select(1, U().call(object, "getSprite"))
        local properties = select(1, U().call(object, "getProperties"))
            or select(1, U().call(objectSprite, "getProperties"))
        return cardinal(select(1, U().call(properties, "get", "Facing")))
    end
    local function physicalFacing(object, nativeFacing)
        local width = gridNumber(select(1, U().call(grid, "getWidth")))
        local height = gridNumber(select(1, U().call(grid, "getHeight")))
        local actual = tileFacing(object)
        if Geometry.sleepPriority(object) == 2 then
            -- Camping sprites carry chair-style facing for a flat bag. Its
            -- two physical tiles establish the mattress axis instead.
            if width == 2 and height == 1 and (nativeFacing == "N" or nativeFacing == "S") then
                return nativeFacing == "N" and "E" or "W", true
            end
            if width == 1 and height == 2 and (nativeFacing == "W" or nativeFacing == "E") then
                return nativeFacing == "W" and "S" or "N", true
            end
        end
        -- Several stock hospital beds advertise chair-facing metadata across
        -- their mattress. Trust the bed's own Facing only when its complete
        -- two-tile grid proves that orientation. Never guess missing halves.
        if width == 1 and height == 2 and (nativeFacing == "E" or nativeFacing == "W")
            and (actual == "N" or actual == "S") then return actual, true end
        if width == 2 and height == 1 and (nativeFacing == "N" or nativeFacing == "S")
            and (actual == "E" or actual == "W") then return actual, true end
        return nativeFacing, false
    end
    local correctedFacing
    facing, correctedFacing = physicalFacing(bed, facing)
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
        return segmentAt(tile, grid, targetGX, targetGY)
    end
    local function clearForActor(tile)
        if not tile then return false end
        local clear, reason = U().isClearActorSpawnSquare(tile)
        if not clear and reason == "unsafe_to_spawn"
            and U().squareOccupyingObject(tile) == nil then
            -- Native spawn safety requires more than seven connected tiles.
            -- A companion walking beside a bed needs only this loaded, solid,
            -- free floor: cramped bedrooms are valid entries, not spawn sites.
            local moving = select(1, U().call(tile, "getMovingObjects"))
            if moving and SC.NativeList then
                clear = true
                for index = 0, SC.NativeList.size(moving) - 1 do
                    if SC.NativeList.get(moving,index) ~= actor then clear=false break end
                end
            end
        end
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
                            z = z or 0 },
                        otherPillow = { x = side[4] == originX and originX+1 or originX,
                            y = originY, z = z or 0 } }, "entry"
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
    facing, correctedFacing = physicalFacing(bed, facing)
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
    local headX, headY = x, y
    if facing == "N" then headY = headY + 1
    elseif facing == "S" then headY = headY - 1
    elseif facing == "W" then headX = headX + 1
    else headX = headX - 1 end
    local beyondHead = U().gridSquare(headX, headY, z or 0)
    local headFloor, headFloorChecked = U().call(beyondHead, "TreatAsSolidFloor")
    -- Head-side OnBed clips can step back past the pillow. At an upstairs
    -- exterior wall that step can leave the floor before sleep even starts.
    -- Enter from a clear foot side when the head is against a hard boundary.
    local preferFoot = beyondHead == nil
        or select(1, U().call(beyondHead, "getRoom")) ~= room
        or headFloorChecked and headFloor ~= true
        or select(1, U().call(beyondHead, "isSolid")) == true
        or select(1, U().call(beyondHead, "isSolidTrans")) == true
    local actorX, actorY
    if actor then actorX, actorY = U().position(actor) end
    local best, bestRank, bestDistance
    for index, point in ipairs(candidates) do
        local tile = U().gridSquare(math.floor(point[1]),
            math.floor(point[2]), z or 0)
        if tile and select(1, U().call(tile, "getRoom")) == room then
            if clearForActor(tile) and not (preferFoot and index <= 2) then
                local distance = actorX and actorY
                    and (actorX - point[1]) ^ 2
                        + (actorY - point[2]) ^ 2 or 0
                local rank = index == 5 and 3
                    or (preferFoot and index >= 3 or not preferFoot and index <= 2) and 1 or 2
                if not bestRank or rank < bestRank
                    or (rank == bestRank and distance < bestDistance) then
                    best, bestRank, bestDistance = point, rank, distance
                end
            end
        end
    end
    if not best then return nil, nil, "bed_entry_blocked" end
    return bed, { x = best[1], y = best[2], z = z or 0,
        facing = facing, entryKind = best[3], correctedFacing = correctedFacing }, "entry"
end

-- Configure only this owned action. OnBed blocks turning as soon as it enters,
-- so setting a future facing target can freeze the previous approach angle.
-- Set both native animation and forward direction before requesting that state.
-- Stock metadata remains untouched; the mattress and native clips still own
-- entry position, root movement, sleep and getting up.
function Geometry.configureEntryAction(action, entry)
    if not action or not entry then return end
    local vectors = { N = { 0, -1 }, S = { 0, 1 }, E = { 1, 0 }, W = { -1, 0 } }
    local direction = vectors[entry.facing]
    if not direction then return end
    if entry.correctedFacing == true then
        action.setBeforeSitDirection = function(self)
            local x, y = U().position(self.character)
            local bx, by = U().position(self.bed)
            if x == nil or bx == nil then return end
            U().call(self.character, "setVariable", "OnBedDirection", entry.entryKind)
            local dx, dy = direction[1], direction[2]
            if entry.entryKind ~= "Foot" then
                if direction[1] == 0 then dx, dy = x < bx + 0.5 and 1 or -1, 0
                else dx, dy = 0, y < by + 0.5 and 1 or -1 end
            end
            U().call(self.character, "faceLocationF", x + dx * 2, y + dy * 2)
        end
    end
    action.setWhileSittingDirection = function(self)
        local _, set = U().call(self.character, "setTargetAndCurrentDirection",
            direction[1], direction[2])
        if not set then
            local x, y = U().position(self.character)
            if x == nil then return end
            U().call(self.character, "faceLocationF", x + direction[1] * 2,
                y + direction[2] * 2)
        end
    end
    local originalStart = action.start
    if type(originalStart) == "function" then
        action.start = function(self)
            self:setWhileSittingDirection()
            return originalStart(self)
        end
    end
end

return Geometry
