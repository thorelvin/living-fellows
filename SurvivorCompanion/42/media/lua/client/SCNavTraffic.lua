-- SPDX-License-Identifier: MIT

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
if not SC.GameplayUtil and type(require) == "function" then pcall(require, "SCGameplayUtil") end

SC.NavTraffic = SC.NavTraffic or {}
local Traffic = SC.NavTraffic

local chokeReservations = {}
local chokeWaiters = setmetatable({}, { __mode = "k" })
local groupPassages = {}
local actorPassages = setmetatable({}, { __mode = "k" })
local trafficSequence = 0
local nextChokeSweepAt = 0
local stepReservations = {}
local nextStepSweepAt = 0

local function U()
    return SC.GameplayUtil
end

local function call(context, name, ...)
    local callback = type(context) == "table" and context[name] or nil
    if type(callback) ~= "function" then return nil end
    return callback(...)
end

local function record(context, actor, kind, fields)
    call(context, "record", actor, kind, fields)
end

local function groupPassageKey(edge, cohort)
    if type(edge) ~= "table" or not edge.key or not cohort then return nil end
    return tostring(cohort) .. "|" .. tostring(edge.key)
end

local function passageTimeout(count)
    return math.min(16000, 4000 + math.max(1, tonumber(count) or 1) * 1500)
end

local function passageActor(value)
    return type(value) == "table" and value.actor or value
end

local function passageCrossed(passage, actor, context)
    if not passage or not actor then return false end
    if passage.crossed[actor] == true then return true end
    if passage.kind == "door" then
        local progress = call(context, "doorGeometry", passage, actor)
        return progress ~= nil and progress >= (U().config("doorClearanceDistance") or 0.38)
    end
    if passage.kind == "stairs" then
        return call(context, "sameSquare", U().squareOf(actor), passage.toSquare) == true
            or (call(context, "differentFloor", actor, passage.fromSquare) == true
                and call(context, "differentFloor", actor, passage.toSquare) ~= true)
    end
    return call(context, "sameSquare", U().squareOf(actor), passage.toSquare) == true
end

