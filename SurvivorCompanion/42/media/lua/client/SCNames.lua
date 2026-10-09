-- SPDX-License-Identifier: MIT

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.Names = SC.Names or {}
local Names = SC.Names

local sources = {
    intro = true, profession = true, trait = true, place = true,
    earned = true, player = true,
}

local professionNames = {
    burglar = { "Slim", "Fingers", "Shadow" },
    burgerflipper = { "Fry", "Grease", "Combo" },
    carpenter = { "Sawdust", "Chips", "Plumb" },
    chef = { "Cookie", "Chef", "Gravy" },
    constructionworker = { "Hardhat", "Rebar", "Dozer" },
    doctor = { "Doc", "Scalpel" },
    electrician = { "Volts", "Fuse", "Amp" },
    engineer = { "Prof", "Gears", "Slide Rule" },
    farmer = { "Hayseed", "Clod", "Tractor" },
    fireofficer = { "Smokey", "Hose", "Cinders" },
    fisherman = { "Hooks", "Bait", "Catfish" },
    fitnessinstructor = { "Coach", "Reps" },
    lumberjack = { "Timber", "Stump", "Hatchet" },
    mechanics = { "Wrench", "Torque", "Grease Monkey" },
    metalworker = { "Rivets", "Torch" },
    nurse = { "Patches", "Band-Aid" },
    parkranger = { "Ranger", "Trail" },
    policeofficer = { "Badge", "Deputy", "Copper" },
    rancher = { "Tex", "Cowpoke", "Spurs" },
    repairman = { "Fix-It", "Duct Tape" },
    securityguard = { "Mall Cop", "Flashlight" },
    smither = { "Anvil", "Hammer" },
    tailor = { "Stitch", "Needles" },
    unemployed = { "Champ", "Couch" },
    veteran = { "Sarge", "Gunny", "Boots" },
}

local traitNames = {
    strong = { "Tank", "Bull" }, stout = { "Tank", "Bull" },
    weak = { "Twig", "Noodle" }, feeble = { "Twig", "Noodle" },
    athletic = { "Legs", "Wheels" }, fit = { "Legs", "Wheels" },
    jogger = { "Legs", "Wheels" }, outofshape = { "Puff" },
    unfit = { "Puff" }, clumsy = { "Butterfingers", "Thumbs" },
    allthumbs = { "Butterfingers", "Thumbs" },
    graceful = { "Cat", "Slick" }, dextrous = { "Cat", "Slick" },
    brave = { "Crash", "Rush" }, adrenalinejunkie = { "Crash", "Rush" },
    cowardly = { "Jumpy", "Rabbit" }, smoker = { "Smokes", "Ashtray" },
    conspicuous = { "Foghorn" }, inconspicuous = { "Ghost", "Whisper" },
    organized = { "Clipboard" }, outdoorsman = { "Mountain" },
    hiker = { "Mountain" }, shortsighted = { "Specs", "Four-Eyes" },
    eagleeyed = { "Hawk" }, catseyes = { "Owl" },
    hardofhearing = { "Huh", "Earmuffs" }, keenhearing = { "Ears" },
    thickskinned = { "Leather", "Rhino" }, irongut = { "Goat" },
    heartyappetite = { "Biscuit", "Seconds" }, lighteater = { "Bird" },
}

local familiarForms = {
    Abraham = "Abe", Barbara = "Barb", Caroline = "Carrie",
    Cassandra = "Cass", Christa = "Chrissy", Clementine = "Clem",
    Daniel = "Danny", David = "Dave", Edward = "Eddie",
    Elijah = "Eli", Eugene = "Gene", Ezekiel = "Zeke",
    Francine = "Frankie", Gabriel = "Gabe", Helena = "Lena",
    Herbert = "Herb", Howard = "Howie", Isabela = "Izzy",
    James = "Jimmy", Kenneth = "Ken", Madison = "Maddie",
    Matthew = "Matty", Michael = "Mikey", Nicole = "Nikki",
    Philip = "Phil", Rebecca = "Becca", Regina = "Gina",
    Robert = "Bobby", Roberta = "Bobbie", Rochelle = "Shelly",
    Samantha = "Sam", Stephen = "Steve", Theodore = "Teddy",
    Thomas = "Tommy", Victor = "Vic", William = "Billy",
}

local function config(key, fallback)
    local value
    if SC.Config and type(SC.Config.get) == "function" then
        value = SC.Config.get(key)
    end
    if value == nil then return fallback end
    return value
end

local function finite(value)
    value = tonumber(value)
    if value == nil or value ~= value or value == math.huge or value == -math.huge then
        return nil
    end
    return value
end

