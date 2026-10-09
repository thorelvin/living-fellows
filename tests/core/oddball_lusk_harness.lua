-- SPDX-License-Identifier: MIT
local SC = SurvivorCompanion
local clockHour, seen = 22, false
local lusk = { id = "lusk", x = 0, y = 0, z = 0 }
local player = { id = "player", x = 11, y = 0, z = 0,
    inv = { items = {} } }
local households = {
    a = { id = "a", name = "Oak family", lifecycle = "active",
        members = { { actorId = "oak" } } },
    b = { id = "b", name = "Elm family", lifecycle = "active",
        members = {} },
}
local group = { id = "lusk-group", standing = "Neutral",
    members = { { actorId = "lusk" } }, oddball = {
        id = "watcher_pettigrew_lusk", stage = "unmet", site = {
            spawn = { x = 0, y = 0, z = 0 }, neighbors = {
                { id = "a", name = "Oak family", x = 10, y = 0, z = 0 },
                { id = "b", name = "Elm family", x = 40, y = 0, z = 0 },
            } } } }
local reports = {}
SC.GameplayUtil = {
    isValidActor = function(v) return v ~= nil end,
    canSee = function(observer, target)
        if observer.id == "oak" then return seen end
        return observer.id == "player" and target.id == "lusk"
    end,
    distance = function(a, b)
        return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
    end,
    position = function(v) return v.x, v.y, v.z end,
    gridSquare = function(x, y, z) return { x = x, y = y, z = z } end,
    inventory = function(v) return v.inv end,
    addItem = function(inv, kind)
        local item = { kind = kind, data = {} }
        inv.items[#inv.items + 1] = item
        return item
    end,
    modData = function(item) return item.data end,
    say = function(v, line) if v then v.lastLine = line end return true end,
    nowMs = function() return 1000 end,
    call = function(v, method, ...)
        if method == "getTimeOfDay" then return clockHour, true end
        if method == "setName" then v.name = (...) return true, true end
        return nil, false
    end,
}
SC.Registry = { byId = function(id)
    if id == "lusk" then return { actor = lusk } end
    if id == "oak" then return { actor = {
        id = "oak", x = 10, y = 1, z = 0 } } end
    return nil
end }
SC.Factions = {
    group = function(id) return households[id] end,
    forceStanding = function(id, value)
        assert(id == group.id or id == "lusk-group-2")
        if id == group.id then group.standing = value end
        return true
    end,
}
SC.FactionWorld = { noteNeighborhoodReport = function(kind, a, b)
    reports[#reports + 1] = { kind = kind, a = a, b = b }
    return true
end }
getGameTime = function() return {} end

local Lusk = SC.OddballLusk
assert(Lusk.onSpawn(group, lusk))
assert(Lusk.pulse(group, player, 1000))
assert(group.discovered == nil)
assert(group.oddball.watchId == "a")
seen = true
Lusk.pulse(group, player, 61000)
assert(group.oddball.watched.a ~= true, "seen player cannot complete watch")
seen = false
Lusk.pulse(group, player, 62000)
Lusk.pulse(group, player, 122100)
assert(group.oddball.watched.a == true)
player.x = 39
clockHour = 12
Lusk.pulse(group, player, 123000)
assert(group.oddball.watchId == nil, "daylight cannot count")
clockHour = 22
Lusk.pulse(group, player, 124000)
Lusk.pulse(group, player, 184100)
assert(group.oddball.watched.b == true)
player.x = 1
local options = Lusk.menuOptions(group, player)
assert(#options == 5, "all three outcomes should be visible")
assert(Lusk.action(group, "accuse:a", player))
assert(group.oddball.stage == "accused")
assert(#player.inv.items == 1)
assert(player.inv.items[1].data.lfLuskTargetId == "a")
assert(#reports == 1 and reports[1].kind == "neighborhood_accusation")
local second = { id = "lusk-group-2", standing = "Neutral",
    members = group.members, oddball = { id = "watcher_pettigrew_lusk",
        stage = "watching", watched = { a = true, b = true },
        site = group.oddball.site } }
assert(Lusk.action(second, "report_lusk", player))
assert(second.oddball.stage == "reported")
assert(reports[2].kind == "neighborhood_warning")
print("Lusk PASS: night watch, unseen timer, kill list, household news")
