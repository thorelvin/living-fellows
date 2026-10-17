-- SPDX-License-Identifier: MIT
SurvivorCompanion = {}
local SC = SurvivorCompanion
Fluid = { Petrol = "petrol" }

local time = 1000
local square = { x = 10, y = 10, z = 0 }
local generator = { square = square, fuel = 20, capacity = 100,
    activated = true, index = 1, data = {} }
function square:getGenerator() return generator.square == self and generator or nil end
function generator:getSquare() return self.square end
function generator:getObjectIndex() return self.index end
function generator:getFuel() return self.fuel end
function generator:getMaxFuel() return self.capacity end
function generator:isActivated() return self.activated end
function generator:getID() return 99 end

local actor = { id = "worker", square = square, inventory = { items = {} } }
local storage = { id = "general:1", category = "general", reserve = 0,
    container = { items = {} } }
local memorial = { id = "memorial:1", category = "memorial", reserve = 0,
    container = { items = {} } }
local base = { id = "base:1", jobs = {}, zones = {
    { id = "area:1", kind = "area", x1 = 10, y1 = 10, x2 = 10, y2 = 10, z = 0 },
} }
local native = nil

local function contains(container, item)
    for _, value in ipairs(container and container.items or {}) do
        if value == item then return true end
    end
    return false
end
local function transfer(from, to, item)
    for index, value in ipairs(from.items) do
        if value == item then
            table.remove(from.items, index)
            to.items[#to.items + 1] = item
            return true
        end
    end
    return false
end

SC.GameplayUtil = {
    call = function(object, method, ...)
        if not object or type(object[method]) ~= "function" then return nil, false end
        return object[method](object, ...), true
    end,
    instanceOf = function(value, kind)
        return kind == "IsoGenerator" and value == generator
    end,
    modData = function(item) return item and item.data or nil end,
    inventoryItems = function(container)
        local values = {}
        for index, item in ipairs(container and container.items or {}) do
            values[index] = item
        end
        return values
    end,
    inventory = function(value) return value and value.inventory or nil end,
    inventoryContains = contains,
    itemType = function(item) return item.kind end,
    idOf = function(value) return value.id end,
    isDead = function(value) return value and value.dead == true end,
    squareOf = function(value) return value == actor and actor.square or value end,
    position = function(value)
        return value and value.x, value and value.y, value and value.z
    end,
    gridSquare = function(x, y, z)
        return x == square.x and y == square.y and z == square.z and square or nil
    end,
    directInteractionAccess = function(value, target)
        return value == actor and target == generator, { square }, "at_generator"
    end,
    distanceSq = function() return 0 end,
    nowMs = function() return time end,
}
SC.BaseLife = {
    active = function() return base end,
    withinWorkReach = function(value)
        return value and (value.x or 10) <= 40
    end,
    describeObject = function(value)
        if value ~= generator or value.index < 0 then return nil end
        return { objectId = "object:1", objectIndex = value.index,
            objectSignature = "generator", x = square.x, y = square.y, z = square.z }
    end,
    resolveObject = function(reference)
        if reference.objectId == "object:1" and generator.index >= 0 then
            return generator
        end
        return reference == storage and storage or nil
    end,
    storageRows = function(_, withdrawals)
        return withdrawals and { storage } or { storage, memorial }
    end,
    storage = function(id) return id == storage.id and storage or nil end,
    resolveContainer = function(row) return row and row.container or nil end,
    availableCountExact = function(row, kind)
        local count = 0
        for _, item in ipairs(row.container.items) do
            if item.kind == kind then count = count + 1 end
        end
        return math.max(0, count - row.reserve)
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
        return transfer(actor.inventory, container, item), "base_supply_returned"
    end,
    restoreToStorage = function(_, _, container, item)
        return transfer(actor.inventory, container, item), "base_supply_returned"
    end,
}
SC.Navigation = { requestAny = function()
    return true, "approaching_generator"
end }
SC.NativeActions = {
    startGeneratorRefuel = function(_, target, item, jobId)
        native = { generator = target, item = item, jobId = jobId, active = true }
        return true, "generator_refuel_action_started"
    end,
    workKind = function() return native and "generator_refuel" or nil end,
    isWorkActive = function() return native and native.active or false end,
    finishWork = function()
        if native and native.active then return false, "work_action_still_active" end
        native = nil
        return true
    end,
    cancelWork = function() native = nil return true end,
}

SC_GENERATOR_REFUEL_TEST = {
    actor = actor, generator = generator, square = square, base = base,
    storage = storage, memorial = memorial,
    item = function(id, quantity, mixed)
        local fluid = { amount = quantity, mixed = mixed == true }
        function fluid:contains(kind)
            return kind == Fluid.Petrol and self.amount > 0
        end
        function fluid:isMixture() return self.mixed end
        function fluid:getAmount() return self.amount end
        function fluid:getSpecificFluidAmount(kind)
            return kind == Fluid.Petrol and self.amount or 0
        end
        local can = { id = id, kind = "Base.PetrolCan", data = {}, fluid = fluid }
        function can:getFluidContainer() return self.fluid end
        function can:getID() return self.id end
        return can
    end,
    finishAction = function(withReceipt)
        local item = native and native.item
        if not item then return end
        local beforeFuel, beforeCan = generator.fuel, item.fluid.amount
        local gain = math.min(beforeCan, generator.capacity - beforeFuel)
        generator.fuel = generator.fuel + gain
        item.fluid.amount = item.fluid.amount - gain
        if withReceipt ~= false then
            SC.GeneratorRefuel.recordTransfer(native.jobId, generator, item,
                beforeFuel, beforeCan, generator.fuel, item.fluid.amount)
        end
        native.active = false
    end,
    resetNative = function() native = nil end,
    nativeActive = function() return native and native.active end,
    clock = function(value) if value then time = value end return time end,
    moveGenerator = function(x, y)
        square.x, square.y = x, y
    end,
}
