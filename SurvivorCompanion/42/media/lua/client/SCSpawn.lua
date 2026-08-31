-- SPDX-License-Identifier: MIT

require "SCNamespace"
require "SCConfig"
require "SCRegistry"
require "SCDiagnostics"

local SC = SurvivorCompanion
SC.Spawn = SC.Spawn or {}

local spawn = SC.Spawn
local lastDebugAttempt = -math.huge
local productionStartedAt = nil
local lastProductionAttempt = -math.huge
local sequence = 0
local lastGeneratedIdentityKey = nil
local pendingSpawn = nil

-- Genre-inspired given names are mixed independently from an original/common
-- surname pool and vanilla appearances. The generator does not recreate a
-- character's full name, dialogue, costume, or likeness.
local firstNames = {
    { name = "Abby", gender = "female" },
    { name = "Ada", gender = "female" },
    { name = "Addy", gender = "female" },
    { name = "Alice", gender = "female" },
    { name = "Amy", gender = "female" },
    { name = "Ana", gender = "female" },
    { name = "Andrea", gender = "female" },
    { name = "Anna", gender = "female" },
    { name = "Barbara", gender = "female" },
    { name = "Beth", gender = "female" },
    { name = "Carol", gender = "female" },
    { name = "Christa", gender = "female" },
    { name = "Claire", gender = "female" },
    { name = "Connie", gender = "female" },
    { name = "Dianne", gender = "female" },
    { name = "Dina", gender = "female" },
    { name = "Ellie", gender = "female" },
    { name = "Enid", gender = "female" },
    { name = "Hannah", gender = "female" },
    { name = "Jess", gender = "female" },
    { name = "Jill", gender = "female" },
    { name = "Judith", gender = "female" },
    { name = "Kate", gender = "female" },
    { name = "Kelly", gender = "female" },
    { name = "Liz", gender = "female" },
    { name = "Lori", gender = "female" },
    { name = "Lydia", gender = "female" },
    { name = "Maggie", gender = "female" },
    { name = "Maria", gender = "female" },
    { name = "Marlene", gender = "female" },
    { name = "Mel", gender = "female" },
    { name = "Michonne", gender = "female" },
    { name = "Monica", gender = "female" },
    { name = "Naomi", gender = "female" },
    { name = "Nicole", gender = "female" },
    { name = "Nora", gender = "female" },
    { name = "Rebecca", gender = "female" },
    { name = "Rikki", gender = "female" },
    { name = "Riley", gender = "female" },
    { name = "Rochelle", gender = "female" },
    { name = "Rosita", gender = "female" },
    { name = "Sarah", gender = "female" },
    { name = "Sasha", gender = "female" },
    { name = "Scarlet", gender = "female" },
    { name = "Selena", gender = "female" },
    { name = "Tammy", gender = "female" },
    { name = "Tara", gender = "female" },
    { name = "Tess", gender = "female" },
    { name = "Yara", gender = "female" },
    { name = "Yvonne", gender = "female" },
    { name = "Zoey", gender = "female" },
    { name = "Aaron", gender = "male" },
    { name = "Abraham", gender = "male" },
    { name = "Andre", gender = "male" },
    { name = "Andy", gender = "male" },
    { name = "Ben", gender = "male" },
    { name = "Bill", gender = "male" },
    { name = "Carl", gender = "male" },
    { name = "Carlos", gender = "male" },
    { name = "Chris", gender = "male" },
    { name = "Dale", gender = "male" },
    { name = "Daryl", gender = "male" },
    { name = "David", gender = "male" },
    { name = "Deacon", gender = "male" },
    { name = "Don", gender = "male" },
    { name = "Doyle", gender = "male" },
    { name = "Duane", gender = "male" },
    { name = "Dwight", gender = "male" },
    { name = "Ed", gender = "male" },
    { name = "Ellis", gender = "male" },
    { name = "Eugene", gender = "male" },
    { name = "Ezekiel", gender = "male" },
    { name = "Francis", gender = "male" },
    { name = "Frank", gender = "male" },
    { name = "Gabriel", gender = "male" },
    { name = "Gerry", gender = "male" },
    { name = "Glenn", gender = "male" },
    { name = "Henry", gender = "male" },
    { name = "Hershel", gender = "male" },
    { name = "Isaac", gender = "male" },
    { name = "Jesse", gender = "male" },
    { name = "Jim", gender = "male" },
    { name = "Joel", gender = "male" },
    { name = "Kenneth", gender = "male" },
    { name = "Leon", gender = "male" },
    { name = "Lev", gender = "male" },
    { name = "Lionel", gender = "male" },
    { name = "Louis", gender = "male" },
    { name = "Manny", gender = "male" },
    { name = "Merle", gender = "male" },
    { name = "Michael", gender = "male" },
    { name = "Morgan", gender = "male" },
    { name = "Negan", gender = "male" },
    { name = "Nick", gender = "male" },
    { name = "Owen", gender = "male" },
    { name = "Paul", gender = "male" },
    { name = "Pete", gender = "male" },
    { name = "Philip", gender = "male" },
    { name = "Rick", gender = "male" },
    { name = "Roger", gender = "male" },
    { name = "Sam", gender = "male" },
    { name = "Sanghwa", gender = "male" },
    { name = "Seokwoo", gender = "male" },
    { name = "Shane", gender = "male" },
    { name = "Shaun", gender = "male" },
    { name = "Stephen", gender = "male" },
    { name = "Steve", gender = "male" },
    { name = "Tommy", gender = "male" },
    { name = "Tucker", gender = "male" },
    { name = "Tyreese", gender = "male" },
    { name = "Yongguk", gender = "male" },
}

