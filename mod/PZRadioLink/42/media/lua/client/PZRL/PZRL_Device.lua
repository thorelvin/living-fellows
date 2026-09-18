--[[
PZ Radio Link -- device adapter.

Every mutation goes through ISRadioAction + ISTimedActionQueue, which is the path
the vanilla radio window uses. Nothing here calls a DeviceData setter directly.

Verified against 42.20.4 (client/RadioCom/ISRadioAction.lua):

  ISRadioAction:new(mode, character, device, secondaryItem)
      maxTime = 30, stopOnWalk = false, stopOnRun = true

  isValidToggleOnOff : getIsBatteryPowered() and getPower()>0 or canBePoweredHere()
  isValidSetChannel  : getIsTurnedOn() and getPower()>0
  isValidSetVolume   : getIsTurnedOn() and getPower()>0

Two things the vanilla layer will NOT do for us:

  1. Its isValid* guards read
         if (not self.secondaryItem) and type(self.secondaryItem)~="number" then
     where the author meant `or`. A truthy non-number therefore passes the guard
     and reaches setChannel()/setDeviceVolume(). Every value is validated here
     before an action is ever constructed.
  2. stopOnRun = true, so a sprinting player cancels an action that was already
     accepted. That is reported as `cancelled`, never as `applied`.

Channel policy: vanilla only ever issues SetChannel with a saved preset's
frequency (RWMChannel:doTuneInButton). Free tuning exists in the preset editor,
whose slider is MHz with a 0.2 step -- 200 raw units. This adapter allows any
multiple of 200 inside the device's own range, which is the same set of
frequencies a player can reach, and never creates or edits a preset to get there.
]]

PZRL = PZRL or {}

local Device = {}
PZRL.Device = Device

Device.CHANNEL_STEP = 200
Device.MAX_PRESETS_EXPORTED = 12

-- Two kinds of device share one command path. A carried radio is an
-- InventoryItem; a placed one is an IsoRadio, which extends IsoWaveSignal and
-- so also carries DeviceData. ISRadioAction handles both -- its update() faces
-- the parent object when deviceData:isIsoDevice().
Device.ITEM = "item"
Device.WORLD = "world"

-- luautils.walkAdj treats the player as "already near enough, do not walk" when
-- both axis distances are <= 1.6 and the square is reachable. Reusing that exact
-- test means our idea of in-reach is identical to vanilla's.
Device.REACH = 1.6

function Device.kindOf(target)
    if target == nil then return nil end
    local ok, kind = pcall(function()
        if instanceof(target, "IsoRadio") then
            if target:getDeviceData() == nil then return nil end
            return Device.WORLD
        end
        local script = target:getScriptItem()
        if script == nil or not script:isItemType(ItemType.RADIO) then return nil end
        local data = target:getDeviceData()
        if data == nil then return nil end
        if data:getIsPortable() ~= true then return nil end
        return Device.ITEM
    end)
    if not ok then return nil end
    return kind
end

function Device.isSupported(target)
    return Device.kindOf(target) ~= nil
end

-- Possession, not proximity. RWMPanel:doWalkTo returns true immediately for an
-- InventoryItem, so a carried radio has no positional requirement; what matters
-- is that this is still the linked player's item.
function Device.heldBy(item, player)
    if item == nil or player == nil then return false end
    local ok, result = pcall(function()
        local container = item:getContainer()
        if container == nil then return false end
        return container:isInCharacterInventory(player) == true
    end)
    return ok and result == true
end

-- Does the binding still point at a device that exists? For a world object this
-- is separate from being able to reach it: walking away must not drop the link,
-- but the object being removed or its chunk unloading must.
function Device.stillPresent(target, kind)
    kind = kind or Device.kindOf(target)
    if kind == Device.ITEM then return true end
    if kind ~= Device.WORLD then return false end
    local ok, present = pcall(function()
        local square = target:getSquare()
        if square == nil then return false end
        local objects = square:getObjects()
        if objects == nil then return false end
        for i = 0, objects:size() - 1 do
            if objects:get(i) == target then return true end
        end
        return false
    end)
    return ok and present == true
end

