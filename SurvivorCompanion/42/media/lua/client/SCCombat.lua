-- SPDX-License-Identifier: MIT

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
if not SC.GameplayUtil and type(require) == "function" then pcall(require, "SCGameplayUtil") end

SC.Combat = SC.Combat or {}
local Combat = SC.Combat
local states = setmetatable({}, { __mode = "k" })
local targetClaims = setmetatable({}, { __mode = "k" })
local lastGroupCombatBarkAt = -math.huge

local function U()
    return SC.GameplayUtil
end

local function actionSupervisor()
    return type(SC.ActionSupervisor) == "table" and SC.ActionSupervisor or nil
end

local function weaponKey(item)
    return "weapon:" .. tostring(U().itemType(item) or "unknown") .. ":" .. tostring(item)
end

local function equipWeapon(actor, item, options)
    options = type(options) == "table" and options or {}
    if item == nil then return false, "equip_weapon_missing" end
    local primary, primaryOk = U().call(actor, "getPrimaryHandItem")
    if primaryOk and primary == item then return true, "weapon_already_equipped" end
    local service = actionSupervisor()
    if service == nil or type(service.begin) ~= "function" then
        return U().move(actor, "walk", {
            action = "equip_weapon", item = item, nextAction = options.nextAction,
            immediateCommand = options.immediateCommand == true,
        })
    end
    local token, beginReason, retry = service.begin(actor, {
        owner = "combat-loadout",
        action = "equip_weapon",
        priority = options.immediateCommand == true and service.Priority.PLAYER
            or service.Priority.COMBAT_RESCUE,
        targetKey = weaponKey(item),
        targetLabel = U().itemName(item),
        phase = "selected",
        allowedActions = { equip_weapon = true },
        metadata = { preference = options.preference, nextAction = options.nextAction },
    })
    if token == nil then return false, beginReason or "equip_owner_rejected", retry end
    local reserved, reserveReason = service.reserve(token, item, "weapon")
    if reserved ~= true then
        service.fail(token, "equip_weapon_reservation_failed", { reason = reserveReason })
        return false, reserveReason
    end
    service.transition(token, "committing", { weapon = U().itemName(item) })
    local accepted, reason = U().move(actor, "walk", {
        action = "equip_weapon", item = item, nextAction = options.nextAction,
        immediateCommand = options.immediateCommand == true,
        supervisorToken = token,
    })
    if accepted ~= true then
        service.fail(token, "equip_weapon_rejected", { reason = reason })
        return false, reason or "equip_rejected"
    end
    service.transition(token, "verifying", { nativeReason = reason })
    primary, primaryOk = U().call(actor, "getPrimaryHandItem")
    if not primaryOk or primary ~= item then
        service.fail(token, "equip_weapon_not_verified", { nativeReason = reason })
        return false, "equip_not_verified"
    end
    local twoHanded, twoHandedOk = U().call(item, "isTwoHandWeapon")
    if twoHandedOk and twoHanded == true then
        local secondary, secondaryOk = U().call(actor, "getSecondaryHandItem")
        if not secondaryOk or secondary ~= item then
            service.fail(token, "equip_two_handed_not_verified", { nativeReason = reason })
            return false, "equip_two_handed_not_verified"
        end
    end
    service.complete(token, "weapon_equipped", {
        weapon = U().itemName(item), preference = options.preference,
    })
    return true, "weapon_equipped"
end

Combat.equipWeapon = equipWeapon

local function stateFor(actor)
    local state = states[actor]
    if not state then
        state = { active = false, target = nil, lastActionAt = 0 }
        states[actor] = state
    end
    return state
end

-- Keep rejected native combat pulses visible without flooding console.txt.
-- The ordinary diagnostics throttle is keyed by actor and message, while the
-- runtime fields let the support panel explain why a drawn weapon did not
-- produce a swing on the most recent combat tick.
function Combat.noteRejection(actor, state, runtime, action, reason, target, distance, weapon)
    reason = tostring(reason or "combat_action_rejected")
    state.lastRejectedAction = action
    state.lastRejectedReason = reason
    state.lastRejectedAt = U().nowMs()
    runtime.combatRejectedAction = action
    runtime.combatRejectedReason = reason
    runtime.combatRejectedDistance = tonumber(distance)
    runtime.combatRejectedWeapon = weapon and U().itemName(weapon.item) or nil
    U().diagnostic("combat", actor,
        "action=" .. tostring(action or "none")
            .. " reason=" .. reason
            .. " distance=" .. string.format("%.2f", tonumber(distance) or -1)
            .. " weapon=" .. tostring(runtime.combatRejectedWeapon or "none")
            .. " target=" .. tostring(target and U().objectLabel(target) or "none"))
end

local function clearRejection(state, runtime)
    state.lastRejectedAction = nil
    state.lastRejectedReason = nil
    state.lastRejectedAt = nil
    runtime.combatRejectedAction = nil
    runtime.combatRejectedReason = nil
    runtime.combatRejectedDistance = nil
    runtime.combatRejectedWeapon = nil
end

local function commandState(actor)
    local commands = SC.Commands
    if type(commands) == "table" and type(commands.peek) == "function" then
        local ok, value = pcall(commands.peek, actor)
        if ok and type(value) == "table" then return value end
    end
    return {
        combatMode = "defensive",
        combatDoctrine = "close_defense",
        holdFire = false,
        weaponPriority = "best",
    }
end

local barkCooldownKeys = {
    ["combat.engage"] = "combatBarkEngageCooldownMs",
    ["combat.retreat"] = "combatBarkRetreatCooldownMs",
    ["combat.struggle"] = "combatBarkStruggleCooldownMs",
    ["combat.kill"] = "combatBarkKillCooldownMs",
}

