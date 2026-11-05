-- SPDX-License-Identifier: MIT
local SC = SurvivorCompanion
local now = 500000
local player = { id = "player", x = 0, y = 0, z = 0 }
local forearm = { bittenFlag = false }
local body = { infected = false, infectionTime = -1, duration = 60 }
local hershel = { id = "hershel", x = 3, y = 0, z = 0, inv = { items = {} },
    seated = false, hours = 100, shelter = false, ended = 0 }
local fellow = { id = "fellow", x = 1, y = 1, z = 0 }
local group = { id = "hershel-group", standing = "Neutral",
    members = { { actorId = "hershel" } },
    oddball = { id = "bitten_hershel_combs", stage = "unmet",
        site = { kind = "resident", spawn = { x = 3, y = 0, z = 0 } } } }
local visible = true
local profanityEnabled = true
local biteWorks = true
local moves = {}

BodyPartType = { ForeArm_L = "ForeArm_L" }
SandboxVars = { ZombieLore = { Transmission = 1, Mortality = 5 } }

local function said(actor)
    local line = actor.lastLine
    actor.lastLine = nil
    return line
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
    addItem = function(inv, kind)
        local item = { kind = kind, data = {}, pages = {} }
        inv.items[#inv.items + 1] = item
        return item
    end,
    modData = function(item) return item.data end,
    say = function(value, line) value.lastLine = line return true end,
    move = function(actor, mode, intent)
        moves[#moves + 1] = intent.action
        return true
    end,
    call = function(value, method, ...)
        local a, b, c, d = ...
        if value == hershel then
            if method == "getBodyDamage" then return body, true end
            if method == "isSitOnGround" then return hershel.seated, true end
            if method == "getHoursSurvived" then return hershel.hours, true end
            if method == "isZombiesDontAttack" then return hershel.shelter, true end
        elseif value == body then
            if method == "getBodyPart" then
                assert(a == "ForeArm_L", "the bite goes on the left forearm")
                return forearm, true
            end
            if method == "isInfected" then return body.infected, true end
            if method == "getInfectionTime" then return body.infectionTime, true end
            if method == "getInfectionMortalityDuration" then return body.duration, true end
        elseif value == forearm then
            if method == "SetBitten" then
                forearm.setBittenCalls = (forearm.setBittenCalls or 0) + 1
                if biteWorks then forearm.bittenFlag = a == true end
                return nil, true
            end
            if method == "setBandaged" then
                forearm.bandage = { on = a, life = b, alcohol = c, kind = d }
                return nil, true
            end
            if method == "bitten" then return forearm.bittenFlag, true end
        elseif type(value) == "table" and value.pages then
            if method == "setName" then value.name = a return nil, true end
            if method == "addPage" then value.pages[a] = b return nil, true end
        end
        return nil, false
    end,
}
SC.Registry = {
    byId = function(id)
        if id == "hershel" then return { actor = hershel } end
        if id == "fellow" then return { actor = fellow, recruited = true } end
        return nil
    end,
    living = function() return { hershel, fellow } end,
}
SC.Oddballs = { setZombieShelter = function(actor, wanted)
    assert(actor == hershel)
    hershel.shelter = wanted
    return true
end }
SC.Actor = { endLife = function(actor)
    assert(actor == hershel)
    hershel.ended = hershel.ended + 1
    return true
end }

local B = SC.OddballBitten
local LINES = B.LINES

local function contains(pool, line)
    for _, entry in ipairs(LINES[pool]) do
        if entry == line or type(entry) == "table"
            and (entry[1] == line or entry.clean == line) then return true end
    end
    return false
end

-- Lines: printable ASCII, short, clean twins really clean, no game words,
-- and nothing about a room other than the bathroom he is placed in.
do
    local banned = { "tile", "player", "save", "mod", "moodle", "reload", "game" }
    local swears = { "shit", "bitch", "bastard", "hell", "damn", "goddamn", "fuck" }
    local rooms = { "kitchen", "bedroom", "garage", "basement", "living room", "tub" }
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
        for _, room in ipairs(rooms) do
            assert(not string.find(lower, room, 1, true),
                label .. " names no room he may not be in: " .. line)
        end
    end
    for pool, list in pairs(LINES) do
        for index, entry in ipairs(list) do
            local label = pool .. "[" .. index .. "]"
            if type(entry) == "table" then
                lint(entry[1], label)
                lint(entry.clean, label .. ".clean")
                local clean = string.lower(entry.clean)
                for _, word in ipairs(swears) do
                    assert(not string.find(clean, "%f[%a]" .. word .. "%f[%A]"),
                        label .. " clean twin is clean: " .. entry.clean)
                end
            else
                lint(entry, label)
            end
        end
    end
    assert(#B.PAGES == 9, "nine pages for nine counted days")
    for index, page in ipairs(B.PAGES) do
        assert(string.find(page, "^Day " .. index .. "%. "), "page " .. index .. " is that day's entry")
        assert(not string.find(page, "[^\032-\126]"), "page " .. index .. " is printable ASCII")
    end
end

-- The sandbox decides whether his story can be true.
assert(B.bitesInfect() == true, "blood and saliva transmission with a two-to-three day mortality")
SandboxVars.ZombieLore.Transmission = 2
assert(B.bitesInfect() == true, "saliva-only transmission still kills by bite")
for _, transmission in ipairs({ 3, 4 }) do
    SandboxVars.ZombieLore.Transmission = transmission
    assert(B.bitesInfect() == false, "transmission " .. transmission .. " leaves a bite harmless to his story")
end
SandboxVars.ZombieLore.Transmission = 1
for _, mortality in ipairs({ 1, 7 }) do
    SandboxVars.ZombieLore.Mortality = mortality
    assert(B.bitesInfect() == false, "mortality " .. mortality .. " is instant or never")
end
SandboxVars.ZombieLore.Mortality = 5
local saved = SandboxVars
SandboxVars = nil
assert(B.bitesInfect() == false, "no sandbox table, no Hershel")
SandboxVars = saved

-- A refused native bite is not papered over.
biteWorks = false
local ready, reason = B.onSpawn(group, hershel)
assert(ready == false and reason == "hershel_bite_unavailable" and #hershel.inv.items == 0,
    "setup fails and retries when the native part does not read back bitten")
biteWorks = true

-- The bite is the vanilla call, bandaged with a dirty rag, and his notebook
-- carries nine real pages.
assert(B.onSpawn(group, hershel))
assert(forearm.bittenFlag == true and forearm.bandage.on == true
        and forearm.bandage.kind == "Base.RippedSheetsDirty",
    "a real bitten forearm under a dirty rag")
assert(#hershel.inv.items == 1 and hershel.inv.items[1].kind == "Base.Notebook"
        and hershel.inv.items[1].name == "Hershel's count"
        and hershel.inv.items[1].pages[1] == B.PAGES[1]
        and hershel.inv.items[1].pages[9] == B.PAGES[9],
    "his count is a readable notebook")
assert(hershel.shelter == true, "the dead leave him alone until the player arrives")
local calls = forearm.setBittenCalls
assert(B.onSpawn(group, hershel))
assert(forearm.setBittenCalls == calls and #hershel.inv.items == 1,
    "a reload neither bites him twice nor writes a second notebook")

-- He sits on the floor and stays there; retries are bounded.
local intent = B.intentFor(hershel, player, {}, group)
assert(intent.mode == "bitten_floor" and intent.priority == 94)
assert(B.update(hershel, player, {}, intent, group))
assert(#moves == 1 and moves[1] == "sit_ground", "he sits down on the floor")
assert(B.update(hershel, player, {}, intent, group) and #moves == 1,
    "no second request inside the retry gap")
for _ = 1, 6 do
    now = now + 13000
    B.update(hershel, player, {}, intent, group)
end
assert(#moves == 4, "a stubborn floor gets four tries, not forever")
hershel.seated = true
now = now + 13000
local _, seatedReason = B.update(hershel, player, {}, intent, group)
assert(seatedReason == "hershel_seated" and #moves == 4)

-- Far away: silence. Close and in sight: the greeting, then two intro beats.
player.x = 20
assert(B.pulse(group, player, now) and group.oddball.stage == "waiting"
        and hershel.lastLine == nil)
assert(#B.menuOptions(group, player) == 0, "no choices before you have met him")
player.x = 0
assert(B.pulse(group, player, now))
assert(group.oddball.stage == "pleading" and group.discovered == true
        and contains("greet", said(hershel)))
assert(B.pulse(group, player, now) and hershel.lastLine == nil,
    "he lets the greeting land before the next line")
now = now + 5600
assert(B.pulse(group, player, now) and said(hershel) == LINES.intro[1])
now = now + 5600
assert(B.pulse(group, player, now) and said(hershel) == LINES.intro[2])
assert(contains("fellowMeet", said(fellow)), "a companion weighs in once")

-- The pleas rotate; every third beat is the fever talking.
local heard = {}
for beat = 1, 6 do
    now = now + 50000
    B.pulse(group, player, now)
    heard[beat] = said(hershel)
end
assert(contains("plea", heard[1]) and contains("plea", heard[2])
        and contains("fever", heard[3]) and contains("plea", heard[4])
        and contains("fever", heard[6]),
    "plea, plea, fever, in rotation")
assert(heard[1] ~= heard[2] and heard[2] ~= heard[4], "no plea repeats back to back")

-- Late in the infection the lines change.
body.infected, body.infectionTime, body.duration = true, 40, 60
hershel.hours = 40 + 0.9 * 60
assert(math.abs(B.infectionPercent(hershel) - 90) < 0.001,
    "progress mirrors the engine: hours survived since infection over mortality")
now = now + 50000
B.pulse(group, player, now)
assert(contains("late", said(hershel)), "near the end he asks for it plainly")
body.infected = false
assert(B.infectionPercent(hershel) == 0)

-- The clean twin with profanity off.
profanityEnabled = false
for index, entry in ipairs(LINES.plea) do
    if type(entry) == "table" then group.oddball.lines.plea = index - 1 break end
end
group.oddball.talkCount = 0
now = now + 50000
B.pulse(group, player, now)
local cleanLine = said(hershel)
local isClean = false
for _, entry in ipairs(LINES.plea) do
    if type(entry) == "table" and entry.clean == cleanLine then isClean = true end
end
assert(isClean, "profanity off swaps in the clean plea: " .. tostring(cleanLine))
profanityEnabled = true

-- Walking out and coming back.
player.x = 15
assert(B.pulse(group, player, now) and group.oddball.stage == "left")
now = now + 31000
player.x = 0
assert(B.pulse(group, player, now) and group.oddball.stage == "pleading"
        and contains("back", said(hershel)), "he notices you came back")

-- The menu, in reach only.
player.x = 8
assert(#B.menuOptions(group, player) == 0, "no choices from across the room")
player.x = 1
local options = B.menuOptions(group, player)
assert(#options == 5 and options[5].id == "mercy_hershel")
assert(B.action(group, "ask_hershel_bite", player) and said(hershel) == LINES.bite[1])
assert(B.action(group, "ask_hershel_bite", player) and said(hershel) == LINES.bite[2])
assert(B.action(group, "ask_hershel_count", player) and contains("count", said(hershel)))
assert(B.action(group, "refuse_hershel", player) and said(hershel) == LINES.refuse[1])
assert(B.action(group, "refuse_hershel", player) and said(hershel) == LINES.refuse[2])
assert(B.action(group, "sit_with_hershel", player) and contains("sit", said(hershel)))
now = now + 21000
B.pulse(group, player, now)
assert(contains("sitAfter", said(hershel)), "the quiet beat after you sit with him")

-- Struck, he asks you to finish; no standing change is requested.
local struck, struckWhy = B.action(group, "hurt", player)
assert(struck == true and struckWhy == "hershel_does_not_fight_back"
        and contains("hurt", said(hershel)))

-- Mercy: his last line, the native fatal injury, and a companion who knows
-- what comes next.
assert(B.action(group, "mercy_hershel", player))
assert(said(hershel) == LINES.mercy[1] and hershel.ended == 1
        and group.oddball.stage == "dying" and group.oddball.outcome == "mercy")
assert(contains("fellowMercy", said(fellow)))
assert(#B.menuOptions(group, player) == 0, "nothing left to ask")
assert(select(1, B.action(group, "mercy_hershel", player)) == false and hershel.ended == 1,
    "mercy cannot be applied twice")
assert(B.intentFor(hershel, player, {}, group).mode == "oddball_idle")
assert(B.zombiesIgnore(hershel, group) == false, "the shelter ends with him")
hershel.dead = true
assert(select(2, B.pulse(group, player, now)) == "hershel_dead")
assert(B.avoidsZombieCombat() == true and select(1, B.canRecruit()) == false)

print("Bitten PASS: sandbox gate, native bite and notebook, floor sitting, greeting and intro order, plea rotation, late lines, leave and return, menu, mercy")
