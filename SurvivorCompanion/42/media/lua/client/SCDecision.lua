-- SPDX-License-Identifier: MIT

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
if not SC.GameplayUtil and type(require) == "function" then pcall(require, "SCGameplayUtil") end
if not SC.Positioning and type(require) == "function" then pcall(require, "SCPositioning") end

SC.Decision = SC.Decision or {}
local Decision = SC.Decision
local states = setmetatable({}, { __mode = "k" })
local lastGroupThreatWarningAt = -math.huge
local workReservations = {}
local targetedWorkKinds = { barricade = true, remove_barricade = true, dismantle = true }

local function U()
    return SC.GameplayUtil
end

local function stateFor(actor, runtime)
    local utility = U()
    local rootRuntime = utility.actorState(actor, runtime)
    rootRuntime.decision = rootRuntime.decision or {}
    states[actor] = rootRuntime.decision
    return rootRuntime.decision, rootRuntime
end

local function commandsFor(actor)
    if SC.Commands and type(SC.Commands.peek) == "function" then
        local ok, value = pcall(SC.Commands.peek, actor)
        if ok and type(value) == "table" then return value end
    end
    return {
        recruited = false,
        order = "wander",
        followDistance = U().config("followDistance") or 3,
        moveMode = "walk",
        scavenge = false,
        combatMode = "defensive",
        combatDoctrine = "close_defense",
        rideWithPlayer = true,
    }
end

local function commandMoveMode(commands, player)
    local requested = commands and commands.moveMode or "walk"
    if SC.Positioning and type(SC.Positioning.resolveMoveMode) == "function" then
        return SC.Positioning.resolveMoveMode(requested, player)
    end
    return requested == "copy" and "walk" or requested
end

local function medicalAssessment(actor)
    if SC.Medical and type(SC.Medical.assess) == "function" then
        local ok, assessment = pcall(SC.Medical.assess, actor)
        if ok and type(assessment) == "table" then return assessment end
    end
    return {
        health = U().nativeHealth(actor), alive = not U().isDead(actor),
        critical = false, needsBandage = false, downed = false,
    }
end

local function rescueNeed(player, snapshot)
    local score = 0
    if player and SC.Medical and type(SC.Medical.assess) == "function" then
        local ok, assessment = pcall(SC.Medical.assess, player)
        if ok and assessment then
            if assessment.critical then score = score + 35 end
            score = score + (assessment.bleedingCount or 0) * 22
            if assessment.downed then score = score + 45 end
        end
    end
    if snapshot and type(snapshot.allies) == "table" then
        for _, ally in ipairs(snapshot.allies) do
            local assessment = medicalAssessment(ally.actor)
            local allyScore = (assessment.critical and 25 or 0)
                + (assessment.bleedingCount or 0) * 18
                + (assessment.downed and 40 or 0)
            if allyScore > score then score = allyScore end
        end
    end
    return score
end

local function recentSharedAlert(actor, snapshot, state, current)
    if type(snapshot) ~= "table" or type(snapshot.sounds) ~= "table" then return nil end
    local newest
    for _, sound in ipairs(snapshot.sounds) do
        local soundTime = tonumber(sound.time) or (current - (tonumber(sound.ageMs) or 0))
        if sound.kind == "companion_alert" and sound.source ~= actor
            and current - soundTime <= (U().config("sharedAlertMemoryMs") or 5000)
            and soundTime > (state.lastHandledAlertTime or -math.huge)
            and (not newest or soundTime > (tonumber(newest.time) or -math.huge)) then
            newest = sound
        end
    end
    return newest
end

local function evaluate(actor, player, snapshot, commands, assessment, needs, state, current)
    local candidates = {}
    local downtimeAdded = false
    local function add(kind, score, emergency, detail)
        if emergency ~= true then
            if SC.Personality and type(SC.Personality.adjustDecision) == "function" then
                score = score + SC.Personality.adjustDecision(commands.personalityProfile,
                    { kind = kind, score = score }, {
                        rescue = type(detail) == "table" and detail.rescue == true,
                        indoors = type(snapshot) == "table" and snapshot.indoors == true,
                    })
            end
            if SC.Objectives and type(SC.Objectives.decisionBonus) == "function" then
                score = score + SC.Objectives.decisionBonus(commands.objectives, kind)
            end
            if SC.Autonomy and type(SC.Autonomy.decisionBonus) == "function" then
                score = score + SC.Autonomy.decisionBonus(actor, kind)
            end
        end
        candidates[#candidates + 1] = {
            kind = kind,
            score = score,
            emergency = emergency == true,
            detail = detail,
        }
        if kind == "downtime" then downtimeAdded = true end
    end
    if assessment.downed or (assessment.health > 0 and assessment.health <= (U().config("downedHealth") or 18)) then
        add("medical", 140, true)
    elseif assessment.needsBandage or assessment.critical then
        add("medical", 96 + (assessment.bleedingCount or 0) * 8, assessment.bleedingCount and assessment.bleedingCount > 0)
    end
    local rescue = rescueNeed(player, snapshot)
    if rescue > 0 and (snapshot.immediateCount or 0) == 0 then
        add("medical", 64 + rescue, rescue >= 40, { rescue = true })
    end

    local threatCount = snapshot.threatCount or #(snapshot.threats or {})
    local immediate = snapshot.immediateCount or #(snapshot.immediateAttackers or {})
    if threatCount == 0 and SC.Positioning
        and type(SC.Positioning.activeConversation) == "function"
        and SC.Positioning.activeConversation(actor) then
        add("conversation", 68, false)
    end
    if SC.InfectionCrisis and type(SC.InfectionCrisis.intentFor) == "function" then
        local crisis = SC.InfectionCrisis.intentFor(actor, player)
        if crisis and crisis.priority and crisis.priority > 0 then
            add("infection_crisis", crisis.priority, false, crisis)
        end
    end
    if type(needs) == "table" and (needs.active or needs.hungry or needs.thirsty)
        and threatCount == 0 then
        local pressure = math.max(needs.hunger or 0, needs.thirst or 0)
        add("needs", needs.active and 112 or (62 + pressure * 42), needs.emergency)
    end
    if threatCount > 0 then
        local combatScore = 72 + immediate * 17 + (snapshot.pressure or 0) * 5
        local doctrine = commands.combatDoctrine
            or (commands.combatMode == "aggressive" and "weapons_free")
            or (commands.combatMode == "passive" and "stealth")
            or "close_defense"
        if doctrine == "weapons_free" then combatScore = combatScore + 14 end
        if doctrine == "stealth" and immediate == 0
            and (snapshot.player and snapshot.player.danger or 0) == 0 then
            combatScore = 30
        elseif doctrine == "close_defense" and immediate == 0
            and (tonumber(snapshot.closeThreatCount) or 0) == 0
            and (snapshot.player and snapshot.player.immediateThreats or 0) == 0 then
            combatScore = 28
        end
        add("combat", combatScore, immediate > 0 or snapshot.encircled)
    end

    if commands.recruited and SC.Autonomy and type(SC.Autonomy.intentFor) == "function" then
        local okay, intent = pcall(SC.Autonomy.intentFor, actor, player, snapshot, commands)
        if okay and type(intent) == "table" and tonumber(intent.priority) then
            add(intent.kind, tonumber(intent.priority), false, intent)
        end
    end

    if threatCount == 0 and SC.Logistics and type(SC.Logistics.status) == "function" then
        local ok, load = pcall(SC.Logistics.status, actor)
        if ok and load and load.shouldManage then
            -- Overload beats routine follow/work, but never urgent medicine,
            -- needs, retreat, or combat survival.
            add("logistics", load.overloaded and 92 or 74, false, load)
        end
    end

    local factionIntent
    if not commands.recruited and SC.FactionBehavior
        and type(SC.FactionBehavior.intentFor) == "function" then
        local ok, value = pcall(SC.FactionBehavior.intentFor, actor, player, snapshot)
        if ok and type(value) == "table" and tonumber(value.priority) then
            factionIntent = value
            add("faction", tonumber(value.priority), value.mode == "hostile", value)
        end
    end

    if factionIntent then
        -- Faction residents use their territorial policy and can never fall
        -- through to the generic recruitable encounter state.
    elseif not commands.recruited then
        add("encounter", threatCount > 0 and 84 or 48, threatCount > 0)
    else
        local alert = threatCount == 0 and recentSharedAlert(actor, snapshot, state, current) or nil
        if alert then
            local closeRadius = U().config("sharedAlertCloseRadius") or 8
            local distanceSq = tonumber(alert.distanceSq) or U().distanceSq(actor, alert)
            add("alert", distanceSq <= closeRadius * closeRadius and 66 or 45, false, alert)
        end
        if commands.order == "retreat" then add("retreat", 122, true)
        elseif commands.order == "regroup" then add("follow", 82, false)
        elseif commands.order == "follow" then
            local playerMoving, movingOk = U().call(player, "isMoving")
            local close = player and U().distance(actor, player)
                <= math.max(3, (commands.followDistance or 3) + 1.5)
            if close and snapshot.indoors == true
                and (not movingOk or playerMoving ~= true) then
                add("downtime", 52, false)
                add("follow", 22, false)
            else
                add("follow", 48, false)
            end
        elseif commands.order == "stay" or commands.order == "guard" then
            local anchor = type(commands.anchor) == "table" and U().loadedSquare(commands.anchor) or nil
            local allowed = commands.order == "guard" and (U().config("guardRadius") or 5) or 0.7
            local outside = anchor and U().distance(actor, anchor) > allowed
            local patrolDue = commands.order == "guard" and (
                state.guardPatrolTarget ~= nil or current >= (state.guardPatrolDue or 0))
            if outside or patrolDue then add("tactical", 56, false) end
            add("downtime", 30, false)
        elseif commands.order == "move_to" or commands.order == "check_room"
            or commands.order == "interact" or commands.order == "work" then
            add("tactical", commands.order == "work" and 62 or 56, false)
        elseif commands.order == "base_duty" then
            add("base_work", 58, false)
        end
        if commands.scavenge and threatCount == 0 and commands.order ~= "regroup"
            and commands.order ~= "retreat" then add("scavenge", 32, false) end
        if threatCount == 0 and not downtimeAdded
            and (commands.order ~= "follow" or snapshot.indoors == true) then
            add("downtime", 10, false)
        end
    end
    U().sortByScoreDescending(candidates)
    return candidates
