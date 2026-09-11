-- SPDX-License-Identifier: MIT
-- Load after core_fixture, native action modules, GameplayUtil and Combat.
local SC, checks = SurvivorCompanion, 0
local C, N, U = SC.Combat, SC.NativeActions, SC.GameplayUtil
local function check(value, message)
    checks = checks + 1
    assert(value, "ground finisher check " .. checks .. ": " .. message)
end
local function weapon(name, range, cost)
    local value = { __class = "HandWeapon", name = name, range = range or 1.1,
        condition = 10, cost = cost or 1, melee = true }
    function value:getFullType() return self.name end
    function value:getCategory() return "Weapon" end
    function value:getCondition() return self.condition end
    function value:getConditionMax() return 10 end
    function value:getMaxRange() return self.range end
    function value:getMinRange() return 0.6 end
    function value:getMaxDamage() return 1.5 end
    function value:getActualWeight() return self.cost end
    function value:getSwingTime() return 1 end
    function value:isRanged() return self.ranged == true end
    function value:isMelee() return self.melee end
    return value
end
local hammer = weapon("Base.Hammer")
local actor = { x = 0, y = 0, z = 0, primary = hammer, data = {}, moves = 0 }
function actor:getX() return self.x end
function actor:getY() return self.y end
function actor:getZ() return self.z end
function actor:getSquare() return self end
function actor:getPrimaryHandItem() return self.primary end
function actor:getModData() return self.data end
function actor:getHealth() return 100 end
function actor:isDead() return false end
function actor:CanSee() return not self.hidden end
function actor:getMeleeDelay() return self.meleeDelay or 0 end
function actor:getRecoilDelay() return self.recoilDelay or 0 end
function actor:isAttackStarted() return self.attacking == true end
function actor:setMoving(value) if not self.rejectStop then self.moving = value end end
function actor:isMoving() return self.moving == true end
function actor:setRunning() end
function actor:setSprinting() end
function actor:setCompanionFloorAttackInput() return true end
function actor:getCompanionAttackCollisionSerial() return 0 end
function actor:getCompanionAttackCollisionHitCount() return 0 end
function actor:getCompanionAttackCollisionTarget() return nil end
function actor:didCompanionAttackCollisionHitTarget() return false end
function actor:hasFootInjury() return self.footInjury == true end
function actor:getWornItem() return self.shoes end
function actor:getWornItems()
    return { size = function() return 0 end }
end
local function zombie(x)
    local value = { __class = "IsoZombie", x = x or 1, y = 0, z = 0, grounded = true }
    function value:getX() return self.x end
    function value:getY() return self.y end
    function value:getZ() return self.z end
    function value:getSquare() return self end
    function value:isDead() return self.dead == true end
    function value:isOnFloor() return self.grounded end
    function value:isProne() return self.grounded end
    return value
end
local a, b = zombie(0.5), zombie(0.5)
local function record(item)
    local minimum, maximum, value = C.meleeRange(actor, item)
    if item.ranged then
        value = { item = item, ranged = true, condition = item.condition, conditionRatio = 1 }
    end
    value.equipped = true
    return value
end
local readiness = { endurance = 0.8, panic = 0, pain = 0, immediate = 1, close = 1,
    occupiedSectors = 1, strength = 5, combatSkill = 5, weaponQuality = 1,
    footing = { crowd = 0 }, confidence = 60 }
local boots = { type = "Base.Shoes_ArmyBoots", factor = 1.15 }
local sandals = { type = "Base.Shoes_Sandals", factor = 0.78 }
local function choose(item, roll, feet, status, commands, target)
    return C.groundedFinisher(actor, target or a, item and record(item), status or readiness,
        commands or {}, { rng = function() return roll or 0.5 end, footwear = feet or boots })
