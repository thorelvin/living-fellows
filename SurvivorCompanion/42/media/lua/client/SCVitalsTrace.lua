-- SPDX-License-Identifier: MIT
-- Opt-in, bounded probe for live CharacterStat discovery on Project Zomboid 42.x.

if not SurvivorCompanion and type(require) == "function" then pcall(require, "SCNamespace") end

local SC = SurvivorCompanion
SC.VitalsTrace = SC.VitalsTrace or {}
local Trace = SC.VitalsTrace

local reportedAt = {}
local reportedCount = 0

local function config(key, fallback)
    if SC.Config == nil or type(SC.Config.get) ~= "function" then return fallback end
    local value = SC.Config.get(key)
    if value == nil then return fallback end
    return value
end

local function enabled()
    return config("vitalsStatTrace", false) == true
end

local function actorKey(record)
    if type(record) == "table" and record.id ~= nil then return tostring(record.id) end
    return tostring(type(record) == "table" and record.actor or record)
end

local function diagnostic(message)
    if SC.Diagnostics and type(SC.Diagnostics.report) == "function" then
        pcall(SC.Diagnostics.report, "vitals-trace", nil, message)
    elseif type(print) == "function" then
        print("[SurvivorCompanion/vitals-trace] " .. message)
    end
end

function Trace.report(record, current)
    if not enabled() then return false, "disabled" end
    if type(record) ~= "table" or record.actor == nil or SC.Vitals == nil
        or type(SC.Vitals.statVector) ~= "function" then
        return false, "unavailable"
    end
    current = tonumber(current) or 0
    local key = actorKey(record)
    local interval = math.max(1000, tonumber(config("vitalsStatTraceIntervalMs", 10000)) or 10000)
    if current - (tonumber(reportedAt[key]) or -interval) < interval then
        return false, "cooldown"
    end
    if reportedAt[key] == nil then
        local limit = math.max(1, tonumber(config("vitalsStatTraceActorLimit", 32)) or 32)
        if reportedCount >= limit then return false, "actor_limit" end
        reportedCount = reportedCount + 1
    end
    reportedAt[key] = current

    local vector = SC.Vitals.statVector(record.actor)
    local names = type(SC.Vitals.statNames) == "function" and SC.Vitals.statNames() or {}
    local fields = {
        "actor=" .. key,
        "doCharacterStats=" .. tostring(SC.Vitals.characterStatsEnabled()),
    }
    for _, name in ipairs(names) do
        fields[#fields + 1] = name .. "=" .. tostring(vector[name])
    end
    fields[#fields + 1] = "NICOTINE_EFFECTIVE=" .. tostring(vector.NICOTINE_EFFECTIVE)
    diagnostic(table.concat(fields, " "))
    return true
end

function Trace.snapshot()
    return {
        enabled = enabled(),
        actorCount = reportedCount,
    }
end

function Trace.reset()
    reportedAt = {}
    reportedCount = 0
    return true
end

return Trace