end

local function selectWithHysteresis(state, candidates, now)
    local best = candidates[1]
    if not best then return nil end
    if best.emergency then return best end
    if state.current and now < (state.minimumUntil or 0) then
        local currentCandidate
        for _, candidate in ipairs(candidates) do
            if candidate.kind == state.current then currentCandidate = candidate break end
        end
        if currentCandidate and best.score < currentCandidate.score + (U().config("decisionHysteresis") or 8) then
            return currentCandidate
        end
    end
    return best
end

local function enforceVehicleExitPolicy(actor, player, commands)
    local utility = U()
    local actorVehicle, actorVehicleOk = utility.call(actor, "getVehicle")
    if not actorVehicleOk or actorVehicle == nil then return nil end
    local playerVehicle, playerVehicleOk = utility.call(player, "getVehicle")
    local mustExit = commands.rideWithPlayer == false
        or not playerVehicleOk or playerVehicle == nil or playerVehicle ~= actorVehicle
    if not mustExit then return nil end
    if not SC.Vehicle or type(SC.Vehicle.isStationary) ~= "function" then
        return false, "vehicle_adapter_unavailable"
    end
    local stopped, stopReason = SC.Vehicle.isStationary(actorVehicle)
    if stopped ~= true then
        return true, stopReason == "vehicle is moving"
            and "waiting_for_safe_exit" or "vehicle_speed_unavailable"
    end
    if type(SC.Vehicle.cancelTransaction) == "function" then
        SC.Vehicle.cancelTransaction(actor, "vehicle_exit_policy_changed")
    end
    if not utility.move(actor, "walk", {
        action = "exit_vehicle",
        vehicle = actorVehicle,
        policyDisabled = commands.rideWithPlayer == false,
        followPlayer = playerVehicle ~= actorVehicle,
        transactional = true,
        restoreByDoor = true,
    }) then return false, "policy_exit_vehicle_rejected" end
    return true, "exiting_vehicle"
end

local function doFollow(actor, player, rootRuntime, commands, snapshot)
    local utility = U()
    if not player or not utility.isValidActor(player) then return false, "player_unavailable" end
    local playerVehicle, playerVehicleOk = utility.call(player, "getVehicle")
    local actorVehicle, actorVehicleOk = utility.call(actor, "getVehicle")
    if playerVehicleOk and playerVehicle and actorVehicleOk and actorVehicle == playerVehicle then
        if commands.rideWithPlayer ~= false then return true, "riding_with_player" end
        if not SC.Vehicle or type(SC.Vehicle.isStationary) ~= "function" then
            return false, "vehicle_adapter_unavailable"
        end
        local stopped, stopReason = SC.Vehicle.isStationary(actorVehicle)
        if stopped ~= true then
            return true, stopReason == "vehicle is moving"
                and "waiting_for_safe_exit" or "vehicle_speed_unavailable"
        end
        if not utility.move(actor, "walk", {
            action = "exit_vehicle",
            vehicle = actorVehicle,
            policyDisabled = true,
            transactional = true,
            restoreByDoor = true,
        }) then return false, "policy_exit_vehicle_rejected" end
        return true, "exiting_vehicle"
    elseif playerVehicleOk and playerVehicle and actorVehicleOk and actorVehicle ~= nil then
        if not SC.Vehicle or type(SC.Vehicle.isStationary) ~= "function" then
            return false, "vehicle_adapter_unavailable"
        end
        local stopped, stopReason = SC.Vehicle.isStationary(actorVehicle)
        if stopped ~= true then
            return true, stopReason == "vehicle is moving"
                and "waiting_for_safe_exit" or "vehicle_speed_unavailable"
        end
        if not utility.move(actor, "walk", {
            action = "exit_vehicle",
            vehicle = actorVehicle,
            followPlayer = true,
            transactional = true,
            restoreByDoor = true,
        }) then return false, "wrong_vehicle_exit_rejected" end
        return true, "exiting_wrong_vehicle"
    elseif playerVehicleOk and playerVehicle then
        if not SC.Vehicle or type(SC.Vehicle.preflightBoard) ~= "function"
            or type(SC.Vehicle.boardingSquare) ~= "function"
            or type(SC.Vehicle.beginBoarding) ~= "function"
            or type(SC.Vehicle.isStationary) ~= "function"
            or type(SC.Vehicle.assignmentFor) ~= "function" then
            return false, "vehicle_adapter_unavailable"
        end
        if commands.rideWithPlayer == false then
            if type(SC.Vehicle.cancelTransaction) == "function" then
                SC.Vehicle.cancelTransaction(actor, "ride_with_player_disabled")
            end
            if not utility.stop(actor) then return false, "vehicle_opt_out_stop_rejected" end
            return true, "ride_with_player_disabled"
        end
        local assignment, assignmentReason = SC.Vehicle.assignmentFor(
            actor, playerVehicle, player)
        if assignment == nil then
            if type(SC.Vehicle.cancelTransaction) == "function" then
                SC.Vehicle.cancelTransaction(actor, assignmentReason or "vehicle_assignment_lost")
            end
            if assignmentReason == "vehicle_capacity_wait" then
                if not utility.stop(actor) then return false, "vehicle_capacity_wait_stop_rejected" end
                return true, "vehicle_capacity_wait"
            end
            return false, "vehicle_manifest_rejected:" .. tostring(assignmentReason)
        end
        local stopped, stopReason = SC.Vehicle.isStationary(playerVehicle)
        if stopped ~= true then
            if type(SC.Vehicle.cancelTransaction) == "function" then
                SC.Vehicle.cancelTransaction(actor, "vehicle_moving_before_board")
            end
            if not utility.stop(actor) then return false, "vehicle_wait_stop_rejected" end
            return true, stopReason == "vehicle is moving"
                and "waiting_for_vehicle_to_stop" or "vehicle_speed_unavailable"
        end
        local transaction, transactionReason = SC.Vehicle.beginBoarding(
            actor, playerVehicle, assignment.seat, { followPlayer = true })
        if transaction == nil then
            return false, "vehicle_transaction_rejected:" .. tostring(transactionReason)
        end
        local prepared, prepareReason = SC.Vehicle.preflightBoard(
            actor, playerVehicle, assignment.seat)
        if prepared ~= nil then
            if not utility.stop(actor) then return false, "vehicle_boarding_stop_rejected" end
            if not utility.move(actor, "walk", {
                action = "board_vehicle",
                vehicle = playerVehicle,
                seat = prepared.seat,
                preflight = prepared,
                followPlayer = true,
                transactional = true,
                allowVirtualSeat = false,
                supervisorToken = transaction.supervisorToken,
            }) then
                SC.Vehicle.failTransaction(actor, "board_vehicle_dispatch_rejected")
                return false, "board_vehicle_rejected"
            end
            return true, "boarding_vehicle"
        end
        if prepareReason ~= "companion is not at the passenger door" then
            SC.Vehicle.failTransaction(actor, "vehicle_board_preflight_failed", {
                reason = prepareReason,
            })
            return false, "board_vehicle_rejected:" .. tostring(prepareReason)
        end
        local target, seat, targetReason = SC.Vehicle.boardingSquare(
            actor, playerVehicle, assignment.seat)
        if target == nil then
            SC.Vehicle.failTransaction(actor, "vehicle_boarding_square_failed", {
                reason = targetReason,
            })
            return false, "vehicle_approach_rejected:" .. tostring(targetReason)
        end
        if not SC.Navigation or type(SC.Navigation.request) ~= "function" then
            SC.Vehicle.failTransaction(actor, "vehicle_navigation_unavailable")
            return false, "navigation_unavailable"
        end
        local distance = utility.distance(actor, target)
        local accepted, reason = SC.Navigation.request(actor, target,
            distance > 8 and "run" or "walk", {
            action = "approach_vehicle",
            vehicle = playerVehicle,
            seat = seat,
            player = player,
            snapshot = snapshot,
            desiredDistance = 0,
            urgent = false,
            movementPriority = 30,
            supervisorToken = transaction.supervisorToken,
        })
        if accepted ~= true then
            SC.Vehicle.failTransaction(actor, "vehicle_approach_failed", { reason = reason })
        end
        return accepted, reason
    elseif actorVehicleOk and actorVehicle and (not playerVehicleOk or not playerVehicle) then
        if not SC.Vehicle or type(SC.Vehicle.isStationary) ~= "function" then
            return false, "vehicle_adapter_unavailable"
        end
        local stopped, stopReason = SC.Vehicle.isStationary(actorVehicle)
        if stopped ~= true then
            return true, stopReason == "vehicle is moving"
                and "waiting_for_safe_exit" or "vehicle_speed_unavailable"
        end
        if not utility.move(actor, "walk", {
            action = "exit_vehicle",
            vehicle = actorVehicle,
            followPlayer = true,
            transactional = true,
            restoreByDoor = true,
        }) then return false, "exit_vehicle_rejected" end
        return true, "exiting_vehicle"
    end
    if SC.Vehicle and type(SC.Vehicle.cancelTransaction) == "function" then
        SC.Vehicle.cancelTransaction(actor, "player_not_in_vehicle")
    end
    if not SC.Positioning or type(SC.Positioning.formationTarget) ~= "function" then
        return false, "positioning_unavailable"
    end
    local target = SC.Positioning.formationTarget(actor, player, commands, snapshot)
    if not target then return false, "no_formation_target" end
    local leaderDistance = utility.distance(actor, player)
    local desired = commands.followDistance or 3
    if commands.order ~= "regroup" and SC.Positioning.shouldHold(actor, target) then
        -- Stop first: the regular stop adapter deliberately clears tactical
        -- posture. Copy the player's posture only after locomotion has stopped
        -- so a crouched companion stays crouched instead of flickering upright.
        if not utility.stop(actor) then return false, "formation_stop_rejected" end
        local aware, awarenessReason
        if type(SC.Positioning.updateHoldAwareness) == "function" then
            aware, awarenessReason = SC.Positioning.updateHoldAwareness(
                actor, player, snapshot)
        end
        if type(SC.Positioning.syncCopiedPosture) == "function" then
            local synced, syncReason = SC.Positioning.syncCopiedPosture(
                actor, player, commands.moveMode)
            if synced == false then return false, syncReason end
        end
        if aware ~= nil then return aware == true, awarenessReason end
        return true, "holding_formation"
    end
    local mode, posture = SC.Positioning.followMode(
        commands.moveMode or "copy", commands.stress, leaderDistance, player)
    if not SC.Navigation or type(SC.Navigation.request) ~= "function" then return false, "navigation_unavailable" end
    return SC.Navigation.request(actor, target, mode, {
        action = commands.order == "regroup" and "regroup" or "follow_formation",
        player = player,
        snapshot = snapshot,
        followRecovery = true,
        desiredDistance = desired,
        urgent = leaderDistance >= (utility.config("followFarDistance") or 18),
        movementPriority = 20,
        stressPosture = posture,
    })
