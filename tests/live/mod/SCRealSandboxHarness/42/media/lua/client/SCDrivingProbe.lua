-- SPDX-License-Identifier: MIT
-- Disposable-save probe: a real companion gets into the driver's seat of a
-- spawned car on a straight road and drives it with the car's own controls.
-- It checks, in order: the engine starts; which way the wheel turns; low-speed
-- cruise with heading hold; stopping on request; the lane scan seeing a parked
-- car ahead; braking by itself for that car; a real crash into a parked car with
-- obstacle braking off, and the vanilla crash damage it does; letting go and
-- getting out. With driving_screenshots the runner captures the car at cruising
-- speed and the scene after the crash. Telemetry lines start with
-- SC_REAL_SANDBOX|DRIVE. The seed save is never changed.

local Probe = {}
local SCRIPT = "Base.CarNormal"
local CRUISE_KMH = 10
local TURN_TEST_KMH = 6
local SEGMENT_HALF = 30

-- Exactly one value: GameplayUtil.call also returns its success flag, which
-- Kahlua's tonumber would otherwise take as a number base.
local function call(object, method, ...)
    if object == nil then return nil end
    local value = SurvivorCompanion.GameplayUtil.call(object, method, ...)
    return value
end

local function fmt(value)
    local number = tonumber(value)
    if number == nil then return tostring(value) end
    return string.format("%.2f", number)
end

local function openSquare(U, x, y, allowedVehicle)
    local square = U.gridSquare(math.floor(x), math.floor(y), 0)
    if square == nil then return false, "unloaded" end
    if square:isOutside() ~= true or square:getRoom() ~= nil
        or square:getBuilding() ~= nil then return false, "indoors" end
    local occupying = square:getVehicleContainer()
    if occupying ~= nil and occupying ~= allowedVehicle then return false, "vehicle" end
    if square:HasTree() or square:isSolid() or square:isSolidTrans() then
        return false, "solid"
    end
    return true
end

-- A 5-wide corridor along the line from a to b is open and loaded.
local function corridorOpen(U, ax, ay, bx, by, dirX, dirY)
    local length = math.floor(math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2))
    local normalX, normalY = -dirY, dirX
    for step = 0, length do
        for side = -2, 2 do
            local x = ax + dirX * step + normalX * side
            local y = ay + dirY * step + normalY * side
            local ok, why = openSquare(U, x, y)
            if not ok then
                return false, why .. "@" .. math.floor(x) .. "," .. math.floor(y)
            end
        end
    end
    return true
end

-- A straight 60-tile stretch along the middle of a Nav zone near the player.
local function roadFromZone(U, zone, px, py)
    local x, y = tonumber(call(zone, "getX")), tonumber(call(zone, "getY"))
    local w, h = tonumber(call(zone, "getWidth")), tonumber(call(zone, "getHeight"))
    if not (x and y and w and h) then return nil, "zone without bounds" end
    local horizontal = w >= h
    local length, width = horizontal and w or h, horizontal and h or w
    if length < SEGMENT_HALF * 2 + 8 or width < 5 or width > 24 then
        return nil, "zone " .. w .. "x" .. h .. " is not a long road"
    end
    local road = { width = width, zone = x .. "," .. y .. "," .. w .. "x" .. h }
    local lo, hi, along
    if horizontal then
        road.ax, road.ay = 1, 0
        road.lineX, road.lineY = nil, y + h / 2
        lo, hi, along = x + SEGMENT_HALF + 4, x + w - SEGMENT_HALF - 4, px
    else
        road.ax, road.ay = 0, 1
        road.lineX, road.lineY = x + w / 2, nil
        lo, hi, along = y + SEGMENT_HALF + 4, y + h - SEGMENT_HALF - 4, py
    end
    local failure
    for _, shift in ipairs({ 0, 12, -12, 24, -24 }) do
        local center = math.max(lo, math.min(hi, along + shift))
        local cx = horizontal and center or road.lineX
        local cy = horizontal and road.lineY or center
        local sx, sy = cx - road.ax * SEGMENT_HALF, cy - road.ay * SEGMENT_HALF
        local ex, ey = cx + road.ax * SEGMENT_HALF, cy + road.ay * SEGMENT_HALF
        local open, why = corridorOpen(U, sx, sy, ex, ey, road.ax, road.ay)
        if open then
            road.cx, road.cy = cx, cy
            road.sx, road.sy, road.ex, road.ey = sx, sy, ex, ey
            return road
        end
        failure = why
    end
    return nil, "zone " .. road.zone .. " blocked: " .. tostring(failure)
