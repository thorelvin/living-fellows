-- SPDX-License-Identifier: MIT
-- Adversarial traces exercise the acceptance verdict, not simulated combat.
local Probe = SCRealSandboxHarnessProbes.SCBanditsCombatAcceptance
local checks = 0
local function expect(value, why)
    checks = checks + 1
    assert(value, "Bandits combat evidence " .. checks .. ": " .. why)
end
local main = {}
local slots = { size = function() return 4 end, get = function(_, index) if index == 0 then return main end end }
IsoPlayer = { numPlayers = 1, getPlayers = function() return slots end }
getSpecificPlayer = function() return main end
BanditUtils = { GetCharacterID = function() return 1 end }
Events = { OnHitZombie = { Remove = function() end } }
getCore = function() return { TakeFullScreenshot = function() end } end
local function trial(change)
    local previousUtils, previousBrain, previousBandit = BanditUtils, BanditBrain, Bandit
    local hp, ammo, enemyAmmo, task, dead = 1600, 14, 9, "Shoot", false
    local status = { bulletHits = 1, lastVictim = "lf:sc-evidence", lastModel = "BulletHit" }
    local parts = { size = function() return 1 end,
        get = function() return { getHealth = function() return hp end } end }
    local actor = { getBodyDamage = function() return { getBodyParts = function() return parts end } end,
        isDead = function() return false end }
    local enemy = { getHealth = function() return 0.8 end, isDead = function() return dead end,
        getID = function() return 7 end }
    actor.getCompanionAttackCollisionSerial = function() return 1 end
    actor.getCompanionAttackCollisionTarget = function() return enemy end
    actor.didCompanionAttackCollisionHitTarget = function() return true end
    local f = { stage = "combat", actor = actor, id = "sc-evidence", bandits = { [enemy] = true },
        gun = { getCurrentAmmoCount = function() return ammo end }, lastAmmo = 15, lfRounds = 0,
        rounds = { [enemy] = 10 }, lastTasks = { [enemy] = "Shoot" }, banditShots = 0,
        targetIDs = { [enemy] = 7 }, retired = {},
        deadTargets = {}, hitTargets = { [enemy] = true },
        impactClaims = { [1] = { [enemy] = true } },
        banditHealth = { [enemy] = 1 }, healthBefore = 1700, statusBefore = { bulletHits = 0 },
        outgoing = 1, nativeBulletWounds = 1, combatAt = 0, nextTrace = math.huge,
        primary = { player = main, slots = { main }, size = 4, count = 1 } }
    local H = { banditsAcceptance = f, config = { run_id = "evidence-only", bandits_combat_scenario = "firearms" } }
    SurvivorCompanion = {
        Call = { resolve = function(value, key)
            local method = value and value[key]
            return type(method) == "function", method
        end },
        BanditsAdapter = { status = function() return status end },
    }
    BanditBrain = { Get = function() return { weapons = { secondary = { bulletsLeft = enemyAmmo } } } end }
    Bandit = { GetTask = function() return { action = task } end }
    local context = { f = f, H = H, status = status,
        setHealth = function(value) hp = value end,
        setAmmo = function(value) ammo = value end,
        setTask = function(value) task = value end,
        setDead = function(value) dead = value end }
    context.actor = actor
    if change then change(context) end
    local verdict, detail
    local okay, err = pcall(Probe.step, H, 180001,
        function(_, value) return value == true end,
        function(value, _, message) verdict, detail = value, message end,
        function() end)
    BanditUtils, BanditBrain, Bandit = previousUtils, previousBrain, previousBandit
    IsoPlayer.numPlayers = 1
    slots.get = function(_, index) if index == 0 then return main end end
    return okay and verdict == "PASS", okay, detail or err
end
expect(trial(), "matching native event, ammo and exact-victim wound can pass")
expect(not trial(function(c) c.f.outgoing = 0 end), "spent rounds and incoming wounds cannot prove outgoing hits")
expect(not trial(function(c) c.status.lastVictim = "lf:sc-other" end), "another victim cannot satisfy incoming evidence")
expect(not trial(function(c) c.status.lastModel = "MeleeHit" end), "stale bullet count cannot turn a melee wound into firearms evidence")
expect(not trial(function(c) c.setHealth(1700) end), "a routed request without actual health loss is insufficient")
expect(not trial(function(c) c.f.nativeBulletWounds = 0 end),
    "health loss outside the exact native Shoot callback cannot prove a bullet wound")
expect(not trial(function(c) c.f.impactClaims = {} end),
    "another LF's damage cannot prove this shooter's native impact")
expect(not trial(function(c) c.actor.didCompanionAttackCollisionHitTarget = function() return false end end),
    "a candidate or shove receipt cannot prove native target damage")
expect(not trial(function(c) c.actor.getCompanionAttackCollisionTarget = function() return {} end end),
    "a native impact on another object cannot prove the tracked hit")
expect(not trial(function(c) c.f.impactClaims = { [2] = c.f.impactClaims[1] } end),
    "a failed impact's future claim cannot satisfy a later serial")
expect(not trial(function(c) c.setAmmo(15) end), "outgoing hit requires consumed LF ammunition")
expect(not trial(function(c) c.setTask("Smack") c.f.lastTasks = {} end), "ammo changes outside native Shoot tasks cannot prove firing")
expect(not trial(function(c) c.setDead(true) end), "a dead actor's disappearing ammo cannot count as a shot")
expect(not trial(function() IsoPlayer.numPlayers = 2 end), "native player count changes fail the whole verdict")
expect(not trial(function()
    slots.get = function(_, index) if index == 0 then return main elseif index == 1 then return {} end end
end), "mutations of the same native player array are detected against a value snapshot")
expect(trial(function(c)
    c.H.config.bandits_combat_scenario = "firearms_zombie_control"
    c.status.bulletHits = 0
end), "ordinary-zombie control has an explicit directional label and predicate")
local passed, okay = trial(function(c) c.f.statusBefore = nil end)
expect(not passed and not okay, "missing baseline fails instead of fabricating evidence")
expect(trial(function(c)
    c.H.config.companion_firearms_probe = "true"
    c.H.config.bandits_combat_scenario = "firearms_zombie_control"
    c.status.bulletHits = 0
    BanditUtils, BanditBrain, Bandit = nil, nil, nil
end), "ordinary LF verdict runs without any Bandits interfaces")
expect(not trial(function(c)
    c.H.config.companion_firearms_probe = "true"
    c.H.config.bandits_combat_scenario = "firearms_zombie_control"
    c.f.outgoing = 0
    BanditUtils, BanditBrain, Bandit = nil, nil, nil
end), "ordinary LF consumed ammo alone does not pass")
print("BANDITS_COMBAT_EVIDENCE_PASS checks=" .. checks)
