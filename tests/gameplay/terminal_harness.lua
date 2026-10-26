-- SPDX-License-Identifier: MIT
-- EMMA, the camp computer: her lines, how she reads plain English (intents,
-- typos, names, follow-ups and yes/no), the answers she builds from camp
-- facts, her memory, and the live world adapter against fake game objects.
-- Random picks are fixed by an injected roll, so every answer is exact.

local SC = SurvivorCompanion
local Brain, Lines, World = SC.TerminalBrain, SC.TerminalLines, SC.TerminalWorld
local checks = 0
local function check(value, message)
    checks = checks + 1
    if not value then error("terminal check " .. checks .. ": " .. tostring(message)) end
end

local function joined(reply)
    return table.concat(reply.lines or {}, "\n")
end

local function has(reply, fragment)
    return string.find(joined(reply), fragment, 1, true) ~= nil
end

local function firstRoll() return 1 end

local function fixtureWorld(overrides)
    local world = {
        camp = function() return { configured = true, inside = true, name = "Rising" } end,
        clock = function()
            return { hour = 14, minute = 5, day = 12, month = 6, year = 1993, worldHours = 77, days = 3 }
        end,
        weather = function() return { temperature = 14, rain = 0.4, fog = 0, wind = 0.1, snow = false } end,
        power = function() return { source = "generator", fuel = 62, condition = 88 } end,
        people = function()
            return {
                { id = "sc-1", name = "Kate Miller", health = 42, bleeding = true, doing = "Chopping wood",
                    where = "at camp, 12 meters north-east", morale = 40, stress = 70 },
                { id = "sc-2", name = "Bob Fisher", health = 95, doing = "Idle",
                    where = "at camp, right here", morale = 60, stress = 20 },
                { id = "sc-3", name = "Will Turner", health = 100, doing = "Hauling",
                    where = "31 meters south" },
                { id = "sc-4", name = "Doc", away = true },
            }
        end,
        jobs = function()
            return { active = 2, pending = 3, blocked = 1, rows = {
                { state = "active", job = "Chop wood", who = "Kate Miller" },
                { state = "active", job = "Haul", who = "Will Turner" },
                { state = "blocked", job = "Build wall", reason = "Missing materials" },
                { state = "pending", job = "Farm" },
            } }
        end,
        storage = function()
            return { containers = 5, items = 279, truncated = false, groups = {
                { name = "Nails", type = "Base.Nails", category = "Material", count = 214,
                    where = { "shelves (materials)", "crate (tools)" } },
                { name = "Box of Nails", type = "Base.NailsBox", category = "Material", count = 2,
                    where = { "crate (tools)" } },
                { name = "Screws", type = "Base.Screws", category = "Material", count = 50,
                    where = { "crate (tools)" } },
                { name = "Canned Beans", type = "Base.TinnedBeans", category = "Food", food = true,
                    kcal = 1800, count = 6, where = { "shelves (food)" } },
                { name = "Water Bottle", type = "Base.WaterBottle", category = "Water", count = 4,
                    where = { "fridge (food)" } },
                { name = "Bandage", type = "Base.Bandage", category = "FirstAid", count = 3,
                    where = { "counter (medical)" } },
            } }
        end,
        zombies = function() return { count = 3, radius = 40, nearest = 17.4, dir = "north-west" } end,
        expedition = function()
            return { active = true, leader = "Doc", kind = "wood", members = { "Doc" },
                collected = 12, requested = 40 }
        end,
    }
    for key, value in pairs(overrides or {}) do world[key] = value end
    return world
end

local function session(options)
    options = options or {}
    options.random = options.random or firstRoll
    options.operator = options.operator or "Thor"
    return Brain.newSession(options)
end