end

local function findRoad(U, px, py)
    local seen, reasons = {}, {}
    for radius = 0, 66, 3 do
        for dx = -radius, radius, 3 do
            for dy = -radius, radius, 3 do
                if math.max(math.abs(dx), math.abs(dy)) == radius then
                    local square = U.gridSquare(px + dx, py + dy, 0)
                    local zone = square and square:getZone() or nil
                    if zone ~= nil and not seen[zone] then
                        seen[zone] = true
                        if tostring(call(zone, "getType")) == "Nav" then
                            local road, why = roadFromZone(U, zone, px, py)
                            if road then return road end
                            if #reasons < 4 then reasons[#reasons + 1] = why end
                        end
                    end
                end
            end
        end
    end
    return nil, table.concat(reasons, "; ")
end

local function heading(vehicle)
    local forward = vehicle:getForwardVector(Vector3f.new())
    local fx, fy = forward:x(), forward:z()
    return math.atan2(fy, fx), fx, fy
end

local function wrap(angle)
    while angle > math.pi do angle = angle - 2 * math.pi end
    while angle < -math.pi do angle = angle + 2 * math.pi end
    return angle
end

-- Heading hold toward the road axis through the line the car started on.
-- Positive turn means "turn right" (clockwise with y pointing south).
local function holdSteering(test)
    local vehicle = test.vehicle
    local theta = heading(vehicle)
    local headingError = wrap(math.atan2(test.dirY, test.dirX) - theta)
    local normalX, normalY = -test.dirY, test.dirX
    local lateral = (vehicle:getX() - test.lineX) * normalX
        + (vehicle:getY() - test.lineY) * normalY
    local turn = 1.6 * headingError - 0.25 * lateral
    local steering = math.max(-0.7, math.min(0.7, test.steerSign * turn))
    return steering, headingError, lateral
end

local function telemetry(H, test, current, extra)
    if current < (test.nextTraceAt or 0) then return end
    test.nextTraceAt = current + 250
    local status = SurvivorCompanion.Driving.status(test.actor) or {}
    local vehicle = test.vehicle
    local speedOk, gameSpeed = pcall(getGameSpeed)
    print("SC_REAL_SANDBOX|DRIVE|" .. tostring(H.phase)
        .. "|t=" .. tostring(math.floor(current - (test.startedAt or current)))
        .. "|pos=" .. fmt(vehicle:getX()) .. "," .. fmt(vehicle:getY())
        .. "|speed=" .. fmt(vehicle:getCurrentSpeedKmHour())
        .. "|state=" .. tostring(status.state)
        .. "|gas=" .. tostring(status.forward) .. "|brake=" .. tostring(status.brake)
        .. "|steer=" .. fmt(status.steering)
        .. "|engine=" .. tostring(status.engineState)
        .. "|blocked=" .. tostring(status.blocked) .. ":" .. tostring(status.obstacleKind)
        .. ":" .. fmt(status.obstacleDistance)
        .. "|game_speed=" .. tostring(speedOk and gameSpeed or "?")
        .. (extra and ("|" .. extra) or ""))
end

local function failTo(H, test, setPhase, result, current, name, detail)
    result("FAIL", name, detail)
    if test and test.actor then SurvivorCompanion.Driving.release(test.actor) end
    setPhase("finish", current)
end

local function stationary(vehicle)
    return math.abs(tonumber(vehicle:getCurrentSpeedKmHour()) or 99) < 0.6
end

-- Sum of every part's condition; a crash lowers it through vanilla crash damage.
local function partCondition(vehicle)
    local total = 0
    local count = tonumber(call(vehicle, "getPartCount")) or 0
    for index = 0, count - 1 do
        total = total + (tonumber(call(call(vehicle, "getPartByIndex", index), "getCondition")) or 0)
    end
    return total
