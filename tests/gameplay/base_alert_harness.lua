-- SPDX-License-Identifier: MIT
-- The camp alarm: who sees, who hears, who wakes, who goes and where.
local SC = SurvivorCompanion
local Alert = SC.BaseAlert
local RealDowntime = SC.Downtime
local checks = 0
local function check(value, message)
    checks = checks + 1
    if not value then error("base alert check " .. checks .. ": " .. message) end
end

-- Sleepers judge danger by ear (SCDowntime, the real module).
do
    local sleeper = { id = "sleeper-eyes" }
    RealDowntime._sleepStateForTests(sleeper, { kind = "rest_bed", sleepStarted = true })
    local seen = { threats = { { x = 3, y = 3 } }, threatCount = 1, immediateCount = 0,
        heardThreats = {}, player = { danger = 1 } }
    check(RealDowntime._dangerForTests(seen, sleeper, 1000) == false,
        "a sleeper does not wake to a zombie it could only have seen")
    seen.heardThreats = { { distanceBand = "near", activity = 2 } }
    check(RealDowntime._dangerForTests(seen, sleeper, 1000) == false,
        "a sleeper sleeps through a zombie shuffling nearby")
    seen.heardThreats = { { distanceBand = "near", activity = 3 } }
    check(RealDowntime._dangerForTests(seen, sleeper, 1000) == true,
        "a zombie thumping nearby wakes a sleeper")
    seen.heardThreats = { { distanceBand = "very_close", activity = 1 } }
    check(RealDowntime._dangerForTests(seen, sleeper, 1000) == true,
        "a zombie right beside the bed wakes a sleeper")
    seen.heardThreats, seen.immediateCount = {}, 1
    check(RealDowntime._dangerForTests(seen, sleeper, 1000) == true,
        "being attacked wakes a sleeper")
    RealDowntime._sleepStateForTests(sleeper, nil)

    local bedder = { id = "bedder", asleepFlag = true }
    function bedder:setAsleep(value) self.asleepFlag = value end
    function bedder:isAsleep() return self.asleepFlag end
    RealDowntime._sleepStateForTests(bedder, { kind = "rest_bed", sleepStarted = true })
    check(RealDowntime.wakeForAlarm(bedder) == true and bedder.asleepFlag == false
            and RealDowntime.peek(bedder).active == nil
            and RealDowntime.peek(bedder).alarmInterruptedSleep == true,
        "the alarm gets a sleeper out of bed through the ordinary cancel")
    check(RealDowntime.wakeForAlarm(bedder) == false, "an awake resident is not woken twice")

    local eligible = RealDowntime._sleepForTests()
    local savedGameTime = getGameTime
    getGameTime = function() return { getWorldAgeHours = function() return 100 end } end
    local early = { lastBedWakeHour = 99.5 }
    local tooSoon, why = eligible(bedder, early, 0.6)
    early.alarmInterruptedSleep = true
    local backToBed = eligible(bedder, early, 0.6)
    getGameTime = savedGameTime
    check(tooSoon == false and why == "sleep_too_soon" and backToBed == true,
        "a sleep the alarm cut short may be finished at once: " .. tostring(why))
end

Alert.reset()
local now = 100000
local squares, actors, duty = {}, {}, {}
local function square(x, y, z)
    local key = x .. ":" .. y .. ":" .. (z or 0)
    local value = squares[key]
    if not value then
        value = { x = x, y = y, z = z or 0 }
        function value:getBuilding() return self.building end
        squares[key] = value
    end
    return value
end
local function actor(id, x, y, z)
    local value = { id = id, x = x, y = y, z = z or 0, traits = {} }
    function value:hasTrait(trait) return self.traits[trait] == true end
    function value:isAsleep() return false end
    actors[id] = value
    return value
end
local function house(x1, y1, x2, y2, token)
    for x = x1, x2 do for y = y1, y2 do square(x, y, 0).building = token end end
end
CharacterTrait = { DEAF = "DEAF", HARD_OF_HEARING = "HARD_OF_HEARING",
    KEEN_HEARING = "KEEN_HEARING" }
local spoken, sounds, routes = {}, {}, {}
local function said(id, topic)
    for _, line in ipairs(spoken) do
        if line.id == id and line.topic == topic then return line end
    end
    return nil
