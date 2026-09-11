-- SPDX-License-Identifier: MIT
-- Isolated regression for native body-part defaults and dead rescue candidates.
local SC, checks = SurvivorCompanion, 0
local M, U = SC.Medical, SC.GameplayUtil
local function check(value, message)
    checks = checks + 1
    assert(value, "medical liveness regression " .. checks .. ": " .. message)
end
local function part(bandaged, bleeding, life)
    local value = { hasBandage = bandaged == true, isBleeding = bleeding == true, life = life or 0 }
    function value:bandaged() return self.hasBandage end
    -- Exact native semantics: true on healthy, unbandaged parts too.
    function value:isBandageDirty() return self.life <= 0 end
    function value:bleeding() return self.isBleeding end
    function value:getBleedingTime() return self.isBleeding and 10 or 0 end
    return value
end
local square = { getX = function() return 0 end, getY = function() return 0 end,
    getZ = function() return 0 end }
local function patient(health, parts)
    local body = { health = health, parts = parts or {} }
    function body:getHealth() return self.health end
    function body:getBodyParts() return self.parts end
    function body:IsInfected() return self.infected == true end
    function body:getApparentInfectionLevel() return self.infection or 0 end
    local value = { body = body, __class = "IsoPlayer", data = {}, inventory = { items = {} } }
    function value:getBodyDamage() return self.body end
    function value:getHealth() return self.body.health end
    function value:getSquare() return square end
    function value:getX() return self.x or 0.5 end
    function value:getY() return 0.5 end
    function value:getZ() return 0 end
    function value:isDead() return self.dead == true end
    function value:getModData() return self.data end
    function value:getInventory() return self.inventory end
    function value.inventory:getItems() return self.items end
    return value
end
local helper = patient(100, { part(false), part(false), part(false) })
local assessed = M.assess(helper)
check(assessed.dirtyBandages == 0 and not assessed.needsBandageChange and assessed.woundCount == 0,
    "native zero bandage life does not invent dirty bandages on healthy parts")
local dirty = patient(80, { part(true, false, 0) })
check(M.assess(dirty).dirtyBandages == 1 and M.assess(dirty).needsBandageChange,
    "a genuinely worn dirty bandage still requests replacement")
local clean = patient(80, { part(true, false, 10) })
check(not M.assess(clean).needsBandageChange, "clean worn bandage remains clean")
local living = patient(60, { part(false, true) })
check(M.assess(living).needsBandage and M.assess(living).dirtyBandages == 0,
    "uncovered bleeding still needs treatment, not dirty-bandage replacement")
local dead = patient(0, { part(false, true), part(false, true), part(false, true) })
check(not M.isLivingPatient(dead), "zero body health excludes rescue even before native death flag updates")
local corpse = patient(100, { part(false, true) })
corpse.dead = true
check(not M.isLivingPatient(corpse), "native dead flag excludes a stale positive-health corpse")
local terminal = patient(15, { part(false, true) })
terminal.body.infected, terminal.body.infection = true, 100
check(not M.isLivingPatient(terminal), "terminal Knox actor cannot remain a rescue patient")
local accepted, reason = M.treat(helper, dead, {})
check(not accepted and reason == "invalid_patient" and M.peek(helper) == nil,
    "direct treatment rejects zero-health patient without claiming an action")
local snapshot = { threats = {}, immediateAttackers = {}, immediateCount = 0, threatCount = 0,
    allies = {}, escapeSquares = {}, sounds = {} }
local originalTreat, calls = M.treat, 0
M.treat = function() calls = calls + 1 return true, "selected_patient" end
M.update(helper, dead, { snapshot = snapshot })
check(calls == 0, "medical rescue selection ignores corpse bleeding")
M.update(helper, living, { snapshot = snapshot })
check(calls == 1, "medical rescue selection still treats a living bleeding player")
M.treat = originalTreat
local function rescueCount(player, allies)
    snapshot.allies = allies or {}
    local candidates = SC.Decision._evaluateForTests(helper, player, snapshot,
        { recruited = true, order = "stay" }, M.assess(helper), {}, {}, 1000)
    local count = 0
    for _, candidate in ipairs(candidates) do
        if candidate.kind == "medical" and candidate.detail and candidate.detail.rescue then count = count + 1 end
    end
    return count