end

local function bodyHealth(actor)
    return tonumber(call(call(actor, "getBodyDamage"), "getOverallBodyHealth")) or -1
end

local function shotFile(name, state)
    return "SurvivorCompanionHarness/driving-" .. name .. "-" .. state .. ".txt"
end

-- Asks the runner for one screenshot, only when the run asked for them.
local function requestShot(H, test, name, result, detail)
    if H.config.driving_screenshots ~= "true" or test.shots[name] then return end
    test.shots[name] = true
    local signals = H.drivingSignals
    local written = signals ~= nil and signals.write(shotFile(name, "ready"), { "shot=" .. name })
    result(written and "PASS" or "FAIL", "drive_screenshot_" .. name .. "_requested",
        tostring(detail))
end

local function shotCaptured(H, name)
    local signals = H.drivingSignals
    return signals ~= nil and signals.exists(shotFile(name, "captured")) == true
end

-- The cruise shot: at speed, close enough to the observer to be on screen.
local function maybeCruiseShot(H, test, speed, result)
    if speed < 8 or test.shots.cruise then return end
    local px, py = SurvivorCompanion.GameplayUtil.position(H.player)
    local distance = math.sqrt((test.vehicle:getX() - px) ^ 2 + (test.vehicle:getY() - py) ^ 2)
    if distance <= 12 then
        requestShot(H, test, "cruise", result, "speed=" .. fmt(speed) .. " km/h, "
            .. fmt(distance) .. " tiles from the observer")
    end
end

local function setupRoad(H, SC, check, result, setPhase, current)
    local U = SC.GameplayUtil
    if not check("drive_bridge_api", SC.Driving and SC.Driving.available(),
        "SCBridge driving calls are exposed") then
        setPhase("finish", current) return
    end
    local px, py = U.position(H.player)
    local road, why = findRoad(U, math.floor(px), math.floor(py))
    if not check("drive_road_found", road ~= nil, road and ("zone=" .. road.zone
            .. " axis=" .. road.ax .. "," .. road.ay .. " width=" .. road.width
            .. " center=" .. fmt(road.cx) .. "," .. fmt(road.cy)) or tostring(why)) then
        setPhase("finish", current) return
    end
    -- Watch from the roadside, off the lane.
    local normalX, normalY = -road.ay, road.ax
    local watch
    for _, side in ipairs({ 1, -1 }) do
        local offset = road.width / 2 + 4
        local wx, wy = road.cx + normalX * offset * side, road.cy + normalY * offset * side
        if openSquare(U, wx, wy) then watch = { x = math.floor(wx), y = math.floor(wy) } break end
    end
    if watch then
        pcall(function() H.player:teleportTo(watch.x + 0.5, watch.y + 0.5, 0) end)
    end
    pcall(function() getGameTime():setTimeOfDay(12.0) end)
    result("PASS", "drive_observer_placed", watch and (watch.x .. "," .. watch.y)
        or "observer left where it stood")
    H.driveTest = { road = road, startedAt = current, watch = watch, spawnAttempts = 0,
        shots = {} }
    setPhase("drive_spawn_car", current)
end

