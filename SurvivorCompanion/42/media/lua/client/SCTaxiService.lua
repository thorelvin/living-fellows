-- SPDX-License-Identifier: MIT
-- Markus's physical taxi visit. The car and its native containers remain the
-- source of truth; this journal only resumes a particular booking/driver/car.
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.TaxiService = SC.TaxiService or {}
local Service = SC.TaxiService

local visit, driver, spawnTicket, nextSearchAt = nil, nil, nil, 0
local persistentDriverId
local resumePending = false
local resumeDriverAt = 0
local nextDepartureAt, retiringCar = 0, nil
local destinationReminderAt = nil
local lastTraceSignature = nil
local lastDefenseTrace = nil
local serviceRounds, driverGun = 15, nil
local PICKUP_LINES = {
    "Markus Sloane. Your ride's here. Mind the paint; it's mostly blood.",
    "Get in. The meter's broken, but my prices aren't.",
    "Taxi! Yes, the sign still works. No, I won't explain why.",
}
local DEPART_LINES = {
    "First ride is on me. Call it customer acquisition.",
    "Keep your hands inside. The dead never learned to signal.",
    "Gold accepted. Complaints referred to the dead.",
}
local DESTINATION_REMINDERS = {
    "Show me where we're going on the map. I've got places to be.",
    "Point to a road on the map, will you? I got places to be.",
    "Where to? Show me on the map. I've got places to be.",
}
local function U() return SC.GameplayUtil end
local function call(object, method, ...)
    if not object then return nil end
    local value = U().call(object, method, ...)
    return value
end
local function now()
    return U() and U().nowMs and U().nowMs() or 0
end
local function finite(n)
    return type(n) == "number" and n == n and n ~= math.huge
        and n ~= -math.huge
end
local function point(value)
    local x, y, z = U().position(value)
    if not finite(x) or not finite(y) or not finite(z) then return nil end
    return { x = x, y = y, z = z }
end
local function copyPoint(value)
    return value and { x = value.x, y = value.y, z = value.z } or nil
end

local function distanceSquared(a, b)
    if not a or not b then return 0 end
    return (a.x - b.x)^2 + (a.y - b.y)^2
end
local function player()
    return type(getSpecificPlayer) == "function" and getSpecificPlayer(0) or nil
end
local function book()
    return SC.TaxiBooking and SC.TaxiBooking.current() or nil
end
local function cab()
    if not SC.TaxiCab then return nil, "cab_ledger_unavailable" end
    local okay, car = SC.TaxiCab.recover()
    if not okay then return nil, car end
    return car
end
local function sameBooking()
    local current = book()
    return visit and current and current.generation == visit.bookingGeneration
end
function Service.isDriver(actor)
    local data = call(actor, "getModData")
    local owned = SC.TaxiCab and SC.TaxiCab.current()
    return type(data) == "table" and owned ~= nil
        and type(data.LF_MarkusDriver) == "string"
        and data.LF_MarkusDriver == owned.ownershipToken
end

-- A waiting cab has released its driving lease. Only that stopped, owned cab
-- may let Markus use the normal seated firearm path through the driver window.
function Service.canDefend(actor, vehicle)
    if not visit or visit.phase ~= "waiting_board"
        or not Service.isDriver(actor) or not SC.Driving
        or SC.Driving.isDriver(actor) ~= true then return false end
    local car = vehicle or call(actor, "getVehicle")
    if not car or call(actor, "getVehicle") ~= car
        or SC.TaxiCab.matches(car) ~= true
        or call(player(), "getVehicle") == car
        or SC.Vehicle.isStationary(car) ~= true then return false end
    local speed = tonumber(call(car, "getCurrentSpeedKmHour"))
    return speed ~= nil and math.abs(speed) <= 0.5
end

local function markedGun(actor)
    if driverGun and call(driverGun, "getContainer") == call(actor, "getInventory") then
        return driverGun
    end
    driverGun = nil
    local inventory = call(actor, "getInventory")
    local items = inventory and call(inventory, "getItems")
    local count = tonumber(call(items, "size")) or 0
    for index = 0, math.min(count, 64) - 1 do
        local item = call(items, "get", index)
        local data = item and call(item, "getModData")
        if type(data) == "table" and data.LF_MarkusServiceGun == true
            and call(item, "getFullType") == "Base.Pistol" then
            driverGun = item
            return item
        end
    end
    return nil
end

local function updateRounds(actor)
    local gun = actor and markedGun(actor)
    local count = gun and tonumber(call(gun, "getCurrentAmmoCount"))
    if count and count >= 0 then
        serviceRounds = math.min(serviceRounds, math.floor(count))
    end
    return gun
end

local function armDriver(actor)
    if not Service.canDefend(actor) then return false, "taxi_not_parked" end
    local data = call(actor, "getModData")
    if type(data) ~= "table" then return false, "driver_marker_missing" end
    local gun = updateRounds(actor)
    if not gun then
        if data.LF_MarkusArmed == true then return false, "driver_gun_missing" end
        local inventory = call(actor, "getInventory")
        gun = inventory and call(inventory, "AddItem", "Base.Pistol")
        if not gun then return false, "driver_gun_unavailable" end
        local gunData = call(gun, "getModData")
        if type(gunData) ~= "table" then return false, "driver_gun_marker_missing" end
        gunData.LF_MarkusServiceGun = true
        call(gun, "setContainsClip", true)
        call(gun, "setCurrentAmmoCount", serviceRounds)
        call(gun, "setRoundChambered", serviceRounds > 0)
        call(gun, "setJammed", false)
        data.LF_MarkusArmed = true
        driverGun = gun
    end
    if serviceRounds <= 0 then return false, "driver_out_of_ammo" end
    if call(actor, "getPrimaryHandItem") ~= gun then
        call(actor, "setPrimaryHandItem", gun)
        if call(actor, "getPrimaryHandItem") ~= gun then
            return false, "driver_gun_not_equipped"
        end
    end
    return true, "driver_armed"
end

