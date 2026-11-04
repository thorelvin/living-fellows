-- SPDX-License-Identifier: MIT
-- Exact timber delivery is exercised separately from ordinary search receipts.
local SC, T = SurvivorCompanion, INTEGRATION_TEST
local I, U = SC.ExpeditionIntegration, SC.GameplayUtil
local physicalWood, physicalLogging = SC.ExpeditionWood, SC.LoggingWork
local checks = 0
local function check(value, label)
    checks = checks + 1
    assert(value, "wood integration " .. checks .. ": " .. label)
end
local function clone(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, nested in pairs(value) do copy[key] = clone(nested) end
    return copy
end
local transfer = SC.WorkTransport.transferVerified
local function clear()
    I.reset()
    T.now, T.moves, T.animations, T.toolCalls = 0, 0, 0, 0
    T.storages, T.actors, T.car, T.yard = {}, {}, nil, nil
    T.blockToolReturn, T.access, T.transferFault, T.dropFault = nil, nil, nil, nil
    T.dropRefused, T.dropAmbiguous, T.arrangeCalls, T.arrangeVerified = nil, nil, 0, nil
    T.minimums = { food = 0, water = 0, medicine = 0, ammunition = 0 }
end
U.modData = function(item) return item.data end
U.directInteractionAccess = function(_, object)
    return T.access ~= false, { object }, T.access == false and "approach" or nil
end
U.squareOf = function(object) return object end
U.sameSquare = function(actor, square)
    return (actor.x or 10) == square.x and (actor.y or 10) == square.y
end
U.listSize = function(values) return #values end
U.listGet = function(values, index) return values[index + 1] end
U.move = function() T.animations = T.animations + 1 return true end
U.worldItemPresent = function(square, world)
    for _, candidate in ipairs(square.worlds) do if candidate == world then return true end end
    return false
end
U.dropItem = function(source, square, item)
    if T.dropRefused then return false, "native_drop_refused" end
    for index, candidate in ipairs(source.items) do
        if candidate == item then
            table.remove(source.items, index)
            item.container = nil
            local world = { item = item }
            function world:getItem() return self.item end
            item.world = world
            square.worlds[#square.worlds + 1] = world
            T.moves = T.moves + 1
            if T.dropAmbiguous then item.world = { unverified = true } end
            if T.dropFault then return false, "native_drop_return_failed" end
            return true, world
        end
    end
    return false, "missing"
end
SC.WorkTransport.transferVerified = function(source, destination, item, actor)
    local moved, why = transfer(source, destination, item, actor)
    if moved and T.transferFault then return false, "native_return_failed" end
    return moved, why
end
SC.BaseLife.isInside = function(holder) return holder.inside ~= false end
SC.BaseLife.withinWorkReach = function(holder) return holder.reach ~= false end
SC.BaseLife.resolveObject = function(storage) return storage end
SC.BaseLife.storageRows = function(category)
    if category == nil then return T.storages end
    return SC.BaseLife.depositStorageRows(category)
end
SC.BaseLife.storageAcceptsDeposit = function(storage)
    return storage.deposits ~= false
end
SC.Navigation = {
    cancel = function() return true end,
    selectInteraction = function(_, _, _, choices)
        for _, choice in ipairs(choices) do
            if choice.storage.unreachable ~= true then return choice end
        end
        return nil, "unreachable"
    end,
    requestAny = function(_, _, _, options)
        T.navigationOptions = options
        return true, "approaching"
    end,
}
SC.NativeActions = {
    visualStatus = function() return "completed" end,
    visualToken = function() return 7 end,
    clearVisual = function() end,
    stopDirect = function() end,
}
SC.Vehicle.isStationary = function(car) return car.moving ~= true end
SC.LoggingWork = { cargo = function(_, carId, _, _, options)
    T.cargoOptions = options
    local car = SC.Vehicle.loadedBySqlId(carId)
    if not car then return nil, nil, "wood_car_unloaded" end
    if car.locked then return nil, nil, "unlock_car_door", true end
    return car, car.trunk
end }
SC.ExpeditionWood = {
    valid = function(wood) return type(wood) == "table" and type(wood.loans) == "table" end,
    copy = clone,
    toolsPending = function(wood, actorId)
        return actorId and wood.loans[actorId] ~= nil or not actorId and next(wood.loans) ~= nil
    end,
    carryDestination = function(actor)
        return actor.carry or actor.inventory
    end,
    loanState = function(wood, actorId, actor)
        local loan = wood.loans[actorId]
        if not loan then return "none" end
        if not actor or T.loanUnreadable then return "unknown" end
        for _, carried in ipairs(U.inventoryItemsDeep(actor.inventory)) do
            if carried.id == loan.itemId then return "carried" end
        end
        return "missing"
    end,
    returnTools = function(actor, ctx)
        T.toolCalls = T.toolCalls + 1
        T.toolContext = ctx
        if T.blockToolReturn then return false, "wood_tool_source_unavailable", false end
        ctx.wood.loans[actor.id] = nil
        return true, "wood_axe_returned", true
    end,
}
SC.LogYard = {
    hasZone = function() return T.yard ~= nil end,
    select = function()
        if not T.yard or #T.yard.worlds >= 4 then return nil end
        return { kind = "log_yard", zoneId = "yard:1", x = 10, y = 10,
            z = 0, square = T.yard }
    end,
    tile = function(x, y, z, zoneId)
        if T.yard and x == 10 and y == 10 and z == 0 and zoneId == "yard:1" then return T.yard end
    end,
    contents = function(square) return { units = #square.worlds, splitPending = false } end,
    arrange = function(square)
        T.arrangeCalls = T.arrangeCalls + 1
        T.arrangeVerified = true
        for _, world in ipairs(square.worlds) do
            local item = world:getItem()
            T.arrangeVerified = T.arrangeVerified and item:getContainer() == nil
                and item:getWorldItem() == world and U.worldItemPresent(square, world) == true
            for _, actor in pairs(T.actors) do
                for _, carriedItem in ipairs(U.inventoryItemsDeep(actor.inventory)) do
                    if carriedItem == item then T.arrangeVerified = false end
                end
            end
        end
        return true
    end,
}
local function log(id)
    local item = T.item(id, "construction", "Base.Log")
    item.data = {}
    function item:getModData() return self.data end
    function item:getWorldItem() return self.world end
    return item
end
local function mission(actor, logs, options)
    options = options or {}
    local acquisitions = {}
    for index, item in ipairs(logs) do
        acquisitions[index] = { id = item.id, itemType = "Base.Log", memberId = actor.id,
            source = { x = 300, y = 300, z = 0 } }
        item.data.LF_ExpeditionWood = { tripId = "wood:1", id = item.id, memberId = actor.id }
    end
    return { radioSession = "wood:1", homeBaseId = "camp:1",
        restockBaseDuty = options.restock == true, commandSerials = { [actor.id] = 0 },
        roster = { { id = actor.id, name = actor.name, actor = actor } },
        scout = { kind = "wood", vehicle = options.car and { sqlId = options.car.id },
            wood = { version = 1, request = options.request or { mode = "count", quantity = 12 },
                acquisitions = acquisitions, workers = {}, loans = options.loans or {} } } }
end
local function create(actor, logs, options)
    local record = I.create(mission(actor, logs, options))
    check(I.valid(record), "created v2 wood ledger is valid")
    return record
end
local function yard()
    T.yard = { x = 10, y = 10, z = 0, worlds = {} }
    function T.yard:getWorldObjects() return self.worlds end
    return T.yard
end
local function bagFor(actor, items)
    local bag = T.item("bag:" .. actor.id, "container")
    bag.nested = T.container(items)
    function bag.nested:getContainingItem() return bag end
    actor.inventory.items[#actor.inventory.items + 1] = bag
    bag.container = actor.inventory
    return bag.nested
end
local function carFor(item)
    local car = { id = 72, inside = false, reach = true, trunk = T.container({ item }) }
    function car:isEngineRunning() return self.running == true end
    T.car = car
    return car
end

T.WoodDelivery = {
    check = check, clone = clone, clear = clear, log = log, create = create,
    yard = yard, bagFor = bagFor, carFor = carFor, transfer = transfer,
    physicalWood = physicalWood, physicalLogging = physicalLogging,
    checks = function() return checks end,
}
