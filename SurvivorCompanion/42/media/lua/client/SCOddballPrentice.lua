-- SPDX-License-Identifier: MIT
-- The same wandering man asks five times. His clue ledger survives saves and
-- his friend's note is a real item left in the fifth, distant town.

local SC = SurvivorCompanion
SC.OddballPrentice = SC.OddballPrentice or {}
local Prentice = SC.OddballPrentice
local ID = "dewey_prentice_hollowell"
local UNSEEN_MS = 60000
local clues = {
    "Pardon me. Have you seen Dewey? Big fellow. Or small. Laughs.",
    "Dewey has a mustache. Or he did. He said he'd shave before August.",
    "No mustache, he said. Tall as a church door. Unless that was his brother.",
    "We were inseparable. He'd tell you the same. If I could find him.",
    "He'd never leave without a word. He'd leave a note, at least.",
}
local lines = {
    found = "He wrote to you. Then he walked away. I am so sorry.",
    truth = "Dead to me, then. May I come with you? I can't walk this road alone.",
    lie = "No note? Ah. Then he's out there. Thank you, truly.",
    fellow = "Him again. Still no Dewey?",
    hurt = "I've made a mistake. You aren't the sort to help anybody.",
}

local function U() return SC.GameplayUtil end

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

local function worldDay()
    if type(getGameTime) ~= "function" then return nil end
    local okay, time = pcall(getGameTime)
    if not okay or not time then return nil end
    local raw = select(1, U().call(time, "getWorldAgeHours"))
    local hour = tonumber(raw)
    return hour and math.floor(hour / 24) or nil
end

local function near(group, player)
    local actor = actorFor(group)
    return actor and player and U().distance(actor, player) <= 7
        and U().canSee(player, actor) == true
end

local function noteSquare(group)
    local site = story(group).site
    local house = site and site.house
    local point = house and house.anchor or site and site.spawn
    return point and U().gridSquare(point.x, point.y, point.z or 0) or nil
end

local function noteOnGround(square, groupId)
    local objects = square and select(1, U().call(square, "getWorldObjects"))
    if not objects or not SC.NativeList then return false end
    for index = 0, math.min(63, SC.NativeList.size(objects) - 1) do
        local world = SC.NativeList.get(objects, index)
        local item = select(1, U().call(world, "getItem"))
        local data = item and U().modData(item)
        if data and data.lfDeweyGroupId == groupId then return true end
    end
    return false
end

local function placeNote(group, value)
    if value.notePlaced == true then return true end
    local square = noteSquare(group)
    if not square then return false, "dewey_note_square_unloaded" end
    if noteOnGround(square, group.id) then
        value.notePlaced = true
        return true
    end
    if type(instanceItem) ~= "function" then
        return false, "note_item_factory_unavailable"
    end
    local okay, item = pcall(instanceItem, "Base.LetterHandwritten")
    if not okay or not item then return false, "dewey_note_unavailable" end
    U().call(item, "setName", "Dewey's note: If Prentice asks, I'm dead.")
    local data = U().modData(item)
    if type(data) ~= "table" then return false, "note_metadata_unavailable" end
    data.lfDeweyGroupId = group.id
    local _, placed = U().call(square, "AddWorldInventoryItem",
        item, 0.5, 0.5, 0)
    if not placed then return false, "dewey_note_placement_failed" end
    value.notePlaced = true
    return true
end

local function playerHasNote(player, groupId)
    local inventory = player and U().inventory(player)
    for _, item in ipairs(inventory and U().inventoryItemsDeep(inventory, 200, 8)
        or {}) do
        local data = U().modData(item)
        if type(data) == "table" and data.lfDeweyGroupId == groupId then
            return true
        end
    end
    return false
end

local function fellowReaction(player)
    if not SC.Registry or type(SC.Registry.living) ~= "function" then return end
    for _, actor in ipairs(SC.Registry.living()) do
        local record = SC.Registry.byId(U().idOf(actor))
        if record and record.recruited == true
            and U().distance(actor, player) <= 8 then
            U().say(actor, lines.fellow)
            return
        end
    end
end

function Prentice.onSpawn(group, actor)
    local value = story(group)
    if not value or not actor then return false, "prentice_unavailable" end
    if value.stage == "unmet" then
        value.visitSerial, value.stage = 1, "searching"
    elseif value.stage == "waiting" then
        value.visitSerial = (tonumber(value.visitSerial) or 0) + 1
        value.stage = "searching"
    end
    return true, "prentice_ready"
end

