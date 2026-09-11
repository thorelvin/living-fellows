-- SPDX-License-Identifier: MIT

local SC = SurvivorCompanion
SC.FactionBehavior = SC.FactionBehavior or {}

local Behavior = SC.FactionBehavior
local actorStates = setmetatable({}, { __mode = "k" })
local groupRosters = setmetatable({}, { __mode = "k" })

local function U()
    return SC.GameplayUtil
end

local function worldHour()
    if type(getGameTime) == "function" then
        local ok, gameTime = pcall(getGameTime)
        if ok and gameTime ~= nil then
            local value, called = U().call(gameTime, "getWorldAgeHours")
            if called and tonumber(value) then return tonumber(value) end
        end
    end
    return U().nowMs() / 3600000
end

local function timeOfDay()
    if type(getGameTime) == "function" then
        local ok, gameTime = pcall(getGameTime)
        if ok and gameTime ~= nil then
            local value, called = U().call(gameTime, "getTimeOfDay")
            if called and tonumber(value) then return tonumber(value) end
        end
    end
    return worldHour() % 24
end

local function stateFor(actor)
    local state = actorStates[actor]
    if not state then
        state = { nextActionAt = 0, nextPatrolAt = 0, patrolIndex = 0,
            humanContact = nil, patrolPoints = nil }
        actorStates[actor] = state
    end
    return state
end

local function invoke(object, methodName, ...)
    local value, called, b, c = U().call(object, methodName, ...)
    return called, value, b, c
end

local function groupFor(actor)
    local affiliation = SC.Factions and SC.Factions.affiliation(actor) or nil
    return affiliation and affiliation.group or nil, affiliation
end

local function factionNavigationIntent(group, intent)
    local prepared = U().copyShallow(intent)
    if not group or not group.id then return prepared end
    prepared.cohortKey = "faction:" .. tostring(group.id)
    local current = U().nowMs()
    local cached = groupRosters[group]
    if not cached or current >= (cached.expires or 0) then
        cached = { participants = {}, expires = current + 250 }
        for _, member in ipairs(group.members or {}) do
            if member.alive ~= false and member.away == nil and member.departed ~= true
                and member.actorId then
                local record = SC.Registry and SC.Registry.byId(member.actorId) or nil
                if record and record.actor and U().isValidActor(record.actor) then
                    cached.participants[#cached.participants + 1] = {
                        actor = record.actor, id = member.actorId,
                    }
                end
            end
        end
        groupRosters[group] = cached
    end
    prepared.groupParticipants = cached.participants
    return prepared
end
Behavior.navigationIntent = factionNavigationIntent

local function memberForActor(group, actor)
    local id = U().idOf(actor)
    for _, member in ipairs(group and group.members or {}) do
        if member.actorId == id then return member end
    end
    return nil
end

local function playerInside(group, player)
    local bounds = group and group.house and group.house.bounds
    if type(bounds) ~= "table" then return false end
    local x, y, z = U().position(player)
    return x ~= nil and z ~= nil and z >= 0 and z <= 2
        and x >= bounds.x1 and x <= bounds.x2 and y >= bounds.y1 and y <= bounds.y2
end

local function territoryDistance(group, value)
    local bounds = group and group.house and group.house.bounds
    local x, y = U().position(value)
    if type(bounds) ~= "table" or x == nil then return math.huge end
    local dx = x < bounds.x1 and bounds.x1 - x or x > bounds.x2 and x - bounds.x2 or 0
    local dy = y < bounds.y1 and bounds.y1 - y or y > bounds.y2 and y - bounds.y2 or 0
    return math.sqrt(dx * dx + dy * dy)
end

local function speaker(group)
    local fallback
    for _, member in ipairs(group.members or {}) do
        if member.alive ~= false and member.away == nil and member.departed ~= true
            and member.actorId then
            local record = SC.Registry.byId(member.actorId)
            if record and record.actor then
                if member.role == "leader" then return record.actor end
                fallback = fallback or record.actor
            end
        end
    end
    return fallback
end

local function bark(group, topic, fallback, sourceActor)
    local current = U().nowMs()
    if current < (tonumber(group.nextBarkAt) or 0) then return false end
    local actor = sourceActor or speaker(group)
    if not actor then return false end
    group.nextBarkAt = current + (tonumber(SC.Config.get("factionBarkCooldownMs")) or 20000)
    if SC.Dialogue and type(SC.Dialogue.say) == "function" then
        SC.Dialogue.say(actor, topic, nil, nil, { fallback = fallback })
    else
        U().say(actor, fallback)
    end
    return true
end

