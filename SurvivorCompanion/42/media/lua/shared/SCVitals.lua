-- SPDX-License-Identifier: MIT

require "SCNamespace"
require "SCNativeList"

local SC = SurvivorCompanion
SC.Vitals = SC.Vitals or {}

local vitals = SC.Vitals

local function invoke(object, name, fallback, ...)
    if object == nil then
        return fallback
    end
    local method = object[name]
    if type(method) ~= "function" then
        return fallback
    end
    local ok, value = pcall(method, object, ...)
    if not ok then
        return fallback
    end
    return value
end

local function finite(value, fallback)
    value = tonumber(value)
    if value == nil or value ~= value or value == math.huge or value == -math.huge then
        return fallback
    end
    return value
end

local function characterStat(name)
    if CharacterStat == nil then return nil end
    local ok, value = pcall(function() return CharacterStat[name] end)
    return ok and value or nil
end

local function captureStat(actor, name)
    local stats = invoke(actor, "getStats", nil)
    local stat = characterStat(name)
    if not stats or stat == nil then return nil end
    return finite(invoke(stats, "get", nil, stat), nil)
end

local function setRequired(object, name, ...)
    if object == nil then return false, "native target is unavailable for " .. tostring(name) end
    local ok, callback = pcall(function() return object[name] end)
    if not ok or type(callback) ~= "function" then
        return false, "native setter is unavailable: " .. tostring(name)
    end
    local applied, reason = pcall(callback, object, ...)
    if not applied then
        return false, "native setter failed: " .. tostring(name) .. ": " .. tostring(reason)
    end
    return true
end

local function capturePart(part)
    return {
        type = tostring(invoke(part, "getType", "unknown")),
        health = finite(invoke(part, "getHealth", 100), 100),
        bitten = invoke(part, "bitten", false) == true,
        scratched = invoke(part, "scratched", false) == true,
        cut = invoke(part, "isCut", false) == true,
        deepWound = invoke(part, "isDeepWounded", false) == true,
        bleeding = invoke(part, "bleeding", false) == true,
        bandaged = invoke(part, "bandaged", false) == true,
        bandageDirty = invoke(part, "isBandageDirty", false) == true,
        bandageLife = finite(invoke(part, "getBandageLife", 0), 0),
        bandageType = invoke(part, "getBandageType", nil),
        biteTime = finite(invoke(part, "getBiteTime", 0), 0),
        scratchTime = finite(invoke(part, "getScratchTime", 0), 0),
        cutTime = finite(invoke(part, "getCutTime", 0), 0),
        deepWoundTime = finite(invoke(part, "getDeepWoundTime", 0), 0),
        bleedingTime = finite(invoke(part, "getBleedingTime", 0), 0),
        fractureTime = finite(invoke(part, "getFractureTime", 0), 0),
        burnTime = finite(invoke(part, "getBurnTime", 0), 0),
        stitchTime = finite(invoke(part, "getStitchTime", 0), 0),
        stitched = invoke(part, "stitched", false) == true,
        haveGlass = invoke(part, "haveGlass", false) == true,
        haveBullet = invoke(part, "haveBullet", false) == true,
        splint = invoke(part, "isSplint", false) == true,
        splintFactor = finite(invoke(part, "getSplintFactor", 0), 0),
        splintItem = invoke(part, "getSplintItem", nil),
        additionalPain = finite(invoke(part, "getAdditionalPain", 0), 0),
        stiffness = finite(invoke(part, "getStiffness", 0), 0),
        woundInfection = finite(invoke(part, "getWoundInfectionLevel", 0), 0),
        infectedWound = invoke(part, "isInfectedWound", false) == true,
        alcohol = finite(invoke(part, "getAlcoholLevel", 0), 0),
        plantain = finite(invoke(part, "getPlantainFactor", 0), 0),
        comfrey = finite(invoke(part, "getComfreyFactor", 0), 0),
        garlic = finite(invoke(part, "getGarlicFactor", 0), 0),
    }
end

