-- SPDX-License-Identifier: MIT
-- Rare computers with a personality: one line in, one reply out, and no menu.
-- No network and no model. Hand-written rules, a little memory and real facts.
-- Pure Lua: game facts arrive as plain values in `facts`, and effects leave as
-- flags on the reply. The caller decides whether an effect really happened.
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
local P = SC.TerminalPersona or {}
SC.TerminalPersona = P
SC.TerminalPersonaData = SC.TerminalPersonaData or {}

P.MAX_INPUT = 160
P.MAX_MEMORY = 4
P.MEMORY_LENGTH = 60
P.NAME_LENGTH = 16
P.REFLECT_WORDS = 8
P.IDLE_FIRST_SECONDS = 45
P.IDLE_MID_SECONDS = 120
-- Game squares. A player only ever reads meters: {METERS} counts one square as one meter.
P.THREAT_FAR, P.THREAT_NEAR = 14, 4
P.THREAT_FAR_MS, P.THREAT_NEAR_MS = 60000, 30000

-- How far down the conversation has gone: lifetime lines spoken, plus a little
-- for each return, because the machine has had time to think about you.
P.DEPTHS = { 12, 28, 50 }
P.RETURN_WEIGHT = 3
-- After someone says something serious, the machine stays on its surface lines
-- for this many game hours. Nothing a player does can turn that off.
P.GENTLE_HOURS = 168

-- Per mille, and only for a new machine with a free drawer. See section 4 of the plan.
P.DIRECTOR = { tour = 6, gap = 8, home = 120, stray = 4, pityAfter = 24, pityHome = 300, pityStray = 30, firstDay = 23 }
P.ORDER = { "spiffy", "ellis", "duty" }

local CONTRACTIONS = {
    im = "i am", ive = "i have", youre = "you are", youve = "you have", theyre = "they are",
    dont = "do not", doesnt = "does not", didnt = "did not", cant = "can not", cannot = "can not",
    wont = "will not", isnt = "is not", arent = "are not", wasnt = "was not", werent = "were not",
    wouldnt = "would not", couldnt = "could not", shouldnt = "should not", thats = "that is",
    whats = "what is", whos = "who is", wheres = "where is", hows = "how is", theres = "there is",
    hes = "he is", shes = "she is", lets = "let us", u = "you", ur = "your", r = "are",
    pls = "please", plz = "please", thx = "thanks", ty = "thanks", yeah = "yes", yep = "yes",
    yup = "yes", ya = "yes", nope = "no", nah = "no", okay = "ok", k = "ok", kk = "ok",
    hi = "hello", hey = "hello", hiya = "hello", howdy = "hello", yo = "hello", sup = "hello",
    greetings = "hello", heya = "hello", zeds = "zombies", zed = "zombie", gonna = "going to",
    wanna = "want to", gotta = "got to", gimme = "give me",
}
local YES = { yes = true, y = true, sure = true, ok = true, affirmative = true, correct = true,
    right = true, absolutely = true, definitely = true, please = true, indeed = true, aye = true,
    roger = true, alright = true, fine = true, certainly = true }
local NO = { no = true, n = true, never = true, negative = true, ["not"] = true }
local YES_PHRASES = { "i do", "i am", "of course", "go ahead", "do it", "why not", "i guess", "i will" }
local NOT_NAMES = { hello = true, yes = true, no = true, why = true, who = true, what = true, where = true,
    when = true, how = true, ok = true, thanks = true, help = true, none = true, nobody = true,
    nothing = true, you = true, me = true, i = true, the = true, a = true, ["not"] = true, fine = true,
    please = true, sorry = true, maybe = true, stop = true, bye = true, name = true, is = true }
-- Echoing a stranger's words is the one risky thing a parser does. Never reflect these.
local BLOCK = { fuck = true, fucking = true, fucker = true, shit = true, bitch = true, cunt = true,
    cock = true, dick = true, pussy = true, ass = true, asshole = true, bastard = true, whore = true,
    slut = true, sex = true, rape = true, nazi = true, tits = true, penis = true, vagina = true }
local SWAP = { i = "you", me = "you", my = "your", mine = "yours", myself = "yourself", am = "are",
    you = "i", your = "my", yours = "mine", yourself = "myself" }
local STOP = { that = true, this = true, what = true, with = true, have = true, your = true, about = true,
    there = true, they = true, them = true, ["then"] = true, from = true, just = true, like = true,
    want = true, know = true, does = true, will = true, would = true, could = true, should = true }

local function clean(value, limit)
    local text = string.gsub(tostring(value or ""), "[^ -~]", "")
    text = string.gsub(text, "%s+", " ")
    text = string.match(text, "^%s*(.-)%s*$") or ""
    if limit and #text > limit then text = string.sub(text, 1, limit) end
    return text
end

