-- SPDX-License-Identifier: MIT

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion

SC.NativeWorkActions = SC.NativeWorkActions or {}
local Work = SC.NativeWorkActions
local context

function Work.configure(value)
    assert(type(value) == "table", "native work context is required")
    context = value
    return Work
end

function Work.handles(action)
    return action == "barricade" or action == "remove_barricade"
        or action == "dismantle" or action == "eat_food"
        or action == "drink_item" or action == "drink_source"
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
    end
    return false, "unsupported native work action: " .. tostring(action)
end

return Work
