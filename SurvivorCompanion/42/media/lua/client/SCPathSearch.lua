-- SPDX-License-Identifier: MIT

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion

SC.PathSearch = SC.PathSearch or {}
local PathSearch = SC.PathSearch

-- The search job owns only graph-search state. World topology, traversal,
-- movement, reservations and recovery remain behind the caller's adapter.

local function heapEntryLess(a, b)
    if a.f ~= b.f then return a.f < b.f end
    if a.h ~= b.h then return a.h < b.h end
    local aFamiliarity = tonumber(a.familiarity) or 0
    local bFamiliarity = tonumber(b.familiarity) or 0
    if aFamiliarity ~= bFamiliarity then return aFamiliarity > bFamiliarity end
    return a.seq < b.seq
end

local function heapPush(heap, entry)
    heap[#heap + 1] = entry
    local child = #heap
    while child > 1 do
        local parent = math.floor(child / 2)
        if heapEntryLess(heap[child], heap[parent]) then
            heap[child], heap[parent] = heap[parent], heap[child]
            child = parent
        else
            break
        end
    end
end

local function heapPop(heap)
    local size = #heap
    if size == 0 then return nil end
    local top = heap[1]
    local last = heap[size]
    heap[size] = nil
    size = size - 1
    if size > 0 then
        heap[1] = last
        local parent = 1
        while true do
            local left, right = parent * 2, parent * 2 + 1
            local smallest = parent
            if left <= size and heapEntryLess(heap[left], heap[smallest]) then smallest = left end
            if right <= size and heapEntryLess(heap[right], heap[smallest]) then smallest = right end
            if smallest == parent then break end
            heap[parent], heap[smallest] = heap[smallest], heap[parent]
            parent = smallest
        end
    end
    return top
end

local function reconstruct(nodes, goalKey)
    local reverse, key = {}, goalKey
    while key do
        local node = nodes[key]
        if not node then break end
        reverse[#reverse + 1] = node.square
        key = node.parent
    end
    local path = {}
    for index = #reverse, 1, -1 do path[#path + 1] = reverse[index] end
    return path
end

-- Outdoor egress uses the same stable heap primitives with a different goal
-- predicate. They remain stateless and never acquire world-side authority.
PathSearch.heapPush = heapPush
PathSearch.heapPop = heapPop
PathSearch.reconstruct = reconstruct

function PathSearch.classifyFailure(job, reason)
    if reason == "budget" then return "budget_exhausted", true end
    local rejections = type(job) == "table" and job.rejections or {}
    if (tonumber(rejections.safehouse_boundary) or 0) > 0 then
        return "policy", false
    end
    if (tonumber(rejections.native_directional_edge) or 0) > 0 then
        return "topology_native_required", true
    end
    for rejection in pairs(rejections) do
        if string.find(tostring(rejection), "blacklisted_dynamic", 1, true) then
            return "blocked_dynamic", false
        end
    end
    return reason == "invalid_square" and "invalid" or "blocked_static", false
end

local function adapterValid(adapter)
    return type(adapter) == "table"
        and type(adapter.sameSquare) == "function"
        and type(adapter.key) == "function"
        and type(adapter.heuristic) == "function"
        and type(adapter.neighbors) == "function"
        and type(adapter.edge) == "function"
end

function PathSearch.new(startSquare, goalSquare, options, adapter)
    options = type(options) == "table" and options or {}
    if not adapterValid(adapter) then
        return {
            complete = true, path = nil, reason = "invalid_adapter", expanded = 0,
            startSquare = startSquare, goalSquare = goalSquare, options = options,
        }
    end
    if adapter.sameSquare(startSquare, goalSquare) then
        return {
            complete = true, path = { startSquare }, reason = nil, expanded = 0,
            startSquare = startSquare, goalSquare = goalSquare, options = options,
            adapter = adapter,
        }
    end
    local defaultBudget = type(adapter.nodeBudget) == "function"
        and adapter.nodeBudget(options) or adapter.nodeBudget
    local nodeBudget = tonumber(options.nodeBudget) or tonumber(defaultBudget) or 220
    local penalties = type(options.penalties) == "table" and options.penalties or {}
    local startKey = adapter.key(startSquare)
    local goalKey = adapter.key(goalSquare)
    if not startKey or not goalKey then
        return {
            complete = true, path = nil, reason = "invalid_square", expanded = 0,
            startSquare = startSquare, goalSquare = goalSquare, options = options,
            adapter = adapter,
        }
    end
    local startH = adapter.heuristic(startSquare, goalSquare)
    local nodes = {
        [startKey] = { square = startSquare, g = 0, h = startH, f = startH,
            familiarity = 0, parent = nil, seq = 0 },
    }
    return {
        complete = false,
        path = nil,
        reason = nil,
        startSquare = startSquare,
        goalSquare = goalSquare,
        startKey = startKey,
        goalKey = goalKey,
        nodeBudget = nodeBudget,
        options = options,
        penalties = penalties,
        adapter = adapter,
        nodes = nodes,
        open = { { key = startKey, f = startH, h = startH,
            familiarity = 0, seq = 0 } },
        seqCounter = 0,
        closed = {},
        rejections = {},
        requiresNative = false,
        expanded = 0,
    }
end

function PathSearch.resume(job, expansionQuota)
    if type(job) ~= "table" then return "failed", nil, "invalid_job", 0, 0 end
    if job.complete then
        return job.path and "complete" or "failed", job.path, job.reason, job.expanded or 0, 0
    end
    if not adapterValid(job.adapter) then
        job.complete, job.reason = true, "invalid_adapter"
        return "failed", nil, job.reason, job.expanded or 0, 0
    end
    local adapter = job.adapter
    local quota = math.max(1, math.floor(tonumber(expansionQuota) or job.nodeBudget or 1))
    local used = 0
    while #job.open > 0 and job.expanded < job.nodeBudget and used < quota do
        local entry = heapPop(job.open)
        if entry == nil then break end
        local bestKey = entry.key
        local node = job.nodes[bestKey]
        -- Improvements use lazy deletion. Superseded priorities and already
        -- closed nodes do not consume the caller's expansion quota.
        if node ~= nil and not job.closed[bestKey]
            and entry.f == node.f and entry.h == node.h
            and (tonumber(entry.familiarity) or 0) == (tonumber(node.familiarity) or 0) then
            if bestKey == job.goalKey then
                job.complete = true
                job.path = reconstruct(job.nodes, bestKey)
                return "complete", job.path, nil, job.expanded, used
            end
            job.closed[bestKey] = true
            job.expanded = job.expanded + 1
            used = used + 1
            local current = node
            for _, otherSquare in ipairs(adapter.neighbors(
                current.square, job.goalSquare, job.options) or {}) do
                local otherKey = adapter.key(otherSquare)
                if otherKey and not job.closed[otherKey] then
                    local passable, cost, rejection, ignoredObject, edgeFamiliarity =
                        adapter.edge(current.square, otherSquare, job.options,
                            otherKey == job.goalKey)
                    if passable then
                        local dynamicPenalty = 0
                        if type(job.options.squarePenalty) == "function" then
                            local value = tonumber(job.options.squarePenalty(
                                otherSquare, current.square))
                            if value and value == value and value > 0 and value < math.huge then
                                dynamicPenalty = value
                            end
                        end
                        local tentative = current.g + cost
                            + (tonumber(job.penalties[otherKey]) or 0) + dynamicPenalty
                        local tentativeFamiliarity = (tonumber(current.familiarity) or 0)
                            + (tonumber(edgeFamiliarity) or 0)
                        local known = job.nodes[otherKey]
                        if not known or tentative < known.g
                            or (tentative == known.g and tentativeFamiliarity
                                > (tonumber(known.familiarity) or 0)) then
                            local seq = known and known.seq
                            if seq == nil then
                                job.seqCounter = job.seqCounter + 1
                                seq = job.seqCounter
                            end
                            local h = adapter.heuristic(otherSquare, job.goalSquare)
                            local fScore = tentative + h
                            job.nodes[otherKey] = {
                                square = otherSquare,
                                g = tentative,
                                h = h,
                                f = fScore,
                                familiarity = tentativeFamiliarity,
                                parent = bestKey,
                                seq = seq,
                            }
                            heapPush(job.open, { key = otherKey, f = fScore, h = h,
                                familiarity = tentativeFamiliarity, seq = seq })
                        end
                    elseif rejection then
                        job.rejections[rejection] = (job.rejections[rejection] or 0) + 1
                        if rejection == "native_directional_edge" then
                            job.requiresNative = true
                        end
                    end
                end
            end
        end
    end
    if #job.open == 0 or job.expanded >= job.nodeBudget then
        job.complete = true
        job.reason = job.expanded >= job.nodeBudget and "budget" or "unreachable"
        job.failureClass, job.nativeFallbackAllowed = PathSearch.classifyFailure(job, job.reason)
        return "failed", nil, job.reason, job.expanded, used
    end
    return "pending", nil, "searching", job.expanded, used
end

function PathSearch.run(startSquare, goalSquare, options, adapter)
    local job = PathSearch.new(startSquare, goalSquare, options, adapter)
    local status, path, reason, expanded = PathSearch.resume(job, job.nodeBudget or 1)
    if status == "pending" then return nil, "budget", expanded end
    return path, reason, expanded
end

return PathSearch
