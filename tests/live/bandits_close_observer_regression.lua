-- SPDX-License-Identifier: MIT
-- Observer safety only. Real native combat is verified separately in GL runs.
local Probe = SCRealSandboxHarnessProbes.SCBanditsCloseCombatAcceptance
local count = 0
local function expect(value, why)
    count = count + 1
    assert(value, "close observer " .. count .. ": " .. why)
end
local function actor()
    local a = { health = 100, bite = false, bump = "idle" }
    local part = { getHealth = function() return a.health end, bitten = function() return a.bite end }
    local parts = { size = function() return 1 end, get = function() return part end }
    a.getBodyDamage = function() return { getBodyParts = function() return parts end } end
    a.getBumpType = function() return a.bump end
    a.isKnockedDown = function() return false end
    a.getCurrentStateName = function() return a.bump end
    return a
end
local victim, main, enemy = actor(), actor(), {}
local status = { lastVictim = "lf:sc-observer", lastModel = "MeleeHit" }
SurvivorCompanion = {
    Call = { resolve = function(value, key)
        local method = value and value[key]
        return type(method) == "function", method
    end },
    BanditsAdapter = { status = function() return status end },
}
local calls = 0
local function smack(_, task)
    calls = calls + 1
    task.hit = true
    if task.bite then victim.bite = true else victim.health = victim.health - 7 end
    return "stock", nil, 9
end
local function push(_, task)
    calls = calls + 1
    task.hit, victim.bump = true, "stagger"
    return false, nil, 11
end
ZombieActions = { Smack = { onWorking = smack }, Push = { onWorking = push } }
local function fixture()
    victim.health, victim.bite, victim.bump, main.health = 100, false, "idle", 100
    return { actor = victim, id = "sc-observer", primary = { player = main }, bandits = { [enemy] = true },
        bindings = {}, incomingMelee = 0, incomingHand = 0, incomingPush = 0, incomingBites = 0 }
end
local f = fixture()
expect(Probe.observeActions(f), "native observer installs")
local a, b, c = ZombieActions.Smack.onWorking(enemy, { eid = "lf:sc-observer" })
expect(a == "stock" and b == nil and c == 9 and calls == 1, "original called once with exact sparse returns")
expect(f.incomingMelee == 1 and victim.health == 93 and not f.leaked, "exact-LF original wound observed")
ZombieActions.Smack.onWorking(enemy, { eid = 1 })
expect(f.incomingMelee == 1 and calls == 2, "another target cannot create LF evidence")
status.lastModel = "BareHandHit"
ZombieActions.Smack.onWorking(enemy, { eid = "lf:sc-observer" })
expect(f.incomingHand == 1 and f.incomingMelee == 1, "punch and weapon models stay distinct")
status.lastVictim = "lf:other"
ZombieActions.Smack.onWorking(enemy, { eid = "lf:sc-observer" })
expect(f.incomingHand == 1, "wrong-victim model receipt is rejected")
status.lastVictim = "lf:sc-observer"
ZombieActions.Smack.onWorking(enemy, { eid = "lf:sc-observer", bite = true })
expect(f.incomingBites == 1 and Probe.bites(victim) == 1, "new actual bitten part observed inside stock callback")
ZombieActions.Smack.onWorking(enemy, { eid = "lf:sc-observer", bite = true })
expect(f.incomingBites == 1, "an already bitten part is not a new bite")
local before = victim.health
a, b, c = ZombieActions.Push.onWorking(enemy, { eid = "lf:sc-observer" })
expect(a == false and b == nil and c == 11 and victim.health == before,
    "native shove return and no-damage effect preserved")
expect(f.incomingPush == 1 and not f.shoveDamage, "actual stagger proves a shove, not its task alone")
local retained = ZombieActions.Smack.onWorking
Probe.cleanup(f)
expect(ZombieActions.Smack.onWorking == smack and ZombieActions.Push.onWorking == push, "cleanup restores original hooks")
retained(enemy, { eid = "lf:sc-observer" })
expect(f.incomingHand == 1, "retained observer is inert after cleanup")

