-- SPDX-License-Identifier: MIT

-- EMMA's brain. Turns one line of operator text into one reply. There is no
-- network and no model here: a normalizer, a small typo-tolerant intent
-- scorer, a little short-term context ("and screws?", "how is she?", "yes")
-- and handlers that read live camp facts through a world provider.
--
-- The brain never touches game objects. Everything it knows arrives through
-- the world table (see SCTerminalWorld), whose functions return plain Lua
-- values; each call is protected, and a failed or missing fact becomes a
-- line in EMMA's voice instead of an error. That keeps every answer
-- deterministic and testable with fixtures.

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion

SC.TerminalBrain = SC.TerminalBrain or {}
local Brain = SC.TerminalBrain
if not SC.TerminalKnowledge and type(require)=="function" then pcall(require,"SCTerminalKnowledge") end
if not SC.TerminalConversation and type(require)=="function" then pcall(require,"SCTerminalConversation") end
local Conversation = SC.TerminalConversation

Brain.MAX_INPUT = 160
Brain.MAX_NOTES = 8
Brain.NOTE_LENGTH = 80
Brain.NAME_LENGTH = 24
Brain.THRESHOLD = 3
Brain.KCAL_PER_DAY = 2000

local function L() return SC.TerminalLines end

-- ---------------------------------------------------------------------------
-- Text helpers
-- ---------------------------------------------------------------------------

local function trim(value)
    return (string.gsub(tostring(value or ""), "^%s*(.-)%s*$", "%1"))
end

-- Keep printable ASCII only. The terminal font has nothing else.
local function printable(value, limit)
    local text = string.gsub(tostring(value or ""), "[^ -~]", "")
    text = trim(string.gsub(text, "%s+", " "))
    if limit and #text > limit then text = trim(string.sub(text, 1, limit)) end
    return text
end

local function commas(value)
    local number = math.floor((tonumber(value) or 0) + 0.5)
    local text = tostring(math.abs(number))
    local result = ""
    while #text > 3 do
        result = "," .. string.sub(text, -3) .. result
        text = string.sub(text, 1, -4)
    end
    return (number < 0 and "-" or "") .. text .. result
end

local function capitalize(value)
    local text = tostring(value or "")
    return string.upper(string.sub(text, 1, 1)) .. string.sub(text, 2)
end

local function listText(items)
    local count = #items
    if count == 0 then return "" end
    if count == 1 then return items[1] end
    return table.concat(items, ", ", 1, count - 1) .. " and " .. items[count]
end

local function plural(count, one, many)
    return count == 1 and one or many
end

function Brain.duration(hours)
    local value = math.max(0, tonumber(hours) or 0)
    if value < 1 then
        local minutes = math.max(1, math.floor(value * 60 + 0.5))
        return minutes .. plural(minutes, " minute", " minutes")
    end
    if value < 48 then
        local whole = math.floor(value + 0.5)
        return whole .. plural(whole, " hour", " hours")
    end
    local days = math.floor(value / 24 + 0.5)
    return days .. " days"
end

-- Fill {field} markers. Unknown fields stay visible so tests catch them.
function Brain.fill(template, fields)
    fields = fields or {}
    return (string.gsub(tostring(template or ""), "{([%w_]+)}", function(key)
        local value = fields[key]
        if value == nil then return "{" .. key .. "}" end
        return tostring(value)
    end))
end

function Brain.numberText(value)
    local number = tonumber(value) or 0
    if number == math.floor(number) and math.abs(number) < 1e15 then return commas(number) end
    local text = string.format("%.4f", number)
    text = string.gsub(text, "0+$", "")
    return (string.gsub(text, "%.$", ""))
end

-- ---------------------------------------------------------------------------
-- Arithmetic. Operators + - * / x and parentheses, parsed by hand: input is
-- never compiled or run. Returns the cleaned expression and its value, the
-- expression and nil when there is no finite answer, or nil when it is not
-- maths.
-- ---------------------------------------------------------------------------

local MATH_LEADS = { "^what is%s+", "^whats%s+", "^what's%s+", "^calculate%s+", "^compute%s+",
    "^solve%s+", "^how much is%s+", "^eval%s+" }

function Brain.arithmetic(raw)
    local text = string.lower(trim(raw))
    for _, lead in ipairs(MATH_LEADS) do text = string.gsub(text, lead, "") end
    text = string.gsub(text, "[%s=%?]+$", "")
    if #text == 0 or #text > 40 or not string.find(text, "%d")
        or not string.find(text, "^[%d%.%s%+%-%*/%(%)x]+$")
        or not string.find(text, "%d%s*[%+%-%*/x]%s*[%d%(%-]") then
        return nil
    end
    local source = string.gsub(string.gsub(text, "%s+", ""), "x", "*")
    local position, depth, failed = 1, 0, false
    local expression
    local function peek() return string.sub(source, position, position) end
    local function factor()
        local character = peek()
        if character == "-" then
            position = position + 1
            return -factor()
        end
        if character == "(" then
            depth = depth + 1
            if depth > 8 then failed = true return 0 end
            position = position + 1
            local value = expression()
            if peek() ~= ")" then failed = true return 0 end
            position = position + 1
            depth = depth - 1
            return value
        end
        local digits = string.match(string.sub(source, position), "^%d+%.?%d*")
        if not digits then failed = true return 0 end
        position = position + #digits
        return tonumber(digits) or 0
    end
    local function term()
        local value = factor()
        while not failed do
            local character = peek()
            if character ~= "*" and character ~= "/" then break end
            position = position + 1
            local right = factor()
            if character == "*" then value = value * right else value = value / right end
        end
        return value
    end
    expression = function()
        local value = term()
        while not failed do
            local character = peek()
            if character ~= "+" and character ~= "-" then break end
            position = position + 1
            local right = term()
            value = character == "+" and value + right or value - right
        end
        return value
    end
    local value = expression()
    if failed or position <= #source then return nil end
    local shown = trim(string.gsub(text, "%s+", " "))
    -- Dividing by zero gives an infinity or NaN, never a number to print.
    if value ~= value or value == math.huge or value == -math.huge then return shown, nil end
    return shown, value
end

-- ---------------------------------------------------------------------------
-- Normalizing and typo tolerance
-- ---------------------------------------------------------------------------

local CONTRACTIONS = {
    whats = "what is", wheres = "where is", whos = "who is", hows = "how is",
    thats = "that is", theres = "there is", heres = "here is", its = "it is",
    im = "i am", ive = "i have", youre = "you are", youve = "you have",
    theyre = "they are", dont = "do not", doesnt = "does not", didnt = "did not",
    cant = "can not", cannot = "can not", wont = "will not", isnt = "is not",
    arent = "are not", wasnt = "was not", hes = "he is", shes = "she is",
    lets = "let us", u = "you", ur = "your", r = "are", ya = "you", yall = "you all",
    pls = "please", plz = "please", thx = "thanks", ty = "thanks", thanx = "thanks",
    thnx = "thanks", tnx = "thanks", wanna = "want to", gonna = "going to",
    gotta = "got to", gimme = "give me", genny = "generator", hp = "health",
    meds = "medicine", hi = "hello", hey = "hello", howdy = "hello", yo = "hello",
    hiya = "hello", greetings = "hello", yeah = "yes", yep = "yes", yup = "yes",
    nope = "no", nah = "no", okay = "ok", k = "ok", zeds = "zombies", zed = "zombie",
    whoami = "whoami", goodnight = "goodnight", nite = "night",
}

-- Words that never carry an intent or an item on their own.
local STOP = {}
for word in string.gmatch("a an the of to in on at for is are was were be been do does did "
    .. "we us our ours i me my mine you your it its they them their there here this that these "
    .. "those any some have has had got get please can could would will should shall emma ok so "
    .. "just still left now right all much many how what where which who whom tell show give "
    .. "check about and or with lot lots from by up out into than then too very really also "
    .. "am not no yes hello hey well um uh oh hmm let know", "%S+") do
    STOP[word] = true
end

-- Optimal string alignment distance: insertions, deletions, substitutions
-- and swapped neighbours each cost one. Stops early past the limit.
function Brain.distance(a, b, limit)
    limit = limit or 2
    local la, lb = #a, #b
    if math.abs(la - lb) > limit then return limit + 1 end
    local before, previous = nil, {}
    for j = 0, lb do previous[j] = j end
    for i = 1, la do
        local current = { [0] = i }
        local rowMinimum = i
        local ai = string.byte(a, i)
        for j = 1, lb do
            local bj = string.byte(b, j)
            local cost = ai == bj and 0 or 1
            local value = math.min(previous[j] + 1, math.min(current[j - 1] + 1, previous[j - 1] + cost))
            if before and i > 1 and j > 1 and ai == string.byte(b, j - 1)
                and string.byte(a, i - 1) == bj then
                value = math.min(value, before[j - 2] + 1)
            end
            current[j] = value
            if value < rowMinimum then rowMinimum = value end
        end
        if rowMinimum > limit then return limit + 1 end
        before, previous = previous, current
    end
    return previous[lb]
end

local function allowedDistance(word)
    if #word >= 8 then return 2 end
    if #word >= 4 then return 1 end
    return 0
end

function Brain.singular(word)
    local value = tostring(word or "")
    if #value > 4 and string.sub(value, -3) == "ies" then return string.sub(value, 1, -4) .. "y" end
    if #value > 4 and (string.sub(value, -4) == "ches" or string.sub(value, -4) == "shes"
        or string.sub(value, -3) == "xes" or string.sub(value, -4) == "sses") then
        return string.sub(value, 1, -3)
    end
    if #value > 3 and string.sub(value, -1) == "s" and string.sub(value, -2) ~= "ss" then
        return string.sub(value, 1, -2)
    end
    return value
end

