-- SPDX-License-Identifier: MIT
local SC, f = SurvivorCompanion, SurvivorCompanion.TestFixture
local C, B, player = SC.InfectionCrisis, SC.BaseLife, f.player
local subjectId, helperId, crisisId = "sc-missing-subject", "sc-crisis-medic", "crisis:1"
local helper = f.actor(helperId, 3, 1, {})
f.registry[helperId] = { id = helperId, actor = helper }
getSpecificPlayer = function(index) if index == 0 then return player end end
getPlayer = function() return player end
assert(B.create({ x = 3, y = 1, z = 0 }, "Crisis camp"))

local checks = 0
local function check(ok, message)
    checks = checks + 1
    assert(ok, "crisis subject: " .. message)
end
local function member()
    return { knowledge = "confirmed", certainty = 100, spoken = true }
end
local function seed(id, outcome, owner)
    C.reset()
    assert(B.setRestriction(id, nil))
    local row = {
        id = crisisId, subjectId = id, subjectName = "Jill", outcome = outcome,
        phase = "resolved", strategy = "confess", stage = "watching", effectiveRestriction = "watch",
        createdAt = f.clock, resolvedAt = f.clock, updatedAt = f.clock, irreversibleAfter = f.clock - 1,
        decisionRevision = 1, noticeRevision = 1, progressVersion = 2,
        participants = { [id] = member(), ["player:local"] = member(), [helperId] = member() },
        finalAuthorized = outcome == "self_sacrifice", finalAuthorizedAt = f.clock,
        authorizedRevision = 1, evidence = {}, artifacts = {},
    }
    assert(C.restore({ version = 1, nextSerial = 2, crises = { [crisisId] = row },
        observations = {}, history = {} }))
    assert(B.setRestriction(id, "watch", owner))
end

local absence = "gone"
SC.Persistence = {
    restoreStatus = function() return absence ~= "uncommitted" end,
    isPending = function(id) return id == subjectId and absence == "pending" end,
    pendingRestoreStatus = function(id) if id == subjectId and absence == "quarantine" then return "quarantined" end end,
}
SC.Vehicle.contains = function(id) return id == subjectId and absence == "vehicle" end
SC.Factions.retainsActor = function(id) return id == subjectId and absence == "household" end
SC.TaxiService = { retainsActor = function(id) return id == subjectId and absence == "taxi" end }
local observed, lookups, registryLookup = nil, 0, SC.Registry.byId
SC.Registry.byId = function(id)
    if id == observed then lookups = lookups + 1 end
    return registryLookup(id)
end
local function pulse(id)
    observed, lookups = id, 0
    assert(C.pulse(player, f.clock))
    observed = nil
    return lookups
end
local function history(kind, id)
    local matching = {}
    for _, entry in ipairs(C.export().history) do
        if entry.kind == kind and entry.subjectId == id then matching[#matching + 1] = entry end
    end
    return matching
end

local cancelled = 0
SC.Navigation.peek = function(actor)
    if actor == helper then return { lastApproachRequest = { intent = { crisisId = crisisId } } } end
end
SC.Navigation.cancel = function(actor) assert(actor == helper); cancelled = cancelled + 1 end
seed(subjectId, "self_sacrifice", nil) -- Pre-ownership saves adopted this watch restriction.
assert(B.assign(subjectId, "guard", true) and B.forgetGoneResident(subjectId))
assert(not B.resident(subjectId) and B.restriction(subjectId) == "watch")
local oldLookups = pulse(subjectId)
local saved = C.export()
local row = saved.crises[crisisId]
check(row.phase == "terminal" and row.stage == "ended", "orphan left open")
check(row.archivedAt ~= nil and row.archive ~= nil, "orphan missing archive")
check(not B.restriction(subjectId) and not B.restrictionOwner(subjectId), "restriction remains after roster removal")
check(C.summary(player).active == 0 and #C.summary(player).rows == 0, "orphan remains in camp panel")
local events = history("subject_gone", subjectId)
check(#events == 1 and events[1].crisisId == crisisId and events[1].outcome == "self_sacrifice"
    and #C.summary(player).history == 1, "missing subject history or wrong verdict")
check(cancelled == 1, "surviving participant kept the crisis navigation")
check(oldLookups == 1, "repeated subject lookup while adopting and clearing a legacy watch")
assert(C.restore(saved))
pulse(subjectId)
check(#history("subject_gone", subjectId) == 1 and #C.summary(player).rows == 0, "orphan reopened or history repeated on reload")

local available = f.actor(subjectId, 2, 1, {})
f.registry[subjectId] = { id = subjectId, actor = available }
seed(subjectId, "self_sacrifice", crisisId)
assert(C.authorize(crisisId, "self_sacrifice", 1) and C.export().crises[crisisId].finalAuthorized)
f.registry[subjectId] = nil
pulse(subjectId)
check(not C.export().crises[crisisId].finalAuthorized, "missing subject kept live authorization")

seed(subjectId, "watch", "another-crisis")
pulse(subjectId)
check(B.restriction(subjectId) == "watch" and B.restrictionOwner(subjectId) == "another-crisis",
    "unrelated restriction cleared")
seed(subjectId, "watch", crisisId)
assert(B.setRestriction(subjectId, "exiled")) -- Player replaced the crisis's watch order.
pulse(subjectId)
check(B.restriction(subjectId) == "exiled" and not B.restrictionOwner(subjectId), "manual restriction cleared")

for _, reason in ipairs({ "uncommitted", "pending", "quarantine", "vehicle", "household", "taxi", "dormant" }) do
    absence = reason
    f.registry[subjectId] = reason == "dormant" and { id = subjectId, dormant = true } or nil
    seed(subjectId, "watch", crisisId)
    local count = pulse(subjectId)
    check(C.export().crises[crisisId].phase == "resolved" and B.restrictionOwner(subjectId) == crisisId
        and #history("subject_gone", subjectId) == 0 and #C.summary(player).rows == 1,
        reason .. " subject retired")
    check(count == 1, reason .. " subject lookup count")
end

absence = "gone"
local dead = f.actor(subjectId, 2, 1, {})
dead.dead = true
f.registry[subjectId] = { id = subjectId, actor = dead }
seed(subjectId, "watch", crisisId)
local corpseLookups = pulse(subjectId)
check(C.export().crises[crisisId].phase == "terminal" and not B.restriction(subjectId)
    and #history("subject_died", subjectId) == 1 and #history("subject_gone", subjectId) == 0, "visible corpse lost death history")
check(corpseLookups == 1, "registered corpse looked up again on retirement")
f.registry[subjectId] = nil

for _, id in ipairs({ "player:local", "player:local#7" }) do
    seed(id, "watch", crisisId)
    local count = pulse(id)
    check(count == 0 and C.export().crises[crisisId].phase == "resolved" and B.restrictionOwner(id) == crisisId,
        id .. " treated as a companion")
end
seed("player:local", "watch", crisisId)
local previous = C.export()
previous.playerToken = "earlier-character"
assert(C.restore(previous))
pulse("player:local")
local rotated = C.export().crises[crisisId]
check(rotated.subjectId == "player:local#1" and rotated.phase == "terminal"
    and #history("character_replaced", rotated.subjectId) == 1 and #history("subject_gone", rotated.subjectId) == 0,
    "replacement lost the former character's identity or history")
SC_TEST_REPORT = "CRISIS_SUBJECT_PASS checks=" .. checks
