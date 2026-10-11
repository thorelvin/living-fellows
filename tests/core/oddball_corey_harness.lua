-- SPDX-License-Identifier: MIT
local SC = SurvivorCompanion
local hour = 24
local player = { id = "player", x = 0, y = 0, z = 0 }
local corey = { id = "corey", x = 15, y = 0, z = 0,
    inv = { items = {} } }
local group = { id = "corey-group", standing = "Neutral",
    members = { { actorId = "corey" } }, oddball = {
        id = "fan_corey_biggs", stage = "unmet",
        initialTale = "the Battle of the Gas Station",
        site = { kind = "roamer", spawn = { x = 15, y = 0, z = 0 } } } }
local zombie = { id = "zombie", square = {
    room = { name = "gasstation" } } }
local navigationCount = 0
local cancelledCount = 0
local activeRoute
local lastArrivalDistance
local hibernated = false
local visible = true
local profanityEnabled = true
SC.GameplayUtil = {
    config = function(name)
        if name == "profanityEnabled" then return profanityEnabled end
        return nil
    end,
    isValidActor = function(value) return value ~= nil end,
    position = function(value) return value.x, value.y, value.z end,
    distance = function(a, b)
        return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2
            + ((a.z or 0) - (b.z or 0)) ^ 2 * 9)
    end,
    sameFloor = function(a, b) return a.z == b.z end,
    canSee = function() return visible end,
    inventory = function(value) return value.inv end,
    inventoryItemsDeep = function(inv) return inv.items end,
    addItem = function(inv, kind)
        local item = { kind = kind, data = {} }
        inv.items[#inv.items + 1] = item
        return item
    end,
    modData = function(item) return item.data end,
    squareOf = function(value) return { x = value.x, y = value.y, z = value.z } end,
    gridSquare = function(x, y, z) return { x = x, y = y, z = z } end,
    say = function(value, line) value.lastLine = line return true end,
    call = function(value, method, ...)
        if method == "getWorldAgeHours" then return hour, true end
        if method == "getSquare" then return value.square, true end
        if method == "getRoom" then return value.room, true end
        if method == "getName" then return value.name, true end
        if method == "setName" then value.name = (...) return true, true end
        return nil, false
    end,
}
SC.Tales = { title = function(tale)
    assert(tale.place == "gasstation")
    return "the Battle of the Gas Station"
end }
SC.Registry = { byId = function(id)
    return id == "corey" and not hibernated and { actor = corey } or nil
end }
SC.Navigation = { request = function(actor, square, gait, options)
    assert(actor == corey and square.x == player.x
        and (gait == "walk" or gait == "jog"))
    assert(options.action == "faction_follow"
        and options.player == player and options.followRecovery == true
        and options.movingTarget == true and options.continuousApproach == true)
    navigationCount = navigationCount + 1
    lastArrivalDistance = options.arrivalDistance
    activeRoute = { goalAction = options.action }
    return true, "moving"
end, peek = function() return activeRoute end,
cancel = function(actor, reason)
    assert(actor == corey and reason == "fan_holding_distance")
    activeRoute = nil
    cancelledCount = cancelledCount + 1
    return true
end }
SC.Factions = { hibernateOddballRoamer = function(id)
    assert(id == group.id)
    hibernated = true
    return true
end, forceStanding = function() return true end }
SC.Oddballs = { retire = function(value, reason)
    assert(value == group and reason == "gave_up")
    return true
end }
getGameTime = function() return {} end

local Corey = SC.OddballCorey
assert(Corey.onSpawn(group, corey))
assert(corey.inv.items[1].kind == "Base.Notebook")
assert(corey.inv.items[1].data.lfCoreyTales[1]
    == "the Battle of the Gas Station")
assert(Corey.pulse(group, player))
assert(group.discovered ~= true and corey.lastLine == nil,
    "Corey must not call out from his distant spawn")
