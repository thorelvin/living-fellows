-- SPDX-License-Identifier: MIT

if not SurvivorCompanion or not SurvivorCompanion.Call then
    if type(require) == "function" then pcall(require, "SCCall") end
end
if not SurvivorCompanion or not SurvivorCompanion.NativeList then
    if type(require) == "function" then pcall(require, "SCNativeList") end
end

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion

SC.Background = SC.Background or {}
local Background = SC.Background

-- These IDs and starting skill boosts mirror Project Zomboid 42.20.4's
-- generated character_professions.txt.  The extra AI fields are deliberately
-- small preferences: a career informs a companion without deciding every act.
local professions = {
    burglar = {
        label = "Burglar", role = "generalist",
        skills = { Nimble = 2, Sneak = 2, Lightfoot = 2 },
        personality = { courage = 3, caution = 8, practicality = 5 },
        decisions = { scavenge = 3, tactical = 3, retreat = 1 },
        objectives = { put_gear_in_order = 10 },
        jobs = { fetch = 3, haul = 2 },
        aptitudes = { "dextrous", "graceful", "jogger", "keen_hearing" },
        history = "I learned to read locks, routines, and quiet ways through a building before the outbreak.",
    },
    burgerflipper = {
        label = "Burger Flipper", role = "quartermaster",
        skills = { Cooking = 2, Maintenance = 1, SmallBlade = 1 },
        personality = { compassion = 3, practicality = 5 },
        decisions = { downtime = 1 }, downtime = { craft_supply = 2 },
        objectives = { share_a_proper_meal = 24 },
        jobs = { craft_supply = 3, sort = 2 },
        aptitudes = { "organized", "dextrous", "fast_learner" },
        history = "I worked fast shifts in a roadside kitchen and got good at making limited supplies stretch.",
    },
    carpenter = {
        label = "Carpenter", role = "builder",
        skills = { Woodwork = 4, Carving = 1, SmallBlunt = 1, Masonry = 1, Maintenance = 1 },
        personality = { caution = 2, practicality = 10 },
        decisions = { downtime = 2, tactical = 1 },
        downtime = { repair = 4, craft_supply = 3 },
        objectives = { improve_shelter = 30, put_gear_in_order = 8 },
        jobs = { build = 6, barricade = 6, maintain = 4, repair = 4 },
        aptitudes = { "handy", "organized", "outdoorsman" },
        history = "I framed houses and repaired storm damage. A sound wall and a clear exit still make sense to me.",
    },
    chef = {
        label = "Chef", role = "quartermaster",
        skills = { Cooking = 4, Maintenance = 1, SmallBlade = 1, Butchering = 2 },
        personality = { compassion = 6, practicality = 7 },
        decisions = { downtime = 2 }, downtime = { craft_supply = 3 },
        objectives = { share_a_proper_meal = 34 },
        jobs = { craft_supply = 4, sort = 2 },
        aptitudes = { "organized", "dextrous", "gardener" },
        history = "I ran a busy kitchen. Feeding people was equal parts planning, timing, and keeping calm under pressure.",
    },
    constructionworker = {
        label = "Construction Worker", role = "builder",
        skills = { SmallBlunt = 2, Blunt = 1, Masonry = 2, Woodwork = 1, Maintenance = 1 },
        personality = { courage = 5, practicality = 8 },
        decisions = { combat = 1, downtime = 2 },
        downtime = { repair = 3, craft_supply = 2 },
        objectives = { improve_shelter = 28 },
        jobs = { build = 5, barricade = 5, haul = 3, repair = 3 },
        aptitudes = { "handy", "organized", "stout" },
        history = "I spent years on building sites, where bad footing and careless shortcuts could get somebody killed.",
    },
    doctor = {
        label = "Doctor", role = "medic", skills = { Doctor = 6, SmallBlade = 1 },
        personality = { caution = 5, compassion = 10, practicality = 5 },
        decisions = { medical = 4, encounter = 1, combat = -1 },
        downtime = { replace_bandage = 4, wash_self = 1, wash_equipment = 2 },
        objectives = { keep_medical_ready = 36 }, jobs = { replace_bandage = 7, fetch = 2 },
        aptitudes = { "first_aider", "organized", "fast_learner" },
        history = "I treated people when there were still clean rooms, working lights, and more help on the way.",
    },
    electrician = {
        label = "Electrician", role = "builder", skills = { Electricity = 5 },
        personality = { caution = 5, practicality = 10 },
        decisions = { tactical = 2, downtime = 2 },
        downtime = { repair = 4, craft_supply = 3 },
        objectives = { put_gear_in_order = 28, improve_shelter = 16 },
        jobs = { repair = 6, maintain = 5, build = 2 },
        aptitudes = { "handy", "organized", "tinkerer" },
        history = "I traced faults for a living. I still look for the broken link before I start replacing everything.",
    },
    engineer = {
        label = "Engineer", role = "builder",
        skills = { Electricity = 1, Woodwork = 1, Masonry = 1 },
        personality = { caution = 4, practicality = 11 },
        decisions = { tactical = 3, downtime = 2, scavenge = 1 },
        downtime = { repair = 4, craft_supply = 4 },
        objectives = { put_gear_in_order = 26, improve_shelter = 24 },
        jobs = { build = 4, repair = 5, maintain = 5, craft_supply = 4 },
        aptitudes = { "tinkerer", "organized", "fast_learner" },
        history = "I designed systems on paper. Now I work with whatever parts survive and test every assumption twice.",
    },
    farmer = {
        label = "Farmer", role = "quartermaster",
        skills = { Farming = 4, Husbandry = 1, Strength = 1 },
        personality = { caution = 2, compassion = 3, practicality = 9 },
        decisions = { scavenge = 2, downtime = 2 },
        objectives = { improve_shelter = 14, share_a_proper_meal = 22 },
        jobs = { fetch = 4, haul = 4, maintain = 4 },
        aptitudes = { "gardener", "outdoorsman", "organized" },
        history = "I worked land where every season punished poor planning. Food security was never an abstract idea to me.",
    },
    fireofficer = {
        label = "Fire Officer", role = "guard",
        skills = { Sprinting = 1, Strength = 1, Fitness = 1, Axe = 1 },
        personality = { courage = 10, caution = 3, compassion = 6 },
        decisions = { medical = 2, combat = 2, tactical = 2, encounter = 1 },
        objectives = { improve_shelter = 14, keep_medical_ready = 16 },
        jobs = { barricade = 5, maintain = 3, fetch = 2 },
        aptitudes = { "brave", "first_aider", "jogger", "stout" },
        history = "I entered places everyone else was trying to leave. The first rule was always to keep a way back out.",
    },
    fisherman = {
        label = "Fisherman", role = "quartermaster",
        skills = { Fishing = 3, PlantScavenging = 1, Butchering = 1 },
        personality = { caution = 5, practicality = 6 },
        decisions = { scavenge = 3, retreat = 1 },
        objectives = { share_a_proper_meal = 20 }, jobs = { fetch = 4, sort = 2 },
        aptitudes = { "angler", "outdoorsman", "patient" },
        history = "I made a living reading weather, water, and small changes most people never noticed.",
    },
    fitnessinstructor = {
        label = "Fitness Instructor", role = "generalist",
        skills = { Fitness = 3, Sprinting = 2, Strength = 1 },
        personality = { courage = 5, compassion = 3, practicality = 2 },
        decisions = { retreat = 3, encounter = 1, medical = 1 },
        objectives = { keep_medical_ready = 8 }, jobs = { fetch = 4, haul = 2 },
        aptitudes = { "jogger", "graceful", "organized" },
        history = "I coached people at a small gym and ran before dawn. Pacing matters more than showing off.",
    },
    lumberjack = {
        label = "Lumberjack", role = "builder",
        skills = { Axe = 2, Strength = 1, Maintenance = 1 },
        personality = { courage = 7, caution = 2, practicality = 8 },
        decisions = { combat = 2, scavenge = 1, downtime = 1 },
        downtime = { repair = 3 }, objectives = { improve_shelter = 26, put_gear_in_order = 8 },
        jobs = { build = 5, barricade = 4, haul = 3 },
        aptitudes = { "outdoorsman", "handy", "stout", "hiker" },
        history = "I worked logging crews. A sharp axe, solid footing, and knowing which way something will fall kept us alive.",
    },
    mechanics = {
        label = "Mechanic", role = "builder", skills = { Mechanics = 4, MetalWelding = 1 },
        personality = { caution = 3, practicality = 11 },
        decisions = { tactical = 1, downtime = 3, scavenge = 1 },
        downtime = { repair = 5, craft_supply = 2 },
        objectives = { put_gear_in_order = 32 }, jobs = { repair = 7, maintain = 5 },
        -- Amateur Mechanic is mutually exclusive with the profession's
        -- granted Mechanics trait, so it is intentionally not in this pool.
        aptitudes = { "handy", "organized", "tinkerer" },
        history = "I kept old cars running after their owners had given up on them. Most failures warn you first.",
    },
    metalworker = {
        label = "Metalworker", role = "builder", skills = { MetalWelding = 4 },
        personality = { courage = 3, caution = 4, practicality = 10 },
        decisions = { downtime = 3 }, downtime = { repair = 4, craft_supply = 4 },
        objectives = { improve_shelter = 26, put_gear_in_order = 14 },
        jobs = { build = 5, repair = 5, maintain = 3 },
        aptitudes = { "handy", "organized", "stout" },
        history = "I cut and joined steel for a living. Heat, sparks, and weak seams teach you to respect preparation.",
    },
    nurse = {
        label = "Nurse", role = "medic", skills = { Doctor = 3, Lightfoot = 1, Fitness = 1 },
        personality = { caution = 5, compassion = 11, practicality = 4 },
        decisions = { medical = 4, encounter = 2, combat = -1 },
        downtime = { replace_bandage = 5, wash_self = 1, wash_equipment = 2 },
        objectives = { keep_medical_ready = 38 }, jobs = { replace_bandage = 8, fetch = 3 },
        aptitudes = { "first_aider", "organized", "graceful" },
        history = "I spent long shifts noticing what patients were too frightened or tired to say out loud.",
    },
    parkranger = {
        label = "Park Ranger", role = "generalist",
        skills = { Trapping = 1, Doctor = 1, PlantScavenging = 1, FlintKnapping = 1, Carving = 1 },
        personality = { courage = 3, caution = 7, compassion = 3, practicality = 6 },
        decisions = { scavenge = 4, tactical = 2, medical = 1, retreat = 1 },
        objectives = { keep_medical_ready = 10, improve_shelter = 12 },
        jobs = { fetch = 4, maintain = 4, barricade = 2 },
        aptitudes = { "outdoorsman", "hiker", "keen_hearing", "first_aider" },
        history = "I searched trails for lost hikers and watched weather turn without warning. I trust signs more than luck.",
    },
    policeofficer = {
        label = "Police Officer", role = "guard",
        skills = { Aiming = 4, Reloading = 1, Nimble = 1 },
        personality = { courage = 7, caution = 5, practicality = 3 },
        decisions = { combat = 3, tactical = 4, encounter = 1 },
        objectives = { put_gear_in_order = 12 }, jobs = { barricade = 6, maintain = 5 },
        aptitudes = { "keen_hearing", "brave", "organized", "jogger" },
        history = "I answered calls where nobody knew the whole story. I learned to watch hands, exits, and crossfire.",
    },
    rancher = {
        label = "Rancher", role = "quartermaster",
        skills = { Husbandry = 4, Butchering = 3, Fitness = 1 },
        personality = { courage = 4, compassion = 3, practicality = 8 },
        decisions = { scavenge = 2, downtime = 1 },
        objectives = { share_a_proper_meal = 22, improve_shelter = 12 },
        jobs = { haul = 4, fetch = 4, maintain = 4 },
        aptitudes = { "outdoorsman", "stout", "organized" },
        history = "I cared for animals that depended on routine even when weather, machinery, or people made the day difficult.",
    },
    repairman = {
        label = "Repairman", role = "builder",
        skills = { Woodwork = 1, Maintenance = 2, SmallBlunt = 1, Masonry = 1 },
        personality = { caution = 3, practicality = 10 },
        decisions = { downtime = 3 }, downtime = { repair = 5, craft_supply = 2 },
        objectives = { put_gear_in_order = 30, improve_shelter = 18 },
        jobs = { repair = 7, maintain = 6, barricade = 2 },
        aptitudes = { "handy", "tinkerer", "organized" },
        history = "I was the person people called when a door, appliance, or tool had to last one more year.",
    },
    securityguard = {
        label = "Security Guard", role = "guard",
        skills = { Sprinting = 2, Lightfoot = 1, SmallBlunt = 1 },
        personality = { courage = 3, caution = 9, practicality = 3 },
        decisions = { tactical = 4, retreat = 2, combat = 1 },
        objectives = { put_gear_in_order = 10 }, jobs = { maintain = 6, barricade = 5 },
        aptitudes = { "keen_hearing", "jogger", "organized" },
        history = "I walked quiet buildings at night and learned which noises belonged there and which ones did not.",
    },
    smither = {
        label = "Blacksmith", role = "builder",
        skills = { Blacksmith = 4, Maintenance = 1, SmallBlunt = 1 },
        personality = { courage = 4, caution = 3, practicality = 10 },
        decisions = { downtime = 3 }, downtime = { repair = 4, craft_supply = 5 },
        objectives = { improve_shelter = 24, put_gear_in_order = 18 },
        jobs = { build = 5, repair = 5, craft_supply = 5 },
        aptitudes = { "handy", "stout", "organized" },
        history = "I shaped hot metal by patience and repetition. Rushing only meant ruining the work or burning someone.",
    },
    tailor = {
        label = "Tailor", role = "quartermaster", skills = { Tailoring = 4 },
        personality = { caution = 4, compassion = 3, practicality = 8 },
        decisions = { downtime = 3 }, downtime = { repair = 5, craft_supply = 4 },
        objectives = { put_gear_in_order = 24 }, jobs = { repair = 5, sort = 4, craft_supply = 4 },
        aptitudes = { "sewer", "organized", "dextrous" },
        history = "I altered and repaired clothes. Small tears become large failures when nobody deals with them early.",
    },
    unemployed = {
        label = "Unemployed", role = "generalist", skills = {},
        personality = {}, decisions = {}, objectives = {}, jobs = {},
        aptitudes = { "jogger", "first_aider", "handy", "organized", "outdoorsman",
            "fast_learner", "gardener", "keen_hearing" },
        history = "I was between jobs when everything collapsed. I survived by learning quickly and doing what needed doing.",
    },
    veteran = {
        label = "Veteran", role = "guard", skills = { Aiming = 2, Reloading = 2 },
        personality = { courage = 10, caution = 6, practicality = 4 },
        decisions = { combat = 3, tactical = 4, retreat = -1 },
        objectives = { put_gear_in_order = 16 }, jobs = { maintain = 6, barricade = 5 },
        aptitudes = { "organized", "keen_hearing", "first_aider", "hiker" },
        history = "I learned that discipline is mostly doing ordinary things correctly while everyone is exhausted and afraid.",
    },
}

