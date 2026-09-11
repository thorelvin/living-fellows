-- SPDX-License-Identifier: MIT
-- Production native dispatch with a retained-input actor and native Hit semantics.
local SC = SurvivorCompanion
local checks = 0
local function check(value, message)
    checks = checks + 1
    assert(value, "combat recovery check " .. checks .. ": " .. message)
end
local weapon = { __class = "HandWeapon" }
function weapon:getCategory() return "Weapon" end
function weapon:getFullType() return "Base.MeatCleaver" end
function weapon:getType() return "MeatCleaver" end
function weapon:getMaxDamage() return 1.6 end
function weapon:getMaxRange() return 1 end
function weapon:getMinRange() return 0.61 end
function weapon:getCondition() return 10 end
function weapon:getConditionMax() return 10 end
function weapon:isRanged() return false end
local actor = { x = 0, y = 0, z = 0, primary = weapon, vars = {}, attacks = 0 }
function actor:getX() return self.x end
function actor:getY() return self.y end
function actor:getZ() return self.z end
function actor:getVehicle() return nil end
function actor:getPrimaryHandItem() return self.primary end
function actor:setPrimaryHandItem(value) self.primary = value end
function actor:getSecondaryHandItem() return nil end
function actor:setSecondaryHandItem() end
function actor:getUseHandWeapon() return weapon end
function actor:getCharacterActions() return {} end
function actor:getCurrentState() return nil end
function actor:getCompanionActionStateName() return self.actionState or "idle" end
function actor:getVariableBoolean(name) return self.vars[name] == true end
function actor:getVariableString(name) return tostring(self.vars[name] or "") end
function actor:setVariable(name, value) self.vars[name] = value end
function actor:faceLocationF() return true end
function actor:setForwardDirection() end
function actor:setRunning(value) self.running = value end
function actor:setSprinting(value) self.sprinting = value end
function actor:setSneaking(value) self.sneaking = value end
function actor:isSneaking() return self.sneaking == true end
function actor:setMoving(value)
    if value == false and self.rejectStop then return end
    self.moving = value
    if not value then self.moveRequested = false end
end
function actor:isMoving() return self.moving == true end
function actor:MoveForward(distance, dx, dy)
    self.distance, self.dx, self.dy, self.moveRequested = distance, dx, dy, true
    self.moving = true
end
function actor:setCompanionMovementTarget(x, y, z, tolerance, ttlMs)
    self.movementTarget = { x = x, y = y, z = z, tolerance = tolerance, ttlMs = ttlMs }
    return self.rejectBounds ~= true
end
function actor:updateFrame()
    if self.moveRequested and self.moving and not self.attackStarted then
        self.x, self.y = self.x + self.distance * self.dx, self.y + self.distance * self.dy
    end
end
function actor:isCompanionMovementClear() return self.obstructed ~= true end
function actor:CanSee() return self.hidden ~= true end
function actor:setIsAiming(value) self.aiming = value end
function actor:isAiming() return self.aiming == true end
function actor:setCompanionTacticalMovement(value) self.aiming = value return true end
function actor:setAimAtFloor(value) self.floorAim = value end
function actor:isAimAtFloor() return self.floorAim == true end
function actor:setCompanionFloorAttackInput(enabled, stomp)
    self.floorInput, self.stompInput = enabled == true, stomp == true
    return self.rejectFloorInput ~= true
end
function actor:setCompanionAimTarget(value) self.aimTarget = value end
function actor:setCompanionFloorTarget(value) self.floorTarget = value end
function actor:isDoShove() return self.shove == true end
function actor:setDoShove(value) self.shove = value end
function actor:isDoGrapple() return false end
function actor:setDoGrapple() end
function actor:isAttackStarted() return self.attackStarted == true end
function actor:setAttackStarted(value) self.attackStarted = value == true end
function actor:setInitiateAttack(value) self.initiateAttack = value == true end
function actor:isPerformingAttackAnimation() return self.attackAnimation == true end
function actor:setPerformingAttackAnimation(value) self.attackAnimation = value == true end
function actor:isPerformingShoveAnimation() return self.shoveAnimation == true end
function actor:setPerformingShoveAnimation(value) self.shoveAnimation = value == true end
function actor:isPerformingStompAnimation() return self.stompAnimation == true end
function actor:setPerformingStompAnimation(value) self.stompAnimation = value == true end
function actor:setShoveStompAnim(value) self.shoveStompAnimation = value == true end
function actor:clearHandToHandAttack() self.attackStarted = false end
function actor:releaseCompanionStaleAttack()
    self.attackStarted, self.initiateAttack, self.attackAnimation = false, false, false
    self.shoveAnimation, self.stompAnimation, self.shoveStompAnimation = false, false, false
    return true
