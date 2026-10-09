-- SPDX-License-Identifier: MIT
-- Kris checks the player's actual faction history, then gives one wrapped
-- useful present or coal and releases real Santa-green zombies from storage.

local SC = SurvivorCompanion
SC.OddballKris = SC.OddballKris or {}
local Kris = SC.OddballKris
local ID = "christmas_kris_kimbrough"
local GIFTS = { "Base.Bandage", "Base.Lighter", "Base.WaterBottle",
    "Base.HandAxe", "Base.Antibiotics" }
local lines = {
    greet = "Ho, ho. I checked my list. Twice.",
    nice = "You kept people alive. Here. Don't shake it.",
    naughty = "Coal. You know what you did.",
    elves = "The elves are restless. Be good, now.",
    defense = "Even Santa has to lock the door these days.",
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

local function say(group, key)
    local actor = actorFor(group)
    return actor and lines[key] and U().say(actor, lines[key]) == true or false
end

local function near(group, player)
    local actor = actorFor(group)
    return actor and player and U().distance(actor, player) <= 6
        and U().canSee(player, actor) == true
end

local function scoreHistory(ownId)
    local score, offenses = 0, 0
    for _, group in ipairs(SC.Factions and SC.Factions.list(false) or {}) do
        if group.id ~= ownId and group.discovered == true then
            if group.standing == "Trusted" then score = score + 2
            elseif group.standing == "Tolerated" then score = score + 1
            elseif group.standing == "Hostile" then score = score - 2 end
            for _, offense in ipairs(group.offenses or {}) do
                if offense.forgiven ~= true then
                    offenses = offenses + 1
                    score = score - (offense.kind == "murder" and 5 or 2)
                end
            end
        end
    end
    return score, offenses
end

local function findStock(actor, kind)
    local inventory = actor and U().inventory(actor)
    for _, item in ipairs(inventory and U().inventoryItemsDeep(inventory, 160, 8)
        or {}) do
        if U().itemType(item) == kind then return item end
    end
    return nil
end

local function stockRoom(group)
    local site = story(group).site
    local post = site and site.elvesRoom
    local square = post and U().gridSquare(post.x, post.y, post.z or 0)
    return square and U().isSafeSpawnSquare(square) and post or nil
end

local function releaseElves(group, value)
    if value.elvesReleased == true then return true end
    local room = stockRoom(group)
    if not room or type(addZombiesInOutfit) ~= "function" then return false end
    local spawned = pcall(addZombiesInOutfit,
        room.x, room.y, room.z, 2, "SantaGreen", 0)
    if not spawned then return false end
    value.elvesReleased = true
    say(group, "elves")
    return true
end

local function giveCoal(group, player, value)
    if value.coalGiven == true then return true end
    local actor = actorFor(group)
    local source = actor and U().inventory(actor)
    local destination = player and U().inventory(player)
    if not source or not destination then return false, "inventory_unavailable" end
    local coal = findStock(actor, "Base.Charcoal")
        or U().addItem(source, "Base.Charcoal")
    if not coal or not U().transferItemVerified(source, destination, coal) then
        return false, "coal_transfer_failed"
    end
    value.coalGiven = true
    say(group, "naughty")
    return true
end

local function givePresent(group, player, value)
    if value.giftGiven == true then return true end
    local actor = actorFor(group)
    local source = actor and U().inventory(actor)
    local destination = player and U().inventory(player)
    if not source or not destination then return false, "inventory_unavailable" end
    local gift = findStock(actor, "Base.Present_Medium")
        or U().addItem(source, "Base.Present_Medium")
    if not gift then return false, "present_unavailable" end
    if value.giftKind == nil then
        local hash = type(U().stableHash) == "function"
            and U().stableHash(group.id) or #group.id
        value.giftKind = GIFTS[math.abs(hash) % #GIFTS + 1]
    end
    local contents = select(1, U().call(gift, "getInventory"))
    if not contents then return false, "wrapped_present_unavailable" end
    if value.giftPacked ~= true then
        if not U().addItem(contents, value.giftKind) then
            return false, "gift_item_unavailable"
        end
        value.giftPacked = true
    end
    if not U().transferItemVerified(source, destination, gift) then
        return false, "present_transfer_failed"
    end
    value.giftGiven = true
    say(group, "nice")
    return true
end

function Kris.onSpawn(group, actor)
    local value = story(group)
    if not value or not actor then return false, "kris_unavailable" end
    if value.stage == "unmet" then value.stage = "list" end
    return true, "kris_ready"
end

function Kris.pulse(group, player, current)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    if value.stage == "list" and near(group, player)
        and value.greeted ~= true then
        value.greeted = true
        group.discovered = true
        say(group, "greet")
    end
    if value.stage == "naughty" and value.elvesReleased ~= true
        and near(group, player)
        and (tonumber(current) or 0) >= (tonumber(value.nextElfRetryAt) or 0) then
        value.nextElfRetryAt = (tonumber(current) or 0) + 60000
        releaseElves(group, value)
    end
    return true, value.stage
end

function Kris.intentFor(actor, player, snapshot, group)
    if not story(group) then return nil end
    if group.standing == "Hostile" then
        return { mode = "hostile", priority = 110 }
    end
    local threats = type(snapshot) == "table"
        and (tonumber(snapshot.threatCount) or #(snapshot.threats or {})) or 0
    if threats > 0 then return { mode = "zombie_defense", priority = 18 } end
    return { mode = "kris_shop", priority = 30 }
end

function Kris.update(actor, player, runtime, intent, group)
    if not intent or intent.mode ~= "kris_shop" then return false end
    local point = story(group).site and story(group).site.spawn
    if not point then return true, "shop_unavailable" end
    local x, y, z = U().position(actor)
    if x and z == (point.z or 0) and (x - point.x) ^ 2
        + (y - point.y) ^ 2 <= 2.25 then return true, "checking_list" end
    local square = U().gridSquare(point.x, point.y, point.z or 0)
    if not square then return true, "shop_unloaded" end
    if not SC.Navigation or type(SC.Navigation.request) ~= "function" then
        return false, "navigation_unavailable"
    end
    return SC.Navigation.request(actor, square, "walk", {
        action = "faction_shop", arrivalDistance = 1.5 })
end

function Kris.canRecruit()
    return false, "kris_keeps_his_shop"
end

function Kris.menuOptions(group, player)
    local value = story(group)
    if not value or not near(group, player) or value.listChecked == true then
        return {}
    end
    return { { id = "check_list", label = "Ask Kris to check his list",
        enabled = true, detail = "One judgment, based on your faction history" } }
end

function Kris.action(group, action, player)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    if action == "hurt" then
        return SC.Factions.forceStanding(group.id, "Hostile")
    end
    if action ~= "check_list" or value.listChecked == true
        or not near(group, player) then
        return false, "list_check_unavailable"
    end
    if value.judgment == nil then
        local score, offenses = scoreHistory(group.id)
        value.judgment = score < 0 and "naughty" or "nice"
        value.score, value.offensesSeen = score, offenses
    end
    if value.judgment == "nice" then
        local okay, reason = givePresent(group, player, value)
        if not okay then return false, reason end
    else
        local okay, reason = giveCoal(group, player, value)
        if not okay then return false, reason end
        releaseElves(group, value)
    end
    value.listChecked = true
    value.stage = value.judgment
    return true, "kris_" .. value.judgment
end

return Kris
