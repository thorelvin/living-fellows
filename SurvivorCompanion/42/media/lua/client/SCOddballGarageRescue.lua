-- SPDX-License-Identifier: MIT
-- Eli Rourke shut himself into a garage after an engine hoist broke his leg.
-- His call uses a real powered walkie; the player's own medical panel performs
-- treatment, so no story callback invents a bandage or removes a fracture.
local SC = SurvivorCompanion
SC.OddballGarageRescue = SC.OddballGarageRescue or {}
local Rescue = SC.OddballGarageRescue

local ID = "garage_rescue_eli_rourke"
local CHANNEL = 90000
local RADIO_TYPE = "Base.WalkieTalkie2"
local BANDAGE_TYPES = {
    ["Base.Bandage"] = true, ["Base.AlcoholBandage"] = true,
}
local CALLS = {
    "This is Eli Rourke on ninety megahertz. I'm shut in a garage with a busted leg. Anybody copy?",
    "Garage door's holding. The jack didn't. I need a splint and a clean bandage, over.",
    "I fixed everybody else's trucks. Right now I can't fix the two feet between me and the door.",
    "If you hear this, answer me. I'll give you the garage location. Please don't bring the dead.",
    "Ninety megahertz. Eli Rourke. Leg's broken. Still breathing, which feels like an argument I can win.",
}
local PAIN = {
    "I heard the jack click twice. Knew better. Kept turning the wrench anyway.",
    "The leg's got its own heartbeat. Neither one of us likes the rhythm.",
    "Don't haul me upright yet. Splint first, then I'll try being brave.",
    "My brother called this place a grave with a roll-up door. He always was a cheerful bastard.",
    "There's a toolbox by the wall. I can't reach it, and it can't help with a bone.",
}
local AFTER = {
    "I can put weight on it now. Slow, but slow is a direction.",
    "You used your own supplies. I won't forget that when somebody else needs mine.",
    "That garage smelled of old oil and bad decisions. Let's leave both behind.",
}
local shelterState = setmetatable({}, { __mode = "k" })

local function U() return SC.GameplayUtil end
local function number(value, fallback)
    if type(value) == "number" then return value end
    if type(value) == "string" then return tonumber(value) or fallback end
    return fallback
end
local function valueFor(group)
    local value = group and group.oddball
    return type(value) == "table" and value.id == ID and value or nil
end
local function actorFor(group)
    local first = group and group.members and group.members[1]
    local record = first and first.actorId and SC.Registry
        and SC.Registry.byId(first.actorId)
    return record and record.actor and U().isValidActor(record.actor)
        and record.actor or nil
end
local function sitePoint(value)
    local site = value and value.site
    return site and (site.spawn or site.anchor) or nil
end
local function rescueDoor(value)
    local post = value and value.site and value.site.rescueDoor
    local square = post and U().gridSquare(post.x, post.y, post.z or 0)
    local objects = square and select(1, U().call(square, "getObjects"))
    local door = objects and SC.NativeList
        and SC.NativeList.get(objects, post.objectIndex)
    return door and U().instanceOf(door, "IsoDoor") and door or nil
end
local function nearby(actor, player, radius)
    return actor and player and U().distance(actor, player) <= radius
end
local function bodyPart(actor)
    local body = actor and select(1, U().call(actor, "getBodyDamage"))
    local partType = BodyPartType and BodyPartType.LowerLeg_L
    return body and partType and select(1, U().call(body, "getBodyPart", partType))
        or nil
end
local function injuryState(actor)
    local part = bodyPart(actor)
    if not part then return nil, false, false end
    local fracture = number(select(1, U().call(part, "getFractureTime")), 0)
    local factor = number(select(1, U().call(part, "getSplintFactor")), 0)
    local bandaged = select(1, U().call(part, "bandaged")) == true
        or select(1, U().call(part, "isBandaged")) == true
    return part, fracture > 0 and factor > 0, bandaged
