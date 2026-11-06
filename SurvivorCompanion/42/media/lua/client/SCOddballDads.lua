-- SPDX-License-Identifier: MIT
-- Gary Ledford and Ron Pettit sent their families out on the evacuation buses
-- and stayed behind in Ron's living room. They have been trading dad jokes
-- ever since and are tied, forty-one to forty-one. The player judges a best
-- of five. Every joke is two spoken beats with a rival's groan after it; the
-- standings live on a real notebook page and the prize is a real beer.

local SC = SurvivorCompanion
SC.OddballDads = SC.OddballDads or {}
local Dads = SC.OddballDads

local ID = "dad_joke_feud"
local NEAR_DISTANCE = 10
local MENU_DISTANCE = 6
local STARTING_SCORE = 41
local ROUNDS_TO_WIN = 3
local SETUP_TO_PUNCH_MS = 3500
local PUNCH_TO_GROAN_MS = 2500
local BETWEEN_JOKES_MS = 5000
local PROMPT_GAP_MS = 25000
local PROMPTS_BEFORE_MOVING_ON = 3
local EXHIBITION_GAP_MS = 70000
local QUEUED_LINE_GAP_MS = 2500

local JOKES = {
    gary = {
        { "I'm reading a book about anti-gravity.", "Can't put it down." },
        { "Why did the golfer bring two pairs of pants?", "In case he got a hole in one." },
        { "Did you hear about the restaurant on the moon?", "Great food. No atmosphere." },
        { "What do you call a fake noodle?", "An impasta." },
        { "Why did the scarecrow get promoted?", "He was outstanding in his field." },
        { "I'm afraid of the calendar.", "Its days are numbered." },
        { "What do you call a boomerang that won't come back?", "A stick." },
        { "What did the ocean say to the beach?", "Nothing. It just waved." },
        { "I used to be a banker.", "Then I lost interest." },
        { "Why did the cookie go to the doctor?", "It felt crummy." },
        { "What has more letters than the alphabet?", "The post office." },
        { "How do you make an octopus laugh?", "Ten-tickles." },
        { "What do you call a pig that does karate?", "A pork chop." },
        { "What did one wall say to the other wall?", "Meet you at the corner." },
        { "I gave away all my dead batteries.", "Free of charge." },
        { "What do you call an alligator in a vest?", "An investigator." },
        { "I named my horse Mayo.", "Mayo neighs." },
        { "Want to hear a construction joke?", "Hold on. I'm still working on it." },
        { "I used to hate facial hair.", "Then it grew on me." },
        { "What do you call a bear with no teeth?", "A gummy bear." },
        { "What's the best thing about Switzerland?", "Don't know. The flag's a big plus." },
        { "What do you call a dog magician?", "A labracadabrador." },
        { "I tried to catch some fog this morning.", "I mist." },
        { "What do you call a snake that builds houses?", "A boa constructor." },
        { "Why do cows wear bells?", "Their horns don't work." },
        { "I kept wondering why the ball was getting bigger.", "Then it hit me." },
        { "What do you call a man with a rubber toe?", "Roberto." },
        { "What do you call a factory that makes okay products?", "A satisfactory." },
        { "My boy used to say, Dad, I'm hungry.", "I'd say, Hi Hungry, I'm Dad. He moved to Ohio." },
        { "I only know twenty-five letters of the alphabet.", "I don't know Y." },
        { "How do you find Will Smith in the snow?", "Follow the fresh prints." },
        { "I'm on a seafood diet.", "I see food, I eat it. Not lately, but in principle." },
        { "What do you call a zombie who tells jokes?", "A dead-pan." },
        { "Why don't the dead eat clowns?", "They taste funny." },
        { "What do the dead take for a cold?", "Coffin drops." },
        { "Ron asked if I got a haircut.", "No, Ron. I got them all cut." },
        { "Where do you learn to make ice cream?", "Sundae school." },
        { "Why did the man put his money in the freezer?", "He wanted cold hard cash." },
    },
    ron = {
        { "Why don't skeletons fight each other?", "They don't have the guts." },
        { "I used to play piano by ear.", "Now I use my hands." },
        { "What do you call cheese that isn't yours?", "Nacho cheese." },
        { "Two fellas walk into a bar.", "Third one ducks." },
        { "Why did the bicycle fall over?", "It was two tired." },
        { "I don't trust stairs.", "They're always up to something." },
        { "What do you call a fish with no eyes?", "A fsh." },
        { "What do you call a deer with no eyes?", "No idea." },
        { "What do you call a deer with no eyes and no legs?", "Still no idea." },
        { "What do you call a sleeping dinosaur?", "A dino-snore." },
        { "What's brown and sticky?", "A stick." },
        { "When does a joke become a dad joke?", "When it becomes apparent." },
        { "I got hit in the head with a can of pop.", "Lucky it was a soft drink." },
        { "Why do seagulls fly over the sea?", "Over the bay they'd be bagels." },
        { "What do you call a cow after an earthquake?", "A milkshake." },
        { "Why did the tomato blush?", "It saw the salad dressing." },
        { "Why can't a nose be twelve inches long?", "Then it'd be a foot." },
        { "What kind of shoes does a lazy man wear?", "Loafers." },
        { "How does a penguin build a house?", "Igloos it together." },
        { "Why don't eggs tell jokes?", "They'd crack each other up." },
        { "What time is it when you go to the dentist?", "Tooth-hurty." },
        { "Why was the math book sad?", "Too many problems." },
        { "Did you hear about the fella afraid of hurdles?", "He got over it." },
        { "Why couldn't the pony sing?", "She was a little horse." },
        { "What did the grape do when it got stepped on?", "Let out a little wine." },
        { "How do you throw a party on Mars?", "You planet." },
        { "Why did the barber win the race?", "He knew a shortcut." },
        { "Why did the coffee call the police?", "It got mugged." },
        { "What did the buffalo say when his boy left for college?", "Bison." },
        { "What's orange and sounds like a parrot?", "A carrot." },
        { "Why did the stadium get hot after the ballgame?", "All the fans left." },
        { "What do you call a man lying in a pile of leaves?", "Russell." },
        { "What lies at the bottom of the sea and twitches?", "A nervous wreck." },
        { "Why did the invisible man turn down the job?", "Couldn't see himself doing it." },
        { "What did the zero say to the eight?", "Nice belt." },
        { "Why don't scientists trust atoms?", "They make up everything." },
        { "What do you call a belt made of watches?", "A waist of time." },
        { "How does a zombie say hello?", "Pleased to eat you." },
        { "What's a zombie's favorite bean?", "A human bean." },
    },
}
Dads.JOKES = JOKES