function P.tokens(raw)
    local lower = string.lower(clean(raw, P.MAX_INPUT))
    lower = string.gsub(lower, "'", "")
    lower = string.gsub(lower, "[^%w%s]", " ")
    local out = {}
    for word in string.gmatch(lower, "%S+") do
        local expanded = CONTRACTIONS[word]
        if expanded then
            for part in string.gmatch(expanded, "%S+") do out[#out + 1] = part end
        else
            out[#out + 1] = word
        end
    end
    return out
end

-- Same optimal string alignment as SC.TerminalBrain.distance. Kept here so this
-- file can be tested alone, and so a change to EMMA's parser cannot reach it.
function P.distance(a, b, limit)
    limit = limit or 2
    local la, lb = #a, #b
    if math.abs(la - lb) > limit then return limit + 1 end
    local before, previous = nil, {}
    for j = 0, lb do previous[j] = j end
    for i = 1, la do
        local current = { [0] = i }
        local lowest = i
        local ai = string.byte(a, i)
        for j = 1, lb do
            local bj = string.byte(b, j)
            local cost = ai == bj and 0 or 1
            local value = math.min(previous[j] + 1, math.min(current[j - 1] + 1, previous[j - 1] + cost))
            if before and i > 1 and j > 1 and ai == string.byte(b, j - 1) and string.byte(a, i - 1) == bj then
                value = math.min(value, before[j - 2] + 1)
            end
            current[j] = value
            if value < lowest then lowest = value end
        end
        if lowest > limit then return limit + 1 end
        before, previous = previous, current
    end
    return previous[lb]
end

local function hash(text)
    local total = 0
    for i = 1, #text do total = (total * 31 + string.byte(text, i)) % 104729 end
    return total
end

-- ---------------------------------------------------------------------------
-- Persona data: index once, never written to the save
-- ---------------------------------------------------------------------------

local function indexed(D)
    if D._byId then return D end
    local byId, known, list = {}, {}, {}
    local function add(word)
        if not known[word] then
            known[word] = true
            if #word >= 5 then list[#list + 1] = word end
        end
    end
    local function learn(row)
        for _, word in ipairs(row.words or {}) do add(word) end
        for _, word in ipairs(row.all or {}) do add(word) end
        for _, phrase in ipairs(row.phrases or {}) do
            for word in string.gmatch(phrase, "%S+") do add(word) end
        end
    end
    for _, rule in ipairs(D.rules) do
        byId[rule.id] = rule
        if D.dark and D.dark[rule.id] then rule.dark = D.dark[rule.id] end
        learn(rule)
    end
    for _, expect in pairs(D.expects or {}) do
        for _, row in ipairs(expect.match or {}) do learn(row) end
    end
    table.sort(list)
    D._byId, D._known, D._vocabulary = byId, known, list
    return D
end

local function corrected(D, word)
    if D._known[word] or #word < 5 then return word end
    local limit = #word >= 8 and 2 or 1
    local best, bestDistance = nil, limit + 1
    local first = string.sub(word, 1, 1)
    for _, candidate in ipairs(D._vocabulary) do
        if string.sub(candidate, 1, 1) == first then
            local value = P.distance(word, candidate, limit)
            if value < bestDistance then best, bestDistance = candidate, value end
        end
    end
    return best or word
end

-- ---------------------------------------------------------------------------
-- Saved state
-- ---------------------------------------------------------------------------

function P.new(id, seed)
    if not SC.TerminalPersonaData[id] then return nil end
    return { id = id, seed = math.floor(tonumber(seed) or 1), met = false, visits = 0, spoken = 0, flags = {}, used = {}, memory = {} }
end

-- Bad fields are dropped one at a time. A damaged conversation must never take
-- the rest of the computer's record with it. Unknown persona: nil, and the
-- caller treats the machine as an ordinary one.
function P.normalize(saved)
    if type(saved) ~= "table" or type(saved.id) ~= "string" then return nil end
    local D = SC.TerminalPersonaData[saved.id]
    if not D then return nil end
    indexed(D)
    local out = P.new(saved.id, saved.seed)
    out.met = saved.met == true
    local visits = tonumber(saved.visits)
    if visits and visits == visits and visits >= 0 then out.visits = math.min(100000, math.floor(visits)) end
    local spoken = tonumber(saved.spoken)
    if spoken and spoken == spoken and spoken >= 0 then out.spoken = math.min(1000000, math.floor(spoken)) end
    local gentle = tonumber(saved.gentleUntil)
    if gentle and gentle == gentle and gentle >= 0 and gentle < 100000000 then out.gentleUntil = gentle end
    local name = type(saved.name) == "string" and clean(saved.name, P.NAME_LENGTH) or ""
    if name ~= "" then out.name = name end
    local hours = tonumber(saved.lastHours)
    if hours and hours == hours and hours >= 0 and hours < 100000000 then out.lastHours = hours end
    if type(saved.flags) == "table" then
        local count = 0
        for _, rule in ipairs(D.rules) do
            for _, flag in ipairs(rule.set or {}) do
                if saved.flags[flag] == true and not out.flags[flag] and count < 64 then
                    out.flags[flag] = true
                    count = count + 1
                end
            end
        end
        for _, flag in ipairs({ "drawer_done", "forced", "power_cut", "moved_seen" }) do
            if saved.flags[flag] == true then out.flags[flag] = true end
        end
    end
    if type(saved.used) == "table" then
        for _, rule in ipairs(D.rules) do
            local count = tonumber(saved.used[rule.id])
            if count and count == count and count >= 1 then out.used[rule.id] = math.min(100000, math.floor(count)) end
        end
    end
    if type(saved.memory) == "table" then
        for index = 1, P.MAX_MEMORY do
            local row = saved.memory[index]
            if type(row) == "string" then
                local text = clean(row, P.MEMORY_LENGTH)
                if text ~= "" then out.memory[#out.memory + 1] = text end
            end
        end
    end
    if type(saved.expect) == "string" and D.expects and D.expects[saved.expect] then
        out.expect = saved.expect
        out.expectTries = math.min(16, math.max(0, math.floor(tonumber(saved.expectTries) or 0)))
        if type(saved.expectRule) == "string" and D._byId[saved.expectRule] then out.expectRule = saved.expectRule end
    end
    return out
end

function P.depth(state, hours)
    if state.gentleUntil and (not hours or hours < state.gentleUntil) then return 0 end
    local D = SC.TerminalPersonaData[state.id]
    local steps, level = D and D.depths or P.DEPTHS, 0
    for index = 1, #steps do
        if (state.spoken or 0) >= steps[index] then level = index end
    end
    return level
end

function P.session() return { turns = 0, misses = 0, sinceBeat = 0, noticed = {} } end

-- ---------------------------------------------------------------------------
-- Text
-- ---------------------------------------------------------------------------

local function blocked(words)
    for _, word in ipairs(words) do
        if BLOCK[word] then return true end
    end
    return false
end

function P.reflect(fragment)
    local words = {}
    for word in string.gmatch(fragment, "%S+") do words[#words + 1] = word end
    if #words == 0 or #words > P.REFLECT_WORDS or blocked(words) then return nil end
    local out, i = {}, 1
    while i <= #words do
        local word, nextWord = words[i], words[i + 1]
        if word == "you" and nextWord == "are" then
            out[#out + 1] = "i am"
            i = i + 2
        elseif word == "i" and nextWord == "am" then
            out[#out + 1] = "you are"
            i = i + 2
        else
            out[#out + 1] = SWAP[word] or word
            i = i + 1
        end
    end
    return table.concat(out, " ")
end

local function titleCase(word)
    return string.upper(string.sub(word, 1, 1)) .. string.sub(word, 2)
end

function P.captureName(tokens, padded)
    local found
    for _, pattern in ipairs({ " my name is (.-) $", " call me (.-) $", " i am called (.-) $", " this is (.-) $",
        " it is (.-) $", " name is (.-) $", " i am (.-) $" }) do
        found = string.match(padded, pattern)
        if found then break end
    end
    if not found and #tokens <= 2 then found = table.concat(tokens, " ") end
    if not found then return nil end
    local parts = {}
    for word in string.gmatch(found, "%S+") do parts[#parts + 1] = word end
    if #parts == 0 or #parts > 2 or blocked(parts) or NOT_NAMES[parts[1]] or not string.match(parts[1], "^%a") then return nil end
    for index, word in ipairs(parts) do parts[index] = titleCase(word) end
    local name = table.concat(parts, " ")
    return #name <= P.NAME_LENGTH and name or string.sub(name, 1, P.NAME_LENGTH)
end

local function yesOrNo(tokens, padded)
    if #tokens == 0 or #tokens > 6 then return nil end
    if NO[tokens[1]] then return "no" end
    if YES[tokens[1]] then return "yes" end
    for _, phrase in ipairs(YES_PHRASES) do
        if string.find(padded, " " .. phrase .. " ", 1, true) then return "yes" end
    end
    return nil
end

local function rating(tokens)
    local words = { one = 1, two = 2, three = 3, four = 4, five = 5 }
    for _, word in ipairs(tokens) do
        local value = tonumber(word) or words[word]
        if value and value >= 1 and value <= 5 then return math.floor(value) end
    end
    return nil
end

local function values(ctx)
    local facts, state = ctx.facts, ctx.state
    local v = { NAME = state.name or ctx.D.anon, DAY = facts.days, TIME = facts.time, SPOKEN = state.spoken,
        COMPANION = facts.companion, COMPANIONS = facts.companions, FALLEN = facts.fallen,
        R = ctx.reflected, ECHO = ctx.echo, RATING = ctx.rating, AWAY = ctx.away }
    if facts.zombies and facts.zombies > 0 then
        local count = math.floor(facts.zombies)
        v.ZOMBIES = count
        v.GUESTS = count == 1 and "1 guest" or tostring(count) .. " guests"
    end
    local distance = facts.threat and tonumber(facts.threat.distance)
    if distance then
        local whole = math.max(1, math.floor(distance + 0.5))
        v.METERS = whole == 1 and "1 meter" or tostring(whole) .. " meters"
    end
    -- The army reads a clock its own way: 1415, not 2:15 PM.
    if facts.hour then v.HHMM = string.format("%02d%02d", math.floor(facts.hour), math.floor(facts.minute or 0)) end
    if facts.level then v.LEVEL = math.abs(math.floor(facts.level)) end
    if facts.days and facts.days >= 2 then v.DAYS = facts.days end
    if facts.days and facts.days >= 4 then v.LATE = facts.days - 3 end
    if #state.memory > 0 then v.M = state.memory[(state.visits + (ctx.session.turns or 0)) % #state.memory + 1] end
    return v
end

-- A line that needs a fact we do not have is skipped, never printed with a hole.
local function fill(template, v)
    local missing = false
    local text = string.gsub(template, "{([A-Z]+)}", function(key)
        local value = v[key]
        if value == nil then missing = true return "" end
        if type(value) == "number" then value = math.floor(value + 0.5) end
        return tostring(value)
    end)
    if missing then return nil end
    return text
end

-- Round robin from a seeded start: no line repeats until every line has been used.
local function pickFrom(ctx, rule, lines, v, tier)
    local count = #lines
    if count == 0 then return nil end
    local start = (ctx.state.seed + hash(rule.id) + tier + (ctx.state.used[rule.id] or 0)) % count
    for offset = 0, count - 1 do
        local row = lines[(start + offset) % count + 1]
        local rows, out, okay = type(row) == "table" and row or { row }, {}, true
        for _, template in ipairs(rows) do
            local text = fill(template, v)
            if not text then okay = false break end
            out[#out + 1] = text
        end
        if okay then return out end
    end
    return nil
end

-- The darkest tier this conversation has reached wins, and a tier that needs a
-- fact we lack falls back to a lighter one. `plain` is the last resort: a key
-- beat must still happen when the game could not tell us the time.
local function variant(ctx, rule)
    local v = values(ctx)
    for tier = math.min(ctx.depth or 0, 3), 1, -1 do
        local lines = rule.dark and rule.dark[tier]
        if lines then
            local rows = pickFrom(ctx, rule, lines, v, tier)
            if rows then return rows end
        end
    end
    return pickFrom(ctx, rule, rule.lines or {}, v, 0) or pickFrom(ctx, rule, rule.plain or {}, v, 0)
end

-- ---------------------------------------------------------------------------
-- Rules
-- ---------------------------------------------------------------------------

local function allowed(ctx, rule)
    local state = ctx.state
    if rule.once and (state.used[rule.id] or 0) > 0 then return false end
    for _, flag in ipairs(rule.need or {}) do
        if not state.flags[flag] then return false end
    end
    for _, flag in ipairs(rule.without or {}) do
        if state.flags[flag] then return false end
    end
    if rule.drawer and (ctx.facts.drawer or "closed") ~= rule.drawer then return false end
    if rule.moved ~= nil and (ctx.facts.moved == true) ~= rule.moved then return false end
    if rule.camp ~= nil and (ctx.facts.atCamp == true) ~= rule.camp then return false end
    if rule.deep ~= nil and (ctx.facts.deep == true) ~= rule.deep then return false end
    if rule.depth and (ctx.depth or 0) < rule.depth then return false end
    if rule.hour and ctx.facts.hour ~= rule.hour then return false end
    if rule.sitting ~= nil and (ctx.facts.sitting == true) ~= rule.sitting then return false end
    return true
end

local function score(row, ctx)
    local total = 0
    if row.all then
        for _, word in ipairs(row.all) do
            if not ctx.set[word] then return 0 end
        end
        total = 3
    end
    if row.words or row.phrases then
        local hit = 0
        for _, phrase in ipairs(row.phrases or {}) do
            if string.find(ctx.padded, " " .. phrase .. " ", 1, true) then hit = hit + 4 end
        end
        for _, word in ipairs(row.words or {}) do
            if ctx.set[word] then hit = hit + 2 end
        end
        if hit == 0 then return 0 end
        total = total + hit
    end
    return total
end

local function best(ctx, test)
    local chosen, top = nil, 0
    for _, rule in ipairs(ctx.D.rules) do
        if (rule.words or rule.phrases or rule.all) and test(rule) and allowed(ctx, rule) then
            local value = score(rule, ctx)
            if value > 0 then
                value = value + (rule.rank or 5) * 100
                if value > top and variant(ctx, rule) then chosen, top = rule, value end
            end
        end
    end
    return chosen
end

local function fire(ctx, rule, depth)
    local state, reply = ctx.state, ctx.reply
    local rows = variant(ctx, rule)
    if not rows then return false end
    for _, text in ipairs(rows) do reply.rows[#reply.rows + 1] = text end
    state.used[rule.id] = (state.used[rule.id] or 0) + 1
    for _, flag in ipairs(rule.set or {}) do state.flags[flag] = true end
    if rule.effect then reply.effects[rule.effect] = true end
    if rule.effect2 then reply.effects[rule.effect2] = true end
    if rule.expect then state.expect, state.expectTries, state.expectRule = rule.expect, 0, rule.id end
    ctx.fired = rule
    if rule.next and (depth or 0) < 3 then
        local follow = ctx.D._byId[rule.next]
        if follow and allowed(ctx, follow) then fire(ctx, follow, (depth or 0) + 1) end
    end
    return true
end

-- Walking away from a question must not lose the story: a beat left unanswered
-- gets asked again later, or a session could never reach its drawer.
local function dropExpect(ctx)
    local state = ctx.state
    local asked = state.expectRule and ctx.D._byId[state.expectRule]
    if state.expect and asked and asked.beat then state.used[asked.id] = nil end
    state.expect, state.expectRule, state.expectTries = nil, nil, nil
end

local function fireId(ctx, id)
    local rule = id and ctx.D._byId[id]
    return rule and allowed(ctx, rule) and fire(ctx, rule) or false
end

local function nextBeat(ctx)
    for _, id in ipairs(ctx.D.spine or {}) do
        local rule = ctx.D._byId[id]
        if rule and allowed(ctx, rule) and (ctx.state.used[id] or 0) == 0 and variant(ctx, rule) then return rule end
    end
    return nil
end

local function urgentBeat(ctx)
    for _, id in ipairs(ctx.D.spine or {}) do
        local rule = ctx.D._byId[id]
        if rule and rule.urgent and allowed(ctx, rule) and (ctx.state.used[id] or 0) == 0 and variant(ctx, rule) then return rule end
    end
    return nil
end

local function answerExpect(ctx)
    local state, D = ctx.state, ctx.D
    local expect = D.expects and D.expects[state.expect]
    if not expect then state.expect = nil return false end
    local go
    for _, row in ipairs(expect.match or {}) do
        if score(row, ctx) > 0 then go = row.go break end
    end
    if not go then
        local answer = yesOrNo(ctx.tokens, ctx.padded)
        if answer == "yes" then go = expect.yes end
        if answer == "no" then go = expect.no end
    end
    if not go and expect.rating then
        local value = rating(ctx.tokens)
        if value then
            ctx.rating = value
            go = expect.rating[value]
        end
    end
    if not go then
        local aside = best(ctx, function(rule) return rule.aside end)
        if aside then return fire(ctx, aside) end
    end
    if not go and expect.name then
        local name = P.captureName(ctx.tokens, ctx.padded)
        if name then
            state.name = name
            go = expect.name
        else
            go = expect.noname
        end
    end
    if not go then go = expect.any end
    if go then
        state.expect = nil
        return fireId(ctx, go)
    end
    state.expectTries = (state.expectTries or 0) + 1
    if state.expectTries <= (expect.tries or 1) and expect.miss then return fireId(ctx, expect.miss) end
    state.expect = nil
    if expect.giveup then return fireId(ctx, expect.giveup) end
    return false
end

local function remember(ctx)
    local D, state = ctx.D, ctx.state
    for _, pattern in ipairs(D.remember or {}) do
        local fragment = string.match(ctx.norm, pattern)
        local mirrored = fragment and P.reflect("my " .. fragment)
        if mirrored and #mirrored <= P.MEMORY_LENGTH then
            for _, old in ipairs(state.memory) do
                if old == mirrored then return end
            end
            table.insert(state.memory, 1, mirrored)
            while #state.memory > P.MAX_MEMORY do table.remove(state.memory) end
            return
        end
    end
end

local function reflectRule(ctx)
    for _, row in ipairs(ctx.D.reflect or {}) do
        local fragment = string.match(ctx.norm, row.pattern)
        local mirrored = fragment and P.reflect(fragment)
        if mirrored then
            ctx.reflected = mirrored
            return ctx.D._byId[row.rule]
        end
    end
    return nil
end

local function looksMashed(tokens)
    if #tokens == 0 or #tokens > 3 then return false end
    for _, word in ipairs(tokens) do
        if #word >= 4 and not string.find(word, "[aeiouy]") then return true end
        if string.find(word, "[^aeiouy%d][^aeiouy%d][^aeiouy%d][^aeiouy%d][^aeiouy%d]") then return true end
    end
    return false
end

local function echoWord(tokens)
    if blocked(tokens) then return nil end
    for index = #tokens, 1, -1 do
        local word = tokens[index]
        if #word >= 4 and not STOP[word] and string.match(word, "^%a+$") then return word end
    end
    return nil
end

local function finish(ctx, raw)
    local D, state, session, reply, facts = ctx.D, ctx.state, ctx.session, ctx.reply, ctx.facts
    local quiet = reply.effects.close or reply.effects.shutdown or reply.effects.drawer or (ctx.fired and ctx.fired.rest)
    if ctx.fired and ctx.fired.beat then session.sinceBeat = 0 end
    session.sinceBeat = session.sinceBeat + 1
    -- An urgent beat waits one turn at most, so a big moment gets a line of its own.
    if not state.expect and not quiet then
        local beat = urgentBeat(ctx) or session.sinceBeat > (D.beatEvery or 4) and nextBeat(ctx)
        if beat and fire(ctx, beat) then session.sinceBeat = 0 end
    end
    if not quiet and session.turns >= 2 and session.turns % 3 == 0 and not state.expect then
        for _, row in ipairs(D.notices or {}) do
            local level = facts.moodles and facts.moodles[row.moodle] or 0
            if level >= (row.min or 2) and not session.noticed[row.moodle] then
                session.noticed[row.moodle] = true
                local rule = D._byId[row.rule]
                if rule then fire(ctx, rule) end
                break
            end
        end
    end
    if facts.pause and facts.pause >= (D.pauseAfter or 30) and session.turns > 1 and not session.pausedOnce then
        local rule = D._byId.pause_noted
        local rows = rule and variant(ctx, rule)
        if rows then
            session.pausedOnce = true
            state.used.pause_noted = (state.used.pause_noted or 0) + 1
            for index = #rows, 1, -1 do table.insert(reply.rows, 1, rows[index]) end
        end
    end
    local letters = string.gsub(raw, "%A", "")
    if #letters >= 6 and letters == string.upper(letters) and not session.shouted then
        local rule = D._byId.shouting
        local rows = rule and variant(ctx, rule)
        if rows then
            session.shouted = true
            state.used.shouting = (state.used.shouting or 0) + 1
            for index = #rows, 1, -1 do table.insert(reply.rows, 1, rows[index]) end
        end
    end
    return P.package(D, reply, ctx.depth)
end

-- `~` opens a slow row: the typewriter crawls, which is how a pause is written.
function P.package(D, reply, depth)
    depth = depth or 0
    local out = { rows = {}, effects = reply.effects, layer = reply.layer, depth = depth,
        speed = D.speeds and D.speeds[depth + 1] or D.speed,
        thinkMs = D.thinks and D.thinks[depth + 1] or D.thinkMs }
    for _, text in ipairs(reply.rows) do
        local slow = string.sub(text, 1, 1) == "~"
        if slow then text = string.sub(text, 2) end
        if D.upper then text = string.upper(text) end
        out.rows[#out.rows + 1] = { text = text, slow = slow }
    end
    return out
end

-- ---------------------------------------------------------------------------
-- One line in, one reply out
-- ---------------------------------------------------------------------------

function P.respond(state, session, raw, facts)
    if SC.EmmaCare then
        local signal=SC.EmmaUnderstand and SC.EmmaUnderstand.careSignal(raw)
        local care=SC.EmmaCare.respond(session,raw,signal,true)
        if care then
            local rows={}
            for _,line in ipairs(care.lines) do rows[#rows+1]={text=line} end
            return {layer="care",rows=rows,effects={},thinkMs=0,speed=95,
                private=true,support=care.support,careDetected=care.careDetected,command=care.command}
        end
    end
    local D = indexed(SC.TerminalPersonaData[state.id])
    facts = facts or {}
    local text = clean(raw, P.MAX_INPUT)
    local reply = { rows = {}, effects = {} }
    local ctx = { D = D, state = state, session = session, facts = facts, reply = reply, set = {}, tokens = {}, depth = P.depth(state, facts.hours) }
    session.turns = session.turns + 1
    session.spoke = true
    local tokens = P.tokens(text)
    for index, word in ipairs(tokens) do tokens[index] = corrected(D, word) end
    ctx.tokens = tokens
    for _, word in ipairs(tokens) do ctx.set[word] = true end
    ctx.norm = table.concat(tokens, " ")
    ctx.padded = " " .. ctx.norm .. " "
    ctx.echo = echoWord(tokens)
    if #tokens == 0 then
        reply.layer = "empty"
        fireId(ctx, "empty")
        return P.package(D, reply, ctx.depth)
    end
    local firstOfVisit = session.turns == 1
    if firstOfVisit then
        dropExpect(ctx)
        if state.lastHours and facts.hours then ctx.away = math.floor(math.max(0, facts.hours - state.lastHours) / 24 + 0.5) end
        if state.met then state.visits = state.visits + 1 end
    end
    if facts.hours then state.lastHours = facts.hours end
    remember(ctx)
    if firstOfVisit and state.met then state.spoken = (state.spoken or 0) + P.RETURN_WEIGHT end
    if ctx.norm ~= session.lastNorm and not looksMashed(tokens) then state.spoken = (state.spoken or 0) + 1 end
    ctx.depth = P.depth(state, facts.hours)

    -- Someone saying this for real gets a straight answer before anything else,
    -- and the machine stays on its surface lines for a good while afterwards.
    ctx.depth = 0
    local serious = best(ctx, function(rule) return rule.safety end)
    ctx.depth = P.depth(state, facts.hours)
    if serious then
        reply.layer = "safety"
        state.met = true
        state.gentleUntil = (facts.hours or 0) + P.GENTLE_HOURS
        ctx.depth = 0
        fire(ctx, serious)
        return P.package(D, reply, ctx.depth)
    end
    -- Leaving and ending the machine always work, even in the middle of a question.
    local interrupt = best(ctx, function(rule) return rule.interrupt end)
    if interrupt and state.met then
        dropExpect(ctx)
        reply.layer = "rule"
        fire(ctx, interrupt)
        return finish(ctx, text)
    end
    if not state.met then
        state.met, state.visits = true, 1
        reply.layer = "first"
        fireId(ctx, D.first)
        return finish(ctx, text)
    end
    if state.expect then
        reply.layer = "expect"
        if answerExpect(ctx) then return finish(ctx, text) end
    end
    -- A greeting must not swallow something that matters: "we're closed" as the
    -- first words of a visit still closes the store.
    if firstOfVisit and not best(ctx, function(rule) return (rule.rank or 5) >= 7 end) then
        for _, id in ipairs(D.returns or {}) do
            local rule = D._byId[id]
            if rule and allowed(ctx, rule) and variant(ctx, rule) then
                reply.layer = "return"
                fire(ctx, rule)
                return finish(ctx, text)
            end
        end
    end
    -- Some beats do not wait for an answer. They interrupt, and that is the point.
    if not state.expect then
        local beat = urgentBeat(ctx) or session.sinceBeat >= (D.beatEvery or 4) and nextBeat(ctx)
        if beat and beat.alone and fire(ctx, beat) then
            reply.layer = "spine"
            session.lastNorm = ctx.norm
            return finish(ctx, text)
        end
    end
    -- A rule marked `again` wants the repeat: asking twice is how it gets further.
    if ctx.norm == session.lastNorm and not best(ctx, function(rule) return rule.again end)
        and fireId(ctx, "repeated") then
        reply.layer = "repeat"
        return finish(ctx, text)
    end
    session.lastNorm = ctx.norm
    if looksMashed(tokens) and fireId(ctx, "mash") then
        reply.layer = "mash"
        return finish(ctx, text)
    end
    if string.find(ctx.padded, " my name is ", 1, true) or string.find(ctx.padded, " call me ", 1, true) then
        local name = P.captureName(tokens, ctx.padded)
        if name then
            state.name = name
            if fireId(ctx, "renamed") then
                reply.layer = "rule"
                return finish(ctx, text)
            end
        end
    end
    local rule = best(ctx, function() return true end)
    if rule then
        session.misses = 0
        reply.layer = "rule"
        -- Leaning in is rewarded: "go on" draws out the next thing it has been holding back.
        if rule.pull then
            local beat = nextBeat(ctx)
            if beat and fire(ctx, beat) then
                reply.layer = "spine"
                session.lastNorm = ctx.norm
                return finish(ctx, text)
            end
        end
        -- Saying the same line twice running is what makes a parser feel like one.
        local said = table.concat(variant(ctx, rule) or {}, " ")
        if said == session.lastSaid and fireId(ctx, "repeated") then
            reply.layer = "repeat"
        else
            fire(ctx, rule)
            session.lastSaid = said
        end
        return finish(ctx, text)
    end
    local mirror = reflectRule(ctx)
    if mirror and fire(ctx, mirror) then
        session.misses = 0
        reply.layer = "reflect"
        return finish(ctx, text)
    end
    -- The ladder. Nothing understood must still move the story: this is the rule
    -- that keeps a parser from becoming a wall.
    session.misses = session.misses + 1
    reply.layer = "deflect"
    local beat = session.misses >= 3 and nextBeat(ctx)
    if beat and fire(ctx, beat) then
        reply.layer = "spine"
        session.misses = 0
    elseif session.misses == 2 and #state.memory > 0 and fireId(ctx, "recall") then
        reply.layer = "recall"
    elseif session.misses >= 2 and fireId(ctx, "steer") then
        reply.layer = "steer"
        session.misses = 0
    else
        fireId(ctx, "deflect")
    end
    return finish(ctx, text)
end

-- The machine may speak first only if the player has been sitting in silence.
function P.idle(state, session, seconds, facts)
    local D = indexed(SC.TerminalPersonaData[state.id])
    local id
    if not session.spoke and seconds >= P.IDLE_FIRST_SECONDS and not session.idleFirst then
        id, session.idleFirst = "idle_first", true
    elseif session.spoke and seconds >= P.IDLE_MID_SECONDS and not session.idleMid then
        id, session.idleMid = "idle_mid", true
    end
    if not id then return nil end
    local reply = { rows = {}, effects = {} }
    local ctx = { D = D, state = state, session = session, facts = facts or {}, reply = reply, set = {}, tokens = {}, depth = P.depth(state, facts and facts.hours) }
    if not fireId(ctx, id) then return nil end
    return P.package(D, reply, ctx.depth)
end

-- The lamp's job on a machine with no lamp: say it out loud, once in a while.
function P.threat(state, session, facts, now)
    local threat = facts and facts.threat
    if not threat or not threat.distance or threat.closing ~= true then return nil end
    local id, wait, key
    if threat.distance <= P.THREAT_NEAR then id, wait, key = "threat_near", P.THREAT_NEAR_MS, "threatNearAt"
    elseif threat.distance <= P.THREAT_FAR then id, wait, key = "threat_far", P.THREAT_FAR_MS, "threatFarAt"
    else return nil end
    if session[key] and now - session[key] < wait then return nil end
    session[key] = now
    local D = indexed(SC.TerminalPersonaData[state.id])
    local reply = { rows = {}, effects = {} }
    local ctx = { D = D, state = state, session = session, facts = facts, reply = reply, set = {}, tokens = {}, depth = P.depth(state, facts.hours) }
    if not fireId(ctx, id) then return nil end
    return P.package(D, reply, ctx.depth)
end

-- The caller reports what really happened. A drawer that did not open never
-- gets a line saying it did.
function P.confirmDrawer(state, opened)
    if opened then state.flags.drawer_done = true end
    local D = indexed(SC.TerminalPersonaData[state.id])
    if opened then return nil end
    local reply = { rows = {}, effects = {} }
    local ctx = { D = D, state = state, session = P.session(), facts = {}, reply = reply, set = {}, tokens = {}, depth = P.depth(state) }
    fireId(ctx, "drawer_failed")
    return P.package(D, reply, ctx.depth)
end

-- The screen goes dark mid-sentence. On the next visit the machine notices.
function P.powerCut(state)
    local D = indexed(SC.TerminalPersonaData[state.id])
    state.flags.power_cut = true
    local reply = { rows = {}, effects = {} }
    local ctx = { D = D, state = state, session = P.session(), facts = {}, reply = reply, set = {}, tokens = {}, depth = P.depth(state) }
    fireId(ctx, "power_failed")
    return P.package(D, reply, ctx.depth)
end

function P.rewardItems(state)
    local D = SC.TerminalPersonaData[state.id]
    local out = {}
    for _, name in ipairs(D.items or {}) do out[#out + 1] = name end
    for _, row in ipairs(D.bonus or {}) do
        if state.flags[row.flag] then
            for _, name in ipairs(row.items) do out[#out + 1] = name end
        end
    end
    return out
end

-- ---------------------------------------------------------------------------
-- The Director. One of each in a whole world, and never before the player knows
-- what an ordinary computer looks like.
-- ---------------------------------------------------------------------------

local function random(seed)
    local value = seed
    return function(count)
        value = (value * 48271) % 2147483647
        return value % count + 1
    end
end

-- The research complex west of Rosewood, measured from the map files: 40 computers
-- on floors -13 to -17. Nobody gets there by accident, so nobody leaves disappointed.
function P.isDeepPost(x, y, z)
    return x ~= nil and y ~= nil and z ~= nil and x >= 5400 and x <= 5700 and y >= 12300 and y <= 12600 and z <= -10
end

-- Their stories happen on set dates in July 1993, so none of them can be met
-- before August. On July 11th a machine cannot remember the 19th.
function P.choose(book, kind, brand, seed, hasDrawer, level, deepPost, days)
    local rules = P.DIRECTOR
    level = level or 2
    book.boots = (book.boots or 0) + 1
    book.met = type(book.met) == "table" and book.met or {}
    if days and days < rules.firstDay then return nil end
    if deepPost and level ~= 1 and hasDrawer and not book.met.duty and SC.TerminalPersonaData.duty then
        book.met.duty = true
        book.lastAt = book.boots
        return "duty"
    end
    if level == 1 or not hasDrawer or book.boots <= rules.tour then return nil end
    local since = book.boots - (book.lastAt or 0)
    if book.lastAt and since < rules.gap then return nil end
    local home, stray = rules.home, rules.stray
    if since >= rules.pityAfter then home, stray = rules.pityHome, rules.pityStray end
    if level == 3 then home, stray = home * 2, stray * 2 end
    local pick = random((seed % 2147483646) + 1)
    pick(1000)
    local matching, wanting = {}, {}
    for _, id in ipairs(P.ORDER) do
        local D = SC.TerminalPersonaData[id]
        if D and not book.met[id] then
            -- A machine whose lines describe its own building stays in that kind of building.
            if not D.brandOnly then wanting[#wanting + 1] = id end
            if D.homes[kind] or (D.brand and D.brand == brand) then matching[#matching + 1] = id end
        end
    end
    local chosen
    if #matching > 0 and pick(1000) <= home then chosen = matching[pick(#matching)]
    elseif #wanting > 0 and (kind == "office" or kind == "general") and pick(1000) <= stray then chosen = wanting[pick(#wanting)] end
    if chosen then
        book.met[chosen] = true
        book.lastAt = book.boots
    end
    return chosen
end

return P
