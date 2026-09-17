-- SPDX-License-Identifier: MIT

-- Tall tales. A companion remembers the fights it did well in and later tells
-- them again to whoever sits still long enough, with the numbers growing every
-- time. A companion who was there may correct it; the teller never backs down.
-- Speech only: no animation, no world effect. The killer keeps the tale on its
-- command state (commands.tales), saved with it; each witness keeps a short
-- stub with the true count so it can object. Bites are never told.

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
if not SC.GameplayUtil and type(require) == "function" then pcall(require, "SCGameplayUtil") end

SC.Tales = SC.Tales or {}
local Tales = SC.Tales

local function U() return SC.GameplayUtil end

local function config(key, fallback)
    local utility = U()
    local value = utility and utility.config(key) or nil
    if value == nil then return fallback end
    return value
end

local POOLS = {
    ["tales.open"] = {
        common = {
            "Did I ever tell you about %1?",
            "You ever hear about %1? No? Sit down.",
            "This reminds me of %1.",
            "Nobody asked, but here's %1.",
            "Let me tell you about %1.",
            "Sit down. You're going to want to hear about %1.",
            "Stop me if you've heard this one. It's about %1.",
            "Nobody believes me about %1. You will.",
        },
        brave = { "Gather round. Time you heard about %1." },
        cautious = { "I don't like to talk about %1. But I will." },
        caring = { "I think about %1 sometimes. Want to hear it?" },
        practical = { "Short version of %1. It's a good one." },
    },
    ["tales.body"] = {
        common = {
            "%2 of 'em. Came out of nowhere at %1.",
            "I counted %2. Maybe more. Hard to count and swing.",
            "%2 zombies, one of me. Do the math.",
            "They just kept coming. %2, easy.",
            "Me, my %5, and %2 very unhappy people.",
            "%2 of 'em, every one with my name on its teeth.",
            "I went through my %5 like it owed me money. %2 times.",
            "%2. I stopped counting when I ran out of fingers. Twice.",
        },
    },
    ["tales.dark"] = {
        common = {
            "And it was pitch dark. Couldn't see my own hand.",
            "Middle of the night, mind you. No moon.",
            "Dark as the inside of a cow. Didn't stop me.",
            "Lights were out. All of them. Everywhere.",
            "Fog so thick I was fighting by smell.",
            "Couldn't see a thing. Just teeth and moaning.",
            "Blackout. Whole county. Then the moon went behind a cloud too.",
        },
    },
    ["tales.guest"] = {
        common = {
            "And %3. I'm not saying it was involved. I'm saying it was there.",
            "Then %3 showed up. Didn't help. Didn't hurt.",
            "Oh, and %3. Don't ask. I still don't know.",
            "Did I mention %3? Because there was %3.",
            "There was %3 too. Explain that one.",
            "And then, out of nowhere, %3.",
            "You'll laugh. %3. I swear on my mother.",
        },
    },
    ["tales.injury"] = {
        common = {
            "Did it all with one arm, by the way.",
            "Twisted ankle the whole time. Never complained once.",
            "Couldn't feel my left hand. Used it anyway.",
            "Bleeding from places I didn't know I had.",
            "Cracked rib. Laughed anyway. Hurt more.",
            "Fought half of it hopping on one leg.",
            "Blood in my eyes the whole time. Fought by ear.",
        },
    },
    ["tales.grabbed"] = {
        common = {
            "One of 'em had me down on the ground. Big mistake. For it.",
            "Got grabbed. Pinned flat. Talked my way out. Mostly punched.",
            "One had me by the collar. I'm still mad about the collar.",
            "They pulled me down once. Once.",
            "Had one hanging off my back like a backpack. Shook it off.",
            "Dragged down in the mud. Came up swinging.",
            "One grabbed my boot. I kept the boot. It didn't keep its head.",
        },
    },
    ["tales.hurt"] = {
        common = {
            "Took a hit that should've put me down. Didn't.",
            "Got clipped bad. Kept going. Doctors hate me.",
            "Lost a lot of blood. Found most of it later.",
            "Hurt? Sure. Stopped? No.",
            "Got hit hard enough to see stars. Named a few of them.",
            "I was bleeding. They were worse off.",
            "Would've fainted, but I was busy.",
        },
    },
    ["tales.close"] = {
        common = {
            "Anyway. I'm still here. They're not.",
            "And that's why I don't go to %1 anymore.",
            "True story. Mostly.",
            "Point is, don't ever mess with me at %1.",
            "Anyway. Pass the beans.",
            "And that's the truth. Most of it.",
            "Somebody write that down. For history.",
            "Another day, another miracle. Mine, specifically.",
        },
        brave = { "I'd do it again. Tonight, even." },
        cautious = { "I still dream about it. Don't tell anyone." },
        caring = { "Could've been any of us. Glad it was me." },
        practical = { "Lesson is, bring more than one weapon." },
    },
    ["tales.correction"] = {
        common = {
            "It was %2, %4. I was there.",
            "%2, %4. It was %2. I counted.",
            "That's not how it went, %4. It was %2.",
            "%4, it was %2. And it was daytime.",
            "That's not what happened, %4. I was right behind you. %2.",
            "You're doing it again, %4. It was %2.",
            "%4. Buddy. %2. Tops.",
        },
        caring = { "It was %2, %4. Still brave. Just %2." },
    },
    ["tales.doubledown"] = {
        common = {
            "%2 HUNDRED, %4. Some of us were counting.",
            "You were facing the wrong way, %4.",
            "Who's telling this, %4? Me. That's who.",
            "Your %2 were in front, %4. Mine were behind. It adds up.",
            "I know what I saw, %4.",
            "Get your own story, %4.",
            "It goes up because I remember more every time, %4. That's science.",
        },
    },
    ["tales.appeal"] = {
        common = {
            "Ask the boss. They were there. Tell 'em, boss.",
            "Boss saw it. Boss, back me up.",
            "Don't look at me. Look at the boss. The boss knows.",
            "Boss, tell 'em how many. Go on.",
            "The boss was there. The boss doesn't lie. Right, boss?",
            "Back me up here, boss. You saw it.",
            "Boss. Honestly. How many was it? Round up.",
        },
    },
}

