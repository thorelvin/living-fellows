-- SPDX-License-Identifier: MIT
-- Pettigrew's suspicions use real neighboring household factions. Watching
-- takes a full minute per house, at night, without being seen by its people.

local SC = SurvivorCompanion
SC.OddballLusk = SC.OddballLusk or {}
local Lusk = SC.OddballLusk
local ID = "watcher_pettigrew_lusk"
local WATCH_MS = 60000

local function U() return SC.GameplayUtil end

local function story(group)
    local value = type(group) == "table" and group.oddball or nil
    if type(value) ~= "table" or value.id ~= ID then return nil end
    value.stage = value.stage or "watching"
    value.watched = type(value.watched) == "table" and value.watched or {}
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

local function isNight()
    if type(getGameTime) ~= "function" then return false end
    local okay, time = pcall(getGameTime)
    local rawHour = okay and time and select(1, U().call(time,
        "getTimeOfDay")) or nil
    local hour = tonumber(rawHour)
    return hour ~= nil and (hour >= 20 or hour < 5)
end

local function targetGroup(target)
    return target and SC.Factions and SC.Factions.group(target.id) or nil
end

local function canWatch(target, player)
    local group = targetGroup(target)
    local x, y, z
    if player then x, y, z = U().position(player) end
    if not group or group.lifecycle == "destroyed" or not x
        or math.floor(z or 0) ~= math.floor(target.z or 0)
        or (x - target.x) ^ 2 + (y - target.y) ^ 2 > 20 * 20 then
        return false
    end
    -- The target must be in loaded space; an unloaded, simulated house does
    -- not grant free surveillance progress.
    if not U().gridSquare(target.x, target.y, target.z or 0) then return false end
    for _, member in ipairs(group.members or {}) do
        local record = member.actorId and SC.Registry
            and SC.Registry.byId(member.actorId) or nil
        local resident = record and record.actor
        if resident and U().isValidActor(resident)
            and U().canSee(resident, player) == true then
            return false
        end
    end
    return true
end

local function allWatched(value)
    local neighbors = value.site and value.site.neighbors or {}
    if #neighbors < 2 then return false end
    for _, target in ipairs(neighbors) do
        if value.watched[target.id] ~= true then return false end
    end
    return true
end

local function reportToWorld(kind, value, accusedId)
    local world = SC.FactionWorld
    if not world or type(world.noteNeighborhoodReport) ~= "function" then
        return false, "household_news_unavailable"
    end
    local neighbors = value.site and value.site.neighbors or {}
    local changed = false
    for left = 1, #neighbors - 1 do
        for right = left + 1, #neighbors do
            local a, b = neighbors[left], neighbors[right]
            if (not accusedId) or a.id == accusedId or b.id == accusedId then
                local okay = world.noteNeighborhoodReport(kind, a.id, b.id)
                changed = okay == true or changed
            end
        end
    end
    return changed, changed and "neighborhood_informed"
        or "no_household_pair_available"
end

local function giveList(player, target)
    local inventory = player and U().inventory(player)
    if not inventory then return false, "player_inventory_unavailable" end
    local item = U().addItem(inventory, "Base.LetterHandwritten")
    if not item then return false, "list_item_unavailable" end
    U().call(item, "setName", "Lusk's kill list: " .. tostring(target.name))
    local data = U().modData(item)
    if type(data) == "table" then
        data.lfLuskTargetId = target.id
        data.lfLuskTargetName = target.name
    end
    return true, "kill_list_received"
end

function Lusk.onSpawn(group, actor)
    local value = story(group)
    if not value or not actor then return false, "watcher_unavailable" end
    if value.stage == "unmet" then value.stage = "watching" end
    return true, "watcher_ready"
end

function Lusk.pulse(group, player, current)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    current = tonumber(current) or U().nowMs()
    local actor = actorFor(group)
    if near(group, player) and value.greeted ~= true then
        value.greeted = true
        group.discovered = true
        U().say(actor,
            "They signal each other. Lights on, lights off. Morse, I'm sure of it.")
    end
    if value.stage ~= "watching" then return true, value.stage end
    if not isNight() then value.watchStart = nil; value.watchId = nil
        return true, "wait_for_night" end
    for _, target in ipairs(value.site and value.site.neighbors or {}) do
        if value.watched[target.id] ~= true and canWatch(target, player) then
            if value.watchId ~= target.id or not value.watchStart
                or current < value.watchStart then
                value.watchId, value.watchStart = target.id, current
            elseif current - value.watchStart >= WATCH_MS then
                value.watched[target.id] = true
                value.watchId, value.watchStart = nil, nil
                if actor then U().say(actor,
                    "You saw it too? Tell me after you've watched the rest.") end
                return true, "household_watched"
            end
            return true, "watching_" .. target.id
        end
    end
    value.watchId, value.watchStart = nil, nil
    return true, allWatched(value) and "report_ready" or "watch_unseen_household"
