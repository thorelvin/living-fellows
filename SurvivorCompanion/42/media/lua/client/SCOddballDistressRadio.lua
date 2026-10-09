-- SPDX-License-Identifier: MIT
-- Two authored rescue calls on the ordinary 90 MHz radio channel. The native
-- radio system delivers the text; this module only offers an answer after the
-- player's actual tuned receiver has heard it.

local SC = SurvivorCompanion
SC.OddballDistressRadio = SC.OddballDistressRadio or {}
local Radio = SC.OddballDistressRadio

local CHANNEL = 90000
local rescueModules = {
    garage_rescue_eli_rourke = "OddballGarageRescue",
    radio_rescue_nate_duvall = "OddballDehydrated",
}
local pending
local hooked = false

local function U() return SC.GameplayUtil end

local function number(value)
    if type(value) == "number" then return value end
    if type(value) == "string" then return tonumber(value) end
    return nil
end

local function call(object, method, ...)
    return object and select(1, U().call(object, method, ...)) or nil
end

local function actorFor(group)
    local member = group and group.members and group.members[1]
    local record = member and member.actorId and SC.Registry
        and SC.Registry.byId(member.actorId) or nil
    return record and record.actor or nil
end

local function equippedRadio(actor, transmit)
    if not actor then return nil end
    local inventory = call(actor, "getInventory")
    local radio = call(actor, "getEquipedRadio")
    local primary = call(actor, "getPrimaryHandItem")
    local secondary = call(actor, "getSecondaryHandItem")
    local back = call(actor, "getClothingItem_Back")
    if not radio or radio ~= primary and radio ~= secondary and radio ~= back
        or call(radio, "getContainer") ~= inventory then return nil end
    if not U().instanceOf(radio, "Radio") then return nil end
    local data = call(radio, "getDeviceData")
    -- ZomboidRadio.DistributeToPlayer hands a call to any portable radio that
    -- is on, tuned and audible; only answering needs a two-way set.
    if not data or call(data, "getIsPortable") ~= true
        or call(data, "getIsTurnedOn") ~= true
        or call(data, "getHasBattery") ~= true
        or (number(call(data, "getPower")) or 0) <= 0
        or number(call(data, "getChannel")) ~= CHANNEL
        or not transmit and ((number(call(data, "getDeviceVolume")) or 0) <= 0
            or call(data, "isPlayingMedia") == true
            or call(data, "isNoTransmit") == true)
        or transmit and (call(data, "getIsTwoWay") ~= true
            or (number(call(data, "getTransmitRange")) or 0) <= 0
            or call(data, "getMicIsMuted") == true
            or call(data, "isNoTransmit") == true) then
        return nil
    end
    return radio, data
end

local function inRange(a, b, range)
    local ax, ay = U().position(a)
    local bx, by = U().position(b)
    if not ax or not bx then return false end
    local dx, dy = ax - bx, ay - by
    return dx * dx + dy * dy <= range * range
end

-- The native delivery rule, so a call is only sent when it can arrive intact:
-- whole-tile Euclidean distance above three tiles, and no farther than 90% of
-- the sender's range, past which the text is scrambled and can never match.
local function deliverable(source, listener, range)
    local sx, sy = U().position(source)
    local lx, ly = U().position(listener)
    if not sx or not lx or not range or range <= 0 then return false end
    local dx = math.floor(lx) - math.floor(sx)
    local dy = math.floor(ly) - math.floor(sy)
    local distance = math.floor(math.sqrt(dx * dx + dy * dy))
    return distance > 3 and distance < range and distance <= range * 0.9
end

local function send(source, data, textValue, guid, code)
    if type(getZomboidRadio) ~= "function" then
        return false, "native_radio_unavailable"
    end
    local api = getZomboidRadio()
    if not api then return false, "native_radio_unavailable" end
    local x, y = U().position(source)
    if not x or not y then return false, "radio_source_unavailable" end
    local range = math.floor(number(call(data, "getTransmitRange")) or 0)
    if range <= 0 then return false, "radio_range_unavailable" end
    local okay, failure = pcall(function()
        api:SendTransmission(math.floor(x), math.floor(y), CHANNEL,
            textValue, guid, code, 0.83, 0.89, 0.73, range, false)
    end)
    return okay, okay and "transmitted" or tostring(failure)
end

function Radio.onDeviceText(guid, codes, x, y, _z, message, device)
    local expected = pending
    if not expected or expected.guid ~= tostring(guid)
        or expected.code ~= tostring(codes)
        or expected.text ~= tostring(message) then return end
    -- OnDeviceText's vanilla Lua contract has six arguments. Some native
    -- contexts also pass the receiving device as a seventh; use that exact
    -- identity when available, otherwise verify the player's equipped radio
    -- still meets the same channel, power and range checks.
    if device ~= nil then
        if expected.receiver ~= device then return end
        -- Radio.AddDeviceText emits -1/-1/-1 for an equipped receiver.
        if not ((number(x) == -1 and number(y) == -1)
            or (expected.x == number(x) and expected.y == number(y))) then
            return
        end
    elseif expected.x ~= number(x) or expected.y ~= number(y)
        or equippedRadio(expected.player, false) ~= expected.receiver
        or not inRange(expected.source, expected.player, expected.range) then
        return
    end
    expected.received = true
end

local function commitReceipt(expected)
    local story = expected.group and expected.group.oddball
    if not story or story.radioAnswered == true then return false end
    story.radioCallSerial = expected.serial
    story.radioHeard = true
    story.radioReplyLabel = expected.label
    story.radioSourceX = expected.x
    story.radioSourceY = expected.y
    story.radioSourceZ = expected.z
    U().call(expected.player, "setHaloNote", expected.text)
    return true
