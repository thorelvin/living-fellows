-- SPDX-License-Identifier: MIT

if type(require) == "function" then pcall(require, "SCNamespace") end

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.StableValue = SC.StableValue or {}

local StableValue = SC.StableValue

local function finite(value)
    return value == value and value ~= math.huge and value ~= -math.huge
end

local function copyFailure(job, reason)
    job.status = "failed"
    job.reason = tostring(reason)
    return job.status, nil, job.reason, job.count
end

function StableValue.beginCopy(value, options)
    options = type(options) == "table" and options or {}
    return {
        status = "pending",
        maximumDepth = math.max(0, math.floor(tonumber(options.maxDepth) or 8)),
        maximumValues = math.max(1,
            math.floor(tonumber(options.maxEntries or options.maxValues) or 1024)),
        seen = {}, count = 0, result = nil, reason = nil,
        stack = {{
            phase = "value", value = value, depth = 0,
            path = options.path or "$", parent = nil, key = nil,
        }},
    }
end

local function assign(frame, value, job)
    if frame.parent == nil then job.result = value
    else frame.parent[frame.key] = value end
end

local function resumeSlice(job, maximumUnits, deadline, clock, minimumUnits)
    local units = 0
    while #job.stack > 0 and units < maximumUnits do
        if units >= minimumUnits and deadline ~= nil and clock() >= deadline then break end
        local frame = job.stack[#job.stack]
        if frame.phase == "iterate" then
            local key, child = frame.iterator(frame.state, frame.lastKey)
            units = units + 1
            if key == nil then
                job.seen[frame.source] = nil
                job.stack[#job.stack] = nil
            else
                frame.lastKey = key
                local keyType = type(key)
                if keyType ~= "string" and keyType ~= "number" then
                    error("unsupported " .. keyType .. " key at " .. frame.path)
                end
                if keyType == "number" and not finite(key) then
                    error("non-finite key at " .. frame.path)
                end
                job.stack[#job.stack + 1] = {
                    phase = "value", value = child, depth = frame.depth + 1,
                    path = frame.path .. "[" .. tostring(key) .. "]",
                    parent = frame.result, key = key,
                }
            end
        else
            job.stack[#job.stack] = nil
            local current = frame.value
            local kind = type(current)
            units = units + 1
            if kind == "nil" then
                assign(frame, nil, job)
            else
                job.count = job.count + 1
                if job.count > job.maximumValues then
                    error("stable value limit exceeded at " .. frame.path)
                end
                if kind == "string" or kind == "boolean" then
                    assign(frame, current, job)
                elseif kind == "number" then
                    if not finite(current) then error("non-finite number at " .. frame.path) end
                    assign(frame, current, job)
                elseif kind ~= "table" then
                    error("unsupported " .. kind .. " at " .. frame.path)
                else
                    if frame.depth > job.maximumDepth then
                        error("stable value depth exceeded at " .. frame.path)
                    end
                    if job.seen[current] ~= nil then
                        error("cyclic or repeated table at " .. frame.path .. " (first seen at "
                            .. job.seen[current] .. ")")
                    end
                    job.seen[current] = frame.path
                    local result = {}
                    assign(frame, result, job)
                    local iterator, state, first = pairs(current)
                    job.stack[#job.stack + 1] = {
                        phase = "iterate", source = current, result = result,
                        depth = frame.depth, path = frame.path,
                        iterator = iterator, state = state, lastKey = first,
                    }
                end
            end
        end
    end
    return units
end

function StableValue.resumeCopy(job, options)
    if type(job) ~= "table" then return "failed", nil, "invalid copy job", 0 end
    if job.status == "complete" then return "complete", job.result, nil, job.count end
    if job.status == "failed" then return "failed", nil, job.reason, job.count end
    options = type(options) == "table" and options or { maxUnits = options }
    local maximumUnits = math.max(1, math.floor(tonumber(options.maxUnits) or 128))
    local minimumUnits = math.max(1, math.min(maximumUnits,
        math.floor(tonumber(options.minUnits) or 1)))
    local clock = type(options.clock) == "function" and options.clock
        or function() return math.floor((os.clock and os.clock() or 0) * 1000) end
    local ok, unitsOrReason = pcall(resumeSlice, job, maximumUnits,
        tonumber(options.deadline), clock, minimumUnits)
    if not ok then return copyFailure(job, unitsOrReason) end
    job.lastUnits = unitsOrReason
    if #job.stack == 0 then
        job.status = "complete"
        return "complete", job.result, nil, job.count
    end
    job.status = "yielded"
    return "yielded", nil, nil, job.count
end

function StableValue.copyStrict(value, options)
    local job = StableValue.beginCopy(value, options)
    while true do
        local status, copied, reason, count = StableValue.resumeCopy(job, {
            maxUnits = math.max(1024, job.maximumValues * 2 + 2),
        })
        if status == "complete" then return copied, nil, count end
        if status == "failed" then return nil, reason, count end
    end
end

return StableValue
