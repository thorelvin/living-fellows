-- SPDX-License-Identifier: MIT
-- Subject scenarios use the same native-shaped fixture as the essential checks.
local f = assert(SurvivorCompanion.TestFixture)
local check, item, inventory, actor, zombie = f.check, f.item, f.inventory, f.actor, f.zombie
local bodyPart, bodyDamage, buildKit = f.bodyPart, f.bodyDamage, f.buildKit
local cell, registry, player, containerObject = f.cell, f.registry, f.player, f.containerObject
local makeSquare, squares, movementLog = f.makeSquare, f.squares, f.movementLog
function SurvivorCompanion.__testDecisionNativeSwingLease()
    local SC = SurvivorCompanion
    local oldSenses, oldNative = SC.Senses, SC.NativeActions
    local oldStop, oldMove = SC.Actor.stop, SC.Actor.setMovement
    local quietSnapshot = {
        threats = {}, threatCount = 0, immediateCount = 0, pressure = 0,
        escapeSquares = {}, allies = {}, player = { danger = 0 },
    }
    SC.Senses = {
        snapshot = function() return quietSnapshot end,
        refreshImmediate = function() return quietSnapshot end,
    }
    SC.NativeActions = {
        holdCombatPosition = function(value)
            value.leaseHolds = (value.leaseHolds or 0) + 1
            if value.rejectStop then return false end
            value.moving = false
            return true
        end,
        pollCombatEvents = function(value)
            local evidence = value.pendingEvidence
            value.pendingEvidence = nil
            if evidence then
                value.consumedImpacts = (value.consumedImpacts or 0) + 1
                return true, "stomp_collision_landed", evidence
            end
            return false, "no_pending_combat"
        end,
    }
    SC.Actor.stop = function(value)
        if value.leaseProbe then value.attackPose = false end
        return oldStop(value)
    end
    SC.Actor.setMovement = function(value, mode, intent)
        if value.leaseProbe then value.attackPose = false end
        return oldMove(value, mode, intent)
    end
    for _, order in ipairs({ "follow", "stay" }) do
        local fighter = actor("sc-decision-swing-" .. order, 24, 28, {})
        registry[fighter.id] = fighter
        fighter.modData.SC_Order = order
        fighter.leaseProbe, fighter.attackPose, fighter.attackStarted = true, true, true
        function fighter:isAttackStarted() return self.attackStarted end
        function fighter:isPerformingAttackAnimation() return self.attackStarted end
        local runtime = { snapshot = quietSnapshot }
        SC.Combat.update(fighter, player, runtime)
        local victim = zombie(25, 28, { onFloor = true })
        victim.dead = true
        local combatState = SC.Combat.peek(fighter)
        combatState.target, combatState.lastOffensiveTarget = victim, victim
        combatState.lastOffensiveAt = f.clock
        fighter.pendingEvidence = { result = "landed", action = "stomp", target = victim }
        local holdsBefore = fighter.leaseHolds or 0
        local movementBefore = fighter.movementCalls or 0
        local handled, reason
        for _ = 1, 2 do
            f.clock = f.clock + 201
            handled, reason = SC.Decision.update(fighter, player, runtime)
        end
        check(handled and reason == "attack_in_progress" and fighter.attackPose == true
                and fighter.leaseHolds > holdsBefore
                and (fighter.movementCalls or 0) == movementBefore,
            "real Decision preserves the native swing tail after its last target dies under " .. order
                .. ": " .. tostring(reason))
        check(fighter.consumedImpacts == 1
                and SC.Combat.peek(fighter).lastCombatEvidenceReason == "stomp_collision_landed",
            "Decision consumes each pending native collision once while holding the no-threat swing tail")
        fighter.attackStarted = false
        for _ = 1, 4 do
            f.clock = f.clock + 201
            handled, reason = SC.Decision.update(fighter, player, runtime)
        end
        check(reason ~= "attack_in_progress" and fighter.attackPose == false,
            "real Decision resumes " .. order .. " only after the native swing exits")
        SC.Combat.reset(fighter)
        SC.Decision.reset(fighter)
        registry[fighter.id] = nil
    end
    local priorityFighter = actor("sc-decision-swing-priority", 24, 29, {})
    registry[priorityFighter.id] = priorityFighter
    priorityFighter.modData.SC_Order = "stay"
    priorityFighter.leaseProbe, priorityFighter.attackPose = true, true
    function priorityFighter:isAttackStarted() return true end
    function priorityFighter:isPerformingAttackAnimation() return true end
    function priorityFighter:getCompanionActionStateName() return self.actionState or "melee" end
    local priorityRuntime = { snapshot = quietSnapshot }
    priorityFighter.rejectStop = true
    local held, holdReason = SC.Decision.update(priorityFighter, player, priorityRuntime)
    check(not held and holdReason == "native_combat_stop_failed"
            and priorityFighter.attackPose == true and not priorityFighter.lastIntent,
        "a rejected native swing hold cannot fall through to stay or follow")
    priorityFighter.rejectStop = nil
    local holdsBefore = priorityFighter.leaseHolds or 0
    for _, nativeState in ipairs({ "hitreaction", "grapple", "getup" }) do
        priorityFighter.actionState = nativeState
        local leased = SC.Combat.holdNativeAttack(priorityFighter, priorityRuntime)
        check(leased == nil and priorityFighter.leaseHolds == holdsBefore,
            "native " .. nativeState .. " keeps precedence over a stale attack flag")
    end
    priorityFighter.actionState = "melee"
    priorityFighter.knockedDown = true
    check(SC.Combat.holdNativeAttack(priorityFighter, priorityRuntime) == nil
            and priorityFighter.leaseHolds == holdsBefore,
        "native knockdown keeps precedence over a stale attack flag")
    priorityFighter.knockedDown = false
    priorityFighter.body.infected, priorityFighter.body.infectionLevel = true, 100
    local terminalHandled, terminalReason = SC.Decision.update(priorityFighter, player, priorityRuntime)
    check(not terminalHandled and terminalReason == "dead"
            and priorityFighter.leaseHolds == holdsBefore,
        "terminal medical state precedes the native combat lease")
    priorityFighter.body.infected, priorityFighter.body.infectionLevel = false, 0
    local oldMedicalUpdate = SC.Medical.update
    local oldSelfCareBlocker = SC.Medical.selfCareBlocker
    SC.Medical.update = function(value, ...)
        if value == priorityFighter then return true, "medical_priority_probe" end
        return oldMedicalUpdate(value, ...)
    end
    SC.Medical.selfCareBlocker = function(value)
        if value == priorityFighter then return nil end
        return oldSelfCareBlocker(value)
    end
    priorityFighter.body.parts = { bodyPart({ name = "ForeArm_R", isBleeding = true }) }
    for _, health in ipairs({ 25, 10 }) do
        priorityFighter.body.health = health
        SC.Decision.reset(priorityFighter)
        for _ = 1, 4 do
            f.clock = f.clock + 201
            held, holdReason = SC.Decision.update(priorityFighter, player, priorityRuntime)
        end
        check(held and holdReason == "medical_priority_probe"
                and priorityFighter.leaseHolds == holdsBefore,
            "actionable critical medicine precedes the native swing lease at health " .. tostring(health))
    end
    SC.Medical.update = oldMedicalUpdate
    SC.Medical.selfCareBlocker = oldSelfCareBlocker
    SC.Combat.reset(priorityFighter)
    SC.Decision.reset(priorityFighter)
    registry[priorityFighter.id] = nil
    SC.Actor.stop, SC.Actor.setMovement = oldStop, oldMove
    SC.Senses, SC.NativeActions = oldSenses, oldNative
