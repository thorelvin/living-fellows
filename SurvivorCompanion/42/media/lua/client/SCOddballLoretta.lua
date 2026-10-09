-- SPDX-License-Identifier: MIT
-- Loretta Biddle waits in the rear seat of an existing, saved vehicle.
-- The vehicle SQL id, not a Java vehicle reference, is the durable identity.

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.OddballLoretta = SC.OddballLoretta or {}
local Loretta = SC.OddballLoretta

local ID = "loretta_ten_and_two"
local CLIPBOARD_LINE = "Day four. Out of water. Out of patience. Whoever finds this: signal."
local immunityByActor = setmetatable({}, { __mode = "k" })
local drivingByActor = setmetatable({}, { __mode = "k" })
local houseSearchByGroup = setmetatable({}, { __mode = "k" })
local conditionAtByGroup = setmetatable({}, { __mode = "k" })
local loadedCarBySqlId = setmetatable({}, { __mode = "v" })
local siteScanCursor = {}

local function U() return SC.GameplayUtil end

local function story(group)
    local value = type(group) == "table" and group.oddball or nil
    if type(value) ~= "table" or value.id ~= ID then return nil end
    local siteVehicle = value.site and value.site.vehicle
    if type(siteVehicle) == "table" then
        value.carSqlId = tonumber(value.carSqlId) or tonumber(siteVehicle.sqlId)
        value.seat = tonumber(value.seat) or tonumber(siteVehicle.seat)
    end
    return value
end

local function doorPoint(value)
    local site = value and value.site
    local vehicle = site and site.vehicle
    return vehicle and vehicle.door or site and site.spawn or nil
end

local function actorFor(group)
    local member = group and group.members and group.members[1]
    local actorId = member and member.actorId or group and group.recruitment
        and group.recruitment.joinedActorId
    local record = actorId and SC.Registry and SC.Registry.byId(actorId) or nil
    return record and record.actor and U().isValidActor(record.actor)
        and record.actor or nil
end

local function fellowReaction(group, player, line, flag)
    local value = story(group)
    if not value or value[flag] == true or not player or not SC.Registry
        or type(SC.Registry.living) ~= "function" then return false end
    local loretta = actorFor(group)
    for _, fellow in ipairs(SC.Registry.living()) do
        if fellow ~= loretta and U().distance(fellow, player) <= 8 then
            local id = U().idOf(fellow)
            local record = id and SC.Registry.byId(id) or nil
            if record and record.recruited == true then
                U().say(fellow, line)
                value[flag] = true
                return true
            end
        end
    end
    return false
end

local function worldHour()
    if type(getGameTime) ~= "function" then return nil end
    local okay, clock = pcall(getGameTime)
    if not okay or not clock then return nil end
    local raw, read = U().call(clock, "getWorldAgeHours")
    return read and tonumber(raw) or nil
end

local function configNumber(key, fallback, low, high)
    local number = tonumber(U().config(key)) or fallback
    return math.max(low, math.min(high, number))
end

local function loadedVehicles()
    if type(getCell) ~= "function" or not SC.NativeList then return nil end
    local okay, cell = pcall(getCell)
    if not okay or not cell then return nil end
    local list, called = U().call(cell, "getVehicles")
    if not called then list, called = U().call(cell, "getVehicleList") end
    return called and list or nil
end

local function listItem(list, index)
    local item = SC.NativeList.get(list, index)
    if item ~= nil then return item end
    -- Some Lua array bridges expose only one-based numeric indexing. The
    -- Build 42 vehicle collection is a Set, so it normally uses the iterator
    -- path below and reaches this fallback only on other collection types.
    local okay, indexed = pcall(function() return list[index + 1] end)
    return okay and indexed or nil
end

local function eachLoadedVehicle(visitor)
    local collection = loadedVehicles()
    if not collection then return false end
    local count = math.min(256, SC.NativeList.size(collection))
    local iterator, opened = U().call(collection, "iterator")
    if opened and iterator then
        for _ = 1, count do
            local available, checked = U().call(iterator, "hasNext")
            if not checked then return false end
            if available ~= true then return true end
            local car, read = U().call(iterator, "next")
            if not read then return false end
            if car and visitor(car) == false then return true end
        end
        return true
    end
    -- Older builds expose a List instead of the current Build 42 Set.
    local found = false
    for index = 0, count - 1 do
        local car = listItem(collection, index)
        if car then
            found = true
            if visitor(car) == false then return true end
        end
    end
    return found
end

local function carAtSquare(square)
    return square and select(1, U().call(square, "getVehicleContainer"))
        or nil
end

local function loadedCar(sqlId, point)
    sqlId = tonumber(sqlId)
    if not sqlId or sqlId <= 0 then return nil end
    local cached = loadedCarBySqlId[sqlId]
    if cached then
        local anchor = select(1, U().call(cached, "getSquare"))
        local x, y, z = U().position(anchor)
        local liveSquare = x and U().gridSquare(math.floor(x),
            math.floor(y), math.floor(z or 0)) or nil
        local cachedId = select(1, U().call(cached, "getSqlId"))
        if liveSquare and carAtSquare(liveSquare) == cached
            and tonumber(cachedId) == sqlId then
            return cached
        end
        loadedCarBySqlId[sqlId] = nil
    end
    if type(point) == "table" and tonumber(point.x)
        and tonumber(point.y) then
        local x, y = math.floor(point.x), math.floor(point.y)
        local z = math.floor(tonumber(point.z) or 0)
        for dx = -5, 5 do
            for dy = -5, 5 do
                local car = carAtSquare(U().gridSquare(x + dx, y + dy, z))
                local id = car and select(1, U().call(car, "getSqlId"))
                local square = car and select(1, U().call(car, "getSquare"))
                if tonumber(id) == sqlId and square then
                    loadedCarBySqlId[sqlId] = car
                    return car
                end
            end
        end
    end
    local found
    eachLoadedVehicle(function(car)
        local id = select(1, U().call(car, "getSqlId"))
        local square = select(1, U().call(car, "getSquare"))
        if tonumber(id) == sqlId and square then
            found = car
            return false
        end
        return true
    end)
    if found then loadedCarBySqlId[sqlId] = found end
    return found
end