end
for _, name in ipairs({ "Base.Hammer", "Base.HuntingKnife", "Base.BaseballBat",
        "Base.Sledgehammer", "Base.SpearCrafted", "Base.MeatCleaver" }) do
    local picked = choose(weapon(name), 0.5)
    check(picked.kind == "melee" and picked.floorAttack,
        name .. " uses an equipped native floor weapon swing by default")
end
check(choose(hammer, 0.99).kind == "stomp", "protected feet permit a rare alternative, not identical robot swings")
check(choose(hammer, 0.01).kind == "melee", "injected low roll reproducibly chooses weapon")
check(choose(hammer, 0.5, sandals).weaponProbability > choose(hammer, 0.5, boots).weaponProbability,
    "sandals favor the equipped weapon more than protective boots")
local barefoot = N.stompFootwearProfile(actor)
check(barefoot.type == "barefoot" and barefoot.stompPower == 0.5
        and barefoot.factor < 0.25,
    "selector mirrors vanilla's barefoot stomp-power penalty")
actor.shoes = weapon("Base.Shoes_Sandals")
local worn = N.stompFootwearProfile(actor)
check(worn.stompPower == 0.8 and worn.factor < 0.4 and worn.condition == 1,
    "fallback sandals retain their vanilla-scale stomp power and condition")
actor.shoes.condition = 0
check(N.stompFootwearProfile(actor).factor < worn.factor, "destroyed shoes do not give pristine foot protection")
actor.shoes = nil
local cautious = choose(hammer, 0.5, boots, readiness,
    { personalityProfile = { caution = 95, courage = 15 } })
local brave = choose(hammer, 0.5, boots, readiness,
    { personalityProfile = { caution = 15, courage = 95 } })
check(cautious.weaponProbability > brave.weaponProbability
        and cautious.weaponProbability - brave.weaponProbability < 0.15,
    "personality produces a bounded preference without overriding equipment")
local panicked = { endurance = 0.8, panic = 4 }
check(choose(hammer, 0.5, boots, panicked).weaponProbability > choose(hammer, 0.5).weaponProbability,
    "panic favors the weapon already held over balancing for a stomp")
local heavy = weapon("Base.Sledgehammer", 1.5, 4)
check(choose(heavy, 0.5, boots, { endurance = 0.2 }).weaponProbability
        < choose(heavy, 0.5, boots, readiness).weaponProbability,
    "heavy weapon fatigue increases the protected-foot alternative")
check(choose(hammer, 0.5, boots, { endurance = 0.05 }).kind == "hold_range",
    "extreme exhaustion does not keep forcing finishing attacks")
local hurtFeet = { type = "barefoot", factor = 0.65, footInjured = true }
check(choose(hammer, 0.99, hurtFeet).kind == "melee", "injured foot cannot win a random stomp")
check(choose(nil, 0.5, hurtFeet).kind == "hold_range", "unarmed injured foot waits instead of repeatedly stomping")
hammer.condition = 1
check(choose(hammer, 0.01).kind == "stomp", "near-breaking weapon is preserved when feet permit")
hammer.condition = 0
check(choose(hammer, 0.01).kind == "stomp", "broken weapon cannot be selected for a floor swing")
hammer.condition = 10
local pistol = weapon("Base.Pistol")
pistol.ranged = true
check(choose(pistol, 0.01).kind == "stomp", "ranged weapon is not misclassified as a floor melee strike")
local thrown = weapon("Base.PipeBomb")
thrown.melee = false
check(choose(thrown, 0.01).kind == "stomp", "explicitly non-melee HandWeapon is not given a floor swing")
local spare = record(hammer)
spare.equipped = false
check(C.groundedFinisher(actor, a, spare, readiness, {},
        { rng = function() return 0 end, footwear = boots }).kind == "stomp",
    "an inventory weapon cannot pretend it is already visibly held")