end
SurvivorCompanion.__testDecisionNativeSwingLease()
SurvivorCompanion.__testDecisionNativeSwingLease = nil

function SurvivorCompanion.__testDelegateReleasesCorpseDrag()
    local sc = SurvivorCompanion
    local saved = {
        production = sc.Production, downtime = sc.Downtime and sc.Downtime.update,
        needs = sc.Needs and sc.Needs.update, encounter = sc.Encounter and sc.Encounter.update,
        baseWork = sc.BaseWork and sc.BaseWork.update, combat = sc.Combat and sc.Combat.update,
    }
    local released, ran = {}, {}
    sc.Production = { releaseDrag = function(subject, reason)
        released[#released + 1] = reason
        return true, reason
    end }
    local function stub(kind) return function() ran[#ran + 1] = kind return false, "stub" end end
    sc.Downtime.update, sc.Needs.update = stub("downtime"), stub("needs")
    sc.Encounter.update, sc.BaseWork.update = stub("scavenge"), stub("base_work")
    sc.Combat.update = stub("combat")
    local hauler = actor("drag-delegate", 3, 3, { recruited = true })
    for _, kind in ipairs({ "base_work", "combat", "downtime", "needs", "scavenge" }) do
        sc.Decision._delegateForTests({ kind = kind }, hauler, player, {}, {},
            { threats = {}, threatCount = 0, immediateCount = 0 }, {})
    end
    sc.Production = saved.production
    sc.Downtime.update, sc.Needs.update = saved.downtime, saved.needs
    sc.Encounter.update, sc.BaseWork.update = saved.encounter, saved.baseWork
    sc.Combat.update = saved.combat
    check(#ran == 5 and #released == 3 and released[1] == "decision_downtime"
            and released[2] == "decision_needs" and released[3] == "decision_scavenge",
        "every delegate but base work and combat puts a towed body down first: "
            .. table.concat(released, ","))
end
SurvivorCompanion.__testDelegateReleasesCorpseDrag()
SurvivorCompanion.__testDelegateReleasesCorpseDrag = nil

print("SUBJECT_PASS checks=" .. tostring(f.checks()))
