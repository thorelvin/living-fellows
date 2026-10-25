-- SPDX-License-Identifier: MIT
-- Expedition and work-order voice: line rules, pacing, eligibility, the
-- result mappings and two-person crew exchanges. Speech is captured, never
-- shown; every decision is driven by a fake clock and fixed random rolls.

local SC = SurvivorCompanion
local U, Dialogue, Voice, Lines = SC.GameplayUtil, SC.Dialogue, SC.WorkVoice, SC.WorkVoiceLines
local checks = 0
local function check(value, message)
    checks = checks + 1
    if not value then error("work voice check " .. checks .. ": " .. tostring(message)) end
end

-- ---------------------------------------------------------------------------
-- Fixture
-- ---------------------------------------------------------------------------

local clock, rollValue, pickValue = 100000, 0, 0
local overrides = {}
local spoken = {}
local actors = {}
local configLookup = U.config
U.config = function(key)
    if overrides[key] ~= nil then return overrides[key] end
    return configLookup(key)
end
U.nowMs = function() return clock end
U.isDead = function(actor) return actor == nil or actor.dead == true end
U.isValidActor = function(actor) return actor ~= nil and actor.dead ~= true and actor.gone ~= true end
U.idOf = function(actor) return actor and actor.id end
U.nameOf = function(actor) return actor and actor.name end
U.resolveActor = function(id) return actors[id] end
U.distance = function(a, b)
    if not a or not b then return math.huge end
    return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
