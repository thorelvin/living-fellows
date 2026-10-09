-- SPDX-License-Identifier: MIT
-- Silas Reed keeps a real campfire in a forest clearing. A story told by the
-- player plays out over several beats; progress is scalar and survives saves.

local SC = SurvivorCompanion
SC.OddballCampStoryteller = SC.OddballCampStoryteller or {}
local Camp = SC.OddballCampStoryteller
local ID = "survivalist05_mid_storyteller"

local STORIES = {
    home = {
        { player = true, line = "There was a house by the river. Everyone knew the porch light." },
        { line = "And one night it went dark? They always do." },
        { player = true, line = "It did. So the neighbors lit their own, one by one, until the whole road glowed." },
        { line = "That's a good one. It lets a person keep the ending." },
    },
    bridge = {
        { player = true, line = "We crossed a bridge in a storm. The planks were coming loose behind us." },
        { line = "Sounds like every road in Kentucky this week. Go on." },
        { player = true, line = "The last one across went back for a stranger's dog. We held the boards until they both made it." },
        { line = "A dog and a fool. I like stories where both survive." },
    },
    funny = {
        { player = true, line = "A fish told me it was afraid of water." },
        { line = "That's the worst opening I've heard in thirty years." },
        { player = true, line = "I said, 'Then you'll fit right in up here. None of us knows how to live in it either.'" },
        { line = "Ha! Terrible. Tell it again when the world's less terrible." },
    },
}

local GREETINGS = {
    "Sit where you can see the flames. Then tell me something worth hearing.",
    "I can feed a fire. I can't feed a silence. Got a story?",
    "A good story buys a place by this fire. No money changes hands.",
}
local FISHING_LINES = {
    "The fish don't care what happened on land. That's why I go looking for them.",
    "A rod, spare line, a bobber, and patience. Forget one and the lake collects the rest.",
    "When the float goes under, wait half a breath. Then lift. Don't yank like you're starting a mower.",
    "In cold rain, look where the bank cuts deep. The little ones hide there too.",
}
local FIRE_LINES = {
    "The fire's small on purpose. Big flames make a beacon for the dead.",
    "I don't burn green wood. Smoke tells every stranger where I sleep.",
    "When the wind turns, I put it out. A camp is worth more than a warm hand.",
}
local nextFireRetryByGroup = {}
local nextFireRequestByGroup = {}
local FIRE_COMMAND_MODULE = "LivingFellowsCampStory"

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
        and SC.Registry.byId(member.actorId) or nil
    return record and record.actor and U().isValidActor(record.actor)
        and record.actor or nil
end

local function point(square)
    local x, y, z = U().position(square)
    if x == nil then return nil end
    return { x = math.floor(x), y = math.floor(y), z = math.floor(z or 0) }
end

local function outside(square)
    if not square then return false end
    local room, readRoom = U().call(square, "getRoom")
    local building, readBuilding = U().call(square, "getBuilding")
    local exposed, readOutside = U().call(square, "isOutside")
    return readRoom and room == nil and readBuilding and building == nil
        and readOutside and exposed == true
end

local function unseen(square, player, allowSeen)
    if allowSeen then return true end
    if not player then return false end
    local index = select(1, U().call(player, "getPlayerNum"))
    if number(index) == nil then return false end
    local visible, checked = U().call(square, "isCanSee", math.floor(index))
    return checked and visible ~= true and U().canSee(player, square) ~= true
end

local function naturalFloor(square)
    local floor = select(1, U().call(square, "getFloor"))
    local sprite = floor and select(1, U().call(floor, "getSprite"))
    local name = sprite and select(1, U().call(sprite, "getName"))
    name = type(name) == "string" and string.lower(name) or ""
    return string.find(name, "blends_natural", 1, true) ~= nil
        or string.find(name, "blends_grass", 1, true) ~= nil
        or string.find(name, "blends_forest", 1, true) ~= nil
        or string.find(name, "vegetation", 1, true) ~= nil
