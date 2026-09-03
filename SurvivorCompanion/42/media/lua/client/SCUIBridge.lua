-- SPDX-License-Identifier: MIT

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion

SC.UIBridge = SC.UIBridge or {}
local Bridge = SC.UIBridge

Bridge.NEARBY_DISTANCE = 4

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

function Bridge.openInventory(actor, player)
    local valid, reason, argument = Bridge.validateNearbyActor(actor, player, Bridge.NEARBY_DISTANCE)
    if not valid then
        return false, reason, argument
    end
    local inventory = safeMethod(actor, "getInventory")
    if not inventory then
        return failure("UI_SC_Disabled_NoInventory")
    end
    local playerNumValue = safeMethod(player, "getPlayerNum")
    local playerNum = tonumber(playerNumValue)
    if playerNum == nil or type(getPlayerLoot) ~= "function" then
        return failure("UI_SC_Disabled_NoInventoryUI")
    end
    local okPage, lootPage = pcall(getPlayerLoot, playerNum)
    if not okPage or not lootPage or type(lootPage.setNewContainer) ~= "function" or type(lootPage.setVisible) ~= "function" then
        return failure("UI_SC_Disabled_NoInventoryUI")
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
        return failure("UI_SC_Disabled_NoInventoryUI")
    end
    local selected = not lootPage.inventoryPane or lootPage.inventoryPane.inventory == inventory
    local visible = safeMethod(lootPage, "getIsVisible")
    if visible == nil then
        visible = safeMethod(lootPage, "isVisible")
    end
    if not selected or visible == false or lootPage.isCollapsed == true then
        return failure("UI_SC_Disabled_NoInventoryUI")
    end
    return true
end

function Bridge.openHealth(actor, player, openFunction, describeFunction)
    local valid, reason, argument = Bridge.validateNearbyActor(actor, player, Bridge.NEARBY_DISTANCE)
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