local function carClaimed(car, sqlId, player)
    if select(1, U().call(player, "getVehicle")) == car then return true end
    local inventory = U().inventory(player)
    local keyId = select(1, U().call(car, "getKeyId"))
    if inventory and tonumber(keyId) and keyId > 0
        and select(1, U().call(inventory, "haveThisKeyId", keyId)) == true then
        return true
    end
    if SC.Factions and type(SC.Factions.list) == "function" then
        for _, group in ipairs(SC.Factions.list(false) or {}) do
            local value = group.oddball
            local siteVehicle = value and value.site and value.site.vehicle
            if group.lifecycle ~= "destroyed" and value
                and (tonumber(value.carSqlId) == sqlId
                    or siteVehicle and tonumber(siteVehicle.sqlId) == sqlId) then
                return true
            end
        end
    end
    return false
end

local function eachPart(car, visitor)
    local count, read = U().call(car, "getPartCount")
    if not read or not tonumber(count) or count < 1 or count > 256 then
        return false
    end
    for index = 0, count - 1 do
        local part = select(1, U().call(car, "getPartByIndex", index))
        if part and visitor(part) == false then return false end
    end
    return true
end

local function rearWindowPart(car, seat)
    local part = select(1, U().call(car, "getPassengerDoor", seat))
    local id = part and select(1, U().call(part, "getId"))
    if type(id) ~= "string" then return nil end
    local suffix = id:match("^Door(RearLeft)$")
        or id:match("^Door(RearRight)$")
    if not suffix then return nil end
    local window = select(1, U().call(car, "getPartById", "Window" .. suffix))
    return window and select(1, U().call(window, "getWindow"))
        and window or nil
end

local function rearDoor(car, seat)
    local part = select(1, U().call(car, "getPassengerDoor", seat))
    local door = part and select(1, U().call(part, "getDoor"))
    return part, door
end

local function carSealed(car)
    if not car then return false end
    local windows, doors = 0, 0
    local intact = eachPart(car, function(part)
        local window = select(1, U().call(part, "getWindow"))
        if window then
            windows = windows + 1
            local broken, brokenRead = U().call(window, "isDestroyed")
            local open, openRead = U().call(window, "isOpen")
            local glass = select(1, U().call(part, "getInventoryItem"))
            if not brokenRead or broken ~= false or not openRead
                or open ~= false or glass == nil then return false end
        end
        local door = select(1, U().call(part, "getDoor"))
        if door then
            doors = doors + 1
            local open, read = U().call(door, "isOpen")
            if not read or open ~= false then return false end
        end
        return true
    end)
    return intact and windows >= 4 and doors >= 4
end

local function nativeSeat(actor, value, car)
    if not actor or not car or not SC.Vehicle
        or type(SC.Vehicle.isNativeSeated) ~= "function" then return false end
    local seated, vehicle, seat = SC.Vehicle.isNativeSeated(actor)
    return seated == true and vehicle == car
        and tonumber(seat) == tonumber(value.seat)
end

local function sealed(group, actor)
    local value = story(group)
    if not value or value.freed == true or value.dead == true
        or value.pendingDead == true then return false end
    local car = loadedCar(value.carSqlId, doorPoint(value))
    return nativeSeat(actor, value, car) and carSealed(car)
end

local function syncImmunity(group, actor)
    if not actor then return false end
    local enabled = sealed(group, actor)
    local nativeFlag, readable = U().call(actor, "isZombiesDontAttack")
    if immunityByActor[actor] == enabled
        and readable and nativeFlag == enabled then return enabled end
    -- Build 42 restricts IsoGameCharacter.setZombiesDontAttack to characters
    -- with a cheat capability. Our non-local companion has no such role, so
    -- the native bridge owns this transient story flag instead.
    local bridge = type(_G) == "table" and rawget(_G, "SCBridge") or nil
    if not bridge or not SC.Call or type(SC.Call.static) ~= "function" then
        return false
    end
    local called, accepted = SC.Call.static(bridge,
        "setStoryZombieIgnored", actor, enabled)
    if not called or accepted ~= true then return false end
    local observed, observedOk = U().call(actor, "isZombiesDontAttack")
    if observedOk and observed ~= enabled then return false end
    local reacquired = enabled and (immunityByActor[actor] ~= true
        or nativeFlag ~= true)
    immunityByActor[actor] = enabled
    if reacquired then
        local snapshot = SC.Senses and SC.Senses.cached
            and SC.Senses.cached(actor) or nil
        if snapshot and SC.ZombieTargeting
            and type(SC.ZombieTargeting.releaseTargets) == "function" then
            SC.ZombieTargeting.releaseTargets(actor, snapshot.threats)
        end
        if SC.ZombieAttack and type(SC.ZombieAttack.reset) == "function" then
            SC.ZombieAttack.reset(actor)
        end
    end
    return enabled
end

local function nearDoor(group, player, radius)
    local value = story(group)
    local point = doorPoint(value)
    if not point or not player then return false end
    local px, py, pz = U().position(player)
    if not px or math.floor(pz or 0) ~= math.floor(point.z or 0) then
        return false
    end
    local dx, dy = px - (point.x + 0.5), py - (point.y + 0.5)
    return dx * dx + dy * dy <= radius * radius
end

local function unseen(square, player, allowSeen)
    if allowSeen then return true end
    if U().canSee(player, square) == true then return false end
    local index = select(1, U().call(player, "getPlayerNum"))
    if tonumber(index) then
        local visible = select(1, U().call(square, "isCanSee",
            math.floor(index)))
        if visible == true then return false end
    end
    return true
end

local function outdoorSquare(square)
    local outside, read = U().call(square, "isOutside")
    return read and outside == true
end

local function doorSquare(car, seat, player, allowSeen)
    local x, y, z = U().position(car)
    if not x then return nil end
    local best, bestDistance
    for dx = -4, 4 do
        for dy = -4, 4 do
            local square = U().gridSquare(math.floor(x) + dx,
                math.floor(y) + dy, math.floor(z or 0))
            if outdoorSquare(square) and U().isSafeSpawnSquare(square)
                and unseen(square, player, allowSeen) then
                local distance, read = U().call(car, "getEnterSeatDistance",
                    seat, math.floor(x) + dx + 0.5,
                    math.floor(y) + dy + 0.5)
                if read and tonumber(distance) and distance >= 0
                    and distance <= 2.56
                    and (not best or distance < bestDistance) then
                    best, bestDistance = square, distance
                end
            end
        end
    end
    return best
end

