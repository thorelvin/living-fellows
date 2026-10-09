-- SPDX-License-Identifier: MIT
-- Five small Muldraugh stories share existing resident, trade, combat, and
-- recruitment machinery. Only their dialogue and one-shot bargains differ.

local SC = SurvivorCompanion
SC.OddballSins = SC.OddballSins or {}
local Sins = SC.OddballSins
local KIND = {
    sin_gluttony_bonnie = "gluttony", sin_greed_lyman = "greed",
    sin_sloth_harlan = "sloth", sin_wrath_duane = "wrath",
    sin_pride_darlene = "pride",
}
local lines = {
    gluttony = {
        greet = "The ovens quit before I did. Funny, that. I'm still hungry.",
        bargain = "Chocolate cake? Lord, put it here. Take the canned stuff.",
        theft = "I saw you take that. My shelves are not your pantry.",
    },
    greed = {
        greet = "Paper money is paper. Gold still has a pulse.",
        bargain = "A little gold for a little lead. Everybody leaves heavier.",
        empty = "That's my last box. I might have misjudged the market.",
    },
    sloth = {
        greet = "Been in this chair since July. Legs work. Just don't see a reason.",
        bargain = "Water? That's kindness. The key's yours. Safe's in the house.",
        idle = "If the dead want me, they can come in and sit a spell.",
    },
    wrath = {
        greet = "Put down the iron. We can settle this with a bat and a bruise.",
        challenge = "One round. No guns, no friends jumping in.",
        win = "That's enough. You earned my respect. Need a fighter?",
        forfeit = "You brought a gun to a fistfight. Round's over.",
    },
    pride = {
        greet = "Miss Muldraugh, 1979. You may address me properly.",
        royal = "Your Majesty. There, you do have manners. Take my makeup kit.",
        ordinary = "Wrong. The words are 'Your Majesty.' Try again.",
    },
}
local nextLineAt = {}

local function U() return SC.GameplayUtil end

local function story(group)
    local value = type(group) == "table" and group.oddball or nil
    if type(value) ~= "table" or not KIND[value.id] then return nil end
    value.stage = value.stage or "unmet"
    return value, KIND[value.id]
end

local function actorFor(group)
    local member = group and group.members and group.members[1]
    local record = member and member.actorId and SC.Registry
        and SC.Registry.byId(member.actorId) or nil
    return record and record.actor and U().isValidActor(record.actor)
        and record.actor or nil
end

local function say(group, kind, key)
    local actor = actorFor(group)
    local line = lines[kind] and lines[kind][key]
    return actor and line and U().say(actor, line) == true or false
end

local function near(group, player)
    local actor = actorFor(group)
    return actor and player and U().distance(actor, player) <= 6
        and U().canSee(player, actor) == true
end

local function itemFor(actor, test)
    local inventory = actor and U().inventory(actor)
    for _, item in ipairs(inventory and U().inventoryItemsDeep(inventory, 160, 8)
        or {}) do
        if test(U().itemType(item)) then return item end
    end
    return nil
end

local function exact(kind)
    return function(value) return value == kind end
end

local function jewelry(kind)
    return type(kind) == "string"
        and (string.find(kind, "Base.Ring_", 1, true) == 1
            or string.find(kind, "Base.Necklace_", 1, true) == 1)
        and not string.find(kind, "DogTag", 1, true)
end

local function disallowedWeapon(player)
    for _, hand in ipairs({ "getPrimaryHandItem", "getSecondaryHandItem" }) do
        local item = select(1, U().call(player, hand))
        local kind = item and U().itemType(item)
        if kind and kind ~= "Base.ShortBat" then
            local category = select(1, U().call(item, "getCategory"))
            if category == "Weapon" then return true end
        end
    end
    return false
end

local function setStanding(group, standing)
    if not SC.Factions or type(SC.Factions.forceStanding) ~= "function" then
        return false, "faction_standing_unavailable"
    end
    return SC.Factions.forceStanding(group.id, standing)
end

local function transfer(group, player, offered, reward)
    local resident = actorFor(group)
    local residentInventory = resident and U().inventory(resident)
    local playerInventory = player and U().inventory(player)
    local source = offered and select(1, U().call(offered, "getContainer"))
    if not source or not residentInventory or not playerInventory or not reward then
        return false, "trade_items_unavailable"
    end
    if not U().transferItemVerified(source, residentInventory, offered) then
        return false, "offer_transfer_failed"
    end
    if not U().transferItemVerified(residentInventory,
        playerInventory, reward) then
        U().transferItemVerified(residentInventory, source, offered)
        return false, "reward_transfer_failed"
    end
    return true, "one_shot_trade_complete"
