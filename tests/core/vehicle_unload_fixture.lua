-- SPDX-License-Identifier: MIT
SurvivorCompanion = {}
local SC = SurvivorCompanion
local square = { x = 10, y = 10, z = 0 }
local trunk = { items = {} }
local inventory = { items = {} }
local storage = { items = {} }
local car = { id = 41, stationary = true }
local part = {}
local base = { jobs = {} }
local visual = "none"
local deferDeposit = false

function car:getSqlId() return self.id end
function car:getPartById(id) return id == "TruckBed" and part or nil end
function car:isTrunkLocked() return false end
function car:getX() return 10 end
function car:getY() return 10 end
function car:getZ() return 0 end
function car:getScriptName() return "Franklin Valuline" end
function car:getAreaCenter()
    return { getX = function() return 10 end, getY = function() return 10 end }
end
function part:getItemContainer() return trunk end
function part:getArea() return "trunk" end

local actor = { id = "worker", square = square, inventory = inventory }
local function items(container) return container and container.items or {} end
SC.GameplayUtil = {
    call = function(object, method, ...)
        if not object or type(object[method]) ~= "function" then return nil, false end
        return object[method](object, ...), true
    end,
    inventoryItems = function(container)
        local result = {}
        for index, item in ipairs(items(container)) do result[index] = item end
        return result
    end,
    inventory = function(value) return value.inventory end,
    inventoryContains = function(container, item)
        for _, candidate in ipairs(items(container)) do
            if candidate == item then return true end
        end
        return false
    end,
    idOf = function(value) return value.id end,
    gridSquare = function() return square end,
    isSquareFree = function() return true end,
    safehouseBlocker = function() return false end,
    distanceSq = function() return 0 end,
    sameSquare = function(value, target) return value.square == target end,
    move = function() visual = "active" return true end,
}
SC.Vehicle = {
    isStationary = function(value) return value.stationary end,
    loadedVehicles = function() return { car } end,
    loadedBySqlId = function(id) return id == car.id and car or nil end,
}
SC.ExpeditionCar = {
    parkingAreas = function() return { { id = "parking:1" } } end,
    fitsParking = function(value) return value == car and car.stationary end,
}
SC.BaseLife = {
    active = function() return base end,
    enqueueJob = function(spec)
        local job = { id = "job:" .. tostring(#base.jobs + 1),
            type = spec.type, state = "pending", target = spec.target }
        base.jobs[#base.jobs + 1] = job
        return true, job
    end,
}
SC.BaseWork = {
    destinationForCarItem = function()
        return { id = "general:1" }, storage
    end,
    depositToStorage = function(_, _, _, _, item)
        if deferDeposit then return false, "approaching_base_storage" end
        return SC.WorkTransport.transferVerified(inventory, storage, item, actor)
    end,
}
SC.WorkTransport = {
    transferVerified = function(source, destination, item)
        for index, candidate in ipairs(source.items) do
            if candidate == item then
                table.remove(source.items, index)
                destination.items[#destination.items + 1] = item
                return true, "transferred"
            end
        end
        return false, "item_missing"
    end,
}
SC.NativeActions = {
    visualStatus = function() return visual end,
    clearVisual = function() visual = "none" return true end,
    cancelVisual = function() visual = "none" return true end,
}
SC.Navigation = { requestAny = function() return true, "approaching" end }

SC_VEHICLE_UNLOAD_TEST = {
    actor = actor, car = car, trunk = trunk, inventory = inventory,
    storage = storage, base = base,
    item = function(id)
        local value = { id = id, data = {} }
        function value:getModData() return self.data end
        return value
    end,
    visual = function(value) if value then visual = value end return visual end,
    deferDeposit = function(value) deferDeposit = value end,
}
