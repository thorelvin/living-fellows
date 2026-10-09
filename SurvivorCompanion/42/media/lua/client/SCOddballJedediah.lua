-- SPDX-License-Identifier: MIT
-- Jedediah's cattle are native animals. His trail contract examines a real
-- loaded road and real nearby zombies; he never fabricates a successful scout.

local SC = SurvivorCompanion
SC.OddballJedediah = SC.OddballJedediah or {}
local Jedediah = SC.OddballJedediah
local ID = "jedediah_cattle_drive"
local HERD = {
    { kind = "cow", breed = "holstein", name = "Mary Lou" },
    { kind = "cow", breed = "simmental", name = "Bluebell" },
    { kind = "cow", breed = "angus", name = "Midnight" },
    { kind = "bull", breed = "angus", name = "Marshal" },
}

local function U() return SC.GameplayUtil end
local function story(group)
    local value = type(group) == "table" and group.oddball or nil
    if type(value) ~= "table" or value.id ~= ID then return nil end
    value.stage = value.stage or "waiting_for_sunday"
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
        160, 8) or {}) do
        if U().itemType(item) == kind then return item end
    end
    return nil
end
local function ageDay()
    local clock = type(getGameTime) == "function" and getGameTime() or nil
    local hours = clock and select(1, U().call(clock, "getWorldAgeHours"))
    return tonumber(hours) and math.floor(hours / 24) or nil
end
local function seedHerd(group)
    local value = story(group)
    local posts = value and value.site and value.site.animalSpawns
    if not posts then return false, "cattle_pasture_missing" end
    local all = true
    for slot, spec in ipairs(HERD) do
        if SC.OddballAnimals.status(group, slot) == "unseeded" then
            local okay = SC.OddballAnimals.spawn(group, slot, spec, posts[slot])
            if not okay then all = false end
        end
    end
    value.herdSeeded = all
    return all, all and "four_native_cattle" or "herd_partly_seeded"
end

local function roadClear(value)
    local trail = value.site and value.site.trail
    if not trail or type(getCell) ~= "function" or not SC.NativeList then
        return false, "trail_or_zombie_list_unavailable"
    end
    local square = U().gridSquare(trail.x, trail.y, trail.z or 0)
    if not square then return false, "trail_unloaded" end
    local cell = getCell()
    local list = cell and select(1, U().call(cell, "getZombieList"))
    if not list then return false, "zombie_list_unavailable" end
    local count = 0
    for index = 0, math.min(2047, SC.NativeList.size(list) - 1) do
        local zombie = SC.NativeList.get(list, index)
        local x, y, z = U().position(zombie)
        if x and z == (trail.z or 0)
            and (x - trail.x) ^ 2 + (y - trail.y) ^ 2 <= 30 * 30 then
            count = count + 1
        end
    end
    return count == 0, count
end

function Jedediah.onSpawn(group, actor)
    local value = story(group)
    if not value or not actor then return false, "jedediah_unavailable" end
    if value.herdSeeded ~= true then seedHerd(group) end
    local inventory = U().inventory(actor)
    if value.gearSeeded ~= true and inventory then
        local revolver = itemFor(actor, "Base.Revolver")
            or U().addItem(inventory, "Base.Revolver")
        if revolver then
            U().call(actor, "setPrimaryHandItem", revolver)
            value.gearSeeded = true
        end
    end
    if value.stockSeeded ~= true and inventory then
        local milk = U().addItem(inventory, "Base.Milk")
        local beef = U().addItem(inventory, "Base.Beef")
        if milk and beef then value.stockSeeded = true end
    end
    return true, "cattle_drive_ready"
end

function Jedediah.pulse(group, player, current)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    if value.herdSeeded ~= true
        and current >= (tonumber(value.nextHerdRetryAt) or 0) then
        value.nextHerdRetryAt = current + 30000
        seedHerd(group)
    end
    if near(group, player) and value.greeted ~= true then
        value.greeted = true
        group.discovered = true
        U().say(actorFor(group),
            "Cholera's bad this year. Worst since '79. Louisville by Sunday, if the trail holds.")
    end
    for slot = 1, 4 do
        if SC.OddballAnimals.status(group, slot) == "alive" then
            SC.OddballAnimals.follow(group, slot, actorFor(group), current)
        end
    end
    return true, value.stage
end

function Jedediah.pulseRecruited(group, actor, player, current)
    for slot = 1, 4 do
        if SC.OddballAnimals.status(group, slot) == "alive" then
            SC.OddballAnimals.follow(group, slot, actor, current)
        end
    end
    return true, "herd_near_keeper"
end