local function updateTerritory(group, player)
    local distance = territoryDistance(group, player)
    local outer = tonumber(SC.Config.get("factionWarningOuterRadius")) or 18
    local inner = tonumber(SC.Config.get("factionWarningInnerRadius")) or 10
    local current = U().nowMs()
    local hasAccess = SC.FactionContracts
        and type(SC.FactionContracts.hasAccess) == "function"
        and SC.FactionContracts.hasAccess(group, player) == true
    if distance <= outer then
        SC.Factions.markDiscovered(group.id)
        if not hasAccess and (not group.warningLevel or group.warningLevel < 1) then
            group.warningLevel = 1
            bark(group, "faction.warn.outer", "Stay away. This house is occupied.")
        end
    end
    if not hasAccess and distance <= inner and (group.warningLevel or 0) < 2 then
        group.warningLevel = 2
        group.nextBarkAt = 0
        bark(group, "faction.warn.inner", "Do not come any closer.")
    end
    if playerInside(group, player) then
        local aimingOk, aiming = invoke(player, "isAiming")
        if aimingOk and aiming == true and group.standing ~= "Hostile" then
            SC.Factions.noteOffense(group.id, "aim", 1)
            group.alertUntil = current + 60000
            group.nextBarkAt = 0
            bark(group, "faction.warn.weapon", "Lower your weapon!")
        elseif hasAccess then
            group.trespassStartedAt, group.trespassRecordedAt = nil, nil
        else
            group.trespassStartedAt = group.trespassStartedAt or current
        end
        if not hasAccess and not (aimingOk and aiming == true)
            and (group.warningLevel or 0) >= 2 and group.trespassRecordedAt == nil
            and current - group.trespassStartedAt >= 5000 and group.standing == "Wary" then
            SC.Factions.noteOffense(group.id, "trespass", 1)
            group.trespassRecordedAt = current
            group.alertUntil = current + 60000
            group.nextBarkAt = 0
            bark(group, "faction.warn.leave", "Leave our house. Last warning.")
        elseif not hasAccess and group.trespassRecordedAt ~= nil and group.standing == "Wary"
            and current - group.trespassStartedAt >= 12000 then
            SC.Factions.forceStanding(group.id, "Hostile")
            group.nextBarkAt = 0
            bark(group, "faction.hostile", "You were warned!")
        end
    else
        group.trespassStartedAt = nil
        if distance > outer + 8 then
            group.warningLevel = nil
            group.trespassRecordedAt = nil
        end
    end
end

local function resolveObject(target)
    if type(target) ~= "table" then return nil end
    local square = U().gridSquare(target.x, target.y, target.z or 0)
    if not square then return nil end
    local objects, ok = U().call(square, "getObjects")
    if not ok or objects == nil then return nil end
    local index = math.floor(tonumber(target.objectIndex) or -1)
    if type(objects) == "table" then return objects[index + 1] end
    local object, called = U().call(objects, "get", index)
    return called and object or nil
end

local function planksOn(object)
    local same, sameOk = U().call(object, "getBarricadeOnSameSquare")
    local opposite, oppositeOk = U().call(object, "getBarricadeOnOppositeSquare")
    local sameCount, sameCountOk = 0, false
    if sameOk and same then sameCount, sameCountOk = U().call(same, "getNumPlanks") end
    local oppositeCount, oppositeCountOk = 0, false
    if oppositeOk and opposite then oppositeCount, oppositeCountOk = U().call(opposite, "getNumPlanks") end
    return math.max(sameCountOk and tonumber(sameCount) or 0,
        oppositeCountOk and tonumber(oppositeCount) or 0)
end

local function allJobsComplete(group)
    for _, job in ipairs(group.jobs or {}) do
        if job.status ~= "completed" and job.status ~= "cancelled" then return false end
    end
    return true
end

local function sameTarget(left, right)
    return type(left) == "table" and type(right) == "table"
        and left.x == right.x and left.y == right.y
        and (left.z or 0) == (right.z or 0)
        and left.objectIndex == right.objectIndex
end

local function ensureEmergencyJobs(group, threatCount)
    local primary = group.house and group.house.primaryEntry
    if not primary then return end
    local current = U().nowMs()
    if (tonumber(threatCount) or 0) > 0 then
        group.sustainedThreatAt = group.sustainedThreatAt or current
        group.lastThreatAt = current
        group.lifecycle = group.standing == "Hostile" and "hostile" or "alert"
        group.alertUntil = current + 30000
        if current - group.sustainedThreatAt >= 8000 then
            local exists = false
            for _, job in ipairs(group.jobs or {}) do
                if job.phase == "emergency_seal" and sameTarget(job.target, primary) then
                    exists = true
                    break
                end
            end
            if not exists then
                group.jobs[#group.jobs + 1] = {
                    id = group.house.id .. ":primary:emergency_seal",
                    kind = "barricade", phase = "emergency_seal", targetPlanks = 2,
                    target = U().copyShallow(primary), status = "open", attempts = 0,
                }
            end
        end
        return
    end
    if group.lastThreatAt and current - group.lastThreatAt > 30000 then
        group.sustainedThreatAt = nil
        for _, seal in ipairs(group.jobs or {}) do
            if seal.phase == "emergency_seal" and seal.status == "completed" then
                local reopenExists = false
                for _, job in ipairs(group.jobs or {}) do
                    if job.phase == "emergency_reopen" and sameTarget(job.target, primary) then
                        reopenExists = true
                        break
                    end
                end
                if not reopenExists then
                    group.jobs[#group.jobs + 1] = {
                        id = group.house.id .. ":primary:emergency_reopen",
                        kind = "remove_barricade", phase = "emergency_reopen", targetPlanks = 0,
                        target = U().copyShallow(primary), status = "open", attempts = 0,
                    }
                    group.lifecycle = "fortifying"
                end
            end
        end
    end
