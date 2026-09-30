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

local function isOutsidePath(path, sourceRoom)
    local outside = sourceRoom == nil
    local sourceBuilding, buildingOk
    if sourceRoom ~= nil then
        sourceBuilding, buildingOk = call(sourceRoom, "getBuilding")
    end
    for _, square in ipairs(path) do
        local room, roomOk = call(square, "getRoom")
        if not roomOk then return false end
        if room == nil then
            outside = true
        elseif outside then
            return false
        elseif room ~= sourceRoom then
            local building, known = call(room, "getBuilding")
            if not buildingOk or sourceBuilding == nil or not known
                or building ~= sourceBuilding then return false end
        end
    end
    return outside
end

local function matchingBuildingAt(grid, place, x, y)
    local building, found = call(grid, "getBuildingAt", x, y, 0)
    if not found or building == nil then return false end
    local bx, bxOk = call(building, "getX")
    local by, byOk = call(building, "getY")
    local bx2, bx2Ok = call(building, "getX2")
    local by2, by2Ok = call(building, "getY2")
    return bxOk and byOk and bx2Ok and by2Ok
        and table.concat({ bx, by, bx2, by2 }, ":") == place.id
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

local function savedSite(siteId)
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
        or z ~= 0 or x < bounds.x or x > bounds.x2
        or y < bounds.y or y > bounds.y2 then return false end
    local world = type(getWorld) == "function" and getWorld() or nil
    local grid, ready = call(world, "getMetaGrid")
    return ready and grid ~= nil
        and matchingBuildingAt(grid, place, x, y) or false
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

local function addCandidate(candidates, grid, cell, place, x, y, side,
        sourceX, sourceY)
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
    local dx, dy = sourceX - x, sourceY - y
    candidates[#candidates + 1] = {
        x = x, y = y, z = 0, square = square, side = side,
        distanceSq = dx * dx + dy * dy,
    }
end

-- A path to an outdoor square beside the building is a site approach, not
-- proof that a door opens or that interior containers can be reached.
-- Recheck when the leader streams the site; barriers can change en route.
function Places.loadedApproach(place, actor)
    local bounds = validBounds(place)
    if bounds == nil then return nil, "invalid_place_reference" end
    if place.groundFloor ~= true then
        return nil, "place_without_ground_floor"
    end
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
        or SC.Navigation == nil or type(SC.Navigation.findPath) ~= "function"
        or SC.GameplayUtil == nil
        or type(SC.GameplayUtil.isSquareFree) ~= "function" then
        return nil, "approach_world_unavailable"
    end
    local sides = { west = {}, east = {}, north = {}, south = {} }
    for y = bounds.y, bounds.y2 do
        addCandidate(sides.west, grid, cell, place, bounds.x - 1, y,
            "west", sourceX, sourceY)
        addCandidate(sides.east, grid, cell, place, bounds.x2 + 1, y,
            "east", sourceX, sourceY)
    end
    for x = bounds.x, bounds.x2 do
        addCandidate(sides.north, grid, cell, place, x, bounds.y - 1,
            "north", sourceX, sourceY)
        addCandidate(sides.south, grid, cell, place, x, bounds.y2 + 1,
            "south", sourceX, sourceY)
    end
    local candidates = {}
    local sideOrder = { "west", "east", "north", "south" }
    for _, side in ipairs(sideOrder) do
        local items = sides[side]
        table.sort(items, function(a, b)
            if a.distanceSq ~= b.distanceSq then
                return a.distanceSq < b.distanceSq
            end
            if a.x ~= b.x then return a.x < b.x end
            return a.y < b.y
        end)
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
    if #candidates == 0 then return nil, "approach_exterior_unavailable" end
    table.sort(candidates, function(a, b)
        if a.distanceSq ~= b.distanceSq then
            return a.distanceSq < b.distanceSq
        end
        if a.x ~= b.x then return a.x < b.x end
        return a.y < b.y
    end)
    for _, candidate in ipairs(candidates) do
        local path
        if candidate.x == sourceX and candidate.y == sourceY then
            path = { source }
        else
            path = SC.Navigation.findPath(source, candidate.square,
                { actor = actor, nodeBudget = 1800 })
        end
        if path ~= nil and #path >= 1 and #path <= 180
            and isOutsidePath(path, sourceRoom) then
            return {
                x = candidate.x, y = candidate.y, z = 0,
                buildingId = place.id, side = candidate.side,
                pathNodes = #path, scope = "loaded_exterior_only",
            }
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

-- Emergency refuge must be an actual reachable interior square. A map house
-- label or an exterior doorstep alone is not shelter from a blocked road.
function Places.nearestLoadedShelter(actor, hazard)
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
        if place.kind == "residence" and place.groundFloor == true then
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