local function spawnCar(H, SC, result, setPhase, current, test)
    if current - H.phaseStartedAt < 2000 then return end
    local U = SC.GameplayUtil
    local road = test.road
    test.spawnAttempts = test.spawnAttempts + 1
    local flip = test.spawnAttempts > 1
    local dirX, dirY = road.ax, road.ay
    if flip then dirX, dirY = -dirX, -dirY end
    local startX = (flip and road.ex or road.sx) + dirX * 5
    local startY = (flip and road.ey or road.sy) + dirY * 5
    local square = U.gridSquare(math.floor(startX), math.floor(startY), 0)
    local direction = road.ax == 1 and (flip and IsoDirections.W or IsoDirections.E)
        or (flip and IsoDirections.N or IsoDirections.S)
    local ok, vehicle = pcall(addVehicleDebug, SCRIPT, direction, nil, square)
    -- addVehicleDebug sets the car's square only when the spawn spot is valid;
    -- its collision shape is not registered until its first update.
    if not ok or vehicle == nil or vehicle:getSquare() == nil then
        failTo(H, test, setPhase, result, current, "drive_car_spawned",
            "addVehicleDebug at " .. math.floor(startX) .. "," .. math.floor(startY)
                .. " -> " .. tostring(vehicle) .. " script=" .. tostring(call(vehicle, "getScriptName")))
        return
    end
    local theta, fx, fy = heading(vehicle)
    local dot = fx * dirX + fy * dirY
    if dot < 0.7 and test.spawnAttempts == 1 then
        -- Spawned facing back up the road: try once from the other end.
        result("PASS", "drive_spawn_direction_probe", "IsoDirections." .. tostring(direction)
            .. " faced " .. fmt(fx) .. "," .. fmt(fy) .. "; respawning reversed")
        pcall(vehicle.permanentlyRemove, vehicle)
        H.phaseStartedAt = current
        return
    end
    if dot < 0.7 then
        failTo(H, test, setPhase, result, current, "drive_car_spawned",
            "car faces " .. fmt(fx) .. "," .. fmt(fy) .. " but the road runs "
                .. dirX .. "," .. dirY)
        return
    end
    test.vehicle, test.dirX, test.dirY = vehicle, dirX, dirY
    test.lineX = road.lineX or vehicle:getX()
    test.lineY = road.lineY or vehicle:getY()
    if road.ax == 1 then test.lineX = vehicle:getX() else test.lineY = vehicle:getY() end
    result("PASS", "drive_car_spawned", SCRIPT .. " at " .. fmt(vehicle:getX()) .. ","
        .. fmt(vehicle:getY()) .. " facing " .. fmt(fx) .. "," .. fmt(fy)
        .. " (" .. tostring(direction) .. ", heading " .. fmt(math.deg(theta)) .. " deg)")
    -- Fuel and battery, so the engine test measures driving, not a dead car.
    local tank = call(vehicle, "getPartById", "GasTank")
    if tank then call(tank, "setContainerContentAmount", call(tank, "getContainerCapacity") or 0) end
    local battery = call(vehicle, "getBattery")
    local cell = battery and call(battery, "getInventoryItem") or nil
    if cell then call(cell, "setCurrentUsesFloat", 1.0) end
    -- A free square at the driver's door, inside the boarding range.
    local outside = vehicle:getPassengerPosition(0, "outside")
    local door = outside and vehicle:getPassengerPositionWorldPos(outside, Vector3f.new()) or nil
    local best, bestDistance
    if door then
        local dx0, dy0 = math.floor(door:x()), math.floor(door:y())
        for dx = -2, 2 do
            for dy = -2, 2 do
                local candidate = U.gridSquare(dx0 + dx, dy0 + dy, 0)
                if candidate and openSquare(U, dx0 + dx, dy0 + dy) and U.isSquareFree(candidate) then
                    local distance = vehicle:getEnterSeatDistance(0,
                        candidate:getX() + 0.5, candidate:getY() + 0.5)
                    if distance and distance >= 0 and distance <= 2.56
                        and (bestDistance == nil or distance < bestDistance) then
                        best, bestDistance = candidate, distance
                    end
                end
            end
        end
    end
    if not best then
        failTo(H, test, setPhase, result, current, "drive_driver_door",
            "no free square within boarding range of the driver's door")
        return
    end
    local ticket, reason = SC.Actor.beginSpawn(best, {
        recruited = true,
        identity = { forename = "Driver", surname = "Tester", gender = "woman",
            outfit = "Generic01" },
    })
    if not ticket then
        failTo(H, test, setPhase, result, current, "drive_companion_spawn", tostring(reason))
        return
    end
    test.ticket = ticket
    result("PASS", "drive_driver_door", "door square " .. best:getX() .. "," .. best:getY()
        .. " range=" .. fmt(bestDistance))
    setPhase("drive_spawn_companion", current)
end