local function hash(value)
    local utility = SC.GameplayUtil
    if utility and type(utility.stableHash) == "function" then
        return math.abs(tonumber(utility.stableHash(value)) or 0)
    end
    local result = 0
    value = tostring(value or "")
    for index = 1, #value do
        result = (result * 33 + string.byte(value, index)) % 2147483647
    end
    return result
end

local function nowHours()
    if type(getGameTime) == "function" then
        local ok, time = pcall(getGameTime)
        if ok and time ~= nil then
            local called, hours = pcall(function() return time:getWorldAgeHours() end)
            if called and finite(hours) then return math.max(0, hours) end
        end
    end
    return 0
end

function Names.normalize(value)
    if type(value) ~= "string" then return nil end
    local cleaned = value:gsub("^%s+", ""):gsub("%s+$", "")
    local limit = math.max(2, math.min(64, math.floor(finite(config("nicknameMaxLength", 16)) or 16)))
    if #cleaned < 2 or #cleaned > limit
        or not cleaned:match("^[A-Za-z0-9 .'%-]+$") then return nil end
    return cleaned
end

function Names.make(value, source, likes, since)
    local cleaned = Names.normalize(value)
    source = source or "player"
    if cleaned == nil or sources[source] ~= true then return nil end
    local at = finite(since)
    return {
        text = cleaned, source = source,
        likes = likes ~= false, since = at and math.max(0, at) or nowHours(),
    }
end

function Names.normalizeRecord(value)
    if type(value) ~= "table" or type(value.text) ~= "string"
        or sources[value.source] ~= true
        or (value.likes ~= nil and type(value.likes) ~= "boolean")
        or (value.since ~= nil and (type(value.since) ~= "number"
            or finite(value.since) == nil or value.since < 0)) then
        return nil
    end
    return Names.make(value.text, value.source, value.likes, value.since or 0)
end

local function metaKey(value)
    return type(value) == "string" and #value > 0 and #value <= 48
        and value:match("^[A-Za-z0-9_.:%-]+$") ~= nil
end

function Names.normalizeMeta(value)
    if type(value) ~= "table" then return nil end
    local result = { offered = {}, events = {}, private = {}, used = {} }
    local hour = finite(value.lastCoinHour)
    if hour and hour >= 0 then result.lastCoinHour = hour end
    if metaKey(value.lastEventKey) then result.lastEventKey = value.lastEventKey end
    local count = 0
    for key, offered in pairs(type(value.offered) == "table" and value.offered or {}) do
        if count >= 64 then break end
        if metaKey(key) and offered == true then
            result.offered[key] = true
            count = count + 1
        end
    end
    count = 0
    for key, amount in pairs(type(value.events) == "table" and value.events or {}) do
        if count >= 64 then break end
        amount = finite(amount)
        if metaKey(key) and amount and amount >= 0 then
            result.events[key] = math.min(1000000, math.floor(amount))
            count = count + 1
        end
    end
    count = 0
    for key, nickname in pairs(type(value.private) == "table" and value.private or {}) do
        if count >= 16 then break end
        local cleaned = Names.normalize(nickname)
        if type(key) == "string" and key:match("^%d+$") and #key <= 16
            and cleaned then
            result.private[key] = cleaned
            count = count + 1
        end
    end
    count = 0
    for key, nickname in pairs(type(value.used) == "table" and value.used or {}) do
        if count >= 32 then break end
        local cleaned = Names.normalize(nickname)
        if type(key) == "string" and key:match("^%d+$") and #key <= 16
            and cleaned then
            result.used[key] = cleaned
            count = count + 1
        end
    end
    return result
end

local function recordFor(value)
    if type(value) == "table" and type(value.identity) == "table" then return value end
    local registry = SC.Registry
    if not registry or type(registry.byId) ~= "function" then return nil end
    local id = type(value) == "string" and value or nil
    if id == nil and type(value) == "table" and type(value.id) == "string" then
        id = value.id
    end
    if id == nil and type(registry.idOf) == "function" then id = registry.idOf(value) end
    return id and registry.byId(id) or nil
end

local function actorFor(value, record)
    if type(value) == "table" and type(value.identity) == "table" then
        return value.actor
    end
    if type(value) == "string" then return record and record.actor or nil end
    return value
end

local function modDataOf(actor)
    if actor == nil then return nil end
    local utility = SC.GameplayUtil
    if utility and type(utility.call) == "function" then
        local data, called = utility.call(actor, "getModData")
        if called and type(data) == "table" then return data end
    end
    local okay, data = pcall(function() return actor:getModData() end)
    return okay and type(data) == "table" and data or nil
end

local function playerNickname(value)
    local data = modDataOf(value)
    local cleaned = data and Names.normalize(data.SC_PlayerNickname) or nil
    return cleaned and Names.make(cleaned, "intro", true, 0) or nil