-- Can the player act on it right now? A carried radio: possession. A placed
-- one: standing next to it. We deliberately do NOT queue a walk the way the
-- vanilla window does -- a button on a phone should never send the survivor
-- across the base while nobody is looking at the screen.
function Device.reachable(target, player, kind)
    kind = kind or Device.kindOf(target)
    if kind == Device.ITEM then return Device.heldBy(target, player) end
    if kind ~= Device.WORLD or player == nil then return false end
    local ok, near = pcall(function()
        local square = target:getSquare()
        local standing = player:getSquare()
        if square == nil or standing == nil then return false end
        square = luautils.getCorrectSquareForWall(player, square)
        if square == nil then return false end
        local dx = math.abs(square:getX() + 0.5 - player:getX())
        local dy = math.abs(square:getY() + 0.5 - player:getY())
        if dx > Device.REACH or dy > Device.REACH then return false end
        return standing:canReachTo(square) == true
    end)
    return ok and near == true
end

-- item:getName() on a radio includes its power state -- "ValuTech Walkie Talkie
-- (On)" -- so the faceplate label would change every time the radio is toggled,
-- and the codec strips the parentheses leaving a stray "On". The script item's
-- display name is the stable one.
function Device.stableName(target, kind)
    kind = kind or Device.kindOf(target)
    local ok, name = pcall(function()
        if kind == Device.WORLD then
            local data = target:getDeviceData()
            local device = data and data:getDeviceName()
            if type(device) == "string" and device ~= "" then return device end
            return target:getObjectName()
        end
        local script = target:getScriptItem()
        if script ~= nil then
            local display = script:getDisplayName()
            if type(display) == "string" and display ~= "" then return display end
        end
        return target:getName()
    end)
    if ok and type(name) == "string" and name ~= "" then return name end
    return "Radio"
end

function Device.dataOf(item)
    if item == nil then return nil end
    local ok, data = pcall(function() return item:getDeviceData() end)
    if not ok then return nil end
    return data
end

function Device.channelRange(data)
    local ok, lo, hi = pcall(function()
        return data:getMinChannelRange(), data:getMaxChannelRange()
    end)
    if not ok or type(lo) ~= "number" or type(hi) ~= "number" or hi <= lo then
        return nil, nil
    end
    return lo, hi
end

function Device.channelAllowed(data, channel)
    if type(channel) ~= "number" or math.floor(channel) ~= channel then return false end
    local lo, hi = Device.channelRange(data)
    if lo == nil then return false end
    if channel < lo or channel > hi then return false end
    return (channel % Device.CHANNEL_STEP) == 0
end

--[[
BF-10. A saved preset can sit off the 200-unit grid, and simply adding 200 to
88500 gives 88700 -- still off-grid, so channelAllowed() rejects it and the
nudge buttons do nothing. Step to the next or previous *legal grid point*
instead: from 88500, up is 88600 and down is 88400.

Returns nil when no legal point exists in that direction.
]]
function Device.nextGridChannel(data, from, direction)
    if type(from) ~= "number" then return nil end
    local lo, hi = Device.channelRange(data)
    if lo == nil then return nil end
    local step = Device.CHANNEL_STEP

    local target
    if direction > 0 then
        target = math.floor(from / step) * step + step
    else
        target = math.ceil(from / step) * step - step
    end

    -- Clamp to legal grid points inside the band, not to the raw endpoints,
    -- which may themselves be off-grid.
    local lowest = math.ceil(lo / step) * step
    local highest = math.floor(hi / step) * step
    if lowest > highest then return nil end
    if target < lowest then target = lowest end
    if target > highest then target = highest end
    if target == from then return nil end
    return target
end

