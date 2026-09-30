-- SPDX-License-Identifier: MIT
-- One vocabulary and preflight for the companion panel and world context menu.
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.Interaction = SC.Interaction or {}
local Interaction = SC.Interaction

Interaction.categories = {
    { id = "check_in", key = "UI_SC_Talk_CheckIn",
        actions = { "doing", "status", "needs", "plans" } },
    { id = "get_to_know", key = "UI_SC_Talk_GetToKnow",
        actions = { "memory", "background", "opinion", "relationship" } },
    { id = "support", key = "UI_SC_Talk_Support",
        actions = { "encourage", "praise" } },
}
Interaction.actions = {
    doing = { key = "UI_SC_Action_Doing", kind = "talk" },
    status = { key = "UI_SC_Action_Status", kind = "talk" },
    needs = { key = "UI_SC_Action_Needs", kind = "talk" },
    plans = { key = "UI_SC_Action_Plans", kind = "talk" },
    memory = { key = "UI_SC_Action_Memory", kind = "talk" },
    background = { key = "UI_SC_Action_Background", kind = "talk" },
    opinion = { key = "UI_SC_Action_Opinion", kind = "talk" },
    relationship = { key = "UI_SC_Action_Relationship", kind = "talk" },
    encourage = { key = "UI_SC_Action_Encourage", kind = "talk" },
    praise = { key = "UI_SC_Action_Praise", kind = "talk" },
    follow = { key = "UI_SC_Action_Follow", kind = "order" },
    stay = { key = "UI_SC_Action_Stay", kind = "order" },
    guard = { key = "UI_SC_Action_Guard", kind = "order" },
    regroup = { key = "UI_SC_Action_Regroup", kind = "order" },
    retreat = { key = "UI_SC_Action_Retreat", kind = "order" },
}
Interaction.quickOrders = { "follow", "stay", "regroup", "retreat" }
Interaction.recruitedOnly = {
    relationship = true, encourage = true, praise = true,
}
Interaction.sessions = Interaction.sessions or {}

local function label(key, ...)
    if SC.UI and type(SC.UI.text) == "function" then return SC.UI.text(key, ...) end
    if type(getText) == "function" then return getText(key, ...) end
    return key
end

function Interaction.descriptor(action)
    return Interaction.actions[action]
end

