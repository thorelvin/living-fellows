-- SPDX-License-Identifier: MIT
-- Elmer speaks a saved, ordered story while seated in a real chair. The
-- bedroom contains one tagged native zombie behind a real door.

local SC = SurvivorCompanion
SC.OddballElmer = SC.OddballElmer or {}
local Elmer = SC.OddballElmer
local ID = "man_in_the_chair"
local LINES = {
    "Ninth of July. I was mowing the lawn. Lawn looks good. Lawn still looks good.",
    "Mrs. Kettering came over to borrow the mower. Bit the mailman instead.",
    "The TV said stay inside. So I stayed inside. Then the TV stopped saying things.",
    "Army trucks on the bypass. Then no army trucks. Then the army, walking. Slow.",
    "They put a fence around the whole county. Fence keeps us in. Keeps nothing out.",
    "The helicopter came over every day. Never landed. Just made them all follow it.",
    "I counted them from the window. Got to four hundred. Then I counted backwards.",
    "My brother-in-law said they were only sick people. He hugged one. He was wrong.",
    "Saw a whole church walk out on a Sunday. Choir and all. Still singing, sort of.",
    "Twelve days on canned peaches. You can taste the can. You can taste the fear.",
    "The radio man kept saying help was coming. Then the radio man just breathed.",
    "Saw a cow on fire run down Main Street. Nobody chased it. Nobody could.",
    { "I have seen some shit. Some real shit. And then it got up and walked.",
        clean = "I have seen some things. Some real things. And then they got up and walked." },
    "Don't open the freezer at the Jay's. I mean it. Don't you open it.",
    "You blink, they're at the window. Blink again, they're in the kitchen. So I quit blinking.",
    "My wife's in the bedroom. She's quiet now. She's been quiet since Tuesday.",
    "...Who are you? How long have you been standing there?",
}
local FRAGMENTS = { "Lawn still looks good.", "Four hundred and one.",
    "Noon. The helicopter's late.", "Peaches.",
    "Don't open the bedroom." }

local function U() return SC.GameplayUtil end
local function story(group)
    local value = type(group) == "table" and group.oddball or nil
    if type(value) ~= "table" or value.id ~= ID then return nil end
    value.stage = value.stage or "telling"
    value.line = math.max(1, math.min(#LINES + 1,
        math.floor(tonumber(value.line) or 1)))
    return value
end
local function actorFor(group)
    local member = group and group.members and group.members[1]
    local record = member and member.actorId and SC.Registry
        and SC.Registry.byId(member.actorId) or nil
    return record and record.actor and U().isValidActor(record.actor)
        and record.actor or nil
end
local function near(group, player, radius)
    local actor = actorFor(group)
    return actor and player and U().distance(actor, player) <= radius
        and U().canSee(player, actor) == true
end
local function chairObject(value)
    local post = value.site and value.site.chair
    local square = post and U().gridSquare(post.x, post.y, post.z or 0)
    local objects = square and select(1, U().call(square, "getObjects"))
    return objects and SC.NativeList
        and SC.NativeList.get(objects, post.objectIndex) or nil
end
local function bedroomDoor(value)
    local post = value.site and value.site.bedroomDoor
    local square = post and U().gridSquare(post.x, post.y, post.z or 0)
    local objects = square and select(1, U().call(square, "getObjects"))
    local door = objects and SC.NativeList
        and SC.NativeList.get(objects, post.objectIndex) or nil
    return door and U().instanceOf(door, "IsoDoor") and door or nil
end
local function speak(actor, index)
    local line = LINES[index]
    if type(line) == "table" then
        line = U().config("profanityEnabled") == false and line.clean or line[1]
    end
    return line and U().say(actor, line)
end

function Elmer.onSpawn(group, actor)
    local value = story(group)
    if not value or not actor then return false, "elmer_unavailable" end
    local inventory = U().inventory(actor)
    if value.revolverSeeded ~= true and inventory then
        local gun = U().addItem(inventory, "Base.Revolver")
        if gun then
            U().call(gun, "setCurrentAmmoCount", 0)
            U().call(actor, "setPrimaryHandItem", gun)
            value.revolverSeeded = true
        end
    end
    if value.wifeSpawned ~= true then
        local post = value.site and value.site.bedroom
        local door = bedroomDoor(value)
        if not post or not door or type(addZombiesInOutfit) ~= "function"
            or not SC.NativeList then
            return false, "wife_bedroom_unavailable"
        end
        if select(1, U().call(door, "IsOpen")) == true then
            U().call(door, "ToggleDoor", actor)
            if select(1, U().call(door, "IsOpen")) == true then
                return false, "wife_bedroom_door_open"
            end
        end
        local okay, list = pcall(addZombiesInOutfit,
            post.x, post.y, post.z or 0, 1, "OfficeWorker", 0)
        local zombie = okay and list and SC.NativeList.get(list, 0) or nil
        if not zombie then return false, "wife_zombie_spawn_failed" end
        local data = U().modData(zombie)
        if data then data.lfElmerWifeGroupId = group.id end
        value.wifeSpawned = true
    end
    return true, "elmer_and_wife_ready"
end

