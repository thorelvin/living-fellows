-- SPDX-License-Identifier: MIT
-- Horde awareness: a horde in sight is not a horde in the fight.
--
-- Playtest report: a companion sees a crowd at a distance while only one or two
-- zombies are actually closing, and it retreats or kites instead of taking a
-- safe swing. The cause is arithmetic, not nerve. `snapshot.pressure` mixes
-- local danger with ambient sightings at 0.35 apiece, and retreat utility
-- multiplies the whole thing by 16 -- so twenty idle zombies on the far side of
-- a field move retreat by +112 and melee by -21 without a single fact about the
-- fight in front of the companion having changed.
--
-- These cases hold every local fact constant and vary only the distant count.
local SC, checks = SurvivorCompanion, 0
local U = SC.GameplayUtil
local function check(value, message)
    checks = checks + 1
    assert(value, "combat coordination regression " .. checks .. ": " .. message)
end

local squares = {}
local function square(x, y, z)
    z = z or 0
    local key = tostring(x) .. ":" .. tostring(y) .. ":" .. tostring(z)
    if squares[key] then return squares[key] end
    local value = { x = x, y = y, z = z, objects = {}, moving = {} }
    function value:getX() return self.x end
    function value:getY() return self.y end
    function value:getZ() return self.z end
    function value:getObjects() return self.objects end
    function value:getSpecialObjects() return self.objects end
    function value:getMovingObjects() return self.moving end
    function value:isFree() return true end
    function value:isSolid() return false end
    function value:isSolidTrans() return false end
    function value:TreatAsSolidFloor() return true end
    squares[key] = value
    return value
end
local cell = { getGridSquare = function(_, x, y, z) return square(x, y, z) end }
function getCell() return cell end

local function body(health)
    local value = { health = health or 100, parts = {} }
    function value:getHealth() return self.health end
    function value:getBodyParts() return self.parts end
    function value:IsInfected() return false end
    function value:getApparentInfectionLevel() return 0 end
    return value
end

local function character(id, x, y, class)
    local value = { __class = class or "IsoPlayer", x = x, y = y, data = {},
        damage = body(100) }
    function value:getX() return self.x end
    function value:getY() return self.y end
    function value:getZ() return 0 end
    function value:getSquare() return square(math.floor(self.x), math.floor(self.y)) end
    function value:getCurrentSquare() return self:getSquare() end
    function value:getModData() return self.data end
    function value:isDead() return false end
    function value:isOnFloor() return false end
    function value:isProne() return false end
    function value:getBodyDamage() return self.damage end
    function value:getHealth() return self.damage.health end
    value.data.SC_Id = id
    return value
end

local weaponItem = { }
function weaponItem:getFullType() return "Base.Axe" end
function weaponItem:getType() return "Axe" end
function weaponItem:getCondition() return 10 end
function weaponItem:getConditionMax() return 10 end
function weaponItem:getCategory() return "Weapon" end
function weaponItem:getMaxDamage() return 2.0 end
function weaponItem:getMaxRange() return 1.5 end
function weaponItem:getMinRange() return 0.3 end

local fighter = character("sc-horde-fighter", 10.5, 10.5)
local player = character("sc-horde-player", 11.5, 10.5)
local weapon = { item = weaponItem, ranged = false, damage = 2.0, range = 1.5,
    minRange = 0.3, condition = 10, conditionRatio = 1,
    sharpness = 1, staminaCost = 1, weight = 1.5 }

local woundedZombie = character("z-wounded-priority", 12, 10.5, "IsoZombie")
woundedZombie.damage.health = 2
local woundedScore = SC.Combat._woundedTargetScoreForTests
check(woundedScore(woundedZombie, 2.25, 1000) == 0,
    "a fresh zombie gets no finish preference")
woundedZombie.damage.health = 0.5
check(woundedScore(woundedZombie, 2.25, 1600) > 20,
    "a badly wounded nearby zombie gets a bounded finish preference")
check(woundedScore(woundedZombie, 25, 1600) == 0,
    "a wounded distant zombie does not pull the fighter into danger")
woundedZombie.damage.health = 2
check(woundedScore(woundedZombie, 2.25, 2200) == 0,
    "a recovered health reading clears the finish preference")

local earlyZombie = character("z-early-swing", 12.3, 10.5, "IsoZombie")
local earlyThreat = { actor = earlyZombie, visible = true,
    obstructed = false, attacking = false, bearing = "front", closingSpeed = 1.0 }
local earlySnapshot = { allies = {}, threats = { earlyThreat },
    reachableImmediateCount = 1, reachableThreatSectors = 1,
    encircled = false }
local earlyReady = { health = 100, staminaCritical = false }
check(SC.Combat.anticipatoryMeleeWindow(fighter, nil, earlySnapshot,
    earlyThreat, weapon, earlyReady) ~= nil,
    "a closing frontal zombie permits a narrow swing before contact")
earlyZombie.x = 12.8
local earlyLead, earlyWait = SC.Combat.anticipatoryMeleeWindow(fighter,
    nil, earlySnapshot, earlyThreat, weapon, earlyReady, true)
check(earlyLead == nil and earlyWait == true,
    "the fighter faces a closing zombie instead of walking into its reach")
earlyZombie.x = 12.3
earlyThreat.closingSpeed = 0
check(SC.Combat.anticipatoryMeleeWindow(fighter, nil, earlySnapshot,
    earlyThreat, weapon, earlyReady) == nil,
    "a stationary zombie does not invite an out-of-range swing")
earlyThreat.closingSpeed = 1.0
earlyReady.health = 55
check(SC.Combat.anticipatoryMeleeWindow(fighter, nil, earlySnapshot,
    earlyThreat, weapon, earlyReady) == nil,
    "an injured fighter withdraws instead of starting an early swing")
earlyReady.health = 100
earlySnapshot.reachableImmediateCount = 2
check(SC.Combat.anticipatoryMeleeWindow(fighter, nil, earlySnapshot,
    earlyThreat, weapon, earlyReady) == nil,
    "an unverified second immediate zombie rules out the anticipatory swing")
local pairZombie = character("z-frontal-pair", 12.45, 10.5, "IsoZombie")
earlySnapshot.threats[2] = { actor = pairZombie, visible = true,
    obstructed = false, attacking = false }
earlySnapshot.reachableThreatSectors = 1
earlySnapshot.escapeSquares = { { square = square(9, 10), danger = 0 } }
check(SC.Combat.anticipatoryMeleeWindow(fighter, nil, earlySnapshot,
    earlyThreat, weapon, earlyReady) ~= nil,
    "two closing frontal zombies outside weapon reach permit a guarded early swing")
earlySnapshot.threats[3] = { actor = character("z-third-visible", 18, 10.5,
    "IsoZombie"), visible = true, obstructed = false }
