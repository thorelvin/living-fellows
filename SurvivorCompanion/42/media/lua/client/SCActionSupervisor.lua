-- SPDX-License-Identifier: MIT

if not SurvivorCompanion or not SurvivorCompanion.Call then
    if type(require) == "function" then pcall(require, "SCCall") end
end

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
-- This graph is deliberately explicit.  A phase may be skipped only through a
-- listed edge; transaction phases never move backwards into selection or
-- animation.  Waiting/recovery are resumable pre-commit support phases.
local legalTransitions = {
    selected = {
        reserved = true, approaching = true, settling = true, animating = true,
        committing = true, waiting = true, recovering = true,
    },
    reserved = {
        approaching = true, settling = true, animating = true,
        committing = true, waiting = true, recovering = true,
    },
    approaching = {
        settling = true, animating = true, committing = true,
        waiting = true, recovering = true,
    },
    settling = {
        animating = true, committing = true, waiting = true, recovering = true,
    },
    animating = { committing = true, waiting = true, recovering = true },
    waiting = {
        selected = true, reserved = true, approaching = true, settling = true,
        animating = true, recovering = true,
    },
    recovering = {
        selected = true, reserved = true, approaching = true, settling = true,
        animating = true, waiting = true,
    },
    committing = { verifying = true },
    verifying = { cooling_down = true },
    cooling_down = {},
}
local movementPhases = { approaching = true, recovering = true }
local activeByActor = setmetatable({}, { __mode = "k" })
local historyByActor = setmetatable({}, { __mode = "k" })
local retryByActor = setmetatable({}, { __mode = "k" })
local retryResetByActor = setmetatable({}, { __mode = "k" })
local reservationOwners = setmetatable({}, { __mode = "k" })
local urgentByActor = setmetatable({}, { __mode = "k" })
local lastUrgentByActor = setmetatable({}, { __mode = "k" })
local sequence = 0
local urgentSequence = 0

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
    local values = SC.Call.pack(SC.Call.method(value, methodName, ...))
    if values[1] ~= true then return nil, false end
    return values[2], true, SC.Call.unpack(values, 3, values.n)
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

local function nativeActivity(actor)
    if actor == nil or not SC.NativeActions
        or type(SC.NativeActions.activityStatus) ~= "function" then return nil end
    local ok, phase, owner, action, at, object = pcall(
        SC.NativeActions.activityStatus, actor)
    if not ok or phase == nil or phase == "none" then return nil end
    return {
        actorId = actorId(actor), owner = owner or "native",
        action = action or "activity", phase = phase, startedAt = at,
        phaseAt = at, object = object, priority = Supervisor.Priority.EXTERNAL,
        external = owner == "native", compatibility = true,
        reservationCount = 0,
    }
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
        targetLabel = token and token.targetLabel or nil,
        failureCategory = token and token.failureCategory or nil,
        recovery = token and safeDetail(token.recovery, 0) or nil,
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
        commitEntered = record.commitEntered == true,
        commitAttempted = record.commitAttempted == true,
        committed = record.committed == true,
        commitAt = record.commitAt,
        commitReceipt = safeDetail(record.commitReceipt, 0),
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
    local value = string.lower(tostring(reason or "unspecified_failure"))
    if string.find(value, "phase_timeout:animat", 1, true) then return "animation" end
    if string.find(value, "phase_timeout:commit", 1, true)
        or string.find(value, "phase_timeout:verif", 1, true) then return "transaction" end
    if string.find(value, "phase_timeout:approach", 1, true)
        or string.find(value, "phase_timeout:recover", 1, true) then return "navigation" end
    if string.find(value, "phase_timeout", 1, true) then return "control" end
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
        or string.find(value, "unsupported", 1, true)
        or string.find(value, "unavailable", 1, true) then return "capability"
    elseif string.find(value, "treatment", 1, true)
        or string.find(value, "medical", 1, true)
        or string.find(value, "equip", 1, true)
        or string.find(value, "wear", 1, true)
        or string.find(value, "transfer", 1, true)
        or string.find(value, "deposit", 1, true)
        or string.find(value, "drop", 1, true)
        or string.find(value, "vehicle", 1, true)
        or string.find(value, "native", 1, true) then return "transaction"
    elseif string.find(value, "invalid", 1, true)
        or string.find(value, "missing", 1, true) then return "target" end
    -- A stable broad category is preferable to emitting an unexplained
    -- `unknown` into public UI/support output.  Callers should still add a more
    -- specific vocabulary mapping when introducing a new failure code.
    return "control"
