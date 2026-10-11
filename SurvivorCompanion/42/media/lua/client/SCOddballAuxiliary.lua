-- SPDX-License-Identifier: MIT
-- Three kitchen defenders sell finite, real baked goods for exact ingredients.
-- An attack flips the whole faction hostile; Opal uses native recruitment.

local SC = SurvivorCompanion
SC.OddballAuxiliary = SC.OddballAuxiliary or {}
local Auxiliary = SC.OddballAuxiliary
local ID = "rosewood_auxiliary"
local REWARDS = { "Base.Pie", "Base.CakeCarrot", "Base.Pie",
    "Base.CakeChocolate", "Base.Pie", "Base.CakeStrawberryShortcake" }
-- Props for the kitchen scene only. Trades still require the player's own
-- flour and sugar; these items are never spent by the ambient Craft visuals.
local INGREDIENTS = {
    { "Base.Flour2", "Base.Sugar" },
    { "Base.Egg", "Base.Egg", "Base.Butter" },
    { "Base.Milk", "Base.Yeast", "Base.Salt" },
}
local kitchenStates = setmetatable({}, { __mode = "k" })
local FACINGS = { { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 } }

local function U() return SC.GameplayUtil end

local function story(group)
    local value = type(group) == "table" and group.oddball or nil
    if type(value) ~= "table" or value.id ~= ID then return nil end
    value.stage = value.stage or "bake_sale"
    value.trades = math.max(0, math.min(#REWARDS,
        math.floor(tonumber(value.trades) or 0)))
    value.gearSeeded = value.gearSeeded or {}
    value.ingredientsSeeded = value.ingredientsSeeded or {}
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

local function indexFor(group, actor)
    for index = 1, 3 do
        if actor == actorFor(group, index) then return index end
    end
    return nil
end

local function kitchenPost(group, index)
    local site = group and group.oddball and group.oddball.site
    return site and ((site.memberSpawns and site.memberSpawns[index])
        or site.spawn) or nil
end

local function fixtureScore(object, index)
    local container = select(1, U().call(object, "getContainer"))
    local kind = string.lower(tostring(container
        and select(1, U().call(container, "getType")) or ""))
    if kind == "stove" or kind == "microwave"
        or U().instanceOf(object, "IsoStove") then
        return index == 2 and 4 or 2, container
    elseif kind == "counter" then
        return index == 2 and 3 or 4, container
    elseif kind == "fridge" or kind == "freezer" then
        return index == 1 and 3 or 1, container
    end
    return 0, nil
end

local function fixtureFacing(post, index)
    if not post or type(U().squareObjects) ~= "function" then return nil end
    local postSquare = U().gridSquare(post.x, post.y, post.z or 0)
    local kitchen = postSquare and select(1, U().call(postSquare, "getRoom"))
    if not kitchen then return nil end
    local best, bestScore
    -- Rotate equal-score ties so the three workers do not automatically face
    -- the same wall when a kitchen has counters on several sides.
    for step = 0, 3 do
        local delta = FACINGS[(step + index - 1) % 4 + 1]
        local x, y = post.x + delta[1], post.y + delta[2]
        local square = U().gridSquare(x, y, post.z or 0)
        if square and select(1, U().call(square, "getRoom")) == kitchen then
            local score, chosenContainer = 0, nil
            U().squareObjects(square, function(object)
                local option, container = fixtureScore(object, index)
                if option > score then
                    score, chosenContainer = option, container
                end
            end, 32)
            if score > 0 and (not bestScore or score > bestScore) then
                best, bestScore = { x = x + 0.5, y = y + 0.5,
                    container = chosenContainer }, score
            end
        end
    end
    return best
end

local function facingDirection(post, target)
    if not post or not target then return nil end
    local dx, dy = target.x - (post.x + 0.5),
        target.y - (post.y + 0.5)
    if math.abs(dx) >= math.abs(dy) then
        return dx >= 0 and "east" or "west"
    end
    return dy >= 0 and "south" or "north"
end

local function kitchenFacings(group)
    local posts, targets = {}, {}
    for index = 1, 3 do posts[index] = kitchenPost(group, index) end
    for index = 1, 3 do
        targets[index] = fixtureFacing(posts[index], index)
            or (posts[index == 3 and 1 or index + 1] and {
                x = posts[index == 3 and 1 or index + 1].x + 0.5,
                y = posts[index == 3 and 1 or index + 1].y + 0.5 })
    end
    local first = facingDirection(posts[1], targets[1])
    if first and first == facingDirection(posts[2], targets[2])
        and first == facingDirection(posts[3], targets[3]) then
        -- One long counter can still yield three identical poses. The quiet
        -- baker turns to her colleague instead of staring into that wall.
        local other = posts[2]
        if other then targets[3] = { x = other.x + 0.5,
            y = other.y + 0.5 } end
        if first == facingDirection(posts[3], targets[3]) and posts[3] then
            local delta = FACINGS[first == "north" and 2
                or first == "east" and 3 or 1]
            targets[3] = { x = posts[3].x + delta[1] + 0.5,
                y = posts[3].y + delta[2] + 0.5 }
        end
    end
    return targets
end

local function faceKitchen(group, actor, index)
    local target = kitchenFacings(group)[index]
    if not target then return false, nil end
    local _, called = U().call(actor, "faceLocationF", target.x, target.y)
    return called == true, target
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