local function board(H, SC, check, result, setPhase, current, test)
    if not test.actor then
        local actor, reason = SC.Actor.pollSpawn(test.ticket)
        if not actor then
            if reason ~= "spawn_pending" or current - H.phaseStartedAt > 12000 then
                failTo(H, test, setPhase, result, current, "drive_companion_spawn", tostring(reason))
            end
            return
        end
        test.actor = actor
        -- Decision would walk a fresh companion off to follow the player.
        SC.Scheduler.unregister("decision")
        H.phaseStartedAt = current
        return
    end
    if not stationary(test.vehicle) then
        if current - H.phaseStartedAt > 15000 then
            failTo(H, test, setPhase, result, current, "drive_car_settled",
                "speed=" .. fmt(test.vehicle:getCurrentSpeedKmHour()))
        end
        return
    end
    if current - H.phaseStartedAt < 1200 then return end
    local key = call(test.vehicle, "createVehicleKey")
    local inventory = call(test.actor, "getInventory")
    if key and inventory then call(inventory, "AddItem", key) end
    local boarded, status = SC.Driving.takeWheel(test.actor, test.vehicle)
    if not check("drive_board_driver_seat", boarded == true and status == "native_seat"
            and SC.Driving.isDriver(test.actor),
        "status=" .. tostring(status) .. " key=" .. tostring(SC.Driving.hasKey(test.actor))) then
        setPhase("finish", current) return
    end
    local started, why = SC.Driving.start(test.actor)
    if not check("drive_take_wheel", started == true,
            started == true and "held still with the engine off" or tostring(why)) then
        setPhase("finish", current) return
    end
    SC.Driving.cruise(test.actor, CRUISE_KMH, 0)
    test.startedAt = current
    setPhase("drive_engine", current)
end