function Jedediah.intentFor(actor, player, snapshot, group)
    if not story(group) then return nil end
    if group.standing == "Hostile" then
        return { mode = "hostile", priority = 110 }
    end
    local threats = type(snapshot) == "table"
        and (tonumber(snapshot.threatCount) or #(snapshot.threats or {})) or 0
    if threats > 0 then return { mode = "zombie_defense", priority = 18 } end
    return { mode = "oddball_idle", priority = 28 }
end

function Jedediah.canRecruit(group)
    local value = story(group)
    return value and value.truth == "broken" and group.standing == "Trusted"
        or false, "show_him_the_date_first"
end

function Jedediah.menuOptions(group, player)
    local value = story(group)
    if not value or not near(group, player) then return {} end
    local trail = value.site and value.site.trail
    return {
        { id = "ask_drive", label = "Ask about the cattle drive",
            enabled = true },
        { id = "scout_trail", label = "Report the trail clear",
            enabled = trail ~= nil and value.truth == nil,
            detail = trail and ("Road near " .. trail.x .. ", " .. trail.y
                .. "; clear the dead within 30 tiles") or "No road named" },
        { id = "show_newspaper", label = "Show Jedediah a newspaper",
            enabled = itemFor(player, "Base.Newspaper") ~= nil
                and value.truth == nil },
        { id = "trade_milk", label = "Ask for milk and beef",
            enabled = value.traded ~= true },
        { id = "lead_cow", label = "Ask to lead a cow home",
            enabled = value.truth ~= nil and value.leashGiven ~= true },
        { id = "recruit", label = "Ask Jedediah to join",
            enabled = Jedediah.canRecruit(group) == true },
    }
end

function Jedediah.action(group, action, player)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    if action == "hurt" or action == "animal_hurt" then
        return SC.Factions.forceStanding(group.id, "Hostile")
    end
    if not near(group, player) then return false, "cowpoke_too_far" end
    local actor = actorFor(group)
    if action == "ask_drive" then
        U().say(actor, "Iron wagons everywhere, and not one horse to pull 'em.")
        return true, "drive_discussed"
    end
    if action == "scout_trail" and value.truth == nil then
        local trail = value.site and value.site.trail
        local px, py, pz = U().position(player)
        if not trail or not px or pz ~= (trail.z or 0)
            or (px - trail.x) ^ 2 + (py - trail.y) ^ 2 > 6 * 6 then
            return false, "visit_named_road_first"
        end
        local clear, count = roadClear(value)
        if not clear then return false,
            type(count) == "number" and (count .. "_dead_block_the_trail")
                or count end
        local day = ageDay()
        if day and value.lastTrailDay == day then
            return false, "trail_already_scouted_today"
        end
        value.lastTrailDay = day
        value.scouts = math.min(3, (tonumber(value.scouts) or 0) + 1)
        SC.Factions.adjustStanding(group.id, 18, "real_cattle_trail_cleared")
        U().say(actor, value.scouts == 1
            and "Trail's clear, is it? Good. Rain'll hold us till Sunday."
            or "You cleared it again? Then the cattle need another day. Always another day.")
        return true, "real_road_cleared"
    end
    if action == "show_newspaper" and value.truth == nil
        and itemFor(player, "Base.Newspaper") then
        local hash = U().stableHash and U().stableHash(group.id) or 0
        value.truth = hash % 2 == 0 and "broken" or "laughing"
        if value.truth == "broken" then
            SC.Factions.forceStanding(group.id, "Trusted")
            U().say(actor,
                "Nineteen ninety-three? That ain't right. I should come with you.")
        else
            U().say(actor,
                "A newspaper? Son, them printers get the year wrong every time. See you Sunday.")
        end
        return true, "newspaper_shown_to_cowpoke"
    end
    if action == "trade_milk" and value.traded ~= true then
        local destination = U().inventory(player)
        local milk, beef = itemFor(actor, "Base.Milk"),
            itemFor(actor, "Base.Beef")
        local milkSource = milk and select(1, U().call(milk, "getContainer"))
        local beefSource = beef and select(1, U().call(beef, "getContainer"))
        if not destination or not milkSource or not beefSource then
            return false, "cattle_goods_unavailable"
        end
        if not U().transferItemVerified(milkSource, destination, milk) then
            return false, "milk_transfer_failed"
        end
        if not U().transferItemVerified(beefSource, destination, beef) then
            U().transferItemVerified(destination, milkSource, milk)
            return false, "beef_transfer_failed"
        end
        value.traded = true
        U().say(actor, "Milk's fresh. Beef's from the old girl we lost last spring.")
        return true, "real_cattle_goods_received"
    end
    if action == "lead_cow" and value.truth ~= nil
        and value.leashGiven ~= true then
        if not SC.OddballAnimals.find(group, 1) then
            return false, "cow_unavailable"
        end
        local leash = U().addItem(U().inventory(player), "Base.Leash")
        if not leash then return false, "leash_unavailable" end
        value.leashGiven = true
        U().say(actor,
            "Mary Lou can go with you. Put the leash on her yourself. Mind that bull.")
        return true, "vanilla_cow_lead_offered"
    end
    if action == "recruit" and Jedediah.canRecruit(group) == true
        and SC.FactionRecruitment then
        local asked, reason = SC.FactionRecruitment.ask(group.id, player, false)
        if not asked then return false, reason end
        return SC.FactionRecruitment.startTrial(group.id, player, false)
    end
    return false, "cattle_drive_choice_unavailable"
end

return Jedediah
