-- SPDX-License-Identifier: MIT
-- Verify the native-shot recorder rejects coincident/stale wounds.
local Probe = SCRealSandboxHarnessProbes.SCBanditsCombatAcceptance
local checks, calls, health = 0, 0, 1700
local function expect(value, why)
    checks = checks + 1
    assert(value, "firearm observer " .. checks .. ": " .. why)
end
local victim, enemy, status = {}, {}, {}
local parts = { size = function() return 1 end, get = function()
    return { getHealth = function() return health end }
end }
victim.getBodyDamage = function() return { getBodyParts = function() return parts end } end
SurvivorCompanion = {
    Call = { resolve = function(value, key)
        local callback = value and value[key]
        return type(callback) == "function", callback
    end },
    BanditsAdapter = { status = function() return status end },
}
local effect
local function original(_, _, argument)
    calls = calls + 1
    if effect then effect() end
    return argument, nil, 9
end
ZombieActions = { Shoot = { onComplete = original } }
local function fixture()
    health = 1700
    status = { bulletHits = 0, lastVictim = "lf:sc-firearm", lastModel = "BulletHit" }
    local f = { actor = victim, id = "sc-firearm", bandits = { [enemy] = true } }
    assert(Probe.observeFirearms(f))
    return f
end
local function wound()
    health = health - 7
    status.bulletHits = status.bulletHits + 1
end
local f = fixture()
effect = wound
local before = calls
local a, b, c = ZombieActions.Shoot.onComplete(enemy, { eid = "lf:sc-firearm" }, "native")
expect(a == "native" and b == nil and c == 9 and calls == before + 1,
    "native callback called once with exact arguments and sparse returns")
expect(f.nativeBulletWounds == 1 and f.incoming == true, "exact victim has a scoped native bullet wound")
local retained = ZombieActions.Shoot.onComplete
Probe.cleanup(f)
expect(ZombieActions.Shoot.onComplete == original, "cleanup restores original callback")
retained(enemy, { eid = "lf:sc-firearm" })
expect(f.nativeBulletWounds == 1, "retained observer cannot record after teardown")

local cases = {
    { "wrong victim", function() wound() status.lastVictim = "lf:other" end },
    { "wrong model", function() wound() status.lastModel = "MeleeHit" end },
    { "stale request count", function() health = health - 7 end },
    { "blocked damage", function() status.bulletHits = status.bulletHits + 1 end },
}
for _, case in ipairs(cases) do
    f = fixture()
    effect = case[2]
    ZombieActions.Shoot.onComplete(enemy, { eid = "lf:sc-firearm" })
    expect(f.nativeBulletWounds == 0 and not f.incoming, case[1] .. " cannot satisfy bullet-wound evidence")
    Probe.cleanup(f)
end
f = fixture()
effect = wound
ZombieActions.Shoot.onComplete(enemy, { eid = 1 })
expect(f.nativeBulletWounds == 0, "another task target cannot satisfy exact-LF evidence")
ZombieActions.Shoot.onComplete({}, { eid = "lf:sc-firearm" })
expect(f.nativeBulletWounds == 0, "an untracked shooter cannot satisfy the encounter")
f.retired = { [enemy] = true }
ZombieActions.Shoot.onComplete(enemy, { eid = "lf:sc-firearm" })
expect(f.nativeBulletWounds == 0, "a retired or reused shooter cannot satisfy the original encounter")
Probe.cleanup(f)

f = fixture()
effect = function() error("native shoot failed") end
before = calls
local okay = pcall(ZombieActions.Shoot.onComplete, enemy, { eid = "lf:sc-firearm" })
expect(not okay and calls == before + 1 and f.failure, "native error propagates without replay")
expect(not f.observing and ZombieActions.Shoot.onComplete == original, "native error tears down the recorder")

f = fixture()
effect = wound
local inner = ZombieActions.Shoot.onComplete
local outer = function(...) return inner(...) end
ZombieActions.Shoot.onComplete = outer
Probe.cleanup(f)
outer(enemy, { eid = "lf:sc-firearm" })
expect(ZombieActions.Shoot.onComplete == outer and f.nativeBulletWounds == 0,
    "cleanup preserves a foreign outer wrapper while retiring its inner observer")
print("BANDITS_FIREARM_OBSERVER_PASS checks=" .. checks)