end

local function anchorSquare(commands)
    if type(commands.anchor) ~= "table" then return nil end
    return U().loadedSquare(commands.anchor)
end

local function switchToStay(actor, player)
    if not SC.Commands or type(SC.Commands.issue) ~= "function" then
        return false, "stay_transition_commands_unavailable"
    end
    local called, accepted, reason = pcall(
        SC.Commands.issue,
        U().idOf(actor),
        "stay",
        nil,
        player
    )
    if not called then return false, "stay_transition_error" end
    if accepted ~= true then
        return false, "stay_transition_rejected:" .. tostring(reason or "unknown")
    end
    return true, "stay"
end

local function navigationArrived(actor, target, status)
    if status == "arrived" then return true end
    local actorKey = U().squareKey(U().squareOf(actor))
    local targetKey = U().squareKey(U().loadedSquare(target))
    return actorKey ~= nil and actorKey == targetKey
end

local function resolveWorkObject(commands)
    local utility = U()
    local target = type(commands.workTarget) == "table" and commands.workTarget or nil
    if not target or targetedWorkKinds[target.kind] ~= true
        or tonumber(target.objectIndex) == nil then
        return nil, nil, "invalid_work_target"
    end
    local square = utility.loadedSquare(target)
    if not square then return nil, nil, "work_target_not_loaded" end
    local expectedIndex = math.floor(tonumber(target.objectIndex))
    local object = target.object
    if object then
        local currentIndex, indexOk = utility.call(object, "getObjectIndex")
        local objectSquare = utility.squareOf(object)
        if not indexOk or tonumber(currentIndex) ~= expectedIndex
            or utility.squareKey(objectSquare) ~= utility.squareKey(square) then
            object = nil
        end
    end
    if not object then
        local objects, objectsOk = utility.call(square, "getObjects")
        if objectsOk then object = utility.listGet(objects, expectedIndex) end
    end
    if not object then
        return nil, square, "work_target_changed"
    end
    if target.kind == "barricade" or target.kind == "remove_barricade" then
        if not utility.hasMethod(object, "getBarricadeForCharacter") then
            return nil, square, "work_target_changed"
        end
    elseif target.kind == "dismantle" then
        local isThumpable = false
        if type(instanceof) == "function" then
            local called, value = pcall(instanceof, object, "IsoThumpable")
            isThumpable = called and value == true
        end
        local dismantlable, dismantlableOk = utility.call(object, "isDismantable")
        if not isThumpable or not dismantlableOk or dismantlable ~= true then
            return nil, square, "work_target_changed"
        end
    end
    local currentIndex, indexOk = utility.call(object, "getObjectIndex")
    if not indexOk or tonumber(currentIndex) ~= expectedIndex then
        return nil, square, "work_target_changed"
    end
    target.object = object
    return object, square, nil
end

local function removalInteractionSquare(object, target, fallback)
    if type(target) ~= "table" or target.kind ~= "remove_barricade"
        or target.barricadeSide ~= "opposite" then return fallback end
    local north, northOk = U().call(object, "getNorth")
    local x, y, z = U().position(fallback)
    if x == nil then return fallback end
    local candidate = {
        x = northOk and north == true and x or x - 1,
        y = northOk and north == true and y - 1 or y,
        z = z or 0,
    }
    return U().loadedSquare(candidate) or fallback
end

local function barricadePlanks(object, actor)
    local barricade, ok = U().call(object, "getBarricadeForCharacter", actor)
    if not ok or not barricade then return 0 end
    local count, countOk = U().call(barricade, "getNumPlanks")
    if countOk and type(count) == "number" then return count end
    return 0
end

local function selectedBarricade(object, actor, target)
    local method = type(target) == "table" and target.barricadeSide == "same"
        and "getBarricadeOnSameSquare"
        or type(target) == "table" and target.barricadeSide == "opposite"
            and "getBarricadeOnOppositeSquare" or nil
    if method then
        local barricade, ok = U().call(object, method)
        if ok then return barricade end
    end
    local barricade, ok = U().call(object, "getBarricadeForCharacter", actor)
    return ok and barricade or nil
end

local function selectedBarricadePlanks(object, actor, target)
    local barricade = selectedBarricade(object, actor, target)
    if not barricade then return nil end
    local count, countOk = U().call(barricade, "getNumPlanks")
    return countOk and math.max(0, math.floor(tonumber(count) or 0)) or 0
end

local function workKey(commands)
    local target = type(commands) == "table" and commands.workTarget or nil
    if type(target) ~= "table" or tonumber(target.objectIndex) == nil then return nil end
    local square = U().squareKey(U().loadedSquare(target))
    if not square then return nil end
    return tostring(target.kind or "work") .. ":" .. square .. ":"
        .. tostring(math.floor(tonumber(target.objectIndex)))
end

local function releaseWorkReservation(actor, state)
    local key = state and state.workReservationKey or nil
    local reservation = key and workReservations[key] or nil
    if reservation and reservation.actor == actor then workReservations[key] = nil end
    if state then state.workReservationKey = nil end
end

local function reserveWork(actor, commands, state, current)
    local key = workKey(commands)
    if not key then return false, "invalid_work_reservation" end
    if state.workReservationKey and state.workReservationKey ~= key then
        releaseWorkReservation(actor, state)
    end
    local reservation = workReservations[key]
    if reservation and reservation.actor ~= actor and reservation.expires > current then
        return false, "work_reserved_by_companion"
    end
    workReservations[key] = {
        actor = actor,
        expires = current + (U().config("workReservationMs") or 45000),
    }
    state.workReservationKey = key
    return true, "work_reserved"
