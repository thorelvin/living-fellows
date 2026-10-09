-- SPDX-License-Identifier: MIT
-- One merchant, many dusk appearances. Faction hibernation owns departure and
-- wake-up so his native actor, wounds, stock, and identity are not cloned.

local SC = SurvivorCompanion
SC.OddballEbb = SC.OddballEbb or {}
local Ebb = SC.OddballEbb
local ID = "peddler_mister_ebb"
local UNSEEN_MS = 60000
local VISIT_DAYS = 5
local lines = {
    greet = "Evening, stranger. Got a little something for everybody.",
    stock = "Don't ask where I get it. I don't ask where you got yours.",
    price = "Prices are firm. Like a handshake. Like rigor mortis.",
    struck = "We're past that, aren't we? Prices went up, though.",
    depart = "We'll meet again. Roads have a way of doing that.",
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

local function worldDay()
    if type(getGameTime) ~= "function" then return nil end
    local okay, time = pcall(getGameTime)
    if not okay or not time then return nil end
    local raw = select(1, U().call(time, "getWorldAgeHours"))
    local hour = tonumber(raw)
    return hour and math.floor(hour / 24) or nil
end

local function evening()
    if type(getGameTime) ~= "function" then return false end
    local okay, time = pcall(getGameTime)
    if not okay or not time then return false end
    local raw = select(1, U().call(time, "getTimeOfDay"))
    local hour = tonumber(raw)
    return hour and hour >= 18 and hour < 22 or false
end

local function near(group, player)
    local actor = actorFor(group)
    return actor and player and U().distance(actor, player) <= 6
        and U().canSee(player, actor) == true
end

local function itemFor(actor, kind)
    local inventory = actor and U().inventory(actor)
    for _, item in ipairs(inventory and U().inventoryItemsDeep(inventory, 160, 8)
        or {}) do
        if U().itemType(item) == kind then return item end
    end
    return nil
end

local function nearbyCar(group)
    if type(getCell) ~= "function" then return nil end
    local okay, cell = pcall(getCell)
    local vehicles = okay and select(1, U().call(cell, "getVehicles")) or nil
    if not vehicles or not SC.NativeList then return nil end
    local site = story(group).site
    local center = site and (site.wake or site.spawn)
    if not center then return nil end
    for index = 0, math.min(127, SC.NativeList.size(vehicles) - 1) do
        local vehicle = SC.NativeList.get(vehicles, index)
        local x, y, z = U().position(vehicle)
        local keyId = select(1, U().call(vehicle, "getKeyId"))
        if x and z == center.z and tonumber(keyId)
            and (x - center.x) ^ 2 + (y - center.y) ^ 2 <= 18 * 18 then
            return vehicle, keyId
        end
    end
    return nil
end

local function stockVisit(group, actor, value)
    local day = worldDay()
    if not day then return false, "world_day_unavailable" end
    if value.stockDay == day then return true, "stock_already_prepared" end
    local inventory = U().inventory(actor)
    if not inventory then return false, "merchant_inventory_unavailable" end
    value.visitSerial = (tonumber(value.visitSerial) or 0) + 1
    local kind = value.visitSerial % 2 == 0
        and "Base.EngineerMagazine2" or "Base.RedDot"
    local vehicle, keyId = nearbyCar(group)
    if vehicle and value.visitSerial % 3 == 0 then kind = "Base.CarKey" end
    local stock = itemFor(actor, kind) or U().addItem(inventory, kind)
    if not stock then
        value.visitSerial = value.visitSerial - 1
        return false, "merchant_stock_unavailable"
    end
    if kind == "Base.CarKey" then
        U().call(stock, "setKeyId", keyId)
        U().call(stock, "setName", "A key for a car nearby")
    end
    value.stockKind, value.stockDay, value.stockSold = kind, day, false
    value.stage, value.unseenSince = "trading", nil
    return true, "merchant_stock_ready"
end

local function money(player, due)
    local found = {}
    local inventory = player and U().inventory(player)
    for _, item in ipairs(inventory and U().inventoryItemsDeep(inventory, 200, 8)
        or {}) do
        if U().itemType(item) == "Base.Money" then
            local source = select(1, U().call(item, "getContainer"))
            if source then
                found[#found + 1] = { item = item, source = source }
                if #found >= due then break end
            end
        end
    end
    return found
end

function Ebb.onSpawn(group, actor)
    local value = story(group)
    if not value or not actor then return false, "merchant_unavailable" end
    local inventory = U().inventory(actor)
    if not inventory then return false, "merchant_inventory_unavailable" end
    if value.lanternSeeded ~= true then
        local lantern = itemFor(actor, "Base.Lantern_HurricaneLit")
            or U().addItem(inventory, "Base.Lantern_HurricaneLit")
        if not lantern then return false, "lantern_unavailable" end
        U().call(actor, "setSecondaryHandItem", lantern)
        value.lanternSeeded = true
    end
    if value.stage == "unmet" or value.stage == "waiting" then
        stockVisit(group, actor, value)
    end
    value.priceMultiplier = tonumber(value.priceMultiplier) or 1
    value.nextVisitDay = tonumber(value.nextVisitDay)
        or (worldDay() and worldDay() + VISIT_DAYS)
    return true, "merchant_ready"
end

function Ebb.pulse(group, player, current)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    local member = group.members and group.members[1]
    local actor = actorFor(group)
    if member and member.hibernated == true then
        local day = worldDay()
        if day and day >= (tonumber(value.nextVisitDay) or math.huge)
            and evening() and SC.Oddballs
            and type(SC.Oddballs.findEbbSite) == "function" then
            local previous = value.site and (value.site.wake or value.site.spawn)
            local site = SC.Oddballs.findEbbSite(player, previous)
            if site and site.spawn then
                value.site.wake = site.spawn
                value.site.anchor = site.spawn
                value.site.room = site.room
                value.nextVisitDay = day + VISIT_DAYS
                value.stage = "waiting"
                return true, "merchant_next_landmark_selected"
            end
        end
        return true, "merchant_away"
    end
    if not actor then return false, "merchant_actor_unavailable" end
    if value.stage == "waiting" then stockVisit(group, actor, value) end
    if near(group, player) and value.greetedVisit ~= value.visitSerial then
        value.greetedVisit = value.visitSerial
        group.discovered = true
        say(group, value.priceMultiplier > 1 and "struck" or "greet")
    end
    local visible = player and U().canSee(player, actor) == true
    if value.stage == "trading" or value.stage == "retreat" then
        if visible then
            value.unseenSince = nil
        else
            value.unseenSince = value.unseenSince or current
            if current - value.unseenSince >= UNSEEN_MS
                and SC.Factions
                and type(SC.Factions.hibernateOddballRoamer) == "function" then
                local gone = SC.Factions.hibernateOddballRoamer(group.id, player)
                if gone then
                    value.stage = "away"
                    value.nextVisitDay = (worldDay() or 0) + VISIT_DAYS
                    value.unseenSince = nil
                    return true, "merchant_departed"
                end
            end
        end
    end
    return true, value.stage
end

function Ebb.intentFor(actor, player, snapshot, group)
    local value = story(group)
    if not value then return nil end
    if group.standing == "Hostile" then
        return { mode = "hostile", priority = 110 }
    end
    local threats = type(snapshot) == "table"
        and (tonumber(snapshot.threatCount) or #(snapshot.threats or {})) or 0
    if threats > 0 then return { mode = "zombie_defense", priority = 18 } end
    return { mode = value.stage == "retreat" and "ebb_retreat"
        or "ebb_market", priority = 30 }
end

function Ebb.update(actor, player, runtime, intent, group)
    if not intent or (intent.mode ~= "ebb_market"
        and intent.mode ~= "ebb_retreat") then return false end
    local value = story(group)
    local point = value.site and (value.site.wake or value.site.spawn)
    if not point then return true, "merchant_post_unavailable" end
    if intent.mode == "ebb_retreat" and player then
        local px, py, pz = U().position(player)
        local ax, ay, az = U().position(actor)
        if px and ax and pz == az then
            local dx, dy = ax - px, ay - py
            local span = math.max(1, math.sqrt(dx * dx + dy * dy))
            local square = U().gridSquare(math.floor(ax + dx / span * 15),
                math.floor(ay + dy / span * 15), az)
            if square and U().isSafeSpawnSquare(square) and SC.Navigation then
                return SC.Navigation.request(actor, square, "run", {
                    action = "faction_retreat", arrivalDistance = 2 })
            end
        end
    end
    local x, y, z = U().position(actor)
    if x and z == (point.z or 0) and (x - point.x) ^ 2
        + (y - point.y) ^ 2 <= 2.25 then return true, "merchant_waiting" end
    local square = U().gridSquare(point.x, point.y, point.z or 0)
    if not square then return true, "merchant_landmark_unloaded" end
    if not SC.Navigation or type(SC.Navigation.request) ~= "function" then
        return false, "navigation_unavailable"
    end
    return SC.Navigation.request(actor, square, "walk", {
        action = "faction_market", arrivalDistance = 1.5 })
end

function Ebb.canRecruit()
    return false, "mister_ebb_never_stays"
end

function Ebb.menuOptions(group, player)
    local value = story(group)
    if not value or value.stage ~= "trading" or not near(group, player) then
        return {}
    end
    local due = value.priceMultiplier > 1 and 3 or 2
    return { { id = "buy_stock",
        label = "Buy " .. tostring(value.stockKind or "the oddity")
            .. " for " .. tostring(due) .. " cash",
        enabled = value.stockSold ~= true and #money(player, due) >= due
            and itemFor(actorFor(group), value.stockKind) ~= nil,
        detail = "One genuine item from Mister Ebb's pack" } }
end

function Ebb.action(group, action, player)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    if action == "hurt" then
        value.priceMultiplier = 1.5
        value.stage = "retreat"
        say(group, "struck")
        return true, "merchant_remembers_attack"
    end
    if action ~= "buy_stock" or value.stage ~= "trading"
        or value.stockSold == true or not near(group, player) then
        return false, "merchant_trade_unavailable"
    end
    local due = value.priceMultiplier > 1 and 3 or 2
    local payment = money(player, due)
    local merchant = actorFor(group)
    local source = merchant and U().inventory(merchant)
    local destination = player and U().inventory(player)
    local stock = itemFor(merchant, value.stockKind)
    if #payment < due or not source or not destination or not stock then
        return false, "merchant_stock_or_cash_unavailable"
    end
    local paid = {}
    for _, coin in ipairs(payment) do
        if not U().transferItemVerified(coin.source, source, coin.item) then
            for _, prior in ipairs(paid) do
                U().transferItemVerified(source, prior.source, prior.item)
            end
            return false, "cash_transfer_failed"
        end
        paid[#paid + 1] = coin
    end
    if not U().transferItemVerified(source, destination, stock) then
        for _, coin in ipairs(paid) do
            U().transferItemVerified(source, coin.source, coin.item)
        end
        return false, "stock_transfer_failed"
    end
    value.stockSold = true
    say(group, "price")
    return true, "mister_ebb_trade_complete"
end

return Ebb