end
function actor:getMeleeDelay() return self.meleeDelay or 0 end
function actor:getRecoilDelay() return self.recoilDelay or 0 end
function actor:CanAttack() return not self.attackStarted and self.warming ~= true end
function actor:isAuthorizedHandToHandAction() return true end
function actor:setAuthorizedHandToHandAction() end
function actor:isAuthorizedHandToHand() return true end
function actor:setAuthorizedHandToHand() end
function actor:setAttackType() end
function actor:DoAttack()
    -- Model the native preflight overwriting output flags. At this prone body
    -- orientation/range, automatic shove targeting would remain standing.
    self.floorAim = self.floorInput == true
    if self.floorAim then self.shove = self.stompInput == true end
    self.attacks = self.attacks + 1
    self.attackStarted = true
    return false
end
function actor:getCompanionAttackCollisionSerial() return self.serial or 0 end
function actor:getCompanionAttackCollisionHitCount() return self.hitCount or 0 end
function actor:getCompanionAttackCollisionTarget() return self.collisionTarget end
function actor:didCompanionAttackCollisionHitTarget() return self.targetHit == true end
local target = { x = 2, y = 0, z = 0, health = 5, hits = 0 }
function target:getX() return self.x end
function target:getY() return self.y end
function target:getZ() return self.z end
function target:getHealth() return self.health end
function target:isDead() return self.health <= 0 end
function target:isOnFloor() return true end
function target:isProne() return true end
function target:Hit(attackWeapon, wielder, damage, ignoreDamage)
    self.hits = self.hits + 1
    ignoreDamage = ignoreDamage or (wielder:isDoShove() and not wielder:isAimAtFloor())
    self.ignored = ignoreDamage
    if not ignoreDamage then self.health = self.health - damage end
end
local provider = { directNative = true }
local savedAttackType = AttackType
AttackType = { SHOVE = {}, STOMP = {}, SHOT = {}, MELEE_SWING = {} }
local function dispatch(action, extra)
    local intent = extra or {}
    intent.action, intent.target = action, target
    return SC.NativeActions.dispatch(actor, "walk", intent, provider)
end
local function approach()
    target.x = actor.x + 2
    local ok, reason = dispatch("combat_approach", {
        dx = 1, dy = 0, keepFacing = true, weaponReady = true,
    })
    check(ok, "approach starts: " .. tostring(reason))
    actor:updateFrame()
    target.x = actor.x + 0.9
end
approach()
local before = actor.x
local held = dispatch("ready_weapon", { combatSpacingHold = true })
for _ = 1, 30 do actor:updateFrame() end
check(held and actor.x == before and not actor.moveRequested,
    "a successful stationary hold clears retained approach across delayed decisions")
actor.moving, actor.rejectStop = true, true
local stopFailureCount = actor.attacks
local failedHold, failedHoldReason = dispatch("ready_weapon")
local failedAttack, failedAttackReason = dispatch("attack_melee")
check(not failedHold and failedHoldReason == "native_combat_stop_failed"
    and not failedAttack and failedAttackReason == "native_combat_stop_failed"
    and actor.attacks == stopFailureCount,
    "a rejected native stop cannot be reported as a successful hold or start an attack")
actor.rejectStop = false
actor:setMoving(false)
target.x = actor.x + 1.4
local bounded = dispatch("combat_approach", {
    dx = 1, dy = 1, keepFacing = true, weaponReady = true, combatMinimumDistance = 0.9,
})
local endpoint = actor.movementTarget
check(bounded and endpoint and endpoint.x > actor.x and endpoint.y > actor.y
    and math.abs((endpoint.x - actor.x) - (endpoint.y - actor.y)) < 0.00001
    and math.sqrt((target.x - endpoint.x) ^ 2 + (target.y - endpoint.y) ^ 2) >= 0.9
    and math.sqrt((endpoint.x - actor.x) ^ 2 + (endpoint.y - actor.y) ^ 2) <= 0.5
    and endpoint.ttlMs <= 250 and endpoint.tolerance <= 0.02,
    "approach endpoint preserves checked diagonal steering and cannot consume the safe range gap")
target.x = actor.x + 0.8
local bandHeld, bandReason = dispatch("combat_approach", {
    dx = 1, dy = 0, keepFacing = true, weaponReady = true, combatMinimumDistance = 0.9,
})
check(bandHeld and bandReason == "combat_spacing_reached" and not actor.moveRequested,
    "approach already inside desired band returns a stationary success")
actor.moving, actor.rejectStop = true, true
local bandRejected, bandRejectedReason = dispatch("combat_approach", {
    dx = 1, dy = 0, weaponReady = true, combatMinimumDistance = 0.9,
})
check(not bandRejected and bandRejectedReason == "combat_position_hold_failed",
    "reaching the spacing band cannot hide a failed stop")
