-- SPDX-License-Identifier: MIT
--
-- Drives the real SCRuntime decision scheduler (review 2.1/2.2/2.3): one callback
-- services several actors, an emergency (critical) lane is serviced first and
-- often, and neither lane can starve the other. Loads the production SCRuntime and
-- the real SCScheduler (for per-actor dueFor cadence), stubs the decision/targeting
-- surface with counting test doubles, and calls the exposed decisionTask seam with
-- an explicit clock so timing is deterministic.

local SC = SurvivorCompanion
local checks = 0
local function check(value, message)
    checks = checks + 1
    assert(value, "decision-scheduler check " .. tostring(checks) .. " failed: " .. tostring(message))
end

local decisionTask = SC.Runtime._decisionTaskForTests
local recordIsCritical = SC.Runtime._recordIsCriticalForTests
check(type(decisionTask) == "function", "decisionTask test seam is exposed")
check(type(recordIsCritical) == "function", "recordIsCritical test seam is exposed")

-- Counting test doubles for the per-actor service path. Every serviced actor --
-- whether it runs a normal decision or is skipped as grabbed -- falls through to
-- the attack resolve, so counting there catches both branches.
local services = {}
local grabbed = {}
SC.Decision.update = function() return true, "serviced" end
SC.ZombieTargeting = { scan = function() return true, "scanned", {} end }
SC.ZombieAttack = {
    isGrabbed = function(actor) return actor ~= nil and grabbed[actor] == true end,
    resolve = function(actor)
        if actor ~= nil then services[actor.id] = (services[actor.id] or 0) + 1 end
        return true, "resolved", {}
    end,
}
SC.Actor = type(SC.Actor) == "table" and SC.Actor or {}
SC.Actor.stop = function() return true end

local records = {}
SC.Registry.records = function() return records end

local function makeRecord(index, runtime)
    local actor = { id = "sc-" .. tostring(index) }
    return { id = "sc-" .. tostring(index), actor = actor, runtime = runtime or {} }
end

local function uniqueServiced()
    local count = 0
    for _, value in pairs(services) do
        if value > 0 then count = count + 1 end
    end
    return count
end

-- Prime the per-actor dueFor clocks (their first read carries a stagger offset in
-- [0, interval)), then jump past the largest decision interval so every actor is
-- due, giving each scenario a deterministic starting point.
local function prime(baseTime)
    decisionTask(baseTime, 1000000)
    services = {}
    return baseTime + 100
end

-- Scenario 1: the ordinary round-robin services several actors per callback (the
-- configured cap), not one, so reaction time stops scaling with party size.
do
    SC.Scheduler.reset(true)
    services = {}
    grabbed = {}
    records = {}
    for index = 1, 12 do records[index] = makeRecord(index) end
    local base = prime(500000)

    services = {}
    decisionTask(base, 1000000)
    check(uniqueServiced() == SC.Config.get("decisionOrdinaryPerTick")
            and uniqueServiced() == 3,
        "a single callback services exactly the ordinary cap (3), not 1 and not all 12")

    decisionTask(base + 1, 1000000)
    decisionTask(base + 2, 1000000)
    decisionTask(base + 3, 1000000)
    check(uniqueServiced() == 12,
        "four callbacks cover all 12 actors -- throughput is independent of party size (1/callback would need 12)")
end

-- Scenario 2: a grabbed (critical) actor is serviced by the critical lane on nearly
-- every callback while ordinary actors are still serviced -- the critical actor
-- does not starve the party.
do
    SC.Scheduler.reset(true)
    services = {}
    grabbed = {}
    records = {}
    for index = 1, 10 do records[index] = makeRecord(index) end
    grabbed[records[1].actor] = true
    local base = prime(700000)

    services = {}
    for step = 0, 4 do
        decisionTask(base + step * 50, 1000000)
    end
    check((services[records[1].id] or 0) >= 4,
        "a grabbed actor is serviced by the critical lane on nearly every callback")
    local ordinaryCovered = 0
    for index = 2, 10 do
        if (services[records[index].id] or 0) >= 1 then ordinaryCovered = ordinaryCovered + 1 end
    end
    check(ordinaryCovered == 9,
        "every ordinary actor is still serviced -- the critical actor does not starve the round-robin")
end

-- Scenario 3: when every actor is critical at once, one callback services exactly
-- criticalCap (6) via the critical lane plus ordinaryCap (3) via the round-robin =
-- 9 distinct actors. This bounds critical work per callback and proves the ordinary
-- lane still runs under critical saturation (starvation is capped both ways).
do
    SC.Scheduler.reset(true)
    services = {}
    grabbed = {}
    records = {}
    for index = 1, 14 do
        records[index] = makeRecord(index)
        grabbed[records[index].actor] = true
    end
    local base = prime(900000)

    services = {}
    decisionTask(base, 1000000)
    check(uniqueServiced() == SC.Config.get("decisionCriticalPerTick")
                + SC.Config.get("decisionOrdinaryPerTick")
            and uniqueServiced() == 9,
        "one callback services criticalCap(6) + ordinaryCap(3) = 9 distinct actors when all are critical")
end

