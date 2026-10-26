-- SPDX-License-Identifier: MIT
local A, P, checks = SurvivorCompanion.ALifeAdapter, ProjectALife, 0
local function check(value, message) checks = checks + 1 assert(value, "A-Life hardening " .. checks .. ": " .. message) end
local actor = ALIFE_TEST_ACTOR("sc-hardened", true)
local shell, record = ALIFE_TEST_NPC("hardened-foreign")
ALIFE_TEST_MODS.ProjectALifeNPCs = nil
check(not A.initialize() and A.status().state == "absent", "absent dependency stays optional")
ALIFE_TEST_MODS.ProjectALifeNPCs = true
local attack = P.Combat.resolveAttack
P.Combat.resolveAttack = nil
check(not A.initialize() and A.status().state == "unsupported", "missing critical interfaces fail closed")
check(P.Reputation.playerKey(actor) == "lf:sc-hardened", "identity guards do not wait for damage interfaces")
P.Reputation.onPlayerDied(actor)
check(ALIFE_TEST_LIFECYCLE == 0, "partial initialization still protects player death state")
P.Combat.resolveAttack = attack
local adapters = P.Perception.adapters
P.Perception.adapters = nil
A.pulse(SC_TEST_CLOCK + 1000)
check(not A.status().active and string.find(A.status().reason, "not initialized", 1, true),
    "late perception configuration remains a retryable startup condition")
