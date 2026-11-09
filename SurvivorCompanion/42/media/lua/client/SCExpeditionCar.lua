-- SPDX-License-Identifier: MIT
-- Read-only expedition car selection and dispatch checks. No car or actor is
-- moved during review; dispatch repeats these checks against live objects.
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.ExpeditionCar = SC.ExpeditionCar or {}
local Car = SC.ExpeditionCar
local returnStreams = setmetatable({}, {__mode="k"})

local function traceTrip(trip, action, detail, driveStatus)
    if type(print) ~= "function" then return end
    if type(driveStatus) == "table" then
        detail = (detail and detail .. " " or "")
            .. "drivePhase=" .. tostring(driveStatus.phase):sub(1, 64)
            .. " result=" .. tostring(driveStatus.result):sub(1, 64)
            .. " reason=" .. tostring(driveStatus.reason):sub(1, 128)
            .. " managed=" .. tostring(driveStatus.managed)
            .. " parked=" .. tostring(driveStatus.parked)
            .. " owned=" .. tostring(driveStatus.owned)
            .. " firstRefusal=" .. tostring(driveStatus.firstParkingRefusal):sub(1, 128)
            .. " alignmentReason=" .. tostring(driveStatus.parkingAlignmentReason):sub(1, 128)
    end
    print("[SurvivorCompanion/expedition-car] car="
        .. tostring(trip and trip.sqlId or "?") .. " action="
        .. tostring(action) .. (detail and " " .. detail or ""))
end

local function call(object, method, ...)
    if object == nil then return false, nil end
    return SC.Call.method(object, method, ...)
end

local function finite(value)
    value = tonumber(value)
    return value and value == value and value ~= math.huge
        and value ~= -math.huge and value or nil
end

local function point(vehicle)
    local xOk, x = call(vehicle, "getX")
    local yOk, y = call(vehicle, "getY")
    local zOk, z = call(vehicle, "getZ")
    if not xOk or not yOk or not zOk then return nil end
    x, y, z = finite(x), finite(y), finite(z)
    if not x or not y or not z then return nil end
    return { x = x, y = y, z = z }
end

local function contains(zone, p)
    return p and zone and math.floor(p.z) == zone.z
        and p.x >= zone.x1 and p.x < zone.x2 + 1
        and p.y >= zone.y1 and p.y < zone.y2 + 1
end