end

local function cancelWork(actor, state, reason)
    local cancelled, cancelReason = true, nil
    if SC.NativeActions and type(SC.NativeActions.cancelWork) == "function" then
        local called
        called, cancelled, cancelReason = pcall(SC.NativeActions.cancelWork, actor, reason)
        if not called then cancelled, cancelReason = false, cancelled end
    end
    if cancelled ~= true then return false, "work_cancel_failed:" .. tostring(cancelReason) end
    state.workAction = nil
    state.workAssignedAt = nil
    if SC.Encounter and type(SC.Encounter.cancelPlayerSupply) == "function" then
        SC.Encounter.cancelPlayerSupply(actor)
    end
    releaseWorkReservation(actor, state)
    return true, reason or "work_cancelled"
end

local function finishWork(actor, player, state, reason)
    if SC.NativeActions and type(SC.NativeActions.finishWork) == "function" then
        local called, finished, finishReason = pcall(SC.NativeActions.finishWork, actor)
        if not called or finished ~= true then
            return false, "work_cleanup_failed:" .. tostring(finishReason or finished)
        end
    end
    state.workAction = nil
    state.workAssignedAt = nil
    if SC.Encounter and type(SC.Encounter.cancelPlayerSupply) == "function" then
        SC.Encounter.cancelPlayerSupply(actor)
    end
    releaseWorkReservation(actor, state)
    if not SC.Commands or type(SC.Commands.issue) ~= "function" then
        return false, "work_finish_commands_unavailable"
    end
    local called, accepted, commandReason = pcall(
        SC.Commands.issue, U().idOf(actor), "finish_work", { reason = reason }, player)
    if not called or accepted ~= true then
        return false, "work_finish_failed:" .. tostring(commandReason or accepted)
    end
    return true, reason or "work_finished"
end

local function reportWorkFailure(actor, reason)
    local lowered = string.lower(tostring(reason or ""))
    local key, fallback, topic = "IGUI_SC_Work_Cannot", "I can't do that safely.", "work.cannot"
    if string.find(lowered, "hammer", 1, true) then
        key, fallback, topic = "IGUI_SC_Work_NeedHammer", "I need an unbroken hammer.", "work.hammer"
    elseif string.find(lowered, "plank", 1, true) then
        key, fallback, topic = "IGUI_SC_Work_NeedPlank", "I need a plank.", "work.plank"
    elseif string.find(lowered, "nail", 1, true) then
        key, fallback, topic = "IGUI_SC_Work_NeedNails", "I need two nails.", "work.nails"
    elseif string.find(lowered, "saw", 1, true) then
        key, fallback, topic = "IGUI_SC_Work_NeedSaw", "I need an unbroken saw.", "work.saw"
    elseif string.find(lowered, "screwdriver", 1, true) then
        key, fallback, topic = "IGUI_SC_Work_NeedScrewdriver", "I need an unbroken screwdriver.", "work.screwdriver"
    elseif string.find(lowered, "blowtorch", 1, true) then
        key, fallback, topic = "IGUI_SC_Work_NeedBlowTorch", "I need a fueled blowtorch.", "work.blowtorch"
    elseif string.find(lowered, "remove", 1, true)
        or string.find(lowered, "pry", 1, true) then
        key, fallback, topic = "IGUI_SC_Work_NeedPryTool", "I need a tool that can remove barricades.", "work.pry"
    elseif string.find(lowered, "timed action", 1, true)
        or string.find(lowered, "already", 1, true) then
        key, fallback, topic = "IGUI_SC_Work_Busy", "I need to finish what I'm doing first.", "work.busy"
    end
    if SC.Dialogue and type(SC.Dialogue.say) == "function" then
        SC.Dialogue.say(actor, topic, nil, nil, { fallback = U().text(key, fallback) })
    else
        U().say(actor, U().text(key, fallback))
    end
end

local function doWork(actor, player, commands, snapshot, state)
    local utility = U()
    local current = utility.nowMs()
    state.workAssignedAt = state.workAssignedAt or current
    if current - state.workAssignedAt > (utility.config("workApproachTimeoutMs") or 60000) then
        return finishWork(actor, player, state, "work_timeout")
    end
    local object, targetSquare, targetReason = resolveWorkObject(commands)
    if not object then return finishWork(actor, player, state, targetReason) end
    local reserved, reservationReason = reserveWork(actor, commands, state, current)
    if not reserved then
        if not utility.stop(actor) then return false, "work_wait_stop_rejected" end
        return true, reservationReason
    end
    local interactionSquare = removalInteractionSquare(object, commands.workTarget, targetSquare)
    local wrongRemovalSide = commands.workTarget.kind == "remove_barricade"
        and utility.squareKey(utility.squareOf(actor)) ~= utility.squareKey(interactionSquare)
    if utility.distance(actor, object) > 1.75 or wrongRemovalSide then
        if not SC.Navigation or type(SC.Navigation.request) ~= "function" then
            return finishWork(actor, player, state, "work_navigation_unavailable")
        end
        return SC.Navigation.request(actor, interactionSquare, commandMoveMode(commands, player), {
            action = "approach_interaction",
            targetSquare = interactionSquare,
            object = object,
            snapshot = snapshot,
        })
    end


    if commands.workTarget.kind == "remove_barricade" then
        local currentPlanks = selectedBarricadePlanks(object, actor, commands.workTarget)
        if currentPlanks == nil then
            return finishWork(actor, player, state, "barricade_removed")
        end
        local work = state.workAction
        if work then
            if SC.NativeActions and type(SC.NativeActions.isWorkActive) == "function"
                and SC.NativeActions.isWorkActive(actor) then
                return true, "removing_barricade"
            end
            local elapsed = utility.nowMs() - (work.startedAt or 0)
            if elapsed <= 500 then return true, "remove_barricade_starting" end
            if currentPlanks < (work.initialPlanks or currentPlanks) then
                local cleaned, cleanupReason = SC.NativeActions.finishWork(actor)
                if cleaned ~= true then return false, cleanupReason end
                state.workAction = nil
                return true, "remove_barricade_continuing"
            end
            local cancelled, cancelReason = cancelWork(actor, state, "remove_barricade_interrupted")
            if not cancelled then return false, cancelReason end
            return finishWork(actor, player, state, "remove_barricade_interrupted")
        end
        local accepted, rejectionReason = utility.move(actor, "walk", {
            action = "remove_barricade",
            object = object,
            targetSquare = interactionSquare,
            transactional = true,
        })
        if not accepted then
            reportWorkFailure(actor, rejectionReason)
            return finishWork(actor, player, state, "remove_barricade_rejected")
        end
        state.workAction = {
            startedAt = utility.nowMs(),
            initialPlanks = currentPlanks,
            objectIndex = commands.workTarget.objectIndex,
        }
        return true, "remove_barricade_started"
    elseif commands.workTarget.kind == "dismantle" then
        local work = state.workAction
        if work then
            if SC.NativeActions and type(SC.NativeActions.isWorkActive) == "function"
                and SC.NativeActions.isWorkActive(actor) then
                return true, "dismantling"
            end
            local elapsed = utility.nowMs() - (work.startedAt or 0)
            if elapsed <= 500 then return true, "dismantle_starting" end
            local cancelled, cancelReason = cancelWork(actor, state, "dismantle_interrupted")
            if not cancelled then return false, cancelReason end
            return finishWork(actor, player, state, "dismantle_interrupted")
        end
        local accepted, rejectionReason = utility.move(actor, "walk", {
            action = "dismantle",
            object = object,
            targetSquare = targetSquare,
            transactional = true,
        })
        if not accepted then
            reportWorkFailure(actor, rejectionReason)
            return finishWork(actor, player, state, "dismantle_rejected")
        end
        state.workAction = {
            startedAt = utility.nowMs(),
            objectIndex = commands.workTarget.objectIndex,
        }
        return true, "dismantle_started"
    end

    local currentPlanks = barricadePlanks(object, actor)
    local work = state.workAction
    if work then
        if currentPlanks > (work.initialPlanks or 0) then
            if SC.NativeActions and type(SC.NativeActions.isWorkActive) == "function"
                and SC.NativeActions.isWorkActive(actor) then
                return true, "barricade_finishing"
            end
            return finishWork(actor, player, state, "barricade_completed")
        end
        local nativeActions, actionsOk = utility.call(actor, "getCharacterActions")
        local elapsed = utility.nowMs() - (work.startedAt or 0)
        if actionsOk and utility.listSize(nativeActions) > 0 and elapsed <= 30000 then
            return true, "barricading"
        end
        if elapsed <= 500 then return true, "barricade_starting" end
        local cancelled, cancelReason = cancelWork(actor, state, "barricade_interrupted")
        if not cancelled then return false, cancelReason end
        return finishWork(actor, player, state, "barricade_interrupted")
    end

    -- The baseline is persisted with the one-shot order. If the world already
    -- contains the requested extra plank after a save/load (or another worker
    -- completed the same queued job), finish the role transition without
    -- applying the construction twice.
    local initialPlanks = math.max(0,
        math.floor(tonumber(commands.workTarget.initialPlanks) or 0))
    if currentPlanks > initialPlanks then
        return finishWork(actor, player, state, "barricade_already_completed")
    end

    if SC.Logistics and type(SC.Logistics.prepareBuild) == "function" then
        local ready, handled, supplyReason = SC.Logistics.prepareBuild(
            actor, targetSquare, snapshot, commandMoveMode(commands, player))
        if not ready then
            if handled then return true, supplyReason or "gathering_build_supplies" end
            reportWorkFailure(actor, supplyReason)
            return finishWork(actor, player, state, "build_supplies_unavailable")
        end
    end

    local accepted, rejectionReason = utility.move(actor, "walk", {
        action = "barricade",
        object = object,
        targetSquare = targetSquare,
        transactional = true,
    })
    if not accepted then
        reportWorkFailure(actor, rejectionReason)
        return finishWork(actor, player, state, "barricade_rejected")
    end
    state.workAction = {
        startedAt = utility.nowMs(),
        initialPlanks = currentPlanks,
        objectIndex = commands.workTarget.objectIndex,
    }
    return true, "barricade_started"
