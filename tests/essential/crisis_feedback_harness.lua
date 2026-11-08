-- SPDX-License-Identifier: MIT
-- Outcome, ownership and discovery checks in the existing gameplay fixture.
local SC, f = SurvivorCompanion, SurvivorCompanion.TestFixture
local C, B, S = SC.InfectionCrisis, SC.BaseLife, SC.ActionSupervisor
local check, player = f.check, f.player
getSpecificPlayer = function(index) return index == 0 and player or nil end
getPlayer = function() return player end
local subject, helper = f.actor("crisis-subject", 3, 1, {}), f.actor("crisis-helper", 4, 1, {})
f.registry[subject.id], f.registry[helper.id] = subject, helper
subject.modData.SC_Order, helper.modData.SC_Order = "base_duty", "base_duty"
B.create(subject.square, "Crisis camp")
B.assign(subject.id, "generalist", true)
B.assign(helper.id, "medic", true)
subject.square.outside, helper.square.outside = false, false
local quiet = { threatCount = 0, immediateCount = 0 }
local function member(knowledge)
    return { knowledge = knowledge or "confirmed", certainty = 100,
        stance = "pragmatic", spoken = true }
end
local function seed(outcome, overrides)
    C.reset()
    B.setRestriction(subject.id, nil)
    local row = { id = "crisis:1", subjectId = subject.id, subjectName = "Jill",
        phase = "resolved", strategy = "confess", outcome = outcome,
        createdAt = f.clock, updatedAt = f.clock, resolvedAt = f.clock,
        irreversibleAfter = f.clock - 1, deliberateAfter = f.clock - 1,
        biteCount = 1, infectionLevel = 0, artifacts = {}, evidence = {},
        participants = { ["player:local"] = member(), [subject.id] = member(), [helper.id] = member() },
        finalAuthorized = false, decisionRevision = 1, noticeRevision = 1, progressVersion = 2,
        stage = outcome == "watch" and "watching" or "moving" }
    for key, value in pairs(overrides or {}) do row[key] = value end
    check(C.restore({ version = 1, nextSerial = 2, crises = { [row.id] = row },
        observations = {}, history = {} }), "crisis restores through its real validator")
    return row.id
end

local zoneCenter, request = B.zoneCenter, SC.Navigation.request
local target
B.zoneCenter = function(kind) if kind == "quarantine" then return target end return zoneCenter(kind) end
local id = seed("quarantine", { outcomeCompletedAt = f.clock })
B.setRestriction(subject.id, "quarantine") -- Legacy unowned verdict, adopted narrowly on restore.
C.pulse(player, f.clock)
local row = C.summary(player).rows[1]
check(row.stage == "route_pending" and row.restriction == "watch" and row.canRetry,
    "a missing quarantine is pending under watch, never falsely complete")
check(C.intentFor(subject, player, quiet) == nil, "a pending route releases its action claim")
check(B.workPermitted(subject.id, { type = "sort" }) and not B.workPermitted(subject.id, { type = "farm" }),
    "watch permits indoor sorting and suspends outdoor work")
check(B.watchMovementPermitted(subject, subject.square, {})
    and not B.watchMovementPermitted(subject, f.makeSquare(20, 1, 0), {}),
    "watch checks actual camp and indoor movement boundaries")
check(C.retry(id, 0) == false and C.retry(id, 1), "manual recovery rejects stale decisions")
target = f.makeSquare(3, 1, 1); target.outside = false
SC.Navigation.request = function() return true, "moving" end
C.pulse(player, f.clock)
check(C.intentFor(subject, player, { threatCount = 1, immediateCount = 0, closeThreatCount = 0 }) ~= nil,
    "a distant non-immediate zombie does not block a safe indoor quarantine route")
