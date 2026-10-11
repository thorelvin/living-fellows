-- SPDX-License-Identifier: MIT

-- A rare, voluntary camp gift. The offered item is a real inventory object
-- held by the companion until the player accepts its exact transfer.
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
if not SC.GameplayUtil and type(require) == "function" then pcall(require, "SCGameplayUtil") end

SC.CompanionGifts = SC.CompanionGifts or {}
local Gifts = SC.CompanionGifts
local pending = nil

local giftTypes = {
    "Base.ToyBear", "Base.CannedPeaches", "Base.Chocolate",
    "Base.Bandage", "Base.Bullets9mmBox", "Base.ShotgunShellsBox",
}
local allowed = {}
for _, kind in ipairs(giftTypes) do allowed[kind] = true end

local function U() return SC.GameplayUtil end

local function worldDay()
    if type(getGameTime) ~= "function" then return nil end
    local ok, gameTime = pcall(getGameTime)
    if not ok or gameTime == nil then return nil end
    local hours, available = U().call(gameTime, "getWorldAgeHours")
    hours = available and tonumber(hours) or nil
    return hours and math.floor(hours / 24) or nil
end

local function noDanger(actor)
    local senses = SC.Senses
    local snapshot = senses and type(senses.cached) == "function"
        and senses.cached(actor) or nil
    if type(snapshot) ~= "table" then return false end
    if (tonumber(snapshot.threatCount) or 0) > 0
        or (tonumber(snapshot.immediateCount) or 0) > 0
        or (tonumber(snapshot.pressure) or 0) > 0 then return false end
    local player = snapshot.player
    return type(player) ~= "table" or (tonumber(player.danger) or 0) <= 0
end

local function playerReady(player)
    if not U().isValidActor(player) then return false end
    if select(1, U().call(player, "getVehicle")) ~= nil
        or select(1, U().call(player, "isAsleep")) == true
        or select(1, U().call(player, "isAiming")) == true then return false end
    if type(ISTimedActionQueue) == "table"
        and type(ISTimedActionQueue.isPlayerDoingAction) == "function" then
        local ok, busy = pcall(ISTimedActionQueue.isPlayerDoingAction, player)
        if ok and busy == true then return false end
    end
    return true
end

local function nearbyAtBase(actor, player, maximum)
    if not U().isValidActor(actor) or not playerReady(player)
        or not U().sameFloor(actor, player)
        or U().distance(actor, player) > maximum then return false end
    return SC.BaseLife and type(SC.BaseLife.isInside) == "function"
        and SC.BaseLife.isInside(actor) == true
        and SC.BaseLife.isInside(player) == true
end

local function sourceOf(item, actor)
    local container = select(1, U().call(item, "getContainer"))
    if not container or U().containerContainsIdentity(container, item) ~= true then
        return nil
    end
    local root = U().inventory(actor)
    local current, visited = container, {}
    for _ = 1, 12 do
        if current == root then return container end
        if current == nil or visited[current] then return nil end
        visited[current] = true
        local holder = select(1, U().call(current, "getContainingItem"))
        if not holder then return nil end
        local parent = select(1, U().call(holder, "getContainer"))
        if not parent or U().containerContainsIdentity(parent, holder) ~= true then
            return nil
        end
        current = parent
    end
    return nil
end

local function stillGiftable(actor, item)
    if not allowed[U().itemType(item)]
        or select(1, U().call(item, "isFavorite")) == true
        or select(1, U().call(actor, "getPrimaryHandItem")) == item
        or select(1, U().call(actor, "getSecondaryHandItem")) == item
        or select(1, U().call(actor, "isEquippedClothing", item)) == true then
        return false
    end
    local data = select(1, U().call(item, "getModData"))
    return type(data) ~= "table" or (data.SC_GivenByPlayer ~= true
        and data.SC_PersonalOwnerId == nil)
end