check(SC.Combat.anticipatoryMeleeWindow(fighter, nil, earlySnapshot,
    earlyThreat, weapon, earlyReady) ~= nil,
    "a distant visible zombie does not suppress a safe local pair swing")
earlySnapshot.squadPlan = { mode = "give_ground" }
local pairActions = SC.Combat._actionUtilitiesForTests(fighter, nil,
    earlySnapshot, earlyThreat, weapon, nil,
    { combatDoctrine = "close_defense", morale = 70 })
local pairSwingOffered = false
for _, action in ipairs(pairActions or {}) do
    if action.kind == "melee" and action.anticipatorySwing == true then
        pairSwingOffered = true
    end
end
check(pairSwingOffered,
    "giving ground still offers an early swing against the local frontal pair")
earlySnapshot.squadPlan = nil
local thirdZombie = character("z-third-close", 13.1, 10.5, "IsoZombie")
earlySnapshot.threats[3] = { actor = thirdZombie, visible = true,
    obstructed = false, attacking = false }
earlyReady.close = 3
check(SC.Combat.anticipatoryMeleeWindow(fighter, nil, earlySnapshot,
    earlyThreat, weapon, earlyReady) ~= nil,
    "a third zombie outside the weapon's danger envelope does not suppress a safe swing")
thirdZombie.x = 12.55
earlySnapshot.reachableImmediateCount = 3
check(SC.Combat.anticipatoryMeleeWindow(fighter, nil, earlySnapshot,
    earlyThreat, weapon, earlyReady) == nil,
    "three immediate zombies still require withdrawal")
earlySnapshot.reachableImmediateCount = 2
earlySnapshot.threats[3] = nil
earlyReady.close = nil
pairZombie.x = 11.9
check(SC.Combat.anticipatoryMeleeWindow(fighter, nil, earlySnapshot,
    earlyThreat, weapon, earlyReady) == nil,
    "a second zombie already inside weapon reach cancels the early swing")
pairZombie.x, pairZombie.y = 10.7, 12.3
check(SC.Combat.anticipatoryMeleeWindow(fighter, nil, earlySnapshot,
    earlyThreat, weapon, earlyReady) == nil,
    "a flanking second zombie cancels the early swing")
pairZombie.x, pairZombie.y = 12.45, 10.5
earlySnapshot.escapeSquares = {}
check(SC.Combat.anticipatoryMeleeWindow(fighter, nil, earlySnapshot,
    earlyThreat, weapon, earlyReady) == nil,
    "without an escape lane the pair cannot be swung into safely")
earlySnapshot.threats[2] = nil
earlySnapshot.reachableImmediateCount = 1
local rearZombie = character("z-behind-early-swing", 9.5, 10.5, "IsoZombie")
earlySnapshot.threats[2] = { actor = rearZombie, visible = true,
    obstructed = false }
check(SC.Combat.anticipatoryMeleeWindow(fighter, nil, earlySnapshot,
    earlyThreat, weapon, earlyReady) == nil,
    "a nearby zombie behind the fighter cancels the early swing")
earlySnapshot.threats[2] = nil
local function rangedFixture(fullType, maximum, minimum)
    local item = setmetatable({}, { __index = weaponItem })
    function item:getFullType() return fullType end
    function item:getType() return string.match(fullType, "%.(.+)$") end
    function item:getMaxRange() return maximum end
    function item:getMinRange() return minimum end
    return item, { item = item, ranged = false, condition = 10,
        equipped = true, minRange = minimum }
end
local penItem, penWeapon = rangedFixture("Base.Pen", 0.8, 0.61)
local crowbarItem, crowbarWeapon = rangedFixture("Base.Crowbar", 1.25, 0.61)
local shovelItem, shovelWeapon = rangedFixture("Base.Shovel", 1.6, 0.61)
local _, penMax = SC.Combat.meleeRange(fighter, penItem)
local _, crowbarMax = SC.Combat.meleeRange(fighter, crowbarItem)
local _, shovelMax = SC.Combat.meleeRange(fighter, shovelItem)
check(penMax < crowbarMax and crowbarMax < shovelMax,
    "native weapon reach sets the pen, crowbar and shovel swing bands")
earlySnapshot.escapeSquares = { { square = square(9, 10), danger = 0 } }
earlySnapshot.reachableImmediateCount = 1
earlySnapshot.reachableThreatSectors = 1
for _, row in ipairs({ { crowbarWeapon, crowbarMax },
    { shovelWeapon, shovelMax } }) do
    earlyZombie.x = 10.5 + row[2] + 0.2
    pairZombie.x = earlyZombie.x + 0.1
    earlySnapshot.threats[2] = { actor = pairZombie, visible = true,
        obstructed = false, attacking = false }
    earlySnapshot.reachableImmediateCount = 2
    check(SC.Combat.anticipatoryMeleeWindow(fighter, nil, earlySnapshot,
        earlyThreat, row[1], earlyReady) ~= nil,
        "a frontal pair permits an early swing at the weapon's own reach")
end
earlyZombie.x = 10.5 + penMax + 0.17
pairZombie.x = earlyZombie.x + 0.1
check(SC.Combat.anticipatoryMeleeWindow(fighter, nil, earlySnapshot,
    earlyThreat, penWeapon, earlyReady) == nil,
    "a pen's narrow striking band does not permit a two-zombie early swing")
earlySnapshot.threats[2] = nil
earlySnapshot.reachableImmediateCount = 1
check(SC.Combat.anticipatoryMeleeWindow(fighter, nil, earlySnapshot,
    earlyThreat, penWeapon, earlyReady) ~= nil,
    "a pen can still counter one closing zombie inside its short lead")
earlyZombie.x = 10.5 + crowbarMax + 0.15
pairZombie.x = 12.85
thirdZombie.x, thirdZombie.y = 13.6, 10.5
earlySnapshot.threats[2] = { actor = pairZombie, visible = true,
    obstructed = false, attacking = false }
earlySnapshot.threats[3] = { actor = thirdZombie, visible = true,
    obstructed = false, attacking = false }
local guarded = SC.Combat._guardedKiteOpeningForTests
check(guarded(fighter, earlySnapshot, earlyThreat, crowbarWeapon,
    earlyReady, 1, 3, 1) == true,
    "a crowbar fighter may swing while two followers remain behind the leading zombie")
check(guarded(fighter, earlySnapshot, earlyThreat, penWeapon,
    earlyReady, 1, 3, 1) == false,
    "a pen does not grant a guarded opening against three zombies")
thirdZombie.x, thirdZombie.y = 10.5, 13.0
check(guarded(fighter, earlySnapshot, earlyThreat, crowbarWeapon,
    earlyReady, 1, 3, 2) == false,
    "a nearby flanker cancels the crowbar opening")
