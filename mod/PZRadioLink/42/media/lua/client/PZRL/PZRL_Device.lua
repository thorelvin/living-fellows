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
        -- A placed radio may run off mains or a generator, in which case
        -- getPower() is not a battery charge and must not be shown as one.
        local battery = data:getIsBatteryPowered() == true
        return {
            name       = Device.stableName(target, kind),
            kind       = kind,
            turnedOn   = data:getIsTurnedOn() == true,
            channel    = data:getChannel(),
            channelMin = lo,
            channelMax = hi,
            volume     = data:getDeviceVolume(),
            power      = data:getPower(),
            battery    = battery,
            mains      = (not battery) and data:canBePoweredHere() == true,
            presets    = Device.presets(data),
        }
    end)
    if not ok then return nil end
    return snap
end

local function queue(mode, player, item, secondary)
    local ok, err = pcall(function()
        ISTimedActionQueue.add(ISRadioAction:new(mode, player, item, secondary))
    end)
    if not ok then
        print("[PZRL] failed to queue " .. tostring(mode) .. ": " .. tostring(err))
        return false
    end
    return true
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

function Device.requestPower(player, item, desiredOn)
    local data = Device.dataOf(item)
    if data == nil then return false, "unreadable" end
    local isOn = (data:getIsTurnedOn() == true)
    if isOn == desiredOn then return false, "noop" end
    local ok, valid = pcall(function()
        return (data:getIsBatteryPowered() and data:getPower() > 0) or data:canBePoweredHere()
    end)
    if not ok then return false, "unreadable" end
    if valid ~= true then return false, "no_power" end
    if not queue("ToggleOnOff", player, item) then return false, "queue_failed" end
    return true, "queued"
end

function Device.requestChannel(player, item, channel)
    local data = Device.dataOf(item)
    if data == nil then return false, "unreadable" end
    if not Device.channelAllowed(data, channel) then return false, "channel_rejected" end
    local ok, ready = pcall(function()
        return data:getIsTurnedOn() and data:getPower() > 0
    end)
    if not ok then return false, "unreadable" end
    if ready ~= true then return false, "device_off" end
    if data:getChannel() == channel then return false, "noop" end
    if not queue("SetChannel", player, item, channel) then return false, "queue_failed" end
    return true, "queued"
end

function Device.requestVolume(player, item, volume)
    local data = Device.dataOf(item)
    if data == nil then return false, "unreadable" end
    if type(volume) ~= "number" or volume ~= volume then return false, "volume_rejected" end
    if volume < 0 or volume > 1 then return false, "volume_rejected" end
    local ok, ready = pcall(function()
        return data:getIsTurnedOn() and data:getPower() > 0
    end)
    if not ok then return false, "unreadable" end
    if ready ~= true then return false, "device_off" end
    if not queue("SetVolume", player, item, volume) then return false, "queue_failed" end
    return true, "queued"
end

-- Resolves a preset by index against the device's own list and tunes to its
-- frequency. The index is never trusted as a frequency, and the preset list is
-- never modified.
function Device.requestPreset(player, item, index)
    local data = Device.dataOf(item)
    if data == nil then return false, "unreadable" end
    if type(index) ~= "number" or math.floor(index) ~= index or index < 1 then
        return false, "preset_rejected"
    end
    local list = Device.presets(data)
    local entry = list[index]
    if entry == nil then return false, "preset_missing" end
    local freq = entry.freq
    if type(freq) ~= "number" then return false, "preset_missing" end
    local ok, ready = pcall(function()
        return data:getIsTurnedOn() and data:getPower() > 0
    end)
    if not ok then return false, "unreadable" end
    if ready ~= true then return false, "device_off" end
    if data:getChannel() == freq then return false, "noop" end
    if not queue("SetChannel", player, item, freq) then return false, "queue_failed" end
    return true, "queued"
end

return Device
