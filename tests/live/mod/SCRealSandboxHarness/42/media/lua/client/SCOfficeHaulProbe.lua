-- SPDX-License-Identifier: MIT
-- Disposable cloned-save probe. Geometry comes exclusively from loaded native
-- map squares and door objects; walls, furniture and doors are never altered.
SCRealSandboxHarnessProbes = SCRealSandboxHarnessProbes or {}
local Probe = {}
SCRealSandboxHarnessProbes.SCOfficeHaulProbe = Probe
local OUTSIDE = "outside"
local steps = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

local function call(object, method, ...)
    if object == nil or type(object[method]) ~= "function" then return nil end
    local ok, value = pcall(function(...) return object[method](object, ...) end, ...)
    if ok then return value end
    return nil
end

local function position(object)
    return tonumber(call(object, "getX")), tonumber(call(object, "getY")),
        tonumber(call(object, "getZ"))
end

local function key(x, y, z)
    return tostring(x) .. "," .. tostring(y) .. "," .. tostring(z or 0)
end

local function at(object)
    local x, y, z = position(object)
    if x == nil then return "none" end
    return string.format("%.3f,%.3f,%.2f", x, y, z or 0)
end

local function roomKey(square)
    local room = call(square, "getRoom")
    return room and tostring(room) or OUTSIDE, room
end

local function inside(zone, square)
    local x, y, z = position(square)
    return x ~= nil and math.floor(z or 0) == (tonumber(zone.z) or 0)
        and x >= zone.x1 and x <= zone.x2 and y >= zone.y1 and y <= zone.y2
end

local function screenshot(H, suffix)
    pcall(function()
        getCore():TakeFullScreenshot(tostring(H.config.run_id) .. "-office-haul-" .. suffix)
    end)
end