function Device.presets(data)
    local out = {}
    local ok = pcall(function()
        local holder = data:getDevicePresets()
        if holder == nil then return end
        local list = holder:getPresets()
        if list == nil then return end
        local count = list:size()
        if count > Device.MAX_PRESETS_EXPORTED then count = Device.MAX_PRESETS_EXPORTED end
        for i = 0, count - 1 do
            local entry = list:get(i)
            if entry ~= nil then
                out[#out + 1] = { name = entry:getName(), freq = entry:getFrequency() }
            end
        end
    end)
    if not ok then return {} end
    return out
end

-- A single snapshot read. Returns nil if the device cannot be read at all, which
-- the caller must treat as identity uncertainty rather than as "radio is off".
function Device.snapshot(target, kind)
    local data = Device.dataOf(target)
    if data == nil then return nil end
    kind = kind or Device.kindOf(target)
    local ok, snap = pcall(function()
        local lo, hi = Device.channelRange(data)
        --[[
        BF-10. getPower() is a battery charge only on a battery-powered set.
        A non-battery device without mains power was previously shown as
        "BATT 0%", which is fiction. The four states are modelled explicitly
        and an unreadable one stays "unknown" rather than defaulting to
        something plausible.
        ]]
        local battery = data:getIsBatteryPowered() == true
        local source, charge
        if battery then
            source, charge = "battery", data:getPower()
        elseif data:canBePoweredHere() == true then
            source, charge = "mains", nil
        else
            source, charge = "unpowered", nil
        end

        return {
            name       = Device.stableName(target, kind),
            kind       = kind,
            turnedOn   = data:getIsTurnedOn() == true,
            channel    = data:getChannel(),
            -- nil when the range could not be read. Never exported as 0..0,
            -- which would look like an authoritative empty band.
            channelMin = lo,
            channelMax = hi,
            volume     = data:getDeviceVolume(),
            powerSource = source,
            battery    = charge,
            presets    = Device.presets(data),
            presetRevision = Device.presetRevision(data),
        }
    end)
    if not ok then return nil end
    if snap ~= nil and snap.powerSource == nil then snap.powerSource = "unknown" end
    return snap
end

--[[
BF-04. Preset selection by index alone tunes "whatever now occupies slot 3".
A cheap revision over the list lets a command name the list it was composed
against, so a reordered or edited list produces stale_preset rather than a
wrong frequency.
]]
function Device.presetRevision(data)
    local list = Device.presets(data)
    local acc = #list
    for index, entry in ipairs(list) do
        acc = (acc * 31 + (tonumber(entry.freq) or 0) + index) % 4294967296
    end
    return acc
end

--[[
BF-03. The old code threw the action reference away, so "cancelled" was really
just "four seconds passed" -- while the action sat in the queue and could still
execute afterwards. Now every request keeps its action and observes its real
lifecycle.

Per-instance overrides rather than a global patch: assigning a function to the
action table shadows the class method for that one object, so no other radio
action in the game is affected and no shipped file is touched. The vanilla
implementations are captured first and still do the work.

The override points are the mode functions (performToggleOnOff and friends),
not perform() itself, so ISRadioAction's own completion bookkeeping still runs.

Returns an `owned` handle:
  started    the action left the queue and began
  performed  the mode function ran to completion
  stopped    the action was stopped (sprint, cancel, queue clear)
  invalidated  isValid() refused it at the execution boundary
  noop       the desired state already held, so nothing was mutated
]]
function Device.beginOwnedAction(mode, player, item, secondary, options)
    options = options or {}
    local owned = {
        mode = mode, started = false, performed = false,
        stopped = false, invalidated = false, noop = false,
        queuedAt = getTimestampMs(), startedAt = nil,
    }

    local ok, err = pcall(function()
        local action = ISRadioAction:new(mode, player, item, secondary)

        local baseIsValid = action.isValid
        local baseStart = action.start
        local baseStop = action.stop
        local baseMode = action["perform" .. mode]

        action.isValid = function(self)
            -- Preconditions are re-proved where the engine actually asks,
            -- which is the moment before execution, not when we queued.
            if options.revalidate and options.revalidate() ~= true then
                owned.invalidated = true
                return false
            end
            return baseIsValid(self)
        end

        action.start = function(self)
            owned.started = true
            owned.startedAt = getTimestampMs()
            return baseStart(self)
        end

        action.stop = function(self)
            owned.stopped = true
            return baseStop(self)
        end

        if baseMode ~= nil then
            action["perform" .. mode] = function(self)
                -- Desired-state commands re-read immediately before mutating.
                -- Vanilla only exposes a toggle, so a power request whose state
                -- changed in the meantime would otherwise invert it.
                if options.alreadySatisfied and options.alreadySatisfied() == true then
                    owned.noop = true
                    owned.performed = true
                    return
                end
                baseMode(self)
                owned.performed = true
            end
        end

        owned.action = action
        ISTimedActionQueue.add(action)
    end)

    if not ok then
        print("[PZRL] failed to queue " .. tostring(mode) .. ": " .. tostring(err))
        return nil
    end
    return owned
end

-- Stops only our own action. Never clears the player's queue.
function Device.cancelOwnedAction(owned)
    if owned == nil or owned.action == nil then return false end
    local ok = pcall(function()
        if owned.action.forceStop then
            owned.action:forceStop()
        elseif owned.action.stop then
            owned.action:stop()
        end
    end)
    return ok
end

--[[
Each request returns (accepted, reason). `accepted` means an action was queued,
never that the change happened -- the runtime confirms `applied` by observing the
device afterwards.

A request whose target already equals the current state returns
(false, "noop"), which the runtime reports as `applied` without queueing work.
This matters for set_power: vanilla only exposes a toggle, so issuing it against
an already-correct state would invert it.
]]

-- The protocol carries volume to three decimals and DeviceData stores the float
-- it is given, so a completed SetVolume reads back as what we sent. Half the
-- protocol precision is the right window. The old 0.05 was wide enough that
-- changing 0.30 to 0.34 matched the *unchanged* 0.30 and reported success.
Device.VOLUME_EPSILON = 0.0005

local function powered(data)
    local ok, ready = pcall(function()
        return data:getIsTurnedOn() and data:getPower() > 0
    end)
    if not ok then return nil end
    return ready == true
end

function Device.requestPower(player, item, desiredOn, revalidate)
    local data = Device.dataOf(item)
    if data == nil then return nil, "unreadable" end
    if (data:getIsTurnedOn() == true) == desiredOn then return nil, "noop" end
    local ok, valid = pcall(function()
        return (data:getIsBatteryPowered() and data:getPower() > 0) or data:canBePoweredHere()
    end)
    if not ok then return nil, "unreadable" end
    if valid ~= true then return nil, "no_power" end

    local owned = Device.beginOwnedAction("ToggleOnOff", player, item, nil, {
        revalidate = revalidate,
        -- Re-read at the execution boundary: if the player already flipped it
        -- by hand, completing as a no-op is correct and toggling is not.
        alreadySatisfied = function()
            return (data:getIsTurnedOn() == true) == desiredOn
        end,
    })
    if owned == nil then return nil, "queue_failed" end
    return owned, "queued"
end

function Device.requestChannel(player, item, channel, revalidate)
    local data = Device.dataOf(item)
    if data == nil then return nil, "unreadable" end
    if not Device.channelAllowed(data, channel) then return nil, "channel_rejected" end
    local ready = powered(data)
    if ready == nil then return nil, "unreadable" end
    if not ready then return nil, "device_off" end
    if data:getChannel() == channel then return nil, "noop" end

    local owned = Device.beginOwnedAction("SetChannel", player, item, channel, {
        revalidate = revalidate,
        alreadySatisfied = function() return data:getChannel() == channel end,
    })
    if owned == nil then return nil, "queue_failed" end
    return owned, "queued"
end

function Device.requestVolume(player, item, volume, revalidate)
    local data = Device.dataOf(item)
    if data == nil then return nil, "unreadable" end
    if type(volume) ~= "number" or volume ~= volume then return nil, "volume_rejected" end
    if volume < 0 or volume > 1 then return nil, "volume_rejected" end
    local ready = powered(data)
    if ready == nil then return nil, "unreadable" end
    if not ready then return nil, "device_off" end

    local owned = Device.beginOwnedAction("SetVolume", player, item, volume, {
        revalidate = revalidate,
        alreadySatisfied = function()
            local current = data:getDeviceVolume()
            return type(current) == "number"
                and math.abs(current - volume) <= Device.VOLUME_EPSILON
        end,
    })
    if owned == nil then return nil, "queue_failed" end
    return owned, "queued"
end

--[[
Resolves a preset against the device's own list and tunes to its frequency. The
index is never trusted as a frequency, and the list is never modified.

BF-04: the caller passes the frequency and list revision it displayed. If the
list changed between render and click, this refuses rather than tuning whatever
now sits at that index.
]]
function Device.requestPreset(player, item, index, expectedFreq, expectedRevision, revalidate)
    local data = Device.dataOf(item)
    if data == nil then return nil, "unreadable" end
    if type(index) ~= "number" or math.floor(index) ~= index or index < 1 then
        return nil, "preset_rejected"
    end
    if expectedRevision ~= nil and Device.presetRevision(data) ~= expectedRevision then
        return nil, "stale_preset"
    end
    local entry = Device.presets(data)[index]
    if entry == nil or type(entry.freq) ~= "number" then return nil, "preset_missing" end
    if expectedFreq ~= nil and entry.freq ~= expectedFreq then return nil, "stale_preset" end

    local freq = entry.freq
    local ready = powered(data)
    if ready == nil then return nil, "unreadable" end
    if not ready then return nil, "device_off" end
    if data:getChannel() == freq then return nil, "noop" end

    local owned = Device.beginOwnedAction("SetChannel", player, item, freq, {
        revalidate = revalidate,
        alreadySatisfied = function() return data:getChannel() == freq end,
    })
    if owned == nil then return nil, "queue_failed" end
    return owned, "queued"
end

return Device
