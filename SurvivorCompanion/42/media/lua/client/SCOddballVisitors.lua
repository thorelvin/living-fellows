-- SPDX-License-Identifier: MIT
-- The Visitors use an actual radio and batteries, walk to an actual wooded
-- square, and leave exact carried supplies in a real farm container.

local SC = SurvivorCompanion
SC.OddballVisitors = SC.OddballVisitors or {}
local Visitors = SC.OddballVisitors
local ID = "silver_visitors_fellowship"

local function U() return SC.GameplayUtil end

local function story(group)
    local value = type(group) == "table" and group.oddball or nil
    if type(value) ~= "table" or value.id ~= ID then return nil end
    value.stage = value.stage or "waiting"
    value.batteries = math.max(0, math.min(2,
        math.floor(tonumber(value.batteries) or 0)))
    return value
end

local function actorFor(group, index)
    local member = group and group.members and group.members[index]
    local record = member and member.actorId and SC.Registry
        and SC.Registry.byId(member.actorId) or nil
    return record and record.actor and U().isValidActor(record.actor)
        and record.actor or nil
end

local function near(group, player)
    for index = 1, #(group.members or {}) do
        local actor = actorFor(group, index)
        if actor and player and U().distance(actor, player) <= 7
            and U().canSee(player, actor) == true then return true end
    end
    return false
end

local function ageHours()
    local time = type(getGameTime) == "function" and getGameTime() or nil
    local hours = time and select(1, U().call(time, "getWorldAgeHours"))
    return tonumber(hours)
end

local function night()
    local hours = ageHours()
    if not hours then return false end
    local clock = hours % 24
    return clock >= 20 or clock < 5
end

local function itemFor(actor, kind)
    local inventory = actor and U().inventory(actor)
    for _, item in ipairs(inventory and U().inventoryItemsDeep(inventory,
        240, 10) or {}) do
        if U().itemType(item) == kind then return item end
    end
    return nil
end

local function taggedSupply(actor, groupId)
    local inventory = actor and U().inventory(actor)
    for _, item in ipairs(inventory and U().inventoryItemsDeep(inventory,
        240, 10) or {}) do
        local data = U().modData(item)
        if data and data.lfVisitorsSupplyGroupId == groupId then
            return item
        end
    end
    return nil
end

local function cache(group)
    local site = group and group.oddball and group.oddball.site
    if not site or not site.cache or not SC.Factions
        or type(SC.Factions.resolveQuestContainer) ~= "function" then
        return nil
    end
    local container, _, locator = SC.Factions.resolveQuestContainer(
        site.cache, group.house and group.house.bounds,
        group.house and group.house.anchor)
    if container and locator then site.cache = locator end
    return container
end

local function stashSupplies(group)
    local destination = cache(group)
    if not destination then return false, "farm_cache_missing" end
    local moved = 0
    for index = 1, #(group.members or {}) do
        local actor = actorFor(group, index)
        while actor do
            local item = taggedSupply(actor, group.id)
            if not item then break end
            local source = select(1, U().call(item, "getContainer"))
            if not source or not U().transferItemVerified(source,
                destination, item) then
                return false, "farm_cache_transfer_failed"
            end
            moved = moved + 1
        end
    end
    return moved > 0, moved > 0 and "supplies_left_in_farm"
        or "no_supplies_to_leave"
end

local function disappear(group, player)
    local value = story(group)
    for index = 1, #(group.members or {}) do
        local actor = actorFor(group, index)
        if actor and player and U().canSee(player, actor) ~= false then
            return false, "visitors_still_visible"
        end
    end
    if value.suppliesLeft ~= true then
        local deposited, reason = stashSupplies(group)
        if not deposited then return false, reason end
        value.suppliesLeft = true
    end
    if not SC.Actor or type(SC.Actor.remove) ~= "function" then
        return false, "native_removal_unavailable"
    end
    for index, member in ipairs(group.members or {}) do
        local actor = actorFor(group, index)
        if actor then
            local removed = SC.Actor.remove(actor)
            if not removed then return false, "visitor_removal_pending" end
        end
        member.alive, member.actorId = false, nil
    end
    group.lifecycle = "destroyed"
    value.stage = "gone"
    if SC.Oddballs and type(SC.Oddballs.retire) == "function" then
        SC.Oddballs.retire(group, "vanished_in_woods")
    end
    return true, "visitors_departed_into_woods"
