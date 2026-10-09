-- SPDX-License-Identifier: MIT
-- The Crabtree flock consists of named vanilla sheep, tracked by native ID.
-- The player settles the dispute; animal feeding, shearing and leading stay
-- native game actions.

local SC = SurvivorCompanion
SC.OddballCrabtree = SC.OddballCrabtree or {}
local Crabtree = SC.OddballCrabtree
local ID = "crabtree_sheep_farm"
local FLOCK = {
    { kind = "ewe", breed = "rambouillet", name = "Mabel" },
    { kind = "ewe", breed = "rambouillet", name = "Daisy" },
    { kind = "ewe", breed = "friesian", name = "June" },
    { kind = "ewe", breed = "friesian", name = "Pearl" },
    { kind = "ewe", breed = "suffolk", name = "Nell" },
    { kind = "ram", breed = "suffolk", name = "King" },
}

local function U() return SC.GameplayUtil end

local function story(group)
    local value = type(group) == "table" and group.oddball or nil
    if type(value) ~= "table" or value.id ~= ID then return nil end
    value.stage = value.stage or "dispute"
    value.recruitmentCandidateKey = value.side == "lyle"
        and "member-1" or "member-2"
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
    for index = 1, 2 do
        local actor = actorFor(group, index)
        if actor and player and U().distance(actor, player) <= 7
            and U().canSee(player, actor) == true then return true end
    end
    return false
end

local function itemFor(actor, kind)
    local inventory = actor and U().inventory(actor)
    for _, item in ipairs(inventory and U().inventoryItemsDeep(inventory,
        160, 8) or {}) do
        if U().itemType(item) == kind then return item end
    end
    return nil
end

local function seedFlock(group)
    local value = story(group)
    if not value or not value.site or not value.site.animalSpawns then
        return false, "sheep_pen_unavailable"
    end
    local all = true
    for slot, spec in ipairs(FLOCK) do
        local status = SC.OddballAnimals.status(group, slot)
        if status == "unseeded" then
            local okay = SC.OddballAnimals.spawn(group, slot, spec,
                value.site.animalSpawns[slot])
            if not okay then all = false end
        end
    end
    value.flockSeeded = all
    return all, all and "six_real_sheep" or "flock_partly_seeded"
end

function Crabtree.onSpawn(group, actor)
    local value = story(group)
    if not value or not actor then return false, "crabtree_unavailable" end
    if value.flockSeeded ~= true then seedFlock(group) end
    if actor == actorFor(group, 2) and value.stockSeeded ~= true then
        local inventory = U().inventory(actor)
        if not inventory then return false, "shepherd_inventory_unavailable" end
        local wool = U().addItem(inventory, "Base.WoolRaw")
        local milk = U().addItem(inventory, "Base.Milk")
        if not wool or not milk then return false, "shepherd_stock_unavailable" end
        value.stockSeeded = true
    end
    return true, "crabtrees_ready"
end

function Crabtree.pulse(group, player, current)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    if value.flockSeeded ~= true
        and current >= (tonumber(value.nextFlockRetryAt) or 0) then
        value.nextFlockRetryAt = current + 30000
        seedFlock(group)
    end
    if near(group, player) and value.greeted ~= true then
        value.greeted = true
        group.discovered = true
        U().say(actorFor(group, 2),
            "Six sheep, one drunk and the end of the world. Guess who I feed first.")
        U().say(actorFor(group, 1), "Wake me when the world's fixed.")
    end
    for slot = 1, 6 do
        local state, sheep = SC.OddballAnimals.status(group, slot)
        if state == "alive" and sheep then
            local keeper = actorFor(group, value.side == "lyle" and 1 or 2)
            if keeper then SC.OddballAnimals.follow(group, slot, keeper,
                current) end
        end
    end
    return true, value.stage
end

