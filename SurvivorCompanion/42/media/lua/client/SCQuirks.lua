-- SPDX-License-Identifier: MIT

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
if not SC.GameplayUtil and type(require) == "function" then pcall(require, "SCGameplayUtil") end

SC.Quirks = SC.Quirks or {}
local Quirks = SC.Quirks

local episodes = setmetatable({}, { __mode = "k" })
local recognition = setmetatable({}, { __mode = "k" })
local shrineReservations = setmetatable({}, { __mode = "k" })

local ritualIds = {
    spiffo_salute = true,
    bourbon_blessing = true,
    mannequin_apology = true,
    gnome_commander = true,
    sports_pep_talk = true,
    rubber_duck_oracle = true,
}

local ritualLabels = {
    spiffo_salute = "Salutes Spiffo signs",
    bourbon_blessing = "Blesses Kentucky bourbon",
    mannequin_apology = "Apologizes to mannequins",
    gnome_commander = "Reports to garden-gnome command",
    sports_pep_talk = "Gives the old team a pep talk",
    rubber_duck_oracle = "Worships the Rubber Duck",
}

local genericEmotes = {
    spiffo_salute = "salute",
    bourbon_blessing = "thankyou",
    mannequin_apology = "wavehi",
    gnome_commander = "salute",
    sports_pep_talk = "clap",
}

local function U() return SC.GameplayUtil end

local function finite(value, fallback)
    value = tonumber(value)
    if value == nil or value ~= value or value == math.huge or value == -math.huge then
        return fallback
    end
    return value
end

local function boundedText(value, maximum)
    value = tostring(value or ""):gsub("[%c]", " ")
    return string.sub(value, 1, maximum or 96)
end

local function simNow()
    if SC.LifeEvents and type(SC.LifeEvents.now) == "function" then
        return finite(SC.LifeEvents.now(), U().nowMs())
    end
    return U().nowMs()
end

local function hours(value) return math.floor(finite(value, 0) * 3600000) end

local function commandState(actor, supplied)
    if type(supplied) == "table" then return supplied end
    if SC.Commands and type(SC.Commands.peek) == "function" then
        local ok, state = pcall(SC.Commands.peek, actor)
        if ok and type(state) == "table" then return state end
    end
    return nil
end

local function persist(actor)
    if SC.Commands and type(SC.Commands.persist) == "function" then
        local ok, saved = pcall(SC.Commands.persist, actor)
        return ok and saved == true
    end
    return false
end

local function stageFor(completions)
    completions = math.max(0, math.floor(finite(completions, 0)))
    if completions >= 7 then return "tradition" end
    if completions >= 3 then return "routine" end
    return "quirk"
end

local function normalizedDuck(source)
    source = type(source) == "table" and source or {}
    local phase = source.phase
    if phase ~= "awaiting_base" and phase ~= "carried" and phase ~= "displayed"
        and phase ~= "recovery_pending" and phase ~= "lost" then phase = "carried" end
    local result = {
        relicKey = boundedText(source.relicKey, 128),
        phase = phase,
        baseId = boundedText(source.baseId, 64),
    }
    if finite(source.x, nil) ~= nil and finite(source.y, nil) ~= nil
        and finite(source.z, nil) ~= nil then
        result.x = math.floor(finite(source.x, 0))
        result.y = math.floor(finite(source.y, 0))
        result.z = math.floor(finite(source.z, 0))
    end
    return result
end

function Quirks.normalize(source)
    source = type(source) == "table" and source or {}
    local id = ritualIds[source.id] and source.id or nil
    local completions = math.max(0, math.min(999, math.floor(finite(source.completions, 0))))
    local result = {
        version = 1,
        id = id,
        completions = completions,
        stage = id and stageFor(completions) or nil,
        lastAt = math.max(0, math.floor(finite(source.lastAt, 0))),
        lastObjectKey = boundedText(source.lastObjectKey, 160),
        convertedFromId = ritualIds[source.convertedFromId] and source.convertedFromId or nil,
    }
    if id == "rubber_duck_oracle" or type(source.duck) == "table" then
        result.duck = normalizedDuck(source.duck)
    end
    return result
end

local function ensureRitual(state)
    if type(state) ~= "table" then return nil end
    state.ritual = Quirks.normalize(state.ritual)
    return state.ritual
end

function Quirks.describe(source)
    local ritual = Quirks.normalize(source)
    if not ritual.id then
        return { known = false, id = nil, stage = nil, completions = 0 }
    end
    local duck = ritual.duck
    return {
        known = true,
        id = ritual.id,
        label = ritualLabels[ritual.id] or ritual.id,
        stage = ritual.stage,
        completions = ritual.completions,
        relicStatus = duck and duck.phase or nil,
        convertedFromId = ritual.convertedFromId,
    }
end

local function isDuck(item)
    return item ~= nil and U().itemType(item) == "Base.Rubberducky"
end

local function personalRecord(item)
    if SC.PersonalItems and type(SC.PersonalItems.personalRecord) == "function" then
        return SC.PersonalItems.personalRecord(item)
    end
    return nil
end

local function relicItem(actor, ritual)
    local duck = ritual and ritual.duck
    if not duck or duck.relicKey == "" then return nil end
    if SC.PersonalItems and type(SC.PersonalItems.find) == "function" then
        local ok, item = pcall(SC.PersonalItems.find, actor, duck.relicKey)
        if ok and isDuck(item) then return item end
    end
    return nil
end

function Quirks.acceptsLoot(actor, item, suppliedState)
    if not isDuck(item) then return false end
    local state = commandState(actor, suppliedState)
    if type(state) ~= "table" then return false end
    local ritual = Quirks.normalize(state.ritual)
    if ritual.id ~= "rubber_duck_oracle" then return true end
    if relicItem(actor, ritual) then return false end
    return not ritual.duck or ritual.duck.phase == "lost"
end

function Quirks.itemDesireBonus(actor, item, suppliedState)
    if not Quirks.acceptsLoot(actor, item, suppliedState) then return 0, nil end
    return U().config("duckRitualPickupScore") or 140, "personal"
end

local function atBase(actor)
    return SC.BaseLife and type(SC.BaseLife.active) == "function" and SC.BaseLife.active() ~= nil
        and type(SC.BaseLife.isInside) == "function" and SC.BaseLife.isInside(actor) == true
end

