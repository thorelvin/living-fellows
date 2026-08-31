-- SPDX-License-Identifier: MIT

require "SCNamespace"
require "SCConfig"

local SC = SurvivorCompanion
SC.Diagnostics = SC.Diagnostics or {}

local diagnostics = SC.Diagnostics
local entries = {}
local circuits = {}

local function nowMs()
    if getTimestampMs ~= nil then
        local ok, value = pcall(getTimestampMs)
        local numeric = ok and tonumber(value) or nil
        if numeric ~= nil then return numeric end
    end
    return math.floor(os.clock() * 1000)
end

local function keyFor(subsystem, companionId)
    return tostring(subsystem or "core") .. ":" .. tostring(companionId or "global")
end

function diagnostics.report(subsystem, companionId, message, detail)
    local key = keyFor(subsystem, companionId)
    local current = nowMs()
    local entry = entries[key]
    if entry == nil then
        entry = {
            count = 0,
            consecutiveFailures = 0,
            recoveries = 0,
            lastPrint = -math.huge,
            lastMessage = nil,
        }
        entries[key] = entry
    end

    entry.count = entry.count + 1
    entry.lastMessage = tostring(message or "unknown error")
    entry.lastDetail = detail ~= nil and tostring(detail) or nil
    entry.lastAt = current

    if current - entry.lastPrint >= SC.Config.get("runtime", "diagnosticCooldownMs") then
        entry.lastPrint = current
        local suffix = entry.lastDetail and (": " .. entry.lastDetail) or ""
        print("[SurvivorCompanion][" .. key .. "] " .. entry.lastMessage .. suffix)
    end

    return entry.count
end

local function openCircuit(subsystem, companionId, entry, current)
    local key = keyFor(subsystem, companionId)
    local resetMs = math.max(1,
        tonumber(SC.Config.get("runtime", "circuitBreakerResetMs")) or 30000)
    circuits[key] = {
        state = "open",
        openedAt = current,
        retryAt = current + resetMs,
        manual = false,
    }
    entry.openedAt = current
    entry.retryAt = current + resetMs
end

local function recordFailure(subsystem, companionId, message, detail)
    diagnostics.report(subsystem, companionId, message, detail)
    local key = keyFor(subsystem, companionId)
    local entry = entries[key]
    entry.consecutiveFailures = (entry.consecutiveFailures or 0) + 1
    local threshold = math.max(1,
        tonumber(SC.Config.get("runtime", "circuitBreakerErrors")) or 3)
    if entry.consecutiveFailures >= threshold then
        openCircuit(subsystem, companionId, entry, nowMs())
    end
    return entry
end

function diagnostics.guard(subsystem, companionId, callback, ...)
    if type(callback) ~= "function" then
        diagnostics.report(subsystem, companionId, "invalid diagnostic callback")
        return false, "invalid callback"
    end
    if diagnostics.isDisabled(subsystem, companionId) then
        return false, "circuit open"
    end

    local results = { pcall(callback, ...) }
    if not results[1] then
        recordFailure(subsystem, companionId, "subsystem exception", results[2])
        return false, results[2]
    end

    local key = keyFor(subsystem, companionId)
    local entry = entries[key]
    local circuit = circuits[key]
    if entry ~= nil then
        if (entry.consecutiveFailures or 0) > 0 or circuit ~= nil then
            entry.recoveries = (entry.recoveries or 0) + 1
            entry.lastRecoveredAt = nowMs()
        end
        entry.consecutiveFailures = 0
        entry.retryAt = nil
    end
    circuits[key] = nil

    local unpackFn = table.unpack or unpack
    return true, unpackFn(results, 2)
end

function diagnostics.isDisabled(subsystem, companionId)
    local key = keyFor(subsystem, companionId)
    local circuit = circuits[key]
    if circuit == nil then return false end
    if circuit.manual == true then return true end
    local current = nowMs()
    if current < (tonumber(circuit.retryAt) or math.huge) then return true end
    circuit.state = "half_open"
    return false
end

function diagnostics.disable(subsystem, companionId, reason)
    local key = keyFor(subsystem, companionId)
    diagnostics.report(subsystem, companionId, reason or "subsystem disabled")
    circuits[key] = {
        state = "open",
        openedAt = nowMs(),
        retryAt = math.huge,
        manual = true,
        reason = tostring(reason or "subsystem disabled"),
    }
end

function diagnostics.retry(subsystem, companionId)
    local key = keyFor(subsystem, companionId)
    local entry = entries[key]
    if entry ~= nil then
        entry.consecutiveFailures = 0
        entry.retryAt = nil
    end
    circuits[key] = nil
    return true
end

function diagnostics.snapshot()
    local copy = {}
    for key, entry in pairs(entries) do
        local circuit = circuits[key]
        local disabled = false
        if circuit ~= nil then
            disabled = circuit.manual == true
                or nowMs() < (tonumber(circuit.retryAt) or math.huge)
            if not disabled and circuit.manual ~= true then circuit.state = "half_open" end
        end
        copy[key] = {
            count = entry.count,
            lastMessage = entry.lastMessage,
            lastDetail = entry.lastDetail,
            lastAt = entry.lastAt,
            consecutiveFailures = entry.consecutiveFailures or 0,
            recoveries = entry.recoveries or 0,
            lastRecoveredAt = entry.lastRecoveredAt,
            state = circuit and circuit.state or "closed",
            disabled = disabled,
            retryAt = circuit and circuit.retryAt or nil,
            manual = circuit and circuit.manual == true or false,
        }
    end
    return copy
end

function diagnostics.reset()
    entries = {}
    circuits = {}
end

return diagnostics