function Crabtree.intentFor(actor, player, snapshot, group)
    local value = story(group)
    if not value then return nil end
    if group.standing == "Hostile" then
        return { mode = "hostile", priority = 110 }
    end
    local threats = type(snapshot) == "table"
        and (tonumber(snapshot.threatCount) or #(snapshot.threats or {})) or 0
    if threats > 0 then return { mode = "zombie_defense", priority = 18 } end
    if value.side and actor == actorFor(group,
        value.side == "dewayne" and 1 or 2) then
        return { mode = "crabtree_leave", priority = 45 }
    end
    return { mode = "oddball_idle", priority = 28 }
end

function Crabtree.update(actor, player, runtime, intent, group)
    if not intent or intent.mode ~= "crabtree_leave" then
        return false, "shepherd_at_pen"
    end
    local value = story(group)
    local memberIndex = value.side == "dewayne" and 1 or 2
    local member = group.members and group.members[memberIndex]
    if not member or member.departed == true then return true, "already_left" end
    local anchor = value.site and value.site.anchor
    local ax, ay, az = U().position(actor)
    if not anchor or not ax then return false, "farm_exit_unavailable" end
    local separation = (ax - anchor.x) ^ 2 + (ay - anchor.y) ^ 2
    if separation >= 20 * 20 and player
        and U().canSee(player, actor) ~= true then
        if SC.Actor and SC.Actor.remove and SC.Actor.remove(actor) then
            member.actorId = nil
            member.departed = true
            U().say(actorFor(group, value.side == "dewayne" and 2 or 1),
                "He made his choice. The sheep didn't get one.")
            return true, "farm_member_walked_away"
        end
    end
    local dx = ax >= anchor.x and 25 or -25
    local destination = U().gridSquare(anchor.x + dx, anchor.y, az or 0)
    if not destination or not SC.Navigation
        or type(SC.Navigation.request) ~= "function" then
        return false, "farm_exit_route_unavailable"
    end
    return SC.Navigation.request(actor, destination, "walk", {
        action = "crabtree_walk_away", arrivalDistance = 1 })
end

function Crabtree.canRecruit(group)
    local value = story(group)
    if not value or not value.side then return false, "settle_the_farm_first" end
    if group.standing ~= "Trusted" then return false, "earn_farm_trust" end
    return true, "chosen_farmer_can_join"
end

function Crabtree.menuOptions(group, player)
    local value = story(group)
    if not value or not near(group, player) then return {} end
    if not value.side then
        return {
            { id = "side_dewayne", label = "Side with Dewayne and the flock",
                enabled = true },
            { id = "side_lyle", label = "Side with Lyle, the owner",
                enabled = true },
        }
    end
    local options = {
        { id = "ask_flock", label = "Ask about the sheep", enabled = true },
        { id = "recruit", label = "Ask the farmer to join",
            enabled = Crabtree.canRecruit(group) == true },
    }
    if value.side == "dewayne" then
        options[#options + 1] = { id = "trade_wool",
            label = "Trade for wool and milk", enabled = value.traded ~= true }
        options[#options + 1] = { id = "lead_lamb",
            label = "Ask to lead a lamb home", enabled = value.lambOffered ~= true }
    end
    return options
end

function Crabtree.action(group, action, player)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    if action == "hurt" or action == "animal_hurt" then
        return SC.Factions.forceStanding(group.id, "Hostile")
    end
    if not near(group, player) then return false, "farm_too_far" end
    if (action == "side_dewayne" or action == "side_lyle")
        and not value.side then
        value.side = action == "side_dewayne" and "dewayne" or "lyle"
        value.recruitmentCandidateKey = value.side == "lyle"
            and "member-1" or "member-2"
        value.stage = "farm_settled"
        SC.Factions.forceStanding(group.id, "Trusted")
        U().say(actorFor(group, value.side == "lyle" and 1 or 2),
            value.side == "lyle"
                and "It's my land. I'll try to keep them fed. Try."
                or "Ewes don't care about zombies. They care about breakfast.")
        return true, "crabtree_side_chosen"
    end
    local keeper = actorFor(group, value.side == "lyle" and 1 or 2)
    if action == "ask_flock" and keeper then
        U().say(keeper, value.side == "lyle"
            and "Dewayne left. I reckon the sheep will tell me when they're hungry."
            or "Six living souls. They need feeding and shearing; you can help with the real work.")
        return true, "flock_discussed"
    end
    if action == "trade_wool" and value.side == "dewayne"
        and value.traded ~= true then
        local shepherd = actorFor(group, 2)
        local wool, milk = itemFor(shepherd, "Base.WoolRaw"),
            itemFor(shepherd, "Base.Milk")
        local playerInventory = U().inventory(player)
        local woolSource = wool and select(1, U().call(wool, "getContainer"))
        local milkSource = milk and select(1, U().call(milk, "getContainer"))
        if not woolSource or not milkSource or not playerInventory then
            return false, "shepherd_goods_unavailable"
        end
        if not U().transferItemVerified(woolSource, playerInventory, wool) then
            return false, "wool_transfer_failed"
        end
        if not U().transferItemVerified(milkSource, playerInventory, milk) then
            U().transferItemVerified(playerInventory, woolSource, wool)
            return false, "milk_transfer_failed"
        end
        value.traded = true
        U().say(shepherd, "Wool and milk. The rest you earn by helping the flock.")
        return true, "real_wool_and_milk_traded"
    end
    if action == "lead_lamb" and value.side == "dewayne"
        and value.lambOffered ~= true then
        local spec = { kind = "lamb", breed = "friesian", name = "Little Blue" }
        local spawned = SC.OddballAnimals.spawn(group, 7, spec,
            value.site.animalSpawns[1])
        if not spawned then return false, "lamb_spawn_unavailable" end
        local leash = U().addItem(U().inventory(player), "Base.Leash")
        if not leash then return false, "lamb_leash_unavailable" end
        value.lambOffered = true
        U().say(actorFor(group, 2),
            "Little Blue's yours. Put that leash on her yourself; she knows the way out.")
        return true, "real_lamb_waits_for_vanilla_lead"
    end
    if action == "recruit" and Crabtree.canRecruit(group) == true
        and SC.FactionRecruitment then
        local asked, reason = SC.FactionRecruitment.ask(group.id, player, false)
        if not asked then return false, reason end
        return SC.FactionRecruitment.startTrial(group.id, player, false)
    end
    return false, "farm_choice_unavailable"
end

return Crabtree
