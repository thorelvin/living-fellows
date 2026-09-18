--[[
PZ Radio Link -- tick loop, command dispatch and state export.

One Events.OnTickEvenPaused handler. Single-player pauses on focus loss and
OnTick stops with the game loop, which would make the page report that the game
had gone away at exactly the moment the player looked at it.

BF-09: work is scheduled by elapsed milliseconds, not by counting callbacks.
The old code assumed 60 callbacks per second; at 30 fps it silently halved the
transport rate. After a stall at most one due operation runs per callback, so
returning from a pause cannot burst file I/O.

BF-03: a command owns its timed action and reports what actually happened.
`applied` requires the owned action to have run AND the device to show the
requested state. When neither completion nor cancellation can be established
the result is `unknown` -- never `cancelled`, which previously meant nothing
more than "four seconds passed" while the action was still queued and able to
execute later.

BF-04: the pending record captures the exact item, player and binding it was
created for, so a relink cannot make the observer judge a different radio.
]]

PZRL = PZRL or {}

local Runtime = {}
PZRL.Runtime = Runtime

Runtime.COMMAND_INTERVAL_MS = 250
Runtime.STATE_INTERVAL_MS = 500
Runtime.HEARTBEAT_MS = 1000

-- Time allowed waiting in the player's queue, separate from time executing.
-- A radio action may legitimately sit behind a long task.
Runtime.QUEUE_WAIT_MS = 20000
Runtime.EXECUTING_MS = 8000

Runtime.RESULT_RETENTION = 8

Runtime._installed = false
Runtime._pending = nil
Runtime._results = {}
Runtime._nextCommandAt = 0
Runtime._nextStateAt = 0
Runtime._lastPublishedKey = nil
Runtime._snapshotCache = nil
Runtime._snapshotAt = 0

local function now()
    return getTimestampMs()
end

local function recordResult(id, status, reason)
    if id == nil or id == "" then return end
    for _, existing in ipairs(Runtime._results) do
        if existing.id == id then
            existing.status = status
            existing.reason = reason or ""
            existing.at = now()
            return
        end
    end
    table.insert(Runtime._results, 1, {
        id = id, status = status, reason = reason or "", at = now(),
    })
    while #Runtime._results > Runtime.RESULT_RETENTION do
        table.remove(Runtime._results)
    end
end

--[[ ---------------------------------------------------------------- pending ]]

local function beginPending(id, kind, owned, postcondition, identity)
    Runtime._pending = {
        id = id,
        kind = kind,
        owned = owned,
        postcondition = postcondition,
        -- BF-04: judge the radio this command was composed against.
        item = identity.item,
        player = identity.player,
        binding = identity.binding,
        queuedAt = now(),
    }
    recordResult(id, "queued")
end

local function finishPending(status, reason)
    local pending = Runtime._pending
    if pending == nil then return end
    Runtime._pending = nil
    recordResult(pending.id, status, reason)
end

