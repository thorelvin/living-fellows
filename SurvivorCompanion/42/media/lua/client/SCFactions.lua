-- SPDX-License-Identifier: MIT

local SC = SurvivorCompanion
if not SC.Performance and type(require) == "function" then pcall(require, "SCPerformance") end
if not SC.StableValue and type(require) == "function" then pcall(require, "SCStableValue") end
if not SC.NativeList and type(require) == "function" then pcall(require, "SCNativeList") end
if not SC.Allegiance and type(require) == "function" then pcall(require, "SCAllegiance") end
SC.Factions = SC.Factions or {}

local Factions = SC.Factions
local SCHEMA = 2
local LEGACY_SCHEMA = 1
local groups = {}
local groupOrder = {}
local memberToGroup = {}
local sequence = 0
local lastWorldSpawnDay = -math.huge
local lastProductionCheckDay = -math.huge
local productionHouseSearch = nil
local banditHouseSearch = nil
local lastBanditSpawnDay = -math.huge
local lastBanditCheckDay = -math.huge
local spawnQueue = {}
local spawnTicket = nil
local spawnEntry = nil
local restored = false
local observedContainers = setmetatable({}, { __mode = "k" })
local recentPlayerAttacks = {}
local hitHookInstalled = false
local swingHookInstalled = false
local fallbackRandomSequence = 0

local lifecycleValues = {
    forming = true, fortifying = true, settled = true,
    alert = true, hostile = true, destroyed = true,
}

local standingValues = {
    Wary = true, Tolerated = true, Trusted = true, Hostile = true,
}

local archetypeProfiles = {
    barricaded_household = {
        social = true, trade = true, recruitment = true,
        patrol = false, permanentlyHostile = false,
    },
    bandit_camp = {
        social = false, trade = false, recruitment = false,
        patrol = true, permanentlyHostile = true,
    },
}

local requestKinds = { "food", "water", "medicine", "tools", "materials", "ammunition" }

local requestDefinitions = {
    food = {
        label = "Food supplies",
        required = { { category = "food", count = 6 } },
        reward = { { type = "Base.Battery", count = 2 }, { type = "Base.Lighter", count = 1 } },
    },
    water = {
        label = "Clean water",
        required = { { category = "water", count = 4 } },
        reward = { { type = "Base.NailsBox", count = 1 } },
    },
    medicine = {
        label = "Medical supplies",
        required = { { type = "Base.Bandage", count = 4 }, { type = "Base.Disinfectant", count = 1 } },
        reward = { { type = "Base.Hammer", count = 1 }, { type = "Base.NailsBox", count = 1 } },
    },
    tools = {
        label = "Tools",
        required = { { type = "Base.Saw", count = 1 }, { type = "Base.Screwdriver", count = 1 } },
        reward = { { type = "Base.CannedSardines", count = 3 } },
    },
    materials = {
        label = "Barricade materials",
        required = { { type = "Base.Plank", count = 4 }, { type = "Base.Nails", count = 8 } },
        reward = { { type = "Base.FirstAidKit", count = 1 } },
    },
    ammunition = {
        label = "Ammunition",
        required = { { type = "Base.Bullets9mmBox", count = 1 } },
        reward = { { type = "Base.CannedCornedBeef", count = 3 }, { type = "Base.WaterBottle", count = 1 } },
    },
}

local roles = { "leader", "watch", "builder" }

-- Grounded names that sound like survivor groups could have coined them in
-- rural Kentucky.  Pairing the pools yields enough unique names for every
-- persistent household allowed by the sandbox settings.
local factionLandmarks = {
    "Ashwood", "Blacktop", "Bluegrass", "Briar", "Cedar", "County Line",
    "Creekside", "Crossroads", "Depot", "Hilltop", "Ironwood", "Lantern",
    "Last Stop", "Old Mill", "Orchard", "Pine Ridge", "Quarry", "Rail Yard",
    "Red Oak", "Riverbend", "Sawmill", "Southbound", "Water Tower", "West Fork",
}

local factionCollectives = {
    "Circle", "Co-op", "Crew", "Guard", "Holdouts", "Household",
    "Neighbors", "Refuge", "Survivors", "Union", "Ward", "Watch",
}

local banditLandmarks = {
    "Ash Creek", "Blacktop", "Briar", "County Line", "Dead End",
    "Ironwood", "Quarry", "Rail Yard", "Red River", "West Fork",
}

local banditCollectives = {
    "Jackals", "Marauders", "Outlaws", "Raiders",
    "Rattlers", "Reavers", "Runners", "Wolves",
}

local streetLookup = {
    api = nil,
    bridge = nil,
    retryAt = 0,
}

local function U()
    return SC.GameplayUtil
end

local function nowMs()
    return U().nowMs()
end

local function worldAgeHours()
    if type(getGameTime) == "function" then
        local ok, gameTime = pcall(getGameTime)
        if ok and gameTime ~= nil then
            local hours, called = U().call(gameTime, "getWorldAgeHours")
            if called and tonumber(hours) then return tonumber(hours) end
        end
    end
    return nowMs() / 3600000
end

local function worldDay()
    return math.floor(worldAgeHours() / 24)
end

local function localPlayer()
    if type(getPlayer) ~= "function" then return nil end
    local ok, value = pcall(getPlayer)
    return ok and value or nil
end

local function random(maximum)
    maximum = math.max(1, math.floor(tonumber(maximum) or 1))
    if type(ZombRand) == "function" then
        local ok, value = pcall(ZombRand, maximum)
        if ok and tonumber(value) then return math.floor(tonumber(value)) end
    end
    fallbackRandomSequence = fallbackRandomSequence + 1
    local clockValue = type(os) == "table" and type(os.clock) == "function"
        and tonumber(os.clock()) or nil
    if clockValue ~= nil then return math.floor((clockValue * 1000000) % maximum) end
    return (fallbackRandomSequence * 1103515245 + 12345) % maximum
end

local function stableCopy(value, depth, budget)
    return SC.StableValue.copyStrict(value, {
        maxDepth = math.max(0, tonumber(depth) or 8),
        maxEntries = type(budget) == "table" and budget.count or 8192,
        path = "$.factions",
    })
end

