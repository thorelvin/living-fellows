-- SPDX-License-Identifier: MIT

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion

SC.NicknameLife = SC.NicknameLife or {}
local Life = SC.NicknameLife

-- The bounds follow stock Build 42 map.info/spawnpoints.lua, except Louisville,
-- whose nine paper-map bounds are in ISMapDefinitions.lua. Unknown space has no
-- town nickname; a nearby town is never inferred from distance alone.
local towns = {
    { "Muldraugh", 10550, 11100, 9300, 10700 },
    { "Rosewood", 7700, 8650, 11150, 12500 },
    { "Riverside", 5600, 7500, 5100, 6250 },
    { "West Point", 10850, 12400, 6500, 7300 },
    { "March Ridge", 9700, 10200, 12350, 13050 },
    { "Louisville", 11700, 14700, 750, 3900 },
    { "Ekron", 300, 1200, 9600, 10100 },
    { "Irvington", 1800, 2950, 13550, 14600 },
    { "Brandenburg", 2000, 2500, 5850, 6450 },
    { "Echo Creek", 3450, 4450, 10750, 11300 },
}

local earnedNames = {
    pan = "Pans", bat = "Slugger", shovel = "Spade", axe = "Hatchet",
    reaper = "Reaper", rescued = "Nine Lives", rescuer = "Angel",
    burn = "Toast", fall = "Skydiver", fish = "Hooks", stealth = "Ghost",
}

local careerNames = {
    burglar = "Shadow", carpenter = "Chips", chef = "Cookie",
    doctor = "Doc", electrician = "Fuse", engineer = "Gears",
    farmer = "Tractor", fireofficer = "Smokey", fisherman = "Hooks",
    lumberjack = "Timber", mechanics = "Wrench", nurse = "Patches",
    parkranger = "Trail", policeofficer = "Badge", repairman = "Fix-It",
    tailor = "Stitch", veteran = "Sarge",
}
local generalNames = { "Scout", "Keeper", "Ace", "Rook", "Trail" }
local replies = {}

local function finite(value)
    value = tonumber(value)
    if value == nil or value ~= value or value == math.huge or value == -math.huge then
        return nil
    end
    return value
end

local function config(key, fallback)
    local value = SC.Config and type(SC.Config.get) == "function"
        and SC.Config.get(key) or nil
    return value == nil and fallback or value
end

local function hash(value)
    if SC.GameplayUtil and type(SC.GameplayUtil.stableHash) == "function" then
        return math.abs(tonumber(SC.GameplayUtil.stableHash(value)) or 0)
    end
    local result, source = 0, tostring(value or "")
    for index = 1, #source do
        result = (result * 33 + string.byte(source, index)) % 2147483647
    end
    return result
end

local function nowHours()
    if type(getGameTime) == "function" then
        local okay, time = pcall(getGameTime)
        if okay and time then
            local hourOkay, hour = pcall(function() return time:getWorldAgeHours() end)
            if hourOkay and finite(hour) then return math.max(0, hour) end
        end
    end
    return 0
end

local function nowMs()
    if SC.GameplayUtil and type(SC.GameplayUtil.nowMs) == "function" then
        return finite(SC.GameplayUtil.nowMs()) or 0
    end
    if type(getTimestampMs) == "function" then
        local okay, value = pcall(getTimestampMs)
        if okay then return finite(value) or 0 end
    end
    return 0
end

local function recordFor(value)
    if type(value) == "table" and type(value.identity) == "table" then return value end
    local registry = SC.Registry
    if not registry or type(registry.byId) ~= "function" then return nil end
    local id = type(value) == "string" and value or nil
    if id == nil and registry.idOf then id = registry.idOf(value) end
    return id and registry.byId(id) or nil
end

local function actorFor(value, record)
    if type(value) == "table" and type(value.identity) == "table" then
        return value.actor
    end
    if type(value) == "string" then return record and record.actor or nil end
    return value
end

local function metaFor(record)
    if type(record) ~= "table" then return nil end
    local normalized = SC.Names and SC.Names.normalizeMeta
        and SC.Names.normalizeMeta(record.nicknameMeta) or nil
    record.nicknameMeta = normalized or { offered = {}, events = {}, private = {} }
    local pending = record.nicknameMeta.lastEventKey
    local earned = pending and pending:match("^earned%.([a-z]+)$")
    if pending and not earnedNames[earned] then
        record.nicknameMeta.lastEventKey = nil
    end
    return record.nicknameMeta
