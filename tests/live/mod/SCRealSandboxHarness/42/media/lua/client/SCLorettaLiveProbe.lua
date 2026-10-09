-- SPDX-License-Identifier: MIT
-- Focused cloned-save smoke probe. The car must already exist in the world;
-- this probe never calls addVehicle or changes the source save.
local Probe = {}

local READY = "SurvivorCompanionHarness/loretta-ready.txt"
local CAPTURED = "SurvivorCompanionHarness/loretta-captured.txt"

local function call(object, method, ...)
    if not object then return nil end
    local okay, value = pcall(function(...)
        return object[method](object, ...)
    end, ...)
    return okay and value or nil
end

local function read(object, method, ...)
    if not object then return nil, false end
    local okay, value = pcall(function(...)
        return object[method](object, ...)
    end, ...)
    return value, okay
end

local function actorFor(SC, group)
    local member = group and SC.Factions.member(group.id, "member-1")
    local record = member and member.actorId and SC.Registry.byId(member.actorId)
    return record and record.actor or nil
end

local function nearbyCars(SC, point, radius)
    local cars, seen = {}, {}
    if type(point) ~= "table" then return cars end
    local x, y, z = math.floor(tonumber(point.x) or 0),
        math.floor(tonumber(point.y) or 0),
        math.floor(tonumber(point.z) or 0)
    for dy = -radius, radius do
        for dx = -radius, radius do
            local square = SC.GameplayUtil.gridSquare(x + dx, y + dy, z)
            local car = call(square, "getVehicleContainer")
            if car and not seen[car] then
                seen[car] = true
                cars[#cars + 1] = car
            end
        end
    end
    return cars
end

local function loadedCar(SC, sqlId, point)
    local cars = nearbyCars(SC, point, 5)
    for _, car in ipairs(cars) do
        if tonumber(call(car, "getSqlId")) == tonumber(sqlId)
            and call(car, "getSquare") ~= nil then
            return car, #cars
        end
    end
    return nil, #cars
end

local function describeCar(SC, H, car)
    local U = SC.GameplayUtil
    local id = tonumber(call(car, "getSqlId"))
    local seats = tonumber(call(car, "getMaxPassengers")) or 0
    local x, y, z = U.position(car)
    local px, py = U.position(H.player)
    local distance = x and px and math.floor(math.sqrt(
        (x - px) ^ 2 + (y - py) ^ 2)) or -1
    local issues = {}
    local function issue(value) issues[#issues + 1] = value end
    if not id or id <= 0 then issue("unsaved") end
    if not call(car, "getSquare") then issue("no-square") end
    if seats < 4 then issue("seats=" .. tostring(seats)) end
    local stationary = SC.Vehicle and SC.Vehicle.isStationary
        and SC.Vehicle.isStationary(car)
    if stationary ~= true then issue("moving") end
    if call(H.player, "getVehicle") == car then issue("player-inside") end
    local inventory = U.inventory(H.player)
    local keyId = tonumber(call(car, "getKeyId"))
    local ownsKey = keyId and keyId >= 0
        and select(1, read(inventory, "haveThisKeyId", keyId)) == true
    if ownsKey then issue("player-has-key") end
    for _, group in ipairs(SC.Factions.list(false) or {}) do
        local story = group.oddball
        local siteVehicle = story and story.site and story.site.vehicle
        if group.lifecycle ~= "destroyed" and story
            and (tonumber(story.carSqlId) == id
                or siteVehicle and tonumber(siteVehicle.sqlId) == id) then
            issue("claimed-by-group")
            break
        end
    end
    local partCount = tonumber(call(car, "getPartCount")) or -1
    local windows, doors = 0, 0
    for index = 0, math.min(255, partCount - 1) do
        local part = call(car, "getPartByIndex", index)
        local name = tostring(call(part, "getId") or index)
        local window = call(part, "getWindow")
        if window then
            windows = windows + 1
            local broken, brokenRead = read(window, "isDestroyed")
            local open, openRead = read(window, "isOpen")
            if not brokenRead or broken ~= false or not openRead
                or open ~= false or not call(part, "getInventoryItem") then
                issue(name .. ":window=" .. tostring(broken)
                    .. "/" .. tostring(open) .. "/"
                    .. tostring(call(part, "getInventoryItem") ~= nil))
            end
        end
        local door = call(part, "getDoor")
        if door then
            doors = doors + 1
            local open, openRead = read(door, "isOpen")
            if not openRead or open ~= false then
                issue(name .. ":door-open=" .. tostring(open))
            end
        end
    end
    if partCount < 1 or partCount > 256 then issue("parts=" .. tostring(partCount)) end
    if windows < 4 then issue("windows=" .. tostring(windows)) end
    if doors < 4 then issue("doors=" .. tostring(doors)) end
    for seat = 0, math.min(seats - 1, 7) do
        local occupied = select(1, read(car, "isSeatOccupied", seat))
        if occupied == true or call(car, "getCharacter", seat) then
            issue("occupied=" .. tostring(seat))
        end
    end
    local gas = call(car, "getPartById", "GasTank")
    if not gas or not call(gas, "getInventoryItem") then issue("no-gas-tank") end
    local rear = {}
    for _, seat in ipairs({ 2, 3 }) do
        local installed = select(1, read(car, "isSeatInstalled", seat))
        local doorPart = call(car, "getPassengerDoor", seat)
        local door = call(doorPart, "getDoor")
        local suffix = tostring(call(doorPart, "getId") or ""):match(
            "^Door(RearLeft)$") or tostring(call(doorPart, "getId") or "")
            :match("^Door(RearRight)$")
        local glass = suffix and call(car, "getPartById", "Window" .. suffix)
        local window = call(glass, "getWindow")
        local candidates = 0
        if x and installed == true and door and window then
            for dx = -4, 4 do
                for dy = -4, 4 do
                    local square = U.gridSquare(math.floor(x) + dx,
                        math.floor(y) + dy, math.floor(z or 0))
                    local safe = square and U.isSafeSpawnSquare(square)
                    if safe then
                        local rawRange = select(1, read(car,
                            "getEnterSeatDistance", seat,
                            math.floor(x) + dx + 0.5,
                            math.floor(y) + dy + 0.5))
                        local range = tonumber(rawRange)
                        if range and range >= 0 and range <= 2.56 then
                            candidates = candidates + 1
                        end
                    end
                end
            end
        end
        rear[#rear + 1] = tostring(seat) .. ":" .. tostring(installed)
            .. "/" .. tostring(door ~= nil)
            .. "/" .. tostring(window ~= nil)
            .. "/" .. tostring(call(doorPart, "getInventoryItem") ~= nil)
            .. "/" .. tostring(candidates)
    end
    local detail = "script=" .. tostring(call(car, "getScriptName"))
        .. " at=" .. tostring(x) .. "," .. tostring(y)
        .. " dist=" .. tostring(distance) .. " seats=" .. tostring(seats)
        .. " parts=" .. tostring(partCount) .. " glass=" .. tostring(windows)
        .. " doors=" .. tostring(doors) .. " rear(inst/door/glass/item/safe)="
        .. table.concat(rear, ",") .. " issues="
        .. (#issues > 0 and table.concat(issues, ",") or "none")
    return id, distance, detail
end

local function diagnoseLoadedCars(SC, H, result)
    local cell = type(getCell) == "function" and getCell() or nil
    local vehicles = call(cell, "getVehicles") or call(cell, "getVehicleList")
    local listedCount = vehicles and SC.NativeList.size(vehicles) or 0
    local iterator, iteratorRead = read(vehicles, "iterator")
    local hasNext, hasNextRead = read(iterator, "hasNext")
    local first, nextRead
    if hasNext == true then first, nextRead = read(iterator, "next") end
    local x, y, z = SC.GameplayUtil.position(H.player)
    local cars = nearbyCars(SC, { x = x, y = y, z = z }, 20)
    local observerSquare = x and SC.GameplayUtil.gridSquare(
        math.floor(x), math.floor(y), math.floor(z or 0)) or nil
    local observerCar = call(observerSquare, "getVehicleContainer")
    result("SKIP", "loretta_vehicle_access",
        "native-list-size=" .. tostring(listedCount)
            .. " spatial-cars=" .. tostring(#cars)
            .. " radius=20 observer-sql="
            .. tostring(call(observerCar, "getSqlId"))
            .. "; native list elements are unavailable in Build 42")
    result("SKIP", "loretta_vehicle_set_iterator",
        "iterator=" .. tostring(iteratorRead)
            .. "/" .. tostring(iterator)
            .. " hasNext=" .. tostring(hasNextRead)
            .. "/" .. tostring(hasNext)
            .. " next=" .. tostring(nextRead)
            .. "/" .. tostring(first)
            .. " firstSql=" .. tostring(call(first, "getSqlId")))
    local nearest, nearestDistance
    for _, car in ipairs(cars) do
        local id, distance, detail = describeCar(SC, H, car)
        result("SKIP", "loretta_candidate_sql_" .. tostring(id), detail)
        if distance >= 0 and (not nearestDistance or distance < nearestDistance) then
            nearest, nearestDistance = detail, distance
        end
    end
    return listedCount, nearest
end

local function waitAwayFromDoor(SC, H, site)
    local door = site.vehicle and site.vehicle.door or site.spawn
    if not door then return false end
    local x, y = SC.GameplayUtil.position(H.player)
    if x and (x - door.x) ^ 2 + (y - door.y) ^ 2 > 49 then
        return true
    end
    -- Keep the observer and car streamed while the native faction queue
    -- spawns Loretta, without accidentally starting her first-sight clock.
    for radius = 9, 14 do
        for dy = -radius, radius do
            for dx = -radius, radius do
                if math.max(math.abs(dx), math.abs(dy)) == radius then
                    local square = SC.GameplayUtil.gridSquare(
                        door.x + dx, door.y + dy, door.z or 0)
                    if square and SC.GameplayUtil.isSafeSpawnSquare(square)
                        and call(square, "getRoom") == nil then
                        return pcall(function()
                            H.player:teleportTo(square:getX() + 0.5,
                                square:getY() + 0.5, square:getZ())
                        end)
                    end
                end
            end
        end
    end
    return false
end

local function sealedGate(SC, actor, group)
    local moduleGate, moduleReason = SC.OddballLoretta.zombiesIgnore(actor,
        group)
    local oddballGate, oddballReason = SC.Oddballs.isZombieIgnored(actor)
    local getterValue, getterRead = SC.GameplayUtil.call(actor,
        "isZombiesDontAttack")
    local setterResolved = select(1, SC.Call.resolve(actor,
        "setZombiesDontAttack"))
    local valid = moduleGate == true and oddballGate == true
        and setterResolved == true
        and (getterRead ~= true or getterValue == true)
    return valid, "module=" .. tostring(moduleGate)
        .. "/" .. tostring(moduleReason)
        .. " oddballs=" .. tostring(oddballGate)
        .. "/" .. tostring(oddballReason)
        .. " nativeGetter=" .. tostring(getterRead)
        .. "/" .. tostring(getterValue)
        .. " nativeSetterAvailable=" .. tostring(setterResolved)
end

local function taggedDarren(SC, group)
    local cell = type(getCell) == "function" and getCell() or nil
    local zombies = call(cell, "getZombieList")
    if not zombies then return nil, 0, 0 end
    local count = SC.NativeList.size(zombies)
    local maximum = math.min(1024, count)
    local iterator = call(zombies, "iterator")
    for index = 0, maximum - 1 do
        local zombie
        if iterator then
            if call(iterator, "hasNext") ~= true then
                return nil, index, count
            end
            zombie = call(iterator, "next")
        else
            zombie = SC.NativeList.get(zombies, index)
        end
        local data = zombie and SC.GameplayUtil.modData(zombie)
        if data and data.lfLorettaDarrenGroupId == group.id then
            return zombie, index + 1, count
        end
    end
    return nil, maximum, count
end

local function darrenState(SC, group, car)
    local story = group.oddball
    local zombie, scanned, count = taggedDarren(SC, group)
    local inventory = zombie and SC.GameplayUtil.inventory(zombie)
    local carKeyId = tonumber(call(car, "getKeyId"))
    local keyReadable = inventory ~= nil and carKeyId ~= nil
        and carKeyId >= 0
    local keyMatches = false
    if keyReadable then
        local hasKey, checked = SC.GameplayUtil.call(inventory,
            "haveThisKeyId", carKeyId)
        if checked then keyMatches = hasKey == true end
        if not keyMatches then
            for _, item in ipairs(SC.GameplayUtil.inventoryItemsDeep(
                inventory, 120, 4)) do
                if SC.GameplayUtil.itemType(item) == "Base.CarKey"
                    and tonumber(call(item, "getKeyId")) == carKeyId then
                    keyMatches = true
                    break
                end
            end
        end
    end
    local valid = story.darrenSpawned == true
        and story.darrenKeyPlaced == true and zombie ~= nil
        and (not keyReadable or keyMatches)
    local point = story.darrenPoint
    local detail = "spawned=" .. tostring(story.darrenSpawned)
        .. " keyPlaced=" .. tostring(story.darrenKeyPlaced)
        .. " taggedLoaded=" .. tostring(zombie ~= nil)
        .. " zombieScan=" .. tostring(scanned) .. "/" .. tostring(count)
        .. " point=" .. tostring(point and point.x)
            .. "," .. tostring(point and point.y)
        .. " carKeyId=" .. tostring(carKeyId)
        .. " keyReadable=" .. tostring(keyReadable)
        .. " keyMatches=" .. tostring(keyMatches)
    return valid, detail
end

local function restoreSpeech(H)
    if H.lorettaOriginalSay and SurvivorCompanion
        and SurvivorCompanion.GameplayUtil then
        SurvivorCompanion.GameplayUtil.say = H.lorettaOriginalSay
    end
    H.lorettaOriginalSay = nil
end

local function fail(H, result, setPhase, current, name, detail)
    restoreSpeech(H)
    result("FAIL", name, detail)
    setPhase("finish", current)
end

function Probe.step(H, current, check, result, setPhase)
    local SC = SurvivorCompanion
    if H.phase == "loretta_prepare" then
        if current - H.phaseStartedAt < 1500 then return end
        local definition = SC.Oddballs and SC.Oddballs.definition
            and SC.Oddballs.definition("loretta_ten_and_two") or nil
        if not check("loretta_definition_and_site_selector",
            definition ~= nil and SC.OddballLoretta
                and type(SC.OddballLoretta.siteFor) == "function",
            "loretta_ten_and_two with real parked-car selector") then
            setPhase("finish", current) return
        end
        H.lorettaDefinition = definition
        pcall(function() getGameTime():setTimeOfDay(12.0) end)
        if SC.Scheduler then SC.Scheduler.unregister("decision") end
        pcall(function() if SC.UI then SC.UI.close() end end)
        pcall(function() getPlayerInventory(0):setVisible(false) end)
        pcall(function() getPlayerLoot(0):setVisible(false) end)
        pcall(function()
            getCore():setAutoZoom(0, false)
            for _ = 1, 4 do getCore():doZoomScroll(0, -1) end
        end)
        local x = tonumber(H.config.loretta_site_x) or 0
        local y = tonumber(H.config.loretta_site_y) or 0
        if x > 0 and y > 0 then
            local moved = pcall(function()
                H.player:teleportTo(x + 0.5, y + 0.5, 0)
            end)
            if not check("loretta_parking_area_loaded", moved,
                "observer moved to " .. tostring(x) .. "," .. tostring(y)
                    .. " in disposable clone") then
                setPhase("finish", current) return
            end
        end
        pcall(function() H.player:setInvisible(true) end)
        setPhase("loretta_find_car", current)
        return
    end

    if H.phase == "loretta_find_car" then
        if current - H.phaseStartedAt < 2500 then return end
        local site = SC.OddballLoretta.siteFor(H.player, true, 0, 100)
        if not site then
            if current - H.phaseStartedAt > 20000 then
                local count, nearest = diagnoseLoadedCars(SC, H, result)
                fail(H, result, setPhase, current, "loretta_real_parked_car_site",
                    "no eligible loaded saved four-seat car within 100 tiles; "
                        .. "loaded vehicles=" .. tostring(count)
                        .. "; nearest: " .. tostring(nearest))
            end
            return
        end
        local sqlId = tonumber(site.carSqlId or site.vehicle and site.vehicle.sqlId)
        local seat = tonumber(site.seat or site.vehicle and site.vehicle.seat)
        local car, count = loadedCar(SC, sqlId, site.spawn)
        local actualSqlId = tonumber(call(car, "getSqlId"))
        if not check("loretta_real_parked_car_site",
            car ~= nil and sqlId ~= nil and sqlId > 0
                and actualSqlId == sqlId and (seat == 2 or seat == 3)
                and SC.Vehicle.isStationary(car) == true,
            "sqlId=" .. tostring(sqlId) .. " seat=" .. tostring(seat)
                .. " nearby spatial cars=" .. tostring(count)
                .. " script=" .. tostring(call(car, "getScriptName"))) then
            setPhase("finish", current) return
        end
        H.lorettaSite, H.lorettaCar = site, car
        if not check("loretta_observer_waits_away",
            waitAwayFromDoor(SC, H, site),
            "first-sight clock remains unstarted until the native seat is verified") then
            setPhase("finish", current) return
        end
        local group, reason = SC.Factions.createOddballGroup(
            site, H.lorettaDefinition, true)
        if not check("loretta_native_group_created", group ~= nil,
            tostring(reason)) then
            setPhase("finish", current) return
        end
        H.lorettaGroup = group
        setPhase("loretta_native_spawn", current)
        return
    end

    if H.phase == "loretta_native_spawn" then
        local actor = actorFor(SC, H.lorettaGroup)
        if not actor then
            if current - H.phaseStartedAt > 30000 then
                fail(H, result, setPhase, current, "loretta_native_actor_spawned",
                    "faction spawn queue did not produce Loretta")
            end
            return
        end
        local story = H.lorettaGroup.oddball
        local seated, vehicle, seat = SC.Vehicle.isNativeSeated(actor)
        if seated ~= true then
            if current - H.phaseStartedAt > 30000 then
                fail(H, result, setPhase, current, "loretta_native_actor_seated",
                    "actor spawned but native board did not complete; carPrepared="
                        .. tostring(story.carPrepared))
            end
            return
        end
        H.lorettaActor = actor
        local car = H.lorettaCar
        local expectedId = tonumber(H.lorettaSite.carSqlId
            or H.lorettaSite.vehicle.sqlId)
        local expectedSeat = tonumber(H.lorettaSite.seat
            or H.lorettaSite.vehicle.seat)
        if not check("loretta_native_actor_seated",
            vehicle == car and tonumber(seat) == expectedSeat
                and tonumber(call(vehicle, "getSqlId")) == expectedId
                and tonumber(story.carSqlId) == expectedId
                and tonumber(story.seat) == expectedSeat,
            "actor=" .. tostring(call(actor, "getFullName"))
                .. " sqlId=" .. tostring(call(vehicle, "getSqlId"))
                .. " seat=" .. tostring(seat)
                .. " saved=" .. tostring(story.carSqlId)
                    .. "/" .. tostring(story.seat)) then
            setPhase("finish", current) return
        end
        -- Native boarding can finish after onSpawn's first immunity sync.
        -- Exercise the production pulse once while the observer is still
        -- away from the rear door, then inspect the actual native flag.
        local pulsed, pulseReason = SC.Oddballs.pulseGroup(
            H.lorettaGroup, H.player, current)
        if not check("loretta_sealed_sync_pulse", pulsed == true,
            tostring(pulseReason)) then
            setPhase("finish", current) return
        end
        local gateValid, gateDetail = sealedGate(SC, actor, H.lorettaGroup)
        if not check("loretta_sealed_zombie_gate", gateValid, gateDetail) then
            setPhase("finish", current) return
        end
        local darrenValid, darrenDetail = darrenState(SC,
            H.lorettaGroup, car)
        if not check("loretta_darren_tag_and_car_key", darrenValid,
            darrenDetail) then
            setPhase("finish", current) return
        end
        local door = story.site and story.site.vehicle
            and story.site.vehicle.door or H.lorettaSite.spawn
        local moved = door and pcall(function()
            H.player:teleportTo(door.x + 0.5, door.y + 0.5,
                door.z or 0)
        end) or false
        if not check("loretta_observer_at_rear_door", moved,
            "door=" .. tostring(door and door.x)
                .. "," .. tostring(door and door.y)) then
            setPhase("finish", current) return
        end
        H.lorettaSpeech = {}
        H.lorettaOriginalSay = SC.GameplayUtil.say
        SC.GameplayUtil.say = function(speaker, line, ...)
            if speaker == actor then
                H.lorettaSpeech[#H.lorettaSpeech + 1] = tostring(line)
            end
            return H.lorettaOriginalSay(speaker, line, ...)
        end
        setPhase("loretta_first_sight", current)
        return
    end

    if H.phase == "loretta_first_sight" then
        if current - H.phaseStartedAt < 500 then return end
        local group, actor = H.lorettaGroup, H.lorettaActor
        local handled, reason = SC.Oddballs.pulseGroup(group, H.player, current)
        local story = group.oddball
        local lineSeen = false
        for _, line in ipairs(H.lorettaSpeech or {}) do
            if line:find("Don't shout.", 1, true) then lineSeen = true end
        end
        if story.firstSeenHour == nil and current - H.phaseStartedAt < 10000 then
            return
        end
        restoreSpeech(H)
        if not check("loretta_first_sight_warning",
            handled == true and story.firstSeenHour ~= nil
                and group.discovered == true and lineSeen,
            "pulse=" .. tostring(reason)
                .. " firstSeenHour=" .. tostring(story.firstSeenHour)
                .. " lines=" .. table.concat(H.lorettaSpeech or {}, " | ")) then
            setPhase("finish", current) return
        end
        local gateValid, gateDetail = sealedGate(SC, actor, group)
        if not check("loretta_gate_after_warning", gateValid,
            gateDetail .. "; still natively seated behind intact glass") then
            setPhase("finish", current) return
        end
        if H.config.loretta_screenshot ~= "true" then
            setPhase("finish", current) return
        end
        local signaled = H.lorettaSignals.write(READY, {
            "ready=true", "sqlId=" .. tostring(story.carSqlId),
            "seat=" .. tostring(story.seat),
            "firstSeenHour=" .. tostring(story.firstSeenHour),
        })
        if not check("loretta_capture_ready", signaled,
            "native rear-seat scene ready for capture") then
            setPhase("finish", current) return
        end
        setPhase("loretta_capture", current)
        return
    end

    if H.phase == "loretta_capture" then
        if H.lorettaSignals.exists(CAPTURED) then
            result("PASS", "loretta_live_capture",
                "native parked-car encounter captured")
            setPhase("finish", current)
        elseif current - H.phaseStartedAt > 15000 then
            fail(H, result, setPhase, current, "loretta_live_capture",
                "runner did not capture the ready frame")
        end
    end
end

SCRealSandboxHarnessProbes = SCRealSandboxHarnessProbes or {}
SCRealSandboxHarnessProbes.SCLorettaLiveProbe = Probe

return Probe