actor.rejectStop = false
actor:setMoving(false)

actor.pathStatus = "pending"
function actor:getCompanionPathStatus() return self.pathStatus end
function actor:getPathFindBehavior2()
    return { isMovingUsingPathFind = function() return true end,
        hasStartedMoving = function() return false end, cancel = function() end }
end
for _, status in ipairs({ "pending", "ready", "moving", "stopping", "none" }) do
    actor.pathStatus = status
    local telemetry = SC.NativeActions.pathTelemetry(actor)
    check(telemetry.status == status and telemetry.pending == (status == "pending")
        and telemetry.active == (status ~= "none") and telemetry.moving == (status == "moving"),
        "native path telemetry separates owner from motion: " .. status)
end

target.x, target.z = actor.x + 2, actor.z + 1
local wrongFloor, wrongFloorReason = dispatch("combat_approach", {
    dx = 1, dy = 0, combatMinimumDistance = 0.9,
})
check(not wrongFloor and wrongFloorReason == "combat_movement_target_invalid" and not actor.moveRequested,
    "a bounded approach with invalid floor fails closed")
target.z, actor.rejectBounds = actor.z, true
local boundsAccepted = dispatch("combat_approach", {
    dx = 1, dy = 0, combatMinimumDistance = 0.9,
})
check(not boundsAccepted and not actor.moveRequested,
    "native endpoint rejection clears translation before returning")
actor.rejectBounds = false
approach()
before = actor.x
actor.warming = true
local started, reason = dispatch("attack_melee", { weapon = weapon })
actor:updateFrame()
check(not started and reason == "native weapon is not attack-ready" and actor.x == before,
    "model warm-up failure stops approach before returning")
actor.warming = false
approach()
before = actor.x
check(dispatch("attack_melee", { weapon = weapon }), "ready melee starts")
actor:updateFrame()
actor.attackStarted = false
actor:updateFrame()
check(actor.x == before and not actor.moveRequested, "swing exit cannot revive pre-swing input")

for _, action in ipairs({ "attack_melee", "attack_firearm", "shove", "stomp" }) do
    actor.attackStarted, actor.meleeDelay, actor.recoilDelay = false, 8, 10
    target.x = actor.x + (action == "stomp" and 0.5 or 0.9)
    local count = actor.attacks
    local ok, why = dispatch(action)
    check(not ok and why == "native_melee_recovery" and actor.attacks == count and actor.meleeDelay == 8,
        action .. " waits for native post-animation melee recovery")
    actor.meleeDelay, actor.recoilDelay = 0, 0
    check(dispatch(action), action .. " resumes after native recovery reaches zero")
end
actor.attackStarted, actor.meleeDelay, actor.recoilDelay = false, 0, 10
check(not SC.NativeActions.combatReadiness(actor, "attack_melee"), "melee honors residual recoil")
check(not SC.NativeActions.combatReadiness(actor, "attack_firearm"), "firearm honors residual recoil")
check(SC.NativeActions.combatReadiness(actor, "shove"), "defensive shove follows player rule and ignores firearm recoil")
check(SC.NativeActions.combatReadiness(actor, "stomp"), "stomp follows player hand-to-hand recovery rule")
actor.recoilDelay = 0
actor.shoveAnimation = true
check(not SC.NativeActions.combatReadiness(actor, "attack_melee"), "shove animation retains attack ownership")
actor.shoveAnimation, actor.stompAnimation = false, true
check(not SC.NativeActions.combatReadiness(actor, "attack_melee"), "stomp animation retains attack ownership")
actor.stompAnimation = false
actor.actionState = "melee"
check(not SC.NativeActions.combatReadiness(actor, "attack_melee"),
    "melee action state retains ownership even while individual animation flags transition")
actor.actionState = nil

actor.attackStarted, actor.initiateAttack, actor.attackAnimation = true, true, true
actor.shoveAnimation, actor.stompAnimation, actor.shoveStompAnimation = true, true, true
local staleReleased, staleReason = SC.NativeActions.releaseStaleAttack(actor)
check(staleReleased and staleReason == "stale_native_attack_released"
        and not actor.attackStarted and not actor.initiateAttack
        and not actor.attackAnimation and not actor.shoveAnimation
        and not actor.stompAnimation and not actor.shoveStompAnimation,
    "dead-target cleanup releases and verifies every independent native attack owner")