local function canonicalCombatTopic(topic)
    for baseTopic in pairs(barkCooldownKeys) do
        if topic == baseTopic or string.sub(topic, 1, #baseTopic + 1) == baseTopic .. "." then
            return baseTopic
        end
    end
    return topic
end

local function countedCombatTopic(prefix, snapshot)
    local count = type(snapshot) == "table" and (tonumber(snapshot.threatCount)
        or #(snapshot.threats or {})) or 1
    if SC.Dialogue and type(SC.Dialogue.threatTopic) == "function" then
        return SC.Dialogue.threatTopic(prefix, count)
    end
    return prefix
end

local function emitCombatBark(actor, state, commands, topic, now, survivalCritical)
    if commands.combatDoctrine == "stealth" and survivalCritical ~= true then
        return false, "combat_bark_stealth_suppressed"
    end
    state.combatBarkAt = state.combatBarkAt or {}
    local cooldownTopic = canonicalCombatTopic(topic)
    local actorGap = survivalCritical == true
        and (U().config("combatBarkCriticalActorGapMs") or 2000)
        or (U().config("combatBarkActorGapMs") or 7500)
    if now - (tonumber(state.lastCombatBarkAt) or -math.huge) < actorGap then
        return false, "combat_bark_actor_cooldown"
    end
    if SC.Dialogue and type(SC.Dialogue.lastSpokenAt) == "function" then
        local spokenAt = SC.Dialogue.lastSpokenAt(actor)
        if now - spokenAt < actorGap then return false, "combat_bark_speech_cooldown" end
    end
    local groupGap = survivalCritical == true
        and (U().config("combatBarkCriticalGroupGapMs") or 1200)
        or (U().config("combatBarkGroupGapMs") or 2500)
    if now - lastGroupCombatBarkAt < groupGap then
        return false, "combat_bark_group_cooldown"
    end
    local cooldownKey = barkCooldownKeys[cooldownTopic]
    local cooldown = cooldownKey and U().config(cooldownKey) or 15000
    if now - (tonumber(state.combatBarkAt[cooldownTopic]) or -math.huge) < cooldown then
        return false, "combat_bark_topic_cooldown"
    end
    if not SC.Dialogue or type(SC.Dialogue.say) ~= "function" then
        return false, "combat_bark_dialogue_unavailable"
    end
    local spoken = SC.Dialogue.say(actor, topic, nil, nil, {
        state = commands,
        recentLimit = 4,
        salt = tostring(now),
    })
    if spoken ~= true then return false, "combat_bark_rejected" end
    state.lastCombatBarkAt = now
    state.combatBarkAt[cooldownTopic] = now
    lastGroupCombatBarkAt = now

    -- A yell is not cosmetic silence: nearby actors can hear it and the game
    -- receives a modest world-sound event. The radius stays below the existing
    -- general zombie warning so combat chatter does not dominate stealth.
    local x, y, z = U().position(actor)
    if x and SC.Senses and type(SC.Senses.hear) == "function" then
        pcall(SC.Senses.hear, actor, x, y, z,
            U().config("combatBarkSoundRadius") or 8, 10, "companion_combat_bark")
    end
    if x and type(addSound) == "function" then
        pcall(addSound, actor, x, y, z, U().config("combatBarkSoundRadius") or 8, 10)
    end
    return true, "combat_bark_spoken"
end

local function clearEngagement(state)
    state.engagementTarget = nil
    state.engagementStartedAt = nil
    state.engagementActionCount = 0
    state.engagementAnnounced = false
    state.struggleAnnounced = false
end

local function prepareEngagement(state, target, now)
    if state.engagementTarget == target then return end
    state.engagementTarget = target
    state.engagementStartedAt = now
    state.engagementActionCount = 0
    state.engagementAnnounced = false
    state.struggleAnnounced = false
end

local function recordOffensiveAction(actor, state, commands, target, now, announceEngage, snapshot)
    if target == nil then return end
    prepareEngagement(state, target, now)
    state.engagementActionCount = (tonumber(state.engagementActionCount) or 0) + 1
    state.lastOffensiveTarget = target
    state.lastOffensiveAt = now

    if announceEngage == true and state.engagementAnnounced ~= true then
        state.engagementAnnounced = true
        emitCombatBark(actor, state, commands,
            countedCombatTopic("combat.engage", snapshot), now, false)
    end
    local actionMinimum = U().config("combatBarkStruggleActionCount") or 4
    local timeMinimum = U().config("combatBarkStruggleDelayMs") or 6500
    if state.struggleAnnounced ~= true
        and state.engagementActionCount >= actionMinimum
        and now - (tonumber(state.engagementStartedAt) or now) >= timeMinimum then
        local spoken, barkReason = emitCombatBark(
            actor, state, commands, "combat.struggle", now, false)
        -- A temporary actor/group gate may clear during the same prolonged
        -- fight, so retry on a later accepted attack. Stealth suppression is
        -- policy, not timing, and should not be probed on every combat tick.
        if spoken == true or barkReason == "combat_bark_stealth_suppressed" then
            state.struggleAnnounced = true
        end
    end
end

local function enterRetreat(actor, state, commands, now, survivalCritical, snapshot)
    if state.retreating == true then return end
    state.retreating = true
    emitCombatBark(actor, state, commands,
        countedCombatTopic("combat.retreat", snapshot), now, survivalCritical)
end

local function confirmRecentKill(actor, state, commands, now)
    local target = state.lastOffensiveTarget
    if target == nil then return false, "no_recent_offense" end
    local attackedAt = tonumber(state.lastOffensiveAt) or -math.huge
    local creditWindow = U().config("combatBarkKillCreditMs") or 5000
    if U().isDead(target) ~= true then
        if now - attackedAt > creditWindow then
            state.lastOffensiveTarget = nil
            state.lastOffensiveAt = nil
        end
        return false, "target_still_alive"
    end
    local credited = now - attackedAt <= creditWindow
    state.lastOffensiveTarget = nil
    state.lastOffensiveAt = nil
    if state.engagementTarget == target then clearEngagement(state) end
    if credited and state.lastConfirmedKill ~= target then
        state.lastConfirmedKill = target
        emitCombatBark(actor, state, commands, "combat.kill", now, false)
        return true, "recent_kill_confirmed"
    end
    return false, credited and "kill_already_confirmed" or "kill_credit_expired"
end

-- Decision selection stops delegating to Combat as soon as Senses removes a
-- dead zombie. Keep this tiny observer public so the next ordinary AI tick can
-- confirm a kill even though there is no longer a combat candidate.
function Combat.observe(actor)
    if not U() or not U().isValidActor(actor) then return false, "invalid_actor" end
    local state = states[actor]
    if type(state) ~= "table" then return false, "no_combat_history" end
    return confirmRecentKill(actor, state, commandState(actor), U().nowMs())
end

local function activeClaim(target, actor, now)
    local claim = target and targetClaims[target] or nil
    if type(claim) ~= "table" then return nil end
    if (tonumber(claim.untilAt) or 0) <= now or U().isDead(claim.actor) then
        targetClaims[target] = nil
        return nil
    end
    if claim.actor == actor then return nil end
    return claim
end

local function claimTarget(target, actor, now)
    if target == nil then return end
    targetClaims[target] = {
        actor = actor,
        untilAt = now + (U().config("combatTargetClaimMs") or 450),
    }
end

local function boolCall(value, methodName, ...)
    local result, ok = U().call(value, methodName, ...)
    return ok and result == true
end

local function numberCall(value, methodName, fallback, ...)
    local result, ok = U().call(value, methodName, ...)
    if ok and type(result) == "number" then return result end
    return fallback or 0
end

local function weaponRecord(item)
    local utility = U()
    if not item then return nil end
    local isWeapon = utility.instanceOf(item, "HandWeapon")
        or utility.instanceOf(item, "zombie.inventory.types.HandWeapon")
        or utility.hasMethod(item, "getMaxDamage")
    if not isWeapon then return nil end
    local ranged = boolCall(item, "isRanged")
    local condition = numberCall(item, "getCondition", 100)
    local conditionMax = math.max(1, numberCall(item, "getConditionMax", 100))
    local ammo = numberCall(item, "getCurrentAmmoCount", -1)
    if ammo < 0 then ammo = numberCall(item, "getAmmoCount", ranged and 0 or 1) end
    local maxAmmo = numberCall(item, "getMaxAmmo", ranged and 1 or 1)
    local damage = numberCall(item, "getMaxDamage", 1)
    local range = numberCall(item, "getMaxRange", ranged and 8 or 1.5)
    local swing = math.max(0.2, numberCall(item, "getSwingTime", 1))
    local weight = math.max(0.1, numberCall(item, "getActualWeight",
        numberCall(item, "getWeight", 1)))
    local enduranceMod = math.max(0.1, numberCall(item, "getEnduranceMod", 1))
    local sharpness = U().clamp(numberCall(item, "getSharpness", 1), 0, 1)
    local twoHanded = boolCall(item, "isTwoHandWeapon")
    local staminaCost = weight * enduranceMod * swing * (twoHanded and 1.08 or 1)
    return {
        item = item,
        type = utility.itemType(item),
        ranged = ranged,
        condition = condition,
        conditionRatio = condition / conditionMax,
        ammo = ammo,
        maxAmmo = maxAmmo,
        damage = damage,
        range = range,
        swing = swing,
        weight = weight,
        enduranceMod = enduranceMod,
        sharpness = sharpness,
        twoHanded = twoHanded,
        staminaCost = staminaCost,
        score = damage * 12 + range * (ranged and 2 or 0.5) - swing * 2
            + condition / conditionMax * 15 + (ranged and 0 or sharpness * 5)
            - staminaCost * 1.5,
    }
end

local function inventoryWeapons(actor)
    local utility = U()
    local result = {}
    local primary, primaryOk = utility.call(actor, "getPrimaryHandItem")
    if primaryOk and primary then
        local record = weaponRecord(primary)
        if record then record.equipped = true result[#result + 1] = record end
    end
    local inventory = utility.inventory(actor)
    for _, item in ipairs(utility.inventoryItems(inventory, 90)) do
        if item ~= primary then
            local record = weaponRecord(item)
            if record then result[#result + 1] = record end
        end
    end
    return result, inventory
end

local function hasReloadAmmo(inventory, weapon)
    local utility = U()
    if not inventory or not weapon or not weapon.ranged then return false end
    local ammoType, ok = utility.call(weapon.item, "getAmmoType")
    if ok and ammoType then
        local contains, containsOk = utility.call(inventory, "containsTypeRecurse", tostring(ammoType))
        if containsOk then return contains == true end
        contains, containsOk = utility.call(inventory, "contains", tostring(ammoType))
        if containsOk then return contains == true end
    end
    for _, item in ipairs(utility.inventoryItems(inventory, 90)) do
        local itemType = string.lower(utility.itemType(item))
        if string.find(itemType, "ammo", 1, true)
            or string.find(itemType, "bullets", 1, true)
            or string.find(itemType, "shells", 1, true) then return true end
    end
    return false
end

local function chooseWeapon(actor, preference, distance, pressure)
    local weapons, inventory = inventoryWeapons(actor)
    local preferredAvailable = false
    if preference == "melee" or preference == "quiet" or preference == "firearm" then
        for _, weapon in ipairs(weapons) do
            local matches = (preference == "firearm" and weapon.ranged)
                or ((preference == "melee" or preference == "quiet") and not weapon.ranged)
            if matches and weapon.condition > 0 then
                preferredAvailable = true
                break
            end
        end
    end
    local best, bestScore
    for _, weapon in ipairs(weapons) do
        local score = weapon.score
        if weapon.condition <= 0 then score = -1000 end
        local matchesPreference = (preference == "firearm" and weapon.ranged)
            or ((preference == "melee" or preference == "quiet") and not weapon.ranged)
        if preferredAvailable and not matchesPreference then score = score - 10000 end
        if weapon.ranged then
            if weapon.ammo <= 0 and not hasReloadAmmo(inventory, weapon) then score = score - 100 end
            if distance < (U().config("combatFirearmMinDistance") or 2.2) then score = score - 32 end
            if pressure >= 3 then score = score - 18 end
            if preference == "firearm" then score = score + 24 end
            if preference == "melee" or preference == "quiet" then score = score - 28 end
        else
            if distance <= 2 then score = score + 20 end
            if pressure >= 2 then score = score + 10 end
            if preference == "melee" or preference == "quiet" then score = score + 24 end
            if preference == "firearm" then score = score - 12 end
        end
        if not bestScore or score > bestScore then best, bestScore = weapon, score end
    end
    return best, inventory
end

function Combat.equipPreferred(actor, preference)
    if not U().isValidActor(actor) then return false, "invalid_actor" end
    local weapon = chooseWeapon(actor, preference or "best", 3, 0)
    if not weapon or not weapon.item or weapon.condition <= 0 then
        return false, "no_usable_weapon"
    end
    local weaponName = U().itemName(weapon.item)
    local primary, primaryOk = U().call(actor, "getPrimaryHandItem")
    if primaryOk and primary == weapon.item then
        return true, "weapon_already_equipped", { weaponName = weaponName }
    end
    local accepted, reason = equipWeapon(actor, weapon.item, {
        preference = preference or "best",
        immediateCommand = true,
    })
    if not accepted then
        return false, reason or "equip_rejected", { weaponName = weaponName }
    end
    return true, "weapon_equipped", { weaponName = weaponName }
end

local function threatBearing(actor, threat)
    local utility = U()
    local ax, ay = utility.position(actor)
    local tx, ty = utility.position(threat)
    if ax == nil or tx == nil then return "unknown", 0 end
    local dx, dy = tx - ax, ty - ay
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 0.001 then return "front", 1 end
    dx, dy = dx / length, dy / length
    local fx, fxOk = utility.call(actor, "getForwardDirectionX")
    local fy, fyOk = utility.call(actor, "getForwardDirectionY")
    if not fxOk or not fyOk or type(fx) ~= "number" or type(fy) ~= "number" then
        local vector, vectorOk = utility.call(actor, "getForwardDirection")
        if not vectorOk or vector == nil then return "unknown", 0 end
        fx, fxOk = utility.call(vector, "getX")
        fy, fyOk = utility.call(vector, "getY")
        if not fxOk or not fyOk or type(fx) ~= "number" or type(fy) ~= "number" then
            return "unknown", 0
        end
    end
    local forwardLength = math.sqrt(fx * fx + fy * fy)
    if forwardLength < 0.001 then return "unknown", 0 end
    local dot = dx * (fx / forwardLength) + dy * (fy / forwardLength)
    if dot <= -0.35 then return "rear", dot end
    if dot < 0.35 then return "flank", dot end
    return "front", dot
end

local function threatScore(threat, actor, player, snapshot)
    local utility = U()
    local distance = math.sqrt(threat.distanceSq or utility.distanceSq(actor, threat.actor))
    local score = 45 / (0.75 + distance)
    if threat.attacking then score = score + 32 end
    if threat.visible then score = score + 10 else score = score - 8 end
    if threat.obstructed then score = score - 12 end
    if threat.fenced then score = score - 7 end
    local bearing, facingDot = threatBearing(actor, threat.actor)
    if bearing == "rear" then
        score = score + (utility.config("combatRearThreatPriority") or 30)
    elseif bearing == "flank" then
        score = score + (utility.config("combatFlankThreatPriority") or 18)
    end
    if player and utility.sameFloor(player, threat.actor)
        and utility.distanceSq(player, threat.actor) <= 5.75 then score = score + 24 end
    if snapshot and type(snapshot.allies) == "table" then
        for _, ally in ipairs(snapshot.allies) do
            if utility.sameFloor(ally.actor, threat.actor)
                and utility.distanceSq(ally.actor, threat.actor) <= 4 then score = score + 15 break end
        end
    end
    return score, bearing, facingDot
end

function Combat.scoreTargets(actor, player, snapshot, previousTarget)
    local scored = {}
    local now = U().nowMs()
    if type(snapshot) ~= "table" or type(snapshot.threats) ~= "table" then return scored end
    for index = 1, math.min(#snapshot.threats, U().config("perceptionThreatLimit") or 32) do
        local threat = snapshot.threats[index]
        if threat.actor and not U().isDead(threat.actor) and U().sameFloor(actor, threat.actor) then
            local score, bearing, facingDot = threatScore(threat, actor, player, snapshot)
            if threat.actor == previousTarget then score = score + 8 end
            local claimed = activeClaim(threat.actor, actor, now) ~= nil
            if claimed then score = score - (U().config("combatTargetClaimPenalty") or 42) end
            local record = U().copyShallow(threat)
            record.score = score
            record.bearing = bearing
            record.facingDot = facingDot
            record.claimedByAlly = claimed
            scored[#scored + 1] = record
        end
    end
    table.sort(scored, function(a, b)
        if a.score == b.score then return (a.distanceSq or math.huge) < (b.distanceSq or math.huge) end
        return a.score > b.score
    end)
    return scored
end

local function addNearbyGrounded(actor, scored)
    local utility = U()
    local x, y, z = utility.position(actor)
    if not x then return end
    local seen = setmetatable({}, { __mode = "k" })
    for _, threat in ipairs(scored) do seen[threat.actor] = true end
    for dx = -1, 1 do
        for dy = -1, 1 do
            local square = utility.gridSquare(x + dx, y + dy, z)
            utility.squareMovingObjects(square, function(value)
                if not seen[value] and utility.isZombie(value) and not utility.isDead(value)
                    and utility.sameFloor(actor, value)
                    and (boolCall(value, "isOnFloor") or boolCall(value, "isProne")) then
                    seen[value] = true
                    scored[#scored + 1] = {
                        actor = value,
                        square = square,
                        distanceSq = utility.distanceSq(actor, value),
                        visible = utility.canSee(actor, value),
                        obstructed = utility.edgeBlocked(utility.squareOf(actor), square),
                        attacking = false,
                        grounded = true,
                        score = 42,
                    }
                end
            end, 10)
        end
    end
    table.sort(scored, function(a, b)
        if a.score == b.score then return (a.distanceSq or math.huge) < (b.distanceSq or math.huge) end
        return a.score > b.score
    end)
end

local function lineBlockedByFriendly(actor, target, player, snapshot)
    local utility = U()
    if utility.config("friendlyFire") == true then return false end
    if not utility.sameFloor(actor, target) then return true end
    local corridor = utility.config("friendlyFireCorridor") or 0.8
    local corridorSq = corridor * corridor
    local function blocks(friendly)
        if not friendly or friendly == actor or friendly == target then return false end
        if not utility.sameFloor(actor, friendly) then return false end
        if utility.distanceSq(actor, friendly) < 0.75 * 0.75 then return false end
        if utility.distanceSq(target, friendly) < 0.5 * 0.5 then return false end
        return utility.pointSegmentDistanceSq(friendly, actor, target) <= corridorSq
    end
    if blocks(player) then return true end
    if snapshot and type(snapshot.allies) == "table" then
        for _, ally in ipairs(snapshot.allies) do
            if blocks(ally.actor) then return true end
        end
    end
    return false
end

local function medicalPressure(actor)
    local medical = SC.Medical
    if type(medical) == "table" and type(medical.assess) == "function" then
        local ok, assessment = pcall(medical.assess, actor)
        if ok and type(assessment) == "table" then
            return assessment, assessment.bleedingCount * 0.8
                + math.max(0, 45 - assessment.health) / 15
                + assessment.woundCount * 0.15
        end
    end
    return { health = U().nativeHealth(actor), bleedingCount = 0, woundCount = 0 }, 0
end

local function healthySupportCount(actor, snapshot)
    local utility = U()
    local count = 0
    local radius = utility.config("combatAllySupportRadius") or 6
    local radiusSq = radius * radius
    for _, ally in ipairs(snapshot.allies or {}) do
        local downed = false
        if SC.Medical and type(SC.Medical.isDowned) == "function" then
            local ok, value = pcall(SC.Medical.isDowned, ally.actor)
            downed = ok and value == true
        end
        if ally.actor and not downed and utility.sameFloor(actor, ally.actor)
            and (tonumber(ally.distanceSq) or utility.distanceSq(actor, ally.actor)) <= radiusSq
            and (tonumber(ally.health) or utility.nativeHealth(ally.actor)) > 30 then count = count + 1 end
    end
    local player = type(snapshot.player) == "table" and snapshot.player or nil
    if player and player.available and player.actor and not utility.isDead(player.actor)
        and utility.sameFloor(actor, player.actor) and utility.distanceSq(actor, player.actor) <= radiusSq
        and (tonumber(player.health) or utility.nativeHealth(player.actor)) > 30 then count = count + 1 end
    return count
end

local function actorIsIndoor(actor)
    local square = U().squareOf(actor)
    local room, ok = U().call(square, "getRoom")
    return ok and room ~= nil
end

local meleePerks = {
    Axe = true, Blunt = true, LongBlade = true, LongBlunt = true,
    SmallBlade = true, SmallBlunt = true, Spear = true,
}

local function weaponSkill(actor, weapon)
    if not weapon then return 0, "Unarmed" end
    if weapon.ranged then return U().perkLevel(actor, "Aiming", 0), "Aiming" end
    local best, bestName = 0, "Melee"
    local categories, ok = U().call(weapon.item, "getCategories")
    if ok and categories then
        U().each(categories, 12, function(category)
            local name = tostring(category)
            if meleePerks[name] then
                local level = U().perkLevel(actor, name, 0)
                if level > best then best, bestName = level, name end
            end
        end)
    end
    if best > 0 then return best, bestName end
    local itemType = string.lower(tostring(weapon.type or ""))
    local inferred = string.find(itemType, "axe", 1, true) and "Axe"
        or (string.find(itemType, "knife", 1, true)
            or string.find(itemType, "blade", 1, true)) and "SmallBlade"
        or (string.find(itemType, "hammer", 1, true)
            or string.find(itemType, "club", 1, true)) and "SmallBlunt"
        or (string.find(itemType, "bat", 1, true)
            or string.find(itemType, "crowbar", 1, true)) and "Blunt"
        or nil
    if inferred then return U().perkLevel(actor, inferred, 0), inferred end
    return 0, bestName
end

local function footingRisk(actor)
    local utility = U()
    local square = utility.squareOf(actor)
    if not square then return 8, { squareMissing = true } end
    local tree, treeOk = utility.call(square, "HasTree")
    local crowd, corpses = 0, 0
    utility.squareMovingObjects(square, function(value)
        if value ~= actor and not utility.isDead(value) then crowd = crowd + 1 end
    end, 12)
    utility.squareStaticMovingObjects(square, function(value)
        if utility.isDead(value) or utility.instanceOf(value, "IsoDeadBody") then
            corpses = corpses + 1
        end
    end, 12)
    local risk = (treeOk and tree == true) and 8 or 0
    risk = risk + math.max(0, crowd - 1) * 4 + math.min(corpses, 3) * 1.5
    return risk, { tree = treeOk and tree == true, crowd = crowd, corpses = corpses }
end

-- A compact, inspectable model of what a competent player considers before
-- committing to another exchange. Internal state controls how much danger the
-- companion can absorb; the local geometry and squad situation control how
-- quickly that capacity is spent.
function Combat.readiness(actor, snapshot, weapon, commands)
    local utility = U()
    snapshot = type(snapshot) == "table" and snapshot or {}
    commands = type(commands) == "table" and commands or commandState(actor)
    local assessment, woundPressure = medicalPressure(actor)
    local endurance = utility.clamp(
        utility.characterStatValue(actor, "ENDURANCE", 0.5), 0, 1)
    local panic = utility.clamp(utility.moodleLevel(actor, "PANIC", 0), 0, 4)
    local pain = utility.clamp(utility.moodleLevel(actor, "PAIN", 0), 0, 4)
    local tired = utility.clamp(utility.moodleLevel(actor, "TIRED", 0), 0, 4)
    local heavyLoad = utility.clamp(utility.moodleLevel(actor, "HEAVY_LOAD", 0), 0, 4)
    local relationshipStress = utility.clamp(tonumber(commands.stress) or 0, 0, 100)
    local nativeStress = utility.characterStatValue(
        actor, "STRESS", relationshipStress / 100)
    local stress = utility.clamp(math.max(relationshipStress, nativeStress * 100), 0, 100)
    local morale = utility.clamp(tonumber(commands.morale) or 55, 0, 100)
    local strength = utility.clamp(utility.perkLevel(actor, "Strength", 5), 0, 10)
    local fitness = utility.clamp(utility.perkLevel(actor, "Fitness", 5), 0, 10)
    local nimble = utility.clamp(utility.perkLevel(actor, "Nimble", 0), 0, 10)
    local skill, skillName = weaponSkill(actor, weapon)
    local support = healthySupportCount(actor, snapshot)
    local immediate = tonumber(snapshot.closeImmediateCount)
        or tonumber(snapshot.immediateCount) or #(snapshot.immediateAttackers or {})
    local close = tonumber(snapshot.closeThreatCount) or immediate
    local occupied = tonumber(snapshot.occupiedThreatSectors) or 0
    local escapeSquares = snapshot.escapeSquares or {}
    local bestEscape = escapeSquares[1]
    local escapeDanger = bestEscape and (tonumber(bestEscape.danger) or 0) or 3
    local escapeClearance = bestEscape
        and math.sqrt(math.max(0, tonumber(bestEscape.nearestThreatSq) or 0)) or 0
    local localFootingRisk, footing = footingRisk(actor)
    local weaponCost = weapon and math.max(0.1, tonumber(weapon.staminaCost) or 1) or 0.8
    local heavyThreshold = utility.config("combatHeavyWeaponWeight") or 2.5
    local reserve = (utility.config("combatMinimumEnduranceReserve") or 0.18)
        + math.max(0, weaponCost - 1) * 0.035
        + math.max(0, 5 - fitness) * 0.018
        + math.max(0, immediate - 1) * 0.03
        + math.max(0, occupied - 1) * 0.035
        + (weapon and (tonumber(weapon.weight) or 0) >= heavyThreshold and 0.05 or 0)
        + (#escapeSquares == 0 and 0.1 or math.min(0.08, escapeDanger * 0.02))
    reserve = utility.clamp(reserve,
        utility.config("combatMinimumEnduranceReserve") or 0.18,
        utility.config("combatMaximumEnduranceReserve") or 0.62)
    local skillFitness = weapon and weapon.ranged and skill
        or skill * 0.45 + strength * 0.3 + nimble * 0.25
    local weaponQuality = weapon and utility.clamp(
        (tonumber(weapon.conditionRatio) or 0) * 0.7
            + (weapon.ranged and 0.3 or (tonumber(weapon.sharpness) or 0) * 0.3),
        0, 1) or 0
    local capacity = 1 + support * 1.25 + skillFitness * 0.08
        + fitness * 0.035 + weaponQuality * 0.45
    local internalRisk = (1 - endurance) * 24 + panic * 5 + stress * 0.1
        + pain * 4 + tired * 3 + heavyLoad * 4 + woundPressure * 5
        + math.max(0, 45 - morale) * 0.12
        + math.max(0, weaponCost - 1.5) * 2.5
    local externalRisk = immediate * 12 + math.max(0, close - capacity) * 8
        + math.max(0, occupied - 1) * 12 + escapeDanger * 5
        + localFootingRisk
    if snapshot.encircled then externalRisk = externalRisk + 22 end
    if #escapeSquares == 0 then externalRisk = externalRisk + 10 end
    if actorIsIndoor(actor) and occupied >= 2 then externalRisk = externalRisk + 6 end
    local staminaCritical = endurance <= reserve
    if staminaCritical then
        internalRisk = internalRisk + (reserve - endurance) * 90 + 10
    end
    local confidence = utility.clamp(50 + skillFitness * 3 + support * 7
        + weaponQuality * 12 + (morale - 50) * 0.25
        - internalRisk * 0.7 - externalRisk * 0.45, 0, 100)
    return {
        health = assessment.health,
        woundPressure = woundPressure,
        endurance = endurance,
        enduranceReserve = reserve,
        staminaCritical = staminaCritical,
        panic = panic,
        pain = pain,
        tired = tired,
        heavyLoad = heavyLoad,
        stress = stress,
        morale = morale,
        strength = strength,
        fitness = fitness,
        nimble = nimble,
        combatSkill = skill,
        combatSkillName = skillName,
        weaponCost = weaponCost,
        weaponQuality = weaponQuality,
        support = support,
        immediate = immediate,
        close = close,
        occupiedSectors = occupied,
        escapeCount = #escapeSquares,
        escapeDanger = escapeDanger,
        escapeClearance = escapeClearance,
        indoors = actorIsIndoor(actor),
        footing = footing,
        internalRisk = internalRisk,
        externalRisk = externalRisk,
        capacity = capacity,
        confidence = confidence,
    }
end

function Combat.assessOverrun(actor, snapshot, weapon, commands)
    snapshot = type(snapshot) == "table" and snapshot or {}
    commands = type(commands) == "table" and commands or commandState(actor)
    local readiness = Combat.readiness(actor, snapshot, weapon, commands)
    local assessment = { health = readiness.health }
    local reportedImmediate = tonumber(snapshot.immediateCount) or #(snapshot.immediateAttackers or {})
    local close = tonumber(snapshot.closeThreatCount) or reportedImmediate
    local immediate = tonumber(snapshot.closeImmediateCount) or math.min(reportedImmediate, close)
    local occupied = tonumber(snapshot.occupiedThreatSectors) or 0
    local support = readiness.support
    local capacity = readiness.capacity
    local risk = (tonumber(snapshot.directionalPressure) or tonumber(snapshot.pressure) or 0) * 10
        + immediate * 12
        + math.max(0, close - capacity) * 8
        + math.max(0, occupied - 1) * 12
        + readiness.internalRisk
        + readiness.escapeDanger * 3
        + (readiness.footing and ((readiness.footing.tree and 6 or 0)
            + math.max(0, readiness.footing.crowd - 1) * 3) or 0)
        - support * 5
    if snapshot.encircled then risk = risk + 22 end
    if #(snapshot.escapeSquares or {}) == 0 then risk = risk + 8 end
    if actorIsIndoor(actor) then risk = risk + 8 end
    if assessment.health < 45 then risk = risk + (45 - assessment.health) * 0.8 end
    if not weapon then risk = risk + 8
    elseif (tonumber(weapon.conditionRatio) or 1) < 0.2 then risk = risk + 8
    elseif weapon.ranged and (tonumber(weapon.ammo) or 0) <= 0 then risk = risk + 10 end
    local threshold = U().config("combatOverrunRisk") or 62
    if commands.combatMode == "aggressive" then threshold = threshold + 8
    elseif commands.combatMode == "passive" then threshold = threshold - 6 end
    if SC.Personality and type(SC.Personality.overrunThresholdDelta) == "function" then
        threshold = threshold + SC.Personality.overrunThresholdDelta(commands.personalityProfile, {
            escapeCount = #(snapshot.escapeSquares or {}),
            support = support,
            indoors = actorIsIndoor(actor),
        })
    end
    local overrun = immediate >= 3 or occupied >= 3
        or readiness.staminaCritical and (immediate >= 1 or close >= 2)
        or risk >= threshold
    return {
        risk = risk,
        threshold = threshold,
        overrun = overrun,
        immediate = immediate,
        close = close,
        occupiedSectors = occupied,
        support = support,
        indoors = actorIsIndoor(actor),
        readiness = readiness,
        staminaCritical = readiness.staminaCritical,
        confidence = readiness.confidence,
    }
end

local function retreatUtility(actor, snapshot, weapon, readiness)
    readiness = readiness or Combat.readiness(actor, snapshot, weapon, commandState(actor))
    local assessment = { health = readiness.health }
    local pressure = tonumber(snapshot.pressure) or 0
    local value = pressure * 16 + readiness.woundPressure * 12
        + (1 - readiness.endurance) * 28 + readiness.panic * 4
        + readiness.stress * 0.08 + readiness.pain * 3
        + readiness.heavyLoad * 3 + readiness.escapeDanger * 4
    if snapshot.encircled then value = value + 35 end
    if assessment.health < 30 then value = value + 35 end
    if not weapon then value = value + 18
    elseif weapon.conditionRatio < 0.2 then value = value + 14
    elseif weapon.ranged and weapon.ammo <= 0 then value = value + 12
    elseif weapon.ranged and weapon.maxAmmo > 0 and weapon.ammo / weapon.maxAmmo <= 0.2 then value = value + 7 end
    if #(snapshot.escapeSquares or {}) == 0 then value = value + 10 end
    if readiness.staminaCritical then value = value + 34 end
    if readiness.occupiedSectors >= 2 then value = value + (readiness.occupiedSectors - 1) * 12 end
    if readiness.footing and readiness.footing.tree then value = value + 8 end
    local support = readiness.support * 4
    value = value - math.min(support, U().config("combatAllySupportMax") or 12)
    return value
end

local function findGroundedThreat(scored, range)
    for _, threat in ipairs(scored) do
        if (threat.distanceSq or math.huge) <= range * range then
            if boolCall(threat.actor, "isOnFloor") or boolCall(threat.actor, "isProne") then return threat end
        end
    end
    return nil
end

local function shoveFollowUpSafe(snapshot, target)
    if type(snapshot) ~= "table" or snapshot.encircled == true then return false end
    local immediate = tonumber(snapshot.closeImmediateCount)
        or tonumber(snapshot.immediateCount) or #(snapshot.immediateAttackers or {})
    if immediate > (U().config("combatStompMaxImmediate") or 1) then return false end
    local dangerDistance = (U().config("combatShoveDistance") or 1.35) + 0.45
    local dangerDistanceSq = dangerDistance * dangerDistance
    for _, threat in ipairs(snapshot.threats or {}) do
        if threat.actor and threat.actor ~= target and not U().isDead(threat.actor)
            and (tonumber(threat.distanceSq) or U().distanceSq(threat.actor, target))
                <= dangerDistanceSq then return false end
    end
    return true
end

local function tryShoveFollowUp(actor, state, snapshot, now)
    local followUp = state.shoveFollowUp
    if type(followUp) ~= "table" then return nil, nil end
    local target = followUp.target
    if not target or U().isDead(target) or not U().isZombie(target)
        or not U().sameFloor(actor, target) then
        state.shoveFollowUp = nil
        return nil, "shove_followup_invalid"
    end
    if now > (followUp.expires or 0) then
        state.shoveFollowUp = nil
        return nil, "shove_followup_expired"
    end
    local elapsed = now - (followUp.startedAt or now)
    local attacking = boolCall(actor, "isAttackStarted")
        or boolCall(actor, "isPerformingAttackAnimation")
    if elapsed < (U().config("combatShoveFollowupDelayMs") or 300) or attacking then
        return true, "waiting_for_shove_result"
    end
    local grounded = boolCall(target, "isOnFloor") or boolCall(target, "isProne")
    if not grounded then
        state.shoveFollowUp = nil
        return nil, "shove_did_not_ground_target"
    end
    if not shoveFollowUpSafe(snapshot, target) then
        state.shoveFollowUp = nil
        return nil, "stomp_followup_unsafe"
    end
    local maximum = U().config("combatStompDistance") or 1.55
    if U().distanceSq(actor, target) > maximum * maximum then
        state.shoveFollowUp = nil
        return nil, "stomp_followup_out_of_range"
    end
    local accepted = U().move(actor, "walk", {
        action = "stomp", target = target, floorAttack = true,
        shoveFollowUp = true,
    })
    state.shoveFollowUp = nil
    if not accepted then return nil, "stomp_followup_rejected" end
    return true, "stomp_after_shove"
end

local function actionUtilities(actor, player, snapshot, target, weapon, inventory, commands,
        readiness)
    local utility = U()
    local distance = math.sqrt(target.distanceSq or utility.distanceSq(actor, target.actor))
    local pressure = tonumber(snapshot.pressure) or 0
    readiness = readiness or Combat.readiness(actor, snapshot, weapon, commands)
    local isolatedFront = readiness.close <= 1 and readiness.occupiedSectors <= 1
        and snapshot.encircled ~= true and target.bearing ~= "rear"
    local fatiguePenalty = (1 - readiness.endurance) * 24
    local actions = {}
    local retreat = retreatUtility(actor, snapshot, weapon, readiness)
    actions[#actions + 1] = { kind = "retreat", score = retreat }
    if distance <= (utility.config("combatShoveDistance") or 1.35) then
        actions[#actions + 1] = {
            kind = "shove",
            score = 62 + pressure * 7 + readiness.strength * 1.3
                + readiness.nimble * 0.5 - fatiguePenalty * 0.35
                + (isolatedFront and 10 or -8),
        }
    end
    local grounded = findGroundedThreat({ target }, 1.45)
    if grounded and readiness.immediate <= 1 and isolatedFront then
        actions[#actions + 1] = {
            kind = "stomp",
            score = 68 + readiness.strength * 0.8 - fatiguePenalty * 0.45,
        }
    end
    if weapon then
        if weapon.ranged then
            if weapon.ammo <= 0 and hasReloadAmmo(inventory, weapon) then
                actions[#actions + 1] = { kind = "reload", score = distance > 3 and 62 or 24 }
            elseif weapon.ammo > 0 and not commands.holdFire and target.visible
                and utility.sameFloor(actor, target.actor)
                and not target.obstructed and not lineBlockedByFriendly(actor, target.actor, player, snapshot) then
                actions[#actions + 1] = {
                    kind = "shoot",
                    score = 54 + math.min(weapon.range, distance) * 2
                        + readiness.combatSkill * 2.2 + readiness.weaponQuality * 8
                        - pressure * 4 - readiness.panic * 5
                        - readiness.stress * 0.08,
                }
            end
            if distance < (utility.config("combatFirearmMinDistance") or 2.2) then
                actions[#actions + 1] = {
                    kind = "backstep",
                    score = 58 + pressure * 8 + readiness.nimble * 1.5
                        + readiness.fitness - readiness.footing.crowd * 4,
                }
            end
        elseif distance <= (utility.config("combatMeleeDistance") or 1.7) then
            actions[#actions + 1] = {
                kind = "melee",
                score = 58 + weapon.damage * 5 + readiness.combatSkill * 1.8
                    + readiness.strength * 0.6 + readiness.weaponQuality * 8
                    - pressure * 3 - fatiguePenalty
                    - math.max(0, readiness.weaponCost - 1.5) * 3,
            }
        elseif isolatedFront and readiness.staminaCritical ~= true then
            -- A melee companion used to kite laterally forever whenever the
            -- target was just outside swing range. Advance under a ready guard
            -- when the lane is safe; the next decision tick switches to the
            -- ordinary melee/shove exchange at combatMeleeDistance.
            actions[#actions + 1] = {
                kind = "approach",
                score = 61 + weapon.damage * 3 + readiness.combatSkill * 1.2
                    + readiness.nimble * 0.7 + readiness.confidence * 0.08
                    - math.max(0, distance - 2) * 2 - pressure * 3,
            }
        else
            actions[#actions + 1] = {
                kind = "kite",
                score = 42 + target.score * 0.2 + readiness.nimble * 1.4
                    + readiness.fitness * 0.7 + math.min(10, readiness.escapeClearance)
                    - readiness.footing.crowd * 4 - (readiness.footing.tree and 8 or 0),
            }
        end
    else
        actions[#actions + 1] = { kind = distance <= 1.35 and "shove" or "escape", score = 58 + pressure * 8 }
    end
    return utility.sortByScoreDescending(actions), distance
end

local function passiveMayFight(target, player, snapshot)
    local emergency = U().config("combatStealthEmergencyRadius") or 1.5
    if target.attacking or (target.distanceSq or math.huge) <= emergency * emergency then return true end
    if player and U().distanceSq(player, target.actor) <= 4 and snapshot.player and snapshot.player.immediateThreats > 0 then return true end
    if type(snapshot.allies) == "table" then
        for _, ally in ipairs(snapshot.allies) do
            if U().distanceSq(ally.actor, target.actor) <= 2.25 then return true end
        end
    end
    return false
end


local function closeDefenseMayFight(actor, target, player, snapshot)
    local radius = U().config("combatCloseDefenseRadius") or 5
    local radiusSq = radius * radius
    if target.attacking or (target.distanceSq or U().distanceSq(actor, target.actor)) <= radiusSq then
        return true
    end
    if player and U().sameFloor(player, target.actor)
        and U().distanceSq(player, target.actor) <= radiusSq then return true end
    for _, ally in ipairs(snapshot.allies or {}) do
        if ally.actor and U().sameFloor(ally.actor, target.actor)
            and U().distanceSq(ally.actor, target.actor) <= radiusSq then return true end
    end
    return false
end

local function doctrineMayFight(actor, target, player, snapshot, commands)
    local doctrine = commands.combatDoctrine
    if doctrine == nil then
        doctrine = commands.combatMode == "passive" and "stealth"
            or commands.combatMode == "aggressive" and "weapons_free"
            or commands.weaponPriority == "firearm" and "ranged_support"
            or "close_defense"
    end
    if doctrine == "stealth" then return passiveMayFight(target, player, snapshot) end
    if doctrine == "close_defense" then
        return closeDefenseMayFight(actor, target, player, snapshot)
    end
    if doctrine == "ranged_support" then
        return target.visible == true and target.obstructed ~= true
    end
    local radius = U().config("combatWeaponsFreeRadius") or 14
    return target.attacking == true
        or (target.distanceSq or U().distanceSq(actor, target.actor)) <= radius * radius
end

local function selectDoctrineTarget(actor, scored, player, snapshot, commands)
    for _, target in ipairs(scored) do
        if doctrineMayFight(actor, target, player, snapshot, commands) then return target end
    end
    return nil
end

local function clearAimPreparation(state)
    state.aimTarget = nil
    state.aimStartedAt = nil
    state.aimRequiredMs = nil
end

local function prepareRangedShot(actor, state, snapshot, target, weapon, readiness,
        player, commands, now)
    if not weapon or weapon.ranged ~= true or weapon.equipped ~= true
        or weapon.ammo <= 0 or commands.holdFire == true
        or not target or target.visible ~= true or target.obstructed == true
        or readiness.immediate > 0
        or lineBlockedByFriendly(actor, target.actor, player, snapshot) then
        clearAimPreparation(state)
        return false, "aim_not_required"
    end
    local distance = math.sqrt(target.distanceSq or U().distanceSq(actor, target.actor))
    if distance < (U().config("combatFirearmMinDistance") or 2.2) + 0.5 then
        clearAimPreparation(state)
        return false, "aim_not_safe"
    end
    if state.aimTarget ~= target.actor then
        state.aimTarget = target.actor
        state.aimStartedAt = now
        state.aimRequiredMs = U().clamp(
            (U().config("combatAimBaseMs") or 650)
                - readiness.combatSkill * (U().config("combatAimSkillReductionMs") or 55)
                + readiness.panic * (U().config("combatAimPanicPenaltyMs") or 170)
                + readiness.stress * (U().config("combatAimStressPenaltyMs") or 4)
                + math.max(0, distance - 5) * 18,
            U().config("combatAimMinimumMs") or 220,
            U().config("combatAimMaximumMs") or 1800)
    end
    local elapsed = now - (tonumber(state.aimStartedAt) or now)
    if elapsed >= (tonumber(state.aimRequiredMs) or 0) then return false, "aim_settled" end
    local accepted = true
    if state.lastAction ~= "aiming" then
        accepted = U().move(actor, "walk", {
            action = "ready_weapon",
            facingTarget = target.actor,
            target = target.actor,
            deliberateAim = true,
            requiredMs = state.aimRequiredMs,
        })
    end
    if accepted ~= true then
        clearAimPreparation(state)
        return false, "aim_rejected"
    end
    return true, "aiming"
end

local function executeRetreat(actor, snapshot, target, survivalCritical)
    local utility = U()
    local remembered, retreatPlan
    if SC.Navigation and type(SC.Navigation.retreatTarget) == "function" then
        remembered, retreatPlan = SC.Navigation.retreatTarget(actor, snapshot)
    end
    local escape = snapshot.escapeSquares and snapshot.escapeSquares[1]
    if remembered and retreatPlan and (tonumber(retreatPlan.danger) or 0) >= 5
        and escape and (tonumber(escape.danger) or 0) == 0 then remembered = nil end
    if remembered and SC.Navigation and type(SC.Navigation.request) == "function" then
        return SC.Navigation.request(actor, remembered, "jog", {
            action = "combat_retreat",
            snapshot = snapshot,
            awayFrom = target and target.actor,
            urgent = true,
            escapeSpeedOverride = true,
            survivalCritical = survivalCritical == true,
            retreatPlan = retreatPlan,
        })
    end
    if escape and SC.Navigation and type(SC.Navigation.request) == "function" then
        return SC.Navigation.request(actor, escape.square, "jog", {
            action = "combat_retreat",
            snapshot = snapshot,
            awayFrom = target and target.actor,
            urgent = true,
            escapeSpeedOverride = true,
            survivalCritical = survivalCritical == true,
        })
    end
    if escape then
        local accepted = utility.move(actor, "jog", {
            action = "combat_retreat",
            targetSquare = escape.square,
            enginePath = true,
            snapshot = snapshot,
            awayFrom = target and target.actor,
            urgent = true,
            escapeSpeedOverride = true,
            survivalCritical = survivalCritical == true,
        })
        return accepted == true, accepted and "retreating" or "retreat_rejected"
    end
    local threat = target and target.actor or nil
    if threat == nil then
        local immediate = snapshot and snapshot.immediateAttackers
            and snapshot.immediateAttackers[1] or nil
        local known = immediate or (snapshot and snapshot.threats and snapshot.threats[1])
        threat = type(known) == "table" and known.actor or known
    end
    if threat == nil then return false, "retreat_direction_unavailable" end
    local accepted = utility.move(actor, "jog", {
        action = "corner_escape",
        awayFrom = threat,
        lateral = true,
        collisionRecovery = true,
        urgent = true,
        escapeSpeedOverride = true,
        survivalCritical = survivalCritical == true,
    })
    return accepted == true, accepted and "corner_escape" or "retreat_rejected"
end

local function executeRetreatCounter(actor, player, snapshot, target, weapon, commands,
        overrun, state, now)
    if not target or not target.actor then return false end
    local utility = U()
    local cooldown = utility.config("combatRetreatCounterCooldownMs") or 1100
    if now - (tonumber(state.lastRetreatCounterAt) or 0) < cooldown then return false end
    local immediate = tonumber(snapshot.closeImmediateCount)
        or tonumber(snapshot.immediateCount) or #(snapshot.immediateAttackers or {})
    if snapshot.encircled == true
        or immediate > (utility.config("combatTacticalRetreatMaxImmediate") or 1)
        or (tonumber(overrun.risk) or math.huge)
            > (utility.config("combatRetreatCoverFireMaxRisk") or 76) then return false end

    local distance = math.sqrt(target.distanceSq or utility.distanceSq(actor, target.actor))
    local accepted, action
    if distance <= (utility.config("combatShoveDistance") or 1.35)
        and utility.sameFloor(actor, target.actor) then
        -- One controlled shove buys the next movement decision room to turn.
        accepted = utility.move(actor, "walk", {
            action = "shove", target = target.actor, retreatCounter = true,
        })
        action = "retreat_shove"
    elseif weapon and weapon.equipped and weapon.ranged and weapon.ammo > 0
        and commands.holdFire ~= true and commands.combatDoctrine ~= "stealth"
        and distance >= (utility.config("combatRetreatCoverFireMinDistance") or 3.0)
        and distance <= math.max(1, tonumber(weapon.range) or 1)
        and target.visible == true and target.obstructed ~= true
        and utility.sameFloor(actor, target.actor)
        and not lineBlockedByFriendly(actor, target.actor, player, snapshot) then
        -- This is deliberate bounding fire, not simultaneous sliding and
        -- shooting: fire once, then the next decision resumes the escape path.
        accepted = utility.move(actor, "walk", {
            action = "attack_firearm", weapon = weapon.item, target = target.actor,
            friendlyFireChecked = true, lineOfSightChecked = true,
            retreatCounter = true, combatDoctrine = commands.combatDoctrine,
        })
        action = "retreat_cover_fire"
    end
    if accepted ~= true then return false end
    state.lastRetreatCounterAt = now
    if action == "retreat_cover_fire" then claimTarget(target.actor, actor, now) end
    return true, action
end

local function execute(actor, player, snapshot, target, weapon, action, commands)
    local utility = U()
    local targetActor = target and target.actor
    if action.kind == "retreat" or action.kind == "escape" then
        return executeRetreat(actor, snapshot, target, action.kind == "escape")
    end
    if weapon and not weapon.equipped and action.kind ~= "shove" and action.kind ~= "stomp" then
        if not equipWeapon(actor, weapon.item, { nextAction = action.kind }) then
            return false, "equip_rejected"
        end
        return true, "equip"
    end
    local accepted
    if action.kind == "reload" then
        accepted = utility.move(actor, "walk", { action = "reload", weapon = weapon.item, target = targetActor })
    elseif action.kind == "shoot" then
        if not utility.sameFloor(actor, targetActor) then return false, "different_floor" end
        accepted = utility.move(actor, "walk", {
            action = "attack_firearm", weapon = weapon.item, target = targetActor,
            friendlyFireChecked = true, lineOfSightChecked = true,
            combatDoctrine = commands and commands.combatDoctrine,
        })
    elseif action.kind == "melee" then
        if not utility.sameFloor(actor, targetActor) then return false, "different_floor" end
        accepted = utility.move(actor, "walk", { action = "attack_melee", weapon = weapon.item, target = targetActor })
    elseif action.kind == "shove" then
        if not utility.sameFloor(actor, targetActor) then return false, "different_floor" end
        accepted = utility.move(actor, "walk", { action = "shove", target = targetActor })
    elseif action.kind == "stomp" then
        if not utility.sameFloor(actor, targetActor) then return false, "different_floor" end
        accepted = utility.move(actor, "walk", { action = "stomp", target = targetActor, floorAttack = true })
    elseif action.kind == "approach" then
        if not utility.sameFloor(actor, targetActor) then return false, "different_floor" end
        local ax, ay = utility.position(actor)
        local tx, ty = utility.position(targetActor)
        if ax == nil or tx == nil then return false, "approach_position_unavailable" end
        accepted = utility.move(actor, "walk", {
            action = "combat_approach",
            dx = tx - ax,
            dy = ty - ay,
            target = targetActor,
            facingTarget = targetActor,
            keepFacing = true,
            weaponReady = true,
            tacticalStrafe = true,
        })
    elseif action.kind == "backstep" then
        accepted = utility.move(actor, "walk", { action = "backstep", target = targetActor, keepFacing = true })
    elseif action.kind == "kite" then
        accepted = utility.move(actor, "walk", { action = "lateral_kite", target = targetActor, keepFacing = true })
    else
        return false, "unknown_action"
    end
    if not accepted then return false, action.kind .. "_rejected" end
    return true, action.kind
end

local function vehicleCombat(actor, player, snapshot, target, weapon, inventory, commands)
    local utility = U()
    local doctrine = commands.combatDoctrine or "close_defense"
    if doctrine ~= "ranged_support" and doctrine ~= "weapons_free" then
        utility.stop(actor)
        return true, "vehicle_holding_fire"
    end
    if not weapon or weapon.ranged ~= true then
        utility.stop(actor)
        return true, "vehicle_no_firearm"
    end
    if not weapon.equipped then
        local accepted = equipWeapon(actor, weapon.item, { nextAction = "shoot" })
        return accepted == true, accepted and "equip" or "equip_rejected"
    end
    if weapon.ammo <= 0 then
        if not hasReloadAmmo(inventory, weapon) then
            utility.stop(actor)
            return true, "vehicle_out_of_ammo"
        end
        local accepted = utility.move(actor, "walk", {
            action = "reload", weapon = weapon.item, target = target.actor,
        })
        return accepted == true, accepted and "reload" or "reload_rejected"
    end
    local distance = math.sqrt(target.distanceSq or utility.distanceSq(actor, target.actor))
    if distance > math.max(1, tonumber(weapon.range) or 1)
        or target.visible ~= true or target.obstructed == true then
        utility.stop(actor)
        return true, "vehicle_target_out_of_arc"
    end
    if lineBlockedByFriendly(actor, target.actor, player, snapshot) then
        utility.stop(actor)
        return true, "vehicle_friendly_in_fire_lane"
    end
    if not SC.Vehicle or type(SC.Vehicle.claimPassengerShot) ~= "function" then
        return false, "vehicle_fire_adapter_unavailable"
    end
    local claimed, claimReason = SC.Vehicle.claimPassengerShot(actor, target.actor, doctrine)
    if not claimed then
        utility.stop(actor)
        return true, claimReason
    end
    claimTarget(target.actor, actor, utility.nowMs())
    local accepted = utility.move(actor, "walk", {
        action = "attack_firearm",
        weapon = weapon.item,
        target = target.actor,
        friendlyFireChecked = true,
        lineOfSightChecked = true,
        vehicleFireChecked = true,
        combatDoctrine = doctrine,
    })
    return accepted == true, accepted and "vehicle_shoot" or "vehicle_shoot_rejected"
end

function Combat.update(actor, player, runtime)
    local utility = U()
    if not utility or not utility.isValidActor(actor) then return false, "invalid_actor" end
    local rootRuntime = utility.actorState(actor, runtime)
    local snapshot = rootRuntime.senses and rootRuntime.senses.current or rootRuntime.snapshot
    local state = stateFor(actor)
    if type(snapshot) ~= "table" then snapshot = {} end
    snapshot.threats = snapshot.threats or {}
    snapshot.allies = snapshot.allies or {}
    snapshot.escapeSquares = snapshot.escapeSquares or {}
    local commands = commandState(actor)
    local now = utility.nowMs()
    confirmRecentKill(actor, state, commands, now)
    local scored = Combat.scoreTargets(actor, player, snapshot, state.target)
    addNearbyGrounded(actor, scored)
    local followUpHandled, followUpReason = tryShoveFollowUp(
        actor, state, snapshot, now)
    if followUpHandled then
        state.active = true
        state.lastAction = followUpReason
        state.lastActionAt = now
        if followUpReason == "stomp_after_shove" then
            recordOffensiveAction(actor, state, commands, state.target, now, false, snapshot)
        end
        rootRuntime.combatTarget = state.shoveFollowUp and state.shoveFollowUp.target
            or state.target
        rootRuntime.combatAction = followUpReason
        return true, followUpReason
    end
    if #scored == 0 then
        if state.active then utility.stop(actor) end
        state.active, state.target, state.lastAction = false, nil, nil
        state.retreating = false
        clearAimPreparation(state)
        utility.call(actor, "setCompanionAimTarget", nil)
        state.lastOffensiveTarget, state.lastOffensiveAt = nil, nil
        clearEngagement(state)
        rootRuntime.combatTarget = nil
        rootRuntime.combatOverrun = nil
        rootRuntime.combatReadiness = nil
        state.readiness = nil
        return false, "no_threat"
    end
    if SC.Medical and type(SC.Medical.isDowned) == "function" and SC.Medical.isDowned(actor) then
        utility.stop(actor)
        state.retreating = false
        clearAimPreparation(state)
        return false, "downed"
    end

    local target = selectDoctrineTarget(actor, scored, player, snapshot, commands)
    if not target then
        if state.active then utility.stop(actor) end
        state.active, state.target = false, nil
        state.retreating = false
        clearAimPreparation(state)
        utility.call(actor, "setCompanionAimTarget", nil)
        state.readiness, state.overrun = nil, nil
        clearEngagement(state)
        return false, "no_credible_target"
    end
    -- Continuously point the actor at the engaged target so the native swing's
    -- hit arc (getDirectionAngle) lands, like a player's mouse aim. Cleared above
    -- when there is no credible target.
    utility.call(actor, "setCompanionAimTarget", target.actor)
    local distance = math.sqrt(target.distanceSq or utility.distanceSq(actor, target.actor))
    local vehicle, vehicleOk = utility.call(actor, "getVehicle")
    local seated = vehicleOk and vehicle ~= nil
    -- The ranged_support doctrine means "prefer the firearm" whether or not the
    -- companion is seated. Previously only the seated branch honored the
    -- doctrine, so an on-foot companion fell back to weaponPriority. When that
    -- priority was stale (for example a team doctrine change that did not
    -- resync the per-actor priority), chooseWeapon's close-range firearm
    -- penalty made an approaching zombie flip the selection to a melee weapon,
    -- so a companion set to ranged combat drew and swung melee instead of
    -- firing. weapons_free stays best-weapon on foot but firearm-only seated,
    -- where melee is not an option.
    local preference = commands.weaponPriority
    if commands.combatDoctrine == "ranged_support" then
        preference = "firearm"
    elseif seated and commands.combatDoctrine == "weapons_free" then
        preference = "firearm"
    end
    local weapon, inventory = chooseWeapon(actor, preference, distance, snapshot.pressure or 0)
    if seated then
        clearAimPreparation(state)
        local ok, reason = vehicleCombat(
            actor, player, snapshot, target, weapon, inventory, commands)
        if ok then
            state.active = true
            state.target = target.actor
            state.targetScore = target.score
            state.lastActionAt = now
            state.lastAction = reason
            state.retreating = false
            if reason == "vehicle_shoot" then
                recordOffensiveAction(actor, state, commands, target.actor, now, true, snapshot)
            end
            rootRuntime.combatTarget = target.actor
            rootRuntime.combatAction = reason
        end
        return ok, reason
    end
    local overrun = Combat.assessOverrun(actor, snapshot, weapon, commands)
    rootRuntime.combatOverrun = overrun
    rootRuntime.combatReadiness = overrun.readiness
    state.readiness = overrun.readiness
    state.overrun = overrun
    if overrun.overrun then state.retreatUntil = now + (utility.config("combatOverrunHoldMs") or 2600) end
    local keepRetreating = now < (state.retreatUntil or 0)
        and overrun.risk >= (utility.config("combatOverrunRecoveryRisk") or 38)
    if overrun.overrun or keepRetreating then
        clearAimPreparation(state)
        local countered, counterAction = executeRetreatCounter(actor, player, snapshot,
            target, weapon, commands, overrun, state, now)
        if countered then
            enterRetreat(actor, state, commands, now, true, snapshot)
            recordOffensiveAction(actor, state, commands, target.actor, now, false, snapshot)
            state.active = true
            state.target = target.actor
            state.lastAction = counterAction
            state.lastActionAt = now
            rootRuntime.combatTarget = target.actor
            rootRuntime.combatAction = counterAction
            return true, counterAction
        end
        local ok, reason = executeRetreat(actor, snapshot, target, true)
        if ok then
            enterRetreat(actor, state, commands, now, true, snapshot)
            state.active = true
            state.target = target.actor
            state.lastAction = "overrun_retreat"
            state.lastActionAt = now
            rootRuntime.combatTarget = target.actor
            rootRuntime.combatAction = "retreat"
        end
        return ok, ok and "overrun_retreat" or reason
    end

    if commands.combatDoctrine == "stealth" and not passiveMayFight(target, player, snapshot) then
        if (snapshot.pressure or 0) > 0 then
            local ok, reason = executeRetreat(actor, snapshot, target)
            if ok then
                enterRetreat(actor, state, commands, now, false, snapshot)
                state.active = true
                state.target = target.actor
                state.lastAction = "retreat"
            end
            return ok, reason
        end
        if state.active then utility.stop(actor) end
        state.active = false
        state.retreating = false
        return false, "passive"
    end

    local readiness = overrun.readiness
    local actions = actionUtilities(actor, player, snapshot, target, weapon, inventory,
        commands, readiness)
    if commands.combatDoctrine == "weapons_free" then
        for _, action in ipairs(actions) do
            if action.kind == "shoot" or action.kind == "melee" then action.score = action.score + 12 end
        end
        utility.sortByScoreDescending(actions)
    elseif commands.combatDoctrine == "stealth" then
        for _, action in ipairs(actions) do
            if action.kind == "retreat" then action.score = action.score + 20 end
        end
        utility.sortByScoreDescending(actions)
    end
    local chosen = actions[1]
    if not chosen then return false, "no_action" end

    if chosen.kind == "shoot" then
        local aiming, aimReason = prepareRangedShot(actor, state, snapshot, target,
            weapon, readiness, player, commands, now)
        if aiming then
            state.active = true
            state.target = target.actor
            state.targetScore = target.score
            state.lastActionAt = now
            state.lastAction = aimReason
            state.retreating = false
            rootRuntime.combatTarget = target.actor
            rootRuntime.combatAction = aimReason
            return true, aimReason
        end
    else
        clearAimPreparation(state)
    end

    local ok, reason = execute(actor, player, snapshot, target, weapon, chosen, commands)
    if not ok then
        Combat.noteRejection(actor, state, rootRuntime, chosen.kind, reason,
            target.actor, distance, weapon)
        return false, reason
    end
    clearRejection(state, rootRuntime)
    if chosen.kind == "shoot" or chosen.kind == "melee"
        or chosen.kind == "shove" or chosen.kind == "stomp" then
        claimTarget(target.actor, actor, now)
        clearAimPreparation(state)
    end
    if chosen.kind == "retreat" or chosen.kind == "escape" then
        enterRetreat(actor, state, commands, now, chosen.kind == "escape", snapshot)
    else
        state.retreating = false
    end
    if reason == "shoot" or reason == "melee" or reason == "shove" or reason == "stomp" then
        recordOffensiveAction(actor, state, commands, target.actor, now, true, snapshot)
    end
    state.active = true
    state.target = target.actor
    state.targetScore = target.score
    state.lastActionAt = now
    state.lastAction = reason
    if chosen.kind == "shove" then
        state.shoveFollowUp = {
            target = target.actor,
            startedAt = state.lastActionAt,
            expires = state.lastActionAt
                + (utility.config("combatShoveFollowupWindowMs") or 1800),
        }
    elseif chosen.kind == "stomp" then
        state.shoveFollowUp = nil
    end
    rootRuntime.combatTarget = target.actor
    rootRuntime.combatAction = chosen.kind
    return true, reason
end

function Combat.peek(actor)
    return actor and states[actor] or nil
end

function Combat.reset(actor)
    if actor then
        local state = states[actor]
        if state and state.active then U().stop(actor) end
        states[actor] = nil
    else
        states = setmetatable({}, { __mode = "k" })
        targetClaims = setmetatable({}, { __mode = "k" })
        lastGroupCombatBarkAt = -math.huge
    end
end

return Combat
