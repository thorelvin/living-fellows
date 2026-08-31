-- SPDX-License-Identifier: MIT

local SC = SurvivorCompanion
SC.FactionLife = SC.FactionLife or {}

local Life = SC.FactionLife
local LIFE_SCHEMA = 1
local actorStates = setmetatable({}, { __mode = "k" })

local personalityOrder = {
    "Paranoid", "Generous", "Militarized", "Desperate", "Isolationist", "Resourceful",
}

local personalityDefinitions = {
    Paranoid = { caution = 82, generosity = 25, discipline = 64, solidarity = 58, openness = 18 },
    Generous = { caution = 44, generosity = 84, discipline = 48, solidarity = 76, openness = 74 },
    Militarized = { caution = 68, generosity = 34, discipline = 88, solidarity = 70, openness = 30 },
    Desperate = { caution = 56, generosity = 18, discipline = 32, solidarity = 42, openness = 46 },
    Isolationist = { caution = 76, generosity = 28, discipline = 62, solidarity = 66, openness = 10 },
    Resourceful = { caution = 52, generosity = 54, discipline = 72, solidarity = 68, openness = 48 },
}

local relationKinds = { "Family", "Friends", "Partners", "Strangers", "Rivals" }
local rumourKinds = { "supply_cache", "horde", "water_source", "shelter" }
local crisisKinds = { supply_collapse = true, illness = true, internal_dispute = true }
local resourceKinds = { "food", "water", "medicine", "construction", "ammunition", "tools" }

local function U()
    return SC.GameplayUtil
end

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, tonumber(value) or minimum))
end

local function worldHour()
    if type(getGameTime) == "function" then
        local ok, gameTime = pcall(getGameTime)
        if ok and gameTime then
            local value, called = U().call(gameTime, "getWorldAgeHours")
            if called and tonumber(value) then return tonumber(value) end
        end
    end
    return U().nowMs() / 3600000
end

local function timeOfDay()
    if type(getGameTime) == "function" then
        local ok, gameTime = pcall(getGameTime)
        if ok and gameTime then
            local value, called = U().call(gameTime, "getTimeOfDay")
            if called and tonumber(value) then return tonumber(value) % 24 end
        end
    end
    return worldHour() % 24
end

local function stringHash(value)
    local hash = 5381
    value = tostring(value or "")
    for index = 1, #value do hash = (hash * 33 + string.byte(value, index)) % 2147483647 end
    return hash
end

