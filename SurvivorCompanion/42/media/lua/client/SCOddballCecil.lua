-- SPDX-License-Identifier: MIT
-- Cecil owns the gun-shop threshold. The warning is one per visit; ordinary
-- faction combat handles the fight after he has given the player time to back up.

local SC = SurvivorCompanion
SC.OddballCecil = SC.OddballCecil or {}
local Cecil = SC.OddballCecil
local ID = "gunshop_cecil_haskins"
local warningAt = {}
local cannedFood = {
    ["Base.CannedCorn"] = true, ["Base.CannedCornedBeef"] = true,
    ["Base.CannedPeas"] = true, ["Base.CannedCarrots"] = true,
    ["Base.CannedSardines"] = true,
}

local lines = {
    greet = { "That tape's the border. You're a foreign country.",
        "That tape's the border. You're a foreign country." },
    warn = { "Cross that tape and I'll blow your goddamn head off.",
        "Cross that tape and I'll blow your fool head off." },
    holster = { "Holster that, or I'll holster you.",
        "Holster that, or I'll holster you." },
    hostile = { "Last fella said he was friendly too. He's out back.",
        "Last fella said he was friendly too. He's out back." },
    trade = { "Prices went up. Supply and demand. Mostly demand.",
        "Prices went up. Supply and demand. Mostly demand." },
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
    return value
end

local function actorFor(group)
    local member = group and group.members and group.members[1]
    local record = member and member.actorId and SC.Registry
        and SC.Registry.byId(member.actorId)
    return record and record.actor or nil
end

local function speak(group, beat)
    local actor, choice = actorFor(group), lines[beat]
    if not actor or not choice then return false end
    return U().say(actor, choice[U().config("profanityEnabled") == false
        and 2 or 1]) == true
end

local function distance(group, player)
    local anchor = story(group).site and story(group).site.spawn
    local x, y, z = U().position(player)
    if not anchor or not x or z ~= (anchor.z or 0) then return math.huge end
    return math.sqrt((x - anchor.x) ^ 2 + (y - anchor.y) ^ 2)
end

local function armed(player)
    local held = select(1, U().call(player, "getPrimaryHandItem"))
    if not held then return false end
    return U().instanceOf(held, "HandWeapon")
        or U().hasMethod(held, "getMaxDamage")
end

local function itemFor(actor, kind)
    local inventory = actor and U().inventory(actor)
    for _, item in ipairs(inventory and U().inventoryItemsDeep(inventory, 160, 8)
        or {}) do
        if U().itemType(item) == kind then return item end
    end
    return nil
end

local function cleanWater(item)
    if U().itemType(item) ~= "Base.WaterBottle" then return false end
    local fluid = select(1, U().call(item, "getFluidContainer"))
    if not fluid then return false end
    local amount = number(select(1, U().call(fluid, "getAmount"))) or 0
    local safe = select(1, U().call(fluid, "isFilledWithCleanWater"))
    local tainted = select(1, U().call(fluid, "isTainted"))
    return amount >= 0.75 and safe == true and tainted ~= true
end

local function paymentItems(player, kind)
    local result = {}
    local inventory = player and U().inventory(player)
    for _, item in ipairs(inventory and U().inventoryItemsDeep(inventory, 240, 12)
        or {}) do
        if kind == "food" and cannedFood[U().itemType(item)]
            or kind == "water" and cleanWater(item) then
            result[#result + 1] = item
        end
    end
    return result
end

local function hostile(group, value)
    if value.stage == "hostile" then return true end
    value.stage = "hostile"
    warningAt[group.id] = nil
    SC.Factions.forceStanding(group.id, "Hostile")
    speak(group, "hostile")
    return true
end

function Cecil.onSpawn(group, actor)
    local value = story(group)
    if not value or not actor then return false, "cecil_unavailable" end
    local inventory = U().inventory(actor)
    if not inventory then return false, "cecil_inventory_unavailable" end
    local gun = itemFor(actor, "Base.DoubleBarrelShotgun")
    if not gun and value.equipmentSeeded ~= true then
        gun = U().addItem(inventory, "Base.DoubleBarrelShotgun")
    end
    if gun then
        U().call(actor, "setPrimaryHandItem", gun)
        U().call(actor, "setSecondaryHandItem", gun)
    end
    if value.equipmentSeeded ~= true and gun then
        for _ = 1, 3 do U().addItem(inventory, "Base.ShotgunShellsBox") end
        U().addItem(inventory, "Base.DuctTape")
        value.equipmentSeeded = true
    end
    return true, gun and "cecil_ready" or "cecil_gun_removed"
end

function Cecil.pulse(group, player, current)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    if value.stage == "hostile" then return true, "cecil_hostile" end
    local range = distance(group, player)
    if range > 12 then
        value.warnedVisit = false
        value.compliedVisit = false
        warningAt[group.id] = nil
        if value.stage == "warned" then value.stage = "open" end
        return true, "outside_shop"
    end
    if value.stage == "unmet" then
        value.stage = "open"
        group.discovered = true
        speak(group, "greet")
    end
    local violation = range <= 4 or range <= 6 and armed(player)
    if violation then
        if value.compliedVisit == true then
            hostile(group, value)
        elseif value.warnedVisit ~= true then
            value.warnedVisit = true
            value.stage = "warned"
            warningAt[group.id] = current + 5000
            speak(group, armed(player) and "holster" or "warn")
        else
            warningAt[group.id] = warningAt[group.id] or current + 5000
            if current >= warningAt[group.id] then hostile(group, value) end
        end
    elseif value.stage == "warned" then
        value.stage = "open"
        value.compliedVisit = true
        warningAt[group.id] = nil
    end
    return true, value.stage
end

function Cecil.intentFor(actor, player, snapshot, group)
    local value = story(group)
    if not value then return nil end
    if value.stage == "hostile" or group.standing == "Hostile" then
        return { mode = "hostile", priority = 110 }
    end
    local threatCount = type(snapshot) == "table"
        and (number(snapshot.threatCount) or #(snapshot.threats or {})) or 0
    if threatCount > 0 then return { mode = "zombie_defense", priority = 18 } end
    return { mode = "cecil_perch", priority = 30 }
end

function Cecil.update(actor, player, runtime, intent, group)
    if not intent or intent.mode ~= "cecil_perch" then return false end
    local anchor = story(group).site and story(group).site.spawn
    if not anchor then return true, "perch_unavailable" end
    local x, y, z = U().position(actor)
    if x and z == (anchor.z or 0) and (x - anchor.x) ^ 2
        + (y - anchor.y) ^ 2 <= 2.25 then
        return true, "holding_counter"
    end
    local square = U().gridSquare(anchor.x, anchor.y, anchor.z or 0)
    if not square then return true, "perch_unloaded" end
    if not SC.Navigation or type(SC.Navigation.request) ~= "function" then
        return false, "navigation_unavailable"
    end
    return SC.Navigation.request(actor, square, "walk", {
        action = "faction_gunshop", arrivalDistance = 1.5 })
end

function Cecil.canRecruit(group)
    return false, "cecil_never_leaves_his_counter"
end

function Cecil.menuOptions(group, player)
    local value = story(group)
    if not value then return {} end
    local trading = distance(group, player) > 4
        and distance(group, player) <= 8
        and not armed(player) and value.stage ~= "hostile"
    local stock = itemFor(actorFor(group), "Base.ShotgunShellsBox") ~= nil
    return {
        { id = "trade_food", label = "Trade three canned foods for shotgun shells",
            enabled = trading and stock and #paymentItems(player, "food") >= 3,
            detail = "Stay behind Cecil's taped line with your weapon holstered" },
        { id = "trade_water", label = "Trade two clean water bottles for shotgun shells",
            enabled = trading and stock and #paymentItems(player, "water") >= 2,
            detail = "Full clean bottles only" },
    }
end

local function trade(group, player, kind)
    local value = story(group)
    local range = distance(group, player)
    if range <= 4 or range > 8 or armed(player)
        or value.stage == "hostile" then return false, "trade_line_not_safe" end
    local actor = actorFor(group)
    local seller = actor and U().inventory(actor)
    local buyer = player and U().inventory(player)
    local stock = itemFor(actor, "Base.ShotgunShellsBox")
    local payment = paymentItems(player, kind)
    local required = kind == "food" and 3 or 2
    if not seller or not buyer or not stock or #payment < required then
        return false, "trade_supplies_missing"
    end
    local moved = {}
    for index = 1, required do
        local item = payment[index]
        local source = select(1, U().call(item, "getContainer"))
        local ok = source and U().transferItemVerified(source, seller, item)
        if not ok then
            for _, previous in ipairs(moved) do
                U().transferItemVerified(seller, buyer, previous)
            end
            return false, "trade_payment_failed"
        end
        moved[#moved + 1] = item
    end
    local delivered = U().transferItemVerified(seller, buyer, stock)
    if not delivered then
        for _, previous in ipairs(moved) do
            U().transferItemVerified(seller, buyer, previous)
        end
        return false, "trade_reward_failed"
    end
    speak(group, "trade")
    return true, "cecil_trade_complete"
end

function Cecil.action(group, action, player)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    if action == "hurt" then
        hostile(group, value)
        return true, "cecil_defends_himself"
    end
    if action == "trade_food" then return trade(group, player, "food") end
    if action == "trade_water" then return trade(group, player, "water") end
    return false, "unsupported_cecil_action"
end

return Cecil