local savedLease = actor.setCompanionFloorAttackInput
actor.setCompanionFloorAttackInput = nil
check(choose(hammer, 0).reason == "floor_input_unavailable", "missing native input support fails closed")
actor.setCompanionFloorAttackInput = savedLease
local far = zombie(1.8)
check(choose(weapon("Base.SpearCrafted", 2), 0.99, boots, readiness, {}, far).kind == "melee",
    "a reachable spear floor strike avoids walking closer only to stomp")
far.x = 1.4
local shortOutOfReach = choose(hammer, 0, boots, readiness, {}, far)
check(shortOutOfReach.kind == "approach" and shortOutOfReach.attackKind == "melee",
    "short weapon closes to its real floor-swing reach instead of stomping from range")
far.x = 2.2
local approach = choose(hammer, 0, boots, readiness, {}, far)
check(approach.kind == "approach" and approach.attackKind == "melee"
        and approach.minimumDistance > 0 and approach.maximum < far.x,
    "shove displacement requests bounded movement before weapon impact")
far.x = 6
check(choose(hammer, 0, boots, readiness, {}, far).kind == "hold_range",
    "short finisher follow-up cannot pursue arbitrarily far")

-- Real production cooldown gates, with only physical movement/attack submission
-- captured. The actual native floor stance/collision contract has its own suite.
local savedMove, savedRand = U.move, ZombRandFloat
local randomCalls = 0
ZombRandFloat = function() randomCalls = randomCalls + 1 return 0.5 end
U.move = function(_, _, intent) actor.moves = actor.moves + 1 actor.lastIntent = intent return true end
local state = C.peek(actor)
state.finisherRolls = nil
for index = 1, 100 do
    C.groundedFinisher(actor, a, record(hammer), readiness, {})
end
check(randomCalls == 1, "repeated scoring of one grounded target keeps one stable choice")
C.groundedFinisher(actor, b, record(hammer), readiness, {})
check(randomCalls == 2, "a different grounded zombie receives its own preference draw")
C.groundedFinisher(actor, a, record(hammer), readiness, {})
check(randomCalls == 2,
    "interleaved A-B-A scoring retains A's roll instead of fishing for a new choice")
local snapshot = { threats = { { actor = a, distanceSq = 1 } }, allies = {}, escapeSquares = {},
    closeImmediateCount = 1, closeThreatCount = 1, occupiedThreatSectors = 1 }
local function follow(target)
    snapshot.threats = { { actor = target or a, distanceSq = U.distanceSq(actor, target or a) } }
    state.shoveFollowUp = { target = target or a, startedAt = SC_TEST_CLOCK - 400, expires = SC_TEST_CLOCK + 1000 }
    return C._tryShoveFollowUpForTests(actor, state, snapshot, SC_TEST_CLOCK, {})
end
actor.meleeDelay, actor.moving = 3, true
local accepted, reason = follow()
check(accepted and reason == "waiting_for_shove_result" and actor.moves == 0 and not actor.moving,
    "post-shove finisher stops actual movement while native melee cooldown remains")
check(actor.meleeDelay == 3 and randomCalls == 2,
    "decision neither decrements nor bypasses native cooldown or rerolls")
actor.meleeDelay, actor.recoilDelay = 0, 2
accepted, reason = follow()
check(accepted and reason == "waiting_for_shove_result" and actor.moves == 0,
    "weapon follow-up also respects recoil recovery that a stomp would not require")
actor.recoilDelay = 0
accepted, reason = follow()
check(accepted and reason == "melee_after_shove" and actor.lastIntent.action == "attack_melee"
        and actor.lastIntent.weapon == hammer and actor.lastIntent.floorAttack == true
        and actor.lastIntent.groundedAttack == true and actor.lastIntent.shoveFollowUp == true,
    "hammer uses genuine manual floor weapon input after a successful shove")
check(state.shoveFollowUp == nil and state.finisherRolls[a] == nil
        and state.finisherRolls[b] ~= nil,
    "accepted floor attack clears only that target's choice and retains other targets")
