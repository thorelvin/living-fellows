-- SPDX-License-Identifier: MIT
-- Squad coordination as it stands on 0.27.12: phase 0 of
-- plan-horde-combat-wp2-6. A check marked GAP pins today's behaviour that a
-- later phase replaces on purpose; that phase flips the check to its new
-- expectation in the same commit, so the change is visible in review. Checks
-- without GAP are invariants every phase must keep.
local SC, f = SurvivorCompanion, SurvivorCompanion.TestFixture
local check = f.check
local Squad = SC.CombatSquad
local oldUsable, oldOpen, oldFacts =
    SC.Combat.primaryWeaponUsable, SC.Navigation.openSegment, SC.ZombieFacts
SC.Combat.primaryWeaponUsable = function() return true end
SC.Navigation.openSegment = function() return true end
SC.ZombieFacts = nil

local clock = 500000
local function tick(ms) clock = clock + (ms or 1000) return clock end

local function fighter(id, x, y)
    local actor = f.actor(id, x, y, {})
    f.registry[actor.id] = actor
    return actor
end
local function zombie(x, y)
    local value = f.zombie(x, y, {})
    return value
end
local function row(value)
    local x, y, z = value:getX(), value:getY(), value:getZ()
    return { actor = value, x = x, y = y, z = z, visible = true, obstructed = false }
