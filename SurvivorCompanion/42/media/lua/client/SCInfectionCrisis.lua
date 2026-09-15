-- SPDX-License-Identifier: MIT

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
if not SC.GameplayUtil and type(require) == "function" then pcall(require, "SCGameplayUtil") end
if not SC.Medical and type(require) == "function" then pcall(require, "SCMedical") end
if not SC.BaseLife and type(require) == "function" then pcall(require, "SCBaseLife") end
if not SC.StableValue and type(require) == "function" then pcall(require, "SCStableValue") end

SC.InfectionCrisis = SC.InfectionCrisis or {}
local Crisis = SC.InfectionCrisis

Crisis.VERSION = 1
Crisis.OUTCOMES = {
    watch = true, quarantine = true, exile = true, mercy = true,
    self_exile = true, self_sacrifice = true,
}

local document

local function U() return SC.GameplayUtil end
local function now() return U() and U().nowMs() or 0 end

local function finite(value, fallback)
    value = tonumber(value)
    if value == nil or value ~= value or value == math.huge or value == -math.huge then
        return fallback
    end
    return value
end

local function cleanText(value, fallback, limit)
    if type(value) ~= "string" or value == "" then value = fallback or "" end
    value = tostring(value)
    return string.sub(value, 1, limit or 96)
end

local function stableCopy(value, depth, remaining)
    return SC.StableValue.copyStrict(value, {
        maxDepth = tonumber(depth) or 8,
        maxEntries = type(remaining) == "table" and remaining.count or 1024,
        path = "$.infectionCrisis",
    })
end

local function emptyDocument()
    return { version = Crisis.VERSION, nextSerial = 1, crises = {}, observations = {}, history = {} }
end

local function ensure()
    if type(document) ~= "table" then document = emptyDocument() end
    return document
end

local function actorId(actor, player)
    if actor == nil then return nil end
    if actor == player then return "player:local" end
    return U().idOf(actor)
end

local function resolveActor(id, player)
    if id == "player:local" then return player end
    if SC.Registry and type(SC.Registry.byId) == "function" then
        local record = SC.Registry.byId(id)
        return type(record) == "table" and (record.actor or record) or nil
    end
    return nil
end