local function appendBounded(list, value, maximum)
    list[#list + 1] = value
    while #list > maximum do table.remove(list, 1) end
end

local function invoke(object, methodName, ...)
    local value, called, b, c = U().call(object, methodName, ...)
    return called, value, b, c
end

local listSize = SC.NativeList.size
local listGet = SC.NativeList.get

local function trimmed(value)
    return tostring(value or ""):match("^%s*(.-)%s*$") or ""
end

local function isCoordinateFactionName(value)
    if type(value) ~= "string" then return false end
    return value:match("^%s*Household near%s+%-?%d+%.?%d*,%s*%-?%d+%.?%d*%s*$") ~= nil
end

local function occupiedFactionNames(source)
    local occupied = {}
    for _, group in pairs(type(source) == "table" and source or groups) do
        if type(group) == "table" and trimmed(group.name) ~= "" then
            occupied[group.name] = true
        end
    end
    return occupied
end

local function generatedFactionName(group, occupied)
    local anchor = type(group.house) == "table" and group.house.anchor or {}
    local seed = table.concat({
        tostring(group.id or "faction"), tostring(anchor.x or 0),
        tostring(anchor.y or 0), tostring(anchor.z or 0),
    }, ":")
    local landmarks = group.archetype == "bandit_camp" and banditLandmarks or factionLandmarks
    local collectives = group.archetype == "bandit_camp" and banditCollectives or factionCollectives
    local total = #landmarks * #collectives
    local first = U().stableHash(seed .. ":name") % total
    local stride = group.archetype == "bandit_camp" and 37 or 73
    for attempt = 0, total - 1 do
        local pair = (first + attempt * stride) % total
        local landmark = landmarks[(pair % #landmarks) + 1]
        local collective = collectives[(math.floor(pair / #landmarks)
            % #collectives) + 1]
        local candidate = "The " .. landmark .. " " .. collective
        if not occupied[candidate] then return candidate end
    end
    return "The " .. landmarks[(first % #landmarks) + 1] .. " "
        .. collectives[(math.floor(first / #landmarks)
            % #collectives) + 1] .. " " .. tostring(U().stableHash(seed) % 1000)
end

local function archetypeProfile(groupOrArchetype)
    local archetype = type(groupOrArchetype) == "table" and groupOrArchetype.archetype
        or groupOrArchetype
    return archetypeProfiles[archetype] or archetypeProfiles.barricaded_household
end

function Factions.supports(groupOrId, capability)
    local group = type(groupOrId) == "table" and groupOrId or groups[groupOrId]
    if not group or type(capability) ~= "string" then return false end
    return archetypeProfile(group)[capability] == true
end

function Factions.archetypeProfile(archetype)
    return stableCopy(archetypeProfile(archetype), 2)
end

local function ensureBanditState(group)
    if type(group) ~= "table" or group.archetype ~= "bandit_camp" then return nil end
    local state = type(group.bandit) == "table" and group.bandit or {}
    group.bandit = state
    state.schema = 1
    if state.threatTier ~= "mixed" and state.threatTier ~= "armed"
        and state.threatTier ~= "melee" then state.threatTier = "melee" end
    state.armed = state.armed == true
    if state.firearmKind ~= "pistol" and state.firearmKind ~= "shotgun" then
        state.firearmKind = nil
    end
    if not state.armed then state.firearmKind, state.firearmMemberKey = nil, nil end
    state.nextPatrolHour = math.max(0, tonumber(state.nextPatrolHour) or worldAgeHours() + 1)
    state.patrolSerial = math.max(0, math.floor(tonumber(state.patrolSerial) or 0))
    if state.engagement ~= "challenging" and state.engagement ~= "attacking" then
        state.engagement = "unaware"
    end
    if state.patrolMemberKey ~= nil then state.patrolMemberKey = tostring(state.patrolMemberKey) end
    -- Pre-schema prototypes stored process-relative millisecond clocks here.
    -- They are deliberately discarded because they are invalid after reload.
    state.attackedAt, state.challengeStartedAt, state.engagedAt = nil, nil, nil
    return state
end

local function ensureFactionIdentity(group, occupied)
    if type(group) ~= "table" then return false end
    occupied = type(occupied) == "table" and occupied or occupiedFactionNames()
    local currentName = trimmed(group.name)
    if currentName == "" or isCoordinateFactionName(currentName) then
        group.name = generatedFactionName(group, occupied)
    else
        group.name = currentName
    end
    occupied[group.name] = true

    if group.location == nil then group.location = {} end
    if type(group.location) == "table" and group.location.coordinates == nil
        and type(group.house) == "table" and type(group.house.anchor) == "table" then
        group.location.coordinates = {
            x = math.floor(tonumber(group.house.anchor.x) or 0),
            y = math.floor(tonumber(group.house.anchor.y) or 0),
            z = math.floor(tonumber(group.house.anchor.z) or 0),
        }
    end
    return true
end

local function streetDataApi()
    local current = nowMs()
    if streetLookup.api ~= nil then return streetLookup.api end
    if current < (tonumber(streetLookup.retryAt) or 0) then return nil end
    streetLookup.retryAt = current + 10000

    local mapApi, mapUI
    local existing = type(_G) == "table" and rawget(_G, "ISWorldMap_instance") or nil
    if existing ~= nil then
        local okay, value = pcall(function() return existing.mapAPI end)
        if okay then mapApi = value end
        mapUI = existing
        if mapApi == nil then
            local javaObject
            okay, javaObject = pcall(function() return existing.javaObject end)
            if okay and javaObject ~= nil then
                mapApi = select(1, U().call(javaObject, "getAPIv3"))
            end
        end
    end

    if mapApi == nil then
        local uiType = type(_G) == "table" and rawget(_G, "UIWorldMap") or nil
        if uiType ~= nil and type(uiType.new) == "function" then
            local owner = {}
            local created, javaObject = pcall(uiType.new, owner)
            if created and javaObject ~= nil then
                mapUI = { owner = owner, javaObject = javaObject }
                mapApi = select(1, U().call(javaObject, "getAPIv3"))
                streetLookup.bridge = mapUI
            end
        end
    end
    if mapApi == nil then return nil end

    local api, apiCalled = U().call(mapApi, "getStreetsAPI")
    if not apiCalled or api == nil then return nil end
    local count, countCalled = U().call(api, "getStreetDataCount")
    if not countCalled or (tonumber(count) or 0) <= 0 then
        local mapUtils = type(_G) == "table" and rawget(_G, "MapUtils") or nil
        if (type(mapUtils) ~= "table" or type(mapUtils.initDefaultStreetData) ~= "function")
            and type(require) == "function" then
            pcall(require, "ISUI/Maps/ISMapDefinitions")
            mapUtils = type(_G) == "table" and rawget(_G, "MapUtils") or nil
        end
        if mapUI ~= nil and type(mapUtils) == "table"
            and type(mapUtils.initDefaultStreetData) == "function" then
            pcall(mapUtils.initDefaultStreetData, mapUI)
            count, countCalled = U().call(api, "getStreetDataCount")
        end
    end
    if not countCalled or (tonumber(count) or 0) <= 0 then return nil end
    streetLookup.api = api
    return api
end

local function closestPointOnSegment(px, py, x1, y1, x2, y2)
    local dx, dy = x2 - x1, y2 - y1
    local lengthSq = dx * dx + dy * dy
    local factor = 0
    if lengthSq > 0 then
        factor = ((px - x1) * dx + (py - y1) * dy) / lengthSq
        factor = math.max(0, math.min(1, factor))
    end
    local x, y = x1 + factor * dx, y1 + factor * dy
    local offsetX, offsetY = px - x, py - y
    return offsetX * offsetX + offsetY * offsetY, x, y
end

local function streetLowerBoundSq(street, x, y)
    local minX, minXCalled = U().call(street, "getMinX")
    local minY, minYCalled = U().call(street, "getMinY")
    local maxX, maxXCalled = U().call(street, "getMaxX")
    local maxY, maxYCalled = U().call(street, "getMaxY")
    minX, minY, maxX, maxY = tonumber(minX), tonumber(minY), tonumber(maxX), tonumber(maxY)
    if not minXCalled or not minYCalled or not maxXCalled or not maxYCalled
        or minX == nil or minY == nil or maxX == nil or maxY == nil then return nil end
    local dx = x < minX and minX - x or x > maxX and x - maxX or 0
    local dy = y < minY and minY - y or y > maxY and y - maxY or 0
    return dx * dx + dy * dy
end

local function streetName(street)
    local name, called = U().call(street, "getTranslatedText")
    name = called and trimmed(name) or ""
    if name == "" then
        name, called = U().call(street, "getUntranslatedText")
        name = called and trimmed(name) or ""
    end
    return name
end

local function nearestStreetFromApi(api, x, y)
    x, y = tonumber(x), tonumber(y)
    if api == nil or x == nil or y == nil then return nil end
    local dataCount, dataCountCalled = U().call(api, "getStreetDataCount")
    if not dataCountCalled then return nil end
    local bestDistanceSq, bestName, bestX, bestY = math.huge, nil, nil, nil
    for dataIndex = 0, math.min(127, math.max(0, tonumber(dataCount) or 0) - 1) do
        local data, dataCalled = U().call(api, "getStreetDataByIndex", dataIndex)
        local streetCount, streetCountCalled = U().call(data, "getStreetCount")
        if dataCalled and streetCountCalled then
            for streetIndex = 0, math.min(65535,
                math.max(0, tonumber(streetCount) or 0) - 1) do
                local street, streetCalled = U().call(data, "getStreetByIndex", streetIndex)
                local name = streetCalled and streetName(street) or ""
                local lowerBound = name ~= "" and streetLowerBoundSq(street, x, y) or nil
                if name ~= "" and (lowerBound == nil or lowerBound <= bestDistanceSq) then
                    local pointCount, pointsCalled = U().call(street, "getNumPoints")
                    pointCount = pointsCalled and math.min(4096,
                        math.max(0, tonumber(pointCount) or 0)) or 0
                    local previousX, previousY
                    for pointIndex = 0, pointCount - 1 do
                        local pointX, xCalled = U().call(street, "getPointX", pointIndex)
                        local pointY, yCalled = U().call(street, "getPointY", pointIndex)
                        pointX, pointY = tonumber(pointX), tonumber(pointY)
                        if xCalled and yCalled and pointX ~= nil and pointY ~= nil then
                            local distanceSq, closestX, closestY
                            if previousX == nil then
                                local dx, dy = x - pointX, y - pointY
                                distanceSq, closestX, closestY = dx * dx + dy * dy, pointX, pointY
                            else
                                distanceSq, closestX, closestY = closestPointOnSegment(
                                    x, y, previousX, previousY, pointX, pointY)
                            end
                            if distanceSq < bestDistanceSq then
                                bestDistanceSq, bestName = distanceSq, name
                                bestX, bestY = closestX, closestY
                            end
                            previousX, previousY = pointX, pointY
                        end
                    end
                end
            end
        end
    end
    if bestName == nil then return nil end
    local function tenth(value)
        return math.floor(value * 10 + 0.5) / 10
    end
    return {
        name = bestName,
        distance = tenth(math.sqrt(bestDistanceSq)),
        x = tenth(bestX), y = tenth(bestY),
        source = "world_map_streets",
    }
end

local function ensureNearestStreet(group)
    if type(group) ~= "table" then return nil end
    ensureFactionIdentity(group)
    local location = group.location
    if type(location) ~= "table" then return nil end
    if type(location.nearestStreet) == "table" then return location.nearestStreet end
    if location.streetLookupComplete == true then return nil end
    local coordinates = location.coordinates
    if type(coordinates) ~= "table" then return nil end
    local api = streetDataApi()
    if api == nil then return nil end
    location.nearestStreet = nearestStreetFromApi(api, coordinates.x, coordinates.y)
    location.streetLookupComplete = true
    return location.nearestStreet
end

Factions._nearestStreetFromApiForTests = nearestStreetFromApi

local function compassDirection(dx, dy)
    local horizontal = math.abs(dx) >= 0.38 * math.max(0.001, math.abs(dy))
    local vertical = math.abs(dy) >= 0.38 * math.max(0.001, math.abs(dx))
    local northSouth = dy < 0 and "N" or "S"
    local eastWest = dx < 0 and "W" or "E"
    if horizontal and vertical then return northSouth .. eastWest end
    if horizontal then return eastWest end
    return northSouth
end

-- Returns a stable, player-readable location without inventing a house number.
-- Map street data is optional, so coordinates always remain the final fallback.
function Factions.describeLocation(position)
    if type(position) ~= "table" then return nil, "position_unavailable" end
    local x, y, z = tonumber(position.x), tonumber(position.y), tonumber(position.z) or 0
    if x == nil or y == nil then return nil, "position_unavailable" end
    local result = {
        x = math.floor(x), y = math.floor(y), z = math.floor(z),
        coordinates = math.floor(x) .. ", " .. math.floor(y) .. ", " .. math.floor(z),
    }
    local api = streetDataApi()
    local street = api and nearestStreetFromApi(api, x, y) or nil
    if street then
        result.nearestStreet = street
        result.direction = compassDirection(x - street.x, y - street.y)
        result.distance = math.max(0, math.floor((tonumber(street.distance) or 0) + 0.5))
        result.address = "House " .. tostring(result.distance) .. " tiles "
            .. result.direction .. " of " .. street.name
    else
        result.address = "House near " .. result.coordinates
    end
    return result
end

local function objectKind(object)
    if object == nil then return nil end
    if type(instanceof) == "function" then
        local ok, result = pcall(instanceof, object, "IsoWindow")
        if ok and result == true then return "window" end
        ok, result = pcall(instanceof, object, "IsoWindowFrame")
        if ok and result == true then return "window" end
        ok, result = pcall(instanceof, object, "IsoDoor")
        if ok and result == true then return "door" end
        ok, result = pcall(instanceof, object, "IsoThumpable")
        if ok and result == true then
            local doorOk, door = invoke(object, "isDoor")
            if doorOk and door == true then return "door" end
            local windowOk, window = invoke(object, "isWindow")
            if windowOk and window == true then return "window" end
        end
    end
    local _, oppositeOk = U().call(object, "getOppositeSquare")
    local _, allowedOk = U().call(object, "isBarricadeAllowed")
    if oppositeOk and allowedOk then
        local door, doorOk = U().call(object, "isDoor")
        return doorOk and door == true and "door" or "window"
    end
    return nil
end

local function buildingAt(square)
    local ok, building = invoke(square, "getBuilding")
    return ok and building or nil
end

local function boundsFor(building)
    if building == nil then return nil end
    local defOk, definition = invoke(building, "getDef")
    local xOk, x, yOk, y, x2Ok, x2, y2Ok, y2 = false, nil, false, nil, false, nil, false, nil
    if defOk and definition then
        xOk, x = invoke(definition, "getX")
        yOk, y = invoke(definition, "getY")
        x2Ok, x2 = invoke(definition, "getX2")
        y2Ok, y2 = invoke(definition, "getY2")
    end
    if not xOk or not yOk or not x2Ok or not y2Ok
        or not tonumber(x) or not tonumber(y) or not tonumber(x2) or not tonumber(y2) then
        x, y, x2, y2 = math.huge, math.huge, -math.huge, -math.huge
        local roomsOk, rooms = invoke(building, "getRooms")
        if (not roomsOk or rooms == nil) and definition ~= nil then
            roomsOk, rooms = invoke(definition, "getRooms")
        end
        if not roomsOk or rooms == nil then return nil end
        for index = 0, listSize(rooms) - 1 do
            local room = listGet(rooms, index)
            local roomDef, roomDefOk = U().call(room, "getRoomDef")
            if not roomDefOk or roomDef == nil then roomDef = room end
            local rxOk, rx = invoke(roomDef, "getX")
            local ryOk, ry = invoke(roomDef, "getY")
            local rx2Ok, rx2 = invoke(roomDef, "getX2")
            local ry2Ok, ry2 = invoke(roomDef, "getY2")
            if rxOk and ryOk and rx2Ok and ry2Ok and tonumber(rx) and tonumber(ry)
                and tonumber(rx2) and tonumber(ry2) then
                x, y = math.min(x, tonumber(rx)), math.min(y, tonumber(ry))
                x2, y2 = math.max(x2, tonumber(rx2)), math.max(y2, tonumber(ry2))
            end
        end
        if x == math.huge then return nil end
    end
    x, y, x2, y2 = math.floor(x), math.floor(y), math.floor(x2), math.floor(y2)
    if x2 < x then x, x2 = x2, x end
    if y2 < y then y, y2 = y2, y end
    if x2 - x > 40 or y2 - y > 40 or x2 == x or y2 == y then return nil end
    return { x1 = x, y1 = y, x2 = x2, y2 = y2, z = 0 }
end

local function sameBuilding(square, building)
    return square ~= nil and buildingAt(square) == building
end

local function squareSeen(square)
    local ok, seen = invoke(square, "isSeen", 0)
    if ok and seen == true then return true end
    local roomOk, room = invoke(square, "getRoom")
    if roomOk and room then
        local defOk, definition = invoke(room, "getRoomDef")
        if defOk and definition then
            local exploredOk, explored = invoke(definition, "isExplored")
            if exploredOk and explored == true then return true end
        end
    end
    return false
end

local function squareBurned(square)
    local ok, burned = invoke(square, "isBurntOut")
    if ok and burned == true then return true end
    ok, burned = invoke(square, "isBurned")
    return ok and burned == true
end

local function objectIndex(square, object)
    local ok, objects = invoke(square, "getObjects")
    if not ok or objects == nil then return nil end
    for index = 0, listSize(objects) - 1 do
        if listGet(objects, index) == object then return index end
    end
    return nil
end

local function openingExterior(object, square, building)
    local oppositeOk, opposite = invoke(object, "getOppositeSquare")
    if not oppositeOk then opposite = nil end
    local hereInside = sameBuilding(square, building)
    local thereInside = sameBuilding(opposite, building)
    if opposite == nil then return hereInside end
    return hereInside ~= thereInside
end

local questContainerPreference = {
    crate = 1, counter = 2, cabinet = 2, wardrobe = 3, dresser = 3,
    desk = 4, filingcabinet = 4, metal_shelves = 5, shelves = 5,
}

local function containerType(container)
    local value, called = U().call(container, "getType")
    return called and tostring(value or "") or ""
end

local function sortQuestContainers(choices)
    table.sort(choices, function(left, right)
        if left.preference ~= right.preference then return left.preference < right.preference end
        if left.z ~= right.z then return left.z < right.z end
        if left.x ~= right.x then return left.x < right.x end
        return left.y < right.y
    end)
    local selected = choices[1]
    if selected then selected.preference = nil end
    return selected
end

local function descriptorFor(building, bounds, allowSeen, collectQuestContainer)
    local openings, interior, seen, burned = {}, {}, false, false
    local questContainers = {}
    local budget = 0
    for z = 0, 2 do
        for x = bounds.x1, bounds.x2 do
            for y = bounds.y1, bounds.y2 do
                local square = U().gridSquare(x, y, z)
                if square ~= nil and sameBuilding(square, building) then
                    budget = budget + 1
                    if squareSeen(square) then seen = true end
                    if squareBurned(square) then burned = true end
                    if z == 0 and U().isSafeSpawnSquare(square) then
                        interior[#interior + 1] = { x = x, y = y, z = z }
                    end
                    local objectsOk, objects = invoke(square, "getObjects")
                    if objectsOk and objects ~= nil then
                        for index = 0, listSize(objects) - 1 do
                            local object = listGet(objects, index)
                            local kind = objectKind(object)
                            if kind and openingExterior(object, square, building) then
                                openings[#openings + 1] = {
                                    x = x, y = y, z = z,
                                    objectIndex = objectIndex(square, object) or index,
                                    kind = kind,
                                }
                            end
                            if collectQuestContainer then
                                local container, called = U().call(object, "getContainer")
                                if called and container ~= nil then
                                    local containerKind = string.lower(containerType(container))
                                    questContainers[#questContainers + 1] = {
                                        x = x, y = y, z = z,
                                        objectIndex = index, containerType = containerKind,
                                        preference = questContainerPreference[containerKind] or 20,
                                    }
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    if burned then return nil, "house_burned" end
    if not allowSeen and seen then return nil, "house_seen" end
    if #interior == 0 then return nil, "house_has_no_ground_floor" end
    if #openings == 0 then return nil, "house_has_no_exterior_openings" end
    table.sort(openings, function(a, b)
        if a.kind ~= b.kind then return a.kind == "door" end
        if a.x ~= b.x then return a.x < b.x end
        return a.y < b.y
    end)
    table.sort(interior, function(a, b)
        local ac = math.abs(a.x - (bounds.x1 + bounds.x2) / 2)
            + math.abs(a.y - (bounds.y1 + bounds.y2) / 2)
        local bc = math.abs(b.x - (bounds.x1 + bounds.x2) / 2)
            + math.abs(b.y - (bounds.y1 + bounds.y2) / 2)
        return ac < bc
    end)
    local anchor = interior[1]
    local descriptor = {
        id = table.concat({ bounds.x1, bounds.y1, bounds.x2, bounds.y2 }, ":"),
        bounds = bounds,
        anchor = { x = anchor.x, y = anchor.y, z = anchor.z },
        interior = interior,
        openings = openings,
        primaryEntry = openings[1],
        squareCount = budget,
    }
    if collectQuestContainer then
        descriptor.questContainer = sortQuestContainers(questContainers)
    end
    return descriptor
end

local function distanceSqPosition(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return math.huge end
    local dx, dy = (tonumber(a.x) or 0) - (tonumber(b.x) or 0),
        (tonumber(a.y) or 0) - (tonumber(b.y) or 0)
    return dx * dx + dy * dy
end

local function conflictsWithExisting(house)
    local minimum = tonumber(SC.Config.get("factionMinHouseDistance")) or 300
    for _, id in ipairs(groupOrder) do
        local group = groups[id]
        if group and group.lifecycle ~= "destroyed" and group.house
            and distanceSqPosition(group.house.anchor, house.anchor) < minimum * minimum then
            return true
        end
    end
    return false
end

local function playerBuilding(player)
    local square = U().squareOf(player)
    return buildingAt(square)
end

local function overlapsPlayerBase(bounds)
    if not SC.BaseLife or type(SC.BaseLife.active) ~= "function" then return false end
    local ok, base = pcall(SC.BaseLife.active)
    if not ok or type(base) ~= "table" then return false end
    local core = type(base.core) == "table" and base.core or nil
    if not core then return false end
    local radius = tonumber(base.radius) or tonumber(SC.Config.get("baseDefaultAreaRadius")) or 6
    return core.x + radius >= bounds.x1 and core.x - radius <= bounds.x2
        and core.y + radius >= bounds.y1 and core.y - radius <= bounds.y2
end

local function safehouseAt(anchor)
    local safeHouse = type(_G) == "table" and rawget(_G, "SafeHouse") or nil
    if safeHouse == nil then return false end
    local method = safeHouse.getSafehouseList
    if type(method) ~= "function" then return false end
    local ok, list = pcall(method)
    if not ok or list == nil then return false end
    for index = 0, listSize(list) - 1 do
        local house = listGet(list, index)
        local containsOk, contains = invoke(house, "containsLocation", anchor.x, anchor.y)
        if containsOk and contains == true then return true end
    end
    return false
end

local function exactHouseClaimed(house)
    for _, id in ipairs(groupOrder) do
        local group = groups[id]
        if group and group.lifecycle ~= "destroyed"
            and group.house and group.house.id == house.id then return true end
    end
    return false
end

local function replacementQuestContainer(bounds, expectedBuilding)
    if type(bounds) ~= "table" or expectedBuilding == nil then return nil, nil end
    local choices = {}
    for z = 0, 2 do
        for x = tonumber(bounds.x1) or 0, tonumber(bounds.x2) or -1 do
            for y = tonumber(bounds.y1) or 0, tonumber(bounds.y2) or -1 do
                local square = U().gridSquare(x, y, z)
                if sameBuilding(square, expectedBuilding) then
                    U().squareObjects(square, function(object, index)
                        local container, called = U().call(object, "getContainer")
                        if called and container ~= nil then
                            local kind = string.lower(containerType(container))
                            choices[#choices + 1] = {
                                x = x, y = y, z = z, objectIndex = index,
                                containerType = kind,
                                preference = questContainerPreference[kind] or 20,
                                value = container,
                            }
                        end
                    end, 64)
                end
            end
        end
    end
    local selected = sortQuestContainers(choices)
    if selected == nil then return nil, nil end
    local container = selected.value
    selected.value = nil
    return container, selected
end

function Factions.resolveQuestContainer(locator, bounds, anchor)
    if type(locator) ~= "table" then return nil, "container_locator_unavailable" end
    local square = U().gridSquare(locator.x, locator.y, locator.z or 0)
    if not square then return nil, "container_square_unloaded" end
    local selected
    U().squareObjects(square, function(object, index)
        if selected ~= nil then return end
        local container, called = U().call(object, "getContainer")
        if called and container ~= nil then
            local exactIndex = tonumber(locator.objectIndex)
            local sameType = locator.containerType == nil
                or string.lower(containerType(container)) == string.lower(tostring(locator.containerType))
            if (exactIndex ~= nil and index == exactIndex and sameType)
                or (exactIndex == nil and sameType) then
                selected = container
            end
        end
    end, 64)
    if selected == nil and locator.containerType ~= nil then
        U().squareObjects(square, function(object)
            if selected ~= nil then return end
            local container, called = U().call(object, "getContainer")
            if called and container ~= nil and string.lower(containerType(container))
                == string.lower(tostring(locator.containerType)) then selected = container end
        end, 64)
    end
    if selected ~= nil then return selected, nil, locator end
    local anchorSquare = type(anchor) == "table"
        and U().gridSquare(anchor.x, anchor.y, anchor.z or 0) or nil
    local expectedBuilding = buildingAt(anchorSquare) or buildingAt(square)
    local replacement, replacementLocator = replacementQuestContainer(bounds, expectedBuilding)
    if replacement ~= nil then
        return replacement, "quest_container_relocated", replacementLocator
    end
    return nil, "quest_container_missing"
end

local function candidateAt(square, player, allowSeen, options)
    options = type(options) == "table" and options or {}
    local building = buildingAt(square)
    if building == nil or building == playerBuilding(player) then return nil, "not_a_candidate_house" end
    local bounds = boundsFor(building)
    if bounds == nil then return nil, "house_bounds_unavailable" end
    if overlapsPlayerBase(bounds) then return nil, "player_base_house" end
    local descriptor, reason = descriptorFor(building, bounds, allowSeen,
        options.purpose == "quest")
    if descriptor == nil then return nil, reason end
    if safehouseAt(descriptor.anchor) then return nil, "safehouse_reserved" end
    if options.purpose == "quest" then
        if exactHouseClaimed(descriptor) then
            return nil, "house_claimed_by_faction"
        end
        if descriptor.questContainer == nil then return nil, "house_has_no_quest_container" end
    elseif conflictsWithExisting(descriptor) then return nil, "house_too_close_to_faction" end
    return descriptor
end

local function newHouseSearch(player, options)
    options = type(options) == "table" and options or {}
    if player == nil then return nil, "player_unavailable" end
    local px, py, pz
    if type(options.origin) == "table" then
        px, py, pz = tonumber(options.origin.x), tonumber(options.origin.y),
            tonumber(options.origin.z) or 0
    else
        px, py, pz = U().position(player)
    end
    if px == nil then return nil, "player_position_unavailable" end
    local minimum = tonumber(options.minimumDistance)
        or tonumber(SC.Config.get("factionSpawnMinDistance")) or 35
    local maximum = tonumber(options.maximumDistance)
        or tonumber(SC.Config.get("factionSpawnMaxDistance")) or 90
    local budget = tonumber(options.sampleBudget)
        or tonumber(SC.Config.get("factionHouseSampleBudget")) or 96
    local allowSeen = options.allowSeen == true
    return {
        player = player,
        px = px, py = py, pz = pz or 0,
        minimum = minimum, maximum = maximum, budget = budget,
        allowSeen = allowSeen,
        purpose = options.purpose,
        sourceFactionId = options.sourceFactionId,
        attempt = 1,
        visited = {},
        best = nil,
        bestDistance = math.huge,
    }
end

local function resumeHouseSearch(job, quota)
    if type(job) ~= "table" then return "failed", nil, "invalid_house_search", 0 end
    local processed = 0
    quota = math.max(1, math.floor(tonumber(quota) or job.budget or 1))
    while job.attempt <= job.budget and processed < quota do
        local attempt = job.attempt
        job.attempt = job.attempt + 1
        processed = processed + 1
        local angle = (attempt * 2.399963229728653) + random(1000) / 1000
        local distance = job.minimum
            + ((attempt - 1) % math.max(1, job.maximum - job.minimum + 1))
        local x = math.floor(job.px + math.cos(angle) * distance)
        local y = math.floor(job.py + math.sin(angle) * distance)
        local square = U().gridSquare(x, y, job.pz)
        local building = buildingAt(square)
        if building ~= nil and not job.visited[building] then
            job.visited[building] = true
            local house = candidateAt(square, job.player, job.allowSeen, job)
            if house then
                local actual = math.sqrt(distanceSqPosition(
                    house.anchor, { x = job.px, y = job.py }))
                if actual >= job.minimum and actual <= job.maximum
                    and actual < job.bestDistance then
                    job.best, job.bestDistance = house, actual
                end
            end
        end
    end
    if job.attempt <= job.budget then return "pending", nil, "house_searching", processed end
    if job.best then return "complete", job.best, nil, processed end
    return "failed", nil, "no_valid_loaded_house", processed
end

function Factions.findHouse(player, options)
    local job, reason = newHouseSearch(player, options)
    if not job then return nil, reason end
    local _, house, searchReason = resumeHouseSearch(job, job.budget)
    return house, searchReason
end

function Factions.pollHouseSearch(player, options, job)
    local reason
    if type(job) ~= "table" then
        job, reason = newHouseSearch(player, options)
        if not job then return "failed", nil, reason, nil end
    end
    local requested = math.max(0, job.budget - job.attempt + 1)
    local granted = requested
    if SC.Performance and type(SC.Performance.claimUnits) == "function" then
        granted = SC.Performance.claimUnits("factionSamples", requested, false)
    end
    if granted <= 0 then
        if SC.Performance and type(SC.Performance.markYield) == "function" then
            SC.Performance.markYield("faction.house_search", nil, 0)
        end
        return "pending", nil, "house_search_deferred", job
    end
    local startedAt = nowMs()
    local status, house, searchReason, processed = resumeHouseSearch(job, granted)
    if SC.Performance and type(SC.Performance.record) == "function" then
        SC.Performance.record("faction.house_search", nil,
            nowMs() - startedAt, processed or 0, false)
    end
    if status == "pending" and SC.Performance and type(SC.Performance.markYield) == "function" then
        SC.Performance.markYield("faction.house_search", nil, processed or 0)
    end
    return status, house, searchReason, status == "pending" and job or nil
end

local function nextGroupId(archetype)
    sequence = sequence + 1
    local stamp = math.floor(worldAgeHours() * 1000)
    local kind = archetype == "bandit_camp" and "bandit" or "household"
    return "faction-" .. kind .. "-" .. tostring(stamp) .. "-" .. tostring(sequence)
end

local function standingForReputation(reputation, permanentHostility)
    if permanentHostility or reputation <= -60 then return "Hostile" end
    if reputation >= 40 then return "Trusted" end
    if reputation >= 0 then return "Tolerated" end
    return "Wary"
end

local function buildJobs(house)
    local jobs = {}
    for index, opening in ipairs(house.openings or {}) do
        local secondaryDoor = opening.kind ~= "door"
            or house.primaryEntry == nil
            or opening.x ~= house.primaryEntry.x or opening.y ~= house.primaryEntry.y
                or opening.objectIndex ~= house.primaryEntry.objectIndex
        if opening.kind == "window" or secondaryDoor then
            jobs[#jobs + 1] = {
                id = house.id .. ":opening:" .. tostring(index) .. ":first",
                kind = "barricade", phase = "first", targetPlanks =
                    tonumber(SC.Config.get("factionBarricadeFirstPassPlanks")) or 2,
                target = stableCopy(opening, 2), status = "open", attempts = 0,
            }
        end
    end
    for index, opening in ipairs(house.openings or {}) do
        local secondaryDoor = opening.kind ~= "door"
            or house.primaryEntry == nil
            or opening.x ~= house.primaryEntry.x or opening.y ~= house.primaryEntry.y
                or opening.objectIndex ~= house.primaryEntry.objectIndex
        if opening.kind == "window" or secondaryDoor then
            jobs[#jobs + 1] = {
                id = house.id .. ":opening:" .. tostring(index) .. ":final",
                kind = "barricade", phase = "final", targetPlanks =
                    tonumber(SC.Config.get("factionBarricadeFinalPlanks")) or 4,
                target = stableCopy(opening, 2), status = "open", attempts = 0,
            }
        end
    end
    return jobs
end

local function makeRequest(group)
    local kind = group.shortageKind
    if not requestDefinitions[kind] then
        local index = ((sequence + #group.members) % #requestKinds) + 1
        kind = requestKinds[index]
    end
    local definition = requestDefinitions[kind]
    local required = stableCopy(definition.required, 3)
    if kind == "materials" and type(group.materialNeed) == "table" then
        required = {
            { type = "Base.Plank", count = math.max(4,
                math.floor(tonumber(group.materialNeed.planks) or 4)) },
            { type = "Base.Nails", count = math.max(8,
                math.floor(tonumber(group.materialNeed.nails) or 8)) },
        }
    end
    return {
        kind = kind,
        label = definition.label,
        required = required,
        reward = stableCopy(definition.reward, 3),
        status = "available",
        rewardReserved = true,
        createdDay = worldDay(),
    }
end

local function banditTierForDay(day, forced)
    if forced == "armed" then return "armed", true end
    if forced == "melee" then return "melee", false end
    day = math.max(0, math.floor(tonumber(day) or worldDay()))
    if day < 14 then return "melee", false end
    if day < 30 then return "mixed", random(100) < 20 end
    return "armed", random(100) < 40
end

Factions._banditTierForDayForTests = banditTierForDay

local banditMeleeWeapons = {
    "Base.Crowbar", "Base.BaseballBat", "Base.HandAxe", "Base.HuntingKnife",
}

local function addGear(actor, role, group)
    local inventory, inventoryOk = U().call(actor, "getInventory")
    if not inventoryOk or inventory == nil then return false, "inventory_unavailable" end
    local required = {}
    if group and group.archetype == "bandit_camp" then
        local memberIndex = 1
        for index, member in ipairs(group.members or {}) do
            if member.role == role then memberIndex = index break end
        end
        required[#required + 1] = banditMeleeWeapons[
            (U().stableHash(group.id .. ":" .. tostring(memberIndex)) % #banditMeleeWeapons) + 1]
        required[#required + 1] = "Base.WaterBottle"
        required[#required + 1] = "Base.Bandage"
        required[#required + 1] = "Base.CannedSardines"
        if group.bandit and group.bandit.firearmMemberKey
            and group.bandit.firearmMemberKey == "member-" .. tostring(memberIndex) then
            if group.bandit.firearmKind == "shotgun" then
                required[#required + 1] = "Base.DoubleBarrelShotgun"
                for _ = 1, 4 do required[#required + 1] = "Base.ShotgunShells" end
            else
                required[#required + 1] = "Base.Pistol"
                for _ = 1, 15 do required[#required + 1] = "Base.Bullets9mm" end
            end
        end
    else
        required[#required + 1] = "Base.Hammer"
    end
    local materialShortage = type(group) == "table" and group.shortageKind == "materials"
    local planks = materialShortage and 1
        or math.max(4, math.floor(tonumber(group and group.materialsPerMemberPlanks) or 4))
    local nails = materialShortage and 2
        or math.max(8, math.floor(tonumber(group and group.materialsPerMemberNails) or 8))
    if not group or group.archetype ~= "bandit_camp" then
        for _ = 1, planks do required[#required + 1] = "Base.Plank" end
        for _ = 1, nails do required[#required + 1] = "Base.Nails" end
        if role == "watch" then required[#required + 1] = "Base.BaseballBat"
        elseif role == "leader" then required[#required + 1] = "Base.KitchenKnife"
        else required[#required + 1] = "Base.HandAxe" end
        if role == "leader" and group and group.shortageKind == "ammunition" then
            required[#required + 1] = "Base.Pistol"
        end
    end
    -- Build 42's randomized book entries returned nil from
    -- ItemContainer:AddItem in a real sandbox.  A notebook is concrete
    -- literature, needs no OnCreate randomization, and fits a leader's gear.
    if not group or group.archetype ~= "bandit_camp" then
        if role == "leader" then required[#required + 1] = "Base.Notebook" end
        if not group or group.shortageKind ~= "water" then required[#required + 1] = "Base.WaterBottle" end
        if not group or group.shortageKind ~= "food" then required[#required + 1] = "Base.CannedSardines" end
        if not group or group.shortageKind ~= "medicine" then required[#required + 1] = "Base.Bandage" end
    end
    -- A single item type that Build 42 renamed or that a mod removed (seen in a
    -- real save: a literature template would not instantiate) must not abort the whole faction
    -- member's initialization. Add what is available, and record the rest so the
    -- member still spawns instead of the household coming up short.
    local missing
    local function tryAdd(itemType)
        local _, added = invoke(inventory, "AddItem", itemType)
        if added == nil then
            missing = missing or {}
            missing[#missing + 1] = tostring(itemType)
        end
    end
    for _, itemType in ipairs(required) do tryAdd(itemType) end
    if role == "leader" and type(group) == "table" and group.archetype ~= "bandit_camp"
        and type(group.request) == "table" then
        for _, reward in ipairs(group.request.reward or {}) do
            for _ = 1, math.max(0, math.floor(tonumber(reward.count) or 0)) do
                tryAdd(reward.type)
            end
        end
    end
    if missing and SC.Diagnostics and type(SC.Diagnostics.report) == "function" then
        SC.Diagnostics.report("faction", tostring(U().idOf(actor)),
            "faction member gear items unavailable", table.concat(missing, ","))
    end
    return true
end
-- Test seam: a member's gear-add must tolerate an item that cannot instantiate.
Factions._addGearForTests = addGear

local function profileFor(group, member, snapshot)
    local identity = snapshot and snapshot.identity or member.identity
    local profile = {
        id = snapshot and snapshot.id or member.actorId,
        recruited = false,
        restored = snapshot ~= nil,
        identity = stableCopy(identity, 3),
        state = snapshot or {
            order = {
                current = "faction_duty", scavenge = false,
                movementMode = group.archetype == "bandit_camp" and "jog" or "walk",
                combatStance = group.archetype == "bandit_camp" and "aggressive" or "defensive",
                combatDoctrine = group.archetype == "bandit_camp" and "weapons_free"
                    or "close_defense", weaponPriority = "best",
                workMode = "build",
            },
        },
    }
    profile.initialize = function(actor, recordInput)
        recordInput.factionId = group.id
        recordInput.factionRole = member.role
        recordInput.factionLeader = member.role == "leader"
        if not snapshot then
            local okay, reason = addGear(actor, member.role, group)
            if not okay then return false, reason end
        end
        local data, called = U().call(actor, "getModData")
        if called and type(data) == "table" then
            data.SC_FactionId = group.id
            data.SC_FactionRole = member.role
        end
        return true
    end
    return profile
end

local function spawnPositionKey(position)
    if type(position) ~= "table" or position.x == nil or position.y == nil then return nil end
    return table.concat({ tostring(math.floor(position.x)), tostring(math.floor(position.y)),
        tostring(math.floor(position.z or 0)) }, ":")
end

local function reservedSpawnPositions(group, excludeEntry)
    local reserved = {}
    local function reserveEntry(entry)
        if entry ~= nil and entry ~= excludeEntry and entry.groupId == group.id then
            local key = spawnPositionKey(entry.square)
            if key then reserved[key] = true end
        end
    end
    reserveEntry(spawnEntry)
    for _, entry in ipairs(spawnQueue) do reserveEntry(entry) end
    for _, member in ipairs(group.members or {}) do
        if member.actorId ~= nil and member.away == nil and member.departed ~= true
            and SC.Registry and type(SC.Registry.byId) == "function" then
            local record = SC.Registry.byId(member.actorId)
            local x, y, z
            if record and record.actor then x, y, z = U().position(record.actor) end
            local key = x ~= nil and spawnPositionKey({ x = x, y = y, z = z }) or nil
            if key then reserved[key] = true end
        end
    end
    return reserved
end

local function chooseMemberSquare(group, memberIndex, excludeEntry, offset)
    local interior = group and group.house and group.house.interior or {}
    if #interior == 0 then return nil, nil, "house_has_no_safe_spawn_square" end
    local reserved = reservedSpawnPositions(group, excludeEntry)
    local start = ((math.max(1, tonumber(memberIndex) or 1) - 1
        + math.max(0, tonumber(offset) or 0)) % #interior) + 1
    for step = 0, #interior - 1 do
        local position = interior[((start + step - 1) % #interior) + 1]
        local key = spawnPositionKey(position)
        if key and not reserved[key] then
            local square = U().gridSquare(position.x, position.y, position.z or 0)
            local safe = U().isSafeSpawnSquare(square)
            if safe then return square, position, "safe" end
        end
    end
    return nil, nil, "no_unique_safe_member_square"
end

local function queueMemberSpawn(group, member, square, snapshot, debugCreated)
    local safe, safeReason = U().isSafeSpawnSquare(square)
    if not safe then return false, "member_square_" .. tostring(safeReason) end
    local x, y, z = U().position(square)
    if x == nil or y == nil then return false, "member_square_unavailable" end
    local memberIndex = 1
    for index, candidate in ipairs(group.members or {}) do
        if candidate == member or candidate.key == member.key then memberIndex = index break end
    end
    member.spawnQueued = true
    spawnQueue[#spawnQueue + 1] = {
        groupId = group.id,
        memberKey = member.key,
        -- Never retain an IsoGridSquare across streaming or save transitions.
        -- Resolve a fresh native square immediately before beginning the spawn.
        square = { x = math.floor(x), y = math.floor(y), z = math.floor(z or 0) },
        snapshot = snapshot,
        debugCreated = debugCreated == true,
        memberIndex = memberIndex,
        attempts = 0,
    }
    return true, "member_spawn_queued"
end

local function advanceSpawnSquare(entry, group)
    local _, position = chooseMemberSquare(group, entry.memberIndex, entry, entry.attempts)
    if position == nil then return false end
    entry.square = { x = position.x, y = position.y, z = position.z or 0 }
    return true
end

local function rollbackGroupCreation(group)
    for index = #spawnQueue, 1, -1 do
        if spawnQueue[index].groupId == group.id then table.remove(spawnQueue, index) end
    end
    for _, member in ipairs(group.members or {}) do member.spawnQueued = false end
    groups[group.id] = nil
    for index = #groupOrder, 1, -1 do
        if groupOrder[index] == group.id then table.remove(groupOrder, index) break end
    end
    if SC.FactionWorld and type(SC.FactionWorld.onGroupRemoved) == "function" then
        SC.FactionWorld.onGroupRemoved(group.id)
    end
end

local function createGroup(house, size, debugCreated, archetype, loadoutOverride)
    archetype = archetypeProfiles[archetype] and archetype or "barricaded_household"
    size = math.max(tonumber(SC.Config.get("factionMemberMin")) or 1,
        math.min(tonumber(SC.Config.get("factionMemberMax")) or 3, math.floor(tonumber(size) or 1)))
    local active = SC.Registry and type(SC.Registry.living) == "function"
        and #SC.Registry.living() or 0
    local stored = SC.Vehicle and type(SC.Vehicle.storedCount) == "function"
        and SC.Vehicle.storedCount() or 0
    if active + stored + size > (tonumber(SC.Config.get("maxCompanions")) or 16) then
        return nil, "native_actor_capacity_reached"
    end
    local profile = archetypeProfile(archetype)
    local group = {
        id = nextGroupId(archetype), archetype = archetype,
        lifecycle = "forming", standing = profile.permanentlyHostile and "Hostile" or "Wary",
        reputation = profile.permanentlyHostile and -100 or -20,
        discovered = debugCreated == true, debugCreated = debugCreated == true,
        createdDay = worldDay(), lastInteractionDay = worldDay(),
        permanentHostility = profile.permanentlyHostile == true, barterUnlocked = false,
        shortageKind = requestKinds[((sequence + size) % #requestKinds) + 1],
        house = stableCopy(house, 5, { count = 4096 }),
        members = {}, jobs = buildJobs(house), offenses = {}, history = {},
    }
    if archetype == "bandit_camp" then
        local tier, armed = banditTierForDay(worldDay(), loadoutOverride)
        group.bandit = {
            schema = 1, threatTier = tier, armed = armed == true,
            firearmKind = armed and (random(4) == 0 and "shotgun" or "pistol") or nil,
            nextPatrolHour = worldAgeHours() + 1, patrolSerial = 0,
            engagement = "unaware",
        }
        if armed then group.bandit.firearmMemberKey = "member-1" end
    end
    ensureFactionIdentity(group)
    local finalJobs = 0
    for _, job in ipairs(group.jobs) do
        if job.phase == "final" then finalJobs = finalJobs + 1 end
    end
    local totalPlanks = finalJobs
        * (tonumber(SC.Config.get("factionBarricadeFinalPlanks")) or 4)
    local seededPerMember = group.shortageKind == "materials" and 1
        or math.max(4, math.ceil(totalPlanks / size))
    group.materialsPerMemberPlanks = seededPerMember
    group.materialsPerMemberNails = seededPerMember * 2
    if group.shortageKind == "materials" then
        group.materialNeed = {
            planks = math.max(4, totalPlanks - seededPerMember * size),
            nails = math.max(8, totalPlanks * 2 - seededPerMember * size * 2),
        }
    end
    for index = 1, size do
        local identity = SC.Spawn and type(SC.Spawn.generateIdentity) == "function"
            and SC.Spawn.generateIdentity() or {
                forename = "Fellow", surname = tostring(index), gender = "male", outfit = "Survivalist",
            }
        group.members[#group.members + 1] = {
            key = "member-" .. tostring(index), role = roles[index] or "resident",
            identity = stableCopy(identity, 3), actorId = nil,
            alive = true, hibernated = false, snapshot = nil,
        }
    end
    group.request = makeRequest(group)
    if SC.FactionLife and type(SC.FactionLife.initialize) == "function" then
        SC.FactionLife.initialize(group)
    end
    if SC.FactionContracts and type(SC.FactionContracts.initialize) == "function" then
        SC.FactionContracts.initialize(group)
    end
    if SC.FactionRecruitment and type(SC.FactionRecruitment.initialize) == "function" then
        SC.FactionRecruitment.initialize(group)
    end
    groups[group.id] = group
    groupOrder[#groupOrder + 1] = group.id
    if SC.FactionWorld and type(SC.FactionWorld.onGroupAdded) == "function" then
        SC.FactionWorld.onGroupAdded(group)
    end
    for index, member in ipairs(group.members) do
        local square, _, squareReason = chooseMemberSquare(group, index)
        if square == nil then
            rollbackGroupCreation(group)
            return nil, squareReason or "house_member_square_unloaded"
        end
        local queued, queueReason = queueMemberSpawn(group, member, square, nil, debugCreated)
        if not queued then
            rollbackGroupCreation(group)
            return nil, queueReason
        end
    end
    group.lifecycle = "fortifying"
    return group
end

local function hasOpenJobs(group)
    for _, job in ipairs(group.jobs or {}) do
        if job.status ~= "completed" and job.status ~= "cancelled" then return true end
    end
    return false
end

local function beginNextSpawn()
    if spawnTicket ~= nil or #spawnQueue == 0 then return false, "spawn_queue_idle" end
    local entry = table.remove(spawnQueue, 1)
    local group = groups[entry.groupId]
    if group == nil or group.lifecycle == "destroyed" then return false, "group_unavailable" end
    local member
    for _, candidate in ipairs(group.members or {}) do
        if candidate.key == entry.memberKey then member = candidate break end
    end
    if member == nil or member.alive == false or member.away ~= nil or member.departed == true then
        if member then member.spawnQueued, member.waking = false, false end
        return false, "member_unavailable"
    end
    local square = entry.square
    if type(square) == "table" and square.x ~= nil then
        square = U().gridSquare(square.x, square.y, square.z or 0)
    end
    if square == nil then
        -- Streaming is temporary. Release the queue claim so lifecyclePulse can
        -- retry once the household is loaded instead of losing this member.
        member.spawnQueued = false
        member.waking = false
        if entry.snapshot then
            member.hibernated = true
            member.snapshot = entry.snapshot
        end
        return false, "member_square_unloaded"
    end
    local profile = profileFor(group, member, entry.snapshot)
    local ticket, reason = SC.Actor.beginSpawn(square, profile)
    if ticket == nil then
        member.spawnFailure = tostring(reason)
        entry.attempts = (entry.attempts or 0) + 1
        if entry.attempts < 3 then
            if advanceSpawnSquare(entry, group) then
                spawnQueue[#spawnQueue + 1] = entry
            else
                member.spawnQueued, member.waking = false, false
                member.spawnRetryAt = nowMs() + (group.debugCreated and 5000 or 30000)
            end
        elseif entry.snapshot then
            member.waking, member.spawnQueued = false, false
            member.hibernated, member.snapshot = true, entry.snapshot
            member.spawnRetryAt = nowMs() + (group.debugCreated and 5000 or 30000)
        else
            member.spawnQueued = false
            member.waking = false
            member.actorId = nil
            member.spawnRetryAt = nowMs() + (group.debugCreated and 5000 or 30000)
        end
        if entry.attempts >= 3 and SC.Diagnostics and type(SC.Diagnostics.report) == "function" then
            SC.Diagnostics.report("faction-spawn", group.id,
                "resident spawn deferred without declaring a death", member.spawnFailure)
        end
        return false, reason
    end
    spawnTicket, spawnEntry = ticket, entry
    return true, reason
end

local function pollSpawn()
    if spawnTicket == nil then return beginNextSpawn() end
    local actor, reason = SC.Actor.pollSpawn(spawnTicket)
    if actor == nil and reason == "spawn_pending" then return false, reason end
    local entry = spawnEntry
    spawnTicket, spawnEntry = nil, nil
    local group = entry and groups[entry.groupId] or nil
    local member
    if group then
        for _, candidate in ipairs(group.members or {}) do
            if candidate.key == entry.memberKey then member = candidate break end
        end
    end
    if actor == nil then
        if member then member.spawnFailure = tostring(reason) end
        if entry then
            entry.attempts = (entry.attempts or 0) + 1
            if entry.attempts < 3 then
                if advanceSpawnSquare(entry, group) then
                    spawnQueue[#spawnQueue + 1] = entry
                elseif member then
                    member.spawnQueued, member.waking = false, false
                    member.spawnRetryAt = nowMs() + (group and group.debugCreated and 5000 or 30000)
                end
            elseif member then
                member.waking = false
                member.spawnQueued = false
                if entry.snapshot then
                    member.hibernated = true
                    member.snapshot = entry.snapshot
                    member.spawnRetryAt = nowMs() + (group.debugCreated and 5000 or 30000)
                else
                    member.actorId = nil
                    member.spawnRetryAt = nowMs() + (group and group.debugCreated and 5000 or 30000)
                end
                if SC.Diagnostics and type(SC.Diagnostics.report) == "function" then
                    SC.Diagnostics.report("faction-spawn", group and group.id,
                        "resident spawn deferred without declaring a death", member.spawnFailure)
                end
            end
        end
        return false, reason
    end
    local actorId = U().idOf(actor)
    if member then
        member.actorId = actorId
        member.hibernated = false
        member.waking = false
        member.spawnQueued = false
        member.snapshot = nil
        member.spawnFailure = nil
        member.spawnRetryAt = nil
        memberToGroup[actorId] = group.id
    end
    if group then
        group.lifecycle = hasOpenJobs(group) and "fortifying" or "settled"
        appendBounded(group.history, {
            day = worldDay(), kind = "member_spawned", member = member and member.key,
        }, 256)
    end
    return true, actor
end

local function aliveCount(group)
    local count = 0
    for _, member in ipairs(group.members or {}) do
        if member.alive ~= false and member.away == nil and member.departed ~= true then
            count = count + 1
        end
    end
    return count
end

local function householdLivingCount(group)
    local count = 0
    for _, member in ipairs(group.members or {}) do
        if member.alive ~= false and member.departed ~= true then count = count + 1 end
    end
    return count
end

local function activeCount(group)
    local count = 0
    for _, member in ipairs(group.members or {}) do
        if member.alive ~= false and member.away == nil and member.departed ~= true
            and member.actorId and SC.Registry.byId(member.actorId) then
            count = count + 1
        end
    end
    return count
end

local function livingGroupCount(archetype)
    local count = 0
    for _, id in ipairs(groupOrder) do
        local group = groups[id]
        if group and group.lifecycle ~= "destroyed"
            and (archetype == nil or group.archetype == archetype) then
            count = count + 1
        end
    end
    return count
end

function Factions.count(archetype)
    return livingGroupCount(archetype)
end

local function groupAtPosition(position)
    if type(position) ~= "table" then return nil end
    for _, id in ipairs(groupOrder) do
        local group = groups[id]
        local bounds = group and group.house and group.house.bounds
        if bounds and position.x >= bounds.x1 and position.x <= bounds.x2
            and position.y >= bounds.y1 and position.y <= bounds.y2
            and (position.z or 0) >= 0 and (position.z or 0) <= 2 then
            return group
        end
    end
    return nil
end

local function containerFingerprint(container)
    local itemsOk, items = invoke(container, "getItems")
    if not itemsOk or items == nil then return nil end
    local result = { total = 0, types = {} }
    for index = 0, math.min(listSize(items), 512) - 1 do
        local item = listGet(items, index)
        local typeOk, itemType = invoke(item, "getFullType")
        if typeOk and type(itemType) == "string" then
            result.total = result.total + 1
            result.types[itemType] = (result.types[itemType] or 0) + 1
        end
    end
    return result
end

function Factions.observeContainerOpened(container, player)
    if container == nil then return false, "container_unavailable" end
    local squareOk, square = invoke(container, "getSourceGrid")
    if not squareOk or square == nil then
        local parentOk, parent = invoke(container, "getParent")
        if parentOk and parent then square = U().squareOf(parent) end
    end
    local x, y, z = U().position(square)
    local group = x and groupAtPosition({ x = x, y = y, z = z or 0 }) or nil
    if not group then return false, "container_outside_faction_territory" end
    observedContainers[container] = {
        factionId = group.id, fingerprint = containerFingerprint(container),
        openedAt = nowMs(), player = player,
    }
    return true, group.id
end

local function observeContainerTransfers(current)
    for container, observation in pairs(observedContainers) do
        if current - (observation.openedAt or 0) > 60000 then
            observedContainers[container] = nil
        else
            local currentPrint = containerFingerprint(container)
            local prior = observation.fingerprint
            if currentPrint and prior then
                local removed = 0
                for itemType, count in pairs(prior.types or {}) do
                    removed = removed + math.max(0,
                        (tonumber(count) or 0) - (tonumber(currentPrint.types[itemType]) or 0))
                end
                if removed > 0 and not (SC.Trade
                    and type(SC.Trade.isAuthorizedTransfer) == "function"
                    and SC.Trade.isAuthorizedTransfer(observation.factionId)) then
                    Factions.noteOffense(observation.factionId, "theft", math.min(2, removed))
                    observation.openedAt = current
                end
                observation.fingerprint = currentPrint
            end
        end
    end
end

function Factions.onWeaponHitCharacter(attacker, target, weapon, damage)
    local currentPlayer = localPlayer()
    if attacker == nil or attacker ~= currentPlayer or target == nil then return end
    local id = U().idOf(target)
    local record = id and SC.Registry.byId(id) or nil
    if not record then return end
    local factionId = record.factionId
    if type(factionId) ~= "string" and SC.FactionRecruitment
        and type(SC.FactionRecruitment.originForActor) == "function" then
        local origin = SC.FactionRecruitment.originForActor(id)
        factionId = origin and origin.factionId or nil
    end
    if type(factionId) ~= "string" then return end
    local current = nowMs()
    local group = groups[factionId]
    if group and group.archetype == "bandit_camp" and type(group.bandit) == "table" then
        group.bandit.engagement = "attacking"
        group.bandit.attackedHour = worldAgeHours()
    end
    local prior = recentPlayerAttacks[id]
    recentPlayerAttacks[id] = current
    if prior == nil or current - prior > 3000 then
        Factions.noteOffense(factionId, "damage", 1)
    end
end

function Factions.onWeaponSwingHitPoint(attacker, weapon)
    local currentPlayer = localPlayer()
    if attacker == nil or attacker ~= currentPlayer or not SC.Senses
        or type(SC.Senses.hear) ~= "function" then return end
    local x, y, z = U().position(attacker)
    if x == nil then return end
    local ranged, rangedOk = nil, false
    if weapon then ranged, rangedOk = U().call(weapon, "isRanged") end
    local radius = 8
    if rangedOk and ranged == true then
        local nativeRadius, radiusOk = U().call(weapon, "getSoundRadius")
        radius = radiusOk and math.max(12, math.min(100, tonumber(nativeRadius) or 24)) or 24
    end
    SC.Senses.hear(attacker, x, y, z, radius,
        rangedOk and ranged == true and 30 or 8, "player_attack")
end

function Factions.installHooks()
    if hitHookInstalled then return true end
    if type(Events) ~= "table" or not Events.OnWeaponHitCharacter
        or type(Events.OnWeaponHitCharacter.Add) ~= "function" then
        return false, "OnWeaponHitCharacter event is unavailable"
    end
    local ok, reason = pcall(Events.OnWeaponHitCharacter.Add, Factions.onWeaponHitCharacter)
    if not ok then return false, tostring(reason) end
    hitHookInstalled = true
    if Events.OnWeaponSwingHitPoint
        and type(Events.OnWeaponSwingHitPoint.Add) == "function" then
        local swingOk = pcall(Events.OnWeaponSwingHitPoint.Add,
            Factions.onWeaponSwingHitPoint)
        swingHookInstalled = swingOk == true
    end
    return true
end

function Factions.removeHooks()
    if not hitHookInstalled then return true end
    if type(Events) ~= "table" or not Events.OnWeaponHitCharacter
        or type(Events.OnWeaponHitCharacter.Remove) ~= "function" then
        return false, "OnWeaponHitCharacter removal is unavailable"
    end
    if swingHookInstalled then
        if not Events.OnWeaponSwingHitPoint
            or type(Events.OnWeaponSwingHitPoint.Remove) ~= "function" then
            return false, "OnWeaponSwingHitPoint removal is unavailable"
        end
        local swingOk, swingReason = pcall(Events.OnWeaponSwingHitPoint.Remove,
            Factions.onWeaponSwingHitPoint)
        if not swingOk then return false, tostring(swingReason) end
        swingHookInstalled = false
    end
    local ok, reason = pcall(Events.OnWeaponHitCharacter.Remove, Factions.onWeaponHitCharacter)
    if not ok then return false, tostring(reason) end
    hitHookInstalled = false
    return true
end

function Factions.hooksInstalled()
    return hitHookInstalled
end

function Factions.isFactionRecord(record)
    return type(record) == "table" and type(record.factionId) == "string"
        and groups[record.factionId] ~= nil
end

function Factions.affiliation(subject)
    if subject == nil then return nil end
    local record = subject
    if type(subject) ~= "table" or subject.id == nil or subject.actor == nil then
        local id = U().idOf(subject)
        record = id and SC.Registry.byId(id) or nil
    end
    local factionId = record and record.factionId
    if not factionId and record and record.id then factionId = memberToGroup[record.id] end
    local group = factionId and groups[factionId] or nil
    if not group then return nil end
    return {
        factionId = factionId, group = group, role = record.factionRole,
        standing = group.standing, reputation = group.reputation,
    }
end

local function recordForSubject(subject)
    if subject == nil or not SC.Registry or type(SC.Registry.byId) ~= "function" then return nil end
    local id = type(subject) == "table" and subject.id or U().idOf(subject)
    return id and SC.Registry.byId(id) or nil
end

local function isPlayerPartyMember(subject, player)
    if subject == nil then return false end
    if player ~= nil and subject == player then return true end
    local record = recordForSubject(subject)
    return record ~= nil and record.recruited == true and record.factionId == nil
end

local function allegianceFacts(source, target, player)
    return {
        sourceExists = source ~= nil,
        targetExists = target ~= nil,
        same = source ~= nil and source == target,
        sourceParty = isPlayerPartyMember(source, player),
        targetParty = isPlayerPartyMember(target, player),
        sourceAffiliation = Factions.affiliation(source),
        targetAffiliation = Factions.affiliation(target),
    }
end

function Factions.isHostileBetween(source, target, player)
    player = player or localPlayer()
    return SC.Allegiance.isHostile(allegianceFacts(source, target, player))
end

-- One relationship contract feeds perception, support, rescue and line-of-fire
-- policy. "Neutral" deliberately does not mean combat cooperation: a tolerated
-- household may be protected from a careless shot without contributing morale,
-- formation support, or medical obligations.
function Factions.relationshipBetween(source, target, player)
    player = player or localPlayer()
    return SC.Allegiance.relationship(allegianceFacts(source, target, player))
end

function Factions.areAlliesBetween(source, target, player)
    player = player or localPlayer()
    return SC.Allegiance.areAllies(allegianceFacts(source, target, player))
end

function Factions.isProtectedBetween(source, target, player)
    player = player or localPlayer()
    return SC.Allegiance.isProtected(allegianceFacts(source, target, player))
end

local function visibleHumanCandidate(observer, candidate, maximumDistance)
    if candidate == nil or candidate == observer or U().isDead(candidate)
        or not U().sameFloor(observer, candidate) then return nil end
    local distance = U().distance(observer, candidate)
    if distance > maximumDistance or not U().canSee(observer, candidate) then return nil end
    return { actor = candidate, id = U().idOf(candidate), distance = distance,
        visible = true }
end

function Factions.hostileTargetFor(actor, player)
    if actor == nil then return nil end
    player = player or localPlayer()
    local sourceAffiliation = Factions.affiliation(actor)
    local candidates, seen = {}, setmetatable({}, { __mode = "k" })
    local function addCandidate(candidate)
        if candidate ~= nil and candidate ~= actor and not seen[candidate] then
            seen[candidate] = true
            candidates[#candidates + 1] = candidate
        end
    end
    if sourceAffiliation then
        addCandidate(player)
    end
    if (sourceAffiliation or isPlayerPartyMember(actor, player)) and SC.Registry
        and type(SC.Registry.living) == "function" then
        -- Registry.living() deliberately returns live actors, not registry
        -- records. Let the shared hostility predicate resolve each actor's
        -- record/affiliation instead of reaching through a non-existent .actor
        -- field. Considering all live actors also keeps hostile households in
        -- the same contract as bandit camps.
        for _, candidate in ipairs(SC.Registry.living() or {}) do
            addCandidate(candidate)
        end
    end
    local best
    for _, candidate in ipairs(candidates) do
        if Factions.isHostileBetween(actor, candidate, player) then
            local row = visibleHumanCandidate(actor, candidate,
                tonumber(SC.Config.get("banditFactionAwarenessRadius")) or 24)
            if row and (not best or row.distance < best.distance) then best = row end
        end
    end
    return best
end

function Factions.group(id)
    return type(id) == "string" and groups[id] or nil
end

function Factions.member(id, memberKey)
    local group = type(id) == "table" and id or groups[id]
    if not group or type(memberKey) ~= "string" then return nil end
    for _, member in ipairs(group.members or {}) do
        if member.key == memberKey then return member end
    end
    return nil
end

function Factions.memberIsPresent(member)
    return type(member) == "table" and member.alive ~= false
        and member.away == nil and member.departed ~= true
end

function Factions.presentCount(id)
    local group = type(id) == "table" and id or groups[id]
    return group and aliveCount(group) or 0
end

local function releaseMemberJobs(group, actorId)
    for _, job in ipairs(group.jobs or {}) do
        if job.assignedId == actorId and job.status == "active" then
            job.status, job.assignedId = "open", nil
        end
    end
end

function Factions.detachMemberForRecruitment(id, memberKey)
    local group = groups[id]
    local member = Factions.member(group, memberKey)
    if not group or not member then return false, "faction_member_unavailable" end
    if not Factions.memberIsPresent(member) then return false, "faction_member_not_present" end
    if aliveCount(group) <= 1 then return false, "last_household_resident" end
    local actorId = member.actorId
    local record = actorId and SC.Registry and SC.Registry.byId(actorId) or nil
    if not record or not record.actor then return false, "faction_member_not_loaded" end
    local snapshot = {
        actorId = actorId, role = member.role, away = member.away,
        departed = member.departed, hibernated = member.hibernated,
    }
    member.away = "recruitment_trial"
    member.departed = false
    member.hibernated = false
    member.snapshot = nil
    memberToGroup[actorId] = nil
    releaseMemberJobs(group, actorId)
    appendBounded(group.history, {
        day = worldDay(), kind = "recruitment_trial_started", member = member.key,
        actorId = actorId,
    }, 256)
    return true, snapshot
end

function Factions.restoreMemberFromRecruitment(id, memberKey, actorId, reason)
    local group = groups[id]
    local member = Factions.member(group, memberKey)
    if not group or not member or member.alive == false or member.departed == true then
        return false, "faction_member_unavailable"
    end
    if type(actorId) ~= "string" or member.actorId ~= actorId then
        return false, "faction_actor_identity_changed"
    end
    local record = SC.Registry and SC.Registry.byId(actorId) or nil
    if not record or not record.actor then return false, "faction_member_not_loaded" end
    member.away = nil
    member.hibernated = false
    member.snapshot = nil
    memberToGroup[actorId] = id
    appendBounded(group.history, {
        day = worldDay(), kind = "recruitment_trial_returned", member = member.key,
        actorId = actorId, reason = tostring(reason or "returned"),
    }, 256)
    return true, member
end

function Factions.completeMemberRecruitment(id, memberKey, actorId)
    local group = groups[id]
    local member = Factions.member(group, memberKey)
    if not group or not member or member.alive == false then
        return false, "faction_member_unavailable"
    end
    if member.away ~= "recruitment_trial" or member.actorId ~= actorId then
        return false, "recruitment_trial_identity_changed"
    end
    memberToGroup[actorId] = nil
    releaseMemberJobs(group, actorId)
    member.away = nil
    member.departed = true
    member.departedActorId = actorId
    member.departedDay = worldDay()
    member.actorId = nil
    member.hibernated = false
    member.snapshot = nil
    appendBounded(group.history, {
        day = worldDay(), kind = "member_joined_player", member = member.key,
        actorId = actorId,
    }, 256)
    return true, member
end

function Factions.atPosition(position)
    return groupAtPosition(position)
end

function Factions.list(discoveredOnly)
    local result = {}
    for _, id in ipairs(groupOrder) do
        local group = groups[id]
        if group and (not discoveredOnly or group.discovered == true) then
            result[#result + 1] = group
        end
    end
    return result
end

function Factions.summary(id)
    local group = groups[id]
    if not group then return nil end
    ensureFactionIdentity(group)
    ensureNearestStreet(group)
    local unresolved, restitution = 0, 0
    for _, offense in ipairs(group.offenses or {}) do
        if offense.forgiven ~= true then
            unresolved = unresolved + 1
            restitution = restitution + (tonumber(offense.restitution) or 0)
        end
    end
    local summary = {
        id = group.id, name = group.name, archetype = group.archetype,
        capabilities = stableCopy(archetypeProfile(group), 2),
        lifecycle = group.lifecycle, standing = group.standing,
        reputation = group.reputation, discovered = group.discovered == true,
        barterUnlocked = group.barterUnlocked == true,
        alive = aliveCount(group), active = activeCount(group),
        request = stableCopy(group.request, 4), house = stableCopy(group.house, 3),
        location = stableCopy(group.location, 3),
        unresolvedOffenses = unresolved, restitutionRequired = restitution,
        permanentHostility = group.permanentHostility == true,
        debugCreated = group.debugCreated == true,
    }
    if group.archetype == "bandit_camp" then
        summary.bandit = stableCopy(group.bandit, 4)
    end
    if SC.FactionLife and type(SC.FactionLife.summary) == "function" then
        summary.life = SC.FactionLife.summary(group)
    end
    if Factions.supports(group, "social") and SC.FactionContracts
        and type(SC.FactionContracts.summary) == "function" then
        summary.social = SC.FactionContracts.summary(group)
    end
    if SC.FactionWorld and type(SC.FactionWorld.summary) == "function" then
        summary.world = SC.FactionWorld.summary(group.id)
    end
    if Factions.supports(group, "recruitment") and SC.FactionRecruitment
        and type(SC.FactionRecruitment.summary) == "function" then
        summary.recruitment = SC.FactionRecruitment.summary(group.id)
    end
    return summary
end

function Factions.markDiscovered(id)
    local group = groups[id]
    if not group then return false, "faction_unavailable" end
    group.discovered = true
    group.lastInteractionDay = worldDay()
    ensureNearestStreet(group)
    return true
end

function Factions.adjustStanding(id, delta, reason)
    local group = groups[id]
    if not group then return false, "faction_unavailable" end
    if group.permanentHostility then return false, "permanent_hostility" end
    group.reputation = math.max(-100, math.min(100,
        (tonumber(group.reputation) or -20) + (tonumber(delta) or 0)))
    group.standing = standingForReputation(group.reputation, group.permanentHostility)
    group.lastInteractionDay = worldDay()
    appendBounded(group.history, {
        day = worldDay(), kind = "standing_changed", delta = delta, reason = tostring(reason or "unknown"),
    }, 256)
    if SC.FactionWorld and type(SC.FactionWorld.onStandingChanged) == "function" then
        SC.FactionWorld.onStandingChanged(id, tonumber(delta) or 0, reason)
    end
    return true, group.standing
end

function Factions.forceStanding(id, standing)
    local group = groups[id]
    if not group or not standingValues[standing] then return false, "invalid_standing" end
    if group.permanentHostility == true and standing ~= "Hostile" then
        return false, "permanent_hostility"
    end
    group.permanentHostility = standing == "Hostile" and group.permanentHostility or false
    group.reputation = standing == "Trusted" and 40 or standing == "Tolerated" and 10
        or standing == "Hostile" and -70 or -20
    group.standing = standing
    group.lifecycle = standing == "Hostile" and "hostile" or "settled"
    return true, standing
end

function Factions.noteOffense(id, kind, severity)
    local group = groups[id]
    if not group then return false, "faction_unavailable" end
    if Factions.supports(group, "social") and SC.FactionContracts
        and type(SC.FactionContracts.noteAction) == "function" then
        pcall(SC.FactionContracts.noteAction, group, kind, tostring(severity or 1))
    end
    local deltas = { trespass = -12, aim = -28, theft = -40, damage = -55, barricade = -45, murder = -100 }
    local delta = (deltas[kind] or -10) * math.max(1, tonumber(severity) or 1)
    local permanent = kind == "murder"
    local offense = {
        kind = kind, day = worldDay(), restitution = math.abs(delta)
            * ((kind == "theft" or kind == "damage") and 2 or 1),
        forgiven = false, permanent = permanent,
    }
    if #group.offenses >= 64 then
        for index = #group.offenses, 1, -1 do
            local prior = group.offenses[index]
            if prior.kind == kind and prior.forgiven ~= true then
                prior.day = worldDay()
                prior.restitution = (tonumber(prior.restitution) or 0) + offense.restitution
                offense = nil
                break
            end
        end
    end
    if offense then appendBounded(group.offenses, offense, 64) end
    if permanent then
        group.permanentHostility = true
        group.reputation = -100
        group.standing = "Hostile"
        group.lifecycle = "hostile"
        return true, "permanent_hostility"
    end
    Factions.adjustStanding(id, delta, kind)
    if group.reputation <= -60 then group.lifecycle = "hostile" else group.lifecycle = "alert" end
    return true, group.standing
end

function Factions.canReconcile(id)
    local group = groups[id]
    if not group then return false, "faction_unavailable" end
    if group.permanentHostility then return false, "murder_is_not_forgiven" end
    local waiting, unresolved = 0, 0
    for _, offense in ipairs(group.offenses or {}) do
        if offense.forgiven ~= true then
            unresolved = unresolved + 1
            local days = offense.kind == "trespass"
                and (SC.Config.get("factionTrespassForgivenessDays") or 3)
                or (SC.Config.get("factionOffenseForgivenessDays") or 7)
            waiting = math.max(waiting, (offense.day or worldDay()) + days - worldDay())
        end
    end
    if unresolved == 0 then return false, "no_restitution_due" end
    return waiting <= 0, waiting > 0 and ("wait_" .. tostring(waiting) .. "_days") or "restitution_due"
end

function Factions.restitutionRequired(id)
    local group = groups[id]
    if not group then return nil, "faction_unavailable" end
    local required = 0
    for _, offense in ipairs(group.offenses or {}) do
        if offense.forgiven ~= true then
            required = required + (tonumber(offense.restitution) or 0)
        end
    end
    return required
end

function Factions.reconcile(id, parcelValue)
    local ready, reason = Factions.canReconcile(id)
    if not ready then return false, reason end
    local group = groups[id]
    local required = Factions.restitutionRequired(id) or 0
    if (tonumber(parcelValue) or 0) < required then return false, "restitution_too_small" end
    for _, offense in ipairs(group.offenses or {}) do offense.forgiven = true end
    group.reputation = -20
    group.standing = "Wary"
    group.lifecycle = "settled"
    return true, "relations_reopened"
end

function Factions.fulfillRequest(id, player)
    local group = groups[id]
    if not group or type(group.request) ~= "table" then return false, "request_unavailable" end
    if not Factions.supports(group, "trade") then return false, "faction_does_not_trade" end
    if group.request.status == "completed" then return false, "request_already_completed" end
    if not SC.Trade or type(SC.Trade.completeRequest) ~= "function" then
        return false, "trade_unavailable"
    end
    local ok, reason = SC.Trade.completeRequest(group, player)
    if not ok then return false, reason end
    group.request.status = "completed"
    group.request.completedDay = worldDay()
    group.barterUnlocked = true
    Factions.adjustStanding(id, 30, "request_completed")
    if SC.FactionLife and type(SC.FactionLife.noteEvent) == "function" then
        SC.FactionLife.noteEvent(group, "request_completed", group.request.kind)
    end
    if SC.FactionContracts and type(SC.FactionContracts.noteAction) == "function" then
        SC.FactionContracts.noteAction(group, "request_completed", group.request.kind)
    end
    if SC.FactionLife and type(SC.FactionLife.shareRumour) == "function" then
        -- A completed need earns one piece of imperfect map intelligence. A
        -- map API failure must never roll back the already committed trade.
        pcall(SC.FactionLife.shareRumour, group, player, false)
    end
    return true, "barter_unlocked"
end

function Factions.setNeed(id, kind, reason)
    local group = groups[id]
    if not group then return false, "faction_unavailable" end
    if not requestDefinitions[kind] then return false, "invalid_request_kind" end
    group.shortageKind = kind
    group.request = makeRequest(group)
    appendBounded(group.history, {
        day = worldDay(), kind = "need_changed", need = kind,
        reason = tostring(reason or "faction_life"),
    }, 256)
    return true, kind
end

function Factions.memberDied(record)
    local factionId = type(record) == "table" and record.factionId or nil
    if type(factionId) ~= "string" and type(record) == "table"
        and SC.FactionRecruitment and type(SC.FactionRecruitment.originForActor) == "function" then
        local origin = SC.FactionRecruitment.originForActor(record.id)
        factionId = origin and origin.factionId or nil
    end
    local group = factionId and groups[factionId] or nil
    if not group then return false, "not_a_faction_member" end
    local playerCaused = nowMs() - (tonumber(recentPlayerAttacks[record.id]) or -math.huge) <= 10000
    recentPlayerAttacks[record.id] = nil
    if playerCaused then Factions.noteOffense(factionId, "murder", 1) end
    memberToGroup[record.id] = nil
    for _, job in ipairs(group.jobs or {}) do
        if job.assignedId == record.id and job.status == "active" then
            job.status, job.assignedId = "open", nil
        end
    end
    local deadMemberKey
    for _, member in ipairs(group.members or {}) do
        if member.actorId == record.id or member.departedActorId == record.id then
            deadMemberKey = member.key
            member.alive, member.hibernated, member.snapshot = false, false, nil
            member.away = nil
            member.actorId = nil
            member.diedDay = worldDay()
            break
        end
    end
    if SC.FactionLife and type(SC.FactionLife.noteEvent) == "function" then
        SC.FactionLife.noteEvent(group, "member_died", deadMemberKey or record.id)
    end
    if householdLivingCount(group) == 0 then group.lifecycle = "destroyed" end
    if Factions.supports(group, "social") and SC.FactionContracts
        and type(SC.FactionContracts.memberDied) == "function" then
        SC.FactionContracts.memberDied(group, deadMemberKey or record.id)
    elseif Factions.supports(group, "social") and SC.FactionContracts
        and type(SC.FactionContracts.noteAction) == "function" then
        SC.FactionContracts.noteAction(group, "member_died", record.id)
    end
    if Factions.supports(group, "recruitment") and SC.FactionRecruitment
        and type(SC.FactionRecruitment.actorDied) == "function" then
        pcall(SC.FactionRecruitment.actorDied, record.id, factionId)
    end
    return true
end

local function actorHiddenFromPlayer(actor, player, runtime)
    if player == nil then return false end
    local visible = U().canSee and U().canSee(player, actor)
    if visible == true then return false end
    -- The player may be far away while a recruited companion is in contact with
    -- this resident. Never hibernate an actor out from under active human combat.
    if Factions.hostileTargetFor(actor, player) ~= nil then return false end
    local threatCount = 0
    if SC.Senses and type(SC.Senses.snapshot) == "function" then
        -- Hibernation is destructive actor removal, so absence of a completed
        -- danger scan is not evidence of safety. Reuse the registry runtime and
        -- wait for the bounded native/grid cursor instead of restarting it.
        local ok, snapshot = pcall(SC.Senses.snapshot, actor, player, runtime)
        if not ok or type(snapshot) ~= "table" or snapshot.valid == false then return false end
        threatCount = tonumber(snapshot.threatCount) or 0
        if type(snapshot.nativeDiscovery) == "table"
            and snapshot.nativeDiscovery.complete ~= true then return false end
        if snapshot.nativeDiscovery == nil and snapshot.scanComplete == false then return false end
    end
    return threatCount == 0
end

Factions._actorHiddenFromPlayerForTests = actorHiddenFromPlayer

local function hibernateMember(group, member, player)
    local record = member.actorId and SC.Registry.byId(member.actorId) or nil
    if not record or not record.actor
        or not actorHiddenFromPlayer(record.actor, player, record.runtime) then
        return false, "member_not_safe_to_hibernate"
    end
    local snapshot, reason = SC.Persistence.captureRecord(record)
    if not snapshot then return false, reason end
    local removed, result = SC.Actor.remove(record.actor)
    if not removed then return false, result end
    member.snapshot = snapshot
    member.hibernated = true
    memberToGroup[member.actorId] = nil
    member.actorId = snapshot.id
    for _, job in ipairs(group.jobs or {}) do
        if job.assignedId == snapshot.id and job.status == "active" then
            job.status, job.assignedId = "open", nil
        end
    end
    return true, "hibernated"
end

local function wakeMember(group, member)
    if member.waking == true then return false, "wake_already_queued" end
    if not member.hibernated or type(member.snapshot) ~= "table" then return false end
    local square = chooseMemberSquare(group, 1)
    if not square then return false, "house_unloaded" end
    local queued, reason = queueMemberSpawn(group, member, square, member.snapshot, group.debugCreated)
    if not queued then return false, reason end
    member.waking = true
    return true, "wake_queued"
end

function Factions.handleMissingSquare(record, player)
    local affiliation = Factions.affiliation(record)
    if not affiliation then return false, "not_a_faction_member" end
    local group = affiliation.group
    for _, member in ipairs(group.members or {}) do
        if member.actorId == record.id then
            local square = chooseMemberSquare(group, 1)
            if square and SC.Actor.recover(record.actor, square) == true then
                return true, "recovered_at_territory"
            end
            return hibernateMember(group, member, player)
        end
    end
    return false, "faction_member_missing"
end

local function lifecyclePulse(group, player)
    if group.lifecycle == "destroyed" or player == nil or not group.house then return end
    local distance = U().distance(player, group.house.anchor)
    local hibernateDistance = tonumber(SC.Config.get("factionHibernationDistance")) or 120
    local wakeDistance = tonumber(SC.Config.get("factionWakeDistance")) or 100
    if distance > hibernateDistance then
        for _, member in ipairs(group.members or {}) do
            if Factions.memberIsPresent(member) and member.actorId
                and SC.Registry.byId(member.actorId) then
                hibernateMember(group, member, player)
            end
        end
    elseif distance < wakeDistance then
        for index, member in ipairs(group.members or {}) do
            if Factions.memberIsPresent(member) and member.hibernated then
                wakeMember(group, member)
            elseif Factions.memberIsPresent(member) and member.actorId ~= nil
                and SC.Registry.byId(member.actorId) == nil
                and member.spawnQueued ~= true
                and not (SC.Persistence and type(SC.Persistence.isPending) == "function"
                    and SC.Persistence.isPending(member.actorId)) then
                -- A valid faction document may outlive a missing/corrupt actor
                -- snapshot. Recreate that resident at its territory once the
                -- persistence queue confirms it has nothing left to restore.
                member.actorId = nil
                local square = chooseMemberSquare(group, index)
                if square then queueMemberSpawn(group, member, square, nil, group.debugCreated) end
            elseif Factions.memberIsPresent(member) and member.actorId == nil
                and member.spawnQueued ~= true
                and nowMs() >= (tonumber(member.spawnRetryAt) or 0) then
                local square = chooseMemberSquare(group, index)
                if square then queueMemberSpawn(group, member, square, nil, group.debugCreated) end
            end
        end
    end
    if group.lifecycle == "alert" and group.standing ~= "Hostile"
        and nowMs() > (tonumber(group.alertUntil) or 0) then
        group.lifecycle = hasOpenJobs(group) and "fortifying" or "settled"
    end
end

function Factions.productionPulse(player)
    if SC.Config.get("factionEnabled") ~= true then return false, "factions_disabled" end
    if not SC.Actor or type(SC.Actor.checkBridge) ~= "function" then
        return false, "actor_provider_unavailable"
    end
    local ready, providerReason = SC.Actor.checkBridge(false)
    if ready ~= true then return false, providerReason or "actor_provider_unavailable" end
    if livingGroupCount("barricaded_household")
        >= (tonumber(SC.Config.get("factionMaxHouseholds")) or 3) then
        productionHouseSearch = nil
        return false, "faction_cap_reached"
    end
    if productionHouseSearch then
        local status, house, searchReason, nextJob = Factions.pollHouseSearch(
            player, { allowSeen = false }, productionHouseSearch.job)
        productionHouseSearch.job = nextJob or productionHouseSearch.job
        if status == "pending" then return false, searchReason or "house_searching" end
        local pending = productionHouseSearch
        productionHouseSearch = nil
        if status ~= "complete" or not house then return false, searchReason end
        local group, createReason = createGroup(house, pending.memberCount, false)
        if not group then return false, createReason end
        lastWorldSpawnDay = pending.day
        return true, group.id
    end
    local day = worldDay()
    if day < (tonumber(SC.Config.get("factionFirstEligibleDay")) or 7) then
        return false, "world_too_young"
    end
    if day - lastWorldSpawnDay < (tonumber(SC.Config.get("factionSpawnCooldownDays")) or 7) then
        return false, "faction_spawn_cooldown"
    end
    if day == lastProductionCheckDay then return false, "daily_roll_already_made" end
    lastProductionCheckDay = day
    if random(100) >= (tonumber(SC.Config.get("factionDailySpawnChancePercent")) or 8) then
        return false, "daily_roll_missed"
    end
    local minimum = tonumber(SC.Config.get("factionMemberMin")) or 1
    local maximum = tonumber(SC.Config.get("factionMemberMax")) or 3
    local memberCount = minimum + random(maximum - minimum + 1)
    local status, house, reason, job = Factions.pollHouseSearch(
        player, { allowSeen = false }, nil)
    if status == "pending" then
        productionHouseSearch = { job = job, day = day, memberCount = memberCount }
        return false, reason or "house_searching"
    end
    if status ~= "complete" or not house then return false, reason end
    local group, createReason = createGroup(house, memberCount, false)
    if not group then return false, createReason end
    lastWorldSpawnDay = day
    return true, group.id
end

local function banditMemberCount(day)
    day = math.max(0, math.floor(tonumber(day) or worldDay()))
    if day < 14 then return 1 + random(2) end
    return 2 + random(2)
end

Factions._banditMemberCountForTests = banditMemberCount

function Factions.banditProductionPulse(player)
    if SC.Config.get("banditFactionEnabled") ~= true then
        banditHouseSearch = nil
        return false, "bandit_factions_disabled"
    end
    if not SC.Actor or type(SC.Actor.checkBridge) ~= "function" then
        return false, "actor_provider_unavailable"
    end
    local ready, providerReason = SC.Actor.checkBridge(false)
    if ready ~= true then return false, providerReason or "actor_provider_unavailable" end
    if livingGroupCount("bandit_camp")
        >= (tonumber(SC.Config.get("banditFactionMaxCamps")) or 1) then
        banditHouseSearch = nil
        return false, "bandit_camp_cap_reached"
    end
    if banditHouseSearch then
        local status, house, searchReason, nextJob = Factions.pollHouseSearch(player, {
            allowSeen = false,
            minimumDistance = tonumber(SC.Config.get("banditFactionSpawnMinDistance")) or 55,
            maximumDistance = tonumber(SC.Config.get("banditFactionSpawnMaxDistance")) or 90,
        }, banditHouseSearch.job)
        banditHouseSearch.job = nextJob or banditHouseSearch.job
        if status == "pending" then return false, searchReason or "house_searching" end
        local pending = banditHouseSearch
        banditHouseSearch = nil
        if status ~= "complete" or not house then return false, searchReason end
        local group, createReason = createGroup(house, pending.memberCount, false, "bandit_camp")
        if not group then return false, createReason end
        lastBanditSpawnDay = pending.day
        return true, group.id
    end
    local day = worldDay()
    if day < (tonumber(SC.Config.get("banditFactionFirstEligibleDay")) or 4) then
        return false, "world_too_young_for_bandits"
    end
    if day - lastBanditSpawnDay
        < (tonumber(SC.Config.get("banditFactionSpawnCooldownDays")) or 10) then
        return false, "bandit_spawn_cooldown"
    end
    if day == lastBanditCheckDay then return false, "bandit_daily_roll_already_made" end
    lastBanditCheckDay = day
    if random(100) >= (tonumber(SC.Config.get("banditFactionDailySpawnChancePercent")) or 4) then
        return false, "bandit_daily_roll_missed"
    end
    local memberCount = banditMemberCount(day)
    local status, house, reason, job = Factions.pollHouseSearch(player, {
        allowSeen = false,
        minimumDistance = tonumber(SC.Config.get("banditFactionSpawnMinDistance")) or 55,
        maximumDistance = tonumber(SC.Config.get("banditFactionSpawnMaxDistance")) or 90,
    }, nil)
    if status == "pending" then
        banditHouseSearch = { job = job, day = day, memberCount = memberCount }
        return false, reason or "house_searching"
    end
    if status ~= "complete" or not house then return false, reason end
    local group, createReason = createGroup(house, memberCount, false, "bandit_camp")
    if not group then return false, createReason end
    lastBanditSpawnDay = day
    return true, group.id
end

function Factions.debugSpawnHousehold(player, size)
    if SC.Config.get("debugSpawnEnabled") ~= true then return false, "debug_tools_disabled" end
    if not SC.Actor or type(SC.Actor.checkBridge) ~= "function" then
        return false, "actor_provider_unavailable"
    end
    local ready, providerReason = SC.Actor.checkBridge(false)
    if ready ~= true then return false, providerReason or "actor_provider_unavailable" end
    if livingGroupCount("barricaded_household")
        >= (tonumber(SC.Config.get("factionMaxHouseholds")) or 3) then
        return false, "faction_cap_reached"
    end
    local house, reason = Factions.findHouse(player, {
        allowSeen = true, minimumDistance = 8, maximumDistance = 55, sampleBudget = 160,
    })
    if not house then return false, reason end
    local minimum = tonumber(SC.Config.get("factionMemberMin")) or 1
    local maximum = tonumber(SC.Config.get("factionMemberMax")) or 3
    if size == "random" or size == nil then size = minimum + random(maximum - minimum + 1) end
    local group, createReason = createGroup(house, size, true)
    return group ~= nil, group and group.id or createReason
end

function Factions.debugSpawnBanditCamp(player, size, loadoutOverride)
    if SC.Config.get("debugSpawnEnabled") ~= true then return false, "debug_tools_disabled" end
    if not SC.Actor or type(SC.Actor.checkBridge) ~= "function" then
        return false, "actor_provider_unavailable"
    end
    local ready, providerReason = SC.Actor.checkBridge(false)
    if ready ~= true then return false, providerReason or "actor_provider_unavailable" end
    if livingGroupCount("bandit_camp")
        >= (tonumber(SC.Config.get("banditFactionMaxCamps")) or 1) then
        return false, "bandit_camp_cap_reached"
    end
    local house, reason = Factions.findHouse(player, {
        allowSeen = true, minimumDistance = 8, maximumDistance = 55, sampleBudget = 160,
    })
    if not house then return false, reason end
    if size == "random" or size == nil then size = banditMemberCount(worldDay()) end
    local group, createReason = createGroup(
        house, size, true, "bandit_camp", loadoutOverride)
    return group ~= nil, group and group.id or createReason
end

function Factions.debugSetBanditEngagement(id, engagement)
    if SC.Config.get("debugSpawnEnabled") ~= true then return false, "debug_tools_disabled" end
    local group = groups[id]
    if not group or group.archetype ~= "bandit_camp" then
        return false, "bandit_camp_unavailable"
    end
    if engagement ~= "unaware" and engagement ~= "challenging"
        and engagement ~= "attacking" then return false, "invalid_bandit_engagement" end
    ensureBanditState(group)
    group.bandit.engagement = engagement
    if engagement == "unaware" then
        group.bandit.attackedHour, group.bandit.engagedHour = nil, nil
    elseif engagement == "attacking" then
        group.bandit.engagedHour = worldAgeHours()
    end
    return true, engagement
end

function Factions.debugStartBanditPatrol(id)
    if SC.Config.get("debugSpawnEnabled") ~= true then return false, "debug_tools_disabled" end
    local group = groups[id]
    if not group or group.archetype ~= "bandit_camp" then
        return false, "bandit_camp_unavailable"
    end
    ensureBanditState(group)
    group.bandit.patrolMemberKey = nil
    group.bandit.patrolStartedHour = nil
    group.bandit.patrolReturnHour = nil
    group.bandit.patrolPhase = nil
    group.bandit.nextPatrolHour = 0
    return true, "bandit_patrol_due"
end

function Factions.debugSpawnLone(player)
    return Factions.debugSpawnHousehold(player, 1)
end

function Factions.debugDelete(id)
    if SC.Config.get("debugSpawnEnabled") ~= true then return false, "debug_tools_disabled" end
    local group = groups[id]
    if not group or group.debugCreated ~= true then return false, "only_debug_groups_can_be_deleted" end
    if group.recruitment and group.recruitment.status == "trial" then
        return false, "cannot_delete_household_during_recruitment_trial"
    end
    for _, member in ipairs(group.members or {}) do
        local record = member.actorId and SC.Registry.byId(member.actorId) or nil
        if record and record.actor then
            local removed, reason = SC.Actor.remove(record.actor)
            if not removed then return false, reason end
        end
        memberToGroup[member.actorId] = nil
    end
    groups[id] = nil
    for index = #groupOrder, 1, -1 do
        if groupOrder[index] == id then table.remove(groupOrder, index) end
    end
    if SC.FactionWorld and type(SC.FactionWorld.onGroupRemoved) == "function" then
        SC.FactionWorld.onGroupRemoved(id)
    end
    return true, "debug_group_deleted"
end

function Factions.debugAdvanceJob(id)
    if SC.Config.get("debugSpawnEnabled") ~= true then return false, "debug_tools_disabled" end
    local group = groups[id]
    if not group then return false, "faction_unavailable" end
    for _, job in ipairs(group.jobs or {}) do
        if job.status ~= "completed" then
            job.status, job.completedDay = "completed", worldDay()
            return true, job.id
        end
    end
    return false, "no_open_fortification_job"
end

function Factions.debugForceRequest(id, kind)
    if SC.Config.get("debugSpawnEnabled") ~= true then return false, "debug_tools_disabled" end
    local group = groups[id]
    local definition = requestDefinitions[kind]
    if not group or not definition then return false, "invalid_request_kind" end
    group.request = {
        kind = kind, label = definition.label,
        required = stableCopy(definition.required, 3), reward = stableCopy(definition.reward, 3),
        status = "available", rewardReserved = true, createdDay = worldDay(),
    }
    return true, kind
end

function Factions.debugSetBarter(id, unlocked)
    if SC.Config.get("debugSpawnEnabled") ~= true then return false, "debug_tools_disabled" end
    local group = groups[id]
    if not group then return false, "faction_unavailable" end
    if not Factions.supports(group, "trade") then return false, "faction_does_not_trade" end
    group.barterUnlocked = unlocked == true
    if unlocked == true and group.request then group.request.status = "completed" end
    return true, unlocked == true and "barter_unlocked" or "barter_locked"
end

function Factions.pulse(player, current)
    current = current or nowMs()
    pollSpawn()
    observeContainerTransfers(current)
    for _, id in ipairs(groupOrder) do
        local group = groups[id]
        lifecyclePulse(group, player)
        if group and group.lifecycle ~= "destroyed" and SC.FactionLife
            and type(SC.FactionLife.pulseGroup) == "function" then
            SC.FactionLife.pulseGroup(group, player, current)
        end
        if group and group.lifecycle ~= "destroyed" and Factions.supports(group, "social")
            and SC.FactionContracts
            and type(SC.FactionContracts.pulseGroup) == "function" then
            SC.FactionContracts.pulseGroup(group, player, current)
        end
        if group and Factions.supports(group, "recruitment") and SC.FactionRecruitment
            and type(SC.FactionRecruitment.pulseGroup) == "function" then
            SC.FactionRecruitment.pulseGroup(group, player, current)
        end
    end
    if not Factions._nextProductionAt or current >= Factions._nextProductionAt then
        Factions._nextProductionAt = current
            + (tonumber(SC.Config.get("factionProductionCheckIntervalMs")) or 30000)
        Factions.productionPulse(player)
        Factions.banditProductionPulse(player)
    end
    if SC.FactionWorld and type(SC.FactionWorld.pulse) == "function" then
        SC.FactionWorld.pulse(worldAgeHours())
    end
    return true
end

function Factions.export()
    local orderCopy, orderReason = stableCopy(groupOrder, 3, { count = 256 })
    if orderCopy == nil then return nil, orderReason end
    local result = {
        schema = SCHEMA, sequence = sequence,
        order = orderCopy, groups = {},
    }
    -- Lua's common `condition and value or fallback` idiom cannot produce nil:
    -- the nil immediately selects the fallback and used to leak -math.huge into
    -- the JSON save document. Omit unset days explicitly so persistence remains
    -- finite and restore can map the absent fields back to its internal sentinel.
    if lastWorldSpawnDay ~= -math.huge then
        result.lastWorldSpawnDay = lastWorldSpawnDay
    end
    if lastProductionCheckDay ~= -math.huge then
        result.lastProductionCheckDay = lastProductionCheckDay
    end
    if lastBanditSpawnDay ~= -math.huge then result.lastBanditSpawnDay = lastBanditSpawnDay end
    if lastBanditCheckDay ~= -math.huge then result.lastBanditCheckDay = lastBanditCheckDay end
    for _, id in ipairs(groupOrder) do
        local group = groups[id]
        if group then
            local copy, copyReason = stableCopy(group, 14, { count = 131072 })
            if copy == nil then
                return nil, "faction " .. tostring(id) .. " export failed: "
                    .. tostring(copyReason)
            else
                -- Active native actors are captured transactionally by
                -- SCPersistence.factionActors. Only hibernated snapshots live
                -- inside faction state.
                for _, member in ipairs(copy.members or {}) do
                    local source
                    for _, original in ipairs(group.members or {}) do
                        if original.key == member.key then source = original break end
                    end
                    if source and source.hibernated ~= true then member.snapshot = nil end
                    member.spawnQueued = nil
                    member.waking = nil
                    member.spawnRetryAt = nil
                    member.spawnFailure = nil
                end
                if copy.life then
                    copy.life.nextPulseAt = nil
                    if copy.life.representative then
                        copy.life.representative.requested = false
                        copy.life.representative.state = "inside"
                        copy.life.representative.memberKey = nil
                        copy.life.representative.greetedVisit = nil
                    end
                end
                if copy.social then copy.social.nextPulseAt = nil end
                if copy.recruitment then copy.recruitment.nextPulseAt = nil end
                result.groups[id] = copy
            end
        end
    end
    return result
end

local function finiteNumber(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

local function restoreFailure(path, detail)
    return false, "invalid faction state at " .. tostring(path) .. ": " .. tostring(detail)
end

local function denseArray(value, path, minimum, maximum)
    if type(value) ~= "table" then return restoreFailure(path, "expected dense array") end
    local count, highest = 0, 0
    for key in pairs(value) do
        if type(key) ~= "number" or not finiteNumber(key) or key < 1
            or key ~= math.floor(key) then
            return restoreFailure(path .. "[" .. tostring(key) .. "]", "non-array key")
        end
        count, highest = count + 1, math.max(highest, key)
    end
    if highest ~= count then return restoreFailure(path, "sparse array") end
    if minimum ~= nil and count < minimum then return restoreFailure(path, "too few entries") end
    if maximum ~= nil and count > maximum then return restoreFailure(path, "too many entries") end
    return true, count
end

local function validPosition(value, path, requireObject)
    if type(value) ~= "table" then return restoreFailure(path, "expected position") end
    if not finiteNumber(value.x) then return restoreFailure(path .. ".x", "expected finite number") end
    if not finiteNumber(value.y) then return restoreFailure(path .. ".y", "expected finite number") end
    if not finiteNumber(value.z or 0) then return restoreFailure(path .. ".z", "expected finite number") end
    if requireObject == true and (not finiteNumber(value.objectIndex)
        or tonumber(value.objectIndex) < 0
        or tonumber(value.objectIndex) ~= math.floor(tonumber(value.objectIndex))) then
        return restoreFailure(path .. ".objectIndex", "expected non-negative integer")
    end
    return true
end

local function validRecordArray(value, path, maximum)
    local okay, countOrReason = denseArray(value, path, 0, maximum)
    if not okay then return false, countOrReason end
    for index = 1, countOrReason do
        if type(value[index]) ~= "table" then
            return restoreFailure(path .. "[" .. tostring(index) .. "]", "expected record")
        end
    end
    return true, countOrReason
end

local function validGroup(source, id, path)
    path = path or ("$.factions.groups[" .. tostring(id) .. "]")
    if type(source) ~= "table" or source.id ~= id
        or type(id) ~= "string" or #id < 8 or #id > 96
        or type(source.name) ~= "string" or #source.name < 1 or #source.name > 96
        or archetypeProfiles[source.archetype] == nil
        or not lifecycleValues[source.lifecycle]
        or not standingValues[source.standing]
        or type(source.house) ~= "table" or type(source.location) ~= "table" then
        return restoreFailure(path, "invalid group header")
    end
    if source.archetype == "bandit_camp" then
        local bandit = source.bandit
        if type(bandit) ~= "table" or bandit.schema ~= 1
            or (bandit.threatTier ~= "melee" and bandit.threatTier ~= "mixed"
                and bandit.threatTier ~= "armed")
            or (bandit.engagement ~= "unaware" and bandit.engagement ~= "challenging"
                and bandit.engagement ~= "attacking")
            or not finiteNumber(bandit.nextPatrolHour)
            or not finiteNumber(bandit.patrolSerial) then
            return restoreFailure(path .. ".bandit", "invalid bandit state")
        end
    end
    local okay, reason = validPosition(source.house.anchor, path .. ".house.anchor", false)
    if not okay then return false, reason end
    okay, reason = validPosition(source.location.coordinates,
        path .. ".location.coordinates", false)
    if not okay then return false, reason end
    if source.location.streetLookupComplete ~= nil
        and type(source.location.streetLookupComplete) ~= "boolean" then
        return restoreFailure(path .. ".location.streetLookupComplete",
            "expected boolean")
    end
    local nearestStreet = source.location.nearestStreet
    if nearestStreet ~= nil then
        if type(nearestStreet) ~= "table" or type(nearestStreet.name) ~= "string"
            or #nearestStreet.name < 1 or #nearestStreet.name > 128
            or not finiteNumber(nearestStreet.distance)
            or tonumber(nearestStreet.distance) < 0
            or not finiteNumber(nearestStreet.x) or not finiteNumber(nearestStreet.y)
            or (nearestStreet.source ~= nil and type(nearestStreet.source) ~= "string") then
            return restoreFailure(path .. ".location.nearestStreet",
                "invalid nearest-street record")
        end
    end
    if type(source.house.bounds) ~= "table" then
        return restoreFailure(path .. ".house.bounds", "expected bounds")
    end
    for _, field in ipairs({ "x1", "y1", "x2", "y2" }) do
        if not finiteNumber(source.house.bounds[field]) then
            return restoreFailure(path .. ".house.bounds." .. field, "expected finite number")
        end
    end
    if tonumber(source.house.bounds.x1) > tonumber(source.house.bounds.x2)
        or tonumber(source.house.bounds.y1) > tonumber(source.house.bounds.y2) then
        return restoreFailure(path .. ".house.bounds", "inverted bounds")
    end
    okay, reason = denseArray(source.house.interior, path .. ".house.interior", 1, 16384)
    if not okay then return false, reason end
    for index = 1, reason do
        local pointOkay, pointReason = validPosition(source.house.interior[index],
            path .. ".house.interior[" .. tostring(index) .. "]", false)
        if not pointOkay then return false, pointReason end
    end
    local openingCount
    okay, openingCount = denseArray(source.house.openings, path .. ".house.openings", 0, 4096)
    if not okay then return false, openingCount end
    for index = 1, openingCount do
        local opening = source.house.openings[index]
        local openingPath = path .. ".house.openings[" .. tostring(index) .. "]"
        local openingOkay, openingReason = validPosition(opening, openingPath, true)
        if not openingOkay then return false, openingReason end
        if opening.kind ~= "door" and opening.kind ~= "window" then
            return restoreFailure(openingPath .. ".kind", "invalid opening kind")
        end
    end
    if source.house.primaryEntry ~= nil then
        okay, reason = validPosition(source.house.primaryEntry,
            path .. ".house.primaryEntry", true)
        if not okay then return false, reason end
    end
    local memberCount
    okay, memberCount = denseArray(source.members, path .. ".members", 1, 3)
    if not okay then return false, memberCount end
    local memberKeys, actorIds = {}, {}
    for index = 1, memberCount do
        local member = source.members[index]
        local memberPath = path .. ".members[" .. tostring(index) .. "]"
        if type(member) ~= "table" or type(member.key) ~= "string" or memberKeys[member.key]
            or type(member.identity) ~= "table"
            or (member.actorId ~= nil and (not SC.Registry
                or type(SC.Registry.isValidId) ~= "function"
                or not SC.Registry.isValidId(member.actorId)))
            or (member.actorId ~= nil and actorIds[member.actorId])
            or (member.hibernated == true and type(member.snapshot) ~= "table") then
            return restoreFailure(memberPath, "invalid or duplicate member")
        end
        memberKeys[member.key] = true
        if member.actorId then actorIds[member.actorId] = true end
    end
    okay, reason = validRecordArray(source.jobs, path .. ".jobs", 256)
    if not okay then return false, reason end
    okay, reason = validRecordArray(source.offenses, path .. ".offenses", 64)
    if not okay then return false, reason end
    okay, reason = validRecordArray(source.history, path .. ".history", 256)
    if not okay then return false, reason end
    if type(source.request) ~= "table" then
        return restoreFailure(path .. ".request", "expected request")
    end
    for _, field in ipairs({ "required", "reward" }) do
        okay, reason = validRecordArray(source.request[field],
            path .. ".request." .. field, 64)
        if not okay then return false, reason end
    end
    if SC.FactionLife and type(SC.FactionLife.validate) == "function" then
        local called, accepted = pcall(SC.FactionLife.validate, source)
        if not called or accepted ~= true then
            return restoreFailure(path .. ".life", called
                and "invalid faction-life extension" or accepted)
        end
    end
    if SC.FactionContracts and type(SC.FactionContracts.validate) == "function" then
        local called, accepted = pcall(SC.FactionContracts.validate, source)
        if not called or accepted ~= true then
            return restoreFailure(path .. ".social", called
                and "invalid faction-contract extension" or accepted)
        end
    end
    if SC.FactionRecruitment and type(SC.FactionRecruitment.validate) == "function" then
        local called, accepted = pcall(SC.FactionRecruitment.validate, source)
        if not called or accepted ~= true then
            return restoreFailure(path .. ".recruitment", called
                and "invalid faction-recruitment extension" or accepted)
        end
    end
    return true
end

local function captureRestoreState()
    return {
        groups = groups, order = groupOrder, members = memberToGroup,
        sequence = sequence, worldDay = lastWorldSpawnDay,
        checkDay = lastProductionCheckDay,
        banditWorldDay = lastBanditSpawnDay, banditCheckDay = lastBanditCheckDay,
        houseSearch = productionHouseSearch, banditHouseSearch = banditHouseSearch,
        queue = spawnQueue, ticket = spawnTicket, entry = spawnEntry,
        restored = restored,
        observed = observedContainers, attacks = recentPlayerAttacks,
        hookInstalled = hitHookInstalled, randomSequence = fallbackRandomSequence,
        nextProductionAt = Factions._nextProductionAt,
    }
end

local function reinstateRestoreState(previous)
    groups, groupOrder, memberToGroup = previous.groups, previous.order, previous.members
    sequence, lastWorldSpawnDay, lastProductionCheckDay = previous.sequence,
        previous.worldDay, previous.checkDay
    lastBanditSpawnDay, lastBanditCheckDay = previous.banditWorldDay, previous.banditCheckDay
    productionHouseSearch, banditHouseSearch = previous.houseSearch, previous.banditHouseSearch
    spawnQueue, spawnTicket, spawnEntry = previous.queue, previous.ticket, previous.entry
    restored = previous.restored
    observedContainers, recentPlayerAttacks = previous.observed, previous.attacks
    hitHookInstalled, fallbackRandomSequence = previous.hookInstalled, previous.randomSequence
    Factions._nextProductionAt = previous.nextProductionAt
end

local function cancelRestoreSpawn(ticket)
    if ticket == nil then return true end
    if not SC.Actor or type(SC.Actor.cancelSpawn) ~= "function" then
        return false, "faction spawn cancellation unavailable"
    end
    local called, cancelled, reason = pcall(SC.Actor.cancelSpawn, ticket)
    if not called or cancelled ~= true then
        return false, "faction spawn cancellation failed: "
            .. tostring(called and (reason or cancelled) or cancelled)
    end
    return true
end

local function commitRestoredTransients()
    productionHouseSearch, banditHouseSearch = nil, nil
    spawnQueue, spawnTicket, spawnEntry = {}, nil, nil
    observedContainers = setmetatable({}, { __mode = "k" })
    recentPlayerAttacks = {}
    fallbackRandomSequence = 0
    Factions._nextProductionAt = nil
end

function Factions.restore(document)
    local candidateGroups, candidateOrder, candidateMembers = {}, {}, {}
    local candidateSequence, candidateWorldDay, candidateCheckDay = 0, -math.huge, -math.huge
    local candidateBanditWorldDay, candidateBanditCheckDay = -math.huge, -math.huge
    if document == nil then
        local previous = captureRestoreState()
        local cancelled, cancelReason = cancelRestoreSpawn(previous.ticket)
        if not cancelled then return false, cancelReason end
        groups, groupOrder, memberToGroup = candidateGroups, candidateOrder, candidateMembers
        sequence, lastWorldSpawnDay, lastProductionCheckDay = 0, -math.huge, -math.huge
        lastBanditSpawnDay, lastBanditCheckDay = -math.huge, -math.huge
        restored = true
        commitRestoredTransients()
        return true, "no_faction_state"
    end
    if type(document) ~= "table"
        or (document.schema ~= SCHEMA and document.schema ~= LEGACY_SCHEMA)
        or type(document.groups) ~= "table" then
        return false, "invalid_faction_state"
    end
    local sourceOrder, copyReason = stableCopy(document.order, 3, { count = 256 })
    if sourceOrder == nil then
        return restoreFailure("$.factions.order", copyReason or "copy failed")
    end
    local orderOkay, orderCount = denseArray(sourceOrder, "$.factions.order", 0, 128)
    if not orderOkay then return false, orderCount end
    if not finiteNumber(document.sequence) or tonumber(document.sequence) < 0 then
        return restoreFailure("$.factions.sequence", "expected non-negative finite number")
    end
    if document.lastWorldSpawnDay ~= nil and not finiteNumber(document.lastWorldSpawnDay) then
        return restoreFailure("$.factions.lastWorldSpawnDay", "expected finite number")
    end
    if document.lastProductionCheckDay ~= nil
        and not finiteNumber(document.lastProductionCheckDay) then
        return restoreFailure("$.factions.lastProductionCheckDay", "expected finite number")
    end
    if document.lastBanditSpawnDay ~= nil and not finiteNumber(document.lastBanditSpawnDay) then
        return restoreFailure("$.factions.lastBanditSpawnDay", "expected finite number")
    end
    if document.lastBanditCheckDay ~= nil and not finiteNumber(document.lastBanditCheckDay) then
        return restoreFailure("$.factions.lastBanditCheckDay", "expected finite number")
    end
    candidateSequence = math.max(0, math.floor(tonumber(document.sequence)))
    candidateWorldDay = document.lastWorldSpawnDay ~= nil
        and tonumber(document.lastWorldSpawnDay) or -math.huge
    candidateCheckDay = document.lastProductionCheckDay ~= nil
        and tonumber(document.lastProductionCheckDay) or -math.huge
    candidateBanditWorldDay = document.lastBanditSpawnDay ~= nil
        and tonumber(document.lastBanditSpawnDay) or -math.huge
    candidateBanditCheckDay = document.lastBanditCheckDay ~= nil
        and tonumber(document.lastBanditCheckDay) or -math.huge
    local seenGroups, seenActors, occupiedNames = {}, {}, {}
    -- Reserve every authored name before migrating legacy entries so a
    -- generated name can never displace a custom name that appears later.
    for orderIndex = 1, orderCount do
        local source = document.groups[sourceOrder[orderIndex]]
        local sourceName = type(source) == "table" and trimmed(source.name) or ""
        if sourceName ~= "" and not isCoordinateFactionName(sourceName) then
            occupiedNames[sourceName] = true
        end
    end
    for orderIndex = 1, orderCount do
        local id = sourceOrder[orderIndex]
        local source = document.groups[id]
        -- Sandbox maximums govern future spawns only. Lowering the setting
        -- must never prune already-persistent households on the next save.
        if type(id) ~= "string" or seenGroups[id] or source == nil then
            return restoreFailure("$.factions.order[" .. tostring(orderIndex) .. "]",
                "missing or duplicate group id")
        end
        local group, groupCopyReason = stableCopy(source, 14, { count = 131072 })
        if group == nil then
            return restoreFailure("$.factions.groups[" .. tostring(id) .. "]",
                groupCopyReason or "copy failed")
        end
        ensureFactionIdentity(group, occupiedNames)
        ensureBanditState(group)
        local groupOkay, groupReason = validGroup(group, id,
            "$.factions.groups[" .. tostring(id) .. "]")
        if groupOkay then
            local unique = true
            for _, member in ipairs(group and group.members or {}) do
                if member.actorId and seenActors[member.actorId] then unique = false break end
            end
            if unique then
                seenGroups[id] = true
                candidateGroups[id], candidateOrder[#candidateOrder + 1] = group, id
                if not requestDefinitions[group.shortageKind] then
                    group.shortageKind = requestDefinitions[group.request.kind]
                        and group.request.kind or requestKinds[((candidateSequence + #group.members)
                            % #requestKinds) + 1]
                end
                if SC.FactionLife and type(SC.FactionLife.initialize) == "function" then
                    local called, initialized = pcall(SC.FactionLife.initialize, group)
                    if not called or initialized == nil then
                        return restoreFailure("$.factions.groups[" .. tostring(id) .. "].life",
                            called and "initialization rejected" or initialized)
                    end
                    group.life.nextPulseAt = nil
                    group.life.representative.requested = false
                    group.life.representative.state = "inside"
                    group.life.representative.memberKey = nil
                end
                if SC.FactionContracts and type(SC.FactionContracts.initialize) == "function" then
                    local called, initialized = pcall(SC.FactionContracts.initialize, group)
                    if not called or initialized == nil then
                        return restoreFailure("$.factions.groups[" .. tostring(id) .. "].social",
                            called and "initialization rejected" or initialized)
                    end
                    group.social.nextPulseAt = nil
                end
                if SC.FactionRecruitment and type(SC.FactionRecruitment.initialize) == "function" then
                    local called, initialized = pcall(SC.FactionRecruitment.initialize, group)
                    if not called or initialized == nil then
                        return restoreFailure("$.factions.groups[" .. tostring(id)
                            .. "].recruitment", called and "initialization rejected" or initialized)
                    end
                end
                for _, member in ipairs(group.members or {}) do
                    member.spawnQueued, member.waking = nil, nil
                    member.spawnRetryAt, member.spawnFailure = nil, nil
                    if member.hibernated ~= true then member.snapshot = nil end
                    if member.actorId and Factions.memberIsPresent(member) then
                        seenActors[member.actorId] = true
                        candidateMembers[member.actorId] = id
                    end
                end
            else
                return restoreFailure("$.factions.groups[" .. tostring(id) .. "].members",
                    "actor id also belongs to an earlier group")
            end
        else
            return false, groupReason
        end
    end
    for id in pairs(document.groups) do
        if type(id) ~= "string" then
            return restoreFailure("$.factions.groups[" .. tostring(id) .. "]",
                "group map key must be a string")
        end
        if not seenGroups[id] then
            return restoreFailure("$.factions.groups[" .. tostring(id) .. "]",
                "unordered group is absent from order")
        end
    end
    local previous = captureRestoreState()
    local world = SC.FactionWorld
    if world and type(world.reconcile) == "function"
        and type(world.transaction) ~= "function" then
        return false, "faction world transaction unavailable"
    end
    groups, groupOrder, memberToGroup = candidateGroups, candidateOrder, candidateMembers
    sequence, lastWorldSpawnDay, lastProductionCheckDay = candidateSequence,
        candidateWorldDay, candidateCheckDay
    lastBanditSpawnDay, lastBanditCheckDay = candidateBanditWorldDay, candidateBanditCheckDay
    restored = true

    local function reconcileAndCancel()
        if world and type(world.reconcile) == "function" then
            local called, reconciled, reason = pcall(world.reconcile)
            if not called or reconciled ~= true then
                return false, "faction reconcile failed: "
                    .. tostring(called and (reason or reconciled) or reconciled)
            end
        end
        return cancelRestoreSpawn(previous.ticket)
    end

    local committed, commitReason
    if world and type(world.reconcile) == "function" then
        local called
        called, committed, commitReason = pcall(world.transaction, reconcileAndCancel)
        if not called then committed, commitReason = false, committed end
    else
        committed, commitReason = reconcileAndCancel()
    end
    if committed ~= true then
        reinstateRestoreState(previous)
        return false, tostring(commitReason or "faction restore transaction failed")
    end
    commitRestoredTransients()
    return true, #groupOrder
end

function Factions.reset()
    if spawnTicket and SC.Actor and type(SC.Actor.cancelSpawn) == "function" then
        pcall(SC.Actor.cancelSpawn, spawnTicket)
    end
    groups, groupOrder, memberToGroup = {}, {}, {}
    sequence, lastWorldSpawnDay, lastProductionCheckDay = 0, -math.huge, -math.huge
    lastBanditSpawnDay, lastBanditCheckDay = -math.huge, -math.huge
    productionHouseSearch, banditHouseSearch = nil, nil
    spawnQueue, spawnTicket, spawnEntry = {}, nil, nil
    observedContainers = setmetatable({}, { __mode = "k" })
    recentPlayerAttacks = {}
    fallbackRandomSequence = 0
    streetLookup = { api = nil, bridge = nil, retryAt = 0 }
    Factions._nextProductionAt = nil
    if SC.FactionContracts and type(SC.FactionContracts.reset) == "function" then
        SC.FactionContracts.reset()
    end
    if SC.FactionWorld and type(SC.FactionWorld.reset) == "function" then
        SC.FactionWorld.reset()
    end
    restored = false
    if SC.FactionLife and type(SC.FactionLife.reset) == "function" then SC.FactionLife.reset() end
end

function Factions.wasRestored()
    return restored
end

return Factions
