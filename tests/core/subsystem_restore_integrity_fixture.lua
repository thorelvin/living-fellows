-- SPDX-License-Identifier: MIT

local SC = SurvivorCompanion

local limits = {
    baseMaxZones = 24,
    baseMaxStorages = 32,
    baseMaxMaintenanceTargets = 64,
    baseMaxJobs = 64,
    baseHistoryLimit = 96,
    infectionCrisisEvidenceLimit = 32,
    infectionCrisisHistoryLimit = 96,
    infectionCrisisMaxRecords = 32,
    mindThoughtLimit = 12,
    mindPairLimit = 64,
    mindPairMemoryLimit = 8,
    mindHistoryLimit = 96,
    griefMemoryLimit = 8,
    griefDeathHistoryLimit = 32,
}

local function hash(value)
    value = tostring(value or "")
    local result = 17
    for index = 1, #value do
        result = (result * 33 + string.byte(value, index)) % 2147483647
    end
    return result
end

SC.GameplayUtil = {
    nowMs = function() return SC_TEST_CLOCK or 1000 end,
    config = function(key) return limits[key] end,
    stableHash = hash,
    idOf = function(value)
        if type(value) == "string" then return value end
        return type(value) == "table" and value.id or nil
    end,
    call = function() return nil, false end,
}

SC.Config = {
    get = function(key) return limits[key] end,
}

SC.Registry = {
    isValidId = function(id)
        return type(id) == "string" and string.sub(id, 1, 3) == "sc-"
    end,
    byId = function() return nil end,
    living = function() return {} end,
}

SC.Actor = {
    cancelSpawn = function() return true end,
}

