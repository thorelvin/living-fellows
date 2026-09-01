-- SPDX-License-Identifier: MIT

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
if not SC.StableValue and type(require) == "function" then pcall(require, "SCStableValue") end
SC.FactionRecruitment = SC.FactionRecruitment or {}

local Recruitment = SC.FactionRecruitment
local SCHEMA = 1
local statuses = {
    available = true, candidate = true, trial = true, joined = true,
    returned = true, declined = true, dead = true,
}

local function U()
    return SC.GameplayUtil
end

local function worldHour()
    if type(getGameTime) == "function" then
        local ok, gameTime = pcall(getGameTime)
        if ok and gameTime ~= nil then
            local value, called = U().call(gameTime, "getWorldAgeHours")
            if called and tonumber(value) then return tonumber(value) end
        end
    end
    return U().nowMs() / 3600000
end

local copyLimits = {
    origin = { maxDepth = 3, maxEntries = 32 },
    summary = { maxDepth = 4, maxEntries = 128 },
}

local function strictCopy(value, limit, path)
    if not SC.StableValue or type(SC.StableValue.copyStrict) ~= "function" then
        return nil, "stable copy unavailable at " .. tostring(path or "$.recruitment")
    end
    return SC.StableValue.copyStrict(value, {
        maxDepth = limit.maxDepth,
        maxEntries = limit.maxEntries,
        path = path or "$.recruitment",
    })
end

