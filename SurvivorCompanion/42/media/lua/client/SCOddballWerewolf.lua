-- SPDX-License-Identifier: MIT
-- Dalton's calendar chooses the turning night. He uses navigation to enter a
-- real cellar; the player boards its real door through normal game controls.

local SC = SurvivorCompanion
SC.OddballWerewolf = SC.OddballWerewolf or {}
local Werewolf = SC.OddballWerewolf
local ID = "werewolf_dalton_reese"

local function U() return SC.GameplayUtil end

local function ageHours()
    local time = type(getGameTime) == "function" and getGameTime() or nil
    local hours = time and select(1, U().call(time, "getWorldAgeHours"))
    return tonumber(hours)
end

local function story(group)
    local value = type(group) == "table" and group.oddball or nil
    if type(value) ~= "table" or value.id ~= ID then return nil end
    value.stage = value.stage or "daytime"
    return value
end

local function actorFor(group)
    local member = group and group.members and group.members[1]
    local record = member and member.actorId and SC.Registry
        and SC.Registry.byId(member.actorId) or nil
    return record and record.actor and U().isValidActor(record.actor)
        and record.actor or nil
end

local function nearPoint(player, point, radius)
    local x, y, z = U().position(player)
    return x ~= nil and type(point) == "table"
        and z == (point.z or 0)
        and (x - point.x) ^ 2 + (y - point.y) ^ 2 <= radius * radius
end

local function cellarDoor(value)
    local post = value and value.site and value.site.cellarDoor
    local square = post and U().gridSquare(post.x, post.y, post.z or 0)
    local objects = square and select(1, U().call(square, "getObjects"))
    if not objects or not SC.NativeList then return nil end
    local object = SC.NativeList.get(objects, post.objectIndex)
    if object and U().instanceOf(object, "IsoDoor") then return object end
    for index = 0, SC.NativeList.size(objects) - 1 do
        object = SC.NativeList.get(objects, index)
        if U().instanceOf(object, "IsoDoor") then return object end
    end
    return nil
end

local function planksOnDoor(value)
    local door = cellarDoor(value)
    if not door then return 0 end
    local count = 0
    for _, method in ipairs({ "getBarricadeOnSameSquare",
        "getBarricadeOnOppositeSquare" }) do
        local barricade = select(1, U().call(door, method))
        local planks = barricade and select(1,
            U().call(barricade, "getNumPlanks"))
        count = math.max(count, tonumber(planks) or 0)
    end
    return count
end

function Werewolf.canTalkThroughDoor(group, player)
    local value = story(group)
    return value and actorFor(group) and value.site
        and nearPoint(player, value.site.cellarDoor, 3)
        and planksOnDoor(value) > 0 or false
end

local function convert(group)
    local value = story(group)
    if not value or value.stage == "turned" then return false end
    if value.turnPending ~= true then
        local actor = actorFor(group)
        if not actor then return false, "dalton_actor_missing" end
        if type(addZombiesInOutfit) ~= "function"
            or not SC.Actor or type(SC.Actor.remove) ~= "function" then
            return false, "native_zombie_conversion_unavailable"
        end
        local x, y, z = U().position(actor)
        if not x then return false, "turn_location_unavailable" end
        local removed = SC.Actor.remove(actor)
        if not removed then return false, "dalton_removal_failed" end
        local member = group.members and group.members[1]
        if member then member.actorId, member.alive = nil, false end
        value.turnPosition = { x = math.floor(x), y = math.floor(y),
            z = math.floor(z or 0) }
        value.turnPending = true
    end
    local post = value.turnPosition
    if not post then return false, "turn_location_missing" end
    local okay, list = pcall(addZombiesInOutfit,
        post.x, post.y, post.z, 1, "Hunter", 0)
    if not okay or not list or not SC.NativeList
        or SC.NativeList.size(list) < 1 then
        return false, "zombie_spawn_pending"
    end
    local zombie = SC.NativeList.get(list, 0)
    local data = zombie and U().modData(zombie)
    if data then data.lfDaltonReese = group.id end
    value.stage = "turned"
    value.turnPending = false
    group.lifecycle = "destroyed"
    if SC.Oddballs and type(SC.Oddballs.retire) == "function" then
        SC.Oddballs.retire(group, "turned")
    end
    return true, "dalton_turned_behind_the_boards"
end

function Werewolf.onSpawn(group, actor)
    local value = story(group)
    if not value or not actor then return false, "dalton_unavailable" end
    local hours = ageHours()
    if hours and value.turnHour == nil then
        local hash = U().stableHash and U().stableHash(group.id) or 0
        value.turnHour = (math.floor(hours / 24) + 2 + hash % 3) * 24 + 20
    end
    return true, "dalton_waiting_for_night"
end

