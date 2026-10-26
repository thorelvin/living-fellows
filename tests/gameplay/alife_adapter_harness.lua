-- SPDX-License-Identifier: MIT
local SC, A, P = SurvivorCompanion, SurvivorCompanion.ALifeAdapter, ProjectALife
local checks = 0
local function check(value, message) checks = checks + 1 assert(value, "A-Life check " .. checks .. ": " .. message) end
local member = ALIFE_TEST_ACTOR("sc-alife-member", true)
local resident = ALIFE_TEST_ACTOR("sc-alife-resident")
ALIFE_TEST_RECORDS[resident.md.SC_Id].resident = {}
local household = ALIFE_TEST_ACTOR("sc-alife-household")
local folk = ALIFE_TEST_ACTOR("sc-alife-folk")
ALIFE_TEST_RECORDS[household.md.SC_Id].factionId = "household"
ALIFE_TEST_RECORDS[folk.md.SC_Id].factionId = "strange_folk"
local shell, record = ALIFE_TEST_NPC("alife-1")
local originalPlayers, originalKey, originalPolicy = P.PlayerLocator.list, P.Reputation.playerKey, P.TargetPolicy.canAttack
check(A.initialize() and A.status().active, "valid single-player interfaces activate")
check(A.initialize() and P.PlayerLocator.list == originalPlayers, "repeat initialization never hooks the global player locator")
check(P.Reputation.playerKey(ALIFE_TEST_PLAYER) == "sp:0", "main player key is unchanged")
for _, actor in ipairs({ member, resident, household, folk }) do
    check(P.Reputation.playerKey(actor) == "lf:" .. actor.md.SC_Id, "every LF actor has a distinct reputation key")
    check(A.resolve(A.idFor(actor)) == actor, "every living LF alias resolves exactly")