-- Called once per encounter scan, after the normal range has been selected.
function Loretta.siteFor(player, allowSeen, minimumDistance, maximumDistance)
    if not player then return nil end
    local minimum = math.max(0, tonumber(minimumDistance) or 35)
    local maximum = math.max(minimum, tonumber(maximumDistance) or 90)
    local px, py, pz = U().position(player)
    if not px then return nil end
    local best, bestDistance, seenSqlIds = nil, nil, {}
    local function considerCar(car)
        local x, y, z = U().position(car)
        local square = select(1, U().call(car, "getSquare"))
        local sqlId = select(1, U().call(car, "getSqlId"))
        sqlId = tonumber(sqlId)
        if not sqlId or seenSqlIds[sqlId] then return true end
        seenSqlIds[sqlId] = true
        local seats = select(1, U().call(car, "getMaxPassengers"))
        local distance = x and math.sqrt((x - px) ^ 2 + (y - py) ^ 2)
        if square and outdoorSquare(square) and sqlId > 0
            and tonumber(seats) and seats >= 4 and x
            and math.floor(z or 0) == math.floor(pz or 0)
            and distance >= minimum and distance <= maximum
            and (allowSeen or unseen(square, player, false))
            and SC.Vehicle and SC.Vehicle.isStationary
            and SC.Vehicle.isStationary(car) == true
            and not carClaimed(car, sqlId, player)
            and carSealed(car) then
            local occupied = false
            for seat = 0, math.min(seats - 1, 7) do
                if select(1, U().call(car, "isSeatOccupied", seat)) == true
                    or select(1, U().call(car, "getCharacter", seat))
                    or SC.Vehicle.isSeatReserved
                        and SC.Vehicle.isSeatReserved(car, seat) == true then
                    occupied = true
                    break
                end
            end
            if not occupied then
                local gas = select(1, U().call(car, "getPartById", "GasTank"))
                if gas and select(1, U().call(gas, "getInventoryItem")) then
                    for _, seat in ipairs({ 2, 3 }) do
                        local installed = select(1, U().call(car,
                            "isSeatInstalled", seat))
                        local doorPart, door = rearDoor(car, seat)
                        local windowPart = rearWindowPart(car, seat)
                        if installed == true and doorPart and door and windowPart
                            and select(1, U().call(doorPart,
                                "getInventoryItem")) then
                            local spawnSquare = doorSquare(car, seat, player, allowSeen)
                            if spawnSquare and (not best or distance < bestDistance) then
                                local sx, sy, sz = U().position(spawnSquare)
                                local spawn = { x = math.floor(sx),
                                    y = math.floor(sy), z = math.floor(sz or 0) }
                                best = {
                                    kind = "resident", anchor = spawn, spawn = spawn,
                                    carSqlId = sqlId, seat = seat,
                                    vehicle = { sqlId = sqlId, seat = seat,
                                        door = spawn },
                                    house = {
                                        id = "loretta-car-" .. tostring(sqlId),
                                        anchor = spawn,
                                        bounds = { x1 = spawn.x - 1,
                                            y1 = spawn.y - 1, x2 = spawn.x + 1,
                                            y2 = spawn.y + 1 },
                                        interior = { spawn }, openings = {},
                                    },
                                }
                                bestDistance = distance
                            end
                        end
                    end
                end
            end
        end
        return true
    end
    local centerX, centerY, floorZ = math.floor(px), math.floor(py),
        math.floor(pz or 0)
    -- The debug observer may be standing on the car. This single square is
    -- also a cheap fast path when the Set's iterator is not Lua-exposed.
    considerCar(carAtSquare(U().gridSquare(centerX, centerY, floorZ)))
    if best then return best end
    if eachLoadedVehicle(considerCar) then return best end

    -- Build 42.21 may expose IsoCell.getVehicles() as a Set with size(), but
    -- without a usable Lua iterator. Walk a rotating, bounded tile sample;
    -- getVehicleContainer() is exposed on individual loaded squares. A car
    -- spans several tiles, so successive scans find it without a frame spike.
    local radius = math.ceil(maximum)
    local span = radius * 2 + 1
    local total = span * span
    local key = tostring(math.floor(minimum)) .. ":" .. tostring(radius)
    local cursor = siteScanCursor[key] or 0
    local stride = span * 7 + 1 -- coprime to span squared
    local samples = math.min(512, total)
    for offset = 0, samples - 1 do
        local index = ((cursor + offset) * stride) % total
        local dx = index % span - radius
        local dy = math.floor(index / span) - radius
        local distanceSq = dx * dx + dy * dy
        if distanceSq >= minimum * minimum
            and distanceSq <= maximum * maximum then
            local square = U().gridSquare(centerX + dx, centerY + dy, floorZ)
            considerCar(carAtSquare(square))
        end
    end
    siteScanCursor[key] = (cursor + samples) % total
    return best
end

local function prepareCar(value, car, lockDoors)
    if value.carPrepared == true then return true end
    if not carSealed(car) then return false, "loretta_car_no_longer_sealed" end
    local gas = select(1, U().call(car, "getPartById", "GasTank"))
    if not gas or not select(1, U().call(gas, "getInventoryItem")) then
        return false, "loretta_gas_tank_missing"
    end
    if value.gasDrained ~= true then
        local _, set = U().call(gas, "setContainerContentAmount", 0)
        if not set then return false, "loretta_gas_could_not_drain" end
        value.gasDrained = true
    end
    if value.alarmArmed ~= true then
        local _, set = U().call(car, "setAlarmed", true)
        if not set then return false, "loretta_alarm_could_not_arm" end
        value.alarmArmed = true
    end
    -- Native entry is verified before her door is locked. Locking first can
    -- make a particular vehicle script reject the boarding operation.
    if lockDoors ~= true then return true end
    if value.doorsLocked ~= true then
        local locked = eachPart(car, function(part)
            local door = select(1, U().call(part, "getDoor"))
            if door then
                local _, set = U().call(door, "setLocked", true)
                local result, read = U().call(door, "isLocked")
                if not set or not read or result ~= true then return false end
            end
            return true
        end)
        if not locked then return false, "loretta_doors_could_not_lock" end
        value.doorsLocked = true
    end
    value.carPrepared = true
    return true
end

