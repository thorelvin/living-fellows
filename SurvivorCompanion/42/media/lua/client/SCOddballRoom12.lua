-- SPDX-License-Identifier: MIT
-- Room 12 is a real barricade job, a real door-slot barter and a real sow.
-- The room-guard module gives Delbert a fair five minutes before the player
-- arrives; after that the planks, not an invulnerability flag, hold the room.

local SC = SurvivorCompanion
SC.OddballRoom12 = SC.OddballRoom12 or {}
local Room12 = SC.OddballRoom12
local ID = "party_room12_delbert"
local SWEET_PEA = { kind = "sow", breed = "landrace", name = "Sweet Pea" }
local SUPPLIES = {
    ["Base.BeerCanPack"] = true, ["Base.Whiskey"] = true,
    ["Base.Crisps"] = true,
}
local REWARDS = { "Base.Pills", "Base.Bullets9mmBox", "Base.KeyRing" }
local nextLineAt = {}

local lines = {
    knock = "Occupied! Can't you read? Do Not Disturb!",
    private = "Go away! Me and Sweet Pea are having a party. Private party.",
    idle = "We got a radio, a minibar and pork rinds. Sorry, Sweet Pea.",
    trade = "Slide the beer under the door. I'll slide something back.",
    ruin = "You ruined the party! Sweet Pea, run!",
    over = "Party's over. My head's killing me. Got room for two?",
    dark = "The radio finally went quiet. Sweet Pea is alone in Room 12.",
}

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
    value.supplies = math.max(0, math.min(42,
        math.floor(number(value.supplies) or 3)))
    value.rewardIndex = math.max(1, math.min(#REWARDS + 1,
        math.floor(number(value.rewardIndex) or 1)))
    return value
end

local function actorFor(group)
    local member = group and group.members and group.members[1]
    local record = member and member.actorId and SC.Registry
        and SC.Registry.byId(member.actorId)
    return record and record.actor or nil
end

local function speak(group, beat)
    local actor = actorFor(group)
    return actor and U().say(actor, lines[beat]) == true or false
end

local function worldHour()
    local time = type(getGameTime) == "function" and getGameTime() or nil
    return time and number(select(1, U().call(time, "getWorldAgeHours")))
        or nil
end

local function nearPoint(player, point, radius)
    local x, y, z = U().position(player)
    if not x or not point or z ~= (point.z or 0) then return false end
    return (x - point.x) ^ 2 + (y - point.y) ^ 2 <= radius * radius
end

local function nearDoor(group, player)
    local value = story(group)
    return nearPoint(player, value.site and value.site.partyDoor, 4)
end

local function inPartyRoom(group, player)
    local value = story(group)
    local spawn = value.site and value.site.spawn
    local playerSquare = U().squareOf(player)
    local spawnSquare = spawn and U().gridSquare(spawn.x, spawn.y, spawn.z or 0)
    local room = select(1, U().call(spawnSquare, "getRoom"))
    return room ~= nil and select(1, U().call(playerSquare, "getRoom")) == room
end

local function itemFor(actor, kind)
    local inventory = actor and U().inventory(actor)
    for _, item in ipairs(inventory and U().inventoryItemsDeep(inventory, 200, 8)
        or {}) do
        if U().itemType(item) == kind then return item end
    end
    return nil
end

local function supplyItem(player)
    local inventory = player and U().inventory(player)
    for _, item in ipairs(inventory and U().inventoryItemsDeep(inventory, 240, 12)
        or {}) do
        if SUPPLIES[U().itemType(item)] then return item end
    end
    return nil
end

local function addJob(group, opening, suffix, kind, planks)
    if type(opening) ~= "table" then return end
    group.jobs = type(group.jobs) == "table" and group.jobs or {}
    local id = group.id .. ":room12:" .. suffix .. ":" .. kind
    for _, job in ipairs(group.jobs) do
        if job.id == id then return end
    end
    group.jobs[#group.jobs + 1] = {
        id = id, kind = kind, phase = suffix,
        targetPlanks = planks, target = {
            x = opening.x, y = opening.y, z = opening.z or 0,
            objectIndex = opening.objectIndex, kind = opening.kind },
        status = "open", attempts = 0,
    }
end

local function jobsComplete(group)
    for _, job in ipairs(group.jobs or {}) do
        if job.status ~= "completed" and job.status ~= "cancelled" then
            return false
        end
    end
    return true
end

local function endParty(group, value)
    if value.stage == "over" or value.stage == "hungover" then return end
    value.stage = "over"
    addJob(group, value.site.partyDoor, "door", "remove_barricade", 0)
    addJob(group, value.site.partyWindow, "window", "remove_barricade", 0)
    speak(group, "over")
end

