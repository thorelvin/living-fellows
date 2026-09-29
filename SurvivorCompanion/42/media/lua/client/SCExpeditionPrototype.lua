-- SPDX-License-Identifier: MIT
-- Disposable single-player expedition prototype; no release packaging yet.
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.ExpeditionPrototype = SC.ExpeditionPrototype or {}
local Expedition = SC.ExpeditionPrototype

local mission
local lastOutcome
local lastDebrief
local reusableSlotSqlId
local holdColdHandoffForTest = false
local TEST_RADIO_CHANNEL = 90000
local TEST_RADIO_PRESET = "Living Fellows Team"
local SEARCH_HOURS = 0.75
local startReturnFromSite
local SUPPLY_CATEGORIES = {
    food = true, water = true, medicine = true, ammunition = true,
    weapon = true, tools = true, construction = true, crafting = true,
    farming = true, clothing = true, container = true, literature = true,
}
local MISSION_DOCTRINES = {
    stealth = true, close_defense = true, weapons_free = true,
}

local function validTile(value)
    return type(value) == "number" and value == value
        and value >= 0 and value <= 30000
        and value == math.floor(value)
end

local function validPoint(point)
    return type(point) == "table" and validTile(point.x)
        and validTile(point.y) and validTile(point.z)
        and point.z <= 16
end

local function copyPoint(point)
    return { x = point.x, y = point.y, z = point.z }
end

local function copyRoadAvoidance(value)
    if value == nil then return nil end
    return { x = value.x, y = value.y, radius = value.radius }
end

local function scoutWorldHour()
    if type(getGameTime) ~= "function" then return nil end
    local ok, gameTime = pcall(getGameTime)
    if not ok or gameTime == nil then return nil end
    local hour, called = SC.GameplayUtil.call(gameTime, "getWorldAgeHours")
    hour = tonumber(hour)
    if called and hour and hour == hour and hour >= 0
        and hour < 100000000 then return hour end
    return nil
end

local function validWorldHour(value)
    return type(value) == "number" and value == value
        and value >= 0 and value < 100000000
end