local function boundedAppend(list, value, maximum)
    list[#list + 1] = value
    while #list > maximum do table.remove(list, 1) end
end

local function shallowCopy(source)
    local result = {}
    for key, value in pairs(type(source) == "table" and source or {}) do result[key] = value end
    return result
end

local function memberPairKey(left, right)
    left, right = tostring(left or ""), tostring(right or "")
    if left > right then left, right = right, left end
    return left .. "|" .. right
end

local function livingMembers(group)
    local result = {}
    for _, member in ipairs(type(group) == "table" and group.members or {}) do
        if member.alive ~= false and member.away == nil and member.departed ~= true then
            result[#result + 1] = member
        end
    end
    return result
end

local function memberForActor(group, actor)
    local id = actor and U().idOf(actor) or nil
    if not id then return nil, nil end
    for index, member in ipairs(group.members or {}) do
        if member.actorId == id then return member, index end
    end
    return nil, nil
end

local function recordForMember(member)
    return member and member.actorId and SC.Registry and SC.Registry.byId(member.actorId) or nil
end

local function activeActorCount(group)
    local count = 0
    for _, member in ipairs(livingMembers(group)) do
        local record = recordForMember(member)
        if record and record.actor and not U().isDead(record.actor) then count = count + 1 end
    end
    return count
end

local function personalityFor(group)
    local first = (stringHash(group.id) % #personalityOrder) + 1
    local second = ((first + 1 + stringHash(group.name) % (#personalityOrder - 1))
        % #personalityOrder) + 1
    if second == first then second = (second % #personalityOrder) + 1 end
    local primary, secondary = personalityOrder[first], personalityOrder[second]
    local left, right = personalityDefinitions[primary], personalityDefinitions[secondary]
    local values = {}
    for _, key in ipairs({ "caution", "generosity", "discipline", "solidarity", "openness" }) do
        values[key] = math.floor((left[key] * 0.7 + right[key] * 0.3) + 0.5)
    end
    return { primary = primary, secondary = secondary, values = values }
end

local function relationFor(group, left, right)
    local seed = stringHash(group.id .. ":" .. left.key .. ":" .. right.key)
    local kind = relationKinds[(seed % #relationKinds) + 1]
    local affinity = kind == "Family" and 58 or kind == "Partners" and 66
        or kind == "Friends" and 42 or kind == "Rivals" and -24 or 8
    local trust = kind == "Family" and 72 or kind == "Partners" and 78
        or kind == "Friends" and 55 or kind == "Rivals" and 18 or 32
    return {
        left = left.key, right = right.key, kind = kind,
        affinity = clamp(affinity + (seed % 17) - 8, -100, 100),
        trust = clamp(trust + (math.floor(seed / 17) % 17) - 8, 0, 100),
        tension = clamp(kind == "Rivals" and 58 or 8 + (seed % 23), 0, 100),
        lastChangeHour = worldHour(),
    }
end

local rumourLabels = {
    supply_cache = "Reported supply cache",
    horde = "Reported horde",
    water_source = "Reported water source",
    shelter = "Possible shelter",
}

local function makeRumours(group)
    local result, anchor = {}, group.house and group.house.anchor or { x = 0, y = 0, z = 0 }
    local minimum = tonumber(SC.Config.get("factionRumourMinDistance")) or 45
    local maximum = tonumber(SC.Config.get("factionRumourMaxDistance")) or 120
    for index = 1, 3 do
        local seed = stringHash(group.id .. ":rumour:" .. tostring(index))
        local kind = rumourKinds[(seed % #rumourKinds) + 1]
        local angle = (seed % 6283) / 1000
        local distance = minimum + (math.floor(seed / 7) % math.max(1, maximum - minimum + 1))
        local sourceX = math.floor(anchor.x + math.cos(angle) * distance)
        local sourceY = math.floor(anchor.y + math.sin(angle) * distance)
        local uncertainty = 8 + (seed % 28)
        local errorAngle = (math.floor(seed / 31) % 6283) / 1000
        result[#result + 1] = {
            id = group.id .. ":rumour:" .. tostring(index), kind = kind,
            label = rumourLabels[kind],
            sourceX = sourceX, sourceY = sourceY,
            x = math.floor(sourceX + math.cos(errorAngle) * uncertainty),
            y = math.floor(sourceY + math.sin(errorAngle) * uncertainty), z = 0,
            reportedDay = math.floor(worldHour() / 24),
            accuracy = uncertainty, uncertaintyRadius = uncertainty,
            shared = false, mapSymbolAdded = false,
        }
    end
    return result
end

local function initialResources(group)
    local size = math.max(1, #livingMembers(group))
    local counts = {
        food = size * 3, water = size * 3, medicine = math.max(1, size),
        construction = size * 6, ammunition = size * 4, tools = size,
    }
    local shortageMap = {
        food = "food", water = "water", medicine = "medicine",
        materials = "construction", ammunition = "ammunition", tools = "tools",
    }
    local shortage = shortageMap[group.shortageKind]
    if shortage then counts[shortage] = shortage == "tools" and 0 or math.max(0, size - 1) end
    return { counts = counts, thresholds = {}, level = "Unknown", shortage = shortage,
        lastAuditHour = nil, source = "seeded" }
end

local function ensureRelations(group, life)
    life.relationships = type(life.relationships) == "table" and life.relationships or {}
    local members = livingMembers(group)
    for left = 1, #members do
        for right = left + 1, #members do
            local key = memberPairKey(members[left].key, members[right].key)
            if type(life.relationships[key]) ~= "table" then
                life.relationships[key] = relationFor(group, members[left], members[right])
            end
        end
    end
end

function Life.initialize(group)
    if type(group) ~= "table" then return nil, "faction_unavailable" end
    local life = type(group.life) == "table" and group.life or {}
    group.life = life
    life.schema = LIFE_SCHEMA
    life.personality = type(life.personality) == "table" and life.personality
        or personalityFor(group)
    if not personalityDefinitions[life.personality.primary]
        or not personalityDefinitions[life.personality.secondary] then
        life.personality = personalityFor(group)
    end
    life.personality.values = type(life.personality.values) == "table"
        and life.personality.values or personalityFor(group).values
    ensureRelations(group, life)
    life.resources = type(life.resources) == "table" and life.resources
        or initialResources(group)
    life.resources.counts = type(life.resources.counts) == "table"
        and life.resources.counts or initialResources(group).counts
    life.resources.thresholds = type(life.resources.thresholds) == "table"
        and life.resources.thresholds or {}
    life.routines = type(life.routines) == "table" and life.routines or {}
    life.representative = type(life.representative) == "table" and life.representative
        or { state = "inside", memberKey = nil, requested = false }
    life.crisis = type(life.crisis) == "table" and life.crisis
        or { active = nil, history = {}, nextEligibleHour = worldHour() + 24,
            nextCheckHour = worldHour() + 6 }
    life.crisis.history = type(life.crisis.history) == "table" and life.crisis.history or {}
    life.rumours = type(life.rumours) == "table" and life.rumours or makeRumours(group)
    life.events = type(life.events) == "table" and life.events or {}
    if type(life.mourning) == "table" then
        life.mourning.subjectKey = tostring(life.mourning.subjectKey or "")
        life.mourning.subjectName = tostring(life.mourning.subjectName or "Survivor")
        life.mourning.startedHour = math.max(0, tonumber(life.mourning.startedHour) or 0)
        life.mourning.untilHour = math.max(life.mourning.startedHour,
            tonumber(life.mourning.untilHour) or life.mourning.startedHour)
    else
        life.mourning = nil
    end
    return life
end

local function resourceThresholds(group)
    local alive = math.max(1, #livingMembers(group))
    local jobs = 0
    for _, job in ipairs(group.jobs or {}) do
        if job.status ~= "completed" and job.status ~= "cancelled" then jobs = jobs + 1 end
    end
    return {
        food = alive * 2, water = alive * 2, medicine = math.max(1, math.ceil(alive / 2)),
        construction = math.max(1, jobs * 2), ammunition = alive * 2,
        tools = math.min(2, alive),
    }
end

local function resourceLevel(count, threshold)
    if threshold <= 0 then return "Stable", 1 end
    local ratio = count / threshold
    if ratio < 0.35 then return "Critical", ratio end
    if ratio < 0.9 then return "Low", ratio end
    if ratio < 2 then return "Stable", ratio end
    return "Well supplied", ratio
end

local function categoryForItem(item)
    if SC.Logistics and type(SC.Logistics.itemCategory) == "function" then
        local ok, category = pcall(SC.Logistics.itemCategory, item)
        if ok and type(category) == "string" then return category end
    end
    local itemType = string.lower(U().itemType(item))
    local category, categoryOk = U().call(item, "getCategory")
    category = categoryOk and string.lower(tostring(category or "")) or ""
    if category == "food" then return "food" end
    if string.find(itemType, "water", 1, true) then return "water" end
    if string.find(itemType, "bandage", 1, true) or string.find(itemType, "pill", 1, true) then
        return "medicine"
    end
    if string.find(itemType, "plank", 1, true) or string.find(itemType, "nail", 1, true) then
        return "construction"
    end
    if string.find(itemType, "bullet", 1, true) or string.find(itemType, "ammo", 1, true) then
        return "ammunition"
    end
    if string.find(itemType, "hammer", 1, true) or string.find(itemType, "saw", 1, true) then
        return "tools"
    end
    return nil
end

local function countResourceItems(container, counts, state, depth)
    if container == nil or state.remaining <= 0 or depth > 3 then return end
    for _, item in ipairs(U().inventoryItems(container, math.min(384, state.remaining))) do
        if state.remaining <= 0 then break end
        state.remaining = state.remaining - 1
        local category = categoryForItem(item)
        if counts[category] ~= nil then counts[category] = counts[category] + 1 end
        local nested, nestedOk = U().call(item, "getInventory")
        if nestedOk and nested ~= nil and nested ~= container then
            countResourceItems(nested, counts, state, depth + 1)
        end
    end
end

function Life.auditResources(group, force)
    local life = Life.initialize(group)
    if not life then return false, "faction_unavailable" end
    local hour = worldHour()
    local interval = tonumber(SC.Config.get("factionResourceAuditHours")) or 1
    if force ~= true and life.resources.lastAuditHour
        and hour - life.resources.lastAuditHour < interval then
        return true, life.resources
    end
    local alive = #livingMembers(group)
    if alive == 0 then return false, "household_destroyed" end
    if activeActorCount(group) < alive then return false, "household_not_fully_loaded" end
    local counts = { food = 0, water = 0, medicine = 0, construction = 0,
        ammunition = 0, tools = 0 }
    for _, member in ipairs(livingMembers(group)) do
        local record = recordForMember(member)
        local inventory = record and U().inventory(record.actor) or nil
        countResourceItems(inventory, counts, { remaining = 512 }, 0)
    end
    local thresholds, worstKind, worstRatio, worstLevel = resourceThresholds(group), nil, math.huge, "Stable"
    local levels = {}
    for _, kind in ipairs(resourceKinds) do
        local threshold = thresholds[kind]
        local level, ratio = resourceLevel(counts[kind] or 0, threshold)
        levels[kind] = level
        if ratio < worstRatio then worstKind, worstRatio, worstLevel = kind, ratio, level end
    end
    local prior = life.resources.level
    life.resources = {
        counts = counts, thresholds = thresholds, levels = levels,
        level = worstLevel, shortage = worstKind, lastAuditHour = hour, source = "inventory",
    }
    if prior ~= nil and prior ~= "Unknown" and prior ~= worstLevel then
        boundedAppend(life.events, {
            hour = hour, kind = "resource_level_changed", from = prior, to = worstLevel,
            shortage = worstKind,
        }, 128)
    end
    return true, life.resources
end

local function watchMemberKey(group, hour)
    local members = livingMembers(group)
    if #members == 0 then return nil end
    local day = math.floor(hour / 24)
    return members[(day % #members) + 1].key
end

local function routineTarget(group, memberIndex, phase, block)
    local interior = group.house and group.house.interior or {}
    if #interior == 0 then return group.house and group.house.anchor or nil end
    local cursor = ((math.max(1, memberIndex) - 1 + stringHash(phase .. ":" .. tostring(block)))
        % #interior) + 1
    local position = interior[cursor]
    return { x = position.x, y = position.y, z = position.z or 0 }
end

local function routineFor(group, member, memberIndex, hour)
    local tod, block = timeOfDay(), math.floor(hour * 2) / 2
    local watchKey = watchMemberKey(group, hour)
    local primary = group.life.personality.primary
    local phase
    local mourning = type(group.life.mourning) == "table" and group.life.mourning or nil
    local griefBlock = mourning and hour < (tonumber(mourning.untilHour) or 0)
        and (hour - (tonumber(mourning.startedHour) or hour) < 6
            or (math.floor(hour * 2) + stringHash(member.key .. ":mourning")) % 8 == 0)
    if griefBlock and member.key ~= watchKey then phase = "mourning"
    elseif tod < 5.5 then phase = member.key == watchKey and "watch" or "sleep"
    elseif tod < 8.5 then phase = member.role == "watch" and "watch" or "meal"
    elseif tod < 17 then
        if member.role == "watch"
            or (primary == "Paranoid" or primary == "Militarized") and member.key == watchKey then
            phase = "watch"
        elseif member.role == "builder" then phase = "maintenance"
        elseif primary == "Desperate" then phase = "inventory_check"
        else phase = "organize" end
    elseif tod < 20 then phase = member.role == "watch" and "watch" or "socialize"
    elseif tod < 23 then
        phase = member.key == watchKey and "watch"
            or member.role == "builder" and "maintenance" or "read"
    else phase = member.key == watchKey and "watch" or "sleep" end
    return {
        phase = phase, block = block, sinceHour = hour,
        target = routineTarget(group, memberIndex, phase, block),
    }
end

local function updateRoutines(group, hour)
    local life = group.life
    local block = math.floor(timeOfDay() * 2) / 2
    if life.lastRoutineBlock == block and life.lastRoutineDay == math.floor(hour / 24) then return end
    life.lastRoutineBlock, life.lastRoutineDay = block, math.floor(hour / 24)
    for index, member in ipairs(group.members or {}) do
        if member.alive ~= false and member.away == nil and member.departed ~= true then
            local nextRoutine = routineFor(group, member, index, hour)
            local prior = life.routines[member.key]
            if not prior or prior.phase ~= nextRoutine.phase then
                boundedAppend(life.events, {
                    hour = hour, kind = "routine_changed", member = member.key,
                    from = prior and prior.phase or nil, to = nextRoutine.phase,
                }, 128)
            end
            life.routines[member.key] = nextRoutine
        end
    end
end

local function relationForCrisis(group)
    local selected
    for _, relation in pairs(group.life.relationships or {}) do
        if not selected or (tonumber(relation.tension) or 0) > (tonumber(selected.tension) or 0) then
            selected = relation
        end
    end
    return selected
end

local function resolveCrisis(group, outcome)
    local crisisState = group.life.crisis
    local active = crisisState.active
    if not active then return false, "no_active_crisis" end
    active.resolvedHour, active.outcome = worldHour(), outcome or "resolved"
    boundedAppend(crisisState.history, shallowCopy(active), 32)
    boundedAppend(group.life.events, {
        hour = worldHour(), kind = "crisis_resolved", crisis = active.kind,
        outcome = active.outcome,
    }, 128)
    crisisState.active = nil
    crisisState.nextEligibleHour = worldHour()
        + (tonumber(SC.Config.get("factionCrisisCooldownHours")) or 72)
    return true, active.outcome
end

function Life.resolveCrisis(groupOrId, outcome, expectedKind)
    local group = type(groupOrId) == "table" and groupOrId
        or SC.Factions and SC.Factions.group(groupOrId) or nil
    if not group then return false, "faction_unavailable" end
    local life = Life.initialize(group)
    local active = life.crisis and life.crisis.active or nil
    if not active then return false, "no_active_crisis" end
    if expectedKind and active.kind ~= expectedKind then
        return false, "different_crisis_active"
    end
    return resolveCrisis(group, outcome)
end

local function triggerCrisis(group, kind, forced)
    local life = Life.initialize(group)
    if life.crisis.active then return false, "crisis_already_active" end
    if not crisisKinds[kind] then return false, "invalid_crisis" end
    local hour, members = worldHour(), livingMembers(group)
    if forced ~= true and hour < (tonumber(life.crisis.nextEligibleHour) or 0) then
        return false, "crisis_cooldown"
    end
    local active = { kind = kind, state = "active", startedHour = hour, stage = 1 }
    if kind == "supply_collapse" then
        active.resource = life.resources.shortage or group.shortageKind or "food"
        if SC.Factions and type(SC.Factions.setNeed) == "function" then
            local requestKind = active.resource == "construction" and "materials" or active.resource
            if requestKind == "tools" then requestKind = "tools" end
            pcall(SC.Factions.setNeed, group.id, requestKind, "supply_crisis")
        end
    elseif kind == "illness" then
        if #members == 0 then return false, "no_living_members" end
        active.target = members[(stringHash(group.id .. ":illness:" .. tostring(math.floor(hour)))
            % #members) + 1].key
        active.severity = 35 + (stringHash(active.target .. tostring(hour)) % 46)
    elseif kind == "internal_dispute" then
        local relation = relationForCrisis(group)
        if not relation then return false, "not_enough_members_for_dispute" end
        active.left, active.right = relation.left, relation.right
        relation.tension = clamp((tonumber(relation.tension) or 0) + 28, 0, 100)
        relation.lastChangeHour = hour
    end
    life.crisis.active = active
    boundedAppend(life.events, { hour = hour, kind = "crisis_started", crisis = kind }, 128)
    return true, kind
end

local function updateCrisis(group, hour)
    local active = group.life.crisis.active
    if not active then return end
    local age = hour - (tonumber(active.startedHour) or hour)
    if active.kind == "supply_collapse" then
        if age >= 6 and group.life.resources.level ~= "Critical"
            and group.life.resources.level ~= "Low" then
            resolveCrisis(group, "supplies_recovered")
        elseif age >= 48 then resolveCrisis(group, "household_adapted") end
    elseif active.kind == "illness" then
        local medicine = group.life.resources.levels
            and group.life.resources.levels.medicine or "Critical"
        if age >= 12 and medicine ~= "Critical" then resolveCrisis(group, "resident_recovered")
        elseif age >= 36 then resolveCrisis(group, "illness_stabilized") end
    elseif active.kind == "internal_dispute" and age >= 2 then
        local relation = group.life.relationships[memberPairKey(active.left, active.right)]
        if relation then
            local discipline = tonumber(group.life.personality.values.discipline) or 50
            relation.tension = clamp((tonumber(relation.tension) or 0) - (discipline >= 60 and 32 or 18), 0, 100)
            relation.affinity = clamp((tonumber(relation.affinity) or 0) - (discipline >= 60 and 3 or 9), -100, 100)
            relation.lastChangeHour = hour
        end
        resolveCrisis(group, discipline >= 60 and "argument_deescalated" or "resentment_lingers")
    end
end

local function maybeStartCrisis(group, hour)
    local crisisState = group.life.crisis
    if crisisState.active or hour < (tonumber(crisisState.nextEligibleHour) or 0)
        or hour < (tonumber(crisisState.nextCheckHour) or 0) then return end
    local interval = tonumber(SC.Config.get("factionCrisisCheckHours")) or 6
    crisisState.nextCheckHour = hour + interval
    local chance = tonumber(SC.Config.get("factionCrisisChancePercent")) or 4
    local primary = group.life.personality.primary
    if primary == "Desperate" then chance = chance + 3
    elseif primary == "Resourceful" then chance = math.max(1, chance - 2)
    elseif primary == "Paranoid" then chance = chance + 1 end
    local check = math.floor(hour / math.max(1, interval))
    if stringHash(group.id .. ":crisis:" .. tostring(check)) % 100 >= chance then return end
    local kind
    if group.life.resources.level == "Critical" then kind = "supply_collapse"
    elseif relationForCrisis(group) and (relationForCrisis(group).tension or 0) >= 55 then
        kind = "internal_dispute"
    else kind = (stringHash(group.id .. ":kind:" .. tostring(check)) % 2 == 0)
        and "illness" or "internal_dispute" end
    triggerCrisis(group, kind, false)
end

local function representativeMember(group)
    local fallback
    for _, member in ipairs(livingMembers(group)) do
        if member.actorId then
            if member.role == "leader" then return member end
            fallback = fallback or member
        end
    end
    return fallback
end

local function territoryDistance(group, value)
    local bounds = group.house and group.house.bounds
    local x, y = U().position(value)
    if not bounds or x == nil then return math.huge end
    local dx = x < bounds.x1 and bounds.x1 - x or x > bounds.x2 and x - bounds.x2 or 0
    local dy = y < bounds.y1 and bounds.y1 - y or y > bounds.y2 and y - bounds.y2 or 0
    return math.sqrt(dx * dx + dy * dy)
end

local function playerInside(group, player)
    local bounds = group.house and group.house.bounds
    local x, y, z = U().position(player)
    return bounds and x ~= nil and z ~= nil and z >= 0 and z <= 2
        and x >= bounds.x1 and x <= bounds.x2 and y >= bounds.y1 and y <= bounds.y2
end

local function updateRepresentative(group, player)
    local state = group.life.representative
    local outer = tonumber(SC.Config.get("factionRepresentativeApproachRadius")) or 26
    local distance = territoryDistance(group, player)
    local aiming, aimingOk = U().call(player, "isAiming")
    local primary = group.life.personality.primary
    local guarded = (primary == "Isolationist" or primary == "Paranoid")
        and group.standing == "Wary"
    local canMeet = group.discovered == true and group.standing ~= "Hostile" and not guarded
        and group.lifecycle ~= "hostile" and not playerInside(group, player)
        and not (aimingOk and aiming == true)
    if canMeet and distance <= outer then
        local member = representativeMember(group)
        state.memberKey = member and member.key or nil
        state.requested, state.state = member ~= nil, member and "approaching" or "unavailable"
    elseif distance > outer + 12 or not canMeet then
        state.requested, state.state, state.memberKey = false, "inside", nil
        state.greetedVisit = nil
    end
end

function Life.pulseGroup(group, player, current)
    local life = Life.initialize(group)
    if not life then return false, "faction_unavailable" end
    current = tonumber(current) or U().nowMs()
    if current < (tonumber(life.nextPulseAt) or 0) then return true, "life_pulse_throttled" end
    life.nextPulseAt = current + (tonumber(SC.Config.get("factionLifePulseIntervalMs")) or 2500)
    local hour = worldHour()
    Life.auditResources(group, false)
    updateRoutines(group, hour)
    updateRepresentative(group, player)
    updateCrisis(group, hour)
    maybeStartCrisis(group, hour)
    return true, "faction_life_updated"
end

local function actorState(actor)
    local state = actorStates[actor]
    if not state then
        state = { nextActionAt = 0, nextSpeechAt = 0, nextPoseAt = 0, lastMode = nil }
        actorStates[actor] = state
    end
    return state
end

local function entryPosition(group)
    local primary, interior = group.house and group.house.primaryEntry,
        group.house and group.house.interior or {}
    if not primary then return group.house and group.house.anchor end
    local best, bestDistance
    for _, position in ipairs(interior) do
        local distance = math.abs(position.x - primary.x) + math.abs(position.y - primary.y)
        if distance >= 1 and (not bestDistance or distance < bestDistance) then
            best, bestDistance = position, distance
        end
    end
    return best or group.house.anchor
end

local function approach(actor, target, action, mode)
    if target == nil then return false, "life_target_unavailable" end
    if U().distance(actor, target) <= 1.15 then return true, "life_target_reached" end
    local x, y, z = U().position(target)
    if x == nil then return false, "life_target_unavailable" end
    local square = U().gridSquare(x, y, z or 0)
    if not square or not U().isSquareFree(square) or not SC.Navigation then
        return false, "life_target_blocked"
    end
    return SC.Navigation.request(actor, square, mode or "walk", {
        action = action, targetSquare = square,
    })
end

local function visual(actor, action, state, cooldown)
    if SC.NativeActions and type(SC.NativeActions.visualStatus) == "function" then
        local status = SC.NativeActions.visualStatus(actor)
        if status == "active" then return true, "life_visual_active" end
        if status == "completed" and type(SC.NativeActions.clearVisual) == "function" then
            SC.NativeActions.clearVisual(actor)
        end
    end
    local current = U().nowMs()
    if current < (tonumber(state.nextActionAt) or 0) then
        U().stop(actor)
        return true, "life_activity_idle"
    end
    state.nextActionAt = current + (cooldown or 14000)
    return U().move(actor, "walk", { action = action })
end

local function sayOnce(actor, state, topic, fallback, arguments, cooldown)
    local current = U().nowMs()
    if current < (tonumber(state.nextSpeechAt) or 0) then return false end
    state.nextSpeechAt = current + (cooldown or 18000)
    if SC.Dialogue and type(SC.Dialogue.say) == "function" then
        local spoken = SC.Dialogue.say(actor, topic, nil, arguments, { fallback = fallback })
        return spoken == true
    end
    return U().say(actor, fallback)
end

local function conversationPose(actor, state, target, emote, cooldown)
    local current = U().nowMs()
    if current < (tonumber(state.nextPoseAt) or 0) then
        U().stop(actor)
        return true, "life_pose_held"
    end
    state.nextPoseAt = current + (cooldown or 9000)
    return U().move(actor, "walk", {
        action = "conversation_pose", target = target, targetPosition = target,
        emote = emote,
    })
end

local function updateRepresentativeActor(actor, player, group, state)
    local reached, reason = approach(actor, entryPosition(group),
        "faction_representative_approach", "walk")
    if not reached or reason ~= "life_target_reached" then return reached, reason end
    group.life.representative.state = "at_entry"
    U().stop(actor)
    local topic = "faction.life.greeting." .. tostring(group.standing or "Wary")
    local line, arguments = group.standing == "Trusted" and "Good to see a familiar face."
        or group.standing == "Tolerated" and "We can talk here. Do not enter the house."
        or "State your business from there.", nil
    local active = group.life.crisis.active
    if active and active.kind == "supply_collapse" then
        topic, line, arguments = "faction.life.supply_crisis", "We are running out of %1.",
            { active.resource or "supplies" }
    elseif active and active.kind == "illness" then
        topic, line = "faction.life.illness", "Someone inside is sick. Keep your distance."
    end
    sayOnce(actor, state, topic, line, arguments, 22000)
    return conversationPose(actor, state, player,
        group.standing == "Wary" and "undecided" or "yes", 12000)
end

local function updateDispute(actor, group, member, active, state)
    local otherKey = member.key == active.left and active.right or active.left
    local other
    for _, candidate in ipairs(group.members or {}) do
        if candidate.key == otherKey then other = recordForMember(candidate) break end
    end
    if not other or not other.actor then return visual(actor, "repair", state, 10000) end
    if U().distance(actor, other.actor) > 2.4 then
        return approach(actor, U().squareOf(other.actor), "faction_dispute_approach", "walk")
    end
    U().stop(actor)
    sayOnce(actor, state, "faction.life.dispute",
        "We cannot keep wasting supplies like this.", nil, 9000)
    return conversationPose(actor, state, other.actor, "shrug", 7000)
end

local function updateRoutine(actor, group, member, routine, state)
    if not routine then return false, "routine_unavailable" end
    if routine.phase == "watch" then return false, "delegate_guard" end
    local reached, reason = approach(actor, routine.target, "faction_routine_" .. routine.phase, "walk")
    if not reached or reason ~= "life_target_reached" then return reached, reason end
    U().stop(actor)
    if routine.phase == "sleep" then return visual(actor, "sit_ground", state, 22000)
    elseif routine.phase == "meal" then return visual(actor, "ambient_eat", state, 16000)
    elseif routine.phase == "read" then return visual(actor, "read", state, 20000)
    elseif routine.phase == "mourning" then return visual(actor, "sit_ground", state, 18000)
    elseif routine.phase == "maintenance" then return visual(actor, "repair", state, 18000)
    elseif routine.phase == "inventory_check" then return visual(actor, "loot_container", state, 14000)
    elseif routine.phase == "organize" then return visual(actor, "craft_supply", state, 18000)
    elseif routine.phase == "socialize" then
        local target
        for _, candidate in ipairs(livingMembers(group)) do
            if candidate.key ~= member.key then
                local record = recordForMember(candidate)
                if record and record.actor then target = record.actor break end
            end
        end
        if target then
            sayOnce(actor, state, "faction.life.plan",
                "We should review tomorrow's plan.", nil, 30000)
            return conversationPose(actor, state, target, "yes", 12000)
        end
    end
    return true, "routine_idle"
end

function Life.intentFor(actor, group, player, snapshot)
    if not actor or type(group) ~= "table" then return nil end
    Life.pulseGroup(group, player, U().nowMs())
    local member = memberForActor(group, actor)
    if not member then return nil end
    local representative = group.life.representative
    if representative.requested == true and representative.memberKey == member.key then
        return { priority = 62, mode = "life_representative", memberKey = member.key }
    end
    local crisis = group.life.crisis.active
    if crisis then
        if crisis.kind == "internal_dispute"
            and (member.key == crisis.left or member.key == crisis.right) then
            return { priority = 63, mode = "life_dispute", memberKey = member.key }
        elseif crisis.kind == "illness" and member.key == crisis.target then
            return { priority = 60, mode = "life_illness", memberKey = member.key }
        elseif crisis.kind == "supply_collapse" and member.role == "leader" then
            return { priority = 60, mode = "life_supply", memberKey = member.key }
        end
    end
    return { priority = 24, mode = "life_routine", memberKey = member.key,
        routine = group.life.routines[member.key] }
end

function Life.updateActor(actor, player, runtime, intent, group, affiliation)
    local member = memberForActor(group, actor)
    if not member then return false, "faction_life_member_unavailable" end
    local state = actorState(actor)
    local mode = type(intent) == "table" and intent.mode or "life_routine"
    state.lastMode = mode
    if mode == "life_representative" then
        return updateRepresentativeActor(actor, player, group, state)
    elseif mode == "life_dispute" then
        return updateDispute(actor, group, member, group.life.crisis.active, state)
    elseif mode == "life_illness" then
        sayOnce(actor, state, "faction.life.need_rest",
            "I need to sit down for a while.", nil, 30000)
        return visual(actor, "sit_ground", state, 24000)
    elseif mode == "life_supply" then
        sayOnce(actor, state, "faction.life.check_supplies",
            "Check every bag. We are short on supplies.", nil, 26000)
        return visual(actor, "loot_container", state, 16000)
    end
    local routine = group.life.routines[member.key]
    return updateRoutine(actor, group, member, routine, state)
end

local function mapSymbols()
    local mapType = type(_G) == "table" and rawget(_G, "MapItem") or nil
    if mapType == nil or type(mapType.getSingleton) ~= "function" then
        return nil, nil, "world_map_unavailable"
    end
    local ok, mapItem = pcall(mapType.getSingleton)
    if not ok or mapItem == nil then return nil, nil, "world_map_unavailable" end
    local symbols, called = U().call(mapItem, "getSymbols")
    if called and symbols ~= nil then return mapType, symbols end

    -- Build 42.20.4 keeps MapItem:getSymbols() out of Kahlua even though the
    -- Java method is public.  Vanilla edits annotations through UIWorldMapV3's
    -- symbols API, so use an existing map UI or create a tiny non-visible API
    -- bridge that points at the same singleton MapItem.
    local mapApi
    local existing = type(_G) == "table" and rawget(_G, "ISWorldMap_instance") or nil
    if existing and existing.mapAPI then mapApi = existing.mapAPI end
    if mapApi == nil and existing and existing.javaObject then
        mapApi, called = U().call(existing.javaObject, "getAPIv3")
        if not called then mapApi = nil end
    end
    local bridge
    if mapApi == nil then
        local uiType = type(_G) == "table" and rawget(_G, "UIWorldMap") or nil
        if uiType and type(uiType.new) == "function" then
            local owner = {}
            local created, value = pcall(uiType.new, owner)
            if created and value then
                bridge = { owner = owner, javaObject = value }
                mapApi, called = U().call(value, "getAPIv3")
                if not called then mapApi = nil end
            end
        end
    end
    if mapApi == nil then return nil, nil, "world_map_api_unavailable" end
    local _, assigned = U().call(mapApi, "setMapItem", mapItem)
    if not assigned then return nil, nil, "world_map_item_assignment_failed" end
    symbols, called = U().call(mapApi, "getSymbolsAPIv2")
    if not called or symbols == nil then return nil, nil, "world_map_symbols_unavailable" end
    return mapType, symbols, nil, bridge
end

local function findSymbol(symbols, text)
    local count, countOk = U().call(symbols, "getSymbolCount")
    if not countOk then return nil, nil end
    for index = 0, math.min(2047, math.max(0, tonumber(count) or 0) - 1) do
        local symbol, symbolOk = U().call(symbols, "getSymbolByIndex", index)
        if symbolOk and symbol then
            local translated, translatedOk = U().call(symbol, "getTranslatedText")
            local untranslated, untranslatedOk = U().call(symbol, "getUntranslatedText")
            if translatedOk and translated == text or untranslatedOk and untranslated == text then
                return symbol, index
            end
        end
    end
    return nil, nil
end

function Life.addMapAnnotation(text, x, y, color)
    text = tostring(text or "")
    if text == "" then return false, "world_map_symbol_text_missing" end
    local mapType, symbols, failure, bridge = mapSymbols()
    if not symbols then return false, failure end
    if not findSymbol(symbols, text) then
        local layer, layerOk
        local symbolsType = type(_G) == "table" and rawget(_G, "WorldMapSymbols") or nil
        if symbolsType and type(symbolsType.getDefaultTextLayerID) == "function" then
            local ok, value = pcall(symbolsType.getDefaultTextLayerID)
            if ok and value ~= nil then layer, layerOk = value, true end
        end
        if not layerOk then layer, layerOk = U().call(symbols, "getDefaultTextLayerID") end
        layer = layerOk and layer or "text"
        color = type(color) == "table" and color or { 0.95, 0.78, 0.25, 1.0 }
        local r, g, b, a = tonumber(color[1]) or 0.95, tonumber(color[2]) or 0.78,
            tonumber(color[3]) or 0.25, tonumber(color[4]) or 1.0
        local symbol, added = U().call(symbols, "addTranslatedText", text, layer,
            tonumber(x) or 0, tonumber(y) or 0)
        if not added or symbol == nil then
            symbol, added = U().call(symbols, "addTranslatedText", text, layer,
                tonumber(x) or 0, tonumber(y) or 0, r, g, b, a)
        end
        if not added or symbol == nil then return false, "world_map_symbol_add_failed" end
        U().call(symbol, "setRGBA", r, g, b, a)
        U().call(symbol, "setAnchor", 0.5, 0.5)
        U().call(symbol, "setScale", 0.8)
        U().call(symbol, "setCollide", true)
        U().call(symbol, "setUserDefined", true)
        U().call(symbol, "setPrivate")
    end
    if type(mapType.SaveWorldMap) == "function" then pcall(mapType.SaveWorldMap) end
    bridge = nil
    return true, text
end

function Life.removeMapAnnotation(text)
    text = tostring(text or "")
    if text == "" then return false, "world_map_symbol_text_missing" end
    local mapType, symbols, failure, bridge = mapSymbols()
    if not symbols then return false, failure end
    local symbol, index = findSymbol(symbols, text)
    if not symbol then return true, "world_map_symbol_absent" end
    local _, removed = U().call(symbols, "removeSymbol", symbol)
    if not removed then _, removed = U().call(symbols, "removeSymbolByIndex", index) end
    if not removed then return false, "world_map_symbol_remove_failed" end
    if type(mapType.SaveWorldMap) == "function" then pcall(mapType.SaveWorldMap) end
    bridge = nil
    return true, "world_map_symbol_removed"
end

local function writeRumourSymbol(rumour)
    local text = "[LF] " .. tostring(rumour.label) .. " (day "
        .. tostring(rumour.reportedDay or 0) .. ")"
    return Life.addMapAnnotation(text, rumour.x, rumour.y, { 0.95, 0.78, 0.25, 1.0 })
end

function Life.canTalk(group, player)
    if type(group) ~= "table" or player == nil then return false, "faction_unavailable" end
    if group.standing == "Hostile" or group.lifecycle == "hostile" then
        return false, "faction_hostile"
    end
    local representative = representativeMember(group)
    local record = recordForMember(representative)
    if not record or not record.actor then return false, "representative_unavailable" end
    local maximum = tonumber(SC.Config.get("factionTradeDistance")) or 6
    if U().distance(player, record.actor) > maximum then return false, "too_far_to_talk" end
    if U().canSee and U().canSee(player, record.actor) ~= true then return false, "line_of_sight_lost" end
    return true, record.actor
end

function Life.shareRumour(groupOrId, player, forced)
    local group = type(groupOrId) == "table" and groupOrId
        or SC.Factions and SC.Factions.group(groupOrId) or nil
    if not group then return false, "faction_unavailable" end
    Life.initialize(group)
    if forced ~= true then
        if group.standing ~= "Tolerated" and group.standing ~= "Trusted" then
            return false, "insufficient_trust_for_rumour"
        end
        local ready, reason = Life.canTalk(group, player)
        if not ready then return false, reason end
    end
    local selected
    for _, rumour in ipairs(group.life.rumours or {}) do
        if rumour.shared ~= true then selected = rumour break end
    end
    if not selected then return false, "no_unshared_rumours" end
    -- Trust and a relevant representative background improve a report, but
    -- never turn hearsay into exact coordinates. Existing 0.17 rumours are
    -- migrated lazily without moving a marker that was already shared.
    local seed = stringHash(selected.id)
    selected.sourceX = tonumber(selected.sourceX) or tonumber(selected.x)
        + ((seed % 13) - 6)
    selected.sourceY = tonumber(selected.sourceY) or tonumber(selected.y)
        + ((math.floor(seed / 13) % 13) - 6)
    local uncertainty = tonumber(selected.uncertaintyRadius or selected.accuracy) or 24
    local improvement = group.standing == "Trusted" and 12
        or group.standing == "Tolerated" and 6 or 2
    local representative = representativeMember(group)
    local record = recordForMember(representative)
    local background = record and record.state and record.state.personality
        and record.state.personality.background or nil
    local profession = type(background) == "table"
        and tostring(background.profession or background.occupation or "") or ""
    local informed = profession == "park_ranger" or profession == "police_officer"
        or profession == "fire_officer" or profession == "security_guard"
        or profession == "veteran" or profession == "farmer"
    if informed then improvement = improvement + 5 end
    uncertainty = math.max(4, uncertainty - improvement)
    local errorAngle = (math.floor(seed / 97) % 6283) / 1000
    selected.x = math.floor(selected.sourceX + math.cos(errorAngle) * uncertainty)
    selected.y = math.floor(selected.sourceY + math.sin(errorAngle) * uncertainty)
    selected.accuracy, selected.uncertaintyRadius = uncertainty, uncertainty
    selected.precisionSource = informed and "trust_and_background" or "trust"
    local written, reason = writeRumourSymbol(selected)
    if not written then return false, reason end
    selected.shared, selected.mapSymbolAdded, selected.sharedHour = true, true, worldHour()
    selected.sharedReason = forced == true and "debug" or "relationship"
    boundedAppend(group.life.events, {
        hour = worldHour(), kind = "rumour_shared", rumour = selected.id,
    }, 128)
    return true, selected.label
end

function Life.noteEvent(groupOrId, kind, detail)
    local group = type(groupOrId) == "table" and groupOrId
        or SC.Factions and SC.Factions.group(groupOrId) or nil
    if not group then return false, "faction_unavailable" end
    local life = Life.initialize(group)
    boundedAppend(life.events, {
        hour = worldHour(), kind = tostring(kind or "unknown"), detail = tostring(detail or ""),
    }, 128)
    if kind == "request_completed" then
        for _, relation in pairs(life.relationships or {}) do
            relation.trust = clamp((relation.trust or 0) + 3, 0, 100)
            relation.tension = clamp((relation.tension or 0) - 4, 0, 100)
        end
    elseif kind == "member_died" then
        for _, relation in pairs(life.relationships or {}) do
            relation.tension = clamp((relation.tension or 0) + 12, 0, 100)
        end
        local subjectName = "a household member"
        for _, member in ipairs(group.members or {}) do
            if member.key == detail or member.actorId == detail or member.departedActorId == detail then
                local identity = type(member.identity) == "table" and member.identity or {}
                subjectName = tostring(identity.forename or "Unknown") .. " "
                    .. tostring(identity.surname or "Survivor")
                break
            end
        end
        life.mourning = {
            subjectKey = tostring(detail or "unknown"), subjectName = subjectName,
            startedHour = worldHour(), untilHour = worldHour() + 72,
        }
    end
    return true, "event_recorded"
end

function Life.summary(groupOrId)
    local group = type(groupOrId) == "table" and groupOrId
        or SC.Factions and SC.Factions.group(groupOrId) or nil
    if not group then return nil end
    local life = Life.initialize(group)
    local names, members = {}, {}
    for _, member in ipairs(group.members or {}) do
        local identity = type(member.identity) == "table" and member.identity or {}
        local name = tostring(identity.forename or "Unknown") .. " "
            .. tostring(identity.surname or "Survivor")
        names[member.key] = name
        if member.alive ~= false and member.away == nil and member.departed ~= true then
            members[#members + 1] = {
                key = member.key, name = name, role = member.role,
                routine = life.routines[member.key] and life.routines[member.key].phase or "settling",
            }
        end
    end
    local relations = {}
    for _, relation in pairs(life.relationships or {}) do
        relations[#relations + 1] = {
            left = relation.left, right = relation.right, kind = relation.kind,
            leftName = names[relation.left] or relation.left,
            rightName = names[relation.right] or relation.right,
            affinity = math.floor(tonumber(relation.affinity) or 0),
            trust = math.floor(tonumber(relation.trust) or 0),
            tension = math.floor(tonumber(relation.tension) or 0),
        }
    end
    table.sort(relations, function(a, b) return memberPairKey(a.left, a.right) < memberPairKey(b.left, b.right) end)
    local routines = {}
    for key, routine in pairs(life.routines or {}) do routines[key] = routine.phase end
    local shared, total = 0, 0
    local lastUncertainty
    for _, rumour in ipairs(life.rumours or {}) do
        total = total + 1
        if rumour.shared == true then
            shared = shared + 1
            lastUncertainty = tonumber(rumour.uncertaintyRadius or rumour.accuracy)
                or lastUncertainty
        end
    end
    local mourning
    if type(life.mourning) == "table" and worldHour() < (life.mourning.untilHour or 0) then
        mourning = shallowCopy(life.mourning)
        mourning.hoursRemaining = math.max(0, (life.mourning.untilHour or worldHour()) - worldHour())
    end
    return {
        personality = life.personality.primary .. " / " .. life.personality.secondary,
        personalityPrimary = life.personality.primary,
        personalitySecondary = life.personality.secondary,
        values = shallowCopy(life.personality.values), members = members, relations = relations,
        resources = {
            level = life.resources.level, shortage = life.resources.shortage,
            levels = shallowCopy(life.resources.levels), source = life.resources.source,
        },
        routines = routines,
        representative = {
            state = life.representative.state, memberKey = life.representative.memberKey,
        },
        crisis = life.crisis.active and shallowCopy(life.crisis.active) or nil,
        mourning = mourning,
        crisisHistoryCount = #(life.crisis.history or {}),
        rumoursShared = shared, rumoursTotal = total,
        lastRumourUncertainty = lastUncertainty,
    }
end

function Life.debugSetPersonality(id, primary)
    if SC.Config.get("debugSpawnEnabled") ~= true then return false, "debug_tools_disabled" end
    local group = SC.Factions and SC.Factions.group(id) or nil
    if not group or not personalityDefinitions[primary] then return false, "invalid_personality" end
    local life = Life.initialize(group)
    local secondary = life.personality.secondary
    if secondary == primary then
        local index = (stringHash(id) % #personalityOrder) + 1
        secondary = personalityOrder[index]
        if secondary == primary then secondary = personalityOrder[(index % #personalityOrder) + 1] end
    end
    life.personality = { primary = primary, secondary = secondary, values = {} }
    local left, right = personalityDefinitions[primary], personalityDefinitions[secondary]
    for _, key in ipairs({ "caution", "generosity", "discipline", "solidarity", "openness" }) do
        life.personality.values[key] = math.floor(left[key] * 0.7 + right[key] * 0.3 + 0.5)
    end
    return true, primary
end

function Life.debugTriggerCrisis(id, kind)
    if SC.Config.get("debugSpawnEnabled") ~= true then return false, "debug_tools_disabled" end
    local group = SC.Factions and SC.Factions.group(id) or nil
    if not group then return false, "faction_unavailable" end
    return triggerCrisis(group, kind, true)
end

function Life.debugResolveCrisis(id)
    if SC.Config.get("debugSpawnEnabled") ~= true then return false, "debug_tools_disabled" end
    local group = SC.Factions and SC.Factions.group(id) or nil
    if not group then return false, "faction_unavailable" end
    Life.initialize(group)
    return resolveCrisis(group, "debug_resolved")
end

function Life.debugAdvanceRoutine(id)
    if SC.Config.get("debugSpawnEnabled") ~= true then return false, "debug_tools_disabled" end
    local group = SC.Factions and SC.Factions.group(id) or nil
    if not group then return false, "faction_unavailable" end
    local life = Life.initialize(group)
    local phases = { "sleep", "meal", "organize", "maintenance", "inventory_check",
        "socialize", "read", "watch" }
    local phaseIndex = {}
    for index, phase in ipairs(phases) do phaseIndex[phase] = index end
    local hour, block = worldHour(), math.floor(timeOfDay() * 2) / 2
    life.lastRoutineBlock, life.lastRoutineDay = block, math.floor(hour / 24)
    for index, member in ipairs(group.members or {}) do
        if member.alive ~= false and member.away == nil and member.departed ~= true then
            local current = life.routines[member.key]
            local cursor = ((phaseIndex[current and current.phase] or 0) % #phases) + 1
            life.routines[member.key] = {
                phase = phases[cursor], block = block, sinceHour = hour,
                target = routineTarget(group, index, phases[cursor], block),
            }
        end
    end
    return true, "routines_advanced"
end

function Life.debugAuditResources(id)
    if SC.Config.get("debugSpawnEnabled") ~= true then return false, "debug_tools_disabled" end
    local group = SC.Factions and SC.Factions.group(id) or nil
    if not group then return false, "faction_unavailable" end
    local audited, result = Life.auditResources(group, true)
    return audited, audited and tostring(result.level) or result
end

function Life.debugShareRumour(id, player)
    if SC.Config.get("debugSpawnEnabled") ~= true then return false, "debug_tools_disabled" end
    return Life.shareRumour(id, player, true)
end

function Life.validate(group)
    if type(group) ~= "table" then return false end
    local life = Life.initialize(group)
    if not life or life.schema ~= LIFE_SCHEMA
        or not personalityDefinitions[life.personality.primary]
        or not personalityDefinitions[life.personality.secondary]
        or type(life.relationships) ~= "table" or type(life.routines) ~= "table"
        or type(life.resources) ~= "table" or type(life.representative) ~= "table"
        or type(life.crisis) ~= "table" or type(life.rumours) ~= "table"
        or #life.rumours > 8 or #(life.crisis.history or {}) > 32
        or #(life.events or {}) > 128 then return false end
    local relationCount = 0
    for _, relation in pairs(life.relationships) do
        relationCount = relationCount + 1
        if relationCount > 12 or type(relation) ~= "table"
            or type(relation.left) ~= "string" or type(relation.right) ~= "string" then return false end
    end
    if life.crisis.active and not crisisKinds[life.crisis.active.kind] then return false end
    return true
end

function Life.reset(actor)
    if actor then actorStates[actor] = nil
    else actorStates = setmetatable({}, { __mode = "k" }) end
end

return Life
