-- SPDX-License-Identifier: MIT

local SC = SurvivorCompanion
SC.FactionContracts = SC.FactionContracts or {}

local Contracts = SC.FactionContracts
local SOCIAL_SCHEMA = 2
local actorStates = setmetatable({}, { __mode = "k" })
local zombieHookInstalled = false

local contractKinds = { supply = true, medical = true, local_threat = true }
local complications = {
    "none", "hidden_severity", "diverted_delivery", "rival_objection",
    "broken_reward", "private_dissent",
}
local complicationValues = {}
for _, value in ipairs(complications) do complicationValues[value] = true end
local accessStates = {
    threshold = true, lower_weapon = true, guest = true, denied = true, contested = true,
}

local tones = {
    Paranoid = "Careful answer:", Generous = "Straight answer:",
    Militarized = "Situation report:", Desperate = "We will be honest:",
    Isolationist = "This stays at the gate:", Resourceful = "Here is what matters:",
}

local function U()
    return SC.GameplayUtil
end

local function worldHour()
    if type(getGameTime) == "function" then
        local ok, value = pcall(getGameTime)
        if ok and value then
            local age, called = U().call(value, "getWorldAgeHours")
            if called and tonumber(age) then return tonumber(age) end
        end
    end
    return U().nowMs() / 3600000
end

local function worldDay()
    return math.floor(worldHour() / 24)
end

local function hash(value)
    local result = 5381
    value = tostring(value or "")
    for index = 1, #value do
        result = (result * 33 + string.byte(value, index)) % 2147483647
    end
    return result
end

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, tonumber(value) or minimum))
end

local function configuredLimit(key, fallback, maximum)
    local value = tonumber(SC.Config.get(key))
    if value == nil or value ~= value or value == math.huge or value == -math.huge then
        return fallback
    end
    return math.max(1, math.min(maximum or 4096, math.floor(value)))
end

local function localPlayer()
    if type(getPlayer) ~= "function" then return nil end
    local ok, value = pcall(getPlayer)
    return ok and value or nil
end

