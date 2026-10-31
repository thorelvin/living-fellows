-- SPDX-License-Identifier: MIT
-- Runs inside the gameplay integration world's real perception/combat modules.
function SC_HUMAN_COMBAT_REGRESSIONS(f)
    local SC, checks = SurvivorCompanion, 0
    local function check(condition, message)
        checks = checks + 1
        f.check(condition, message)
    end
    local actor = f.actor("sc-human-regression", -3, -3, {})
    local enemy = f.zombie(2, -3, {})
    function enemy:getX() return self.worldX or (self.square.x + 0.5) end
    function enemy:getY() return self.worldY or (self.square.y + 0.5) end
    function enemy:getVariableBoolean(key) return key == "Bandit" end
    f.registry[actor.id] = actor
    local commands = { recruited = true, order = "stay", combatDoctrine = "stealth" }
    local oldPeek, oldRelation, oldAttack = SC.Commands.peek, SC.BanditsAdapter.relationship, SC.BanditsAdapter.isAttacking
    local oldMove, oldRequest = SC.GameplayUtil.move, SC.Navigation.request
    local attacking, requested, intent, reject = nil, nil, nil, false
    SC.Commands.peek = function(value) return value == actor and commands or oldPeek(value) end
    SC.BanditsAdapter.relationship = function(bandit, value)
        if bandit == enemy and value == actor then return "hostile" end
        return oldRelation(bandit, value)
    end
    SC.BanditsAdapter.isAttacking = function(bandit, value)
        if bandit == enemy then return value == attacking end
        return oldAttack(bandit, value)
    end
    SC.Navigation.request = function(value, square, mode, options)
        if value ~= actor then return oldRequest(value, square, mode, options) end
        requested = { square = square, intent = options }
        return true, "path_requested"
    end
    SC.GameplayUtil.move = function(value, mode, options)
        if value ~= actor then return oldMove(value, mode, options) end
        intent = options
        if reject then return false, type(reject) == "string" and reject or "native_action_rejected" end
        if options.action == "equip_weapon" then value:setPrimaryHandItem(options.item) end
        return true, options.action
    end
    local function place(value, x, y)
        value.worldX, value.worldY = nil, nil
        local moving = value.square.moving
        for index = #moving, 1, -1 do if moving[index] == value then table.remove(moving, index) end end
        value.square = f.cell:getGridSquare(x, y, 0)
        value.square.moving[#value.square.moving + 1] = value
    end
    local function human()
        return { actor = enemy, external = "bandits2", visible = true,
            x = enemy:getX(), y = enemy:getY(), z = enemy:getZ() }
    end
    local state, escapes, meta = {}, nil, nil
    local quiet = SC.Senses._collectEscapeSquaresForTests(actor, {}, state, f.clock, 0, nil)
    check(#quiet == 0, "quiet perception still defers escape work")
    for _ = 1, 32 do
        escapes, _, meta = SC.Senses._collectEscapeSquaresForTests(actor, {}, state, f.clock, 0, nil, human())
        if state.escapeSearch == nil then break end
    end
    check(#escapes > 0 and state.escapeSearch == nil and meta.signature ~= "quiet_deferred",
        "a human-only threat starts and completes the existing bounded escape search")
    check(escapes[1].square:getX() < actor:getX() and escapes[1].nearestThreatSq > 25,
        "human-only retreat candidates prefer reachable ground away from the Bandit")
    local snapshot = { actor = actor, threats = {}, threatCount = 0, immediateCount = 0,
        escapeSquares = escapes, humanThreat = human(), pressure = 0, player = { danger = 0, actor = f.player } }
    local handled = SC.FactionBehavior.updateHumanCombat(actor, nil, {}, snapshot.humanThreat, snapshot)
    check(handled and requested and requested.intent.action == "human_threat_retreat"
            and requested.square:getX() < actor:getX() and #snapshot.threats == 0,
        "Stealth dispatches a real navigation request without adding Bandits to zombie threats")
    commands.combatDoctrine, actor.body.health, requested = "weapons_free", 30, nil
    check(SC.FactionBehavior.updateHumanCombat(actor, nil, {}, snapshot.humanThreat, snapshot)
            and requested and requested.intent.action == "human_threat_retreat",
        "an injured aggressive companion also retreats from a human-only threat")
    local oldCorneredALife = SC.ALifeAdapter
    -- A fresh cornered encounter has no assignment from the escape test above.
    SC.Combat.reset()
    local cornered = { threats = {}, threatCount = 0, immediateCount = 0, escapeSquares = {}, pressure = 0 }
    for _, external in ipairs({ "bandits2", "project_alife" }) do
        if external == "project_alife" then
            SC.ALifeAdapter = { owns = function(value) return value == enemy end,
                relationship = function() return "hostile" end,
                isAttacking = function(_, value) return value == attacking end }
        end
        place(enemy, -2, -3)
        local contact = human()
        contact.external = external
        for _, mode in ipairs({ { "stealth", 100 }, { "weapons_free", 30 } }) do
            commands.combatDoctrine, actor.body.health, intent, requested = mode[1], mode[2], nil, nil
            local defended, why = SC.FactionBehavior.updateHumanCombat(actor, nil, {}, contact, cornered)
            check(defended and intent and intent.action == "shove" and requested == nil
                    and why ~= "human_retreat_position_unavailable",
                external .. " cornered " .. mode[1] .. " companion defends contact without an escape square: "
                    .. tostring(why) .. "/" .. tostring(intent and intent.action)
                    .. "/" .. tostring(requested and requested.intent.action))
        end
        place(enemy, 2, -3)
        contact = human()
        contact.external = external
        commands.combatDoctrine, actor.body.health, intent = "stealth", 100, nil
        local held, why = SC.FactionBehavior.updateHumanCombat(actor, nil, {}, contact, cornered)
        check(held and why == "human_retreat_position_unavailable" and intent == nil,
            external .. " cornered Stealth actor does not initiate a distant fight")
        place(enemy, -2, -3)
        contact = human()
        contact.external, contact.visible, attacking, intent = external, false, actor, nil
        held, why = SC.FactionBehavior.updateHumanCombat(actor, nil, {}, contact, cornered)
        check(held and why == "human_retreat_position_unavailable" and intent == nil,
            external .. " cornered actor does not chase an unseen attacker")
        attacking = nil
    end
    SC.ALifeAdapter = oldCorneredALife
    SC.FactionBehavior.releaseActor(actor)
    place(enemy, 2, -3)
    commands.combatDoctrine, actor.body.health = "stealth", 100
    local walker = f.zombie(-8, -3, {})
    local undead = { { actor = walker, x = walker:getX(), y = walker:getY(), z = 0 } }
    local mixed = SC.Senses._collectEscapeSquaresForTests(actor, undead, state, f.clock + 1, 0, nil, human())
    check(#mixed > 0 and mixed[1].nearestThreatSq > 25 and #undead == 1,
        "mixed-threat escape scoring avoids both the nearby Bandit and an ordinary zombie")
    for index = #walker.square.moving, 1, -1 do
        if walker.square.moving[index] == walker then table.remove(walker.square.moving, index) end
    end
    local geometry = state.escapeTopology
    local cachedHuman = human()
    place(enemy, -8, -3)
    local moved = SC.Senses._collectEscapeSquaresForTests(actor, {}, state, f.clock + 1, 0, nil, cachedHuman)
    check(state.escapeTopology == geometry and #moved > 0 and moved[1].square:getX() > actor:getX(),
        "cached escape geometry is rescored against a moving human's latest position")
    enemy.dead = true
    local retired = SC.Senses._collectEscapeSquaresForTests(actor, {}, state, f.clock + 2, 0, nil, human())
    check(#retired == 0, "a retired human cannot keep peaceful escape work active")
    enemy.dead = false
    place(enemy, 2, -3)
    local runtime, observed = {}, nil
    for _ = 1, 32 do
        observed = SC.Senses.snapshot(actor, nil, runtime)
        if observed.humanThreat then break end
    end
    check(observed.humanThreat and observed.humanThreat.actor == enemy
            and observed.threatCount == 0 and #observed.escapeSquares > 0,
        "production snapshot collection supplies human-only escapes while keeping undead counts zero")
    observed = SC.Senses.refreshImmediate(actor, nil, observed, runtime)
    check(observed.humanThreat and #observed.escapeSquares > 0 and observed.threatCount == 0,
        "the reflex refresh retains human-aware escape scoring")

    local assessment = { downed = false, critical = false, bleedingCount = 1 }
    local function urgent()
        snapshot.humanThreat = human()
        return SC.Decision._ownerNeedsImmediatePreemptionForTests("medical", snapshot,
            assessment, {}, commands, false, actor, f.player)
    end
    place(enemy, 17, -3)
    for _, doctrine in ipairs({ "close_defense", "ranged_support", "stealth" }) do
        commands.combatDoctrine = doctrine
        check(not urgent(), doctrine .. " keeps treatment active for a distant non-attacking Bandit")
    end
    commands.combatDoctrine = "close_defense"
    local service, cancellations = SC.ActionSupervisor, 0
    local token = service.begin(actor, { owner = "medical", action = "treat_wound",
        targetKey = "actor:" .. actor.id, priority = service.Priority.COMBAT_RESCUE,
        interruptible = true, onCancel = function() cancellations = cancellations + 1 return true end })
    check(token and service.transition(token, "animating"), "the medical regression owns a real supervisor transaction")
    SC.Decision._holdOwnedActivityOrPacingForTests(actor, f.player, snapshot, assessment,
        {}, commands, {}, f.clock)
    check(service.isCurrent(token) and cancellations == 0,
        "the real decision ownership gate retains treatment for a distant non-attacking Bandit")
    attacking = actor
    SC.Decision._holdOwnedActivityOrPacingForTests(actor, f.player, snapshot, assessment,
        {}, commands, {}, f.clock)
    check(not service.isCurrent(token) and cancellations == 1,
        "an actual attack still cancels the real medical transaction through its rollback callback")
    attacking = nil
    commands.combatDoctrine = "weapons_free"
    check(urgent(), "Weapons Free retains its explicit proactive combat policy")
    commands.combatDoctrine, attacking = "close_defense", actor
    check(urgent(), "an actual attack interrupts treatment outside the close-defense radius")
    attacking = f.player
    check(urgent(), "an attack on the main player remains urgent for a recruited companion")
    attacking = nil
    place(enemy, 2, -3)
    check(urgent(), "a nearby Bandit still interrupts treatment")
    place(enemy, 17, -3)
    snapshot.immediateCount = 1
    check(urgent(), "immediate zombie pressure still interrupts treatment")
    snapshot.immediateCount, commands.order = 0, "retreat"
    check(urgent(), "a direct Retreat order still interrupts treatment")
    commands.order = "stay"

    local gun = f.item("Base.Pistol", "Weapon", { ranged = true, ammo = 0, maxAmmo = 15,
        magazineType = "Base.9mmClip", ammoType = "Base.Bullets9mm", range = 12 })
    local magazine = f.item("Base.9mmClip", "Magazine", { ammo = 12 })
    local bat = f.item("Base.BaseballBat", "Weapon", { damage = 1.4 })
    actor.inventory = f.inventory({ gun, magazine, bat })
    actor.primary, commands.combatDoctrine = gun, "weapons_free"
    place(enemy, 2, -3)
    local function fight()
        intent = nil
        return SC.FactionBehavior.updateHumanCombat(actor, nil, {}, human(), {})
    end
    check(fight() and intent.action == "reload" and intent.weapon == gun
            and gun.ammo == 0 and magazine.ammo == 12 and #actor.inventory.items == 3,
        "an empty gun uses the ordinary reload action without creating ammunition or changing item ownership")
    gun.ammo, gun.jammed = 2, true
    check(fight() and intent.action == "unjam" and intent.weapon == gun,
        "a jammed human-combat firearm uses the ordinary rack action")
    gun.jammed = false
    check(fight() and intent.action == "attack_firearm", "a loaded repaired gun can fire at a hostile human")
    gun.ammo, magazine.ammo = 0, 0
    actor.inventory:AddItem(f.item("Base.45Clip", "Magazine", { ammo = 15 }))
    SC.InventoryIndex.touch(actor)
    check(fight() and intent.action == "equip_weapon" and actor.primary == bat,
        "empty and incompatible magazines cannot prevent a real carried melee fallback")
    actor.primary, reject = gun, true
    magazine.ammo = 12
    local accepted, failure = fight()
    check(not accepted and failure == "native_action_rejected" and intent.action == "reload",
        "a rejected native reload is reported rather than replaced by a shot")
    reject = false
    local baggedMagazine = f.item("Base.9mmClip", "Magazine", { ammo = 9 })
    local bag = f.item("Base.Bag_Schoolbag", "Container", { nestedInventory = f.inventory({ baggedMagazine }) })
    function bag:getItemContainer() return self.nestedInventory end
    actor.inventory = f.inventory({ gun, bag })
    SC.InventoryIndex.touch(actor)
    check(fight() and intent and intent.action == "reload" and baggedMagazine.ammo == 9,
        "compatible ammunition in an owned bag uses the same reload path")
    actor.primary, commands.holdFire = gun, true
    local held, holdReason = fight()
    check(not held and holdReason == "hold_fire" and intent == nil,
        "Hold Fire does not fire or start maintenance in place of the player's held movement order")
    place(enemy, -2, -3)
    check(fight() and intent.action == "shove", "an immediate attacker is shoved instead of reloading at contact distance")

    local oldNative, holds = SC.NativeActions, 0
    SC.NativeActions = { holdCombatPosition = function(value)
        holds = holds + 1
        check(value == actor, "recovery holds the actor that owns this attack")
        return true
    end }
    gun.ammo, commands.holdFire = 3, false
    place(enemy, 2, -3)
    for _, recovery in ipairs({ "native_attack_active", "native_melee_recovery", "native_recoil_recovery" }) do
        reject = recovery
        local waiting, why = fight()
        check(waiting and why == "combat_recovery_wait" and intent.action == "attack_firearm",
            "human combat retains native attack ownership during " .. recovery)
    end
    check(holds == 3, "every native recovery pulse stops translation without lowering or replacing the weapon")
    SC.NativeActions.holdCombatPosition = function() return false end
    local stopped, stopFailure = fight()
    check(not stopped and stopFailure == "native_combat_stop_failed", "a rejected stationary recovery is still a real failure")
    SC.NativeActions, reject = oldNative, false

    actor.inventory:AddItem(bat)
    actor.primary, commands.holdFire = bat, false
    local spacing = SC.Combat.meleeSpacing(actor, bat)
    local outerBand = spacing.maximum - 0.02
    place(enemy, actor:getX() + outerBand, actor:getY())
    enemy.worldX, enemy.worldY = actor:getX() + outerBand, actor:getY()
    check(fight() and intent.action == "combat_approach",
        "human melee closes inside actual reach instead of swinging at the outer acceptance tolerance")
    place(enemy, actor:getX() + spacing.desired, actor:getY())
    enemy.worldX, enemy.worldY = actor:getX() + spacing.desired, actor:getY()
    check(fight() and intent.action == "attack_melee",
        "human melee commits its native swing once the ordinary weapon spacing is reached")

    -- Exercise the production update boundary, where non-recruited people used
    -- to lose A-Life observations even though perception classified them correctly.
    local oldALife, oldSnapshot, oldReflex = SC.ALifeAdapter, SC.Senses.snapshot, SC.Senses.refreshImmediate
    local relation = "hostile"
    SC.ALifeAdapter = { owns = function(value) return value == enemy end,
        relationship = function() return relation end, isAttacking = function() return true end }
    commands.recruited, commands.holdFire = false, false
    for _, role in ipairs({ "household", "strange_folk" }) do
        local contact = human()
        contact.external = "project_alife"
        local perception = { threats = {}, immediateAttackers = {}, allies = {}, escapeSquares = {},
            humanThreat = contact, threatCount = 0, immediateCount = 0, pressure = 0, player = { danger = 0 } }
        SC.Senses.snapshot = function() return perception end
        SC.Senses.refreshImmediate = function() return perception end
        local decisionRuntime = {}
        SC.Decision.reset(actor)
        SC.Decision.update(actor, f.player, decisionRuntime, f.clock)
        check(decisionRuntime.snapshot.humanThreat == contact,
            role .. " retains an observed A-Life hostile through the real decision update")
        relation, perception.humanThreat = "neutral", contact
        SC.Decision.update(actor, f.player, decisionRuntime, f.clock + 1000)
        check(decisionRuntime.snapshot.humanThreat == nil,
            role .. " drops a stale A-Life hostile after a truce")
        relation = "hostile"
    end
    SC.ALifeAdapter, SC.Senses.snapshot, SC.Senses.refreshImmediate = oldALife, oldSnapshot, oldReflex

    SC.Commands.peek, SC.BanditsAdapter.relationship, SC.BanditsAdapter.isAttacking = oldPeek, oldRelation, oldAttack
    SC.GameplayUtil.move, SC.Navigation.request = oldMove, oldRequest
    SC.Senses.reset(actor)
    SC.Combat.reset(actor)
    SC.FactionBehavior.releaseActor(actor)
    f.registry[actor.id] = nil
    for _, value in ipairs({ actor, enemy }) do
        local moving = value.square and value.square.moving or {}
        for index = #moving, 1, -1 do if moving[index] == value then table.remove(moving, index) end end
    end
    print("HUMAN_COMBAT_REGRESSION_PASS checks=" .. tostring(checks))
end