end

local function identityOf(value)
    local record = recordFor(value)
    local identity = record and record.identity or nil
    local actor = actorFor(value, record)
    local first = identity and identity.forename or nil
    local last = identity and identity.surname or nil
    if (first == nil or last == nil) and actor ~= nil then
        local utility = SC.GameplayUtil
        local descriptor, called
        if utility and utility.call then
            descriptor, called = utility.call(actor, "getDescriptor")
        end
        if called and descriptor then
            local valueFirst, firstOk = utility.call(descriptor, "getForename")
            local valueLast, lastOk = utility.call(descriptor, "getSurname")
            if first == nil and firstOk then first = valueFirst end
            if last == nil and lastOk then last = valueLast end
        end
    end
    first = type(first) == "string" and first ~= "" and first or nil
    last = type(last) == "string" and last ~= "" and last or nil
    if first == nil and actor ~= nil and SC.GameplayUtil
        and type(SC.GameplayUtil.nameOf) == "function" then
        local full = SC.GameplayUtil.nameOf(actor)
        first = type(full) == "string" and full:match("^(%S+)") or nil
    end
    return first or "friend", last
end

local function idOf(value)
    local record = recordFor(value)
    if record and type(record.id) == "string" then return record.id end
    if type(value) == "string" then return value end
    local utility = SC.GameplayUtil
    if utility and type(utility.idOf) == "function" then return utility.idOf(value) end
    return tostring(value)
end

function Names.privateKey(listener)
    return tostring(hash(idOf(listener)))
end

function Names.displayName(actorOrRecord, show)
    local first, last = identityOf(actorOrRecord)
    local record = recordFor(actorOrRecord)
    local nickname = show ~= false and config("nicknamesEnabled", true) ~= false
        and record and Names.normalizeRecord(record.nickname) or nil
    if nickname then first = first .. ' "' .. nickname.text .. '"' end
    return first .. (last and " " .. last or "")
end

local function usedNickname(speakerRecord, listener, nickname)
    local meta = speakerRecord and speakerRecord.nicknameMeta
    return type(meta) == "table" and type(meta.used) == "table"
        and meta.used[Names.privateKey(listener)] == nickname
end

local function rememberNickname(speakerRecord, listener, nickname)
    if not speakerRecord or speakerRecord == recordFor(listener) then return end
    local meta = speakerRecord.nicknameMeta
    if type(meta) ~= "table" then
        meta = {}
        speakerRecord.nicknameMeta = meta
    end
    if type(meta.used) ~= "table" then meta.used = {} end
    local key = Names.privateKey(listener)
    if meta.used[key] == nil then
        local count = 0
        for _ in pairs(meta.used) do count = count + 1 end
        if count >= 32 then return end
    end
    meta.used[key] = nickname
end

function Names.callName(speaker, listener, context)
    context = type(context) == "table" and context or {}
    local first, last = identityOf(listener)
    if config("nicknamesEnabled", true) == false then return first end
    local record = recordFor(listener)
    local nickname = record and Names.normalizeRecord(record.nickname)
        or playerNickname(listener)
    local speakerRecord = recordFor(speaker)
    local pair = SC.Community and type(SC.Community.relation) == "function"
        and SC.Community.relation(idOf(speaker), idOf(listener), false) or nil
    local familiarity = finite(pair and pair.familiarity) or 0
    local opinion = finite(pair and pair.opinion) or 0
    local tension = finite(pair and pair.tension) or 0
    local familiar = familiarity >= (finite(config("nicknameFamiliarForm", 60)) or 60)
        and familiarForms[first] or nil
    local ordinary = familiar or first
    if nickname and context.about then
        return (context.usedBefore == true
            or usedNickname(speakerRecord, listener, nickname.text))
            and nickname.text or first
    end
    if nickname and context.urgent then
        if #nickname.text < #first then
            rememberNickname(speakerRecord, listener, nickname.text)
            return nickname.text
        end
        return first
    end
    local rival = tension >= (finite(config("nicknameRivalTension", 50)) or 50)
        or opinion <= -30
    local seed = tostring(idOf(speaker)) .. ":" .. tostring(idOf(listener))
        .. ":" .. tostring(context.salt or "")
    local roll = hash(seed) % 10000
    local private = speakerRecord and type(speakerRecord.nicknameMeta) == "table"
        and type(speakerRecord.nicknameMeta.private) == "table"
        and Names.normalize(speakerRecord.nicknameMeta.private[Names.privateKey(listener)])
        or nil
    if rival then
        if private and roll < 5000 then return private end
        if nickname and nickname.likes == false and roll < 5000 then
            rememberNickname(speakerRecord, listener, nickname.text)
            return nickname.text
        end
        return last or ordinary
    end
    if nickname == nil then return ordinary end
    local introduced = nickname.source == "intro"
    local friendly = familiarity >= (finite(config("nicknameFamiliarity", 25)) or 25)
        and opinion >= (finite(config("nicknameFriendlyOpinion", 15)) or 15)
    if nickname.likes == false or not (introduced or friendly) then return ordinary end
    local chance = finite(config("nicknameAddressChance", 0.4)) or 0.4
    if chance > 1 then chance = chance / 100 end
    chance = math.max(0, math.min(1, chance))
    if roll < chance * 10000 then
        rememberNickname(speakerRecord, listener, nickname.text)
        return nickname.text
    end
    return ordinary