end

local function mapCount(map)
    local count = 0
    for _ in pairs(map or {}) do count = count + 1 end
    return count
end

local function putBounded(map, key, value, limit)
    if map[key] == nil and mapCount(map) >= (limit or 60) then return false end
    map[key] = value
    return true
end

local function idFor(value, record)
    if record and type(record.id) == "string" then return record.id end
    if SC.GameplayUtil and SC.GameplayUtil.idOf then return SC.GameplayUtil.idOf(value) end
    return tostring(value)
end

local function firstName(value, record)
    local identity = record and record.identity or nil
    if identity and type(identity.forename) == "string" then return identity.forename end
    local actor = actorFor(value, record)
    if SC.GameplayUtil and SC.GameplayUtil.nameOf then
        local name = SC.GameplayUtil.nameOf(actor)
        if type(name) == "string" then return name:match("^(%S+)") or "friend" end
    end
    return "friend"
end

local function speak(actor, topic, arguments, salt)
    if actor == nil or not SC.Dialogue or type(SC.Dialogue.say) ~= "function" then
        return false
    end
    return SC.Dialogue.say(actor, topic, nil, arguments, { salt = salt }) == true
end

local function queueReply(actor, topic, arguments, salt)
    if actor == nil then return false end
    if #replies >= 8 then table.remove(replies, 1) end
    replies[#replies + 1] = {
        actor = actor, topic = topic, arguments = arguments, salt = salt,
        due = nowMs() + 2800,
    }
    return true
end

function Life.pulse(current)
    current = finite(current) or nowMs()
    for index = 1, #replies do
        local reply = replies[index]
        if current >= reply.due then
            table.remove(replies, index)
            local spoken = speak(reply.actor, reply.topic, reply.arguments, reply.salt)
            return spoken, spoken and "nickname_reply_spoken" or "nickname_reply_unavailable"
        end
    end
    return false, "nickname_reply_not_due"
end

local function hasNickname(record)
    return record and SC.Names and SC.Names.normalizeRecord
        and SC.Names.normalizeRecord(record.nickname) ~= nil
end

local function townAt(x, y)
    x, y = finite(x), finite(y)
    if not x or not y then return nil end
    for _, town in ipairs(towns) do
        if x >= town[2] and x <= town[3] and y >= town[4] and y <= town[5] then
            return town[1]
        end
    end
    return nil
end
Life.townAt = townAt

local function uniqueNickname(name, exceptId)
    if not SC.Registry or type(SC.Registry.records) ~= "function" then return true end
    for _, record in ipairs(SC.Registry.records()) do
        local nickname = SC.Names.normalizeRecord(record.nickname)
        if record.id ~= exceptId and nickname
            and string.lower(nickname.text) == string.lower(name) then return false end
    end
    return true
end

local function oddball(record)
    if not record or not record.factionId or not SC.Factions
        or type(SC.Factions.group) ~= "function" then return false end
    local group = SC.Factions.group(record.factionId)
    return type(group) == "table" and type(group.oddball) == "table"
end

function Life.onRecruit(actor, player)
    if config("nicknamesEnabled", true) == false then return false, "disabled" end
    local record = recordFor(actor)
    local speaker = actorFor(actor, record)
    if not record or not speaker then return false, "companion_unavailable" end
    if oddball(record) then return false, "oddball" end
    local meta = metaFor(record)
    if not meta.offered["recruit.place.checked"] then
        meta.offered["recruit.place.checked"] = true
        if not hasNickname(record) then
            local x, y
            if SC.GameplayUtil and type(SC.GameplayUtil.position) == "function" then
                x, y = SC.GameplayUtil.position(speaker)
            end
            local town = townAt(x, y)
            local chance = finite(config("nicknamePlaceChance", 0.05)) or 0.05
            if chance > 1 then chance = chance / 100 end
            chance = math.max(0, math.min(1, chance))
            local seed = tostring(record.id) .. ":place:" .. tostring(town or "none")
            if town and uniqueNickname(town, record.id)
                and hash(seed) % 10000 < chance * 10000 then
                SC.Names.offer(record, town, "place", true)
            end
        end
    end
    local nickname = SC.Names.normalizeRecord(record.nickname)
    if nickname and (nickname.source == "intro" or nickname.source == "place")
        and not meta.offered["recruit.intro.spoken"] then
        local spoken = speak(speaker, "nickname.intro",
            { firstName(actor, record), nickname.text }, record.id .. ":intro")
        if spoken then
            meta.offered["recruit.intro.spoken"] = true
            return true, "intro_spoken"
        end
    end
    if config("famousNamesakes", false) == true
        and not meta.offered["recruit.namesake.spoken"]
        and SC.Spawn and type(SC.Spawn.isReservedFullName) == "function"
        and SC.Spawn.isReservedFullName(record.identity and record.identity.forename,
            record.identity and record.identity.surname) then
        local spoken = speak(speaker, "nickname.namesake", {}, record.id .. ":namesake")
        if spoken then
            meta.offered["recruit.namesake.spoken"] = true
            return true, "namesake_spoken"
        end
    end
    return false, "no_nickname_speech"
