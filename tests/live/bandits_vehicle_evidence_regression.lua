-- SPDX-License-Identifier: MIT
local Probe = SCRealSandboxHarnessProbes.SCBanditsVehicleAcceptance
local checks = 0
local function expect(value, why)
    checks = checks + 1
    assert(value, "vehicle evidence " .. checks .. ": " .. why)
end
local status = { lastVictim = "lf:sc-window", lastModel = "MeleeHit" }
SurvivorCompanion = { BanditsAdapter = { status = function() return status end } }
local function fixture()
    return { id = "sc-window", stage = "test", closedProtected = 0, openWound = 0, brokenWound = 0 }
end
local function state(condition, open, hits)
    return { condition = condition, intact = condition > 0, open = open == true, meleeHits = hits or 0 }
end
local task = { eid = "lf:sc-window", hit = true }
local f = fixture()
Probe.observe(f, "Smack", task, false, state(100), state(56), 1700, 1700)
expect(f.closedProtected == 1 and f.openWound == 0, "damaged intact glass with no wound proves a protected melee impact")
Probe.observe(f, "Smack", task, false, state(56, true, 0), state(56, true, 1), 1700, 1680)
expect(f.openWound == 1, "exact native wound through open intact glass is observed")
Probe.observe(f, "Smack", task, false, state(12, false, 1), state(0, false, 2), 1680, 1660)
expect(f.brokenWound == 1, "native shattering impact can expose the victim in the same callback")
Probe.observe(f, "Smack", task, false, state(0, false, 2), state(0, false, 3), 1660, 1640)
expect(f.brokenWound == 2, "an already broken window allows native wounds")
f = fixture()
Probe.observe(f, "Smack", task, false, state(100), state(100), 1700, 1700)
expect(f.closedProtected == 0, "an animation alone proves no blocked impact")
Probe.observe(f, "Smack", task, true, state(100), state(56), 1700, 1700)
expect(f.closedProtected == 0, "a repeated task hit cannot add evidence")
Probe.observe(f, "Push", task, false, state(100), state(56), 1700, 1700)
expect(f.closedProtected == 0, "shoves cannot prove window protection")
Probe.observe(f, "Smack", { eid = 1, hit = true }, false, state(100), state(56), 1700, 1700)
expect(f.closedProtected == 0, "another victim cannot satisfy this scene")
Probe.observe(f, "Smack", task, false, state(56, true, 1), state(56, true, 1), 1700, 1680)
expect(f.openWound == 0, "stale model receipts cannot prove an open-window wound")
status.lastVictim = "lf:other"
Probe.observe(f, "Smack", task, false, state(56, true, 1), state(56, true, 2), 1700, 1680)
expect(f.openWound == 0, "a fresh wrong-victim receipt cannot prove the wound")
status.lastVictim, status.lastModel = "lf:sc-window", "BulletHit"
Probe.observe(f, "Smack", task, false, state(56, true, 1), state(56, true, 2), 1700, 1680)
expect(f.openWound == 0, "another native model cannot prove a melee wound")
status.lastModel = "MeleeHit"
Probe.observe(f, "Smack", task, false, state(100, false, 1), state(56, false, 2), 1700, 1680)
expect(f.closedProtected == 0 and f.openWound == 0 and f.brokenWound == 0,
    "a wound behind still-intact closed glass must never count as protection")
expect(f.failure ~= nil, "a native wound through intact closed glass fails the whole scene")
Probe.observe(f, "Smack", task, false, state(56, true, 2), state(56, true, 3), 1700, 1700)
expect(f.openWound == 0, "routing without an actual wound is insufficient")
local vehicleX, vehicleY, loaded = nil, nil, true
getCell = function() return { getGridSquare = function(_, x, y)
    if not loaded then return nil end
    return { getVehicleContainer = function() return x == vehicleX and y == vehicleY and {} or nil end }
end } end
SurvivorCompanion.Call = { resolve = function(value, key)
    local method = value and value[key]
    return type(method) == "function", method
end }
local shooter = { getX = function() return 0 end, getY = function() return 0 end }
local target = { getX = function() return 8 end, getY = function() return 0 end, getZ = function() return 0 end }
expect(Probe.carFreeRay(shooter, target), "a loaded vehicle-free stock ray permits an exposure destination")
vehicleX, vehicleY = 4, 0
expect(not Probe.carFreeRay(shooter, target), "an intervening car keeps the destination behind cover")
vehicleX, vehicleY = 7, 2
expect(not Probe.carFreeRay(shooter, target), "Bandits' final two-tile neighborhood must also be free of cars")
vehicleX, vehicleY, loaded = nil, nil, false
expect(not Probe.carFreeRay(shooter, target), "unloaded ray cells cannot supply exposure proof")
loaded = true
local movingTarget = { getX = function() return 8.35 end, getY = function() return 0.65 end, getZ = function() return 0 end }
expect(Probe.carFreeRay(shooter, movingTarget), "an actual moving actor's fractional coordinates use the stock floor-tile ray")
vehicleX, vehicleY = 10, 2
expect(not Probe.carFreeRay(shooter, movingTarget), "fractional target positions still inspect the actual final vehicle neighborhood")
local walker = { getX = function() return 0 end, getY = function() return 7 end }
local function destination(x, y)
    return { getX = function() return x - 0.5 end, getY = function() return y - 0.5 end }
end
expect(Probe.keepsGunRange(walker, shooter, destination(6, 7)), "a lateral normal foot route can retain native gun range")
expect(not Probe.keepsGunRange(walker, shooter, destination(0, -7)),
    "a far endpoint cannot hide a route that cuts through the shooter's melee envelope")
expect(not Probe.keepsGunRange(walker, shooter, destination(0, 4)), "a close destination is refused")
expect(not Probe.keepsGunRange(walker, shooter, destination(0, 7)), "a stationary destination cannot prove a new exposure route")
local function unloadTrial(worn, wrongWorld)
    local held, world = true, nil
    local item = { getID = function() return 123 end, getFullType = function() return "Base.Log" end,
        getWorldItem = function() return world end }
    local inventory = { getCapacityWeight = function() return held and 50 or 0 end,
        getItems = function() return { size = function() return held and 1 or 0 end, get = function() return item end } end,
        Remove = function(_, value) assert(value == item and held) held = false end }
    local player = { getInventory = function() return inventory end, getMaxWeight = function() return 12 end,
        isEquippedClothing = function() return worn end, isEquipped = function() return false end }
    local square = { AddWorldInventoryItem = function(_, value)
        world = { getItem = function() return wrongWorld and {} or value end }
        return value -- Native API returns the item, not its world wrapper.
    end }
    return Probe.unloadObserver(player, square), held, item:getID()
end
local unloaded, held, id = unloadTrial(false, false)
expect(unloaded and not held and id == 123, "observer setup drops the exact real item without changing carry limits or item identity")
expect(not unloadTrial(true, false), "worn equipment is retained even when its load prevents scene preparation")
expect(not unloadTrial(false, true), "an unverified world item cannot be recreated or credited as safely unloaded")
SC_TEST_REPORT = "BANDITS_VEHICLE_EVIDENCE_PASS checks=" .. checks