local LINES = {
    garyGroan = {
        "Oh, come on, Ron.",
        "That's a two. A generous two.",
        "I heard that one at my wedding.",
        "Boo. Boo, I say.",
        "The dead outside just groaned too.",
        "That's not a joke, that's a cry for help.",
        "You got that off a popsicle stick.",
        "Barb took the bus for a reason, Ron.",
        { "Hell, I'd give that a three.", clean = "Heck, I'd give that a three." },
    },
    ronGroan = {
        "Gary. No.",
        "That's a one. I'm being kind.",
        "I'm writing that down. As evidence.",
        "Linda left on the first bus. Now I know why.",
        "My ears are bleeding, Gary.",
        "That one was old when Nixon was new.",
        "Even the dead have standards.",
        { "Goddamn it, Gary.", clean = "Doggone it, Gary." },
        "Put that one back where you found it.",
    },
    garyGreet = { "Oh, thank God. A neutral party." },
    ronGreet = { "We're tied. Forty-one to forty-one. You're the judge." },
    garyRules = { "Best of five. One joke each, then you pick. No pressure." },
    garyPrompt = { "Well, judge?", "Take your time. Pick me." },
    ronPrompt = { "Judge. We're waiting.", "Go on. Tell him he lost." },
    garyWin = { "Thank you. Justice.", "Put it in the book, Ron.", "The people have spoken." },
    ronWin = { "Finally. Somebody with ears.", "Mark it down, Gary. In pen.", "Sanity prevails." },
    garyLose = { "This is rigged.", "You're on his side. I can tell." },
    ronLose = { "You don't even live here.", "I want a recount." },
    garyTie = { "A tie? That's a coward's call." },
    ronTie = { "Tie. Fine. Nobody's happy. Like marriage." },
    ronNoVerdict = { "No verdict. Fine. Next round." },
    garyNoVerdict = { "Silent judge. Just like Linda." },
    garyChampion = { "Champion of this living room. Say it with me." },
    ronChampion = { "Undisputed. Undefeated. Mostly." },
    garyLoser = { "I need a minute. And a new neighbor." },
    ronLoser = { "I'm moving. The second this is over, I'm moving." },
    garyPrize = { "Winner gets the last two beers. Judge gets one. Don't argue." },
    ronPrize = { "Prize was the last two beers. Judge gets one. Take it before I change my mind." },
    ronScore = { "Gary %d, Ron %d. Round %d. Don't encourage him." },
    fellow = {
        "Are they doing this on purpose?",
        "I'd rather go back outside.",
    },
}
Dads.LINES = LINES

