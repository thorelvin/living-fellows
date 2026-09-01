-- SPDX-License-Identifier: MIT

local SC = SurvivorCompanion
local checks = 0

local function check(value, message)
    checks = checks + 1
    assert(value, "check " .. tostring(checks) .. " failed: " .. tostring(message))
end

local function contains(value, token)
    return string.find(tostring(value), token, 1, true) ~= nil
end

local function makeFlat(count, prefix)
    local result = {}
    for index = 1, count do result[(prefix or "k") .. tostring(index)] = index end
    return result
end

local function actor(id)
    local value = { id = id, data = {} }
    function value:getModData() return self.data end
    return value
end

local commandActor = actor("strict-command")
local exactObjectives = makeFlat(511, "objective") -- root + 511 values = 512
local exactRecord = {
    id = commandActor.id,
    recruited = true,
    objectives = exactObjectives,
    possessions = { keepsake = "baseline" },
}
SC_STRICT_COPY_RECORDS[commandActor.id] = { actor = commandActor, entry = exactRecord }
local restored, restoreReason = SC.Commands.restore(commandActor, exactRecord)
check(restored == true and restoreReason == nil,
    "command restore accepts objectives at the exact 512-value boundary")
local exactExport, exactExportReason = SC.Commands.export(commandActor)
check(exactExport and exactExportReason == nil
        and exactExport.objectives.objective511 == 511,
    "command export preserves the final objective at the exact boundary")
exactObjectives.objective511 = -1
check(exactExport.objectives.objective511 == 511
        and SC.Commands.peek(commandActor).objectives.objective511 == 511,
    "restored and exported objectives are detached from caller-owned input")

local oversizedObjectives = makeFlat(512, "objective")
local oversizedRecord = {
    id = commandActor.id, recruited = true,
    objectives = oversizedObjectives,
    possessions = { keepsake = "must-not-commit" },
}
SC_STRICT_COPY_RECORDS[commandActor.id].entry = oversizedRecord
local oversizedOk, oversizedReason = SC.Commands.restore(commandActor, oversizedRecord)
check(oversizedOk == false and contains(oversizedReason, "$.commands.objectives")
        and contains(oversizedReason, "limit exceeded")
        and SC.Commands.peek(commandActor).objectives.objective511 == 511
        and oversizedRecord.state == nil,
    "one-over objective restore fails with a path and publishes no partial state")

local cyclicObjectives = { marker = "cycle-must-not-commit" }
cyclicObjectives.self = cyclicObjectives
local cyclicRecord = {
    id = commandActor.id, recruited = true,
    objectives = cyclicObjectives,
    possessions = { keepsake = "must-not-commit" },
}
SC_STRICT_COPY_RECORDS[commandActor.id].entry = cyclicRecord
local cyclicOk, cyclicReason = SC.Commands.restore(commandActor, cyclicRecord)
check(cyclicOk == false and contains(cyclicReason, "$.commands.objectives[self]")
        and contains(cyclicReason, "cyclic") and cyclicRecord.state == nil
        and SC.Commands.peek(commandActor).possessions.keepsake == "baseline",
    "cyclic objectives fail at the offending path and preserve prior state")

local exactPossessions = makeFlat(255, "possession") -- root + 255 values = 256
local possessionsRecord = {
    id = commandActor.id, recruited = true,
    objectives = { marker = "possessions-baseline" },
    possessions = exactPossessions,
}
SC_STRICT_COPY_RECORDS[commandActor.id].entry = possessionsRecord
check(SC.Commands.restore(commandActor, possessionsRecord),
    "command restore accepts possessions at the exact 256-value boundary")
local possessionsExport = SC.Commands.export(commandActor)
check(possessionsExport and possessionsExport.possessions.possession255 == 255,
    "command export preserves the final possession at the exact boundary")

