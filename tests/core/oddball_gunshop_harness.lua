-- SPDX-License-Identifier: MIT
local SC = SurvivorCompanion
local now = 3000000
local player = { id = "player", x = 0, y = 0, z = 0, inv = { items = {} }, num = 0 }
local bob = { id = "bob", x = 3, y = 0, z = 0, inv = { items = {} } }
local fellow = { id = "fellow", x = 1, y = 1, z = 0 }
player.inv.owner, bob.inv.owner = player, bob
local glass = { __class = "IsoWindow", smashed = false, barricaded = false, smashCalls = 0 }
local windowSquare = { x = -2, y = 0, z = 0, objects = { glass } }
local visible, profanityEnabled = true, true
local seenPosts = {}
local spawned, sounds, emotes = {}, {}, {}
local function newGroup()
    return { id = "bob-group", standing = "Neutral", members = { { actorId = "bob" } },
        oddball = { id = "gunshop_bob_kenley", stage = "unmet", site = { kind = "resident",
            spawn = { x = 3, y = 0, z = 0 },
            partyWindow = { x = -2, y = 0, z = 0, objectIndex = 0, kind = "window" },
            hordeSpawns = { { x = -9, y = -3 }, { x = -9, y = 3 }, { x = -11, y = 0 },
                { x = -13, y = 1 }, { x = -15, y = -1 } } } } }
end

