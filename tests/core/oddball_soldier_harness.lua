-- SPDX-License-Identifier: MIT
local SC = SurvivorCompanion
local now = 4000000
local hours = 24 * 6 + 3 -- day six, 03:00
local player = { id = "player", x = 0, y = 0, z = 0, inv = { items = {} } }
local hatcher = { id = "hatcher", x = 500, y = 0, z = 0, inv = { items = {} } }
local fellow = { id = "fellow", x = 1, y = 1, z = 0 }
local radioData = { on = true, battery = true, power = 0.8, channel = 146600,
    twoWay = true, range = 8000, muted = false, noTransmit = false }
local playerRadio = { __class = "Radio", data = radioData }
player.inv.owner = player
playerRadio.container = player.inv
player.secondary = playerRadio
local walkieData = { range = 16000 }
local zombies = {
    { x = 510, y = 0, z = 0 }, { x = 470, y = 20, z = 0 }, { x = 530, y = 0, z = 0 },
    { x = 545, y = 0, z = 0 }, { x = 505, y = 5, z = 0, dead = true },
}
local hatcherLoaded = true
local sent = {}
local marks = {}
local cacheContainer = { items = {} }
local cacheHouse = { anchor = { x = 560, y = 40, z = 0 }, questContainer = { x = 561, y = 41 },
    bounds = {} }
local houseAvailable = true

getZomboidRadio = function()
    return { SendTransmission = function(self, x, y, channel, text, guid, code, r, g, b, range, tv)
        sent[#sent + 1] = { x = x, y = y, channel = channel, text = text, code = code,
            range = range, tv = tv }
    end }
end
getGameTime = function() return {} end
getClimateManager = function()
    local today, tomorrow = { name = "Clear" }, { name = "Light Rain" }
    local forecasts = { today, tomorrow }
    return { getClimateForecaster = function()
        return { getForecasts = function()
            return { size = function() return #forecasts end,
                get = function(_, index) return forecasts[index + 1] end }
        end }
    end }
end
getCell = function() return { getZombieList = function() return zombies end } end

