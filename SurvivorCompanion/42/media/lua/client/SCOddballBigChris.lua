-- SPDX-License-Identifier: MIT
-- Chris visits real bins with the native looting visual, keeps the actual
-- finds in his trash bag, and walks with a native raccoon called Rascal.

local SC = SurvivorCompanion
SC.OddballBigChris = SC.OddballBigChris or {}
local Chris = SC.OddballBigChris
local ID = "big_chris_rascal"
local RASCAL = { kind = "raccoonboar", breed = "grey", name = "Rascal" }
local ART = {
    "Everything is trash. Some folks just put a frame around it.",
    "That's not a painting. That's a wall with an expensive mistake on it.",
    "Now this is good trash. That gallery stuff? Bad trash.",
    "One day computers'll paint pictures. They'll be trash, only faster.",
}

local function U() return SC.GameplayUtil end
local function story(group)
    local value = type(group) == "table" and group.oddball or nil
    if type(value) ~= "table" or value.id ~= ID then return nil end
    value.stage = value.stage or "trash_run"
    value.binIndex = math.max(1, math.floor(tonumber(value.binIndex) or 1))
    value.trades = math.max(0, math.floor(tonumber(value.trades) or 0))
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
local function itemFor(actor, kind)
    local inventory = actor and U().inventory(actor)
    for _, item in ipairs(inventory and U().inventoryItemsDeep(inventory,
        180, 8) or {}) do
        if U().itemType(item) == kind then return item end
    end
    return nil
end
local function bagFor(actor)
    local bag = itemFor(actor, "Base.Bag_TrashBag")
    return bag and select(1, U().call(bag, "getInventory")) or nil
end
local function binContainer(group, index)
    local value = story(group)
    local locator = value.site and value.site.bins
        and value.site.bins[index]
    if not locator or not SC.Factions then return nil end
    return SC.Factions.resolveQuestContainer(locator,
        nil, nil)
end
local function ageHours()
    local time = type(getGameTime) == "function" and getGameTime() or nil
    local raw = time and select(1, U().call(time, "getWorldAgeHours"))
    return tonumber(raw)
end
local function playerCarriesRascal(group, player)
    local _, record = SC.OddballAnimals.find(group, 1)
    if not record or not player then return false end
    local inventory = U().inventory(player)
    for _, item in ipairs(inventory and U().inventoryItemsDeep(inventory,
        180, 8) or {}) do
        local animal = select(1, U().call(item, "getAnimal"))
        local id = animal and select(1,
            U().call(animal, "getAnimalID"))
        if tonumber(id) == tonumber(record.id) then return true end
    end
    return false
end
local function offering(player)
    local inventory = player and U().inventory(player)
    for _, item in ipairs(inventory and U().inventoryItemsDeep(inventory,
        200, 8) or {}) do
        local kind = U().itemType(item)
        if kind == "Base.PorkRinds" or kind == "Base.Crisps"
            or type(kind) == "string" and (string.find(kind,
                "Ring_", 1, true) or string.find(kind,
                "Necklace_", 1, true)) then return item end
    end
    return nil
end

function Chris.onSpawn(group, actor)
    local value = story(group)
    if not value or not actor then return false, "chris_unavailable" end
    local inventory = U().inventory(actor)
    if not inventory then return false, "trash_inventory_unavailable" end
    if value.gearSeeded ~= true then
        local plunger = itemFor(actor, "Base.Plunger_BarbedWire")
            or U().addItem(inventory, "Base.Plunger_BarbedWire")
        local bag = itemFor(actor, "Base.Bag_TrashBag")
            or U().addItem(inventory, "Base.Bag_TrashBag")
        if not plunger or not bag then return false, "chris_gear_unavailable" end
        U().call(actor, "setPrimaryHandItem", plunger)
        local bagInventory = select(1, U().call(bag, "getInventory"))
        if bagInventory then
            for _, kind in ipairs({ "Base.Paperclip", "Base.DuctTape",
                "Base.Screwdriver", "Base.Twine" }) do
                U().addItem(bagInventory, kind)
            end
            local hash = U().stableHash and U().stableHash(group.id) or 0
            if hash % 8 == 0 then
                U().addItem(bagInventory, "Base.Spiffo")
            end
        end
        for _ = 1, 3 do U().addItem(inventory, "Base.BeerCan") end
        local nutrition = select(1, U().call(actor, "getNutrition"))
        if nutrition then U().call(nutrition, "setWeight", 125) end
        value.gearSeeded = true
    end
    if SC.OddballAnimals.status(group, 1) == "unseeded" then
        local post = value.site and value.site.animalSpawns
            and value.site.animalSpawns[1]
        if post then SC.OddballAnimals.spawn(group, 1, RASCAL, post) end
    end
    return true, "chris_and_rascal_ready"