end

function Lusk.intentFor(actor, player, snapshot, group)
    local value = story(group)
    if not value then return nil end
    if group.standing == "Hostile" then
        return { mode = "hostile", priority = 110 }
    end
    local threats = type(snapshot) == "table"
        and (tonumber(snapshot.threatCount) or #(snapshot.threats or {})) or 0
    if threats > 0 then return { mode = "zombie_defense", priority = 18 } end
    return { mode = "lusk_home", priority = 30 }
end

function Lusk.update(actor, player, runtime, intent, group)
    if not intent or intent.mode ~= "lusk_home" then return false end
    local position = story(group).site and story(group).site.spawn
    if not position then return true, "home_unavailable" end
    local x, y, z = U().position(actor)
    if x and z == (position.z or 0)
        and (x - position.x) ^ 2 + (y - position.y) ^ 2 <= 2.25 then
        return true, "keeping_watch"
    end
    local square = U().gridSquare(position.x, position.y, position.z or 0)
    if not square then return true, "home_unloaded" end
    if not SC.Navigation or type(SC.Navigation.request) ~= "function" then
        return false, "navigation_unavailable"
    end
    return SC.Navigation.request(actor, square, "walk", {
        action = "faction_home", arrivalDistance = 1.5 })
end

function Lusk.canRecruit()
    return false, "lusk_wont_leave_his_watch"
end

function Lusk.menuOptions(group, player)
    local value = story(group)
    if not value or not near(group, player) then return {} end
    local options = { { id = "ask_watch", label = "Ask about the neighbors",
        enabled = true } }
    if value.stage == "watching" and allWatched(value) then
        for _, target in ipairs(value.site.neighbors or {}) do
            options[#options + 1] = { id = "accuse:" .. target.id,
                label = "Accuse " .. tostring(target.name), enabled = true }
        end
        options[#options + 1] = { id = "report_lusk",
            label = "Warn the households about Pettigrew", enabled = true }
        options[#options + 1] = { id = "clear_all",
            label = "Clear all the neighbors", enabled = true }
    end
    return options
end

function Lusk.action(group, action, player)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    if action == "hurt" then
        U().say(actorFor(group), "Don't look at their house. That's what they want.")
        return SC.Factions.forceStanding(group.id, "Hostile")
    end
    if not near(group, player) then return false, "watcher_too_far" end
    local actor = actorFor(group)
    if action == "ask_watch" then
        U().say(actor, allWatched(value)
            and "You watched them all. Now tell me what you saw."
            or "Wait until dark. Stay out of their sight for a full minute each.")
        return true, "watch_instructions"
    end
    if value.stage ~= "watching" or not allWatched(value) then
        return false, "watch_all_neighbors_first"
    end
    if type(action) == "string" and string.sub(action, 1, 7) == "accuse:" then
        local id = string.sub(action, 8)
        for _, target in ipairs(value.site.neighbors or {}) do
            if target.id == id then
                local given, reason = giveList(player, target)
                if not given then return false, reason end
                reportToWorld("neighborhood_accusation", value, target.id)
                value.stage, value.accusedId = "accused", target.id
                U().say(actor, "Names are on the paper. I knew you saw it too.")
                return true, "neighbor_accused"
            end
        end
        return false, "unknown_neighbor"
    elseif action == "report_lusk" then
        local changed, reason = reportToWorld("neighborhood_warning", value)
        if not changed then return false, reason end
        value.stage = "reported"
        SC.Factions.forceStanding(group.id, "Wary")
        U().say(actor, "You told them? Then I'd best lock my door.")
        return true, "lusk_reported_to_households"
    elseif action == "clear_all" then
        value.stage = "exposed"
        U().say(actor, "So you're with them. I knew it. I always know.")
        SC.Factions.forceStanding(group.id, "Hostile")
        return true, "neighbors_cleared_lusk_hostile"
    end
    return false, "unknown_watcher_choice"
end

return Lusk
