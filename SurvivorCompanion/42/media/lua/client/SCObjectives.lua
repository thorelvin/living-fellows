-- SPDX-License-Identifier: MIT

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
if not SC.GameplayUtil and type(require) == "function" then pcall(require, "SCGameplayUtil") end
if not SC.Dialogue and type(require) == "function" then pcall(require, "SCDialogue") end

SC.Objectives = SC.Objectives or {}
local Objectives = SC.Objectives
local audits = setmetatable({}, { __mode = "k" })

local kinds = {
    keep_medical_ready = true,
    find_something_to_read = true,
    put_gear_in_order = true,
    improve_shelter = true,
    share_a_proper_meal = true,
    recover_keepsake = true,
}

local labels = {
    keep_medical_ready = { "IGUI_SC_Objective_Medical", "Keep clean bandages ready" },
    find_something_to_read = { "IGUI_SC_Objective_Reading", "Find something worth reading" },
    put_gear_in_order = { "IGUI_SC_Objective_Gear", "Put our gear in order" },
    improve_shelter = { "IGUI_SC_Objective_Shelter", "Improve this shelter" },
    share_a_proper_meal = { "IGUI_SC_Objective_Meal", "Share a proper meal" },
    recover_keepsake = { "IGUI_SC_Objective_Keepsake", "Recover the personal keepsake" },
}