end

function Chris.pulse(group, player, current)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    local actor = actorFor(group)
    if not actor then return false, "chris_unloaded" end
    if SC.OddballAnimals.status(group, 1) == "unseeded"
        and current >= (tonumber(value.nextRascalRetryAt) or 0) then
        value.nextRascalRetryAt = current + 30000
        local post = value.site and value.site.animalSpawns
            and value.site.animalSpawns[1]
        if post then SC.OddballAnimals.spawn(group, 1, RASCAL, post) end
    end
    local animalState = SC.OddballAnimals.status(group, 1)
    if animalState == "dead" and value.stage ~= "grieving"
        and value.stage ~= "gone" then
        value.stage = "grieving"
        value.griefStartedHour = ageHours()
        U().say(actor, "Rascal? Rascal, wake up. We still got bins to check.")
    elseif animalState == "alive" then
        SC.OddballAnimals.follow(group, 1, actor, current)
    end
    if value.stage == "grieving" and value.griefStartedHour
        and ageHours() and ageHours() - value.griefStartedHour >= 24
        and player and U().canSee(player, actor) ~= true
        and U().distance(player, actor) >= 20
        and SC.Actor and SC.Actor.remove and SC.Actor.remove(actor) then
        local member = group.members and group.members[1]
        if member then member.actorId, member.departed = nil, true end
        value.stage = "gone"
        group.lifecycle = "destroyed"
        if SC.Oddballs then SC.Oddballs.retire(group, "rascal_gone") end
    end
    if near(group, player) and value.greeted ~= true then
        value.greeted = true
        group.discovered = true
        U().say(actor,
            "This here's Rascal. He's my best friend and my business partner. Everything's trash, but some trash is useful.")
    end
    if near(group, player) and value.stage == "trash_run"
        and current >= (tonumber(value.nextArtAt) or 0) then
        value.nextArtAt = current + 120000
        value.artIndex = ((tonumber(value.artIndex) or 0) % #ART) + 1
        U().say(actor, ART[value.artIndex])
    end
    return true, value.stage
end

function Chris.pulseRecruited(group, actor, player, current)
    return SC.OddballAnimals.follow(group, 1, actor, current)
end

function Chris.intentFor(actor, player, snapshot, group)
    local value = story(group)
    if not value then return nil end
    if group.standing == "Hostile" then
        return { mode = "hostile", priority = 110 }
    end
    local threats = type(snapshot) == "table"
        and (tonumber(snapshot.threatCount) or #(snapshot.threats or {})) or 0
    if threats > 0 then return { mode = "zombie_defense", priority = 18 } end
    if playerCarriesRascal(group, player) then
        return { mode = "chris_chase_rascal", priority = 70 }
    end
    if value.stage == "trash_run" then
        return { mode = "chris_search_bins", priority = 38 }
    end
    return { mode = "oddball_idle", priority = 28 }
end

function Chris.update(actor, player, runtime, intent, group)
    local value = story(group)
    if not value or not intent then return false, "chris_idle" end
    if intent.mode == "chris_chase_rascal" then
        if not player or not SC.Navigation then
            return false, "rascal_carrier_unavailable" end
        U().say(actor, "Put Rascal down! He hates being carried by strangers!")
        return SC.Navigation.request(actor, U().squareOf(player),
            "run", { action = "chris_chase_rascal", arrivalDistance = 2 })
    end
    if intent.mode ~= "chris_search_bins" then return false, "chris_idle" end
    local bins = value.site and value.site.bins or {}
    if #bins == 0 then return false, "trash_bins_missing" end
    if value.searchingBin then
        local status = SC.NativeActions and SC.NativeActions.visualStatus
            and SC.NativeActions.visualStatus(actor, "loot_container") or "none"
        if status == "active" then return true, "searching_real_bin" end
        if status == "completed" then
            local container = binContainer(group, value.searchingBin)
            local bag = bagFor(actor)
            local items = container and U().inventoryItemsDeep(container, 32, 2)
                or {}
            local item = items[1]
            if item and bag then U().transferItemVerified(container, bag, item) end
            U().say(actor, item and
                "Finders keepers! Useful trash right here." or
                "Nothing in this one. Next lid.")
        end
        if SC.NativeActions and SC.NativeActions.clearVisual then
            SC.NativeActions.clearVisual(actor)
        end
        value.searchingBin = nil
        value.binIndex = value.binIndex % #bins + 1
        local hour = ageHours()
        value.nextSearchHour = hour and hour + 1 / 6 or nil
        return true, "finished_bin_search"
    end
    local hour = ageHours()
    if hour and hour < (tonumber(value.nextSearchHour) or 0) then
        return true, "bin_run_interval"
    end
    if player and U().distance(actor, player) > 65 then
        return true, "bin_outside_loading_range"
    end
    local index = value.binIndex
    local post = bins[index]
    local container = binContainer(group, index)
    if not post or not container then
        value.binIndex = index % #bins + 1
        value.nextSearchHour = hour and hour + 1 / 6 or nil
        return false, "bin_unavailable"
    end
    local square = U().gridSquare(post.x, post.y, post.z or 0)
    local owner = select(1, U().call(container, "getParent"))
    local arrived, targets = U().directInteractionAccess(actor,
        owner or square)
    if not arrived then
        if not SC.Navigation or type(SC.Navigation.requestAny) ~= "function"
            or #targets == 0 then return false, "bin_access_blocked" end
        return SC.Navigation.requestAny(actor, targets, "run", {
            action = "chris_run_to_bin", container = container,
            targetSquare = square, continuousApproach = true })
    end
    local started, reason = U().move(actor, "walk", {
        action = "loot_container", container = container,
        lootPosition = "Low", targetSquare = square })
    if started then
        value.searchingBin = index
        return true, "searching_real_bin"
    end
    return false, reason or "bin_visual_rejected"
end

function Chris.canRecruit(group)
    local value = story(group)
    return value and value.trades >= 3 and value.stage == "trash_run"
        and group.standing == "Trusted" or false,
        "trade_three_presents_and_keep_rascal_safe"
end

function Chris.menuOptions(group, player)
    local value = story(group)
    if not value or not near(group, player) then return {} end
    return {
        { id = "ask_art", label = "Ask Chris to review the art",
            enabled = true },
        { id = "trade_present", label = "Offer Chris a snack or shiny thing",
            enabled = offering(player) ~= nil and bagFor(actorFor(group)) ~= nil },
        { id = "recruit", label = "Ask Chris and Rascal to join",
            enabled = Chris.canRecruit(group) == true },
    }
end

function Chris.action(group, action, player)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    if action == "hurt" or action == "animal_hurt" then
        value.stage = "hostile"
        U().say(actorFor(group),
            "You hurt Rascal? This plunger's got your name on it!")
        return SC.Factions.forceStanding(group.id, "Hostile")
    end
    if not near(group, player) then return false, "trash_runner_too_far" end
    local actor = actorFor(group)
    if action == "ask_art" then
        value.artIndex = ((tonumber(value.artIndex) or 0) % #ART) + 1
        U().say(actor, ART[value.artIndex])
        return true, "chris_reviewed_art"
    end
    if action == "trade_present" then
        local payment = offering(player)
        local bag = bagFor(actor)
        local goods = bag and U().inventoryItemsDeep(bag, 80, 3) or {}
        local gift = goods[1]
        local source = payment and select(1,
            U().call(payment, "getContainer"))
        if not source or not bag or not gift then
            return false, "present_or_trash_missing"
        end
        local actorInventory, playerInventory = U().inventory(actor),
            U().inventory(player)
        if not U().transferItemVerified(source, actorInventory, payment) then
            return false, "present_transfer_failed"
        end
        if not U().transferItemVerified(bag, playerInventory, gift) then
            U().transferItemVerified(actorInventory, source, payment)
            return false, "trash_gift_transfer_failed"
        end
        value.trades = value.trades + 1
        if value.trades >= 3 then
            SC.Factions.forceStanding(group.id, "Trusted")
        else
            SC.Factions.adjustStanding(group.id, 10, "chris_present")
        end
        U().say(actor,
            "Pork rinds? You're my second best friend now. Here, this is good trash.")
        return true, "real_trash_present_traded"
    end
    if action == "recruit" and Chris.canRecruit(group) == true
        and SC.FactionRecruitment then
        local asked, reason = SC.FactionRecruitment.ask(group.id, player, false)
        if not asked then return false, reason end
        return SC.FactionRecruitment.startTrial(group.id, player, false)
    end
    return false, "chris_choice_unavailable"
end

return Chris
