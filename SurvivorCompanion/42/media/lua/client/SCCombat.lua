-- SPDX-License-Identifier: MIT

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
if not SC.GameplayUtil and type(require) == "function" then pcall(require, "SCGameplayUtil") end

SC.Combat = SC.Combat or {}
local Combat = SC.Combat
local states = setmetatable({}, { __mode = "k" })
local targetClaims = setmetatable({}, { __mode = "k" })
local actorClaims = setmetatable({}, { __mode = "k" })
local retreatPlans = {}
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
        state = {
            active = false, target = nil, lastActionAt = 0,
            motionTracks = setmetatable({}, { __mode = "k" }),
        }
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

-- Drop this actor's engagement lease(s) when it abandons a target, so the longer
-- lease (review 4.4) does not keep deterring the rest of the squad from a target
-- its owner has left. Only the owner can release its own claim. releaseActorClaims
-- is keyed on ownership, not on engagementTarget, because a claim can be taken on a
-- committed action whose engagement bookkeeping did not run.
local function combatCohortKey(actor, player)
    local commands = commandState(actor)
    if commands.recruited == true then
        return "party:" .. tostring(U().idOf(player or actor))
    end
    if SC.Factions and type(SC.Factions.affiliation) == "function" then
        local ok, affiliation = pcall(SC.Factions.affiliation, actor)
        if ok and type(affiliation) == "table" and affiliation.factionId then
            return "faction:" .. tostring(affiliation.factionId)
        end
    end
    if player ~= nil then return "party:" .. tostring(U().idOf(player)) end
    return "actor:" .. tostring(U().idOf(actor))
end

local function releaseClaim(target, actor)
    local container = target and targetClaims[target] or nil
    if type(container) == "table" and type(container.cohorts) == "table" then
        for cohort, claim in pairs(container.cohorts) do
            local changed = false
            for _, role in ipairs({ "primary", "support" }) do
                if claim[role] and claim[role].actor == actor then
                    claim[role] = nil
                    changed = true
                end
            end
            if changed and claim.primary == nil and claim.support == nil then
                container.cohorts[cohort] = nil
            end
        end
    end
    local reverse = actorClaims[actor]
    if reverse and reverse.target == target then actorClaims[actor] = nil end
end

local function releaseActorClaims(actor)
    if actor == nil then return end
    local reverse = actorClaims[actor]
    if reverse then releaseClaim(reverse.target, actor) end
end

local function clearEngagement(state, actor)
    releaseActorClaims(actor)
    state.engagementTarget = nil
    state.engagementStartedAt = nil
    state.engagementActionCount = 0
    state.engagementAnnounced = false
    state.struggleAnnounced = false
end

local function prepareEngagement(state, actor, target, now)
    if state.engagementTarget == target then return end
    if state.engagementTarget ~= nil then releaseClaim(state.engagementTarget, actor) end
    state.engagementTarget = target
    state.engagementStartedAt = now
    state.engagementActionCount = 0
    state.engagementAnnounced = false
    state.struggleAnnounced = false
end

local function recordOffensiveAction(actor, state, commands, target, now, announceEngage, snapshot)
    if target == nil then return end
    prepareEngagement(state, actor, target, now)
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
    if state.engagementTarget == target then clearEngagement(state, actor) end
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

local function cohortClaim(target, cohort, now)
    local container = target and targetClaims[target] or nil
    local claim = type(container) == "table" and type(container.cohorts) == "table"
        and container.cohorts[cohort] or nil
    if type(claim) ~= "table" then return nil end
    for _, role in ipairs({ "primary", "support" }) do
        local value = claim[role]
        if value and ((tonumber(value.untilAt) or 0) <= now or U().isDead(value.actor)
            or U().isDead(target)) then
            local reverse = value.actor and actorClaims[value.actor] or nil
            if reverse and reverse.target == target and reverse.cohort == cohort then
                actorClaims[value.actor] = nil
            end
            claim[role] = nil
        end
    end
    if claim.primary == nil and claim.support ~= nil then
        claim.primary, claim.support = claim.support, nil
        local promoted = actorClaims[claim.primary.actor]
        if promoted and promoted.target == target and promoted.cohort == cohort then
            promoted.role = "primary"
        end
    end
    if claim.primary == nil and claim.support == nil then
        container.cohorts[cohort] = nil
        return nil
    end
    return claim
end

local function activeClaim(target, actor, now, cohort)
    local claim = cohortClaim(target, cohort or combatCohortKey(actor), now)
    if not claim then return nil end
    if claim.primary and claim.primary.actor ~= actor then return claim.primary end
    if claim.support and claim.support.actor ~= actor then return claim.support end
    return nil
end

-- Combat engagement lease (review 4.4). A brief claim (~450ms) expired between an
-- actor's combat decisions once a party grew, so companions oscillated targets:
-- the claim lapsed, a peer grabbed the same zombie, then the original owner
-- re-claimed it, and so on. The lease now spans the worst-case revisit latency
-- (~2s) and is refreshed on every offensive action against the target, so a
-- committed attacker holds its target while it is engaging and alive, and the
-- lease is released the moment the owner switches away, disengages, or dies.
local function claimTarget(target, actor, now, cohort, requestedRole, phase, distance)
    if target == nil then return nil end
    cohort = cohort or (stateFor(actor).cohortKey) or combatCohortKey(actor)
    local container = targetClaims[target]
    if type(container) ~= "table" or type(container.cohorts) ~= "table" then
        container = { cohorts = {} }
        targetClaims[target] = container
    end
    local claim = cohortClaim(target, cohort, now)
    if not claim then
        claim = {}
        container.cohorts[cohort] = claim
    end
    local current = actorClaims[actor]
    if current and (current.target ~= target or current.cohort ~= cohort) then
        releaseClaim(current.target, actor)
    end
    local reverse = actorClaims[actor]
    local role = requestedRole or (reverse and reverse.target == target
        and reverse.cohort == cohort and reverse.role or nil)
    if role ~= "primary" and role ~= "support" then
        if claim.primary == nil or claim.primary.actor == actor then role = "primary"
        elseif claim.support == nil or claim.support.actor == actor then role = "support"
        else role = "reserve" end
    end
    if role == "primary" and claim.primary and claim.primary.actor ~= actor then
        local old = claim.primary
        local advantage = (tonumber(old.distance) or math.huge) - (tonumber(distance) or math.huge)
        local committed = old.phase == "attack" or old.phase == "committed"
            or old.phase == "aim" or old.phase == "aiming"
        if committed or advantage < (U().config("combatTargetPrimaryChallengeDistance") or 0.75) then
            role = claim.support == nil and "support" or "reserve"
        else
            actorClaims[old.actor] = nil
        end
    end
    if role == "reserve" then
        actorClaims[actor] = { target = target, cohort = cohort, role = role }
        return role, claim
    end
    local previous = claim[role]
    if previous and previous.actor ~= actor then actorClaims[previous.actor] = nil end
    claim[role] = {
        actor = actor,
        untilAt = now + (U().config("combatEngagementLeaseMs") or 2000),
        phase = phase or "tracking",
        distance = distance,
    }
    actorClaims[actor] = { target = target, cohort = cohort, role = role }
    return role, claim
end

local function boolCall(value, methodName, ...)
    local result, ok = U().call(value, methodName, ...)
    return ok and result == true
end

