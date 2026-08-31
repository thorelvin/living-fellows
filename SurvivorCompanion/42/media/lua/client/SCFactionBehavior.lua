-- SPDX-License-Identifier: MIT

local SC = SurvivorCompanion
SC.FactionBehavior = SC.FactionBehavior or {}

local Behavior = SC.FactionBehavior
local actorStates = setmetatable({}, { __mode = "k" })

local function U()
    return SC.GameplayUtil
end

local function stateFor(actor)
    local state = actorStates[actor]
    if not state then
        state = { nextActionAt = 0, nextPatrolAt = 0, patrolIndex = 0 }
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

local function bark(group, topic, fallback)
    local current = U().nowMs()
    if current < (tonumber(group.nextBarkAt) or 0) then return false end
    local actor = speaker(group)
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
        return SC.Navigation.request(actor, square, "walk", {
            action = "faction_approach_barricade", targetSquare = square,
        })
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

local function friendlyInLine(actor, player, group)
    if not U().pointSegmentDistanceSq then return false end
    for _, member in ipairs(group.members or {}) do
        if member.alive ~= false and member.away == nil and member.departed ~= true
            and member.actorId and member.actorId ~= U().idOf(actor) then
            local record = SC.Registry.byId(member.actorId)
            if record and record.actor and U().pointSegmentDistanceSq(record.actor, actor, player) <= 0.8 * 0.8
                and U().distance(record.actor, actor) > 0.75 then return true end
        end
    end
    return false
end

local function hostile(actor, player, group, state)
    local leash = tonumber(SC.Config.get("factionPursuitLeash")) or 15
    if territoryDistance(group, player) > leash then
        local target = group.house and U().loadedSquare(group.house.anchor) or nil
        if target and SC.Navigation then
            return SC.Navigation.request(actor, target, "jog", {
                action = "faction_break_pursuit", targetSquare = target, seekOpenEscape = true,
            })
        end
        return false, "hostile_target_outside_leash"
    end
    if U().distance(actor, player) > 1.65 then
        local primary, primaryOk = U().call(actor, "getPrimaryHandItem")
        local ranged = false
        if primaryOk and primary then
            local rangedValue, rangedOk = U().call(primary, "isRanged")
            ranged = rangedOk and rangedValue == true
        end
        if ranged and U().distance(actor, player) <= 12 and not friendlyInLine(actor, player, group) then
            return U().move(actor, "walk", {
                action = "attack_firearm", weapon = primary, target = player,
                factionCombat = true,
            })
        end
        if SC.Combat and type(SC.Combat.equipPreferred) == "function"
            and U().nowMs() >= (state.nextEquipAt or 0) then
            state.nextEquipAt = U().nowMs() + 2500
            SC.Combat.equipPreferred(actor, "best")
        end
        local square = U().squareOf(player)
        if square and SC.Navigation then
            return SC.Navigation.request(actor, square, "jog", {
                action = "faction_defend_territory", targetSquare = square,
            })
        end
        return false, "hostile_path_unavailable"
    end
    local primary, primaryOk = U().call(actor, "getPrimaryHandItem")
    if primaryOk and primary then
        return U().move(actor, "walk", {
            action = "attack_melee", weapon = primary, target = player, factionCombat = true,
        })
    end
    return U().move(actor, "walk", { action = "shove", target = player, factionCombat = true })
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
            return SC.Navigation.request(actor, square, "walk", {
                action = "faction_return_home", targetSquare = square,
            })
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
                        return SC.Navigation.request(actor, square, "walk", {
                            action = "faction_close_door", targetSquare = square,
                        })
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
        return SC.Navigation.request(actor, square, "walk", {
            action = "faction_guard_patrol", targetSquare = square,
        })
    end
    return false, "guard_patrol_square_blocked"
end

function Behavior.intentFor(actor, player, snapshot)
    local group = groupFor(actor)
    if not group then return nil end
    updateTerritory(group, player)
    ensureEmergencyJobs(group, type(snapshot) == "table" and snapshot.threatCount or 0)
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
        return { priority = 110, kind = "faction", mode = "hostile", factionId = group.id }
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
    if mode == "hostile" or group.standing == "Hostile" then
        if mode == "restitution_watch" then
            return guard(actor, group, state, affiliation and affiliation.role)
        end
        return hostile(actor, player, group, state)
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

function Behavior.reset(actor)
    if actor then actorStates[actor] = nil
    else actorStates = setmetatable({}, { __mode = "k" }) end
end

return Behavior
