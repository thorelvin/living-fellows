-- SPDX-License-Identifier: MIT
local Probe = SCRealSandboxHarnessProbes.SCBanditsProtectedLaneAcceptance
local checks = 0
local function expect(value, why)
    checks = checks + 1
    assert(value, "protected lane " .. checks .. ": " .. why)
end
local function point(x, y, z)
    return { getX = function() return x end, getY = function() return y end, getZ = function() return z or 0 end }
end
local actor, target, neutral, loyal = point(0, 0), point(10, 0), point(4, 0), point(6, 0.5)
expect(Probe.inLane(actor, neutral, target), "a neutral between shooter and target occupies the lane")
expect(Probe.inLane(actor, loyal, target), "a nearby loyal bystander also occupies the corridor")
expect(not Probe.inLane(actor, point(-1, 0), target), "actors behind the shooter cannot prove a blocked lane")
expect(not Probe.inLane(actor, point(11, 0), target), "actors behind the target cannot prove this lane")
expect(not Probe.inLane(actor, point(4, 0.81), target), "an actor outside the actual corridor cannot prove protection")
expect(not Probe.inLane(actor, point(4, 0, 1), target), "a different floor cannot prove this firing veto")
expect(not Probe.inLane(actor, neutral, actor), "a zero-length ray is not evidence")
local f = { actor = actor, observing = true, targets = { [target] = true }, bystanders = { [neutral] = "neutral", [loyal] = "loyal" },
    blocked = { neutral = 0, loyal = 0 } }
local context = { snapshot = { protectedActors = { { actor = neutral }, { actor = loyal } } } }
Probe.observeLane(f, actor, target, context, true)
expect(f.blocked.neutral == 1 and f.blocked.loyal == 1,
    "a real production veto counts both protected native bystanders actually on its ray")
Probe.observeLane(f, actor, target, context, false)
expect(f.blocked.neutral == 1 and f.blocked.loyal == 1, "an offered shot cannot count as a protection veto")
Probe.observeLane(f, point(0, 0), target, context, true)
expect(f.blocked.neutral == 1, "another LF actor's veto cannot satisfy this scene")
Probe.observeLane(f, actor, point(10, 0), context, true)
expect(f.blocked.neutral == 1, "an untracked target cannot satisfy this scene")
Probe.observeLane(f, actor, target, { snapshot = { allies = context.snapshot.protectedActors } }, true)
expect(f.blocked.neutral == 1, "party ally membership cannot substitute for external-human protection")
Probe.observeLane(f, actor, target, nil, true)
expect(f.blocked.neutral == 1, "a veto without the production perception snapshot supplies no evidence")
f.observing = false
Probe.observeLane(f, actor, target, context, true)
expect(f.blocked.neutral == 1 and f.blocked.loyal == 1, "retained observers become inert after cleanup")
local occupant, furniture, staticFree = actor, nil, true
local moving = { size = function() return 1 end, get = function() return occupant end }
local square = { getMovingObjects = function() return moving end }
actor.getSquare = function() return square end
local SC = { GameplayUtil = { isClearActorSpawnSquare = function() return false end,
    isSquareFree = function() return staticFree end, squareOccupyingObject = function() return furniture end } }
expect(Probe.clearFor(SC, square, actor), "an actor's own existing scene tile may be centered without treating itself as a collision")
occupant = neutral
expect(not Probe.clearFor(SC, square, actor), "another body still prevents initial placement")
occupant, furniture = actor, {}
expect(not Probe.clearFor(SC, square, actor), "furniture still prevents placement")
furniture, staticFree = nil, false
expect(not Probe.clearFor(SC, square, actor), "a static obstruction still prevents placement")
SurvivorCompanion = { Call = { resolve = function(object, key)
    local method = object and object[key]
    return type(method) == "function", method
end } }
local attempt, receipt, serial, outcome, health, identity, attacker, burning, dead, ammo, chambered
local gun = { getCurrentAmmoCount = function() return ammo end, isRoundChambered = function() return chambered end }
actor.getCompanionAttackAttemptSerial = function() return attempt end
actor.getCompanionAttackReceiptSerial = function() return receipt end
actor.getCompanionAttackCollisionSerial = function() return serial end
actor.getCompanionAttackReceiptOutcome = function() return outcome end
actor.isDoShove = function() return false end
target.getHealth = function() return health end
target.getID = function() return identity end
target.getAttackedBy = function() return attacker end
target.isOnFire = function() return burning end
target.isDead = function() return dead end
local function hitFixture()
    attempt, receipt, serial, outcome = 3, 2, 2, "completed"
    health, identity, attacker, burning, dead, ammo, chambered = 1, 44, nil, false, false, 15, true
    return { actor = actor, gun = gun }
