-- SPDX-License-Identifier: MIT
SurvivorCompanion = {}
local SC = SurvivorCompanion
INTEGRATION_TEST = { now = 0, moves = 0, storages = {}, actors = {} }
local T = INTEGRATION_TEST

function T.container(items, capacity)
    local container = { items = items or {}, capacity = capacity or 99 }
    for _, item in ipairs(container.items) do item.container = container end
    return container
end
function T.item(id, category, fullType)
    local item = { id = id, category = category,
        fullType = fullType or "Base." .. id }
    function item:getContainer() return self.container end
    function item:getItemContainer() return self.nested end
    return item
end
function T.actor(id, name, items)
    local actor = { id = id, name = name, serial = 0,
        inventory = T.container(items) }
    T.actors[id] = actor
    return actor
end
function T.storage(id, category, items, capacity)
    local row = { id = id, category = category,
        container = T.container(items, capacity) }
    T.storages[#T.storages + 1] = row
    return row
end
SC.GameplayUtil = {
    nowMs = function() return T.now end,
    call = function(object, method, ...)
        if not object or type(object[method]) ~= "function" then
            return nil, false
        end
        return object[method](object, ...), true
    end,
    itemStableId = function(item) return item and item.id end,
    itemType = function(item) return item.fullType end,
    inventory = function(actor) return actor.inventory end,
    inventoryItems = function(container, limit)
        local result = {}
        for index = 1, math.min(#(container and container.items or {}), limit) do
            result[index] = container.items[index]
        end
        return result
    end,
    inventoryItemsDeep = function(container)
        local result = {}
        local function visit(current)
            for _, item in ipairs(current.items) do
                result[#result + 1] = item
                if item.nested then visit(item.nested) end
            end
        end
        visit(container)
        return result
    end,
    inventoryContains = function(container, item)
        for _, value in ipairs(container and container.items or {}) do
            if value == item then return true end
        end
        return false
    end,
    idOf = function(actor) return actor.id end,
    isDead = function(actor) return actor.dead == true end,
}
SC.Registry = { byId = function(id)
    return T.actors[id] and { actor = T.actors[id] } or nil
end }
SC.WorkTransport = {
    hasRoom = function(container) return #container.items < container.capacity end,
    transferVerified = function(source, destination, item)
        if #destination.items >= destination.capacity then return false, "full" end
        for index, value in ipairs(source.items) do
            if value == item then
                table.remove(source.items, index)
                destination.items[#destination.items + 1] = item
                item.container = destination
                T.moves = T.moves + 1
                return true
            end
        end
        return false, "missing"
    end,
}
SC.BaseLife = {
    active = function() return { id = "camp:1", core = { x = 10, y = 10, z = 0 } } end,
    isInside = function() return true end,
    foodDepositCategory = function(item)
        local wanted = item.fresh and "fresh_food" or "food"
        for _, row in ipairs(T.storages) do
            if row.category == wanted then return wanted end
        end
        return item.fresh and "food" or "fresh_food"
    end,
    depositStorageRows = function(category)
        local result = {}
        for _, row in ipairs(T.storages) do
            if row.category == category then result[#result + 1] = row end
        end
        return result
    end,
    storageRows = function(category)
        return SC.BaseLife.depositStorageRows(category)
    end,
    resolveContainer = function(row) return row.container end,
    storageAcceptsDeposit = function() return true end,
}
SC.BaseWork = {
    classifyItem = function(item) return item.category end,
    depositToStorage = function(actor, _, storage, container, item)
        local moved, reason = SC.WorkTransport.transferVerified(
            actor.inventory, container, item)
        return moved, moved and "base_supply_returned" or reason
    end,
    withdrawFromStorage = function(actor, _, storage, container, item)
        local moved, reason = SC.WorkTransport.transferVerified(
            container, actor.inventory, item)
        return moved, moved and "base_supply_taken" or reason
    end,
}
SC.Vehicle = { loadedBySqlId = function(id)
    return T.car and T.car.id == id and T.car or nil
end }
SC.VehicleUnload = { takeExact = function(actor, _, item, _, source)
    if T.car.locked then return false, "car_trunk_locked" end
    local moved, reason = SC.WorkTransport.transferVerified(
        source, actor.inventory, item)
    return moved, moved and "car_item_carried" or reason
end }
SC.Logistics = {
    roleMinimums = function() return T.minimums or {
        food = 0, water = 0, medicine = 0, ammunition = 0 } end,
    itemCategory = function(item) return item.category end,
}
SC.Needs = {
    isSafeFoodItem = function(item) return item.safeFood == true end,
    isSafeWaterItem = function(item) return item.safeWater == true end,
}
SC.Commands = {
    peek = function(actor) return { commandSerial = actor.serial or 0,
        order = actor.order or "stay" } end,
    resumeBaseDutyIfUnchanged = function(id, serial)
        local actor = T.actors[id]
        if actor.serial ~= serial then return false, "new_player_order" end
        actor.order = "base_duty"
        actor.serial = actor.serial + 1
        return true, "base_duty"
    end,
}
