-- SPDX-License-Identifier: MIT

if type(require) == "function" then
    pcall(require, "SCNamespace")
    pcall(require, "SCCall")
    pcall(require, "SCConfig")
end

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.Performance = SC.Performance or {}

local Performance = SC.Performance
local clockOverride = nil
local frame = nil
local frameSequence = 0
local systems = {}
local actors = {}
local frameSamples = {}
local cache = {}
local cacheQueue = {}
local cacheQueueHead = 1
local cacheQueueTail = 0
local cacheSerial = 0
local cacheEntries = 0
local loadLevel = 0
local lastLoadChangeFrame = 0
local totals = {
    frames = 0,
    overBudgetFrames = 0,
    deferredFrames = 0,
    yieldedJobs = 0,
    cacheHits = 0,
    cacheMisses = 0,
    cacheEvictions = 0,
    cacheExpired = 0,
}

local quotaKeys = {
    perception = "performancePerceptionUnitsPerFrame",
    navigation = "performanceNavigationNodesPerFrame",
    scavengeSquares = "performanceScavengeSquaresPerFrame",
    scavengeContainers = "performanceScavengeContainersPerFrame",
    factionSamples = "performanceFactionSamplesPerFrame",
}

local function nowMs()
    if clockOverride ~= nil then return tonumber(clockOverride()) or 0 end
    if type(getTimestampMs) == "function" then
        local ok, value = pcall(getTimestampMs)
        local numeric = ok and tonumber(value) or nil
        if numeric ~= nil then return numeric end
    end
    return math.floor((os.clock and os.clock() or 0) * 1000)
end

local function configured(key, fallback)
    local value = SC.Config and type(SC.Config.get) == "function" and SC.Config.get(key) or nil
    value = tonumber(value)
    return value ~= nil and value or fallback
end

local function cacheBucket(name)
    local bucket = cache[name]
    if bucket == nil then
        bucket = { entries = {}, queue = {}, head = 1, tail = 0, count = 0 }
        cache[name] = bucket
    end
    return bucket
end

local function removeCacheEntry(namespace, key, serial, expired)
    local bucket = cache[namespace]
    local entry = bucket and bucket.entries[key] or nil
    if entry == nil or entry.serial ~= serial then return false end
    bucket.entries[key] = nil
    bucket.count = math.max(0, bucket.count - 1)
    cacheEntries = math.max(0, cacheEntries - 1)
    if bucket.count == 0 then cache[namespace] = nil end
    if expired then totals.cacheExpired = totals.cacheExpired + 1
    else totals.cacheEvictions = totals.cacheEvictions + 1 end
    return true
end

local function cacheLimits()
    local namespaceLimit = math.max(1,
        math.floor(configured("performanceCacheNamespaceLimit", 512)))
    local totalLimit = math.max(namespaceLimit,
        math.floor(configured("performanceCacheTotalLimit", 1024)))
    return namespaceLimit, totalLimit
end

local function dequeueGlobal()
    if cacheQueueHead > cacheQueueTail then return nil end
    local token = cacheQueue[cacheQueueHead]
    cacheQueue[cacheQueueHead] = nil
    cacheQueueHead = cacheQueueHead + 1
    if cacheQueueHead > cacheQueueTail then
        cacheQueue, cacheQueueHead, cacheQueueTail = {}, 1, 0
    end
    return token
end

local function sweepCache(current, maximum)
    maximum = math.max(0, math.floor(tonumber(maximum) or 0))
    for _ = 1, maximum do
        local token = dequeueGlobal()
        if token == nil then break end
        local bucket = cache[token.namespace]
        local entry = bucket and bucket.entries[token.key] or nil
        if entry ~= nil and entry.serial == token.serial then
            if current > entry.expires then
                removeCacheEntry(token.namespace, token.key, token.serial, true)
            else
                cacheQueueTail = cacheQueueTail + 1
                cacheQueue[cacheQueueTail] = token
            end
        end
    end
end

local function evictBucketOldest(namespace, bucket)
    while bucket.head <= bucket.tail do
        local token = bucket.queue[bucket.head]
        bucket.queue[bucket.head] = nil
        bucket.head = bucket.head + 1
        local entry = token and bucket.entries[token.key] or nil
        if entry ~= nil and entry.serial == token.serial then
            return removeCacheEntry(namespace, token.key, token.serial, false)
        end
    end
    bucket.queue, bucket.head, bucket.tail = {}, 1, 0
    return false
end