local choices = SC.Decision._evaluateForTests(subject, player,
    { threats = {}, allies = {}, threatCount = 1, immediateCount = 0, closeThreatCount = 0,
        pressure = 0, player = { danger = 0 } },
    { recruited = true, order = "base_duty", commandSerial = 1 },
    { health = 100, alive = true, wounds = {}, bleedingCount = 0 },
    { hunger = .2, thirst = .1 }, {}, f.clock)
check(choices[1].kind == "infection_crisis", "safe withdrawal wins arbitration over a distant combat candidate with no target")
C.updateActor(subject, player, quiet)
check(C.export().crises[id].outcomeCompletedAt == nil, "the floor below quarantine does not count as arrival")
subject.square = target
C.updateActor(subject, player, quiet)
check(C.summary(player).rows[1].restriction == "quarantine"
    and C.export().crises[id].outcomeCompletedAt ~= nil, "verified arrival applies quarantine")
check(C.release(id, "test", 1) and B.restriction(subject.id) == nil,
    "release clears the exact crisis-owned restriction")

subject.square = f.makeSquare(3, 1, 0); subject.square.outside = false
target = nil
id = seed("quarantine")
C.pulse(player, f.clock)
f.worldHour = f.worldHour + 4 / 60
target = f.makeSquare(4, 1, 0); target.outside = false
C.pulse(player, f.clock)
check(C.summary(player).rows[1].stage == "moving", "time and a changed area reopen bounded recovery")
B.setRestriction(subject.id, "watch", "another-owner")
-- A direct player edit deliberately replaces the crisis mark.
B.setRestriction(subject.id, "watch")
C.release(id, "test", 1)
check(B.restriction(subject.id) == "watch", "release preserves a later manual restriction")

id = seed("watch", { participants = { [subject.id] = member(), ["player:local"] = member("unaware") },
    strategy = "conceal", history = {} })
B.setRestriction(subject.id, "watch", id)
row = C.summary(player).rows[1]
check(row and not row.knownToViewer and not row.unread and row.infectionLevel == nil and row.strategy == nil,
    "private staffing restrictions do not disclose hidden infection or intentions")
check(C.authorize(id, "mercy", 1) == false, "an undiscovered crisis cannot be authorized by guessing its id")

-- Discovery follows the actual medical claim, never merely a nearby medic.
id = seed("watch", { participants = { [subject.id] = member(), [helper.id] = member("unaware"),
    ["player:local"] = member("unaware") }, strategy = "conceal" })
local medical, peek, oldBody = SC.Medical, SC.Medical.peek, subject.body
subject.body = f.bodyDamage(100, { f.bodyPart({ isBitten = true }) })
medical.invalidate(subject)
check(medical.claimPatient(helper, subject, f.clock), "medic holds this patient's treatment claim")
medical.peek = function() return { phase = "bandaging", patient = helper } end
C.pulse(player, f.clock)
check(C.export().crises[id].participants[helper.id].knowledge == "unaware",
    "another patient's care cannot disclose this subject's bite")
medical.peek = function() return { phase = "bandaging", patient = subject } end
C.pulse(player, f.clock)
check(C.export().crises[id].participants[helper.id].knowledge == "confirmed"
    and C.summary(helper).rows[1].knownToViewer and #C.summary(player).rows == 0,
    "actual medic care confirms only the medic's knowledge")
medical.peek, subject.body = peek, oldBody
medical.releasePatient(helper, subject)
medical.invalidate(subject)

id = seed("watch")
check(C.acknowledge(id, 1), "the current notice can be acknowledged")
check(C.restore(C.export()) and C.summary(player).rows[1].unread == false,
    "notice acknowledgement survives save and restore")
check(C.choose(id, "mercy", 1), "a known reversible verdict can be reconsidered")
row = C.summary(player).rows[1]
check(C.authorize(id, "mercy", 1) == false and C.authorize(id, "mercy", row.decisionRevision),
    "authorization is bound to the current decision")