local function validSite(value)
    if type(value) ~= "table" or type(value.id) ~= "string"
        or #value.id > 64 or type(value.label) ~= "string"
        or #value.label < 1 or #value.label > 64
        or (value.knowledge ~= "player_seen_interior"
            and value.knowledge ~= "map_metadata_unconfirmed")
        or (value.street ~= nil and (type(value.street) ~= "string"
            or #value.street > 128)) then return false end
    local x, y, x2, y2 = string.match(value.id,
        "^(%d+):(%d+):(%d+):(%d+)$")
    x, y, x2, y2 = tonumber(x), tonumber(y), tonumber(x2), tonumber(y2)
    return validTile(x) and validTile(y) and validTile(x2)
        and validTile(y2) and x2 > x and y2 > y
end

local function copySite(value)
    if value == nil then return nil end
    return { id = value.id, label = value.label,
        knowledge = value.knowledge, street = value.street }
end

local function validRequest(value)
    return type(value) == "table"
        and SUPPLY_CATEGORIES[value.category] == true
        and type(value.quantity) == "number"
        and value.quantity >= 1 and value.quantity <= 8
        and value.quantity == math.floor(value.quantity)
end

local function copyRequest(value)
    if value == nil then return nil end
    return { category = value.category, quantity = value.quantity }
end

local function validReceipt(value)
    return type(value) == "table"
        and type(value.id) == "string" and #value.id > 0 and #value.id <= 160
        and type(value.itemType) == "string"
        and #value.itemType > 0 and #value.itemType <= 160
        and type(value.memberId) == "string"
        and #value.memberId > 0 and #value.memberId <= 128
        and (value.sourceObjectIndex == nil
            or (type(value.sourceObjectIndex) == "number"
                and value.sourceObjectIndex >= 0
                and value.sourceObjectIndex <= 65535
                and value.sourceObjectIndex
                    == math.floor(value.sourceObjectIndex)))
        and (value.source == nil or validPoint(value.source))
end

local function copyReceipt(value)
    return { id = value.id, itemType = value.itemType,
        memberId = value.memberId,
        source = value.source and copyPoint(value.source) or nil,
        sourceObjectIndex = value.sourceObjectIndex }
end

local function validReceipts(values)
    if type(values) ~= "table" or #values > 16 then return false end
    local seen = {}
    for _, value in ipairs(values) do
        if not validReceipt(value) or seen[value.id] then return false end
        seen[value.id] = true
    end
    return true
end

local function copyReceipts(values)
    local result = {}
    for index, value in ipairs(values or {}) do
        result[index] = copyReceipt(value)
    end
    return result
end

local function validSearch(value)
    return type(value) == "table" and validRequest(value.request)
        and validReceipts(value.acquisitions)
        and type(value.radius) == "number"
        and value.radius >= 2 and value.radius <= 8
        and value.radius == math.floor(value.radius)
        and (value.startedHour == nil or (type(value.startedHour) == "number"
            and value.startedHour >= 0 and value.startedHour < 100000000))
        and (value.deadlineHour == nil or (type(value.deadlineHour) == "number"
            and value.deadlineHour >= 0 and value.deadlineHour < 100000000))
        and (value.startedHour == nil or value.deadlineHour ~= nil)
        and (value.deadlineHour == nil or value.startedHour ~= nil)
        and (value.endReason == nil or (type(value.endReason) == "string"
            and #value.endReason <= 64))
end

local function copySearch(value)
    if value == nil then return nil end
    return {
        request = copyRequest(value.request),
        acquisitions = copyReceipts(value.acquisitions),
        radius = value.radius,
        startedHour = value.startedHour,
        deadlineHour = value.deadlineHour,
        endReason = value.endReason,
    }
end

local function validObservation(value)
    return type(value) == "table"
        and (value.status == "complete" or value.status == "partial"
            or value.status == "unavailable")
        and validPoint(value.at)
        and type(value.worldHour) == "number"
        and value.worldHour == value.worldHour
        and value.worldHour >= 0 and value.worldHour < 100000000
        and type(value.scannedSquares) == "number"
        and value.scannedSquares >= 0 and value.scannedSquares <= 10000
        and value.scannedSquares == math.floor(value.scannedSquares)
        and type(value.visibleSquares) == "number"
        and value.visibleSquares >= 0 and value.visibleSquares <= 9
        and value.visibleSquares == math.floor(value.visibleSquares)
        and (value.status == "unavailable"
            or value.visibleSquares >= 1)
        and (value.visibleThreats == nil
            or (type(value.visibleThreats) == "number"
                and value.visibleThreats >= 0 and value.visibleThreats <= 128
                and value.visibleThreats == math.floor(value.visibleThreats)))
end

local function copyObservation(value)
    if value == nil then return nil end
    return {
        status = value.status, at = copyPoint(value.at),
        worldHour = value.worldHour,
        scannedSquares = value.scannedSquares,
        visibleSquares = value.visibleSquares,
        visibleThreats = value.visibleThreats,
    }
end

local function copyDebrief(value)
    if value == nil then return nil end
    if value.kind == "search" then
        local returned = {}
        for index, id in ipairs(value.returnedIds or {}) do returned[index] = id end
        return {
            kind = "search", destination = copyPoint(value.destination),
            returnPoint = copyPoint(value.returnPoint),
            request = copyRequest(value.request),
            acquisitions = copyReceipts(value.acquisitions),
            returnedIds = returned, endReason = value.endReason,
            inventoryComplete = value.inventoryComplete,
            site = copySite(value.site),
        }
    end
    return {
        kind = "scout", destination = copyPoint(value.destination),
        returnPoint = copyPoint(value.returnPoint),
        observation = copyObservation(value.observation),
        endReason = value.endReason,
        site = copySite(value.site),
    }
end

local function validDebrief(value)
    if type(value) == "table" and value.kind == "search" then
        if not validPoint(value.destination)
            or not validPoint(value.returnPoint)
            or not validRequest(value.request)
            or not validReceipts(value.acquisitions)
            or type(value.returnedIds) ~= "table"
            or #value.returnedIds > #value.acquisitions
            or type(value.endReason) ~= "string"
            or #value.endReason > 64
            or type(value.inventoryComplete) ~= "boolean" then return false end
        if value.site ~= nil and not validSite(value.site) then return false end
        local acquired, returned = {}, {}
        for _, receipt in ipairs(value.acquisitions) do
            acquired[receipt.id] = true
        end
        for _, id in ipairs(value.returnedIds) do
            if type(id) ~= "string" or not acquired[id] or returned[id] then
                return false
            end
            returned[id] = true
        end
        return true
    end
    return type(value) == "table" and value.kind == "scout"
        and validPoint(value.destination)
        and validPoint(value.returnPoint)
        and (value.observation == nil or validObservation(value.observation))
        and (value.endReason == nil or (type(value.endReason) == "string"
            and #value.endReason <= 64))
        and (value.site == nil or validSite(value.site))
end

local function distanceToPoint(actor, point)
    local x, y, z = SC.GameplayUtil.position(actor)
    if x == nil or y == nil or z == nil
        or math.floor(z) ~= point.z then return math.huge end
    return math.sqrt((x - point.x)^2 + (y - point.y)^2)
end

local function validSlotSqlId(value)
    return type(value) == "number" and value >= 2
        and value <= 2147483647 and value == math.floor(value)
end

local function radioTextReceived(guid, codes, _x, _y, _z, message, device)
    local pending = mission and mission.pendingRadio
    if pending == nil or pending.received == true
        or tostring(guid) ~= pending.guid
        or tostring(codes) ~= pending.codes
        or tostring(message) ~= pending.text
        or device ~= pending.receiver
        or mission.leader.actor ~= pending.leader
        or getSpecificPlayer(1) ~= pending.leader
        or SCSplitScreenProbe == nil
        or SCSplitScreenProbe.isLeaderRadioTextContextActive() ~= true then
        return
    end
    pending.received = true
end

local function alive(record)
    if record == nil or record.actor == nil
        or not SC.Registry.isActive(record.actor, record.id) then return false end
    local ok, dead = pcall(function() return record.actor:isDead() end)
    return ok and dead == false
end

local function squadNeedsWithdrawal(roster)
    for _, record in ipairs(roster or {}) do
        if alive(record) then
            local assessment
            if SC.Medical and type(SC.Medical.assessCached) == "function" then
                local ok, value = pcall(SC.Medical.assessCached,
                    record.actor, nil, 250)
                if ok and type(value) == "table" then assessment = value end
            end
            local health = tonumber(assessment and assessment.health)
            if health == nil
                and type(SC.GameplayUtil.nativeHealth) == "function" then
                health = tonumber(SC.GameplayUtil.nativeHealth(record.actor))
            end
            local bleeding = tonumber(assessment and assessment.bleedingCount) or 0
            if health ~= nil and (health <= 30
                or (health <= 55 and bleeding > 0)) then
                return true, record, health
            end
        end
    end
    return false
end
Expedition._squadNeedsWithdrawalForTests = squadNeedsWithdrawal

-- getEquipedRadio() is cached by the native character update. A hand change
-- can leave it pointing at the old device until the next tick, so validate
-- the current physical slot before accepting either endpoint.
local function currentEquippedRadio(actor)
    local radio = actor and actor:getEquipedRadio()
    if radio == nil then return nil end
    -- A hand reference can lag an inventory transfer. A walkie packed into a
    -- bag is no longer an operable endpoint even if that reference is stale.
    if radio:getContainer() ~= actor:getInventory() then return nil end
    if radio == actor:getPrimaryHandItem()
        or radio == actor:getSecondaryHandItem()
        or radio == actor:getClothingItem_Back() then
        return radio
    end
    return nil
end

-- Private playtest kit. These are real inventory items and native DeviceData;
-- the kit does not grant command authority or make radios a departure gate.
local function installTestWalkie(actor)
    local inventory = actor and actor:getInventory()
    if inventory == nil then error("radio holder has no inventory") end
    local radio = inventory:AddItem("Base.WalkieTalkie2")
    if radio == nil or not SC.GameplayUtil.instanceOf(radio, "Radio") then
        error("native walkie-talkie could not be spawned")
    end
    local data = radio:getDeviceData()
    if data == nil or not data:getIsPortable() or not data:getIsTwoWay() then
        error("spawned radio lacks native two-way portable capability")
    end
    if data:getHasBattery() and data:getPower() <= 0 then
        data:getBattery(inventory)
    end
    if not data:getHasBattery() then
        local battery = inventory:AddItem("Base.Battery")
        if battery == nil then error("native battery could not be spawned") end
        data:addBattery(battery)
    end
    local presets = data:getDevicePresets()
    if presets == nil then error("radio has no native preset store") end
    if presets:getPresets():size() < presets:getMaxPresets() then
        presets:addPreset(TEST_RADIO_PRESET, TEST_RADIO_CHANNEL)
    else
        presets:setPreset(0, TEST_RADIO_PRESET, TEST_RADIO_CHANNEL)
    end
    data:setChannel(TEST_RADIO_CHANNEL)
    data:setDeviceVolume(0.8)
    data:setIsTurnedOn(true)
    actor:setSecondaryHandItem(radio)
    local presetFound = false
    local entries = presets:getPresets()
    for index = 0, entries:size() - 1 do
        local entry = entries:get(index)
        if entry:getName() == TEST_RADIO_PRESET
            and entry:getFrequency() == TEST_RADIO_CHANNEL then
            presetFound = true break
        end
    end
    if not presetFound or not data:getHasBattery() or data:getPower() <= 0
        or not data:getIsTurnedOn() or data:getChannel() ~= TEST_RADIO_CHANNEL
        or actor:getSecondaryHandItem() ~= radio then
        error("native radio failed battery, power, channel, preset or hand check")
    end
    return radio
end

function Expedition.provisionTestRadios(player, records)
    if player == nil or type(records) ~= "table" or #records < 1 then
        error("playtest radio kit requires a player and team")
    end
    local radios = { team = {} }
    radios.player = installTestWalkie(player)
    for index, record in ipairs(records) do
        radios.team[index] = installTestWalkie(record.actor)
    end
    return radios
end

function Expedition.start(records, plan)
    if mission ~= nil then return false, "expedition_already_active" end
    if SCSplitScreenProbe == nil then return false, "local_view_unavailable" end
    if type(records) ~= "table" or #records < 1 or #records > 4 then
        return false, "expedition_requires_one_to_four_companions"
    end
    local seen, roster = {}, {}
    for _, record in ipairs(records) do
        if not alive(record) or seen[record.actor] then
            return false, "expedition_member_unavailable"
        end
        seen[record.actor] = true
        -- Registry death cleanup clears record.actor. The active mission must
        -- retain the original native actor identity for later handoffs.
        local name = SC.GameplayUtil.nameOf(record.actor)
        if type(name) ~= "string" or name == "" then name = record.id end
        roster[#roster + 1] = { id = record.id, actor = record.actor,
            name = string.sub(name, 1, 80) }
    end
    local scout
    if plan ~= nil then
        local travelMode = type(plan) == "table"
            and (plan.travelMode or "straight") or "straight"
        if travelMode ~= "road" and travelMode ~= "straight" then
            return false, "invalid_travel_mode"
        end
        if type(plan) == "table" and plan.doctrine ~= nil
            and not MISSION_DOCTRINES[plan.doctrine] then
            return false, "invalid_expedition_doctrine"
        end
        -- This is the latest time to turn home, not a promised arrival time.
        local returnHours = type(plan) == "table"
            and plan.turnHomeAfterHours or nil
        if returnHours ~= nil and (type(returnHours) ~= "number"
            or returnHours ~= returnHours or returnHours < 0.25
            or returnHours > 24) then
            return false, "invalid_return_time"
        end
        local arriveByHour = type(plan) == "table"
            and plan.arriveByHour or nil
        if arriveByHour ~= nil and not validWorldHour(arriveByHour) then
            return false, "invalid_return_time"
        end
        local departureHour = (returnHours or arriveByHour)
            and scoutWorldHour() or nil
        if (returnHours or arriveByHour) and departureHour == nil then
            return false, "expedition_clock_unavailable"
        end
        if returnHours and not validWorldHour(departureHour + returnHours) then
            return false, "invalid_return_time"
        end
        if arriveByHour and (arriveByHour <= departureHour
            or arriveByHour > departureHour + 24) then
            return false, "invalid_return_time"
        end
        local player = type(getSpecificPlayer) == "function"
            and getSpecificPlayer(0) or nil
        local returnPoint = player and {
            x = math.floor(player:getX()), y = math.floor(player:getY()),
            z = math.floor(player:getZ()),
        } or nil
        local searchPlan = type(plan) == "table" and plan.kind == "search"
        if type(plan) ~= "table"
            or (plan.kind ~= "scout" and not searchPlan)
            or not validPoint(plan.destination)
            or not validPoint(returnPoint)
            or plan.destination.z ~= returnPoint.z
            or distanceToPoint(roster[1].actor, plan.destination)
                < (searchPlan and 8 or 20)
            or distanceToPoint(roster[1].actor, plan.destination)
                > (SC.Config and SC.Config.get("expeditionDestinationRadius") or 200)
            or (plan.site ~= nil and not validSite(plan.site))
            or (searchPlan and (not validRequest(plan.request)
                or (plan.radius ~= nil and (type(plan.radius) ~= "number"
                    or plan.radius < 2 or plan.radius > 8
                    or plan.radius ~= math.floor(plan.radius))))) then
            return false, searchPlan and "invalid_search_plan"
                or "invalid_scout_plan"
        end
        local extended = distanceToPoint(roster[1].actor,
            plan.destination) > 120
        local roadRoute
        if travelMode == "road" then
            if SC.ExpeditionRoute == nil then
                return false, "road_routing_unavailable"
            end
            local routeReason
            roadRoute, routeReason = SC.ExpeditionRoute.plan(
                roster[1].actor, plan.destination)
            if roadRoute == nil then return false, routeReason end
            local entryReady, entryReason = SC.ExpeditionRoute.verifyEntry(
                roadRoute, roster[1].actor)
            if not entryReady then return false, entryReason end
        end
        scout = {
            kind = plan.kind, phase = "outbound",
            travelMode = travelMode, extended = extended,
            destination = copyPoint(plan.destination),
            site = copySite(plan.site),
            returnPoint = returnPoint, legs = 0,
            turnHomeAtHour = returnHours and departureHour + returnHours or nil,
            arriveByHour = arriveByHour,
            departureHour = departureHour,
            trail = { {
                x = math.floor(roster[1].actor:getX()),
                y = math.floor(roster[1].actor:getY()),
                z = math.floor(roster[1].actor:getZ()),
            } },
            search = searchPlan and {
                request = copyRequest(plan.request), acquisitions = {},
                radius = plan.radius or 5,
            } or nil,
            roadRoute = roadRoute,
            road = roadRoute and SC.ExpeditionRoute.descriptor(
                roadRoute, "outbound") or nil,
        }
    end
    local ok, promoted = pcall(SCSplitScreenProbe.promote,
        roster[1].actor, reusableSlotSqlId or -1)
    if not ok or promoted ~= roster[1].actor then
        return false, tostring(promoted)
    end
    lastOutcome = nil
    lastDebrief = nil
    -- Departure is local. Neither the player nor any team member needs a radio.
    -- The scoped test link below is the only remote order entry point so far.
    mission = {
        roster = roster, leader = roster[1], members = seen,
        doctrine = plan and plan.doctrine or nil,
        slotSqlId = reusableSlotSqlId,
        radioSequence = 0,
        scout = scout,
        radioSession = tostring(type(getTimestampMs) == "function"
                and getTimestampMs() or 0)
            .. ":" .. tostring(type(ZombRand) == "function"
                and ZombRand(2147483647) or 0),
    }
    if Events and Events.OnDeviceText then
        Events.OnDeviceText.Add(radioTextReceived)
        mission.radioTextHooked = true
    end
    if SC.Dialogue and type(SC.Dialogue.say) == "function" then
        pcall(SC.Dialogue.say, roster[1].actor, "expedition.departure")
    end
    return true, mission
end

-- Draft reads have no gameplay effects. Requery at commit time so a stale
-- building ID or a change from All nearby to Known only cannot bypass the
-- selected knowledge policy. The map approach is a direction for local legs;
-- the leader checks loaded exterior access when it reaches the building.
function Expedition.placeCandidates(leaderId, page)
    local record = type(leaderId) == "string" and SC.Registry
        and SC.Registry.byId(leaderId) or nil
    if leaderId ~= nil and (record == nil or record.actor == nil) then
        return nil, "leader_unavailable"
    end
    local player = record and record.actor or type(getSpecificPlayer) == "function"
        and getSpecificPlayer(0) or nil
    local x, y
    if player then x, y = SC.GameplayUtil.position(player) end
    if x == nil or y == nil then return nil, "local_player_unavailable" end
    local places = SC.ExpeditionPlaces
    if places == nil or type(places.targetableNearby) ~= "function" then
        return nil, "place_lookup_unavailable"
    end
    page = tonumber(page) or 1
    if page < 1 or page > 128 or page ~= math.floor(page) then
        return nil, "invalid_place_page"
    end
    return places.targetableNearby(math.floor(x), math.floor(y),
        SC.Config and SC.Config.get("expeditionDestinationRadius") or 200,
        32, (page - 1) * 32)
end

function Expedition.startAtPlace(records, placeId, kind, options)
    if mission ~= nil then return false, "expedition_already_active" end
    if type(placeId) ~= "string" or #placeId < 1 or #placeId > 64
        or (kind ~= "scout" and kind ~= "search") then
        return false, "invalid_place_plan"
    end
    if type(records) ~= "table" or #records < 1
        or type(records[1]) ~= "table" or records[1].actor == nil then
        return false, "expedition_member_unavailable"
    end
    local lookup = SC.ExpeditionPlaces
    if lookup == nil or type(lookup.targetableById) ~= "function" then
        return false, "place_lookup_unavailable"
    end
    local x, y = SC.GameplayUtil.position(records[1].actor)
    if x == nil or y == nil then return false, "leader_unavailable" end
    local selected, reason = lookup.targetableById(math.floor(x), math.floor(y),
        SC.Config and SC.Config.get("expeditionDestinationRadius") or 200, placeId)
    if selected == nil then return false, reason or "place_no_longer_selectable" end
    if type(lookup.plannedApproach) ~= "function"
        or type(lookup.loadedSiteApproach) ~= "function" then
        return false, "place_approach_unavailable"
    end
    local approach, approachReason = lookup.plannedApproach(
        selected, records[1].actor)
    if approach == nil then
        return false, approachReason or "place_approach_unavailable"
    end
    options = type(options) == "table" and options or {}
    return Expedition.start(records, {
        kind = kind,
        destination = { x = approach.x, y = approach.y, z = approach.z },
        site = selected,
        request = options.request, radius = options.radius,
        turnHomeAfterHours = options.turnHomeAfterHours,
        arriveByHour = options.arriveByHour,
        doctrine = options.doctrine,
        travelMode = options.travelMode,
    })
end

function Expedition.previewAtPlace(leader, place, travelMode)
    if leader == nil or leader.actor == nil or type(place) ~= "table" then
        return nil, "leader_unavailable"
    end
    local approach, reason = SC.ExpeditionPlaces.plannedApproach(
        place, leader.actor)
    if approach == nil then return nil, reason end
    local distance = distanceToPoint(leader.actor, approach)
    if travelMode ~= "road" then
        return { mode = "local", distance = math.floor(distance + 0.5) }
    end
    if SC.ExpeditionRoute == nil then
        return nil, "road_routing_unavailable"
    end
    local route, routeReason = SC.ExpeditionRoute.plan(
        leader.actor, approach)
    if route == nil then return nil, routeReason end
    local streets, seen = {}, {}
    for _, point in ipairs(route.points) do
        if point.street ~= "" and not seen[point.street] then
            seen[point.street] = true
            streets[#streets + 1] = point.street
        end
    end
    -- Off-road stretches at either end are walked in loaded local legs.
    local x, y = SC.GameplayUtil.position(leader.actor)
    local entry, exit = route.points[1], route.points[#route.points]
    local function tiles(fromX, fromY, point)
        return math.floor(math.sqrt((fromX - point.x)^2
            + (fromY - point.y)^2) + 0.5)
    end
    return { mode = "road", distance = math.floor(
        route.roadLength + 0.5), streets = streets,
        provisional = route.inferredJunctions > 0,
        elapsedMs = route.elapsedMs,
        offRoadStart = x ~= nil and y ~= nil and tiles(x, y, entry) or 0,
        offRoadEnd = tiles(exit.x, exit.y, approach) }
end

-- Persist only stable companion IDs and command serials. Native actors,
-- chunk maps, UI, and in-flight radio callbacks cannot cross a save boundary.
function Expedition.export()
    if mission == nil or mission.terminal then
        if validSlotSqlId(reusableSlotSqlId) then
            return { schema = 2, state = "idle",
                slotSqlId = reusableSlotSqlId,
                debrief = copyDebrief(lastDebrief) }
        end
        return nil
    end
    local roster, rosterNames, survivors = {}, {}, {}
    for _, record in ipairs(mission.roster) do
        roster[#roster + 1] = record.id
        rosterNames[record.id] = record.name or record.id
        if (mission.restoring and mission.survivors[record.id])
            or (not mission.restoring and alive(record)) then
            survivors[#survivors + 1] = record.id
        end
    end
    local leaderId = mission.leader and mission.leader.id
    local leaderAlive = false
    for _, id in ipairs(survivors) do
        if id == leaderId then leaderAlive = true break end
    end
    if not leaderAlive then leaderId = survivors[1] or leaderId end
    local sqlOk, sqlValue = false, nil
    if SCSplitScreenProbe ~= nil then
        sqlOk, sqlValue = pcall(function()
            return SCSplitScreenProbe.leaderSqlId()
        end)
    end
    local liveSqlId = sqlOk and tonumber(sqlValue) or nil
    local slotSqlId = type(liveSqlId) == "number" and liveSqlId >= 2
        and liveSqlId or mission.slotSqlId
    if not validSlotSqlId(slotSqlId) then slotSqlId = nil end
    local scoutTrail
    if mission.scout ~= nil then
        scoutTrail = {}
        for index, point in ipairs(mission.scout.trail) do
            scoutTrail[index] = copyPoint(point)
        end
    end
    return {
        schema = mission.scout and ((mission.scout.extended
                or mission.scout.road ~= nil) and 5
            or mission.scout.kind == "search" and 4 or 3)
            or 1,
        roster = roster, rosterNames = rosterNames, survivors = survivors,
        leaderId = leaderId, radioSession = mission.radioSession,
        doctrine = mission.doctrine,
        radioSequence = mission.radioSequence,
        slotSqlId = slotSqlId,
        scout = mission.scout and {
            kind = mission.scout.kind,
            travelMode = mission.scout.travelMode,
            phase = mission.scout.phase,
            destination = copyPoint(mission.scout.destination),
            returnPoint = copyPoint(mission.scout.returnPoint),
            legs = mission.scout.legs,
            trail = scoutTrail,
            returnIndex = mission.scout.returnIndex,
            observation = copyObservation(mission.scout.observation),
            search = copySearch(mission.scout.search),
            site = copySite(mission.scout.site),
            turnHomeAtHour = mission.scout.turnHomeAtHour,
            arriveByHour = mission.scout.arriveByHour,
            departureHour = mission.scout.departureHour,
            endReason = mission.scout.endReason,
            road = mission.scout.road and {
                version = 1, phase = mission.scout.road.phase,
                fingerprint = mission.scout.road.fingerprint,
                goal = copyPoint(mission.scout.road.goal),
                avoidance = copyRoadAvoidance(
                    mission.scout.road.avoidance),
            } or nil,
            hordeDetours = mission.scout.hordeDetours,
        } or nil,
    }
end

function Expedition.restore(saved)
    if mission ~= nil then return false, "expedition is already active" end
    if type(saved) == "table" and saved.schema == 2 then
        if saved.state ~= "idle" or not validSlotSqlId(saved.slotSqlId)
            or saved.roster ~= nil or saved.survivors ~= nil
            or saved.leaderId ~= nil
            or (saved.debrief ~= nil and not validDebrief(saved.debrief)) then
            return false, "saved idle expedition slot is invalid"
        end
        reusableSlotSqlId = saved.slotSqlId
        lastDebrief = copyDebrief(saved.debrief)
        return true
    end
    if type(saved) ~= "table" or (saved.schema ~= 1
            and saved.schema ~= 3 and saved.schema ~= 4
            and saved.schema ~= 5)
        or type(saved.roster) ~= "table" or #saved.roster < 1
        or #saved.roster > 4 or type(saved.survivors) ~= "table"
        or type(saved.leaderId) ~= "string"
        or type(saved.radioSession) ~= "string"
        or #saved.radioSession < 1 or #saved.radioSession > 128
        or type(saved.radioSequence) ~= "number"
        or (saved.doctrine ~= nil
            and not MISSION_DOCTRINES[saved.doctrine])
        or saved.radioSequence < 0 or saved.radioSequence > 1000000
        or saved.radioSequence ~= math.floor(saved.radioSequence)
        or (saved.slotSqlId ~= nil
            and not validSlotSqlId(saved.slotSqlId)) then
        return false, "saved expedition descriptor is invalid"
    end
    local scout = saved.scout
    if saved.schema == 3 or saved.schema == 4 or saved.schema == 5 then
        if type(scout) ~= "table"
            or (scout.phase ~= "outbound" and scout.phase ~= "observing"
                and scout.phase ~= "searching" and scout.phase ~= "inbound"
                and scout.phase ~= "awaiting_player")
            or (saved.schema == 3 and (scout.kind ~= nil
                and scout.kind ~= "scout" or scout.search ~= nil
                or scout.phase == "searching"))
            or ((saved.schema == 4 or saved.schema == 5
                    and scout.kind == "search") and (scout.kind ~= "search"
                or scout.phase == "observing"
                or not validSearch(scout.search)
                or (scout.phase ~= "outbound"
                    and scout.search.startedHour == nil
                    and (scout.search.endReason ~= "return_time_reached"
                        or scout.turnHomeAtHour == nil)
                    and (scout.search.endReason ~= "arrival_reserve_reached"
                        or scout.arriveByHour == nil))
                or ((scout.phase == "inbound"
                        or scout.phase == "awaiting_player")
                    and scout.search.endReason == nil)
                or scout.observation ~= nil))
            or (saved.schema == 5 and (scout.kind ~= "scout"
                    and scout.kind ~= "search"
                or (scout.travelMode ~= "road"
                    and scout.travelMode ~= "straight")
                or (scout.travelMode == "road" and (
                    not SC.ExpeditionRoute
                    or not SC.ExpeditionRoute.validDescriptor(scout.road)))
                or (scout.travelMode == "straight" and scout.road ~= nil)
                or (scout.kind == "scout" and (scout.search ~= nil
                    or scout.phase == "searching"))
                or (scout.road ~= nil and (scout.phase == "inbound"
                    or scout.phase == "awaiting_player")
                    and scout.road.phase ~= "inbound")
                or (scout.road ~= nil and (scout.phase == "outbound"
                    or scout.phase == "observing"
                    or scout.phase == "searching")
                    and scout.road.phase ~= "outbound")))
            or (saved.schema ~= 5 and scout.road ~= nil)
            or not validPoint(scout.destination)
            or not validPoint(scout.returnPoint)
            or (saved.schema == 5 and scout.road ~= nil and (
                scout.road.goal.x ~= (scout.road.phase == "inbound"
                    and scout.returnPoint.x or scout.destination.x)
                or scout.road.goal.y ~= (scout.road.phase == "inbound"
                    and scout.returnPoint.y or scout.destination.y)))
            or scout.destination.z ~= scout.returnPoint.z
            or type(scout.legs) ~= "number" or scout.legs < 0
            or scout.legs > (saved.schema == 5 and 256 or 96)
                or scout.legs ~= math.floor(scout.legs)
            or type(scout.trail) ~= "table" or #scout.trail < 1
            or #scout.trail > (saved.schema == 5 and 128 or 64)
            or (scout.observation ~= nil
                and not validObservation(scout.observation))
            or (scout.site ~= nil and not validSite(scout.site))
            or (scout.turnHomeAtHour ~= nil
                and not validWorldHour(scout.turnHomeAtHour))
            or (scout.departureHour ~= nil
                and not validWorldHour(scout.departureHour))
            or (scout.turnHomeAtHour ~= nil
                and scout.departureHour ~= nil
                and (scout.turnHomeAtHour <= scout.departureHour
                    or scout.turnHomeAtHour > scout.departureHour + 24))
            or (scout.arriveByHour ~= nil
                and (not validWorldHour(scout.arriveByHour)
                    or not validWorldHour(scout.departureHour)
                    or scout.arriveByHour <= scout.departureHour
                    or scout.arriveByHour > scout.departureHour + 24))
            or (scout.arriveByHour == nil and scout.departureHour ~= nil
                and scout.turnHomeAtHour == nil)
            or (scout.endReason ~= nil
                and (type(scout.endReason) ~= "string"
                    or #scout.endReason > 64))
            or (scout.hordeDetours ~= nil
                and (type(scout.hordeDetours) ~= "number"
                    or scout.hordeDetours < 0 or scout.hordeDetours > 3
                    or scout.hordeDetours ~= math.floor(scout.hordeDetours)))
            or (scout.returnIndex ~= nil
                and (type(scout.returnIndex) ~= "number"
                    or scout.returnIndex < 0
                    or scout.returnIndex > #scout.trail
                    or scout.returnIndex ~= math.floor(scout.returnIndex))) then
            return false, "saved scout itinerary is invalid"
        end
        local trail = {}
        for index, point in ipairs(scout.trail) do
            if not validPoint(point)
                or point.z ~= scout.returnPoint.z then
                return false, "saved scout itinerary is invalid"
            end
            trail[index] = copyPoint(point)
        end
        scout = {
            kind = (saved.schema == 4 or saved.schema == 5
                and scout.kind == "search") and "search" or "scout",
            travelMode = saved.schema == 5 and scout.travelMode
                or scout.travelMode or "straight",
            extended = saved.schema == 5,
            phase = scout.phase, destination = copyPoint(scout.destination),
            returnPoint = copyPoint(scout.returnPoint), legs = scout.legs,
            trail = trail, returnIndex = scout.returnIndex,
            observation = copyObservation(scout.observation),
            search = copySearch(scout.search),
            site = copySite(scout.site),
            turnHomeAtHour = scout.turnHomeAtHour,
            arriveByHour = scout.arriveByHour,
            departureHour = scout.departureHour,
            endReason = scout.endReason,
            road = scout.road and {
                version = 1, phase = scout.road.phase,
                fingerprint = scout.road.fingerprint,
                goal = copyPoint(scout.road.goal),
                avoidance = copyRoadAvoidance(scout.road.avoidance),
            } or nil,
            hordeDetours = scout.hordeDetours or 0,
        }
    elseif scout ~= nil then
        return false, "saved expedition descriptor is invalid"
    end
    local roster, known, survivors = {}, {}, {}
    for index, id in ipairs(saved.roster) do
        if type(id) ~= "string" or #id < 1 or #id > 128 or known[id] then
            return false, "saved expedition roster is invalid"
        end
        known[id] = true
        local name = type(saved.rosterNames) == "table"
            and saved.rosterNames[id] or nil
        if name ~= nil and (type(name) ~= "string" or #name < 1
            or #name > 80) then
            return false, "saved expedition roster names are invalid"
        end
        roster[index] = { id = id, name = name or id }
    end
    if saved.rosterNames ~= nil then
        if type(saved.rosterNames) ~= "table" then
            return false, "saved expedition roster names are invalid"
        end
        for id in pairs(saved.rosterNames) do
            if not known[id] then
                return false, "saved expedition roster names are invalid"
            end
        end
    end
    if not known[saved.leaderId] then
        return false, "saved expedition leader is not in roster"
    end
    for _, id in ipairs(saved.survivors) do
        if type(id) ~= "string" or not known[id] or survivors[id] then
            return false, "saved expedition survivors are invalid"
        end
        survivors[id] = true
    end
    mission = {
        roster = roster, leader = nil, members = {}, survivors = survivors,
        doctrine = saved.doctrine,
        radioSession = saved.radioSession,
        radioSequence = saved.radioSequence,
        slotSqlId = saved.slotSqlId,
        scout = scout,
        restoring = true,
        technicalIssue = { reason = "expedition_restart_waiting_for_native_team" },
    }
    reusableSlotSqlId = saved.slotSqlId
    for _, record in ipairs(roster) do
        if record.id == saved.leaderId then mission.leader = record break end
    end
    return true
end

function Expedition.current() return mission end
function Expedition.lastOutcome() return lastOutcome end
function Expedition.lastDebrief() return copyDebrief(lastDebrief) end

-- Runtime calls this before disposing native actors. Keep the mission's stable
-- descriptor available to the save owner until world teardown commits.
function Expedition.prepareReset()
    if mission == nil then return true end
    if mission.suspended then return true end
    if SCSplitScreenProbe == nil then
        return false, "expedition_view_owner_unavailable"
    end
    local slot = getSpecificPlayer(1)
    if slot ~= nil then
        if not mission.restoring and slot ~= mission.leader.actor then
            return false, "expedition_view_owner_mismatch"
        end
        if type(destroyPlayerData) ~= "function" then
            return false, "expedition_ui_teardown_unavailable"
        end
        if not mission.uiDetached then
            local uiOk, uiError = pcall(destroyPlayerData, slot)
            if not uiOk then return false, tostring(uiError) end
            mission.uiDetached = true
        end
        local released, value = pcall(SCSplitScreenProbe.releaseForWorldExit)
        if not released or value ~= true then
            return false, tostring(value)
        end
    end
    mission.pendingRadio = nil
    mission.radioAuthorization = nil
    if mission.radioTextHooked then
        Events.OnDeviceText.Remove(radioTextReceived)
        mission.radioTextHooked = false
    end
    mission.suspended = true
    return true
end

function Expedition.reset()
    if mission ~= nil and not mission.suspended then
        return false, "expedition_view_still_owned"
    end
    mission = nil
    lastOutcome = nil
    lastDebrief = nil
    reusableSlotSqlId = nil
    holdColdHandoffForTest = false
    return true
end

-- Disposable crash probe: keep the cold loader in slot 1 long enough to save
-- its native row, then terminate the cloned client before the normal handoff.
function Expedition.holdColdHandoffForTest(hold)
    holdColdHandoffForTest = hold == true
end

-- Read-only boundary for a future native restart loader. Only the exact
-- surviving leader of a paused expedition may request its saved area; this
-- does not create a player, move an actor, or consume the pending snapshot.
function Expedition.restartBootstrapCandidate()
    if mission == nil or mission.restoring ~= true
        or mission.leader == nil or alive(mission.leader)
        or mission.survivors[mission.leader.id] ~= true
        or SC.Persistence == nil
        or type(SC.Persistence.pendingBootstrap) ~= "function" then
        return nil
    end
    local candidate = SC.Persistence.pendingBootstrap(mission.leader.id)
    if candidate ~= nil then candidate.slotSqlId = mission.slotSqlId end
    return candidate
end

function Expedition.isMember(actor)
    return mission ~= nil and mission.members[actor] == true
end

function Expedition.isFollower(actor)
    return Expedition.isMember(actor) and mission.leader.actor ~= actor
end

local function missionRecord(id)
    if mission == nil or type(id) ~= "string" then return nil end
    for _, record in ipairs(mission.roster) do
        if record.id == id then return record end
    end
    return nil
end

function Expedition.isMemberId(id)
    return missionRecord(id) ~= nil
end

function Expedition.memberName(id)
    local record = missionRecord(id)
    return record and record.name or nil
end

function Expedition.playerCanObserve(actor, viewer)
    if not Expedition.isMember(actor) or viewer == nil
        or type(getSpecificPlayer) ~= "function"
        or getSpecificPlayer(0) ~= viewer then return false end
    local px, py, pz = SC.GameplayUtil.position(viewer)
    local x, y, z = SC.GameplayUtil.position(actor)
    if px == nil or x == nil or math.floor(pz or -1) ~= math.floor(z or -2)
        or (px - x)^2 + (py - y)^2 > 20 * 20 then return false end
    return SC.GameplayUtil.canSee(viewer, actor) == true
end

-- Normal UI receives only known plans and locally visible member facts. A
-- hidden death or return phase is not a player observation.
function Expedition.describeForPlayer(viewer)
    if mission == nil then return nil end
    local leader = mission.leader and missionRecord(mission.leader.id)
    local itinerary = mission.scout
    local members = {}
    for _, record in ipairs(mission.roster) do
        members[#members + 1] = {
            id = record.id, name = record.name or record.id,
            visible = record.actor ~= nil
                and Expedition.playerCanObserve(record.actor, viewer) or false,
        }
    end
    return {
        leaderName = leader and leader.name or "?",
        kind = itinerary and itinerary.kind or nil,
        plannedSite = itinerary and itinerary.site
            and itinerary.site.label or nil,
        turnHomeAtHour = itinerary and itinerary.turnHomeAtHour or nil,
        members = members,
    }
end

-- The selected combat style is a trip-local view. It never rewrites the
-- companion's saved doctrine and therefore needs no post-return command.
function Expedition.effectiveDoctrineFor(actor, saved)
    if not Expedition.isMember(actor) or mission.doctrine == nil
        or type(saved) ~= "table" then return saved end
    local effective = {}
    for key, value in pairs(saved) do effective[key] = value end
    effective.combatDoctrine = mission.doctrine
    effective.combatMode = mission.doctrine == "stealth" and "passive"
        or mission.doctrine == "weapons_free" and "aggressive"
        or "defensive"
    effective.expeditionTravelCombat = Expedition.roadCombatFor
        and Expedition.roadCombatFor(actor) or nil
    return effective
end

-- A temporary formation policy, not a saved Follow order. Travelling members
-- stay close even if their ordinary squad distance is eight tiles. Once the
-- leader is searching inside a building, give the team room around containers
-- and doorways. The next outbound/inbound leg automatically tightens it again.
function Expedition.followDistanceFor(actor)
    if not Expedition.isFollower(actor) then return nil end
    local itinerary = mission.scout
    if itinerary and itinerary.phase == "searching" then
        local square = mission.leader.actor:getCurrentSquare()
        if square and square:getRoom() ~= nil then return 5 end
    end
    return 2
end

-- Shared Positioning owns follower movement. The road route supplies only the
-- current street geometry so its open formation can stay within the road.
function Expedition.roadFormationFor(actor)
    if not Expedition.isFollower(actor) or mission.scout == nil then return nil end
    local scout = mission.scout
    if scout.phase ~= "outbound" and scout.phase ~= "inbound" then return nil end
    local route = scout.roadRoute
    if route == nil or SC.ExpeditionRoute == nil then return nil end
    local first = route.points[route.index - 1]
    local last = route.points[route.index]
    if (first and first.junction == true
        and distanceToPoint(mission.leader.actor,
            { x = first.x, y = first.y, z = 0 }) <= 6)
        or (last and last.junction == true
            and distanceToPoint(mission.leader.actor,
                { x = last.x, y = last.y, z = 0 }) <= 6) then
        return { column = true }
    end
    return SC.ExpeditionRoute.formationSegment
        and SC.ExpeditionRoute.formationSegment(
            route, mission.leader.actor) or nil
end

-- Aggressive combat remains defensive while the leader is travelling: it may
-- fight threats close to the squad, but should not chase one across a verge
-- and strand the entire mission away from the mapped road.
function Expedition.roadCombatFor(actor)
    if not Expedition.isMember(actor)
        or mission.scout == nil then return nil end
    local scout = mission.scout
    if (scout.phase ~= "outbound" and scout.phase ~= "inbound")
        or scout.roadRoute == nil then return nil end
    local route = scout.roadRoute
    local first, last = route.points[route.index - 1],
        route.points[route.index]
    local policy = { radius = 2.5 }
    if first and last and (last.width or 0) >= 6 then
        policy.first, policy.last, policy.width = first, last, last.width
    end
    return policy
end

function Expedition.radioCommandAuthorized(actor, command, payload, player)
    local auth = mission and mission.radioAuthorization
    return auth ~= nil and auth.actor == actor
        and auth.command == command and auth.payload == payload
        and auth.player == player and mission.leader.actor == actor
end

-- Private vertical slice: send one real native radio message, accept only its
-- exact receiver-side text event, then use the existing Commands owner.
function Expedition.sendRadioOrder(player, command, payload)
    if mission == nil or mission.terminal then return false, "no_active_expedition" end
    if player == nil or getSpecificPlayer(0) ~= player then
        return false, "invalid_local_operator"
    end
    local returnNow = command == "return_now" and payload == "now"
    if not returnNow and (command ~= "set_move_mode"
        or (payload ~= "walk" and payload ~= "sneak")) then
        return false, "unsupported_radio_order"
    end
    if returnNow and (mission.scout == nil
        or mission.scout.phase == "inbound") then
        return false, "expedition_already_returning"
    end
    if not mission.radioTextHooked then return false, "radio_receive_hook_unavailable" end
    if mission.pendingRadio ~= nil then return false, "radio_busy" end
    if not alive(mission.leader) or getSpecificPlayer(1) ~= mission.leader.actor then
        return false, "leader_unavailable"
    end
    local sender = currentEquippedRadio(player)
    if sender == nil then return false, "local_radio_not_equipped" end
    local data = sender:getDeviceData()
    if data == nil or not data:getIsTwoWay() or not data:getIsTurnedOn()
        or not data:getHasBattery() or data:getPower() <= 0
        or data:getMicIsMuted() or data:isNoTransmit()
        or data:getTransmitRange() <= 0 then
        return false, "local_radio_unavailable"
    end
    local receiver = currentEquippedRadio(mission.leader.actor)
    -- The receiver is used only to bind the actual native text event. Its
    -- operational state is deliberately not exposed as a local failure reason.
    if receiver == nil then return false, "radio_no_ack" end
    mission.radioSequence = mission.radioSequence + 1
    local sequence = mission.radioSequence
    local guid = "LF-EXP-" .. mission.radioSession
    local codes = "CMD-" .. tostring(sequence)
    local text = guid .. "|" .. codes .. "|" .. command .. "|" .. payload
    local pending = {
        leader = mission.leader.actor, receiver = receiver,
        guid = guid, codes = codes, text = text,
    }
    mission.pendingRadio = pending
    local sent, failure = pcall(SCSplitScreenProbe.sendTestRadioWithLeaderText,
        math.floor(player:getX()), math.floor(player:getY()),
        data:getChannel(), text, guid, codes,
        0.8, 0.9, 1.0, data:getTransmitRange(), false)
    mission.pendingRadio = nil
    if not sent then return false, "radio_dispatch_failed:" .. tostring(failure) end
    if pending.received ~= true or not alive(mission.leader)
        or mission.leader.actor ~= pending.leader then
        return false, "radio_no_ack"
    end
    if returnNow then
        local leader = mission.leader.actor
        if mission.testWaypoint ~= nil then
            Expedition.clearTestWaypoint(leader)
            local owner = SC.ActionSupervisor
                and type(SC.ActionSupervisor.current) == "function"
                and SC.ActionSupervisor.current(leader) or nil
            if owner == nil and SC.Navigation
                and type(SC.Navigation.cancel) == "function" then
                SC.Navigation.cancel(leader, "expedition_radio_return")
            end
        end
        startReturnFromSite(mission.scout, "radio_return")
        mission.lastRadioOrder = {
            sequence = sequence, command = command, payload = payload,
            leader = pending.leader,
        }
        return true, "returning"
    end
    mission.radioAuthorization = {
        actor = pending.leader, command = command,
        payload = payload, player = player,
    }
    local issued, accepted, reason = pcall(SC.Commands.issue,
        mission.leader.id, command, payload, player)
    mission.radioAuthorization = nil
    if not issued then return false, "radio_order_error:" .. tostring(accepted) end
    if accepted ~= true then return false, tostring(reason) end
    mission.lastRadioOrder = {
        sequence = sequence, command = command, payload = payload,
        leader = pending.leader,
    }
    return true, reason
end

-- Private W03 movement probe: a standing waypoint is installed by the local
-- test driver. This is not a radio command and is never exposed in Orders UI.
function Expedition.stageTestWaypoint(actor, x, y, z)
    if mission == nil or mission.leader.actor ~= actor or not alive(mission.leader)
        or type(x) ~= "number" or type(y) ~= "number"
        or type(z) ~= "number" then return false, "invalid_test_waypoint" end
    -- Departure must finish any owned idle action before movement takes over.
    -- The old local order can otherwise keep a chair action alive after the
    -- expedition decision has chosen a waypoint.
    if SC.Downtime and type(SC.Downtime.peek) == "function"
        and type(SC.Downtime.cancel) == "function" then
        for _, record in ipairs(mission.roster) do
            local member = record.actor
            local state = member and SC.Downtime.peek(member)
            if state and (state.active or state.curtainTask) then
                local cancelled, reason = SC.Downtime.cancel(
                    member, "expedition_departure")
                if cancelled ~= true then
                    return false, "departure_downtime_busy:" .. tostring(reason)
                end
            end
        end
    end
    mission.testWaypoint = {
        x = math.floor(x), y = math.floor(y), z = math.floor(z),
    }
    mission.testWaypointArrived = false
    mission.testWaypointArrival = nil
    mission.cohesionHold = nil
    return true
end

function Expedition.testWaypointActiveFor(actor)
    return Expedition.isMember(actor) and mission.testWaypoint ~= nil
end

function Expedition.testWaypointFor(actor)
    if mission ~= nil and mission.leader.actor == actor then
        if mission.cohesionHold ~= nil or mission.technicalIssue ~= nil then
            return nil
        end
        return mission.testWaypoint
    end
    return nil
end

-- A tactical diversion can carry the leader past a standing waypoint.
-- Abandon that target explicitly before the test planner replans from the
-- actual square; never count it as an arrival.
function Expedition.clearTestWaypoint(actor)
    if mission == nil or mission.leader.actor ~= actor then
        return false, "leader_unavailable"
    end
    mission.testWaypoint = nil
    mission.testWaypointArrived = false
    mission.testWaypointArrival = nil
    mission.cohesionHold = nil
    return true
end

-- Private W05 probe: permit the existing Encounter owner to select and loot
-- real local containers while the leader holds the remote area.
function Expedition.stageTestSearch(actor, targetContainer, requestedCategory)
    if mission == nil or mission.terminal or mission.leader.actor ~= actor
        or not alive(mission.leader) then
        return false, "leader_unavailable"
    end
    mission.testSearch = true
    -- This native reference belongs only to the live test task. A later
    -- mission planner must resolve its durable target after reload.
    mission.testSearchTarget = targetContainer
    mission.testSearchCategory = requestedCategory
    return true
end

function Expedition.testSearchFor(actor)
    if mission == nil or mission.terminal or mission.leader.actor ~= actor
        or mission.technicalIssue ~= nil then return false end
    if mission.testSearch == true then return true end
    local itinerary = mission.scout
    local search = itinerary and itinerary.search
    return itinerary ~= nil and itinerary.phase == "searching"
        and search ~= nil
        and #search.acquisitions < search.request.quantity
end

function Expedition.testSearchTargetFor(actor)
    if Expedition.testSearchFor(actor) and mission.testSearch == true then
        return mission.testSearchTarget
    end
    return nil
end

function Expedition.testSearchCategoryFor(actor)
    if Expedition.testSearchFor(actor) then
        local itinerary = mission.scout
        if itinerary and itinerary.phase == "searching"
            and itinerary.search then
            return itinerary.search.request.category
        end
        return mission.testSearchCategory
    end
    return nil
end

function Expedition.testSearchMissionIdFor(actor)
    if Expedition.testSearchFor(actor) and mission.scout
        and mission.scout.phase == "searching"
        and mission.scout.search then
        return mission.radioSession
    end
    return nil
end

function Expedition.searchSiteFor(actor)
    if Expedition.testSearchFor(actor) and mission.scout
        and mission.scout.phase == "searching"
        and mission.scout.search then
        return mission.scout.destination
    end
    return nil
end

function Expedition.searchSiteRadiusFor(actor)
    if Expedition.searchSiteFor(actor) then
        return mission.scout.search.radius
    end
    return nil
end

-- Encounter calls this only after its exact native source debit and
-- destination membership check. The item token survives companion inventory
-- serialization; these receipts explain cargo without owning another item.
function Expedition.noteVerifiedSearchLoot(actor, loot)
    local itinerary = mission and mission.scout
    local search = itinerary and itinerary.search
    if not Expedition.testSearchFor(actor) or search == nil
        or type(loot) ~= "table" or loot.verified ~= true
        or loot.missionId ~= mission.radioSession
        or loot.requestedCategory ~= search.request.category
        or type(loot.stableId) ~= "string" or #loot.stableId == 0
        or #loot.stableId > 160
        or type(loot.type) ~= "string" then return false end
    for _, receipt in ipairs(search.acquisitions) do
        if receipt.id == loot.stableId then return false end
    end
    if #search.acquisitions >= 16 then return false end
    local source = {
        x = loot.sourceX, y = loot.sourceY, z = loot.sourceZ,
    }
    local sourceObjectIndex = tonumber(loot.sourceObjectIndex)
    if sourceObjectIndex == nil or sourceObjectIndex < 0
        or sourceObjectIndex > 65535
        or sourceObjectIndex ~= math.floor(sourceObjectIndex) then
        sourceObjectIndex = nil
    end
    search.acquisitions[#search.acquisitions + 1] = {
        id = loot.stableId, itemType = loot.type,
        memberId = mission.leader.id,
        source = validPoint(source) and source or nil,
        sourceObjectIndex = sourceObjectIndex,
    }
    return true
end

function Expedition.clearTestSearch(actor)
    if mission == nil or mission.leader.actor ~= actor then
        return false, "leader_unavailable"
    end
    mission.testSearch = false
    mission.testSearchTarget = nil
    mission.testSearchCategory = nil
    return true
end

function Expedition.noteTestWaypointArrived(actor)
    if mission == nil or mission.leader.actor ~= actor
        or mission.testWaypoint == nil then return false end
    mission.testWaypointArrival = {
        x = actor:getX(), y = actor:getY(), z = actor:getZ(),
    }
    mission.testWaypoint = nil
    mission.testWaypointArrived = true
    mission.cohesionHold = nil
    if mission.scout ~= nil then
        mission.scout.legs = mission.scout.legs + 1
        mission.scout.lastStalledTarget = nil
        mission.scout.replans = 0
        if mission.scout.phase == "outbound"
            and #mission.scout.trail < (mission.scout.extended and 128 or 64) then
            local point = {
                x = math.floor(actor:getX()), y = math.floor(actor:getY()),
                z = math.floor(actor:getZ()),
            }
            local previous = mission.scout.trail[#mission.scout.trail]
            if point.x ~= previous.x or point.y ~= previous.y then
                mission.scout.trail[#mission.scout.trail + 1] = point
            end
        end
    end
    return true
end

local function exteriorRoute(path, sourceRoom)
    local outside = sourceRoom == nil
    for _, node in ipairs(path) do
        local room = node:getRoom()
        if outside and room ~= nil then return false end
        if sourceRoom ~= nil and room ~= sourceRoom then
            if room ~= nil then return false end
            outside = true
        end
    end
    return outside
end

-- Plan just one loaded local leg at a time. The promoted leader streams the
-- next area while walking; an unloaded destination must never be handed to
-- the ordinary local pathfinder. Outdoor legs keep followers from entering a
-- locked building that only the leader could unlock from its inside face.
local function nextScoutLeg(actor, target, excluded, allowInteriorRoute,
        roadRoute)
    local source = actor:getCurrentSquare()
    local world = type(getWorld) == "function" and getWorld() or nil
    local cell = world and world:getCell() or nil
    local x, y, z = SC.GameplayUtil.position(actor)
    if source == nil or cell == nil or x == nil or y == nil or z == nil
        or SC.Navigation == nil or type(SC.Navigation.findPath) ~= "function" then
        return nil, "scout_area_unavailable"
    end
    local dx, dy = target.x - x, target.y - y
    local distance = math.sqrt(dx * dx + dy * dy)
    if distance < 1 then return nil, "scout_already_near_target" end
    if allowInteriorRoute and distance <= 18
        and not (excluded and excluded.x == target.x
            and excluded.y == target.y) then
        local destination = cell:getGridSquare(target.x, target.y, target.z)
        if destination ~= nil and SC.GameplayUtil.isSquareFree(destination) then
            local path = SC.Navigation.findPath(source, destination, {
                actor = actor, nodeBudget = 2500,
            })
            if path ~= nil and #path >= 2 and #path <= 80
                and (roadRoute == nil or SC.ExpeditionRoute.withinCorridor(
                    roadRoute, path)) then
                if roadRoute ~= nil and roadRoute.index <= 1
                    and #path <= 40 then
                    -- An indoor road-entry connector is already fully loaded.
                    -- Let native Navigation keep its door approach intact.
                    return { x = target.x, y = target.y, z = target.z }
                end
                -- The synchronous survey establishes a traversable route, but
                -- an ordinary move to its far end must plan again under the
                -- shared per-frame navigation budget. Locked portals can put
                -- that second search past the scout's stall interval. Walk
                -- the verified route in short native legs so each request
                -- reaches its first door or window before the next survey.
                local node = path[math.min(#path, 5)]
                local nx, ny, nz = SC.GameplayUtil.position(node)
                if nx ~= nil and ny ~= nil and nz ~= nil then
                    return { x = math.floor(nx), y = math.floor(ny),
                        z = math.floor(nz) }
                end
            end
        end
    end
    local forwardX, forwardY = dx / distance, dy / distance
    local sideX, sideY = -forwardY, forwardX
    local sourceRoom = source:getRoom()
    local attempts = {}
    for _, length in ipairs({ math.min(12, distance),
            math.min(10, distance), math.min(8, distance),
            math.min(5, distance), math.min(3, distance) }) do
        for _, lateral in ipairs({ 0, 3, -3, 6, -6, 10, -10,
                14, -14, 18, -18 }) do
            local tx = math.floor(x + forwardX * length + sideX * lateral)
            local ty = math.floor(y + forwardY * length + sideY * lateral)
            local projected = (tx - x) * forwardX + (ty - y) * forwardY
            if projected > 1 and not (excluded ~= nil
                and excluded.x == tx and excluded.y == ty) then
                local square = cell:getGridSquare(tx, ty, target.z)
                if square ~= nil and square:getRoom() == nil
                    and SC.GameplayUtil.isSquareFree(square) then
                    local path = SC.Navigation.findPath(source, square,
                        { actor = actor, nodeBudget = 1800 })
                    local direct = math.sqrt((tx - x)^2 + (ty - y)^2)
                    if path ~= nil and #path >= 2
                        and #path <= direct * 1.8 + 8
                        and exteriorRoute(path, sourceRoom)
                        and (roadRoute == nil
                            or SC.ExpeditionRoute.withinCorridor(
                                roadRoute, path)) then
                        -- Use a nearby point on this verified route. The
                        -- native movement owner can then handle the corner
                        -- before the itinerary asks it to cross a building.
                        local node = path[math.min(#path, 8)]
                        local nx, ny, nz = SC.GameplayUtil.position(node)
                        if nx ~= nil and ny ~= nil and nz ~= nil
                            and not (excluded ~= nil
                                and excluded.x == math.floor(nx)
                                and excluded.y == math.floor(ny)) then
                            return { x = math.floor(nx), y = math.floor(ny),
                                z = math.floor(nz) }
                        end
                    end
                    attempts[#attempts + 1] = tostring(tx) .. "," .. tostring(ty)
                end
            end
        end
    end
    return nil, "scout_no_exterior_path:" .. tostring(#attempts)
end

local function scoutFollowersNearLeader()
    local leader = mission.leader.actor
    local lx, ly, lz = SC.GameplayUtil.position(leader)
    if lx == nil or ly == nil or lz == nil then return false end
    for _, record in ipairs(mission.roster) do
        if record ~= mission.leader and alive(record) then
            local x, y, z = SC.GameplayUtil.position(record.actor)
            if x == nil or y == nil or z == nil
                or math.floor(z) ~= math.floor(lz)
                or math.sqrt((x - lx)^2 + (y - ly)^2) >= 12 then
                return false
            end
        end
    end
    return true
end

local function scoutSiteSnapshot(actor, runtime, worldHour, now)
    if SC.Senses == nil or type(SC.Senses.cached) ~= "function" then
        return nil, "senses_unavailable"
    end
    local snapshot = SC.Senses.cached(actor, runtime)
    local actorSquare = actor:getCurrentSquare()
    local origin = snapshot and snapshot.origin
    local originSquare = origin and origin.square
    if snapshot == nil or snapshot.valid ~= true then
        return nil, "snapshot_unavailable"
    end
    if type(snapshot.time) ~= "number"
        or snapshot.time > now + 1000 or now - snapshot.time > 2000 then
        return nil, "snapshot_stale"
    end
    if actorSquare == nil or originSquare == nil
        or SC.GameplayUtil.squareKey(actorSquare)
            ~= SC.GameplayUtil.squareKey(originSquare) then
        return nil, "snapshot_origin_changed"
    end
    local world = type(getWorld) == "function" and getWorld() or nil
    local cell = world and world:getCell() or nil
    if cell == nil or type(SC.GameplayUtil.canSee) ~= "function" then
        return nil, "site_squares_unavailable"
    end
    local ax, ay, az = math.floor(actor:getX()),
        math.floor(actor:getY()), math.floor(actor:getZ())
    local visibleSquares = 0
    for _, dx in ipairs({ -4, 0, 4 }) do
        for _, dy in ipairs({ -4, 0, 4 }) do
            local square = cell:getGridSquare(ax + dx, ay + dy, az)
            if square ~= nil and (square == actorSquare
                or SC.GameplayUtil.canSee(actor, square) == true) then
                visibleSquares = visibleSquares + 1
            end
        end
    end
    if visibleSquares == 0 then return nil, "site_not_visible" end
    local native = snapshot.nativeDiscovery
    local complete = snapshot.scanComplete == true
        and snapshot.scanDiscoveryComplete == true
        and snapshot.scanVisualComplete == true
        and (type(native) ~= "table"
            or (native.complete == true and native.freshComplete == true))
    local seen = 0
    for _, threat in ipairs(snapshot.threats or {}) do
        if threat.visible == true and threat.obstructed ~= true then
            seen = seen + 1
        end
    end
    return {
        status = complete and "complete" or "partial",
        at = { x = math.floor(actor:getX()),
            y = math.floor(actor:getY()), z = math.floor(actor:getZ()) },
        worldHour = worldHour,
        scannedSquares = math.min(10000,
            math.max(0, math.floor(tonumber(snapshot.scannedSquares) or 0))),
        visibleSquares = visibleSquares,
        visibleThreats = math.min(128, seen),
    }
end

startReturnFromSite = function(itinerary, reason)
    if itinerary.search ~= nil then
        itinerary.search.endReason = reason
        if SC.Encounter and type(SC.Encounter.cancelScavenge) == "function" then
            SC.Encounter.cancelScavenge(mission.leader.actor,
                "expedition_search_finished")
        end
    else
        itinerary.endReason = reason
    end
    itinerary.phase = "inbound"
    itinerary.returnIndex = math.max(0, #itinerary.trail - 1)
    itinerary.observingSince = nil
    if itinerary.road ~= nil then
        local avoidance = itinerary.roadAvoidance
            or itinerary.road.avoidance
        -- The return intent is authoritative even when native route planning
        -- must wait or fails. A saved technical hold must never restore an
        -- outbound descriptor into an inbound mission.
        itinerary.road.phase = "inbound"
        itinerary.road.goal = copyPoint(itinerary.returnPoint)
        itinerary.road.avoidance = copyRoadAvoidance(avoidance)
        local route, routeReason = SC.ExpeditionRoute.plan(
            mission.leader.actor, itinerary.returnPoint, true,
            avoidance)
        if route == nil then
            mission.technicalIssue = { reason = routeReason or "road_return_unavailable" }
            itinerary.roadRoute = nil
        else
            local entryReady, entryReason = SC.ExpeditionRoute.verifyEntry(
                route, mission.leader.actor)
            if not entryReady then
                mission.technicalIssue = { reason = entryReason }
                itinerary.roadRoute = nil
                return
            end
            itinerary.roadRoute = route
            itinerary.road = SC.ExpeditionRoute.descriptor(route, "inbound")
        end
    end
end

-- The trail consists of actually reached local waypoints. Use its measured
-- outbound pace and length to reserve a return window along the same ground.
-- Before four tiles of evidence, use a conservative fallback rather than
-- treating an unmeasured route as instantaneous. This remains an estimate:
-- combat, new obstacles and a lagging follower can still delay arrival.
local function estimatedReturnHours(itinerary, actor, worldHour)
    local trail = itinerary.trail
    local distance = 0
    for index = 2, #trail do
        local previous, point = trail[index - 1], trail[index]
        distance = distance + math.sqrt((point.x - previous.x)^2
            + (point.y - previous.y)^2)
    end
    local x, y = SC.GameplayUtil.position(actor)
    local last = trail[#trail]
    if x ~= nil and y ~= nil then
        distance = distance + math.sqrt((x - last.x)^2 + (y - last.y)^2)
    end
    local elapsed = math.max(0, worldHour - itinerary.departureHour)
    local hoursPerTile = distance >= 4 and elapsed >= 0.01
        and math.max(0.001, elapsed / distance) or 0.005
    return math.max(0.25, distance * hoursPerTile * 1.5 + 0.1)
end

local function pulseScout()
    local scout = mission and mission.scout
    if scout == nil or mission.restoring or mission.technicalIssue
        or not alive(mission.leader) then return end
    local now = SC.GameplayUtil.nowMs()
    if scout.road ~= nil and scout.roadRoute == nil
        and (scout.phase == "outbound" or scout.phase == "inbound") then
        local goal = scout.phase == "inbound"
            and scout.returnPoint or scout.destination
        local route, routeReason = SC.ExpeditionRoute.plan(
            mission.leader.actor, goal, true,
            scout.road.avoidance)
        if route == nil then
            mission.technicalIssue = {
                reason = routeReason or "road_restart_replan_failed" }
            return
        end
        local entryReady, entryReason = SC.ExpeditionRoute.verifyEntry(
            route, mission.leader.actor)
        if not entryReady then
            mission.technicalIssue = { reason = entryReason }
            return
        end
        scout.roadRoute = route
        scout.road = SC.ExpeditionRoute.descriptor(route, scout.phase)
    end
    if now >= (scout.nextReturnCheckAt or -math.huge)
        and (scout.turnHomeAtHour ~= nil or scout.arriveByHour ~= nil)
        and (scout.phase == "outbound" or scout.phase == "observing"
            or scout.phase == "searching") then
        -- The world-hour getter and trail estimate need only a one-second
        -- cadence; the ordinary movement pulse may run every game frame.
        scout.nextReturnCheckAt = now + 1000
        local worldHour = scoutWorldHour()
        if worldHour == nil then
            mission.technicalIssue = { reason = "expedition_clock_unavailable" }
            return
        end
        local returnReason
        if scout.turnHomeAtHour ~= nil
            and worldHour >= scout.turnHomeAtHour then
            returnReason = "return_time_reached"
        elseif scout.arriveByHour ~= nil
            and worldHour + estimatedReturnHours(scout,
                mission.leader.actor, worldHour) >= scout.arriveByHour then
            returnReason = "arrival_reserve_reached"
        end
        if returnReason ~= nil then
            local leader = mission.leader.actor
            if mission.testWaypoint ~= nil then
                Expedition.clearTestWaypoint(leader)
                local owner = SC.ActionSupervisor
                    and type(SC.ActionSupervisor.current) == "function"
                    and SC.ActionSupervisor.current(leader) or nil
                if owner == nil and SC.Navigation
                    and type(SC.Navigation.cancel) == "function" then
                    SC.Navigation.cancel(leader, "expedition_return_time")
                end
            end
            startReturnFromSite(scout, returnReason)
            return
        end
    end
    local wounded, woundedRecord, woundedHealth =
        squadNeedsWithdrawal(mission.roster)
    if wounded and scout.phase == "outbound" then
        -- The expedition is optional; a bleeding or critically weak member
        -- turns the whole party home. Preserve a visible roadside hazard so
        -- the return planner does not simply retrace through the fight.
        if scout.roadRoute ~= nil then
            local leader = mission.leader.actor
            local registered = SC.Registry.byId(mission.leader.id)
            local snapshot = SC.Senses and SC.Senses.cached
                and SC.Senses.cached(leader,
                    registered and registered.runtime) or nil
            local living = 0
            for _, record in ipairs(mission.roster) do
                if alive(record) then living = living + 1 end
            end
            scout.roadAvoidance = SC.ExpeditionRoute.visibleHorde(
                scout.roadRoute, leader, snapshot, living, now,
                math.max(2, living - 2))
        end
        if type(SC.GameplayUtil.diagnostic) == "function" then
            SC.GameplayUtil.diagnostic("expedition-squad", mission.leader.actor,
                "action=withdraw member=" .. tostring(woundedRecord.id)
                    .. " health=" .. tostring(math.floor(woundedHealth)))
        end
        startReturnFromSite(scout, "squad_wounded")
        return
    end
    if mission.cohesionHold ~= nil and not wounded then return end
    if scout.roadRoute ~= nil
        and (scout.phase == "outbound" or scout.phase == "inbound")
        and now >= (scout.nextHordeCheckAt or 0) then
        scout.nextHordeCheckAt = now + 1000
        local leader = mission.leader.actor
        local registered = SC.Registry.byId(mission.leader.id)
        local snapshot = SC.Senses and SC.Senses.cached
            and SC.Senses.cached(leader,
                registered and registered.runtime) or nil
        local living = 0
        for _, record in ipairs(mission.roster) do
            if alive(record) then living = living + 1 end
        end
        local avoidance = SC.ExpeditionRoute.visibleHorde(
            scout.roadRoute, leader, snapshot, living, now,
            wounded and math.max(2, living - 2) or nil)
        local previous = scout.road and scout.road.avoidance
        if avoidance ~= nil and previous ~= nil
            and math.sqrt((avoidance.x - previous.x)^2
                + (avoidance.y - previous.y)^2)
                    <= math.max(avoidance.radius, previous.radius) + 4 then
            avoidance = nil
        end
        if avoidance ~= nil then
            -- Stop the old travel intent before planning around observed
            -- zombies. Combat and other urgent owners remain authoritative.
            if mission.testWaypoint ~= nil then
                Expedition.clearTestWaypoint(leader)
                local owner = SC.ActionSupervisor
                    and type(SC.ActionSupervisor.current) == "function"
                    and SC.ActionSupervisor.current(leader) or nil
                if owner == nil and SC.Navigation
                    and type(SC.Navigation.cancel) == "function" then
                    SC.Navigation.cancel(leader, "expedition_horde_detour")
                end
            end
            local destination = scout.phase == "inbound"
                and scout.returnPoint or scout.destination
            local alternative, routeReason
            if (scout.hordeDetours or 0) < 3 then
                alternative, routeReason = SC.ExpeditionRoute.plan(
                    leader, destination, true, avoidance)
                if alternative ~= nil then
                    local entryReady, entryReason =
                        SC.ExpeditionRoute.verifyEntry(alternative, leader)
                    if not entryReady then
                        alternative = nil
                        routeReason = entryReason
                    end
                end
            else
                routeReason = "horde_detour_limit"
            end
            if alternative ~= nil then
                scout.roadRoute = alternative
                scout.road = SC.ExpeditionRoute.descriptor(
                    alternative, scout.phase)
                scout.hordeDetours = (scout.hordeDetours or 0) + 1
                scout.lastStalledTarget = nil
                scout.firstPlanFailureAt = nil
                scout.replans = 0
            elseif scout.phase == "outbound" then
                scout.roadAvoidance = avoidance
                scout.lastRoadFailure = routeReason
                startReturnFromSite(scout, "horde_no_safe_detour")
            else
                mission.technicalIssue = {
                    reason = routeReason or "horde_no_safe_detour" }
            end
            return
        end
    end
    if mission.testWaypoint ~= nil then
        local leader = mission.leader.actor
        local remaining = distanceToPoint(leader, mission.testWaypoint)
        if (scout.bestDistanceToWaypoint or math.huge) - remaining >= 0.75 then
            scout.bestDistanceToWaypoint = remaining
            scout.lastProgressAt = now
            scout.replans = 0
            return
        end
        if now - (scout.lastProgressAt or now) < 8000
            and now - (scout.waypointStagedAt or now) < 30000 then
            return
        end
        -- Smashing, clearing and climbing a window can hold the leader on the
        -- approach square longer than the walking stall interval. Keep the
        -- current portal waypoint while native traversal owns the actor;
        -- replanning here chooses a second window before the first is used.
        local traversal = SC.NativeTraversalActions
        if traversal and type(traversal.activityStatus) == "function" then
            local phase, _, _, _, record = traversal.activityStatus(leader, now)
            if phase == "active" then
                scout.lastProgressAt = now
                return
            end
            if record and record.phase == "completed"
                and (record.finishedAt or 0)
                    > (scout.lastTraversalCompletionAt or 0) then
                scout.lastTraversalCompletionAt = record.finishedAt
                scout.lastProgressAt = now
                return
            end
        end
        local owner = SC.ActionSupervisor
            and type(SC.ActionSupervisor.current) == "function"
            and SC.ActionSupervisor.current(leader) or nil
        if owner ~= nil then return end
        if scout.roadRoute ~= nil
            and SC.ExpeditionRoute.skipLane(scout.roadRoute) then
            scout.lastStalledTarget = nil
            Expedition.clearTestWaypoint(leader)
            if SC.Navigation and type(SC.Navigation.cancel) == "function" then
                SC.Navigation.cancel(leader, "road_lane_unreachable")
            end
            return
        end
        scout.replans = (scout.replans or 0) + 1
        if scout.replans > 5 then
            if scout.phase == "outbound" then
                Expedition.clearTestWaypoint(leader)
                if SC.Navigation and type(SC.Navigation.cancel) == "function" then
                    SC.Navigation.cancel(leader, "scout_road_stall_return")
                end
                scout.replans = 0
                startReturnFromSite(scout, scout.travelMode == "road"
                    and "road_path_unreachable"
                    or "straight_path_unreachable")
            else
                -- Repeated contact at one road segment may keep Combat in
                -- charge even though the leader cannot advance west. Try a
                -- different street around the visible contact before ending
                -- an inbound mission in a permanent technical hold.
                local rerouted = false
                if scout.roadRoute ~= nil
                    and (scout.hordeDetours or 0) < 3 then
                    local registered = SC.Registry.byId(mission.leader.id)
                    local snapshot = SC.Senses and SC.Senses.cached
                        and SC.Senses.cached(leader,
                            registered and registered.runtime) or nil
                    local living = 0
                    for _, record in ipairs(mission.roster) do
                        if alive(record) then living = living + 1 end
                    end
                    local avoidance = SC.ExpeditionRoute.visibleHorde(
                        scout.roadRoute, leader, snapshot, living, now, 0)
                    if avoidance then
                        local route = SC.ExpeditionRoute.plan(
                            leader, scout.returnPoint, true, avoidance)
                        local ready = route and SC.ExpeditionRoute.verifyEntry(
                            route, leader)
                        if ready then
                            Expedition.clearTestWaypoint(leader)
                            if SC.Navigation
                                and type(SC.Navigation.cancel) == "function" then
                                SC.Navigation.cancel(leader,
                                    "scout_combat_stall_detour")
                            end
                            scout.roadRoute = route
                            scout.road = SC.ExpeditionRoute.descriptor(
                                route, "inbound")
                            scout.hordeDetours = (scout.hordeDetours or 0) + 1
                            scout.replans = 0
                            scout.lastProgressAt = now
                            rerouted = true
                        end
                    end
                end
                if not rerouted then
                    mission.technicalIssue = { reason = "scout_stall_replan_limit" }
                end
            end
            return
        end
        scout.lastStalledTarget = copyPoint(mission.testWaypoint)
        Expedition.clearTestWaypoint(leader)
        if SC.Navigation and type(SC.Navigation.cancel) == "function" then
            SC.Navigation.cancel(leader, "scout_stalled")
        end
    end
    if scout.phase == "outbound" and scout.site ~= nil
        and scout.siteApproachConfirmed ~= true then
        local siteDistance = distanceToPoint(mission.leader.actor,
            scout.destination)
        if siteDistance <= 18 and now >= (scout.nextSiteCheckAt or 0) then
            scout.nextSiteCheckAt = now + 3000
            local places = SC.ExpeditionPlaces
            local approach, approachReason
            if places and type(places.loadedSiteApproach) == "function" then
                approach, approachReason = places.loadedSiteApproach(
                    scout.site.id, mission.leader.actor)
            else
                approachReason = "place_approach_unavailable"
            end
            if approach ~= nil then
                scout.destination = { x = approach.x, y = approach.y,
                    z = approach.z }
                if scout.roadRoute then
                    scout.roadRoute.goal = copyPoint(scout.destination)
                    scout.road.goal = copyPoint(scout.destination)
                end
                scout.siteApproachConfirmed = true
                scout.siteApproachFailureAt = nil
                scout.lastPlanFailure = nil
                scout.firstPlanFailureAt = nil
            else
                scout.lastPlanFailure = approachReason
                    or "approach_no_loaded_path"
                scout.siteApproachFailureAt = scout.siteApproachFailureAt
                    or now
            end
        end
        if siteDistance <= 4 and scout.siteApproachConfirmed ~= true then
            if scout.siteApproachFailureAt ~= nil
                and now - scout.siteApproachFailureAt >= 30000 then
                startReturnFromSite(scout, "site_unreachable")
            end
            return
        end
    end
    if scout.phase == "observing" then
        scout.observingSince = scout.observingSince or now
        local elapsed = now - scout.observingSince
        if elapsed < 5000 then return end
        local worldHour = scoutWorldHour()
        if worldHour == nil then
            if elapsed >= 30000 then
                mission.technicalIssue = { reason = "scout_clock_unavailable" }
            end
            return
        end
        local registered = SC.Registry.byId(mission.leader.id)
        local observation, observationReason = scoutSiteSnapshot(
            mission.leader.actor, registered and registered.runtime,
            worldHour, now)
        scout.observationReason = observationReason
        if observation == nil and elapsed < 30000 then return end
        scout.observation = observation or {
            status = "unavailable",
            at = { x = math.floor(mission.leader.actor:getX()),
                y = math.floor(mission.leader.actor:getY()),
                z = math.floor(mission.leader.actor:getZ()) },
            worldHour = worldHour, scannedSquares = 0,
            visibleSquares = 0,
        }
        if observation ~= nil and observation.status ~= "complete"
            and elapsed < 30000 then return end
        startReturnFromSite(scout, "observed")
        return
    end
    if scout.phase == "searching" then
        if not scoutFollowersNearLeader() then return end
        local search = scout.search
        if #search.acquisitions >= search.request.quantity then
            startReturnFromSite(scout, "quantity_met")
            return
        end
        local worldHour = scoutWorldHour()
        if worldHour == nil then
            mission.technicalIssue = { reason = "search_clock_unavailable" }
            return
        end
        if worldHour >= search.deadlineHour then
            startReturnFromSite(scout, "search_deadline")
            return
        end
        local audit = SC.Logistics and SC.Logistics.audit(
            mission.leader.actor) or nil
        if audit and tonumber(audit.capacity) and audit.capacity > 0
            and tonumber(audit.weight) and tonumber(audit.hardRatio)
            and audit.weight >= audit.capacity * audit.hardRatio then
            startReturnFromSite(scout, "capacity_full")
        end
        return
    end
    if not scoutFollowersNearLeader() then return end
    if scout.phase == "awaiting_player" then
        local player = getSpecificPlayer(0)
        if player ~= nil then Expedition.finishAtPlayer(player) end
        return
    end
    local target = scout.phase == "outbound" and scout.destination
        or scout.returnIndex ~= nil and scout.returnIndex >= 1
            and scout.trail[scout.returnIndex] or scout.returnPoint
    if scout.roadRoute ~= nil then
        local registered = SC.Registry.byId(mission.leader.id)
        local snapshot = SC.Senses and SC.Senses.cached
            and SC.Senses.cached(mission.leader.actor,
                registered and registered.runtime) or nil
        target = SC.ExpeditionRoute.target(scout.roadRoute,
            mission.leader.actor, snapshot) or target
        local crossing = SC.ExpeditionRoute.takeJunction(scout.roadRoute)
        if crossing ~= nil and now - (scout.lastJunctionCalloutAt or -math.huge)
                >= 30000 and SC.Dialogue
                and type(SC.Dialogue.say) == "function"
                and type(ZombRand) == "function" and ZombRand(100) < 40 then
            local candidates = {}
            for _, member in ipairs(mission.roster) do
                if alive(member) and distanceToPoint(member.actor,
                        crossing) <= 12 then
                    local lastSpoken = type(SC.Dialogue.lastSpokenAt)
                        == "function" and SC.Dialogue.lastSpokenAt(member.actor)
                        or -math.huge
                    if now - lastSpoken >= 10000 then
                        candidates[#candidates + 1] = member.actor
                    end
                end
            end
            if #candidates > 0 then
                local speaker = candidates[ZombRand(#candidates) + 1]
                local spoken = SC.Dialogue.say(speaker,
                    "expedition.road_intersection", nil,
                    { crossing.street or "the next road" })
                if spoken then scout.lastJunctionCalloutAt = now end
            end
        end
    end
    local close = distanceToPoint(mission.leader.actor, target)
    if scout.phase == "outbound" and close <= 4
        and (scout.roadRoute == nil
            or scout.roadRoute.index > #scout.roadRoute.points) then
        if scout.search then
            local worldHour = scoutWorldHour()
            if worldHour == nil then
                mission.technicalIssue = { reason = "search_clock_unavailable" }
                return
            end
            scout.search.startedHour = worldHour
            scout.search.deadlineHour = worldHour + SEARCH_HOURS
            scout.phase = "searching"
        else
            scout.phase = "observing"
            scout.observingSince = now
        end
        return
    end
    if scout.roadRoute == nil and scout.phase == "inbound" and scout.returnIndex ~= nil
        and scout.returnIndex >= 1 and close <= 4 then
        scout.returnIndex = scout.returnIndex - 1
        return
    end
    if scout.phase == "inbound" and (scout.roadRoute ~= nil
            and scout.roadRoute.index > #scout.roadRoute.points
            or scout.roadRoute == nil and (scout.returnIndex == nil
                or scout.returnIndex == 0)) and close <= 4 then
        scout.phase = "awaiting_player"
        local player = getSpecificPlayer(0)
        if player ~= nil then Expedition.finishAtPlayer(player) end
        return
    end
    if scout.legs >= (scout.extended and 256 or 64) then
        mission.technicalIssue = { reason = "scout_leg_limit" }
        return
    end
    if now - (scout.lastPlanAt or -math.huge) < 1500 then return end
    scout.lastPlanAt = now
    local leaderSquare = mission.leader.actor:getCurrentSquare()
    local leaderInRoom = leaderSquare ~= nil
        and leaderSquare:getRoom() ~= nil
    local leg, reason = nextScoutLeg(mission.leader.actor, target,
        scout.lastStalledTarget,
        SC.ExpeditionRoute.allowInteriorAccess(scout.roadRoute,
            scout.kind, scout.phase, leaderInRoom),
        scout.roadRoute)
    if leg == nil then
        if scout.roadRoute ~= nil
            and SC.ExpeditionRoute.skipLane(scout.roadRoute) then
            scout.lastStalledTarget = nil
            scout.firstPlanFailureAt = nil
            scout.lastPlanFailure = nil
            return
        end
        scout.lastPlanFailure = reason
        if scout.firstPlanFailureAt == nil then scout.firstPlanFailureAt = now end
        if now - scout.firstPlanFailureAt >= 30000 then
            if scout.phase == "outbound" then
                startReturnFromSite(scout, scout.travelMode == "road"
                    and "road_path_unreachable"
                    or "straight_path_unreachable")
            else
                mission.technicalIssue = { reason = reason }
            end
        end
        return
    end
    scout.firstPlanFailureAt = nil
    scout.lastPlanFailure = nil
    local staged, stageReason = Expedition.stageTestWaypoint(
        mission.leader.actor, leg.x, leg.y, leg.z)
    if staged ~= true then
        mission.technicalIssue = { reason = tostring(stageReason) }
    else
        scout.bestDistanceToWaypoint = distanceToPoint(
            mission.leader.actor, leg)
        scout.lastProgressAt = now
        scout.waypointStagedAt = now
    end
end

-- A moving expedition must keep its living tail inside the leader's loaded
-- footprint. The test waypoint is the only route owner in this prototype.
-- Hysteresis gives delayed followers room to rejoin without toggling the
-- leader's route every decision beat. Survival decisions still run while held.
local function updateWaypointCohesion()
    if mission == nil or mission.testWaypoint == nil
        or not alive(mission.leader) then return end
    local leader = mission.leader.actor
    local lx, ly, lz = SC.GameplayUtil.position(leader)
    local leaderSquare = leader:getCurrentSquare()
    local maxGap, laggard, missing = 0, nil, nil
    for _, record in ipairs(mission.roster) do
        local actor = record.actor
        local expected = mission.survivors == nil
            or mission.survivors[record.id] == true
        local dead = actor ~= nil and actor:isDead() == true
        if record ~= mission.leader and expected and not dead then
            if actor == nil or not SC.Registry.isActive(actor, record.id) then
                missing = record.id
            else
                local fx, fy, fz = SC.GameplayUtil.position(actor)
                if actor:getCurrentSquare() == nil or lx == nil or ly == nil
                    or fx == nil or fy == nil
                    or lz == nil or fz == nil
                    or math.floor(fz) ~= math.floor(lz) then
                    missing = record.id
                else
                    local gap = math.sqrt((fx - lx)^2 + (fy - ly)^2)
                    if gap > maxGap then maxGap, laggard = gap, record.id end
                end
            end
        end
    end
    if leaderSquare == nil or lx == nil or ly == nil then
        missing = mission.leader.id
    end
    local held = mission.cohesionHold ~= nil
    -- A stopped scout can strand a pathing follower just outside the tighter
    -- generic release radius at a building corner. Resume a short scout leg
    -- once the tail is back inside eleven tiles; the twelve-tile trigger still
    -- stops the leader immediately if that follower falls behind again.
    local releaseGap = mission.scout and 11 or 8
    if missing ~= nil or maxGap >= (held and releaseGap or 12) then
        mission.cohesionHold = {
            reason = missing and "member_square_missing" or "straggler",
            memberId = missing or laggard, maxGap = maxGap,
        }
        if not held and SC.Navigation and type(SC.Navigation.peek) == "function"
            and type(SC.Navigation.cancel) == "function" then
            local route = SC.Navigation.peek(leader)
            local owner = SC.ActionSupervisor
                and type(SC.ActionSupervisor.current) == "function"
                and SC.ActionSupervisor.current(leader) or nil
            if route and route.goalAction == "ordered_move" and owner == nil then
                SC.Navigation.cancel(leader, "expedition_regroup")
            end
        end
    elseif held then
        mission.cohesionHold = nil
    end
end

function Expedition.contextFor(actor, primary)
    if Expedition.isMember(actor) then
        if mission.restoring then return actor end
        if alive(mission.leader) then return mission.leader.actor end
    end
    return primary
end

function Expedition.notePlacementFailure(actor, reason)
    if not Expedition.isMember(actor) then return false end
    -- Never use the ordinary near-player follower recovery for a remote team.
    -- A missing square is a technical pause until native world ownership is
    -- restored; teleporting to the human would conceal the streaming failure.
    mission.technicalIssue = { actor = actor, reason = tostring(reason) }
    return true
end

function Expedition.notePlacementRestored(actor)
    if mission == nil or mission.technicalIssue == nil
        or mission.technicalIssue.actor ~= actor then return false end
    mission.technicalIssue = nil
    return true
end

local function searchDebrief(itinerary)
    local search = itinerary.search
    local wanted, carried = {}, {}
    for _, receipt in ipairs(search.acquisitions) do wanted[receipt.id] = true end
    local complete = SC.Logistics ~= nil
        and type(SC.Logistics.audit) == "function"
        and type(SC.GameplayUtil.itemStableId) == "function"
    local budget = type(SC.GameplayUtil.config) == "function"
        and tonumber(SC.GameplayUtil.config(
            "logisticsInventoryItemBudget")) or 256
    if complete then
        for _, record in ipairs(mission.roster) do
            if alive(record) then
                local ok, audit = pcall(SC.Logistics.audit, record.actor)
                if not ok or type(audit) ~= "table"
                    or type(audit.items) ~= "table" then
                    complete = false
                else
                    if #audit.items >= budget then complete = false end
                    for _, entry in ipairs(audit.items) do
                        local id = SC.GameplayUtil.itemStableId(entry.item, false)
                        if wanted[id] then carried[id] = true end
                    end
                end
            end
        end
    end
    local returned = {}
    for _, receipt in ipairs(search.acquisitions) do
        if carried[receipt.id] then
            returned[#returned + 1] = receipt.id
        end
    end
    return {
        kind = "search", destination = copyPoint(itinerary.destination),
        returnPoint = copyPoint(itinerary.returnPoint),
        site = copySite(itinerary.site),
        request = copyRequest(search.request),
        acquisitions = copyReceipts(search.acquisitions),
        returnedIds = returned, inventoryComplete = complete,
        endReason = search.endReason or "returned_early",
    }
end

-- The player has physically met the team. Release only slot 1's chunk map;
-- the primary player's map must already cover the leader and all survivors.
function Expedition.finishAtPlayer(player)
    if mission == nil or mission.terminal then return false, "no_active_expedition" end
    if player == nil or getSpecificPlayer(0) ~= player
        or not alive(mission.leader)
        or getSpecificPlayer(1) ~= mission.leader.actor then
        return false, "return_view_unavailable"
    end
    if mission.pendingRadio ~= nil or mission.technicalIssue ~= nil then
        return false, "return_busy_or_paused"
    end
    local px, py, pz = player:getX(), player:getY(), player:getZ()
    for _, record in ipairs(mission.roster) do
        -- A casualty saved before restart has no restored actor. Its stable ID
        -- remains in the historical roster, but only saved survivors need to
        -- assemble at the player before the second view can be released.
        if mission.survivors == nil or mission.survivors[record.id] then
            if record.actor == nil then return false, "return_member_unresolved" end
            if not record.actor:isDead() then
                if not alive(record) or math.abs(record.actor:getX() - px) > 12
                    or math.abs(record.actor:getY() - py) > 12
                    or math.floor(record.actor:getZ()) ~= math.floor(pz) then
                    return false, "return_member_not_assembled"
                end
            end
        end
    end
    if SCSplitScreenProbe == nil
        or SCSplitScreenProbe.canReleaseJoinedLeader() ~= true
        or type(destroyPlayerData) ~= "function" then
        return false, "return_primary_area_unavailable"
    end
    local pendingDebrief = mission.scout and mission.scout.search
        and searchDebrief(mission.scout) or nil
    local identityOk, slotSqlId = pcall(
        SCSplitScreenProbe.persistJoinedLeaderSlotForReuse)
    if not identityOk or not validSlotSqlId(slotSqlId) then
        return false, "return_slot_identity_unavailable:" .. tostring(slotSqlId)
    end
    local uiOk, uiError = pcall(destroyPlayerData, mission.leader.actor)
    if not uiOk then
        mission.technicalIssue = { reason = "return_ui_teardown_failed" }
        return false, tostring(uiError)
    end
    local released, value = pcall(SCSplitScreenProbe.releaseJoinedLeader)
    if not released or value ~= true then
        mission.technicalIssue = { reason = "return_view_release_failed" }
        return false, tostring(value)
    end
    if mission.radioTextHooked then
        Events.OnDeviceText.Remove(radioTextReceived)
    end
    mission.terminal = "returned"
    if mission.scout ~= nil then
        lastDebrief = pendingDebrief or {
            kind = "scout",
            destination = copyPoint(mission.scout.destination),
            returnPoint = copyPoint(mission.scout.returnPoint),
            observation = copyObservation(mission.scout.observation),
            endReason = mission.scout.endReason,
            site = copySite(mission.scout.site),
        }
    end
    mission = nil
    reusableSlotSqlId = slotSqlId
    lastOutcome = "returned"
    return true, "returned"
end

function Expedition.pulse()
    if mission == nil then return false, "no_mission" end
    if mission.terminal then return false, mission.terminal end
    -- Build 42's slot-1 ISHotbar:update() makes a non-joypad bar visible,
    -- while ISHotbar:render() hides every slot above zero. That oscillates the
    -- numbered bar every frame in the companion view. This AI slot has no
    -- hotbar input; remove only its panel from the UI manager once created.
    if mission.leader ~= nil and mission.leader.actor ~= nil
        and getSpecificPlayer(1) == mission.leader.actor
        and type(getPlayerHotbar) == "function" then
        local ok, hotbar = pcall(getPlayerHotbar, 1)
        if ok and hotbar ~= nil and hotbar ~= mission.hiddenHotbar
            and type(hotbar.setVisible) == "function"
            and type(hotbar.removeFromUIManager) == "function" then
            hotbar:setVisible(false)
            hotbar:removeFromUIManager()
            mission.hiddenHotbar = hotbar
        end
    end
    if mission.restoring then
        -- The saved leader's pending snapshot names an authoritative tile. A
        -- hidden native co-op actor may load that tile; the ordinary persistence
        -- owner then restores every exact saved team member into the same world.
        -- Queue the loader once and keep the mission paused until it is replaced.
        if not mission.bootstrapQueued and not mission.bootstrapFailed
            and SCSplitScreenProbe ~= nil
            and getSpecificPlayer(1) == nil then
            local candidate = Expedition.restartBootstrapCandidate()
            if candidate ~= nil then
                local world = type(getWorld) == "function" and getWorld() or nil
                local cell = world and world:getCell()
                if cell ~= nil and cell:getGridSquare(candidate.x,
                    candidate.y, candidate.z) == nil then
                    local ok, loader = pcall(
                        SCSplitScreenProbe.startColdCompanionProbe,
                        candidate.x, candidate.y, candidate.z,
                        candidate.slotSqlId or -1)
                    if not ok or loader == nil then
                        mission.bootstrapFailed = true
                        mission.technicalIssue = {
                            reason = "expedition_restart_loader_failed",
                            detail = tostring(loader),
                        }
                        return false, "expedition_restart_loader_failed"
                    end
                    mission.bootstrapQueued = true
                    mission.bootstrapActor = loader
                    -- Disposable playtest diagnostics retain the disposed actor
                    -- so the live harness can verify world removal after handoff.
                    mission.lastBootstrapActor = loader
                    mission.technicalIssue = {
                        reason = "expedition_restart_loading_native_team",
                    }
                end
            end
        end
        local allReady = true
        for _, record in ipairs(mission.roster) do
            if mission.survivors[record.id] then
                local restored = SC.Registry.byId(record.id)
                record.actor = restored and restored.actor or nil
                if alive(record) then
                    mission.members[record.actor] = true
                else
                    allReady = false
                end
            end
        end
        if not allReady then
            return false, "expedition_restart_waiting_for_native_team"
        end
        local leader = mission.leader
        if not alive(leader) then
            for _, record in ipairs(mission.roster) do
                if alive(record) then leader = record break end
            end
        end
        if not alive(leader) then
            return false, "expedition_restart_has_no_living_leader"
        end
        local slot = getSpecificPlayer(1)
        if slot ~= nil then
            if slot ~= leader.actor then
                if SCSplitScreenProbe.isColdProbe(slot) ~= true
                    or (mission.bootstrapActor ~= nil
                        and slot ~= mission.bootstrapActor) then
                    return false, "expedition_restart_second_slot_occupied"
                end
                if holdColdHandoffForTest then
                    return false, "expedition_restart_handoff_held_for_test"
                end
                local ok, replaced = pcall(
                    SCSplitScreenProbe.replaceColdProbeWithRestoredLeader,
                    leader.actor, mission.slotSqlId or -1)
                if not ok or replaced ~= true then
                    mission.technicalIssue = {
                        reason = "expedition_restart_handoff_failed",
                        detail = tostring(replaced),
                    }
                    return false, "expedition_restart_handoff_failed"
                end
            elseif SCSplitScreenProbe.isLeader(slot) ~= true then
                return false, "expedition_restart_second_slot_occupied"
            end
        else
            if mission.bootstrapQueued then
                return false, "expedition_restart_loader_pending"
            end
            local ok, promoted = pcall(SCSplitScreenProbe.promote,
                leader.actor, mission.slotSqlId or -1)
            if not ok or promoted ~= leader.actor then
                mission.technicalIssue = {
                    reason = "expedition_restart_view_unavailable",
                    detail = tostring(promoted),
                }
                return false, "expedition_restart_view_unavailable"
            end
        end
        mission.leader = leader
        local liveSqlId = SCSplitScreenProbe.leaderSqlId()
        if type(liveSqlId) == "number" and liveSqlId >= 2 then
            mission.slotSqlId = liveSqlId
        end
        mission.restoring = nil
        mission.bootstrapQueued = nil
        mission.bootstrapActor = nil
        mission.bootstrapFailed = nil
        mission.technicalIssue = nil
        if Events and Events.OnDeviceText then
            Events.OnDeviceText.Add(radioTextReceived)
            mission.radioTextHooked = true
        end
        return true, "expedition_resumed"
    end
    -- Keep each ready native corpse in the game's live chunk graph while the
    -- expedition's second view continues moving across map boundaries.
    for _, record in ipairs(mission.roster) do
        if record.actor ~= nil and record.actor:isDead() == true then
            local readyOk, corpseReady = pcall(record.actor.isCorpseReady,
                record.actor)
            if readyOk and corpseReady == true then
                local stagedOk, staged = pcall(
                    SCSplitScreenProbe.stageDeadCorpseChunk, record.actor)
                if not stagedOk or staged ~= true then
                    mission.technicalIssue = {
                        reason = "expedition_corpse_retention_failed",
                        detail = tostring(staged),
                    }
                    return false, tostring(staged)
                end
            end
        end
    end
    if alive(mission.leader) then
        updateWaypointCohesion()
        pulseScout()
        if mission == nil then return true, "returned" end
        return false, mission.cohesionHold and "expedition_regroup"
            or "leader_alive"
    end
    for _, record in ipairs(mission.roster) do
        if record ~= mission.leader and alive(record) then
            local ok, handed = pcall(SCSplitScreenProbe.handoff, record.actor)
            if ok and handed == record.actor then
                mission.leader = record
                mission.pendingRadio = nil
                mission.radioAuthorization = nil
                return true, record.id
            end
            return false, tostring(handed)
        end
    end
    -- Registry retirement can precede the native death transition. The
    -- second chunk map must stay loaded until every dead actor has a native
    -- corpse; unloading it earlier strands the pending bridge ownership.
    for _, record in ipairs(mission.roster) do
        if mission.survivors == nil or mission.survivors[record.id] then
            if record.actor == nil or record.actor:isDead() ~= true then
                return false, "member_pending_death"
            end
            local readyOk, corpseReady = pcall(record.actor.isCorpseReady,
                record.actor)
            if not readyOk or corpseReady ~= true then
                return false, "member_corpse_pending"
            end
        end
    end
    -- Build 42 clears static corpses while unloading the remote chunk map.
    -- Retain exact native chunk bytes before releasing the final view.
    for _, record in ipairs(mission.roster) do
        if mission.survivors == nil or mission.survivors[record.id] then
            local stagedOk, staged = pcall(
                SCSplitScreenProbe.stageDeadCorpseChunk, record.actor)
            if not stagedOk or staged ~= true then
                mission.technicalIssue = { reason = "all_dead_corpse_save_failed" }
                return false, tostring(staged)
            end
        end
    end
    -- Stock split-screen teardown removes all slot-1 panels and their update
    -- callbacks. They otherwise keep dereferencing a cleared player slot.
    if type(destroyPlayerData) ~= "function" then
        return false, "player_ui_teardown_unavailable"
    end
    local slotSaved, releasedSlotSqlId = pcall(
        SCSplitScreenProbe.persistDeadLeaderSlotForReuse)
    if not slotSaved or not validSlotSqlId(releasedSlotSqlId) then
        mission.technicalIssue = { reason = "all_dead_slot_save_failed" }
        return false, tostring(releasedSlotSqlId)
    end
    local uiOk, uiError = pcall(destroyPlayerData, mission.leader.actor)
    if not uiOk then
        mission.technicalIssue = { reason = "all_dead_ui_teardown_failed" }
        return false, tostring(uiError)
    end
    local ok, released = pcall(SCSplitScreenProbe.releaseDeadLeader)
    if not ok or released ~= true then
        mission.technicalIssue = { reason = "all_dead_view_release_failed" }
        return false, tostring(released)
    end
    mission.terminal = "all_dead"
    if validSlotSqlId(releasedSlotSqlId) then
        reusableSlotSqlId = releasedSlotSqlId
    end
    mission.pendingRadio = nil
    mission.radioAuthorization = nil
    if mission.radioTextHooked then
        Events.OnDeviceText.Remove(radioTextReceived)
        mission.radioTextHooked = false
    end
    mission = nil
    lastOutcome = "all_dead"
    return true, lastOutcome
end
