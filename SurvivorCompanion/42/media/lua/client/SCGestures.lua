-- SPDX-License-Identifier: MIT

-- Body language. Short Build 42 "Ext" animations -- a yawn that spreads, a
-- stretch after sitting or first thing in the morning at base, a sneeze in a
-- dusty storeroom or a cough in the cold -- and visual-only morning workouts,
-- run as a downtime activity (SCDowntime kind "workout"). Nothing here makes
-- world noise, changes a stat or moves anyone. Every gesture needs a calm,
-- idle, recruited companion, and per-companion and party cooldowns keep it
-- rare.

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
if not SC.GameplayUtil and type(require) == "function" then pcall(require, "SCGameplayUtil") end

SC.Gestures = SC.Gestures or {}
local Gestures = SC.Gestures

local function U() return SC.GameplayUtil end

local function config(key, fallback)
    local utility = U()
    local value = utility and utility.config(key) or nil
    if value == nil then return fallback end
    return value
end

local POOLS = {
    ["gestures.yawn.catch"] = {
        common = {
            "Stop that. Now I'm doing it.",
            "Don't. Don't you dare. ...Too late.",
            "Great. Now it's going around.",
            "Cover your mouth. It's catching.",
            "Oh, come on. Now it's everyone.",
            "Rude. Now I'm tired too.",
            "That's contagious, you know that?",
        },
    },
    ["gestures.stretch"] = {
        common = {
            "Every part of me has an opinion this morning.",
            "Something popped. I think it was supposed to.",
            "Ow. Good ow. Mostly.",
            "My back is older than I am.",
            "Right. Legs work. Let's go.",
            "Joints crack like popcorn these days.",
            "Okay, body. We're doing this.",
            "I'm up. Mostly.",
        },
    },
    ["gestures.sneeze"] = {
        common = {
            "Bless me, then.",
            "Dust. It's always dust.",
            "Nobody say anything.",
            "Whole place smells like an attic.",
            "Allergic to the apocalypse, apparently.",
            "Has anybody dusted this place? Ever?",
            "That's three. I'm counting.",
        },
    },
    ["gestures.sneeze.sneaking"] = {
        common = {
            "Sorry. SORRY.",
            "That wasn't me.",
            "I'm fine. Keep going. Quietly.",
            "Ugh. Sorry. Carry on.",
            "Nobody heard that. Right?",
            "Sorry. It snuck up on me.",
            "Worst possible timing. I know.",
        },
    },
    ["gestures.cough"] = {
        common = {
            "Cold's getting into my chest.",
            "Just the cold. Just the cold.",
            "It's not a fever cough. I'd know.",
            "Somebody find me a scarf.",
            "Just a tickle. Don't look at me like that.",
            "It's the cold. Relax.",
            "I need a hot drink. Or a fire. Or both.",
        },
    },
    ["gestures.workout.start"] = {
        common = {
            "Join me. No? Your loss. Mostly mine.",
            "Morning reps. The dead don't skip leg day.",
            "Twenty minutes. Then coffee. If we had coffee.",
            "Fit people outrun zombies. That's the whole plan.",
            "Up and at it. We're getting strong today.",
            "Morning drills. No excuses.",
            "Stay strong, stay alive. Let's move.",
        },
    },
    ["gestures.workout.join"] = {
        common = {
            "Fine. But I'm doing the easy ones.",
            "If you're going to make me feel bad, I'll join.",
            "Move over. Show me how it's done.",
            "One set. One. Don't look at me like that.",
            "Alright, alright. Count me in.",
            "You're making the rest of us look bad.",
            "Two sets. Then I'm done. Maybe.",
        },
    },
    ["gestures.workout.idle"] = {
        common = {
            "If we're waiting, I'm getting my reps in.",
            "You stand. I'll do pushups. Productive.",
            "Wake me when we move. I'll be on the floor.",
            "Might as well build some muscle while you think.",
            "Standing still makes me restless. Pushups it is.",
            "Waiting is just resting, but boring. Let's move.",
            "Take your time. I'll be down here getting strong.",
        },
    },
    ["gestures.workout.count"] = {
        common = {
            "Ten. Nine. That counts as ten.",
            "Eleven... twelve... thirteen-ish.",
            "I've lost count. Starting over at twenty.",
            "Almost there. Wherever there is.",
            "Fifteen... sixteen... I'll call it twenty.",
            "One more. Then another one more.",
            "Almost done. Don't quote me.",
        },
    },
    ["gestures.workout.struggle"] = {
        common = {
            "This is fine. My arms are fine.",
            "Carrying all this gear is the real workout.",
            "I'm resting. On the floor. On purpose.",
            "Why is the ground so far away today?",
            "My arms have filed a complaint.",
            "Pretty sure this isn't how pushups go.",
            "Give me a second. Or a minute. Or ten.",
        },
    },
}