end

local function nextJob(group, actorId)
    for _, job in ipairs(group.jobs or {}) do
        if job.status == "active" and job.assignedId == actorId then return job end
    end
    for _, job in ipairs(group.jobs or {}) do
        if job.status == "open"
            or (job.status == "blocked" and U().nowMs() >= (job.retryAt or 0)) then
            job.status, job.assignedId = "active", actorId
            job.startedAt = U().nowMs()
            return job
        end
    end
    return nil
end

local function finishTrackedWork(actor, state, job, object)
    if SC.NativeActions and type(SC.NativeActions.isWorkActive) == "function"
        and SC.NativeActions.isWorkActive(actor) then
        return true, "fortification_action_active"
    end
    local finished, reason = true, "no_tracked_work"
    if SC.NativeActions and type(SC.NativeActions.finishWork) == "function" then
        finished, reason = SC.NativeActions.finishWork(actor)
    end
    if not finished then return false, reason end
    local after = planksOn(object)
    local progressed = job.kind == "remove_barricade"
        and after < (state.workBefore or math.huge)
        or job.kind ~= "remove_barricade" and after > (state.workBefore or -1)
    if progressed then
        job.attempts = (job.attempts or 0) + 1
        local complete = job.kind == "remove_barricade" and after <= 0
            or job.kind ~= "remove_barricade" and after >= (tonumber(job.targetPlanks) or 1)
        if complete then
            job.status, job.assignedId, job.completedAt = "completed", nil, U().nowMs()
        else
            job.status, job.assignedId = "open", nil
        end
        state.workJob, state.workBefore = nil, nil
        return true, "fortification_progress"
    end
    job.status, job.assignedId = "blocked", nil
    job.retryAt = U().nowMs() + 10000
    job.lastFailure = "native_action_made_no_progress:" .. tostring(reason)
    state.workJob, state.workBefore = nil, nil
    return false, job.lastFailure
end

local function fortify(actor, group, state)
    local id = U().idOf(actor)
    local job = nextJob(group, id)
    if not job then
        if allJobsComplete(group) then group.lifecycle = "settled" end
        return false, "no_fortification_job"
    end
    local object = resolveObject(job.target)
    if not object then
        job.status, job.assignedId, job.retryAt = "blocked", nil, U().nowMs() + 15000
        job.lastFailure = "fortification_target_unloaded"
        return false, job.lastFailure
    end
    local currentPlanks = planksOn(object)
    if (job.kind == "remove_barricade" and currentPlanks <= 0)
        or (job.kind ~= "remove_barricade"
            and currentPlanks >= (tonumber(job.targetPlanks) or 1)) then
        job.status, job.assignedId, job.completedAt = "completed", nil, U().nowMs()
        return true, "fortification_already_complete"
    end
    if state.workJob == job.id then return finishTrackedWork(actor, state, job, object) end
    if U().distance(actor, object) > 1.45 then
        local square = U().squareOf(object)
        if not square or not SC.Navigation or type(SC.Navigation.request) ~= "function" then
            return false, "fortification_navigation_unavailable"
        end
        return SC.Navigation.request(actor, square, "walk", factionNavigationIntent(group, {
            action = "faction_approach_barricade", targetSquare = square,
        }))
    end
    local action = job.kind == "remove_barricade" and "remove_barricade" or "barricade"
    local started, reason = U().move(actor, "walk", {
        action = action, object = object, factionJobId = job.id,
    })
    if not started then
        job.status, job.assignedId, job.retryAt = "blocked", nil, U().nowMs() + 10000
        job.lastFailure = tostring(reason)
        return false, reason
    end
    state.workJob, state.workBefore = job.id, currentPlanks
    return true, "fortification_started"
end

