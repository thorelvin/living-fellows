-- SPDX-License-Identifier: MIT
-- Named encounter animals are real vanilla IsoAnimals. The saved slot keeps
-- the persistent animal ID separately from the online ID used by getAnimal().
-- An absent animal is never silently replaced with a clone.

local SC = SurvivorCompanion
SC.OddballAnimals = SC.OddballAnimals or {}
local Animals = SC.OddballAnimals
local followAt = {}
local loadedScan = { cell = nil, list = nil, untilMs = 0 }

local function U() return SC.GameplayUtil end

local function number(value)
    if type(value) == "number" then return value end
    if type(value) == "string" then return tonumber(value) end
    return nil
end

local function onlineId(animal)
    local id = number(select(1, U().call(animal, "getOnlineID")))
    -- The native map uses signed short IDs and skips -1. Single-player
    -- animals can keep the -1 sentinel and are found via IsoCell:getAnimals().
    if id and id >= -32768 and id <= 32767 and id ~= -1
        and id == math.floor(id) then
        return id
    end
    return nil
end

local function stableId(animal)
    local id = number(select(1, U().call(animal, "getAnimalID")))
    if id and id >= 0 and id == math.floor(id) then return id end
    return nil
end

local function matches(animal, group, slot, record)
    if animal == nil or stableId(animal) ~= number(record.id) then return false end
    local data = select(1, U().call(animal, "getModData"))
    return type(data) == "table" and data.lfOddballGroupId == group.id
        and number(data.lfOddballAnimalSlot) == slot
end

local function firstMatching(list, predicate)
    if list == nil then return nil end
    if type(list) == "table" then
        for _, candidate in ipairs(list) do
            if predicate(candidate) then return candidate end
        end
        return nil
    end
    local count = number(select(1, U().call(list, "size")))
    if not count then return nil end
    for index = 0, count - 1 do
        local candidate = select(1, U().call(list, "get", index))
        if predicate(candidate) then return candidate end
    end
    return nil
end

local function stillLoaded(animal)
    local square = select(1, U().call(animal, "getSquare"))
    local squareAnimals = square and select(1, U().call(square, "getAnimals"))
    return firstMatching(squareAnimals,
        function(candidate) return candidate == animal end) ~= nil
end

local function invalidateLoadedScan()
    loadedScan.cell, loadedScan.list, loadedScan.untilMs = nil, nil, 0
end

local function findLoaded(group, slot, record)
    if type(getCell) ~= "function" then return nil end
    local cellOk, cell = pcall(getCell)
    if not cellOk or cell == nil then return nil end
    local current = number(U().nowMs()) or 0
    local reused = loadedScan.cell == cell and loadedScan.list ~= nil
        and current < loadedScan.untilMs
    if not reused then
        loadedScan.cell = cell
        loadedScan.list = select(1, U().call(cell, "getAnimals"))
        loadedScan.untilMs = current + 1000
    end
    return firstMatching(loadedScan.list, function(candidate)
        return matches(candidate, group, slot, record)
            and (not reused or stillLoaded(candidate))
    end)
end

local function slots(group)
    local story = type(group) == "table" and group.oddball or nil
    if type(story) ~= "table" then return nil end
    story.animals = type(story.animals) == "table" and story.animals or {}
    story.animals.slots = type(story.animals.slots) == "table"
        and story.animals.slots or {}
    return story.animals.slots
end

local function location(point)
    if type(point) ~= "table" then return nil end
    local x, y, z = number(point.x), number(point.y), number(point.z) or 0
    if not x or not y or z < -2 or z > 2 then return nil end
    local square = U().gridSquare(math.floor(x), math.floor(y), z)
    if not square or U().isSafeSpawnSquare(square) ~= true then return nil end
    return square, math.floor(x), math.floor(y), z
end

function Animals.spawn(group, slot, spec, point)
    local records = slots(group)
    if not records or type(slot) ~= "number" or slot < 1 or slot > 10
        or type(spec) ~= "table" or type(spec.kind) ~= "string"
        or type(spec.breed) ~= "string" or type(spec.name) ~= "string" then
        return false, "invalid_named_animal"
    end
    if records[slot] ~= nil then return true, "animal_slot_already_seeded" end
    local square, x, y, z = location(point)
    if not square then return false, "animal_enclosure_unavailable" end
    if not AnimalDefinitions or not AnimalDefinitions.getDef
        or type(addAnimal) ~= "function" or type(getCell) ~= "function" then
        return false, "vanilla_animal_api_unavailable"
    end
    local defined, definition = pcall(AnimalDefinitions.getDef, spec.kind)
    if not defined then return false, "animal_definition_unavailable" end
    local breed = definition and select(1,
        U().call(definition, "getBreedByName", spec.breed))
    if not breed then return false, "animal_breed_unavailable" end
    local ok, animal = pcall(addAnimal, getCell(),
        x + 0.35 + (slot % 3) * 0.12,
        y + 0.35 + (math.floor(slot / 3) % 3) * 0.12,
        z, spec.kind, breed, false)
    if not ok or not animal then return false, "animal_spawn_failed" end
    U().call(animal, "setCustomName", spec.name)
    U().call(animal, "setWild", false)
    local data = select(1, U().call(animal, "getModData"))
    if type(data) == "table" then
        data.lfOddballGroupId = group.id
        data.lfOddballAnimalSlot = slot
    end
    local _, added = U().call(animal, "addToWorld")
    if not added then
        U().call(animal, "removeFromWorld")
        return false, "animal_world_add_failed"
    end
    local id = stableId(animal)
    if not id then
        U().call(animal, "removeFromWorld")
        return false, "animal_native_id_unavailable"
    end
    records[slot] = { kind = spec.kind, breed = spec.breed,
        name = spec.name, id = id, onlineId = onlineId(animal),
        x = x, y = y, z = z,
        spawned = true }
    invalidateLoadedScan()
    return true, animal