end

local function queueEarned(record, key)
    local meta = metaFor(record)
    local eventKey = "earned." .. key
    if not earnedNames[key] or meta.offered[eventKey] then return false, "already_offered" end
    if hasNickname(record) then
        putBounded(meta.offered, eventKey, true)
        return false, "nickname_exists"
    end
    if meta.lastEventKey then return false, "pending_exists" end
    meta.lastEventKey = eventKey
    return true, "earned_pending"
end

local function eventOnce(meta, prefix, key)
    if type(key) ~= "string" or key == "" then return false end
    local token = prefix .. "." .. tostring(hash(key))
    if meta.events[token] then return false end
    return putBounded(meta.events, token, 1, 48)
end

-- Details are evidence supplied by the verifying hook, not a claim inferred
-- from a health or damage callback. A rescue needs one stable crisisKey.
function Life.noteEvent(actor, kind, detail)
    if config("nicknamesEnabled", true) == false then return false, "disabled" end
    local record = recordFor(actor)
    if not record then return false, "companion_unavailable" end
    detail = type(detail) == "table" and detail or {}
    local meta = metaFor(record)
    if kind == "rescued" then
        local health = finite(detail.patientHealth)
        if detail.wasDowned ~= true and (not health or health >= 25) then
            return false, "crisis_unverified"
        end
        if not eventOnce(meta, "crisis", detail.crisisKey) then
            return false, "crisis_repeated_or_unidentified"
        end
        meta.events.rescued = math.min(1000000, (meta.events.rescued or 0) + 1)
        if meta.events.rescued >= 2 then return queueEarned(record, "rescued") end
        return true, "rescue_counted"
    elseif kind == "rescuer" then
        if detail.verified ~= true or type(detail.crisisKey) ~= "string" then
            return false, "rescue_unverified"
        end
        if not eventOnce(meta, "saved", detail.crisisKey) then
            return false, "rescue_repeated"
        end
        return queueEarned(record, "rescuer")
    elseif kind == "burn" then
        if detail.verified ~= true then return false, "burn_unverified" end
        return queueEarned(record, "burn")
    elseif kind == "fall" then
        if detail.survived ~= true or (finite(detail.floors) or 0) < 2 then
            return false, "fall_unverified"
        end
        return queueEarned(record, "fall")
    elseif kind == "fish" then
        local size = finite(detail.size)
        if not size or size <= 0 then return false, "catch_size_unavailable" end
        -- nicknameMeta stores integers. Millisize preserves fish-size ordering
        -- while remaining within normalizeMeta's bounded counter range.
        local scaled = math.min(1000000, math.floor(size * 1000 + 0.5))
        local biggest = 0
        if SC.Registry and type(SC.Registry.records) == "function" then
            for _, other in ipairs(SC.Registry.records()) do
                local events = type(other.nicknameMeta) == "table"
                    and other.nicknameMeta.events or nil
                biggest = math.max(biggest,
                    finite(events and events.biggestFish) or 0)
            end
        end
        if scaled <= biggest then return false, "catch_not_biggest" end
        meta.events.biggestFish = scaled
        return queueEarned(record, "fish")
    end
    return false, "unknown_event"
end

local function eventDay(now)
    return math.floor(math.max(0, finite(now) or nowHours()) / 24)
end

