-- SPDX-License-Identifier: MIT
-- Read-only expedition car selection and dispatch checks. No car or actor is
-- moved during review; dispatch repeats these checks against live objects.
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.ExpeditionCar = SC.ExpeditionCar or {}
local Car = SC.ExpeditionCar

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

function Car.candidates(zone)
    local result = {}
    if zone == nil or not SC.Vehicle or not SC.Vehicle.loadedVehicles then
        return result
    end
    for _, vehicle in ipairs(SC.Vehicle.loadedVehicles()) do
        local at = point(vehicle)
        if contains(zone, at) then
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
                    seats = okSeats and tonumber(seats) or 0,
                    fuel = amountOk and finite(fuel) or nil,
                    point = at,
                }
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

-- Step 2 initially supports a short, clear, forward driveway. Survey the
-- full car-width strip in the loaded cell; a human-sized path is insufficient
-- because its neighbours can be walls, fences or a closed garage opening.
function Car.accessBetween(vehicle, at, entry)
    if not at or type(entry) ~= "table" then
        return false, "road_access_unavailable"
    end
    local dx, dy = entry.x - at.x, entry.y - at.y
    local length = math.sqrt(dx * dx + dy * dy)
    if length > 15 then return false, "road_access_too_far" end
    if length < 0.5 then return true end
    if type(getCell) ~= "function" then return false, "road_access_not_loaded" end
    local okay, cell = pcall(getCell)
    if not okay or cell == nil then return false, "road_access_not_loaded" end
    local px, py = -dy / length, dx / length
    local ux, uy = dx / length, dy / length
    local steps = math.ceil(length * 2)
    for _, offset in ipairs({ -1.25, 0, 1.25 }) do
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
            if not solidOk or not transOk or solid or trans then
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

function Car.preflight(records, zoneId, sqlId, destination)
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
    local seatMap = {}
    for index, record in ipairs(records) do
        local seat = index - 1
        local installedOk, installed = call(vehicle, "isSeatInstalled", seat)
        local occupantOk, occupant = call(vehicle, "getCharacter", seat)
        if not installedOk or installed ~= true or not occupantOk
            or occupant ~= nil then return nil, "seat_unavailable" end
        if record.id == nil or record.actor == nil then
            return nil, "team_unavailable"
        end
        seatMap[record.id] = seat
        local doors, _, doorReason = SC.Vehicle.boardingSquares(
            record.actor, vehicle, seat, seat == 0)
        if not doors or #doors < 1 then
            return nil, doorReason or "door_inaccessible"
        end
    end
    for seat = #records, count - 1 do
        local occupantOk, occupant = call(vehicle, "getCharacter", seat)
        if not occupantOk or occupant ~= nil then
            return nil, "car_has_other_occupants"
        end
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
    local route, routeReason, native = SC.ExpeditionRoute.planFromPoint(
        at, destination)
    if not route then return nil, routeReason end
    local entryX = native and finite(native.entryX)
    local entryY = native and finite(native.entryY)
    local exitX = native and finite(native.exitX)
    local exitY = native and finite(native.exitY)
    if not entryX or not entryY or not exitX or not exitY then
        return nil, "road_access_unavailable"
    end
    local access = math.sqrt((at.x - entryX)^2 + (at.y - entryY)^2)
    if access > 15 then return nil, "road_access_too_far" end
    local accessReady, accessReason = Car.accessReady(vehicle,
        { x = entryX, y = entryY, z = 0 })
    if not accessReady then return nil, accessReason end
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