local requests = {
    keep_medical_ready = { "IGUI_SC_Objective_Request_Medical", "I would feel better if we kept two clean bandages ready." },
    find_something_to_read = { "IGUI_SC_Objective_Request_Reading", "I would like to find something worth reading when things are quiet." },
    put_gear_in_order = { "IGUI_SC_Objective_Request_Gear", "I want to repair our worn gear before it fails us." },
    improve_shelter = { "IGUI_SC_Objective_Request_Shelter", "I want to make this place a little harder for the dead to enter." },
    share_a_proper_meal = { "IGUI_SC_Objective_Request_Meal", "I miss sitting down for a proper meal with someone." },
    recover_keepsake = { "IGUI_SC_Objective_Request_Keepsake", "I am missing something personal. I would like it back." },
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

local function cleanText(value, limit)
    value = tostring(value or "")
    value = string.gsub(value, "[%c]", "")
    if #value > (limit or 128) then value = string.sub(value, 1, limit or 128) end
    return value
end

local function hash(value)
    local result = 3571
    value = tostring(value or "objective")
    for index = 1, #value do
        result = (result * 137 + string.byte(value, index)) % 2147483647
    end
    return result
end

local function objectiveNowMs()
    if type(getGameTime) == "function" then
        local ok, gameTime = pcall(getGameTime)
        if ok and gameTime then
            local age, ageOk = U().call(gameTime, "getWorldAgeHours")
            if ageOk and type(age) == "number" then return math.floor(age * 3600000) end
        end
    end
    return U().nowMs()
end

local function copyRow(source)
    if type(source) ~= "table" or not kinds[source.kind] then return nil end
    return {
        version = 1,
        id = cleanText(source.id, 128),
        kind = source.kind,
        status = source.status == "completed" and "completed" or "active",
        revealed = source.revealed == true,
        progress = clamp(source.progress, 0, 1),
        createdAt = math.max(0, tonumber(source.createdAt) or 0),
        completedAt = source.completedAt and math.max(0, tonumber(source.completedAt) or 0) or nil,
    }
end

function Objectives.normalize(source)
    source = type(source) == "table" and source or {}
    local result = {
        version = 1,
        serial = math.max(0, math.floor(tonumber(source.serial) or 0)),
        active = copyRow(source.active),
        history = {},
        nextEligibleAt = math.max(0, tonumber(source.nextEligibleAt) or 0),
    }
    if result.active and result.active.status == "completed" then result.active = nil end
    local maximum = U().config("maxObjectiveHistory") or 8
    for _, row in ipairs(type(source.history) == "table" and source.history or {}) do
        local copy = copyRow(row)
        if copy and copy.status == "completed" then result.history[#result.history + 1] = copy end
    end
    while #result.history > maximum do table.remove(result.history, 1) end
    return result
end

local function eachInventory(actor, callback)
    if SC.PersonalItems and type(SC.PersonalItems.walkActorInventory) == "function" then
        return SC.PersonalItems.walkActorInventory(actor, callback)
    end
    for _, item in ipairs(U().inventoryItems(U().inventory(actor), U().config("maxInventoryItems") or 256)) do
        if callback(item, 0) == false then return false end
    end
    return true
end

local function isCleanBandage(item)
    if SC.PersonalItems and SC.PersonalItems.isProtected(item, nil, "medical_consume") then return false end
    local itemType = string.lower(U().itemType(item))
    local dirty, dirtyOk = U().call(item, "isDirty")
    local bloody, bloodyOk = U().call(item, "isBloody")
    if (dirtyOk and dirty) or (bloodyOk and bloody) or string.find(itemType, "dirty", 1, true) then return false end
    return string.find(itemType, "bandage", 1, true) ~= nil
        or string.find(itemType, "rippedsheet", 1, true) ~= nil
        or U().itemHasTag(item, "CanBandage")
end

local function isLiterature(item, actor)
    local category, categoryOk = U().call(item, "getCategory")
    local display, displayOk = U().call(item, "getDisplayCategory")
    local itemType = string.lower(U().itemType(item))
    if displayOk and string.lower(tostring(display)) == "memento" then return false end
    local literature = (categoryOk and tostring(category) == "Literature")
        or (displayOk and tostring(display) == "Literature")
        or string.find(itemType, "book", 1, true) ~= nil
        or string.find(itemType, "magazine", 1, true) ~= nil
    if not literature then return false end
    local pages, pagesOk = U().call(item, "getNumberOfPages")
    if pagesOk and type(pages) == "number" and pages <= 0 then return false end
    if actor and pagesOk and type(pages) == "number" then
        local alreadyRead, readOk = U().call(actor, "getAlreadyReadPages", U().itemType(item))
        if readOk and type(alreadyRead) == "number" and alreadyRead >= pages then return false end
    end
    return true
end

local function isReadyWeapon(item)
    local category, categoryOk = U().call(item, "getCategory")
    local weapon = U().instanceOf(item, "HandWeapon")
        or (categoryOk and tostring(category) == "Weapon")
    if not weapon then return false end
    local condition, conditionOk = U().call(item, "getCondition")
    local maximum, maximumOk = U().call(item, "getConditionMax")
    return conditionOk and maximumOk and type(condition) == "number"
        and type(maximum) == "number" and maximum > 0 and condition / maximum >= 0.8
end

local function inventoryProgress(actor, kind, state)
    if kind == "recover_keepsake" then
        local keepsake = type(state.possessions) == "table" and state.possessions.keepsake or nil
        return keepsake and keepsake.status == "carried" and 1 or 0
    end
    local count = 0
    eachInventory(actor, function(item)
        if kind == "keep_medical_ready" and isCleanBandage(item) then count = count + 1
        elseif kind == "find_something_to_read" and isLiterature(item, actor) then count = 1
        elseif kind == "put_gear_in_order" and isReadyWeapon(item) then count = 1 end
        if kind == "keep_medical_ready" then
            if count >= 2 then return false end
        elseif count >= 1 then
            return false
        end
    end)
    if kind == "keep_medical_ready" then return clamp(count / 2, 0, 1) end
    if kind == "find_something_to_read" or kind == "put_gear_in_order" then
        return count >= 1 and 1 or 0
    end
    return 0
end

local function recentKind(objectives, kind)
    for index = #objectives.history, math.max(1, #objectives.history - 2), -1 do
        if objectives.history[index] and objectives.history[index].kind == kind then return true end
    end
    return false
end

local function candidates(actor, state, objectives)
    local result = {}
    local possessions = type(state.possessions) == "table" and state.possessions or {}
    if possessions.keepsake and possessions.keepsake.status ~= "carried" then
        result[#result + 1] = "recover_keepsake"
    end
    if inventoryProgress(actor, "keep_medical_ready", state) < 1 then result[#result + 1] = "keep_medical_ready" end
    if inventoryProgress(actor, "find_something_to_read", state) < 1 then result[#result + 1] = "find_something_to_read" end
    if inventoryProgress(actor, "put_gear_in_order", state) < 1 then
        result[#result + 1] = "put_gear_in_order"
    end
    result[#result + 1] = "improve_shelter"
    result[#result + 1] = "share_a_proper_meal"
    local filtered = {}
    for _, kind in ipairs(result) do
        if not recentKind(objectives, kind) then filtered[#filtered + 1] = kind end
    end
    return #filtered > 0 and filtered or result
end

local function candidateScore(id, serial, kind, state)
    local profile = type(state.personalityProfile) == "table" and state.personalityProfile or {}
    local background = type(state.background) == "table" and state.background or {}
    local score = 10 + (hash(tostring(id) .. ":" .. tostring(serial) .. ":" .. kind) % 20)
    if kind == "keep_medical_ready" then score = score + (tonumber(profile.compassion) or 50) * 0.25
    elseif kind == "find_something_to_read" then score = score + (tonumber(profile.caution) or 50) * 0.15
    elseif kind == "put_gear_in_order" or kind == "improve_shelter" then
        score = score + (tonumber(profile.practicality) or 50) * 0.25
    elseif kind == "share_a_proper_meal" then score = score + (tonumber(profile.compassion) or 50) * 0.2
    elseif kind == "recover_keepsake" then score = score + 100 end
    local occupation = background.occupation
    if kind == "find_something_to_read" and (occupation == "teacher" or occupation == "librarian") then score = score + 28 end
    if kind == "put_gear_in_order" and (occupation == "mechanic" or occupation == "electrician") then score = score + 25 end
    if kind == "improve_shelter" and (occupation == "carpenter" or occupation == "warehouse") then score = score + 25 end
    if kind == "keep_medical_ready" and (occupation == "nurse" or occupation == "paramedic") then score = score + 30 end
    if kind == "share_a_proper_meal" and occupation == "cook" then score = score + 30 end
    if SC.Background and type(SC.Background.objectiveModifier) == "function" then
        score = score + SC.Background.objectiveModifier(background, kind)
    end
    return score
end

local function generate(actor, state, objectives, current)
    local id = U().idOf(actor)
    if not id then return false end
    local best, bestScore
    local nextSerial = objectives.serial + 1
    for _, kind in ipairs(candidates(actor, state, objectives)) do
        local score = candidateScore(id, nextSerial, kind, state)
        if not bestScore or score > bestScore then best, bestScore = kind, score end
    end
    if not best then return false end
    objectives.serial = nextSerial
    objectives.active = {
        version = 1,
        id = id .. ":objective:" .. tostring(nextSerial),
        kind = best,
        status = "active",
        revealed = false,
        progress = inventoryProgress(actor, best, state),
        createdAt = current,
    }
    return true
end

local function complete(state, objectives, current)
    local active = objectives.active
    if not active or active.status ~= "active" then return false end
    active.status = "completed"
    active.progress = 1
    active.completedAt = current
    objectives.history[#objectives.history + 1] = copyRow(active)
    local maximum = U().config("maxObjectiveHistory") or 8
    while #objectives.history > maximum do table.remove(objectives.history, 1) end
    objectives.active = nil
    objectives.nextEligibleAt = current + (U().config("objectiveCooldownMs") or 21600000)
    if SC.Relationship and type(SC.Relationship.noteEvent) == "function" then
        SC.Relationship.noteEvent(state, "goal_completed", {
            bond = active.revealed and 1 or 0,
            morale = 4,
            counter = "goalsCompleted",
            objectiveKind = active.kind,
        })
    end
    return true
end

function Objectives.initialize(actor, state)
    if not actor or type(state) ~= "table" then return nil, false end
    local objectives = Objectives.normalize(state.objectives)
    local changed = type(state.objectives) ~= "table" or tonumber(state.objectives.version) ~= 1
    local current = objectiveNowMs()
    if not objectives.active and current >= objectives.nextEligibleAt then
        changed = generate(actor, state, objectives, current) or changed
    end
    state.objectives = objectives
    return objectives, changed
end

function Objectives.update(actor, state, current)
    if not actor or type(state) ~= "table" then return false end
    local auditCurrent = current or U().nowMs()
    local interval = U().config("objectiveAuditIntervalMs") or 5000
    if auditCurrent < (audits[actor] or 0) then return false end
    audits[actor] = auditCurrent + interval
    local objectives, changed = Objectives.initialize(actor, state)
    if not objectives then return changed end
    local active = objectives.active
    if active and (active.kind == "keep_medical_ready" or active.kind == "find_something_to_read"
        or active.kind == "put_gear_in_order" or active.kind == "recover_keepsake") then
        local progress = inventoryProgress(actor, active.kind, state)
        if math.abs(progress - (active.progress or 0)) > 0.001 then active.progress = progress changed = true end
        if progress >= 1 then changed = complete(state, objectives, objectiveNowMs()) or changed end
    end
    return changed
end

function Objectives.noteEvent(state, event, fact)
    if type(state) ~= "table" then return false end
    local objectives = Objectives.normalize(state.objectives)
    state.objectives = objectives
    local active = objectives.active
    if not active or active.status ~= "active" then return false end
    fact = type(fact) == "table" and fact or {}
    local matched = active.kind == "share_a_proper_meal" and event == "meal"
        or active.kind == "put_gear_in_order" and event == "worked" and fact.activity == "repair"
        or active.kind == "improve_shelter" and event == "worked" and fact.activity == "barricade"
    if not matched then return false end
    active.progress = 1
    return complete(state, objectives, objectiveNowMs())
end

local function variedPlan(actor, topic, fallback, state)
    if SC.Dialogue and type(SC.Dialogue.choose) == "function" then
        local line = SC.Dialogue.choose(actor, topic, nil, nil,
            { state = state, fallback = fallback })
        if type(line) == "string" and line ~= "" then return line end
    end
    return fallback
end

function Objectives.respondPlans(state, actor)
    if type(state) ~= "table" then return nil, nil, false, "objective_state_unavailable" end
    local objectives = Objectives.normalize(state.objectives)
    state.objectives = objectives
    local active = objectives.active
    if not active then
        local fallback = U().text("IGUI_SC_Objective_None",
            "Nothing specific. I need a little time to think.")
        return variedPlan(actor, "plans.none", fallback, state), "shrug", false
    end
    if active.revealed ~= true and (tonumber(state.trust) or 0) < 10 then
        local fallback = U().text("IGUI_SC_Objective_Reserved",
            "I am not ready to talk about that yet.")
        return variedPlan(actor, "plans.reserved", fallback, state), "undecided", false
    end
    local changed = active.revealed ~= true
    active.revealed = true
    local specification = requests[active.kind]
    local voice = type(state.personalityProfile) == "table"
        and state.personalityProfile.archetype or state.personality or "practical"
    local voiceFallbacks = {
        brave = "Straight answer: ",
        cautious = "If we can do it safely: ",
        caring = "For both our sakes: ",
        practical = "What would help most: ",
    }
    local lead = U().text("IGUI_SC_VoiceLead_" .. tostring(voice),
        voiceFallbacks[voice] or voiceFallbacks.practical)
    local fallback = lead .. U().text(specification[1], specification[2])
    return variedPlan(actor, "plans." .. tostring(active.kind), fallback, state), "yes", changed
end

function Objectives.label(kind)
    local specification = labels[kind]
    return specification and U().text(specification[1], specification[2])
        or U().text("IGUI_SC_Objective_Unknown", "Unknown personal goal")
end

function Objectives.describe(source)
    local objectives = Objectives.normalize(source)
    local active = objectives.active
    if not active or active.revealed ~= true then
        return { known = false, status = active and "private" or "none", progress = 0 }
    end
    return {
        known = true,
        id = active.id,
        kind = active.kind,
        label = Objectives.label(active.kind),
        status = active.status,
        progress = clamp(active.progress, 0, 1),
    }
end

function Objectives.decisionBonus(source, kind)
    local active = type(source) == "table" and source.active or nil
    if type(active) ~= "table" or active.status ~= "active" then return 0 end
    if kind == "scavenge" and (active.kind == "keep_medical_ready"
        or active.kind == "find_something_to_read" or active.kind == "recover_keepsake") then
        return U().config("objectiveDecisionModifierCap") or 4
    end
    if kind == "downtime" and (active.kind == "put_gear_in_order"
        or active.kind == "improve_shelter") then return U().config("objectiveDecisionModifierCap") or 4 end
    return 0
end

function Objectives.activityBonus(source, activity)
    local active = type(source) == "table" and source.active or nil
    if type(active) ~= "table" or type(activity) ~= "table" then return 0 end
    if active.kind == "put_gear_in_order" and activity.kind == "repair" then
        return U().config("objectiveActivityModifierCap") or 6
    end
    return 0
end

function Objectives.itemBonus(source, item, actor)
    local active = type(source) == "table" and source.active or nil
    if type(active) ~= "table" or not item then return 0 end
    local cap = U().config("objectiveItemModifierCap") or 12
    if active.kind == "keep_medical_ready" and isCleanBandage(item) then return cap end
    if active.kind == "find_something_to_read" and isLiterature(item, actor) then return cap end
    if active.kind == "recover_keepsake" and SC.PersonalItems then
        local personal = SC.PersonalItems.personalRecord(item)
        if personal and string.find(active.id or "", personal.ownerId, 1, true) == 1 then return cap end
    end
    return 0
end

function Objectives.reset(actor)
    if actor then audits[actor] = nil else audits = setmetatable({}, { __mode = "k" }) end
end

return Objectives
