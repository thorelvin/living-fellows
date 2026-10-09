-- SPDX-License-Identifier: MIT

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion

SC.UIBridge = SC.UIBridge or {}
local Bridge = SC.UIBridge

Bridge.NEARBY_DISTANCE = 4
Bridge.AUTO_INVENTORY_TILES = 1
-- Opening a companion's read-only health/loadout view does not borrow the loot
-- pane (only the explicit Open Inventory action does), so it must not be gated to
-- the same arm's-reach distance as inventory. The context menu already only offers
-- it for companions within ~16 tiles; this generous bound keeps a sane "loaded and
-- with you" limit while letting a normally-following companion's health open.
Bridge.VIEW_DISTANCE = 64

-- When we borrow the local player's loot pane to show a companion's inventory we
-- must be able to put it back exactly as it was. Single-player, so one snapshot:
-- { page, playerNum, container, visible, collapsed, collapseCounter, ourContainer,
--   heldActor, stayToken }.
-- ourContainer is the companion inventory we set, so a restore only reverts the
-- pane while it still shows what we put there (never clobbers a container the
-- player deliberately selected afterwards).
local ownedLootPane = nil
local transferOwners = setmetatable({}, { __mode = "kv" })
local originalTransferItem, transferItemWrapper
local transferHookActive = false
local inventoryMenuInstalled = false
local nearbySignatures = setmetatable({}, { __mode = "k" })

function Bridge.invalidateNearbyInventoryLabels()
    nearbySignatures = setmetatable({}, { __mode = "k" })
end

local function safeMethod(object, methodName, ...)
    if not object then
        return nil
    end
    local method = object[methodName]
    if type(method) ~= "function" then
        return nil
    end
    local ok, value, second = pcall(method, object, ...)
    if not ok then
        return nil
    end
    return value, second
end

local function failure(key, argument)
    return false, key, argument
end

local function companionId(actor)
    local modData = safeMethod(actor, "getModData")
    if type(modData) ~= "table" then
        return nil
    end
    local id = modData.SC_Id
    if id == nil or id == "" then
        return nil
    end
    return tostring(id)
end

local function recruitedActor(actor)
    if not actor or not SC.Actor or type(SC.Actor.isCompanion) ~= "function" then
        return false
    end
    local valid, isCompanion = pcall(SC.Actor.isCompanion, actor)
    if not valid or isCompanion ~= true then return false end
    if SC.Commands and type(SC.Commands.peek) == "function" then
        local record = SC.Commands.peek(actor)
        if type(record) == "table" then return record.recruited == true end
    end
    if SC.Registry and type(SC.Registry.snapshot) == "function" then
        for _, record in ipairs(SC.Registry.snapshot()) do
            if record.actor == actor then return record.recruited == true end
        end
    end
    return false
end

-- InventoryItem:getContainer() points to its immediate bag. Walk containing
-- items back to a recruited companion's root instead of treating bag gifts as
-- world-container transfers. Only exact, currently owned roots are trusted.
function Bridge.ownerOfContainer(container)
    local visited = {}
    local current = container
    for _ = 1, 12 do
        if not current or visited[current] then break end
        visited[current] = true
        local owner = transferOwners[current]
        if owner and safeMethod(owner, "getInventory") == current
            and recruitedActor(owner) then return owner end
        local containingItem = safeMethod(current, "getContainingItem")
        if not containingItem then
            local parent = safeMethod(current, "getParent")
            if parent and safeMethod(parent, "getContainer") then
                containingItem = parent
            end
        end
        current = containingItem and safeMethod(containingItem, "getContainer") or nil
    end
    if SC.Registry and type(SC.Registry.snapshot) == "function" then
        for _, record in ipairs(SC.Registry.snapshot()) do
            if record.recruited == true and record.actor
                and recruitedActor(record.actor) then
                local root = safeMethod(record.actor, "getInventory")
                if root and visited[root] then
                    transferOwners[root] = record.actor
                    return record.actor
                end
            end
        end
    end
    return nil
end

