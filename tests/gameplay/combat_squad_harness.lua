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

-- 3. A zombie count wobbling at a threshold flips the mode every rebuild.
Squad.reset()
b.square = f.cell:getGridSquare(1, 0, 0)
local crowd = { zombie(2, 1), zombie(2, -1), zombie(-2, 1), zombie(-2, -1) }
local modes, changes, previous = {}, 0, nil
for index = 1, 4 do
    local present = { crowd[1], crowd[2], crowd[3] }
    if index % 2 == 0 then present[4] = crowd[4] end
    local current = Squad.forActor(a, nil, snapshot({ b }, present), "party:squad", tick(260))
    modes[#modes + 1] = current and current.mode or "none"
    if previous ~= nil and current and current.mode ~= previous then changes = changes + 1 end
    previous = current and current.mode
end
-- GAP (phase 3, hysteresis): three zombies against two fighters is engage,
-- four is give_ground, and the mode follows every 250 ms rebuild. Phase 3
-- expects at most one change inside the 1.5 s dwell.
check(changes == 3, "GAP: the squad mode flips on every rebuild: " .. table.concat(modes, ","))

-- 4. Local pressure is never delegated to a stale plan: a plan built from a's
-- view still reaches b, and an empty threat list yields no plan view at all.
Squad.reset()
check(Squad.forActor(a, nil, snapshot({ b }, {}), "party:squad", tick()) == nil,
    "no threats, no squad view")

Squad.reset()
SC.Combat.primaryWeaponUsable, SC.Navigation.openSegment, SC.ZombieFacts =
    oldUsable, oldOpen, oldFacts
SC_TEST_REPORT = "COMBAT_SQUAD_PASS checks=" .. f.checks()