local function append(list, value, maximum)
    list[#list + 1] = value
    while #list > maximum do table.remove(list, 1) end
end

local function groupFor(groupOrId)
    if type(groupOrId) == "table" then return groupOrId end
    return SC.Factions and type(SC.Factions.group) == "function"
        and SC.Factions.group(groupOrId) or nil
end

local function memberFor(group, memberKey)
    return group and SC.Factions and type(SC.Factions.member) == "function"
        and SC.Factions.member(group, memberKey) or nil
end

local function memberName(member)
    local identity = type(member) == "table" and type(member.identity) == "table"
        and member.identity or {}
    local first = tostring(identity.forename or "Unknown")
    local last = tostring(identity.surname or "Survivor")
    return first .. " " .. last, first
end

local function activeRecord(member)
    if not member or type(member.actorId) ~= "string" or not SC.Registry
        or type(SC.Registry.byId) ~= "function" then return nil end
    local record = SC.Registry.byId(member.actorId)
    return record and record.actor and record or nil
end

local function completedContracts(group)
    return math.max(0, math.floor(tonumber(group and group.social and group.social.trade
        and group.social.trade.completedContracts) or 0))
end

local function unresolvedOffenses(group)
    local count = 0
    for _, offense in ipairs(group and group.offenses or {}) do
        if offense.forgiven ~= true then count = count + 1 end
    end
    return count
end

local function presentCount(group)
    return SC.Factions and type(SC.Factions.presentCount) == "function"
        and SC.Factions.presentCount(group) or 0
end

local function relationshipWeight(group, memberKey)
    local total, strongest, kind = 0, 0, nil
    for _, relation in pairs(group and group.life and group.life.relationships or {}) do
        if relation.left == memberKey or relation.right == memberKey then
            local weight = math.max(0, tonumber(relation.trust) or 0) * 0.12
                + math.max(0, tonumber(relation.affinity) or 0) * 0.08
                - math.max(0, tonumber(relation.tension) or 0) * 0.04
            total = total + weight
            if weight > strongest then strongest, kind = weight, relation.kind end
        end
    end
    return total, kind
end

local function candidateScore(group, member)
    local lifeValues = group.life and group.life.personality
        and group.life.personality.values or {}
    local ties = relationshipWeight(group, member.key)
    local score = 50
        + (tonumber(group.reputation) or -20) * 0.25
        + completedContracts(group) * 6
        + (tonumber(lifeValues.openness) or 50) * 0.20
        - (tonumber(lifeValues.solidarity) or 50) * 0.10
        - ties * 0.35
    if member.role == "leader" then score = score - 32
    elseif member.role == "watch" then score = score - 8
    elseif member.role == "resident" then score = score + 5 end
    if group.life and group.life.crisis and group.life.crisis.active then score = score - 20 end
    return math.floor(score + 0.5)
end

local function selectCandidate(group)
    local selected, selectedScore, present, loaded = nil, nil, 0, 0
    for _, member in ipairs(group.members or {}) do
        local isPresent = SC.Factions and SC.Factions.memberIsPresent
            and SC.Factions.memberIsPresent(member)
        if isPresent then present = present + 1 end
        if isPresent and activeRecord(member) then
            loaded = loaded + 1
            local score = candidateScore(group, member)
            local essential = member.role == "leader" and presentCount(group) <= 2
            if not essential and score >= 25
                and (selected == nil or score > selectedScore
                    or score == selectedScore and tostring(member.key) < tostring(selected.key)) then
                selected, selectedScore = member, score
            end
        end
    end
    if selected then return selected, selectedScore, "candidate_available" end
    if present > 0 and loaded == 0 then return nil, nil, "candidate_not_loaded" end
    return nil, nil, "household_refused_recruitment"
end

function Recruitment.initialize(groupOrId)
    local group = groupFor(groupOrId)
    if not group then return nil, "faction_unavailable" end
    local state = type(group.recruitment) == "table" and group.recruitment or {}
    group.recruitment = state
    state.schema = SCHEMA
    state.status = statuses[state.status] and state.status or "available"
    state.history = type(state.history) == "table" and state.history or {}
    state.attempts = math.max(0, math.floor(tonumber(state.attempts) or 0))
    state.extensions = math.max(0, math.floor(tonumber(state.extensions) or 0))
    state.cooldownUntilHour = tonumber(state.cooldownUntilHour) or 0
    state.nextPulseAt = tonumber(state.nextPulseAt) or 0
    if (state.status == "candidate" or state.status == "trial")
        and not memberFor(group, state.candidateKey) then
        state.status, state.candidateKey, state.actorId = "available", nil, nil
        state.reason = "candidate_no_longer_exists"
    end
    return state
end

local function eligibility(group, forced)
    local state = Recruitment.initialize(group)
    local current = worldHour()
    if state.status == "trial" then return false, "trial_already_active" end
    if state.status == "joined" then return false, "household_member_already_joined" end
    if state.status == "dead" then return false, "candidate_died" end
    if (state.status == "returned" or state.status == "declined")
        and current < state.cooldownUntilHour and forced ~= true then
        return false, "recruitment_cooldown"
    end
    if (state.status == "returned" or state.status == "declined")
        and current >= state.cooldownUntilHour then
        state.status, state.candidateKey, state.actorId = "available", nil, nil
        state.reason = nil
    end
    if forced ~= true then
        if SC.Config and SC.Config.get("factionRecruitmentEnabled") ~= true then
            return false, "faction_recruitment_disabled"
        end
        if group.discovered ~= true then return false, "faction_not_discovered" end
        if group.standing == "Hostile" or group.lifecycle == "hostile"
            or group.permanentHostility == true then return false, "faction_hostile" end
        if group.standing ~= "Trusted" then return false, "trusted_standing_required" end
        if unresolvedOffenses(group) > 0 then return false, "unresolved_offenses" end
        local required = tonumber(SC.Config.get("factionRecruitmentContractsRequired")) or 2
        if completedContracts(group) < required then return false, "more_contracts_required" end
    end
    if presentCount(group) <= 1 then return false, "last_household_resident" end
    local candidate = state.status == "candidate" and memberFor(group, state.candidateKey) or nil
    if candidate and activeRecord(candidate) then return true, candidate end
    local ignoredScore, selectionReason
    candidate, ignoredScore, selectionReason = selectCandidate(group)
    if not candidate then return false, selectionReason end
    return true, candidate
end

local function canTalk(group, player, forced)
    if forced == true then return true end
    if not SC.FactionContracts or type(SC.FactionContracts.canTalk) ~= "function" then
        return false, "conversation_unavailable"
    end
    return SC.FactionContracts.canTalk(group.id, player)
end

local function say(member, topic, key, fallback)
    local record = activeRecord(member)
    if record and record.actor then
        local localized = U().text(key, fallback)
        if SC.Dialogue and type(SC.Dialogue.say) == "function" then
            SC.Dialogue.say(record.actor, topic, nil, nil, { fallback = localized })
        else
            U().say(record.actor, localized)
        end
    end
end

function Recruitment.ask(groupOrId, player, forced)
    local group = groupFor(groupOrId)
    if not group then return false, "faction_unavailable" end
    local talking, talkReason = canTalk(group, player, forced)
    if not talking then return false, talkReason end
    local eligible, candidateOrReason = eligibility(group, forced)
    if not eligible then
        local state = Recruitment.initialize(group)
        state.reason = candidateOrReason
        if candidateOrReason == "household_refused_recruitment" then
            state.status = "declined"
            state.cooldownUntilHour = worldHour()
                + (tonumber(SC.Config.get("factionRecruitmentCooldownHours")) or 72)
            append(state.history, {
                hour = worldHour(), kind = "household_refused",
            }, 48)
        end
        return false, candidateOrReason
    end
    local candidate = candidateOrReason
    local state = Recruitment.initialize(group)
    state.status = "candidate"
    state.candidateKey = candidate.key
    state.actorId = candidate.actorId
    state.offeredHour = worldHour()
    state.reason = "candidate_interested"
    state.willingness = candidateScore(group, candidate)
    state.attempts = state.attempts + 1
    local ties, tieKind = relationshipWeight(group, candidate.key)
    state.householdReaction = ties >= 16 and "worried"
        or tieKind == "Rivals" and "supportive" or "cautiously_supportive"
    append(state.history, {
        hour = worldHour(), kind = "candidate_named", memberKey = candidate.key,
        actorId = candidate.actorId, willingness = state.willingness,
    }, 48)
    local name, first = memberName(candidate)
    say(candidate, "faction.recruit.candidate", "IGUI_SC_FactionRecruit_Candidate",
        "I can try one run with you. Then I decide.")
    if SC.FactionLife and type(SC.FactionLife.noteEvent) == "function" then
        SC.FactionLife.noteEvent(group, "recruitment_discussed", name)
    end
    return true, "candidate_named:" .. first
end

function Recruitment.startTrial(groupOrId, player, forced)
    local group = groupFor(groupOrId)
    if not group then return false, "faction_unavailable" end
    local state = Recruitment.initialize(group)
    if state.status ~= "candidate" then return false, "name_candidate_first" end
    local talking, talkReason = canTalk(group, player, forced)
    if not talking then return false, talkReason end
    local candidate = memberFor(group, state.candidateKey)
    local record = activeRecord(candidate)
    if not candidate or not record then return false, "candidate_not_loaded" end
    if forced ~= true then
        local maximum = (tonumber(SC.Config.get("factionTradeDistance")) or 6) + 3
        if U().distance(player, record.actor) > maximum then return false, "candidate_too_far_away" end
        if U().canSee and U().canSee(player, record.actor) ~= true then
            return false, "candidate_line_of_sight_lost"
        end
    end

    local detached, origin = SC.Factions.detachMemberForRecruitment(group.id, candidate.key)
    if not detached then return false, origin end
    origin.factionId, origin.memberKey, origin.factionRole = group.id, candidate.key, candidate.role
    local stableOrigin, originCopyReason = strictCopy(origin, copyLimits.origin,
        "$.recruitment.origin")
    if not stableOrigin then
        local restored, restoreReason = SC.Factions.restoreMemberFromRecruitment(
            group.id, candidate.key, record.id, "origin_copy_rollback")
        if not restored then
            return false, "recruitment_origin_copy_failed:" .. tostring(originCopyReason)
                .. ";rollback_failed:" .. tostring(restoreReason)
        end
        return false, "recruitment_origin_copy_failed:" .. tostring(originCopyReason)
    end
    local transitioned, transitionReason = SC.Commands.beginFactionTrial(
        record.actor, stableOrigin, player)
    if not transitioned then
        SC.Factions.restoreMemberFromRecruitment(group.id, candidate.key, record.id,
            "transition_rollback")
        return false, transitionReason
    end

    local started = worldHour()
    local minimum = tonumber(SC.Config.get("factionRecruitmentTrialMinHours")) or 6
    local maximum = tonumber(SC.Config.get("factionRecruitmentTrialMaxHours")) or 24
    state.status = "trial"
    state.actorId = record.id
    state.origin = stableOrigin
    state.trialStartedHour = started
    state.readyHour = started + minimum
    state.deadlineHour = started + math.max(minimum, maximum)
    state.extensions = 0
    state.decision = nil
    state.reason = "trial_in_progress"
    state.missingSinceHour = nil
    append(state.history, {
        hour = started, kind = "trial_started", memberKey = candidate.key,
        actorId = record.id,
    }, 48)
    if SC.FactionLife and type(SC.FactionLife.noteEvent) == "function" then
        SC.FactionLife.noteEvent(group, "member_left_on_trial", candidate.key)
    end
    if SC.FactionContracts and type(SC.FactionContracts.noteAction) == "function" then
        SC.FactionContracts.noteAction(group, "recruitment_trial", candidate.key)
    end
    say(candidate, "faction.recruit.trial", "IGUI_SC_FactionRecruit_TrialStart",
        "One run. I am still responsible for getting myself home.")
    return true, "trial_started"
end

local function trialDecisionScore(group, state, record)
    local command = record and SC.Commands and SC.Commands.peek(record.actor) or {}
    local care = type(command.care) == "table" and command.care or {}
    local member = memberFor(group, state.candidateKey)
    local ties = member and relationshipWeight(group, member.key) or 0
    local hours = math.max(0, worldHour() - (tonumber(state.trialStartedHour) or worldHour()))
    local score = 38
        + completedContracts(group) * 12
        + math.max(0, (tonumber(group.reputation) or 0) - 40) * 0.35
        + math.min(14, hours * 0.8)
        + (tonumber(command.trust) or 0) * 0.35
        + (tonumber(command.bond) or 0) * 0.30
        + ((tonumber(command.morale) or 55) - 50) * 0.12
        - math.max(0, (tonumber(command.stress) or 12) - 25) * 0.20
        + (tonumber(care.treatment) or 0) * 3
        + (tonumber(care.meals) or 0) * 1.5
        + (tonumber(care.rescues) or 0) * 5
        + (tonumber(care.goalsCompleted) or 0) * 2
        - ties * 0.30
    if member and member.role == "leader" then score = score - 12 end
    return math.floor(score + 0.5)
end

local function returnToHousehold(group, state, record, reason)
    local member = memberFor(group, state.candidateKey)
    if not member or not record or not record.actor then return false, "candidate_unavailable" end
    local origin = state.origin or {
        factionId = group.id, memberKey = member.key, factionRole = member.role,
    }
    local transitioned, transitionReason = SC.Commands.returnFactionTrial(record.actor, origin)
    if not transitioned then return false, transitionReason end
    local restored, restoreReason = SC.Factions.restoreMemberFromRecruitment(
        group.id, member.key, record.id, reason)
    if not restored then
        SC.Commands.beginFactionTrial(record.actor, origin)
        return false, "return_rollback:" .. tostring(restoreReason)
    end
    state.status = "returned"
    state.decision = "return"
    state.reason = reason or "returned_home"
    state.decidedHour = worldHour()
    state.cooldownUntilHour = worldHour()
        + (tonumber(SC.Config.get("factionRecruitmentCooldownHours")) or 72)
    append(state.history, {
        hour = worldHour(), kind = "returned", memberKey = member.key,
        actorId = record.id, reason = state.reason,
    }, 48)
    if SC.FactionLife and type(SC.FactionLife.noteEvent) == "function" then
        SC.FactionLife.noteEvent(group, "member_returned_from_trial", member.key)
    end
    say(member, "faction.recruit.return", "IGUI_SC_FactionRecruit_Return",
        "I am going home. This is where I belong.")
    return true, "returned_home"
end

local function joinPlayer(group, state, record, player)
    local member = memberFor(group, state.candidateKey)
    if not member or not record or not record.actor then return false, "candidate_unavailable" end
    local origin = state.origin or {
        factionId = group.id, memberKey = member.key, factionRole = member.role,
    }
    local transitioned, transitionReason = SC.Commands.completeFactionTrial(
        record.actor, origin, player)
    if not transitioned then return false, transitionReason end
    local completed, completionReason = SC.Factions.completeMemberRecruitment(
        group.id, member.key, record.id)
    if not completed then
        SC.Commands.returnFactionTrial(record.actor, origin)
        return false, "join_rollback:" .. tostring(completionReason)
    end
    state.status = "joined"
    state.decision = "join"
    state.reason = "joined_permanently"
    state.decidedHour = worldHour()
    state.joinedActorId = record.id
    state.actorId = record.id
    append(state.history, {
        hour = worldHour(), kind = "joined", memberKey = member.key,
        actorId = record.id,
    }, 48)
    if SC.FactionLife and type(SC.FactionLife.noteEvent) == "function" then
        SC.FactionLife.noteEvent(group, "member_joined_player", member.key)
    end
    if SC.FactionContracts and type(SC.FactionContracts.noteAction) == "function" then
        SC.FactionContracts.noteAction(group, "recruitment_joined", member.key)
    end
    say(member, "faction.recruit.join", "IGUI_SC_FactionRecruit_Join",
        "I have made my choice. I am staying with you.")
    return true, "joined_permanently"
end

function Recruitment.decide(groupOrId, player, forcedOutcome, automatic)
    local group = groupFor(groupOrId)
    if not group then return false, "faction_unavailable" end
    local state = Recruitment.initialize(group)
    if state.status ~= "trial" then return false, "no_active_trial" end
    local member = memberFor(group, state.candidateKey)
    local record = activeRecord(member)
    if not record or record.id ~= state.actorId then return false, "trial_actor_unavailable" end
    if forcedOutcome == nil and automatic ~= true then
        if worldHour() < (tonumber(state.readyHour) or math.huge) then
            return false, "trial_not_ready"
        end
        local maximum = (tonumber(SC.Config.get("factionTradeDistance")) or 6) + 3
        if player and U().distance(player, record.actor) > maximum then
            return false, "candidate_too_far_away"
        end
    end
    local score = trialDecisionScore(group, state, record)
    state.lastDecisionScore = score
    local outcome = forcedOutcome
    if outcome == nil then
        outcome = score >= 68 and "join"
            or score >= 48 and state.extensions < 1 and "more_time" or "return"
    end
    if outcome == "join" then return joinPlayer(group, state, record, player) end
    if outcome == "return" then return returnToHousehold(group, state, record, "trial_decision") end
    if outcome ~= "more_time" then return false, "invalid_recruitment_decision" end
    state.extensions = state.extensions + 1
    state.decision = "more_time"
    state.reason = "candidate_needs_more_time"
    local extension = tonumber(SC.Config.get("factionRecruitmentExtensionHours")) or 12
    state.readyHour = worldHour() + extension
    state.deadlineHour = math.max(tonumber(state.deadlineHour) or 0,
        state.readyHour + math.max(3, extension / 2))
    append(state.history, {
        hour = worldHour(), kind = "more_time", memberKey = member.key, score = score,
    }, 48)
    say(member, "faction.recruit.more_time", "IGUI_SC_FactionRecruit_MoreTime",
        "I need more time before I make that choice.")
    return true, "more_time_requested"
end

function Recruitment.returnNow(groupOrId, player, forced)
    local group = groupFor(groupOrId)
    if not group then return false, "faction_unavailable" end
    local state = Recruitment.initialize(group)
    if state.status ~= "trial" then return false, "no_active_trial" end
    local member = memberFor(group, state.candidateKey)
    local record = activeRecord(member)
    if not record then return false, "trial_actor_unavailable" end
    if forced ~= true and player and U().distance(player, record.actor) > 12 then
        return false, "candidate_too_far_away"
    end
    return returnToHousehold(group, state, record, "player_ended_trial")
end

function Recruitment.originForActor(actorId)
    if type(actorId) ~= "string" or not SC.Factions then return nil end
    for _, group in ipairs(SC.Factions.list(false) or {}) do
        local state = Recruitment.initialize(group)
        if state.actorId == actorId or state.joinedActorId == actorId then
            return {
                factionId = group.id, memberKey = state.candidateKey,
                status = state.status, group = group,
            }
        end
    end
    return nil
end

function Recruitment.actorDied(actorId, factionId)
    local origin = Recruitment.originForActor(actorId)
    local group = origin and origin.group or groupFor(factionId)
    if not group then return false, "recruitment_origin_unavailable" end
    local state = Recruitment.initialize(group)
    if state.actorId ~= actorId and state.joinedActorId ~= actorId then
        return false, "actor_not_recruitment_candidate"
    end
    state.status = "dead"
    state.decision = "dead"
    state.reason = "candidate_died"
    state.decidedHour = worldHour()
    append(state.history, {
        hour = worldHour(), kind = "candidate_died", memberKey = state.candidateKey,
        actorId = actorId,
    }, 48)
    return true, "candidate_death_recorded"
end

function Recruitment.pulseGroup(groupOrId, player, current)
    local group = groupFor(groupOrId)
    if not group then return false, "faction_unavailable" end
    local state = Recruitment.initialize(group)
    current = tonumber(current) or U().nowMs()
    if current < state.nextPulseAt then return true, "recruitment_pulse_throttled" end
    state.nextPulseAt = current + 2500
    if state.status ~= "trial" then return true, state.status end
    local member = memberFor(group, state.candidateKey)
    local record = activeRecord(member)
    if not record or record.id ~= state.actorId then
        if SC.Persistence and type(SC.Persistence.isPending) == "function"
            and SC.Persistence.isPending(state.actorId) then
            state.missingSinceHour = nil
            return true, "trial_actor_restoring"
        end
        state.missingSinceHour = tonumber(state.missingSinceHour) or worldHour()
        return false, "trial_actor_temporarily_unavailable"
    end
    state.missingSinceHour = nil
    if record.recruited ~= true or record.factionId ~= nil then
        local origin = state.origin or {
            factionId = group.id, memberKey = member.key, factionRole = member.role,
        }
        local repaired, reason = SC.Commands.beginFactionTrial(record.actor, origin, player)
        if not repaired then return false, "trial_reconciliation_failed:" .. tostring(reason) end
    end
    if worldHour() >= (tonumber(state.deadlineHour) or math.huge) then
        return Recruitment.decide(group, player, nil, true)
    end
    return true, "trial_in_progress"
end

function Recruitment.summary(groupOrId)
    local group = groupFor(groupOrId)
    if not group then return nil end
    local state = Recruitment.initialize(group)
    local ready, reason = eligibility(group, false)
    local member = memberFor(group, state.candidateKey)
    local name, first = memberName(member)
    local now = worldHour()
    local result = {
        schema = SCHEMA,
        status = state.status,
        reason = state.reason or (ready and "eligible" or reason),
        candidateKey = state.candidateKey,
        candidateName = member and name or nil,
        candidateFirstName = member and first or nil,
        actorId = state.actorId,
        householdReaction = state.householdReaction,
        willingness = state.willingness,
        decision = state.decision,
        decisionScore = state.lastDecisionScore,
        attempts = state.attempts,
        extensions = state.extensions,
        contractsCompleted = completedContracts(group),
        contractsRequired = tonumber(SC.Config.get("factionRecruitmentContractsRequired")) or 2,
        presentResidents = presentCount(group),
        canAsk = ready == true and state.status == "available",
        canStartTrial = state.status == "candidate" and activeRecord(member) ~= nil,
        canDecide = state.status == "trial" and now >= (tonumber(state.readyHour) or math.huge),
        canReturn = state.status == "trial",
        hoursOnTrial = state.status == "trial"
            and math.max(0, now - (tonumber(state.trialStartedHour) or now)) or 0,
        hoursUntilDecision = state.status == "trial"
            and math.max(0, (tonumber(state.readyHour) or now) - now) or 0,
        cooldownHours = math.max(0, (tonumber(state.cooldownUntilHour) or 0) - now),
        historyCount = #state.history,
    }
    local copied, copyReason = strictCopy(result, copyLimits.summary,
        "$.recruitment.summary")
    if not copied then
        return nil, "recruitment_summary_copy_failed:" .. tostring(copyReason)
    end
    return copied
end

function Recruitment.debugPrepare(groupOrId)
    if not SC.Config or SC.Config.get("debugSpawnEnabled") ~= true then
        return false, "debug_tools_disabled"
    end
    local group = groupFor(groupOrId)
    if not group then return false, "faction_unavailable" end
    group.discovered = true
    group.permanentHostility = false
    group.offenses = {}
    SC.Factions.forceStanding(group.id, "Trusted")
    if SC.FactionContracts and type(SC.FactionContracts.initialize) == "function" then
        local social = SC.FactionContracts.initialize(group)
        social.trade.completedContracts = math.max(
            tonumber(social.trade.completedContracts) or 0,
            tonumber(SC.Config.get("factionRecruitmentContractsRequired")) or 2)
    end
    local state = Recruitment.initialize(group)
    if state.status ~= "trial" and state.status ~= "joined" then
        state.status, state.candidateKey, state.actorId = "available", nil, nil
        state.cooldownUntilHour = 0
    end
    return true, "recruitment_requirements_met"
end

function Recruitment.debugCandidate(groupOrId, player)
    local ready, reason = Recruitment.debugPrepare(groupOrId)
    if not ready then return false, reason end
    return Recruitment.ask(groupOrId, player, true)
end

function Recruitment.debugTrial(groupOrId, player)
    local group = groupFor(groupOrId)
    if not group then return false, "faction_unavailable" end
    local state = Recruitment.initialize(group)
    if state.status ~= "candidate" then
        local named, reason = Recruitment.debugCandidate(group, player)
        if not named then return false, reason end
    end
    return Recruitment.startTrial(group, player, true)
end

function Recruitment.debugDecision(groupOrId, player, outcome)
    if not SC.Config or SC.Config.get("debugSpawnEnabled") ~= true then
        return false, "debug_tools_disabled"
    end
    return Recruitment.decide(groupOrId, player, outcome)
end

function Recruitment.validate(groupOrId)
    local group = groupFor(groupOrId)
    if not group then return false end
    local state = Recruitment.initialize(group)
    if state.schema ~= SCHEMA or not statuses[state.status]
        or type(state.history) ~= "table" or #state.history > 48
        or state.candidateKey ~= nil and type(state.candidateKey) ~= "string"
        or state.actorId ~= nil and type(state.actorId) ~= "string" then return false end
    if (state.status == "candidate" or state.status == "trial")
        and memberFor(group, state.candidateKey) == nil then return false end
    return true
end

return Recruitment
