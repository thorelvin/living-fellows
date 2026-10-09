-- SPDX-License-Identifier: MIT
-- Corey starts at a real player kill. His notebook is an inventory item, and
-- his wide trailing distance uses the same navigation service as other NPCs.

local SC = SurvivorCompanion
SC.OddballCorey = SC.OddballCorey or {}
local Corey = SC.OddballCorey
local ID = "fan_corey_biggs"

local function U() return SC.GameplayUtil end

local function story(group)
    local value = type(group) == "table" and group.oddball or nil
    if type(value) ~= "table" or value.id ~= ID then return nil end
    value.stage = value.stage or "following"
    value.tales = type(value.tales) == "table" and value.tales or {}
    return value
end

local function actorFor(group)
    local member = group and group.members and group.members[1]
    local record = member and member.actorId and SC.Registry
        and SC.Registry.byId(member.actorId) or nil
    return record and record.actor and U().isValidActor(record.actor)
        and record.actor or nil
end

local function dayNow()
    if type(getGameTime) ~= "function" then return nil end
    local okay, time = pcall(getGameTime)
    if not okay or not time then return nil end
    local hours = select(1, U().call(time, "getWorldAgeHours"))
    return tonumber(hours) and math.floor(tonumber(hours) / 24) or nil
end

local function notebook(actor, groupId)
    local inventory = actor and U().inventory(actor)
    for _, item in ipairs(inventory and U().inventoryItemsDeep(inventory,
        100, 4) or {}) do
        local data = U().modData(item)
        if type(data) == "table" and data.lfCoreyGroupId == groupId then
            return item
        end
    end
    return nil
end

local function locationOf(zombie)
    local square = zombie and select(1, U().call(zombie, "getSquare"))
    local room = square and select(1, U().call(square, "getRoom"))
    local name = room and select(1, U().call(room, "getName"))
    if type(name) == "string" and #name > 0 then
        return { placeKind = "room", place = string.lower(name) }
    end
    return { placeKind = "open", place = "by the road" }
end

function Corey.describeKill(player, zombie)
    local place = locationOf(zombie)
    if SC.Tales and type(SC.Tales.title) == "function" then
        return SC.Tales.title(place, 2)
    end
    return place.place
end

function Corey.onSpawn(group, actor)
    local value = story(group)
    if not value or not actor then return false, "fan_unavailable" end
    if value.stage == "unmet" then value.stage = "following" end
    if not notebook(actor, group.id) then
        local inventory = U().inventory(actor)
        local item = inventory and U().addItem(inventory, "Base.Notebook")
        if not item then return false, "fan_diary_unavailable" end
        U().call(item, "setName", "Corey's diary")
        local data = U().modData(item)
        if type(data) ~= "table" then return false, "fan_diary_metadata_unavailable" end
        data.lfCoreyGroupId = group.id
        data.lfCoreyTales = value.tales
    end
    if value.initialTale and #value.tales == 0 then
        value.tales[1] = value.initialTale
        local item = notebook(actor, group.id)
        local data = item and U().modData(item)
        if type(data) == "table" then data.lfCoreyTales = value.tales end
    end
    return true, "fan_following"
end