end
check(rescueCount(dead, { { actor = corpse }, { actor = terminal } }) == 0,
    "decision emergency scoring cannot select dead player, dead ally, or terminal patient")
check(rescueCount(living) == 1, "decision rescue priority still selects living bleeding player")
check(rescueCount(dead, { { actor = living } }) == 1, "dead player cannot mask a living ally's rescue")

-- Death during a real staged treatment releases its owner and supplies.
local savedNative, savedSupervisor, savedMove, savedStop = SC.NativeActions, SC.ActionSupervisor, U.move, U.stop
SC.ActionSupervisor = nil
SC.NativeActions = { visualStatus = function() return "active" end,
    clearVisual = function() end, cancelVisual = function() return true end }
U.move, U.stop = function() return true end, function() return true end
local bandage = { getFullType = function() return "Base.Bandage" end }
helper.inventory.items = { bandage }
function helper.inventory:contains(item) return self.items[1] == item end
accepted = M.treat(helper, living, { snapshot = snapshot })
check(accepted and M.peek(helper) and M.peek(helper).phase == "bandaging",
    "living patient starts a staged bandage transaction")
living.body.health = 0
M.treat(helper, helper, { snapshot = snapshot })
check(M.peek(helper) == nil and helper.inventory.items[1] == bandage,
    "patient death cancels animation ownership without consuming reserved bandage")
SC.NativeActions, SC.ActionSupervisor, U.move, U.stop = savedNative, savedSupervisor, savedMove, savedStop