end
SC.GameplayUtil = {
    nowMs = function() return now end,
    config = function() return nil end,
    idOf = function(value) return value.id end,
    position = function(value) return value.x, value.y, value.z end,
    call = function(object, method, ...)
        if object and type(object[method]) == "function" then
            return object[method](object, ...), true
        end
        return nil, false
    end,
    squareOf = function(value)
        return square(math.floor(value.x), math.floor(value.y), value.z)
    end,
    gridSquare = function(x, y, z) return square(x, y, z) end,
    isSquareFree = function(value) return value.blocked ~= true end,
    isValidActor = function(value) return value ~= nil end,
    isDead = function(value) return value.dead == true end,
    resolveActor = function(id) return actors[id] end,
    stableHash = function(value) return #tostring(value) * 97 end,
    moodleLevel = function(value, name) return value.moodles and value.moodles[name] or 0 end,
    say = function(value, line) spoken[#spoken + 1] = { id = value.id, text = line } return true end,
    move = function(value, _, intent) value.lastMove = intent return true end,
    stop = function(value) value.stopped = true return true end,
}
local base = { id = "base:alarm", settings = { defense = "rotation" },
    core = { x = 10, y = 10, z = 0 },
    zones = { { kind = "area", x1 = 0, y1 = 0, x2 = 20, y2 = 20, z = 0 } } }
local watch, roles = {}, {}
SC.BaseLife = {
    active = function() return base end,
    dutyResidentIds = function() return duty end,
    isInside = function(value)
        return (value.z or 0) == 0 and value.x >= 0 and value.x <= 20
            and value.y >= 0 and value.y <= 20
    end,
    guardStatus = function(id) return watch[id] == true end,
    resident = function(id) return { role = roles[id] or "generalist" } end,
    zoneCenter = function(kind)
        return kind == "rally" and { x = 10, y = 10, z = 0 } or nil
    end,
}
local asleep, woken, over = {}, {}, {}
SC.Downtime = {
    peek = function(value)
        if asleep[value.id] then return { active = { kind = "rest_bed", sleepStarted = true } } end
        return nil
    end,
    wakeForAlarm = function(value)
        if not asleep[value.id] then return false end
        asleep[value.id] = nil
        woken[#woken + 1] = value.id
        return true
    end,
    alarmOver = function(value) over[value.id] = true return true end,
}
SC.Dialogue = { say = function(value, topic, _, arguments)
    spoken[#spoken + 1] = { id = value.id, topic = topic, args = arguments }
    return true
end }
SC.Navigation = { requestAny = function(value, targets, mode, intent)
    routes[value.id] = { targets = targets, mode = mode, intent = intent }
    return true, "moving"
end }
SC.Medical = { isDowned = function(value) return value.downed == true end }
addSound = function(_, _, _, _, radius) sounds[#sounds + 1] = radius end
local resident = { recruited = true, order = "base_duty" }
local function sightList(points)
    local threats = {}
    for _, point in ipairs(points) do
        threats[#threats + 1] = { x = point[1], y = point[2], z = 0,
            breaching = point[3] == true }
    end
    return { threats = threats, threatCount = #threats, immediateCount = 0 }
end
local function sight(...) return sightList({ ... }) end

-- How near is "at the camp", and how many make it serious.
check(Alert._distanceToCampForTests(base, 10, 10, 0) == 0
        and Alert._distanceToCampForTests(base, 26, 10, 0) == 5
        and Alert._distanceToCampForTests(base, 26, 10, 1) == math.huge,
    "distance to the camp is measured on its own floor")
check(Alert._assessForTests(base, sight({ 25, 10 })) == "contact",
    "one zombie by the fence is a contact")
check(Alert._assessForTests(base, sight({ 30, 10 })) == nil,
    "a zombie nine tiles out is no business of the camp yet")
check(Alert._assessForTests(base, sight({ 25, 10 }, { 25, 11 }, { 24, 12 })) == "stand_to",
    "three zombies by the fence are a stand-to")
check(Alert._assessForTests(base, sight({ 15, 10 })) == "stand_to"
        and Alert._assessForTests(base, sight({ 22, 10, true })) == "stand_to",
    "a zombie inside the camp, or one breaking in, is a stand-to")
local crowd = {}
for index = 1, 8 do crowd[index] = { 23, index } end
check(Alert._assessForTests(base, sightList(crowd))
        == "fall_back", "a crowd of eight is a fall-back")

-- How far a call carries.
local outdoor = actor("outdoor", 0, 0)
local listener = actor("listener", 9, 0)
check(Alert._audibleForTests(outdoor, listener, 10, false) == true, "a call carries ten tiles outdoors")
listener.x = 11
check(Alert._audibleForTests(outdoor, listener, 10, false) == false, "and no further")
house(40, 0, 50, 10, "house-a")
local indoors = actor("indoors", 44, 5)
local caller = actor("caller", 36, 5)
check(Alert._audibleForTests(caller, indoors, 10, false) == false
        and Alert._audibleForTests(caller, indoors, 20, false) == true,
    "a wall halves how far a voice carries")
check(Alert._audibleForTests(caller, indoors, 20, true) == false,
    "a sleeper behind a wall needs the shout to be closer")
local upstairs = actor("upstairs", 4, 0, 1)
check(Alert._audibleForTests(outdoor, upstairs, 10, false) == true
        and Alert._audibleForTests(outdoor, upstairs, 6, false) == false,
    "a floor between them halves it again")
listener.x = 9
listener.traits.DEAF = true
check(Alert._audibleForTests(outdoor, listener, 20, false) == false, "a deaf resident hears no call")
listener.traits.DEAF, listener.traits.HARD_OF_HEARING = nil, true
check(Alert._audibleForTests(outdoor, listener, 10, false) == false
        and Alert._audibleForTests(outdoor, listener, 20, false) == true,
    "hard of hearing halves the reach")
listener.traits.HARD_OF_HEARING, listener.traits.KEEN_HEARING = nil, true
listener.x = 14
check(Alert._audibleForTests(outdoor, listener, 10, false) == true, "keen hearing extends it")
check(Alert._directionForTests(0, 0, 5, 0) == "on the east side"
        and Alert._directionForTests(0, 0, -3, -4) == "on the northwest side"
        and Alert._directionForTests(0, 0, 0.5, 0.5) == "right here",
    "calls name the side the zombies are on")

-- The camp: a guard on watch at the east fence, two residents awake in the
-- yard, one asleep in the house, one far off in the west corner.
house(10, 8, 13, 14, "house")
local guard = actor("guard", 21, 10)
local near = actor("near", 18, 10)
local yard = actor("yard", 14, 10)
local sleeper = actor("sleeper", 12, 12)
local far = actor("far", 1, 1)
local napper = actor("napper", 19, 11)
duty = { "guard", "near", "yard", "sleeper", "far", "napper" }
watch.guard = true
asleep.sleeper, asleep.napper = true, true

check(Alert.observe(sleeper, nil, sight({ 25, 10 }), resident, now) == false
        and Alert.peek() == nil,
    "a sleeper's eyes raise no alarm")
check(Alert.observe(guard, nil, sight({ 25, 10 }), resident, now) == true,
    "the guard who sees a walker at the fence raises a contact")
local contact = Alert.peek()
check(contact.level == "contact" and contact.spotterId == "guard"
        and said("guard", "camp_alert.contact")
        and said("guard", "camp_alert.contact").args[1] == "on the east side"
        and said("guard", "camp_alert.contact").args[2] == "one"
        and sounds[#sounds] == 5,
    "a contact is a quiet word that names the side and the count")
check(#woken == 0 and Alert.directiveFor(sleeper, now) == nil
        and Alert.directiveFor(napper, now) == nil
        and Alert._audibleForTests(guard, napper, 10, true) == true,
    "a contact wakes nobody, not even a sleeper close enough to hear it")
local guardContact, nearContact = Alert.directiveFor(guard, now), Alert.directiveFor(near, now)
check(guardContact and guardContact.mode == "watch"
        and nearContact and nearContact.mode == "respond"
        and nearContact.score == 70 and nearContact.run == false
        and Alert.directiveFor(yard, now) == nil
        and Alert.directiveFor(far, now) == nil,
    "at a contact the spotter watches and the nearest awake resident backs it up")
local laterGuard = Alert.directiveFor(guard, now + 5000)
check(laterGuard and laterGuard.mode == "watch",
    "a spotter with an awake backup keeps watching instead of waking anyone")
duty = { "guard", "near", "yard", "sleeper", "far" }

-- Two more come into view: the guard shouts a stand-to.
now = now + 1000
check(Alert.observe(guard, nil, sight({ 25, 10 }, { 25, 11 }, { 24, 9 }), resident, now) == true,
    "more zombies escalate the alert")
local stand = Alert.peek()
check(stand.level == "stand_to" and sounds[#sounds] == 20
        and said("guard", "camp_alert.stand_to"),
    "a stand-to is a shout the dead can hear too")
check(woken[1] == "sleeper" and (said("near", "camp_alert.relay")
        or said("yard", "camp_alert.relay")),
    "the sleeper out of reach of the shout is woken by a resident passing it on: "
        .. tostring(woken[1]))
local waking = Alert.directiveFor(sleeper, now)
check(waking and waking.mode == "waking" and waking.score == 90,
    "a woken resident is groggy before it does anything")
check(Alert.act(sleeper, nil, waking, {}) == true and sleeper.stopped == true
        and said("sleeper", "camp_alert.woken"),
    "it stays where it is a moment and says it is up")
now = now + 7000
local afterGrog = Alert.directiveFor(sleeper, now)
check(afterGrog and afterGrog.mode == "stand_to",
    "the third resident told stands to while the nearest two answer: "
        .. tostring(afterGrog and afterGrog.mode))
local nearOrder = Alert.directiveFor(near, now)
local yardOrder = Alert.directiveFor(yard, now)
check(nearOrder.mode == "respond" and yardOrder.mode == "respond"
        and nearOrder.score == 88 and nearOrder.run == true,
    "under the rotating watch the two nearest answer a stand-to, running")
check(Alert.directiveFor(far, now) and Alert.directiveFor(far, now).mode == "stand_to",
    "the resident across the camp heard the call passed on, and stands to")

-- Where they go: beside the guard, on the camp side, spread out.
local rally = Alert._slotsForTests(guard)
local campSide = #rally >= 3
for _, spot in ipairs(rally) do
    if spot.x >= guard.x or not SC.BaseLife.isInside(spot) then campSide = false end
end
check(campSide, "rally squares are beside the guard, away from the zombies and inside the camp")
yard.x = 15
check(Alert.act(yard, nil, yardOrder, {}) == true and routes.yard
        and routes.yard.mode == "run" and routes.yard.intent.urgent ~= true
        and routes.yard.intent.action == "move_to_alert_rally"
        and #routes.yard.targets == #rally
        and said("yard", "camp_alert.coming"),
    "a responder runs to the guard and says it is coming")
near.x = 19
check(select(2, Alert.act(near, nil, Alert.directiveFor(near, now), {})) == "base_alert_arrived"
        and near.lastMove and near.lastMove.action == "face_alert"
        and Alert.directiveFor(near, now).mode == "hold",
    "beside the guard a responder holds, facing the threat")
yard.x, yard.y = 25, 7
routes.yard = nil
local _, forwardReason = Alert.act(yard, nil, Alert.directiveFor(yard, now), {})
check(forwardReason == "base_alert_holding_forward" and routes.yard == nil
        and yard.lastMove and yard.lastMove.action == "face_alert",
    "a responder already nearer the zombies than the caller holds there instead of walking away: "
        .. tostring(forwardReason))
yard.x, yard.y = 15, 10

-- Every wait has a deadline.
for _ = 1, 4 do
    now = now + 15000
    Alert.observe(guard, nil, sight({ 25, 10 }, { 25, 11 }, { 24, 9 }), resident, now)
end
check(Alert.directiveFor(yard, now).mode == "hold",
    "a responder that has not arrived after a minute holds where it is")
check(Alert.directiveFor(guard, now) == nil,
    "the spotter goes back to its work after watching for a while")
for _ = 1, 5 do
    now = now + 15000
    Alert.observe(guard, nil, sight({ 25, 10 }, { 25, 11 }, { 24, 9 }), resident, now)
end
check(Alert.directiveFor(near, now) == nil and Alert.directiveFor(yard, now) == nil
        and Alert.directiveFor(sleeper, now) == nil,
    "holding and standing to have their own limits")

-- Quiet for a minute: all clear.
now = now + 61000
Alert.pulse(now)
check(Alert.peek() == nil and Alert.lastCleared.reason == "clear"
        and said("guard", "camp_alert.clear") and over.sleeper == true,
    "after a quiet minute the guard calls all clear and the woken may go back to bed")

-- A resident woken minutes ago is not woken again for the next stand-to.
now = now + 1000
asleep.sleeper, woken = true, {}
sleeper.x, sleeper.y = 19, 12
Alert.observe(guard, nil, sight({ 25, 10 }, { 25, 11 }, { 24, 9 }), resident, now)
check(#woken == 0 and Alert.directiveFor(sleeper, now) == nil,
    "a resident woken by the last alarm is left to sleep through the next stand-to")

-- A crowd: everybody falls back to the rally point.
now = now + 1000
Alert.observe(guard, nil, sightList(crowd), resident, now)
check(Alert.peek().level == "fall_back" and woken[1] == "sleeper",
    "a fall-back wakes even a resident woken minutes ago")
now = now + 7000
local back = Alert.directiveFor(near, now)
check(back.mode == "fall_back" and back.score == 96
        and Alert.directiveFor(guard, now).mode == "fall_back",
    "everyone told falls back, the spotter too")
near.x, near.y = 18, 10
Alert.act(near, nil, back, {})
local toRally = routes.near
local aroundRally = toRally and toRally.intent.action == "move_to_alert_fallback"
    and #toRally.targets == 9
for _, spot in ipairs(toRally and toRally.targets or {}) do
    if math.abs(spot.x - 10) > 1 or math.abs(spot.y - 10) > 1 then aroundRally = false end
end
check(aroundRally and toRally.mode == "run" and toRally.intent.urgent == true,
    "falling back means running for the squares around the rally point")

Alert.pulse(now + 70000)
now = now + 70000

-- A walker pacing behind the fence for ten minutes does not hold the camp.
spoken = {}
now = now + 1000
Alert.observe(guard, nil, sight({ 25, 10 }), resident, now)
for _ = 1, 41 do
    now = now + 15000
    Alert.observe(guard, nil, sight({ 25, 10 }), resident, now)
end
check(Alert.lastCleared.reason == "timeout" and Alert.peek() == nil,
    "an alert ends after its time limit")
now = now + 15000
check(Alert.observe(guard, nil, sight({ 25, 10 }), resident, now) == false and Alert.peek() == nil,
    "and the same walker does not raise it again at once")
check(Alert.observe(guard, nil, sight({ 25, 10 }, { 25, 11 }, { 24, 9 }), resident, now) == true
        and Alert.peek().level == "stand_to",
    "a worse sighting still does")

-- Policies: role-based sends only guards.
Alert.pulse(now + 70000)
now = now + 70000
base.settings.defense = "role_based"
watch.guard = false
roles.yard = "guard"
asleep.sleeper = nil
yard.x, yard.y = 15, 10
Alert.observe(near, nil, sight({ 25, 10 }, { 25, 11 }, { 24, 9 }), resident, now)
check(Alert.directiveFor(yard, now).mode == "respond"
        and Alert.directiveFor(guard, now).mode == "stand_to",
    "under role-based defence a guard answers and the others stand to")
roles.yard, roles.guard = nil, "guard"
Alert.pulse(now + 70000)
now = now + 70000
Alert.observe(guard, nil, sight({ 25, 10 }, { 25, 11 }, { 24, 9 }), resident, now)
local loneSleeper, loneNear, loneYard = Alert.directiveFor(sleeper, now),
    Alert.directiveFor(near, now), Alert.directiveFor(yard, now)
check(loneSleeper and loneSleeper.mode == "respond"
        and loneNear and loneNear.mode == "stand_to"
        and loneYard and loneYard.mode == "stand_to",
    "when the only guard is the one who saw them, the nearest resident still comes")
roles.guard = nil
base.settings.defense = "all_hands"
Alert.pulse(now + 70000)
now = now + 70000
Alert.observe(near, nil, sight({ 25, 10 }, { 25, 11 }, { 24, 9 }), resident, now)
check(Alert.directiveFor(yard, now).mode == "respond"
        and Alert.directiveFor(guard, now).mode == "respond",
    "under all hands everyone told answers")
guard.downed = true
Alert.pulse(now + 70000)
now = now + 70000
Alert.observe(near, nil, sight({ 25, 10 }, { 25, 11 }, { 24, 9 }), resident, now)
check(Alert.directiveFor(guard, now).mode == "stand_to",
    "a downed resident stands to instead of answering")
guard.downed = nil

-- A lone guard at night: nobody awake heard the quiet word, so it walks over
-- and wakes the nearest sleeper by hand, then takes it back to its post.
Alert.reset()
base.settings.defense = "rotation"
duty = { "lone", "bunk", "cot" }
local lone = actor("lone", 21, 10)
local bunk = actor("bunk", 12, 12)
local cot = actor("cot", 2, 2)
watch = { lone = true }
asleep = { bunk = true, cot = true }
woken, routes, spoken = {}, {}, {}
Alert.observe(lone, nil, sight({ 25, 10 }), resident, now)
local loneFirst = Alert.directiveFor(lone, now)
check(Alert.peek().level == "contact" and Alert.peek().needsBackup == true
        and loneFirst and loneFirst.mode == "watch",
    "a lone guard first keeps its eyes on the walker")
now = now + 5000
local shakeOrder = Alert.directiveFor(lone, now)
check(shakeOrder and shakeOrder.mode == "shake" and shakeOrder.targetId == "bunk",
    "then goes to wake the nearest sleeper: " .. tostring(shakeOrder and shakeOrder.targetId))
local soundsBefore = #sounds
check(Alert.act(lone, nil, shakeOrder, {}) == true and routes.lone
        and routes.lone.mode == "walk" and routes.lone.intent.action == "move_to_alert_wake"
        and #routes.lone.targets > 0 and #woken == 0 and #sounds == soundsBefore,
    "it walks there quietly")
lone.x, lone.y = 13, 12
local _, shookReason = Alert.act(lone, nil, Alert.directiveFor(lone, now), {})
check(shookReason == "base_alert_shook_awake" and woken[1] == "bunk" and #woken == 1
        and asleep.cot == true and said("lone", "camp_alert.shake")
        and #sounds == soundsBefore,
    "beside the bed it wakes that one sleeper with a word, and no shout: " .. tostring(shookReason))
local bunkWaking = Alert.directiveFor(bunk, now)
check(bunkWaking and bunkWaking.mode == "waking", "the one shaken awake is groggy first")
now = now + 7000
local bunkOrder = Alert.directiveFor(bunk, now)
check(bunkOrder and bunkOrder.mode == "respond" and bunkOrder.score == 70,
    "then it backs the guard up")
local backOrder = Alert.directiveFor(lone, now)
check(backOrder and backOrder.mode == "return" and backOrder.origin.x == 21,
    "the guard heads back to its post")
Alert.act(lone, nil, backOrder, {})
check(routes.lone.intent.action == "move_to_alert_post", "walking back to where it stood")
lone.x, lone.y = 21, 10
local _, backReason = Alert.act(lone, nil, Alert.directiveFor(lone, now), {})
local watching = Alert.directiveFor(lone, now)
check(backReason == "base_alert_back_on_watch" and watching and watching.mode == "watch",
    "and watches again from there: " .. tostring(backReason))
local line = Alert.statusLine(function(key, a, b, c, d)
    return key .. "|" .. tostring(a) .. "|" .. tostring(b) .. "|" .. tostring(c) .. "|" .. tostring(d)
end, function(id) return id == "lone" and "Lone Guard" or nil end, now)
check(line == "UI_SC_Base_CampAlarm_contact|one|on the east side|Lone Guard|1",
    "the Base tab names the level, count, side, spotter and responders: " .. tostring(line))

-- Next time it prefers a sleeper the alarm has not just woken, and gives up
-- after half a minute if it cannot get there.
Alert.pulse(now + 40000)
now = now + 40000
check(Alert.statusLine(function() return "x" end, nil, now) == nil, "a quiet camp shows no alarm line")
asleep.bunk = true
lone.x, lone.y = 21, 10
Alert.observe(lone, nil, sight({ 25, 10 }), resident, now)
now = now + 5000
local second = Alert.directiveFor(lone, now)
check(second and second.mode == "shake" and second.targetId == "cot",
    "a lone guard wakes a rested sleeper before one woken minutes ago: "
        .. tostring(second and second.targetId))
Alert.act(lone, nil, second, {})
for _ = 1, 2 do
    now = now + 15000
    Alert.observe(lone, nil, sight({ 25, 10 }), resident, now)
end
now = now + 1000
local _, giveUpReason = Alert.act(lone, nil, Alert.directiveFor(lone, now), {})
local afterGiveUp = Alert.directiveFor(lone, now)
check(giveUpReason == "base_alert_shake_timeout" and afterGiveUp and afterGiveUp.mode == "return"
        and asleep.cot == true,
    "a wake it cannot finish in half a minute is given up: " .. tostring(giveUpReason))
Alert.reset()

-- Elsewhere: no camp, no alarm.
Alert.reset()
local savedActive = SC.BaseLife.active
SC.BaseLife.active = function() return nil end
check(Alert.observe(guard, nil, sight({ 25, 10 }), resident, now) == false and Alert.peek() == nil,
    "without a camp there is no alarm")
SC.BaseLife.active = savedActive
check(Alert.observe(guard, nil, sight({ 25, 10 }), { recruited = true, order = "follow" }, now) == false,
    "a follower is not a camp resident")
Alert.reset()

SC_TEST_REPORT = "BASE_ALERT_PASS checks=" .. checks
