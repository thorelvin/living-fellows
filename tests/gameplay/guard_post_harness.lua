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
s1.primary, s2.primary = f.item("Base.Crowbar", "Weapon"), f.item("Base.Crowbar", "Weapon")
SC.Commands.issue(s1.id, "guard", { target = landing }, f.player)
SC.Commands.issue(s2.id, "guard", { target = landing }, f.player)
local sp1, sp2 = P.forActor(s1, r1), P.forActor(s2, r2)
check(sp1 and sp2 and sp1.post.kind == "stairs" and sp1.position.z == 1 and sp1.position.y == 0
        and sp2.position.z == 1 and sp2.position.y <= 0,
    "G05 stair guards occupy supported landing positions, never the slope")

check(sp1.position.x < 4 and sp2.position.x > 4 and sp1.position.y == 0 and sp2.position.y == 0,
    "G17 a wide landing gives both front defenders a checked side of the incoming column")
local longWeapon = s1.primary
s1.primary = nil
local shortPost = P.forActor(s1, r1, nil, f.clock + 500)
check(shortPost.position.x == 4 and shortPost.position.y == 0,
    "G38 unarmed or short-reach guards retain the closer landing formation")
s1.primary = longWeapon
square(3, 0, 1).solid = true
local narrow1 = P.forActor(s1, r1, nil, f.clock + 1000)
local narrow2 = P.forActor(s2, r2, nil, f.clock + 1000)
check(narrow1.position.x == 4 and narrow1.position.y == 0 and narrow2.position.y == -1,
    "G32 a blocked landing wing retains the safe single-file fallback")
square(3, 0, 1).solid = false
sp1, sp2 = P.forActor(s1, r1, nil, f.clock + 2000), P.forActor(s2, r2, nil, f.clock + 2000)
local point = P.point({ position = { x = 4, y = 0, z = 1 }, post = sp1.post, rank = 1 })
check(math.floor(point.x) == 4 and math.floor(point.y) == 0 and point.y < 0.3,
    "G23 the front guard leaves weapon room on the protected edge of its landing square")
point = P.point(sp1)
local earlyMove, earlyIntent, oldX, oldY = U.move, nil, s1.getX, s1.getY
U.move = function(_, _, intent) earlyIntent = intent; return true end
s1.square = landing
s1.getX = function() return point.x end
s1.getY = function() return point.y end
P.move(s1, sp1, { stairIncoming = { { actor = {} } } })
U.move, s1.getX, s1.getY = earlyMove, oldX, oldY
check(earlyIntent and earlyIntent.action == "ready_weapon",
    "G18 the stair warning readies a guard's weapon before the attacker reaches its floor")
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
-- Connected-stair warnings stay out of attack targeting; a shove loop opens
-- the landing without clipping through furniture or blocking the second guard.
landing.solid = false
f.clock = f.clock + 20000
local function stairPart(x, y, kind)
    local tile = square(x, y, 0)
    tile.HasStairs = function() return true end
    tile.objects[#tile.objects + 1] = {
        isStairsObject = function() return true end, getType = function() return kind end,
    }
    return tile
end
local mid = stairPart(4, 2, "stairsMN")
stairPart(4, 3, "stairsBN")
local climbing = f.zombie(4, 2)
local height = 0.3
climbing.getZ = function() return height end
mid.moving = { climbing }
local incomingState = {}
f.clock = f.clock + 1000
SC.StairCombat.incoming(s1, incomingState, f.clock)
height, f.clock = 0.45, f.clock + 300
SC.ZombieFacts.reset()
local incoming = SC.StairCombat.incoming(s1, incomingState, f.clock)
check(#incoming == 1 and incoming[1].actor == climbing and incoming[1].arrivingMs < 8000,
    "I01 a rising zombie on the connected middle step is forecast before the last step")
