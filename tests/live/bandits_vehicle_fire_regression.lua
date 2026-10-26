-- SPDX-License-Identifier: MIT
local Probe = SCRealSandboxHarnessProbes.SCBanditsVehicleFireEvidence
local checks, item = 0, {}
local function expect(value, why)
    checks = checks + 1
    assert(value, "vehicle bullet " .. checks .. ": " .. why)
end
local function state(condition, health, requests, nativeItem)
    return { parts = { WindowFrontRight = { condition = condition, item = nativeItem or item } }, health = health, requests = requests }
end
local f = { vehicleBlocks = 0 }
Probe.observe(f, state(100, 1700, 0), state(80, 1700, 0), false)
expect(f.vehicleBlocks == 1, "a stopped native ray with surviving part damage and no wound/request proves car protection")
Probe.observe(f, state(100, 1700, 0), state(100, 1700, 0), false)
expect(f.vehicleBlocks == 1, "a miss or animation without actual part damage cannot prove vehicle protection")
Probe.observe(f, state(20, 1700, 0), state(0, 1700, 0), false)
expect(f.vehicleBlocks == 1, "a destroyed part cannot prove surviving-part bullet protection")
Probe.observe(f, state(100, 1700, 0), state(80, 1700, 1), false)
expect(f.vehicleBlocks == 1, "a routed armor deflection cannot be mislabeled a car block")
Probe.observe(f, state(100, 1700, 0), state(80, 1680, 1), false)
expect(f.vehicleBlocks == 1, "a native wound cannot satisfy the no-wound block predicate")
Probe.observe(f, state(100, 1700, 0), state(80, 1700, 0), true)
expect(f.vehicleBlocks == 1, "a ray that continues cannot prove its bullet stopped in the car")
Probe.observe(f, state(100, 1700, 0), state(80, 1700, 0, {}), false)
expect(f.vehicleBlocks == 1, "replacement parts/items cannot create a damage receipt")
Probe.observe(f, { health = 1700, requests = 0 }, state(80, 1700, 0), false)
expect(f.failure ~= nil, "unavailable native parts fail rather than supplying empty proof")
f = {}
Probe.observe(f, state(100, nil, 0), state(80, nil, 0), false)
expect(f.failure and not f.vehicleBlocks, "missing LF health never substitutes for verified unchanged health")
f = {}
Probe.observe(f, state(100, 1700, nil), state(80, 1700, nil), false)
expect(f.failure and not f.vehicleBlocks, "missing damage receipt counters fail instead of supplying equality proof")
f = {}
Probe.observe(f, state(100, math.huge, 0), state(80, math.huge, 0), false)
expect(f.failure and not f.vehicleBlocks, "non-finite health cannot prove a native block")
local function exposedTrial(exposed, victim, model, health, requests)
    local before, after = state(100, 1700, 0), state(100, health, requests)
    before.exposed, after.lastVictim, after.lastModel = exposed, victim, model
    local fixture = { id = "sc-exposed" }
    Probe.observe(fixture, before, after, true)
    return fixture.exposedBulletWounds or 0
end
expect(exposedTrial(true, "lf:sc-exposed", "BulletHit", 1680, 1) == 1,
    "a fresh exact-victim native wound at the actual exposed position proves the transition")
expect(exposedTrial(false, "lf:sc-exposed", "BulletHit", 1680, 1) == 0,
    "a requested destination alone cannot prove the actor left car cover")
expect(exposedTrial(true, "lf:other", "BulletHit", 1680, 1) == 0,
    "another victim cannot supply the exposed wound")
expect(exposedTrial(true, "lf:sc-exposed", "MeleeHit", 1680, 1) == 0,
    "a fresh melee wound cannot supply the exposed gunshot")
expect(exposedTrial(true, "lf:sc-exposed", "BulletHit", 1700, 1) == 0,
    "an armor deflection cannot prove an exposed wound")
expect(exposedTrial(true, "lf:sc-exposed", "BulletHit", 1680, 0) == 0,
    "health loss without a fresh bullet receipt cannot prove the transition")
local condition, calls = 100, 0
local part = { getId = function() return "WindowFrontRight" end,
    getInventoryItem = function() return item end, getCondition = function() return condition end }
local car = { getPartCount = function() return 1 end, getPartByIndex = function() return part end }
local bodyPart = { getHealth = function() return 100 end }
local actor = { getBodyDamage = function() return { getBodyParts = function()
    return { size = function() return 1 end, get = function() return bodyPart end }
end } end }
local shooter = {}
SurvivorCompanion = { Call = { resolve = function(value, key)
    local method = value and value[key]
    return type(method) == "function", method
end }, BanditsAdapter = { status = function() return { bulletHits = 0 } end } }
local function original()
    calls, condition = calls + 1, condition - 20
    return false, nil, 7
end
BanditUtils = { ManageLineOfFire = original }
f = { car = car, actor = actor, bandits = { [shooter] = true } }
expect(Probe.install(f), "read-only native ray observer installs")
local a, b, c = BanditUtils.ManageLineOfFire(shooter, actor)
expect(a == false and b == nil and c == 7 and calls == 1 and f.vehicleBlocks == 1,
    "original executes once with sparse returns and actual part snapshot retained")
BanditUtils.ManageLineOfFire({}, actor)
expect(calls == 2 and f.vehicleBlocks == 1, "another shooter delegates without adding evidence")
local retained = BanditUtils.ManageLineOfFire
local outer = function(...) return retained(...) end
BanditUtils.ManageLineOfFire = outer
Probe.cleanup(f)
expect(BanditUtils.ManageLineOfFire == outer, "cleanup preserves a foreign current wrapper")
outer(shooter, actor)
expect(calls == 3 and f.vehicleBlocks == 1, "retained observer becomes inert after cleanup")
BanditUtils.ManageLineOfFire = function() calls = calls + 1 error("native ray failed") end
local throwing = BanditUtils.ManageLineOfFire
expect(Probe.install(f), "native error fixture installs")
local before = calls
local okay = pcall(BanditUtils.ManageLineOfFire, shooter, actor)
expect(not okay and calls == before + 1 and f.failure and not f.fireObserving
    and BanditUtils.ManageLineOfFire == throwing, "native error propagates once and closes its own scope")
car.getPartCount = function() return 513 end
expect(Probe.parts(car) == nil, "unbounded native part snapshots are refused")
SC_TEST_REPORT = "BANDITS_VEHICLE_FIRE_PASS checks=" .. checks