f = fixture()
ZombieActions.Smack.onWorking = function() calls = calls + 1 error("stock failed") end
expect(Probe.observeActions(f), "error fixture installs")
local beforeCalls = calls
local okay = pcall(ZombieActions.Smack.onWorking, enemy, { eid = "lf:sc-observer" })
expect(not okay and f.failure and calls == beforeCalls + 1, "native error propagates without replay")
expect(not f.observing and #f.bindings == 0, "native error closes all observer scopes")
ZombieActions.Smack.onWorking = smack

f = fixture()
ZombieActions.Push.onWorking = function(_, task) task.hit = true victim.bump = "stagger" victim.health = victim.health - 1 end
expect(Probe.observeActions(f), "damaging-push negative control installs")
ZombieActions.Push.onWorking(enemy, { eid = "lf:sc-observer" })
expect(f.shoveDamage == true, "unexpected shove health loss is recorded, not passed")
Probe.cleanup(f)
ZombieActions.Push.onWorking = push

f = fixture()
ZombieActions.Smack.onWorking = function(_, task) task.hit = true main.health = main.health - 1 end
expect(Probe.observeActions(f), "wrong-main-victim negative control installs")
ZombieActions.Smack.onWorking(enemy, { eid = "lf:sc-observer" })
expect(f.leaked == true and f.incomingMelee == 0, "main-player leakage cannot satisfy an LF wound")
Probe.cleanup(f)
ZombieActions.Smack.onWorking = smack

f = fixture()
expect(Probe.observeActions(f), "foreign outer wrapper fixture installs")
local inner = ZombieActions.Smack.onWorking
local outer = function(...) return inner(...) end
ZombieActions.Smack.onWorking = outer
Probe.cleanup(f)
expect(ZombieActions.Smack.onWorking == outer, "cleanup preserves another mod's current binding")
outer(enemy, { eid = "lf:sc-observer" })
expect(f.incomingMelee == 0, "a retained inner observer cannot collect post-teardown evidence")

local ordinary, runtime = {}, {}
local snapshot = { threats = { { actor = ordinary } }, humanThreat = { actor = enemy } }
local observedRuntime
local classification = {
    Registry = { byId = function(id)
        expect(id == "sc-observer", "classification reads the exact LF registry record")
        return { runtime = runtime }
    end },
    Senses = { cached = function(value, supplied)
        observedRuntime = supplied
        return supplied == runtime and snapshot or nil
    end },
    GameplayUtil = { isZombie = function() return false end },
}
f = fixture()
f.ordinary = ordinary
Probe.inspectClassification(f, classification)
expect(observedRuntime == runtime and f.ordinarySeen and f.humanSeen and not f.zombieLeak,
    "classification observes the production registry runtime and both actual threat lanes")
snapshot = { threats = { { actor = enemy } } }
Probe.inspectClassification(f, classification)
expect(f.zombieLeak == true, "a Bandit in the undead snapshot fails classification")
f = fixture()
snapshot = {}
classification.ZombieFacts = { get = function() return { zombie = false } end }
Probe.inspectClassification(f, classification)
expect(f.nativeFactsChecked and not f.zombieLeak, "native snapshot consumer excludes the actual Bandit")
classification.ZombieFacts.get = function() return { zombie = true } end
Probe.inspectClassification(f, classification)
expect(not f.nativeFactsChecked and f.zombieLeak, "native-snapshot leakage cannot satisfy infected acceptance")
f = fixture()
f.retired = { [enemy] = true }
snapshot = { threats = { { actor = enemy } } }
classification.GameplayUtil.isZombie = function() return true end
Probe.inspectClassification(f, classification)
expect(not f.zombieLeak and not f.humanSeen,
    "a retired Bandit's pooled ordinary-zombie shell is no longer the encounter's Bandit")
print("BANDITS_CLOSE_OBSERVER_PASS checks=" .. count)