end
local first = P.Perception.adapters.players()
check(#first == 5 and #ALIFE_TEST_PLAYERS == 1, "only the perception-derived list gains LF actors")
local builds = A.status().listBuilds
P.Perception.adapters.players()
check(A.status().listBuilds == builds, "membership is cached for 250 ms")
ALIFE_TEST_PLAYERS[2] = member
local dedup = P.Perception.adapters.players()
check(#dedup == 5, "owned secondary-slot leaders are deduplicated")
member.x = 25
local cachedMember
for _, actor in ipairs(first) do if actor == member then cachedMember = actor end end
check(cachedMember and cachedMember:getX() == 25, "cached membership retains live actor coordinates")
local supplied = { ALIFE_TEST_PLAYER, member }
local provider = function() return supplied end
local configureResult = P.Perception.configure({ players = provider, sentinel = "retained" })
check(#P.Perception.adapters.players() == 5 and #supplied == 2 and P.Perception.adapters.sentinel == "retained",
    "A-Life reconfiguration chains its supplied provider without changing other adapters")
check(A.initialize(), "legitimate perception reconfiguration remains supported")
check(A.relationship(shell, member) == "hostile" and A.relationship(shell, resident) == "hostile",
    "companions and camp residents inherit player faction hostility")
record.memory.hostileOverride = true
check(A.relationship(shell, household) == "neutral" and A.relationship(shell, folk) == "neutral",
    "independent people start neutral even when the faction hates the player")
P.Reputation.escalate(household, record, "attack")
check(A.relationship(shell, household) == "hostile" and A.relationship(shell, folk) == "neutral",
    "independent aggression creates an isolated native reputation entry")
check(ALIFE_TEST_REPUTATION["sp:0"] == nil and #ALIFE_TEST_SYNCS == 0,
    "independent escalation changes neither player reputation nor player UI")
record.factionId = "neutral"
P.Reputation.escalate(member, record, "attack")
check(ALIFE_TEST_REPUTATION["sp:0"].neutral == "hostile" and ALIFE_TEST_SYNCS[1] == ALIFE_TEST_PLAYER,
    "companion aggression updates player faction reputation through explicit delegation")
record.victim = member
local old = ALIFE_TEST_REPUTATION["sp:0"].friendly
record.factionId = "friendly"
local defended, defenseReason = P.Reputation.escalate(member, record, "attack")
check(not defended and defenseReason == "self_defence" and ALIFE_TEST_REPUTATION["sp:0"].friendly == old,
    "mapping reputation preserves the actual companion's self-defence test")
record.victim, record.factionId = folk, "hostile"
check(A.relationship(shell, folk) == "hostile", "independent victims can defend against the owner's verified aggression")
record.memory.robberyTruce = { [A.idFor(folk)] = SC_TEST_CLOCK + 5000 }
check(A.relationship(shell, folk) == "neutral", "an explicit A-Life truce overrides retained aggression")
record.memory.robberyTruce, record.victim = nil, nil
for _, entry in ipairs({ { P.Reputation, "onPlayerDied" }, { P.Reputation, "forgetPlayer" },
    { P.PersonalRep, "onPlayerDied" }, { P.PersonalRep, "forgetPlayer" },
    { P.CharacterReset, "check" }, { P.CharacterReset, "onPlayerDied" }, { P.CharacterReset, "forget" },
    { P.RepTrack, "onPlayerDied" } }) do
    entry[1][entry[2]](member)
    entry[1][entry[2]](A.idFor(member))
end
check(ALIFE_TEST_LIFECYCLE == 0, "LF death/reset callbacks never enter real-player lifecycle code")
local lifecycle, middle, last = P.Reputation.onPlayerDied(ALIFE_TEST_PLAYER)
check(lifecycle == "original" and middle == nil and last == 9 and ALIFE_TEST_LIFECYCLE == 1,
    "real-player lifecycle values and nil holes are preserved")
P.PersonalRep.announce(folk, "kill", 2)
check(ALIFE_TEST_POPUPS == 0, "NPC personal reputation does not display a player popup")
check(P.Combat.friendlyBody(record, shell, folk) and not P.Combat.hostileToActor(record, folk, shell),
    "neutral LF people are protected in the owner's friendly-body checks")
check(P.LineOfFire.liveBystander(folk, shell, member), "LF player bodies appear in the owner's bullet lanes")
check(not P.LineOfFire.liveBystander(member, shell, member), "the selected target is not its own bystander")
local hit, nilReturn, marker = P.Combat.resolveAttack(record, shell, member, { damage = 7 })
check(hit and nilReturn == nil and marker == 13 and member.body.hits == 1 and member.body.damage == 7,
    "one native wound is applied once with original result values")
check(A.isAttacking(shell, member), "a confirmed native wound is urgent for its exact victim")
local priorHits = resident.body.hits
ALIFE_TEST_BEFORE_WOUND = function(target) target.god = true end
local guarded = P.Combat.resolveAttack(record, shell, resident, { damage = 11 })
check(not guarded and resident.body.hits == priorHits and resident.body.damage == 0,
    "application-time immunity aborts without entering the caller's AddDamage fallback")
ALIFE_TEST_BEFORE_WOUND, resident.god = nil, false
ALIFE_TEST_BEFORE_WOUND = function(target)
    ALIFE_TEST_BEFORE_WOUND = nil
    P.Combat.resolveAttack(record, shell, resident, { damage = 3 })
end
P.Combat.resolveAttack(record, shell, member, { damage = 5 })
check(member.body.damage == 12 and resident.body.damage == 3, "nested attacks preserve exact victims and restore the outer scope")
ALIFE_TEST_BEFORE_WOUND = function() error("original_failure", 0) end
local okay, errorValue = pcall(P.Combat.resolveAttack, record, shell, member, { damage = 50 })
check(not okay and errorValue == "original_failure" and member.body.damage == 12, "unrelated attack errors propagate without a replay")
ALIFE_TEST_BEFORE_WOUND = nil
check(not pcall(P.Wounds.damagePlayer, member.body, { damage = 50 }), "standalone LF wound calls have no attack authority")
check(P.Combat.resolveAttack(record, shell, member, { damage = 1 }) and member.body.damage == 13,
    "a fresh attack still succeeds after a nested call and an exception")
shell.md.ProjectALifeGeneration = 2
check(A.owns(shell) and A.relationship(shell, member) == "unknown", "a recycled shell remains human but loses combat authority")
check(not P.Combat.resolveAttack(record, shell, member, { damage = 9 }), "stale A-Life generations cannot damage LF")
shell.md.ProjectALifeGeneration = 3
member.removed = true
check(A.resolve(A.idFor(member)) == nil and not P.TargetPolicy.canAttack(member), "native removal is respected before registry cleanup")
member.removed = false
local alias = A.idFor(folk)
ALIFE_TEST_REMOVE(folk)
check(A.resolve(alias) == nil and P.Reputation.playerKey(folk) == alias, "retired references cannot collapse to sp:0")
check(#P.Perception.adapters.players() == 4, "roster lifecycle changes invalidate cached membership")
ALIFE_TEST_OPTIONS.alifeCompatibility = false
check(not A.initialize() and A.status().state == "disabled" and #P.Perception.adapters.players() == 1,
    "Off filters owned view slots and removes extra combat targets")
check(A.owns(shell), "Off retains human classification for enabled A-Life shells")
check(not P.Combat.resolveAttack(record, shell, member, { damage = 20 }) and P.Reputation.playerKey(member) ~= "sp:0",
    "Off retains identity and damage isolation")
ALIFE_TEST_OPTIONS.alifeCompatibility = true
check(A.initialize(), "integration can be reenabled without stacking wrappers")
ALIFE_TEST_MODS.Bandits2 = true
check(not A.initialize() and A.status().state == "unsupported", "the unvalidated three-mod combination is diagnosed")
ALIFE_TEST_MODS.Bandits2 = nil
check(A.initialize(), "supported mod composition can recover")
local retainedKey, retainedWound, retainedProvider = P.Reputation.playerKey, P.Wounds.damagePlayer, P.Perception.adapters.players
A.reset()
check(P.Reputation.playerKey == originalKey and P.TargetPolicy.canAttack == originalPolicy, "reset restores only its owned bindings")
check(retainedKey(member) == A.idFor(member), "retained identity guards preserve tombstones")
check(not pcall(retainedWound, member.body, { damage = 50 }), "retained damage wrappers cannot wound into a retired world")
check(pcall(retainedProvider), "retained providers remain safe after teardown")
check(A.initialize(), "a new world can initialize after teardown")
local attackWrapper = P.Combat.resolveAttack
P.Combat.resolveAttack = function(...) return attackWrapper(...) end
A.pulse(SC_TEST_CLOCK + 1000)
check(A.status().state == "unsupported" and string.find(A.status().reason, "hook changed", 1, true),
    "a foreign hook replacement disables integration rather than overwriting it")
SC_TEST_REPORT = "ALIFE_ADAPTER_PASS checks=" .. tostring(checks)
