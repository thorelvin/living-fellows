-- SPDX-License-Identifier: MIT
-- Four armed household members defend the farmhouse with the existing
-- faction combat system. Watch credit requires two real game hours on site.

local SC = SurvivorCompanion
SC.OddballTolliver = SC.OddballTolliver or {}
local Tolliver = SC.OddballTolliver
local ID = "tolliver_farm_siege"
local REWARD = { "Base.AnimalFeedBag", "Base.HandShovel", "Base.SeedBag" }

local function U() return SC.GameplayUtil end
local function story(group)
    local value = type(group) == "table" and group.oddball or nil
    if type(value) ~= "table" or value.id ~= ID then return nil end
    value.stage = value.stage or "siege"
    value.armed = value.armed or {}
    return value
end
local function actorFor(group, index)
    local member = group and group.members and group.members[index]
    local record = member and member.actorId and SC.Registry
        and SC.Registry.byId(member.actorId) or nil
    return record and record.actor and U().isValidActor(record.actor)
        and record.actor or nil
end
local function ageHours()
    local time = type(getGameTime) == "function" and getGameTime() or nil
    local raw = time and select(1, U().call(time, "getWorldAgeHours"))
    return tonumber(raw)
end
local function night()
    local time = type(getGameTime) == "function" and getGameTime() or nil
    local raw = time and select(1, U().call(time, "getTimeOfDay"))
    local hour = tonumber(raw)
    return hour and (hour >= 19 or hour < 5) or false
end
local function near(group, player, radius)
    local actor = actorFor(group, 1)
    return actor and player and U().distance(actor, player) <= radius
end
local function itemFor(actor, kind)
    local inventory = actor and U().inventory(actor)
    for _, item in ipairs(inventory and U().inventoryItemsDeep(inventory,
        160, 8) or {}) do
        if U().itemType(item) == kind then return item end
    end
    return nil
end
local function playerHasLight(player)
    for _, getter in ipairs({ "getPrimaryHandItem", "getSecondaryHandItem" }) do
        local item = select(1, U().call(player, getter))
        local active = item and select(1, U().call(item, "isActivated"))
        local emits = item and select(1,
            U().call(item, "isLightSource"))
        if active == true and emits == true then return true end
    end
    return false
end
local function fellowNear(player)
    for _, actor in ipairs(SC.Registry and SC.Registry.living() or {}) do
        local record = SC.Registry.byId(U().idOf(actor))
        if record and record.recruited == true
            and U().distance(actor, player) <= 12 then return true end
    end
    return false
end

function Tolliver.onSpawn(group, actor)
    local value = story(group)
    if not value or not actor then return false, "tolliver_unavailable" end
    local index
    for current = 1, 4 do
        if actor == actorFor(group, current) then index = current; break end
    end
    if not index then return false, "tolliver_member_missing" end
    local inventory = U().inventory(actor)
    if not inventory then return false, "tolliver_inventory_unavailable" end
    if value.armed[index] ~= true then
        local shotgun = index ~= 2
        local kind = shotgun and "Base.Shotgun" or "Base.HuntingRifle"
        local weapon = itemFor(actor, kind) or U().addItem(inventory, kind)
        if not weapon then return false, "farm_gun_unavailable" end
        U().call(weapon, "setCurrentAmmoCount", shotgun and 6 or 4)
        U().call(actor, "setPrimaryHandItem", weapon)
        for _ = 1, 12 do
            U().addItem(inventory,
                shotgun and "Base.ShotgunShells" or "Base.308Bullets")
        end
        value.armed[index] = true
    end
    if index == 1 and value.rewardSeeded ~= true then
        local added = 0
        for _, kind in ipairs(REWARD) do
            local item = U().addItem(inventory, kind)
            if item then
                local data = U().modData(item)
                if data then data.lfTolliverReward = true end
                added = added + 1
            end
        end
        if added == #REWARD then value.rewardSeeded = true end
    end
    return true, "farm_defenders_armed"
end

