-- SPDX-License-Identifier: MIT

FarmLifecycleFixture = {}
local F = FarmLifecycleFixture
local SC = SurvivorCompanion
local U = SC.GameplayUtil

F.clock = 1000
F.squares = {}
F.actors = {}
F.receipts = {}
F.storages = {}
F.storageContainers = {}
F.nextReceipt = 1
F.returnMode = "complete"
F.restoreCalls = 0
F.navigationRequests = {}
F.native = setmetatable({}, { __mode = "k" })
F.nativeStarts = {}
F.nativeCancels = 0
F.completedJobs = 0
F.itemBudget = 256
F.nativeStops = 0

local function removeIdentity(container, item)
    for index = #(container.items or {}), 1, -1 do
        if container.items[index] == item then
            table.remove(container.items, index)
            if item.container == container then item.container = nil end
            return true
        end
    end
    return false
end

local function addIdentity(container, item)
    if not container or not item then return false end
    for _, existing in ipairs(container.items or {}) do
        if existing == item then return true end
    end
    container.items[#container.items + 1] = item
    item.container = container
    return true
end

function F.container(items)
    local container = { items = {} }
    function container:getItems() return self.items end
    function container:contains(item)
        for _, value in ipairs(self.items) do if value == item then return true end end
        return false
    end
    function container:Remove(item) return removeIdentity(self, item) end
    function container:AddItem(item) return addIdentity(self, item) end
    for _, item in ipairs(items or {}) do addIdentity(container, item) end
    return container
end

function F.item(fullType, nativeId, options)
    options = options or {}
    local item = {
        fullType = fullType, nativeId = nativeId, modData = {}, tags = options.tags or {},
        category = options.category, fluidAmount = options.fluidAmount,
        fluidCapacity = options.fluidCapacity,
    }
    function item:getFullType() return self.fullType end
    function item:getType() return string.match(self.fullType, "[^%.]+$") end
    function item:getID() return self.nativeId end
    function item:getModData() return self.modData end
    function item:getContainer() return self.container end
    function item:getCategory() return self.category end
    function item:hasTag(tag) return self.tags[tostring(tag)] == true end
    function item:isBroken() return false end
    function item:getFluidContainer()
        if self.fluidCapacity == nil then return nil end
        local owner = self
        return {
            getAmount = function() return owner.fluidAmount or 0 end,
            getCapacity = function() return owner.fluidCapacity end,
            getPrimaryFluid = function()
                if (owner.fluidAmount or 0) <= 0 then return nil end
                return { getFluidTypeString = function() return "Water" end }
            end,
        }
    end
    return item
end

function F.actor(id, x, y)
    local actor = { id = id, x = x or 0, y = y or 0, z = 0, inventory = F.container() }
    function actor:getInventory() return self.inventory end
    function actor:getX() return self.x end
    function actor:getY() return self.y end
    function actor:getZ() return self.z end
    function actor:getModData() return { SC_Id = self.id } end
    F.actors[id] = actor
    return actor
end

function F.square(x, y, plant)
    local value = { x = x, y = y, z = 0, plant = plant, objects = {} }
    function value:getX() return self.x end
    function value:getY() return self.y end
    function value:getZ() return self.z end
    function value:getObjects() return self.objects end
    F.squares[tostring(x) .. ":" .. tostring(y) .. ":0"] = value
    return value
end

function F.plant(options)
    options = options or {}
    local plant = {
        state = options.state or "seeded", typeOfSeed = options.cropType or "Tomato",
        hasSeeds = options.hasSeeds == true, waterLvl = options.waterLvl or 80,
        waterNeeded = options.waterNeeded or 70, compost = options.compost == true,
        harvestable = options.harvestable ~= false,
    }
    function plant:canHarvest() return self.harvestable == true end
    return plant
end

function F.waterSource(square, tainted)
    local source = { square = square, fluidAmount = 20, tainted = tainted ~= false }
    function source:getSquare() return self.square end
    function source:getFluidAmount() return self.fluidAmount end
    function source:hasFluid() return self.fluidAmount > 0 end
    function source:isTaintedWater() return self.tainted end
    function source:getObjectName() return "Rain Collector Barrel" end
    square.objects[#square.objects + 1] = source
    return source
end

function F.addStorage(id, category, items)
    local storage = { id = id, category = category, withdrawals = true }
    F.storages[#F.storages + 1] = storage
    F.storageContainers[id] = F.container(items)
    F.base.storages = F.storages
    return storage, F.storageContainers[id]
end

function F.job(operation, x, y, extras)
    extras = extras or {}
    local target = {
        operation = operation, zoneId = extras.zoneId or "zone:farm",
        x = x, y = y, z = 0, cropType = extras.cropType,
        emergency = extras.emergency, uses = extras.uses,
    }
    for key, value in pairs(extras) do target[key] = value end
    local job = {
        id = extras.id or "job:" .. tostring(#F.base.jobs + 1), type = "farm",
        state = extras.state or "active", reservedBy = extras.actorId,
        target = target, priority = 5,
    }
    F.base.jobs[#F.base.jobs + 1] = job
    return job
end

function F.reset()
    F.clock = F.clock + 1000
    F.squares, F.actors, F.receipts = {}, {}, {}
    F.storages, F.storageContainers = {}, {}
    F.nextReceipt, F.returnMode, F.restoreCalls = 1, "complete", 0
    F.navigationRequests, F.nativeStarts = {}, {}
    F.native = setmetatable({}, { __mode = "k" })
    F.nativeCancels, F.completedJobs, F.nativeStops = 0, 0, 0
    F.itemBudget = 256
    F.base = {
        zones = {
            { id = "zone:area", kind = "area", x1 = 0, y1 = 0, x2 = 30, y2 = 30, z = 0 },
            { id = "zone:farm", kind = "farm", x1 = 1, y1 = 1, x2 = 1, y2 = 1, z = 0 },
        },
        jobs = {}, storages = F.storages, farm = { recoveryCursor = 1 },
    }
end

U.nowMs = function() return F.clock end
U.config = function(key)
    local values = {
        farmScanSquaresPerSlice = 8, farmRecoveryPerPulse = 4,
        farmSeedSpareReserve = 2, campStorageItemBudget = F.itemBudget,
        farmDayStartHour = 6, farmDayEndHour = 21, farmActionMaxMs = 120000,
    }
    return values[key]
end
U.idOf = function(actor) return actor and actor.id or nil end
U.position = function(value) return value and value.x, value and value.y, value and value.z end
U.gridSquare = function(x, y, z)
    return F.squares[tostring(x) .. ":" .. tostring(y) .. ":" .. tostring(z or 0)]
end
U.squareOf = function(value) return value and (value.square or value) or nil end
U.inventory = function(actor) return actor and actor.inventory or nil end
U.inventoryItems = function(container, limit)
    local result = {}
    for index, item in ipairs(container and container.items or {}) do
        if index > (limit or 256) then break end
        result[#result + 1] = item
    end
    return result
end
U.inventoryContains = function(container, item)
    for _, value in ipairs(container and container.items or {}) do if value == item then return true end end
    return false
end
U.itemType = function(item) return item and item.fullType or "" end
U.modData = function(item) return item and item.modData or nil end
U.itemHasTag = function(item, tag) return item and item.tags[tostring(tag)] == true end
U.instanceOf = function() return false end
U.squareObjects = function(square, callback, limit)
    for index, object in ipairs(square and square.objects or {}) do
        if index > (limit or 64) then break end
        callback(object)
    end
end
U.objectLabel = function(object) return object and "Rain Collector Barrel" or "" end
U.distance = function(a, b)
    return math.max(math.abs((a.x or 0) - (b.x or 0)), math.abs((a.y or 0) - (b.y or 0)))
end
U.perkLevel = function() return 0 end
U.stop = function() return true end

function getGameTime()
    return { getTimeOfDay = function() return 12 end, getMonth = function() return 4 end }
end
function getSandboxOptions() return nil end

local foodType = { toString = function() return "Food" end }
ScriptManager = { instance = { getItem = function(_, itemType)
    if itemType == "Base.Tomato" then return { getItemType = function() return foodType end } end
    return nil
end } }
farming_vegetableconf = { props = { Tomato = {
    vegetableName = "Base.Tomato", seedTypes = { "Base.TomatoSeed" },
    sowMonth = { 5 }, bestMonth = { 5 }, riskMonth = {}, growBack = 2,
} } }
CFarmingSystem = { instance = { getLuaObjectOnSquare = function(_, square)
    return square and square.plant or nil
end } }

SC.BaseLife = {
    active = function() return F.base end,
    isInside = function(square)
        for _, zone in ipairs(F.base.zones) do
            if zone.kind == "area" and square and square.z == zone.z
                and square.x >= zone.x1 and square.x <= zone.x2
                and square.y >= zone.y1 and square.y <= zone.y2 then return true, zone end
        end
        return false
    end,
    storageRows = function(category)
        local result = {}
        for _, storage in ipairs(F.storages) do
            if storage.category == category then result[#result + 1] = storage end
        end
        return result
    end,
    resolveContainer = function(storage) return storage and F.storageContainers[storage.id] or nil end,
    availableCount = function(storage, itemType)
        local count = 0
        for _, item in ipairs(F.storageContainers[storage.id] and F.storageContainers[storage.id].items or {}) do
            if item.fullType == itemType then count = count + 1 end
        end
        return count
    end,
    enqueueJob = function(spec)
        spec.id, spec.state = "job:" .. tostring(#F.base.jobs + 1), "pending"
        F.base.jobs[#F.base.jobs + 1] = spec
        return true, spec
    end,
    job = function(id)
        for _, job in ipairs(F.base.jobs) do if job.id == id then return job end end
        return nil
    end,
    completeJob = function(id)
        local job = SC.BaseLife.job(id)
        if job then job.state, job.reservedBy = "completed", nil end
        F.completedJobs = F.completedJobs + 1
        return true, job
    end,
    resident = function() return nil end,
    allocateFarmReceipt = function(spec)
        local receipt = {}
        for key, value in pairs(spec) do receipt[key] = value end
        receipt.id = "farm-receipt:" .. tostring(F.nextReceipt)
        F.nextReceipt = F.nextReceipt + 1
        F.receipts[#F.receipts + 1] = receipt
        return true, receipt
    end,
    farmReceipt = function(id)
        for _, receipt in ipairs(F.receipts) do if receipt.id == id then return receipt end end
        return nil
    end,
    farmReceipts = function(jobId, includeTerminal)
        local result = {}
        for _, receipt in ipairs(F.receipts) do
            local terminal = receipt.phase == "returned" or receipt.phase == "delivered"
                or receipt.phase == "consumed"
            if (jobId == nil or receipt.jobId == jobId) and (includeTerminal or not terminal) then
                result[#result + 1] = receipt
            end
        end
        return result
    end,
    updateFarmReceipt = function(id, fields)
        local receipt = SC.BaseLife.farmReceipt(id)
        if not receipt then return false end
        for key, value in pairs(fields) do
            if key == "blocker" and value == false then receipt.blocker = nil
            else receipt[key] = value end
        end
        return true, receipt
    end,
    farmRecoveryCursor = function(value)
        if value ~= nil then F.base.farm.recoveryCursor = value end
        return F.base.farm.recoveryCursor
    end,
}

SC.Registry = { byId = function(id)
    local actor = F.actors[id]
    return actor and { actor = actor } or nil
end }
SC.WorkTransport = { hasRoom = function() return true end }
SC.BaseWork = {
    withdrawFromStorage = function(actor, _, storage, container, item)
        if not removeIdentity(container, item) then return false, "missing" end
        addIdentity(actor.inventory, item)
        return true, "base_supply_taken"
    end,
    returnToStorage = function(actor, _, storage, container, item)
        if F.returnMode == "pending" then return true, "base_storage_looting" end
        if not removeIdentity(actor.inventory, item) then return false, "missing" end
        addIdentity(container, item)
        return true, "base_supply_returned"
    end,
    restoreToStorage = function(actor, storage, container, item)
        F.restoreCalls = F.restoreCalls + 1
        if not removeIdentity(actor.inventory, item) then return false, "missing" end
        addIdentity(container, item)
        return true, "base_supply_returned"
    end,
}

SC.Navigation = {
    interactionTargets = function(_, square) return square and { square } or {} end,
    requestAny = function(actor, targets)
        local square = targets and targets[1]
        F.navigationRequests[#F.navigationRequests + 1] = { actor = actor, square = square }
        return true, "farm_approaching"
    end,
    cancel = function() return true end,
}

SC.NativeActions = {
    startFarm = function(actor, intent)
        F.nativeStarts[#F.nativeStarts + 1] = { actor = actor, intent = intent }
        F.native[actor] = { kind = "farm_" .. tostring(intent.operation), active = true }
        return true, "started"
    end,
    workKind = function(actor) return F.native[actor] and F.native[actor].kind or nil end,
    isWorkActive = function(actor) return F.native[actor] and F.native[actor].active == true or false end,
    finishWork = function(actor)
        if F.native[actor] and F.native[actor].active then return false, "active" end
        F.native[actor] = nil
        return true, "finished"
    end,
    cancelWork = function(actor, reason)
        F.nativeCancels = F.nativeCancels + 1
        F.native[actor] = nil
        return true, reason
    end,
    stopDirect = function()
        F.nativeStops = F.nativeStops + 1
        return true
    end,
}

F.reset()
