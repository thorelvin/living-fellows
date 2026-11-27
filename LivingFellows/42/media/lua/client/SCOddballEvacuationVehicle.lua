-- SPDX-License-Identifier: MIT
-- The Evacuation owns the exact car explicitly donated by the player.
local SC = LivingFellows
local Vehicle = {}
SC.OddballEvacuationVehicle = Vehicle

local MARKER = "SC_EvacuationDonation"
local MAX_DISTANCE = 25
local EXIT_DISTANCE = 30
local DRIVER_STAGE_ACTION = "evacuation_driver_stage"
local jobs = setmetatable({}, { __mode = "k" })

local function U() return SC.GameplayUtil end
local function call(object, method, ...)
    return U().call(object, method, ...)
end

local function integer(value, low, high)
    return type(value) == "number" and value >= low and value <= high
        and value == math.floor(value)
end

local function point(object)
    local x, y, z = U().position(object)
    if x and y and z then return { x = x, y = y, z = z } end
end

local function distanceSquared(a, b)
    return (a.x - b.x)^2 + (a.y - b.y)^2
end

local function native(method, ...)
    if not SCSplitScreenProbe then return nil end
    local okay, value = pcall(SCSplitScreenProbe[method], ...)
    if okay then return value end
end

function Vehicle.available()
    if type(isClient) == "function" and isClient() or type(isServer) == "function" and isServer() then
        return false
    end
    return SC.Driving and SC.Driving.available() == true and SC.Vehicle ~= nil
        and SC.ExpeditionCar ~= nil and SC.TaxiService ~= nil and SC.HomeTrip ~= nil and SC.Navigation ~= nil
        and SCSplitScreenProbe ~= nil and SCSplitScreenProbe.vehicleRetirementStatus ~= nil
        and type(removeVehicle) == "function" and native("homeVehicleSaveCapability") == true
end

local function actors(group, includingDead)
    local actor = includingDead and SC.OddballKit.recordActor or SC.OddballKit.livingActor
    return actor(group, 1), actor(group, 2)
end

local function claimId(group) return group.id .. ":evacuation" end

local function state(group)
    local runtime = jobs[group]
    if not runtime then
        runtime = {}
        jobs[group] = runtime
    end
    return runtime
end

local function stableVehicle(group)
    return group and group.oddball and group.oddball.vehicle
end

local function marker(car)
    local data, readable = call(car, "getModData")
    if not readable or type(data) ~= "table" then return nil, nil end
    return data[MARKER], data
end

local function matches(car, value)
    return car ~= nil and call(car, "getSqlId") == value.sqlId
        and call(car, "getScriptName") == value.script and marker(car) == value.token
end

local function occupancy(car, joy, brock, passengerSeat)
    local count = call(car, "getMaxPassengers")
    if not integer(count, 2, 32) then return nil end
    for seat = 0, count - 1 do
        local occupant, read = call(car, "getCharacter", seat)
        local permitted = (seat == 0 and joy) or (seat == passengerSeat and brock) or nil
        if not read or occupant ~= nil and occupant ~= permitted then return nil end
    end
    return count
end

local function doorUnlocked(car, seat)
    local part, partRead = call(car, "getPassengerDoor", seat)
    if not partRead then return false end
    if part == nil then return true end
    local door, doorRead = call(part, "getDoor")
    return doorRead and (door == nil or call(door, "isLocked") == false)
end

local function untowed(car)
    local towing, readTowing = call(car, "getVehicleTowing")
    local tow, readTow = call(car, "getVehicleTowedBy")
    return readTowing and readTow and towing == nil and tow == nil
end

local function otherClaim(car, sqlId)
    if SC.TaxiCab and SC.TaxiCab.isOwned(car) then return true end
    local pickup = SC.PickupService and SC.PickupService.current()
    if pickup and pickup.carSqlId == sqlId then return true end
    local mission = SC.ExpeditionPrototype and SC.ExpeditionPrototype.current()
    local scout = mission and mission.scout
    if scout and (scout.vehicle and scout.vehicle.sqlId == sqlId
        or scout.home and scout.home.vehicleSqlId == sqlId) then return true end
    if SC.Commands and SC.Commands.peekExisting and SC.Registry and SC.Registry.living then
        for _, actor in ipairs(SC.Registry.living()) do
            local order = SC.Commands.peekExisting(actor)
            if order and order.recruited and order.order == "follow"
                and tonumber(order.followCarSqlId) == sqlId then return true end
        end
    end
    return false