end

-- The player can bring a living animal through the vanilla pick-up and drop
-- actions. Register that exact native animal instead of spawning a substitute.
function Animals.adopt(group, slot, animal, expectedKind)
    local records = slots(group)
    if not records or records[slot] ~= nil or animal == nil then
        return false, "animal_slot_occupied_or_missing"
    end
    local kind = select(1, U().call(animal, "getAnimalType"))
    local id = stableId(animal)
    local breed = select(1, U().call(animal, "getBreed"))
    local breedName = breed and select(1, U().call(breed, "getName"))
    local x, y, z = U().position(animal)
    if kind ~= expectedKind or not id or not x or not y then
        return false, "animal_kind_or_id_unavailable"
    end
    local data = select(1, U().call(animal, "getModData"))
    if type(data) ~= "table" or data.lfOddballGroupId then
        return false, "animal_already_owned"
    end
    data.lfOddballGroupId, data.lfOddballAnimalSlot = group.id, slot
    records[slot] = { kind = kind,
        breed = type(breedName) == "string" and breedName or "",
        name = select(1,
        U().call(animal, "getCustomName")) or kind,
        id = id, onlineId = onlineId(animal),
        x = math.floor(x), y = math.floor(y),
        z = z or 0, spawned = true, adopted = true }
    invalidateLoadedScan()
    return true, "existing_native_animal_adopted"
end

function Animals.find(group, slot)
    local records = slots(group)
    local record = records and records[slot] or nil
    if not record or record.dead == true or not record.id then
        return nil, record
    end
    local animal
    local lookupId = number(record.onlineId)
    if lookupId and type(getAnimal) == "function" then
        local ok, candidate = pcall(getAnimal, lookupId)
        if ok and matches(candidate, group, slot, record) then
            animal = candidate
        end
    end
    -- Existing saves have only record.id (getAnimalID), and online IDs may be
    -- reassigned after loading. Search loaded animals by their persisted ID and
    -- owner marker, then refresh the fast lookup key. Never trust a reused
    -- online ID without the stable ID and owner marker.
    if animal == nil then animal = findLoaded(group, slot, record) end
    if animal == nil then return nil, record end
    record.onlineId = onlineId(animal)
    local health = number(select(1, U().call(animal, "getHealth")))
    if health ~= nil and health <= 0 then
        record.dead = true
        return nil, record
    end
    local x, y, z = U().position(animal)
    if x then record.x, record.y, record.z = math.floor(x), math.floor(y), z end
    return animal, record
end

function Animals.status(group, slot, player)
    local animal, record = Animals.find(group, slot)
    if not record then return "unseeded" end
    if animal then return "alive", animal end
    if record.dead == true then return "dead" end
    -- Native lookup may return nil while the animal is unloaded. Absence alone
    -- is not evidence of death, especially across a save/load.
    return "unloaded"
end

function Animals.follow(group, slot, actor, current)
    local animal = Animals.find(group, slot)
    if not animal or not actor then return false, "animal_or_keeper_unavailable" end
    local key = group.id .. ":" .. tostring(slot)
    if current < (followAt[key] or 0) then return false, "follow_cooldown" end
    followAt[key] = current + 5000
    local ax, ay, az = U().position(animal)
    local px, py, pz = U().position(actor)
    if not ax or not px or az ~= pz then return false, "different_floor" end
    if (ax - px) ^ 2 + (ay - py) ^ 2 <= 9 then return true, "animal_near_keeper" end
    local _, called = U().call(animal, "pathToCharacter", actor)
    return called, called and "animal_following" or "animal_path_unavailable"
end

function Animals.isProtected(animal)
    local data = animal and select(1, U().call(animal, "getModData"))
    return type(data) == "table" and (type(data.lfOddballGroupId) == "string"
        or type(data.lfWendellGroupId) == "string")
end

return Animals
