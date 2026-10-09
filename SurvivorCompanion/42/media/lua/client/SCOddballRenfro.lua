-- SPDX-License-Identifier: MIT
-- A windowless room and eight individually tracked, native rats. Death is
-- observed through the animals' actual health, never simulated by dialogue.

local SC = SurvivorCompanion
SC.OddballRenfro = SC.OddballRenfro or {}
local Renfro = SC.OddballRenfro
local ID = "renfro_rat_king"
local RATS = {
    { kind = "rat", breed = "grey", name = "Minister" },
    { kind = "ratfemale", breed = "white", name = "Duchess" },
    { kind = "rat", breed = "grey", name = "Captain" },
    { kind = "ratfemale", breed = "grey", name = "Little Queen" },
    { kind = "rat", breed = "white", name = "Mayor" },
    { kind = "ratfemale", breed = "white", name = "Sister" },
    { kind = "ratbaby", breed = "grey", name = "Pip" },
    { kind = "ratbaby", breed = "white", name = "Dot" },
}

local function U() return SC.GameplayUtil end
local function story(group)
    local value = type(group) == "table" and group.oddball or nil
    if type(value) ~= "table" or value.id ~= ID then return nil end
    value.stage = value.stage or "court"
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
local function itemFor(actor, kinds, tagged)
    local inventory = actor and U().inventory(actor)
    for _, item in ipairs(inventory and U().inventoryItemsDeep(inventory,
        180, 8) or {}) do
        if kinds[U().itemType(item)] then
            local data = U().modData(item)
            if not tagged or data and data.lfRenfroStock then return item end
        end
    end
    return nil
end
local function seedRats(group)
    local value = story(group)
    local posts = value and value.site and value.site.animalSpawns
    if not posts then return false, "rat_room_unavailable" end
    local all = true
    for slot, spec in ipairs(RATS) do
        if SC.OddballAnimals.status(group, slot) == "unseeded" then
            local okay = SC.OddballAnimals.spawn(group, slot, spec,
                posts[slot])
            if not okay then all = false end
        end
    end
    value.ratsSeeded = all
    return all, all and "eight_real_rats" or "rat_spawn_pending"
end

function Renfro.onSpawn(group, actor)
    local value = story(group)
    if not value or not actor then return false, "rat_king_unavailable" end
    if value.ratsSeeded ~= true then seedRats(group) end
    if value.stockSeeded ~= true then
        local inventory = U().inventory(actor)
        if not inventory then return false, "rat_trade_inventory_unavailable" end
        local added = 0
        for _ = 1, 3 do
            local rat = U().addItem(inventory, "Base.DeadRat")
            if rat then
                local data = U().modData(rat)
                if data then data.lfRenfroStock = true end
                added = added + 1
            end
        end
        if added == 0 then return false, "rat_stock_unavailable" end
        value.stockSeeded = true
    end
    return true, "renfro_court_ready"
end

function Renfro.pulse(group, player, current)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    local actor = actorFor(group)
    if not actor then return false, "renfro_unloaded" end
    if value.ratsSeeded ~= true
        and current >= (tonumber(value.nextRatsRetryAt) or 0) then
        value.nextRatsRetryAt = current + 30000
        seedRats(group)
    end
    if near(group, player) and value.greeted ~= true then
        value.greeted = true
        group.discovered = true
        U().say(actor, "Every kingdom needs subjects. Mine have tails.")
    end
    local alive, dead = 0, 0
    for slot = 1, #RATS do
        local state = SC.OddballAnimals.status(group, slot)
        if state == "alive" then alive = alive + 1
        elseif state == "dead" then dead = dead + 1 end
    end
    if dead > 0 and dead > (tonumber(value.lastDeadCount) or 0) then
        value.lastDeadCount = dead
        if alive == 0 then
            value.stage = "vengeance"
            SC.Factions.forceStanding(group.id, "Hostile")
            U().say(actor,
                "Every subject gone. You'd best pray I don't find who did it.")
        else
            value.stage = "unwelcome"
            SC.Factions.adjustStanding(group.id, -25, "rat_subject_died")
            U().say(actor,
                "One of my subjects is dead. You aren't welcome in this court.")
        end
    end
    return true, value.stage
end

function Renfro.intentFor(actor, player, snapshot, group)
    if not story(group) then return nil end
    if group.standing == "Hostile" then
        return { mode = "hostile", priority = 110 }
    end
    local threats = type(snapshot) == "table"
        and (tonumber(snapshot.threatCount) or #(snapshot.threats or {})) or 0
    if threats > 0 then return { mode = "zombie_defense", priority = 18 } end
    return { mode = "oddball_idle", priority = 28 }
end

function Renfro.canRecruit() return false, "rat_king_keeps_his_court" end

function Renfro.menuOptions(group, player)
    local value = story(group)
    if not value or not near(group, player)
        or value.stage == "unwelcome" or value.stage == "vengeance" then
        return {}
    end
    local food = { ["Base.Cheese"] = true, ["Base.Cornmeal2"] = true }
    local stock = { ["Base.DeadRat"] = true }
    return {
        { id = "ask_court", label = "Ask about Renfro's subjects",
            enabled = true },
        { id = "trade_rat", label = "Trade cheese or grain for rat meat",
            enabled = itemFor(player, food) ~= nil
                and itemFor(actorFor(group), stock, true) ~= nil },
    }
end

function Renfro.action(group, action, player)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    if action == "hurt" then
        return SC.Factions.forceStanding(group.id, "Hostile")
    end
    if action == "animal_hurt" then
        value.stage = "unwelcome"
        SC.Factions.adjustStanding(group.id, -25, "player_harmed_rat")
        U().say(actorFor(group),
            "Step on one of my subjects again and I'll feed you to the rest.")
        return true, "rat_king_warned_player"
    end
    if not near(group, player) or value.stage == "unwelcome"
        or value.stage == "vengeance" then return false, "rat_court_closed" end
    local actor = actorFor(group)
    if action == "ask_court" then
        U().say(actor,
            "Rats don't get bit. Rats do the biting. They know when dead folk are near.")
        return true, "subjects_introduced"
    end
    if action ~= "trade_rat" then return false, "rat_choice_unavailable" end
    local food = itemFor(player,
        { ["Base.Cheese"] = true, ["Base.Cornmeal2"] = true })
    local rat = itemFor(actor, { ["Base.DeadRat"] = true }, true)
    local source = food and select(1, U().call(food, "getContainer"))
    local ratSource = rat and select(1, U().call(rat, "getContainer"))
    local playerInventory, kingInventory = U().inventory(player),
        U().inventory(actor)
    if not source or not ratSource or not playerInventory
        or not kingInventory then return false, "rat_trade_items_missing" end
    if not U().transferItemVerified(source, kingInventory, food) then
        return false, "rat_payment_failed"
    end
    if not U().transferItemVerified(ratSource, playerInventory, rat) then
        U().transferItemVerified(kingInventory, source, food)
        return false, "rat_goods_failed"
    end
    U().say(actor, "Hungry? I got protein. Don't ask what kind.")
    return true, "finite_real_rat_trade"
end

return Renfro