-- A native player swing owns locomotion until its animation exits. Re-running
-- spacing utility during that window made the companion submit approach and
-- backstep pulses that the actor correctly rejected as movement_locked. Apart
-- from noisy logs, the next accepted pulse could reverse the previous one and
-- create the observed approach/backstep loop. Treat the swing as a short action
-- lease, just as keyboard input is ignored while a normal player's attack plays.
local function attackInProgress(actor)
    if boolCall(actor, "isAttackStarted")
        or boolCall(actor, "isPerformingAttackAnimation") then return true end
    local stateName, stateOk = U().call(actor, "getCompanionActionStateName")
    if not stateOk or stateName == nil then return false end
    local lower = string.lower(tostring(stateName))
    return string.find(lower, "melee", 1, true) ~= nil
        or string.find(lower, "attack", 1, true) ~= nil
        or string.find(lower, "shove", 1, true) ~= nil
        or string.find(lower, "stomp", 1, true) ~= nil
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
    local jammed = ranged and boolCall(item, "isJammed") or false
    local condition = numberCall(item, "getCondition", 100)
    local conditionMax = math.max(1, numberCall(item, "getConditionMax", 100))
    local ammo = numberCall(item, "getCurrentAmmoCount", -1)
    if ammo < 0 then ammo = numberCall(item, "getAmmoCount", ranged and 0 or 1) end
    local maxAmmo = numberCall(item, "getMaxAmmo", ranged and 1 or 1)
    local damage = numberCall(item, "getMaxDamage", 1)
    local range = numberCall(item, "getMaxRange", ranged and 8 or 1.5)
    local minRange = math.max(0, numberCall(item, "getMinRange", 0))
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
        jammed = jammed,
        condition = condition,
        conditionRatio = condition / conditionMax,
        ammo = ammo,
        maxAmmo = maxAmmo,
        damage = damage,
        range = range,
        minRange = minRange,
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

-- Return the same tolerant melee band used by the combat decision loop. Other
-- combat owners (notably hostile faction residents and the final native attack
-- gate) must not fall back to one generic distance: a cleaver, spear and axe do
-- not begin a valid player swing from the same range.
function Combat.meleeRange(actor, item)
    local weapon = weaponRecord(item)
    if not weapon or weapon.ranged then return nil, nil, weapon end
    local reachVal = select(1, U().call(item, "getMaxRange", actor))
    local reachMax = tonumber(reachVal) or tonumber(weapon.range) or 1.5
    local modVal = select(1, U().call(item, "getRangeMod", actor))
    local rangeMod = tonumber(modVal) or 1.0
    local effectiveMax = reachMax * (rangeMod > 0 and rangeMod or 1.0)
    local swingMin = math.max(0.15, (tonumber(weapon.minRange) or 0)
        - (U().config("combatMeleeInnerTolerance") or 0.15))
    local swingMax = math.max(swingMin + 0.2,
        effectiveMax + (U().config("combatMeleeOuterTolerance") or 0.08))
    return swingMin, swingMax, weapon
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

-- Tolerate a module prefix difference (e.g. "Base.M9Clip" vs "M9Clip") when
-- comparing an inventory item's type against a weapon's magazine/ammo type.
local function ammoTypeMatches(candidateType, wantedType)
    if candidateType == nil or wantedType == nil then return false end
    if candidateType == wantedType then return true end
    local function short(value) return string.match(value, "%.([%w_]+)$") or value end
    return short(candidateType) == short(wantedType)
end

local function hasReloadAmmo(inventory, weapon)
    local utility = U()
    if not inventory or not weapon or not weapon.ranged then return false end
    local item = weapon.item
    -- Build 42 firearms reload from a magazine of the weapon's magazine type that
    -- still holds rounds, or from loose rounds of the weapon's ammo type (revolvers,
    -- shotguns, bolt-actions). Match ONLY by those exact types: an item whose name
    -- merely contains "ammo"/"bullets"/"shells" is not proof of compatibility and
    -- was driving reloads with the wrong calibre or an empty magazine (repeated
    -- failed reload decisions).
    local magType = select(1, utility.call(item, "getMagazineType"))
    magType = magType ~= nil and tostring(magType) or nil
    local ammoType = select(1, utility.call(item, "getAmmoType"))
    ammoType = ammoType ~= nil and tostring(ammoType) or nil
    if (magType == nil or magType == "") and (ammoType == nil or ammoType == "") then
        return false
    end
    for _, candidate in ipairs(utility.inventoryItems(inventory, 90)) do
        local candidateType = utility.itemType(candidate)
        if magType and magType ~= "" and ammoTypeMatches(candidateType, magType) then
            -- A magazine only enables a reload if it actually holds rounds.
            local countValue = select(1, utility.call(candidate, "getCurrentAmmoCount"))
            local count = tonumber(countValue)
            if (count or 0) > 0 then return true end
        elseif ammoType and ammoType ~= "" and ammoTypeMatches(candidateType, ammoType) then
            return true
        end
    end
    return false
end

-- A preferred weapon is only a real option when the next combat pulse can do
-- something useful with it. Empty firearms without compatible ammunition used
-- to suppress carried melee weapons; broken weapons could win for the same
-- reason. A jammed firearm remains operational because unjamming is an action.
local function weaponUsableNow(inventory, weapon)
    if not weapon or (tonumber(weapon.condition) or 0) <= 0 then return false end
    if not weapon.ranged then return true end
    return weapon.jammed == true or (tonumber(weapon.ammo) or 0) > 0
        or hasReloadAmmo(inventory, weapon)
end

local function chooseWeapon(actor, preference, distance, pressure)
    local weapons, inventory = inventoryWeapons(actor)
    local preferredAvailable = false
    if preference == "melee" or preference == "quiet" or preference == "firearm" then
        for _, weapon in ipairs(weapons) do
            local matches = (preference == "firearm" and weapon.ranged)
                or ((preference == "melee" or preference == "quiet") and not weapon.ranged)
            if matches and weaponUsableNow(inventory, weapon) then
                preferredAvailable = true
                break
            end
        end
    end
    local best, bestScore
    for _, weapon in ipairs(weapons) do
        if weaponUsableNow(inventory, weapon) then
            local score = weapon.score
            local matchesPreference = (preference == "firearm" and weapon.ranged)
                or ((preference == "melee" or preference == "quiet") and not weapon.ranged)
            if preferredAvailable and not matchesPreference then score = score - 10000 end
            if weapon.ranged then
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
    end
    return best, inventory
end

local function weaponDistanceBand(distance)
    local firearmMinimum = U().config("combatFirearmMinDistance") or 2.2
    return distance <= 2 and 1 or (distance < firearmMinimum and 2 or 3)
end