C.groundedFinisher(actor, a, record(hammer), readiness, {})
check(randomCalls == 3, "only the completed target gets another variation draw")
local acceptedMove = U.move
U.move = function() return false, "native_melee_recovery" end
actor.moving = true
accepted, reason = follow()
check(accepted and reason == "waiting_for_shove_result" and not actor.moving
        and state.shoveFollowUp ~= nil and state.finisherRolls[a] ~= nil,
    "recovery appearing between scoring and dispatch retains the pending choice and stops movement")
U.move = acceptedMove
state.finisherRolls[a] = 0.999
actor.shoes = weapon("Base.Shoes_ArmyBoots")
state.finisherFootwear = nil
accepted, reason = follow()
check(accepted and reason == "stomp_after_shove" and actor.lastIntent.action == "stomp"
        and actor.lastIntent.weapon == nil, "occasional boot finisher is a real stomp, not a fake weapon damage call")
actor.shoes = nil
local distantGrounded = zombie(2.2)
state.finisherRolls[distantGrounded] = 0.5
accepted, reason = follow(distantGrounded)
check(accepted and reason == "approach_melee_after_shove"
        and actor.lastIntent.action == "combat_approach" and actor.lastIntent.combatMinimumDistance > 0,
    "weapon post-shove approach preserves a finite stopping distance")
local before = actor.moves
actor.meleeDelay, actor.moving, actor.rejectStop = 3, true, true
accepted, reason = follow()
check(not accepted and reason == "native_combat_stop_failed" and actor.moves == before,
    "rejected stationary hold cannot start or falsely acknowledge a finisher")
actor.meleeDelay, actor.rejectStop = 0, false
actor.hidden = true
accepted, reason = follow()
check(not accepted and state.shoveFollowUp == nil and actor.moves == before,
    "post-shove visibility loss cancels the action before selection")
actor.hidden = false
a.grounded = false
accepted, reason = follow()
check(not accepted and reason == "shove_did_not_ground_target", "standing target cannot receive stale grounded input")
a.grounded = true
U.move, ZombRandFloat = savedMove, savedRand

-- A -> B evidence passes through the same observer used by real Decision ticks.
local savedPoll, evidence = N.pollCombatEvents, nil
N.pollCombatEvents = function() return true, "regression_evidence", evidence end
evidence = { result = "no_effect", target = a }
C.observe(actor)
C.observe(actor)
check(C.peek(actor).noEffectCollisions == 2 and C.peek(actor).noEffectTarget == a,
    "two ineffective collisions on A form a target-specific streak")
evidence = { result = "landed", target = b }
C.observe(actor)
check(C.peek(actor).noEffectCollisions == 0 and C.peek(actor).noEffectTarget == b,
    "successful first collision on B resets A's failure count")
evidence = { result = "no_effect", target = b }
C.observe(actor)
check(C.peek(actor).noEffectCollisions == 1, "B's next ineffective collision starts at one, not three")
evidence = { result = "no_effect", target = a }
C.observe(actor)
check(C.peek(actor).noEffectCollisions == 1 and C.peek(actor).noEffectTarget == a,
    "changing target on another miss also starts a fresh streak")
evidence = { result = "no_effect", action = "attack_melee", floorAttack = true,
    target = a, weapon = hammer }
C.observe(actor)
C.observe(actor)
local failedClipChoice = choose(hammer, 0, boots, readiness, {}, a)
check(failedClipChoice.attackKind == "stomp",
    "two target-specific native floor-weapon failures fall back to a safe stomp")
evidence = { result = "landed", action = "attack_melee", floorAttack = true,
    target = a, weapon = hammer }
C.observe(actor)
check(C.peek(actor).floorWeaponFailures[a] == nil,
    "a confirmed native floor-weapon hit clears its compatibility failure record")
N.pollCombatEvents = savedPoll
C.reset(actor)
SC_TEST_REPORT = "GROUND_FINISHER_PASS checks=" .. checks
