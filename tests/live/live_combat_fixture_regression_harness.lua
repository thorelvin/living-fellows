-- SPDX-License-Identifier: MIT
-- Test only the private live fixture's semantic clip and observer API contracts.
local H, checks = SCRealSandboxHarness, 0
local function check(value, message)
    checks = checks + 1
    assert(value, "live combat fixture " .. checks .. ": " .. message)
end
for _, names in ipairs({
    "Bob_AttackFloorStamp", "Bob_AttackFloorStamp_Bat", "Bob_AttackFloorStamp_Rifle",
    "Bob_AttackFloorStamp_Hgun", "Bob_AttackFloorStamp_2Hheavy",
    "Bob_Idle|Bob_AttackFloorStomp|Bob_Walk", "Bob_AttackFloorStomp_Bat",
}) do
    check(H.isStompClip(names), "recognizes the native stomp attack family: " .. names)
end
for _, names in ipairs({
    "", "Bob_Shove", "Bob_AttackFloorBat", "Bob_IdleToStomp", "Bob_StompToIdle",
    "Bob_AttackFloorStampede", "Unrelated_Bob_AttackFloorStamp",
}) do
    check(not H.isStompClip(names), "rejects a non-stomp or transition clip: " .. names)
end
local body, companion = { health = 32, restores = 0 }, { health = 43 }
local observer = { dead = false }
function observer:isDead() return self.dead end
function observer:getBodyDamage() return body end
function observer:setGodMod() error("ordinary SP refuses cheats") end
function body:RestoreToFullHealth()
    self.restores = self.restores + 1; self.health = 100
    self.infected, self.fake, self.infectionTime, self.mortality, self.infectionLevel = false, false, -1, -1, 0
    self.bites, self.scratches, self.bleeding = 0, 0, 0
end
function body:getOverallBodyHealth() return self.health end
function body:isInfected() return self.infected end
function body:isIsFakeInfected() return self.fake end
function body:getInfectionTime() return self.infectionTime end
function body:getInfectionMortalityDuration() return self.mortality end
function body:getApparentInfectionLevel() return self.infectionLevel end
function body:getNumPartsBitten() return self.bites end
function body:getNumPartsScratched() return self.scratches end
function body:getNumPartsBleeding() return self.bleeding end
check(H.restoreObserver(observer) and body.health == 100 and body.restores == 1
        and companion.health == 43,
    "ordinary native phase-boundary health restoration never protects companions")
observer.dead = true
check(not H.restoreObserver(observer) and body.restores == 1,
    "dead cloned observer fails before any resurrection attempt")
observer.dead = false
body.health = 32
function body:RestoreToFullHealth() end
check(not H.restoreObserver(observer), "successful native call without full-health readback fails")
body.health = 100; body.infected = true; body.infectionLevel = 100
check(not H.restoreObserver(observer), "full health alone cannot hide terminal Knox contamination")
body.infected = false; body.infectionLevel = 0; body.bites = 1
check(not H.restoreObserver(observer), "leftover wounds reject a clean observer boundary")
body.bites = 0; body.mortality = 72
check(not H.restoreObserver(observer), "retained infection timer fails sanitation readback")
function body:RestoreToFullHealth() error("restore rejected") end
check(not H.restoreObserver(observer), "failed native restoration is not accepted")
function observer:isDead() error("readback unavailable") end
check(not H.restoreObserver(observer), "an unverified alive observer cannot enter target probes")
local weapon = { minimum = 0.6, maximum = 1.4, modifier = 1 }
function weapon:getMinRange() return self.minimum end
function weapon:getMaxRange(actor) self.actor = actor; return self.maximum end
function weapon:getRangeMod() return self.modifier end
local distance = H.meleeFixtureDistance(weapon, companion)
check(math.abs(distance - 1.05) < 0.0001 and weapon.actor == companion,
    "fixture uses actual actor-scaled weapon range at a deterministic interior point")
check(distance > weapon.minimum + 0.25 and distance < weapon.maximum - 0.15,
    "target cannot start in native defensive-shove or marginal max-range band")
weapon.modifier = 1.2
check(H.meleeFixtureDistance(weapon, companion) > distance,
    "native weapon range modifier is applied to the fixture")
weapon.maximum = 0.65
check(H.meleeFixtureDistance(weapon, companion) == nil,
    "no stable band rejects setup instead of inventing a hittable distance")