function Car.boardMember(actor, order, snapshot)
    local car, seat = order.car, order.seat
    local seated, current, actualSeat = SC.Vehicle.isNativeSeated(actor)
    if seated then
        if current == car and actualSeat == seat then return true, "already_boarded" end
        return false, "wrong_vehicle_or_seat"
    end
    local began, beginReason = SC.Vehicle.beginBoarding(actor, car, seat,
        { driverSeat = seat == 0, playerCommand = order.hotwire == true })
    if began == nil then return false, beginReason end
    local prepared, reason = SC.Vehicle.preflightBoard(actor, car, seat,
        seat == 0)
    if prepared then
        local options = { driverSeat = seat == 0,
            playerCommand = order.hotwire == true,
            allowVirtualSeat = false, preflight = prepared }
        if seat == 0 then return SC.Vehicle.boardDriver(actor, car, options) end
        return SC.Vehicle.board(actor, car, seat, options)
    end
    if reason ~= "companion is not at the passenger door" then
        SC.Vehicle.failTransaction(actor, "expedition_board_preflight_failed",
            { reason = reason })
        return false, reason
    end
    local squares, _, squareReason = SC.Vehicle.boardingSquares(
        actor, car, seat, seat == 0)
    if not squares then
        SC.Vehicle.failTransaction(actor, "expedition_door_unavailable",
            { reason = squareReason })
        return false, squareReason
    end
    if not SC.Navigation or not SC.Navigation.requestAny then
        return false, "navigation_unavailable"
    end
    local x, y = SC.GameplayUtil.position(actor)
    local sx, sy = SC.GameplayUtil.position(squares[1])
    local gap = x and sx and math.sqrt((x - sx)^2 + (y - sy)^2) or 0
    local accepted, moveReason = SC.Navigation.requestAny(actor, squares,
        gap > 8 and "run" or "walk", {
            action = "approach_vehicle", vehicle = car, seat = seat,
            snapshot = snapshot, desiredDistance = 0,
            arrivalDistance = 0.15, continuousApproach = true,
            movementPriority = 30,
            supervisorToken = began.supervisorToken,
        })
    if not accepted then
        SC.Vehicle.failTransaction(actor, "expedition_door_approach_failed",
            { reason = moveReason })
    end
    return accepted, moveReason
end

local function sameParkingArea(zone, saved)
    return zone and saved and zone.z == saved.z
        and zone.x1 == saved.x1 and zone.y1 == saved.y1
        and zone.x2 == saved.x2 and zone.y2 == saved.y2
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
    if trip.leg == "home" and not sameParkingArea(
        Car.areaById(trip.parkingZoneId), trip.parking) then
        return false, "home_parking_changed"
    end
    local goal = trip.leg == "home" and trip.departure or trip.siteStop
    local at = point(car)
    if not at then return false, "car_position_unavailable" end
    local route, routeReason, native = SC.ExpeditionRoute.planFromPoint(
        at, goal, true)
    if not route then return false, routeReason or "no_route" end
    local entry = native and { x = finite(native.entryX),
        y = finite(native.entryY), z = 0 }
    if not entry or not entry.x or not entry.y then
        return false, "road_access_unavailable"
    end
    local access, why = Car.accessBetween(car, at, entry)
    if not access then return false, why end
    local tankOk, tank = call(car, "getPartById", "GasTank")
    local fuelOk, fuel = false, nil
    if tankOk and tank then fuelOk, fuel = call(tank,
        "getContainerContentAmount") end
    fuel = fuelOk and finite(fuel) or nil
    if fuel == nil then return false, "fuel_unreadable" end
    local rate = fuelRate(trip.script)
    local required = (finite(route.roadLength) or 0) * rate
    if trip.leg == "outbound" then required = required * 2 end
    required = (required + 30 * rate) * 1.5
    if fuel < required then return false, "fuel_insufficient" end
    return true
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

local function abandonToWalking(mission, trip, car)
    local scout = mission.scout
    local leader = mission.leader and mission.leader.actor
    local x, y, z
    if leader then x, y, z = SC.GameplayUtil.position(leader) end
    if not x or not y or not z then return false, "leader_position_unavailable" end
    trip.state = "abandoned"
    trip.abandonedAt = car and point(car) or trip.position
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