function Quirks.onVerifiedLoot(actor, item, suppliedState)
    if not actor or not isDuck(item) then return false, "not_rubber_duck" end
    local state = commandState(actor, suppliedState)
    if type(state) ~= "table" then return false, "command_state_unavailable" end
    local ritual = ensureRitual(state)
    local currentRelic = relicItem(actor, ritual)
    if currentRelic and currentRelic ~= item then return false, "duck_relic_already_owned" end

    local key = tostring(U().idOf(actor)) .. ":ritual:duck"
    if SC.PersonalItems and type(SC.PersonalItems.restoreMarker) == "function" then
        local marked, reason = SC.PersonalItems.restoreMarker(item, {
            version = 1, ownerId = U().idOf(actor), key = key, kind = "duck_relic",
        }, true)
        if marked ~= true then return false, reason or "duck_marker_failed" end
    end

    local converted = ritual.id ~= "rubber_duck_oracle"
    if converted then
        ritual.convertedFromId = ritual.id
        ritual.id = "rubber_duck_oracle"
        ritual.completions = 0
        ritual.stage = "quirk"
        ritual.lastAt = 0
        ritual.lastObjectKey = ""
    end
    ritual.duck = normalizedDuck({
        relicKey = key,
        -- "awaiting_base" also means the first ceremony is pending. If the
        -- find happens inside camp, autonomy may perform it immediately.
        phase = "awaiting_base",
        baseId = "",
    })
    state.ritual = ritual
    persist(actor)
    if SC.Dialogue and type(SC.Dialogue.say) == "function" then
        SC.Dialogue.say(actor, "ritual.duck.discovery", nil, nil, {
            state = state, recentLimit = 4,
            salt = tostring(U().idOf(actor)) .. ":duck-found",
            fallback = "Well now. The Duck has found me.",
        })
    end
    if SC.Relationship and type(SC.Relationship.playEmote) == "function" then
        pcall(SC.Relationship.playEmote, actor, converted and "thumbsup" or "thankyou")
    end
    return true, "duck_devotion_started", ritual
end

local femaleNames = { "Loretta", "Marlene", "Tammy", "Louise", "Darlene", "Becky", "June", "Wanda" }
local maleNames = { "Dillard", "Earl", "Waylon", "Mercer", "Bobby", "Lester", "Hank", "Ray" }
local surnames = { "Talbot", "McCrary", "Hensley", "Pruitt", "Givens", "Ratliff", "Boone", "Copley" }

local professionRoles = {
    fitness_instructor = "old football coach", fitnessinstructor = "old football coach",
    burger_flipper = "fryer-shift manager", burgerflipper = "fryer-shift manager",
    police_officer = "county deputy", policeofficer = "county deputy",
    veteran = "former sergeant", farmer = "feed-store regular", rancher = "neighboring rancher",
    mechanic = "garage foreman", nurse = "night-shift nurse", doctor = "clinic doctor",
    teacher = "high-school teacher", librarian = "county librarian", chef = "kitchen boss",
    construction_worker = "site foreman", carpenter = "site foreman",
}

local function pronouns(gender)
    gender = string.lower(tostring(gender or ""))
    if gender == "female" or gender == "woman" then
        return { subject = "she", object = "her", possessive = "her", label = "woman" }
    elseif gender == "male" or gender == "man" then
        return { subject = "he", object = "him", possessive = "his", label = "man" }
    end
    return { subject = "they", object = "them", possessive = "their", label = "person" }
end

local function zombieGender(threat)
    local female, ok = U().call(threat, "isFemale")
    if ok then return female == true and "female" or "male" end
    return nil
end

local function recognitionRuntime(actor)
    local state = recognition[actor]
    if not state then
        state = { recognized = setmetatable({}, { __mode = "k" }), nextAt = 0 }
        recognition[actor] = state
    end
    return state
end