-- Room definitions worth naming; anything else indoors is "that building".
local ROOM_PLACES = {
    gasstore = "the gas station", fossoil = "the gas station",
    policestorage = "the police station", policelocker = "the police station",
    prisoncells = "the jail", church = "the church", bar = "the bar",
    liquorstore = "the liquor store", classroom = "the school",
    elementaryschool = "the school", library = "the library", gunstore = "the gun store",
    pharmacy = "the pharmacy", hospitalroom = "the hospital", medical = "the hospital",
    morgue = "the morgue", spiffo_dining = "Spiffo's", spiffoskitchen = "Spiffo's",
    jayschicken_dining = "Jay's Chicken", gigamart = "the Gigamart", grocery = "the grocery",
    mechanic = "the garage", firestorage = "the fire station",
    armystorage = "the army depot", theatre = "the movie theater",
    bowlingalley = "the bowling alley", motelroom = "the motel", laundry = "the laundromat",
    gym = "the gym", warehouse = "the warehouse", storageunit = "the storage units",
    kitchen = "somebody's kitchen", bedroom = "somebody's house",
    livingroom = "somebody's house", bathroom = "somebody's bathroom",
}

local ZONE_PLACES = {
    Forest = "the woods", DeepForest = "the woods", Vegitation = "the woods",
    Farm = "a farm", FarmLand = "a farm", Nav = "the road",
    TownZone = "the middle of town", TrailerPark = "the trailer park",
}

local GUESTS = {
    "a bear", "a mall Santa", "a school bus", "a marching band",
    "a pastor on a riding mower", "a llama", "the whole Muldraugh bowling league",
}

local GROWTH = { 1, 1.5, 2.5, 4, 7, 12 }