end

-- Called only for loaded sampled tiles. Count real trees, rather than trusting
-- the map zone label (which also covers lawns and thin roadside vegetation).
function Camp.siteFor(square, player, allowSeen)
    local fire = point(square)
    if not fire or fire.z ~= 0 or not outside(square)
        or not naturalFloor(square) or not unseen(square, player, allowSeen)
        or not U().isSafeSpawnSquare(square)
        or select(1, U().call(square, "getTree")) ~= nil then
        return nil
    end
    local trees = 0
    for dx = -5, 5, 2 do
        for dy = -5, 5, 2 do
            local tile = U().gridSquare(fire.x + dx, fire.y + dy, 0)
            if tile and select(1, U().call(tile, "getTree")) then
                trees = trees + 1
            end
        end
    end
    if trees < 8 then return nil end
    local stand
    for _, offset in ipairs({ { 2, 0 }, { 0, 2 }, { -2, 0 },
        { 0, -2 } }) do
        local tile = U().gridSquare(fire.x + offset[1],
            fire.y + offset[2], 0)
        local mid = U().gridSquare(fire.x + offset[1] / 2,
            fire.y + offset[2] / 2, 0)
        if outside(tile) and unseen(tile, player, allowSeen)
            and U().isSafeSpawnSquare(tile)
            and outside(mid) and U().isSafeSpawnSquare(mid)
            and select(1, U().call(tile, "getTree")) == nil then
            stand = point(tile)
            break
        end
    end
    if not stand then return nil end
    return { kind = "forest_camp", room = "forest",
        anchor = fire, spawn = stand,
        house = { id = "forest-camp:" .. fire.x .. ":" .. fire.y,
            anchor = fire, bounds = { x1 = fire.x - 3, y1 = fire.y - 3,
                x2 = fire.x + 3, y2 = fire.y + 3 },
            interior = { fire, stand }, openings = {} } }
end

local function multiplayerClient()
    return type(isClient) == "function" and isClient() == true
end

local function campfireSystem()
    if multiplayerClient() then
        if CCampfireSystem and CCampfireSystem.instance then
            return CCampfireSystem.instance
        end
        if type(require) == "function" then
            pcall(require, "Camping/CCampfireSystem")
        end
        return CCampfireSystem and CCampfireSystem.instance or nil
    end
    if SCampfireSystem and SCampfireSystem.instance then
        return SCampfireSystem.instance
    end
    if type(require) == "function" then
        pcall(require, "Camping/SCampfireSystem")
    end
    return SCampfireSystem and SCampfireSystem.instance or nil
end

local function ensureFire(group, player)
    local value = story(group)
    local post = value.site and value.site.anchor
    local square = post and U().gridSquare(post.x, post.y, post.z or 0)
    local system = campfireSystem()
    if not square or not system then return false, "campfire_system_unavailable" end
    local fire = select(1, U().call(system, "getLuaObjectOnSquare", square))
    if value.campfirePlaced == true then
        -- The player may have dismantled or extinguished the campfire. Respect
        -- that choice instead of reconstructing or relighting it on reload.
        return true, fire and "campfire_persisted" or "campfire_removed"
    end
    if fire then
        value.campfirePlaced = true
        return true, "existing_campfire"
    end
    if not U().isSafeSpawnSquare(square) then
        return false, "campfire_tile_blocked"
    end
    if multiplayerClient() then
        if type(sendClientCommand) ~= "function" then
            return false, "campfire_command_unavailable"
        end
        local now = U().nowMs()
        if now < (nextFireRequestByGroup[group.id] or 0) then
            return true, "campfire_request_pending"
        end
        if not player and type(getSpecificPlayer) == "function" then
            player = getSpecificPlayer(0)
        end
        if not player then return false, "campfire_sender_unavailable" end
        local sent = pcall(sendClientCommand, player,
            FIRE_COMMAND_MODULE, "place", {
                scene = ID, groupId = group.id,
                x = post.x, y = post.y, z = post.z or 0 })
        if not sent then return false, "campfire_command_failed" end
        nextFireRequestByGroup[group.id] = now + 30000
        -- Only CCampfireSystem readback confirms placement. Never save a
        -- successful placement merely because sendClientCommand returned.
        return true, "campfire_request_pending"
    end
    fire = select(1, U().call(system, "addCampfire", square))
    if not fire then return false, "campfire_placement_failed" end
    value.campfirePlaced = true
    local _, fueled = U().call(fire, "addFuel", 180)
    if fueled then U().call(fire, "lightFire") end
    return true, fueled and "campfire_lit" or "campfire_unlit"
