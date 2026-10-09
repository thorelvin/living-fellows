-- SPDX-License-Identifier: MIT
-- Lester's house uses the ordinary faction barricade worker. The barter is
-- an exact two-way transfer with a finite stock; his corpse carries the clue.

local SC = SurvivorCompanion
SC.OddballLester = SC.OddballLester or {}
local Lester = SC.OddballLester
local ID = "slot_lester_voss"
local MAX_TRADES = 10
local STOCK = {
    "Base.Bandage", "Base.TinnedBeans", "Base.Bullets9mmBox",
    "Base.Bandage", "Base.TinnedSoup", "Base.Pills",
    "Base.Bandage", "Base.CannedPeaches", "Base.Bullets9mmBox",
    "Base.Bandage",
}

local function U() return SC.GameplayUtil end

local function story(group)
    local value = type(group) == "table" and group.oddball or nil
    if type(value) ~= "table" or value.id ~= ID then return nil end
    value.stage = value.stage or "fortifying"
    value.trades = math.max(0, math.min(MAX_TRADES,
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

local function slotDoor(value)
    local point = value and value.site and value.site.slotDoor
    local square = point and U().gridSquare(point.x, point.y, point.z or 0)
    local objects = square and select(1, U().call(square, "getObjects"))
    if not objects or not SC.NativeList then return nil end
    local object = SC.NativeList.get(objects, point.objectIndex)
    if object and U().instanceOf(object, "IsoDoor") then return object end
    for index = 0, SC.NativeList.size(objects) - 1 do
        object = SC.NativeList.get(objects, index)
        if U().instanceOf(object, "IsoDoor") then return object end
    end
    return nil
end

local function doorClosed(value)
    local door = slotDoor(value)
    if not door then return false end
    local opened, called = U().call(door, "IsOpen")
    return called and opened == false
end

local function nearPoint(player, point, radius)
    local x, y, z = U().position(player)
    return x ~= nil and type(point) == "table"
        and z == (point.z or 0)
        and (x - point.x) ^ 2 + (y - point.y) ^ 2 <= radius * radius
end

function Lester.canTalkThroughSlot(group, player)
    local value = story(group)
    if not value or not actorFor(group, 2) or not doorClosed(value)
        or not nearPoint(player, value.site.slotOutside, 2.5) then
        return false
    end
    local square = U().squareOf(player)
    return square ~= nil and select(1, U().call(square, "getRoom")) == nil
end

local function playerInside(group, player)
    local x, y, z = U().position(player)
    local bounds = group and group.house and group.house.bounds
    local site = group and group.oddball and group.oddball.site
    return x and bounds and site and z == (site.spawn.z or 0)
        and x >= bounds.x1 and x <= bounds.x2
        and y >= bounds.y1 and y <= bounds.y2
        and select(1, U().call(U().squareOf(player), "getRoom")) ~= nil
end

local function itemFor(actor, predicate)
    local inventory = actor and U().inventory(actor)
    for _, item in ipairs(inventory and U().inventoryItemsDeep(inventory,
        240, 10) or {}) do
        if predicate(U().itemType(item), item) then return item end
    end
    return nil
end

local function payment(kind)
    return type(kind) == "string" and (
        (string.sub(kind, 1, 11) == "Base.Tinned"
            or string.sub(kind, 1, 11) == "Base.Canned")
            and not string.find(kind, "Open", 1, true)
            and not string.find(kind, "Empty", 1, true)
        or kind == "Base.CigarettePack" or kind == "Base.Bandage")
end

local function reward(_, item)
    local data = U().modData(item)
    return data and data.lfLesterStock == true
end

local function addBarricadeJob(group, opening, index)
    if opening.kind ~= "door" and opening.kind ~= "window" then return end
    group.jobs = group.jobs or {}
    local id = group.id .. ":lester:barricade:" .. tostring(index)
    for _, job in ipairs(group.jobs) do if job.id == id then return end end
    group.jobs[#group.jobs + 1] = {
        id = id, kind = "barricade", phase = "final", targetPlanks = 4,
        target = { x = opening.x, y = opening.y, z = opening.z or 0,
            objectIndex = opening.objectIndex, kind = opening.kind },
        status = "open", attempts = 0,
    }
end

function Lester.onSpawn(group, actor)
    local value = story(group)
    if not value or not actor then return false, "slot_unavailable" end
    if actor == actorFor(group, 1) and value.husbandNoteSeeded ~= true then
        local inventory = U().inventory(actor)
        local note = inventory and U().addItem(inventory,
            "Base.LetterHandwritten")
        if not note then return false, "husband_note_unavailable" end
        U().call(note, "setName",
            "Lester's letter: Martha, keep the slot moving. I am sorry.")
        value.husbandNoteSeeded = true
    end
    if actor == actorFor(group, 2) and value.stockSeeded ~= true then
        local inventory = U().inventory(actor)
        if not inventory then return false, "trader_inventory_unavailable" end
        local added = 0
        for _, kind in ipairs(STOCK) do
            local item = U().addItem(inventory, kind)
            if item then
                local data = U().modData(item)
                if data then data.lfLesterStock = true end
                added = added + 1
            end
        end
        if added == 0 then return false, "slot_stock_unavailable" end
        U().addItem(inventory, "Base.Hammer")
        for _ = 1, 20 do U().addItem(inventory, "Base.Plank") end
        for _ = 1, 40 do U().addItem(inventory, "Base.Nails") end
        for index, opening in ipairs(group.house and group.house.openings or {}) do
            if index > 5 then break end
            addBarricadeJob(group, opening, index)
        end
        value.stockSeeded = true
    end
    return true, "slot_ready"
end

function Lester.pulse(group, player)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    local husband, wife = actorFor(group, 1), actorFor(group, 2)
    if husband and wife and value.husbandNoteSeeded
        and value.husbandDeathRequested ~= true
        and SC.Actor and type(SC.Actor.endLife) == "function" then
        local ended = SC.Actor.endLife(husband)
        if ended then value.husbandDeathRequested = true end
    end
    if player and wife and playerInside(group, player)
        and U().canSee(player, wife) == true
        and value.revealed ~= true then
        value.revealed = true
        value.stage = "revealed"
        group.discovered = true
        U().say(wife,
            "Lester died before you arrived. I kept the slot moving. Somebody had to.")
    elseif player and Lester.canTalkThroughSlot(group, player)
        and value.greeted ~= true then
        value.greeted = true
        group.discovered = true
        U().say(wife,
            "Put it in the slot. Slowly. I can hear you breathing.")
    end
    return true, value.stage
end

function Lester.intentFor(actor, player, snapshot, group)
    local value = story(group)
    if not value then return nil end
    if group.standing == "Hostile" then
        return { mode = "hostile", priority = 110 }
    end
    local threats = type(snapshot) == "table"
        and (tonumber(snapshot.threatCount) or #(snapshot.threats or {})) or 0
    if threats > 0 then return { mode = "zombie_defense", priority = 18 } end
    if actor == actorFor(group, 2) and value.stockSeeded then
        for _, job in ipairs(group.jobs or {}) do
            if job.status ~= "completed" and job.status ~= "cancelled" then
                return { mode = "lester_fortify", priority = 57 }
            end
        end
    end
    return { mode = "oddball_idle", priority = 28 }
end

function Lester.update(actor, player, runtime, intent, group)
    if intent and intent.mode == "lester_fortify" then
        return SC.FactionBehavior.fortifyOddball(actor, group)
    end
    return false, "slot_idle"
end

function Lester.canRecruit()
    return false, "martha_keeps_the_house"
end

function Lester.menuOptions(group, player)
    local value = story(group)
    if not value then return {} end
    if Lester.canTalkThroughSlot(group, player) then
        if value.stage == "quiet" then
            return { { id = "listen", label = "Listen at the silent slot",
                enabled = true } }
        end
        return {
            { id = "knock", label = "Knock on Lester's door",
                enabled = true },
            { id = "peek", label = "Peek into the slot",
                enabled = true },
            { id = "slot_trade", label = "Trade canned food through the slot",
                enabled = value.trades < MAX_TRADES
                    and itemFor(player, payment) ~= nil
                    and itemFor(actorFor(group, 2), reward) ~= nil },
        }
    end
    local wife = actorFor(group, 2)
    if wife and value.revealed and U().distance(player, wife) <= 6
        and U().canSee(player, wife) == true then
        return { { id = "ask_lester", label = "Ask Martha about Lester",
            enabled = true } }
    end
    return {}
end

function Lester.action(group, action, player)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    if action == "hurt" then
        return SC.Factions.forceStanding(group.id, "Hostile")
    end
    local wife = actorFor(group, 2)
    if action == "ask_lester" and wife and value.revealed
        and U().distance(player, wife) <= 6 then
        U().say(wife,
            "He wrote the last price list in his robe. The letter's still with him.")
        return true, "lester_letter_on_corpse"
    end
    if not Lester.canTalkThroughSlot(group, player) or not wife then
        return false, "slot_unavailable"
    end
    if action == "listen" and value.stage == "quiet" then
        return true, "nothing_moves_behind_the_slot"
    end
    if action == "knock" and value.stage ~= "quiet" then
        U().say(wife, "No faces. Faces are how it gets in.")
        return true, "voice_behind_door"
    end
    if action == "peek" and value.stage ~= "quiet" then
        U().say(wife, U().config("profanityEnabled") == false
            and "The slot's for trading, not for your eyeball."
            or "The slot's for trading, not for your goddamn eyeball.")
        return true, "trader_hides_behind_slot"
    end
    if action ~= "slot_trade" or value.trades >= MAX_TRADES
        or value.stage == "quiet" then
        return false, "slot_trade_finished"
    end
    local offered = itemFor(player, payment)
    local stocked = itemFor(wife, reward)
    local offerSource = offered and select(1, U().call(offered, "getContainer"))
    local stockSource = stocked and select(1, U().call(stocked, "getContainer"))
    local playerInventory, wifeInventory = U().inventory(player), U().inventory(wife)
    if not offered or not stocked or not offerSource or not stockSource
        or not playerInventory or not wifeInventory then
        return false, "slot_goods_missing"
    end
    if not U().transferItemVerified(offerSource, wifeInventory, offered) then
        return false, "slot_payment_transfer_failed"
    end
    if not U().transferItemVerified(stockSource, playerInventory, stocked) then
        U().transferItemVerified(wifeInventory, offerSource, offered)
        return false, "slot_reward_transfer_failed"
    end
    value.trades = value.trades + 1
    if value.trades == MAX_TRADES then
        value.stage = "quiet"
        U().say(wife, "Fair trade. Now go away.")
    else
        U().say(wife, "Fair trade. Now go away.")
    end
    return true, value.stage == "quiet"
        and "slot_falls_silent" or "slot_trade_completed"
end

return Lester
