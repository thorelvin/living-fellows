-- SPDX-License-Identifier: MIT

require "SCNamespace"
require "SCCall"
require "SCConfig"
require "SCRegistry"
require "SCDiagnostics"
require "SCActionSupervisor"

local SC = SurvivorCompanion
SC.Vehicle = SC.Vehicle or {}

local vehicleService = SC.Vehicle
local storedById = {}
local reservations = {}
local manifests = {}
local lastVehicleShotAt = setmetatable({}, { __mode = "k" })
local transactions = setmetatable({}, { __mode = "k" })
local seatResources = {}
local stationary

local function method(object, name)
    if object == nil then return nil end
    local ok, value = pcall(function() return object[name] end)
    return ok and type(value) == "function" and value or nil
end

local function invoke(object, name, ...)
    return SC.Call.method(object, name, ...)
end

local function finite(value, fallback)
    value = tonumber(value)
    if value == nil or value ~= value or value == math.huge or value == -math.huge then
        return fallback
    end
    return value
end

local function vehicleIdentity(vehicle)
    if vehicle == nil then return nil end
    local idOk, id = invoke(vehicle, "getId")
    local scriptOk, script = invoke(vehicle, "getScriptName")
    local xOk, x = invoke(vehicle, "getX")
    local yOk, y = invoke(vehicle, "getY")
    local zOk, z = invoke(vehicle, "getZ")
    if not idOk or id == nil or not xOk or not yOk then return nil end
    return {
        id = math.floor(finite(id, -1)),
        script = scriptOk and tostring(script or "") or "",
        x = finite(x, 0),
        y = finite(y, 0),
        z = zOk and finite(z, 0) or 0,
    }
end

local function keyFor(identity)
    if type(identity) ~= "table" then return nil end
    return tostring(identity.id) .. ":" .. tostring(identity.script or "")
end

local function seatKey(identity, seat)
    local key = keyFor(identity)
    return key and (key .. ":" .. tostring(seat)) or nil
end

local function seatResource(reservation)
    if reservation == nil then return nil end
    local resource = seatResources[reservation]
    if resource == nil then
        resource = { kind = "vehicle_seat", key = reservation }
        seatResources[reservation] = resource
    end
    return resource
end

local function supervisor()
    return type(SC.ActionSupervisor) == "table" and SC.ActionSupervisor or nil
end

local function transactionIsCurrent(transaction)
    local service = supervisor()
    return type(transaction) == "table" and service ~= nil
        and type(service.isCurrent) == "function"
        and service.isCurrent(transaction.supervisorToken)
end

local function clearTransaction(actor, transaction)
    if transactions[actor] == transaction then transactions[actor] = nil end
end

local function actorIsOnFoot(actor)
    local vehicleOk, current = invoke(actor, "getVehicle")
    return vehicleOk and current == nil
end

local function cancelTransactionState(actor, reason, token)
    local transaction = transactions[actor]
    if transaction == nil or transaction.supervisorToken ~= token then return true end
    if transaction.moduleReservationClaimed == true and actorIsOnFoot(actor)
        and reservations[transaction.reservation] == transaction.actorId then
        reservations[transaction.reservation] = nil
    end
    clearTransaction(actor, transaction)
    return true, reason or "vehicle_transaction_cancelled"
end

local function finishTransaction(transaction, succeeded, reason, detail)
    if type(transaction) ~= "table" then return false, "vehicle_transaction_missing" end
    local service = supervisor()
    local token = transaction.supervisorToken
    if succeeded ~= true and transaction.moduleReservationClaimed == true
        and not (type(detail) == "table" and detail.preserveReservation == true)
        and actorIsOnFoot(transaction.actor)
        and reservations[transaction.reservation] == transaction.actorId then
        reservations[transaction.reservation] = nil
    end
    clearTransaction(transaction.actor, transaction)
    if service == nil or type(token) ~= "table" then return succeeded, reason end
    if succeeded == true and type(service.complete) == "function" then
        service.complete(token, reason or "vehicle_transaction_complete", detail)
    elseif succeeded ~= true and type(service.fail) == "function" then
        service.fail(token, reason or "vehicle_transaction_failed", detail)
    end
    return succeeded, reason
end

local function beginTransaction(actor, vehicle, seat, action, intent)
    local service = supervisor()
    if service == nil or type(service.begin) ~= "function"
        or type(service.reserve) ~= "function" then
        return nil, "action_supervisor_unavailable"
    end
    if not SC.Actor.isCompanion(actor) then return nil, "actor is not an active companion" end
    local identity = vehicleIdentity(vehicle)
    if identity == nil then return nil, "vehicle identity is unavailable" end
    seat = math.floor(finite(seat, -1))
    if seat < 1 then return nil, "native vehicle seat is invalid" end
    local reservation = seatKey(identity, seat)
    local id = SC.Registry.idOf(actor)
    if id == nil then return nil, "companion identity is unavailable" end
    local existing = transactions[actor]
    if transactionIsCurrent(existing) then
        if existing.action == action and existing.vehicle == vehicle and existing.seat == seat then
            return existing, "already_active"
        end
    else
        transactions[actor] = nil
    end
    local explicit = type(intent) == "table" and (intent.immediateCommand == true
        or intent.playerCommand == true)
    local targetKey = action .. ":" .. tostring(reservation)
    local token, beginReason, retry = service.begin(actor, {
        owner = "vehicle",
        action = action,
        priority = explicit and service.Priority.PLAYER or service.Priority.TRAVEL,
        targetKey = targetKey,
        targetLabel = tostring(identity.script or "vehicle") .. " seat " .. tostring(seat),
        phase = action == "board_vehicle" and "approaching" or "selected",
        allowedActions = {
            approach_vehicle = true,
            board_vehicle = true,
            exit_vehicle = true,
            ready_weapon = true,
            lower_weapon = true,
        },
        metadata = { seat = seat, vehicleKey = keyFor(identity) },
        onCancel = cancelTransactionState,
    })
    if token == nil then return nil, beginReason, retry end
    local resource = seatResource(reservation)
    local reserved, reserveReason = service.reserve(token, resource,
        "passenger seat " .. tostring(seat))
    if reserved ~= true then
        service.fail(token, "vehicle_seat_reservation_failed", { reason = reserveReason })
        return nil, reserveReason
    end
    local claimed = reservations[reservation] == nil
    if reservations[reservation] ~= nil and reservations[reservation] ~= id then
        service.fail(token, "vehicle_seat_reserved_by_other", { seat = seat })
        return nil, "vehicle seat is reserved by another companion"
    end
    reservations[reservation] = id
    local transaction = {
        actor = actor,
        actorId = id,
        action = action,
        vehicle = vehicle,
        identity = identity,
        vehicleKey = keyFor(identity),
        seat = seat,
        reservation = reservation,
        resource = resource,
        moduleReservationClaimed = claimed,
        supervisorToken = token,
    }
    transactions[actor] = transaction
    return transaction, "started"