local function darkEnding(group, value, player)
    if value.darkEnding == true or not nearPoint(player, value.site.spawn, 28)
        or not actorFor(group) then return false end
    local actor = actorFor(group)
    if U().canSee(player, actor) ~= false then return false end
    if not SC.Actor or type(SC.Actor.remove) ~= "function" then return false end
    local removed = SC.Actor.remove(actor)
    if not removed then return false end
    local spawn = value.site.spawn
    local member = group.members and group.members[1]
    if member then member.alive, member.actorId = false, nil end
    group.lifecycle = "destroyed"
    value.darkEnding = true
    value.stage = "dead"
    if type(addZombiesInOutfit) == "function" then
        pcall(addZombiesInOutfit, spawn.x, spawn.y, spawn.z or 0,
            1, "Bathrobe", 0)
    end
    if SC.Oddballs and type(SC.Oddballs.retire) == "function" then
        SC.Oddballs.retire(group, "dead")
    end
    return true
end

function Room12.onSpawn(group, actor)
    local value = story(group)
    if not value or not actor then return false, "room12_unavailable" end
    local inventory = U().inventory(actor)
    if not inventory then return false, "party_inventory_unavailable" end
    local plunger = itemFor(actor, "Base.Plunger")
    if not plunger and value.equipmentSeeded ~= true then
        plunger = U().addItem(inventory, "Base.Plunger")
    end
    if plunger then U().call(actor, "setPrimaryHandItem", plunger) end
    if value.equipmentSeeded ~= true and plunger then
        U().addItem(inventory, "Base.BeerCanPack")
        U().addItem(inventory, "Base.PorkRinds")
        U().addItem(inventory, "Base.Hammer")
        for _ = 1, 8 do U().addItem(inventory, "Base.Plank") end
        for _ = 1, 16 do U().addItem(inventory, "Base.Nails") end
        for _, reward in ipairs(REWARDS) do U().addItem(inventory, reward) end
        value.equipmentSeeded = true
    end
    local hour = worldHour()
    value.startedHour = value.startedHour or hour
    value.nextConsumeHour = value.nextConsumeHour or hour and hour + 24
    if value.stage == "unmet" then value.stage = "fortifying" end
    if value.stage == "fortifying" then
        local final = number(SC.Config.get("factionBarricadeFinalPlanks")) or 4
        addJob(group, value.site.partyDoor, "door", "barricade", final)
        addJob(group, value.site.partyWindow, "window", "barricade", final)
    end
    if value.site and value.site.coop then
        SC.OddballAnimals.spawn(group, 1, SWEET_PEA, value.site.coop)
    end
    return true, "party_ready"
end

function Room12.pulse(group, player, current)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    if value.stage == "dead" or value.stage == "ruined" then
        return true, value.stage
    end
    local hour = worldHour()
    local animals = value.animals and value.animals.slots
    if (not animals or not animals[1]) and hour
        and hour >= (number(value.nextAnimalRetryHour) or 0) then
        value.nextAnimalRetryHour = hour + 6
        if value.site and value.site.coop then
            SC.OddballAnimals.spawn(group, 1, SWEET_PEA, value.site.coop)
        end
    end
    if hour and not value.startedHour then value.startedHour = hour end
    if hour and value.nextConsumeHour then
        local days = math.max(0, math.min(42,
            math.floor((hour - value.nextConsumeHour) / 24) + 1))
        if days > 0 then
            value.supplies = math.max(0, value.supplies - days)
            value.nextConsumeHour = value.nextConsumeHour + days * 24
        end
    end
    if value.stage == "fortifying" and jobsComplete(group) then
        value.stage = "party"
    end
    if (value.stage == "party" or value.stage == "fortifying")
        and inPartyRoom(group, player) then
        value.stage = "ruined"
        SC.Factions.forceStanding(group.id, "Hostile")
        speak(group, "ruin")
        return true, "party_broken_into"
    end
    if value.stage == "party" and value.supplies <= 0 and hour then
        if value.tradeCount == nil and hour - value.startedHour >= 21 * 24 then
            if darkEnding(group, value, player) then
                return true, "room12_dark_ending"
            end
        elseif nearDoor(group, player) then
            endParty(group, value)
        end
    end
    if value.stage == "over" and jobsComplete(group) then
        value.stage = "hungover"
    end
    if value.stage == "party" and nearDoor(group, player)
        and current >= (nextLineAt[group.id] or 0) then
        nextLineAt[group.id] = current + 120000
        speak(group, "idle")
    end
    local recruitment = SC.FactionRecruitment
        and SC.FactionRecruitment.summary(group.id)
    if recruitment and recruitment.status == "joined" then
        value.stage = "recruited"
    end
    return true, value.stage
end

function Room12.pulseRecruited(group, actor, player, current)
    return SC.OddballAnimals.follow(group, 1, actor, current)
end

