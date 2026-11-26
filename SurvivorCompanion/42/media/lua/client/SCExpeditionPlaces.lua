-- SPDX-License-Identifier: MIT
-- Read-only destination candidates for the private expedition prototype.
-- Map-derived locations are labelled as such; room metadata is not sight.

local SC = SurvivorCompanion
SC.ExpeditionPlaces = SC.ExpeditionPlaces or {}
local Places = SC.ExpeditionPlaces
local NativeList = SC.NativeList

local function call(object, method, ...)
    if object == nil or SC.Call == nil then return nil, false end
    local called, value = SC.Call.method(object, method, ...)
    return value, called
end

local function coordinate(value)
    value = tonumber(value)
    return value ~= nil and value == value and value >= 0 and value <= 30000
        and value == math.floor(value)
end

local function exteriorDistanceSq(bounds, x, y)
    local function clamp(value, low, high)
        return math.max(low, math.min(high, value))
    end
    local function distanceSq(px, py)
        return (px - x)^2 + (py - y)^2
    end
    return math.min(
        distanceSq(bounds.x - 1, clamp(y, bounds.y, bounds.y2)),
        distanceSq(bounds.x2 + 1, clamp(y, bounds.y, bounds.y2)),
        distanceSq(clamp(x, bounds.x, bounds.x2), bounds.y - 1),
        distanceSq(clamp(x, bounds.x, bounds.x2), bounds.y2 + 1))
end

local function classify(names)
    local found = {}
    for _, name in ipairs(names) do found[name] = true end
    local hasPolice, hasFire = false, false
    for _, name in ipairs(names) do
        if name:find("^police") then hasPolice = true end
        if name:find("^fire") then hasFire = true end
    end
    if hasPolice and hasFire then return "unclassified", "Building" end
    if hasPolice then return "police", "Police building" end
    if hasFire then return "fire", "Fire station" end
    if found.fossoil or found.gasstore or found.gasstorage then
        return "gas_station", "Gas station"
    end
    for _, name in ipairs(names) do
        if name:find("store", 1, true) or name == "grocery"
            or name == "shop" or name == "pharmacy" then
            return "store", "Store"
        end
    end
    if found.bedroom and (found.kitchen or found.livingroom) then
        return "residence", "House"
    end
    return "unclassified", "Building"
end

local function addStreet(place)
    local location = SC.Factions.describeLocation(place.anchor)
    local street = location and location.nearestStreet or nil
    place.street = street and street.name or nil
    place.streetDistance = street and street.distance or nil
    return place
end