local function recentCount(record, prefix, day)
    local events = record and record.nicknameMeta and record.nicknameMeta.events or {}
    local total = 0
    for offset = 0, 6 do
        total = total + (tonumber(events[prefix .. "." .. tostring(day - offset)]) or 0)
    end
    return total
end

local function leader(record, prefix, day, minimum)
    local own = recentCount(record, prefix, day)
    if own < minimum then return false end
    if SC.Registry and type(SC.Registry.records) == "function" then
        for _, other in ipairs(SC.Registry.records()) do
            if other.id ~= record.id and other.recruited == true
                and recentCount(other, prefix, day) >= own then return false end
        end
    end
    return true
end

local function incrementDay(meta, prefix, day)
    for key in pairs(meta.events) do
        local stored = key:match("^" .. prefix .. "%.(%d+)$")
        if stored and tonumber(stored) < day - 6 then meta.events[key] = nil end
    end
    local key = prefix .. "." .. tostring(day)
    putBounded(meta.events, key, math.min(1000000, (meta.events[key] or 0) + 1), 56)
end

local function weaponCategory(item)
    if not item then return nil end
    local utility = SC.GameplayUtil
    local fullType = utility and utility.call and select(1, utility.call(item, "getFullType"))
        or nil
    if type(fullType) ~= "string" then return nil end
    local name = string.lower(fullType)
    if name:find("fryingpan", 1, true) or name:find("saucepan", 1, true) then
        return "pan"
    elseif name:find("baseballbat", 1, true) or name:find("woodenbat", 1, true) then
        return "bat"
    elseif name:find("shovel", 1, true) then return "shovel"
    elseif name:find("axe", 1, true) or name:find("hatchet", 1, true) then
        return "axe"
    end
    return nil
end

-- Kill hooks may pass a millisecond timestamp as now. The rolling seven-day
-- window always uses the game's world-age clock; detail.stealth is verified by
-- the hook, and detail.worldAgeHours is only a test/replay override.
function Life.noteKill(actor, target, now, detail)
    if config("nicknamesEnabled", true) == false then return false, "disabled" end
    local record = recordFor(actor)
    if not record then return false, "companion_unavailable" end
    local utility = SC.GameplayUtil
    local meta, day = metaFor(record), eventDay(
        type(detail) == "table" and detail.worldAgeHours or nil)
    incrementDay(meta, "killday", day)
    local item = utility and utility.call and select(1,
        utility.call(actorFor(actor, record), "getPrimaryHandItem")) or nil
    local category = weaponCategory(item)
    if category then
        local token = utility and utility.itemStableId
            and utility.itemStableId(item, true) or tostring(item)
        local key = "weapon." .. category .. "." .. tostring(hash(token))
        if putBounded(meta.events, key,
            math.min(1000000, (meta.events[key] or 0) + 1), 32)
            and meta.events[key] == 25 then queueEarned(record, category) end
    end
    if leader(record, "killday", day, 50) then queueEarned(record, "reaper") end
    local stealth
    if type(detail) == "table" then stealth = detail.stealth end
    if stealth == nil then
        local state = SC.Commands and type(SC.Commands.peek) == "function"
            and SC.Commands.peek(actorFor(actor, record)) or nil
        stealth = type(state) == "table" and state.combatDoctrine == "stealth"
    end
    if stealth == true then
        incrementDay(meta, "stealthday", day)
        if leader(record, "stealthday", day, 25) then
            queueEarned(record, "stealth")
        end
    end
    return true, "kill_counted"
end

local function friends(speaker, listener, speakerRecord, listenerRecord)
    if listenerRecord then
        local pair = SC.Community and type(SC.Community.relation) == "function"
            and SC.Community.relation(speakerRecord.id, listenerRecord.id, false) or nil
        return pair and (finite(pair.familiarity) or 0)
            >= (finite(config("nicknameFamiliarity", 25)) or 25)
            and (finite(pair.opinion) or 0)
            >= (finite(config("nicknameFriendlyOpinion", 15)) or 15)
    end
    if type(getPlayer) ~= "function" or listener ~= getPlayer() then return false end
    local state = SC.Commands and type(SC.Commands.peek) == "function"
        and SC.Commands.peek(speaker) or nil
    return type(state) == "table" and (finite(state.trust) or 0) >= 25
        and (finite(state.bond) or 0) >= 25
end

