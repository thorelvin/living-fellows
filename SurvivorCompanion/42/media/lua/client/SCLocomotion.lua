-- SPDX-License-Identifier: MIT

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
if not SC.GameplayUtil and type(require) == "function" then pcall(require, "SCGameplayUtil") end

SC.Locomotion = SC.Locomotion or {}
local Locomotion = SC.Locomotion
local states = setmetatable({}, { __mode = "k" })
local histories = setmetatable({}, { __mode = "k" })

local interactionActions = {
    attack_melee = true, attack_firearm = true, shove = true, stomp = true,
    reload = true, unjam = true, equip = true, equip_weapon = true,
    bandage = true, treat = true, kneel_treat = true,
    rip_clothing = true, tear_clothing = true, rip_clothing_for_bandage = true,
    replace_bandage = true,
    loot = true, loot_container = true, scavenge = true,
    pack_item = true, deposit_item = true,
    eat_food = true, drink_item = true, drink_source = true,
    read = true, repair = true, craft_supply = true, wash = true,
    wear_clothing = true, wash_self = true, wash_equipment = true,
    stress_bottle_smash = true, stress_furniture_hit = true,
    ambient_eat = true, ambient_drink = true,
    sit = true, sit_ground = true, stand_ground = true,
    barricade = true, remove_barricade = true, dismantle = true,
    open_door = true, close_door = true, open_window = true, close_window = true,
    smash_window = true, remove_glass = true, climb_window = true,
    climb_window_emergency = true, open_curtain = true, close_curtain = true,
    board_vehicle = true, exit_vehicle = true,
    downed = true, recover_from_downed = true,
}

local turnActions = {
    room_sweep = true, face_alert = true, rear_scan = true,
    face_formation = true, face_conversation = true, conversation_pose = true,
    ready_weapon = true, lower_weapon = true, hand_signal = true,
    copy_player_posture = true,
}

local escapeActions = {
    combat_retreat = true,
    ordered_retreat = true,
    corner_escape = true,
    climb_window_emergency = true,
}

local function utility()
    return SC.GameplayUtil
end

local function nowMs()
    local u = utility()
    return u and type(u.nowMs) == "function" and u.nowMs() or 0
end

local function actorId(actor)
    local u = utility()
    return tostring(u and type(u.idOf) == "function" and u.idOf(actor) or "unknown")
end

local function actorName(actor)
    local u = utility()
    if u and type(u.call) == "function" then
        local display, ok = u.call(actor, "getDisplayName")
        if ok and display ~= nil and tostring(display) ~= "" then return tostring(display) end
        local descriptor = select(1, u.call(actor, "getDescriptor"))
        if descriptor then
            local forename = select(1, u.call(descriptor, "getForename"))
            local surname = select(1, u.call(descriptor, "getSurname"))
            local full = tostring(forename or "") .. " " .. tostring(surname or "")
            full = string.gsub(full, "^%s+", "")
            full = string.gsub(full, "%s+$", "")
            if full ~= "" then return full end
        end
    end
    return actorId(actor)
end

local function squareText(value)
    local u = utility()
    if value == nil or not u or type(u.position) ~= "function" then return nil end
    local x, y, z = u.position(value)
    if x == nil then return nil end
    return tostring(math.floor(x)) .. "," .. tostring(math.floor(y))
        .. "," .. tostring(math.floor(z or 0))
end

local function clean(value, maximum)
    if value == nil then return nil end
    local text = string.gsub(tostring(value), "[%c\r\n]+", " ")
    maximum = maximum or 96
    if #text > maximum then text = string.sub(text, 1, maximum - 3) .. "..." end
    return text
end

local function recordingEnabled()
    return SC.Config and type(SC.Config.get) == "function"
        and SC.Config.get("movementRecorderEnabled") == true
end

local function classify(mode, intent)
    intent = type(intent) == "table" and intent or {}
    local action = tostring(intent.action or "move")
    if interactionActions[action] or intent.interaction == true then return "interact", action end
    if turnActions[action] then return "turn", action end
    if action == "backstep" or action == "lateral_kite" or intent.tacticalStrafe == true
        or intent.keepFacing == true then return "strafe", action end
    if string.find(action, "recovery", 1, true) or string.find(action, "yield", 1, true)
        or string.find(action, "unstuck", 1, true) then return "recover", action end
    if mode == "run" or mode == "jog" or mode == "sprint" then return "run", action end
    return "walk", action
