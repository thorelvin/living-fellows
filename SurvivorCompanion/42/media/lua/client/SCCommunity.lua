-- SPDX-License-Identifier: MIT

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
if not SC.GameplayUtil and type(require) == "function" then pcall(require, "SCGameplayUtil") end
if not SC.LifeEvents and type(require) == "function" then pcall(require, "SCLifeEvents") end

SC.Community = SC.Community or {}
local Community = SC.Community
Community.VERSION = 2

local document
local reservations = {}
local history

local stressLabels = {
    venter = "Venter", restless = "Restless", confronter = "Confronter",
    withdrawer = "Withdrawer", shutdown = "Shutdown",
}
local joyLabels = {
    focused = "Focused", rallying = "Rallying", caretaker = "Caretaker",
    organizer = "Organizer", bold = "Bold",
}

local function U() return SC.GameplayUtil end

local function finite(value, fallback)
    value = tonumber(value)
    if value == nil or value ~= value or value == math.huge or value == -math.huge then
        return fallback or 0
    end
    return value
end

local function clamp(value, low, high)
    value = finite(value, low)
    if value < low then return low end
    if value > high then return high end
    return value
end

local function clean(value, fallback, maximum)
    local result = type(value) == "string" and value or fallback or ""
    result = string.gsub(result, "[\r\n\t]", " ")
    if maximum and #result > maximum then result = string.sub(result, 1, maximum) end
    return result
end

local function stableCopy(value, depth, remaining)
    remaining = remaining or { count = 4096 }
    if remaining.count <= 0 then return nil end
    local kind = type(value)
    if kind == "string" or kind == "boolean" then
        remaining.count = remaining.count - 1
        return value
    elseif kind == "number" then
        remaining.count = remaining.count - 1
        return finite(value, 0)
    elseif kind ~= "table" or (depth or 0) <= 0 then
        return nil
    end
    remaining.count = remaining.count - 1
    local result = {}
    for key, child in pairs(value) do
        if type(key) == "string" or type(key) == "number" then
            local copied = stableCopy(child, depth - 1, remaining)
            if copied ~= nil then result[key] = copied end
            if remaining.count <= 0 then break end
        end
    end
    return result
end

local function now()
    if SC.LifeEvents and type(SC.LifeEvents.now) == "function" then return SC.LifeEvents.now() end
    return U() and U().nowMs() or 0
end

local function hours(value) return math.floor(finite(value, 0) * 3600000) end
local function minutes(value) return math.floor(finite(value, 0) * 60000) end

local function emptyDocument()
    return {
        version = Community.VERSION,
        minds = {}, pairs = {}, history = {}, deaths = {},
        groupMajorCooldownUntil = 0,
        groupJoyCooldownUntil = 0,
        lastSupplyRunAt = now(),
        activeRun = nil,
        playerAtBase = nil,
    }
end

local function ensure()
    if type(document) ~= "table" then document = emptyDocument() end
    return document
end

local function idOf(value)
    if type(value) == "string" then return clean(value, "", 80) end
    if value == nil then return nil end
    return U() and U().idOf(value) or nil
end

local function responseProfile(id, state)
    local profile = type(state) == "table" and type(state.personalityProfile) == "table"
        and state.personalityProfile or {}
    local courage = clamp(profile.courage, 0, 100)
    local caution = clamp(profile.caution, 0, 100)
    local compassion = clamp(profile.compassion, 0, 100)
    local practicality = clamp(profile.practicality, 0, 100)
    local stressResponse = "venter"
    local strongest = compassion
    if courage > strongest then stressResponse, strongest = "confronter", courage end
    if caution > strongest then stressResponse, strongest = "withdrawer", caution end
    if practicality > strongest then stressResponse = "restless" end
    -- A shutdown is a distinct, uncommon response rather than a universal
    -- low-morale animation. Keep it deterministic so a survivor's temperament
    -- remains stable across save/load and restarts.
    if courage < 75 and (U().stableHash(tostring(id) .. ":shutdown") % 5) == 0 then
        stressResponse = "shutdown"
    end

    local joyResponse = "rallying"
    strongest = courage
    if compassion > strongest then joyResponse, strongest = "caretaker", compassion end
    if practicality > strongest then
        joyResponse, strongest = ((U().stableHash(tostring(id) .. ":joy") % 2) == 0)
            and "organizer" or "focused", practicality
    end
    if caution > strongest then joyResponse = "focused" end
    if courage >= 80 and courage > caution + 12 then joyResponse = "bold" end

    local impatience = (U().stableHash(tostring(id) .. ":impatience") % 61) + 20
        + math.floor((courage - caution) * 0.15)
    return stressResponse, joyResponse, clamp(impatience, 0, 100)
end

local function normalizeThought(source)
    if type(source) ~= "table" then return nil end
    local key = clean(source.key or source.kind, "thought", 64)
    if key == "" then return nil end
    local at = math.max(0, math.floor(finite(source.at, now())))
    return {
        key = key,
        kind = clean(source.kind, key, 48),
        text = clean(source.text, key, 160),
        stress = clamp(source.stress, -100, 100),
        morale = clamp(source.morale, -100, 100),
        at = at,
        expiresAt = math.max(at, math.floor(finite(source.expiresAt, at + hours(6)))),
        sourceId = clean(source.sourceId, "", 80),
        targetId = clean(source.targetId, "", 80),
        memoryId = clean(source.memoryId, "", 80),
    }
end