end
local function completeHit(f)
    receipt, serial, health, attacker = 3, 3, 0.8, actor
    Probe.consumeHits(f)
end
f = hitFixture()
Probe.claimHit(f, target, gun)
completeHit(f)
expect(f.damaged and #f.actualHits == 0,
    "a real gun event during this LF's native attempt can prove damage to the actually hit zombie, even when it was not the aim target")
f = hitFixture()
Probe.claimHit(f, target, gun)
receipt, serial, health, attacker = 3, 3, 0.8, neutral
Probe.consumeHits(f)
expect(not f.damaged, "another native attacker's health loss cannot satisfy LF ownership")
f = hitFixture()
receipt = 3
Probe.claimHit(f, target, gun)
completeHit(f)
expect(not f.damaged, "a hit outside an in-flight native LF collision supplies no owned claim")
f = hitFixture()
Probe.claimHit(f, target, {})
completeHit(f)
expect(not f.damaged, "another item cannot prove the configured pistol's native hit")
f = hitFixture()
Probe.claimHit(f, target, gun)
receipt, serial, health, attacker, outcome = 3, 3, 0.8, actor, "failed_maybe_partial"
Probe.consumeHits(f)
expect(not f.damaged, "a partially failed native collision is never promoted to completed damage proof")
f = hitFixture()
Probe.claimHit(f, target, gun)
receipt, serial, health, attacker = 3, 4, 0.8, actor
Probe.consumeHits(f)
expect(not f.damaged, "a later collision serial cannot consume an earlier hit event")
f = hitFixture()
Probe.claimHit(f, target, gun)
identity = 45
completeHit(f)
expect(not f.damaged, "a pooled zombie shell with a new native ID is rejected")
f = hitFixture()
Probe.claimHit(f, target, gun)
receipt, serial, attacker = 3, 3, actor
Probe.consumeHits(f)
expect(not f.damaged, "an event without a native wound cannot pass")
f = hitFixture()
dead = true
Probe.claimHit(f, target, gun)
completeHit(f)
expect(not f.damaged, "an already dead target supplies no new LF damage")
f = hitFixture()
Probe.claimHit(f, target, gun)
burning = true
completeHit(f)
expect(not f.damaged, "a burning target cannot supply ambiguous delayed health-loss proof")
local function shotFixture(blocked, targetValue)
    local value = hitFixture()
    receipt = 3
    value.pendingShots = { { target = targetValue, blocked = blocked, ammo = 15, attempt = 3, chambered = true } }
    return value
end
f = shotFixture(true, target)
Probe.consumeShots(f)
expect(not f.failure and not f.safeShots, "an animation event without a spent round is not an unsafe gunshot")
f = shotFixture(true, target)
ammo = 14
Probe.consumeShots(f)
expect(f.failure ~= nil, "a consumed shot across a protected lane fails the entire scene")
f = shotFixture(false, target)
ammo = 14
Probe.consumeShots(f)
expect(f.safeShots == 1 and not f.failure, "an exposed shot requires actual ammunition and the same completed receipt")
f = shotFixture(false, target)
ammo, receipt = 14, 4
Probe.consumeShots(f)
expect(f.failure ~= nil, "a foreign/later receipt cannot authorize a recorded shot")
f = shotFixture(false, nil)
ammo = 14
Probe.consumeShots(f)
expect(f.failure ~= nil, "an actual shot with unknown native aim cannot establish safe firing")
f = shotFixture(true, target)
chambered = false
Probe.consumeShots(f)
expect(f.failure ~= nil, "the last chambered round counts even without a magazine-count change")
SC_TEST_REPORT = "BANDITS_PROTECTED_LANE_PASS checks=" .. checks
