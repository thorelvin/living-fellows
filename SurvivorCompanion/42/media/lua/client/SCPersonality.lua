-- SPDX-License-Identifier: MIT

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
if not SC.Background and type(require) == "function" then pcall(require, "SCBackground") end

SC.Personality = SC.Personality or {}
local Personality = SC.Personality

local dimensions = { "courage", "caution", "compassion", "practicality" }
local validArchetypes = { brave = true, cautious = true, caring = true, practical = true }

local function clamp(value, low, high)
    value = tonumber(value)
    if value == nil or value ~= value or value == math.huge or value == -math.huge then value = low end
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

local function backgroundKey(background)
    background = type(background) == "table" and background or {}
    return table.concat({
        tostring(background.profession or background.occupation or ""),
        tostring(background.aptitude or ""), tostring(background.home or ""),
        tostring(background.value or ""), tostring(background.fear or ""),
        tostring(background.habit or ""),
    }, ":")
end

local function generated(id, background)
    local seed = hash(tostring(id or "fellow") .. ":" .. backgroundKey(background) .. ":profile-v2")
    local primaryIndex = (seed % #dimensions) + 1
    local values = {}
    for index, name in ipairs(dimensions) do
        local valueSeed = hash(tostring(seed) .. ":" .. name)
        values[name] = 35 + (valueSeed % 31)
        if index == primaryIndex then values[name] = 76 + (valueSeed % 19) end
    end
    local offsets = SC.Background and type(SC.Background.personalityOffsets) == "function"
        and SC.Background.personalityOffsets(background) or {}
    for _, name in ipairs(dimensions) do
        values[name] = clamp(values[name] + (tonumber(offsets[name]) or 0), 0, 100)
    end
    values[dimensions[primaryIndex]] = math.max(76, values[dimensions[primaryIndex]])
    local archetypes = { courage = "brave", caution = "cautious", compassion = "caring", practicality = "practical" }
    local highestName, highestValue
    for _, name in ipairs(dimensions) do
        if highestValue == nil or values[name] > highestValue then
            highestName, highestValue = name, values[name]
        end
    end
    values.version = 2
    values.archetype = archetypes[highestName]
    values.background = SC.Background and SC.Background.copy
        and SC.Background.copy(background) or background
    values.profession = values.background and values.background.profession or nil
    values.aptitude = values.background and values.background.aptitude or nil
    return values
end

function Personality.initialize(id, background, saved)
    local fallback = generated(id, background)
    saved = type(saved) == "table" and saved or {}
    local savedVersion = tonumber(saved.version)
    if savedVersion ~= 1 and savedVersion ~= 2 then return fallback end
    local profile = { version = 2 }
    local highestName, highestValue
    for _, name in ipairs(dimensions) do
        local value = clamp(saved[name] == nil and fallback[name] or saved[name], 0, 100)
        profile[name] = value
        if highestValue == nil or value > highestValue then
            highestName, highestValue = name, value
        end
    end
    local inferred = ({ courage = "brave", caution = "cautious", compassion = "caring", practicality = "practical" })[highestName]
    profile.archetype = validArchetypes[saved.archetype] and saved.archetype or inferred
    profile.background = SC.Background and SC.Background.copy
        and SC.Background.copy(background) or background
    profile.profession = profile.background and profile.background.profession or nil
    profile.aptitude = profile.background and profile.background.aptitude or nil
    return profile
end

function Personality.apply(id, personalityState)
    personalityState = type(personalityState) == "table" and personalityState or {}
    local profile = Personality.initialize(id, personalityState.background, personalityState.profile)
    personalityState.profile = profile
    personalityState.archetype = profile.archetype
    return profile
end

local function centered(profile, name)
    profile = type(profile) == "table" and profile or {}
    return (clamp(profile[name] == nil and 50 or profile[name], 0, 100) - 50) / 50
end

local function config(name, fallback)
    local value = SC.GameplayUtil and type(SC.GameplayUtil.config) == "function"
        and SC.GameplayUtil.config(name) or nil
    return tonumber(value) or fallback
end

function Personality.adjustDecision(profile, candidate, context)
    candidate = type(candidate) == "table" and candidate or {}
    context = type(context) == "table" and context or {}
    local kind = candidate.kind
    local courage = centered(profile, "courage")
    local caution = centered(profile, "caution")
    local compassion = centered(profile, "compassion")
    local practical = centered(profile, "practicality")
    local delta = 0
    if kind == "medical" then
        delta = compassion * (context.rescue and 8 or 5)
    elseif kind == "combat" then
        delta = courage * 5 - caution * 2
    elseif kind == "retreat" then
        delta = caution * 6 - courage * 3
    elseif kind == "tactical" or kind == "alert" then
        delta = caution * 5 + practical * 2
    elseif kind == "downtime" then
        delta = practical * 5 + caution
    elseif kind == "scavenge" then
        delta = practical * 6 - caution * (context.indoors and 2 or 0)
    elseif kind == "encounter" then
        delta = caution * 2 + compassion * 2
    end
    if SC.Background and type(SC.Background.decisionModifier) == "function" then
        delta = delta + SC.Background.decisionModifier(profile, kind)
    end
    local cap = config("personalityDecisionModifierCap", 8)
    return clamp(delta, -cap, cap)
end

function Personality.overrunThresholdDelta(profile, context)
    context = type(context) == "table" and context or {}
    local courage = centered(profile, "courage")
    local caution = centered(profile, "caution")
    local delta = (courage - caution) * 3
    if (tonumber(context.escapeCount) or 0) <= 0 or (tonumber(context.support) or 0) <= 0 then
        delta = math.min(0, delta)
    end
    local cap = config("personalityOverrunModifierCap", 4)
    return clamp(delta, -cap, cap)
end

function Personality.adjustDowntime(profile, activity)
    activity = type(activity) == "table" and activity or {}
    local kind = activity.kind
    local practical = centered(profile, "practicality")
    local compassion = centered(profile, "compassion")
    local caution = centered(profile, "caution")
    local delta = 0
    if kind == "repair" or kind == "craft_supply" then delta = practical * 6
    elseif kind == "replace_bandage" then delta = compassion * 3
    elseif kind == "read" or kind == "sit" then delta = caution * 2 + practical end
    if SC.Background and type(SC.Background.downtimeModifier) == "function" then
        delta = delta + SC.Background.downtimeModifier(profile, kind)
    end
    local cap = config("personalityDowntimeModifierCap", 6)
    return clamp(delta, -cap, cap)
end

function Personality.voice(profile)
    profile = type(profile) == "table" and profile or {}
    return validArchetypes[profile.archetype] and profile.archetype or "practical"
end

function Personality.copy(profile)
    profile = type(profile) == "table" and profile or {}
    return {
        version = 2,
        archetype = Personality.voice(profile),
        courage = clamp(profile.courage, 0, 100),
        caution = clamp(profile.caution, 0, 100),
        compassion = clamp(profile.compassion, 0, 100),
        practicality = clamp(profile.practicality, 0, 100),
        profession = profile.profession,
        aptitude = profile.aptitude,
        background = SC.Background and SC.Background.copy
            and SC.Background.copy(profile.background) or profile.background,
    }
end

return Personality