function Probe.step(H, current, check, result, setPhase)
    local SC = SurvivorCompanion
    if H.phase == "drive_setup" then
        if current - H.phaseStartedAt < 3000 then return end
        setupRoad(H, SC, check, result, setPhase, current)
        return
    end
    local test = H.driveTest
    if test == nil then setPhase("finish", current) return end
    if H.phase == "drive_spawn_car" then
        spawnCar(H, SC, result, setPhase, current, test)
        return
    end
    if H.phase == "drive_spawn_companion" then
        board(H, SC, check, result, setPhase, current, test)
        return
    end
    local vehicle, actor = test.vehicle, test.actor
    telemetry(H, test, current)
    local speed = tonumber(vehicle:getCurrentSpeedKmHour()) or 0

    if H.phase == "drive_engine" then
        local status = SC.Driving.status(actor) or {}
        if status.engineRunning == true then
            result("PASS", "drive_engine_started", "start_calls=" .. tostring(status.engineStartCalls)
                .. " after " .. tostring(current - H.phaseStartedAt) .. " ms")
            test.turnStartHeading = heading(vehicle)
            SC.Driving.cruise(actor, TURN_TEST_KMH, 0.8)
            setPhase("drive_turn_test", current)
        elseif status.state == "engine_failed" or current - H.phaseStartedAt > 15000 then
            failTo(H, test, setPhase, result, current, "drive_engine_started",
                "state=" .. tostring(status.state) .. " engine=" .. tostring(status.engineState)
                    .. " attempts=" .. tostring(status.startAttempts))
        end
        return
    end

    if H.phase == "drive_turn_test" then
        local turned = wrap(heading(vehicle) - test.turnStartHeading)
        if math.abs(turned) >= math.rad(12) or current - H.phaseStartedAt > 6000 then
            local enough = math.abs(turned) >= math.rad(12)
            -- With y pointing south, a clockwise (right) turn grows the heading.
            test.steerSign = turned > 0 and 1 or -1
            check("drive_steering_turns_car", enough, "steering +0.8 turned the car "
                .. (turned > 0 and "right" or "left") .. " by " .. fmt(math.deg(turned))
                .. " deg at " .. fmt(speed) .. " km/h")
            if not enough then
                failTo(H, test, setPhase, result, current, "drive_turn_test", "the wheel had no effect")
                return
            end
            test.cruiseFrom = { x = vehicle:getX(), y = vehicle:getY() }
            test.maxSpeed, test.speedSum, test.speedSamples = 0, 0, 0
            setPhase("drive_cruise", current)
        end
        return
    end

    if H.phase == "drive_cruise" then
        local steering, headingError, lateral = holdSteering(test)
        SC.Driving.cruise(actor, CRUISE_KMH, steering)
        maybeCruiseShot(H, test, speed, result)
        test.maxSpeed = math.max(test.maxSpeed, speed)
        test.speedSum, test.speedSamples = test.speedSum + speed, test.speedSamples + 1
        if current - H.phaseStartedAt >= 7000 then
            local moved = (vehicle:getX() - test.cruiseFrom.x) * test.dirX
                + (vehicle:getY() - test.cruiseFrom.y) * test.dirY
            local average = test.speedSum / math.max(1, test.speedSamples)
            check("drive_cruise_moves_slowly", moved >= 10 and test.maxSpeed <= 16
                    and test.maxSpeed >= 6,
                "moved=" .. fmt(moved) .. " tiles max=" .. fmt(test.maxSpeed)
                    .. " avg=" .. fmt(average) .. " km/h target=" .. CRUISE_KMH)
            check("drive_heading_hold", math.abs(headingError) <= math.rad(8)
                    and math.abs(lateral) <= 2.0,
                "heading_error=" .. fmt(math.deg(headingError)) .. " deg lateral="
                    .. fmt(lateral) .. " tiles")
            SC.Driving.hold(actor)
            test.stopFrom = { x = vehicle:getX(), y = vehicle:getY(), speed = speed }
            setPhase("drive_stop", current)
        end
        return
    end

    if H.phase == "drive_stop" then
        if stationary(vehicle) and current - H.phaseStartedAt > 300 then
            local slide = math.sqrt((vehicle:getX() - test.stopFrom.x) ^ 2
                + (vehicle:getY() - test.stopFrom.y) ^ 2)
            local status = SC.Driving.status(actor) or {}
            check("drive_stops_on_request", slide <= 4.0 and status.state == "holding",
                "from " .. fmt(test.stopFrom.speed) .. " km/h in " .. fmt(slide)
                    .. " tiles, " .. tostring(current - H.phaseStartedAt) .. " ms, state="
                    .. tostring(status.state) .. " pedal_down=" .. tostring(status.brake))
            setPhase("drive_place_wreck", current)
        elseif current - H.phaseStartedAt > 8000 then
            failTo(H, test, setPhase, result, current, "drive_stops_on_request",
                "still at " .. fmt(speed) .. " km/h")
        end
        return
    end

    if H.phase == "drive_place_wreck" then
        if current - H.phaseStartedAt < 1000 then return end
        local U = SC.GameplayUtil
        local wx = vehicle:getX() + test.dirX * 16
        local wy = vehicle:getY() + test.dirY * 16
        local square = U.gridSquare(math.floor(wx), math.floor(wy), 0)
        local direction = test.dirX ~= 0 and IsoDirections.N or IsoDirections.E
        local ok, wreck = pcall(addVehicleDebug, SCRIPT, direction, nil, square)
        if not ok or wreck == nil or square == nil or wreck:getSquare() == nil then
            failTo(H, test, setPhase, result, current, "drive_wreck_placed",
                "addVehicleDebug at " .. math.floor(wx) .. "," .. math.floor(wy))
            return
        end
        test.wreck = wreck
        result("PASS", "drive_wreck_placed", "parked car across the lane at "
            .. fmt(wreck:getX()) .. "," .. fmt(wreck:getY()))
        setPhase("drive_scan_wreck", current)
        return
    end

    if H.phase == "drive_scan_wreck" then
        if not stationary(test.wreck) or current - H.phaseStartedAt < 1500 then
            if current - H.phaseStartedAt > 12000 then
                failTo(H, test, setPhase, result, current, "drive_wreck_settled", "wreck still moving")
            end
            return
        end
        local lane = SC.Driving.scanLane(actor, 24) or {}
        check("drive_lane_scan_sees_wreck", lane.blocked == true
                and lane.obstacleKind == "vehicle"
                and (tonumber(lane.obstacleDistance) or -1) >= 6
                and (tonumber(lane.obstacleDistance) or 99) <= 16,
            "blocked=" .. tostring(lane.blocked) .. " kind=" .. tostring(lane.obstacleKind)
                .. " distance=" .. fmt(lane.obstacleDistance) .. " rays L/C/R="
                .. fmt(lane.leftDistance) .. "/" .. fmt(lane.centerDistance) .. "/"
                .. fmt(lane.rightDistance) .. " squares=" .. tostring(lane.squaresChecked))
        test.wreckAt = { x = test.wreck:getX(), y = test.wreck:getY() }
        test.approachStartedAt = current
        setPhase("drive_approach_wreck", current)
        return
    end

    if H.phase == "drive_approach_wreck" then
        local steering = holdSteering(test)
        SC.Driving.cruise(actor, CRUISE_KMH, steering)
        maybeCruiseShot(H, test, speed, result)
        local status = SC.Driving.status(actor) or {}
        local wreckMoved = math.sqrt((test.wreck:getX() - test.wreckAt.x) ^ 2
            + (test.wreck:getY() - test.wreckAt.y) ^ 2)
        if wreckMoved > 0.3 then
            failTo(H, test, setPhase, result, current, "drive_brakes_for_wreck",
                "hit the parked car: it moved " .. fmt(wreckMoved) .. " tiles")
            return
        end
        test.approachMax = math.max(test.approachMax or 0, speed)
        if status.state == "blocked" and stationary(vehicle)
            and current - H.phaseStartedAt > 1500 then
            test.blockedSince = test.blockedSince or current
            if current - test.blockedSince >= 1500 then
                local lane = SC.Driving.scanLane(actor, 24) or {}
                local gap = tonumber(lane.obstacleDistance) or -1
                check("drive_brakes_for_wreck", gap >= 0.8 and gap <= 5.0,
                    "stopped " .. fmt(gap) .. " tiles short, top speed "
                        .. fmt(test.approachMax) .. " km/h, wreck moved " .. fmt(wreckMoved))
                SC.Driving.hold(actor)
                setPhase("drive_crash_setup", current)
            end
        else
            test.blockedSince = nil
        end
        if current - H.phaseStartedAt > 25000 then
            failTo(H, test, setPhase, result, current, "drive_brakes_for_wreck",
                "state=" .. tostring(status.state) .. " speed=" .. fmt(speed))
        end
        return
    end

    -- A real crash: the parked car moves 20 tiles on, and the companion drives
    -- into it at 20 km/h with obstacle braking switched off on purpose.
    if H.phase == "drive_crash_setup" then
        if not stationary(vehicle) or current - H.phaseStartedAt < 1000 then return end
        local U = SC.GameplayUtil
        pcall(test.wreck.permanentlyRemove, test.wreck)
        local wx = vehicle:getX() + test.dirX * 20
        local wy = vehicle:getY() + test.dirY * 20
        local square = U.gridSquare(math.floor(wx), math.floor(wy), 0)
        local direction = test.dirX ~= 0 and IsoDirections.N or IsoDirections.E
        local ok, wreck = pcall(addVehicleDebug, SCRIPT, direction, nil, square)
        if not ok or wreck == nil or square == nil or wreck:getSquare() == nil then
            failTo(H, test, setPhase, result, current, "drive_crash_wreck_placed",
                "addVehicleDebug at " .. math.floor(wx) .. "," .. math.floor(wy))
            return
        end
        test.crashWreck = wreck
        -- Watch from the roadside just short of the parked car.
        local normalX, normalY = -test.dirY, test.dirX
        local side = test.road.width / 2 + 3
        local ox = wx - test.dirX * 5 + normalX * side
        local oy = wy - test.dirY * 5 + normalY * side
        pcall(function() H.player:teleportTo(math.floor(ox) + 0.5, math.floor(oy) + 0.5, 0) end)
        result("PASS", "drive_crash_wreck_placed", "parked car 20 tiles ahead at "
            .. fmt(wreck:getX()) .. "," .. fmt(wreck:getY()) .. ", observer at "
            .. math.floor(ox) .. "," .. math.floor(oy))
        setPhase("drive_crash_settle", current)
        return
    end

    if H.phase == "drive_crash_settle" then
        if not stationary(test.crashWreck) or current - H.phaseStartedAt < 1500 then
            if current - H.phaseStartedAt > 12000 then
                failTo(H, test, setPhase, result, current, "drive_crash_wreck_settled",
                    "parked car still moving")
            end
            return
        end
        test.crashFrom = { parts = partCondition(vehicle), health = bodyHealth(actor),
            wreckParts = partCondition(test.crashWreck),
            wreckX = test.crashWreck:getX(), wreckY = test.crashWreck:getY() }
        test.crashMax, test.lastSpeed = 0, 0
        setPhase("drive_crash_run", current)
        return
    end

    if H.phase == "drive_crash_run" then
        local steering = holdSteering(test)
        SC.Driving.cruise(actor, 20, steering, false)
        test.crashMax = math.max(test.crashMax, speed)
        local moved = math.sqrt((test.crashWreck:getX() - test.crashFrom.wreckX) ^ 2
            + (test.crashWreck:getY() - test.crashFrom.wreckY) ^ 2)
        local collapsed = test.lastSpeed >= 6 and speed < test.lastSpeed * 0.5
        test.lastSpeed = speed
        if moved > 0.2 or collapsed then
            SC.Driving.hold(actor)
            test.impact = { speed = test.crashMax, moved = moved }
            setPhase("drive_crash_after", current)
        elseif current - H.phaseStartedAt > 20000 then
            failTo(H, test, setPhase, result, current, "drive_crash_impact",
                "no impact after 20 s, top speed " .. fmt(test.crashMax) .. " km/h")
        end
        return
    end

    if H.phase == "drive_crash_after" then
        if not test.crashReported then
            if current - H.phaseStartedAt < 2000 or not stationary(vehicle) then
                if current - H.phaseStartedAt > 10000 then
                    failTo(H, test, setPhase, result, current, "drive_crash_stopped",
                        "still at " .. fmt(speed) .. " km/h after the impact")
                end
                return
            end
            test.crashReported = true
            local carDamage = test.crashFrom.parts - partCondition(vehicle)
            local wreckDamage = test.crashFrom.wreckParts - partCondition(test.crashWreck)
            local health = bodyHealth(actor)
            check("drive_crash_impact", carDamage > 0 or wreckDamage > 0,
                "hit at " .. fmt(test.impact.speed) .. " km/h; car parts -" .. fmt(carDamage)
                    .. ", parked car parts -" .. fmt(wreckDamage) .. ", parked car pushed "
                    .. fmt(test.impact.moved) .. " tiles; driver health "
                    .. fmt(test.crashFrom.health) .. " -> " .. fmt(health))
            requestShot(H, test, "crash", result, "two seconds after the impact")
            test.shotWaitFrom = current
        end
        if H.config.driving_screenshots == "true" and not shotCaptured(H, "crash")
            and current - test.shotWaitFrom < 10000 then return end
        setPhase("drive_release", current)
        return
    end

    if H.phase == "drive_release" then
        if not stationary(vehicle) then return end
        local released = SC.Driving.release(actor)
        local status = SC.Driving.status(actor) or {}
        check("drive_release_wheel", released == true and status.active == false,
            "active=" .. tostring(status.active) .. " reason=" .. tostring(status.reason))
        local exited, why = SC.Vehicle.exit(actor, vehicle)
        check("drive_driver_gets_out", exited == true and actor:getVehicle() == nil,
            tostring(why))
        if H.config.driving_screenshots == "true" then
            check("drive_screenshots_captured", shotCaptured(H, "cruise") and shotCaptured(H, "crash"),
                "cruise=" .. tostring(shotCaptured(H, "cruise"))
                    .. " crash=" .. tostring(shotCaptured(H, "crash")))
        end
        setPhase("finish", current)
    end
end

SCRealSandboxHarnessProbes = SCRealSandboxHarnessProbes or {}
SCRealSandboxHarnessProbes.SCDrivingProbe = Probe
return Probe
