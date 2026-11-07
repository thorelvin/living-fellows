-- SPDX-License-Identifier: MIT
-- Garland Hatcher, Sergeant First Class (retired), ran the range at Fort
-- Knox and walked into the woods when the order came to fire on the fence.
-- He camps in a real forest clearing with a US Army walkie-talkie and sends
-- sitreps on 146.6 MHz at 06:00 and 20:00: walkers he can actually count and
-- the game's own forecast. A player with a two-way set on 146.6, in range
-- both ways, can call him. Trust grows one step per day of contact. He gives
-- a real supply cache, then his camp, then may join.

local SC = SurvivorCompanion
SC.OddballSoldier = SC.OddballSoldier or {}
local Soldier = SC.OddballSoldier

local ID = "forest_soldier_hatcher"
local CHANNEL = 146600
local CALLING_CHANNEL = 90000
local SLOT_HOURS = { 6, 20 }
-- The US Army walkie-talkie (WalkieTalkie5) reaches 16 km.
local FALLBACK_RANGE = 16000
local REPLY_DELAY_MS = 5000
local LINE_GAP_MS = 10000
local MAX_TRUST = 3
local CALLS_PER_HOUR = 3
local COUNT_RADIUS = 40
local NEAR_DISTANCE = 8
local MENU_DISTANCE = 4

local CACHE_ITEMS = {
    "Base.CanteenMilitaryFull", "Base.FirstAidKit_Military",
    "Base.WaterRationCan", "Base.WaterRationCan", "Base.556Box", "Base.PonchoGreen",
}
Soldier.CACHE_ITEMS = CACHE_ITEMS

local PERSONAL_KIT = {
    "Base.AssaultRifle", "Base.556Clip", "Base.556Clip", "Base.556Clip", "Base.556Box",
    "Base.Pistol", "Base.9mmClip", "Base.9mmClip", "Base.EntrenchingTool",
    "Base.WalkieTalkie5", "Base.Battery", "Base.Battery",
    "Base.CanteenMilitaryFull", "Base.FirstAidKit_Military",
    "Base.FlashLight_AngleHead_Army", "Base.CompassDirectional", "Base.Map",
    "Base.Matches", "Base.CigarettePack", "Base.MilitaryMedal", "Base.Hat_GasMask",
}
local KIT_COUNTS = {}
for _, kind in ipairs(PERSONAL_KIT) do KIT_COUNTS[kind] = (KIT_COUNTS[kind] or 0) + 1 end

local PLAYER_LINES = {
    identify = "Unknown station on one-four-six point six, identify yourself. Over.",
    fence = "Hatcher, what happened at the fence? Over.",
    sitrep = "Hatcher, requesting a sitrep. Over.",
    supplies = "Hatcher, we're short on supplies. Over.",
    meet = "Hatcher, can we meet? Over.",
}
Soldier.PLAYER_LINES = PLAYER_LINES

local LINES = {
    cutIn = { "Anybody on this channel, go to one-four-six point six. Repeat, one-four-six point six." },
    morning = { "Hatcher. Morning sitrep." },
    evening = { "Hatcher. Evening sitrep." },
    count = { "Walkers in sight of my position: %d." },
    noCount = { "No count this time. Out of sight lines." },
    weather = { "Tomorrow looks like %s." },
    closing = {
        "Nobody's coming. Plan accordingly. Out.",
        "Keep your head down and your powder dry. Out.",
        "Radio discipline, people. Hatcher out.",
        "If you can hear this, you're doing better than most. Out.",
    },
    identify = {
        "Hatcher. Sergeant First Class, retired. I ran the range at Fort Knox. That's all you get today. Out.",
        "Still Hatcher. Still retired. Out.",
    },
    fence = {
        "Order came down to fire on the fence line. Civilians. I walked into the trees instead. Out.",
        "I don't tell that one twice. Out.",
    },
    sitrepCount = { "Walkers in sight of my position: %d. Out." },
    sitrepWeather = { "Walkers in sight: %d. Tomorrow looks like %s. Out." },
    sitrepBlind = { "Can't count from here. Out of sight lines. Out." },
    supplies = { "Write this down. %s. Inside. Take what you need, not all of it. Out." },
    suppliesAgain = { "Same place as before. I don't run a store. Out." },
    noCache = { "Nothing close enough to stash it. Ask me tomorrow. Out." },
    meet = { "My camp's in the woods, %s. Come slow. Hands empty. Out." },
    meetAgain = { "You know where I am. Out." },
    notYet = { "Not yet. Call me tomorrow. Out." },
    silent = { "Radio discipline. Going quiet till tomorrow. Out." },
    invited = { "You came slow. Good. Sit if you want. Don't touch the rifle." },
    uninvited = { "You found me. Means you're good, or lucky. Either way, go." },
    frequency = { "Want to talk, one-four-six point six. Dawn and dusk." },
    kit = {
        "Everything I own is on me or under a tarp. Don't get ideas.",
        "Rifle's older than you think and cleaner than you'd guess.",
    },
    woods = {
        "Trees don't take orders. I find that restful.",
        "Out here the only thing that salutes is the wind.",
    },
    fellow = {
        "He's got better gear than the National Guard did.",
        "That man's been sleeping with one eye open since Vietnam.",
    },
}
Soldier.LINES = LINES

