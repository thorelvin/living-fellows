-- SPDX-License-Identifier: MIT

local SC = SurvivorCompanion
local Radio = SC.OddballDistressRadio
local channel = 90000
local delivered = true
local deferred = false
local queued
local transmissions = {}
local annotations = {}

local function data()
    return {
        on = true, channel = channel, power = 1, volume = 0.8,
        twoWay = true, range = 100,
        getIsPortable = function() return true end,
        getIsTwoWay = function(self) return self.twoWay end,
        getIsTurnedOn = function(self) return self.on end,
        getHasBattery = function() return true end,
        getPower = function(self) return self.power end,
        getDeviceVolume = function(self) return self.volume end,
        getTransmitRange = function(self) return self.range end,
        getChannel = function(self) return self.channel end,
        getMicIsMuted = function() return false end,
        isNoTransmit = function() return false end,
    }
end

local function person(x, y)
    local inventory = {}
    local device = data()
    local radio = {
        getContainer = function() return inventory end,
        getDeviceData = function() return device end,
    }
    local actor = {
        x = x, y = y, z = 0, radio = radio, device = device,
        getInventory = function() return inventory end,
        getEquipedRadio = function(self) return self.radio end,
        getPrimaryHandItem = function(self) return self.radio end,
        getSecondaryHandItem = function() return nil end,
        getClothingItem_Back = function() return nil end,
        getX = function(self) return self.x end,
        getY = function(self) return self.y end,
        getZ = function(self) return self.z end,
        setHaloNote = function(self, note) self.note = note end,
    }
    return actor
end

local player = person(100, 100)
local survivor = person(120, 100)
local group = {
    id = "eli-test", name = "Eli Rourke", lifecycle = "settled",
    members = { { actorId = 5 } },
    oddball = {
        id = "garage_rescue_eli_rourke",
        site = { spawn = { x = 120, y = 100, z = 0 } },
    },
}
local offered, answered = 0, 0
SC.GameplayUtil = {
    call = function(object, method, ...)
        local methodValue = object and object[method]
        if type(methodValue) ~= "function" then return nil, false end
        return methodValue(object, ...), true
    end,
    instanceOf = function(object, kind)
        return kind == "Radio" and object == player.radio
            or kind == "Radio" and object == survivor.radio
    end,
    position = function(object) return object.x, object.y, object.z end,
}
SC.Registry = { byId = function(id)
    return id == 5 and { actor = survivor } or nil
end }
SC.Factions = {
    list = function() return { group } end,
    group = function(id) return id == group.id and group or nil end,
}
SC.FactionLife = {
    addMapAnnotation = function(label, x, y)
        annotations[label] = { x = x, y = y }
        return true
    end,
    removeMapAnnotation = function(label)
        annotations[label] = nil
        return true
    end,
}
SC.OddballGarageRescue = {
    radioOffer = function()
        offered = offered + 1
        return { frequency = channel, text = "Eli: Garage. Leg's broken.",
            x = 120, y = 100, z = 0, replyLabel = "Eli Rourke" }
    end,
    radioRespond = function()
        answered = answered + 1
        return true, "answered", "Eli: Marked the garage. Bring a splint."
    end,
}
Events = { OnDeviceText = {
    callbacks = {},
    Add = function(callback)
        Events.OnDeviceText.callbacks[#Events.OnDeviceText.callbacks + 1] = callback
    end,
    Remove = function(callback)
        for i, item in ipairs(Events.OnDeviceText.callbacks) do
            if item == callback then table.remove(Events.OnDeviceText.callbacks, i) break end
        end
    end,
} }
getZomboidRadio = function()
    return { SendTransmission = function(_self, x, y, frequency,
        message, guid, codes)
        transmissions[#transmissions + 1] = { x = x, y = y,
            frequency = frequency, message = message }
        if delivered then
            local receiver = x == 120 and player.radio or survivor.radio
            local function dispatch(xValue, yValue, device)
                for _, callback in ipairs(Events.OnDeviceText.callbacks) do
                    callback(guid, codes, xValue, yValue, 0, message, device)
                end
            end
            if deferred then
                queued = dispatch
            else
                dispatch(x, y, receiver)
            end
        end
    end }
end

assert(Radio.install() == true)
player.device.channel = 88000
assert(Radio.pulse(group, player, 1000) == false and offered == 0,
    "wrong channel must not consume a distress offer")
player.device.channel = channel
player.device.volume = 0
assert(Radio.pulse(group, player, 1500) == false and offered == 0,
    "silent receiver must not consume a distress offer")
player.device.volume = 0.8
-- The game skips a listener within three tiles of the sender and scrambles
-- the text past 90% of the sender's range; neither can ever be heard intact.
player.x = 117
assert(Radio.pulse(group, player, 1600) == false and offered == 0,
    "a listener within three tiles must not consume a distress offer")
player.x = 29
assert(Radio.pulse(group, player, 1700) == false and offered == 0,
    "a listener past 90% of the range must not consume a distress offer")
player.x = 100
-- Listening needs only a powered portable radio on 90 MHz, as in the game.
player.device.twoWay, player.device.range = false, 0
delivered = false
assert(Radio.pulse(group, player, 2000) == false
    and group.oddball.radioHeard ~= true,
    "a dispatch without native receiver text cannot unlock the reply")
delivered = true
deferred = true
assert(Radio.pulse(group, player, 8000) == false
    and group.oddball.radioHeard ~= true and queued ~= nil,
    "a delayed native callback must not mark the call as heard prematurely")
queued(121, 100, player.radio)
assert(Radio.pulse(group, player, 8001) == false
    and group.oddball.radioHeard ~= true,
    "a matching payload from different source coordinates is ignored")
queued(-1, -1, survivor.radio)
assert(Radio.pulse(group, player, 8002) == false
    and group.oddball.radioHeard ~= true,
    "a native callback for the wrong receiving device is ignored")
queued(-1, -1, player.radio)
assert(Radio.pulse(group, player, 8003) == true
    and group.oddball.radioHeard == true,
    "the delayed exact receiver hears the call on a receive-only radio")
assert(#Radio.replyOptions(player) == 0,
    "a receive-only radio hears the call but cannot offer a reply")
player.device.twoWay, player.device.range = true, 100
assert(#Radio.replyOptions(player) == 1,
    "a two-way radio offers exactly one reply")
deferred = false
queued = nil
player.device.on = false
local anyMarker = false
for _ in pairs(annotations) do anyMarker = true end
assert(Radio.answer(group.id, player) == false and answered == 0
    and not anyMarker,
    "a dead radio must not mark the map")
player.device.on = true
survivor.device.volume = 0
assert(Radio.answer(group.id, player) == false and answered == 0
    and not anyMarker,
    "a silent survivor radio cannot acknowledge the reply")
survivor.device.volume = 0.8
assert(Radio.answer(group.id, player) == true and answered == 1
    and annotations["[LF] Eli Rourke rescue, 90 MHz"].x == 120
    and #Radio.replyOptions(player) == 0,
    "real reply records exactly one map marker")
assert(#transmissions >= 3
    and transmissions[#transmissions].frequency == channel,
    "native radio dispatch carries the answer on 90 MHz")
Radio.remove()
print("Oddball distress radio checks passed")