local runtimeByGroup = setmetatable({}, { __mode = "k" })

local function U() return SC.GameplayUtil end

local function story(group)
    local value = type(group) == "table" and group.oddball or nil
    if type(value) ~= "table" or value.id ~= ID then return nil end
    if value.stage == nil or value.stage == "unmet" then value.stage = "waiting" end
    value.score = type(value.score) == "table" and value.score
        or { gary = STARTING_SCORE, ron = STARTING_SCORE }
    value.rounds = type(value.rounds) == "table" and value.rounds or { gary = 0, ron = 0 }
    value.cursor = type(value.cursor) == "table" and value.cursor or { gary = 0, ron = 0 }
    value.lines = type(value.lines) == "table" and value.lines or {}
    value.turn = value.turn == "ron" and "ron" or "gary"
    value.roundJokes = tonumber(value.roundJokes) or 0
    return value
end

local function memberActor(group, role)
    for _, member in ipairs(group and group.members or {}) do
        if member.role == role then
            local record = member.actorId and SC.Registry
                and SC.Registry.byId(member.actorId) or nil
            local actor = record and record.actor
            if actor and U().isValidActor(actor) and not U().isDead(actor) then
                return actor
            end
            return nil
        end
    end
    return nil
end

local function roleOf(group, actor)
    local id = actor and U().idOf(actor)
    for _, member in ipairs(group and group.members or {}) do
        if id ~= nil and member.actorId == id then return member.role end
    end
    return nil
end

local function other(role) return role == "gary" and "ron" or "gary" end

local function lineText(entry)
    if type(entry) == "table" then
        return U().config("profanityEnabled") == false and entry.clean or entry[1]
    end
    return entry
end

local function nextLine(value, pool)
    local list = LINES[pool]
    local index = tonumber(value.lines[pool]) or 0
    if index ~= index or index < 0 or index % 1 ~= 0 then index = 0 end
    index = index % #list + 1
    value.lines[pool] = index
    return lineText(list[index])
end

local function runtimeFor(group)
    local entry = runtimeByGroup[group]
    if not entry then
        entry = { phase = nil, nextAt = 0, queue = {} }
        runtimeByGroup[group] = entry
    end
    return entry
end

local function say(group, role, text)
    local actor = memberActor(group, role)
    if not actor or not text then return false end
    return U().say(actor, text) == true
end

local function sayPool(group, value, role, pool)
    return say(group, role, nextLine(value, pool))
end