assert(Corey.noteKill(group, player, zombie))
assert(#group.oddball.tales == 2)
local intent = Corey.intentFor(corey, player, {}, group)
assert(Corey.update(corey, player, {}, intent, group))
assert(navigationCount == 1 and activeRoute and lastArrivalDistance == 5)
corey.x = 5
visible = false
assert(Corey.pulse(group, player))
assert(group.oddball.greeted ~= true)
assert(Corey.update(corey, player, {}, intent, group))
assert(navigationCount == 2 and cancelledCount == 0
    and lastArrivalDistance == 0.85,
    "Corey must route through a wall instead of holding in greeting range")
corey.x, corey.z = 0, 1
visible = true
assert(Corey.update(corey, player, {}, intent, group))
assert(navigationCount == 3 and cancelledCount == 0
    and lastArrivalDistance == 0.85,
    "Corey must route between floors instead of holding above the player")
corey.z = 0
corey.x = 6
assert(Corey.pulse(group, player))
assert(group.discovered == true and corey.lastLine ~= nil,
    "Corey should introduce himself when close enough to hear")
assert(Corey.update(corey, player, {}, intent, group))
assert(cancelledCount == 1 and navigationCount == 3,
    "holding the trailing distance must cancel the old follow route")
corey.x = 10
visible = false
assert(Corey.update(corey, player, {}, intent, group))
assert(navigationCount == 4 and cancelledCount == 1
    and lastArrivalDistance == 0.85,
    "an introduced Corey must keep following when a wall blocks sight")
visible = true
corey.x = 20
assert(Corey.update(corey, player, {}, intent, group))
assert(navigationCount == 5 and lastArrivalDistance == 8)
corey.lastLine = nil
assert(Corey.noteKill(group, player, zombie))
assert(#group.oddball.tales == 3 and corey.lastLine == nil,
    "Corey may record a distant kill without shouting the third tale")
do
    local savedStory, savedX, savedLine = group.oddball, corey.x, corey.lastLine
    local value = {}
    for key, entry in pairs(savedStory) do value[key] = entry end
    value.tales, value.diaryOpeningIndex = { value.initialTale }, nil
    group.oddball, corey.x = value, 5
    local tale = "the Battle of the Gas Station"
    local seenOpenings = {}
    local function openingOf(line)
        assert(type(line) == "string", "a nearby Corey speaks each diary milestone")
        local at = string.find(line, tale, 1, true)
        assert(at and not string.find(line, ". the ", 1, true),
            "Corey's diary opening leads into the lowercase tale: " .. line)
        assert(not string.find(line, "[^\032-\126]"),
            "Corey's spoken diary line uses printable ASCII: " .. line)
        return string.sub(line, 1, at - 1)
    end
    local function writeUntil(count)
        corey.lastLine = nil
        while #value.tales < count do assert(Corey.noteKill(group, player, zombie)) end
        local line = corey.lastLine
        seenOpenings[openingOf(line)] = true
        return line
    end
    local third, sixth = writeUntil(3), writeUntil(6)
    assert(openingOf(third) ~= openingOf(sixth),
        "Corey's third and sixth diary milestones use different openings")
    writeUntil(9)
    local previous = writeUntil(12)
    for _ = 1, 7 do
        assert(Corey.noteKill(group, player, zombie))
        local line = corey.lastLine
        local opening = openingOf(line)
        assert(opening ~= openingOf(previous),
            "Corey's diary openings keep rotating after the twelve-tale cap")
        assert(#value.tales == 12 and corey.inv.items[1].data.lfCoreyTales == value.tales,
            "diary rotation preserves the bounded notebook history")
        seenOpenings[opening], previous = true, line
    end
    local distinct = 0
    for _ in pairs(seenOpenings) do distinct = distinct + 1 end
    assert(distinct == 6, "all six Corey openings remain accessible; actual=" .. tostring(distinct))

    -- A restored story carries the last opening independently of its capped tales.
    local restored = {}
    for key, entry in pairs(value) do restored[key] = entry end
    group.oddball = restored
    assert(Corey.noteKill(group, player, zombie))
    assert(restored.diaryOpeningIndex == value.diaryOpeningIndex % 6 + 1
            and openingOf(corey.lastLine) ~= openingOf(previous),
        "the saved diary opening index resumes without repeating the last line")
    value = restored

    value.diaryOpeningIndex = 5
    profanityEnabled = false
    assert(Corey.noteKill(group, player, zombie))
    local cleanSixth = corey.lastLine
    assert(value.diaryOpeningIndex == 6 and string.find(cleanSixth, "heck", 1, true)
            and not string.find(string.lower(cleanSixth), "%f[%a]hell%f[%A]"),
        "Corey's sixth opening uses its clean twin with profanity disabled: " .. cleanSixth)
    openingOf(cleanSixth)
    value.diaryOpeningIndex, profanityEnabled = 5, true
    assert(Corey.noteKill(group, player, zombie))
    assert(corey.lastLine == string.gsub(cleanSixth, "heck", "hell", 1),
        "Corey's rough and clean sixth openings retain the same tale and rhythm")

    value.diaryOpeningIndex = "unreadable saved index"
    local safe, recorded = pcall(Corey.noteKill, group, player, zombie)
    assert(safe and recorded == true,
        "a corrupted saved opening index cannot interrupt Corey's diary")
    openingOf(corey.lastLine)

    group.oddball, corey.x, corey.lastLine = savedStory, savedX, savedLine
    corey.inv.items[1].data.lfCoreyTales = savedStory.tales
end
player.x = 150
visible = false
assert(Corey.pulse(group, player))
hour = 24 * 5
assert(Corey.pulse(group, player))
assert(group.lifecycle == "destroyed" and hibernated)
print("Corey PASS: close speech, wall/floor routing, smooth follow intent, route hold, diary, three-day departure")