function Places.describeBuilding(building, deferStreet)
    if building == nil then return nil, "building_unavailable" end
    local x, xOk = call(building, "getX")
    local y, yOk = call(building, "getY")
    local x2, x2Ok = call(building, "getX2")
    local y2, y2Ok = call(building, "getY2")
    x, y, x2, y2 = tonumber(x), tonumber(y), tonumber(x2), tonumber(y2)
    if not xOk or not yOk or not x2Ok or not y2Ok
        or not coordinate(x) or not coordinate(y)
        or not coordinate(x2) or not coordinate(y2)
        or x2 <= x or y2 <= y then
        return nil, "building_bounds_unavailable"
    end
    local rooms, roomsOk = call(building, "getRooms")
    if not roomsOk or rooms == nil then return nil, "building_rooms_unavailable" end
    local names, seen = {}, {}
    local roomCount = NativeList.size(rooms)
    if roomCount > 256 then return nil, "building_rooms_unbounded" end
    for index = 0, roomCount - 1 do
        local room, available = NativeList.get(rooms, index)
        if not available then return nil, "building_room_unavailable" end
        local name, nameOk = call(room, "getName")
        name = nameOk and type(name) == "string" and name:lower() or ""
        if name ~= "" and #name <= 64 and not seen[name] then
            seen[name] = true
            names[#names + 1] = name
        end
    end
    table.sort(names)
    local kind, label = classify(names)
    local minLevel, minLevelOk = call(building, "getMinLevel")
    local maxLevel, maxLevelOk = call(building, "getMaxLevel")
    minLevel, maxLevel = tonumber(minLevel), tonumber(maxLevel)
    local groundFloor = minLevelOk and maxLevelOk
        and minLevel ~= nil and maxLevel ~= nil
        and minLevel <= 0 and maxLevel >= 0 or false
    local anchor = { x = math.floor((x + x2) / 2),
        y = math.floor((y + y2) / 2), z = 0 }
    local place = {
        id = table.concat({ x, y, x2, y2 }, ":"),
        anchor = anchor, bounds = { x = x, y = y, x2 = x2, y2 = y2 },
        kind = kind, label = label, rooms = names,
        minLevel = minLevel, maxLevel = maxLevel,
        groundFloor = groundFloor,
    }
    return deferStreet and place or addStreet(place)
end

-- Direct lookup for a selected footprint; never scan the departure radius.
function Places.atPoint(at)
    if type(at) ~= "table" or not coordinate(at.x) or not coordinate(at.y)
        or at.z ~= 0 then return nil end
    local world = type(getWorld) == "function" and getWorld() or nil
    local grid = call(world, "getMetaGrid")
    local building = call(grid, "getBuildingAt", at.x, at.y, 0)
    local place = building and Places.describeBuilding(building)
    if not place or not place.groundFloor then return nil end
    place.knowledge = "map_metadata_unconfirmed"
    return place
end

-- Only a bounded area is indexed. This result is internal map metadata; a
-- player-facing picker should use targetableNearby for the selected policy.
function Places.nearby(x, y, radius, limit, deferStreets)
    x, y, radius, limit = tonumber(x), tonumber(y), tonumber(radius), tonumber(limit)
    if not coordinate(x) or not coordinate(y) or radius == nil
        or radius < 1 or radius > 200 or radius ~= math.floor(radius)
        or limit == nil or limit < 1 or limit > 4096
        or limit ~= math.floor(limit) then
        return nil, "invalid_place_query"
    end
    local world = type(getWorld) == "function" and getWorld() or nil
    local grid, gridOk = call(world, "getMetaGrid")
    if not gridOk or grid == nil then return nil, "meta_grid_unavailable" end
    local listClass = type(_G) == "table" and rawget(_G, "ArrayList") or nil
    if listClass == nil then return nil, "building_result_list_unavailable" end
    local result, seen = {}, {}
    local left, top = math.max(0, x - radius), math.max(0, y - radius)
    local width, height = radius * 2 + 1, radius * 2 + 1
    -- Each native query remains bounded, including in a dense 200-tile area.
    -- Overlapping sector footprints are deduplicated by stable building bounds.
    local side = radius > 150 and 2 or 1
    for row = 0, side - 1 do
        for column = 0, side - 1 do
            local sx = left + math.floor(width * column / side)
            local sy = top + math.floor(height * row / side)
            local ex = left + math.floor(width * (column + 1) / side)
            local ey = top + math.floor(height * (row + 1) / side)
            local created, buildings = pcall(function() return listClass.new() end)
            if not created or buildings == nil then
                return nil, "building_result_list_unavailable"
            end
            local _, queried = call(grid, "getBuildingsIntersecting",
                sx, sy, ex - sx, ey - sy, buildings)
            if not queried then return nil, "building_query_unavailable" end
            local count = NativeList.size(buildings)
            if count > 2048 then return nil, "building_query_unbounded" end
            for index = 0, count - 1 do
                local building, available = NativeList.get(buildings, index)
                if not available then return nil, "building_result_unavailable" end
                local place = Places.describeBuilding(building, true)
                if place and not seen[place.id] then
                    seen[place.id] = true
                    place.distanceSq = exteriorDistanceSq(place.bounds, x, y)
                    place.distance = math.floor(math.sqrt(place.distanceSq) + 0.5)
                    result[#result + 1] = place
                    if #result > 4096 then return nil, "building_query_unbounded" end
                end
            end
        end
    end
    table.sort(result, function(a, b)
        if a.distance ~= b.distance then return a.distance < b.distance end
        return a.id < b.id
    end)
    while #result > limit do result[#result] = nil end
    if deferStreets ~= true then
        for _, place in ipairs(result) do addStreet(place) end
    end
    return result
end

local function pathRoomProgress(square, sourceRoom, sourceBuilding, outside)
    local room, roomOk = call(square, "getRoom")
    if not roomOk then return nil end
    if room == nil then return true end
    if outside then return nil end
    if room ~= sourceRoom then
        local building, known = call(room, "getBuilding")
        if sourceBuilding == nil or not known or building ~= sourceBuilding then return nil end
    end
    return false
end

local function isOutsidePath(path, sourceRoom)
    local outside = sourceRoom == nil
    local sourceBuilding = call(sourceRoom, "getBuilding")
    for _, square in ipairs(path) do
        outside = pathRoomProgress(square, sourceRoom, sourceBuilding, outside)
        if outside == nil then return false end
    end
    return outside
end

local savedSite
local function matchingBuildingAt(grid, place, x, y, z)
    local building, found = call(grid, "getBuildingAt", x, y, z or 0)
    if not found or building == nil then return false end
    if z ~= nil and z ~= 0 then
        local low, lowOk = call(building, "getMinLevel")
        local high, highOk = call(building, "getMaxLevel")
        if not lowOk or not highOk or tonumber(low) == nil
            or tonumber(high) == nil or z < tonumber(low)
            or z > tonumber(high) then return false end
    end
    local bx, bxOk = call(building, "getX")
    local by, byOk = call(building, "getY")
    local bx2, bx2Ok = call(building, "getX2")
    local by2, by2Ok = call(building, "getY2")
    local matching = bxOk and byOk and bx2Ok and by2Ok
        and table.concat({ bx, by, bx2, by2 }, ":") == place.id
    return matching, matching and building or nil
end

-- Read the floor range afresh from the saved site's map building. A mission
-- stores only the stable footprint ID, not mutable planner page metadata.
function Places.siteFloors(siteId)
    local place = savedSite(siteId)
    if place == nil then return nil end
    local world = type(getWorld) == "function" and getWorld() or nil
    local grid, ready = call(world, "getMetaGrid")
    if not ready or grid == nil then return nil end
    local bounds = place.bounds
    local midX = math.floor((bounds.x + bounds.x2) / 2)
    local midY = math.floor((bounds.y + bounds.y2) / 2)
    local building
    for _, point in ipairs({
        { midX, midY }, { bounds.x, bounds.y },
        { bounds.x2, bounds.y }, { bounds.x, bounds.y2 },
        { bounds.x2, bounds.y2 },
    }) do
        local matching, candidate = matchingBuildingAt(
            grid, place, point[1], point[2], 0)
        if matching then
            building = candidate
            break
        end
    end
    if building == nil then return nil end
    local low, lowOk = call(building, "getMinLevel")
    local high, highOk = call(building, "getMaxLevel")
    low, high = tonumber(low), tonumber(high)
    if not lowOk or not highOk or low == nil or high == nil
        or low ~= math.floor(low) or high ~= math.floor(high)
        or low < -32 or high > 31 or low > 0 or high < 0
        or high - low > 7 then return nil end
    local floors = {}
    for z = low, high do floors[#floors + 1] = z end
    return floors
end

local function validBounds(place)
    local bounds = type(place) == "table" and place.bounds or nil
    if type(bounds) ~= "table" or not coordinate(bounds.x)
        or not coordinate(bounds.y) or not coordinate(bounds.x2)
        or not coordinate(bounds.y2) or bounds.x2 <= bounds.x
        or bounds.y2 <= bounds.y or bounds.x2 - bounds.x > 80
        or bounds.y2 - bounds.y > 80
        or place.id ~= table.concat({ bounds.x, bounds.y,
            bounds.x2, bounds.y2 }, ":") then
        return nil
    end
    return bounds
end

savedSite = function(siteId)
    if type(siteId) ~= "string" then return nil end
    local x, y, x2, y2 = siteId:match("^(%d+):(%d+):(%d+):(%d+)$")
    local place = { id = siteId, bounds = {
        x = tonumber(x), y = tonumber(y),
        x2 = tonumber(x2), y2 = tonumber(y2),
    } }
    return validBounds(place) and place or nil
end

-- The exterior approach point is not the search area. Verify the saved map
-- footprint against the current metagrid before accepting a source square.
function Places.siteContainsPoint(siteId, x, y, z)
    local place = savedSite(siteId)
    local bounds = place and place.bounds
    x, y, z = tonumber(x), tonumber(y), tonumber(z)
    if bounds == nil or not coordinate(x) or not coordinate(y)
        or z == nil or z ~= math.floor(z) or z < -32 or z > 31
        or x < bounds.x or x > bounds.x2
        or y < bounds.y or y > bounds.y2 then return false end
    local world = type(getWorld) == "function" and getWorld() or nil
    local grid, ready = call(world, "getMetaGrid")
    if not ready or grid == nil then return false end
    return matchingBuildingAt(grid, place, x, y, z) == true
end

local entryOffsets = {{1, 0}, {-1, 0}, {0, 1}, {0, -1}}

local function ordinaryEntryEdge(actor, outside, inside)
    local topology = SC.Topology
    if not topology or not topology.classifyEdge then return nil end
    local outdoors, known = call(outside, "getRoom")
    local indoors = call(inside, "getRoom")
    if not known or outdoors or not indoors
        or not SC.GameplayUtil.isSquareFree(outside) then return nil end
    local edge = topology.classifyEdge(actor, outside, inside)
    local kind = edge and edge.affordance
    if edge and edge.traversable and (kind == "open" or kind == "door"
        or kind == "window" or kind == "window_frame") then return edge end
end

function Places.siteEntryPortalSquares(actor, portal)
    local util = SC.GameplayUtil
    local outside = util.gridSquare(portal.outside.x, portal.outside.y, 0)
    local inside = util.gridSquare(portal.inside.x, portal.inside.y, 0)
    if outside and inside and ordinaryEntryEdge(actor, outside, inside) then
        return outside, inside
    end
end

local function addEntryPortals(portals, actor, cell, square, x, y, ax, ay)
    local topology = SC.Topology
    if not topology or not topology.classifyEdge then return end
    for _, offset in ipairs(entryOffsets) do
        local ox, oy = x + offset[1], y + offset[2]
        local outside = call(cell, "getGridSquare", ox, oy, 0)
        local edge = ordinaryEntryEdge(actor, outside, square)
        if edge then
            local kind = edge.affordance
            local window = kind == "window" or kind == "window_frame"
            local key = table.concat({ox, oy, x, y}, ":")
            local signature = topology.objectStateSignature
                and topology.objectStateSignature(edge.object) or kind
            portals[#portals + 1] = {
                outside = {x = ox, y = oy, z = 0}, inside = {x = x, y = y, z = 0},
                key = key, signature = signature,
                score = math.sqrt((ox - ax)^2 + (oy - ay)^2)
                    + (window and math.max(4, tonumber(edge.cost) or 0) or 0),
            }
        end
    end
end

-- Keep the scan local. A portal records the actual exterior stand and interior
-- landing so the expedition can walk around the building before crossing.
function Places.loadedInteriorCandidates(siteId, actor, survey)
    local place = savedSite(siteId)
    if not place or not actor or not SC.GameplayUtil then
        return {}, "site_entry_unavailable"
    end
    local ax, ay = tonumber(actor:getX()), tonumber(actor:getY())
    local world = type(getWorld) == "function" and getWorld() or nil
    local grid, gridOk = call(world, "getMetaGrid")
    local cell, cellOk = call(world, "getCell")
    if not ax or not ay or not gridOk or not cellOk or not grid or not cell then
        return {}, "site_entry_unavailable"
    end
    survey = survey or {}
    if survey.index == nil then
        local radius = survey.budget and 32 or 14
        local bounds = place.bounds
        survey.x = math.max(bounds.x, math.floor(ax) - radius)
        survey.y = math.max(bounds.y, math.floor(ay) - radius)
        survey.width = math.max(0, math.min(bounds.x2, math.floor(ax) + radius) - survey.x + 1)
        survey.total = survey.width
            * math.max(0, math.min(bounds.y2, math.floor(ay) + radius) - survey.y + 1)
        survey.index, survey.candidates, survey.portals = 0, {}, {}
    end
    local candidates, portals = survey.candidates, survey.portals
    local finish = math.min(survey.total, survey.index + (survey.budget or survey.total))
    for index = survey.index, finish - 1 do
        local x = survey.x + index % survey.width
        local y = survey.y + math.floor(index / survey.width)
        local square, loaded = call(cell, "getGridSquare", x, y, 0)
        local room, roomOk = call(square, "getRoom")
        if loaded and square and roomOk and room
            and SC.GameplayUtil.isSquareFree(square)
            and matchingBuildingAt(grid, place, x, y, 0) then
            candidates[#candidates + 1] = {
                x = x, y = y, z = 0,
                distanceSq = (x - ax)^2 + (y - ay)^2,
            }
            addEntryPortals(portals, actor, cell, square, x, y, ax, ay)
        end
    end
    survey.index = finish
    if finish < survey.total then return nil, "site_entry_survey_pending" end
    table.sort(candidates, function(a, b)
        if a.distanceSq ~= b.distanceSq then
            return a.distanceSq < b.distanceSq
        end
        if a.x ~= b.x then return a.x < b.x end
        return a.y < b.y
    end)
    local result = {}
    for _, candidate in ipairs(candidates) do
        local distinct = true
        for _, chosen in ipairs(result) do
            if (candidate.x - chosen.x)^2 + (candidate.y - chosen.y)^2 < 9 then
                distinct = false
                break
            end
        end
        if distinct then
            result[#result + 1] = { x = candidate.x, y = candidate.y, z = 0 }
            if #result >= 12 then break end
        end
    end
    table.sort(portals, function(a, b)
        if a.score ~= b.score then return a.score < b.score end
        if a.outside.x ~= b.outside.x then return a.outside.x < b.outside.x end
        if a.outside.y ~= b.outside.y then return a.outside.y < b.outside.y end
        if a.inside.x ~= b.inside.x then return a.inside.x < b.inside.x end
        return a.inside.y < b.inside.y
    end)
    local selectable, retryPending = {}, false
    for _, portal in ipairs(portals) do
        local rejected = survey.rejected and survey.rejected[portal.key]
        if not rejected or rejected.signature ~= portal.signature
            or survey.now >= rejected.retryAt then
            selectable[#selectable + 1] = portal
            if #selectable >= (survey.budget and 8 or 4) then break end
        elseif rejected.retryAt < math.huge then
            retryPending = true
        end
    end
    return result, #result == 0 and "site_entry_no_loaded_floor" or nil, selectable, retryPending
end

function Places.actorInsideSite(siteId, actor)
    local place = savedSite(siteId)
    local square, squareOk = call(actor, "getCurrentSquare")
    local room, roomOk = call(square, "getRoom")
    if not place or not squareOk or not roomOk or not room then return false end
    local x, xOk = call(square, "getX")
    local y, yOk = call(square, "getY")
    local z, zOk = call(square, "getZ")
    local world = type(getWorld) == "function" and getWorld() or nil
    local grid, gridOk = call(world, "getMetaGrid")
    return xOk and yOk and zOk and gridOk and grid
        and matchingBuildingAt(grid, place, x, y, z) == true or false
end

-- A scout confirms its selected building only from a square it can actually
-- see. Bound the inspection to loaded squares near the leader.
function Places.visibleSiteSquare(siteId, actor)
    local place = savedSite(siteId)
    if place == nil or actor == nil or SC.GameplayUtil == nil
        or type(SC.GameplayUtil.canSee) ~= "function" then return false end
    local ax, xOk = call(actor, "getX")
    local ay, yOk = call(actor, "getY")
    local az, zOk = call(actor, "getZ")
    ax, ay, az = tonumber(ax), tonumber(ay), tonumber(az)
    if not xOk or not yOk or not zOk or ax == nil or ay == nil
        or az == nil or not coordinate(math.floor(ax))
        or not coordinate(math.floor(ay)) or math.floor(az) ~= 0 then
        return false
    end
    local world = type(getWorld) == "function" and getWorld() or nil
    local grid, gridOk = call(world, "getMetaGrid")
    local cell, cellOk = call(world, "getCell")
    if not gridOk or not cellOk or grid == nil or cell == nil then
        return false
    end
    local bounds = place.bounds
    local axTile, ayTile = math.floor(ax), math.floor(ay)
    local checked = 0
    for radius = 0, 8 do
        for dx = -radius, radius do
            for dy = -radius, radius do
                if math.max(math.abs(dx), math.abs(dy)) == radius then
                    local x, y = axTile + dx, ayTile + dy
                    if x >= bounds.x and x <= bounds.x2
                        and y >= bounds.y and y <= bounds.y2
                        and matchingBuildingAt(grid, place, x, y) then
                        local square, loaded = call(cell,
                            "getGridSquare", x, y, 0)
                        if loaded and square ~= nil then
                            checked = checked + 1
                            if SC.GameplayUtil.canSee(actor, square) == true then
                                return true
                            end
                            if checked >= 64 then return false end
                        end
                    end
                end
            end
        end
    end
    return false
end

-- A map footprint can be selected before its chunks are loaded. Pick the
-- nearest exterior coordinate from that footprint without searching a route
-- on the UI thread. The leader will validate the actual loaded approach when
-- it reaches the site; this coordinate is only a direction for local legs.
function Places.plannedApproach(place, actor)
    local bounds = validBounds(place)
    if bounds == nil then return nil, "invalid_place_reference" end
    if place.groundFloor ~= true then
        return nil, "place_without_ground_floor"
    end
    local source, sourceOk = call(actor, "getCurrentSquare")
    local sourceX, xOk = call(source, "getX")
    local sourceY, yOk = call(source, "getY")
    if not sourceOk or source == nil or not xOk or not yOk
        or not coordinate(sourceX) or not coordinate(sourceY) then
        return nil, "approach_source_unavailable"
    end
    local world = type(getWorld) == "function" and getWorld() or nil
    local grid, gridOk = call(world, "getMetaGrid")
    if not gridOk or grid == nil then
        return nil, "approach_world_unavailable"
    end
    local best, bestDistance
    local function consider(x, y, insideX, insideY, side)
        if x < 0 or y < 0 or x > 30000 or y > 30000
            or not matchingBuildingAt(grid, place, insideX, insideY) then
            return
        end
        local distance = (sourceX - x)^2 + (sourceY - y)^2
        if bestDistance == nil or distance < bestDistance then
            bestDistance = distance
            best = { x = x, y = y, z = 0,
                buildingId = place.id, side = side,
                scope = "map_exterior_pending" }
        end
    end
    for y = bounds.y, bounds.y2 do
        consider(bounds.x - 1, y, bounds.x, y, "west")
        consider(bounds.x2 + 1, y, bounds.x2, y, "east")
    end
    for x = bounds.x, bounds.x2 do
        consider(x, bounds.y - 1, x, bounds.y, "north")
        consider(x, bounds.y2 + 1, x, bounds.y2, "south")
    end
    if best == nil then return nil, "approach_exterior_unavailable" end
    return best
end

local function outdoorCandidateSquare(grid, cell, place, x, y, side)
    if x < 0 or y < 0 or x > 30000 or y > 30000 then return end
    local square, loaded = call(cell, "getGridSquare", x, y, 0)
    if not loaded or square == nil then return end
    local room, roomOk = call(square, "getRoom")
    if not roomOk or room ~= nil
        or not SC.GameplayUtil.isSquareFree(square) then return end
    local insideX, insideY = x, y
    if side == "west" then insideX = x + 1 end
    if side == "east" then insideX = x - 1 end
    if side == "north" then insideY = y + 1 end
    if side == "south" then insideY = y - 1 end
    if not matchingBuildingAt(grid, place, insideX, insideY) then return end
    return square
end

local function addCandidate(survey, x, y, side)
    local square = outdoorCandidateSquare(survey.grid, survey.cell, survey.place, x, y, side)
    if square == nil then return end
    local dx, dy = survey.sourceX - x, survey.sourceY - y
    local candidates = survey.sides[side]
    candidates[#candidates + 1] = {
        x = x, y = y, z = 0, square = square, side = side,
        distanceSq = dx * dx + dy * dy,
    }
end

local function readApproachInputs(actor)
    local source, sourceOk = call(actor, "getCurrentSquare")
    local sourceX, xOk = call(source, "getX")
    local sourceY, yOk = call(source, "getY")
    local sourceRoom, roomOk = call(source, "getRoom")
    if not sourceOk or source == nil or not xOk or not yOk or not roomOk
        or not coordinate(sourceX) or not coordinate(sourceY) then
        return nil, "approach_source_unavailable"
    end
    local world = type(getWorld) == "function" and getWorld() or nil
    local grid, gridOk = call(world, "getMetaGrid")
    local cell, cellOk = call(world, "getCell")
    if not gridOk or not cellOk or grid == nil or cell == nil
        or SC.GameplayUtil == nil
        or type(SC.GameplayUtil.isSquareFree) ~= "function" then
        return nil, "approach_world_unavailable"
    end
    return { actor = actor, source = source, sourceRoom = sourceRoom,
        sourceX = sourceX, sourceY = sourceY, grid = grid, cell = cell }
end

local function startApproachSurvey(survey, place, bounds)
    survey.place, survey.bounds = place, bounds
    survey.sides = { west = {}, east = {}, north = {}, south = {} }
    survey.boundaryIndex, survey.candidateIndex = 0, 1
    survey.verticalCount = (bounds.y2 - bounds.y + 1) * 2
    survey.boundaryCount = survey.verticalCount + (bounds.x2 - bounds.x + 1) * 2
    return survey
end

local function scanApproachBoundary(survey, budget, expired)
    local bounds = survey.bounds
    local before = survey.boundaryIndex
    local finish = math.min(survey.boundaryCount, before + budget)
    for index = before, finish - 1 do
        if index > before and expired and expired() then break end
        if index < survey.verticalCount then
            local y = bounds.y + math.floor(index / 2)
            if index % 2 == 0 then
                addCandidate(survey, bounds.x - 1, y, "west")
            else
                addCandidate(survey, bounds.x2 + 1, y, "east")
            end
        else
            local column = index - survey.verticalCount
            local x = bounds.x + math.floor(column / 2)
            if column % 2 == 0 then
                addCandidate(survey, x, bounds.y - 1, "north")
            else
                addCandidate(survey, x, bounds.y2 + 1, "south")
            end
        end
        survey.boundaryIndex = index + 1
    end
    return survey.boundaryIndex - before
end

local function approachCandidateLess(a, b)
    if a.distanceSq ~= b.distanceSq then return a.distanceSq < b.distanceSq end
    if a.x ~= b.x then return a.x < b.x end
    return a.y < b.y
end

local function orderedApproachCandidates(sides)
    local candidates = {}
    local sideOrder = { "west", "east", "north", "south" }
    for _, side in ipairs(sideOrder) do
        table.sort(sides[side], approachCandidateLess)
    end
    -- Try more than the three closest squares on each face. A boarded window
    -- or dense vegetation can block those while another part of the same
    -- loaded building has a sound exterior approach.
    for rank = 1, 6 do
        for _, side in ipairs(sideOrder) do
            local candidate = sides[side][rank]
            if candidate then candidates[#candidates + 1] = candidate end
        end
    end
    table.sort(candidates, approachCandidateLess)
    return candidates
end

local function approachResult(survey, candidate, path)
    return { x = candidate.x, y = candidate.y, z = 0,
        buildingId = survey.place.id, side = candidate.side,
        pathNodes = #path, scope = "loaded_exterior_only" }
end

-- This verifies a loaded exterior stand. The entry survey separately checks
-- the door or window from an exact outside stand to an interior landing.
function Places.loadedApproach(place, actor)
    local bounds = validBounds(place)
    if bounds == nil then return nil, "invalid_place_reference" end
    if place.groundFloor ~= true then return nil, "place_without_ground_floor" end
    local survey, reason = readApproachInputs(actor)
    if survey == nil then return nil, reason end
    local nav = SC.Navigation
    if not nav or type(nav.findPath) ~= "function" then return nil, "approach_world_unavailable" end
    startApproachSurvey(survey, place, bounds)
    scanApproachBoundary(survey, survey.boundaryCount)
    local candidates = orderedApproachCandidates(survey.sides)
    if #candidates == 0 then return nil, "approach_exterior_unavailable" end
    for _, candidate in ipairs(candidates) do
        local path
        if candidate.x == survey.sourceX and candidate.y == survey.sourceY then
            path = { survey.source }
        else
            path = nav.findPath(survey.source, candidate.square,
                { actor = actor, nodeBudget = 1800 })
        end
        if path ~= nil and #path >= 1 and #path <= 180
            and isOutsidePath(path, survey.sourceRoom) then
            return approachResult(survey, candidate, path)
        end
    end
    return nil, "approach_no_loaded_path"
end

-- Saved site descriptions retain the footprint ID but not the draft-only
-- bounds. Rebuild those bounds for the final, loaded arrival check.
function Places.loadedSiteApproach(siteId, actor)
    local place = savedSite(siteId)
    if place == nil then return nil, "invalid_place_reference" end
    place.groundFloor = true
    return Places.loadedApproach(place, actor)
end

local function currentApproachSquare(cell, square)
    local x = call(square, "getX")
    local y = call(square, "getY")
    local z = call(square, "getZ")
    return coordinate(x) and coordinate(y) and type(z) == "number"
        and call(cell, "getGridSquare", x, y, z) == square
end

local function sameApproachInputs(survey, siteId, current)
    return survey and survey.place.id == siteId and survey.actor == current.actor
        and survey.source == current.source and survey.sourceRoom == current.sourceRoom
        and survey.sourceX == current.sourceX and survey.sourceY == current.sourceY
        and survey.grid == current.grid and survey.cell == current.cell
end

local function candidateStillValid(survey, candidate)
    return outdoorCandidateSquare(survey.grid, survey.cell, survey.place,
        candidate.x, candidate.y, candidate.side) == candidate.square
end

local function advanceApproachCandidate(survey)
    survey.job, survey.proof = nil, nil
    survey.candidateIndex = survey.candidateIndex + 1
    if survey.candidates[survey.candidateIndex] == nil then
        return nil, "approach_no_loaded_path", "failed"
    end
    return nil, "approach_search_pending", "pending"
end

local function verifyApproachPath(survey, candidate, nav, expired)
    local proof = survey.proof
    local first = proof.index
    local finish = math.min(#proof.path, first + 6)
    local options = { actor = survey.actor, allowHazards = false }
    local function passable(previous, square)
        return nav._adjacentStepForWorkRoutes(previous, square)
            and nav._passableEdgeForWorkRoutes(previous, square, 1, options) == true
    end
    for index = first, finish do
        if index > first and expired() then break end
        local square = proof.path[index]
        if not currentApproachSquare(survey.cell, square) then return false end
        proof.outside = pathRoomProgress(square, survey.sourceRoom, proof.sourceBuilding, proof.outside)
        if proof.outside == nil then return false end
        if index > 1 and not passable(proof.path[index - 1], square) then return false end
        proof.index = index + 1
    end
    if proof.index <= #proof.path then return nil end
    -- The handoff is an exterior point, and Navigation proves its own route
    -- from there. Refresh the start edge while publishing this survey result.
    local nextSquare = proof.path[2]
    return proof.outside and currentApproachSquare(survey.cell, nextSquare)
        and pathRoomProgress(nextSquare, survey.sourceRoom, proof.sourceBuilding,
            survey.sourceRoom == nil) ~= nil
        and passable(survey.source, nextSquare)
        and candidateStillValid(survey, candidate)
end

local function pollApproachSurvey(survey, nav, perf, expired)
    if survey.candidates == nil then
        local tested = scanApproachBoundary(survey, 16, expired)
        if survey.boundaryIndex >= survey.boundaryCount then
            survey.candidates = orderedApproachCandidates(survey.sides)
            survey.sides = nil
            if #survey.candidates == 0 then return nil, "approach_exterior_unavailable", "failed", tested end
        end
        return nil, "approach_boundary_pending", "pending", tested
    end
    local candidate = survey.candidates[survey.candidateIndex]
    if not candidateStillValid(survey, candidate) then return advanceApproachCandidate(survey) end
    if survey.proof then
        local valid = verifyApproachPath(survey, candidate, nav, expired)
        if valid == nil then return nil, "approach_proof_pending", "pending" end
        if valid then return approachResult(survey, candidate, survey.proof.path), nil, "complete" end
        return advanceApproachCandidate(survey)
    end

    if survey.source == candidate.square then
        return approachResult(survey, candidate, { survey.source }), nil, "complete"
    end
    local quota, claim = 48, nil
    if perf and type(perf.claimUnits) == "function" then
        quota, claim = perf.claimUnits("navigation", quota, false, true)
    end
    if quota <= 0 then return nil, "approach_search_pending", "pending" end
    if survey.job == nil then
        survey.job = nav.beginPathSearch(survey.source, candidate.square, nil,
            { actor = survey.actor, nodeBudget = 1800, alternatives = false, sliceBudgetMs = 1 })
    end
    local status, path, reason, expanded, report, used
    if survey.job then
        status, path, reason, expanded, report, used = nav.resumePathSearch(survey.job, quota)
    end
    used = tonumber(used) or 0
    if claim and type(perf.settleUnits) == "function" then perf.settleUnits(claim, used) end
    if status == "pending" then return nil, "approach_search_pending", "pending", used end
    if status == "complete" and reason == nil and type(path) == "table" and #path >= 2 and #path <= 180
        and path[1] == survey.source and path[#path] == candidate.square then
        survey.job = nil
        survey.proof = { path = path, index = 1, outside = survey.sourceRoom == nil,
            sourceBuilding = call(survey.sourceRoom, "getBuilding") }
        return nil, "approach_proof_pending", "pending", used
    end
    local approach, why, nextStatus = advanceApproachCandidate(survey)
    return approach, why, nextStatus, used
end

-- A scout owns this transient survey until it confirms an exterior stand or
-- reaches a terminal result. A pending slice does not establish obstruction.
function Places.pollLoadedSiteApproach(siteId, actor, state)
    if type(state) ~= "table" then return nil, "approach_state_unavailable", "failed" end
    local nav, perf = SC.Navigation, SC.Performance
    if not nav or type(nav.beginPathSearch) ~= "function" or type(nav.resumePathSearch) ~= "function"
        or type(nav._adjacentStepForWorkRoutes) ~= "function"
        or type(nav._passableEdgeForWorkRoutes) ~= "function" then
        state.survey = nil
        return nil, "approach_world_unavailable", "failed"
    end
    local frame = perf and type(perf.frameId) == "function" and perf.frameId() or nil
    if frame ~= nil and state.lastFrame == frame then return nil, "approach_frame_pending", "pending" end
    state.lastFrame = frame
    local clock = perf and perf.preciseNowMs
    local began = type(clock) == "function" and clock() or nil
    local function expired()
        return began ~= nil and clock() - began >= 1
    end
    local current, reason = readApproachInputs(actor)
    if current == nil or not currentApproachSquare(current.cell, current.source) then
        state.survey = nil
        return nil, reason or "approach_source_unavailable", "failed"
    end
    if not sameApproachInputs(state.survey, siteId, current) then
        local place = savedSite(siteId)
        if not place then
            state.survey = nil
            return nil, "invalid_place_reference", "failed"
        end
        state.survey = startApproachSurvey(current, place, place.bounds)
    end
    local approach, why, status, units = pollApproachSurvey(state.survey, nav, perf, expired)
    if status ~= "pending" then state.survey = nil end
    if began ~= nil and type(perf.record) == "function" then
        perf.record("expedition.site-approach", nil, clock() - began, units or 0, status == "pending")
    end
    return approach, why, status
end

-- Emergency refuge must be an actual reachable interior square. A map house
-- label or an exterior doorstep alone is not shelter from a blocked road.
function Places.nearestLoadedShelter(actor, hazard, excluded)
    local source = actor and actor:getCurrentSquare()
    local x, y = SC.GameplayUtil.position(actor)
    local world = type(getWorld) == "function" and getWorld() or nil
    local cell = world and world:getCell() or nil
    if source == nil or x == nil or y == nil or cell == nil
        or SC.Navigation == nil or type(SC.Navigation.findPath) ~= "function" then
        return nil, "shelter_area_unavailable"
    end
    local places, reason = Places.nearby(math.floor(x), math.floor(y),
        40, 64, true)
    if places == nil then return nil, reason end
    local checked = 0
    for _, place in ipairs(places) do
        if place.kind == "residence" and place.groundFloor == true
            and not (excluded and excluded[place.id]) then
            checked = checked + 1
            if checked > 8 then break end
            local options = {}
            local bounds = place.bounds
            local area = (bounds.x2 - bounds.x + 1)
                * (bounds.y2 - bounds.y + 1)
            local stride = math.max(1, math.ceil(math.sqrt(area / 256)))
            for sx = bounds.x, bounds.x2, stride do
                for sy = bounds.y, bounds.y2, stride do
                    local square = cell:getGridSquare(sx, sy, 0)
                    if square and square:getRoom() ~= nil
                        and SC.GameplayUtil.isSquareFree(square)
                        and not (excluded and excluded[sx..":"..sy..":0"])
                        and (hazard == nil or math.sqrt((sx - hazard.x)^2
                            + (sy - hazard.y)^2) > hazard.radius + 3) then
                        options[#options + 1] = { square = square,
                            x = sx, y = sy,
                            distance = (sx - x)^2 + (sy - y)^2 }
                    end
                end
            end
            table.sort(options, function(a, b)
                return a.distance < b.distance
            end)
            for index = 1, math.min(8, #options) do
                local candidate = options[index]
                local path = SC.Navigation.findPath(source,
                    candidate.square, { actor = actor, nodeBudget = 1800 })
                if path and #path >= 1 and #path <= 80
                    and (hazard == nil or SC.ExpeditionRoute.withinCorridor(
                        { points = {}, index = 1, avoidance = hazard,
                            allowEscapeFromAvoidance = true }, path)) then
                    return { x = candidate.x, y = candidate.y, z = 0,
                        buildingId = place.id, pathNodes = #path }
                end
            end
        end
    end
    return nil, "shelter_no_loaded_path"
end

local function sameShelterExclusions(snapshot, excluded)
    for key in pairs(snapshot) do
        if not (excluded and excluded[key]) then return false end
    end
    for key, enabled in pairs(excluded or {}) do
        if enabled and not snapshot[key] then return false end
    end
    return true
end

local function sameShelterSurvey(survey, current, hazard, excluded)
    if not survey or survey.actor ~= current.actor or survey.source ~= current.source
        or survey.sourceRoom ~= current.sourceRoom or survey.cell ~= current.cell
        or survey.grid ~= current.grid then return false end
    local marker = survey.hazard
    if marker ~= nil or hazard ~= nil then
        if not marker or not hazard or marker.x ~= hazard.x or marker.y ~= hazard.y
            or marker.radius ~= hazard.radius then return false end
    end
    return sameShelterExclusions(survey.excluded, excluded)
end

local function shelterOutsideHazard(hazard, x, y, clearance)
    return hazard == nil or (x - hazard.x)^2 + (y - hazard.y)^2
        > (hazard.radius + clearance)^2
end

local function shelterCandidateSquare(survey, house, x, y)
    if survey.excluded[house.place.id] or survey.excluded[x .. ":" .. y .. ":0"]
        or not shelterOutsideHazard(survey.hazard, x, y, 3) then return nil end
    local square = call(survey.cell, "getGridSquare", x, y, 0)
    if square and call(square, "getRoom") ~= nil and SC.GameplayUtil.isSquareFree(square)
        and matchingBuildingAt(survey.grid, house.place, x, y, 0) then return square end
end

local function shelterCandidateLess(a, b)
    if a.distance ~= b.distance then return a.distance < b.distance end
    if a.x ~= b.x then return a.x < b.x end
    return a.y < b.y
end

local function beginShelterSurvey(current, hazard, excluded)
    local x, y = SC.GameplayUtil.position(current.actor)
    if x == nil or y == nil then return nil, "shelter_area_unavailable" end
    local places, reason = Places.nearby(math.floor(x), math.floor(y), 40, 64, true)
    if not places then return nil, reason end
    current.x, current.y = x, y
    current.hazard = hazard and { x = hazard.x, y = hazard.y, radius = hazard.radius }
    current.excluded, current.houses = {}, {}
    for key, enabled in pairs(excluded or {}) do
        if enabled then current.excluded[key] = true end
    end
    for _, place in ipairs(places) do
        if place.kind == "residence" and place.groundFloor and not current.excluded[place.id] then
            local bounds = place.bounds
            local area = (bounds.x2 - bounds.x + 1) * (bounds.y2 - bounds.y + 1)
            current.houses[#current.houses + 1] = { place = place, x = bounds.x, y = bounds.y,
                stride = math.max(1, math.ceil(math.sqrt(area / 256))), candidates = {} }
            if #current.houses >= 8 then break end
        end
    end
    if #current.houses == 0 then return nil, "shelter_no_loaded_path" end
    current.discoveryIndex, current.searchIndex, current.discoveryTurn = 1, 1, true
    return current
end

local function scanShelterHouse(survey, house, expired)
    local bounds = house.place.bounds
    local checked = 0
    while house.x <= bounds.x2 and checked < 24 and (checked == 0 or not expired()) do
        local x, y = house.x, house.y
        local square = shelterCandidateSquare(survey, house, x, y)
        if square then
            local candidates = house.candidates
            local candidate = { square = square, x = x, y = y,
                distance = (x - survey.x)^2 + (y - survey.y)^2 }
            if #candidates < 8 or shelterCandidateLess(candidate, candidates[8]) then
                candidates[#candidates + 1] = candidate
                table.sort(candidates, shelterCandidateLess)
                candidates[9] = nil
            end
        end
        checked = checked + 1
        house.y = y + house.stride
        if house.y > bounds.y2 then house.x, house.y = x + house.stride, bounds.y end
    end
    if house.x > bounds.x2 then
        survey.discoveryIndex = survey.discoveryIndex + 1
        house.ready = #house.candidates > 0
    end
    return checked
end

-- Match the road corridor's escape rule for each edge, so a short unsafe
-- route does not hide a safe route to the same house.
local function shelterCorridorEdge(survey, previous, square)
    local hazard = survey.hazard
    if not hazard then return true end
    local x, y = SC.GameplayUtil.position(square)
    if x == nil or y == nil then return false end
    if shelterOutsideHazard(hazard, x, y, 2) then return true end
    if shelterOutsideHazard(hazard, survey.sourceX, survey.sourceY, 2) then return false end
    local px, py = SC.GameplayUtil.position(previous)
    if px == nil or py == nil or shelterOutsideHazard(hazard, px, py, 2) then return false end
    local originDistance = math.sqrt((survey.sourceX - hazard.x)^2 + (survey.sourceY - hazard.y)^2)
    return math.sqrt((x - hazard.x)^2 + (y - hazard.y)^2) >= originDistance - 1
end

local function shelterResult(house, candidate, path)
    return { x = candidate.x, y = candidate.y, z = 0,
        buildingId = house.place.id, pathNodes = #path, path = path }
end

local function verifyShelterPath(survey, nav, expired)
    local proof = survey.proof
    local path, candidate, house = proof.path, proof.candidate, proof.house
    local first = proof.index
    local options = { actor = survey.actor, allowHazards = false }
    local function passable(previous, square)
        return shelterCorridorEdge(survey, previous, square)
            and nav._adjacentStepForWorkRoutes(previous, square)
            and nav._passableEdgeForWorkRoutes(previous, square, 1, options) == true
    end
    for index = first, math.min(#path, first + 6) do
        if index > first and expired() then break end
        local square = path[index]
        if not currentApproachSquare(survey.cell, square)
            or (index > 1 and not passable(path[index - 1], square)) then return false end
        proof.index = index + 1
    end
    if proof.index <= #path then return nil end
    if #path > 1 and (not currentApproachSquare(survey.cell, path[2])
        or not passable(path[1], path[2])) then return false end
    return shelterCandidateSquare(survey, house, candidate.x, candidate.y) == candidate.square
end

local function pollShelterJob(survey, house, nav, quota)
    if not house.job then
        local goals = {}
        for index = #house.candidates, 1, -1 do
            local candidate = house.candidates[index]
            if shelterCandidateSquare(survey, house, candidate.x, candidate.y) ~= candidate.square then
                table.remove(house.candidates, index)
            end
        end
        for _, candidate in ipairs(house.candidates) do goals[#goals + 1] = candidate.square end
        if #goals == 0 then house.ready = false return 0 end
        house.job = nav.beginPathSearch(survey.source, goals[1], nil, {
            actor = survey.actor, goalSquares = goals, nodeBudget = 1800,
            alternatives = false, sliceBudgetMs = 1,
            squareAdmission = survey.hazard and function(square, previous)
                return shelterCorridorEdge(survey, previous, square)
            end or nil,
        })
    end
    local status, path, reason, _, _, used
    if house.job then status, path, reason, _, _, used = nav.resumePathSearch(house.job, quota) end
    if status == "pending" then return tonumber(used) or 0 end
    house.job = nil
    if status == "complete" and reason == nil and type(path) == "table" and #path >= 1
        and path[1] == survey.source then
        for index, candidate in ipairs(house.candidates) do
            if path[#path] == candidate.square then
                -- An invalidated goal may be exchanged for a different goal in
                -- the same house. A blocked group does not start eight jobs.
                table.remove(house.candidates, index)
                if #path <= 80 then
                    survey.proof = { path = path, index = 1, candidate = candidate, house = house }
                end
                house.ready = #house.candidates > 0
                return tonumber(used) or 0
            end
        end
    end
    house.ready = false
    return tonumber(used) or 0
end

local function pollShelterSurvey(survey, nav, perf, expired)
    if survey.proof then
        local valid = verifyShelterPath(survey, nav, expired)
        if valid then
            local proof = survey.proof
            return shelterResult(proof.house, proof.candidate, proof.path), nil, "complete"
        end
        if valid == false then survey.proof = nil end
        return nil, "shelter_proof_pending", "pending"
    end
    local selected
    for offset = 0, #survey.houses - 1 do
        local index = (survey.searchIndex + offset - 1) % #survey.houses + 1
        if survey.houses[index].ready then selected = index break end
    end
    local discovering = survey.houses[survey.discoveryIndex]
    if discovering and (survey.discoveryTurn or selected == nil) then
        survey.discoveryTurn = false
        return nil, "shelter_discovery_pending", "pending", scanShelterHouse(survey, discovering, expired)
    end
    if not selected then return nil, "shelter_no_loaded_path", "failed" end
    local quota, claim = 48, nil
    if perf and type(perf.claimUnits) == "function" then
        quota, claim = perf.claimUnits("navigation", quota, false, true)
    end
    survey.discoveryTurn = true
    if quota <= 0 then return nil, "shelter_search_pending", "pending" end
    -- Rotate between homes. One locked house cannot monopolize all search
    -- slices when a nearby alternate is reachable.
    survey.searchIndex = selected % #survey.houses + 1
    local used = pollShelterJob(survey, survey.houses[selected], nav, quota)
    if claim and type(perf.settleUnits) == "function" then perf.settleUnits(claim, used) end
    return nil, "shelter_search_pending", "pending", used
end

function Places.pollNearestLoadedShelter(actor, hazard, excluded, state)
    if type(state) ~= "table" then return nil, "shelter_area_unavailable", "failed" end
    local nav, perf = SC.Navigation, SC.Performance
    if not nav or type(nav.beginPathSearch) ~= "function" or type(nav.resumePathSearch) ~= "function"
        or type(nav._adjacentStepForWorkRoutes) ~= "function"
        or type(nav._passableEdgeForWorkRoutes) ~= "function"
        or (hazard ~= nil and (type(hazard) ~= "table" or type(hazard.x) ~= "number"
            or type(hazard.y) ~= "number" or type(hazard.radius) ~= "number"
            or hazard.x ~= hazard.x or hazard.y ~= hazard.y or hazard.radius ~= hazard.radius
            or hazard.x < 0 or hazard.x > 30000 or hazard.y < 0 or hazard.y > 30000
            or hazard.radius < 0 or hazard.radius > 32)) then
        state.survey = nil
        return nil, "shelter_area_unavailable", "failed"
    end
    local frame = perf and type(perf.frameId) == "function" and perf.frameId() or nil
    if frame ~= nil and state.lastFrame == frame then return nil, "shelter_frame_pending", "pending" end
    state.lastFrame = frame
    local clock = perf and perf.preciseNowMs
    local began = type(clock) == "function" and clock() or nil
    local function expired() return began ~= nil and clock() - began >= 1 end
    local current = readApproachInputs(actor)
    local shelter, reason, status, units
    if not current or not currentApproachSquare(current.cell, current.source) then
        reason, status = "shelter_area_unavailable", "failed"
    elseif sameShelterSurvey(state.survey, current, hazard, excluded) then
        shelter, reason, status, units = pollShelterSurvey(state.survey, nav, perf, expired)
    else
        state.survey, reason = beginShelterSurvey(current, hazard, excluded)
        status = state.survey and "pending" or "failed"
        if state.survey then reason = "shelter_discovery_pending" end
    end
    if status ~= "pending" then state.survey = nil end
    if began ~= nil and type(perf.record) == "function" then
        perf.record("expedition.shelter-survey", nil, clock() - began, units or 0, status == "pending")
    end
    return shelter, reason, status
end

local function seenInterior(place, grid, cell)
    if place.groundFloor ~= true then return false, false, {} end
    local bounds = place.bounds
    local width, height = bounds.x2 - bounds.x + 1,
        bounds.y2 - bounds.y + 1
    local step = math.max(1, math.ceil(math.sqrt(width * height / 256)))
    local anyLoaded, anySeen = false, false
    local names, nameSeen = {}, {}
    for x = bounds.x, bounds.x2, step do
        for y = bounds.y, bounds.y2, step do
            if matchingBuildingAt(grid, place, x, y) then
                local square, loaded = call(cell, "getGridSquare", x, y, 0)
                if loaded and square ~= nil then
                    anyLoaded = true
                    local room, roomOk = call(square, "getRoom")
                    if roomOk and room ~= nil then
                        local seen, seenOk = call(square, "isSeen", 0)
                        if seenOk and seen == true then
                            anySeen = true
                            local definition, defOk = call(square,
                                "getRoomDef")
                            if not defOk or definition == nil then
                                definition = select(1, call(room,
                                    "getRoomDef"))
                            end
                            local name, nameOk = call(definition, "getName")
                            name = nameOk and type(name) == "string"
                                and name:lower() or ""
                            if name ~= "" and #name <= 64
                                and not nameSeen[name] then
                                nameSeen[name] = true
                                names[#names + 1] = name
                            end
                        end
                    end
                end
            end
        end
    end
    table.sort(names)
    return anySeen, anyLoaded, names
end

-- Strict first knowledge gate for a later destination picker. Only ground
-- floors with a player-seen interior square can appear. Classify using only
-- those seen rooms. Return a UI-safe copy without raw room names.
function Places.knownNearby(x, y, radius, limit, offset)
    limit = tonumber(limit)
    offset = tonumber(offset) or 0
    if limit == nil or limit < 1 or limit > 32
        or limit ~= math.floor(limit) or offset < 0 or offset > 4096
        or offset ~= math.floor(offset) then
        return nil, "invalid_known_place_limit"
    end
    local candidates, reason = Places.nearby(x, y, radius, 4096, true)
    if candidates == nil then return nil, reason end
    local world = type(getWorld) == "function" and getWorld() or nil
    local grid, gridOk = call(world, "getMetaGrid")
    local cell, cellOk = call(world, "getCell")
    if not gridOk or not cellOk or grid == nil or cell == nil then
        return nil, "knowledge_world_unavailable"
    end
    local result, anyLoaded, total = {}, false, 0
    for _, place in ipairs(candidates) do
        local withinRange = validBounds(place) ~= nil
            and place.distanceSq <= radius * radius
        local known, loaded, seenNames
        if withinRange then
            known, loaded, seenNames = seenInterior(place, grid, cell)
            if SC.ExpeditionTargets and WorldMapVisited then
                known = SC.ExpeditionTargets.known(place.anchor)
                loaded = true
                if known then seenNames = place.rooms end
            end
            anyLoaded = anyLoaded or loaded
        end
        if known then
            total = total + 1
            if total > offset and #result < limit then
                addStreet(place)
                local observedKind, observedLabel = classify(seenNames)
                result[#result + 1] = {
                    id = place.id,
                    anchor = { x = place.anchor.x, y = place.anchor.y,
                        z = place.anchor.z },
                    bounds = { x = place.bounds.x, y = place.bounds.y,
                        x2 = place.bounds.x2, y2 = place.bounds.y2 },
                    kind = observedKind, label = observedLabel,
                    street = place.street,
                    streetDistance = place.streetDistance,
                    distance = place.distance,
                    groundFloor = true,
                    knowledge = "player_seen_interior",
                }
            end
        end
    end
    if total == 0 and not anyLoaded then
        return nil, "knowledge_area_unavailable"
    end
    return result, nil, total
end

-- The sandbox option selects the destination pool. The default deliberately
-- includes unvisited buildings, identified as map-derived candidates. Both
-- modes return bounded, UI-safe copies and exclude basement-only footprints.
function Places.targetableNearby(x, y, radius, limit, offset)
    if SC.Config and SC.Config.get("expeditionDestinationScope") == "known_only" then
        return Places.knownNearby(x, y, radius, limit, offset)
    end
    limit = tonumber(limit)
    offset = tonumber(offset) or 0
    if limit == nil or limit < 1 or limit > 32
        or limit ~= math.floor(limit) or offset < 0 or offset > 4096
        or offset ~= math.floor(offset) then
        return nil, "invalid_targetable_place_limit"
    end
    local candidates, reason = Places.nearby(x, y, radius, 4096, true)
    if candidates == nil then return nil, reason end
    local result, total = {}, 0
    for _, place in ipairs(candidates) do
        if place.groundFloor and validBounds(place) ~= nil
            and place.distanceSq <= radius * radius then
            total = total + 1
            if total > offset and #result < limit then
                addStreet(place)
                result[#result + 1] = {
                    id = place.id,
                    anchor = { x = place.anchor.x, y = place.anchor.y,
                        z = place.anchor.z },
                    bounds = { x = place.bounds.x, y = place.bounds.y,
                        x2 = place.bounds.x2, y2 = place.bounds.y2 },
                    kind = place.kind, label = place.label,
                    street = place.street,
                    streetDistance = place.streetDistance,
                    distance = place.distance,
                    groundFloor = true,
                    knowledge = "map_metadata_unconfirmed",
                }
            end
        end
    end
    return result, nil, total
end

-- Dispatch validates one stable footprint independently of UI pagination.
-- Street naming happens only for this selected place, not every page skipped.
function Places.targetableById(x, y, radius, id)
    if type(id) ~= "string" or #id < 1 or #id > 64 then
        return nil, "invalid_place_reference"
    end
    local candidates, reason = Places.nearby(x, y, radius, 4096, true)
    if candidates == nil then return nil, reason end
    for _, place in ipairs(candidates) do
        if place.id == id and place.groundFloor and validBounds(place) ~= nil
            and place.distanceSq <= radius * radius then
            local knowledge = "map_metadata_unconfirmed"
            if SC.Config and SC.Config.get("expeditionDestinationScope") == "known_only" then
                local world = type(getWorld) == "function" and getWorld() or nil
                local grid, gridOk = call(world, "getMetaGrid")
                local cell, cellOk = call(world, "getCell")
                if not gridOk or not cellOk or grid == nil or cell == nil then
                    return nil, "knowledge_world_unavailable"
                end
                local known, _, names = seenInterior(place, grid, cell)
                if SC.ExpeditionTargets and WorldMapVisited then
                    known = SC.ExpeditionTargets.known(place.anchor)
                    names = place.rooms
                end
                if not known then return nil, "place_no_longer_selectable" end
                place.kind, place.label = classify(names)
                knowledge = "player_seen_interior"
            end
            addStreet(place)
            return {
                id = place.id, anchor = place.anchor, bounds = place.bounds,
                kind = place.kind, label = place.label,
                street = place.street, streetDistance = place.streetDistance,
                distance = place.distance, groundFloor = true,
                knowledge = knowledge,
            }
        end
    end
    return nil, "place_no_longer_selectable"
end

return Places
