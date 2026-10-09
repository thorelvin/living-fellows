-- SPDX-License-Identifier: MIT
-- Mister Buttons is a real named hen. The radio parts are exact inventory
-- transfers, and a cockerel must be physically brought to her kitchen.

local SC = SurvivorCompanion
SC.OddballGideon = SC.OddballGideon or {}
local Gideon = SC.OddballGideon
local ID = "gideon_mister_buttons"
local HEN = { kind = "hen", breed = "rhodeisland",
    name = "Mister Buttons" }
local PARTS = { ["Base.HamRadio1"] = 1,
    ["Base.Battery"] = 4, ["Base.ElectronicsScrap"] = 5 }

local function U() return SC.GameplayUtil end
local function story(group)
    local value = type(group) == "table" and group.oddball or nil
    if type(value) ~= "table" or value.id ~= ID then return nil end
    value.stage = value.stage or "oracle"
    return value
end
local function actorFor(group)
    local member = group and group.members and group.members[1]
    local record = member and member.actorId and SC.Registry
        and SC.Registry.byId(member.actorId) or nil
    return record and record.actor and U().isValidActor(record.actor)
        and record.actor or nil
end
local function near(group, player)
    local actor = actorFor(group)
    return actor and player and U().distance(actor, player) <= 7
        and U().canSee(player, actor) == true
end
local function ageHours()
    local clock = type(getGameTime) == "function" and getGameTime() or nil
    return tonumber(clock and select(1,
        U().call(clock, "getWorldAgeHours")))
end
local function henStatus(group, player)
    local animal, record = SC.OddballAnimals.find(group, 1)
    if record and player then
        local inventory = U().inventory(player)
        for _, item in ipairs(inventory and U().inventoryItemsDeep(inventory,
            220, 10) or {}) do
            local carried = select(1, U().call(item, "getAnimal"))
            local id = carried and select(1,
                U().call(carried, "getAnimalID"))
            if tonumber(id) == tonumber(record.id) then
                return "carried_by_player", carried
            end
        end
    end
    if animal then return "present", animal end
    if record and record.dead then return "dead" end
    return record and "unloaded" or "unseeded"
end
local function cockerelInKitchen(value)
    local post = value.site and value.site.spawn
    if not post or not SC.NativeList then return nil end
    for dx = -2, 2 do
        for dy = -2, 2 do
            local square = U().gridSquare(post.x + dx, post.y + dy,
                post.z or 0)
            local moving = square and select(1,
                U().call(square, "getMovingObjects"))
            if moving then
                for index = 0, math.min(31,
                    SC.NativeList.size(moving) - 1) do
                    local animal = SC.NativeList.get(moving, index)
                    if select(1, U().call(animal, "getAnimalType"))
                        == "cockerel" then return animal end
                end
            end
        end
    end
    return nil