function Tolliver.pulse(group, player)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    local leader = actorFor(group, 1)
    if not leader then return false, "farm_defenders_unloaded" end
    if near(group, player, 12) and value.greeted ~= true then
        value.greeted = true
        group.discovered = true
        U().say(leader,
            "They come up to the windows. Little faces, big eyes. Every night.")
    end
    if value.stage == "watching" then
        local hours = ageHours()
        if not night() or not near(group, player, 15) then
            value.stage = "siege"
            value.watchStartHour = nil
            U().say(leader, "You left the post. The night doesn't pause for anybody.")
        elseif hours and value.watchStartHour
            and hours - value.watchStartHour >= 2 then
            value.stage = "watch_complete"
            SC.Factions.forceStanding(group.id, "Trusted")
            U().say(leader,
                "You kept the watch. Whatever's at those windows, it bleeds. Take the supplies.")
        end
    end
    if night() and value.stage ~= "watching"
        and value.stage ~= "watch_complete" and player
        and fellowNear(player) and not playerHasLight(player) then
        if near(group, player, 16) and value.darkWarning ~= true then
            value.darkWarning = true
            U().say(leader,
                "Light your faces! We can't tell you from the little men out there!")
        elseif near(group, player, 7) and value.darkWarning == true
            and value.mistakenHostile ~= true then
            value.mistakenHostile = true
            SC.Factions.forceStanding(group.id, "Hostile")
            U().say(leader, "At the door! Hold the line!")
        end
    elseif value.mistakenHostile == true and value.playerAttacked ~= true then
        value.mistakenHostile = false
        value.darkWarning = false
        SC.Factions.forceStanding(group.id, "Wary")
        U().say(leader, "That's a person. Dammit, I almost shot a person.")
    end
    return true, value.stage
end

function Tolliver.intentFor(actor, player, snapshot, group)
    if not story(group) then return nil end
    if group.standing == "Hostile" then
        return { mode = "hostile", priority = 110 }
    end
    local threats = type(snapshot) == "table"
        and (tonumber(snapshot.threatCount) or #(snapshot.threats or {})) or 0
    if threats > 0 then return { mode = "zombie_defense", priority = 18 } end
    return { mode = "oddball_idle", priority = 28 }
end

function Tolliver.canRecruit() return false, "family_holds_the_farm" end

function Tolliver.menuOptions(group, player)
    local value = story(group)
    if not value or not near(group, player, 7) then return {} end
    return {
        { id = "ask_little_men", label = "Ask about the little men",
            enabled = true },
        { id = "take_watch", label = "Stand night watch with the Tollivers",
            enabled = night() and value.stage == "siege" },
        { id = "claim_supplies", label = "Take the farm supplies",
            enabled = value.stage == "watch_complete"
                and value.rewardClaimed ~= true },
    }
end

function Tolliver.action(group, action, player)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    if action == "hurt" then
        value.playerAttacked = true
        return SC.Factions.forceStanding(group.id, "Hostile")
    end
    if not near(group, player, 7) then return false, "farm_watch_too_far" end
    local leader = actorFor(group, 1)
    if action == "ask_little_men" then
        U().say(leader,
            "Daddy saw 'em in '55. Nobody believed him either. We know now they're dead folk.")
        return true, "siege_story_told"
    end
    if action == "take_watch" and night()
        and value.stage == "siege" then
        local hours = ageHours()
        if not hours then return false, "watch_clock_unavailable" end
        value.stage = "watching"
        value.watchStartHour = hours
        value.darkWarning = false
        U().say(leader,
            "Two hours by the windows. Keep a light on you and watch the tree line.")
        return true, "real_night_watch_started"
    end
    if action == "claim_supplies" and value.stage == "watch_complete"
        and value.rewardClaimed ~= true then
        local leaderInventory = U().inventory(leader)
        local destination = U().inventory(player)
        if not leaderInventory or not destination then
            return false, "farm_inventory_unavailable" end
        local moved = {}
        for _, kind in ipairs(REWARD) do
            local item = itemFor(leader, kind)
            local data = item and U().modData(item)
            if not item or not data or data.lfTolliverReward ~= true
                or not U().transferItemVerified(leaderInventory,
                    destination, item) then
                for index = #moved, 1, -1 do
                    U().transferItemVerified(destination,
                        leaderInventory, moved[index])
                end
                return false, "farm_reward_transfer_failed"
            end
            moved[#moved + 1] = item
        end
        value.rewardClaimed = true
        U().say(leader, "For standing with us. No more little men tonight.")
        return true, "exact_farm_supplies_received"
    end
    return false, "farm_watch_choice_unavailable"
end

return Tolliver