-- The stock transfer action is run by the player, even when its source is a
-- companion's borrowed inventory. Vanilla therefore unequips the player, not
-- the companion. A weapon left in the companion's hand after being taken can
-- be captured as a new inventory root on save and appear duplicated on reload.
local function releaseTransferredEquipment(actor, item)
    if not actor or not item then return end
    local changed = false
    if safeMethod(actor, "getPrimaryHandItem") == item then
        safeMethod(actor, "setPrimaryHandItem", nil)
        changed = true
    end
    if safeMethod(actor, "getSecondaryHandItem") == item then
        safeMethod(actor, "setSecondaryHandItem", nil)
        changed = true
    end
    safeMethod(actor, "removeAttachedItem", item)
    if safeMethod(actor, "isEquippedClothing", item) == true then
        safeMethod(actor, "removeWornItem", item, false)
        changed = true
        if type(triggerEvent) == "function" then
            pcall(triggerEvent, "OnClothingUpdated", actor)
        end
    end
    if changed then safeMethod(actor, "resetModelNextFrame") end
    local data = safeMethod(item, "hasModData") == true
        and safeMethod(item, "getModData") or nil
    if type(data) == "table" then
        local id = companionId(actor)
        if data.SC_ManualEquipFor == id then data.SC_ManualEquipFor = nil end
        if data.SC_ManualWearFor == id then data.SC_ManualWearFor = nil end
    end
    if SC.InventoryIndex and type(SC.InventoryIndex.touch) == "function" then
        SC.InventoryIndex.touch(actor)
    end
end

local function installInventoryMenu()
    if inventoryMenuInstalled then return end
    if Events and Events.OnFillInventoryObjectContextMenu then
        Events.OnFillInventoryObjectContextMenu.Add(Bridge.fillInventoryContextMenu)
        inventoryMenuInstalled = true
    end
end

local function holds(container, item)
    if SC.GameplayUtil and type(SC.GameplayUtil.inventoryContains) == "function" then
        return SC.GameplayUtil.inventoryContains(container, item) == true
    end
    return safeMethod(container, "contains", item) == true
end

-- Vanilla hands a lit candle or hurricane lantern over as a new unlit item and
-- removes the lit original from both containers, so the original is in
-- neither and only the returned replacement proves the move happened.
local function leftSource(item, result, source, destination)
    if safeMethod(item, "getContainer") == destination then return true end
    if holds(source, item) then return false end
    if holds(destination, item) then return true end
    return result ~= nil and result ~= item
        and (safeMethod(result, "getContainer") == destination
            or holds(destination, result))
end

function Bridge.installTransferHook()
    if originalTransferItem ~= nil then
        transferHookActive = true
        installInventoryMenu()
        return true
    end
    if type(ISTransferAction) ~= "table" and type(require) == "function" then
        pcall(require, "TimedActions/ISTransferAction")
    end
    if type(ISTransferAction) ~= "table"
        or type(ISTransferAction.transferItem) ~= "function" then
        return false, "vanilla transfer action unavailable"
    end
    originalTransferItem = ISTransferAction.transferItem
    transferItemWrapper = function(self, character, item, source, destination, ...)
        local result = originalTransferItem(self, character, item,
            source, destination, ...)
        if not transferHookActive then return result end
        local repaired, repairReason = pcall(function()
            local owner = Bridge.ownerOfContainer(source)
            if owner and item and destination and source ~= destination
                and leftSource(item, result, source, destination) then
                releaseTransferredEquipment(owner, item)
            end
            local receiver = Bridge.ownerOfContainer(destination)
            if receiver and receiver ~= owner and source ~= destination then
                local received = item
                if not holds(destination, received)
                    and result ~= nil and result ~= item
                    and holds(destination, result) then received = result end
                if holds(destination, received) and not holds(source, item) then
                    if SC.InventoryIndex and type(SC.InventoryIndex.touch) == "function" then
                        SC.InventoryIndex.touch(receiver)
                    end
                    if SC.Logistics and type(SC.Logistics.noteGift) == "function" then
                        SC.Logistics.noteGift(receiver, received)
                    end
                end
            end
        end)
        if not repaired and SC.Diagnostics
            and type(SC.Diagnostics.report) == "function" then
            pcall(SC.Diagnostics.report, "inventory-transfer", nil,
                "companion equipment cleanup failed", repairReason)
        end
        return result
    end
    ISTransferAction.transferItem = transferItemWrapper
    transferHookActive = true
    installInventoryMenu()
    return true
