-- SPDX-License-Identifier: MIT
-- Caleb's warning has a real locked door and twenty real zombies behind it.
local SC = SurvivorCompanion
SC.OddballSurvivalist = SC.OddballSurvivalist or {}
local Survivalist = SC.OddballSurvivalist
local ID = "survivalist_locked_horde"
local WARNINGS = {
    "Quiet. There's twenty of them in that room. Don't touch the door.",
    "How I got them in there is my business. Keep your hand off that latch.",
    "That lock is the only reason we're having this conversation.",
    "You hear scratching? Good. Means the door is still doing its job.",
}
local clickHookInstalled = false

local function U() return SC.GameplayUtil end
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
    local post = value and value.site and value.site.roomDoor
    local square = post and U().gridSquare(post.x, post.y, post.z or 0)
    local objects = square and select(1, U().call(square, "getObjects"))
    local door = objects and SC.NativeList
        and SC.NativeList.get(objects, post.objectIndex)
    return door and U().instanceOf(door, "IsoDoor") and door or nil
end
local function near(group, player, radius)
    local actor = actorFor(group)
    return actor and player and U().distance(actor, player) <= radius
        and U().canSee(player, actor) == true
end
local function retreatPost(actor, player)
    local ax, ay, az = U().position(actor)
    local px, py = U().position(player)
    if not ax then return nil end
    local best, score
    for radius = 12, 24, 4 do
        for index = 0, 15 do
            local theta = index * math.pi / 8
            local x = math.floor(ax + math.cos(theta) * radius)
            local y = math.floor(ay + math.sin(theta) * radius)
            local tile = U().gridSquare(x, y, az or 0)
            local room = tile and select(1, U().call(tile, "getRoom"))
            if tile and room == nil and U().isSafeSpawnSquare(tile) then
                local separation = px and (x - px) ^ 2 + (y - py) ^ 2
                    or radius * radius
                if not score or separation > score then
                    best, score = { x = x, y = y, z = az or 0 }, separation
                end
            end
        end
    end
    return best
end
local function flee(group, player, line)
    local value = story(group)
    if not value or value.stage == "fleeing" or value.stage == "gone" then
        return false
    end
    value.stage = "fleeing"
    value.fleeStartedAt = U().nowMs()
    local actor = actorFor(group)
    value.retreat = actor and retreatPost(actor, player) or nil
    if actor then U().say(actor, line or "I told you. I'm leaving!") end
    group.discovered = true
    return true
end

function Survivalist.matchesDoor(group, object, player)
    local value = story(group)
    if not value or value.stage == "gone" or value.stage == "fleeing"
        or not object or not player then
        return false
    end
    local door = doorFor(value)
    local post = value.site and value.site.roomDoor
    local x, y, z = U().position(player)
    return door ~= nil and door == object and x ~= nil and post ~= nil
        and math.floor(z or 0) == (post.z or 0)
        and (x - post.x) ^ 2 + (y - post.y) ^ 2 <= 9
end

function Survivalist.onObjectLeftMouseButtonDown(object)
    if not object or not U().instanceOf(object, "IsoDoor")
        or not SC.Factions or type(getSpecificPlayer) ~= "function" then
        return end
    local count = 1
    if type(getNumActivePlayers) == "function" then
        local okay, active = pcall(getNumActivePlayers)
        if okay and tonumber(active) then
            count = math.max(1, math.min(4, math.floor(active)))
        end
    end
    for _, group in ipairs(SC.Factions.list(false) or {}) do
        for index = 0, count - 1 do
            local player = getSpecificPlayer(index)
            if Survivalist.matchesDoor(group, object, player) then
                Survivalist.action(group, "touch_door", player)
                return
            end
        end
    end
end

function Survivalist.install()
    if clickHookInstalled then return true end
    local event = Events and Events.OnObjectLeftMouseButtonDown
    if not event or type(event.Add) ~= "function" then return false end
    local okay = pcall(event.Add, Survivalist.onObjectLeftMouseButtonDown)
    clickHookInstalled = okay
    return okay
end

function Survivalist.remove()
    if clickHookInstalled and Events and Events.OnObjectLeftMouseButtonDown
        and type(Events.OnObjectLeftMouseButtonDown.Remove) == "function" then
        pcall(Events.OnObjectLeftMouseButtonDown.Remove,
            Survivalist.onObjectLeftMouseButtonDown)
    end
    clickHookInstalled = false
end

