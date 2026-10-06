-- SPDX-License-Identifier: MIT

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.RadioListening = SC.RadioListening or {}
local Radio = SC.RadioListening
local installed = false
local lastCommentAt = setmetatable({}, { __mode = "k" })

local function U() return SC.GameplayUtil end
local function numberCall(object, method)
    local value = select(1, U().call(object, method))
    return tonumber(value)
end

local function dataOf(object)
    if type(object) ~= "table" and not U().instanceOf(object, "IsoWaveSignal") then
        return nil
    end
    local data = select(1, U().call(object, "getDeviceData"))
    if not data or select(1, U().call(data, "getIsTelevision")) == true then
        return nil
    end
    return data
end

local function roomOf(value)
    return select(1, U().call(U().squareOf(value), "getRoom"))
end

local function sameRoom(first, second)
    local room = roomOf(first)
    return room ~= nil and room == roomOf(second)
end

local function campFloorRoute(source, destination)
    return SC.BaseLife and type(SC.BaseLife.allowsFloorTransit) == "function"
        and SC.BaseLife.allowsFloorTransit(source, destination,
            { workCampOnly = true }) == true
end

local function powerAvailable(data)
    if select(1, U().call(data, "getIsBatteryPowered")) == true then
        return (numberCall(data, "getPower") or 0) > 0
    end
    return select(1, U().call(data, "canBePoweredHere")) == true
        or (numberCall(data, "getPower") or 0) > 0
end

local function station(data)
    local current = numberCall(data, "getChannel")
    local team = SC.ExpeditionPrototype
        and SC.ExpeditionPrototype.TEAM_RADIO_CHANNEL or 90000
    if current and current > 0 and current ~= team then return current end
    local presets = select(1, U().call(data, "getDevicePresets"))
    local entries = select(1, U().call(presets, "getPresets"))
    local size = numberCall(entries, "size") or 0
    for index = 0, math.min(size, 20) - 1 do
        local entry = select(1, U().call(entries, "get", index))
        local frequency = numberCall(entry, "getFrequency")
        if frequency and frequency > 0 and frequency ~= team then
            return frequency
        end
    end
    return nil
end

function Radio.usable(object)
    local data = object and dataOf(object) or nil
    if not data or not powerAvailable(data) or not station(data) then return false end
    return true, data
end

function Radio.audible(object)
    local usable, data = Radio.usable(object)
    return usable and select(1, U().call(data, "getIsTurnedOn")) == true
        and (numberCall(data, "getDeviceVolume") or 0) > 0
        and numberCall(data, "getChannel") == station(data)
end

local function nearbySeat(actor, receiver, hooks, state, now)
    local rx, ry, rz = U().position(receiver)
    if not rx then return nil end
    local best, bestDistance
    for dx = -4, 4 do
        for dy = -4, 4 do
            local square = U().gridSquare(rx + dx, ry + dy, rz)
            if square and sameRoom(square, receiver) then
                U().squareObjects(square, function(object)
                    if hooks.furnitureKind(object) ~= "sit"
                        or hooks.reserved(object, actor, now)
                        or hooks.cooling(state, object, now)
                        or select(1, U().call(object,
                            "isFurnitureOccupied", actor)) == true then return true end
                    local arrived, targets = hooks.freeAccess(actor, object)
                    if not arrived and #(targets or {}) == 0 then return true end
                    local distance = U().distance(actor, square)
                    if distance <= 10 and (not best or distance < bestDistance) then
                        best, bestDistance = object, distance
                    end
                    return true
                end, 24)
            end
        end
    end
    return best
end