addZombiesInOutfit = function(x, y, z, count, outfit, female)
    local zombie = { id = "zombie" .. (#spawned + 1), x = x, y = y, z = z,
        outfit = outfit, data = {} }
    spawned[#spawned + 1] = zombie
    return { zombie }
end
addSound = function(source, x, y, z, radius, volume)
    sounds[#sounds + 1] = { source = source, x = x, y = y, radius = radius }
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
    instanceOf = function(value, name) return type(value) == "table" and value.__class == name end,
    position = function(value) return value.x, value.y, value.z end,
    distance = function(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end,
    sameFloor = function(a, b) return (a.z or 0) == (b.z or 0) end,
    canSee = function(observer, target)
        if target and target.post then return seenPosts[target.key] == true end
        return visible
    end,
    gridSquare = function(x, y, z)
        if x == windowSquare.x and y == windowSquare.y then return windowSquare end
        return { x = x, y = y, z = z or 0, post = true, key = x .. ":" .. y }
    end,
    isSafeSpawnSquare = function(square) return square ~= nil end,
    inventory = function(value) return value.inv end,
    inventoryItemsDeep = function(inv) return inv.items end,
    itemType = function(item) return item.kind end,
    addItem = function(inv, kind)
        local item = { kind = kind, data = {}, container = inv }
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
    say = function(actor, line) actor.lastLine = line return true end,
    call = function(value, method, a)
        if value == glass then
            if method == "isSmashed" then return glass.smashed, true end
            if method == "isBarricaded" then return glass.barricaded, true end
            if method == "smashWindow" then
                glass.smashed = true
                glass.smashCalls = glass.smashCalls + 1
                return nil, true
            end
        end
        if value == windowSquare and method == "getObjects" then return windowSquare.objects, true end
        if value == player and method == "getPlayerNum" then return 0, true end
        if type(value) == "table" and value.post and method == "isCanSee" then
            return seenPosts[value.key] == true, true
        end
        if method == "setPrimaryHandItem" then value.primary = a return nil, true end
        if method == "getContainer" then return value.container, true end
        return nil, false
    end,
}
SC.Registry = {
    byId = function(id)
        if id == "bob" then return { actor = bob } end
        if id == "fellow" then return { actor = fellow, recruited = true } end
        return nil
    end,
    living = function() return { bob, fellow } end,
}
SC.Relationship = { playEmote = function(actor, emote)
    emotes[#emotes + 1] = { actor = actor.id, emote = emote }
    return true
end }

local G = SC.OddballGunShop
local LINES = G.LINES

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
local function said()
    local line = bob.lastLine
    bob.lastLine = nil
    return line
end

-- Lines: ASCII, short, no game words, clean twins clean.
do
    local banned = { "tile", "player", "save", "mod", "moodle", "reload", "game" }
    local swears = { "shit", "bitch", "bastard", "hell", "damn", "goddamn", "fuck" }
    local function lint(line, label)
        assert(type(line) == "string" and #line > 0, label .. " is text")
        assert(not string.find(line, "[^\032-\126]"), label .. " is printable ASCII: " .. line)
        local words = 0
        for _ in string.gmatch(line, "%S+") do words = words + 1 end
        assert(words <= 18, label .. " stays at eighteen words or fewer: " .. line)
        for _, word in ipairs(banned) do
            assert(not string.find(string.lower(line), "%f[%a]" .. word .. "s?%f[%A]"),
                label .. " avoids the game word '" .. word .. "': " .. line)
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
                        label .. " clean twin is clean")
                end
            else
                lint(entry, label)
            end
        end
    end
end

local group = newGroup()
assert(G.onSpawn(group, bob))
assert(bob.primary and bob.primary.kind == "Base.Shotgun"
        and count(bob.inv, "Base.ShotgunShellsBox") == 2,
    "Bob holds his own shotgun with shells to feed it")
assert(count(bob.inv, "Base.Pistol2") == 1 and count(bob.inv, "Base.45Clip") == 2
        and count(bob.inv, "Base.Bullets45Box") == 1, "the good stuff is stocked in back")
local items = #bob.inv.items
assert(G.onSpawn(group, bob) and #bob.inv.items == items, "a setup retry stocks nothing twice")

-- Out of sight: nothing. In sight: the gun comes up, then the apology.
visible = false
assert(G.pulse(group, player, now) and group.oddball.stage == "waiting" and bob.lastLine == nil)
visible = true
G.pulse(group, player, now)
assert(group.oddball.stage == "greeted" and group.discovered == true
        and said() == LINES.greet[1] and emotes[1].emote == "freeze",
    "he throws up a hand and shouts for yours")
local order = {}
for _ = 1, 4 do
    now = now + 2700
    G.pulse(group, player, now)
    order[#order + 1] = said()
end
assert(order[1] == LINES.greet2[1] and order[2] == LINES.intro[1] and order[3] == LINES.safe[1],
    "apology, name, then the famous promise about the glass")
assert(order[4] == nil and glass.smashCalls == 0, "a beat of calm after the promise")

-- Nine seconds after the promise: the glass goes and the dead come.
for _ = 1, 4 do
    now = now + 2700
    G.pulse(group, player, now)
end
assert(glass.smashCalls == 1 and group.oddball.stage == "siege",
    "the real shop window is smashed")
assert(#spawned == 5 and group.oddball.spawned == 5, "five real zombies, out on the street")
for _, zombie in ipairs(spawned) do
    assert(zombie.data.lfGunShopZombieGroupId == group.id and zombie.x <= -9,
        "each one is tagged and starts past the glass")
end
assert(#sounds == 1 and sounds[1].x == -2 and sounds[1].radius == 30,
    "the breaking glass carries thirty meters")
assert(contains("smash", said()), "Bob notices")
assert(group.oddball.stage == "siege" and select(1, G.canRecruit(group)) == false)

-- During the fight he barks every eight seconds, not every pulse.
now = now + 1000
G.pulse(group, player, now)
assert(bob.lastLine == nil)
now = now + 8000
G.pulse(group, player, now)
assert(contains("bark", said()))

-- Only his tagged dead count, once each.
local stranger = { data = {} }
assert(G.onZombieDead(group, stranger) == false)
assert(G.onZombieDead(group, spawned[1]) == true and G.onZombieDead(group, spawned[1]) == false,
    "the same body is not counted twice")
for index = 2, 4 do G.onZombieDead(group, spawned[index]) end
now = now + 1000
G.pulse(group, player, now)
assert(group.oddball.stage == "siege", "one left standing")
G.onZombieDead(group, spawned[5])
now = now + 1000
fellow.lastLine = nil
G.pulse(group, player, now)
assert(group.oddball.stage == "survived" and said() == LINES.survived[1],
    "with all five down, Bob counts himself alive")
assert(contains("fellow", fellow.lastLine), "a companion has an opinion about the glass")

-- The reward is real and moves only when the player is close.
player.x = 20
now = now + 2700
G.pulse(group, player, now)
assert(count(player.inv, "Base.Pistol2") == 0 and group.oddball.rewardGiven ~= true)
player.x = 0
now = now + 100
G.pulse(group, player, now)
assert(count(player.inv, "Base.Pistol2") == 1 and count(player.inv, "Base.45Clip") == 2
        and count(player.inv, "Base.Bullets45Box") == 1 and count(bob.inv, "Base.Pistol2") == 0
        and group.oddball.rewardGiven == true, "the pistol, magazines and ammo change hands")
now = now + 2700
G.pulse(group, player, now)
assert(said() == LINES.reward[1])
assert(G.canRecruit(group) == true, "a shop with a hole in it is easier to leave")

-- Menu and questions.
player.x = 8
assert(#G.menuOptions(group, player) == 0)
player.x = 1
assert(#G.menuOptions(group, player) == 2)
assert(G.action(group, "ask_bob_family", player) and said() == LINES.family[1])
assert(G.action(group, "ask_bob_shop", player) and said() == LINES.shop[1])

-- A shop whose glass is already gone: no scene, an honest line.
G._resetForTests()
group = newGroup()
glass.smashed, glass.smashCalls = true, 0
spawned = {}
group.oddball.stage = "greeted"
group.oddball.smashAt = now
G.pulse(group, player, now)
assert(group.oddball.stage == "quiet" and said() == LINES.noGlass[1] and #spawned == 0)

-- Every approach in view: no pop-in. Six tries, then a quiet day.
G._resetForTests()
group = newGroup()
glass.smashed, glass.smashCalls = false, 0
for _, post in ipairs(group.oddball.site.hordeSpawns) do
    seenPosts[post.x .. ":" .. post.y] = true
end
group.oddball.stage = "greeted"
group.oddball.smashAt = now
for _ = 1, 6 do
    G.pulse(group, player, now)
    now = now + 5100
end
assert(group.oddball.stage == "quiet" and said() == LINES.quiet[1]
        and glass.smashCalls == 0 and #spawned == 0,
    "the dead never appear in front of the player")
seenPosts = {}

-- A siege nobody finishes still ends.
G._resetForTests()
group = newGroup()
glass.smashed = false
profanityEnabled = false
group.oddball.stage = "greeted"
group.oddball.smashAt = now
group.oddball.lines = { smash = 1 }
G.pulse(group, player, now)
assert(group.oddball.stage == "siege" and said() == LINES.smash[2].clean,
    "the clean twin when profanity is off")
now = now + 600001
G.pulse(group, player, now)
assert(group.oddball.stage == "survived", "ten quiet minutes end the siege")

print("GunShop PASS: kit, greeting order, smash and spawn out of sight, barks, kill count, reward, quiet fallbacks, siege limit")