local professionOrder = {
    "burglar", "burgerflipper", "carpenter", "chef", "constructionworker", "doctor",
    "electrician", "engineer", "farmer", "fireofficer", "fisherman", "fitnessinstructor",
    "lumberjack", "mechanics", "metalworker", "nurse", "parkranger", "policeofficer",
    "rancher", "repairman", "securityguard", "smither", "tailor", "unemployed", "veteran",
}

local aptitudes = {
    angler = { id = "base:fishing", label = "Angler", personality = { caution = 2, practicality = 3 }, decisions = { scavenge = 1 } },
    brave = { id = "base:brave", label = "Brave", personality = { courage = 7, caution = -2 }, decisions = { combat = 1, retreat = -1 } },
    dextrous = { id = "base:dextrous", label = "Dextrous", personality = { practicality = 3 }, downtime = { repair = 1, craft_supply = 1 } },
    fast_learner = { id = "base:fastlearner", label = "Fast Learner", personality = { practicality = 3 }, decisions = { downtime = 1 } },
    first_aider = { id = "base:firstaid", label = "First Aider", personality = { compassion = 5, caution = 2 }, decisions = { medical = 2 }, skills = { Doctor = 1 } },
    gardener = { id = "base:gardener", label = "Gardener", personality = { compassion = 2, practicality = 4 }, decisions = { scavenge = 1 } },
    graceful = { id = "base:graceful", label = "Graceful", personality = { caution = 3 }, decisions = { tactical = 1, retreat = 1 } },
    handy = { id = "base:handy", label = "Handy", personality = { practicality = 5 }, downtime = { repair = 2, craft_supply = 1 }, skills = { Woodwork = 1, Maintenance = 1 } },
    hiker = { id = "base:hiker", label = "Hiker", personality = { courage = 2, caution = 3 }, decisions = { scavenge = 1, retreat = 1 } },
    jogger = { id = "base:jogger", label = "Jogger", personality = { courage = 2, caution = 2 }, decisions = { retreat = 2, tactical = 1 }, skills = { Sprinting = 1 } },
    keen_hearing = { id = "base:keenhearing", label = "Keen Hearing", personality = { caution = 5 }, decisions = { tactical = 2 } },
    mechanical = { id = "base:mechanics", label = "Amateur Mechanic", personality = { practicality = 4 }, downtime = { repair = 2 }, skills = { Mechanics = 1 } },
    organized = { id = "base:organized", label = "Organized", personality = { caution = 2, practicality = 5 }, decisions = { downtime = 1 }, jobs = { sort = 2, haul = 1 } },
    outdoorsman = { id = "base:outdoorsman", label = "Outdoorsman", personality = { courage = 3, caution = 2 }, decisions = { scavenge = 2, retreat = 1 } },
    patient = { id = "base:fastreader", label = "Patient Reader", personality = { caution = 3, practicality = 2 }, downtime = { read = 2 } },
    sewer = { id = "base:tailor", label = "Sewer", personality = { practicality = 4 }, downtime = { repair = 2, craft_supply = 2 }, skills = { Tailoring = 1 } },
    stout = { id = "base:stout", label = "Stout", personality = { courage = 4 }, decisions = { combat = 1 }, skills = { Strength = 1 } },
    tinkerer = { id = "base:tinkerer", label = "Tinkerer", personality = { practicality = 5 }, downtime = { repair = 2, craft_supply = 2 } },
}