local function U() return SC.GameplayUtil end

local function number(value)
    if type(value) == "number" then return value end
    if type(value) == "string" then return tonumber(value) end
    return nil
end

local function call(object, method, ...)
    return object and select(1, U().call(object, method, ...)) or nil
end

local function story(group)
    local value = type(group) == "table" and group.oddball or nil
    if type(value) ~= "table" or value.id ~= ID then return nil end
    if value.stage == nil or value.stage == "unmet" then value.stage = "camped" end
    value.trust = number(value.trust) or 0
    value.lines = type(value.lines) == "table" and value.lines or {}
    value.pending = type(value.pending) == "table" and value.pending or {}
    return value
end

local function actorFor(group)
    local member = group and group.members and group.members[1]
    local record = member and member.actorId and SC.Registry
        and SC.Registry.byId(member.actorId) or nil
    local actor = record and record.actor
    return actor and U().isValidActor(actor) and not U().isDead(actor) and actor or nil
end

local function nextLine(value, pool)
    local list = LINES[pool]
    local index = number(value.lines[pool]) or 0
    if index ~= index or index < 0 or index % 1 ~= 0 then index = 0 end
    index = index % #list + 1
    value.lines[pool] = index
    return list[index]
end

local function worldHours()
    if type(getGameTime) ~= "function" then return nil end
    local okay, time = pcall(getGameTime)
    if not okay or not time then return nil end
    return number((U().call(time, "getWorldAgeHours")))
end

local function walkie(actor)
    local inventory = actor and U().inventory(actor)
    for _, item in ipairs(inventory and U().inventoryItemsDeep(inventory, 120, 4) or {}) do
        if U().itemType(item) == "Base.WalkieTalkie5" then return item end
    end
    return nil
end

function Soldier.transmitRange(group)
    local data = call(walkie(actorFor(group)), "getDeviceData")
    local range = number(call(data, "getTransmitRange"))
    if range and range > 0 then return math.floor(range) end
    return FALLBACK_RANGE
end

local function sourcePoint(group, value)
    local actor = actorFor(group)
    local x, y
    if actor then x, y = U().position(actor) end
    if x and y then return math.floor(x), math.floor(y) end
    local post = value.site and value.site.spawn
    if post then return post.x, post.y end
    return nil
end

local function send(x, y, channel, text, code, range)
    if type(getZomboidRadio) ~= "function" then return false, "native_radio_unavailable" end
    local api = getZomboidRadio()
    if not api or not x then return false, "native_radio_unavailable" end
    local okay, failure = pcall(function()
        api:SendTransmission(math.floor(x), math.floor(y), channel, text,
            "LF-HATCHER", code, 0.6, 0.85, 0.55, math.floor(range), false)
    end)
    return okay, okay and "transmitted" or tostring(failure)
end

local function transmit(group, value, text, code, channel)
    local x, y = sourcePoint(group, value)
    if not x then return false, "hatcher_position_unavailable" end
    return send(x, y, channel or CHANNEL, text, code, Soldier.transmitRange(group))
end

-- The game's own forecast for tomorrow, in words.
local function forecast()
    local reader = SC.OddballForecast
    return reader and type(reader.tomorrow) == "function" and reader.tomorrow() or nil