end

function Bridge.transferHookState()
    return transferHookActive,
        originalTransferItem == nil or (type(ISTransferAction) == "table"
            and ISTransferAction.transferItem == transferItemWrapper)
end

function Bridge.removeTransferHook()
    transferOwners = setmetatable({}, { __mode = "kv" })
    nearbySignatures = setmetatable({}, { __mode = "k" })
    transferHookActive = false
    if inventoryMenuInstalled and Events and Events.OnFillInventoryObjectContextMenu then
        Events.OnFillInventoryObjectContextMenu.Remove(Bridge.fillInventoryContextMenu)
    end
    inventoryMenuInstalled = false
    if originalTransferItem == nil then return true end
    if type(ISTransferAction) == "table"
        and ISTransferAction.transferItem == transferItemWrapper then
        ISTransferAction.transferItem = originalTransferItem
        originalTransferItem, transferItemWrapper = nil, nil
        return true
    end
    -- Another mod wrapped the transfer after us and calls our wrapper from its
    -- own. Unwrapping would cut that mod out of the chain, so ours stays in it
    -- as a plain pass-through until the next install switches it back on.
    return true, "transfer hook left inert"
end

-- A nearby recruited companion is a loot-pane container, without borrowing
-- the pane or putting the companion on a temporary Stay order.
function Bridge.nearbyInventories(player)
    local result, ids = {}, {}
    local playerSquare = safeMethod(player, "getSquare")
    if not playerSquare or not SC.Registry
        or type(SC.Registry.snapshot) ~= "function" then return result, "" end
    local px = tonumber((safeMethod(playerSquare, "getX")))
    local py = tonumber((safeMethod(playerSquare, "getY")))
    local pz = tonumber((safeMethod(playerSquare, "getZ")))
    if not px or not py or not pz then return result, "" end
    for _, record in ipairs(SC.Registry.snapshot()) do
        local actor = record.actor
        if record.recruited == true and actor
            and not (type(record.runtime) == "table"
                and record.runtime.inactive == true) then
            local square = safeMethod(actor, "getSquare")
            local x = tonumber((safeMethod(square, "getX")))
            local y = tonumber((safeMethod(square, "getY")))
            local z = tonumber((safeMethod(square, "getZ")))
            if x and y and z == pz and math.abs(x - px) <= Bridge.AUTO_INVENTORY_TILES
                and math.abs(y - py) <= Bridge.AUTO_INVENTORY_TILES
                and safeMethod(actor, "isDead") ~= true then
                local container = safeMethod(actor, "getInventory")
                if container then
                    result[#result + 1] = { container = container, actor = actor }
                    ids[#ids + 1] = tostring(record.id)
                    transferOwners[container] = actor
                end
            end
        end
    end
    if #result > 0 and not Bridge.installTransferHook() then return {}, "" end
    return result, table.concat(ids, "|")
end

-- The vanilla pane only rebuilds when the player turns or changes squares.
-- Companions can enter or leave arm's reach while the player stands still.
function Bridge.refreshNearbyInventory(player)
    local playerNum = tonumber((safeMethod(player, "getPlayerNum")))
    if playerNum ~= 0 or type(getPlayerLoot) ~= "function" then return end
    local ok, page = pcall(getPlayerLoot, playerNum)
    if not ok or type(page) ~= "table"
        or type(page.refreshBackpacks) ~= "function" then return end
    local visible = safeMethod(page, "getIsVisible")
    if visible == nil then visible = safeMethod(page, "isVisible") end
    if visible == false then return end
    local _, signature = Bridge.nearbyInventories(player)
    if nearbySignatures[page] ~= signature then
        nearbySignatures[page] = signature
        page:refreshBackpacks()
    end
end

function Bridge.validateNearbyActor(actor, player, maximumDistance)
    if not actor or safeMethod(actor, "getSquare") == nil then
        return failure("UI_SC_Disabled_InvalidActor")
    end
    if safeMethod(actor, "isDead") == true then
        return failure("UI_SC_Disabled_NotAlive")
    end
    if SC.Actor and type(SC.Actor.isCompanion) == "function" then
        local ok, valid = pcall(SC.Actor.isCompanion, actor)
        if not ok or valid ~= true then
            return failure("UI_SC_Disabled_InvalidActor")
        end
    end
    if not player then
        return failure("UI_SC_Disabled_NoPlayer")
    end
    local limit = tonumber(maximumDistance) or Bridge.NEARBY_DISTANCE
    local distanceValue = safeMethod(player, "DistTo", actor)
    local distance = tonumber(distanceValue)
    if not distance or distance > limit then
        return failure("UI_SC_Disabled_TooFar", limit)
    end
    return true
end

function Bridge.equipOnCompanion(actor, item, player, kind)
    local valid, reason = Bridge.validateNearbyActor(actor, player,
        Bridge.NEARBY_DISTANCE)
    if not valid then return false, reason end
    if not recruitedActor(actor) then return false, "companion_not_recruited" end
    local actorSquare = safeMethod(actor, "getSquare")
    local playerSquare = safeMethod(player, "getSquare")
    if not actorSquare or not playerSquare
        or safeMethod(actorSquare, "getZ") ~= safeMethod(playerSquare, "getZ") then
        return false, "companion_on_other_floor"
    end
    local source = safeMethod(item, "getContainer")
    if not source or Bridge.ownerOfContainer(source) ~= actor then
        return false, "item_not_owned"
    end
    local equipped, equipReason
    if kind == "weapon" and SC.Combat
        and type(SC.Combat.equipExactWeapon) == "function" then
        equipped, equipReason = SC.Combat.equipExactWeapon(actor, item)
    elseif kind == "wear" and SC.Logistics
        and type(SC.Logistics.equipExactWearable) == "function" then
        equipped, equipReason = SC.Logistics.equipExactWearable(actor, item)
    else
        return false, "equip_action_unavailable"
    end
    if equipped and SC.InventoryIndex and type(SC.InventoryIndex.touch) == "function" then
        SC.InventoryIndex.touch(actor)
    end
    return equipped == true, equipReason
end

local function firstInventoryItem(entries)
    if type(entries) ~= "table" then return nil end
    for _, entry in ipairs(entries) do
        local item = entry
        if type(entry) == "table" and type(entry.items) == "table" then
            item = entry.items[1]
        end
        if item and safeMethod(item, "getContainer") then return item end
    end
    return nil
end

local function onEquipmentOption(item, actor, player, kind)
    local ok, equipped, reason = pcall(Bridge.equipOnCompanion,
        actor, item, player, kind)
    local message = ok and equipped
        and (Bridge.borrowedInventoryLabel(actor) .. " equipped "
            .. tostring(safeMethod(item, "getDisplayName") or "the item"))
        or ("Could not equip item: " .. tostring(ok and reason or equipped))
    safeMethod(player, "setHaloNote", message)
end

local function equipmentLabel(key, fallback, name)
    if type(getText) == "function" then
        local ok, translated = pcall(getText, key, name)
        if ok and type(translated) == "string" and translated ~= ""
            and translated ~= key then return translated end
    end
    return fallback .. " " .. name
end

local function removePlayerEquipOptions(context)
    local vanilla = ISInventoryPaneContextMenu
    if type(vanilla) ~= "table" or type(context.options) ~= "table"
        or type(context.removeOptionByName) ~= "function" then return end
    local callbacks = {}
    local function remember(callback)
        if type(callback) == "function" then callbacks[callback] = true end
    end
    remember(vanilla.onWearItems)
    remember(vanilla.onClothingItemExtra)
    remember(vanilla.OnPrimaryWeapon)
    remember(vanilla.OnSecondWeapon)
    remember(vanilla.OnTwoHandsEquip)
    local names = {}
    for _, option in ipairs(context.options) do
        local playerAction = option and option.onSelect and callbacks[option.onSelect]
        -- Variant clothing creates a callback-free "Wear" parent with the
        -- player-targeted clothing action in its submenu.
        if not playerAction and option and option.subOption
            and type(context.getSubMenu) == "function" then
            local ok, submenu = pcall(context.getSubMenu, context, option.subOption)
            if ok and submenu and type(submenu.options) == "table" then
                for _, child in ipairs(submenu.options) do
                    if child and child.onSelect == vanilla.onClothingItemExtra then
                        playerAction = true
                        break
                    end
                end
            end
        end
        if playerAction then
            names[#names + 1] = option.name
        end
    end
    for _, name in ipairs(names) do context:removeOptionByName(name) end
end

function Bridge.fillInventoryContextMenu(playerIndex, context, entries)
    if not context or type(context.addOption) ~= "function" then return end
    local item = firstInventoryItem(entries)
    if not item then return end
    local actor = Bridge.ownerOfContainer(safeMethod(item, "getContainer"))
    if not actor then return end
    local player = type(getSpecificPlayer) == "function"
        and getSpecificPlayer(playerIndex) or nil
    local valid = Bridge.validateNearbyActor(actor, player, Bridge.NEARBY_DISTANCE)
    if not valid then return end
    local actorSquare = safeMethod(actor, "getSquare")
    local playerSquare = safeMethod(player, "getSquare")
    if safeMethod(actorSquare, "getZ") ~= safeMethod(playerSquare, "getZ") then
        return
    end
    local name = Bridge.borrowedInventoryLabel(actor)
    local category = safeMethod(item, "getCategory")
    removePlayerEquipOptions(context)
    if tostring(category) == "Weapon" or (SC.GameplayUtil
        and type(SC.GameplayUtil.instanceOf) == "function"
        and SC.GameplayUtil.instanceOf(item, "HandWeapon")) then
        context:addOption(equipmentLabel("UI_SC_EquipOnCompanion",
            "Equip on", name), item,
            onEquipmentOption, actor, player, "weapon")
    end
    local clothing = safeMethod(item, "IsClothing") == true
        or tostring(category) == "Clothing"
    local bag = safeMethod(item, "getItemContainer")
        or safeMethod(item, "getInventory")
    local location = safeMethod(item, "getBodyLocation")
        or safeMethod(item, "canBeEquipped")
    if (clothing or bag) and location and tostring(location) ~= "" then
        context:addOption(equipmentLabel("UI_SC_WearOnCompanion",
            "Wear on", name), item,
            onEquipmentOption, actor, player, "wear")
    end
end

function Bridge.openInventory(actor, player)
    local valid, reason, argument = Bridge.validateNearbyActor(actor, player, Bridge.NEARBY_DISTANCE)
    if not valid then
        return false, reason, argument
    end
    local inventory = safeMethod(actor, "getInventory")
    if not inventory then
        return failure("UI_SC_Disabled_NoInventory")
    end
    local hooked, hookReason = Bridge.installTransferHook()
    if not hooked then return false, "UI_SC_Disabled_NoInventoryUI", hookReason end
    transferOwners[inventory] = actor
    local playerNumValue = safeMethod(player, "getPlayerNum")
    local playerNum = tonumber(playerNumValue)
    if playerNum == nil or type(getPlayerLoot) ~= "function" then
        return failure("UI_SC_Disabled_NoInventoryUI")
    end
    local okPage, lootPage = pcall(getPlayerLoot, playerNum)
    if not okPage or not lootPage or type(lootPage.setNewContainer) ~= "function" or type(lootPage.setVisible) ~= "function" then
        return failure("UI_SC_Disabled_NoInventoryUI")
    end
    local priorActor = ownedLootPane and ownedLootPane.heldActor or nil
    if priorActor ~= nil and priorActor ~= actor and SC.Commands
        and type(SC.Commands.endTemporaryStay) == "function" then
        pcall(SC.Commands.endTemporaryStay, priorActor, ownedLootPane.stayToken)
        ownedLootPane.heldActor, ownedLootPane.stayToken = nil, nil
    end
    local stayToken = ownedLootPane and ownedLootPane.heldActor == actor
        and ownedLootPane.stayToken or nil
    if stayToken == nil and SC.Commands
        and type(SC.Commands.beginTemporaryStay) == "function" then
        local okStay, value = pcall(SC.Commands.beginTemporaryStay,
            actor, "companion_inventory")
        if not okStay or type(value) ~= "table" then
            return failure("UI_SC_Disabled_NoInventoryUI")
        end
        stayToken = value
    end
    -- Snapshot the pane's prior state the first time we borrow it, so it can be
    -- restored later. If we already own it (switching companions), keep the
    -- original snapshot and just update which container is "ours".
    if ownedLootPane == nil then
        local priorVisible = safeMethod(lootPage, "getIsVisible")
        if priorVisible == nil then priorVisible = safeMethod(lootPage, "isVisible") end
        ownedLootPane = {
            page = lootPage,
            playerNum = playerNum,
            container = lootPage.inventoryPane and lootPage.inventoryPane.inventory or nil,
            visible = priorVisible,
            collapsed = lootPage.isCollapsed,
            collapseCounter = lootPage.collapseCounter,
            ourContainer = inventory,
            heldActor = actor,
            stayToken = stayToken,
        }
    else
        ownedLootPane.page = lootPage
        ownedLootPane.ourContainer = inventory
        ownedLootPane.heldActor = actor
        ownedLootPane.stayToken = stayToken
    end
    local shown = pcall(function()
        -- This mirrors vanilla B42 ISOpenContainerTimedAction on the existing
        -- player loot page, keeping transfer behavior inside the normal UI.
        lootPage:setNewContainer(inventory)
        lootPage:setVisible(true)
        lootPage.collapseCounter = 0
        if lootPage.isCollapsed then
            lootPage.isCollapsed = false
            if type(lootPage.clearMaxDrawHeight) == "function" then
                lootPage:clearMaxDrawHeight()
            end
            lootPage.collapseCounter = -40
        end
        if type(lootPage.bringToTop) == "function" then
            lootPage:bringToTop()
        end
    end)
    if not shown then
        Bridge.restoreInventory()
        return failure("UI_SC_Disabled_NoInventoryUI")
    end
    local selected = not lootPage.inventoryPane or lootPage.inventoryPane.inventory == inventory
    local visible = safeMethod(lootPage, "getIsVisible")
    if visible == nil then
        visible = safeMethod(lootPage, "isVisible")
    end
    if not selected or visible == false or lootPage.isCollapsed == true then
        Bridge.restoreInventory()
        return failure("UI_SC_Disabled_NoInventoryUI")
    end
    return true
end

-- The companion container this pane is showing on our behalf, and the companion
-- it belongs to.
--
-- Vanilla rebuilds the loot pane's container list every time the player turns
-- or steps to a new square, from the containers it can find in the world. A
-- companion is a moving character, not one of those, so the rebuild dropped
-- our container, `found` came out false, and the pane fell back to
-- `backpacks[1]` -- the floor. The window appeared to close itself, and an
-- item dragged over it landed on the ground, because turning to drag is
-- exactly what triggers the rebuild.
--
-- Read by the refresh hook so the companion can be put back into that list
-- like any other container.
function Bridge.borrowedInventory(page)
    local snap = ownedLootPane
    if snap == nil then return nil end
    if page ~= nil and snap.page ~= page then return nil end
    return snap.ourContainer, snap.heldActor
end

-- What to call the companion's container in the pane's button list.
function Bridge.borrowedInventoryLabel(actor)
    if SC.Names and type(SC.Names.displayName) == "function" then
        local show = true
        if SC.UI and type(SC.UI.getSettings) == "function" then
            local settings = SC.UI.getSettings()
            show = type(settings) ~= "table" or settings.showNicknames ~= false
        end
        local ok, display = pcall(SC.Names.displayName, actor, show)
        if ok and type(display) == "string" and display ~= "" then return display end
    end
    local descriptor = safeMethod(actor, "getDescriptor")
    local forename = descriptor and safeMethod(descriptor, "getForename") or nil
    local surname = descriptor and safeMethod(descriptor, "getSurname") or nil
    local name
    if forename ~= nil and tostring(forename) ~= "" then
        name = tostring(forename)
        if surname ~= nil and tostring(surname) ~= "" then
            name = name .. " " .. tostring(surname)
        end
    end
    if name == nil then
        local full = safeMethod(actor, "getFullName")
        if full ~= nil and tostring(full) ~= "" then name = tostring(full) end
    end
    return name or "Companion"
end

-- Put the local player's loot pane back the way it was before we borrowed it for
-- a companion's inventory. Safe to call any time; a no-op if we never borrowed it
-- or if the player has since selected a different container in that pane.
function Bridge.restoreInventory()
    local snap = ownedLootPane
    if snap == nil then return true, "not_owned" end
    ownedLootPane = nil
    -- Release the companion even if the player replaced our container or the UI
    -- page disappeared; pane ownership and movement ownership are independent.
    if snap.heldActor and SC.Commands
        and type(SC.Commands.endTemporaryStay) == "function" then
        pcall(SC.Commands.endTemporaryStay, snap.heldActor, snap.stayToken)
    end
    local lootPage = snap.page
    if type(lootPage) ~= "table" then return true, "page_unavailable" end
    -- Only revert while the pane still shows the companion container we set. If
    -- the player opened another container afterwards, leave their choice alone.
    local current = lootPage.inventoryPane and lootPage.inventoryPane.inventory or nil
    if current ~= snap.ourContainer then return true, "player_changed_container" end
    pcall(function()
        if snap.container ~= nil and type(lootPage.setNewContainer) == "function" then
            lootPage:setNewContainer(snap.container)
        end
        if type(lootPage.setVisible) == "function" then
            lootPage:setVisible(snap.visible == true)
        end
        lootPage.isCollapsed = snap.collapsed
        lootPage.collapseCounter = snap.collapseCounter
    end)
    return true, "restored"
end

-- The vanilla pane can be closed or switched independently of our panel. Release
-- the borrowed movement hold as soon as that happens, instead of waiting for the
-- user to leave Loadout or close Living Fellows itself.
function Bridge.maintainInventory()
    local snap = ownedLootPane
    if snap == nil then return true, "not_owned" end
    local lootPage = snap.page
    if type(lootPage) ~= "table" then return Bridge.restoreInventory() end
    local current = lootPage.inventoryPane and lootPage.inventoryPane.inventory or nil
    local visible = safeMethod(lootPage, "getIsVisible")
    if visible == nil then visible = safeMethod(lootPage, "isVisible") end
    if current ~= snap.ourContainer or visible == false or lootPage.isCollapsed == true then
        return Bridge.restoreInventory()
    end
    return true, "owned"
end

function Bridge.openHealth(actor, player, openFunction, describeFunction)
    local valid, reason, argument = Bridge.validateNearbyActor(actor, player, Bridge.VIEW_DISTANCE)
    if not valid then
        return false, reason, argument
    end
    local id = companionId(actor)
    if not id or type(openFunction) ~= "function" then
        return failure("UI_SC_Disabled_HealthUnavailable")
    end
    local description = { id = id, actor = actor }
    if type(describeFunction) == "function" then
        local okDescription, described = pcall(describeFunction, actor, player)
        if okDescription and type(described) == "table" then
            description = described
            description.id = description.id or id
            description.actor = description.actor or actor
        end
    end
    local okOpen, root = pcall(openFunction, "loadout", id, description)
    if not okOpen or not root then
        return failure("UI_SC_Disabled_HealthUnavailable")
    end
    local visible = safeMethod(root, "isVisible")
    if visible == nil then
        visible = safeMethod(root, "getIsVisible")
    end
    local selectedActor = root.selectedRow and root.selectedRow.actor or nil
    local selected = root.selectedId == id or selectedActor == actor
    local correctTab = root.detail and root.detail.tab == "loadout"
    local renderedForCompanion = root.detail and root.detail.displayedCompanionId == id
    if root.collapsed == true or visible == false or not selected or not correctTab or not renderedForCompanion then
        return failure("UI_SC_Disabled_HealthUnavailable")
    end
    return true
end

return Bridge
