-- SPDX-License-Identifier: MIT
-- Aunt Velma's reading points to a real, stocked container in a loaded house.
-- Her weather line reads the game's forecaster rather than inventing rain.

local SC = SurvivorCompanion
SC.OddballVelma = SC.OddballVelma or {}
local Velma = SC.OddballVelma
local ID = "seer_aunt_velma_crisp"
local PAYMENT = { ["Base.CigarettePack"] = true,
    ["Base.Coffee2"] = true }
local REWARDS = { "Base.FirstAidKit", "Base.Bullets9mmBox",
    "Base.CannedPeaches" }

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

local function near(group, player)
    local actor = actorFor(group)
    return actor and player and U().distance(actor, player) <= 6
        and U().canSee(player, actor) == true
end

local function paymentFor(player)
    local inventory = player and U().inventory(player)
    for _, item in ipairs(inventory and U().inventoryItemsDeep(inventory,
        160, 8) or {}) do
        if PAYMENT[U().itemType(item)] == true then return item end
    end
    return nil
end

local function weatherForecast()
    if type(getClimateManager) ~= "function" then return nil end
    local okay, climate = pcall(getClimateManager)
    if not okay or not climate then return nil end
    local forecaster = select(1, U().call(climate, "getClimateForecaster"))
    local forecasts = select(1, U().call(forecaster, "getForecasts"))
    local rawCount = forecasts and select(1, U().call(forecasts,
        "size")) or nil
    local count = tonumber(rawCount) or 0
    if count < 2 then return nil end
    local nextDay = select(1, U().call(forecasts, "get", 1))
    local name = nextDay and select(1, U().call(nextDay, "getName"))
    return type(name) == "string" and name or nil
end

local function cacheContainer(player, group)
    if not SC.Factions or type(SC.Factions.findHouse) ~= "function"
        or type(SC.Factions.resolveQuestContainer) ~= "function" then
        return nil, nil, "house_search_unavailable"
    end
    local house, reason = SC.Factions.findHouse(player, {
        purpose = "quest", sourceFactionId = group.id,
        minimumDistance = 30, maximumDistance = 100,
        sampleBudget = 48 })
    if not house or not house.questContainer then
        return nil, nil, reason or "no_loaded_cache_house"
    end
    local container, locatorReason = SC.Factions.resolveQuestContainer(
        house.questContainer, house.bounds, house.anchor)
    if not container then return nil, nil,
        locatorReason or "cache_container_unavailable" end
    return container, house
end

function Velma.onSpawn(group, actor)
    local value = story(group)
    if not value or not actor then return false, "seer_unavailable" end
    local inventory = U().inventory(actor)
    if not inventory then return false, "seer_inventory_unavailable" end
    if value.deckSeeded ~= true then
        local deck = U().addItem(inventory, "Base.TarotCardDeck")
        if not deck then return false, "tarot_deck_unavailable" end
        value.deckSeeded = true
    end
    return true, "seer_ready"
end

function Velma.pulse(group, player)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    if near(group, player) and value.greeted ~= true then
        value.greeted = true
        group.discovered = true
        U().say(actorFor(group), "Sit. Cut the deck. No, the other way.")
    end
    return true, value.stage
end

function Velma.intentFor(actor, player, snapshot, group)
    if not story(group) then return nil end
    if group.standing == "Hostile" then
        return { mode = "hostile", priority = 110 }
    end
    local threats = type(snapshot) == "table"
        and (tonumber(snapshot.threatCount) or #(snapshot.threats or {})) or 0
    if threats > 0 then return { mode = "zombie_defense", priority = 18 } end
    return { mode = "velma_home", priority = 30 }
end

function Velma.update(actor, player, runtime, intent, group)
    if not intent or intent.mode ~= "velma_home" then return false end
    local post = story(group).site and story(group).site.spawn
    if not post then return true, "motel_room_unavailable" end
    local x, y, z = U().position(actor)
    if x and z == (post.z or 0)
        and (x - post.x) ^ 2 + (y - post.y) ^ 2 <= 2.25 then
        return true, "reading_cards"
    end
    local square = U().gridSquare(post.x, post.y, post.z or 0)
    if not square then return true, "motel_unloaded" end
    if not SC.Navigation or type(SC.Navigation.request) ~= "function" then
        return false, "navigation_unavailable"
    end
    return SC.Navigation.request(actor, square, "walk", {
        action = "faction_home", arrivalDistance = 1.5 })
end

function Velma.canRecruit(group)
    local value = story(group)
    return value and value.stage == "reading_complete" or false,
        "take_a_reading_first"
end

function Velma.menuOptions(group, player)
    local value = story(group)
    if not value or not near(group, player) then return {} end
    return { { id = "read_cards", label = "Pay Velma for a reading",
        enabled = value.stage ~= "reading_complete"
            and paymentFor(player) ~= nil },
        { id = "repeat_reading", label = "Ask where the cache is",
            enabled = value.stage == "reading_complete" } }
end

function Velma.action(group, action, player)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    if action == "hurt" then
        return SC.Factions.forceStanding(group.id, "Hostile")
    end
    if not near(group, player) then return false, "seer_too_far" end
    local actor = actorFor(group)
    if action == "repeat_reading" and value.stage == "reading_complete" then
        U().say(actor, "The cards don't move the cache. "
            .. tostring(value.cacheAddress))
        return true, "cache_location_repeated"
    end
    if action ~= "read_cards" then return false, "unknown_seer_choice" end
    if value.stage == "reading_complete" then
        return false, "reading_already_given"
    end
    local payment = paymentFor(player)
    if not payment then return false, "coffee_or_cigarettes_required" end
    local container, house, reason = cacheContainer(player, group)
    if not container then return false, reason end
    local source = select(1, U().call(payment, "getContainer"))
    local destination = U().inventory(actor)
    if not source or not destination then return false, "payment_container_unavailable" end
    if not U().transferItemVerified(source, destination, payment) then
        return false, "payment_transfer_failed"
    end
    local hash = type(U().stableHash) == "function"
        and U().stableHash(tostring(group.id)) or 0
    local rewardType = REWARDS[(hash % #REWARDS) + 1]
    local reward = U().addItem(container, rewardType)
    if not reward then
        U().transferItemVerified(destination, source, payment)
        return false, "cache_item_unavailable"
    end
    local data = U().modData(reward)
    if type(data) == "table" then data.lfVelmaCacheGroupId = group.id end
    local location = SC.Factions.describeLocation(house.anchor)
    value.stage = "reading_complete"
    value.cacheAddress = location and location.address
        or tostring(house.anchor.x) .. ", " .. tostring(house.anchor.y)
    value.cacheType = rewardType
    value.cacheLocator = house.questContainer
    value.cacheHouseId = house.id
    U().say(actor, "The Tower, reversed. A cupboard at "
        .. value.cacheAddress .. ". Look before the dead do.")
    local forecast = weatherForecast()
    if forecast then U().say(actor,
        "Tomorrow's sky? " .. forecast .. ". The cards don't lie, sugar.") end
    return true, "real_cache_reading_complete"
end

return Velma
