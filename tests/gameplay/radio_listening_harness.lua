-- SPDX-License-Identifier: MIT

local SC = SurvivorCompanion
local Radio = SC.RadioListening
local originalUtil, originalRegistry, originalPeek =
    SC.GameplayUtil, SC.Registry, SC.Downtime.peek
local originalBaseLife, originalNavigation = SC.BaseLife, SC.Navigation
local originalSay, originalLastSpoken =
    SC.Dialogue.say, SC.Dialogue.lastSpokenAt
local checks, clock = 0, 100000
local function check(value, message)
    checks = checks + 1
    assert(value, "radio listening check " .. checks .. ": " .. message)
end

local room, upperRoom, squares = {}, {}, {}
local function square(x, y, z)
    z = z or 0
    local key = x .. ":" .. y .. ":" .. z
    if not squares[key] then
        squares[key] = { x = x, y = y, z = z, objects = {},
            room = z == 0 and room or upperRoom }
        squares[key].getRoom = function(self) return self.room end
    end
    return squares[key]
end

local receiver = { square = square(10, 10), on = false,
    power = 1, volume = 0, channel = 90000, sounds = {} }
local preset = { getFrequency = function() return 88000 end }
local presets = { getPresets = function()
    return { size = function() return 1 end,
        get = function() return preset end }
end }
local receiverData = {
    getIsTelevision = function() return false end,
    getIsBatteryPowered = function() return true end,
    getPower = function() return receiver.power end,
    getIsTurnedOn = function() return receiver.on end,
    setIsTurnedOn = function(_, value) receiver.on = value end,
    getDeviceVolume = function() return receiver.volume end,
    setDeviceVolume = function(_, value) receiver.volume = value end,
    getChannel = function() return receiver.channel end,
    setChannel = function(_, value) receiver.channel = value end,
    getDevicePresets = function() return presets end,
    playSoundSend = function(_, sound)
        receiver.sounds[#receiver.sounds + 1] = sound
    end,
}
function receiver:getDeviceData() return receiverData end
receiver.square.objects[1] = receiver
local chair = { square = square(10, 12) }
chair.square.objects[1] = chair
local actor = { square = square(10, 11), seated = false }
function actor:isSittingOnFurniture() return self.seated end
function actor:faceThisObject(object) self.faced = object end

local spoken, active = {}, nil
SC.Dialogue.say = function(_, topic)
    spoken[#spoken + 1] = topic
    return true
end
SC.Dialogue.lastSpokenAt = function() return -math.huge end
SC.Downtime.peek = function() return { active = active } end
SC.Registry = { living = function() return { actor } end }
SC.GameplayUtil = {
    call = function(object, method, ...)
        if not object or type(object[method]) ~= "function" then return nil, false end
        local ok, result = pcall(object[method], object, ...)
        return ok and result or nil, ok
    end,
    squareOf = function(value) return value and (value.square or value) end,
    position = function(value)
        local point = value and (value.square or value)
        return point and point.x, point and point.y, point and point.z
    end,
    gridSquare = function(x, y, z)
        return squares[x .. ":" .. y .. ":" .. z]
    end,
    squareObjects = function(value, callback)
        for _, object in ipairs(value.objects) do
            if callback(object) == false then break end
        end
    end,
    distance = function(a, b)
        local aa, bb = a.square or a, b.square or b
        return math.sqrt((aa.x - bb.x)^2 + (aa.y - bb.y)^2
            + (aa.z - bb.z)^2 * 9)
    end,
    directInteractionAccess = function(value, object)
        return value.square == object.square, { object.square }
    end,
    nowMs = function() return clock end,
}
local hooks = {
    seatingStatus = function(value)
        return value.seated and "furniture" or "standing"
    end,
    furnitureKind = function(value) return value == chair and "sit" or nil end,
    reserved = function() return false end,
    cooling = function() return false end,
    freeAccess = function() return false, { chair.square } end,
}

local setup = Radio.candidate(actor, {}, clock, hooks)
check(setup and setup.kind == "radio_setup" and setup.object == receiver,
    "an off radio with a nearby chair is selected")
check(not Radio.audible(receiver), "an off muted radio is not audible")
local requested
SC.Navigation = { requestAny = function(_, targets, _, options)
    requested = { targets = targets, options = options }
    return true, "moving"
end }
check(Radio.approach(actor, setup) and requested
        and requested.options.object == receiver,
    "the companion approaches the actual receiver")
actor.square = receiver.square
check(Radio.setup(actor, setup) and Radio.audible(receiver)
        and receiver.channel == 88000 and receiver.volume > 0
        and actor.faced == receiver,
    "using the radio powers it, chooses a non-team preset, unmutes and faces it")
check(spoken[1] == "downtime.radio.tune" and #receiver.sounds == 2,
    "radio setup speaks and makes native button and tuning sounds")
check(Radio.candidate(actor, {}, clock, hooks).kind == "sit",
    "a working radio makes the companion choose a nearby chair")
actor.square, actor.seated = chair.square, true
local listen = Radio.candidate(actor, {}, clock, hooks)
check(listen and listen.kind == "radio_listen" and listen.object == receiver,
    "a seated companion can listen to the nearby radio")
check(Radio.start(actor, listen, clock)
        and spoken[#spoken] == "downtime.radio.listen",
    "listening starts from the actual seated position")
active = listen
clock = clock + 15000
Radio.onDeviceText("broadcast-one", "", 10, 10, 0)
check(listen.lastBroadcastAt == clock
        and spoken[#spoken] == "downtime.radio.broadcast",
    "the actual receiver's broadcast prompts a comment")
local count = #spoken
Radio.onDeviceText("other-radio", "", 11, 10, 0)
check(#spoken == count, "another radio cannot trigger a listener reaction")
clock = clock + 1000
Radio.onDeviceText("broadcast-two", "", 10, 10, 0)
check(#spoken == count, "broadcast chatter is rate limited")
Radio.finish(actor, listen)
check(spoken[#spoken] == "downtime.radio.signoff",
    "a heard broadcast gets an honest signoff")
receiver.power = 0
check(not Radio.valid(actor, listen, true)
        and Radio.candidate(actor, {}, clock, hooks) == nil,
    "a dead battery cancels listening and prevents reselection")
receiver.power, receiver.on = 1, false
check(Radio.candidate(actor, {}, clock, hooks) == nil,
    "a seated companion does not operate an out-of-reach radio")

receiver.on, receiver.volume, receiver.channel = true, 0.35, 88000
receiver.square.objects, chair.square.objects = {}, {}
receiver.square, chair.square = square(10, 10, 1), square(10, 12, 1)
receiver.square.objects[1], chair.square.objects[1] = receiver, chair
actor.square, actor.seated = square(10, 11, 0), false
SC.BaseLife = {
    active = function() return true end,
    allowsFloorTransit = function() return true end,
    isInside = function() return true end,
}
local upstairs = Radio.candidate(actor, {}, clock, hooks)
check(upstairs and upstairs.kind == "radio_setup" and upstairs.crossFloor,
    "an upstairs receiver first routes through the camp stairs")
check(Radio.valid(actor, upstairs, false)
        and not Radio.valid(actor, upstairs, true),
    "the upstairs receiver cannot be operated from the lower floor")
check(Radio.approach(actor, upstairs) and requested.options.workCampOnly,
    "radio routing uses the camp floor transit contract")
actor.square = receiver.square
check(Radio.setup(actor, upstairs)
        and spoken[#spoken] == "downtime.radio.found"
        and Radio.candidate(actor, {}, clock, hooks).kind == "sit",
    "after taking stairs, the companion leaves the working set alone and sits")

SC.GameplayUtil, SC.Registry, SC.Downtime.peek =
    originalUtil, originalRegistry, originalPeek
SC.BaseLife, SC.Navigation = originalBaseLife, originalNavigation
SC.Dialogue.say, SC.Dialogue.lastSpokenAt =
    originalSay, originalLastSpoken
print("Radio listening harness PASS: " .. checks .. " checks")