end

local function destination(value, index)
    local woods = value.site and value.site.woods
    if not woods then return nil end
    local offsets = { { 0, 0 }, { 1, 0 }, { 0, 1 }, { -1, 0 } }
    local offset = offsets[index] or offsets[1]
    local square = U().gridSquare(woods.x + offset[1],
        woods.y + offset[2], woods.z or 0)
    if square and U().isSafeSpawnSquare(square) then return square end
    return U().gridSquare(woods.x, woods.y, woods.z or 0)
end

function Visitors.onSpawn(group, actor)
    local value = story(group)
    if not value or not actor then return false, "visitor_unavailable" end
    if actor == actorFor(group, 1) and value.stockSeeded ~= true then
        local inventory = U().inventory(actor)
        if not inventory then return false, "visitor_inventory_unavailable" end
        local count = 0
        for _, kind in ipairs({ "Base.TinnedBeans", "Base.Bandage",
            "Base.TinnedSoup", "Base.Matches" }) do
            local item = U().addItem(inventory, kind)
            if item then
                local data = U().modData(item)
                if data then data.lfVisitorsSupplyGroupId = group.id end
                count = count + 1
            end
        end
        if count == 0 then return false, "visitor_supplies_unavailable" end
        value.stockSeeded = true
    end
    return true, "visitor_ready"
end

function Visitors.pulse(group, player, current)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    current = tonumber(current) or U().nowMs()
    local leader = actorFor(group, 1)
    if value.stage == "unmet" then value.stage = "waiting" end
    if leader and near(group, player) and value.greeted ~= true then
        value.greeted = true
        group.discovered = true
        U().say(leader,
            "They came for the Suttons in '55. They're coming back for us.")
    end
    if value.stage == "ready" and night() then
        value.stage = "marching"
        U().say(leader, "Bring the radio to the hill. They'll hear it.")
    end
    if value.stage == "marching" then
        local arrived = 0
        for index = 1, #(group.members or {}) do
            local actor, target = actorFor(group, index), destination(value, index)
            if actor and target and U().distance(actor, target) <= 3 then
                arrived = arrived + 1
            end
        end
        if arrived == #(group.members or {}) then
            value.stage = "vigil"
            value.vigilStartedAt = current
            if leader then U().say(leader,
                "The dead aren't a plague. They're the welcome committee.") end
        end
    end
    if value.stage == "vigil" and player and value.playerFollowed ~= true
        and value.site and value.site.woods
        and U().distance(player, value.site.woods) <= 12 then
        value.playerFollowed = true
        group.discovered = true
    end
    if value.stage == "vigil" and value.playerFollowed ~= true
        and current - (tonumber(value.vigilStartedAt) or current) >= 120000 then
        return disappear(group, player)
    end
    if value.stage == "returning" then
        local arrived = 0
        for index = 1, #(group.members or {}) do
            local actor = actorFor(group, index)
            local post = value.site and value.site.memberSpawns
                and value.site.memberSpawns[index]
            if actor and post and U().distance(actor, post) <= 3 then
                arrived = arrived + 1
            end
        end
        if arrived == #(group.members or {}) then value.stage = "settled" end
    end
    return true, value.stage
end