end

function Names.setNickname(actorOrRecord, value, source, likes)
    local record = recordFor(actorOrRecord)
    if record == nil then return false, "companion_unavailable" end
    if source == "player" and likes == nil then
        likes = hash(tostring(record.id or "") .. ":player:"
            .. tostring(value or "")) % 100 < 85
    end
    local nickname = Names.make(value, source, likes)
    if nickname == nil then return false, "invalid_nickname" end
    if type(record.nickname) == "table" and record.nickname.source == "player"
        and nickname.source ~= "player" then return false, "player_nickname_retained" end
    record.nickname = nickname
    return true, "nickname_set", nickname
end

function Names.offer(actorOrRecord, value, source, likes)
    local record = recordFor(actorOrRecord)
    if record == nil then return false, "companion_unavailable" end
    if Names.normalizeRecord(record.nickname) then return false, "nickname_exists" end
    local nickname = Names.make(value, source, likes)
    if nickname == nil then return false, "invalid_nickname" end
    record.nickname = nickname
    return true, "nickname_offered", nickname
end

function Names.clearNickname(actorOrRecord)
    local record = recordFor(actorOrRecord)
    if record == nil then return false, "companion_unavailable" end
    record.nickname = nil
    return true, "nickname_cleared"
end

function Names.setPlayerNickname(player, value)
    local data = modDataOf(player)
    if data == nil then return false, "player_unavailable" end
    local cleaned = Names.normalize(value)
    if cleaned == nil then return false, "invalid_nickname" end
    data.SC_PlayerNickname = cleaned
    return true, "player_nickname_set", cleaned
end

function Names.clearPlayerNickname(player)
    local data = modDataOf(player)
    if data == nil then return false, "player_unavailable" end
    data.SC_PlayerNickname = nil
    return true, "player_nickname_cleared"
end

function Names.ensureIntro(recordOrProfile, actor)
    if type(recordOrProfile) ~= "table" or recordOrProfile.restored == true
        or config("nicknamesEnabled", true) == false then return nil end
    if recordOrProfile.factionId and SC.Factions
        and type(SC.Factions.group) == "function" then
        local group = SC.Factions.group(recordOrProfile.factionId)
        if type(group) == "table" and type(group.oddball) == "table" then return nil end
    end
    local existing = Names.normalizeRecord(recordOrProfile.nickname)
    if existing then return existing end
    local identity = type(recordOrProfile.identity) == "table"
        and recordOrProfile.identity or recordOrProfile
    local state = type(recordOrProfile.state) == "table" and recordOrProfile.state or {}
    local personality = type(state.personality) == "table" and state.personality or {}
    local background = type(personality.background) == "table" and personality.background or {}
    local seed = tostring(recordOrProfile.id or identity.visualSeed
        or ((identity.forename or "") .. ":" .. (identity.surname or "")))
    local chance = finite(config("nicknameIntroChance", 0.12)) or 0.12
    if chance > 1 then chance = chance / 100 end
    chance = math.max(0, math.min(1, chance))
    if hash(seed .. ":intro-chance") % 10000 >= chance * 10000 then return nil end
    local options = {}
    local profession = tostring(background.profession or ""):gsub("^base:", "")
    for _, value in ipairs(professionNames[profession] or {}) do options[#options + 1] = value end
    local traits = SC.Background and type(SC.Background.characterTraits) == "function"
        and SC.Background.characterTraits(background) or {}
    for _, trait in ipairs(traits) do
        local code = tostring(trait.id or ""):gsub("^base:", "")
            :gsub("[^%a]", ""):lower()
        for _, value in ipairs(traitNames[code] or {}) do options[#options + 1] = value end
    end
    if #options == 0 then return nil end
    local choice = options[(hash(seed .. ":intro-name") % #options) + 1]
    local nickname = Names.make(choice, "intro", true)
    recordOrProfile.nickname = nickname
    return nickname
end

return Names