end
local function exactParts(player)
    local inventory = U().inventory(player)
    if not inventory then return nil end
    local found = { ["Base.HamRadio1"] = {}, ["Base.Battery"] = {},
        ["Base.ElectronicsScrap"] = {} }
    for _, item in ipairs(U().inventoryItemsDeep(inventory, 320, 12)) do
        local kind = U().itemType(item)
        local bucket = found[kind]
        if bucket and #bucket < PARTS[kind] then
            bucket[#bucket + 1] = item
        end
    end
    local selected = {}
    for _, kind in ipairs({ "Base.HamRadio1", "Base.Battery",
        "Base.ElectronicsScrap" }) do
        if #found[kind] < PARTS[kind] then return nil end
        for _, item in ipairs(found[kind]) do
            selected[#selected + 1] = item
        end
    end
    return selected
end
local function kitchenDoor(value)
    local post = value.site and value.site.kitchenDoor
    local square = post and U().gridSquare(post.x, post.y, post.z or 0)
    local objects = square and select(1, U().call(square, "getObjects"))
    local door = objects and SC.NativeList
        and SC.NativeList.get(objects, post.objectIndex) or nil
    return door and U().instanceOf(door, "IsoDoor") and door or nil
end

function Gideon.onSpawn(group, actor)
    local value = story(group)
    if not value or not actor then return false, "gideon_unavailable" end
    if SC.OddballAnimals.status(group, 1) == "unseeded" then
        local post = value.site and value.site.animalSpawns
            and value.site.animalSpawns[1]
        if post then SC.OddballAnimals.spawn(group, 1, HEN, post) end
    end
    local door = kitchenDoor(value)
    if door and select(1, U().call(door, "IsOpen")) == true then
        U().call(door, "ToggleDoor", actor)
    end
    return true, "buttons_kitchen_ready"
end

function Gideon.pulse(group, player, current)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    local actor = actorFor(group)
    if not actor then return false, "gideon_unloaded" end
    if SC.OddballAnimals.status(group, 1) == "unseeded"
        and current >= (tonumber(value.nextHenRetryAt) or 0) then
        value.nextHenRetryAt = current + 30000
        local post = value.site and value.site.animalSpawns
            and value.site.animalSpawns[1]
        if post then SC.OddballAnimals.spawn(group, 1, HEN, post) end
    end
    local status, hen = henStatus(group, player)
    if status == "carried_by_player" and value.henTaken ~= true then
        value.henTaken = true
        U().say(actor, "Put Mister Buttons down! She cannot speak through a sack!")
    elseif status == "present" and value.henTaken == true
        and hen and U().distance(hen, actor) <= 6 then
        value.henTaken = false
        SC.Factions.adjustStanding(group.id, 12, "buttons_returned")
        U().say(actor, "She forgives you. It was a long argument, but she forgives you.")
    elseif status == "dead" and value.henDead ~= true then
        value.henDead = true
        value.stage = "mourning"
        U().say(actor, "The stars went quiet. So did she.")
    end
    if near(group, player) and value.greeted ~= true then
        value.greeted = true
        group.discovered = true
        U().say(actor,
            "Mister Buttons says you can stay. She clucked twice. That means north. Or batteries.")
    end
    local hours = ageHours()
    if value.stage == "ship_ready" and hours
        and hours >= (tonumber(value.launchHour) or math.huge) then
        value.stage = "no_ship"
        U().say(actor,
            "No lights. No ship. She says the weather was poor between worlds. Mostly she says cluck.")
    end
    if status == "present" then
        SC.OddballAnimals.follow(group, 1, actor, current)
    end
    return true, value.stage
end

function Gideon.pulseRecruited(group, actor, player, current)
    SC.OddballAnimals.follow(group, 1, actor, current)
    if story(group) and story(group).cockerelGiven then
        SC.OddballAnimals.follow(group, 2, actor, current)
    end
    return true, "birds_near_keeper"
end

function Gideon.intentFor(actor, player, snapshot, group)
    if not story(group) then return nil end
    if group.standing == "Hostile" then
        return { mode = "hostile", priority = 110 }
    end
    local threats = type(snapshot) == "table"
        and (tonumber(snapshot.threatCount) or #(snapshot.threats or {})) or 0
    if threats > 0 then return { mode = "zombie_defense", priority = 18 } end
    return { mode = "oddball_idle", priority = 28 }
end

function Gideon.canRecruit(group)
    local value = story(group)
    return value and value.cockerelGiven == true
        and value.henDead ~= true and group.standing == "Trusted"
        or false, "bring_buttons_a_real_cockerel"
end

function Gideon.menuOptions(group, player)
    local value = story(group)
    if not value or not near(group, player) then return {} end
    return {
        { id = "ask_buttons", label = "Ask what Mister Buttons says",
            enabled = true },
        { id = "bring_parts", label = "Bring the ship's radio parts",
            enabled = value.stage == "oracle" and exactParts(player) ~= nil },
        { id = "introduce_cockerel", label = "Introduce the cockerel in the kitchen",
            enabled = value.henDead ~= true and value.cockerelGiven ~= true
                and cockerelInKitchen(value) ~= nil },
        { id = "recruit", label = "Invite Gideon and Buttons to join",
            enabled = Gideon.canRecruit(group) == true },
    }
end

function Gideon.action(group, action, player)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    if action == "hurt" then
        return SC.Factions.forceStanding(group.id, "Hostile")
    end
    if action == "animal_hurt" then
        value.stage = "mourning"
        value.henDead = true
        return SC.Factions.forceStanding(group.id, "Hostile")
    end
    if not near(group, player) then return false, "kitchen_too_far" end
    local actor = actorFor(group)
    if action == "ask_buttons" then
        U().say(actor, "Her people are coming. She just needs a radio and a little faith.")
        return true, "buttons_oracle_consulted"
    end
    if action == "bring_parts" and value.stage == "oracle" then
        local parts = exactParts(player)
        if not parts then return false, "ship_parts_missing" end
        local received = {}
        local destination = U().inventory(actor)
        for _, item in ipairs(parts) do
            local source = select(1, U().call(item, "getContainer"))
            if not source or not U().transferItemVerified(source,
                destination, item) then
                for index = #received, 1, -1 do
                    local record = received[index]
                    U().transferItemVerified(destination,
                        record.source, record.item)
                end
                return false, "ship_parts_transfer_failed"
            end
            received[#received + 1] = { item = item, source = source }
        end
        local hours = ageHours()
        value.stage = "ship_ready"
        value.launchHour = hours and (math.floor(hours / 24) + 1) * 24
            + 20 or nil
        SC.Factions.adjustStanding(group.id, 20, "real_radio_parts_delivered")
        U().say(actor,
            "Radio, four batteries, five pieces of scrap. Her people have no excuse now.")
        return true, "exact_ship_parts_delivered"
    end
    if action == "introduce_cockerel" and value.henDead ~= true
        and value.cockerelGiven ~= true then
        local bird = cockerelInKitchen(value)
        if not bird then return false, "cockerel_not_in_kitchen" end
        local adopted, reason = SC.OddballAnimals.adopt(group, 2,
            bird, "cockerel")
        if not adopted then return false, reason end
        value.cockerelGiven = true
        SC.Factions.forceStanding(group.id, "Trusted")
        U().say(actor,
            "A companion for Mister Buttons. She says you have a place among the stars. And here.")
        return true, "real_cockerel_joined_buttons"
    end
    if action == "recruit" and Gideon.canRecruit(group) == true
        and SC.FactionRecruitment then
        local asked, reason = SC.FactionRecruitment.ask(group.id, player, false)
        if not asked then return false, reason end
        return SC.FactionRecruitment.startTrial(group.id, player, false)
    end
    return false, "oracle_choice_unavailable"
end

return Gideon