function Visitors.intentFor(actor, player, snapshot, group)
    local value = story(group)
    if not value then return nil end
    if group.standing == "Hostile" then
        return { mode = "hostile", priority = 110 }
    end
    local threats = type(snapshot) == "table"
        and (tonumber(snapshot.threatCount) or #(snapshot.threats or {})) or 0
    if threats > 0 then return { mode = "zombie_defense", priority = 18 } end
    if value.stage == "marching" or value.stage == "returning" then
        return { mode = "visitors_march", priority = 40 }
    end
    return { mode = "oddball_idle", priority = 28 }
end

function Visitors.update(actor, player, runtime, intent, group)
    if not intent or intent.mode ~= "visitors_march" then
        return false, "visitor_idle"
    end
    local index
    for current = 1, #(group.members or {}) do
        if actor == actorFor(group, current) then index = current; break end
    end
    local value = story(group)
    local target = index and (value.stage == "returning"
        and value.site and value.site.memberSpawns
            and U().gridSquare(value.site.memberSpawns[index].x,
                value.site.memberSpawns[index].y,
                value.site.memberSpawns[index].z or 0)
        or destination(value, index))
    if not target then return false, "woods_path_unloaded" end
    if U().distance(actor, target) <= 2 then return true, "at_woods" end
    if not SC.Navigation or type(SC.Navigation.request) ~= "function" then
        return false, "navigation_unavailable"
    end
    return SC.Navigation.request(actor, target, "walk", {
        action = "faction_visitors_woods", arrivalDistance = 2 })
end

function Visitors.canRecruit()
    return false, "visitors_wait_for_pickup"
end

function Visitors.menuOptions(group, player)
    local value = story(group)
    if not value or not near(group, player) then return {} end
    if value.stage == "vigil" and value.playerFollowed then
        return {
            { id = "wait_with_them", label = "Wait beneath the trees",
                enabled = true },
            { id = "call_it_off", label = "Tell them no one is coming",
                enabled = true },
        }
    end
    if value.stage == "gone" then return {} end
    return {
        { id = "ask_visitors", label = "Ask about the Silver Visitors",
            enabled = true },
        { id = "give_radio", label = "Give them a ham radio",
            enabled = value.radioGiven ~= true
                and itemFor(player, "Base.HamRadio1") ~= nil },
        { id = "give_battery", label = "Give them a battery",
            enabled = value.batteries < 2
                and itemFor(player, "Base.Battery") ~= nil },
    }
end

function Visitors.action(group, action, player)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    if action == "hurt" then
        return SC.Factions.forceStanding(group.id, "Hostile")
    end
    if not near(group, player) then return false, "visitor_too_far" end
    local leader = actorFor(group, 1)
    if action == "ask_visitors" then
        U().say(leader,
            "They came for the Suttons in '55. We're not missing the next one.")
        return true, "visitors_explained"
    end
    if action == "wait_with_them" and value.stage == "vigil"
        and value.playerFollowed then
        value.stage = "returning"
        U().say(leader,
            "No lights. Just us, the dead, and that radio. Perhaps that is the answer.")
        return true, "the_sky_stays_empty"
    end
    if action == "call_it_off" and value.stage == "vigil"
        and value.playerFollowed then
        value.stage = "returning"
        U().say(leader, "All right. Back to the barn before dawn.")
        return true, "visitors_turn_back"
    end
    local kind = action == "give_radio" and "Base.HamRadio1"
        or action == "give_battery" and "Base.Battery" or nil
    if not kind or action == "give_radio" and value.radioGiven
        or action == "give_battery" and value.batteries >= 2 then
        return false, "visitor_choice_unavailable"
    end
    local item = itemFor(player, kind)
    local source = item and select(1, U().call(item, "getContainer"))
    local destination = leader and U().inventory(leader)
    if not item or not source or not destination
        or not U().transferItemVerified(source, destination, item) then
        return false, "beacon_part_transfer_failed"
    end
    local data = U().modData(item)
    if data then data.lfVisitorsSupplyGroupId = group.id end
    if action == "give_radio" then value.radioGiven = true
    else value.batteries = value.batteries + 1 end
    if value.radioGiven and value.batteries == 2 then
        value.stage = "ready"
        U().say(leader,
            "That's the beacon. The pickup happens after dark.")
    else
        U().say(leader, "One part closer. Keep your eyes on the sky.")
    end
    return true, "beacon_part_received"
end

return Visitors
