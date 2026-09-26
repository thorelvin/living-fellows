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

local fighter = character("sc-horde-fighter", 10.5, 10.5)
local player = character("sc-horde-player", 11.5, 10.5)
local weapon = { item = weaponItem, ranged = false, damage = 2.0, range = 1.5,
    minRange = 0.3, conditionRatio = 1, sharpness = 1, staminaCost = 1, weight = 1.5 }

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

    -- Ground that is not provably open is never crossed to flank.
    second.x, second.y = 19.4, 20.6
    openEverywhere = false
    check(SC.Combat.engagementAim(second, zombie, 1.2, 1000) == nil,
        "a flank across unproven ground is refused")
    openEverywhere = true
end
SC.Navigation.openSegment = priorOpenSegment

print("COMBAT_COORDINATION_REGRESSION_PASS checks=" .. tostring(checks))
