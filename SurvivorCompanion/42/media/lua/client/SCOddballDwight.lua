-- SPDX-License-Identifier: MIT
-- Three real rooms, one persistent knight. He leaves unseen through faction
-- hibernation and cannot wake until the next authored site has been found.

local SC = SurvivorCompanion
SC.OddballDwight = SC.OddballDwight or {}
local Dwight = SC.OddballDwight
local ID = "knight_sir_dwight"
local lines = {
    "Ah! Friend! I was merely contemplating. With my eyes closed.",
    "A knight never retreats. He relocates. Thoughtfully.",
    "Mmph. Five more minutes, then glory.",
}

local function U() return SC.GameplayUtil end

local function story(group)
    local value = type(group) == "table" and group.oddball or nil
    if type(value) ~= "table" or value.id ~= ID then return nil end
    value.stage = value.stage or "unmet"
    value.visit = tonumber(value.visit) or 1
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
    return actor and player and U().distance(actor, player) <= 6
        and U().canSee(player, actor) == true
end

local function nearbyDead(group)
    local site = story(group).site
    local post = site and site.spawn
    if not post then return 0 end
    local count = 0
    for dx = -6, 6 do
        for dy = -6, 6 do
            if dx * dx + dy * dy <= 36 then
                local square = U().gridSquare(post.x + dx, post.y + dy,
                    post.z or 0)
                local list = square and select(1, U().call(square,
                    "getMovingObjects"))
                if list and SC.NativeList then
                    for index = 0, math.min(31, SC.NativeList.size(list) - 1) do
                        local creature = SC.NativeList.get(list, index)
                        if creature and U().instanceOf(creature, "IsoZombie") then
                            count = count + 1
                        end
                    end
                end
            end
        end
    end
    return count
end

function Dwight.onSpawn(group, actor)
    local value = story(group)
    if not value or not actor then return false, "knight_unavailable" end
    if value.stage == "arriving" then
        value.visit = tonumber(value.nextVisit) or value.visit
        value.nextVisit = nil
    end
    if value.stage == "unmet" or value.stage == "arriving" then
        value.stage = "sleeping"
        value.poseStarted = nil
        value.wokenAt = nil
    end
    local inventory = U().inventory(actor)
    if not inventory then return false, "knight_inventory_unavailable" end
    if value.swordSeeded ~= true then
        local sword = U().addItem(inventory, "Base.Sword")
        if not sword then return false, "knight_sword_unavailable" end
        U().call(actor, "setPrimaryHandItem", sword)
        value.swordSeeded = true
    end
    if value.visit == 3 then
        value.rescueCountAtArrival = nearbyDead(group)
    end
    return true, "knight_ready"
end

local function relocate(group, player)
    if not SC.Factions
        or type(SC.Factions.hibernateOddballRoamer) ~= "function" then
        return false, "knight_hibernation_unavailable"
    end
    local hibernated = SC.Factions.hibernateOddballRoamer(group.id, player)
    if not hibernated then return false, "knight_departure_pending" end
    local value = story(group)
    value.stage = "awaiting_site"
    value.nextVisit = value.visit + 1
    value.awaitingStageSite = true
    value.nextSearchAt = nil
    value.poseStarted = nil
    return true, "knight_moved_on"
end

