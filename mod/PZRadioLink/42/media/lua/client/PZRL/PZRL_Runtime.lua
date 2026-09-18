--[[
PZ Radio Link -- tick loop, command dispatch and state export.

One Events.OnTick handler. Command polling only runs while a radio is linked;
state export runs at a slower cadence regardless, so the host can show
"game running, nothing linked" without the mod scanning anything.

An accepted command is never reported as `applied` on the strength of having
been queued. The runtime records what the device should look like afterwards and
only reports success once it observes that state. If the deadline passes first
the result is `cancelled` (the device moved, or the action was interrupted) or
`unknown` (nothing observable changed) -- and the command is not retried.
]]

PZRL = PZRL or {}

local Runtime = {}
PZRL.Runtime = Runtime

Runtime.COMMAND_INTERVAL_TICKS = 15   -- ~4 Hz at 60 fps
Runtime.STATE_INTERVAL_TICKS = 30     -- ~2 Hz
Runtime.PENDING_TIMEOUT_MS = 4000
Runtime.RESULT_RETENTION = 6

Runtime._tick = 0
Runtime._installed = false
Runtime._pending = nil
Runtime._results = {}
Runtime._lastSnapshot = nil

local function now()
    return getTimestampMs()
end

-- One entry per command id, updated in place. Appending a second row when a
-- `pending` later becomes `applied` would halve the useful size of the buffer,
-- and a result could then be evicted before the page had read it -- so a
-- command would silently never report Done.
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

local function beginPending(id, kind, predicate)
    Runtime._pending = {
        id = id,
        kind = kind,
        predicate = predicate,
        deadline = now() + Runtime.PENDING_TIMEOUT_MS,
    }
    recordResult(id, "pending")
end

local function resolvePending(snapshot, paused)
    local pending = Runtime._pending
    if pending == nil then return end
    if snapshot ~= nil and pending.predicate(snapshot) then
        Runtime._pending = nil
        PZRL.Session.bumpRevision()
        recordResult(pending.id, "applied")
        return
    end
    -- The deadline is wall-clock, but ISTimedActionQueue does not advance while
    -- the game is paused. Without this, alt-tabbing right after pressing a
    -- button would time the command out and report a "cancelled" that never
    -- happened.
    if paused then
        pending.deadline = now() + Runtime.PENDING_TIMEOUT_MS
        return
    end
    if now() >= pending.deadline then
        Runtime._pending = nil
        -- stopOnRun = true on ISRadioAction, so an interrupted sprint lands here.
        recordResult(pending.id, "cancelled", "not_observed")
    end
end

--[[ --------------------------------------------------------------- commands ]]

local HANDLERS = {}

HANDLERS.set_power = function(fields, player, item)
    local desired = PZRL.Codec.boolean(fields, "value")
    if desired == nil then return false, "bad_value" end
    local accepted, reason = PZRL.Device.requestPower(player, item, desired)
    if not accepted then return false, reason end
    return true, nil, function(snap) return snap.turnedOn == desired end
end

HANDLERS.set_channel = function(fields, player, item)
    local channel = PZRL.Codec.integer(fields, "value")
    if channel == nil then return false, "bad_value" end
    local accepted, reason = PZRL.Device.requestChannel(player, item, channel)
    if not accepted then return false, reason end
    return true, nil, function(snap) return snap.channel == channel end
end

HANDLERS.set_volume = function(fields, player, item)
    local volume = PZRL.Codec.number(fields, "value")
    if volume == nil then return false, "bad_value" end
    local accepted, reason = PZRL.Device.requestVolume(player, item, volume)
    if not accepted then return false, reason end
    -- The volume bar quantises to its own step count, so an exact float match is
    -- the wrong postcondition; accept anything inside one coarse step.
    return true, nil, function(snap)
        return type(snap.volume) == "number" and math.abs(snap.volume - volume) <= 0.05
    end
end

HANDLERS.select_preset = function(fields, player, item)
    local index = PZRL.Codec.integer(fields, "index")
    if index == nil then return false, "bad_value" end
    local data = PZRL.Device.dataOf(item)
    if data == nil then return false, "unreadable" end
    local entry = PZRL.Device.presets(data)[index]
    local accepted, reason = PZRL.Device.requestPreset(player, item, index)
    if not accepted then return false, reason end
    local target = entry and entry.freq
    return true, nil, function(snap) return snap.channel == target end
end

HANDLERS.unlink = function()
    PZRL.Session.clear("unlinked_by_host")
    return false, "noop"
end

local function dispatch(fields)
    local id = fields.id
    if id == nil or id == "" then return end

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
    -- A placed radio stays linked when you walk away, but cannot be operated
    -- from a distance: we refuse rather than walking the survivor over to it.
    if fields.cmd ~= "unlink" and not PZRL.Session.reachable() then
        recordResult(id, "rejected", "too_far")
        return
    end

    local handler = HANDLERS[fields.cmd or ""]
    if handler == nil then
        recordResult(id, "rejected", "unknown_command")
        return
    end

    local accepted, failReason, predicate = handler(fields, PZRL.Session.player, PZRL.Session.item)
    if not accepted then
        if failReason == "noop" then
            PZRL.Session.bumpRevision()
            recordResult(id, "applied", "noop")
        else
            recordResult(id, "rejected", failReason)
        end
        return
    end
    beginPending(id, fields.cmd, predicate)