--[[
Truthful outcome rules:

  applied    the owned action ran (or completed as a verified no-op) AND the
             device shows the requested state.
  cancelled  the owned action is known to be unable to execute again.
  unknown    we cannot establish either. The command is not retried and the
             page shows a recovery state rather than a spinner.
]]
local function resolvePending(snapshot, paused)
    local pending = Runtime._pending
    if pending == nil then return end
    local owned = pending.owned

    -- The binding must still be the one this command was made for.
    if PZRL.Session.bindingId ~= pending.binding
            or PZRL.Session.item ~= pending.item then
        PZRL.Device.cancelOwnedAction(owned)
        finishPending("cancelled", "rebound")
        return
    end

    if owned.performed then
        if owned.noop then
            PZRL.Session.bumpRevision()
            finishPending("applied", "noop")
            return
        end
        if snapshot ~= nil and pending.postcondition(snapshot) then
            PZRL.Session.bumpRevision()
            finishPending("applied")
            return
        end
        -- Ran, but the device does not show it. Do not claim success.
        if now() - (owned.startedAt or pending.queuedAt) > Runtime.EXECUTING_MS then
            finishPending("unknown", "postcondition_not_observed")
        end
        return
    end

    if owned.invalidated then
        finishPending("cancelled", "preconditions_changed")
        return
    end

    if owned.stopped then
        -- Stopped before performing: it cannot execute again.
        finishPending("cancelled", "interrupted")
        return
    end

    -- Pause freezes the action queue, so neither deadline should advance.
    if paused then
        pending.queuedAt = pending.queuedAt + (now() - (pending.tickedAt or now()))
    end
    pending.tickedAt = now()

    if owned.started then
        if now() - owned.startedAt > Runtime.EXECUTING_MS then
            PZRL.Device.cancelOwnedAction(owned)
            finishPending("unknown", "execution_did_not_finish")
        end
        return
    end

    -- Still waiting in the queue behind the player's own work.
    if now() - pending.queuedAt > Runtime.QUEUE_WAIT_MS then
        -- Stop it first: expiring while it can still run is exactly the bug
        -- that made "cancelled" commands apply themselves later.
        local cancelled = PZRL.Device.cancelOwnedAction(owned)
        finishPending(cancelled and "cancelled" or "unknown", "queue_wait_expired")
    end
end

--[[ --------------------------------------------------------------- commands ]]

local HANDLERS = {}

HANDLERS.set_power = function(fields, player, item, revalidate)
    local desired = PZRL.Codec.boolean(fields, "value")
    if desired == nil then return nil, "bad_value" end
    local owned, reason = PZRL.Device.requestPower(player, item, desired, revalidate)
    if owned == nil then return nil, reason end
    return owned, nil, function(snap) return snap.turnedOn == desired end
end

HANDLERS.set_channel = function(fields, player, item, revalidate)
    local channel = PZRL.Codec.integer(fields, "value")
    if channel == nil then return nil, "bad_value" end
    local owned, reason = PZRL.Device.requestChannel(player, item, channel, revalidate)
    if owned == nil then return nil, reason end
    return owned, nil, function(snap) return snap.channel == channel end
end

HANDLERS.set_volume = function(fields, player, item, revalidate)
    local volume = PZRL.Codec.number(fields, "value")
    if volume == nil then return nil, "bad_value" end
    local owned, reason = PZRL.Device.requestVolume(player, item, volume, revalidate)
    if owned == nil then return nil, reason end
    return owned, nil, function(snap)
        return type(snap.volume) == "number"
            and math.abs(snap.volume - volume) <= PZRL.Device.VOLUME_EPSILON
    end
end

HANDLERS.select_preset = function(fields, player, item, revalidate)
    local index = PZRL.Codec.integer(fields, "index")
    if index == nil then return nil, "bad_value" end
    local expectedFreq = PZRL.Codec.integer(fields, "freq")
    local expectedRev = PZRL.Codec.integer(fields, "prev")
    local data = PZRL.Device.dataOf(item)
    if data == nil then return nil, "unreadable" end
    local entry = PZRL.Device.presets(data)[index]
    local owned, reason = PZRL.Device.requestPreset(
        player, item, index, expectedFreq, expectedRev, revalidate)
    if owned == nil then return nil, reason end
    local target = entry and entry.freq
    return owned, nil, function(snap) return snap.channel == target end
end

HANDLERS.unlink = function()
    PZRL.Session.clear("unlinked_by_host")
    return nil, "noop"
end

