-- SPDX-License-Identifier: MIT

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
if not SC.GameplayUtil and type(require) == "function" then pcall(require, "SCGameplayUtil") end

SC.Positioning = SC.Positioning or {}
local Positioning = SC.Positioning

-- Local X is right/left of the leader; local Y is distance behind the
-- leader's travel direction. Stable identity ordering prevents companions
-- swapping sides from one decision pulse to the next.
local formationOffsets = {
    { -1, 1 }, { 1, 1 }, { -2, 0 }, { 2, 0 },
    { -2, 2 }, { 2, 2 }, { -1, 3 }, { 1, 3 },
}

local states = setmetatable({}, { __mode = "k" })
local targetReservations = {}
local nextReservationSweepAt = 0

local function U()
    return SC.GameplayUtil
end

local function stateFor(actor)
    local state = states[actor]
    if state == nil then
        state = {}
        states[actor] = state
    end
    return state
end

local function normalized(x, y)
    x, y = tonumber(x), tonumber(y)
    if not x or not y then return nil, nil end
    local length = math.sqrt(x * x + y * y)
    if length < 0.001 then return nil, nil end
    return x / length, y / length
end

local function followerSlot(actor)
    local utility = U()
    local followers = {}
    for _, other in ipairs(utility.registryLiving(utility.config("maxCompanions") or 16)) do
        local commandState
        if SC.Commands and type(SC.Commands.peek) == "function" then
            local ok, value = pcall(SC.Commands.peek, other)
            if ok and type(value) == "table" then commandState = value end
        end
        if commandState and commandState.recruited
            and (commandState.order == "follow" or commandState.order == "regroup") then
            followers[#followers + 1] = { actor = other, id = utility.idOf(other) }
        end
    end
    table.sort(followers, function(a, b) return tostring(a.id) < tostring(b.id) end)
    for index, value in ipairs(followers) do
        if value.actor == actor then return index end
    end
    return (utility.stableHash(utility.idOf(actor)) % #formationOffsets) + 1
end

local function leaderHeading(actor, leader, current)
    local utility = U()
    local state = stateFor(actor)
    local x, y = utility.position(leader)
    if not x then return state.headingX or 0, state.headingY or -1 end

    if state.leaderX ~= nil then
        local velocityX, velocityY = normalized(x - state.leaderX, y - state.leaderY)
        if velocityX ~= nil then
            state.headingX, state.headingY = velocityX, velocityY
            state.headingAt = current
        end
    end
    state.leaderX, state.leaderY = x, y

    -- Turning to aim while standing still must not make the whole formation
    -- orbit the player. Native facing is only adopted before a travel heading
    -- exists or after a long stationary interval.
    if state.headingX == nil or current - (state.headingAt or 0) > 2500 then
        local forwardX, forwardXOk = utility.call(leader, "getForwardDirectionX")
        local forwardY, forwardYOk = utility.call(leader, "getForwardDirectionY")
        if forwardXOk and forwardYOk then
            local normalizedX, normalizedY = normalized(forwardX, forwardY)
            if normalizedX ~= nil then
                state.headingX, state.headingY = normalizedX, normalizedY
                state.headingAt = current
            end
        end
    end
    return state.headingX or 0, state.headingY or -1
end

local function reservationKey(square)
    return U().squareKey(square)
end

local function sweepReservations(current)
    if current < nextReservationSweepAt then return end
    for key, reservation in pairs(targetReservations) do
        if not reservation or reservation.expires <= current then targetReservations[key] = nil end
    end
    nextReservationSweepAt = current + 3000
end

local function canReserve(actor, square, current)
    local key = reservationKey(square)
    if not key then return false end
    local existing = targetReservations[key]
    if existing and existing.actor ~= actor and existing.expires > current then return false end
    targetReservations[key] = {
        actor = actor,
        expires = current + (U().config("positioningReservationMs") or 650),
    }
    local state = stateFor(actor)
    if state.reservationKey and state.reservationKey ~= key then
        local previous = targetReservations[state.reservationKey]
        if previous and previous.actor == actor then targetReservations[state.reservationKey] = nil end
    end
    state.reservationKey = key
    return true
end

local function allyClear(actor, square, snapshot, minimum)
    if not square then return false end
    local minimumSq = minimum * minimum
    if type(snapshot) == "table" then
        for _, ally in ipairs(snapshot.allies or {}) do
            if ally.actor and ally.actor ~= actor and U().sameFloor(ally.actor, square)
                and U().distanceSq(ally.actor, square) < minimumSq then return false end
        end
        local player = snapshot.player
        if type(player) == "table" and player.actor and player.actor ~= actor
            and U().sameFloor(player.actor, square)
            and U().distanceSq(player.actor, square) < minimumSq then return false end
    end
    return true
end

local candidateDeltas = {
    { 0, 0 }, { -1, 0 }, { 1, 0 }, { 0, 1 }, { 0, -1 },
    { -1, 1 }, { 1, 1 }, { -1, -1 }, { 1, -1 },
}

local function availableTarget(actor, x, y, z, snapshot, minimum, predicate)
    local utility = U()
    local current = utility.nowMs()
    sweepReservations(current)
    local start = (utility.stableHash(utility.idOf(actor)) % (#candidateDeltas - 1)) + 2
    local ordered = { candidateDeltas[1] }
    for offset = 0, #candidateDeltas - 2 do
        ordered[#ordered + 1] = candidateDeltas[((start - 2 + offset) % (#candidateDeltas - 1)) + 2]
    end
    for _, delta in ipairs(ordered) do
        local square = utility.gridSquare(x + delta[1], y + delta[2], z)
        if square and utility.isSquareFree(square) and allyClear(actor, square, snapshot, minimum)
            and (type(predicate) ~= "function" or predicate(square))
            and canReserve(actor, square, current) then return square end
    end
    return nil
end

function Positioning.formationTarget(actor, leader, commands, snapshot)
    local utility = U()
    local px, py, pz = utility.position(leader)
    if not px then return nil end
    local current = utility.nowMs()
    local forwardX, forwardY = leaderHeading(actor, leader, current)
    local rightX, rightY = -forwardY, forwardX
    local slot = followerSlot(actor)
    local localOffset = formationOffsets[((slot - 1) % #formationOffsets) + 1]
    local scale = commands.order == "regroup" and 0.75
        or math.max(0.75, (tonumber(commands.followDistance) or 3) / 3)
    local targetX = px + rightX * localOffset[1] * scale - forwardX * localOffset[2] * scale
    local targetY = py + rightY * localOffset[1] * scale - forwardY * localOffset[2] * scale
    local minimum = utility.config("formationSeparation") or 1.25
    local target = availableTarget(actor, targetX, targetY, pz, snapshot, minimum)
    if target then
        local state = stateFor(actor)
        state.slot = slot
        state.targetKey = reservationKey(target)
    end
    return target
end

function Positioning.shouldHold(actor, target)
    if not actor or not target then return false end
    local state = stateFor(actor)
    local distance = U().distance(actor, target)
    local enter = U().config("formationArrivalDistance") or 0.9
    local leave = math.max(enter + 0.25, U().config("formationReleaseDistance") or 1.55)
    if state.holdingFormation then
        if distance <= leave then return true end
        state.holdingFormation = false
        return false
    end
    if distance <= enter then
        state.holdingFormation = true
        state.heldAt = U().nowMs()
        return true
    end
    return false
end

local function booleanState(character, method, variable)
    if not character then return false end
    local value, ok = U().call(character, method)
    if ok then return value == true end
    if variable then
        value, ok = U().call(character, "getVariableBoolean", variable)
        if ok then return value == true end
    end
    return false
end

function Positioning.playerMoveMode(player)
    if not player then return "walk" end
    if booleanState(player, "isSneaking", "isSneaking")
        or booleanState(player, "isCrouching", "isCrouching") then
        return "sneak"
    end
    if booleanState(player, "isSprinting", "isSprinting")
        or booleanState(player, "isRunning", "isRunning") then
        return "jog"
    end
    return "walk"
end

function Positioning.resolveMoveMode(requested, player)
    if requested == "copy" then return Positioning.playerMoveMode(player) end
    if requested == "jog" or requested == "sneak" then return requested end
    return "walk"
end

function Positioning.syncCopiedPosture(actor, player, requested)
    if requested ~= "copy" then return nil, "posture_not_copied" end
    local sneaking = Positioning.playerMoveMode(player) == "sneak"
    return U().move(actor, "walk", {
        action = "copy_player_posture",
        sneaking = sneaking,
        humanAnimationOnly = true,
    })
end

function Positioning.followMode(requested, stress, leaderDistance, player)
    local mode = Positioning.resolveMoveMode(requested, player)
    local far = U().config("followFarDistance") or 18
    if leaderDistance >= far then return "jog", "catch_up" end
    if leaderDistance > 8 and mode == "sneak" then return "walk", "closing_distance" end
    if requested ~= "copy" and tonumber(stress) and tonumber(stress) >= 72
        and leaderDistance <= 8 then
        return "sneak", "guarded"
    end
    return mode, tonumber(stress) and tonumber(stress) >= 42 and "alert" or "calm"
end

function Positioning.updateHoldAwareness(actor, leader, snapshot)
    local utility = U()
    if not utility.isValidActor(actor) or not utility.isValidActor(leader) then
        return false, "invalid_awareness_actor"
    end
    if type(snapshot) == "table" and ((tonumber(snapshot.threatCount) or 0) > 0
        or (tonumber(snapshot.immediateCount) or 0) > 0) then return nil, "danger_present" end

    local state = stateFor(actor)
    local current = utility.nowMs()
    local forwardX, forwardY = leaderHeading(actor, leader, current)
    local actorX, actorY, actorZ = utility.position(actor)
    if not actorX then return false, "awareness_position_unavailable" end

    if state.restoreFormationFacingAt then
        if current < state.restoreFormationFacingAt then return true, "rear_scan_observing" end
        local accepted, reason = utility.move(actor, "walk", {
            action = "face_formation",
            targetPosition = {
                x = actorX + forwardX * 2,
                y = actorY + forwardY * 2,
                z = actorZ,
            },
            stableFacing = true,
            awarenessMovement = true,
        })
        if accepted then state.restoreFormationFacingAt = nil end
        return accepted == true, reason or "formation_facing_restore_rejected"
    end

    local interval = utility.config("rearScanIntervalMs") or 8500
    if not utility.isDue(actor, "formation_rear_scan", interval, current) then
        return nil, "rear_scan_not_due"
    end
    if not utility.stop(actor) then return false, "rear_scan_stop_rejected" end
    local accepted, reason = utility.move(actor, "walk", {
        action = "rear_scan",
        targetPosition = {
            x = actorX - forwardX * 2,
            y = actorY - forwardY * 2,
            z = actorZ,
        },
        stableFacing = true,
        awarenessMovement = true,
    })
    if accepted then
        state.restoreFormationFacingAt = current + (utility.config("rearScanHoldMs") or 550)
    end
    return accepted == true, reason or "rear_scan_rejected"
end

local function conversationTarget(actor, partner, snapshot)
    local utility = U()
    local px, py, pz = utility.position(partner)
    local ax, ay = utility.position(actor)
    if not px or not ax then return nil end
    local awayX, awayY = normalized(ax - px, ay - py)
    if awayX == nil then
        local hash = utility.stableHash(utility.idOf(actor)) % 4
        local directions = { { 1, 0 }, { 0, 1 }, { -1, 0 }, { 0, -1 } }
        awayX, awayY = directions[hash + 1][1], directions[hash + 1][2]
    end
    local radius = utility.config("conversationPreferredDistance") or 1.65
    local minimum = utility.config("conversationMinimumDistance") or 1.2
    local maximum = utility.config("conversationMaximumDistance") or 2.8
    return availableTarget(actor, px + awayX * radius, py + awayY * radius, pz,
        snapshot, utility.config("conversationCompanionSpacing") or 1.15, function(square)
            local distance = utility.distance(square, partner)
            return distance >= minimum and distance <= maximum
        end)
end

function Positioning.beginConversation(actor, partner, options)
    local utility = U()
    if not utility.isValidActor(actor) or not utility.isValidActor(partner) then
        return false, "invalid_conversation_actor"
    end
    local state = stateFor(actor)
    local current = utility.nowMs()
    state.conversation = {
        partner = partner,
        action = type(options) == "table" and options.action or nil,
        emote = type(options) == "table" and options.emote or nil,
        stress = type(options) == "table" and tonumber(options.stress) or 0,
        expires = current + (utility.config("conversationHoldMs") or 5000),
        posed = false,
    }
    return true, "conversation_staged"
end

function Positioning.activeConversation(actor)
    local state = actor and states[actor] or nil
    local conversation = state and state.conversation or nil
    if not conversation then return nil end
    if U().nowMs() >= (conversation.expires or 0)
        or not U().isValidActor(conversation.partner) then
        state.conversation = nil
        return nil
    end
    return conversation
end

function Positioning.updateConversation(actor, snapshot)
    local utility = U()
    local conversation = Positioning.activeConversation(actor)
    if not conversation then return false, "no_conversation" end
    if type(snapshot) == "table" and ((tonumber(snapshot.threatCount) or 0) > 0
        or (tonumber(snapshot.immediateCount) or 0) > 0) then
        stateFor(actor).conversation = nil
        return false, "conversation_interrupted_by_danger"
    end

    local partner = conversation.partner
    local minimum = utility.config("conversationMinimumDistance") or 1.2
    local maximum = utility.config("conversationMaximumDistance") or 2.8
    local partnerDistance = utility.distance(actor, partner)
    if not utility.sameFloor(actor, partner) or partnerDistance > maximum
        or partnerDistance < minimum then
        local target = conversationTarget(actor, partner, snapshot)
        if not target then return false, "conversation_position_unavailable" end
        if not SC.Navigation or type(SC.Navigation.request) ~= "function" then
            return false, "conversation_navigation_unavailable"
        end
        return SC.Navigation.request(actor, target, "walk", {
            action = "conversation_approach",
            targetSquare = target,
            snapshot = snapshot,
            socialMovement = true,
        })
    end

    if not utility.stop(actor) then return false, "conversation_stop_rejected" end
    local action = conversation.posed and "face_conversation" or "conversation_pose"
    local emote = conversation.emote
    if not conversation.posed and (type(emote) ~= "string" or emote == "") then
        if conversation.stress >= 72 then emote = "undecided"
        elseif conversation.stress >= 42 then emote = "shrug"
        else emote = "yes" end
    end
    local accepted, reason = utility.move(actor, "walk", {
        action = action,
        targetPosition = partner,
        emote = not conversation.posed and emote or nil,
        socialMovement = true,
        stableFacing = true,
        stressPosture = conversation.stress >= 72 and "shaken"
            or conversation.stress >= 42 and "uneasy" or "calm",
    })
    if accepted then conversation.posed = true end
    return accepted == true, reason or (accepted and "conversation_facing" or "conversation_pose_rejected")
end

function Positioning.debug(actor)
    local state = actor and states[actor] or nil
    if not state then return nil end
    return {
        slot = state.slot,
        targetKey = state.targetKey,
        holdingFormation = state.holdingFormation == true,
        conversation = state.conversation and {
            action = state.conversation.action,
            posed = state.conversation.posed == true,
            expires = state.conversation.expires,
        } or nil,
    }
end

function Positioning.reset(actor)
    if actor then
        local state = states[actor]
        if state and state.reservationKey then
            local reservation = targetReservations[state.reservationKey]
            if reservation and reservation.actor == actor then targetReservations[state.reservationKey] = nil end
        end
        states[actor] = nil
    else
        states = setmetatable({}, { __mode = "k" })
        targetReservations = {}
        nextReservationSweepAt = 0
    end
end

return Positioning