SC.GameplayUtil = {
    config = function() return nil end,
    nowMs = function() return now end,
    isValidActor = function(value) return value ~= nil end,
    isDead = function(value) return value == nil or value.dead == true end,
    idOf = function(value) return value and value.id end,
    instanceOf = function(value, name) return type(value) == "table" and value.__class == name end,
    position = function(value) return value.x, value.y, value.z end,
    distance = function(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end,
    sameFloor = function(a, b) return (a.z or 0) == (b.z or 0) end,
    canSee = function() return true end,
    gridSquare = function(x, y, z) return { x = x, y = y, z = z or 0 } end,
    inventory = function(value) return value.inv end,
    inventoryItemsDeep = function(inv) return inv.items end,
    itemType = function(item) return item.kind end,
    addItem = function(inv, kind)
        local item = { kind = kind, data = {} }
        if kind == "Base.WalkieTalkie5" then item.device = walkieData end
        inv.items[#inv.items + 1] = item
        return item
    end,
    modData = function(item) return item.data end,
    say = function(actor, line) actor.lastLine = line return true end,
    call = function(value, method, ...)
        local a = ...
        if method == "getWorldAgeHours" then return hours, true end
        if value == player then
            if method == "getInventory" then return player.inv, true end
            if method == "getEquipedRadio" then return player.secondary, true end
            if method == "getSecondaryHandItem" then return player.secondary, true end
            if method == "getPrimaryHandItem" then return nil, true end
            if method == "getClothingItem_Back" then return nil, true end
        end
        if value == playerRadio then
            if method == "getContainer" then return playerRadio.container, true end
            if method == "getDeviceData" then return radioData, true end
        end
        if value == radioData then
            local map = { getIsTurnedOn = radioData.on, getHasBattery = radioData.battery,
                getPower = radioData.power, getChannel = radioData.channel,
                getIsTwoWay = radioData.twoWay, getTransmitRange = radioData.range,
                getMicIsMuted = radioData.muted, isNoTransmit = radioData.noTransmit }
            return map[method], true
        end
        if type(value) == "table" and value.device and method == "getDeviceData" then
            return value.device, true
        end
        if value == walkieData and method == "getTransmitRange" then return walkieData.range, true end
        if type(value) == "table" and type(value[method]) == "function" then
            return value[method](value, ...), true
        end
        if type(value) == "table" and method == "getName" then return value.name, true end
        if method == "setPrimaryHandItem" then value.primary = a return nil, true end
        return nil, false
    end,
}
SC.NativeList = {
    size = function(list) return #list end,
    get = function(list, index) return list[index + 1] end,
}
local group = { id = "hatcher-group", standing = "Neutral", members = { { actorId = "hatcher" } },
    lifecycle = "active",
    oddball = { id = "forest_soldier_hatcher", stage = "unmet", site = { kind = "resident",
        anchor = { x = 502, y = 0, z = 0 }, spawn = { x = 500, y = 0, z = 0 } } } }
SC.Registry = {
    byId = function(id)
        if id == "hatcher" and hatcherLoaded then return { actor = hatcher } end
        if id == "fellow" then return { actor = fellow, recruited = true } end
        return nil
    end,
    living = function() return { hatcher, fellow } end,
}
SC.Factions = {
    group = function(id) return id == group.id and group or nil end,
    list = function() return { group } end,
    findHouse = function(_, options)
        assert(options.purpose == "quest" and options.sourceFactionId == group.id)
        return houseAvailable and cacheHouse or nil
    end,
    resolveQuestContainer = function(locator)
        assert(locator == cacheHouse.questContainer)
        return cacheContainer
    end,
    describeLocation = function(position)
        if position == cacheHouse.anchor then return { address = "114 Dogwood Lane" } end
        return { address = "the Tanner Road" }
    end,
}
SC.FactionLife = { addMapAnnotation = function(text, x, y)
    marks[#marks + 1] = { text = text, x = x, y = y }
    return true
end }

local S = SC.OddballSoldier
local LINES = S.LINES

local function lastSent() return sent[#sent] end
local function drain()
    for _ = 1, 12 do
        now = now + 10100
        S.pulse(group, player, now)
        if #group.oddball.pending == 0 then return end
    end
    error("radio queue never drained")
end

-- Every line: ASCII, short, no game words.
do
    local banned = { "tile", "player", "save", "mod", "moodle", "reload", "game" }
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
        for index, line in ipairs(list) do lint(line, pool .. "[" .. index .. "]") end
    end
    for topic, line in pairs(S.PLAYER_LINES) do lint(line, "player " .. topic) end
end

-- Kit: the rifle in hand and the rest on him, once.
assert(S.onSpawn(group, hatcher))
assert(hatcher.primary and hatcher.primary.kind == "Base.AssaultRifle", "M16 in hand")
local kinds = {}
for _, item in ipairs(hatcher.inv.items) do kinds[item.kind] = (kinds[item.kind] or 0) + 1 end
assert(kinds["Base.556Clip"] == 3 and kinds["Base.WalkieTalkie5"] == 1
        and kinds["Base.EntrenchingTool"] == 1 and kinds["Base.MilitaryMedal"] == 1,
    "magazines, walkie, shovel and the medal he won't talk about")
local carried = #hatcher.inv.items
assert(S.onSpawn(group, hatcher) and #hatcher.inv.items == carried, "no second kit on reload")
assert(S.transmitRange(group) == 16000, "his range is the army walkie's")

-- 03:00: the slot already passed is skipped; at 06:00 the first broadcast.
S.pulse(group, player, now)
assert(#sent == 0 and group.oddball.lastSlot == 24 * 5 + 20)
hours = 24 * 6 + 6.2
now = now + 1000
S.pulse(group, player, now)
drain()
assert(sent[1].channel == 90000 and sent[1].text == LINES.cutIn[1],
    "the first time, he cuts in on 90 MHz to point people at his channel")
assert(sent[2].channel == 146600 and sent[2].text == LINES.morning[1], "then the morning sitrep")
assert(sent[3].text == "Walkers in sight of my position: 3.",
    "only the living within forty meters are counted: " .. sent[3].text)
assert(sent[4].text == "Tomorrow looks like Light Rain.", "the game's forecast for tomorrow")
assert(sent[5] and sent[5].range == 16000 and sent[5].x == 500 and #sent == 5,
    "a closing line, all from his position with his range")
local count = #sent
hours = 24 * 6 + 20.5
now = now + 1000
S.pulse(group, player, now)
drain()
assert(sent[count + 1].text == LINES.evening[1] and sent[count + 1].channel == 146600,
    "evening sitrep, no second cut-in")

-- Far out of the loaded world: no count, still on the air from his camp.
hatcherLoaded = false
hours = 24 * 7 + 6.5
now = now + 1000
count = #sent
S.pulse(group, player, now)
drain()
assert(sent[count + 2].text == LINES.noCount[1] and sent[count + 2].x == 500
        and sent[count + 2].range == 16000, "unloaded: an honest no-count from the saved camp")
hatcherLoaded = true

-- The radio menu only appears with a working set on 146.6, in range.
radioData.channel = 90000
assert(#S.radioOptions(player) == 0, "wrong channel, no options")
radioData.channel = 146600
radioData.twoWay = false
assert(#S.radioOptions(player) == 0, "a receive-only set cannot call him")
radioData.twoWay = true
local options = S.radioOptions(player)
assert(#options == 1 and options[1].topic == "identify"
        and options[1].label == "146.6: Ask who's broadcasting", "he is a voice until he says his name")
player.x = -9000
assert(#S.radioOptions(player) == 0, "beyond ninety percent of the player's range")
player.x = 0

-- Calling: the player's line goes out on the air; his answer follows.
count = #sent
assert(S.call(group.id, "identify", player))
assert(sent[count + 1].text == S.PLAYER_LINES.identify and sent[count + 1].x == 0
        and sent[count + 1].range == 8000, "the player's own transmission, from the player's set")
now = now + 5100
S.pulse(group, player, now)
assert(lastSent().text == LINES.identify[1] and group.oddball.trust == 1
        and group.oddball.identified == true, "Hatcher, and one step of trust")
options = S.radioOptions(player)
assert(#options == 2 and options[1].topic == "fence", "now the fence and a sitrep")
assert(select(1, S.call(group.id, "supplies", player)) == false, "supplies are not offered yet")

-- Same day: more talk, no more trust.
assert(S.call(group.id, "fence", player))
now = now + 5100
S.pulse(group, player, now)
assert(lastSent().text == LINES.fence[1] and group.oddball.trust == 1)

-- Chatter: the fourth call in one hour gets radio discipline and silence.
assert(S.call(group.id, "sitrep", player))
assert(S.call(group.id, "sitrep", player))
drain()
assert(lastSent().text == LINES.silent[1], "too many calls in an hour")
assert(#S.radioOptions(player) == 0, "he is quiet until tomorrow morning")

-- Next morning: a sitrep call, trust two, and supplies on the table.
hours = 24 * 8 + 7
now = now + 1000
S.pulse(group, player, now)
drain()
assert(S.call(group.id, "sitrep", player))
drain()
assert(group.oddball.trust == 2
        and sent[#sent].text == "Walkers in sight: 3. Tomorrow looks like Light Rain. Out.",
    "a live sitrep on request")
houseAvailable = false
assert(S.call(group.id, "supplies", player))
drain()
assert(lastSent().text == LINES.noCache[1] and group.oddball.cacheGiven ~= true,
    "no house in reach: an honest not today")
houseAvailable = true
hours = hours + 1
assert(S.call(group.id, "supplies", player))
drain()
assert(lastSent().text == "Write this down. 114 Dogwood Lane. Inside. Take what you need, not all of it. Out.")
assert(#cacheContainer.items == #S.CACHE_ITEMS and cacheContainer.items[1].data.lfHatcherCacheGroupId == group.id,
    "the cache is real items in a real container")
assert(marks[1].text == "[LF] Hatcher's cache" and marks[1].x == 560, "and it is on the map")
hours = hours + 1
assert(S.call(group.id, "supplies", player))
drain()
assert(lastSent().text == LINES.suppliesAgain[1] and #cacheContainer.items == #S.CACHE_ITEMS,
    "one cache, never restocked")

-- Third day of contact: an invitation and his camp on the map.
hours = 24 * 9 + 7
now = now + 1000
S.pulse(group, player, now)
drain()
assert(S.call(group.id, "sitrep", player))
drain()
assert(group.oddball.trust == 3)
options = S.radioOptions(player)
assert(options[#options].topic == "meet")
assert(select(1, S.canRecruit(group)) == false, "not before he has met you")
assert(S.call(group.id, "meet", player))
drain()
assert(lastSent().text == "My camp's in the woods off the Tanner Road. Come slow. Hands empty. Out."
        and group.oddball.invited == true and marks[2].text == "[LF] Hatcher's camp",
    "the camp, with the nearest road")

-- In person, invited: he expects you.
player.x = 495
fellow.x = 494
S.pulse(group, player, now)
assert(group.oddball.met == true and hatcher.lastLine == LINES.invited[1])
assert(S.canRecruit(group) == true, "three days of radio and one visit")
assert(#S.menuOptions(group, player) == 0, "five meters is not conversation distance")
player.x = 497
assert(S.action(group, "ask_hatcher_woods", player) and hatcher.lastLine == LINES.woods[1])
assert(S.action(group, "ask_hatcher_kit", player) and hatcher.lastLine == LINES.kit[1])
assert(select(1, S.action(group, "hurt", player)) == false, "hitting him is an offense like any other")

-- A stranger walking into an uninvited camp gets told to go, and how to call.
local stranger = { id = "hatcher-group", standing = "Neutral", members = { { actorId = "hatcher" } },
    lifecycle = "active",
    oddball = { id = "forest_soldier_hatcher", stage = "unmet", site = group.oddball.site } }
hatcher.lastLine = nil
S.pulse(stranger, player, now)
assert(hatcher.lastLine == LINES.uninvited[1] and stranger.oddball.met ~= true)
now = now + 3100
S.pulse(stranger, player, now)
assert(hatcher.lastLine == LINES.frequency[1], "then the frequency")
assert(select(1, S.canRecruit(stranger)) == false)

print("Soldier PASS: kit, cut-in and sitreps with real counts and forecast, radio gating, calls, trust by day, discipline, real cache, invitation, meeting")
