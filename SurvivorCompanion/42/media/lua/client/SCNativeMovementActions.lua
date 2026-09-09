-- SPDX-License-Identifier: MIT

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion

SC.NativeMovementActions = SC.NativeMovementActions or {}
local Movement = SC.NativeMovementActions
local context

function Movement.configure(value)
    assert(type(value) == "table", "native movement context is required")
    context = value
    return Movement
end

-- Admission, supported-intent validation, seating, and unknown native-action
-- blocking have already run in the facade before this provider/native choice.
function Movement.dispatch(actor, normalizedMode, intent, provider)
    local target = context.targetOf(intent)
    if intent.enginePath == true and target ~= nil then
        local handled, reason = context.useProvider(
            provider, "path", actor, target, normalizedMode, intent)
        if handled ~= nil then return handled, reason end
        if not provider.directNative then return false, reason end
        return context.directPath(actor, target, normalizedMode, intent)
    end

    local dx, dy, vectorReason = context.vectorFor(actor, intent)
    if dx == nil then return false, vectorReason end
    local handled, reason = context.useProvider(
        provider, "move", actor, normalizedMode, dx, dy, intent)
    if handled ~= nil then return handled, reason end
    if not provider.directNative then return false, reason end
    return context.directMove(actor, normalizedMode, dx, dy, intent)
end

return Movement