local function stopAndUnload(mission, trip, car)
    local leader = mission.leader and mission.leader.actor
    if leader and SC.Driving.isDriving(leader) then
        local stopped, why = SC.Driving.release(leader, "expedition_unload")
        if not stopped then return false, why or "drive_stop_pending" end
    end
    local stationary, why = SC.Vehicle.isStationary(car)
    if not stationary then return false, why or "car_not_stopped" end
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
    if #seated > 0 then
        local stationary, why = SC.Vehicle.isStationary(car)
        if not stationary then return false, why or "car_not_stopped" end
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
    if scout.search then
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
    if trip.state == "held" or trip.state == "interrupted_by_load" then
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
    if trip.leg == "home" and not sameParkingArea(zone, trip.parking) then
        return false, "home_parking_changed"
    end
    local goal = trip.leg == "home" and trip.departure or trip.siteStop
    local route, routeReason, native = SC.ExpeditionRoute.planFromPoint(
        at, goal, true)
    if not route then return false, routeReason end
    local entryX = native and finite(native.entryX)
    local entryY = native and finite(native.entryY)
    if not entryX or not entryY then
        return false, "road_access_unavailable"
    end
    local access, accessReason = Car.accessBetween(car, at,
        { x = entryX, y = entryY, z = 0 })
    if not access then return false, accessReason end
    local tankOk, tank = call(car, "getPartById", "GasTank")
    local fuelOk, fuel = false, nil
    if tankOk and tank then fuelOk, fuel = call(tank, "getContainerContentAmount") end
    fuel = fuelOk and finite(fuel) or nil
    if fuel == nil then return false, "fuel_unreadable" end
    local rate = fuelRate(trip.script)
    local distance = route.roadLength or 0
    if trip.leg == "outbound" then
        distance = distance + math.sqrt((trip.departure.x - trip.siteStop.x)^2
            + (trip.departure.y - trip.siteStop.y)^2)
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