local usable, open = SC.Combat.primaryWeaponUsable, SC.Navigation.openSegment
SC.Combat.primaryWeaponUsable = function() return true end
SC.Navigation.openSegment = function() return true end
SC.CombatSquad.reset()
local warned = SC.CombatSquad.forActor(s1, f.player, {
    allies = { { actor = s2, health = 100 } }, threats = {}, stairIncoming = incoming,
}, "party:stair-test", f.clock)
SC.Combat.primaryWeaponUsable, SC.Navigation.openSegment = usable, open
check(warned and warned.incoming == 1 and warned.active == 0 and warned.target == nil,
    "I02 incoming stair evidence changes the forecast without creating an attack target")
local elsewhere = f.zombie(9, 2)
elsewhere.getZ = function() return height end
mid.moving[#mid.moving + 1] = elsewhere
height, f.clock = 0.5, f.clock + 300
SC.ZombieFacts.reset()
SC.StairCombat.incoming(s1, incomingState, f.clock)
height, f.clock = 0.6, f.clock + 300
SC.ZombieFacts.reset()
local restricted = SC.StairCombat.incoming(s1, incomingState, f.clock)
check(#restricted == 1 and restricted[1].actor == climbing,
    "I03 actors not on the connected column are excluded even from its candidate list")
landing.losBlocked, f.clock = true, f.clock + 300
local hidden = SC.StairCombat.incoming(s1, incomingState, f.clock)
check(#hidden == 0, "I04 a hidden landing cannot reveal climbers through a wall")
landing.losBlocked = false
local safe, safetyReason = SC.Senses.isCompleteObservation({ valid = true, threatCount = 0,
    stairIncoming = incoming, time = f.clock, scanComplete = true,
    scanDiscoveryComplete = true, scanVisualComplete = true })
check(not safe and safetyReason == "danger_nearby",
    "I05 an incoming climber prevents an all-clear without inflating undead attack counts")

r1.senses = { current = { threats = {}, allies = {}, escapeSquares = {} } }
SC.Combat.update(s1, f.player, r1)
local combatState = SC.Combat.peek(s1)
local evidence = { target = climbing, action = "shove", result = "landed", healthBefore = 1, healthAfter = 1 }
SC.StairCombat.observe(s1, combatState, evidence, f.clock)
local one = SC.StairCombat.recovery(s1, r1, {}, f.clock)
SC.StairCombat.observe(s1, combatState, evidence, f.clock + 500)
local draw = SC.StairCombat.recovery(s1, r1, {}, f.clock + 500)
check(not one and draw and r1.guardPost.position and r2.guardPost.position
        and r1.guardPost.position.y == -1 and r2.guardPost.position.y == -2,
    "R01 two non-damaging shoves open the landing and move both guards back together")
local movement, movingTo = SC.Navigation.request
SC.Navigation.request = function(_, goal) movingTo = goal; return true, "moving" end
local previousSquare = s1.square
s1.square = landing
SC.StairCombat.hold(s1, r1, {}, f.clock + 700)
s1.square = previousSquare
SC.Navigation.request = movement
check(movingTo and movingTo:getY() == -1,
    "R02 the reset survives the shoved zombie leaving the attackable floor")
local damaged = { stairShoves = { target = climbing, count = 1, at = f.clock } }
SC.StairCombat.observe(s1, damaged, { target = climbing, action = "attack_melee",
    result = "landed", healthBefore = 1, healthAfter = 0.7 }, f.clock)
check(damaged.stairShoves == nil, "R03 real native damage clears the shove-loop counter")
r1.stairCombat.recovery = nil
for x = 3, 5 do for y = -3, -1 do square(x, y, 1).solid = true end end
combatState.stairShoves = { target = climbing, count = 2, at = f.clock }
local blockedDraw = SC.StairCombat.recovery(s1, r1, {}, f.clock + 1000)
check(blockedDraw == nil and P.stairSetback(s1, { x = 4, y = 0, z = 1, dx = 0, dy = -1 }) == nil,
    "R04 a blocked landing setback never moves a guard into furniture")
for x = 3, 5 do for y = -3, -1 do square(x, y, 1).solid = false end end
local beforeCancel = SC.StairCombat.recovery(s1, r1, {}, f.clock + 1200)
s1.modData.SC_CommandSerial = (s1.modData.SC_CommandSerial or 0) + 1
local canceledDraw = SC.StairCombat.recovery(s1, r1, {}, f.clock + 1300)
check(beforeCancel and not canceledDraw and not r1.stairCombat.recovery,
    "R05 a new command cancels the old stair recovery rather than imposing its movement")
local lip = f.zombie(4, 0, { z = 1 })
local lipState = {}
SC.StairCombat.observe(s2, lipState, { target = lip, action = "shove",
    result = "landed", healthBefore = 1, healthAfter = 1 }, f.clock)
check(lipState.stairShoves and lipState.stairShoves.count == 1,
    "R06 a native shove at the last stride counts even when its victim reaches the landing")
square(4, -2, 1).solid = true
local sideRoom = P.stairInset(s2, r2, 1, f.clock + 1500)
check(sideRoom and r1.guardPost.position.y == -1 and r2.guardPost.position.y == -1
        and r1.guardPost.position.x ~= r2.guardPost.position.x,
    "R07 a cramped landing gives the second guard a verified side position to clear the setback")
square(4, -2, 1).solid = false
local pursuit, paths = {}, 0
climbing.target = s1
climbing.getCurrentStateName = function() return "ZombieIdleState" end
climbing.pathToCharacter = function(_, target) if target == s1 then paths = paths + 1 end end
SC.ZombieFacts.reset()
SC.StairCombat.incoming(s1, pursuit, f.clock + 3000)
SC.StairCombat.incoming(s1, pursuit, f.clock + 5000)
check(paths == 0, "P01 observing a stalled climber leaves its native navigation untouched")
climbing.target = f.player
SC.ZombieFacts.reset()
SC.StairCombat.incoming(s1, pursuit, f.clock + 9000)
check(paths == 0, "P02 stair observation never redirects a zombie targeting someone else")
local peerGoal = SC.StairCombat.resetGoal(s2, r2, {}, f.clock + 1800)
check(peerGoal and not (r2.stairCombat and r2.stairCombat.recovery),
    "R08 the second fighter receives the shared reset goal even without its own shove counter")
local placed = s2.square
s2.square = square(r2.guardPost.position.x, r2.guardPost.position.y, 1)
local centred = U.distance(s2, peerGoal) == 0
local oldX = s2.getX
s2.getX = function() return peerGoal.x + 0.5 end
local short = P.atPosition(s2, r2.guardPost)
s2.getX = oldX
check(centred and not short,
    "R09 arrival uses the square centre so the guard can stop stepping and strike")
s2.square = placed
local waiting = f.zombie(4, 3)
waiting.getZ = function() return 0.2 end
r1.stairCombat.recovery = nil
combatState.stairShoves = { target = climbing, count = 2, at = f.clock + 2100 }
SC.ZombieFacts.reset()
local wave = { threats = {}, stairIncoming = { { actor = waiting } } }
local unsafeDraw = SC.StairCombat.recovery(s1, r1, wave, f.clock + 2100)
check(not unsafeDraw and combatState.stairShoves.count == 2,
    "R10 several standing climbers keep the choke closed rather than flooding the landing")
waiting.onFloor = true
SC.ZombieFacts.reset()
local singleDraw = SC.StairCombat.recovery(s1, r1, wave, f.clock + 2200)
check(singleDraw ~= nil, "R11 a downed climber does not prevent a safe reset against one standing attacker")
local savedPosition = r1.guardPost.position
r1.guardPost.position = nil
local changedLanding = SC.StairCombat.resetGoal(s1, r1, wave, f.clock + 2300)
r1.guardPost.position = savedPosition
check(changedLanding == nil, "R12 an invalidated post cannot reuse its old recovery destination")
local savedPost, plainArrival, priorRequest, savedSquare = r1.guardPost, nil, SC.Navigation.request, s1.square
r1.guardPost, s1.square = nil, landing
SC.Navigation.request = function(_, _, _, intent) plainArrival = intent.arrivalDistance; return true end
SC.StairCombat.hold(s1, r1, wave, f.clock + 2300)
SC.Navigation.request, r1.guardPost, s1.square = priorRequest, savedPost, savedSquare
check(plainArrival and plainArrival < 0.3,
    "R13 a plain Stay reset reaches the same centre tolerance as its holding check")
local front = f.actor("lane-front", 30, 0, { z = 1 })
local rear = f.actor("lane-rear", 30, -1, { z = 1 })
local foe = f.zombie(30, 1, { z = 1 })
local bar = f.item("Base.Crowbar", "Weapon")
bar.getMinAngle = function() return 0.75 end
front.primary = bar
rear.getY = function() return front:getY() - 0.7 end
local lane = { kind = "melee", allies = { rear } }
check(not SC.Combat.friendlyFireBlocked(front, foe, lane),
    "F01 a separated rear guard outside the native forward melee arc does not silence the front fighter")
rear.getY = function() return front:getY() + 0.7 end
local ahead = SC.Combat.friendlyFireBlocked(front, foe, lane)
rear.getY = function() return front:getY() - 0.7 end
check(ahead and SC.Combat.friendlyFireBlocked(front, foe, { kind = "ranged", allies = { rear } }),
    "F02 frontal melee protection and the firearm corridor remain intact")
bar.getMinAngle = function() return -0.5 end
local wide = SC.Combat.friendlyFireBlocked(front, foe, lane)
bar.getMinAngle = nil
check(wide and SC.Combat.friendlyFireBlocked(front, foe, lane),
    "F03 wide or unknown native melee arcs retain the conservative rear protection")
local human = f.actor("stair-human", 4, 2, { z = 0 })
human.getZ = function() return 0.6 end
local humanState = {}
SC.StairCombat.observe(s1, humanState, { target = human, action = "shove",
    result = "landed", healthBefore = 1, healthAfter = 1 }, f.clock)
r1.stairCombat.recovery = nil
combatState.stairShoves = nil
combatState.noEffectTarget, combatState.noEffectCollisions = human, 2
local humanReset = SC.StairCombat.recovery(s1, r1, {}, f.clock + 2500)
check(not humanState.stairShoves and not humanReset,
    "I06 human actors remain outside the zombie stair-exchange recovery")
local stepMove, stepOpen, steppedIntent = U.move, SC.Navigation.openSegment
U.move = function(_, _, intent) steppedIntent = intent; return true end
SC.Navigation.openSegment = function() return true end
local stepActor = f.actor("post-footwork", 40, 40, { z = 1 })
local stepTarget = { actor = f.zombie(40, 42, { z = 1 }), distanceSq = 4 }
local stepPost = { position = { x = 40, y = 40, z = 1 }, post = { kind = "stairs" } }
local stepped, stepWhy = SC.Combat._executeForTests(stepActor, f.player,
    { threats = {} }, stepTarget, {}, { kind = "backstep", moveX = 0, moveY = -1 }, {},
    { guardPost = stepPost })
check(stepped and stepWhy == "guard_combat_step" and steppedIntent.movementTarget
        and (steppedIntent.targetPosition.x - 40.5)^2 + (steppedIntent.targetPosition.y - 40.5)^2 < 0.7^2,
    "G13 fixed guards retain checked weapon spacing inside their post's hold radius")
local closes, closeWhy = SC.Combat._executeForTests(stepActor, f.player,
    { threats = {} }, stepTarget, {}, { kind = "approach", moveX = 1, moveY = 0 }, {},
    { guardPost = stepPost })
check(closes and closeWhy == "guard_combat_step" and steppedIntent.action == "combat_approach"
        and steppedIntent.targetPosition.x < 41.2,
    "G30 a guard may close a short finishing gap while staying inside the post's hold area")
f.clock = f.clock + 500
local floorVictim = f.zombie(41, 40, { z = 1, onFloor = true })
floorVictim.square.hidden, stepActor.square.hidden = false, false
floorVictim.getX = function() return 42 end
local normalFinisher = SC.Combat.groundedFinisher
SC.Combat.groundedFinisher = function() return { kind = "approach", attackKind = "stomp", maximum = 1.2 } end
local followState = { guardPost = stepPost, shoveFollowUp = { target = floorVictim,
    startedAt = f.clock - 500, expires = f.clock + 1500 } }
local follows, followWhy = SC.Combat._tryShoveFollowUpForTests(stepActor, followState,
    { threats = {}, allies = {} }, f.clock, {})
SC.Combat.groundedFinisher = normalFinisher
check(follows and followWhy == "guard_combat_step" and followState.shoveFollowUp ~= nil,
    "G31 a safe short post step retains the native shove finisher window")
SC.Navigation.openSegment = function() return false end
local obstructed = P.combatStep(stepActor, stepPost, {}, stepTarget,
    { kind = "kite", moveX = 1, moveY = 0 })
check(obstructed == nil, "G14 post footwork refuses a blocked segment")
SC.Navigation.openSegment = function() return true end
local belowStep = square(40, 39, 0)
belowStep.HasStairs = function() return true end
stepActor.getY = function() return 40.05 end
local sloped = P.combatStep(stepActor, stepPost, {}, stepTarget,
    { kind = "backstep", moveX = 0, moveY = -1 })
check(sloped == nil, "G15 post footwork never steps over the staircase below the landing")
belowStep.HasStairs = nil
U.move, SC.Navigation.openSegment = stepMove, stepOpen
local capped = {}
for batch = 1, 4 do
    mid.moving = {}
    for i = 1, 8 do
        local passing = f.zombie(4, 2)
        passing.getZ = function() return 0.6 end
        mid.moving[i] = passing
    end
    SC.ZombieFacts.reset()
    SC.StairCombat.incoming(s1, capped, f.clock + 3000 + batch * 300)
end
local retained = 0
for _ in pairs(capped.stairs.known) do retained = retained + 1 end
check(retained == 24, "I07 passing waves cannot grow the retained stair pursuit list beyond its bound")
local coveredPost = { post = { x = 4, y = -1, z = 1, dx = 0, dy = -1, kind = "stairs" },
    position = { x = 4, y = -1, z = 1 } }
s1.square = square(4, -1, 1)
s1.square.room = {}
combatState.guardPost = coveredPost
local firstContact, secondContact = f.zombie(4, 0, { z = 1 }), f.zombie(5, 0, { z = 1 })
local contactView = { threats = { { actor = firstContact }, { actor = secondContact } },
    reachableCloseCount = 2, reachableImmediateCount = 2, reachableThreatSectors = 1,
    escapeSquares = {}, squadPlan = { mode = "engage", supportCount = 1, holds = 2 } }
local normalReadiness = SC.Combat.readiness
local guardSupport, guardRisk = 1, 24
SC.Combat.readiness = function() return { health = 100, support = guardSupport, capacity = 2,
    escapeDanger = 3, internalRisk = guardRisk, footing = { crowd = 0 }, staminaCritical = false } end
coveredPost.withdrawn = true
local exposed = SC.Combat.assessOverrun(s1, contactView, { range = 1.3 }, {})
coveredPost.withdrawn = false
local covered = SC.Combat.assessOverrun(s1, contactView, { range = 1.3 }, {})
check(exposed.overrun and not covered.overrun,
    "G19 a fit supported stair guard can hold two frontal contacts without the generic indoor penalty")
guardSupport, guardRisk = 0, 18
contactView.squadPlan.supportCount = 0
local busyPartner = SC.Combat.assessOverrun(s1, contactView, { range = 1.3 }, {})
check(not busyPartner.overrun,
    "G24 a fit guard keeps its own two-contact capacity when the partner is busy")
local distant = f.zombie(4, -7, { z = 1 })
contactView.threats[#contactView.threats + 1] = { actor = distant }
local ambient = SC.Combat.assessOverrun(s1, contactView, { range = 1.3 }, {})
check(not ambient.overrun, "G26 distant or unreachable onlookers cannot negate the covered stair geometry")
table.remove(contactView.threats)
secondContact.square = square(4, -2, 1)
SC.ZombieFacts.reset()
local flanked = SC.Combat.assessOverrun(s1, contactView, { range = 1.3 }, {})
check(flanked.overrun, "G20 a contact behind the post cancels its covered-stair allowance")
secondContact.square = square(5, 0, 1)
SC.ZombieFacts.reset()
contactView.squadPlan.holds = 1
local wornGuard = SC.Combat.assessOverrun(s1, contactView, { range = 1.3 }, {})
check(wornGuard.overrun, "G25 a one-contact guard does not receive the two-contact stair allowance")
SC.Combat.readiness = normalReadiness
local centreActor = f.actor("centre-post", 50, 50, { z = 1 })
local centrePost = { position = { x = 50, y = 50, z = 1 }, post = { kind = "stairs", dx = 0, dy = -1 } }
centreActor.getX = function() return 50.05 end
centreActor.getY = function() return 50.05 end
check(not P.atPosition(centreActor, centrePost),
    "G21 a calm guard must centre on the landing rather than settle at its corner")
local oldRequest, arrival = SC.Navigation.request
SC.Navigation.request = function(_, _, _, intent) arrival = intent.arrivalDistance; return true end
P.move(centreActor, centrePost, {})
SC.Navigation.request = oldRequest
check(arrival == 0.25, "G22 the navigation arrival radius agrees with the centred guard position")
centrePost.post.kind = "door"
check(P.atPosition(centreActor, centrePost), "G27 ordinary doorway guards retain their original hold radius")
local urgentGuard, urgentRuntime = fighter("urgent-post", 10, 1)
local urgentDoor = doorway(10, 0)
SC.Commands.issue(urgentGuard.id, "guard", { target = urgentDoor }, f.player)
P.forActor(urgentGuard, urgentRuntime)
local urgent = P.observe(urgentGuard, urgentRuntime, { mode = "disengage", capacity = 4, forecast = 9 }, f.clock)
check(urgent, "G28 a decisively overwhelmed post withdraws before the normal dwell delay")
urgentRuntime.guardPost.withdrawn, urgentRuntime.guardPost.disengageSince = false, nil
local moderate = P.observe(urgentGuard, urgentRuntime, { mode = "disengage", capacity = 4, forecast = 6 }, f.clock)
check(not moderate, "G29 marginal forecast pressure still requires a sustained withdrawal decision")
local sharedGuard = fighter("shared-post-a", 10, 10, 1)
local sharedPeer = fighter("shared-post-b", 12, 10, 1)
for _, peer in ipairs({ sharedGuard, sharedPeer }) do
    peer.modData.SC_Order, peer.modData.SC_GuardSide = "guard", { x = 0, y = -1 }
    peer.modData.SC_AnchorX, peer.modData.SC_AnchorY, peer.modData.SC_AnchorZ = 11, 10, 1
end
local personalPost = { position = { x = 10, y = 10, z = 1 },
    post = { x = 11, y = 10, z = 1, dx = 0, dy = -1, kind = "stairs" } }
local personalThreats = {}
for index = 1, 3 do
    local threat = f.zombie(index == 3 and 12 or 10, 11, { z = 1 })
    threat.target = index == 3 and sharedPeer or sharedGuard
    personalThreats[index] = { actor = threat, x = threat:getX(), y = threat:getY(), z = 1 }
end
local sharedView = { threats = personalThreats, allies = { { actor = sharedPeer } },
    reachableImmediateCount = 3, reachableCloseCount = 3, localPressure = 4.5,
    encircled = true, squadPlan = { forecast = 3 } }
SC.ZombieFacts.reset()
local localView = P.combatView(sharedGuard, f.player, personalPost, sharedView)
check(localView ~= sharedView and localView.reachableImmediateCount == 2
        and sharedView.reachableImmediateCount == 3 and localView.threats == personalThreats
        and localView.squadPlan == sharedView.squadPlan and localView.encircled,
    "G33 personal stair pressure shares an ally-owned contact without hiding geometry or squad pressure")
local sharedZombie = personalThreats[3].actor
sharedZombie.square = square(10, 10, 1)
local sharedX, sharedY, peerX = sharedZombie.getX, sharedZombie.getY, sharedPeer.getX
sharedZombie.getX, sharedZombie.getY = function() return 11 end, function() return 10.5 end
sharedPeer.getX = function() return 11.2 end
SC.ZombieFacts.reset()
check(P.combatView(sharedGuard, f.player, personalPost, sharedView) == sharedView,
    "G34 a body-contact zombie counts personally even while targeting the other guard")
sharedZombie.getX, sharedZombie.getY, sharedPeer.getX = sharedX, sharedY, peerX
sharedZombie.square = square(12, 11, 1)
SC.ZombieFacts.reset()
check(P.combatView(sharedGuard, sharedPeer, personalPost, sharedView) == sharedView,
    "G35 a real-player attacker is never deferred as another guard's contact")
sharedZombie.target = sharedPeer
sharedPeer.body.health = 50
SC.ZombieFacts.reset()
check(P.combatView(sharedGuard, f.player, personalPost, sharedView) == sharedView,
    "G36 an injured guard cannot be trusted with a shared contact")
sharedPeer.body.health = 100
personalPost.post.kind = "door"
check(P.combatView(sharedGuard, f.player, personalPost, sharedView) == sharedView,
    "G37 ordinary doorway and open-ground combat retain their full personal observation")

-- One guard cannot keep promising to hold while its partner is repeatedly
-- forced out of the same choke. A short personal sidestep is not a new order.
local withdrawing, wr = fighter("withdraw-post-a", 30, 30)
local covering, cv = fighter("withdraw-post-b", 31, 30)
local exit = doorway(30, 29)
SC.Commands.issue(withdrawing.id,"guard",{target=exit},f.player)
SC.Commands.issue(covering.id,"guard",{target=exit},f.player)
local wp, cp = P.forActor(withdrawing,wr), P.forActor(covering,cv)
local oldPeek = SC.Combat.peek
local personal = {retreating=true,overrun={overrun=true,cause="immediate_count"}}
SC.Combat.peek = function(who) if who==withdrawing then return personal end return oldPeek(who) end
local holding = {mode="engage",capacity=4,forecast=4}
check(not P.observe(withdrawing,wr,holding,10000), "G39 a short personal withdrawal does not abandon a shared post")
personal.overrun.overrun = false
check(not P.observe(withdrawing,wr,holding,13000), "G40 recovery cancels the pending shared withdrawal")
personal.overrun.overrun = true
P.observe(withdrawing,wr,holding,14000)
check(P.observe(withdrawing,wr,holding,17000) and cv.guardPost.withdrawn,
    "G41 sustained personal withdrawal releases both guards even when the squad still says engage")
wp.withdrawn, cv.guardPost.withdrawn, wp.disengageSince = false, false, nil
personal.overrun.cause = "health"
check(P.observe(withdrawing,wr,holding,18000) and cv.guardPost.withdrawn,
    "G42 a wounded retreating guard cannot leave its partner holding the abandoned choke")
SC.Combat.peek = oldPeek
SC_TEST_REPORT = "GUARD_POST_PASS checks=" .. f.checks()
