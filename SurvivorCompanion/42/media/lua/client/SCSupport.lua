-- SPDX-License-Identifier: MIT

require "SCNamespace"
require "SCConfig"
require "SCDiagnostics"
require "SCActor"
require "SCRegistry"
require "SCScheduler"
require "SCPerformance"

local SC = SurvivorCompanion
SC.Support = SC.Support or {}

local support = SC.Support

local function safeCall(callback, fallback)
    if type(callback) ~= "function" then return fallback end
    local ok, value = pcall(callback)
    if not ok or value == nil then return fallback end
    return value
end

local function gameVersion()
    return tostring(safeCall(function()
        local core = getCore and getCore() or nil
        if core ~= nil and type(core.getVersionNumber) == "function" then
            return core:getVersionNumber()
        end
        return nil
    end, SC.Identity.gameVersion or "unknown"))
end

local function recordCount()
    local records = safeCall(function()
        return SC.Registry and SC.Registry.records and SC.Registry.records() or nil
    end, {})
    return type(records) == "table" and #records or 0
end

local function factionCount()
    local groups = safeCall(function()
        return SC.Factions and SC.Factions.all and SC.Factions.all() or nil
    end, {})
    return type(groups) == "table" and #groups or 0
end

local function diagnosticSummary()
    local snapshot = safeCall(function()
        return SC.Diagnostics.snapshot()
    end, {})
    local result = {
        keys = {},
        entries = snapshot,
        reports = 0,
        open = 0,
        recoveries = 0,
    }
    for key, entry in pairs(snapshot) do
        result.keys[#result.keys + 1] = key
        result.reports = result.reports + (tonumber(entry.count) or 0)
        result.recoveries = result.recoveries + (tonumber(entry.recoveries) or 0)
        if entry.state == "open" or entry.state == "half_open" then
            result.open = result.open + 1
        end
    end
    table.sort(result.keys)
    return result
end

local function bridgeAdvice(status)
    local code = status and status.code or "unavailable"
    if code == "ready" then return "Native companion bridge is ready." end
    if code == "test_provider" then return "A test-only actor provider is active." end
    if code == "experimental_provider" then
        return "An experimental actor provider is active; do not use this save for release testing."
    end
    if code == "unsupported_multiplayer" then
        return "Living Fellows currently supports single-player only."
    end
    if code == "bridge_missing" then
        return "Enable ZombieBuddy 2.3.3 or newer and Living Fellows, then restart the game."
    end
    if code == "protocol_mismatch" then
        return "The installed native bootstrap does not match this Living Fellows release. Update both mods and restart."
    end
    return "The native bridge did not become ready. Restart once, then copy this report if the problem remains."
end

function support.snapshot(force)
    local bridge = safeCall(function()
        return SC.Actor.bridgeStatus(force == true)
    end, {
        ready = false,
        provider = nil,
        expectedProtocol = SC.Identity.bridgeProtocol,
        code = "unavailable",
        reason = "SC.Actor.bridgeStatus is unavailable",
    })
    bridge.advice = bridgeAdvice(bridge)
    return {
        release = tostring(SC.Identity.release or "unknown"),
        gameVersion = gameVersion(),
        expectedGameVersion = tostring(SC.Identity.gameVersion or "unknown"),
        saveSchema = tonumber(SC.Identity.saveSchema) or 0,
        runtimeActive = SC.State and SC.State.active == true or false,
        disabledReason = SC.State and SC.State.disabledReason or nil,
        companions = recordCount(),
        factions = factionCount(),
        bridge = bridge,
        scheduler = safeCall(function()
            return SC.Scheduler.getStats()
        end, {}),
        performance = safeCall(function()
            return SC.Performance.snapshot()
        end, {}),
        diagnostics = diagnosticSummary(),
        sandbox = safeCall(function()
            return SC.Config.sandboxSnapshot()
        end, {}),
    }
end

local function booleanText(value)
    return value == true and "yes" or "no"
end

function support.summary(force)
    local data = support.snapshot(force == true)
    local bridge = data.bridge or {}
    local scheduler = data.scheduler or {}
    local diagnostics = data.diagnostics or {}
    local performance = data.performance or {}
    local lines = {
        "Living Fellows support report",
        "Release: " .. data.release,
        "Game build: " .. data.gameVersion .. " (target " .. data.expectedGameVersion .. ")",
        "Save schema: " .. tostring(data.saveSchema),
        "Runtime active: " .. booleanText(data.runtimeActive),
        "Bridge: " .. tostring(bridge.code or "unknown"),
        "Bridge provider: " .. tostring(bridge.provider or "none"),
        "Bridge protocol: " .. tostring(bridge.observedProtocol or "unavailable")
            .. " (expected " .. tostring(bridge.expectedProtocol or "unknown") .. ")",
        "Bridge detail: " .. tostring(bridge.reason or "none"),
        "Suggested action: " .. tostring(bridge.advice or "none"),
        "Active companions: " .. tostring(data.companions),
        "Known households: " .. tostring(data.factions),
        "Scheduler: " .. tostring(scheduler.taskCount or 0) .. " tasks, "
            .. tostring(scheduler.exceptions or 0) .. " exceptions, "
            .. tostring(scheduler.deferredFrames or 0) .. " deferred frames",
        string.format("AI performance: load %d, frame p95 %.2f ms, max %.2f ms, %d yielded jobs",
            tonumber(performance.loadLevel) or 0,
            tonumber(performance.p95FrameMs) or 0,
            tonumber(performance.maxFrameMs) or 0,
            tonumber(performance.yieldedJobs) or 0),
        "Diagnostics: " .. tostring(diagnostics.reports or 0) .. " reports, "
            .. tostring(diagnostics.open or 0) .. " open circuits, "
            .. tostring(diagnostics.recoveries or 0) .. " recoveries",
    }
    if data.disabledReason ~= nil then
        lines[#lines + 1] = "Runtime disabled reason: " .. tostring(data.disabledReason)
    end
    for _, key in ipairs(diagnostics.keys or {}) do
        local entry = diagnostics.entries[key] or {}
        lines[#lines + 1] = "Diagnostic " .. key .. ": "
            .. tostring(entry.state or "closed") .. ", count "
            .. tostring(entry.count or 0) .. ", last "
            .. tostring(entry.lastMessage or "none")
    end
    for _, metric in ipairs(performance.topSystems or {}) do
        lines[#lines + 1] = string.format("Performance %s: p95 %.2f ms, max %.2f ms, yields %d",
            tostring(metric.label or metric.key), tonumber(metric.p95Ms) or 0,
            tonumber(metric.maxMs) or 0, tonumber(metric.yielded) or 0)
    end
    return table.concat(lines, "\n"), data
end

function support.copySummary(force)
    local report = support.summary(force == true)
    if Clipboard == nil or type(Clipboard.setClipboard) ~= "function" then
        return false, "The game clipboard service is unavailable.", report
    end
    local ok, reason = pcall(Clipboard.setClipboard, report)
    if not ok then return false, tostring(reason), report end
    return true, "Support report copied to the clipboard.", report
end

function support.copyPerformance()
    if not SC.Performance or type(SC.Performance.summary) ~= "function" then
        return false, "AI performance diagnostics are unavailable."
    end
    local report = SC.Performance.summary()
    if Clipboard == nil or type(Clipboard.setClipboard) ~= "function" then
        return false, "The game clipboard service is unavailable.", report
    end
    local ok, reason = pcall(Clipboard.setClipboard, report)
    if not ok then return false, tostring(reason), report end
    return true, "AI performance report copied to the clipboard.", report
end

function support.resetPerformance()
    if not SC.Performance or type(SC.Performance.reset) ~= "function" then
        return false, "AI performance diagnostics are unavailable."
    end
    SC.Performance.reset()
    return true, "AI performance samples reset."
end

function support.copyMovement(actor)
    if not SC.Locomotion or type(SC.Locomotion.report) ~= "function" then
        return false, "Movement diagnostics are unavailable."
    end
    if actor == nil then return false, "Select a companion first." end
    local report = SC.Locomotion.report(actor)
    if Clipboard == nil or type(Clipboard.setClipboard) ~= "function" then
        return false, "The game clipboard service is unavailable.", report
    end
    local ok, reason = pcall(Clipboard.setClipboard, report)
    if not ok then return false, tostring(reason), report end
    return true, "Movement report copied to the clipboard.", report
end

function support.clearMovement(actor)
    if not SC.Locomotion or type(SC.Locomotion.reset) ~= "function" then
        return false, "Movement diagnostics are unavailable."
    end
    if actor == nil then return false, "Select a companion first." end
    SC.Locomotion.reset(actor)
    return true, "Movement history cleared."
end

function support.retryFailures()
    local diagnostics = diagnosticSummary()
    local retried = 0
    for _, key in ipairs(diagnostics.keys) do
        local entry = diagnostics.entries[key]
        if entry and (entry.state == "open" or entry.state == "half_open") then
            local subsystem, companionId = string.match(key, "^([^:]+):(.*)$")
            if subsystem ~= nil then
                if companionId == "global" then companionId = nil end
                SC.Diagnostics.retry(subsystem, companionId)
                retried = retried + 1
            end
        end
    end
    if SC.Actor and type(SC.Actor.checkBridge) == "function" then
        SC.Actor.checkBridge(true)
    end
    return true, retried
end

return support