end

function Radio.pulse(group, player, current)
    if not hooked and not Radio.install() then
        return false, "radio_event_unavailable"
    end
    current = number(current) or U().nowMs()
    if pending then
        local expected = pending
        if expected.received then
            pending = nil
            return commitReceipt(expected), "rescue_call_received"
        end
        if current - expected.sentAt < 5000 then
            return false, "radio_delivery_pending"
        end
        pending = nil
    end
    local story = group and group.oddball
    local moduleName = story and rescueModules[story.id]
    local behavior = moduleName and SC[moduleName]
    if not behavior or type(behavior.radioOffer) ~= "function"
        or not player or not actorFor(group) or story.radioAnswered == true then
        return false, "no_rescue_call"
    end
    local source = actorFor(group)
    local receiver = equippedRadio(player, false)
    local sender, data = equippedRadio(source, true)
    if not receiver or not sender
        or not deliverable(source, player,
            number(call(data, "getTransmitRange")) or 0) then
        return false, "radio_endpoints_unavailable"
    end
    local okay, offer = pcall(behavior.radioOffer, group, player, current)
    if not okay or type(offer) ~= "table" or not offer.text
        or number(offer.frequency) ~= CHANNEL then
        return false, "no_call_due"
    end
    local serial = (number(story.radioCallSerial) or 0) + 1
    local message = tostring(offer.text)
    local x, y, z = U().position(source)
    local expected = {
        group = group, player = player, source = source,
        receiver = receiver, text = message,
        guid = "LF-RESCUE-" .. tostring(group.id),
        code = "CALL-" .. tostring(serial), received = false,
        serial = serial, label = tostring(offer.replyLabel or group.name or "survivor"),
        x = math.floor(number(x) or 0), y = math.floor(number(y) or 0),
        z = math.floor(number(z) or 0),
        range = number(call(data, "getTransmitRange")) or 0,
        sentAt = current,
    }
    pending = expected
    local sent, reason = send(source, data, message, expected.guid, expected.code)
    if not sent then
        pending = nil
        return false, reason
    end
    if not expected.received then return false, "radio_delivery_pending" end
    pending = nil
    return commitReceipt(expected), "rescue_call_received"
end

function Radio.replyOptions(player)
    if not equippedRadio(player, true) then return {} end
    local options = {}
    for _, group in ipairs(SC.Factions and SC.Factions.list(false) or {}) do
        local story = group.oddball
        if story and rescueModules[story.id] and story.radioHeard == true
            and story.radioAnswered ~= true and group.lifecycle ~= "destroyed"
            and actorFor(group) then
            options[#options + 1] = {
                groupId = group.id,
                label = "Reply to " .. tostring(story.radioReplyLabel
                    or group.name or "distress call") .. " on 90 MHz",
            }
        end
    end
    return options
end

function Radio.answer(groupId, player)
    local group = SC.Factions and SC.Factions.group(groupId)
    local story = group and group.oddball
    local moduleName = story and rescueModules[story.id]
    local behavior = moduleName and SC[moduleName]
    if not behavior or type(behavior.radioRespond) ~= "function"
        or story.radioHeard ~= true or story.radioAnswered == true then
        return false, "rescue_call_unavailable"
    end
    local source, data = equippedRadio(player, true)
    local survivor = actorFor(group)
    local receiver, receiverData = equippedRadio(survivor, false)
    if not source or not receiver or not inRange(player, survivor,
        number(call(data, "getTransmitRange")) or 0)
        or not inRange(player, survivor,
            number(call(receiverData, "getTransmitRange")) or 0) then
        return false, "radios_out_of_range"
    end
    local marker = "[LF] " .. tostring(group.name or "Rescue")
        .. " rescue, 90 MHz"
    local life = SC.FactionLife
    if not life or type(life.addMapAnnotation) ~= "function" then
        return false, "map_symbols_unavailable"
    end
    local marked, markReason = life.addMapAnnotation(marker,
        story.radioSourceX or story.site.spawn.x,
        story.radioSourceY or story.site.spawn.y,
        { 0.35, 0.8, 0.95, 1.0 })
    if marked ~= true then return false, markReason end
    local textValue = "I hear you. I'm coming. Mark your location."
    local sent, reason = send(player, data, textValue,
        "LF-RESCUE-" .. tostring(group.id), "REPLY")
    if not sent then
        if type(life.removeMapAnnotation) == "function" then
            life.removeMapAnnotation(marker)
        end
        return false, reason
    end
    local okay, accepted, responseReason, reply = pcall(
        behavior.radioRespond, group, player)
    if not okay or accepted ~= true then
        if type(life.removeMapAnnotation) == "function" then
            life.removeMapAnnotation(marker)
        end
        return false, okay and responseReason or tostring(accepted)
    end
    story.radioAnswered = true
    story.radioMapText = marker
    U().call(player, "setHaloNote", reply or responseReason or textValue)
    return true, reply or responseReason or "location_marked"
end

function Radio.install()
    if hooked then return true end
    if not Events or not Events.OnDeviceText then
        return false, "radio_event_unavailable"
    end
    Events.OnDeviceText.Add(Radio.onDeviceText)
    hooked = true
    return true
end

function Radio.remove()
    if hooked and Events and Events.OnDeviceText then
        Events.OnDeviceText.Remove(Radio.onDeviceText)
    end
    hooked, pending = false, nil
end

function Radio.isInstalled() return hooked end

return Radio