thirdZombie.x, thirdZombie.y = 13.6, 10.5
check(guarded(fighter, earlySnapshot, earlyThreat, crowbarWeapon,
    earlyReady, 3, 3, 1) == false,
    "three immediate attackers require retreat even with a crowbar")
earlySnapshot.threats[2], earlySnapshot.threats[3] = nil, nil
earlyZombie.x = 12.3
-- Two zombies genuinely in the fight, and nothing else about them changes.
local nearA = character("z-near-a", 11.4, 10.5, "IsoZombie")
local nearB = character("z-near-b", 10.5, 11.4, "IsoZombie")
local function localThreat(zombie, score)
    return { actor = zombie, square = zombie:getSquare(), distanceSq = 0.81,
        visible = true, obstructed = false, score = score, bearing = "front",
        close = true }
end

-- Idle contacts a long way off, on a bearing that touches nothing.
local function distantThreats(count)
    local list = {}
    for index = 1, count do
        local zombie = character("z-far-" .. tostring(index), 40 + index, 40, "IsoZombie")
        list[index] = { actor = zombie, square = zombie:getSquare(),
            distanceSq = 900 + index, visible = true, obstructed = false,
            score = 10, bearing = "front" }
    end
    return list
end

-- Identical local geometry every time. Only the ambient tail grows.
local function snapshotWith(distantCount)
    local threats = { localThreat(nearA, 90), localThreat(nearB, 80) }
    for _, far in ipairs(distantThreats(distantCount)) do
        threats[#threats + 1] = far
    end
    local snapshot = {
        threats = threats,
        immediateAttackers = { threats[1], threats[2] },
        immediate = { threats[1], threats[2] },
        immediateCount = 2,
        threatCount = #threats,
        closeThreatCount = 2,
        closeImmediateCount = 2,
        occupiedThreatSectors = 1,
        threatSectors = {},
        allies = {},
        escapeSquares = {
            { square = square(9, 10, 0), danger = 0, nearestThreatSq = 16 },
        },
        encircled = false,
    }
    -- Derived exactly as the sensing writers derive it. A fixture that invents
    -- its own arithmetic proves nothing about what the game computes.
    snapshot.directionalPressure = 2 * 1.8
    snapshot.pressure = 2 * 1.5 + math.max(0, #threats - 2) * 0.35
    SC.CombatThreatModel.apply(snapshot, {
        immediateCount = 2,
        closeThreatCount = 2,
        closeImmediateCount = 2,
        occupiedThreatSectors = 1,
        visibleCount = #threats,
        threats = threats,
        escapeSquares = snapshot.escapeSquares,
    })
    return snapshot
end

local function scoresFor(distantCount)
    local snapshot = snapshotWith(distantCount)
    local actions = SC.Combat._actionUtilitiesForTests(
        fighter, player, snapshot, snapshot.threats[1], weapon,
        nil, { combatDoctrine = "close_defense", morale = 70 }, nil)
    local byKind, best, bestScore = {}, nil, -math.huge
    for _, action in ipairs(actions or {}) do
        byKind[action.kind] = action.score
        if action.score > bestScore then best, bestScore = action.kind, action.score end
    end
    return byKind, best
end

-- T01: ambient invariance. Every local fact is identical across these three,
-- so the local decision has to be identical too.
local baseline, baselineBest = scoresFor(0)
local fiveMore, fiveBest = scoresFor(5)
local twentyMore, twentyBest = scoresFor(20)

-- The sensing pass reports each immediate zombie in directionalPressure too.
-- Overrun must count that attacker once, or a three-person squad drops its
-- attack every time one zombie comes within arm's reach.
local quietPressure = snapshotWith(0)
quietPressure.immediateCount, quietPressure.closeImmediateCount = 0, 0
quietPressure.closeThreatCount, quietPressure.directionalPressure = 0, 0
local singlePressure = snapshotWith(0)
singlePressure.immediateCount, singlePressure.closeImmediateCount = 1, 1
singlePressure.closeThreatCount, singlePressure.directionalPressure = 1, 1.8
local quietRisk = SC.Combat.assessOverrun(fighter, quietPressure, weapon,
    { combatMode = "defensive", morale = 70 })
local singleRisk = SC.Combat.assessOverrun(fighter, singlePressure, weapon,
    { combatMode = "defensive", morale = 70 })
check(math.abs(singleRisk.risk - quietRisk.risk - 12) < 0.01,
    "one nearby zombie contributes one immediate-count term, not two")
check(singleRisk.overrun == false,
    "a healthy armed fighter does not retreat solely from one nearby zombie")

local frontPressure = snapshotWith(0)
frontPressure.reachableCloseCount = 4
frontPressure.reachableImmediateCount = 0
frontPressure.reachableThreatSectors = 1
frontPressure.closeThreatCount = 4
frontPressure.immediateCount = 0
frontPressure.squadPlan = { mode = "hold", supportCount = 1 }
local supportedFront = SC.Combat.assessOverrun(fighter, frontPressure,
    weapon, { combatMode = "defensive", morale = 70 })
frontPressure.squadPlan.supportCount = 0
local unsupportedFront = SC.Combat.assessOverrun(fighter, frontPressure,
    weapon, { combatMode = "defensive", morale = 70 })
check(supportedFront.threshold >= unsupportedFront.threshold + 10,
    "supported fighters may hold the outer edge before a frontal group reaches contact")
frontPressure.squadPlan.supportCount = 1
frontPressure.reachableImmediateCount = 1
local contactFront = SC.Combat.assessOverrun(fighter, frontPressure,
    weapon, { combatMode = "defensive", morale = 70 })
check(contactFront.threshold < supportedFront.threshold,
    "the guarded outer-edge allowance ends when a zombie reaches contact")
check(baselineBest ~= nil, "the fixture produces a scored action at all")
check(baselineBest == fiveBest and baselineBest == twentyBest,
    "the chosen action is the same with 0, 5 and 20 idle zombies in the distance: "
        .. tostring(baselineBest) .. "/" .. tostring(fiveBest) .. "/" .. tostring(twentyBest))

for kind, score in pairs(baseline) do
    if fiveMore[kind] ~= nil then
        check(math.abs(fiveMore[kind] - score) < 0.001,
            kind .. " is unchanged by five distant idle zombies: "
                .. tostring(score) .. " then " .. tostring(fiveMore[kind]))
    end
    if twentyMore[kind] ~= nil then
        check(math.abs(twentyMore[kind] - score) < 0.001,
            kind .. " is unchanged by twenty distant idle zombies: "
                .. tostring(score) .. " then " .. tostring(twentyMore[kind]))
    end
end

-- T02: forecast still matters. Making distant contacts irrelevant is only
-- correct while they are actually idle. A pack observed closing, with an
-- estimated arrival inside the planning horizon, has to raise retreat again --
-- otherwise this patch has simply made companions deaf instead of discerning.
local function convergingSnapshot(count)
    local snapshot = snapshotWith(0)
    local threats = snapshot.threats
    for index = 1, count do
        local zombie = character("z-run-" .. tostring(index), 20 + index, 20, "IsoZombie")
        threats[#threats + 1] = { actor = zombie, square = zombie:getSquare(),
            distanceSq = 100 + index, visible = true, obstructed = false,
            score = 40, bearing = "front", closingSpeed = 1.2,
            timeToImpactMs = 2500 }
    end
    snapshot.threatCount = #threats
    SC.CombatThreatModel.apply(snapshot, {
        immediateCount = 2, closeThreatCount = 2, closeImmediateCount = 2,
        occupiedThreatSectors = 1, visibleCount = #threats, threats = threats,
        escapeSquares = snapshot.escapeSquares,
    })
    return snapshot
end

local idleRetreat = baseline["retreat"]
local convergingSix = convergingSnapshot(6)
check((tonumber(convergingSix.incomingCount) or 0) == 6,
    "six observed closing zombies are counted as incoming: "
        .. tostring(convergingSix.incomingCount))
local convergingActions = SC.Combat._actionUtilitiesForTests(
    fighter, player, convergingSix, convergingSix.threats[1], weapon,
    nil, { combatDoctrine = "close_defense", morale = 70 }, nil)
local convergingRetreat
for _, action in ipairs(convergingActions or {}) do
    if action.kind == "retreat" then convergingRetreat = action.score end
end
check(convergingRetreat ~= nil and convergingRetreat > idleRetreat,
    "a pack observed converging still raises retreat: " .. tostring(idleRetreat)
        .. " then " .. tostring(convergingRetreat))

-- The same zombies, seen but not observed closing, must not.
local seenNotClosing = convergingSnapshot(6)
for _, threat in ipairs(seenNotClosing.threats) do
    threat.closingSpeed, threat.timeToImpactMs = nil, nil
end
SC.CombatThreatModel.apply(seenNotClosing, {
    immediateCount = 2, closeThreatCount = 2, closeImmediateCount = 2,
    occupiedThreatSectors = 1, visibleCount = #seenNotClosing.threats,
    threats = seenNotClosing.threats, escapeSquares = seenNotClosing.escapeSquares,
})
check((tonumber(seenNotClosing.incomingCount) or 0) == 0
        and math.abs(seenNotClosing.localPressure - convergingSix.localPressure) < 0.001,
    "the same zombies merely seen are ambient, not incoming")

-- An arrival beyond the horizon is awareness, not a reason to break off.
local farFuture = convergingSnapshot(6)
for _, threat in ipairs(farFuture.threats) do
    if threat.timeToImpactMs then threat.timeToImpactMs = 60000 end
end
SC.CombatThreatModel.apply(farFuture, {
    immediateCount = 2, closeThreatCount = 2, closeImmediateCount = 2,
    occupiedThreatSectors = 1, visibleCount = #farFuture.threats,
    threats = farFuture.threats, escapeSquares = farFuture.escapeSquares,
})
check((tonumber(farFuture.incomingCount) or 0) == 0,
    "an arrival a minute away is not inside the planning horizon")

-- T03: personal danger still wins. A squad score cannot talk a companion out of
-- being surrounded, and proven multi-sided pressure is still encirclement.
local surrounded = snapshotWith(0)
SC.CombatThreatModel.apply(surrounded, {
    immediateCount = 4, closeThreatCount = 4, closeImmediateCount = 4,
    occupiedThreatSectors = 4, visibleCount = 4, threats = surrounded.threats,
    escapeSquares = surrounded.escapeSquares,
})
check(surrounded.encircled == true,
    "four close attackers on four bearings is still encirclement")
check(surrounded.localPressure > baseline["retreat"] * 0 + 4,
    "four immediate attackers produce real local pressure: "
        .. tostring(surrounded.localPressure))

-- T04: an escape search that produced nothing is its own state. It used to mean
-- "encircled" the moment two zombies were visible anywhere on the map.
local noRoute = snapshotWith(20)
SC.CombatThreatModel.apply(noRoute, {
    immediateCount = 0, closeThreatCount = 0, closeImmediateCount = 0,
    occupiedThreatSectors = 0, visibleCount = #noRoute.threats,
    threats = noRoute.threats, escapeSquares = {},
})
check(noRoute.encircled == false and noRoute.escapeStatus == "unknown",
    "no route and a distant crowd is unknown, not encircled: "
        .. tostring(noRoute.escapeStatus))
local pinned = snapshotWith(0)
SC.CombatThreatModel.apply(pinned, {
    immediateCount = 1, closeThreatCount = 2, closeImmediateCount = 1,
    occupiedThreatSectors = 2, visibleCount = 2, threats = pinned.threats,
    escapeSquares = {},
})
check(pinned.encircled == false and pinned.escapeStatus == "blocked",
    "no route with something already on us is blocked: " .. tostring(pinned.escapeStatus))

-- T05: two companions sent at one zombie both walked at its centre tile, so
-- they arrived in the same place, shouldered each other and staggered out of
-- their own swings. The second attacker should take the far side instead.
local zombie = character("z-flanked", 20.5, 20.5, "IsoZombie")
local first = character("sc-flank-first", 19.5, 20.5)   -- west of it
local second = character("sc-flank-second", 19.4, 20.6) -- almost on top of the first

local openEverywhere = true
local priorOpenSegment = SC.Navigation.openSegment
SC.Navigation.openSegment = function() return openEverywhere end

check(type(SC.Combat.engagementAim) == "function", "the flank aim is reachable")
check(type(SC.Combat.claimPartner) == "function", "the claim partner lookup is reachable")

-- With no claim at all there is nobody to stand apart from.
check(SC.Combat.engagementAim(second, zombie, 1.2, 1000) == nil,
    "an unclaimed target produces no flanking detour")

-- Give the first companion the primary claim and the second the support claim.
SC.Combat.scoreTargets(first, nil, snapshotWith(0), nil)
local claimed = SC.Combat._claimTargetForTests
if type(claimed) == "function" then
    claimed(zombie, first, 1000, "cohort-flank", "primary", "attack", 1.0)
    claimed(zombie, second, 1000, "cohort-flank", "support", "tracking", 1.1)

    -- The committed attacker keeps the line it already had.
    check(SC.Combat.engagementAim(first, zombie, 1.2, 1000) == nil,
        "the first attacker is not moved aside for the newcomer")

    -- The newcomer, almost on the same bearing, is sent to the far side.
    local aimX, aimY = SC.Combat.engagementAim(second, zombie, 1.2, 1000)
    check(aimX ~= nil and aimY ~= nil,
        "a second attacker on the same bearing is given a flank")
    check(aimX > 20.5,
        "the flank is on the far side of the zombie from the first attacker: "
            .. tostring(aimX))
    local span = math.sqrt((aimX - 20.5) ^ 2 + (aimY - 20.5) ^ 2)
    check(math.abs(span - 1.2) < 0.001,
        "the flank stands at weapon spacing, not on top of the zombie: " .. tostring(span))

    -- Already on opposite sides: a working approach is left alone.
    second.x, second.y = 21.6, 20.5
    check(SC.Combat.engagementAim(second, zombie, 1.2, 1000) == nil,
        "companions already apart are not shuffled around further")

    -- A third recruited fighter is a reserve claim, but a zombie in open
    -- ground has another side to attack from. It must not wait for the first
    -- two to finish while a companion is being bitten.
    local third = character("sc-flank-third", 19.3, 20.5)
    local thirdRole = claimed(zombie, third, 1000, "cohort-flank",
        nil, "tracking", 1.2)
    check(thirdRole == "reserve", "the third fighter starts as reserve")
    local thirdX, thirdY = SC.Combat.engagementAim(third, zombie, 1.2, 1000)
    check(thirdX ~= nil and math.abs(thirdY - 20.5) > 0.8,
        "a reserve finds a third open strike lane rather than the occupied two")
    check(SC.Combat.shouldYieldEngagement(third, zombie, 1.2, 1000) == false,
        "a reserve with a clear third lane may join the fight")
    check(SC.Combat._roleMayAttackForTests(third, "reserve", nil,
        { kind = "melee" }, { actor = zombie, distanceSq = 2.0 },
        { immediateCount = 1 }) == true,
        "a reserve in melee range may strike through a clear friendly-fire lane")
    openEverywhere = false
    check(SC.Combat.shouldYieldEngagement(third, zombie, 1.2, 1000) == true,
        "without a proven third route the reserve yields the shared lane")
    third.x, third.y = 16.5, 20.5
    check(SC.Combat.shouldYieldEngagement(third, zombie, 1.2, 1000) == false,
        "a distant reserve may approach before the crowded-lane check")
    third.x, third.y = 19.3, 20.5
    openEverywhere = true

    -- Ground that is not provably open is never crossed to flank.
    second.x, second.y = 19.4, 20.6
    openEverywhere = false
    check(SC.Combat.engagementAim(second, zombie, 1.2, 1000) == nil,
        "a flank across unproven ground is refused")
    openEverywhere = true
end
SC.Navigation.openSegment = priorOpenSegment

-- A pushed-down zombie can fail character CanSee even though its occupied
-- square is visible. The short floor-sight fallback must remain local and
-- reject an unseen square, an upright zombie, or one outside pursuit range.
local sightActor = character("sc-floor-sight", 40.5, 40.5)
local sightZombie = character("z-floor-sight", 41.5, 40.5, "IsoZombie")
function sightZombie:isOnFloor() return true end
local priorCanSee = U.canSee
U.canSee = function(_, value) return value == sightZombie:getSquare() end
check(SC.Combat._canSeeCombatTargetForTests(sightActor, sightZombie,
    sightZombie:getSquare(), 1) == true,
    "a nearby fallen zombie remains visible by square LOS")
U.canSee = function() return false end
check(SC.Combat._canSeeCombatTargetForTests(sightActor, sightZombie,
    sightZombie:getSquare(), 1) == false,
    "a blocked square does not admit a blind floor attack")
U.canSee = priorCanSee

-- The grounded pair keeps one finisher while their relative distance changes
-- during the sidestep. After the short lease it may choose again.
local fallen = character("z-grounded-lane", 25.5, 25.5, "IsoZombie")
function fallen:isOnFloor() return true end
local closer = character("sc-grounded-closer", 24.8, 25.5)
local farther = character("sc-grounded-farther", 24.2, 25.5)
local laneClaim = SC.Combat._groundedLaneClaimForTests
local claim, created = laneClaim(farther, fallen, closer, "support", 1000)
check(created == true and claim.finisher == closer and claim.yielder == farther,
    "the farther companion initially yields the grounded finishing lane")
farther.x, closer.x = 25.0, 23.8
local held, changed = laneClaim(closer, fallen, farther, "support", 1100)
check(changed == false and held == claim and held.yielder == farther,
    "distance reversal cannot swap finisher while the lane claim is live")
claim.goalX, claim.goalY = 25.0, 26.8
local previousOpen = SC.Navigation.openSegment
SC.Navigation.openSegment = function() return true end
local retained = SC.Combat._retainGroundedLaneActionForTests(farther, fallen,
    { kind = "approach", score = 10 }, 1200)
check(retained.kind == "kite" and retained.floorLaneYield == true
        and retained.moveY > 0,
    "the yielding companion continues to its clear side instead of re-approaching")
SC.Navigation.openSegment = function() return false end
local blockedRetain = SC.Combat._retainGroundedLaneActionForTests(farther, fallen,
    { kind = "approach", score = 10 }, 1200)
check(blockedRetain.kind == "hold_range",
    "an invalidated side route holds instead of crossing an unproven tile")
SC.Navigation.openSegment = previousOpen
local renewed, renewedNow = laneClaim(closer, fallen, farther, "support", 3000)
check(renewedNow == true and renewed.yielder == closer,
    "an expired lane claim permits a new finisher decision")
previousOpen = SC.Navigation.openSegment
SC.Navigation.openSegment = function() return false end
check(SC.Combat._groundedLaneYieldForTests(farther, fallen, closer, {}, 1.5) == nil,
    "a grounded sidestep must not cross unproven ground")
SC.Navigation.openSegment = function() return true end
local stepX, stepY = SC.Combat._groundedLaneYieldForTests(farther, fallen,
    closer, {}, 1.5)
check(stepX ~= nil and stepY ~= nil,
    "a loaded, pathable sidestep can clear the finishing lane")
SC.Navigation.openSegment = previousOpen

-- T06: a companion being bitten is a companion who needs help. isGrabbed only
-- becomes true once a grapple or synthetic pin exists, so during the bite
-- itself -- exactly when help is wanted -- the victim did not register as
-- pinned, nobody was given rescue priority, and the zombie stayed an ordinary
-- low-scoring target that nobody came to deal with.
local ZA = SC.ZombieAttack
check(type(ZA) == "table" and type(ZA.underAttack) == "function",
    "the under-attack query is reachable")

local victim = character("sc-bitten", 30.5, 30.5)
check(ZA.underAttack(victim, 1000) == false,
    "a companion nobody is attacking is not under attack")
check(ZA.underAttack(nil, 1000) == false, "a missing actor is tolerated")

local biter = character("z-biter", 31.4, 30.5, "IsoZombie")
local remembered = ZA._rememberPairForTests
if type(remembered) == "function" then
    remembered(biter, victim, 1000)
    check(ZA.underAttack(victim, 1100) == true,
        "a companion a zombie is attacking is under attack straight away")
    check(ZA.underAttack(victim, 1000 + 100000) == false,
        "the state expires rather than sticking")
end

-- The rescue itself: a bystander must see the bitten ally as pinned.
local bystander = character("sc-bystander", 28.5, 30.5)
local allySnapshot = { allies = { { actor = victim } }, threats = {} }
if type(remembered) == "function" then
    remembered(biter, victim, 2000)
    local pinned = SC.Combat._pinnedAllies(bystander, allySnapshot)
    local sawVictim = false
    for _, ally in ipairs(pinned) do if ally == victim then sawVictim = true end end
    check(sawVictim, "a bystander sees the bitten ally as needing help")
    check(SC.Combat._rescuing(bystander, biter, pinned) == true,
        "the zombie doing the biting is a rescue target")
    -- The victim itself is not its own rescue case.
    local ownPinned = SC.Combat._pinnedAllies(victim, allySnapshot)
    check(#ownPinned == 0, "a companion is not rescuing itself")
end

-- T07 note: the claim-penalty waiver for a rescue is pinned in the static gate
-- rather than exercised here. scoreTargets declined to produce a record for a
-- synthetic zombie in this fixture and a test that quietly skips is worse than
-- no test, so it is asserted on the source instead and said so plainly. The
-- rescue detection it depends on is covered for real by T06 above.

-- T08: a doorway, corner or corridor offers exactly one place to stand and
-- swing. Walking in anyway put two companions on the same tile -- the playtest
-- log has two of them at 6011.5,5217.5 to the decimal -- where they shoulder
-- each other and neither can act, with the zombie free to bite either.
if type(SC.Combat._claimTargetForTests) == "function" then
    local penned = character("z-penned", 40.5, 40.5, "IsoZombie")
    local holder = character("sc-lane-holder", 39.5, 40.5)
    local latecomer = character("sc-lane-late", 39.4, 40.6)
    SC.Combat._claimTargetForTests(penned, holder, 1000, "cohort-lane", "primary", "attack", 1.0)
    SC.Combat._claimTargetForTests(penned, latecomer, 1000, "cohort-lane", "support", "tracking", 1.1)

    local openFar = true
    local priorOpen = SC.Navigation.openSegment
    SC.Navigation.openSegment = function() return openFar end

    -- Room on the far side: both can fight, nobody yields.
    check(SC.Combat.shouldYieldEngagement(latecomer, penned, 1.2, 1000) == false,
        "with a free far side the second attacker does not yield")

    -- No way round: the newcomer holds off instead of sharing the tile.
    openFar = false
    check(SC.Combat.shouldYieldEngagement(latecomer, penned, 1.2, 1000) == true,
        "with only one lane the second attacker yields")

    -- The companion already there never yields to the newcomer.
    check(SC.Combat.shouldYieldEngagement(holder, penned, 1.2, 1000) == false,
        "the companion already engaged keeps its place")

    -- A partner still walking in from across the room is not holding the lane.
    holder.x, holder.y = 30.5, 40.5
    check(SC.Combat.shouldYieldEngagement(latecomer, penned, 1.2, 1000) == false,
        "a distant partner does not reserve the only lane")
    holder.x, holder.y = 39.5, 40.5

    -- Already fighting from opposite sides: that is working, leave it be.
    latecomer.x, latecomer.y = 41.6, 40.5
    check(SC.Combat.shouldYieldEngagement(latecomer, penned, 1.2, 1000) == false,
        "companions already apart are not told to stand down")

    SC.Navigation.openSegment = priorOpen
end

-- Review 01: the incoming forecast read closingSpeed from the snapshot, but
-- combat wrote it onto utility.copyShallow(threat) -- a copy. The observation
-- never carried it, so the forecast was dead in the game while the old fixture
-- passed by inserting the fields by hand. Measure it the way perception does.
local motionSample = SC.Senses._sampleThreatMotionForTests
check(type(motionSample) == "function", "perception measures contact motion")

local watcher = character("sc-motion-watcher", 10.5, 10.5)
local runner = character("z-motion-runner", 20.5, 10.5, "IsoZombie")
local motionState = {}
local motionThreats = { { actor = runner } }

-- First look establishes the track; nothing can be known from one sample.
motionSample(watcher, motionState, motionThreats, 1000)
check(motionThreats[1].closingSpeed == nil,
    "one observation is not enough to call something incoming")

-- The zombie closes four tiles in half a second.
runner.x = 16.5
motionSample(watcher, motionState, motionThreats, 1500)
check((tonumber(motionThreats[1].closingSpeed) or 0) > 0,
    "a contact that moved closer is measured as closing: "
        .. tostring(motionThreats[1].closingSpeed))
check((tonumber(motionThreats[1].timeToImpactMs) or -1) > 0,
    "a closing contact has an estimated arrival")

-- The forecast now reaches the model from the observation alone.
local derived = SC.CombatThreatModel.derive({
    immediateCount = 0, closeThreatCount = 0, closeImmediateCount = 0,
    occupiedThreatSectors = 0, visibleCount = 1, threats = motionThreats,
    escapeSquares = {}, horizonMs = 60000,
})
check(derived.incomingCount == 1 and derived.incomingPressure > 0,
    "a measured approach reaches the incoming forecast: "
        .. tostring(derived.incomingCount))

-- The observer walking at a standing crowd is not the crowd chasing anybody.
local walker = character("sc-motion-walker", 40.5, 10.5)
local idle = character("z-motion-idle", 50.5, 10.5, "IsoZombie")
local walkState = {}
local walkThreats = { { actor = idle } }
motionSample(walker, walkState, walkThreats, 1000)
walker.x = 46.5
motionSample(walker, walkState, walkThreats, 1500)
check(walkThreats[1].closingSpeed == nil,
    "walking toward a standing crowd is not the crowd advancing")

-- Review 05: one actor may hold one slot. A support promoted to primary used
-- to renew with its stale role and end up in both, leaving a phantom holder
-- that blocked a third companion.
if type(SC.Combat._claimTargetForTests) == "function" then
    local slotZombie = character("z-slots", 60.5, 10.5, "IsoZombie")
    local slotA = character("sc-slot-a", 59.5, 10.5)
    local slotB = character("sc-slot-b", 61.5, 10.5)
    -- Stagger them, so A's claim lapses while B's is still live. Claimed at the
    -- same moment they expire together and no promotion ever happens, which is
    -- how this fixture quietly proved nothing the first time.
    local lease = SC.Config.get("runtime", "combatEngagementLeaseMs") or 2000
    SC.Combat._claimTargetForTests(slotZombie, slotA, 0, "cohort-slots", "primary", "attack", 1.0)
    SC.Combat._claimTargetForTests(slotZombie, slotB, lease * 0.5, "cohort-slots", "support", "tracking", 1.1)
    -- Past A's expiry, inside B's: B is promoted to primary.
    local lapsed = lease + 100
    -- B renews asking for the role it used to have. Without the fix that
    -- writes B into support while it is still primary.
    SC.Combat._claimTargetForTests(
        slotZombie, slotB, lapsed, "cohort-slots", "support", "committed", 1.1)
    local partner = SC.Combat.claimPartner(slotZombie, slotB, lapsed)
    check(partner ~= slotB, "a companion is never its own engagement partner")
    -- A third companion must find the support slot free, not blocked by a
    -- phantom holder that is really the primary wearing two hats.
    local slotC = character("sc-slot-c", 60.5, 11.5)
    local thirdRole = SC.Combat._claimTargetForTests(
        slotZombie, slotC, lapsed, "cohort-slots", nil, "tracking", 1.2)
    check(thirdRole ~= "reserve",
        "a third companion can take a support slot nobody is really in: "
            .. tostring(thirdRole))
end

-- Review 04: the unaligned fallback ignored other companions' reservations, so
-- two of them were handed the same tile to run to and the second quietly took
-- over the first's booking while the first kept its assignment.
--
-- These assert plan consistency, which is worth holding, but they do NOT
-- isolate the ownership fix: in this fixture the second companion is already
-- refused for an unrelated reason, so reverting the fix still passes. The
-- ownership checks themselves are pinned in the static gate and said so there.
if type(SC.Combat._sharedRetreatSquareForTests) == "function" then
    local retreat = SC.Combat._sharedRetreatSquareForTests
    local runnerA = character("sc-retreat-a", 70.5, 10.5)
    local runnerB = character("sc-retreat-b", 70.5, 11.5)
    local onlySquare = square(68, 10, 0)
    local escapeOnly = { escapeSquares = { { square = onlySquare, danger = 0 } } }
    -- The plan is internal and shared by cohort, so both companions in one
    -- cohort are competing for the same booking.
    local firstSquare = retreat(runnerA, { cohortKey = "cohort-retreat" },
        escapeOnly, nil, 1000, nil, nil)
    check(firstSquare == onlySquare, "the first companion takes the only way out")

    local secondSquare, plan, secondReason = retreat(runnerB,
        { cohortKey = "cohort-retreat" }, escapeOnly, nil, 1000, nil, nil)
    check(secondSquare == nil,
        "the second companion is not sent to the same tile: " .. tostring(secondReason))
    check(type(plan) == "table" and plan.assignments[runnerA] == onlySquare,
        "the first companion keeps the tile it booked")
    check(type(plan) == "table"
            and plan.reserved[SC.GameplayUtil.squareKey(onlySquare)] == runnerA,
        "the reservation still names the companion that holds it")
end

-- A shared plan must distinguish a fight the team can give ground through
-- from one it should leave. These are bounded snapshots, not world scans.
local squad = SC.CombatSquad
local originalUsable = SC.Combat.primaryWeaponUsable
local originalOpen = SC.Navigation.openSegment
SC.Combat.primaryWeaponUsable = function() return true end
SC.Navigation.openSegment = function() return true end
local function groupFight(memberCount, threatCount, start)
    squad.reset()
    local leader = character("squad-leader-" .. tostring(start), start, 80)
    local allies = {}
    for index = 2, memberCount do
        local ally = character("squad-ally-" .. tostring(start) .. ":" .. index,
            start + (index % 3) * 0.8, 80 + math.floor(index / 3) * 0.8)
        allies[#allies + 1] = { actor = ally, relationship = "party_ally",
            health = 100 }
    end
    local threats = {}
    for index = 1, threatCount do
        local angle = (index - 1) * 2 * math.pi / threatCount
        local x, y = start + math.cos(angle) * 3,
            80 + math.sin(angle) * 3
        local zombie = character("squad-zombie-" .. tostring(start) .. ":" .. index,
            x, y, "IsoZombie")
        threats[#threats + 1] = { actor = zombie, x = x, y = y,
            z = 0, visible = true, obstructed = false, posture = "upright",
            distanceSq = 9 }
    end
    local snapshot = { allies = allies, threats = threats }
    local plan = squad.forActor(leader, player, snapshot,
        "party:combat-test:home", start * 100)
    return leader, snapshot, plan
end

local solo = character("squad-solo", 130, 80)
check(squad.forActor(solo, player, { allies = {}, threats = {
    { actor = nearA, x = 130.8, y = 80, z = 0, visible = true },
} }, "party:combat-test:home", 1000) == nil,
    "solo fighters keep their local combat behavior")
local three, threeSnapshot, threePlan = groupFight(3, 6, 140)
check(threePlan and threePlan.mode == "give_ground" and threePlan.capable == 3,
    "three armed companions facing six give ground together")
local exchange = snapshotWith(0)
exchange.threats = { exchange.threats[1] }
exchange.immediateAttackers = { exchange.threats[1] }
exchange.immediateCount, exchange.closeImmediateCount = 1, 1
exchange.closeThreatCount, exchange.directionalPressure = 1, 1.8
exchange.localPressure = SC.CombatThreatModel.localPressure(1, 1, 1)
exchange.squadPlan = { mode = "give_ground", supportCount = 2 }
local exchangeActions = SC.Combat._actionUtilitiesForTests(
    fighter, player, exchange, exchange.threats[1], weapon,
    nil, { combatDoctrine = "close_defense", morale = 70 }, nil)
local retreatScore, strikeScore = -math.huge, -math.huge
for _, action in ipairs(exchangeActions or {}) do
    if action.kind == "retreat" then retreatScore = action.score end
    if action.kind == "melee" or action.kind == "shove" then
        strikeScore = math.max(strikeScore, action.score)
    end
end
check(strikeScore > retreatScore,
    "giving ground still permits a healthy fighter to strike at a safe opening")
local _, _, threeEight = groupFight(3, 8, 160)
check(threeEight and threeEight.mode == "give_ground",
    "three armed companions facing eight still fight while yielding ground")
local hurtLeader, hurtSnapshot = groupFight(3, 8, 170)
hurtSnapshot.allies[1].health = 35
squad.reset()
local hurtPlan = squad.forActor(hurtLeader, player, hurtSnapshot,
    "party:combat-test:home", 17001)
check(hurtPlan and hurtPlan.capable == 2 and hurtPlan.mode == "disengage",
    "an injured fighter is not counted as usable support against eight")
local _, _, fiveTen = groupFight(5, 10, 180)
check(fiveTen and fiveTen.mode == "give_ground",
    "five armed companions facing ten coordinate their withdrawal")
local fiveLeader, fiveSnapshot, fiveTwelve = groupFight(5, 12, 200)
check(fiveTwelve and fiveTwelve.mode == "give_ground",
    "five armed companions facing twelve do not auto-disengage")
local cachedPlan = squad.forActor(fiveLeader, player, fiveSnapshot,
    "party:combat-test:home", 20100)
check(cachedPlan and cachedPlan.refreshedAt == fiveTwelve.refreshedAt,
    "the shared plan is reused inside its 250 millisecond planning window")
local refreshedPlan = squad.forActor(fiveLeader, player, fiveSnapshot,
    "party:combat-test:home", 20260)
check(refreshedPlan and refreshedPlan.refreshedAt == 20260,
    "the plan refreshes after 250 milliseconds")
local _, _, fiveThirteen = groupFight(5, 13, 220)
check(fiveThirteen and fiveThirteen.mode == "disengage",
    "a larger crowd makes the same team disengage")
local crowdedFinisher = { threats = {
    threeSnapshot.threats[1],
    { actor = threeSnapshot.threats[2].actor, x = 140.8, y = 80,
        z = 0, posture = "upright", obstructed = false },
} }
check(squad.safeFinisher(three, crowdedFinisher.threats[1].actor,
    crowdedFinisher) == false,
    "a surrounding upright attacker blocks a floor finisher")
local quietFinisher = { threats = {
    { actor = threeSnapshot.threats[1].actor, x = 143, y = 80,
        z = 0, posture = "downed" },
    { actor = threeSnapshot.threats[2].actor, x = 140.6, y = 80,
        z = 0, posture = "downed" },
} }
check(squad.safeFinisher(three, quietFinisher.threats[1].actor,
    quietFinisher) == true,
    "a second grounded zombie does not block a safe finisher")
quietFinisher.threats[2].gettingUp = true
check(squad.safeFinisher(three, quietFinisher.threats[1].actor,
    quietFinisher) == true,
    "a zombie still on the ground while getting up leaves a finisher opening")
quietFinisher.threats[2].posture = "upright"
check(squad.safeFinisher(three, quietFinisher.threats[1].actor,
    quietFinisher) == false,
    "the opening closes as soon as the other zombie is upright")

local crowdFront = {}
for index = 1, 4 do
    crowdFront[index] = { actor = character("front-" .. index,
        241 + index * 0.1, 80 + index * 0.1, "IsoZombie"),
        x = 241 + index * 0.1, y = 80 + index * 0.1,
        z = 0, posture = "upright" }
end
local reachableFront = SC.CombatThreatModel.reachable(crowdFront, 240, 80, 0)
check(reachableFront.close == 4 and reachableFront.surrounded == false,
    "four zombies on one side are pressure, not encirclement")
local ring = {}
for index = 1, 4 do
    local angle = (index - 1) * math.pi * 0.5
    ring[index] = { actor = character("ring-" .. index,
        240 + math.cos(angle), 80 + math.sin(angle), "IsoZombie"),
        x = 240 + math.cos(angle), y = 80 + math.sin(angle), z = 0 }
end
check(SC.CombatThreatModel.reachable(ring, 240, 80, 0).surrounded == true,
    "a four-sided ring is actual encirclement")
ring[1].obstructed = true
check(SC.CombatThreatModel.reachable(ring, 240, 80, 0).surrounded == false,
    "a solid barrier opens the encirclement assessment")
ring[1].obstructed = false
ring[2].posture = "downed"
ring[3].posture = "crawler"; ring[3].x = 243
check(SC.CombatThreatModel.reachable(ring, 240, 80, 0).close == 2,
    "downed and distant crawling zombies do not inflate reachable pressure")
local flankActor = character("squad-flank", 250, 80)
local flankTarget = character("squad-flank-target", 252, 80, "IsoZombie")
local flankBlocker = character("squad-flank-blocker", 251, 80, "IsoZombie")
check(squad.safePosition(flankActor, flankTarget, 252, 81, 0, {
    threats = { { actor = flankBlocker, x = 251, y = 80, z = 0,
        posture = "upright" } }, allies = {},
}, 25000) == false,
    "a flank is refused when the path crosses another upright zombie")
local laneActor = character("upright-lane-actor", 260, 80)
local laneTarget = character("upright-lane-target", 263, 80, "IsoZombie")
local laneBlocker = character("upright-lane-blocker", 261, 80)
local laneX, laneY = SC.Combat._uprightLaneYieldForTests(laneActor,
    laneTarget, laneBlocker, { threats = {}, allies = {
        { actor = laneBlocker },
    } }, 25000)
check(laneX ~= nil and laneY ~= nil and math.abs(laneY) > 0.5,
    "a fighter whose melee lane is blocked tries a proven side step")
squad.reset()
local granted = 0
for index = 1, 10 do
    if squad.positionProbe(26000) then granted = granted + 1 end
end
check(granted == 8, "a frame grants at most eight costly position proofs")
do
    -- With one proof left, the old executor proved the flank in its yield
    -- check, then tried to prove it again after exhausting the shared budget.
    -- It consequently used the precomputed centre vector into its partner.
    local target = character("budget-target", 300, 80, "IsoZombie")
    local primary = character("budget-primary", 299, 80)
    local support = character("budget-support", 298.9, 80.1)
    local priorNow, priorMove, priorSpacing = U.nowMs, U.move, SC.Combat.meleeSpacing
    U.nowMs = function() return 30000 end
    SC.Combat.meleeSpacing = function() return { desired = 1.2 } end
    local moved
    U.move = function(_, _, intent) moved = intent return true end
    SC.Navigation.openSegment = function() return true end
    SC.Combat._claimTargetForTests(target, primary, 30000, "budget-cohort", "primary", "attack", 1)
    SC.Combat._claimTargetForTests(target, support, 30000, "budget-cohort", "support", "tracking", 1.1)
    squad.reset()
    for _ = 1, 7 do check(squad.positionProbe(30000), "reserve a shared proof for another fighter") end
    local acted = SC.Combat._executeForTests(support, nil, { threats = {}, allies = {} },
        { actor = target }, { item = weaponItem, equipped = true },
        { kind = "approach", moveX = 0.1, moveY = 0, microSteered = true }, {}, {})
    check(acted and moved and moved.action == "combat_approach" and moved.dx > 2,
        "an approach retains its proven flank when the final shared proof is consumed")
    check(not squad.positionProbe(30000), "flank retention does not exceed the eight-proof frame budget")
    U.nowMs, U.move, SC.Combat.meleeSpacing = priorNow, priorMove, priorSpacing
end
SC.Combat.primaryWeaponUsable = originalUsable
SC.Navigation.openSegment = originalOpen
squad.reset()

print("COMBAT_COORDINATION_REGRESSION_PASS checks=" .. tostring(checks))