end
local function hasPlayerSupplies(player)
    local inventory = player and U().inventory(player)
    if not inventory then return false, false end
    local splint, bandage = false, false
    for _, item in ipairs(U().inventoryItemsDeep(inventory, 320, 16)) do
        local kind = U().itemType(item)
        if kind == "Base.Splint" then splint = true end
        if BANDAGE_TYPES[kind] then bandage = true end
    end
    return splint, bandage
end
local function radioItem(actor)
    local inventory = actor and U().inventory(actor)
    if not inventory then return nil end
    for _, item in ipairs(U().inventoryItemsDeep(inventory, 240, 8)) do
        if U().itemType(item) == RADIO_TYPE then return item end
    end
    return nil
end
local function radioReady(actor)
    local item = radioItem(actor)
    local inventory = U().inventory(actor)
    local data = item and select(1, U().call(item, "getDeviceData"))
    if not data or select(1, U().call(item, "getContainer")) ~= inventory
        or select(1, U().call(actor, "getSecondaryHandItem")) ~= item
        or select(1, U().call(data, "getIsTwoWay")) ~= true
        or select(1, U().call(data, "getIsTurnedOn")) ~= true
        or select(1, U().call(data, "getHasBattery")) ~= true
        or number(select(1, U().call(data, "getPower")), 0) <= 0
        or number(select(1, U().call(data, "getChannel"))) ~= CHANNEL then
        return nil
    end
    return item, data
end
local function prepareRadio(actor)
    local inventory = U().inventory(actor)
    if not inventory then return false, "garage_radio_inventory_unavailable" end
    local item = radioItem(actor) or U().addItem(inventory, RADIO_TYPE)
    if not item or not U().instanceOf(item, "Radio") then
        return false, "garage_radio_unavailable" end
    local data = select(1, U().call(item, "getDeviceData"))
    if not data or select(1, U().call(data, "getIsPortable")) ~= true
        or select(1, U().call(data, "getIsTwoWay")) ~= true then
        return false, "garage_two_way_radio_unavailable" end
    if select(1, U().call(data, "getHasBattery")) == true
        and number(select(1, U().call(data, "getPower")), 0) <= 0 then
        U().call(data, "getBattery", inventory)
    end
    if select(1, U().call(data, "getHasBattery")) ~= true then
        local battery
        for _, candidate in ipairs(U().inventoryItemsDeep(inventory, 160, 8)) do
            if U().itemType(candidate) == "Base.Battery" then
                battery = candidate break
            end
        end
        battery = battery or U().addItem(inventory, "Base.Battery")
        if not battery then return false, "garage_battery_unavailable" end
        local _, installed = U().call(data, "addBattery", battery)
        if not installed then return false, "garage_battery_install_failed" end
    end
    U().call(data, "setChannel", CHANNEL)
    U().call(data, "setDeviceVolume", 0.8)
    U().call(data, "setIsTurnedOn", true)
    local presets = select(1, U().call(data, "getDevicePresets"))
    if presets then
        local list = select(1, U().call(presets, "getPresets"))
        local count = number(select(1, U().call(list, "size")), 0)
        local max = number(select(1, U().call(presets, "getMaxPresets")), 0)
        if max > 0 and count < max then
            U().call(presets, "addPreset", "Eli's rescue channel", CHANNEL)
        elseif max > 0 then
            U().call(presets, "setPreset", 0, "Eli's rescue channel", CHANNEL)
        end
    end
    U().call(actor, "setSecondaryHandItem", item)
    return radioReady(actor) ~= nil,
        radioReady(actor) and "garage_radio_ready" or "garage_radio_readback_failed"
end
local function syncShelter(actor, wanted)
    if not actor or shelterState[actor] == wanted then return true end
    local service = SC.Oddballs
    if not service or type(service.setZombieShelter) ~= "function" then
        return false, "garage_shelter_unavailable" end
    local accepted, reason = service.setZombieShelter(actor, wanted)
    if accepted then shelterState[actor] = wanted end
    return accepted, reason
