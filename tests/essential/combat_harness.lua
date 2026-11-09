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
print("BEHAVIOUR_COMBAT_PASS checks=" .. tostring(f.checks()))
