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
local square = { getZ = function() return 0 end }
function companion:getSquare() return square end
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
function player:getSquare() return square end
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
SurvivorCompanion.Registry = {
    snapshot = function()
        return { { id = "transfer-companion", actor = companion, recruited = true } }
    end,
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
    -- A lit candle or hurricane lantern arrives as a new unlit item, and the
    -- lit original is removed from the destination as well.
    if item.unlit then
        local unlit = item.unlit
        unlit.container = destination
        destination.items[#destination.items + 1] = unlit
        remove(destination, item)
        item.container = nil
        return unlit
    end
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

local function newItem(container)
    local item = { container = container }
    function item:getContainer() return self.container end
    if container then container.items[#container.items + 1] = item end
    return item
end

-- A lit lantern carried as the companion's light leaves no copy behind.
local lantern = newItem(companionInventory)
lantern.unlit = newItem(nil)
companion.secondary = lantern
local unlit = ISTransferAction:transferItem(player, lantern,
    companionInventory, playerInventory)
assert(unlit == lantern.unlit and contains(playerInventory, unlit))
assert(not contains(companionInventory, lantern) and not contains(playerInventory, lantern))
assert(companion.secondary == nil, "companion still holds the lit lantern that was replaced")

-- Another mod wraps the transfer after us. Teardown must not cut it out of the
-- chain, and must not refuse: our wrapper stays in it as a pass-through.
local ours = ISTransferAction.transferItem
local foreignCalls = 0
local foreign = function(self, ...)
    foreignCalls = foreignCalls + 1
    return ours(self, ...)
end
ISTransferAction.transferItem = foreign
local removed, removedReason = bridge.removeTransferHook()
assert(removed == true, tostring(removedReason))
assert(ISTransferAction.transferItem == foreign, "teardown cut the other mod out of the chain")
assert(bridge.transferHookState() == false, "the left-behind wrapper is still active")
local axe = newItem(companionInventory)
companion.primary = axe
ISTransferAction:transferItem(player, axe, companionInventory, playerInventory)
assert(foreignCalls == 1 and contains(playerInventory, axe), "the chain stopped moving items")
assert(companion.primary == axe, "an inert wrapper still changed the companion")

-- Opening the inventory again switches the same wrapper back on, without a
-- second layer.
opened, reason = bridge.openInventory(companion, player)
assert(opened == true, tostring(reason))
assert(ISTransferAction.transferItem == foreign and bridge.transferHookState() == true)
local knife = newItem(companionInventory)
companion.primary = knife
ISTransferAction:transferItem(player, knife, companionInventory, playerInventory)
assert(foreignCalls == 2 and companion.primary == nil,
    "the reactivated wrapper did not release the knife")

local gifts = {}
SurvivorCompanion.Logistics = {
    noteGift = function(actor, item)
        assert(actor == companion)
        gifts[#gifts + 1] = item
    end,
    equipExactWearable = function(actor, item)
        assert(actor == companion)
        return true, item
    end,
}
SurvivorCompanion.Combat = {
    equipExactWeapon = function(actor, item)
        assert(actor == companion)
        return true, item
    end,
}
local crowbar = newItem(playerInventory)
function crowbar:getCategory() return "Weapon" end
ISTransferAction:transferItem(player, crowbar, playerInventory, companionInventory)
assert(gifts[#gifts] == crowbar and crowbar.container == companionInventory,
    "confirmed gift to companion root did not request a loadout review")
local bag = newItem(companionInventory)
local bagInventory = { items = {}, containingItem = bag }
function bagInventory:getContainingItem() return self.containingItem end
local shoulderPads = newItem(playerInventory)
function shoulderPads:IsClothing() return true end
function shoulderPads:getBodyLocation() return "TorsoExtra" end
ISTransferAction:transferItem(player, shoulderPads, playerInventory, bagInventory)
assert(gifts[#gifts] == shoulderPads and shoulderPads.container == bagInventory,
    "confirmed gift to a nested companion bag did not request a loadout review")
assert(bridge.ownerOfContainer(bagInventory) == companion)
local wearOk, wearItem = bridge.equipOnCompanion(companion, shoulderPads,
    player, "wear")
assert(wearOk == true and wearItem == shoulderPads,
    "explicit Wear did not target the exact nested item")
local weaponOk, weaponItem = bridge.equipOnCompanion(companion, crowbar,
    player, "weapon")
assert(weaponOk == true and weaponItem == crowbar,
    "explicit Equip did not target the exact weapon")
local stranger = newItem(otherInventory)
assert(bridge.equipOnCompanion(companion, stranger, player, "weapon") == false,
    "explicit Equip accepted an item the companion does not own")

getSpecificPlayer = function(index) assert(index == 0) return player end
local vanillaEquip = function() end
local vanillaWear = function() end
local vanillaClothingExtra = function() end
ISInventoryPaneContextMenu = {
    OnPrimaryWeapon = vanillaEquip, onWearItems = vanillaWear,
    onClothingItemExtra = vanillaClothingExtra,
}
local function menuWithVanilla(optionName, callback)
    local menu = { options = { { name = optionName, onSelect = callback } } }
    function menu:addOption(name, target, onSelect)
        local option = { name = name, target = target, onSelect = onSelect }
        self.options[#self.options + 1] = option
        return option
    end
    function menu:removeOptionByName(name)
        for index, option in ipairs(self.options) do
            if option.name == name then table.remove(self.options, index) return end
        end
    end
    return menu
end
local weaponMenu = menuWithVanilla("Equip primary", vanillaEquip)
bridge.fillInventoryContextMenu(0, weaponMenu, { crowbar })
assert(#weaponMenu.options == 1 and weaponMenu.options[1].target == crowbar
        and weaponMenu.options[1].name == "Equip on Companion",
    "companion inventory menu kept a player-targeted weapon action")
local armorMenu = menuWithVanilla("Wear", vanillaWear)
bridge.fillInventoryContextMenu(0, armorMenu, { shoulderPads })
assert(#armorMenu.options == 1 and armorMenu.options[1].target == shoulderPads
        and armorMenu.options[1].name == "Wear on Companion",
    "companion inventory menu kept player-targeted Wear or lost nested armor")
local variantMenu = menuWithVanilla("Wear", nil)
variantMenu.options[1].subOption = 1
function variantMenu:getSubMenu(index)
    assert(index == 1)
    return { options = { { name = "Wear up", onSelect = vanillaClothingExtra } } }
end
bridge.fillInventoryContextMenu(0, variantMenu, { shoulderPads })
assert(#variantMenu.options == 1
        and variantMenu.options[1].name == "Wear on Companion",
    "companion inventory menu kept vanilla player-targeted variant Wear submenu")

-- With the other mod gone, teardown restores the vanilla function.
ISTransferAction.transferItem = ours
removed = bridge.removeTransferHook()
assert(removed == true and ISTransferAction.transferItem == original)
SC_TEST_REPORT = "Companion inventory transfer: equipped item removal, root/bag gifts, exact Equip/Wear and foreign wrapper chain"