local function appendBounded(rows, value, maximum)
    rows[#rows + 1] = value
    while #rows > maximum do table.remove(rows, 1) end
end

local function copy(value, depth, budget)
    budget = budget or { count = 2048 }
    if budget.count <= 0 then return nil end
    local kind = type(value)
    if kind == "string" or kind == "boolean" then
        budget.count = budget.count - 1
        return value
    end
    if kind == "number" then
        if value ~= value or value == math.huge or value == -math.huge then return nil end
        budget.count = budget.count - 1
        return value
    end
    if kind ~= "table" or (depth or 0) <= 0 then return nil end
    budget.count = budget.count - 1
    local result = {}
    for key, child in pairs(value) do
        if type(key) == "string" or type(key) == "number" then
            local childCopy = copy(child, depth - 1, budget)
            if childCopy ~= nil then result[key] = childCopy end
            if budget.count <= 0 then break end
        end
    end
    return result
end

local function groupFor(value)
    if type(value) == "table" then return value end
    return SC.Factions and SC.Factions.group(value) or nil
end

local function livingMembers(group)
    local result = {}
    for _, member in ipairs(group and group.members or {}) do
        if member.alive ~= false and member.away == nil and member.departed ~= true then
            result[#result + 1] = member
        end
    end
    return result
end

local function memberName(member)
    local identity = member and member.identity or {}
    return tostring(identity.forename or "Unknown") .. " "
        .. tostring(identity.surname or "Survivor")
end

local function memberByKey(group, key)
    for _, member in ipairs(group and group.members or {}) do
        if member.key == key then return member end
    end
    return nil
end

local function representative(group)
    local wanted = group.life and group.life.representative
        and group.life.representative.memberKey or nil
    local fallback
    for _, member in ipairs(livingMembers(group)) do
        if member.key == wanted then return member end
        if member.role == "leader" then fallback = member end
        fallback = fallback or member
    end
    return fallback
end

local function recordForMember(member)
    return member and member.actorId and SC.Registry and SC.Registry.byId(member.actorId) or nil
end

local function personality(group)
    return group.life and group.life.personality or {
        primary = "Resourceful", secondary = "Generous",
        values = { caution = 50, generosity = 50, discipline = 50,
            solidarity = 50, openness = 50 },
    }
end

local function highestTensionRelation(group)
    local selected
    for _, relation in pairs(group.life and group.life.relationships or {}) do
        if not selected or (tonumber(relation.tension) or 0)
            > (tonumber(selected.tension) or 0) then selected = relation end
    end
    return selected
end

local function addMemory(group, kind, detail, memberKey)
    local social = group.social
    appendBounded(social.memories, {
        hour = worldHour(), day = worldDay(), kind = kind,
        detail = tostring(detail or ""), memberKey = memberKey,
    }, configuredLimit("factionContractMemoryLimit", 64))
end

local function notify(group, player, kind, message, onceKey)
    local social = group and group.social
    if type(social) ~= "table" then return false end
    social.notifications = type(social.notifications) == "table" and social.notifications or {}
    social.notificationFlags = type(social.notificationFlags) == "table"
        and social.notificationFlags or {}
    social.notificationFlagOrder = type(social.notificationFlagOrder) == "table"
        and social.notificationFlagOrder or {}
    if onceKey and social.notificationFlags[onceKey] == true then return false end
    if onceKey then
        social.notificationFlags[onceKey] = true
        social.notificationFlagOrder[#social.notificationFlagOrder + 1] = onceKey
        while #social.notificationFlagOrder
            > configuredLimit("factionNotificationFlagLimit", 96) do
            local removed = table.remove(social.notificationFlagOrder, 1)
            social.notificationFlags[removed] = nil
        end
    end
    local row = {
        serial = (tonumber(social.notificationSerial) or 0) + 1,
        hour = worldHour(), kind = tostring(kind or "contract"),
        message = tostring(message or "Contract updated."),
    }
    social.notificationSerial = row.serial
    appendBounded(social.notifications, row,
        configuredLimit("factionNotificationLimit", 24))
    if player == nil then player = localPlayer() end
    if player then U().call(player, "setHaloNote", row.message, 238, 196, 82, 300) end
    return true
end

local function addPromise(group, contract, status)
    appendBounded(group.social.promises, {
        id = contract.id, kind = contract.kind, status = status,
        madeHour = contract.acceptedHour, deadlineHour = contract.deadlineHour,
        resolvedHour = status ~= "active" and worldHour() or nil,
    }, configuredLimit("factionContractPromiseLimit", 24))
end

local function relationNames(group, relation)
    if not relation then return "two residents" end
    return memberName(memberByKey(group, relation.left)) .. " and "
        .. memberName(memberByKey(group, relation.right))
end

local function contractTarget(group, serial)
    local anchor = group.house and group.house.anchor or { x = 0, y = 0, z = 0 }
    local seed = hash(group.id .. ":contract-target:" .. tostring(serial))
    local distance = tonumber(SC.Config.get("factionContractTargetDistance")) or 24
    local angle = (seed % 6283) / 1000
    return {
        x = math.floor(anchor.x + math.cos(angle) * distance),
        y = math.floor(anchor.y + math.sin(angle) * distance), z = 0,
    }
end

local function markerPosition(group, contract)
    if contract.kind == "local_threat" and type(contract.target) == "table" then
        return contract.target
    end
    return group.house and group.house.anchor or { x = 0, y = 0, z = 0 }
end

local function ensureContractMarker(group, contract)
    if not contract or contract.status ~= "active" then return false, "contract_not_active" end
    local position = markerPosition(group, contract)
    contract.marker = type(contract.marker) == "table" and contract.marker or {
        text = "[LF Contract] " .. tostring(contract.title or "Household promise")
            .. " @ " .. tostring(math.floor(tonumber(position.x) or 0)) .. ", "
            .. tostring(math.floor(tonumber(position.y) or 0)),
        x = position.x, y = position.y, status = "active",
    }
    contract.marker.x, contract.marker.y, contract.marker.status =
        position.x, position.y, "active"
    if contract.marker.added == true
        and U().nowMs() < (tonumber(contract.marker.nextSyncAt) or 0) then
        return true, "world_map_symbol_recently_synced"
    end
    if SC.FactionLife and type(SC.FactionLife.addMapAnnotation) == "function" then
        local ok, result, detail = pcall(SC.FactionLife.addMapAnnotation,
            contract.marker.text, contract.marker.x, contract.marker.y,
            { 0.94, 0.42, 0.20, 1.0 })
        contract.marker.added = ok and result == true
        contract.marker.lastResult = ok and detail or tostring(result)
        contract.marker.nextSyncAt = U().nowMs() + 60000
        return contract.marker.added, contract.marker.lastResult
    end
    contract.marker.added, contract.marker.lastResult = false, "map_bridge_unavailable"
    return false, contract.marker.lastResult
end

local function closeContractMarker(contract, outcome)
    if not contract or type(contract.marker) ~= "table" then return true end
    contract.marker.status = tostring(outcome or "closed")
    local removed, reason = true, "world_map_symbol_absent"
    if SC.FactionLife and type(SC.FactionLife.removeMapAnnotation) == "function" then
        local ok, result, detail = pcall(SC.FactionLife.removeMapAnnotation,
            contract.marker.text)
        removed, reason = ok and result == true, ok and detail or tostring(result)
    end
    contract.marker.removed, contract.marker.lastResult = removed, reason
    return removed, reason
end

local function supplyRequirements(group)
    if type(group.request) == "table" and type(group.request.required) == "table" then
        return copy(group.request.required, 4, { count = 96 })
    end
    local kind = group.shortageKind or "food"
    if kind == "water" then return { { category = "water", count = 3 } }
    elseif kind == "medicine" then return { {
        label = "clean bandages", count = 3,
        types = { "Base.Bandage", "Base.AlcoholBandage", "Base.RippedSheets" },
    } }
    elseif kind == "tools" then return { { type = "Base.Hammer", count = 1 } }
    elseif kind == "materials" then return { { type = "Base.Plank", count = 4 } }
    elseif kind == "ammunition" then return { { type = "Base.Bullets9mmBox", count = 1 } }
    end
    return { { category = "food", count = 5 } }
end

local function chooseContractKind(group, serial, forcedKind)
    if contractKinds[forcedKind] then return forcedKind end
    local crisis = group.life and group.life.crisis and group.life.crisis.active or nil
    if crisis and crisis.kind == "illness" then return "medical" end
    if crisis and crisis.kind == "supply_collapse" then return "supply" end
    local order = { "supply", "medical", "local_threat" }
    return order[(hash(group.id .. ":contract:" .. tostring(serial)) % #order) + 1]
end

local function chooseComplication(group, kind, serial, forced)
    if complicationValues[forced] then return forced end
    local primary = personality(group).primary
    if primary == "Desperate" and (kind == "supply" or kind == "medical") then
        return "hidden_severity"
    end
    local eligible = { "none", "diverted_delivery", "rival_objection",
        "broken_reward", "private_dissent" }
    if highestTensionRelation(group) == nil then
        eligible = { "none", "broken_reward", "hidden_severity" }
    end
    return eligible[(hash(group.id .. ":complication:" .. tostring(serial)) % #eligible) + 1]
end

local function makeContract(group, forcedKind, forcedComplication)
    local social = group.social
    social.contract.sequence = math.max(0,
        math.floor(tonumber(social.contract.sequence) or 0)) + 1
    local serial = social.contract.sequence
    local kind = chooseContractKind(group, serial, forcedKind)
    local complication = chooseComplication(group, kind, serial, forcedComplication)
    local contract = {
        id = group.id .. ":social:" .. tostring(serial), kind = kind,
        status = "offered", createdHour = worldHour(), revealed = false,
        complication = complication, hiddenSeverity = complication == "hidden_severity",
        reward = { barter = true, access = true, rumour = true,
            safeRest = kind ~= "local_threat", futureRecruitConsideration = true },
        progress = {},
    }
    if kind == "supply" then
        contract.title = "Urgent supply delivery"
        contract.requirements = supplyRequirements(group)
        contract.resource = group.shortageKind or "food"
        contract.progress.delivered = false
    elseif kind == "medical" then
        local members = livingMembers(group)
        local target = members[(hash(group.id .. ":patient:" .. tostring(serial))
            % math.max(1, #members)) + 1]
        contract.title = "Medical help"
        contract.targetMemberKey = target and target.key or nil
        contract.requirements = {
            { label = "clean bandages", count = 2,
                types = { "Base.Bandage", "Base.AlcoholBandage", "Base.RippedSheets" } },
            { label = "disinfectant", count = 1,
                types = { "Base.Disinfectant", "Base.AlcoholWipes" } },
        }
        contract.progress.delivered = false
    else
        contract.title = "Clear a local threat"
        contract.target = contractTarget(group, serial)
        contract.radius = tonumber(SC.Config.get("factionContractThreatRadius")) or 18
        contract.requiredKills = 2 + (hash(contract.id) % 3)
        contract.progress.kills = 0
        contract.progress.visited = false
    end
    local relation = highestTensionRelation(group)
    if complication == "rival_objection" or complication == "private_dissent" then
        contract.rival = relation and copy(relation, 3, { count = 32 }) or nil
    end
    return contract
end

local function ensureOffer(group, forcedKind, forcedComplication)
    local social = group.social
    if type(social) ~= "table" or type(social.contract) ~= "table" then
        social = Contracts.initialize(group)
    end
    if social.contract.active then return social.contract.active end
    local offer = social.contract.offer
    local crisis = group.life and group.life.crisis and group.life.crisis.active or nil
    local crisisKind = crisis and (crisis.kind == "illness" and "medical"
        or crisis.kind == "supply_collapse" and "supply" or nil) or nil
    if forcedKind or forcedComplication or offer == nil
        or (crisisKind and offer.kind ~= crisisKind and offer.status == "offered") then
        offer = makeContract(group, forcedKind or crisisKind, forcedComplication)
        social.contract.offer = offer
    end
    return offer
end

function Contracts.initialize(group)
    if type(group) ~= "table" then return nil, "faction_unavailable" end
    local social = type(group.social) == "table" and group.social or {}
    group.social = social
    social.schema = SOCIAL_SCHEMA
    social.access = type(social.access) == "table" and social.access or {
        state = "threshold", reason = "not_invited", invitedUntilHour = 0,
        hostMemberKey = nil, objectorMemberKey = nil, safeRest = false,
    }
    social.contract = type(social.contract) == "table" and social.contract or {
        sequence = 0, offer = nil, active = nil, history = {}, cooldownUntilHour = 0,
    }
    social.contract.history = type(social.contract.history) == "table"
        and social.contract.history or {}
    social.memories = type(social.memories) == "table" and social.memories or {}
    social.promises = type(social.promises) == "table" and social.promises or {}
    social.dialogue = type(social.dialogue) == "table" and social.dialogue or {
        lastTopic = nil, lastResponse = nil, lastSpeakerKey = nil,
    }
    social.trade = type(social.trade) == "table" and social.trade or {
        favor = 0, debt = 0, completedContracts = 0, brokenPromises = 0,
    }
    social.notifications = type(social.notifications) == "table" and social.notifications or {}
    social.notificationFlags = type(social.notificationFlags) == "table"
        and social.notificationFlags or {}
    social.notificationFlagOrder = type(social.notificationFlagOrder) == "table"
        and social.notificationFlagOrder or {}
    social.notificationSerial = math.max(0, math.floor(tonumber(social.notificationSerial) or 0))
    social.privateContact = type(social.privateContact) == "table"
        and social.privateContact or nil
    if group.lifecycle ~= "destroyed" and #livingMembers(group) > 0 then ensureOffer(group) end
    return social
end

local function canTalk(group, player, forced)
    if forced == true then return true, nil end
    if group.standing == "Hostile" or group.lifecycle == "hostile" then
        return false, "faction_hostile"
    end
    if SC.FactionLife and type(SC.FactionLife.canTalk) == "function" then
        return SC.FactionLife.canTalk(group, player)
    end
    return false, "representative_unavailable"
end

function Contracts.canTalk(groupOrId, player)
    local group = groupFor(groupOrId)
    if not group then return false, "faction_unavailable" end
    return canTalk(group, player, false)
end

local function rememberDialogue(group, topic, response, speakerKey, private)
    local dialogue = group.social.dialogue
    dialogue.lastTopic, dialogue.lastResponse = topic, tostring(response or "")
    dialogue.lastSpeakerKey, dialogue.lastHour = speakerKey, worldHour()
    dialogue.private = private == true
    addMemory(group, private and "private_conversation" or "conversation",
        topic .. ": " .. tostring(response or ""), speakerKey)
end

local function toneFor(group, actor)
    local primary = personality(group).primary
    local fallback = tones[primary] or "Straight answer:"
    if actor and SC.Dialogue and type(SC.Dialogue.choose) == "function" then
        local line = SC.Dialogue.choose(actor, "faction.tone." .. tostring(primary),
            nil, nil, { fallback = fallback })
        if type(line) == "string" and line ~= "" then return line end
    end
    return fallback
end

local function visibleOfferText(group, offer)
    if offer.hiddenSeverity and group.standing ~= "Trusted" and offer.status == "offered" then
        return "We need a few things. It is better if we do not discuss the details out here."
    end
    if offer.kind == "supply" then
        return "Our " .. tostring(offer.resource or "supply")
            .. " stock is failing. We need a delivery before it becomes a disaster."
    elseif offer.kind == "medical" then
        local patient = memberName(memberByKey(group, offer.targetMemberKey))
        return patient .. " is ill. We need clean bandages and disinfectant."
    end
    return "There is a dangerous pocket of dead near " .. tostring(offer.target.x)
        .. ", " .. tostring(offer.target.y) .. ". We need someone to make it safe."
end

function Contracts.tradePolicy(groupOrId)
    local group = groupFor(groupOrId)
    if not group then return nil, "faction_unavailable" end
    local social = Contracts.initialize(group)
    local primary = personality(group).primary
    local markup = group.standing == "Trusted" and 1.0
        or group.standing == "Tolerated" and 1.2 or 1.4
    if primary == "Generous" then markup = markup - 0.08
    elseif primary == "Isolationist" then markup = markup + 0.15
    elseif primary == "Desperate" then markup = markup + 0.1
    elseif primary == "Resourceful" then markup = markup - 0.04 end
    markup = clamp(markup - math.min(0.15, (tonumber(social.trade.favor) or 0) / 200), 1, 1.65)
    local refused, refusedReasons, reasons = {}, {}, {}
    local levels = group.life and group.life.resources and group.life.resources.levels or {}
    for category, level in pairs(levels or {}) do
        if level == "Critical" then
            refused[category] = true
            refusedReasons[category] = "critical household stock"
        end
    end
    if primary == "Militarized" then
        refused.ammunition, refused.weapon = true, true
        refusedReasons.ammunition, refusedReasons.weapon =
            "militarized household reserve", "militarized household reserve"
    end
    local crisis = group.life and group.life.crisis and group.life.crisis.active or nil
    if crisis and crisis.kind == "illness" then
        refused.medicine = true
        refusedReasons.medicine = "active illness"
    end
    for category, _ in pairs(refused) do reasons[#reasons + 1] = category end
    table.sort(reasons)
    return {
        markup = markup, refused = refused, refusedReasons = refusedReasons,
        refusalText = #reasons > 0 and table.concat(reasons, ", ") or "none",
        counterOffers = true,
    }
end

local function membersResponse(group)
    local relation = highestTensionRelation(group)
    if relation and (tonumber(relation.tension) or 0) >= 45 then
        return relationNames(group, relation) .. " do not agree about recent decisions."
    end
    local names = {}
    for _, member in ipairs(livingMembers(group)) do names[#names + 1] = memberName(member) end
    return "We are " .. table.concat(names, ", ") .. ". We make decisions as a household."
end

local function dangerResponse(group, offer)
    if offer.kind == "local_threat" then return visibleOfferText(group, offer) end
    local crisis = group.life and group.life.crisis and group.life.crisis.active or nil
    if crisis then return "Our immediate danger is the " .. tostring(crisis.kind)
        .. " inside this house." end
    for _, rumour in ipairs(group.life and group.life.rumours or {}) do
        if rumour.kind == "horde" then
            return "We heard about a horde near " .. tostring(rumour.x) .. ", "
                .. tostring(rumour.y) .. ", but the report may be wrong."
        end
    end
    return "Nothing specific. That does not mean the roads are safe."
end

function Contracts.talk(groupOrId, player, topic, forced)
    local group = groupFor(groupOrId)
    if not group then return false, "faction_unavailable" end
    local ready, reason = canTalk(group, player, forced)
    if not ready then return false, reason end
    local social = Contracts.initialize(group)
    local offer = ensureOffer(group)
    topic = tostring(topic or "status")
    local speaker = representative(group)
    local speakerKey = speaker and speaker.key or nil
    local response
    if topic == "needs" then
        offer.revealed = true
        response = visibleOfferText(group, offer)
    elseif topic == "members" then response = membersResponse(group)
    elseif topic == "trade" then
        local policy = Contracts.tradePolicy(group)
        response = "Current markup is " .. tostring(math.floor(policy.markup * 100 + 0.5))
            .. "%. Reserved categories: " .. policy.refusalText .. "."
    elseif topic == "danger" then response = dangerResponse(group, offer)
    elseif topic == "rumours" then
        local shared, detail = false, "rumour_unavailable"
        if SC.FactionLife and type(SC.FactionLife.shareRumour) == "function" then
            shared, detail = SC.FactionLife.shareRumour(group, player, forced == true)
        end
        response = shared and ("I marked it on your map: " .. tostring(detail) .. ".")
            or ("No useful map lead right now: " .. tostring(detail) .. ".")
    elseif topic == "access" then
        local record = recordForMember(memberByKey(group, speakerKey))
        if record and record.actor and SC.Dialogue and type(SC.Dialogue.choose) == "function" then
            response = SC.Dialogue.choose(record.actor, "faction.access", nil, nil,
                { fallback = "Ask clearly and keep your weapon lowered. The household will decide." })
        else
            response = "Ask clearly and keep your weapon lowered. The household will decide."
        end
    elseif topic == "private" then
        local contact = social.privateContact
        if not contact or contact.available ~= true then return false, "no_private_contact" end
        contact.available, contact.delivered, contact.deliveredHour = false, true, worldHour()
        speakerKey = contact.memberKey
        response = contact.message
    elseif topic == "status" then
        local mourning = group.life and group.life.mourning or nil
        local record = recordForMember(memberByKey(group, speakerKey))
        local actor = record and record.actor or nil
        if mourning and worldHour() < (tonumber(mourning.untilHour) or 0) then
            local subject = tostring(mourning.subjectName or "someone from this house")
            response = SC.Dialogue and type(SC.Dialogue.choose) == "function"
                and SC.Dialogue.choose(actor, "faction.status.mourning", nil, { subject },
                    { fallback = "We lost %1. We are keeping watch, but give us time to grieve." })
                or ("We lost " .. subject .. ". We are keeping watch, but give us time to grieve.")
        else
            local standing = string.lower(tostring(group.standing or "wary"))
            local supplies = string.lower(tostring(group.life and group.life.resources.level or "uncertain"))
            response = SC.Dialogue and type(SC.Dialogue.choose) == "function"
                and SC.Dialogue.choose(actor, "faction.status.normal", nil,
                    { standing, supplies }, { fallback = "We are %1 toward you. Supplies are %2." })
                or ("We are " .. standing .. " toward you. Supplies are " .. supplies .. ".")
        end
    else return false, "unknown_conversation_topic" end
    local record = recordForMember(memberByKey(group, speakerKey))
    response = toneFor(group, record and record.actor or nil) .. " " .. response
    rememberDialogue(group, topic, response, speakerKey, topic == "private")
    if record and record.actor then U().say(record.actor, response) end
    return true, response
end

function Contracts.accept(groupOrId, player, forced)
    local group = groupFor(groupOrId)
    if not group then return false, "faction_unavailable" end
    local ready, reason = canTalk(group, player, forced)
    if not ready then return false, reason end
    local social = Contracts.initialize(group)
    if social.contract.active then return false, "one_contract_already_active" end
    local offer = ensureOffer(group)
    if not offer.revealed and forced ~= true then return false, "ask_about_need_first" end
    social.contract.offer = nil
    social.contract.active = offer
    offer.status, offer.acceptedHour = "active", worldHour()
    offer.deadlineHour = offer.acceptedHour
        + (tonumber(SC.Config.get("factionContractDeadlineHours")) or 48)
    addPromise(group, offer, "active")
    addMemory(group, "promise_made", offer.kind, nil)
    ensureContractMarker(group, offer)
    notify(group, player, "accepted", "Contract accepted: " .. tostring(offer.title) .. ".",
        offer.id .. ":accepted")
    if offer.complication == "private_dissent" then
        local relation = offer.rival or highestTensionRelation(group)
        local memberKey = relation and relation.right
            or livingMembers(group)[2] and livingMembers(group)[2].key or nil
        if memberKey then
            social.privateContact = {
                available = true, delivered = false, memberKey = memberKey,
                message = "Do not trust the deal exactly as it was presented. Someone here disagrees.",
                contractId = offer.id,
            }
        end
    end
    return true, offer.kind .. "_contract_accepted"
end

local function threatsNear(position, radius)
    local count, visited = 0, {}
    radius = math.max(1, math.floor(tonumber(radius) or 12))
    local squareBudget = math.min(625, (radius * 2 + 1) * (radius * 2 + 1))
    local scanned = 0
    for dx = -radius, radius do
        for dy = -radius, radius do
            if scanned >= squareBudget then return count, scanned end
            if dx * dx + dy * dy <= radius * radius then
                local square = U().gridSquare(position.x + dx, position.y + dy, position.z or 0)
                if square then
                    scanned = scanned + 1
                    U().squareMovingObjects(square, function(value)
                        if U().isZombie(value) and not U().isDead(value) and not visited[value] then
                            visited[value], count = true, count + 1
                        end
                    end, 24)
                end
            end
        end
    end
    return count, scanned
end

local function deadlineProgress(contract)
    if not contract or contract.status ~= "active" then return nil end
    local remaining = (tonumber(contract.deadlineHour) or worldHour()) - worldHour()
    local urgency = remaining <= 0 and "expired" or remaining <= 3 and "critical"
        or remaining <= 12 and "due_soon" or "normal"
    return math.max(0, remaining), urgency
end

function Contracts.progress(groupOrId, player, scanThreat)
    local group = groupFor(groupOrId)
    if not group then return nil, "faction_unavailable" end
    local social = Contracts.initialize(group)
    local contract = social.contract.active or social.contract.offer
    if not contract then return nil, "contract_unavailable" end
    local result = {
        id = contract.id, kind = contract.kind, status = contract.status,
        ready = false, requirements = {}, marker = copy(contract.marker, 3, { count = 32 }),
    }
    result.hoursRemaining, result.urgency = deadlineProgress(contract)
    if contract.kind == "local_threat" then
        result.kills = tonumber(contract.progress and contract.progress.kills) or 0
        result.requiredKills = tonumber(contract.requiredKills) or 0
        result.remainingThreats = tonumber(contract.progress and contract.progress.lastScanCount)
        result.loadedSquares = tonumber(contract.progress and contract.progress.loadedSquares) or 0
        result.minimumLoadedSquares = tonumber(SC.Config.get(
            "factionContractThreatMinLoadedSquares")) or 64
        if scanThreat == true and player and U().distance(player, contract.target)
            <= math.min(12, tonumber(contract.radius) or 18) then
            result.remainingThreats, result.loadedSquares = threatsNear(
                contract.target, contract.radius)
            contract.progress.lastScanCount = result.remainingThreats
            contract.progress.loadedSquares = result.loadedSquares
            contract.progress.lastScanHour = worldHour()
        end
        result.areaLoaded = result.loadedSquares >= result.minimumLoadedSquares
        result.ready = contract.status == "active" and result.areaLoaded
            and result.kills >= result.requiredKills and result.remainingThreats == 0
        return result
    end
    if player == nil then player = localPlayer() end
    if player and SC.Trade and type(SC.Trade.previewRequirements) == "function" then
        local rows, ready, reason = SC.Trade.previewRequirements(player,
            contract.requirements, false)
        result.requirements, result.ready, result.reason = rows or {}, ready == true, reason
    else
        for index, requirement in ipairs(contract.requirements or {}) do
            result.requirements[index] = {
                index = index, label = requirement.label or requirement.type
                    or requirement.category or "item",
                required = tonumber(requirement.count) or 0, available = 0,
                remaining = tonumber(requirement.count) or 0, ready = false,
            }
        end
        result.reason = "player_inventory_unavailable"
    end
    return result
end

local function resolveLifeCrisis(group, kind)
    if SC.FactionLife and type(SC.FactionLife.resolveCrisis) == "function" then
        local expected = kind == "medical" and "illness"
            or kind == "supply" and "supply_collapse" or nil
        if expected then pcall(SC.FactionLife.resolveCrisis, group, "player_help", expected) end
    end
end

local function completeContract(group, contract, forced)
    local social = group.social
    contract.status, contract.completedHour = "completed", worldHour()
    local complication = contract.complication
    if complication == "diverted_delivery" then
        contract.outcome = "part_of_delivery_diverted"
        local relation = highestTensionRelation(group)
        if relation then relation.tension = clamp((relation.tension or 0) + 15, 0, 100) end
        addMemory(group, "delivery_diverted", "A resident hid part of the delivery.",
            relation and relation.right or nil)
    elseif complication == "rival_objection" then
        contract.outcome = "invitation_contested"
        local relation = contract.rival or highestTensionRelation(group)
        social.access.state, social.access.reason = "contested", "resident_objected"
        social.access.hostMemberKey = representative(group) and representative(group).key or nil
        social.access.objectorMemberKey = relation and relation.right or nil
        social.access.invitedUntilHour = worldHour()
            + (tonumber(SC.Config.get("factionGuestAccessHours")) or 12)
        addMemory(group, "access_contested", relationNames(group, relation),
            social.access.objectorMemberKey)
    elseif complication == "broken_reward" then
        contract.outcome = "promised_payment_unavailable"
        social.trade.debt = clamp((social.trade.debt or 0) + 25, 0, 200)
        addMemory(group, "reward_unpaid", "The household could not honor its full promise.")
    else contract.outcome = "agreement_honored" end
    if complication ~= "rival_objection" then
        social.access.state, social.access.reason = "guest", "contract_completed"
        social.access.hostMemberKey = representative(group) and representative(group).key or nil
        social.access.objectorMemberKey = nil
        social.access.invitedUntilHour = worldHour()
            + (tonumber(SC.Config.get("factionGuestAccessHours")) or 12)
        social.access.safeRest = contract.reward.safeRest == true
    end
    social.trade.completedContracts = (tonumber(social.trade.completedContracts) or 0) + 1
    social.trade.favor = clamp((social.trade.favor or 0) + 20, 0, 100)
    social.trade.futureRecruitConsideration = contract.reward.futureRecruitConsideration == true
    social.trade.futureRecruitCandidate = social.trade.completedContracts >= 2
    group.barterUnlocked = true
    if type(group.request) == "table" and group.request.status == "available" then
        group.request.status, group.request.rewardReserved = "superseded", false
    end
    if SC.Factions and type(SC.Factions.adjustStanding) == "function" then
        pcall(SC.Factions.adjustStanding, group.id, complication == "broken_reward" and 18 or 28,
            "social_contract_completed")
    end
    resolveLifeCrisis(group, contract.kind)
    addMemory(group, "contract_completed", contract.kind)
    closeContractMarker(contract, "completed")
    notify(group, nil, "completed", "Contract completed: " .. tostring(contract.title) .. ".",
        contract.id .. ":completed")
    for index = #(social.promises or {}), 1, -1 do
        if social.promises[index].id == contract.id and social.promises[index].status == "active" then
            social.promises[index].status = "kept"
            social.promises[index].resolvedHour = worldHour()
            break
        end
    end
    appendBounded(social.contract.history, copy(contract, 6, { count = 512 }),
        configuredLimit("factionContractHistoryLimit", 32))
    social.contract.active = nil
    social.contract.cooldownUntilHour = worldHour()
        + (tonumber(SC.Config.get("factionContractCooldownHours")) or 24)
    if contract.reward.rumour and SC.FactionLife and type(SC.FactionLife.shareRumour) == "function"
        and forced ~= true then
        local player = localPlayer()
        if player then pcall(SC.FactionLife.shareRumour, group, player, false) end
    end
    return true, contract.outcome
end

function Contracts.fulfill(groupOrId, player, forced)
    local group = groupFor(groupOrId)
    if not group then return false, "faction_unavailable" end
    local social = Contracts.initialize(group)
    local contract = social.contract.active
    if not contract then return false, "no_active_contract" end
    if forced ~= true then
        local ready, reason = canTalk(group, player, false)
        if contract.kind ~= "local_threat" and not ready then return false, reason end
    end
    if forced ~= true and contract.kind ~= "local_threat" then
        if not SC.Trade or type(SC.Trade.deliverRequirements) ~= "function" then
            return false, "trade_unavailable"
        end
        local delivered, reason, receipt = SC.Trade.deliverRequirements(
            group, player, contract.requirements)
        if not delivered then return false, reason end
        contract.progress.delivered = true
        contract.progress.receipt = receipt
    elseif forced ~= true then
        if U().distance(player, contract.target) > math.min(12, contract.radius) then
            return false, "travel_to_reported_area"
        end
        contract.progress.visited = true
        local remaining, scanned = threatsNear(contract.target, contract.radius)
        contract.progress.lastScanCount, contract.progress.loadedSquares,
            contract.progress.lastScanHour = remaining, scanned, worldHour()
        local minimumLoaded = tonumber(SC.Config.get(
            "factionContractThreatMinLoadedSquares")) or 64
        if scanned < minimumLoaded then return false, "reported_area_not_fully_loaded" end
        if remaining > 0 or (tonumber(contract.progress.kills) or 0) < contract.requiredKills then
            return false, "danger_remains:" .. tostring(remaining)
        end
    else
        if contract.kind == "local_threat" then
            contract.progress.visited = true
            contract.progress.kills = contract.requiredKills
        else contract.progress.delivered = true end
    end
    return completeContract(group, contract, forced)
end

function Contracts.withdraw(groupOrId, player, forced)
    local group = groupFor(groupOrId)
    if not group then return false, "faction_unavailable" end
    local social = Contracts.initialize(group)
    local contract = social.contract.active
    if not contract then return false, "no_active_contract" end
    if forced ~= true then
        local ready, reason = canTalk(group, player, false)
        if not ready then return false, reason end
    end
    contract.status, contract.failedHour, contract.outcome = "failed", worldHour(), "promise_withdrawn"
    closeContractMarker(contract, "withdrawn")
    appendBounded(social.contract.history, copy(contract, 6, { count = 512 }),
        configuredLimit("factionContractHistoryLimit", 32))
    social.contract.active = nil
    social.contract.cooldownUntilHour = worldHour()
        + (tonumber(SC.Config.get("factionContractCooldownHours")) or 24)
    social.trade.brokenPromises = (tonumber(social.trade.brokenPromises) or 0) + 1
    social.access.state, social.access.reason = "denied", "promise_broken"
    addMemory(group, "promise_broken", contract.kind)
    notify(group, player, "withdrawn", "Promise withdrawn: " .. tostring(contract.title) .. ".",
        contract.id .. ":withdrawn")
    if SC.Factions then pcall(SC.Factions.adjustStanding, group.id, -12, "promise_broken") end
    return true, "promise_withdrawn"
end

function Contracts.requestAccess(groupOrId, player, forced)
    local group = groupFor(groupOrId)
    if not group then return false, "faction_unavailable" end
    local ready, reason = canTalk(group, player, forced)
    if not ready then return false, reason end
    local social = Contracts.initialize(group)
    local aiming, aimingOk = U().call(player, "isAiming")
    if forced ~= true and aimingOk and aiming == true then
        social.access.state, social.access.reason = "lower_weapon", "lower_weapon_required"
        addMemory(group, "weapon_demand", "The visitor was told to lower their weapon.")
        return false, "lower_weapon_required"
    end
    if social.access.state == "contested" then return false, "invitation_contested" end
    local completed = tonumber(social.trade.completedContracts) or 0
    local open = tonumber(personality(group).values.openness) or 50
    if forced == true or group.standing == "Trusted"
        or group.standing == "Tolerated" and completed >= 1
        or group.standing == "Tolerated" and open >= 70 then
        social.access.state, social.access.reason = "guest", "invited"
        social.access.hostMemberKey = representative(group) and representative(group).key or nil
        social.access.objectorMemberKey = nil
        social.access.invitedUntilHour = worldHour()
            + (tonumber(SC.Config.get("factionGuestAccessHours")) or 12)
        social.access.safeRest = completed >= 1
        addMemory(group, "access_granted", "The visitor was invited inside.")
        return true, "guest_access_granted"
    end
    social.access.state, social.access.reason = "denied", "trust_too_low"
    addMemory(group, "access_denied", "The visitor was kept outside.")
    return false, "trust_too_low"
end

function Contracts.resolveAccessDispute(groupOrId, player, choice, forced)
    local group = groupFor(groupOrId)
    if not group then return false, "faction_unavailable" end
    local ready, reason = canTalk(group, player, forced)
    if not ready then return false, reason end
    local social = Contracts.initialize(group)
    if social.access.state ~= "contested" then return false, "no_access_dispute" end
    if choice == "respect_boundary" then
        social.access.state, social.access.reason = "denied", "visitor_respected_objection"
        social.access.invitedUntilHour, social.access.safeRest = 0, false
        social.trade.favor = clamp((social.trade.favor or 0) + 5, 0, 100)
        addMemory(group, "objection_respected", "The visitor stayed outside.")
        return true, "boundary_respected"
    end
    if choice == "appeal" and (group.standing == "Trusted"
        or (tonumber(social.trade.completedContracts) or 0) >= 2 or forced == true) then
        social.access.state, social.access.reason = "guest", "household_overruled_objection"
        social.access.safeRest = true
        addMemory(group, "objection_overruled", "The household honored the invitation.")
        return true, "guest_access_granted"
    end
    social.access.state, social.access.reason = "denied", "appeal_rejected"
    social.access.invitedUntilHour, social.access.safeRest = 0, false
    addMemory(group, "appeal_rejected", "The household sided with the objector.")
    return false, "appeal_rejected"
end

function Contracts.hasAccess(groupOrId, player)
    local group = groupFor(groupOrId)
    if not group then return false end
    local access = Contracts.initialize(group).access
    if group.standing == "Hostile" or group.lifecycle == "hostile" then
        access.state, access.reason, access.safeRest = "denied", "hostile", false
        access.invitedUntilHour = 0
        return false
    end
    if access.state == "guest" and worldHour() <= (tonumber(access.invitedUntilHour) or 0) then
        return true
    end
    if access.state == "guest" then
        access.state, access.reason, access.safeRest = "threshold", "invitation_expired", false
    end
    return false
end

function Contracts.safeRestStatus(groupOrId, player)
    local group = groupFor(groupOrId)
    if not group then return false, "faction_unavailable" end
    local social = Contracts.initialize(group)
    if not Contracts.hasAccess(group, player) then return false, "house_access_required" end
    if social.access.safeRest ~= true then return false, "safe_rest_not_granted" end
    local aiming, aimingOk = U().call(player, "isAiming")
    if aimingOk and aiming == true then return false, "lower_weapon_required" end
    local x, y = U().position(player)
    local bounds = group.house and group.house.bounds or nil
    if not x or not bounds or x < tonumber(bounds.x1) or x > tonumber(bounds.x2)
        or y < tonumber(bounds.y1) or y > tonumber(bounds.y2) then
        return false, "enter_house_to_rest"
    end
    return true, "safe_rest_available"
end

function Contracts.noteAction(groupOrId, kind, detail)
    local group = groupFor(groupOrId)
    if not group then return false, "faction_unavailable" end
    Contracts.initialize(group)
    kind = tostring(kind or "unknown")
    local memoryKind = kind == "aim" and "threat" or kind
    addMemory(group, memoryKind, detail or kind)
    if kind == "theft" or kind == "aim" or kind == "damage"
        or kind == "barricade" or kind == "murder" then
        group.social.access.state, group.social.access.reason = "denied", kind
        group.social.access.invitedUntilHour, group.social.access.safeRest = 0, false
    end
    if kind == "fair_trade" then
        group.social.trade.favor = clamp((tonumber(group.social.trade.favor) or 0) + 2, 0, 100)
    elseif kind == "help" or kind == "request_completed" then
        group.social.trade.favor = clamp((tonumber(group.social.trade.favor) or 0) + 8, 0, 100)
    end
    return true, "action_remembered"
end

local function closeContractWithoutBlame(group, contract, outcome, message)
    if not contract then return end
    contract.status, contract.failedHour, contract.outcome = "failed", worldHour(), outcome
    closeContractMarker(contract, outcome)
    appendBounded(group.social.contract.history, copy(contract, 6, { count = 512 }),
        configuredLimit("factionContractHistoryLimit", 32))
    for index = #(group.social.promises or {}), 1, -1 do
        local promise = group.social.promises[index]
        if promise.id == contract.id and promise.status == "active" then
            promise.status, promise.resolvedHour = outcome, worldHour()
            break
        end
    end
    group.social.contract.active = nil
    group.social.contract.cooldownUntilHour = worldHour() + 12
    addMemory(group, outcome, message)
    notify(group, nil, "closed", message, contract.id .. ":" .. outcome)
end

function Contracts.memberDied(groupOrId, memberOrActorId)
    local group = groupFor(groupOrId)
    if not group then return false, "faction_unavailable" end
    local social = Contracts.initialize(group)
    local deadMember
    for _, member in ipairs(group.members or {}) do
        if member.key == memberOrActorId or member.actorId == memberOrActorId then
            deadMember = member
            break
        end
    end
    local alive = livingMembers(group)
    if #alive == 0 or group.lifecycle == "destroyed" then
        closeContractWithoutBlame(group, social.contract.active, "household_destroyed",
            "The household is gone. Its contract has ended.")
        social.contract.offer, social.privateContact = nil, nil
        social.access.state, social.access.reason, social.access.safeRest =
            "denied", "household_destroyed", false
        social.access.invitedUntilHour = 0
        return true, "household_contracts_closed"
    end
    local active = social.contract.active
    if active and active.kind == "medical" and deadMember
        and active.targetMemberKey == deadMember.key then
        closeContractWithoutBlame(group, active, "patient_died",
            "The patient died before medical help could arrive.")
    end
    local offer = social.contract.offer
    if offer and offer.kind == "medical" and deadMember
        and offer.targetMemberKey == deadMember.key then
        social.contract.offer = nil
        ensureOffer(group, "medical", offer.complication)
    end
    if deadMember and (social.access.hostMemberKey == deadMember.key
        or social.access.objectorMemberKey == deadMember.key) then
        social.access.state, social.access.reason, social.access.safeRest =
            "threshold", "household_membership_changed", false
        social.access.hostMemberKey, social.access.objectorMemberKey = nil, nil
        social.access.invitedUntilHour = 0
    end
    return true, "member_death_reconciled"
end

local function failExpiredContract(group, contract)
    contract.status, contract.failedHour, contract.outcome = "failed", worldHour(), "promise_expired"
    closeContractMarker(contract, "expired")
    local social = group.social
    appendBounded(social.contract.history, copy(contract, 6, { count = 512 }),
        configuredLimit("factionContractHistoryLimit", 32))
    social.contract.active = nil
    social.contract.cooldownUntilHour = worldHour()
        + (tonumber(SC.Config.get("factionContractCooldownHours")) or 24)
    social.trade.brokenPromises = (tonumber(social.trade.brokenPromises) or 0) + 1
    social.access.state, social.access.reason = "denied", "promise_expired"
    addMemory(group, "promise_broken", "The promised help never arrived.")
    notify(group, nil, "expired", "Contract expired: " .. tostring(contract.title) .. ".",
        contract.id .. ":expired")
    if SC.Factions then pcall(SC.Factions.adjustStanding, group.id, -15, "promise_expired") end
end

function Contracts.pulseGroup(group, player, current)
    local social = Contracts.initialize(group)
    current = tonumber(current) or U().nowMs()
    if current < (tonumber(social.nextPulseAt) or 0) then return true, "contract_pulse_throttled" end
    social.nextPulseAt = current + (tonumber(SC.Config.get("factionContractPulseIntervalMs")) or 2500)
    if social.access.state == "guest"
        and worldHour() > (tonumber(social.access.invitedUntilHour) or 0) then
        social.access.state, social.access.reason, social.access.safeRest =
            "threshold", "invitation_expired", false
    end
    local active = social.contract.active
    if active and worldHour() > (tonumber(active.deadlineHour) or math.huge) then
        failExpiredContract(group, active)
    elseif active then
        ensureContractMarker(group, active)
        local hours, urgency = deadlineProgress(active)
        if urgency == "critical" then
            notify(group, player, "deadline", "Contract deadline is under 3 hours away.",
                active.id .. ":deadline_critical")
        elseif urgency == "due_soon" then
            notify(group, player, "deadline", "Contract deadline is under 12 hours away.",
                active.id .. ":deadline_soon")
        end
        if active.kind ~= "local_threat" and player then
            local progress = Contracts.progress(group, player, false)
            local available, required = 0, 0
            for _, row in ipairs(progress and progress.requirements or {}) do
                available = available + math.min(tonumber(row.available) or 0,
                    tonumber(row.required) or 0)
                required = required + (tonumber(row.required) or 0)
            end
            if active.progress.lastAvailable ~= nil
                and active.progress.lastAvailable ~= available then
                notify(group, player, "progress", "Delivery progress: "
                    .. tostring(available) .. "/" .. tostring(required)
                    .. " required items ready.", active.id .. ":delivery:" .. tostring(available))
            end
            if progress and progress.ready then
                notify(group, player, "progress", "All contract goods are ready to deliver.",
                    active.id .. ":delivery_ready")
            end
            active.progress.lastAvailable, active.progress.requiredItems = available, required
        end
    elseif not active and social.contract.offer == nil
        and worldHour() >= (tonumber(social.contract.cooldownUntilHour) or 0) then
        ensureOffer(group)
    end
    return true, "social_contract_updated"
end

function Contracts.onZombieDead(zombie)
    if zombie == nil then return end
    local attacker, attackerOk = U().call(zombie, "getAttackedBy")
    local player = localPlayer()
    if not attackerOk or attacker ~= player then return end
    for _, group in ipairs(SC.Factions and SC.Factions.list(false) or {}) do
        local active = group.social and group.social.contract and group.social.contract.active or nil
        if active and active.kind == "local_threat" and active.status == "active"
            and U().distance(zombie, active.target) <= (tonumber(active.radius) or 18) then
            active.progress.kills = math.min(active.requiredKills,
                (tonumber(active.progress.kills) or 0) + 1)
            addMemory(group, "local_threat_kill", tostring(active.progress.kills)
                .. "/" .. tostring(active.requiredKills))
            notify(group, player, "progress", "Local threat progress: "
                .. tostring(active.progress.kills) .. "/"
                .. tostring(active.requiredKills) .. " confirmed kills.",
                active.id .. ":kill:" .. tostring(active.progress.kills))
        end
    end
end

function Contracts.installHooks()
    if zombieHookInstalled then return true end
    local configured, configuredReason = Contracts.validateConfiguration()
    if not configured then return false, configuredReason end
    if type(Events) ~= "table" or not Events.OnZombieDead
        or type(Events.OnZombieDead.Add) ~= "function" then
        return false, "OnZombieDead event is unavailable"
    end
    local ok, reason = pcall(Events.OnZombieDead.Add, Contracts.onZombieDead)
    if not ok then return false, tostring(reason) end
    zombieHookInstalled = true
    return true
end

function Contracts.removeHooks()
    if not zombieHookInstalled then return true end
    if type(Events) ~= "table" or not Events.OnZombieDead
        or type(Events.OnZombieDead.Remove) ~= "function" then
        return false, "OnZombieDead removal is unavailable"
    end
    local ok, reason = pcall(Events.OnZombieDead.Remove, Contracts.onZombieDead)
    if not ok then return false, tostring(reason) end
    zombieHookInstalled = false
    return true
end

function Contracts.hooksInstalled()
    return zombieHookInstalled
end

local function actorState(actor)
    local state = actorStates[actor]
    if not state then
        state = { nextSpeechAt = 0, nextPoseAt = 0 }
        actorStates[actor] = state
    end
    return state
end

local function actorMember(group, actor)
    local id = U().idOf(actor)
    for _, member in ipairs(group.members or {}) do
        if member.actorId == id then return member end
    end
    return nil
end

function Contracts.intentFor(actor, group, player)
    local social = Contracts.initialize(group)
    local contact = social.privateContact
    if not contact or contact.available ~= true or group.discovered ~= true
        or group.standing == "Hostile" then return nil end
    local member = actorMember(group, actor)
    if not member or member.key ~= contact.memberKey then return nil end
    local outer = tonumber(SC.Config.get("factionPrivateContactRadius")) or 14
    if U().distance(player, group.house and group.house.anchor) > outer + 20 then return nil end
    return { priority = 64, mode = "contract_private_contact", memberKey = member.key }
end

function Contracts.updateActor(actor, player, runtime, intent, group)
    local contact = group.social and group.social.privateContact or nil
    if not contact or contact.available ~= true then return false, "private_contact_unavailable" end
    local distance = U().distance(actor, player)
    if distance > 2.4 then
        local square = U().squareOf(player)
        if square and SC.Navigation then
            return SC.Navigation.request(actor, square, "walk", {
                action = "faction_private_contact", targetSquare = square,
            })
        end
        return false, "private_contact_path_unavailable"
    end
    U().stop(actor)
    local state, current = actorState(actor), U().nowMs()
    if current >= state.nextSpeechAt then
        state.nextSpeechAt = current + 30000
        U().say(actor, contact.message)
        contact.available, contact.delivered, contact.deliveredHour = false, true, worldHour()
        rememberDialogue(group, "private", toneFor(group, actor) .. " " .. contact.message,
            contact.memberKey, true)
    end
    if current >= state.nextPoseAt then
        state.nextPoseAt = current + 10000
        return U().move(actor, "walk", {
            action = "conversation_pose", target = player, targetPosition = player,
            emote = "undecided",
        })
    end
    return true, "private_contact_delivered"
end

function Contracts.summary(groupOrId)
    local group = groupFor(groupOrId)
    if not group then return nil end
    local social = Contracts.initialize(group)
    local offer = social.contract.offer
    local active = social.contract.active
    local current = active or offer
    local response = social.dialogue.lastResponse
    local contact = social.privateContact
    local player = localPlayer()
    local progress = current and Contracts.progress(group, player, false) or nil
    local reserves = SC.Trade and type(SC.Trade.reserveSummary) == "function"
        and SC.Trade.reserveSummary(group) or nil
    return {
        access = copy(social.access, 3, { count = 48 }),
        offer = offer and copy(offer, 6, { count = 512 }) or nil,
        active = active and copy(active, 6, { count = 512 }) or nil,
        currentTitle = current and current.title or nil,
        currentKind = current and current.kind or nil,
        lastResponse = response,
        lastTopic = social.dialogue.lastTopic,
        lastSpeaker = social.dialogue.lastSpeakerKey
            and memberName(memberByKey(group, social.dialogue.lastSpeakerKey)) or nil,
        privateContactAvailable = contact and contact.available == true or false,
        privateContactMember = contact and memberName(memberByKey(group, contact.memberKey)) or nil,
        completedContracts = tonumber(social.trade.completedContracts) or 0,
        brokenPromises = tonumber(social.trade.brokenPromises) or 0,
        householdDebt = tonumber(social.trade.debt) or 0,
        futureRecruitCandidate = social.trade.futureRecruitCandidate == true,
        futureRecruitConsideration = social.trade.futureRecruitConsideration == true,
        memoryCount = #social.memories,
        contractHistoryCount = #social.contract.history,
        tradePolicy = Contracts.tradePolicy(group),
        progress = progress,
        reserveSummary = reserves,
        notifications = copy(social.notifications, 4, { count = 192 }) or {},
    }
end

function Contracts.debugOffer(id, kind)
    if SC.Config.get("debugSpawnEnabled") ~= true then return false, "debug_tools_disabled" end
    local group = groupFor(id)
    if not group or not contractKinds[kind] then return false, "invalid_contract_kind" end
    local social = Contracts.initialize(group)
    social.contract.active = nil
    social.contract.offer = makeContract(group, kind, "none")
    social.contract.offer.revealed = true
    return true, kind
end

function Contracts.debugComplication(id, value)
    if SC.Config.get("debugSpawnEnabled") ~= true then return false, "debug_tools_disabled" end
    local group = groupFor(id)
    if not group or not complicationValues[value] then return false, "invalid_complication" end
    local social = Contracts.initialize(group)
    local contract = social.contract.active or social.contract.offer
    if not contract then return false, "contract_unavailable" end
    contract.complication, contract.hiddenSeverity = value, value == "hidden_severity"
    if value == "rival_objection" or value == "private_dissent" then
        contract.rival = copy(highestTensionRelation(group), 3, { count = 32 })
    end
    return true, value
end

function Contracts.debugComplete(id)
    if SC.Config.get("debugSpawnEnabled") ~= true then return false, "debug_tools_disabled" end
    local group = groupFor(id)
    if not group then return false, "faction_unavailable" end
    local social = Contracts.initialize(group)
    if not social.contract.active then
        local accepted, reason = Contracts.accept(group, nil, true)
        if not accepted then return false, reason end
    end
    return Contracts.fulfill(group, nil, true)
end

function Contracts.debugExpire(id)
    if SC.Config.get("debugSpawnEnabled") ~= true then return false, "debug_tools_disabled" end
    local group = groupFor(id)
    if not group then return false, "faction_unavailable" end
    local active = Contracts.initialize(group).contract.active
    if not active then return false, "no_active_contract" end
    active.deadlineHour = worldHour() - 1
    group.social.nextPulseAt = 0
    Contracts.pulseGroup(group, nil, U().nowMs())
    return true, "contract_expired"
end

function Contracts.debugAccess(id, state)
    if SC.Config.get("debugSpawnEnabled") ~= true then return false, "debug_tools_disabled" end
    local group = groupFor(id)
    if not group or (state ~= "guest" and state ~= "denied" and state ~= "contested") then
        return false, "invalid_access_state"
    end
    local access = Contracts.initialize(group).access
    access.state, access.reason = state, "debug"
    access.invitedUntilHour = state == "guest" and worldHour() + 24 or 0
    access.safeRest = state == "guest"
    return true, state
end

function Contracts.validate(group)
    if type(group) ~= "table" then return false end
    local social = Contracts.initialize(group)
    if not social or social.schema ~= SOCIAL_SCHEMA or type(social.access) ~= "table"
        or type(social.contract) ~= "table" or type(social.contract.history) ~= "table"
        or type(social.memories) ~= "table" or type(social.promises) ~= "table"
        or type(social.dialogue) ~= "table" or type(social.trade) ~= "table"
        or type(social.notifications) ~= "table" or type(social.notificationFlags) ~= "table"
        or type(social.notificationFlagOrder) ~= "table"
        or #social.contract.history > configuredLimit("factionContractHistoryLimit", 32)
        or #social.memories > configuredLimit("factionContractMemoryLimit", 64)
        or #social.promises > configuredLimit("factionContractPromiseLimit", 24) then
        return false
    end
    if #social.notifications > configuredLimit("factionNotificationLimit", 24)
        or #social.notificationFlagOrder
            > configuredLimit("factionNotificationFlagLimit", 96) then return false end
    if not accessStates[social.access.state] then return false end
    local active, offer = social.contract.active, social.contract.offer
    if active and (not contractKinds[active.kind] or active.status ~= "active") then return false end
    if offer and (not contractKinds[offer.kind] or offer.status ~= "offered") then return false end
    if active and offer then return false end
    for _, contract in pairs({ active, offer }) do
        if contract and (type(contract.id) ~= "string" or #contract.id > 160
            or (contract.requirements ~= nil and (type(contract.requirements) ~= "table"
                or #contract.requirements > 8))
            or (contract.kind == "local_threat" and type(contract.target) ~= "table")) then
            return false
        end
    end
    return true
end

function Contracts.validateConfiguration()
    for _, spec in ipairs({
        { "factionContractHistoryLimit", 32 },
        { "factionContractMemoryLimit", 64 },
        { "factionContractPromiseLimit", 24 },
        { "factionNotificationLimit", 24 },
        { "factionNotificationFlagLimit", 96 },
    }) do
        local raw = tonumber(SC.Config.get(spec[1]))
        if raw == nil or raw ~= raw or raw == math.huge or raw == -math.huge
            or raw < 1 or raw > 4096 or raw ~= math.floor(raw) then
            return false, "invalid faction limit: " .. spec[1]
        end
    end
    return true
end

function Contracts.reset(actor)
    if actor then actorStates[actor] = nil
    else actorStates = setmetatable({}, { __mode = "k" }) end
end

return Contracts