function Werewolf.pulse(group, player)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    if value.turnPending == true then return convert(group) end
    if value.stage == "turned" or value.stage == "gone" then
        return true, value.stage
    end
    local actor = actorFor(group)
    if actor and player and U().distance(actor, player) <= 7
        and U().canSee(player, actor) == true
        and value.greeted ~= true then
        value.greeted = true
        group.discovered = true
        U().say(actor, "A raccoon bit me. Full moon Friday. Lock it from outside.")
    end
    local hours = ageHours()
    if not hours or not actor then return true, "clock_or_actor_unavailable" end
    local clock = hours % 24
    local dusk = clock >= 18 or clock < 5
    if dusk and (value.stage == "daytime" or value.stage == "returned") then
        value.stage = "entering"
        U().say(actor,
            "If I start howling, don't you open that door. Board it tight.")
    end
    local _, _, actorZ = U().position(actor)
    if value.stage == "entering" and value.site and value.site.cellar
        and actorZ == (value.site.cellar.z or 0)
        and U().distance(actor, value.site.cellar) <= 2 then
        value.stage = "cellar"
    end
    if (value.stage == "cellar" or value.stage == "entering"
        or value.stage == "leaving")
        and hours >= (tonumber(value.turnHour)
        or math.huge) then
        return convert(group)
    end
    if not dusk and value.stage == "cellar" then
        value.stage = "leaving"
        U().say(actor, "Morning. Still me. Take those boards down.")
    end
    if value.stage == "leaving" and planksOnDoor(value) == 0
        and value.site and value.site.spawn
        and actorZ == (value.site.spawn.z or 0)
        and U().distance(actor, value.site.spawn) <= 2 then
        value.stage = "returned"
    end
    if value.stage == "exiling" and value.site and value.site.woods
        and U().distance(actor, value.site.woods) <= 3
        and player and U().canSee(player, actor) == false
        and SC.Actor and type(SC.Actor.remove) == "function" then
        local removed = SC.Actor.remove(actor)
        if removed then
            local member = group.members and group.members[1]
            if member then member.actorId, member.alive = nil, false end
            group.lifecycle, value.stage = "destroyed", "gone"
            if SC.Oddballs and type(SC.Oddballs.retire) == "function" then
                SC.Oddballs.retire(group, "left_for_the_woods")
            end
            return true, "dalton_left_for_the_woods"
        end
    end
    return true, value.stage
end

function Werewolf.intentFor(actor, player, snapshot, group)
    local value = story(group)
    if not value then return nil end
    if group.standing == "Hostile" then
        return { mode = "hostile", priority = 110 }
    end
    local threats = type(snapshot) == "table"
        and (tonumber(snapshot.threatCount) or #(snapshot.threats or {})) or 0
    if threats > 0 then return { mode = "zombie_defense", priority = 18 } end
    if value.stage == "entering" or value.stage == "leaving"
        or value.stage == "exiling" then
        return { mode = "werewolf_walk", priority = 45 }
    end
    return { mode = "oddball_idle", priority = 28 }
end

function Werewolf.update(actor, player, runtime, intent, group)
    if not intent or intent.mode ~= "werewolf_walk" then
        return false, "dalton_idle"
    end
    local value = story(group)
    local post = value.stage == "entering" and value.site.cellar
        or value.stage == "leaving" and planksOnDoor(value) == 0
            and value.site.spawn
        or value.stage == "exiling" and value.site.woods or nil
    if not post then return true, "cellar_door_still_barricaded" end
    local _, _, actorZ = U().position(actor)
    if actorZ == (post.z or 0) and U().distance(actor, post) <= 2 then
        return true, "dalton_arrived"
    end
    local square = U().gridSquare(post.x, post.y, post.z or 0)
    if not square then return false, "dalton_route_unloaded" end
    if not SC.Navigation or type(SC.Navigation.request) ~= "function" then
        return false, "navigation_unavailable"
    end
    return SC.Navigation.request(actor, square, "walk", {
        action = "faction_dalton_shelter", arrivalDistance = 2 })
end

function Werewolf.canRecruit()
    return false, "dalton_fears_the_bite"
end

function Werewolf.menuOptions(group, player)
    local value = story(group)
    local actor = actorFor(group)
    if not value or not actor or group.standing == "Hostile" then return {} end
    local close = player and U().distance(actor, player) <= 7
        and U().canSee(player, actor) == true
        or Werewolf.canTalkThroughDoor(group, player)
    if not close then return {} end
    local options = { { id = "ask_bite",
        label = "Ask Dalton about the bite", enabled = true } }
    if value.stage ~= "exiling" and value.stage ~= "turned"
        and value.stage ~= "gone" then
        options[#options + 1] = { id = "send_to_woods",
            label = "Let Dalton walk into the woods",
            enabled = value.site and value.site.woods ~= nil }
    end
    return options
end

function Werewolf.action(group, action, player)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    if action == "hurt" then
        value.stage = "hostile"
        return SC.Factions.forceStanding(group.id, "Hostile")
    end
    local actor = actorFor(group)
    if not actor or not player or not (U().distance(actor, player) <= 7
        or Werewolf.canTalkThroughDoor(group, player)) then
        return false, "dalton_too_far"
    end
    if action == "ask_bite" then
        U().say(actor, value.stage == "cellar"
            and "The boards are good. Keep them there until dawn."
            or "A raccoon, I said. Doesn't explain why the wound went black.")
        return true, "dalton_bite_explained"
    end
    if action == "send_to_woods" and value.stage ~= "turned"
        and value.stage ~= "gone" then
        value.stage = "exiling"
        U().say(actor, "No one has to watch what happens to me out there.")
        return true, "dalton_exiled_to_woods"
    end
    return false, "unknown_dalton_choice"
end

return Werewolf