local homes = { "muldraugh", "rosewood", "riverside", "west_point", "louisville", "brandenburg" }
local values = { "honesty", "loyalty", "kindness", "self_reliance", "community", "courage" }
local fears = { "being_alone", "turning", "fire", "tight_spaces", "letting_people_down", "the_dark" }
local habits = { "checks_exits", "counts_supplies", "hums", "keeps_notes", "makes_tea", "cleans_tools" }
local legacyProfession = {
    mechanic = "mechanics", park_ranger = "parkranger", cook = "chef",
    paramedic = "nurse", warehouse = "constructionworker", teacher = "unemployed",
    librarian = "unemployed", fitnessInstructor = "fitnessinstructor",
}

local function clamp(value, low, high)
    value = tonumber(value) or low
    if value < low then return low end
    if value > high then return high end
    return value
end

local function hash(value)
    local result = 7919
    value = tostring(value or "fellow")
    for index = 1, #value do
        result = (result * 131 + string.byte(value, index)) % 2147483647
    end
    return result
end

local function choose(pool, seed, salt)
    return pool[((hash(tostring(seed) .. ":" .. tostring(salt)) % #pool) + 1)]
end

local function professionCode(value)
    value = tostring(value or "")
    value = string.gsub(value, "^base:", "")
    value = string.lower(value)
    value = legacyProfession[value] or value
    return professions[value] and value or nil
end

local function copyScalarMap(source)
    local result, count = {}, 0
    if type(source) == "table" then
        for key, value in pairs(source) do
            if type(key) == "string" and (type(value) == "string"
                or type(value) == "number" or type(value) == "boolean") then
                result[key] = value
                count = count + 1
                if count >= 32 then break end
            end
        end
    end
    return result
end

function Background.initialize(seed, source)
    source = copyScalarMap(source)
    local code = professionCode(source.profession or source.professionId or source.occupation)
        or choose(professionOrder, seed, "profession")
    local definition = professions[code]
    local allowed = definition.aptitudes or { "fast_learner" }
    local aptitude = type(source.aptitude) == "string" and aptitudes[source.aptitude]
        and source.aptitude or choose(allowed, seed, "aptitude")
    return {
        version = 2,
        profession = code,
        professionId = "base:" .. code,
        occupation = code,
        aptitude = aptitude,
        traitId = aptitudes[aptitude] and aptitudes[aptitude].id or nil,
        preferredRole = definition.role or "generalist",
        history = type(source.history) == "string" and source.history or code,
        home = source.home or choose(homes, seed, "home"),
        value = source.value or choose(values, seed, "value"),
        fear = source.fear or choose(fears, seed, "fear"),
        habit = source.habit or choose(habits, seed, "habit"),
    }
end

function Background.prepareProfile(profile)
    profile = type(profile) == "table" and profile or {}
    local identity = type(profile.identity) == "table" and profile.identity or profile
    local state = type(profile.state) == "table" and profile.state or {}
    local personality = type(state.personality) == "table" and state.personality or {}
    local seed = profile.id or identity.visualSeed
        or (tostring(identity.forename or "Fellow") .. ":" .. tostring(identity.surname or "Survivor"))
    personality.background = Background.initialize(seed, personality.background or profile.background)
    state.personality = personality
    profile.state = state
    return profile, personality.background
end

function Background.definition(backgroundOrCode)
    local value = type(backgroundOrCode) == "table"
        and (backgroundOrCode.profession or backgroundOrCode.professionId
            or backgroundOrCode.occupation) or backgroundOrCode
    local code = professionCode(value) or "unemployed"
    return professions[code], code
end

function Background.aptitude(backgroundOrCode)
    local code = type(backgroundOrCode) == "table" and backgroundOrCode.aptitude
        or backgroundOrCode
    return aptitudes[code], code
end

function Background.professionLabel(background)
    local definition = Background.definition(background)
    return definition.label
end

function Background.aptitudeLabel(background)
    local definition = Background.aptitude(background)
    return definition and definition.label or "Adaptable"
end

function Background.summaryLabel(background)
    return Background.professionLabel(background) .. " / " .. Background.aptitudeLabel(background)
end

function Background.historyText(background)
    if type(background) == "table" and type(background.history) == "string"
        and professions[background.history] == nil and background.history ~= "" then
        return background.history
    end
    local definition = Background.definition(background)
    return definition.history
end

function Background.preferredRole(background)
    local definition = Background.definition(background)
    return definition.role or "generalist"
end

local function combinedMap(background, field)
    if type(background) == "table" and type(background.background) == "table" then
        background = background.background
    end
    local profession = Background.definition(background)
    local aptitude = Background.aptitude(background)
    local result = {}
    for key, value in pairs(type(profession[field]) == "table" and profession[field] or {}) do
        result[key] = (result[key] or 0) + (tonumber(value) or 0)
    end
    for key, value in pairs(type(aptitude) == "table" and type(aptitude[field]) == "table"
        and aptitude[field] or {}) do
        result[key] = (result[key] or 0) + (tonumber(value) or 0)
    end
    return result
end

function Background.personalityOffsets(background)
    return combinedMap(background, "personality")
end

function Background.decisionModifier(profileOrBackground, kind)
    return tonumber(combinedMap(profileOrBackground, "decisions")[kind]) or 0
end

function Background.downtimeModifier(profileOrBackground, kind)
    return tonumber(combinedMap(profileOrBackground, "downtime")[kind]) or 0
end

function Background.objectiveModifier(background, kind)
    return tonumber(combinedMap(background, "objectives")[kind]) or 0
end

function Background.baseJobModifier(background, kind)
    return tonumber(combinedMap(background, "jobs")[kind]) or 0
end

local function invoke(object, methodName, ...)
    local values = SC.Call.pack(SC.Call.method(object, methodName, ...))
    if values[1] ~= true then return values[2], false end
    return values[2], true, SC.Call.unpack(values, 3, values.n)
end

local listSize = SC.NativeList.size
local listGet = SC.NativeList.get

local function resolveScriptObject(className, id)
    local class = type(_G) == "table" and rawget(_G, className) or nil
    local resource = type(_G) == "table" and rawget(_G, "ResourceLocation") or nil
    if class == nil or resource == nil then return nil end
    local ok, value = pcall(function() return class.get(resource.of(id)) end)
    return ok and value or nil
end

local function addTrait(actor, trait)
    if trait == nil then return false end
    local present, presentOk = invoke(actor, "hasTrait", trait)
    if presentOk and present == true then return true end
    local traits, traitsOk = invoke(actor, "getCharacterTraits")
    if not traitsOk or traits == nil then return false end
    -- Match Build 42's own PlayerStats path. Older bridge fixtures expose the
    -- underlying known-traits list, so retain that narrow fallback for tests.
    local added, addOk = invoke(traits, "add", trait)
    if not addOk then
        local known, knownOk = invoke(traits, "getKnownTraits")
        if not knownOk or known == nil then return false end
        added, addOk = invoke(known, "add", trait)
    end
    if not addOk or added == false then return false end
    invoke(actor, "modifyTraitXPBoost", trait, false)
    present, presentOk = invoke(actor, "hasTrait", trait)
    return presentOk and present == true
end

local function applySkills(actor, skillMaps)
    local perkTable = type(_G) == "table" and rawget(_G, "Perks") or nil
    if perkTable == nil then return false end
    local targets = {}
    for _, skills in ipairs(skillMaps) do
        for name, boost in pairs(type(skills) == "table" and skills or {}) do
            local baseline = (name == "Strength" or name == "Fitness") and 5 or 0
            targets[name] = math.max(targets[name] or 0,
                clamp(baseline + (tonumber(boost) or 0), 0, 10))
        end
    end
    for name, target in pairs(targets) do
        local perkOk, perk = pcall(function() return perkTable[name] end)
        local current, currentOk
        if perkOk then current, currentOk = invoke(actor, "getPerkLevel", perk) end
        if not perkOk or perk == nil or not currentOk then return false end
        if (tonumber(current) or 0) < target then
            local result, setOk = invoke(actor, "setPerkLevelDebug", perk, target)
            if not setOk or result == false then return false end
        end
    end
    return true
end

-- Sets the same descriptor profession object used by normal Build 42 players,
-- then applies its granted traits/recipes and conservative starting levels.
-- Failure is reported to the caller but never leaves a half-registered actor.
function Background.applyNative(actor, background)
    if actor == nil then return false, "background_actor_missing" end
    background = Background.initialize("native", background)
    local professionDefinition, code = Background.definition(background)
    local profession = resolveScriptObject("CharacterProfession", "base:" .. code)
    if profession == nil then return false, "native_profession_unavailable:" .. code end
    local descriptor, descriptorOk = invoke(actor, "getDescriptor")
    if not descriptorOk or descriptor == nil then return false, "native_descriptor_unavailable" end
    local setResult, setOk = invoke(descriptor, "setCharacterProfession", profession)
    if not setOk or setResult == false then return false, "native_profession_rejected" end

    local definitionClass = type(_G) == "table"
        and rawget(_G, "CharacterProfessionDefinition") or nil
    local nativeDefinition
    if definitionClass ~= nil then
        local ok, value = pcall(function()
            return definitionClass.getCharacterProfessionDefinition(profession)
        end)
        if ok then nativeDefinition = value end
    end
    if nativeDefinition ~= nil then
        invoke(descriptor, "setProfessionSkills", nativeDefinition)
        local granted, grantedOk = invoke(nativeDefinition, "getGrantedTraits")
        if grantedOk and granted ~= nil then
            for index = 0, math.min(listSize(granted), 16) - 1 do
                if not addTrait(actor, listGet(granted, index)) then
                    return false, "native_profession_trait_rejected"
                end
            end
        end
    end

    local aptitude = Background.aptitude(background)
    local aptitudeTrait = aptitude and resolveScriptObject("CharacterTrait", aptitude.id) or nil
    if aptitudeTrait == nil or not addTrait(actor, aptitudeTrait) then
        return false, "native_aptitude_rejected:" .. tostring(background.aptitude)
    end
    if not applySkills(actor, { professionDefinition.skills, aptitude.skills }) then
        return false, "native_background_skills_rejected"
    end
    invoke(actor, "applyProfessionRecipes")
    invoke(actor, "applyCharacterTraitsRecipes")
    local current, currentOk = invoke(descriptor, "getCharacterProfession")
    if not currentOk or current ~= profession then return false, "native_profession_not_retained" end
    return true, "native_background_applied"
end

function Background.copy(background)
    return Background.initialize("copy", background)
end

return Background
