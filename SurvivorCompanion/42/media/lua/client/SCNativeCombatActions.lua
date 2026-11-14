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

-- Read the actual native owner; do not mistake servicing this actor's held gun
-- for unrelated work which ordinary combat sightings should interrupt.
function Combat.serviceKind(actor)
    local queues = type(ISTimedActionQueue) == "table" and ISTimedActionQueue.queues
    local queue = queues and queues[actor]
    local active = queue and queue.current
    if not active or active.character ~= actor or not active.gun then return nil end
    if type(SC.GameplayUtil) ~= "table" then return nil end
    local gun, okay = SC.GameplayUtil.call(actor, "getPrimaryHandItem")
    if not okay or active.gun ~= gun then return nil end
    if active.Type == "ISRackFirearm" then return "unjam", active end
    if active.Type == "ISReloadWeaponAction" or active.Type == "ISInsertMagazine"
        or active.Type == "ISEjectMagazine" then return "reload", active end
    return nil
end

-- A walking step may coexist with this exact native gun action. A stale
-- receipt, another actor's action, running, or a modded action which disallows
-- walking must still pass through the ordinary ownership protections.
function Combat.permitsServiceWalk(actor, mode, intent)
    if mode ~= "walk" or type(intent) ~= "table" or intent.action ~= "backstep"
        or intent.enginePath or intent.keepFacing or intent.weaponReady then return false end
    local kind, active = Combat.serviceKind(actor)
    return kind ~= nil and intent.firearmService == active
        and intent.weapon == active.gun and active.stopOnWalk == false
        and active.stopOnRun == true
end

-- IsoPlayer's input update resets AttackType to NONE. LF deliberately omits
-- that local-player controller; after a finished shot, its retained SHOT input
-- can keep shouldBeTurning() true and exclude the native reload animation.
-- Release only that completed input, never a committed swing or its receipt.
function Combat.releaseCompletedInput(actor)
    local utility = SC.GameplayUtil
    local attacking, readable = utility.call(actor, "isAttacking")
    if not readable or attacking ~= true then return true end
    local ready, why = SC.NativeActions.combatReadiness(actor, "reload")
    if not ready then return false, why end
    local okay, none = pcall(function() return AttackType.NONE end)
    if not okay or none == nil then return false, "native_attack_input_unavailable" end
    local _, changed = utility.call(actor, "setAttackType", none)
    local retained, checked = utility.call(actor, "isAttacking")
    return changed and (not checked or retained ~= true), "native_attack_input_released"
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
