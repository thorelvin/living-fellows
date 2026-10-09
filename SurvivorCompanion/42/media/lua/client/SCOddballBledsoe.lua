-- SPDX-License-Identifier: MIT
-- An actual creekside shack, exact sugar/cornmeal-for-whiskey trades, and an
-- outfit check of worn clothing rather than a carried police shirt in a bag.

local SC = SurvivorCompanion
SC.OddballBledsoe = SC.OddballBledsoe or {}
local Bledsoe = SC.OddballBledsoe
local ID = "bledsoe_brothers_still"

local function U() return SC.GameplayUtil end

local function story(group)
    local value = type(group) == "table" and group.oddball or nil
    if type(value) ~= "table" or value.id ~= ID then return nil end
    value.stage = value.stage or "still_open"
    value.trades = math.max(0, math.min(12,
        math.floor(tonumber(value.trades) or 0)))
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
    local actor = actorFor(group, 1)
    return actor and player and U().distance(actor, player) <= 7
        and U().canSee(player, actor) == true
end

local function itemFor(actor, kind)
    local inventory = actor and U().inventory(actor)
    for _, item in ipairs(inventory and U().inventoryItemsDeep(inventory,
        240, 10) or {}) do
        if U().itemType(item) == kind then return item end
    end
    return nil
end

local function lawOutfit(actor)
    local outfit = select(1, U().call(actor, "getOutfitName"))
    if type(outfit) == "string" then
        local name = string.lower(outfit)
        if string.find(name, "police", 1, true)
            or string.find(name, "deputy", 1, true)
            or string.find(name, "sheriff", 1, true) then
            return true
        end
    end
    local worn = select(1, U().call(actor, "getWornItems"))
    if not worn or not SC.NativeList then return false end
    for index = 0, math.min(63, SC.NativeList.size(worn) - 1) do
        local entry = SC.NativeList.get(worn, index)
        local item = entry and select(1, U().call(entry, "getItem"))
        local kind = item and U().itemType(item)
        if type(kind) == "string" then
            local name = string.lower(kind)
            if string.find(name, "police", 1, true)
                or string.find(name, "deputy", 1, true)
                or string.find(name, "sheriff", 1, true) then
                return true
            end
        end
    end
    return false
end