local function impact(nativeTarget, hit, healthAfter)
    actor.attackStarted, actor.hidden, actor.obstructed = false, false, false
    target.x, target.z = actor.x + 0.5, actor.z
    local before = target.health
    check(dispatch("stomp"), "stomp request starts before impact")
    check(actor.floorAim and actor.shove and actor.floorInput and actor.stompInput,
        "explicit stomp survives native floor preflight and retains actor-local input")
    if healthAfter ~= nil then target.health = healthAfter end
    actor.collisionTarget = nativeTarget
    actor.targetHit = hit == true
    actor.hitCount = hit and 1 or 0
    actor.serial = (actor.serial or 0) + 1
    local ok, why, evidence = SC.NativeActions.pollCombatEvents(actor)
    local second = SC.NativeActions.pollCombatEvents(actor)
    return ok, why, evidence, target.health - before, second
end
target.health, target.hits = 5, 0
local ok, why, evidence, delta, second = impact(target, true, 4.4)
check(ok and why == "stomp_collision_landed" and evidence.result == "landed"
    and evidence.hitCount == 1 and delta < 0 and target.hits == 0 and second == false,
    "one target-specific native stomp is consumed once without a Lua Hit")
target.health = 5
ok, why, evidence, delta = impact(target, false)
check(ok and why == "stomp_collision_no_effect" and evidence.result == "no_effect"
    and delta == 0 and target.hits == 0,
    "a native miss remains harmless instead of being converted to a fallback hit")
target.health = 5
local other = { getX = function() return actor.x + 0.5 end,
    getY = function() return actor.y end, getZ = function() return actor.z end }
ok, why, evidence, delta = impact(other, true)
check(ok and why == "stomp_collision_no_effect"
    and evidence.collisionTargetMatched == false and delta == 0 and target.hits == 0,
    "collision evidence for another target cannot authorize damage or success")
actor.hidden, actor.obstructed, actor.attackStarted = false, false, false
target.x, target.z = actor.x + 0.5, actor.z
actor.rejectFloorInput = true
local floorRejected = dispatch("stomp")
check(not floorRejected and not actor.floorInput and not actor.floorAim,
    "failed floor input selection releases input and cannot start a phantom stomp")
actor.rejectFloorInput, actor.warming = false, true
check(not dispatch("stomp") and not actor.floorInput,
    "native CanAttack rejection releases the temporary floor input")
actor.warming = false
check(dispatch("attack_melee", { floorAttack = true }) and actor.floorAim and not actor.shove,
    "a floor weapon swing uses explicit floor aim without becoming a stomp")
actor.attackStarted = false
check(dispatch("shove") and not actor.floorInput and not actor.floorAim,
    "standing shove clears the previous floor input lease")
actor.hidden, actor.obstructed, actor.attackStarted = false, false, false
target.z = 0
local readiness = {
    health = 100, close = 1, occupiedSectors = 1, endurance = 1, woundPressure = 0,
    panic = 0, stress = 0, pain = 0, heavyLoad = 0, escapeDanger = 0, support = 0,
    immediate = 1, strength = 5, nimble = 2, fitness = 5, combatSkill = 3,
    weaponQuality = 1, weaponCost = 1, confidence = 70, escapeClearance = 3,
    footing = { crowd = 0, tree = false }, staminaCritical = false,
}
local _, _, record = SC.Combat.meleeRange(actor, weapon)
local function choices(distance, closing, attacking)
    return SC.Combat._actionUtilitiesForTests(actor, nil,
        { pressure = 1, escapeSquares = {}, encircled = false },
        { actor = target, distanceSq = distance * distance, bearing = "front", visible = true,
            attacking = attacking, closingSpeed = closing, score = 90 },
        record, nil, {}, readiness)
end
function target:isOnFloor() return false end
function target:isProne() return false end
local spacing = SC.Combat.meleeSpacing(actor, weapon, { closingSpeed = 1.5 })
check(spacing.desired > spacing.nativeMinimum and spacing.desired < 1
    and spacing.defend > spacing.minimum, "desired stance and early defense are distinct from permissive hit reach")
check(choices(0.5, 1.5, true)[1].kind == "shove", "short-blade fighter defends before body contact")
check(choices(0.90, 0, false)[1].kind == "melee", "short weapon retains a usable swing band")
check(choices(0.78, 0, false)[1].kind == "melee", "stationary target inside useful reach can be struck")
check(choices(0.78, 1.5, false)[1].kind == "backstep", "closing speed adds bounded early defensive movement")
actor.meleeDelay = 8
local recovering = choices(1.8, 0, false)
for _, choice in ipairs(recovering) do
    check(choice.kind ~= "melee" and choice.kind ~= "shove" and choice.kind ~= "approach",
        "native recovery does not attack or advance toward the zombie")
end
actor.meleeDelay = 0
AttackType = savedAttackType
SC.NativeActions.resetCombatEvents(actor)
SC_TEST_REPORT = "COMBAT_RECOVERY_KAHLUA_PASS checks=" .. checks
