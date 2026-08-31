-- SPDX-License-Identifier: MIT

require "SCNamespace"
require "SCConfig"
require "SCDiagnostics"
require "SCPerformance"

local SC = SurvivorCompanion
SC.Scheduler = SC.Scheduler or {}

local scheduler = SC.Scheduler
local tasksByName = {}
local ordered = {}
local actorClocks = {}
local clockOverride = nil
local stats = {
    frames = 0,
    callbacks = 0,
    deferredFrames = 0,
    exceptions = 0,
    circuitSkips = 0,
    reportedFailures = 0,
    lastFrameMs = 0,
    overBudgetFrames = 0,
}

local function nowMs()
    if clockOverride ~= nil then
        return clockOverride()
    end
    if getTimestampMs ~= nil then
        local ok, value = pcall(getTimestampMs)
        local numeric = ok and tonumber(value) or nil
        if numeric ~= nil then return numeric end
    end
    return math.floor(os.clock() * 1000)
end

local function rebuildOrder()
    ordered = {}
    for _, task in pairs(tasksByName) do
        ordered[#ordered + 1] = task
    end
    table.sort(ordered, function(a, b)
        if a.priority == b.priority then
            return a.name < b.name
        end
        return a.priority > b.priority
    end)
end

local function stableHash(text)
    local hash = 2166136261
    for index = 1, #text do
        hash = (hash * 16777619 + string.byte(text, index)) % 2147483647
    end
    return hash
end

local function inferredLane(priority)
    if priority >= 80 then return "critical" end
    if priority >= 50 then return "high" end
    if priority < 20 then return "background" end
    return "normal"
end

function scheduler.register(name, interval, priority, callback, options)
    if type(name) ~= "string" or name == "" then
        return false, "scheduler name is required"
    end
    if type(interval) ~= "number" or interval < 1 then
        return false, "scheduler interval must be at least one millisecond"
    end
    if type(priority) ~= "number" then
        return false, "scheduler priority must be numeric"
    end
    if type(callback) ~= "function" then
        return false, "scheduler callback is required"
    end

    options = type(options) == "table" and options or {}
    local existing = tasksByName[name]
    local lane = options.lane or (existing and existing.lane) or inferredLane(priority)
    local validLanes = { critical = true, high = true, normal = true, background = true }
    if validLanes[lane] ~= true then
        return false, "scheduler lane must be critical, high, normal, or background"
    end
    local unchanged = existing ~= nil and existing.interval == math.floor(interval)
        and existing.priority == priority and existing.callback == callback
        and existing.lane == lane
    local keepSchedule = existing ~= nil
        and (options.preserveSchedule == true or unchanged)
    tasksByName[name] = {
        name = name,
        interval = math.floor(interval),
        priority = priority,
        callback = callback,
        nextDue = keepSchedule and existing.nextDue or nil,
        runs = existing and existing.runs or 0,
        lane = lane,
        reportFailure = options.reportFailure == nil and existing ~= nil
            and existing.reportFailure == true or options.reportFailure == true,
    }
    rebuildOrder()
    return true
end

function scheduler.unregister(name)
    if tasksByName[name] == nil then
        return false
    end
    tasksByName[name] = nil
    rebuildOrder()
    return true
end

function scheduler.dueFor(companionId, lane, interval, current)
    if type(companionId) ~= "string" or type(lane) ~= "string" then
        return false
    end
    if type(interval) ~= "number" or interval < 1 then
        return false
    end

    current = current or nowMs()
    local key = companionId .. ":" .. lane
    local due = actorClocks[key]
    if due == nil then
        due = current + (stableHash(key) % math.floor(interval))
        actorClocks[key] = due
    end
    if current < due then
        return false
    end

    actorClocks[key] = current + math.floor(interval)
    return true
end

function scheduler.tick()
    stats.frames = stats.frames + 1
    if #ordered == 0 then
        stats.lastFrameMs = 0
        return
    end

    local started = nowMs()
    local budget = SC.Config.get("runtime", "frameBudgetMs")
    if SC.Performance and type(SC.Performance.beginFrame) == "function" then
        SC.Performance.beginFrame(budget, started)
    end
    local current = started
    local deferred = false
    local runnable = {}
    for _, task in ipairs(ordered) do
        if task.nextDue == nil then
            task.nextDue = current + task.interval
        elseif current >= task.nextDue then
            runnable[#runnable + 1] = task
        end
    end
    local laneRank = { critical = 4, high = 3, normal = 2, background = 1 }
    table.sort(runnable, function(left, right)
        local leftRank = laneRank[left.lane] or 2
        local rightRank = laneRank[right.lane] or 2
        if leftRank ~= rightRank then return leftRank > rightRank end
        local leftOverdue = current - (left.nextDue or current)
        local rightOverdue = current - (right.nextDue or current)
        if leftOverdue ~= rightOverdue then return leftOverdue > rightOverdue end
        if left.priority ~= right.priority then return left.priority > right.priority end
        return left.name < right.name
    end)

    for runnableIndex, task in ipairs(runnable) do
        if current - started >= budget then
            stats.deferredFrames = stats.deferredFrames + 1
            deferred = true
            break
        end
        local callbackStarted = nowMs()
        local ok, result, detail = SC.Diagnostics.guard(task.name, nil,
            task.callback, current, budget - (current - started))
        local callbackElapsed = math.max(0, nowMs() - callbackStarted)
        if SC.Performance and type(SC.Performance.record) == "function" then
            SC.Performance.record("scheduler." .. task.name, nil, callbackElapsed)
        end
        task.runs = task.runs + 1
        stats.callbacks = stats.callbacks + 1
        if not ok then
            if detail == "circuit_skip" then
                stats.circuitSkips = stats.circuitSkips + 1
            else
                stats.exceptions = stats.exceptions + 1
            end
        elseif task.reportFailure and result == false then
            stats.reportedFailures = stats.reportedFailures + 1
            SC.Diagnostics.report(task.name, nil,
                "scheduled callback reported failure", detail)
        end
        current = nowMs()
        local scale = SC.Performance and type(SC.Performance.intervalScale) == "function"
            and SC.Performance.intervalScale(task.lane) or 1
        task.nextDue = current + math.max(1, math.floor(task.interval * scale))
    end
    stats.lastFrameMs = nowMs() - started
    if stats.lastFrameMs > budget then stats.overBudgetFrames = stats.overBudgetFrames + 1 end
    if SC.Performance and type(SC.Performance.endFrame) == "function" then
        SC.Performance.endFrame(stats.lastFrameMs, deferred)
    end
end

function scheduler.reset(clearTasks)
    actorClocks = {}
    stats.frames = 0
    stats.callbacks = 0
    stats.deferredFrames = 0
    stats.exceptions = 0
    stats.circuitSkips = 0
    stats.reportedFailures = 0
    stats.lastFrameMs = 0
    stats.overBudgetFrames = 0
    if clearTasks then
        tasksByName = {}
        ordered = {}
    else
        for _, task in pairs(tasksByName) do
            task.nextDue = nil
            task.runs = 0
        end
    end
    if clearTasks and SC.Performance and type(SC.Performance.reset) == "function" then
        SC.Performance.reset()
    end
end

function scheduler.getStats()
    local taskStats = {}
    for _, task in ipairs(ordered) do
        taskStats[#taskStats + 1] = {
            name = task.name,
            lane = task.lane,
            interval = task.interval,
            runs = task.runs,
            nextDue = task.nextDue,
        }
    end
    return {
        frames = stats.frames,
        callbacks = stats.callbacks,
        deferredFrames = stats.deferredFrames,
        exceptions = stats.exceptions,
        circuitSkips = stats.circuitSkips,
        reportedFailures = stats.reportedFailures,
        lastFrameMs = stats.lastFrameMs,
        overBudgetFrames = stats.overBudgetFrames,
        taskCount = #ordered,
        tasks = taskStats,
        loadLevel = SC.Performance and type(SC.Performance.loadLevel) == "function"
            and SC.Performance.loadLevel() or 0,
    }
end

function scheduler._setClock(callback)
    clockOverride = callback
end

return scheduler
