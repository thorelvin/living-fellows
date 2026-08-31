-- SPDX-License-Identifier: MIT

local checks = 0
local function check(value, message)
    checks = checks + 1
    assert(value, "performance check " .. tostring(checks) .. " failed: " .. tostring(message))
end

local SC = SurvivorCompanion
check(type(SC.Performance) == "table", "performance service is loaded")

local clock = 0
SC.Performance._setClock(function() return clock end)
SC.Scheduler._setClock(function() return clock end)

do
    SC.Scheduler.reset(true)
    local order = {}
    SC.Scheduler.register("background-test", 1, 1,
        function() order[#order + 1] = "background" end, { lane = "background" })
    SC.Scheduler.register("critical-test", 1, 100,
        function() order[#order + 1] = "critical" end, { lane = "critical" })
    SC.Scheduler.tick()
    clock = clock + 1
    SC.Scheduler.tick()
    check(order[1] == "critical" and order[2] == "background",
        "scheduler always runs combat/survival lanes before background work")
end

for _, companionCount in ipairs({ 1, 4, 8, 16 }) do
    SC.Performance.reset()
    local progress = {}
    for index = 1, companionCount do progress[index] = 0 end

    -- Production decisions rotate through actors. This simulation proves that
    -- the shared quota remains bounded while every actor receives work.
    for frame = 1, companionCount * 4 do
        SC.Performance.beginFrame(2, clock)
        local actorIndex = ((frame - 1) % companionCount) + 1
        local granted = SC.Performance.claimUnits("perception", 240, false)
        progress[actorIndex] = progress[actorIndex] + granted
        SC.Performance.record("scale.perception", "actor-" .. tostring(actorIndex),
            1, granted, false)
        clock = clock + 1
        SC.Performance.endFrame(1, false)
    end
    for index = 1, companionCount do
        check(progress[index] > 0,
            tostring(companionCount) .. " companion rotation must not starve actor " .. tostring(index))
    end

    SC.Performance.beginFrame(2, clock)
    local shared = 0
    for _ = 1, companionCount do
        shared = shared + SC.Performance.claimUnits("navigation", 220, false)
    end
    check(shared <= SC.Config.get("performanceNavigationNodesPerFrame"),
        tostring(companionCount) .. " companions share one navigation quota")
    clock = clock + 1
    SC.Performance.endFrame(1, false)

    local snapshot = SC.Performance.snapshot()
    check(snapshot.frames == companionCount * 4 + 1 and snapshot.p95FrameMs <= 2,
        tostring(companionCount) .. " companion nominal profile stays inside budget")
end

SC.Performance.reset()
for _ = 1, 360 do
    SC.Performance.beginFrame(2, clock)
    clock = clock + 5
    SC.Performance.endFrame(5, true)
end
check(SC.Performance.loadLevel() >= 2, "sustained overload raises adaptive load shedding")
check(SC.Performance.intervalScale("critical") == 1,
    "combat and survival lanes retain their original cadence under load")
check(SC.Performance.intervalScale("background") > 1,
    "background work slows down under sustained load")

SC.Performance.record("perception", "actor-profile", 1, 72, false)
SC.Performance.markYield("navigation", "actor-profile", 64)
local report, snapshot = SC.Performance.summary()
check(type(report) == "string" and string.find(report, "Top systems", 1, true) ~= nil,
    "performance report is exportable")
check(#snapshot.topSystems > 0 and #snapshot.topActors > 0,
    "profiler exposes expensive systems and companions")
check(#snapshot.topActors == 1 and snapshot.topActors[1].key == "actor-profile"
        and snapshot.topActors[1].yielded == 1,
    "per-companion metrics aggregate work and yields across subsystems")

SC.Performance.cachePut("test", "square", "cached", 75, clock)
check(SC.Performance.cacheGet("test", "square", clock + 50) == "cached",
    "short-lived shared cache returns fresh data")
check(SC.Performance.cacheGet("test", "square", clock + 100) == nil,
    "short-lived shared cache expires stale data")

SC.Performance._setClock(nil)
SC.Scheduler._setClock(nil)
print("PERFORMANCE_SCALABILITY_PASS checks=" .. tostring(checks)
    .. " companions=1,4,8,16 critical-latency=preserved")