end

-- Walkers he can count from camp: a bounded walk of the loaded zombie list.
function Soldier.walkerCount(group)
    local actor = actorFor(group)
    if not actor or type(getCell) ~= "function" or not SC.NativeList then return nil end
    local okay, cell = pcall(getCell)
    local zombies = okay and call(cell, "getZombieList") or nil
    if not zombies then return nil end
    local total = 0
    for index = 0, math.min(511, SC.NativeList.size(zombies) - 1) do
        local zombie = SC.NativeList.get(zombies, index)
        if zombie and not U().isDead(zombie) and U().sameFloor(actor, zombie)
            and U().distance(actor, zombie) <= COUNT_RADIUS then
            total = total + 1
        end
    end
    return total
end

local function enqueue(value, text, code, channel, at)
    local last = value.pending[#value.pending]
    local when = math.max(at, last and (number(last.at) or 0) + LINE_GAP_MS or 0)
    value.pending[#value.pending + 1] = { text = text, code = code,
        channel = channel or CHANNEL, at = when }
    return when
end

local function dueSlot(hours)
    if not hours then return nil end
    local day = math.floor(hours / 24)
    local hour = hours - day * 24
    local best, label
    for _, slot in ipairs(SLOT_HOURS) do
        if hour >= slot then best, label = day * 24 + slot, slot end
    end
    if best then return best, label end
    return (day - 1) * 24 + SLOT_HOURS[#SLOT_HOURS], SLOT_HOURS[#SLOT_HOURS]
end

local function scheduleSitrep(group, value, slotHour, current)
    local code = "SITREP-" .. tostring(value.lastSlot)
    enqueue(value, nextLine(value, slotHour == SLOT_HOURS[1] and "morning" or "evening"),
        code .. "-1", CHANNEL, current)
    local count = Soldier.walkerCount(group)
    if count then
        enqueue(value, string.format(LINES.count[1], count), code .. "-2", CHANNEL, current)
    else
        enqueue(value, LINES.noCount[1], code .. "-2", CHANNEL, current)
    end
    local sky = forecast()
    if sky then
        enqueue(value, string.format(LINES.weather[1], sky), code .. "-3", CHANNEL, current)
    end
    enqueue(value, nextLine(value, "closing"), code .. "-4", CHANNEL, current)
end

local function fellowLine(group, player, value, text)
    if value.fellowSpoke == true or not player or not SC.Registry
        or type(SC.Registry.living) ~= "function" then return false end
    local hatcher = actorFor(group)
    for _, fellow in ipairs(SC.Registry.living()) do
        if fellow ~= hatcher and U().distance(fellow, player) <= 10 then
            local id = U().idOf(fellow)
            local record = id and SC.Registry.byId(id) or nil
            if record and record.recruited == true then
                U().say(fellow, text)
                value.fellowSpoke = true
                return true
            end
        end
    end
    return false
end

function Soldier.pulse(group, player, current)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    current = number(current) or U().nowMs()
    local head = value.pending[1]
    if head and current >= (number(head.at) or 0) then
        table.remove(value.pending, 1)
        transmit(group, value, head.text, head.code, head.channel)
    end
    local actor = actorFor(group)
    if actor and player and U().sameFloor(actor, player)
        and U().distance(actor, player) <= NEAR_DISTANCE
        and U().canSee(actor, player) == true then
        if value.invited == true and value.met ~= true then
            value.met, value.seen = true, true
            group.discovered = true
            U().say(actor, LINES.invited[1])
            fellowLine(group, player, value, nextLine(value, "fellow"))
        elseif value.invited ~= true and value.seen ~= true then
            value.seen = true
            group.discovered = true
            U().say(actor, LINES.uninvited[1])
            value.pendingVoice = { text = LINES.frequency[1], at = current + 3000 }
            fellowLine(group, player, value, nextLine(value, "fellow"))
        end
    end
    if actor and type(value.pendingVoice) == "table"
        and current >= (number(value.pendingVoice.at) or 0) then
        U().say(actor, value.pendingVoice.text)
        value.pendingVoice = nil
    end
    local slot, slotHour = dueSlot(worldHours())
    if not slot then return true, "hatcher_clock_unavailable" end
    if value.lastSlot == nil then
        value.lastSlot = slot
        return true, "hatcher_waiting_for_the_next_slot"
    end
    if slot > value.lastSlot then
        value.lastSlot = slot
        if value.cutInDone ~= true then
            value.cutInDone = true
            enqueue(value, LINES.cutIn[1], "CUT-IN", CALLING_CHANNEL, current)
        end
        scheduleSitrep(group, value, slotHour, current)
        return true, "hatcher_sitrep_queued"
    end
    return true, value.stage
end

-- The player's set, exactly as the rescue calls require it: equipped, on,
-- powered, two-way, on his channel and able to transmit.
function Soldier.playerRadio(player)
    local radio = SC.OddballDistressRadio
    if radio and type(radio.equippedRadio) == "function" then
        return radio.equippedRadio(player, true, CHANNEL)
    end
    return nil
end

-- The native delivery rule from the rescue calls: more than three meters
-- apart and within ninety percent of the sender's range, both ways.
local function deliverable(ax, ay, bx, by, range)
    if not ax or not bx or not range or range <= 0 then return false end
    local dx, dy = math.floor(bx) - math.floor(ax), math.floor(by) - math.floor(ay)
    local distance = math.floor(math.sqrt(dx * dx + dy * dy))
    return distance > 3 and distance < range and distance <= range * 0.9
end

local function reachable(group, value, player, data)
    local hx, hy = sourcePoint(group, value)
    local px, py = U().position(player)
    return deliverable(px, py, hx, hy, number(call(data, "getTransmitRange")) or 0)
        and deliverable(hx, hy, px, py, Soldier.transmitRange(group))
end

local function topicsFor(value)
    local hours = worldHours() or 0
    if (number(value.silentUntilHour) or -1) > hours then return {} end
    if value.identified ~= true then
        return { { topic = "identify", label = "146.6: Ask who's broadcasting" } }
    end
    local topics = {
        { topic = "fence", label = "146.6: Ask Hatcher about the fence" },
        { topic = "sitrep", label = "146.6: Ask Hatcher for a sitrep" },
    }
    if value.trust >= 2 then
        topics[#topics + 1] = { topic = "supplies", label = "146.6: Ask Hatcher about supplies" }
    end
    if value.trust >= MAX_TRUST then
        topics[#topics + 1] = { topic = "meet", label = "146.6: Ask Hatcher to meet" }
    end
    return topics
end

function Soldier.radioOptions(player)
    local _, data = Soldier.playerRadio(player)
    if not data then return {} end
    local options = {}
    for _, group in ipairs(SC.Factions and SC.Factions.list(false) or {}) do
        local value = story(group)
        if value and group.lifecycle ~= "destroyed" and reachable(group, value, player, data) then
            for _, entry in ipairs(topicsFor(value)) do
                options[#options + 1] = { groupId = group.id, topic = entry.topic,
                    label = entry.label }
            end
        end
    end
    return options
end

local function stockCache(group, value, player)
    if not SC.Factions or type(SC.Factions.findHouse) ~= "function"
        or type(SC.Factions.resolveQuestContainer) ~= "function" then
        return nil, "house_search_unavailable"
    end
    -- A stash is a stash in a house the player already knows. Near a
    -- lived-in base every house is explored; live, an unexplored-only search
    -- from the edge of West Point found none. Never the player's base house.
    local house = SC.Factions.findHouse(player, { purpose = "quest",
        sourceFactionId = group.id, minimumDistance = 30, maximumDistance = 120,
        sampleBudget = 48, allowSeen = true })
    if not house or not house.questContainer then return nil, "no_cache_house" end
    local container = SC.Factions.resolveQuestContainer(house.questContainer,
        house.bounds, house.anchor)
    if not container then return nil, "cache_container_unavailable" end
    for _, kind in ipairs(CACHE_ITEMS) do
        local item = U().addItem(container, kind)
        local data = item and U().modData(item)
        if type(data) == "table" then data.lfHatcherCacheGroupId = group.id end
    end
    local location = SC.Factions.describeLocation and SC.Factions.describeLocation(house.anchor)
    return { anchor = house.anchor,
        address = location and location.address
            or (tostring(house.anchor.x) .. ", " .. tostring(house.anchor.y)) }
end

local function mark(text, x, y)
    local life = SC.FactionLife
    if life and type(life.addMapAnnotation) == "function" then
        life.addMapAnnotation(text, x, y, { 0.45, 0.65, 0.35, 1.0 })
    end
end

local function replyFor(group, value, topic, player)
    if topic == "identify" then
        value.identified = true
        return nextLine(value, "identify")
    elseif topic == "fence" then
        return nextLine(value, "fence")
    elseif topic == "sitrep" then
        local count, sky = Soldier.walkerCount(group), forecast()
        if count and sky then return string.format(LINES.sitrepWeather[1], count, sky) end
        if count then return string.format(LINES.sitrepCount[1], count) end
        return LINES.sitrepBlind[1]
    elseif topic == "supplies" then
        if value.trust < 2 then return LINES.notYet[1] end
        if value.cacheGiven == true then return LINES.suppliesAgain[1] end
        local cache = stockCache(group, value, player)
        if not cache then return LINES.noCache[1] end
        value.cacheGiven = true
        mark("[LF] Hatcher's cache", cache.anchor.x, cache.anchor.y)
        return string.format(LINES.supplies[1], cache.address)
    elseif topic == "meet" then
        if value.trust < MAX_TRUST then return LINES.notYet[1] end
        if value.invited == true then return LINES.meetAgain[1] end
        value.invited = true
        local post = value.site and (value.site.anchor or value.site.spawn)
        local location = post and SC.Factions and SC.Factions.describeLocation
            and SC.Factions.describeLocation(post)
        if post then mark("[LF] Hatcher's camp", post.x, post.y) end
        -- The describer names every point a "House"; a camp is not one.
        local street = location and location.nearestStreet
        local where = street and location.direction and string.format("%d meters %s of %s",
            number(location.distance) or 0, location.direction, tostring(street.name))
            or "past the treeline"
        return string.format(LINES.meet[1], where)
    end
    return nil
end

function Soldier.call(groupId, topic, player)
    local group = SC.Factions and SC.Factions.group(groupId)
    local value = story(group)
    if not value or group.lifecycle == "destroyed" then return false, "hatcher_unavailable" end
    local radio, data = Soldier.playerRadio(player)
    if not radio then return false, "radio_not_ready_on_146_6" end
    if not reachable(group, value, player, data) then return false, "radios_out_of_range" end
    local allowed = false
    for _, entry in ipairs(topicsFor(value)) do
        if entry.topic == topic then allowed = true end
    end
    if not allowed then return false, "topic_unavailable" end
    local current = U().nowMs()
    local hours = worldHours() or 0
    local hour, day = math.floor(hours), math.floor(hours / 24)
    local px, py = U().position(player)
    send(px, py, CHANNEL, PLAYER_LINES[topic], "LF-LISTENER",
        number(call(data, "getTransmitRange")) or 0)
    if number(value.callsHour) == hour then
        value.callsInHour = (number(value.callsInHour) or 0) + 1
    else
        value.callsHour, value.callsInHour = hour, 1
    end
    if value.callsInHour > CALLS_PER_HOUR then
        value.silentUntilHour = (day + 1) * 24 + SLOT_HOURS[1]
        enqueue(value, LINES.silent[1], "REPLY-SILENT", CHANNEL, current + REPLY_DELAY_MS)
        return true, "hatcher_went_quiet"
    end
    -- One step of trust per day of contact, the first on the day he answers.
    if (number(value.lastTrustDay) or -1) < day then
        value.trust = math.min(MAX_TRUST, value.trust + 1)
        value.lastTrustDay = day
    end
    local reply = replyFor(group, value, topic, player)
    if reply then
        enqueue(value, reply, "REPLY-" .. string.upper(topic), CHANNEL, current + REPLY_DELAY_MS)
    end
    return true, "hatcher_called"
end

function Soldier.onSpawn(group, actor)
    local value = story(group)
    if not value or not actor then return false, "hatcher_unavailable" end
    local inventory = U().inventory(actor)
    if not inventory then return false, "hatcher_inventory_unavailable" end
    if value.kitSeeded == true then return true, "hatcher_dug_in" end
    local issued = value.kitIssuedCounts
    if issued == nil then
        -- Adopt older, partially seeded kits once. Later retries trust these
        -- persisted receipts, never recreating issued gear which has since left.
        issued = {}
        for _, item in ipairs(U().inventoryItemsDeep(inventory, 120, 4)) do
            local kind = U().itemType(item)
            if KIT_COUNTS[kind] then
                issued[kind] = math.min(KIT_COUNTS[kind], (issued[kind] or 0) + 1)
            end
        end
        value.kitIssuedCounts = issued
    elseif type(issued) ~= "table" then
        return false, "hatcher_kit_receipt_invalid"
    end
    for kind, maximum in pairs(KIT_COUNTS) do
        local count = issued[kind]
        if count ~= nil and (type(count) ~= "number" or count ~= count
            or count < 0 or count > maximum or count % 1 ~= 0) then
            return false, "hatcher_kit_receipt_invalid:" .. kind
        end
    end
    local needed = {}
    for _, kind in ipairs(PERSONAL_KIT) do
        needed[kind] = (needed[kind] or 0) + 1
        if (issued[kind] or 0) < needed[kind] then
            local item = U().addItem(inventory, kind)
            if not item then return false, "hatcher_kit_unavailable:" .. kind end
            issued[kind] = needed[kind]
            -- Only newly issued weapons receive starting ammunition. Retrying
            -- or loading a partial kit must not refill or replace an owned gun.
            if kind == "Base.AssaultRifle" then
                U().call(item, "setCurrentAmmoCount", 20)
                U().call(actor, "setPrimaryHandItem", item)
                U().call(actor, "setSecondaryHandItem", item)
            elseif kind == "Base.Pistol" then U().call(item, "setCurrentAmmoCount", 15) end
        end
    end
    value.kitSeeded = true
    return true, "hatcher_dug_in"
end

function Soldier.intentFor(actor, player, snapshot, group)
    if not story(group) then return nil end
    if group.standing == "Hostile" then return { mode = "hostile", priority = 110 } end
    local threats = type(snapshot) == "table"
        and (number(snapshot.threatCount) or #(snapshot.threats or {})) or 0
    if threats > 0 then return { mode = "zombie_defense", priority = 18 } end
    return { mode = "hatcher_camp", priority = 30 }
end

function Soldier.update(actor, player, runtime, intent, group)
    if not intent or intent.mode ~= "hatcher_camp" then return false end
    local value = story(group)
    local post = value and value.site and value.site.spawn
    if not post then return true, "hatcher_post_unavailable" end
    local x, y, z = U().position(actor)
    if x and z == (post.z or 0) and (x - post.x) ^ 2 + (y - post.y) ^ 2 <= 4 then
        return true, "hatcher_on_watch"
    end
    local square = U().gridSquare(post.x, post.y, post.z or 0)
    if not square or not SC.Navigation or type(SC.Navigation.request) ~= "function" then
        return true, "hatcher_post_unloaded"
    end
    return SC.Navigation.request(actor, square, "walk", {
        action = "faction_home", arrivalDistance = 1.5 })
end

function Soldier.menuOptions(group, player)
    local value = story(group)
    local actor = actorFor(group)
    if not value or not actor or not player or not U().sameFloor(actor, player)
        or U().distance(actor, player) > MENU_DISTANCE then return {} end
    return {
        { id = "ask_hatcher_kit", label = "Ask about his kit", enabled = true },
        { id = "ask_hatcher_woods", label = "Ask why the woods", enabled = true },
    }
end

function Soldier.action(group, action, player)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    local actor = actorFor(group)
    if action == "hurt" then return false, "hatcher_returns_fire" end
    if not actor or not player or U().distance(actor, player) > MENU_DISTANCE then
        return false, "hatcher_out_of_reach"
    end
    if action == "ask_hatcher_kit" then
        U().say(actor, nextLine(value, "kit"))
        return true, action
    elseif action == "ask_hatcher_woods" then
        U().say(actor, nextLine(value, "woods"))
        return true, action
    end
    return false, "unknown_hatcher_choice"
end

function Soldier.canRecruit(group)
    local value = story(group)
    if value and value.invited == true and value.met == true and value.trust >= MAX_TRUST then
        return true
    end
    return false, "hatcher_does_not_know_you_yet"
end

return Soldier