local function seedNeeds(value, actor)
    if value.needsSeeded == true then return true end
    local stats = select(1, U().call(actor, "getStats"))
    local thirst, hunger
    if CharacterStat ~= nil then
        pcall(function()
            thirst, hunger = CharacterStat.THIRST, CharacterStat.HUNGER
        end)
    end
    if not stats or not thirst or not hunger then
        return false, "loretta_stats_unavailable"
    end
    if value.thirstSeeded ~= true then
        local _, set = U().call(stats, "set", thirst,
            configNumber("oddballLorettaThirst", 0.8, 0, 1))
        if not set then return false, "loretta_thirst_unavailable" end
        value.thirstSeeded = true
    end
    if value.hungerSeeded ~= true then
        local _, set = U().call(stats, "set", hunger,
            configNumber("oddballLorettaHunger", 0.6, 0, 1))
        if not set then return false, "loretta_hunger_unavailable" end
        value.hungerSeeded = true
    end
    value.needsSeeded = true
    return true
end

local function darrenFor(group)
    if not group or type(getCell) ~= "function" or not SC.NativeList then
        return nil
    end
    local okay, cell = pcall(getCell)
    if not okay or not cell then return nil end
    local zombies = select(1, U().call(cell, "getZombieList"))
    if not zombies then return nil end
    for index = 0, math.min(1023, SC.NativeList.size(zombies) - 1) do
        local zombie = listItem(zombies, index)
        local data = zombie and U().modData(zombie)
        if data and data.lfLorettaDarrenGroupId == group.id then return zombie end
    end
    return nil
end

local function giveDarrenKey(group, value, car, zombie)
    if value.darrenKeyPlaced == true then return true end
    if not zombie then return false, "darren_not_loaded" end
    local inventory = U().inventory(zombie)
    if not inventory then return false, "darren_inventory_unavailable" end
    local key, made = U().call(car, "createVehicleKey")
    if not made or not key then return false, "loretta_car_key_unavailable" end
    local added, stored = U().call(inventory, "AddItem", key)
    if not stored or added == false then
        return false, "darren_key_transfer_failed"
    end
    value.darrenKeyPlaced = true
    return true
end

local function spawnDarren(group, value, car, player)
    if value.darrenSpawned == true then
        if value.darrenKeyPlaced ~= true then
            return giveDarrenKey(group, value, car, darrenFor(group))
        end
        return true
    end
    if type(addZombiesInOutfit) ~= "function" or not SC.NativeList
        or not player then return false, "darren_spawn_unavailable" end
    local x, y, z = U().position(car)
    if not x then return false, "loretta_car_unloaded" end
    local radius = math.floor(configNumber("oddballLorettaDarrenRadius",
        20, 6, 30))
    local directions = { { 1, 0 }, { 1, 1 }, { 0, 1 }, { -1, 1 },
        { -1, 0 }, { -1, -1 }, { 0, -1 }, { 1, -1 } }
    for distance = 6, radius, 3 do
        for _, direction in ipairs(directions) do
            local dx, dy = direction[1] * distance,
                direction[2] * distance
            if dx * dx + dy * dy <= radius * radius then
                local sx = math.floor(x + dx)
                local sy = math.floor(y + dy)
                local square = U().gridSquare(sx, sy, math.floor(z or 0))
                if square and U().isSafeSpawnSquare(square)
                    and unseen(square, player, false) then
                    local okay, list = pcall(addZombiesInOutfit, sx, sy,
                        math.floor(z or 0), 1, "Student", 0)
                    local zombie = okay and list and listItem(list, 0)
                        or nil
                    if zombie then
                        value.darrenSpawned = true
                        value.darrenPoint = { x = sx, y = sy,
                            z = math.floor(z or 0) }
                        local data = U().modData(zombie)
                        if data then data.lfLorettaDarrenGroupId = group.id end
                        return giveDarrenKey(group, value, car, zombie)
                    end
                end
            end
        end
    end
    return false, "darren_unseen_square_unavailable"
end

local function boardIfPossible(group, value, actor, car, player)
    if nativeSeat(actor, value, car) then return true end
    if value.freed or value.dead or value.pendingDead then return false end
    local seat = tonumber(value.seat)
    local point = doorPoint(value)
    if not seat or not point or not SC.Vehicle
        or type(SC.Vehicle.board) ~= "function" then
        return false, "loretta_seat_unavailable"
    end
    if select(1, U().call(car, "isSeatOccupied", seat)) == true then
        return false, "loretta_seat_occupied"
    end
    local square = U().gridSquare(point.x, point.y, point.z or 0)
    if not square or not select(1, U().call(square, "getChunk")) then
        return false, "loretta_door_square_unavailable"
    end
    local distance = U().distance(actor, square)
    if distance > 1.5 then
        -- A streamed actor may be recovered on a nearby tile. Only move her
        -- back to the saved door while nobody is watching the correction.
        if player and U().canSee(player, actor) == true then
            return false, "loretta_reboard_visible"
        end
        if not SC.Actor or type(SC.Actor.recover) ~= "function" then
            return false, "loretta_recovery_unavailable"
        end
        if not U().isSafeSpawnSquare(square) then
            return false, "loretta_recovery_square_occupied"
        end
        local recovered, reason = SC.Actor.recover(actor, square)
        if recovered ~= true then return false, reason end
    end
    return SC.Vehicle.board(actor, car, seat, { allowVirtualSeat = false })
end

function Loretta.zombiesIgnore(actor, group)
    return sealed(group, actor), "actor_sealed_in_car"
end

function Loretta.canTalkFromVehicle(group, player)
    local value = story(group)
    if not value or value.freed == true
        or not nearDoor(group, player, 6) then return false end
    local car = loadedCar(value.carSqlId, doorPoint(value))
    if not car then return false end
    local square = select(1, U().call(car, "getSquare"))
    return square and U().canSee(player, square) == true or false
end

function Loretta.onSpawn(group, actor)
    local value = story(group)
    if not value or not actor then return false, "loretta_unavailable" end
    if value.freed == true or value.dead == true or value.pendingDead == true then
        syncImmunity(group, actor)
        return true, "loretta_resolved"
    end
    local car = loadedCar(value.carSqlId, doorPoint(value))
    if not car then return false, "loretta_car_unloaded" end
    local prepared, reason = prepareCar(value, car, false)
    if not prepared then return false, reason end
    local boarded, boardReason = boardIfPossible(group, value, actor, car)
    if boarded ~= true then return false, boardReason end
    prepared, reason = prepareCar(value, car, true)
    if not prepared then return false, reason end
    seedNeeds(value, actor)
    local player
    if type(getPlayer) == "function" then
        local okay, found = pcall(getPlayer)
        if okay then player = found end
    end
    spawnDarren(group, value, car, player)
    syncImmunity(group, actor)
    return true, "loretta_seated"
end