local function giftItem(actor, day)
    local inventory = U().inventory(actor)
    if not inventory then return nil end
    local choices = {}
    local primary = select(1, U().call(actor, "getPrimaryHandItem"))
    local secondary = select(1, U().call(actor, "getSecondaryHandItem"))
    for _, item in ipairs(U().inventoryItemsDeep(inventory, 240)) do
        if item ~= primary and item ~= secondary and allowed[U().itemType(item)]
            and select(1, U().call(item, "isFavorite")) ~= true
            and select(1, U().call(actor, "isEquippedClothing", item)) ~= true then
            local data = select(1, U().call(item, "getModData"))
            if type(data) ~= "table"
                or (data.SC_GivenByPlayer ~= true
                    and data.SC_PersonalOwnerId == nil) then
                if sourceOf(item, actor) then choices[#choices + 1] = item end
            end
        end
    end
    local hash = U().stableHash(tostring(U().idOf(actor)) .. ":gift:" .. day)
    if #choices > 0 then return choices[(hash % #choices) + 1] end
    -- A companion can set aside a small find even if their current pockets
    -- contain only work gear. It is created once, in their own inventory.
    local kind = giftTypes[(hash % #giftTypes) + 1]
    return U().addItem(inventory, kind)
end

local function eligible(record, player, day)
    local actor = type(record) == "table" and record.actor or nil
    if not actor or record.recruited ~= true or not nearbyAtBase(actor, player, 12)
        or not noDanger(actor) then return nil end
    if not SC.Commands or type(SC.Commands.peek) ~= "function" then return nil end
    local state = SC.Commands.peek(actor)
    if type(state) ~= "table" or state.recruited ~= true
        or (state.order ~= "base_duty" and state.order ~= "follow") then return nil end
    if not SC.Relationship or type(SC.Relationship.score) ~= "function"
        or SC.Relationship.score(state) < 70
        or (tonumber(state.trust) or 0) < 65
        or (tonumber(state.bond) or 0) < 65 then return nil end
    local care = type(state.care) == "table" and state.care or {}
    if day - (tonumber(care.lastSocialGiftDay) or -1000) < 14 then return nil end
    if SC.BaseLife and type(SC.BaseLife.jobFor) == "function"
        and SC.BaseLife.jobFor(record.id) ~= nil then return nil end
    if SC.ActionSupervisor and type(SC.ActionSupervisor.current) == "function"
        and SC.ActionSupervisor.current(actor) ~= nil then return nil end
    if type(SC.Commands.isTemporaryStay) == "function"
        and SC.Commands.isTemporaryStay(actor) == true then return nil end
    if not SC.Positioning or type(SC.Positioning.activeConversation) ~= "function"
        or SC.Positioning.activeConversation(actor) ~= nil then return nil end
    if SC.Dialogue and type(SC.Dialogue.lastSpokenAt) == "function"
        and U().nowMs() - SC.Dialogue.lastSpokenAt(actor) < 15000 then return nil end
    return state
end

local function clearOffer(reason, spoken)
    local offer = pending
    pending = nil
    if SC.UI and type(SC.UI.closeGiftOffer) == "function" then
        SC.UI.closeGiftOffer()
    end
    if offer and offer.stayToken and SC.Commands
        and type(SC.Commands.endTemporaryStay) == "function" then
        SC.Commands.endTemporaryStay(offer.actor, offer.stayToken)
    end
    if spoken and offer and U().isValidActor(offer.actor)
        and SC.Dialogue and type(SC.Dialogue.say) == "function" then
        SC.Dialogue.say(offer.actor, "gift.declined")
    end
    return true, reason
end

function Gifts.current()
    return pending and pending.phase == "offered" and pending or nil
end

function Gifts.accept(actor, player)
    local offer = Gifts.current()
    if not offer or offer.actor ~= actor or offer.player ~= player then
        return false, "gift_offer_unavailable"
    end
    if not nearbyAtBase(actor, player, 4) or not noDanger(actor) then
        return false, "gift_offer_no_longer_safe"
    end
    local source = sourceOf(offer.item, actor)
    if not source or not stillGiftable(actor, offer.item) then
        clearOffer("gift_item_missing", false)
        return false, "gift_item_missing"
    end
    local destination = U().inventory(player)
    if not destination then return false, "player_inventory_unavailable" end
    local moved, reason = U().transferItemVerified(source, destination, offer.item)
    if not moved then return false, reason end
    clearOffer("gift_accepted", false)
    if SC.Dialogue and type(SC.Dialogue.say) == "function" then
        SC.Dialogue.say(actor, "gift.accepted")
    end
    return true, "gift_accepted", offer.item
end

function Gifts.decline(actor, player)
    local offer = Gifts.current()
    if not offer or offer.actor ~= actor or offer.player ~= player then
        return false, "gift_offer_unavailable"
    end
    return clearOffer("gift_declined", nearbyAtBase(actor, player, 4))
end

local function beginOffer(record, player, day, state)
    local actor = record.actor
    if not SC.Positioning or type(SC.Positioning.beginConversation) ~= "function"
        or not SC.UI or type(SC.UI.openGiftOffer) ~= "function"
        or type(SC.UI.canOpenGiftOffer) ~= "function"
        or not SC.Commands or type(SC.Commands.beginTemporaryStay) ~= "function"
        or not SC.UI.canOpenGiftOffer() then return false, "gift_ui_unavailable" end
    local offer = { actor = actor, player = player, day = day,
        phase = "approaching", expires = U().nowMs() + 30000 }
    pending = offer
    local accepted, reason = SC.Positioning.beginConversation(actor, player, {
        action = "social_gift", emote = "thankyou", timeoutMs = 30000,
        onCancel = function()
            if pending == offer and offer.phase == "approaching" then pending = nil end
        end,
        onReady = function()
            if pending ~= offer or not nearbyAtBase(actor, player, 3)
                or not noDanger(actor) or not SC.UI.canOpenGiftOffer() then
                pending = nil
                return false
            end
            local token, holdReason = SC.Commands.beginTemporaryStay(actor, "companion_gift")
            if type(token) ~= "table" or holdReason == "already_held" then
                pending = nil
                return false
            end
            offer.stayToken = token
            local item = giftItem(actor, day)
            if not item or not sourceOf(item, actor) then
                clearOffer("gift_item_unavailable", false)
                return false
            end
            offer.item, offer.phase = item, "offered"
            if SC.Dialogue and type(SC.Dialogue.say) == "function" then
                SC.Dialogue.say(actor, "gift.offer")
            end
            local opened = SC.UI.openGiftOffer(actor, item, player)
            if opened ~= true then
                clearOffer("gift_ui_unavailable", false)
                return false
            end
            state.care = type(state.care) == "table" and state.care or {}
            local previous = state.care.lastSocialGiftDay
            state.care.lastSocialGiftDay = day
            local saved = SC.Commands.persist(actor)
            if saved ~= true then
                state.care.lastSocialGiftDay = previous
                clearOffer("gift_persistence_unavailable", false)
                return false
            end
            local playerData = select(1, U().call(player, "getModData"))
            if type(playerData) == "table" then
                playerData.SC_LastSocialGiftDay = day
            end
            return true
        end,
    })
    if accepted ~= true then pending = nil end
    return accepted == true, reason
end

function Gifts.pulse(player, records)
    if pending then
        if pending.phase == "offered" then
            if not nearbyAtBase(pending.actor, pending.player, 4)
                or not noDanger(pending.actor)
                or not sourceOf(pending.item, pending.actor)
                or not stillGiftable(pending.actor, pending.item) then
                clearOffer("gift_offer_interrupted", false)
            end
        elseif U().nowMs() >= (pending.expires or 0)
            or not nearbyAtBase(pending.actor, pending.player, 16) then
            if SC.Positioning and type(SC.Positioning.cancelConversation) == "function" then
                SC.Positioning.cancelConversation(pending.actor, "gift_approach_expired")
            end
            pending = nil
        end
        return false, "gift_pending"
    end
    local day = worldDay()
    if day == nil or not playerReady(player) then return false, "gift_not_ready" end
    local playerData = select(1, U().call(player, "getModData"))
    if type(playerData) ~= "table"
        or day - (tonumber(playerData.SC_LastSocialGiftDay) or -1000) < 7
        or not SC.BaseLife or SC.BaseLife.isInside(player) ~= true then
        return false, "gift_cooldown_or_outside_base"
    end
    -- One opportunity for the whole party, about once every twelve game
    -- days; no reload reroll and no chorus from a large camp.
    local seed = U().stableHash(tostring(U().nameOf(player)) .. ":social-gift:" .. day)
    if seed % 12 ~= 0 then return false, "gift_not_rolled" end
    local candidates = {}
    for _, record in ipairs(records or {}) do
        local state = eligible(record, player, day)
        if state then candidates[#candidates + 1] = { record = record, state = state } end
    end
    if #candidates == 0 then return false, "gift_no_available_companion" end
    table.sort(candidates, function(first, second)
        return tostring(first.record.id) < tostring(second.record.id)
    end)
    local selected = candidates[(seed % #candidates) + 1]
    return beginOffer(selected.record, player, day, selected.state)
end

function Gifts.reset()
    if pending and pending.phase == "approaching" and SC.Positioning
        and type(SC.Positioning.cancelConversation) == "function" then
        SC.Positioning.cancelConversation(pending.actor, "gift_world_reset")
    end
    clearOffer("gift_world_reset", false)
    return true
end

return Gifts