-- Scenario 4: recordIsCritical classifies emergencies from cheap cached state
-- without depending on a fresh sensing pass.
do
    grabbed = {}
    check(recordIsCritical({ actor = { id = "a" },
        runtime = { senses = { current = { immediateCount = 1 } } } }) == true,
        "an immediate attacker marks the actor critical")
    check(recordIsCritical({ actor = { id = "b" },
        runtime = { senses = { current = { threatCount = 2 } } } }) == true,
        "a nearby threat marks the actor critical")
    check(recordIsCritical({ actor = { id = "c" }, runtime = { downed = true } }) == true,
        "a downed actor is critical")
    check(recordIsCritical({ actor = { id = "d" }, runtime = { needsRescue = true } }) == true,
        "an actor needing rescue is critical")
    local grabbedActor = { id = "e" }
    grabbed[grabbedActor] = true
    check(recordIsCritical({ actor = grabbedActor, runtime = {} }) == true,
        "a grabbed actor is critical from the live grab probe")
    check(recordIsCritical({ actor = { id = "f" },
        runtime = { senses = { current = { threatCount = 0, immediateCount = 0 } } } }) == false,
        "an actor with no threat, grab, or medical emergency stays ordinary")
end

-- Scenario 5: native schedule repair is a throttled integrity pulse (review 2.6),
-- not a per-frame roster scan, and a roster-size change forces it immediately.
do
    SC.Scheduler.reset(true)
    local productionTick = SC.Runtime._productionTickForTests
    check(type(productionTick) == "function", "productionTick test seam is exposed")
    local ensureCalls = 0
    SC.Registry.living = function() ensureCalls = ensureCalls + 1; return {} end
    SC.GameplayUtil = { call = function() return true end }
    records = {}
    for index = 1, 3 do records[index] = makeRecord(index) end

    local interval = SC.Config.get("scheduleRepairIntervalMs")
    local t = 1000
    ensureCalls = 0
    productionTick(t)
    check(ensureCalls == 1, "the first production tick repairs the schedule (roster went from none to three)")

    productionTick(t + 10)
    productionTick(t + 20)
    productionTick(t + 50)
    check(ensureCalls == 1, "schedule repair is throttled within the interval on a stable roster")

    productionTick(t + interval)
    check(ensureCalls == 2, "an integrity pulse repairs the schedule once the interval elapses")

    records[4] = makeRecord(4)
    productionTick(t + interval + 5)
    check(ensureCalls == 3, "a roster-size change forces an immediate schedule repair within the interval")
end

-- Scenario 6 (hardening): a messy roster -- a record with no id, an inactive
-- record, a dying record, plus valid actors -- is serviced safely. Only the valid
-- actors run, nothing crashes on the nil-key path, and the caps still hold.
do
    SC.Scheduler.reset(true)
    services = {}
    grabbed = {}
    records = {}
    records[1] = { id = nil, actor = { id = "noid" } }
    records[2] = makeRecord(2, { inactive = true })
    records[3] = makeRecord(3, { dying = true })
    records[4] = makeRecord(4)
    records[5] = makeRecord(5)
    local base = prime(1200000)

    services = {}
    decisionTask(base, 1000000)
    check(uniqueServiced() == 2
            and (services[records[4].id] or 0) >= 1
            and (services[records[5].id] or 0) >= 1
            and (services["noid"] or 0) == 0,
        "a roster with a missing id, an inactive, and a dying record services only the valid actors without crashing")
end

-- Scenario 7 (LF-03): the critical lane rotates so a permanently-critical actor
-- early in id order cannot starve later ones. With more critical actors than the
-- per-callback cap and the ordinary lane disabled (so it cannot mask the critical
-- rotation), successive callbacks must still cover every critical actor -- a
-- fixed-prefix scan would service only the first six forever.
do
    SC.Scheduler.reset(true)
    services = {}
    grabbed = {}
    records = {}
    for index = 1, 10 do
        records[index] = makeRecord(index)
        grabbed[records[index].actor] = true
    end
    local realGet = SC.Config.get
    SC.Config.get = function(section, key)
        if section == "decisionOrdinaryPerTick" then return 0 end
        return realGet(section, key)
    end
    local base = prime(1400000)
    services = {}
    for step = 0, 3 do
        decisionTask(base + step * 60, 1000000)
    end
    SC.Config.get = realGet
    local covered = 0
    for index = 1, 10 do
        if (services[records[index].id] or 0) >= 1 then covered = covered + 1 end
    end
    check(covered == 10,
        "the critical lane rotates so every critical actor is serviced across callbacks (no fixed-prefix starvation)")
end

-- Scenario 8 (R2-05): under sustained overload the critical lane can consume the
-- whole frame budget, but the ordinary lane must still get a reserved service so a
-- genuine ordinary actor is not starved indefinitely.
do
    SC.Scheduler.reset(true)
    services = {}
    grabbed = {}
    records = {}
    for index = 1, 8 do
        records[index] = makeRecord(index)
        grabbed[records[index].actor] = true
    end
    records[9] = makeRecord(9)
    -- Simulate a 1 ms cost per serviced actor through a controllable frame clock so
    -- a tight budget is actually reached mid-callback.
    local frameClock = 0
    local realTimestamp = getTimestampMs
    getTimestampMs = function() return frameClock end
    local realResolve = SC.ZombieAttack.resolve
    SC.ZombieAttack.resolve = function(actor)
        if actor ~= nil then services[actor.id] = (services[actor.id] or 0) + 1 end
        frameClock = frameClock + 1
        return true, "resolved", {}
    end
    local base = prime(1600000)
    services = {}
    for step = 0, 4 do
        decisionTask(base + step * 150, 4)
    end
    SC.ZombieAttack.resolve = realResolve
    getTimestampMs = realTimestamp
    check((services[records[9].id] or 0) >= 4,
        "the lone ordinary actor still receives its reserved service every callback even while the critical lane consumes the frame budget (no ordinary starvation)")
end

print("DECISION_SCHEDULER_PASS checks=" .. tostring(checks)
    .. " multi-actor=true critical-lane=true starvation-capped=true schedule-repair=pulsed"
    .. " hardened=true critical-fairness=rotating")