end
U.say = function(actor, line)
    spoken[#spoken + 1] = { actor = actor, line = line, at = clock }
    return true
end
function ZombRand(count)
    if count == 100 then return rollValue end
    return pickValue % count
end

local function actor(id, x, y, voice)
    local value = { id = id, name = id:sub(1, 1):upper() .. id:sub(2), x = x, y = y, z = 0,
        voice = voice or "practical" }
    function value:isAsleep() return self.asleep == true end
    function value:getX() return self.x end
    function value:getY() return self.y end
    function value:getZ() return self.z end
    actors[id] = value
    return value
end
local player = actor("player", 0, 0)
function getSpecificPlayer(index) if index == 0 then return player end return nil end
SC.Commands = { peek = function(target)
    return { recruited = target ~= player, personality = target.voice }
end }
SC.Registry = { byId = function(id)
    local target = actors[id]
    if not target then return nil end
    return { actor = target, runtime = { snapshot = target.snapshot } }
end }

local function reset()
    Voice.reset()
    if Dialogue.reset then Dialogue.reset() end
    spoken, overrides = {}, {}
    rollValue, pickValue = 0, 0
    clock = clock + 3600000
end
local function last() return spoken[#spoken] end
local function inPool(topic, line)
    local pool = Dialogue._poolForTests(topic)
    for _, rows in pairs(pool or {}) do
        if type(rows) == "table" then
            for _, entry in ipairs(rows) do
                if entry == line or type(entry) == "table" and (entry[1] == line or entry.clean == line) then
                    return true
                end
            end
        end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Line rules
-- ---------------------------------------------------------------------------

local roughWords = { "damn", "damned", "dammit", "goddamn", "hell", "shit", "shitty",
    "bullshit", "fuck", "fucking", "fucked", "ass", "asses", "dumbass",
    "bastard", "bastards", "bitch", "christ" }
local function rough(line)
    local lower = string.lower(line)
    for _, word in ipairs(roughWords) do
        if string.find(lower, "%f[%a]" .. word .. "%f[%A]") then return word end
    end
    return nil
end
local problems = {}
local function lintText(text, where, allowName)
    if type(text) ~= "string" or text == "" then problems[#problems + 1] = where .. ": empty" return end
    if string.find(text, "[^\032-\126]") or string.find(text, '"', 1, true)
        or string.find(text, "^%s") or string.find(text, "%s$") or string.find(text, "  ", 1, true) then
        problems[#problems + 1] = where .. ": format: " .. text
    end
    local words = 0
    for _ in string.gmatch(text, "%S+") do words = words + 1 end
    if words > 15 then problems[#problems + 1] = where .. ": " .. words .. " words: " .. text end
    for marker in string.gmatch(text, "%%(%d+)") do
        if not allowName or marker ~= "1" then problems[#problems + 1] = where .. ": %" .. marker end
    end
    if string.find(text, "%%[^%d]") or string.find(text, "%%$") then
        problems[#problems + 1] = where .. ": stray percent: " .. text
    end
end
local function lintEntry(entry, where, seen, allowName)
    if type(entry) == "string" then
        lintText(entry, where, allowName)
        if rough(entry) then problems[#problems + 1] = where .. ": rough word without clean twin: " .. entry end
        if seen[entry] then problems[#problems + 1] = where .. ": duplicate: " .. entry end
        seen[entry] = true
    elseif type(entry) == "table" and type(entry[1]) == "string" then
        lintText(entry[1], where, allowName)
        lintText(entry.clean, where .. ".clean", allowName)
        if not rough(entry[1]) then problems[#problems + 1] = where .. ": twin without rough word: " .. entry[1] end
        if type(entry.clean) == "string" and rough(entry.clean) then
            problems[#problems + 1] = where .. ": rough clean twin: " .. entry.clean
        end
        if seen[entry[1]] or seen[entry.clean] then
            problems[#problems + 1] = where .. ": duplicate: " .. entry[1]
        end
        seen[entry[1]], seen[tostring(entry.clean)] = true, true
    else
        problems[#problems + 1] = where .. ": malformed entry"
    end
end
local actionTopics, roughCount, lineCount = 0, 0, 0
for topic, pool in pairs(Lines.POOLS) do
    actionTopics = actionTopics + 1
    local seen = {}
    for key, rows in pairs(pool) do
        for index, entry in ipairs(rows) do
            lintEntry(entry, topic .. "." .. key .. "." .. index, seen, false)
            lineCount = lineCount + 1
            if type(entry) == "table" then roughCount = roughCount + 1 end
        end
    end
    if #(pool.common or {}) < 4 then problems[#problems + 1] = topic .. ": fewer than four common lines" end
    for _, voice in ipairs({ "brave", "cautious", "caring", "practical" }) do
        if #Dialogue._candidatesForTests(pool, voice, "steady", false) < 4 then
            problems[#problems + 1] = topic .. ": " .. voice .. " has fewer than four lines"
        end
    end
    check(Dialogue.has(topic), "action pool registers with dialogue: " .. topic)
end
local beatCount = 0
for context, beats in pairs(Lines.BANTER) do
    if #beats < 10 then problems[#problems + 1] = context .. ": fewer than ten beats" end
    local opens, replies, closes = {}, {}, {}
    for index, beat in ipairs(beats) do
        beatCount = beatCount + 1
        local where = "banter." .. context .. "." .. index
        lintEntry(beat.open, where .. ".open", opens, true)
        if type(beat.reply) ~= "table" or #beat.reply < 2 then
            problems[#problems + 1] = where .. ": needs two replies"
        end
        for replyIndex, reply in ipairs(beat.reply or {}) do
            lintEntry(reply, where .. ".reply." .. replyIndex, replies, true)
            lineCount = lineCount + 1
        end
        if beat.close ~= nil then lintEntry(beat.close, where .. ".close", closes, true) end
    end
    check(Dialogue.has("voice.banter." .. context .. ".open")
        and Dialogue.has("voice.banter." .. context .. ".reply"),
        "banter beats register aggregate pools for the shared lint: " .. context)
end
for _, problem in ipairs(problems) do print("WORK_VOICE_LINT " .. problem) end
check(#problems == 0, "every work and expedition line obeys the line rules: "
    .. #problems .. "\n" .. table.concat(problems, "\n"))
check(actionTopics >= 50 and beatCount >= 80 and lineCount >= 600 and roughCount >= 40,
    "the layer is broad: topics=" .. actionTopics .. " beats=" .. beatCount
        .. " lines=" .. lineCount .. " rough=" .. roughCount)
local events, groups, classes = Voice._eventsForTests()
for _, group in pairs(groups) do
    check(Dialogue.has("voice.job.start." .. group) and Dialogue.has("voice.job.done." .. group),
        "every job group has start and done lines: " .. group)
end
for _, class in pairs(classes) do
    check(Dialogue.has("voice.expedition.turn_home." .. class), "every return class has lines: " .. class)
end
check(Dialogue.has("voice.expedition.turn_home.generic"), "unknown return reasons have a generic line")
for event in pairs(events) do
    if string.sub(event, 1, 4) ~= "job." and event ~= "expedition.turn_home" then
        check(Dialogue.has("voice." .. event), "every paced event has a pool: " .. event)
    end
end

-- ---------------------------------------------------------------------------
-- Pacing
-- ---------------------------------------------------------------------------

reset()
local cutter, hauler = actor("cutter", 5, 0), actor("hauler", 7, 0)
local ok, topic = Voice.cue(cutter, "wood.timber")
check(ok and topic == "voice.wood.timber" and last().actor == cutter
    and inPool("voice.wood.timber", last().line), "a calm, heard cutter calls the fall: " .. tostring(topic))
ok, topic = Voice.cue(hauler, "wood.haul")
check(not ok and topic == "work_voice_party_gap", "nobody talks over the last line: " .. tostring(topic))
clock = clock + 7000
ok, topic = Voice.cue(hauler, "wood.timber")
check(not ok and topic == "work_voice_topic_gap", "a second tree inside the gap stays unannounced")
ok, topic = Voice.cue(hauler, "wood.haul")
check(ok and last().actor == hauler, "another topic is free after the party gap")
clock = clock + 14000
ok, topic = Voice.cue(cutter, "wood.timber")
check(not ok and topic == "work_voice_cooldown", "the same speaker waits out its own cooldown")
clock = clock + 40000
ok = Voice.cue(cutter, "wood.timber")
check(ok, "the cooldown ends")

reset()
cutter, hauler = actor("cutter", 5, 0), actor("hauler", 7, 0)
rollValue = 99
ok, topic = Voice.cue(cutter, "wood.chop")
check(not ok and topic == "work_voice_roll" and #spoken == 0, "a missed roll stays silent")
rollValue = 0
ok, topic = Voice.cue(cutter, "wood.chop")
check(not ok and topic == "work_voice_cooldown",
    "a missed roll still spends the cooldown, so a repeated result is not rerolled")

reset()
cutter = actor("cutter", 5, 0)
cutter.snapshot = { threatCount = 1 }
ok, topic = Voice.cue(cutter, "wood.timber")
check(not ok and topic == "work_voice_danger", "nobody chats with a zombie in sight")
cutter.snapshot = nil
ok = Voice.cue(cutter, "wood.timber")
check(ok, "danger does not spend the cooldown")
clock = clock + 120000
cutter.asleep = true
ok, topic = Voice.cue(cutter, "wood.rest")
check(not ok and topic == "work_voice_asleep", "sleepers say nothing")
cutter.asleep = false
Dialogue.emitResolved(cutter, "other.topic", "Something else entirely.")
ok, topic = Voice.cue(cutter, "wood.rest")
check(not ok and topic == "work_voice_speaker_busy", "a speaker who just spoke keeps quiet")
clock = clock + 13000
ok = Voice.cue(cutter, "wood.rest")
check(ok, "the quiet period ends")

reset()
local far = actor("far", 300, 0)
ok, topic = Voice.cue(far, "wood.timber")
check(not ok and topic == "work_voice_unheard", "speech nobody can see is not spent")
SC.ViewSession = { owner = function() return "expedition" end }
ok = Voice.cue(far, "wood.timber")
check(ok, "an open companion view carries the crew's voices")
SC.ViewSession = nil
overrides.workVoiceEnabled = false
clock = clock + 600000
ok, topic = Voice.cue(far, "wood.timber")
check(not ok and topic == "work_voice_disabled", "the layer can be switched off")

reset()
cutter = actor("cutter", 5, 0)
SC.Banter = { chatterMultiplier = function() return 4 end }
ok = Voice.cue(cutter, "wood.timber")
check(ok and Voice._stateForTests().actors[cutter].nextAt["voice.wood.timber"] == clock + 160000
    and Voice._stateForTests().partyNextAt == clock + 24000,
    "the chatter setting stretches every gap")
SC.Banter = nil

-- With profanity off, no rough word is ever spoken, across every topic.
reset()
overrides.profanityEnabled = false
local speaker = actor("speaker", 3, 0)
local dirty
for name in pairs(Lines.POOLS) do
    for _ = 1, 30 do
        local line = Dialogue.choose(speaker, name)
        if type(line) == "string" and rough(line) then dirty = name .. ": " .. line end
    end
end
for context, beats in pairs(Lines.BANTER) do
    for _, beat in ipairs(beats) do
        for _, source in ipairs({ { beat.open }, beat.reply, beat.close and { beat.close } or {} }) do
            for _ = 1, 4 do
                local line = Dialogue.choose(speaker, "voice.banter.check", { common = source }, { "Ann" })
                if type(line) == "string" and rough(line) then dirty = context .. ": " .. line end
            end
        end
    end
end
check(dirty == nil, "profanity off selects only clean twins: " .. tostring(dirty))
overrides.profanityEnabled = nil

-- ---------------------------------------------------------------------------
-- Result mappings
-- ---------------------------------------------------------------------------

local function freshSpeaker()
    reset()
    return actor("worker", 4, 0)
end
local worker = freshSpeaker()
ok, topic = Voice.woodResult(worker, "wood_tree_felled")
check(ok and topic == "voice.wood.timber", "a felled expedition tree is called")
worker = freshSpeaker()
check(select(2, Voice.woodResult(worker, "wood_cargo_loaded")) == "voice.wood.load"
    and select(2, Voice.woodResult(freshSpeaker(), "wood_trunk_full")) == "voice.wood.full",
    "trunk loading and a full trunk have their own lines")
check(select(2, Voice.woodResult(freshSpeaker(), "wood_axe_missing")) == "voice.prep.missing"
    and select(2, Voice.woodResult(freshSpeaker(), "wood_waiting_for_daylight")) == "voice.prep.daylight"
    and select(2, Voice.woodResult(freshSpeaker(), "wood_scanning")) == "work_voice_no_event",
    "gear and daylight waits speak; routine scanning does not")
check(select(2, Voice.fishingPrepResult(freshSpeaker(), "fishing_preparing_rod")) == "voice.prep.fetch"
    and select(2, Voice.fishingPrepResult(freshSpeaker(), "fishing_bait_missing")) == "voice.prep.missing",
    "fishing gear preparation shares the gear lines")
check(select(2, Voice.fieldResult(freshSpeaker(), true, "field_action_started", "harvest")) == "voice.field.harvest"
    and select(2, Voice.fieldResult(freshSpeaker(), true, "field_action_started", "chop")) == "voice.field.chop"
    and select(2, Voice.fieldResult(freshSpeaker(), true, "field_target_completed", "chop")) == "voice.field.timber"
    and select(2, Voice.fieldResult(freshSpeaker(), true, "field_target_completed", "harvest")) == "voice.field.picked"
    and select(2, Voice.fieldResult(freshSpeaker(), true, "field_worker_done", "chop")) == "voice.field.done"
    and select(2, Voice.fieldResult(freshSpeaker(), false, "field_action_started", "chop")) == "work_voice_no_event",
    "field orders speak by order kind, and only for accepted results")
check(select(2, Voice.searchResult(freshSpeaker(), "nothing_needed")) == "voice.search.empty"
    and select(2, Voice.searchResult(freshSpeaker(), "approach_timeout")) == "voice.search.blocked",
    "an empty or unreachable search has words")

worker = freshSpeaker()
local pending = 2
SC.ExpeditionIntegration = { summary = function() return { pending = pending } end }
local record = { tripId = "trip:1" }
check(select(2, Voice.deliveryResult(worker, record, true, "car_item_carried")) == "voice.delivery.unload",
    "taking cargo from the trunk is announced")
clock = clock + 200000
pending = 1
check(select(2, Voice.deliveryResult(worker, record, true, "expedition_supply_stored")) == "voice.delivery.stored",
    "a stored item with more to go is a small remark")
clock = clock + 200000
pending = 0
check(select(2, Voice.deliveryResult(worker, record, true, "expedition_supply_stored")) == "voice.delivery.done",
    "the last stored item closes the trip in words")
clock = clock + 200000
check(select(2, Voice.deliveryResult(worker, record, true, "expedition_supply_stored")) == "voice.delivery.stored",
    "the finished-trip line is said once per trip")
clock = clock + 200000
check(select(2, Voice.deliveryResult(worker, record, false, "matching_storage_full")) == "voice.delivery.blocked",
    "full storage is said out loud")
SC.ExpeditionIntegration = nil

worker = freshSpeaker()
check(select(2, Voice.jobEvent("start", { type = "refuel_vehicle" }, "worker")) == "voice.job.start.fuel",
    "a claimed job is spoken as intent")
clock = clock + 20000
check(select(2, Voice.jobEvent("done", { type = "barricade" }, "worker")) == "voice.job.done.barricade",
    "a finished job has its own line")
clock = clock + 20000
check(select(2, Voice.jobEvent("blocked", { type = "clean" }, "worker")) == "voice.job.blocked",
    "a blocked job gets a grumble")
check(select(2, Voice.jobEvent("start", { type = "production" }, "worker")) == "work_voice_no_event"
    and select(2, Voice.jobEvent("start", { type = "farm" }, "worker")) == "work_voice_no_event"
    and select(2, Voice.jobEvent("start", { type = "replace_bandage" }, "worker")) == "work_voice_no_event",
    "production, farming and medical jobs keep their own voices")

-- ---------------------------------------------------------------------------
-- Expedition pulse
-- ---------------------------------------------------------------------------

reset()
local leader, driverMate, rider = actor("leader", 50, 50, "brave"), actor("mate", 51, 50), actor("rider", 52, 50)
local roster = { { id = "leader", actor = leader }, { id = "mate", actor = driverMate },
    { id = "rider", actor = rider } }
local members = { [leader] = true, [driverMate] = true, [rider] = true }
local mission = { roster = roster, members = members, leader = roster[1],
    scout = { phase = "outbound", returnPoint = { x = 0, y = 0, z = 0 },
        vehicle = { state = "walking_to_car", leg = "outbound",
            seats = { leader = 0, mate = 1, rider = 2 } } } }
SC.ViewSession = { owner = function() return "expedition" end }
ok, topic = Voice.expeditionPulse(mission, clock)
check(not ok and topic == "work_voice_observing" and #spoken == 0,
    "first sight of a mission only records its state")
mission.scout.vehicle.state = "driving_out"
clock = clock + 1000
ok, topic = Voice.expeditionPulse(mission, clock)
check(ok and topic == "voice.expedition.drive_out" and last().actor ~= leader,
    "a passenger, not the driver, talks as the car pulls away")
mission.scout.vehicle.state = "parked_at_site"
clock = clock + 15000
ok, topic = Voice.expeditionPulse(mission, clock)
check(ok and topic == "voice.expedition.park_site" and last().actor == leader,
    "the leader settles the crew at the site")
mission.scout.vehicle.state = "unloading_site"
mission.scout.phase = "wood_working"
mission.scout.wood = {}
clock = clock + 15000
ok, topic = Voice.expeditionPulse(mission, clock)
check(ok and topic == "voice.expedition.wood_arrive", "the forest arrival is marked")
mission.scout.wood.endReason = "wood_night"
mission.scout.phase = "inbound"
mission.scout.vehicle = nil
clock = clock + 15000
ok, topic = Voice.expeditionPulse(mission, clock)
check(ok and topic == "voice.expedition.turn_home.night", "nightfall gives the night return lines")
leader.x, leader.y = 20, 20
clock = clock + 15000
ok, topic = Voice.expeditionPulse(mission, clock)
check(ok and topic == "voice.expedition.near_home", "the camp in sight is noticed once")
local function nearHomeLines()
    local count = 0
    for _, row in ipairs(spoken) do
        if inPool("voice.expedition.near_home", row.line) then count = count + 1 end
    end
    return count
end
for _ = 1, 4 do
    clock = clock + 15000
    Voice.expeditionPulse(mission, clock)
end
check(nearHomeLines() == 1, "near-home is said only once")

-- A reloaded mission starts quietly, even when it is already on its way home.
reset()
leader, driverMate = actor("leader", 50, 50), actor("mate", 51, 50)
mission = { roster = { { id = "leader", actor = leader }, { id = "mate", actor = driverMate } },
    members = { [leader] = true, [driverMate] = true },
    scout = { phase = "inbound", wood = { endReason = "wood_quantity_met" } } }
mission.leader = mission.roster[1]
Voice.expeditionPulse(mission, clock)
clock = clock + 1000
Voice.expeditionPulse(mission, clock)
check(#spoken == 0, "a reload does not replay the turn for home")

-- Crew banter on the march: opener, the same beat's reply, then its close.
reset()
leader, driverMate = actor("leader", 50, 50), actor("mate", 53, 50)
mission = { roster = { { id = "leader", actor = leader }, { id = "mate", actor = driverMate } },
    members = { [leader] = true, [driverMate] = true },
    scout = { phase = "outbound", returnPoint = { x = 0, y = 0, z = 0 } } }
mission.leader = mission.roster[1]
Voice.expeditionPulse(mission, clock)
clock = clock + 30000
Voice.expeditionPulse(mission, clock)
check(#spoken == 0, "the crew settles before the first exchange")
clock = clock + 20000
ok, topic = Voice.expeditionPulse(mission, clock)
local beat = Lines.BANTER.march[1]
check(ok and topic == "march" and #spoken == 1 and spoken[1].line == beat.open,
    "a marching crew opens with a chosen beat: " .. tostring(spoken[1] and spoken[1].line))
local opener = spoken[1].actor
clock = clock + 1000
Voice.expeditionPulse(mission, clock)
check(#spoken == 1, "the reply waits a beat")
clock = clock + 2500
Voice.expeditionPulse(mission, clock)
local replied = spoken[2]
check(replied and replied.actor ~= opener
    and (replied.line == beat.reply[1] or replied.line == beat.reply[2]),
    "the other crew member answers that same beat: " .. tostring(replied and replied.line))
clock = clock + 3500
Voice.expeditionPulse(mission, clock)
check(spoken[3] and spoken[3].actor == opener and spoken[3].line == beat.close,
    "the opener closes the beat")
clock = clock + 30000
Voice.expeditionPulse(mission, clock)
check(#spoken == 3, "the next exchange waits for the banter interval")

-- Anything else said in between ends the exchange.
reset()
leader, driverMate = actor("leader", 50, 50), actor("mate", 53, 50)
mission = { roster = { { id = "leader", actor = leader }, { id = "mate", actor = driverMate } },
    members = { [leader] = true, [driverMate] = true },
    scout = { phase = "outbound", returnPoint = { x = 0, y = 0, z = 0 } } }
mission.leader = mission.roster[1]
Voice.expeditionPulse(mission, clock)
clock = clock + 50000
Voice.expeditionPulse(mission, clock)
local first = spoken[1] and spoken[1].actor
local second = first == leader and driverMate or leader
clock = clock + 1000
Dialogue.emitResolved(second, "danger.one", "Zombie!")
clock = clock + 3000
Voice.expeditionPulse(mission, clock)
check(#spoken == 2 and Voice._stateForTests().exchange == nil,
    "a reply never lands after someone said something else")

-- Banter respects the banter switch; action chat does not depend on it.
reset()
overrides.banterEnabled = false
leader, driverMate = actor("leader", 50, 50), actor("mate", 53, 50)
mission = { roster = { { id = "leader", actor = leader }, { id = "mate", actor = driverMate } },
    members = { [leader] = true, [driverMate] = true },
    scout = { phase = "outbound", returnPoint = { x = 0, y = 0, z = 0 } } }
mission.leader = mission.roster[1]
Voice.expeditionPulse(mission, clock)
clock = clock + 60000
Voice.expeditionPulse(mission, clock)
check(#spoken == 0, "banter off means no crew exchanges")
check(Voice.cue(leader, "wood.timber"), "action chat still works with banter off")
SC.ViewSession = nil

-- Camp and field talk from the runtime banter lane.
reset()
local cook, builder = actor("cook", 4, 0), actor("builder", 6, 0)
local jobs = { cook = { state = "active" }, builder = { state = "reserved" } }
SC.BaseLife = { jobFor = function(id) return jobs[id] end, isInside = function() return true end }
local records = { { actor = cook }, { actor = builder }, { actor = player } }
Voice.update(player, records, clock)
clock = clock + 46000
ok, topic = Voice.update(player, records, clock)
check(ok and topic == "camp_work" and inPool("voice.banter.camp_work.open", spoken[1].line),
    "two residents at their jobs trade a few words")
clock = clock + 3100
Voice.update(player, records, clock)
check(#spoken == 2 and inPool("voice.banter.camp_work.reply", spoken[2].line),
    "the camp reply follows on the banter lane")

reset()
local chopper, picker = actor("chopper", 4, 0), actor("picker", 6, 0)
records = { { actor = chopper }, { actor = picker } }
Voice.update(player, records, clock)
clock = clock + 46000
Voice.fieldResult(chopper, true, "field_action_active", "chop")
Voice.fieldResult(picker, true, "field_action_active", "chop")
ok, topic = Voice.update(player, records, clock)
check(ok and topic == "field" and inPool("voice.banter.field.open", spoken[1].line),
    "a field crew talks between swings")
SC.BaseLife = nil

reset()
cook, builder = actor("cook", 4, 0), actor("builder", 6, 0)
SC.BaseLife = { jobFor = function() return nil end, isInside = function() return true end }
records = { { actor = cook }, { actor = builder } }
Voice.update(player, records, clock)
clock = clock + 46000
ok, topic = Voice.update(player, records, clock)
check(not ok and topic == "work_banter_no_pair"
    and Voice._stateForTests().campBanterNextAt == clock + 15000,
    "with nobody at work the camp scan backs off instead of polling every second")
SC.BaseLife = nil

print("WORK_VOICE_KAHLUA_PASS checks=" .. checks)
