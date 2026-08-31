-- SPDX-License-Identifier: MIT

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
if not SC.GameplayUtil and type(require) == "function" then pcall(require, "SCGameplayUtil") end
if not SC.Dialogue and type(require) == "function" then pcall(require, "SCDialogue") end
if not SC.Background and type(require) == "function" then pcall(require, "SCBackground") end

SC.Relationship = SC.Relationship or {}
local Relationship = SC.Relationship
local observations = setmetatable({}, { __mode = "k" })

local validEmotes = {
    wavehi = true, wavebye = true, clap = true, thumbsup = true, thankyou = true,
    insult = true, stop = true, surrender = true, thumbsdown = true,
    followme = true, comehere = true, yes = true, no = true, shrug = true,
    undecided = true, ceasefire = true, signalok = true, moveout = true,
    freeze = true, followbehind = true, signalfire = true, comefront = true,
    salute = true,
}

local function U()
    return SC.GameplayUtil
end

local function clamp(value, low, high)
    value = tonumber(value)
    if value == nil or value ~= value or value == math.huge or value == -math.huge then value = low end
    if value < low then return low end
    if value > high then return high end
    return value
end

local function copyMap(source)
    local result = {}
    local count = 0
    if type(source) == "table" then
        for key, value in pairs(source) do
            if (type(key) == "string" or type(key) == "number")
                and (type(value) == "string" or type(value) == "number"
                    or type(value) == "boolean") then
                result[key] = value
                count = count + 1
                if count >= 64 then break end
            end
        end
    end
    return result
end

local function replaceArguments(value, arguments)
    local result = tostring(value or "")
    for index, argument in ipairs(arguments or {}) do
        result = string.gsub(result, "%%" .. tostring(index), tostring(argument))
    end
    return result
end

local function text(key, fallback, ...)
    local arguments = { ... }
    return U().text(key, replaceArguments(fallback, arguments), unpack(arguments))
end

local function varied(actor, topic, fallback, arguments, state, options)
    options = type(options) == "table" and options or {}
    options.state, options.fallback = state, fallback
    if SC.Dialogue and type(SC.Dialogue.choose) == "function" then
        local line = SC.Dialogue.choose(actor, topic, nil, arguments, options)
        if type(line) == "string" and line ~= "" then return line end
    end
    return replaceArguments(fallback, arguments)
end

local function backgroundFor(actor, source)
    local seed = actor and U().idOf(actor) or "survivor"
    if SC.Background and type(SC.Background.initialize) == "function" then
        return SC.Background.initialize(seed, source)
    end
    source = type(source) == "table" and source or {}
    return source
end

function Relationship.initialize(actor, state)
    if type(state) ~= "table" then return nil end
    state.trust = clamp(state.trust, 0, 100)
    state.bond = clamp(state.bond, 0, 100)
    state.morale = clamp(state.morale == nil and 55 or state.morale, 0, 100)
    state.stress = clamp(state.stress == nil and 12 or state.stress, 0, 100)
    state.memories = type(state.memories) == "table" and state.memories or {}
    state.background = backgroundFor(actor, state.background)
    state.care = copyMap(state.care)
    state.reveals = copyMap(state.reveals)
    state.timeTogetherMs = math.max(0, tonumber(state.timeTogetherMs) or 0)
    return state
end

function Relationship.isEmote(name)
    return type(name) == "string" and validEmotes[name] == true
end

function Relationship.playEmote(actor, emote)
    if not actor or not Relationship.isEmote(emote) then return false, "invalid_emote" end
    local accepted = U().move(actor, "walk", {
        action = "hand_signal",
        emote = emote,
        humanAnimationOnly = true,
    })
    return accepted == true, accepted == true and "emote_started" or "emote_rejected"
end

function Relationship.tier(state)
    state = type(state) == "table" and state or {}
    local score = clamp(state.trust, 0, 100) * 0.55 + clamp(state.bond, 0, 100) * 0.45
    if score >= 80 then return "family" end
    if score >= 55 then return "close" end
    if score >= 30 then return "trusted" end
    if score >= 10 then return "ally" end
    return "cautious"
