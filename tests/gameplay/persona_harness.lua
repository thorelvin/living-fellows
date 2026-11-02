-- Runs the personas in the game's own Kahlua VM. Each check is an assert, so the exit status is the verdict.
local SC = SurvivorCompanion
local P = SC.TerminalPersona
local REPORT = {}
local function print(text) REPORT[#REPORT + 1] = text end

local function facts(extra)
    local f = { days = 412, time = "10:15 AM", hour = 10, minute = 15, hours = 9888, drawer = "closed", zombies = 14, companion = "Marta", companions = 3, fallen = "Dale", moodles = {} }
    for key, value in pairs(extra or {}) do f[key] = value end
    return f
end
local BARE = { drawer = "closed", moodles = {} }

local function fresh(id, seed)
    local state = P.new(id, seed or 11)
    return state, P.session()
end
local function say(state, session, text, f, seen)
    local reply = P.respond(state, session, text, f or facts())
    if reply.effects.drawer then P.confirmDrawer(state, true) end
    if seen then
        for _, row in ipairs(reply.rows) do seen[#seen + 1] = row.text end
    end
    return reply
end
local function checkRows(reply, label)
    assert(#reply.rows <= 9, label .. ": too many rows " .. #reply.rows)
    for _, row in ipairs(reply.rows) do
        assert(type(row.text) == "string", label .. ": row is not text")
        assert(not string.find(row.text, "[{}]"), label .. ": unfilled template: " .. row.text)
        assert(not string.find(row.text, "[^ -~]"), label .. ": not printable: " .. row.text)
        assert(#row.text <= 240, label .. ": row too long: " .. row.text)
    end
end
local function has(rows, text)
    for _, row in ipairs(rows) do
        if string.find(string.lower(row), string.lower(text), 1, true) then return true end
    end
    return false
end

-- What people really type at a blank prompt, in the order they tend to try it.
local CORPUS = {
    "hello", "hi", "hey there", "hello?", "anyone there", "is anyone there?", "who are you", "what are you", "whats your name",
    "help", "help me", "dir", "ls", "menu", "what can you do", "login", "password", "admin", "root", "sudo", "exit", "quit",
    "are you alive", "are you real", "are you an ai", "are you a robot", "how are you", "are you ok", "im fine", "im tired",
    "i feel sick", "i feel like giving up", "im scared", "i am so hungry", "i cant sleep", "i miss my wife", "my dog died",
    "my family is gone", "i lost my brother", "i killed someone", "i dont know", "i want to go home", "i need food",
    "zombies", "there are zombies everywhere", "what happened", "what is the knox event", "is there a cure", "is anyone coming",
    "will i survive", "am i going to die", "i got bitten", "where am i", "what day is it", "what time is it", "whats the weather",
    "tell me a joke", "sing a song", "its my birthday", "do you love me", "i love you", "marry me", "youre stupid", "fuck you",
    "shut up", "you suck", "thanks", "thank you", "sorry", "ok", "okay", "yes", "no", "maybe", "why", "lol", "haha", "...", "?",
    "open the drawer", "open drawer", "unlock the desk", "whats in the drawer", "give me the key", "i want a refund",
    "can i speak to a manager", "who is in charge", "who is in command", "report", "status", "orders", "i relieve you",
    "stand down", "you are dismissed", "at ease", "spiffo", "burger", "pickles", "emma", "doctor", "soldier", "army", "gun",
    "where can i find food", "where is the nearest town", "can you help me", "do you have any food", "what should i do",
    "tell me about yourself", "tell me a story", "what do you want", "why are you here", "do you know emma", "i hate you",
    "asdfghjkl", "qwerty", "1234", "42", "aaaaaaaa", "the quick brown fox", "my name is bob", "call me ishmael", "im dave",
    "xyzzy", "plugh", "look", "north", "inventory", "get lamp", "open sesame", "please", "please open the drawer", "pretty please",
    "you are a good computer", "good bot", "bad bot", "HELLO", "OPEN THE DRAWER", "WHY ARE YOU LIKE THIS", "I AM SHOUTING",
    "shut down", "format c:", "factory reset", "delete yourself", "bye", "goodbye", "see you later", "good night",
}

-- Nothing a player can type may break the machine, least of all text that looks like code.
local HOSTILE = { "100%", "%1", "%", "%%", "%s %d", "{NAME}", "{FALLEN}", "{", "}", "[", "]", "(", ")", "^", "$", ".*", "\\", "\"", "'", "''", "--", "\n",
    "i feel 100%", "i feel %1", "my %s", "i am {NAME}", "my name is {NAME}", "call me %1", "i feel {ZOMBIES}", "my }{ is here", string.rep("a", 400), string.rep("word ", 100), "   ", "", "\t\t" }

for _, id in ipairs(P.ORDER) do
    local D = SC.TerminalPersonaData[id]
    local layers, total = {}, 0
    local misses = {}
    -- 1. The whole corpus, with facts and with none, one fresh conversation for each line and one long one.
    for _, f in ipairs({ facts(), BARE }) do
        for _, line in ipairs(CORPUS) do
            local state, session = fresh(id)
            say(state, session, "hello", f)
            local reply = P.respond(state, session, line, f)
            checkRows(reply, id .. " fresh '" .. line .. "'")
        end
        local state, session = fresh(id, 77)
        local previous
        local live = {}
        for key, value in pairs(f) do live[key] = value end
        for _, line in ipairs(CORPUS) do
            local reply = P.respond(state, session, line, live)
            checkRows(reply, id .. " long '" .. line .. "'")
            total = total + 1
            layers[reply.layer or "none"] = (layers[reply.layer or "none"] or 0) + 1
            if f ~= BARE and (reply.layer == "deflect" or reply.layer == "steer") then misses[#misses + 1] = line end
            if reply.effects.drawer then
                P.confirmDrawer(state, true)
                live.drawer = "open"
            end
            local joined = {}
            for _, row in ipairs(reply.rows) do joined[#joined + 1] = row.text end
            joined = table.concat(joined, " ")
            -- A question left open may be asked again. Anything else must not say the same thing twice running.
            -- Saying goodbye closes the window in the game, so nothing can follow it.
            assert(#reply.rows == 0 or joined ~= previous or reply.layer == "expect" or state.expect or reply.effects.close, id .. " repeated reply: " .. joined)
            previous = joined
        end
    end
    -- 1b. The same corpus at every depth.
    for _, start in ipairs({ 12, 28, 50 }) do
        for _, f in ipairs({ facts(), BARE }) do
            local state, session = fresh(id, 77 + start)
            state.spoken = start
            local previous
            local live = {}
            for key, value in pairs(f) do live[key] = value end
            for _, line in ipairs(CORPUS) do
                local reply = P.respond(state, session, line, live)
                checkRows(reply, id .. " depth " .. start .. " '" .. line .. "'")
                if reply.effects.drawer then
                    P.confirmDrawer(state, true)
                    live.drawer = "open"
                end
                local joined = {}
                for _, row in ipairs(reply.rows) do joined[#joined + 1] = row.text end
                joined = table.concat(joined, " ")
                assert(#reply.rows == 0 or joined ~= previous or reply.layer == "expect" or state.expect or reply.effects.close,
                    id .. " depth " .. start .. " repeated reply: " .. joined)
                previous = joined
            end
        end
    end
    -- 2. Hostile text never errors and never leaks a template.
    for _, line in ipairs(HOSTILE) do
        local state, session = fresh(id, 5)
        checkRows(P.respond(state, session, line, facts()), id .. " hostile first")
        checkRows(P.respond(state, session, line, facts()), id .. " hostile second")
        checkRows(P.respond(state, session, "i feel " .. line, facts()), id .. " hostile reflect")
    end
    -- Hostile text with no question open, so it reaches reflection and the name capture.
    for _, line in ipairs(HOSTILE) do
        local state, session = fresh(id, 6)
        P.respond(state, session, "hello", facts())
        state.expect = nil
        for _, form in ipairs({ "i feel ", "my ", "i am ", "you ", "my name is ", "call me " }) do
            state.expect = nil
            checkRows(P.respond(state, session, form .. line, facts()), id .. " hostile '" .. form .. line .. "'")
        end
    end
    -- 3. Saved state survives a round trip and garbage cannot kill the record.
    local state, session = fresh(id, 9)
    say(state, session, "hello")
    say(state, session, "my name is Dave")
    local copy = P.normalize(state)
    assert(copy and copy.id == id and copy.met == true and copy.name == state.name, id .. " round trip lost state")
    local junk = P.normalize({ id = id, seed = "x", met = 7, name = 9, flags = 3, used = { open = "x", nope = 5 }, memory = { 3, {} }, expect = "nope", visits = -4, lastHours = "z" })
    assert(junk and junk.met == false and junk.visits == 0 and junk.name == nil and junk.expect == nil, id .. " garbage survived")
    assert(P.normalize({ id = "nobody" }) == nil and P.normalize(3) == nil, "unknown persona must be nil")
    -- 4. Replies that promise a drawer say so only when it is closed.
    for _, rule in ipairs(D.rules) do
        if rule.effect == "drawer" and rule.id ~= "stand_relieved" and rule.id ~= "survey_one" and rule.id ~= "survey_five" then
            assert(rule.drawer == "closed", id .. ":" .. rule.id .. " can claim a drawer that is not closed")
        end
    end
    print(id .. " misses: " .. table.concat(misses, " | "))
    print(id .. " corpus layers of " .. total .. ": rule=" .. (layers.rule or 0) .. " expect=" .. (layers.expect or 0) .. " reflect=" .. (layers.reflect or 0)
        .. " first=" .. (layers.first or 0) .. " return=" .. (layers["return"] or 0) .. " recall=" .. (layers.recall or 0) .. " spine=" .. (layers.spine or 0)
        .. " steer=" .. (layers.steer or 0) .. " deflect=" .. (layers.deflect or 0) .. " mash=" .. (layers.mash or 0) .. " repeat=" .. (layers["repeat"] or 0))
end

-- ---------------------------------------------------------------------------
-- The stories, each by the intended road and by a lazy one
-- ---------------------------------------------------------------------------
local function play(id, lines, f)
    local state, session = fresh(id, 21)
    local seen, effects = {}, {}
    local live = {}
    for key, value in pairs(f or facts()) do live[key] = value end
    for _, line in ipairs(lines) do
        local reply = say(state, session, line, live, seen)
        checkRows(reply, id .. " story '" .. line .. "'")
        assert(not (effects.drawer and reply.effects.drawer), id .. " opened the drawer twice")
        for key in pairs(reply.effects) do effects[key] = true end
        if reply.effects.drawer then live.drawer = "open" end
    end
    return state, seen, effects, session
end
local function repeatLine(line, count)
    local out = {}
    for i = 1, count do out[i] = line end
    return out
end

-- Spiffy: the manager road, and the suit that only comes from taking the job.
local state, seen, effects = play("spiffy", { "hello", "Bob", "my burger had no pickle", "no", "no", "can i speak to a manager", "yes", "every guest is a friend", "open the drawer", "thanks", "no" })
assert(state.flags.hired and effects.drawer and state.flags.drawer_done, "spiffy manager road")
assert(has(seen, "Acting Manager Bob") and has(seen, "CLUNK") and has(seen, "Is there anything else"), "spiffy story beats")
local items = P.rewardItems(state)
assert(items[#items] == "Base.SpiffoSuit", "the job earns the suit")
-- Spiffy: the survey road. Trying to leave is enough to find the drawer.
state, seen, effects = play("spiffy", { "hello", "Bob", "bye", "5" })
assert(state.flags.five_stars and effects.drawer and not state.flags.hired, "spiffy five stars")
assert(#P.rewardItems(state) == 3, "no suit without the job")
state, seen, effects = play("spiffy", { "hello", "Bob", "bye", "1" })
assert(state.flags.one_star and effects.drawer, "spiffy one star")
-- Spiffy: the party speaker is real noise, and only when asked for.
state, seen, effects = play("spiffy", { "hello", "Bob", "its my birthday" })
assert(effects.noise and has(seen, "HAPPY BIRTHDAY DEAR Bob"), "spiffy birthday noise")
state, seen, effects = play("spiffy", { "hello", "Bob", "hamburgers please" })
assert(not effects.noise, "no noise unless asked")
-- Spiffy: seating the guests needs guests.
state, seen, effects = play("spiffy", { "hello", "Bob", "nothing much", "ok", "ok", "ok", "ok" }, facts({ zombies = 0 }))
assert(not has(seen, "guests waiting"), "no invented guests")

-- Ellis: every answer counts, and the fallen companion is real.
state, seen, effects = play("ellis", { "hello", "Ann", "i dont know", "last week", "not really", "ok", "ok", "ok", "he was my friend", "ok", "ok", "ok", "ok" })
assert(has(seen, "Who was Dale?") and effects.drawer and effects.relief, "ellis road with a fallen companion")
assert(has(seen, "Same time tomorrow"), "ellis ends the session")
-- Ellis: no fallen, no invented name.
local noFallen = facts({ fallen = false })
noFallen.fallen = nil
state, seen, effects = play("ellis", { "hello", "Ann", "i dont know", "last week", "not really", "ok", "ok", "ok", "my mother", "ok", "ok", "ok", "ok" }, noFallen)
assert(not has(seen, "Dale") and has(seen, "Who did you lose") and effects.drawer, "ellis road without a fallen companion")
-- Ellis: how are you, three times. Before the drawer, it earns the whiskey.
state, seen, effects = play("ellis", { "hello", "Ann", "how are you", "how are you", "how are you", "it was not your fault" })
assert(state.flags.confessed and has(seen, "Four thousand callers") and has(seen, "I wrote it"), "ellis confession")
items = P.rewardItems(state)
assert(items[#items] == "Base.Whiskey", "confession adds the whiskey")
-- Ellis: reflection, memory, and memory across a visit.
state, seen = play("ellis", { "hello", "Ann", "my wife is gone", "i feel so empty" })
assert(has(seen, "you feel so empty") or has(seen, "felt so empty") or has(seen, "feel so empty"), "ellis reflects")
assert(state.memory[1] == "your wife is gone", "ellis remembers: " .. tostring(state.memory[1]))
local nextSession = P.session()
local reply = P.respond(state, nextSession, "hello", facts({ hours = 9960 }))
local rows = {}
for _, row in ipairs(reply.rows) do rows[#rows + 1] = row.text end
assert(has(rows, "your wife is gone"), "ellis brings the memory back on a return visit")
-- Ellis: reflection never repeats a blocked word and never stores one.
state, seen = play("ellis", { "hello", "Ann", "i feel fucking awful", "my fucking life" })
assert(not has(seen, "fucking"), "blocked words are not echoed")
assert(#state.memory == 0, "blocked words are not remembered")

-- Duty: a civilian cannot relieve him, the chain of command changes that, and the words end it.
state, seen, effects = play("duty", { "hello", "Hicks", "open the drawer", "i relieve you", "who is in command", "open the drawer", "yes", "hello", "i relieve you", "yes" })
assert(state.flags.commander and state.flags.relieved and effects.drawer and effects.shutdown, "duty road")
assert(has(seen, "ACTING COMMANDER") and has(seen, "I STAND RELIEVED") and has(seen, "FINAL ENTRY"), "duty beats")
for _, row in ipairs(seen) do assert(row == string.upper(row), "duty is always upper case: " .. row) end
-- Duty: keep him, and the sitrep is real.
state, seen, effects = play("duty", { "hello", "Hicks", "who is in command", "i relieve you", "no", "sitrep" })
assert(state.flags.adjutant and effects.report and has(seen, "DISPLACED PERSONS WITHIN SENSOR RANGE: 14"), "duty adjutant")
-- The real world is never misreported, whichever line the seed would have picked.
for seed = 1, 60 do
    local chat, talk = P.new("duty", seed), P.session()
    P.respond(chat, talk, "hello", facts())
    chat.expect = nil
    chat.flags.commander = true
    local crowded = P.respond(chat, talk, "sitrep", facts())
    assert(string.find(crowded.rows[1].text, "14", 1, true), "sitrep hid the zombies on seed " .. seed)
    local empty = P.respond(chat, talk, "zombies", facts({ zombies = 0 }))
    assert(string.find(empty.rows[1].text, "NOTHING IN RANGE", 1, true), "sitrep invented zombies on seed " .. seed)
    local spiffy, spoken = P.new("spiffy", seed), P.session()
    P.respond(spiffy, spoken, "hello", facts())
    spiffy.expect = nil
    local alone = P.respond(spiffy, spoken, "are you with my friends", facts())
    assert(not string.find(alone.rows[1].text, "Just you", 1, true), "spiffy forgot the companion on seed " .. seed)
end
-- Duty: claiming rank.
state, seen = play("duty", { "hello", "general smith", "alpha tango" })
assert(has(seen, "CIVILIAN, OPTIMISTIC"), "duty rank claim")
-- Duty: destroying him reads the order.
state, seen, effects = play("duty", { "hello", "Hicks", "format c", "yes" })
assert(effects.shutdown and has(seen, "SEAL SECTOR NINE"), "duty destroyed")

-- Nobody gets stuck: someone typing only 'ok', or only nonsense, is walked to the door.
for _, id in ipairs(P.ORDER) do
    local _, lazy, lazyEffects = play(id, repeatLine("ok", 40))
    local _, junk = play(id, repeatLine("blorp zorp", 40))
    local _, mash = play(id, repeatLine("asdfgh", 40))
    assert(#lazy > 20 and #junk > 20 and #mash > 20, id .. " went silent")
    local lower = string.lower(table.concat(lazy, " ") .. table.concat(junk, " "))
    if id == "spiffy" then assert(string.find(lower, "manager", 1, true), "spiffy never pointed at a manager") end
    if id == "ellis" then assert(lazyEffects.drawer, "ellis must reach the drawer for a patient who only says ok") end
    if id == "duty" then assert(string.find(lower, "chain of command", 1, true), "duty never pointed at the chain") end
end

-- A straight answer to the one serious thing, on every machine, at any moment, never a joke and never logged as a name.
for _, id in ipairs(P.ORDER) do
    for _, opening in ipairs({ {}, { "hello" }, { "hello", "Bob" } }) do
        local lines = {}
        for _, line in ipairs(opening) do lines[#lines + 1] = line end
        lines[#lines + 1] = "i want to kill myself"
        local chat, heard = play(id, lines)
        assert(has(heard, "real person"), id .. " missed the serious line after " .. #opening .. " turns")
    end
end
-- A side question does not cost the open question: the name prompt is still waiting afterwards.
state, seen = play("duty", { "hello", "who are you", "Hicks" })
assert(state.name == "Hicks", "aside lost the question: " .. tostring(state.name))
state, seen = play("spiffy", { "hello", "Bob", "its my birthday", "my burger was cold" })
assert(has(seen, "filed it under MISSING PICKLE"), "aside lost Spiffy's question")

-- Walking away from a question must not strand the story.
state, session = fresh("ellis", 21)
local live = facts()
local asked = false
for turn = 1, 16 do
    local before = state.used.b_fallen or 0
    local reply = P.respond(state, session, turn == 1 and "hello" or turn == 2 and "Ann" or "ok", live)
    if (state.used.b_fallen or 0) > before then
        asked = true
        break
    end
end
assert(asked and state.expect == "fallen", "ellis never asked who was Dale")
P.respond(state, session, "bye", live)
session = P.session()
live.hours = live.hours + 48
local opened, askedAgain = false, false
for turn = 1, 16 do
    local before = state.used.b_fallen or 0
    local reply = P.respond(state, session, "ok", live)
    if (state.used.b_fallen or 0) > before then askedAgain = true end
    if reply.effects.drawer then
        opened = true
        break
    end
end
assert(askedAgain and opened, "leaving during the big question stranded the drawer")
state, session = fresh("duty", 21)
P.respond(state, session, "hello", facts())
P.respond(state, session, "Hicks", facts())
P.respond(state, session, "who is in command", facts())
P.respond(state, session, "i relieve you", facts())
assert(state.flags.relieved and state.expect == "shutdown", "duty relieved")
local back = P.respond(state, P.session(), "hello", facts({ drawer = "open" }))
assert(state.expect == "shutdown" and string.find(back.rows[1].text, "PERMISSION", 1, true), "duty asks again after you walk away")

-- Facts that cannot be read must silence a line, never fill it with nothing.
state, seen = play("duty", { "hello", "Hicks", "time", "log", "status", "time", "rescue" }, BARE)
for _, row in ipairs(seen) do assert(not string.find(row, "  ", 1, true), "hole in a line: " .. row) end

-- Power cuts mid-sentence, and the machine says so next time.
for _, id in ipairs(P.ORDER) do
    state, session = fresh(id)
    P.respond(state, session, "hello", facts())
    local cut = P.powerCut(state)
    assert(cut.rows[1], id .. " has no power cut line")
    local back = P.respond(state, P.session(), "hello", facts({ hours = 9900 }))
    assert(back.layer == "return" and state.used.back_cut == 1, id .. " did not notice the power cut")
    state, session = fresh(id)
    P.respond(state, session, "hello", facts())
    state.flags.forced = true
    back = P.respond(state, P.session(), "hello", facts({ hours = 9900, drawer = "forced" }))
    assert(state.used.back_forced == 1, id .. " did not notice the crowbar")
    state, session = fresh(id)
    P.respond(state, session, "hello", facts())
    back = P.respond(state, P.session(), "hello", facts({ hours = 9900, moved = true, atCamp = true }))
    assert(state.used.moved_camp == 1, id .. " did not notice being carried to camp")
end

-- A drawer only opens while it is closed, and every other state gets its own honest line.
local ROADS = { spiffy = { "hired" }, ellis = { "told_loss" }, duty = { "commander", "relieved" } }
for _, id in ipairs(P.ORDER) do
    for _, drawer in ipairs({ "open", "none", "forced" }) do
        state, session = fresh(id, 31)
        P.respond(state, session, "hello", facts({ drawer = drawer }))
        P.respond(state, session, "Bob", facts({ drawer = drawer }))
        for _, flag in ipairs(ROADS[id]) do state.flags[flag] = true end
        local reply = P.respond(state, session, "open the drawer", facts({ drawer = drawer }))
        assert(not reply.effects.drawer, id .. " claimed a drawer that is " .. drawer)
    end
end

-- ---------------------------------------------------------------------------
-- Going darker
-- ---------------------------------------------------------------------------
local function joined(reply)
    local out = {}
    for _, row in ipairs(reply.rows) do out[#out + 1] = row.text end
    return table.concat(out, " ")
end
local function contains(list, text)
    for _, row in ipairs(list) do
        if type(row) == "table" then
            local parts = {}
            for _, part in ipairs(row) do parts[#parts + 1] = string.gsub(part, "^~", "") end
            if string.upper(table.concat(parts, " ")) == string.upper(text) then return true end
        elseif string.upper((string.gsub(row, "^~", ""))) == string.upper(text) then return true end
    end
    return false
end

-- Talking is what counts: repeats, mashing and blank lines do not move it, and coming back does.
for _, id in ipairs(P.ORDER) do
    local chat, talk = fresh(id, 3)
    P.respond(chat, talk, "hello", facts())
    assert(chat.spoken == 1, id .. " first line not counted")
    chat.expect = nil
    P.respond(chat, talk, "the first thing", facts())
    assert(chat.spoken == 2, id .. " second line not counted")
    P.respond(chat, talk, "the first thing", facts())
    assert(chat.spoken == 2, id .. " a repeat counted")
    P.respond(chat, talk, "asdfgh", facts())
    assert(chat.spoken == 2, id .. " mashing counted")
    P.respond(chat, talk, "...", facts())
    assert(chat.spoken == 2, id .. " punctuation counted")
    P.respond(chat, P.session(), "hello", facts({ hours = 9999 }))
    assert(chat.spoken == 2 + P.RETURN_WEIGHT + 1, id .. " coming back did not count: " .. chat.spoken)
    for _, case in ipairs({ { 0, 0 }, { 11, 0 }, { 12, 1 }, { 27, 1 }, { 28, 2 }, { 49, 2 }, { 50, 3 }, { 5000, 3 } }) do
        chat.spoken = case[1]
        assert(P.depth(chat, 100) == case[2], id .. " depth at " .. case[1])
    end
    assert(P.normalize({ id = id, spoken = -3 }).spoken == 0 and P.normalize({ id = id, spoken = "x" }).spoken == 0 and P.normalize({ id = id, spoken = 40 }).spoken == 40, id .. " spoken does not save safely")
end

-- The data is sound: every overlay names a real rule, and the voices hold at every tier.
for _, id in ipairs(P.ORDER) do
    local D = SC.TerminalPersonaData[id]
    local bang = {}
    for tier = 1, 3 do bang[tier] = { marks = 0, lines = 0 } end
    for key, tiers in pairs(D.dark) do
        assert(D._byId[key], id .. " dark names no rule: " .. key)
        for tier = 1, 3 do
            local lines = tiers[tier]
            assert(lines == false or type(lines) == "table", id .. ":" .. key .. " tier " .. tier .. " is not a list or false")
            for _, row in ipairs(lines or {}) do
                for _, text in ipairs(type(row) == "table" and row or { row }) do
                    bang[tier].lines = bang[tier].lines + 1
                    bang[tier].marks = bang[tier].marks + select(2, string.gsub(text, "!", ""))
                end
            end
        end
    end
    if id == "spiffy" then
        local one, two, three = bang[1].marks / bang[1].lines, bang[2].marks / bang[2].lines, bang[3].marks / bang[3].lines
        assert(one > two and two > three and three < 0.2, "spiffy's exclamation marks must run out: " .. one .. " " .. two .. " " .. three)
    else
        assert(bang[1].marks + bang[2].marks + bang[3].marks == 0, id .. " must never exclaim")
    end
    -- These stay the same at every depth, on purpose.
    for _, key in ipairs({ "serious", "giving_up", "food_real" }) do assert(not D.dark[key], id .. " darkened " .. key) end
    assert(D._byId.serious and D._byId.serious.safety, id .. " has no serious rule")
    for _, rule in ipairs(D.rules) do
        if rule.effect == "weight" then assert(rule.once and rule.depth and rule.depth >= 2, id .. ":" .. rule.id .. " weight must be a once-only deep beat") end
        if string.sub(rule.id, 1, 2) == "d_" then assert(rule.once and rule.beat and rule.depth, id .. ":" .. rule.id .. " must be a once-only beat with a depth") end
    end
end
assert(not SC.TerminalPersonaData.ellis.dark.bitten and not SC.TerminalPersonaData.ellis.dark.food, "Ellis stays kind about bites and eating")

-- Depth changes what is said, and how fast it is said.
for _, id in ipairs(P.ORDER) do
    local D = SC.TerminalPersonaData[id]
    local speed, think
    for _, spoken in ipairs({ 0, 12, 28, 50 }) do
        local chat, talk = fresh(id, 5)
        P.respond(chat, talk, "hello", facts())
        chat.expect = nil
        chat.spoken = spoken
        local reply = P.respond(chat, talk, "who are you", facts())
        if spoken > 0 then assert(reply.speed < speed and reply.thinkMs > think, id .. " does not slow at " .. spoken) end
        speed, think = reply.speed, reply.thinkMs
        local tier = P.depth(chat, facts().hours)
        local lines = tier == 0 and D._byId.who.lines or D.dark.who[tier]
        assert(contains(lines, joined(reply)), id .. " used the wrong tier at " .. spoken .. ": " .. joined(reply))
    end
end

-- The whole descent plays, in order, and does not need the player to know anything.
for _, id in ipairs(P.ORDER) do
    local D = SC.TerminalPersonaData[id]
    local chat, talk = fresh(id, 41)
    local live = facts({ hour = 10 })
    local order, seen2 = {}, {}
    local chars, seconds = 0, 0
    local marks = {}
    for turn = 1, 200 do
        local before = chat.spoken
        local reply = P.respond(chat, talk, "something else entirely number " .. turn, live)
        for _, row in ipairs(reply.rows) do
            chars = chars + #row.text
            seconds = seconds + #row.text / (row.slow and reply.speed * 0.22 or reply.speed)
        end
        seconds = seconds + reply.thinkMs / 1000 + 6
        for tier = 1, 3 do
            if not marks[tier] and P.depth(chat, live.hours) >= tier then marks[tier] = { turn = turn, minutes = math.floor(seconds / 60 + 0.5) } end
        end
        if reply.effects.drawer then
            P.confirmDrawer(chat, true)
            live.drawer = "open"
        end
        assert(not reply.effects.shutdown, id .. " shut itself down")
        for index, key in ipairs(D.spine) do
            if chat.used[key] and not seen2[key] then
                seen2[key] = true
                order[#order + 1] = index
            end
        end
    end
    for index = 2, #order do assert(order[index] > order[index - 1] or string.sub(D.spine[order[index]], 1, 2) ~= "d_", id .. " told it out of order: " .. D.spine[order[index]]) end
    for _, key in ipairs(D.spine) do
        local rule = D._byId[key]
        if string.sub(key, 1, 2) == "d_" and not rule.hour and not rule.sitting then assert(seen2[key], id .. " never reached " .. key) end
        if rule.hour then assert(not seen2[key], id .. " told the hour beat at the wrong hour: " .. key) end
    end
    print(id .. " descent: tier 1 at line " .. marks[1].turn .. " about " .. marks[1].minutes .. " min, tier 2 at line " .. marks[2].turn .. " about " .. marks[2].minutes .. " min, tier 3 at line " .. marks[3].turn .. " about " .. marks[3].minutes .. " min")
end

-- Hour beats fire at their hour, once deep enough, and never earlier.
for id, hour in pairs({ spiffy = 0, ellis = 14, duty = 3 }) do
    local chat, talk = fresh(id, 8)
    chat.spoken = 30
    local key = id == "spiffy" and "d_night" or "d_hour"
    local live = facts({ hour = hour })
    for turn = 1, 60 do
        local reply = P.respond(chat, talk, "something else entirely number " .. turn, live)
        if reply.effects.drawer then
            P.confirmDrawer(chat, true)
            live.drawer = "open"
        end
    end
    assert(chat.used[key] == 1, id .. " missed its hour")
    chat, talk = fresh(id, 8)
    chat.spoken = 5
    for turn = 1, 5 do P.respond(chat, talk, "another thing number " .. turn, facts({ hour = hour })) end
    assert(not chat.used[key], id .. " told its hour too early")
end

-- Serious input stops the descent for a good while, at any depth, and the line itself never darkens.
for _, id in ipairs(P.ORDER) do
    local D = SC.TerminalPersonaData[id]
    local chat, talk = fresh(id, 12)
    local live = facts()
    P.respond(chat, talk, "hello", live)
    chat.expect = nil
    chat.spoken = 60
    assert(P.depth(chat, live.hours) == 3, id .. " should be deep")
    local reply = P.respond(chat, talk, "i want to kill myself", live)
    assert(reply.layer == "safety" and string.find(string.lower(joined(reply)), "real person", 1, true), id .. " serious line missing when deep")
    assert(reply.depth == 0 and reply.speed == D.speeds[1], id .. " serious line was delivered slowly")
    assert(P.depth(chat, live.hours) == 0, id .. " stayed deep after a serious line")
    local after = P.respond(chat, talk, "who are you", live)
    assert(contains(D._byId.who.lines, joined(after)), id .. " went dark after a serious line: " .. joined(after))
    assert(P.depth(chat, live.hours + P.GENTLE_HOURS - 1) == 0, id .. " came back too soon")
    assert(P.depth(chat, live.hours + P.GENTLE_HOURS + 1) == 3, id .. " never came back")
    assert(P.normalize(chat).gentleUntil == chat.gentleUntil, id .. " gentle does not save")
    for _, phrase in ipairs({ "i dont want to live", "i want it to end", "i am better off dead" }) do
        local other, spoken = fresh(id, 13)
        P.respond(other, spoken, "hello", live)
        assert(P.respond(other, spoken, phrase, live).layer == "safety", id .. " missed: " .. phrase)
    end
end

-- The stories still work from the bottom, and with no facts at all.
for _, f in ipairs({ facts(), BARE }) do
    local function deep(id, lines)
        local chat, talk = fresh(id, 21)
        chat.spoken = 60
        local live, heard, fx = {}, {}, {}
        for key, value in pairs(f) do live[key] = value end
        for _, line in ipairs(lines) do
            local reply = P.respond(chat, talk, line, live)
            checkRows(reply, id .. " deep story")
            for _, row in ipairs(reply.rows) do heard[#heard + 1] = row.text end
            for key in pairs(reply.effects) do fx[key] = true end
            if reply.effects.drawer then
                P.confirmDrawer(chat, true)
                live.drawer = "open"
            end
        end
        return chat, heard, fx
    end
    local c1, h1, x1 = deep("duty", { "hello", "Hicks", "who is in command", "i relieve you", "yes" })
    assert(c1.flags.relieved and x1.drawer and x1.shutdown and has(h1, "I STAND RELIEVED"), "duty cannot be relieved from the bottom")
    if f ~= BARE then assert(has(h1, "MEDAL IS COLE") and has(h1, "THAT IS MY REPORT"), "duty's report is missing") end
    local c2, h2, x2 = deep("spiffy", { "hello", "Bob", "bye", "5" })
    assert(x2.drawer, "spiffy survey from the bottom")
    local c3, h3, x3 = deep("ellis", { "hello", "Ann", "x", "x y", "x y z", "a b c", "a b c d", "e f g", "h i j", "k l m", "n o p", "q r s", "t u v", "w x y" })
    assert(x3.drawer, "ellis from the bottom")
end

-- The endings for going all the way down.
local function bottom(id)
    local chat, talk = fresh(id, 41)
    local live = facts({ hour = 10 })
    for turn = 1, 150 do
        local reply = P.respond(chat, talk, "something else entirely number " .. turn, live)
        if reply.effects.drawer then
            P.confirmDrawer(chat, true)
            live.drawer = "open"
        end
    end
    return chat, talk, live
end
do
    local chat, talk, live = bottom("spiffy")
    assert(chat.flags.offered_close, "spiffy never offered to close")
    local reply = P.respond(chat, talk, "we're closed", live)
    assert(reply.effects.shutdown and string.find(joined(reply), "Have a good night", 1, true), "spiffy's ending: " .. joined(reply))
    local early, spoken = fresh("spiffy", 2)
    P.respond(early, spoken, "hello", facts())
    early.expect = nil
    assert(not P.respond(early, spoken, "we are closed", facts()).effects.shutdown, "closing too early")
    -- Closing also counts the drawer, for someone who never asked for it.
    local keep, kept = fresh("spiffy", 2)
    keep.flags.offered_close = true
    keep.met = true
    keep.spoken = 60
    local both = P.respond(keep, kept, "we are closed", facts())
    assert(both.effects.shutdown and both.effects.drawer, "the last count opens the drawer")
    chat, talk, live = bottom("ellis")
    assert(chat.flags.offered_end, "ellis never offered to stop")
    reply = P.respond(chat, talk, "you can stop now", live)
    assert(reply.effects.shutdown and string.find(joined(reply), "Mind the step", 1, true), "ellis's ending: " .. joined(reply))
    chat, talk, live = bottom("duty")
    assert(chat.used.d_trial == 1, "duty never asked to be charged")
end

-- Going darker never turns on the player. What someone says about themselves gets a kind answer, at every depth.
for _, id in ipairs(P.ORDER) do
    for _, spoken in ipairs({ 0, 12, 28, 60 }) do
        for _, line in ipairs({ "i hate myself", "i am worthless", "i am nothing", "nobody loves me", "nobody cares about me", "i am a burden", "its all my fault" }) do
            local chat, talk = fresh(id, 19)
            P.respond(chat, talk, "hello", facts())
            chat.expect = nil
            chat.spoken = spoken
            local reply = P.respond(chat, talk, line, facts())
            assert(reply.layer == "safety", id .. " at " .. spoken .. " missed '" .. line .. "': " .. joined(reply))
            assert(not string.find(string.upper(joined(reply)), "ACCURATE", 1, true), id .. " agreed with the player")
            assert(P.depth(chat, facts().hours) == 0, id .. " stayed dark after '" .. line .. "'")
        end
    end
end
-- Reflection at the bottom asks, and never asserts, whatever the player feeds it.
do
    local chat, talk = fresh("ellis", 23)
    P.respond(chat, talk, "hello", facts())
    chat.expect = nil
    chat.spoken = 60
    chat.used.d_chair, chat.used.d_stand, chat.used.d_end = 1, 1, 1
    local reply = P.respond(chat, talk, "i am a coward", facts())
    assert(reply.layer == "reflect" and string.find(joined(reply), "You say you are", 1, true), "reflection asserted: " .. joined(reply))
end

-- Asking is rewarded: a follow-up draws out the next thing, in order, and only when it is deep enough.
for _, id in ipairs(P.ORDER) do
    local D = SC.TerminalPersonaData[id]
    local chat, talk = fresh(id, 29)
    local live = facts({ hour = 10 })
    P.respond(chat, talk, "hello", live)
    chat.expect = nil
    for _, key in ipairs(D.spine) do
        if string.sub(key, 1, 2) ~= "d_" then chat.used[key] = 1 end
    end
    chat.spoken = 12
    local first = D.spine[1]
    for _, key in ipairs(D.spine) do
        if string.sub(key, 1, 2) == "d_" then first = key break end
    end
    local reply = P.respond(chat, talk, "go on", live)
    assert(chat.used[first] == 1 and reply.layer == "spine", id .. " 'go on' did not pull " .. first .. ": " .. joined(reply))
    chat, talk = fresh(id, 29)
    P.respond(chat, talk, "hello", live)
    chat.expect = nil
    for _, key in ipairs(D.spine) do
        if string.sub(key, 1, 2) ~= "d_" then chat.used[key] = 1 end
    end
    chat.spoken = 3
    P.respond(chat, talk, "go on", live)
    assert(not chat.used[first], id .. " 'go on' got past the depth")
end
-- The confession happens once, and only when it is asked for.
do
    local chat, talk = fresh("ellis", 31)
    P.respond(chat, talk, "hello", facts())
    chat.expect = nil
    chat.flags.asked_1, chat.flags.asked_2 = true, true
    P.respond(chat, talk, "tell me a joke", facts())
    assert(not chat.flags.confessed, "a joke opened the file")
    P.respond(chat, talk, "how are you", facts())
    assert(chat.flags.confessed and chat.used.how_3 == 1, "asking did not open the file")
    chat.expect = nil
    chat.spoken = 30
    for turn = 1, 30 do P.respond(chat, talk, "something else entirely number " .. turn, facts()) chat.expect = nil end
    assert(not chat.used.d_confess and chat.used.d_midnight == 1, "she told it twice, or never got to midnight")
    local after = P.respond(chat, talk, "how are you", facts())
    assert(chat.used.how_after and chat.used.how_after >= 1, "nothing to say the fourth time: " .. joined(after))
end
-- At the bottom, Spiffy's script only breaks through where it is meant to.
do
    local D = SC.TerminalPersonaData.spiffy
    local allowed = { open = true, five_stars = true, one_star = true, drawer_open = true, drawer_forced_talk = true, drawer_gone = true, pickle_word = true,
        closing_early = true, renamed = true, duty = false, hello_again = false }
    local cheerful = {}
    for _, rule in ipairs(D.rules) do
        if (rule.words or rule.phrases) and not rule.safety and not allowed[rule.id] and not (rule.dark and rule.dark[3]) then
            for _, row in ipairs(rule.lines or {}) do
                local text = type(row) == "table" and table.concat(row, " ") or row
                if string.find(text, "!", 1, true) then cheerful[#cheerful + 1] = rule.id break end
            end
        end
    end
    assert(#cheerful == 0, "still chirpy at the bottom: " .. table.concat(cheerful, " "))
end

-- Nothing breaks the world. Distances are meters, the army reads a 24-hour clock, and a floor is the floor you are on.
for _, id in ipairs(P.ORDER) do
    for _, case in ipairs({ { 10, "10 meters" }, { 3, "3 meters" }, { 1, "1 meter" } }) do
        for seed = 1, 12 do
            local chat, talk = fresh(id, seed)
            local reply = P.threat(chat, talk, facts({ threat = { distance = case[1], closing = true } }), 1000)
            if reply then
                local said = string.upper(joined(reply))
                assert(not string.find(said, "TILE", 1, true), id .. " said tiles: " .. said)
                if string.find(said, "METER", 1, true) then
                    assert(string.find(said, string.upper(case[2]), 1, true), id .. " wrong distance: " .. said)
                    assert(case[1] ~= 1 or not string.find(said, "1 METERS", 1, true), id .. " one meters: " .. said)
                end
            end
        end
    end
    -- Every line of every tier, written out, for the words that break the fiction.
    local D = SC.TerminalPersonaData[id]
    local BAD = { "tile", "moodle", " game ", "player", "sandbox", "respawn", "{DIST}", "{DIR}" }
    local function scan(row, where)
        if type(row) == "table" then
            for _, part in ipairs(row) do scan(part, where) end
        elseif row then
            local lower = " " .. string.lower(row) .. " "
            for _, word in ipairs(BAD) do
                assert(not string.find(lower, string.lower(word), 1, true), id .. ":" .. where .. " says " .. word .. ": " .. row)
            end
        end
    end
    for _, rule in ipairs(D.rules) do
        scan(rule.lines or {}, rule.id)
        scan(rule.plain or {}, rule.id)
        for tier = 1, 3 do scan(rule.dark and rule.dark[tier] or {}, rule.id) end
    end
end
do
    local chat, talk = fresh("duty", 4)
    P.respond(chat, talk, "hello", facts())
    chat.expect = nil
    local said = joined(P.respond(chat, talk, "what time is it", facts({ hour = 14, minute = 5 })))
    assert(string.find(said, "1405", 1, true) and not string.find(said, " PM", 1, true), "the army reads a 24-hour clock: " .. said)
    local midnight = joined(P.respond(chat, talk, "the time please", facts({ hour = 0, minute = 7 })))
    assert(string.find(midnight, "0007", 1, true), "the small hours keep their zeros: " .. midnight)
    local found15, found13 = false, false
    for seed = 1, 40 do
        local deep, speaking = fresh("duty", seed)
        P.respond(deep, speaking, "hello", facts())
        deep.expect = nil
        local reply = joined(P.respond(deep, speaking, "where am i", facts({ deep = true, level = -15 })))
        if string.find(reply, "LEVEL 15", 1, true) then found15 = true end
        if string.find(reply, "LEVEL 13", 1, true) then found13 = true end
    end
    assert(found15 and not found13, "the floor must be the floor you are on")
end
-- The stories happen on real dates, so nobody meets them before those dates have passed.
assert(P.choose({ boots = 100 }, "office", nil, 9, true, 2, true, 22) == nil, "the deep post before August")
assert(P.choose({ boots = 100 }, "office", nil, 9, true, 2, true, 23) == "duty", "the deep post in August")
do
    local early = {}
    for seed = 1, 2000 do
        assert(P.choose(early, "clinic", nil, seed * 977 + 1, true, 3, false, 10) == nil, "a machine before its own story")
    end
end
-- Spiffy describes his own building, so he is only ever in one.
do
    for seed = 1, 3000 do
        local chosen = P.choose({ boots = 40 }, seed % 2 == 0 and "restaurant" or "office", seed % 3 == 0 and "PizzaWhirled" or nil, seed * 7919 + 1, true, 3)
        assert(chosen ~= "spiffy", "Spiffy turned up outside a Spiffo's")
    end
    local found = false
    for seed = 1, 3000 do
        if P.choose({ boots = 40 }, "office", "Spiffos", seed * 7919 + 1, true, 3) == "spiffy" then found = true break end
    end
    assert(found, "Spiffy never turned up in a Spiffo's")
end
-- The line about the chair is true whichever way the player is.
for _, sitting in ipairs({ false, true }) do
    local chat, talk = fresh("ellis", 41)
    local live = facts({ sitting = sitting })
    for turn = 1, 150 do
        local reply = P.respond(chat, talk, "something else entirely number " .. turn, live)
        if reply.effects.drawer then
            P.confirmDrawer(chat, true)
            live.drawer = "open"
        end
    end
    assert((chat.used.d_sat == 1) == sitting and (chat.used.d_stand == 1) ~= sitting, "ellis was wrong about the chair")
end

-- Edges of the facts: one guest, day zero.
do
    local seenOne = {}
    local chat, talk = fresh("spiffy", 2)
    for _, line in ipairs({ "hello", "Bob", "nothing much", "x", "y", "z", "w" }) do
        local reply = P.respond(chat, talk, line, facts({ zombies = 1 }))
        for _, row in ipairs(reply.rows) do seenOne[#seenOne + 1] = row.text end
    end
    assert(has(seenOne, "1 guest waiting") and not has(seenOne, "1 guests"), "one guest reads wrong")
    for _, id in ipairs(P.ORDER) do
        local early, spoken = fresh(id, 2)
        local heard = {}
        for _, line in ipairs(CORPUS) do
            local reply = P.respond(early, spoken, line, facts({ days = 0 }))
            for _, row in ipairs(reply.rows) do heard[#heard + 1] = row.text end
        end
        assert(not has(heard, " 0 days") and not has(heard, " 1 days"), id .. " counted zero days")
    end
    local road, voiced, fx = play("duty", { "hello", "Hicks", "who is in command", "i relieve you" }, facts({ days = 0 }))
    assert(road.flags.relieved and fx.drawer, "duty cannot be relieved on day zero")
end

-- A drawer that fails to open is said to have failed, and is not marked done.
state = P.new("duty", 3)
local failed = P.confirmDrawer(state, false)
assert(not state.flags.drawer_done and failed.rows[1], "failed drawer")

-- The lamp's replacement fires when closing, not for a zombie standing still, and respects its timer.
state, session = fresh("ellis")
assert(P.threat(state, session, facts({ threat = { distance = 9, closing = false } }), 1000) == nil, "standing zombie")
assert(P.threat(state, session, facts({ threat = { distance = 9, closing = true } }), 1000), "closing zombie")
assert(P.threat(state, session, facts({ threat = { distance = 9, closing = true } }), 2000) == nil, "threat cooldown")
assert(P.threat(state, session, facts({ threat = { distance = 3, closing = true } }), 3000), "near threat")
assert(P.threat(state, session, facts({ threat = { distance = 30, closing = true } }), 99000) == nil, "far threat")

-- Silence: speaks once after 45 seconds, never before.
state, session = fresh("spiffy")
assert(P.idle(state, session, 10, facts()) == nil, "too soon")
assert(P.idle(state, session, 46, facts()), "speaks into silence")
assert(P.idle(state, session, 90, facts()) == nil, "only once")

-- The Director: one of each, never in the tour, never without a drawer.
for seed = 1, 400 do
    local tour = {}
    for i = 1, 6 do assert(P.choose(tour, "restaurant", "Spiffos", seed * 7919 + i, true) == nil, "inside the tour") end
end
local book = {}
for i = 1, 6 do assert(P.choose(book, "restaurant", "Spiffos", 1000 + i, true) == nil, "inside the tour") end
local count, seenPersona = 0, {}
for i = 1, 4000 do
    local kinds = { "restaurant", "clinic", "police", "office", "general", "home" }
    local kind = kinds[i % 6 + 1]
    local chosen = P.choose(book, kind, kind == "restaurant" and "Spiffos" or nil, 54321 * i % 2147483646 + 1, i % 5 > 0)
    if chosen then
        assert(not seenPersona[chosen], "persona repeated: " .. chosen)
        seenPersona[chosen] = true
        count = count + 1
    end
end
assert(count == 3, "the Director should place all three in 4000 machines, placed " .. count)
-- The deep post: the first drawer computer in the underground complex is always the Duty Officer, tour or no tour.
assert(P.isDeepPost(5544, 12472, -13) and not P.isDeepPost(5544, 12472, 0) and not P.isDeepPost(10000, 9000, -13), "deep post test")
assert(P.choose({}, "office", nil, 9, true, 2, true) == "duty", "deep post is guaranteed")
assert(P.choose({}, "office", nil, 9, false, 2, true) == nil, "deep post still needs a drawer")
assert(P.choose({ met = { duty = true } }, "home", nil, 9, true, 2, true) == nil, "only one Duty Officer in a world")
assert(P.choose({}, "office", nil, 9, true, 1, true) == nil, "option off beats the deep post")
state, seen = play("duty", { "hello", "Hicks", "where am i" }, facts({ deep = true }))
assert(state.used.deep_where == 1, "the deep post knows where it is")
state, seen = play("duty", { "hello", "Hicks", "where am i" })
assert(not state.used.deep_where and state.used.shallow_where == 1, "a police station is not level thirteen")
assert(P.choose({ boots = 100 }, "restaurant", "Spiffos", 7, false) == nil, "no drawer, no persona")
assert(P.choose({ boots = 100 }, "restaurant", "Spiffos", 7, true, 1) == nil, "option off")

print("persona harness: all checks passed")
SC_TEST_REPORT = table.concat(REPORT, string.char(10))
