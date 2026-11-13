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
-- GAP (phase 1, single spending): b and c each hold a zombie of their own,
-- yet both count as a's support. Phase 1 expects 0.
check(view.supportCount == 2,
    "GAP: busy fighters count as support: " .. tostring(view.supportCount))

-- 2. First come, first served. a is nearest to both zombies, b reaches only
-- the first one, so the second is left with nobody.
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
-- GAP (phase 2, cover before doubling): a takes the first zombie and b is
-- left without a target although it could take that one and free a for the
-- second. Phase 2 expects a -> second, b -> first.
check(viewA.target == first and viewB.target == nil,
    "GAP: greedy assignment leaves the second zombie uncovered: "
        .. tostring(viewA.target == first) .. "/" .. tostring(viewB.target))

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
