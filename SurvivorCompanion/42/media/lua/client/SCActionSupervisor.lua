-- SPDX-License-Identifier: MIT

local SC = SurvivorCompanion
SC.ActionSupervisor = SC.ActionSupervisor or {}

local Supervisor = SC.ActionSupervisor

Supervisor.Priority = Supervisor.Priority or {
    DOWNTIME = 50,
    WORK = 150,
    NEEDS = 250,
    TRAVEL = 300,
    PLAYER = 400,
    COMBAT_RESCUE = 500,
    SURVIVAL = 600,
    EXTERNAL = 1000,
}

local terminalPhases = { completed = true, cancelled = true, failed = true }
local validPhases = {
    selected = true, reserved = true, approaching = true, settling = true,
    animating = true, committing = true, verifying = true,
    cooling_down = true, waiting = true, recovering = true,
    completed = true, cancelled = true, failed = true,
}
local movementPhases = { selected = true, reserved = true, approaching = true, recovering = true }
local activeByActor = setmetatable({}, { __mode = "k" })
local historyByActor = setmetatable({}, { __mode = "k" })
local retryByActor = setmetatable({}, { __mode = "k" })
local reservationOwners = setmetatable({}, { __mode = "k" })
local sequence = 0

local function nowMs()
    if type(getTimestampMs) == "function" then
        local ok, value = pcall(getTimestampMs)
        if ok and tonumber(value) ~= nil then return tonumber(value) end
    end
    return math.floor(os.clock() * 1000)
end

local function config(key, fallback)
    if SC.Config and type(SC.Config.get) == "function" then
        local value = SC.Config.get(key)
        if value ~= nil then return value end
    end
    return fallback
end

local function invoke(value, methodName, ...)
    if value == nil then return nil, false end
    local ok, method = pcall(function() return value[methodName] end)
    if not ok or type(method) ~= "function" then return nil, false end
    local results = { pcall(method, value, ...) }
    if not results[1] then return nil, false end
    return results[2], true
end

local function actorId(actor)
    if SC.Registry and type(SC.Registry.idOf) == "function" then
        local ok, value = pcall(SC.Registry.idOf, actor)
        if ok and value ~= nil then return tostring(value) end
    end
    local data, dataOk = invoke(actor, "getModData")
    if dataOk and type(data) == "table" and data.SC_Id ~= nil then
        return tostring(data.SC_Id)
    end
    if type(actor) == "table" and actor.id ~= nil then return tostring(actor.id) end
    return tostring(actor or "unknown")
end

local function clean(value, maximum)
    if value == nil then return nil end
    local text = tostring(value):gsub("[\r\n\t]", " ")
    maximum = maximum or 160
    if #text > maximum then return string.sub(text, 1, maximum) end
    return text
end

local function safeDetail(value, depth)
    local kind = type(value)
    if kind == "nil" or kind == "boolean" or kind == "number" then return value end
    if kind == "string" then return clean(value, 160) end
    if kind ~= "table" or (depth or 0) >= 2 then return clean(value, 80) end
    local copy, count = {}, 0
    for key, child in pairs(value) do
        if type(key) == "string" or type(key) == "number" then
            copy[key] = safeDetail(child, (depth or 0) + 1)
            count = count + 1
            if count >= 16 then break end
        end
    end
    return copy
end

local function position(actor)
    local x, xOk = invoke(actor, "getX")
    local y, yOk = invoke(actor, "getY")
    local z, zOk = invoke(actor, "getZ")
    if xOk and yOk and tonumber(x) and tonumber(y) then
        return tonumber(x), tonumber(y), zOk and tonumber(z) or 0
    end
    return nil
end

