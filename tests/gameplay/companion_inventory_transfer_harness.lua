-- SPDX-License-Identifier: MIT

local companionInventory = { items = {} }
local playerInventory = { items = {} }
local otherInventory = { items = {} }
local function contains(container, item)
    for _, candidate in ipairs(container.items) do
        if candidate == item then return true end
    end
    return false
end
local function remove(container, item)
    for index, candidate in ipairs(container.items) do
        if candidate == item then table.remove(container.items, index) return end
    end
end

local companion = { inventory = companionInventory }
function companion:getSquare() return {} end
function companion:isDead() return false end
function companion:getInventory() return self.inventory end
function companion:getPrimaryHandItem() return self.primary end
function companion:getSecondaryHandItem() return self.secondary end
function companion:setPrimaryHandItem(item) self.primary = item end
function companion:setSecondaryHandItem(item) self.secondary = item end
function companion:removeAttachedItem(item) self.detached = item end
function companion:isEquippedClothing() return false end
function companion:resetModelNextFrame() self.modelReset = true end

local player = { inventory = playerInventory }
function player:DistTo() return 1 end
function player:getPlayerNum() return 0 end
function player:removeFromHands(item)
    if self.primary == item then self.primary = nil end
end

local lootPage = { inventoryPane = { inventory = otherInventory }, visible = false }
function lootPage:setNewContainer(container) self.inventoryPane.inventory = container end
function lootPage:setVisible(visible) self.visible = visible end
function lootPage:getIsVisible() return self.visible end
function lootPage:bringToTop() end
getPlayerLoot = function() return lootPage end

SurvivorCompanion = SurvivorCompanion or {}
SurvivorCompanion.Actor = {
    isCompanion = function(actor) return actor == companion end,
}
SurvivorCompanion.GameplayUtil = { inventoryContains = contains }
SurvivorCompanion.InventoryIndex = {
    touch = function(actor) actor.indexTouched = true end,
}

-- Vanilla's transfer receives the player as `character`. It removes a source
-- item but only unequips that player; the companion hand is left dangling.
ISTransferAction = {}
function ISTransferAction:transferItem(character, item, source, destination)
    remove(source, item)
    destination.items[#destination.items + 1] = item
    item.container = destination
    character:removeFromHands(item)
    return item
end

local original = ISTransferAction.transferItem
local bridge = SurvivorCompanion.UIBridge
local opened, reason = bridge.openInventory(companion, player)
assert(opened == true, tostring(reason))

local hammer = { container = companionInventory }
function hammer:getContainer() return self.container end
companionInventory.items[1] = hammer
companion.primary, companion.secondary = hammer, hammer
local result = ISTransferAction:transferItem(player, hammer,
    companionInventory, playerInventory)
assert(result == hammer and contains(playerInventory, hammer))
assert(not contains(companionInventory, hammer))
assert(companion.primary == nil and companion.secondary == nil)
assert(companion.modelReset == true and companion.indexTouched == true)

local second = { container = otherInventory }
function second:getContainer() return self.container end
otherInventory.items[1] = second
companion.primary = second
ISTransferAction:transferItem(player, second, otherInventory, playerInventory)
assert(companion.primary == second, "unrelated transfer changed companion")

local removed = bridge.removeTransferHook()
assert(removed == true and ISTransferAction.transferItem == original)
SC_TEST_REPORT = "Companion inventory transfer: wielded hammer moves once and clears both hands"