local function writeClipboard(value, actor)
    if value.clipboardWritten == true then return true end
    local inventory = actor and U().inventory(actor)
    if not inventory then return false end
    for _, item in ipairs(U().inventoryItemsDeep(inventory, 120, 4)) do
        if U().itemType(item) == "Base.Clipboard" then
            local _, set = U().call(item, "setName",
                "Loretta's clipboard: " .. CLIPBOARD_LINE)
            if set then value.clipboardWritten = true end
            return set
        end
    end
    return false
end

local function dieIfDue(group, value, actor, hour)
    if value.freed == true or value.dead == true
        or not tonumber(value.firstSeenHour) or not hour then return false end
    local limit = configNumber("oddballLorettaRescueHours", 72, 1, 720)
    if hour - value.firstSeenHour < limit and value.pendingDead ~= true then
        return false
    end
    value.pendingDead = true
    syncImmunity(group, actor)
    if not actor or not SC.Actor or type(SC.Actor.endLife) ~= "function" then
        return false
    end
    writeClipboard(value, actor)
    local ended, reason = SC.Actor.endLife(actor)
    if ended ~= true then return false, reason end
    value.dead = true
    value.pendingDead = nil
    value.stage = "dying"
    return true, "loretta_died_waiting"
end

local function showClipboard(group, value, player, car)
    if value.clipboardShown == true or value.dead ~= true or not player
        or not car or not nearDoor(group, player, 4) then return false end
    local _, door = rearDoor(car, value.seat)
    if not door or select(1, U().call(door, "isOpen")) ~= true then
        return false
    end
    local _, shown = U().call(player, "setHaloNote", CLIPBOARD_LINE)
    if shown then
        value.clipboardShown = true
        if SC.Oddballs and type(SC.Oddballs.retire) == "function" then
            SC.Oddballs.retire(group, "dead_of_thirst")
        end
        group.lifecycle = "destroyed"
    end
    return shown
end

local function freeFromCar(group, value, actor, car, method)
    if not nativeSeat(actor, value, car) then return false,
        "loretta_not_natively_seated" end
    local _, door = rearDoor(car, value.seat)
    if not door then return false, "loretta_door_unavailable" end
    if method == "window" then
        local _, unlocked = U().call(door, "setLocked", false)
        if not unlocked then return false, "loretta_door_could_not_unlock" end
    end
    syncImmunity(group, actor)
    local exited, reason = SC.Vehicle.exit(actor, car, value.seat)
    if exited ~= true then return false, reason end
    value.freed = true
    value.freedBy = method
    value.stage = "freed"
    syncImmunity(group, actor)
    if SC.Factions and type(SC.Factions.forceStanding) == "function" then
        SC.Factions.forceStanding(group.id,
            (tonumber(value.hurtCount) or 0) > 0 and "Tolerated"
                or "Trusted")
    end
    value.freedomLine = method == "window" and "alarm" or "freed"
    value.freedomLineHour = worldHour()
    if method == "key" then
        fellowReaction(group, actor,
            "The quiet way, please. I'm begging you, the quiet way.",
            "quietFellowSpoken")
    end
    return true, "loretta_freed_by_" .. method
end

local function advanceFreedomLines(value, actor, hour)
    if not actor or not hour or not value.freedomLine
        or hour < (tonumber(value.freedomLineHour) or hour) then return end
    if value.freedomLine == "alarm" then
        U().say(actor, U().config("profanityEnabled") == false
            and "Well, shoot. Now every one of them heard that."
            or "Well, shit. Now every one of them heard that.")
        value.freedomLine = "freed"
    elseif value.freedomLine == "freed" then
        U().say(actor, "I am never sitting in the back of anything again.")
        value.freedomLine = "water"
    elseif value.freedomLine == "water" then
        U().say(actor, "Water first, sweetheart. Then we can talk.")
        value.freedomLine = nil
    end
    value.freedomLineHour = hour + 0.003
end

local function carCondition(car)
    local total, count = 0, 0
    local read = eachPart(car, function(part)
        local condition, okay = U().call(part, "getCondition")
        if okay and tonumber(condition) then
            total = total + condition
            count = count + 1
        end
        return true
    end)
    return read and count > 0 and total or nil
end

local function hurtLine(value, actor)
    value.hurtCount = math.min(2, (tonumber(value.hurtCount) or 0) + 1)
    local angry = U().config("profanityEnabled") == false
        and "You ought to be ashamed. Get away from my car."
        or "Damn you. Get away from my car."
    U().say(actor, value.hurtCount == 1
        and "Please stop. I can't get away from you."
        or angry)
end

local function noteCarDamage(group, value, actor, car, player, current)
    if not actor or not car or value.firstSeenHour == nil then return end
    current = tonumber(current) or U().nowMs()
    if current < (conditionAtByGroup[group] or 0) then return end
    conditionAtByGroup[group] = current + 5000
    local condition = carCondition(car)
    if not condition then return end
    local previous = tonumber(value.carCondition)
    value.carCondition = condition
    if previous and previous - condition >= 2
        and nearDoor(group, player, 8)
        and value.pendingDead ~= true then
        local windowPart = rearWindowPart(car, value.seat)
        local window = windowPart and select(1, U().call(windowPart,
            "getWindow"))
        if window and select(1, U().call(window, "isDestroyed")) == true then
            return
        end
        hurtLine(value, actor)
    end
end

local function noteActorDamage(value, actor)
    if not actor or value.firstSeenHour == nil
        or value.pendingDead == true then return end
    local body = select(1, U().call(actor, "getBodyDamage"))
    local health = body and select(1, U().call(body,
        "getOverallBodyHealth"))
    if not tonumber(health) then return end
    local previous = tonumber(value.actorHealth)
    value.actorHealth = health
    -- Small starvation/illness ticks are not treated as an assault.
    if previous and previous - health >= 5 then hurtLine(value, actor) end
end