end
local function holdByWall(actor, value, current)
    if value.rescued or not actor then return end
    if select(1, U().call(actor, "isSitOnGround")) == true then return end
    if current < number(value.nextPoseAt, 0) then return end
    value.nextPoseAt = current + 12000
    if SC.Actor and type(SC.Actor.setMovement) == "function" then
        SC.Actor.setMovement(actor, "walk", { action = "sit_ground",
            reason = "garage_broken_leg_wall_rest" })
    end
end

function Rescue.onSpawn(group, actor)
    local value = valueFor(group)
    if not value or not actor then return false, "garage_rescue_unavailable" end
    local door = rescueDoor(value)
    if value.rescued ~= true and not door then
        return false, "garage_rescue_door_unavailable" end
    if value.rescued ~= true then
        local part = bodyPart(actor)
        if not part then return false, "garage_injury_part_unavailable" end
        if value.injurySeeded ~= true then
            local _, fractured = U().call(part, "setFractureTime", 60)
            local _, scratched = U().call(part, "setScratched", true, true)
            if not fractured or not scratched
                or number(select(1, U().call(part, "getFractureTime")), 0) <= 0 then
                return false, "garage_injury_readback_failed"
            end
            value.injurySeeded = true
        end
        if select(1, U().call(door, "IsOpen")) ~= true
            and value.doorUnlocked ~= true then
            U().call(door, "setLocked", true)
            value.doorLocked = select(1, U().call(door, "isLocked")) == true
        end
    end
    local ready, reason = prepareRadio(actor)
    if not ready then return false, reason end
    value.radioReady = true
    syncShelter(actor, value.rescued ~= true and value.doorOpened ~= true)
    holdByWall(actor, value, U().nowMs())
    return true, "garage_rescue_ready"
end