local surnames = {
    "Baker", "Bennett", "Carter", "Cole", "Ellis", "Foster", "Grant", "Hayes",
    "Holland", "Lane", "Mercer", "Nolan", "Parker", "Reed", "Rowan", "Shaw",
    "Sutton", "Turner", "Walker", "Ward",
}

-- Stock 42.20.4 outfits present in both male and female OutfitManager catalogs.
-- The mundane pool keeps encounters grounded and prevents unclothed descriptors.
local survivorOutfits = {
    "Generic01", "Generic02", "Generic03", "Generic04", "Generic05",
    "Grunge", "Hobbyist", "Backpacker", "Camper", "Evacuee",
}

local function method(object, name)
    if object == nil then return nil end
    local ok, value = pcall(function() return object[name] end)
    return ok and type(value) == "function" and value or nil
end

local function invoke(object, name, ...)
    local callback = method(object, name)
    if callback == nil then return false, nil end
    local values = { pcall(callback, object, ...) }
    if not values[1] then return false, values[2] end
    local unpackFn = table.unpack or unpack
    return true, unpackFn(values, 2)
end

local function nowMs()
    if type(getTimestampMs) == "function" then
        local ok, value = pcall(getTimestampMs)
        local numeric = ok and tonumber(value) or nil
        if numeric ~= nil then return numeric end
    end
    return math.floor(os.clock() * 1000)
end

local function randomBetween(minimum, maximum)
    if type(ZombRand) == "function" then
        local ok, value = pcall(ZombRand, math.floor(minimum), math.floor(maximum) + 1)
        if ok and type(value) == "number" then return value end
    end
    sequence = sequence + 1
    return minimum + (sequence * 1103515245 % math.max(1, maximum - minimum + 1))
end