local episodes = setmetatable({}, { __mode = "k" })
local checkedBuckets = setmetatable({}, { __mode = "k" })
local registered = false

local function freshParty()
    return { lastEpisodeEndedAt = -math.huge, lastTellAt = -math.huge, telling = nil, serial = 0 }
end
local party = freshParty()

local function registerPools()
    if registered or not SC.Dialogue or type(SC.Dialogue.register) ~= "function" then return end
    for topic, pool in pairs(POOLS) do SC.Dialogue.register(topic, pool) end
    registered = true
end

local function clampInteger(value, low, high, fallback)
    value = tonumber(value)
    if value == nil or value ~= value then return fallback end
    value = math.floor(value)
    if value < low then return low end
    if value > high then return high end
    return value
end

local function text(value, fallback, limit)
    if type(value) ~= "string" or value == "" then return fallback end
    return string.sub(value, 1, limit or 48)
end

local function gameTime()
    if type(getGameTime) ~= "function" then return nil end
    local ok, value = pcall(getGameTime)
    return ok and value or nil
end

local function worldHours()
    local value = tonumber((U().call(gameTime(), "getWorldAgeHours")))
    return value or 0
end

local function worldDay()
    return math.floor(worldHours() / 24)
end

local function hourNow()
    return clampInteger((U().call(gameTime(), "getHour")), 0, 23, 12)
end

local function timeOfDay(hour)
    hour = tonumber(hour) or 12
    if hour < 5 or hour >= 21 then return "night" end
    if hour < 12 then return "morning" end
    if hour < 18 then return "afternoon" end
    return "evening"
end

local function playerNow()
    if type(getSpecificPlayer) == "function" then
        local ok, value = pcall(getSpecificPlayer, 0)
        if ok and value then return value end
    end
    if type(getPlayer) == "function" then
        local ok, value = pcall(getPlayer)
        if ok then return value end
    end
    return nil
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

local function firstName(actor)
    local name = tostring(U().nameOf(actor) or "")
    return string.match(name, "^(%S+)") or "friend"
end

local function recordSnapshot(record)
    local runtime = type(record) == "table" and record.runtime or nil
    if type(runtime) ~= "table" then return nil end
    return type(runtime.senses) == "table" and runtime.senses.current or runtime.snapshot
end