local function normalizeGrief(source)
    if type(source) ~= "table" then return nil end
    local subjectId = clean(source.subjectId, "", 80)
    if subjectId == "" then return nil end
    local startedAt = math.max(0, math.floor(finite(source.startedAt, now())))
    local acuteUntil = math.max(startedAt, math.floor(finite(source.acuteUntil,
        startedAt + hours(24))))
    return {
        subjectId = subjectId,
        subjectName = clean(source.subjectName, "Survivor", 80),
        startedAt = startedAt,
        acuteUntil = acuteUntil,
        recoveryAt = math.max(acuteUntil, math.floor(finite(source.recoveryAt,
            acuteUntil + hours(24 * 6)))),
        intensity = clamp(source.intensity, 0, 100),
        witnessed = source.witnessed == true,
        reactionPending = source.reactionPending == true,
        nextReactionAt = math.max(startedAt, math.floor(finite(source.nextReactionAt, startedAt))),
        reactedAt = math.max(0, math.floor(finite(source.reactedAt, 0))),
        resolvedAt = math.max(0, math.floor(finite(source.resolvedAt, 0))),
    }
end

local function normalizeMind(id, source, state)
    source = type(source) == "table" and source or {}
    local stressResponse, joyResponse, impatience = responseProfile(id, state)
    local validStress = { venter = true, restless = true, confronter = true,
        withdrawer = true, shutdown = true }
    local validJoy = { focused = true, rallying = true, caretaker = true,
        organizer = true, bold = true }
    local result = {
        id = id,
        stressResponse = validStress[source.stressResponse] and source.stressResponse or stressResponse,
        joyResponse = validJoy[source.joyResponse] and source.joyResponse or joyResponse,
        impatience = clamp(source.impatience == nil and impatience or source.impatience, 0, 100),
        boredom = clamp(source.boredom, 0, 100),
        thoughts = {}, expectations = {}, grief = {},
        lastEvaluatedAt = math.max(0, finite(source.lastEvaluatedAt, 0)),
        criticalSince = finite(source.criticalSince, 0),
        hopefulSince = finite(source.hopefulSince, 0),
        nextMinorAt = math.max(0, finite(source.nextMinorAt, 0)),
        nextMajorAt = math.max(0, finite(source.nextMajorAt, 0)),
        nextJoyAt = math.max(0, finite(source.nextJoyAt, 0)),
        nextPurposeAt = math.max(0, finite(source.nextPurposeAt, 0)),
        lastSupplyRequestAt = math.max(0, finite(source.lastSupplyRequestAt, 0)),
        activeEpisode = nil,
        inspiration = type(source.inspiration) == "table" and stableCopy(source.inspiration, 2,
            { count = 16 }) or nil,
        pendingRequest = type(source.pendingRequest) == "table" and stableCopy(source.pendingRequest, 3,
            { count = 32 }) or nil,
        stressTarget = clamp(source.stressTarget == nil and 12 or source.stressTarget, 0, 100),
        moraleTarget = clamp(source.moraleTarget == nil and 55 or source.moraleTarget, 0, 100),
    }
    for _, thought in ipairs(type(source.thoughts) == "table" and source.thoughts or {}) do
        local normalized = normalizeThought(thought)
        if normalized then result.thoughts[#result.thoughts + 1] = normalized end
        if #result.thoughts >= (U().config("mindThoughtLimit") or 12) then break end
    end
    for _, expectation in ipairs(type(source.expectations) == "table" and source.expectations or {}) do
        if type(expectation) == "table" and type(expectation.kind) == "string" then
            result.expectations[#result.expectations + 1] = {
                kind = clean(expectation.kind, "promise", 48),
                madeAt = math.max(0, finite(expectation.madeAt, now())),
                dueAt = math.max(0, finite(expectation.dueAt, now())),
                status = expectation.status == "fulfilled" and "fulfilled"
                    or expectation.status == "broken" and "broken" or "pending",
            }
            if #result.expectations >= 8 then break end
        end
    end
    for _, grief in ipairs(type(source.grief) == "table" and source.grief or {}) do
        local normalized = normalizeGrief(grief)
        if normalized then result.grief[#result.grief + 1] = normalized end
        if #result.grief >= (U().config("griefMemoryLimit") or 8) then break end
    end
    return result
end

function Community.mindFor(actorOrId, state)
    local id = idOf(actorOrId)
    if not id or id == "" then return nil end
    local source = ensure().minds[id]
    if type(source) ~= "table" then
        source = normalizeMind(id, nil, state)
        ensure().minds[id] = source
    end
    return source
end

function Community.peekMind(actorOrId)
    local id = idOf(actorOrId)
    if not id or id == "" or type(document) ~= "table"
        or type(document.minds) ~= "table" then return nil end
    return document.minds[id]
end

local function thoughtIndex(mind, key)
    for index, thought in ipairs(mind.thoughts or {}) do
        if thought.key == key then return index, thought end
    end
    return nil, nil
end

function Community.removeThought(actorOrId, key)
    local mind = Community.mindFor(actorOrId)
    if not mind then return false end
    local index = thoughtIndex(mind, key)
    if not index then return false end
    table.remove(mind.thoughts, index)
    return true
end

function Community.addThought(actorOrId, specification)
    local mind = Community.mindFor(actorOrId)
    if not mind then return nil, "unknown_companion" end
    local thought = normalizeThought(specification)
    if not thought then return nil, "invalid_thought" end
    local index = thoughtIndex(mind, thought.key)
    if index then mind.thoughts[index] = thought else mind.thoughts[#mind.thoughts + 1] = thought end
    table.sort(mind.thoughts, function(left, right)
        local leftImpact = math.abs(left.stress) + math.abs(left.morale)
        local rightImpact = math.abs(right.stress) + math.abs(right.morale)
        if leftImpact == rightImpact then return left.at > right.at end
        return leftImpact > rightImpact
    end)
    local limit = U().config("mindThoughtLimit") or 12
    while #mind.thoughts > limit do table.remove(mind.thoughts) end
    return thought
end

local function commandState(actor)
    if actor and SC.Commands and type(SC.Commands.peek) == "function" then
        local ok, state = pcall(SC.Commands.peek, actor)
        if ok and type(state) == "table" then return state end
    end
    return nil
end

local function persistActor(actor)
    if actor and SC.Commands and type(SC.Commands.persist) == "function" then
        pcall(SC.Commands.persist, actor)
    end
end

local function deathName(record)
    local identity = type(record) == "table" and type(record.identity) == "table"
        and record.identity or nil
    if identity then
        local first = clean(identity.forename, "", 40)
        local last = clean(identity.surname, "", 40)
        local combined = clean(first .. (first ~= "" and last ~= "" and " " or "") .. last,
            "", 80)
        if combined ~= "" then return combined end
    end
    if type(record) == "table" and record.actor and U() then
        return clean(U().nameOf(record.actor), "Survivor", 80)
    end
    return "Survivor"
end

local function rememberDeath(row)
    local deaths = ensure().deaths
    deaths[row.subjectId] = stableCopy(row, 3, { count = 32 })
    local ordered = {}
    for id, death in pairs(deaths) do
        ordered[#ordered + 1] = { id = id, at = finite(death.startedAt, 0) }
    end
    table.sort(ordered, function(left, right)
        if left.at == right.at then return left.id < right.id end
        return left.at > right.at
    end)
    local limit = U().config("griefDeathHistoryLimit") or 32
    for index = limit + 1, #ordered do deaths[ordered[index].id] = nil end
end

function Community.griefIntensity(grief, current)
    if type(grief) ~= "table" then return 0 end
    current = finite(current, now())
    local original = clamp(grief.intensity, 0, 100)
    if current <= finite(grief.acuteUntil, current) then return original end
    local recoveryAt = finite(grief.recoveryAt, current)
    if current >= recoveryAt then return 0 end
    local span = math.max(1, recoveryAt - finite(grief.acuteUntil, current))
    return clamp(original * 0.7 * ((recoveryAt - current) / span), 0, 100)
end

function Community.activeGrief(actorOrId)
    local mind = Community.peekMind(actorOrId)
    if not mind then return nil end
    local current, selected, selectedScore = now(), nil, -1
    for _, grief in ipairs(mind.grief or {}) do
        local score = Community.griefIntensity(grief, current)
        if score > selectedScore then selected, selectedScore = grief, score end
    end
    if not selected or selectedScore <= 0 then return nil end
    local result = stableCopy(selected, 3, { count = 32 }) or {}
    result.currentIntensity = math.floor(selectedScore + 0.5)
    result.stage = current <= finite(selected.acuteUntil, current) and "acute" or "recovering"
    return result
end

function Community.finishGriefReaction(actorOrId, subjectId)
    local mind = Community.mindFor(actorOrId)
    if not mind then return false, "mind_unavailable" end
    for _, grief in ipairs(mind.grief or {}) do
        if grief.subjectId == subjectId then
            grief.reactionPending = false
            grief.reactedAt = now()
            return true, "grief_reaction_finished"
        end
    end
    return false, "grief_unavailable"
end

function Community.noteCompanionDeath(record)
    if type(record) ~= "table" or type(record.id) ~= "string" then
        return false, "invalid_death_record"
    end
    local deceasedState = commandState(record.actor)
    if record.recruited ~= true and not (deceasedState and deceasedState.recruited == true) then
        return false, "not_recruited_death"
    end
    ensure().deaths = type(ensure().deaths) == "table" and ensure().deaths or {}
    if ensure().deaths[record.id] then return false, "death_already_recorded" end

    local current = now()
    local name = deathName(record)
    rememberDeath({ subjectId = record.id, subjectName = name, startedAt = current })
    local affected = 0
    -- The registry also contains neutral encounters and loaded faction actors.
    -- Scan a bounded superset so those records cannot push a recruited teammate
    -- out of a maxCompanions-sized prefix.
    for _, actor in ipairs(U().registryLiving(math.max(128,
        tonumber(U().config("maxCompanions")) or 16))) do
        local survivorId = U().idOf(actor)
        local state = commandState(actor)
        if survivorId and survivorId ~= record.id and not U().isDead(actor)
            and state and state.recruited == true then
            local pair = Community.relation(survivorId, record.id, false)
            local familiarity = clamp(pair and pair.familiarity or 0, 0, 100)
            local trust = clamp(pair and pair.trust or 0, -100, 100)
            local opinion = clamp(pair and pair.opinion or 0, -100, 100)
            local witnessed = record.actor ~= nil and U().sameFloor(actor, record.actor)
                and U().distance(actor, record.actor) <= 14
            local intensity = clamp(30 + familiarity * 0.38 + math.max(0, trust) * 0.2
                + math.max(0, opinion) * 0.08 + (witnessed and 18 or 0), 25, 100)
            local acuteMin = finite(U().config("griefAcuteMinHours"), 18)
            local acuteMax = math.max(acuteMin, finite(U().config("griefAcuteMaxHours"), 72))
            local recoveryMin = finite(U().config("griefRecoveryMinDays"), 5)
            local recoveryMax = math.max(recoveryMin, finite(U().config("griefRecoveryMaxDays"), 18))
            local acuteHours = acuteMin + (acuteMax - acuteMin) * intensity / 100
            local recoveryDays = recoveryMin + (recoveryMax - recoveryMin) * intensity / 100
            local mind = Community.mindFor(actor, state)
            local grief = {
                subjectId = record.id, subjectName = name, startedAt = current,
                acuteUntil = current + hours(acuteHours),
                recoveryAt = current + hours(recoveryDays * 24),
                intensity = intensity, witnessed = witnessed,
                reactionPending = true,
                nextReactionAt = current + minutes(2 + (U().stableHash(
                    survivorId .. ":grief:" .. record.id) % math.max(1,
                        math.floor(finite(U().config("griefReactionDelayGameMinutes"), 12))))),
                reactedAt = 0, resolvedAt = 0,
            }
            local replaced = false
            for index, prior in ipairs(mind.grief or {}) do
                if prior.subjectId == record.id then mind.grief[index], replaced = grief, true break end
            end
            if not replaced then mind.grief[#mind.grief + 1] = grief end
            table.sort(mind.grief, function(left, right)
                return finite(left.startedAt, 0) > finite(right.startedAt, 0)
            end)
            while #mind.grief > (U().config("griefMemoryLimit") or 8) do table.remove(mind.grief) end
            Community.addThought(actor, {
                key = "grief:" .. record.id, kind = "companion_died",
                text = name .. " died. I am still trying to take that in.",
                stress = math.floor(10 + intensity * 0.28),
                morale = -math.floor(8 + intensity * 0.3),
                at = current, expiresAt = grief.acuteUntil,
                sourceId = record.id, targetId = survivorId,
            })
            Community.adjustRelation(survivorId, record.id, {
                familiarity = 2,
                memory = { kind = "companion_died", at = current,
                    subjectId = record.id, subjectName = name, witnessed = witnessed },
            })
            if SC.Relationship and type(SC.Relationship.noteEvent) == "function" then
                pcall(SC.Relationship.noteEvent, state, "companion_died", {
                    at = current, morale = -math.floor(5 + intensity * 0.12),
                    stress = math.floor(5 + intensity * 0.1),
                    subjectId = record.id, subjectName = name, witnessed = witnessed,
                })
            end
            persistActor(actor)
            affected = affected + 1
        end
    end
    history({ id = "death:" .. record.id .. ":" .. tostring(current),
        kind = "companion_died", at = current, sourceId = record.id,
        subjectName = name, affected = affected })
    return true, { affected = affected, subjectId = record.id, subjectName = name }
end

local function upsertCondition(actor, key, amount, morale, textValue, current)
    if amount <= 0.05 and math.abs(morale or 0) <= 0.05 then
        Community.removeThought(actor, key)
        return
    end
    Community.addThought(actor, {
        key = key, kind = "condition", text = textValue,
        stress = amount, morale = morale or 0, at = current,
        expiresAt = current + minutes((U().config("mindSampleGameMinutes") or 10) * 2.5),
    })
end

local function refreshGrief(actor, mind, current)
    for _, grief in ipairs(mind.grief or {}) do
        local intensity = Community.griefIntensity(grief, current)
        local key = "grief:" .. tostring(grief.subjectId)
        if intensity <= 0 then
            if finite(grief.resolvedAt, 0) <= 0 then grief.resolvedAt = current end
            grief.reactionPending = false
            Community.removeThought(actor, key)
        else
            local acute = current <= finite(grief.acuteUntil, current)
            Community.addThought(actor, {
                key = key, kind = "companion_died",
                text = acute and (tostring(grief.subjectName) .. " is dead. It still does not feel real.")
                    or ("I still miss " .. tostring(grief.subjectName) .. "."),
                stress = math.floor((acute and 7 or 2) + intensity * (acute and 0.26 or 0.1)),
                morale = -math.floor((acute and 6 or 2) + intensity * (acute and 0.28 or 0.12)),
                at = grief.startedAt, expiresAt = current + minutes(
                    (U().config("mindSampleGameMinutes") or 10) * 2.5),
                sourceId = grief.subjectId, targetId = mind.id,
            })
        end
    end
end

local function pairKey(first, second)
    first, second = idOf(first), idOf(second)
    if not first or not second or first == second then return nil end
    if first > second then first, second = second, first end
    return first .. "|" .. second, first, second
end

function Community.relation(first, second, create)
    local key, left, right = pairKey(first, second)
    if not key then return nil end
    local pair = ensure().pairs[key]
    if type(pair) ~= "table" and create ~= false then
        pair = {
            id = key, firstId = left, secondId = right,
            opinion = 0, trust = 0, tension = 0, familiarity = 0,
            lastInteractionAt = 0, memories = {},
        }
        ensure().pairs[key] = pair
        local count, oldestKey, oldestAt = 0, nil, math.huge
        for candidateKey, candidate in pairs(ensure().pairs) do
            count = count + 1
            local touched = finite(type(candidate) == "table" and candidate.lastInteractionAt, 0)
            if candidateKey ~= key and (touched < oldestAt
                or (touched == oldestAt and (oldestKey == nil or candidateKey < oldestKey))) then
                oldestKey, oldestAt = candidateKey, touched
            end
        end
        local limit = U().config("mindPairLimit") or 64
        if count > limit and oldestKey then ensure().pairs[oldestKey] = nil end
    end
    return pair
end

function Community.adjustRelation(first, second, changes)
    local pair = Community.relation(first, second, true)
    if not pair then return nil end
    changes = type(changes) == "table" and changes or {}
    pair.opinion = clamp(finite(pair.opinion, 0) + finite(changes.opinion, 0), -100, 100)
    pair.trust = clamp(finite(pair.trust, 0) + finite(changes.trust, 0), -100, 100)
    pair.tension = clamp(finite(pair.tension, 0) + finite(changes.tension, 0), 0, 100)
    pair.familiarity = clamp(finite(pair.familiarity, 0) + finite(changes.familiarity, 0), 0, 100)
    pair.lastInteractionAt = now()
    if type(changes.memory) == "table" then
        pair.memories[#pair.memories + 1] = stableCopy(changes.memory, 3, { count = 32 })
        local limit = U().config("mindPairMemoryLimit") or 8
        while #pair.memories > limit do table.remove(pair.memories, 1) end
    end
    return pair
end

function Community.latestSharedMemory(first, second)
    local pair = Community.relation(first, second, false)
    return pair and pair.memories and pair.memories[#pair.memories] or nil
end

local eventEffects = {
    companion_hurt = { stress = 18, morale = -6, opinion = 1, tension = 4 },
    witnessed_injury = { stress = 14, morale = -5, opinion = 2, tension = 2 },
    shared_escape = { stress = -8, morale = 8, opinion = 5, trust = 4, tension = -6 },
    rescued_player = { stress = -4, morale = 7, opinion = 3, trust = 3 },
    worked = { stress = -1, morale = 3, opinion = 1 },
    supply_run_completed = { stress = -8, morale = 9, opinion = 4, trust = 3, tension = -8 },
    supply_run_rough = { stress = 12, morale = -5, opinion = -2, tension = 10 },
    promise_broken = { stress = 14, morale = -8 },
    argument = { stress = 10, morale = -4, opinion = -10, tension = 18 },
    social_fight = { stress = 18, morale = -8, opinion = -20, tension = 25 },
    reconciled = { stress = -10, morale = 6, opinion = 8, trust = 5, tension = -20 },
    encouraged = { stress = -10, morale = 6 },
    joy_shared = { stress = -5, morale = 8, opinion = 4, tension = -5 },
}

local function eventThoughtText(row)
    local texts = {
        companion_hurt = "I was hurt while we were together.",
        witnessed_injury = "I watched someone get hurt.",
        shared_escape = "We barely made it back together.",
        rescued_player = "We pulled someone out of danger.",
        worked = "Useful work made this place feel more secure.",
        supply_run_completed = "The last supply run brought us home together.",
        supply_run_rough = "The last run went badly.",
        promise_broken = "The promised supply run never happened.",
        argument = "That argument is still sitting with me.",
        social_fight = "Things between us became physical.",
        reconciled = "We faced the problem instead of letting it grow.",
        encouraged = "Someone took the time to steady me.",
        joy_shared = "Someone's good mood lifted the room.",
    }
    return clean(row.text, texts[row.kind] or "Something happened that I cannot ignore.", 160)
end

history = function(row)
    local copy = stableCopy(row, 4, { count = 96 }) or {}
    ensure().history[#ensure().history + 1] = copy
    local limit = U().config("mindHistoryLimit") or 96
    while #ensure().history > limit do table.remove(ensure().history, 1) end
    if SC.BaseLife and type(SC.BaseLife.noteHistory) == "function" then
        pcall(SC.BaseLife.noteHistory, "community_" .. tostring(row.kind), copy)
    end
end

local function fulfillSupplyExpectation(id, eventTime)
    local mind = Community.mindFor(id)
    if not mind then return end
    for _, expectation in ipairs(mind.expectations or {}) do
        if expectation.kind == "supply_run" and expectation.status == "pending" then
            expectation.status = "fulfilled"
            expectation.fulfilledAt = eventTime
            Community.addThought(id, {
                key = "promise_kept:" .. tostring(expectation.madeAt), kind = "promise_kept",
                text = "The promised supply run happened.", stress = -8, morale = 10,
                at = eventTime, expiresAt = eventTime + hours(24),
            })
        end
    end
end

function Community.processEvents(limit)
    if not SC.LifeEvents or type(SC.LifeEvents.drain) ~= "function" then return 0 end
    local events = SC.LifeEvents.drain(limit or 32)
    for _, row in ipairs(events) do
        local effect = eventEffects[row.kind] or { stress = 2, morale = 0 }
        for _, id in ipairs(row.participants or {}) do
            if string.sub(id, 1, 3) == "sc-" then
                Community.addThought(id, {
                    key = tostring(row.id) .. ":" .. id,
                    kind = row.kind, text = eventThoughtText(row),
                    stress = effect.stress or 0, morale = effect.morale or 0,
                    at = row.at, expiresAt = row.at + hours(row.kind == "social_fight" and 48 or 24),
                    sourceId = row.sourceId, targetId = row.targetId, memoryId = row.id,
                })
                if row.kind == "supply_run_completed" then fulfillSupplyExpectation(id, row.at) end
            end
        end
        local participants = row.participants or {}
        for firstIndex = 1, #participants do
            for secondIndex = firstIndex + 1, #participants do
                local first, second = participants[firstIndex], participants[secondIndex]
                if string.sub(first, 1, 3) == "sc-" and string.sub(second, 1, 3) == "sc-" then
                    Community.adjustRelation(first, second, {
                        opinion = effect.opinion, trust = effect.trust,
                        tension = effect.tension, familiarity = 2,
                        memory = {
                            id = row.id, kind = row.kind, at = row.at,
                            text = eventThoughtText(row),
                        },
                    })
                end
            end
        end
        history(row)
    end
    return #events
end

local function highestTension(id)
    local highest = 0
    for _, pair in pairs(ensure().pairs) do
        if pair.firstId == id or pair.secondId == id then
            highest = math.max(highest, finite(pair.tension, 0))
        end
    end
    return highest
end

function Community.updateMind(actor, state, snapshot, context)
    if actor == nil or type(state) ~= "table" then return false, "invalid_mind_subject" end
    local mind = Community.mindFor(actor, state)
    if not mind then return false, "mind_unavailable" end
    local current = now()
    local interval = minutes(U().config("mindSampleGameMinutes") or 10)
    if mind.lastEvaluatedAt > 0 and current - mind.lastEvaluatedAt < interval then
        return false, "mind_sample_deferred"
    end
    local elapsed = mind.lastEvaluatedAt > 0 and math.max(interval,
        math.min(hours(1), current - mind.lastEvaluatedAt)) or interval
    mind.lastEvaluatedAt = current
    refreshGrief(actor, mind, current)
    for index = #mind.thoughts, 1, -1 do
        if finite(mind.thoughts[index].expiresAt, 0) <= current then table.remove(mind.thoughts, index) end
    end

    local health = U().nativeHealth(actor)
    local hunger = U().characterStatValue(actor, "HUNGER", 0)
    local thirst = U().characterStatValue(actor, "THIRST", 0)
    local _, _, loadRatio = U().inventoryLoad(actor)
    local threats = finite(snapshot and (snapshot.threatCount or snapshot.immediateCount), 0)
    upsertCondition(actor, "condition:injury", health < 80 and (80 - health) * 0.38 or 0,
        health < 55 and -7 or 0, "My injuries are wearing me down.", current)
    upsertCondition(actor, "condition:hunger", hunger > 0.4 and (hunger - 0.4) * 38 or 0,
        hunger > 0.65 and -5 or 0, "I need a proper meal.", current)
    upsertCondition(actor, "condition:thirst", thirst > 0.35 and (thirst - 0.35) * 48 or 0,
        thirst > 0.6 and -6 or 0, "I need clean water.", current)
    upsertCondition(actor, "condition:load", loadRatio > 0.85 and math.min(18, (loadRatio - 0.85) * 42) or 0,
        0, "This load is exhausting me.", current)
    upsertCondition(actor, "condition:danger", threats > 0 and math.min(30, 8 + threats * 4) or 0,
        threats > 0 and -4 or 0, "The dead are too close.", current)
    local tension = highestTension(mind.id)
    upsertCondition(actor, "condition:tension", tension > 40 and (tension - 40) * 0.35 or 0,
        tension > 65 and -5 or 0, "There is unresolved tension in the group.", current)

    context = type(context) == "table" and context or {}
    if context.idle == true and threats <= 0 then
        mind.boredom = clamp(mind.boredom + elapsed / minutes(U().config("mindBoredGameMinutes") or 45) * 45,
            0, 100)
    else
        mind.boredom = clamp(mind.boredom - elapsed / minutes(20) * 35, 0, 100)
    end
    upsertCondition(actor, "condition:boredom", mind.boredom >= 45 and (mind.boredom - 35) * 0.18 or 0,
        mind.boredom >= 70 and -2 or 0, "Waiting without a purpose is getting to me.", current)

    for _, expectation in ipairs(mind.expectations) do
        if expectation.status == "pending" and current > expectation.dueAt then
            expectation.status = "broken"
            Community.addThought(actor, {
                key = "promise_broken:" .. tostring(expectation.madeAt), kind = "promise_broken",
                text = "The promised supply run never happened.", stress = 14, morale = -8,
                at = current, expiresAt = current + hours(48),
            })
            if SC.LifeEvents then SC.LifeEvents.emit("promise_broken", {
                participants = { mind.id }, sourceId = "player:local",
            }) end
        end
    end
    if mind.pendingRequest and current >= finite(mind.pendingRequest.expiresAt, current) then
        Community.addThought(actor, {
            key = "request_unanswered:" .. tostring(mind.pendingRequest.askedAt),
            kind = "request_unanswered", text = "My request was left unanswered.",
            stress = 4, morale = -3, at = current, expiresAt = current + hours(12),
        })
        mind.pendingRequest = nil
    end

    local stressTarget, moraleTarget = 12, 55
    for _, thought in ipairs(mind.thoughts) do
        stressTarget = stressTarget + finite(thought.stress, 0)
        moraleTarget = moraleTarget + finite(thought.morale, 0)
    end
    stressTarget = clamp(stressTarget, 0, 100)
    moraleTarget = clamp(moraleTarget - math.max(0, stressTarget - 50) * 0.25, 0, 100)
    mind.stressTarget, mind.moraleTarget = stressTarget, moraleTarget
    local sampleScale = clamp(elapsed / interval, 1, 6)
    local function approach(value, target, maximumStep)
        value = finite(value, target)
        local delta = target - value
        if delta > maximumStep then delta = maximumStep elseif delta < -maximumStep then delta = -maximumStep end
        return clamp(value + delta, 0, 100)
    end
    state.stress = approach(state.stress, stressTarget, 3 * sampleScale)
    state.morale = approach(state.morale, moraleTarget, 2 * sampleScale)

    if state.stress >= (U().config("mindMajorStress") or 82) then
        if mind.criticalSince <= 0 then mind.criticalSince = current end
    else
        mind.criticalSince = 0
    end
    if state.morale >= (U().config("mindJoyMorale") or 82)
        and state.stress <= (U().config("mindJoyMaximumStress") or 25) then
        if mind.hopefulSince <= 0 then mind.hopefulSince = current end
    else
        mind.hopefulSince = 0
    end
    if mind.inspiration and current >= finite(mind.inspiration.untilAt, 0) then mind.inspiration = nil end
    return true, "mind_updated"
end

function Community.topThoughts(actorOrId, limit)
    local mind = Community.mindFor(actorOrId)
    local result = {}
    if not mind then return result end
    limit = math.max(1, math.min(6, math.floor(finite(limit, 3))))
    for index = 1, math.min(limit, #mind.thoughts) do
        result[#result + 1] = mind.thoughts[index].text
    end
    return result
end

function Community.summary(actorOrId)
    -- UI description is intentionally read-only: opening the menu must not
    -- manufacture persistent simulation state for an unknown actor.
    local mind = Community.peekMind(actorOrId)
    if not mind then return nil end
    local expectation = nil
    for _, value in ipairs(mind.expectations) do
        if value.status == "pending" then expectation = value.kind break end
    end
    local grief = Community.activeGrief(actorOrId)
    return {
        stressResponse = mind.stressResponse,
        stressResponseLabel = stressLabels[mind.stressResponse] or mind.stressResponse,
        joyResponse = mind.joyResponse,
        joyResponseLabel = joyLabels[mind.joyResponse] or mind.joyResponse,
        boredom = mind.boredom,
        stressTarget = mind.stressTarget,
        moraleTarget = mind.moraleTarget,
        topThoughts = Community.topThoughts(actorOrId, 3),
        currentExpectation = expectation,
        activeEpisode = mind.activeEpisode,
        inspiration = mind.inspiration and mind.inspiration.kind or nil,
        pendingRequest = stableCopy(mind.pendingRequest, 3, { count = 32 }),
        grief = grief,
        lossCount = #(mind.grief or {}),
    }
end

function Community.reserve(ownerId, participantIds, untilAt)
    ownerId = idOf(ownerId)
    if not ownerId or type(participantIds) ~= "table" then return false, "invalid_reservation" end
    local current = U().nowMs()
    for _, participantId in ipairs(participantIds) do
        local id = idOf(participantId)
        local held = id and reservations[id] or nil
        if held and held.untilAt > current and held.ownerId ~= ownerId then
            return false, "participant_reserved"
        end
    end
    for _, participantId in ipairs(participantIds) do
        local id = idOf(participantId)
        if id then reservations[id] = { ownerId = ownerId, untilAt = untilAt or current + 15000 } end
    end
    return true, "participants_reserved"
end

function Community.reservationFor(actorOrId)
    local id = idOf(actorOrId)
    local held = id and reservations[id] or nil
    if held and held.untilAt <= U().nowMs() then reservations[id], held = nil, nil end
    return held
end

function Community.release(ownerId)
    ownerId = idOf(ownerId)
    for id, held in pairs(reservations) do
        if held.ownerId == ownerId then reservations[id] = nil end
    end
end

function Community.groupMajorReady(current)
    return (current or now()) >= finite(ensure().groupMajorCooldownUntil, 0)
end

function Community.beginMajor(actorOrId, kind)
    local mind = Community.mindFor(actorOrId)
    if not mind then return false end
    local current = now()
    mind.activeEpisode = clean(kind, "breakdown", 48)
    mind.nextMajorAt = current + hours(U().config("mindMajorCooldownGameHours") or 96)
    ensure().groupMajorCooldownUntil = current + hours(U().config("mindGroupCooldownGameHours") or 60)
    return true
end

function Community.finishMajor(actorOrId)
    local mind = Community.mindFor(actorOrId)
    if not mind then return false end
    mind.activeEpisode, mind.criticalSince = nil, 0
    return true
end

function Community.joyReady(actorOrId, state)
    local mind = Community.mindFor(actorOrId, state)
    local current = now()
    return mind and mind.hopefulSince > 0
        and current - mind.hopefulSince >= hours(U().config("mindJoySustainGameHours") or 2)
        and current >= mind.nextJoyAt
        and current >= finite(ensure().groupJoyCooldownUntil, 0)
end

function Community.beginJoy(actorOrId)
    local mind = Community.mindFor(actorOrId)
    if not mind then return nil end
    local current = now()
    mind.nextJoyAt = current + hours(U().config("mindJoyCooldownGameHours") or 36)
    ensure().groupJoyCooldownUntil = current + hours(U().config("mindJoyCooldownGameHours") or 36)
    mind.inspiration = {
        kind = mind.joyResponse, startedAt = current,
        untilAt = current + hours(U().config("mindJoyDurationGameHours") or 6),
    }
    return mind.inspiration
end

function Community.createSupplyRequest(actorOrId, choices)
    local mind = Community.mindFor(actorOrId)
    if not mind then return nil end
    local current = now()
    mind.lastSupplyRequestAt = current
    mind.pendingRequest = {
        id = "request:" .. mind.id .. ":" .. tostring(current), kind = "supply_run",
        askedAt = current, expiresAt = current + hours(24),
        text = "When are we making the next supply run?",
        choices = stableCopy(choices, 2, { count = 16 }) or {},
    }
    return mind.pendingRequest
end

function Community.clearRequest(actorOrId)
    local mind = Community.mindFor(actorOrId)
    if mind then mind.pendingRequest = nil return true end
    return false
end

function Community.addExpectation(actorOrId, kind, dueAt)
    local mind = Community.mindFor(actorOrId)
    if not mind then return nil end
    local row = { kind = clean(kind, "promise", 48), madeAt = now(),
        dueAt = math.max(now(), finite(dueAt, now())), status = "pending" }
    mind.expectations[#mind.expectations + 1] = row
    while #mind.expectations > 8 do table.remove(mind.expectations, 1) end
    return row
end

function Community.lastSupplyRunAt() return finite(ensure().lastSupplyRunAt, 0) end
function Community.setLastSupplyRunAt(value) ensure().lastSupplyRunAt = math.max(0, finite(value, now())) end
function Community.activeRun() return ensure().activeRun end
function Community.setActiveRun(value) ensure().activeRun = value end
function Community.playerAtBase() return ensure().playerAtBase end
function Community.setPlayerAtBase(value) ensure().playerAtBase = value == true end

function Community.debugSet(actorOrId, fields)
    if U().config("debugSpawnEnabled") ~= true then return false, "debug_mode_required" end
    local mind = Community.mindFor(actorOrId)
    if not mind then return false, "mind_unavailable" end
    fields = type(fields) == "table" and fields or {}
    if fields.boredom ~= nil then mind.boredom = clamp(fields.boredom, 0, 100) end
    if fields.criticalSince ~= nil then mind.criticalSince = finite(fields.criticalSince, now()) end
    local validStressResponse = {
        venter = true, restless = true, confronter = true, withdrawer = true, shutdown = true,
    }
    if fields.stressResponse ~= nil then
        if not validStressResponse[fields.stressResponse] then
            return false, "invalid_stress_response"
        end
        mind.stressResponse = fields.stressResponse
    end
    local actor = type(actorOrId) == "string" and U().resolveActor(actorOrId) or actorOrId
    if actor and SC.Commands and type(SC.Commands.peek) == "function" then
        local state = SC.Commands.peek(actor)
        if fields.stress ~= nil then state.stress = clamp(fields.stress, 0, 100) end
        if fields.morale ~= nil then state.morale = clamp(fields.morale, 0, 100) end
        if type(SC.Commands.persist) == "function" then SC.Commands.persist(actor) end
    end
    return true, "mind_debug_updated"
end

local function normalize(source)
    if type(source) ~= "table" then return emptyDocument() end
    local copy = stableCopy(source, 8, { count = 16384 })
    if type(copy) ~= "table" then return emptyDocument() end
    copy.version = Community.VERSION
    copy.minds = type(copy.minds) == "table" and copy.minds or {}
    copy.pairs = type(copy.pairs) == "table" and copy.pairs or {}
    copy.history = type(copy.history) == "table" and copy.history or {}
    copy.deaths = type(copy.deaths) == "table" and copy.deaths or {}
    copy.groupMajorCooldownUntil = math.max(0, finite(copy.groupMajorCooldownUntil, 0))
    copy.groupJoyCooldownUntil = math.max(0, finite(copy.groupJoyCooldownUntil, 0))
    copy.lastSupplyRunAt = math.max(0, finite(copy.lastSupplyRunAt, now()))
    copy.activeRun = nil
    copy.playerAtBase = nil
    for id, mind in pairs(copy.minds) do
        if type(id) ~= "string" or type(mind) ~= "table" then copy.minds[id] = nil
        else copy.minds[id] = normalizeMind(id, mind, nil) end
    end
    for key, pair in pairs(copy.pairs) do
        local expected = type(pair) == "table" and pairKey(pair.firstId, pair.secondId) or nil
        if type(key) ~= "string" or expected ~= key then copy.pairs[key] = nil
        else
            pair.opinion = clamp(pair.opinion, -100, 100)
            pair.trust = clamp(pair.trust, -100, 100)
            pair.tension = clamp(pair.tension, 0, 100)
            pair.familiarity = clamp(pair.familiarity, 0, 100)
            pair.memories = type(pair.memories) == "table" and pair.memories or {}
        end
    end
    local deathRows = {}
    for id, death in pairs(copy.deaths) do
        if type(id) ~= "string" or type(death) ~= "table" then copy.deaths[id] = nil
        else
            death.subjectId = id
            death.subjectName = clean(death.subjectName, "Survivor", 80)
            death.startedAt = math.max(0, finite(death.startedAt, 0))
            deathRows[#deathRows + 1] = { id = id, at = death.startedAt }
        end
    end
    table.sort(deathRows, function(left, right)
        if left.at == right.at then return left.id < right.id end
        return left.at > right.at
    end)
    for index = (U().config("griefDeathHistoryLimit") or 32) + 1, #deathRows do
        copy.deaths[deathRows[index].id] = nil
    end
    local pairRows = {}
    for key, pair in pairs(copy.pairs) do
        pairRows[#pairRows + 1] = {
            key = key, touched = finite(type(pair) == "table" and pair.lastInteractionAt, 0),
        }
    end
    table.sort(pairRows, function(left, right)
        if left.touched == right.touched then return left.key < right.key end
        return left.touched > right.touched
    end)
    for index = (U().config("mindPairLimit") or 64) + 1, #pairRows do
        copy.pairs[pairRows[index].key] = nil
    end
    local historyLimit = U().config("mindHistoryLimit") or 96
    while #copy.history > historyLimit do table.remove(copy.history, 1) end
    return copy
end

function Community.export()
    return stableCopy(ensure(), 8, { count = 16384 })
end

function Community.restore(source)
    document = normalize(source)
    reservations = {}
    return true, document
end

function Community.reset()
    document = emptyDocument()
    reservations = {}
end

Community.reset()
return Community