function Car.pulse(mission, now, worldHour)
    local scout = mission and mission.scout
    local trip = scout and scout.vehicle
    if not trip or trip.state == "abandoned" then return false end
    if trip.state == "parked_at_site" then
        if scout.phase ~= "inbound" then return false end
        trip.state, trip.leg = "returning_to_car", "home"
        scout.phase = "returning_to_car"
        trip.boardStartedAt = now
        return true
    end
    if trip.state == "held" then
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
        trip.missingSince = trip.missingSince or now
        if now - trip.missingSince > 30000 then
            hold(trip, "car_not_loaded")
        end
        return true
    end
    trip.missingSince = nil
    if trip.state == "walking_to_car" then
        local transferred, why = Car.ensureDriverKey(mission.roster, car)
        if not transferred then hold(trip, why) return true end
        trip.state = "boarding_out"
        scout.phase = "boarding_out"
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
                else
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
        if not teamSeated(mission, trip, car) then
            if now - (trip.boardStartedAt or now) > 120000 then
                trip.state = "boarding_rollback"
                trip.blocker = "boarding_deadline"
            end
            return true
        end
        local ready, why = departReady(mission, trip, car)
        if not ready then
            trip.state, trip.blocker = "boarding_rollback", why
            return true
        end
        local goal = trip.leg == "home" and trip.departure or trip.siteStop
        local started, reason = SC.Driving.drive(mission.leader.actor,
            goal, { speedKmh = 10 })
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
            trip.state, trip.blocker = "boarding_rollback", reason
            return true
        end
        trip.state = trip.leg == "home" and "driving_home" or "driving_out"
        scout.phase = trip.state
        return true
    end
    if trip.state == "driving_out" or trip.state == "driving_home" then
        local status = SC.Driving.jobStatus(mission.leader.actor)
        if status and status.result == "arrived" then
            trip.state = trip.leg == "home" and "parking_home"
                or "unloading_site"
            scout.phase = trip.state
        elseif status and status.result == "failed" then
            trip.blocker = status.reason
            if status.reason == "streaming_stalled" then
                hold(trip, "streaming_stalled")
            else
                trip.state = "fallback_unloading"
                scout.phase = trip.state
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
                hold(trip, "drive_status_unavailable")
            end
        else
            trip.statusMissingSince = nil
        end
        return true
    end
    if trip.state == "parking_home" then
        local zone = Car.areaById(trip.parkingZoneId)
        if not sameParkingArea(zone, trip.parking) then
            hold(trip, "home_parking_changed")
        else
            local fit, reason = Car.fitsParking(car, zone, trip.seats)
            -- A valid parking area accepts either car orientation. Road
            -- travel normally brings the car home facing the opposite way;
            -- requiring the departure heading would force an unnecessary
            -- turn inside the marked bay.
            if fit then
                trip.state, scout.phase = "unloading_home", "unloading_home"
            elseif trip.approachStartedAt then
                local status = SC.Driving.jobStatus(mission.leader.actor)
                if status and status.result == "failed" then
                    hold(trip, status.reason or "parking_approach_failed")
                elseif status and status.result == "arrived" then
                    if trip.approachStage == "road" then
                        -- Native road arrival may stop a few tiles short. First
                        -- settle at the verified road attachment, then run the
                        -- separately checked driveway approach next pulse.
                        trip.approachStage, trip.approachStartedAt = nil, nil
                    else
                        hold(trip, reason or "parking_footprint_outside_area")
                    end
                elseif now - trip.approachStartedAt > 30000 then
                    SC.Driving.release(mission.leader.actor, "parking_timeout")
                    hold(trip, "parking_approach_timeout")
                end
            else
                local at = point(car)
                local gap = at and math.sqrt((at.x - trip.departure.x)^2
                    + (at.y - trip.departure.y)^2) or math.huge
                if gap > 15 then
                    local status = SC.Driving.jobStatus(mission.leader.actor)
                    local road = status and status.roadGoal
                    local roadGap = road and at and math.sqrt(
                        (at.x - road.x)^2 + (at.y - road.y)^2) or math.huge
                    if roadGap > 6 then hold(trip, "parking_road_end_unavailable")
                    else
                        local started, why = SC.Driving.approach(
                            mission.leader.actor, road, 30000)
                        if started then
                            trip.approachStage, trip.approachStartedAt = "road", now
                        else hold(trip, why) end
                    end
                else
                    local clear, why = targetBayClear(car, zone, trip.departure)
                    if clear then clear, why = Car.accessBetween(car,
                        at, trip.departure) end
                    if not clear then hold(trip, why)
                    else
                        local started, startReason = SC.Driving.approach(
                            mission.leader.actor, trip.departure, 30000)
                        if started then
                            trip.approachStage, trip.approachStartedAt = "bay", now
                        else hold(trip, startReason) end
                    end
                end
            end
        end
        return true
    end
    if trip.state == "unloading_site" or trip.state == "unloading_home"
        or trip.state == "boarding_rollback"
        or trip.state == "fallback_unloading" then
        local unloaded, why = stopAndUnload(mission, trip, car)
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
            trip.state, scout.phase = "home_wait", "awaiting_player"
        else
            local abandoned, abandonReason = abandonToWalking(
                mission, trip, car)
            if not abandoned then trip.blocker = abandonReason end
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
    local resumeState = value.resumeState
    if state == "held" and not validStates[resumeState] then
        return nil, "vehicle_hold_invalid"
    end
    local result = {
        state = state, leg = value.leg, sqlId = value.sqlId,
        script = value.script, seats = seats,
        parkingZoneId = value.parkingZoneId, parking = parking,
        departure = departure, home = home, siteStop = siteStop,
        position = pointCopy(value.position),
        sitePoint = pointCopy(value.sitePoint),
        abandonedAt = pointCopy(value.abandonedAt),
        departureFuel = fuel,
        departureHeading = heading,
        resumeState = state == "held" and resumeState or nil,
        returnRequested = value.returnRequested == true,
        blocker = type(value.blocker) == "string"
            and value.blocker:sub(1, 128) or nil,
    }
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
    if interruptedStates[result.state] then
        result.state = "interrupted_by_load"
    end
    return result
end

return Car
