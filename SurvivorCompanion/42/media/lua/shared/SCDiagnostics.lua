-- SPDX-License-Identifier: MIT

require "SCNamespace"
require "SCCall"
require "SCConfig"

local SC = SurvivorCompanion
SC.Diagnostics = SC.Diagnostics or {}

local diagnostics = SC.Diagnostics
local entries = {}
local circuits = {}
local circuitCount = 0
local failingCount = 0
local reportLines = {}

-- Keys and error details in the ordinary console can contain actor names,
-- world names and filesystem paths. Only these source literals may enter the
-- player-facing report. A new diagnostic remains private by default.
local publicSystems = {}
for _, name in ipairs({
    "action-supervisor", "actor", "actor-death", "actor-provider", "actor-removal",
    "alife-adapter", "background", "bandits-adapter", "base-job", "base-work", "bootstrap",
    "camp-supply-transfer", "commands", "companion-map", "container-hook", "convoy",
    "departure-preparation", "diary-ui", "downtime", "field-work", "floor-sort",
    "expedition", "expedition-map", "faction", "faction-spawn", "factions",
    "fishing-map", "handover", "medical", "persistence", "power-night",
    "pzoptimizer-adapter", "runtime", "terminal", "terminal-load", "terminal-place",
    "terminal_hardware", "trade-recovery", "trade-transaction", "vehicle", "vitals",
    "combat-gun-service", "needs-rate", "radio-work", "senses", "senses-reflex",
    "wood-cargo", "wood-expedition",
}) do publicSystems[name] = true end
local publicMessages = {}
for _, message in ipairs({
    "A-Life adapter unavailable", "Bandits adapter unavailable", "PZOptimizer adapter unavailable",
    "OnInitGlobalModData failed", "OnSave failed", "action cancellation callback failed",
    "action rollback verification failed", "actor quarantined inactive after unverified removal",
    "bootstrap installation failed", "companion actors disabled", "companion container refresh failed",
    "companion placement recovery retained for retry", "computer menu failed", "container marker failed",
    "diary reader failed", "initial restore pulse failed; imported records retained",
    "item ownership retained for recovery", "map overlay failed", "mapped shore lookup failed",
    "module contract failed", "native companion failed its runtime health gate",
    "native corpse chunk save failed", "native vitals update failed", "radio restore failed",
    "receiver delivery failed", "recovery pending; world records preserved", "restore initialization failed",
    "restore record quarantined", "runtime contracts failed", "runtime start failed", "save incomplete",
    "save record quarantined", "save transaction aborted; prior snapshot retained",
    "saved successor recovery failed", "started", "subsystem exception", "view teardown pending",
}) do publicMessages[message] = true end

local function rememberReportLine(system, message)
    if not publicSystems[system] then return end
    if #reportLines == 5 then table.remove(reportLines, 1) end
    reportLines[#reportLines + 1] = "[" .. system .. "] "
        .. (publicMessages[message] and message or "Diagnostic reported")
end

function diagnostics.recentReportLines()
    local copy = {}
    for index, line in ipairs(reportLines) do copy[index] = line end
    return copy
end

function diagnostics.clearReportLines()
    reportLines = {}
end

local function setCircuit(key, circuit)
    local hadCircuit = circuits[key] ~= nil
    local hasCircuit = circuit ~= nil
    if hadCircuit ~= hasCircuit then
        circuitCount = circuitCount + (hasCircuit and 1 or -1)
    end
    circuits[key] = circuit
end

local function setFailureCount(entry, count)
    local hadFailure = (entry.consecutiveFailures or 0) > 0
    local hasFailure = count > 0
    if hadFailure ~= hasFailure then
        failingCount = failingCount + (hasFailure and 1 or -1)
    end
    entry.consecutiveFailures = count
end

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
        rememberReportLine(subsystem, entry.lastMessage)
        local suffix = entry.lastDetail and (": " .. entry.lastDetail) or ""
        print("[SurvivorCompanion][" .. key .. "] " .. entry.lastMessage .. suffix)
    end

    return entry.count
end

local function openCircuit(subsystem, companionId, entry, current)
    local key = keyFor(subsystem, companionId)
    local resetMs = math.max(1,
        tonumber(SC.Config.get("runtime", "circuitBreakerResetMs")) or 30000)
    setCircuit(key, {
        state = "open",
        openedAt = current,
        retryAt = current + resetMs,
        manual = false,
    })
    entry.openedAt = current
    entry.retryAt = current + resetMs
end

local function recordFailure(subsystem, companionId, message, detail)
    diagnostics.report(subsystem, companionId, message, detail)
    local key = keyFor(subsystem, companionId)
    local entry = entries[key]
    setFailureCount(entry, (entry.consecutiveFailures or 0) + 1)
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
    if circuitCount > 0 and diagnostics.isDisabled(subsystem, companionId) then
        return false, "circuit open", "circuit_skip"
    end

    local results = SC.Call.pack(pcall(callback, ...))
    if not results[1] then
        recordFailure(subsystem, companionId, "subsystem exception", results[2])
        return false, results[2]
    end

    if circuitCount == 0 and failingCount == 0 then
        return true, SC.Call.unpack(results, 2, results.n)
    end

    local key = keyFor(subsystem, companionId)
    local entry = entries[key]
    local circuit = circuits[key]
    if entry ~= nil then
        if (entry.consecutiveFailures or 0) > 0 or circuit ~= nil then
            entry.recoveries = (entry.recoveries or 0) + 1
            entry.lastRecoveredAt = nowMs()
        end
        setFailureCount(entry, 0)
        entry.retryAt = nil
    end
    setCircuit(key, nil)

    return true, SC.Call.unpack(results, 2, results.n)
end

function diagnostics.isDisabled(subsystem, companionId)
    if circuitCount == 0 then return false end
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
    setCircuit(key, {
        state = "open",
        openedAt = nowMs(),
        retryAt = math.huge,
        manual = true,
        reason = tostring(reason or "subsystem disabled"),
    })
end

function diagnostics.retry(subsystem, companionId)
    local key = keyFor(subsystem, companionId)
    local entry = entries[key]
    if entry ~= nil then
        setFailureCount(entry, 0)
        entry.retryAt = nil
    end
    setCircuit(key, nil)
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
        end
        local state = circuit and circuit.state or "closed"
        if circuit ~= nil and not disabled and circuit.manual ~= true then state = "half_open" end
        copy[key] = {
            count = entry.count,
            lastMessage = entry.lastMessage,
            lastDetail = entry.lastDetail,
            lastAt = entry.lastAt,
            consecutiveFailures = entry.consecutiveFailures or 0,
            recoveries = entry.recoveries or 0,
            lastRecoveredAt = entry.lastRecoveredAt,
            state = state,
            disabled = disabled,
            retryAt = circuit and circuit.retryAt or nil,
            manual = circuit and circuit.manual == true or false,
        }
    end
    return copy
end

function diagnostics.reset()
    diagnostics.clearReportLines()
    entries = {}
    circuits = {}
    circuitCount = 0
    failingCount = 0
end

return diagnostics
