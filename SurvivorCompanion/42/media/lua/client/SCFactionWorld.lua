-- SPDX-License-Identifier: MIT

local SC = SurvivorCompanion
if not SC.StableValue and type(require) == "function" then pcall(require, "SCStableValue") end
SC.FactionWorld = SC.FactionWorld or {}

local World = SC.FactionWorld
local SCHEMA = 1
local MAX_RELATIONS = 64
local MAX_NEWS = 48
local state
local spreading = false

local eventDefinitions = {
    shared_warning = { delta = 5, text = "%s warned %s about danger moving through the area." },
    supply_exchange = { delta = 8, text = "%s and %s exchanged supplies." },
    medical_aid = { delta = 10, text = "%s provided emergency medical help to %s." },
    uneasy_contact = { delta = 1, text = "%s and %s made cautious contact." },
    boundary_dispute = { delta = -9, text = "%s and %s argued over territory and scavenging rights." },
}

local function freshState()
    return { schema = SCHEMA, serial = 0, version = 0, nextEventHour = nil,
        relations = {}, news = {} }
end

state = freshState()

local function finite(value, fallback)
    value = tonumber(value)
    if value == nil or value ~= value or value == math.huge or value == -math.huge then
        return fallback
    end
    return value
end

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, finite(value, minimum)))
end

local function worldHour()
    if type(getGameTime) == "function" then
        local ok, gameTime = pcall(getGameTime)
        if ok and gameTime ~= nil and SC.GameplayUtil
            and type(SC.GameplayUtil.call) == "function" then
            local hours, called = SC.GameplayUtil.call(gameTime, "getWorldAgeHours")
            if called and finite(hours, nil) ~= nil then return finite(hours, 0) end
        end
    end
    if SC.GameplayUtil and type(SC.GameplayUtil.nowMs) == "function" then
        return SC.GameplayUtil.nowMs() / 3600000
    end
    return os.clock() / 3600
end

local function stableCopy(value, depth, budget)
    return SC.StableValue.copyStrict(value, {
        maxDepth = tonumber(depth) or 8,
        maxEntries = type(budget) == "table" and budget.count or 4096,
        path = "$.factionWorld",
    })
end

