-- SPDX-License-Identifier: MIT

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion

SC.NativeWorkActions = SC.NativeWorkActions or {}
local Work = SC.NativeWorkActions
local context

local productionActions = {
    chop_tree = "chopTree",
    saw_logs = "sawLogs",
    dig_grave = "digGrave",
    bury_body = "buryBody",
    fill_grave = "fillGrave",
    grab_body = "grabBody",
    drop_body = "dropBody",
    burn_body = "burnBody",
}

function Work.configure(value)
    assert(type(value) == "table", "native work context is required")
    context = value
    return Work
end

function Work.handles(action)
    return action == "barricade" or action == "remove_barricade"
        or action == "dismantle" or action == "eat_food"
        or action == "drink_item" or action == "drink_source"
        or productionActions[action] ~= nil
end

-- Timed-action records and their rollback/cancellation APIs remain in the
-- guarded facade; this family owns only action-specific selection.
function Work.dispatch(actor, action, intent, provider)
    if action == "barricade" then
        return context.barricade(actor, intent, provider)
    elseif action == "remove_barricade" then
        return context.removeBarricade(actor, intent, provider)
    elseif action == "dismantle" then
        return context.dismantle(actor, intent, provider)
    elseif action == "eat_food" or action == "drink_item" or action == "drink_source" then
        return context.needs(actor, action, intent, provider)
    elseif productionActions[action] ~= nil then
        local handler = context[productionActions[action]]
        if type(handler) ~= "function" then
            return false, "native production action is unavailable: " .. tostring(action)
        end
        return handler(actor, intent, provider)
    end
    return false, "unsupported native work action: " .. tostring(action)
end

return Work
