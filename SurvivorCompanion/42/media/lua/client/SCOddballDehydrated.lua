-- SPDX-License-Identifier: MIT
-- Nate Duvall, the county meter reader who ran out of water inside a shut room.
-- Radio dispatch and the player map are owned by the shared rescue-radio service.
local SC = SurvivorCompanion
SC.OddballDehydrated = SC.OddballDehydrated or {}
local Dehydrated = SC.OddballDehydrated

local ID = "radio_rescue_nate_duvall"
local CHANNEL = 90000
local RECOVERY_MS = 120000
local RADIO_INTERVAL_MS = 110000
local RADIO_LINES = {
    "Nate Duvall on ninety. County meter reader. Shut in a room with an empty canteen. Anybody carrying clean water?",
    "Ninety megahertz. Nate Duvall again. I can hear rain on the roof but I cannot get a drop to drink.",
    "If you hear the little radio, answer it. I am behind a closed door, and my mouth's too dry to shout much longer.",
    "I used to mark every working tap in this county. That's a cruel thing to remember when you're dying of thirst.",
}
local WAIT_LINES = {
    "It's Nate. Door's closed. Please tell me that's a water bottle I hear.",
    "I walked the county checking meters. Every well I tried was dry or bad. Last one cost me the walk back.",
    "My tongue feels like a strip of old leather. Clean water, if you have it.",
    "I locked myself in when I started seeing two doorways where there was one.",
    "Don't let the radio fool you. I sound stronger than I am.",
}
local OPEN_LINES = {
    "That door was the last thing I could still manage. Come close. I can't stand yet.",
    "You made it. Don't make me try to rise before I can see straight.",
}
local RECOVER_LINES = {
    "Slow. If I stand up too fast, you'll have to carry me.",
    "The room's stopped turning. Let me sit a little longer.",
    "A county full of taps and one good bottle saved me. That's some arithmetic.",
}
local AFTER_LINES = {
    "I'm Nate. I read water meters before Knox forgot what a working tap sounded like.",
    "I can walk now. First I want to mark the wells that are still worth trying.",
    "You brought water to a stranger. I won't forget that.",
}
local lastRecoveryPulse = setmetatable({}, { __mode = "k" })
local nextPoseAt = setmetatable({}, { __mode = "k" })
local shelterByActor = setmetatable({}, { __mode = "k" })

local function U() return SC.GameplayUtil end
local function number(value)
    if type(value) == "number" then return value end
    if type(value) == "string" then return tonumber(value) end
    return nil
end
local function story(group)
    local value = group and group.oddball
    return type(value) == "table" and value.id == ID and value or nil
end
local function actorFor(group)
    local member = group and group.members and group.members[1]
    local record = member and member.actorId and SC.Registry
        and SC.Registry.byId(member.actorId)
    return record and record.actor and U().isValidActor(record.actor)
        and record.actor or nil
end
local function doorFor(value)
    local post = value and value.site and value.site.rescueDoor
    local square = post and U().gridSquare(post.x, post.y, post.z or 0)
    local objects = square and select(1, U().call(square, "getObjects"))
    local door = objects and SC.NativeList
        and SC.NativeList.get(objects, post.objectIndex)
    return door and U().instanceOf(door, "IsoDoor") and door or nil
end
local function playerInRoom(value, player)
    local post = value and value.site and value.site.spawn
    local roomSquare = post and U().gridSquare(post.x, post.y, post.z or 0)
    local room = roomSquare and select(1, U().call(roomSquare, "getRoom"))
    local playerSquare = player and U().squareOf(player)
    return room ~= nil and playerSquare ~= nil
        and select(1, U().call(playerSquare, "getRoom")) == room
end
local function near(group, player, radius)
    local actor = actorFor(group)
    return actor ~= nil and player ~= nil
        and U().distance(actor, player) <= radius
end
local function nearDoor(value, player, radius)
    local post = value and value.site and value.site.rescueDoor
    if not player then return false end
    local x, y, z = U().position(player)
    return post ~= nil and x ~= nil and math.floor(z or 0) == (post.z or 0)
        and (x - post.x) ^ 2 + (y - post.y) ^ 2 <= radius * radius
