-- SPDX-License-Identifier: MIT
-- Explicit posts use real command, topology, decision and combat boundaries.
local SC, f = SurvivorCompanion, SurvivorCompanion.TestFixture
local P, U, check = SC.GuardPost, SC.GameplayUtil, f.check
local function square(x, y, z) return f.cell:getGridSquare(x, y, z or 0) end
local function fighter(id, x, y, z)
    local actor = f.actor(id, x, y, { z = z })
    f.registry[id] = { id = id, actor = actor, recruited = true, runtime = {} }
    return actor, f.registry[id].runtime
end
SC.Registry.records = function()
    local rows = {}; for _, record in pairs(f.registry) do
        if record.actor then rows[#rows + 1] = record end
    end; return rows
end
local function doorway(x, y)
    local from, to = square(x, y), square(x, y - 1)
    local door = { __class = "IsoDoor" }
    function door:getSquare() return from end
    function door:getNorth() return true end
    function door:isOpen() return true end
    function door:isDoor() return true end
    function from:getDoorTo(other) if other == to then return door end end
    function to:getDoorTo(other) if other == from then return door end end
    return from, door
end
local a, ar = fighter("choke-a", 0, 1)
local b, br = fighter("choke-b", 1, 1)
local c, cr = fighter("choke-c", -1, 1)
local anchor = doorway(0, 0)
local accepted = SC.Commands.issue(a.id, "guard", { target = anchor }, f.player)
check(accepted and a.modData.SC_Order == "guard" and a.modData.SC_GuardSide
        and a.modData.SC_GuardSide.y == 1 and a.modData.SC_AnchorY == 0,
    "G01 doorway order records the protected side")
SC.Commands.issue(b.id, "guard", { target = anchor }, f.player)
SC.Commands.issue(c.id, "guard", { target = anchor }, f.player)
b.modData.SC_Group = "another-squad"
local pa, pb, pc = P.forActor(a, ar), P.forActor(b, br), P.forActor(c, cr)
check(pa.position.y == 0 and pb.position.y == 1 and pc.position.y == 2
        and pa.rank == 1 and pb.rank == 2 and pc.rank == 3,
    "G02 id-ordered doorway guards hold the threshold then one and two metres behind")

local command, state = SC.Commands.effective(a), { guardPatrolDue = 0 }
a.square = anchor
f.clock = f.clock + 60000
local worked, why = SC.Decision._doTacticalForTests(a, f.player, ar, command,
    { threats = {}, escapeSquares = {} }, state)
check(worked and why == "guard_choke_holding" and state.guardPatrolTarget == nil,
    "G03 a doorway post never starts the patrol even after its timer expires")
check(a.lastIntent and a.lastIntent.action == "face_alert" and a.lastIntent.stableFacing
        and a.lastIntent.targetPosition.y < 0,
    "G12 a calm guard watches the approach rather than facing away from its post")

local plain, plainRuntime = fighter("plain-guard", 8, 4)
SC.Commands.issue(plain.id, "guard", { target = square(8, 4) }, f.player)
local plainState = { guardPatrolDue = 0 }
local plainOk, _, plainWhy = pcall(SC.Decision._doTacticalForTests, plain, f.player, plainRuntime,
    SC.Commands.effective(plain), { threats = {}, escapeSquares = {} }, plainState)
check(plainOk and plain.modData.SC_GuardSide == nil and plainState.guardPatrolTarget ~= nil
        and plainWhy ~= "guard_choke_holding",
    "G04 a plain guard square retains its ordinary patrol")

local landing = square(4, 0, 1)
local top = square(4, 1, 0)
top.HasStairs = function() return true end
top.objects[#top.objects + 1] = {
    isStairsObject = function() return true end, getType = function() return "stairsTN" end,
}
local s1, r1 = fighter("stair-a", 4, -1, 1)
local s2, r2 = fighter("stair-b", 5, -1, 1)
SC.Commands.issue(s1.id, "guard", { target = landing }, f.player)
SC.Commands.issue(s2.id, "guard", { target = landing }, f.player)
local sp1, sp2 = P.forActor(s1, r1), P.forActor(s2, r2)
check(sp1 and sp2 and sp1.post.kind == "stairs" and sp1.position.z == 1 and sp1.position.y == 0
        and sp2.position.z == 1 and sp2.position.y == -1,
    "G05 stair guards occupy the landing and its protected side, never the slope")

local exported = SC.Commands.export(a)
local replacement, rr = fighter("restored-choke", 0, -1)
local restored = SC.Commands.restore(replacement, { id = replacement.id, actor = replacement,
    recruited = true, state = { order = { current = "guard", anchor = { x = 0, y = 0, z = 0 },
        guardSide = exported.guardSide } } })
local rp = P.forActor(replacement, rr)
check(restored and rp and rp.post.dy == 1 and replacement.modData.SC_GuardSide.y == 1,
    "G06 command restoration preserves the original side rather than guessing from the new position")

local previousMove, intent = U.move
U.move = function(_, _, request) intent = request; return true, "accepted" end
local foe = f.zombie(0, -3)
local target = { actor = foe, distanceSq = 9 }
local held, heldWhy = SC.Combat._executeForTests(a, f.player, { threats = {} }, target,
    { range = 1.2, equipped = true }, { kind = "approach" }, command, { guardPost = pa })
U.move = previousMove
check(held and heldWhy == "hold_range" and intent.action == "ready_weapon",
    "G07 a choke defender waits for reach instead of approaching away from its post: "
        .. tostring(held) .. "/" .. tostring(heldWhy) .. "/" .. tostring(intent and intent.action))

local previousRequest, requested = SC.Navigation.request
SC.Navigation.request = function(_, goal) requested = goal; return true, "returning" end
a.square = square(3, 3)
SC.Combat._executeForTests(a, f.player, { threats = {} }, target,
    { range = 1.2, equipped = true }, { kind = "approach" }, command, { guardPost = pa })
SC.Navigation.request = previousRequest
check(requested == anchor, "G08 a displaced guard returns to its post instead of chasing")
a.square = anchor

P.observe(a, ar, { mode = "disengage" }, f.clock)
local brief = P.observe(a, ar, { mode = "disengage" }, f.clock + 1000)
P.observe(a, ar, { mode = "engage" }, f.clock + 1500)
P.observe(a, ar, { mode = "disengage" }, f.clock + 2000)
local long = P.observe(a, ar, { mode = "disengage" }, f.clock + 4600)
f.clock = f.clock + 4600
local released = P.release(a, f.player, ar.guardPost)
check(not brief and long and released and a.modData.SC_Order == "retreat" and br.guardPost.withdrawn,
    "G09 sustained disengagement releases the whole post toward the player; a brief change does not")

landing.solid = true
local blocked = P.forActor(s1, r1, nil, f.clock + 10000)
local waiting, waitWhy = P.move(s1, blocked, {})
check(blocked and blocked.position == nil and waiting and waitWhy == "guard_choke_no_room",
    "G10 blocked or missing choke geometry holds safely instead of reverting to patrol")
local candidates = SC.Decision._evaluateForTests(b, f.player, { threats = {}, allies = {}, threatCount = 0,
    immediateCount = 0, escapeSquares = {} }, SC.Commands.effective(b),
    { health = 100, bleedingCount = 0 }, {}, {}, f.clock + 10000)
local tactical
for _, candidate in ipairs(candidates) do if candidate.kind == "tactical" then tactical = candidate end end
check(tactical and candidates[1] == tactical,
    "G11 the decision scheduler keeps a calm choke guard on its post: "
        .. tostring(b.modData.SC_Order) .. "/" .. tostring(tactical and tactical.score)
        .. "/" .. tostring(SC.Commands.effective(b).order))
SC_TEST_REPORT = "GUARD_POST_PASS checks=" .. f.checks()