local function dispatch(fields)
    local id = fields.id
    if id == nil or id == "" then return end

    -- BF-08: the protocol version is enforced, not merely carried.
    if PZRL.Codec.integer(fields, "proto") ~= PZRL.Codec.PROTOCOL then
        recordResult(id, "rejected", "protocol_mismatch")
        return
    end
    -- BF-02: an envelope the mod did not read in time must not execute late.
    local deadline = PZRL.Codec.number(fields, "deadline")
    if deadline ~= nil and now() > deadline then
        recordResult(id, "expired", "acceptance_deadline")
        return
    end
    if fields.epoch ~= PZRL.Session.gameEpoch then
        recordResult(id, "rejected", "stale_epoch")
        return
    end
    if fields.binding ~= PZRL.Session.bindingId then
        recordResult(id, "rejected", "stale_binding")
        return
    end
    if Runtime._pending ~= nil then
        recordResult(id, "rejected", "busy")
        return
    end

    local ok, reason = PZRL.Session.validate()
    if not ok then
        recordResult(id, "rejected", reason)
        return
    end
    if fields.cmd ~= "unlink" and not PZRL.Session.reachable() then
        recordResult(id, "rejected", "too_far")
        return
    end

    local handler = HANDLERS[fields.cmd or ""]
    if handler == nil then
        recordResult(id, "rejected", "unknown_command")
        return
    end

    -- Re-proved at the moment the engine is about to execute, not now.
    local binding, item, player = PZRL.Session.bindingId, PZRL.Session.item, PZRL.Session.player
    local revalidate = function()
        if PZRL.Session.bindingId ~= binding or PZRL.Session.item ~= item then return false end
        local stillOk = PZRL.Session.validate()
        return stillOk and PZRL.Session.reachable()
    end

    local owned, failReason, postcondition = handler(fields, player, item, revalidate)
    if owned == nil then
        if failReason == "noop" then
            PZRL.Session.bumpRevision()
            recordResult(id, "applied", "noop")
        else
            recordResult(id, "rejected", failReason)
        end
        return
    end
    beginPending(id, fields.cmd, owned, postcondition,
                 { item = item, player = player, binding = binding })
end

--[[ ------------------------------------------------------------------ state ]]