local function responsiveWeapon(actor, state, preference, distance, pressure, snapshot, now)
    local snapshotTime = tonumber(snapshot and snapshot.reflexTime)
        or tonumber(snapshot and snapshot.time)
    if snapshotTime == nil then return chooseWeapon(actor, preference, distance, pressure) end
    local primary = select(1, U().call(actor, "getPrimaryHandItem"))
    local distanceBand = weaponDistanceBand(distance)
    local pressureBand = pressure >= 3 and 3 or (pressure >= 2 and 2 or 1)
    local cache = state.weaponCache
    if type(cache) == "table" and now < (cache.expires or 0)
        and cache.snapshotTime == snapshotTime and cache.preference == preference
        and cache.distanceBand == distanceBand and cache.pressureBand == pressureBand
        and cache.primary == primary then
        state.weaponCacheHits = (state.weaponCacheHits or 0) + 1
        if cache.item == nil then return nil, cache.inventory end
        local current = weaponRecord(cache.item)
        if current and current.condition > 0 and current.ammo == cache.ammo
            and current.jammed == cache.jammed
            and weaponUsableNow(cache.inventory, current) then
            current.equipped = primary == cache.item
            return current, cache.inventory
        end
    end
    state.weaponCacheMisses = (state.weaponCacheMisses or 0) + 1
    local weapon, inventory = chooseWeapon(actor, preference, distance, pressure)
    state.weaponCache = {
        snapshotTime = snapshotTime,
        preference = preference,
        distanceBand = distanceBand,
        pressureBand = pressureBand,
        primary = primary,
        item = weapon and weapon.item or nil,
        ammo = weapon and weapon.ammo or nil,
        jammed = weapon and weapon.jammed or nil,
        inventory = inventory,
        expires = now + (U().config("combatTacticalIntervalMs") or 250),
    }
    return weapon, inventory
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

local function sampleTargetMotion(state, actor, target, distance, now)
    state.motionTracks = state.motionTracks or setmetatable({}, { __mode = "k" })
    local utility = U()
    local ax, ay, az = utility.position(actor)
    local tx, ty, tz = utility.position(target)
    if ax == nil or tx == nil then return nil, nil end
    local track = state.motionTracks[target]
    local minimum = utility.config("combatMotionSampleMinimumMs") or 80
    local maximum = utility.config("combatMotionSampleMaximumMs") or 750
    local history = utility.config("combatMotionHistoryMs") or 1500
    local jump = utility.config("combatMotionJumpDistance") or 4
    local closing, tti
    if track then
        local elapsed = now - (track.at or now)
        local actorJump = math.sqrt((ax - track.ax) ^ 2 + (ay - track.ay) ^ 2)
        local targetJump = math.sqrt((tx - track.tx) ^ 2 + (ty - track.ty) ^ 2)
        if elapsed >= minimum and elapsed <= maximum and elapsed <= history
            and actorJump <= jump and targetJump <= jump
            and math.floor(az or 0) == math.floor(track.az or 0)
            and math.floor(tz or 0) == math.floor(track.tz or 0) then
            closing = ((track.distance or distance) - distance) * 1000 / elapsed
            if closing > 0.01 then tti = distance / closing * 1000 end
        end
    end
    if not track or now - (track.at or 0) >= minimum then
        state.motionTracks[target] = {
            ax = ax, ay = ay, az = az, tx = tx, ty = ty, tz = tz,
            distance = distance, at = now,
        }
    end
    return closing, tti
end