end

function Relationship.mood(state)
    state = type(state) == "table" and state or {}
    local stress = clamp(state.stress, 0, 100)
    local morale = clamp(state.morale == nil and 55 or state.morale, 0, 100)
    if stress >= 72 then return "shaken" end
    if morale <= 25 then return "low" end
    if stress >= 42 then return "uneasy" end
    if clamp(state.bond, 0, 100) >= 70 then return "loyal" end
    if morale >= 72 then return "hopeful" end
    return "steady"
end

local function latestMemory(state, predicate)
    local memories = type(state) == "table" and state.memories or nil
    if type(memories) ~= "table" then return nil end
    for index = #memories, 1, -1 do
        local memory = memories[index]
        if type(memory) == "table" and (not predicate or predicate(memory)) then return memory end
        if not predicate and memory ~= nil then return memory end
    end
    return nil
end

local memoryText = {
    recruited = { "IGUI_SC_Memory_Recruited", "You asked me to come with you. I remember deciding I did not want to face this alone." },
    treatment = { "IGUI_SC_Memory_Treatment", "You stayed close when I was hurt and helped me get patched up." },
    meal = { "IGUI_SC_Memory_Meal", "You made sure I had something to eat when I needed it." },
    drink = { "IGUI_SC_Memory_Drink", "You made sure I had water when I was running dry." },
    shared_escape = { "IGUI_SC_Memory_Escape", "We got out together when things were closing in. I have not forgotten that." },
    rescued_player = { "IGUI_SC_Memory_Rescue", "I helped pull the danger away from you. We made it through." },
    companion_hurt = { "IGUI_SC_Memory_Hurt", "I got hurt while we were together. I was scared, but you did not leave." },
    player_helped = { "IGUI_SC_Memory_HelpedPlayer", "You were hurt, and I did what I could to help you." },
    background = { "IGUI_SC_Memory_Background", "You took the time to ask who I was before all this." },
    worked = { "IGUI_SC_Memory_Worked", "I used the quiet time to keep our gear and supplies in shape." },
    goal_completed = { "IGUI_SC_Memory_GoalCompleted", "We managed something that mattered to me." },
}

function Relationship.memoryText(memory)
    if type(memory) ~= "table" then
        if type(memory) == "string" and memory ~= "" then return memory end
        return text("IGUI_SC_Memory_None", "I do not have much to say about that yet.")
    end
    if type(memory.text) == "string" and memory.text ~= "" then return memory.text end
    if memory.kind == "companion_died" then
        return text("IGUI_SC_Memory_CompanionDied",
            "%1 died. I keep thinking about the time we had together.",
            type(memory.subjectName) == "string" and memory.subjectName or "Someone from our group")
    end
    if memory.kind == "goal_completed" and type(memory.objectiveKind) == "string"
        and SC.Objectives and type(SC.Objectives.label) == "function" then
        return text("IGUI_SC_Memory_GoalCompletedNamed", "We did it: %1.",
            SC.Objectives.label(memory.objectiveKind))
    end
    local specification = memoryText[memory.kind]
    if specification then return text(specification[1], specification[2]) end
    return text("IGUI_SC_Memory_Generic", "I remember us getting through another day together.")
end

function Relationship.recentMemory(state)
    return Relationship.memoryText(latestMemory(state))
end