end
local function snapshot(allies, zombies)
    local result = { allies = {}, threats = {} }
    for _, ally in ipairs(allies) do
        result.allies[#result.allies + 1] = { actor = ally, health = 100 }
    end
    for _, value in ipairs(zombies) do result.threats[#result.threats + 1] = row(value) end
    return result
end

-- 1. Three fighters, each on its own zombie.
Squad.reset()
local a, b, c = fighter("squad-a", 0, 0), fighter("squad-b", 2, 0), fighter("squad-c", 0, 2)
local za, zb, zc = zombie(-1, 0), zombie(3, 0), zombie(0, 3)
local view = Squad.forActor(a, nil, snapshot({ b, c }, { za, zb, zc }), "party:squad", tick())
check(view ~= nil and view.target == za,
    "three fighters and three zombies: the nearest fighter takes its own zombie")
-- Phase 1, single spending: b and c each hold a zombie of their own, so
-- neither is standing by for a's.
check(view.supportCount == 0,
    "busy fighters are not support: " .. tostring(view.supportCount))

-- 1b. A free ally is support. Each way of being unable to help removes it.
local function supportFor(change, undo)
    Squad.reset()
    if change then change() end
    local current = Squad.forActor(a, nil, snapshot({ b }, { za }), "party:squad", tick())
    if undo then undo() end
    return current and current.supportCount
end
check(supportFor() == 1, "a free, armed ally is support")
local grabbed = SC.ZombieAttack.isGrabbed
check(supportFor(function() SC.ZombieAttack.isGrabbed = function(x) return x == b end end,
    function() SC.ZombieAttack.isGrabbed = grabbed end) == 0, "a grabbed ally is not support")
check(supportFor(function() b.vehicle = {} end, function() b.vehicle = nil end) == 0,
    "a seated ally is not support")
check(supportFor(function() b.endurance = 0.2 end, function() b.endurance = nil end) == 0,
    "an exhausted ally is not support")
local downed = SC.Medical.isDowned
check(supportFor(function() SC.Medical.isDowned = function(x) return x == b end end,
    function() SC.Medical.isDowned = downed end) == 0, "a downed ally is not support")
local usable, unarmed = SC.Combat.primaryWeaponUsable, SC.Combat.unarmedResponse
check(supportFor(function()
    SC.Combat.primaryWeaponUsable = function(x) return x ~= b end
    SC.Combat.unarmedResponse = function() return "withdraw" end
end, function()
    SC.Combat.primaryWeaponUsable, SC.Combat.unarmedResponse = usable, unarmed
end) == 0, "an ally with no weapon who would withdraw is not support")
check(supportFor(function()
    b.modData.SC_Order, b.modData.SC_AnchorX, b.modData.SC_AnchorY = "stay", 30, 0
end, function()
    b.modData.SC_Order, b.modData.SC_AnchorX, b.modData.SC_AnchorY = nil, nil, nil
end) == 0, "an ally held to a stay spot out of reach is not support")
check(supportFor(function()
    b.modData.SC_Order, b.modData.SC_AnchorX, b.modData.SC_AnchorY = "guard", 2, 0
end, function()
    b.modData.SC_Order, b.modData.SC_AnchorX, b.modData.SC_AnchorY = nil, nil, nil
end) == 1, "an ally guarding a spot within reach is support")

-- 2. Cover before doubling. a is nearest to both zombies and b reaches only
-- the first, so b takes the first and frees a for the second.
Squad.reset()
b.square = f.cell:getGridSquare(5, 0, 0)
local first, second = zombie(1, 0), zombie(-1, 0)
local scene = snapshot({ b }, { first, second })
scene.threats[1].x = a:getX() + 0.9
scene.threats[2].x = a:getX() - 1.2
local now = tick()
local viewA = Squad.forActor(a, nil, scene, "party:squad", now)
local viewB = Squad.forActor(b, nil, scene, "party:squad", now)
check(viewA ~= nil and viewB ~= nil, "both fighters share one squad plan")
-- Phase 2: first-come assignment used to give a the first zombie and leave
-- the second with nobody.
check(viewA.target == second and viewB.target == first,
    "every reachable zombie gets a defender: "
        .. tostring(viewA.target == second) .. "/" .. tostring(viewB.target == first))

-- 2b. A zombie on the player comes first, even before one attacking nearby.
Squad.reset()
b.square, b.worldX, b.worldY = f.cell:getGridSquare(-5, 0, 0), a:getX() - 5.1, a:getY()
local biter, onPlayer = zombie(1, 0), zombie(3, 0)
scene = snapshot({ b }, { biter, onPlayer })
scene.threats[1].x, scene.threats[1].attacking = a:getX() + 1.5, true
scene.threats[2].x, scene.threats[2].target = a:getX() + 3.0, f.player
viewA = Squad.forActor(a, f.player, scene, "party:squad", tick())
check(viewA ~= nil and viewA.target == onPlayer,
    "the only defender in reach takes the zombie on the player")
b.worldX, b.worldY = nil, nil

-- 2c. The plan is the encounter's: a zombie only b can see is still in it,
-- while b's view is fresh.
local function viewsWith(bView)
    local byId = SC.Registry.byId
    SC.Registry.byId = function(id)
        if id == b.id then return { actor = b, runtime = { senses = { current = bView } } } end
        return byId(id)
    end
    local result = Squad.forActor(a, nil, snapshot({ b }, {}), "party:squad", now)
    SC.Registry.byId = byId
    return result
end
Squad.reset()
b.square = f.cell:getGridSquare(5, 0, 0)
local farSide = zombie(6, 0)
now = tick()
local bView = snapshot({ a }, { farSide })
bView.time = now - 200
local shared = viewsWith(bView)
check(shared ~= nil and Squad.forActor(b, nil, bView, "party:squad", now).target == farSide,
    "a zombie only one member sees belongs to the shared plan")
Squad.reset()
bView.time = now - 800
check(viewsWith(bView) == nil, "a stale member view is not used")

-- 2d. A companion already fighting a zombie keeps it, even when another
-- member stands closer to it.
Squad.reset()
b.square = f.cell:getGridSquare(2, 0, 0)
local fought, other = zombie(2, 0), zombie(-1, 0)
scene = snapshot({ b }, { fought, other })
scene.threats[1].x = b:getX() + 0.5
local peek = SC.Combat.peek
SC.Combat.peek = function(value) if value == a then return { target = fought } end return peek(value) end
viewA = Squad.forActor(a, nil, scene, "party:squad", tick())
SC.Combat.peek = peek
check(viewA ~= nil and viewA.target == fought, "a fighter keeps the zombie it is already fighting")

-- 2e. Same scene, same plan, whatever order the allies were listed in.
local function tieWinner(allies)
    Squad.reset()
    local tie = zombie(2, 2)
    local current = tick()
    Squad.forActor(a, nil, snapshot(allies, { tie }), "party:squad", current)
    local viewC = Squad.forActor(c, nil, snapshot({ a, b }, { tie }), "party:squad", current)
    local viewOfB = Squad.forActor(b, nil, snapshot({ a, c }, { tie }), "party:squad", current)
    return viewOfB and viewOfB.target == tie and "b" or viewC and viewC.target == tie and "c" or "none"
end
local firstOrder, secondOrder = tieWinner({ b, c }), tieWinner({ c, b })
check(firstOrder == secondOrder and firstOrder ~= "none",
    "an equal choice is settled by id, not list order: " .. firstOrder .. "/" .. secondOrder)

-- 3. A zombie count wobbling at the capacity line no longer flips the mode
-- on every 250 ms rebuild. Two fit fighters hold four; a fifth asks to give
-- ground, which waits out the 1.5 s dwell. Disengage does not wait.
Squad.reset()
b.square = f.cell:getGridSquare(1, 0, 0)
local crowd = { zombie(2, 1), zombie(2, -1), zombie(-2, 1), zombie(-2, -1),
    zombie(3, 0), zombie(0, -2), zombie(-3, 0), zombie(0, 3), zombie(-2, 2) }
local function present(count)
    local list = {}
    for index = 1, count do list[index] = crowd[index] end
    return snapshot({ b }, list)
end
local modes, changes, previous = {}, 0, nil
for index = 1, 4 do
    local current = Squad.forActor(a, nil, present(index % 2 == 0 and 5 or 4), "party:squad", tick(260))
    modes[#modes + 1] = current and current.mode or "none"
    if previous ~= nil and current and current.mode ~= previous then changes = changes + 1 end
    previous = current and current.mode
end
check(changes == 0 and modes[1] == "engage",
    "a count wobbling at the line holds its mode through the dwell: " .. table.concat(modes, ","))
local held
for _ = 1, 7 do held = Squad.forActor(a, nil, present(5), "party:squad", tick(260)) end
check(held and held.mode == "give_ground", "a sustained fifth zombie gives ground after the dwell")
Squad.reset()
Squad.forActor(a, nil, present(4), "party:squad", tick(260))
local escalated = Squad.forActor(a, nil, present(9), "party:squad", tick(260))
check(escalated and escalated.mode == "disengage", "a crowd past the margin disengages at once")

-- 3b. Capacity: two zombies per fit fighter, one per worn fighter, shifted by
-- doctrine, with arrivals weighed by how soon they come.
b.square, c.square = f.cell:getGridSquare(2, 0, 0), f.cell:getGridSquare(0, 2, 0)
local ring = { zombie(-2, 0), zombie(0, -2), zombie(3, 1), zombie(1, 3), zombie(-1, 3),
    zombie(3, -1), zombie(-2, -2), zombie(-3, 1), zombie(4, 0), zombie(1, -3) }
local function modeFor(count, arrivals)
    Squad.reset()
    local list = {}
    for index = 1, count do list[index] = ring[index] end
    local scene = snapshot({ b, c }, list)
    for _, eta in ipairs(arrivals or {}) do
        local far = zombie(-8, 0)
        local row = row(far)
        row.timeToImpactMs = eta
        scene.threats[#scene.threats + 1] = row
    end
    local current = Squad.forActor(a, nil, scene, "party:squad", tick())
    return current and current.mode or "none", current
end
check(modeFor(6) == "engage", "three fit fighters hold six, two each")
check(modeFor(7) == "give_ground", "three fit fighters give ground to seven")
check(modeFor(9) == "disengage", "three fit fighters pull out from nine")
c.endurance = 0.4
check(modeFor(6) == "give_ground", "a worn fighter holds one, so six is too many")
c.endurance = nil
for _, member in ipairs({ a, b, c }) do member.modData.SC_CombatDoctrine = "weapons_free" end
check(modeFor(9) == "engage", "Weapons Free fighters hold three each")
for _, member in ipairs({ a, b, c }) do member.modData.SC_CombatDoctrine = nil end
a.modData.SC_CombatDoctrine = "ranged_support"
check(modeFor(6) == "give_ground", "Ranged Support holds one fewer at close range")
a.modData.SC_CombatDoctrine = nil
check(modeFor(6, { 2000 }) == "give_ground", "an arrival two seconds out counts in full")
check(modeFor(6, { 9000 }) == "engage", "an arrival nine seconds out does not count")
local _, half = modeFor(6, { 5500 })
check(half and math.abs(half.forecast - 6.5) < 0.01, "an arrival 5.5 s out counts half: "
    .. tostring(half and half.forecast))

-- 3c. Closing in: alone, only on an isolated front; in a squad that covers
-- everything, a fighter may close on its own zombie with its share near.
local front = { actor = za, bearing = "front" }
local two = { close = 2, occupiedSectors = 2, immediate = 1 }
local covered = { mode = "engage", target = za, holds = 2 }
check(SC.Combat.openFront({}, front, two) == false, "alone, two zombies near is no open front")
check(SC.Combat.openFront({ squadPlan = covered }, front, two) == true,
    "a covered squad lets a fighter close on its own zombie with two near")
check(SC.Combat.openFront({ squadPlan = { mode = "give_ground", target = za, holds = 2 } },
    front, two) == false, "giving ground is no open front")
check(SC.Combat.openFront({ squadPlan = { mode = "engage", target = zb, holds = 2 } },
    front, two) == false, "another fighter's zombie is no open front")
check(SC.Combat.openFront({ squadPlan = covered }, front,
    { close = 3, occupiedSectors = 2, immediate = 1 }) == false, "more than its share near is no open front")
check(SC.Combat.openFront({ squadPlan = covered, encircled = true }, front, two) == false,
    "encircled is never an open front")
check(SC.Combat.openFront({}, front, { close = 1, occupiedSectors = 1, immediate = 1 }) == true,
    "alone, one zombie on one side is still an open front")

-- 4. Local pressure is never delegated to a stale plan: a plan built from a's
-- view still reaches b, and an empty threat list yields no plan view at all.
Squad.reset()
check(Squad.forActor(a, nil, snapshot({ b }, {}), "party:squad", tick()) == nil,
    "no threats, no squad view")

-- 5. Stairs (horde plan S1). Nobody steps onto a staircase to fight, and
-- stairs are never an escape square.
local function stairs(x, y, z)
    local square = f.cell:getGridSquare(x, y, z or 0)
    square.HasStairs = function() return true end
    return square
end
local function level(square) square.HasStairs = nil end
local climber = fighter("stair-fighter", 20, 20)
local foot = stairs(21, 20, 0)
check(SC.Combat.stepsOntoStairs(climber, 1, 0) == true, "a step onto a stair tile is refused")
check(SC.Combat.stepsOntoStairs(climber, -1, 0) == false, "a step away from the stairs is allowed")
check(SC.Combat.stepsOntoStairs(climber, 0, 1) == false, "a step along level ground is allowed")
local upstairs = f.actor("stair-upstairs", 20, 22, { z = 1 })
local below = stairs(21, 22, 0)
check(SC.Combat.stepsOntoStairs(upstairs, 1, 0) == true,
    "from a landing, a step over the steps one floor down is refused")
local middle, top = stairs(22, 20, 0), stairs(23, 20, 0)
local onSteps = f.actor("stair-on-steps", 22, 20, {})
check(SC.Combat.stepsOntoStairs(onSteps, 1, 0) == false and SC.Combat.stepsOntoStairs(onSteps, -1, 0) == false,
    "a fighter already on the stairs may move along them to get off")
level(middle) level(top)
local kept = SC.Senses._offStairsForTests({ { square = foot }, { square = f.cell:getGridSquare(19, 20, 0) } })
check(#kept == 1 and kept[1].square ~= foot, "a stair tile is never an escape square")
level(foot) level(below)

Squad.reset()
SC.Combat.primaryWeaponUsable, SC.Navigation.openSegment, SC.ZombieFacts =
    oldUsable, oldOpen, oldFacts
SC_TEST_REPORT = "COMBAT_SQUAD_PASS checks=" .. f.checks()