local function localIdentity(actor, threat, state, current)
    local gender = zombieGender(threat)
    local p = pronouns(gender)
    local background = type(state.background) == "table" and state.background or {}
    local occupation = string.lower(tostring(background.occupation or ""))
    local role = professionRoles[occupation] or "someone from back home"
    local home = boundedText(background.home ~= nil and background.home or "Kentucky", 40)
    home = home:gsub("_", " ")
    local seed = tostring(U().idOf(actor)) .. ":" .. tostring(threat) .. ":" .. tostring(current)
    local names = gender == "female" and femaleNames or gender == "male" and maleNames or surnames
    local first = names[(U().stableHash(seed .. ":first") % #names) + 1]
    local last = surnames[(U().stableHash(seed .. ":last") % #surnames) + 1]
    return {
        source = "local", topic = "recognition.local", name = first .. " " .. last,
        gender = gender, pronoun = p, role = role, home = home,
        thoughtStress = 3, thoughtMorale = -1,
    }
end

function Quirks.recognitionCandidate(actor, threat, snapshot, suppliedState, current, force)
    if not actor or not threat or U().isDead(threat) then return nil end
    snapshot = type(snapshot) == "table" and snapshot or {}
    local count = tonumber(snapshot.threatCount) or #(snapshot.threats or {})
    local immediate = tonumber(snapshot.immediateCount) or #(snapshot.immediateAttackers or {})
    if count ~= 1 or immediate > 0 then return nil end
    local state = commandState(actor, suppliedState)
    if type(state) ~= "table" or state.recruited ~= true then return nil end
    local runtime = recognitionRuntime(actor)
    if runtime.recognized[threat] or simNow() < finite(runtime.nextAt, 0) then return nil end
    local standing, standingOk = U().call(threat, "isOnFloor")
    if standingOk and standing == true then return nil end

    local grief = SC.Community and type(SC.Community.activeGrief) == "function"
        and SC.Community.activeGrief(actor) or nil
    local chance = finite(U().config("recognitionChancePercent"), 8)
    if finite(state.stress, 0) >= 65 then
        chance = chance + finite(U().config("recognitionStressBonusPercent"), 4)
    end
    if grief then chance = chance + finite(U().config("recognitionGriefBonusPercent"), 4) end
    local bucket = math.floor((tonumber(current) or U().nowMs()) / 250)
    local roll = U().stableHash(tostring(U().idOf(actor)) .. ":recognize:"
        .. tostring(threat) .. ":" .. tostring(bucket)) % 100
    if force ~= true and roll >= chance then return nil end

    local result
    if type(grief) == "table" and type(grief.subjectName) == "string" then
        local p = pronouns(grief.subjectGender)
        result = {
            source = "grief", topic = "recognition.grief",
            name = boundedText(grief.subjectName, 80), gender = grief.subjectGender,
            pronoun = p, role = "one of ours", home = "Kentucky",
            thoughtStress = 6, thoughtMorale = -3,
            subjectId = grief.subjectId,
        }
    else
        result = localIdentity(actor, threat, state, current or U().nowMs())
    end
    result.target = threat
    result.arguments = {
        result.name, result.pronoun.subject, result.role, result.home,
        result.pronoun.object, result.pronoun.possessive,
    }
    return result
end

function Quirks.speakRecognition(actor, candidate, suppliedState, current)
    if not actor or type(candidate) ~= "table" or not candidate.target then
        return false, "invalid_recognition"
    end
    local state = commandState(actor, suppliedState)
    local spoken, line
    if SC.Dialogue and type(SC.Dialogue.say) == "function" then
        spoken, line = SC.Dialogue.say(actor, candidate.topic, nil, candidate.arguments, {
            state = state, recentLimit = 8,
            salt = tostring(candidate.target) .. ":" .. tostring(current),
            fallback = "That walker looks familiar. Keep your distance.",
        })
    else
        line = "That walker looks familiar. Keep your distance."
        spoken = U().say(actor, line)
    end
    if spoken ~= true then return false, line or "recognition_speech_rejected" end

    local runtime = recognitionRuntime(actor)
    runtime.recognized[candidate.target] = true
    runtime.nextAt = simNow() + hours(U().config("recognitionCooldownGameHours") or 6)
    local resolveRoll = U().stableHash(tostring(U().idOf(actor)) .. ":resolve:"
        .. tostring(candidate.target) .. ":" .. tostring(current)) % 100
    runtime.pending = {
        target = candidate.target,
        source = candidate.source,
        name = candidate.name,
        shouldResolve = resolveRoll < (U().config("recognitionResolutionChancePercent") or 25),
        expiresAt = simNow() + hours(U().config("recognitionResolutionExpiryGameHours") or 4),
    }
    if SC.Community and type(SC.Community.addThought) == "function" then
        SC.Community.addThought(actor, {
            key = "zombie_recognition:" .. tostring(candidate.target),
            kind = "zombie_recognition",
            text = "A walker looked like " .. tostring(candidate.name) .. ".",
            stress = candidate.thoughtStress, morale = candidate.thoughtMorale,
            at = simNow(),
            expiresAt = simNow() + hours(U().config("recognitionThoughtGameHours") or 4),
            sourceId = candidate.subjectId,
            targetId = U().idOf(actor),
        })
    end
    persist(actor)
    return true, line
end

function Quirks.observeRecognitionResolution(actor, snapshot, suppliedState, current)
    local runtime = recognition[actor]
    local pending = runtime and runtime.pending or nil
    if not pending then return false, "recognition_resolution_none" end
    if simNow() >= finite(pending.expiresAt, 0) then
        runtime.pending = nil
        return false, "recognition_resolution_expired"
    end
    snapshot = type(snapshot) == "table" and snapshot or {}
    local threats = tonumber(snapshot.threatCount) or #(snapshot.threats or {})
    local immediate = tonumber(snapshot.immediateCount) or #(snapshot.immediateAttackers or {})
    if threats > 0 or immediate > 0 or not U().isDead(pending.target) then
        return false, "recognition_resolution_waiting"
    end
    runtime.pending = nil
    if pending.shouldResolve ~= true then return false, "recognition_resolution_roll" end
    local topic = pending.source == "grief" and "recognition.resolve.grief"
        or "recognition.resolve.local"
    if SC.Dialogue and type(SC.Dialogue.say) == "function" then
        return SC.Dialogue.say(actor, topic, nil, { pending.name }, {
            state = commandState(actor, suppliedState), recentLimit = 6,
            salt = tostring(current), fallback = "No. Wasn't them. I don't think.",
        })
    end
    return U().say(actor, "No. Wasn't them. I don't think."), topic
end

local function safeContext(actor, player, snapshot, state)
    if not actor or not state or state.recruited ~= true or U().isDead(actor) then return false end
    snapshot = type(snapshot) == "table" and snapshot or {}
    if (tonumber(snapshot.threatCount) or #(snapshot.threats or {})) > 0
        or (tonumber(snapshot.immediateCount) or #(snapshot.immediateAttackers or {})) > 0
        or finite(snapshot.pressure, 0) > 0 or U().nativeHealth(actor) < 70 then return false end
    if not atBase(actor) then return false end
    if player then
        local moving, movingOk = U().call(player, "isMoving")
        if state.order == "follow" and movingOk and moving == true then return false end
        if not U().sameFloor(actor, player) or U().distance(actor, player) > 12 then return false end
    end
    return true
end

local function objectSpriteName(object)
    local name, ok = U().call(object, "getSpriteName")
    if ok and name then return string.lower(tostring(name)) end
    local sprite, spriteOk = U().call(object, "getSprite")
    if spriteOk and sprite then
        name, ok = U().call(sprite, "getName")
        if ok and name then return string.lower(tostring(name)) end
    end
    if type(object) == "table" then return string.lower(tostring(object.spriteName or object.name or "")) end
    return ""
end

local function triggerForObject(object)
    if U().instanceOf(object, "IsoMannequin") then return "mannequin_apology" end
    local name = objectSpriteName(object)
    if string.find(name, "spiffo", 1, true) then return "spiffo_salute" end
    if string.find(name, "gnome", 1, true) then return "gnome_commander" end
    return nil
end

local function triggerForItem(item)
    local itemType = string.lower(U().itemType(item))
    if string.find(itemType, "bourbon", 1, true)
        or string.find(itemType, "whiskey", 1, true) then return "bourbon_blessing" end
    if string.find(itemType, "football", 1, true)
        or string.find(itemType, "basketball", 1, true)
        or string.find(itemType, "baseball", 1, true) then return "sports_pep_talk" end
    return nil
end

local function affinity(actor, state, id)
    local profile = type(state.personalityProfile) == "table" and state.personalityProfile or {}
    local background = type(state.background) == "table" and state.background or {}
    local occupation = string.lower(tostring(background.occupation or ""))
    local score = U().stableHash(tostring(U().idOf(actor)) .. ":ritual:" .. id) % 31
    if id == "spiffo_salute" and (string.find(occupation, "burger", 1, true)
        or string.find(occupation, "chef", 1, true)) then score = score + 60 end
    if id == "bourbon_blessing" and (occupation == "veteran" or occupation == "farmer") then
        score = score + 45
    end
    if id == "sports_pep_talk" and string.find(occupation, "fitness", 1, true) then
        score = score + 70
    end
    if id == "mannequin_apology" then score = score + finite(profile.compassion, 50) * 0.4 end
    if id == "gnome_commander" then score = score + finite(profile.courage, 50) * 0.35 end
    if id == "bourbon_blessing" then score = score + finite(profile.practicality, 50) * 0.2 end
    return score
end

local function genericOpportunity(actor, state, wanted)
    local best, bestScore
    for _, item in ipairs(U().inventoryItems(U().inventory(actor), 128)) do
        local id = triggerForItem(item)
        if id and (wanted == nil or wanted == id) then
            local score = affinity(actor, state, id)
            if not bestScore or score > bestScore then
                best, bestScore = { id = id, item = item, key = U().itemType(item) }, score
            end
        end
    end
    local ax, ay, az = U().position(actor)
    if not ax then return best end
    local radius = math.max(1, math.floor(U().config("ritualScanRadius") or 4))
    local squareBudget = math.max(1, math.floor(U().config("ritualSquareBudget") or 25))
    local objectBudget = math.max(1, math.floor(U().config("ritualObjectBudget") or 40))
    local squares, objects = 0, 0
    for distance = 0, radius do
        for dx = -distance, distance do
            for dy = -distance, distance do
                if math.max(math.abs(dx), math.abs(dy)) == distance and squares < squareBudget
                    and objects < objectBudget then
                    local square = U().gridSquare(math.floor(ax + dx), math.floor(ay + dy), math.floor(az))
                    squares = squares + 1
                    if square then
                        U().squareObjects(square, function(object)
                            objects = objects + 1
                            local id = triggerForObject(object)
                            if id and (wanted == nil or wanted == id) then
                                local score = affinity(actor, state, id) - U().distance(actor, square) * 3
                                if not bestScore or score > bestScore then
                                    best, bestScore = {
                                        id = id, object = object, square = square,
                                        key = U().squareKey(square) .. ":" .. objectSpriteName(object),
                                    }, score
                                end
                            end
                            return objects < objectBudget
                        end, objectBudget - objects)
                    end
                end
            end
        end
    end
    return best
end

local function validShrineSquare(square, actor)
    if not square or not U().isSquareFree(square) then return false end
    if SC.BaseLife and type(SC.BaseLife.isInside) == "function"
        and SC.BaseLife.isInside(square) ~= true then return false end
    local fire, fireOk = U().call(square, "getFire")
    if fireOk and fire ~= nil then return false end
    local glass, glassOk = U().call(square, "getBrokenGlass")
    if glassOk and glass ~= nil then return false end
    return shrineReservations[square] == nil or shrineReservations[square] == actor
end

local function shrineSquare(actor)
    local centers = {}
    if SC.BaseLife and type(SC.BaseLife.zoneCenter) == "function" then
        centers[#centers + 1] = SC.BaseLife.zoneCenter("social")
        centers[#centers + 1] = SC.BaseLife.zoneCenter("rest")
    end
    centers[#centers + 1] = U().squareOf(actor)
    for _, center in ipairs(centers) do
        local base = center and (U().loadedSquare(center) or center) or nil
        local x, y, z = U().position(base)
        if x then
            for radius = 0, 2 do
                for dx = -radius, radius do
                    for dy = -radius, radius do
                        if math.max(math.abs(dx), math.abs(dy)) == radius then
                            local square = U().gridSquare(math.floor(x + dx), math.floor(y + dy), math.floor(z))
                            if validShrineSquare(square, actor) then return square end
                        end
                    end
                end
            end
        end
    end
    return nil
end

local function worldItems(square)
    local result = {}
    local list, ok = U().call(square, "getWorldObjects")
    if ok and list then U().each(list, 64, function(value) result[#result + 1] = value end) end
    if #result == 0 and type(square) == "table" and type(square.worldItems) == "table" then
        for _, value in ipairs(square.worldItems) do result[#result + 1] = value end
    end
    return result
end

local function worldRelic(ritual)
    local duck = ritual and ritual.duck
    if not duck or duck.x == nil then return nil, nil end
    local square = U().gridSquare(duck.x, duck.y, duck.z)
    if not square then return nil, nil end
    for _, worldItem in ipairs(worldItems(square)) do
        local item = select(1, U().call(worldItem, "getItem"))
        if not item and type(worldItem) == "table" then item = worldItem.item end
        local personal = item and personalRecord(item) or nil
        if isDuck(item) and personal and personal.key == duck.relicKey then
            return worldItem, item, square
        end
    end
    return nil, nil, square
end

local function dueForRitual(ritual, current)
    return current >= finite(ritual.lastAt, 0)
        + hours(U().config("ritualCooldownGameHours") or 24)
end

function Quirks.ritualIntent(actor, player, snapshot, suppliedState)
    local state = commandState(actor, suppliedState)
    if not safeContext(actor, player, snapshot, state) then return nil end
    local episode = episodes[actor]
    if episode then
        return { kind = "ritual", priority = episode.recovery and 84 or 72,
            ritual = episode.id, active = true }
    end
    local ritual = ensureRitual(state)
    local current = simNow()
    if ritual.id == "rubber_duck_oracle" then
        local duck = ritual.duck or normalizedDuck(nil)
        ritual.duck = duck
        if atBase(actor) and (duck.phase == "displayed" or duck.phase == "recovery_pending") then
            return { kind = "ritual", priority = 84, ritual = ritual.id, recovery = true }
        end
        local item = relicItem(actor, ritual)
        if item and atBase(actor) and (duck.phase == "awaiting_base"
            or duck.phase == "carried" and dueForRitual(ritual, current)) then
            return { kind = "ritual", priority = duck.phase == "awaiting_base" and 74 or 48,
                ritual = ritual.id, item = item }
        end
        if not item and duck.phase ~= "lost" then
            duck.phase = "lost"
            persist(actor)
        end
        return nil
    end
    if ritual.id and not dueForRitual(ritual, current) then return nil end
    if not U().isDue(actor, "ritual_scan", U().config("ritualScanIntervalMs") or 10000,
        U().nowMs()) then return nil end
    local opportunity = genericOpportunity(actor, state, ritual.id)
    if not opportunity then return nil end
    return { kind = "ritual", priority = 34, ritual = opportunity.id,
        opportunity = opportunity }
end

local function clearVisual(actor)
    if SC.NativeActions and type(SC.NativeActions.clearVisual) == "function" then
        pcall(SC.NativeActions.clearVisual, actor)
    end
end

local function visualStatus(actor)
    if SC.NativeActions and type(SC.NativeActions.visualStatus) == "function" then
        local ok, status = pcall(SC.NativeActions.visualStatus, actor, "loot_container")
        if ok then return status end
    end
    return nil
end

local function startLootVisual(actor, episode, nextStage)
    local started, reason = U().move(actor, "walk", {
        action = "loot_container", lootPosition = "Low", item = episode.item,
        ritual = episode.id,
    })
    if started ~= true then return false, reason or "ritual_visual_rejected" end
    episode.stage = "visual_wait"
    episode.visualNext = nextStage
    return true, "ritual_visual_started"
end

local function completeRitual(actor, state, ritual, objectKey)
    ritual.completions = math.min(999, math.max(0, finite(ritual.completions, 0)) + 1)
    ritual.stage = stageFor(ritual.completions)
    ritual.lastAt = simNow()
    ritual.lastObjectKey = boundedText(objectKey, 160)
    state.ritual = ritual
    if SC.Community and type(SC.Community.addThought) == "function" then
        SC.Community.addThought(actor, {
            key = "ritual:" .. tostring(ritual.id), kind = "personal_ritual",
            text = "Keeping my ritual made this place feel a little more like ours.",
            stress = -2, morale = 1, at = simNow(), expiresAt = simNow() + hours(6),
            targetId = U().idOf(actor),
        })
    end
    persist(actor)
end

local function beginEpisode(actor, detail, state)
    local ritual = ensureRitual(state)
    local id = detail.ritual
    if id == "rubber_duck_oracle" then
        local recovery = detail.recovery == true
            or ritual.duck and (ritual.duck.phase == "displayed"
                or ritual.duck.phase == "recovery_pending")
        local square, item, worldItem
        if recovery then
            worldItem, item, square = worldRelic(ritual)
            if not square and ritual.duck and ritual.duck.x ~= nil then
                return nil, "duck_square_unloaded"
            end
            if not worldItem then
                local carried = relicItem(actor, ritual)
                if carried then
                    ritual.duck.phase = "carried"
                    persist(actor)
                    return nil, "duck_already_recovered"
                end
                ritual.duck.phase = "lost"
                ritual.duck.x, ritual.duck.y, ritual.duck.z = nil, nil, nil
                persist(actor)
                return nil, "duck_relic_missing"
            end
        else
            item = relicItem(actor, ritual)
            square = shrineSquare(actor)
            if not item then return nil, "duck_relic_not_carried" end
            if not square then return nil, "duck_shrine_unavailable" end
        end
        shrineReservations[square] = actor
        local episode = {
            id = id, ritual = ritual, item = item, worldItem = worldItem,
            square = square, recovery = recovery, stage = "approach",
            objectKey = U().squareKey(square) .. ":rubber_duck",
        }
        episodes[actor] = episode
        return episode
    end
    local opportunity = detail.opportunity
    if type(opportunity) ~= "table" then return nil, "ritual_opportunity_missing" end
    local episode = {
        id = id, ritual = ritual, item = opportunity.item,
        object = opportunity.object, square = opportunity.square,
        objectKey = opportunity.key, stage = "approach",
    }
    episodes[actor] = episode
    return episode
end

local function sayRitual(actor, episode, state)
    local stage = stageFor(finite(episode.ritual.completions, 0) + 1)
    local topic = episode.id == "rubber_duck_oracle"
        and "ritual.duck." .. stage or "ritual." .. episode.id
    local fallback = episode.id == "rubber_duck_oracle"
        and "General Quack, your survivor reports." or "Still doing this. Still alive."
    if SC.Dialogue and type(SC.Dialogue.say) == "function" then
        return SC.Dialogue.say(actor, topic, nil, nil, {
            state = state, recentLimit = 8,
            salt = tostring(episode.objectKey) .. ":" .. tostring(episode.ritual.completions),
            fallback = fallback,
        })
    end
    return U().say(actor, fallback), fallback
end

local function duckEmotes(ritual)
    local stage = stageFor(finite(ritual.completions, 0) + 1)
    if stage == "tradition" then return { "surrender", "clap", "salute" } end
    if stage == "routine" then return { "surrender", "thankyou" } end
    return { "undecided", "thankyou" }
end

local function finishEpisode(actor, state, episode, completed, reason)
    if episode.square and shrineReservations[episode.square] == actor then
        shrineReservations[episode.square] = nil
    end
    clearVisual(actor)
    episodes[actor] = nil
    if completed then completeRitual(actor, state, episode.ritual, episode.objectKey) end
    return completed == true, reason
end

local function updateDuck(actor, state, episode)
    local ritual, duck = episode.ritual, episode.ritual.duck
    if episode.stage == "approach" then
        if U().distance(actor, episode.square) > (U().config("duckRitualApproachRange") or 1.25) then
            if SC.Navigation and type(SC.Navigation.request) == "function" then
                local accepted, reason = SC.Navigation.request(actor, episode.square, "walk", {
                    purpose = episode.recovery and "duck_recovery" or "duck_worship",
                })
                return accepted == true, accepted and "approaching_duck_shrine" or reason
            end
            return false, "duck_navigation_unavailable"
        end
        U().stop(actor)
        if episode.recovery then
            return startLootVisual(actor, episode, "pickup")
        end
        return startLootVisual(actor, episode, "place")
    end
    if episode.stage == "visual_wait" then
        local status = visualStatus(actor)
        if status == "active" then return true, "duck_visual_active" end
        if status ~= nil and status ~= "completed" then
            return finishEpisode(actor, state, episode, false, "duck_visual_" .. tostring(status))
        end
        clearVisual(actor)
        episode.stage = episode.visualNext
    end
    if episode.stage == "place" then
        local source = select(1, U().call(episode.item, "getContainer")) or U().inventory(actor)
        local dropped, worldOrReason = U().dropItem(source, episode.square, episode.item, 0.5, 0.5, 0)
        if dropped ~= true then
            duck.phase = atBase(actor) and "carried" or "awaiting_base"
            persist(actor)
            return finishEpisode(actor, state, episode, false, worldOrReason or "duck_drop_failed")
        end
        episode.worldItem = worldOrReason
        duck.phase = "displayed"
        local base = SC.BaseLife and SC.BaseLife.active and SC.BaseLife.active() or nil
        duck.baseId = base and tostring(base.id or "") or ""
        duck.x, duck.y, duck.z = U().position(episode.square)
        persist(actor)
        episode.stage = "worship_say"
    end
    if episode.stage == "worship_say" then
        U().move(actor, "walk", {
            action = "face_conversation", target = episode.worldItem,
            targetSquare = episode.square, stableFacing = true,
            ritual = "rubber_duck_oracle",
        })
        sayRitual(actor, episode, state)
        episode.emotes, episode.emoteIndex = duckEmotes(ritual), 1
        episode.stage = "worship_emote"
    end
    if episode.stage == "worship_emote" then
        if U().nowMs() < finite(episode.nextEmoteAt, 0) then return true, "duck_worshipping" end
        local emote = episode.emotes[episode.emoteIndex]
        if emote then
            if SC.Relationship and type(SC.Relationship.playEmote) == "function" then
                pcall(SC.Relationship.playEmote, actor, emote)
            end
            episode.emoteIndex = episode.emoteIndex + 1
            episode.nextEmoteAt = U().nowMs() + (U().config("ritualEmoteHoldMs") or 1800)
            return true, "duck_worshipping"
        end
        return startLootVisual(actor, episode, "pickup")
    end
    if episode.stage == "pickup" then
        local destination = U().inventory(actor)
        local recovered, recoverReason = U().takeWorldItemVerified(
            episode.worldItem, destination, episode.item)
        if recovered ~= true then
            duck.phase = "recovery_pending"
            persist(actor)
            return finishEpisode(actor, state, episode, false,
                recoverReason or "duck_recovery_failed")
        end
        duck.phase = "carried"
        duck.x, duck.y, duck.z = nil, nil, nil
        duck.baseId = ""
        return finishEpisode(actor, state, episode, true,
            episode.recovery and "duck_recovered" or "duck_worship_completed")
    end
    return true, "duck_ritual_active"
end

local function updateGeneric(actor, state, episode)
    if episode.stage == "approach" and episode.square
        and U().distance(actor, episode.square) > 1.4 then
        if SC.Navigation and type(SC.Navigation.request) == "function" then
            local accepted, reason = SC.Navigation.request(actor, episode.square, "walk", {
                purpose = "personal_ritual", ritual = episode.id,
            })
            return accepted == true, accepted and "approaching_ritual" or reason
        end
        return false, "ritual_navigation_unavailable"
    end
    U().stop(actor)
    if episode.object or episode.square then
        U().move(actor, "walk", {
            action = "face_conversation", target = episode.object,
            targetSquare = episode.square, ritual = episode.id,
        })
    end
    sayRitual(actor, episode, state)
    local emote = genericEmotes[episode.id]
    if emote and SC.Relationship and type(SC.Relationship.playEmote) == "function" then
        pcall(SC.Relationship.playEmote, actor, emote)
    end
    if not episode.ritual.id then episode.ritual.id = episode.id end
    return finishEpisode(actor, state, episode, true, "ritual_completed")
end

function Quirks.updateRitual(actor, player, rootRuntime, detail)
    local state = commandState(actor)
    if type(state) ~= "table" then return false, "ritual_state_unavailable" end
    local snapshot = type(rootRuntime) == "table" and (rootRuntime.snapshot
        or rootRuntime.senses and rootRuntime.senses.current) or {}
    if not safeContext(actor, player, snapshot, state) then
        Quirks.interrupt(actor, "ritual_unsafe")
        return false, "ritual_unsafe"
    end
    local episode = episodes[actor]
    if not episode then
        local started, reason = beginEpisode(actor, type(detail) == "table" and detail or {}, state)
        if not started then return false, reason end
        episode = started
    end
    if episode.id == "rubber_duck_oracle" then return updateDuck(actor, state, episode) end
    return updateGeneric(actor, state, episode)
end

function Quirks.interrupt(actor, reason)
    local episode = actor and episodes[actor] or nil
    if not episode then return false, "ritual_not_active" end
    local state = commandState(actor)
    if episode.id == "rubber_duck_oracle" and state then
        local ritual = ensureRitual(state)
        if episode.worldItem or ritual.duck and ritual.duck.phase == "displayed" then
            ritual.duck.phase = "recovery_pending"
        elseif ritual.duck then
            ritual.duck.phase = atBase(actor) and "carried" or "awaiting_base"
        end
        persist(actor)
    end
    if SC.Navigation and type(SC.Navigation.cancel) == "function" then
        pcall(SC.Navigation.cancel, actor, reason or "ritual_interrupted")
    end
    if SC.NativeActions and type(SC.NativeActions.cancelVisual) == "function" then
        pcall(SC.NativeActions.cancelVisual, actor, reason or "ritual_interrupted")
    end
    if episode.square and shrineReservations[episode.square] == actor then
        shrineReservations[episode.square] = nil
    end
    episodes[actor] = nil
    return true, reason or "ritual_interrupted"
end

function Quirks.reset(actor)
    if actor then
        Quirks.interrupt(actor, "reset")
        episodes[actor], recognition[actor] = nil, nil
    else
        episodes = setmetatable({}, { __mode = "k" })
        recognition = setmetatable({}, { __mode = "k" })
        shrineReservations = setmetatable({}, { __mode = "k" })
    end
end

local function registerDialogue()
    if not SC.Dialogue or type(SC.Dialogue.register) ~= "function" then return end
    SC.Dialogue.register("recognition.local", {
        common = {
            "%1? Hell, that walker even leans like %5. Keep your distance.",
            "I swear that's %1, the %3 from %4. Eyes on that one.",
            "That looks like %1. %2 used to be the %3 back in %4.",
            "%1? No. Couldn't be. Still—watch that walker.",
            "Same coat, same walk. Could be %1 from %4. Contact ahead.",
            "Tell me that isn't %1. %2 was our %3. Stay sharp.",
            "I knew a %3 named %1. That dead thing stole %6 face.",
            "That walker has %1's eyes. Kentucky is too damn small.",
            "%1 used to wave from across the road. Now %2 is crossing it dead.",
            "Looks like %1 from back home. Don't let %5 get close.",
            "For half a second I thought that was %1. Half a second too long.",
            "That deadhead could be %1. Same walk, worse manners.",
        },
        brave = {
            "%1? If that's you, you picked the wrong survivor to bite.",
            "Looks like %1. Doesn't matter—I'm putting %5 down if %2 comes closer.",
            "Our old %3, maybe. Keep moving. I can grieve after.",
            "%1 always tackled high. This one won't get the chance.",
        },
        cautious = {
            "Could be %1. There may be more from %4 nearby. Check the exits.",
            "That looks like %1. Don't go closer to make sure.",
            "%1 or not, give %5 room and keep a retreat line.",
            "I remember that walk. I also remember where the back door is.",
        },
        caring = {
            "%1? Oh, no. %2 didn't deserve this. Please stay back.",
            "That might be %1. I hope it isn't. I really hope it isn't.",
            "%1 was kind to me in %4. Watch that walker—please.",
            "I knew %5. Or someone with that face. Don't make me look twice.",
        },
        practical = {
            "Possible match: %1, %3. Identification changes nothing—walker ahead.",
            "Could be %1. Bad posture, active decay, immediate problem.",
            "Familiar face. Irrelevant teeth. Keep distance.",
            "Maybe %1. We confirm after it stops moving, from here.",
        },
        stressed = {
            "%1? No. No, %2 was safe. Wasn't %2?",
            "That is %1. It can't be %1. Watch it!",
            "I know that face. I know that face. Keep it away from me.",
            "Kentucky keeps sending everybody back wrong.",
        },
    })
    SC.Dialogue.register("recognition.grief", {
        common = {
            "%1? No. We already lost you. Walker ahead.",
            "That looks like %1. Same face. Same damned ending.",
            "%1, is that— no. Keep your distance from it.",
            "For one second I saw %1 standing there alive.",
            "That dead thing is wearing %1's memory. Watch it.",
            "%1 died with us. Whatever that is, it isn't %5 anymore.",
            "I know %1's walk. I wish I didn't recognize this one.",
            "One of ours. Maybe. God, %1, what happened to you?",
        },
        brave = { "%1, forgive me. I'm not letting you hurt them.", "%1 or not, I finish this standing." },
        cautious = { "It looks like %1. Don't make me go closer to prove it.", "%1? Stay back. We cannot risk certainty." },
        caring = { "%1? I'm sorry. I'm so damn sorry. Stay behind me.", "That might be %1. Please don't make me do this twice." },
        practical = { "Resemblance to %1 confirmed. Identity irrelevant. Threat remains.", "Could be %1. We survive first and mourn later." },
        stressed = { "%1 is dead. %1 is dead. Then who is that?", "No. We buried %1. We buried %5." },
    })
    SC.Dialogue.register("recognition.resolve.local", {
        common = {
            "No. Wasn't %1. I don't think.", "%1 had better posture.",
            "Wrong face once it stopped moving.", "Not %1. Same coat, different nightmare.",
            "Couldn't have been %1. %1 knew how to tie shoes.",
            "False alarm. Kentucky still owes me one heartbeat.",
            "Nope. %1 had all their teeth last I checked.",
            "Wasn't them. Good. That's good, right?",
        },
        brave = { "Not %1. Shame—I had a speech ready.", "%1 would've put up more of a fight." },
        cautious = { "Probably not %1. Probably is doing too much work there.", "Not enough left to be certain. Leave it." },
        caring = { "Wasn't %1. Thank God for one small mercy.", "Not them. I can breathe again." },
        practical = { "Negative identification. Moving on.", "Not %1. Resemblance resolved." },
    })
    SC.Dialogue.register("recognition.resolve.grief", {
        common = {
            "No. That wasn't %1. We still lost them, though.", "%1 had kinder eyes.",
            "Wasn't %1. The dead just borrowed the hurt.", "Not them. Just another cruel resemblance.",
            "%1 would've known us. Wouldn't they?", "No. We said goodbye once already.",
        },
        brave = { "Wasn't %1. I won't apologize for surviving.", "Not %1. Keep the memory; leave the corpse." },
        cautious = { "Not %1. Don't inspect it. Let that answer be enough." },
        caring = { "Wasn't %1. I'm sorry I doubted the memory." },
        practical = { "Not %1. Grief made the match, not evidence." },
    })

    local ordinary = {
        spiffo_salute = {
            "*salutes the Spiffo sign* Still open for business, sir.",
            "Colonel Spiffo, the fryers are cold but morale remains greasy.",
            "If the raccoon made it this long, we can too.",
            "Permission to survive another shift, Commander Spiffo.",
        },
        bourbon_blessing = {
            "Kentucky made this before Kentucky tried to eat us. Respect.",
            "Bless the barrel, curse the dead, save the bottle.",
            "To everyone who said bourbon wasn't emergency equipment.",
            "One bottle, zero waste, and no drinking on watch.",
        },
        mannequin_apology = {
            "Sorry, ma'am. Thought you were dead. Different kind of unsettling.",
            "Morning, Mister Plastic. Still judging the outfit, I see.",
            "Excuse us. We'll be out of your store before closing.",
            "You keep watch. Blink if the dead come in.",
        },
        gnome_commander = {
            "Colonel Beauregard, perimeter report: terrible, but ours.",
            "*salutes the gnome* No casualties on your lawn, sir.",
            "Commander, the enemy remains numerous and badly dressed.",
            "Hold the garden. We hold Kentucky.",
        },
        sports_pep_talk = {
            "Fourth quarter, no bench, everybody bites. Eyes up.",
            "The dead play dirty, so protect the ball and the brain.",
            "Coach used to say finish through contact. He meant football.",
            "Knox County, huddle up. Today's play is don't get eaten.",
        },
    }
    for id, lines in pairs(ordinary) do
        SC.Dialogue.register("ritual." .. id, {
            common = lines,
            brave = { "Apocalypse or not, tradition is tradition." },
            cautious = { "Quick ritual. Then we check the exits again." },
            caring = { "A little kindness still counts, even now." },
            practical = { "Ridiculous. Repeatable. Surprisingly effective." },
            stressed = { "Just let me do this. Then I'll be fine." },
        })
    end

    SC.Dialogue.register("ritual.duck.discovery", {
        common = {
            "Well now. The Duck has found me.",
            "A rubber duck. Finally, competent leadership.",
            "Look at youâ€”yellow, unbitten, and coming with me.",
            "This is either a sign or a bath toy. Both beat canned peas.",
            "General Quack, I presume. Your transport awaits.",
            "Nobody tell the others, but this may be our best find yet.",
        },
        brave = { "Command has arrived, pocket-sized and fearless.", "The dead took Kentucky. They do not get this duck." },
        cautious = { "Quiet little thing. Good. You can ride in my pack.", "No squeaking until we're behind the barricades." },
        caring = { "Hey, little survivor. You're safe with us now.", "Someone left you behind. I won't." },
        practical = { "Portable morale device acquired. Condition: immaculate enough.", "Zero calories, negligible mass, undeniable strategic value." },
        stressed = { "You're real, right? Good. Stay where I can see you.", "A good omen. I am declaring you a good omen." },
    })

    SC.Dialogue.register("ritual.duck.quirk", {
        common = {
            "Okay, little duck. One minute. Then back in the bag.",
            "You are yellow, silent, and somehow management now.",
            "I found you in a cupboard. That practically makes this destiny.",
            "Your Yellowness, please ignore the blood on the floor.",
            "This is not worship. This is a tactical morale consultation.",
            "Tiny duck, enormous responsibility. Don't make it weird.",
        },
        brave = {
            "General Quack, your survivor reports. The dead remain undisciplined.",
            "Give the order, Commander. Preferably something involving a shotgun.",
            "I fear no corpse, but I respect your tiny authority.",
            "Yellow command is established. Kentucky may proceed.",
            "One squeak for charge, two for tactical withdrawal.",
            "I have followed worse officers than you.",
        },
        cautious = {
            "Keep watch, little one. You see everything from down there.",
            "If you spot anything, remain exactly that quiet.",
            "Front door, back door, windows, duck. All checked.",
            "You guard the floor. I'll guard everything with teeth.",
            "I know this is foolish. Foolish can still calm the nerves.",
            "No sudden squeaking. We're trying to stay hidden.",
        },
        caring = {
            "Nobody gets left behind. Not even bath toys.",
            "You've had a rough apocalypse too, haven't you?",
            "There. You get a place at the table like everyone else.",
            "I'll keep you safe. You keep us strange.",
            "You look ridiculous. I think we needed ridiculous.",
            "Welcome to the family, little duck.",
        },
        practical = {
            "This is ridiculous. The morale benefit remains measurable.",
            "Mass: point three. Tactical value: disputed. Emotional value: rising.",
            "Inventory item deployed for controlled superstition.",
            "No ammunition consumed. Ritual approved provisionally.",
            "You're washable, portable, and easier than therapy.",
            "One minute of nonsense, then back to logistics.",
        },
        stressed = {
            "Tell me the walls hold. Just nod with your whole... duck.",
            "You saw nothing in that bathroom. We understand each other.",
            "Please be a good omen. We are critically short on those.",
            "Everybody else is dead and I'm talking to a duck. Fine.",
            "Don't look at me like that. I found you, not the other way around.",
            "One quiet minute. That's all I'm asking.",
        },
    })
    SC.Dialogue.register("ritual.duck.routine", {
        common = {
            "The Duck has reviewed the perimeter. Present your report.",
            "Same floor, same duck, another day not dead.",
            "Council is now in session. Complaints may be submitted by squeak.",
            "Your shrine is temporary because pockets are safer.",
            "We gather under the yellow wing once more.",
            "The ritual continues. Kentucky has seen stranger churches.",
        },
        brave = {
            "General Quack, the line held. Naturally.", "Commander, authorize unnecessary courage.",
            "Your army remains one survivor strong and mean as winter.", "The dead advance. We advance louder.",
            "I brought grit, steel, and your portable command post.", "No retreat without a formal quack, sir.",
        },
        cautious = {
            "The Duck has reviewed the exits. None of them are good.", "Quiet council tonight. Too much movement outside.",
            "Watch the window while I count supplies again.", "We leave before dawn if you look worried.",
            "No squeak means all clear. I choose to believe that.", "Same safety prayer, same checked locks.",
        },
        caring = {
            "Everybody made it home. Thought you'd want to know.", "Keep an eye on them while I sleep, okay?",
            "We found food today. Nobody goes hungry under your watch.", "I saved your place, little friend.",
            "They laugh, but they smile when they see you.", "Thank you for making this room feel less empty.",
        },
        practical = {
            "Daily duck inspection: intact, clean, inexplicably reassuring.", "Morale protocol initiated. Yes, I hate that it works.",
            "Portable shrine deployed. Recovery procedure follows.", "The cost-benefit analysis still favors the duck.",
            "No batteries, no feed, no arguments. Ideal leadership.", "Consultation complete pending one ceremonial gesture.",
        },
        stressed = {
            "You were right yesterday. Be right again.", "Tell me the dead stay outside tonight.",
            "I counted everyone twice. You make one more survivor.", "Don't disappear while you're on the floor.",
            "The walls creak less when council is in session.", "Just one more day. Put that in the official minutes.",
        },
    })
    SC.Dialogue.register("ritual.duck.tradition", {
        common = {
            "By yellow wing and squeaking beak, this house remains ours.",
            "Bless this base, bless this bourbon, and confuse the hell out of the dead.",
            "The First Duck takes the floor. Let all bad luck wait outside.",
            "We survived long enough to have liturgy. That's something.",
            "The congregation stands armed. The Duck stands adorable.",
            "Kentucky fell. The Yellow Chapel remains open.",
        },
        brave = {
            "General Quack, your army reports undefeated by anything that stayed dead.", "Under the yellow banner, we hold.",
            "Grant me courage, ammunition, and a clean swing.", "The dead get fear. We get faith and blunt objects.",
            "No grave, no tyrant, no bad-tempered corpse takes this base.", "Commander, witness another impossible dawn.",
        },
        cautious = {
            "Bless every exit, especially the one we haven't found yet.", "Yellow Watch, keep the blind corners quiet.",
            "By beak and barricade, let no latch fail tonight.", "Count the windows, count the doors, count the living.",
            "If danger comes, guide our feet before our pride.", "The perimeter is sealed. The prayer is not a substitute.",
        },
        caring = {
            "Little Duck, keep every name in this house among the living.", "Nobody gets left behind beneath the yellow wing.",
            "Bless the tired, the frightened, and the ones pretending not to be.", "Keep their dreams quieter than the road outside.",
            "We made a family out of whoever was left. Watch over it.", "For the absent, the lost, and everyone still coming home.",
        },
        practical = {
            "Formal morale maintenance begins. Mockery may resume afterward.", "Protocol Duck-Seven: breathe, inventory, survive.",
            "The shrine remains portable by deliberate engineering choice.", "Observed outcome: lower stress, higher cohesion, zero feed cost.",
            "Leadership review complete. The duck retains command.", "Ceremony logged. Relic recovery is the next mandatory phase.",
        },
        stressed = {
            "The Duck was here yesterday. We were alive yesterday.", "Say nothing. That's how I know you're listening.",
            "Hold this house together while I hold myself together.", "By yellow wing, not tonight. Please, not tonight.",
            "We keep the ritual because the ritual keeps count of us.", "One prayer for every sound beyond the walls.",
        },
    })
end

registerDialogue()

SC.Modules = SC.Modules or {}
SC.Modules.quirks = true
return Quirks