local oversizedPossessions = makeFlat(256, "possession")
local possessionsOverRecord = {
    id = commandActor.id, recruited = true,
    objectives = { marker = "must-not-replace" },
    possessions = oversizedPossessions,
}
SC_STRICT_COPY_RECORDS[commandActor.id].entry = possessionsOverRecord
local possessionsOverOk, possessionsOverReason = SC.Commands.restore(
    commandActor, possessionsOverRecord)
check(possessionsOverOk == false
        and contains(possessionsOverReason, "$.commands.possessions")
        and SC.Commands.peek(commandActor).possessions.possession255 == 255
        and possessionsOverRecord.state == nil,
    "one-over possessions fail without replacing the prior command state")

SC_STRICT_COPY_RECORDS[commandActor.id].entry = possessionsRecord
local currentState = SC.Commands.peek(commandActor)
local storedObjectives = possessionsRecord.state.objectives
local commandCycle = { marker = "runtime-cycle" }
commandCycle.self = commandCycle
currentState.objectives = commandCycle
local persisted, persistenceReason = SC.Commands.persist(commandActor)
check(persisted == false and contains(persistenceReason, "$.commands.objectives[self]")
        and possessionsRecord.state.objectives == storedObjectives
        and possessionsRecord.state.objectives.marker == "possessions-baseline",
    "command persistence preflights cycles before touching the previous record")
local failedExport, failedExportReason = SC.Commands.export(commandActor)
check(failedExport == nil and contains(failedExportReason, "$.commands.objectives[self]"),
    "command export rejects a cyclic runtime objective instead of returning a prefix")
currentState.objectives = { marker = "repaired" }

local function baseContract(id)
    return {
        id = id .. ":contract", kind = "supply", status = "active",
        title = "Boundary delivery", complication = "none",
        createdHour = 1, acceptedHour = 1, deadlineHour = 100,
        completedHour = 0, outcome = "pending", revealed = true,
        requirements = {}, progress = { delivered = false },
        reward = { barter = true, access = true, rumour = false,
            safeRest = true, futureRecruitConsideration = true },
        padding = {},
    }
end

local function padStable(value, target)
    local _, reason, count = SC.StableValue.copyStrict(value, {
        maxDepth = 12, maxEntries = 10000, path = "$.fixture",
    })
    assert(reason == nil and count <= target, "fixture cannot reach requested boundary")
    for index = 1, target - count do value.padding["field" .. tostring(index)] = index end
    local _, finalReason, finalCount = SC.StableValue.copyStrict(value, {
        maxDepth = 12, maxEntries = 10000, path = "$.fixture",
    })
    assert(finalReason == nil and finalCount == target, "fixture boundary count mismatch")
    return value
end

local function contractGroup(id, contract)
    local group = {
        id = id, lifecycle = "destroyed", standing = "Trusted", reputation = 0,
        members = { { key = "resident", role = "leader", alive = true,
            identity = { forename = "Test", surname = "Resident" } } },
        history = {}, house = { anchor = { x = 0, y = 0, z = 0 } },
        life = { personality = { primary = "Resourceful",
            values = { openness = 50 } }, resources = { levels = {} } },
    }
    local social = SC.FactionContracts.initialize(group)
    social.contract.active = contract
    social.contract.offer = nil
    SC_STRICT_COPY_GROUPS[id] = group
    return group, social
end

local exactContract = padStable(baseContract("contract-exact"), 512)
local exactGroup, exactSocial = contractGroup("contract-exact", exactContract)
local fulfilled, fulfillReason = SC.FactionContracts.fulfill(exactGroup, nil, true)
check(fulfilled == true and fulfillReason == "agreement_honored"
        and exactSocial.contract.active == nil and #exactSocial.contract.history == 1
        and exactSocial.contract.history[1].padding.field1 ~= nil,
    "contract completion commits a complete history row at the exact boundary")

