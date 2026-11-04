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
print("BEHAVIOUR_COMBAT_PASS checks=" .. tostring(f.checks()))