local function fellowsNear(player, leader)
    local result = {}
    if not SC.Registry or type(SC.Registry.living) ~= "function" then
        return result
    end
    for _, actor in ipairs(SC.Registry.living() or {}) do
        local id = U().idOf(actor)
        local record = id and SC.Registry.byId(id) or nil
        if record and record.recruited == true
            and U().distance(actor, player) <= 10
            and U().distance(actor, leader) <= 12 then
            result[#result + 1] = actor
        end
    end
    return result
end

function Bledsoe.onSpawn(group, actor)
    local value = story(group)
    if not value or not actor then return false, "still_unavailable" end
    if actor == actorFor(group, 1) and value.stockSeeded ~= true then
        local inventory = U().inventory(actor)
        if not inventory then return false, "still_inventory_unavailable" end
        local count = 0
        for _ = 1, 6 do
            if U().addItem(inventory, "Base.Whiskey") then count = count + 1 end
        end
        if count == 0 then return false, "whiskey_stock_unavailable" end
        value.stockSeeded = true
    end
    return true, "still_ready"
end

function Bledsoe.pulse(group, player, current)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    current = tonumber(current) or U().nowMs()
    local leader = actorFor(group, 1)
    if leader and near(group, player) and value.greeted ~= true then
        value.greeted = true
        group.discovered = true
        U().say(leader,
            "That ain't whiskey. Whiskey's got a tax stamp.")
    end
    if not leader or not player or group.standing == "Hostile"
        or current < (tonumber(value.nextLawCheckAt) or 0) then
        return true, value.stage
    end
    value.nextLawCheckAt = current + 5000
    for _, fellow in ipairs(fellowsNear(player, leader)) do
        if lawOutfit(fellow) then
            value.stage = "hostile"
            SC.Factions.forceStanding(group.id, "Hostile")
            U().say(leader,
                "Is that a deputy? Why'd you bring a deputy?")
            return true, "law_outfit_spotted"
        end
        if value.blessed ~= true and SC.Commands
            and type(SC.Commands.peek) == "function" then
            local state = SC.Commands.peek(fellow)
            if state and type(state.ritual) == "table"
                and state.ritual.id == "bourbon_blessing" then
                value.blessed = true
                U().say(fellow,
                    "Bless this still and the foolish souls keeping it warm.")
                U().say(leader,
                    "You know the old words. Have a seat by the creek.")
            end
        end
    end
    return true, value.stage
end

function Bledsoe.intentFor(actor, player, snapshot, group)
    if not story(group) then return nil end
    if group.standing == "Hostile" then
        return { mode = "hostile", priority = 110 }
    end
    local threats = type(snapshot) == "table"
        and (tonumber(snapshot.threatCount) or #(snapshot.threats or {})) or 0
    if threats > 0 then return { mode = "zombie_defense", priority = 18 } end
    return { mode = "oddball_idle", priority = 28 }
end

function Bledsoe.canRecruit()
    return false, "brothers_keep_the_still"
end

function Bledsoe.menuOptions(group, player)
    local value = story(group)
    if not value or not near(group, player)
        or group.standing == "Hostile" then return {} end
    return {
        { id = "ask_still", label = "Ask about the still", enabled = true },
        { id = "trade_mash", label = "Trade sugar and cornmeal for whiskey",
            enabled = itemFor(player, "Base.Sugar") ~= nil
                and itemFor(player, "Base.Cornmeal2") ~= nil
                and itemFor(actorFor(group, 1), "Base.Whiskey") ~= nil },
    }
end

function Bledsoe.action(group, action, player)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    if action == "hurt" then
        value.stage = "hostile"
        return SC.Factions.forceStanding(group.id, "Hostile")
    end
    if not near(group, player) or group.standing == "Hostile" then
        return false, "still_too_far"
    end
    local leader = actorFor(group, 1)
    if action == "ask_still" then
        U().say(leader,
            "Sugar, cornmeal, creek water and a little patience. No taxman.")
        return true, "still_explained"
    end
    if action ~= "trade_mash" then return false, "unknown_still_choice" end
    local sugar = itemFor(player, "Base.Sugar")
    local cornmeal = itemFor(player, "Base.Cornmeal2")
    local whiskey = itemFor(leader, "Base.Whiskey")
    local sugarSource = sugar and select(1, U().call(sugar, "getContainer"))
    local cornSource = cornmeal and select(1, U().call(cornmeal,
        "getContainer"))
    local whiskeySource = whiskey and select(1, U().call(whiskey,
        "getContainer"))
    local playerInventory, stillInventory = U().inventory(player),
        U().inventory(leader)
    if not sugarSource or not cornSource or not whiskeySource
        or not playerInventory or not stillInventory then
        return false, "still_goods_missing"
    end
    if not U().transferItemVerified(sugarSource,
        stillInventory, sugar) then
        return false, "sugar_transfer_failed"
    end
    if not U().transferItemVerified(cornSource,
        stillInventory, cornmeal) then
        U().transferItemVerified(stillInventory, sugarSource, sugar)
        return false, "cornmeal_transfer_failed"
    end
    if not U().transferItemVerified(whiskeySource,
        playerInventory, whiskey) then
        U().transferItemVerified(stillInventory, cornSource, cornmeal)
        U().transferItemVerified(stillInventory, sugarSource, sugar)
        return false, "whiskey_transfer_failed"
    end
    value.trades = value.trades + 1
    U().say(leader, "There. You won't find this bottle in a tax ledger.")
    return true, "exact_mash_for_whiskey_trade"
end

return Bledsoe