function Room12.intentFor(actor, player, snapshot, group)
    local value = story(group)
    if not value or value.stage == "recruited" then return nil end
    if value.stage == "ruined" or group.standing == "Hostile" then
        return { mode = "hostile", priority = 110 }
    end
    local threatCount = type(snapshot) == "table"
        and (number(snapshot.threatCount) or #(snapshot.threats or {})) or 0
    if threatCount > 0 then return { mode = "zombie_defense", priority = 18 } end
    if value.stage == "fortifying" or value.stage == "over" then
        return { mode = "room12_fortify", priority = 57 }
    end
    return { mode = "room12_party", priority = 30 }
end

function Room12.update(actor, player, runtime, intent, group)
    if not intent then return false end
    if intent.mode == "room12_fortify" then
        return SC.FactionBehavior.fortifyOddball(actor, group)
    end
    if intent.mode ~= "room12_party" then return false end
    local spawn = story(group).site and story(group).site.spawn
    if not spawn then return true, "party_room_unavailable" end
    local x, y, z = U().position(actor)
    if x and z == (spawn.z or 0) and (x - spawn.x) ^ 2
        + (y - spawn.y) ^ 2 <= 2.25 then return true, "party_in_progress" end
    local square = U().gridSquare(spawn.x, spawn.y, spawn.z or 0)
    if not square then return true, "party_room_unloaded" end
    if not SC.Navigation or type(SC.Navigation.request) ~= "function" then
        return false, "navigation_unavailable"
    end
    return SC.Navigation.request(actor, square, "walk", {
        action = "faction_room12", arrivalDistance = 1.5 })
end

function Room12.canRecruit(group)
    local value = story(group)
    if not value or value.stage ~= "hungover" then
        return false, "party_not_over"
    end
    local animal = SC.OddballAnimals.find(group, 1)
    return animal ~= nil, animal and "sweet_pea_comes_too"
        or "sweet_pea_missing"
end

function Room12.menuOptions(group, player)
    local value = story(group)
    if not value then return {} end
    local nearby = nearDoor(group, player)
    if value.stage == "party" or value.stage == "fortifying" then
        local hour = worldHour() or 0
        return {
            { id = "knock", label = "Knock on Room 12",
                enabled = nearby, detail = "A radio plays behind the door" },
            { id = "trade_supplies", label = "Trade party supplies through the door",
                enabled = nearby and supplyItem(player) ~= nil
                    and value.rewardIndex <= #REWARDS
                    and value.lastTradeDay ~= math.floor(hour / 24),
                detail = "Beer, whiskey or crisps for one of Delbert's finds" },
        }
    end
    local canJoin, reason = Room12.canRecruit(group)
    local recruitment = SC.FactionRecruitment
        and SC.FactionRecruitment.summary(group.id) or nil
    if recruitment and recruitment.status == "joined" then return {} end
    local options = { { id = "recruit", label = "Invite Delbert and Sweet Pea",
        enabled = nearby and canJoin, detail = reason } }
    if recruitment and recruitment.status == "trial" then
        options[#options + 1] = { id = "recruitment_decide",
            label = "Ask Delbert for his decision",
            enabled = nearby and recruitment.canDecide == true }
    end
    return options
end

function Room12.action(group, action, player)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    if action == "hurt" or action == "animal_hurt" then
        value.stage = "ruined"
        SC.Factions.forceStanding(group.id, "Hostile")
        speak(group, "ruin")
        return true, "party_attacked"
    end
    if action == "knock" then
        if not nearDoor(group, player) then return false, "door_too_far" end
        speak(group, value.stage == "party" and "private" or "knock")
        return true, "room12_knocked"
    end
    if action == "trade_supplies" then
        if not nearDoor(group, player) or value.stage ~= "party"
            and value.stage ~= "fortifying" then
            return false, "party_trade_unavailable"
        end
        local hour = worldHour()
        local day = hour and math.floor(hour / 24)
        if not day or value.lastTradeDay == day then
            return false, "party_trade_daily_limit"
        end
        local gift = supplyItem(player)
        local actor = actorFor(group)
        local seller = actor and U().inventory(actor)
        local buyer = player and U().inventory(player)
        local rewardType = REWARDS[value.rewardIndex]
        local reward = rewardType and itemFor(actor, rewardType)
        local source = gift and select(1, U().call(gift, "getContainer"))
        if not source or not seller or not buyer or not reward then
            return false, "party_trade_items_missing"
        end
        local paid = U().transferItemVerified(source, seller, gift)
        if not paid then return false, "party_supply_transfer_failed" end
        local delivered = U().transferItemVerified(seller, buyer, reward)
        if not delivered then
            U().transferItemVerified(seller, buyer, gift)
            return false, "party_reward_transfer_failed"
        end
        value.lastTradeDay = day
        value.tradeCount = math.min(99, (number(value.tradeCount) or 0) + 1)
        value.supplies = math.min(42, value.supplies + 3)
        value.rewardIndex = value.rewardIndex + 1
        speak(group, "trade")
        return true, "party_supply_traded"
    end
    if action == "recruit" then
        if not nearDoor(group, player) then return false, "too_far_away" end
        local allowed, reason = Room12.canRecruit(group)
        if not allowed then return false, reason end
        if not SC.FactionRecruitment then return false, "recruitment_unavailable" end
        local summary = SC.FactionRecruitment.summary(group.id)
        if not summary or summary.status ~= "candidate" then
            local asked, askReason = SC.FactionRecruitment.ask(group.id, player, false)
            if not asked then return false, askReason end
        end
        return SC.FactionRecruitment.startTrial(group.id, player, false)
    end
    if action == "recruitment_decide" and SC.FactionRecruitment then
        return SC.FactionRecruitment.decide(group.id, player)
    end
    return false, "unsupported_room12_action"
end

return Room12