function Brain.tokens(text)
    local lower = string.lower(printable(text, Brain.MAX_INPUT))
    lower = string.gsub(lower, "'", "")
    lower = string.gsub(lower, "[^%w%s]", " ")
    local result = {}
    for word in string.gmatch(lower, "%S+") do
        local expanded = CONTRACTIONS[word]
        if expanded then
            for part in string.gmatch(expanded, "%S+") do result[#result + 1] = part end
        else
            result[#result + 1] = word
        end
    end
    return result
end

-- ---------------------------------------------------------------------------
-- Intents. Words score once each; phrases match on word boundaries. Order
-- breaks ties, so the more specific intents sit earlier.
-- ---------------------------------------------------------------------------

Brain.INTENTS = {
    { id = "help", label = "help",
        words = { help = 4, commands = 4, command = 3, manual = 3, menu = 3, options = 2,
            instructions = 3, guide = 2 },
        phrases = { ["what can you do"] = 5, ["how does this work"] = 4, ["how do i use"] = 4,
            ["what do you do"] = 3 } },
    { id = "skills", label = "skills", exact = { "skills", "who has the best skills" },
        words = { skills = 6, skill = 5 }, phrases = { ["best at"] = 6 } },
    { id = "shortages", label = "shortages", exact = { "shortages", "what are we short of", "stock targets" },
        words = { shortages = 6, shortage = 6 }, phrases = { ["short of"] = 6, ["running out of"] = 5 } },
    { id = "alarms", label = "camp alarms", exact = { "alarms", "alarm history", "camp alarm" },
        words = { alarm = 5, alarms = 5 }, phrases = { ["who raised the alarm"] = 7 } },
    { id = "deliveries", label = "pending deliveries", exact = { "deliveries", "pending deliveries", "cargo pending" },
        words = { deliveries = 6, delivery = 5 }, phrases = { ["cargo pending"] = 6 } },
    { id = "clear", exact = { "clear", "cls", "clear screen" } },
    { id = "exit",
        exact = { "exit", "quit", "logout", "log out", "logoff", "log off", "bye", "goodbye",
            "bye bye", "close", "q", "see you", "later", "cya", "see ya" },
        words = { bye = 4, goodbye = 4, logout = 4, quit = 4, exit = 4 },
        phrases = { ["see you"] = 4, ["log off"] = 4, ["log out"] = 4, ["got to go"] = 4,
            ["have to go"] = 4, ["need to go"] = 4 } },
    { id = "repeat", exact = { "again", "repeat", "what", "huh", "pardon", "come again",
        "say again", "say that again", "repeat that", "what did you say", "sorry what" } },
    { id = "dir", exact = { "ls", "dir", "ls la", "ls l", "ls al", "dir w", "list files", "files" } },
    { id = "whoami", label = "whoami", exact = { "whoami" },
        phrases = { ["who am i"] = 7, ["what is my name"] = 7, ["do you know me"] = 6,
            ["do you know who i am"] = 7, ["my file"] = 5, ["remember me"] = 7 } },
    { id = "recall", label = "notes",
        exact = { "notes", "memory", "recall", "my notes" },
        words = { notes = 5, memory = 3, memories = 3, recall = 5 },
        phrases = { ["what did i tell you"] = 7, ["what do you remember"] = 7,
            ["what did i say"] = 6, ["read notes"] = 6, ["show notes"] = 6 } },
    { id = "forget",
        phrases = { ["forget everything"] = 7, ["clear notes"] = 7, ["delete notes"] = 7,
            ["erase notes"] = 7, ["forget notes"] = 7, ["wipe notes"] = 7, ["forget all"] = 7 } },
    { id = "status", label = "status",
        words = { status = 4, report = 3, sitrep = 4, overview = 4, summary = 4, update = 2,
            situation = 3, news = 2 },
        phrases = { ["how are things"] = 4, ["how is the camp"] = 4, ["what is going on"] = 3,
            ["what is new"] = 3, ["what is happening"] = 3 } },
    { id = "odds", label = "will we survive",
        words = { survive = 5, survival = 5, odds = 5, chance = 4, chances = 4, die = 3,
            dying = 3 },
        phrases = { ["will we survive"] = 7, ["are we going to die"] = 7,
            ["am i going to die"] = 7, ["will we make it"] = 7, ["are we going to make it"] = 7,
            ["will i die"] = 6 } },
    { id = "advice", label = "advice",
        words = { advice = 6, advise = 5, tip = 5, tips = 5, suggest = 5, suggestion = 5,
            recommend = 5, recommendation = 5, priority = 4, priorities = 4, plan = 3,
            idea = 3, ideas = 3, should = 2 },
        phrases = { ["what should i do"] = 7, ["what should we do"] = 7, ["what now"] = 5,
            ["what next"] = 5, ["what do i do"] = 6, ["what do we do"] = 6 } },
    { id = "people_hurt", label = "who is hurt",
        words = { hurt = 5, injured = 5, injury = 4, injuries = 4, wounded = 5, wounds = 4,
            wound = 4, bleeding = 5, sick = 4, ill = 3, health = 4, medical = 3, medic = 3,
            doctor = 3 },
        phrases = { ["needs help"] = 4, ["need help"] = 3, ["anyone hurt"] = 6 } },
    { id = "people_mood", label = "morale",
        words = { morale = 5, mood = 5, happy = 3, sad = 3, stress = 4, stressed = 4,
            spirits = 4, depressed = 4, panic = 3, feeling = 3, feelings = 3 },
        phrases = { ["everyone feeling"] = 6, ["everybody feeling"] = 6, ["they feeling"] = 6 } },
    { id = "people_list", label = "who is here",
        words = { who = 2, survivors = 4, survivor = 3, people = 4, everyone = 3, everybody = 3,
            roster = 5, team = 2, group = 2, crew = 3, headcount = 5, companions = 4,
            companion = 3, followers = 4, residents = 4 },
        phrases = { ["who is here"] = 4, ["who is around"] = 4, ["how many people"] = 9,
            ["how many survivors"] = 9, ["who is alive"] = 5, ["where is everyone"] = 5,
            ["where is everybody"] = 5, ["how is everyone"] = 5, ["how is everybody"] = 5 } },
    { id = "blocked", label = "any problems",
        words = { blocked = 6, stuck = 6, problems = 5, problem = 5, issues = 5, issue = 4,
            wrong = 4, failing = 5, failed = 4, trouble = 4, errors = 4, error = 3 },
        phrases = { ["what is wrong"] = 6, ["anything wrong"] = 6, ["any problems"] = 6 } },
    { id = "jobs", label = "what is everyone doing",
        words = { jobs = 5, job = 4, work = 3, working = 4, tasks = 5, task = 4, doing = 3,
            busy = 3, orders = 3, chores = 4, progress = 2, assignments = 4, assigned = 3,
            workers = 3, duty = 3 },
        phrases = { ["what is everyone doing"] = 6, ["what are they doing"] = 6,
            ["work orders"] = 5, ["who is working"] = 6 } },
    { id = "food", label = "how much food",
        words = { food = 5, eat = 3, eating = 3, calories = 5, meals = 4, meal = 4,
            rations = 5, hungry = 3, starving = 3 },
        phrases = { ["how much food"] = 6 } },
    { id = "zombies", label = "any zombies",
        words = { zombies = 5, zombie = 5, undead = 5, walkers = 5, dead = 2, infected = 3,
            horde = 5, monsters = 4, threats = 3, threat = 3, danger = 3, dangerous = 3,
            safe = 3, movement = 3, enemies = 3, outside = 1 },
        phrases = { ["is it safe"] = 5, ["any zombies"] = 6, ["how many zombies"] = 7 } },
    { id = "expedition", label = "expedition",
        words = { expedition = 6, expeditions = 6, trip = 4, mission = 4, away = 3,
            scavengers = 4, scavenging = 3, radio = 3, raid = 3, convoy = 3, ["return"] = 2 },
        phrases = { ["away team"] = 5, ["when are they back"] = 6, ["when will they be back"] = 6 } },
    { id = "power", label = "power",
        words = { power = 4, electricity = 5, electric = 3, generator = 5, generators = 5,
            fuel = 3, gas = 2, gasoline = 2, grid = 3, lights = 2, battery = 2, voltage = 4,
            volts = 3, energy = 3 },
        phrases = { ["how much fuel"] = 6, ["fuel left"] = 4, ["generator fuel"] = 6 } },
    { id = "weather", label = "weather",
        words = { weather = 5, temperature = 4, rain = 4, raining = 4, cold = 3, hot = 3,
            warm = 3, forecast = 4, snow = 4, snowing = 4, fog = 4, foggy = 4, wind = 3,
            windy = 3, sunny = 3, storm = 3, degrees = 3, outside = 1 } },
    { id = "time", label = "time",
        words = { time = 4, date = 4, clock = 3, day = 2, days = 2, today = 2, hour = 3,
            calendar = 3, month = 3, year = 3, survived = 3 },
        phrases = { ["what day"] = 3, ["how long"] = 2, ["what time"] = 3, ["days survived"] = 4 } },
    { id = "storage", label = "how many <item>",
        words = { many = 2, much = 2, count = 4, stock = 4, inventory = 4, supplies = 3,
            storage = 4, stored = 3, store = 2, have = 1, got = 1, left = 1, find = 2,
            need = 1, enough = 2, stockpile = 4, quantity = 3 },
        phrases = { ["how many"] = 4, ["how much"] = 4, ["do we have"] = 4, ["have we got"] = 4,
            ["any left"] = 3, ["where is the"] = 3, ["where are the"] = 3 } },
    -- Conversation.
    { id = "identity", label = "who are you",
        words = { name = 2, emma = 2 },
        phrases = { ["who are you"] = 7, ["what are you"] = 7, ["your name"] = 6,
            ["what is your name"] = 7, ["introduce yourself"] = 7, ["tell me about yourself"] = 7,
            ["are you a computer"] = 6, ["are you a robot"] = 6, ["are you an ai"] = 6,
            ["are you a program"] = 6 } },
    { id = "alive",
        words = { alive = 5, sentient = 6, conscious = 6, soul = 5, dream = 4, dreams = 4 },
        phrases = { ["are you alive"] = 7, ["are you real"] = 7, ["are you human"] = 7,
            ["can you think"] = 6, ["do you dream"] = 7, ["are you a person"] = 7 } },
    { id = "feelings",
        words = { lonely = 4 },
        phrases = { ["how are you"] = 7, ["how do you feel"] = 7, ["are you ok"] = 7,
            ["you ok"] = 6, ["how is it going"] = 5, ["how are you doing"] = 7,
            ["are you happy"] = 6, ["are you lonely"] = 7, ["are you sad"] = 6 } },
    { id = "joke",
        words = { joke = 6, jokes = 6, funny = 4, laugh = 4, humor = 4, humour = 4, pun = 4 },
        phrases = { ["make me laugh"] = 7, ["something funny"] = 7, ["cheer me up"] = 6 } },
    { id = "poem", words = { poem = 6, poetry = 6, haiku = 6, verse = 4, rhyme = 4, limerick = 6 } },
    { id = "story", words = { story = 6, stories = 6, tale = 5, bedtime = 4 },
        phrases = { ["once upon"] = 6 } },
    { id = "sing", words = { sing = 6, song = 6, music = 5, songs = 5 } },
    { id = "thanks",
        words = { thanks = 6, thank = 5, appreciate = 5, grateful = 5, cheers = 4 },
        phrases = { ["thank you"] = 7 } },
    { id = "sorry",
        words = { sorry = 6, apologize = 6, apologies = 6, apology = 6, oops = 4 },
        phrases = { ["my bad"] = 6 } },
    { id = "insult",
        words = { stupid = 6, dumb = 6, idiot = 6, useless = 6, hate = 5, moron = 6,
            annoying = 5, suck = 5, sucks = 5, worthless = 6, trash = 5, garbage = 5, liar = 5 },
        phrases = { ["shut up"] = 7, ["i hate you"] = 8, ["you suck"] = 8, ["go away"] = 5 } },
    { id = "love",
        words = { love = 6, marry = 6, kiss = 6, girlfriend = 6, crush = 5, adore = 6 },
        phrases = { ["i like you"] = 7, ["go out with me"] = 7 } },
    { id = "compliment",
        words = { smart = 5, clever = 5, genius = 5, brilliant = 5, amazing = 4, awesome = 4,
            great = 3, nice = 3, cool = 3, helpful = 5, best = 3, good = 2, wonderful = 4,
            impressive = 4 },
        phrases = { ["good job"] = 7, ["well done"] = 7, ["nice work"] = 7, ["you are the best"] = 7 } },
    { id = "meaning",
        words = { meaning = 4, purpose = 4 },
        phrases = { ["meaning of life"] = 8, ["what is the point"] = 7, ["why are we here"] = 7,
            ["purpose of life"] = 8 } },
    { id = "rescue",
        words = { rescue = 7, rescued = 7, evacuation = 6, evacuate = 6, helicopter = 6,
            helicopters = 6, coming = 3 },
        phrases = { ["is help coming"] = 8, ["is anyone coming"] = 8, ["anyone out there"] = 7,
            ["anybody out there"] = 7, ["will someone come"] = 7 } },
    { id = "cure",
        words = { cure = 7, vaccine = 7, antidote = 7, bitten = 6, bite = 5, bites = 5,
            scratched = 4, infection = 5, immune = 5, immunity = 5 },
        phrases = { ["am i infected"] = 8, ["is there a cure"] = 8 } },
    { id = "lore",
        exact={"lore","local history","knox history","emma backstory","emma history","who created emma","who made emma",
            "tell me about emma","what is emma","how does emma work",
            "knox event files","what is the knox event","does emma need the internet"},
        words = { outbreak = 6, knox = 6, happened = 4, government = 5, military = 5, army = 5,
            quarantine = 6, exclusion = 5, fence = 3, virus = 5, plague = 5, pandemic = 5,
            kentucky = 4, louisville = 5 },
        phrases = { ["what happened"] = 7, ["how did it start"] = 7, ["where did it come from"] = 7 } },
    { id = "delete",
        words = { uninstall = 6 },
        phrases = { ["rm rf"] = 8, ["delete yourself"] = 8, ["format c"] = 8, ["deltree"] = 8 } },
    { id = "hack",
        words = { hack = 6, hacking = 6, password = 6, admin = 5, administrator = 6, root = 5,
            override = 6, cheat = 5, cheats = 5, godmode = 6, login = 4, superuser = 6 } },
    { id = "game",
        words = { game = 5, games = 5, play = 4, chess = 6, checkers = 6, solitaire = 6,
            minesweeper = 6 },
        phrases = { ["tic tac toe"] = 7, ["play a game"] = 8 } },
    { id = "shutdown",
        words = { shutdown = 7, reboot = 6, restart = 6, poweroff = 7 },
        phrases = { ["shut down"] = 7, ["turn off"] = 6, ["power off"] = 7, ["switch off"] = 6 } },
    { id = "sleep",
        words = { goodnight = 7, sleep = 4, bed = 3, tired = 3, nap = 4 },
        phrases = { ["good night"] = 7, ["going to bed"] = 7, ["going to sleep"] = 7 } },
    { id = "hello",
        words = { hello = 4, morning = 3, evening = 3, afternoon = 2 },
        phrases = { ["good morning"] = 5, ["good evening"] = 5, ["good afternoon"] = 5,
            ["anyone there"] = 5, ["anybody there"] = 5, ["are you there"] = 6, ["you there"] = 5 } },
    { id = "yes", exact = { "yes", "y", "sure", "correct", "affirmative", "do it", "go ahead",
        "yes please", "please", "right" } },
    { id = "no", exact = { "no", "n", "negative", "wrong", "cancel", "never", "no thanks" } },
    { id = "ack", exact = { "ok", "alright", "fine", "cool", "got it", "understood", "i see",
        "noted", "ok thanks" } },
}

if SC.TerminalKnowledge then
    for _, spec in ipairs(SC.TerminalKnowledge.CHAT) do
        spec.phrases={}
        for _,phrase in ipairs(spec.exact) do spec.phrases[table.concat(Brain.tokens(phrase)," ")]=5 end
        Brain.INTENTS[#Brain.INTENTS+1]=spec
        L().POOLS[spec.id]=spec.lines
    end
    if not L().knowledgeExpanded then
        for name, extra in pairs(SC.TerminalKnowledge.EXTRA_POOLS) do
            for _,line in ipairs(extra) do L().POOLS[name][#L().POOLS[name]+1]=line end
        end
        L().knowledgeExpanded=true
    end
end
if Conversation then
    for _, spec in ipairs(Conversation.CHAT) do
        spec.phrases={}
        for _,phrase in ipairs(spec.exact) do spec.phrases[table.concat(Brain.tokens(phrase)," ")]=5 end
        Brain.INTENTS[#Brain.INTENTS+1]=spec
        L().POOLS[spec.id]=spec.lines
    end
    if not L().conversationExpanded then
        for name,extra in pairs(Conversation.EXTRA_POOLS) do
            for _,line in ipairs(extra) do L().POOLS[name][#L().POOLS[name]+1]=line end
        end
        L().conversationExpanded=true
    end
end
local INTENT_BY_ID, EXACT, VOCABULARY = {}, {}, {}
for _, intent in ipairs(Brain.INTENTS) do
    INTENT_BY_ID[intent.id] = intent
    for _, phrase in ipairs(intent.exact or {}) do
        if EXACT[phrase] == nil then EXACT[phrase] = intent.id end
    end
    for word in pairs(intent.words or {}) do
        if #word >= 4 then VOCABULARY[#VOCABULARY + 1] = word end
    end
    if intent.lines then
        for phrase in pairs(intent.phrases) do
            for word in phrase:gmatch("%S+") do if #word>=4 then VOCABULARY[#VOCABULARY+1]=word end end
        end
    end
end
table.sort(VOCABULARY)
local KNOWN = {}
for _, word in ipairs(VOCABULARY) do KNOWN[word] = true end
for _, intent in ipairs(Brain.INTENTS) do
    for phrase in pairs(intent.phrases or {}) do
        for word in string.gmatch(phrase, "%S+") do KNOWN[word] = true end
    end
    for _, phrase in ipairs(intent.exact or {}) do
        for word in string.gmatch(phrase, "%S+") do KNOWN[word] = true end
    end
    for word in pairs(intent.words or {}) do KNOWN[word] = true end
end

-- A misspelling must keep its first letter and stay within one edit (two for
-- long words). Exact words, stop words and names are never corrected.
local function corrected(word, protected)
    if KNOWN[word] or STOP[word] or (protected and protected[word]) then return word end
    local limit = allowedDistance(word)
    if limit == 0 then return word end
    local best, bestDistance = nil, limit + 1
    local first = string.sub(word, 1, 1)
    for _, candidate in ipairs(VOCABULARY) do
        if string.sub(candidate, 1, 1) == first then
            local value = Brain.distance(word, candidate, limit)
            if value < bestDistance then best, bestDistance = candidate, value end
        end
    end
    return best or word
end

local function score(intent, tokenSet, padded)
    local total = 0
    for word, weight in pairs(intent.words or {}) do
        if tokenSet[word] then total = total + weight end
    end
    for phrase, weight in pairs(intent.phrases or {}) do
        if string.find(padded, " " .. phrase .. " ", 1, true) then total = total + weight end
    end
    return total
end

-- ---------------------------------------------------------------------------
-- Session
-- ---------------------------------------------------------------------------

local function defaultRandom(count)
    if count <= 1 then return 1 end
    if type(ZombRand) == "function" then
        local ok, value = pcall(ZombRand, count)
        if ok and tonumber(value) then return math.floor(tonumber(value)) + 1 end
    end
    return math.random(count)
end

function Brain.normalizeMemory(value)
    local result = { notes = {}, visits = 0 }
    if type(value) ~= "table" then return result end
    local name = type(value.operator) == "string" and printable(value.operator, Brain.NAME_LENGTH) or ""
    if name ~= "" then result.operator = name end
    if type(value.notes) == "table" then
        for index = 1, Brain.MAX_NOTES do
            local entry = value.notes[index]
            local note = (type(entry) == "string" or type(entry) == "number")
                and printable(entry, Brain.NOTE_LENGTH) or ""
            if note ~= "" then result.notes[#result.notes + 1] = note end
        end
    end
    local seen = tonumber(value.lastSeen)
    if seen and seen == seen and seen >= 0 and seen < 10000000 then result.lastSeen = seen end
    local visits = tonumber(value.visits)
    if visits and visits == visits then
        result.visits = math.max(0, math.min(100000, math.floor(visits)))
    end
    return result
end

function Brain.newSession(options)
    options = type(options) == "table" and options or {}
    local memory = Brain.normalizeMemory(options.memory)
    return {
        random = type(options.random) == "function" and options.random or defaultRandom,
        nowMs = type(options.nowMs)=="function" and options.nowMs
            or type(getTimestampMs)=="function" and getTimestampMs or nil,
        operator = memory.operator or printable(options.operator, Brain.NAME_LENGTH),
        notes = memory.notes,
        namedOperator = memory.operator ~= nil,
        visits = memory.visits,
        lastSeen = memory.lastSeen,
        recent = {},
        context = {},
        insults = 0,
        turns = 0,
    }
end

function Brain.exportMemory(session, worldHours)
    local notes = {}
    for index = 1, math.min(#session.notes, Brain.MAX_NOTES) do notes[index] = session.notes[index] end
    return Brain.normalizeMemory({
        operator = session.namedOperator and session.operator or nil,
        notes = notes,
        lastSeen = tonumber(worldHours) or session.lastSeen,
        visits = session.visits,
    })
end

local function roll(session, count)
    local value = tonumber(session.random(count)) or 1
    return math.max(1, math.min(count, math.floor(value)))
end

-- Pick from a pool without repeating the last few picks.
function Brain.pick(session, poolName)
    local pool = L().POOLS[poolName]
    if type(pool) ~= "table" or #pool == 0 then return nil end
    local recent = session.recent[poolName] or {}
    session.recent[poolName] = recent
    local blocked = {}
    for _, index in ipairs(recent) do blocked[index] = true end
    local open = {}
    for index = 1, #pool do
        if not blocked[index] then open[#open + 1] = index end
    end
    if #open == 0 then
        for index = 1, #pool do open[#open + 1] = index end
    end
    local chosen = open[roll(session, #open)]
    recent[#recent + 1] = chosen
    while #recent > math.min(3, #pool - 1) do table.remove(recent, 1) end
    return pool[chosen]
end

local function operatorName(session)
    return session.operator ~= "" and session.operator or "operator"
end

-- ---------------------------------------------------------------------------
-- Reply building
-- ---------------------------------------------------------------------------

local function newReply(intent, category)
    return { intent = intent, category = category or "generic", lines = {}, think = {} }
end

local function add(reply, text, fields)
    if text == nil then return end
    if type(text) == "table" then
        for _, line in ipairs(text) do add(reply, line, fields) end
        return
    end
    reply.lines[#reply.lines + 1] = Brain.fill(text, fields)
end

local function addPool(session, reply, poolName, fields)
    local entry = Brain.pick(session, poolName)
    if entry ~= nil then add(reply, entry, fields) end
end

local function addTemplate(reply, key, fields)
    add(reply, L().T[key], fields)
end

local function ask(turn, world, name, ...)
    local key = name
    if select("#", ...) > 0 then key = name .. ":" .. tostring((...)) end
    if turn.cache[key] ~= nil then return turn.cache[key] or nil end
    local value
    if type(world) == "table" and type(world[name]) == "function" then
        local ok, result = pcall(world[name], ...)
        if ok then value = result end
    end
    turn.cache[key] = value == nil and false or value
    return value
end

-- ---------------------------------------------------------------------------
-- Facts shared by several handlers
-- ---------------------------------------------------------------------------

local function campAccess(turn, world)
    local camp = ask(turn, world, "camp")
    if type(camp) ~= "table" or camp.configured ~= true then return false, "no_camp" end
    if camp.inside ~= true then return false, "outside_camp" end
    return true
end

local function peopleList(turn, world)
    if not campAccess(turn, world) then return {} end
    local people = ask(turn, world, "people")
    return type(people) == "table" and people or {}
end

local function hurtRows(people)
    local rows = {}
    for _, person in ipairs(people) do
        local health = tonumber(person.health)
        if person.away ~= true and (person.bleeding == true or (health and health < 80)) then
            rows[#rows + 1] = person
        end
    end
    table.sort(rows, function(a, b)
        return (tonumber(a.health) or 100) < (tonumber(b.health) or 100)
    end)
    return rows
end

local function mouths(people)
    local count = 1
    for _, person in ipairs(people) do
        if person.away ~= true then count = count + 1 end
    end
    return count
end

local CATEGORY_ALIASES = {
    food = { Food = true }, ammo = { Ammo = true }, ammunition = { Ammo = true },
    bullet = { Ammo = true }, medicine = { FirstAid = true }, medical = { FirstAid = true },
    firstaid = { FirstAid = true }, weapon = { Weapon = true, WeaponCrafted = true, ToolWeapon = true },
    tool = { Tool = true, ToolWeapon = true }, material = { Material = true },
    clothe = { Clothing = true }, clothing = { Clothing = true }, water = { Water = true },
    seed = { Gardening = true }, book = { Literature = true }, literature = { Literature = true },
}

local function nameWords(group)
    if group._words then return group._words end
    local words = {}
    for word in string.gmatch(string.lower(tostring(group.name or "")), "%a+") do
        words[#words + 1] = Brain.singular(word)
    end
    local short = string.match(tostring(group.type or ""), "%.([%w_]+)$")
    if short then words[#words + 1] = Brain.singular(string.lower(short)) end
    group._words = words
    return words
end

local function wordMatches(query, group)
    local alias = CATEGORY_ALIASES[query]
    if alias and (alias[tostring(group.category or "")] or (query == "food" and group.food == true)) then
        return true
    end
    for _, word in ipairs(nameWords(group)) do
        if word == query then return true end
        if #query >= 3 and string.sub(word, 1, #query) == query then return true end
        if #query >= 4 and string.sub(query, 1, 1) == string.sub(word, 1, 1)
            and Brain.distance(query, word, 1) <= 1 then return true end
    end
    return false
end

-- Every query word must match the item's name, type or category.
function Brain.matchStorage(index, queryWords)
    local matches, total = {}, 0
    if type(index) ~= "table" or type(index.groups) ~= "table" or #queryWords == 0 then
        return matches, total
    end
    for _, group in ipairs(index.groups) do
        local all = true
        for _, word in ipairs(queryWords) do
            if not wordMatches(word, group) then all = false break end
        end
        if all then
            matches[#matches + 1] = group
            total = total + (tonumber(group.count) or 0)
        end
    end
    table.sort(matches, function(a, b)
        local left, right = tonumber(a.count) or 0, tonumber(b.count) or 0
        if left ~= right then return left > right end
        return tostring(a.name) < tostring(b.name)
    end)
    return matches, total
end

local STORAGE_NOISE = {}
for word in string.gmatch("many much count stock inventory supplies storage stored store have got "
    .. "left find need enough stockpile quantity camp item items total there any some do we "
    .. "in on our of the a an is are", "%S+") do
    STORAGE_NOISE[word] = true
end

local function shownWords(tokens)
    local shown = {}
    for _, word in ipairs(tokens) do
        if not STOP[word] and not STORAGE_NOISE[word] and #word >= 2 then
            shown[#shown + 1] = word
        elseif word == "of" and #shown > 0 and shown[#shown] ~= "of" then
            shown[#shown + 1] = word
        end
    end
    while shown[#shown] == "of" do table.remove(shown) end
    return shown
end

local function itemWords(tokens)
    local words = {}
    for _, word in ipairs(tokens) do
        if not STOP[word] and not STORAGE_NOISE[word] and #word >= 2 then
            words[#words + 1] = Brain.singular(word)
        end
    end
    return words
end

local function foodFacts(index)
    local items, kcal = 0, 0
    for _, group in ipairs(index and index.groups or {}) do
        if group.food == true or group.category == "Food" then
            items = items + (tonumber(group.count) or 0)
            kcal = kcal + math.max(0, tonumber(group.kcal) or 0)
        end
    end
    return items, kcal
end

local function foodDays(kcal, mouthCount)
    local days = kcal / (math.max(1, mouthCount) * Brain.KCAL_PER_DAY)
    return math.floor(days * 10 + 0.5) / 10
end

local function clockText(clock)
    if type(clock) ~= "table" then return "an unknown hour" end
    local hour = math.floor(tonumber(clock.hour) or 0) % 24
    local minute = math.floor(tonumber(clock.minute) or 0) % 60
    local suffix = hour >= 12 and "PM" or "AM"
    local twelve = hour % 12
    if twelve == 0 then twelve = 12 end
    return twelve .. ":" .. (minute < 10 and "0" or "") .. minute .. " " .. suffix
end

local MONTHS = { "January", "February", "March", "April", "May", "June", "July", "August",
    "September", "October", "November", "December" }

local function dateText(clock)
    if type(clock) ~= "table" then return "an unknown date" end
    local month = MONTHS[(math.floor(tonumber(clock.month) or 0) % 12) + 1]
    return month .. " " .. math.floor(tonumber(clock.day) or 1) .. ", "
        .. math.floor(tonumber(clock.year) or 1993)
end

local function isNight(clock)
    local hour = type(clock) == "table" and tonumber(clock.hour) or nil
    return hour ~= nil and (hour >= 21 or hour < 6)
end

local function powerText(power)
    if type(power) ~= "table" then return "unknown" end
    if power.source == "grid" then return "grid" end
    if power.source == "generator" then
        if tonumber(power.fuel) then return "generator, fuel " .. math.floor(power.fuel) .. "%" end
        return "generator"
    end
    return "unknown"
end

local function skyText(weather)
    if type(weather) ~= "table" then return "conditions unknown" end
    local parts = {}
    local rain, fog, wind = tonumber(weather.rain) or 0, tonumber(weather.fog) or 0,
        tonumber(weather.wind) or 0
    if weather.snow == true then parts[#parts + 1] = "snow"
    elseif rain >= 0.6 then parts[#parts + 1] = "heavy rain"
    elseif rain >= 0.15 then parts[#parts + 1] = "rain" end
    if fog >= 0.4 then parts[#parts + 1] = "fog" end
    if wind >= 0.5 then parts[#parts + 1] = "strong wind" end
    if #parts == 0 then parts[1] = "dry" end
    return capitalize(listText(parts))
end

local function temperatures(weather)
    local celsius = type(weather) == "table" and tonumber(weather.temperature) or nil
    if not celsius then return nil, nil end
    return math.floor(celsius * 9 / 5 + 32 + 0.5), math.floor(celsius + 0.5)
end

local function personState(person)
    if person.away == true then return "out on the expedition" end
    local parts = {}
    if person.where and person.where ~= "" then parts[#parts + 1] = person.where end
    if person.doing and person.doing ~= "" then parts[#parts + 1] = string.lower(person.doing) end
    if #parts == 0 then return "location unknown" end
    return table.concat(parts, ", ")
end

local function healthExtra(person)
    local parts = {}
    if person.bleeding == true then parts[#parts + 1] = "bleeding" end
    if (tonumber(person.stress) or 0) >= 60 then parts[#parts + 1] = "stressed" end
    if tonumber(person.morale) and tonumber(person.morale) <= 30 then parts[#parts + 1] = "low spirits" end
    if #parts == 0 then return "" end
    return ", " .. table.concat(parts, ", ")
end

local function zombieFacts(turn, world)
    local zombies = ask(turn, world, "zombies")
    return type(zombies) == "table" and zombies or nil
end

local function jobFacts(turn, world)
    local jobs = ask(turn, world, "jobs")
    return type(jobs) == "table" and jobs or nil
end

-- ---------------------------------------------------------------------------
-- Handlers
-- ---------------------------------------------------------------------------

local H = {}

local function simplePool(poolName, category)
    return function(session, reply)
        reply.category = category or "chat"
        addPool(session, reply, poolName, { name = operatorName(session) })
    end
end

H.hello = simplePool("hello")
H.identity = simplePool("identity")
H.alive = simplePool("alive")
H.feelings = simplePool("feelings")
H.joke = simplePool("joke")
H.poem = simplePool("poem")
H.story = simplePool("story")
H.sing = simplePool("sing")
H.thanks = simplePool("thanks")
H.sorry = simplePool("sorry")
H.compliment = simplePool("compliment")
H.love = simplePool("love")
H.meaning = simplePool("meaning")
if SC.TerminalKnowledge then
    for _,spec in ipairs(SC.TerminalKnowledge.CHAT) do H[spec.id]=simplePool(spec.id) end
end
if Conversation then
    for _,spec in ipairs(Conversation.CHAT) do H[spec.id]=simplePool(spec.id) end
end
function H.guide(_, reply, turn)
    reply.category="chat"
    local record=Conversation and Conversation.guide(turn.slots.guideId)
    if not record then return add(reply,"I do not have that operating note. Ask help for supported subjects.") end
    local page=math.max(1,tonumber(turn.slots.page) or 1)
    if page>#record.pages then return add(reply,"That is the end of this operating note. Name another subject, or ask about the current camp readings.") end
    add(reply,record.title..":")
    add(reply,record.pages[page])
    if page<#record.pages then add(reply,"Ask tell me more for the next part.") end
end
function H.conversation_history(session,reply)
    reply.category="chat"
    local history=Conversation.state(session).history
    if #history==0 then return add(reply,"We have not discussed a subject in this session yet. What would you like to ask?") end
    add(reply,"Your recent questions in this terminal session:")
    for i=math.max(1,#history-5),#history do add(reply,"  - "..history[i].question) end
    add(reply,"I can check a subject again using current readings. Saved notes are separate; ask my notes to read them.")
end
function H.conversation_forget(session,reply)
    Conversation.forget(session)
    reply.category="chat"
    add(reply,"Recent conversation cleared. Your saved notes, files and hardware are unchanged. What shall we discuss?")
end
function H.conversation_missing(_,reply,turn)
    reply.category="chat"
    add(reply,"I cannot resolve "..printable(turn.slots.query or "that earlier subject",80).." from this session. Please name the person, item or topic.")
end
function H.clarify_person(session,reply,turn)
    reply.category="chat"
    local choices={}
    if #(turn.slots.people or {})==0 then return add(reply,"I have no current person to attach that question to. Please give their name.") end
    add(reply,"Which person do you mean? Type their full name or a number in chat:")
    for i=1,math.min(8,#(turn.slots.people or {})) do
        local person=turn.slots.people[i]
        choices[i]={id=person.id,name=printable(person.name,80)}
        add(reply,"  "..i..". "..choices[i].name)
    end
    session.context.personChoices={people=choices,aspect=turn.slots.aspect,turn=session.turns}
end
function H.lore(session,reply,turn,world)
    local archive=SC.TerminalLore
    if not archive then return addPool(session,reply,"lore") end
    reply.category="lore"
    local query=string.lower(turn.slots.query or "")
    if not turn.slots.more then session.context.referencesSeen={} end
    local clock=ask(turn,world,"clock")
    local knowledge=SC.TerminalKnowledge
    local record=turn.slots.referenceId and archive.reference(turn.slots.referenceId)
        or knowledge and knowledge.find(query,Brain.distance)
    if turn.slots.more then
        record=nil
        local previous=archive.reference(turn.slots.referenceId or session.context.referenceId)
        for _,id in ipairs(previous and previous.related or {}) do
            local candidate=archive.reference(id)
            if candidate and archive.available(candidate,clock)
                and not (session.context.referencesSeen or {})[id] then record=candidate break end
        end
        if not record then return add(reply,"That is the end of this thread in the available local files. Ask about another town, broadcaster or part of the Knox Event.") end
    end
    if not record then
        local id="knox_overview"
        if query:find("emma",1,true) or query:find("created",1,true) or query:find("backstory",1,true) then id="emma_origin" end
        if query:find("offline",1,true) or query:find("network",1,true) or query:find("internet",1,true) then id="emma_offline" end
        record=archive.reference(id) or archive.reference("county_rumour")
    end
    if not record or not archive.available(record,clock) then
        session.context.referenceId=nil
        return add(reply,"I have no dated local file on that subject available for the current clock. I cannot use a later report as if it had already arrived.")
    end
    if turn.slots.placeStatus then
        add(reply,"I cannot confirm that place's current safety, supplies or occupants from this terminal. This is background, not a live survey.")
    end
    add(reply,(record.source or "Local archive")..": "..record.date.." - "..record.title)
    add(reply,record.text)
    add(reply,"Archived reference, not a live transmission. Ask 'tell me more' for a related file, or choose County files and EMMA.")
    session.context.referenceId=record.id
    session.context.referencesSeen=session.context.referencesSeen or {}
    session.context.referencesSeen[record.id]=true
end
H.rescue = simplePool("rescue")
H.cure = simplePool("cure")
H.sudo = simplePool("sudo")
H.delete = simplePool("delete")
H.hack = simplePool("hack")
H.game = simplePool("game")
H.shutdown = simplePool("shutdown")
H.sleep = simplePool("sleep")

function H.insult(session, reply)
    reply.category = "chat"
    session.insults = session.insults + 1
    addPool(session, reply, session.insults >= 3 and "insult_again" or "insult",
        { name = operatorName(session) })
end

function H.help(_, reply)
    reply.category = "generic"
    add(reply, L().HELP)
end

function H.dir(_, reply)
    reply.category = "memory"
    add(reply, L().DIR)
end

function H.clear(_, reply)
    reply.command = "clear"
    reply.instant = true
end

function H.exit(session, reply)
    addPool(session, reply, "bye", { name = operatorName(session) })
    reply.command = "close"
end

H.ack = simplePool("ack")

function H.math(session, reply, turn)
    reply.category = "chat"
    local value = turn.slots.value
    if value == nil then return addPool(session, reply, "math_zero") end
    add(reply, turn.slots.expression .. " = " .. Brain.numberText(value) .. ".")
    addPool(session, reply, "math")
end

function H.yes(session, reply)
    addPool(session, reply, "yes_free")
end

function H.no(session, reply)
    addPool(session, reply, "no_free")
end

function H.request(_, reply, turn)
    reply.category = "jobs"
    reply.proposal = { kind = turn.slots.kind, query = turn.slots.query }
end

function H.factory_reset(_, reply)
    reply.proposal = { kind = "factory_reset" }
    reply.instant = true
end

function H.factory_reset_help(_, reply)
    add(reply, "Type factory reset to start a clean EMMA setup on this computer. I will ask for Y/N confirmation.")
    add(reply, "This erases the old owner's files, firm branding, your notes and conversation memory. "
        .. "Mounted hardware, access protections, screen colour and connected equipment settings stay intact.")
end

function H.skills(_, reply, turn, world)
    reply.category = "people"
    local query = string.lower(turn.slots.query or "")
    local aliases = { medic = "first aid", medical = "first aid", doctor = "first aid",
        wood = "axe handling", woodcutting = "axe handling", logging = "axe handling", shooting = "aiming",
        guns = "aiming", electricity = "electrical" }
    query = aliases[query] or query
    local best = {}
    for _, person in ipairs(peopleList(turn, world)) do
        if not person.away and person.atCamp ~= false then
            for _, skill in ipairs(person.skills or {}) do
                local name = tostring(skill.name)
                if query == "" or string.find(string.lower(name), query, 1, true) then
                    local current = best[name]
                    if not current or skill.level > current.level then
                        best[name] = { who = person.name, level = skill.level }
                    end
                end
            end
        end
    end
    local names = {}
    for name in pairs(best) do names[#names + 1] = name end
    table.sort(names)
    if #names == 0 then return add(reply, "I have no current skill readings for that job.") end
    add(reply, "Highest recorded skill among people currently at camp:")
    for _, name in ipairs(names) do
        add(reply, "  - " .. name .. ": " .. best[name].who .. ", level " .. best[name].level .. ".")
    end
    add(reply, "Availability, tools and safety still determine who can do the work.")
end

function H.shortages(session, reply, turn, world)
    reply.category = "storage"
    local facts = ask(turn, world, "shortages")
    if type(facts) ~= "table" then return addPool(session, reply, "unavailable") end
    if facts.pending then add(reply, "The camp stock audit is still updating. Ask again shortly.") end
    if facts.ageSeconds then add(reply, "Last completed stock audit: " .. facts.ageSeconds .. " seconds ago.") end
    local shown = 0
    for _, row in ipairs(facts.stock or {}) do
        if row.status ~= "Ready" then
            shown = shown + 1
            add(reply, "  - " .. tostring(row.name) .. ": " .. tostring(row.count or 0) .. "/"
                .. tostring(row.target or 0) .. " target (" .. tostring(row.status or "unknown") .. ").")
        end
    end
    if shown == 0 and not facts.pending then add(reply, "The recorded stock targets are covered.") end
    for _, alert in ipairs(facts.alerts or {}) do add(reply, "  - " .. alert) end
    if (facts.unloaded or 0) > 0 then add(reply, "Some stores are unloaded. These totals may be incomplete.") end
end

function H.alarms(session, reply, turn, world)
    reply.category = "jobs"
    local facts = ask(turn, world, "alarms")
    if type(facts) ~= "table" then return addPool(session, reply, "unavailable") end
    if facts.active then
        local alarm = facts.active
        add(reply, "Camp alarm: " .. tostring(alarm.level) .. "; " .. tostring(alarm.count)
            .. " threats " .. tostring(alarm.side) .. ".")
        add(reply, "Reported by " .. tostring(alarm.spotter) .. "; " .. tostring(alarm.responding or 0) .. " responding.")
    else add(reply, "No active camp alarm is recorded.") end
    if facts.last then add(reply, "Last cleared alarm this session: " .. facts.last.level .. " (" .. facts.last.reason .. ").")
    else add(reply, "No cleared alarm is recorded for this session.") end
    add(reply, "Alarm history is limited to the current session.")
end

function H.deliveries(session, reply, turn, world)
    reply.category = "expedition"
    local facts = ask(turn, world, "deliveries")
    if type(facts) ~= "table" then return addPool(session, reply, "unavailable") end
    if #(facts.rows or {}) == 0 then return add(reply, "No returned expedition has a pending delivery on record.") end
    for index, row in ipairs(facts.rows) do
        add(reply, "  - Returned " .. tostring(row.kind) .. " trip " .. index .. ": collected "
            .. tostring(row.collected or 0) .. ", carried " .. tostring(row.carried or 0)
            .. ", stored " .. tostring(row.stored or 0) .. ", pending " .. tostring(row.pending or 0) .. ".")
        if (row.unknown or 0) > 0 then add(reply, "    " .. row.unknown .. " items cannot currently be located; their ownership remains unresolved.") end
        if row.toolsPending then add(reply, "    Borrowed tools still need to be returned.") end
        if row.retryRemainingMs then add(reply, "    Next automatic delivery check in about "
            .. math.max(1, math.ceil(row.retryRemainingMs / 1000)) .. " seconds.") end
    end
    if facts.truncated then add(reply, "More delivery records exist; only the first eight are shown.") end
end

function H.whoami(session, reply, turn, world)
    reply.category = "memory"
    addPool(session, reply, "whoami", { name = operatorName(session),
        alive = #peopleList(turn, world) + 1 })
end

function H.recall(session, reply)
    reply.category = "memory"
    if #session.notes == 0 then return addPool(session, reply, "recall_none") end
    addTemplate(reply, "recall_head")
    for index, note in ipairs(session.notes) do addTemplate(reply, "recall_row", { n = index, note = note }) end
end

function H.forget(session, reply)
    reply.category = "memory"
    session.notes = {}
    reply.memoryChanged = true
    addPool(session, reply, "forget")
end

function H.remember(session, reply, turn)
    reply.category = "memory"
    local note = trim(string.gsub(printable(turn.slots.note, Brain.NOTE_LENGTH), "[{}]", ""))
    if note == "" then return addPool(session, reply, "remember_empty") end
    table.insert(session.notes, note)
    while #session.notes > Brain.MAX_NOTES do table.remove(session.notes, 1) end
    reply.memoryChanged = true
    addPool(session, reply, "remember_ok", { note = note })
end

function H.callme(session, reply, turn)
    reply.category = "memory"
    local name = printable(turn.slots.name, Brain.NAME_LENGTH)
    name = string.gsub(name, "[^%a%s%-%.]", "")
    name = trim(name)
    if name == "" then return addPool(session, reply, "fallback") end
    session.operator, session.namedOperator = capitalize(name), true
    reply.memoryChanged = true
    addPool(session, reply, "callme", { name = session.operator })
end

function H.time(session, reply, turn, world)
    reply.category = "time"
    local clock = ask(turn, world, "clock")
    if type(clock) ~= "table" then return addPool(session, reply, "unavailable") end
    addTemplate(reply, "time", { time = clockText(clock), date = dateText(clock),
        days = math.max(1, math.floor(tonumber(clock.days) or 0) + 1) })
    addPool(session, reply, isNight(clock) and "night" or "day")
end

function H.weather(session, reply, turn, world)
    reply.category = "weather"
    local weather = ask(turn, world, "weather")
    local fahrenheit, celsius = temperatures(weather)
    if not fahrenheit then return addPool(session, reply, "unavailable") end
    addTemplate(reply, "weather", { tempF = fahrenheit, tempC = celsius, sky = skyText(weather) })
    if (tonumber(weather.rain) or 0) >= 0.15 or roll(session, 3) == 1 then
        addPool(session, reply, "weather_talk")
    end
end

function H.power(session, reply, turn, world)
    reply.category = "power"
    local power = ask(turn, world, "power")
    if type(power) ~= "table" or (power.source ~= "grid" and power.source ~= "generator") then
        return addTemplate(reply, "power_unknown")
    end
    if power.source == "grid" then
        addTemplate(reply, "power_grid")
        return addPool(session, reply, "power_grid")
    end
    local fuel = tonumber(power.fuel)
    if not fuel then return addTemplate(reply, "power_generator_unseen") end
    addTemplate(reply, "power_generator", { fuel = math.floor(fuel + 0.5),
        condition = math.floor((tonumber(power.condition) or 100) + 0.5) })
    addPool(session, reply, fuel < 25 and "power_gen_low" or "power_gen_ok")
end

function H.people_list(session, reply, turn, world)
    reply.category = "people"
    local people = peopleList(turn, world)
    reply.subjects={}
    for _,person in ipairs(people) do reply.subjects[#reply.subjects+1]={id=person.id,name=person.name} end
    if #people == 0 then return addPool(session, reply, "people_none") end
    if #people == 1 then addTemplate(reply, "people_head_one")
    else addTemplate(reply, "people_head", { n = #people }) end
    for _, person in ipairs(people) do
        addTemplate(reply, "people_row", { who = person.name, state = personState(person) })
    end
end

function H.people_hurt(session, reply, turn, world)
    reply.category = "people"
    local people = peopleList(turn, world)
    if #people == 0 then return addPool(session, reply, "people_none") end
    local rows = hurtRows(people)
    reply.subjects={}
    for _,person in ipairs(rows) do reply.subjects[#reply.subjects+1]={id=person.id,name=person.name} end
    if #rows == 0 then return addPool(session, reply, "hurt_none") end
    addTemplate(reply, "hurt_head", { n = #rows })
    local treatableReport
    for _, person in ipairs(rows) do
        addTemplate(reply, "hurt_row", { who = person.name,
            health = math.floor((tonumber(person.health) or 0) + 0.5), extra = healthExtra(person) })
        for index = 1, math.min(4, #(person.wounds or {})) do add(reply, "    " .. person.wounds[index]) end
        if not treatableReport and (person.bleeding or #(person.wounds or {}) > 0) then treatableReport = person end
    end
    if treatableReport then
        addPool(session, reply, "hurt_some")
        if treatableReport.id then add(reply, "You can ask me to send a medic to " .. treatableReport.name .. ".") end
    else add(reply, "No open wound is visible in these readings. Low health alone does not mean a bandage will help.") end
end

function H.people_mood(session, reply, turn, world)
    reply.category = "people"
    local people = peopleList(turn, world)
    reply.subjects={}
    for _,person in ipairs(people) do reply.subjects[#reply.subjects+1]={id=person.id,name=person.name} end
    if #people == 0 then return addPool(session, reply, "people_none") end
    for _, person in ipairs(people) do
        local state
        if person.away == true then state = "away, mood unknown"
        else
            local morale, stress = tonumber(person.morale), tonumber(person.stress)
            local parts = {}
            if morale then parts[#parts + 1] = "morale " .. math.floor(morale + 0.5) end
            if stress then parts[#parts + 1] = "stress " .. math.floor(stress + 0.5) end
            if person.mood and person.mood ~= "" then parts[#parts + 1] = string.lower(person.mood) end
            state = #parts > 0 and table.concat(parts, ", ") or "unreadable"
        end
        addTemplate(reply, "people_row", { who = person.name, state = state })
    end
end

function H.person(session, reply, turn, world)
    reply.category = "people"
    local person = turn.slots.person
    if type(person) ~= "table" then
        return addTemplate(reply, "person_unknown", { q = turn.slots.query or "" })
    end
    session.context.person = person.name
    session.context.personId = person.id
    if person.away == true then return addTemplate(reply, "person_away", { who = person.name }) end
    if turn.slots.aspect=="skills" then
        add(reply,person.name.."'s recorded skills:")
        local count=0
        for _,skill in ipairs(person.skills or {}) do
            if count>=12 then break end
            add(reply,"  - "..tostring(skill.name)..": level "..tostring(skill.level)..".") count=count+1
        end
        if count==0 then add(reply,"No current skill readings are available for this person.") end
        return
    end
    if turn.slots.aspect=="mood" then
        local parts={}
        if tonumber(person.morale) then parts[#parts+1]="morale "..math.floor(person.morale+.5) end
        if tonumber(person.stress) then parts[#parts+1]="stress "..math.floor(person.stress+.5) end
        if type(person.mood)=="string" and person.mood~="" then parts[#parts+1]=person.mood end
        return add(reply,person.name..": "..(#parts>0 and table.concat(parts,", ") or "no current mood readings")..".")
    end
    addTemplate(reply, "person", { who = person.name,
        health = math.floor((tonumber(person.health) or 0) + 0.5), extra = healthExtra(person),
        doing = capitalize(person.doing and person.doing ~= "" and string.lower(person.doing)
            or "activity unknown") })
    if person.where and person.where ~= "" then
        addTemplate(reply, "person_where", { who = person.name, where = person.where })
    end
    for index = 1, math.min(8, #(person.wounds or {})) do add(reply, "  - " .. person.wounds[index]) end
    local needs = {}
    if tonumber(person.hunger) then needs[#needs + 1] = "hunger " .. math.floor(person.hunger * 100 + .5) .. "%" end
    if tonumber(person.thirst) then needs[#needs + 1] = "thirst " .. math.floor(person.thirst * 100 + .5) .. "%" end
    if tonumber(person.endurance) then needs[#needs+1]="stamina "..math.floor(person.endurance*100+.5).."%" end
    if tonumber(person.fatigue) then needs[#needs+1]="tiredness "..math.floor(person.fatigue*100+.5).."%" end
    if #needs > 0 then add(reply, "Current needs: " .. table.concat(needs, ", ") .. ".") end
    if turn.slots.aspect=="needs" and #needs==0 then add(reply,"I have no current needs readings for this person.") end
end

local function jobRetries(row)
    return row.autoRetry == true or row.autoRetry == nil and tonumber(row.retryRemainingMs) ~= nil
end

local function addJobRetry(reply, row)
    if not jobRetries(row) then return end
    local remaining = math.max(0, tonumber(row.retryRemainingMs) or 0)
    if remaining == 0 then return addTemplate(reply, "job_retry_ready") end
    local minutes = math.max(1, math.ceil(remaining / 60000))
    addTemplate(reply, minutes == 1 and "job_retry_minute" or "job_retry_minutes", { n = minutes })
end

function H.jobs(session, reply, turn, world)
    reply.category = "jobs"
    local access, reason = campAccess(turn, world)
    if not access then return addPool(session, reply, reason) end
    local jobs = jobFacts(turn, world)
    if not jobs then return addPool(session, reply, "unavailable") end
    addTemplate(reply, "jobs_head", { active = jobs.active or 0, pending = jobs.pending or 0,
        blocked = jobs.blocked or 0 })
    local shown = 0
    for _, row in ipairs(jobs.rows or {}) do
        if row.who and row.who ~= "" and shown < 6 then
            shown = shown + 1
            addTemplate(reply, "jobs_row", { who = row.who, job = string.lower(tostring(row.job or "work")) })
        end
    end
    if (jobs.active or 0) == 0 and shown == 0 then addPool(session, reply, "jobs_idle") end
end

function H.blocked(session, reply, turn, world)
    reply.category = "jobs"
    local access, reason = campAccess(turn, world)
    if not access then return addPool(session, reply, reason) end
    local jobs = jobFacts(turn, world)
    if not jobs then return addPool(session, reply, "unavailable") end
    local rows = {}
    for _, row in ipairs(jobs.rows or {}) do
        if row.state == "blocked" then rows[#rows + 1] = row end
    end
    if #rows == 0 then return addPool(session, reply, "blocked_none") end
    addTemplate(reply, "blocked_head", { n = #rows })
    for index = 1, math.min(6, #rows) do
        addTemplate(reply, "blocked_row", { job = rows[index].job or "Work",
            reason = rows[index].reason or "reason unknown" })
        local row = rows[index]
        addJobRetry(reply, row)
        if row.id then add(reply, "    To retry now: retry job " .. tostring(row.id)) end
    end
end

function H.storage(session, reply, turn, world)
    reply.category = "storage"
    local access, reason = campAccess(turn, world)
    if not access then return addPool(session, reply, reason) end
    local index = ask(turn, world, "storage")
    if type(index) ~= "table" then return addPool(session, reply, "unavailable") end
    local words = turn.slots.item or {}
    if #words == 0 then
        if (tonumber(index.containers) or 0) == 0 or #(index.groups or {}) == 0 then
            return addTemplate(reply, "storage_empty")
        end
        addTemplate(reply, "storage_overview", { containers = index.containers or 0,
            items = commas(index.items or 0) })
        addTemplate(reply, "storage_top")
        local sorted = {}
        for _, group in ipairs(index.groups) do sorted[#sorted + 1] = group end
        table.sort(sorted, function(a, b)
            local left, right = tonumber(a.count) or 0, tonumber(b.count) or 0
            if left ~= right then return left > right end
            return tostring(a.name) < tostring(b.name)
        end)
        for position = 1, math.min(5, #sorted) do
            addTemplate(reply, "storage_row", { count = commas(sorted[position].count),
                label = sorted[position].name })
        end
        return
    end
    local shown = turn.slots.itemText or words
    session.context.item, session.context.itemText = words, shown
    local label = table.concat(shown, " ")
    local matches, total = Brain.matchStorage(index, words)
    if #matches == 0 then
        addTemplate(reply, "storage_none", { item = label })
        addPool(session, reply, "storage_none")
    else
        addTemplate(reply, "storage_total", { n = commas(total), item = label })
        if #matches > 1 then
            for position = 1, math.min(5, #matches) do
                addTemplate(reply, "storage_row", { count = commas(matches[position].count),
                    label = matches[position].name })
            end
        end
        local places, seen = {}, {}
        for _, group in ipairs(matches) do
            for _, place in ipairs(group.where or {}) do
                if not seen[place] and #places < 3 then seen[place], places[#places + 1] = true, place end
            end
        end
        if #places > 0 then addTemplate(reply, "storage_where", { where = listText(places) }) end
    end
    if index.truncated == true then addTemplate(reply, "storage_partial") end
    if turn.slots.required then
        local required=turn.slots.required
        if total>=required then add(reply,"For "..commas(required)..", the recorded stock covers that amount.")
        elseif index.truncated then add(reply,"The audit is incomplete; I cannot certify the shortfall against "..commas(required)..".")
        else add(reply,"For "..commas(required)..", you need "..commas(required-total).." more.") end
    elseif turn.slots.enough then
        add(reply,"How many do you need? Give me a quantity, for example: enough for 100. I will check the stock again.")
    end
end

function H.food(session, reply, turn, world)
    reply.category = "storage"
    local access, reason = campAccess(turn, world)
    if not access then return addPool(session, reply, reason) end
    local index = ask(turn, world, "storage")
    if type(index) ~= "table" then return addPool(session, reply, "unavailable") end
    session.context.item, session.context.itemText = { "food" }, { "food" }
    local items, kcal = foodFacts(index)
    if items == 0 then
        addTemplate(reply, "storage_none", { item = "food" })
        return addPool(session, reply, "storage_none")
    end
    local mouthCount = mouths(peopleList(turn, world))
    addTemplate(reply, "food", { n = commas(items), kcal = commas(kcal),
        mouths = mouthCount .. plural(mouthCount, " mouth", " mouths"),
        days_food = foodDays(kcal, mouthCount) })
    if index.truncated == true then addTemplate(reply, "storage_partial") end
end

function H.zombies(session, reply, turn, world)
    reply.category = "zombies"
    local zombies = zombieFacts(turn, world)
    if not zombies then return addPool(session, reply, "unavailable") end
    local count = math.floor(tonumber(zombies.count) or 0)
    if count <= 0 then
        addTemplate(reply, "zombies_none", { r = zombies.radius or 40 })
        return addPool(session, reply, "zombies_none")
    end
    addTemplate(reply, "zombies", { n = count, r = zombies.radius or 40,
        d = math.floor((tonumber(zombies.nearest) or 0) + 0.5), dir = zombies.dir or "away" })
    addPool(session, reply, count >= 10 and "zombies_many" or "zombies_some")
end

function H.expedition(session, reply, turn, world)
    reply.category = "expedition"
    local expedition = ask(turn, world, "expedition")
    if type(expedition) ~= "table" or expedition.active ~= true then
        addPool(session, reply, "expedition_none")
        local last = type(expedition) == "table" and expedition.last
        if not last then return end
        add(reply, "Last trip: " .. tostring(last.kind or "expedition") .. ".")
        if last.reason then add(reply, "Ended: " .. last.reason .. ".") end
        if last.collected ~= nil then add(reply, "Collected: " .. last.collected .. ".") end
        if last.carried ~= nil then add(reply, "Carried: " .. last.carried .. "; stored: " .. tostring(last.stored or 0) .. ".") end
        if last.deliveryPending then
            add(reply, "Delivery remains pending. Returning home has not completed storage.")
            if (last.unknown or 0) > 0 then add(reply, last.unknown .. " cargo items cannot currently be located; I cannot count them as carried or stored.") end
        end
        return
    end
    addTemplate(reply, "expedition", { leader = expedition.leader or "Someone",
        kind = expedition.kind or "supply" })
    if type(expedition.members) == "table" and #expedition.members > 0 then
        addTemplate(reply, "expedition_members", { members = listText(expedition.members) })
    end
    if tonumber(expedition.collected) and tonumber(expedition.requested) then
        addTemplate(reply, "expedition_progress", { collected = expedition.collected,
            requested = expedition.requested })
    end
    if expedition.phase then add(reply, "Last observed phase: " .. expedition.phase .. ".") end
    if expedition.destination then add(reply, "Planned destination: " .. expedition.destination .. ".") end
    if expedition.source == "radio" then add(reply, "Progress is from the last radio report; it may have changed.")
    elseif expedition.partial then add(reply, "Only part of the crew's cargo is currently observable.") end
    if expedition.carried ~= nil then add(reply, "Carried: " .. expedition.carried .. "; stored: " .. tostring(expedition.stored or 0) .. ".") end
    if expedition.deliveryPending then add(reply, "Delivery pending: " .. tostring(expedition.pending or 0) .. " items awaiting storage.") end
    addPool(session, reply, "expedition_some")
end

local function generatorFuel(turn, world)
    local power = ask(turn, world, "power")
    if type(power) == "table" and power.source == "generator" then return tonumber(power.fuel) end
    return nil
end

function H.advice(session, reply, turn, world)
    reply.category = "advice"
    local people = peopleList(turn, world)
    for _, person in ipairs(people) do
        if person.away ~= true and person.bleeding == true then
            return addTemplate(reply, "advice_bleeding", { who = person.name })
        end
    end
    local hurt = hurtRows(people)
    if hurt[1] and (tonumber(hurt[1].health) or 100) < 50 then
        return addTemplate(reply, "advice_hurt", { who = hurt[1].name,
            health = math.floor((tonumber(hurt[1].health) or 0) + 0.5) })
    end
    local fuel = generatorFuel(turn, world)
    if fuel and fuel < 25 then return addTemplate(reply, "advice_fuel", { fuel = math.floor(fuel + 0.5) }) end
    local zombies = zombieFacts(turn, world)
    if zombies and (tonumber(zombies.count) or 0) >= 5 then
        return addTemplate(reply, "advice_zombies", { n = math.floor(zombies.count) })
    end
    local access = campAccess(turn, world)
    if access then
        local jobs = jobFacts(turn, world)
        local paused
        for _, row in ipairs(jobs and jobs.rows or {}) do
            if row.state == "blocked" then
                if not jobRetries(row) then
                    return addTemplate(reply, "advice_blocked", { job = row.job or "Work",
                        reason = capitalize(row.reason or L().T.job_reason_unknown):gsub("[%.%s]+$", "") })
                end
                paused = paused or row
            end
        end
        if paused then
            addTemplate(reply, "advice_paused", { job = paused.job or "Work",
                reason = capitalize(paused.reason or L().T.job_reason_unknown):gsub("[%.%s]+$", "") })
            return addJobRetry(reply, paused)
        end
        local index = ask(turn, world, "storage")
        if type(index) == "table" then
            local _, kcal = foodFacts(index)
            local days = foodDays(kcal, mouths(people))
            if days < 3 then return addTemplate(reply, "advice_food", { days_food = days }) end
        end
    else
        local camp = ask(turn, world, "camp")
        if type(camp) ~= "table" or camp.configured ~= true then
            return addTemplate(reply, "advice_camp")
        end
    end
    local clock = ask(turn, world, "clock")
    if isNight(clock) then return addTemplate(reply, "advice_night", { time = clockText(clock) }) end
    addPool(session, reply, "advice_generic")
end

-- A playful estimate built only from facts EMMA can actually see.
function Brain.survivalPercent(facts)
    local percent = 30
    percent = percent + math.min(6, facts.people or 0) * 5
    percent = percent + math.min(14, facts.foodDays or 0) * 2
    if facts.power == "grid" then percent = percent + 6
    elseif facts.power == "generator" then
        local fuel = tonumber(facts.fuel) or 50
        percent = percent + (fuel >= 50 and 5 or (fuel < 20 and -6 or 0))
    end
    percent = percent - math.min(3, facts.hurt or 0) * 7 - math.min(3, facts.bleeding or 0) * 5
    if (facts.zombies or 0) >= 10 then percent = percent - 12
    elseif (facts.zombies or 0) >= 3 then percent = percent - 5 end
    if facts.camp ~= true then percent = percent - 10 end
    return math.max(3, math.min(89, math.floor(percent)))
end

function H.odds(session, reply, turn, world)
    reply.category = "odds"
    local people = peopleList(turn, world)
    local facts = { people = #people, hurt = #hurtRows(people), bleeding = 0 }
    for _, person in ipairs(people) do
        if person.bleeding == true then facts.bleeding = facts.bleeding + 1 end
    end
    local power = ask(turn, world, "power")
    facts.power = type(power) == "table" and power.source or nil
    facts.fuel = type(power) == "table" and power.fuel or nil
    local zombies = zombieFacts(turn, world)
    facts.zombies = zombies and tonumber(zombies.count) or 0
    facts.camp = campAccess(turn, world) == true
    if facts.camp then
        local index = ask(turn, world, "storage")
        if type(index) == "table" then
            local _, kcal = foodFacts(index)
            facts.foodDays = foodDays(kcal, mouths(people))
        end
    end
    local percent = Brain.survivalPercent(facts)
    addTemplate(reply, "survive", { pct = percent })
    addPool(session, reply, percent >= 60 and "survive_high" or "survive_low")
end

function H.status(session, reply, turn, world)
    reply.category = "generic"
    local clock = ask(turn, world, "clock")
    addTemplate(reply, "status_head", { time = clockText(clock),
        days = type(clock) == "table" and math.max(1, math.floor(tonumber(clock.days) or 0) + 1) or "?" })
    local people = peopleList(turn, world)
    local away = 0
    for _, person in ipairs(people) do if person.away == true then away = away + 1 end end
    local access, reason = campAccess(turn, world)
    if access then
        addTemplate(reply, "status_people", { people = #people, hurt = #hurtRows(people), away = away })
        local jobs = jobFacts(turn, world)
        if jobs then
            addTemplate(reply, "status_jobs", { active = jobs.active or 0, pending = jobs.pending or 0,
                blocked = jobs.blocked or 0 })
        end
        local index = ask(turn, world, "storage")
        if type(index) == "table" then
            local _, kcal = foodFacts(index)
            local mouthCount = mouths(people)
            addTemplate(reply, "status_food", { days_food = foodDays(kcal, mouthCount),
                mouths = mouthCount .. plural(mouthCount, " mouth", " mouths") })
        end
    end
    addTemplate(reply, "status_power", { power = powerText(ask(turn, world, "power")) })
    local weather = ask(turn, world, "weather")
    local fahrenheit = temperatures(weather)
    if fahrenheit then
        addTemplate(reply, "status_weather", { weather = fahrenheit .. " F, " .. string.lower(skyText(weather)) })
    end
    local zombies = zombieFacts(turn, world)
    if zombies then
        local count = math.floor(tonumber(zombies.count) or 0)
        addTemplate(reply, "status_threat", { threat = count == 0 and "none nearby"
            or (count .. " within " .. (zombies.radius or 40) .. " meters") })
    end
    if not access then addPool(session, reply, reason) end
end

-- ---------------------------------------------------------------------------
-- Parsing
-- ---------------------------------------------------------------------------

local COMMON_WORD_NAMES = {}
for word in string.gmatch("will may mark rose june grace hope faith art bill frank sue dawn rich pat "
    .. "guy jack bob joy april summer august sunny buck chase drew lance max miles rusty sky", "%S+") do
    COMMON_WORD_NAMES[word] = true
end
local NAME_LEADERS = {}
for word in string.gmatch("is about find where locate of with for has does did call ask", "%S+") do
    NAME_LEADERS[word] = true
end

-- Name lookup from the live roster: every word of a name, and the whole name.
local function nameIndex(people)
    local index = {}
    for _, person in ipairs(people) do
        for word in string.gmatch(string.lower(tostring(person.name or "")), "%a+") do
            if #word >= 2 then
                index[word]=index[word] or {}
                local seen=false
                for _,candidate in ipairs(index[word]) do if candidate==person then seen=true end end
                if not seen then index[word][#index[word]+1]=person end
            end
        end
    end
    return index
end

local function findPerson(tokens, names, fuzzy)
    local matches,counts={},{}
    for position, word in ipairs(tokens) do
        local candidates = names[word]
        if candidates and (not COMMON_WORD_NAMES[word] or #tokens == 1
            or (position > 1 and NAME_LEADERS[tokens[position - 1]])) then
            for _,person in ipairs(candidates) do
                if not counts[person] then matches[#matches+1]=person counts[person]=0 end
                counts[person]=counts[person]+1
            end
        end
    end
    if #matches==0 and fuzzy then
        for _, word in ipairs(tokens) do
            if #word >= 4 and not STOP[word] and not KNOWN[word] then
                for name,candidates in pairs(names) do
                    if #name >= 4 and string.sub(name,1,1)==string.sub(word,1,1)
                        and not COMMON_WORD_NAMES[name] and Brain.distance(word,name,1)<=1 then
                        for _,person in ipairs(candidates) do
                            if not counts[person] then matches[#matches+1]=person counts[person]=1 end
                        end
                    end
                end
            end
        end
    end
    local best,choices=0,{}
    for _,person in ipairs(matches) do
        if counts[person]>best then best,choices=counts[person],{person}
        elseif counts[person]==best then choices[#choices+1]=person end
    end
    if #choices==1 then return choices[1] end
    if #choices>1 then
        table.sort(choices,function(a,b)
            if a.name~=b.name then return a.name<b.name end
            return tostring(a.id)<tostring(b.id)
        end)
        return nil,nil,choices
    end
    return nil
end

local function personReference(slots,people)
    for _,person in ipairs(people) do
        if slots.id and person.id==slots.id or not slots.id and person.name==slots.name then
            return "person",{person=person,aspect=slots.aspect}
        end
    end
    return "conversation_missing",{query=slots.name or "that person"}
end

local function topicReference(intent,slots,people)
    if intent=="person_reference" then return personReference(slots,people) end
    return intent,slots
end

local PRONOUNS = { he = true, she = true, him = true, her = true }
local GROUP_PRONOUNS = { they = true, them = true }
local THING_PRONOUNS = { them = true, those = true, it = true, these = true, that = true }

local function lettersOnly(value)
    return (string.gsub(value, "[^%a]", ""))
end

local function looksLikeMash(text)
    local letters = lettersOnly(string.lower(text))
    if #letters < 6 then return false end
    local vowels = #(string.gsub(letters, "[^aeiouy]", ""))
    return vowels / #letters < 0.15
end

local function looksLikeShout(text)
    local letters = lettersOnly(text)
    return #letters >= 6 and not string.find(letters, "%l")
end

local function freeText(raw, patterns)
    local lower = string.lower(raw)
    for _, pattern in ipairs(patterns) do
        local first, last = string.find(lower, pattern)
        if first then
            local rest = trim(string.sub(raw, last + 1))
            rest = string.gsub(rest, "^[Tt][Hh][Aa][Tt]%s+", "")
            return rest
        end
    end
    return nil
end

local REMEMBER_PATTERNS = { "^%s*remember%s+", "^%s*remember$", "^%s*make a note%s*", "^%s*note:?%s+",
    "^%s*write down%s+", "^%s*save note%s+" }
local CALLME_PATTERNS = { "^%s*call me%s+", "^%s*my name is%s+", "^%s*my names%s+" }
local FOLLOW_PREFIXES = { {"no","i","meant"},{"no","i","mean"},{"i","meant"},{"i","mean"},{"actually"},
    { "and", "what", "about" }, { "what", "about" }, { "how", "about" },
    { "and" }, { "also" } }

local function stripFollowUp(tokens)
    for _, prefix in ipairs(FOLLOW_PREFIXES) do
        if #tokens > #prefix then
            local match = true
            for index, word in ipairs(prefix) do
                if tokens[index] ~= word then match = false break end
            end
            if match then
                local rest = {}
                for index = #prefix + 1, #tokens do rest[#rest + 1] = tokens[index] end
                return rest, true
            end
        end
    end
    return tokens, false
end

local function scored(tokens)
    local set = {}
    for _, word in ipairs(tokens) do set[word] = true end
    local padded = " " .. table.concat(tokens, " ") .. " "
    local best, bestScore, runner, runnerScore = nil, 0, nil, 0
    for _, intent in ipairs(Brain.INTENTS) do
        local value = score(intent, set, padded)
        if value > bestScore then
            runner, runnerScore = best, bestScore
            best, bestScore = intent, value
        elseif value > runnerScore then
            runner, runnerScore = intent, value
        end
    end
    return best, bestScore, runner, runnerScore
end

-- A name turns these into a question about that one person. Anything else
-- ("thanks, Kate") keeps its own meaning.
local PERSON_COMPATIBLE = { people_list = true, people_hurt = true, people_mood = true, jobs = true,
    storage = true, food = true, expedition = true, blocked = true }

-- Returns the intent id and the slots for one line of input.
function Brain.parse(session, raw, world, turn)
    turn = turn or { cache = {} }
    local text = trim(printable(raw, Brain.MAX_INPUT))
    local context = session.context
    if text == "" then return "empty", {} end
    local note = freeText(text, REMEMBER_PATTERNS)
    if note and string.find(string.lower(note), "^me%W*$") then return "whoami", {} end
    if note then return "remember", { note = note } end
    local expression, value = Brain.arithmetic(text)
    if expression then return "math", { expression = expression, value = value } end
    local name = freeText(text, CALLME_PATTERNS)
    if name then return "callme", { name = name } end
    local tokens = Brain.tokens(text)
    if #tokens == 0 then return string.find(text, "?", 1, true) and "help" or "mash", {} end
    if tokens[1] == "sudo" then return "sudo", {} end
    local joined = table.concat(tokens, " ")
    local pending = context.pending
    context.pending = nil
    local exact = EXACT[joined]
    if pending and (exact == "yes" or exact == "ack") then return pending.intent, pending.slots or {} end
    if pending and exact == "no" then return "did_you_mean_no", {} end
    local selection=context.personChoices
    context.personChoices=nil
    if selection and session.turns-selection.turn<=2 then
        local ordinal={first=1,second=2,third=3,fourth=4,fifth=5,sixth=6,seventh=7,eighth=8}
        local number=tonumber(joined:match("^(%d)$"))
            or ordinal[joined:match("^the (%a+) one$") or joined:match("^(%a+) one$") or joined]
        if number and selection.people[number] then
            local person=selection.people[number]
            return personReference({id=person.id,name=person.name,aspect=selection.aspect},peopleList(turn,world))
        end
        if exact=="yes" or exact=="ack" then return "clarify_person",{people=selection.people,aspect=selection.aspect} end
    end
    if Conversation then
        -- Phrases match the normalized tokens, so contractions and punctuation
        -- read as they do everywhere else. Only arithmetic follow-ups need the
        -- original text, for signed and decimal numbers.
        local meta,metaSlots=Conversation.meta(session,joined,text)
        if meta then return topicReference(meta,metaSlots,peopleList(turn,world)) end
        if Conversation.more(joined) or Conversation.refresh(joined) then
            local topic=Conversation.latest(session)
            if topic then
                if topic.kind=="lore" then return "lore",{more=not Conversation.refresh(joined),referenceId=topic.id} end
                local follow,followSlots=Conversation.topicTurn(topic)
                if follow=="guide" and Conversation.more(joined) then followSlots.page=(followSlots.page or 1)+1 end
                followSlots.explain=Conversation.more(joined)
                return topicReference(follow,followSlots,peopleList(turn,world))
            end
        end
    end
    if SC.TerminalKnowledge and SC.TerminalKnowledge.more(joined) then
        if Conversation then
            -- Older continuation phrases use the same bounded subject as
            -- other follow-ups, rather than reviving a stale legacy ID.
            local topic=Conversation.latest(session)
            if topic and topic.kind=="lore" then return "lore",{more=true,referenceId=topic.id} end
        elseif context.referenceId and (context.intent=="lore"
            or context.intent=="thanks" or context.intent=="ack") then
            return "lore",{more=true}
        end
    end
    if exact then return exact, exact=="lore" and {query=text} or {} end
    local bestSkill = string.lower(text):match("who is best at%s+(.+)")
        or string.lower(text):match("who is the best at%s+(.+)")
    if bestSkill then return "skills", { query = bestSkill:gsub("[?!%.]+$", "") } end
    -- Only explicit requests reach the confirmation layer. Ordinary questions
    -- about fuel, health or blocked work remain read-only.
    local request = string.lower(text):gsub("^emma[,:%s]+", ""):gsub("[?!%.]+$", ""):gsub("^please%s+", "")
        :gsub("^can you%s+", ""):gsub("^could you%s+", ""):gsub("^please%s+", "")
    if request == "what is a factory reset" or request == "what does factory reset do"
        or request == "how do i factory reset" or request == "how do i reset this computer" then
        return "factory_reset_help", {}
    end
    local resetTarget = request:match("^factory reset%s+(.+)$")
        or request:match("^reset%s+(.+)%s+to factory settings$")
        or request:match("^restore%s+(.+)%s+to factory settings$")
        or request:match("^reset%s+(.+)%s+to factory defaults$")
    if request == "factory reset" or request == "reset to factory settings"
        or request == "restore factory settings" or request == "restore factory defaults"
        or resetTarget == "this computer" or resetTarget == "this pc"
        or resetTarget == "the computer" or resetTarget == "the pc"
        or resetTarget == "my computer" or resetTarget == "my pc"
        or resetTarget == "computer" or resetTarget == "pc" then
        return "factory_reset", {}
    end
    local fuel = request:match("^refuel%s+(.+)$") or request:match("^fuel up%s+(.+)$")
        or request:match("^queue refuel%s+(.+)$")
    if fuel then
        if fuel == "generator" or fuel == "the generator" then
            return "request", { kind = "refuel_generator" }
        end
        fuel = fuel:gsub("^the%s+", "")
        if fuel == "car" or fuel == "vehicle" then fuel = ""
        else fuel = fuel:gsub("^car%s+", ""):gsub("^vehicle%s+", "") end
        return "request", { kind = "refuel_vehicle", query = fuel }
    end
    local retry = request:match("^retry%s+(.+)$")
    if retry then
        retry = retry:gsub("^the%s+", "")
        if retry == "blocked jobs" or retry == "blocked job" or retry == "jobs" or retry == "job" then retry = ""
        else retry = retry:gsub("^blocked%s+", ""):gsub("^jobs?%s+", "") end
        return "request", { kind = "retry_job", query = retry }
    end
    local patient = request:match("^ask%s+the%s+medic%s+to%s+check%s+(.+)$")
        or request:match("^ask%s+a%s+medic%s+to%s+check%s+(.+)$")
        or request:match("^send%s+a?%s*medic%s+to%s+(.+)$")
        or request:match("^send%s+the%s+medic%s+to%s+(.+)$")
        or request:match("^treat%s+(.+)$")
    if patient then
        if Conversation and (patient=="her" or patient=="him" or patient=="them") then
            local topic=Conversation.latest(session,{person=true,people=true})
            if not topic or topic.kind~="person" then return "conversation_missing",{query="the intended patient"} end
            local resolved,personSlots=personReference({id=topic.id,name=topic.label},peopleList(turn,world))
            if resolved~="person" then return resolved,personSlots end
            patient=personSlots.person.name
        end
        return "request", { kind = "medic", query = patient:gsub("^on%s+", "") }
    end
    if Conversation then
        local guide=Conversation.findGuide(text,Brain.tokens,Brain.distance)
        if guide then return "guide",{guideId=guide.id,page=1} end
    end
    -- Keep literal business names before chat shorthand expands U to "you".
    local knownReference,referenceScore
    if SC.TerminalKnowledge then
        knownReference,referenceScore=SC.TerminalKnowledge.find(text,Brain.distance)
        if not knownReference then knownReference,referenceScore=SC.TerminalKnowledge.find(joined,Brain.distance) end
    end
    if looksLikeMash(text) and not knownReference then return "mash", {} end

    local people = peopleList(turn, world)
    local names = nameIndex(people)
    local rest, followUp = stripFollowUp(tokens)
    local fixed = {}
    -- A matched directory title is already understood. In particular, do not
    -- turn County into count and route a police-department name to storage.
    for index, word in ipairs(rest) do fixed[index] = knownReference and word or corrected(word, names) end

    local best, bestScore, runner, runnerScore = scored(fixed)
    local intent = best and bestScore >= Brain.THRESHOLD and best.id or nil

    local knowledge=SC.TerminalKnowledge
    local framed=joined:find("^tell me about ") or joined:find("^what is ") or joined:find("^who is ")
    local itemFollowUp=not framed and (context.intent=="storage" or context.intent=="food")
    local record=knowledge and not itemFollowUp and intent~="storage" and knownReference
    -- An exact complete directory title beats a shorter name inside it.
    -- Incidental place mentions still let an explicitly named person win.
    if not (record and referenceScore>=20) and (intent == nil or PERSON_COMPATIBLE[intent]) then
        local person,_,ambiguous = findPerson(fixed,names,false)
        if not person and not ambiguous then person,_,ambiguous=findPerson(rest,names,true) end
        if ambiguous then return "clarify_person",{people=ambiguous,aspect=Conversation and Conversation.aspect(joined)} end
        if person then return "person", { person = person,aspect=Conversation and Conversation.aspect(joined) } end
    end
    if record then
        return "lore",{query=text,referenceId=record.id,placeStatus=record.category=="places"
            and (joined:find("safe",1,true)~=nil or joined:find("occupied",1,true)~=nil
                or joined:find("supplies",1,true)~=nil or joined:find("open",1,true)~=nil
                or joined:find("zombies",1,true)~=nil or joined:find("clear",1,true)~=nil
                or joined:find("looted",1,true)~=nil)}
    end

    local pronoun, groupPronoun, thing = false, false, false
    for _, word in ipairs(fixed) do
        if PRONOUNS[word] then pronoun = true end
        if GROUP_PRONOUNS[word] then groupPronoun = true end
        if THING_PRONOUNS[word] then thing = true end
    end

    if Conversation then
        local current=Conversation.latest(session,{person=true,people=true,item=true,data=true,guide=true,lore=true})
        if current and current.kind=="lore" and thing and (intent==nil or intent=="zombies"
            or joined:find("looted",1,true) or joined:find("supplies",1,true) or joined:find("occupied",1,true)) then
            return "lore",{referenceId=current.id,placeStatus=true}
        end
        if current and current.kind=="data" and current.intent=="power" and thing
            and (intent==nil or intent=="power" or intent=="storage") then return "power",{} end
        local entity=Conversation.latest(session,{person=true,people=true,item=true})
        local namedPerson=Conversation.latest(session,{person=true,people=true})
        if pronoun and namedPerson and (intent==nil or intent=="people_hurt" or intent=="jobs"
            or intent=="people_mood" or intent=="skills" or intent=="storage" or intent=="sleep") then
            if namedPerson.kind=="people" then return "clarify_person",{people=namedPerson.people,aspect=Conversation.aspect(joined)} end
            return personReference({id=namedPerson.id,name=namedPerson.label,aspect=Conversation.aspect(joined)},people)
        end
        local countFollow=joined=="how many more" or joined=="how much more" or joined=="where are they"
            or joined=="where is it" or joined=="where are those" or joined=="do we have any"
            or joined=="how many do we have" or joined=="how much do we have" or joined=="is that enough"
            or joined=="do we have enough" or joined:find("^enough for %d+") or joined:find("^and for %d+")
            or joined:find("^is that enough for %d+") or joined:find("^is it enough for %d+")
            or joined:find("^do we have enough for %d+")
        if entity and entity.kind=="item" and (countFollow or thing and intent=="storage") then
            local follow,followSlots=Conversation.topicTurn(entity)
            followSlots.required=Conversation.quantity(text) or entity.required
            followSlots.enough=joined:find("enough",1,true)~=nil or joined:find("more",1,true)~=nil
            return follow,followSlots
        end
        if entity and entity.kind=="person" and groupPronoun and intent==nil then
            return personReference({id=entity.id,name=entity.label,aspect=Conversation.aspect(joined)},people)
        end
        if entity and entity.kind=="people" and groupPronoun and intent==nil then return "people_list",{} end
    end

    if not Conversation and context.person and ((pronoun and (intent == nil or intent == "people_hurt"
        or intent == "jobs" or intent == "people_mood")) or (groupPronoun and intent == nil)) then
        for _, candidate in ipairs(people) do
            if candidate.name == context.person then return "person", { person = candidate } end
        end
    end

    if intent == "storage" then
        local words, shown = itemWords(rest), shownWords(rest)
        local required=Conversation and Conversation.quantity(text)
        if required then
            local withoutNumbers={}
            for _,word in ipairs(rest) do if not tonumber(word) then withoutNumbers[#withoutNumbers+1]=word end end
            words,shown=itemWords(withoutNumbers),shownWords(withoutNumbers)
        end
        if #words==0 and Conversation and thing then
            local item=Conversation.latest(session,{item=true})
            if item then words,shown=item.item,item.itemText end
        elseif #words==0 and thing and context.item then words,shown=context.item,context.itemText or context.item end
        return "storage", { item = words, itemText = #shown > 0 and shown or nil,
            required=required,enough=joined:find("enough",1,true)~=nil }
    end
    if intent then return intent, intent=="lore" and {query=text} or {} end

    -- Nothing scored. Try the context, then the shelves, then a suggestion.
    local words, shown = itemWords(rest), shownWords(rest)
    if #words > 0 and #words <= 3 then
        local itemTopic=Conversation and Conversation.latest(session,{item=true})
        local lastIntent = itemTopic and itemTopic.intent or context.intent
        if followUp or lastIntent == "storage" or lastIntent == "food"
            or (best and best.id == "storage") then
            return "storage", { item = words, itemText = shown }
        end
        if campAccess(turn, world) then
            local index = ask(turn, world, "storage")
            local matches = Brain.matchStorage(index, words)
            if #matches > 0 then return "storage", { item = words, itemText = shown } end
        end
    end
    if followUp and context.intent and INTENT_BY_ID[context.intent]
        and INTENT_BY_ID[context.intent].label then
        return context.intent, {}
    end
    if best and bestScore > 0 and best.label then
        return "did_you_mean", { suggest = best }
    end
    if runner and runnerScore > 0 and runner.label then
        return "did_you_mean", { suggest = runner }
    end
    return "fallback", {}
end

H.empty = simplePool("empty", "chat")
H.mash = simplePool("mash", "chat")
H.fallback = simplePool("fallback", "chat")
H.did_you_mean_no = simplePool("did_you_mean_no", "chat")

function H.did_you_mean(session, reply, turn)
    reply.category = "chat"
    local suggest = turn.slots.suggest
    addTemplate(reply, "did_you_mean", { suggest = suggest.label })
    session.context.pending = { intent = suggest.id, slots = {} }
end

function H.repeat_last(session, reply)
    local last = session.context.last
    if type(last) ~= "table" or #last.lines == 0 then return addPool(session, reply, "repeat_none") end
    for _, line in ipairs(last.lines) do reply.lines[#reply.lines + 1] = line end
    reply.category = last.category
end
H["repeat"] = H.repeat_last

local DATA_CATEGORIES = { storage = true, people = true, jobs = true, power = true, weather = true,
    time = true, zombies = true, expedition = true, advice = true, odds = true }

local function thinking(session, reply)
    local steps = L().THINK[reply.category] or L().THINK.generic
    local count = DATA_CATEGORIES[reply.category] and math.min(#steps, 1 + roll(session, 2)) or 1
    local start = roll(session, #steps)
    for offset = 0, count - 1 do
        reply.think[#reply.think + 1] = steps[(start + offset - 1) % #steps + 1]
    end
    local base = DATA_CATEGORIES[reply.category] and 1200 or 500
    reply.thinkMs = base + (#reply.think - 1) * 350 + (roll(session, 9) - 1) * 50
end

-- One line of operator text in, one reply out.
local CAMP_INTENTS = {
    people_list = true, people_hurt = true, people_mood = true, person = true,
    storage = true, food = true, jobs = true, blocked = true, expedition = true,
    odds = true, request = true, skills = true, shortages = true, alarms = true, deliveries = true,
}

function Brain.respond(session, raw, world)
    session.turns = session.turns + 1
    if Conversation then Conversation.state(session) end
    local turn = { cache = {} }
    local intent, slots = Brain.parse(session, raw, world, turn)
    turn.slots = slots or {}
    local reply = newReply(intent)
    local handler = H[intent] or H.fallback
    if CAMP_INTENTS[intent] then
        local access, reason = campAccess(turn, world)
        if not access then handler = function(s, r) return addPool(s, r, reason) end end
    end
    local ok, failure = pcall(handler, session, reply, turn, world)
    if not ok then
        reply.lines, reply.category = {}, "chat"
        reply.error = tostring(failure)
        addPool(session, reply, "unavailable")
    end
    if ok and turn.slots.explain and Conversation then add(reply,Conversation.EXPLAIN[intent]) end
    if looksLikeShout(printable(raw, Brain.MAX_INPUT)) and intent ~= "mash" then
        local shout = Brain.pick(session, "shout")
        if shout then table.insert(reply.lines, 1, shout) end
    end
    if reply.category == "chat" and #reply.lines > 0 and roll(session, 40) == 40 then
        addPool(session, reply, "glitch")
    end
    if not reply.instant then thinking(session, reply) else reply.thinkMs = 0 end
    if intent ~= "repeat" and intent ~= "empty" and intent ~= "did_you_mean"
        and intent ~= "did_you_mean_no" and intent ~= "fallback"
        and not (Conversation and Conversation.neutral(intent)) then
        session.context.intent = intent
    end
    if intent ~= "repeat" and #reply.lines > 0 then
        session.context.last = { lines = reply.lines, category = reply.category }
    end
    if Conversation then Conversation.record(session,raw,reply,turn.slots) end
    return reply
end

-- The boot screen and the greeting for this operator.
function Brain.boot(session, world)
    local turn = { cache = {} }
    local reply = newReply("boot", "generic")
    local people = peopleList(turn, world)
    add(reply, L().BOOT, { alive = campAccess(turn, world)
        and (commas(#people + 1) .. " local records") or "not connected",
        power = powerText(ask(turn, world, "power")) })
    local clock = ask(turn, world, "clock")
    local now = type(clock) == "table" and tonumber(clock.worldHours) or nil
    local fields = { name = operatorName(session) }
    if (session.visits or 0) == 0 or not session.lastSeen or not now then
        addPool(session, reply, "greet_first", fields)
    else
        local away = math.max(0, now - session.lastSeen)
        fields.away = Brain.duration(away)
        addPool(session, reply, away >= 24 and "greet_long" or "greet_back", fields)
    end
    session.visits = (session.visits or 0) + 1
    session.lastSeen = now or session.lastSeen
    reply.memoryChanged = true
    return reply
end

Brain.HANDLERS = H

return Brain
