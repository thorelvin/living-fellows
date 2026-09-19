-- SPDX-License-Identifier: MIT
--
-- A small, disableable combat phase tracer.
--
-- The thing worth watching during a playtest is not any single event but a
-- *rate*: CB-01's symptom is that an attack the engine should be sustaining
-- keeps being re-entered, which reads as a stutter on screen. One log line per
-- entry would bury that in noise, so this module counts events and reports a
-- bounded summary on an interval, plus an immediate line the moment a rate
-- crosses the threshold that means "this is the hiccup".
--
-- Off unless `combatTraceEnabled` is set, so public builds carry no cost
-- beyond a config read. Every counter is a plain integer and every report is
-- bounded, so leaving it on during a long session cannot grow without limit.

if not SurvivorCompanion or not SurvivorCompanion.Call then
    if type(require) == "function" then pcall(require, "SCCall") end
end

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion

SC.CombatTrace = SC.CombatTrace or {}
local Trace = SC.CombatTrace

local function config(key, fallback)
    if SC.Config == nil or type(SC.Config.get) ~= "function" then return fallback end
    local value = SC.Config.get(key)
    if value == nil then return fallback end
    return value
end

local function enabled()
    return config("combatTraceEnabled", false) == true
end

local function nowMs()
    if SC.GameplayUtil and type(SC.GameplayUtil.nowMs) == "function" then
        return SC.GameplayUtil.nowMs()
    end
    return 0
end

local function report(message)
    if SC.Diagnostics and type(SC.Diagnostics.report) == "function" then
        pcall(SC.Diagnostics.report, "combat-trace", nil, message)
        return
    end
    if type(print) == "function" then print("[SurvivorCompanion/combat-trace] " .. message) end
end

-- One window's worth of counts. Reset wholesale each interval so nothing here
-- accumulates across a session.
local window = {
    startedAt = 0, entries = 0, started = 0, sustained = 0,
    dropped = 0, peakPairs = 0, refusals = {}, refusalKinds = 0,
}

local function resetWindow(current)
    window.startedAt = current
    window.entries, window.started = 0, 0
    window.sustained, window.dropped, window.peakPairs = 0, 0, 0
    window.refusals, window.refusalKinds = {}, 0
end

--- Record an attack-entry request. `started` is true when the graph actually
--- entered the attack state, as opposed to reporting one already active.
function Trace.entry(zombie, actor, current, reason, started)
    if not enabled() then return end
    current = tonumber(current) or nowMs()
    if window.startedAt == 0 then resetWindow(current) end
    window.entries = window.entries + 1
    if started == true then window.started = window.started + 1 end
    if type(reason) == "string" and reason ~= "attack_started"
        and reason ~= "attack_active" then
        if window.refusals[reason] == nil then
            -- Bounded: a runaway variety of reasons cannot grow this table.
            if window.refusalKinds < 12 then
                window.refusalKinds = window.refusalKinds + 1
                window.refusals[reason] = 0
            end
        end
        if window.refusals[reason] ~= nil then
            window.refusals[reason] = window.refusals[reason] + 1
        end
    end
end

--- Record one pass of the per-frame continuation service.
function Trace.pulse(current, sustained, dropped, livePairs)
    if not enabled() then return end
    current = tonumber(current) or nowMs()
    if window.startedAt == 0 then resetWindow(current) end
    window.sustained = window.sustained + (tonumber(sustained) or 0)
    window.dropped = window.dropped + (tonumber(dropped) or 0)
    local live = tonumber(livePairs) or 0
    if live > window.peakPairs then window.peakPairs = live end

    local interval = tonumber(config("combatTraceIntervalMs", 2000)) or 2000
    local elapsed = current - window.startedAt
    if elapsed < interval then return end

    -- Entries per second is the number that matters. A sustained attack should
    -- need one entry and then nothing: a rate above the threshold means the
    -- graph is dropping the attack and being asked to restart it, which is the
    -- stutter CB-01 describes.
    local seconds = elapsed / 1000
    local entryRate = seconds > 0 and (window.entries / seconds) or 0
    local threshold = tonumber(config("combatTraceReentryPerSecond", 3)) or 3
    if window.entries > 0 or window.sustained > 0 or window.dropped > 0 then
        local detail = ""
        for reason, count in pairs(window.refusals) do
            detail = detail .. " " .. reason .. "=" .. tostring(count)
        end
        report(string.format(
            "window=%dms pairs=%d sustained=%d dropped=%d entries=%d started=%d"
            .. " entries/s=%.1f%s%s",
            elapsed, window.peakPairs, window.sustained, window.dropped,
            window.entries, window.started, entryRate,
            detail,
            entryRate > threshold and "  <-- RE-ENTRY STUTTER" or ""))
    end
    resetWindow(current)
end

--- Plain-language view for the support tab and for tests.
function Trace.snapshot()
    return {
        enabled = enabled(),
        entries = window.entries, started = window.started,
        sustained = window.sustained, dropped = window.dropped,
        peakPairs = window.peakPairs,
    }
end

function Trace.reset()
    resetWindow(0)
    window.startedAt = 0
    return true
end

return Trace