end

local function departure(car, value)
    return SC.TaxiService.departureGoal(car, value, function(origin, target)
        return SC.ExpeditionCar.planRoadAccess(car, origin, target, true)
    end)
end

local function distinctDriverSquares(driver, passenger)
    if not driver or not passenger then return {} end
    local used, distinct = {}, {}
    for _, square in ipairs(passenger) do
        local key = U().squareKey(square)
        if key then used[key] = true end
    end
    for _, square in ipairs(driver) do
        if not used[U().squareKey(square)] then distinct[#distinct + 1] = square end
    end
    return distinct
end

local function inspect(group, car, joy, brock, anchor)
    local at = point(car)
    if not at or at.z ~= 0 or distanceSquared(at, anchor) > MAX_DISTANCE^2 then return nil end
    local sqlId, script = call(car, "getSqlId"), call(car, "getScriptName")
    local tagged, data = marker(car)
    -- A cancelled car may have streamed out before its old marker could be cleared.
    local ours = type(tagged) == "string" and not stableVehicle(group)
        and tagged:sub(1, #claimId(group) + 1) == claimId(group) .. ":"
    if not integer(sqlId, 1, 2147483647) or type(script) ~= "string" or script == ""
        or not data or tagged ~= nil and not ours or not untowed(car)
        or SC.Vehicle.serviceClaim(car) or otherClaim(car, sqlId)
        or SC.Vehicle.isStationary(car) ~= true or call(car, "isEngineRunning") ~= true then
        return nil
    end
    local count = occupancy(car)
    if not count or not doorUnlocked(car, 0) then return nil end
    local driver = SC.Vehicle.boardingSquares(joy, car, 0, true)
    if not driver then return nil end
    for seat = 0, count - 1 do
        if SC.Vehicle.isSeatReserved(car, seat) then return nil end
    end
    for seat = 1, count - 1 do
        local passenger = doorUnlocked(car, seat) and SC.Vehicle.boardingSquares(brock, car, seat, false)
        if #distinctDriverSquares(driver, passenger) > 0 then
            return { car = car, sqlId = sqlId, script = script, seat = seat, origin = at,
                label = SC.ExpeditionCar.displayName(car), distance = math.sqrt(distanceSquared(at, anchor)) }
        end
    end
end

local function findCandidate(group, player, expectedSqlId)
    if not player or not Vehicle.available() then return nil, "evacuation_driving_unavailable" end
    local joy, brock = actors(group)
    if not joy or not brock then return nil, "evacuation_crew_unavailable" end
    local anchor = group.house and (group.house.primaryEntry or group.house.anchor)
    if not anchor then return nil, "evacuation_house_unavailable" end
    local candidates = {}
    if expectedSqlId ~= nil then
        local car = SC.Vehicle.loadedBySqlId(expectedSqlId)
        if car then candidates[1] = inspect(group, car, joy, brock, anchor) end
    else
        for _, car in ipairs(SC.Vehicle.loadedVehicles()) do
            local report = inspect(group, car, joy, brock, anchor)
            if report then candidates[#candidates + 1] = report end
        end
        table.sort(candidates, function(a, b)
            return a.distance < b.distance or a.distance == b.distance and a.sqlId < b.sqlId
        end)
    end
    for _, report in ipairs(candidates) do
        local goal, _, entry = departure(report.car, { dropoff = report.origin })
        if goal and entry then
            report.goal, report.entry = goal, entry
            return report
        end
    end
    return nil, "evacuation_no_ready_car"
end

local function publicReport(report)
    return { sqlId = report.sqlId, seat = report.seat, label = report.label, distance = report.distance }
end

function Vehicle.candidate(group, player, expectedSqlId)
    local report, why = findCandidate(group, player, expectedSqlId)
    return report and publicReport(report), why
end

local function claim(group, car, value)
    local existing = SC.Vehicle.serviceClaim(car)
    if existing and existing.requestId == claimId(group) then return true end
    return SC.Vehicle.reserveService(claimId(group), car,
        { [value.joyId] = 0, [value.brockId] = value.seat })
end

function Vehicle.accept(group, player, expectedSqlId)
    if not integer(expectedSqlId, 1, 2147483647) or stableVehicle(group) then
        return false, "evacuation_vehicle_changed"
    end
    local report, why = findCandidate(group, player, expectedSqlId)
    if not report then return false, why end
    local story = group.oddball
    local joy, brock = actors(group)
    local joyId, brockId = U().idOf(joy), U().idOf(brock)
    local attempt = (story.vehicleAttempt or 0) + 1
    local value = { sqlId = report.sqlId, script = report.script, seat = report.seat,
        joyId = joyId, brockId = brockId, origin = report.origin, goal = report.goal, entry = report.entry,
        token = claimId(group) .. ":" .. tostring(attempt) }
    if not joyId or not brockId then return false, "evacuation_crew_unavailable" end
    local reserved, reason = claim(group, report.car, value)
    if not reserved then return false, reason end
    local previous, data = marker(report.car)
    data[MARKER] = value.token
    if not matches(report.car, value) then
        data[MARKER] = previous
        SC.Vehicle.releaseService(claimId(group))
        return false, "evacuation_car_marker_unavailable"
    end
    story.vehicleAttempt, story.vehicle, story.stage = attempt, value, "boarding"
    jobs[group] = { car = report.car }
    return true, publicReport(report)
end

local function seated(actor, car, seat)
    if not actor then return false end
    local aboard, actual, index = SC.Vehicle.isNativeSeated(actor)
    return aboard == true and actual == car and index == seat
end

local function engineReady(car, joy)
    return call(car, "isEngineRunning") == true or call(car, "isHotwired") == true
        or call(car, "isKeysInIgnition") == true or SC.Driving.hasKey(joy, car)
end

local function stopDriver(joy, reason)
    if not joy then return true end
    return SC.Driving.stop(joy, reason)
end

local function exitIfAboard(actor, car)
    if actor and call(actor, "getVehicle") == car then return SC.Vehicle.exit(actor, car) end
    return true
end

local function clearApproach(actor, car, reason)
    if not actor then return true end
    local transaction = SC.Vehicle.transactionStatus(actor)
    if transaction and transaction.vehicle == car and transaction.action == "board_vehicle" then
        return SC.Vehicle.cancelTransaction(actor, reason)
    end
    return true
end

local function clearDriverStage(joy, reason)
    if not joy then return end
    local navigation = SC.Navigation.peek(joy)
    if navigation and navigation.goalAction == DRIVER_STAGE_ACTION then
        SC.Navigation.cancel(joy, reason)
    end
end

function Vehicle.cancel(group, reason)
    local value = stableVehicle(group)
    if not value then return true end
    if value.retirement or value.removed then return false, "evacuation_retirement_committed" end
    reason = reason or "evacuation_cancelled"
    local runtime = state(group)
    local car = SC.Vehicle.loadedBySqlId(value.sqlId)
    local joy, brock = actors(group, true)
    local stopped, why = stopDriver(joy, reason)
    if not stopped then return false, why end
    clearDriverStage(joy, reason)
    for _, actor in pairs({ joy, brock }) do
        local cleared, clearReason = clearApproach(actor, runtime.car or car, reason)
        if not cleared then return false, clearReason end
    end
    if car and matches(car, value) then
        if not SC.Vehicle.isStationary(car) then return false, "evacuation_car_moving" end
        for _, actor in pairs({ joy, brock }) do
            local exited, exitReason = exitIfAboard(actor, car)
            if not exited then return false, exitReason end
        end
        local _, data = marker(car)
        data[MARKER] = nil
    elseif (joy and call(joy, "getVehicle") ~= nil) or (brock and call(brock, "getVehicle") ~= nil) then
        return false, "evacuation_car_still_occupied"
    end
    if runtime.ticket then native("cancelHomeVehicleSave", runtime.ticket) end
    SC.Vehicle.releaseService(claimId(group))
    group.oddball.vehicle, jobs[group] = nil, nil
    return true
end

local function snapshot(actor)
    local record = SC.Registry.byId(U().idOf(actor))
    local runtime = record and record.runtime
    return runtime and (runtime.senses and runtime.senses.current or runtime.snapshot) or {}
end

local function approach(actor, car, value, seat)
    if not doorUnlocked(car, seat) then return false, "evacuation_car_door_locked" end
    return SC.ExpeditionCar.boardMember(actor, { car = car, sqlId = value.sqlId,
        seat = seat, gait = "walk" }, snapshot(actor))
end

-- Joy starts in the only doorway. Let her reach the driver side on foot
-- before Brock tries to pass her, then keep that passenger's seat first.
local function stageDriver(runtime, car, value, joy, brock)
    local at = point(car)
    if runtime.driverStage and at
        and distanceSquared(at, runtime.driverStage.origin) <= 0.25^2
        and U().arrived(joy, runtime.driverStage.contact, { targetKind = "square", distance = 0.35 }) then
        return true
    end
    runtime.driverStage = nil
    if not at then return false, "evacuation_car_position_missing" end
    local driver = SC.Vehicle.boardingSquares(joy, car, 0, true)
    local passenger = SC.Vehicle.boardingSquares(brock, car, value.seat, false)
    local contacts = distinctDriverSquares(driver, passenger)
    if #contacts == 0 then return false, "evacuation_driver_contact_unavailable" end
    local reached, reason, square = SC.Navigation.requestAny(joy, contacts, "walk", {
        action = DRIVER_STAGE_ACTION, object = car, snapshot = snapshot(joy),
        arrivalDistance = 0.35, continuousApproach = true, preferVerifiedPath = true,
        verifiedSelectedGoal = true,
    })
    local contact = reached and reason == "arrived" and point(square)
    if contact and U().arrived(joy, contact, { targetKind = "square", distance = 0.35 }) then
        runtime.driverStage = { origin = at, contact = contact }
        clearDriverStage(joy, "evacuation_driver_staged")
        return true
    end
    return false, reason or "evacuation_driver_approaching"
end

local function board(group, car, value, joy, brock, current)
    if not SC.Vehicle.isStationary(car) or not occupancy(car, joy, brock, value.seat) then
        return "pending", "evacuation_car_unavailable"
    end
    if not engineReady(car, joy) then
        return value.moved and "pending" or "replacement", "evacuation_car_needs_key"
    end
    local reserved, why = claim(group, car, value)
    if not reserved then return "pending", why end
    local runtime = state(group)
    if current < (runtime.nextBoardAt or 0) then return "pending", runtime.reason end
    local actor, seat
    if not seated(brock, car, value.seat) then
        if not seated(joy, car, 0) then
            local staged, stageReason = stageDriver(runtime, car, value, joy, brock)
            if not staged then
                runtime.nextBoardAt, runtime.reason = current + 250, stageReason
                return "pending", stageReason
            end
        end
        actor, seat = brock, value.seat
    elseif not seated(joy, car, 0) then actor, seat = joy, 0 end
    if actor then
        local accepted, boardReason = approach(actor, car, value, seat)
        runtime.nextBoardAt, runtime.reason = current + (accepted and 250 or 1000), boardReason
        if boardReason == "evacuation_car_door_locked" and not value.moved then
            return "replacement", boardReason
        end
        return "pending", boardReason
    end
    group.oddball.stage = "driving"
    return "pending", "evacuation_crew_boarded"
end

function Vehicle.flush(player)
    local saved, why = SC.Persistence.save(player)
    if not saved then return false, why end
    if native("flushGlobalModDataForWorldExit") ~= true then return false, "evacuation_save_pending" end
    return true
end

local function go(group, car, value, joy, brock, current)
    if not seated(joy, car, 0) or not seated(brock, car, value.seat)
        or not occupancy(car, joy, brock, value.seat) or not untowed(car) then
        local stopped, why = stopDriver(joy, "evacuation_crew_changed")
        if stopped then group.oddball.stage = "boarding" end
        return "pending", why or "evacuation_crew_changed"
    end
    local at = point(car)
    if not at then return "pending", "evacuation_car_position_missing" end
    local runtime = state(group)
    local status = SC.Driving.jobStatus(joy)
    if runtime.driveStarted and status and status.owned and distanceSquared(at, runtime.driveStarted) >= 1 then
        value.travelOrigin = value.travelOrigin or runtime.driveStarted
        value.moved = true
    end
    if value.travelOrigin and distanceSquared(at, value.travelOrigin) >= EXIT_DISTANCE^2
        and SC.TaxiService.outsideViews(at.x, at.y) then
        local stopped, why = stopDriver(joy, "evacuation_out_of_view")
        if stopped then group.oddball.stage = "retiring" end
        return "pending", why or "evacuation_stopping_offscreen"
    end
    if runtime.driveStarted and status and not status.result and status.owned then
        return "pending", "evacuation_driving"
    end
    if current < (runtime.nextDriveAt or 0) then return "pending", "evacuation_road_wait" end
    local released, why = stopDriver(joy, "evacuation_next_leg")
    if not released then return "pending", why end
    runtime.nextDriveAt = current + 3000
    local priorGoal = runtime.driveStarted and value.goal or nil
    runtime.driveStarted = nil
    if priorGoal or not SC.ExpeditionCar.accessBetween(car, at, value.entry) then
        local goal, backtracked, entry = departure(car, { dropoff = value.travelOrigin or value.origin,
            departureGoal = priorGoal, departurePreviousGoal = value.previousGoal,
            departureBacktracked = value.backtracked })
        if not goal then return "pending", "evacuation_road_wait" end
        value.previousGoal, value.goal, value.entry = priorGoal, goal, entry
        if backtracked == true then value.backtracked = true end
    end
    if not engineReady(car, joy) then
        return value.moved and "pending" or "replacement", "evacuation_car_needs_key"
    end
    local started, driveReason = SC.Driving.drive(joy, value.goal,
        { speedKmh = 20, roadAccessEntry = value.entry })
    if started then runtime.driveStarted = at end
    return "pending", driveReason
end

local function safeRetirePosition(car, value)
    local at = point(car)
    if not at or at.z ~= 0 or not value.travelOrigin
        or distanceSquared(at, value.travelOrigin) < EXIT_DISTANCE^2
        or not SC.TaxiService.outsideViews(at.x, at.y) then return false end
    return not value.retirement or distanceSquared(at, value.retirement) <= 1
end

local function retire(group, player, car, value, current)
    local runtime = state(group)
    if current < (runtime.nextRetireAt or 0) then return "pending", "evacuation_retirement_wait" end
    runtime.nextRetireAt = current + 500
    if value.retirement then
        if not runtime.intentFlushed then
            local okay, why = Vehicle.flush(player)
            if not okay then return "pending", why end
            runtime.intentFlushed = true
        end
        local database = native("vehicleRetirementStatus", value.retirement)
        if database == "absent" and car == nil then
            value.removed = true
            SC.Vehicle.releaseService(claimId(group))
            return "departed", "evacuation_vehicle_removed"
        end
        if database ~= "present" or not matches(car, value) or runtime.removalCar == car
            or not safeRetirePosition(car, value) or not occupancy(car) or not untowed(car)
            or otherClaim(car, value.sqlId)
            or SC.Vehicle.isStationary(car) ~= true or call(car, "isEngineRunning") ~= false
            or call(car, "isEngineStarted") ~= false then
            return "pending", "evacuation_vehicle_removal_wait"
        end
        local _, data = marker(car)
        if data.SC_HomeVehicleSaveTag ~= value.retirement.tagUUID then
            return "pending", "evacuation_vehicle_marker_conflict"
        end
        local called = pcall(removeVehicle, player, car)
        if called then runtime.removalCar = car end
        return "pending", "evacuation_vehicle_removal_queued"
    end
    if not matches(car, value) then return "pending", "evacuation_car_loading" end
    local joy, brock = actors(group, true)
    local stopped, why = stopDriver(joy, "evacuation_retire")
    if not stopped then return "pending", why end
    if not SC.Vehicle.isStationary(car) or not untowed(car) or otherClaim(car, value.sqlId)
        or not occupancy(car, joy, brock, value.seat) then
        return "pending", "evacuation_vehicle_retirement_blocked"
    end
    if not safeRetirePosition(car, value) then
        return "pending", "evacuation_car_still_in_view"
    end
    for _, actor in pairs({ brock, joy }) do
        local exited, exitReason = exitIfAboard(actor, car)
        if not exited then return "pending", exitReason end
    end
    if not occupancy(car) then return "pending", "evacuation_vehicle_still_occupied" end
    if call(car, "isEngineRunning") ~= false or call(car, "isEngineStarted") ~= false then
        call(car, "shutOff")
        return "pending", "evacuation_engine_stopping"
    end
    if not runtime.ticket then
        local ticket = native("requestHomeVehicleSave", car)
        if integer(ticket, 1, 9007199254740991) then runtime.ticket = ticket end
        return "pending", "evacuation_vehicle_save_pending"
    end
    local saved = native("pollHomeVehicleSave", runtime.ticket)
    if saved == "pending" then return "pending", "evacuation_vehicle_save_pending" end
    if saved == "ready" then
        local receipt = native("homeVehicleSaveReceipt", runtime.ticket)
        value.retirement = SC.HomeTrip.copyCarReceipt(receipt, value.sqlId)
    end
    native("cancelHomeVehicleSave", runtime.ticket)
    runtime.ticket = nil
    return "pending", "evacuation_vehicle_retirement_preparing"
end

local function pulse(group, player, current)
    local value = stableVehicle(group)
    if not value then return "replacement", "evacuation_car_missing" end
    if value.removed then return "departed", "evacuation_vehicle_removed" end
    local runtime = state(group)
    local car = SC.Vehicle.loadedBySqlId(value.sqlId)
    if group.oddball.stage == "retiring" then return retire(group, player, car, value, current) end
    if not car then return "pending", "evacuation_car_loading" end
    if not matches(car, value) then
        return value.moved and "pending" or "replacement", "evacuation_car_identity_changed"
    end
    if runtime.car ~= car then
        SC.Vehicle.releaseService(claimId(group))
        runtime.car, runtime.driveStarted, runtime.driverStage = car, nil, nil
    end
    local joy, brock = actors(group)
    if not joy or not brock then return "pending", "evacuation_crew_loading" end
    if group.oddball.stage == "boarding" then return board(group, car, value, joy, brock, current) end
    if group.oddball.stage == "driving" then return go(group, car, value, joy, brock, current) end
    return "pending", "evacuation_stage_wait"
end

function Vehicle.pulse(group, player, current)
    local status, reason = pulse(group, player, current or U().nowMs())
    if status == "replacement" then
        local cancelled, why = Vehicle.cancel(group, reason)
        if not cancelled then return "pending", why end
    end
    return status, reason
end

function Vehicle.recoverMember(group, record)
    local value = stableVehicle(group)
    local car = value and SC.Vehicle.loadedBySqlId(value.sqlId)
    if not value or value.removed or not matches(car, value) then return false, "evacuation_car_loading" end
    if not SC.Vehicle.isStationary(car) then return false, "evacuation_car_moving" end
    if record.id ~= value.joyId and record.id ~= value.brockId then
        return false, "evacuation_crew_changed"
    end
    local seat = record.id == value.joyId and 0 or value.seat
    local square = SC.Vehicle.reloadedCarSquare({ sqlId = value.sqlId, seat = seat })
    if square and SC.Actor.recover(record.actor, square) == true then
        return true, "evacuation_recovered_at_car"
    end
    return false, "evacuation_car_door_unavailable"
end

function Vehicle.validate(story, path, kit)
    local value = story.vehicle
    if story.vehicleAttempt ~= nil and not integer(story.vehicleAttempt, 1, 1000000) then
        return kit.fail(path .. ".vehicleAttempt", "invalid evacuation car attempt")
    end
    if value == nil then
        if story.stage == "boarding" or story.stage == "driving" or story.stage == "retiring" then
            return kit.fail(path .. ".vehicle", "missing evacuation car")
        end
        return true
    end
    path = path .. ".vehicle"
    if type(value) ~= "table" or not integer(value.sqlId, 1, 2147483647)
        or not integer(value.seat, 1, 31) or type(value.script) ~= "string" or #value.script < 1
        or #value.script > 128 or type(value.token) ~= "string" or #value.token < 1 or #value.token > 128
        or not SC.Registry.isValidId(value.joyId) or not SC.Registry.isValidId(value.brockId)
        or value.joyId == value.brockId then return kit.fail(path, "invalid evacuation car identity") end
    for _, field in ipairs({ "origin", "goal", "entry", "previousGoal", "travelOrigin" }) do
        if field ~= "previousGoal" and field ~= "travelOrigin" or value[field] ~= nil then
            local valid, why = kit.position(value[field], path .. "." .. field)
            if not valid then return false, why end
            if value[field].z ~= 0 then return kit.fail(path .. "." .. field, "expected ground-level position") end
        end
    end
    if value.moved == true and value.travelOrigin == nil then
        return kit.fail(path .. ".travelOrigin", "missing evacuation movement origin")
    end
    for _, field in ipairs({ "moved", "backtracked", "removed" }) do
        if value[field] ~= nil and type(value[field]) ~= "boolean" then
            return kit.fail(path .. "." .. field, "expected boolean")
        end
    end
    if value.retirement ~= nil and (value.moved ~= true or not SC.HomeTrip.validCarReceipt(value.retirement, value.sqlId))
        or value.removed == true and value.retirement == nil then
        return kit.fail(path .. ".retirement", "invalid evacuation removal receipt")
    end
    return true
end

return Vehicle