function Prentice.pulse(group, player, current)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    local member = group.members and group.members[1]
    if member and member.hibernated == true then
        local day = worldDay()
        if day and day >= (tonumber(value.nextVisitDay) or math.huge)
            and SC.Oddballs
            and type(SC.Oddballs.findRoamerLandmark) == "function" then
            local previous = value.site and (value.site.wake or value.site.spawn)
            local site = SC.Oddballs.findRoamerLandmark(
                player, previous, false, 300)
            if site and site.spawn then
                value.site.wake = site.spawn
                value.site.anchor = site.spawn
                value.site.house = { id = site.house.id,
                    anchor = site.house.anchor, bounds = site.house.bounds }
                value.stage = "waiting"
                value.nextVisitDay = day + 1
                return true, "prentice_next_town_selected"
            end
        end
        return true, "prentice_elsewhere"
    end
    local actor = actorFor(group)
    if not actor then return false, "prentice_actor_unavailable" end
    if near(group, player) and value.metThisVisit ~= value.visitSerial then
        value.metThisVisit = value.visitSerial
        value.meetings = math.min(5, (tonumber(value.meetings) or 0) + 1)
        group.discovered = true
        U().say(actor, clues[value.meetings])
        if value.meetings >= 2 then fellowReaction(player) end
        if value.meetings == 5 then placeNote(group, value) end
    end
    if value.meetings >= 5 and value.notePlaced ~= true then
        placeNote(group, value)
    end
    if value.stage == "searching" then
        local visible = player and U().canSee(player, actor) == true
        if visible then value.unseenSince = nil
        else
            value.unseenSince = value.unseenSince or current
            if current - value.unseenSince >= UNSEEN_MS
                and SC.Factions
                and type(SC.Factions.hibernateOddballRoamer) == "function" then
                local gone = SC.Factions.hibernateOddballRoamer(group.id, player)
                if gone then
                    value.stage = "away"
                    value.nextVisitDay = (worldDay() or 0) + 1
                    value.unseenSince = nil
                    return true, "prentice_departed"
                end
            end
        end
    end
    return true, value.stage
end

function Prentice.intentFor(actor, player, snapshot, group)
    local value = story(group)
    if not value then return nil end
    if group.standing == "Hostile" then
        return { mode = "hostile", priority = 110 }
    end
    local threats = type(snapshot) == "table"
        and (tonumber(snapshot.threatCount) or #(snapshot.threats or {})) or 0
    if threats > 0 then return { mode = "zombie_defense", priority = 18 } end
    return { mode = "prentice_search", priority = 30 }
end

function Prentice.update(actor, player, runtime, intent, group)
    if not intent or intent.mode ~= "prentice_search" then return false end
    local site = story(group).site
    local point = site and (site.wake or site.spawn)
    if not point then return true, "town_square_unavailable" end
    local x, y, z = U().position(actor)
    if x and z == (point.z or 0) and (x - point.x) ^ 2
        + (y - point.y) ^ 2 <= 2.25 then return true, "searching_for_dewey" end
    local square = U().gridSquare(point.x, point.y, point.z or 0)
    if not square then return true, "town_square_unloaded" end
    if not SC.Navigation or type(SC.Navigation.request) ~= "function" then
        return false, "navigation_unavailable"
    end
    return SC.Navigation.request(actor, square, "walk", {
        action = "faction_search", arrivalDistance = 1.5 })
end

function Prentice.canRecruit(group)
    local value = story(group)
    return value and value.stage == "crushed" or false,
        "tell_prentice_the_truth_first"
end

function Prentice.menuOptions(group, player)
    local value = story(group)
    if not value or not near(group, player) then return {} end
    local result = { { id = "ask_dewey", label = "Ask about Dewey",
        enabled = value.stage == "searching" } }
    if value.meetings >= 5 and value.stage == "searching" then
        result[#result + 1] = { id = "tell_truth",
            label = "Show him Dewey's note",
            enabled = playerHasNote(player, group.id) }
        result[#result + 1] = { id = "lie",
            label = "Say Dewey is still out there", enabled = true }
    end
    return result
end

function Prentice.action(group, action, player)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    if action == "hurt" then
        U().say(actorFor(group), lines.hurt)
        return SC.Factions.forceStanding(group.id, "Hostile")
    end
    if not near(group, player) then return false, "prentice_too_far" end
    if action == "ask_dewey" then
        U().say(actorFor(group), clues[math.min(5,
            tonumber(value.meetings) or 1)])
        return true, "dewey_description_repeated"
    end
    if value.meetings < 5 or value.stage ~= "searching" then
        return false, "dewey_note_not_due"
    end
    if action == "tell_truth" then
        if not playerHasNote(player, group.id) then
            return false, "dewey_note_required"
        end
        value.stage = "crushed"
        U().say(actorFor(group), lines.truth)
        return true, "prentice_truth_told"
    elseif action == "lie" then
        value.lied = true
        U().say(actorFor(group), lines.lie)
        return true, "prentice_search_continues"
    end
    return false, "unknown_dewey_choice"
end

return Prentice