check(C.intentFor(subject, player, quiet) == nil, "the victim never executes the executor's mercy action")
check(C.intentFor(helper, player, { threatCount = 1, immediateCount = 1 }) == nil,
    "authorized crisis actions yield to immediate safety")
local native, calls = SC.NativeActions, 0
SC.NativeActions = { performEndOfLife = function() calls = calls + 1 return false, "final_action_requires_weapon" end }
C.updateActor(helper, player, quiet)
check(calls == 1 and not C.summary(player).rows[1].finalAuthorized
    and C.intentFor(helper, player, quiet) == nil, "an unavailable final action stops and requires review instead of looping")
SC.NativeActions = native
id = seed("mercy", { finalAuthorized = true, finalStarted = true, authorizedRevision = 1, executorId = helper.id })
check(C.authorize(id, "mercy", 1) == false and C.intentFor(helper, player, quiet) == nil,
    "reload does not replay an ambiguous irreversible effect")
C.release(id, "test", 1)
check(#C.summary(player).history > 0, "known crisis history remains available after release")
id = seed("quarantine")
C.pulse(player, f.clock)
subject.dead = true
C.pulse(player, f.clock)
check(#C.summary(player).rows == 0 and B.restriction(subject.id) == nil,
    "death retires the decision and its owned restriction")
subject.dead = false
B.zoneCenter, SC.Navigation.request = zoneCenter, request

id = seed("self_sacrifice")
local decisions = C.export()
local second = SC.GameplayUtil.copyShallow(decisions.crises[id])
second.id, second.subjectId, second.subjectName = "crisis:2", helper.id, "Other subject"
decisions.crises[second.id], decisions.nextSerial = second, 3
check(C.restore(decisions) and C.authorize(id, "self_sacrifice", 1)
    and C.authorize(second.id, "self_sacrifice", 1),
    "independent decisions without executors do not block one another")
local executor = f.actor("crisis-executor", 5, 1, {})
f.registry[executor.id] = executor
for _, decision in pairs(decisions.crises) do
    decision.outcome, decision.executorId = "mercy", executor.id
    decision.participants[executor.id] = member()
end
check(C.restore(decisions) and C.authorize(id, "mercy", 1), "the first executor claim is authorized")
local allowed, conflict = C.authorize(second.id, "mercy", 1)
check(not allowed and conflict == "crisis_actor_busy", "a real shared executor still blocks a conflicting decision")
decisions.crises[id].executorId = helper.id
check(C.restore(decisions) and C.authorize(id, "mercy", 1), "one subject can be another decision's executor")
allowed, conflict = C.authorize(second.id, "mercy", 1)
check(not allowed and conflict == "crisis_actor_busy", "a subject already acting as executor remains protected")
C.reset()

local token = assert(S.begin(helper, { owner = "feedback-test", action = "sort", targetKey = "shelf-a" }))
S.fail(token, "destination_full")
local summary = S.summary(helper, true)
check(SC.ActionFeedback.failure(summary).kind == "storage_full", "current blockers have useful player wording")
local nextToken = assert(S.begin(helper, { owner = "feedback-test", action = "clean", targetKey = "sink-b" }))
check(SC.ActionFeedback.failure(S.summary(helper, true)) == nil, "a replacement task resolves stale current feedback")
S.complete(nextToken, "done")
check(S.summary(helper, true).lastFailure ~= nil, "historical failures remain available after recovery")
local feedback = SC.ActionFeedback.failure({ feedbackVersion = 1,
    blocker = { action = "sort", targetKey = "a", reason = "unexpected_new_code" },
    retry = { action = "clean", targetKey = "b", remainingMs = 9000 } })
check(feedback.kind == "unknown" and feedback.remainingMs == nil,
    "unknown failures have a safe explanation and never inherit another task's timer")
SC_TEST_REPORT = "Crisis/feedback PASS: arrival, indoor watch, retries, revision checks, privacy, safety, reload and exact ownership"