local function friendlyInLine(actor, target, group, player, kind)
    local allies = {}
    if group then
        for _, member in ipairs(group.members or {}) do
            if member.alive ~= false and member.away == nil and member.departed ~= true
                and member.actorId and member.actorId ~= U().idOf(actor) then
                local record = SC.Registry.byId(member.actorId)
                if record and record.actor then allies[#allies + 1] = record.actor end
            end
        end
    else
        if player and player ~= actor then allies[#allies + 1] = player end
        if SC.Registry and type(SC.Registry.living) == "function" then
            for _, record in ipairs(SC.Registry.living() or {}) do
                if record.recruited == true and record.actor and record.actor ~= actor then
                    allies[#allies + 1] = record.actor
                end
            end
        end
    end
    return SC.Combat and type(SC.Combat.friendlyFireBlocked) == "function"
        and SC.Combat.friendlyFireBlocked(actor, target, {
            player = player, allies = allies, kind = kind or "ranged",
        }) == true
end

local function approachHostile(actor, target, swingMax, group)
    local distance = U().distance(actor, target)
    -- Inside the short reaction envelope, use the same continuous, obstacle-
    -- probed step as ordinary companion combat. This closes the last fraction of
    -- a tile without asking A* to path onto the player's occupied square.
    if U().sameFloor(actor, target) and U().canSee(actor, target)
        and distance <= math.max(2.5, (tonumber(swingMax) or 1.0) + 1.25) then
        local ax, ay = U().position(actor)
        local tx, ty = U().position(target)
        if ax ~= nil and tx ~= nil then
            local dx, dy, steered
            if SC.Navigation and type(SC.Navigation.combatVector) == "function" then
                dx, dy, steered = SC.Navigation.combatVector(actor, target, "approach")
            else
                dx, dy = tx - ax, ty - ay
            end
            if dx ~= nil and dy ~= nil then
                return U().move(actor, "walk", {
                    action = "combat_approach",
                    dx = dx, dy = dy,
                    target = target, facingTarget = target, keepFacing = true,
                    weaponReady = true, tacticalStrafe = true,
                    microSteered = steered == true, factionCombat = true,
                })
            end
            -- A blocked micro-step is not a licence to dispatch the raw vector.
            -- Fall through to the attack-ring path below instead.
        end
    end

    -- For walls, doors and longer pursuit, route to one of the free attack-ring
    -- squares. Never route to the player's occupied tile: doing so made crowd
    -- avoidance fight the hostile approach and produced repeated forward/back
    -- steps at entrances.
    if SC.Navigation and type(SC.Navigation.interactionTargets) == "function"
        and type(SC.Navigation.requestAny) == "function" then
        local targets = SC.Navigation.interactionTargets(actor, target, { maximum = 8 })
        if #targets > 0 then
            return SC.Navigation.requestAny(actor, targets, "jog", factionNavigationIntent(group, {
                action = "faction_defend_territory", target = target,
                movingTarget = true, arrivalDistance = 0.85,
                factionCombat = true,
            }))
        end
    end
    return false, "hostile_path_unavailable"
end

local function hostile(actor, target, group, state, player)
    if target == nil then return false, "hostile_target_unavailable" end
    local leash = group and group.archetype == "bandit_camp"
        and (tonumber(SC.Config.get("banditFactionPursuitLeash")) or 24)
        or (tonumber(SC.Config.get("factionPursuitLeash")) or 15)
    if group and territoryDistance(group, target) > leash then
        local target = group.house and U().loadedSquare(group.house.anchor) or nil
        if target and SC.Navigation then
            return SC.Navigation.request(actor, target, "jog", factionNavigationIntent(group, {
                action = "faction_break_pursuit", targetSquare = target, seekOpenEscape = true,
            }))
        end
        return false, "hostile_target_outside_leash"
    end
    local primary, primaryOk = U().call(actor, "getPrimaryHandItem")
    if (not primaryOk or primary == nil) and SC.Combat
        and type(SC.Combat.equipPreferred) == "function"
        and U().nowMs() >= (state.nextEquipAt or 0) then
        state.nextEquipAt = U().nowMs() + 2500
        local equipped, equipReason = SC.Combat.equipPreferred(actor, "best")
        if equipped then return true, equipReason or "equipping_for_faction_combat" end
        primary, primaryOk = U().call(actor, "getPrimaryHandItem")
    end

    local distance = U().distance(actor, target)
    local visible = U().sameFloor(actor, target) and U().canSee(actor, target)
    local ranged = false
    if primaryOk and primary then
        local rangedValue, rangedOk = U().call(primary, "isRanged")
        ranged = rangedOk and rangedValue == true
    end
    local rangedLimit = group and group.archetype == "bandit_camp"
        and (tonumber(SC.Config.get("banditFactionFirearmMaxRange")) or 8) or 12
    if ranged and visible and distance <= rangedLimit
        and not friendlyInLine(actor, target, group, player, "ranged") then
        return U().move(actor, "walk", {
            action = "attack_firearm", weapon = primary, target = target,
            factionCombat = true,
        })
    end

    local swingMin, swingMax
    if primaryOk and primary and SC.Combat
        and type(SC.Combat.meleeRange) == "function" then
        swingMin, swingMax = SC.Combat.meleeRange(actor, primary)
    end
    if swingMax and visible and distance >= swingMin and distance <= swingMax then
        if friendlyInLine(actor, target, group, player, "melee") then
            U().stop(actor)
            return true, "friendly_in_attack_lane"
        end
        return U().move(actor, "walk", {
            action = "attack_melee", weapon = primary, target = target, factionCombat = true,
        })
    end
    local shoveDistance = tonumber(SC.Config.get("combatShoveDistance")) or 1.35
    if visible and distance <= shoveDistance and (not swingMin or distance < swingMin) then
        if friendlyInLine(actor, target, group, player, "melee") then
            U().stop(actor)
            return true, "friendly_in_attack_lane"
        end
        return U().move(actor, "walk", {
            action = "shove", target = target, factionCombat = true,
        })
    end
    return approachHostile(actor, target, swingMax, group)
end

local function rememberHumanThreat(actor, player, state)
    local current = U().nowMs()
    local observed = SC.Factions and type(SC.Factions.hostileTargetFor) == "function"
        and SC.Factions.hostileTargetFor(actor, player) or nil
    if observed and observed.actor then
        local x, y, z = U().position(observed.actor)
        state.humanContact = {
            actor = observed.actor, id = observed.id, x = x, y = y, z = z,
            seenAt = current,
        }
        observed.x, observed.y, observed.z, observed.seenAt = x, y, z, current
        observed.visible = true
        return observed
    end
    local memory = state.humanContact
    local memoryMs = tonumber(SC.Config.get("banditFactionLastSeenMs")) or 6000
    if type(memory) == "table" and current - (tonumber(memory.seenAt) or 0) <= memoryMs
        and memory.actor and not U().isDead(memory.actor) then
        return {
            actor = memory.actor, id = memory.id, x = memory.x, y = memory.y,
            z = memory.z, seenAt = memory.seenAt, visible = false,
        }
    end
    state.humanContact = nil
    return nil
end

local function hostileSound(actor, player, snapshot)
    local sounds = type(snapshot) == "table" and snapshot.sounds or nil
    if type(sounds) ~= "table" or not SC.Factions
        or type(SC.Factions.isHostileBetween) ~= "function" then return nil end
    local current = U().nowMs()
    local memoryMs = tonumber(SC.Config.get("banditFactionHeardMemoryMs")) or 8000
    local newest
    for _, sound in ipairs(sounds) do
        local soundAt = tonumber(sound.time) or current - (tonumber(sound.ageMs) or 0)
        if sound.source and current - soundAt <= memoryMs
            and SC.Factions.isHostileBetween(actor, sound.source, player)
            and (not newest or soundAt > (tonumber(newest.time) or -math.huge)) then
            newest = sound
        end
    end
    return newest
end

local function moveToStaticPosition(actor, position, movementMode, action, group)
    if type(position) ~= "table" or position.x == nil then
        return false, "search_position_missing"
    end
    if U().distance(actor, position) <= 1.25 then
        U().stop(actor)
        return false, "search_position_reached"
    end
    local square = U().gridSquare(position.x, position.y, position.z or 0)
    if not square or not SC.Navigation or type(SC.Navigation.request) ~= "function" then
        return false, "search_position_unavailable"
    end
    return SC.Navigation.request(actor, square, movementMode or "walk", factionNavigationIntent(group, {
        action = action or "faction_search_last_seen", targetSquare = square,
        seekOpenEscape = true,
    }))
end

local function beginBanditAttack(group)
    group.bandit = group.bandit or {}
    group.bandit.engagement = "attacking"
    group.bandit.engagedHour = worldHour()
end

local function banditHumanCombat(actor, targetInfo, group, state, player)
    if not targetInfo or not targetInfo.actor then return false, "bandit_target_missing" end
    group.bandit = group.bandit or {}
    local target = targetInfo.actor
    if targetInfo.visible ~= true then
        local handled, reason = moveToStaticPosition(actor, targetInfo, "jog",
            "bandit_search_last_seen", group)
        if reason == "search_position_reached" then state.humanContact = nil end
        return handled, reason
    end
    if group.bandit.engagement == "unaware" then
        group.bandit.engagement = "challenging"
        state.challengeStartedAt = U().nowMs()
        SC.Factions.markDiscovered(group.id)
        group.nextBarkAt = 0
        bark(group, "faction.bandit.challenge", "Stop right there. Turn around.", actor)
    end
    if group.bandit.engagement == "challenging" then
        local current = U().nowMs()
        local aiming, aimingOk = U().call(target, "isAiming")
        local attackedAgo = (worldHour()
            - (tonumber(group.bandit.attackedHour) or -math.huge)) * 3600000
        local attacked = attackedAgo >= 0 and attackedAgo <= 5000
        local threatened = aimingOk and aiming == true and U().distance(actor, target) <= 8
        state.challengeStartedAt = tonumber(state.challengeStartedAt) or current
        local elapsed = current - state.challengeStartedAt
        if attacked or threatened
            or elapsed >= (tonumber(SC.Config.get("banditFactionChallengeMs")) or 2000) then
            beginBanditAttack(group)
        else
            return U().move(actor, "walk", {
                action = "face_alert", target = target, facingTarget = target,
                stableFacing = true, weaponReady = true, humanAnimationOnly = true,
            })
        end
    end
    return hostile(actor, target, group, state, player)
end

local function livingPatrolMembers(group)
    local rows = {}
    for _, member in ipairs(group.members or {}) do
        if member.alive ~= false and member.away == nil and member.departed ~= true
            and member.actorId then rows[#rows + 1] = member end
    end
    return rows
end

local function selectPatrolMember(group)
    local members = livingPatrolMembers(group)
    if #members < 2 then return nil end
    for _, member in ipairs(members) do
        if member.role ~= "leader" then return member end
    end
    return members[2]
end

local function beginPatrolIfDue(group)
    group.bandit = group.bandit or {}
    local bandit = group.bandit
    local nowHour = worldHour()
    if bandit.patrolMemberKey then
        local assignedAlive = false
        for _, member in ipairs(livingPatrolMembers(group)) do
            if member.key == bandit.patrolMemberKey then assignedAlive = true break end
        end
        if not assignedAlive then
            bandit.patrolMemberKey = nil
            bandit.patrolStartedHour = nil
            bandit.patrolReturnHour = nil
            bandit.patrolPhase = nil
            bandit.nextPatrolHour = nowHour + 1
            return
        end
        if nowHour >= (tonumber(bandit.patrolReturnHour) or nowHour) then
            bandit.patrolPhase = "return"
        end
        return
    end
    local hour = timeOfDay()
    if hour < 7 or hour > 21 or nowHour < (tonumber(bandit.nextPatrolHour) or 0) then return end
    local member = selectPatrolMember(group)
    if not member then
        bandit.nextPatrolHour = nowHour + 1
        return
    end
    bandit.patrolSerial = (tonumber(bandit.patrolSerial) or 0) + 1
    bandit.patrolMemberKey = member.key
    bandit.patrolStartedHour = nowHour
    bandit.patrolReturnHour = nowHour + 0.5
    bandit.patrolPhase = "out"
end

local function patrolPoints(group, state)
    local serial = tonumber(group.bandit and group.bandit.patrolSerial) or 0
    if state.patrolPoints and state.patrolSerial == serial then return state.patrolPoints end
    local anchor = group.house and group.house.anchor
    local points = {}
    if anchor then
        local minRadius = tonumber(SC.Config.get("banditFactionPatrolMinRadius")) or 8
        local maxRadius = math.max(minRadius,
            tonumber(SC.Config.get("banditFactionPatrolMaxRadius")) or 24)
        local span = math.max(1, math.floor(maxRadius - minRadius + 1))
        for index = 1, 3 do
            local seed = U().stableHash(group.id .. ":patrol:" .. tostring(serial)
                .. ":" .. tostring(index))
            local radius = minRadius + seed % span
            local angle = ((seed % 360) + (index - 1) * 120) * math.pi / 180
            for probe = 0, 11 do
                local probeAngle = angle + probe * math.pi / 6
                local point = {
                    x = math.floor(anchor.x + math.cos(probeAngle) * radius + 0.5),
                    y = math.floor(anchor.y + math.sin(probeAngle) * radius + 0.5),
                    z = anchor.z or 0,
                }
                local square = U().gridSquare(point.x, point.y, point.z)
                if square and U().isSquareFree(square) then
                    points[#points + 1] = point
                    break
                end
            end
        end
    end
    state.patrolPoints, state.patrolSerial, state.patrolIndex = points, serial, 1
    return points
end

local function finishPatrol(group, state)
    local bandit = group.bandit or {}
    bandit.patrolMemberKey = nil
    bandit.patrolStartedHour = nil
    bandit.patrolReturnHour = nil
    bandit.patrolPhase = nil
    bandit.nextPatrolHour = worldHour()
        + (tonumber(SC.Config.get("banditFactionPatrolIntervalHours")) or 2)
    state.patrolPoints, state.patrolSerial, state.patrolIndex = nil, nil, 1
end

local function banditPatrol(actor, group, state)
    local bandit = group.bandit or {}
    local anchor = group.house and group.house.anchor
    if bandit.patrolPhase == "return" then
        if anchor and U().distance(actor, anchor) <= 3 then
            finishPatrol(group, state)
            return true, "bandit_patrol_complete"
        end
        return moveToStaticPosition(actor, anchor, "jog", "bandit_patrol_return", group)
    end
    local points = patrolPoints(group, state)
    if #points == 0 then
        finishPatrol(group, state)
        return false, "bandit_patrol_route_unavailable"
    end
    local target = points[state.patrolIndex or 1]
    if target and U().distance(actor, target) <= 1.25 then
        state.patrolIndex = (state.patrolIndex or 1) + 1
        target = points[state.patrolIndex]
        if not target then
            bandit.patrolPhase = "return"
            return moveToStaticPosition(actor, anchor, "jog", "bandit_patrol_return", group)
        end
    end
    return moveToStaticPosition(actor, target, "walk", "bandit_patrol", group)
end

function Behavior.humanThreatFor(actor, player)
    if actor == nil then return nil end
    return rememberHumanThreat(actor, player, stateFor(actor))
end

local function entryGuardPosition(group)
    local primary = group.house and group.house.primaryEntry
    local interior = group.house and group.house.interior or {}
    if not primary then return group.house and group.house.anchor end
    local best, bestDistance
    for _, position in ipairs(interior) do
        local distance = math.abs(position.x - primary.x) + math.abs(position.y - primary.y)
        if distance >= 1 and (bestDistance == nil or distance < bestDistance) then
            best, bestDistance = position, distance
        end
    end
    return best or group.house.anchor
end

local function roleGuardsEntry(group, role)
    if role == "watch" then return true end
    if role ~= "leader" then return false end
    for _, member in ipairs(group.members or {}) do
        if member.alive ~= false and member.away == nil and member.departed ~= true
            and member.role == "watch" then return false end
    end
    return true
end

local function guard(actor, group, state, role)
    local anchor = roleGuardsEntry(group, role)
        and entryGuardPosition(group) or group.house and group.house.anchor
    if not anchor then return false, "territory_anchor_missing" end
    if U().distance(actor, anchor) > (roleGuardsEntry(group, role) and 4 or 8) then
        local square = U().loadedSquare(anchor)
        if square and SC.Navigation then
            return SC.Navigation.request(actor, square, "walk", factionNavigationIntent(group, {
                action = "faction_return_home", targetSquare = square,
            }))
        end
    end
    if U().nowMs() >= (state.nextHousekeepingAt or 0) then
        state.nextHousekeepingAt = U().nowMs() + 4000
        state.openingIndex = ((state.openingIndex or 0) % math.max(1,
            #(group.house.openings or {}))) + 1
        local opening = (group.house.openings or {})[state.openingIndex]
        local object = opening and resolveObject(opening) or nil
        if object then
            if opening.kind == "door" then
                local open, openOk = U().call(object, "IsOpen")
                if openOk and open == true then
                    if U().distance(actor, object) <= 1.45 and SC.Navigation then
                        return SC.Navigation.interact(actor, object, "close_door")
                    end
                    local square = U().squareOf(object)
                    if square and SC.Navigation then
                        return SC.Navigation.request(actor, square, "walk", factionNavigationIntent(group, {
                            action = "faction_close_door", targetSquare = square,
                        }))
                    end
                end
            elseif opening.kind == "window" then
                local curtain, curtainOk = U().call(object, "getCurtain")
                if curtainOk and curtain then
                    local open, openOk = U().call(curtain, "IsOpen")
                    if openOk and open == true and U().distance(actor, object) <= 1.45
                        and SC.Navigation then
                        return SC.Navigation.interact(actor, curtain, "close_curtain")
                    end
                end
            end
        end
    end
    if U().nowMs() < (state.nextPatrolAt or 0) then
        U().stop(actor)
        return true, "guarding_household"
    end
    local interior = group.house and group.house.interior or {}
    state.nextPatrolAt = U().nowMs() + 18000 + ((state.patrolIndex or 0) % 4) * 1500
    state.patrolIndex = ((state.patrolIndex or 0) % math.max(1, #interior)) + 1
    local patrol = interior[state.patrolIndex] or anchor
    if roleGuardsEntry(group, role) and U().distance(patrol, anchor) > 4 then patrol = anchor end
    local square = U().gridSquare(patrol.x, patrol.y, patrol.z or 0)
    if square and U().isSquareFree(square) and SC.Navigation then
        return SC.Navigation.request(actor, square, "walk", factionNavigationIntent(group, {
            action = "faction_guard_patrol", targetSquare = square,
        }))
    end
    return false, "guard_patrol_square_blocked"
end

function Behavior.intentFor(actor, player, snapshot)
    local group, affiliation = groupFor(actor)
    if not group then return nil end
    local threatCount = type(snapshot) == "table"
        and (tonumber(snapshot.threatCount) or #(snapshot.threats or {})) or 0
    ensureEmergencyJobs(group, threatCount)
    if threatCount > 0 then
        -- Keep a faction candidate in the list so residents never fall through
        -- to the generic recruitable encounter, but score it below even the
        -- companion engine's cautious/last-seen combat candidate. This makes
        -- every household resident use SCCombat against zombies, including a
        -- hostile resident who resumes attacking the player after the walkers
        -- are dealt with.
        return { priority = 18, kind = "faction", mode = "zombie_defense",
            factionId = group.id }
    end
    if group.archetype == "bandit_camp" then
        local state = stateFor(actor)
        local humanThreat = rememberHumanThreat(actor, player, state)
        if humanThreat then
            if humanThreat.visible then SC.Factions.markDiscovered(group.id) end
            return {
                priority = humanThreat.visible and 110 or 90,
                kind = "faction",
                mode = humanThreat.visible and "bandit_human" or "bandit_search",
                factionId = group.id,
                humanThreat = humanThreat,
            }
        end
        local sound = hostileSound(actor, player, snapshot)
        if sound then
            return { priority = 65, kind = "faction", mode = "bandit_investigate",
                factionId = group.id, sound = sound }
        end
        if group.lifecycle == "fortifying" and not allJobsComplete(group) then
            return { priority = 57, kind = "faction", mode = "fortify",
                factionId = group.id }
        end
        beginPatrolIfDue(group)
        local member = memberForActor(group, actor)
        if group.bandit and member
            and group.bandit.patrolMemberKey == member.key then
            return { priority = 42, kind = "faction", mode = "bandit_patrol",
                factionId = group.id }
        end
        return { priority = 28, kind = "faction", mode = "guard", factionId = group.id }
    end
    updateTerritory(group, player)
    if group.lifecycle == "hostile" or group.standing == "Hostile" then
        local canReconcile = group.permanentHostility ~= true
            and SC.Factions.canReconcile(group.id) == true
        local aiming, aimingOk = U().call(player, "isAiming")
        if canReconcile and not playerInside(group, player)
            and not (aimingOk and aiming == true) then
            bark(group, "faction.restitution", "Leave the restitution where we can see it.")
            return { priority = 70, kind = "faction", mode = "restitution_watch",
                factionId = group.id }
        end
        local humanThreat = rememberHumanThreat(actor, player, stateFor(actor))
        if humanThreat then
            return { priority = humanThreat.visible and 110 or 90, kind = "faction",
                mode = "hostile", factionId = group.id, humanThreat = humanThreat }
        end
        return { priority = 28, kind = "faction", mode = "guard", factionId = group.id }
    end
    local contractIntent = SC.FactionContracts
        and type(SC.FactionContracts.intentFor) == "function"
        and SC.FactionContracts.intentFor(actor, group, player, snapshot) or nil
    if contractIntent and (tonumber(contractIntent.priority) or 0) >= 60 then
        return { priority = contractIntent.priority, kind = "faction",
            mode = contractIntent.mode, factionId = group.id, contract = contractIntent }
    end
    local lifeIntent = SC.FactionLife and type(SC.FactionLife.intentFor) == "function"
        and SC.FactionLife.intentFor(actor, group, player, snapshot) or nil
    if lifeIntent and (tonumber(lifeIntent.priority) or 0) >= 60 then
        return { priority = lifeIntent.priority, kind = "faction", mode = lifeIntent.mode,
            factionId = group.id, life = lifeIntent }
    end
    if group.lifecycle == "fortifying" and not allJobsComplete(group) then
        return { priority = 57, kind = "faction", mode = "fortify", factionId = group.id }
    end
    if lifeIntent then
        return { priority = lifeIntent.priority, kind = "faction", mode = lifeIntent.mode,
            factionId = group.id, life = lifeIntent }
    end
    return { priority = 28, kind = "faction", mode = "guard", factionId = group.id }
end

function Behavior.update(actor, player, runtime, intent)
    local group, affiliation = groupFor(actor)
    if not group then return false, "not_a_faction_member" end
    local state = stateFor(actor)
    local mode = type(intent) == "table" and intent.mode or nil
    if mode == "bandit_human" or mode == "bandit_search" then
        return banditHumanCombat(actor, intent and intent.humanThreat,
            group, state, player)
    elseif mode == "bandit_investigate" then
        return moveToStaticPosition(actor, intent and intent.sound, "walk",
            "bandit_investigate_sound", group)
    elseif mode == "bandit_patrol" then
        return banditPatrol(actor, group, state)
    elseif mode == "hostile" then
        local threat = intent and intent.humanThreat or rememberHumanThreat(actor, player, state)
        if not threat and player and group.archetype ~= "bandit_camp" then
            local x, y, z = U().position(player)
            threat = { actor = player, id = U().idOf(player), x = x, y = y, z = z,
                visible = U().sameFloor(actor, player) and U().canSee(actor, player) }
        end
        return banditHumanCombat(actor, threat, group, state, player)
    elseif mode == "restitution_watch" then
        return guard(actor, group, state, affiliation and affiliation.role)
    end
    if type(mode) == "string" and string.sub(mode, 1, 9) == "contract_"
        and SC.FactionContracts and type(SC.FactionContracts.updateActor) == "function" then
        return SC.FactionContracts.updateActor(
            actor, player, runtime, intent.contract or intent, group, affiliation)
    end
    if type(mode) == "string" and string.sub(mode, 1, 5) == "life_"
        and SC.FactionLife and type(SC.FactionLife.updateActor) == "function" then
        local handled, reason = SC.FactionLife.updateActor(
            actor, player, runtime, intent.life or intent, group, affiliation)
        if handled or reason ~= "delegate_guard" then return handled, reason end
    end
    if mode == "fortify" or group.lifecycle == "fortifying" then
        local handled, reason = fortify(actor, group, state)
        if handled or reason ~= "no_fortification_job" then return handled, reason end
    end
    return guard(actor, group, state, affiliation and affiliation.role)
end

function Behavior.updateHumanCombat(actor, player, runtime, threat)
    if type(threat) ~= "table" or not threat.actor then
        return false, "human_threat_unavailable"
    end
    local state = stateFor(actor)
    if threat.visible ~= true then
        local handled, reason = moveToStaticPosition(actor, threat, "jog",
            "companion_search_hostile_last_seen")
        if reason == "search_position_reached" then state.humanContact = nil end
        return handled, reason
    end
    return hostile(actor, threat.actor, nil, state, player)
end

function Behavior.reset(actor)
    if actor then return Behavior.releaseActor(actor)
    else
        actorStates = setmetatable({}, { __mode = "k" })
        groupRosters = setmetatable({}, { __mode = "k" })
    end
end


function Behavior.releaseActor(actor)
    if actor == nil then return false end
    actorStates[actor] = nil
    -- Each roster is a strong participant array; invalidate them all so a
    -- retired native actor cannot survive through a long-lived faction group.
    for group in pairs(groupRosters) do groupRosters[group] = nil end
    return true
end

return Behavior