function vitals.capture(actor)
    if actor == nil then
        return nil, "actor is required"
    end
    local body = invoke(actor, "getBodyDamage", nil)
    if body == nil then
        return nil, "native body damage is unavailable"
    end

    local result = {
        health = finite(invoke(actor, "getHealth", 100), 100),
        overallHealth = finite(invoke(body, "getOverallBodyHealth", 100), 100),
        infected = invoke(body, "isInfected", false) == true,
        infectionTime = finite(invoke(body, "getInfectionTime", -1), -1),
        infectionMortalityDuration = finite(invoke(body, "getInfectionMortalityDuration", -1), -1),
        apparentInfection = finite(invoke(body, "getApparentInfectionLevel", 0), 0),
        hunger = captureStat(actor, "HUNGER"),
        thirst = captureStat(actor, "THIRST"),
        parts = {},
    }

    local parts = invoke(body, "getBodyParts", nil)
    if parts ~= nil and type(parts.size) == "function" and type(parts.get) == "function" then
        local count = math.min(32, SC.NativeList.size(parts))
        for index = 0, count - 1 do
            local part = SC.NativeList.get(parts, index)
            if part ~= nil then
                result.parts[#result.parts + 1] = capturePart(part)
            end
        end
    end
    return result
end

local function applyPart(part, saved)
    local operations = {
        { "SetHealth", finite(saved.health, 100) },
        { "SetBitten", saved.bitten == true },
        { "setScratched", saved.scratched == true, false },
        { "setCut", saved.cut == true, false },
        { "setDeepWounded", saved.deepWound == true },
        { "setBleeding", saved.bleeding == true },
        { "setBandaged", saved.bandaged == true, finite(saved.bandageLife, 0),
            saved.bandageDirty == true, tostring(saved.bandageType or "") },
        { "setBiteTime", finite(saved.biteTime, 0) },
        { "setScratchTime", finite(saved.scratchTime, 0) },
        { "setCutTime", finite(saved.cutTime, 0) },
        { "setDeepWoundTime", finite(saved.deepWoundTime, 0) },
        { "setBleedingTime", finite(saved.bleedingTime, 0) },
        { "setFractureTime", finite(saved.fractureTime, 0) },
        { "setBurnTime", finite(saved.burnTime, 0) },
        { "setStitchTime", finite(saved.stitchTime, 0) },
        { "setStitched", saved.stitched == true },
        { "setHaveGlass", saved.haveGlass == true },
        { "setHaveBullet", saved.haveBullet == true, 0 },
        { "setSplint", saved.splint == true, finite(saved.splintFactor, 0) },
        { "setSplintFactor", finite(saved.splintFactor, 0) },
        { "setSplintItem", tostring(saved.splintItem or "") },
        { "setAdditionalPain", finite(saved.additionalPain, 0) },
        { "setStiffness", finite(saved.stiffness, 0) },
        { "setWoundInfectionLevel", finite(saved.woundInfection, 0) },
        { "setAlcoholLevel", finite(saved.alcohol, 0) },
        { "setPlantainFactor", finite(saved.plantain, 0) },
        { "setComfreyFactor", finite(saved.comfrey, 0) },
        { "setGarlicFactor", finite(saved.garlic, 0) },
    }
    local unpackFn = table.unpack or unpack
    for _, operation in ipairs(operations) do
        local ok, reason = setRequired(part, unpackFn(operation))
        if not ok then return false, reason end
    end
    return true
end

function vitals.apply(actor, saved)
    if actor == nil or type(saved) ~= "table" then
        return false, "actor and native vitals are required"
    end
    local body = invoke(actor, "getBodyDamage", nil)
    if body == nil then
        return false, "native body damage is unavailable"
    end

    local currentParts = invoke(body, "getBodyParts", nil)
    local byType = {}
    if currentParts ~= nil and type(currentParts.size) == "function"
        and type(currentParts.get) == "function" then
        local count = math.min(32, SC.NativeList.size(currentParts))
        for index = 0, count - 1 do
            local part = SC.NativeList.get(currentParts, index)
            byType[tostring(invoke(part, "getType", "unknown"))] = part
        end
    end
    if type(saved.parts) == "table" then
        for _, savedPart in ipairs(saved.parts) do
            if type(savedPart) == "table" then
                local part = byType[tostring(savedPart.type)]
                if part == nil then
                    return false, "saved native body part is unavailable: " .. tostring(savedPart.type)
                end
                local applied, reason = applyPart(part, savedPart)
                if not applied then return false, reason end
            end
        end
    end

    local overall = math.max(0.1, finite(saved.overallHealth, finite(saved.health, 100)))
    local actorHealth = math.max(0.1, finite(saved.health, overall))
    local operations = {
        { body, "setInfected", saved.infected == true },
        { body, "setInfectionTime", finite(saved.infectionTime, -1) },
        { body, "setInfectionMortalityDuration", finite(saved.infectionMortalityDuration, -1) },
        { body, "setOverallBodyHealth", overall },
        { actor, "setHealth", actorHealth },
    }
    local unpackFn = table.unpack or unpack
    for _, operation in ipairs(operations) do
        local ok, reason = setRequired(unpackFn(operation))
        if not ok then return false, reason end
    end

    local stats = invoke(actor, "getStats", nil)
    local restoredNeeds = {}
    for _, entry in ipairs({ { "HUNGER", saved.hunger }, { "THIRST", saved.thirst } }) do
        local stat = characterStat(entry[1])
        local amount = finite(entry[2], nil)
        if stats and stat ~= nil and amount ~= nil then
            amount = math.max(0, math.min(1, amount))
            local ok, reason = setRequired(stats, "set", stat, amount)
            if not ok then return false, reason end
            restoredNeeds[#restoredNeeds + 1] = { name = entry[1], amount = amount }
        end
    end

    local verified, verifyReason = vitals.capture(actor)
    if verified == nil then return false, verifyReason end
    if verified.infected ~= (saved.infected == true)
        or math.abs(finite(verified.overallHealth, -1) - overall) > 0.1
        or math.abs(finite(verified.health, -1) - actorHealth) > 0.1 then
        return false, "native vitals did not retain restored health/infection state"
    end
    for _, entry in ipairs(restoredNeeds) do
        local value = entry.name == "HUNGER" and verified.hunger or verified.thirst
        if type(value) ~= "number" or math.abs(value - entry.amount) > 0.001 then
            return false, "native vitals did not retain restored " .. string.lower(entry.name)
        end
    end
    return true
end

function vitals.summary(actor)
    local snapshot, reason = vitals.capture(actor)
    if snapshot == nil then
        return nil, reason
    end
    local wounds = 0
    local bleeding = 0
    local bites = 0
    for _, part in ipairs(snapshot.parts) do
        if part.bitten or part.scratched or part.cut or part.deepWound or part.burnTime > 0 then
            wounds = wounds + 1
        end
        if part.bleeding then
            bleeding = bleeding + 1
        end
        if part.bitten then
            bites = bites + 1
        end
    end
    return {
        health = snapshot.overallHealth,
        wounds = wounds,
        bleeding = bleeding,
        bites = bites,
        knox = snapshot.infected,
        apparentInfection = snapshot.apparentInfection,
    }
end

return vitals