end

function Sins.onSpawn(group, actor)
    local value, kind = story(group)
    if not value or not actor then return false, "sin_unavailable" end
    if value.stockSeeded == true then return true, "sin_stock_ready" end
    local inventory = U().inventory(actor)
    if not inventory then return false, "sin_inventory_unavailable" end
    local stock = {
        gluttony = "Base.CannedPeaches", greed = "Base.Bullets9mmBox",
        sloth = "Base.Key1", wrath = "Base.ShortBat",
        pride = "Base.MakeupCase_Professional",
    }
    local target = stock[kind]
    local item = itemFor(actor, exact(target)) or U().addItem(inventory, target)
    if not item then return false, "sin_stock_unavailable" end
    if kind == "sloth" then
        U().call(item, "setName", "Harlan's gun-safe key")
        local site = value.site and value.site.spawn
        local square = site and U().gridSquare(site.x, site.y, site.z or 0)
        local building = select(1, U().call(square, "getBuilding"))
        local definition = select(1, U().call(building, "getDef"))
        local keyId = select(1, U().call(definition, "getKeyId"))
        if tonumber(keyId) then U().call(item, "setKeyId", keyId) end
    end
    if kind == "wrath" then
        U().call(actor, "setPrimaryHandItem", item)
    end
    value.stockSeeded = true
    if value.stage == "unmet" then value.stage = "waiting" end
    return true, "sin_ready"
end

function Sins.pulse(group, player, current)
    local value, kind = story(group)
    if not value then return false, "wrong_oddball" end
    if near(group, player) and value.greeted ~= true then
        value.greeted = true
        group.discovered = true
        say(group, kind, "greet")
    end
    if kind == "wrath" and value.stage == "duel" then
        if disallowedWeapon(player) then
            value.stage = "forfeit"
            setStanding(group, "Wary")
            say(group, kind, "forfeit")
            return true, "duel_forfeited"
        end
        local resident = actorFor(group)
        if resident and SC.Medical and type(SC.Medical.assess) == "function" then
            local okay, medical = pcall(SC.Medical.assess, resident)
            if okay and medical and tonumber(medical.health)
                and medical.health <= 45 and medical.alive ~= false then
                value.stage = "won"
                setStanding(group, "Trusted")
                U().stop(resident)
                say(group, kind, "win")
                return true, "duel_won"
            end
        end
    end
    if kind == "sloth" and near(group, player)
        and current >= (nextLineAt[group.id] or 0) then
        nextLineAt[group.id] = current + 180000
        say(group, kind, "idle")
    end
    return true, value.stage
end