end

--[[ ------------------------------------------------------------------ state ]]

-- Entries are "<name>:<freq>" joined by '|'. The name has '|' stripped so it can
-- never split an entry, and the reader takes the LAST ':' so a name may keep its
-- own colons.
local function presetPairs(snapshot)
    local parts = {}
    for _, entry in ipairs(snapshot.presets or {}) do
        local name = string.gsub(PZRL.Codec.sanitize(entry.name, 24), "%|", "")
        if name == "" then name = "Preset" end
        parts[#parts + 1] = name .. ":" .. tostring(math.floor(entry.freq or 0))
    end
    return table.concat(parts, "|")
end

local function publish(snapshot, statusReason)
    local pairs_ = {
        { "proto", "1" },
        { "epoch", PZRL.Session.gameEpoch or "" },
        { "binding", PZRL.Session.bindingId or "" },
        { "rev", PZRL.Session.controlRevision },
        { "status", statusReason },
        { "paused", isGamePaused() and "1" or "0" },
    }

    if snapshot ~= nil then
        local vol = snapshot.volume
        pairs_[#pairs_ + 1] = { "kind", snapshot.kind or "item" }
        pairs_[#pairs_ + 1] = { "reach", PZRL.Session.reachable() and "1" or "0" }
        pairs_[#pairs_ + 1] = { "mains", snapshot.mains and "1" or "0" }
        pairs_[#pairs_ + 1] = { "name", PZRL.Codec.sanitize(snapshot.name, 40) }
        pairs_[#pairs_ + 1] = { "on", snapshot.turnedOn and "1" or "0" }
        pairs_[#pairs_ + 1] = { "ch", tostring(math.floor(snapshot.channel or 0)) }
        pairs_[#pairs_ + 1] = { "chmin", tostring(math.floor(snapshot.channelMin or 0)) }
        pairs_[#pairs_ + 1] = { "chmax", tostring(math.floor(snapshot.channelMax or 0)) }
        pairs_[#pairs_ + 1] = { "chstep", tostring(PZRL.Device.CHANNEL_STEP) }
        pairs_[#pairs_ + 1] = { "vol", string.format("%.3f", type(vol) == "number" and vol or 0) }
        pairs_[#pairs_ + 1] = { "batt", string.format("%.3f", snapshot.power or 0) }
        pairs_[#pairs_ + 1] = { "battery", snapshot.battery and "1" or "0" }
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
    Runtime._tick = Runtime._tick + 1

    -- No local player means the main menu or a load screen, not a paused game.
    -- Publishing nothing lets the host's own staleness timer report "game not
    -- running", which is the truthful answer.
    if getSpecificPlayer(0) == nil then return end

    local linked, reason = PZRL.Session.validate()
    local snapshot = nil
    if linked then
        snapshot = PZRL.Device.snapshot(PZRL.Session.item, PZRL.Session.kind)
        if snapshot == nil then
            PZRL.Session.clear("item_unreadable")
            linked, reason = false, "item_unreadable"
        else
            Runtime._lastSnapshot = snapshot
        end
    end

    if not linked and Runtime._pending ~= nil then
        recordResult(Runtime._pending.id, "cancelled", reason)
        Runtime._pending = nil
    end

    local paused = isGamePaused()

    if linked then
        resolvePending(snapshot, paused)

        -- A command that arrives while the game is paused is answered, not
        -- queued for unpause: ISTimedActionQueue does not advance while paused.
        if Runtime._tick % Runtime.COMMAND_INTERVAL_TICKS == 0 then
            local fields = PZRL.Mailbox.pollCommand()
            if fields ~= nil then
                if paused then
                    recordResult(fields.id, "rejected", "paused")
                else
                    dispatch(fields)
                end
            end
        end
    end

    if Runtime._tick % Runtime.STATE_INTERVAL_TICKS == 0 then
        publish(snapshot, linked and "linked" or (reason or "unlinked"))
    end
end

function Runtime.onGameStart()
    PZRL.Session.beginGame()
    PZRL.Mailbox.beginSession()
    Runtime._results = {}
    Runtime._pending = nil
    Runtime._lastSnapshot = nil
    if not PZRL.Session.modeSupported() then
        print("[PZRL] multiplayer or split-screen detected; external control stays disabled")
    end
    publish(nil, PZRL.Session.modeSupported() and "unlinked" or "unsupported_mode")
end

function Runtime.onPlayerDeath(player)
    if PZRL.Session.player == player then
        PZRL.Session.clear("player_died")
    end
end

function Runtime.install()
    if Runtime._installed then return true end
    -- OnTickEvenPaused, not OnTick. Project Zomboid pauses single-player when
    -- its window loses focus, and OnTick stops with the game loop -- so a player
    -- alt-tabbing to the browser would stop the state feed and the page would
    -- report "game not running" at exactly the moment they started looking at
    -- it. On this event the feed survives the pause and the page can say
    -- "paused" and keep showing live values. Commands are still refused while
    -- paused, because ISTimedActionQueue does not advance either.
    Events.OnTickEvenPaused.Add(Runtime.onTick)
    Events.OnGameStart.Add(Runtime.onGameStart)
    Events.OnPlayerDeath.Add(Runtime.onPlayerDeath)
    Runtime._installed = true
    return true
end

Runtime.install()

return Runtime