function Service.pulseDefense(actor, human, runtime, current)
    if not Service.canDefend(actor) then return false, "taxi_service" end
    local armed, reason = armDriver(actor)
    if not armed then return false, reason end
    local door = call(call(actor, "getVehicle"), "getPassengerDoor", 0)
    local window = call(door, "findWindow")
    if not window then return false, "driver_window_unavailable" end
    runtime = type(runtime) == "table" and runtime or {}
    local utility = U()
    current = tonumber(current) or now()
    local snapshot = type(runtime.senses) == "table" and runtime.senses.current
        or runtime.snapshot
    if utility.isDue(actor, "taxi-perception", 500, current)
        and SC.Senses and type(SC.Senses.snapshot) == "function" then
        local safe, observed = utility.safeSubsystem("taxi-senses", actor,
            SC.Senses.snapshot, actor, human, runtime)
        if safe and type(observed) == "table" then snapshot = observed end
    end
    if type(snapshot) ~= "table" then return false, "taxi_perception_pending" end
    if SC.Senses and type(SC.Senses.refreshImmediate) == "function" then
        local safe, observed = utility.safeSubsystem("taxi-senses-reflex", actor,
            SC.Senses.refreshImmediate, actor, human, snapshot, runtime)
        if safe and type(observed) == "table" then snapshot = observed end
    end
    runtime.snapshot = snapshot
    if (tonumber(snapshot.threatCount) or #(snapshot.threats or {})) < 1 then
        return false, "taxi_no_threat"
    end
    if call(window, "isHittable") == true then
        if call(window, "isDestroyed") == true then
            return false, "driver_window_blocked"
        end
        call(window, "setOpen", true)
        call(call(actor, "getVehicle"), "transmitPartWindow", door)
        if call(window, "isHittable") == true then
            return false, "driver_window_closed"
        end
    end
    if not SC.Combat or type(SC.Combat.update) ~= "function" then
        return false, "taxi_combat_unavailable"
    end
    local handled, combatReason = SC.Combat.update(actor, human, runtime)
    updateRounds(actor)
    return handled, combatReason
end
local pulseDefense = Service.pulseDefense
function Service.pulseDefense(actor, human, runtime, current)
    local handled, reason = pulseDefense(actor, human, runtime, current)
    if reason ~= lastDefenseTrace then
        if reason ~= "taxi_service" and reason ~= "taxi_no_threat" then
            print("[SurvivorCompanion/taxi] defense " .. tostring(reason)
                .. " rounds=" .. tostring(serviceRounds))
        end
        lastDefenseTrace = reason
    end
    return handled, reason
end
local function recordDriver(actor)
    local id = SC.Registry and SC.Registry.idOf and SC.Registry.idOf(actor)
    if type(id) ~= "string" or id == "" then return false end
    local data = call(actor, "getModData")
    if type(data) ~= "table" then return false end
    data.LF_MarkusDriver = visit.cabToken
    if data.LF_MarkusDriver ~= visit.cabToken then return false end
    visit.driverId, driver = id, actor
    return true
end
local function findDriver()
    if driver and SC.Actor.isCompanion(driver)
        and call(driver, "getModData")
        and call(driver, "getModData").LF_MarkusDriver == visit.cabToken then
        return driver
    end
    driver = nil
    if not visit or not SC.Registry then return nil end
    local record = visit.driverId and SC.Registry.byId(visit.driverId) or nil
    local actor = record and record.actor
    local data = actor and call(actor, "getModData")
    if actor and SC.Actor.isCompanion(actor) and type(data) == "table"
        and data.LF_MarkusDriver == visit.cabToken then
        driver = actor
    end
    if driver then return driver end
    -- A save can land after native actor registration but before this visit
    -- records its id. Recover the one marked actor before considering a spawn.
    for _, candidate in ipairs(SC.Registry.snapshot() or {}) do
        local actor = candidate.actor
        local marker = actor and call(actor, "getModData")
        if actor and SC.Actor.isCompanion(actor)
            and type(marker) == "table"
            and marker.LF_MarkusDriver == visit.cabToken then
            visit.driverId, persistentDriverId = candidate.id, candidate.id
            driver = actor
            return actor
        end
    end
    return nil
end

-- Check a car-width strip in the loaded cell, including street furniture and
-- other vehicles. Never ask the native spawner to resolve an obstructed patch.
local function openPatch(x, y, radius)
    for dx = -radius, radius do
        for dy = -radius, radius do
            local tx, ty = math.floor(x + dx), math.floor(y + dy)
            local square = U().gridSquare(tx, ty, 0)
            local why
            if not square then why = "unloaded"
            elseif call(square, "isOutside") ~= true then why = "inside"
            elseif call(square, "getRoom") ~= nil then why = "room"
            elseif call(square, "isSolid") ~= false then why = "solid"
            elseif call(square, "isSolidTrans") ~= false then why = "solid_trans"
            elseif call(square, "getVehicleContainer") ~= nil then why = "vehicle"
            else
                local blocker = U().squareStaticBlocker(square)
                if blocker then why = "static_blocker" end
            end
            if why then return false, why .. "@" .. tx .. "," .. ty end
            local moving = call(square, "getMovingObjects")
            if moving and (tonumber(call(moving, "size")) or 0) > 0 then
                return false, "moving@" .. tx .. "," .. ty
            end
        end
    end
    return true
end
-- Engine line of sight can cover a long, straight street beyond the camera.
-- Materialization only needs to be outside every active player's viewport.
-- Check the entire cab footprint and a margin for its raised sprite.
local function outsideViews(x, y)
    if type(isoToScreenX) ~= "function"
        or type(isoToScreenY) ~= "function"
        or type(getPlayerScreenLeft) ~= "function"
        or type(getPlayerScreenTop) ~= "function"
        or type(getPlayerScreenWidth) ~= "function"
        or type(getPlayerScreenHeight) ~= "function" then return false end
    for index = 0, 3 do
        local observer = type(getSpecificPlayer) == "function"
            and getSpecificPlayer(index) or nil
        if observer then
            local okLeft, left = pcall(getPlayerScreenLeft, index)
            local okTop, top = pcall(getPlayerScreenTop, index)
            local okWidth, width = pcall(getPlayerScreenWidth, index)
            local okHeight, height = pcall(getPlayerScreenHeight, index)
            if not okLeft or not okTop or not okWidth or not okHeight
                or not finite(left) or not finite(top)
                or not finite(width) or not finite(height)
                or width <= 0 or height <= 0 then return false end
            local minX, minY, maxX, maxY
            for _, corner in ipairs({ { -4, -4 }, { -4, 4 },
                { 4, -4 }, { 4, 4 } }) do
                local okX, sx = pcall(isoToScreenX, index,
                    x + corner[1], y + corner[2], 0)
                local okY, sy = pcall(isoToScreenY, index,
                    x + corner[1], y + corner[2], 0)
                if not okX or not okY or not finite(sx) or not finite(sy) then
                    return false
                end
                minX, maxX = math.min(minX or sx, sx), math.max(maxX or sx, sx)
                minY, maxY = math.min(minY or sy, sy), math.max(maxY or sy, sy)
            end
            local margin = 120
            if maxX + margin >= left and minX - margin <= left + width
                and maxY + margin >= top and minY - margin <= top + height then
                return false
            end
        end
    end
    return true
end
local function roadZone(square)
    local zone = square and call(square, "getZone")
    if tostring(call(zone, "getType")) ~= "Nav" then return nil end
    local x, y = tonumber(call(zone, "getX")), tonumber(call(zone, "getY"))
    local w, h = tonumber(call(zone, "getWidth")), tonumber(call(zone, "getHeight"))
    if not x or not y or not w or not h then return nil end
    local horizontal = w >= h
    if math.max(w, h) < 55 or math.min(w, h) < 5
        or math.min(w, h) > 24 then return nil end
    return { x = x, y = y, w = w, h = h, horizontal = horizontal }
end
local function pickupRoute(from, pickup, reusedCab)
    local route, why, native = SC.ExpeditionRoute.planFromPoint(from,
        pickup, true)
    if not route then return false, why or "pickup_route_unavailable" end
    local entryX, entryY = native and tonumber(native.entryX),
        native and tonumber(native.entryY)
    local exitX, exitY = native and tonumber(native.exitX),
        native and tonumber(native.exitY)
    -- The street router may return a tiny route on a different nearby road.
    -- That route cannot take a saved cab to this pickup, regardless of how
    -- clear the map squares around the requested stop look.
    if not finite(entryX) or not finite(entryY)
        or (entryX - from.x)^2 + (entryY - from.y)^2 > 144 then
        return false, "pickup_road_entry_far"
    end
    if not finite(exitX) or not finite(exitY)
        or (exitX - pickup.x)^2 + (exitY - pickup.y)^2 > 64 then
        return false, "pickup_road_exit_far"
    end
    local length = tonumber(route.roadLength)
    if not finite(length) or length > (reusedCab and 1000 or 120) then
        return false, "pickup_route_too_long"
    end
    return true
end
local function siteForZone(zone, origin, actor, parkedCar)
    local along = zone.horizontal and origin.x or origin.y
    local low = (zone.horizontal and zone.x or zone.y) + 8
    local high = (zone.horizontal and zone.x + zone.w or zone.y + zone.h) - 8
    if low >= high then return nil, "zone_too_short" end
    local cross = zone.horizontal and zone.y + zone.h / 2
        or zone.x + zone.w / 2
    local rejected = {}
    for _, shift in ipairs({ 0, -6, 6, -12, 12 }) do
        local stop = math.max(low, math.min(high, along + shift))
        for _, offset in ipairs({ -38, 38, -32, 32, -26, 26, -20, 20,
            -44, 44 }) do
            local sign = offset < 0 and -1 or 1
            local spawn = stop + offset
            if spawn >= low and spawn <= high then
                local px = zone.horizontal and stop or cross
                local py = zone.horizontal and cross or stop
                local sx = zone.horizontal and spawn or cross
                local sy = zone.horizontal and cross or spawn
                local square = U().gridSquare(math.floor(sx), math.floor(sy), 0)
                if not square then
                    rejected.unloaded = true
                elseif not outsideViews(sx, sy) then
                    rejected.visible = true
                elseif not openPatch(sx, sy, 2) then
                    local _, why = openPatch(sx, sy, 2)
                    rejected["spawn_blocked:" .. tostring(why)] = true
                elseif not openPatch(px, py, 2) then
                    rejected.pickup_blocked = true
                else
                    local clear = true
                    for step = 1, 18 do
                        local t = step / 18
                        if not openPatch(sx + (px - sx) * t,
                            sy + (py - sy) * t, 1) then
                            clear = false break
                        end
                    end
                    if clear then
                        local facing = zone.horizontal
                            and (sign < 0 and IsoDirections.E or IsoDirections.W)
                            or (sign < 0 and IsoDirections.S or IsoDirections.N)
                        local from = { x = sx, y = sy, z = 0 }
                        local pickup = { x = px, y = py, z = 0 }
                        local source = parkedCar and point(parkedCar) or from
                        local routable, routeReason
                        if source then
                            routable, routeReason = pickupRoute(
                                source, pickup, parkedCar ~= nil)
                        end
                        if routable then
                            return { spawn = from, pickup = pickup,
                                facing = facing }
                        end
                        rejected[routeReason or "pickup_route_unavailable"] = true
                    else
                        rejected.corridor_blocked = true
                    end
                end
            else
                rejected.outside_zone = true
            end
        end
    end
    local reasons = {}
    for reason in pairs(rejected) do reasons[#reasons + 1] = reason end
    table.sort(reasons)
    return nil, table.concat(reasons, "+")
end
local function findSite(actor, origin, parkedCar)
    if not SC.ExpeditionRoute or not SC.ExpeditionRoute.planFromPoint
        or type(addVehicleDebug) ~= "function" then
        return nil, "taxi_creation_unavailable"
    end
    local seen, rejected = {}, {}
    local zoneCount = 0
    for radius = 0, 24, 3 do
        for dx = -radius, radius, 3 do
            for dy = -radius, radius, 3 do
                if math.max(math.abs(dx), math.abs(dy)) == radius then
                    local square = U().gridSquare(origin.x + dx,
                        origin.y + dy, 0)
                    local zone = roadZone(square)
                    local key = zone and (zone.x .. ":" .. zone.y .. ":"
                        .. zone.w .. ":" .. zone.h)
                    if key and not seen[key] then
                        seen[key] = true
                        zoneCount = zoneCount + 1
                        local site, why = siteForZone(zone, origin, actor,
                            parkedCar)
                        if site then return site end
                        rejected[why or "unknown"] = true
                    end
                end
            end
        end
    end
    local reasons = {}
    for reason in pairs(rejected) do reasons[#reasons + 1] = reason end
    table.sort(reasons)
    return nil, "no_safe_loaded_road:zones=" .. tostring(zoneCount)
        .. ":" .. table.concat(reasons, ",")
end

local function doorSquare(car)
    if Vector3f == nil then return nil end
    local outside = call(car, "getPassengerPosition", 0, "outside")
    local world = outside and call(car, "getPassengerPositionWorldPos",
        outside, Vector3f.new())
    local x, y = world and world:x(), world and world:y()
    if not x or not y then return nil end
    local best, distance
    for dx = -2, 2 do
        for dy = -2, 2 do
            local square = U().gridSquare(math.floor(x) + dx,
                math.floor(y) + dy, 0)
            local clear = square and U().isClearActorSpawnSquare(square)
            local gap = clear and call(car, "getEnterSeatDistance", 0,
                square:getX() + 0.5, square:getY() + 0.5)
            if clear and finite(gap) and gap >= 0 and gap <= 2.56
                and (not distance or gap < distance) then
                best, distance = square, gap
            end
        end
    end
    return best
end

local function prepareCar(car)
    local tank = call(car, "getPartById", "GasTank")
    local capacity = tank and tonumber(call(tank, "getContainerCapacity"))
    if not capacity or capacity <= 0 then return false, "taxi_fuel_unavailable" end
    call(tank, "setContainerContentAmount", capacity * 0.8)
    if (tonumber(call(tank, "getContainerContentAmount")) or 0) < capacity * 0.75 then
        return false, "taxi_fuel_unavailable"
    end
    local battery = call(car, "getBattery")
    local cell = battery and call(battery, "getInventoryItem")
    if not cell then return false, "taxi_battery_unavailable" end
    call(cell, "setCurrentUsesFloat", 1)
    return true
end

local function spawnDriver(car, token, restoredId, preservePhase)
    local door = doorSquare(car)
    if not door then return false, "taxi_driver_door_blocked" end
    local ticket, spawnReason = SC.Actor.beginSpawn(door, {
        id = restoredId,
        recruited = false,
        identity = { forename = "Markus", surname = "Sloane",
            gender = "male", outfit = "Classy", visualSeed = 3100240 },
        initialize = function(actor)
            local data = call(actor, "getModData")
            if type(data) ~= "table" then return false, "driver_marker_missing" end
            data.LF_MarkusDriver = token
            return data.LF_MarkusDriver == token
        end,
    })
    if not ticket then return false, spawnReason end
    spawnTicket = ticket
    if not preservePhase then visit.phase = "driver_pending" end
    return true, "driver_spawn_requested"
end

local function spawnCab(actor, site)
    local ready, token = SC.TaxiCab.prepareSpawn(visit.bookingGeneration)
    if not ready then return false, token end
    visit.cabToken, visit.phase = token, "spawn_pending"
    visit.pickup = copyPoint(site.pickup)
    local square = U().gridSquare(math.floor(site.spawn.x),
        math.floor(site.spawn.y), 0)
    if not outsideViews(site.spawn.x, site.spawn.y) or not openPatch(site.spawn.x,
        site.spawn.y, 2) then return false, "spawn_site_changed" end
    local okay, car = pcall(addVehicleDebug, "Base.CarTaxi",
        site.facing, nil, square)
    if not okay or not car or not call(car, "getSquare") then
        return false, "taxi_spawn_unresolved"
    end
    local claimed, reason = SC.TaxiCab.claimSpawn(car, token)
    if not claimed then return false, reason end
    visit.cabSqlId = tonumber(call(car, "getSqlId"))
    local prepared, why = prepareCar(car)
    if not prepared then return false, why end
    local dressed, appearanceReason = SC.TaxiCab.applyAppearance(car)
    if not dressed then
        print("[SurvivorCompanion/taxi] cab appearance: "
            .. tostring(appearanceReason))
    end
    return spawnDriver(car, token)
end

local function copyCabBlood(values)
    if type(values) ~= "table" then return nil end
    local result = {}
    for _, area in ipairs({ "Front", "Rear", "Left", "Right" }) do
        local intensity = tonumber(values[area])
        if not intensity or intensity ~= intensity
            or intensity < 0 or intensity > 1 then return nil end
        result[area] = intensity
    end
    return result
end

local function snapshot()
    if not visit then return nil end
    return { bookingGeneration = visit.bookingGeneration,
        phase = visit.phase, cabToken = visit.cabToken,
        cabSqlId = visit.cabSqlId, driverId = visit.driverId,
        pickup = copyPoint(visit.pickup),
        destination = copyPoint(visit.destination),
        destinationId = visit.destinationId,
        roadTiles = visit.roadTiles,
        dropoff = copyPoint(visit.dropoff),
        departureGoal = copyPoint(visit.departureGoal),
        departurePreviousGoal = copyPoint(visit.departurePreviousGoal),
        departureBacktracked = visit.departureBacktracked,
        departureAttempts = visit.departureAttempts,
        offscreenRetirement = visit.offscreenRetirement,
        removalRequested = visit.removalRequested,
        cabBlood = copyCabBlood(visit.cabBlood),
        destinationProvided = visit.destinationProvided,
        reminderDelivered = visit.reminderDelivered,
        reason = visit.reason }
end

function Service.current() return snapshot() end

function Service.available()
    return SC.Driving and SC.Driving.passengerAvailable()
        and SC.TaxiCab and SC.TaxiFares and SC.ExpeditionRoute
        and SC.Vehicle and SC.Actor and SC.Registry
        and type(addVehicleDebug) == "function"
end

function Service.request(actor, radio)
    if actor ~= player() then return false, "not_booked_customer" end
    if not Service.available() then return false, "taxi_creation_unavailable" end
    -- A cab left at an earlier dropoff is an actual saved vehicle. If its
    -- chunk is not loaded, beginning another booking would strand the caller
    -- in a search state that cannot be fulfilled without making a duplicate.
    if not visit and SC.TaxiCab.current() then
        local recovered, why = cab()
        if not recovered then return false, why end
    end
    local accepted, reason, booking = SC.TaxiBooking.request(actor, radio)
    if not accepted then return false, reason end
    if visit then return true, "already_booked", snapshot() end
    -- The next physical pickup is a new fare with a fresh, finite magazine.
    serviceRounds, driverGun, lastDefenseTrace = 15, nil, nil
    visit = { bookingGeneration = booking.generation,
        phase = "searching", driverId = persistentDriverId }
    nextSearchAt = 0
    return true, reason, snapshot()
end

function Service.status(actor, radio)
    local okay, reason = SC.TaxiBooking.checkRadio(actor, radio)
    if not okay then return false, reason end
    if not visit then return false, "no_booking" end
    return true, visit.phase, snapshot()
end

function Service.updatePickup(actor, radio)
    if not visit or visit.phase ~= "searching" then
        return false, "pickup_locked"
    end
    local okay, reason = SC.TaxiBooking.updatePickup(actor, radio)
    if okay then nextSearchAt = 0 end
    return okay, reason, snapshot()
end

local function stopDrive(reason)
    local actor = findDriver()
    if actor and SC.Driving then SC.Driving.release(actor, reason) end
end

function Service.cancel(actor, radio)
    local okay, reason = SC.TaxiBooking.checkRadio(actor, radio)
    if not okay then return false, reason end
    if not visit then return false, "no_booking" end
    if actor ~= player() then return false, "not_booked_customer" end
    if visit.phase == "in_transit" or visit.phase == "waiting_exit"
        or visit.phase == "payment_due" or visit.phase == "finishing"
        or visit.phase == "departing" or visit.phase == "retiring"
        or visit.phase == "departure_held" then
        return false, "pickup_locked"
    end
    local car = cab()
    if car and call(actor, "getVehicle") == car then
        return false, "leave_cab_before_cancelling"
    end
    stopDrive("taxi_cancelled")
    local fare = SC.TaxiFares and SC.TaxiFares.current()
    if fare and fare.bookingGeneration == visit.bookingGeneration
        and fare.phase ~= "committed" then
        local released, why = SC.TaxiFares.cancel(car)
        if not released then return false, why end
    end
    visit.phase = "cancelling"
    return true, "booking_cancelled", snapshot()
end

local function destinationPoint(zone)
    return { x = (zone.x1 + zone.x2 + 1) / 2,
        y = (zone.y1 + zone.y2 + 1) / 2, z = 0 }
end

local bookedPassenger

function Service.destinations(actor, radio)
    if radio ~= nil then
        local okay, reason = SC.TaxiBooking.checkRadio(actor, radio)
        if not okay then return nil, reason end
    end
    local car = cab()
    if not visit or not car then return nil, "taxi_not_at_pickup" end
    if radio == nil and not bookedPassenger(actor, car) then
        return nil, "taxi_not_ready"
    end
    if visit.phase ~= "waiting_board" and visit.phase ~= "ready_to_depart" then
        return nil, "taxi_not_at_pickup"
    end
    local source = point(car)
    if not SC.ExpeditionCar or not SC.ExpeditionCar.parkingAreas then
        return nil, "parking_unavailable"
    end
    local result = {}
    for _, zone in ipairs(SC.ExpeditionCar.parkingAreas()) do
        local target = destinationPoint(zone)
        local route = SC.ExpeditionRoute.planFromPoint(source, target, true)
        local distance = route and tonumber(route.roadLength)
        if distance and distance >= 12 and distance <= 1000 then
            local quote = SC.TaxiFares.quote(distance)
            result[#result + 1] = { id = zone.id,
                name = zone.name or zone.label or "Base parking",
                target = target, roadTiles = distance,
                required = quote and quote.required or nil }
        end
    end
    return result
end

bookedPassenger = function(actor, car)
    if actor ~= player() or call(actor, "getVehicle") ~= car then return false end
    local seat = tonumber(call(car, "getSeat", actor))
    return seat and seat >= 1 and seat < (tonumber(call(car,
        "getMaxPassengers")) or 0)
        and call(car, "getCharacter", seat) == actor
end

-- The customer has no key to Markus's car. Native player entry needs an
-- accessible front passenger door before the game can board them normally.
local function pickupDoor(car, open)
    local part = call(car, "getPassengerDoor", 1)
    local door = part and call(part, "getDoor")
    if not door then return false, "taxi_passenger_door_unavailable" end
    if call(door, "isLocked") == true then
        if not select(2, U().call(door, "setLocked", false)) then
            return false, "taxi_passenger_door_locked"
        end
        call(car, "transmitPartDoor", part)
        if call(door, "isLocked") ~= false then
            return false, "taxi_passenger_door_locked"
        end
    end
    if call(door, "isOpen") ~= open then
        if not select(2, U().call(door, "setOpen", open)) then
            return false, "taxi_passenger_door_unavailable"
        end
        call(car, "transmitPartDoor", part)
    end
    if call(door, "isOpen") ~= open then
        return false, "taxi_passenger_door_unavailable"
    end
    return true
end

function Service.isBookedPassenger(actor, car)
    local owned = SC.TaxiCab and SC.TaxiCab.current()
    return visit ~= nil and sameBooking() and owned ~= nil
        and owned.ownershipToken == visit.cabToken
        and bookedPassenger(actor, car) == true
end

function Service.offer(actor, radio, item)
    if radio ~= nil then
        local okay, reason = SC.TaxiBooking.checkRadio(actor, radio)
        if not okay then return false, reason end
    end
    local car = cab()
    if not visit or not car or visit.phase ~= "ready_to_depart"
        or not bookedPassenger(actor, car) then
        return false, "taxi_not_ready"
    end
    return SC.TaxiFares.offer(actor, car, item)
end

local function departTo(actor, radio, selected)
    if radio ~= nil then
        local okay, reason = SC.TaxiBooking.checkRadio(actor, radio)
        if not okay then return false, reason end
    end
    local car = cab()
    if not visit or not car or visit.phase ~= "ready_to_depart"
        or not bookedPassenger(actor, car) then
        return false, "taxi_not_ready"
    end
    if not selected then return false, "destination_unavailable" end
    local paid, why, detail = SC.TaxiFares.reserve(actor, car,
        selected.roadTiles)
    if not paid then return false, why, detail end
    local chauffeur = findDriver()
    if not chauffeur or not SC.Driving.isDriver(chauffeur) then
        return false, "driver_unavailable"
    end
    local doorReady, doorReason = pickupDoor(car, false)
    if not doorReady then
        SC.TaxiFares.cancel(car)
        return false, doorReason
    end
    SC.Driving.release(chauffeur, "taxi_departure")
    local started, driveReason = SC.Driving.drive(chauffeur,
        selected.target, { passenger = actor, speedKmh = 50,
            cornerSpeedScale = 2, blockWaitMs = 6000 })
    if not started then
        SC.TaxiFares.cancel(car)
        return false, driveReason
    end
    visit.destination = copyPoint(selected.target)
    visit.destinationId = selected.id
    visit.roadTiles = selected.roadTiles
    visit.phase, visit.reason = "in_transit", nil
    SC.TaxiBooking.advance(visit.bookingGeneration, "in_transit")
    if U().say then
        U().say(chauffeur, DEPART_LINES[(visit.bookingGeneration - 1)
            % #DEPART_LINES + 1])
    end
    return true, "taxi_departed", snapshot()
end

function Service.depart(actor, radio, zoneId)
    local selected
    for _, destination in ipairs(Service.destinations(actor, radio) or {}) do
        if destination.id == zoneId then selected = destination break end
    end
    if selected then visit.destinationProvided = true end
    return departTo(actor, radio, selected)
end

function Service.previewPoint(actor, target)
    if type(target) ~= "table" or not finite(target.x)
        or not finite(target.y) or target.z ~= 0
        or target.x < 0 or target.x > 30000
        or target.y < 0 or target.y > 30000 then
        return nil, "destination_unavailable"
    end
    local car = cab()
    if not visit or not car or visit.phase ~= "ready_to_depart"
        or not bookedPassenger(actor, car) then
        return nil, "taxi_not_ready"
    end
    local route, why, native = SC.ExpeditionRoute.planFromPoint(
        point(car), target, true)
    local distance = route and tonumber(route.roadLength)
    if not distance or distance < 12 or distance > 1000 then
        return nil, why or "destination_unavailable"
    end
    local exitX = native and tonumber(native.exitX)
    local exitY = native and tonumber(native.exitY)
    if not finite(exitX) or not finite(exitY)
        or (exitX - target.x)^2 + (exitY - target.y)^2 > 64 then
        return nil, "destination_not_near_road"
    end
    local quote, quoteReason = SC.TaxiFares.quote(distance)
    if not quote then return nil, quoteReason end
    return { id = "map-point", target = { x = exitX, y = exitY, z = 0 },
        roadTiles = distance, required = quote.required }
end

function Service.departToPoint(actor, radio, target)
    local selected, reason = Service.previewPoint(actor, target)
    if not selected then return false, reason end
    visit.destinationProvided = true
    return departTo(actor, radio, selected)
end

local function fail(reason)
    if not visit then return end
    visit.phase, visit.reason = "held", tostring(reason or "taxi_unavailable")
    resumePending = false
    stopDrive("taxi_held")
end

local function driverKey(actor, car)
    if SC.Driving.hasKey(actor, car) then return true end
    local key = call(car, "createVehicleKey")
    local inventory = call(actor, "getInventory")
    if not key or not inventory or not call(inventory, "AddItem", key)
        or not SC.Driving.hasKey(actor, car) then
        return false, "taxi_key_unavailable"
    end
    return true
end

local function readyToDrive(car)
    local chauffeur = findDriver()
    if not chauffeur then return false, "driver_unavailable" end
    if not SC.Driving.isDriver(chauffeur) then
        local passenger = bookedPassenger(player(), car) and player() or nil
        local prepared, why = SC.Vehicle.preflightDriver(chauffeur, car,
            passenger)
        if not prepared then return false, why end
        local keyed, keyReason = driverKey(chauffeur, car)
        if not keyed then return false, keyReason end
        local boarded, boardReason = SC.Driving.takeWheel(chauffeur, car,
            { preflight = prepared, taxiPassenger = passenger })
        if not boarded then return false, boardReason end
    end
    return SC.Driving.isDriver(chauffeur), "driver_boarded"
end

local function onlyMarkusAboard(car, chauffeur)
    local seats = tonumber(call(car, "getMaxPassengers"))
    if not seats or seats < 1 or seats > 16 then return false end
    for seat = 0, seats - 1 do
        local occupant = call(car, "getCharacter", seat)
        if seat == 0 then
            if occupant ~= chauffeur then return false end
        elseif occupant ~= nil then return false end
    end
    return true
end

local function departureHeading(car)
    if Vector3f ~= nil then
        local forward = call(car, "getForwardVector", Vector3f.new())
        local x, y = tonumber(call(forward, "x")), tonumber(call(forward, "z"))
        local length = x and y and math.sqrt(x * x + y * y) or 0
        if length > 0.1 then return x / length, y / length end
    end
    local from, to = visit and visit.pickup, visit and visit.dropoff
    local x, y = from and to and to.x - from.x,
        from and to and to.y - from.y
    local length = x and y and math.sqrt(x * x + y * y) or 0
    if length > 1 then return x / length, y / length end
    return 1, 0
end

-- Prefer the road ahead, but permit a side street or diagonal when the road
-- bends. A dead end may require one return to the dropoff junction before a
-- different outward leg is available.
local function departureGoal(car)
    local origin = point(car)
    if not origin or not SC.ExpeditionRoute
        or type(SC.ExpeditionRoute.planFromPoint) ~= "function" then
        return nil, "departure_road_unavailable"
    end
    local hx, hy = departureHeading(car)
    local directions = { { hx, hy }, { -hy, hx },
        { hy, -hx }, { -hx, -hy } }
    local diagonal = 0.70710678118655
    local bends = { { (hx - hy) * diagonal, (hy + hx) * diagonal },
        { (hx + hy) * diagonal, (hy - hx) * diagonal },
        { (-hx - hy) * diagonal, (-hy + hx) * diagonal },
        { (-hx + hy) * diagonal, (-hy - hx) * diagonal } }
    local fallback
    for index, radius in ipairs({ 48, 36, 64, 48, 64 }) do
        local probes = index <= 3 and directions or bends
        for _, direction in ipairs(probes) do
            local target = { x = origin.x + direction[1] * radius,
                y = origin.y + direction[2] * radius, z = 0 }
            if target.x >= 0 and target.x <= 30000
                and target.y >= 0 and target.y <= 30000
                and U().gridSquare(math.floor(target.x),
                    math.floor(target.y), 0) then
                local route, _, native = SC.ExpeditionRoute.planFromPoint(
                    origin, target, true)
                local entry = native and { x = tonumber(native.entryX),
                    y = tonumber(native.entryY) }
                local exit = native and { x = tonumber(native.exitX),
                    y = tonumber(native.exitY) }
                local length = route and tonumber(route.roadLength)
                if entry and exit and finite(entry.x) and finite(entry.y)
                    and finite(exit.x) and finite(exit.y)
                    and length and length >= 25 and length <= 140
                    and distanceSquared(entry, origin) <= 144
                    and distanceSquared(exit, target) <= 64
                    and distanceSquared(exit, origin) >= 625
                    and (not visit.dropoff or distanceSquared(exit, visit.dropoff)
                        > distanceSquared(origin, visit.dropoff) + 100)
                    and (not visit.departureGoal
                        or distanceSquared(exit, visit.departureGoal) >= 100)
                    and (not visit.departurePreviousGoal
                        or distanceSquared(exit, visit.departurePreviousGoal) >= 100) then
                    local goal = { x = exit.x, y = exit.y, z = 0 }
                    if outsideViews(goal.x, goal.y) then return goal end
                    fallback = fallback or goal
                end
            end
        end
    end
    if not fallback and not visit.departureBacktracked and visit.dropoff
        and distanceSquared(origin, visit.dropoff) >= 625 then
        local route, _, native = SC.ExpeditionRoute.planFromPoint(
            origin, visit.dropoff, true)
        local entry = native and { x = tonumber(native.entryX),
            y = tonumber(native.entryY) }
        local exit = native and { x = tonumber(native.exitX),
            y = tonumber(native.exitY) }
        local length = route and tonumber(route.roadLength)
        if entry and exit and finite(entry.x) and finite(entry.y)
            and finite(exit.x) and finite(exit.y)
            and length and length >= 25 and length <= 140
            and distanceSquared(entry, origin) <= 144
            and distanceSquared(exit, visit.dropoff) <= 64 then
            return { x = exit.x, y = exit.y, z = 0 }, true
        end
    end
    return fallback, fallback and nil or "departure_road_unavailable"
end

local function startDeparture(current)
    if current < nextDepartureAt then return true end
    nextDepartureAt = current + 5000
    local car, reason = cab()
    if not car then visit.reason = reason return true end
    visit.dropoff = visit.dropoff or point(car)
    if not visit.dropoff then
        visit.reason = "dropoff_position_unavailable" return true
    end
    if type(removeVehicle) ~= "function" then
        visit.reason = "cab_removal_unavailable" return true
    end
    local chauffeur = findDriver()
    if not chauffeur then visit.reason = "driver_unavailable" return true end
    if not onlyMarkusAboard(car, chauffeur) then
        visit.reason = "passengers_still_aboard" return true
    end
    local clear, why = SC.TaxiFares.retirementStatus(car)
    if not clear then visit.reason = why return true end
    local goal, backtrackingOrReason = departureGoal(car)
    local goalReason = type(backtrackingOrReason) == "string"
        and backtrackingOrReason or nil
    if not goal then
        visit.departureAttempts = (visit.departureAttempts or 0) + 1
        visit.reason = goalReason
        if visit.departureAttempts >= 4 then
            visit.phase = "departure_held"
            nextDepartureAt = current + 30000
        end
        return true
    end
    local released, releaseReason = SC.Driving.release(chauffeur,
        "taxi_depart_after_dropoff")
    if not released then visit.reason = releaseReason return true end
    local ready, boardReason = readyToDrive(car)
    if not ready then visit.reason = boardReason return true end
    local started, driveReason = SC.Driving.drive(chauffeur, goal,
        { speedKmh = 30, cornerSpeedScale = 2,
            blockWaitMs = 6000 })
    if not started then visit.reason = driveReason return true end
    visit.departurePreviousGoal = copyPoint(visit.departureGoal)
    visit.departureGoal, visit.phase, visit.reason = goal, "departing", nil
    if backtrackingOrReason == true then visit.departureBacktracked = true end
    visit.departureAttempts = (visit.departureAttempts or 0) + 1
    return true
end

local function finishRetirement(current)
    local car = retiringCar or cab()
    if not car then visit.reason = "cab_retirement_unresolved" return true end
    local sqlId, token = visit.cabSqlId, visit.cabToken
    local removed = call(car, "isRemovedFromWorld") == true
        and SC.Vehicle.loadedBySqlId(sqlId) == nil
    if not removed then
        local location = point(car)
        if not location or not visit.dropoff
            or (visit.offscreenRetirement ~= true
                and distanceSquared(location, visit.dropoff) < 900)
            or not outsideViews(location.x, location.y) then
            visit.reason = "cab_still_in_view" return true
        end
        if SC.Vehicle.isStationary(car) ~= true then
            visit.reason = "cab_still_moving" return true
        end
        local chauffeur = findDriver()
        if chauffeur and call(chauffeur, "getVehicle") == car then
            local released, why = SC.Driving.release(chauffeur,
                "taxi_retiring")
            if not released then visit.reason = why return true end
            local exited, exitReason = SC.Vehicle.exit(chauffeur, car)
            if not exited then visit.reason = exitReason return true end
        end
        local seats = tonumber(call(car, "getMaxPassengers"))
        if not seats or seats < 1 or seats > 16 then
            visit.reason = "cab_seats_unavailable" return true
        end
        for seat = 0, seats - 1 do
            if call(car, "getCharacter", seat) ~= nil then
                visit.reason = "cab_still_occupied" return true
            end
        end
        local clear, why = SC.TaxiFares.retirementStatus(car)
        if not clear then visit.reason = why return true end
        if chauffeur and SC.Actor.isCompanion(chauffeur) then
            local retired, actorReason = SC.Actor.remove(chauffeur)
            if not retired then visit.reason = actorReason return true end
        end
        if current < nextDepartureAt then return true end
        nextDepartureAt = current + 5000
        local blood, bloodReason = SC.TaxiCab.captureAppearance(car)
        if blood then visit.cabBlood = blood
        else print("[SurvivorCompanion/taxi] cab appearance capture: "
            .. tostring(bloodReason)) end
        local called, result = pcall(removeVehicle, player(), car)
        if not called then visit.reason = "cab_removal_failed:" .. tostring(result)
            return true end
        visit.removalRequested = true
        retiringCar = car
        removed = call(car, "isRemovedFromWorld") == true
            and SC.Vehicle.loadedBySqlId(sqlId) == nil
        if not removed then visit.reason = "cab_removal_pending" return true end
    end
    local fareRetired, fareReason = SC.TaxiFares.retireRemoved(sqlId)
    if not fareRetired then visit.reason = fareReason return true end
    local cabRetired, cabReason = SC.TaxiCab.retireRemoved(sqlId, token,
        visit.cabBlood)
    if not cabRetired then visit.reason = cabReason return true end
    local completed = SC.TaxiBooking.complete(visit.bookingGeneration)
    if not completed then visit.reason = "booking_completion_failed" return false end
    visit, driver, persistentDriverId, retiringCar = nil, nil, nil, nil
    return true
end

function Service.tick(current)
    if not visit then return true end
    current = tonumber(current) or now()
    if visit.phase ~= "cancelling" and not sameBooking() then
        fail("booking_changed") return false
    end
    if resumePending then
        local car = cab()
        if not car then return true end
        local chauffeur = findDriver()
        if not chauffeur then
            if spawnTicket then
                local actor, why = SC.Actor.pollSpawn(spawnTicket)
                if actor then
                    spawnTicket = nil
                    local expectedId = visit.driverId or persistentDriverId
                    if not recordDriver(actor)
                        or visit.driverId ~= expectedId then
                        fail("driver_identity_changed_on_reload") return false
                    end
                    persistentDriverId = visit.driverId
                    chauffeur = actor
                elseif why ~= "spawn_pending" then
                    spawnTicket = nil
                    fail(why) return false
                end
            elseif resumeDriverAt == 0 then
                resumeDriverAt = current + 5000
            elseif current >= resumeDriverAt then
                if call(car, "getCharacter", 0) ~= nil then
                    visit.reason = "driver_seat_occupied_on_reload"
                    return true
                end
                local recoveryId = visit.driverId or persistentDriverId
                if type(recoveryId) ~= "string" or recoveryId == "" then
                    fail("driver_identity_missing_on_reload") return false
                end
                local started, why = spawnDriver(car, visit.cabToken,
                    recoveryId, true)
                if not started then
                    visit.reason = why
                    resumeDriverAt = current + 5000
                end
            end
            if not chauffeur then return true end
        end
        local ready, boardReason = readyToDrive(car)
        if not ready then
            visit.reason = boardReason
            return true
        end
        if visit.phase == "pickup_drive" then
            local started, why = SC.Driving.drive(chauffeur,
                visit.pickup, { speedKmh = 20, cornerSpeedScale = 2,
                    blockWaitMs = 6000 })
            if not started then fail(why) return false end
        elseif visit.phase == "in_transit" then
            if not bookedPassenger(player(), car) then
                fail("taxi_passenger_seat_lost_on_reload") return false
            end
            local started, why = SC.Driving.drive(chauffeur,
                visit.destination, { passenger = player(),
                    speedKmh = 50, cornerSpeedScale = 2,
                    blockWaitMs = 6000 })
            if not started then fail(why) return false end
        elseif visit.phase == "departing" then
            if not visit.departureGoal then
                fail("departure_goal_missing_on_reload") return false
            end
            local started, why = SC.Driving.drive(chauffeur,
                visit.departureGoal, { speedKmh = 30,
                    cornerSpeedScale = 2, blockWaitMs = 6000 })
            if not started then visit.reason = why return true end
        elseif visit.phase == "waiting_board"
            or visit.phase == "ready_to_depart" then
            -- The parked cab does not need a driving lease. Keeping one here
            -- prevents a defensive firearm action while Markus waits outside.
            if type(SC.Driving.isDriving) == "function"
                and SC.Driving.isDriving(chauffeur) then
                local released, why = SC.Driving.release(chauffeur,
                    "taxi_waiting_for_passenger")
                if not released then visit.reason = why return true end
            end
        end
        resumePending = false
        resumeDriverAt = 0
    end
    if visit.phase == "searching" then
        if current < nextSearchAt then return true end
        nextSearchAt = current + 10000
        local actor = player()
        local booking = book()
        if not actor or not booking then return true end
        local existing = SC.TaxiCab.current()
        local car, recoverReason
        if existing then
            car, recoverReason = cab()
            if not car then visit.reason = recoverReason return true end
        end
        local site, why = findSite(actor, booking.requestedAt, car)
        if not site then visit.reason = why return true end
        if existing then
            local bound, boundReason = SC.TaxiCab.beginVisit(car,
                visit.bookingGeneration)
            if not bound then visit.reason = boundReason return true end
            visit.cabToken, visit.cabSqlId = existing.ownershipToken,
                existing.sqlId
            visit.pickup = copyPoint(site.pickup)
            visit.phase = "board_driver"
            if not findDriver() then
                local spawned, spawnReason = spawnDriver(car, visit.cabToken,
                    persistentDriverId)
                if not spawned then fail(spawnReason) end
            end
        else
            local spawned, spawnReason = spawnCab(actor, site)
            if not spawned then fail(spawnReason) end
        end
    elseif visit.phase == "driver_pending" then
        if not spawnTicket then fail("driver_spawn_unresolved") return false end
        local actor, why = SC.Actor.pollSpawn(spawnTicket)
        if actor then
            spawnTicket = nil
            if not recordDriver(actor) then fail("driver_identity_unavailable")
            else
                persistentDriverId = visit.driverId
                visit.phase = "board_driver"
            end
        elseif why ~= "spawn_pending" then
            spawnTicket = nil
            fail(why)
        end
    elseif visit.phase == "board_driver" then
        local car, reason = cab()
        if not car then visit.reason = reason return true end
        local ready, why = readyToDrive(car)
        if not ready then visit.reason = why return true end
        local started, driveReason = SC.Driving.drive(driver,
            visit.pickup, { speedKmh = 20, cornerSpeedScale = 2,
                blockWaitMs = 6000 })
        if not started then fail(driveReason) return false end
        visit.phase, visit.reason = "pickup_drive", nil
        SC.TaxiBooking.advance(visit.bookingGeneration, "pickup_en_route")
    elseif visit.phase == "pickup_drive" then
        local chauffeur = findDriver()
        local job = chauffeur and SC.Driving.jobStatus(chauffeur)
        if job and job.result == "arrived" then
            local car = cab()
            local opened, doorReason
            if car then opened, doorReason = pickupDoor(car, true) end
            if not opened then
                visit.reason = doorReason or "taxi_cab_unloaded"
                return true
            end
            local released, releaseReason = SC.Driving.release(chauffeur,
                "taxi_waiting_for_passenger")
            if not released then visit.reason = releaseReason return true end
            visit.phase, visit.reason = "waiting_board", nil
            SC.TaxiBooking.advance(visit.bookingGeneration, "at_pickup")
            if U().say then
                U().say(chauffeur, PICKUP_LINES[(visit.bookingGeneration - 1)
                    % #PICKUP_LINES + 1])
            end
        elseif not job or job.result == "failed" then
            fail(job and job.reason or "pickup_drive_lost")
        end
    elseif visit.phase == "waiting_board" or visit.phase == "ready_to_depart" then
        local car = cab()
        if not car then return true end
        if bookedPassenger(player(), car) then
            if visit.phase ~= "ready_to_depart" then
                call(player(), "setHaloNote",
                    "Markus: Right-click to choose a destination, or right-click a road on the world map.")
                destinationReminderAt = current + 10000
            end
            visit.phase = "ready_to_depart"
            if destinationReminderAt == nil then
                destinationReminderAt = current + 10000
            end
            if not visit.destinationProvided and not visit.reminderDelivered
                and current >= destinationReminderAt then
                visit.reminderDelivered = true
                local chauffeur = findDriver()
                if chauffeur and U().say then
                    U().say(chauffeur, DESTINATION_REMINDERS[
                        (visit.bookingGeneration - 1) % #DESTINATION_REMINDERS + 1])
                end
            end
        else
            destinationReminderAt = nil
            local opened, doorReason = pickupDoor(car, true)
            visit.reason = opened and nil or doorReason
            visit.phase = "waiting_board"
        end
    elseif visit.phase == "in_transit" then
        local car = cab()
        local chauffeur = findDriver()
        if not car or not chauffeur then return true end
        if not bookedPassenger(player(), car) then
            fail("passenger_left_during_ride") return false
        end
        local job = SC.Driving.jobStatus(chauffeur)
        if job and job.result == "arrived" then
            visit.phase = "waiting_exit"
            SC.TaxiBooking.advance(visit.bookingGeneration, "at_destination")
            if U().say then U().say(chauffeur,
                "End of the road. For now. Take your belongings.") end
        elseif not job or job.result == "failed" then
            fail(job and job.reason or "ride_lost")
        end
    elseif visit.phase == "waiting_exit" or visit.phase == "payment_due" then
        local car = cab()
        if not car then return true end
        if bookedPassenger(player(), car) then return true end
        if SC.Vehicle.isStationary(car) ~= true then return true end
        local settled, why = SC.TaxiFares.commit(car)
        if settled then
            visit.phase, visit.reason = "finishing", nil
            visit.dropoff = point(car)
            nextDepartureAt = 0
        else
            visit.phase, visit.reason = "payment_due", why
        end
    elseif visit.phase == "finishing" then
        return startDeparture(current)
    elseif visit.phase == "departing" then
        local car = cab()
        local chauffeur = findDriver()
        if not car or not chauffeur then return true end
        local location = point(car)
        if location and visit.dropoff
            and distanceSquared(location, visit.dropoff) >= 900
            and outsideViews(location.x, location.y) then
            local released, why = SC.Driving.release(chauffeur,
                "taxi_out_of_view")
            if not released then visit.reason = why return true end
            visit.phase, visit.reason = "retiring", nil
            nextDepartureAt = 0
            return finishRetirement(current)
        end
        local job = SC.Driving.jobStatus(chauffeur)
        if job and (job.result == "arrived" or job.result == "failed") then
            SC.Driving.release(chauffeur, "taxi_departure_leg_ended")
            if job.result == "arrived" then
                -- A visible arrival is progress, not a failed departure. Keep
                -- finding outward legs until the cab has left every viewport.
                visit.departureAttempts = 0
            end
            if (visit.departureAttempts or 0) >= 4 then
                visit.phase = "departure_held"
                visit.reason = job.reason or "cab_still_in_view"
                nextDepartureAt = current + 30000
            else
                visit.phase = "finishing"
                visit.reason = job.result == "failed" and job.reason or nil
                nextDepartureAt = current + 2000
            end
        end
    elseif visit.phase == "departure_held" then
        -- Retry in bounded bursts. A blocked road can clear when the player
        -- moves away or traffic changes; a held visit must not own the booking
        -- indefinitely. startDeparture rechecks fare, passengers and property.
        if nextDepartureAt == 0 then nextDepartureAt = current + 30000 end
        if current < nextDepartureAt then return true end
        local car = cab()
        local chauffeur = findDriver()
        local location = car and point(car)
        if car and chauffeur and location and outsideViews(location.x, location.y)
            and SC.Vehicle.isStationary(car) == true
            and onlyMarkusAboard(car, chauffeur)
            and SC.TaxiFares.retirementStatus(car) == true
            and type(removeVehicle) == "function" then
            visit.phase, visit.reason = "retiring", nil
            visit.offscreenRetirement = true
            nextDepartureAt = 0
            return finishRetirement(current)
        end
        visit.departureAttempts = 0
        visit.phase = "finishing"
        nextDepartureAt = 0
        return startDeparture(current)
    elseif visit.phase == "retiring" then
        return finishRetirement(current)
    elseif visit.phase == "cancelling" then
        local car = cab()
        local chauffeur = findDriver()
        if chauffeur and car and call(chauffeur, "getVehicle") == car then
            SC.Driving.release(chauffeur, "taxi_visit_finished")
            local exited = SC.Vehicle.exit(chauffeur, car)
            if not exited then return true end
        end
        local completed = SC.TaxiBooking.abort(visit.bookingGeneration)
        if not completed then return false end
        visit = nil
    end
    return true
end

-- One line per state change makes a field report distinguish a fare hold,
-- missing road, failed native drive, and a cab that is still in view.
local tickVisit = Service.tick
function Service.tick(current)
    local result = tickVisit(current)
    local phase = visit and visit.phase or "none"
    local reason = visit and visit.reason or "none"
    local attempts = visit and visit.departureAttempts or 0
    local signature = tostring(phase) .. ":" .. tostring(reason)
        .. ":" .. tostring(attempts)
    if signature ~= lastTraceSignature then
        print("[SurvivorCompanion/taxi] visit " .. signature)
        lastTraceSignature = signature
    end
    return result
end

function Service.export()
    if visit then updateRounds(findDriver()) end
    return { schema = 1, driverId = persistentDriverId,
        serviceRounds = serviceRounds, visit = snapshot() }
end

function Service.restore(saved)
    if saved == nil then
        visit, driver, spawnTicket, nextSearchAt = nil, nil, nil, 0
        persistentDriverId = nil
        resumePending = false
        resumeDriverAt = 0
        nextDepartureAt, retiringCar = 0, nil
        destinationReminderAt = nil
        lastTraceSignature = nil
        serviceRounds, driverGun, lastDefenseTrace = 15, nil, nil
        return true
    end
    if type(saved) ~= "table" or saved.schema ~= 1
        or saved.driverId ~= nil and (type(saved.driverId) ~= "string"
            or saved.driverId == "")
        or saved.serviceRounds ~= nil and (type(saved.serviceRounds) ~= "number"
            or saved.serviceRounds < 0 or saved.serviceRounds > 15
            or saved.serviceRounds ~= math.floor(saved.serviceRounds)) then
        return false, "invalid_taxi_service"
    end
    local candidate = saved.visit
    if candidate then
        if type(candidate) ~= "table"
            or not finite(candidate.bookingGeneration)
            or candidate.bookingGeneration < 1
            or candidate.bookingGeneration ~= math.floor(candidate.bookingGeneration)
            or type(candidate.phase) ~= "string"
            or not ({ searching = true, spawn_pending = true,
                driver_pending = true, board_driver = true,
                pickup_drive = true, waiting_board = true,
                ready_to_depart = true, in_transit = true,
                waiting_exit = true, payment_due = true,
                finishing = true, departing = true, retiring = true,
                departure_held = true, cancelling = true,
                held = true })[candidate.phase]
            or candidate.driverId ~= nil and type(candidate.driverId) ~= "string"
            or candidate.cabToken ~= nil and type(candidate.cabToken) ~= "string"
            or candidate.cabSqlId ~= nil and not finite(candidate.cabSqlId)
            or candidate.pickup ~= nil and (type(candidate.pickup) ~= "table"
                or not finite(candidate.pickup.x) or not finite(candidate.pickup.y)
                or candidate.pickup.z ~= 0)
            or candidate.destination ~= nil and (type(candidate.destination) ~= "table"
                or not finite(candidate.destination.x)
                or not finite(candidate.destination.y)
                or candidate.destination.z ~= 0)
            or candidate.dropoff ~= nil and (type(candidate.dropoff) ~= "table"
                or not finite(candidate.dropoff.x)
                or not finite(candidate.dropoff.y)
                or candidate.dropoff.z ~= 0)
            or candidate.departureGoal ~= nil
                and (type(candidate.departureGoal) ~= "table"
                    or not finite(candidate.departureGoal.x)
                    or not finite(candidate.departureGoal.y)
                    or candidate.departureGoal.z ~= 0)
            or candidate.departurePreviousGoal ~= nil
                and (type(candidate.departurePreviousGoal) ~= "table"
                    or not finite(candidate.departurePreviousGoal.x)
                    or not finite(candidate.departurePreviousGoal.y)
                    or candidate.departurePreviousGoal.z ~= 0)
            or candidate.departureBacktracked ~= nil
                and type(candidate.departureBacktracked) ~= "boolean"
            or candidate.departureAttempts ~= nil
                and (not finite(candidate.departureAttempts)
                    or candidate.departureAttempts < 0
                    or candidate.departureAttempts > 4
                    or candidate.departureAttempts ~= math.floor(candidate.departureAttempts))
            or candidate.offscreenRetirement ~= nil
                and type(candidate.offscreenRetirement) ~= "boolean"
            or candidate.removalRequested ~= nil
                and type(candidate.removalRequested) ~= "boolean"
            or candidate.destinationProvided ~= nil
                and type(candidate.destinationProvided) ~= "boolean"
            or candidate.reminderDelivered ~= nil
                and type(candidate.reminderDelivered) ~= "boolean"
            or candidate.cabBlood ~= nil
                and copyCabBlood(candidate.cabBlood) == nil then
            return false, "invalid_taxi_service"
        end
        candidate = { bookingGeneration = candidate.bookingGeneration,
            phase = candidate.phase, driverId = candidate.driverId,
            cabToken = candidate.cabToken, cabSqlId = candidate.cabSqlId,
            pickup = copyPoint(candidate.pickup),
            destination = copyPoint(candidate.destination),
            destinationId = candidate.destinationId,
            roadTiles = candidate.roadTiles,
            dropoff = copyPoint(candidate.dropoff),
            departureGoal = copyPoint(candidate.departureGoal),
            departurePreviousGoal = copyPoint(candidate.departurePreviousGoal),
            departureBacktracked = candidate.departureBacktracked,
            departureAttempts = candidate.departureAttempts,
            offscreenRetirement = candidate.offscreenRetirement,
            removalRequested = candidate.removalRequested,
            cabBlood = copyCabBlood(candidate.cabBlood),
            destinationProvided = candidate.destinationProvided,
            reminderDelivered = candidate.reminderDelivered,
            reason = candidate.reason }
        if candidate.phase == "driver_pending"
            or candidate.phase == "spawn_pending" then
            candidate.phase, candidate.reason = "held", "spawn_recovery_unresolved"
        end
    end
    visit, persistentDriverId = candidate, saved.driverId
    driver, spawnTicket, nextSearchAt = nil, nil, 0
    resumePending = candidate ~= nil and (candidate.phase == "board_driver"
        or candidate.phase == "pickup_drive"
        or candidate.phase == "in_transit"
        or candidate.phase == "waiting_board"
        or candidate.phase == "ready_to_depart"
        or candidate.phase == "waiting_exit"
        or candidate.phase == "payment_due"
        or candidate.phase == "finishing"
        or candidate.phase == "departing"
        or candidate.phase == "departure_held")
    resumeDriverAt = 0
    nextDepartureAt, retiringCar = 0, nil
    destinationReminderAt = nil
    lastTraceSignature = nil
    serviceRounds, driverGun, lastDefenseTrace = saved.serviceRounds or 15, nil, nil
    return true
end

function Service.reset()
    visit, driver, spawnTicket, nextSearchAt = nil, nil, nil, 0
    persistentDriverId = nil
    resumePending = false
    resumeDriverAt = 0
    nextDepartureAt, retiringCar = 0, nil
    destinationReminderAt = nil
    lastTraceSignature = nil
    serviceRounds, driverGun, lastDefenseTrace = 15, nil, nil
    return true
end

return Service
