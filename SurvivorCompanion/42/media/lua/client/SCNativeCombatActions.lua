-- SPDX-License-Identifier: MIT

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion

SC.NativeCombatActions = SC.NativeCombatActions or {}
local Combat = SC.NativeCombatActions
local context

function Combat.configure(value)
    assert(type(value) == "table", "native combat context is required")
    context = value
    return Combat
end

function Combat.handles(action)
    return action == "reload" or action == "unjam"
        or action == "attack_firearm" or action == "attack_melee"
        or action == "shove" or action == "stomp"
end

-- This handler is reachable only after SCNativeActions has applied pacing,
-- activity-ownership, interruption, effect-claim, and seating guards.
function Combat.dispatch(actor, action, intent, provider)
    if action == "reload" then return context.reload(actor, intent, provider) end
    if action == "unjam" then return context.unjam(actor, intent, provider) end
    if action == "attack_firearm" or action == "attack_melee"
        or action == "shove" or action == "stomp" then
        return context.attack(actor, action, intent, provider)
    end
    return false, "unsupported native combat action: " .. tostring(action)
end

return Combat