function Corey.noteKill(group, player, zombie)
    local value = story(group)
    local actor = actorFor(group)
    if not value or value.stage ~= "following" or not actor
        or U().distance(actor, player) > 25
        or U().canSee(actor, player) ~= true then
        return false, "fan_did_not_witness_kill"
    end
    local tale = Corey.describeKill(player, zombie)
    value.tales[#value.tales + 1] = tale
    while #value.tales > 12 do table.remove(value.tales, 1) end
    local item = notebook(actor, group.id)
    local data = item and U().modData(item)
    if type(data) == "table" then data.lfCoreyTales = value.tales end
    if #value.tales % 3 == 0 then
        U().say(actor, "I'm writing it all down. Somebody has to. " .. tale .. ".")
    end
    return true, "real_kill_written_in_diary"
end

function Corey.pulse(group, player)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    if value.stage ~= "following" then return true, value.stage end
    local actor = actorFor(group)
    local day = dayNow()
    if not actor or not player or U().distance(actor, player) > 90 then
        value.awaySinceDay = value.awaySinceDay or day
        if day and value.awaySinceDay and day - value.awaySinceDay >= 3
            and (not actor or U().canSee(player, actor) ~= true) then
            local member = group.members and group.members[1]
            local gone = member and member.hibernated == true
            if not gone and actor and SC.Factions
                and type(SC.Factions.hibernateOddballRoamer) == "function" then
                gone = SC.Factions.hibernateOddballRoamer(group.id, player)
            end
            if gone then
                value.stage = "gave_up"
                group.lifecycle = "destroyed"
                if SC.Oddballs then SC.Oddballs.retire(group, "gave_up") end
                return true, "fan_gave_up_after_three_days"
            end
        end
        return true, "fan_away"
    end
    value.awaySinceDay = nil
    if value.greeted ~= true and U().canSee(actor, player) == true then
        value.greeted = true
        group.discovered = true
        U().say(actor,
            "I saw what you did back there. Incredible. I'm writing it down.")
    end
    return true, "fan_trailing"
end

function Corey.intentFor(actor, player, snapshot, group)
    local value = story(group)
    if not value then return nil end
    if group.standing == "Hostile" then
        return { mode = "hostile", priority = 110 }
    end
    local threats = type(snapshot) == "table"
        and (tonumber(snapshot.threatCount) or #(snapshot.threats or {})) or 0
    if threats > 0 then return { mode = "zombie_defense", priority = 18 } end
    return { mode = "fan_follow", priority = 30 }
end

function Corey.update(actor, player, runtime, intent)
    if not intent or intent.mode ~= "fan_follow" or not player then return false end
    local distance = U().distance(actor, player)
    if distance >= 12 and distance <= 18 then return true, "fan_trailing" end
    if not SC.Navigation or type(SC.Navigation.request) ~= "function" then
        return false, "navigation_unavailable"
    end
    local px, py, pz = U().position(player)
    local ax, ay = U().position(actor)
    if not px or not ax then return true, "fan_position_unavailable" end
    local target
    if distance > 18 then
        target = U().squareOf(player)
    else
        local dx, dy = ax - px, ay - py
        local length = math.max(0.01, math.sqrt(dx * dx + dy * dy))
        target = U().gridSquare(math.floor(px + dx / length * 14),
            math.floor(py + dy / length * 14), pz or 0)
    end
    if not target then return true, "fan_target_unloaded" end
    return SC.Navigation.request(actor, target, "walk", {
        action = "faction_follow", arrivalDistance = distance > 18 and 14 or 1.5 })
end

function Corey.canRecruit(group)
    local value = story(group)
    return value and value.stage == "following" or false,
        "fan_has_moved_on"
end

function Corey.menuOptions(group, player)
    local value = story(group)
    local actor = actorFor(group)
    if not value or not actor or not player
        or U().distance(actor, player) > 6 then return {} end
    return { { id = "ask_diary", label = "Ask what Corey wrote",
        enabled = true } }
end

function Corey.action(group, action, player)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    if action == "hurt" then
        U().say(actorFor(group), "I thought you were better than that.")
        return SC.Factions.forceStanding(group.id, "Wary")
    end
    local actor = actorFor(group)
    if not actor or not player or U().distance(actor, player) > 6 then
        return false, "fan_too_far"
    end
    if action == "ask_diary" then
        local last = value.tales[#value.tales]
        U().say(actor, last and "I wrote about " .. last .. "."
            or "Can I carry something? Anything? Your shoes?")
        return true, "fan_diary_recalled"
    end
    return false, "unknown_fan_choice"
end

return Corey
