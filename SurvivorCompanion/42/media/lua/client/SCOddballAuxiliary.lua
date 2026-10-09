-- SPDX-License-Identifier: MIT
-- Three kitchen defenders sell finite, real baked goods for exact ingredients.
-- An attack flips the whole faction hostile; Opal uses native recruitment.

local SC = SurvivorCompanion
SC.OddballAuxiliary = SC.OddballAuxiliary or {}
local Auxiliary = SC.OddballAuxiliary
local ID = "rosewood_auxiliary"
local REWARDS = { "Base.Pie", "Base.CakeCarrot", "Base.Pie",
    "Base.CakeChocolate", "Base.Pie", "Base.CakeStrawberryShortcake" }

local function U() return SC.GameplayUtil end

local function story(group)
    local value = type(group) == "table" and group.oddball or nil
    if type(value) ~= "table" or value.id ~= ID then return nil end
    value.stage = value.stage or "bake_sale"
    value.trades = math.max(0, math.min(#REWARDS,
        math.floor(tonumber(value.trades) or 0)))
    value.gearSeeded = value.gearSeeded or {}
    value.recruitmentCandidateKey = "member-3"
    return value
end

local function actorFor(group, index)
    local member = group and group.members and group.members[index]
    local record = member and member.actorId and SC.Registry
        and SC.Registry.byId(member.actorId) or nil
    return record and record.actor and U().isValidActor(record.actor)
        and record.actor or nil
end

local function near(group, player)
    local leader = actorFor(group, 1)
    return leader and player and U().distance(leader, player) <= 7
        and U().canSee(player, leader) == true
end

local function itemFor(actor, predicate)
    local inventory = actor and U().inventory(actor)
    for _, item in ipairs(inventory and U().inventoryItemsDeep(inventory,
        240, 10) or {}) do
        if predicate(U().itemType(item), item) then return item end
    end
    return nil
end

local function taggedBake(_, item)
    local data = U().modData(item)
    return data and data.lfAuxiliaryBake == true
end

function Auxiliary.onSpawn(group, actor)
    local value = story(group)
    if not value or not actor then return false, "auxiliary_unavailable" end
    local index
    for current = 1, 3 do
        if actor == actorFor(group, current) then index = current; break end
    end
    if not index then return false, "auxiliary_member_missing" end
    local inventory = U().inventory(actor)
    if not inventory then return false, "auxiliary_inventory_unavailable" end
    if value.gearSeeded[index] ~= true then
        local weapon = U().addItem(inventory,
            index == 2 and "Base.Pan" or "Base.RollingPin")
        if not weapon then return false, "auxiliary_weapon_unavailable" end
        U().call(actor, "setPrimaryHandItem", weapon)
        value.gearSeeded[index] = true
    end
    if index == 1 and value.stockSeeded ~= true then
        local count = 0
        for _, kind in ipairs(REWARDS) do
            local item = U().addItem(inventory, kind)
            if item then
                local data = U().modData(item)
                if data then data.lfAuxiliaryBake = true end
                count = count + 1
            end
        end
        if count == 0 then return false, "bake_sale_stock_unavailable" end
        value.stockSeeded = true
    end
    return true, "bake_sale_ready"
end

function Auxiliary.pulse(group, player)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    local leader = actorFor(group, 1)
    if near(group, player) and value.greeted ~= true then
        value.greeted = true
        group.discovered = true
        U().say(leader,
            "Wipe your feet. We didn't survive the end of the world for mud.")
    end
    return true, value.stage
end