function Loretta.pulse(group, player, current)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    local actor = actorFor(group)
    local car = loadedCar(value.carSqlId, doorPoint(value))
    local hour = worldHour()
    if value.storyFollowup == "student" and actor and hour
        and hour >= (tonumber(value.storyFollowupHour) or hour)
        and value.dead ~= true and value.pendingDead ~= true then
        U().say(actor, "My student ran out of gas, then ran off. With my keys.")
        value.storyFollowup = nil
        value.storyFollowupHour = nil
    end
    if value.dead == true then
        syncImmunity(group, actor)
        showClipboard(group, value, player, car)
        return true, "loretta_dead"
    end
    if value.freed == true then
        syncImmunity(group, actor)
        advanceFreedomLines(value, actor, hour)
        if value.escortRequested == true and value.escort == nil
            and type(Loretta.advanceEscortSearch) == "function" then
            Loretta.advanceEscortSearch(group, player)
        end
        local escort = value.escort
        if type(escort) == "table" and escort.arrived ~= true
            and player and actor and escort.home then
            local target = U().gridSquare(escort.home.x,
                escort.home.y, escort.home.z or 0)
            if target and U().distance(player, target) <= 8
                and U().distance(actor, target) <= 8 then
                escort.arrived = true
                U().say(actor, "Home. I owe you the rest of this conversation.")
            end
        end
        return true, "loretta_freed"
    end
    if actor and car and value.pendingDead ~= true then
        local prepared = prepareCar(value, car, false)
        if prepared == true then
            local boarded = boardIfPossible(group, value, actor, car, player)
            if boarded == true then prepareCar(value, car, true) end
        end
        if value.carPrepared == true then
            seedNeeds(value, actor)
            if value.darrenSpawned ~= true or value.darrenKeyPlaced ~= true then
                spawnDarren(group, value, car, player)
            end
        end
    end
    syncImmunity(group, actor)
    if actor and player and value.firstSeenHour == nil and hour
        and nearDoor(group, player, 4)
        and (Loretta.canTalkFromVehicle(group, player)
            or U().canSee(player, actor) == true) then
        value.firstSeenHour = hour
        group.discovered = true
        U().say(actor,
            "Don't shout. They can't see me if I don't move.")
        fellowReaction(group, player,
            "She's been sitting there for days? I can't sit still for five minutes.",
            "sightFellowSpoken")
    end
    noteCarDamage(group, value, actor, car, player, current)
    noteActorDamage(value, actor)
    if dieIfDue(group, value, actor, hour) then return true,
        "loretta_died_waiting" end
    if value.pendingDead == true or not actor or not car then
        return true, "loretta_waiting_for_car"
    end
    local windowPart = rearWindowPart(car, value.seat)
    local window = windowPart and select(1, U().call(windowPart,
        "getWindow"))
    local broken = window and select(1, U().call(window,
        "isDestroyed")) == true
    local _, door = rearDoor(car, value.seat)
    local open = door and select(1, U().call(door, "isOpen")) == true
    if broken or open then
        local method = broken and "window" or "key"
        local freed, reason = freeFromCar(group, value, actor, car, method)
        return freed == true, reason
    end
    return true, "loretta_sealed"
end