end
local function sayIndex(actor, value, list, key)
    if not actor or #list == 0 then return false end
    local index = ((number(value[key]) or 0) % #list) + 1
    value[key] = index
    return U().say(actor, list[index])
end
local function thirstStat()
    if CharacterStat == nil then return nil end
    local okay, result = pcall(function() return CharacterStat.THIRST end)
    return okay and result or nil
end
local function seedThirst(value, actor)
    if value.thirstSeeded == true then return true end
    local stats = select(1, U().call(actor, "getStats"))
    local kind = thirstStat()
    if not stats or not kind then return false, "thirst_stat_unavailable" end
    local _, set = U().call(stats, "set", kind, 0.94)
    if not set then return false, "thirst_seed_failed" end
    value.thirstSeeded = true
    return true
end
local function ensureRadio(actor, allowCreate)
    local inventory = actor and U().inventory(actor)
    if not inventory then return false, "radio_inventory_unavailable" end
    local radio
    for _, item in ipairs(U().inventoryItemsDeep(inventory, 160, 8)) do
        if U().itemType(item) == "Base.WalkieTalkie2" then
            radio = item
            break
        end
    end
    if radio then
        local source = select(1, U().call(radio, "getContainer"))
        if source ~= inventory
            and (not source or U().transferItemVerified(source,
                inventory, radio) ~= true) then
            return false, "radio_could_not_be_unpacked"
        end
    end
    if not radio and allowCreate == false then
        return false, "radio_missing"
    end
    if not radio then radio = U().addItem(inventory, "Base.WalkieTalkie2") end
    if not radio or not U().instanceOf(radio, "Radio") then
        return false, "native_radio_unavailable"
    end
    local data = select(1, U().call(radio, "getDeviceData"))
    if not data or select(1, U().call(data, "getIsTwoWay")) ~= true
        or select(1, U().call(data, "getIsPortable")) ~= true then
        return false, "two_way_radio_unavailable"
    end
    local hasBattery = select(1, U().call(data, "getHasBattery"))
    local rawPower = select(1, U().call(data, "getPower"))
    local power = number(rawPower) or 0
    if hasBattery == true and power <= 0 then
        U().call(data, "getBattery", inventory)
        hasBattery = false
    end
    if hasBattery ~= true then
        local battery = U().addItem(inventory, "Base.Battery")
        if not battery then return false, "radio_battery_unavailable" end
        U().call(data, "addBattery", battery)
    end
    U().call(data, "setChannel", CHANNEL)
    U().call(data, "setDeviceVolume", 0.8)
    U().call(data, "setMicIsMuted", false)
    U().call(data, "setIsTurnedOn", true)
    U().call(actor, "setSecondaryHandItem", radio)
    local held = select(1, U().call(actor, "getSecondaryHandItem")) == radio
    local active = select(1, U().call(data, "getIsTurnedOn")) == true
    local channel = select(1, U().call(data, "getChannel"))
    local tuned = number(channel) == CHANNEL
    hasBattery = select(1, U().call(data, "getHasBattery")) == true
    rawPower = select(1, U().call(data, "getPower"))
    power = number(rawPower) or 0
    local nativeEquipped, nativeRead = U().call(actor, "getEquipedRadio")
    local range = select(1, U().call(data, "getTransmitRange"))
    local muted = select(1, U().call(data, "getMicIsMuted"))
    local noTransmit = select(1, U().call(data, "isNoTransmit"))
    local ready = held and active and tuned and hasBattery and power > 0
        and (not nativeRead or nativeEquipped == radio)
        and (range == nil or number(range) and number(range) > 0)
        and muted ~= true and noTransmit ~= true
    return ready,
        ready
            and "radio_ready" or "radio_readback_failed"
end
local function operationalRadio(actor)
    local radio = actor and select(1, U().call(actor, "getEquipedRadio"))
    local inventory = actor and U().inventory(actor)
    if not radio or not inventory
        or select(1, U().call(radio, "getContainer")) ~= inventory
        or select(1, U().call(actor, "getSecondaryHandItem")) ~= radio then
        return nil
    end
    local data = select(1, U().call(radio, "getDeviceData"))
    local channel = data and select(1, U().call(data, "getChannel"))
    local power = data and select(1, U().call(data, "getPower"))
    local range = data and select(1, U().call(data, "getTransmitRange"))
    if not data or number(channel) ~= CHANNEL
        or select(1, U().call(data, "getHasBattery")) ~= true
        or select(1, U().call(data, "getIsTurnedOn")) ~= true
        or (number(power) or 0) <= 0
        or (number(range) or 0) <= 0
        or select(1, U().call(data, "getMicIsMuted")) == true
        or select(1, U().call(data, "isNoTransmit")) == true then
        return nil
    end
    return radio, data, number(range)
end
local function syncShelter(actor, wanted)
    if not actor then return false end
    local actual, readable = U().call(actor, "isZombiesDontAttack")
    if shelterByActor[actor] == wanted and readable and actual == wanted then
        return true
    end
    if not SC.Oddballs or type(SC.Oddballs.setZombieShelter) ~= "function" then
        return false
    end
    local okay = SC.Oddballs.setZombieShelter(actor, wanted)
    if okay == true then shelterByActor[actor] = wanted end
    return okay == true
end
local function waterItem(player)
    local inventory = player and U().inventory(player)
    if not inventory then return nil end
    for _, item in ipairs(U().inventoryItemsDeep(inventory, 240, 12)) do
        local source = select(1, U().call(item, "getContainer"))
        if source and select(1, U().call(item, "isWaterSource")) == true then
            local fluid = select(1, U().call(item, "getFluidContainer"))
            local rawAmount = fluid and select(1,
                U().call(fluid, "getAmount"))
            local amount = number(rawAmount) or 0
            local primary = fluid and select(1,
                U().call(fluid, "getPrimaryFluid"))
            local kind = primary and select(1,
                U().call(primary, "getFluidTypeString"))
            local tainted = false
            if Fluid ~= nil then
                local okay, taintedType = pcall(function()
                    return Fluid.TaintedWater
                end)
                if okay and taintedType then
                    local contains, read = U().call(fluid, "contains", taintedType)
                    tainted = not read or contains == true
                end
            end
            if amount >= 0.12 and not tainted
                and (kind == "Water" or kind == "CarbonatedWater") then
                return item, fluid, amount
            end
        end
    end
    return nil
end
local function applyWater(group, player, actor)
    local item, fluid, originalAmount = waterItem(player)
    local source = item and select(1, U().call(item, "getContainer"))
    local destination = actor and U().inventory(actor)
    local stats = actor and select(1, U().call(actor, "getStats"))
    local thirst = thirstStat()
    if not source or not destination or not stats or not thirst then
        return false, "clean_water_unavailable"
    end
    if U().transferItemVerified(source, destination, item) ~= true then
        return false, "water_transfer_failed"
    end
    local sip = math.min(originalAmount, 0.25)
    local _, drained = U().call(fluid, "adjustAmount", originalAmount - sip)
    if not drained then
        U().transferItemVerified(destination, source, item)
        return false, "water_could_not_be_drunk"
    end
    local _, relieved = U().call(stats, "remove", thirst, 0.5)
    if not relieved then
        U().call(fluid, "adjustAmount", originalAmount)
        U().transferItemVerified(destination, source, item)
        return false, "thirst_could_not_decrease"
    end
    local value = story(group)
    value.waterReceived = true
    value.radioAnswered = true
    value.recoveryElapsedMs = 0
    value.stage = "recovering"
    value.nextRecoveryLineAt = U().nowMs() + 35000
    lastRecoveryPulse[group] = U().nowMs()
    U().say(actor, "Water. Real water. Give me a minute. My legs haven't forgiven me yet.")
    return true, "water_given"
end
local function gamePaused()
    if type(getGameTime) ~= "function" then return false end
    local okay, gameTime = pcall(getGameTime)
    if not okay or not gameTime then return false end
    local multiplier = select(1, U().call(gameTime, "getMultiplier"))
    return number(multiplier) ~= nil and number(multiplier) <= 0
end

function Dehydrated.onSpawn(group, actor)
    local value = story(group)
    if not value or not actor then return false, "nate_unavailable" end
    if value.roomGuardDone == true then value.opened = true end
    local door = doorFor(value)
    local square = value.site and value.site.spawn
        and U().gridSquare(value.site.spawn.x, value.site.spawn.y,
            value.site.spawn.z or 0)
    if value.opened ~= true and (not door or not square
        or select(1, U().call(square, "getRoom")) == nil) then
        return false, "rescue_room_unavailable"
    end
    if value.opened ~= true and select(1, U().call(door, "IsOpen")) == true then
        return false, "rescue_door_open"
    end
    local ready, why = ensureRadio(actor, value.radioSeeded ~= true)
    if not ready and why ~= "radio_missing" then return false, why end
    if ready then value.radioSeeded = true end
    if value.emptyBottleSeeded ~= true then
        local inventory = U().inventory(actor)
        local bottle
        for _, item in ipairs(U().inventoryItemsDeep(inventory, 160, 8)) do
            if U().itemType(item) == "Base.WaterBottle" then
                bottle = item break
            end
        end
        bottle = bottle or U().addItem(inventory, "Base.WaterBottle")
        local fluid = bottle and select(1, U().call(bottle,
            "getFluidContainer"))
        local _, emptied = U().call(fluid, "adjustAmount", 0)
        if not emptied then return false, "empty_canteen_unavailable" end
        value.emptyBottleSeeded = true
    end
    local seeded, reason = seedThirst(value, actor)
    if not seeded then return false, reason end
    value.stage = value.stage or "waiting"
    if value.stage == "unmet" then value.stage = "waiting" end
    if value.opened ~= true and value.roomGuardDone ~= true then
        syncShelter(actor, true)
    else
        syncShelter(actor, false)
    end
    if value.waterReceived ~= true and SC.Actor
        and type(SC.Actor.setMovement) == "function" then
        SC.Actor.setMovement(actor, "walk", { action = "sit_ground" })
    end
    return true, "nate_waiting"
end

function Dehydrated.pulse(group, player, current)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    local actor = actorFor(group)
    if not actor then return false, "nate_unloaded" end
    current = number(current) or U().nowMs()
    if value.opened ~= true then
        local door = doorFor(value)
        if door and select(1, U().call(door, "IsOpen")) == true
            or value.roomGuardDone == true
            or playerInRoom(value, player) then
            value.opened = true
            value.stage = value.waterReceived and "recovering" or "waiting"
            if SC.OddballRoomGuard then SC.OddballRoomGuard.release(group.id) end
            syncShelter(actor, false)
            group.discovered = true
            sayIndex(actor, value, OPEN_LINES, "openLineIndex")
            value.nextWaitLineAt = current + 30000
        else
            syncShelter(actor, true)
        end
    end
    if value.waterReceived == true and value.recovered ~= true then
        local last = lastRecoveryPulse[group]
        if last and current > last and not gamePaused() then
            value.recoveryElapsedMs = math.min(RECOVERY_MS,
                (number(value.recoveryElapsedMs) or 0)
                    + math.min(current - last, 2500))
        end
        lastRecoveryPulse[group] = current
        if value.recoveryElapsedMs >= RECOVERY_MS then
            value.stage = "getting_up"
            if SC.Actor and type(SC.Actor.setMovement) == "function" then
                SC.Actor.setMovement(actor, "walk", { action = "stand_ground" })
            end
            local seated, seatedRead = U().call(actor, "isSitOnGround")
            if seatedRead and seated == false then
                value.recovered = true
                value.stage = "recovered"
                U().say(actor, "There. I can stand. The room can keep the rest of me.")
            end
        elseif value.opened and near(group, player, 6)
            and current >= (number(value.nextRecoveryLineAt) or 0) then
            sayIndex(actor, value, RECOVER_LINES, "recoveryLineIndex")
            value.nextRecoveryLineAt = current + 45000
        end
    elseif value.recovered == true and near(group, player, 7)
        and current >= (number(value.nextAfterLineAt) or 0) then
        sayIndex(actor, value, AFTER_LINES, "afterLineIndex")
        value.nextAfterLineAt = current + 95000
    elseif value.waterReceived ~= true and near(group, player, 7)
        and current >= (number(value.nextWaitLineAt) or 0) then
        sayIndex(actor, value, WAIT_LINES, "waitLineIndex")
        value.nextWaitLineAt = current + 32000
        group.discovered = true
    end
    return true, value.stage
end

function Dehydrated.radioOffer(group, player, current)
    local value = story(group)
    if not value or value.radioAnswered == true
        or value.waterReceived == true or value.recovered == true then
        return nil, "rescue_already_answered"
    end
    local actor = actorFor(group)
    local point = value.site and value.site.spawn
    if not actor or not point then return nil, "radio_survivor_unloaded" end
    local radio, _, range = operationalRadio(actor)
    if not radio then return nil, "radio_unavailable" end
    current = number(current) or U().nowMs()
    if current < (number(value.nextRadioAt) or 0) then
        return nil, "radio_cooldown"
    end
    local index = ((number(value.radioIndex) or 0) % #RADIO_LINES) + 1
    value.radioIndex = index
    value.nextRadioAt = current + RADIO_INTERVAL_MS
    group.discovered = true
    return { frequency = CHANNEL, text = RADIO_LINES[index],
        x = point.x, y = point.y, z = point.z or 0,
        guid = "LF-NATE-" .. tostring(group.id),
        replyLabel = "Tell Nate you are coming", range = range }, "distress"
end

function Dehydrated.radioRespond(group, player)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    if value.recovered == true then return false, "nate_already_recovered" end
    value.radioAnswered = true
    group.discovered = true
    local reply = value.opened == true
        and "Copy. I'm still on the floor. Bring clean water and give me time to stand."
        or "Copy. The door's shut. I'm on the floor inside. Bring clean water, please."
    return true, "radio_answered", reply
end

function Dehydrated.intentFor(actor, player, snapshot, group)
    local value = story(group)
    if not value then return nil end
    if value.recovered ~= true then
        return { mode = "dehydrated_wait", priority = 90 }
    end
    local threats = snapshot and (number(snapshot.threatCount)
        or #(snapshot.threats or {})) or 0
    if threats > 0 then return { mode = "zombie_defense", priority = 18 } end
    return { mode = "oddball_idle", priority = 28 }
end

function Dehydrated.update(actor, player, runtime, intent, group)
    local value = story(group)
    if not value or not intent or intent.mode ~= "dehydrated_wait" then
        return false, "nate_no_special_move"
    end
    if value.waterReceived ~= true
        and select(1, U().call(actor, "isSitOnGround")) ~= true
        and U().nowMs() >= (nextPoseAt[actor] or 0)
        and SC.Actor and type(SC.Actor.setMovement) == "function" then
        nextPoseAt[actor] = U().nowMs() + 12000
        SC.Actor.setMovement(actor, "walk", { action = "sit_ground" })
    end
    return true, value.waterReceived and "nate_recovering"
        or "nate_waiting_for_water"
end

function Dehydrated.zombiesIgnore(actor, group)
    local value = story(group)
    return value ~= nil and value.opened ~= true
        and value.roomGuardDone ~= true and value.recovered ~= true
end

function Dehydrated.avoidsZombieCombat(actor, group)
    local value = story(group)
    return value ~= nil and value.recovered ~= true
end

function Dehydrated.menuOptions(group, player)
    local value = story(group)
    if not value or not player or not nearDoor(value, player, 7)
        and not near(group, player, 7) then return {} end
    if value.recovered == true then
        return { { id = "ask_story", label = "Ask Nate about the wells",
            enabled = true } }
    end
    if value.opened ~= true then
        return { { id = "call_through_door",
            label = "Call to Nate through the door", enabled = true } }
    end
    return { { id = "give_water", label = "Give Nate clean water",
        enabled = value.waterReceived ~= true and waterItem(player) ~= nil },
        { id = "ask_story", label = "Ask Nate how he got trapped",
            enabled = true } }
end

function Dehydrated.action(group, action, player)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    local actor = actorFor(group)
    if action == "hurt" then
        if actor then U().say(actor, "I'm not one of them. Don't make this worse.") end
        return true, "nate_hurt_warning"
    end
    if not actor or not player or not nearDoor(value, player, 7)
        and not near(group, player, 7) then return false, "nate_too_far" end
    if action == "call_through_door" and value.opened ~= true then
        U().say(actor, "Nate Duvall. I locked the room. Please, water first. Questions after.")
        group.discovered = true
        return true, "nate_answered_door"
    elseif action == "ask_story" then
        if value.waterReceived ~= true then
            U().say(actor, "Meter reader. I knew every working tap. Found four dry ones before I fell in here.")
        else
            U().say(actor, "I walked the water route after the mains died. Left chalk marks where the wells still ran. Then I lost my own bottle.")
        end
        return true, "nate_story_told"
    elseif action == "give_water" then
        if value.opened ~= true then return false, "open_rescue_door_first" end
        if value.waterReceived == true then return false, "water_already_given" end
        if not near(group, player, 3) then return false, "nate_out_of_reach" end
        return applyWater(group, player, actor)
    end
    return false, "unknown_nate_action"
end

function Dehydrated.canRecruit(group)
    local value = story(group)
    return value ~= nil and value.recovered == true
        and group.standing ~= "Hostile" or false,
        "give_nate_water_and_wait_until_he_can_stand"
end

return Dehydrated
