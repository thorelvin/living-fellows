-- SPDX-License-Identifier: MIT
-- Gale's shop rules use the faction inventory observation path. Only an exact
-- item moved from his shelves into the player's inventory counts as a purchase.

local SC = SurvivorCompanion
SC.OddballGale = SC.OddballGale or {}
local Gale = SC.OddballGale
local ID = "grocery_gale_mercer"
local nextRemarkAt = {}

local lines = {
    greet = { "Welcome to GigaMart. Baskets by the door. Cash only, sweetheart.",
        "Welcome to GigaMart. Baskets by the door. Cash only, friend." },
    idle = { "Price check on aisle four. That's you. You're aisle four.",
        "Price check on aisle four. That's you. You're aisle four." },
    warning = { "Put it back on the shelf, you thieving bastard.",
        "Put it back on the shelf, you thieving so-and-so." },
    hostile = { "I have been robbed nine times since July. I am not doing ten.",
        "I have been robbed nine times since July. I am not doing ten." },
    paid = { "Thank you for shopping GigaMart. Have a blessed day.",
        "Thank you for shopping GigaMart. Have a blessed day." },
    short = { "Money's worthless, you say? Not in my store it isn't.",
        "Money's worthless, you say? Not in my store it isn't." },
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
    value.credit = math.max(0, math.min(100, math.floor(number(value.credit) or 0)))
    value.unpaid = math.max(0, math.min(100, math.floor(number(value.unpaid) or 0)))
    value.offenses = math.max(0, math.min(2, math.floor(number(value.offenses) or 0)))
    return value
end

local function actorFor(group)
    local member = type(group) == "table" and group.members and group.members[1]
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

local function nearCheckout(group, player)
    local actor = actorFor(group)
    local ax, ay, az = U().position(actor)
    local px, py, pz = U().position(player)
    if not ax or not px or az ~= pz then return false end
    local dx, dy = ax - px, ay - py
    return dx * dx + dy * dy <= 16
end

local function insideShop(group, player)
    local bounds = group and group.house and group.house.bounds
    local x, y, z = U().position(player)
    if not bounds or not x or z ~= (group.oddball.site.spawn.z or 0) then
        return false
    end
    return x >= bounds.x1 and x <= bounds.x2
        and y >= bounds.y1 and y <= bounds.y2
end

local function moneyItems(player)
    local singles, bundles = {}, {}
    local inventory = player and U().inventory(player)
    for _, item in ipairs(inventory and U().inventoryItemsDeep(inventory, 240, 12)
        or {}) do
        local kind = U().itemType(item)
        if kind == "Base.Money" then singles[#singles + 1] = item end
        if kind == "Base.MoneyBundle" then bundles[#bundles + 1] = item end
    end
    return singles, bundles
end

local function removeExact(item)
    local container = item and select(1, U().call(item, "getContainer"))
    if not container or U().containerContainsIdentity(container, item) ~= true then
        return false
    end
    local _, called = U().call(container, "Remove", item)
    return called and U().containerContainsIdentity(container, item) == false
end

local function pay(group, player, useBundle)
    if not nearCheckout(group, player) then return false, "checkout_too_far" end
    local value = story(group)
    if value.stage == "hostile" or group.standing == "Hostile" then
        return false, "store_closed_to_player"
    end
    local singles, bundles = moneyItems(player)
    local amount
    if useBundle then
        if not removeExact(bundles[1]) then return false, "money_bundle_required" end
        amount = 50
    else
        local due = math.max(1, value.unpaid)
        if #singles < due then return false, "not_enough_cash" end
        amount = 0
        for index = 1, due do
            if not removeExact(singles[index]) then break end
            amount = amount + 1
        end
        if amount == 0 then return false, "cash_transfer_failed" end
    end
    local settled = math.min(amount, value.unpaid)
    value.unpaid = value.unpaid - settled
    value.credit = math.min(100, value.credit + amount - settled)
    if value.unpaid == 0 then
        value.offenses = 0
        value.stage = "open"
    end
    speak(group, "paid")
    return true, "grocery_payment_accepted"
end

local function findWeapon(actor, kind)
    local inventory = actor and U().inventory(actor)
    for _, item in ipairs(inventory and U().inventoryItemsDeep(inventory, 160, 8)
        or {}) do
        if U().itemType(item) == kind then return item end
    end
    return nil
end

function Gale.onSpawn(group, actor)
    local value = story(group)
    if not value or not actor then return false, "gale_unavailable" end
    local inventory = U().inventory(actor)
    if not inventory then return false, "gale_inventory_unavailable" end
    local gun = findWeapon(actor, "Base.Shotgun")
    if not gun and value.equipmentSeeded ~= true then
        gun = U().addItem(inventory, "Base.Shotgun")
    end
    if gun then
        U().call(actor, "setPrimaryHandItem", gun)
        U().call(actor, "setSecondaryHandItem", gun)
    end
    if value.equipmentSeeded ~= true and gun then
        U().addItem(inventory, "Base.ShotgunShellsBox")
        local keys = U().addItem(inventory, "Base.KeyRing")
        if keys then U().call(keys, "setName", "Gale's store keys") end
        local note = U().addItem(inventory, "Base.LetterHandwritten")
        if note then U().call(note, "setName", "Employee of the Month") end
        value.equipmentSeeded = true
    end
    return true, gun and "gale_ready" or "shotgun_removed"
end

function Gale.pulse(group, player, current)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    if value.stage == "hostile" then return true, "store_hostile" end
    if value.stage == "unmet" and insideShop(group, player) then
        value.stage = "open"
        group.discovered = true
        speak(group, "greet")
    elseif value.stage == "open" and insideShop(group, player)
        and current >= (nextRemarkAt[group.id] or 0) then
        nextRemarkAt[group.id] = current + 90000
        speak(group, "idle")
    end
    return true, value.stage
end

function Gale.intentFor(actor, player, snapshot, group)
    local value = story(group)
    if not value then return nil end
    if value.stage == "hostile" or group.standing == "Hostile" then
        return { mode = "hostile", priority = 110 }
    end
    local threatCount = type(snapshot) == "table"
        and (number(snapshot.threatCount) or #(snapshot.threats or {})) or 0
    if threatCount > 0 then return { mode = "zombie_defense", priority = 18 } end
    return { mode = "gale_checkout", priority = 30 }
end

function Gale.update(actor, player, runtime, intent, group)
    if not intent or intent.mode ~= "gale_checkout" then return false end
    local site = story(group).site
    local checkout = site and site.spawn
    if not checkout then return true, "checkout_unavailable" end
    local x, y, z = U().position(actor)
    if x and z == checkout.z and (x - checkout.x) ^ 2
        + (y - checkout.y) ^ 2 <= 2.25 then
        return true, "at_checkout"
    end
    local square = U().gridSquare(checkout.x, checkout.y, checkout.z or 0)
    if not square then return true, "checkout_unloaded" end
    if not SC.Navigation or type(SC.Navigation.request) ~= "function" then
        return false, "navigation_unavailable"
    end
    return SC.Navigation.request(actor, square, "walk", {
        action = "faction_checkout", arrivalDistance = 1.5 })
end

function Gale.canRecruit(group)
    return false, "gale_keeps_the_store"
end

function Gale.menuOptions(group, player)
    local value = story(group)
    if not value then return {} end
    local nearby = nearCheckout(group, player)
    local singles, bundles = moneyItems(player)
    return {
        { id = "pay_cash", label = value.unpaid > 0
            and ("Pay for " .. value.unpaid .. " store item(s)")
            or "Buy one dollar of store credit",
            enabled = nearby and value.stage ~= "hostile"
                and #singles >= math.max(1, value.unpaid),
            detail = "One Base.Money per item, paid at Gale's checkout" },
        { id = "pay_bundle", label = "Pay with a money bundle",
            enabled = nearby and value.stage ~= "hostile" and #bundles > 0,
            detail = "A bundle buys fifty items; unused credit remains" },
    }
end

function Gale.action(group, action, player, payload)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    if action == "pay_cash" then return pay(group, player, false) end
    if action == "pay_bundle" then return pay(group, player, true) end
    if action == "shoplift" then
        if value.stage == "hostile" then return true, "store_already_hostile" end
        local count = math.max(1, math.min(32,
            math.floor(number(payload and payload.count) or 1)))
        for _ = 1, count do
            if value.credit > 0 then
                value.credit = value.credit - 1
            else
                value.unpaid = math.min(100, value.unpaid + 1)
                value.offenses = math.min(2, value.offenses + 1)
                if value.offenses == 1 then
                    value.stage = "warned"
                    speak(group, "warning")
                else
                    value.stage = "hostile"
                    SC.Factions.forceStanding(group.id, "Hostile")
                    speak(group, "hostile")
                    break
                end
            end
        end
        return true, value.stage
    end
    if action == "hurt" then
        value.stage = "hostile"
        SC.Factions.forceStanding(group.id, "Hostile")
        return true, "gale_defends_himself"
    end
    return false, "unsupported_gale_action"
end

return Gale
