-- SPDX-License-Identifier: MIT
-- Real target selection, strike geometry and one owner per native damage episode.
local SC, f = SurvivorCompanion, SurvivorCompanion.TestFixture
local check = f.check
local part = f.bodyPart({})
local parts = { part }
function parts:size() return #self end
function parts:get(index) return self[index + 1] end
local fighter = f.actor("essential-fighter", 0, 0, { body = f.bodyDamage(100, parts) })
f.registry[fighter.id] = fighter
local player, playerHealth = f.player, f.player.body.health
local attacker = f.zombie(1, 0, {})
local accepted = SC.ZombieTargeting.consider(attacker, fighter)
check(accepted and attacker.target == fighter and attacker.spottedCalls == 1,
    "visible companions enter native zombie targeting")
attacker.target = player
SC.ZombieTargeting.scan(fighter, f.clock + 2000, { attacker })
check(attacker.target == player, "targeting preserves a live alternate player target")

local from, to = fighter.square, attacker.square
local door = { open = false }
function door:IsOpen() return self.open end
function door:isLocked() return false end
function from:isDoorTo(other) return other == to end
function to:isDoorTo(other) return other == from end
function to:getDoor(north) if north == false then return door end end
local blocked = SC.Topology.strikeBarrier(fighter, attacker, "melee", nil, {})
check(blocked, "a closed door owns the physical strike barrier")
door.open = true
check(not SC.Topology.strikeBarrier(fighter, attacker, "melee", nil, {}),
    "opening that exact door admits an unobstructed strike")

SC.ZombieAttack.reset()
attacker.target = fighter
attacker:beginAttackEpisode()
SC.ZombieAttack.resolve(fighter, f.clock, { attacker })
attacker:swingOutcome("success")
attacker:reportVictimProcessed(true)
local _, _, native = SC.ZombieAttack.resolve(fighter, f.clock, { attacker })
check(native.applied == 0 and native.receipts.native_injury == 1 and part.health == 100,
    "a native injury receipt prevents a second Lua wound")

local priorRandom = ZombRand
ZombRand = function(maximum) return maximum == 1000 and 300 or 0 end
attacker:beginAttackEpisode()
SC.ZombieAttack.resolve(fighter, f.clock + 500, { attacker })
attacker:swingOutcome("success")
attacker:finishBiteClip()
local _, _, fallback = SC.ZombieAttack.resolve(fighter, f.clock + 500, { attacker })
local healthAfter = part.health
local _, _, repeated = SC.ZombieAttack.resolve(fighter, f.clock + 550, { attacker })
ZombRand = priorRandom
check(fallback.applied == 1 and part.isScratched and not part.infectionRollReachable
        and healthAfter < 100 and repeated.applied == 0 and part.health == healthAfter,
    "an unprocessed completed episode wounds once and preserves the scratch infection policy"
        .. " applied=" .. tostring(fallback.applied)
        .. " landed=" .. tostring(fallback.landed)
        .. " omittedReceipt=" .. tostring(fallback.receipts.processing_omitted)
        .. " nativeReceipt=" .. tostring(fallback.receipts.native_injury)
        .. " health=" .. tostring(healthAfter) .. "/" .. tostring(part.health)
        .. " scratch=" .. tostring(part.isScratched)
        .. " infectionRoll=" .. tostring(part.infectionRollReachable)
        .. " repeated=" .. tostring(repeated.applied)
        .. " repeatedReceipt=" .. tostring(repeated.receipts.processing_omitted))
check(player.body.health == playerHealth and not player.lastIntent,
    "companion damage resolution leaves the local player untouched")

-- The optional boundary has no polling service and survives world/reset cycles.
local originalBridge, originalOptions, originalDiagnostics = SCBridge, SC.UserOptions, SC.Diagnostics
local requested, configCalls, diagnosticCalls = true, 0, 0
local nativeState = "absent"
SCBridge = {
    configurePZOptimizerAdapter = function(value)
        configCalls = configCalls + 1
        requested = value
    end,
    getPZOptimizerAdapterState = function() return nativeState end,
    getPZOptimizerAdapterReason = function() return "test " .. nativeState end,
    getPZOptimizerInlineCalls = function() return 7 end,
}
SC.UserOptions = { get = function() return requested end }
SC.Diagnostics = { report = function() diagnosticCalls = diagnosticCalls + 1 end }
check(not SC.PZOptimizerAdapter.initialize() and SC.PZOptimizerAdapter.status().state == "absent",
    "optimizer absent stays inactive")
nativeState = "active"
check(SC.PZOptimizerAdapter.initialize() and SC.PZOptimizerAdapter.status().inlineCalls == 7,
    "validated native adapter activates and exposes counters")
SC.PZOptimizerAdapter.status()
check(configCalls == 2, "reading Support does not reinstall or rescan the adapter")
SC.PZOptimizerAdapter.reset()
check(requested == false and SC.PZOptimizerAdapter.status().state == "disabled", "world reset disables the hook")
requested, nativeState = true, "unsupported"
SC.PZOptimizerAdapter.initialize()
SC.PZOptimizerAdapter.initialize()
check(diagnosticCalls == 1, "unsupported optimizer produces one readable diagnostic")
SCBridge = {}
check(not SC.PZOptimizerAdapter.initialize(), "older native bridges fail safely")
local originalPcall, invalidNativeCalls = pcall, 0
pcall = function(fn, ...)
    local okay, a, b = originalPcall(fn, ...)
    if not okay then invalidNativeCalls = invalidNativeCalls + 1 end
    return okay, a, b