end

local function urgent(action, intent)
    if type(intent) == "table" and (intent.urgent == true or intent.emergency == true
        or intent.survivalCritical == true) then return true end
    action = tostring(action or "")
    return string.find(action, "retreat", 1, true) ~= nil
        or string.find(action, "combat", 1, true) ~= nil
        or string.find(action, "rescue", 1, true) ~= nil
        or action == "attack_melee" or action == "attack_firearm"
        or action == "shove" or action == "stomp"
        or action == "corner_escape" or action == "climb_window_emergency"
        or action == "downed" or action == "recover_from_downed"
        or action == "exit_vehicle"
end

local function escapeAction(action, intent)
    intent = type(intent) == "table" and intent or {}
    if intent.escapeSpeedOverride == true or intent.seekOpenEscape == true then return true end
    action = tostring(action or intent.action or "")
    return escapeActions[action] == true
        or string.find(action, "retreat", 1, true) ~= nil
        or string.find(action, "escape", 1, true) ~= nil
end

local function escapeConstraint(intent)
    intent = type(intent) == "table" and intent or {}
    local action = tostring(intent.action or "")
    if action == "climb_window_emergency" or string.find(action, "window", 1, true) then
        return "window_transition"
    end
    if intent.emergencyVegetation == true or intent.vegetationClearance == true then
        return "vegetation_clearance"
    end
    local affordance = tostring(intent.nativeAffordance or "")
    if affordance == "stairs" or intent.tacticalStair == true then return "stairs" end
    if affordance == "door" then return "doorway" end
    if affordance == "fence" then return "fence_transition" end
    if intent.tacticalRetreat == true then return "controlled_retreat_footwork" end
    return nil
end

-- Movement policy is advisory during survival escape.  Resolve the final speed
-- at the Actor boundary so Copy player, Sneak, weapon-ready corner handling and
-- formation logic cannot silently slow a retreat after Combat chose it. Native
-- transitions that require precise foot placement keep ordinary walking speed.
function Locomotion.resolveMovementMode(mode, intent)
    intent = type(intent) == "table" and intent or {}
    if not escapeAction(intent.action, intent) then return mode, nil end
    local constraint = escapeConstraint(intent)
    if constraint ~= nil then return "walk", "escape_constrained:" .. constraint end
    return "run", "escape_speed_override"
end

function Locomotion.isEscapeIntent(intent)
    return type(intent) == "table" and escapeAction(intent.action, intent) or false
end

local function stateFor(actor)
    local state = states[actor]
    if not state then
        state = {
            phase = "idle", owner = "none", action = "none",
            since = nowMs(), lastAccepted = nil, lastReason = "created",
        }
        states[actor] = state
    end
    return state
end

local function prune(history, current)
    local window = tonumber(SC.Config and SC.Config.get("movementRecorderWindowMs")) or 30000
    local write = 1
    for index = 1, #history do
        local entry = history[index]
        if current - (tonumber(entry.at) or 0) <= window then
            history[write] = entry
            write = write + 1
        end
    end
    for index = #history, write, -1 do history[index] = nil end
    local limit = tonumber(SC.Config and SC.Config.get("movementRecorderMaxEvents")) or 180
    while #history > limit do table.remove(history, 1) end
end