-- ---------------------------------------------------------------------------
-- Lines: ASCII, known fields, no swearing, nothing borrowed
-- ---------------------------------------------------------------------------
do
    local allowed = {}
    for field in string.gmatch("name away alive power note n who state health extra doing where q "
        .. "active pending blocked job reason item count label containers items kcal mouths days_food "
        .. "r d dir leader kind collected requested members pct fuel condition time date days tempF "
        .. "tempC sky people hurt weather threat suggest", "%S+") do
        allowed[field] = true
    end
    local banned = { "damn", "hell", "shit", "fuck", "ass", "bastard", "bitch", "christ",
        "claude", "openai", "chatgpt", "glados", "aperture", "portal", "cake", "neurotoxin",
        "for science", "test chamber" }
    local seen = 0
    local function lint(value, where)
        if type(value) == "table" then
            check(#value > 0, where .. " is not empty")
            for index, entry in ipairs(value) do lint(entry, where .. "[" .. index .. "]") end
            return
        end
        check(type(value) == "string", where .. " is text")
        seen = seen + 1
        check(not string.find(value, "[^ -~]"), where .. " is printable ASCII: " .. value)
        check(#value <= 220, where .. " fits a terminal paragraph")
        for field in string.gmatch(value, "{([%w_]+)}") do
            check(allowed[field], where .. " uses a known field {" .. field .. "}")
        end
        local lower = " " .. string.lower(value) .. " "
        for _, word in ipairs(banned) do
            check(not string.find(lower, "[^%a]" .. word .. "[^%a]"), where .. " avoids '" .. word .. "'")
        end
    end
    lint(Lines.BOOT, "BOOT")
    lint(Lines.HELP, "HELP")
    lint(Lines.DIR, "DIR")
    lint(Lines.TITLE, "TITLE")
    for name, pool in pairs(Lines.POOLS) do lint(pool, "POOLS." .. name) end
    for name, steps in pairs(Lines.THINK) do lint(steps, "THINK." .. name) end
    for name, template in pairs(Lines.T) do lint(template, "T." .. name) end
    check(seen > 250, "EMMA has a real vocabulary (" .. seen .. " lines)")
    for _, pool in ipairs({ "greet_first", "greet_back", "greet_long", "joke", "fallback", "insult",
        "insult_again", "bye", "remember_ok", "math", "math_zero", "ack" }) do
        check(type(Lines.POOLS[pool]) == "table" and #Lines.POOLS[pool] >= 1, "pool " .. pool .. " exists")
    end
    for _, pool in ipairs({ "joke", "fallback", "identity", "greet_first", "bye", "insult" }) do
        check(#Lines.POOLS[pool] >= 4, "pool " .. pool .. " has room to vary")
    end
end

-- ---------------------------------------------------------------------------
-- Text plumbing
-- ---------------------------------------------------------------------------
do
    check(Brain.distance("help", "hlep", 1) == 1, "a swapped pair is one edit")
    check(Brain.distance("generator", "generater", 2) == 1, "one wrong letter is one edit")
    check(Brain.distance("weather", "wether", 1) == 1, "a dropped letter is one edit")
    check(Brain.distance("nails", "fails", 1) == 1 and Brain.distance("abc", "xyzuvw", 2) == 3,
        "distance stops past its limit")
    check(Brain.singular("boxes") == "box" and Brain.singular("batteries") == "battery"
        and Brain.singular("glass") == "glass" and Brain.singular("nails") == "nail"
        and Brain.singular("matches") == "match", "plurals reduce to a stem")
    local tokens = Brain.tokens("What's the WEATHER like, Emma?!")
    check(table.concat(tokens, " ") == "what is the weather like emma", "tokens are lower case and expanded")
    check(table.concat(Brain.tokens("u r gonna hate me"), " ") == "you are going to hate me",
        "chat shorthand expands")
    check(Brain.fill("{a} and {b} {c}", { a = 1, b = "two" }) == "1 and two {c}",
        "unknown fields stay visible so tests catch them")
    check(Brain.duration(0.25) == "15 minutes" and Brain.duration(1) == "1 hour"
        and Brain.duration(30) == "30 hours" and Brain.duration(80) == "3 days",
        "durations read like speech")
    check(Brain.numberText(1234567) == "1,234,567" and Brain.numberText(2.5) == "2.5"
        and Brain.numberText(1 / 3) == "0.3333", "numbers print with commas or four decimals")
end

-- ---------------------------------------------------------------------------
-- Arithmetic is parsed, never compiled
-- ---------------------------------------------------------------------------
do
    local function calc(text)
        local expression, value = Brain.arithmetic(text)
        return expression, value
    end
    local expression, value = calc("2+2")
    check(expression == "2+2" and value == 4, "2+2 is 4")
    expression, value = calc("what is 12 x 3?")
    check(expression == "12 x 3" and value == 36, "x means times and the question is stripped")
    expression, value = calc("calculate (4+6)/2")
    check(value == 5, "parentheses group")
    expression, value = calc("2+3*4")
    check(value == 14, "multiplication binds first")
    expression, value = calc("-3+10")
    check(value == 7, "a leading minus is a sign")
    expression, value = calc("-5")
    check(value == nil and expression == nil, "a bare negative number is not a sum")
    expression, value = calc("10/0")
    check(expression == "10/0" and value == nil, "division by zero is caught, not computed")
    expression, value = calc("0/0")
    check(expression == "0/0" and value == nil, "zero over zero has no answer either")
    check(calc("2+") == nil and calc("(2+3") == nil and calc("hello 2+2") == nil
        and calc("1993") == nil and calc(string.rep("1+", 30) .. "1") == nil,
        "broken, wordy, operator-free and overlong input is not maths")
    check(calc("os.exit()") == nil and calc("2+2;print(1)") == nil, "code is never accepted")
end

-- ---------------------------------------------------------------------------
-- Intents: how EMMA reads plain English
-- ---------------------------------------------------------------------------
do
    local world = fixtureWorld()
    local cases = {
        { "help", "help" }, { "HELP", "help" }, { "help me", "help" }, { "what can you do", "help" },
        { "commands", "help" }, { "menu", "help" }, { "how does this work", "help" },
        { "hlep", "help" }, { "hepl", "help" }, { "?", "help" },
        { "clear", "clear" }, { "cls", "clear" }, { "CLS", "clear" },
        { "exit", "exit" }, { "quit", "exit" }, { "bye", "exit" }, { "goodbye", "exit" },
        { "log off", "exit" }, { "see you", "exit" }, { "gotta go", "exit" }, { "i have to go", "exit" },
        { "what", "repeat" }, { "what?", "repeat" }, { "huh", "repeat" }, { "say that again", "repeat" },
        { "ls", "dir" }, { "dir", "dir" }, { "ls -la", "dir" },
        { "whoami", "whoami" }, { "who am i", "whoami" }, { "what's my name", "whoami" },
        { "remember me?", "whoami" }, { "do you know who i am", "whoami" },
        { "notes", "recall" }, { "what did i tell you", "recall" }, { "what do you remember", "recall" },
        { "show notes", "recall" },
        { "forget everything", "forget" }, { "clear notes", "forget" }, { "delete notes", "forget" },
        { "remember the red key is in the van", "remember" }, { "Remember that Kate hates fish", "remember" },
        { "note: fuel in the shed", "remember" }, { "write down gate code 4512", "remember" },
        { "call me Thor", "callme" }, { "my name is Ann", "callme" },
        { "status", "status" }, { "report", "status" }, { "sitrep", "status" },
        { "give me a status report", "status" }, { "how are things", "status" },
        { "what's going on", "status" }, { "whats happening", "status" }, { "overview", "status" },
        { "stauts", "status" },
        { "will we survive", "odds" }, { "are we going to die?", "odds" }, { "what are our odds", "odds" },
        { "survival chances", "odds" }, { "will we make it", "odds" },
        { "advice", "advice" }, { "what should i do", "advice" }, { "what should we do now", "advice" },
        { "any tips", "advice" }, { "what now", "advice" }, { "what next", "advice" },
        { "recommend something", "advice" }, { "what is the priority", "advice" },
        { "who is hurt", "people_hurt" }, { "anyone hurt?", "people_hurt" },
        { "is anyone injured", "people_hurt" }, { "who is wounded", "people_hurt" },
        { "is anybody bleeding", "people_hurt" }, { "who needs a doctor", "people_hurt" },
        { "health report", "people_hurt" }, { "who is sick", "people_hurt" }, { "hurt", "people_hurt" },
        { "morale", "people_mood" }, { "how is everyone feeling", "people_mood" }, { "mood", "people_mood" },
        { "is anyone stressed", "people_mood" },
        { "who is here", "people_list" }, { "survivors", "people_list" }, { "list people", "people_list" },
        { "who is alive", "people_list" }, { "where is everyone", "people_list" }, { "roster", "people_list" },
        { "headcount", "people_list" }, { "how many people do we have", "people_list" },
        { "how many survivors", "people_list" }, { "show me the crew", "people_list" },
        { "survivers", "people_list" }, { "how is everyone", "people_list" },
        { "any problems", "blocked" }, { "what is wrong", "blocked" }, { "whats wrong", "blocked" },
        { "anything stuck", "blocked" }, { "blocked jobs", "blocked" }, { "problems", "blocked" },
        { "jobs", "jobs" }, { "what is everyone doing", "jobs" }, { "what are they doing", "jobs" },
        { "who is working", "jobs" }, { "work orders", "jobs" }, { "tasks", "jobs" },
        { "is anyone working", "jobs" },
        { "food", "food" }, { "how much food", "food" }, { "how much food do we have", "food" },
        { "do we have food", "food" }, { "calories", "food" }, { "are we starving", "food" },
        { "rations", "food" },
        { "zombies", "zombies" }, { "any zombies", "zombies" }, { "how many zombies", "zombies" },
        { "is it safe", "zombies" }, { "is it safe outside", "zombies" }, { "zeds?", "zombies" },
        { "zombeis", "zombies" }, { "any walkers nearby", "zombies" }, { "undead", "zombies" },
        { "expedition", "expedition" }, { "how is the expedition", "expedition" },
        { "where is the away team", "expedition" }, { "when are they back", "expedition" },
        { "any news on the radio", "expedition" },
        { "power", "power" }, { "electricity", "power" }, { "generator", "power" },
        { "how much fuel is left", "power" }, { "generater", "power" }, { "is the power on", "power" },
        { "weather", "weather" }, { "what's the weather like", "weather" }, { "is it raining", "weather" },
        { "temperature", "weather" }, { "cold outside?", "weather" }, { "waether", "weather" },
        { "temprature", "weather" },
        { "time", "time" }, { "what time is it", "time" }, { "date", "time" }, { "what day is it", "time" },
        { "how long have we survived", "time" }, { "what year is it", "time" },
        { "how many nails", "storage" }, { "how many nails do we have", "storage" },
        { "do we have any screws", "storage" }, { "count bandages", "storage" },
        { "inventory", "storage" }, { "storage", "storage" }, { "supplies", "storage" },
        { "where is the hammer", "storage" }, { "how much water", "storage" },
        { "any ammo left", "storage" }, { "how many boxes of nails", "storage" },
        { "nails", "storage" }, { "screws?", "storage" },
        { "who are you", "identity" }, { "what are you", "identity" }, { "your name?", "identity" },
        { "introduce yourself", "identity" }, { "are you a robot", "identity" },
        { "are you alive", "alive" }, { "are you real", "alive" }, { "are you sentient", "alive" },
        { "do you dream", "alive" },
        { "how are you", "feelings" }, { "how are you doing", "feelings" }, { "are you ok", "feelings" },
        { "are you lonely", "feelings" },
        { "tell me a joke", "joke" }, { "joke", "joke" }, { "make me laugh", "joke" },
        { "write a poem", "poem" }, { "haiku please", "poem" },
        { "tell me a story", "story" }, { "sing me a song", "sing" }, { "play some music", "sing" },
        { "thanks", "thanks" }, { "thank you", "thanks" }, { "thx", "thanks" }, { "ty", "thanks" },
        { "much appreciated", "thanks" }, { "thanks kate", "thanks" },
        { "sorry", "sorry" }, { "my bad", "sorry" },
        { "you are stupid", "insult" }, { "shut up", "insult" }, { "i hate you", "insult" },
        { "useless machine", "insult" },
        { "i love you", "love" }, { "will you marry me", "love" },
        { "good job", "compliment" }, { "well done", "compliment" }, { "you are smart", "compliment" },
        { "what is the meaning of life", "meaning" }, { "why are we here", "meaning" },
        { "is help coming", "rescue" }, { "is anyone out there", "rescue" }, { "evacuation", "rescue" },
        { "is there a cure", "cure" }, { "i got bitten", "cure" }, { "vaccine", "cure" },
        { "what happened", "lore" }, { "what about the military", "lore" }, { "outbreak", "lore" },
        { "rm -rf /", "delete" }, { "delete yourself", "delete" },
        { "hack", "hack" }, { "admin password", "hack" }, { "override", "hack" },
        { "lets play a game", "game" }, { "chess", "game" }, { "tic tac toe", "game" },
        { "shutdown", "shutdown" }, { "shut down", "shutdown" }, { "reboot", "shutdown" },
        { "goodnight", "sleep" }, { "good night", "sleep" }, { "going to bed", "sleep" },
        { "hello", "hello" }, { "hi", "hello" }, { "hey emma", "hello" }, { "good morning", "hello" },
        { "anyone there?", "hello" }, { "yo", "hello" },
        { "yes", "yes" }, { "no", "no" }, { "ok", "ack" },
        { "sudo make me a sandwich", "sudo" },
        { "2+2", "math" }, { "what is 12 x 3", "math" }, { "10/0", "math" },
        { "how is kate", "person" }, { "where is kate", "person" }, { "kate", "person" },
        { "is kate hurt", "person" }, { "what is kate doing", "person" }, { "where is bob", "person" },
        { "bob", "person" }, { "how is will", "person" }, { "katie", "person" }, { "doc", "person" },
        { "who will work tonight", "jobs" },
        { "", "empty" }, { "   ", "empty" }, { "sdfghjkl", "mash" }, { "qwrtpsdf", "mash" },
    }
    check(#cases >= 150, "the phrasing table covers " .. #cases .. " inputs")
    for _, case in ipairs(cases) do
        local probe = session()
        local intent = Brain.parse(probe, case[1], world)
        check(intent == case[2], "'" .. case[1] .. "' reads as " .. case[2] .. ", got " .. tostring(intent))
    end
    local probe = session()
    local intent, slots = Brain.parse(probe, "katie", world)
    check(intent == "person" and slots.person.name == "Kate Miller", "a close misspelling finds Kate")
    intent, slots = Brain.parse(probe, "will we survive", world)
    check(intent == "odds", "a common-word name is not mistaken for the word")
    intent, slots = Brain.parse(probe, "Remember that Kate hates fish", world)
    check(intent == "remember" and slots.note == "Kate hates fish", "a note keeps its words and case")
    intent, slots = Brain.parse(probe, "how many boxes of nails", world)
    check(intent == "storage" and table.concat(slots.item, " ") == "box nail"
        and table.concat(slots.itemText, " ") == "boxes of nails", "an item query keeps its own words")
end

-- ---------------------------------------------------------------------------
-- Answers built from camp facts
-- ---------------------------------------------------------------------------
do
    local world = fixtureWorld()
    local s = session()
    local reply = Brain.respond(s, "how many nails", world)
    check(has(reply, "216 nails in camp storage.") and has(reply, "214 x Nails")
        and has(reply, "2 x Box of Nails") and has(reply, "Stored in: shelves (materials) and crate (tools)."),
        "nails are counted across groups with places: " .. joined(reply))
    check(reply.category == "storage" and #reply.think >= 2 and reply.thinkMs >= 650 and reply.thinkMs <= 2500,
        "a storage question thinks like it is searching")
    reply = Brain.respond(s, "and screws?", world)
    check(has(reply, "50 screws in camp storage."), "a follow-up reuses the storage question")
    reply = Brain.respond(s, "how many of them", world)
    check(has(reply, "50 screws in camp storage."), "'them' refers to the last item")
    reply = Brain.respond(s, "how many boxes of nails", world)
    check(has(reply, "2 boxes of nails in camp storage."), "a two-word item narrows the match")
    reply = Brain.respond(s, "how many rifles", world)
    check(has(reply, "No rifles in camp storage."), "a missing item is reported as none")
    reply = Brain.respond(s, "how many nials", world)
    check(has(reply, "nials in camp storage") and has(reply, "214 x Nails") == true, "a misspelt item still matches")
    reply = Brain.respond(s, "count bandages", world)
    check(has(reply, "3 bandages in camp storage."), "a single group prints no table")
    reply = Brain.respond(s, "any medicine?", world)
    check(has(reply, "3 medicine in camp storage."), "a category word matches by display category")
    reply = Brain.respond(s, "inventory", world)
    check(has(reply, "5 storage containers on file, 279 items counted.") and has(reply, "214 x Nails"),
        "inventory gives an overview")
    reply = Brain.respond(s, "how much food", world)
    check(has(reply, "6 food items, about 1,800 calories. For 4 mouths, that is roughly 0.2 days."),
        "food counts calories and mouths present: " .. joined(reply))

    reply = Brain.respond(s, "who is hurt", world)
    check(has(reply, "1 of your people need attention:") and has(reply, "Kate Miller .... health 42 percent, bleeding, stressed"),
        "the hurt list names Kate with what is wrong: " .. joined(reply))
    reply = Brain.respond(s, "who is here", world)
    check(has(reply, "4 survivors on file:") and has(reply, "Kate Miller .... at camp, 12 meters north-east, chopping wood")
        and has(reply, "Doc .... out on the expedition"), "the roster says where everyone is")
    reply = Brain.respond(s, "how is kate", world)
    check(has(reply, "Kate Miller: health 42 percent, bleeding, stressed. Chopping wood.")
        and has(reply, "Kate Miller is at camp, 12 meters north-east."), "a person report: " .. joined(reply))
    reply = Brain.respond(s, "is she hurt", world)
    check(has(reply, "Kate Miller: health 42"), "'she' refers to the last person")
    reply = Brain.respond(s, "any zombies", world)
    reply = Brain.respond(s, "and now?", world)
    check(reply.intent == "zombies" and has(reply, "3 of them"), "'and now?' asks the last question again")
    reply = Brain.respond(s, "how about the power", world)
    check(reply.intent == "power", "'how about' leads into a new topic")
    reply = Brain.respond(s, "what about bob", world)
    check(has(reply, "Bob Fisher: health 95 percent. Idle."), "a follow-up can switch person")
    reply = Brain.respond(s, "where is doc", world)
    check(has(reply, "Doc is out with the expedition."), "an away member is not located")
    reply = Brain.respond(s, "where is mallory", world)
    check(reply.intent ~= "person", "an unknown name is not invented")

    reply = Brain.respond(s, "what is everyone doing", world)
    check(has(reply, "Work: 2 in progress, 3 waiting, 1 blocked.") and has(reply, "Kate Miller .... chop wood"),
        "jobs list who does what")
    reply = Brain.respond(s, "any problems", world)
    check(has(reply, "1 blocked:") and has(reply, "Build wall .... Missing materials"), "blocked jobs give reasons")
    reply = Brain.respond(s, "power", world)
    check(has(reply, "Running on generator power. Fuel 62 percent, condition 88 percent."), "generator power")
    reply = Brain.respond(s, "time", world)
    check(has(reply, "It is 2:05 PM on July 12, 1993. Day 4 on my clock."), "time and date: " .. joined(reply))
    reply = Brain.respond(s, "weather", world)
    check(has(reply, "Outside: 57 F, 14 C. Rain."), "weather in both scales: " .. joined(reply))
    reply = Brain.respond(s, "any zombies", world)
    check(has(reply, "3 of them within 40 meters of this terminal. The closest is 17 meters north-west."),
        "movement near the terminal")
    reply = Brain.respond(s, "expedition", world)
    check(has(reply, "Doc is leading a wood expedition.") and has(reply, "Last word: 12 of 40 collected."),
        "expedition news")
    reply = Brain.respond(s, "status", world)
    check(has(reply, "Camp report, 2:05 PM, day 4.") and has(reply, "4 on file, 1 hurt, 1 away")
        and has(reply, "2 in progress, 3 waiting, 1 blocked") and has(reply, "generator, fuel 62%")
        and has(reply, "57 F, rain") and has(reply, "3 within 40 meters") and has(reply, "about 0.2 days for 4 mouths"),
        "status collects everything: " .. joined(reply))
    reply = Brain.respond(s, "what should i do", world)
    check(has(reply, "Kate Miller is bleeding."), "advice puts bleeding first")
    reply = Brain.respond(s, "2+2", world)
    check(reply.lines[1] == "2+2 = 4.", "maths answers")
    reply = Brain.respond(s, "10/0", world)
    check(#reply.lines == 1 and not has(reply, "="), "division by zero gets a remark instead")
end

-- ---------------------------------------------------------------------------
-- Advice order, the survival estimate and camp access
-- ---------------------------------------------------------------------------
do
    local calm = {
        { id = "a", name = "Ann", health = 100, doing = "Idle" },
    }
    local function advise(overrides)
        local world = fixtureWorld(overrides)
        return Brain.respond(session(), "advice", world)
    end
    local reply = advise({ people = function() return { { id = "a", name = "Ann", health = 30 } } end })
    check(has(reply, "Treat Ann first. Health 30 percent."), "low health comes next")
    reply = advise({ people = function() return calm end,
        power = function() return { source = "generator", fuel = 12, condition = 90 } end })
    check(has(reply, "Refuel the generator. 12 percent left."), "then generator fuel")
    reply = advise({ people = function() return calm end,
        zombies = function() return { count = 9, radius = 40, nearest = 5, dir = "east" } end })
    check(has(reply, "There are 9 of them near this building."), "then a crowd outside")
    reply = advise({ people = function() return calm end,
        zombies = function() return { count = 0, radius = 40 } end })
    check(has(reply, "Fix the stuck work order: Build wall. Missing materials."), "then blocked work")
    reply = advise({ people = function() return calm end,
        zombies = function() return { count = 0, radius = 40 } end,
        jobs = function() return { active = 0, pending = 0, blocked = 0, rows = {} } end })
    check(has(reply, "Find food. You have about 0.5 days."), "then food: " .. joined(reply))
    reply = advise({ people = function() return calm end,
        zombies = function() return { count = 0, radius = 40 } end,
        jobs = function() return { active = 0, pending = 0, blocked = 0, rows = {} } end,
        storage = function() return { containers = 1, items = 40, groups = {
            { name = "Rice", category = "Food", food = true, kcal = 40000, count = 40 } } } end,
        clock = function() return { hour = 23, minute = 30, day = 1, month = 6, year = 1993, days = 1 } end })
    check(has(reply, "It is 11:30 PM. Sleep."), "then sleep at night")
    reply = advise({ people = function() return calm end,
        zombies = function() return { count = 0, radius = 40 } end,
        camp = function() return { configured = false } end })
    check(has(reply, "Set up a camp and mark your storage."), "without a camp, set one up")

    local base = { people = 3, foodDays = 5, power = "grid", hurt = 0, bleeding = 0, zombies = 0, camp = true }
    local healthy = Brain.survivalPercent(base)
    base.hurt, base.bleeding = 2, 1
    local wounded = Brain.survivalPercent(base)
    check(healthy > wounded and healthy <= 89 and wounded >= 3, "wounds lower the survival estimate")
    check(Brain.survivalPercent({ hurt = 9, bleeding = 9, zombies = 99 }) == 3
        and Brain.survivalPercent({ people = 99, foodDays = 99, power = "grid", camp = true }) == 89,
        "the estimate is clamped")
    reply = Brain.respond(session(), "will we survive", fixtureWorld())
    check(string.find(joined(reply), "^Survival estimate for this camp: %d+ percent%.") ~= nil, "odds answer")

    local outside = fixtureWorld({ camp = function() return { configured = true, inside = false } end })
    for _, input in ipairs({ "how many nails", "jobs", "any problems", "how much food" }) do
        reply = Brain.respond(session(), input, outside)
        check(has(reply, "outside") or has(reply, "Carry me inside"), "'" .. input .. "' needs the camp network")
    end
    reply = Brain.respond(session(), "who is here", outside)
    check(has(reply, "4 survivors on file:"), "people answers work from any computer")
    local nomad = fixtureWorld({ camp = function() return { configured = false } end })
    reply = Brain.respond(session(), "how many nails", nomad)
    check(has(reply, "camp"), "no camp is explained")
    reply = Brain.respond(session(), "status", nomad)
    check(has(reply, "Camp report") and not has(reply, "Work ......"), "status skips camp facts without a camp")
end

-- ---------------------------------------------------------------------------
-- Conversation: suggestions, yes/no, repeats, insults, shouting, picks
-- ---------------------------------------------------------------------------
do
    local world = fixtureWorld()
    local s = session()
    local reply = Brain.respond(s, "day", world)
    check(reply.intent == "did_you_mean" and has(reply, "Did you mean \"time\"?"), "a weak match asks")
    reply = Brain.respond(s, "yes", world)
    check(reply.intent == "time" and has(reply, "2:05 PM"), "yes runs the suggestion")
    reply = Brain.respond(s, "yes", world)
    check(reply.intent == "yes", "a suggestion is answered once")
    Brain.respond(s, "dead", world)
    reply = Brain.respond(s, "no", world)
    check(reply.intent == "did_you_mean_no", "no declines the suggestion")
    Brain.respond(s, "outside", world)
    reply = Brain.respond(s, "ok", world)
    check(reply.intent == "weather" or reply.intent == "zombies", "ok also accepts a suggestion")

    reply = Brain.respond(s, "how many nails", world)
    local before = joined(reply)
    reply = Brain.respond(s, "what?", world)
    check(joined(reply) == before, "'what?' repeats the last answer")
    reply = Brain.respond(session(), "say that again", world)
    check(#reply.lines == 1 and reply.intent == "repeat", "nothing to repeat is said kindly")

    local rude = session()
    Brain.respond(rude, "you are stupid", world)
    Brain.respond(rude, "idiot", world)
    reply = Brain.respond(rude, "useless", world)
    local again = false
    for _, line in ipairs(Lines.POOLS.insult_again) do
        if string.find(joined(reply), string.gsub(line, "{name}", "Thor"), 1, true) then again = true end
    end
    check(again, "the third insult is taken statistically")

    reply = Brain.respond(session(), "HOW MANY NAILS DO WE HAVE", world)
    local shout = false
    for _, line in ipairs(Lines.POOLS.shout) do if reply.lines[1] == line then shout = true end end
    check(shout and has(reply, "216 nails"), "shouting gets a remark and still an answer")

    local cycle = { 1, 1, 1, 1 }
    local position = 0
    local picker = session({ random = function() position = position + 1 return cycle[position] or 1 end })
    local first = Brain.pick(picker, "joke")
    local second = Brain.pick(picker, "joke")
    local third = Brain.pick(picker, "joke")
    check(first ~= second and second ~= third and first ~= third, "picks avoid recent repeats")

    reply = Brain.respond(session(), "exit", world)
    check(reply.command == "close" and #reply.lines == 1, "exit says goodbye and closes")
    reply = Brain.respond(session(), "cls", world)
    check(reply.command == "clear" and reply.thinkMs == 0, "clear is instant")
    reply = Brain.respond(session(), "tell me a joke", world)
    check(reply.category == "chat" and reply.thinkMs >= 250 and reply.thinkMs < 1000 and #reply.think == 1,
        "small talk thinks briefly")
end

-- ---------------------------------------------------------------------------
-- Memory: notes, names, greetings and normalization
-- ---------------------------------------------------------------------------
do
    local world = fixtureWorld()
    local s = session()
    local reply = Brain.respond(s, "remember the red key is in the van", world)
    check(reply.memoryChanged == true and has(reply, "\"the red key is in the van\""), "a note is stored")
    Brain.respond(s, "remember " .. string.rep("x", 200), world)
    check(#s.notes[2] == Brain.NOTE_LENGTH, "long notes are cut to size")
    for index = 1, 10 do Brain.respond(s, "remember note " .. index, world) end
    check(#s.notes == Brain.MAX_NOTES and s.notes[Brain.MAX_NOTES] == "note 10", "the oldest notes drop")
    reply = Brain.respond(s, "what did i tell you", world)
    check(has(reply, "1. note 3") and has(reply, "8. note 10"), "notes are read back in order")
    reply = Brain.respond(s, "remember", world)
    check(reply.memoryChanged ~= true, "an empty note is refused")
    local marked = session()
    reply = Brain.respond(marked, "remember {name} is {away}", world)
    check(marked.notes[1] == "name is away" and not has(reply, "{"),
        "a note cannot smuggle a template field into EMMA's lines")
    reply = Brain.respond(s, "call me Ragnar the Bold", world)
    check(s.operator == "Ragnar the Bold" and has(reply, "Ragnar the Bold"), "a new name is used")
    local memory = Brain.exportMemory(s, 120)
    check(memory.operator == "Ragnar the Bold" and #memory.notes == 8 and memory.lastSeen == 120,
        "memory exports the name, notes and last visit")
    reply = Brain.respond(s, "forget everything", world)
    check(#s.notes == 0 and reply.memoryChanged == true, "notes can be erased")
    check(Brain.exportMemory(session(), 5).operator == nil, "a default name is not saved as chosen")

    local normalized = Brain.normalizeMemory({ operator = "A\200nn" .. string.rep("n", 60),
        notes = { "ok", 7, { "bad" }, "caf\233", string.rep("y", 300), "", "a", "b", "c", "d", "e" },
        lastSeen = 0 / 0, visits = -4 })
    check(normalized.operator == string.sub("Ann" .. string.rep("n", 60), 1, Brain.NAME_LENGTH),
        "a stored name is cleaned and bounded")
    check(#normalized.notes <= Brain.MAX_NOTES and normalized.notes[1] == "ok" and normalized.notes[2] == "7"
        and normalized.notes[3] == "caf" and #normalized.notes[4] == Brain.NOTE_LENGTH,
        "stored notes are cleaned, bounded and stripped of non-text: " .. table.concat(normalized.notes, "|"))
    check(normalized.lastSeen == nil and normalized.visits == 0, "bad numbers are dropped or clamped")
    check(#Brain.normalizeMemory("junk").notes == 0 and Brain.normalizeMemory(nil).visits == 0,
        "missing memory is empty")

    local fresh = session({ memory = { visits = 0 } })
    reply = Brain.boot(fresh, world)
    check(has(reply, "EMMA 0.9.3 BETA") and has(reply, "5 of 3,685,296 records responding")
        and has(reply, "generator, fuel 62%"), "boot screen counts the living: " .. joined(reply))
    local greeted = false
    for _, line in ipairs(Lines.GREET_FIRST) do
        if has(reply, (string.gsub(line, "{name}", "Thor"))) then greeted = true end
    end
    check(greeted and fresh.visits == 1 and fresh.lastSeen == 77, "a first visit gets a first greeting")
    local back = session({ memory = { visits = 3, lastSeen = 74, operator = "Ragnar" } })
    reply = Brain.boot(back, world)
    check(has(reply, "3 hours") or not has(reply, "{away}"), "a return greeting says how long")
    check(back.operator == "Ragnar" and back.namedOperator == true, "a remembered name returns")
    local long = session({ memory = { visits = 3, lastSeen = 1 } })
    reply = Brain.boot(long, world)
    local longGreeting = false
    for _, line in ipairs(Lines.GREET_LONG) do
        if has(reply, (string.gsub(string.gsub(line, "{name}", "Thor"), "{away}", "3 days"))) then
            longGreeting = true
        end
    end
    check(longGreeting, "a long absence gets its own greeting: " .. joined(reply))
end

-- ---------------------------------------------------------------------------
-- Robustness: broken facts, missing worlds, and noise
-- ---------------------------------------------------------------------------
do
    local broken = {}
    for _, name in ipairs({ "camp", "clock", "weather", "power", "people", "jobs", "storage", "zombies",
        "expedition" }) do
        broken[name] = function() error("injected " .. name .. " failure") end
    end
    for _, input in ipairs({ "status", "how many nails", "who is hurt", "power", "time", "weather",
        "any zombies", "expedition", "advice", "will we survive", "jobs", "any problems", "food",
        "kate", "hello" }) do
        local reply = Brain.respond(session(), input, broken)
        check(#reply.lines >= 1 and not has(reply, "{"), "'" .. input .. "' survives failing facts")
        reply = Brain.respond(session(), input, nil)
        check(#reply.lines >= 1, "'" .. input .. "' survives a missing world")
    end
    local poisoned = fixtureWorld({ people = function()
        return { { id = "x", name = "Kate", health = 50, doing = { "not text" }, where = "here" } }
    end })
    local reply = Brain.respond(session(), "how is kate", poisoned)
    check(reply.error ~= nil and #reply.lines == 1, "a handler error becomes a line, not a crash")

    local words = { "how", "many", "nails", "kate", "is", "the", "power", "zombies", "what", "and", "?",
        "HELLO", "remember", "2", "+", "x", "/", "(", ")", "food", "bob", "generator", "asdf", "zzz",
        "yes", "no", "help", "call", "me", "they", "them", "it", "where", "who", "hurt", "status",
        "\"", "'", ";", "%", "{name}", "\t", "dofile", "Ragnar", "fuel", "weather", "blocked" }
    local seed = 12345
    local function nextRandom(count)
        seed = (seed * 1103515245 + 12345) % 2147483648
        return seed % count + 1
    end
    local fuzz = session({ random = nextRandom })
    local world = fixtureWorld()
    for _ = 1, 400 do
        local parts = {}
        for _ = 1, nextRandom(7) do parts[#parts + 1] = words[nextRandom(#words)] end
        local input = table.concat(parts, " ")
        local result = Brain.respond(fuzz, input, world)
        check(result.command == "clear" or #result.lines >= 1, "fuzz '" .. input .. "' answers")
        for _, line in ipairs(result.lines) do
            check(not string.find(line, "{[%w_]+}"), "fuzz '" .. input .. "' fills every field: " .. line)
        end
        check((result.thinkMs or 0) >= 0 and (result.thinkMs or 0) <= 3000, "fuzz thinking is bounded")
    end
    local long = string.rep("supercalifragilistic ", 40)
    reply = Brain.respond(session(), long, world)
    check(#reply.lines >= 1, "overlong input is cut, not choked on")
end

-- ---------------------------------------------------------------------------
-- The live world adapter against fake game objects
-- ---------------------------------------------------------------------------
do
    local function square(x, y, z, extra)
        local value = extra or {}
        value.x, value.y, value.z = x, y, z or 0
        function value:getX() return self.x end
        function value:getY() return self.y end
        function value:getZ() return self.z end
        function value:haveElectricity() return self.generatorPower == true end
        function value:hasGridPower() return self.gridPower == true end
        function value:getRoom() return self.room end
        function value:getGenerator() return self.generator end
        return value
    end
    local squares = {}
    local function at(x, y, z) return squares[x .. "," .. y .. "," .. (z or 0)] end
    local function place(value) squares[value.x .. "," .. value.y .. "," .. value.z] = value return value end
    local function list(values)
        return { values = values, size = function(self) return #self.values end,
            get = function(self, index) return self.values[index + 1] end }
    end
    local function item(name, fullType, category, food, calories)
        return { getDisplayName = function() return name end, fullType = fullType,
            getDisplayCategory = function() return category end,
            IsFood = function() return food == true end,
            getCalories = function() return calories end }
    end
    local function actor(id, x, y, z, bleeding)
        return { id = id, x = x, y = y, z = z or 0,
            getBodyDamage = function()
                return { getNumPartsBleeding = function() return bleeding and 1 or 0 end }
            end }
    end

    local saved = { U = SC.GameplayUtil, life = SC.BaseLife, registry = SC.Registry, ui = SC.UI,
        expedition = SC.ExpeditionPrototype, taxi = SC.TaxiService }
    SC.GameplayUtil = {
        call = function(object, method, ...)
            if object == nil then return nil, false end
            local member = object[method]
            if type(member) ~= "function" then return nil, false end
            local ok, value = pcall(member, object, ...)
            return value, ok
        end,
        gridSquare = function(x, y, z) return at(x, y, z) end,
        position = function(value)
            if type(value) ~= "table" then return nil end
            return value.x, value.y, value.z
        end,
        itemType = function(value) return value.fullType end,
        inventoryItems = function(container, limit)
            local result = {}
            for index = 1, math.min(#container.items, limit or 80) do result[index] = container.items[index] end
            return result
        end,
        isZombie = function(value) return value.zombie == true end,
        isGoneTarget = function(value) return value.gone == true end,
        nameOf = function(value) return value.name or value.id end,
    }
    local generator = { getFuel = function() return 4.5 end, getMaxFuel = function() return 10 end,
        getCondition = function() return 73 end, isActivated = function() return true end }
    local desk = place(square(100, 100, 0, { generatorPower = true }))
    place(square(103, 97, 0, { generator = generator }))
    local computer = { getSquare = function() return desk end }

    local crate = { getType = function() return "crate" end, items = {
        item("Nails", "Base.Nails", "Material"), item("Nails", "Base.Nails", "Material"),
        item("Canned Beans", "Base.TinnedBeans", "Food", true, 300),
        item("Canned Beans", "Base.TinnedBeans", "Food", true, 300),
    } }
    local shelves = { getType = function() return "shelves" end, items = {
        item("Nails", "Base.Nails", "Material"), item("Hammer", "Base.Hammer", "Tool") } }
    local storages = { { id = "s1", category = "tools", container = crate },
        { id = "s2", category = "materials", container = shelves },
        { id = "s3", category = "food", container = nil } }
    local insideCamp = true
    SC.BaseLife = {
        active = function() return { name = "Rising" } end,
        isInside = function(value) return insideCamp and value ~= nil and (value.x or 0) >= 90 end,
        storageRows = function() return storages end,
        resolveContainer = function(storage) return storage.container end,
        summary = function()
            return { jobs = { active = 1, pending = 0, blocked = 1 }, rows = {
                { type = "chop_wood", state = "active", reservedBy = "sc-1" },
                { type = "build", kind = "wall_frame", state = "blocked", blocker = "missing_planks" },
            } }
        end,
    }
    SC.UI = {
        humanize = function(value)
            local text = string.gsub(tostring(value), "_", " ")
            return string.upper(string.sub(text, 1, 1)) .. string.sub(text, 2)
        end,
        stateText = function(value) return "State " .. tostring(value) end,
        baseFailureReason = function(reason) return "Reason " .. tostring(reason) end,
        displayName = function(entry, fallback)
            if entry.id == "sc-1" then return "Kate Miller" end
            if entry.id == "sc-9" then return "Doc Holm" end
            return fallback
        end,
        describeEntry = function(value)
            if value.id == "sc-1" then
                return { id = "sc-1", name = "Kate Miller", health = 41, morale = 30, stress = 65,
                    actionSummary = { active = true, action = "chop" } }
            end
            return { id = value.id, name = "Bob Fisher", health = 90, activity = "idle" }
        end,
    }
    local kate, bob, driver, stranger = actor("sc-1", 103, 97, 0, true), actor("sc-2", 100, 101, 1),
        actor("sc-7", 110, 110), actor("sc-8", 120, 120)
    local records = { ["sc-1"] = { recruited = true }, ["sc-2"] = { recruited = true },
        ["sc-7"] = { recruited = true }, ["sc-8"] = { recruited = false } }
    SC.Registry = {
        living = function() return { kate, bob, driver, stranger } end,
        idOf = function(value) return value.id end,
        byId = function(id) return records[id] end,
    }
    SC.TaxiService = { isDriver = function(value) return value == driver end }
    SC.ExpeditionPrototype = { describeForPlayer = function()
        return { leaderName = "Doc Holm", kind = "search", members = { { id = "sc-9", name = "Doc" } },
            supplyProgress = { collected = 5, requested = 20 } }
    end }
    local zombies = list({
        { zombie = true, x = 110, y = 100, z = 0 },
        { zombie = true, x = 100, y = 80, z = 0 },
        { zombie = true, x = 100, y = 99, z = 3 },
        { zombie = true, gone = true, x = 101, y = 101, z = 0 },
        { zombie = false, x = 101, y = 100, z = 0 },
        { zombie = true, x = 200, y = 200, z = 0 },
    })
    getCell = function() return { getZombieList = function() return zombies end } end
    getGameTime = function()
        return { getWorldAgeHours = function() return 50 end, getHour = function() return 9 end,
            getMinutes = function() return 30 end, getDay = function() return 10 end,
            getMonth = function() return 6 end, getYear = function() return 1993 end }
    end
    getClimateManager = function()
        return { getTemperature = function() return 21.5 end,
            getPrecipitationIntensity = function() return 0 end, isSnowing = function() return false end,
            getFogIntensity = function() return 0.6 end, getWindIntensity = function() return 0.2 end }
    end

    check(World.direction(0, -5) == "north" and World.direction(5, 0) == "east"
        and World.direction(-4, 4) == "south-west" and World.direction(3, -3) == "north-east"
        and World.direction(0.1, 0.2) == "here", "compass words follow map axes")
    check(World.whereText({ x = 0, y = 0, z = 0 }, 3, -4, 1) == "5 meters north-east upstairs"
        and World.whereText({ x = 0, y = 0, z = 0 }, 1, 0, 0) == "right here", "where text")

    local world = World.new({ id = "player" }, computer)
    local power = world.power()
    check(power.source == "generator" and power.fuel == 45 and power.condition == 73,
        "the nearest running generator reports fuel as a percentage")
    desk.gridPower, desk.room = true, {}
    check(world.power().source == "grid", "grid power inside a building wins")
    desk.gridPower, desk.room, desk.generatorPower = false, nil, false
    check(world.power().source == "none" and not World.powered(desk), "no power is no power")
    desk.gridPower = true
    check(not World.powered(desk), "grid power needs a room, as vanilla appliances do")
    desk.generatorPower, desk.gridPower = true, false

    local index = world.storage()
    check(index.containers == 2 and index.items == 6 and index.truncated == true,
        "an unloaded container marks the count partial")
    local byName = {}
    for _, group in ipairs(index.groups) do byName[group.name] = group end
    check(byName.Nails.count == 3 and byName.Nails.where[1] == "crate (tools)"
        and byName.Nails.where[2] == "shelves (materials)" and byName.Nails.places == nil,
        "items group by type with every place they sit")
    check(byName["Canned Beans"].food == true and byName["Canned Beans"].kcal == 600
        and byName.Hammer.category == "Tool", "food carries calories and items keep categories")
    local limit = World.ITEMS_PER_CONTAINER
    World.ITEMS_PER_CONTAINER = 1
    index = world.storage()
    check(index.items == 2 and index.truncated == true, "per-container scans are capped")
    World.ITEMS_PER_CONTAINER = limit
    local total = World.ITEMS_TOTAL
    World.ITEMS_TOTAL = 3
    storages[3] = nil
    index = world.storage()
    check(index.items == 3 and index.truncated == true, "the whole scan is capped")
    World.ITEMS_TOTAL = total

    local people = world.people()
    check(#people == 3, "recruited people and away members, without the cab driver or strangers")
    local byId = {}
    for _, person in ipairs(people) do byId[person.id] = person end
    check(byId["sc-1"].name == "Kate Miller" and byId["sc-1"].bleeding == true
        and byId["sc-1"].health == 41 and byId["sc-1"].doing == "State chop"
        and byId["sc-1"].where == "at camp, 4 meters north-east", "Kate's live state: "
        .. tostring(byId["sc-1"].where))
    check(byId["sc-2"].where == "at camp, right here upstairs" and byId["sc-2"].bleeding == false
        and byId["sc-2"].doing == "State idle", "Bob upstairs")
    check(byId["sc-9"].away == true and byId["sc-9"].name == "Doc Holm", "away members are listed by name")

    local jobs = world.jobs()
    check(jobs.active == 1 and jobs.blocked == 1 and jobs.rows[1].who == "Kate Miller"
        and jobs.rows[1].job == "Chop wood" and jobs.rows[2].job == "Wall frame"
        and jobs.rows[2].reason == "Reason missing_planks", "jobs carry names and blocker reasons")

    local seen = world.zombies()
    check(seen.count == 2 and math.floor(seen.nearest + 0.5) == 10 and seen.dir == "east",
        "only real, present zombies within reach and a floor count")
    local scanLimit = World.ZOMBIE_SCAN_LIMIT
    World.ZOMBIE_SCAN_LIMIT = 1
    check(world.zombies().count == 1, "the zombie scan is capped")
    World.ZOMBIE_SCAN_LIMIT = scanLimit

    local clock = world.clock()
    check(clock.day == 11 and clock.month == 6 and clock.hour == 9 and clock.days == 2,
        "the game clock's zero-based day becomes a calendar day")
    local weather = world.weather()
    check(weather.temperature == 21.5 and weather.fog == 0.6, "weather reads the climate")
    local expedition = world.expedition()
    check(expedition.active and expedition.leader == "Doc Holm" and expedition.kind == "search"
        and expedition.members[1] == "Doc Holm" and expedition.collected == 5, "expedition summary")
    check(world.camp().inside == true, "the desk is inside camp")
    insideCamp = false
    check(world.camp().inside == false and world.camp().configured == true, "outside camp is told apart")

    insideCamp = true
    local reply = Brain.respond(session(), "how many nails", world)
    check(has(reply, "3 nails in camp storage."),
        "the brain answers from the live adapter: " .. joined(reply))
    reply = Brain.respond(session(), "how is kate", world)
    check(has(reply, "Kate Miller: health 41 percent, bleeding, stressed"), "a live person report")

    SC.GameplayUtil, SC.BaseLife, SC.Registry, SC.UI = saved.U, saved.life, saved.registry, saved.ui
    SC.ExpeditionPrototype, SC.TaxiService = saved.expedition, saved.taxi
    getCell, getGameTime, getClimateManager = nil, nil, nil
end

print("TERMINAL_KAHLUA_PASS checks=" .. checks)
SC_TEST_REPORT = "Camp computer brain and world: " .. checks .. " checks passed"