local function calm(snapshot)
    if type(snapshot) ~= "table" then return true end
    if (tonumber(snapshot.threatCount) or #(snapshot.threats or {})) > 0 then return false end
    return (tonumber(snapshot.immediateCount) or 0) == 0
end

-- Where a fight happened, as the teller would say it.
local function placeOf(actor)
    local utility = U()
    local square = utility.squareOf(actor)
    local room = utility.roomName and utility.roomName(square) or nil
    if room ~= nil then
        return ROOM_PLACES[string.lower(tostring(room))] or "that building",
            ROOM_PLACES[string.lower(tostring(room))] and "room" or "building"
    end
    local zone = square and utility.call(square, "getZone") or nil
    local zoneType = zone and utility.call(zone, "getType") or nil
    local label = zoneType and ZONE_PLACES[tostring(zoneType)] or nil
    if label then return label, "zone" end
    return "out in the open", "open"
end

local function weaponOf(actor)
    local utility = U()
    local item = utility.call(actor, "getPrimaryHandItem")
    local name = item and utility.call(item, "getDisplayName") or nil
    if type(name) ~= "string" or name == "" then return "bare hands" end
    return string.lower(string.sub(name, 1, 40))
end

local function noteWitnesses(actor, episode)
    local utility = U()
    local radius = config("taleWitnessRadius", 12)
    for _, record in ipairs(records()) do
        local other = type(record) == "table" and record.actor or nil
        if other ~= nil and other ~= actor and record.recruited == true
            and type(record.id) == "string" and not episode.witnesses[record.id]
            and episode.witnessCount < 4 and not utility.isDead(other)
            and utility.sameFloor(actor, other) and utility.distance(actor, other) <= radius then
            episode.witnesses[record.id] = true
            episode.witnessCount = episode.witnessCount + 1
        end
    end
    local player = playerNow()
    if player ~= nil and utility.sameFloor(actor, player)
        and utility.distance(actor, player) <= radius then
        episode.playerThere = true
    end
end

local function episodeFor(actor, now)
    local episode = episodes[actor]
    if episode == nil then
        episode = {
            startedAt = now, lastEventAt = now, kills = 0, witnesses = {}, witnessCount = 0,
            startHealth = tonumber(U().nativeHealth(actor)) or 100,
        }
        episodes[actor] = episode
    end
    return episode
end

-- A credited kill (SCCombat.confirmRecentKill).
function Tales.noteKill(actor, target, now)
    local utility = U()
    if actor == nil or not utility.isCompanion(actor) then return false, "not_a_companion" end
    now = tonumber(now) or utility.nowMs()
    local episode = episodeFor(actor, now)
    episode.kills = episode.kills + 1
    episode.lastEventAt = now
    episode.place, episode.placeKind = placeOf(actor)
    episode.weapon = weaponOf(actor)
    episode.hour = hourNow()
    noteWitnesses(actor, episode)
    return true, "kill_noted"
end

-- A close call: "grabbed" (pulled down by a pile) or "hurt" (a heavy hit).
function Tales.noteCloseCall(actor, kind, now)
    local utility = U()
    if actor == nil or (kind ~= "grabbed" and kind ~= "hurt") then return false, "invalid_close_call" end
    now = tonumber(now) or utility.nowMs()
    local episode = episodeFor(actor, now)
    if episode.closeCall ~= "grabbed" then episode.closeCall = kind end
    episode.lastEventAt = now
    return true, "close_call_noted"
end

local function normalizeTale(tale)
    if type(tale) ~= "table" or type(tale.id) ~= "string" or tale.id == "" then return nil end
    local witnesses = {}
    for _, id in ipairs(type(tale.witnesses) == "table" and tale.witnesses or {}) do
        if type(id) == "string" and id ~= "" and #witnesses < 4 then
            witnesses[#witnesses + 1] = string.sub(id, 1, 96)
        end
    end
    return {
        id = string.sub(tale.id, 1, 64),
        day = clampInteger(tale.day, 0, 1000000, 0),
        place = text(tale.place, "out in the open", 48),
        placeKind = text(tale.placeKind, "open", 16),
        timeOfDay = text(tale.timeOfDay, "afternoon", 16),
        kills = clampInteger(tale.kills, 0, 999, 0),
        closeCall = (tale.closeCall == "grabbed" or tale.closeCall == "hurt") and tale.closeCall or nil,
        weapon = text(tale.weapon, "bare hands", 48),
        witnesses = witnesses,
        playerThere = tale.playerThere == true,
        tellings = clampInteger(tale.tellings, 0, 99, 0),
        lastToldHour = tonumber(tale.lastToldHour) or -1,
    }
end

-- A clean bucket from any saved value: unknown keys dropped, lists bounded,
-- tales older than the fade window forgotten unless they became legends.
function Tales.normalize(value, today)
    local bucket = { version = 1, list = {}, witnessed = {} }
    if type(value) ~= "table" then return bucket end
    local maximum = math.max(1, math.floor(config("taleMaxPerCompanion", 6)))
    local fade = config("taleFadeDays", 60)
    for _, raw in ipairs(type(value.list) == "table" and value.list or {}) do
        local tale = normalizeTale(raw)
        local faded = tale and today ~= nil and today - tale.day > fade and tale.tellings < 5
        if tale and not faded and #bucket.list < maximum then bucket.list[#bucket.list + 1] = tale end
    end
    for _, stub in ipairs(type(value.witnessed) == "table" and value.witnessed or {}) do
        if type(stub) == "table" and type(stub.id) == "string" and stub.id ~= ""
            and #bucket.witnessed < 12 then
            bucket.witnessed[#bucket.witnessed + 1] = {
                id = string.sub(stub.id, 1, 64),
                teller = type(stub.teller) == "string" and string.sub(stub.teller, 1, 96) or nil,
                kills = clampInteger(stub.kills, 0, 999, 0),
            }
        end
    end
    return bucket
end

function Tales.bucket(commands)
    if type(commands) ~= "table" then return nil end
    local bucket = commands.tales
    if type(bucket) == "table" and checkedBuckets[bucket] then return bucket end
    bucket = Tales.normalize(bucket, worldDay())
    commands.tales = bucket
    checkedBuckets[bucket] = true
    return bucket
end

local function taleWeight(tale)
    return (tonumber(tale.kills) or 0) * (tale.closeCall and 2 or 1)
end

-- Never-told tales go first, the weakest of them; told ones only after.
local function evict(bucket)
    local maximum = math.max(1, math.floor(config("taleMaxPerCompanion", 6)))
    while #bucket.list > maximum do
        local worstIndex, worstWeight, worstTold
        for index, tale in ipairs(bucket.list) do
            local told = (tale.tellings or 0) > 0
            local weight = taleWeight(tale)
            if worstIndex == nil or (worstTold and not told)
                or (told == worstTold and weight < worstWeight) then
                worstIndex, worstWeight, worstTold = index, weight, told
            end
        end
        table.remove(bucket.list, worstIndex)
    end
end

local function storeTale(actor, episode, current)
    local commands = commandsOf(actor)
    if type(commands) ~= "table" or commands.recruited ~= true then return nil end
    local bucket = Tales.bucket(commands)
    local tellerId = tostring(U().idOf(actor) or "companion")
    party.serial = party.serial + 1
    local witnesses = {}
    for id in pairs(episode.witnesses) do witnesses[#witnesses + 1] = id end
    table.sort(witnesses)
    local tale = normalizeTale({
        id = "tale:" .. tostring(U().stableHash(tellerId .. ":" .. tostring(current)
            .. ":" .. tostring(party.serial))),
        day = worldDay(), place = episode.place, placeKind = episode.placeKind,
        timeOfDay = timeOfDay(episode.hour), kills = episode.kills,
        closeCall = episode.closeCall, weapon = episode.weapon,
        witnesses = witnesses, playerThere = episode.playerThere == true,
        tellings = 0, lastToldHour = -1,
    })
    bucket.list[#bucket.list + 1] = tale
    evict(bucket)
    persist(actor)
    if SC.Diary and type(SC.Diary.noteTale) == "function" then
        pcall(SC.Diary.noteTale, actor, tale)
    end
    for _, id in ipairs(tale.witnesses) do
        local record = SC.Registry and type(SC.Registry.byId) == "function"
            and SC.Registry.byId(id) or nil
        local witnessCommands = record and record.actor and commandsOf(record.actor) or nil
        local witnessBucket = witnessCommands and Tales.bucket(witnessCommands) or nil
        if witnessBucket then
            witnessBucket.witnessed[#witnessBucket.witnessed + 1] = {
                id = tale.id, teller = tellerId, kills = tale.kills,
            }
            while #witnessBucket.witnessed > 12 do table.remove(witnessBucket.witnessed, 1) end
            persist(record.actor)
        end
    end
    return tale
end

-- An episode closes after a quiet gap with the killer out of danger. It
-- becomes a tale with enough kills, or with a close call and at least one.
local function closeEpisodes(current)
    local gap = config("taleEpisodeGapMs", 30000)
    local minimum = config("taleMinKills", 4)
    local byActor = {}
    for _, record in ipairs(records()) do
        if type(record) == "table" and record.actor ~= nil then byActor[record.actor] = record end
    end
    local closing = {}
    for actor, episode in pairs(episodes) do
        local utility = U()
        if not utility.isValidActor(actor) or utility.isDead(actor) then
            closing[#closing + 1] = { actor = actor, keep = false }
        else
            local health = tonumber(utility.nativeHealth(actor))
            if health and episode.startHealth - health >= config("taleHurtDrop", 25)
                and episode.closeCall == nil then
                episode.closeCall = "hurt"
            end
            if current - episode.lastEventAt >= gap and calm(recordSnapshot(byActor[actor])) then
                closing[#closing + 1] = { actor = actor, keep = episode.kills >= minimum
                    or (episode.closeCall ~= nil and episode.kills >= 1) }
            end
        end
    end
    local stored = 0
    for _, item in ipairs(closing) do
        local episode = episodes[item.actor]
        episodes[item.actor] = nil
        if item.keep and episode and storeTale(item.actor, episode, current) then
            stored = stored + 1
        end
        party.lastEpisodeEndedAt = current
    end
    return stored
end

function Tales.toldCount(kills, telling)
    kills = math.max(0, math.floor(tonumber(kills) or 0))
    local factor = GROWTH[math.min(#GROWTH, math.max(1, math.floor(tonumber(telling) or 1)))]
    return math.max(kills, math.floor(kills * factor + 0.5))
end

-- Title case without the leading article; proper names ("Spiffo's") keep
-- no article of their own.
local function titled(place)
    local bare, article = tostring(place or ""), ""
    for _, prefix in ipairs({ "the ", "a ", "somebody's " }) do
        if string.sub(bare, 1, #prefix) == prefix then
            bare, article = string.sub(bare, #prefix + 1), "the "
            break
        end
    end
    -- A plain loop: Kahlua's gsub may hand a function replacement nil captures.
    local out, wordStart = {}, true
    for index = 1, #bare do
        local char = string.sub(bare, index, index)
        if char == " " then
            wordStart = true
        elseif wordStart then
            char, wordStart = string.upper(char), false
        end
        out[#out + 1] = char
    end
    return table.concat(out), article
end

-- "that thing at the gas station" -> "the Battle of the Gas Station" ->
-- "the Gas Station Massacre of '93" -> "the Legend of the Gas Station".
function Tales.title(tale, telling)
    telling = math.max(1, math.floor(tonumber(telling) or 1))
    local open = type(tale) == "table" and tale.placeKind == "open"
    local place = type(tale) == "table" and tale.place or "out in the open"
    local name, article = "Nowhere", ""
    if not open then name, article = titled(place) end
    if telling <= 1 then return "that thing " .. (open and place or ("at " .. place)) end
    if telling <= 3 then return "the Battle of " .. article .. name end
    if telling == 4 then return "the " .. name .. " Massacre of '93" end
    return "the Legend of " .. article .. name
end

local function roll(percent, seed)
    percent = tonumber(percent) or 0
    if percent >= 100 then return true end
    if percent <= 0 then return false end
    if type(ZombRand) == "function" then
        local ok, value = pcall(ZombRand, 100)
        if ok and tonumber(value) then return tonumber(value) < percent end
    end
    return math.abs(tonumber(U().stableHash(seed)) or 0) % 100 < percent
end

local function nearbyWitness(tale, teller)
    local utility = U()
    local radius = config("taleCorrectionRadius", 8)
    for _, id in ipairs(tale.witnesses or {}) do
        local record = SC.Registry and type(SC.Registry.byId) == "function"
            and SC.Registry.byId(id) or nil
        local other = record and record.actor or nil
        local commands = other and commandsOf(other) or nil
        local bucket = commands and Tales.bucket(commands) or nil
        local stub
        for _, entry in ipairs(bucket and bucket.witnessed or {}) do
            if entry.id == tale.id then stub = entry break end
        end
        if stub and other ~= teller and not utility.isDead(other)
            and calm(recordSnapshot(record)) and utility.sameFloor(teller, other)
            and utility.distance(teller, other) <= radius then
            return other, commands, stub
        end
    end
    return nil
end

local function arguments(first, count, guest, name, weapon)
    return { tostring(first), tostring(count), tostring(guest), tostring(name), tostring(weapon) }
end

-- The beats of one telling. The numbers grow with each telling; the second
-- is suddenly pitch dark, the third gains an absurd guest, the fourth an
-- injury, and the title climbs. A witness nearby may state the true count.
local function buildBeats(teller, tale, player, current)
    local telling = (tale.tellings or 0) + 1
    local count = Tales.toldCount(tale.kills, telling)
    local seed = tostring(tale.id) .. ":" .. tostring(telling)
    local guest = GUESTS[(math.abs(tonumber(U().stableHash(seed .. ":guest")) or 0) % #GUESTS) + 1]
    local function beat(actor, topic, args)
        return { actor = actor, topic = topic, args = args }
    end
    local story = arguments(tale.place, count, guest, firstName(teller), tale.weapon)
    local beats = {
        beat(teller, "tales.open", arguments(Tales.title(tale, telling), count, guest,
            firstName(teller), tale.weapon)),
        beat(teller, "tales.body", story),
    }
    if telling >= 2 then beats[#beats + 1] = beat(teller, "tales.dark", story) end
    if telling >= 3 then beats[#beats + 1] = beat(teller, "tales.guest", story) end
    if telling >= 4 then beats[#beats + 1] = beat(teller, "tales.injury", story) end
    if tale.closeCall == "grabbed" then
        beats[#beats + 1] = beat(teller, "tales.grabbed", story)
    elseif tale.closeCall == "hurt" then
        beats[#beats + 1] = beat(teller, "tales.hurt", story)
    end
    beats[#beats + 1] = beat(teller, "tales.close", story)
    if count > tale.kills then
        local witness, _, stub = nearbyWitness(tale, teller)
        if witness and roll(config("taleWitnessCorrectChancePercent", 70), seed .. ":witness") then
            beats[#beats + 1] = beat(witness, "tales.correction", arguments(tale.place,
                stub.kills, guest, firstName(teller), tale.weapon))
            local utility = U()
            if tale.playerThere and player ~= nil and utility.sameFloor(teller, player)
                and utility.distance(teller, player) <= config("ambientDialogueDistance", 10) then
                beats[#beats + 1] = beat(teller, "tales.appeal", story)
            else
                beats[#beats + 1] = beat(teller, "tales.doubledown", arguments(tale.place,
                    stub.kills, guest, firstName(witness), tale.weapon))
            end
        end
    end
    return beats, count, telling
end

local function banter()
    return type(SC.Banter) == "table" and SC.Banter or nil
end

local function speak(beat, current)
    if not SC.Dialogue or type(SC.Dialogue.say) ~= "function" then return false end
    registerPools()
    local ok, spoken = pcall(SC.Dialogue.say, beat.actor, beat.topic, nil, beat.args, {
        state = commandsOf(beat.actor), recentLimit = 6,
        salt = beat.topic .. ":" .. tostring(current),
    })
    return ok and spoken == true
end

local function finishTelling(current, completed)
    local telling = party.telling
    party.telling = nil
    if not telling then return end
    if completed or telling.spoken >= 2 then
        telling.tale.tellings = math.min(99, (telling.tale.tellings or 0) + 1)
        telling.tale.lastToldHour = worldHours()
        persist(telling.teller)
        if SC.Diary and type(SC.Diary.noteTaleTold) == "function" and telling.number then
            pcall(SC.Diary.noteTaleTold, telling.teller, telling.tale, telling.toldCount,
                telling.number, Tales.title(telling.tale, telling.number))
        end
    end
    party.lastTellAt = current
end

local function advanceTelling(current)
    local telling = party.telling
    local utility = U()
    local teller = telling.teller
    if teller == nil or not utility.isValidActor(teller) or utility.isDead(teller)
        or not calm(recordSnapshot(telling.record)) then
        finishTelling(current, false)
        return false, "tale_interrupted"
    end
    if current < telling.nextAt then return true, "tale_pausing" end
    local beat = telling.beats[telling.index]
    if beat == nil then
        finishTelling(current, true)
        return false, "tale_finished"
    end
    telling.index = telling.index + 1
    telling.nextAt = current + config("taleBeatMs", 5000)
    local speaker = beat.actor
    if speaker ~= nil and utility.isValidActor(speaker) and not utility.isDead(speaker)
        and speak(beat, current) then
        telling.spoken = telling.spoken + 1
        local owner = banter()
        if owner and type(owner.spendBudget) == "function" then owner.spendBudget(current) end
    end
    return true, beat.topic
end

local function readyTale(bucket, hours)
    local cooldown = config("taleRetellCooldownHours", 48)
    local best, bestScore
    for _, tale in ipairs(bucket and bucket.list or {}) do
        if (tonumber(tale.kills) or 0) > 0
            and ((tonumber(tale.lastToldHour) or -1) < 0 or hours - tale.lastToldHour >= cooldown) then
            local score = taleWeight(tale) - (tale.tellings or 0)
            if bestScore == nil or score > bestScore then best, bestScore = tale, score end
        end
    end
    return best
end

-- A telling starts only in a settled moment: the teller at base, or the
-- player standing still for a while, with the player close enough to listen.
local function startTelling(player, list, current)
    local owner = banter()
    if player == nil or owner == nil or type(owner.availableSpeaker) ~= "function" then
        return false, "tales_no_audience"
    end
    if current - party.lastTellAt < config("taleTellPartyCooldownMs", 1800000) then
        return false, "tales_cooldown"
    end
    if type(owner.budgetAllows) == "function" and not owner.budgetAllows(current) then
        return false, "flavor_budget"
    end
    local idle = type(owner.playerIdleMs) == "function" and owner.playerIdleMs(current) or 0
    local settledPlayer = idle >= config("taleIdleMs", 60000)
    local hours = worldHours()
    local radius = config("ambientDialogueDistance", 10)
    local best, bestRecord, bestTale, bestScore
    for _, record in ipairs(list) do
        local commands = owner.availableSpeaker(record, player, current, radius)
        if commands then
            local atBase = SC.BaseLife and type(SC.BaseLife.isInside) == "function"
                and SC.BaseLife.isInside(record.actor) == true
            local tale = (atBase or settledPlayer) and readyTale(Tales.bucket(commands), hours) or nil
            local score = tale and taleWeight(tale) or nil
            if score and (bestScore == nil or score > bestScore) then
                best, bestRecord, bestTale, bestScore = record.actor, record, tale, score
            end
        end
    end
    if best == nil then return false, "tales_no_teller" end
    local beats, toldCount, tellingNumber = buildBeats(best, bestTale, player, current)
    party.telling = {
        teller = best, record = bestRecord, tale = bestTale, beats = beats,
        index = 1, nextAt = current, spoken = 0, startedAt = current,
        toldCount = toldCount, number = tellingNumber,
    }
    return advanceTelling(current)
end

-- One pulse from Banter: close finished fights, then continue or start a
-- telling. Returns true while a telling holds the party's flavor voice.
function Tales.update(player, list, current)
    local utility = U()
    if config("talesEnabled", true) == false then return false, "tales_disabled" end
    current = tonumber(current) or utility.nowMs()
    list = type(list) == "table" and list or records()
    closeEpisodes(current)
    if party.telling then return advanceTelling(current) end
    return startTelling(player, list, current)
end

function Tales.lastEpisodeEndedAt()
    return party.lastEpisodeEndedAt
end

function Tales.isTelling(actor)
    return party.telling ~= nil and (actor == nil or party.telling.teller == actor)
end

function Tales.reset(actor)
    if actor ~= nil then
        episodes[actor] = nil
        if party.telling and party.telling.teller == actor then party.telling = nil end
        return true
    end
    episodes = setmetatable({}, { __mode = "k" })
    checkedBuckets = setmetatable({}, { __mode = "k" })
    party = freshParty()
    return true
end

-- Test seams.
function Tales._episodesForTests()
    return episodes
end

function Tales._partyForTests()
    return party
end

function Tales._poolsForTests()
    return POOLS
end

return Tales
