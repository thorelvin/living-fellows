-- SPDX-License-Identifier: MIT

local SC = SurvivorCompanion
if not SC.Performance and type(require) == "function" then pcall(require, "SCPerformance") end
SC.Factions = SC.Factions or {}

local Factions = SC.Factions
local SCHEMA = 1
local groups = {}
local groupOrder = {}
local memberToGroup = {}
local sequence = 0
local lastWorldSpawnDay = -math.huge
local lastProductionCheckDay = -math.huge
local productionHouseSearch = nil
local spawnQueue = {}
local spawnTicket = nil
local spawnEntry = nil
local restored = false
local observedContainers = setmetatable({}, { __mode = "k" })
local recentPlayerAttacks = {}
local hitHookInstalled = false
local fallbackRandomSequence = 0

local lifecycleValues = {
    forming = true, fortifying = true, settled = true,
    alert = true, hostile = true, destroyed = true,
}

local standingValues = {
    Wary = true, Tolerated = true, Trusted = true, Hostile = true,
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
    budget = budget or { count = 8192 }
    if budget.count <= 0 then return nil end
    local kind = type(value)
    if kind == "string" or kind == "boolean" then
        budget.count = budget.count - 1
        return value
    end
    if kind == "number" then
        if value ~= value or value == math.huge or value == -math.huge then return nil end
        budget.count = budget.count - 1
        return value
    end
    if kind ~= "table" or (depth or 0) <= 0 then return nil end
    budget.count = budget.count - 1
    local result = {}
    for key, child in pairs(value) do
        if type(key) == "string" or type(key) == "number" then
            local copy = stableCopy(child, depth - 1, budget)
            if copy ~= nil then result[key] = copy end
            if budget.count <= 0 then break end
        end
    end
    return result
end

local function appendBounded(list, value, maximum)
    list[#list + 1] = value
    while #list > maximum do table.remove(list, 1) end
end

local function invoke(object, methodName, ...)
    local value, called, b, c = U().call(object, methodName, ...)
    return called, value, b, c
end

local function listSize(list)
    if type(list) == "table" then return #list end
    local ok, size = invoke(list, "size")
    return ok and tonumber(size) or 0
end

local function listGet(list, index)
    if type(list) == "table" then return list[index + 1] end
    local ok, value = invoke(list, "get", index)
    return ok and value or nil
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

local function descriptorFor(building, bounds, allowSeen)
    local openings, interior, seen, burned = {}, {}, false, false
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
    return {
        id = table.concat({ bounds.x1, bounds.y1, bounds.x2, bounds.y2 }, ":"),
        bounds = bounds,
        anchor = { x = anchor.x, y = anchor.y, z = anchor.z },
        interior = interior,
        openings = openings,
        primaryEntry = openings[1],
        squareCount = budget,
    }
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

local function candidateAt(square, player, allowSeen)
    local building = buildingAt(square)
    if building == nil or building == playerBuilding(player) then return nil, "not_a_candidate_house" end
    local bounds = boundsFor(building)
    if bounds == nil then return nil, "house_bounds_unavailable" end
    if overlapsPlayerBase(bounds) then return nil, "player_base_house" end
    local descriptor, reason = descriptorFor(building, bounds, allowSeen)
    if descriptor == nil then return nil, reason end
    if safehouseAt(descriptor.anchor) then return nil, "safehouse_reserved" end
    if conflictsWithExisting(descriptor) then return nil, "house_too_close_to_faction" end
    return descriptor
end

local function newHouseSearch(player, options)
    options = type(options) == "table" and options or {}
    if player == nil then return nil, "player_unavailable" end
    local px, py, pz = U().position(player)
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
            local house = candidateAt(square, job.player, job.allowSeen)
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

local function nextGroupId()
    sequence = sequence + 1
    local stamp = math.floor(worldAgeHours() * 1000)
    return "faction-household-" .. tostring(stamp) .. "-" .. tostring(sequence)
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

local function addGear(actor, role, group)
    local inventory, inventoryOk = U().call(actor, "getInventory")
    if not inventoryOk or inventory == nil then return false, "inventory_unavailable" end
    local required = { "Base.Hammer" }
    local materialShortage = type(group) == "table" and group.shortageKind == "materials"
    local planks = materialShortage and 1
        or math.max(4, math.floor(tonumber(group and group.materialsPerMemberPlanks) or 4))
    local nails = materialShortage and 2
        or math.max(8, math.floor(tonumber(group and group.materialsPerMemberNails) or 8))
    for _ = 1, planks do required[#required + 1] = "Base.Plank" end
    for _ = 1, nails do required[#required + 1] = "Base.Nails" end
    if role == "watch" then required[#required + 1] = "Base.BaseballBat"
    elseif role == "leader" then required[#required + 1] = "Base.KitchenKnife"
    else required[#required + 1] = "Base.HandAxe" end
    if role == "leader" and group and group.shortageKind == "ammunition" then
        required[#required + 1] = "Base.Pistol"
    end
    if role == "leader" then required[#required + 1] = "Base.Book" end
    if not group or group.shortageKind ~= "water" then required[#required + 1] = "Base.WaterBottle" end
    if not group or group.shortageKind ~= "food" then required[#required + 1] = "Base.CannedSardines" end
    if not group or group.shortageKind ~= "medicine" then required[#required + 1] = "Base.Bandage" end
    for _, itemType in ipairs(required) do
        local _, added = invoke(inventory, "AddItem", itemType)
        if added == nil then return false, "gear_add_failed:" .. itemType end
    end
    if role == "leader" and type(group) == "table" and type(group.request) == "table" then
        for _, reward in ipairs(group.request.reward or {}) do
            for _ = 1, math.max(0, math.floor(tonumber(reward.count) or 0)) do
                local _, added = invoke(inventory, "AddItem", reward.type)
                if added == nil then return false, "reward_reservation_failed:" .. tostring(reward.type) end
            end
        end
    end
    return true
end

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
                movementMode = "walk", combatStance = "defensive",
                combatDoctrine = "close_defense", weaponPriority = "best",
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

local function createGroup(house, size, debugCreated)
    size = math.max(tonumber(SC.Config.get("factionMemberMin")) or 1,
        math.min(tonumber(SC.Config.get("factionMemberMax")) or 3, math.floor(tonumber(size) or 1)))
    local active = SC.Registry and type(SC.Registry.living) == "function"
        and #SC.Registry.living() or 0
    local stored = SC.Vehicle and type(SC.Vehicle.storedCount) == "function"
        and SC.Vehicle.storedCount() or 0
    if active + stored + size > (tonumber(SC.Config.get("maxCompanions")) or 16) then
        return nil, "native_actor_capacity_reached"
    end
    local group = {
        id = nextGroupId(), archetype = "barricaded_household",
        name = "Household near " .. tostring(house.anchor.x) .. ", " .. tostring(house.anchor.y),
        lifecycle = "forming", standing = "Wary", reputation = -20,
        discovered = debugCreated == true, debugCreated = debugCreated == true,
        createdDay = worldDay(), lastInteractionDay = worldDay(),
        permanentHostility = false, barterUnlocked = false,
        shortageKind = requestKinds[((sequence + size) % #requestKinds) + 1],
        house = stableCopy(house, 5, { count = 4096 }),
        members = {}, jobs = buildJobs(house), offenses = {}, history = {},
    }
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
    local localPlayer = type(getPlayer) == "function" and getPlayer() or nil
    if attacker == nil or attacker ~= localPlayer or target == nil then return end
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
    local prior = recentPlayerAttacks[id]
    recentPlayerAttacks[id] = current
    if prior == nil or current - prior > 3000 then
        Factions.noteOffense(factionId, "damage", 1)
    end
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
    return true
end

function Factions.removeHooks()
    if not hitHookInstalled then return true end
    if type(Events) ~= "table" or not Events.OnWeaponHitCharacter
        or type(Events.OnWeaponHitCharacter.Remove) ~= "function" then
        return false, "OnWeaponHitCharacter removal is unavailable"
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
    local unresolved, restitution = 0, 0
    for _, offense in ipairs(group.offenses or {}) do
        if offense.forgiven ~= true then
            unresolved = unresolved + 1
            restitution = restitution + (tonumber(offense.restitution) or 0)
        end
    end
    local summary = {
        id = group.id, name = group.name, archetype = group.archetype,
        lifecycle = group.lifecycle, standing = group.standing,
        reputation = group.reputation, discovered = group.discovered == true,
        barterUnlocked = group.barterUnlocked == true,
        alive = aliveCount(group), active = activeCount(group),
        request = stableCopy(group.request, 4), house = stableCopy(group.house, 3),
        unresolvedOffenses = unresolved, restitutionRequired = restitution,
        permanentHostility = group.permanentHostility == true,
        debugCreated = group.debugCreated == true,
    }
    if SC.FactionLife and type(SC.FactionLife.summary) == "function" then
        summary.life = SC.FactionLife.summary(group)
    end
    if SC.FactionContracts and type(SC.FactionContracts.summary) == "function" then
        summary.social = SC.FactionContracts.summary(group)
    end
    if SC.FactionWorld and type(SC.FactionWorld.summary) == "function" then
        summary.world = SC.FactionWorld.summary(group.id)
    end
    if SC.FactionRecruitment and type(SC.FactionRecruitment.summary) == "function" then
        summary.recruitment = SC.FactionRecruitment.summary(group.id)
    end
    return summary
end

function Factions.markDiscovered(id)
    local group = groups[id]
    if not group then return false, "faction_unavailable" end
    group.discovered = true
    group.lastInteractionDay = worldDay()
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
    if SC.FactionContracts and type(SC.FactionContracts.noteAction) == "function" then
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
    if SC.FactionContracts and type(SC.FactionContracts.memberDied) == "function" then
        SC.FactionContracts.memberDied(group, deadMemberKey or record.id)
    elseif SC.FactionContracts and type(SC.FactionContracts.noteAction) == "function" then
        SC.FactionContracts.noteAction(group, "member_died", record.id)
    end
    if SC.FactionRecruitment and type(SC.FactionRecruitment.actorDied) == "function" then
        pcall(SC.FactionRecruitment.actorDied, record.id, factionId)
    end
    return true
end

local function actorHiddenFromPlayer(actor, player)
    if player == nil then return false end
    local visible = U().canSee and U().canSee(player, actor)
    if visible == true then return false end
    local threatCount = 0
    if SC.Senses and type(SC.Senses.snapshot) == "function" then
        local ok, snapshot = pcall(SC.Senses.snapshot, actor, player)
        if ok and type(snapshot) == "table" then threatCount = tonumber(snapshot.threatCount) or 0 end
    end
    return threatCount == 0
end

local function hibernateMember(group, member, player)
    local record = member.actorId and SC.Registry.byId(member.actorId) or nil
    if not record or not record.actor or not actorHiddenFromPlayer(record.actor, player) then
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
    if #groupOrder >= (tonumber(SC.Config.get("factionMaxHouseholds")) or 3) then
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

function Factions.debugSpawnHousehold(player, size)
    if SC.Config.get("debugSpawnEnabled") ~= true then return false, "debug_tools_disabled" end
    if not SC.Actor or type(SC.Actor.checkBridge) ~= "function" then
        return false, "actor_provider_unavailable"
    end
    local ready, providerReason = SC.Actor.checkBridge(false)
    if ready ~= true then return false, providerReason or "actor_provider_unavailable" end
    if #groupOrder >= (tonumber(SC.Config.get("factionMaxHouseholds")) or 3) then
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
        if group and group.lifecycle ~= "destroyed" and SC.FactionContracts
            and type(SC.FactionContracts.pulseGroup) == "function" then
            SC.FactionContracts.pulseGroup(group, player, current)
        end
        if group and SC.FactionRecruitment
            and type(SC.FactionRecruitment.pulseGroup) == "function" then
            SC.FactionRecruitment.pulseGroup(group, player, current)
        end
    end
    if not Factions._nextProductionAt or current >= Factions._nextProductionAt then
        Factions._nextProductionAt = current
            + (tonumber(SC.Config.get("factionProductionCheckIntervalMs")) or 30000)
        Factions.productionPulse(player)
    end
    if SC.FactionWorld and type(SC.FactionWorld.pulse) == "function" then
        SC.FactionWorld.pulse(worldAgeHours())
    end
    return true
end

function Factions.export()
    local result = {
        schema = SCHEMA, sequence = sequence,
        lastWorldSpawnDay = lastWorldSpawnDay == -math.huge and nil or lastWorldSpawnDay,
        lastProductionCheckDay = lastProductionCheckDay == -math.huge and nil or lastProductionCheckDay,
        order = stableCopy(groupOrder, 2, { count = 64 }), groups = {},
    }
    for _, id in ipairs(groupOrder) do
        local group = groups[id]
        if group then
            local copy = stableCopy(group, 8, { count = 16384 })
            if copy then
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
    value = tonumber(value)
    return value ~= nil and value == value and value ~= math.huge and value ~= -math.huge
end

local function validGroup(source, id)
    if type(source) ~= "table" or source.id ~= id
        or type(id) ~= "string" or #id < 8 or #id > 96
        or source.archetype ~= "barricaded_household"
        or not lifecycleValues[source.lifecycle]
        or not standingValues[source.standing]
        or type(source.house) ~= "table" or type(source.house.anchor) ~= "table"
        or not finiteNumber(source.house.anchor.x) or not finiteNumber(source.house.anchor.y)
        or not finiteNumber(source.house.anchor.z or 0)
        or type(source.house.bounds) ~= "table"
        or not finiteNumber(source.house.bounds.x1) or not finiteNumber(source.house.bounds.y1)
        or not finiteNumber(source.house.bounds.x2) or not finiteNumber(source.house.bounds.y2)
        or tonumber(source.house.bounds.x1) > tonumber(source.house.bounds.x2)
        or tonumber(source.house.bounds.y1) > tonumber(source.house.bounds.y2)
        or type(source.house.interior) ~= "table" or #source.house.interior < 1
        or type(source.house.openings) ~= "table"
        or type(source.members) ~= "table" or #source.members < 1 or #source.members > 3 then
        return false
    end
    local memberKeys, actorIds = {}, {}
    for _, member in ipairs(source.members) do
        if type(member) ~= "table" or type(member.key) ~= "string" or memberKeys[member.key]
            or type(member.identity) ~= "table"
            or (member.actorId ~= nil and (not SC.Registry
                or type(SC.Registry.isValidId) ~= "function"
                or not SC.Registry.isValidId(member.actorId)))
            or (member.actorId ~= nil and actorIds[member.actorId])
            or (member.hibernated == true and type(member.snapshot) ~= "table") then
            return false
        end
        memberKeys[member.key] = true
        if member.actorId then actorIds[member.actorId] = true end
    end
    if type(source.jobs) ~= "table" or #source.jobs > 256
        or type(source.offenses) ~= "table" or #source.offenses > 64
        or type(source.history) ~= "table" or #source.history > 256 then
        return false
    end
    if SC.FactionLife and type(SC.FactionLife.validate) == "function"
        and SC.FactionLife.validate(source) ~= true then return false end
    if SC.FactionContracts and type(SC.FactionContracts.validate) == "function"
        and SC.FactionContracts.validate(source) ~= true then return false end
    if SC.FactionRecruitment and type(SC.FactionRecruitment.validate) == "function"
        and SC.FactionRecruitment.validate(source) ~= true then return false end
    return true
end

function Factions.restore(document)
    if spawnTicket and SC.Actor and type(SC.Actor.cancelSpawn) == "function" then
        pcall(SC.Actor.cancelSpawn, spawnTicket)
    end
    groups, groupOrder, memberToGroup = {}, {}, {}
    spawnQueue, spawnTicket, spawnEntry = {}, nil, nil
    productionHouseSearch = nil
    sequence, lastWorldSpawnDay, lastProductionCheckDay = 0, -math.huge, -math.huge
    restored = true
    if document == nil then return true, "no_faction_state" end
    if type(document) ~= "table" or document.schema ~= SCHEMA or type(document.groups) ~= "table" then
        return false, "invalid_faction_state"
    end
    sequence = math.max(0, math.floor(tonumber(document.sequence) or 0))
    lastWorldSpawnDay = tonumber(document.lastWorldSpawnDay) or -math.huge
    lastProductionCheckDay = tonumber(document.lastProductionCheckDay) or -math.huge
    local sourceOrder = type(document.order) == "table" and document.order or {}
    local seenGroups, seenActors = {}, {}
    for _, id in ipairs(sourceOrder) do
        local source = document.groups[id]
        -- Sandbox maximums govern future spawns only. Lowering the setting
        -- must never prune already-persistent households on the next save.
        if type(id) == "string" and not seenGroups[id]
            and validGroup(source, id) then
            local group = stableCopy(source, 8, { count = 16384 })
            local unique = group ~= nil
            for _, member in ipairs(group and group.members or {}) do
                if member.actorId and seenActors[member.actorId] then unique = false break end
            end
            if unique then
                seenGroups[id] = true
                groups[id], groupOrder[#groupOrder + 1] = group, id
                if not requestDefinitions[group.shortageKind]
                    or type(group.request) ~= "table" then
                    group.shortageKind = requestDefinitions[group.shortageKind]
                        and group.shortageKind or requestKinds[((sequence + #group.members)
                            % #requestKinds) + 1]
                    group.request = makeRequest(group)
                end
                if SC.FactionLife and type(SC.FactionLife.initialize) == "function" then
                    SC.FactionLife.initialize(group)
                    group.life.nextPulseAt = nil
                    group.life.representative.requested = false
                    group.life.representative.state = "inside"
                    group.life.representative.memberKey = nil
                end
                if SC.FactionContracts and type(SC.FactionContracts.initialize) == "function" then
                    SC.FactionContracts.initialize(group)
                    group.social.nextPulseAt = nil
                end
                if SC.FactionRecruitment and type(SC.FactionRecruitment.initialize) == "function" then
                    SC.FactionRecruitment.initialize(group)
                end
                for _, member in ipairs(group.members or {}) do
                    member.spawnQueued, member.waking = nil, nil
                    member.spawnRetryAt, member.spawnFailure = nil, nil
                    if member.hibernated ~= true then member.snapshot = nil end
                    if member.actorId and Factions.memberIsPresent(member) then
                        seenActors[member.actorId] = true
                        memberToGroup[member.actorId] = id
                    end
                end
            end
        end
    end
    if SC.FactionWorld and type(SC.FactionWorld.reconcile) == "function" then
        SC.FactionWorld.reconcile()
    end
    return true, #groupOrder
end

function Factions.reset()
    if spawnTicket and SC.Actor and type(SC.Actor.cancelSpawn) == "function" then
        pcall(SC.Actor.cancelSpawn, spawnTicket)
    end
    groups, groupOrder, memberToGroup = {}, {}, {}
    sequence, lastWorldSpawnDay, lastProductionCheckDay = 0, -math.huge, -math.huge
    spawnQueue, spawnTicket, spawnEntry = {}, nil, nil
    observedContainers = setmetatable({}, { __mode = "k" })
    recentPlayerAttacks = {}
    fallbackRandomSequence = 0
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