local DUSTY_ROOMS = { storageunit = true, garagestorage = true }
local ATHLETIC = { fitnessinstructor = true, veteran = true, policeofficer = true,
    fireofficer = true }
-- Floor exercises only. Burpees may carry the body past the supervisor's
-- 0.25-tile pose limit; they wait for the live probe.
local EXERCISES = { "pushups", "situp" }
local PENDING_LIMIT = 8
local PENDING_PATIENCE_MS = 10000

local actors = setmetatable({}, { __mode = "k" })
local registered = false

local function freshParty()
    return {
        lastGestureAt = -math.huge, lastYawnAt = -math.huge, yawnWindow = nil,
        pending = {}, session = nil, idleRequest = nil,
    }
end
local party = freshParty()

local function registerPools()
    if registered or not SC.Dialogue or type(SC.Dialogue.register) ~= "function" then return end
    for topic, pool in pairs(POOLS) do SC.Dialogue.register(topic, pool) end
    registered = true
end

local function actorState(actor)
    local state = actors[actor]
    if not state then
        state = { lastGestureAt = -math.huge }
        actors[actor] = state
    end
    return state
end

local function commandsOf(actor)
    if SC.Commands and type(SC.Commands.peek) == "function" then
        local ok, state = pcall(SC.Commands.peek, actor)
        if ok and type(state) == "table" then return state end
    end
    return nil
end

local function persist(actor)
    if SC.Commands and type(SC.Commands.persist) == "function" then
        local ok, saved = pcall(SC.Commands.persist, actor)
        return ok and saved == true
    end
    return false
end

local function records()
    if SC.Registry and type(SC.Registry.records) == "function" then
        local ok, value = pcall(SC.Registry.records)
        if ok and type(value) == "table" then return value end
    end
    return {}
end

local function hash(text)
    return math.abs(tonumber(U().stableHash(text)) or 0)
end

-- Chance in percent. ZombRand in game; a stable hash in the headless harness.
local function roll(percent, seed)
    percent = tonumber(percent) or 0
    if percent >= 100 then return true end
    if percent <= 0 then return false end
    if type(ZombRand) == "function" then
        local ok, value = pcall(ZombRand, 100)
        if ok and tonumber(value) then return tonumber(value) < percent end
    end
    return hash(seed) % 100 < percent
end

local function gameTime()
    if type(getGameTime) ~= "function" then return nil end
    local ok, value = pcall(getGameTime)
    return ok and value or nil
end

local function hourNow()
    local hour = tonumber((U().call(gameTime(), "getHour")))
    if hour == nil then return 12 end
    return math.max(0, math.min(23, math.floor(hour)))
end

local function today()
    local hours = tonumber((U().call(gameTime(), "getWorldAgeHours"))) or 0
    return math.floor(hours / 24)
end

local function recordSnapshot(record)
    local runtime = type(record) == "table" and record.runtime or nil
    if type(runtime) ~= "table" then return nil end
    return type(runtime.senses) == "table" and runtime.senses.current or runtime.snapshot
end

