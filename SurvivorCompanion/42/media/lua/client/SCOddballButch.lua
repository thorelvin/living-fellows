-- SPDX-License-Identifier: MIT
-- The friendly counter and the forbidden back room are one faction encounter.
-- Human combat and all movement remain with the normal faction/navigation code.

local SC = SurvivorCompanion
SC.OddballButch = SC.OddballButch or {}
local Butch = SC.OddballButch
local ID = "butcher_ambrose_kittredge"
local followUntil = {}

local lines = {
    greet = "Prime cuts. Locally sourced. Very, very locally.",
    offer = "You're looking lean, friend. Sit. Let me fix you a plate.",
    warn = "Don't go in the back. Health code.",
    reveal = "Everybody's meat now. Only question is who holds the cleaver.",
    taunt = "I never waste a thing. Not one thing.",
}

local function U() return SC.GameplayUtil end

local function number(value)
    if type(value) == "number" then return value end
    if type(value) == "string" then return tonumber(value) end
    return nil
end

local function story(group)
    local value = type(group) == "table" and group.oddball or nil
    if type(value) ~= "table" or value.id ~= ID then return nil end
    value.stage = value.stage or "unmet"
    return value
end

local function actorFor(group)
    local member = group and group.members and group.members[1]
    local record = member and member.actorId and SC.Registry
        and SC.Registry.byId(member.actorId)
    return record and record.actor or nil
end

local function speak(group, beat)
    local actor = actorFor(group)
    return actor and U().say(actor, lines[beat]) == true or false
end

local function distanceToPlayer(group, player)
    local actor = actorFor(group)
    local ax, ay, az = U().position(actor)
    local px, py, pz = U().position(player)
    if not ax or not px or az ~= pz then return math.huge end
    return math.sqrt((ax - px) ^ 2 + (ay - py) ^ 2)
end

local function insideStore(group, player)
    local bounds = group and group.house and group.house.bounds
    local x, y, z = U().position(player)
    local spawn = story(group).site and story(group).site.spawn
    if not bounds or not x or not spawn or z ~= (spawn.z or 0) then
        return false
    end
    return x >= bounds.x1 and x <= bounds.x2
        and y >= bounds.y1 and y <= bounds.y2
end

local backRooms = {
    freezer = true, storage = true, kitchen = true, butcherstorage = true,
    pantry = true, stockroom = true,
}

local function inBackRoom(group, player)
    if not insideStore(group, player) then return false end
    local square = U().squareOf(player)
    local room = select(1, U().call(square, "getRoom"))
    local name = select(1, U().call(room, "getName"))
    if type(name) ~= "string" then return false end
    name = string.lower(name)
    return backRooms[name] == true
        or string.find(name, "freezer", 1, true) ~= nil
end

local function findItem(actor, kind)
    local inventory = actor and U().inventory(actor)
    for _, item in ipairs(inventory and U().inventoryItemsDeep(inventory, 160, 8)
        or {}) do
        if U().itemType(item) == kind then return item end
    end
    return nil
end

local function hostile(group, value)
    if value.stage == "hostile" then return true end
    value.stage = "hostile"
    followUntil[group.id] = nil
    SC.Factions.forceStanding(group.id, "Hostile")
    speak(group, "reveal")
    return true
end

function Butch.onSpawn(group, actor)
    local value = story(group)
    if not value or not actor then return false, "butch_unavailable" end
    local inventory = U().inventory(actor)
    if not inventory then return false, "butch_inventory_unavailable" end
    local cleaver = findItem(actor, "Base.MeatCleaver")
    if not cleaver and value.equipmentSeeded ~= true then
        cleaver = U().addItem(inventory, "Base.MeatCleaver")
    end
    if value.equipmentSeeded ~= true and cleaver then
        for _ = 1, 4 do U().addItem(inventory, "Base.Steak") end
        value.equipmentSeeded = true
    end
    if cleaver then U().call(actor, "setPrimaryHandItem", cleaver) end
    return true, cleaver and "butch_ready" or "cleaver_removed"
end

function Butch.pulse(group, player, current)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    if value.stage == "hostile" then return true, "butch_hostile" end
    if value.stage == "unmet" and distanceToPlayer(group, player) <= 12 then
        value.stage = "welcoming"
        group.discovered = true
        speak(group, "greet")
    end
    if value.stage ~= "following_back" and inBackRoom(group, player) then
        value.stage = "following_back"
        followUntil[group.id] = current + 2000
        speak(group, "warn")
    elseif value.stage == "following_back" then
        followUntil[group.id] = followUntil[group.id] or current + 2000
        if current >= followUntil[group.id] then
            hostile(group, value)
        end
    end
    return true, value.stage
end

function Butch.intentFor(actor, player, snapshot, group)
    local value = story(group)
    if not value then return nil end
    if value.stage == "hostile" or group.standing == "Hostile" then
        return { mode = "hostile", priority = 110 }
    end
    local threatCount = type(snapshot) == "table"
        and (number(snapshot.threatCount) or #(snapshot.threats or {})) or 0
    if threatCount > 0 then return { mode = "zombie_defense", priority = 18 } end
    if value.stage == "following_back" then
        return { mode = "butch_follow", priority = 45 }
    end
    return { mode = "butch_counter", priority = 30 }
end

function Butch.update(actor, player, runtime, intent, group)
    if not intent or (intent.mode ~= "butch_follow"
        and intent.mode ~= "butch_counter") then return false end
    local target = intent.mode == "butch_follow" and U().squareOf(player)
        or story(group).site and story(group).site.spawn
    local square = type(target) == "table" and target.x ~= nil
        and U().gridSquare(target.x, target.y, target.z or 0) or target
    if not square then return true, "butch_target_unloaded" end
    local x, y, z = U().position(actor)
    local tx, ty, tz = U().position(square)
    if x and tx and z == tz and (x - tx) ^ 2 + (y - ty) ^ 2 <= 2.25 then
        return true, "butch_at_position"
    end
    if not SC.Navigation or type(SC.Navigation.request) ~= "function" then
        return false, "navigation_unavailable"
    end
    return SC.Navigation.request(actor, square, "walk", {
        action = "faction_butcher", arrivalDistance = 1.5 })
end

function Butch.canRecruit(group)
    return false, "butch_keeps_the_shop"
end

function Butch.menuOptions(group, player)
    local value = story(group)
    if not value then return {} end
    local nearby = distanceToPlayer(group, player) <= 4
    return { { id = "accept_steak", label = "Accept Butch's steak",
        enabled = nearby and value.gifted ~= true
            and value.stage ~= "hostile"
            and value.stage ~= "following_back"
            and findItem(actorFor(group), "Base.Steak") ~= nil,
        detail = "He says it is fresh. He will not say from where." } }
end

function Butch.action(group, action, player)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    if action == "hurt" then
        hostile(group, value)
        return true, "butch_attacked"
    end
    if action ~= "accept_steak" then return false, "unsupported_butch_action" end
    if distanceToPlayer(group, player) > 4 then return false, "too_far_away" end
    if value.gifted or value.stage == "hostile"
        or value.stage == "following_back" then return false, "offer_unavailable" end
    local steak = findItem(actorFor(group), "Base.Steak")
    local source = steak and select(1, U().call(steak, "getContainer"))
    local destination = U().inventory(player)
    if not source or not destination then return false, "steak_unavailable" end
    local moved, reason = U().transferItemVerified(source, destination, steak)
    if not moved then return false, reason or "steak_transfer_failed" end
    value.gifted = true
    speak(group, "offer")
    return true, "butch_steak_gifted"
end

return Butch