local function livingActors(player)
    local result = {}
    if player and not U().isDead(player) then result[#result + 1] = player end
    for _, actor in ipairs(U().registryLiving(U().config("maxCompanions") or 16)) do
        result[#result + 1] = actor
    end
    return result
end

-- Everyone within earshot of the bitten one: the player and any registered
-- survivor, uncapped (the companion cap would hide companions behind
-- households and camps), filtered by distance first so it stays cheap.
local function nearbyActors(subject, player, radius)
    local utility = U()
    local result = {}
    if player ~= nil and not utility.isDead(player) and utility.distance(player, subject) <= radius then
        result[#result + 1] = player
    end
    for _, actor in ipairs(utility.registryLiving(false)) do
        if actor ~= player and utility.distance(actor, subject) <= radius then
            result[#result + 1] = actor
        end
    end
    return result
end

local function assess(actor)
    if not actor or not SC.Medical or type(SC.Medical.assess) ~= "function" then return nil end
    local ok, value = pcall(SC.Medical.assess, actor)
    return ok and type(value) == "table" and value or nil
end

local function commandState(actor)
    if SC.Commands and type(SC.Commands.export) == "function" then
        local ok, state = pcall(SC.Commands.export, actor)
        if ok and type(state) == "table" then return state end
    end
    return {}
end

local function history(kind, fields)
    local row = stableCopy(fields, 3, { count = 64 }) or {}
    row.kind, row.at = cleanText(kind, "event", 48), now()
    local rows = ensure().history
    rows[#rows + 1] = row
    local limit = U().config("infectionCrisisHistoryLimit") or 96
    while #rows > limit do table.remove(rows, 1) end
    if SC.BaseLife and type(SC.BaseLife.noteHistory) == "function" then
        SC.BaseLife.noteHistory("infection_" .. row.kind, row)
    end
    return row
end

local function addEvidence(crisis, kind, observerId, certainty, details)
    local row = {
        kind = cleanText(kind, "observation", 48), observerId = observerId,
        certainty = math.max(0, math.min(100, finite(certainty, 0))), at = now(),
        details = cleanText(details, "", 96),
    }
    crisis.evidence[#crisis.evidence + 1] = row
    local limit = U().config("infectionCrisisEvidenceLimit") or 32
    while #crisis.evidence > limit do table.remove(crisis.evidence, 1) end
    return row
end

local function profileChoice(actor, id, choices, salt)
    local state = commandState(actor)
    local profile = type(state.personalityProfile) == "table" and state.personalityProfile or {}
    local score = U().stableHash(tostring(id) .. ":" .. tostring(salt))
        + math.floor(finite(state.bond, 0) * 7) + math.floor(finite(state.trust, 0) * 3)
    if profile.value == "loyalty" or profile.value == "community" then score = score + 5 end
    return choices[(score % #choices) + 1]
end

local function strategyFor(actor, id)
    local state = commandState(actor)
    if finite(state.trust, 0) >= 70 or finite(state.bond, 0) >= 65 then return "confess" end
    return profileChoice(actor, id, { "conceal", "confess", "self_exile" }, "bite-strategy")
end

local function stanceFor(actor, subjectId)
    local state = commandState(actor)
    local bond, stress = finite(state.bond, 0), finite(state.stress, 0)
    if bond >= 72 then return "protective" end
    if stress >= 70 then return "fearful" end
    return profileChoice(actor, subjectId, {
        "protective", "pragmatic", "fearful", "compassionate", "authoritarian",
    }, "crisis-stance")
end

local function participant(crisis, id)
    crisis.participants[id] = crisis.participants[id] or {
        knowledge = "unaware", certainty = 0, stance = nil, choice = nil, spoken = false,
    }
    return crisis.participants[id]
end

local function discover(crisis, observer, observerId, certainty, kind)
    local row = participant(crisis, observerId)
    if certainty >= 95 then row.knowledge = "confirmed"
    elseif row.knowledge ~= "confirmed" then row.knowledge = "suspected" end
    row.certainty = math.max(row.certainty or 0, certainty)
    row.stance = row.stance or stanceFor(observer, crisis.subjectId)
    addEvidence(crisis, kind, observerId, certainty)
end

-- Conversation timing that does not need saving: when each bystander set
-- off to walk over, and when the next voice in a crisis may speak.
local walks, turns = {}, {}

local function say(actor, topic, fallback)
    if SC.Dialogue and type(SC.Dialogue.say) == "function" then
        local ok, spoken = pcall(SC.Dialogue.say, actor, topic, nil, nil, { fallback = fallback })
        return ok and spoken == true
    end
    return U().say(actor, fallback) == true
end

local function liveCommands(actor)
    if SC.Commands and type(SC.Commands.peek) == "function" then
        local ok, state = pcall(SC.Commands.peek, actor)
        if ok and type(state) == "table" then return state end
    end
    return nil
end

-- Talking about a bite waits for a quiet moment, and a follower waits until
-- the player has stopped walking.
local function readyToTalk(actor, player, snapshot)
    if type(snapshot) == "table" and ((tonumber(snapshot.threatCount) or 0) > 0
        or (tonumber(snapshot.immediateCount) or 0) > 0 or snapshot.humanThreat ~= nil) then
        return false
    end
    local commands = liveCommands(actor)
    return not (type(commands) == "table" and commands.order == "follow" and player ~= nil
        and U().call(player, "isMoving") == true)
end

local stanceEmotes = {
    protective = "comehere", compassionate = "yes", pragmatic = "signalok",
    fearful = "stop", authoritarian = "no",
}

-- Face the other person and make one gesture, the way two people talk.
local function faceWithGesture(actor, target, emote)
    local x, y, z = U().position(target)
    if x == nil then return false end
    return U().move(actor, "walk", {
        action = "conversation_pose", targetPosition = { x = x, y = y, z = z or 0 },
        emote = emote, humanAnimationOnly = true,
    }) == true
end

-- Who a bitten companion would tell first: the companion it trusts most
-- (their mutual trust plus half their opinion), or the player when it
-- trusts the player more. Nobody when no one is trusted enough.
local function confidantFor(subject, player)
    local utility = U()
    local best, bestScore
    local state = liveCommands(subject)
    if player ~= nil and not utility.isDead(player) then
        best, bestScore = player, finite(state and state.trust, 0)
    end
    if SC.Community and type(SC.Community.relation) == "function" then
        -- The whole registry: the companion cap would cut friends off behind
        -- households and camps. Only recruited companions are told.
        for _, other in ipairs(utility.registryLiving(false)) do
            local otherCommands = other ~= subject and liveCommands(other) or nil
            if otherCommands ~= nil and otherCommands.recruited == true
                and not utility.isDead(other) then
                local ok, pair = pcall(SC.Community.relation, subject, other, false)
                if ok and type(pair) == "table" then
                    local score = finite(pair.trust, 0) + finite(pair.opinion, 0) * 0.5
                    if bestScore == nil or score > bestScore then best, bestScore = other, score end
                end
            end
        end
    end
    if best == nil or bestScore < (utility.config("crisisConfideTrust") or 40) then return nil end
    return best
end
Crisis._confidantForTests = confidantFor

local function newCrisis(subject, subjectId, medical, player)
    local count, oldestId, oldestAt = 0, nil, math.huge
    for candidateId, candidate in pairs(ensure().crises) do
        count = count + 1
        if (candidate.phase == "terminal" or candidate.phase == "closed")
            and (candidate.createdAt or 0) < oldestAt then
            oldestId, oldestAt = candidateId, candidate.createdAt or 0
        end
    end
    if count >= (U().config("infectionCrisisMaxRecords") or 32) and oldestId then
        ensure().crises[oldestId] = nil
    end
    local id = "crisis:" .. tostring(ensure().nextSerial)
    ensure().nextSerial = ensure().nextSerial + 1
    local current = now()
    local crisis = {
        id = id, subjectId = subjectId, subjectName = U().nameOf(subject), phase = "discovered",
        strategy = strategyFor(subject, subjectId), outcome = nil,
        createdAt = current, updatedAt = current,
        irreversibleAfter = current + (U().config("infectionCrisisSafeDelayMs") or 10000),
        deliberateAfter = current + (U().config("infectionCrisisDeliberationMs") or 12000),
        biteCount = medical.bites or 1, infectionLevel = medical.infectionLevel or 0,
        baseId = SC.BaseLife and SC.BaseLife.active() and SC.BaseLife.active().id or nil,
        participants = {}, evidence = {}, artifacts = {}, finalAuthorized = false,
    }
    participant(crisis, subjectId).knowledge = "confirmed"
    participant(crisis, subjectId).certainty = 100
    addEvidence(crisis, "bite", subjectId, 100, "new bite")
    -- A companion who trusts the player walks over and tells them first; one
    -- who would hide it may still confide in the one it trusts most.
    if subjectId ~= "player:local" then
        if crisis.strategy == "confess" and player ~= nil and not U().isDead(player) then
            crisis.confidantId, crisis.confideState = "player:local", "pending"
        elseif crisis.strategy == "conceal" then
            local confidant = confidantFor(subject, player)
            if confidant ~= nil then
                crisis.confidantId, crisis.confideState = actorId(confidant, player), "pending"
            end
        end
    end
    ensure().crises[id] = crisis
    history("created", { crisisId = id, subjectId = subjectId, strategy = crisis.strategy })

    -- Anyone close enough to see the attack knows immediately; otherwise the
    -- bitten survivor controls disclosure until symptoms or an examination.
    for _, witness in ipairs(nearbyActors(subject, player, 6)) do
        local witnessId = actorId(witness, player)
        if witness ~= subject and U().canSee(witness, subject) then
            discover(crisis, witness, witnessId, 100, "witnessed_bite")
        end
    end
    return crisis
end

local function activeForSubject(subjectId)
    for _, crisis in pairs(ensure().crises) do
        if crisis.subjectId == subjectId and crisis.phase ~= "closed" then return crisis end
    end
    return nil
end

local function atBase(actor)
    return SC.BaseLife and SC.BaseLife.active() and SC.BaseLife.isInside(actor)
end

local function confess(crisis, subject, player)
    local radius = atBase(subject) and 10 or 7
    for _, actor in ipairs(nearbyActors(subject, player, radius)) do
        local id = actorId(actor, player)
        if actor ~= subject then
            discover(crisis, actor, id, 100, "confession")
        end
    end
    if not crisis.confessedAt then
        crisis.confessedAt = now()
        if SC.Dialogue and type(SC.Dialogue.say) == "function" then
            SC.Dialogue.say(subject, "crisis.confess", nil, nil,
                { fallback = "I was bitten. We need to decide what happens next." })
        else
            U().say(subject, "I was bitten. We need to decide what happens next.")
        end
        history("confessed", { crisisId = crisis.id, subjectId = crisis.subjectId })
    end
end

local function symptomDiscovery(crisis, subject, player, level)
    if level < 25 then return end
    local radius = atBase(subject) and 10 or 7
    for _, actor in ipairs(nearbyActors(subject, player, radius)) do
        local id = actorId(actor, player)
        if actor ~= subject then
            local certainty = level >= 70 and 100 or math.min(90, 45 + level)
            discover(crisis, actor, id, certainty, "visible_symptoms")
        end
    end
end

local function medicInspection(crisis, subject, player)
    if crisis.examinedAt then return end
    for _, actor in ipairs(nearbyActors(subject, player, 4)) do
        local id = actorId(actor, player)
        local resident = SC.BaseLife and SC.BaseLife.resident(id) or nil
        if resident and resident.role == "medic" and actor ~= subject then
            crisis.examinedAt = now()
            discover(crisis, actor, id, crisis.strategy == "conceal" and 82 or 100,
                crisis.strategy == "conceal" and "refused_exam" or "medical_exam")
            if crisis.strategy ~= "conceal" then confess(crisis, subject, player) end
            return
        end
    end
end

local stanceScores = {
    protective = { watch = 5, quarantine = 3, exile = -3, mercy = -4 },
    compassionate = { watch = 3, quarantine = 5, exile = -2, mercy = 1 },
    pragmatic = { watch = 1, quarantine = 4, exile = 2, mercy = 2 },
    fearful = { watch = -2, quarantine = 3, exile = 5, mercy = 3 },
    authoritarian = { watch = -3, quarantine = 3, exile = 4, mercy = 5 },
}

local function chooseOutcome(crisis, subject, player)
    if crisis.strategy == "self_exile" then return "self_exile" end
    local scores = { watch = 0, quarantine = 0, exile = 0, mercy = 0 }
    local confirmed = 0
    local executorId
    for id, member in pairs(crisis.participants) do
        if id ~= crisis.subjectId and member.knowledge == "confirmed" then
            confirmed = confirmed + 1
            local actor = resolveActor(id, player)
            member.stance = member.stance or stanceFor(actor, crisis.subjectId)
            local weights = stanceScores[member.stance] or stanceScores.pragmatic
            local memberChoice, memberScore = "watch", -math.huge
            for choice, value in pairs(weights) do scores[choice] = scores[choice] + value end
            for choice, value in pairs(weights) do
                if value > memberScore then memberChoice, memberScore = choice, value end
            end
            member.choice = memberChoice
            if not executorId and (member.stance == "authoritarian" or member.stance == "pragmatic") then
                executorId = id
            end
        end
    end
    if confirmed == 0 then return nil end
    local level = crisis.infectionLevel or 0
    if level < 55 then scores.watch = scores.watch + 6; scores.quarantine = scores.quarantine + 4 end
    if level >= 80 then scores.mercy = scores.mercy + 6; scores.exile = scores.exile + 3 end
    if not (SC.BaseLife and SC.BaseLife.zoneCenter("quarantine")) then
        scores.quarantine = scores.quarantine - 7
    end
    local best, bestScore = "watch", -math.huge
    for _, choice in ipairs({ "watch", "quarantine", "exile", "mercy" }) do
        if scores[choice] > bestScore then best, bestScore = choice, scores[choice] end
    end
    crisis.executorId = best == "mercy" and executorId or nil
    return best
end

local function preserveKeepsake(crisis, subject, player)
    if crisis.artifacts.keepsake then return end
    local state = commandState(subject)
    local keepsake = type(state.possessions) == "table" and state.possessions.keepsake or nil
    if not keepsake or not SC.PersonalItems or type(SC.PersonalItems.find) ~= "function" then return end
    local item = SC.PersonalItems.find(subject, keepsake.key)
    if not item then return end
    local recipient
    for id, member in pairs(crisis.participants) do
        if id ~= crisis.subjectId and member.stance == "protective" then
            recipient = resolveActor(id, player)
            if recipient then break end
        end
    end
    if recipient and U().transferItem(U().inventory(subject), U().inventory(recipient), item) then
        crisis.artifacts.keepsake = { recipientId = actorId(recipient, player), at = now() }
        history("keepsake_given", {
            crisisId = crisis.id, subjectId = crisis.subjectId,
            recipientId = crisis.artifacts.keepsake.recipientId,
        })
        return
    end
    if SC.BaseLife and type(SC.BaseLife.storageRows) == "function" then
        for _, storage in ipairs(SC.BaseLife.storageRows("memorial", false)) do
            local container = SC.BaseLife.resolveContainer(storage)
            if container and U().transferItem(U().inventory(subject), container, item) then
                crisis.artifacts.keepsake = { storageId = storage.id, at = now() }
                history("keepsake_memorial", {
                    crisisId = crisis.id, subjectId = crisis.subjectId, storageId = storage.id,
                })
                return
            end
        end
    end
end

local function createNote(subject, crisis, outcome)
    if crisis.artifacts.note then return end
    local item = U().addItem(U().inventory(subject), "Base.Note")
    if not item then return end
    local data = U().modData(item)
    if data then
        data.SC_CrisisId, data.SC_CrisisOutcome = crisis.id, outcome
        data.SC_NoteText = "If you find this: I was bitten. I chose " .. outcome
            .. ". Remember me as I was."
    end
    U().call(item, "setName", "Farewell note")
    crisis.artifacts.note = true
end

local function applyOutcome(crisis, subject, outcome, player)
    crisis.outcome, crisis.phase, crisis.resolvedAt = outcome, "resolved", now()
    local restriction = nil
    if outcome == "watch" then restriction = "watch"
    elseif outcome == "quarantine" then restriction = "quarantine" end
    if SC.BaseLife and type(SC.BaseLife.setRestriction) == "function" then
        SC.BaseLife.setRestriction(crisis.subjectId, restriction)
    end
    if outcome == "self_exile" or outcome == "exile" or outcome == "self_sacrifice" then
        createNote(subject, crisis, outcome)
    end
    if outcome ~= "watch" then preserveKeepsake(crisis, subject, player) end
    history("resolved", {
        crisisId = crisis.id, subjectId = crisis.subjectId, outcome = outcome,
    })
end

-- The slow parts of a crisis conversation: a walk to confide that takes too
-- long is given up, a confidant answers a few seconds after being told, and
-- the bitten companion answers the first person who comes over.
local function conversationBeats(crisis, subject, player, current)
    local utility = U()
    if crisis.confideState == "pending" and current - finite(crisis.createdAt, current)
        > (utility.config("crisisConfideTimeoutMs") or 45000) then
        crisis.confideState = "abandoned"
        history("confide_abandoned", { crisisId = crisis.id, subjectId = crisis.subjectId })
    end
    if crisis.confideReplyDue ~= nil and current >= finite(crisis.confideReplyDue, current) then
        crisis.confideReplyDue = nil
        local friend = resolveActor(crisis.confidantId, player)
        local member = crisis.participants[crisis.confidantId]
        if friend ~= nil and member ~= nil and not utility.isDead(friend) then
            member.stance = member.stance or stanceFor(friend, crisis.subjectId)
            if member.stance == "protective" or member.stance == "compassionate" then
                crisis.secretKept = true
                say(friend, "crisis.keep", "Okay. It stays between us. For now.")
            else
                crisis.strategy = "confess"
                crisis.confessAfter = current + (utility.config("crisisConfessPauseMs") or 4000)
                say(friend, "crisis.urge", "You have to tell them. Now. Or I will.")
            end
            history("confidant_answered", {
                crisisId = crisis.id, subjectId = crisis.subjectId,
                confidantId = crisis.confidantId, kept = crisis.secretKept == true,
            })
        end
    end
    if crisis.replyDue ~= nil and current >= finite(crisis.replyDue, current)
        and crisis.subjectReplied ~= true then
        crisis.replyDue, crisis.subjectReplied = nil, true
        say(subject, "crisis.reply", "I know.")
    end
end

local function advance(crisis, subject, player, medical, current)
    crisis.updatedAt = current
    crisis.infectionLevel = math.max(crisis.infectionLevel or 0, medical.infectionLevel or 0)
    crisis.biteCount = math.max(crisis.biteCount or 0, medical.bites or 0)
    if crisis.infectionLevel >= (U().config("lastWordsTurningThreshold") or 97)
        and SC.Dialogue and type(SC.Dialogue.sayLastWords) == "function" then
        SC.Dialogue.sayLastWords(subject, "turning", player)
    end
    if crisis.phase == "resolved" or crisis.phase == "terminal" then return end
    conversationBeats(crisis, subject, player, current)
    symptomDiscovery(crisis, subject, player, crisis.infectionLevel)
    medicInspection(crisis, subject, player)
    -- A confession waits while the bitten one is still walking over to tell
    -- someone first, and a moment after a friend has pushed for it.
    if crisis.strategy == "confess" and crisis.confideState ~= "pending"
        and current >= crisis.createdAt + 2000
        and current >= finite(crisis.confessAfter, 0) then
        confess(crisis, subject, player)
    end
    local inCamp = atBase(subject)
    if current >= crisis.deliberateAfter and (inCamp or crisis.infectionLevel >= 85) then
        crisis.phase = "deliberating"
        local outcome = chooseOutcome(crisis, subject, player)
        if outcome then applyOutcome(crisis, subject, outcome, player) end
    end
end

local lines = {
    protective = "We do not abandon our own. We watch them and keep them safe.",
    compassionate = "Give them a quiet room and a little dignity.",
    pragmatic = "Separate them, keep watch, and make an exit plan.",
    fearful = "They cannot stay among us. It is too dangerous.",
    authoritarian = "We decide this now, before they turn.",
}

local function speakReaction(actor, crisis, member, subject)
    if member.spoken or member.knowledge ~= "confirmed" then return false end
    member.spoken = true
    member.stance = member.stance or stanceFor(actor, crisis.subjectId)
    if subject ~= nil then
        faceWithGesture(actor, subject, stanceEmotes[member.stance] or "signalok")
    end
    say(actor, "crisis." .. tostring(member.stance or "pragmatic"),
        lines[member.stance] or lines.pragmatic)
    if crisis.subjectReplied ~= true and crisis.replyDue == nil then
        crisis.replyDue = now() + (U().config("crisisReplyDelayMs") or 2500)
    end
    return true
end

-- A bystander walks over before saying anything, faces the bitten one and
-- takes a turn: one voice every few seconds. Someone who cannot get there in
-- time says it from where they stand.
local function approachAndReact(actor, id, crisis, member, subject)
    local utility = U()
    local current = now()
    local key = crisis.id .. "|" .. tostring(id)
    walks[key] = walks[key] or current
    local distance = utility.distance(actor, subject)
    local near = distance <= (utility.config("crisisTalkDistance") or 2.2)
    local late = current - walks[key] > (utility.config("crisisGatherTimeoutMs") or 20000)
    local canWalk = SC.Navigation and type(SC.Navigation.request) == "function"
    if crisis.phase == "deliberating" then
        if distance > 3 and not late and canWalk then
            return SC.Navigation.request(actor, utility.squareOf(subject), "walk", {
                action = "crisis_approach", targetSquare = utility.squareOf(subject),
            })
        end
        if member.spoken == true then return true, "crisis_gathered" end
    elseif member.spoken == true then
        walks[key] = nil
        return false, "crisis_reacted"
    elseif not near and not late and canWalk then
        return SC.Navigation.request(actor, utility.squareOf(subject), "walk", {
            action = "crisis_approach", targetSquare = utility.squareOf(subject),
        })
    end
    if current < (turns[crisis.id] or 0) then
        if near then utility.stop(actor) end
        return true, "crisis_waiting_turn"
    end
    utility.stop(actor)
    turns[crisis.id] = current + (utility.config("crisisTurnGapMs") or 3500)
    walks[key] = nil
    speakReaction(actor, crisis, member, subject)
    return true, "crisis_reacting"
end

-- The bitten companion walks over to the one it trusts and tells them first:
-- the player hears a confession (or a private word when it would rather
-- hide it); a friend hears it privately and answers a moment later.
local function confideStep(subject, crisis, player)
    local utility = U()
    local confidant = resolveActor(crisis.confidantId, player)
    if confidant == nil or utility.isDead(confidant) then
        crisis.confideState = "abandoned"
        return false, "confidant_unavailable"
    end
    if utility.distance(subject, confidant) > (utility.config("crisisTalkDistance") or 2.2) then
        if not SC.Navigation or type(SC.Navigation.request) ~= "function" then
            return false, "navigation_unavailable"
        end
        return SC.Navigation.request(subject, utility.squareOf(confidant), "walk", {
            action = "crisis_approach", targetSquare = utility.squareOf(confidant),
        })
    end
    utility.stop(subject)
    local toPlayer = crisis.confidantId == "player:local"
    faceWithGesture(subject, confidant, toPlayer and "comehere" or "undecided")
    crisis.confideState, crisis.confideAt = "done", now()
    if toPlayer and crisis.strategy == "confess" then
        confess(crisis, subject, player)
    elseif toPlayer then
        say(subject, "crisis.confide.player", "Boss. Just you and me. I got bit.")
        discover(crisis, confidant, crisis.confidantId, 100, "confided")
    else
        say(subject, "crisis.confide", "Keep your voice down. I got bit.")
        discover(crisis, confidant, crisis.confidantId, 100, "confided")
        participant(crisis, crisis.confidantId).spoken = true
        crisis.confideReplyDue = now() + (utility.config("crisisConfideReplyMs") or 3000)
    end
    history("confided", {
        crisisId = crisis.id, subjectId = crisis.subjectId, confidantId = crisis.confidantId,
    })
    return true, "crisis_confided"
end

local function updateResolvedActor(actor, id, crisis, subject)
    if id ~= crisis.subjectId then return false, "crisis_observer" end
    local outcome = crisis.outcome
    if outcome == "quarantine" then
        local target = SC.BaseLife and SC.BaseLife.zoneCenter("quarantine")
        local square = target and U().loadedSquare(target) or nil
        if square and U().distance(actor, square) > 1.5 and SC.Navigation then
            return SC.Navigation.request(actor, square, "walk", {
                action = "move_to_quarantine", targetSquare = square,
            })
        end
        return true, "quarantined"
    end
    if outcome == "exile" or outcome == "self_exile" then
        local base = SC.BaseLife and SC.BaseLife.active()
        if base and SC.BaseLife.isInside(actor) then
            local dx = (U().stableHash(id) % 2 == 0) and 18 or -18
            local target = U().gridSquare(base.core.x + dx, base.core.y + 12, base.core.z)
            if target and SC.Navigation then
                return SC.Navigation.request(actor, target, "walk", {
                    action = "leave_base", targetSquare = target,
                })
            end
        end
        return true, "exiled"
    end
    if outcome == "mercy" or outcome == "self_sacrifice" then
        if now() < crisis.irreversibleAfter or crisis.finalAuthorized ~= true then
            return true, "final_outcome_awaiting_authorization"
        end
        if SC.NativeActions and type(SC.NativeActions.performEndOfLife) == "function" then
            local ok, reason = SC.NativeActions.performEndOfLife(actor, outcome, subject)
            if ok then crisis.phase, crisis.terminalAt = "terminal", now() end
            return ok == true, reason
        end
        return false, "native_final_action_unavailable"
    end
    return true, "watched"
end

function Crisis.pulse(player, current)
    current = finite(current, now())
    local seen = {}
    for _, actor in ipairs(livingActors(player)) do
        local id = actorId(actor, player)
        local medical = assess(actor)
        if id and medical then
            seen[id] = true
            local prior = ensure().observations[id] or { bites = 0, infected = false }
            local crisis = activeForSubject(id)
            if (medical.bites or 0) > (prior.bites or 0) and not crisis then
                crisis = newCrisis(actor, id, medical, player)
            elseif not crisis and medical.knoxInfected and (medical.infectionLevel or 0) >= 20 then
                crisis = newCrisis(actor, id, medical, player)
                addEvidence(crisis, "symptoms", id, 70, "infection already underway")
            end
            if crisis then advance(crisis, actor, player, medical, current) end
            ensure().observations[id] = {
                bites = medical.bites or 0, infected = medical.knoxInfected == true,
                infectionLevel = medical.infectionLevel or 0, seenAt = current,
            }
        end
    end
    for _, crisis in pairs(ensure().crises) do
        if crisis.phase ~= "terminal" and crisis.phase ~= "closed" then
            local subject = resolveActor(crisis.subjectId, player)
            if subject and U().isDead(subject) then
                crisis.phase, crisis.terminalAt = "terminal", current
                if SC.BaseLife and type(SC.BaseLife.setRestriction) == "function" then
                    SC.BaseLife.setRestriction(crisis.subjectId, nil)
                end
                history("subject_died", {
                    crisisId = crisis.id, subjectId = crisis.subjectId,
                    outcome = crisis.outcome,
                })
            end
        end
    end
    return true, seen
end

-- What a crisis still asks of one person, and how urgently. The bitten
-- companion lives normally until the group decides; then it follows the
-- outcome (quarantine, exile, or waiting on a final act), except "watch",
-- which is ordinary life under watch. Everyone else reacts once when they
-- learn of it and gathers while the group deliberates; the authorized
-- executor acts. A crisis whose subject died or turned asks nothing.
local actingOutcomes = {
    quarantine = true, exile = true, self_exile = true, mercy = true, self_sacrifice = true,
}

local function intentPriority(crisis, id, actor, player, snapshot)
    if crisis.phase == "terminal" or crisis.phase == "closed" then return 0 end
    local utility = U()
    if crisis.subjectId == id then
        if crisis.phase == "discovered" and crisis.confideState == "pending" then
            local confidant = resolveActor(crisis.confidantId, player)
            if confidant == nil or not readyToTalk(actor, player, snapshot)
                or utility.distance(actor, confidant) > (utility.config("crisisConfideRadius") or 25) then
                return 0
            end
            return 70
        end
        return crisis.phase == "resolved" and actingOutcomes[crisis.outcome] and 84 or 0
    end
    local member = crisis.participants[id]
    if not member then return 0 end
    if crisis.finalAuthorized and crisis.outcome == "mercy" and crisis.executorId == id then
        return 125
    end
    if member.knowledge ~= "confirmed" then return 0 end
    local talking = crisis.phase == "deliberating"
        or (crisis.phase ~= "resolved" and member.spoken ~= true)
    if not talking or not readyToTalk(actor, player, snapshot) then return 0 end
    local subject = resolveActor(crisis.subjectId, player)
    if subject == nil
        or utility.distance(actor, subject) > (utility.config("crisisGatherRadius") or 20) then
        return 0
    end
    return 66
end

function Crisis.intentFor(actor, player, snapshot)
    local id = actorId(actor, player)
    if not id then return nil end
    local best
    for _, crisis in pairs(ensure().crises) do
        local priority = intentPriority(crisis, id, actor, player, snapshot)
        if priority > 0 and (best == nil or priority > best.priority) then
            best = {
                crisisId = crisis.id, phase = crisis.phase, outcome = crisis.outcome,
                subjectId = crisis.subjectId, priority = priority,
            }
        end
    end
    return best
end

function Crisis.updateActor(actor, player)
    local intent = Crisis.intentFor(actor, player)
    if not intent or intent.priority <= 0 then return false, "no_crisis_intent" end
    local crisis = ensure().crises[intent.crisisId]
    if not crisis then return false, "crisis_missing" end
    local id = actorId(actor, player)
    local subject = resolveActor(crisis.subjectId, player)
    if not subject then return false, "crisis_subject_unavailable" end
    local member = participant(crisis, id)
    if id ~= crisis.subjectId then
        if crisis.phase == "resolved" and crisis.outcome == "mercy"
            and crisis.finalAuthorized and crisis.executorId == id then
            local ok, reason = SC.NativeActions and SC.NativeActions.performEndOfLife
                and SC.NativeActions.performEndOfLife(actor, "mercy", subject)
            if ok and U().isDead(subject) then crisis.phase, crisis.terminalAt = "terminal", now() end
            return ok == true, reason or "native_final_action_unavailable"
        end
        return approachAndReact(actor, id, crisis, member, subject)
    end
    if crisis.phase == "discovered" and crisis.confideState == "pending" then
        return confideStep(actor, crisis, player)
    end
    return updateResolvedActor(actor, id, crisis, subject)
end

function Crisis.authorize(crisisId, outcome)
    local crisis = ensure().crises[crisisId]
    if not crisis or crisis.phase ~= "resolved" then return false, "crisis_not_resolved" end
    if outcome ~= nil and crisis.outcome ~= outcome then return false, "outcome_mismatch" end
    if crisis.outcome ~= "mercy" and crisis.outcome ~= "self_sacrifice" then
        return false, "outcome_not_irreversible"
    end
    if now() < crisis.irreversibleAfter then return false, "safety_delay_active" end
    crisis.finalAuthorized = true
    history("final_authorized", { crisisId = crisis.id, outcome = crisis.outcome })
    return true, crisis
end

function Crisis.choose(crisisId, outcome)
    local crisis = ensure().crises[crisisId]
    if not crisis then return false, "unknown_crisis" end
    if crisis.phase == "resolved" or crisis.phase == "terminal" or crisis.phase == "closed" then
        return false, "crisis_already_resolved"
    end
    if not Crisis.OUTCOMES[outcome] then return false, "invalid_outcome" end
    if outcome == "mercy" and crisis.subjectId == "player:local" then
        return false, "player_final_outcome_is_never_automated"
    end
    local player = type(getPlayer) == "function" and getPlayer() or nil
    if player then
        local knowledge = crisis.participants[actorId(player, player)]
        if crisis.subjectId ~= actorId(player, player)
            and (not knowledge or knowledge.knowledge == "unaware") then
            return false, "crisis_not_known_to_player"
        end
        if outcome == "mercy" and crisis.subjectId ~= actorId(player, player)
            and knowledge.knowledge ~= "confirmed" then
            return false, "bite_not_confirmed"
        end
    end
    local subject = resolveActor(crisis.subjectId, player)
    if not subject then return false, "crisis_subject_unavailable" end
    if outcome == "mercy" and not crisis.executorId then
        for id, member in pairs(crisis.participants) do
            if id ~= crisis.subjectId and member.knowledge == "confirmed" then
                crisis.executorId = id
                if member.stance == "authoritarian" or member.stance == "pragmatic" then break end
            end
        end
        if not crisis.executorId then return false, "mercy_executor_unavailable" end
    end
    applyOutcome(crisis, subject, outcome, player)
    return true, crisis
end

function Crisis.summary(viewer)
    if viewer == nil and type(getPlayer) == "function" then
        local ok, value = pcall(getPlayer)
        if ok then viewer = value end
    end
    local viewerId = actorId(viewer, viewer)
    local result = { active = 0, rows = {}, history = stableCopy(ensure().history, 4, { count = 1024 }) or {} }
    for _, crisis in pairs(ensure().crises) do
        local knowledge = viewerId and crisis.participants[viewerId] or nil
        local visible = viewer == nil or crisis.subjectId == viewerId
            or (knowledge and knowledge.knowledge ~= "unaware")
        -- A resolved crisis -- the subject died/turned ("terminal") or its fate was
        -- decided ("closed") -- is no longer an ongoing crisis and must not linger in
        -- the active list (playtest: dead companions still shown under infection
        -- crises). Its record stays in history for the record.
        if visible and crisis.phase ~= "terminal" and crisis.phase ~= "closed" then
            result.active = result.active + 1
            result.rows[#result.rows + 1] = {
                id = crisis.id, subjectId = crisis.subjectId, subjectName = crisis.subjectName,
                subjectIsPlayer = crisis.subjectId == "player:local",
                phase = crisis.phase,
                strategy = crisis.strategy, outcome = crisis.outcome,
                infectionLevel = crisis.infectionLevel, finalAuthorized = crisis.finalAuthorized == true,
            }
        end
    end
    table.sort(result.rows, function(a, b) return a.id < b.id end)
    return result
end

local function normalize(source)
    if type(source) ~= "table" then return emptyDocument() end
    local copy = stableCopy(source, 8, { count = 8192 })
    if type(copy) ~= "table" then return emptyDocument() end
    copy.version = Crisis.VERSION
    copy.nextSerial = math.max(1, math.floor(finite(copy.nextSerial, 1)))
    copy.crises = type(copy.crises) == "table" and copy.crises or {}
    copy.observations = type(copy.observations) == "table" and copy.observations or {}
    copy.history = type(copy.history) == "table" and copy.history or {}
    for id, crisis in pairs(copy.crises) do
        if type(id) ~= "string" or type(crisis) ~= "table" or crisis.id ~= id
            or type(crisis.subjectId) ~= "string" then copy.crises[id] = nil
        else
            local phases = { discovered = true, deliberating = true, resolved = true,
                terminal = true, closed = true }
            local strategies = { conceal = true, confess = true, self_exile = true }
            crisis.phase = phases[crisis.phase] and crisis.phase or "discovered"
            crisis.strategy = strategies[crisis.strategy] and crisis.strategy or "conceal"
            crisis.outcome = Crisis.OUTCOMES[crisis.outcome] and crisis.outcome or nil
            crisis.participants = type(crisis.participants) == "table" and crisis.participants or {}
            crisis.evidence = type(crisis.evidence) == "table" and crisis.evidence or {}
            crisis.artifacts = type(crisis.artifacts) == "table" and crisis.artifacts or {}
            crisis.finalAuthorized = crisis.finalAuthorized == true
                and crisis.phase == "resolved"
                and (crisis.outcome == "mercy" or crisis.outcome == "self_sacrifice")
        end
    end
    return copy
end

local function restoreFailure(path, detail)
    return false, "invalid infection crisis state at " .. tostring(path) .. ": " .. tostring(detail)
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

local function configuredLimit(key, fallback)
    local raw = U() and U().config and tonumber(U().config(key)) or nil
    if raw == nil or raw ~= raw or raw < 0 or raw == math.huge or raw == -math.huge then
        return fallback
    end
    return math.floor(raw)
end

local phases = { discovered = true, deliberating = true, resolved = true,
    terminal = true, closed = true }
local strategies = { conceal = true, confess = true, self_exile = true }
local knowledgeValues = { unaware = true, suspected = true, confirmed = true }
local stanceValues = { protective = true, pragmatic = true, fearful = true,
    compassionate = true, authoritarian = true }

local function validateCrisis(crisis, id, path)
    if type(crisis) ~= "table" or type(id) ~= "string" or id == ""
        or crisis.id ~= id or type(crisis.subjectId) ~= "string" or crisis.subjectId == "" then
        return restoreFailure(path, "invalid crisis identity")
    end
    if not phases[crisis.phase] then return restoreFailure(path .. ".phase", "invalid phase") end
    if not strategies[crisis.strategy] then
        return restoreFailure(path .. ".strategy", "invalid strategy")
    end
    if crisis.outcome ~= nil and not Crisis.OUTCOMES[crisis.outcome] then
        return restoreFailure(path .. ".outcome", "invalid outcome")
    end
    if type(crisis.finalAuthorized) ~= "boolean" then
        return restoreFailure(path .. ".finalAuthorized", "expected boolean")
    end
    if crisis.finalAuthorized and (crisis.phase ~= "resolved"
        or (crisis.outcome ~= "mercy" and crisis.outcome ~= "self_sacrifice")) then
        return restoreFailure(path .. ".finalAuthorized", "authorization is inconsistent with outcome")
    end
    if type(crisis.participants) ~= "table" then
        return restoreFailure(path .. ".participants", "expected participant map")
    end
    for participantId, participant in pairs(crisis.participants) do
        local participantPath = path .. ".participants[" .. tostring(participantId) .. "]"
        if type(participantId) ~= "string" or participantId == ""
            or type(participant) ~= "table" then
            return restoreFailure(participantPath, "invalid participant")
        end
        if not knowledgeValues[participant.knowledge] then
            return restoreFailure(participantPath .. ".knowledge", "invalid knowledge")
        end
        if not finiteNumber(participant.certainty) or participant.certainty < 0
            or participant.certainty > 100 then
            return restoreFailure(participantPath .. ".certainty", "invalid certainty")
        end
        if participant.stance ~= nil and not stanceValues[participant.stance] then
            return restoreFailure(participantPath .. ".stance", "invalid stance")
        end
        if participant.choice ~= nil and not Crisis.OUTCOMES[participant.choice] then
            return restoreFailure(participantPath .. ".choice", "invalid choice")
        end
        if type(participant.spoken) ~= "boolean" then
            return restoreFailure(participantPath .. ".spoken", "expected boolean")
        end
    end
    local evidenceOkay, evidenceCount = denseArray(crisis.evidence, path .. ".evidence",
        configuredLimit("infectionCrisisEvidenceLimit", 32))
    if not evidenceOkay then return false, evidenceCount end
    for index = 1, evidenceCount do
        local evidence = crisis.evidence[index]
        local evidencePath = path .. ".evidence[" .. tostring(index) .. "]"
        if type(evidence) ~= "table" or type(evidence.kind) ~= "string"
            or type(evidence.observerId) ~= "string" or not finiteNumber(evidence.certainty)
            or evidence.certainty < 0 or evidence.certainty > 100
            or not finiteNumber(evidence.at) or type(evidence.details) ~= "string" then
            return restoreFailure(evidencePath, "invalid evidence")
        end
    end
    if type(crisis.artifacts) ~= "table" then
        return restoreFailure(path .. ".artifacts", "expected artifact map")
    end
    return true
end

local function validateRestoreSource(source)
    if type(source) ~= "table" or source.version ~= Crisis.VERSION
        or type(source.crises) ~= "table" or type(source.observations) ~= "table" then
        return false, "invalid_infection_crisis_state"
    end
    if not finiteNumber(source.nextSerial) or source.nextSerial < 1
        or source.nextSerial ~= math.floor(source.nextSerial) then
        return restoreFailure("$.infectionCrisis.nextSerial", "expected positive integer")
    end
    local crisisCount = 0
    for id, crisis in pairs(source.crises) do
        crisisCount = crisisCount + 1
        if crisisCount > configuredLimit("infectionCrisisMaxRecords", 32) then
            return restoreFailure("$.infectionCrisis.crises", "too many crises")
        end
        local okay, reason = validateCrisis(crisis, id,
            "$.infectionCrisis.crises[" .. tostring(id) .. "]")
        if not okay then return false, reason end
    end
    for id, observation in pairs(source.observations) do
        local path = "$.infectionCrisis.observations[" .. tostring(id) .. "]"
        if type(id) ~= "string" or id == "" or type(observation) ~= "table"
            or not finiteNumber(observation.bites) or observation.bites < 0
            or observation.bites ~= math.floor(observation.bites)
            or type(observation.infected) ~= "boolean"
            or not finiteNumber(observation.infectionLevel) or observation.infectionLevel < 0
            or not finiteNumber(observation.seenAt) then
            return restoreFailure(path, "invalid observation")
        end
    end
    local historyOkay, historyCount = denseArray(source.history,
        "$.infectionCrisis.history", configuredLimit("infectionCrisisHistoryLimit", 96))
    if not historyOkay then return false, historyCount end
    for index = 1, historyCount do
        if type(source.history[index]) ~= "table" then
            return restoreFailure("$.infectionCrisis.history[" .. tostring(index) .. "]",
                "expected record")
        end
    end
    return true
end

function Crisis.export() return stableCopy(ensure(), 8, { count = 8192 }) end
function Crisis.restore(source)
    if source == nil then
        document = emptyDocument()
        return true, document
    end
    local stable, reason = stableCopy(source, 12, { count = 8192 })
    if stable == nil then
        return restoreFailure("$.infectionCrisis", reason or "copy failed")
    end
    local valid, validationReason = validateRestoreSource(stable)
    if not valid then return false, validationReason end
    local normalized, candidate = pcall(normalize, stable)
    if not normalized or type(candidate) ~= "table" then
        return restoreFailure("$.infectionCrisis", normalized and "normalization failed" or candidate)
    end
    document = candidate
    return true, document
end
function Crisis.reset()
    document = emptyDocument()
    walks, turns = {}, {}
end

Crisis.reset()
return Crisis