local oversizedContract = padStable(baseContract("contract-over"), 513)
local overGroup, overSocial = contractGroup("contract-over", oversizedContract)
local overAccessState = overSocial.access.state
local overOk, overReason = SC.FactionContracts.fulfill(overGroup, nil, true)
check(overOk == false and contains(overReason, "$.factionContracts.history.completed")
        and contains(overReason, "limit exceeded")
        and overSocial.contract.active == oversizedContract
        and oversizedContract.status == "active"
        and oversizedContract.progress.delivered == false
        and #overSocial.contract.history == 0
        and overSocial.trade.completedContracts == 0
        and overSocial.access.state == overAccessState,
    "one-over contract history fails before any contract or social mutation")

local cyclicContract = baseContract("contract-cycle")
cyclicContract.loop = cyclicContract
local cycleGroup, cycleSocial = contractGroup("contract-cycle", cyclicContract)
local contractCycleOk, contractCycleReason = SC.FactionContracts.fulfill(
    cycleGroup, nil, true)
check(contractCycleOk == false
        and contains(contractCycleReason, "$.factionContracts.history.completed[loop]")
        and cycleSocial.contract.active == cyclicContract
        and cyclicContract.status == "active" and #cycleSocial.contract.history == 0,
    "cyclic contract fails at its exact path and remains active unchanged")

local corruptOffer = baseContract("contract-offer")
corruptOffer.status = "offered"
corruptOffer.loop = corruptOffer
local offerGroup, offerSocial = contractGroup("contract-offer", nil)
offerSocial.contract.offer = corruptOffer
local accepted, acceptReason = SC.FactionContracts.accept(offerGroup, nil, true)
check(accepted == false and contains(acceptReason, "$.factionContracts.active[loop]")
        and offerSocial.contract.offer == corruptOffer
        and offerSocial.contract.active == nil and corruptOffer.status == "offered",
    "contract acceptance cannot replace a corrupt offer with a partial active copy")

local requirementCycle = {}
requirementCycle.self = requirementCycle
local needGroup, needSocial = contractGroup("contract-need", nil)
needGroup.lifecycle = "destroyed"
needGroup.request = { required = requirementCycle }
needGroup.life.crisis = { active = { kind = "supply_collapse" } }
local sequenceBefore = needSocial.contract.sequence
local needAccepted, needReason = SC.FactionContracts.accept(needGroup, nil, true)
check(needAccepted == false
        and contains(needReason, "$.factionContracts.offer.requirements[self]")
        and needSocial.contract.sequence == sequenceBefore
        and needSocial.contract.offer == nil and needSocial.contract.active == nil,
    "contract creation preserves the previous slot and sequence after requirement-copy failure")

local productionCommands = SC.Commands
local detachOrigin
local detachCount, rollbackCount, transitionCount = 0, 0, 0
SC.Commands = {
    beginFactionTrial = function()
        transitionCount = transitionCount + 1
        return true, "transitioned"
    end,
}
SC.FactionContracts = { noteAction = function() return true end,
    initialize = function(group)
        group.social = group.social or { trade = { completedContracts = 2 } }
        group.social.trade = group.social.trade or { completedContracts = 2 }
        return group.social
    end }

SC.Factions.detachMemberForRecruitment = function(_, memberKey)
    detachCount = detachCount + 1
    local group = SC_STRICT_COPY_GROUPS.recruitment
    local member = SC.Factions.member(group, memberKey)
    member.away = "recruitment_trial"
    return true, detachOrigin
end
SC.Factions.restoreMemberFromRecruitment = function(_, memberKey)
    rollbackCount = rollbackCount + 1
    local member = SC.Factions.member(SC_STRICT_COPY_GROUPS.recruitment, memberKey)
    member.away = nil
    return true, member
end