end

local function coordinates(value)
    local xOk, x = invoke(value, "getX")
    local yOk, y = invoke(value, "getY")
    local zOk, z = invoke(value, "getZ")
    if not xOk or not yOk then return nil end
    return finite(x, nil), finite(y, nil), zOk and finite(z, 0) or 0
end

local function doorDistanceSquared(vehicle, seat, x, y)
    local ok, distance = invoke(vehicle, "getEnterSeatDistance", seat, x, y)
    distance = ok and finite(distance, -1) or -1
    return distance >= 0 and distance or nil
end

local function availableSeat(vehicle, identity, seat, actorId)
    local installedOk, installed = invoke(vehicle, "isSeatInstalled", seat)
    local occupiedOk, occupied = invoke(vehicle, "isSeatOccupied", seat)
    if not installedOk or installed ~= true or not occupiedOk or occupied == true then
        return false
    end
    local reservation = seatKey(identity, seat)
    local owner = reservation ~= nil and reservations[reservation] or nil
    return reservation ~= nil and (owner == nil or owner == actorId)
end

local function chooseSeat(vehicle, actor, requested, identity)
    local countOk, count = invoke(vehicle, "getMaxPassengers")
    count = countOk and math.floor(finite(count, -1)) or -1
    if count < 2 or count > 32 then
        return nil, "vehicle has no bounded passenger seat"
    end
    local requestedNumber = tonumber(requested)
    local actorId = SC.Registry and SC.Registry.idOf(actor) or nil
    if requestedNumber ~= nil then
        local seat = math.floor(requestedNumber)
        -- Seat zero is the driver. Companion driving is not implemented and a
        -- follower must never displace or compete with the local player.
        if seat < 1 or seat >= count or not availableSeat(vehicle, identity, seat, actorId) then
            return nil, "requested vehicle seat is unavailable"
        end
        return seat
    end

    local actorX, actorY = coordinates(actor)
    local best, bestDistance
    for seat = 1, count - 1 do
        if availableSeat(vehicle, identity, seat, actorId) then
            local distance = actorX and doorDistanceSquared(vehicle, seat, actorX, actorY) or nil
            if best == nil or (distance ~= nil and (bestDistance == nil or distance < bestDistance)) then
                best, bestDistance = seat, distance
            end
        end
    end
    if best == nil then return nil, "vehicle has no available passenger seat" end
    return best
end

local function commandState(actor)
    if SC.Commands and type(SC.Commands.peek) == "function" then
        local ok, state = pcall(SC.Commands.peek, actor)
        if ok and type(state) == "table" then return state end
    end
    return nil
end

local function eligibleFollower(actor, vehicle)
    local state = commandState(actor)
    if type(state) ~= "table" or state.recruited ~= true
        or state.rideWithPlayer == false
        or (state.order ~= "follow" and state.order ~= "regroup") then return false end
    local vehicleOk, current = invoke(actor, "getVehicle")
    return vehicleOk and (current == nil or current == vehicle)
end

local function releaseManifest(manifest)
    if type(manifest) ~= "table" or type(manifest.identity) ~= "table" then return end
    for id, seat in pairs(manifest.assignments or {}) do
        local reservation = seatKey(manifest.identity, seat)
        if reservation ~= nil and reservations[reservation] == id then
            reservations[reservation] = nil
        end
    end
end

local function manifestCandidate(actor, player)
    local id = SC.Registry and SC.Registry.idOf(actor) or nil
    if id == nil then return nil end
    local actorX, actorY = coordinates(actor)
    local playerX, playerY = coordinates(player)
    local distance = math.huge
    if actorX ~= nil and playerX ~= nil then
        distance = (actorX - playerX) ^ 2 + (actorY - playerY) ^ 2
    end
    local bodyOk, body = invoke(actor, "getBodyDamage")
    local healthOk, health = false, 100
    if bodyOk then
        local ok, value = invoke(body, "getHealth")
        healthOk, health = ok, value
    end
    health = healthOk and finite(health, 100) or 100
    local priority = health <= 35 and 0 or health < 75 and 1 or 2
    return { actor = actor, id = id, distance = distance, priority = priority }
end