local function calm(snapshot)
    if type(snapshot) ~= "table" then return true end
    if (tonumber(snapshot.threatCount) or #(snapshot.threats or {})) > 0 then return false end
    if (tonumber(snapshot.immediateCount) or 0) > 0 then return false end
    if (tonumber(snapshot.pressure) or 0) > 0 then return false end
    local playerState = snapshot.player
    if type(playerState) == "table" and (tonumber(playerState.danger) or 0) > 0 then return false end
    return true
end

local function atBase(actor)
    return SC.BaseLife ~= nil and type(SC.BaseLife.isInside) == "function"
        and SC.BaseLife.isInside(actor) == true
end

local function professionOf(commands)
    local profile = type(commands) == "table" and commands.personalityProfile or nil
    local value = type(profile) == "table" and profile.profession or nil
    if value == nil then return nil end
    value = string.lower(tostring(value))
    value = string.match(value, "[^:%.]+$") or value
    return (string.gsub(value, "[^%w]", ""))
end

local function flavorOf(commands)
    if SC.Banter and type(SC.Banter.flavor) == "function" then return SC.Banter.flavor(commands) end
    return nil
end

local function cooledDown(actor, current)
    return current - actorState(actor).lastGestureAt >= config("gestureActorCooldownMs", 90000)
end

-- A recruited, calm companion standing still that no other action owns. A
-- downtime sit counts as idle: the animation graph plays the seated variant.
local function eligible(record, player, current)
    local actor = type(record) == "table" and record.actor or nil
    local utility = U()
    if actor == nil or not utility.isValidActor(actor) or utility.isDead(actor) then return nil end
    local commands = commandsOf(actor)
    if type(commands) ~= "table" or commands.recruited ~= true then return nil end
    if not calm(recordSnapshot(record)) then return nil end
    if utility.call(actor, "getVehicle") ~= nil or utility.call(actor, "isAsleep") == true
        or utility.call(actor, "isMoving") == true then return nil end
    if SC.ZombieAttack and type(SC.ZombieAttack.isGrabbed) == "function"
        and SC.ZombieAttack.isGrabbed(actor) == true then return nil end
    if commands.order == "follow" and player ~= nil and utility.call(player, "isMoving") == true then
        return nil
    end
    local owner = SC.ActionSupervisor and type(SC.ActionSupervisor.current) == "function"
        and SC.ActionSupervisor.current(actor) or nil
    if owner ~= nil then
        local downtime = SC.Downtime and type(SC.Downtime.peek) == "function"
            and SC.Downtime.peek(actor) or nil
        local active = type(downtime) == "table" and downtime.active or nil
        if not (type(active) == "table" and active.kind == "sit") then return nil end
    end
    return commands
end

local function perform(actor, name, current)
    local accepted = U().move(actor, "walk", {
        action = "ext_gesture", ext = name, humanAnimationOnly = true,
    })
    if accepted ~= true then return false end
    actorState(actor).lastGestureAt = current
    party.lastGestureAt = current
    return true
end

-- A line to go with a gesture, within the shared flavor-speech budget.
local function say(actor, topic, commands, current, chance)
    if chance ~= nil and not roll(chance, tostring(U().idOf(actor)) .. ":" .. topic
        .. ":" .. tostring(current)) then
        return false
    end
    local banter = SC.Banter
    if type(banter) == "table" and type(banter.budgetAllows) == "function"
        and not banter.budgetAllows(current) then
        return false
    end
    if not SC.Dialogue or type(SC.Dialogue.say) ~= "function" then return false end
    registerPools()
    local ok, spoken = pcall(SC.Dialogue.say, actor, topic, nil, nil, {
        state = commands or commandsOf(actor), recentLimit = 4,
        salt = topic .. ":" .. tostring(current),
    })
    if ok and spoken == true and type(banter) == "table" and type(banter.spendBudget) == "function" then
        banter.spendBudget(current)
    end
    return ok and spoken == true
end

local function schedule(actor, name, at, line, options)
    if #party.pending >= PENDING_LIMIT then return false end
    for _, entry in ipairs(party.pending) do
        if entry.actor == actor then return false end
    end
    options = type(options) == "table" and options or {}
    party.pending[#party.pending + 1] = {
        actor = actor, name = name, at = at, line = line,
        chain = options.chain == true, lineChance = options.lineChance,
    }
    return true
end

-- Delayed gestures: a yawn caught from a neighbour, a stretch after getting
-- up, a sneeze a moment after walking into dust. Each waits up to ten
-- seconds for its companion to be free, then is dropped.
local function processPending(player, byActor, current)
    local keep = {}
    for _, entry in ipairs(party.pending) do
        local record = byActor[entry.actor]
        if current < entry.at then
            keep[#keep + 1] = entry
        elseif record and current - entry.at <= PENDING_PATIENCE_MS then
            local commands = eligible(record, player, current)
            if commands and (entry.chain or cooledDown(entry.actor, current)) then
                if perform(entry.actor, entry.name, current) and entry.line then
                    say(entry.actor, entry.line, commands, current, entry.lineChance)
                end
            else
                keep[#keep + 1] = entry
            end
        end
    end
    party.pending = keep
end

local function sneezeName(actor, current)
    return hash(tostring(U().idOf(actor)) .. ":sneeze:" .. tostring(current)) % 2 == 0
        and "Sneeze1" or "Sneeze2"
end

local function airTemperature(actor)
    if type(getClimateManager) ~= "function" then return nil end
    local ok, climate = pcall(getClimateManager)
    if not ok or climate == nil then return nil end
    return tonumber((U().call(climate, "getAirTemperatureForCharacter", actor)))
end

-- Walking into a dusty storeroom, or a cold spell, may draw a sneeze or a
-- cough. Rooms are tracked for every companion so an entry counts once; the
-- cold is rolled once per window.
local function dustAndCold(list, current)
    local utility = U()
    local window = math.floor(current / math.max(1000, config("sneezeColdWindowMs", 300000)))
    local lineChance = config("gestureLineChancePercent", 35)
    for _, record in ipairs(list) do
        local actor = type(record) == "table" and record.actor or nil
        if actor ~= nil and record.recruited == true and utility.isValidActor(actor) then
            local state = actorState(actor)
            local room = utility.roomName(utility.squareOf(actor))
            room = room and string.lower(tostring(room)) or nil
            local entered = room ~= nil and room ~= state.room and DUSTY_ROOMS[room] == true
            state.room = room
            local id = tostring(utility.idOf(actor))
            if entered then
                if roll(config("sneezeDustyChancePercent", 5), id .. ":dust:" .. tostring(current)) then
                    local sneaking = utility.call(actor, "isSneaking") == true
                    schedule(actor, sneezeName(actor, current), current + 1500,
                        sneaking and "gestures.sneeze.sneaking" or "gestures.sneeze",
                        { lineChance = lineChance })
                end
            elseif state.coldWindow ~= window then
                state.coldWindow = window
                local temperature = airTemperature(actor)
                if temperature ~= nil and temperature < config("sneezeColdTemperature", 5)
                    and roll(config("sneezeColdChancePercent", 5), id .. ":cold:" .. tostring(window)) then
                    local cough = hash(id .. ":cough:" .. tostring(window)) % 2 == 0
                    schedule(actor, cough and "Cough" or sneezeName(actor, current), current + 500,
                        cough and "gestures.cough" or "gestures.sneeze", { lineChance = lineChance })
                end
            end
        end
    end
end

-- The first gesture of the morning at base is a stretch, once a day each.
local function morningStretch(player, list, current)
    local hour = hourNow()
    if hour < config("workoutMorningStartHour", 6) or hour >= config("workoutMorningEndHour", 10) then
        return false
    end
    local day = today()
    for _, record in ipairs(list) do
        local actor = type(record) == "table" and record.actor or nil
        local state = actor and actorState(actor) or nil
        if state and state.stretchDay ~= day and atBase(actor) then
            local commands = eligible(record, player, current)
            if commands and cooledDown(actor, current) then
                state.stretchDay = day
                if perform(actor, "TiredStretch", current) then
                    say(actor, "gestures.stretch", commands, current,
                        config("gestureLineChancePercent", 35))
                    return true
                end
            end
        end
    end
    return false
end

-- Late in the evening, or when one of them is tired, one companion yawns.
-- Neighbours within a few tiles catch it a few seconds later; the chain
-- stops at yawnChainMax, and the party waits ten minutes for the next one.
local function yawnPulse(player, list, current)
    if current - party.lastYawnAt < config("yawnPartyCooldownMs", 600000) then
        return false, "yawn_cooldown"
    end
    local window = math.floor(current / math.max(1000, config("gestureRollWindowMs", 60000)))
    if party.yawnWindow == window then return false, "yawn_rolled" end
    local hour = hourNow()
    local late = hour >= config("yawnEveningHour", 21) or hour < config("yawnMorningHour", 6)
    local utility = U()
    local best, bestFatigue
    for _, record in ipairs(list) do
        local actor = type(record) == "table" and record.actor or nil
        local commands = actor and eligible(record, player, current) or nil
        if commands and cooledDown(actor, current) then
            local fatigue = tonumber(utility.characterStatValue(actor, "FATIGUE", 0)) or 0
            if (late or fatigue >= config("yawnFatigue", 0.5))
                and (best == nil or fatigue > bestFatigue) then
                best, bestFatigue = actor, fatigue
            end
        end
    end
    if best == nil then return false, "yawn_no_one" end
    party.yawnWindow = window
    if not roll(config("yawnChancePercent", 25), tostring(utility.idOf(best)) .. ":yawn:"
        .. tostring(window)) then
        return false, "yawn_roll"
    end
    if not perform(best, "Yawn", current) then return false, "yawn_rejected" end
    party.lastYawnAt = current
    local caught = 1
    local limit = math.max(1, math.floor(config("yawnChainMax", 3)))
    for _, record in ipairs(list) do
        if caught >= limit then break end
        local other = type(record) == "table" and record.actor or nil
        if other ~= nil and other ~= best and utility.sameFloor(best, other)
            and utility.distance(best, other) <= config("yawnCatchRadius", 6)
            and eligible(record, player, current) and cooledDown(other, current) then
            local id = tostring(utility.idOf(other))
            if roll(config("yawnCatchChancePercent", 60), id .. ":catch:" .. tostring(current)) then
                local delay = 2000 + hash(id .. ":delay:" .. tostring(current)) % 4001
                if schedule(other, "Yawn", current + delay,
                    caught == 1 and "gestures.yawn.catch" or nil,
                    { chain = true, lineChance = config("gestureLineChancePercent", 35) }) then
                    caught = caught + 1
                end
            end
        end
    end
    return true, "yawn"
end

local function workoutChatter(list, current)
    for _, record in ipairs(list) do
        local actor = type(record) == "table" and record.actor or nil
        local state = actor and actors[actor] or nil
        local workout = state and state.workout or nil
        if workout then
            local downtime = SC.Downtime and type(SC.Downtime.peek) == "function"
                and SC.Downtime.peek(actor) or nil
            local active = type(downtime) == "table" and downtime.active or nil
            if not (type(active) == "table" and active.kind == "workout") then
                state.workout = nil
            elseif not workout.spoke and current - workout.startedAt >= config("workoutChatterMs", 12000) then
                workout.spoke = true
                say(actor, workout.struggle and "gestures.workout.struggle" or "gestures.workout.count",
                    nil, current, 50)
            end
        end
    end
end

-- One party pulse from the runtime's background lane.
function Gestures.update(player, list, current)
    if config("gesturesEnabled", true) == false then return false, "gestures_disabled" end
    current = tonumber(current) or U().nowMs()
    list = type(list) == "table" and list or records()
    registerPools()
    local byActor = {}
    for _, record in ipairs(list) do
        if type(record) == "table" and record.actor ~= nil then byActor[record.actor] = record end
    end
    processPending(player, byActor, current)
    workoutChatter(list, current)
    dustAndCold(list, current)
    if current - party.lastGestureAt < config("gesturePartyGapMs", 15000) then
        return false, "gesture_party_gap"
    end
    if morningStretch(player, list, current) then return true, "stretch" end
    return yawnPulse(player, list, current)
end

-- SCDowntime calls this when a companion gets up from a seat.
function Gestures.noteStoodUp(actor, current)
    if actor == nil or config("gesturesEnabled", true) == false then
        return false, "gestures_disabled"
    end
    current = tonumber(current) or U().nowMs()
    local id = tostring(U().idOf(actor))
    if not roll(config("stretchAfterSitChancePercent", 40), id .. ":stood:" .. tostring(current)) then
        return false, "stretch_roll"
    end
    local scheduled = schedule(actor, "TiredStretch", current + config("stretchDelayMs", 1500),
        "gestures.stretch", { lineChance = config("gestureLineChancePercent", 35) })
    return scheduled, scheduled and "stretch_scheduled" or "stretch_queue_full"
end

local function athletic(commands)
    return ATHLETIC[professionOf(commands) or ""] == true
end

-- Tired, winded or carrying a heavy load: the struggling animation.
local function struggling(actor)
    local utility = U()
    local fatigue = tonumber(utility.characterStatValue(actor, "FATIGUE", 0)) or 0
    local endurance = tonumber(utility.characterStatValue(actor, "ENDURANCE", 1)) or 1
    if fatigue >= 0.5 or endurance <= 0.5 then return true end
    local carried = tonumber((utility.call(utility.inventory(actor), "getCapacityWeight")))
    local capacity = tonumber((utility.call(actor, "getMaxWeight")))
    return carried ~= nil and capacity ~= nil and capacity > 0 and carried / capacity >= 0.75
end

local function nearLeader(actor, session)
    local leader = session.leader
    local utility = U()
    return leader ~= nil and leader ~= actor and utility.isValidActor(leader)
        and utility.sameFloor(actor, leader)
        and utility.distance(actor, leader) <= config("workoutJoinRadius", 10)
end

-- Downtime candidate (SCDowntime kind "workout"). A morning at base draws an
-- athletic companion (fitness instructor, veteran, police, fire officer) once
-- a day, and others nearby may join in the first half minute. After ten idle
-- minutes the companion making the joke may do a set too (SCBanter).
function Gestures.workoutActivity(actor, commands, state, current)
    if config("gesturesEnabled", true) == false then return nil end
    commands = type(commands) == "table" and commands or {}
    state = type(state) == "table" and state or {}
    current = tonumber(current) or U().nowMs()
    if commands.recruited ~= true then return nil end
    if current - (tonumber(state.safeSince) or current) < config("workoutSafeMs", 10000) then
        return nil
    end
    local utility = U()
    local id = tostring(utility.idOf(actor))
    local day = today()
    local mode, score
    local request = party.idleRequest
    if type(request) == "table" and request.actor == actor and current <= request.untilAt then
        mode, score = "idle", 50
    elseif atBase(actor) then
        local flavor = flavorOf(commands)
        if type(flavor) == "table" and flavor.lastWorkoutDay == day then return nil end
        local session = party.session
        if type(session) == "table" and session.day == day and current <= session.untilAt
            and not session.rolled[id] and nearLeader(actor, session) then
            session.rolled[id] = true
            if roll(config("workoutJoinChancePercent", 30), id .. ":join:" .. tostring(day)) then
                mode, score = "join", 34
            end
        end
        local hour = hourNow()
        if mode == nil and athletic(commands) and hour >= config("workoutMorningStartHour", 6)
            and hour < config("workoutMorningEndHour", 10) then
            mode, score = "lead", 36
        end
    end
    if mode == nil then return nil end
    local minimum = math.max(1000, math.floor(config("workoutMinMs", 20000)))
    local maximum = math.max(minimum, math.floor(config("workoutMaxMs", 40000)))
    local seed = id .. ":" .. tostring(day) .. ":" .. mode
    local exercise = EXERCISES[(hash(seed .. ":exercise") % #EXERCISES) + 1]
    local duration = minimum + hash(seed .. ":duration") % (maximum - minimum + 1)
    -- The supervisor's default animation and settle deadlines are far shorter
    -- than a workout; this one gets its own, with room to get up again.
    local deadline = duration + 15000
    return {
        kind = "workout", score = score, workout = mode, exercise = exercise,
        struggle = struggling(actor), durationMs = duration,
        deadlines = { animating = deadline, settling = deadline },
        fact = { activity = "workout", exercise = exercise },
    }
end

-- SCBanter's ten-minute idle joke may turn into a workout.
function Gestures.requestIdleWorkout(actor, current)
    if actor == nil or config("gesturesEnabled", true) == false then return false end
    local commands = commandsOf(actor)
    if type(commands) ~= "table" or commands.recruited ~= true then return false end
    if U().call(actor, "getVehicle") ~= nil then return false end
    current = tonumber(current) or U().nowMs()
    party.idleRequest = { actor = actor,
        untilAt = current + config("workoutIdleRequestMs", 60000) }
    return true
end

function Gestures.workoutStarted(actor, activity, current)
    if type(activity) ~= "table" then return false end
    current = tonumber(current) or U().nowMs()
    local mode = activity.workout
    if mode == "lead" then
        party.session = { day = today(), leader = actor, rolled = {},
            untilAt = current + config("workoutJoinWindowMs", 30000) }
    elseif mode == "idle" and type(party.idleRequest) == "table"
        and party.idleRequest.actor == actor then
        party.idleRequest = nil
    end
    actorState(actor).workout = { startedAt = current, spoke = false,
        struggle = activity.struggle == true }
    local topic = mode == "lead" and "gestures.workout.start"
        or mode == "join" and "gestures.workout.join" or nil
    if topic then say(actor, topic, nil, current) end
    return true
end

-- A finished workout counts for the day and is saved with the companion.
function Gestures.workoutFinished(actor, activity, current)
    actorState(actor).workout = nil
    local flavor = flavorOf(commandsOf(actor))
    if type(flavor) ~= "table" then return false end
    flavor.lastWorkoutDay = today()
    persist(actor)
    return true
end

function Gestures.reset(actor)
    if actor ~= nil then
        actors[actor] = nil
        local keep = {}
        for _, entry in ipairs(party.pending) do
            if entry.actor ~= actor then keep[#keep + 1] = entry end
        end
        party.pending = keep
        if type(party.idleRequest) == "table" and party.idleRequest.actor == actor then
            party.idleRequest = nil
        end
        return true
    end
    actors = setmetatable({}, { __mode = "k" })
    party = freshParty()
    return true
end

-- Test seams.
function Gestures._partyForTests()
    return party
end

function Gestures._actorStateForTests(actor)
    return actorState(actor)
end

function Gestures._poolsForTests()
    return POOLS
end

registerPools()

return Gestures
