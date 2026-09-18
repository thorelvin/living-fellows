--[[
PZ Radio Link -- session and item binding.

Everything here is in-memory and session-local. Nothing is written to the save,
no ModData is attached to the radio, and no custom item type exists. Reloading a
save, dying, or entering the main menu therefore invalidates the link implicitly;
the explicit invalidation below exists so the host learns about it promptly
rather than by timeout.

Identity is the item reference itself, not its name, type or channel. Two
identical radios in the same bag are distinguishable because they are two
different Lua references to two different Java objects.
]]

PZRL = PZRL or {}

local Session = {}
PZRL.Session = Session

Session.gameEpoch = nil
Session.bindingId = nil
Session.item = nil
Session.player = nil
Session.controlRevision = 0
Session.lastReason = "unlinked"

local bindingCounter = 0

local function newEpoch()
    return "g" .. tostring(getTimestampMs())
end

function Session.beginGame()
    Session.gameEpoch = newEpoch()
    Session.clear("session_start")
    bindingCounter = 0
end

function Session.endGame()
    Session.gameEpoch = nil
    Session.clear("session_end")
end

-- Single-player only, exactly as the product boundary requires. Split-screen is
-- a real case, not a theoretical one: vanilla's own OnDeviceText handler loops
-- over four local players.
function Session.modeSupported()
    local ok, supported = pcall(function()
        if isClient() or isServer() then return false end
        if getNumActivePlayers() > 1 then return false end
        return true
    end)
    return ok and supported == true
end

function Session.bind(player, item)
    if not Session.modeSupported() then return false, "unsupported_mode" end
    if player == nil or item == nil then return false, "no_target" end
    local kind = PZRL.Device.kindOf(item)
    if kind == nil then return false, "unsupported_item" end
    -- Linking requires being able to act on it; staying linked does not.
    if not PZRL.Device.reachable(item, player, kind) then
        return false, kind == PZRL.Device.WORLD and "too_far" or "not_held"
    end
    bindingCounter = bindingCounter + 1
    Session.player = player
    Session.item = item
    Session.kind = kind
    Session.bindingId = "b" .. tostring(bindingCounter)
    Session.controlRevision = 1
    Session.lastReason = "linked"
    return true, Session.bindingId
end

function Session.clear(reason)
    Session.item = nil
    Session.player = nil
    Session.kind = nil
    Session.bindingId = nil
    Session.controlRevision = 0
    Session.lastReason = reason or "unlinked"
end

function Session.linked()
    return Session.bindingId ~= nil and Session.item ~= nil
end

function Session.isBoundTo(item)
    return Session.linked() and Session.item == item
end

function Session.bumpRevision()
    Session.controlRevision = Session.controlRevision + 1
end

--[[
BF-04. The revision previously advanced only when a remote command succeeded,
so a player turning the dial in game left it unchanged and a phone request
composed against the old reading still looked current.

It now tracks the controllable state -- power, channel, volume and the preset
list -- and deliberately ignores battery drain and heartbeats, which would
otherwise invalidate a user's in-flight edit for no reason.
]]
function Session.observeControlState(snapshot)
    if snapshot == nil then
        Session._controlKey = nil
        return
    end
    local key = table.concat({
        snapshot.turnedOn and "1" or "0",
        tostring(snapshot.channel or ""),
        string.format("%.3f", type(snapshot.volume) == "number" and snapshot.volume or 0),
        tostring(snapshot.presetRevision or 0),
    }, "|")
    if Session._controlKey ~= nil and Session._controlKey ~= key then
        Session.controlRevision = Session.controlRevision + 1
    end
    Session._controlKey = key
end

-- Re-proves the binding from scratch every time it is asked. A linked but
-- inaccessible device is dropped, never silently replaced by a similar item.
-- Returns (ok, reason).
function Session.validate()
    if not Session.linked() then return false, Session.lastReason end
    if not Session.modeSupported() then
        Session.clear("unsupported_mode")
        return false, "unsupported_mode"
    end
    local player = Session.player
    local alive = pcall(function() return player:isDead() end) and (not player:isDead())
    if not alive then
        Session.clear("player_gone")
        return false, "player_gone"
    end
    if getSpecificPlayer(0) ~= player then
        Session.clear("player_changed")
        return false, "player_changed"
    end
    if PZRL.Device.kindOf(Session.item) ~= Session.kind then
        Session.clear("item_invalid")
        return false, "item_invalid"
    end

    if Session.kind == PZRL.Device.WORLD then
        -- Distance is NOT an invalidation for a placed radio: you are meant to
        -- walk away from it and come back. Only the object ceasing to exist --
        -- picked up, destroyed, or its chunk unloaded -- drops the binding.
        if not PZRL.Device.stillPresent(Session.item, Session.kind) then
            Session.clear("object_gone")
            return false, "object_gone"
        end
    elseif not PZRL.Device.heldBy(Session.item, player) then
        Session.clear("item_lost")
        return false, "item_lost"
    end

    return true, "linked"
end

-- Separate from validate(): the link is intact but commands may still be
-- refused because the player has walked away from a placed radio.
function Session.reachable()
    if not Session.linked() then return false end
    return PZRL.Device.reachable(Session.item, Session.player, Session.kind)
end

return Session