end

local function doTactical(actor, player, rootRuntime, commands, snapshot, state)
    local utility = U()
    if commands.order == "work" then
        return doWork(actor, player, commands, snapshot, state)
    end
    if commands.order == "stay" or commands.order == "guard" then
        local anchor = anchorSquare(commands) or utility.squareOf(actor)
        local allowed = commands.order == "guard" and (utility.config("guardRadius") or 5) or 0.7
        if utility.distance(actor, anchor) > allowed then
            state.guardPatrolTarget = nil
            if SC.Navigation and type(SC.Navigation.request) == "function" then
                return SC.Navigation.request(actor, anchor, commandMoveMode(commands, player), {
                    action = "return_to_" .. commands.order,
                    snapshot = snapshot,
                })
            end
            return false, "navigation_unavailable"
        end
        if commands.order == "guard" then
            local current = utility.nowMs()
            local patrolTarget = state.guardPatrolTarget
                and utility.loadedSquare(state.guardPatrolTarget) or nil
            if patrolTarget and utility.distance(actor, patrolTarget) <= 0.8 then
                state.guardPatrolTarget = nil
                state.guardPatrolDue = current + (utility.config("guardPatrolIntervalMs") or 30000)
                if not utility.stop(actor) then return false, "guard_patrol_stop_rejected" end
                return true, "guard_patrol_complete"
            end
            if not patrolTarget and current >= (state.guardPatrolDue or 0) then
                local ax, ay, az = utility.position(anchor)
                local radius = math.max(2, math.min(4, math.floor(allowed)))
                local offsets = {
                    { radius, 0 }, { 0, radius }, { -radius, 0 }, { 0, -radius },
                    { radius - 1, radius - 1 }, { 1 - radius, radius - 1 },
                    { 1 - radius, 1 - radius }, { radius - 1, 1 - radius },
                }
                local start = ((state.guardPatrolIndex or utility.stableHash(utility.idOf(actor)))
                    % #offsets) + 1
                for step = 0, #offsets - 1 do
                    local offset = offsets[((start + step - 1) % #offsets) + 1]
                    local candidate = utility.gridSquare(ax + offset[1], ay + offset[2], az)
                    if candidate and utility.isSquareFree(candidate) then
                        patrolTarget = candidate
                        state.guardPatrolTarget = {
                            x = select(1, utility.position(candidate)),
                            y = select(2, utility.position(candidate)),
                            z = select(3, utility.position(candidate)),
                        }
                        state.guardPatrolIndex = start + step
                        break
                    end
                end
                if not patrolTarget then
                    state.guardPatrolDue = current + (utility.config("guardPatrolIntervalMs") or 30000)
                    if not utility.stop(actor) then return false, "guard_patrol_stop_rejected" end
                    return true, "guard_holding"
                end
            end
            if patrolTarget then
                if not SC.Navigation or type(SC.Navigation.request) ~= "function" then
                    return false, "navigation_unavailable"
                end
                return SC.Navigation.request(actor, patrolTarget, "walk", {
                    action = "guard_patrol",
                    targetSquare = patrolTarget,
                    snapshot = snapshot,
                })
            end
        end
        if not utility.stop(actor) then return false, "tactical_stop_rejected" end
        return true, commands.order
    end

    local tactical = commands.tacticalTarget
    local target = tactical and utility.loadedSquare(tactical)
    if commands.order == "move_to" and target then
        if not SC.Navigation or type(SC.Navigation.request) ~= "function" then
            return false, "navigation_unavailable"
        end
        local ok, status = SC.Navigation.request(actor, target, commandMoveMode(commands, player), {
            action = "ordered_move", snapshot = snapshot,
        })
        if ok and navigationArrived(actor, target, status) then
            local transitioned, transitionReason = switchToStay(actor, player)
            if not transitioned then return false, transitionReason end
        end
        return ok, status
    end
    if commands.order == "check_room" and target then
        local _, _, actorZ = utility.position(actor)
        local _, _, targetZ = utility.position(target)
        if math.floor(actorZ or 0) ~= math.floor(targetZ or 0) then return false, "room_check_floor_changed" end
        if not SC.Navigation or type(SC.Navigation.request) ~= "function" then
            return false, "navigation_unavailable"
        end
        local ok, status = SC.Navigation.request(actor, target, "sneak", {
            action = "check_room", snapshot = snapshot, orderedFloor = math.floor(targetZ or 0),
        })
        if ok and navigationArrived(actor, target, status) then
            if not state.roomCheckAt then
                if not utility.move(actor, "walk", {
                    action = "room_sweep",
                    targetSquare = target,
                    stableFacing = true,
                    orderedFloor = targetZ,
                }) then return false, "room_sweep_rejected" end
                state.roomCheckAt = utility.nowMs()
            elseif utility.nowMs() - state.roomCheckAt >= 1500 then
                local transitioned, transitionReason = switchToStay(actor, player)
                if not transitioned then return false, transitionReason end
                state.roomCheckAt = nil
            end
        end
        return ok, status
    end
    if commands.order == "interact" and commands.pendingInteraction then
        if not SC.Navigation then return false, "navigation_unavailable" end
        local pending = commands.pendingInteraction
        if utility.distance(actor, pending.object) <= 1.75 then
            if type(SC.Navigation.interact) ~= "function" then return false, "navigation_unavailable" end
            return SC.Navigation.interact(actor, pending.object, pending.action)
        end
        if type(SC.Navigation.request) ~= "function" then return false, "navigation_unavailable" end
        return SC.Navigation.request(actor, utility.squareOf(pending.object),
            commandMoveMode(commands, player), {
            action = "approach_interaction", snapshot = snapshot,
        })
    end
    return false, "no_tactical_target"
end

local function doRetreat(actor, snapshot, commands)
    if SC.Navigation and type(SC.Navigation.retreatTarget) == "function"
        and type(SC.Navigation.request) == "function" then
        local remembered, plan = SC.Navigation.retreatTarget(actor, snapshot)
        if remembered then
            return SC.Navigation.request(actor, remembered, "jog", {
                action = "ordered_retreat", snapshot = snapshot, urgent = true,
                escapeSpeedOverride = true, retreatPlan = plan,
            })
        end
    end
    local escape = snapshot.escapeSquares and snapshot.escapeSquares[1]
    if escape and SC.Navigation and type(SC.Navigation.request) == "function" then
        return SC.Navigation.request(actor, escape.square, "jog", {
            action = "ordered_retreat", snapshot = snapshot, urgent = true,
            escapeSpeedOverride = true,
        })
    end
    if escape then
        local accepted = U().move(actor, "jog", {
            action = "ordered_retreat", targetSquare = escape.square,
            enginePath = true, snapshot = snapshot,
            urgent = true, escapeSpeedOverride = true,
        })
        return accepted == true, accepted and "retreating" or "retreat_rejected"
    end
    local immediate = snapshot.immediateAttackers and snapshot.immediateAttackers[1] or nil
    local known = immediate or (snapshot.threats and snapshot.threats[1])
    local threat = type(known) == "table" and known.actor or known
    if threat == nil then return false, "retreat_direction_unavailable" end
    local accepted = U().move(actor, "jog", {
        action = "ordered_retreat", awayFrom = threat,
        urgent = true, escapeSpeedOverride = true,
    })
    return accepted == true, accepted and "retreating" or "retreat_rejected"
end

local function doSharedAlert(actor, candidate, state)
    local alert = candidate and candidate.detail or nil
    if type(alert) ~= "table" or type(alert.x) ~= "number" or type(alert.y) ~= "number" then
        return false, "invalid_shared_alert"
    end
    local accepted = U().move(actor, "walk", {
        action = "face_alert",
        targetPosition = { x = alert.x, y = alert.y, z = tonumber(alert.z) or 0 },
        stableFacing = true,
        sharedAlert = true,
    })
    if accepted ~= true then return false, "shared_alert_facing_rejected" end
    state.lastHandledAlertTime = tonumber(alert.time)
        or (U().nowMs() - (tonumber(alert.ageMs) or 0))
    return true, "shared_threat_alert"
end

local function callSubsystem(name, actor, callback)
    local safe, handled, reason = U().safeSubsystem(name, actor, callback)
    if not safe then return false, reason end
    return handled == true, reason
end

local function delegate(candidate, actor, player, rootRuntime, commands, snapshot, state)
    if candidate.kind == "mental_episode" or candidate.kind == "purposeful_idle"
        or candidate.kind == "joy_response" or candidate.kind == "social_participant" then
        if not SC.Autonomy or type(SC.Autonomy.update) ~= "function" then
            return false, "autonomy_unavailable"
        end
        return callSubsystem("autonomy", actor, function()
            return SC.Autonomy.update(actor, player, rootRuntime, candidate.detail)
        end)
    elseif candidate.kind == "medical" then
        if not SC.Medical or type(SC.Medical.update) ~= "function" then return false, "medical_unavailable" end
        return callSubsystem("medical", actor, function() return SC.Medical.update(actor, player, rootRuntime) end)
    elseif candidate.kind == "combat" then
        if not SC.Combat or type(SC.Combat.update) ~= "function" then return false, "combat_unavailable" end
        return callSubsystem("combat", actor, function() return SC.Combat.update(actor, player, rootRuntime) end)
    elseif candidate.kind == "encounter" then
        if not SC.Encounter or type(SC.Encounter.update) ~= "function" then return false, "encounter_unavailable" end
        return callSubsystem("encounter", actor, function() return SC.Encounter.update(actor, player, rootRuntime) end)
    elseif candidate.kind == "scavenge" then
        if not SC.Encounter or type(SC.Encounter.update) ~= "function" then return false, "encounter_unavailable" end
        return callSubsystem("encounter", actor, function() return SC.Encounter.update(actor, player, rootRuntime) end)
    elseif candidate.kind == "logistics" then
        if not SC.Logistics or type(SC.Logistics.update) ~= "function" then
            return false, "logistics_unavailable"
        end
        return callSubsystem("logistics", actor, function()
            return SC.Logistics.update(actor, player, rootRuntime)
        end)
    elseif candidate.kind == "downtime" then
        if not SC.Downtime or type(SC.Downtime.update) ~= "function" then return false, "downtime_unavailable" end
        return callSubsystem("downtime", actor, function() return SC.Downtime.update(actor, player, rootRuntime) end)
    elseif candidate.kind == "needs" then
        if not SC.Needs or type(SC.Needs.update) ~= "function" then return false, "needs_unavailable" end
        return callSubsystem("needs", actor, function() return SC.Needs.update(actor, player, rootRuntime) end)
    elseif candidate.kind == "base_work" then
        if not SC.BaseWork or type(SC.BaseWork.update) ~= "function" then
            return false, "base_work_unavailable"
        end
        return callSubsystem("base-work", actor, function()
            return SC.BaseWork.update(actor, player, rootRuntime)
        end)
    elseif candidate.kind == "infection_crisis" then
        if not SC.InfectionCrisis or type(SC.InfectionCrisis.updateActor) ~= "function" then
            return false, "infection_crisis_unavailable"
        end
        return callSubsystem("infection-crisis", actor, function()
            return SC.InfectionCrisis.updateActor(actor, player)
        end)
    elseif candidate.kind == "faction" then
        if not SC.FactionBehavior or type(SC.FactionBehavior.update) ~= "function" then
            return false, "faction_behavior_unavailable"
        end
        return callSubsystem("faction", actor, function()
            return SC.FactionBehavior.update(actor, player, rootRuntime, candidate.detail)
        end)
    elseif candidate.kind == "follow" then
        return callSubsystem("navigation", actor, function() return doFollow(actor, player, rootRuntime, commands, snapshot) end)
    elseif candidate.kind == "tactical" then
        return callSubsystem("navigation", actor, function() return doTactical(actor, player, rootRuntime, commands, snapshot, state) end)
    elseif candidate.kind == "retreat" then
        return callSubsystem("navigation", actor, function() return doRetreat(actor, snapshot, commands) end)
    elseif candidate.kind == "alert" then
        return callSubsystem("navigation", actor, function() return doSharedAlert(actor, candidate, state) end)
    elseif candidate.kind == "conversation" then
        if not SC.Positioning or type(SC.Positioning.updateConversation) ~= "function" then
            return false, "positioning_unavailable"
        end
        return callSubsystem("positioning", actor, function()
            return SC.Positioning.updateConversation(actor, snapshot)
        end)
    end
    return false, "unknown_decision"
end

local function candidateInterval(candidate)
    if candidate.kind == "combat" then
        return candidate.emergency and 100 or (U().config("combatDecisionIntervalMs") or 125)
    elseif candidate.kind == "medical" then
        return candidate.emergency and 100 or 250
    elseif candidate.kind == "retreat" then
        return 100
    elseif candidate.kind == "follow" or candidate.kind == "tactical"
        or candidate.kind == "conversation" then
        return U().config("followIntervalMs") or 167
    elseif candidate.kind == "alert" then
        return 167
    elseif candidate.kind == "mental_episode" or candidate.kind == "social_participant" then
        return 167
    elseif candidate.kind == "purposeful_idle" or candidate.kind == "joy_response" then
        return 250
    elseif candidate.kind == "needs" then
        return 250
    elseif candidate.kind == "base_work" then
        return 250
    elseif candidate.kind == "logistics" then
        return U().config("logisticsUpdateIntervalMs") or 750
    elseif candidate.kind == "infection_crisis" then
        return U().config("infectionCrisisIntervalMs") or 500
    elseif candidate.kind == "faction" then
        return 250
    elseif candidate.kind == "downtime" then
        return U().config("downtimeIntervalMs") or 1500
    elseif candidate.kind == "encounter" or candidate.kind == "scavenge" then
        return U().config("encounterIntervalMs") or 1000
    end
    return 250
end

local function candidateDue(actor, candidate, current)
    return U().isDue(actor, "decision_" .. candidate.kind, candidateInterval(candidate), current)
end

local function warnAboutThreat(actor, snapshot, state, current)
    local count = tonumber(snapshot.threatCount) or #(snapshot.threats or {})
    if count <= 0 then
        if state.threatClearAt == nil then state.threatClearAt = current end
        if current - state.threatClearAt >= 3000 then
            state.lastWarnedThreat = nil
            state.lastThreatBand = nil
            state.lastThreatBandRank = nil
        end
        return
    end
    state.threatClearAt = nil
    local strongest = type(snapshot.threats) == "table" and snapshot.threats[1] or nil
    local threat = strongest and strongest.actor or nil
    local dangerTopic, band, bandRank = "danger.zombie", "one", 1
    if SC.Dialogue and type(SC.Dialogue.threatTopic) == "function" then
        dangerTopic, band, bandRank = SC.Dialogue.threatTopic("danger", count)
    end
    local escalated = bandRank > (tonumber(state.lastThreatBandRank) or 0)
    if current < (state.nextThreatWarningAt or 0)
        and state.lastWarnedThreat == threat and state.lastThreatBand == band
        and not escalated then return end
    local immediate = tonumber(snapshot.immediateCount) or #(snapshot.immediateAttackers or {})
    state.lastWarnedThreat = threat
    state.lastThreatBand = band
    state.lastThreatBandRank = bandRank
    state.nextThreatWarningAt = current + (U().config("threatWarningCooldownMs") or 15000)
    -- Immediate contact is resolved in the same decision by Combat. Reserving
    -- the overhead line lets the more useful Engage or Fall back bark describe
    -- the action instead of first showing a generic warning and then replacing
    -- it. Distant contacts retain the existing hand signal or warning.
    if immediate > 0 then return end
    if current - lastGroupThreatWarningAt
        < (U().config("threatWarningGroupCooldownMs") or 3500)
        and not (escalated and band == "horde") then return end
    lastGroupThreatWarningAt = current
    local player = snapshot.player and snapshot.player.actor or nil
    local threatDistance = threat and U().distance(actor, threat) or 0
    local quietSignal = immediate == 0
        and threatDistance > (U().config("dangerSignalImmediateRadius") or 4)
        and player ~= nil
        and U().distance(actor, player) <= (U().config("dangerSignalMaxDistance") or 10)
        and U().canSee(player, actor)
        and (tonumber(snapshot.player and snapshot.player.danger) or 0) <= 0
    if quietSignal then
        local signalled = U().move(actor, "walk", {
            action = "hand_signal",
            emote = "freeze",
            target = threat,
            silent = true,
        })
        if signalled ~= true then
            quietSignal = false
        elseif SC.Dialogue and type(SC.Dialogue.say) == "function" then
            local signalTopic = SC.Dialogue.threatTopic("signal", count)
            SC.Dialogue.say(actor, signalTopic, nil, nil, {
                recentLimit = 4,
                salt = tostring(current) .. ":" .. tostring(count),
            })
        end
    end
    if not quietSignal then
        if SC.Dialogue and type(SC.Dialogue.say) == "function" then
            SC.Dialogue.say(actor, dangerTopic, nil, nil,
                { fallback = U().text("IGUI_SC_Threat_Warning", "Zombie! Watch out!") })
        else
            U().say(actor, U().text("IGUI_SC_Threat_Warning", "Zombie! Watch out!"))
        end
    end
    local x, y, z = U().position(threat or actor)
    if x and SC.Senses and type(SC.Senses.hear) == "function" then
        pcall(SC.Senses.hear, actor, x, y, z, 24, 18, "companion_alert")
    end
    local actorX, actorY, actorZ = U().position(actor)
    if not quietSignal and actorX and type(addSound) == "function" then
        local radius = U().config("threatWarningSoundRadius") or 10
        pcall(addSound, actor, actorX, actorY, actorZ, radius, 12)
    end
end

local function survivalNeedsImmediateControl(snapshot, assessment, needs, commands)
    snapshot = type(snapshot) == "table" and snapshot or {}
    local immediate = tonumber(snapshot.immediateCount)
        or #(snapshot.immediateAttackers or {})
    local playerDanger = type(snapshot.player) == "table"
        and tonumber(snapshot.player.danger) or 0
    return immediate > 0 or (tonumber(snapshot.pressure) or 0) >= 1.5
        or playerDanger > 0 or commands.order == "retreat"
        or assessment.downed == true or assessment.critical == true
        or (tonumber(assessment.bleedingCount) or 0) > 0
        or type(needs) == "table" and needs.emergency == true
end

local function pacingFollowMustMove(actor, player, commands)
    if commands.order ~= "follow" and commands.order ~= "regroup" then return false end
    if not player then return false end
    local moving, movingOk = U().call(player, "isMoving")
    local slack = U().config("actionPacingFollowSlack") or 2.5
    local limit = math.max(3, tonumber(commands.followDistance) or 3) + slack
    return U().distance(actor, player) > limit or (movingOk and moving == true
        and U().distance(actor, player) > math.max(2, limit - 1.5))
end

local function queueUrgentReassessment(actor, state, source)
    local service = SC.ActionSupervisor
    if type(service) ~= "table" or type(service.queueUrgent) ~= "function" then
        return false, "urgent_queue_unavailable"
    end
    return service.queueUrgent(actor, {
        owner = "decision", action = "survival_reassess",
        priority = service.Priority and service.Priority.SURVIVAL or 100,
        targetKey = "actor:" .. tostring(U().idOf(actor) or actor),
        reason = "survival_priority_waiting_for_owner",
        detail = { source = source },
        dispatch = function()
            -- The concrete survival action is deliberately selected on the
            -- next decision pass from fresh senses.  This callback is the
            -- observable hand-off from the former non-cancellable owner.
            state.current = "urgent"
            state.intent = "survival_reassess_released"
            state.urgentReleasedAt = U().nowMs()
            state.lastHandledAt = 0
            return true, "survival_reassess_dispatched", { source = source }
        end,
    })
end

local function holdOwnedActivityOrPacing(actor, player, snapshot, assessment,
        needs, commands, state, current)
    local native = SC.NativeActions
    local urgent = survivalNeedsImmediateControl(snapshot, assessment, needs, commands)
    if SC.ActionSupervisor and type(SC.ActionSupervisor.current) == "function" then
        local token = SC.ActionSupervisor.current(actor)
        if token then
            local serialChanged = token.owner == "downtime"
                and type(token.metadata) == "table"
                and tonumber(token.metadata.commandSerial) ~= (tonumber(commands.commandSerial) or 0)
            if urgent or serialChanged then
                local cancelled, cancelReason = SC.ActionSupervisor.cancel(actor,
                    urgent and "survival_priority" or "command_changed",
                    urgent and SC.ActionSupervisor.Priority.SURVIVAL
                        or SC.ActionSupervisor.Priority.PLAYER, false)
                if cancelled ~= true then
                    state.current = "activity"
                    if urgent then
                        local queued, queueReason = queueUrgentReassessment(actor,
                            state, tostring(token.owner) .. ":" .. tostring(token.action)
                                .. ":" .. tostring(token.phase))
                        state.intent = queued and (queueReason or "urgent_queued")
                            or (queueReason or cancelReason or "action_cancel_pending")
                    else
                        state.intent = cancelReason or "action_cancel_pending"
                    end
                    state.lastHandledAt = current
                    return true, state.intent
                end
            elseif token.phase == "committing" or token.phase == "verifying" then
                state.current = "activity"
                state.intent = tostring(token.owner) .. ":" .. tostring(token.action)
                state.lastHandledAt = current
                return true, state.intent
            end
        end
    end
    if type(native) ~= "table" then return false end
    if type(native.activityStatus) == "function" then
        local phase, owner, name = native.activityStatus(actor)
        if phase == "active" and not urgent then
            state.current = "activity"
            state.intent = tostring(owner) .. ":" .. tostring(name)
            state.lastHandledAt = current
            return true, state.intent
        elseif urgent and phase ~= nil and phase ~= "none" then
            local queued, queueReason = queueUrgentReassessment(actor, state,
                tostring(owner) .. ":" .. tostring(name) .. ":" .. tostring(phase))
            state.current = "activity"
            state.intent = queued and (queueReason or "urgent_queued")
                or (queueReason or "urgent_queue_rejected")
            state.lastHandledAt = current
            return true, state.intent
        end
    end
    if type(native.pacingStatus) ~= "function" then return false end
    local pacing, record = native.pacingStatus(actor, current)
    if not pacing then return false end
    local serialChanged = tonumber(record.commandSerial) ~= (tonumber(commands.commandSerial) or 0)
    local inVehicle = select(1, U().call(actor, "getVehicle")) ~= nil
    if urgent or serialChanged or inVehicle or pacingFollowMustMove(actor, player, commands) then
        if type(native.cancelPacing) == "function" then
            native.cancelPacing(actor, urgent and "survival_priority"
                or serialChanged and "new_order"
                or inVehicle and "vehicle_transition" or "follow_resumed")
        end
        return false
    end

    if record.stopped ~= true then
        local stopped = type(native.stopDirect) == "function" and native.stopDirect(actor, {
            preservePosture = commands.moveMode == "copy",
        })
            or U().stop(actor)
        record.stopped = stopped == true
    end
    -- Thinking does not make a companion forget the team's movement posture.
    -- Keep crouch in sync during the pause without starting a path request.
    if commands.moveMode == "copy" and SC.Positioning
        and type(SC.Positioning.syncCopiedPosture) == "function" then
        SC.Positioning.syncCopiedPosture(actor, player, "copy")
    end
    local looked = false
    if record.shouldLook == true and record.looked ~= true
        and current >= (tonumber(record.lookDueAt) or math.huge) then
        local x, y, z = U().position(actor)
        if x ~= nil then
            local directions = { { 1, 0 }, { 0, 1 }, { -1, 0 }, { 0, -1 } }
            local direction = directions[(tonumber(record.lookDirection) or 0) % 4 + 1]
            local accepted = U().move(actor, "walk", {
                action = "rear_scan",
                targetPosition = { x = x + direction[1] * 3,
                    y = y + direction[2] * 3, z = z or 0 },
                pacingObservation = true,
                humanAnimationOnly = true,
            })
            looked = accepted == true
        end
        record.looked = true
    end
    state.current = "pacing"
    state.intent = looked and "looking_around" or "thinking"
    state.lastHandledAt = current
    return true, state.intent
end

function Decision.update(actor, player, runtime)
    local utility = U()
    if not utility or not utility.isValidActor(actor) then return false, "invalid_actor" end
    local state, rootRuntime = stateFor(actor, runtime)
    local current = utility.nowMs()
    if SC.Needs and type(SC.Needs.updateRates) == "function" then
        utility.safeSubsystem("needs-rate", actor, function()
            return SC.Needs.updateRates(actor, rootRuntime, current)
        end)
    end

    local snapshot = rootRuntime.senses and rootRuntime.senses.current or rootRuntime.snapshot
    if utility.isDue(actor, "perception", utility.config("perceptionIntervalMs") or 500, current) then
        if SC.Senses and type(SC.Senses.snapshot) == "function" then
            local safe, value = utility.safeSubsystem("senses", actor, function()
                return SC.Senses.snapshot(actor, player, rootRuntime)
            end)
            if safe and type(value) == "table" then snapshot = value end
        end
    end
    snapshot = snapshot or {
        threats = {}, immediateAttackers = {}, escapeSquares = {}, allies = {},
        threatCount = 0, immediateCount = 0, pressure = 0,
        player = { danger = 0 },
    }
    rootRuntime.snapshot = snapshot

    if SC.Commands and type(SC.Commands.observeRelationship) == "function" then
        utility.safeSubsystem("relationship", actor, function()
            return SC.Commands.observeRelationship(actor, player, snapshot)
        end)
    end

    local commands = commandsFor(actor)
    if SC.Combat and type(SC.Combat.observe) == "function" then
        utility.safeSubsystem("combat-observe", actor, function()
            return SC.Combat.observe(actor)
        end)
    end
    if SC.Autonomy and type(SC.Autonomy.observe) == "function" then
        utility.safeSubsystem("autonomy-observe", actor, function()
            return SC.Autonomy.observe(actor, player, rootRuntime, snapshot, commands)
        end)
    end
    local assessment = medicalAssessment(actor)
    local needs
    if SC.Needs and type(SC.Needs.assess) == "function" then
        local ok, value = pcall(SC.Needs.assess, actor, rootRuntime)
        if ok and type(value) == "table" then needs = value end
    end
    if not assessment.alive or assessment.health <= 0 or assessment.terminalKnox then
        if not utility.stop(actor) then
            state.intent = "dead_stop_rejected"
            return false, state.intent
        end
        state.current, state.intent = "dead", "dead"
        return false, "dead"
    end

    local held, heldReason = holdOwnedActivityOrPacing(
        actor, player, snapshot, assessment, needs, commands, state, current)
    if held then return true, heldReason end

    local vehicleHandled, vehicleReason = enforceVehicleExitPolicy(actor, player, commands)
    if vehicleHandled ~= nil then
        state.current = "vehicle"
        state.intent = vehicleReason or "vehicle_policy"
        state.lastHandledAt = current
        return vehicleHandled == true, state.intent
    end

    warnAboutThreat(actor, snapshot, state, current)
    local candidates = evaluate(actor, player, snapshot, commands, assessment, needs, state, current)
    local selected = selectWithHysteresis(state, candidates, current)
    if not selected then
        if not utility.stop(actor) then
            state.intent = "idle_stop_rejected"
            return false, state.intent
        end
        state.current, state.intent = "idle", "stable_idle"
        return false, "no_candidate"
    end

    if not candidateDue(actor, selected, current) then return false, "deferred" end

    local previous = state.current
    if selected.kind ~= "mental_episode" and selected.kind ~= "social_participant"
        and (selected.kind == "combat" or selected.kind == "retreat"
            or selected.kind == "medical" and selected.emergency) then
        if SC.Autonomy and type(SC.Autonomy.interrupt) == "function" then
            pcall(SC.Autonomy.interrupt, actor, "survival_priority")
        end
    end
    if previous == "base_work" and selected.kind ~= "base_work"
        and (selected.kind == "combat" or selected.kind == "retreat" or selected.emergency)
        and SC.BaseWork and type(SC.BaseWork.cancel) == "function" then
        SC.BaseWork.cancel(actor, "danger_preempted_base_work")
    end
    if state.workAction and (selected.kind ~= "tactical" or commands.order ~= "work") then
        local cancelled, cancelReason = cancelWork(actor, state, "work_preempted")
        if not cancelled then
            state.intent = cancelReason
            return false, cancelReason
        end
    end
    -- Downtime owns a timed animation and sometimes a reserved object. Release
    -- both before another decision may translate the actor; otherwise the old
    -- kneeling pose can move with the new follow path.
    if previous == "downtime" and selected.kind ~= "downtime"
        and SC.Downtime and type(SC.Downtime.peek) == "function"
        and type(SC.Downtime.cancel) == "function" then
        local downtimeState = SC.Downtime.peek(actor)
        if downtimeState and (downtimeState.active or downtimeState.curtainTask) then
            local cancelled, cancelReason = SC.Downtime.cancel(actor, "decision_preempted")
            if cancelled ~= true then
                state.intent = cancelReason or "downtime_preempt_failed"
                return false, state.intent
            end
        end
    end
    if selected.kind ~= "needs" and (selected.kind == "combat"
        or selected.kind == "retreat" or selected.emergency) then
        if SC.Needs and type(SC.Needs.cancel) == "function" then
            local cancelled, cancelReason = SC.Needs.cancel(actor, "needs_preempted")
            if cancelled ~= true then
                state.intent = cancelReason or "needs_preempt_failed"
                return false, state.intent
            end
        end
    end
    local handled, reason = delegate(selected, actor, player, rootRuntime, commands, snapshot, state)
    if not handled then
        local selectedFailure = reason
        -- A preferred subsystem may have no concrete action (for example no
        -- bandage). Try lower utilities once, without recursive subsystem calls.
        for _, fallback in ipairs(candidates) do
            if fallback ~= selected and fallback.kind ~= selected.kind
                and candidateDue(actor, fallback, current) then
                local fallbackHandled, fallbackReason = delegate(
                    fallback,
                    actor,
                    player,
                    rootRuntime,
                    commands,
                    snapshot,
                    state
                )
                if fallbackHandled then
                    handled, reason, selected = true, fallbackReason, fallback
                    break
                end
            end
        end
        if not handled then reason = selectedFailure end
    end

    if handled then
        if previous ~= selected.kind then
            state.enteredAt = current
            state.minimumUntil = current + (utility.config("decisionMinStateMs") or 900)
        end
        state.current = selected.kind
        state.intent = reason or selected.kind
        state.score = selected.score
        state.lastHandledAt = current
        return true, state.intent
    end
    state.intent = reason or "not_handled"
    return false, state.intent
end

function Decision.peek(actor)
    return actor and states[actor] or nil
end

function Decision.cancelWork(actor, reason)
    if actor == nil then return false, "invalid_actor" end
    local state = states[actor]
    if not state then
        if SC.Encounter and type(SC.Encounter.cancelPlayerSupply) == "function" then
            SC.Encounter.cancelPlayerSupply(actor)
        end
        local runtime = U().peekActorState(actor)
        state = runtime and runtime.decision or nil
    end
    if not state then
        if SC.NativeActions and type(SC.NativeActions.cancelWork) == "function" then
            return SC.NativeActions.cancelWork(actor, reason)
        end
        return true, reason or "no_work_state"
    end
    return cancelWork(actor, state, reason)
end

function Decision.reset(actor)
    if actor then
        Decision.cancelWork(actor, "decision_reset")
        if SC.Needs and type(SC.Needs.reset) == "function" then SC.Needs.reset(actor) end
        if SC.Logistics and type(SC.Logistics.reset) == "function" then SC.Logistics.reset(actor) end
        if SC.NativeActions and type(SC.NativeActions.resetActivity) == "function" then
            SC.NativeActions.resetActivity(actor)
        end
        if SC.Locomotion and type(SC.Locomotion.reset) == "function" then
            SC.Locomotion.reset(actor)
        end
        states[actor] = nil
        local runtime = U().peekActorState(actor)
        if runtime then runtime.decision = nil end
    else
        for candidate, state in pairs(states) do
            cancelWork(candidate, state, "decision_reset")
        end
        states = setmetatable({}, { __mode = "k" })
        workReservations = {}
        lastGroupThreatWarningAt = -math.huge
    end
end

function Decision.resetAll()
    for actor, state in pairs(states) do cancelWork(actor, state, "world_reset") end
    local modules = { SC.Locomotion, SC.Senses, SC.ZombieTargeting, SC.Navigation, SC.Combat, SC.Medical, SC.Needs,
        SC.Logistics, SC.Encounter, SC.Downtime, SC.BaseWork, SC.Positioning, SC.Commands }
    modules[#modules + 1] = SC.FactionLife
    modules[#modules + 1] = SC.FactionContracts
    modules[#modules + 1] = SC.FactionBehavior
    for _, module in ipairs(modules) do
        if type(module) == "table" and type(module.reset) == "function" then
            local ok, result = pcall(module.reset, nil)
            if not ok or result == false then return false, "reset_failed" end
        end
    end
    states = setmetatable({}, { __mode = "k" })
    workReservations = {}
    if SC.NativeActions and type(SC.NativeActions.resetWork) == "function" then
        SC.NativeActions.resetWork(nil)
    end
    if SC.NativeActions and type(SC.NativeActions.resetActivity) == "function" then
        SC.NativeActions.resetActivity(nil)
    end
    if SC.NativeActions and type(SC.NativeActions.resetFinal) == "function" then
        SC.NativeActions.resetFinal(nil)
    end
    if SC.NativeActions and type(SC.NativeActions.resetNeeds) == "function" then
        SC.NativeActions.resetNeeds(nil)
    end
    if SC.NativeActions and type(SC.NativeActions.clearVisual) == "function" then
        SC.NativeActions.clearVisual(nil)
    end
    lastGroupThreatWarningAt = -math.huge
    if U() and type(U().clearActorState) == "function" then U().clearActorState(nil) end
    return true
end

return Decision
