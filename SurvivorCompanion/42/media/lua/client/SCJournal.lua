-- SPDX-License-Identifier: MIT

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
if not SC.GameplayUtil and type(require) == "function" then pcall(require, "SCGameplayUtil") end

SC.Journal = SC.Journal or {}
local Journal = SC.Journal

local function U()
    return SC.GameplayUtil
end

local function copyMap(source)
    local result = {}
    local count = 0
    if type(source) == "table" then
        for key, value in pairs(source) do
            if type(key) == "string" and (type(value) == "string" or type(value) == "number"
                or type(value) == "boolean") then
                result[key] = value
                count = count + 1
                if count >= 32 then break end
            end
        end
    end
    return result
end

local function profileLabel(archetype)
    local fallback = ({ brave = "Brave", cautious = "Cautious", caring = "Caring", practical = "Practical" })[archetype]
        or "Practical"
    return U().text("UI_SC_Personality_" .. tostring(archetype or "practical"), fallback)
end

local function backgroundRows(state)
    local rows = {}
    local revealed = math.max(0, math.floor(tonumber(type(state.reveals) == "table"
        and state.reveals.background or 0) or 0))
    local background = type(state.background) == "table" and state.background or {}
    local fields = {
        { id = "occupation", label = "UI_SC_Journal_Occupation" },
        { id = "history", label = "UI_SC_Journal_History" },
        { id = "home", label = "UI_SC_Journal_Home" },
        { id = "value", label = "UI_SC_Journal_Value" },
        { id = "fear", label = "UI_SC_Journal_Fear" },
        { id = "habit", label = "UI_SC_Journal_Habit" },
    }
    for index, field in ipairs(fields) do
        if index <= revealed and type(background[field.id]) == "string" then
            local value = background[field.id]
            if field.id == "occupation" and SC.Background
                and type(SC.Background.professionLabel) == "function" then
                value = SC.Background.professionLabel(background)
            elseif field.id == "history" and SC.Background
                and type(SC.Background.historyText) == "function" then
                value = SC.Background.historyText(background)
            end
            rows[#rows + 1] = {
                key = field.id,
                label = U().text(field.label, field.id),
                value = value,
            }
        end
    end
    return rows
end

local function timeline(state)
    local result = {}
    local memories = type(state.memories) == "table" and state.memories or {}
    local maximum = U().config("maxJournalMemories") or 12
    for index = #memories, math.max(1, #memories - maximum + 1), -1 do
        local memory = memories[index]
        if type(memory) == "table" then
            local textValue = SC.Relationship and type(SC.Relationship.memoryText) == "function"
                and SC.Relationship.memoryText(memory) or tostring(memory.kind or "memory")
            result[#result + 1] = {
                kind = tostring(memory.kind or "memory"),
                text = textValue,
                at = math.max(0, tonumber(memory.at) or 0),
                objectiveKind = type(memory.objectiveKind) == "string" and memory.objectiveKind or nil,
            }
        end
    end
    return result
end

local function reasons(state, memories)
    local result = {}
    for index = 1, math.min(3, #memories) do result[#result + 1] = memories[index].text end
    if #result == 0 and (tonumber(state.timeTogetherMs) or 0) > 0 then
        result[1] = U().text("UI_SC_Journal_Reason_Time", "You have survived together for a while.")
    end
    return result
end

function Journal.build(actor, state, description)
    state = type(state) == "table" and state or {}
    description = type(description) == "table" and description or {}
    local profile = type(state.personalityProfile) == "table" and state.personalityProfile or {}
    local memories = timeline(state)
    local objective = SC.Objectives and type(SC.Objectives.describe) == "function"
        and SC.Objectives.describe(state.objectives) or { known = false, status = "none", progress = 0 }
    local possessions = type(state.possessions) == "table" and state.possessions or {}
    local keepsakeRevealed = type(state.reveals) == "table" and state.reveals.keepsake == true
    local keepsake = SC.PersonalItems and type(SC.PersonalItems.description) == "function"
        and SC.PersonalItems.description(possessions, keepsakeRevealed)
        or { known = false, status = "unknown", kind = "private" }
    return {
        version = 1,
        name = description.name or (actor and U().nameOf(actor)) or U().text("UI_SC_UnknownCompanion", "Unknown companion"),
        profile = {
            archetype = profile.archetype or state.personality or "practical",
            label = profileLabel(profile.archetype or state.personality),
            courage = math.max(0, math.min(100, tonumber(profile.courage) or 50)),
            caution = math.max(0, math.min(100, tonumber(profile.caution) or 50)),
            compassion = math.max(0, math.min(100, tonumber(profile.compassion) or 50)),
            practicality = math.max(0, math.min(100, tonumber(profile.practicality) or 50)),
        },
        backgroundProfile = {
            profession = SC.Background and SC.Background.professionLabel
                and SC.Background.professionLabel(state.background) or "Unknown",
            aptitude = SC.Background and SC.Background.aptitudeLabel
                and SC.Background.aptitudeLabel(state.background) or "Adaptable",
            preferredRole = SC.Background and SC.Background.preferredRole
                and SC.Background.preferredRole(state.background) or "generalist",
        },
        background = backgroundRows(state),
        relationship = {
            tier = description.relationshipTier or (SC.Relationship and SC.Relationship.tier(state)) or "cautious",
            mood = description.mood or (SC.Relationship and SC.Relationship.mood(state)) or "steady",
            trust = tonumber(state.trust) or 0,
            bond = tonumber(state.bond) or 0,
            morale = tonumber(state.morale) or 55,
            stress = tonumber(state.stress) or 12,
            reasons = reasons(state, memories),
        },
        objective = objective,
        keepsake = keepsake,
        memories = memories,
        care = copyMap(state.care),
        timeTogetherHours = math.floor(((tonumber(state.timeTogetherMs) or 0) / 3600000) * 10) / 10,
    }
end

return Journal