local function recruitmentCase(origin)
    local candidate = { key = "candidate", role = "resident", actorId = "recruit-actor",
        alive = true, identity = { forename = "Casey", surname = "Test" } }
    local group = {
        id = "recruitment", lifecycle = "active", standing = "Trusted",
        discovered = true, permanentHostility = false, reputation = 50,
        members = { candidate, { key = "other", role = "leader", alive = true,
            actorId = "other-actor", identity = { forename = "Other", surname = "Test" } } },
        offenses = {}, social = { trade = { completedContracts = 2 } },
        life = { personality = { values = { openness = 60, solidarity = 40 } },
            relationships = {} },
        recruitment = { schema = 1, status = "candidate", candidateKey = "candidate",
            actorId = "recruit-actor", history = {}, attempts = 1, extensions = 0 },
    }
    SC_STRICT_COPY_GROUPS.recruitment = group
    local recruitActor = actor("recruit-actor")
    SC_STRICT_COPY_RECORDS[recruitActor.id] = {
        actor = recruitActor, entry = { id = recruitActor.id }, factionId = group.id,
    }
    detachOrigin = origin
    return group, candidate
end

local exactOrigin = {
    actorId = "recruit-actor", role = "resident", departed = false,
    hibernated = false, factionId = "recruitment", memberKey = "candidate",
    factionRole = "resident", padding = {},
}
padStable(exactOrigin, 32)
local exactRecruitGroup, exactCandidate = recruitmentCase(exactOrigin)
local exactTrial, exactTrialReason = SC.FactionRecruitment.startTrial(
    exactRecruitGroup, nil, true)
check(exactTrial == true and exactTrialReason == "trial_started"
        and exactRecruitGroup.recruitment.status == "trial"
        and exactRecruitGroup.recruitment.origin.padding.field1 ~= nil
        and exactCandidate.away == "recruitment_trial",
    "recruitment accepts and stores the complete origin at its exact boundary")

local oversizedOrigin = {
    actorId = "recruit-actor", role = "resident", departed = false,
    hibernated = false, factionId = "recruitment", memberKey = "candidate",
    factionRole = "resident", padding = {},
}
padStable(oversizedOrigin, 33)
local overRecruitGroup, overCandidate = recruitmentCase(oversizedOrigin)
local transitionsBefore = transitionCount
local rollbacksBefore = rollbackCount
local overTrial, overTrialReason = SC.FactionRecruitment.startTrial(
    overRecruitGroup, nil, true)
check(overTrial == false and contains(overTrialReason, "$.recruitment.origin")
        and contains(overTrialReason, "limit exceeded")
        and transitionCount == transitionsBefore and rollbackCount == rollbacksBefore + 1
        and overCandidate.away == nil
        and overRecruitGroup.recruitment.status == "candidate"
        and overRecruitGroup.recruitment.origin == nil
        and #overRecruitGroup.recruitment.history == 0,
    "one-over recruitment origin rolls household membership back before transition")

local cyclicOrigin = {
    actorId = "recruit-actor", role = "resident", departed = false,
    hibernated = false, factionId = "recruitment", memberKey = "candidate",
    factionRole = "resident",
}
cyclicOrigin.self = cyclicOrigin
local cycleRecruitGroup, cycleCandidate = recruitmentCase(cyclicOrigin)
transitionsBefore, rollbacksBefore = transitionCount, rollbackCount
local cycleTrial, cycleTrialReason = SC.FactionRecruitment.startTrial(
    cycleRecruitGroup, nil, true)
check(cycleTrial == false and contains(cycleTrialReason, "$.recruitment.origin[self]")
        and contains(cycleTrialReason, "cyclic")
        and transitionCount == transitionsBefore and rollbackCount == rollbacksBefore + 1
        and cycleCandidate.away == nil
        and cycleRecruitGroup.recruitment.status == "candidate",
    "cyclic recruitment origin is observable and leaves no partial trial")

SC.Commands = productionCommands

print("STRICT_COPY_BOUNDARY_HARNESS_PASS checks=" .. tostring(checks)
    .. " detaches=" .. tostring(detachCount) .. " rollbacks=" .. tostring(rollbackCount))