local function genericName(record, seed)
    local state = type(record.state) == "table" and record.state or {}
    local personality = type(state.personality) == "table" and state.personality or {}
    local background = type(personality.background) == "table" and personality.background
        or type(state.background) == "table" and state.background or {}
    local profession = tostring(background.profession or ""):gsub("^base:", "")
    local preferred = careerNames[profession]
    if preferred and uniqueNickname(preferred, record.id) then
        return preferred, "profession"
    end
    local start = hash(seed) % #generalNames
    for offset = 0, #generalNames - 1 do
        local candidate = generalNames[((start + offset) % #generalNames) + 1]
        if uniqueNickname(candidate, record.id) then return candidate, "earned" end
    end
    return nil
end

function Life.maybeCoin(speaker, listener, salt)
    if config("nicknamesEnabled", true) == false then return false, "disabled" end
    local speakerRecord, listenerRecord = recordFor(speaker), recordFor(listener)
    local speakerActor = actorFor(speaker, speakerRecord)
    if not speakerRecord or not speakerActor or not listener
        or (listenerRecord and listenerRecord.id == speakerRecord.id) then
        return false, "invalid_pair"
    end
    if listenerRecord and hasNickname(listenerRecord) then
        return false, "nickname_exists"
    end
    if not listenerRecord and SC.GameplayUtil and SC.GameplayUtil.call then
        local data = select(1, SC.GameplayUtil.call(listener, "getModData"))
        if type(data) == "table" and SC.Names.normalize(data.SC_PlayerNickname) then
            return false, "nickname_exists"
        end
    end
    if not friends(speakerActor, listener, speakerRecord, listenerRecord) then
        return false, "not_friends"
    end
    local now, meta = nowHours(), metaFor(speakerRecord)
    local cooldown = math.max(1, finite(config("nicknameCoinCooldownHours", 168)) or 168)
    if meta.lastCoinHour and now - meta.lastCoinHour < cooldown then
        return false, "cooldown"
    end
    local seed = speakerRecord.id .. ":" .. idFor(listener, listenerRecord)
        .. ":" .. tostring(salt or "") .. ":" .. tostring(math.floor(now / cooldown))
    local eventMeta = listenerRecord and metaFor(listenerRecord) or nil
    local pending = eventMeta and eventMeta.lastEventKey or nil
    local earned = pending and pending:match("^earned%.([a-z]+)$") or nil
    if not earned then
        meta.lastCoinHour = now
        if hash(seed .. ":chance") % 10000 >= 500 then
            return false, "chance"
        end
    end
    local nickname, source
    if earned then
        nickname, source = earnedNames[earned], "earned"
    elseif listenerRecord then
        nickname, source = genericName(listenerRecord, seed)
    else
        nickname = generalNames[(hash(seed .. ":player") % #generalNames) + 1]
    end
    if not nickname then return false, "name_unavailable" end
    if earned then
        if not putBounded(eventMeta.offered, pending, true) then
            return false, "event_capacity"
        end
    end
    local listenerFirst = firstName(listener, listenerRecord)
    if not speak(speakerActor, "nickname.coin", { listenerFirst, nickname }, seed) then
        if earned then eventMeta.offered[pending] = nil end
        return false, "speech_unavailable"
    end
    meta.lastCoinHour = now
    if earned then eventMeta.lastEventKey = nil end
    if not listenerRecord then
        local accepted = SC.Names.setPlayerNickname(listener, nickname)
        return accepted == true, accepted and "player_coined" or "player_unavailable"
    end
    local likes = hash(seed .. ":likes") % 100 < 85
    local listenerActor = actorFor(listener, listenerRecord)
    if likes then
        local accepted, reason = SC.Names.offer(listenerRecord, nickname,
            source, true)
        if not accepted then
            if earned then
                eventMeta.offered[pending] = nil
                eventMeta.lastEventKey = pending
            end
            return false, reason or "nickname_offer_failed"
        end
    else
        local private = meta.private
        local key = SC.Names.privateKey(listener)
        if private and key then putBounded(private, key, nickname, 16) end
    end
    queueReply(listenerActor,
        likes and "nickname.coin.accept" or "nickname.coin.reject",
        { listenerFirst, nickname }, seed .. ":reply")
    return true, likes and "nickname_coined" or "nickname_rejected"
end

return Life