local function evictGlobalOldest()
    while true do
        local token = dequeueGlobal()
        if token == nil then return false end
        if removeCacheEntry(token.namespace, token.key, token.serial, false) then return true end
    end
end

local function sampleWindow()
    return math.max(16, math.floor(configured("performanceSampleWindow", 120)))
end

local function pushSample(list, value)
    list[#list + 1] = math.max(0, tonumber(value) or 0)
    local limit = sampleWindow()
    while #list > limit do table.remove(list, 1) end
end

local function percentile(list, amount)
    if type(list) ~= "table" or #list == 0 then return 0 end
    local copy = {}
    for index, value in ipairs(list) do copy[index] = tonumber(value) or 0 end
    table.sort(copy)
    local index = math.max(1, math.min(#copy, math.ceil(#copy * amount)))
    return copy[index]
end

local function metricFor(store, key, label)
    local metric = store[key]
    if metric == nil then
        metric = {
            key = key,
            label = label or key,
            runs = 0,
            totalMs = 0,
            maxMs = 0,
            overBudget = 0,
            yielded = 0,
            units = 0,
            samples = {},
        }
        store[key] = metric
    end
    return metric
end

local function updateMetric(metric, elapsed, units, yielded)
    elapsed = math.max(0, tonumber(elapsed) or 0)
    metric.runs = metric.runs + 1
    metric.totalMs = metric.totalMs + elapsed
    metric.lastMs = elapsed
    metric.maxMs = math.max(metric.maxMs, elapsed)
    metric.units = metric.units + math.max(0, tonumber(units) or 0)
    if elapsed > configured("frameBudgetMs", 2) then
        metric.overBudget = metric.overBudget + 1
    end
    if yielded == true then
        metric.yielded = metric.yielded + 1
        totals.yieldedJobs = totals.yieldedJobs + 1
    end
    pushSample(metric.samples, elapsed)
end

local function metricSnapshot(metric)
    local average = metric.runs > 0 and metric.totalMs / metric.runs or 0
    return {
        key = metric.key,
        label = metric.label,
        runs = metric.runs,
        averageMs = average,
        p50Ms = percentile(metric.samples, 0.50),
        p95Ms = percentile(metric.samples, 0.95),
        maxMs = metric.maxMs,
        lastMs = metric.lastMs or 0,
        overBudget = metric.overBudget,
        yielded = metric.yielded,
        units = metric.units,
    }
end

local function sortedMetrics(store, limit)
    local result = {}
    for _, metric in pairs(store) do result[#result + 1] = metricSnapshot(metric) end
    table.sort(result, function(left, right)
        if left.p95Ms == right.p95Ms then
            if left.maxMs == right.maxMs then return left.key < right.key end
            return left.maxMs > right.maxMs
        end
        return left.p95Ms > right.p95Ms
    end)
    while #result > limit do table.remove(result) end
    return result
end

local function loadScale()
    if loadLevel == 1 then return 0.75 end
    if loadLevel == 2 then return 0.50 end
    if loadLevel >= 3 then return 0.35 end
    return 1
end

local function updateLoadLevel()
    local evaluationFrames = math.max(15,
        math.floor(configured("performanceLoadEvaluationFrames", 60)))
    if totals.frames == 0 or totals.frames % evaluationFrames ~= 0 then return end
    local cooldown = math.max(evaluationFrames,
        math.floor(configured("performanceLoadChangeCooldownFrames", 120)))
    if totals.frames - lastLoadChangeFrame < cooldown then return end
    local over = 0
    local budget = configured("frameBudgetMs", 2)
    for _, sample in ipairs(frameSamples) do if sample > budget then over = over + 1 end end
    local ratio = #frameSamples > 0 and over / #frameSamples or 0
    local p95 = percentile(frameSamples, 0.95)
    local raiseRatio = configured("performanceLoadRaiseRatio", 0.22)
    local lowerRatio = configured("performanceLoadLowerRatio", 0.05)
    if (ratio >= raiseRatio or p95 > budget * 1.5) and loadLevel < 3 then
        loadLevel = loadLevel + 1
        lastLoadChangeFrame = totals.frames
    elseif ratio <= lowerRatio and p95 <= budget and loadLevel > 0 then
        loadLevel = loadLevel - 1
        lastLoadChangeFrame = totals.frames
    end
end

function Performance.beginFrame(budgetMs, startedAt)
    local current = tonumber(startedAt) or nowMs()
    sweepCache(current, configured("performanceCacheSweepPerFrame", 24))
    frameSequence = frameSequence + 1
    frame = {
        id = frameSequence,
        startedAt = current,
        budgetMs = math.max(0.1, tonumber(budgetMs) or configured("frameBudgetMs", 2)),
        used = {},
        yielded = {},
    }
    return frame.id
end

function Performance.endFrame(elapsedMs, deferred)
    if frame == nil then return false end
    local elapsed = math.max(0, tonumber(elapsedMs) or (nowMs() - frame.startedAt))
    totals.frames = totals.frames + 1
    if elapsed > frame.budgetMs then totals.overBudgetFrames = totals.overBudgetFrames + 1 end
    if deferred == true then totals.deferredFrames = totals.deferredFrames + 1 end
    pushSample(frameSamples, elapsed)
    frame = nil
    updateLoadLevel()
    return true
end

function Performance.claimUnits(kind, requested, urgent)
    requested = math.max(0, math.floor(tonumber(requested) or 0))
    if requested == 0 or frame == nil then return requested end
    local configKey = quotaKeys[kind]
    if configKey == nil then return requested end
    local base = math.max(1, math.floor(configured(configKey, requested)))
    local limit = math.max(1, math.floor(base * loadScale()))
    if urgent == true then
        limit = math.max(limit, math.floor(configured("performanceUrgentUnitFloor", 96)))
    end
    local used = tonumber(frame.used[kind]) or 0
    local granted = math.max(0, math.min(requested, limit - used))
    frame.used[kind] = used + granted
    return granted
end

function Performance.markYield(system, companionId, units)
    if frame ~= nil then frame.yielded[tostring(system or "work")] = true end
    local systemKey = tostring(system or "unknown")
    local metric = metricFor(systems, systemKey, systemKey)
    metric.yielded = metric.yielded + 1
    if companionId ~= nil then
        local actorKey = tostring(companionId)
        local actorMetric = metricFor(actors, actorKey, actorKey)
        actorMetric.yielded = actorMetric.yielded + 1
    end
    totals.yieldedJobs = totals.yieldedJobs + 1
end

function Performance.record(system, companionId, elapsedMs, units, yielded)
    local systemKey = tostring(system or "unknown")
    updateMetric(metricFor(systems, systemKey, systemKey), elapsedMs, units, yielded)
    if companionId ~= nil then
        local actorKey = tostring(companionId)
        updateMetric(metricFor(actors, actorKey, actorKey),
            elapsedMs, units, yielded)
    end
end

function Performance.measure(system, companionId, callback, ...)
    if type(callback) ~= "function" then return false, "invalid callback" end
    local started = nowMs()
    local values = SC.Call.pack(pcall(callback, ...))
    Performance.record(system, companionId, nowMs() - started)
    if not values[1] then return false, values[2] end
    return true, SC.Call.unpack(values, 2, values.n)
end

function Performance.intervalScale(lane)
    lane = tostring(lane or "normal")
    if lane == "critical" then return 1 end
    if lane == "high" then return loadLevel >= 3 and 1.25 or 1 end
    if lane == "background" then
        if loadLevel == 1 then return 1.5 end
        if loadLevel == 2 then return 2 end
        if loadLevel >= 3 then return 3 end
        return 1
    end
    if loadLevel == 1 then return 1.15 end
    if loadLevel == 2 then return 1.5 end
    if loadLevel >= 3 then return 2 end
    return 1
end

function Performance.cacheGet(namespace, key, current)
    local name = tostring(namespace or "default")
    local textKey = tostring(key)
    local bucket = cache[name]
    local entry = bucket and bucket.entries[textKey] or nil
    current = tonumber(current) or nowMs()
    if entry and current <= entry.expires then
        totals.cacheHits = totals.cacheHits + 1
        return entry.value
    end
    if entry then removeCacheEntry(name, textKey, entry.serial, true) end
    totals.cacheMisses = totals.cacheMisses + 1
    return nil
end

function Performance.cachePut(namespace, key, value, ttlMs, current)
    local name = tostring(namespace or "default")
    local textKey = tostring(key)
    local bucket = cacheBucket(name)
    current = tonumber(current) or nowMs()
    local entry = bucket.entries[textKey]
    if entry == nil then
        cacheSerial = cacheSerial + 1
        entry = { serial = cacheSerial }
        bucket.entries[textKey] = entry
        bucket.count = bucket.count + 1
        cacheEntries = cacheEntries + 1
        local token = { namespace = name, key = textKey, serial = entry.serial }
        bucket.tail = bucket.tail + 1
        bucket.queue[bucket.tail] = token
        cacheQueueTail = cacheQueueTail + 1
        cacheQueue[cacheQueueTail] = token
    end
    entry.value = value
    entry.expires = current + math.max(1, tonumber(ttlMs)
        or configured("performanceCacheTtlMs", 75))
    local namespaceLimit, totalLimit = cacheLimits()
    while bucket.count > namespaceLimit do
        if not evictBucketOldest(name, bucket) then break end
    end
    while cacheEntries > totalLimit do
        if not evictGlobalOldest() then break end
    end
    return value
end

function Performance.cacheStats()
    local namespaces = {}
    for name, bucket in pairs(cache) do namespaces[name] = bucket.count end
    local namespaceLimit, totalLimit = cacheLimits()
    return {
        entries = cacheEntries,
        namespaceLimit = namespaceLimit,
        totalLimit = totalLimit,
        evictions = totals.cacheEvictions,
        expired = totals.cacheExpired,
        namespaces = namespaces,
    }
end

-- Test/support hook: production sweeping remains bounded through beginFrame.
function Performance.sweepCache(current, maximum)
    sweepCache(tonumber(current) or nowMs(), maximum)
    return Performance.cacheStats()
end

function Performance.frameId()
    return frame and frame.id or nil
end

function Performance.loadLevel()
    return loadLevel
end

function Performance.snapshot()
    return {
        frames = totals.frames,
        frameBudgetMs = configured("frameBudgetMs", 2),
        lastFrameMs = frameSamples[#frameSamples] or 0,
        p50FrameMs = percentile(frameSamples, 0.50),
        p95FrameMs = percentile(frameSamples, 0.95),
        maxFrameMs = percentile(frameSamples, 1),
        overBudgetFrames = totals.overBudgetFrames,
        deferredFrames = totals.deferredFrames,
        yieldedJobs = totals.yieldedJobs,
        cacheHits = totals.cacheHits,
        cacheMisses = totals.cacheMisses,
        cacheEntries = cacheEntries,
        cacheEvictions = totals.cacheEvictions,
        cacheExpired = totals.cacheExpired,
        loadLevel = loadLevel,
        topSystems = sortedMetrics(systems, 12),
        topActors = sortedMetrics(actors, 12),
        activeFrame = frame ~= nil,
    }
end

function Performance.summary()
    local snapshot = Performance.snapshot()
    local lines = {
        "Living Fellows AI performance report",
        "Frames: " .. tostring(snapshot.frames),
        "Budget: " .. tostring(snapshot.frameBudgetMs) .. " ms",
        string.format("Frame p50 / p95 / max: %.2f / %.2f / %.2f ms",
            snapshot.p50FrameMs, snapshot.p95FrameMs, snapshot.maxFrameMs),
        "Load level: " .. tostring(snapshot.loadLevel),
        "Over-budget frames: " .. tostring(snapshot.overBudgetFrames),
        "Deferred frames: " .. tostring(snapshot.deferredFrames),
        "Yielded jobs: " .. tostring(snapshot.yieldedJobs),
        "Cache hits / misses: " .. tostring(snapshot.cacheHits) .. " / "
            .. tostring(snapshot.cacheMisses),
        "Top systems:",
    }
    for _, metric in ipairs(snapshot.topSystems) do
        lines[#lines + 1] = string.format("  %s: p95 %.2f ms, max %.2f ms, runs %d, yields %d",
            metric.label, metric.p95Ms, metric.maxMs, metric.runs, metric.yielded)
    end
    lines[#lines + 1] = "Top companions:"
    for _, metric in ipairs(snapshot.topActors) do
        lines[#lines + 1] = string.format("  %s: p95 %.2f ms, max %.2f ms, runs %d, yields %d",
            metric.label, metric.p95Ms, metric.maxMs, metric.runs, metric.yielded)
    end
    return table.concat(lines, "\n"), snapshot
end

function Performance.reset()
    frame = nil
    systems = {}
    actors = {}
    frameSamples = {}
    cache = {}
    cacheQueue = {}
    cacheQueueHead = 1
    cacheQueueTail = 0
    cacheSerial = 0
    cacheEntries = 0
    loadLevel = 0
    lastLoadChangeFrame = 0
    totals = {
        frames = 0, overBudgetFrames = 0, deferredFrames = 0,
        yieldedJobs = 0, cacheHits = 0, cacheMisses = 0,
        cacheEvictions = 0, cacheExpired = 0,
    }
    return true
end

function Performance._setClock(callback)
    clockOverride = callback
end

return Performance