-- Run real Decision.update and real Medical.update, isolating only world services
-- and movement endpoints. Low health with no treatable injury is not a medicine
-- action and must never strand Follow behind the safety-tier fallback guard.
do
    local saved = {}
    for _, name in ipairs({ "Commands", "Positioning", "Navigation", "Senses", "Combat",
        "Needs", "InfectionCrisis", "Autonomy", "Encounter", "Logistics", "FactionBehavior",
        "Personality", "Objectives", "Downtime", "Dialogue", "ActionSupervisor", "NativeActions",
        "Locomotion", "Performance" }) do
        saved[name] = SC[name]
        SC[name] = nil
    end
    local oldStop, oldMove = U.stop, U.move
    SC.Commands = { effective = function()
        return { recruited = true, order = "follow", moveMode = "walk" }
    end }
    SC.Positioning = {
        formationTarget = function(_, leader) return leader end,
        shouldHold = function() return false end,
        followMode = function() return "walk" end,
    }
    SC.Navigation = { request = function(value)
        value.followCalls = (value.followCalls or 0) + 1
        return true, "followed"
    end }
    U.stop = function(value) value.stopCalls = (value.stopCalls or 0) + 1 return true end
    local leader = patient(100)
    leader.x = 10.5
    local function quietRuntime()
        return { snapshot = { threats = {}, immediateAttackers = {}, escapeSquares = {},
            allies = {}, threatCount = 0, immediateCount = 0, pressure = 0, sounds = {} } }
    end
    local function medicalCount(value, target, runtime)
        local count = 0
        local proposals = SC.Decision._evaluateForTests(value, target, runtime.snapshot,
            SC.Commands.effective(), M.assess(value, runtime), {}, {}, SC_TEST_CLOCK)
        for _, proposal in ipairs(proposals) do
            if proposal.kind == "medical" then count = count + 1 end
        end
        return count, proposals
    end
    for _, health in ipairs({ 100, 35, 19, 18, 10, 1 }) do
        local value, runtime = patient(health), quietRuntime()
        check(not M.hasActionableNeed(value, M.assess(value), true)
                and medicalCount(value, leader, runtime) == 0,
            "health " .. health .. " alone cannot propose self medicine")
        local treated, treatmentReason = M.update(value, leader, runtime)
        check(not treated and treatmentReason == "no_medical_action",
            "health " .. health .. " alone has no treatment executor action")
        local handled, result
        for _ = 1, 10 do
            SC_TEST_CLOCK = SC_TEST_CLOCK + 1000
            handled, result = SC.Decision.update(value, leader, runtime)
        end
        check(handled and result == "followed" and (value.followCalls or 0) > 0
                and (value.stopCalls or 0) == 0 and SC.Decision.peek(value).current == "follow",
            "health " .. health .. " follows normally without a medical or safety hold")
        local rescuer, rescueRuntime = patient(100), quietRuntime()
        rescueRuntime.snapshot.allies = { { actor = value } }
        check(medicalCount(rescuer, value, rescueRuntime) == 0,
            "health " .. health .. " alone cannot propose player or ally rescue")
        local oldTreat, rescueCalls = M.treat, 0
        M.treat = function() rescueCalls = rescueCalls + 1 return true, "unexpected_rescue" end
        M.update(rescuer, value, rescueRuntime)
        M.treat = oldTreat
        check(rescueCalls == 0, "health " .. health .. " alone cannot execute a rescue")
    end

    local fragile, danger = patient(10), quietRuntime()
    danger.snapshot.threats = { { actor = patient(100), distanceSq = 9, visible = true } }
    danger.snapshot.threatCount = 1
    local _, proposals = medicalCount(fragile, leader, danger)
    check(proposals[1].kind == "combat" and proposals[1].emergency
            and proposals[1].safetyTier == SC.Decision.SafetyTier.SURVIVAL,
        "critical health still promotes real danger to survival combat and its retreat policy")
    SC.Combat = { update = function() return false, "blocked_defense" end }
    local handled, reason
    for _ = 1, 4 do
        SC_TEST_CLOCK = SC_TEST_CLOCK + 1000
        handled, reason = SC.Decision.update(fragile, leader, danger)
    end
    check(handled and reason == "safety_guarded_hold:combat" and not fragile.followCalls,
        "a rejected critical combat response still cannot fall through to routine Follow")
    SC.Combat = nil

    local criticalDirty, cleanRuntime = patient(19, { part(true, false, 0) }), quietRuntime()
    local oldTreat, treatedPatient = M.treat, nil
    M.treat = function(_, target) treatedPatient = target return true, "replace_actual_bandage" end
    local replaced = M.update(criticalDirty, leader, cleanRuntime)
    M.treat = oldTreat
    check(replaced and treatedPatient == criticalDirty
            and medicalCount(criticalDirty, leader, cleanRuntime) == 1,
        "critical dirty-bandage proposal and execution agree on actual self treatment")

    local legacy, legacyRuntime = patient(10), quietRuntime()
    legacyRuntime.downed, legacyRuntime.needsRescue = true, true
    check(M.assess(legacy, legacyRuntime).downed and not M.assess(legacy).downed
            and medicalCount(legacy, leader, legacyRuntime) == 1,
        "only an explicit supplied legacy downed state requests emergency self recovery")
    U.move = function(_, _, intent)
        check(intent.action == "recover_from_downed", "legacy recovery uses the existing native recovery action")
        return false
    end
    local recovered, recoveryReason = M.update(legacy, leader, legacyRuntime)
    check(not recovered and recoveryReason == "recovery_action_rejected"
            and legacyRuntime.downed and legacyRuntime.needsRescue,
        "a rejected native recovery preserves the explicit legacy state")
    U.move = function(value, _, intent)
        value.recoveryAction = intent.action
        return true
    end
    for _ = 1, 5 do
        SC_TEST_CLOCK = SC_TEST_CLOCK + 1000
        SC.Decision.update(legacy, leader, legacyRuntime)
    end
    check(legacy.recoveryAction == "recover_from_downed" and not legacyRuntime.downed
            and not legacyRuntime.needsRescue and (legacy.followCalls or 0) > 0,
        "accepted legacy recovery clears its flags and resumes Follow through real decisions")
    U.stop, U.move = oldStop, oldMove
    for name, value in pairs(saved) do SC[name] = value end
end
SC_TEST_REPORT = "MEDICAL_LIVENESS_REGRESSION_PASS checks=" .. checks
