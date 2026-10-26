-- SPDX-License-Identifier: MIT
local A, P, checks = SurvivorCompanion.ALifeAdapter, ProjectALife, 0
local function check(value, message) checks = checks + 1 assert(value, "A-Life source check " .. checks .. ": " .. message) end
local member = ALIFE_TEST_ACTOR("sc-source-member", true)
local independent = ALIFE_TEST_ACTOR("sc-source-independent")
member.x, member.y, independent.x, independent.y = 6, 5, 7, 5
local shell, record = ALIFE_TEST_NPC("source-1")
record.profileId = "test"
local originalWound = P.Wounds.damagePlayer
local originalAttack = P.Combat.resolveAttack
check(A.initialize(), "current original interfaces activate")
check(P.Reputation.playerKey(member) ~= P.Reputation.playerKey(ALIFE_TEST_PLAYER), "the stock sp:0 collision is isolated")
check(A.relationship(shell, member) == "hostile" and A.relationship(shell, independent) == "neutral", "stock diplomacy respects the selected relation scopes")
local target, _, kind = P.Perception.findThreat(record, shell, "assault")
check(target == member and kind == "player", "the original threat picker discovers the closer LF actor without a native player slot")
check(#P.PlayerLocator.list() == 1 and #P.Perception.adapters.players() == 3, "stock simulation anchors stay separate from combat targets")
P.Reputation.escalate(independent, record, "attack")
check(P.Reputation.recordedStatus(independent, record) == "hostile"
    and P.Reputation.recordedStatus(ALIFE_TEST_PLAYER, record) == nil, "stock persistence stores independent retaliation under its own key")
record.factionId = "neutral"
P.Reputation.escalate(member, record, "attack")
check(P.Reputation.recordedStatus(ALIFE_TEST_PLAYER, record) == "hostile", "stock player faction reputation receives companion aggression")
check(ALIFE_SOURCE_STORES[P.Reputation.TAG].players[A.idFor(member)] == nil,
    "party faction reputation is delegated without replacing the identity key")
record.memory.hostileToPlayerKeys = { [A.idFor(member)] = true }
local stamp = P.TargetPolicy.identity(member)
check(stamp.uid == A.idFor(member) and P.TargetPolicy.sameIdentity(member, stamp), "stock target identity stamps are LF-specific")
local replacement = ALIFE_TEST_ACTOR(member.md.SC_Id, true)
check(not P.TargetPolicy.canAttack(member, stamp), "a retired object cannot remain a target after replacement")
check(not P.TargetPolicy.sameIdentity(replacement, stamp), "a reloaded incarnation cannot inherit the former object's attack stamp")
ALIFE_TEST_RECORDS[member.md.SC_Id].actor = member
record.factionId = "hostile"

-- Compare unchanged stock wound results with and without the adapter, seeded
-- identically, over real source paths and synthetic native body boundaries.
for _, ranged in ipairs({ true, false }) do
    for _, armor in ipairs({ 0, 60, 100 }) do
        for seed = 1, 8 do
            local control = ALIFE_TEST_ACTOR()
            ALIFE_SOURCE_BODY(control, armor)
            ALIFE_SOURCE_BODY(member, armor)
            local weapon = ALIFE_SOURCE_WEAPON(ranged)
            ALIFE_SOURCE_SEED = seed
            local expected = originalWound(control.body, weapon, 6)
            shell.weapon, shell.md.ProjectALifeNextStrikeAtMs = weapon, nil
            ALIFE_SOURCE_SEED = seed
            local actual = P.Combat.resolveAttack(record, shell, member, false)
            -- Firearm accuracy consumes one stock random roll before wounds.
            -- Compare the wound wrapper separately using that same seed.
            if ranged then
                ALIFE_SOURCE_BODY(control, armor)
                ALIFE_SOURCE_SEED = seed
                ZombRand(10000)
                originalWound(control.body, weapon, 6)
            end
            check(expected and actual and member.body.hits == 1 and member.body.fallbacks == nil,
                "stock attack dispatch applies one native wound without the emergency fallback")
            for index = 0, 16 do
                local a, b = control.body.parts[index], member.body.parts[index]
                check(a.health == b.health and a.cut == b.cut and a.deep == b.deep
                    and a.bullet == b.bullet and a.scratched == b.scratched and a.bleeding == b.bleeding,
                    "seeded stock wound output is unchanged")
            end
            check(control.body.clothingHoles == member.body.clothingHoles, "armour/clothing callback results remain exact")
        end
    end
end
local bystander = ALIFE_TEST_ACTOR("sc-source-bystander")
bystander.x, bystander.y = 6, 5
ALIFE_SOURCE_MOVING["6:5"] = { bystander }
member.x = 8
check(P.LineOfFire.firstBodyOnLine(shell, member) == bystander, "the original line walker recognizes LF bystanders")
check(P.Combat.friendlyBody(record, shell, bystander), "neutral bystanders are protected by stock combat queries")
local before = member.body.hits
ALIFE_SOURCE_WALL = true
shell.md.ProjectALifeNextStrikeAtMs = nil
check(not P.Combat.resolveAttack(record, shell, member, false) and member.body.hits == before, "wall refusal cannot become a synthetic hit")
ALIFE_SOURCE_WALL = nil
member.god = true
check(not P.Combat.resolveAttack(record, shell, member, false) and member.body.hits == before, "stock attacks respect explicit LF immunity")
member.god = false
local originalBody = member.getBodyDamage
member.getBodyDamage = function(actor) actor.god = true return originalBody(actor) end
shell.md.ProjectALifeNextStrikeAtMs = nil
local accepted = P.Combat.resolveAttack(record, shell, member, false)
check(not accepted and member.body.hits == before and not member.body.fallbacks,
    "late immunity blocks the actual stock AddDamage fallback")
member.getBodyDamage, member.god = originalBody, false
SC_TEST_REPORT = "ALIFE_INSTALLED_SOURCE_PASS checks=" .. tostring(checks)