local function buildManifest(vehicle, player)
    local identity = vehicleIdentity(vehicle)
    local key = keyFor(identity)
    if key == nil then return nil, "vehicle identity is unavailable" end
    local countOk, count = invoke(vehicle, "getMaxPassengers")
    count = countOk and math.floor(finite(count, -1)) or -1
    if count < 2 or count > finite(SC.Config.get("vehicleManifestLimit"), 32) then
        return nil, "vehicle has no bounded passenger seat"
    end

    local previous = manifests[key]
    if previous then releaseManifest(previous) end
    local manifest = {
        vehicle = vehicle,
        identity = identity,
        seatCount = count,
        seatState = {},
        assignmentBySeat = {},
        assignments = {},
        actors = {},
        waiting = {},
        capacity = 0,
        assigned = 0,
    }
    local freeSeats = {}
    local occupiedIds = {}
    for seat = 1, count - 1 do
        local installedOk, installed = invoke(vehicle, "isSeatInstalled", seat)
        local occupiedOk, occupied = invoke(vehicle, "isSeatOccupied", seat)
        manifest.seatState[seat] = installedOk and installed == true
            and occupiedOk and (occupied == true and "occupied" or "free") or "missing"
        if installedOk and installed == true and occupiedOk then
            if occupied == true then
                local characterOk, character = invoke(vehicle, "getCharacter", seat)
                local id = characterOk and SC.Registry and SC.Registry.idOf(character) or nil
                if id ~= nil and eligibleFollower(character, vehicle) then
                    manifest.capacity = manifest.capacity + 1
                    manifest.assignments[id] = seat
                    manifest.assignmentBySeat[seat] = id
                    manifest.actors[id] = character
                    occupiedIds[id] = true
                    reservations[seatKey(identity, seat)] = id
                end
            else
                local reservation = reservations[seatKey(identity, seat)]
                if reservation == nil then
                    manifest.capacity = manifest.capacity + 1
                    freeSeats[#freeSeats + 1] = seat
                end
            end
        end
    end

    local candidates = {}
    local living = SC.Registry and SC.Registry.living and SC.Registry.living() or {}
    for index = 1, math.min(#living, finite(SC.Config.get("maxCompanions"), 16)) do
        local actor = living[index]
        if eligibleFollower(actor, vehicle) then
            local candidate = manifestCandidate(actor, player)
            if candidate and not occupiedIds[candidate.id] then candidates[#candidates + 1] = candidate end
        end
    end
    table.sort(candidates, function(left, right)
        if left.priority ~= right.priority then return left.priority < right.priority end
        if left.distance ~= right.distance then return left.distance < right.distance end
        return tostring(left.id) < tostring(right.id)
    end)
    table.sort(freeSeats)
    for index, candidate in ipairs(candidates) do
        local seat = freeSeats[index]
        if seat == nil then
            manifest.waiting[candidate.id] = true
        else
            manifest.assignments[candidate.id] = seat
            manifest.assignmentBySeat[seat] = candidate.id
            manifest.actors[candidate.id] = candidate.actor
            reservations[seatKey(identity, seat)] = candidate.id
        end
    end
    for _ in pairs(manifest.assignments) do manifest.assigned = manifest.assigned + 1 end
    manifests[key] = manifest
    return manifest
end

local function manifestIsCurrent(manifest, vehicle)
    if type(manifest) ~= "table" or manifest.vehicle ~= vehicle then return false end
    local countOk, count = invoke(vehicle, "getMaxPassengers")
    count = countOk and math.floor(finite(count, -1)) or -1
    if count ~= manifest.seatCount then return false end

    for seat = 1, count - 1 do
        local installedOk, installed = invoke(vehicle, "isSeatInstalled", seat)
        local occupiedOk, occupied = invoke(vehicle, "isSeatOccupied", seat)
        if not installedOk or not occupiedOk then return false end
        local installedNow = installed == true
        local assignedId = manifest.assignmentBySeat[seat]
        if assignedId ~= nil then
            local actor = manifest.actors[assignedId]
            local deadOk, dead = invoke(actor, "isDead")
            if actor == nil or SC.Registry.idOf(actor) ~= assignedId
                or (deadOk and dead == true) or not eligibleFollower(actor, vehicle)
                or not installedNow then return false end
            if occupied == true then
                local characterOk, character = invoke(vehicle, "getCharacter", seat)
                if not characterOk or character ~= actor then return false end
            elseif reservations[seatKey(manifest.identity, seat)] ~= assignedId then
                return false
            end
        else
            local prior = manifest.seatState[seat]
            if (prior == "missing") ~= (not installedNow) then return false end
            if prior == "occupied" and occupied ~= true then return false end
            if prior == "free" and occupied == true then return false end
        end
    end
    for id in pairs(manifest.waiting or {}) do
        local record = SC.Registry.byId(id)
        local actor = record and record.actor or nil
        local deadOk, dead = invoke(actor, "isDead")
        if actor == nil or (deadOk and dead == true)
            or not eligibleFollower(actor, vehicle) then return false end
    end
    return true
end

local function manifestFor(vehicle, player)
    local identity = vehicleIdentity(vehicle)
    local key = keyFor(identity)
    if key == nil then return nil, "vehicle identity is unavailable" end
    local manifest = manifests[key]
    if manifest == nil or not manifestIsCurrent(manifest, vehicle) then
        return buildManifest(vehicle, player)
    end
    return manifest
end

function vehicleService.invalidateManifests(vehicle)
    if vehicle ~= nil then
        local key = keyFor(vehicleIdentity(vehicle))
        local manifest = key and manifests[key] or nil
        if manifest then releaseManifest(manifest) manifests[key] = nil end
        return
    end
    for _, manifest in pairs(manifests) do releaseManifest(manifest) end
    manifests = {}
end

function vehicleService.assignmentFor(actor, vehicle, player)
    if not SC.Actor.isCompanion(actor) then return nil, "actor is not an active companion" end
    if not eligibleFollower(actor, vehicle) then return nil, "ride_with_player_disabled" end
    local manifest, reason = manifestFor(vehicle, player)
    if manifest == nil then return nil, reason end
    local id = SC.Registry.idOf(actor)
    local seat = manifest.assignments[id]
    if seat == nil then
        return nil, "vehicle_capacity_wait", {
            assigned = manifest.assigned,
            capacity = manifest.capacity,
            waiting = manifest.waiting,
        }
    end
    return {
        seat = seat,
        assigned = manifest.assigned,
        capacity = manifest.capacity,
        waiting = manifest.waiting,
    }
end

function vehicleService.statusFor(actor, player)
    local state = commandState(actor) or {}
    local seated, actorVehicle, actorSeat = vehicleService.isNativeSeated(actor)
    if seated and actorVehicle ~= nil then
        local stopped = select(1, stationary(actorVehicle)) == true
        local waitingForSafeExit = state.rideWithPlayer == false and not stopped
        return {
            status = waitingForSafeExit and "waiting_safe_exit" or "in_vehicle",
            seat = actorSeat,
            canExitNow = stopped,
            policyEnabled = state.rideWithPlayer ~= false,
        }
    end
    local playerOk, vehicle = invoke(player, "getVehicle")
    if not playerOk or vehicle == nil or state.rideWithPlayer == false
        or not eligibleFollower(actor, vehicle) then
        return { status = "on_foot", canExitNow = false,
            policyEnabled = state.rideWithPlayer ~= false }
    end
    local manifest = manifestFor(vehicle, player)
    if manifest == nil then
        return { status = "on_foot", canExitNow = false, policyEnabled = true }
    end
    local id = SC.Registry.idOf(actor)
    local waiting = 0
    for _ in pairs(manifest.waiting) do waiting = waiting + 1 end
    return {
        status = manifest.assignments[id] ~= nil and "approaching_vehicle" or "on_foot",
        seat = manifest.assignments[id],
        assigned = manifest.assigned,
        capacity = manifest.capacity,
        waiting = waiting,
        capacityWait = manifest.waiting[id] == true,
        canExitNow = false,
        policyEnabled = true,
    }
end

vehicleService.manifestStatus = vehicleService.statusFor

function vehicleService.canPassengerFire(actor, target, doctrine)
    if doctrine ~= "ranged_support" and doctrine ~= "weapons_free" then
        return false, "vehicle_fire_blocked_by_doctrine"
    end
    local seated, vehicle, seat = vehicleService.isNativeSeated(actor)
    if not seated or vehicle == nil or seat == nil or seat < 1 then
        return false, "vehicle_fire_requires_passenger_seat"
    end
    local doorOk, door = invoke(vehicle, "getPassengerDoor", seat)
    if not doorOk or door == nil then return false, "passenger_door_unavailable" end
    local windowOk, window = invoke(door, "findWindow")
    if not windowOk or window == nil then return false, "passenger_window_unavailable" end
    local hittableOk, hittable = invoke(window, "isHittable")
    if not hittableOk or hittable == true then return false, "passenger_window_closed" end
    local speedOk, speed = invoke(vehicle, "getCurrentSpeedKmHour")
    if not speedOk then return false, "vehicle_speed_unavailable" end
    speed = math.abs(finite(speed, math.huge))
    local maximum = doctrine == "ranged_support"
        and finite(SC.Config.get("vehicleRangedSupportMaxSpeedKph"), 15)
        or finite(SC.Config.get("vehicleWeaponsFreeMaxSpeedKph"), 30)
    if speed > maximum then return false, "vehicle_too_fast_to_fire" end
    if target == nil then return false, "vehicle_fire_target_unavailable" end
    return true, "vehicle_fire_ready", { vehicle = vehicle, seat = seat, speed = speed }
end

function vehicleService.claimPassengerShot(actor, target, doctrine)
    local ready, reason, details = vehicleService.canPassengerFire(actor, target, doctrine)
    if not ready then return false, reason end
    local timestamp = type(getTimestampMs) == "function" and tonumber(getTimestampMs()) or nil
    local now = timestamp or math.floor((os.clock and os.clock() or 0) * 1000)
    local last = tonumber(lastVehicleShotAt[details.vehicle]) or -math.huge
    local spacing = math.max(0, finite(SC.Config.get("vehicleFireSpacingMs"), 240))
    if now - last < spacing then return false, "vehicle_fire_lane_busy" end
    lastVehicleShotAt[details.vehicle] = now
    return true, "vehicle_fire_lane_claimed", details
end

local function rollbackNativeEntry(actor, vehicle)
    local currentOk, current = invoke(actor, "getVehicle")
    if currentOk and current == nil then return true end
    if currentOk and current ~= vehicle then return false end
    local exitOk, exited = invoke(vehicle, "exit", actor)
    local verifyOk, after = invoke(actor, "getVehicle")
    return exitOk and exited == true and verifyOk and after == nil
end

local function nativeBoard(actor, vehicle, seat)
    local enteredOk, entered = invoke(vehicle, "enter", seat, actor)
    if not enteredOk or entered ~= true then
        if rollbackNativeEntry(actor, vehicle) then
            return false, "native vehicle entry was rejected", true
        end
        return false, "native vehicle entry failed and rollback was not verified", false
    end
    local vehicleOk, currentVehicle = invoke(actor, "getVehicle")
    local seatOk, currentSeat = invoke(vehicle, "getSeat", actor)
    if not vehicleOk or currentVehicle ~= vehicle or not seatOk or tonumber(currentSeat) ~= seat then
        if rollbackNativeEntry(actor, vehicle) then
            return false, "native vehicle entry could not be verified; rollback verified", true
        end
        return false, "native vehicle entry and rollback could not be verified", false
    end
    return true, "native_seat", false
end

local function safeSquare(square)
    if square == nil then return false end
    local solidOk, solid = invoke(square, "isSolid")
    local transOk, trans = invoke(square, "isSolidTrans")
    local floorOk, floor = invoke(square, "TreatAsSolidFloor")
    local freeOk, free = invoke(square, "isFree", true)
    return solidOk and solid ~= true and transOk and trans ~= true
        and floorOk and floor == true and freeOk and free == true
end

local function nearbyVehicleSquare(vehicle, seat, actor)
    local xOk, x = invoke(vehicle, "getX")
    local yOk, y = invoke(vehicle, "getY")
    local zOk, z = invoke(vehicle, "getZ")
    local cellOk, cell = invoke(vehicle, "getCell")
    if (not cellOk or cell == nil) and actor ~= nil then
        cellOk, cell = invoke(actor, "getCell")
    end
    if not xOk or not yOk or not zOk or not cellOk or cell == nil then
        return nil, "vehicle world position is unavailable"
    end
    local actorX, actorY = coordinates(actor)
    local radius = math.max(2, math.floor(finite(SC.Config.get("vehicleApproachRadius"), 4)))
    local baseX, baseY, floorZ = math.floor(x), math.floor(y), math.floor(z)
    local best, bestDoorDistance, bestActorDistance
    for dx = -radius, radius do
        for dy = -radius, radius do
            local ok, square = invoke(cell, "getGridSquare", baseX + dx, baseY + dy, floorZ)
            if ok and safeSquare(square) then
                local squareX, squareY = coordinates(square)
                if squareX == nil then
                    squareX, squareY = baseX + dx + 0.5, baseY + dy + 0.5
                else
                    -- Grid-square coordinates identify the tile corner; a
                    -- standing character occupies its center.
                    squareX, squareY = math.floor(squareX) + 0.5, math.floor(squareY) + 0.5
                end
                local doorDistance = seat ~= nil
                    and doorDistanceSquared(vehicle, seat, squareX, squareY) or nil
                doorDistance = doorDistance or (dx * dx + dy * dy)
                local actorDistance = actorX and ((squareX - actorX) ^ 2 + (squareY - actorY) ^ 2) or 0
                if best == nil or doorDistance < bestDoorDistance
                    or (doorDistance == bestDoorDistance and actorDistance < bestActorDistance) then
                    best, bestDoorDistance, bestActorDistance = square, doorDistance, actorDistance
                end
            end
        end
    end
    if best == nil then return nil, "no safe loaded passenger-door square" end
    return best
end

local function exitSquare(vehicle, player, seat)
    return nearbyVehicleSquare(vehicle, seat, player)
end

stationary = function(vehicle)
    local speedOk, speed = invoke(vehicle, "getCurrentSpeedKmHour")
    if not speedOk then return false, "vehicle speed is unavailable" end
    speed = math.abs(finite(speed, math.huge))
    local maximum = math.max(0, finite(SC.Config.get("vehicleBoardMaxSpeedKph"), 0.5))
    if speed > maximum then return false, "vehicle is moving" end
    return true
end

function vehicleService.preflightBoard(actor, vehicle, requestedSeat)
    if not SC.Actor.isCompanion(actor) then
        return nil, "actor is not an active companion"
    end
    if vehicle == nil then return nil, "vehicle is required" end
    local currentOk, current = invoke(actor, "getVehicle")
    if not currentOk or current ~= nil then
        return nil, "actor is already in a vehicle or native state is unavailable"
    end
    local identity = vehicleIdentity(vehicle)
    if identity == nil then return nil, "vehicle identity is unavailable" end
    local stopped, stoppedReason = stationary(vehicle)
    if not stopped then return nil, stoppedReason end
    local actorX, actorY, actorZ = coordinates(actor)
    if actorX == nil then return nil, "companion world position is unavailable" end
    if math.floor(actorZ) ~= math.floor(identity.z) then
        return nil, "companion and vehicle are on different floors"
    end
    local seat, seatReason = chooseSeat(vehicle, actor, requestedSeat, identity)
    if seat == nil then return nil, seatReason end
    local entranceDistance = doorDistanceSquared(vehicle, seat, actorX, actorY)
    if entranceDistance == nil then return nil, "passenger door position is unavailable" end
    if entranceDistance > finite(SC.Config.get("vehicleBoardRangeSquared"), 2.56) then
        return nil, "companion is not at the passenger door"
    end
    local reservation = seatKey(identity, seat)
    local actorId = SC.Registry.idOf(actor)
    if actorId == nil then return nil, "companion identity is unavailable" end
    if reservations[reservation] ~= nil and reservations[reservation] ~= actorId then
        return nil, "vehicle seat is reserved by another companion"
    end
    return {
        actorId = actorId,
        vehicle = vehicle,
        identity = identity,
        vehicleKey = keyFor(identity),
        seat = seat,
        entranceDistance = entranceDistance,
        reservation = reservation,
    }
end

function vehicleService.isStationary(vehicle)
    return stationary(vehicle)
end

function vehicleService.boardingSquare(actor, vehicle, requestedSeat)
    if not SC.Actor.isCompanion(actor) then
        return nil, nil, "actor is not an active companion"
    end
    if vehicle == nil then return nil, nil, "vehicle is required" end
    local identity = vehicleIdentity(vehicle)
    if identity == nil then return nil, nil, "vehicle identity is unavailable" end
    local seat, reason = chooseSeat(vehicle, actor, requestedSeat, identity)
    if seat == nil then return nil, nil, reason end
    local square, squareReason = nearbyVehicleSquare(vehicle, seat, actor)
    if square == nil then return nil, nil, squareReason end
    return square, seat
end

function vehicleService.isNativeSeated(actor)
    local vehicleOk, vehicle = invoke(actor, "getVehicle")
    if not vehicleOk or vehicle == nil then return false, nil, nil end
    local seatOk, seat = invoke(vehicle, "getSeat", actor)
    seat = seatOk and math.floor(finite(seat, -1)) or -1
    if seat < 0 then return false, vehicle, nil end
    local characterOk, character = invoke(vehicle, "getCharacter", seat)
    if characterOk and character ~= actor then return false, vehicle, seat end
    return true, vehicle, seat
end

function vehicleService.isSeatReserved(vehicle, seat)
    local identity = vehicleIdentity(vehicle)
    local reservation = seatKey(identity, math.floor(finite(seat, -1)))
    if reservation == nil then return false, nil end
    return reservations[reservation] ~= nil, reservations[reservation]
end

function vehicleService.beginBoarding(actor, vehicle, requestedSeat, intent)
    if vehicle == nil then return nil, "vehicle is required" end
    local identity = vehicleIdentity(vehicle)
    if identity == nil then return nil, "vehicle identity is unavailable" end
    local seat, reason = chooseSeat(vehicle, actor, requestedSeat, identity)
    if seat == nil then return nil, reason end
    local stopped, stopReason = stationary(vehicle)
    if stopped ~= true then return nil, stopReason end
    return beginTransaction(actor, vehicle, seat, "board_vehicle", intent)
end

function vehicleService.cancelTransaction(actor, reason)
    local transaction = actor and transactions[actor] or nil
    if transaction == nil then return true, "no_vehicle_transaction" end
    local service = supervisor()
    if service == nil or type(service.cancel) ~= "function" then
        cancelTransactionState(actor, reason, transaction.supervisorToken)
        return true, "vehicle_transaction_cleared"
    end
    return service.cancel(actor, reason or "vehicle_transaction_cancelled", nil, true)
end

function vehicleService.failTransaction(actor, reason, detail)
    local transaction = actor and transactions[actor] or nil
    if transaction == nil then return false, "no_vehicle_transaction" end
    if transaction.moduleReservationClaimed == true and actorIsOnFoot(actor)
        and reservations[transaction.reservation] == transaction.actorId then
        reservations[transaction.reservation] = nil
    end
    return finishTransaction(transaction, false,
        reason or "vehicle_transaction_failed", detail)
end

function vehicleService.transactionStatus(actor)
    local transaction = actor and transactions[actor] or nil
    if not transactionIsCurrent(transaction) then return nil end
    local service = supervisor()
    local snapshot = service and service.snapshot and service.snapshot(actor) or nil
    return {
        action = transaction.action,
        phase = snapshot and snapshot.phase or "unknown",
        vehicle = transaction.vehicle,
        seat = transaction.seat,
        targetKey = snapshot and snapshot.targetKey or nil,
    }
end

function vehicleService.board(actor, vehicle, requestedSeat, intent)
    intent = type(intent) == "table" and intent or {}
    local supplied = intent.preflight
    if requestedSeat == nil and type(supplied) == "table" then
        requestedSeat = supplied.seat
    end
    local prepared, prepareReason = vehicleService.preflightBoard(actor, vehicle, requestedSeat)
    if prepared == nil then
        vehicleService.failTransaction(actor, "vehicle_board_preflight_failed", {
            reason = prepareReason,
        })
        return false, prepareReason
    end
    if supplied ~= nil and (type(supplied) ~= "table" or supplied.actorId ~= prepared.actorId
        or supplied.vehicle ~= vehicle or supplied.seat ~= prepared.seat
        or supplied.reservation ~= prepared.reservation
        or supplied.vehicleKey ~= prepared.vehicleKey) then
        vehicleService.failTransaction(actor, "vehicle_board_preflight_stale")
        return false, "vehicle boarding preflight is stale or belongs to another actor"
    end
    local transaction = transactions[actor]
    if not transactionIsCurrent(transaction) or transaction.action ~= "board_vehicle"
        or transaction.vehicle ~= vehicle or transaction.seat ~= prepared.seat then
        transaction, prepareReason = beginTransaction(actor, vehicle, prepared.seat,
            "board_vehicle", intent)
        if transaction == nil then return false, prepareReason end
    end
    intent.supervisorToken = transaction.supervisorToken
    local reservation = prepared.reservation
    local id = prepared.actorId
    if SC.Actor.stop(actor) ~= true then
        finishTransaction(transaction, false, "vehicle_board_stop_failed")
        return false, "companion could not stop safely at the passenger door"
    end
    reservations[reservation] = id

    local service = supervisor()
    service.transition(transaction.supervisorToken, "committing", {
        seat = prepared.seat, vehicleKey = prepared.vehicleKey,
    })

    local entered, nativeReason, safeFallback = nativeBoard(actor, vehicle, prepared.seat)
    if entered then
        service.transition(transaction.supervisorToken, "verifying", {
            result = nativeReason, seat = prepared.seat,
        })
        local record = SC.Registry.byId(id)
        if record ~= nil then
            record.runtime = type(record.runtime) == "table" and record.runtime or {}
            record.runtime.vehicle = { native = true, vehicle = vehicle, seat = prepared.seat }
        end
        return finishTransaction(transaction, true, nativeReason, {
            vehicleKey = prepared.vehicleKey, seat = prepared.seat, native = true,
        })
    end

    if safeFallback ~= true then
        if transaction.moduleReservationClaimed == true then reservations[reservation] = nil end
        return finishTransaction(transaction, false, nativeReason, {
            rollbackVerified = false, preserveReservation = true,
        })
    end
    if intent.allowVirtualSeat ~= true then
        if transaction.moduleReservationClaimed == true then reservations[reservation] = nil end
        return finishTransaction(transaction, false, nativeReason, {
            rollbackVerified = true,
        })
    end
    if SC.Persistence == nil or type(SC.Persistence.captureRecord) ~= "function" then
        if transaction.moduleReservationClaimed == true then reservations[reservation] = nil end
        return finishTransaction(transaction, false,
            "persistence adapter is unavailable for virtual seating")
    end
    local record = SC.Registry.byId(id)
    local saved, captureReason = SC.Persistence.captureRecord(record, {
        stored = true,
        vehicle = prepared.identity,
        seat = prepared.seat,
    })
    if saved == nil then
        if transaction.moduleReservationClaimed == true then reservations[reservation] = nil end
        return finishTransaction(transaction, false, captureReason)
    end
    record.runtime = type(record.runtime) == "table" and record.runtime or {}
    record.runtime.lastStableSnapshot = saved
    local removed, removedRecord = SC.Actor.remove(actor)
    if not removed then
        if transaction.moduleReservationClaimed == true then reservations[reservation] = nil end
        return finishTransaction(transaction, false, tostring(removedRecord))
    end
    storedById[id] = {
        id = id,
        record = saved,
        vehicle = prepared.identity,
        seat = prepared.seat,
        reservation = reservation,
    }
    service.transition(transaction.supervisorToken, "verifying", {
        stored = true, seat = prepared.seat,
    })
    return finishTransaction(transaction, true, "virtual_seat", {
        vehicleKey = prepared.vehicleKey, seat = prepared.seat, stored = true,
    })
end

function vehicleService.exit(actor, vehicle, requestedSeat, intent)
    intent = type(intent) == "table" and intent or {}
    if not SC.Actor.isCompanion(actor) then
        return false, "actor is not an active companion"
    end
    local currentOk, current = invoke(actor, "getVehicle")
    vehicle = vehicle or (currentOk and current or nil)
    if vehicle == nil then return false, "actor is not in a native vehicle seat" end
    local stopped, stopReason = stationary(vehicle)
    if stopped ~= true then return false, stopReason or "vehicle is moving" end
    local seatOk, seat = invoke(vehicle, "getSeat", actor)
    local identity = vehicleIdentity(vehicle)
    if not seatOk or finite(seat, -1) < 0 then return false, "native vehicle seat is invalid" end
    seat = math.floor(seat)
    local transaction = transactions[actor]
    if not transactionIsCurrent(transaction) or transaction.action ~= "exit_vehicle"
        or transaction.vehicle ~= vehicle or transaction.seat ~= seat then
        transaction, stopReason = beginTransaction(actor, vehicle, seat,
            "exit_vehicle", intent)
        if transaction == nil then return false, stopReason end
    end
    intent.supervisorToken = transaction.supervisorToken
    local square, squareReason = exitSquare(vehicle, nil, seat)
    if square == nil then
        return finishTransaction(transaction, false, squareReason)
    end
    if SC.Actor.stop(actor) ~= true then
        finishTransaction(transaction, false, "vehicle_exit_stop_failed")
        return false, "companion could not stop before vehicle exit"
    end
    local service = supervisor()
    service.transition(transaction.supervisorToken, "committing", { seat = seat })
    local exitedOk, exited = invoke(vehicle, "exit", actor)
    if not exitedOk or exited ~= true then
        return finishTransaction(transaction, false, "native vehicle exit was rejected")
    end
    service.transition(transaction.supervisorToken, "verifying", { seat = seat })
    local verifyOk, after = invoke(actor, "getVehicle")
    if not verifyOk or after ~= nil then
        return finishTransaction(transaction, false,
            "native vehicle exit could not be verified", { preserveReservation = true })
    end
    local recovered, recoverReason = SC.Actor.recover(actor, square)
    if recovered ~= true then
        local rollbackOk, rollbackEntered = invoke(vehicle, "enter", seat, actor)
        local rollbackVehicleOk, rollbackVehicle = invoke(actor, "getVehicle")
        if rollbackOk and rollbackEntered == true and rollbackVehicleOk and rollbackVehicle == vehicle then
            return finishTransaction(transaction, false,
                "native vehicle exit placement failed; seat rollback verified: "
                    .. tostring(recoverReason), { preserveReservation = true })
        end
        return finishTransaction(transaction, false,
            "native vehicle exit placement and rollback failed: " .. tostring(recoverReason),
            { preserveReservation = true })
    end
    if seatOk and identity ~= nil then reservations[seatKey(identity, seat)] = nil end
    local record = SC.Registry.byId(SC.Registry.idOf(actor))
    if record ~= nil then record.runtime.vehicle = nil end
    vehicleService.invalidateManifests(vehicle)
    return finishTransaction(transaction, true, "native_exit", {
        vehicleKey = keyFor(identity), seat = seat,
    })
end

-- Number of virtual passengers still stored for a vehicle key. The runtime uses
-- this to keep retrying placement instead of consuming the exit after one attempt
-- (a missing exit square or a temporary spawn rejection is not permanent). (LF-04)
local function storedRemainingForKey(key)
    if key == nil then return 0 end
    local remaining = 0
    for _, stored in pairs(storedById) do
        if keyFor(stored.vehicle) == key then remaining = remaining + 1 end
    end
    return remaining
end

function vehicleService.storedCountFor(vehicle)
    return storedRemainingForKey(keyFor(vehicleIdentity(vehicle)))
end

function vehicleService.restoreForVehicle(vehicle, player)
    local identity = vehicleIdentity(vehicle)
    local key = keyFor(identity)
    if key == nil then return 0, 0 end
    vehicleService.invalidateManifests(vehicle)
    if SC.Persistence == nil or type(SC.Persistence.restoreAt) ~= "function" then
        return 0, storedRemainingForKey(key)
    end
    local square = exitSquare(vehicle, player, nil)
    -- No safe loaded exit square is a temporary condition: leave the passengers
    -- stored and report how many still await placement so the caller retries.
    if square == nil then return 0, storedRemainingForKey(key) end
    local restored = 0
    local ids = {}
    for id, stored in pairs(storedById) do
        if keyFor(stored.vehicle) == key then ids[#ids + 1] = id end
    end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local stored = storedById[id]
        if SC.Registry.byId(id) ~= nil then
            storedById[id] = nil
            reservations[stored.reservation] = nil
        elseif stored.spawnTicket ~= nil then
            -- Placement is already in flight; restorePulse owns this ticket. Do not
            -- launch a second spawn for the same passenger.
        else
            local actor, reason, ticket = SC.Persistence.restoreAt(stored.record, square)
            if actor ~= nil then
                storedById[id] = nil
                reservations[stored.reservation] = nil
                restored = restored + 1
            elseif reason == "spawn_pending" and ticket ~= nil then
                stored.spawnTicket = ticket
            else
                SC.Diagnostics.report("vehicle", id, "virtual-seat restore deferred", reason)
            end
        end
    end
    return restored, storedRemainingForKey(key)
end

function vehicleService.restorePulse()
    local restored = 0
    local ids = {}
    for id, stored in pairs(storedById) do
        if stored.spawnTicket ~= nil then ids[#ids + 1] = id end
    end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local stored = storedById[id]
        if stored ~= nil and stored.spawnTicket ~= nil then
            local actor, reason = SC.Actor.pollSpawn(stored.spawnTicket)
            if actor ~= nil then
                storedById[id] = nil
                reservations[stored.reservation] = nil
                restored = restored + 1
            elseif reason ~= "spawn_pending" then
                stored.spawnTicket = nil
                SC.Diagnostics.report("vehicle", id, "virtual-seat restore deferred", reason)
            end
        end
    end
    return restored
end

function vehicleService.importStored(record)
    if type(record) ~= "table" or not SC.Registry.isValidId(record.id)
        or type(record.vehicle) ~= "table" or record.vehicle.stored ~= true
        or type(record.vehicle.vehicle) ~= "table" then
        return false, "invalid virtual vehicle save record"
    end
    if SC.Registry.byId(record.id) ~= nil or storedById[record.id] ~= nil then
        return false, "duplicate vehicle-stored companion id"
    end
    local seat = math.floor(finite(record.vehicle.seat, -1))
    local reservation = seatKey(record.vehicle.vehicle, seat)
    if seat < 0 or reservation == nil or reservations[reservation] ~= nil then
        return false, "invalid or occupied virtual seat reservation"
    end
    storedById[record.id] = {
        id = record.id,
        record = record,
        vehicle = record.vehicle.vehicle,
        seat = seat,
        reservation = reservation,
    }
    reservations[reservation] = record.id
    return true
end

function vehicleService.importNativeSeat(record)
    if type(record) ~= "table" or type(record.vehicle) ~= "table"
        or record.vehicle.stored ~= false then
        return false, "invalid native-seated companion save record"
    end
    -- A Java actor cannot be trusted to survive a mod-managed load in a native
    -- seat. Convert the stable record to the same reserved virtual-seat form
    -- used by a verified fallback, without mutating the caller on failure.
    local converted = {}
    for key, value in pairs(record) do converted[key] = value end
    converted.vehicle = {}
    for key, value in pairs(record.vehicle) do converted.vehicle[key] = value end
    converted.vehicle.stored = true
    local imported, reason = vehicleService.importStored(converted)
    if not imported then return false, reason end
    return true, "native seat converted to a reserved virtual seat"
end

function vehicleService.exportStored()
    local result = {}
    for id, stored in pairs(storedById) do result[id] = stored.record end
    return result
end

function vehicleService.stateFor(actor)
    local vehicleOk, vehicle = invoke(actor, "getVehicle")
    if not vehicleOk or vehicle == nil then return nil end
    local identity = vehicleIdentity(vehicle)
    local seatOk, seat = invoke(vehicle, "getSeat", actor)
    if identity == nil or not seatOk then return nil end
    return { stored = false, vehicle = identity, seat = math.floor(finite(seat, -1)) }
end

function vehicleService.storedCount()
    local count = 0
    for _ in pairs(storedById) do count = count + 1 end
    return count
end

function vehicleService.contains(id)
    return storedById[id] ~= nil
end

function vehicleService.reset()
    local activeActors = {}
    for actor in pairs(transactions) do activeActors[#activeActors + 1] = actor end
    for _, actor in ipairs(activeActors) do
        vehicleService.cancelTransaction(actor, "vehicle_reset")
    end
    for _, stored in pairs(storedById) do
        if stored.spawnTicket ~= nil and SC.Actor ~= nil
            and type(SC.Actor.cancelSpawn) == "function" then
            pcall(SC.Actor.cancelSpawn, stored.spawnTicket)
        end
    end
    storedById = {}
    reservations = {}
    manifests = {}
    transactions = setmetatable({}, { __mode = "k" })
    seatResources = {}
    lastVehicleShotAt = setmetatable({}, { __mode = "k" })
end

return vehicleService