end

local function near(group, player, radius)
    local actor = actorFor(group)
    return actor and player and U().distance(actor, player) <= (radius or 7)
        and U().canSee(player, actor) == true
end

local function sayPlayer(player, line)
    local _, spoken = U().call(player, "Say", line)
    if not spoken then U().call(player, "say", line) end
end

local function nextBeat(group, player, current)
    local value = story(group)
    local beats = value and STORIES[value.storyChoice]
    local index = value and math.floor(number(value.storyBeat) or 1)
    local beat = beats and beats[index]
    local actor = actorFor(group)
    if not beat or not actor or not near(group, player, 9) then return false end
    if beat.player then sayPlayer(player, beat.line)
    else U().say(actor, beat.line) end
    value.storyBeat = index + 1
    value.nextStoryAt = current + 9000
    if index >= #beats then
        value.stage = "story_heard"
        value.storyTold = true
        value.nextStoryAt = nil
        if value.storyRewarded ~= true and SC.Factions
            and type(SC.Factions.adjustStanding) == "function" then
            value.storyRewarded = true
            SC.Factions.adjustStanding(group.id, 65, "forest_camp_story")
        end
    end
    return true
end

function Camp.onSpawn(group, actor)
    local value = story(group)
    if not value or not actor then return false, "storyteller_unavailable" end
    local built, reason = ensureFire(group)
    if value.stage == "unmet" then value.stage = "waiting" end
    return built, reason
end