local function refreshGroupPassage(passage, now, context)
    if not passage then return nil end
    local write, changed = 1, false
    for index = 1, #(passage.participants or {}) do
        local actor = passage.participants[index]
        if U().isValidActor(actor) and not U().isDead(actor) and U().squareOf(actor) then
            if passageCrossed(passage, actor, context) then
                if passage.crossed[actor] ~= true then changed = true end
                passage.crossed[actor] = true
            end
            passage.participants[write] = actor
            write = write + 1
        else
            passage.crossed[actor] = true
            changed = true
        end
    end
    for index = #passage.participants, write, -1 do passage.participants[index] = nil end
    local complete = true
    for _, actor in ipairs(passage.participants) do
        if passage.crossed[actor] ~= true then complete = false break end
    end
    if changed then
        passage.lastProgressAt = now
        passage.expires = now + passageTimeout(#passage.participants)
    end
    passage.complete = complete
    if complete then passage.completedAt = passage.completedAt or now end
    return passage
end

local function sweepGroupPassages(now, context)
    for key, passage in pairs(groupPassages) do
        refreshGroupPassage(passage, now, context)
        if (passage.complete and now - (passage.completedAt or now) > 1000)
            or now >= (passage.expires or 0) then
            groupPassages[key] = nil
        end
    end
end

function Traffic.observeGroupPassage(leader, edge, cohort, roster, current, context)
    if type(edge) ~= "table" or (edge.kind ~= "door" and edge.kind ~= "stairs") then
        return nil
    end
    local now = tonumber(current) or U().nowMs()
    local key = groupPassageKey(edge, cohort)
    if not key then return nil end
    local passage = groupPassages[key]
    if not passage then
        local participants, seen = {}, setmetatable({}, { __mode = "k" })
        local roles = setmetatable({}, { __mode = "k" })
        for _, value in ipairs(type(roster) == "table" and roster or {}) do
            local actor = passageActor(value)
            if actor and actor ~= leader and not seen[actor] and U().isValidActor(actor)
                and U().sameFloor(actor, edge.fromSquare)
                and U().distance(actor, edge.fromSquare) <= 12 then
                participants[#participants + 1] = actor
                roles[actor] = type(value) == "table" and value.cqbRole or nil
                seen[actor] = true
            end
        end
        passage = {
            key = key, cohort = cohort, kind = edge.kind, object = edge.object,
            fromSquare = edge.fromSquare, toSquare = edge.toSquare,
            owner = leader, participants = participants,
            crossed = setmetatable({}, { __mode = "k" }),
            roles = roles,
            yieldUntil = setmetatable({}, { __mode = "k" }),
            startedAt = now, lastProgressAt = now,
            expires = now + passageTimeout(#participants),
        }
        groupPassages[key] = passage
    end
    return refreshGroupPassage(passage, now, context)
end

local passageRoleOrder = {
    point = 1, assault = 2, ranged_support = 3, rear_guard = 4,
}

local function passageHead(passage, now)
    local approachRadius = tonumber(U().config("navigationPassageApproachRadius")) or 2.5
    local leaseMs = tonumber(U().config("navigationPassageHeadLeaseMs")) or 1100
    local stallMs = tonumber(U().config("navigationPassageStallMs")) or 900
    local progressDistance = tonumber(U().config("navigationGoalProgressDistance")) or 0.05
    local head = passage.head
    if head and passage.crossed[head] ~= true and U().isValidActor(head) then
        local nearby, distance = U().arrived(head, passage.fromSquare, {
            targetKind = "square", distance = approachRadius,
        })
        if distance + progressDistance < (passage.headDistance or math.huge) then
            passage.headDistance, passage.headProgressAt = distance, now
        end
        local stalled = now - (passage.headProgressAt or passage.headSince or now) > stallMs
        local expired = now - (passage.headSince or now) > leaseMs
        if nearby and not stalled and not expired then return head end
        passage.yieldUntil[head] = now
            + (tonumber(U().config("navigationPassageYieldMs")) or 500)
    end

    local candidates = {}
    for index, member in ipairs(passage.participants or {}) do
        if passage.crossed[member] ~= true and U().isValidActor(member) then
            local nearby, distance = U().arrived(member, passage.fromSquare, {
                targetKind = "square", distance = approachRadius,
            })
            if nearby and now >= (tonumber(passage.yieldUntil[member]) or 0) then
                candidates[#candidates + 1] = {
                    actor = member, index = index, distance = distance,
                    rank = passageRoleOrder[passage.roles[member]] or 9,
                }
            end
        end
    end
    if #candidates == 0 then
        for index, member in ipairs(passage.participants or {}) do
            if passage.crossed[member] ~= true and U().isValidActor(member) then
                local nearby, distance = U().arrived(member, passage.fromSquare, {
                    targetKind = "square", distance = approachRadius,
                })
                if nearby then
                    candidates[#candidates + 1] = {
                        actor = member, index = index, distance = distance,
                        rank = passageRoleOrder[passage.roles[member]] or 9,
                    }
                end
            end
        end
    end
    table.sort(candidates, function(left, right)
        if left.rank ~= right.rank then return left.rank < right.rank end
        return left.index < right.index
    end)
    local selected = candidates[1]
    passage.head = selected and selected.actor or nil
    passage.headSince = selected and now or nil
    passage.headProgressAt = selected and now or nil
    passage.headDistance = selected and selected.distance or nil
    return passage.head
end

function Traffic.groupPassageActive(edge, cohort, current, context)
    if type(edge) ~= "table" or not edge.key or not cohort then return false end
    local now = tonumber(current) or U().nowMs()
    sweepGroupPassages(now, context)
    local key = groupPassageKey(edge, cohort)
    local passage = key and groupPassages[key] or nil
    if not passage then return false, key end
    refreshGroupPassage(passage, now, context)
    return passage.complete ~= true and now < (passage.expires or 0), key
end

function Traffic.activePassageKey(key, current, context)
    local passage = key and groupPassages[key] or nil
    if not passage then return false end
    local now = tonumber(current) or U().nowMs()
    refreshGroupPassage(passage, now, context)
    return passage.complete ~= true and now < (passage.expires or 0)
end

function Traffic.ensureGroupPassage(actor, state, sourceSquare, nextSquare, kind,
        intent, now, context)
    if kind == "open" and (call(context, "squareHasStairs", sourceSquare) == true
        or call(context, "squareHasStairs", nextSquare) == true
        or call(context, "differentFloor", sourceSquare, nextSquare) == true) then
        kind = "stairs"
    end
    if kind == "open" and (call(context, "squareHasSlope", sourceSquare) == true
        or call(context, "squareHasSlope", nextSquare) == true) then
        kind = "slope"
    end
    if kind ~= "door" and kind ~= "stairs" and kind ~= "slope" then return true end
    local cohort = intent and intent.cohortKey
    if not cohort then return true end
    sweepGroupPassages(now, context)
    local edge = call(context, "edgeAffordance", sourceSquare, nextSquare)
    if not edge then return true end
    local key = groupPassageKey(edge, cohort)
    local passage = groupPassages[key]
    if not passage then
        passage = Traffic.observeGroupPassage(nil, edge, cohort,
            intent.groupParticipants, now, context)
    end
    if not passage then return true end
    local present = false
    for _, member in ipairs(passage.participants) do
        if member == actor then present = true break end
    end
    if not present then passage.participants[#passage.participants + 1] = actor end
    passage.roles = passage.roles or setmetatable({}, { __mode = "k" })
    passage.yieldUntil = passage.yieldUntil or setmetatable({}, { __mode = "k" })
    if intent and intent.cqbRole then passage.roles[actor] = intent.cqbRole end
    refreshGroupPassage(passage, now, context)
    state.currentPassageKey = key
    actorPassages[actor] = key
    if passage.crossed[actor] == true then return true end
    local head = passageHead(passage, now)
    if head ~= actor and intent and intent.urgent == true then
        local occupied = false
        for _, member in ipairs(passage.participants) do
            if member ~= actor and call(context, "occupiesDoorway", member, passage) == true then
                occupied = true
                break
            end
        end
        if not occupied then
            for index, member in ipairs(passage.participants) do
                if member == actor then table.remove(passage.participants, index) break end
            end
            table.insert(passage.participants, 1, actor)
            head = actor
            passage.head = actor
            passage.headSince, passage.headProgressAt = now, now
            passage.headDistance = select(2, U().arrived(actor, passage.fromSquare, {
                targetKind = "square", distance = 0,
            }))
        end
    end
    if head ~= actor then
        if state.passageQueueOwner ~= head then
            record(context, actor, "passage_queued", {
                status = "waiting_for:" .. tostring(U().idOf(head)), nextSquare = nextSquare,
            })
        end
        state.passageQueueOwner = head
        return false, head
    end
    if state.passageQueueOwner ~= nil then
        record(context, actor, "passage_acquired", {
            status = passage.kind, nextSquare = nextSquare,
        })
    end
    state.passageQueueOwner = nil
    return true
end

function Traffic.markActorPassage(actor, state, now, context)
    local key = state and (state.currentPassageKey or actorPassages[actor])
        or actorPassages[actor]
    local passage = key and groupPassages[key] or nil
    if not passage then return end
    if passageCrossed(passage, actor, context) then
        passage.crossed[actor] = true
        passage.lastProgressAt = now
        passage.expires = now + passageTimeout(#passage.participants)
        refreshGroupPassage(passage, now, context)
        if passage.complete then
            if state then state.currentPassageKey = nil end
            actorPassages[actor] = nil
        end
    end
end

function Traffic.actorPassageKey(actor, state)
    return state and state.currentPassageKey or actor and actorPassages[actor] or nil
end

function Traffic.priority(intent)
    if type(intent) ~= "table" then return 10 end
    if intent.urgent == true then return 100 end
    if tonumber(intent.movementPriority) then return tonumber(intent.movementPriority) end
    local action = tostring(intent.action or "")
    if string.find(action, "retreat", 1, true) or string.find(action, "rescue", 1, true)
        or string.find(action, "combat", 1, true) then return 80 end
    if string.find(action, "medical", 1, true) then return 70 end
    if string.find(action, "conversation", 1, true) then return 30 end
    if string.find(action, "follow", 1, true) or action == "regroup" then return 20 end
    return 40
end

function Traffic.releaseChoke(state, actor, context)
    local released = state and type(state.chokeReservationKeys) == "table"
        and #state.chokeReservationKeys > 0
    for _, key in ipairs(state and state.chokeReservationKeys or {}) do
        local entry = chokeReservations[key]
        if entry and entry.actor == actor then chokeReservations[key] = nil end
    end
    chokeWaiters[actor] = nil
    if state then
        state.chokeReservationKeys = nil
        state.chokeQueueOwner = nil
        state.chokeQueueSince = nil
    end
    if released then
        record(context, actor, "choke_released", { status = "corridor_clear" })
    end
end

function Traffic.extendChoke(state, actor, untilAt)
    for _, key in ipairs(state and state.chokeReservationKeys or {}) do
        local entry = chokeReservations[key]
        if entry and entry.actor == actor then
            entry.expires = math.max(tonumber(entry.expires) or 0, tonumber(untilAt) or 0)
        end
    end
end

local function chokeEdgeKey(first, second, context)
    local firstKey = call(context, "squareKey", first)
    local secondKey = call(context, "squareKey", second)
    if not firstKey or not secondKey then return nil end
    if firstKey > secondKey then firstKey, secondKey = secondKey, firstKey end
    return "edge:" .. firstKey .. "<>" .. secondKey
end

local function waiterOverlaps(keys, waiter)
    if type(waiter) ~= "table" or type(waiter.keys) ~= "table" then return false end
    local wanted = {}
    for _, key in ipairs(keys or {}) do wanted[key] = true end
    for _, key in ipairs(waiter.keys) do if wanted[key] then return true end end
    return false
end

local function waiterBefore(first, second)
    if second == nil then return true end
    if first.priority ~= second.priority then return first.priority > second.priority end
    if first.ticket ~= second.ticket then return first.ticket < second.ticket end
    return tostring(first.id) < tostring(second.id)
end

local function bestChokeWaiter(keys, now)
    local best
    for candidate, waiter in pairs(chokeWaiters) do
        if not waiter or waiter.expires <= now then
            chokeWaiters[candidate] = nil
        elseif waiterOverlaps(keys, waiter) and waiterBefore(waiter, best) then
            best = waiter
        end
    end
    return best
end

function Traffic.reserveChoke(sourceSquare, nextSquare, afterSquare, actor, state,
        intent, now, context)
    if now >= nextChokeSweepAt then
        for key, entry in pairs(chokeReservations) do
            if not entry or entry.expires <= now then chokeReservations[key] = nil end
        end
        nextChokeSweepAt = now + 5000
    end
    local keys, seen = {}, {}
    local function add(key)
        if key and not seen[key] then seen[key] = true keys[#keys + 1] = key end
    end
    add(chokeEdgeKey(sourceSquare, nextSquare, context))
    local nextKey = call(context, "squareKey", nextSquare)
    add(nextKey and "square:" .. tostring(nextKey) or nil)
    if (U().config("navigationChokeCorridorNodes") or 3) >= 3 then
        add(chokeEdgeKey(nextSquare, afterSquare, context))
        local afterKey = call(context, "squareKey", afterSquare)
        add(afterKey and "square:" .. tostring(afterKey) or nil)
    end
    if #keys == 0 then return false end
    local owner
    for _, key in ipairs(keys) do
        local existing = chokeReservations[key]
        if existing and existing.actor ~= actor and existing.expires > now then
            owner = existing.actor
            break
        end
    end
    local waiting = chokeWaiters[actor]
    if owner then
        if not waiting then
            trafficSequence = trafficSequence + 1
            waiting = {
                actor = actor, id = tostring(U().idOf(actor)), ticket = trafficSequence,
                since = now,
            }
        end
        waiting.keys = keys
        waiting.priority = Traffic.priority(intent)
        waiting.expires = now + (U().config("navigationTrafficWaiterMs") or 5000)
        chokeWaiters[actor] = waiting
        if state.chokeQueueOwner ~= owner then
            record(context, actor, "choke_queued", {
                status = "waiting_for:" .. tostring(U().idOf(owner)),
                nextSquare = nextSquare,
            })
        end
        state.chokeQueueOwner = owner
        state.chokeQueueSince = state.chokeQueueSince or now
        return false, owner
    end
    local retained = type(state.chokeReservationKeys) == "table"
        and #state.chokeReservationKeys == #keys
    if retained then
        local currentKeys = {}
        for _, key in ipairs(state.chokeReservationKeys) do currentKeys[key] = true end
        for _, key in ipairs(keys) do
            local entry = chokeReservations[key]
            if not currentKeys[key] or not entry or entry.actor ~= actor then
                retained = false
                break
            end
        end
    end
    if retained then
        local expiry = now + (U().config("navigationChokeReservationMs") or 1400)
        for _, key in ipairs(keys) do chokeReservations[key].expires = expiry end
        chokeWaiters[actor] = nil
        state.chokeQueueOwner, state.chokeQueueSince = nil, nil
        return true
    end
    local best = bestChokeWaiter(keys, now)
    if best and best.actor ~= actor then
        state.chokeQueueOwner = best.actor
        state.chokeQueueSince = state.chokeQueueSince or now
        return false, best.actor
    end
    Traffic.releaseChoke(state, actor, context)
    local expiry = now + (U().config("navigationChokeReservationMs") or 1400)
    local priority = Traffic.priority(intent)
    local id = tostring(U().idOf(actor))
    for _, key in ipairs(keys) do
        chokeReservations[key] = {
            actor = actor, id = id, priority = priority, expires = expiry,
        }
    end
    state.chokeReservationKeys = keys
    state.chokeQueueOwner = nil
    state.chokeQueueSince = nil
    record(context, actor, "choke_acquired", {
        status = "keys:" .. tostring(#keys), nextSquare = nextSquare,
    })
    return true
end

function Traffic.releaseStep(state, actor)
    local key = state and state.stepReservationKey or nil
    local reservation = key and stepReservations[key] or nil
    if reservation and reservation.actor == actor then stepReservations[key] = nil end
    if state then state.stepReservationKey = nil end
end

function Traffic.reserveStep(square, actor, state, intent, now, context)
    if now >= nextStepSweepAt then
        for key, entry in pairs(stepReservations) do
            if not entry or entry.expires <= now then stepReservations[key] = nil end
        end
        nextStepSweepAt = now + 3000
    end
    local key = call(context, "squareKey", square)
    if not key then return false end
    local priority = Traffic.priority(intent)
    local id = tostring(U().idOf(actor))
    local existing = stepReservations[key]
    if existing and existing.actor ~= actor and existing.expires > now then
        if state.stepQueueOwner ~= existing.actor then
            record(context, actor, "step_queued", {
                status = "waiting_for:" .. tostring(existing.id), nextSquare = square,
            })
        end
        state.stepQueueOwner = existing.actor
        state.stepQueueSince = state.stepQueueSince or now
        return false, existing.actor
    end
    Traffic.releaseStep(state, actor)
    stepReservations[key] = {
        actor = actor,
        id = id,
        priority = priority,
        expires = now + (U().config("navigationStepReservationMs") or 450),
    }
    state.stepReservationKey = key
    state.stepQueueOwner = nil
    state.stepQueueSince = nil
    return true
end

function Traffic.cancel(actor, state, context)
    local passageKey = actor and actorPassages[actor] or nil
    local passage = passageKey and groupPassages[passageKey] or nil
    if passage and actor then passage.crossed[actor] = true end
    if actor then actorPassages[actor] = nil end
    Traffic.releaseStep(state, actor)
    Traffic.releaseChoke(state, actor, context)
end

function Traffic.releaseActor(actor)
    if actor == nil then return false end
    chokeWaiters[actor] = nil
    actorPassages[actor] = nil
    for key, entry in pairs(chokeReservations) do
        if entry and entry.actor == actor then chokeReservations[key] = nil end
    end
    for key, entry in pairs(stepReservations) do
        if entry and entry.actor == actor then stepReservations[key] = nil end
    end
    for key, passage in pairs(groupPassages) do
        if passage.owner == actor then
            groupPassages[key] = nil
        else
            local write = 1
            for index = 1, #(passage.participants or {}) do
                local participant = passage.participants[index]
                if participant ~= actor then
                    passage.participants[write] = participant
                    write = write + 1
                end
            end
            for index = #(passage.participants or {}), write, -1 do
                passage.participants[index] = nil
            end
            if passage.crossed then passage.crossed[actor] = nil end
            if passage.roles then passage.roles[actor] = nil end
            if passage.yieldUntil then passage.yieldUntil[actor] = nil end
            if passage.head == actor then
                passage.head, passage.headDistance, passage.headSince,
                    passage.headProgressAt = nil, nil, nil, nil
            end
        end
    end
    return true
end

function Traffic.reset()
    chokeReservations = {}
    chokeWaiters = setmetatable({}, { __mode = "k" })
    groupPassages = {}
    actorPassages = setmetatable({}, { __mode = "k" })
    trafficSequence = 0
    nextChokeSweepAt = 0
    stepReservations = {}
    nextStepSweepAt = 0
end

return Traffic
