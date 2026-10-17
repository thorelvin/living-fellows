-- SPDX-License-Identifier: MIT
SurvivorCompanion = {}
local SC = SurvivorCompanion
Fluid = { Petrol = "petrol" }

local clock = 1000
local square = { x = 10, y = 10, z = 0 }
local actor = { id = "worker", square = square, inventory = { items = {} } }
local storage = { id = "general:1", category = "general", reserve = 0,
    container = { items = {} } }
local memorial = { id = "memorial:1", category = "memorial", reserve = 0,
    container = { items = {} } }
local base = { jobs = {} }
local part = { current = 20, capacity = 50 }
local car = { id = 41, stationary = true, x = 10, y = 10, engine = false }
local native = nil
local deferReturn = false
local rejectReturn = false
local function contains(container, item)
    for _, candidate in ipairs(container and container.items or {}) do
        if candidate == item then return true end
    end
    return false
end
local function transfer(source, destination, item)
    for index, candidate in ipairs(source.items) do
        if candidate == item then
            table.remove(source.items, index)
            destination.items[#destination.items + 1] = item
            return true
        end
    end
    return false
end
function car:getSqlId() return self.id end
function car:getX() return self.x end
function car:getY() return self.y end
function car:getZ() return 0 end
function car:isEngineRunning() return self.engine end
function car:isEngineStarted() return self.engine end
function car:isStarting() return false end
function car:getPartById(id) return id == "GasTank" and part or nil end
function car:getAreaCenter()
    return { getX = function() return 10 end, getY = function() return 10 end }
end
function part:getContainerContentAmount() return self.current end
function part:getContainerCapacity() return self.capacity end
function part:getArea() return "GasTank" end

SC.GameplayUtil = {
    call = function(object, method, ...)
        if not object or type(object[method]) ~= "function" then return nil, false end
        return object[method](object, ...), true
    end,
    modData = function(item) return item and item.data or nil end,
    inventoryItems = function(container)
        local result = {}
        for index, item in ipairs(container and container.items or {}) do
            result[index] = item
        end
        return result
    end,
    inventory = function(value) return value and value.inventory or nil end,
    inventoryContains = contains,
    itemType = function(item) return item.kind end,
    idOf = function(value) return value.id end,
    squareOf = function(value)
        return value == actor and square or value and (value.square or value) or nil
    end,
    gridSquare = function() return square end,
    isSquareFree = function() return true end,
    safehouseBlocker = function() return false end,
    directInteractionAccess = function() return true end,
    distanceSq = function() return 0 end,
    sameSquare = function(value, target) return value.square == target end,
    position = function(value)
        if value == actor then return square.x + 0.5, square.y + 0.5, square.z end
        return value and value.x, value and value.y, value and value.z
    end,
    arrived = function(value, target, options)
        return value == actor and target == square
            and (options and options.distance or 0) >= 0.7
    end,
    nowMs = function() return clock end,
}
SC.Vehicle = {
    loadedBySqlId = function(id) return id == car.id and car or nil end,
    loadedVehicles = function() return { car } end,
    isStationary = function(value) return value.stationary end,
}
SC.ExpeditionCar = {
    parkingAreas = function() return { { id = "parking:1" } } end,
    fitsParking = function(value) return value == car and car.x == 10 end,
}
SC.BaseLife = {
    active = function() return base end,
    withinWorkReach = function(value) return value and (value.x or 10) <= 30 end,
    storageRows = function(_, withdrawals)
        return withdrawals and { storage } or { storage, memorial }
    end,
    storage = function(id) return id == storage.id and storage or nil end,
    resolveObject = function(value) return value end,
    resolveContainer = function(value) return value and value.container or nil end,
    availableCountExact = function(value, kind)
        local count = 0
        for _, item in ipairs(value.container.items) do
            if item.kind == kind then count = count + 1 end
        end
        return math.max(0, count - value.reserve)
    end,
    enqueueJob = function(spec)
        local job = { id = "job:" .. tostring(#base.jobs + 1),
            type = spec.type, target = spec.target, priority = spec.priority,
            state = "pending", reservedBy = actor.id }
        base.jobs[#base.jobs + 1] = job
        return true, job
    end,
    job = function(id)
        for _, job in ipairs(base.jobs) do
            if job.id == id then return job end
        end
    end,
}
SC.WorkTransport = { foreignProtected = function() return false end }
SC.BaseWork = {
    withdrawFromStorage = function(_, _, _, container, item)
        return transfer(container, actor.inventory, item), "base_supply_taken"
    end,
    returnToStorage = function(_, _, _, container, item)
        if deferReturn then return true, "approaching_base_storage" end
        if rejectReturn then return false, "base_storage_action_rejected" end
        return transfer(actor.inventory, container, item), "base_supply_returned"
    end,
    restoreToStorage = function(_, _, container, item)
        return transfer(actor.inventory, container, item), "base_supply_returned"
    end,
}
SC.Navigation = { requestAny = function()
    return true, "approaching_car_fuel"
end }
SC.NativeActions = {
    startVehicleRefuel = function(_, _, _, item)
        native = { item = item, active = true }
        return true, "car_refuel_action_started"
    end,
    workKind = function() return native and "vehicle_refuel" or nil end,
    isWorkActive = function() return native and native.active or false end,
    finishWork = function()
        if native and native.active then return false, "work_action_still_active" end
        native = nil
        return true
    end,
    cancelWork = function()
        native = nil
        return true
    end,
}
SC_REFUEL_TEST = {
    actor = actor, car = car, part = part, base = base,
    storage = storage, memorial = memorial,
    item = function(id, quantity, mixed)
        local fluid = { amount = quantity, mixed = mixed == true }
        function fluid:contains(kind) return kind == Fluid.Petrol and self.amount > 0 end
        function fluid:isMixture() return self.mixed end
        function fluid:getAmount() return self.amount end
        function fluid:getSpecificFluidAmount(kind)
            return kind == Fluid.Petrol and self.amount or 0
        end
        local item = { id = id, kind = "Base.PetrolCan", data = {}, fluid = fluid }
        function item:getFluidContainer() return self.fluid end
        function item:getID() return self.id end
        return item
    end,
    finishAction = function(quantity)
        local item = native and native.item
        if item then
            local delta = quantity or math.min(item.fluid.amount,
                part.capacity - part.current)
            item.fluid.amount = item.fluid.amount - delta
            part.current = part.current + delta
            native.active = false
        end
    end,
    resetNative = function() native = nil end,
    nativeActive = function() return native and native.active end,
    deferReturn = function(value) deferReturn = value end,
    rejectReturn = function(value) rejectReturn = value end,
    clock = function(value) if value then clock = value end return clock end,
}