function spawn.generateIdentity()
    local chosen, surname, key
    for _ = 1, 8 do
        chosen = firstNames[randomBetween(1, #firstNames)]
        surname = surnames[randomBetween(1, #surnames)]
        key = chosen.name .. ":" .. surname
        if key ~= lastGeneratedIdentityKey then break end
        chosen = nil
    end
    if chosen == nil then
        local fallbackIndex = (sequence % #firstNames) + 1
        chosen = firstNames[fallbackIndex]
        local surnameIndex = ((sequence + 1) % #surnames) + 1
        surname = surnames[surnameIndex]
        key = chosen.name .. ":" .. surname
        if key == lastGeneratedIdentityKey then
            surname = surnames[(surnameIndex % #surnames) + 1]
            key = chosen.name .. ":" .. surname
        end
    end
    lastGeneratedIdentityKey = key
    return {
        forename = chosen.name,
        surname = surname,
        gender = chosen.gender,
        outfit = survivorOutfits[randomBetween(1, #survivorOutfits)],
        visualSeed = randomBetween(1, 999999999),
    }
end

local function safeSquare(square, player, requireUnseen)
    if square == nil then return false end
    local chunkOk, chunk = invoke(square, "getChunk")
    local solidOk, solid = invoke(square, "isSolid")
    local transOk, trans = invoke(square, "isSolidTrans")
    local floorOk, floor = invoke(square, "TreatAsSolidFloor")
    local freeOk, free = invoke(square, "isFree", true)
    local safeOk, safe = invoke(square, "isSafeToSpawn")
    if not chunkOk or chunk == nil or not solidOk or solid == true or not transOk or trans == true
        or not floorOk or floor ~= true or not freeOk or free ~= true or not safeOk or safe ~= true then
        return false
    end
    if requireUnseen ~= false then
        local indexOk, playerIndex = invoke(player, "getPlayerNum")
        if not indexOk or tonumber(playerIndex) == nil then return false end
        local visibleOk, visible = invoke(square, "isCanSee", math.floor(playerIndex))
        if not visibleOk or visible == true then return false end
    end
    local objectsOk, moving = invoke(square, "getMovingObjects")
    if objectsOk and moving ~= nil then
        local sizeOk, size = invoke(moving, "size")
        if sizeOk and tonumber(size) and tonumber(size) > 0 then return false end
    end
    local cellOk, cell = invoke(square, "getCell")
    local xOk, x = invoke(square, "getX")
    local yOk, y = invoke(square, "getY")
    local zOk, z = invoke(square, "getZ")
    if not cellOk or not xOk or not yOk or not zOk then return false end
    local radius = SC.Config.get("spawnLocalSafetyRadius")
    local zombies = 0
    for dx = -radius, radius do
        for dy = -radius, radius do
            local nearbyOk, nearby = invoke(cell, "getGridSquare", x + dx, y + dy, z)
            local listOk, list = false, nil
            if nearbyOk then listOk, list = invoke(nearby, "getMovingObjects") end
            if listOk and list ~= nil then
                local sizeOk, size = invoke(list, "size")
                for index = 0, (sizeOk and math.min(tonumber(size) or 0, 16) or 0) - 1 do
                    local getOk, value = invoke(list, "get", index)
                    if getOk and type(instanceof) == "function" then
                        local typeOk, zombie = pcall(instanceof, value, "IsoZombie")
                        if typeOk and zombie == true then
                            zombies = zombies + 1
                            if zombies > SC.Config.get("spawnMaxNearbyZombies") then return false end
                        end
                    end
                end
            end
        end
    end
    return true
end

local function fallbackSquare(player, minimum, maximum, requireUnseen)
    local xOk, playerX = invoke(player, "getX")
    local yOk, playerY = invoke(player, "getY")
    local zOk, playerZ = invoke(player, "getZ")
    local cellOk, cell = invoke(player, "getCell")
    if not xOk or not yOk or not zOk or not cellOk or cell == nil then return nil end
    minimum = tonumber(minimum) or SC.Config.get("spawnMinDistance")
    maximum = tonumber(maximum) or SC.Config.get("spawnMaxDistance")
    for _ = 1, SC.Config.get("spawnSampleCount") do
        local distance = randomBetween(minimum, maximum)
        local octant = randomBetween(0, 7)
        local axis = randomBetween(math.floor(distance * 0.35), distance)
        local other = math.floor(math.sqrt(math.max(0, distance * distance - axis * axis)))
        local dx, dy = axis, other
        if octant % 2 == 1 then dx, dy = dy, dx end
        if octant >= 4 then dx = -dx end
        if octant == 2 or octant == 3 or octant == 6 or octant == 7 then dy = -dy end
        local squareOk, square = invoke(cell, "getGridSquare",
            math.floor(playerX + dx), math.floor(playerY + dy), math.floor(playerZ))
        if squareOk and safeSquare(square, player, requireUnseen) then return square end
    end
    return nil
end

function spawn.chooseSquare(player, runtime)
    if player == nil then return nil, "player is unavailable" end
    if SC.Encounter ~= nil and type(SC.Encounter.chooseSpawnSquare) == "function" then
        local ok, square = pcall(SC.Encounter.chooseSpawnSquare, player, runtime or {})
        if ok and square ~= nil and safeSquare(square, player) then return square end
    end
    local square = fallbackSquare(player, nil, nil, true)
    return square, square and nil or "no valid loaded unseen spawn square"
end

function spawn.chooseDebugSquare(player)
    if SC.Config.get("debugSpawnEnabled") ~= true then
        return nil, "debug spawning disabled"
    end
    if player == nil then return nil, "player is unavailable" end
    local minimum = SC.Config.get("debugSpawnMinDistance")
    local maximum = SC.Config.get("debugSpawnMaxDistance")
    local square = fallbackSquare(player, minimum, maximum, true)
    if square ~= nil then return square end
    square = fallbackSquare(player, minimum, maximum, false)
    return square, square and "visible debug fallback" or "no valid loaded debug spawn square"
end

local function recordFor(actor)
    if actor == nil or type(SC.Registry) ~= "table"
        or type(SC.Registry.idOf) ~= "function" or type(SC.Registry.byId) ~= "function" then
        return nil
    end
    local ok, id = pcall(SC.Registry.idOf, actor)
    if not ok or id == nil then return nil end
    local recordOk, record = pcall(SC.Registry.byId, id)
    return recordOk and record or nil
end

function spawn.isDebugActor(actor)
    if SC.Config.get("debugSpawnEnabled") ~= true then return false end
    local record = recordFor(actor)
    return record ~= nil and type(record.runtime) == "table"
        and record.runtime.debugSpawn == true
end

function spawn.isDebugProtected(actor)
    if not spawn.isDebugActor(actor) then return false end
    local record = recordFor(actor)
    return record.runtime.debugDiscovered ~= true
end

function spawn.markDebugDiscovered(actor)
    if not spawn.isDebugActor(actor) then return false end
    local record = recordFor(actor)
    if record.runtime.debugDiscovered == true then return false end
    record.runtime.debugDiscovered = true
    return true
end

local function finiteCoordinate(value)
    value = tonumber(value)
    if value == nil or value ~= value or value == math.huge or value == -math.huge then return nil end
    return value
end

function spawn.debugDescription(actor, currentPlayer)
    if not spawn.isDebugActor(actor) then return nil end
    local record = recordFor(actor)
    local identity = type(record.identity) == "table" and record.identity or {}
    local name = tostring(identity.forename or identity.name or "Unknown")
    if type(identity.surname) == "string" and identity.surname ~= "" then
        name = name .. " " .. identity.surname
    end
    local xOk, x = invoke(actor, "getX")
    local yOk, y = invoke(actor, "getY")
    local zOk, z = invoke(actor, "getZ")
    x, y, z = xOk and finiteCoordinate(x) or nil,
        yOk and finiteCoordinate(y) or nil, zOk and finiteCoordinate(z) or nil
    local position = x and y and string.format("%.1f,%.1f,%.1f", x, y, z or 0) or "unavailable"
    local distance = "unavailable"
    if x and y and currentPlayer ~= nil then
        local pxOk, px = invoke(currentPlayer, "getX")
        local pyOk, py = invoke(currentPlayer, "getY")
        local pzOk, pz = invoke(currentPlayer, "getZ")
        px, py, pz = pxOk and finiteCoordinate(px) or nil,
            pyOk and finiteCoordinate(py) or nil, pzOk and finiteCoordinate(pz) or nil
        if px and py then
            local dx, dy, dz = x - px, y - py, (z or 0) - (pz or 0)
            distance = string.format("%.1f", math.sqrt(dx * dx + dy * dy + dz * dz * 9))
        end
    end
    return "id=" .. tostring(record.id) .. " name=\"" .. name .. "\" at=" .. position
        .. " distance=" .. distance
end

function spawn.debugLog(event, actor, currentPlayer, reason)
    local description = spawn.debugDescription(actor, currentPlayer)
    if description == nil then return false end
    local suffix = reason ~= nil and " reason=" .. tostring(reason):gsub("[\r\n]", " ") or ""
    print("[SurvivorCompanion][debug-spawn] event=" .. tostring(event)
        .. " " .. description .. suffix)
    return true
end

function spawn.attempt(player, profile, runtime, source)
    if pendingSpawn ~= nil then return nil, "spawn_pending" end
    if #SC.Registry.living() + (SC.Vehicle and SC.Vehicle.storedCount() or 0)
        >= SC.Config.get("maxCompanions") then
        return nil, "companion cap reached"
    end
    local spawnSource = tostring(source or "encounter")
    local privateDebug = spawnSource == "debug" and SC.Config.get("debugSpawnEnabled") == true
    local square, reason
    if privateDebug then
        square, reason = spawn.chooseDebugSquare(player)
    else
        square, reason = spawn.chooseSquare(player, runtime)
    end
    if square == nil then return nil, reason end
    profile = type(profile) == "table" and profile or {
        recruited = false,
        identity = spawn.generateIdentity(),
    }
    if privateDebug then
        profile.debugSpawn = true
        profile.debugDiscovered = false
    end
    if type(SC.Actor.beginSpawn) ~= "function" then
        return SC.Actor.spawn(square, profile)
    end
    local ticket, result = SC.Actor.beginSpawn(square, profile)
    if ticket == nil then return nil, result end
    pendingSpawn = {
        ticket = ticket,
        source = spawnSource,
        startedAt = nowMs(),
    }
    local status, detail = spawn.pollPending()
    if status == "spawned" then return detail end
    if status == "failed" then return nil, detail end
    return nil, "spawn_pending"
end

function spawn.pollPending()
    if pendingSpawn == nil then return "idle", "no spawn request is pending" end
    if SC.Actor == nil or type(SC.Actor.pollSpawn) ~= "function" then
        local source = pendingSpawn.source
        pendingSpawn = nil
        return "failed", "spawn polling is unavailable", source
    end
    local actor, result = SC.Actor.pollSpawn(pendingSpawn.ticket)
    if actor ~= nil then
        local source = pendingSpawn.source
        pendingSpawn = nil
        return "spawned", actor, source
    end
    if result == "spawn_pending" then return "pending", result, pendingSpawn.source end
    local source = pendingSpawn.source
    pendingSpawn = nil
    return "failed", result, source
end

function spawn.hasPending()
    return pendingSpawn ~= nil
end

function spawn.debugPulse(player, runtime, current)
    if SC.Config.get("debugSpawnEnabled") ~= true then return false, "debug spawning disabled" end
    if type(runtime) == "table" and runtime.active == false then
        local ready, reason = SC.Actor.checkBridge(false)
        if ready ~= true then return false, reason or runtime.disabledReason end
        runtime.active = true
        runtime.disabledReason = nil
    end
    current = current or nowMs()
    if current - lastDebugAttempt < SC.Config.get("debugSpawnIntervalMs") then
        return false, "debug spawn cooldown"
    end
    if #SC.Registry.living() > 0 or (SC.Vehicle and SC.Vehicle.storedCount() > 0) then
        return false, "a living or vehicle-stored companion already exists"
    end
    if player == nil then return false, "player is unavailable" end
    local ready, providerReason = SC.Actor.checkBridge(false)
    if ready ~= true then return false, providerReason end
    lastDebugAttempt = current
    local actor, reason = spawn.attempt(player, nil, runtime, "debug")
    return actor ~= nil, actor or reason
end

function spawn.productionPulse(player, runtime, current)
    if SC.Config.get("productionEncounterEnabled") ~= true then
        return false, "production encounters disabled"
    end
    if type(runtime) == "table" and runtime.active == false then
        local ready, reason = SC.Actor.checkBridge(false)
        if ready ~= true then return false, reason or runtime.disabledReason end
        runtime.active = true
        runtime.disabledReason = nil
    end
    current = current or nowMs()
    if productionStartedAt == nil then productionStartedAt = current end
    if current - productionStartedAt < SC.Config.get("productionSpawnInitialDelayMs") then
        return false, "production encounter initial delay"
    end
    if current - lastProductionAttempt < SC.Config.get("productionSpawnCooldownMs") then
        return false, "production encounter cooldown"
    end
    if player == nil then return false, "player is unavailable" end
    local ready, providerReason = SC.Actor.checkBridge(false)
    if ready ~= true then return false, providerReason end

    local neutral = 0
    for _, record in ipairs(SC.Registry.records()) do
        if record.actor ~= nil and record.recruited ~= true
            and type(record.factionId) ~= "string"
            and not (type(record.runtime) == "table" and record.runtime.inactive == true) then
            neutral = neutral + 1
        end
    end
    if neutral >= SC.Config.get("maxNeutralEncounters") then
        return false, "neutral encounter already active"
    end
    if SC.Encounter ~= nil and type(SC.Encounter.canSpawnEncounter) == "function" then
        local ok, eligible, reason = pcall(SC.Encounter.canSpawnEncounter, player, runtime or {})
        if not ok or eligible ~= true then
            return false, ok and (reason or "encounter eligibility rejected") or tostring(eligible)
        end
    end

    -- Record every bounded attempt, successful or not, so an unavailable square
    -- never turns the cadence into broad repeated world scans.
    lastProductionAttempt = current
    local actor, reason = spawn.attempt(player, nil, runtime, "production")
    return actor ~= nil, actor or reason
end

function spawn.reset()
    if pendingSpawn ~= nil and SC.Actor ~= nil and type(SC.Actor.cancelSpawn) == "function" then
        pcall(SC.Actor.cancelSpawn, pendingSpawn.ticket)
    end
    pendingSpawn = nil
    lastDebugAttempt = -math.huge
    productionStartedAt = nil
    lastProductionAttempt = -math.huge
    sequence = 0
    lastGeneratedIdentityKey = nil
end

return spawn