function Survivalist.onSpawn(group, actor)
    Survivalist.install()
    local value = story(group)
    local door = doorFor(value)
    if not value or not door or not actor then
        return false, "sealed_room_unavailable"
    end
    if select(1, U().call(door, "IsOpen")) == true then
        return false, "sealed_door_open"
    end
    U().call(door, "setLocked", true)
    U().call(door, "setLockedByKey", true)
    if select(1, U().call(door, "isLocked")) ~= true then
        return false, "sealed_door_could_not_lock"
    end
    if value.hordeSeedAttempted == true then return true, "horde_already_seeded" end
    local posts = value.site and value.site.hordeSpawns or {}
    if #posts < 4 or type(addZombiesInOutfit) ~= "function"
        or not SC.NativeList then return false, "horde_room_unavailable" end
    value.hordeSeedAttempted = true
    value.hordeCount = 0
    for index = 1, 20 do
        local post = posts[((index - 1) % #posts) + 1]
        local okay, list = pcall(addZombiesInOutfit,
            post.x, post.y, post.z or 0, 1, "Survivalist", 0)
        local zombie = okay and list and SC.NativeList.get(list, 0) or nil
        if zombie then
            value.hordeCount = value.hordeCount + 1
            local data = U().modData(zombie)
            if data then data.lfSealedHordeGroupId = group.id end
        end
    end
    if value.hordeCount ~= 20 and SC.Diagnostics
        and type(SC.Diagnostics.report) == "function" then
        SC.Diagnostics.report("oddballs", group.id,
            "sealed horde spawned fewer than twenty zombies",
            tostring(value.hordeCount))
    end
    return value.hordeCount > 0, "sealed_horde_seeded"
end

function Survivalist.pulse(group, player, current)
    Survivalist.install()
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    local door = doorFor(value)
    if not value.sealBroken and (door == nil
        or select(1, U().call(door, "IsOpen")) == true
        or select(1, U().call(door, "isLocked")) == false
        or value.roomGuardDone == true) then
        value.sealBroken = true
        if SC.OddballRoomGuard then SC.OddballRoomGuard.release(group.id) end
        flee(group, player, "The door! You're on your own!")
    end
    local actor = actorFor(group)
    if value.stage == "fleeing" then
        if actor and player and U().distance(actor, player) >= 22 then
            value.stage = "gone"
        end
        return true, value.stage
    end
    if actor and player and near(group, player, 8)
        and current >= (tonumber(value.nextWarningAt) or 0) then
        group.discovered = true
        local index = ((tonumber(value.warningIndex) or 0) % #WARNINGS) + 1
        value.warningIndex = index
        U().say(actor, WARNINGS[index])
        value.nextWarningAt = current + (index == 1 and 12000 or 35000)
    end
    return true, "sealed_room_warning"
end

function Survivalist.intentFor(actor, player, snapshot, group)
    local value = story(group)
    if not value then return nil end
    if value.stage == "fleeing" and value.retreat then
        return { mode = "survivalist_flee", priority = 95 }
    end
    local threats = snapshot and (tonumber(snapshot.threatCount)
        or #(snapshot.threats or {})) or 0
    if threats > 0 then return { mode = "zombie_defense", priority = 18 } end
    return { mode = "oddball_idle", priority = 28 }
end

function Survivalist.update(actor, player, runtime, intent, group)
    if not intent or intent.mode ~= "survivalist_flee" then
        return false, "survivalist_holding_position"
    end
    local value = story(group)
    local post = value and value.retreat
    local target = post and U().gridSquare(post.x, post.y, post.z or 0)
    if not target or not SC.Navigation then return false, "retreat_unavailable" end
    if U().distance(actor, target) <= 2 then
        value.stage = "gone"
        return true, "survivalist_escaped"
    end
    return SC.Navigation.request(actor, target, "run", {
        action = "survivalist_escape", targetSquare = target,
        arrivalDistance = 2, continuousApproach = true })
end

function Survivalist.menuOptions(group, player)
    local value = story(group)
    if not value or not near(group, player, 7)
        or value.stage == "fleeing" or value.stage == "gone" then return {} end
    return {
        { id = "ask_secret", label = "Ask how he trapped twenty zombies",
            enabled = true },
        { id = "ask_door", label = "Ask about the locked door",
            enabled = true },
    }
end

function Survivalist.action(group, action, player)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    if action == "touch_door" then
        if not player or not doorFor(value) then
            return false, "sealed_door_unavailable" end
        flee(group, player, "You touched it. I told you not to. I'm gone!")
        return true, "survivalist_fled_on_door_touch"
    end
    local actor = actorFor(group)
    if action == "hurt" then
        flee(group, player, "Keep your hands to yourself. I'm out!")
        return true, "survivalist_fled"
    end
    if not actor or not near(group, player, 7) then
        return false, "survivalist_too_far" end
    if action == "ask_secret" then
        U().say(actor, "How? That's a secret. You want to live, leave it alone.")
        return true, "secret_kept"
    elseif action == "ask_door" then
        U().say(actor, "Twenty mouths. One lock. Don't make me explain twice.")
        return true, "door_warning"
    end
    return false, "unknown_survivalist_action"
end

function Survivalist.canRecruit()
    return false, "survivalist_guards_his_secret"
end

return Survivalist