function Car.parkingAreas()
    local base = SC.BaseLife and SC.BaseLife.active and SC.BaseLife.active()
    local zones = base and base.zones or {}
    local result = {}
    for _, zone in ipairs(zones) do
        if zone.kind == "parking" and SC.BaseLife.parkingZoneValid(zone, zones) then
            result[#result + 1] = zone
        end
    end
    return result
end

function Car.areaById(id)
    for _, zone in ipairs(Car.parkingAreas()) do
        if zone.id == id then return zone end
    end
    return nil
end

local validGroups = { alpha = true, bravo = true, charlie = true }

function Car.preference(group)
    if not validGroups[group] then return nil end
    local base = SC.BaseLife and SC.BaseLife.active and SC.BaseLife.active()
    if not base or not base.id then return nil end
    local player = type(getSpecificPlayer) == "function"
        and getSpecificPlayer(0) or nil
    local dataOk, data = call(player, "getModData")
    local byBase = dataOk and type(data) == "table"
        and type(data.SC_SquadParkingCars) == "table"
        and data.SC_SquadParkingCars[base.id] or nil
    local saved = type(byBase) == "table" and byBase[group] or nil
    if type(saved) ~= "table" then return nil end
    return { zoneId = saved.zoneId, sqlId = saved.sqlId }
end

function Car.setPreference(group, zoneId, sqlId)
    if not validGroups[group] then return false end
    local base = SC.BaseLife and SC.BaseLife.active and SC.BaseLife.active()
    if not base or not base.id then return false end
    if zoneId ~= nil and Car.areaById(zoneId) == nil then return false end
    sqlId = sqlId ~= nil and finite(sqlId) or nil
    if sqlId ~= nil and (sqlId < 0 or sqlId ~= math.floor(sqlId)) then
        return false
    end
    local player = type(getSpecificPlayer) == "function"
        and getSpecificPlayer(0) or nil
    local dataOk, data = call(player, "getModData")
    if not dataOk or type(data) ~= "table" then return false end
    if type(data.SC_SquadParkingCars) ~= "table" then
        data.SC_SquadParkingCars = {}
    end
    if type(data.SC_SquadParkingCars[base.id]) ~= "table" then
        data.SC_SquadParkingCars[base.id] = {}
    end
    data.SC_SquadParkingCars[base.id][group] = {
        zoneId = zoneId, sqlId = sqlId,
    }
    return true
end

function Car.displayName(vehicle)
    local scriptOk, script = call(vehicle, "getScript")
    local modelOk, model = call(scriptOk and script or nil, "getCarModelName")
    if not modelOk or type(model) ~= "string" or model == "" then
        modelOk, model = call(scriptOk and script or nil, "getName")
    end
    if modelOk and type(model) == "string" and model ~= ""
        and type(getTextOrNull) == "function" then
        local translatedOk, translated = pcall(getTextOrNull,
            "IGUI_VehicleName" .. model)
        if translatedOk and type(translated) == "string"
            and translated ~= "" then return translated end
    end
    local nameOk, name = call(vehicle, "getScriptName")
    if nameOk and type(name) == "string" and name ~= "" then
        return name:match("[^.]+$") or name
    end
    return "Car"
end

function Car.candidates(zone, vehicles, includeBlocked)
    local result = {}
    if zone == nil or not SC.Vehicle or not SC.Vehicle.loadedVehicles then
        return result
    end
    for _, vehicle in ipairs(vehicles or SC.Vehicle.loadedVehicles()) do
        local at = point(vehicle)
        local inside = contains(zone, at)
        local fits, fitReason
        if inside then fits, fitReason = Car.fitsParking(vehicle, zone, {}) end
        if inside and (fits == true or includeBlocked == true) then
            local okId, sqlId = call(vehicle, "getSqlId")
            local okName, script = call(vehicle, "getScriptName")
            local okSeats, seats = call(vehicle, "getMaxPassengers")
            local fuelOk, tank = call(vehicle, "getPartById", "GasTank")
            local amountOk, fuel = false, nil
            if fuelOk and tank ~= nil then
                amountOk, fuel = call(tank, "getContainerContentAmount")
            end
            sqlId = okId and finite(sqlId) or nil
            if sqlId and sqlId >= 0 then
                result[#result + 1] = {
                    sqlId = math.floor(sqlId), vehicle = vehicle,
                    script = okName and tostring(script) or "?",
                    name = Car.displayName(vehicle), zone = zone,
                    seats = okSeats and tonumber(seats) or 0,
                    fuel = amountOk and finite(fuel) or nil,
                    point = at,
                    unavailableReason = fits ~= true and fitReason or nil,
                }
            end
        end
    end
    table.sort(result, function(a, b) return a.sqlId < b.sqlId end)
    return result
end

function Car.parkedCars(zoneId, includeBlocked)
    local zones = zoneId ~= nil and { Car.areaById(zoneId) }
        or Car.parkingAreas()
    local result, seen = {}, {}
    if not SC.Vehicle or not SC.Vehicle.loadedVehicles then return result end
    local vehicles = SC.Vehicle.loadedVehicles()
    for _, zone in ipairs(zones) do
        for _, car in ipairs(Car.candidates(zone, vehicles, includeBlocked)) do
            local previous = seen[car.sqlId]
            if not previous then
                result[#result + 1] = car
                seen[car.sqlId] = #result
            elseif result[previous].unavailableReason and not car.unavailableReason then
                -- Overlapping zones can contain the same car. A clipped
                -- outline must not hide another zone that fits it fully.
                result[previous] = car
            end
        end
    end
    table.sort(result, function(a, b) return a.sqlId < b.sqlId end)
    return result
end

local function componentReady(vehicle, partId, needsItem)
    local found, part = call(vehicle, "getPartById", partId)
    if not found or part == nil then return false end
    local hasItem, item = call(part, "getInventoryItem")
    local conditionOk, condition = call(part, "getCondition")
    return (not needsItem or hasItem and item ~= nil)
        and conditionOk and finite(condition) ~= nil and condition > 0
end

-- The only calibration currently proven in the remote physical probe is a
-- CarNormal using 0.07 tank units for 158.53 tiles at 10/25 km/h. Inflate
-- that measured rate for manoeuvres, then add the required 50% reserve.
local fuelPerTile = { ["Base.CarNormal"] = 0.07 / 158.53 * 1.25 }
-- Other vanilla and modded cars use the same physical driving path. Budget
-- their fuel conservatively until each script has its own measured rate.
local defaultFuelPerTile = fuelPerTile["Base.CarNormal"] * 2.5
local function fuelRate(script)
    return fuelPerTile[script] or defaultFuelPerTile
end

-- Match the native router's maximum off-road connector. A long driveway is
-- still admitted only when its complete, straight car-width strip is loaded
-- and clear; the return drive covers it in short parking approaches.
local maxRoadAccessTiles = 100
local drivewayApproachTiles = 12

-- Survey the full car-width strip in the loaded cell; a human-sized path is
-- insufficient because its neighbours can be walls or a closed garage.
function Car.accessBetween(vehicle, at, entry)
    if not at or type(entry) ~= "table" then
        return false, "road_access_unavailable"
    end
    local dx, dy = entry.x - at.x, entry.y - at.y
    local length = math.sqrt(dx * dx + dy * dy)
    if length > maxRoadAccessTiles then return false, "road_access_too_far" end
    if length < 0.5 then return true end
    if type(getCell) ~= "function" then return false, "road_access_not_loaded" end
    local okay, cell = pcall(getCell)
    if not okay or cell == nil then return false, "road_access_not_loaded" end
    local px, py = -dy / length, dx / length
    local ux, uy = dx / length, dy / length
    local steps = math.ceil(length * 2)
    -- The old three rays could skip a tile between the centre and edge rays.
    for _, offset in ipairs({ -1.25, -0.625, 0, 0.625, 1.25 }) do
        local lastSquare
        for step = 0, steps do
            local along = math.min(length, step * 0.5)
            local x = at.x + ux * along + px * offset
            local y = at.y + uy * along + py * offset
            local found, square = call(cell, "getGridSquare",
                math.floor(x), math.floor(y), 0)
            if not found or square == nil then
                return false, "road_access_not_loaded"
            end
            local solidOk, solid = call(square, "isSolid")
            local transOk, trans = call(square, "isSolidTrans")
            local treeOk, tree = call(square, "HasTree")
            if not solidOk or not transOk or not treeOk or solid or trans or tree then
                return false, "road_access_blocked"
            end
            local propsOk, props = call(square, "getProperties")
            local stopOk, stop = call(props, "has", "StopCar")
            local shapeOk, shape = call(props, "get", "PhysicsShape")
            if not propsOk or not stopOk or not shapeOk or stop or shape == "Tree" then
                return false, "road_access_blocked"
            end
            local vehicleOk, occupying = call(square, "getVehicleContainer")
            if not vehicleOk or occupying ~= nil and occupying ~= vehicle then
                return false, "road_access_vehicle_blocked"
            end
            if lastSquare and square ~= lastSquare then
                local edgeOk, blocked = call(lastSquare,
                    "isSomethingTo", square)
                if not edgeOk or blocked == true then
                    return false, "road_access_blocked"
                end
            end
            lastSquare = square
        end
    end
    return true
end

function Car.accessReady(vehicle, entry)
    return Car.accessBetween(vehicle, point(vehicle), entry)
end

-- A parked neighbour may block the nearest perpendicular road connector
-- while the lot has a clear diagonal exit. Try at most six nearby mapped
-- attachments, only during review/departure. Every complete corridor keeps
-- the same loaded-ground, wall and vehicle checks as the original choice.
function Car.planRoadAccess(vehicle, at, destination, continuingMission)
    local route, reason, native = SC.ExpeditionRoute.planFromPoint(at, destination, continuingMission)
    if not route then return nil, reason, native end
    local entry = native and { x = finite(native.entryX), y = finite(native.entryY), z = 0 }
    if not entry or not entry.x or not entry.y then return nil, "road_access_unavailable" end
    local clear, blockedReason = Car.accessBetween(vehicle, at, entry)
    if clear then return route, nil, native end
    if blockedReason ~= "road_access_vehicle_blocked" and blockedReason ~= "road_access_blocked" then
        return nil, blockedReason
    end
    local points = route.points or {}
    local first, direction = points[1], nil
    if first and (first.x - entry.x)^2 + (first.y - entry.y)^2 <= 2.25 then
        for index = 2, math.min(#points, 16) do
            local dx, dy = points[index].x - first.x, points[index].y - first.y
            local length = math.sqrt(dx * dx + dy * dy)
            if length >= 1 then direction = { x = dx / length, y = dy / length } break end
        end
    end
    if not direction then return nil, blockedReason end
    for _, offset in ipairs({ 8, -8, 16, -16, 32, -32 }) do
        local candidate = { x = entry.x + direction.x * offset,
            y = entry.y + direction.y * offset, z = 0 }
        if Car.accessBetween(vehicle, at, candidate) then
            local alternate, _, attachment = SC.ExpeditionRoute.planFromPoint(
                candidate, destination, continuingMission)
            local actual = attachment and { x = finite(attachment.entryX),
                y = finite(attachment.entryY), z = 0 }
            -- A projected point beyond a street end is not a mapped exit.
            if alternate and actual and actual.x and actual.y
                and (actual.x - candidate.x)^2 + (actual.y - candidate.y)^2 <= 2.25
                and Car.accessBetween(vehicle, at, actual) then
                return alternate, nil, attachment
            end
        end
    end
    return nil, blockedReason
end

local function equippedOrHeldKey(actor, vehicle)
    if SC.Driving and SC.Driving.hasKey(actor, vehicle) then return true end
    local hotOk, hot = call(vehicle, "isHotwired")
    local ignitionOk, ignition = call(vehicle, "isKeysInIgnition")
    return hotOk and hot == true or ignitionOk and ignition == true
end

local function findSquadKey(records, vehicle)
    local idOk, keyId = call(vehicle, "getKeyId")
    keyId = idOk and finite(keyId) or nil
    local utility = SC.GameplayUtil
    if keyId == nil or not utility or not utility.inventoryItemsDeep
        or not utility.inventory then return nil end
    for _, record in ipairs(records or {}) do
        local inventory = record.actor and utility.inventory(record.actor)
        if inventory then
            for _, item in ipairs(utility.inventoryItemsDeep(inventory, 360, 12)) do
                local itemOk, itemId = call(item, "getKeyId")
                if itemOk and finite(itemId) == keyId then
                    return { record = record, item = item }
                end
            end
        end
    end
    return nil
end

function Car.ensureDriverKey(records, vehicle)
    if type(records) ~= "table" or not records[1]
        or not records[1].actor then return false, "team_unavailable" end
    if equippedOrHeldKey(records[1].actor, vehicle) then return true end
    local found = findSquadKey(records, vehicle)
    if not found then return false, "driver_needs_key" end
    local utility = SC.GameplayUtil
    local target = utility.inventory(records[1].actor)
    local sourceOk, source = call(found.item, "getContainer")
    if not sourceOk or not source or not target then
        return false, "key_owner_unavailable"
    end
    if source ~= target then
        if not utility.transferItemVerified
            or utility.transferItemVerified(source, target, found.item) ~= true then
            return false, "key_transfer_failed"
        end
    end
    if not equippedOrHeldKey(records[1].actor, vehicle) then
        return false, "key_transfer_unverified"
    end
    return true
end

local function preflightSpecific(records, zoneId, sqlId, destination)
    local zone = Car.areaById(zoneId)
    if zone == nil then return nil, "parking_missing" end
    if type(records) ~= "table" or #records < 1 or #records > 4
        or not records[1] or not records[1].actor then
        return nil, "team_unavailable"
    end
    local vehicle = SC.Vehicle and SC.Vehicle.loadedBySqlId
        and SC.Vehicle.loadedBySqlId(sqlId) or nil
    if vehicle == nil then return nil, "car_unavailable" end
    local at = point(vehicle)
    if not contains(zone, at) then return nil, "car_moved" end
    local stationary, stationaryReason = SC.Vehicle.isStationary(vehicle)
    if not stationary then return nil, stationaryReason or "car_moving" end
    local player = type(getSpecificPlayer) == "function"
        and getSpecificPlayer(0) or nil
    local playerOk, playerCar = call(player, "getVehicle")
    if playerOk and playerCar == vehicle then return nil, "player_car" end
    local idOk, script = call(vehicle, "getScriptName")
    if not idOk or type(script) ~= "string" then
        return nil, "car_identity_unavailable"
    end
    local countOk, count = call(vehicle, "getMaxPassengers")
    count = countOk and finite(count) or nil
    if not count or count < #records or count > 32 then
        return nil, "too_few_seats"
    end
    local installedSeats, seatMap, usedSeats = {}, {}, {}
    for seat = 0, count - 1 do
        local installedOk, installed = call(vehicle, "isSeatInstalled", seat)
        local occupantOk, occupant = call(vehicle, "getCharacter", seat)
        if not installedOk or not occupantOk then return nil, "seat_unavailable" end
        if occupant ~= nil then
            return nil, seat == 0 and "seat_unavailable" or "car_has_other_occupants"
        end
        installedSeats[seat] = installed == true
    end
    for index, record in ipairs(records) do
        if record.id == nil or record.actor == nil then
            return nil, "team_unavailable"
        end
        -- The driver needs seat zero. Passengers may use any installed seat
        -- with a real boarding route and a safe exit, including a van's rear.
        local first, last = index == 1 and 0 or 1, index == 1 and 0 or count - 1
        local firstReason
        for seat = first, last do
            if installedSeats[seat] and not usedSeats[seat] then
                local doors, _, doorReason = SC.Vehicle.boardingSquares(
                    record.actor, vehicle, seat, seat == 0)
                local exits = doors and #doors > 0 and SC.Vehicle.safeExitSquares
                    and SC.Vehicle.safeExitSquares(vehicle, seat) or nil
                if exits and #exits > 0 then
                    seatMap[record.id], usedSeats[seat] = seat, true
                    break
                end
                firstReason = firstReason or (not doors or #doors < 1)
                    and (doorReason or "door_inaccessible") or "parking_exit_blocked"
            end
        end
        if seatMap[record.id] == nil then return nil, firstReason or "seat_unavailable" end
    end
    local fits, fitReason = Car.fitsParking(vehicle, zone, seatMap)
    if not fits then return nil, fitReason end
    if not componentReady(vehicle, "Engine") then
        return nil, "engine_unusable"
    end
    for _, part in ipairs({ "TireFrontLeft", "TireFrontRight",
        "TireRearLeft", "TireRearRight" }) do
        if not componentReady(vehicle, part, true) then
            return nil, "wheel_unusable"
        end
    end
    local squadKey = equippedOrHeldKey(records[1].actor, vehicle)
        or findSquadKey(records, vehicle)
    if not squadKey then
        local playerInventory = player and SC.GameplayUtil.inventory
            and SC.GameplayUtil.inventory(player)
        local keyOk, keyId = call(vehicle, "getKeyId")
        local heldOk, held = call(playerInventory, "haveThisKeyId", keyId)
        return nil, keyOk and heldOk and held
            and "driver_needs_key_from_player" or "driver_needs_key"
    end
    local tankOk, tank = call(vehicle, "getPartById", "GasTank")
    local amountOk, fuel = false, nil
    if tankOk and tank ~= nil then
        amountOk, fuel = call(tank, "getContainerContentAmount")
    end
    fuel = amountOk and finite(fuel) or nil
    if fuel == nil then return nil, "fuel_unreadable" end
    if type(destination) ~= "table" or destination.z ~= 0 then
        return nil, "destination_unavailable"
    end
    local route, routeReason, native = Car.planRoadAccess(vehicle, at, destination)
    if not route then return nil, routeReason end
    local entryX = native and finite(native.entryX)
    local entryY = native and finite(native.entryY)
    local exitX = native and finite(native.exitX)
    local exitY = native and finite(native.exitY)
    if not entryX or not entryY or not exitX or not exitY then
        return nil, "road_access_unavailable"
    end
    local access = math.sqrt((at.x - entryX)^2 + (at.y - entryY)^2)
    local rate = fuelRate(script)
    local distance = finite(route.roadLength) or 0
    local required = (distance * 2 + access * 2 + 30) * rate * 1.5
    if fuel < required then return nil, "fuel_insufficient" end
    local headingOk, heading = call(vehicle, "getAngleZ")
    heading = headingOk and finite(heading) or nil
    if heading == nil then return nil, "car_orientation_unavailable" end
    return { zone = zone, sqlId = sqlId, vehicle = vehicle,
        script = script, departure = at, seats = seatMap,
        heading = heading,
        fuel = fuel, fuelRequired = required, route = route,
        entry = { x = entryX, y = entryY, z = 0 },
        exit = { x = exitX, y = exitY, z = 0 },
        access = access }
end

function Car.preflight(records, zoneId, sqlId, destination)
    if zoneId ~= nil and Car.areaById(zoneId) == nil then
        return nil, "parking_missing"
    end
    if sqlId ~= nil then
        if zoneId ~= nil then
            return preflightSpecific(records, zoneId, sqlId, destination)
        end
        for _, car in ipairs(Car.parkedCars(nil, true)) do
            if car.sqlId == sqlId then
                return preflightSpecific(records, car.zone.id, sqlId,
                    destination)
            end
        end
        return nil, "car_unavailable"
    end
    local firstReason
    for _, car in ipairs(Car.parkedCars(zoneId, true)) do
        local plan, reason = preflightSpecific(records, car.zone.id,
            car.sqlId, destination)
        if plan then return plan end
        firstReason = firstReason or reason
    end
    return nil, firstReason or "car_unavailable"
end

local function preparingSupplies(scout)
    return scout and (scout.departurePreparation ~= nil or scout.fishingPreparation ~= nil
        or scout.wood and scout.wood.preparation == true)
end

local function activeSeat(actor)
    local expedition = SC.ExpeditionPrototype
    local mission = expedition and expedition.current and expedition.current()
    local scout = mission and mission.scout
    local trip = scout and scout.vehicle
    local id = actor and SC.Registry and SC.Registry.idOf(actor)
    if not trip or not id or not mission.members[actor] then return nil end
    return mission, trip, trip.seats and trip.seats[id]
end

function Car.boardingOrderFor(actor)
    local mission, trip, seat = activeSeat(actor)
    if not mission or seat == nil then return nil end
    if preparingSupplies(mission.scout) or trip.radioResumeState then return nil end
    if trip.state ~= "walking_to_car" and trip.state ~= "boarding_out"
        and trip.state ~= "returning_to_car"
        and trip.state ~= "boarding_home" then return nil end
    local car = SC.Vehicle.loadedBySqlId(trip.sqlId)
    if car == nil then return nil end
    return { car = car, seat = seat, sqlId = trip.sqlId }
end

-- The seat belongs to this expedition before the driver acquires a lease and
-- remains owned through parked holds and unloading. This exempts passengers
-- from the generic "player left the car" exit policy.
function Car.ownsSeat(actor, vehicle)
    local mission, trip, seat = activeSeat(actor)
    if not mission or seat == nil or trip.state == "abandoned" then return false end
    local idOk, sqlId = call(vehicle, "getSqlId")
    if not idOk or tonumber(sqlId) ~= trip.sqlId then return false end
    local seated, current, actualSeat = SC.Vehicle.isNativeSeated(actor)
    return seated and current == vehicle and actualSeat == seat
end

local function boardingResult(actor, order, accepted, reason, navigationReason)
    local mission, trip, seat = activeSeat(actor)
    if not mission or trip.sqlId ~= order.sqlId or seat ~= order.seat then
        return accepted, reason
    end
    trip.boardingStatus = trip.boardingStatus or {}
    local id = SC.Registry.idOf(actor)
    local previous = trip.boardingStatus[id]
    local now = SC.GameplayUtil.nowMs()
    local reportedAt = previous and previous.reportedAt
    local x, y, z = SC.GameplayUtil.position(actor)
    if accepted ~= true and (not previous or previous.reason ~= reason
        or now - (reportedAt or 0) >= 10000)
        and type(SC.GameplayUtil.diagnostic) == "function" then
        local at = point(order.car)
        SC.GameplayUtil.diagnostic("expedition-car-boarding", actor,
            "action=approach_failed car=" .. tostring(order.sqlId)
                .. " seat=" .. tostring(seat) .. " reason=" .. tostring(reason)
                .. " actor=" .. tostring(x) .. "," .. tostring(y) .. "," .. tostring(z)
                .. " carPoint=" .. tostring(at and at.x) .. "," .. tostring(at and at.y))
        reportedAt = now
    end
    trip.boardingStatus[id] = { reason = reason, accepted = accepted == true,
        navigationReason = navigationReason or previous and previous.navigationReason,
        x = x, y = y, z = z, at = now, reportedAt = reportedAt }
    return accepted, reason
end

function Car.boardMember(actor, order, snapshot)
    local car, seat = order.car, order.seat
    local mission, trip = activeSeat(actor)
    if mission and trip.sqlId == order.sqlId and preparingSupplies(mission.scout) then
        return false, "expedition_preparing_supplies"
    end
    if mission and trip.radioResumeState then return false, "home_radio_holding" end
    local seated, current, actualSeat = SC.Vehicle.isNativeSeated(actor)
    if seated then
        if current == car and actualSeat == seat then
            return boardingResult(actor, order, true, "already_boarded")
        end
        return boardingResult(actor, order, false, "wrong_vehicle_or_seat")
    end
    local began, beginReason = SC.Vehicle.beginBoarding(actor, car, seat,
        { driverSeat = seat == 0,
            playerCommand = order.hotwire == true or order.fieldWork == true })
    if began == nil then return boardingResult(actor, order, false, beginReason) end
    local prepared, reason = SC.Vehicle.preflightBoard(actor, car, seat,
        seat == 0)
    if prepared then
        if mission and trip.sqlId == order.sqlId and seat > 0 then
            local partOk, part = call(car, "getPassengerDoor", seat)
            local doorOk, door = call(part, "getDoor")
            local lockedOk, locked = call(door, "isLocked")
            if partOk and doorOk and lockedOk and locked == true then
                -- A passenger can arrive before the key holder/driver. Native
                -- entry would fail this lock and exhaust retries before the
                -- driver's next unlock pulse. Wait at the door instead.
                if SC.Navigation and SC.Navigation.cancel then SC.Navigation.cancel(actor, "waiting_for_driver_unlock") end
                if SC.Actor and SC.Actor.stop then SC.Actor.stop(actor) end
                if SC.ActionSupervisor and SC.ActionSupervisor.transition then
                    SC.ActionSupervisor.transition(began.supervisorToken, "waiting")
                end
                return boardingResult(actor, order, true, "waiting_for_driver_unlock")
            end
        end
        local options = { driverSeat = seat == 0,
            playerCommand = order.hotwire == true or order.fieldWork == true,
            allowVirtualSeat = false, preflight = prepared }
        local boarded, boardReason
        if seat == 0 then boarded, boardReason = SC.Vehicle.boardDriver(actor, car, options)
        else boarded, boardReason = SC.Vehicle.board(actor, car, seat, options) end
        return boardingResult(actor, order, boarded, boardReason)
    end
    if reason ~= "companion is not at the passenger door" then
        SC.Vehicle.failTransaction(actor, "expedition_board_preflight_failed",
            { reason = reason })
        return boardingResult(actor, order, false, reason)
    end
    local squares, _, squareReason = SC.Vehicle.boardingSquares(
        actor, car, seat, seat == 0)
    if not squares then
        SC.Vehicle.failTransaction(actor, "expedition_door_unavailable",
            { reason = squareReason })
        return boardingResult(actor, order, false, squareReason)
    end
    if not SC.Navigation or not SC.Navigation.requestAny then
        return boardingResult(actor, order, false, "navigation_unavailable")
    end
    local x, y = SC.GameplayUtil.position(actor)
    local sx, sy = SC.GameplayUtil.position(squares[1])
    local gap = x and sx and math.sqrt((x - sx)^2 + (y - sy)^2) or 0
    local accepted, moveReason = SC.Navigation.requestAny(actor, squares,
        gap > 8 and "run" or "walk", {
            action = "approach_vehicle", vehicle = car, object = car, seat = seat,
            snapshot = snapshot, desiredDistance = 0,
            arrivalDistance = 0.15, continuousApproach = true,
            movementPriority = 30,
            -- A shop's locked doorway can be between the returning driver and
            -- the car. Keep the shared portal-aware search instead of sending
            -- an opaque nearest-target route through that same blocked edge.
            preferVerifiedPath = true,
            -- Door candidates belong to one fixed assigned seat. Verify the
            -- selected contact route immediately, including its house exit;
            -- the generic multi-goal fallback otherwise skips this proof.
            verifiedSelectedGoal = true,
            supervisorToken = began.supervisorToken,
        })
    if not accepted then
        SC.Vehicle.failTransaction(actor, "expedition_door_approach_failed",
            { reason = moveReason })
    end
    return boardingResult(actor, order, accepted, moveReason, moveReason)
end

local function sameParkingArea(zone, saved)
    return zone and saved and zone.z == saved.z
        and zone.x1 == saved.x1 and zone.y1 == saved.y1
        and zone.x2 == saved.x2 and zone.y2 == saved.y2
end

local function homeParkingMatches(trip)
    if trip.field then return Car.fieldParkingCurrent and Car.fieldParkingCurrent(trip)==true end
    return sameParkingArea(Car.areaById(trip.parkingZoneId),trip.parking)
end

local function travelMember(mission, member)
    if mission.survivors ~= nil then
        return mission.survivors[member.id] == true
    end
    local actor = member.actor
    if actor then
        local ok, dead = call(actor, "isDead")
        if ok and dead then return false end
    end
    return true
end

local function teamSeated(mission, trip, car)
    for _, member in ipairs(mission.roster) do
        if travelMember(mission, member) then
            if not member.actor or not mission.members[member.actor] then
                return false
            end
            local seated, current, seat = SC.Vehicle.isNativeSeated(member.actor)
            if not seated or current ~= car or seat ~= trip.seats[member.id] then
                return false
            end
        end
    end
    return true
end

local function unlockSquadDoors(mission, trip, car)
    local leader = mission.leader and mission.leader.actor
    if not leader then return false, "driver_unavailable" end
    local seated, vehicle, seat = SC.Vehicle.isNativeSeated(leader)
    if not SC.Driving.hasKey(leader, car)
        and not (seated and vehicle == car and seat == 0) then
        -- With no key, let the driver enter first. Someone inside the car
        -- can then unlock the other doors without giving away the key.
        return true
    end
    for _, member in ipairs(mission.roster) do
        local assigned = trip.seats[member.id]
        if assigned ~= nil and assigned > 0 and travelMember(mission, member) then
            local partOk, part = call(car, "getPassengerDoor", assigned)
            local doorOk, door = call(part, "getDoor")
            if partOk and part and doorOk and door then
                local lockedOk, locked = call(door, "isLocked")
                if not lockedOk then return false, "passenger_door_unreadable" end
                if locked then
                    call(car, "toggleLockedDoor", part, leader, false)
                    lockedOk, locked = call(door, "isLocked")
                    if lockedOk and locked then
                        local changed = call(door, "setLocked", false)
                        if changed then call(car, "transmitPartDoor", part) end
                        lockedOk, locked = call(door, "isLocked")
                    end
                    if not lockedOk or locked then
                        return false, "passenger_door_locked"
                    end
                end
            end
        end
    end
    return true
end

local function departReady(mission, trip, car)
    if not teamSeated(mission, trip, car) then return false, "team_not_seated" end
    local scriptOk, script = call(car, "getScriptName")
    if not scriptOk or script ~= trip.script then
        return false, "car_identity_changed"
    end
    if SC.Vehicle.hasPlayerAboard and SC.Vehicle.hasPlayerAboard(car) then
        return false, "player_aboard"
    end
    local countOk, count = call(car, "getMaxPassengers")
    count = countOk and finite(count) or nil
    if not count or count < #mission.roster or count > 32 then
        return false, "too_few_seats"
    end
    local assigned = {}
    for _, member in ipairs(mission.roster) do
        local seat = trip.seats[member.id]
        local installedOk, installed = call(car, "isSeatInstalled", seat)
        if not installedOk or installed ~= true then
            return false, "seat_unavailable"
        end
        if travelMember(mission, member) then assigned[seat] = member.actor end
    end
    for seat = 0, count - 1 do
        local occupantOk, occupant = call(car, "getCharacter", seat)
        if not occupantOk or occupant ~= assigned[seat] then
            return false, "car_has_other_occupants"
        end
    end
    if not componentReady(car, "Engine") then
        return false, "engine_unusable"
    end
    for _, part in ipairs({ "TireFrontLeft", "TireFrontRight",
        "TireRearLeft", "TireRearRight" }) do
        if not componentReady(car, part, true) then
            return false, "wheel_unusable"
        end
    end
    if not equippedOrHeldKey(mission.leader.actor, car) then
        return false, "driver_needs_key"
    end
    if trip.leg == "home" and not homeParkingMatches(trip) then
        return false, "home_parking_changed"
    end
    local goal = trip.leg == "home"
        and (trip.homeRoadEntry or trip.departure) or trip.siteStop
    local at = point(car)
    if not at then return false, "car_position_unavailable" end
    local route, routeReason, native = Car.planRoadAccess(car, at, goal, true)
    if not route then return false, routeReason or "no_route" end
    local entry = native and { x = finite(native.entryX),
        y = finite(native.entryY), z = 0 }
    if not entry or not entry.x or not entry.y then
        return false, "road_access_unavailable"
    end
    local tankOk, tank = call(car, "getPartById", "GasTank")
    local fuelOk, fuel = false, nil
    if tankOk and tank then fuelOk, fuel = call(tank,
        "getContainerContentAmount") end
    fuel = fuelOk and finite(fuel) or nil
    if fuel == nil then return false, "fuel_unreadable" end
    local rate = fuelRate(trip.script)
    local accessLength = math.sqrt((at.x - entry.x)^2
        + (at.y - entry.y)^2)
    local roadLength = finite(route.roadLength) or 0
    local requiredTiles
    if trip.leg == "outbound" then
        requiredTiles = roadLength * 2 + accessLength * 2 + 30
    else
        local exitX = native and finite(native.exitX)
        local exitY = native and finite(native.exitY)
        if not exitX or not exitY then return false, "road_access_unavailable" end
        local homeAccess = math.sqrt((goal.x - exitX)^2
            + (goal.y - exitY)^2)
        requiredTiles = roadLength + accessLength + homeAccess + 30
    end
    local required = requiredTiles * rate * 1.5
    if fuel < required then return false, "fuel_insufficient" end
    return true, nil, entry
end

local function teamOnFoot(mission)
    for _, member in ipairs(mission.roster) do
        if travelMember(mission, member) and member.actor
            and mission.members[member.actor] then
            local seated, vehicle = SC.Vehicle.isNativeSeated(member.actor)
            if seated or vehicle ~= nil then return false end
        end
    end
    return true
end

local function wholeTeamOnFoot(mission)
    for _, member in ipairs(mission.roster or {}) do
        if travelMember(mission, member)
            and (not member.actor or not mission.members[member.actor]) then
            return false
        end
    end
    return teamOnFoot(mission)
end

local function fieldStopBarrier(mission,trip,car)
    if not trip.field then return true end
    if not SC.HomeTrip or type(SC.HomeTrip.carStopReady)~="function" then return false,"home_car_save_unavailable" end
    local called,ready,reason=pcall(SC.HomeTrip.carStopReady,mission,car)
    if not called or ready~=true then return false,reason or ready or "home_car_save_pending" end
    return true
end

local function abandonToWalking(mission, trip, car)
    local saved,saveReason=fieldStopBarrier(mission,trip,car)
    if not saved then return false,saveReason end
    local scout = mission.scout
    local leader = mission.leader and mission.leader.actor
    local x, y, z
    if leader then x, y, z = SC.GameplayUtil.position(leader) end
    if not x or not y or not z then return false, "leader_position_unavailable" end
    local parkedReturn = trip.state == "returning_to_car"
        or trip.resumeState == "returning_to_car"
        or trip.recovery and trip.recovery.kind == "stream"
    local abandonedAt = car and point(car)
        or parkedReturn and trip.sitePoint or trip.position or trip.sitePoint
    trip.state = "abandoned"
    trip.radioResumeState, trip.radioHoldCar = nil, nil
    if trip.field and (trip.blocker == "home_car_save_pending"
        or trip.blocker == "home_car_save_failed"
        or trip.blocker == "home_car_save_unavailable") then trip.blocker = nil end
    trip.abandonedAt = abandonedAt
    trip.recovery = nil
    scout.phase = (scout.returnRequested or trip.returnRequested
        or trip.leg == "home") and "inbound" or "outbound"
    scout.travelMode = "straight"
    scout.roadRoute, scout.road = nil, nil
    scout.trail = { { x = math.floor(x), y = math.floor(y),
        z = math.floor(z) } }
    scout.lastStalledTarget = nil
    scout.replans, scout.returnIndex = 0, nil
    return true
end

local function unloadOwnership(mission, trip, car)
    local identityOk, sqlId = call(car, "getSqlId")
    if not identityOk or tonumber(sqlId) ~= trip.sqlId then
        return false, "car_identity_changed"
    end
    if SC.Vehicle.hasPlayerAboard and SC.Vehicle.hasPlayerAboard(car) then
        return false, "player_aboard"
    end
    local countOk, count = call(car, "getMaxPassengers")
    count = countOk and finite(count) or nil
    if not count or count < 1 or count > 32 then return false, "seats_unreadable" end
    for seat = 0, count - 1 do
        local occupiedOk, occupant = call(car, "getCharacter", seat)
        if not occupiedOk then return false, "seat_unreadable" end
        if occupant ~= nil then
            local owned = false
            for _, member in ipairs(mission.roster or {}) do
                if member.actor == occupant and mission.members[occupant]
                    and trip.seats[member.id] == seat then owned = true break end
            end
            if not owned then return false, "car_has_other_occupants" end
        end
    end
    return true
end

local function stopOwnedEngine(mission, trip, car, now)
    local owned, ownershipReason = unloadOwnership(mission, trip, car)
    if not owned then return false, ownershipReason end
    local runningOk, running = call(car, "isEngineRunning")
    local startedOk, started = call(car, "isEngineStarted")
    if not runningOk or type(running) ~= "boolean" or not startedOk
        or type(started) ~= "boolean" then return false, "engine_state_unreadable" end
    if not running and not started then
        if trip.engineStopAttempts then traceTrip(trip, "engine_stopped") end
        trip.engineStopAttempts, trip.engineStopAt = nil, nil
        return true
    end
    now = now or (SC.GameplayUtil.nowMs and SC.GameplayUtil.nowMs()) or 0
    if (trip.engineStopAttempts or 0) >= 3 then return false, "engine_shutdown_failed" end
    if trip.engineStopAt and now - trip.engineStopAt < 2000 then
        return false, "engine_shutdown_pending"
    end
    trip.engineStopAttempts, trip.engineStopAt = (trip.engineStopAttempts or 0) + 1, now
    -- Vanilla's engine-off action has zero duration and calls this same API.
    -- Releasing the wheel only parks the controller; exiting leaves it running.
    local stopped, accepted = call(car, "shutOff")
    if not stopped or accepted == false then return false, "engine_shutdown_failed" end
    runningOk, running = call(car, "isEngineRunning")
    startedOk, started = call(car, "isEngineStarted")
    if runningOk and startedOk and running == false and started == false then
        traceTrip(trip, "engine_stopped")
        trip.engineStopAttempts, trip.engineStopAt = nil, nil
        return true
    end
    return false, "engine_shutdown_pending"
end

local function stopAndUnload(mission, trip, car, now)
    local owned, ownershipReason = unloadOwnership(mission, trip, car)
    if not owned then return false, ownershipReason end
    local leader = mission.leader and mission.leader.actor
    if leader and SC.Driving.isDriving(leader) then
        local stopped, why = SC.Driving.release(leader, "expedition_unload")
        if not stopped then return false, why or "drive_stop_pending" end
    end
    local stationary, why = SC.Vehicle.isStationary(car)
    if not stationary then return false, why or "car_not_stopped" end
    local engineStopped, engineReason = stopOwnedEngine(mission, trip, car, now)
    if not engineStopped then return false, engineReason end
    for _, member in ipairs(mission.roster) do
        if member.actor and mission.members[member.actor] then
            local seated, current, seat = SC.Vehicle.isNativeSeated(member.actor)
            if seated then
                if current ~= car or seat ~= trip.seats[member.id] then
                    return false, "wrong_vehicle_or_seat"
                end
                local exited, exitReason = SC.Vehicle.exit(member.actor, car,
                    seat, { expedition = true })
                if not exited then return false, exitReason end
            end
        end
    end
    if not teamOnFoot(mission) then return false, "unload_unverified" end
    -- Step 1's exact-item recovery checks the existing ignition key and
    -- returns it only to the original driver after the native exit commits.
    if leader and trip.seats[mission.leader.id] == 0
        and SC.Vehicle.recoverDriverKeyAfterExit then
        local recovered, recoveryReason = SC.Vehicle.recoverDriverKeyAfterExit(
            leader, trip.sqlId)
        if not recovered then return false, recoveryReason end
    end
    if trip.field then trip.engineStopped=true end
    return true
end

local function hold(trip, reason)
    trip.blocker = reason or "car_recovery_required"
    trip.resumeState = trip.state
    trip.state = "held"
end

local function carLoaded(trip)
    return SC.Vehicle and SC.Vehicle.loadedBySqlId
        and SC.Vehicle.loadedBySqlId(trip.sqlId) or nil
end

-- A failed local manoeuvre is not proof the car must be left behind. Retain
-- the existing roster/seats while the ordinary checked driving entry retries.
-- Only remaining time is persisted; native routes and timers are reconstructed.
do
    local Recovery = {}
    Car.Recovery = Recovery
    Recovery.limitMs = 300000
    function Recovery.advance(trip, now)
        local recovery = trip.recovery
        if not recovery then return nil end
        if recovery.lastAt then
            recovery.remainingMs = math.max(0, recovery.remainingMs
                - math.max(0, now - recovery.lastAt))
        end
        recovery.lastAt = now
        return recovery
    end
    function Recovery.begin(trip, now, kind, reason, car)
        local recovery = trip.recovery
        if not recovery or recovery.kind ~= kind then
            recovery = { kind = kind, remainingMs = Recovery.limitMs,
                attempts = 0, origin = car and point(car) or nil }
            trip.recovery = recovery
        end
        recovery.lastAt = now
        recovery.reason = type(reason) == "string" and reason:sub(1,128)
            or "car_recovery_required"
        recovery.nextAttemptAt = now + 10000
        return recovery
    end
    function Recovery.roadReason(reason)
        return reason == "no_route" or reason == "route_blocked"
            -- Three failed native cranks do not prove a usable engine cannot
            -- restart. The existing cooldown/budget rechecks the car first.
            or reason == "engine_failed"
            or reason == "turn_failed" or reason == "goal_not_reached"
            or reason == "streaming_stalled" or reason == "drive_status_unavailable"
            or reason == "car_not_loaded" or reason == "road_access_blocked"
            or reason == "road_access_vehicle_blocked" or reason == "road_access_not_loaded"
            or reason == "NO_ROUTE" or reason == "NO_SAFE_ROAD_DETOUR"
            or reason == "road_bridge_failed" or reason == "DATA_NOT_READY"
    end
    function Recovery.holdRoad(mission, trip, car, now, reason)
        if not Recovery.roadReason(reason) then return false end
        Recovery.begin(trip, now, "road", reason, car)
        hold(trip, reason)
        traceTrip(trip, "car_recovery_wait", "reason=" .. tostring(reason)
            .. " remainingMs=" .. tostring(trip.recovery.remainingMs))
        return true
    end
    function Recovery.roadPulse(mission, trip, car, now)
        local recovery = trip.recovery
        if not recovery or recovery.kind ~= "road" then return false end
        if car and SC.Vehicle.hasPlayerAboard and SC.Vehicle.hasPlayerAboard(car) then
            trip.blocker = "player_aboard"
            recovery.lastAt = now
            return true
        end
        local driver = mission.leader and mission.leader.actor
        local drive = driver and SC.Driving.jobStatus(driver)
        if car and drive and drive.managed == true and drive.phase ~= "released" then
            local stopped, why = SC.Driving._stopOwnedVehicle(driver, car,
                "expedition_car_recovery")
            if not stopped then trip.blocker = why or "drive_stop_pending" return true end
        end
        if recovery.remainingMs <= 0 then
            if not car and not wholeTeamOnFoot(mission) then return true end
            trip.blocker = "car_recovery_timeout"
            if not car then
                local abandoned, why = abandonToWalking(mission, trip)
                if not abandoned then trip.blocker = why end
            else
                trip.recovery = nil
                trip.state, mission.scout.phase = "fallback_unloading", "fallback_unloading"
            end
            return true
        end
        if not car then
            if wholeTeamOnFoot(mission) and trip.position and SC.ExpeditionPrototype
                and type(SC.ExpeditionPrototype.approachReturnCar) == "function" then
                local stream = returnStreams[trip]
                if not stream then stream = {} returnStreams[trip] = stream end
                local p = trip.position
                local _, why = SC.ExpeditionPrototype.approachReturnCar(mission.leader.actor,
                    {x=math.floor(p.x),y=math.floor(p.y),z=0},stream)
                trip.blocker = why or "car_not_loaded"
            end
            return true
        end
        if now < (recovery.nextAttemptAt or now) then return true end
        recovery.origin = recovery.origin or point(car)
        recovery.attempts = recovery.attempts + 1
        recovery.nextAttemptAt = now + 10000
        -- Boarding revalidates occupants, key, engine, wheels, fuel and route.
        -- Correct road geometry lets the native follower perform its checked turn.
        trip.state = trip.leg == "home" and "boarding_home" or "boarding_out"
        mission.scout.phase = trip.state
        trip.blocker, trip.recoveryAt = nil, nil
        trip.boardStartedAt = now
        traceTrip(trip, "car_recovery_retry", "attempt=" .. recovery.attempts
            .. " remainingMs=" .. recovery.remainingMs)
        return true
    end
    function Recovery.progress(trip, car, status)
        local recovery = trip.recovery
        if not recovery or recovery.kind ~= "road" or not car then return end
        local at = point(car)
        if status and status.result == "arrived" or at and recovery.origin
            and status and status.phase == "following"
            and (at.x-recovery.origin.x)^2+(at.y-recovery.origin.y)^2 >= 144 then
            trip.recovery = nil
            traceTrip(trip, "car_recovery_resumed")
        end
    end
end

-- A dead driver cannot run the normal car pulse. Finish the physical stop and
-- evacuate living passengers before the expedition hands its view to a new
-- leader (or tears the view down when everybody has died). Each step is
-- retryable: a blocked exit or a delayed native stop leaves the trip active.
function Car.recoverDeadDriver(mission)
    local scout = mission and mission.scout
    local trip = scout and scout.vehicle
    if not trip or trip.state == "abandoned" then return true end
    local alreadyWalking = trip.state == "parked_at_site"
        or trip.state == "home_wait"
    local driver = mission.leader and mission.leader.actor
    if driver then
        local stopped, why = SC.Driving.release(driver,
            "expedition_driver_dead")
        if stopped ~= true then return false, why or "drive_stop_pending" end
    end
    local car = carLoaded(trip)
    local seated = {}
    for _, member in ipairs(mission.roster or {}) do
        local actor = member.actor
        local deadOk, dead = false, nil
        if actor then deadOk, dead = call(actor, "isDead") end
        if actor and mission.members[actor] and deadOk and dead == false then
            local inside, current, seat = SC.Vehicle.isNativeSeated(actor)
            if inside or current ~= nil then
                if not car then return false, "car_not_loaded" end
                if not inside or current ~= car
                    or seat ~= trip.seats[member.id] then
                    return false, "wrong_vehicle_or_seat"
                end
                seated[#seated + 1] = { actor = actor, seat = seat }
            end
        end
    end
    if car and (#seated > 0 or not alreadyWalking) then
        local owned, ownershipReason = unloadOwnership(mission, trip, car)
        if not owned and #seated > 0 then return false, ownershipReason end
        -- With no living crew aboard, a player takeover ends our authority;
        -- otherwise even an all-dead trip leaves its own car switched off.
        if owned then
            local stationary, why = SC.Vehicle.isStationary(car)
            if not stationary then return false, why or "car_not_stopped" end
            local engineStopped, engineReason = stopOwnedEngine(mission, trip, car)
            if not engineStopped then return false, engineReason end
        end
    end
    if #seated > 0 then
        for _, passenger in ipairs(seated) do
            local exited, reason = SC.Vehicle.exit(passenger.actor, car,
                passenger.seat, { expedition = true })
            if not exited then return false, reason or "exit_blocked" end
        end
        for _, passenger in ipairs(seated) do
            local inside, current = SC.Vehicle.isNativeSeated(passenger.actor)
            if inside or current ~= nil then return false, "unload_unverified" end
        end
    end
    if trip.field then
        if not car then return false,"car_not_loaded" end
        local owned,why=unloadOwnership(mission,trip,car)
        if not owned then return false,why end
        local stopped=SC.Vehicle.isStationary(car)
        local runningOkay,running=call(car,"isEngineRunning")
        local startingOkay,starting=call(car,"isEngineStarted")
        if not stopped or not runningOkay or not startingOkay or running~=false or starting~=false then return false,"engine_shutdown_pending" end
        trip.engineStopped=true
        local saved,saveReason=fieldStopBarrier(mission,trip,car)
        if not saved then return false,saveReason end
    end
    trip.abandonedAt = car and point(car) or trip.position
    trip.state = "abandoned"
    trip.blocker, trip.resumeState = nil, nil
    if not alreadyWalking and scout.phase ~= "awaiting_player" then
        scout.phase = (scout.returnRequested or trip.returnRequested
            or trip.leg == "home") and "inbound" or "outbound"
    end
    scout.travelMode = "straight"
    if not alreadyWalking then
        scout.roadRoute, scout.road = nil, nil
        scout.lastStalledTarget = nil
        scout.replans, scout.returnIndex = 0, nil
        for _, member in ipairs(mission.roster or {}) do
            local actor = member.actor
            local deadOk, dead = false, nil
            if actor then deadOk, dead = call(actor, "isDead") end
            if actor and mission.members[actor] and deadOk and dead == false then
                local x, y, z = SC.GameplayUtil.position(actor)
                if x and y and z then
                    scout.trail = { { x = math.floor(x), y = math.floor(y),
                        z = math.floor(z) } }
                end
                break
            end
        end
    end
    return true
end

local function recordReturnIntent(scout, reason)
    reason = reason or "radio_return"
    scout.returnRequested = true
    if scout.wood then
        scout.wood.endReason = reason
        scout.wood.pendingCarReturnReason = nil
        scout.wood.pendingReturnReason = nil
    elseif scout.search then
        scout.search.endReason = reason
    else
        scout.endReason = reason
    end
end

function Car.requestReturn(mission, now, reason)
    local scout = mission and mission.scout
    local trip = scout and scout.vehicle
    if not trip or trip.state == "abandoned" then return false, "no_car_trip" end
    if trip.leg == "home" or trip.state == "home_wait" then
        return false, "expedition_already_returning"
    end
    if scout.departurePreparation and SC.ExpeditionPrototype
        and SC.ExpeditionPrototype._cancelDeparturePreparation then
        local stopped, why = SC.ExpeditionPrototype._cancelDeparturePreparation(mission, "expedition_return")
        if stopped ~= true then
            scout.departurePreparation.returnReason = reason or "radio_return"
            return false, why or "departure_preparation_settling"
        end
    end
    if scout.wood then
        if not SC.ExpeditionWood or type(SC.ExpeditionWood.stop) ~= "function" then
            return false, "wood_work_unavailable"
        end
        local wood = scout.wood
        wood.complete, wood.doneReason = true, wood.doneReason or reason or "radio_return"
        wood.pendingCarReturnReason = reason or "radio_return"
        local stopped, why = SC.ExpeditionWood.stop(wood, reason or "radio_return")
        if not stopped then
            return false, why or "wood_work_settling"
        end
        wood.preparation, wood.preparationReason = nil, nil
    end
    if trip.state == "held" or trip.state == "interrupted_by_load" then
        if trip.state == "held" and trip.recovery and trip.recovery.kind == "road" then
            recordReturnIntent(scout, reason)
            trip.leg = "home"
            trip.resumeState = "driving_home"
            return true, "returning_by_car"
        end
        return false, trip.blocker or "car_recovery_required"
    end
    if trip.state == "driving_out" then
        local driver = mission.leader and mission.leader.actor
        if not driver then return false, "driver_unavailable" end
        local stopped, why = SC.Driving.release(driver,
            "expedition_return_requested")
        if not stopped then return false, why or "drive_stop_pending" end
        recordReturnIntent(scout, reason)
        trip.leg, trip.state = "home", "boarding_home"
        scout.phase = "boarding_home"
        trip.boardStartedAt = now
        return true, "returning_by_car"
    end
    if trip.state == "walking_to_car" or trip.state == "boarding_out" then
        recordReturnIntent(scout, reason)
        trip.leg = "home"
        trip.state, scout.phase = "boarding_rollback", "boarding_rollback"
        trip.blocker = "return_requested_before_departure"
        return true, "returning_from_parking"
    end
    if trip.state == "unloading_site" then
        recordReturnIntent(scout, reason)
        trip.returnRequested = true
        return true, "return_after_unloading"
    end
    if trip.state == "parked_at_site" then
        recordReturnIntent(scout, reason)
        trip.leg, trip.state = "home", "returning_to_car"
        scout.phase = "returning_to_car"
        trip.boardStartedAt = now
        return true, "returning_to_car"
    end
    return false, "car_return_state_unavailable"
end

function Car.fitsParking(car, zone, seats)
    local stopped = SC.Vehicle.isStationary(car)
    if not stopped or type(zone) ~= "table" then
        return false, "parking_not_stationary"
    end
    local poly = Car.footprint(car)
    if poly == nil then return false, "parking_footprint_unreadable" end
    for index = 1, 4 do
        local x, y = finite(poly["x" .. index]), finite(poly["y" .. index])
        if not x or not y or x < zone.x1 or x >= zone.x2 + 1
            or y < zone.y1 or y >= zone.y2 + 1 then
            return false, "parking_footprint_outside_area"
        end
    end
    for _, seat in pairs(seats or {}) do
        local squares = SC.Vehicle.safeExitSquares
            and SC.Vehicle.safeExitSquares(car, seat) or nil
        if not squares or #squares < 1 then
            return false, "parking_exit_blocked"
        end
    end
    return true
end

function Car.footprint(car)
    if car == nil then return nil end
    local ok, poly = call(car, "getPoly")
    if ok and type(poly) == "table" then return poly end
    local api = type(_G) == "table" and rawget(_G, "SCBridge") or nil
    if api == nil or not SC.Call or not SC.Call.static then return nil end
    local result = {}
    local called, accepted = SC.Call.static(api, "vehicleFootprint", car, result)
    if called and accepted == true then return result end
    return nil
end

-- Predict the translated vehicle footprint without moving it. Refuse an
-- occupied, unloaded or obstructed bay before granting native throttle.
local function targetBayClear(car, zone, target)
    local at = point(car)
    local poly = Car.footprint(car)
    if not at or not poly then
        return false, "parking_footprint_unreadable"
    end
    local dx, dy = target.x - at.x, target.y - at.y
    local minX, minY, maxX, maxY = 30000, 30000, 0, 0
    for index = 1, 4 do
        local x, y = finite(poly["x" .. index]), finite(poly["y" .. index])
        if not x or not y then return false, "parking_footprint_unreadable" end
        x, y = x + dx, y + dy
        if x < zone.x1 or x >= zone.x2 + 1 or y < zone.y1
            or y >= zone.y2 + 1 then
            return false, "parking_footprint_outside_area"
        end
        minX, minY = math.min(minX, x), math.min(minY, y)
        maxX, maxY = math.max(maxX, x), math.max(maxY, y)
    end
    if type(getCell) ~= "function" then return false, "parking_not_loaded" end
    local cellOk, cell = pcall(getCell)
    if not cellOk or not cell then return false, "parking_not_loaded" end
    for x = math.floor(minX), math.floor(maxX) do
        for y = math.floor(minY), math.floor(maxY) do
            local found, square = call(cell, "getGridSquare", x, y, 0)
            if not found or not square then return false, "parking_not_loaded" end
            local solidOk, solid = call(square, "isSolid")
            local transOk, trans = call(square, "isSolidTrans")
            local vehicleOk, other = call(square, "getVehicleContainer")
            if not solidOk or not transOk or not vehicleOk or solid or trans
                or other ~= nil and other ~= car then
                return false, "parking_bay_blocked"
            end
        end
    end
    for _, other in ipairs(SC.Vehicle.loadedVehicles()) do
        if other ~= car then
            local footprint = Car.footprint(other)
            if not footprint then
                return false, "parking_vehicle_unreadable"
            end
            local otherMinX, otherMinY = 30000, 30000
            local otherMaxX, otherMaxY = 0, 0
            for index = 1, 4 do
                local ox = finite(footprint["x" .. index])
                local oy = finite(footprint["y" .. index])
                if not ox or not oy then return false, "parking_vehicle_unreadable" end
                otherMinX, otherMinY = math.min(otherMinX, ox), math.min(otherMinY, oy)
                otherMaxX, otherMaxY = math.max(otherMaxX, ox), math.max(otherMaxY, oy)
            end
            if minX < otherMaxX and maxX > otherMinX
                and minY < otherMaxY and maxY > otherMinY then
                return false, "parking_bay_occupied"
            end
        end
    end
    return true
end

local function resumeReady(mission, trip, car)
    local at = point(car)
    if not at then return false, "car_position_unavailable" end
    if trip.position and math.sqrt((at.x - trip.position.x)^2
        + (at.y - trip.position.y)^2) > 12 then
        return false, "saved_car_moved"
    end
    local scriptOk, script = call(car, "getScriptName")
    if not scriptOk or script ~= trip.script then
        return false, "saved_car_identity_changed"
    end
    if not teamOnFoot(mission) then return false, "restart_team_not_on_foot" end
    local stationary, why = SC.Vehicle.isStationary(car)
    if not stationary then return false, why or "car_moving" end
    local countOk, count = call(car, "getMaxPassengers")
    count = countOk and finite(count) or nil
    if not count or count < #mission.roster or count > 32 then
        return false, "too_few_seats"
    end
    for _, member in ipairs(mission.roster) do
        if travelMember(mission, member) then
            if not member.actor or not SC.Actor.isCompanion(member.actor)
                or not mission.members[member.actor] then
                return false, "restart_team_unavailable"
            end
            local deadOk, dead = call(member.actor, "isDead")
            if not deadOk or dead then return false, "restart_team_unfit" end
            local health = SC.GameplayUtil.nativeHealth
                and finite(SC.GameplayUtil.nativeHealth(member.actor))
            if health and health <= 30 then return false, "restart_team_unfit" end
            local seat = trip.seats[member.id]
            if seat == nil or seat >= count then return false, "seat_unavailable" end
            local installedOk, installed = call(car, "isSeatInstalled", seat)
            local occupiedOk, occupant = call(car, "getCharacter", seat)
            local doors, _, doorReason = SC.Vehicle.boardingSquares(member.actor, car,
                seat, seat == 0)
            if doorReason == "no safe loaded passenger-door square" then
                return false, "restart_door_not_loaded"
            end
            if not installedOk or installed ~= true or not occupiedOk
                or occupant ~= nil or not doors or #doors < 1 then
                return false, "seat_or_door_unavailable"
            end
        end
    end
    for seat = 0, count - 1 do
        local occupantOk, occupant = call(car, "getCharacter", seat)
        if not occupantOk or occupant ~= nil then
            return false, "car_has_other_occupants"
        end
    end
    -- The historical seat map is retained, but only a surviving original
    -- driver can resume steering. Otherwise evacuate the living squad on foot.
    if not mission.leader or trip.seats[mission.leader.id] ~= 0 then
        return false, "restart_driver_casualty"
    end
    if not componentReady(car, "Engine") then
        return false, "engine_unusable"
    end
    for _, part in ipairs({ "TireFrontLeft", "TireFrontRight",
        "TireRearLeft", "TireRearRight" }) do
        if not componentReady(car, part, true) then
            return false, "wheel_unusable"
        end
    end
    if not equippedOrHeldKey(mission.leader.actor, car)
        and not findSquadKey(mission.roster, car) then
        return false, "driver_needs_key"
    end
    local zone = Car.areaById(trip.parkingZoneId)
    if trip.leg == "home" and not homeParkingMatches(trip) then
        return false, "home_parking_changed"
    end
    local goal = trip.leg == "home"
        and (trip.homeRoadEntry or trip.departure) or trip.siteStop
    local route, routeReason, native = Car.planRoadAccess(car, at, goal, true)
    if not route then return false, routeReason end
    local entryX = native and finite(native.entryX)
    local entryY = native and finite(native.entryY)
    if not entryX or not entryY then
        return false, "road_access_unavailable"
    end
    local tankOk, tank = call(car, "getPartById", "GasTank")
    local fuelOk, fuel = false, nil
    if tankOk and tank then fuelOk, fuel = call(tank, "getContainerContentAmount") end
    fuel = fuelOk and finite(fuel) or nil
    if fuel == nil then return false, "fuel_unreadable" end
    local rate = fuelRate(trip.script)
    local accessLength = math.sqrt((at.x - entryX)^2
        + (at.y - entryY)^2)
    local roadLength = finite(route.roadLength) or 0
    local distance
    if trip.leg == "outbound" then
        distance = roadLength * 2 + accessLength * 2
    else
        local exitX = native and finite(native.exitX)
        local exitY = native and finite(native.exitY)
        if not exitX or not exitY then return false, "road_access_unavailable" end
        distance = roadLength + accessLength
            + math.sqrt((goal.x - exitX)^2 + (goal.y - exitY)^2)
    end
    if fuel < (distance + 30) * rate * 1.5 then
        return false, "fuel_insufficient"
    end
    return true
end

local restartWaitReason = {
    car_not_loaded = true,
    restart_team_unavailable = true,
    car_position_unavailable = true,
    road_access_not_loaded = true,
    restart_door_not_loaded = true,
    parking_not_loaded = true,
}

local restartWalkingReason = {
    restart_driver_casualty = true,
    saved_car_moved = true,
    saved_car_identity_changed = true,
    too_few_seats = true,
    seat_or_door_unavailable = true,
    car_has_other_occupants = true,
    engine_unusable = true,
    wheel_unusable = true,
    fuel_unreadable = true,
    fuel_insufficient = true,
    driver_needs_key = true,
}

local parkingRetryReason = {
    road_access_blocked = true,
    road_access_not_loaded = true,
    road_access_vehicle_blocked = true,
    parking_bay_blocked = true,
    parking_bay_occupied = true,
    parking_not_loaded = true,
    parking_exit_blocked = true,
}

function Car.parkingFailed(mission, trip, car, reason, status)
    trip.parkingRefusal = trip.parkingRefusal
        or tostring(status and status.firstParkingRefusal or reason or "parking_approach_failed"):sub(1, 128)
    trip.lastFailure = trip.lastFailure or { reason = trip.parkingRefusal, at = point(car) }
    trip.approachStartedAt, trip.parkingAligning = nil, nil
    if trip.field then
        trip.blocker = reason or "parking_approach_failed"
        trip.state, mission.scout.phase = "fallback_unloading", "fallback_unloading"
    else hold(trip, reason or "parking_approach_failed") end
    if trip.parkingRefusalReason ~= reason then
        trip.parkingRefusalReason = reason
        traceTrip(trip, "parking_refused", "reason=" .. tostring(reason), status)
    end
end

function Car.pulse(mission, now, worldHour)
    local scout = mission and mission.scout
    local trip = scout and scout.vehicle
    if not trip or trip.state == "abandoned" then return false end
    -- A radio hold owns the existing car and seats until an explicit resume
    -- or recall. Generic held recovery must not abandon it after a timer.
    if trip.radioResumeState or preparingSupplies(scout) then
        if trip.recovery then trip.recovery.lastAt = now end
        return true
    end
    Car.Recovery.advance(trip, now)
    if trip.state == "parked_at_site" then
        if scout.phase ~= "inbound" then return false end
        trip.state, trip.leg = "returning_to_car", "home"
        scout.phase = "returning_to_car"
        trip.boardStartedAt = now
        return true
    end
    if trip.state == "held" then
        if Car.Recovery.roadPulse(mission, trip, carLoaded(trip), now) then return true end
        if trip.resumeState == "returning_to_car" and trip.blocker == "car_not_loaded" then
            trip.state, scout.phase = "returning_to_car", "returning_to_car"
            trip.resumeState, trip.recoveryAt = nil, nil
            return true
        end
        -- A field arrival cannot silently become a purported roadside stop
        -- after a full/blocked marked bay. Keep the physical car and roster
        -- held until loaded clearance can actually be rechecked.
        if trip.field and trip.resumeState=="parking_home" then
            local status = SC.Driving.jobStatus(mission.leader.actor)
            if status and (status.owned == false or status.phase == "released") then
                Car.parkingFailed(mission, trip, carLoaded(trip),
                    status.firstParkingRefusal or trip.parkingRefusal or status.reason or trip.blocker, status)
                return true
            end
            if now>=(trip.nextRecoveryCheckAt or 0) then
                trip.nextRecoveryCheckAt=now+2000
                trip.state,scout.phase="parking_home","parking_home"
            end
            return true
        end
        -- A chunk or roster actor can appear after the restore callback. A
        -- temporary wait resumes the saved leg once both are present. A car
        -- that never reloads can be left behind only after the entire roster
        -- is present and safely on foot.
        if trip.resumeState == "interrupted_by_load"
            and restartWaitReason[trip.blocker] then
            if now >= (trip.nextRestartCheckAt or 0) then
                trip.nextRestartCheckAt = now + 2000
                if carLoaded(trip) then
                    trip.state = "interrupted_by_load"
                    trip.blocker = nil
                    trip.missingSince = nil
                elseif trip.blocker == "car_not_loaded"
                    and wholeTeamOnFoot(mission) then
                    trip.recoveryAt = trip.recoveryAt or now + 60000
                    if now >= trip.recoveryAt then
                        local abandoned, why = abandonToWalking(mission, trip)
                        if not abandoned then trip.blocker = why end
                    end
                end
            end
            return true
        end
        -- A hold outside load restoration has no manual resume action. Give a
        -- transient obstruction time to clear, then stop and leave the car
        -- through the same verified exit path as a failed drive. If the car is
        -- gone, walk only after the entire roster is present and on foot.
        trip.recoveryAt = trip.recoveryAt or now + 15000
        local heldCar = carLoaded(trip)
        if heldCar and SC.Vehicle.hasPlayerAboard
            and SC.Vehicle.hasPlayerAboard(heldCar) then return true end
        if heldCar and trip.resumeState == "parking_home"
            and parkingRetryReason[trip.blocker]
            and now < trip.recoveryAt
            and now >= (trip.nextRecoveryCheckAt or 0) then
            trip.nextRecoveryCheckAt = now + 2000
            trip.state, scout.phase = "parking_home", "parking_home"
            trip.blocker = nil
            return true
        end
        if now < trip.recoveryAt then return true end
        if not heldCar then
            if not wholeTeamOnFoot(mission) then return true end
            local leader = mission.leader and mission.leader.actor
            if leader and SC.Driving.isDriving(leader) then
                local stopped, why = SC.Driving.release(leader,
                    "expedition_car_unloaded")
                if not stopped then trip.blocker = why return true end
            end
            local abandoned, why = abandonToWalking(mission, trip)
            if not abandoned then trip.blocker = why end
            return true
        end
        trip.state, scout.phase = "fallback_unloading", "fallback_unloading"
        return true
    end
    if trip.leg == "outbound" and worldHour
        and (scout.turnHomeAtHour and worldHour >= scout.turnHomeAtHour
            or scout.arriveByHour and worldHour >= scout.arriveByHour)
        and (trip.state == "walking_to_car"
            or trip.state == "boarding_out"
            or trip.state == "driving_out") then
        local returnReason = scout.turnHomeAtHour
            and worldHour >= scout.turnHomeAtHour
            and "return_time_reached" or "arrival_reserve_reached"
        local requested, why = Car.requestReturn(mission, now, returnReason)
        if not requested then trip.blocker = why end
        return true
    end
    local car = carLoaded(trip)
    if car == nil then
        if trip.state == "returning_to_car" then
            local recovery = trip.recovery
            if not recovery or recovery.kind ~= "stream" then
                recovery = Car.Recovery.begin(trip, now, "stream", "car_not_loaded")
            end
            local p = trip.sitePoint or trip.position
            local stream=returnStreams[trip]
            if not stream then stream={startedAt=now} returnStreams[trip]=stream end
            if recovery.remainingMs > 0 and p and SC.ExpeditionPrototype
                and type(SC.ExpeditionPrototype.approachReturnCar) == "function" then
                local moving,why=SC.ExpeditionPrototype.approachReturnCar(mission.leader.actor,
                    {x=math.floor(p.x),y=math.floor(p.y),z=0},stream)
                trip.blocker = why or "car_not_loaded"
                if moving then return true end
            end
            if recovery.remainingMs <= 0 then
                trip.blocker = "car_recovery_timeout"
                if wholeTeamOnFoot(mission) then
                    local abandoned, why = abandonToWalking(mission, trip)
                    if not abandoned then trip.blocker = why end
                end
            end
            return true
        end
        if trip.state ~= "interrupted_by_load" then
            Car.Recovery.holdRoad(mission, trip, nil, now, "car_not_loaded")
        else
            trip.missingSince = trip.missingSince or now
            if now - trip.missingSince > 30000 then hold(trip, "car_not_loaded") end
        end
        return true
    end
    returnStreams[trip]=nil
    if trip.state ~= "interrupted_by_load" then trip.position = point(car) or trip.position end
    if trip.recovery and trip.recovery.kind == "stream" then
        trip.recovery = nil
        trip.blocker = nil
        traceTrip(trip, "parked_car_reloaded")
    end
    trip.missingSince = nil
    if trip.recovery and trip.recovery.kind == "road"
        and trip.state ~= "driving_out" and trip.state ~= "driving_home"
        and trip.recovery.remainingMs <= 0 then
        hold(trip, "car_recovery_timeout")
        Car.Recovery.roadPulse(mission, trip, car, now)
        return true
    end
    if trip.state == "walking_to_car" then
        local transferred, why = Car.ensureDriverKey(mission.roster, car)
        if not transferred then hold(trip, why) return true end
        trip.state = trip.field and trip.leg=="home" and "boarding_home" or "boarding_out"
        scout.phase = trip.state
        trip.boardStartedAt = now
        return true
    end
    if trip.state == "returning_to_car" then
        local transferred, why = Car.ensureDriverKey(mission.roster, car)
        if not transferred then hold(trip, why) return true end
        trip.state = "boarding_home"
        scout.phase = "boarding_home"
        trip.boardStartedAt = now
        return true
    end
    if trip.state == "boarding_out" or trip.state == "boarding_home"
        or trip.state == "interrupted_by_load" then
        if trip.state == "interrupted_by_load" then
            -- Restore has rebuilt the live roster and car. The old job/token
            -- is gone; every member starts a fresh physical boarding action.
            local ready, why = resumeReady(mission, trip, car)
            if not ready then
                if restartWalkingReason[why] then
                    trip.state = "fallback_unloading"
                    trip.blocker = why
                    scout.phase = "fallback_unloading"
                elseif not Car.Recovery.holdRoad(mission, trip, car, now, why) then
                    hold(trip, why)
                end
                return true
            end
            local transferred, transferReason = Car.ensureDriverKey(
                mission.roster, car)
            if not transferred then
                hold(trip, transferReason)
                return true
            end
            trip.state = trip.leg == "home" and "boarding_home"
                or "boarding_out"
            scout.phase = trip.state
            trip.boardStartedAt = now
            return true
        end
        local unlocked, unlockReason = unlockSquadDoors(mission, trip, car)
        if not unlocked then hold(trip, unlockReason) return true end
        if not teamSeated(mission, trip, car) then
            if now - (trip.boardStartedAt or now) > 120000 then
                trip.state = "boarding_rollback"
                trip.blocker = "boarding_deadline"
                for _, member in ipairs(mission.roster) do
                    if travelMember(mission, member) then
                        local seated, current, seat = SC.Vehicle.isNativeSeated(member.actor)
                        if not seated or current ~= car or seat ~= trip.seats[member.id] then
                            local status = trip.boardingStatus and trip.boardingStatus[member.id]
                            local x, y, z = SC.GameplayUtil.position(member.actor)
                            traceTrip(trip, "boarding_deadline", "actor=" .. tostring(member.id)
                                .. " seat=" .. tostring(trip.seats[member.id])
                                .. " reason=" .. tostring(status and status.reason or "boarding_not_attempted")
                                .. " navigation=" .. tostring(status and status.navigationReason or "none")
                                .. " point=" .. tostring(x) .. "," .. tostring(y) .. "," .. tostring(z))
                        end
                    end
                end
            end
            return true
        end
        local ready, why, roadEntry = departReady(mission, trip, car)
        if not ready then
            if Car.Recovery.holdRoad(mission, trip, car, now, why) then return true end
            trip.recovery = nil
            trip.state, trip.blocker = "boarding_rollback", why
            return true
        end
        if trip.leg == "outbound" then
            trip.homeRoadEntry = { x = roadEntry.x, y = roadEntry.y, z = 0 }
        end
        local goal = trip.leg == "home"
            and (trip.homeRoadEntry or trip.departure) or trip.siteStop
        if trip.leg == "home"
            and type(SC.GameplayUtil.diagnostic) == "function" then
            SC.GameplayUtil.diagnostic("expedition-car", mission.leader.actor,
                "action=home_road_goal point=" .. tostring(goal.x)
                    .. "," .. tostring(goal.y))
        end
        -- Home: the road follower turns into the planned driveway itself.
        local roadExit = trip.leg == "home" and trip.homeRoadEntry
            and trip.departure and {
                entry = trip.homeRoadEntry, bay = trip.departure,
            } or nil
        local started, reason = SC.Driving.drive(mission.leader.actor,
            goal, { speedKmh = 30,
                -- A manual logging area is admitted against this exact stop's
                -- hauling circle. The old ten-tile setback can move it outside.
                stopShortTiles = trip.leg == "outbound"
                    and not (scout.wood and scout.wood.version == 2) and 10 or 0,
                roadAccessEntry = roadEntry, roadAccessExit = roadExit })
        if not started then
            if type(reason) == "string"
                and reason:sub(1, 9) == "deferred:" then
                if now - (trip.boardStartedAt or now) > 120000 then
                    trip.state, trip.blocker = "boarding_rollback",
                        "drive_deferred_deadline"
                else
                    trip.blocker = reason
                end
                return true
            end
            if Car.Recovery.holdRoad(mission, trip, car, now, reason) then return true end
            trip.recovery = nil
            trip.state, trip.blocker = "boarding_rollback", reason
            return true
        end
        trip.state = trip.leg == "home" and "driving_home" or "driving_out"
        scout.phase = trip.state
        return true
    end
    if trip.state == "driving_out" or trip.state == "driving_home" then
        local status = SC.Driving.jobStatus(mission.leader.actor)
        Car.Recovery.progress(trip, car, status)
        if trip.recovery and trip.recovery.kind == "road"
            and trip.recovery.remainingMs <= 0 then
            hold(trip, "car_recovery_timeout")
            Car.Recovery.roadPulse(mission, trip, car, now)
            return true
        end
        if status and status.result == "arrived" then
            if status.owned == false or status.phase == "released" then
                Car.parkingFailed(mission, trip, car,
                    status.firstParkingRefusal or status.reason or "parking_requires_arrived_drive", status)
                return true
            end
            trip.state = trip.leg == "home" and "parking_home"
                or "unloading_site"
            scout.phase = trip.state
            if trip.leg == "home" then
                local at = point(car)
                traceTrip(trip, "road_arrived", "point="
                    .. tostring(at and at.x) .. "," .. tostring(at and at.y), status)
            end
        elseif status and status.result == "failed" then
            trip.blocker = status.reason
            local native = type(SC.Driving.status) == "function"
                and SC.Driving.status(mission.leader.actor) or nil
            local failedAt = point(car)
            trip.lastFailure = { reason = type(status.reason) == "string"
                    and status.reason:sub(1, 128) or "drive_failed",
                at = failedAt, obstacle = native and type(native.obstacleKind) == "string"
                    and native.obstacleKind:sub(1, 64) or nil }
            traceTrip(trip, "road_failed", "reason="
                .. tostring(status.reason) .. " at="
                .. tostring(failedAt and failedAt.x) .. ","
                .. tostring(failedAt and failedAt.y)
                .. " attempts=" .. tostring(status.attempts)
                .. " detail=" .. tostring(status.detail)
                .. "/" .. tostring(status.routeFailureReason)
                .. " source=" .. tostring(status.routeSourceX) .. "," .. tostring(status.routeSourceY)
                .. " blocked=" .. tostring(status.blockedKind) .. "@"
                    .. tostring(status.blockedX) .. "," .. tostring(status.blockedY)
                .. " native=" .. tostring(native and native.mode)
                .. "/" .. tostring(native and native.state)
                .. " obstacle=" .. tostring(native and native.obstacleKind))
            if status.reason == "streaming_stalled" then
                Car.Recovery.holdRoad(mission, trip, car, now, "streaming_stalled")
            elseif trip.leg == "home" and trip.homeRoadEntry
                and (status.reason == "goal_not_reached"
                    or status.reason == "route_blocked"
                    or status.reason == "no_route"
                    or status.reason == "turn_failed") then
                local at = point(car)
                local stopped = SC.Vehicle.isStationary(car)
                local entry = trip.homeRoadEntry
                if stopped and at and (at.x - entry.x)^2
                    + (at.y - entry.y)^2 <= 225 then
                    trip.state, scout.phase = "parking_home", "parking_home"
                    trip.parkingRecovery = true
                    traceTrip(trip, "near_road_parking_recovery")
                else
                    Car.Recovery.holdRoad(mission, trip, car, now, status.reason)
                end
            else
                if not Car.Recovery.holdRoad(mission, trip, car, now, status.reason) then
                    trip.recovery = nil
                    trip.state = "fallback_unloading"
                    scout.phase = trip.state
                end
            end
        elseif status and status.result == "interrupted" then
            trip.blocker = status.reason or "drive_interrupted"
            if SC.Vehicle.hasPlayerAboard
                and SC.Vehicle.hasPlayerAboard(car) then
                hold(trip, "player_aboard")
            else
                trip.state = "fallback_unloading"
                scout.phase = trip.state
            end
        elseif not status then
            trip.statusMissingSince = trip.statusMissingSince or now
            if now - trip.statusMissingSince > 5000 then
                Car.Recovery.holdRoad(mission, trip, car, now, "drive_status_unavailable")
            end
        else
            trip.statusMissingSince = nil
        end
        return true
    end
    if trip.state == "parking_home" then
        if trip.field and trip.homeStop and trip.homeStop.kind=="roadside" then
            local clear,why=Car.fieldStopClear(mission,trip,car)
            if clear then trip.state,scout.phase="unloading_home","unloading_home"
            else hold(trip,why or "home_stop_unavailable") end
            return true
        end
        local zone = Car.areaById(trip.parkingZoneId)
        if not homeParkingMatches(trip) then
            hold(trip, "home_parking_changed")
        else
            local fit, reason = Car.fitsParking(car, zone, trip.seats)
            local status = trip.approachStartedAt
                and SC.Driving.jobStatus(mission.leader.actor) or nil
            -- A valid parking area accepts either car orientation. Road
            -- travel normally brings the car home facing the opposite way;
            -- requiring the departure heading would force an unnecessary
            -- turn inside the marked bay.
            if reason == "parking_not_stationary" and (not trip.approachStartedAt
                or status and status.result == "arrived") then
                -- The road follower can report arrived one physics tick before
                -- the vehicle has settled. Do not request a new parking drive
                -- while the car is still coasting inside the marked bay.
                -- An owned driveway leg is still approaching, not settling.
                trip.parkingSettleStartedAt = trip.parkingSettleStartedAt or now
                if now - trip.parkingSettleStartedAt > 10000 then
                    hold(trip, "parking_not_stationary")
                end
            elseif fit then
                trip.parkingSettleStartedAt = nil
                trip.state, scout.phase = "unloading_home", "unloading_home"
                traceTrip(trip, "parking_verified")
            elseif trip.approachStartedAt then
                trip.parkingSettleStartedAt = nil
                if status and status.firstParkingRefusal then trip.parkingRefusal = trip.parkingRefusal or status.firstParkingRefusal end
                if status and (status.result == "failed" or status.owned == false or status.phase == "released") then
                    Car.parkingFailed(mission, trip, car, status.reason or "parking_approach_failed", status)
                elseif status and status.result == "arrived" then
                    if trip.approachStage == "road"
                        or trip.approachStage == "driveway" then
                        -- The road alignment or one driveway leg has finished.
                        -- The next pulse checks the remaining route and starts
                        -- another short leg toward the marked bay.
                        trip.approachStage, trip.approachStartedAt = nil, nil
                    else
                        Car.parkingFailed(mission, trip, car, reason or "parking_footprint_outside_area", status)
                    end
                elseif status and status.phase == "parking_aligning" then
                    trip.parkingAligning = true
                elseif trip.parkingAligning and status and status.phase == "approaching" then
                    trip.parkingAligning, trip.approachStartedAt = nil, now
                elseif now - trip.approachStartedAt > 30000 then
                    SC.Driving.release(mission.leader.actor, "parking_timeout")
                    Car.parkingFailed(mission, trip, car, "parking_approach_timeout", status)
                end
            else
                trip.parkingSettleStartedAt = nil
                local at = point(car)
                local gap = at and math.sqrt((at.x - trip.departure.x)^2
                    + (at.y - trip.departure.y)^2) or math.huge
                local status = SC.Driving.jobStatus(mission.leader.actor)
                local road = status and status.roadGoal
                local roadGap = road and at and math.sqrt(
                    (at.x - road.x)^2 + (at.y - road.y)^2) or math.huge
                local roadProgress = 0
                if road and at then
                    local dx, dy = trip.departure.x - road.x,
                        trip.departure.y - road.y
                    local lengthSq = dx * dx + dy * dy
                    if lengthSq > 0.01 then
                        roadProgress = ((at.x - road.x) * dx
                            + (at.y - road.y) * dy) / lengthSq
                    end
                end
                -- Once the car has entered the driveway, keep moving toward
                -- the bay. Re-centering on the road after every short leg
                -- would send it back to the road indefinitely.
                if gap > 15 and roadGap > 1.5 and roadProgress <= 0.02 then
                    if roadGap > 15 then hold(trip, "parking_road_end_unavailable")
                    else
                        local started, why = SC.Driving.approach(
                            mission.leader.actor, road, 30000,
                            trip.parkingRecovery == true, trip.field == true)
                        if started then
                            trip.parkingRecovery = nil
                            trip.approachStage, trip.approachStartedAt = "road", now
                            traceTrip(trip, "parking_segment", "stage=road")
                        else
                            Car.parkingFailed(mission, trip, car, why, SC.Driving.jobStatus(mission.leader.actor))
                        end
                    end
                else
                    local clear, why = targetBayClear(car, zone, trip.departure)
                    if clear then clear, why = Car.accessBetween(car,
                        at, trip.departure) end
                    if not clear then hold(trip, why)
                    else
                        local waypoint = trip.departure
                        if gap > drivewayApproachTiles then
                            local fraction = drivewayApproachTiles / gap
                            waypoint = { x = at.x + (trip.departure.x - at.x) * fraction,
                                y = at.y + (trip.departure.y - at.y) * fraction,
                                z = 0 }
                        end
                        local started, startReason = SC.Driving.approach(
                            mission.leader.actor, waypoint, 30000,
                            trip.parkingRecovery == true, trip.field == true)
                        if started then
                            trip.parkingRecovery = nil
                            trip.approachStage = waypoint == trip.departure
                                and "bay" or "driveway"
                            trip.approachStartedAt = now
                            traceTrip(trip, "parking_segment", "stage="
                                .. trip.approachStage .. " target="
                                .. tostring(waypoint.x) .. ","
                                .. tostring(waypoint.y))
                        else
                            Car.parkingFailed(mission, trip, car, startReason, SC.Driving.jobStatus(mission.leader.actor))
                        end
                    end
                end
            end
        end
        return true
    end
    if trip.state == "unloading_site" or trip.state == "unloading_home"
        or trip.state == "boarding_rollback"
        or trip.state == "fallback_unloading" then
        local unloaded, why = stopAndUnload(mission, trip, car, now)
        if not unloaded then
            trip.blocker = why
            return true
        end
        local at = point(car)
        if trip.state == "unloading_site" then
            trip.sitePoint = at
            trip.state = "parked_at_site"
            scout.phase = (scout.returnRequested or trip.returnRequested)
                and "inbound" or "outbound"
            trip.returnRequested = nil
            scout.trail = { { x = math.floor(mission.leader.actor:getX()),
                y = math.floor(mission.leader.actor:getY()), z = 0 } }
            scout.roadRoute, scout.road = nil, nil
        elseif trip.state == "unloading_home" then
            local saved,saveReason=fieldStopBarrier(mission,trip,car)
            if not saved then trip.blocker=saveReason return true end
            trip.state, scout.phase = "home_wait", trip.field and "inbound" or "awaiting_player"
            if trip.field and (trip.blocker == "home_car_save_pending"
                or trip.blocker == "home_car_save_failed"
                or trip.blocker == "home_car_save_unavailable") then trip.blocker = nil end
            if trip.field then scout.roadRoute,scout.road=nil,nil end
            traceTrip(trip, "home_unloaded")
        else
            local abandoned, abandonReason = abandonToWalking(
                mission, trip, car)
            if not abandoned then trip.blocker = abandonReason end
            if abandoned then
                traceTrip(trip, "road_unload_fallback", "reason="
                    .. tostring(trip.blocker))
            end
        end
        return true
    end
    if trip.state == "home_wait" then return false end
    hold(trip, "unknown_car_state")
    return true
end

local validStates = {
    walking_to_car = true, boarding_out = true, driving_out = true,
    unloading_site = true, parked_at_site = true,
    returning_to_car = true, boarding_home = true, driving_home = true,
    parking_home = true, unloading_home = true,
    boarding_rollback = true, fallback_unloading = true,
    held = true, interrupted_by_load = true, abandoned = true,
    home_wait = true,
}

local interruptedStates = {
    walking_to_car = true, boarding_out = true, driving_out = true,
    returning_to_car = true, boarding_home = true,
    driving_home = true, parking_home = true,
}

local function pointCopy(value)
    if type(value) ~= "table" then return nil end
    local x, y, z = finite(value.x), finite(value.y), finite(value.z)
    if not x or not y or not z or x < 0 or y < 0 or z ~= 0
        or x > 30000 or y > 30000 then return nil end
    return { x = x, y = y, z = z }
end

function Car.copyRecovery(value)
    if value == nil then return nil end
    if type(value) ~= "table" or (value.kind ~= "road" and value.kind ~= "stream")
        or type(value.remainingMs) ~= "number" or not finite(value.remainingMs) or value.remainingMs < 0
        or value.remainingMs > Car.Recovery.limitMs
        or type(value.attempts) ~= "number" or value.attempts < 0 or value.attempts > 32
        or value.attempts ~= math.floor(value.attempts)
        or type(value.reason) ~= "string" or #value.reason < 1 or #value.reason > 128 then
        return nil, "vehicle_recovery_invalid"
    end
    local origin = value.origin ~= nil and pointCopy(value.origin) or nil
    if value.origin ~= nil and not origin then return nil, "vehicle_recovery_invalid" end
    return { kind=value.kind, remainingMs=value.remainingMs,
        attempts=value.attempts, reason=value.reason, origin=origin }
end

local function rectangleCopy(value)
    if type(value) ~= "table" or value.z ~= 0 then return nil end
    local result = { z = 0 }
    for _, field in ipairs({ "x1", "y1", "x2", "y2" }) do
        result[field] = finite(value[field])
        if result[field] == nil or result[field] < 0
            or result[field] > 30000
            or result[field] ~= math.floor(result[field]) then return nil end
    end
    if result.x2 < result.x1 or result.y2 < result.y1
        or (result.x2 - result.x1 + 1)
            * (result.y2 - result.y1 + 1) > 256 then return nil end
    return result
end

function Car.copyDescriptor(value, roster, leaderId)
    if type(value) ~= "table" or not validStates[value.state]
        or (value.leg ~= "outbound" and value.leg ~= "home")
        or type(value.sqlId) ~= "number" or value.sqlId < 0
        or value.sqlId ~= math.floor(value.sqlId)
        or type(value.script) ~= "string" or #value.script < 1
        or #value.script > 128
        or type(value.parkingZoneId) ~= "string"
        or #value.parkingZoneId < 1 or #value.parkingZoneId > 128
        or type(value.seats) ~= "table" then return nil, "vehicle_invalid" end
    local parking = rectangleCopy(value.parking)
    local departure, home = pointCopy(value.departure), pointCopy(value.home)
    local siteStop = pointCopy(value.siteStop)
    if not parking or not departure or not home or not siteStop then
        return nil, "vehicle_anchor_invalid"
    end
    local homeStop
    if value.field~=nil and type(value.field)~="boolean" then return nil,"vehicle_field_invalid" end
    if value.field==true then
        homeStop=Car.copyFieldStop and Car.copyFieldStop(value.homeStop)
        if not homeStop or value.leg~="home"
            or home.x~=homeStop.core.x or home.y~=homeStop.core.y
            or departure.x~=homeStop.point.x or departure.y~=homeStop.point.y then return nil,"vehicle_field_invalid" end
    elseif value.homeStop~=nil then return nil,"vehicle_field_invalid" end
    local homeRoadEntry = value.homeRoadEntry ~= nil
        and pointCopy(value.homeRoadEntry) or nil
    if value.homeRoadEntry ~= nil and not homeRoadEntry then
        return nil, "vehicle_road_entry_invalid"
    end
    if homeStop then
        if not homeRoadEntry or homeRoadEntry.x~=homeStop.roadEntry.x or homeRoadEntry.y~=homeStop.roadEntry.y
            or siteStop.x~=departure.x or siteStop.y~=departure.y
            or homeStop.kind=="parking" and (value.parkingZoneId~=homeStop.zoneId or not sameParkingArea(parking,homeStop.parking))
            or homeStop.kind=="roadside" and value.parkingZoneId~="field:roadside" then return nil,"vehicle_field_invalid" end
    end
    local seats, used = {}, {}
    if type(roster) ~= "table" then return nil, "vehicle_roster_invalid" end
    for _, member in ipairs(roster) do
        local id = type(member) == "table" and member.id or member
        local seat = value.seats[id]
        if type(id) ~= "string" or type(seat) ~= "number"
            or seat ~= math.floor(seat) or seat < 0 or seat > 31
            or used[seat] or (id == leaderId and seat ~= 0)
            or (id ~= leaderId and seat == 0) then
            return nil, "vehicle_seat_map_invalid"
        end
        used[seat], seats[id] = true, seat
    end
    for id in pairs(value.seats) do
        if seats[id] == nil then return nil, "vehicle_seat_map_invalid" end
    end
    local fuel = finite(value.departureFuel)
    if not fuel or fuel < 0 or fuel > 1000 then
        return nil, "vehicle_fuel_invalid"
    end
    local heading = finite(value.departureHeading)
    if heading == nil or math.abs(heading) > 360 then
        return nil, "vehicle_heading_invalid"
    end
    local state = value.state
    local failure = value.lastFailure
    local failureAt = failure and type(failure) == "table" and pointCopy(failure.at) or nil
    if failure ~= nil and (type(failure) ~= "table" or type(failure.reason) ~= "string"
        or #failure.reason < 1 or #failure.reason > 128
        or failure.at ~= nil and not failureAt
        or failure.obstacle ~= nil and (type(failure.obstacle) ~= "string" or #failure.obstacle > 64)) then
        return nil, "vehicle_failure_invalid"
    end
    if value.parkingRefusal ~= nil and (type(value.parkingRefusal) ~= "string"
        or #value.parkingRefusal < 1 or #value.parkingRefusal > 128) then return nil, "vehicle_failure_invalid" end
    local resumeState = value.resumeState
    if state == "held" and not validStates[resumeState] then
        return nil, "vehicle_hold_invalid"
    end
    local recovery, recoveryReason = Car.copyRecovery(value.recovery)
    if value.recovery ~= nil and not recovery then return nil, recoveryReason end
    if recovery and recovery.kind == "stream" and (value.leg ~= "home"
        or state ~= "returning_to_car"
            and not (state == "held" and resumeState == "returning_to_car")
            and state ~= "interrupted_by_load") then
        return nil, "vehicle_recovery_invalid"
    end
    if recovery and (state == "abandoned" or state == "home_wait"
        or state == "parked_at_site") then return nil, "vehicle_recovery_invalid" end
    local result = {
        state = state, leg = value.leg, sqlId = value.sqlId,
        script = value.script, seats = seats,
        parkingZoneId = value.parkingZoneId, parking = parking,
        departure = departure, home = home, siteStop = siteStop,
        homeRoadEntry = homeRoadEntry,
        position = pointCopy(value.position),
        sitePoint = pointCopy(value.sitePoint),
        abandonedAt = pointCopy(value.abandonedAt),
        departureFuel = fuel,
        departureHeading = heading,
        resumeState = state == "held" and resumeState or nil,
        returnRequested = value.returnRequested == true,
        blocker = type(value.blocker) == "string"
            and value.blocker:sub(1, 128) or nil,
        lastFailure = failure and { reason = failure.reason,
            at = failureAt, obstacle = failure.obstacle } or nil,
        parkingRefusal = value.parkingRefusal,
        recovery = recovery,
    }
    if value.field then
        if value.engineStopped~=nil and type(value.engineStopped)~="boolean" then return nil,"vehicle_field_invalid" end
        result.field,result.homeStop,result.engineStopped=true,homeStop,value.engineStopped==true
    end
    if value.radioResumeState ~= nil then
        if not value.field or not validStates[value.radioResumeState]
            or value.radioResumeState == "held" or value.radioResumeState == "abandoned"
            or value.radioResumeState == "home_wait" then return nil,"vehicle_hold_invalid" end
        result.radioResumeState = value.radioResumeState
    end
    return result
end

function Car.exportDescriptor(value, roster, leaderId)
    if type(value) ~= "table" then return nil, "vehicle_invalid" end
    local car = carLoaded(value)
    if car ~= nil then value.position = point(car) end
    return Car.copyDescriptor(value, roster, leaderId)
end

function Car.restoreDescriptor(value, roster, leaderId)
    local result, reason = Car.copyDescriptor(value, roster, leaderId)
    if not result then return nil, reason end
    if interruptedStates[result.state] or result.field and result.state == "held"
        and result.resumeState == "parking_home" then
        result.state = "interrupted_by_load"
        result.resumeState = nil
    end
    if result.radioResumeState then
        result.state, result.resumeState = "interrupted_by_load", nil
        result.radioResumeState = "interrupted_by_load"
    end
    if result.recovery and not result.radioResumeState then
        if result.recovery.kind == "stream" then
            result.state, result.resumeState = "returning_to_car", nil
        else
            result.state, result.resumeState = "interrupted_by_load", nil
        end
    end
    return result
end

-- Field home trips share the proven physical home-leg controller. Review only
-- reads native objects/map geometry; keys and seats change after dispatch.
do
    local function fieldPlayer(options)
        return type(options)=="table" and options.player
            or type(getSpecificPlayer)=="function" and getSpecificPlayer(0) or nil
    end
    local function fieldBase(value)
        return type(value)=="table" and (value.base or value.zones and value)
            or SC.BaseLife and SC.BaseLife.active and SC.BaseLife.active()
    end
    local function range(a,b)
        return a and b and math.sqrt((a.x-b.x)^2+(a.y-b.y)^2) or math.huge
    end
    local function nameOf(record)
        return SC.Names and SC.Names.displayName and SC.Names.displayName(record)
            or record and (record.name or record.id) or ""
    end
    local function physicalKey(records,vehicle)
        local okay,id=call(vehicle,"getKeyId")
        if not okay or not finite(id) or id<0 or id~=math.floor(id) then return nil end
        return findSquadKey(records,vehicle)
    end
    function Car.fieldFingerprint(vehicle,records,player)
        local parts={tostring(vehicle)}
        local function read(object,method,...)
            local okay,value=call(object,method,...)
            parts[#parts+1]=okay and tostring(value) or "unreadable"
            return okay and value or nil
        end
        for _,method in ipairs({"getSqlId","getScriptName","getX","getY","getZ","getKeyId","isEngineRunning"}) do read(vehicle,method) end
        local count=tonumber(read(vehicle,"getMaxPassengers")) or 0
        for seat=0,math.min(31,count-1) do read(vehicle,"isSeatInstalled",seat) read(vehicle,"getCharacter",seat) end
        for _,id in ipairs({"Engine","TireFrontLeft","TireFrontRight","TireRearLeft","TireRearRight","GasTank"}) do
            local okay,part=call(vehicle,"getPartById",id)
            if okay then read(part,"getCondition") read(part,"getInventoryItem")
                if id=="GasTank" then read(part,"getContainerContentAmount") end
            else parts[#parts+1]="missing:"..id end
        end
        player=player or fieldPlayer()
        read(player,"getVehicle")
        for _,record in ipairs(records or {}) do
            parts[#parts+1]=tostring(record.id) parts[#parts+1]=tostring(record.actor)
            read(record.actor,"getX") read(record.actor,"getY") read(record.actor,"getZ")
            read(record.actor,"getVehicle")
            local held=physicalKey({record},vehicle)
            parts[#parts+1]=tostring(held and held.item)
        end
        return table.concat(parts,"|")
    end
    local function fieldCheck(records,vehicle,player,doors)
        local review={vehicle=vehicle,name=Car.displayName(vehicle),neededSeats=type(records)=="table" and #records or 0,seats=0}
        local function reject(reason) review.canUse=false review.reason=reason return nil,reason,review end
        if type(records)~="table" or #records<1 or #records>4 then return reject("team_unavailable") end
        local ids,actors={},{ }
        for _,record in ipairs(records) do
            if type(record)~="table" or type(record.id)~="string" or not record.actor or ids[record.id] or actors[record.actor] then return reject("team_unavailable") end
            ids[record.id],actors[record.actor]=true,record.id
        end
        local identity,sqlId=call(vehicle,"getSqlId")
        sqlId=identity and finite(sqlId) or nil
        if not sqlId or sqlId<1 or sqlId~=math.floor(sqlId) or not SC.Vehicle
            or not SC.Vehicle.loadedBySqlId or SC.Vehicle.loadedBySqlId(sqlId)~=vehicle then return reject("car_unavailable") end
        review.sqlId=sqlId
        local at=point(vehicle) local leaderAt=point(records[1].actor)
        review.distance=range(at,leaderAt)
        if not at or math.abs(at.z)>.2 or not leaderAt or review.distance>30 then return reject("car_too_far") end
        local playerOkay,playerCar=call(player,"getVehicle")
        local playerKey=player and physicalKey({{actor=player}},vehicle)
        review.yourCar=playerKey~=nil or playerOkay and playerCar==vehicle
        if not playerOkay then return reject("player_unavailable") end
        if playerCar==vehicle then return reject("player_car") end
        local stopped,why=SC.Vehicle.isStationary(vehicle)
        if not stopped then return reject(why=="vehicle is moving" and "car_moving" or why or "car_moving") end
        local scriptOkay,script=call(vehicle,"getScriptName")
        if not scriptOkay or type(script)~="string" or script=="" then return reject("car_identity_unavailable") end
        local countOkay,count=call(vehicle,"getMaxPassengers")
        count=countOkay and finite(count) or nil
        if not count or count~=math.floor(count) or count<1 or count>32 then return reject("too_few_seats") end
        local installed,occupants,seats,used={},{},{},{}
        for seat=0,count-1 do
            local hasOkay,has=call(vehicle,"isSeatInstalled",seat)
            local occupiedOkay,occupant=call(vehicle,"getCharacter",seat)
            if not hasOkay or not occupiedOkay then return reject("seat_unavailable") end
            installed[seat],occupants[seat]=has==true,occupant
            if has==true then review.seats=review.seats+1 end
            if occupant and not actors[occupant] then return reject("car_has_other_occupants") end
        end
        if review.seats<#records then return reject("too_few_seats") end
        if not installed[0] then return reject("seat_unavailable") end
        if occupants[0] and occupants[0]~=records[1].actor then return reject("field_driver_mismatch") end
        seats[records[1].id],used[0]=0,true
        for index,record in ipairs(records) do
            local deadOkay,dead=call(record.actor,"isDead")
            if not deadOkay or dead~=false then return reject("team_unavailable") end
            local seated,current,seat=SC.Vehicle.isNativeSeated(record.actor)
            if seated then
                if current==vehicle and index==1 and seat~=0 then return reject("field_driver_mismatch") end
                if current~=vehicle or not installed[seat] or occupants[seat]~=record.actor
                    or index==1 and seat~=0 or index>1 and (seat==0 or used[seat]) then return reject("seat_unavailable") end
                seats[record.id],used[seat]=seat,true
            end
        end
        for index=2,#records do
            local record=records[index]
            if seats[record.id]==nil then
                local doorReason
                for seat=1,count-1 do
                    if installed[seat] and not used[seat] and occupants[seat]==nil then
                        local reachable=true
                        if doors then
                            local squares,_,why=SC.Vehicle.boardingSquares(record.actor,vehicle,seat,false)
                            reachable=squares~=nil and #squares>0
                            if not reachable then doorReason=doorReason or why or "door_inaccessible" end
                        end
                        if reachable then seats[record.id],used[seat]=seat,true break end
                    end
                end
                if seats[record.id]==nil then return reject(doorReason or "seat_unavailable") end
            end
        end
        for _,record in ipairs(records) do
            local seat=seats[record.id]
            if doors and occupants[seat]~=record.actor then
                local squares,_,reason=SC.Vehicle.boardingSquares(record.actor,vehicle,seat,seat==0)
                if not squares or #squares<1 then return reject(reason or "door_inaccessible") end
            end
        end
        if not componentReady(vehicle,"Engine") then return reject("engine_unusable") end
        for _,id in ipairs({"TireFrontLeft","TireFrontRight","TireRearLeft","TireRearRight"}) do
            if not componentReady(vehicle,id,true) then return reject("wheel_unusable") end
        end
        local held=physicalKey(records,vehicle)
        if not held then return reject(playerKey and "driver_needs_key_from_player" or "driver_needs_key") end
        review.keyHolderId,review.keyHolderName=held.record.id,nameOf(held.record)
        local tankOkay,tank=call(vehicle,"getPartById","GasTank")
        local fuelOkay,fuel=call(tankOkay and tank or nil,"getContainerContentAmount")
        local capacityOkay,capacity=call(tankOkay and tank or nil,"getContainerCapacity")
        fuel=fuelOkay and finite(fuel) or nil capacity=capacityOkay and finite(capacity) or nil
        if fuel==nil or fuel<0 then return reject("fuel_unreadable") end
        review.fuel,review.fuelCapacity=fuel,capacity
        review.fuelPercent=capacity and capacity>0 and fuel/capacity*100 or nil
        if fuel<=0 then return reject("fuel_insufficient") end
        local headingOkay,heading=call(vehicle,"getAngleZ")
        heading=headingOkay and finite(heading) or nil
        if heading==nil then return reject("car_orientation_unavailable") end
        review.canUse=true
        return {field=true,vehicle=vehicle,sqlId=sqlId,script=script,name=review.name,seats=seats,seatCount=review.seats,records=records,leaderId=records[1].id,
            neededSeats=#records,departure=at,heading=heading,fuel=fuel,fuelCapacity=capacity,fuelPercent=review.fuelPercent,
            keyHolderId=review.keyHolderId,keyHolderName=review.keyHolderName,yourCar=review.yourCar},nil,review
    end
    function Car.fieldCandidates(records,player)
        local rows={} local leader=type(records)=="table" and records[1] and point(records[1].actor)
        if not leader or not SC.Vehicle or not SC.Vehicle.loadedVehicles then return rows end
        player=player or fieldPlayer()
        for _,vehicle in ipairs(SC.Vehicle.loadedVehicles()) do
            if range(point(vehicle),leader)<=30 then
                local _,_,row=fieldCheck(records,vehicle,player,false)
                row.fingerprint=Car.fieldFingerprint(vehicle,records,player)
                rows[#rows+1]=row
            end
        end
        table.sort(rows,function(a,b) if a.distance==b.distance then return (a.sqlId or -1)<(b.sqlId or -1) end return (a.distance or math.huge)<(b.distance or math.huge) end)
        return rows
    end
    local function fieldBounds(value)
        if type(value)~="table" or value.z~=0 then return nil end
        local result={z=0}
        for _,key in ipairs({"x1","y1","x2","y2"}) do
            local n=finite(value[key])
            if not n or n~=math.floor(n) or n<0 or n>30000 then return nil end
            result[key]=n
        end
        return result.x1<=result.x2 and result.y1<=result.y2 and result or nil
    end
    local function baseFingerprint(base)
        if type(base)~="table" or not pointCopy(base.core) then return nil end
        local rows={tostring(base.id),base.core.x..","..base.core.y..","..base.core.z}
        for _,zone in ipairs(base.zones or {}) do
            if zone.kind=="area" or zone.kind=="parking" then
                rows[#rows+1]=table.concat({tostring(zone.kind),tostring(zone.id),tostring(zone.name),
                    tostring(zone.x1),tostring(zone.y1),tostring(zone.x2),tostring(zone.y2),tostring(zone.z)},",")
            end
        end
        table.sort(rows)
        return table.concat(rows,"|")
    end
    function Car.fieldBaseFingerprint(base) return baseFingerprint(base) end
    local function outside(bounds,at,radius)
        for _,area in ipairs(bounds) do
            if at.x+radius>=area.x1 and at.x-radius<area.x2+1
                and at.y+radius>=area.y1 and at.y-radius<area.y2+1 then return false end
        end
        return true
    end
    function Car.copyFieldStop(value,camp)
        if type(value)~="table" or value.kind~="parking" and value.kind~="roadside"
            or type(value.baseId)~="string" or #value.baseId<1 or #value.baseId>128 then return nil,"home_stop_invalid" end
        local at,core,entry=pointCopy(value.point),pointCopy(value.core),pointCopy(value.roadEntry)
        if not at or not core or not entry or type(value.boundaries)~="table" or #value.boundaries<1 or #value.boundaries>128 then return nil,"home_stop_invalid" end
        if camp and (camp.id~=value.baseId or not camp.core or range(camp.core,core)>.01 or camp.core.z~=0) then return nil,"home_stop_camp_changed" end
        local bounds={}
        for _,area in ipairs(value.boundaries) do local clean=fieldBounds(area) if not clean then return nil,"home_stop_invalid" end bounds[#bounds+1]=clean end
        local result={kind=value.kind,baseId=value.baseId,point=at,core=core,roadEntry=entry,boundaries=bounds,
            label=type(value.label)=="string" and value.label:sub(1,128) or "",
            warning=type(value.warning)=="string" and value.warning:sub(1,128) or nil,
            provisional=value.provisional==true,clearanceOnArrival=true}
        if value.kind=="parking" then
            result.parking=rectangleCopy(value.parking) result.zoneId=value.zoneId
            if not result.parking or type(result.zoneId)~="string" or #result.zoneId<1 or #result.zoneId>128
                or not contains(result.parking,at) then return nil,"home_stop_invalid" end
        else
            result.radius=finite(value.radius) result.roadWidth=finite(value.roadWidth)
            if not result.radius or result.radius<=0 or result.radius>32 or not result.roadWidth or result.roadWidth<6
                or result.roadWidth>64 or range(at,core)>40 or not outside(bounds,at,result.radius) then return nil,"home_stop_invalid" end
        end
        return result
    end
    function Car.validFieldStop(value,camp) return Car.copyFieldStop(value,camp)~=nil end
    local function shapeRadius(vehicle)
        local at,poly=point(vehicle),Car.footprint(vehicle)
        if not at or not poly then return nil end
        local radius=0
        for index=1,4 do
            local x,y=finite(poly["x"..index]),finite(poly["y"..index])
            if not x or not y then return nil end
            radius=math.max(radius,range(at,{x=x,y=y}))
        end
        return radius>0 and radius<=16 and radius or nil
    end
    local function bayTargets(zone)
        local result={} local center={x=(zone.x1+zone.x2+1)/2,y=(zone.y1+zone.y2+1)/2,z=0}
        result[1]=center
        for x=zone.x1,zone.x2 do for y=zone.y1,zone.y2 do result[#result+1]={x=x+.5,y=y+.5,z=0} end end
        table.sort(result,function(a,b) local da,db=range(a,center),range(b,center) if da==db then return a.x==b.x and a.y<b.y or a.x<b.x end return da<db end)
        return result
    end
    local function mappedRoadside(route,base,bounds,radius)
        local best,bestRange
        for index=2,#(route.points or {}) do
            local a,b=route.points[index-1],route.points[index]
            local length=range(a,b) local width=finite(b.width) or finite(a.width) or 0
            if length<6000 and width>=6 then
                -- SCRoadFollower's right-hand lane offset is bounded by one
                -- quarter of the mapped width. Reserve that real controller
                -- offset as well as the whole car's measured corner radius.
                local laneMargin=width*.25
                for step=0,math.ceil(length) do
                    local t=length>0 and math.min(1,step/length) or 0
                    local at={x=a.x+(b.x-a.x)*t,y=a.y+(b.y-a.y)*t,z=0}
                    local distance=range(at,base.core)
                    if distance<=40-laneMargin and outside(bounds,at,radius+laneMargin) and (not bestRange or distance<bestRange) then
                        best,bestRange={kind="roadside",baseId=base.id,point=at,core=pointCopy(base.core),roadEntry=pointCopy(at),
                            boundaries=bounds,radius=radius+laneMargin,roadWidth=width,label=b.street or "",warning="roadside_trunk_pending",
                            provisional=true,clearanceOnArrival=true},distance
                    end
                end
            end
        end
        return best
    end
    local function routeFor(plan,stop)
        local route,reason,native=Car.planRoadAccess(plan.vehicle,plan.departure,stop.point)
        if not route then return nil,reason end
        local roadLength=finite(route.roadLength)
        local entry=native and {x=finite(native.entryX),y=finite(native.entryY),z=0}
        local exit=native and {x=finite(native.exitX),y=finite(native.exitY),z=0}
        if not roadLength or roadLength<0 or roadLength>5000 or not entry or not entry.x or not entry.y
            or not exit or not exit.x or not exit.y then return nil,"road_access_unavailable" end
        stop.roadEntry=exit
        if stop.kind=="roadside" then stop.point=pointCopy(exit) end
        plan.route,plan.entry,plan.exit=route,entry,exit
        plan.access=range(plan.departure,entry)
        plan.distance=roadLength+plan.access+range(exit,stop.point)
        if plan.distance>5000 then return nil,"home_drive_too_far" end
        plan.fuelRequired=(plan.distance+30)*fuelRate(plan.script)*1.5
        if plan.fuel<plan.fuelRequired then return nil,"fuel_insufficient" end
        plan.requiredFuelPercent=plan.fuelCapacity and plan.fuelCapacity>0 and plan.fuelRequired/plan.fuelCapacity*100 or nil
        plan.estimatedHours=plan.distance/30000
        plan.homeStop=stop
        return plan
    end
    function Car.preflightField(records,vehicle,baseOrOptions)
        local plan,reason,review=fieldCheck(records,vehicle,fieldPlayer(baseOrOptions),true)
        if not plan then return nil,reason,review end
        local base=fieldBase(baseOrOptions)
        local function reject(why) review.canUse,review.reason=false,why return nil,why,review end
        if type(base)~="table" or type(base.id)~="string" or not pointCopy(base.core)
            or type(base.zones)~="table" or #base.zones>128 then return reject("home_stop_unavailable") end
        local bounds={}
        for _,zone in ipairs(base.zones) do if zone.kind=="area" then local clean=fieldBounds(zone) if clean then bounds[#bounds+1]=clean end end end
        if #bounds<1 then return reject("home_stop_unavailable") end
        if not SC.ExpeditionRoute or not SC.ExpeditionRoute.planFromPoint then return reject("road_routing_unavailable") end
        local radius=shapeRadius(vehicle)
        if not radius then return reject("parking_footprint_unreadable") end
        local stop
        for _,zone in ipairs(base.zones) do
            if zone.kind=="parking" and SC.BaseLife.parkingZoneValid(zone,base.zones) and rectangleCopy(zone) then
                for _,target in ipairs(bayTargets(zone)) do
                    local clear,why=targetBayClear(vehicle,zone,target)
                    if clear or why=="parking_not_loaded" then
                        stop={kind="parking",baseId=base.id,point=target,core=pointCopy(base.core),boundaries=bounds,
                            zoneId=zone.id,parking=rectangleCopy(zone),label=zone.name or zone.id,provisional=true,clearanceOnArrival=true}
                        break
                    end
                end
                if stop then break end
            end
        end
        if not stop then
            local route,why=SC.ExpeditionRoute.planFromPoint(plan.departure,base.core)
            if not route then return reject(why or "home_stop_unavailable") end
            if not finite(route.roadLength) or route.roadLength>5000 then return reject("home_drive_too_far") end
            stop=mappedRoadside(route,base,bounds,radius)
            if not stop then return reject("home_stop_unavailable") end
        end
        local accepted,why=routeFor(plan,stop)
        if not accepted then return reject(why) end
        if not Car.validFieldStop(stop,{id=base.id,core=base.core}) then return reject("home_stop_unavailable") end
        for _,key in ipairs({"homeStop","fuelRequired","requiredFuelPercent","distance","estimatedHours"}) do review[key]=plan[key] end
        review.fingerprint=Car.fieldFingerprint(vehicle,records,fieldPlayer(baseOrOptions))
        plan.fingerprint,plan.fieldBaseFingerprint=review.fingerprint,baseFingerprint(base)
        return plan,nil,review
    end
    function Car.prepareField(records,vehicle,baseOrOptions,options)
        local plan,reason,review
        local cached=type(options)=="table" and options.reviewedPlan
        if cached then
            local fresh
            fresh,reason,review=fieldCheck(records,vehicle,fieldPlayer(baseOrOptions),true)
            if not fresh then return nil,reason,review end
            local base=fieldBase(baseOrOptions)
            local fingerprint=Car.fieldFingerprint(vehicle,records,fieldPlayer(baseOrOptions))
            if cached.vehicle~=vehicle or cached.fingerprint~=fingerprint or options.fingerprint and options.fingerprint~=fingerprint
                or cached.fieldBaseFingerprint~=baseFingerprint(base) or not Car.validFieldStop(cached.homeStop,base)
                or not finite(cached.fuelRequired) or fresh.fuel<cached.fuelRequired then return nil,"home_review_changed",review end
            plan={}
            for key,value in pairs(cached) do plan[key]=value end
            plan.records,plan.leaderId=records,records[1].id
            plan.seats=fresh.seats
            plan.homeStop=Car.copyFieldStop(cached.homeStop,base)
        else plan,reason,review=Car.preflightField(records,vehicle,baseOrOptions) end
        if not plan then return nil,reason,review end
        local held=physicalKey(records,vehicle)
        local target=SC.GameplayUtil.inventory(records[1].actor)
        local okay,source=call(held and held.item,"getContainer")
        if not held or not okay or not source or not target then return nil,"key_owner_unavailable",review end
        if source~=target and (not SC.GameplayUtil.transferItemVerified
            or SC.GameplayUtil.transferItemVerified(source,target,held.item)~=true) then return nil,"key_transfer_failed",review end
        if not SC.Driving.hasKey(records[1].actor,vehicle) then return nil,"key_transfer_unverified",review end
        plan.keyHolderId,plan.keyHolderName=records[1].id,nameOf(records[1])
        return plan,nil,review
    end
    function Car.fieldParkingCurrent(trip)
        local stop=Car.copyFieldStop(trip and trip.homeStop)
        if not stop then return false end
        local base=fieldBase()
        if not base or not Car.validFieldStop(stop,base) then return false end
        if stop.kind=="roadside" then
            local current={}
            for _,zone in ipairs(base.zones or {}) do if zone.kind=="area" then local area=fieldBounds(zone) if area then current[#current+1]=area end end end
            return #current>0 and outside(current,stop.point,stop.radius)
        end
        return trip.parkingZoneId==stop.zoneId and sameParkingArea(Car.areaById(stop.zoneId),stop.parking)
    end
    function Car.fieldStopClear(mission,trip,vehicle)
        if not Car.fieldParkingCurrent(trip) then return false,"home_parking_changed" end
        local stop=trip.homeStop local seats={}
        for _,member in ipairs(mission.roster or {}) do if travelMember(mission,member) then seats[member.id]=trip.seats[member.id] end end
        if stop.kind=="parking" then return Car.fitsParking(vehicle,Car.areaById(stop.zoneId),seats) end
        local stationary,why=SC.Vehicle.isStationary(vehicle)
        if not stationary then return false,why or "parking_not_stationary" end
        local at,poly=point(vehicle),Car.footprint(vehicle)
        if not at or not poly or range(at,stop.point)>5 or range(at,stop.core)>40 then return false,"roadside_stop_not_reached" end
        local minX,minY,maxX,maxY=30000,30000,0,0
        for index=1,4 do
            local x,y=finite(poly["x"..index]),finite(poly["y"..index])
            if not x or not y then return false,"parking_footprint_unreadable" end
            minX,minY,maxX,maxY=math.min(minX,x),math.min(minY,y),math.max(maxX,x),math.max(maxY,y)
        end
        for _,area in ipairs(stop.boundaries) do
            if minX<area.x2+1 and maxX>=area.x1 and minY<area.y2+1 and maxY>=area.y1 then return false,"roadside_inside_camp" end
        end
        local clear,reason=targetBayClear(vehicle,{x1=math.floor(minX),y1=math.floor(minY),x2=math.floor(maxX),y2=math.floor(maxY),z=0},at)
        if not clear then return false,reason end
        for _,seat in pairs(seats) do
            local exits=SC.Vehicle.safeExitSquares and SC.Vehicle.safeExitSquares(vehicle,seat)
            if not exits or #exits<1 then return false,"parking_exit_blocked" end
        end
        return true
    end
    local function radioHoldCar(mission, trip)
        if not trip or not trip.field or trip.leg ~= "home"
            or type(trip.seats) ~= "table" or type(mission.members) ~= "table"
            or type(mission.roster) ~= "table" or not mission.leader or not mission.leader.actor
            or trip.state == "abandoned" or trip.state == "home_wait" then
            return nil, "home_car_trip_invalid"
        end
        local car = carLoaded(trip)
        if not car then return nil, "car_not_loaded" end
        if trip.radioHoldCar and trip.radioHoldCar ~= car then return nil, "car_identity_changed" end
        local scriptOkay, script = call(car, "getScriptName")
        if not scriptOkay or script ~= trip.script then return nil, "car_identity_changed" end
        local owned, reason = unloadOwnership(mission, trip, car)
        if not owned then return nil, reason end
        for _, member in ipairs(mission.roster or {}) do
            if travelMember(mission, member) then
                if not member.actor or not mission.members[member.actor]
                    or not SC.Actor.isCompanion(member.actor) then return nil, "restart_team_unavailable" end
                if SC.Registry and SC.Registry.byId then
                    local registered = SC.Registry.byId(member.id)
                    if not registered or registered.actor ~= member.actor then return nil, "restart_team_unavailable" end
                end
                local deadOkay, dead = call(member.actor, "isDead")
                if not deadOkay or dead ~= false then return nil, "restart_team_unfit" end
                local seat = trip.seats[member.id]
                local installedOkay, installed = call(car, "isSeatInstalled", seat)
                if not installedOkay or installed ~= true then return nil, "seat_unavailable" end
                local seated, current, actualSeat = SC.Vehicle.isNativeSeated(member.actor)
                if seated and (current ~= car or actualSeat ~= seat)
                    or not seated and current ~= nil then return nil, "wrong_vehicle_or_seat" end
            end
        end
        return car
    end

    -- Unlike recall, Hold never unloads or abandons the chosen car. The old
    -- managed job is stopped, not kept as resumable native motion authority.
    function Car.holdHome(mission, now)
        local trip = mission and mission.scout and mission.scout.vehicle
        local leader = mission and mission.leader
        local actor = leader and leader.actor
        -- Brake a proven owned job before rejecting a damaged seat/crew
        -- context. Identity failures must not stop somebody else's car.
        if trip and trip.field and trip.leg == "home" and actor
            and type(mission.members) == "table" and type(trip.seats) == "table"
            and mission.members[actor] and trip.seats[leader.id] == 0
            and SC.Registry and SC.Registry.byId and SC.Actor.isCompanion(actor)
            and SC.Driving._stopOwnedVehicle then
            local registered = SC.Registry.byId(leader.id)
            local currentCar = carLoaded(trip)
            local aboard, nativeCar, nativeSeat = SC.Vehicle.isNativeSeated(actor)
            local identityOkay, sqlId = call(currentCar, "getSqlId")
            if registered and registered.actor == actor and currentCar
                and identityOkay and sqlId == trip.sqlId and aboard
                and nativeCar == currentCar and nativeSeat == 0
                and (not trip.radioHoldCar or trip.radioHoldCar == currentCar) then
                local stopped, why = SC.Driving._stopOwnedVehicle(actor, currentCar, "home_radio_hold")
                if stopped == true or why ~= "drive_not_owned" and why ~= "drive_owner_mismatch" then
                    trip.radioResumeState = trip.radioResumeState
                        or (trip.state == "held" and trip.resumeState or trip.state)
                    trip.radioHoldCar = currentCar
                end
                if stopped ~= true and why ~= "drive_not_owned" then return false, why end
            end
        end
        local car, reason = radioHoldCar(mission, trip)
        if not car then return false, reason end
        trip.radioResumeState = trip.radioResumeState
            or (trip.state == "held" and trip.resumeState or trip.state)
        trip.radioHoldCar = car
        leader = mission.leader and mission.leader.actor
        local seated, current, seat
        if leader then seated, current, seat = SC.Vehicle.isNativeSeated(leader) end
        if leader and (seated and current == car and seat == 0
            or SC.Driving.isDriving(leader)) then
            local stopped, why = SC.Driving.release(leader, "home_radio_hold")
            if stopped ~= true then return false, why or "drive_stop_pending" end
        end
        for _, member in ipairs(mission.roster) do
            if travelMember(mission, member) then
                local aboard = SC.Vehicle.isNativeSeated(member.actor)
                if not aboard then
                    if SC.Vehicle.cancelTransaction then
                        local cancelled, why = SC.Vehicle.cancelTransaction(member.actor, "home_radio_hold")
                        if cancelled ~= true then return false, why or "vehicle_stop_pending" end
                    end
                    if SC.Navigation and SC.Navigation.cancel then SC.Navigation.cancel(member.actor, "home_radio_hold") end
                    if not SC.Actor.stop then return false, "home_car_stop_unavailable" end
                    local stopped, why = SC.Actor.stop(member.actor)
                    if stopped ~= true then return false, why or "home_car_stop_pending" end
                end
            end
        end
        local stationary, why = SC.Vehicle.isStationary(car)
        if not stationary then return false, why or "car_not_stopped" end
        local stopped, stopReason = stopOwnedEngine(mission, trip, car, now)
        if not stopped then return false, stopReason end
        if (trip.radioResumeState == "driving_home" or trip.radioResumeState == "parking_home")
            and not teamSeated(mission, trip, car) then return false, "team_not_seated" end
        return true, "home_radio_holding"
    end

    function Car.resumeHome(mission, now)
        local trip = mission and mission.scout and mission.scout.vehicle
        if not trip or not trip.radioResumeState then return false, "home_car_not_held" end
        local held, reason = Car.holdHome(mission, now)
        if not held then return false, reason end
        local car, state = trip.radioHoldCar, trip.radioResumeState
        if state == "interrupted_by_load" then
            local ready, why = resumeReady(mission, trip, car)
            if not ready then return false, why end
            local transferred, transferReason = Car.ensureDriverKey(mission.roster, car)
            if not transferred then return false, transferReason end
            state = "boarding_home"
        elseif state == "driving_home" or state == "parking_home" then
            if state == "parking_home" and Car.fieldStopClear(mission, trip, car) then
                state = "unloading_home"
            else
                local ready, why, roadEntry = departReady(mission, trip, car)
                if not ready then return false, why end
                local goal = trip.homeRoadEntry or trip.departure
                local started, startReason = SC.Driving.drive(mission.leader.actor, goal, {
                    speedKmh = 30, stopShortTiles = 0, roadAccessEntry = roadEntry,
                    roadAccessExit = trip.homeRoadEntry and { entry = trip.homeRoadEntry, bay = trip.departure } or nil,
                })
                if started ~= true then
                    -- A rejected start can still own a native starting job.
                    -- Keep the hold and request its verified stop before retry.
                    local stopped, stopReason = SC.Driving.release(mission.leader.actor, "home_radio_resume_failed")
                    return false, stopped == true and startReason or stopReason or "drive_stop_pending"
                end
                state, trip.engineStopped = "driving_home", false
            end
        elseif state ~= "walking_to_car" and state ~= "boarding_home"
            and state ~= "unloading_home" and state ~= "fallback_unloading"
            and state ~= "boarding_rollback" then return false, "home_car_trip_invalid" end
        trip.state, mission.scout.phase = state, state
        trip.radioResumeState, trip.radioHoldCar = nil, nil
        trip.boardStartedAt, trip.approachStartedAt, trip.parkingAligning = now, nil, nil
        trip.recoveryAt, trip.nextRecoveryCheckAt = nil, nil
        return true, "home_radio_resumed"
    end

    function Car.homeArrivalReady(mission)
        local trip=mission and mission.scout and mission.scout.vehicle
        if not trip or not trip.field then return false,"home_car_trip_invalid" end
        if not wholeTeamOnFoot(mission) then return false,"home_car_unloading" end
        local vehicle=carLoaded(trip)
        if trip.state=="abandoned" and trip.engineStopped and not vehicle then return true end
        if trip.state~="home_wait" and trip.state~="abandoned" then return false,"home_car_unsettled" end
        if not vehicle then return false,"car_not_loaded" end
        local stopped,why=SC.Vehicle.isStationary(vehicle)
        if not stopped then return false,why or "car_moving" end
        local runningOkay,running=call(vehicle,"isEngineRunning")
        local startingOkay,starting=call(vehicle,"isEngineStarted")
        if not runningOkay or not startingOkay or running~=false or starting~=false then return false,"engine_shutdown_pending" end
        if trip.state=="home_wait" then return Car.fieldStopClear(mission,trip,vehicle) end
        return trip.engineStopped==true,trip.engineStopped and nil or "home_car_unsettled"
    end
    function Car.cancelField(mission,now)
        local trip=mission and mission.scout and mission.scout.vehicle
        if not trip or not trip.field then return false,"home_car_trip_invalid" end
        local vehicle=carLoaded(trip)
        if not vehicle then
            if trip.state=="abandoned" and trip.engineStopped and wholeTeamOnFoot(mission) then return true end
            return false,"car_not_loaded"
        end
        local stopped,reason=stopAndUnload(mission,trip,vehicle,now)
        if not stopped then return false,reason end
        return abandonToWalking(mission,trip,vehicle)
    end
    function Car.fieldDescriptor(plan,camp)
        local stop=type(plan)=="table" and Car.copyFieldStop(plan.homeStop,camp)
        if not stop or not plan.field then return nil,"home_stop_invalid" end
        return Car.copyDescriptor({field=true,homeStop=stop,state="walking_to_car",leg="home",sqlId=plan.sqlId,script=plan.script,
            seats=plan.seats,parkingZoneId=stop.zoneId or "field:roadside",parking=stop.parking or {
                x1=math.floor(stop.point.x)-1,y1=math.floor(stop.point.y)-1,x2=math.floor(stop.point.x)+1,y2=math.floor(stop.point.y)+1,z=0},
            departure=stop.point,homeRoadEntry=stop.roadEntry,home=camp.core,siteStop=stop.point,
            position=plan.departure,departureFuel=plan.fuel,departureHeading=plan.heading},
            plan.records or plan.roster or {},plan.leaderId)
    end
end

return Car
