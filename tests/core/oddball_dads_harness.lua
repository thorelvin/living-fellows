-- SPDX-License-Identifier: MIT
local SC = SurvivorCompanion
local now = 1000000
local player = { id = "player", x = 0, y = 0, z = 0, inv = { items = {} } }
local gary = { id = "gary", x = 2, y = 0, z = 0, inv = { items = {} } }
local ron = { id = "ron", x = 3, y = 0, z = 0, inv = { items = {} } }
local fellow = { id = "fellow", x = 50, y = 1, z = 0 }
local group = { id = "dads-group", standing = "Neutral",
    members = { { actorId = "gary", role = "gary" }, { actorId = "ron", role = "ron" } },
    oddball = { id = "dad_joke_feud", stage = "unmet", site = { kind = "resident" } } }
local visible = true
local profanityEnabled = true
local said = {}
gary.inv.owner, ron.inv.owner, player.inv.owner = gary, ron, player

local function speak(actor, line)
    said[#said + 1] = { who = actor.id, line = line }
    return true
end

SC.GameplayUtil = {
    config = function(name)
        if name == "profanityEnabled" then return profanityEnabled end
        return nil
    end,
    nowMs = function() return now end,
    isValidActor = function(value) return value ~= nil end,
    isDead = function(value) return value == nil or value.dead == true end,
    idOf = function(value) return value and value.id end,
    position = function(value) return value.x, value.y, value.z end,
    distance = function(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end,
    sameFloor = function(a, b) return a.z == b.z end,
    canSee = function() return visible end,
    inventory = function(value) return value.inv end,
    inventoryItemsDeep = function(inv) return inv.items end,
    itemType = function(item) return item.kind end,
    addItem = function(inv, kind)
        local item = { kind = kind, data = {}, pages = {}, container = inv }
        inv.items[#inv.items + 1] = item
        return item
    end,
    transferItemVerified = function(source, destination, item)
        for index, value in ipairs(source.items) do
            if value == item then
                table.remove(source.items, index)
                destination.items[#destination.items + 1] = item
                item.container = destination
                return true
            end
        end
        return false
    end,
    modData = function(item) return item.data end,
    say = speak,
    call = function(value, method, a, b)
        if method == "getContainer" then return value.container, true end
        if method == "setPrimaryHandItem" then value.primary = a return nil, true end
        if method == "setName" then value.name = a return nil, true end
        if method == "addPage" then value.pages[a] = b return nil, true end
        return nil, false
    end,
}
SC.Registry = {
    byId = function(id)
        if id == "gary" then return { actor = gary } end
        if id == "ron" then return { actor = ron } end
        if id == "fellow" then return { actor = fellow, recruited = true } end
        return nil
    end,
    living = function() return { gary, ron, fellow } end,
}

local D = SC.OddballDads
local LINES, JOKES = D.LINES, D.JOKES

local function last() return said[#said] end
local function contains(pool, line)
    for _, entry in ipairs(LINES[pool]) do
        if entry == line or type(entry) == "table"
            and (entry[1] == line or entry.clean == line) then return true end
    end
    return false
end
local function count(inv, kind)
    local total = 0
    for _, item in ipairs(inv.items) do if item.kind == kind then total = total + 1 end end
    return total
end
local function step(ms)
    now = now + ms
    return D.advance(group, player, now)
end

-- Every joke and line: ASCII, short, no game words, nothing after July 1993,
-- clean twins clean, and no setup told twice.
do
    local banned = { "tile", "player", "save", "mod", "moodle", "reload", "game" }
    local modern = { "internet", "e-mail", "email", "website", "cell phone", "amazon",
        "roomba", "facebook", "google", "wifi", "dvd", "elsa", "potter", "gump",
        "texting", "selfie", "netflix", "ipod", "lego shop" }
    local swears = { "shit", "bitch", "bastard", "hell", "damn", "goddamn", "fuck" }
    local function lint(line, label)
        assert(type(line) == "string" and #line > 0, label .. " is text")
        assert(not string.find(line, "[^\032-\126]"), label .. " is printable ASCII: " .. line)
        local words = 0
        for _ in string.gmatch(line, "%S+") do words = words + 1 end
        assert(words <= 18, label .. " stays at eighteen words or fewer: " .. line)
        local lower = string.lower(line)
        for _, word in ipairs(banned) do
            assert(not string.find(lower, "%f[%a]" .. word .. "s?%f[%A]"),
                label .. " avoids the game word '" .. word .. "': " .. line)
        end
        for _, word in ipairs(modern) do
            assert(not string.find(lower, word, 1, true),
                label .. " is nothing newer than 1993: " .. line)
        end
    end
    local setups = {}
    for role, list in pairs(JOKES) do
        assert(#list >= 36, role .. " has a long list of jokes")
        for index, joke in ipairs(list) do
            local label = role .. " joke " .. index
            lint(joke[1], label .. " setup")
            lint(joke[2], label .. " punchline")
            local key = string.lower(joke[1])
            assert(not setups[key], label .. " is not told twice: " .. joke[1])
            setups[key] = true
        end
    end
    for pool, list in pairs(LINES) do
        for index, entry in ipairs(list) do
            local label = pool .. "[" .. index .. "]"
            if type(entry) == "table" then
                lint(entry[1], label)
                lint(entry.clean, label .. ".clean")
                for _, word in ipairs(swears) do
                    assert(not string.find(string.lower(entry.clean), "%f[%a]" .. word .. "%f[%A]"),
                        label .. " clean twin is clean: " .. entry.clean)
                end
            else
                lint(entry, label)
            end
        end
    end
end

-- Each dad seeds his own things once.
assert(D.onSpawn(group, gary) and D.onSpawn(group, ron))
assert(count(gary.inv, "Base.BeerCan") == 1 and gary.primary and gary.primary.kind == "Base.Golfclub",
    "Gary holds his golf club and one beer")
assert(count(ron.inv, "Base.BeerCan") == 1 and ron.primary and ron.primary.kind == "Base.BaseballBat",
    "Ron holds his bat and one beer")
local notebook
for _, item in ipairs(ron.inv.items) do if item.kind == "Base.Notebook" then notebook = item end end
assert(notebook and notebook.name == "The Standings"
        and string.find(notebook.pages[1], "Gary 41. Ron 41.", 1, true),
    "Ron keeps the real standings, tied at forty-one")
assert(D.onSpawn(group, gary) and D.onSpawn(group, ron))
assert(#gary.inv.items == 2 and #ron.inv.items == 3, "a repeated setup adds nothing")
-- A beer of his own sits ahead of the prize in his inventory.
local ownBeer = { kind = "Base.BeerCan", data = {}, pages = {}, container = gary.inv }
table.insert(gary.inv.items, 1, ownBeer)
assert(D.intentFor(gary, player, {}, group).mode == "dads_living_room")

-- No audience, no show.
visible = false
assert(step(1000) and #said == 0, "they do not perform to an empty room")
visible = true

-- Greeting, then the rules, one line at a time.
step(1000)
assert(last().who == "gary" and contains("garyGreet", last().line))
assert(group.discovered == true and group.oddball.stage == "contest")
step(1000)
assert(#said == 1, "Ron waits for Gary to finish")
step(1600)
assert(last().who == "ron" and contains("ronGreet", last().line))
step(2600)
assert(last().who == "gary" and contains("garyRules", last().line))
assert(#D.menuOptions(group, player) == 1, "only the score question before a round is complete")

-- One round: Gary sets up, pauses, lands it, Ron groans; then Ron's turn.
step(1600)
assert(contains("garyRules", last().line), "a breath after the rules before the first joke")
step(2400)
local setupLine = last().line
assert(last().who == "gary" and setupLine == JOKES.gary[1][1], "Gary opens with his first joke")
step(1000)
assert(last().line == setupLine, "the punchline waits for the pause")
step(2600)
assert(last().who == "gary" and last().line == JOKES.gary[1][2], "Gary lands the punchline")
step(2600)
assert(last().who == "ron" and contains("ronGroan", last().line), "Ron groans")
step(5100)
assert(last().who == "ron" and last().line == JOKES.ron[1][1], "then Ron tells one")
step(3600)
assert(last().line == JOKES.ron[1][2])
step(2600)
assert(last().who == "gary" and contains("garyGroan", last().line))
assert(group.oddball.awaitingVerdict == true, "after one joke each, they want a verdict")
local options = D.menuOptions(group, player)
assert(#options == 4 and options[1].id == "verdict_gary" and options[3].id == "verdict_tie")

-- The judge gives Gary the round; the book records it; Ron objects in turn.
assert(D.action(group, "verdict_gary", player))
assert(last().who == "gary" and contains("garyWin", last().line))
assert(group.oddball.score.gary == 42 and group.oddball.rounds.gary == 1
        and string.find(notebook.pages[1], "Gary 42. Ron 41.", 1, true),
    "the standings page is rewritten with the new score")
step(2600)
assert(last().who == "ron" and contains("ronLose", last().line))
assert(#D.menuOptions(group, player) == 1, "no second verdict for the same round")
assert(select(1, D.action(group, "verdict_ron", player)) == false)

-- Ask the score mid-match.
assert(D.action(group, "ask_dads_score", player))
assert(last().who == "ron" and last().line == "Gary 42, Ron 41. Round 2. Don't encourage him.")

-- Round two: a tie changes nothing.
local function playRound()
    for _ = 1, 40 do
        step(3000)
        if group.oddball.awaitingVerdict == true then return end
    end
    error("a round never asked for a verdict")
end
playRound()
assert(D.action(group, "verdict_tie", player))
assert(contains("garyTie", last().line) and group.oddball.score.gary == 42
        and group.oddball.score.ron == 41, "a tie scores nobody")

-- Round three: the judge says nothing. They ask three times, then move on.
playRound()
local prompts = 0
for _ = 1, 4 do
    step(25100)
    if contains("garyPrompt", last().line) or contains("ronPrompt", last().line) then
        prompts = prompts + 1
    end
end
assert(prompts == 3, "three prompts, alternating, then no more: " .. prompts)
assert(contains("ronNoVerdict", last().line) and group.oddball.awaitingVerdict == false,
    "a silent judge forfeits the round")
step(2600)
assert(contains("garyNoVerdict", last().line))

-- Profanity off: the rough groan uses its clean twin.
profanityEnabled = false
for index, entry in ipairs(LINES.ronGroan) do
    if type(entry) == "table" then group.oddball.lines.ronGroan = index - 1 break end
end
group.oddball.turn = "gary"
local cleanSeen = false
for _ = 1, 40 do
    step(3000)
    if last().who == "ron" and contains("ronGroan", last().line) then
        for _, entry in ipairs(LINES.ronGroan) do
            if type(entry) == "table" and entry.clean == last().line then cleanSeen = true end
        end
        break
    end
end
assert(cleanSeen, "a rough groan falls back to its clean twin")
profanityEnabled = true
if group.oddball.awaitingVerdict ~= true then playRound() end

-- Two more Gary wins crown him; the beer is really handed over.
assert(D.action(group, "verdict_gary", player))
playRound()
assert(D.action(group, "verdict_gary", player))
assert(group.oddball.stage == "exhibition" and group.oddball.champion == "gary",
    "three round wins make a champion")
assert(count(gary.inv, "Base.BeerCan") == 1 and count(player.inv, "Base.BeerCan") == 1
        and player.inv.items[#player.inv.items].data.lfDadsBeerGroupId == group.id
        and gary.inv.items[1] == ownBeer and group.oddball.prizeGiven == true,
    "the judge gets the winner's tagged beer, not whatever beer he had on him")
local heard = {}
for _ = 1, 6 do
    step(2600)
    heard[#heard + 1] = last().line
end
local function heardFrom(pool)
    for _, line in ipairs(heard) do if contains(pool, line) then return true end end
    return false
end
assert(heardFrom("garyChampion") and heardFrom("ronLoser") and heardFrom("garyPrize"),
    "champion, loser and prize lines all play")
assert(#D.menuOptions(group, player) == 0, "no more judging once it's settled")

-- Exhibition: they keep going, slowly, and never ask for a verdict again.
local before = #said
step(10000)
step(10000)
for _ = 1, 3 do step(3600) end
step(70100)
for _ = 1, 3 do step(3600) end
assert(#said > before and group.oddball.awaitingVerdict ~= true,
    "exhibition jokes continue without verdicts")

-- A companion within earshot speaks up once, not every joke.
local function fellowLines()
    local total = 0
    for _, entry in ipairs(said) do if entry.who == "fellow" then total = total + 1 end end
    return total
end
assert(fellowLines() == 0, "a companion out of earshot says nothing")
fellow.x = 1
for _ = 1, 60 do step(3600) end
assert(fellowLines() == 1, "a companion comments once, not every joke: " .. fellowLines())

-- Out of range, the menu is closed.
player.x = 20
assert(#D.menuOptions(group, player) == 0)
assert(select(1, D.canRecruit()) == false)

print("Dads PASS: seeded kit and standings, greeting order, joke beats, verdicts, tie, silent judge, score, champion, real beer, exhibition")
