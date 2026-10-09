-- SPDX-License-Identifier: MIT
-- An ally anchored to his church. Combat uses faction zombie defense; trade
-- uses the same exact item transfer contract as the other authored residents.

local SC = SurvivorCompanion
SC.OddballAmos = SC.OddballAmos or {}
local Amos = SC.OddballAmos
local ID = "preacher_reverend_amos"

local function U() return SC.GameplayUtil end

local function story(group)
    local value = type(group) == "table" and group.oddball or nil
    if type(value) ~= "table" or value.id ~= ID then return nil end
    value.stage = value.stage or "watching"
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

local function itemFor(actor, predicate)
    local inventory = actor and U().inventory(actor)
    for _, item in ipairs(inventory and U().inventoryItemsDeep(inventory,
        160, 8) or {}) do
        if predicate(U().itemType(item)) then return item end
    end
    return nil
end

local function canned(kind)
    return type(kind) == "string"
        and string.sub(kind, 1, 11) == "Base.Canned"
        and not string.find(kind, "Open", 1, true)
        and not string.find(kind, "Empty", 1, true)
end

local function box(kind) return kind == "Base.ShotgunShellsBox" end

local function playerNeedsHelp(player)
    local px, py, pz = U().position(player)
    if not px then return false end
    for dx = -5, 5 do
        for dy = -5, 5 do
            if dx * dx + dy * dy <= 25 then
                local square = U().gridSquare(math.floor(px + dx),
                    math.floor(py + dy), pz or 0)
                local moving = square and select(1, U().call(square,
                    "getMovingObjects"))
                if moving and SC.NativeList then
                    for index = 0, math.min(15,
                        SC.NativeList.size(moving) - 1) do
                        local zombie = SC.NativeList.get(moving, index)
                        if zombie and U().isZombie(zombie) then return true end
                    end
                end
            end
        end
    end
    return false
end

function Amos.onSpawn(group, actor)
    local value = story(group)
    if not value or not actor then return false, "preacher_unavailable" end
    local inventory = U().inventory(actor)
    if not inventory then return false, "preacher_inventory_unavailable" end
    if value.stockSeeded ~= true then
        local weapon = U().addItem(inventory, "Base.DoubleBarrelShotgun")
        if not weapon then return false, "preacher_shotgun_unavailable" end
        U().call(actor, "setPrimaryHandItem", weapon)
        local stocked = 0
        for _ = 1, 3 do
            if U().addItem(inventory, "Base.ShotgunShellsBox") then
                stocked = stocked + 1 end
        end
        if stocked < 1 then return false, "preacher_shells_unavailable" end
        value.stockSeeded = true
    end
    if group.standing ~= "Hostile" and SC.Factions
        and type(SC.Factions.forceStanding) == "function" then
        SC.Factions.forceStanding(group.id, "Trusted")
    end
    return true, "preacher_armed"
end

function Amos.pulse(group, player, current)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    current = tonumber(current) or U().nowMs()
    local actor = actorFor(group)
    if near(group, player) and value.greeted ~= true then
        value.greeted = true
        group.discovered = true
        U().say(actor,
            "Come, come, my children! Ha! Come and be shriven!")
    end
    if player and actor and current >= (tonumber(value.nextHelpCheckAt) or 0) then
        value.nextHelpCheckAt = current + 5000
        local post = value.site and value.site.spawn
        value.playerNeedsHelp = post and U().distance(player, post) <= 30
            and playerNeedsHelp(player) or false
    end
    return true, value.stage
end

function Amos.onZombieDead(group, zombie, attacker)
    local value = story(group)
    local actor = actorFor(group)
    if not value or not actor or attacker ~= actor then return false end
    local current = U().nowMs()
    if current >= (tonumber(value.nextPreachAt) or 0) then
        value.nextPreachAt = current + 30000
        local clean = U().config and U().config("profanityEnabled") == false
        U().say(actor, clean
            and "Rise, you rotten wretches, and be judged! Ha!"
            or "Rise, you rotten bastards, and be judged! Ha!")
    end
    return true
end

function Amos.intentFor(actor, player, snapshot, group)
    local value = story(group)
    if not value then return nil end
    if group.standing == "Hostile" then
        return { mode = "hostile", priority = 110 }
    end
    local threats = type(snapshot) == "table"
        and (tonumber(snapshot.threatCount) or #(snapshot.threats or {})) or 0
    if threats > 0 then return { mode = "zombie_defense", priority = 18 } end
    if value.playerNeedsHelp then
        return { mode = "amos_support", priority = 35 }
    end
    return { mode = "amos_church", priority = 30 }
end

function Amos.update(actor, player, runtime, intent, group)
    if not intent or (intent.mode ~= "amos_church"
        and intent.mode ~= "amos_support") then return false end
    local value = story(group)
    local post = intent.mode == "amos_support" and player
        or value.site and value.site.spawn
    if not post then return true, "church_post_unavailable" end
    local x, y, z = U().position(actor)
    local px, py, pz = U().position(post)
    if x and px and z == pz
        and (x - px) ^ 2 + (y - py) ^ 2 <= 3 * 3 then
        return true, intent.mode == "amos_support"
            and "preacher_supporting_player" or "preacher_at_church"
    end
    local square = U().gridSquare(math.floor(px), math.floor(py),
        math.floor(pz or 0))
    if not square then return true, "preacher_route_unloaded" end
    if not SC.Navigation or type(SC.Navigation.request) ~= "function" then
        return false, "navigation_unavailable"
    end
    return SC.Navigation.request(actor, square, "walk", {
        action = "faction_support", arrivalDistance = 3 })
end

function Amos.canRecruit()
    return false, "preacher_wont_leave_his_flock"
end

function Amos.menuOptions(group, player)
    local value = story(group)
    if not value or not near(group, player) then return {} end
    return { { id = "tithe_food", label = "Trade canned food for shells",
        enabled = itemFor(player, canned) ~= nil
            and itemFor(actorFor(group), box) ~= nil },
        { id = "ask_flock", label = "Ask about his flock",
            enabled = true } }
end

function Amos.action(group, action, player)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    if action == "hurt" then
        return SC.Factions.forceStanding(group.id, "Hostile")
    end
    if not near(group, player) then return false, "preacher_too_far" end
    local actor = actorFor(group)
    if action == "ask_flock" then
        U().say(actor, "Every one of them was baptized in that font. Every one.")
        return true, "flock_remembered"
    end
    if action ~= "tithe_food" then return false, "unknown_preacher_choice" end
    local food = itemFor(player, canned)
    local shells = itemFor(actor, box)
    local foodSource = food and select(1, U().call(food, "getContainer"))
    local shellsSource = shells and select(1, U().call(shells, "getContainer"))
    local playerInventory = U().inventory(player)
    local preacherInventory = U().inventory(actor)
    if not food or not shells or not foodSource or not shellsSource
        or not playerInventory or not preacherInventory then
        return false, "tithe_or_shells_unavailable"
    end
    if not U().transferItemVerified(foodSource, preacherInventory, food) then
        return false, "tithe_transfer_failed"
    end
    if not U().transferItemVerified(shellsSource,
        playerInventory, shells) then
        U().transferItemVerified(preacherInventory, foodSource, food)
        return false, "shells_transfer_failed"
    end
    value.trades = (tonumber(value.trades) or 0) + 1
    U().say(actor, "The Lord provides. Today He provided buckshot.")
    return true, "tithe_traded_for_real_shells"
end

return Amos