function Dwight.pulse(group, player, current)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    current = tonumber(current) or U().nowMs()
    local actor = actorFor(group)
    local member = group.members and group.members[1]
    if value.stage == "awaiting_site" and member and member.hibernated == true then
        if current < (tonumber(value.nextSearchAt) or 0) then
            return true, "knight_search_cooldown"
        end
        value.nextSearchAt = current + 20000
        local old = value.site and value.site.house
        local site = SC.Oddballs and SC.Oddballs.findKnightSite
            and SC.Oddballs.findKnightSite(player, value.nextVisit, old)
        if not site then return true, "knight_next_room_unloaded" end
        value.site.spawn = site.spawn
        value.site.wake = site.spawn
        value.site.anchor = site.spawn
        value.site.room = site.room
        value.site.house = { id = site.house.id,
            anchor = site.house.anchor, bounds = site.house.bounds }
        value.stage = "arriving"
        value.awaitingStageSite = nil
        return true, "knight_next_scene_ready"
    end
    if value.stage == "awoken" and value.visit < 3
        and member and member.hibernated == true then
        value.stage, value.nextVisit = "awaiting_site", value.visit + 1
        value.awaitingStageSite = true
        return true, "knight_departed_offscreen"
    end
    if not actor then return true, "knight_unloaded" end
    if value.stage == "sleeping" and near(group, player)
        and value.discoveredVisit ~= value.visit then
        value.discoveredVisit = value.visit
        group.discovered = true
        U().say(actor, value.visit == 3
            and "Mmph. Five more minutes, then glory."
            or "Quiet, friend. A knight must contemplate.")
    end
    if value.visit == 3 and (value.stage == "sleeping"
        or value.stage == "awoken")
        and current >= (tonumber(value.nextRescueCheckAt) or 0) then
        value.nextRescueCheckAt = current + 5000
        if nearbyDead(group) == 0 and value.rescueCountAtArrival
            and value.rescueCountAtArrival >= 3 then
            value.stage = "rescued"
            if SC.Actor then SC.Actor.setMovement(actor,
                "walk", { action = "stand_ground" }) end
            U().say(actor,
                "You cleared the room. My quest can wait. Let me join yours.")
            return true, "knight_rescued"
        end
    end
    if value.stage == "awoken" and value.visit < 3 then
        local unseen = player and U().canSee(player, actor) ~= true
        if unseen then
            value.unseenSince = value.unseenSince or current
            if current - value.unseenSince >= 30000 then
                return relocate(group, player)
            end
        else
            value.unseenSince = nil
        end
    end
    return true, value.stage
end

function Dwight.onZombieDead(group, zombie, attacker)
    local value = story(group)
    if not value or value.visit ~= 3 or value.stage == "rescued" then
        return false
    end
    local site = value.site and value.site.spawn
    local x, y, z = U().position(zombie)
    if site and x and z == (site.z or 0)
        and (x - site.x) ^ 2 + (y - site.y) ^ 2 <= 100 then
        value.rescueKills = (tonumber(value.rescueKills) or 0) + 1
    end
    return true
end

function Dwight.intentFor(actor, player, snapshot, group)
    local value = story(group)
    if not value then return nil end
    if group.standing == "Hostile" then
        return { mode = "hostile", priority = 110 }
    end
    local threats = type(snapshot) == "table"
        and (tonumber(snapshot.threatCount) or #(snapshot.threats or {})) or 0
    if threats > 0 and (value.visit == 3 or value.stage == "awoken") then
        return { mode = "zombie_defense", priority = 18 }
    end
    return { mode = "knight_rest", priority = 30 }
end

function Dwight.update(actor, player, runtime, intent, group)
    if not intent or intent.mode ~= "knight_rest" then return false end
    local value = story(group)
    if value.stage ~= "sleeping" then return true, value.stage end
    if value.poseStarted == true then return true, "knight_napping" end
    if SC.Actor and type(SC.Actor.setMovement) == "function" then
        local accepted = SC.Actor.setMovement(actor,
            "walk", { action = "sit_ground" })
        if accepted then value.poseStarted = true end
        return accepted == true, accepted and "knight_napping"
            or "knight_rest_pose_pending"
    end
    return false, "native_rest_unavailable"
end

function Dwight.canRecruit(group)
    local value = story(group)
    return value and value.stage == "rescued" or false,
        "rescue_the_knight_first"
end

function Dwight.menuOptions(group, player)
    local value = story(group)
    if not value or not near(group, player) then return {} end
    if value.stage == "sleeping" then
        return { { id = "wake_knight", label = "Wake Sir Dwight",
            enabled = true } }
    end
    return { { id = "ask_quest", label = "Ask about his quest",
        enabled = true } }
end

function Dwight.action(group, action, player)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    if action == "hurt" then
        return SC.Factions.forceStanding(group.id, "Hostile")
    end
    if not near(group, player) then return false, "knight_too_far" end
    local actor = actorFor(group)
    if action == "ask_quest" then
        U().say(actor, lines[math.min(3, value.visit)])
        return true, "quest_recounted"
    end
    if action ~= "wake_knight" or value.stage ~= "sleeping" then
        return false, "knight_not_asleep"
    end
    value.stage = "awoken"
    value.poseStarted = nil
    if SC.Actor then SC.Actor.setMovement(actor,
        "walk", { action = "stand_ground" }) end
    U().say(actor, lines[math.min(3, value.visit)])
    return true, value.visit == 3 and "knight_needs_rescue"
        or "knight_awakened"
end

return Dwight
