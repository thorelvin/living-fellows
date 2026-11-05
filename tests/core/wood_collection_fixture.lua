-- SPDX-License-Identifier: MIT
-- Exact native effects are supplied by this fixture; the worker must observe
-- those objects and move them, and cannot manufacture successful output.
local SC = SurvivorCompanion
local Wood, Logging = SC.ExpeditionWood, SC.LoggingWork
local checks, clock, serial = 0, 1000, 0
local function check(value, message)
    checks = checks + 1
    if not value then error("wood check " .. checks .. ": " .. message) end
end
local squares, actors, storages = {}, {}, {}
local function weight(container)
    local total = 0
    for _, item in ipairs(container.items) do
        total = total + item.weight + (item.bag and weight(item.bag) * (1 - item.reduction / 100) or 0)
    end
    return total
end
local function container(capacity)
    local result = { items = {}, capacity = capacity or 50 }
    function result:getItems() return self.items end
    function result:getFreeCapacity() return self.capacity - weight(self) end
    return result
end
local function put(owner, item)
    owner.items[#owner.items + 1] = item
    item.owner = owner
end
local function remove(owner, item)
    for index, current in ipairs(owner.items) do
        if current == item then table.remove(owner.items, index) item.owner = nil return true end
    end
    return false
end
local function item(kind)
    serial = serial + 1
    local result = { kind = kind, id = "wood-item-" .. serial, data = {},
        weight = kind == "Base.Log" and 9 or kind == "Base.Axe" and 3 or 0.2 }
    function result:getContainer() return self.owner end
    function result:getWorldItem() return self.world end
    function result:isBroken() return self.broken == true end
    function result:getTreeDamage() return self.kind == "Base.Axe" and 10 or 0 end
    function result:getInventory() return self.bag end
    function result:getWeightReduction() return self.reduction or 0 end
    return result
end
local function actor(id, limit)
    local result = { id = id, bag = container(), limit = limit or 30, x = 0, y = 0, z = 0 }
    function result:isDead() return self.dead == true end
    function result:isEnduranceSufficientForAction() return self.endurance ~= false end
    function result:isEquippedClothing(value) return self.worn == value end
    function result:isHandItem(value) return self.primary == value or self.secondary == value end
    actors[id] = result
    return result
end
local function square(x, y, z)
    if z ~= 0 then return nil end
    local key = x .. ":" .. y
    if not squares[key] then
        local result = { x = x, y = y, z = 0, world = {} }
        function result:getTree() return self.tree end
        function result:getWorldObjects() return self.world end
        squares[key] = result
    end
    return squares[key]
end
local function plant(x, y)
    local result = square(x, y, 0)
    result.tree = { health = 100 }
    function result.tree:getObjectIndex() return 0 end
    function result.tree:getSize() return 3 end
    function result.tree:getHealth() return self.health end
    return result
end
local function drop(target, value)
    local wrapper = { item = value }
    function wrapper:getItem() return self.item end
    target.world[#target.world + 1] = wrapper
    value.world = wrapper
    return wrapper
end
local U = {}
function U.call(object, method, ...)
    if object and type(object[method]) == "function" then return object[method](object, ...), true end
    return nil, false
end
function U.position(value) if value then return value.x, value.y, value.z end end
function U.inventory(value) return value.bag end
function U.nowMs() return clock end
function U.idOf(value) return value.id end
function U.resolveActor(id) return actors[id] end
function U.modData(value) return value.data end
function U.gridSquare(x, y, z) return square(x, y, z) end
function U.itemType(value) return value.kind end
function U.itemStableId(value) return value.id end
function U.itemWeight(value) return value.weight end
function U.itemHasTag(value, tag) return value.kind == "Base.Axe" and tag == "CHOP_TREE" end
function U.listSize(list) return #list end
function U.listGet(list, index) return list[index + 1] end
function U.isSquareFree(value) return value.tree == nil end
function U.sameSquare(value, target) return value.x == target.x and value.y == target.y and value.z == target.z end
function U.inventoryContains(owner, sought)
    for _, value in ipairs(owner and owner.items or {}) do if value == sought then return true end end
    return false
end
function U.carryLoad(value) return weight(value.bag), value.limit, weight(value.bag) / value.limit, value.bag end
function U.stop() return true end
function U.transferItemVerified(source, destination, value)
    if not remove(source, value) then return false, "source_missing" end
    put(destination, value)
    return true
end
function U.worldItemPresent(target, wrapper)
    for _, value in ipairs(target.world) do if value == wrapper then return true end end
    return false
end
function U.takeWorldItemVerified(wrapper, destination, value)
    for _, target in pairs(squares) do
        for index, current in ipairs(target.world) do
            if current == wrapper and current.item == value then
                table.remove(target.world, index)
                value.world = nil
                put(destination, value)
                if U.pickupFault then U.pickupFault = nil return false, "native_pickup_receipt_failed" end
                return true
            end
        end
    end
    return false, "world_missing"
end
local chops = 0
function U.move(value, _, request)
    if request.action ~= "chop_tree" or request.tool.kind ~= "Base.Axe" then return false end
    chops = chops + 1
    value.kind, value.active, value.target = "chop_tree", true, request.targetSquare
    return true
end
SC.GameplayUtil = U
SC.NativeActions = {
    workKind = function(value) return value.kind end,
    isWorkActive = function(value) return value.active == true end,
    finishWork = function(value) value.kind = nil return true end,
    cancelWork = function(value) value.kind, value.active = nil, false return true end,
}
SC.Navigation = {
    interactionTargets = function(_, target) return { target } end,
    requestAny = function(value, targets)
        local target = targets[1]
        value.x, value.y, value.z = target.x, target.y, target.z
        return true, "arrived", target
    end,
    cancel = function() return true end,
}
SC.WorkTransport = {
    hasRoom = function(owner, _, value)
        if owner.reject then return false, "destination_item_rejected" end
        return owner:getFreeCapacity() >= value.weight, "destination_full"
    end,
    foreignProtected = function() return false end,
}
SC.PersonalItems = { isProtected = function() return false end }
SC.BaseLife = {
    isInside = function() return false end,
    policies = function() return { workOutsideAtNight = true } end,
    storageRows = function(category) return category == "tools" and storages or {} end,
    storage = function(id) for _, row in ipairs(storages) do if row.id == id then return row end end end,
    withdrawable = function() return true end,
    resolveContainer = function(storage) return storage.container end,
    availableCountExact = function() return 1 end,
}
SC.BaseWork = {
    withdrawFromStorage = function(value, _, storage, owner, tool)
        if U.transferItemVerified(owner, value.bag, tool) then return true, "base_supply_taken" end
        return false, "source_missing"
    end,
    returnToStorage = function(value, _, storage, owner, tool)
        if U.transferItemVerified(tool.owner, owner, tool) then return true, "base_supply_returned" end
        return false, "source_missing"
    end,
}
local car = { x = 20, y = 20, z = 0, cargo = container(90) }
function car:isTrunkLocked() return false end
function car:getAreaCenter() return { x = 20, y = 20, z = 0 } end
local part = { getArea = function() return "Trunk" end }
SC.Vehicle = {
    loadedBySqlId = function(id) return id == 42 and car end,
    isStationary = function() return true end,
    cargoPart = function() return part, car.cargo end,
}
local function context(wood, roster, carId)
    return { missionId = "wood-trip", wood = wood, roster = roster, carId = carId,
        destination = { x = 0, y = 0, z = 0 } }
end
local function pulse(value, ctx, count)
    for _ = 1, count or 1 do clock = clock + 250 Wood.update(value, ctx) end
end
local function nativeFell(value, logs)
    local target = value.target
    target.tree, value.active = nil, false
    for _ = 1, logs do drop(target, item("Base.Log")) end
    drop(target, item("Base.TreeBranch"))
    drop(target, item("Base.Twigs"))
end

SC.WoodTestFixture = {
    check = check, actor = actor, item = item, container = container, put = put,
    remove = remove, weight = weight, plant = plant, square = square, drop = drop,
    pulse = pulse, nativeFell = nativeFell, context = context, car = car,
    actors = actors, chops = function() return chops end, checks = function() return checks end,
    advanceClock = function(delta) clock = clock + delta end,
    setStorages = function(values) storages = values end,
}