local function recordEvent(state, kind, changes)
    if type(state) ~= "table" or type(kind) ~= "string" then return nil end
    Relationship.initialize(nil, state)
    changes = type(changes) == "table" and changes or {}
    local memory = {
        kind = kind,
        at = math.max(0, math.floor(tonumber(changes.at) or U().nowMs())),
        impact = tonumber(changes.impact) or 1,
        praised = false,
    }
    if type(changes.objectiveKind) == "string" then memory.objectiveKind = changes.objectiveKind end
    if type(changes.subjectId) == "string" then memory.subjectId = changes.subjectId end
    if type(changes.subjectName) == "string" then memory.subjectName = changes.subjectName end
    if changes.witnessed ~= nil then memory.witnessed = changes.witnessed == true end
    state.memories[#state.memories + 1] = memory
    local maximum = tonumber(U().config("maxMemories")) or 24
    while #state.memories > maximum do table.remove(state.memories, 1) end
    state.trust = clamp((state.trust or 0) + (tonumber(changes.trust) or 0), 0, 100)
    state.bond = clamp((state.bond or 0) + (tonumber(changes.bond) or 0), 0, 100)
    state.morale = clamp((state.morale or 55) + (tonumber(changes.morale) or 0), 0, 100)
    state.stress = clamp((state.stress or 12) + (tonumber(changes.stress) or 0), 0, 100)
    if type(changes.counter) == "string" then
        state.care[changes.counter] = (tonumber(state.care[changes.counter]) or 0) + 1
    end
    return memory
end

function Relationship.noteEvent(state, kind, changes)
    return recordEvent(state, kind, changes)
end

function Relationship.noteWork(state, fact)
    if type(state) ~= "table" or type(fact) ~= "table" then return false end
    local kind = fact.activity or fact.kind
    if kind ~= "repair" and kind ~= "craft_supply" and kind ~= "replace_bandage" then return false end
    local now = U().nowMs()
    local previous = tonumber(state.lastWorkMemoryAt) or 0
    if previous > 0 and now - previous < 300000 then return false end
    state.lastWorkMemoryAt = now
    recordEvent(state, "worked", { morale = 1, counter = "usefulWork" })
    return true
end

local function woundCount(actor)
    if SC.Medical and type(SC.Medical.assess) == "function" then
        local ok, assessment = pcall(SC.Medical.assess, actor)
        if ok and type(assessment) == "table" then
            return tonumber(assessment.woundCount) or 0, tonumber(assessment.health) or U().nativeHealth(actor)
        end
    end
    return 0, U().nativeHealth(actor)
end

local function eventReady(runtime, kind, now, cooldown)
    runtime.cooldowns = runtime.cooldowns or {}
    if now < (tonumber(runtime.cooldowns[kind]) or 0) then return false end
    runtime.cooldowns[kind] = now + (cooldown or 60000)
    return true
end

function Relationship.observe(actor, player, snapshot, state)
    if not actor or not player or type(state) ~= "table" then return false end
    Relationship.initialize(actor, state)
    local now = U().nowMs()
    local runtime = observations[actor]
    local interval = tonumber(U().config("relationshipObservationIntervalMs")) or 1000
    if runtime and now - (tonumber(runtime.sampledAt) or 0) < interval then return false end
    local wounds, health = woundCount(actor)
    local playerWounds, playerHealth = woundCount(player)
    local hunger = U().characterStatValue(actor, "HUNGER", 0)
    local thirst = U().characterStatValue(actor, "THIRST", 0)
    local danger = tonumber(snapshot and (snapshot.pressure or snapshot.immediateCount)) or 0
    local playerDanger = tonumber(snapshot and snapshot.player and snapshot.player.danger) or 0
    local close = U().distance(actor, player) <= 8 and U().sameFloor(actor, player)
    if not runtime then
        observations[actor] = {
            sampledAt = now, health = health, wounds = wounds, hunger = hunger, thirst = thirst,
            danger = danger, playerDanger = playerDanger, playerHealth = playerHealth,
            playerWounds = playerWounds, cooldowns = {}, persistedAt = now,
        }
        return false
    end

    local changed, meaningful = false, false
    local elapsed = math.max(0, math.min(30000, now - (runtime.sampledAt or now)))
    if close and elapsed > 0 then
        state.timeTogetherMs = (state.timeTogetherMs or 0) + elapsed
        changed = true
    end
    if close and ((health - (runtime.health or health)) >= 5 or wounds < (runtime.wounds or wounds))
        and eventReady(runtime, "treatment", now, 90000) then
        recordEvent(state, "treatment", { trust = 5, bond = 4, morale = 4, stress = -8, counter = "treatments" })
        meaningful = true
    elseif close and health < (runtime.health or health) - 7
        and eventReady(runtime, "companion_hurt", now, 120000) then
        recordEvent(state, "companion_hurt", { bond = 1, stress = 8, morale = -3, counter = "sharedInjuries" })
        meaningful = true
    end
    if close and hunger < (runtime.hunger or hunger) - 0.12
        and eventReady(runtime, "meal", now, 90000) then
        recordEvent(state, "meal", { trust = 3, bond = 2, morale = 3, stress = -2, counter = "meals" })
        meaningful = true
    end
    if close and thirst < (runtime.thirst or thirst) - 0.12
        and eventReady(runtime, "drink", now, 90000) then
        recordEvent(state, "drink", { trust = 3, bond = 2, morale = 2, stress = -2, counter = "drinks" })
        meaningful = true
    end
    if close and (runtime.danger or 0) >= 0.5 and danger < 0.2
        and eventReady(runtime, "shared_escape", now, 180000) then
        recordEvent(state, "shared_escape", { trust = 2, bond = 4, morale = 3, stress = -5, counter = "sharedEscapes" })
        meaningful = true
    end
    if close and (runtime.playerDanger or 0) >= 0.5 and playerDanger < 0.2
        and eventReady(runtime, "rescued_player", now, 180000) then
        recordEvent(state, "rescued_player", { trust = 2, bond = 5, morale = 4, stress = -3, counter = "rescues" })
        meaningful = true
    end
    if close and ((playerHealth - (runtime.playerHealth or playerHealth)) >= 5
        or playerWounds < (runtime.playerWounds or playerWounds))
        and eventReady(runtime, "player_helped", now, 120000) then
        recordEvent(state, "player_helped", { bond = 3, morale = 3, counter = "playerTreatments" })
        meaningful = true
    end

    runtime.sampledAt, runtime.health, runtime.wounds = now, health, wounds
    runtime.hunger, runtime.thirst = hunger, thirst
    runtime.danger, runtime.playerDanger = danger, playerDanger
    runtime.playerHealth, runtime.playerWounds = playerHealth, playerWounds
    if meaningful or (changed and now - (runtime.persistedAt or 0) >= 60000) then
        runtime.persistedAt = now
        return true, meaningful and "relationship_event" or "time_together"
    end
    return false
end

local function needCode(description, state)
    description = type(description) == "table" and description or {}
    if description.knoxInfected == true then return "knox" end
    if tonumber(description.health or 100) < 45 or tonumber(description.woundCount or 0) > 0 then return "medical" end
    if tonumber(description.thirst or 0) >= 0.62 then return "water" end
    if tonumber(description.hunger or 0) >= 0.62 then return "food" end
    if clamp(state.stress, 0, 100) >= 60 then return "safety" end
    local supplies = type(description.supplies) == "table" and description.supplies or {}
    if tonumber(supplies.bandages or 0) <= 0 then return "bandages" end
    if tonumber(description.ammunition or 0) <= 0 and state.weaponPriority == "firearm" then return "ammunition" end
    return "ready"
end

function Relationship.summary(actor, state, description)
    state = type(state) == "table" and state or {}
    local background = backgroundFor(actor, state.background)
    local publicBackground = {}
    local backgroundFields = { "occupation", "history", "home", "value", "fear", "habit" }
    local revealedBackground = math.max(0, math.min(#backgroundFields,
        math.floor(tonumber(type(state.reveals) == "table" and state.reveals.background or 0) or 0)))
    for index = 1, revealedBackground do
        local key = backgroundFields[index]
        if key == "occupation" and SC.Background and SC.Background.professionLabel then
            publicBackground[key] = SC.Background.professionLabel(background)
        elseif key == "history" and SC.Background and SC.Background.historyText then
            publicBackground[key] = SC.Background.historyText(background)
        elseif type(background[key]) == "string" then
            publicBackground[key] = background[key]
        end
    end
    local hours = math.floor(((tonumber(state.timeTogetherMs) or 0) / 3600000) * 10) / 10
    local profession = SC.Background and SC.Background.professionLabel
        and SC.Background.professionLabel(background) or background.occupation
    local aptitude = SC.Background and SC.Background.aptitudeLabel
        and SC.Background.aptitudeLabel(background) or "Adaptable"
    return {
        bond = clamp(state.bond, 0, 100),
        morale = clamp(state.morale == nil and 55 or state.morale, 0, 100),
        stress = clamp(state.stress == nil and 12 or state.stress, 0, 100),
        relationshipTier = Relationship.tier(state),
        mood = Relationship.mood(state),
        currentNeed = needCode(description, state),
        recentMemory = Relationship.recentMemory(state),
        background = publicBackground,
        profession = profession,
        aptitude = aptitude,
        backgroundLabel = profession .. " / " .. aptitude,
        timeTogetherHours = hours,
    }
end

local needResponses = {
    knox = { "IGUI_SC_Needs_Knox", "I need you to know something is wrong. It feels like Knox symptoms.", "undecided" },
    medical = { "IGUI_SC_Needs_Medical", "I need treatment and a clean bandage.", "undecided" },
    water = { "IGUI_SC_Needs_Water", "Water, if we can spare it. I am getting very thirsty.", "undecided" },
    food = { "IGUI_SC_Needs_Food", "Food would help. I am running on empty.", "undecided" },
    safety = { "IGUI_SC_Needs_Safety", "I need a quiet minute somewhere safe.", "ceasefire" },
    bandages = { "IGUI_SC_Needs_Bandages", "We should find clean bandages before someone needs one.", "undecided" },
    ammunition = { "IGUI_SC_Needs_Ammo", "I am short on ammunition. I will save what I have.", "ceasefire" },
    ready = { "IGUI_SC_Needs_Ready", "I am all right for now. Ready when you are.", "signalok" },
}

local function voiced(state, sentence)
    local voice = type(state.personalityProfile) == "table"
        and state.personalityProfile.archetype or state.personality or "practical"
    local fallbacks = {
        brave = "Straight answer: ",
        cautious = "If we are careful: ",
        caring = "Between us: ",
        practical = "Simply put: ",
    }
    return text("IGUI_SC_VoiceLead_" .. tostring(voice),
        fallbacks[voice] or fallbacks.practical) .. sentence
end

local function backgroundLine(codeType, code)
    if codeType == "History" then return tostring(code or "") end
    local key = "IGUI_SC_Background_" .. codeType .. "_" .. tostring(code)
    local fallback = tostring(code):gsub("_", " ")
    if codeType == "Occupation" then fallback = "Before this, I worked as a " .. fallback .. "." end
    if codeType == "Home" then fallback = "I was living around " .. fallback .. " when it started." end
    if codeType == "Value" then fallback = "The thing I try not to lose is " .. fallback .. "." end
    if codeType == "Fear" then fallback = "What scares me most is " .. fallback .. "." end
    if codeType == "Habit" then fallback = "I still " .. fallback .. ". It helps me feel normal." end
    return text(key, fallback)
end

local function keepsakeLine(state)
    local keepsake = type(state.possessions) == "table" and state.possessions.keepsake or nil
    local kind = type(keepsake) == "table" and keepsake.kind or "memento"
    local fallbacks = {
        photo = "I keep an old photo with me. It reminds me that there was a life before this.",
        locket = "This locket is one of the few personal things I have left.",
        watch = "This watch belonged to someone I do not want to forget.",
        journal = "I keep this journal so the days do not all disappear into each other.",
        memento = "I carry a small memento. It is personal, but I wanted you to know.",
    }
    return text("IGUI_SC_Keepsake_Reveal_" .. tostring(kind), fallbacks[kind] or fallbacks.memento)
end

local function backgroundResponse(state)
    local trust = clamp(state.trust, 0, 100)
    local allowed = trust >= 80 and 7 or trust >= 70 and 6 or trust >= 55 and 5
        or trust >= 40 and 4 or trust >= 25 and 3 or trust >= 10 and 2 or 1
    local revealed = math.floor(tonumber(state.reveals.background) or 0)
    local history = SC.Background and SC.Background.historyText
        and SC.Background.historyText(state.background) or state.background.history
    local occupation = SC.Background and SC.Background.professionLabel
        and string.lower(SC.Background.professionLabel(state.background))
        or state.background.occupation
    local details = {
        { "Occupation", occupation }, { "History", history }, { "Home", state.background.home },
        { "Value", state.background.value }, { "Fear", state.background.fear },
        { "Habit", state.background.habit },
        { "Keepsake", "personal" },
    }
    if revealed < allowed then
        revealed = revealed + 1
        state.reveals.background = revealed
        state.bond = clamp((state.bond or 0) + 1, 0, 100)
        if revealed == 1 and not latestMemory(state, function(memory) return memory.kind == "background" end) then
            recordEvent(state, "background", { bond = 1, morale = 1, counter = "conversations" })
        end
        if details[revealed][1] == "Keepsake" then
            state.reveals.keepsake = true
            if type(state.possessions) == "table" and type(state.possessions.keepsake) == "table" then
                state.possessions.keepsake.revealed = true
            end
            return keepsakeLine(state), "thankyou", true
        end
        return backgroundLine(details[revealed][1], details[revealed][2]), "yes", true
    end
    if revealed < 7 then
        return text("IGUI_SC_Background_Reserved", "Maybe another time. Some things are still hard to talk about."), "undecided", false
    end
    return backgroundLine("Habit", state.background.habit), "shrug", false
end

function Relationship.respond(action, actor, player, state, description)
    Relationship.initialize(actor, state)
    description = type(description) == "table" and description or {}
    local now = U().nowMs()
    if action == "plans" then
        if SC.Objectives and type(SC.Objectives.respondPlans) == "function" then
            return SC.Objectives.respondPlans(state, actor)
        end
        return nil, nil, false, "objectives_unavailable"
    elseif action == "status" then
        local grief = type(description.grief) == "table" and description.grief or nil
        if grief and tonumber(grief.currentIntensity or 0) > 0 then
            local subject = grief.subjectName or "Someone from our group"
            return varied(actor, "status.grief", text("IGUI_SC_Status_Grieving",
                "I am not all right yet. %1 is gone, and I need time.", subject),
                { subject }, state), "undecided", false
        end
        local need = needCode(description, state)
        if need ~= "ready" then
            local response = needResponses[need]
            return varied(actor, "status." .. tostring(need),
                text(response[1], response[2]), nil, state), response[3], false
        end
        if Relationship.mood(state) == "shaken" or Relationship.mood(state) == "uneasy" then
            return varied(actor, "status.shaken", text("IGUI_SC_Status_Shaken",
                "Physically I am okay. I am still trying to settle my nerves."),
                nil, state), "undecided", false
        end
        local voice = type(state.personalityProfile) == "table"
            and state.personalityProfile.archetype or state.personality or "practical"
        local fallbacks = {
            brave = "I am holding up. Point me where you need me.",
            cautious = "I am holding up. I am still watching our exits.",
            caring = "I am all right. How are you holding up?",
            practical = "I am holding up. Our supplies and gear are in order for now.",
        }
        return varied(actor, "status.ready", text("IGUI_SC_Status_Good_" .. tostring(voice),
            fallbacks[voice] or fallbacks.practical), nil, state), "thumbsup", false
    elseif action == "needs" then
        local response = needResponses[needCode(description, state)]
        local need = needCode(description, state)
        return varied(actor, "status." .. tostring(need),
            voiced(state, text(response[1], response[2])), nil, state), response[3], false
    elseif action == "memory" then
        local memory = latestMemory(state)
        if type(memory) == "table" and memory.kind == "companion_died" then
            local subject = type(memory.subjectName) == "string"
                and memory.subjectName or "Someone from our group"
            return varied(actor, "memory.companion_died",
                Relationship.memoryText(memory), { subject }, state), "undecided", false
        end
        return Relationship.memoryText(memory), "undecided", false
    elseif action == "background" then
        return backgroundResponse(state)
    elseif action == "opinion" then
        if tonumber(description.immediateCount or 0) > 0 or clamp(state.stress, 0, 100) >= 60 then
            return varied(actor, "opinion.danger", text("IGUI_SC_Opinion_Danger",
                "We are pushing our luck. I want a clear way out before we go farther."),
                nil, state), "ceasefire", false
        end
        if state.order == "guard" then
            return varied(actor, "opinion.guard", text("IGUI_SC_Opinion_Guard",
                "This position can work, but I am keeping an eye on the exits."),
                nil, state), "signalok", false
        end
        if state.scavenge == true then
            return varied(actor, "opinion.scavenge", text("IGUI_SC_Opinion_Scavenge",
                "I can search as we move. I will leave anything you have already claimed alone."),
                nil, state), "signalok", false
        end
        local voice = type(state.personalityProfile) == "table"
            and state.personalityProfile.archetype or state.personality or "practical"
        local fallbacks = {
            brave = "We can handle a fight, but only if it gets us somewhere.",
            cautious = "Slow and deliberate. I want a clear way back out.",
            caring = "We stay together and avoid fights that put either of us at needless risk.",
            practical = "We conserve ammunition, keep our tools ready, and choose useful fights.",
        }
        return varied(actor, "opinion.general", text("IGUI_SC_Opinion_" .. tostring(voice),
            fallbacks[voice] or fallbacks.practical), nil, state), "yes", false
    elseif action == "relationship" then
        local tier = Relationship.tier(state)
        local fallback = text("IGUI_SC_Relationship_" .. tier,
            tier == "family" and "You are family to me now. I am not walking away."
            or tier == "close" and "I trust you with my life. That is not something I say lightly."
            or tier == "trusted" and "We have been through enough that I know you will be there."
            or tier == "ally" and "We work well together. Trust takes time, but we are getting there."
            or "I am still getting to know you. Give me time.")
        return varied(actor, "relationship." .. tostring(tier), fallback, nil, state),
            tier == "cautious" and "undecided" or "thankyou", false
    elseif action == "encourage" then
        local lastEncouragedAt = tonumber(state.lastEncouragedAt) or 0
        if lastEncouragedAt > 0 and now < lastEncouragedAt + 120000 then
            return varied(actor, "encourage.recent", text("IGUI_SC_Encourage_Recent",
                "I heard you. Give me a minute to breathe."), nil, state), "yes", false
        end
        if clamp(state.stress, 0, 100) < 30 and clamp(state.morale, 0, 100) > 60 then
            return varied(actor, "encourage.not_needed", text("IGUI_SC_Encourage_NotNeeded",
                "I am good. Save that speech for when one of us really needs it."),
                nil, state), "thumbsup", false
        end
        state.lastEncouragedAt = now
        state.stress = clamp((state.stress or 12) - 12, 0, 100)
        state.morale = clamp((state.morale or 55) + 8, 0, 100)
        state.bond = clamp((state.bond or 0) + 1, 0, 100)
        return varied(actor, "encourage.accept", text("IGUI_SC_Encourage_Response",
            "Thank you. I needed to hear that."), nil, state), "thankyou", true
    elseif action == "praise" then
        local memory = latestMemory(state, function(candidate)
            return candidate.praised ~= true and (candidate.kind == "rescued_player"
                or candidate.kind == "shared_escape" or candidate.kind == "player_helped"
                or candidate.kind == "worked")
        end)
        if not memory then
            return varied(actor, "praise.none", text("IGUI_SC_Praise_NoEvent",
                "Thanks, but let us save the celebration until the work is done."),
                nil, state), "shrug", false
        end
        memory.praised = true
        state.bond = clamp((state.bond or 0) + 3, 0, 100)
        state.morale = clamp((state.morale or 55) + 6, 0, 100)
        state.care.praise = (tonumber(state.care.praise) or 0) + 1
        return varied(actor, "praise.accept", text("IGUI_SC_Praise_Response",
            "That means more than you know."), nil, state), "thankyou", true
    end
    return nil, nil, false, "unsupported_conversation"
end

function Relationship.reset(actor)
    if actor then observations[actor] = nil else observations = setmetatable({}, { __mode = "k" }) end
    return true
end

return Relationship
