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
-- three-point turn at the end, and round two wrecks on the way back. With
-- driving_turn drives from this road round a junction into a side street.
-- The WP5 modes leave normal Decision enabled, test a blocked-road alternate,
-- or save a moving seat-zero driver and reload a second disposable clone.
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
    local road = { width = width, zone = x .. "," .. y .. "," .. w .. "x" .. h,
        bx = x, by = y, bw = w, bh = h }
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

-- Read the same cached inputs that Decision used on its last beat. Do not
-- rescan the world or assess Needs here: either could change this drive test.
local function driveDiagnosis(SC, actor, native)
    local function read(module, method, ...)
        if type(module) ~= "table" or type(module[method]) ~= "function" then return nil end
        local ok, value = pcall(module[method], ...)
        return ok and value or nil
    end
    local job = read(SC.Driving, "jobStatus", actor) or {}
    local decision = read(SC.Decision, "peek", actor) or {}
    local id = read(SC.Registry, "idOf", actor)
    local record = id and read(SC.Registry, "byId", id) or nil
    local runtime = record and record.runtime or {}
    local snapshot = runtime.snapshot or (runtime.senses and runtime.senses.current)
        or read(SC.Senses, "cached", actor, runtime) or {}
    local player = type(snapshot.player) == "table" and snapshot.player or {}
    local medical = read(SC.Medical, "assessCached", actor, nil, 750) or {}
    local needs = read(SC.Needs, "peek", actor) or {}
    local commands = read(SC.Commands, "peek", actor) or {}
    local token = read(SC.ActionSupervisor, "current", actor) or {}
    local history = read(SC.ActionSupervisor, "history", actor, 2) or {}
    local events = {}
    for _, entry in ipairs(history) do
        events[#events + 1] = tostring(entry.event) .. "/" .. tostring(entry.owner)
            .. "/" .. tostring(entry.reason)
    end
    local pressure = read(SC.Decision, "_engagementPressure", snapshot)
    local hunger = tonumber(needs.hunger)
    local thirst = tonumber(needs.thirst)
    local U = SC.GameplayUtil
    local hungerLimit = tonumber(read(U, "config", "needsHungerEmergency")) or 0.82
    local thirstLimit = tonumber(read(U, "config", "needsThirstEmergency")) or 0.75
    local needsEmergency = hunger ~= nil and hunger >= hungerLimit
        or thirst ~= nil and thirst >= thirstLimit
    return "job=" .. tostring(job.phase) .. "/" .. tostring(job.result)
        .. "/" .. tostring(job.reason)
        .. ";native=" .. tostring(native.state) .. "/" .. tostring(native.active)
        .. "/" .. tostring(native.reason)
        .. ";decision=" .. tostring(decision.current) .. "/" .. tostring(decision.intent)
        .. "/runtime:" .. tostring(runtime.lastDecision)
        .. ";owner=" .. tostring(token.owner) .. "/" .. tostring(token.action)
        .. ";senses=" .. tostring(snapshot.immediateCount) .. "/"
        .. tostring(snapshot.threatCount) .. "/" .. fmt(pressure)
        .. "/human:" .. tostring(snapshot.humanThreat ~= nil)
        .. "/player:" .. fmt(player.danger) .. "/" .. tostring(player.immediateThreats)
        .. ";medical=" .. tostring(medical.alive) .. "/" .. fmt(medical.health)
        .. "/critical:" .. tostring(medical.critical)
        .. "/downed:" .. tostring(medical.downed)
        .. "/bleeding:" .. tostring(medical.bleedingCount)
        .. ";needs=" .. fmt(hunger) .. "/" .. fmt(thirst)
        .. "/emergency:" .. tostring(needsEmergency)
        .. ";order=" .. tostring(commands.order)
        .. ";supervisor=" .. table.concat(events, ",")
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
        .. "|blocked_point=" .. fmt(status.blockedX) .. "," .. fmt(status.blockedY)
        .. "|game_speed=" .. tostring(speedOk and gameSpeed or "?")
        .. "|diag=" .. driveDiagnosis(SurvivorCompanion, test.actor, status)
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

local function flatDistance(ax, ay, bx, by)
    return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
end

local function distanceToSegment(px, py, ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    local lengthSquared = dx * dx + dy * dy
    if lengthSquared < 0.001 then return flatDistance(px, py, ax, ay) end
    local fraction = math.max(0, math.min(1,
        ((px - ax) * dx + (py - ay) * dy) / lengthSquared))
    return flatDistance(px, py, ax + dx * fraction, ay + dy * fraction)
end

-- Reject a mapped alternate whose squares have not been loaded around the
-- observer. A paper road alone cannot prove a car can make this live detour.
local function loadedAlternate(U, route, goal, blockX, blockY)
    local points = route and route.points or nil
    if type(points) ~= "table" or #points < 2 or #points > 512 then
        return false, "planner returned no bounded alternate"
    end
    local last = points[#points]
    if type(last.x) ~= "number" or type(last.y) ~= "number" then
        return false, "alternate has a malformed end point"
    end
    if flatDistance(last.x, last.y, goal.x, goal.y) > 8 then
        return false, "alternate ends short of the goal"
    end
    local samples, length = 0, 0
    for index = 2, #points do
        local first, second = points[index - 1], points[index]
        if type(first.x) ~= "number" or type(first.y) ~= "number"
            or type(second.x) ~= "number" or type(second.y) ~= "number" then
            return false, "alternate has a malformed point"
        end
        if distanceToSegment(blockX, blockY,
                first.x, first.y, second.x, second.y) < 11 then
            return false, "alternate still crosses the blocked circle"
        end
        local leg = flatDistance(first.x, first.y, second.x, second.y)
        length = length + leg
        for step = 0, math.max(1, math.ceil(leg / 4)) do
            samples = samples + 1
            if samples > 256 then return false, "alternate exceeds loaded probe bounds" end
            local fraction = step / math.max(1, math.ceil(leg / 4))
            local square = U.gridSquare(math.floor(first.x
                + (second.x - first.x) * fraction),
                math.floor(first.y + (second.y - first.y) * fraction), 0)
            if square == nil then
                return false, "alternate crosses an unloaded square"
            end
        end
    end
    return true, "points=" .. #points .. " sampled=" .. samples
        .. " length=" .. fmt(length)
end

-- The route fixture helpers below are shared by the newer WP5 probes.
local roadPoint, placeWreck, watchFrom, settled, recordWrecks, untouched
local failTo, stationary

local function snapshotHasKey(snapshot, wanted)
    local function visit(node)
        if type(node) ~= "table" then return false end
        if type(node.key) == "table" and tonumber(node.key.id) == wanted then
            return true
        end
        for _, child in ipairs(node.children or {}) do
            if visit(child) then return true end
        end
        return false
    end
    for _, root in ipairs(snapshot and snapshot.roots or {}) do
        if visit(root) then return true end
    end
    return false
end

local function snapshotKeyIds(snapshot)
    local ids = {}
    local function visit(node)
        if type(node) ~= "table" or #ids >= 8 then return end
        if type(node.key) == "table" then
            ids[#ids + 1] = tostring(node.key.id)
        end
        for _, child in ipairs(node.children or {}) do visit(child) end
    end
    for _, root in ipairs(snapshot and snapshot.roots or {}) do visit(root) end
    return table.concat(ids, ",")
end

-- Count the exact key in the live native inventory, including bags. A
-- boolean haveThisKeyId check alone cannot catch a duplicated handover.
local function liveKeyCount(actor, keyId)
    local inventory = call(actor, "getInventory")
    if inventory == nil or keyId == nil then return nil end
    local seen, visited, found = {}, 0, 0
    local function visit(container, depth)
        if container == nil or seen[container] or depth > 12 then return false end
        seen[container] = true
        local items = call(container, "getItems")
        local count = tonumber(call(items, "size"))
        if count == nil or count < 0 or count > 2048 then return false end
        for index = 0, count - 1 do
            visited = visited + 1
            if visited > 2048 then return false end
            local item = call(items, "get", index)
            if item == nil then return false end
            if tonumber(call(item, "getKeyId")) == keyId then
                found = found + 1
            end
            local nested = call(item, "getInventory")
            if nested ~= nil and not visit(nested, depth + 1) then return false end
        end
        return true
    end
    return visit(inventory, 0) and found or nil
end

local function readableLoadedVehicles()
    local cell = type(getCell) == "function" and getCell() or nil
    local vehicles = cell and call(cell, "getVehicles") or nil
    local count = tonumber(call(vehicles, "size"))
    if count == nil or count < 0 or count > 512 then
        return nil, count, "invalid_collection_size"
    end
    if count > 0 and call(vehicles, "get", 0) == nil then
        -- Build 42 exposes IsoCell.getVehicles() as a Java Set. Its iterator
        -- implementation is not reliably exposed to Lua, but the stock game
        -- uses the Collection constructor to copy Set entries into a List.
        local copied, list = pcall(function() return ArrayList.new(vehicles) end)
        if not copied or list == nil or tonumber(call(list, "size")) ~= count then
            return nil, count, "set_copy_failed"
        end
        vehicles = list
    end
    return vehicles, count, "readable"
end

local function loadedCarBySqlId(sqlId)
    local vehicles, count = readableLoadedVehicles()
    if vehicles == nil or sqlId == nil then return nil end
    for index = 0, math.min(count, 512) - 1 do
        local item = call(vehicles, "get", index)
        if item and tonumber(call(item, "getSqlId")) == sqlId then
            return item
        end
    end
    return nil
end

local function loadedVehicleDiagnostic()
    local vehicles, count, readReason = readableLoadedVehicles()
    local entries = {}
    for index = 0, math.min(count or 0, 32) - 1 do
        local vehicle = call(vehicles, "get", index)
        entries[#entries + 1] = tostring(call(vehicle, "getSqlId"))
            .. "@" .. fmt(call(vehicle, "getX"))
            .. "," .. fmt(call(vehicle, "getY"))
    end
    return count, readReason, table.concat(entries, ";")
end

local function saveStep(H, SC, current, check, result, setPhase, test)
    local vehicle, actor = test.vehicle, test.actor
    if H.phase == "drive_save_start" then
        test.saveStartX, test.saveStartY = vehicle:getX(), vehicle:getY()
        local started, why = SC.Driving.drive(actor, test.goal, { speedKmh = 10 })
        if not check("drive_save_job_started", started == true,
                tostring(why)) then
            setPhase("finish", current) return
        end
        setPhase("drive_save_moving", current)
        return
    end
    if H.phase == "drive_save_moving" then
        local job = SC.Driving.jobStatus(actor) or {}
        if job.phase == "failed" or job.phase == "released" then
            failTo(H, test, setPhase, result, current,
                "drive_save_midroute", "job stopped: " .. tostring(job.reason))
            return
        end
        local moved = flatDistance(vehicle:getX(), vehicle:getY(),
            test.saveStartX, test.saveStartY)
        local speed = math.abs(tonumber(vehicle:getCurrentSpeedKmHour()) or 0)
        if job.phase == "following" and moved >= 6 and speed >= 4 then
            local id = SC.Registry.idOf(actor)
            local sqlId = tonumber(call(vehicle, "getSqlId"))
            local keyId = tonumber(call(vehicle, "getKeyId"))
            local saved, document = SC.Runtime.save()
            local entry = saved and document and document.companions
                and document.companions[id] or nil
            local seat = tonumber(call(vehicle, "getSeat", actor))
            local savedVehicle = entry and entry.vehicle or nil
            local nativeIdentity = savedVehicle and savedVehicle.vehicle or nil
            local nativeDriver = SC.Driving.isDriver(actor)
            local liveKey = SC.Driving.hasKey(actor, vehicle)
            local liveCount = liveKeyCount(actor, keyId)
            local savedKey = snapshotHasKey(entry and entry.inventory, keyId)
            local ignitionItem = call(vehicle, "getCurrentKey")
            local ignitionKeyId = tonumber(call(ignitionItem, "getKeyId"))
            local ignitionKey = call(vehicle, "isKeysInIgnition") == true
                and ignitionKeyId ~= nil and ignitionKeyId == keyId
            local keyLocation = liveKey and savedKey and liveCount == 1 and "inventory"
                or ignitionKey and not savedKey and liveCount == 0
                    and "ignition" or "missing"
            local observerX, observerY = SC.GameplayUtil.position(H.player)
            local observerGap = observerX and observerY and flatDistance(
                observerX, observerY, vehicle:getX(), vehicle:getY()) or math.huge
            if not check("drive_save_stage_persisted_seat_zero",
                    saved == true and type(id) == "string"
                        and seat == 0 and sqlId ~= nil and sqlId >= 0
                        and keyId ~= nil and keyId >= 0
                        and nativeDriver
                        and observerGap <= 12
                        and keyLocation ~= "missing"
                        and savedVehicle and savedVehicle.stored == false
                        and savedVehicle.seat == 0
                        and nativeIdentity and nativeIdentity.sqlId == sqlId,
                    "save=" .. tostring(saved)
                        .. " id=" .. tostring(id)
                        .. " seat=" .. tostring(seat)
                        .. " saved_seat=" .. tostring(savedVehicle and savedVehicle.seat)
                        .. " sql=" .. tostring(sqlId)
                        .. " saved_sql=" .. tostring(nativeIdentity and nativeIdentity.sqlId)
                        .. " key=" .. tostring(keyId)
                        .. " native_driver=" .. tostring(nativeDriver)
                        .. " live_key=" .. tostring(liveKey)
                        .. " live_key_count=" .. tostring(liveCount)
                        .. " ignition=" .. tostring(call(vehicle, "isKeysInIgnition"))
                        .. " ignition_key_id=" .. tostring(ignitionKeyId)
                        .. " key_location=" .. keyLocation
                        .. " stored=" .. tostring(savedVehicle and savedVehicle.stored)
                        .. " inventory_schema=" .. tostring(entry and entry.inventory
                            and entry.inventory.schema)
                        .. " inventory_roots=" .. tostring(entry and entry.inventory
                            and entry.inventory.roots and #entry.inventory.roots)
                        .. " saved_key=" .. tostring(savedKey)
                        .. " saved_key_ids=" .. snapshotKeyIds(entry and entry.inventory)
                        .. " observer_gap=" .. fmt(observerGap)
                        .. " moved=" .. fmt(moved)
                        .. " speed=" .. fmt(speed)) then
                setPhase("finish", current) return
            end
            local signalled = H.drivingSignals.write(
                "SurvivorCompanionHarness/driving-save-stage.txt", {
                    "SC_DRIVING_STAGE_V1",
                    "actor_id=" .. id,
                    "sql_id=" .. tostring(sqlId),
                    "key_id=" .. tostring(keyId),
                    "key_location=" .. keyLocation,
                    "car_x=" .. string.format("%.2f", vehicle:getX()),
                    "car_y=" .. string.format("%.2f", vehicle:getY()),
                })
            check("drive_save_stage_proof_written", signalled == true,
                "seat zero and exact key verified in inventory or native ignition")
            setPhase("finish", current)
            return
        end
        if current - H.phaseStartedAt > 90000 then
            failTo(H, test, setPhase, result, current,
                "drive_save_midroute", "timeout phase=" .. tostring(job.phase)
                    .. " moved=" .. fmt(moved) .. " speed=" .. fmt(speed))
        end
    end
end

local function resumeStep(H, SC, current, check, result, setPhase)
    local expected = H.config
    local id = expected.driving_expected_actor_id
    local sqlId = tonumber(expected.driving_expected_sql_id)
    local keyId = tonumber(expected.driving_expected_key_id)
    local keyLocation = expected.driving_expected_key_location
    local record = SC.Registry.byId(id)
    local actor = record and record.actor or nil
    local vehicle = sqlId and loadedCarBySqlId(sqlId) or nil
    if actor == nil or vehicle == nil then
        if current - H.phaseStartedAt > 35000 then
            local carX = tonumber(expected.driving_expected_car_x)
            local carY = tonumber(expected.driving_expected_car_y)
            local carSquare = carX and carY and SC.GameplayUtil.gridSquare(
                math.floor(carX), math.floor(carY), 0) or nil
            local loadedCount, readReason, loadedIds = loadedVehicleDiagnostic()
            result("FAIL", "drive_save_resume_loaded",
                "actor=" .. tostring(actor) .. " car=" .. tostring(vehicle)
                    .. " sql=" .. tostring(sqlId)
                    .. " player=" .. fmt(call(H.player, "getX")) .. ","
                    .. fmt(call(H.player, "getY"))
                    .. " actor_pos=" .. fmt(call(actor, "getX")) .. ","
                    .. fmt(call(actor, "getY"))
                    .. " saved_car=" .. fmt(carX) .. "," .. fmt(carY)
                    .. " car_square=" .. tostring(carSquare ~= nil)
                    .. " loaded_vehicle_count=" .. tostring(loadedCount)
                    .. " vehicle_read=" .. tostring(readReason)
                    .. " loaded_vehicles=" .. loadedIds)
            setPhase("finish", current)
        end
        return
    end
    local savedDocument = SC.Persistence.lastDocument()
    local saved = savedDocument and savedDocument.companions
        and savedDocument.companions[id] or nil
    local door = SC.Vehicle.reloadedCarSquare({ sqlId = sqlId, seat = 0 })
    local ax, ay = actor:getX(), actor:getY()
    local gap = door and flatDistance(ax, ay,
        door:getX() + 0.5, door:getY() + 0.5) or math.huge
    if H.phase == "drive_save_resume_wait" then
        local savedKey = snapshotHasKey(saved and saved.inventory, keyId)
        local ignitionItem = call(vehicle, "getCurrentKey")
        local ignitionKeyId = tonumber(call(ignitionItem, "getKeyId"))
        local ignitionKey = call(vehicle, "isKeysInIgnition") == true
            and ignitionKeyId ~= nil and ignitionKeyId == keyId
        local actorHasKey = SC.Driving.hasKey(actor, vehicle)
        local actorKeyCount = liveKeyCount(actor, keyId)
        local recoveredKey = actorHasKey and actorKeyCount == 1
            and ignitionItem == nil
            and call(vehicle, "isKeysInIgnition") ~= true
        if not check("drive_save_resume_loaded",
                saved ~= nil and saved.vehicle ~= nil
                    and saved.vehicle.stored == false
                    and saved.vehicle.seat == 0
                    and saved.vehicle.vehicle
                    and saved.vehicle.vehicle.sqlId == sqlId
                    and (keyLocation == "inventory" and savedKey
                        or keyLocation == "ignition" and not savedKey
                            and (ignitionKey or recoveredKey))
                    and vehicle:getKeyId() == keyId,
                "saved_seat=" .. tostring(saved and saved.vehicle
                    and saved.vehicle.seat)
                    .. " saved_sql=" .. tostring(saved and saved.vehicle
                    and saved.vehicle.vehicle and saved.vehicle.vehicle.sqlId)
                    .. " car_sql=" .. tostring(sqlId)
                    .. " key_location=" .. tostring(keyLocation)
                    .. " saved_key=" .. tostring(savedKey)
                    .. " ignition=" .. tostring(call(vehicle, "isKeysInIgnition"))
                    .. " ignition_key_id=" .. tostring(ignitionKeyId)
                    .. " actor_key=" .. tostring(actorHasKey)
                    .. " actor_key_count=" .. tostring(actorKeyCount)
                    .. " recovered_key=" .. tostring(recoveredKey)) then
            setPhase("finish", current) return
        end
        if not check("drive_save_resume_on_foot_at_driver_door",
                actor:getVehicle() == nil and vehicle:getDriver() == nil
                    and door ~= nil and gap <= 2.2,
                "actor=" .. fmt(ax) .. "," .. fmt(ay)
                    .. " door=" .. tostring(door and door:getX()) .. ","
                    .. tostring(door and door:getY()) .. " gap=" .. fmt(gap)) then
            setPhase("finish", current) return
        end
        setPhase("drive_save_resume_key_wait", current)
        return
    end
    if H.phase == "drive_save_resume_key_wait" then
        -- The committed actor may need a bounded retry to take the exact
        -- ignition item after the car joins the loaded cell. A short delay
        -- does not turn an absent or duplicated key into a passing result.
        local keyCount = liveKeyCount(actor, keyId)
        local exactRecovered = SC.Driving.hasKey(actor, vehicle)
            and keyCount == 1 and call(vehicle, "getCurrentKey") == nil
            and call(vehicle, "isKeysInIgnition") ~= true
        if not exactRecovered and current - H.phaseStartedAt < 15000 then return end
        local positionError = flatDistance(vehicle:getX(), vehicle:getY(),
            tonumber(expected.driving_expected_car_x) or -9999,
            tonumber(expected.driving_expected_car_y) or -9999)
        if not check("drive_save_resume_key_and_park",
                exactRecovered and stationary(vehicle) and positionError <= 5,
                "key=" .. tostring(SC.Driving.hasKey(actor, vehicle))
                    .. " key_count=" .. tostring(keyCount)
                    .. " ignition=" .. tostring(call(vehicle, "isKeysInIgnition"))
                    .. " current_key=" .. tostring(call(vehicle, "getCurrentKey"))
                    .. " speed=" .. fmt(vehicle:getCurrentSpeedKmHour())
                    .. " car_shift=" .. fmt(positionError)) then
            setPhase("finish", current) return
        end
        H.driveResumeCarX, H.driveResumeCarY = vehicle:getX(), vehicle:getY()
        setPhase("drive_save_resume_observe", current)
        return
    end
    if H.phase == "drive_save_resume_observe" then
        if current - H.phaseStartedAt < 5000 then return end
        local native = SC.Driving.status(actor) or {}
        local job = SC.Driving.jobStatus(actor) or {}
        check("drive_save_resume_no_automatic_drive",
            actor:getVehicle() == nil and vehicle:getDriver() == nil
                and stationary(vehicle) and native.active ~= true
                and (job.phase == nil or job.phase == "released"
                    or job.phase == "failed")
                and flatDistance(vehicle:getX(), vehicle:getY(),
                    H.driveResumeCarX, H.driveResumeCarY) <= 0.3,
            "native_active=" .. tostring(native.active)
                .. " job=" .. tostring(job.phase)
                .. " car_shift=" .. fmt(flatDistance(vehicle:getX(), vehicle:getY(),
                    H.driveResumeCarX, H.driveResumeCarY)))
        setPhase("finish", current)
    end
end

local function blockedStep(H, SC, current, check, result, setPhase, test)
    local vehicle, actor = test.vehicle, test.actor
    if H.phase == "drive_blocked_preflight" then
        local blockX, blockY = roadPoint(test, vehicle:getX(), vehicle:getY(), 20, 0)
        local goal = test.goal
        local planner = SC.ExpeditionRoute and SC.ExpeditionRoute.planAvoidingAll
        if type(planner) ~= "function" then
            failTo(H, test, setPhase, result, current,
                "drive_blocked_planner_available", "planAvoidingAll is unavailable")
            return
        end
        local alternate, why = planner(actor, goal,
            { { x = blockX, y = blockY, radius = 12 } })
        local loaded, detail = loadedAlternate(SC.GameplayUtil, alternate,
            goal, blockX, blockY)
        if not alternate or not loaded then
            result("SKIP", "drive_blocked_no_loaded_alternate",
                tostring(alternate and detail or why or detail)
                    .. " at " .. fmt(blockX) .. "," .. fmt(blockY))
            SC.Driving.stop(actor, "probe_no_loaded_alternate")
            SC.Vehicle.exit(actor, vehicle)
            setPhase("finish", current)
            return
        end
        test.blockX, test.blockY = blockX, blockY
        result("PASS", "drive_blocked_loaded_alternate", detail)
        test.wrecks = {}
        local count = math.max(3, math.ceil(test.road.width / 2))
        local direction = test.dirX ~= 0
            and (test.dirX > 0 and IsoDirections.E or IsoDirections.W)
            or (test.dirY > 0 and IsoDirections.S or IsoDirections.N)
        for index = 1, count do
            local side = (index - 1) * (test.road.width - 1.6) / (count - 1)
                - (test.road.width - 1.6) / 2
            local wx, wy = roadPoint(test, vehicle:getX(), vehicle:getY(), 20, side)
            local wreck, failure = placeWreck(SC, wx, wy, direction)
            if not wreck then
                failTo(H, test, setPhase, result, current,
                    "drive_blocked_fixture_placed", tostring(failure))
                return
            end
            test.wrecks[#test.wrecks + 1] = {
                name = "blocker_" .. index, vehicle = wreck }
        end
        result("PASS", "drive_blocked_fixture_placed",
            tostring(#test.wrecks) .. " parked cars across "
                .. fmt(test.road.width) .. " road tiles")
        watchFrom(H, test, blockX, blockY)
        setPhase("drive_blocked_settle", current)
        return
    end
    if H.phase == "drive_blocked_settle" then
        if current - H.phaseStartedAt < 2000 or not settled(test) then
            if current - H.phaseStartedAt > 12000 then
                failTo(H, test, setPhase, result, current,
                    "drive_blocked_fixture_settled", "blocker still moving")
            end
            return
        end
        recordWrecks(test)
        local normalX, normalY = -test.dirY, test.dirX
        local sides = {}
        for _, blocker in ipairs(test.wrecks) do
            sides[#sides + 1] = (blocker.vehicle:getX() - test.blockX) * normalX
                + (blocker.vehicle:getY() - test.blockY) * normalY
        end
        table.sort(sides)
        local largestGap = 0
        for index = 2, #sides do
            largestGap = math.max(largestGap, sides[index] - sides[index - 1])
        end
        if not check("drive_blocked_fixture_spans_road",
                #sides >= 3 and sides[1] <= -test.road.width / 2 + 1.2
                    and sides[#sides] >= test.road.width / 2 - 1.2
                    and largestGap <= 2.7,
                "left=" .. fmt(sides[1]) .. " right=" .. fmt(sides[#sides])
                    .. " gap=" .. fmt(largestGap)
                    .. " road_width=" .. fmt(test.road.width)) then
            setPhase("finish", current)
            return
        end
        local started, why = SC.Driving.drive(actor, test.goal, { speedKmh = 10,
            blockWaitMs = 5000 })
        if not check("drive_blocked_job_started", started == true,
                tostring(why)) then
            setPhase("finish", current) return
        end
        setPhase("drive_blocked_running", current)
        return
    end
    if H.phase == "drive_blocked_running" then
        local job = SC.Driving.jobStatus(actor) or {}
        local native = SC.Driving.status(actor) or {}
        test.sawBlocked = test.sawBlocked or job.phase == "blocked"
            or native.mode == "blocked"
        test.sawReplan = test.sawReplan or job.phase == "replanning"
        test.sawTurn = test.sawTurn or native.mode == "turning"
            or native.turnState ~= nil
        if job.phase == "failed" then
            failTo(H, test, setPhase, result, current, "drive_blocked_replanned_arrival",
                "phase=failed reason=" .. tostring(job.reason)
                    .. " attempts=" .. tostring(job.attempts))
            return
        end
        local clean, damage = untouched(test)
        if not clean then
            failTo(H, test, setPhase, result, current,
                "drive_blocked_no_contact", tostring(damage))
            return
        end
        if job.phase == "arrived" then
            local miss = flatDistance(vehicle:getX(), vehicle:getY(),
                test.goal.x, test.goal.y)
            local circles = type(job.circles) == "table" and #job.circles or 0
            check("drive_blocked_replanned_arrival", test.sawBlocked == true
                    and (test.sawReplan == true or (tonumber(job.attempts) or 0) >= 1)
                    and (tonumber(job.attempts) or 0) >= 1
                    and circles >= 1 and miss <= 6 and stationary(vehicle),
                "blocked=" .. tostring(test.sawBlocked)
                    .. " replanned=" .. tostring(test.sawReplan)
                    .. " turn=" .. tostring(test.sawTurn)
                    .. " attempts=" .. tostring(job.attempts)
                    .. " circles=" .. tostring(circles)
                    .. " miss=" .. fmt(miss))
            setPhase("drive_release", current)
            return
        end
        if current - H.phaseStartedAt > 180000 then
            failTo(H, test, setPhase, result, current,
                "drive_blocked_replanned_arrival",
                "timeout phase=" .. tostring(job.phase)
                    .. " reason=" .. tostring(job.reason)
                    .. " attempts=" .. tostring(job.attempts))
        end
    end
end

failTo = function(H, test, setPhase, result, current, name, detail)
    result("FAIL", name, detail)
    if test and test.actor then SurvivorCompanion.Driving.release(test.actor) end
    setPhase("finish", current)
end

stationary = function(vehicle)
    return math.abs(tonumber(vehicle:getCurrentSpeedKmHour()) or 99) < 0.6
end

local function decisionRuns(SC)
    local stats = SC.Scheduler and SC.Scheduler.getStats and SC.Scheduler.getStats()
    for _, task in ipairs(stats and stats.tasks or {}) do
        if task.name == "decision" then return tonumber(task.runs) end
    end
    return nil
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

-- A side street: a Nav zone across this road that meets it, long enough to
-- drive 26 tiles up, with 33 open tiles of this road before the junction.
local function findJunction(U, road, px, py)
    local horizontal = road.ax == 1
    local bandLo = horizontal and road.by or road.bx
    local bandHi = bandLo + (horizontal and road.bh or road.bw)
    local runLo = horizontal and road.bx or road.by
    local runHi = runLo + (horizontal and road.bw or road.bh)
    local line = horizontal and road.lineY or road.lineX
    local seen, best, bestDistance, reasons = {}, nil, nil, {}
    for radius = 0, 66, 3 do
        for dx = -radius, radius, 3 do
            for dy = -radius, radius, 3 do
                if math.max(math.abs(dx), math.abs(dy)) == radius then
                    local square = U.gridSquare(px + dx, py + dy, 0)
                    local zone = square and square:getZone() or nil
                    if zone ~= nil and not seen[zone] and tostring(call(zone, "getType")) == "Nav" then
                        seen[zone] = true
                        local x, y = tonumber(call(zone, "getX")), tonumber(call(zone, "getY"))
                        local w, h = tonumber(call(zone, "getWidth")), tonumber(call(zone, "getHeight"))
                        local across = horizontal and h > w or not horizontal and w > h
                        local sideLo = horizontal and x or y
                        local sideHi = sideLo + (horizontal and w or h)
                        local reachLo = horizontal and y or x
                        local reachHi = reachLo + (horizontal and h or w)
                        local centre = (sideLo + sideHi) / 2
                        local touches = reachHi >= bandLo - 2 and reachLo <= bandHi + 2
                        local roomBefore = centre - 33 >= runLo
                        local outward = reachLo < bandLo - 20 and -1 or reachHi > bandHi + 20 and 1 or 0
                        if across and touches and roomBefore and outward ~= 0
                            and (sideHi - sideLo) >= 5 and (sideHi - sideLo) <= 24 then
                            local open = horizontal
                                and corridorOpen(U, centre - 33, line, centre - 4, line, 1, 0)
                                or corridorOpen(U, line, centre - 33, line, centre - 4, 0, 1)
                            if open then
                                local distance = math.abs(centre - (horizontal and px or py))
                                if best == nil or distance < bestDistance then
                                    best = { centre = centre, outward = outward,
                                        width = sideHi - sideLo,
                                        zone = x .. "," .. y .. "," .. w .. "x" .. h }
                                    bestDistance = distance
                                end
                            elseif #reasons < 3 then
                                reasons[#reasons + 1] = "approach to " .. x .. "," .. y .. " blocked"
                            end
                        end
                    end
                end
            end
        end
    end
    return best, table.concat(reasons, "; ")
end

local function setupRoad(H, SC, check, result, setPhase, current)
    local U = SC.GameplayUtil
    if not check("drive_bridge_api", SC.Driving and SC.Driving.available(),
        "SCBridge driving calls are exposed") then
        setPhase("finish", current) return
    end
    segmentHalf = (H.config.driving_route == "true"
        or H.config.driving_blocked == "true"
        or H.config.driving_save_stage == "true"
        or H.config.driving_remote == "true"
        or H.config.team_drive_probe == "true")
        and ROUTE_SEGMENT_HALF or SEGMENT_HALF
    local px, py = U.position(H.player)
    local road, why = findRoad(U, math.floor(px), math.floor(py))
    if not check("drive_road_found", road ~= nil, road and ("zone=" .. road.zone
            .. " axis=" .. road.ax .. "," .. road.ay .. " width=" .. road.width
            .. " center=" .. fmt(road.cx) .. "," .. fmt(road.cy)) or tostring(why)) then
        setPhase("finish", current) return
    end
    if H.config.driving_turn == "true" then
        local junction, junctionWhy = findJunction(U, road, math.floor(px), math.floor(py))
        if not check("drive_street_junction", junction ~= nil, junction and ("side street "
                .. junction.zone .. " meets this road at " .. fmt(junction.centre) .. ", running "
                .. (junction.outward < 0 and "north/west" or "south/east") .. ", "
                .. junction.width .. " wide") or ("no side street found: " .. tostring(junctionWhy))) then
            setPhase("finish", current) return
        end
        local horizontal = road.ax == 1
        local line = horizontal and road.lineY or road.lineX
        local bandLo = horizontal and road.by or road.bx
        local bandHi = bandLo + (horizontal and road.bh or road.bw)
        local edge = junction.outward < 0 and bandLo or bandHi
        local goalAcross = edge + junction.outward * 26
        -- Start 28 tiles before the junction, heading towards it.
        if horizontal then
            road.sx, road.sy = junction.centre - 33, line
            road.ex, road.ey = junction.centre + 10, line
            road.cx, road.cy = junction.centre, line
            road.goal = { x = junction.centre, y = goalAcross }
        else
            road.sx, road.sy = line, junction.centre - 33
            road.ex, road.ey = line, junction.centre + 10
            road.cx, road.cy = line, junction.centre
            road.goal = { x = goalAcross, y = junction.centre }
        end
        road.junction = junction
    end
    -- Watch from the roadside, off the lane.
    local normalX, normalY = -road.ay, road.ax
    local watch
    local sides = { 1, -1 }
    -- At a junction, watch from the far side of the main road, facing the turn.
    if road.junction then sides = { -road.junction.outward, road.junction.outward } end
    local saveStage = H.config.driving_save_stage == "true"
    -- The save/reload probe must keep the stage car streamed when vanilla
    -- restores the player. The usual route camera sits near the road centre,
    -- over 30 tiles from this probe's car start, leaving its DB row in meta.
    local alongs = saveStage and { 8, 6, 10, 4, 12 } or { 0 }
    for _, along in ipairs(alongs) do
        local baseX = saveStage and road.sx + road.ax * along or road.cx
        local baseY = saveStage and road.sy + road.ay * along or road.cy
        for _, side in ipairs(sides) do
            local offset = road.width / 2 + 4
            local wx, wy = baseX + normalX * offset * side,
                baseY + normalY * offset * side
            if openSquare(U, wx, wy) then
                watch = { x = math.floor(wx), y = math.floor(wy) }
                break
            end
        end
        if watch ~= nil then break end
    end
    if saveStage and not check("drive_observer_near_stage_car", watch ~= nil
            and flatDistance(watch.x, watch.y, road.sx, road.sy) <= 18,
            watch and ("observer=" .. watch.x .. "," .. watch.y
                .. " car_start=" .. fmt(road.sx) .. "," .. fmt(road.sy))
                or "no clear roadside square near saved car") then
        setPhase("finish", current) return
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
    if H.config.team_drive_probe == "true" then
        setPhase("drive_team_setup", current)
        return
    end
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
    local settled, settleReason = SC.Vehicle.isStationary(test.vehicle)
    if settled ~= true then
        test.settledSince = nil
        if current - H.phaseStartedAt > 15000 then
            failTo(H, test, setPhase, result, current, "drive_car_settled",
                "speed=" .. fmt(test.vehicle:getCurrentSpeedKmHour())
                    .. " reason=" .. tostring(settleReason))
        end
        return
    end
    -- addVehicleDebug may settle below the probe's old 0.6 kph tolerance
    -- briefly, then move again. Boarding uses the stricter SC.Vehicle gate.
    if test.settledSince == nil then test.settledSince = current return end
    if current - test.settledSince < 750 then return end
    if not test.actor then
        -- Keep the deferred spawn unpublished while the car settles. WP5
        -- leaves Decision running, so publish and board in the same beat.
        local actor, reason = SC.Actor.pollSpawn(test.ticket)
        if not actor then
            if reason ~= "spawn_pending" or current - H.phaseStartedAt > 15000 then
                failTo(H, test, setPhase, result, current, "drive_companion_spawn", tostring(reason))
            end
            return
        end
        test.actor = actor
        test.actorReadyAt = current
        -- Legacy mechanics probes isolate the wheel. WP5 keeps normal AI on:
        -- its production drive owner must prevent a seat exit at every stop.
        if H.config.driving_with_ai ~= "true"
            and H.config.driving_blocked ~= "true"
            and H.config.driving_save_stage ~= "true"
            and H.config.driving_remote ~= "true" then
            SC.Scheduler.unregister("decision")
        end
    end
    local normalAiMode = H.config.driving_with_ai == "true"
        or H.config.driving_blocked == "true"
        or H.config.driving_save_stage == "true"
        or H.config.driving_remote == "true"
    if not normalAiMode and current - test.actorReadyAt < 1200 then return end
    local prepared, prepareReason = SC.Vehicle.preflightDriver(test.actor, test.vehicle)
    if prepared == nil then
        if prepareReason == "vehicle is moving" then
            test.settledSince = nil
            return
        end
        failTo(H, test, setPhase, result, current, "drive_board_preflight",
            tostring(prepareReason))
        return
    end
    if test.keyPrepared ~= true then
        test.keyPrepared = true
        local key = call(test.vehicle, "createVehicleKey")
        local inventory = call(test.actor, "getInventory")
        if key and inventory then
            test.key = key
            call(inventory, "AddItem", key)
        end
    end
    local boarded, status = SC.Driving.takeWheel(test.actor, test.vehicle,
        { preflight = prepared })
    if boarded ~= true and status == "vehicle is moving" then
        test.settledSince = nil
        if current - H.phaseStartedAt > 15000 then
            failTo(H, test, setPhase, result, current, "drive_car_settled",
                "boarding speed=" .. fmt(test.vehicle:getCurrentSpeedKmHour()))
        end
        return
    end
    if not check("drive_board_driver_seat", boarded == true and status == "native_seat"
            and SC.Driving.isDriver(test.actor),
        "status=" .. tostring(status) .. " key=" .. tostring(SC.Driving.hasKey(test.actor))) then
        setPhase("finish", current) return
    end
    if H.config.driving_remote == "true" then
        local road = test.road
        local horizontal = road.ax == 1
        local start = horizontal and test.vehicle:getX() or test.vehicle:getY()
        local lower = horizontal and road.bx or road.by
        local upper = lower + (horizontal and road.bw or road.bh)
        local direction = horizontal and test.dirX or test.dirY
        local finish = math.max(lower + 12, math.min(upper - 12,
            start + direction * 160))
        local gx = horizontal and finish or road.lineX
        local gy = horizontal and road.lineY or finish
        test.goal = { x = math.floor(gx), y = math.floor(gy), z = 0 }
        if not check("drive_remote_route_length",
                math.abs(finish - start) >= 130,
                "start=" .. fmt(start) .. " goal=" .. fmt(finish)
                    .. " road=" .. tostring(road.zone)) then
            setPhase("finish", current) return
        end
        local owner, why = SC.Driving.begin(test.actor, test.goal)
        if not check("drive_remote_seat_owner", owner ~= nil, tostring(why)) then
            setPhase("finish", current) return
        end
        test.remoteStartX, test.remoteStartY = test.vehicle:getX(), test.vehicle:getY()
        test.remoteStartFuel = tonumber(call(call(test.vehicle, "getPartById", "GasTank"),
            "getContainerContentAmount"))
        setPhase("drive_remote_claim", current)
        return
    end
    if H.config.driving_blocked == "true"
        or H.config.driving_save_stage == "true" then
        local distance = H.config.driving_blocked == "true" and 52 or 56
        local gx, gy = roadPoint(test, test.vehicle:getX(), test.vehicle:getY(),
            distance, 0)
        test.goal = { x = math.floor(gx), y = math.floor(gy), z = 0 }
        -- Decision is deliberately active in these probes. Own the stopped
        -- driver's seat before the block preflight or the next harness tick.
        local owner, why = SC.Driving.begin(test.actor, test.goal)
        if not check("drive_job_owner_acquired", owner ~= nil,
                "goal=" .. test.goal.x .. "," .. test.goal.y
                    .. " reason=" .. tostring(why)) then
            setPhase("finish", current) return
        end
    end
    if H.config.driving_blocked == "true" then
        test.startedAt = current
        setPhase("drive_blocked_preflight", current)
        return
    end
    if H.config.driving_save_stage == "true" then
        test.startedAt = current
        setPhase("drive_save_start", current)
        return
    end
    local started, why = SC.Driving.start(test.actor)
    if not check("drive_take_wheel", started == true,
            started == true and "held still with the engine off" or tostring(why)) then
        setPhase("finish", current) return
    end
    test.startedAt = current
    if H.config.driving_with_ai == "true" then
        local stats = SC.Scheduler.getStats()
        for _, task in ipairs(stats and stats.tasks or {}) do
            if task.name == "decision" then
                test.decisionRunsAtBoard = task.runs
                break
            end
        end
        if not check("drive_ai_decision_registered", test.decisionRunsAtBoard ~= nil,
                "decision task remains scheduled during companion driving") then
            setPhase("finish", current)
            return
        end
    end
    if H.config.driving_turn == "true" then
        test.goal = test.road.goal
        setPhase("drive_street_plan", current)
        return
    end
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
roadPoint = function(test, fromX, fromY, along, lateral)
    local normalX, normalY = -test.dirY, test.dirX
    local baseX = test.road.ax == 1 and fromX or test.road.lineX
    local baseY = test.road.ax == 1 and test.road.lineY or fromY
    return baseX + test.dirX * along + normalX * lateral,
        baseY + test.dirY * along + normalY * lateral
end

placeWreck = function(SC, x, y, direction)
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
watchFrom = function(H, test, x, y)
    local side = -(test.road.width / 2 + 4)
    local normalX, normalY = -test.dirY, test.dirX
    pcall(function()
        H.player:teleportTo(math.floor(x + normalX * side) + 0.5,
            math.floor(y + normalY * side) + 0.5, 0)
    end)
end

-- No wreck may be touched: each stays put and keeps its parts. The car's own
-- parts are reported, not judged: running down zombies dents it.
untouched = function(test)
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

settled = function(test)
    for _, item in ipairs(test.wrecks) do
        if not stationary(item.vehicle) then return false end
    end
    return true
end

recordWrecks = function(test)
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

-- This gate checks both player chunk maps. Distance alone does not prove that
-- the promoted driver owns the car's streaming area.
local function remoteChunks(test)
    local cell = type(getCell) == "function" and getCell() or nil
    if cell == nil then return nil, nil end
    local x, y = math.floor(test.vehicle:getX()), math.floor(test.vehicle:getY())
    local primary, remote = call(cell, "getChunkMap", 0), call(cell, "getChunkMap", 1)
    return call(primary, "getChunkForGridSquare", x, y),
        call(remote, "getChunkForGridSquare", x, y)
end

local function remoteStep(H, SC, current, check, result, setPhase, test)
    local actor, vehicle = test.actor, test.vehicle
    if H.phase == "drive_remote_claim" then
        if not test.remoteClaimed then
            local accepted, why = SC.ViewSession.claim("expedition", actor)
            if not check("drive_remote_slot_claimed", accepted == true, tostring(why)) then
                setPhase("finish", current) return
            end
            test.remoteClaimed = true
        end
        if type(getSpecificPlayer) ~= "function" or getSpecificPlayer(1) ~= actor then
            if current - H.phaseStartedAt > 15000 then
                failTo(H, test, setPhase, result, current,
                    "drive_remote_slot_ready", "slot 1 did not adopt the seated driver")
            end
            return
        end
        result("PASS", "drive_remote_slot_ready", "real seated leader owns slot 1")
        local awayX, awayY = math.floor(vehicle:getX()), math.floor(vehicle:getY()) + 420
        local moved = pcall(function()
            H.player:setGodMod(true)
            H.player:teleportTo(awayX + 0.5, awayY + 0.5, 0)
        end)
        if not check("drive_remote_primary_moved", moved,
                "player 0 target=" .. awayX .. "," .. awayY) then
            setPhase("finish", current) return
        end
        setPhase("drive_remote_wait_stream", current)
        return
    end
    if H.phase == "drive_remote_wait_stream" then
        local primary, remote = remoteChunks(test)
        local px, py = SC.GameplayUtil.position(H.player)
        local gap = px and flatDistance(px, py, vehicle:getX(), vehicle:getY()) or 0
        if primary == nil and remote ~= nil and gap >= 300 then
            result("PASS", "drive_remote_chunk_ownership",
                "primary_chunk=false slot1_chunk=true gap=" .. fmt(gap))
            local started, why = SC.Driving.drive(actor, test.goal, { speedKmh = 10 })
            if not check("drive_remote_first_leg_started", started == true,
                    tostring(why)) then
                setPhase("finish", current) return
            end
            test.remoteMaxSpeed10, test.remoteMaxSpeed25 = 0, 0
            setPhase("drive_remote_run10", current)
        elseif current - H.phaseStartedAt > 30000 then
            failTo(H, test, setPhase, result, current,
                "drive_remote_chunk_ownership", "primary_chunk=" .. tostring(primary ~= nil)
                    .. " slot1_chunk=" .. tostring(remote ~= nil)
                    .. " gap=" .. fmt(gap))
        end
        return
    end
    if H.phase == "drive_remote_run10" or H.phase == "drive_remote_run25" then
        local primary, remote = remoteChunks(test)
        local speed = math.abs(tonumber(vehicle:getCurrentSpeedKmHour()) or 0)
        local moved = flatDistance(vehicle:getX(), vehicle:getY(),
            test.remoteStartX, test.remoteStartY)
        local job = SC.Driving.jobStatus(actor) or {}
        if primary ~= nil or remote == nil then
            failTo(H, test, setPhase, result, current,
                "drive_remote_stream_kept", "primary=" .. tostring(primary ~= nil)
                    .. " slot1=" .. tostring(remote ~= nil) .. " distance=" .. fmt(moved))
            return
        end
        if job.result == "failed" or job.phase == "stopping" then
            failTo(H, test, setPhase, result, current,
                "drive_remote_physics", "job=" .. tostring(job.phase) .. "/"
                    .. tostring(job.reason) .. " distance=" .. fmt(moved))
            return
        end
        if H.phase == "drive_remote_run10" then
            test.remoteMaxSpeed10 = math.max(test.remoteMaxSpeed10 or 0, speed)
            if moved >= 45 then
                local stopped, why = SC.Driving.stop(actor, "remote_probe_hold")
                if not check("drive_remote_hold_stopped", stopped == true,
                        tostring(why)) then setPhase("finish", current) return end
                local lease, leaseReason = SC.Driving.begin(actor, test.goal)
                if not check("drive_remote_hold_seat_retained", lease ~= nil,
                        tostring(leaseReason)) then setPhase("finish", current) return end
                setPhase("drive_remote_hold", current)
            end
        else
            test.remoteMaxSpeed25 = math.max(test.remoteMaxSpeed25 or 0, speed)
            if job.result == "arrived" then
                local fuel = tonumber(call(call(vehicle, "getPartById", "GasTank"),
                    "getContainerContentAmount"))
                local used = test.remoteStartFuel and fuel
                    and test.remoteStartFuel - fuel or nil
                check("drive_remote_completed",
                    moved >= 125 and (test.remoteMaxSpeed10 or 0) >= 6
                        and (test.remoteMaxSpeed25 or 0) >= 15
                        and used ~= nil and used > 0,
                    "distance=" .. fmt(moved) .. " max10=" .. fmt(test.remoteMaxSpeed10)
                        .. " max25=" .. fmt(test.remoteMaxSpeed25)
                        .. " fuel_used=" .. fmt(used)
                        .. " elapsed_ms=" .. tostring(current - test.startedAt))
                setPhase("drive_release", current)
            end
        end
        if current - H.phaseStartedAt > 180000 then
            failTo(H, test, setPhase, result, current,
                "drive_remote_completed", "timed out distance=" .. fmt(moved)
                    .. " job=" .. tostring(job.phase))
        end
        return
    end
    if H.phase == "drive_remote_hold" then
        local speed = math.abs(tonumber(vehicle:getCurrentSpeedKmHour()) or 0)
        if speed <= 0.8 and current - H.phaseStartedAt >= 1000 then
            result("PASS", "drive_remote_hold_stationary",
                "speed=" .. fmt(speed) .. " second view="
                    .. tostring(getSpecificPlayer(1) == actor))
            local started, why = SC.Driving.drive(actor, test.goal, { speedKmh = 25 })
            if not check("drive_remote_resume_25", started == true,
                    tostring(why)) then setPhase("finish", current) return end
            setPhase("drive_remote_run25", current)
        elseif current - H.phaseStartedAt > 15000 then
            failTo(H, test, setPhase, result, current,
                "drive_remote_hold_stationary", "speed=" .. fmt(speed))
        end
    end
end

local function teamStep(H, SC, current, check, result, setPhase, test)
    local car = test.vehicle
    if H.phase == "drive_team_setup" then
        if current - H.phaseStartedAt < 1200 then return end
        local x, y = math.floor(car:getX()), math.floor(car:getY())
        local base = SC.BaseLife.active()
        if not base then
            local created, why = SC.BaseLife.create({ x = x, y = y, z = 0 },
                "Driving probe camp")
            if not check("team_drive_base_created", created == true,
                tostring(why)) then setPhase("finish", current) return end
        end
        local corners = {
            { x = x - 8, y = y - 6, z = 0 },
            { x = x + 8, y = y + 6, z = 0 },
        }
        local areaOk, areaWhy = SC.BaseLife.beginZone("area", corners[1])
        if areaOk then areaOk, areaWhy = SC.BaseLife.finishZone(
            corners[2], "Driving probe camp") end
        if not check("team_drive_area_marked", areaOk == true,
            tostring(areaWhy)) then setPhase("finish", current) return end
        local parkingOk, parkingWhy = SC.BaseLife.beginZone(
            "parking", corners[1])
        if parkingOk then parkingOk, parkingWhy = SC.BaseLife.finishZone(
            corners[2], "Probe parking") end
        if not check("team_drive_parking_marked", parkingOk == true,
            tostring(parkingWhy)) then setPhase("finish", current) return end
        test.parking = parkingWhy
        local records = {}
        for _, record in ipairs(SC.Registry.records()) do
            if record.actor and SC.Registry.isActive(record.actor, record.id)
                and SC.Actor.validateNative(record.actor)
                and not record.actor:isDead() then
                records[#records + 1] = record
                if #records == 3 then break end
            end
        end
        if not check("team_drive_roster", #records == 3,
            "active=" .. tostring(#records)) then
            setPhase("finish", current) return
        end
        test.team = records
        local used = {}
        for index, record in ipairs(records) do
            local doors, _, why = SC.Vehicle.boardingSquares(
                record.actor, car, index - 1, index == 1)
            if not doors or #doors == 0 then
                result("FAIL", "team_drive_door_" .. index, tostring(why))
                setPhase("finish", current) return
            end
            local square
            for _, candidate in ipairs(doors) do
                local key = tostring(candidate:getX()) .. ":"
                    .. tostring(candidate:getY())
                if not used[key] then square = candidate; used[key] = true; break end
            end
            square = square or doors[1]
            local placed, placementWhy = H.placeCombatActor(record.actor, {
                x = square:getX() + 0.5, y = square:getY() + 0.5, z = 0 })
            if not check("team_drive_member_placed_" .. index,
                placed == true, tostring(placementWhy)) then
                setPhase("finish", current) return
            end
        end
        local key = call(car, "createVehicleKey")
        local inventory = call(records[1].actor, "getInventory")
        if key and inventory then call(inventory, "AddItem", key) end
        if not check("team_drive_real_key", key ~= nil
            and SC.Driving.hasKey(records[1].actor, car),
            "exact generated car key stays with original leader") then
            setPhase("finish", current) return
        end
        local poly = SC.ExpeditionCar.footprint(car)
        if not check("team_drive_vehicle_poly_readable", poly ~= nil,
            "bridge footprint accessor") then
            setPhase("finish", current) return
        end
        result("PASS", "team_drive_vehicle_poly",
            "center=" .. fmt(car:getX()) .. "," .. fmt(car:getY())
                .. " corners=" .. fmt(poly.x1) .. "," .. fmt(poly.y1)
                .. ";" .. fmt(poly.x2) .. "," .. fmt(poly.y2)
                .. ";" .. fmt(poly.x3) .. "," .. fmt(poly.y3)
                .. ";" .. fmt(poly.x4) .. "," .. fmt(poly.y4))
        local along = test.road.ax == 1 and car:getX() or car:getY()
        local lo = test.road.ax == 1 and test.road.bx or test.road.by
        local hi = lo + (test.road.ax == 1
            and test.road.bw or test.road.bh)
        local target = math.max(lo + 12, math.min(hi - 12,
            along + (test.dirX ~= 0 and test.dirX or test.dirY) * 115))
        local destination = { x = math.floor(test.road.ax == 1
            and target or test.road.lineX),
            y = math.floor(test.road.ay == 1
                and target or test.road.lineY), z = 0 }
        local inspected, why = SC.ExpeditionCar.preflight(records,
            test.parking.id, car:getSqlId(), destination)
        if not check("team_drive_dispatch_preflight", inspected ~= nil,
            tostring(why) .. " destination=" .. destination.x
                .. "," .. destination.y) then
            setPhase("finish", current) return
        end
        local started, startWhy = SC.ExpeditionPrototype.start(records,
            { kind = "scout", destination = destination,
                travelMode = "drive", parkingZoneId = test.parking.id,
                vehicleSqlId = car:getSqlId() })
        if not check("team_drive_dispatched", started == true,
            tostring(startWhy)) then setPhase("finish", current) return end
        test.startedAt, test.lastState = current, nil
        setPhase("drive_team_running", current)
        return
    end
    if H.phase ~= "drive_team_running" then return end
    local mission = SC.ExpeditionPrototype.current()
    local trip = mission and mission.scout and mission.scout.vehicle
    local state = trip and trip.state or "mission_finished"
    if test.restartResume and state == "boarding_out" then
        test.restartSawBoarding = true
    end
    if H.config.team_drive_restart_stage == "true"
        and state == "driving_out" and not test.restartStaged
        and flatDistance(car:getX(), car:getY(),
            trip.departure.x, trip.departure.y) >= 10 then
        local saved, document = SC.Runtime.save()
        local snapshot = document and document.expedition
        local nativeSeats = true
        for index, member in ipairs(test.team) do
            local seated, actual, seat = SC.Vehicle.isNativeSeated(member.actor)
            nativeSeats = nativeSeats and seated and actual == car
                and seat == index - 1
        end
        if not check("team_drive_restart_stage_saved",
            saved == true and snapshot and snapshot.schema == 6
                and snapshot.scout and snapshot.scout.vehicle
                and snapshot.scout.vehicle.state == "driving_out"
                and snapshot.scout.vehicle.sqlId == car:getSqlId()
                and #snapshot.roster == 3 and nativeSeats,
            "saved=" .. tostring(saved) .. " state="
                .. tostring(snapshot and snapshot.scout
                    and snapshot.scout.vehicle
                    and snapshot.scout.vehicle.state)
                .. " seats=" .. tostring(nativeSeats)) then
            setPhase("finish", current) return
        end
        local signalled = H.drivingSignals.write(
            "SurvivorCompanionHarness/team-drive-stage.txt", {
                "SC_TEAM_DRIVE_STAGE_V1",
                "sql_id=" .. tostring(car:getSqlId()),
                "leader_id=" .. tostring(test.team[1].id),
                "parking_id=" .. tostring(test.parking.id),
            })
        check("team_drive_restart_stage_proof", signalled == true,
            "schema 6 and all three physical seats saved")
        test.restartStaged = true
        setPhase("finish", current)
        return
    end
    if state ~= test.lastState then
        local fit, fitWhy
        if state == "parking_home" then
            fit, fitWhy = SC.ExpeditionCar.fitsParking(
                car, test.parking, trip.seats)
        end
        result("PASS", "team_drive_state_" .. tostring(state),
            "phase=" .. tostring(mission and mission.scout.phase)
                .. " blocker=" .. tostring(trip and trip.blocker)
                .. " parked=" .. tostring(fit)
                .. " park_reason=" .. tostring(fitWhy)
                .. " x=" .. fmt(car:getX()) .. " y=" .. fmt(car:getY()))
        test.lastState = state
    end
    if trip and (state == "held" or state == "abandoned"
        or state == "boarding_rollback" or state == "fallback_unloading") then
        result("FAIL", "team_drive_full_trip", "state=" .. state
            .. " blocker=" .. tostring(trip.blocker))
        setPhase("finish", current) return
    end
    if trip and (state == "driving_out" or state == "driving_home") then
        local allSeated = true
        for index, member in ipairs(test.team) do
            local seated, actualCar, seat = SC.Vehicle.isNativeSeated(member.actor)
            allSeated = allSeated and seated and actualCar == car
                and seat == index - 1
        end
        if not allSeated then
            result("FAIL", "team_drive_full_roster_seated", state)
            setPhase("finish", current) return
        end
        if state == "driving_out" and not test.shots.team_out then
            requestShot(H, test, "team_out", result,
                "three native occupants driving in the second viewport")
        end
    end
    if trip and state == "parked_at_site"
        and not test.returnRequested
        and current - H.phaseStartedAt > 3000 then
        local requested, why = SC.ExpeditionCar.requestReturn(mission,
            current)
        if not check("team_drive_return_requested", requested == true,
            tostring(why)) then setPhase("finish", current) return end
        test.returnRequested = true
    end
    if trip and state == "home_wait" then
        local parked, reason = SC.ExpeditionCar.fitsParking(
            car, test.parking, trip.seats)
        local allOnFoot = true
        for _, member in ipairs(test.team) do
            local seated = SC.Vehicle.isNativeSeated(member.actor)
            allOnFoot = allOnFoot and not seated
        end
        check("team_drive_home_parked_and_unloaded", parked
            and allOnFoot and test.returnRequested == true
            and (not test.restartResume or test.restartSawBoarding == true),
            "parked=" .. tostring(parked) .. " reason=" .. tostring(reason)
                .. " foot=" .. tostring(allOnFoot)
                .. " fresh_boarding=" .. tostring(test.restartSawBoarding))
        setPhase("finish", current)
        return
    end
    if current - (test.startedAt or current) > 240000 then
        result("FAIL", "team_drive_full_trip_timeout",
            "state=" .. tostring(state) .. " blocker="
                .. tostring(trip and trip.blocker))
        setPhase("finish", current)
    end
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
        if H.config.driving_with_ai == "true" then
            local held, why = SC.Driving.hold(actor)
            if not check("drive_ai_hold_behind_wreck", held == true,
                    "wreck=18 tiles ahead reason=" .. tostring(why)) then
                setPhase("finish", current) return
            end
            setPhase("drive_route_ai_hold", current)
            return
        end
        local following, why = SC.Driving.followRoute(actor, test.route, ROUTE_KMH)
        if not check("drive_route_follow_started", following == true, tostring(why)) then
            setPhase("finish", current) return
        end
        setPhase("drive_route_out", current)
        return
    end

    if H.phase == "drive_route_ai_hold" then
        if current - H.phaseStartedAt < 2500 then return end
        local state = SC.Decision.peek(actor) or {}
        local runs = decisionRuns(SC)
        if not check("drive_ai_stays_seated_at_outbound_stop",
                stationary(vehicle) and SC.Driving.isDriver(actor)
                    and state.current == "driving"
                    and runs ~= nil and runs > (test.decisionRunsAtBoard or math.huge),
                "speed=" .. fmt(vehicle:getCurrentSpeedKmHour())
                    .. " decision=" .. tostring(state.current)
                    .. " runs=" .. tostring(runs)) then
            setPhase("finish", current) return
        end
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
            if H.config.driving_with_ai == "true" then
                check("drive_ai_stays_seated_during_turn",
                    SC.Driving.isDriver(actor)
                        and decisionRuns(SC) ~= nil
                        and decisionRuns(SC) > (test.decisionRunsAtBoard or math.huge),
                    "seat=0 decision_runs=" .. tostring(decisionRuns(SC))
                        .. " turn_legs=" .. tostring(status.turnLegs))
            end
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
        setPhase(H.config.driving_with_ai == "true"
            and "drive_route_ai_arrived_hold" or "drive_release", current)
        return
    end

    if H.phase == "drive_route_ai_arrived_hold" then
        if current - H.phaseStartedAt < 2500 then return end
        local state = SC.Decision.peek(actor) or {}
        local runs = decisionRuns(SC)
        check("drive_ai_stays_seated_after_arrival",
            stationary(vehicle) and SC.Driving.isDriver(actor)
                and state.current == "driving"
                and runs ~= nil and runs > (test.decisionRunsAtBoard or math.huge),
            "speed=" .. fmt(vehicle:getCurrentSpeedKmHour())
                .. " decision=" .. tostring(state.current)
                .. " runs=" .. tostring(runs))
        setPhase("drive_release", current)
    end
end

-- ---------------------------------------------------------------- street to street

local function maxBend(points)
    local worst = 0
    for index = 3, #points do
        local a, b, c = points[index - 2], points[index - 1], points[index]
        local first = math.atan2(b.y - a.y, b.x - a.x)
        local second = math.atan2(c.y - b.y, c.x - b.x)
        worst = math.max(worst, math.abs(wrap(second - first)))
    end
    return math.deg(worst)
end

local function streetStep(H, SC, current, check, result, setPhase, test)
    local vehicle, actor = test.vehicle, test.actor
    if H.phase == "drive_street_plan" then
        if current < (test.nextPlanAt or 0) then return end
        test.nextPlanAt = current + 2000
        local route, why = SC.Driving.planRoute(actor, { x = math.floor(test.goal.x),
            y = math.floor(test.goal.y), z = 0 })
        if not route then
            if current - H.phaseStartedAt > 40000 then
                failTo(H, test, setPhase, result, current, "drive_street_route", tostring(why))
            end
            return
        end
        local length = 0
        for index = 2, #route.points do
            local a, b = route.points[index - 1], route.points[index]
            length = length + math.sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2)
        end
        local bend = maxBend(route.points)
        local streets, seenStreet = {}, {}
        for _, point in ipairs(route.points) do
            local name = tostring(point.street)
            if not seenStreet[name] then seenStreet[name] = true; streets[#streets + 1] = name end
        end
        local last = route.points[#route.points]
        if not check("drive_street_route", #route.points >= 3 and bend >= 60,
            "points=" .. #route.points .. " length=" .. fmt(length) .. " sharpest bend "
                .. fmt(bend) .. " deg, streets " .. table.concat(streets, " -> ") .. ", ends "
                .. fmt(last.x) .. "," .. fmt(last.y)) then
            setPhase("finish", current) return
        end
        test.route = route
        test.routeEnd = { x = last.x, y = last.y }
        test.startHeading = heading(vehicle)
        test.legParts = partCondition(vehicle)
        local following, followWhy = SC.Driving.followRoute(actor, route, ROUTE_KMH)
        if not check("drive_street_follow_started", following == true, tostring(followWhy)) then
            setPhase("finish", current) return
        end
        setPhase("drive_street_go", current)
        return
    end

    if H.phase == "drive_street_go" then
        local status = SC.Driving.status(actor) or {}
        local turned = math.deg(wrap(heading(vehicle) - test.startHeading))
        test.maxTurned = math.max(test.maxTurned or 0, math.abs(turned))
        if math.abs(turned) >= 35 and math.abs(turned) <= 70 then
            requestShot(H, test, "corner", result, "turned " .. fmt(turned) .. " deg at "
                .. fmt(vehicle:getCurrentSpeedKmHour()) .. " km/h")
        end
        if status.mode == "blocked" then
            test.blockedSince = test.blockedSince or current
            if current - test.blockedSince > 10000 then
                failTo(H, test, setPhase, result, current, "drive_street_to_street",
                    "blocked for 10 s at " .. fmt(status.along) .. "/" .. fmt(status.routeLength)
                        .. ", obstacle " .. fmt(status.blockedAt) .. " tiles ahead")
                return
            end
        else
            test.blockedSince = nil
        end
        if status.mode == "arrived" then
            local miss = math.sqrt((vehicle:getX() - test.routeEnd.x) ^ 2
                + (vehicle:getY() - test.routeEnd.y) ^ 2)
            check("drive_street_to_street", miss <= 4 and math.abs(turned) >= 60,
                "arrived in " .. tostring(math.floor((current - H.phaseStartedAt) / 100) / 10)
                    .. " s, " .. fmt(miss) .. " tiles from the route end, turned " .. fmt(turned)
                    .. " deg, lateral in the new street " .. fmt(status.lateral)
                    .. " (lane " .. fmt(status.laneOffset) .. "), swerves=" .. tostring(status.swerves)
                    .. ", car part condition lost " .. fmt(test.legParts - partCondition(vehicle)))
            setPhase("drive_release", current)
            return
        end
        if current - H.phaseStartedAt > 90000 then
            failTo(H, test, setPhase, result, current, "drive_street_to_street", "still "
                .. tostring(status.mode) .. " after 90 s at " .. fmt(status.along) .. "/"
                .. fmt(status.routeLength))
        end
    end
end

function Probe.step(H, current, check, result, setPhase)
    local SC = SurvivorCompanion
    if H.phase == "drive_setup" then
        if H.config.team_drive_restart_resume == "true" then
            setPhase("drive_team_resume_wait", current)
            return
        end
        if current - H.phaseStartedAt < 3000 then return end
        if H.config.driving_save_resume == "true" then
            setPhase("drive_save_resume_wait", current)
            return
        end
        setupRoad(H, SC, check, result, setPhase, current)
        return
    end
    if H.phase == "drive_save_resume_wait"
        or H.phase == "drive_save_resume_key_wait"
        or H.phase == "drive_save_resume_observe" then
        resumeStep(H, SC, current, check, result, setPhase)
        return
    end
    if H.phase == "drive_team_resume_wait" then
        local mission = SC.ExpeditionPrototype.current()
        local trip = mission and mission.scout and mission.scout.vehicle
        local car = trip and SC.Vehicle.loadedBySqlId(trip.sqlId)
        if mission and trip and car and #mission.roster == 3 then
            local expected = H.config
            if not check("team_drive_restart_exact_car_team",
                tostring(trip.sqlId) == expected.team_drive_expected_sql_id
                    and mission.roster[1].id
                        == expected.team_drive_expected_leader_id
                    and trip.parkingZoneId
                        == expected.team_drive_expected_parking_id
                    and trip.state ~= "held"
                    and trip.state ~= "fallback_unloading",
                "state=" .. tostring(trip.state) .. " blocker="
                    .. tostring(trip.blocker) .. " car=" .. tostring(trip.sqlId)) then
                setPhase("finish", current) return
            end
            H.driveTest = { vehicle = car, team = mission.roster,
                parking = SC.ExpeditionCar.areaById(trip.parkingZoneId),
                startedAt = current, lastState = nil, shots = {},
                restartResume = true,
                restartSawBoarding = trip.state == "boarding_out" }
            setPhase("drive_team_running", current)
        elseif current - H.phaseStartedAt > 60000 then
            result("FAIL", "team_drive_restart_loaded",
                "mission=" .. tostring(mission ~= nil)
                    .. " car=" .. tostring(car ~= nil))
            setPhase("finish", current)
        end
        return
    end
    local test = H.driveTest
    if test == nil then setPhase("finish", current) return end
    if string.find(H.phase, "drive_team_", 1, true) == 1 then
        teamStep(H, SC, current, check, result, setPhase, test)
        return
    end
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
    if (H.config.driving_with_ai == "true"
        or H.config.driving_blocked == "true"
        or H.config.driving_save_stage == "true"
        or H.config.driving_remote == "true")
        and H.phase ~= "drive_release"
        and not SC.Driving.isDriver(actor) then
        local native = SC.Driving.status(actor) or {}
        failTo(H, test, setPhase, result, current,
            "drive_job_keeps_native_driver_seat",
            "companion left seat during " .. tostring(H.phase)
                .. " diag=" .. driveDiagnosis(SC, actor, native))
        return
    end
    local speed = tonumber(vehicle:getCurrentSpeedKmHour()) or 0
    if string.find(H.phase, "drive_remote_", 1, true) == 1 then
        remoteStep(H, SC, current, check, result, setPhase, test)
        return
    end
    if string.find(H.phase, "drive_blocked_", 1, true) == 1 then
        blockedStep(H, SC, current, check, result, setPhase, test)
        return
    end
    if string.find(H.phase, "drive_save_", 1, true) == 1 then
        saveStep(H, SC, current, check, result, setPhase, test)
        return
    end
    if string.find(H.phase, "drive_route_", 1, true) == 1 then
        routeStep(H, SC, current, check, result, setPhase, test)
        return
    end
    if string.find(H.phase, "drive_street_", 1, true) == 1 then
        streetStep(H, SC, current, check, result, setPhase, test)
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