local function appendBounded(list, value, maximum)
    list[#list + 1] = value
    while #list > maximum do table.remove(list, 1) end
end

local function group(id)
    return SC.Factions and type(SC.Factions.group) == "function"
        and SC.Factions.group(id) or nil
end

local function pairKey(leftId, rightId)
    if type(leftId) ~= "string" or type(rightId) ~= "string" or leftId == rightId then
        return nil
    end
    if leftId < rightId then return leftId .. "|" .. rightId, leftId, rightId end
    return rightId .. "|" .. leftId, rightId, leftId
end

local function relationStatus(score)
    score = finite(score, 0)
    if score <= -40 then return "Hostile" end
    if score <= -15 then return "Tense" end
    if score < 20 then return "Neutral" end
    if score < 50 then return "Cooperative" end
    return "Allied"
end

local function textHash(value)
    value = tostring(value or "")
    local result = 17
    for index = 1, #value do
        result = (result * 33 + string.byte(value, index)) % 2147483647
    end
    return result
end

local function initialScore(leftId, rightId)
    return (textHash(leftId .. ":" .. rightId) % 25) - 12
end

local function ensureRelation(leftId, rightId)
    local key, first, second = pairKey(leftId, rightId)
    if not key or not group(first) or not group(second) then return nil end
    local relation = state.relations[key]
    if relation == nil then
        local score = initialScore(first, second)
        relation = { key = key, leftId = first, rightId = second, score = score,
            status = relationStatus(score), contactCount = 0, lastEventHour = nil }
        state.relations[key] = relation
        state.version = state.version + 1
    end
    return relation
end

local function orderedGroups(livingOnly)
    local rows = SC.Factions and type(SC.Factions.list) == "function"
        and SC.Factions.list(false) or {}
    local result = {}
    for _, candidate in ipairs(rows) do
        if type(candidate) == "table" and type(candidate.id) == "string"
            and (not livingOnly or candidate.lifecycle ~= "destroyed") then
            result[#result + 1] = candidate
        end
    end
    table.sort(result, function(left, right) return left.id < right.id end)
    return result
end

local function ensureAllRelations()
    local rows = orderedGroups(true)
    for leftIndex = 1, #rows - 1 do
        for rightIndex = leftIndex + 1, #rows do
            ensureRelation(rows[leftIndex].id, rows[rightIndex].id)
        end
    end
    return rows
end

local function addHistory(target, entry)
    if type(target) ~= "table" then return end
    target.history = type(target.history) == "table" and target.history or {}
    appendBounded(target.history, entry, 256)
end

local function namesFor(relation)
    local left, right = group(relation.leftId), group(relation.rightId)
    return left and left.name or relation.leftId, right and right.name or relation.rightId
end

local function addNews(kind, relation, delta, message, hour)
    state.serial = state.serial + 1
    local left, right = group(relation.leftId), group(relation.rightId)
    local entry = {
        id = "world-news-" .. tostring(state.serial), kind = kind,
        hour = finite(hour, worldHour()), leftId = relation.leftId, rightId = relation.rightId,
        delta = finite(delta, 0), status = relation.status, message = tostring(message),
        known = left ~= nil and right ~= nil and left.discovered == true and right.discovered == true,
    }
    appendBounded(state.news, entry, MAX_NEWS)
    state.version = state.version + 1
    return entry
end

local function allowedEvents(status)
    if status == "Hostile" or status == "Tense" then
        return { "boundary_dispute", "shared_warning", "uneasy_contact" }
    end
    if status == "Cooperative" or status == "Allied" then
        return { "supply_exchange", "medical_aid", "shared_warning" }
    end
    return { "uneasy_contact", "shared_warning", "supply_exchange", "boundary_dispute" }
end

local function applyEvent(kind, relation, hour)
    local definition = eventDefinitions[kind]
    if not definition or type(relation) ~= "table" then return false, "invalid_world_event" end
    relation.score = clamp((finite(relation.score, 0) + definition.delta), -100, 100)
    relation.status = relationStatus(relation.score)
    relation.contactCount = math.max(0, math.floor(finite(relation.contactCount, 0))) + 1
    relation.lastEventHour = finite(hour, worldHour())
    local leftName, rightName = namesFor(relation)
    local message = string.format(definition.text, leftName, rightName)
    local entry = addNews(kind, relation, definition.delta, message, relation.lastEventHour)
    local history = { day = math.floor(relation.lastEventHour / 24), kind = "faction_world",
        event = kind, other = relation.rightId, delta = definition.delta }
    addHistory(group(relation.leftId), history)
    history = { day = math.floor(relation.lastEventHour / 24), kind = "faction_world",
        event = kind, other = relation.leftId, delta = definition.delta }
    addHistory(group(relation.rightId), history)
    return true, entry
end

local function relationCount(relations)
    local count = 0
    for _ in pairs(relations or {}) do count = count + 1 end
    return count
end

function World.reconcile()
    local rows = ensureAllRelations()
    for key, relation in pairs(state.relations) do
        if type(relation) ~= "table" or group(relation.leftId) == nil
            or group(relation.rightId) == nil then
            state.relations[key] = nil
            state.version = state.version + 1
        end
    end
    return true, #rows
end

-- Run a faction-world mutation as one in-memory transaction.  Faction restore
-- temporarily exposes its candidate groups so reconciliation can rebuild the
-- relation graph; if reconciliation or the final spawn cancellation fails,
-- none of those relation changes may leak into the live save.
function World.transaction(operation)
    if type(operation) ~= "function" then return false, "invalid_faction_world_transaction" end
    local copied, checkpoint, checkpointReason = pcall(stableCopy,
        state, 6, { count = 8192 })
    if not copied or checkpoint == nil then
        return false, "faction world checkpoint failed: "
            .. tostring(copied and checkpointReason or checkpoint)
    end
    local checkpointSpreading = spreading
    local called, accepted, result = pcall(operation)
    if not called or accepted ~= true then
        state, spreading = checkpoint, checkpointSpreading
        return false, tostring(called and (result or accepted) or accepted)
    end
    return true, result
end

function World.onGroupAdded(groupId)
    local added = type(groupId) == "table" and groupId or group(groupId)
    if not added or type(added.id) ~= "string" then return false, "faction_unavailable" end
    for _, other in ipairs(orderedGroups(true)) do
        if other.id ~= added.id then ensureRelation(added.id, other.id) end
    end
    return true
end

function World.onGroupRemoved(groupId)
    local changed = false
    for key, relation in pairs(state.relations) do
        if relation.leftId == groupId or relation.rightId == groupId then
            state.relations[key], changed = nil, true
        end
    end
    if changed then state.version = state.version + 1 end
    return true
end

function World.relation(leftId, rightId, create)
    local key = pairKey(leftId, rightId)
    if not key then return nil end
    if create == true then return ensureRelation(leftId, rightId) end
    return state.relations[key]
end

function World.pulse(currentHour)
    currentHour = finite(currentHour, worldHour())
    ensureAllRelations()
    local interval = SC.Config and type(SC.Config.get) == "function"
        and finite(SC.Config.get("factionWorldEventIntervalHours"), 24) or 24
    interval = math.max(1, interval)
    if state.nextEventHour == nil then
        state.nextEventHour = currentHour + interval
        return false, "world_event_scheduled"
    end
    if currentHour < state.nextEventHour then return false, "world_event_not_due" end
    state.nextEventHour = currentHour + interval
    local candidates = {}
    for _, relation in pairs(state.relations) do
        local left, right = group(relation.leftId), group(relation.rightId)
        if left and right and left.lifecycle ~= "destroyed" and right.lifecycle ~= "destroyed" then
            candidates[#candidates + 1] = relation
        end
    end
    table.sort(candidates, function(left, right) return left.key < right.key end)
    if #candidates == 0 then return false, "faction_pair_unavailable" end
    local relation = candidates[((state.serial + math.floor(currentHour)) % #candidates) + 1]
    local kinds = allowedEvents(relation.status)
    local kind = kinds[((textHash(relation.key) + state.serial + math.floor(currentHour)) % #kinds) + 1]
    return applyEvent(kind, relation, currentHour)
end

local function spreadStanding(sourceId, delta, reason)
    if spreading or finite(delta, 0) == 0 then return false, "no_world_reaction" end
    local source = group(sourceId)
    if not source or source.discovered ~= true then return false, "source_not_known" end
    local changed = 0
    spreading = true
    for _, relation in pairs(state.relations) do
        local otherId
        if relation.leftId == sourceId then otherId = relation.rightId
        elseif relation.rightId == sourceId then otherId = relation.leftId end
        local other = otherId and group(otherId) or nil
        if other and other.discovered == true and other.lifecycle ~= "destroyed" then
            local factor = relation.score >= 20 and 0.20
                or relation.score <= -20 and -0.08 or 0.05
            local raw = delta * factor
            local magnitude = math.floor(math.abs(raw) + 0.5)
            if magnitude == 0 and math.abs(delta) >= 10 then magnitude = 1 end
            local spill = math.min(6, magnitude) * (raw < 0 and -1 or 1)
            if magnitude > 0 and SC.Factions and type(SC.Factions.adjustStanding) == "function" then
                local ok, accepted = pcall(SC.Factions.adjustStanding, otherId, spill,
                    "word_travels:" .. tostring(reason or "player_action"))
                if ok and accepted == true then
                    changed = changed + 1
                    local sourceName = source.name or sourceId
                    local otherName = other.name or otherId
                    addNews("word_travels", relation, spill,
                        otherName .. " heard what happened with " .. sourceName .. ".",
                        worldHour())
                end
            end
        end
    end
    spreading = false
    return changed > 0, changed
end

function World.onStandingChanged(sourceId, delta, reason)
    if string.sub(tostring(reason or ""), 1, 13) == "word_travels:" then
        return false, "world_reaction_complete"
    end
    ensureAllRelations()
    return spreadStanding(sourceId, finite(delta, 0), reason)
end

function World.notePlayerAction(sourceId, kind, magnitude)
    local weights = { fair_trade = 8, promise_kept = 12, rescue = 20,
        theft = -30, damage = -45, murder = -100 }
    local delta = (weights[kind] or finite(magnitude, 0))
    return spreadStanding(sourceId, delta, kind)
end

function World.summary(groupId)
    local source = group(groupId)
    if not source then return nil end
    local relations, news = {}, {}
    for _, relation in pairs(state.relations) do
        local otherId
        if relation.leftId == groupId then otherId = relation.rightId
        elseif relation.rightId == groupId then otherId = relation.leftId end
        local other = otherId and group(otherId) or nil
        if other and other.discovered == true then
            relations[#relations + 1] = {
                id = otherId, name = other.name or otherId, score = relation.score,
                status = relation.status, contactCount = relation.contactCount,
                lastEventHour = relation.lastEventHour,
            }
        end
    end
    table.sort(relations, function(left, right) return left.name < right.name end)
    for index = #state.news, 1, -1 do
        local entry = state.news[index]
        if (entry.leftId == groupId or entry.rightId == groupId)
            and (entry.known == true or (group(entry.leftId) and group(entry.rightId)
                and group(entry.leftId).discovered == true
                and group(entry.rightId).discovered == true)) then
            news[#news + 1] = stableCopy(entry, 3)
            if #news >= 6 then break end
        end
    end
    return { relations = relations, news = news, relationCount = #relations,
        nextEventHour = state.nextEventHour, version = state.version }
end

function World.debugForceEvent(kind, leftId, rightId)
    if not SC.Config or type(SC.Config.get) ~= "function"
        or SC.Config.get("debugSpawnEnabled") ~= true then
        return false, "debug_tools_disabled"
    end
    local rows = orderedGroups(true)
    if leftId == nil and #rows >= 2 then leftId, rightId = rows[1].id, rows[2].id end
    local relation = ensureRelation(leftId, rightId)
    if not relation then return false, "faction_pair_unavailable" end
    local ok, result = applyEvent(kind, relation, worldHour())
    return ok, ok and result.message or result
end

function World.export()
    return stableCopy(state, 6, { count = 8192 })
end

local function restoreFailure(path, detail)
    return false, "invalid faction world state at " .. tostring(path) .. ": " .. tostring(detail)
end

local function finiteNumber(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

local function denseArray(value, path, maximum)
    if type(value) ~= "table" then return restoreFailure(path, "expected dense array") end
    local count, highest = 0, 0
    for key in pairs(value) do
        if type(key) ~= "number" or not finiteNumber(key) or key < 1
            or key ~= math.floor(key) then
            return restoreFailure(path .. "[" .. tostring(key) .. "]", "non-array key")
        end
        count, highest = count + 1, math.max(highest, key)
    end
    if highest ~= count then return restoreFailure(path, "sparse array") end
    if maximum ~= nil and count > maximum then return restoreFailure(path, "too many entries") end
    return true, count
end

function World.restore(document)
    if document == nil then
        local committed, reason = World.transaction(function()
            state, spreading = freshState(), false
            local reconciled, reconcileReason = World.reconcile()
            if reconciled ~= true then return false, reconcileReason end
            return true, "no_faction_world_state"
        end)
        return committed, reason
    end
    if type(document) ~= "table" or document.schema ~= SCHEMA then
        return false, "invalid_faction_world_state"
    end
    local source, copyReason = stableCopy(document, 6, { count = 8192 })
    if source == nil then return restoreFailure("$.factionWorld", copyReason or "copy failed") end
    if type(source.relations) ~= "table" then
        return restoreFailure("$.factionWorld.relations", "expected relation map")
    end
    if relationCount(source.relations) > MAX_RELATIONS then
        return restoreFailure("$.factionWorld.relations", "too many relations")
    end
    local newsOkay, newsCount = denseArray(source.news, "$.factionWorld.news", MAX_NEWS)
    if not newsOkay then return false, newsCount end
    if not finiteNumber(source.serial) or source.serial < 0
        or source.serial ~= math.floor(source.serial) then
        return restoreFailure("$.factionWorld.serial", "expected non-negative integer")
    end
    if not finiteNumber(source.version) or source.version < 0
        or source.version ~= math.floor(source.version) then
        return restoreFailure("$.factionWorld.version", "expected non-negative integer")
    end
    if source.nextEventHour ~= nil and not finiteNumber(source.nextEventHour) then
        return restoreFailure("$.factionWorld.nextEventHour", "expected finite number")
    end
    local restored = freshState()
    restored.serial = source.serial
    restored.version = source.version
    restored.nextEventHour = source.nextEventHour
    for key, relation in pairs(source.relations) do
        local path = "$.factionWorld.relations[" .. tostring(key) .. "]"
        if type(relation) ~= "table" then
            return restoreFailure(path, "expected relation")
        end
        local expected, leftId, rightId = pairKey(relation.leftId, relation.rightId)
        if type(key) ~= "string" or expected ~= key or not group(leftId) or not group(rightId)
            or not finiteNumber(relation.score)
            or relation.score < -100 or relation.score > 100
            or not finiteNumber(relation.contactCount) or relation.contactCount < 0
            or relation.contactCount ~= math.floor(relation.contactCount)
            or relation.status ~= relationStatus(relation.score)
            or (relation.lastEventHour ~= nil and not finiteNumber(relation.lastEventHour)) then
            return restoreFailure(path, "invalid relation or faction reference")
        end
        local clean = {
            key = key, leftId = leftId, rightId = rightId,
            score = relation.score, contactCount = relation.contactCount,
            lastEventHour = relation.lastEventHour,
        }
        clean.status = relationStatus(clean.score)
        restored.relations[key] = clean
    end
    for index = 1, newsCount do
        local entry = source.news[index]
        local path = "$.factionWorld.news[" .. tostring(index) .. "]"
        if type(entry) ~= "table" or type(entry.id) ~= "string"
            or type(entry.kind) ~= "string" or type(entry.message) ~= "string"
            or #entry.id > 96 or #entry.kind > 48 or #entry.message > 384
            or type(entry.leftId) ~= "string" or type(entry.rightId) ~= "string"
            or entry.leftId == entry.rightId or not finiteNumber(entry.hour)
            or not finiteNumber(entry.delta) or entry.delta < -100 or entry.delta > 100
            or type(entry.status) ~= "string" or type(entry.known) ~= "boolean" then
            return restoreFailure(path, "invalid world-news record")
        end
        appendBounded(restored.news, {
            id = string.sub(entry.id, 1, 96), kind = string.sub(entry.kind, 1, 48),
            hour = entry.hour, leftId = entry.leftId, rightId = entry.rightId,
            delta = entry.delta, status = entry.status,
            message = string.sub(entry.message, 1, 384), known = entry.known,
        }, MAX_NEWS)
    end
    local committed, reason = World.transaction(function()
        state, spreading = restored, false
        local reconciled, reconcileReason = World.reconcile()
        if reconciled ~= true then return false, reconcileReason end
        return true, relationCount(state.relations)
    end)
    return committed, reason
end

function World.reset()
    state = freshState()
    spreading = false
end

function World.version()
    return state.version
end

return World
