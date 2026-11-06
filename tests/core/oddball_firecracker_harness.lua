-- SPDX-License-Identifier: MIT
local SC = SurvivorCompanion
local now = 100000
local hour = 300
local player = { id = "player", x = 0, y = 0, z = 0 }
player.square = { x = 0, y = 0, z = 0, label = "player square" }
local bernice = { id = "bernice", x = 30, y = 0, z = 0, inv = { items = {} },
    sounds = {}, faced = 0 }
local fellow = { id = "fellow", x = 1, y = 0, z = 0 }
local group = { id = "bernice-group", standing = "Neutral",
    members = { { actorId = "bernice" } },
    oddball = { id = "firecracker_bernice_hupp", stage = "unmet",
        site = { kind = "roamer", spawn = { x = 30, y = 0, z = 0 } } } }
local visibleToBernice, visibleToPlayer = true, true
local profanityEnabled = true
local requests, cancels, stops = {}, 0, 0
local activeRoute
local thrownItems = {}
local hibernated, retiredReason = false, nil
local spoken = {}

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
    position = function(value)
        if not value then return nil end
        return value.x, value.y, value.z
    end,
    distance = function(a, b)
        return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
    end,
    sameFloor = function(a, b) return a.z == b.z end,
    canSee = function(observer, target)
        if observer == player then return visibleToPlayer end
        return visibleToBernice
    end,
    inventory = function(value) return value.inv end,
    inventoryItemsDeep = function(inv) return inv.items end,
    addItem = function(inv, kind)
        local item = { kind = kind, data = {} }
        inv.items[#inv.items + 1] = item
        return item
    end,
    consumeItem = function(inv, item)
        for index, value in ipairs(inv.items) do
            if value == item then table.remove(inv.items, index) return true end
        end
        return false
    end,
    modData = function(item) return item.data end,
    squareOf = function(value)
        return value.square or { x = math.floor(value.x), y = math.floor(value.y), z = value.z }
    end,
    gridSquare = function(x, y, z) return { x = x, y = y, z = z } end,
    cell = function() return "cell" end,
    isSafeSpawnSquare = function(square) return square ~= nil end,
    stop = function() stops = stops + 1 return true end,
    say = function(value, line)
        value.lastLine = line
        spoken[#spoken + 1] = line
        return true
    end,
    call = function(value, method, ...)
        local a = ...
        if method == "getWorldAgeHours" then return hour, true end
        if method == "getRoom" then return value.room, true end
        if type(value) == "table" and value.trap == true then
            if method == "shouldPlaceInWorldAfterThrowing" then return false, true end
            if method == "isInstantExplosion" then return true, true end
            if method == "triggerExplosion" then value.exploded = true return nil, true end
        end
        if value == bernice then
            if method == "faceThisObject" then value.faced = value.faced + 1 return nil, true end
            if method == "playSound" then value.sounds[#value.sounds + 1] = a return 1, true end
        end
        return nil, false
    end,
}
SC.Registry = {
    byId = function(id)
        if id == "bernice" and not hibernated then return { actor = bernice } end
        if id == "fellow" then return { actor = fellow, recruited = true } end
        return nil
    end,
    living = function() return { bernice, fellow } end,
}
SC.Navigation = {
    request = function(actor, square, gait, options)
        assert(actor == bernice, "only Bernice navigates here")
        requests[#requests + 1] = { square = square, gait = gait, options = options }
        activeRoute = { goalAction = options.action }
        return true, "moving"
    end,
    peek = function() return activeRoute end,
    cancel = function()
        activeRoute = nil
        cancels = cancels + 1
        return true
    end,
}
SC.Factions = { hibernateOddballRoamer = function(id)
    assert(id == group.id)
    if visibleToPlayer then return false end
    hibernated = true
    group.members[1].hibernated = true
    return true
end }
SC.Oddballs = { retire = function(value, reason)
    assert(value == group)
    retiredReason = reason
    return true
end }
getGameTime = function() return {} end
-- The game's own trap class, as vanilla thrown-object code builds it.
local trapClass = { new = function(actor, item, cell, square)
    assert(cell == "cell", "the trap is built in the live cell")
    local trap = { trap = true, actor = actor, item = item, square = square }
    thrownItems[#thrownItems + 1] = trap
    return trap
end }
IsoTrap = trapClass

local F = SC.OddballFirecracker
local LINES = F.LINES

local function count(kind)
    local total = 0
    for _, item in ipairs(bernice.inv.items) do
        if item.kind == kind and item.data.lfFirecrackerGroupId == group.id then
            total = total + 1
        end
    end
    return total
end
local function contains(pool, line)
    for _, entry in ipairs(LINES[pool]) do
        if entry == line or type(entry) == "table"
            and (entry[1] == line or entry.clean == line) then return true end
    end
    return false
end
local function tick(intent)
    return F.update(bernice, player, {}, intent or F.intentFor(bernice, player, {}, group), group)
end

-- Every line: printable ASCII, short, rough lines carry clean twins that are
-- actually clean, and nothing a person in 1993 would not say.
do
    local banned = { "tile", "player", "save", "mod", "moodle", "reload", "game" }
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
                assert(entry[1] ~= entry.clean, label .. " rough and clean differ")
            else
                lint(entry, label)
            end
        end
    end
end

-- Ten real, tagged firecrackers; setup retries never mint an eleventh.
assert(F.onSpawn(group, bernice))
assert(count("Base.Firecracker") == 10 and #bernice.inv.items == 10,
    "Bernice starts with exactly ten tagged firecrackers")
assert(F.onSpawn(group, bernice))
assert(count("Base.Firecracker") == 10, "a repeated setup adds nothing")
assert(group.oddball.stage == "approach")

-- Approach from out of sight uses the moving-target follow route.
visibleToBernice = false
assert(tick())
assert(#requests == 1 and requests[1].options.action == "faction_follow"
        and requests[1].options.movingTarget == true
        and requests[1].options.arrivalDistance == 0.85,
    "an unseen approach routes all the way instead of holding through a wall")
assert(F.pulse(group, player, now) and group.oddball.stage == "approach"
        and bernice.lastLine == nil, "no greeting without sight")
visibleToBernice = true
bernice.x = 11
assert(F.pulse(group, player, now) and group.oddball.stage == "harass"
        and group.discovered == true and contains("greet", said(bernice)),
    "she announces herself once she can see the player at twelve meters")

-- Inside the throw band she lights the fuse first, then throws on a later tick.
bernice.x = 8
now = now + 2600
local before = #thrownItems
local handled, reason = tick()
assert(handled and reason == "bernice_lighting_fuse" and #thrownItems == before
        and bernice.sounds[#bernice.sounds] == "FireCrackerEquip" and stops >= 1,
    "the windup stops her, faces the player and lights the fuse without throwing")
now = now + 300
assert(select(2, tick()) == "bernice_lighting_fuse" and #thrownItems == before,
    "the fuse burns for the full windup")
now = now + 400
handled, reason = tick()
assert(handled and reason == "bernice_threw" and #thrownItems == before,
    "the firecracker leaves her hand and is still in the air")
assert(bernice.sounds[#bernice.sounds] == "FireCrackerThrow", "the stock throw sound plays")
assert(count("Base.Firecracker") == 9 and group.oddball.thrown == 1,
    "the thrown firecracker leaves her inventory")
assert(contains("throw", said(bernice)), "she yells as she throws")
assert(fellow.lastLine and contains("fellowThrow", said(fellow)),
    "a nearby companion reacts once to the first firecracker")
now = now + 300
tick()
assert(#thrownItems == before, "it does not land before its flight time")
now = now + 300
tick()
assert(#thrownItems == before + 1, "it lands once its flight is over")
local first = thrownItems[#thrownItems]
assert(first.item.kind == "Base.Firecracker"
        and first.item.data.lfFirecrackerGroupId == group.id and first.actor == bernice
        and first.square.x == player.square.x and first.square.y == player.square.y,
    "her own tagged firecracker lands on the player's square as the game's own trap")
assert(first.exploded == true, "a firecracker goes off the moment it lands")

-- The cooldown keeps her from emptying the box in one breath.
now = now + 1000
tick()
assert(#thrownItems == before + 1, "no second throw inside the cooldown")

-- No throw without sight, and none from too close or too far.
now = now + 20000
visibleToBernice = false
tick()
assert(#thrownItems == before + 1, "no throw without line of sight")
visibleToBernice = true
bernice.x = 2
bernice.lastLine = nil
tick()
assert(#thrownItems == before + 1 and contains("close", said(bernice))
        and requests[#requests].options.action == "faction_retreat"
        and requests[#requests].square.x > bernice.x,
    "too close, she warns and backs away from the player instead of throwing")
bernice.x = 14
tick()
assert(#thrownItems == before + 1
        and requests[#requests].options.action == "faction_follow"
        and requests[#requests].options.arrivalDistance == 7,
    "beyond the throw band she closes in to a seven meter hold")

-- Without the game's trap class she spends nothing.
bernice.x = 8
IsoTrap = nil
now = now + 20000
tick()
now = now + 700
handled, reason = tick()
assert(reason == "bernice_native_trap_unavailable" and count("Base.Firecracker") == 9,
    "no throw spends a firecracker that could not land")
IsoTrap = trapClass

-- Seeing the player through a window is not a throw. She never lobs one into
-- a house from outside; she keeps coming instead.
now = now + 20000
local windowed = #thrownItems
player.square.room = "kitchen"
handled, reason = tick()
assert(handled and reason ~= "bernice_lighting_fuse"
        and requests[#requests].options.action == "faction_follow"
        and requests[#requests].options.arrivalDistance == 0.85,
    "a player indoors is followed, not bombarded through the glass")
now = now + 700
tick()
assert(#thrownItems == windowed, "no firecracker goes through a window")
-- Inside one room the lob is fair.
bernice.square = { x = 8, y = 0, z = 0, room = "kitchen" }
tick()
now = now + 700
tick()
now = now + 700
tick()
assert(#thrownItems == windowed + 1, "in the same room she throws")
bernice.square, player.square.room = nil, nil

-- The tell-her-to-stop choice gets an answer and changes nothing.
local options = F.menuOptions(group, player)
assert(#options == 1 and options[1].id == "tell_bernice_stop")
assert(F.action(group, "tell_bernice_stop", player))
assert(contains("stop", said(bernice)), "she refuses in her own words")

-- Throw until two remain; the low lines take over.
local function throwOnce()
    now = now + 20000
    tick()
    now = now + 700
    return tick()
end
while count("Base.Firecracker") > 2 do throwOnce() end
bernice.lastLine = nil
throwOnce()
assert(count("Base.Firecracker") == 1 and contains("low", said(bernice)),
    "with two or fewer left she says so")

-- The clean twin is used with profanity disabled.
profanityEnabled = false
for index, entry in ipairs(LINES.throw) do
    if type(entry) == "table" then
        group.oddball.lines.throw = index - 1
        break
    end
end
group.oddball.lines.low = 0
-- Force a throw line: three spare tagged firecrackers keep her above the
-- low-stock pool for this one check.
for _ = 1, 3 do
    local spare = SC.GameplayUtil.addItem(bernice.inv, "Base.Firecracker")
    spare.data.lfFirecrackerGroupId = group.id
end
bernice.lastLine = nil
throwOnce()
local cleanLine = said(bernice)
local cleanFound = false
for _, entry in ipairs(LINES.throw) do
    if type(entry) == "table" and entry.clean == cleanLine then cleanFound = true end
end
assert(cleanFound, "a rough throw line falls back to its clean twin: " .. tostring(cleanLine))
profanityEnabled = true

-- The last firecracker ends the show.
while count("Base.Firecracker") > 0 do throwOnce() end
assert(group.oddball.stage == "fleeing" and group.oddball.fleeReason == "empty",
    "an empty box sends her running")
local intent = F.intentFor(bernice, player, {}, group)
assert(intent.mode == "firecracker_flee" and intent.priority > 90)
bernice.lastLine = nil
local requestCount = #requests
assert(tick(intent))
assert(contains("empty", said(bernice)), "she announces the end of the show")
local run = requests[#requests]
assert(#requests == requestCount + 1 and run.gait == "run"
        and run.options.action == "faction_retreat" and run.square.x > bernice.x,
    "she runs away from the player")
tick(intent)
assert(bernice.lastLine == nil and #requests == requestCount + 2
        and requests[#requests].square.x == run.square.x,
    "the exit line is said once and the escape target holds steady")

-- She vanishes only after the player has lost sight of her.
visibleToPlayer = true
assert(F.pulse(group, player, now))
assert(not hibernated and contains("fellowGone", said(fellow)),
    "in view she keeps running; a companion remarks on it once")
visibleToPlayer = false
assert(F.pulse(group, player, now))
assert(not hibernated, "a blink out of view is not enough")
now = now + 4100
assert(F.pulse(group, player, now))
assert(hibernated and retiredReason == "ran_off" and group.lifecycle == "destroyed",
    "unseen for four seconds, she is gone for good")

-- A second Bernice: the dead close in before she runs out.
F._resetForTests()
local zombieGroup = { id = "bernice-group", standing = "Neutral",
    members = { { actorId = "bernice" } },
    oddball = { id = "firecracker_bernice_hupp", stage = "harass", thrown = 3,
        stockSeeded = true, site = { kind = "roamer" } } }
group = zombieGroup
hibernated = false
local far = { actor = { x = 30, y = 0, z = 0 } }
assert(F.intentFor(bernice, player, { threats = { far } }, zombieGroup).mode
        == "firecracker_harass", "a walker twenty meters off does not scare her yet")
local near = { actor = { x = bernice.x + 5, y = 0, z = 0 } }
intent = F.intentFor(bernice, player, { threats = { far, near } }, zombieGroup)
assert(intent.mode == "firecracker_flee" and zombieGroup.oddball.fleeReason == "zombies"
        and zombieGroup.oddball.fleeFrom.x == near.actor.x,
    "a walker inside twelve meters turns the show into a retreat")
bernice.lastLine = nil
tick(intent)
assert(contains("zombies", said(bernice)))
assert(requests[#requests].square.x < near.actor.x,
    "she runs away from the walker, not from the player")

-- A blow sends her running without making her a fighter.
local hurtGroup = { id = "bernice-group", standing = "Neutral",
    members = { { actorId = "bernice" } },
    oddball = { id = "firecracker_bernice_hupp", stage = "harass", thrown = 0,
        stockSeeded = true, site = { kind = "roamer" } } }
local accepted, why = F.action(hurtGroup, "hurt", player)
assert(accepted == true and why == "bernice_flees_the_blow"
        and hurtGroup.oddball.stage == "fleeing"
        and hurtGroup.oddball.fleeReason == "hurt",
    "being struck is handled by the story and starts her flight")
assert(F.avoidsZombieCombat() == true and select(1, F.canRecruit()) == false)

-- Losing the player for two hours ends the encounter once she is unseen.
local lostGroup = { id = "bernice-group", standing = "Neutral",
    members = { { actorId = "bernice" } },
    oddball = { id = "firecracker_bernice_hupp", stage = "harass", thrown = 0,
        stockSeeded = true, site = { kind = "roamer" } } }
group = lostGroup
hibernated, retiredReason = false, nil
player.x = 200
visibleToPlayer = false
assert(F.pulse(lostGroup, player, now))
assert(not hibernated and lostGroup.oddball.lostSinceHour == hour)
hour = hour + 2
assert(F.pulse(lostGroup, player, now))
now = now + 4100
assert(F.pulse(lostGroup, player, now))
assert(hibernated and retiredReason == "lost_interest",
    "a long-lost player ends her pursuit without a scene")

print("Firecracker PASS: ten tagged firecrackers, native throw after a lit fuse, cooldown, sight and range, low and clean lines, three exits, unseen departure")