local function presetPairs(snapshot)
    local parts = {}
    for _, entry in ipairs(snapshot.presets or {}) do
        local name = string.gsub(PZRL.Codec.sanitize(entry.name, 24), "%|", "")
        if name == "" then name = "Preset" end
        parts[#parts + 1] = name .. ":" .. tostring(math.floor(entry.freq or 0))
    end
    return table.concat(parts, "|")
end

local function publish(snapshot, statusReason, paused)
    local pairs_ = {
        { "proto", tostring(PZRL.Codec.PROTOCOL) },
        { "epoch", PZRL.Session.gameEpoch or "" },
        { "binding", PZRL.Session.bindingId or "" },
        { "rev", PZRL.Session.controlRevision },
        { "status", statusReason },
        { "paused", paused and "1" or "0" },
        -- BF-05: lets the host reconcile which commands the game consumed.
        { "watermark", tostring(PZRL.Mailbox.commandWatermark()) },
        { "active", Runtime._pending and Runtime._pending.id or "" },
    }

    if snapshot ~= nil then
        local vol = snapshot.volume
        pairs_[#pairs_ + 1] = { "kind", snapshot.kind or "item" }
        pairs_[#pairs_ + 1] = { "reach", PZRL.Session.reachable() and "1" or "0" }
        pairs_[#pairs_ + 1] = { "power_src", snapshot.powerSource or "unknown" }
        pairs_[#pairs_ + 1] = { "name", PZRL.Codec.sanitize(snapshot.name, 40) }
        pairs_[#pairs_ + 1] = { "on", snapshot.turnedOn and "1" or "0" }
        pairs_[#pairs_ + 1] = { "ch", tostring(math.floor(snapshot.channel or 0)) }
        -- Omitted entirely when the range could not be read, so the host can
        -- tell "unknown" from a real band.
        if snapshot.channelMin ~= nil and snapshot.channelMax ~= nil then
            pairs_[#pairs_ + 1] = { "chmin", tostring(math.floor(snapshot.channelMin)) }
            pairs_[#pairs_ + 1] = { "chmax", tostring(math.floor(snapshot.channelMax)) }
            pairs_[#pairs_ + 1] = { "chstep", tostring(PZRL.Device.CHANNEL_STEP) }
        end
        pairs_[#pairs_ + 1] = { "vol", string.format("%.3f", type(vol) == "number" and vol or 0) }
        if snapshot.battery ~= nil then
            pairs_[#pairs_ + 1] = { "batt", string.format("%.3f", snapshot.battery) }
        end
        pairs_[#pairs_ + 1] = { "prev", tostring(snapshot.presetRevision or 0) }
        pairs_[#pairs_ + 1] = { "presets", presetPairs(snapshot), 512 }
    end

    for index, result in ipairs(Runtime._results) do
        pairs_[#pairs_ + 1] = {
            "r" .. tostring(index),
            result.id .. ":" .. result.status .. ":" .. result.reason,
            160,
        }
    end

    PZRL.Mailbox.publishState(pairs_)
end

--[[ ------------------------------------------------------------------- tick ]]

function Runtime.onTick()
    -- No local player means the main menu or a load screen, not a paused game.
    -- Publishing nothing lets the host's staleness timer report "game not
    -- running", which is the truthful answer.
    if getSpecificPlayer(0) == nil then return end

    local stamp = now()
    local linked, reason = PZRL.Session.validate()
    local snapshot = nil
    if linked then
        snapshot = PZRL.Device.snapshot(PZRL.Session.item, PZRL.Session.kind)
        if snapshot == nil then
            PZRL.Session.clear("item_unreadable")
            linked, reason = false, "item_unreadable"
        else
            PZRL.Session.observeControlState(snapshot)
        end
    end

    if not linked and Runtime._pending ~= nil then
        PZRL.Device.cancelOwnedAction(Runtime._pending.owned)
        finishPending("cancelled", reason)
    end

    local paused = isGamePaused()

    if linked then
        resolvePending(snapshot, paused)

        -- At most one due operation per callback: a long stall must not turn
        -- into a burst of file I/O on the frame the game resumes.
        if stamp >= Runtime._nextCommandAt then
            Runtime._nextCommandAt = stamp + Runtime.COMMAND_INTERVAL_MS
            local fields = PZRL.Mailbox.pollCommand()
            if fields ~= nil then
                if paused then
                    recordResult(fields.id, "rejected", "paused")
                else
                    dispatch(fields)
                end
            end
        elseif stamp >= Runtime._nextStateAt then
            Runtime._nextStateAt = stamp + Runtime.STATE_INTERVAL_MS
            publish(snapshot, "linked", paused)
        end
        return
    end

    if stamp >= Runtime._nextStateAt then
        Runtime._nextStateAt = stamp + Runtime.STATE_INTERVAL_MS
        publish(snapshot, reason or "unlinked", paused)
    end
end

function Runtime.onGameStart()
    PZRL.Session.beginGame()
    PZRL.Mailbox.beginSession()
    Runtime._results = {}
    Runtime._pending = nil
    Runtime._nextCommandAt = 0
    Runtime._nextStateAt = 0
    if not PZRL.Session.modeSupported() then
        print("[PZRL] multiplayer or split-screen detected; external control stays disabled")
    end
    publish(nil, PZRL.Session.modeSupported() and "unlinked" or "unsupported_mode", false)
end

function Runtime.onPlayerDeath(player)
    if PZRL.Session.player == player then
        if Runtime._pending ~= nil then
            PZRL.Device.cancelOwnedAction(Runtime._pending.owned)
            finishPending("cancelled", "player_died")
        end
        PZRL.Session.clear("player_died")
    end
end

function Runtime.install()
    if Runtime._installed then return true end
    Events.OnTickEvenPaused.Add(Runtime.onTick)
    Events.OnGameStart.Add(Runtime.onGameStart)
    Events.OnPlayerDeath.Add(Runtime.onPlayerDeath)
    Runtime._installed = true
    return true
end

Runtime.install()

return Runtime