local function addEdge(survey, first, second, cost, door)
    if first == second then return end
    survey.graph[first] = survey.graph[first] or {}
    survey.graph[second] = survey.graph[second] or {}
    survey.graph[first][#survey.graph[first] + 1] = { to = second, cost = cost, door = door }
    survey.graph[second][#survey.graph[second] + 1] = { to = first, cost = cost, door = door }
end

local function doorRow(SC, square, object)
    local north = call(object, "getNorth")
    if type(north) ~= "boolean" then return nil end
    local x, y, z = position(square)
    local other = SC.GameplayUtil.gridSquare(x - (north and 0 or 1),
        y - (north and 1 or 0), z)
    if other == nil then return nil end
    local first, second = roomKey(square), roomKey(other)
    return { object = object, square = square, other = other, x = x, y = y, z = z,
        north = north, id = key(x, y, z) .. (north and "N" or "W"),
        first = first, second = second,
        destroyed = call(object, "isDestroyed") == true,
        blocked = call(object, "isBarricaded") == true
            or call(object, "isPermaLocked") == true }
end

local function surveyMap(SC, base)
    local U = SC.GameplayUtil
    local survey = { squares = {}, ordered = {}, rooms = {}, roomOrder = {}, zones = base.zones or {},
        graph = {}, doors = {}, bodies = {}, bounds = nil }
    for _, zone in ipairs(base.zones or {}) do
        if (zone.kind == "area" or zone.kind == "lumber" or zone.kind == "burial")
            and (tonumber(zone.z) or 0) == 0 then
            for y = zone.y1 - 3, zone.y2 + 3 do
                for x = zone.x1 - 3, zone.x2 + 3 do
                    local k = key(x, y, 0)
                    if survey.squares[k] == nil then
                        local square = U.gridSquare(x, y, 0)
                        if square then
                            survey.squares[k] = square
                            survey.ordered[#survey.ordered + 1] = square
                            local rk, room = roomKey(square)
                            if room and survey.rooms[rk] == nil then
                                local row = { room = room, key = rk, squares = {},
                                    label = tostring(#survey.roomOrder + 1),
                                    name = tostring(call(room, "getName")) }
                                survey.rooms[rk] = row
                                survey.roomOrder[#survey.roomOrder + 1] = row
                            end
                            if room then
                                local list = survey.rooms[rk].squares
                                list[#list + 1] = square
                            end
                            local bounds = survey.bounds
                            if bounds == nil then
                                survey.bounds = { x1 = x, y1 = y, x2 = x, y2 = y }
                            else
                                bounds.x1, bounds.y1 = math.min(bounds.x1, x), math.min(bounds.y1, y)
                                bounds.x2, bounds.y2 = math.max(bounds.x2, x), math.max(bounds.y2, y)
                            end
                            U.squareStaticMovingObjects(square, function(object)
                                if U.instanceOf(object, "IsoDeadBody") then
                                    survey.bodies[#survey.bodies + 1] = { body = object,
                                        square = square, room = rk }
                                end
                            end, 64)
                        end
                    end
                end
            end
        end
    end
    local seen = {}
    for _, square in ipairs(survey.ordered) do
        local objects = call(square, "getObjects")
        for index = 0, (tonumber(call(objects, "size")) or 0) - 1 do
            local object = objects:get(index)
            if U.instanceOf(object, "IsoDoor") or (U.instanceOf(object, "IsoThumpable")
                and call(object, "isDoor") == true) then
                local row = doorRow(SC, square, object)
                if row and not seen[row.id] then
                    seen[row.id] = true
                    survey.doors[#survey.doors + 1] = row
                    if not row.blocked then
                        addEdge(survey, row.first, row.second, row.destroyed and 0 or 1, row)
                    end
                end
            end
        end
    end
    -- Open arches join rooms at zero door cost. This prevents a room's label
    -- from making an open alternative look like a mandatory three-door route.
    for _, square in ipairs(survey.ordered) do
        local x, y, z = position(square)
        local first = roomKey(square)
        for _, direction in ipairs({ { 1, 0 }, { 0, 1 } }) do
            local other = survey.squares[key(x + direction[1], y + direction[2], z)]
            if other then
                local second = roomKey(other)
                if first ~= second then
                    local ok, _, kind = pcall(SC.Topology.barrierBetween, square, other)
                    if ok and kind == "open" then addEdge(survey, first, second, 0) end
                end
            end
        end
    end
    -- Minimum door count from every room to outdoors, including open arches.
    survey.distance, survey.toward = { [OUTSIDE] = 0 }, {}
    local queue, head = { OUTSIDE }, 1
    while head <= #queue do
        local current = queue[head]
        head = head + 1
        for _, edge in ipairs(survey.graph[current] or {}) do
            local distance = survey.distance[current] + edge.cost
            if survey.distance[edge.to] == nil or distance < survey.distance[edge.to] then
                survey.distance[edge.to] = distance
                survey.toward[edge.to] = { room = current, edge = edge }
                queue[#queue + 1] = edge.to
            end
        end
    end
    return survey
end

local function printSurvey(survey, result)
    result("PASS", "office_haul_native_map_survey", "loaded=" .. tostring(#survey.ordered)
        .. " rooms=" .. tostring(#survey.roomOrder) .. " doors=" .. tostring(#survey.doors)
        .. " bodies=" .. tostring(#survey.bodies))
    for _, zone in ipairs(survey.zones) do
        print("SC_REAL_SANDBOX|OFFICE_ZONE|id=" .. tostring(zone.id) .. " kind=" .. tostring(zone.kind)
            .. " bounds=" .. key(zone.x1, zone.y1, zone.z) .. "-" .. key(zone.x2, zone.y2, zone.z))
    end
    for _, room in ipairs(survey.roomOrder) do
        local bounds
        for _, square in ipairs(room.squares) do
            local x, y = position(square)
            if not bounds then bounds = { x, y, x, y }
            else bounds = { math.min(bounds[1], x), math.min(bounds[2], y),
                math.max(bounds[3], x), math.max(bounds[4], y) } end
        end
        local symbolIndex = tonumber(room.label)
        local symbol = string.sub("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ", symbolIndex, symbolIndex)
        print("SC_REAL_SANDBOX|OFFICE_ROOM|label=" .. room.label .. " mapSymbol=" .. symbol .. " id=" .. room.key
            .. " name=" .. room.name .. " tiles=" .. tostring(#room.squares)
            .. " bounds=" .. (bounds and (key(bounds[1], bounds[2], 0) .. "-"
                .. key(bounds[3], bounds[4], 0)) or "none")
            .. " minimumDoorsOutside=" .. tostring(survey.distance[room.key]))
    end
    for _, row in ipairs(survey.doors) do
        print("SC_REAL_SANDBOX|OFFICE_DOOR|id=" .. row.id
            .. " rooms=" .. row.first .. ">" .. row.second
            .. " open=" .. tostring(call(row.object, "IsOpen"))
            .. " locked=" .. tostring(call(row.object, "isLocked"))
            .. " destroyed=" .. tostring(row.destroyed)
            .. " barricaded=" .. tostring(call(row.object, "isBarricaded"))
            .. " permaLocked=" .. tostring(call(row.object, "isPermaLocked")))
    end
    for _, row in ipairs(survey.bodies) do
        print("SC_REAL_SANDBOX|OFFICE_BODY|at=" .. at(row.body) .. " room=" .. row.room
            .. " minimumDoorsOutside=" .. tostring(survey.distance[row.room]))
    end
    local b = survey.bounds
    if b and b.x2 - b.x1 <= 160 and b.y2 - b.y1 <= 160 then
        print("SC_REAL_SANDBOX|OFFICE_MAP_LEGEND|x1=" .. b.x1 .. " x2=" .. b.x2
            .. " room labels=0-9A-Z(+ for later), .=outdoor floor, space=unloaded")
        local symbols = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        for y = b.y1, b.y2 do
            local line = {}
            for x = b.x1, b.x2 do
                local square = survey.squares[key(x, y, 0)]
                local room = square and survey.rooms[roomKey(square)] or nil
                local index = room and tonumber(room.label) or 0
                line[#line + 1] = not square and " " or (room and
                    (index <= #symbols and string.sub(symbols, index, index) or "+") or ".")
            end
            print("SC_REAL_SANDBOX|OFFICE_MAP|y=" .. y .. " " .. table.concat(line))
        end
    end
end

local function standBeside(SC, square)
    local U = SC.GameplayUtil
    local x, y, z = position(square)
    for _, direction in ipairs(steps) do
        local nextSquare = U.gridSquare(x + direction[1], y + direction[2], z)
        if nextSquare and roomKey(nextSquare) == roomKey(square) and U.isSquareFree(nextSquare) then
            local _, kind = SC.Topology.barrierBetween(square, nextSquare)
            if kind == "open" then return nextSquare end
        end
    end
    return nil
end

local function sourceTile(SC, square)
    return SC.BaseLife.isInside(square, "area") == true
        or SC.BaseLife.isInside(square, "lumber") == true
end

local function chooseBody(SC, survey, actor)
    -- The surveyed office has a two-door front exit and a three-door garage
    -- route toward the northern burial ground. Prefer that actual office;
    -- completion proves how many doors the unforced native route really used.
    for _, officeOnly in ipairs({ true, false }) do
        local chosen, best
        local function admitted(roomKeyValue)
            local room = survey.rooms[roomKeyValue]
            local office = room and string.lower(room.name) == "office"
            local depth = survey.distance[roomKeyValue]
            return depth ~= nil and ((officeOnly and office and depth >= 1)
                or (not officeOnly and depth >= 3)), depth
        end
        for _, row in ipairs(survey.bodies) do
            local allowed, depth = admitted(row.room)
            local data = SC.GameplayUtil.modData(row.body)
            if allowed and sourceTile(SC, row.square)
                and (not data or data[SC.Production.BURNED_TAG] == nil)
                and standBeside(SC, row.square) then
                local score = depth * 100
                if chosen == nil or score < best then chosen, best = row, score end
            end
        end
        if chosen then return chosen, "existing_native_body" end
        for _, room in ipairs(survey.roomOrder) do
            local allowed, depth = admitted(room.key)
            if allowed then
                for _, square in ipairs(room.squares) do
                    if sourceTile(SC, square) and SC.GameplayUtil.isSquareFree(square)
                        and standBeside(SC, square) then
                        local score = depth * 100
                        if chosen == nil or score < best then
                            chosen, best = { square = square, room = room.key }, score
                        end
                    end
                end
            end
        end
        if chosen then return chosen, "new_native_body_in_existing_room" end
    end
    return nil, "no_loaded_office_or_three_door_source_room"
end

local function burialZone(SC, base, survey)
    for _, zone in ipairs(base.zones or {}) do
        if zone.kind == "burial" and (tonumber(zone.z) or 0) == 0 then
            for y = zone.y1, zone.y2 do
                for x = zone.x1, zone.x2 do
                    local square = SC.GameplayUtil.gridSquare(x, y, 0)
                    if square and roomKey(square) == OUTSIDE then return zone, "existing" end
                end
            end
        end
    end
    -- A real clear outdoor patch, marked only in the cloned save. A 3x3 plot
    -- gives the native grave's two squares and the worker room to stand.
    for _, square in ipairs(survey.ordered) do
        local x, y = position(square)
        local clear = sourceTile(SC, square) and roomKey(square) == OUTSIDE
        for dy = -1, 1 do
            for dx = -1, 1 do
                local tile = SC.GameplayUtil.gridSquare(x + dx, y + dy, 0)
                local floor = tile and call(tile, "getFloor")
                local texture = tostring(call(floor, "getTextureName") or "")
                local natural = string.sub(texture, 1, 23) == "floors_exterior_natural"
                    or string.sub(texture, 1, 17) == "blends_natural_01"
                if tile == nil or roomKey(tile) ~= OUTSIDE
                    or not SC.GameplayUtil.isSquareFree(tile) or not natural then clear = false end
            end
        end
        if clear then
            local begun = SC.BaseLife.beginZone("burial", { x = x - 1, y = y - 1, z = 0 })
            if begun then
                local made, zone = SC.BaseLife.finishZone({ x = x + 1, y = y + 1, z = 0 },
                    "Harness native office haul burial")
                if made then return zone, "marked_real_outdoor_plot" end
            end
            SC.BaseLife.cancelZone()
        end
    end
    return nil, "no_existing_burial_or_native_diggable_outdoor_plot"
end

local function chooseWorker(SC)
    local fallback
    for _, record in ipairs(SC.Registry.snapshot() or {}) do
        local actor = record.actor
        if record.recruited == true and actor and not SC.GameplayUtil.isDead(actor) then
            local id = SC.GameplayUtil.idOf(actor)
            local role = (SC.BaseLife.resident(id) or {}).role
            local name = tostring(call(actor, "getFullName") or call(actor, "getDisplayName"))
            if string.find(string.lower(name), "jill", 1, true) then return actor, id, name end
            if role == "corpsekeeper" or fallback == nil then fallback = { actor, id, name } end
        end
    end
    if fallback then return fallback[1], fallback[2], fallback[3] end
    return nil
end

local function loadSummary(SC, actor)
    local audit = SC.Logistics.status(actor) or {}
    local surplus = audit.surplus or {}
    local counts = {}
    for category, count in pairs(audit.counts or {}) do counts[#counts + 1] = category .. "=" .. tostring(count) end
    table.sort(counts)
    return "weight=" .. tostring(audit.weight) .. " capacity=" .. tostring(audit.capacity)
        .. " ratio=" .. tostring(audit.ratio) .. " carryCapacity=" .. tostring(audit.carryCapacity)
        .. " carryGearRatio=" .. tostring(audit.carryGearRatio)
        .. " soft=" .. tostring(audit.softRatio) .. " hard=" .. tostring(audit.hardRatio)
        .. " overloaded=" .. tostring(audit.overloaded)
        .. " fieldReturnCleanup=" .. tostring(audit.fieldReturnCleanup)
        .. " fieldReturnCargo=" .. tostring(audit.fieldReturnCargo)
        .. " shouldManage=" .. tostring(audit.shouldManage)
        .. " shouldUnload=" .. tostring(audit.shouldUnload)
        .. " surplus=" .. (surplus.item and SC.GameplayUtil.itemType(surplus.item) or "none")
        .. "/id=" .. tostring(call(surplus.item, "getID"))
        .. "/category=" .. tostring(surplus.category)
        .. "/shelveOnly=" .. tostring(surplus.shelveOnly)
        .. "/proactive=" .. tostring(surplus.proactive)
        .. "/keptHarvest=" .. tostring(surplus.keptHarvest)
        .. " counts=" .. table.concat(counts, ",")
end

local function carriedGraveTool(SC, actor)
    for _, record in ipairs((SC.Logistics.audit(actor) or {}).items or {}) do
        if SC.GameplayUtil.itemHasTag(record.item, "DIG_GRAVE")
            and (tonumber(call(record.item, "getCondition")) or 1) > 0 then return record.item end
    end
    return nil
end

local function cargoProtection(SC, fixture, item, category)
    local actor = fixture.actor
    if item == fixture.graveTool then return "grave_tool" end
    if item == call(actor, "getPrimaryHandItem") or item == call(actor, "getSecondaryHandItem")
        or call(actor, "isEquippedClothing", item) == true or call(item, "isEquipped") == true
        or (tonumber(call(item, "getAttachedSlot")) or -1) >= 0 then return "equipped" end
    if call(item, "isFavorite") == true then return "favorite" end
    if call(item, "getInventory") ~= nil or category == "container" then return "bag" end
    -- The real surplus selector already retains the role's food, water,
    -- medicine and clothing minimums. Additional category-wide exclusions
    -- would prevent it from shelving a genuinely spare unworn garment.
    local keyId = tonumber(call(item, "getKeyId"))
    if keyId and keyId ~= -1 or call(item, "isKeyRing") == true then return "key" end
    if SC.PersonalItems and SC.PersonalItems.isProtected(item, actor, "loadout") then return "personal" end
    if SC.WorkTransport then
        local protected, reason = SC.WorkTransport.foreignProtected(item, actor)
        if protected then return "owned:" .. tostring(reason) end
    end
    return nil
end

local function existingCargoContainer(SC, fixture, item)
    local best, bestObject, bestDistance
    local bx, by, bz = position(fixture.body.square)
    for _, square in ipairs(fixture.survey.ordered) do
        local x, y, z = position(square)
        local distance = math.max(math.abs(x - bx), math.abs(y - by))
        if z == bz and sourceTile(SC, square) then
            local objects = call(square, "getObjects")
            for index = 0, (tonumber(call(objects, "size")) or 0) - 1 do
                local object = objects:get(index)
                local container = call(object, "getContainer")
                if container and call(container, "hasRoomFor", fixture.actor, item) == true
                    and (bestDistance == nil or distance < bestDistance) then
                    best, bestObject, bestDistance = container, object, distance
                end
            end
        end
    end
    return best, bestObject
end

-- Isolate the existing haul task from the seed's unrelated shelving trip.
-- Move only the real Logistics-selected surplus and retain its exact identity
-- and source container. No world object, carry limit or Decision score changes.
local function prepareHaulCargo(SC, fixture)
    fixture.stagedCargo = {}
    for _ = 1, 32 do
        SC.Logistics.reset(fixture.actor)
        local audit = SC.Logistics.status(fixture.actor) or {}
        if audit.surplus == nil then
            print("SC_REAL_SANDBOX|OFFICE_LOAD_STAGE|cargoPrepared " .. loadSummary(SC, fixture.actor))
            return true, "exactSurplusItemsStaged=" .. tostring(#fixture.stagedCargo)
                .. " noStorageSurplus=true shouldManage=" .. tostring(audit.shouldManage)
                .. " localPackMove=" .. tostring(audit.packMove ~= nil)
                .. " localClothingUpgrade=" .. tostring(audit.clothingUpgrade ~= nil)
                .. " localBagUpgrade=" .. tostring(audit.bagUpgrade ~= nil)
                .. " equippedPersonalBagsProtected=true roleMinimumsSelectedByLogistics=true"
                .. " existingWorldContainersOnly=true"
        end
        local surplus = audit.surplus
        if not surplus or not surplus.item or not surplus.source then
            return false, "remainingManagementIsNotLooseSurplus " .. loadSummary(SC, fixture.actor)
        end
        local item = surplus.item
        local protection = cargoProtection(SC, fixture, item, surplus.category)
        if protection then
            return false, "selectedSurplusProtected=" .. protection .. " " .. loadSummary(SC, fixture.actor)
        end
        local destination, object = existingCargoContainer(SC, fixture, item)
        if not destination then
            return false, "noExistingNativeContainerWithRoom " .. loadSummary(SC, fixture.actor)
        end
        local moved, reason = SC.GameplayUtil.transferItemVerified(surplus.source, destination, item)
        if moved ~= true then return false, "exactSurplusTransferFailed=" .. tostring(reason) end
        fixture.stagedCargo[#fixture.stagedCargo + 1] = { item = item, source = surplus.source,
            destination = destination, object = object }
        print("SC_REAL_SANDBOX|OFFICE_CARGO_STAGED|item=" .. SC.GameplayUtil.itemType(item)
            .. " id=" .. tostring(call(item, "getID")) .. " category=" .. tostring(surplus.category)
            .. " originalContainer=" .. tostring(surplus.source) .. " nativeDestination=" .. tostring(destination)
            .. " destinationAt=" .. at(call(object, "getSquare"))
            .. " sourceAbsent=" .. tostring(not SC.GameplayUtil.inventoryContains(surplus.source, item))
            .. " destinationContainsExact=" .. tostring(SC.GameplayUtil.inventoryContains(destination, item)))
    end
    return false, "surplusPreparationBound32 " .. loadSummary(SC, fixture.actor)
end

local function graveOn(SC, square, spriteType)
    local objects = call(square, "getSpecialObjects")
    for index = 0, (tonumber(call(objects, "size")) or 0) - 1 do
        local object = objects:get(index)
        local data = SC.GameplayUtil.modData(object)
        if SC.GameplayUtil.instanceOf(object, "IsoThumpable")
            and call(object, "getName") == "EmptyGraves" and type(data) == "table"
            and data.spriteType == spriteType and (tonumber(data.corpses) or 0) == 0
            and data.filled ~= true and data[SC.Production.FALLEN_NAME] == nil then return object end
    end
    return nil
end

local function emptyGraveIn(SC, zone)
    for y = zone.y1, zone.y2 do
        for x = zone.x1, zone.x2 do
            local square = SC.GameplayUtil.gridSquare(x, y, zone.z)
            local object = graveOn(SC, square, "sprite1")
            if object then
                local north = call(object, "getNorth") == true
                local partnerSquare = SC.GameplayUtil.gridSquare(x - (north and 0 or 1),
                    y - (north and 1 or 0), zone.z)
                local partner = graveOn(SC, partnerSquare, "sprite2")
                if partnerSquare and inside(zone, partnerSquare) and partner then
                    return object, partner, square, partnerSquare
                end
            end
        end
    end
    return nil
end

-- ISEmptyGraves:create is the completion body of the game's normal dig build
-- action. Run it once on validated existing ground so this probe measures the
-- office haul, without first sending the worker away to dig capacity. Reject
-- removable decoration too: create must add its two native grave objects
-- without removing any pre-existing map object.
local function ensureEmptyGrave(SC, fixture, tool)
    local primary, secondary, square, partnerSquare = emptyGraveIn(SC, fixture.zone)
    if primary then return true, "existing native empty grave at=" .. at(square) end
    if type(ISEmptyGraves) ~= "table" or type(ISEmptyGraves.new) ~= "function" then
        return false, "native ISEmptyGraves builder unavailable"
    end
    local made, builder = pcall(ISEmptyGraves.new, ISEmptyGraves,
        "location_community_cemetary_01_33", "location_community_cemetary_01_32",
        "location_community_cemetary_01_34", "location_community_cemetary_01_35", tool)
    if not made or type(builder) ~= "table" then return false, "builder=" .. tostring(builder) end
    builder.character, builder.player, builder.north = fixture.actor,
        call(fixture.actor, "getPlayerNum"), false
    local function untouchedGround(tile)
        if tile == nil or roomKey(tile) ~= OUTSIDE or not SC.GameplayUtil.isSquareFree(tile) then
            return false
        end
        local objects = call(tile, "getObjects")
        for index = 0, (tonumber(call(objects, "size")) or 0) - 1 do
            local object = objects:get(index)
            local properties = call(object, "getProperties")
            if properties and properties:has(IsoFlagType.canBeRemoved) then return false end
            if call(object, "getName") == "EmptyGraves" then return false end
        end
        return true
    end
    local zone = fixture.zone
    for y = zone.y1, zone.y2 do
        for x = zone.x1 + 1, zone.x2 do
            square = SC.GameplayUtil.gridSquare(x, y, zone.z)
            partnerSquare = SC.GameplayUtil.gridSquare(x - 1, y, zone.z)
            if untouchedGround(square) and untouchedGround(partnerSquare) then
                local valid, accepted = pcall(builder.isValid, builder, square)
                if valid and accepted == true then
                    local before = (tonumber(call(call(square, "getObjects"), "size")) or 0)
                        + (tonumber(call(call(partnerSquare, "getObjects"), "size")) or 0)
                    local oldPrimary = call(fixture.actor, "getPrimaryHandItem")
                    local oldSecondary = call(fixture.actor, "getSecondaryHandItem")
                    call(fixture.actor, "setPrimaryHandItem", tool)
                    call(fixture.actor, "setSecondaryHandItem", tool)
                    local created, reason = pcall(builder.create, builder, x, y, zone.z,
                        false, "location_community_cemetary_01_33")
                    call(fixture.actor, "setPrimaryHandItem", oldPrimary)
                    call(fixture.actor, "setSecondaryHandItem", oldSecondary)
                    primary, secondary = graveOn(SC, square, "sprite1"),
                        graveOn(SC, partnerSquare, "sprite2")
                    local after = (tonumber(call(call(square, "getObjects"), "size")) or 0)
                        + (tonumber(call(call(partnerSquare, "getObjects"), "size")) or 0)
                    if not created or primary == nil or secondary == nil or after ~= before + 2 then
                        return false, "native create=" .. tostring(created) .. "/" .. tostring(reason)
                            .. " primary=" .. tostring(primary ~= nil) .. " partner="
                            .. tostring(secondary ~= nil) .. " objectCounts=" .. before .. ">" .. after
                    end
                    fixture.grave, fixture.graveSquare = primary, square
                    return true, "native ISEmptyGraves:create completed at=" .. at(square)
                        .. " partner=" .. at(partnerSquare)
                        .. " spriteTypes=sprite1/sprite2 corpses=0/0 filled=false/false"
                        .. " preExistingObjectsRetained=true objectCounts=" .. before .. ">" .. after
                end
            end
        end
    end
    return false, "no untouched native-valid two-tile grave site in burial zone=" .. tostring(zone.id)
end

local function restore(fixture)
    if not fixture then return end
    if fixture.originalDecision then SurvivorCompanion.Decision.update = fixture.originalDecision end
    for index = #(fixture.stagedCargo or {}), 1, -1 do
        local row = fixture.stagedCargo[index]
        local restored, reason = SurvivorCompanion.GameplayUtil.transferItemVerified(
            row.destination, row.source, row.item)
        print("SC_REAL_SANDBOX|OFFICE_CARGO_RESTORED|ok=" .. tostring(restored)
            .. " item=" .. SurvivorCompanion.GameplayUtil.itemType(row.item)
            .. " id=" .. tostring(call(row.item, "getID")) .. " reason=" .. tostring(reason)
            .. " originalContainsExact="
            .. tostring(SurvivorCompanion.GameplayUtil.inventoryContains(row.source, row.item)))
    end
    if fixture.savedCommand then
        local commands = SurvivorCompanion.Commands
        local state = commands.peek(fixture.actor)
        for field in pairs(state) do state[field] = nil end
        for field, value in pairs(fixture.savedCommand) do state[field] = value end
        local restored, reason = commands.persist(fixture.actor)
        print("SC_REAL_SANDBOX|OFFICE_COMMAND_RESTORED|ok=" .. tostring(restored)
            .. " order=" .. tostring(state.order) .. " reason=" .. tostring(reason))
    end
    for _, row in ipairs(fixture.pausedOrders or {}) do
        for _, field in ipairs({ "state", "blocker", "retryAt", "updatedAt" }) do
            row.order[field] = row.values[field]
        end
        for _, saved in ipairs(row.jobs) do
            for _, field in ipairs({ "state", "reservedBy", "leaseUntil", "blocker", "retryAt",
                "priority", "updatedAt" }) do saved.job[field] = saved.values[field] end
        end
    end
    for _, row in ipairs(fixture.excluded or {}) do row.data[row.tag] = row.previous end
end

local function pauseOtherCollections(SC, fixture)
    fixture.pausedOrders = {}
    local base = SC.BaseLife.active()
    for _, order in ipairs(SC.BaseLife.productionOrders(true) or {}) do
        local assigned = false
        for _, id in ipairs(order.workers or {}) do if id == fixture.id then assigned = true end end
        if assigned and order.operation == "collect_bodies" and order.state ~= "completed"
            and order.state ~= "cancelled" and order.state ~= "paused" then
            local saved = { order = order, values = { state = order.state, blocker = order.blocker,
                retryAt = order.retryAt, updatedAt = order.updatedAt }, jobs = {} }
            for _, job in ipairs(base.jobs or {}) do
                if job.type == "production" and type(job.target) == "table"
                    and job.target.orderId == order.id then
                    saved.jobs[#saved.jobs + 1] = { job = job, values = { state = job.state,
                        reservedBy = job.reservedBy, leaseUntil = job.leaseUntil, blocker = job.blocker,
                        retryAt = job.retryAt, priority = job.priority, updatedAt = job.updatedAt } }
                end
            end
            local paused, reason = SC.BaseLife.pauseProductionOrder(order.id, "office_haul_probe_other_collection")
            if paused ~= true then return false, "order=" .. tostring(order.id) .. " reason=" .. tostring(reason) end
            fixture.pausedOrders[#fixture.pausedOrders + 1] = saved
            print("SC_REAL_SANDBOX|OFFICE_PAUSED_COLLECTION|order=" .. tostring(order.id)
                .. " priorState=" .. tostring(saved.values.state) .. " assignedWorker=" .. fixture.id
                .. " workerCount=" .. tostring(#(order.workers or {})))
        end
    end
    return true, "pausedOtherAssignedCollections=" .. tostring(#fixture.pausedOrders)
end

local function recordDecision(SC, fixture, timestamp, handled, reason)
    fixture.decisionCount = (fixture.decisionCount or 0) + 1
    if fixture.lastDecisionAt then
        fixture.decisionIntervalTotal = (fixture.decisionIntervalTotal or 0)
            + math.max(0, timestamp - fixture.lastDecisionAt)
    end
    fixture.lastDecisionAt, fixture.lastHandled = timestamp, handled
    if reason ~= fixture.lastReason then
        fixture.lastReason = reason
        fixture.sequence[#fixture.sequence + 1] = tostring(reason) .. "@" .. at(fixture.actor)
        if #fixture.sequence > 50 then table.remove(fixture.sequence, 1) end
    end
    local job = SC.BaseLife.jobFor(fixture.id)
    fixture.currentJob = job
    local orderId = job and type(job.target) == "table" and job.target.orderId or nil
    if job and job.type == "production" and fixture.order and orderId == fixture.order.id then
        fixture.fixtureOrderSelected = true
        fixture.orderSelectedAt = fixture.orderSelectedAt or timestamp
    end
end

local function finish(H, fixture, current, result, setPhase, success, name, detail)
    screenshot(H, success and "complete" or "failed")
    result(success and "PASS" or "FAIL", name, detail)
    restore(fixture)
    setPhase("finish", current)
end

local function stageAtTileCenter(actor, square)
    local x, y, z = position(square)
    if x == nil then return false, "stage square missing" end
    -- Native teleportTo(float,float,int) floors its horizontal arguments in
    -- 42.21. Validate the intended centre before completing that placement;
    -- otherwise a corner can overlap furniture despite the tile being free.
    actor:teleportTo(x, y, z)
    local tx, ty = x + 0.5, y + 0.5
    local stands = call(actor, "canStandAt", tx, ty, z) == true
    local clear = call(actor, "isCompanionMovementClear", tx, ty, z) == true
    if not stands or not clear then
        return false, "native center check stand=" .. tostring(stands) .. " sweep=" .. tostring(clear)
            .. " center=" .. key(tx, ty, z) .. " nativeTeleport=" .. at(actor)
    end
    actor:setX(tx)
    actor:setY(ty)
    actor:setNextX(tx)
    actor:setNextY(ty)
    actor:setLastX(tx)
    actor:setLastY(ty)
    actor:ensureOnTile()
    local ax, ay, az = position(actor)
    local actualSquare = call(actor, "getCurrentSquare")
    local correct = ax ~= nil and math.abs(ax - tx) <= 0.02 and math.abs(ay - ty) <= 0.02
        and math.floor(az or 0) == math.floor(z or 0)
    return correct, "centerValidated=true positioned=" .. at(actor)
        .. " immediateSameSquare=" .. tostring(actualSquare == square)
        .. " physicalSquareVerification=pending_native_frames"
end

local function setup(H, SC, current, check, result, setPhase)
    if current - H.phaseStartedAt < 6000 then return end
    local base = SC.BaseLife.active()
    if not check("office_haul_base", base ~= nil, tostring(base and base.name)) then
        setPhase("finish", current) return
    end
    local survey = surveyMap(SC, base)
    printSurvey(survey, result)
    local actor, id, name = chooseWorker(SC)
    result(actor and "PASS" or "FAIL", "office_haul_restored_worker",
        "preferred=Jill selected=" .. tostring(name) .. " id=" .. tostring(id))
    local body, source = chooseBody(SC, survey, actor)
    local depth = body and survey.distance[body.room]
    result(body and "PASS" or "FAIL", "office_haul_office_source_ready",
        "source=" .. tostring(source) .. " tile=" .. tostring(body and at(body.square))
            .. " room=" .. tostring(body and body.room) .. " roomName="
            .. tostring(body and survey.rooms[body.room] and survey.rooms[body.room].name)
            .. " minimumDoorsOutside=" .. tostring(depth) .. " requiredActualCrossings=3")
    if H.config.office_haul_survey_only == "true" then
        screenshot(H, "survey")
        setPhase("finish", current) return
    end
    if actor == nil or body == nil then setPhase("finish", current) return end
    local zone, zoneReason = burialZone(SC, base, survey)
    if not check("office_haul_burial_plot", zone ~= nil, tostring(zoneReason)) then
        setPhase("finish", current) return
    end
    if body.body == nil then
        local x, y, z = position(body.square)
        local zombie = type(createZombie) == "function" and createZombie(x + 0.5, y + 0.5, z, nil, 0, IsoDirections.S)
        local ok, corpse = pcall(function() return zombie and IsoDeadBody.new(zombie, false) end)
        if not check("office_haul_native_corpse", ok and corpse ~= nil, tostring(corpse)) then
            setPhase("finish", current) return
        end
        body.body = corpse
    end
    local fixture = { actor = actor, id = id, name = name, body = body, zone = zone,
        survey = survey, crossed = {}, crossings = 0, excluded = {}, startedAt = current,
        state = {}, runtime = {}, sequence = {} }
    H.officeHaul = fixture
    fixture.savedCommand = SC.GameplayUtil.copyShallow(SC.Commands.peek(actor))
    local paused, pausedReason = pauseOtherCollections(SC, fixture)
    if not check("office_haul_other_collections_paused", paused, pausedReason) then
        restore(fixture) setPhase("finish", current) return
    end
    -- Keep the selected body first in the unmodified production source scan.
    -- Exclusions are reversible tags on the clone's other bodies, never removal.
    for _, row in ipairs(survey.bodies) do
        if row.body ~= body.body then
            local data = SC.GameplayUtil.modData(row.body)
            if type(data) == "table" and data[SC.Production.BURNED_TAG] == nil then
                fixture.excluded[#fixture.excluded + 1] = { data = data,
                    tag = SC.Production.BURNED_TAG, previous = nil }
                data[SC.Production.BURNED_TAG] = "office_haul_probe_excluded"
            end
        end
    end
    if SC.Downtime then SC.Downtime.cancel(actor, "office_haul_probe") end
    if SC.BaseWork then SC.BaseWork.cancel(actor, "office_haul_probe") end
    local cancelled, cancelReason = SC.Decision.cancelWork(actor, "office_haul_probe_prerequisite")
    if not check("office_haul_retained_decision_work_cancelled", cancelled == true, tostring(cancelReason)) then
        restore(fixture) setPhase("finish", current) return
    end
    local commanded, commandReason = SC.Commands.issue(id, "base_duty", nil, H.player)
    local command = SC.Commands.peek(actor)
    if not check("office_haul_real_base_duty_command", commanded == true
        and command and command.order == "base_duty", "previous=" .. tostring(fixture.savedCommand.order)
            .. " current=" .. tostring(command and command.order) .. " reason=" .. tostring(commandReason)) then
        restore(fixture) setPhase("finish", current) return
    end
    if SC.Navigation and SC.Navigation.cancel then SC.Navigation.cancel(actor, "office_haul_probe") end
    print("SC_REAL_SANDBOX|OFFICE_LOAD_STAGE|beforeGraveFixture " .. loadSummary(SC, actor))
    local inventory = call(actor, "getInventory")
    local openGrave = emptyGraveIn(SC, fixture.zone)
    local shovel = carriedGraveTool(SC, actor)
    local fixtureShovel
    if not openGrave and shovel == nil then
        fixtureShovel = inventory and call(inventory, "AddItem", "Base.Shovel")
        shovel = fixtureShovel
    end
    fixture.graveTool = fixtureShovel == nil and shovel or nil
    if not check("office_haul_native_shovel", openGrave ~= nil or shovel ~= nil,
        "existingOpenGrave=" .. tostring(openGrave ~= nil) .. " tool=" .. tostring(shovel)
            .. " fixtureCreated=" .. tostring(fixtureShovel ~= nil)) then
        restore(fixture) setPhase("finish", current) return
    end
    local capacity, capacityReason = ensureEmptyGrave(SC, fixture, shovel)
    if not check("office_haul_native_empty_grave_capacity", capacity, capacityReason) then
        restore(fixture) setPhase("finish", current) return
    end
    -- This is a hauling/drop probe with capacity already dug. A tool made
    -- solely for that native fixture must not turn its carrier into a new
    -- Logistics surplus case. Existing carried tools stay exactly where they were.
    if fixtureShovel then
        inventory:Remove(fixtureShovel)
        if not check("office_haul_fixture_shovel_removed", not SC.GameplayUtil.inventoryContains(inventory, fixtureShovel),
            "exactFixtureItem=" .. tostring(call(fixtureShovel, "getID")) .. " existingToolsUntouched=true") then
            restore(fixture) setPhase("finish", current) return
        end
        SC.Logistics.reset(actor)
    end
    print("SC_REAL_SANDBOX|OFFICE_LOAD_STAGE|afterGraveFixture " .. loadSummary(SC, actor))
    local prepared, prepareReason = prepareHaulCargo(SC, fixture)
    if not check("office_haul_cargo_prepared", prepared == true, prepareReason) then
        restore(fixture) setPhase("finish", current) return
    end
    -- Hold only the chosen worker during placement. Once its real production
    -- order exists, ordinary Decision.update and scheduler cadence own the job.
    fixture.originalDecision = SC.Decision.update
    SC.Decision.update = function(other, player, runtime, roundTimestamp)
        if other == actor and H.phase ~= "office_haul_run" then
            return true, "office_haul_probe_staging"
        end
        local handled, reason = fixture.originalDecision(other, player, runtime, roundTimestamp)
        if other == actor then
            fixture.lastRuntime = runtime
            recordDecision(SC, fixture, tonumber(roundTimestamp) or SC.GameplayUtil.nowMs(), handled, reason)
        end
        return handled, reason
    end
    local stand = standBeside(SC, body.square)
    local placeOk, placed, reason = pcall(stageAtTileCenter, actor, stand)
    if not check("office_haul_worker_center_requested", placeOk and placed == true,
        tostring(placeOk and reason or placed) .. " at=" .. at(actor)) then
        restore(fixture) setPhase("finish", current) return
    end
    -- Put the observer in clear floor in the same room, without moving a resident.
    local bx, by = position(body.square)
    for _, square in ipairs((survey.rooms[body.room] or {}).squares or {}) do
        local x, y, z = position(square)
        if math.max(math.abs(x - bx), math.abs(y - by)) >= 3
            and SC.GameplayUtil.isSquareFree(square) then
            pcall(function() H.player:teleportTo(x + 0.5, y + 0.5, z) end)
            break
        end
    end
    fixture.stand, fixture.stagedAt = stand, current
    setPhase("office_haul_staged", current)
end

local function staged(H, SC, current, check, result, setPhase)
    local fixture = H.officeHaul
    if not fixture then setPhase("finish", current) return end
    -- teleportTo and ensureOnTile retain an already non-null current pointer.
    -- Give normal engine physics at least 250ms to reconcile it, then require
    -- the same centre, floor and physical square before production can begin.
    local elapsed = current - fixture.stagedAt
    if elapsed < 250 then return end
    local actor, stand = fixture.actor, fixture.stand
    local x, y, z = position(stand)
    local ax, ay, az = position(actor)
    local actualSquare = call(actor, "getCurrentSquare")
    local stands = call(actor, "canStandAt", x + 0.5, y + 0.5, z) == true
    local correct = ax ~= nil and math.abs(ax - x - 0.5) <= 0.02
        and math.abs(ay - y - 0.5) <= 0.02 and math.floor(az or 0) == math.floor(z or 0)
        and actualSquare == stand and stands
    if not correct and elapsed < 2000 then return end
    if not check("office_haul_worker_staged", correct,
        "afterNativeMs=" .. elapsed .. " at=" .. at(actor) .. " expected="
            .. key(x + 0.5, y + 0.5, z) .. " currentSquare=" .. at(actualSquare)
            .. " sameSquare=" .. tostring(actualSquare == stand) .. " canStand=" .. tostring(stands)) then
        restore(fixture) setPhase("finish", current) return
    end
    local available = emptyGraveIn(SC, fixture.zone)
    if not check("office_haul_empty_grave_still_available", available ~= nil,
        "nativeEmptyGrave=" .. tostring(available)) then
        restore(fixture) setPhase("finish", current) return
    end
    local zone, body = fixture.zone, fixture.body
    local made, order = SC.BaseLife.createProductionOrder({ operation = "collect_bodies",
        zoneId = zone.id, requested = 1, workers = { fixture.id },
        settings = { fromCamp = true, fromLumber = true, withBelongings = true } })
    if not check("office_haul_native_production_order", made == true,
        tostring(made and order.id or order)) then
        restore(fixture) setPhase("finish", current) return
    end
    fixture.order = order
    fixture.startedAt = current
    for _, job in ipairs((SC.BaseLife.active() or {}).jobs or {}) do
        if job.type == "production" and job.assignedId == fixture.id
            and type(job.target) == "table" and job.target.orderId == order.id then
            job.priority = 5
            fixture.job = job
            break
        end
    end
    if not check("office_haul_actual_runtime_job", fixture.job ~= nil,
        "order=" .. tostring(order.id) .. " job=" .. tostring(fixture.job and fixture.job.id)
            .. " priority=" .. tostring(fixture.job and fixture.job.priority)) then
        restore(fixture) setPhase("finish", current) return
    end
    result("PASS", "office_haul_isolation", "realDecisionPipeline=true decisionCadenceUnmodified=true"
        .. " otherNPCsUntouched=true pausedOtherCollections=" .. #(fixture.pausedOrders or {})
        .. " excludedBodyTags=" .. #fixture.excluded .. " body=" .. at(body.body)
        .. " minimumDoorsOutside=" .. tostring(fixture.survey.distance[body.room])
        .. " burial=" .. key(zone.x1, zone.y1, zone.z)
        .. "-" .. key(zone.x2, zone.y2, zone.z) .. " order=" .. tostring(order.id))
    screenshot(H, "staged")
    setPhase("office_haul_run", current)
end

local function crossedDoor(row, px, py, x, y)
    local first, second = row.north and py or px, row.north and y or x
    local boundary = row.north and row.y or row.x
    if (first < boundary and second >= boundary) or (first >= boundary and second < boundary) then
        local fraction = (boundary - first) / (second - first)
        local along = row.north and (px + (x - px) * fraction) or (py + (y - py) * fraction)
        local low = row.north and row.x or row.y
        return along >= low and along <= low + 1
    end
    return false
end

local function trace(SC, fixture)
    local actor = fixture.actor
    local nav = SC.Navigation.status(actor) or {}
    local state = SC.Navigation.peek(actor) or {}
    local behavior = call(actor, "getPathFindBehavior2")
    local nextPoint = "unavailable"
    pcall(function()
        nextPoint = tostring(behavior.pathNextIsSet) .. ":" .. tostring(behavior.pathNextX)
            .. "," .. tostring(behavior.pathNextY)
    end)
    local target = call(actor, "getGrapplingTarget")
    local job = SC.BaseLife.jobFor(fixture.id)
    local jobOrder = job and type(job.target) == "table" and job.target.orderId or nil
    local decisionMean = (fixture.decisionCount or 0) > 1
        and (fixture.decisionIntervalTotal or 0) / (fixture.decisionCount - 1) or 0
    local decision = SC.Decision.peek(actor) or {}
    local commands = SC.Commands.peek(actor) or {}
    local downtime = SC.Downtime and SC.Downtime.peek(actor) or {}
    local cached = SC.Senses.cached(actor, fixture.lastRuntime)
    local defaultCached = SC.Senses.cached(actor)
    local complete, completeReason = SC.Senses.isCompleteObservation(cached, 1500)
    local observedAge = cached and tonumber(cached.time)
        and math.max(0, SC.GameplayUtil.nowMs() - cached.time) or nil
    local native = cached and cached.nativeDiscovery or {}
    return "at=" .. at(actor) .. " room=" .. roomKey(SC.GameplayUtil.squareOf(actor))
        .. " dragging=" .. tostring(call(actor, "isDraggingCorpse"))
        .. " owner=" .. tostring(call(actor, "getCompanionMovementOwner"))
        .. " moving=" .. tostring(call(actor, "isMoving"))
        .. " pending=" .. tostring(call(actor, "hasPendingMovement"))
        .. " blockMove=" .. tostring(call(actor, "isBlockMovement"))
        .. " ignoreMove=" .. tostring(call(actor, "isIgnoreMovement"))
        .. " collision=" .. tostring(call(actor, "isCollidedThisFrame"))
        .. "/door=" .. tostring(call(actor, "isCollidedWithDoor"))
        .. "/polygon=" .. tostring(call(actor, "isCollidedWithPolygon"))
        .. " forward=" .. tostring(call(actor, "getForwardDirectionX"))
        .. "," .. tostring(call(actor, "getForwardDirectionY"))
        .. " grappleAt=" .. at(target)
        .. " fsm=" .. tostring(call(actor, "getCurrentState"))
        .. " action=" .. tostring(call(actor, "getCompanionActionStateName"))
        .. " anim=" .. tostring(call(actor, "getCompanionActiveAnimationNames"))
        .. " path=" .. tostring(call(actor, "getCompanionPathStatus"))
        .. " waypoint=" .. nextPoint
        .. " doorHolds=" .. tostring(call(actor, "getCompanionPathDoorHolds"))
        .. " nav=" .. tostring(nav.phase) .. "/" .. tostring(nav.pathReason)
        .. "/" .. tostring(nav.lastMovementReason) .. " target=" .. tostring(nav.target)
        .. " searchAgeMs=" .. tostring(nav.pathSearchAgeMs)
        .. " searchYield=" .. tostring(nav.pathSearchYieldReason or state.pathSearchYieldReason)
        .. " searchSliceBudgetMs=" .. tostring(nav.searchSliceBudgetMs)
        .. " searchSliceBudgetReason=" .. tostring(nav.searchSliceBudgetReason)
        .. " expandedNodes=" .. tostring(nav.expandedNodes or state.expandedNodes)
        .. " lastPlanDurationMs=" .. tostring(nav.lastPlanDurationMs or state.lastPlanDurationMs)
        .. " routeReplanCount=" .. tostring(nav.routeReplanCount or state.routeReplanCount)
        .. " searchKey=" .. tostring(state.pathSearch and state.pathSearch.key)
        .. " searchStartedAt=" .. tostring(state.pathSearch and state.pathSearch.startedAt)
        .. " routeRestartCount=" .. tostring(state.routeRestartCount)
        .. " lastRouteRestartReason=" .. tostring(state.lastRouteRestartReason)
        .. " stuck=" .. tostring(nav.stuckAttempts)
        .. " lease=" .. tostring(state.nativeLease and state.nativeLease.affordance)
        .. " reason=" .. tostring(fixture.lastReason)
        .. " workerPhase=" .. tostring(SC.Production.workerPhase(fixture.order.id, fixture.id))
        .. " order=" .. tostring(fixture.order.state) .. "/" .. tostring(fixture.order.blocker)
        .. " actualJob=" .. tostring(job and job.id) .. "/" .. tostring(job and job.type)
        .. "/order=" .. tostring(jobOrder) .. "/state=" .. tostring(job and job.state)
        .. " selectedFixtureOrder=" .. tostring(fixture.fixtureOrderSelected == true)
        .. " decisionCalls=" .. tostring(fixture.decisionCount or 0)
        .. " decisionMeanMs=" .. string.format("%.1f", decisionMean)
        .. " decisionHandled=" .. tostring(fixture.lastHandled)
        .. " decisionCurrent=" .. tostring(decision.current) .. "/key=" .. tostring(decision.currentKey)
        .. "/intent=" .. tostring(decision.intent)
        .. " command=" .. tostring(commands.order)
        .. " downtime=" .. tostring(downtime.active and downtime.active.kind)
        .. " fatigue=" .. tostring(SC.GameplayUtil.characterStatValue(actor, "FATIGUE", -1))
        .. " runtimeSenses=" .. tostring(cached ~= nil) .. "/defaultCached=" .. tostring(defaultCached ~= nil)
        .. "/valid=" .. tostring(cached and cached.valid)
        .. "/complete=" .. tostring(complete) .. "/reason=" .. tostring(completeReason)
        .. "/ageMs=" .. tostring(observedAge)
        .. "/scan=" .. tostring(cached and cached.scanComplete)
        .. "/discovery=" .. tostring(cached and cached.scanDiscoveryComplete)
        .. "/visual=" .. tostring(cached and cached.scanVisualComplete)
        .. "/nativeComplete=" .. tostring(native.complete)
        .. "/nativeFresh=" .. tostring(native.freshComplete)
        .. " load={" .. loadSummary(SC, actor) .. "}"
        .. " crossings=" .. tostring(fixture.crossings)
end

local function bodyAtDestination(SC, fixture)
    local zone = fixture.zone
    for y = zone.y1, zone.y2 do
        for x = zone.x1, zone.x2 do
            local square = SC.GameplayUtil.gridSquare(x, y, zone.z)
            local found
            SC.GameplayUtil.squareStaticMovingObjects(square, function(object)
                if SC.GameplayUtil.instanceOf(object, "IsoDeadBody") then
                    local data = SC.GameplayUtil.modData(object)
                    if object == fixture.body.body or (fixture.tag ~= nil and type(data) == "table"
                        and data[SC.Production.HAUL_TAG] == fixture.tag) then found = object return false end
                end
            end, 64)
            if found then return found, square end
        end
    end
    return nil
end

local function run(H, SC, current, check, result, setPhase)
    local fixture = H.officeHaul
    if not fixture then setPhase("finish", current) return end
    local actor = fixture.actor
    local dragging = call(actor, "isDraggingCorpse") == true
    local x, y, z = position(actor)
    if fixture.previous and dragging and fixture.previous.dragging and x ~= nil
        and math.floor(z or 0) == 0 and math.floor(fixture.previous.z or 0) == 0 then
        for _, row in ipairs(fixture.survey.doors) do
            if not row.destroyed and not fixture.crossed[row.id]
                and crossedDoor(row, fixture.previous.x, fixture.previous.y, x, y) then
                fixture.crossed[row.id] = true
                fixture.crossings = fixture.crossings + 1
                result("PASS", "office_haul_dragged_door_" .. fixture.crossings,
                    "door=" .. row.id .. " rooms=" .. row.first .. ">" .. row.second
                        .. " from=" .. key(fixture.previous.x, fixture.previous.y, 0)
                        .. " to=" .. at(actor) .. " nativeDrag=true")
                screenshot(H, "door-" .. fixture.crossings)
            end
        end
    end
    fixture.previous = { x = x, y = y, z = z, dragging = dragging }
    local bodyData = SC.GameplayUtil.modData(fixture.body.body)
    if type(bodyData) == "table" and bodyData[SC.Production.HAUL_TAG] ~= nil then
        fixture.tag = bodyData[SC.Production.HAUL_TAG]
    end
    if dragging then fixture.everDragged = true end
    local throwing = call(actor, "isGrappleThrowOutWindow") == true
    if throwing or string.find(tostring(fixture.lastReason), "throw", 1, true) then
        finish(H, fixture, current, result, setPhase, false, "office_haul_door_route_only",
            "window throw observed " .. trace(SC, fixture)) return
    end
    if not dragging and fixture.everDragged then
        local body, square = bodyAtDestination(SC, fixture)
        if body then
            check("office_haul_body_in_burial_zone", inside(fixture.zone, square), "body=" .. at(body))
            finish(H, fixture, current, result, setPhase, fixture.crossings >= 3,
                "office_haul_three_doors_complete", "distinctNativeDoors=" .. fixture.crossings
                    .. " body=" .. at(body) .. " held=false windowThrow=false " .. trace(SC, fixture))
            return
        end
    end
    if current >= (fixture.nextTrace or 0) then
        fixture.nextTrace = current + 3000
        print("SC_REAL_SANDBOX|OFFICE_HAUL_TRACE|elapsed=" .. (current - fixture.startedAt)
            .. " " .. trace(SC, fixture))
    end
    if fixture.fixtureOrderSelected and not fixture.selectionReported then
        fixture.selectionReported = true
        result("PASS", "office_haul_runtime_selected_fixture_order", "job="
            .. tostring(fixture.job.id) .. " order=" .. tostring(fixture.order.id)
            .. " afterMs=" .. tostring(fixture.orderSelectedAt - fixture.startedAt))
    elseif not fixture.fixtureOrderSelected and current - fixture.startedAt >= 30000 then
        local downtime = SC.Downtime and SC.Downtime.peek(actor) or {}
        if not fixture.selectionRestWait and downtime.active and downtime.active.kind == "rest_bed" then
            fixture.selectionRestWait = true
            print("SC_REAL_SANDBOX|OFFICE_SELECTION_WAIT|nativeRest=rest_bed"
                .. " selectionDeadlineMs=60000 fatigue="
                .. tostring(SC.GameplayUtil.characterStatValue(actor, "FATIGUE", -1)))
        end
        if fixture.selectionRestWait and current - fixture.startedAt < 60000 then return end
        finish(H, fixture, current, result, setPhase, false, "office_haul_runtime_selected_fixture_order",
            "ordinary Decision did not reserve fixture order; " .. trace(SC, fixture)) return
    end
    if current - fixture.startedAt >= 180000 then
        finish(H, fixture, current, result, setPhase, false, "office_haul_180s_deadline",
            trace(SC, fixture) .. " sequence=" .. table.concat(fixture.sequence, ";")) return
    end
end

function Probe.step(H, current, check, result, setPhase)
    local SC = SurvivorCompanion
    if H.phase == "office_haul_setup" then return setup(H, SC, current, check, result, setPhase) end
    if H.phase == "office_haul_staged" then return staged(H, SC, current, check, result, setPhase) end
    if H.phase == "office_haul_run" then return run(H, SC, current, check, result, setPhase) end
end

return Probe