function Loretta.intentFor(actor, player, snapshot, group)
    local value = story(group)
    if not value then return nil end
    if value.freed ~= true and value.dead ~= true then
        return { mode = "loretta_wait", priority = 90 }
    end
    local threats = type(snapshot) == "table"
        and (tonumber(snapshot.threatCount) or #(snapshot.threats or {})) or 0
    if threats > 0 then return { mode = "zombie_defense", priority = 18 } end
    return { mode = "oddball_idle", priority = 28 }
end

function Loretta.update(actor, player, runtime, intent)
    if intent and intent.mode == "loretta_wait" then
        return true, "waiting_in_car"
    end
    return false, "loretta_no_special_move"
end

function Loretta.avoidsZombieCombat(actor, group)
    local value = story(group)
    return value and value.freed ~= true and value.dead ~= true or false
end

function Loretta.canRecruit(group)
    local value = story(group)
    return value and value.freed == true and value.waterReceived == true
        and value.dead ~= true and value.pendingDead ~= true
        and group.standing ~= "Hostile" or false,
        "free_loretta_and_give_water_first"
end

local function waterItem(player)
    local inventory = player and U().inventory(player)
    if not inventory then return nil end
    for _, item in ipairs(U().inventoryItemsDeep(inventory, 200, 8)) do
        local source = select(1, U().call(item, "getContainer"))
        local water = select(1, U().call(item, "isWaterSource"))
        if source and water == true then
            local fluid = select(1, U().call(item, "getFluidContainer"))
            if fluid then
                local empty = select(1, U().call(fluid, "isEmpty"))
                local amount = select(1, U().call(fluid, "getAmount"))
                local primary = select(1, U().call(fluid, "getPrimaryFluid"))
                local kind = primary and select(1, U().call(primary,
                    "getFluidTypeString"))
                local tainted = false
                if Fluid ~= nil then
                    local okay, taintedType = pcall(function()
                        return Fluid.TaintedWater
                    end)
                    if okay and taintedType then
                        local contains, read = U().call(fluid, "contains",
                            taintedType)
                        tainted = not read or contains == true
                    end
                end
                if empty == false and tonumber(amount) and amount >= 0.12
                    and not tainted
                    and (kind == "Water" or kind == "CarbonatedWater") then
                    return item
                end
            end
        end
    end
    return nil
end

local function recruitNow(group, player)
    local service = SC.FactionRecruitment
    if not service or type(service.initialize) ~= "function"
        or type(service.ask) ~= "function"
        or type(service.startTrial) ~= "function"
        or type(service.decide) ~= "function" then
        return false, "recruitment_unavailable"
    end
    local state = service.initialize(group)
    if state.status == "joined" then return true, "already_recruited" end
    if state.status == "available" then
        local asked, reason = service.ask(group, player)
        if asked ~= true then return false, reason end
    end
    state = service.initialize(group)
    if state.status == "candidate" then
        local started, reason = service.startTrial(group, player)
        if started ~= true then return false, reason end
    end
    state = service.initialize(group)
    if state.status ~= "trial" then return false, "loretta_trial_unavailable" end
    return service.decide(group, player, "join", true)
end

local function escortHome(group, player, house)
    local value = story(group)
    if not house or not house.anchor or not house.bounds then
        return false, "home_unavailable"
    end
    local service = SC.FactionRecruitment
    if not service or type(service.initialize) ~= "function" then
        return false, "recruitment_unavailable"
    end
    local state = service.initialize(group)
    if state.status == "available" then
        local asked, askReason = service.ask(group, player)
        if asked ~= true then return false, askReason end
    end
    state = service.initialize(group)
    if state.status == "candidate" then
        local started, startReason = service.startTrial(group, player)
        if started ~= true then return false, startReason end
    end
    if service.initialize(group).status ~= "trial" then
        return false, "escort_trial_unavailable"
    end
    local anchor = house.anchor
    local bounds = house.bounds
    local location = type(SC.Factions.describeLocation) == "function"
        and SC.Factions.describeLocation(anchor) or nil
    value.escort = {
        home = { x = math.floor(anchor.x), y = math.floor(anchor.y),
            z = math.floor(anchor.z or 0) },
        bounds = { x1 = bounds.x1, y1 = bounds.y1,
            x2 = bounds.x2, y2 = bounds.y2 },
        houseId = house.id,
        address = location and location.address or "the house",
        arrived = false,
    }
    U().say(actorFor(group), "Take me to " .. value.escort.address .. ".")
    return true, "loretta_escort_started"
end

function Loretta.advanceEscortSearch(group, player)
    local value = story(group)
    if not value or value.escortRequested ~= true or not player then
        return false, "escort_search_not_requested"
    end
    if not SC.Factions or type(SC.Factions.pollHouseSearch) ~= "function" then
        value.escortRequested = nil
        return false, "home_search_unavailable"
    end
    local status, house, reason, job = SC.Factions.pollHouseSearch(
        player, {
            purpose = "oddball", sourceFactionId = group.id,
            minimumDistance = 50, maximumDistance = 300,
            sampleBudget = 32,
        }, houseSearchByGroup[group])
    if status == "pending" then
        houseSearchByGroup[group] = job
        return true, "loretta_home_searching"
    end
    houseSearchByGroup[group] = nil
    value.escortRequested = nil
    if status ~= "complete" then
        value.escortProblem = reason or "home_unavailable"
        return false, value.escortProblem
    end
    local started, startReason = escortHome(group, player, house)
    if not started then value.escortProblem = startReason end
    return started, startReason
end

local function stayHome(group, player)
    local value = story(group)
    local escort = value and value.escort
    if not escort or escort.arrived ~= true then
        return false, "loretta_not_home_yet"
    end
    local service = SC.FactionRecruitment
    if not service or type(service.returnNow) ~= "function" then
        return false, "recruitment_unavailable"
    end
    local returned, reason = service.returnNow(group, player, true)
    if returned ~= true then return false, reason end
    local home = escort.home
    group.house = {
        id = escort.houseId or ("loretta-home-" .. tostring(group.id)),
        anchor = home, bounds = escort.bounds,
        interior = { home }, openings = {},
    }
    value.site.spawn = home
    value.site.anchor = home
    value.site.house = { id = group.house.id,
        anchor = home, bounds = escort.bounds,
        interior = { home }, openings = {} }
    value.escort = nil
    value.escortRequested = nil
    value.escortProblem = nil
    value.stage = "home_trader"
    group.barterUnlocked = true
    U().say(actorFor(group), "Thank you, sweetheart. Come by if you need to trade.")
    return true, "loretta_stayed_home"
end

function Loretta.menuOptions(group, player)
    local value = story(group)
    if value and value.stage == "home_trader" then return {} end
    if not value or not player or not nearDoor(group, player, 6)
        and not (actorFor(group) and U().distance(actorFor(group), player) <= 6)
        then return {} end
    local actor = actorFor(group)
    if value.dead == true then
        return { { id = "read_clipboard", label = "Read Loretta's clipboard",
            enabled = value.clipboardShown ~= true } }
    end
    if value.freed ~= true then
        local car = loadedCar(value.carSqlId, doorPoint(value))
        local part = car and rearWindowPart(car, value.seat)
        local window = part and select(1, U().call(part, "getWindow"))
        local hittable = window and select(1, U().call(window,
            "isHittable")) == true
        return {
            { id = "break_window", label = "Break the window",
                enabled = nearDoor(group, player, 2) and hittable == true },
            { id = "ask_story", label = "Ask why she is trapped",
                enabled = actor ~= nil },
            { id = "ask_darren", label = "Ask about Darren",
                enabled = actor ~= nil },
        }
    end
    local options = {}
    if value.waterReceived ~= true then
        options[#options + 1] = { id = "give_water",
            label = "Give Loretta water", enabled = waterItem(player) ~= nil }
    else
        local recruitment = SC.FactionRecruitment
            and SC.FactionRecruitment.initialize
            and SC.FactionRecruitment.initialize(group) or nil
        if not recruitment or recruitment.status ~= "joined" then
            if value.escort and value.escort.arrived then
                options[#options + 1] = { id = "join_at_home",
                    label = "Invite Loretta to join", enabled = true }
                options[#options + 1] = { id = "stay_home",
                    label = "Let Loretta stay and trade", enabled = true }
            elseif not value.escort then
                options[#options + 1] = { id = "recruit_now",
                    label = "Recruit Loretta now", enabled = true }
                options[#options + 1] = { id = "drive_home",
                    label = "Offer to drive Loretta home", enabled = true }
            end
        end
    end
    return options
end

function Loretta.action(group, action, player)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    local actor = actorFor(group)
    if action == "hurt" then
        hurtLine(value, actor)
        return true, "loretta_hurt"
    end
    if value.stage == "home_trader" then
        return false, "loretta_stays_home"
    end
    if not player or not nearDoor(group, player, 6)
        and not (actor and U().distance(actor, player) <= 6) then
        return false, "loretta_too_far"
    end
    if action == "read_clipboard" and value.dead == true then
        local car = loadedCar(value.carSqlId, doorPoint(value))
        local _, door = car and rearDoor(car, value.seat)
        if not door or select(1, U().call(door, "isOpen")) ~= true then
            return false, "open_loretta_door_first"
        end
        local _, shown = U().call(player, "setHaloNote", CLIPBOARD_LINE)
        if shown then
            value.clipboardShown = true
            if SC.Oddballs and type(SC.Oddballs.retire) == "function" then
                SC.Oddballs.retire(group, "dead_of_thirst")
            end
            group.lifecycle = "destroyed"
        end
        return shown, shown and "loretta_clipboard_read"
            or "loretta_clipboard_unavailable"
    end
    if value.dead == true or value.pendingDead == true then
        return false, "loretta_dead"
    end
    if action == "break_window" then
        if value.freed == true or not nearDoor(group, player, 2) then
            return false, "loretta_window_out_of_reach" end
        local car = loadedCar(value.carSqlId, doorPoint(value))
        local part = car and rearWindowPart(car, value.seat)
        local window = part and select(1, U().call(part, "getWindow"))
        if not window or select(1, U().call(window, "isHittable")) ~= true then
            return false, "loretta_window_unavailable" end
        if not ISSmashVehicleWindow and type(require) == "function" then
            pcall(require, "Vehicles/TimedActions/ISSmashVehicleWindow")
        end
        if not ISSmashVehicleWindow or not ISSmashVehicleWindow.new
            or not ISTimedActionQueue or not ISTimedActionQueue.add then
            return false, "vehicle_window_action_unavailable"
        end
        local okay, timed = pcall(ISSmashVehicleWindow.new,
            ISSmashVehicleWindow, player, part)
        if not okay or not timed then return false,
            "vehicle_window_action_unavailable" end
        U().say(actor, "If you break that window, the alarm goes. Be ready.")
        local queued, result = pcall(ISTimedActionQueue.add, timed)
        return queued and result ~= false,
            queued and "loretta_window_smash_queued"
                or "vehicle_window_queue_failed"
    end
    if action == "ask_story" and value.freed ~= true then
        if value.storyFollowup == "student" then
            return true, "loretta_story_ongoing"
        end
        U().say(actor,
            "Child locks. Thirty-one years in the front seat, and I die in the back.")
        value.storyFollowup = "student"
        value.storyFollowupHour = (worldHour() or 0) + 0.003
        return true, "loretta_story_told"
    end
    if action == "ask_darren" and value.freed ~= true then
        U().say(actor, "That's Darren. My two o'clock. He has my keys.")
        return true, "darren_identified"
    end
    if value.freed ~= true then return false, "loretta_still_trapped" end
    if action == "give_water" then
        if value.waterReceived == true then return true, "water_already_given" end
        local item = waterItem(player)
        local source = item and select(1, U().call(item, "getContainer"))
        local destination = actor and U().inventory(actor)
        if not source or not destination then return false,
            "water_unavailable" end
        if U().transferItemVerified(source, destination, item) ~= true then
            return false, "water_transfer_failed" end
        local fluid = select(1, U().call(item, "getFluidContainer"))
        local amount = fluid and select(1, U().call(fluid, "getAmount"))
        local stats = actor and select(1, U().call(actor, "getStats"))
        local thirst
        if CharacterStat ~= nil then
            pcall(function() thirst = CharacterStat.THIRST end)
        end
        if not fluid or not tonumber(amount) or amount < 0.12
            or not stats or not thirst then
            U().transferItemVerified(destination, source, item)
            return false, "water_could_not_be_drunk"
        end
        -- Match vanilla ISDrinkFromBottle's one-use consumption. The item
        -- stays in her inventory for later native needs actions.
        local _, consumed = U().call(fluid, "adjustAmount",
            math.max(0, amount - 0.12))
        if not consumed then
            U().transferItemVerified(destination, source, item)
            return false, "water_could_not_be_drunk"
        end
        local _, relieved = U().call(stats, "remove", thirst, 0.1)
        if not relieved then
            U().call(fluid, "adjustAmount", amount)
            U().transferItemVerified(destination, source, item)
            return false, "thirst_could_not_decrease"
        end
        value.waterReceived = true
        U().say(actor, "That's better. Now, what were you saying?")
        return true, "water_given"
    end
    if value.waterReceived ~= true then return false, "water_first" end
    if action == "recruit_now" or action == "join_at_home" then
        return recruitNow(group, player)
    elseif action == "drive_home" and not value.escort then
        value.escortRequested = true
        return Loretta.advanceEscortSearch(group, player)
    elseif action == "stay_home" then
        return stayHome(group, player)
    end
    return false, "unknown_loretta_action"
end

local function drivingTogether(actor, player)
    if not actor or not player or not SC.Vehicle
        or type(SC.Vehicle.isNativeSeated) ~= "function" then return nil end
    local seated, car, seat = SC.Vehicle.isNativeSeated(actor)
    if seated ~= true or not car or seat ~= 1 then return nil end
    if select(1, U().call(player, "getVehicle")) ~= car
        or select(1, U().call(car, "getSeat", player)) ~= 0 then
        return nil
    end
    return car
end

local function remark(group, actor, line, now)
    local value = story(group)
    local cooldown = configNumber("oddballBackseatRemarkMs",
        90000, 1000, 600000)
    local last = tonumber(value.lastRemarkAt)
    if last and now >= last and now - last < cooldown then return false end
    value.lastRemarkAt = now
    U().say(actor, line)
    return true
end

function Loretta.pulseRecruited(group, actor, player, current)
    local value = story(group)
    if not value or not actor then return false end
    current = tonumber(current) or U().nowMs()
    local car = drivingTogether(actor, player)
    if not car then drivingByActor[actor] = nil return true,
        "loretta_not_riding" end
    fellowReaction(group, player,
        "She graded my parking. I wasn't even driving.",
        "rideFellowSpoken")
    local sample = drivingByActor[actor]
    if sample and current - sample.at < 1000 then return true,
        "loretta_drive_sample_throttled" end
    local rawSpeed = select(1, U().call(car, "getCurrentSpeedKmHour"))
    local speed = math.abs(tonumber(rawSpeed) or 0)
    drivingByActor[actor] = { at = current, speed = speed }
    if sample and current - sample.at <= 1600
        and sample.speed - speed > configNumber(
            "oddballBackseatBrakeKmh", 30, 5, 100) then
        remark(group, actor,
            U().config("profanityEnabled") == false
                and "Good Lord on a bicycle. Gently."
                or "Jesus H. Christ on a bicycle. Gently.", current)
    elseif speed > configNumber("oddballBackseatSpeedKmh", 80, 20, 200) then
        remark(group, actor,
            "This is not the Derby, and you are not a horse.", current)
    end
    local original = doorPoint(value)
    local x, y, z = U().position(car)
    if original and x and value.oldLotSpoken ~= true
        and math.floor(z or 0) == math.floor(original.z or 0)
        and (x - original.x) ^ 2 + (y - original.y) ^ 2 <= 225
        and remark(group, actor,
            "Ten and two, sweetheart. Always ten and two.", current) then
        value.oldLotSpoken = true
    end
    return true, "loretta_riding"
end

function Loretta.onZombieDead(group, zombie, attacker, player)
    local value = story(group)
    if not value or value.freed ~= true or value.dead == true then return false end
    local actor = actorFor(group)
    local car = drivingTogether(actor, player)
    if not car or (attacker ~= player and attacker ~= car)
        or not zombie or U().distance(car, zombie) > 3 then return false end
    local rawSpeed = select(1, U().call(car, "getCurrentSpeedKmHour"))
    local speed = math.abs(tonumber(rawSpeed) or 0)
    if speed < 5 then return false end
    return remark(group, actor, "Pedestrian. That's ten points.", U().nowMs())
end

return Loretta
