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
    check(SC.Scheduler.register("bad-lane", 1, 1, function() end,
            { lane = "urgent-ish" }) == false,
        "scheduler rejects undocumented lane names")

    local firstCallback = function() end
    SC.Scheduler.register("replace-test", 10, 10, firstCallback, { lane = "normal" })
    clock = clock + 10
    SC.Scheduler.tick()
    local dueBefore
    for _, task in ipairs(SC.Scheduler.getStats().tasks) do
        if task.name == "replace-test" then dueBefore = task.nextDue end
    end
    SC.Scheduler.register("replace-test", 100, 10, function() end, { lane = "normal" })
    local dueAfter
    for _, task in ipairs(SC.Scheduler.getStats().tasks) do
        if task.name == "replace-test" then dueAfter = task.nextDue end
    end
    check(dueBefore ~= nil and dueAfter == nil,
        "re-registering changed scheduling parameters resets stale nextDue")
end

do
    SC.Scheduler.reset(true)
    SC.Diagnostics.reset()
    SC.Diagnostics.disable("skip-task", nil, "fixture circuit")
    SC.Scheduler.register("skip-task", 1, 80, function() error("must not run") end,
        { lane = "critical" })
    SC.Scheduler.register("reported-task", 1, 70,
        function() return false, "reported failure" end,
        { lane = "critical", reportFailure = true })
    SC.Scheduler.register("exception-task", 1, 60,
        function() error("fixture exception") end, { lane = "critical" })
    SC.Scheduler.tick()
    clock = clock + 1
    SC.Scheduler.tick()
    local schedulerStats = SC.Scheduler.getStats()
    check(schedulerStats.circuitSkips == 1 and schedulerStats.exceptions == 1
            and schedulerStats.reportedFailures == 1,
        "scheduler separates circuit skips, exceptions, and reported failures")

    SC.Diagnostics.reset()
    SC_TEST_CLOCK = 1000
    for _ = 1, 3 do
        SC.Diagnostics.guard("snapshot-test", nil, function() error("fixture") end)
    end
    SC_TEST_CLOCK = 40000
    local afterExpiry = SC.Diagnostics.snapshot()["snapshot-test:global"]
    SC_TEST_CLOCK = 2000
    local beforeExpiry = SC.Diagnostics.snapshot()["snapshot-test:global"]
    check(afterExpiry.state == "half_open" and beforeExpiry.state == "open",
        "diagnostic snapshot derives half-open state without mutating the circuit")
    SC.Diagnostics.reset()
    SC_TEST_CLOCK = 1000
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

SC.Performance.reset()
local namespaceLimit = SC.Config.get("performanceCacheNamespaceLimit")
local totalLimit = SC.Config.get("performanceCacheTotalLimit")
for index = 1, totalLimit * 8 do
    SC.Performance.cachePut("perception-square", "dynamic:" .. tostring(index), index,
        10, clock)
end
local cacheStats = SC.Performance.cacheStats()
check(cacheStats.entries <= totalLimit
        and cacheStats.namespaces["perception-square"] <= namespaceLimit
        and cacheStats.evictions > 0,
    "dynamic perception-square cache stays within namespace and total caps")
check(cacheStats.queueTokens == cacheStats.entries
        and cacheStats.trackedQueueTokens == cacheStats.entries
        and cacheStats.namespaceQueueTokens == cacheStats.entries
        and cacheStats.queueTombstones == 0
        and cacheStats.namespaceQueueTombstones == 0
        and cacheStats.queueCycle == false,
    "namespace eviction unlinks every physical global and namespace queue token")

SC.Performance.reset()
local churnNamespaces = math.ceil((totalLimit * 4) / namespaceLimit) + 1
for index = 1, totalLimit * 4 do
    local namespace = "global-churn:" .. tostring((index - 1) % churnNamespaces)
    SC.Performance.cachePut(namespace, "dynamic:" .. tostring(index), index, 10, clock)
end
cacheStats = SC.Performance.cacheStats()
check(cacheStats.entries == totalLimit and cacheStats.evictions > 0
        and cacheStats.queueTokens == cacheStats.entries
        and cacheStats.trackedQueueTokens == cacheStats.entries
        and cacheStats.namespaceQueueTokens == cacheStats.entries
        and cacheStats.queueTombstones == 0
        and cacheStats.namespaceQueueTombstones == 0
        and cacheStats.queueCycle == false,
    "global eviction unlinks physical tokens from every namespace queue")

SC.Performance.sweepCache(clock + 1000, totalLimit)
cacheStats = SC.Performance.cacheStats()
check(cacheStats.entries == 0 and cacheStats.expired > 0
        and cacheStats.queueTokens == 0 and cacheStats.trackedQueueTokens == 0
        and cacheStats.namespaceQueueTokens == 0,
    "bounded incremental sweep removes expired dynamic cache entries")

SC.Performance._setClock(nil)
SC.Scheduler._setClock(nil)
print("PERFORMANCE_SCALABILITY_PASS checks=" .. tostring(checks)
    .. " companions=1,4,8,16 critical-latency=preserved")