function Rescue.radioOffer(group, player, current)
    local value = valueFor(group)
    if not value or value.rescued == true or value.radioAnswered == true
        or not player then return nil end
    current = number(current, U().nowMs())
    if current < number(value.nextRadioAt, 0) then return nil end
    local actor = actorFor(group)
    local item, data
    if actor then item, data = radioReady(actor) end
    local post = sitePoint(value)
    if not data or not post then return nil end
    local sequence = number(value.radioSequence, 0) + 1
    local text = CALLS[((sequence - 1) % #CALLS) + 1]
    value.radioSequence = sequence
    value.nextRadioAt = current + (sequence == 1 and 45000 or 90000)
    return { frequency = CHANNEL, channel = CHANNEL,
        text = text, x = math.floor(post.x), y = math.floor(post.y),
        z = math.floor(post.z or 0),
        range = number(select(1, U().call(data, "getTransmitRange")), 400),
        guid = "LF-GARAGE-" .. tostring(group.id),
        codes = "HELP-" .. tostring(sequence),
        source = actor, radio = item }
end

function Rescue.radioRespond(group, player)
    local value = valueFor(group)
    if not value then return false, "wrong_oddball" end
    if value.rescued then return false, "garage_rescue_finished" end
    if value.radioAnswered then return false, "garage_radio_already_answered" end
    if not player or value.radioHeard ~= true then
        return false, "garage_distress_not_heard" end
    local actor = actorFor(group)
    if not actor or not radioReady(actor) then
        return false, "garage_radio_unavailable" end
    local post = sitePoint(value)
    if not post then return false, "garage_location_unavailable" end
    value.radioAnswered = true
    value.stage = "rescue_requested"
    group.discovered = true
    local reply = "Eli Rourke: Copy you. Garage near "
        .. tostring(math.floor(post.x)) .. ", "
        .. tostring(math.floor(post.y))
        .. ". I can unlock the door when you arrive. Bring a splint and a clean bandage."
    U().say(actor, "Somebody answered. Hold together, Eli.")
    return true, "garage_rescue_location_shared", reply
end

function Rescue.pulse(group, player, current)
    local value = valueFor(group)
    if not value then return false, "wrong_oddball" end
    local actor = actorFor(group)
    if not actor then return false, "garage_survivor_unloaded" end
    current = number(current, U().nowMs())
    -- Spawn initialization can fail transiently while the native body or
    -- device state settles. Retry only until the authored kit is verified;
    -- stealing his radio later must not create unlimited replacements.
    if not value.rescued and (value.injurySeeded ~= true
        or value.radioReady ~= true)
        and current >= number(value.nextSetupAt, 0) then
        value.nextSetupAt = current + 10000
        Rescue.onSpawn(group, actor)
    end
    local door = rescueDoor(value)
    local doorOpen = door and select(1, U().call(door, "IsOpen")) == true
    if doorOpen and value.doorOpened ~= true then
        value.doorOpened = true
        value.stage = "reached"
        group.discovered = true
        if SC.OddballRoomGuard then SC.OddballRoomGuard.release(group.id) end
        U().say(actor, "Easy on the threshold. I can't get to you without the splint.")
    end
    local post = value.site and value.site.rescueDoor
    if not value.rescued and door and post and player
        and U().distance(player, post) <= 3.5
        and (value.doorUnlocked ~= true
            or select(1, U().call(door, "isLocked")) == true) then
        U().call(door, "setLocked", false)
        if select(1, U().call(door, "isLocked")) ~= true then
            local firstUnlock = value.doorUnlocked ~= true
            value.doorUnlocked = true
            if firstUnlock then
                U().say(actor, "I'm at the garage. Door's unlocked. Mind the leg.")
            end
        end
    end
    syncShelter(actor, not value.rescued and not value.doorOpened)
    if value.rescued then
        if nearby(actor, player, 6)
            and current >= number(value.nextAfterAt, 0) then
            local index = (number(value.afterIndex, 0) % #AFTER) + 1
            value.afterIndex = index
            value.nextAfterAt = current + 100000
            U().say(actor, AFTER[index])
        end
        return true, "garage_rescued"
    end
    local medicalSession = SC.MedicalUI
        and type(SC.MedicalUI.current) == "function"
        and SC.MedicalUI.current() or nil
    if medicalSession and medicalSession.actor == actor
        and medicalSession.doctor == player then
        -- The player may use the ordinary body right-click Medical Check
        -- instead of Eli's conversation option. It opens the same native
        -- doctor/patient panel and spends the same real supplies.
        value.treatmentOpenedByPlayer = true
    end
    if not medicalSession or medicalSession.actor ~= actor then
        holdByWall(actor, value, current)
    end
    if value.treatmentOpenedByPlayer then
        local _, splinted, bandaged = injuryState(actor)
        value.splintReceived = value.splintReceived or splinted
        value.bandageReceived = value.bandageReceived or bandaged
        if value.splintReceived and value.bandageReceived then
            value.rescued = true
            value.stage = "treated"
            syncShelter(actor, false)
            if SC.Actor and type(SC.Actor.setMovement) == "function" then
                SC.Actor.setMovement(actor, "walk", { action = "stand_ground",
                    reason = "garage_rescue_treated" })
            end
            if SC.Factions and type(SC.Factions.forceStanding) == "function" then
                SC.Factions.forceStanding(group.id, "Trusted")
            end
            U().say(actor, "Splint holds. Bandage is clean. I owe you my next mile.")
            return true, "garage_treated_with_player_supplies"
        end
    end
    if nearby(actor, player, 5)
        and current >= number(value.nextLocalLineAt, 0) then
        group.discovered = true
        local index = (number(value.painIndex, 0) % #PAIN) + 1
        value.painIndex = index
        value.nextLocalLineAt = current + 42000
        U().say(actor, PAIN[index])
    end
    return true, value.stage or "garage_waiting"
end

function Rescue.intentFor(actor, player, snapshot, group)
    local value = valueFor(group)
    if not value then return nil end
    -- Inside the sealed garage he should stay on the wall. If a zombie gets
    -- through the opened door before treatment, he may defend himself.
    if not value.rescued and not value.doorOpened then
        return { mode = "garage_broken_leg_wait", priority = 90 }
    end
    local threats = snapshot and (number(snapshot.threatCount)
        or #(snapshot.threats or {})) or 0
    if threats > 0 then return { mode = "zombie_defense", priority = 18 } end
    if not value.rescued then
        return { mode = "garage_broken_leg_wait", priority = 90 }
    end
    return { mode = "oddball_idle", priority = 28 }
end

function Rescue.update(actor, player, runtime, intent, group)
    local value = valueFor(group)
    if not value or not intent or intent.mode ~= "garage_broken_leg_wait" then
        return false, "garage_no_special_move"
    end
    holdByWall(actor, value, U().nowMs())
    return true, "garage_survivor_waiting"
end

function Rescue.menuOptions(group, player)
    local value = valueFor(group)
    local actor = actorFor(group)
    if not value or not nearby(actor, player, 5) then return {} end
    local options = {
        { id = "ask_accident", label = "Ask Eli what happened",
            enabled = true },
    }
    if not value.rescued then
        local splint, bandage = hasPlayerSupplies(player)
        local inReach = value.doorOpened == true
            and nearby(actor, player, SC.MedicalUI and SC.MedicalUI.RANGE or 1.9)
        options[#options + 1] = {
            id = "treat_leg", label = "Treat Eli's broken leg",
            enabled = inReach and splint and bandage,
            detail = not inReach and "Open the garage and get beside Eli"
                or not splint and "Bring a splint"
                or not bandage and "Bring a clean bandage"
                or "Use your splint and bandage in the medical panel",
        }
    else
        options[#options + 1] = { id = "recruit", label = "Invite Eli to join",
            enabled = true }
    end
    return options
end

function Rescue.action(group, action, player)
    local value = valueFor(group)
    if not value then return false, "wrong_oddball" end
    local actor = actorFor(group)
    if action == "hurt" then
        if actor then U().say(actor, "I'm down already. Save the next swing for the dead.") end
        return true, "garage_survivor_warned"
    end
    if not nearby(actor, player, 5) then return false, "garage_survivor_too_far" end
    if action == "ask_accident" then
        U().say(actor, "Engine hoist slipped. My brother would call that poetic justice. He never liked that truck.")
        return true, "garage_accident_explained"
    elseif action == "treat_leg" then
        if value.rescued then return false, "garage_already_treated" end
        if not value.doorOpened
            or not nearby(actor, player, SC.MedicalUI and SC.MedicalUI.RANGE or 1.9) then
            return false, "garage_patient_out_of_reach"
        end
        local splint, bandage = hasPlayerSupplies(player)
        if not splint or not bandage then
            U().say(actor, not splint and "Please find a splint. Bone first."
                or "Need a clean bandage too. This cut's still open.")
            return false, not splint and "garage_splint_missing"
                or "garage_bandage_missing"
        end
        if not SC.MedicalUI or type(SC.MedicalUI.open) ~= "function" then
            return false, "garage_medical_panel_unavailable" end
        local opened, reason = SC.MedicalUI.open(actor, player)
        if opened ~= true then return false, reason end
        value.treatmentOpenedByPlayer = true
        U().say(actor, "Easy. It's the left leg. Wrap the cut, then splint the break.")
        return true, "garage_medical_panel_opened"
    elseif action == "recruit" then
        if not value.rescued then return false, "garage_treatment_required" end
        local recruited = SC.FactionRecruitment
            and type(SC.FactionRecruitment.ask) == "function"
            and SC.FactionRecruitment.ask(group.id, player, false)
        if recruited then
            value.stage = "recruited"
            U().say(actor, "Sure. Somebody ought to keep your wheels turning.")
            return true, "garage_recruitment_started"
        end
        return false, "garage_recruitment_unavailable"
    end
    return false, "unknown_garage_action"
end

function Rescue.canRecruit(group)
    local value = valueFor(group)
    return value ~= nil and value.rescued == true,
        value and value.rescued and "garage_survivor_recovered"
            or "garage_treatment_required"
end

function Rescue.zombiesIgnore(actor, group)
    local value = valueFor(group)
    return value ~= nil and value.rescued ~= true
        and value.doorOpened ~= true and rescueDoor(value) ~= nil
end

function Rescue.avoidsZombieCombat(actor, group)
    local value = valueFor(group)
    return value ~= nil and value.rescued ~= true
        and value.doorOpened ~= true
end

return Rescue