function Radio.candidate(actor, state, now, hooks, desiredKind)
    if not actor or not hooks or (desiredKind and desiredKind ~= "sit"
        and desiredKind ~= "radio_listen" and desiredKind ~= "radio_setup") then
        return nil
    end
    local ax, ay, az = U().position(actor)
    if not ax then return nil end
    local seated = hooks.seatingStatus(actor) == "furniture"
    local camp = not seated and SC.BaseLife
        and type(SC.BaseLife.active) == "function" and SC.BaseLife.active()
    local best, bestScore
    for floor = math.floor(az) - 1, math.floor(az) + 1 do
        local crossFloor = floor ~= math.floor(az)
        if not crossFloor or camp then
            local radius = crossFloor and 5 or 6
            for dx = -radius, radius do
                for dy = -radius, radius do
                    local square = U().gridSquare(ax + dx, ay + dy, floor)
                    if square and (crossFloor or sameRoom(actor, square)) then
                        U().squareObjects(square, function(object)
                            local usable, data = Radio.usable(object)
                            if not usable or (crossFloor
                                and not campFloorRoute(actor, square)) then return true end
                            local seat
                            if seated then
                                if sameRoom(actor, object)
                                    and U().distance(actor, object) <= 5 then
                                    seat = true
                                end
                            else
                                seat = nearbySeat(actor, object, hooks, state, now)
                            end
                            if not seat then return true end
                            local audible = Radio.audible(object)
                            local candidate
                            if seated and audible and desiredKind ~= "sit"
                                and desiredKind ~= "radio_setup" then
                                candidate = { kind = "radio_listen", score = 30,
                                    object = object, seated = true,
                                    durationMs = 90000,
                                    fact = { activity = "radio_listen" } }
                            elseif not seated and (not audible or crossFloor)
                                and desiredKind ~= "sit"
                                and desiredKind ~= "radio_listen" then
                                candidate = { kind = "radio_setup", score = 26,
                                    object = object, square = square,
                                    crossFloor = crossFloor,
                                    originSquare = crossFloor and U().squareOf(actor) or nil,
                                    fact = { activity = "radio_setup" } }
                            elseif not seated and audible and desiredKind ~= "radio_setup"
                                and desiredKind ~= "radio_listen" then
                                candidate = { kind = "sit", score = 32,
                                    object = seat, square = U().squareOf(seat),
                                    fact = { activity = "sit",
                                        seatingFor = "radio_listen" } }
                            end
                            if candidate then
                                local distance = U().distance(actor, square)
                                candidate.score = candidate.score - distance * 0.2
                                if not best or candidate.score > bestScore then
                                    best, bestScore = candidate, candidate.score
                                end
                            end
                            return true
                        end, 24)
                    end
                end
            end
        end
    end
    return best
end

function Radio.valid(actor, activity, atReceiver)
    if not actor or not activity or not Radio.usable(activity.object) then
        return false
    end
    if not sameRoom(actor, activity.object) then
        if atReceiver or activity.crossFloor ~= true
            or not campFloorRoute(activity.originSquare, activity.square) then
            return false
        end
        local nav = SC.Navigation and type(SC.Navigation.peek) == "function"
            and SC.Navigation.peek(actor) or nil
        local lease = nav and nav.nativeLease or nil
        local onCampStairs = lease and lease.workCampOnly == true
            and lease.affordance == "multi_level"
            and ((SC.Navigation._betweenFloorHeights
                    and SC.Navigation._betweenFloorHeights(actor))
                or (SC.BaseLife and SC.BaseLife.admitsStairTransit
                    and SC.BaseLife.admitsStairTransit(
                        U().squareOf(actor), lease))
                or (SC.Navigation.isCampStairLanding
                    and SC.Navigation.isCampStairLanding(actor)))
        if not SC.BaseLife or (SC.BaseLife.isInside(actor) ~= true
            and not onCampStairs) then
            return false
        end
    end
    if activity.kind == "radio_listen" then
        return Radio.audible(activity.object)
            and sameRoom(actor, activity.object)
            and U().distance(actor, activity.object) <= 5
            and select(1, U().call(actor, "isSittingOnFurniture")) == true
    end
    return true
end

function Radio.approach(actor, activity)
    if U().directInteractionAccess(actor, activity.object) == true then
        return true, "arrived"
    end
    if not SC.Navigation or type(SC.Navigation.requestAny) ~= "function" then
        return false, "navigation_unavailable"
    end
    local _, targets = U().directInteractionAccess(actor, activity.object)
    if #(targets or {}) == 0 then return false, "radio_no_access_square" end
    return SC.Navigation.requestAny(actor, targets, "walk", {
        action = "move_to_radio", object = activity.object,
        targetSquare = activity.square, requireSameSquare = true,
        continuousApproach = true, workCampOnly = activity.crossFloor == true,
        supervisorToken = activity.supervisorToken,
    })