check(P.Reputation.playerKey(actor) == "lf:sc-hardened", "delayed perception retains identity isolation")
P.Perception.adapters = adapters
A.pulse(SC_TEST_CLOCK + 2000)
check(A.status().active, "bounded watchdog recovers late interface availability")
check(#Events.ProjectALife_NpcHit.callbacks == 1, "initialization installs one owner hit listener")
for _ = 1, 20 do A.initialize() end
check(#Events.ProjectALife_NpcHit.callbacks == 1, "repeated initialization does not accumulate listeners")
local stampAlias, stampGeneration = P.TargetPolicy.identityOf(actor)
local staleSource = { uid = record.uid, generation = record.generation - 1, lifecycle = "active" }
check(not P.Combat.resolveAttack(staleSource, shell, actor, { damage = 10 }) and actor.body.hits == 0,
    "a stale attack record cannot borrow the authority of the current live shell")
local sourceGeneration = record.generation
ALIFE_TEST_BEFORE_WOUND = function()
    record.generation = sourceGeneration + 1
    shell.md.ProjectALifeGeneration = sourceGeneration + 1
    P.Watchdog.bindings[record.uid].generation = sourceGeneration + 1
end
check(not P.Combat.resolveAttack(record, shell, actor, { damage = 10 }) and actor.body.hits == 0,
    "recycling the source binding during a wound callback retires its admitted authority")
ALIFE_TEST_BEFORE_WOUND = nil
record.generation, shell.md.ProjectALifeGeneration = sourceGeneration, sourceGeneration
P.Watchdog.bindings[record.uid].generation = sourceGeneration
actor.slot = 2
local movedAlias, movedGeneration = P.TargetPolicy.identityOf(actor)
check(movedAlias == stampAlias and movedGeneration == stampGeneration
    and P.Reputation.playerKey(actor) == stampAlias, "view-slot changes cannot change LF identities")
local beforeMain, ownBody = ALIFE_TEST_PLAYER.body.damage, actor.getBodyDamage
actor.getBodyDamage = function() return ALIFE_TEST_PLAYER.body end
check(not P.Combat.resolveAttack(record, shell, actor, { damage = 10 }) and ALIFE_TEST_PLAYER.body.damage == beforeMain,
    "a wrong BodyDamage owner cannot redirect an LF attack into the main player")
actor.getBodyDamage = ownBody
local oldBody = actor.body
ALIFE_TEST_BEFORE_WOUND = function(value) value.removed = true end
check(not P.Combat.resolveAttack(record, shell, actor, { damage = 10 }) and oldBody.hits == 0,
    "native teardown between admission and application aborts without damage")
ALIFE_TEST_BEFORE_WOUND, actor.removed = nil, false
local peak = P.Perception.adapters.players()
actor.dead = true
check(A.resolve(stampAlias) == nil and #P.Perception.adapters.players() == #peak - 1,
    "dead actors are filtered even inside the membership-cache interval")
actor.dead = false
local saved = record.generation
record.generation = 0 / 0
check(A.relationship(shell, actor) == "unknown", "non-finite generations are never trusted")
record.generation = saved
local peek = P.ActorRegistry.peek
P.ActorRegistry.peek = function() error("registry_unavailable", 0) end
check(A.owns(shell) and A.relationship(shell, actor) == "unknown", "registry lookup failure leaves marked shells protected humans")
P.ActorRegistry.peek = peek
local retainedStatus = P.Reputation.recordedStatus
local retainedBaseline = P.Relations.baselineStance
local retainedWound, retainedAttack = P.Wounds.damagePlayer, P.Combat.resolveAttack
local oldListener = Events.ProjectALife_NpcHit.callbacks[1]
A.reset()
check(#Events.ProjectALife_NpcHit.callbacks == 0, "reset removes its event listeners")
ALIFE_TEST_REPUTATION["sp:0"] = { hostile = "hostile" }
check(retainedStatus(actor, record) == nil and retainedBaseline(record, actor) == "neutral",
    "retired reputation wrappers cannot fall through to the player's native slot key")
oldListener(shell, actor, 5)
check(A.status().state == "absent", "retired event callbacks cannot wake a new world")
-- A third-party wrapper can retain the old wound and attack hooks. Fresh
-- attack authority can traverse that chain; an old standalone callback cannot.
P.Wounds.damagePlayer = function(...) return retainedWound(...) end
P.Combat.resolveAttack = function(...) return retainedAttack(...) end
check(A.initialize(), "a new world can chain a retained foreign damage wrapper")
local damage, woundCount = actor.body.damage, A.status().wounds
check(P.Combat.resolveAttack(record, shell, actor, { damage = 4 }) and actor.body.damage == damage + 4,
    "a fresh nested wrapper chain applies the original damage once")
check(A.status().wounds == woundCount + 1, "retained wrappers do not double-count the fresh wound")
check(not pcall(retainedWound, actor.body, { damage = 50 }) and actor.body.damage == damage + 4,
    "the same retained hook has no standalone wound authority")
local provider = P.Perception.adapters.players
P.Perception.configure({ players = function() return "bad" end })
check(#P.Perception.adapters.players() == 0 and A.status().state == "unsupported",
    "malformed source lists disable integration without feeding fake actors into A-Life")
A.reset()
check(pcall(provider), "old derived lists stay safe after their owners are retired")
P.Perception.configure({})
check(A.initialize(), "a new world recovers from a prior malformed provider")
local called = 0
P.Perception.configure({ players = function() called = called + 1 error("foreign_provider_failure", 0) end })
check(#P.Perception.adapters.players() == 0 and called == 1 and not A.status().active,
    "foreign-provider failures are caught and are never replayed")
A.reset()
P.Perception.configure({})
check(A.initialize(), "fresh initialization remains possible")
for _, cohort in ipairs({ 1, 4, 16 }) do
    for index = 2, cohort do
        if not ALIFE_TEST_RECORDS["sc-cohort-" .. index] then ALIFE_TEST_ACTOR("sc-cohort-" .. index, true) end
    end
    A.invalidate()
    local baseline = ALIFE_TEST_ENUMERATIONS
    local expected = #P.Perception.adapters.players()
    local stable = true
    for index = 1, 1000 do
        SC_TEST_CLOCK = SC_TEST_CLOCK + 1
        if #P.Perception.adapters.players() ~= expected then stable = false end
    end
    check(stable, "derived membership remains stable across repeated AI reads")
    check(ALIFE_TEST_ENUMERATIONS - baseline <= 5, "membership enumeration remains bounded at 1, 4 and 16 LF actors")
end
SC_TEST_REPORT = "ALIFE_HARDENING_PASS checks=" .. tostring(checks)