end

local function retryKey(action, targetKey, category)
    return tostring(action or "unknown") .. "|" .. tostring(targetKey or "none")
        .. "|" .. tostring(category or "control")
end

local function retryDelay(attempt)
    if attempt <= 1 then return tonumber(config("actionRetryBaseMs", 1500)) or 1500 end
    if attempt == 2 then return tonumber(config("actionRetrySecondMs", 5000)) or 5000 end
    if attempt == 3 then return tonumber(config("actionRetryThirdMs", 15000)) or 15000 end
    return tonumber(config("actionRetryMaximumMs", 60000)) or 60000
end

local function retryResetState(actor)
    local state = retryResetByActor[actor]
    if not state then
        state = { generation = 0, reason = "initial", at = nowMs() }
        retryResetByActor[actor] = state
    end
    return state
end

local function noteFailure(actor, token, reason, category)
    local ledger = retryByActor[actor]
    if not ledger then ledger = {} retryByActor[actor] = ledger end
    local key = retryKey(token.action, token.targetKey, category)
    local previous = ledger[key]
    local reset = retryResetState(actor)
    local maximum = math.max(1,
        math.floor(tonumber(config("actionRetryMaxAttempts", 4)) or 4))
    local attempts = math.min(maximum,
        (previous and tonumber(previous.attempts) or 0) + 1)
    local current = nowMs()
    local exhausted = attempts >= maximum
    ledger[key] = {
        action = token.action, targetKey = token.targetKey, category = category,
        reason = clean(reason, 128), attempts = attempts,
        maximumAttempts = maximum, exhausted = exhausted,
        failedAt = current,
        retryAt = exhausted and nil or current + retryDelay(attempts),
        resetGeneration = reset.generation, resetReason = reset.reason,
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

local dispatchQueuedUrgent

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
    if dispatchQueuedUrgent then dispatchQueuedUrgent(token.actor, phase) end
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

local function urgentPublic(record)
    if type(record) ~= "table" then return nil end
    return {
        serial = record.serial, actorId = record.actorId,
        owner = record.owner, action = record.action,
        priority = record.priority, state = record.state,
        reason = record.reason, queuedAt = record.queuedAt,
        expiresAt = record.expiresAt, readyAt = record.readyAt,
        dispatchedAt = record.dispatchedAt, detail = safeDetail(record.detail, 0),
        result = safeDetail(record.result, 0),
    }
end

local function appendUrgent(actor, event, record, reason, detail)
    local token = {
        actorId = record.actorId, serial = record.serial,
        owner = record.owner, action = record.action,
        phase = record.state, targetKey = record.targetKey,
        targetLabel = record.targetLabel,
    }
    append(actor, event, token, reason, detail)
end

dispatchQueuedUrgent = function(actor, releaseReason)
    local record = actor and urgentByActor[actor] or nil
    if not record then return false, "no_urgent_intent" end
    local current = nowMs()
    if current >= (tonumber(record.expiresAt) or current) then
        urgentByActor[actor] = nil
        record.state, record.reason = "expired", "urgent_intent_expired"
        record.readyAt = current
        lastUrgentByActor[actor] = record
        appendUrgent(actor, "urgent_expired", record, record.reason, {
            releaseReason = releaseReason,
        })
        return false, record.reason
    end
    if activeByActor[actor] ~= nil then return false, "urgent_waiting_for_owner" end
    local native = nativeActivity(actor)
    if native ~= nil then
        record.state = "waiting_external"
        record.reason = "external_action_owned:" .. tostring(native.owner)
            .. ":" .. tostring(native.action) .. ":" .. tostring(native.phase)
        return false, record.reason
    end
    urgentByActor[actor] = nil
    record.state, record.readyAt = "dispatching", current
    local callOk, accepted, reason, detail = true, true, "urgent_dispatched", nil
    if type(record.dispatch) == "function" then
        callOk, accepted, reason, detail = pcall(record.dispatch, actor,
            urgentPublic(record))
    end
    record.dispatchedAt = nowMs()
    if not callOk then
        record.state, record.reason = "failed", "urgent_dispatch_error"
        record.result = { error = clean(accepted, 160) }
    elseif accepted == false then
        record.state, record.reason = "failed", clean(reason, 128)
            or "urgent_dispatch_rejected"
        record.result = safeDetail(detail, 0)
    else
        record.state, record.reason = "dispatched", clean(reason, 128)
            or "urgent_dispatched"
        record.result = safeDetail(detail, 0)
    end
    lastUrgentByActor[actor] = record
    appendUrgent(actor, record.state == "dispatched" and "urgent_dispatched"
        or "urgent_dispatch_failed", record, record.reason, {
            releaseReason = releaseReason, result = record.result,
        })
    return record.state == "dispatched", record.reason, urgentPublic(record)
end

function Supervisor.queueUrgent(actor, spec)
    if actor == nil or type(spec) ~= "table" then return false, "invalid_urgent_intent" end
    local action = clean(spec.action, 80)
    if action == nil or action == "" then return false, "urgent_action_missing" end
    local current = nowMs()
    local existing = urgentByActor[actor]
    if existing and current >= (tonumber(existing.expiresAt) or current) then
        dispatchQueuedUrgent(actor, "queue_deadline")
        existing = nil
    end
    if existing then
        if existing.owner == clean(spec.owner, 48) and existing.action == action then
            return true, "urgent_already_queued", urgentPublic(existing)
        end
        return false, "urgent_queue_occupied", urgentPublic(existing)
    end
    urgentSequence = urgentSequence + 1
    local maximumWait = math.max(1, tonumber(spec.expiresMs)
        or tonumber(config("actionUrgentQueueMs", 5000)) or 5000)
    local record = {
        serial = "urgent-" .. tostring(urgentSequence),
        actorId = actorId(actor), owner = clean(spec.owner, 48) or "survival",
        action = action, priority = tonumber(spec.priority) or Supervisor.Priority.SURVIVAL,
        targetKey = clean(spec.targetKey, 120),
        targetLabel = clean(spec.targetLabel, 96),
        state = "queued", reason = clean(spec.reason, 128) or "urgent_queued",
        queuedAt = current, expiresAt = current + maximumWait,
        dispatch = spec.dispatch, detail = safeDetail(spec.detail, 0),
    }
    urgentByActor[actor] = record
    appendUrgent(actor, "urgent_queued", record, record.reason, record.detail)
    local token = activeByActor[actor]
    if token ~= nil and token.phase ~= "committing" and token.phase ~= "verifying" then
        local cancelled, cancelReason = runCancel(token,
            "urgent_preempted_by:" .. tostring(record.owner) .. ":" .. action, false)
        if cancelled ~= true then
            record.reason = cancelReason or "urgent_waiting_for_owner"
            return true, "urgent_queued", urgentPublic(record)
        end
        local last = lastUrgentByActor[actor]
        return last and last.state == "dispatched", last and last.reason
            or "urgent_dispatched", urgentPublic(last)
    end
    if token ~= nil or nativeActivity(actor) ~= nil then
        return true, "urgent_queued", urgentPublic(record)
    end
    return dispatchQueuedUrgent(actor, "owner_idle")
end

function Supervisor.urgentStatus(actor)
    return urgentPublic(actor and (urgentByActor[actor] or lastUrgentByActor[actor]) or nil)
end

function Supervisor.clearUrgent(actor, reason)
    local record = actor and urgentByActor[actor] or nil
    if not record then return false, "no_urgent_intent" end
    urgentByActor[actor] = nil
    record.state, record.reason = "cancelled", clean(reason, 128) or "urgent_cancelled"
    record.readyAt = nowMs()
    lastUrgentByActor[actor] = record
    appendUrgent(actor, "urgent_cancelled", record, record.reason, nil)
    return true, record.reason
end

function Supervisor.retryStatus(actor, action, targetKey, category)
    local ledger = actor and retryByActor[actor] or nil
    if not ledger then return nil end
    local record = ledger[retryKey(action, targetKey, category)]
    if not record then return nil end
    local copy = safeDetail(record, 0)
    copy.remainingMs = record.exhausted == true and 0
        or math.max(0, (tonumber(record.retryAt) or 0) - nowMs())
    return copy
end

function Supervisor.retryStatusAny(actor, action, targetKey)
    local ledger = actor and retryByActor[actor] or nil
    if not ledger then return nil end
    local current = nowMs()
    local selected
    for _, record in pairs(ledger) do
        if record.action == action and record.targetKey == targetKey
            and (record.exhausted == true or (tonumber(record.retryAt) or 0) > current) then
            local better = selected == nil
                or (record.exhausted == true and selected.exhausted ~= true)
                or (record.exhausted == selected.exhausted
                    and (tonumber(record.failedAt) or 0)
                        > (tonumber(selected.failedAt) or 0))
            if better then
                selected = record
            end
        end
    end
    if not selected then return nil end
    local copy = safeDetail(selected, 0)
    copy.remainingMs = selected.exhausted == true and 0
        or math.max(0, (tonumber(selected.retryAt) or 0) - current)
    return copy
end

function Supervisor.canRetry(actor, action, targetKey, category)
    local status = Supervisor.retryStatus(actor, action, targetKey, category)
    if not status then return true end
    if status.exhausted == true then return false, status end
    if (tonumber(status.remainingMs) or 0) <= 0 then return true, status end
    return false, status
end

function Supervisor.resetRetry(actor, reason, action, targetKey)
    if actor == nil then return 0, nil end
    local prior = retryResetState(actor)
    local reset = {
        generation = (tonumber(prior.generation) or 0) + 1,
        reason = clean(reason, 128) or "explicit_retry_reset", at = nowMs(),
    }
    retryResetByActor[actor] = reset
    local ledger = actor and retryByActor[actor] or nil
    local cleared = 0
    if ledger then
        for key, record in pairs(ledger) do
            if (action == nil or record.action == action)
                and (targetKey == nil or record.targetKey == targetKey) then
                ledger[key] = nil
                cleared = cleared + 1
            end
        end
    end
    append(actor, "retry_reset", activeByActor[actor], reset.reason, {
        generation = reset.generation, cleared = cleared,
        action = action, targetKey = targetKey,
    })
    return cleared, safeDetail(reset, 0)
end

function Supervisor.retryResetStatus(actor)
    return safeDetail(actor and retryResetState(actor) or nil, 0)
end

function Supervisor.clearRetry(actor, action, targetKey, reason)
    return Supervisor.resetRetry(actor, reason or "explicit_retry_reset", action, targetKey)
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
    local native = nativeActivity(actor)
    if native ~= nil then
        local prefix = native.external == true and "external_action_owned:"
            or "compatibility_action_owned:"
        return nil, prefix .. tostring(native.owner) .. ":"
            .. tostring(native.action) .. ":" .. tostring(native.phase), native
    end
    if spec.ignoreRetry ~= true then
        local category = clean(spec.retryCategory, 48)
        if category == nil or category == "*" then
            local retry = Supervisor.retryStatusAny(actor, action, targetKey)
            if retry then return nil, retry.exhausted == true and "retry_exhausted"
                or "retry_cooldown", retry end
        else
            local ready, retry = Supervisor.canRetry(actor, action, targetKey, category)
            if not ready then return nil, retry and retry.exhausted == true
                and "retry_exhausted" or "retry_cooldown", retry end
        end
    end
    sequence = sequence + 1
    local currentTime = nowMs()
    local token = {
        actor = actor, actorId = actorId(actor), serial = sequence,
        owner = owner, action = action,
        priority = tonumber(spec.priority) or Supervisor.Priority.WORK,
        targetKey = targetKey, targetLabel = clean(spec.targetLabel, 96),
        phase = validPhases[spec.phase] and not terminalPhases[spec.phase]
            and spec.phase or "selected",
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
        commitEntered = false, commitAttempted = false, committed = false,
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

function Supervisor.commit(token, operation, detail)
    if not Supervisor.isCurrent(token) then return false, "stale_token" end
    if token.phase ~= "committing" then return false, "commit_phase_required" end
    if token.commitAttempted == true then return false, "commit_already_attempted",
        safeDetail(token.commitReceipt, 0) end
    token.commitAttempted = true
    local accepted, reason, receipt = true, "committed", nil
    if type(operation) == "function" then
        local callOk
        callOk, accepted, reason, receipt = pcall(operation, token)
        if not callOk then
            accepted, receipt = false, { error = clean(accepted, 160) }
            reason = "commit_callback_failed"
        end
    else
        receipt = operation
        if receipt == nil then receipt = detail end
    end
    token.commitAt = nowMs()
    token.commitReceipt = safeDetail(receipt, 0)
    token.lastProgressAt = token.commitAt
    if accepted ~= true then
        token.commitRejected = true
        append(token.actor, "commit_rejected", token,
            clean(reason, 128) or "commit_rejected", token.commitReceipt)
        return false, clean(reason, 128) or "commit_rejected", token.commitReceipt
    end
    token.committed = true
    append(token.actor, "commit", token, clean(reason, 128) or "committed",
        token.commitReceipt)
    return true, clean(reason, 128) or "committed", token.commitReceipt
end

function Supervisor.transition(token, phase, detail)
    if not Supervisor.isCurrent(token) then return false, "stale_token" end
    if not validPhases[phase] or terminalPhases[phase] then return false, "invalid_active_phase" end
    if token.phase == phase then
        token.progress = safeDetail(detail, 0) or token.progress
        return true, "unchanged"
    end
    local edges = legalTransitions[token.phase]
    if type(edges) ~= "table" or edges[phase] ~= true then
        return false, "illegal_phase_transition:" .. tostring(token.phase)
            .. ":" .. tostring(phase)
    end
    if phase == "committing" then
        if token.requiresVisual and token.visualVerified ~= true then
            return false, "commit_without_verified_visual"
        end
        if token.commitEntered == true or token.commitAttempted == true then
            return false, "commit_already_entered"
        end
    elseif phase == "verifying" then
        if token.phase ~= "committing" then return false, "commit_phase_required" end
        if token.commitAttempted ~= true then
            local recorded, recordReason = Supervisor.commit(token, {
                legacyTransition = true, detail = safeDetail(detail, 0),
            })
            if recorded ~= true then return false, recordReason or "commit_receipt_missing" end
        elseif token.committed ~= true then
            return false, "commit_not_accepted"
        end
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
    elseif phase == "committing" then
        token.commitEntered = true
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

function Supervisor.expectVisual(token, detail)
    if not Supervisor.isCurrent(token) then return false, "stale_token" end
    if token.commitEntered == true or token.committed == true then
        return false, "visual_after_commit"
    end
    token.requiresVisual = true
    token.visualVerified = false
    token.protectedPose = true
    local x, y, z = position(token.actor)
    token.poseOrigin = x ~= nil and { x = x, y = y, z = z } or nil
    token.lastProgressAt = nowMs()
    append(token.actor, "visual_expected", token, "pending", detail)
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
    if not Supervisor.isCurrent(token) then return false, "stale_token" end
    if token.commitEntered == true and token.committed ~= true then
        return false, "commit_receipt_missing"
    end
    if token.phase == "committing" then return false, "verification_phase_required" end
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
    if not token then
        if actor and urgentByActor[actor] then
            local dispatched, reason = dispatchQueuedUrgent(actor, "owner_idle")
            return dispatched, reason
        end
        return false, "idle"
    end
    local queued = urgentByActor[actor]
    if queued and nowMs() >= (tonumber(queued.expiresAt) or nowMs()) then
        dispatchQueuedUrgent(actor, "queue_deadline")
    end
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
    return nativeActivity(actor)
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

local function mostRecentFailure(actor)
    local history = actor and historyFor(actor) or {}
    for index = #history, 1, -1 do
        local entry = history[index]
        if entry.event == "failed" then return entry end
    end
    return nil
end

local function mostRecentRetry(actor)
    local ledger = actor and retryByActor[actor] or nil
    if not ledger then return nil end
    local selected
    for _, record in pairs(ledger) do
        if selected == nil or (tonumber(record.failedAt) or 0)
            > (tonumber(selected.failedAt) or 0) then
            selected = record
        end
    end
    if not selected then return nil end
    local copy = safeDetail(selected, 0)
    copy.remainingMs = selected.exhausted == true and 0
        or math.max(0, (tonumber(selected.retryAt) or 0) - nowMs())
    return copy
end

function Supervisor.summary(actor)
    if actor == nil then return nil end
    Supervisor.update(actor)
    local token = activeByActor[actor]
    local native = token == nil and nativeSnapshot(actor) or nil
    local source = token or native
    local failure = mostRecentFailure(actor)
    local retry = mostRecentRetry(actor)
    local currentTime = nowMs()
    return {
        actorId = actorId(actor),
        active = source ~= nil,
        external = source and source.external == true or false,
        owner = source and source.owner or "none",
        action = source and source.action or "idle",
        phase = source and source.phase or "idle",
        targetKey = source and source.targetKey or nil,
        targetLabel = source and source.targetLabel or nil,
        progress = source and safeDetail(source.progress, 0) or nil,
        reason = source and source.reason or nil,
        recovery = source and safeDetail(source.recovery, 0) or nil,
        ageMs = source and math.max(0, currentTime
            - (tonumber(source.startedAt) or currentTime)) or 0,
        phaseAgeMs = source and math.max(0, currentTime
            - (tonumber(source.phaseAt) or currentTime)) or 0,
        reservationCount = token and #token.reservations or 0,
        lastFailure = failure and safeDetail(failure, 0) or nil,
        retry = retry,
        urgent = Supervisor.urgentStatus(actor),
    }
end

function Supervisor.health()
    local result = {
        active = 0,
        reservations = 0,
        leakedReservations = 0,
        coolingDown = 0,
        exhaustedRetries = 0,
        invariantViolations = 0,
    }
    for _, token in pairs(activeByActor) do
        if Supervisor.isCurrent(token) then
            result.active = result.active + 1
            result.reservations = result.reservations + #(token.reservations or {})
        end
    end
    for _, token in pairs(reservationOwners) do
        if not Supervisor.isCurrent(token) then result.leakedReservations = result.leakedReservations + 1 end
    end
    local current = nowMs()
    for actor, ledger in pairs(retryByActor) do
        if actor ~= nil then
            for _, record in pairs(ledger) do
                if record.exhausted == true then
                    result.exhaustedRetries = result.exhaustedRetries + 1
                elseif (tonumber(record.retryAt) or 0) > current then
                    result.coolingDown = result.coolingDown + 1
                end
            end
        end
    end
    for actor, history in pairs(historyByActor) do
        if actor ~= nil then
            for _, entry in ipairs(history) do
                if entry.event == "invariant_violation" then
                    result.invariantViolations = result.invariantViolations + 1
                end
            end
        end
    end
    result.healthy = result.leakedReservations == 0 and result.invariantViolations == 0
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
        if urgentByActor[actor] then Supervisor.clearUrgent(actor,
            reason or "reset") end
        local token = activeByActor[actor]
        if token then runCancel(token, reason or "reset", true) end
        activeByActor[actor] = nil
        retryByActor[actor] = nil
        local prior = retryResetState(actor)
        retryResetByActor[actor] = {
            generation = (tonumber(prior.generation) or 0) + 1,
            reason = clean(reason, 128) or "reset", at = nowMs(),
        }
        return true
    end
    -- A reset boundary cancels queued survival work; it must never dispatch
    -- movement while actors are being torn down.
    urgentByActor = setmetatable({}, { __mode = "k" })
    lastUrgentByActor = setmetatable({}, { __mode = "k" })
    local actors = {}
    for value in pairs(activeByActor) do actors[#actors + 1] = value end
    for _, value in ipairs(actors) do
        local token = activeByActor[value]
        if token then runCancel(token, reason or "reset_all", true) end
    end
    activeByActor = setmetatable({}, { __mode = "k" })
    historyByActor = setmetatable({}, { __mode = "k" })
    retryByActor = setmetatable({}, { __mode = "k" })
    retryResetByActor = setmetatable({}, { __mode = "k" })
    reservationOwners = setmetatable({}, { __mode = "k" })
    return true
end

return Supervisor
