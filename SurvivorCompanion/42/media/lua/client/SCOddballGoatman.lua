-- SPDX-License-Identifier: MIT
-- The trestle hermit changes with the clock: trade by daylight, hunt by
-- night. His calls use a real nearby fellow's name when one is available.

local SC = SurvivorCompanion
SC.OddballGoatman = SC.OddballGoatman or {}
local Goatman = SC.OddballGoatman
local ID = "trestle_goatman"

local function U() return SC.GameplayUtil end
local function story(group)
    local value = type(group) == "table" and group.oddball or nil
    if type(value) ~= "table" or value.id ~= ID then return nil end
    value.stage = value.stage or "hermit"
    return value
end
local function actorFor(group)
    local member = group and group.members and group.members[1]
    local record = member and member.actorId and SC.Registry
        and SC.Registry.byId(member.actorId) or nil
    return record and record.actor and U().isValidActor(record.actor)
        and record.actor or nil
end
local function night()
    local clock = type(getGameTime) == "function" and getGameTime() or nil
    local raw = clock and select(1, U().call(clock, "getTimeOfDay"))
    local hour = tonumber(raw)
    return hour ~= nil and (hour >= 19 or hour < 5)
end
local function near(group, player)
    local actor = actorFor(group)
    return actor and player and U().distance(actor, player) <= 10
        and U().canSee(player, actor) == true
end
local function itemFor(actor, kind)
    local inventory = actor and U().inventory(actor)
    for _, item in ipairs(inventory and U().inventoryItemsDeep(inventory,
        140, 8) or {}) do
        if U().itemType(item) == kind then return item end
    end
    return nil
end
local function voiceToMimic(actor)
    for _, fellow in ipairs(SC.Registry and SC.Registry.living() or {}) do
        local record = SC.Registry.byId(U().idOf(fellow))
        if fellow ~= actor and record and record.recruited == true
            and U().distance(actor, fellow) <= 25 then
            local name = select(1, U().call(fellow, "getDisplayName"))
            if type(name) == "string" and name ~= "" then return name end
        end
    end
    return nil
end

function Goatman.onSpawn(group, actor)
    local value = story(group)
    if not value or not actor then return false, "goatman_unavailable" end
    local inventory = U().inventory(actor)
    if value.gearSeeded ~= true and inventory then
        local axe = itemFor(actor, "Base.Axe")
            or U().addItem(inventory, "Base.Axe")
        if axe then U().call(actor, "setPrimaryHandItem", axe)
            value.gearSeeded = true end
    end
    if value.stockSeeded ~= true and inventory then
        local bone = U().addItem(inventory, "Base.AnimalBone")
        local hide = U().addItem(inventory, "Base.DeerHide")
        if bone and hide then value.stockSeeded = true end
    end
    return true, "goatman_at_trestle"
end

function Goatman.pulse(group, player, current)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    local actor = actorFor(group)
    if not actor then return false, "goatman_unloaded" end
    if night() then
        if value.nightAggression ~= true and value.permanentHostile ~= true then
            value.nightAggression = true
            value.stage = "mimic_hunt"
            SC.Factions.forceStanding(group.id, "Hostile")
        end
        if player and U().distance(actor, player) <= 20
            and current >= (tonumber(value.nextCallAt) or 0) then
            value.nextCallAt = current + 65000
            local name = voiceToMimic(actor)
            U().say(actor, name and
                (name .. "! Help! Over here! I can't move my leg!")
                or "Help! Over here! I can't move my leg!")
            group.discovered = true
        end
    elseif value.nightAggression == true and value.permanentHostile ~= true then
        value.nightAggression = false
        value.stage = "hermit"
        SC.Factions.forceStanding(group.id, "Wary")
        U().say(actor,
            "They used to come out on dares. Now nobody comes at all.")
    elseif near(group, player) and value.greeted ~= true then
        value.greeted = true
        group.discovered = true
        U().say(actor,
            "By daylight I'm just a man with too many bones. Don't come by after dark.")
    end
    return true, value.stage
end

function Goatman.intentFor(actor, player, snapshot, group)
    local value = story(group)
    if not value then return nil end
    if group.standing == "Hostile" then
        return { mode = "hostile", priority = 110 }
    end
    local threats = type(snapshot) == "table"
        and (tonumber(snapshot.threatCount) or #(snapshot.threats or {})) or 0
    if threats > 0 then return { mode = "zombie_defense", priority = 18 } end
    if value.site and value.site.haunt then
        return { mode = "goatman_watch_tracks", priority = 35 }
    end
    return { mode = "oddball_idle", priority = 28 }
end

function Goatman.update(actor, player, runtime, intent, group)
    if not intent or intent.mode ~= "goatman_watch_tracks" then
        return false, "goatman_idle"
    end
    local point = story(group).site.haunt
    local destination = U().gridSquare(point.x, point.y, point.z or 0)
    if not destination then return false, "trestle_unloaded" end
    if U().distance(actor, destination) <= 3 then
        return true, "watching_trestle"
    end
    if not SC.Navigation or type(SC.Navigation.request) ~= "function" then
        return false, "trestle_navigation_unavailable"
    end
    return SC.Navigation.request(actor, destination, "walk", {
        action = "goatman_trestle_watch", arrivalDistance = 2.5 })
end

function Goatman.canRecruit() return false, "goatman_is_a_hermit" end

function Goatman.menuOptions(group, player)
    local value = story(group)
    if not value or night() or not near(group, player) then return {} end
    return {
        { id = "ask_tracks", label = "Ask about the trestle",
            enabled = true },
        { id = "trade_bones", label = "Trade beans for bones or hide",
            enabled = itemFor(player, "Base.TinnedBeans") ~= nil
                and (itemFor(actorFor(group), "Base.AnimalBone") ~= nil
                    or itemFor(actorFor(group), "Base.DeerHide") ~= nil) },
    }
end

function Goatman.action(group, action, player)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    if action == "hurt" then
        value.permanentHostile = true
        return SC.Factions.forceStanding(group.id, "Hostile")
    end
    if night() or not near(group, player) then
        return false, "trestle_trade_by_day_only"
    end
    local actor = actorFor(group)
    if action == "ask_tracks" then
        U().say(actor,
            "They used to dare each other onto the rails. Tracks hold a voice a long way.")
        return true, "trestle_tale_told"
    end
    if action ~= "trade_bones" then return false, "goatman_choice_unavailable" end
    local beans = itemFor(player, "Base.TinnedBeans")
    local goods = itemFor(actor, "Base.AnimalBone")
        or itemFor(actor, "Base.DeerHide")
    local source = beans and select(1, U().call(beans, "getContainer"))
    local goodsSource = goods and select(1,
        U().call(goods, "getContainer"))
    local playerInventory, hermitInventory = U().inventory(player),
        U().inventory(actor)
    if not source or not goodsSource or not playerInventory
        or not hermitInventory then return false, "trestle_goods_missing" end
    if not U().transferItemVerified(source, hermitInventory, beans) then
        return false, "trestle_payment_failed"
    end
    if not U().transferItemVerified(goodsSource, playerInventory, goods) then
        U().transferItemVerified(hermitInventory, source, beans)
        return false, "trestle_goods_transfer_failed"
    end
    U().say(actor, "Bones and hide for beans. Not a bad daylight bargain.")
    return true, "finite_trestle_trade"
end

return Goatman