local function seedIngredients(value, actor, index, inventory)
    local slots = value.ingredientsSeeded[index]
    if type(slots) ~= "table" then
        slots = {}
        value.ingredientsSeeded[index] = slots
    end
    for slot, kind in ipairs(INGREDIENTS[index] or {}) do
        if slots[slot] ~= true then
            local marker = tostring(index) .. ":" .. tostring(slot)
            local existing = itemFor(actor, function(_, item)
                local data = U().modData(item)
                return data and data.lfAuxiliaryIngredient == marker
            end)
            local item = existing or U().addItem(inventory, kind)
            if not item then return false, "baking_ingredient_unavailable" end
            local data = U().modData(item)
            if data then data.lfAuxiliaryIngredient = marker end
            slots[slot] = true
        end
    end
    return true
end

local function seedChefHat(value, actor, inventory)
    if value.chefHatSeeded == true then return true end
    local worn, checked = U().call(actor, "getWornItem", "Hat")
    if not checked then return false, "chef_hat_slot_unavailable" end
    if worn ~= nil then
        if U().itemType(worn) == "Base.Hat_ChefHat" then
            value.chefHatSeeded = true
            return true
        end
        local data = U().modData(worn)
        local favorite = select(1, U().call(worn, "isFavorite"))
        if favorite == true or data
            and data.SC_ManualWearFor == U().idOf(actor) then
            -- A player-picked or favorited hat outranks the scene costume.
            value.chefHatSeeded = true
            return true
        end
    end
    -- Replace an ordinary outfit hat on first staging; it stays in inventory.
    local hat = itemFor(actor, function(kind)
        return kind == "Base.Hat_ChefHat"
    end) or U().addItem(inventory, "Base.Hat_ChefHat")
    if not hat then return false, "chef_hat_unavailable" end
    U().call(actor, "setWornItem", "Hat", hat)
    local equipped = select(1, U().call(actor, "getWornItem", "Hat"))
    if equipped ~= hat then return false, "chef_hat_equip_failed" end
    U().call(actor, "resetModelNextFrame")
    value.chefHatSeeded = true
    return true
end

function Auxiliary.onSpawn(group, actor)
    local value = story(group)
    if not value or not actor then return false, "auxiliary_unavailable" end
    local index = indexFor(group, actor)
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
    local supplied, supplyReason = seedIngredients(value, actor,
        index, inventory)
    if not supplied then return false, supplyReason end
    if index == 2 then
        local hatted, hatReason = seedChefHat(value, actor, inventory)
        if not hatted then return false, hatReason end
    end
    local current = type(U().nowMs) == "function" and U().nowMs() or 0
    kitchenStates[actor] = { nextActionAt = current + (index - 1) * 2500 }
    faceKitchen(group, actor, index)
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
    return { mode = "auxiliary_kitchen", priority = 28 }
end

function Auxiliary.update(actor, player, runtime, intent, group)
    if not story(group) or not intent
        or intent.mode ~= "auxiliary_kitchen" then
        return false, "auxiliary_idle"
    end
    local index = indexFor(group, actor)
    local post = index and kitchenPost(group, index)
    if not post then return false, "kitchen_post_unavailable" end
    local state = kitchenStates[actor]
    if not state then
        state = { nextActionAt = U().nowMs() + (index - 1) * 2500 }
        kitchenStates[actor] = state
    end
    if state.action and SC.NativeActions
        and type(SC.NativeActions.visualStatus) == "function" then
        local status = SC.NativeActions.visualStatus(actor, state.action)
        if status == "active" then return true, "kitchen_activity_active" end
        if status == "different" then return false, "other_visual_owns_actor" end
        if type(SC.NativeActions.clearVisual) == "function" then
            SC.NativeActions.clearVisual(actor)
        end
        state.action = nil
        state.nextActionAt = U().nowMs() + 6000 + index * 2800
    end
    local square = U().gridSquare(post.x, post.y, post.z or 0)
    if not square then return false, "kitchen_post_unloaded" end
    -- Navigation aims at the square centre, whereas `post` records its corner.
    -- Share that centre contract so an arrival cannot re-request the same path.
    if not U().arrived(actor, square, {
        targetKind = "square", distance = 0.95 }) then
        state.atPost = false
        if not SC.Navigation
            or type(SC.Navigation.request) ~= "function" then
            return false, "kitchen_post_unreachable"
        end
        return SC.Navigation.request(actor, square, "walk", {
            action = "auxiliary_return_to_kitchen", arrivalDistance = 0.9,
            movementPriority = 20 })
    end
    if state.atPost ~= true then
        U().stop(actor)
        state.atPost = true
        faceKitchen(group, actor, index)
    end
    if U().nowMs() < (tonumber(state.nextActionAt) or 0) then
        return true, "kitchen_between_tasks"
    end
    local _, workTarget = faceKitchen(group, actor, index)
    local action = index == 1 and workTarget
        and workTarget.container and "loot_container" or "craft_supply"
    local started, reason = U().move(actor, "walk", { action = action,
        targetSquare = square,
        container = action == "loot_container"
            and workTarget.container or nil })
    if started then state.action = action end
    return started, reason or "kitchen_activity_started"
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