function Camp.pulse(group, player, current)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    current = number(current) or U().nowMs()
    local actor = actorFor(group)
    if not actor then return true, "storyteller_unloaded" end
    if value.campfirePlaced ~= true
        and current >= (nextFireRetryByGroup[group.id] or 0) then
        nextFireRetryByGroup[group.id] = current + 30000
        ensureFire(group, player)
    end
    if value.stage == "telling" and current >=
        (number(value.nextStoryAt) or 0) then
        if nextBeat(group, player, current) then return true, value.stage end
    end
    if near(group, player, 8) and value.greeted ~= true then
        value.greeted = true
        group.discovered = true
        local anchor = value.site and value.site.anchor or {}
        local greeting = (math.abs((number(anchor.x) or 0)
            + (number(anchor.y) or 0)) % #GREETINGS) + 1
        U().say(actor, GREETINGS[greeting])
        return true, "invited_to_fire"
    end
    return true, value.stage
end

function Camp.intentFor(actor, player, snapshot, group)
    if not story(group) then return nil end
    if group.standing == "Hostile" then
        return { mode = "hostile", priority = 110 }
    end
    local threats = type(snapshot) == "table"
        and (number(snapshot.threatCount) or #(snapshot.threats or {})) or 0
    if threats > 0 then return { mode = "zombie_defense", priority = 18 } end
    return { mode = "campfire_watch", priority = 28 }
end

function Camp.update(actor, player, runtime, intent, group)
    if not intent or intent.mode ~= "campfire_watch" then return false end
    local value = story(group)
    local post = value and value.site and value.site.spawn
    if not post then return true, "camp_post_unavailable" end
    local x, y, z = U().position(actor)
    if x and z == (post.z or 0)
        and (x - post.x) ^ 2 + (y - post.y) ^ 2 <= 2.25 then
        return true, "beside_campfire"
    end
    local square = U().gridSquare(post.x, post.y, post.z or 0)
    if not square then return true, "camp_unloaded" end
    if not SC.Navigation or type(SC.Navigation.request) ~= "function" then
        return false, "navigation_unavailable"
    end
    return SC.Navigation.request(actor, square, "walk", {
        action = "faction_camp_watch", arrivalDistance = 1.5 })
end

function Camp.canRecruit(group)
    local value = story(group)
    return value and value.storyTold == true
        and group.standing == "Trusted" or false,
        "tell_silas_a_good_story_first"
end

function Camp.menuOptions(group, player)
    local value = story(group)
    if not value or not near(group, player, 7)
        or group.standing == "Hostile" then return {} end
    local options = {
        { id = "ask_fishing", label = "Ask about his fishing kit",
            enabled = value.stage ~= "telling" },
        { id = "ask_fire", label = "Ask about his campfire",
            enabled = value.stage ~= "telling" },
    }
    if value.stage ~= "telling" and not value.storyTold then
        options[#options + 1] = { id = "tell_home_story",
            label = "Tell a hopeful story about home", enabled = true }
        options[#options + 1] = { id = "tell_bridge_story",
            label = "Tell a story about a flooded bridge", enabled = true }
        options[#options + 1] = { id = "tell_funny_story",
            label = "Tell him a terrible fishing joke", enabled = true }
    end
    if value.storyTold then
        options[#options + 1] = { id = "recruit",
            label = "Invite Silas to travel with you",
            enabled = Camp.canRecruit(group) == true }
        local recruitment = SC.FactionRecruitment
            and SC.FactionRecruitment.summary(group.id) or nil
        if recruitment and recruitment.status == "trial" then
            options[#options + 1] = { id = "recruitment_decide",
                label = "Ask Silas for his answer",
                enabled = recruitment.canDecide == true }
        end
    end
    return options
end

function Camp.action(group, action, player)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    local actor = actorFor(group)
    if action == "hurt" then
        if actor then U().say(actor, "You came to my fire with a fist. Leave.") end
        return SC.Factions.forceStanding(group.id, "Hostile")
    end
    if not actor or not near(group, player, 7) then
        return false, "storyteller_too_far" end
    if action == "ask_fishing" and value.stage ~= "telling" then
        value.fishingLineIndex = ((number(value.fishingLineIndex) or 0)
            % #FISHING_LINES) + 1
        U().say(actor, FISHING_LINES[value.fishingLineIndex])
        return true, "fishing_discussed"
    elseif action == "ask_fire" and value.stage ~= "telling" then
        value.fireLineIndex = ((number(value.fireLineIndex) or 0)
            % #FIRE_LINES) + 1
        U().say(actor, FIRE_LINES[value.fireLineIndex])
        return true, "campfire_discussed"
    end
    local choice = action == "tell_home_story" and "home"
        or action == "tell_bridge_story" and "bridge"
        or action == "tell_funny_story" and "funny" or nil
    if choice and not value.storyTold and value.stage ~= "telling" then
        value.stage = "telling"
        value.storyChoice = choice
        value.storyBeat = 1
        value.nextStoryAt = U().nowMs()
        group.discovered = true
        nextBeat(group, player, value.nextStoryAt)
        return true, "story_started"
    end
    if action == "recruit" then
        local allowed, reason = Camp.canRecruit(group)
        if not allowed then return false, reason end
        if not SC.FactionRecruitment then return false, "recruitment_unavailable" end
        local summary = SC.FactionRecruitment.summary(group.id)
        if not summary or summary.status ~= "candidate" then
            local asked, askReason = SC.FactionRecruitment.ask(group.id,
                player, false)
            if not asked then return false, askReason end
        end
        return SC.FactionRecruitment.startTrial(group.id, player, false)
    elseif action == "recruitment_decide" and SC.FactionRecruitment then
        return SC.FactionRecruitment.decide(group.id, player)
    end
    return false, "storyteller_choice_unavailable"
end

return Camp
