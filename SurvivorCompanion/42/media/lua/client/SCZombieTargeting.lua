-- SPDX-License-Identifier: MIT

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
if not SC.GameplayUtil and type(require) == "function" then pcall(require, "SCGameplayUtil") end

SC.ZombieTargeting = SC.ZombieTargeting or {}
local Targeting = SC.ZombieTargeting
local scanState = setmetatable({}, { __mode = "k" })

local function U()
    return SC.GameplayUtil
end

local function validCurrentTarget(target)
    return target ~= nil and U().isDead(target) ~= true and U().squareOf(target) ~= nil
end

local function eligibleActor(actor)
    if not U() or U().isValidActor(actor) ~= true then return false, "invalid_actor" end
    local ghost, ghostOk = U().call(actor, "isGhostMode")
    if ghostOk and ghost == true then return false, "actor_is_ghost" end
    local invisible, invisibleOk = U().call(actor, "isInvisible")
    if invisibleOk and invisible == true then return false, "actor_is_invisible" end
    return true
end

local function clearSight(zombie, actor)
    if not U().sameFloor(zombie, actor) then return false end
    -- Character CanSee() depends on a local IsoPlayer visibility index. Our
    -- non-local companion intentionally owns no such slot, so use the game's
    -- tile raycast for the prefilter and then let IsoZombie.spotted() apply its
    -- own facing, light, movement, traits and memory calculation.
    return U().canSee(zombie, U().squareOf(actor))
end

local function mayChallengeCurrentTarget(zombie, actor, actorDistance)
    local current, targetOk = U().call(zombie, "getTarget")
    if not targetOk or not validCurrentTarget(current) then return true, current end
    if current == actor then return false, current, "already_targeted" end
    local currentDistance = U().distance(zombie, current)
    local advantage = U().config("zombieTargetSwitchAdvantage") or 0.75
    return actorDistance + advantage < currentDistance, current,
        actorDistance + advantage < currentDistance and nil or "closer_target_retained"
end

function Targeting.consider(zombie, actor)
    local actorOk, actorReason = eligibleActor(actor)
    if not actorOk then return false, actorReason end
    if zombie == nil or U().isZombie(zombie) ~= true or U().isDead(zombie) then
        return false, "invalid_zombie"
    end
    local useless, uselessOk = U().call(zombie, "isUseless")
    if uselessOk and useless == true then return false, "zombie_is_useless" end
    local distance = U().distance(zombie, actor)
    local radius = U().config("zombieTargetRadius") or 18
    if distance == math.huge or distance > radius then return false, "outside_target_radius" end
    local challenge, _, challengeReason = mayChallengeCurrentTarget(zombie, actor, distance)
    if not challenge then return challengeReason == "already_targeted", challengeReason end
    if not clearSight(zombie, actor) then return false, "line_of_sight_blocked" end

    -- At grabbing distance a clear same-floor human cannot remain invisible
    -- because lighting slot 3 belongs to no local player. Outside that small
    -- safety radius the ordinary spotted probability preserves stealth.
    local closeRadius = U().config("zombieTargetCloseNoticeRadius") or 2.5
    local forced = distance <= closeRadius
    local _, spottedOk = U().call(zombie, "spotted", actor, forced)
    if not spottedOk then return false, "zombie_spotted_adapter_unavailable" end
    local selected, selectedOk = U().call(zombie, "getTarget")
    if selectedOk and selected == actor then
        return true, forced and "close_companion_targeted" or "companion_spotted"
    end
    return false, "companion_not_spotted_this_scan"
end

function Targeting.scan(actor, current, suppliedZombies)
    local actorOk, actorReason = eligibleActor(actor)
    if not actorOk then return false, actorReason end
    current = tonumber(current) or U().nowMs()
    local state = scanState[actor]
    if not state then
        state = { nextAt = 0, checked = 0, targeted = 0 }
        scanState[actor] = state
    end
    if current < (tonumber(state.nextAt) or 0) then return false, "target_scan_cooldown" end
    state.nextAt = current + (U().config("zombieTargetScanIntervalMs") or 350)

    -- The production runtime supplies the already-bounded Senses threat list.
    -- Never rescan the global cell here: that would multiply a large zombie
    -- list by every companion and bypass the shared perception budget.
    local zombies = suppliedZombies
    if zombies == nil then return false, "zombie_candidates_unavailable" end
    local maximum = U().config("zombieTargetMaxChecks") or 128
    local checked, visible, targeted = 0, 0, 0
    U().each(zombies, maximum, function(zombie)
        checked = checked + 1
        local accepted, reason = Targeting.consider(zombie, actor)
        if reason ~= "outside_target_radius" and reason ~= "line_of_sight_blocked"
            and reason ~= "invalid_zombie" then visible = visible + 1 end
        if accepted then targeted = targeted + 1 end
    end)
    state.checked, state.visible, state.targeted = checked, visible, targeted
    state.lastAt = current
    return true, targeted > 0 and "zombies_targeted_companion" or "target_scan_complete", {
        checked = checked,
        visible = visible,
        targeted = targeted,
    }
end

function Targeting.peek(actor)
    return actor and scanState[actor] or nil
end

function Targeting.reset(actor)
    if actor ~= nil then scanState[actor] = nil
    else scanState = setmetatable({}, { __mode = "k" }) end
    return true
end

SC.Modules = SC.Modules or {}
SC.Modules.zombieTargeting = true
return Targeting
