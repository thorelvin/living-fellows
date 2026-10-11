-- SPDX-License-Identifier: MIT
-- Disposable-save probe: a real companion gets into the driver's seat of a
-- spawned car on a straight road and drives it with the car's own controls.
-- It checks, in order: the engine starts; which way the wheel turns; low-speed
-- cruise with heading hold; stopping on request; the lane scan seeing a parked
-- car ahead; braking by itself for that car; a real crash into a parked car with
-- obstacle braking off, and the vanilla crash damage it does; letting go and
-- getting out. With driving_screenshots the runner captures the car at cruising
-- speed and the scene after the crash. With driving_route the probe instead
-- drives an expedition-planner route: round one wreck and through two
-- zombies on the way out (a companion's car kills zombies it touches), a
-- three-point turn at the end, and round two wrecks on the way back.
-- Telemetry lines start with SC_REAL_SANDBOX|DRIVE. The seed save is never changed.

local Probe = {}
local SCRIPT = "Base.CarNormal"
local CRUISE_KMH = 10
local TURN_TEST_KMH = 6
local SEGMENT_HALF = 30
-- Route mode needs a longer clear stretch: 70 tiles out, then a turn.
local ROUTE_SEGMENT_HALF = 45
local ROUTE_KMH = 10
local ROUTE_LENGTH = 70
local segmentHalf = SEGMENT_HALF

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
    if length < segmentHalf * 2 + 8 or width < 5 or width > 24 then
        return nil, "zone " .. w .. "x" .. h .. " is not a long road"
    end
    local road = { width = width, zone = x .. "," .. y .. "," .. w .. "x" .. h }
    local lo, hi, along
    if horizontal then
        road.ax, road.ay = 1, 0
        road.lineX, road.lineY = nil, y + h / 2
        lo, hi, along = x + segmentHalf + 4, x + w - segmentHalf - 4, px
    else
        road.ax, road.ay = 0, 1
        road.lineX, road.lineY = x + w / 2, nil
        lo, hi, along = y + segmentHalf + 4, y + h - segmentHalf - 4, py
    end
    local failure
    for _, shift in ipairs({ 0, 12, -12, 24, -24 }) do
        local center = math.max(lo, math.min(hi, along + shift))
        local cx = horizontal and center or road.lineX
        local cy = horizontal and road.lineY or center
        local sx, sy = cx - road.ax * segmentHalf, cy - road.ay * segmentHalf
        local ex, ey = cx + road.ax * segmentHalf, cy + road.ay * segmentHalf
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
        .. (status.following and ("|mode=" .. tostring(status.mode) .. "|along="
            .. fmt(status.along) .. "/" .. fmt(status.routeLength) .. "|lateral="
            .. fmt(status.lateral) .. "|offset=" .. fmt(status.offset) .. "|swerves="
            .. tostring(status.swerves) .. "|kills=" .. tostring(status.zombiesKilled)
            .. "|rear=" .. tostring(status.rearBlocked) .. ":" .. tostring(status.rearKind)
            .. ":" .. fmt(status.rearDistance) .. (status.turnState and ("|turn="
            .. tostring(status.turnState) .. ":" .. tostring(status.turnLegs) .. ":"
            .. tostring(status.turnReason)) or "")) or "")
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
    segmentHalf = H.config.driving_route == "true" and ROUTE_SEGMENT_HALF or SEGMENT_HALF
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
    test.startedAt = current
    if H.config.driving_route == "true" then
        setPhase("drive_route_plan", current)
        return
    end
    SC.Driving.cruise(test.actor, CRUISE_KMH, 0)
    setPhase("drive_engine", current)
end

-- ---------------------------------------------------------------- route mode

-- A point on this road: along it from a car position, and to the right of the
-- outbound direction (negative is the other lane).
local function roadPoint(test, fromX, fromY, along, lateral)
    local normalX, normalY = -test.dirY, test.dirX
    local baseX = test.road.ax == 1 and fromX or test.road.lineX
    local baseY = test.road.ax == 1 and test.road.lineY or fromY
    return baseX + test.dirX * along + normalX * lateral,
        baseY + test.dirY * along + normalY * lateral
end

local function placeWreck(SC, x, y, direction)
    local square = SC.GameplayUtil.gridSquare(math.floor(x), math.floor(y), 0)
    if square == nil then return nil, "unloaded square " .. math.floor(x) .. "," .. math.floor(y) end
    local ok, wreck = pcall(addVehicleDebug, SCRIPT, direction, nil, square)
    if not ok or wreck == nil or wreck:getSquare() == nil then
        return nil, "addVehicleDebug refused " .. math.floor(x) .. "," .. math.floor(y)
    end
    return wreck
end

local function moved(item)
    return math.sqrt((item.vehicle:getX() - item.at.x) ^ 2 + (item.vehicle:getY() - item.at.y) ^ 2)
end

-- Watch a stretch of road from the far verge.
local function watchFrom(H, test, x, y)
    local side = -(test.road.width / 2 + 4)
    local normalX, normalY = -test.dirY, test.dirX
    pcall(function()
        H.player:teleportTo(math.floor(x + normalX * side) + 0.5,
            math.floor(y + normalY * side) + 0.5, 0)
    end)
end

-- No wreck may be touched: each stays put and keeps its parts. The car's own
-- parts are reported, not judged: running down zombies dents it.
local function untouched(test)
    for _, item in ipairs(test.wrecks) do
        local shift = moved(item)
        if shift > 0.15 then return false, item.name .. " moved " .. fmt(shift) .. " tiles" end
        local dent = item.parts - partCondition(item.vehicle)
        if dent > 0 then return false, item.name .. " lost " .. fmt(dent) .. " part condition" end
    end
    return true
end

local function nearestWreck(test)
    local best, bestName
    for _, item in ipairs(test.wrecks) do
        local gap = math.sqrt((item.vehicle:getX() - test.vehicle:getX()) ^ 2
            + (item.vehicle:getY() - test.vehicle:getY()) ^ 2)
        if best == nil or gap < best then best, bestName = gap, item.name end
    end
    return best, bestName
end

local function settled(test)
    for _, item in ipairs(test.wrecks) do
        if not stationary(item.vehicle) then return false end
    end
    return true
end

local function recordWrecks(test)
    for _, item in ipairs(test.wrecks) do
        item.at = { x = item.vehicle:getX(), y = item.vehicle:getY() }
        item.parts = partCondition(item.vehicle)
    end
end

-- An inert zombie standing on the road, for the car to run down.
local function placeZombie(x, y)
    if type(addZombiesInOutfit) ~= "function" then return nil, "addZombiesInOutfit unavailable" end
    local ok, list = pcall(addZombiesInOutfit, math.floor(x), math.floor(y), 0, 1, nil, 0)
    local zombie = ok and list and call(list, "get", 0) or nil
    if zombie == nil then return nil, "no zombie spawned at " .. math.floor(x) .. "," .. math.floor(y) end
    call(zombie, "setUseless", true)
    return zombie
end

-- One leg along the route: watches for contact, tracks the closest pass, and
-- reports when the follower arrives. Returns the status table when it does.
local function driveLeg(H, SC, test, current, check, result, setPhase, name, shot)
    local status = SC.Driving.status(test.actor) or {}
    -- Build 42 recycles a dead zombie's object, so a death is noted the moment it shows.
    for index, item in ipairs(test.zombies or {}) do
        if not item.diedAt and (call(item.zombie, "isDead") == true
            or call(item.zombie, "isOnKillDone") == true
            or (tonumber(call(item.zombie, "getHealth")) or 1) <= 0) then
            item.diedAt = current
            print("SC_REAL_SANDBOX|DRIVE|zombie_" .. index .. "_dead|car="
                .. fmt(test.vehicle:getX()) .. "," .. fmt(test.vehicle:getY())
                .. "|zombie=" .. fmt(call(item.zombie, "getX")) .. "," .. fmt(call(item.zombie, "getY"))
                .. "|speed=" .. fmt(test.vehicle:getCurrentSpeedKmHour())
                .. "|kills=" .. tostring(status.zombiesKilled))
        end
    end
    local clean, why = untouched(test)
    if not clean then
        failTo(H, test, setPhase, result, current, name, "contact: " .. why)
        return nil
    end
    local gap, gapName = nearestWreck(test)
    if gap and (test.closest == nil or gap < test.closest) then
        test.closest, test.closestName = gap, gapName
    end
    local slide = math.abs((tonumber(status.offset) or 0) - (tonumber(status.laneOffset) or 0))
    test.maxSlide = math.max(test.maxSlide or 0, slide)
    if status.state == "avoiding" and gap and gap <= 7 then
        requestShot(H, test, shot, result, "sliding past " .. tostring(gapName) .. " at "
            .. fmt(gap) .. " tiles")
    end
    if status.mode == "blocked" then
        test.blockedSince = test.blockedSince or current
        if current - test.blockedSince > 10000 then
            failTo(H, test, setPhase, result, current, name, "blocked for 10 s at "
                .. fmt(status.along) .. "/" .. fmt(status.routeLength) .. ", obstacle "
                .. fmt(status.blockedAt) .. " tiles ahead")
            return nil
        end
    else
        test.blockedSince = nil
    end
    if status.mode == "arrived" then return status end
    if current - H.phaseStartedAt > 100000 then
        failTo(H, test, setPhase, result, current, name, "still " .. tostring(status.mode)
            .. " after 100 s at " .. fmt(status.along) .. "/" .. fmt(status.routeLength))
    end
    return nil
end

local function routeStep(H, SC, current, check, result, setPhase, test)
    local vehicle, actor = test.vehicle, test.actor
    local direction = test.road.ax == 1 and IsoDirections.E or IsoDirections.S

    if H.phase == "drive_route_plan" then
        if current < (test.nextPlanAt or 0) then return end
        test.nextPlanAt = current + 2000
        local gx, gy = roadPoint(test, vehicle:getX(), vehicle:getY(), ROUTE_LENGTH, 0)
        local route, why = SC.Driving.planRoute(actor, { x = math.floor(gx), y = math.floor(gy), z = 0 })
        if not route then
            if current - H.phaseStartedAt > 40000 then
                failTo(H, test, setPhase, result, current, "drive_route_planned", tostring(why))
            end
            return
        end
        local length, worst, widths = 0, 0, {}
        for index, point in ipairs(route.points) do
            local off = test.road.ax == 1 and math.abs(point.y - test.road.lineY)
                or math.abs(point.x - test.road.lineX)
            worst = math.max(worst, off)
            widths[tostring(point.width)] = true
            if index > 1 then
                local before = route.points[index - 1]
                length = length + math.sqrt((point.x - before.x) ^ 2 + (point.y - before.y) ^ 2)
            end
        end
        local names = {}
        for width in pairs(widths) do names[#names + 1] = width end
        local first, last = route.points[1], route.points[#route.points]
        if not check("drive_route_planned", #route.points >= 2 and length >= ROUTE_LENGTH * 0.7,
            "points=" .. #route.points .. " length=" .. fmt(length) .. " from " .. fmt(first.x)
                .. "," .. fmt(first.y) .. " to " .. fmt(last.x) .. "," .. fmt(last.y)
                .. " widths=" .. table.concat(names, "/") .. " furthest_from_road_centre="
                .. fmt(worst) .. " street=" .. tostring(first.street)
                .. " planned_in_ms=" .. tostring(current - H.phaseStartedAt)) then
            setPhase("finish", current) return
        end
        test.route = route
        test.routeStart = { x = vehicle:getX(), y = vehicle:getY() }
        local ax, ay = roadPoint(test, vehicle:getX(), vehicle:getY(), 18, 2)
        local wreck, failure = placeWreck(SC, ax, ay, direction)
        if not wreck then
            failTo(H, test, setPhase, result, current, "drive_route_wreck_placed", failure)
            return
        end
        test.wrecks = { { name = "wreck_out", vehicle = wreck } }
        result("PASS", "drive_route_wreck_placed", "one parked car in the right-hand lane at "
            .. fmt(wreck:getX()) .. "," .. fmt(wreck:getY()))
        test.zombies = {}
        for _, along in ipairs({ 36, 40 }) do
            local zx, zy = roadPoint(test, vehicle:getX(), vehicle:getY(), along, 2)
            local zombie, zombieWhy = placeZombie(zx + 0.5, zy + 0.5)
            if not zombie then
                failTo(H, test, setPhase, result, current, "drive_route_zombies_placed", zombieWhy)
                return
            end
            test.zombies[#test.zombies + 1] = { zombie = zombie, at = { x = zx + 0.5, y = zy + 0.5 } }
        end
        result("PASS", "drive_route_zombies_placed", "two still zombies in the lane "
            .. "36 and 40 tiles on")
        watchFrom(H, test, ax, ay)
        setPhase("drive_route_settle_out", current)
        return
    end

    if H.phase == "drive_route_settle_out" then
        if current - H.phaseStartedAt < 1500 or not settled(test) then return end
        recordWrecks(test)
        test.legParts = partCondition(vehicle)
        test.closest, test.maxSlide = nil, 0
        local following, why = SC.Driving.followRoute(actor, test.route, ROUTE_KMH)
        if not check("drive_route_follow_started", following == true, tostring(why)) then
            setPhase("finish", current) return
        end
        setPhase("drive_route_out", current)
        return
    end

    if H.phase == "drive_route_out" then
        local status = driveLeg(H, SC, test, current, check, result, setPhase,
            "drive_route_outbound", "swerve")
        if not status then return end
        local dead = 0
        for _, item in ipairs(test.zombies or {}) do
            if item.diedAt then dead = dead + 1 end
        end
        check("drive_route_rams_zombies", dead == #(test.zombies or {}) and dead >= 2
                and (tonumber(status.zombiesKilled) or 0) >= dead,
            "zombies in the lane dead: " .. dead .. "/" .. #(test.zombies or {})
                .. ", killed by the car this drive: " .. tostring(status.zombiesKilled)
                .. ", car part condition lost: " .. fmt(test.legParts - partCondition(vehicle)))
        check("drive_route_outbound", (tonumber(status.swerves) or 0) >= 1,
            "arrived in " .. tostring(math.floor((current - H.phaseStartedAt) / 1000)) .. " s at "
                .. fmt(status.along) .. "/" .. fmt(status.routeLength) .. ", swerves="
                .. tostring(status.swerves) .. ", widest slide " .. fmt(test.maxSlide)
                .. " tiles, closest pass " .. fmt(test.closest) .. " tiles (centre to centre), "
                .. "lateral at the end " .. fmt(status.lateral))
        -- The outbound wreck goes; two wait in the return lane.
        for _, item in ipairs(test.wrecks) do pcall(item.vehicle.permanentlyRemove, item.vehicle) end
        test.wrecks = {}
        for _, spot in ipairs({ { name = "wreck_back_1", along = -18 },
            { name = "wreck_back_2", along = -50 } }) do
            local wx, wy = roadPoint(test, vehicle:getX(), vehicle:getY(), spot.along, -2)
            local wreck, failure = placeWreck(SC, wx, wy, direction)
            if not wreck then
                failTo(H, test, setPhase, result, current, "drive_route_return_wrecks", failure)
                return
            end
            test.wrecks[#test.wrecks + 1] = { name = spot.name, vehicle = wreck }
        end
        result("PASS", "drive_route_return_wrecks", "two parked cars in the return lane at "
            .. fmt(test.wrecks[1].vehicle:getX()) .. " and " .. fmt(test.wrecks[2].vehicle:getX()))
        watchFrom(H, test, vehicle:getX(), vehicle:getY())
        setPhase("drive_route_settle_back", current)
        return
    end

    if H.phase == "drive_route_settle_back" then
        if current - H.phaseStartedAt < 1500 or not settled(test) or not stationary(vehicle) then
            return
        end
        recordWrecks(test)
        test.legParts = partCondition(vehicle)
        test.turnFrom = heading(vehicle)
        local turning, why = SC.Driving.turnAround(actor, true)
        if not check("drive_route_turn_started", turning == true, tostring(why)) then
            setPhase("finish", current) return
        end
        setPhase("drive_route_turn", current)
        return
    end

    if H.phase == "drive_route_turn" then
        local status = SC.Driving.status(actor) or {}
        local clean, why = untouched(test)
        if not clean then
            failTo(H, test, setPhase, result, current, "drive_turnaround", "contact: " .. why)
            return
        end
        if (tonumber(status.turnLegs) or 0) >= 2 then
            requestShot(H, test, "turn", result, "turn leg " .. tostring(status.turnLegs))
        end
        if status.mode == "turn_failed" then
            failTo(H, test, setPhase, result, current, "drive_turnaround", "legs="
                .. tostring(status.turnLegs) .. " reason=" .. tostring(status.turnReason))
            return
        end
        if status.mode == "follow" or status.mode == "arrived" or status.mode == "blocked" then
            local turned = math.deg(wrap(heading(vehicle) - test.turnFrom))
            check("drive_turnaround", math.abs(math.abs(turned) - 180) <= 25,
                "turned " .. fmt(turned) .. " deg in " .. tostring(status.turnLegs) .. " legs ("
                    .. (tonumber(status.turnSide) == 1 and "right" or "left") .. " first, reverse wheel "
                    .. (tonumber(status.turnReverseSign) == 1 and "as expected" or "flipped") .. ") in "
                    .. tostring(math.floor((current - H.phaseStartedAt) / 100) / 10) .. " s")
            test.closest, test.maxSlide = nil, 0
            local first = test.wrecks[1].vehicle
            watchFrom(H, test, first:getX(), first:getY())
            setPhase("drive_route_back", current)
            return
        end
        if current - H.phaseStartedAt > 60000 then
            failTo(H, test, setPhase, result, current, "drive_turnaround", "still turning after 60 s, legs="
                .. tostring(status.turnLegs) .. " state=" .. tostring(status.turnState))
        end
        return
    end

    if H.phase == "drive_route_back" then
        local status = driveLeg(H, SC, test, current, check, result, setPhase,
            "drive_route_return", "return")
        if not status then return end
        local home = math.sqrt((vehicle:getX() - test.routeStart.x) ^ 2
            + (vehicle:getY() - test.routeStart.y) ^ 2)
        -- Arriving with both wrecks untouched means both were passed; whether
        -- that took one long swerve or two depends on the gap between them.
        check("drive_route_return", (tonumber(status.swerves) or 0) >= 1 and home <= 6,
            "arrived back in " .. tostring(math.floor((current - H.phaseStartedAt) / 1000))
                .. " s, " .. fmt(home) .. " tiles from where it set out, swerves="
                .. tostring(status.swerves) .. ", widest slide " .. fmt(test.maxSlide)
                .. " tiles, closest pass " .. fmt(test.closest) .. " tiles to "
                .. tostring(test.closestName))
        setPhase("drive_release", current)
    end
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
    if string.find(H.phase, "drive_route_", 1, true) == 1 then
        routeStep(H, SC, current, check, result, setPhase, test)
        return
    end

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
            local all, names = true, {}
            for name in pairs(test.shots) do
                local captured = shotCaptured(H, name)
                all = all and captured
                names[#names + 1] = name .. "=" .. tostring(captured)
            end
            check("drive_screenshots_captured", all and #names > 0, table.concat(names, " "))
        end
        setPhase("finish", current)
    end
end

SCRealSandboxHarnessProbes = SCRealSandboxHarnessProbes or {}
SCRealSandboxHarnessProbes.SCDrivingProbe = Probe
return Probe