end
for _,bridge in ipairs({false,{}}) do
    SCBridge = bridge or nil
    check(SC.PZOptimizerAdapter.reset(), "main-menu reset tolerates an unexposed native bridge")
    check(SC.PZOptimizerAdapter.status().inlineCalls == 0, "unexposed bridge status has no native counter")
    check(not SC.PZOptimizerAdapter.initialize(), "unexposed bridge initialization reports unavailable")
end
pcall = originalPcall
check(invalidNativeCalls == 0, "no caught nil or missing-API invocation can produce a game Lua exception")
SCBridge, SC.UserOptions, SC.Diagnostics = originalBridge, originalOptions, originalDiagnostics

-- A remembered route must not bypass another retreating companion's booking.
-- A positive route reply also needs physical progress before it counts as escape.
do
    local U, navigation = SC.GameplayUtil, SC.Navigation
    local request, remembered = navigation.request, navigation.retreatTarget
    local a, b = f.actor("retreat-route-a", 30, 30, {}), f.actor("retreat-route-b", 30, 31, {})
    local first, second = f.cell:getGridSquare(28, 30, 0), f.cell:getGridSquare(28, 31, 0)
    local goalByActor = {}
    navigation.retreatTarget = function() return first, { danger = 0 } end
    navigation.request = function(who, goal) goalByActor[who] = goal; return true, "path_pending" end
    local scene = { escapeSquares = { {square=first,score=10}, {square=second,score=8} } }
    local commands = { recruited=true, order="guard" }
    check(SC.Combat._executeRetreatForTests(a, nil, scene, nil, true,
        {cohortKey="retreat-native-goals"}, commands), "the first native retreat is admitted")
    check(SC.Combat._executeRetreatForTests(b, nil, scene, nil, true,
        {cohortKey="retreat-native-goals"}, commands) and goalByActor[a] ~= goalByActor[b],
        "remembered routes preserve distinct native retreat destinations")

    LosUtil.openGround(40,40,5)
    local pinned = f.actor("retreat-pinned", 40, 40, {forwardX=1,forwardY=0})
    f.registry[pinned.id] = pinned
    local crowbar = f.item("Base.Crowbar", "Weapon", {maxRange=1.5,minRange=0.3})
    pinned.inventory:AddItem(crowbar); pinned.primary = crowbar
    local close, side, far = f.zombie(41,40,{}), f.zombie(41,41,{}), f.zombie(42,40,{})
    local threats = {}
    for _, zed in ipairs({close,side,far}) do threats[#threats+1] = {
        actor=zed,x=zed:getX(),y=zed:getY(),z=0,visible=true,obstructed=false,
        distanceSq=U.distanceSq(pinned,zed),bearing="front",posture="upright"} end
    local snap = {threats=threats,allies={},escapeSquares={{square=first,danger=0}},
        immediateCount=3,closeImmediateCount=3,closeThreatCount=3,
        reachableImmediateCount=3,reachableCloseCount=3,reachableThreatSectors=1}
    local runtime = {senses={current=snap}}
    f.clock = f.clock + 1000
    check(SC.Combat.update(pinned,nil,runtime), "an escape can start with a pending native path")
    check(runtime.combatAction == "retreat", "the first pulse genuinely requests movement")
    f.clock = f.clock + 900
    check(SC.Combat.update(pinned,nil,runtime)
        and (runtime.combatAction=="last_stand_melee" or runtime.combatAction=="last_stand_shove"),
        "a stationary pending retreat defends even while a snapshot still lists an escape")
    SC.Combat.reset(pinned)
    f.clock = f.clock + 1000
    SC.Combat.update(pinned,nil,runtime)
    pinned.worldX = pinned:getX() - 0.5
    f.clock = f.clock + 900
    check(SC.Combat.update(pinned,nil,runtime) and runtime.combatAction=="retreat",
        "measured retreat movement continues instead of triggering a stationary fallback")

    local weapon = {item=crowbar,equipped=true,ranged=false,condition=10}
    local defended, _, actual = SC.Combat._executeLastStandForTests(pinned,nil,snap,threats[3],weapon)
    check(defended and actual and actual.actor == close and pinned.lastIntent.target == close,
        "blocked withdrawal defends against the nearest contact instead of a distant selected target")
    SC.Combat.reset(pinned)
    snap.escapeSquares = {}
    f.clock = f.clock + 1000
    check(SC.Combat.update(pinned,nil,runtime)
        and (runtime.combatAction=="last_stand_melee" or runtime.combatAction=="last_stand_shove"),
        "a surrounded actor with no observed exit defends immediately instead of making a blind escape step")
    SC.Combat.reset(pinned)
    local distant = f.zombie(45,40,{})
    SC.Commands.peek(pinned).combatDoctrine = "weapons_free"
    snap.threats = {{actor=distant,x=45,y=40,z=0,visible=true,obstructed=false,
        distanceSq=U.distanceSq(pinned,distant),bearing="front",posture="upright"}}
    snap.escapeSquares = {{square=first,danger=0}, {square=second,danger=0}}
    f.clock = f.clock + 1000
    local began, beganWhy = SC.Combat.update(pinned,nil,runtime)
    f.clock = f.clock + 900
    local continued, why = SC.Combat.update(pinned,nil,runtime)
    local retryProbe = SC.Combat.peek(pinned).cornerEscapeProbe
    check(continued and retryProbe and retryProbe.at == f.clock,
        "a replacement retreat receives its own progress interval when no contact is in reach"
        .. " first=" .. tostring(began) .. "/" .. tostring(beganWhy)
        .. " next=" .. tostring(continued) .. "/" .. tostring(why)
        .. " probe=" .. tostring(retryProbe and retryProbe.at) .. " now=" .. f.clock)
    SC.Combat.reset(pinned)
    navigation.request, navigation.retreatTarget = request, remembered
end
print("BEHAVIOUR_COMBAT_PASS checks=" .. tostring(f.checks()))