weapon.maximum = 1.4; weapon.modifier = 0
check(H.meleeFixtureDistance(weapon, companion) == nil, "invalid range modifiers fail closed")
function weapon:getMinRange() error("not a hand weapon") end
check(H.meleeFixtureDistance(weapon, companion) == nil, "unavailable native range fails closed")
H.actor, H.testZombie, H.combatImpactCount = observer, companion, nil
H.onMeleeWeaponHit({}, companion, weapon, 1)
H.onMeleeWeaponHit(observer, {}, weapon, 1)
check(H.combatImpactCount == nil and companion.health == 43,
    "impact diagnostics ignore unrelated actors and never apply damage")
local oldCell, U = getCell, SurvivorCompanion.GameplayUtil
local oldFree, oldActor = U.isSquareFree, SurvivorCompanion.Actor
local square = { free = true, occupied = false, blocked = false, chunk = {} }
function square:getChunk() return self.chunk end
function square:getMovingObjects()
    return {size=function() return square.occupied and 1 or 0 end}
end
function square:isBlockedTo() return self.blocked end
local cell = {}
function cell:getGridSquare(x, y, z) return square end
function getCell() return cell end
function U.isSquareFree(value) return value.free end
local point = H.findCombatArena({x=10,y=10,z=0})
check(point and point.observerDistance >= 15, "combat arena prefers physical isolation beyond15tiles")
square.occupied = true
check(H.findCombatArena({x=10,y=10,z=0}) == nil, "occupied arena cannot be used")
square.occupied = false; square.blocked = true
check(H.findCombatArena({x=10,y=10,z=0}) == nil, "arena rejects walls within its5x5 footprint")
square.blocked = false; square.chunk = nil
check(H.findCombatArena({x=10,y=10,z=0}) == nil, "unloaded arena fails closed")
square.chunk = {}
function cell:getGridSquare(x, y, z)
    if x >= 20 and x <= 24 and y >= 8 and y <= 12 then return square end
end
point = H.findCombatArena({x=10,y=10,z=0})
check(point and point.observerDistance >= 10 and point.observerDistance < 15,
    "fallback still requires at least10tiles and all25loaded clear squares")
local oldSquare = { members = {} }
square.members = {}
local actor = {square=oldSquare, renderSquare=oldSquare, moving=oldSquare}
oldSquare.members[actor] = true
function actor:setX(value) self.x = value end
function actor:setY(value) self.y = value end
function actor:setZ(value) self.z = value end
function actor:setNextX(value) self.nx = value end
function actor:setNextY(value) self.ny = value end
function actor:setLastX(value) self.lx = value end
function actor:setLastY(value) self.ly = value end
function actor:setLastZ(value) self.lz = value end
function actor:setCurrentSquareFromPosition() self.square = self.x > 20 and square or oldSquare end
function actor:getCurrentSquare() return self.square end
function actor:setSquare(value) self.renderSquare = value end
function actor:setMovingSquare(value)
    if self.moving then self.moving.members[self] = nil end
    self.moving = value
    if value then value.members[self] = true end
end
function actor:getMovingSquare() return self.moving end
function actor:ensureWorldMembership()
    -- Native repair adds to current square, but isExistInTheWorld checks the
    -- distinct inherited render-square field. Do not collapse those in a mock.
    self.square.members[self] = true
    return self.renderSquare and self.renderSquare.members[self] == true
end
SurvivorCompanion.Actor = {stop=function() return true end}
check(H.placeCombatActor(actor, {x=22.5,y=10.5,z=0}) and actor.nx == actor.lx
    and actor.ny == actor.ly and actor.moving == square and actor.renderSquare == square
    and square.members[actor] and not oldSquare.members[actor],
    "fixture relocation updates last/next/current/render and moving-square ownership together")
check(H.placeCombatActor(actor, {x=10.5,y=10.5,z=0}) and actor.square == oldSquare
    and actor.renderSquare == oldSquare and actor.moving == oldSquare
    and oldSquare.members[actor] and not square.members[actor],
    "arena cleanup restores all three refs and removes its old moving-list entry")
local setRenderSquare = actor.setSquare
function actor:setSquare() end
check(not H.placeCombatActor(actor, {x=22.5,y=10.5,z=0}),
    "omitting the render-square update reproduces the real native membership rejection")
actor.setSquare = setRenderSquare
function actor:ensureWorldMembership() return false end
check(not H.placeCombatActor(actor, {x=22.5,y=10.5,z=0}), "membership repair failure rejects placement")
getCell, U.isSquareFree, SurvivorCompanion.Actor = oldCell, oldFree, oldActor
SC_TEST_REPORT = "LIVE_COMBAT_FIXTURE_REGRESSION_PASS checks=" .. checks