local function append(actor, kind, fields)
    if actor == nil or not recordingEnabled() then return end
    local current = nowMs()
    local history = histories[actor]
    if not history then history = {} histories[actor] = history end
    fields = type(fields) == "table" and fields or {}
    local entry = {
        at = current,
        kind = clean(kind, 32) or "event",
        phase = clean(fields.phase, 24),
        owner = clean(fields.owner, 32),
        action = clean(fields.action, 48),
        status = clean(fields.status, 96),
        target = squareText(fields.targetSquare or fields.target),
        next = squareText(fields.nextSquare),
        blocker = clean(fields.blocker, 48),
        recovery = clean(fields.recovery, 64),
        detail = clean(fields.detail, 128),
        repeats = 1,
    }
    local signature = table.concat({ entry.kind or "", entry.phase or "", entry.owner or "",
        entry.action or "", entry.status or "", entry.target or "", entry.next or "",
        entry.blocker or "", entry.recovery or "", entry.detail or "" }, "|")
    local previous = history[#history]
    if previous and previous.signature == signature and current - previous.at <= 300 then
        previous.at = current
        previous.repeats = (tonumber(previous.repeats) or 1) + 1
    else
        entry.signature = signature
        history[#history + 1] = entry
    end
    prune(history, current)
end

local function transition(actor, phase, owner, action, reason, intent)
    local state = stateFor(actor)
    local changed = state.phase ~= phase or state.owner ~= owner or state.action ~= action
    if changed then
        state.phase, state.owner, state.action = phase, owner, action
        state.since = nowMs()
        append(actor, "transition", {
            phase = phase, owner = owner, action = action, status = reason,
            targetSquare = intent and intent.targetSquare,
            nextSquare = intent and intent.nextSquare,
        })
    end
    state.lastReason = reason or state.lastReason
    if type(intent) == "table" then
        state.target = squareText(intent.targetSquare or intent.target)
        state.next = squareText(intent.nextSquare)
    elseif phase == "idle" then
        state.target, state.next = nil, nil
    end
    return state
end

local function stopForOwnership(actor)
    if SC.NativeActions and type(SC.NativeActions.stopDirect) == "function" then
        pcall(SC.NativeActions.stopDirect, actor, { preservePosture = true })
    end
end

local function copyIntent(intent)
    local result = {}
    for key, value in pairs(type(intent) == "table" and intent or {}) do
        result[key] = value
    end
    -- A queued intent is dispatched after the prior owner has terminated.  A
    -- token captured from that owner must never authorize the later movement.
    result.supervisorToken = nil
    result.urgentQueued = true
    return result
end

local function queueUrgentMovement(actor, mode, action, intent)
    local service = SC.ActionSupervisor
    if type(service) ~= "table" or type(service.queueUrgent) ~= "function" then
        return false, "urgent_queue_unavailable"
    end
    local queuedIntent = copyIntent(intent)
    return service.queueUrgent(actor, {
        owner = "locomotion", action = action,
        priority = service.Priority and service.Priority.SURVIVAL or 100,
        targetKey = squareText(intent.targetSquare or intent.target or intent.nextSquare),
        targetLabel = squareText(intent.targetSquare or intent.target),
        reason = "urgent_locomotion_waiting_for_owner",
        detail = { mode = mode, action = action },
        dispatch = function()
            if type(SC.Actor) ~= "table" or type(SC.Actor.setMovement) ~= "function" then
                return false, "actor_movement_unavailable"
            end
            return SC.Actor.setMovement(actor, mode, queuedIntent)
        end,
    })
end

function Locomotion.authorize(actor, mode, intent)
    if actor == nil or type(intent) ~= "table" then return false, "invalid_locomotion_request" end
    local phase, action = classify(mode, intent)
    if SC.ActionSupervisor and type(SC.ActionSupervisor.movementPermission) == "function" then
        local permitted, supervisorReason, supervisorState =
            SC.ActionSupervisor.movementPermission(actor, action, intent)
        if permitted ~= true then
            local urgentIntent = urgent(action, intent)
            if urgentIntent and supervisorState
                and supervisorState.phase ~= "committing"
                and supervisorState.phase ~= "verifying"
                and type(SC.ActionSupervisor.cancel) == "function" then
                local cancelled = SC.ActionSupervisor.cancel(actor,
                    "urgent_locomotion_preemption", nil, false)
                if cancelled == true then permitted = true end
            end
            if permitted == true then
                supervisorReason, supervisorState = nil, nil
            else
                stopForOwnership(actor)
                local status = supervisorReason or "action_owned"
                if urgentIntent then
                    local queued, queueReason = queueUrgentMovement(actor, mode, action, intent)
                    status = queued and (queueReason or "urgent_queued")
                        or (queueReason or "urgent_queue_rejected")
                end
                transition(actor, "interact", "supervisor",
                    supervisorState and supervisorState.action or "activity",
                    status, intent)
                append(actor, "rejected", {
                    phase = phase, owner = "locomotion", action = action,
                    status = status,
                    targetSquare = intent.targetSquare, nextSquare = intent.nextSquare,
                })
                return false, "locomotion_" .. tostring(status)
            end
        end
    end
    local activityPhase, activityOwner, activityName, activityAt
    if SC.NativeActions and type(SC.NativeActions.activityStatus) == "function" then
        activityPhase, activityOwner, activityName, activityAt = SC.NativeActions.activityStatus(actor)
    end
    local protectedActivity = activityPhase == "active" or activityPhase == "result_pending"
    if protectedActivity and activityPhase == "result_pending" and activityOwner == "visual" then
        local grace = tonumber(SC.Config and SC.Config.get("visualEffectClaimMs")) or 2000
        if nowMs() - (tonumber(activityAt) or nowMs()) >= grace then protectedActivity = false end
    end
    if protectedActivity and activityName ~= action then
        stopForOwnership(actor)
        local status = "protected_activity:" .. tostring(activityOwner)
            .. ":" .. tostring(activityName)
        local response = "locomotion_protected_activity:" .. tostring(activityPhase)
            .. ":" .. tostring(activityOwner) .. ":" .. tostring(activityName)
        if urgent(action, intent) then
            local queued, queueReason = queueUrgentMovement(actor, mode, action, intent)
            status = queued and (queueReason or "urgent_queued")
                or (queueReason or status)
            response = "locomotion_" .. tostring(status)
        end
        transition(actor, "interact", tostring(activityOwner or "native"),
            tostring(activityName or "activity"), status, intent)
        append(actor, "rejected", {
            phase = phase, owner = "locomotion", action = action,
            status = status,
            targetSquare = intent.targetSquare, nextSquare = intent.nextSquare,
        })
        return false, response
    end
    if (phase == "walk" or phase == "run" or phase == "strafe" or phase == "recover")
        then
        local u = utility()
        local blocker = u and type(u.movementStateBlocker) == "function"
            and u.movementStateBlocker(actor) or nil
        if blocker ~= nil then
            stopForOwnership(actor)
            transition(actor, "interact", "native", tostring(blocker),
                "protected_actor_state", intent)
            append(actor, "rejected", {
                phase = phase, owner = "locomotion", action = action,
                status = "actor_state_busy", blocker = blocker,
                targetSquare = intent.targetSquare, nextSquare = intent.nextSquare,
            })
            return false, "locomotion_actor_state_busy:" .. tostring(blocker)
        end
    end
    transition(actor, phase, phase == "interact" and action or "locomotion",
        action, "authorized", intent)
    local state = stateFor(actor)
    state.requestedMode = intent.requestedMovementMode or mode
    state.effectiveMode = mode
    state.speedOverride = intent.movementSpeedOverride
    return true, phase
end

function Locomotion.noteResult(actor, accepted, reason, mode, intent)
    if actor == nil then return end
    local state = stateFor(actor)
    state.lastAccepted = accepted == true
    state.lastReason = clean(reason, 128) or (accepted and "accepted" or "rejected")
    state.lastResultAt = nowMs()
    append(actor, accepted and "accepted" or "rejected", {
        phase = state.phase, owner = state.owner,
        action = type(intent) == "table" and intent.action or state.action,
        status = state.lastReason,
        detail = type(intent) == "table" and intent.movementSpeedOverride or nil,
        targetSquare = type(intent) == "table" and intent.targetSquare or nil,
        nextSquare = type(intent) == "table" and intent.nextSquare or nil,
    })
end

function Locomotion.noteStop(actor, reason)
    if actor == nil then return end
    local phase = SC.NativeActions and type(SC.NativeActions.activityStatus) == "function"
        and SC.NativeActions.activityStatus(actor) or "none"
    if phase == "none" then transition(actor, "idle", "none", "none", reason or "stopped")
    else append(actor, "stop_deferred", { status = reason, detail = tostring(phase) }) end
end

function Locomotion.recordNavigation(actor, kind, fields)
    fields = type(fields) == "table" and fields or {}
    local state = stateFor(actor)
    fields.phase = fields.phase or state.phase
    fields.owner = fields.owner or "navigation"
    fields.action = fields.action or state.action
    append(actor, "nav_" .. tostring(kind or "event"), fields)
end

function Locomotion.peek(actor)
    return actor and states[actor] or nil
end

function Locomotion.snapshot(actor)
    if actor == nil then return nil end
    local current = nowMs()
    local history = histories[actor] or {}
    prune(history, current)
    local state = stateFor(actor)
    local navigation = SC.Navigation and type(SC.Navigation.peek) == "function"
        and SC.Navigation.peek(actor) or nil
    local telemetry = SC.NativeActions and type(SC.NativeActions.pathTelemetry) == "function"
        and SC.NativeActions.pathTelemetry(actor) or { available = false }
    local activityPhase, activityOwner, activityName = "none", "none", "none"
    if SC.NativeActions and type(SC.NativeActions.activityStatus) == "function" then
        activityPhase, activityOwner, activityName = SC.NativeActions.activityStatus(actor)
    end
    return {
        id = actorId(actor), name = actorName(actor), now = current,
        phase = state.phase, owner = state.owner, action = state.action,
        since = state.since, lastAccepted = state.lastAccepted,
        lastReason = state.lastReason, target = state.target, next = state.next,
        requestedMode = state.requestedMode, effectiveMode = state.effectiveMode,
        speedOverride = state.speedOverride,
        activityPhase = activityPhase, activityOwner = activityOwner, activityName = activityName,
        navigation = navigation, telemetry = telemetry, events = history,
    }
end

local function boolText(value)
    if value == nil then return "unknown" end
    return value == true and "yes" or "no"
end

function Locomotion.report(actor)
    local snapshot = Locomotion.snapshot(actor)
    if not snapshot then return "Living Fellows movement recorder\nNo companion selected." end
    local nav, telemetry = snapshot.navigation or {}, snapshot.telemetry or {}
    local blocker = nav.lastBlocker or {}
    local lines = {
        "Living Fellows movement recorder",
        "Companion: " .. tostring(snapshot.name) .. " [" .. tostring(snapshot.id) .. "]",
        "Window: last " .. tostring((tonumber(SC.Config and SC.Config.get("movementRecorderWindowMs")) or 30000) / 1000) .. " seconds",
        "Locomotion: " .. tostring(snapshot.phase) .. " | owner " .. tostring(snapshot.owner)
            .. " | action " .. tostring(snapshot.action),
        "Last result: " .. boolText(snapshot.lastAccepted) .. " | " .. tostring(snapshot.lastReason or "none"),
        "Speed: requested " .. tostring(snapshot.requestedMode or "unknown")
            .. " | effective " .. tostring(snapshot.effectiveMode or "unknown")
            .. " | override " .. tostring(snapshot.speedOverride or "none"),
        "Target / next: " .. tostring(snapshot.target or "none") .. " / " .. tostring(snapshot.next or "none"),
        "Native activity: " .. tostring(snapshot.activityPhase) .. " | "
            .. tostring(snapshot.activityOwner) .. " | " .. tostring(snapshot.activityName),
        "Native path: available " .. boolText(telemetry.available) .. " | active "
            .. boolText(telemetry.active) .. " | pending " .. boolText(telemetry.pending)
            .. " | turning " .. boolText(telemetry.turningToObstacle),
        "Route: index " .. tostring(nav.pathIndex or 0) .. " / "
            .. tostring(type(nav.path) == "table" and #nav.path or 0)
            .. " | choke keys " .. tostring(type(nav.chokeReservationKeys) == "table"
                and #nav.chokeReservationKeys or 0)
            .. " | choke queue " .. tostring(nav.chokeQueueOwner and actorId(nav.chokeQueueOwner) or "none")
            .. " | step queue " .. tostring(nav.stepQueueOwner and actorId(nav.stepQueueOwner) or "none"),
        "Blocker: " .. tostring(blocker.type or "none") .. " | square "
            .. tostring(blocker.squareKey or "none") .. " | recovery "
            .. tostring(blocker.recoveryResult or "none"),
        "Events:",
    }
    for _, entry in ipairs(snapshot.events or {}) do
        local age = math.max(0, snapshot.now - (tonumber(entry.at) or snapshot.now)) / 1000
        local detail = entry.status or entry.detail or "-"
        if entry.blocker then detail = detail .. " | blocker " .. tostring(entry.blocker) end
        if entry.recovery then detail = detail .. " | recovery " .. tostring(entry.recovery) end
        lines[#lines + 1] = string.format("  -%.1fs %s | %s | %s | %s | target %s | next %s%s",
            age, tostring(entry.kind or "event"), tostring(entry.phase or "-"),
            tostring(entry.action or "-"), tostring(detail),
            tostring(entry.target or "-"), tostring(entry.next or "-"),
            (tonumber(entry.repeats) or 1) > 1 and " | x" .. tostring(entry.repeats) or "")
    end
    return table.concat(lines, "\n")
end

function Locomotion.reset(actor)
    if actor ~= nil then
        states[actor], histories[actor] = nil, nil
    else
        states = setmetatable({}, { __mode = "k" })
        histories = setmetatable({}, { __mode = "k" })
    end
    return true
end

return Locomotion
