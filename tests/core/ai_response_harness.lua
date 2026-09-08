-- SPDX-License-Identifier: MIT
--
-- Deterministic multi-companion response/load harness for the production
-- SCRuntime decision dispatcher. The synthetic costs model native roster access,
-- decision work, zombie targeting, and incoming-attack resolution without using
-- wall-clock timing, so regressions remain reproducible on every machine.

local SC = SurvivorCompanion
local checks = 0
local function check(value, message)
    checks = checks + 1
    assert(value, "ai-response check " .. tostring(checks)
        .. " failed: " .. tostring(message))
end

local dispatch = SC.Runtime._decisionTaskForTests
local resetDispatch = SC.Runtime._resetDecisionDispatchForTests
check(type(dispatch) == "function", "production decision dispatcher is exposed")
check(type(resetDispatch) == "function", "decision dispatcher reset seam is exposed")

local clock = 0
local logicalNow = 0
local records = {}
local registryCalls = 0
local grabbedCalls = 0
local serviceAt = {}
local recording = false

function getTimestampMs() return clock end
SC.Scheduler._setClock(function() return clock end)
SC.Performance._setClock(function() return clock end)

local function charge(amount)
    clock = clock + (tonumber(amount) or 0)
end

-- Registry.records() creates and sorts a fresh result in production. Charging a
-- deterministic size-dependent cost makes repeated materialization visible as a
-- budget/latency regression rather than relying on the host machine's wall clock.
SC.Registry.records = function()
    registryCalls = registryCalls + 1
    charge(0.03 + #records * 0.008)
    return records
end

SC.Decision.update = function(actor)
    charge(0.34)
    if recording and serviceAt[actor.id] == nil then
        serviceAt[actor.id] = logicalNow
    end
    return true, "serviced"
end

SC.ZombieTargeting = {
    scan = function()
        charge(0.04)
        return true, "scanned", {}
    end,
}
SC.ZombieAttack = {
    isGrabbed = function(actor)
        grabbedCalls = grabbedCalls + 1
        charge(0.002)
        return actor and actor.grabbed == true
    end,
    resolve = function()
        charge(0.04)
        return true, "resolved", {}
    end,
}
SC.Actor.stop = function() return true end

local function makeRoster(count, criticalCount)
    records = {}
    for index = 1, count do
        local actor = { id = "response-" .. tostring(index) }
        records[index] = {
            id = actor.id,
            actor = actor,
            runtime = {
                senses = { current = {
                    threats = {}, immediateAttackers = {},
                    threatCount = index <= (criticalCount or 0) and 1 or 0,
                    immediateCount = 0,
                    player = { danger = 0 },
                } },
            },
        }
    end
end

local function percentile(samples, ratio)
    local values = {}
    for index, value in ipairs(samples) do values[index] = value end
    table.sort(values)
    if #values == 0 then return 0 end
    return values[math.max(1, math.min(#values, math.ceil(#values * ratio)))]
end

local function resetScenario()
    SC.Scheduler.reset(true)
    resetDispatch()
    registryCalls = 0
    grabbedCalls = 0
    serviceAt = {}
    recording = false
end

local function primeOrdinary(base)
    clock = base - 200
    logicalNow = base - 200
    dispatch(logicalNow, 1000)
    registryCalls = 0
    grabbedCalls = 0
    serviceAt = {}
end

local function runUntilCovered(base, wanted, maximumFrames, budget)
    local samples = {}
    local frames = 0
    recording = true
    while frames < maximumFrames do
        logicalNow = base + frames * 16
        clock = logicalNow
        local started = clock
        dispatch(logicalNow, budget or 2)
        samples[#samples + 1] = clock - started
        frames = frames + 1
        local covered = 0
        for _, record in ipairs(records) do
            if wanted(record) and serviceAt[record.id] ~= nil then covered = covered + 1 end
        end
        local target = 0
        for _, record in ipairs(records) do if wanted(record) then target = target + 1 end end
        if covered == target then break end
    end
    recording = false
    return frames, samples
end

local function maximumResponse(base, wanted)
    local maximum = 0
    for _, record in ipairs(records) do
        if wanted(record) then
            local at = serviceAt[record.id]
            if at == nil then return math.huge end
            maximum = math.max(maximum, at - base)
        end
    end
    return maximum
end

local profileLines = {}
for _, companionCount in ipairs({ 1, 4, 8, 16 }) do
    resetScenario()
    makeRoster(companionCount, 0)
    local base = 100000 + companionCount * 1000
    primeOrdinary(base)
    local frames, samples = runUntilCovered(base, function() return true end, 12, 2)
    local response = maximumResponse(base, function() return true end)
    local p95 = percentile(samples, 0.95)
    check(response <= 96,
        tostring(companionCount) .. " ordinary companions respond within 96 ms")
    check(p95 <= 2,
        tostring(companionCount) .. " ordinary dispatch p95 stays inside the 2 ms budget")
    check(registryCalls == frames,
        tostring(companionCount) .. " companions materialize the sorted registry exactly once per callback")
    profileLines[#profileLines + 1] = string.format(
        "ordinary:%d max-response=%.0fms p95=%.3fms frames=%d registry=%d",
        companionCount, response, p95, frames, registryCalls)
end

-- A newly observed emergency must bypass the critical cadence's initial hash
-- stagger. This is the fastest path and catches a subtle 0-49 ms first-response
-- delay which ordinary cadence tests cannot see.
resetScenario()
makeRoster(1, 1)
local criticalBase = 300000
local criticalFrames, criticalSamples = runUntilCovered(criticalBase,
    function() return true end, 4, 2)
check(maximumResponse(criticalBase, function() return true end) == 0,
    "a newly critical companion is serviced in the discovery callback")
check(registryCalls == criticalFrames,
    "critical entry still uses one sorted registry snapshot per callback")

-- Clear the emergency for one callback, then reintroduce it well before the
-- existing 50 ms critical clock can be due. Re-entry must also bypass that old
-- cadence instead of treating the actor as continuously critical.
records[1].runtime.senses.current.threatCount = 0
logicalNow = criticalBase + 1
clock = logicalNow
dispatch(logicalNow, 2)
records[1].runtime.senses.current.threatCount = 1
serviceAt = {}
recording = true
logicalNow = criticalBase + 2
clock = logicalNow
dispatch(logicalNow, 2)
recording = false
check(serviceAt[records[1].id] == logicalNow,
    "a companion re-entering critical state responds immediately before its old cadence is due")

-- Saturate the emergency lane with a large party. Coarse, non-preemptible actor
-- service may finish just beyond 2 ms, but all 16 actors must rotate through
-- quickly and callback p95 must remain tightly bounded.
resetScenario()
makeRoster(16, 16)
criticalBase = 400000
criticalFrames, criticalSamples = runUntilCovered(criticalBase,
    function() return true end, 8, 2)
local criticalResponse = maximumResponse(criticalBase, function() return true end)
local criticalP95 = percentile(criticalSamples, 0.95)
check(criticalResponse <= 48,
    "16 simultaneous emergencies all receive service within 48 ms")
check(criticalP95 <= 2.5,
    "saturated critical dispatch has a bounded 2.5 ms p95")
check(registryCalls == criticalFrames,
    "critical saturation never rematerializes the registry inside a callback")
check(grabbedCalls <= criticalFrames
        * (#records + SC.Config.get("decisionCriticalPerTick")),
    "critical classification is cached per actor within each callback")
profileLines[#profileLines + 1] = string.format(
    "critical:16 max-response=%.0fms p95=%.3fms frames=%d registry=%d",
    criticalResponse, criticalP95, criticalFrames, registryCalls)

-- Mixed pressure: eight threatened actors consume the critical budget while the
-- ordinary reserve must still get the remaining eight moving. Prime only the
-- ordinary clocks, then introduce danger at the measurement boundary.
resetScenario()
makeRoster(16, 0)
local mixedBase = 500000
primeOrdinary(mixedBase)
for index = 1, 8 do records[index].runtime.senses.current.threatCount = 1 end
local mixedFrames, mixedSamples = runUntilCovered(mixedBase,
    function(record) return tonumber(string.match(record.id, "(%d+)$")) > 8 end,
    12, 2)
local ordinaryMixedResponse = maximumResponse(mixedBase,
    function(record) return tonumber(string.match(record.id, "(%d+)$")) > 8 end)
check(ordinaryMixedResponse <= 112,
    "ordinary companions remain responsive during critical saturation")
check(registryCalls == mixedFrames,
    "mixed dispatch uses one roster snapshot per callback")
profileLines[#profileLines + 1] = string.format(
    "mixed:8+8 ordinary-max=%.0fms p95=%.3fms frames=%d registry=%d",
    ordinaryMixedResponse, percentile(mixedSamples, 0.95), mixedFrames, registryCalls)

SC.Performance._setClock(nil)
SC.Scheduler._setClock(nil)

SC_TEST_REPORT = "AI_RESPONSE_PASS checks=" .. tostring(checks)
    .. " profiles=" .. table.concat(profileLines, " | ")