-- Lines that follow a verdict wait their turn instead of talking over it.
local function queue(group, role, text, current, delay)
    local entry = runtimeFor(group)
    local last = entry.queue[#entry.queue]
    local at = math.max(current + (delay or 0), last and last.at + QUEUED_LINE_GAP_MS or 0)
    entry.queue[#entry.queue + 1] = { role = role, text = text, at = at }
    return at
end

local function flushQueue(group, current)
    local entry = runtimeFor(group)
    local head = entry.queue[1]
    if head and current >= head.at then
        table.remove(entry.queue, 1)
        say(group, head.role, head.text)
        return true
    end
    return head ~= nil
end

local function fellowLine(group, player, value)
    if value.fellowSpoke == true or not player or not SC.Registry
        or type(SC.Registry.living) ~= "function" then return false end
    local gary, ron = memberActor(group, "gary"), memberActor(group, "ron")
    for _, fellow in ipairs(SC.Registry.living()) do
        if fellow ~= gary and fellow ~= ron and U().distance(fellow, player) <= 10 then
            local id = U().idOf(fellow)
            local record = id and SC.Registry.byId(id) or nil
            if record and record.recruited == true then
                U().say(fellow, nextLine(value, "fellow"))
                value.fellowSpoke = true
                return true
            end
        end
    end
    return false
end

local function tagged(actor, key, groupId)
    local inventory = actor and U().inventory(actor)
    for _, item in ipairs(inventory and U().inventoryItemsDeep(inventory, 120, 4) or {}) do
        local data = U().modData(item)
        if type(data) == "table" and data[key] == groupId then return item end
    end
    return nil
end

local function standingsText(value)
    return "THE STANDINGS. Gary " .. tostring(value.score.gary)
        .. ". Ron " .. tostring(value.score.ron) .. ". No erasing. - R.P."
end

local function writeStandings(group, value)
    local notebook = tagged(memberActor(group, "ron"), "lfDadsStandingsGroupId", group.id)
    if notebook then U().call(notebook, "addPage", 1, standingsText(value)) end
    return notebook ~= nil
end

function Dads.onSpawn(group, actor)
    local value = story(group)
    if not value or not actor then return false, "dads_unavailable" end
    local role = roleOf(group, actor)
    if role ~= "gary" and role ~= "ron" then return false, "dad_role_unknown" end
    local inventory = U().inventory(actor)
    if not inventory then return false, "dad_inventory_unavailable" end
    local flag = role .. "Seeded"
    if value[flag] ~= true then
        if not tagged(actor, "lfDadsBeerGroupId", group.id) then
            local beer = U().addItem(inventory, "Base.BeerCan")
            local data = beer and U().modData(beer)
            if type(data) ~= "table" then return false, "dad_beer_unavailable" end
            data.lfDadsBeerGroupId = group.id
        end
        if role == "gary" then
            local club = U().addItem(inventory, "Base.Golfclub")
            if not club then return false, "gary_club_unavailable" end
            U().call(actor, "setPrimaryHandItem", club)
        else
            local bat = U().addItem(inventory, "Base.BaseballBat")
            if not bat then return false, "ron_bat_unavailable" end
            U().call(actor, "setPrimaryHandItem", bat)
            if not tagged(actor, "lfDadsStandingsGroupId", group.id) then
                local notebook = U().addItem(inventory, "Base.Notebook")
                local data = notebook and U().modData(notebook)
                if type(data) ~= "table" then return false, "ron_notebook_unavailable" end
                U().call(notebook, "setName", "The Standings")
                data.lfDadsStandingsGroupId = group.id
                U().call(notebook, "addPage", 1, standingsText(value))
            end
        end
        value[flag] = true
    end
    return true, "dad_ready"
end

local function playerNear(group, player)
    if not player then return false end
    for _, role in ipairs({ "gary", "ron" }) do
        local actor = memberActor(group, role)
        if actor and U().sameFloor(actor, player)
            and U().distance(actor, player) <= NEAR_DISTANCE
            and U().canSee(actor, player) == true then
            return true
        end
    end
    return false
end

local function nextJoke(value, role)
    local list = JOKES[role]
    local index = (tonumber(value.cursor[role]) or 0) % #list + 1
    value.cursor[role] = index
    return list[index]
end

-- The contest is one shared beat machine. Either dad's update may drive it;
-- the timestamp makes the second caller in the same tick a no-op.
function Dads.advance(group, player, current)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    current = tonumber(current) or U().nowMs()
    if not memberActor(group, "gary") or not memberActor(group, "ron") then
        return false, "dads_not_both_present"
    end
    local entry = runtimeFor(group)
    if flushQueue(group, current) then return true, "dads_finishing_a_line" end
    if not playerNear(group, player) then return true, "dads_without_an_audience" end
    if value.stage == "waiting" then
        value.stage = "contest"
        group.discovered = true
        sayPool(group, value, "gary", "garyGreet")
        queue(group, "ron", nextLine(value, "ronGreet"), current, QUEUED_LINE_GAP_MS)
        queue(group, "gary", nextLine(value, "garyRules"), current, 0)
        entry.phase, entry.nextAt = "setup", current + 3 * QUEUED_LINE_GAP_MS + 1500
        return true, "dads_greeted"
    end
    if current < (tonumber(entry.nextAt) or 0) then return true, "dads_pausing" end
    local phase = entry.phase or "setup"
    if value.awaitingVerdict == true then
        local count = tonumber(value.promptCount) or 0
        if count >= PROMPTS_BEFORE_MOVING_ON then
            value.awaitingVerdict, value.promptCount, value.roundJokes = false, 0, 0
            sayPool(group, value, "ron", "ronNoVerdict")
            queue(group, "gary", nextLine(value, "garyNoVerdict"), current, QUEUED_LINE_GAP_MS)
            entry.phase, entry.nextAt = "setup", current + BETWEEN_JOKES_MS + QUEUED_LINE_GAP_MS
            return true, "dads_gave_up_on_the_judge"
        end
        value.promptCount = count + 1
        local role = count % 2 == 0 and "gary" or "ron"
        sayPool(group, value, role, role .. "Prompt")
        entry.nextAt = current + PROMPT_GAP_MS
        return true, "dads_waiting_for_a_verdict"
    end
    if phase == "setup" then
        local teller = value.turn
        local joke = nextJoke(value, teller)
        entry.joke, entry.teller = joke, teller
        say(group, teller, joke[1])
        entry.phase, entry.nextAt = "punch", current + SETUP_TO_PUNCH_MS
        fellowLine(group, player, value)
        return true, "dad_setup"
    elseif phase == "punch" then
        say(group, entry.teller, entry.joke and entry.joke[2])
        entry.phase, entry.nextAt = "groan", current + PUNCH_TO_GROAN_MS
        return true, "dad_punchline"
    elseif phase == "groan" then
        local rival = other(entry.teller)
        sayPool(group, value, rival, rival .. "Groan")
        value.turn = rival
        if value.stage == "contest" then
            value.roundJokes = value.roundJokes + 1
            if value.roundJokes >= 2 then
                value.awaitingVerdict, value.promptCount = true, 0
                entry.phase, entry.nextAt = "setup", current + QUEUED_LINE_GAP_MS
                return true, "dads_round_complete"
            end
            entry.phase, entry.nextAt = "setup", current + BETWEEN_JOKES_MS
        else
            entry.phase, entry.nextAt = "setup", current + EXHIBITION_GAP_MS
        end
        return true, "dad_groaned"
    end
    entry.phase = "setup"
    return true, "dads_reset_beat"
end

function Dads.intentFor(actor, player, snapshot, group)
    if not story(group) then return nil end
    return { mode = "dads_living_room", priority = 40 }
end

function Dads.update(actor, player, runtime, intent, group)
    if not intent or intent.mode ~= "dads_living_room" then return false end
    Dads.advance(group, player, U().nowMs())
    return true, "dads_holding_the_living_room"
end

function Dads.pulse(group, player, current)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    return true, value.stage
end

local function nearForMenu(group, player)
    if not player then return false end
    for _, role in ipairs({ "gary", "ron" }) do
        local actor = memberActor(group, role)
        if actor and U().sameFloor(actor, player)
            and U().distance(actor, player) <= MENU_DISTANCE then return true end
    end
    return false
end

function Dads.menuOptions(group, player)
    local value = story(group)
    if not value or value.stage == "waiting" or not nearForMenu(group, player)
        or not memberActor(group, "gary") or not memberActor(group, "ron") then
        return {}
    end
    local options = {}
    if value.awaitingVerdict == true then
        options[#options + 1] = { id = "verdict_gary", label = "Gary's was funnier", enabled = true }
        options[#options + 1] = { id = "verdict_ron", label = "Ron's was funnier", enabled = true }
        options[#options + 1] = { id = "verdict_tie", label = "Call it a tie", enabled = true }
    end
    if value.stage == "contest" then
        options[#options + 1] = { id = "ask_dads_score", label = "Ask for the score", enabled = true }
    end
    return options
end

local function crown(group, value, winner, player, current)
    local loser = other(winner)
    value.stage = "exhibition"
    value.champion = winner
    queue(group, winner, nextLine(value, winner .. "Champion"), current, QUEUED_LINE_GAP_MS)
    queue(group, loser, nextLine(value, loser .. "Loser"), current, 0)
    queue(group, winner, nextLine(value, winner .. "Prize"), current, 0)
    if value.prizeGiven ~= true then
        -- The exact tagged can, moved and verified. A by-type exchange would
        -- hand over whichever beer he happens to carry first.
        local beer = tagged(memberActor(group, winner), "lfDadsBeerGroupId", group.id)
        local source = beer and select(1, U().call(beer, "getContainer"))
        local destination = player and U().inventory(player)
        if source and destination then
            value.prizeGiven = U().transferItemVerified(source, destination, beer) == true
        end
    end
    return true
end

function Dads.action(group, action, player)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    if not nearForMenu(group, player) then return false, "dads_out_of_earshot" end
    local current = U().nowMs()
    local entry = runtimeFor(group)
    if action == "ask_dads_score" then
        if value.stage ~= "contest" then return false, "no_match_running" end
        local round = value.rounds.gary + value.rounds.ron + 1
        say(group, "ron", string.format(LINES.ronScore[1],
            value.score.gary, value.score.ron, round))
        return true, "dads_reported_the_score"
    end
    if value.awaitingVerdict ~= true then return false, "no_round_to_judge" end
    value.awaitingVerdict, value.promptCount, value.roundJokes = false, 0, 0
    if action == "verdict_tie" then
        say(group, "gary", nextLine(value, "garyTie"))
        queue(group, "ron", nextLine(value, "ronTie"), current, QUEUED_LINE_GAP_MS)
    elseif action == "verdict_gary" or action == "verdict_ron" then
        local winner = action == "verdict_gary" and "gary" or "ron"
        local loser = other(winner)
        value.score[winner] = value.score[winner] + 1
        value.rounds[winner] = value.rounds[winner] + 1
        writeStandings(group, value)
        say(group, winner, nextLine(value, winner .. "Win"))
        queue(group, loser, nextLine(value, loser .. "Lose"), current, QUEUED_LINE_GAP_MS)
        if value.rounds[winner] >= ROUNDS_TO_WIN then
            crown(group, value, winner, player, current)
        end
    else
        value.awaitingVerdict = true
        return false, "unknown_dads_choice"
    end
    entry.phase = "setup"
    entry.nextAt = (entry.queue[#entry.queue] and entry.queue[#entry.queue].at or current)
        + BETWEEN_JOKES_MS
    return true, action
end

function Dads.canRecruit()
    return false, "dads_are_holding_the_living_room"
end

function Dads._resetForTests()
    runtimeByGroup = setmetatable({}, { __mode = "k" })
end

return Dads