function Elmer.pulse(group, player, current)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    local actor = actorFor(group)
    if not actor then return false, "elmer_unloaded" end
    if value.stage == "telling" and near(group, player, 8)
        and current >= (tonumber(value.nextLineAt) or 0) then
        local index = value.line
        speak(actor, index)
        group.discovered = true
        value.line = index + 1
        local hash = U().stableHash and U().stableHash(
            group.id .. ":story:" .. tostring(index)) or 0
        value.nextLineAt = current + 8000 + hash % 7001
        if index == #LINES then
            value.stage = "clear"
            SC.Factions.forceStanding(group.id, "Trusted")
        end
    elseif (value.stage == "fragments" or value.stage == "clear")
        and near(group, player, 8)
        and current >= (tonumber(value.nextFragmentAt) or 0) then
        value.nextFragmentAt = current + 50000
        local nextIndex = ((tonumber(value.fragmentIndex) or 0)
            % #FRAGMENTS) + 1
        value.fragmentIndex = nextIndex
        U().say(actor, FRAGMENTS[nextIndex])
    end
    return true, value.stage
end

function Elmer.onZombieDead(group, zombie)
    local value = story(group)
    local data = zombie and U().modData(zombie)
    if not value or type(data) ~= "table"
        or data.lfElmerWifeGroupId ~= group.id
        or value.wifeDead == true then return false end
    value.wifeDead = true
    if value.stage == "clear" or value.stage == "bedroom_warning" then
        local hash = U().stableHash and U().stableHash(group.id) or 0
        value.stage = hash % 2 == 0 and "grateful" or "silent"
        local actor = actorFor(group)
        if actor then
            U().say(actor, value.stage == "grateful"
                and "She was quiet since Tuesday. Thank you. I think I can leave now."
                or "I heard the shot. I don't have another story in me.")
        end
    end
    return true, "wife_really_put_to_rest"
end

function Elmer.intentFor(actor, player, snapshot, group)
    local value = story(group)
    if not value then return nil end
    local threat
    if type(snapshot) == "table" then
        for _, entry in ipairs(snapshot.threats or {}) do
            local zombie = entry.actor or entry.zombie
            if zombie and U().distance(actor, zombie) <= 3 then
                threat = zombie; break
            end
        end
    end
    if threat then
        if SC.NativeActions then SC.NativeActions.leaveSeating(actor) end
        return { mode = "zombie_defense", priority = 18 }
    end
    return { mode = "elmer_sit", priority = 38 }
end

function Elmer.update(actor, player, runtime, intent, group)
    if not intent or intent.mode ~= "elmer_sit" then
        return false, "elmer_is_talking"
    end
    local chair = chairObject(story(group))
    if not chair then return false, "armchair_unavailable" end
    if select(1, U().call(actor, "isSittingOnFurniture")) == true then
        return true, "elmer_in_chair"
    end
    local arrived, targets = U().directInteractionAccess(actor, chair)
    if not arrived then
        if not SC.Navigation or type(SC.Navigation.requestAny) ~= "function"
            or #targets == 0 then return false, "chair_access_missing" end
        return SC.Navigation.requestAny(actor, targets, "walk", {
            action = "elmer_approach_chair", object = chair,
            targetSquare = U().squareOf(chair),
            requireSameSquare = true, continuousApproach = true })
    end
    return U().move(actor, "walk", { action = "sit",
        object = chair, targetSquare = U().squareOf(chair) })
end

function Elmer.canRecruit(group)
    local value = story(group)
    return value and (value.stage == "clear" or value.stage == "grateful")
        and group.standing == "Trusted" or false,
        "let_elmer_finish_his_story"
end

function Elmer.menuOptions(group, player)
    local value = story(group)
    if not value or not near(group, player, 7) then return {} end
    if value.stage == "telling" then
        return { { id = "interrupt", label = "Talk over Elmer",
            enabled = true } }
    end
    if value.stage == "silent" then return {} end
    return {
        { id = "ask_bedroom", label = "Ask about the bedroom",
            enabled = value.stage == "clear" or value.stage == "grateful" },
        { id = "recruit", label = "Ask Elmer to come with you",
            enabled = Elmer.canRecruit(group) == true },
        { id = "leave_story", label = "Let Elmer speak to himself",
            enabled = value.stage == "clear" },
    }
end

function Elmer.action(group, action, player)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    local actor = actorFor(group)
    if action == "hurt" then
        U().say(actor, "Ninth of July. I was mowing the lawn.")
        SC.Factions.forceStanding(group.id, "Wary")
        return true, "elmer_does_not_fight_back"
    end
    if not near(group, player, 7) then return false, "elmer_too_far" end
    if action == "interrupt" and value.stage == "telling" then
        value.line = 1
        value.nextLineAt = U().nowMs() + 8000
        U().say(actor, "Where was I? Ninth of July...")
        return true, "elmer_lost_his_place"
    end
    if action == "ask_bedroom" and value.stage == "clear" then
        value.stage = "bedroom_warning"
        U().say(actor,
            "Don't open the bedroom. My wife turned on a Tuesday. She is still in there.")
        return true, "bedroom_truth_told"
    end
    if action == "leave_story" and value.stage == "clear" then
        value.stage = "fragments"
        U().say(actor, "Lawn still looks good.")
        return true, "elmer_left_to_fragments"
    end
    if action == "recruit" and Elmer.canRecruit(group) == true
        and SC.FactionRecruitment then
        local asked, reason = SC.FactionRecruitment.ask(group.id, player, false)
        if not asked then return false, reason end
        return SC.FactionRecruitment.startTrial(group.id, player, false)
    end
    return false, "elmer_choice_unavailable"
end

return Elmer