local function distanceFrom(actor, origin)
    if type(origin) ~= "table" then return 0 end
    local x, y, z = position(actor)
    if x == nil then return 0 end
    local dx, dy = x - (origin.x or x), y - (origin.y or y)
    local dz = (z or 0) - (origin.z or z or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function historyFor(actor)
    local history = historyByActor[actor]
    if not history then
        history = {}
        historyByActor[actor] = history
    end
    return history
end

local function append(actor, event, token, reason, detail)
    local history = historyFor(actor)
    local entry = {
        at = nowMs(), event = event,
        actorId = token and token.actorId or actorId(actor),
        token = token and token.serial or nil,
        owner = token and token.owner or nil,
        action = token and token.action or nil,
        phase = token and token.phase or nil,
        targetKey = token and token.targetKey or nil,
        reason = clean(reason, 128), detail = safeDetail(detail, 0),
    }
    history[#history + 1] = entry
    local limit = math.max(4, tonumber(config("actionHistoryLimit", 20)) or 20)
    while #history > limit do table.remove(history, 1) end
    return entry
end

local function copyRecord(record)
    if type(record) ~= "table" then return nil end
    return {
        actorId = record.actorId,
        serial = record.serial,
        owner = record.owner,
        action = record.action,
        phase = record.phase,
        priority = record.priority,
        targetKey = record.targetKey,
        targetLabel = record.targetLabel,
        startedAt = record.startedAt,
        phaseAt = record.phaseAt,
        lastProgressAt = record.lastProgressAt,
        progress = safeDetail(record.progress, 0),
        reason = record.reason,
        failureCategory = record.failureCategory,
        recovery = safeDetail(record.recovery, 0),
        terminalAt = record.terminalAt,
        reservationCount = type(record.reservations) == "table" and #record.reservations or 0,
        protectedPose = record.protectedPose == true,
        visualVerified = record.visualVerified == true,
    }
end

local function deadlineFor(token, phase)
    local deadlines = token.deadlines
    if type(deadlines) == "table" and tonumber(deadlines[phase]) ~= nil then
        return math.max(0, tonumber(deadlines[phase]))
    end
    local settings = {
        selected = { "actionSelectedTimeoutMs", 2500 },
        reserved = { "actionReservedTimeoutMs", 5000 },
        approaching = { "actionApproachTimeoutMs", 15000 },
        settling = { "actionSettleTimeoutMs", 2500 },
        animating = { "actionAnimationTimeoutMs", 12000 },
        committing = { "actionCommitTimeoutMs", 1000 },
        verifying = { "actionVerifyTimeoutMs", 1000 },
        waiting = { "actionWaitingTimeoutMs", 15000 },
        recovering = { "actionRecoveryTimeoutMs", 15000 },
    }
    local setting = settings[phase]
    return setting and math.max(0, tonumber(config(setting[1], setting[2])) or setting[2]) or 0
end

local function failureCategory(reason)
    local value = tostring(reason or "unknown")
    if string.find(value, "animation", 1, true) or string.find(value, "pose", 1, true) then
        return "animation"
    elseif string.find(value, "route", 1, true) or string.find(value, "blocked", 1, true)
        or string.find(value, "recovery", 1, true) or string.find(value, "interaction_point", 1, true) then
        return "navigation"
    elseif string.find(value, "source", 1, true) or string.find(value, "target", 1, true)
        or string.find(value, "topology", 1, true) then return "target"
    elseif string.find(value, "suppl", 1, true) or string.find(value, "bandage", 1, true)
        or string.find(value, "full", 1, true) or string.find(value, "capacity", 1, true)
        or string.find(value, "seat", 1, true) or string.find(value, "load_policy", 1, true) then
        return "resources"
    elseif string.find(value, "commit", 1, true) or string.find(value, "verif", 1, true)
        or string.find(value, "rollback", 1, true) or string.find(value, "reservation", 1, true) then
        return "transaction"
    elseif string.find(value, "command", 1, true) or string.find(value, "danger", 1, true)
        or value == "death" or value == "actor_removed" or value == "save_boundary" then
        return "control"
    elseif string.find(value, "api", 1, true) or string.find(value, "external", 1, true)
        or string.find(value, "unsupported", 1, true) then return "capability" end
    return "unknown"
end

local function retryKey(action, targetKey, category)
    return tostring(action or "unknown") .. "|" .. tostring(targetKey or "none")
        .. "|" .. tostring(category or "unknown")
end

local function retryDelay(attempt)
    if attempt <= 1 then return tonumber(config("actionRetryBaseMs", 1500)) or 1500 end
    if attempt == 2 then return tonumber(config("actionRetrySecondMs", 5000)) or 5000 end
    if attempt == 3 then return tonumber(config("actionRetryThirdMs", 15000)) or 15000 end
    return tonumber(config("actionRetryMaximumMs", 60000)) or 60000
end

local function noteFailure(actor, token, reason, category)
    local ledger = retryByActor[actor]
    if not ledger then ledger = {} retryByActor[actor] = ledger end
    local key = retryKey(token.action, token.targetKey, category)
    local previous = ledger[key]
    local attempts = math.min(tonumber(config("actionRetryMaxAttempts", 4)) or 4,
        (previous and tonumber(previous.attempts) or 0) + 1)
    local current = nowMs()
    ledger[key] = {
        action = token.action, targetKey = token.targetKey, category = category,
        reason = clean(reason, 128), attempts = attempts,
        failedAt = current, retryAt = current + retryDelay(attempts),
    }
    return ledger[key]
end

local function releaseReservations(token)
    if type(token.reservations) ~= "table" then return 0 end
    local released = 0
    for _, resource in ipairs(token.reservations) do
        if reservationOwners[resource] == token then
            reservationOwners[resource] = nil
            released = released + 1
        end
    end
    token.reservations = {}
    return released
end

local function finish(token, phase, reason, detail, recordRetry)
    if type(token) ~= "table" or token.actor == nil then return false, "invalid_token" end
    if token.terminalAt ~= nil then return false, "token_already_terminal" end
    if activeByActor[token.actor] ~= token then return false, "stale_token" end
    token.phase = phase
    token.reason = clean(reason, 128)
    token.failureCategory = phase == "failed" and failureCategory(reason) or nil
    token.terminalAt = nowMs()
    token.phaseAt = token.terminalAt
    token.recovery = detail and safeDetail(detail, 0) or token.recovery
    releaseReservations(token)
    activeByActor[token.actor] = nil
    local retry
    if recordRetry == true then
        retry = noteFailure(token.actor, token, reason, token.failureCategory)
    end
    append(token.actor, phase, token, reason, detail)
    return true, phase, retry
end

local function runCancel(token, reason, force, terminalFailure)
    if token.cancelling == true then return false, "cancel_in_progress" end
    if token.interruptible ~= true and force ~= true then return false, "owner_not_interruptible" end
    if token.phase == "committing" or token.phase == "verifying" then
        if force ~= true then return false, "owner_commit_in_progress" end
    end
    token.cancelling = true
    local callbackOk, accepted, callbackReason = true, true, nil
    if type(token.onCancel) == "function" then
        callbackOk, accepted, callbackReason = pcall(token.onCancel,
            token.actor, reason, token)
        if not callbackOk then
            if SC.Diagnostics and type(SC.Diagnostics.report) == "function" then
                SC.Diagnostics.report("action-supervisor", token.actorId,
                    "action cancellation callback failed", accepted)
            end
            token.cancelling = false
            return finish(token, "failed", "rollback_failed", {
                requestedReason = reason, error = clean(accepted, 160),
            }, true)
        end
        if accepted == false and force ~= true then
            token.cancelling = false
            return false, callbackReason or "cancel_rejected"
        end
    end
    token.cancelling = false
    local terminal = terminalFailure == true and "failed" or "cancelled"
    return finish(token, terminal, reason or callbackReason or terminal, {
        callbackReason = callbackReason,
    }, terminalFailure == true)
end

function Supervisor.retryStatus(actor, action, targetKey, category)
    local ledger = actor and retryByActor[actor] or nil
    if not ledger then return nil end
    local record = ledger[retryKey(action, targetKey, category)]
    if not record then return nil end
    local copy = safeDetail(record, 0)
    copy.remainingMs = math.max(0, (tonumber(record.retryAt) or 0) - nowMs())
    return copy
end

function Supervisor.canRetry(actor, action, targetKey, category)
    local status = Supervisor.retryStatus(actor, action, targetKey, category)
    if not status then return true end
    if (tonumber(status.remainingMs) or 0) <= 0 then return true, status end
    return false, status
end

function Supervisor.clearRetry(actor, action, targetKey)
    local ledger = actor and retryByActor[actor] or nil
    if not ledger then return 0 end
    local cleared = 0
    for key, record in pairs(ledger) do
        if (action == nil or record.action == action)
            and (targetKey == nil or record.targetKey == targetKey) then
            ledger[key] = nil
            cleared = cleared + 1
        end
    end
    return cleared
end

function Supervisor.begin(actor, spec)
    if actor == nil or type(spec) ~= "table" then return nil, "invalid_action_spec" end
    local owner = clean(spec.owner, 48)
    local action = clean(spec.action, 80)
    if not owner or owner == "" or not action or action == "" then
        return nil, "action_owner_or_name_missing"
    end
    Supervisor.update(actor)
    local current = activeByActor[actor]
    local targetKey = clean(spec.targetKey, 120)
    if current then
        if current.owner == owner and current.action == action
            and current.targetKey == targetKey then return current, "already_active" end
        local incomingPriority = tonumber(spec.priority) or Supervisor.Priority.WORK
        if incomingPriority <= (tonumber(current.priority) or 0) then
            return nil, "actor_owned_by:" .. tostring(current.owner) .. ":" .. tostring(current.action)
        end
        local cancelled, cancelReason = runCancel(current,
            "preempted_by:" .. owner .. ":" .. action, false)
        if not cancelled then return nil, cancelReason or "preemption_rejected" end
    end
    if spec.ignoreRetry ~= true then
        local category = clean(spec.retryCategory, 48) or "unknown"
        local ready, retry = Supervisor.canRetry(actor, action, targetKey, category)
        if not ready then return nil, "retry_cooldown", retry end
    end
    sequence = sequence + 1
    local currentTime = nowMs()
    local token = {
        actor = actor, actorId = actorId(actor), serial = sequence,
        owner = owner, action = action,
        priority = tonumber(spec.priority) or Supervisor.Priority.WORK,
        targetKey = targetKey, targetLabel = clean(spec.targetLabel, 96),
        phase = validPhases[spec.phase] and spec.phase or "selected",
        startedAt = currentTime, phaseAt = currentTime, lastProgressAt = currentTime,
        progress = safeDetail(spec.progress, 0), progressSignature = nil,
        interruptible = spec.interruptible ~= false,
        requiresVisual = spec.requiresVisual == true,
        visualVerified = spec.visualVerified == true,
        protectedPose = spec.protectedPose == true,
        onCancel = spec.onCancel,
        deadlines = type(spec.deadlines) == "table" and spec.deadlines or nil,
        allowedActions = type(spec.allowedActions) == "table" and spec.allowedActions or {},
        allowedMovementPhases = type(spec.allowedMovementPhases) == "table"
            and spec.allowedMovementPhases or movementPhases,
        reservations = {}, metadata = safeDetail(spec.metadata, 0),
    }
    if token.protectedPose then
        local x, y, z = position(actor)
        if x ~= nil then token.poseOrigin = { x = x, y = y, z = z } end
    end
    activeByActor[actor] = token
    append(actor, "begin", token, "accepted", token.metadata)
    return token, "started"
end

function Supervisor.current(actor)
    if actor == nil then return nil end
    Supervisor.update(actor)
    return activeByActor[actor]
end

function Supervisor.isCurrent(token)
    return type(token) == "table" and token.actor ~= nil
        and activeByActor[token.actor] == token and token.terminalAt == nil
end

function Supervisor.transition(token, phase, detail)
    if not Supervisor.isCurrent(token) then return false, "stale_token" end
    if not validPhases[phase] or terminalPhases[phase] then return false, "invalid_active_phase" end
    if phase == "committing" and token.requiresVisual and token.visualVerified ~= true then
        return false, "commit_without_verified_visual"
    end
    local current = nowMs()
    token.phase = phase
    token.phaseAt = current
    token.lastProgressAt = current
    token.progress = safeDetail(detail, 0)
    if phase == "animating" then
        token.protectedPose = true
        local x, y, z = position(token.actor)
        if x ~= nil then token.poseOrigin = { x = x, y = y, z = z } end
    end
    append(token.actor, "transition", token, nil, detail)
    return true, phase
end

function Supervisor.progress(token, signature, detail)
    if not Supervisor.isCurrent(token) then return false, "stale_token" end
    local value = clean(signature, 120)
    if value ~= token.progressSignature then
        token.progressSignature = value
        token.lastProgressAt = nowMs()
        token.progress = safeDetail(detail, 0) or token.progress
        append(token.actor, "progress", token, value, detail)
        return true, "progressed"
    end
    return true, "unchanged"
end

function Supervisor.markVisualVerified(token, detail)
    if not Supervisor.isCurrent(token) then return false, "stale_token" end
    token.visualVerified = true
    token.protectedPose = false
    token.lastProgressAt = nowMs()
    append(token.actor, "visual_verified", token, "verified", detail)
    return true
end

function Supervisor.reserve(token, resource, label)
    if not Supervisor.isCurrent(token) or resource == nil then return false, "invalid_reservation" end
    local owner = reservationOwners[resource]
    if owner and owner ~= token and Supervisor.isCurrent(owner) then
        return false, "resource_reserved"
    end
    if owner == token then return true, "already_reserved" end
    reservationOwners[resource] = token
    token.reservations[#token.reservations + 1] = resource
    append(token.actor, "reserve", token, clean(label, 96) or "resource", nil)
    return true, "reserved"
end

function Supervisor.release(token, resource, reason)
    if type(token) ~= "table" or resource == nil then return false, "invalid_reservation" end
    if reservationOwners[resource] ~= token then return false, "reservation_not_owned" end
    reservationOwners[resource] = nil
    for index = #token.reservations, 1, -1 do
        if token.reservations[index] == resource then table.remove(token.reservations, index) end
    end
    append(token.actor, "release", token, reason or "released", nil)
    return true, "released"
end

function Supervisor.complete(token, reason, receipt)
    return finish(token, "completed", reason or "completed", receipt, false)
end

function Supervisor.fail(token, reason, detail)
    return finish(token, "failed", reason or "unknown_failure", detail, true)
end

function Supervisor.cancel(actor, reason, minimumPriority, force)
    local token = actor and activeByActor[actor] or nil
    if not token then return true, "no_active_action" end
    if tonumber(minimumPriority) and (tonumber(token.priority) or 0) >= tonumber(minimumPriority)
        and force ~= true then return false, "owner_priority_protected" end
    return runCancel(token, reason or "cancelled", force == true)
end

function Supervisor.update(actor)
    local token = actor and activeByActor[actor] or nil
    if not token then return false, "idle" end
    if token.protectedPose and token.poseOrigin then
        local displacement = distanceFrom(actor, token.poseOrigin)
        local maximum = tonumber(config("actionPoseMaximumDisplacement", 0.25)) or 0.25
        if displacement > maximum and token.poseViolation ~= true then
            token.poseViolation = true
            if SC.Diagnostics and type(SC.Diagnostics.report) == "function" then
                SC.Diagnostics.report("action-supervisor", token.actorId,
                    "protected pose moved", tostring(displacement))
            end
            append(actor, "invariant_violation", token, "protected_pose_moved", {
                displacement = displacement, maximum = maximum,
            })
        end
    end
    local deadline = deadlineFor(token, token.phase)
    if deadline > 0 and nowMs() - (tonumber(token.lastProgressAt) or token.phaseAt) > deadline then
        local phase = token.phase
        local cancelled, reason = runCancel(token,
            "phase_timeout:" .. tostring(phase), true, true)
        return cancelled, reason or "phase_timeout"
    end
    return true, token.phase
end

function Supervisor.movementPermission(actor, action, intent)
    Supervisor.update(actor)
    local token = actor and activeByActor[actor] or nil
    if not token then return true, "unowned" end
    action = tostring(action or "move")
    if token.allowedActions[action] == true then return true, "owner_action" end
    if token.allowedMovementPhases[token.phase] == true
        and type(intent) == "table" and intent.supervisorToken == token then
        return true, "owner_movement"
    end
    return false, "action_owned:" .. tostring(token.owner) .. ":"
        .. tostring(token.action) .. ":" .. tostring(token.phase), copyRecord(token)
end

local function nativeSnapshot(actor)
    if not SC.NativeActions or type(SC.NativeActions.activityStatus) ~= "function" then return nil end
    local phase, owner, action, at = SC.NativeActions.activityStatus(actor)
    if phase == nil or phase == "none" then return nil end
    return {
        actorId = actorId(actor), owner = owner or "native", action = action or "activity",
        phase = phase, startedAt = at, phaseAt = at, priority = Supervisor.Priority.EXTERNAL,
        external = owner == "native", compatibility = true, reservationCount = 0,
    }
end

function Supervisor.snapshot(actor)
    if actor == nil then return nil end
    Supervisor.update(actor)
    local current = activeByActor[actor]
    local snapshot = current and copyRecord(current) or nativeSnapshot(actor)
    local history = historyFor(actor)
    local last = history[#history]
    if not snapshot then
        snapshot = { actorId = actorId(actor), phase = "idle", owner = "none", action = "idle" }
    end
    snapshot.last = last and safeDetail(last, 0) or nil
    local activeReservations = current and #current.reservations or 0
    snapshot.reservationCount = activeReservations
    return snapshot
end

function Supervisor.history(actor, limit)
    local source = actor and historyFor(actor) or {}
    limit = math.max(1, math.min(#source, tonumber(limit) or #source))
    local result = {}
    local first = math.max(1, #source - limit + 1)
    for index = first, #source do result[#result + 1] = safeDetail(source[index], 0) end
    return result
end

function Supervisor.reservationCount(actor)
    local token = actor and activeByActor[actor] or nil
    return token and #token.reservations or 0
end

function Supervisor.leakedReservations()
    local count = 0
    for resource, token in pairs(reservationOwners) do
        if resource ~= nil and not Supervisor.isCurrent(token) then count = count + 1 end
    end
    return count
end

function Supervisor.reset(actor, reason)
    if actor ~= nil then
        local token = activeByActor[actor]
        if token then runCancel(token, reason or "reset", true) end
        activeByActor[actor] = nil
        retryByActor[actor] = nil
        return true
    end
    local actors = {}
    for value in pairs(activeByActor) do actors[#actors + 1] = value end
    for _, value in ipairs(actors) do
        local token = activeByActor[value]
        if token then runCancel(token, reason or "reset_all", true) end
    end
    activeByActor = setmetatable({}, { __mode = "k" })
    historyByActor = setmetatable({}, { __mode = "k" })
    retryByActor = setmetatable({}, { __mode = "k" })
    reservationOwners = setmetatable({}, { __mode = "k" })
    return true
end

return Supervisor