function Auxiliary.intentFor(actor, player, snapshot, group)
    if not story(group) then return nil end
    if group.standing == "Hostile" then
        return { mode = "hostile", priority = 110 }
    end
    local threats = type(snapshot) == "table"
        and (tonumber(snapshot.threatCount) or #(snapshot.threats or {})) or 0
    if threats > 0 then return { mode = "zombie_defense", priority = 18 } end
    return { mode = "oddball_idle", priority = 28 }
end

function Auxiliary.canRecruit(group)
    local value = story(group)
    return value and value.trades >= 2
        and group.standing == "Trusted"
        and group.members and group.members[3]
        and group.members[3].alive ~= false
end

function Auxiliary.menuOptions(group, player)
    local value = story(group)
    if not value or not near(group, player)
        or group.standing == "Hostile" then return {} end
    local options = {
        { id = "ask_sale", label = "Ask what's baking",
            enabled = true },
        { id = "buy_bake", label = "Trade flour and sugar for a pie or cake",
            enabled = itemFor(player, function(kind)
                    return kind == "Base.Flour2" end) ~= nil
                and itemFor(player, function(kind)
                    return kind == "Base.Sugar" end) ~= nil
                and itemFor(actorFor(group, 1), taggedBake) ~= nil },
    }
    if Auxiliary.canRecruit(group) then
        local candidate = actorFor(group, 3)
        local recruitment = SC.FactionRecruitment
            and type(SC.FactionRecruitment.summary) == "function"
            and SC.FactionRecruitment.summary(group.id) or nil
        if recruitment and recruitment.status == "trial" then
            options[#options + 1] = { id = "recruitment_decide",
                label = "Ask Opal for her decision",
                enabled = recruitment.canDecide == true }
        elseif not recruitment or recruitment.status ~= "joined" then
            options[#options + 1] = { id = "recruit",
                label = "Ask Opal to join",
                enabled = candidate ~= nil
                    and U().distance(player, candidate) <= 6 }
        end
    end
    return options
end

function Auxiliary.action(group, action, player)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    if action == "hurt" then
        value.stage = "hostile"
        local changed = SC.Factions.forceStanding(group.id, "Hostile")
        for index = 1, 3 do
            local actor = actorFor(group, index)
            if actor then U().say(actor, "Mind your manners, young man!") end
        end
        return changed, "ladies_defend_their_kitchen"
    end
    if not near(group, player) or group.standing == "Hostile" then
        return false, "auxiliary_too_far"
    end
    local leader = actorFor(group, 1)
    if action == "ask_sale" then
        U().say(leader,
            "Two cups of sugar and you'll have a pie by Sunday.")
        return true, "bake_sale_explained"
    end
    if action == "buy_bake" then
        local flour = itemFor(player,
            function(kind) return kind == "Base.Flour2" end)
        local sugar = itemFor(player,
            function(kind) return kind == "Base.Sugar" end)
        local baked = itemFor(leader, taggedBake)
        local flourSource = flour and select(1, U().call(flour,
            "getContainer"))
        local sugarSource = sugar and select(1, U().call(sugar,
            "getContainer"))
        local bakeSource = baked and select(1, U().call(baked,
            "getContainer"))
        local playerInventory, bakerInventory = U().inventory(player),
            U().inventory(leader)
        if not flourSource or not sugarSource or not bakeSource
            or not playerInventory or not bakerInventory then
            return false, "bake_sale_goods_missing"
        end
        if not U().transferItemVerified(flourSource,
            bakerInventory, flour) then
            return false, "flour_transfer_failed"
        end
        if not U().transferItemVerified(sugarSource,
            bakerInventory, sugar) then
            U().transferItemVerified(bakerInventory, flourSource, flour)
            return false, "sugar_transfer_failed"
        end
        if not U().transferItemVerified(bakeSource,
            playerInventory, baked) then
            U().transferItemVerified(bakerInventory, sugarSource, sugar)
            U().transferItemVerified(bakerInventory, flourSource, flour)
            return false, "bake_transfer_failed"
        end
        value.trades = value.trades + 1
        if value.trades >= 2 and group.standing ~= "Trusted" then
            SC.Factions.forceStanding(group.id, "Trusted")
        end
        U().say(leader, value.trades >= 2
            and "Opal likes you. She doesn't say so. That's how I know."
            or "There. A proper pie in an improper world.")
        return true, "real_bake_sale_trade"
    end
    if action == "recruit" then
        if not Auxiliary.canRecruit(group) then
            return false, "opal_not_ready"
        end
        local candidate = actorFor(group, 3)
        if not candidate or U().distance(player, candidate) > 6 then
            return false, "opal_too_far"
        end
        if not SC.FactionRecruitment then
            return false, "recruitment_unavailable"
        end
        local summary = type(SC.FactionRecruitment.summary) == "function"
            and SC.FactionRecruitment.summary(group.id) or nil
        if not summary or summary.status ~= "candidate" then
            local asked, reason = SC.FactionRecruitment.ask(
                group.id, player, false)
            if not asked then return false, reason end
        end
        return SC.FactionRecruitment.startTrial(group.id, player, false)
    end
    if action == "recruitment_decide" and SC.FactionRecruitment then
        return SC.FactionRecruitment.decide(group.id, player)
    end
    return false, "unknown_auxiliary_choice"
end

return Auxiliary