function Interaction.choices(categoryId, row)
    local category
    for _, candidate in ipairs(Interaction.categories) do
        if candidate.id == categoryId then category = candidate; break end
    end
    category = category or Interaction.categories[1]
    local choices = {}
    for index, action in ipairs(category.actions) do
        local score = 0
        if action == "needs" and row and row.currentNeed then score = score + 5 end
        if action == "doing" and row and row.actionSummary then score = score + 3 end
        if action == "memory" and row and row.recentMemory then score = score + 4 end
        if action == "plans" and row and row.activity == "Scavenge" then score = score + 2 end
        choices[#choices + 1] = { action = action, score = score, index = index }
    end
    table.sort(choices, function(left, right)
        if left.score ~= right.score then return left.score > right.score end
        return left.index < right.index
    end)
    return choices
end

function Interaction.availability(row, action, player)
    local descriptor = Interaction.actions[action]
    if not descriptor then return false, "UI_SC_Disabled_CommandService" end
    if not row or not row.id or row.id == "" then return false, "UI_SC_Disabled_NoSelection" end
    if row.alive == false then return false, "UI_SC_Disabled_NotAlive" end
    if row.available == false or not row.actor then return false, "UI_SC_Disabled_Unavailable" end
    if row.recruited ~= true and (descriptor.kind == "order"
        or Interaction.recruitedOnly[action]) then
        return false, "UI_SC_Disabled_RecruitedOnly"
    end
    if not player then return false, "UI_SC_Disabled_NoPlayer" end
    if not SC.Commands or type(SC.Commands.issue) ~= "function" then
        return false, "UI_SC_Disabled_CommandService"
    end
    if SC.ExpeditionPrototype and type(SC.ExpeditionPrototype.isMember) == "function"
        and SC.ExpeditionPrototype.isMember(row.actor) then
        return false, "UI_SC_Talk_RadioRequired"
    end
    if SCSplitScreenProbe and type(SCSplitScreenProbe.isLeader) == "function" then
        local ok, leader = pcall(SCSplitScreenProbe.isLeader, row.actor)
        if ok and leader then return false, "UI_SC_Talk_RadioRequired" end
    end
    if descriptor.kind == "talk" then
        if SC.GameplayUtil and type(SC.GameplayUtil.sameFloor) == "function"
            and not SC.GameplayUtil.sameFloor(row.actor, player) then
            return false, "UI_SC_Talk_DifferentFloor"
        end
        if Interaction.sessions[tostring(row.id)]
            and Interaction.sessions[tostring(row.id)].state == "approaching" then
            return false, "UI_SC_Talk_Busy"
        end
        local distance = tonumber(row.distance)
        if not distance or distance > 16 then return false, "UI_SC_Disabled_TooFar", 16 end
    end
    return true
end

local function session(id)
    local key = tostring(id or "")
    if not Interaction.sessions[key] then
        Interaction.sessions[key] = { lines = {}, state = "idle", serial = 0 }
    end
    return Interaction.sessions[key]
end

function Interaction.state(id)
    return session(id)
end

function Interaction.note(id, speaker, message)
    if not id or not message or message == "" then return end
    local item = session(id)
    item.lines[#item.lines + 1] = { speaker = speaker, text = tostring(message) }
    while #item.lines > 24 do table.remove(item.lines, 1) end
    item.serial = item.serial + 1
end

function Interaction.begin(id, action)
    local item = session(id)
    item.state = "approaching"
    item.action = action
    item.serial = item.serial + 1
end

local interruptionKeys = {
    conversation_timed_out = "UI_SC_Talk_Timeout",
    conversation_interrupted_by_danger = "UI_SC_Talk_Danger",
    conversation_interrupted_by_order = "UI_SC_Talk_OrderInterrupted",
    conversation_partner_unavailable = "UI_SC_Talk_PartnerUnavailable",
    conversation_position_unavailable = "UI_SC_Talk_PathUnavailable",
    conversation_navigation_unavailable = "UI_SC_Talk_PathUnavailable",
    conversation_rejected = "UI_SC_Talk_Cancelled",
    conversation_cancelled = "UI_SC_Talk_Cancelled",
    conversation_replaced = "UI_SC_Talk_Cancelled",
    conversation_partner_too_far = "UI_SC_Disabled_TooFar",
}

function Interaction.reasonText(reason, argument)
    local key = interruptionKeys[reason] or reason
    if type(key) == "string" and string.sub(key, 1, 6) == "UI_SC_" then
        if key == "UI_SC_Disabled_TooFar" and argument == nil then argument = 16 end
        return argument ~= nil and label(key, argument) or label(key)
    end
    return label("UI_SC_Talk_Cancelled")
end

function Interaction.finish(id, action, reply, reason)
    local item = session(id)
    if item.action ~= action then return end
    item.state = reason and "interrupted" or "replied"
    item.action = nil
    if not reason then
        Interaction.note(id, "player", label(Interaction.actions[action].key))
    end
    Interaction.note(id, reason and "system" or "companion",
        reason and Interaction.reasonText(reason) or reply)
end

function Interaction.issue(row, action, player)
    local enabled, reason, argument = Interaction.availability(row, action, player)
    if not enabled then return false, reason, argument end
    local descriptor = Interaction.actions[action]
    local ok, accepted, result = pcall(SC.Commands.issue, row.id, action, nil, player)
    if not ok then return false, "UI_SC_Disabled_CommandService" end
    if accepted ~= true then
        if descriptor.kind == "talk" then
            Interaction.note(row.id, "system", Interaction.reasonText(result))
        end
        return false, result
    end
    return true, result
end

function Interaction.reset()
    Interaction.sessions = {}
end

return Interaction
