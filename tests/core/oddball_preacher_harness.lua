-- SPDX-License-Identifier: MIT
local SC = SurvivorCompanion
local now = 2000000
local hours = 24 * 5 + 9 -- day five, 09:00: the 08:00 slot has passed
local player = { id = "player", x = 0, y = 0, z = 0, inv = { items = {} } }
local dwayne = { id = "dwayne", x = 30, y = 0, z = 0, inv = { items = {} } }
local fellow = { id = "fellow", x = 1, y = 1, z = 0 }
player.inv.owner, dwayne.inv.owner = player, dwayne
local radioData = { range = 20000 }
local van = { x = 32, y = 0, z = 0, sqlId = 7001 }
local vanLoaded = true
local spawnedVans = {}
local sent = {}
local visible = true

IsoDirections = { N = "north" }
addVehicleDebug = function(script, facing, _, square)
    spawnedVans[#spawnedVans + 1] = { script = script, facing = facing, square = square }
    return van
end
getZomboidRadio = function()
    return { SendTransmission = function(self, x, y, channel, text, guid, code, r, g, b, range, tv)
        sent[#sent + 1] = { x = x, y = y, channel = channel, text = text, guid = guid,
            code = code, range = range, tv = tv }
    end }
end
getGameTime = function() return {} end

SC.GameplayUtil = {
    config = function() return nil end,
    nowMs = function() return now end,
    isValidActor = function(value) return value ~= nil end,
    isDead = function(value) return value == nil end,
    idOf = function(value) return value and value.id end,
    position = function(value) return value.x, value.y, value.z end,
    distance = function(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end,
    sameFloor = function(a, b) return a.z == b.z end,
    canSee = function() return visible end,
    gridSquare = function(x, y, z) return { x = x, y = y, z = z } end,
    inventory = function(value) return value.inv end,
    inventoryItemsDeep = function(inv) return inv.items end,
    itemType = function(item) return item.kind end,
    itemName = function(item) return item.label or item.kind end,
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
    say = function(actor, line) actor.lastLine = line return true end,
    call = function(value, method, a, b)
        if method == "getWorldAgeHours" then return hours, true end
        if value == van then
            if method == "getSqlId" then return van.sqlId, true end
            if method == "getPartById" and a == "Radio" then return { radioPart = true }, true end
        end
        if type(value) == "table" and value.radioPart then
            if method == "getDeviceData" then return radioData, true end
        end
        if value == radioData and method == "getTransmitRange" then return radioData.range, true end
        if method == "getContainer" then return value.container, true end
        if method == "setName" then value.name = a return nil, true end
        if method == "addPage" then value.pages[a] = b return nil, true end
        return nil, false
    end,
}
SC.Vehicle = { loadedBySqlId = function(id)
    return vanLoaded and id == van.sqlId and van or nil
end }
SC.Registry = {
    byId = function(id)
        if id == "dwayne" then return { actor = dwayne } end
        if id == "fellow" then return { actor = fellow, recruited = true } end
        return nil
    end,
    living = function() return { dwayne, fellow } end,
}

local P = SC.OddballPreacher

local function newGroup()
    return { id = "preacher-group", standing = "Neutral",
        members = { { actorId = "dwayne" } },
        oddball = { id = "radio_preacher_dwayne", stage = "unmet",
            site = { kind = "resident", spawn = { x = 30, y = 0, z = 0 },
                van = { x = 32, y = 0, z = 0 } } } }
end

-- Every spoken and broadcast line: ASCII, short, no game words, period-true.
do
    local banned = { "tile", "player", "save", "mod", "moodle", "reload", "game" }
    local modern = { "internet", "email", "cell phone", "website", "hits different", "google" }
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
            assert(not string.find(lower, word, 1, true), label .. " is period-true: " .. line)
        end
    end
    for number = 41, 52 do
        local sermon = P.SERMONS[number]
        assert(sermon and #sermon == 4, "sermon " .. number .. " has a title and three lines")
        for index, line in ipairs(sermon) do lint(line, "sermon " .. number .. "[" .. index .. "]") end
    end
    for category, lines in pairs(P.READINGS) do
        assert(#lines == 4, category .. " reading has four lines")
        for index, line in ipairs(lines) do lint(line, category .. "[" .. index .. "]") end
    end
    for pool, list in pairs(P.LINES) do
        for index, line in ipairs(list) do lint(line, pool .. "[" .. index .. "]") end
    end
end

assert(P.bookCategory("Base.Book_Bible") == "bible"
    and P.bookCategory("Base.Paperback_Bible") == "bible"
    and P.bookCategory("Base.Book_Cooking") == "cooking"
    and P.bookCategory("Base.Book_Farming") == "growing"
    and P.bookCategory("Base.Magazine_Car") == "engines"
    and P.bookCategory("Base.Magazine_Car_New") == "engines"
    and P.bookCategory("Base.Book_Military") == "soldiering"
    and P.bookCategory("Base.Book_Fiction") == "other",
    "the book decides what kind of reading goes on air")
for index = 1, 5 do
    assert(P.bookCategory("Base.BookMechanic" .. index) == "engines",
        "actual mechanics skill books receive engine readings")
    assert(P.bookCategory("Base.BookCarpentry" .. index) == "other"
            and P.bookCategory("Base.BookCarving" .. index) == "other",
        "carpentry and carving are not car manuals")
end
for index = 1, 3 do
    assert(P.bookCategory("Base.MechanicMag" .. index) == "engines",
        "actual mechanics recipe magazines receive engine readings")
end
assert(P.bookCategory("Base.Paperback_Scary") == "other"
        and P.bookCategory("Base.Book_Caravan") == "other",
    "the letters car in unrelated titles do not make them engine books")

local group = newGroup()
assert(P.onSpawn(group, dwayne))
assert(#spawnedVans == 1 and spawnedVans[1].script == "Base.VanRadio"
        and spawnedVans[1].square.x == 32 and group.oddball.vanSqlId == 7001,
    "one station van is spawned on the road site and remembered by its id")
local binder = dwayne.inv.items[1]
assert(binder and binder.kind == "Base.Notebook" and binder.name == "Reverend Mabry's last sermons"
        and string.find(binder.pages[1], "forty-one", 1, true)
        and string.find(binder.pages[12], "last one", 1, true),
    "the Reverend's twelve sermons are readable in a real binder")
assert(P.onSpawn(group, dwayne))
assert(#spawnedVans == 1 and #dwayne.inv.items == 1, "a setup retry never adds a second van or binder")
for _, hostility in ipairs({ "standing", "lifecycle", "permanentHostility" }) do
    group[hostility] = hostility == "standing" and "Hostile"
        or hostility == "lifecycle" and "hostile" or true
    local intent = P.intentFor(dwayne, player, {}, group)
    assert(intent.mode == "hostile" and intent.priority == 110,
        "hostile Dwayne delegates to human combat: " .. hostility)
    group.standing, group.lifecycle, group.permanentHostility = "Neutral", nil, nil
end

-- The first slot he sees has already passed: nothing until the next one.
assert(P.pulse(group, player, now))
assert(#sent == 0 and group.oddball.lastSlot == 24 * 5 + 8)
hours = 24 * 5 + 12.5
now = now + 1000
P.pulse(group, player, now)
assert(#sent == 0, "no broadcast between slots")

-- 13:00: sermon forty-one goes out line by line from the van.
hours = 24 * 5 + 13.1
local function drain()
    for _ = 1, 20 do
        now = now + 12100
        P.pulse(group, player, now)
        if group.oddball.airing == nil then return end
    end
    error("a broadcast never finished")
end
now = now + 1000
P.pulse(group, player, now)
drain()
assert(#sent == 6, "intro, title, three sermon lines and an outro: " .. #sent)
for index, entry in ipairs(sent) do
    assert(entry.channel == 103400 and entry.range == 20000 and entry.x == 32
            and entry.guid == "LF-GOSPEL-HOUR" and entry.code == "SERMON-41-" .. index
            and entry.tv == false,
        "every line is a native transmission on 103.4 from the van with its own range")
end
assert(sent[2].text == P.SERMONS[41][1] and sent[5].text == P.SERMONS[41][4],
    "the sermon is read in order")
assert(group.oddball.sermon == 42)
local count = #sent
now = now + 60000
P.pulse(group, player, now)
assert(#sent == count, "the same slot is never aired twice")

-- Lines are spaced out, not dumped at once.
hours = 24 * 5 + 19.2
now = now + 1000
P.pulse(group, player, now)
assert(#sent == count + 1)
now = now + 5000
P.pulse(group, player, now)
assert(#sent == count + 1, "twelve seconds between lines")
drain()

-- Without the van in reach, he still transmits from where it stood.
vanLoaded = false
hours = 24 * 6 + 8.5
now = now + 1000
P.pulse(group, player, now)
assert(sent[#sent].range == 7500 and sent[#sent].x == 32,
    "fallback: the smaller ham set's range from the saved van spot")
drain()
vanLoaded = true

-- Meeting him: greeting, the second line after a breath, a companion once.
assert(#P.menuOptions(group, player) == 0, "nothing to ask before you've met")
player.x = 25
fellow.x = 26
P.pulse(group, player, now)
assert(group.oddball.met == true and group.discovered == true and dwayne.lastLine == P.LINES.greet[1])
now = now + 2600
P.pulse(group, player, now)
assert(dwayne.lastLine == P.LINES.greet2[1] and fellow.lastLine ~= nil, "Dwayne finishes; a companion remarks")
fellow.lastLine = nil
now = now + 2600
P.pulse(group, player, now)
assert(fellow.lastLine == nil, "the companion remarks only once")

-- The menu, in reach only.
assert(#P.menuOptions(group, player) == 0, "five meters is too far for the menu")
player.x = 28
local options = P.menuOptions(group, player)
assert(#options == 3 and options[3].id == "give_dwayne_book" and options[3].enabled == false,
    "with no book, the offer is shown but cannot be made")
assert(P.action(group, "ask_dwayne_why", player))
assert(dwayne.lastLine == "Fifty-two sermons. He wrote one a week for a year. I'm on 44.",
    "he says the real next sermon number: " .. tostring(dwayne.lastLine))
assert(P.action(group, "ask_dwayne_reverend", player)
    and dwayne.lastLine == P.LINES.reverend[1])
assert(select(1, P.canRecruit(group)) == false, "not while tapes are left")

-- A real cookbook changes hands and decides what he reads later.
local cookbook = SC.GameplayUtil.addItem(player.inv, "Base.Book_Cooking")
cookbook.label = "The Joy of Cooking"
options = P.menuOptions(group, player)
assert(options[3].enabled == true and string.find(options[3].label, "The Joy of Cooking", 1, true))
assert(P.action(group, "give_dwayne_book", player))
assert(#player.inv.items == 0 and dwayne.inv.items[#dwayne.inv.items] == cookbook
        and group.oddball.bookCategory == "cooking" and dwayne.lastLine == P.LINES.book[1],
    "the exact book moves to Dwayne")
assert(select(1, P.action(group, "give_dwayne_book", player)) == false, "one book is enough")

-- Run the remaining sermons; with a book, no sign-off after fifty-two.
local function nextSlot()
    for _ = 1, 4 do
        hours = hours + 6
        now = now + 1000
        P.pulse(group, player, now)
        if group.oddball.airing then break end
    end
    drain()
end
while group.oddball.sermon <= 52 do nextSlot() end
for _, entry in ipairs(sent) do
    assert(entry.text ~= P.LINES.signOff[1], "with a book in hand he does not sign off yet")
end
nextSlot()
assert(sent[#sent - 4].text == P.READINGS.cooking[1] and group.oddball.readings == 1,
    "then he reads the listener's cookbook on air")
nextSlot()
nextSlot()
assert(sent[#sent].text == P.LINES.signOff[1] and group.oddball.stage == "silent",
    "after three readings, the Gospel Hour signs off")
count = #sent
nextSlot()
assert(#sent == count, "off the air for good")
assert(P.canRecruit(group) == true, "with nothing left to read, he can come along")
assert(P.action(group, "ask_dwayne_why", player) and dwayne.lastLine == P.LINES.whyDone[1])

-- A second Dwayne with no book signs off right after sermon fifty-two.
local quiet = newGroup()
quiet.oddball.vanAttempted = true
quiet.oddball.vanSqlId = 7001
quiet.oddball.sermon = 52
quiet.oddball.lastSlot = 0
group = quiet
sent = {}
nextSlot()
assert(sent[#sent].text == P.LINES.signOff[1] and quiet.oddball.stage == "silent",
    "no book: sermon fifty-two ends with the sign-off")
assert(#sent == 6, "intro, the title, three lines of the farewell note, and the sign-off: " .. #sent)

-- Native recipe-magazine names do not start with Book or Magazine.
local manualGroup = newGroup()
local manual = SC.GameplayUtil.addItem(player.inv, "Base.MechanicMag1")
assert(P.action(manualGroup, "give_dwayne_book", player)
        and manual.container == dwayne.inv and manualGroup.oddball.bookCategory == "engines",
    "a real mechanics recipe magazine is accepted and transferred as engine literature")
local carpentryGroup = newGroup()
local carpentry = SC.GameplayUtil.addItem(player.inv, "Base.BookCarpentry1")
assert(P.action(carpentryGroup, "give_dwayne_book", player)
        and carpentry.container == dwayne.inv and carpentryGroup.oddball.bookCategory == "other",
    "a carpentry book is still accepted without promising engine readings")

-- No native radio: nothing crashes, nothing is claimed.
getZomboidRadio = nil
local ok, reason = P.transmit(quiet.oddball, "test", "T")
assert(ok == false and reason == "native_radio_unavailable")

print("Preacher PASS: one van, binder, hostile combat, schedule, native transmissions with van range, fallback, meeting, menu, exact book categories, real books, readings, sign-off")