function Combat.scoreTargets(actor, player, snapshot, previousTarget)
    local scored = {}
    local utility = U()
    local now = utility.nowMs()
    local state = stateFor(actor)
    local cohort = state.cohortKey or combatCohortKey(actor, player)
    if type(snapshot) ~= "table" or type(snapshot.threats) ~= "table" then return scored end
    for index = 1, math.min(#snapshot.threats, utility.config("perceptionThreatLimit") or 32) do
        local threat = snapshot.threats[index]
        -- Treat the snapshot as a candidate list, not continuing permission to
        -- attack. Revalidate LOS and position every combat pulse so a target that
        -- turns a corner or crosses a closed doorway immediately leaves combat.
        if threat.actor and not utility.isDead(threat.actor)
            and utility.sameFloor(actor, threat.actor) and utility.canSee(actor, threat.actor) then
            local record = utility.copyShallow(threat)
            record.square = utility.squareOf(threat.actor)
            -- Perception snapshots are timestamped and may be up to one scan old.
            -- Use them only as the bounded candidate list: close-combat spacing must
            -- use current geometry or a moving zombie makes the motor alternate
            -- between approach and backstep. Untimestamped synthetic snapshots keep
            -- their explicit distance so external/unit callers retain that contract.
            record.distanceSq = tonumber(snapshot.time) ~= nil
                and utility.distanceSq(actor, threat.actor)
                or tonumber(threat.distanceSq)
                or utility.distanceSq(actor, threat.actor)
            record.distance = math.sqrt(record.distanceSq)
            record.visible = true
            record.obstructed = false
            local score, bearing, facingDot = threatScore(record, actor, player, snapshot)
            local closing, tti = sampleTargetMotion(
                state, actor, threat.actor, record.distance, now)
            local window = utility.config("combatTimeToImpactWindowMs") or 6000
            if tti and tti <= window then
                local maximum = utility.config("combatTimeToImpactScore") or 18
                record.impactScore = maximum * math.max(0, 1 - tti / window)
                score = score + record.impactScore
            end
            record.closingSpeed, record.timeToImpactMs = closing, tti
            if threat.actor == previousTarget then score = score + 8 end
            local claim = cohortClaim(threat.actor, cohort, now)
            local ownPrimary = claim and claim.primary and claim.primary.actor == actor
            local ownSupport = claim and claim.support and claim.support.actor == actor
            local claimed = activeClaim(threat.actor, actor, now, cohort) ~= nil
            if claim and not ownPrimary and not ownSupport then
                if claim.primary and claim.support then
                    score = score - (utility.config("combatTargetClaimPenalty") or 42)
                elseif claim.primary then
                    score = score - 10
                end
            end
            record.score = score
            record.bearing = bearing
            record.facingDot = facingDot
            record.claimedByAlly = claimed
            record.cohortClaim = claim
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
                    and utility.canSee(actor, value)
                    and (boolCall(value, "isOnFloor") or boolCall(value, "isProne")) then
                    seen[value] = true
                    scored[#scored + 1] = {
                        actor = value,
                        square = square,
                        distanceSq = utility.distanceSq(actor, value),
                        visible = true,
                        obstructed = false,
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
        or not U().sameFloor(actor, target) or not U().canSee(actor, target) then
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
        -- A successful shove commonly leaves the zombie just beyond immediate
        -- stomp range. Keep the short-lived follow-up and close on its head rather
        -- than discarding the finisher at the exact moment it becomes available.
        local pursuit = U().config("combatStompPursuitDistance") or 3.25
        if U().distanceSq(actor, target) > pursuit * pursuit then
            state.shoveFollowUp = nil
            return nil, "stomp_followup_out_of_range"
        end
        local headSquare = select(1, U().call(target, "getHeadSquare", actor))
        local ax, ay = U().position(actor)
        local hxValue = headSquare and select(1, U().call(headSquare, "getX")) or nil
        local hyValue = headSquare and select(1, U().call(headSquare, "getY")) or nil
        local hx = tonumber(hxValue)
        local hy = tonumber(hyValue)
        local tx, ty = U().position(target)
        hx, hy = hx or tx, hy or ty
        if ax == nil or ay == nil or hx == nil or hy == nil then
            state.shoveFollowUp = nil
            return nil, "stomp_followup_position_unavailable"
        end
        local accepted = U().move(actor, "walk", {
            action = "combat_approach",
            dx = (hx + (headSquare and 0.5 or 0)) - ax,
            dy = (hy + (headSquare and 0.5 or 0)) - ay,
            target = target, facingTarget = target, keepFacing = true,
            weaponReady = true, stompFollowUp = true,
        })
        if not accepted then return nil, "stomp_followup_approach_rejected" end
        return true, "approach_stomp_after_shove"
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
    local grounded = findGroundedThreat(
        { target }, utility.config("combatStompDistance") or 1.55)
    -- A carried melee weapon is the normal close-range answer. Offering the
    -- generic shove beside it made shove's higher base score beat axes/cleavers.
    -- Firearms may still shove at contact, and unarmed combat still relies on it.
    if not grounded and (not weapon or weapon.ranged)
        and distance <= (utility.config("combatShoveDistance") or 1.35) then
        actions[#actions + 1] = {
            kind = "shove",
            score = 62 + pressure * 7 + readiness.strength * 1.3
                + readiness.nimble * 0.5 - fatiguePenalty * 0.35
                + (isolatedFront and 10 or -8),
        }
    end
    if grounded and readiness.immediate <= 1 and isolatedFront then
        actions[#actions + 1] = {
            kind = "stomp",
            -- A safe grounded target is a fleeting opportunity. Make the finisher
            -- decisive so spacing/retreat utilities cannot moonwalk away from it.
            score = 108 + readiness.strength * 0.8 - fatiguePenalty * 0.45,
        }
    end
    if weapon and not grounded then
        if weapon.ranged then
            if weapon.jammed then
                -- A jammed firearm must be racked clear before it can fire or
                -- reload; prioritise it above every other ranged action.
                actions[#actions + 1] = { kind = "unjam", score = 112 }
            elseif weapon.ammo <= 0 and hasReloadAmmo(inventory, weapon) then
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
        else
            -- Melee spacing is keyed to the weapon's own reach, with a small
            -- hysteresis on both boundaries. The previous implementation added
            -- 0.15 to MinRange and subtracted 0.20 from MaxRange. For a meat
            -- cleaver (0.61..1.00) that left a swing band only ~0.04 tiles wide:
            -- one decision approached, the next backstepped, and neither behaved
            -- like a player. The tolerant band accepts a valid swing before a
            -- moving target crosses the boundary between 125 ms decisions.
            local swingMin, swingMax = Combat.meleeRange(actor, weapon.item)
            swingMin = swingMin or 0.15
            swingMax = swingMax or (utility.config("combatMeleeDistance") or 1.7)
            if distance < swingMin then
                -- Inside the weapon's true minimum reach, use the same defensive
                -- shove a player gets at body contact. It creates space and feeds
                -- the existing stomp follow-up even when a wall makes backstep
                -- impossible. Backstep remains an option when clearance exists.
                if distance <= (utility.config("combatShoveDistance") or 1.35) then
                    actions[#actions + 1] = {
                        kind = "shove",
                        score = 96 + pressure * 7 + readiness.strength
                            - fatiguePenalty * 0.35,
                    }
                end
                actions[#actions + 1] = {
                    kind = "backstep",
                    score = 60 + pressure * 6 + readiness.nimble * 1.5
                        + readiness.fitness - readiness.footing.crowd * 4,
                }
            elseif distance <= swingMax then
                actions[#actions + 1] = {
                    kind = "melee",
                    score = 58 + weapon.damage * 5 + readiness.combatSkill * 1.8
                        + readiness.strength * 0.6 + readiness.weaponQuality * 8
                        - pressure * 3 - fatiguePenalty
                        - math.max(0, readiness.weaponCost - 1.5) * 3,
                }
            elseif isolatedFront and readiness.staminaCritical ~= true then
                -- Beyond swing reach: advance to the outer swing edge under guard;
                -- the next tick resumes the swing/kite exchange from there.
                actions[#actions + 1] = {
                    kind = "approach",
                    score = 61 + weapon.damage * 3 + readiness.combatSkill * 1.2
                        + readiness.nimble * 0.7 + readiness.confidence * 0.08
                        - math.max(0, distance - swingMax - 1) * 2 - pressure * 3,
                }
            else
                actions[#actions + 1] = {
                    kind = "kite",
                    score = 42 + target.score * 0.2 + readiness.nimble * 1.4
                        + readiness.fitness * 0.7 + math.min(10, readiness.escapeClearance)
                        - readiness.footing.crowd * 4 - (readiness.footing.tree and 8 or 0),
                }
            end
        end
    elseif not weapon and not grounded then
        actions[#actions + 1] = { kind = distance <= 1.35 and "shove" or "escape", score = 58 + pressure * 8 }
    end
    if SC.Navigation and type(SC.Navigation.combatVector) == "function" then
        for index = #actions, 1, -1 do
            local action = actions[index]
            if action.kind == "approach" or action.kind == "backstep"
                or action.kind == "kite" then
                local moveX, moveY, steered, vectorReason =
                    SC.Navigation.combatVector(actor, target.actor, action.kind)
                if moveX == nil or moveY == nil then
                    table.remove(actions, index)
                else
                    action.moveX, action.moveY = moveX, moveY
                    action.microSteered = steered == true
                    action.vectorReason = vectorReason
                end
            end
        end
    end
    return utility.sortByScoreDescending(actions), distance
end

Combat._actionUtilitiesForTests = actionUtilities

local function tacticalAssessment(actor, state, snapshot, target, weapon, commands, now)
    local snapshotTime = tonumber(snapshot and snapshot.reflexTime)
        or tonumber(snapshot and snapshot.time)
    local commandKey = table.concat({
        tostring(commands.combatMode), tostring(commands.combatDoctrine),
        tostring(commands.morale), tostring(commands.stress),
        tostring(commands.personalityProfile),
    }, "|")
    local cache = state.tacticalCache
    local weaponItem = weapon and weapon.item or nil
    if snapshotTime ~= nil and type(cache) == "table"
        and cache.snapshotTime == snapshotTime and cache.target == target.actor
        and cache.weaponItem == weaponItem and cache.commandKey == commandKey
        and now < (cache.expires or 0) then
        state.tacticalCacheHits = (state.tacticalCacheHits or 0) + 1
        return cache.overrun
    end
    state.tacticalCacheMisses = (state.tacticalCacheMisses or 0) + 1
    local overrun = Combat.assessOverrun(actor, snapshot, weapon, commands)
    if snapshotTime ~= nil then
        state.tacticalCache = {
            snapshotTime = snapshotTime,
            target = target.actor,
            weaponItem = weaponItem,
            commandKey = commandKey,
            expires = now + (U().config("combatTacticalIntervalMs") or 250),
            overrun = overrun,
        }
    else
        -- Synthetic callers commonly mutate their fixtures between calls without
        -- advancing a snapshot clock. Never let the production cache hide that.
        state.tacticalCache = nil
    end
    return overrun
end

local function stabilizeSpacingAction(state, chosen, target, now)
    if not chosen or chosen.kind ~= "approach" then return chosen end
    local guard = U().config("combatSpacingReversalGuardMs") or 225
    if state.lastSpacingAction == "backstep" and state.lastSpacingTarget == target.actor
        and now - (state.lastSpacingAt or -math.huge) < guard then
        -- A safety backstep may interrupt an approach immediately, but do not
        -- reverse it again on the next reflex pulse. Hold aim for one short player-
        -- sized input window while live geometry settles.
        return { kind = "hold_range", score = chosen.score }
    end
    return chosen
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

local function selectDoctrineTarget(actor, scored, player, snapshot, commands, state, now)
    local best
    for _, target in ipairs(scored) do
        if doctrineMayFight(actor, target, player, snapshot, commands) then best = target break end
    end
    if not best then return nil end
    local previous
    if state.target then
        for _, candidate in ipairs(scored) do
            if candidate.actor == state.target
                and doctrineMayFight(actor, candidate, player, snapshot, commands) then
                previous = candidate
                break
            end
        end
    end
    local emergency = best.attacking == true
        or (best.distanceSq or math.huge)
            <= (U().config("combatShoveDistance") or 1.35) ^ 2
    local margin = U().config("combatTargetScoreMargin") or 18
    if previous and previous.actor ~= best.actor and now < (state.targetCommitUntil or 0)
        and not emergency and best.score < previous.score + margin then
        return previous
    end
    if previous == nil or previous.actor ~= best.actor then
        local ranged = commands.combatDoctrine == "ranged_support"
        state.targetCommitUntil = now + (ranged
            and (U().config("combatRangedCommitMs") or 1000)
            or (U().config("combatMeleeCommitMs") or 650))
    end
    return best
end

-- Score bounded target/action pairs instead of committing to a target before
-- discovering whether anything useful can be done to it. This prevents a prone
-- zombie with no safe stomp from suppressing a viable swing at a standing one.
local function selectViablePair(actor, player, snapshot, scored, commands, state,
        now, preference, preferredTarget)
    local targets, seen = {}, setmetatable({}, { __mode = "k" })
    local hardCap = math.max(1,
        math.floor(tonumber(U().config("combatTargetActionHardCap")) or 8))
    local desired = math.min(hardCap, math.max(1,
        math.floor(tonumber(U().config("combatTargetActionCandidates")) or 3)))
    for _, candidate in ipairs(scored or {}) do
        if #targets >= hardCap then break end
        if doctrineMayFight(actor, candidate, player, snapshot, commands) then
            targets[#targets + 1] = candidate
            seen[candidate.actor] = true
        end
    end
    local committedTarget = state.target and now < (state.targetCommitUntil or 0)
        and state.target or nil
    if committedTarget and not seen[committedTarget] then
        for _, candidate in ipairs(scored or {}) do
            if candidate.actor == committedTarget
                and doctrineMayFight(actor, candidate, player, snapshot, commands) then
                if #targets >= hardCap then targets[#targets] = candidate
                else targets[#targets + 1] = candidate end
                seen[candidate.actor] = true
                break
            end
        end
    end

    local pairs, retreatPair = {}, nil
    local viableTargets, committedEvaluated = 0, committedTarget == nil
    -- Inventory choice depends on coarse tactical bands, not target identity.
    -- Reuse it within this pulse so widening the bounded candidate scan does not
    -- multiply inventory and body-state work.
    local weaponByBand, readinessByWeapon = {}, {}
    for _, target in ipairs(targets) do
        local distance = math.sqrt(target.distanceSq or U().distanceSq(actor, target.actor))
        local band = weaponDistanceBand(distance)
        local selection = weaponByBand[band]
        if selection == nil then
            local weapon, inventory = responsiveWeapon(actor, state, preference, distance,
                snapshot.pressure or 0, snapshot, now)
            selection = { weapon = weapon, inventory = inventory }
            weaponByBand[band] = selection
        end
        local weapon, inventory = selection.weapon, selection.inventory
        local readinessKey = weapon and weapon.item or "unarmed"
        local readiness = readinessByWeapon[readinessKey]
        if readiness == nil then
            readiness = Combat.readiness(actor, snapshot, weapon, commands)
            readinessByWeapon[readinessKey] = readiness
        end
        local actions = actionUtilities(actor, player, snapshot, target, weapon,
            inventory, commands, readiness)
        local useful = false
        for _, action in ipairs(actions) do
            if commands.combatDoctrine == "weapons_free"
                and (action.kind == "shoot" or action.kind == "melee") then
                action.score = action.score + 12
            elseif commands.combatDoctrine == "stealth" and action.kind == "retreat" then
                action.score = action.score + 20
            end
            local pair = {
                target = target, weapon = weapon, inventory = inventory,
                readiness = readiness, action = action, distance = distance,
                score = (tonumber(action.score) or 0)
                    + (tonumber(target.score) or 0) * 0.35,
            }
            if action.kind == "retreat" or action.kind == "escape" then
                if target == preferredTarget and (retreatPair == nil
                    or pair.score > retreatPair.score) then retreatPair = pair end
            else
                pairs[#pairs + 1] = pair
                useful = true
            end
        end
        if useful then viableTargets = viableTargets + 1 end
        if committedTarget and target.actor == committedTarget then committedEvaluated = true end
        if viableTargets >= desired and committedEvaluated then break end
    end
    if retreatPair then pairs[#pairs + 1] = retreatPair end
    table.sort(pairs, function(a, b)
        if a.score == b.score then
            return (a.target.distanceSq or math.huge) < (b.target.distanceSq or math.huge)
        end
        return a.score > b.score
    end)
    local best = pairs[1]
    if best == nil then return nil end

    -- Target commitment applies only among viable pairs. It may stabilize a
    -- close contest, but it cannot preserve a target whose only action vanished.
    if state.target and best.target.actor ~= state.target
        and now < (state.targetCommitUntil or 0) then
        local previous
        for _, pair in ipairs(pairs) do
            if pair.target.actor == state.target then previous = pair break end
        end
        local emergency = best.target.attacking == true
            or (best.target.distanceSq or math.huge)
                <= (U().config("combatShoveDistance") or 1.35) ^ 2
        local margin = tonumber(U().config("combatTargetPairMargin")) or 8
        if previous and not emergency and best.score < previous.score + margin then
            best = previous
        end
    end
    if state.target ~= best.target.actor then
        state.targetCommitUntil = now + (commands.combatDoctrine == "ranged_support"
            and (U().config("combatRangedCommitMs") or 1000)
            or (U().config("combatMeleeCommitMs") or 650))
    end
    return best
end

Combat._selectViablePairForTests = selectViablePair

local function roleMayAttack(actor, role, claim, chosen, target, snapshot)
    if role == "primary" or not chosen then return true end
    local distanceSq = target.distanceSq or U().distanceSq(actor, target.actor)
    local emergency = target.attacking == true
        or distanceSq <= (U().config("combatShoveDistance") or 1.35) ^ 2
        or snapshot.encircled == true
        or (tonumber(snapshot.closeImmediateCount) or tonumber(snapshot.immediateCount) or 0) > 1
    if role == "reserve" then return emergency end
    if chosen.kind == "shoot" then return true end
    if emergency then return true end
    local primary = claim and claim.primary and claim.primary.actor or nil
    local primaryState = primary and states[primary] or nil
    if primaryState and primaryState.noEffectTarget == target.actor
        and (tonumber(primaryState.noEffectCollisions) or 0)
        >= (U().config("combatNoEffectReapproachCount") or 2) then return true end
    local actionState = primary and select(1, U().call(primary, "getCompanionActionStateName")) or nil
    local lower = string.lower(tostring(actionState or ""))
    return string.find(lower, "grapple", 1, true) ~= nil
        or string.find(lower, "grab", 1, true) ~= nil
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

local function sharedRetreatSquare(actor, state, snapshot, target, now)
    local utility = U()
    local ax, ay, az = utility.position(actor)
    if ax == nil then return nil, nil end
    local cohort = state and state.cohortKey or combatCohortKey(actor, nil)
    local key = tostring(cohort) .. ":" .. tostring(math.floor(az or 0))
    local plan = retreatPlans[key]
    local duration = utility.config("combatSharedRetreatMs") or 1200
    if not plan or now >= (plan.expires or 0) then
        plan = {
            cohort = cohort, floor = math.floor(az or 0), createdAt = now,
            expires = now + duration,
            assignments = setmetatable({}, { __mode = "k" }), reserved = {},
        }
        retreatPlans[key] = plan
    end
    local existing = plan.assignments[actor]
    if existing and utility.isSquareFree(existing) then return existing, plan end

    local candidates = snapshot.escapeSquares or {}
    local bestLocal = candidates[1]
    if plan.directionX == nil and bestLocal and bestLocal.square then
        local tx, ty = utility.position(bestLocal.square)
        local length = tx and math.sqrt((tx - ax) ^ 2 + (ty - ay) ^ 2) or 0
        if length > 0.001 then
            plan.directionX, plan.directionY = (tx - ax) / length, (ty - ay) / length
            plan.source = target and target.actor or nil
            plan.danger = tonumber(bestLocal.danger) or 0
        end
    end
    local aligned, alignedDanger
    for _, candidate in ipairs(candidates) do
        local square = candidate.square
        local squareKeyValue = square and utility.squareKey(square) or nil
        local owner = squareKeyValue and plan.reserved[squareKeyValue] or nil
        local tx, ty = utility.position(square)
        if square and tx and (owner == nil or owner == actor) and utility.isSquareFree(square) then
            local dx, dy = tx - ax, ty - ay
            local length = math.sqrt(dx * dx + dy * dy)
            local dot = length > 0.001 and plan.directionX
                and (dx / length) * plan.directionX + (dy / length) * plan.directionY or 1
            local danger = tonumber(candidate.danger) or 0
            if dot >= (utility.config("combatSharedRetreatAlignment") or 0.35)
                and (aligned == nil or danger < alignedDanger) then
                aligned, alignedDanger = square, danger
            end
        end
    end
    local chosen = aligned
    if bestLocal and bestLocal.square then
        local localDanger = tonumber(bestLocal.danger) or 0
        local localKey = utility.squareKey(bestLocal.square)
        local localOwner = localKey and plan.reserved[localKey] or nil
        if (localOwner == nil or localOwner == actor)
            and utility.isSquareFree(bestLocal.square)
            and (chosen == nil or localDanger + 1 < (alignedDanger or math.huge)) then
            chosen = bestLocal.square
        end
    end
    if chosen then
        local squareKeyValue = utility.squareKey(chosen)
        plan.assignments[actor] = chosen
        if squareKeyValue then plan.reserved[squareKeyValue] = actor end
        plan.expires = now + duration
    end
    return chosen, plan
end
Combat._sharedRetreatSquareForTests = sharedRetreatSquare

function Combat.sharedRetreatTarget(actor, player, snapshot, target)
    local state = stateFor(actor)
    state.cohortKey = state.cohortKey or combatCohortKey(actor, player)
    return sharedRetreatSquare(actor, state, snapshot or {}, target, U().nowMs())
end

local function executeRetreat(actor, snapshot, target, survivalCritical, state)
    local utility = U()
    local shared, sharedPlan = sharedRetreatSquare(
        actor, state or stateFor(actor), snapshot, target, utility.nowMs())
    local remembered, retreatPlan
    if SC.Navigation and type(SC.Navigation.retreatTarget) == "function" then
        remembered, retreatPlan = SC.Navigation.retreatTarget(actor, snapshot)
    end
    local escape = snapshot.escapeSquares and snapshot.escapeSquares[1]
    if shared then
        escape = { square = shared, danger = sharedPlan and sharedPlan.danger or 0 }
    end
    if remembered and retreatPlan and (tonumber(retreatPlan.danger) or 0) >= 5
        and escape and (tonumber(escape.danger) or 0) == 0 then remembered = nil end
    -- A combat retreat breaks contact locally; it must never send the companion
    -- sprinting to a distant remembered egress (its far map-entry route), which ran
    -- companions clean off the map when retreating. Cap the retreat distance and
    -- fall back to the nearby escape square when the remembered target is beyond it.
    if remembered then
        local retreatCap = utility.config("combatRetreatMaxDistance") or 14
        if utility.distance(actor, remembered) > retreatCap then remembered = nil end
    end
    if remembered and SC.Navigation and type(SC.Navigation.request) == "function" then
        return SC.Navigation.request(actor, remembered, "jog", {
            action = "combat_retreat",
            snapshot = snapshot,
            awayFrom = target and target.actor,
            urgent = true,
            escapeSpeedOverride = true,
            survivalCritical = survivalCritical == true,
            retreatPlan = retreatPlan,
            sharedRetreat = sharedPlan,
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
            sharedRetreat = sharedPlan,
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

local function execute(actor, player, snapshot, target, weapon, action, commands, state)
    local utility = U()
    state = state or stateFor(actor)
    local targetActor = target and target.actor
    if action.kind == "retreat" or action.kind == "escape" then
        return executeRetreat(actor, snapshot, target, action.kind == "escape", state)
    end
    if weapon and not weapon.equipped and action.kind ~= "shove" and action.kind ~= "stomp" then
        if not equipWeapon(actor, weapon.item, { nextAction = action.kind }) then
            return false, "equip_rejected"
        end
        return true, "equip"
    end
    local accepted, nativeReason
    if action.kind == "unjam" then
        accepted, nativeReason = utility.move(actor, "walk", { action = "unjam", weapon = weapon.item, target = targetActor })
    elseif action.kind == "reload" then
        accepted, nativeReason = utility.move(actor, "walk", { action = "reload", weapon = weapon.item, target = targetActor })
    elseif action.kind == "shoot" then
        if not utility.sameFloor(actor, targetActor) then return false, "different_floor" end
        accepted, nativeReason = utility.move(actor, "walk", {
            action = "attack_firearm", weapon = weapon.item, target = targetActor,
            friendlyFireChecked = true, lineOfSightChecked = true,
            combatDoctrine = commands and commands.combatDoctrine,
        })
    elseif action.kind == "melee" then
        if not utility.sameFloor(actor, targetActor) then return false, "different_floor" end
        accepted, nativeReason = utility.move(actor, "walk", { action = "attack_melee", weapon = weapon.item, target = targetActor })
    elseif action.kind == "shove" then
        if not utility.sameFloor(actor, targetActor) then return false, "different_floor" end
        accepted, nativeReason = utility.move(actor, "walk", { action = "shove", target = targetActor })
    elseif action.kind == "stomp" then
        if not utility.sameFloor(actor, targetActor) then return false, "different_floor" end
        local grounded = boolCall(targetActor, "isOnFloor") or boolCall(targetActor, "isProne")
        if not grounded or utility.isDead(targetActor) or not utility.canSee(actor, targetActor)
            or (tonumber(snapshot.closeImmediateCount) or tonumber(snapshot.immediateCount) or 0)
                > (utility.config("combatStompMaxImmediate") or 1) then
            state.stompAnchor = nil
            return false, "stomp_anchor_invalid"
        end
        -- Aim for the head: step over the zombie's head square before stomping so the
        -- finisher lands on the skull (the lethal spot) instead of the legs. If we are
        -- not on the head yet, close onto it; only stomp once positioned.
        local current = utility.nowMs()
        local anchor = state.stompAnchor
        if not anchor or anchor.target ~= targetActor or current >= (anchor.expires or 0) then
            anchor = {
                target = targetActor,
                square = select(1, utility.call(targetActor, "getHeadSquare", actor)),
                expires = current + (utility.config("combatStompAnchorMs") or 850),
            }
            state.stompAnchor = anchor
        end
        local headSquare = anchor.square
        local ax, ay = utility.position(actor)
        local hxv = headSquare and select(1, utility.call(headSquare, "getX")) or nil
        local hyv = headSquare and select(1, utility.call(headSquare, "getY")) or nil
        local hx = tonumber(hxv)
        local hy = tonumber(hyv)
        if hx ~= nil and hy ~= nil and ax ~= nil and ay ~= nil then
            local hdx = (hx + 0.5) - ax
            local hdy = (hy + 0.5) - ay
            local headRange = utility.config("combatHeadStompRange") or 1.1
            if (hdx * hdx + hdy * hdy) > headRange * headRange then
                accepted, nativeReason = utility.move(actor, "walk", {
                    action = "combat_approach",
                    dx = hdx, dy = hdy,
                    target = targetActor, facingTarget = targetActor,
                    keepFacing = true, weaponReady = true,
                })
                if not accepted then return false, "stomp_rejected" end
                return true, "stomp_approach_head"
            end
        end
        accepted, nativeReason = utility.move(actor, "walk", { action = "stomp", target = targetActor, floorAttack = true })
    elseif action.kind == "approach" then
        if not utility.sameFloor(actor, targetActor) then return false, "different_floor" end
        local ax, ay = utility.position(actor)
        local tx, ty = utility.position(targetActor)
        if ax == nil or tx == nil then return false, "approach_position_unavailable" end
        local moveX, moveY, steered = action.moveX, action.moveY, action.microSteered
        if moveX == nil and SC.Navigation and type(SC.Navigation.combatVector) == "function" then
            local vectorReason
            moveX, moveY, steered, vectorReason = SC.Navigation.combatVector(
                actor, targetActor, "approach")
            if moveX == nil then return false, "approach_blocked:" .. tostring(vectorReason) end
        elseif moveX == nil then
            moveX, moveY = tx - ax, ty - ay
        end
        accepted, nativeReason = utility.move(actor, "walk", {
            action = "combat_approach",
            dx = moveX,
            dy = moveY,
            target = targetActor,
            facingTarget = targetActor,
            keepFacing = true,
            weaponReady = true,
            tacticalStrafe = true,
            microSteered = steered == true,
        })
    elseif action.kind == "backstep" then
        local moveX, moveY, steered = action.moveX, action.moveY, action.microSteered
        if moveX == nil and SC.Navigation and type(SC.Navigation.combatVector) == "function" then
            local vectorReason
            moveX, moveY, steered, vectorReason = SC.Navigation.combatVector(
                actor, targetActor, "backstep")
            if moveX == nil then return false, "backstep_blocked:" .. tostring(vectorReason) end
        end
        accepted, nativeReason = utility.move(actor, "walk", {
            action = "backstep", target = targetActor, awayFrom = targetActor,
            dx = moveX, dy = moveY, keepFacing = true,
            microSteered = steered == true,
        })
    elseif action.kind == "kite" then
        local moveX, moveY, steered = action.moveX, action.moveY, action.microSteered
        if moveX == nil and SC.Navigation and type(SC.Navigation.combatVector) == "function" then
            local vectorReason
            moveX, moveY, steered, vectorReason = SC.Navigation.combatVector(
                actor, targetActor, "kite")
            if moveX == nil then return false, "kite_blocked:" .. tostring(vectorReason) end
        end
        accepted, nativeReason = utility.move(actor, "walk", {
            action = "lateral_kite", target = targetActor, awayFrom = targetActor,
            lateral = true, dx = moveX, dy = moveY, keepFacing = true,
            microSteered = steered == true,
        })
    elseif action.kind == "hold_range" then
        accepted, nativeReason = utility.move(actor, "walk", {
            action = "ready_weapon", target = targetActor, facingTarget = targetActor,
            keepFacing = true, weaponReady = true, combatSpacingHold = true,
        })
    else
        return false, "unknown_action"
    end
    if not accepted then
        local prefix = action.kind .. "_rejected"
        return false, nativeReason and (prefix .. ":" .. tostring(nativeReason)) or prefix
    end
    if action.kind == "melee" or action.kind == "shove" then
        local tx, ty = utility.position(targetActor)
        state.attackAnchor = {
            target = targetActor, x = tx, y = ty,
            expires = utility.nowMs() + (utility.config("combatMeleeAnchorMs") or 900),
        }
    elseif action.kind == "stomp" then
        state.stompAnchor = state.stompAnchor or {
            target = targetActor,
            expires = utility.nowMs() + (utility.config("combatStompAnchorMs") or 850),
        }
    end
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
    if weapon.jammed then
        local accepted = utility.move(actor, "walk", {
            action = "unjam", weapon = weapon.item, target = target.actor,
        })
        return accepted == true, accepted and "unjam" or "unjam_rejected"
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
    local state = stateFor(actor)
    -- Consume the previous native collision before scoring. This both commits a
    -- pending stomp fallback and tells spacing recovery whether melee/shove
    -- actually affected the target.
    if SC.NativeActions and type(SC.NativeActions.pollCombatEvents) == "function" then
        local _, eventReason, evidence = SC.NativeActions.pollCombatEvents(actor)
        if type(evidence) == "table" then
            state.lastCombatEvidence = evidence
            state.lastCombatEvidenceReason = eventReason
            state.lastCombatEvidenceAt = utility.nowMs()
            if evidence.result == "no_effect" then
                state.noEffectCollisions = state.noEffectTarget == evidence.target
                    and (state.noEffectCollisions or 0) + 1 or 1
                state.noEffectTarget = evidence.target
            elseif evidence.result == "landed" then
                if state.noEffectTarget == evidence.target then state.noEffectCollisions = 0 end
                state.noEffectTarget = evidence.target
            end
        end
    end
    local rootRuntime = utility.actorState(actor, runtime)
    local snapshot = rootRuntime.senses and rootRuntime.senses.current or rootRuntime.snapshot
    if type(snapshot) ~= "table" then snapshot = {} end
    snapshot.threats = snapshot.threats or {}
    snapshot.allies = snapshot.allies or {}
    snapshot.escapeSquares = snapshot.escapeSquares or {}
    local commands = commandState(actor)
    local now = utility.nowMs()
    state.cohortKey = combatCohortKey(actor, player)
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
        clearEngagement(state, actor)
        rootRuntime.combatTarget = nil
        rootRuntime.combatRole = nil
        rootRuntime.combatCohort = nil
        rootRuntime.combatOverrun = nil
        rootRuntime.combatReadiness = nil
        state.readiness = nil
        state.tacticalCache = nil
        state.weaponCache = nil
        state.combatRole, state.combatRoleTarget = nil, nil
        return false, "no_threat"
    end
    if SC.Medical and type(SC.Medical.isDowned) == "function" and SC.Medical.isDowned(actor) then
        utility.stop(actor)
        releaseActorClaims(actor)
        state.combatRole, state.combatRoleTarget = nil, nil
        state.retreating = false
        clearAimPreparation(state)
        return false, "downed"
    end

    local target = selectDoctrineTarget(actor, scored, player, snapshot, commands, state, now)
    if not target then
        if state.active then utility.stop(actor) end
        state.active, state.target = false, nil
        state.retreating = false
        clearAimPreparation(state)
        utility.call(actor, "setCompanionAimTarget", nil)
        state.readiness, state.overrun = nil, nil
        state.tacticalCache = nil
        state.weaponCache = nil
        clearEngagement(state, actor)
        state.combatRole, state.combatRoleTarget = nil, nil
        rootRuntime.combatRole, rootRuntime.combatCohort = nil, nil
        return false, "no_credible_target"
    end
    -- Continuously point the actor at the engaged target so the native swing's
    -- hit arc (getDirectionAngle) lands, like a player's mouse aim. Cleared above
    -- when there is no credible target.
    utility.call(actor, "setCompanionAimTarget", target.actor)
    local distance = math.sqrt(target.distanceSq or utility.distanceSq(actor, target.actor))
    local combatRole, cohortClaimRecord = claimTarget(
        target.actor, actor, now, state.cohortKey, nil, "approach", distance)
    state.combatRole = combatRole
    state.combatRoleTarget = target.actor
    rootRuntime.combatRole = combatRole
    rootRuntime.combatCohort = state.cohortKey
    local vehicle, vehicleOk = utility.call(actor, "getVehicle")
    local seated = vehicleOk and vehicle ~= nil
    -- Preserve the target/facing but do not run inventory or locomotion work while
    -- a native on-foot swing owns the actor. This mirrors player input ownership
    -- and keeps the 50 ms reflex cadence cheap during the animation itself.
    if not seated and attackInProgress(actor) then
        claimTarget(target.actor, actor, now, state.cohortKey, combatRole,
            "committed", distance)
        clearRejection(state, rootRuntime)
        state.active = true
        state.target = target.actor
        state.targetScore = target.score
        state.lastActionAt = now
        state.lastAction = "attack_in_progress"
        state.retreating = false
        rootRuntime.combatTarget = target.actor
        rootRuntime.combatAction = "attack_in_progress"
        return true, "attack_in_progress"
    end
    -- Doctrine determines which contacts may be engaged and how the companion
    -- positions. Weapon priority is a separate explicit loadout choice. The only
    -- situational override is a seated actor: melee cannot be executed from a
    -- vehicle, so Weapons Free may select a usable firearm there.
    local preference = commands.weaponPriority or "best"
    if seated and commands.combatDoctrine == "weapons_free" then
        preference = "firearm"
    end
    local weapon, inventory = responsiveWeapon(actor, state, preference, distance,
        snapshot.pressure or 0, snapshot, now)
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
    local overrun = tacticalAssessment(actor, state, snapshot, target, weapon, commands, now)
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
        releaseActorClaims(actor)
        state.combatRole = nil
        rootRuntime.combatRole = nil
        local ok, reason = executeRetreat(actor, snapshot, target, true, state)
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
            releaseActorClaims(actor)
            state.combatRole = nil
            rootRuntime.combatRole = nil
            local ok, reason = executeRetreat(actor, snapshot, target, false, state)
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

    local pair = selectViablePair(actor, player, snapshot, scored, commands, state,
        now, preference, target)
    if not pair then return false, "no_viable_target_action" end
    target, weapon, inventory = pair.target, pair.weapon, pair.inventory
    local readiness = pair.readiness or overrun.readiness
    local chosen = pair.action
    distance = pair.distance or math.sqrt(
        target.distanceSq or utility.distanceSq(actor, target.actor))
    utility.call(actor, "setCompanionAimTarget", target.actor)
    combatRole, cohortClaimRecord = claimTarget(
        target.actor, actor, now, state.cohortKey, nil, "approach", distance)
    state.combatRole = combatRole
    state.combatRoleTarget = target.actor
    rootRuntime.combatRole = combatRole
    rootRuntime.combatReadiness = readiness
    chosen = stabilizeSpacingAction(state, chosen, target, now)
    if chosen.kind == "approach" and state.attackAnchor
        and state.attackAnchor.target == target.actor
        and now < (state.attackAnchor.expires or 0)
        and (state.noEffectTarget ~= target.actor
            or (tonumber(state.noEffectCollisions) or 0)
            < (utility.config("combatNoEffectReapproachCount") or 2)) then
        local tx, ty = utility.position(target.actor)
        local moved = tx and state.attackAnchor.x
            and math.sqrt((tx - state.attackAnchor.x) ^ 2 + (ty - state.attackAnchor.y) ^ 2)
            or math.huge
        if moved <= 0.75 then
            chosen = { kind = "hold_range", score = chosen.score, attackAnchor = true }
        else
            state.attackAnchor = nil
        end
    end
    if combatRole == "reserve" and (chosen.kind == "approach" or chosen.kind == "kite")
        and target.attacking ~= true
        and (target.distanceSq or math.huge)
            > (utility.config("combatShoveDistance") or 1.35) ^ 2 then
        chosen = { kind = "hold_range", score = chosen.score, reserveGuard = true }
    end
    if (chosen.kind == "shoot" or chosen.kind == "melee"
        or chosen.kind == "shove" or chosen.kind == "stomp")
        and not roleMayAttack(actor, combatRole, cohortClaimRecord,
            chosen, target, snapshot) then
        chosen = { kind = "hold_range", score = chosen.score, roleHold = true }
    end

    if chosen.kind == "shoot" then
        local aiming, aimReason = prepareRangedShot(actor, state, snapshot, target,
            weapon, readiness, player, commands, now)
        if aiming then
            claimTarget(target.actor, actor, now, state.cohortKey, combatRole,
                "aiming", distance)
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

    if chosen.kind == "retreat" or chosen.kind == "escape" then
        releaseActorClaims(actor)
        state.combatRole = nil
        rootRuntime.combatRole = nil
    end
    local ok, reason = execute(actor, player, snapshot, target, weapon, chosen, commands, state)
    if not ok then
        Combat.noteRejection(actor, state, rootRuntime, chosen.kind, reason,
            target.actor, distance, weapon)
        return false, reason
    end
    clearRejection(state, rootRuntime)
    if chosen.kind == "shoot" or chosen.kind == "melee"
        or chosen.kind == "shove" or chosen.kind == "stomp" then
        claimTarget(target.actor, actor, now, state.cohortKey, combatRole,
            "committed", distance)
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
    if chosen.kind == "approach" or chosen.kind == "backstep" or chosen.kind == "kite" then
        state.lastSpacingAction = chosen.kind
        state.lastSpacingTarget = target.actor
        state.lastSpacingAt = now
    end
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
        releaseActorClaims(actor)
        if SC.NativeActions and type(SC.NativeActions.resetCombatEvents) == "function" then
            SC.NativeActions.resetCombatEvents(actor)
        end
        states[actor] = nil
    else
        if SC.NativeActions and type(SC.NativeActions.resetCombatEvents) == "function" then
            SC.NativeActions.resetCombatEvents(nil)
        end
        states = setmetatable({}, { __mode = "k" })
        targetClaims = setmetatable({}, { __mode = "k" })
        actorClaims = setmetatable({}, { __mode = "k" })
        retreatPlans = {}
        lastGroupCombatBarkAt = -math.huge
    end
end

return Combat