function Sins.intentFor(actor, player, snapshot, group)
    local value = story(group)
    if not value then return nil end
    if value.stage == "duel" or group.standing == "Hostile" then
        return { mode = "hostile", priority = 110 }
    end
    local threats = type(snapshot) == "table"
        and (tonumber(snapshot.threatCount) or #(snapshot.threats or {})) or 0
    if threats > 0 then return { mode = "zombie_defense", priority = 18 } end
    return { mode = "sin_home", priority = 30 }
end

function Sins.update(actor, player, runtime, intent, group)
    if not intent or intent.mode ~= "sin_home" then return false end
    local site = story(group).site
    local point = site and site.spawn
    if not point then return true, "sin_home_unavailable" end
    local x, y, z = U().position(actor)
    if x and z == (point.z or 0) and (x - point.x) ^ 2
        + (y - point.y) ^ 2 <= 2.25 then return true, "sin_holding_home" end
    local square = U().gridSquare(point.x, point.y, point.z or 0)
    if not square then return true, "sin_home_unloaded" end
    if not SC.Navigation or type(SC.Navigation.request) ~= "function" then
        return false, "navigation_unavailable"
    end
    return SC.Navigation.request(actor, square, "walk", {
        action = "faction_home", arrivalDistance = 1.5 })
end

function Sins.canRecruit(group)
    local value, kind = story(group)
    return kind == "wrath" and value.stage == "won",
        kind == "wrath" and "win_the_duel_first" or "resident_stays_home"
end

function Sins.menuOptions(group, player)
    local value, kind = story(group)
    if not value or not near(group, player) then return {} end
    if kind == "gluttony" then
        return { { id = "trade_sweets", label = "Trade chocolate cake for food",
            enabled = itemFor(player, exact("Base.CakeChocolate")) ~= nil
                and itemFor(actorFor(group), exact("Base.CannedPeaches")) ~= nil } }
    elseif kind == "greed" then
        return { { id = "trade_jewelry", label = "Trade jewelry for ammunition",
            enabled = itemFor(player, jewelry) ~= nil
                and itemFor(actorFor(group), exact("Base.Bullets9mmBox")) ~= nil } }
    elseif kind == "sloth" then
        return { { id = "fetch_water", label = "Bring Harlan a bottle of water",
            enabled = itemFor(player, exact("Base.WaterBottle")) ~= nil
                and itemFor(actorFor(group), exact("Base.Key1")) ~= nil } }
    elseif kind == "wrath" and value.stage == "waiting" then
        return { { id = "challenge", label = "Accept Duane's bat duel",
            enabled = not disallowedWeapon(player),
            detail = "No firearms or blades; one short bat is provided" } }
    elseif kind == "pride" and value.stage ~= "royal" then
        return {
            { id = "royal_address", label = "Address her as Your Majesty",
                enabled = true },
            { id = "ordinary_address", label = "Call her Darlene",
                enabled = true },
        }
    end
    return {}
end

function Sins.action(group, action, player)
    local value, kind = story(group)
    if not value then return false, "wrong_oddball" end
    if action == "shoplift" and kind == "gluttony" then
        value.stage = "hostile"
        say(group, kind, "theft")
        return setStanding(group, "Hostile")
    end
    if action == "hurt" then
        if kind == "wrath" and value.stage == "duel" then
            return Sins.pulse(group, player, U().nowMs())
        end
        value.stage = "hostile"
        return setStanding(group, "Hostile")
    end
    if action == "hit_player" and kind == "wrath"
        and value.stage == "duel" then return true, "duel_in_progress" end
    if not near(group, player) then return false, "resident_too_far" end
    if action == "trade_sweets" and kind == "gluttony" then
        local accepted, reason = transfer(group, player,
            itemFor(player, exact("Base.CakeChocolate")),
            itemFor(actorFor(group), exact("Base.CannedPeaches")))
        if accepted then say(group, kind, "bargain") end
        return accepted, reason
    elseif action == "trade_jewelry" and kind == "greed" then
        local accepted, reason = transfer(group, player,
            itemFor(player, jewelry),
            itemFor(actorFor(group), exact("Base.Bullets9mmBox")))
        if accepted then say(group, kind, "bargain") end
        return accepted, reason
    elseif action == "fetch_water" and kind == "sloth" then
        local accepted, reason = transfer(group, player,
            itemFor(player, exact("Base.WaterBottle")),
            itemFor(actorFor(group), exact("Base.Key1")))
        if accepted then say(group, kind, "bargain") end
        return accepted, reason
    elseif action == "challenge" and kind == "wrath"
        and value.stage == "waiting" then
        if disallowedWeapon(player) then return false, "armed_duel_refused" end
        local inventory = U().inventory(player)
        if not inventory then return false, "player_inventory_unavailable" end
        if not itemFor(player, exact("Base.ShortBat"))
            and value.playerBatIssued ~= true then
            if not U().addItem(inventory, "Base.ShortBat") then
                return false, "duel_bat_unavailable"
            end
            value.playerBatIssued = true
        end
        local changed, reason = setStanding(group, "Hostile")
        if not changed then return false, reason end
        value.stage = "duel"
        say(group, kind, "challenge")
        return true, "duel_started"
    elseif action == "royal_address" and kind == "pride"
        and value.stage ~= "royal" then
        local resident = actorFor(group)
        local source = resident and U().inventory(resident)
        local destination = player and U().inventory(player)
        local gift = itemFor(resident, exact("Base.MakeupCase_Professional"))
        if not source or not destination or not gift
            or not U().transferItemVerified(source, destination, gift) then
            return false, "makeup_gift_unavailable"
        end
        value.stage = "royal"
        say(group, kind, "royal")
        return true, "royal_address_accepted"
    elseif action == "ordinary_address" and kind == "pride" then
        say(group, kind, "ordinary")
        return true, "royal_address_requested"
    end
    return false, "unknown_sin_choice"
end

return Sins