end

function Radio.setup(actor, activity)
    if not Radio.valid(actor, activity, true)
        or U().directInteractionAccess(actor, activity.object) ~= true then
        return false, "radio_out_of_reach"
    end
    local data = dataOf(activity.object)
    local frequency = station(data)
    if not frequency then return false, "radio_no_station" end
    local alreadyAudible = Radio.audible(activity.object)
    U().call(actor, "faceThisObject", activity.object)
    if select(1, U().call(data, "getIsTurnedOn")) ~= true then
        U().call(data, "playSoundSend", "RadioButton", false)
        U().call(data, "setIsTurnedOn", true)
    end
    if numberCall(data, "getChannel") ~= frequency then
        U().call(data, "playSoundSend", "TuneIn", false)
        U().call(data, "setChannel", frequency)
    end
    if (numberCall(data, "getDeviceVolume") or 0) <= 0 then
        U().call(data, "setDeviceVolume", 0.35)
    end
    if not Radio.audible(activity.object) then return false, "radio_setup_failed" end
    activity.actionAccepted = true
    if SC.Dialogue and type(SC.Dialogue.say) == "function" then
        SC.Dialogue.say(actor, alreadyAudible and "downtime.radio.found"
            or "downtime.radio.tune")
    end
    return true, "radio_ready"
end

function Radio.start(actor, activity, now)
    if not Radio.valid(actor, activity, true) then
        return false, "radio_listening_position_lost"
    end
    activity.actionAccepted = true
    activity.startedAt = now
    activity.approaching = nil
    activity.lastBroadcastAt = nil
    if SC.Dialogue and type(SC.Dialogue.say) == "function" then
        SC.Dialogue.say(actor, "downtime.radio.listen")
    end
    return true, "listening_radio"
end

function Radio.finish(actor, activity)
    if not SC.Dialogue or type(SC.Dialogue.say) ~= "function" then return end
    SC.Dialogue.say(actor, activity.lastBroadcastAt
        and "downtime.radio.signoff" or "downtime.radio.silence")
end

function Radio.onDeviceText(guid, codes, x, y, z)
    if tonumber(x) == -1 or tonumber(y) == -1 or tonumber(z) == -1
        or not SC.Registry or type(SC.Registry.living) ~= "function" then return end
    for _, actor in ipairs(SC.Registry.living()) do
        local state = SC.Downtime and SC.Downtime.peek(actor) or nil
        local activity = state and state.active or nil
        if activity and activity.kind == "radio_listen" and activity.startedAt
            and Radio.valid(actor, activity, true) then
            local rx, ry, rz = U().position(activity.object)
            if rx and math.floor(rx) == math.floor(tonumber(x) or -1)
                and math.floor(ry) == math.floor(tonumber(y) or -1)
                and math.floor(rz or 0) == math.floor(tonumber(z) or -1) then
                local now = U().nowMs()
                activity.lastBroadcastAt = now
                if now - (lastCommentAt[actor] or -math.huge) >= 30000
                    and now - (SC.Dialogue and SC.Dialogue.lastSpokenAt
                        and SC.Dialogue.lastSpokenAt(actor) or -math.huge) >= 10000
                    and SC.Dialogue and type(SC.Dialogue.say) == "function" then
                    local topic = type(codes) == "string"
                        and codes:match("%u%u%u[%+%-=]")
                        and "downtime.radio.useful" or "downtime.radio.broadcast"
                    if SC.Dialogue.say(actor, topic, nil, nil,
                        { recentLimit = 8, salt = tostring(guid) }) == true then
                        lastCommentAt[actor] = now
                    end
                end
            end
        end
    end
end

function Radio.install()
    if installed or not Events or not Events.OnDeviceText
        or type(Events.OnDeviceText.Add) ~= "function" then return false end
    Events.OnDeviceText.Add(Radio.onDeviceText)
    installed = true
    return true
end

Radio.install()
