-- SPDX-License-Identifier: MIT

local gifts = SurvivorCompanion.CompanionGifts
local clock, day = 100000, 30
local function inventory()
    local result = { items = {} }
    function result:contains(item)
        for _, value in ipairs(self.items) do if value == item then return true end end
        return false
    end
    return result
end
local actor = { id = "gift-companion", inventory = inventory(), data = {} }
local player = { id = "gift-player", inventory = inventory(), data = {} }
function actor:getInventory() return self.inventory end
function actor:getModData() return self.data end
function actor:getPrimaryHandItem() return nil end
function actor:getSecondaryHandItem() return nil end
function actor:isEquippedClothing() return false end
function player:getInventory() return self.inventory end
function player:getModData() return self.data end
function player:getVehicle() return nil end
function player:isAsleep() return false end
function player:isAiming() return false end
getGameTime = function()
    return { getWorldAgeHours = function() return day * 24 end }
end

local state = { recruited = true, order = "base_duty", trust = 85,
    bond = 85, care = {} }
local speech, dialog, conversation, held = {}, nil, nil, nil
SurvivorCompanion.GameplayUtil = {
    isValidActor = function(value) return value == actor or value == player end,
    call = function(value, name, ...)
        local method = value and value[name]
        if type(method) ~= "function" then return nil, false end
        local ok, result = pcall(method, value, ...)
        return result, ok
    end,
    sameFloor = function() return true end,
    distance = function() return 2 end,
    nowMs = function() return clock end,
    stableHash = function() return 0 end,
    nameOf = function() return "Player" end,
    idOf = function(value) return value.id end,
    inventory = function(value) return value.inventory end,
    inventoryItemsDeep = function(value) return value.items end,
    itemType = function(value) return value.fullType end,
    itemName = function(value) return value.fullType end,
    containerContainsIdentity = function(container, item) return container:contains(item) end,
    addItem = function(container, fullType)
        local value = { fullType = fullType, container = container, data = {} }
        function value:getContainer() return self.container end
        function value:getModData() return self.data end
        function value:isFavorite() return false end
        container.items[#container.items + 1] = value
        return value
    end,
    transferItemVerified = function(source, destination, item)
        if not source:contains(item) then return false, "source_missing" end
        for index, value in ipairs(source.items) do
            if value == item then table.remove(source.items, index) break end
        end
        destination.items[#destination.items + 1] = item
        item.container = destination
        return true, "transferred"
    end,
}
SurvivorCompanion.BaseLife = {
    isInside = function() return true end,
    jobFor = function() return nil end,
}
SurvivorCompanion.Senses = { cached = function()
    return { threatCount = 0, immediateCount = 0, pressure = 0,
        player = { danger = 0 } }
end }
SurvivorCompanion.Relationship = { score = function() return 85 end }
SurvivorCompanion.Commands = {
    peek = function() return state end,
    persist = function() return true end,
    isTemporaryStay = function() return held ~= nil end,
    beginTemporaryStay = function()
        assert(held == nil, "gift tried to replace an existing hold")
        held = { reason = "companion_gift" }
        return held, "temporary_stay"
    end,
    endTemporaryStay = function(_, token)
        assert(token == held, "gift released a different hold")
        held = nil
        return true
    end,
}
SurvivorCompanion.Positioning = {
    activeConversation = function() return conversation end,
    beginConversation = function(_, _, options)
        conversation = options
        return true, "conversation_staged"
    end,
    cancelConversation = function(_, reason)
        local old = conversation
        conversation = nil
        if old and old.onCancel then old.onCancel(reason) end
    end,
}
SurvivorCompanion.UI = {
    canOpenGiftOffer = function() return dialog == nil end,
    openGiftOffer = function(_, item)
        dialog = item
        return true
    end,
    closeGiftOffer = function() dialog = nil end,
}
SurvivorCompanion.Dialogue = {
    lastSpokenAt = function() return -math.huge end,
    say = function(_, topic)
        speech[#speech + 1] = topic
        return true
    end,
}

local record = { id = actor.id, actor = actor, recruited = true }
local started = gifts.pulse(player, { record })
assert(started == true and conversation ~= nil and #actor.inventory.items == 0,
    "rare camp offer did not stage a real approach before creating an item")
assert(conversation.onReady() == true and gifts.current() ~= nil and dialog ~= nil,
    "arrival did not open the centered gift offer")
local item = gifts.current().item
assert(actor.inventory:contains(item) and not player.inventory:contains(item)
    and speech[#speech] == "gift.offer" and state.care.lastSocialGiftDay == day
    and held ~= nil,
    "offered item left the companion before acceptance or did not persist cooldown")
local accepted = gifts.accept(actor, player)
assert(accepted == true and player.inventory:contains(item)
    and not actor.inventory:contains(item) and dialog == nil and held == nil,
    "accept did not transfer the exact item once")
assert(gifts.pulse(player, { record }) == false,
    "another gift appeared on the same day")

day = day + 21
conversation = nil
local second = gifts.pulse(player, { record })
assert(second == true and conversation.onReady() == true,
    "a later rare opportunity did not stage a second offer")
local declinedItem = gifts.current().item
assert(gifts.decline(actor, player) == true
    and actor.inventory:contains(declinedItem)
    and not player.inventory:contains(declinedItem) and dialog == nil and held == nil,
    "declining a gift did not leave the exact item with its owner")
gifts.reset()
SC_TEST_REPORT = "Companion gifts: rare stable offer, staged approach, exact acceptance, decline retention and cooldown"
