-- SPDX-License-Identifier: MIT

if type(require) == "function" then
    pcall(require, "SCBaseLife")
    pcall(require, "SCWorkTransport")
    pcall(require, "SCNativeList")
end

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.FarmWork = SC.FarmWork or {}
local FarmWork = SC.FarmWork

-- Policy lives here; world mutation does not. Every actual farm effect is a
-- stock Build 42 timed action queued through SCNativeActions.
FarmWork.ITEM_MARKER = "LF_FarmReceiptId"

local states = setmetatable({}, { __mode = "k" })
local scanState = {}
local knownPlots = {}
local knownBase = nil
local supplyScans = {}
local seedScans = {}
local metrics = {
    scans = 0, jobsQueued = 0, harvested = 0, watered = 0, sown = 0,
    replanted = 0, composted = 0, cured = 0, recovered = 0, blockers = 0,
    lastBlocker = nil,
}
local FARM_SPEECH = {
    ["farm.plot.start"] = { chance = 45, actorMs = 60000 },
    ["farm.sow.start"] = { chance = 45, actorMs = 60000 },
    ["farm.water.start"] = { chance = 30, actorMs = 60000 },
    ["farm.harvest.start"] = { chance = 55, actorMs = 45000 },
    ["farm.harvest.done"] = { chance = 40, actorMs = 45000 },
    ["farm.crop.ruined"] = { chance = 80, actorMs = 90000 },
    ["farm.crop.diseased"] = { chance = 70, actorMs = 90000 },
    ["farm.tool.trouble"] = { chance = 100, actorMs = 90000 },
}
local lastFarmSpeechAt = -math.huge

local CURES = {
    { field = "mildewLvl", cure = "Mildew", item = "GardeningSprayMilk" },
    { field = "fliesLvl", cure = "Flies", item = "GardeningSprayCigarettes" },
    { field = "slugsLvl", cure = "Slugs", item = "SlugRepellent" },
    { field = "aphidLvl", cure = "Aphids", item = "GardeningSprayAphids" },
}

local function U() return SC.GameplayUtil end
local function now() return U().nowMs() end
local function invoke(object, name, ...) return U().call(object, name, ...) end
local function config(key, fallback)
    local value = U() and tonumber(U().config(key)) or nil
    if value == nil or value ~= value then return fallback end
    return value
end
local function actorId(actor) return U().idOf(actor) end
local function noteOwnershipMutation()
    if SC.BaseLife and type(SC.BaseLife.noteWorkOwnershipMutation) == "function" then
        SC.BaseLife.noteWorkOwnershipMutation()
    end
end
local listSize = SC.NativeList.size
local listGet = SC.NativeList.get
local function pointKey(x, y, z) return tostring(x) .. ":" .. tostring(y) .. ":" .. tostring(z or 0) end
local function zoneContains(zone, x, y, z)
    return type(zone) == "table" and tonumber(zone.z) == tonumber(z)
        and x >= zone.x1 and x <= zone.x2 and y >= zone.y1 and y <= zone.y2
end

local function gameHour()
    if type(getGameTime) ~= "function" then return nil end
    local ok, gameTime = pcall(getGameTime)
    if not ok or not gameTime then return nil end
    local value, called = invoke(gameTime, "getTimeOfDay")
    return called and tonumber(value) or nil
end

local function daylight()
    local hour = gameHour()
    if hour == nil then return true end
    hour = hour % 24
    return hour >= config("farmDayStartHour", 6)
        and hour < config("farmDayEndHour", 21)
end

local function month()
    if type(getGameTime) ~= "function" then return nil end
    local ok, gameTime = pcall(getGameTime)
    if not ok or not gameTime then return nil end
    local value, called = invoke(gameTime, "getMonth")
    return called and tonumber(value) and tonumber(value) + 1 or nil
end

local function seasonsEnabled()
    if type(getSandboxOptions) ~= "function" then return false end
    local ok, options = pcall(getSandboxOptions)
    if not ok or not options then return false end
    local option, optionOk = invoke(options, "getOptionByName", "PlantGrowingSeasons")
    if not optionOk or not option then return false end
    local value, valueOk = invoke(option, "getValue")
    return valueOk and value == true
end

local function plantOn(square)
    local system = type(CFarmingSystem) == "table" and CFarmingSystem.instance or nil
    if not system or not square then return nil end
    local plant, ok = invoke(system, "getLuaObjectOnSquare", square)
    return ok and plant or nil
end

local function propsFor(cropType)
    local conf = type(farming_vegetableconf) == "table" and farming_vegetableconf.props or nil
    return type(conf) == "table" and conf[cropType] or nil
end

local function containsValue(values, wanted)
    for _, value in ipairs(type(values) == "table" and values or {}) do
        if value == wanted then return true end
    end
    return false
end

local function inSeason(props)
    if not seasonsEnabled() then return true end
    local current = month()
    return current ~= nil and containsValue(props and props.sowMonth, current)
end

local function edibleCrop(props)
    if type(props) ~= "table" or type(props.vegetableName) ~= "string" then return false end
    local managerOk, manager = pcall(function()
        return ScriptManager and ScriptManager.instance or nil
    end)
    if not managerOk then manager = nil end
    if not manager then return false end
    local script, scriptOk = invoke(manager, "getItem", props.vegetableName)
    if not scriptOk or not script then return false end
    local itemType, typeOk = invoke(script, "getItemType")
    if not typeOk or itemType == nil then return false end
    local name, nameOk = invoke(itemType, "toString")
    return string.lower(tostring(nameOk and name or itemType)) == "food"
end

local function cropTypes()
    local result = {}
    local conf = type(farming_vegetableconf) == "table" and farming_vegetableconf.props or nil
    for cropType, props in pairs(type(conf) == "table" and conf or {}) do
        if type(cropType) == "string" and edibleCrop(props) then result[#result + 1] = cropType end
    end
    table.sort(result)
    return result
end

local function seedTypes(cropType)
    local props = propsFor(cropType)
    if not props then return {} end
    if type(props.seedTypes) == "table" and #props.seedTypes > 0 then return props.seedTypes end
    return type(props.seedName) == "string" and { props.seedName } or {}
end

local function goodSeed(item)
    if item == nil then return false end
    if not U().instanceOf(item, "Food") then return true end
    for _, method in ipairs({ "isRotten", "isCooked", "isBurnt" }) do
        local value, ok = invoke(item, method)
        if ok and value == true then return false end
    end
    local fresh, freshOk = invoke(item, "isFresh")
    local base, baseOk = invoke(item, "getBaseHunger")
    local hunger, hungerOk = invoke(item, "getHungerChange")
    if baseOk and hungerOk and tonumber(base) and tonumber(hunger) then
        local whole, current = math.abs(base), math.abs(hunger)
        if freshOk and fresh == true and current < whole then return false end
        if freshOk and fresh ~= true and current < whole * 0.75 then return false end
    end
    if U().itemHasTag(item, "IS_CUTTING") and freshOk and fresh ~= true then return false end
    return true
end

local function seedPredicate(cropType)
    local accepted = {}
    for _, itemType in ipairs(seedTypes(cropType)) do accepted[itemType] = true end
    return function(item) return accepted[U().itemType(item)] == true and goodSeed(item) end
end

local function drainableUses(item)
    local value, ok = invoke(item, "getCurrentUses")
    if ok and tonumber(value) then return math.max(0, math.floor(value)) end
    value, ok = invoke(item, "getDrainableUsesFloat")
    return ok and tonumber(value) and math.max(0, math.floor(value)) or 0
end

local function waterUses(item)
    if not item then return 0 end
    local fluid, fluidOk = invoke(item, "getFluidContainer")
    if fluidOk and fluid then
        local primary = select(1, invoke(fluid, "getPrimaryFluid"))
        local kind = primary and select(1, invoke(primary, "getFluidTypeString")) or nil
        if kind == "Water" or kind == "TaintedWater" then
            local amount = select(1, invoke(fluid, "getAmount"))
            return math.max(0, math.floor((tonumber(amount) or 0) / 0.2))
        end
    end
    local source, sourceOk = invoke(item, "isWaterSource")
    return sourceOk and source == true and drainableUses(item) or 0
end

local function fillableWaterContainer(item)
    local fluid, ok = invoke(item, "getFluidContainer")
    if not ok or not fluid then return false end
    local amount = select(1, invoke(fluid, "getAmount"))
    local capacity = select(1, invoke(fluid, "getCapacity"))
    return tonumber(capacity) ~= nil and (tonumber(amount) or 0) + 0.19 < tonumber(capacity)
end

local function currentUses(item)
    return math.max(waterUses(item), drainableUses(item))
end

local function marker(item)
    local data = item and U().modData(item) or nil
    return type(data) == "table" and data[FarmWork.ITEM_MARKER] or nil
end

local function mark(item, receiptId)
    local data = item and U().modData(item) or nil
    if type(data) ~= "table" then return false end
    data[FarmWork.ITEM_MARKER] = receiptId
    return data[FarmWork.ITEM_MARKER] == receiptId
end

local function unmark(item, receiptId)
    local data = item and U().modData(item) or nil
    if type(data) ~= "table" then return false end
    if receiptId == nil or data[FarmWork.ITEM_MARKER] == receiptId then
        data[FarmWork.ITEM_MARKER] = nil
    end
    return data[FarmWork.ITEM_MARKER] == nil
end

function FarmWork.isItemProtected(item, actorOrId, operation)
    local receiptId = marker(item)
    if receiptId == nil then return false end
    if operation == "farm_return" or operation == "farm_deposit" then return false end
    local receipt = SC.BaseLife and SC.BaseLife.farmReceipt
        and SC.BaseLife.farmReceipt(receiptId) or nil
    return receipt == nil or (receipt.phase ~= "returned" and receipt.phase ~= "delivered"
        and receipt.phase ~= "consumed")
end

function FarmWork.isFarmingSupply(item)
    if not item then return false end
    local kind = string.lower(U().itemType(item))
    if U().itemHasTag(item, "DIG_PLOW") or U().itemHasTag(item, "COMPOST") then return true end
    if string.find(kind, "wateringcan", 1, true)
        or string.find(kind, "compostbag", 1, true)
        or string.find(kind, "gardeningspray", 1, true)
        or string.find(kind, "slugrepellent", 1, true)
        or string.find(kind, "seed", 1, true) then return true end
    return false
end

local function storageById(id)
    local base = SC.BaseLife and SC.BaseLife.active() or nil
    for _, storage in ipairs(base and base.storages or {}) do
        if storage.id == id then return storage end
    end
    return nil
end

local function protected(item, actor)
    if marker(item) ~= nil then return true end
    if SC.WorkTransport and type(SC.WorkTransport.foreignProtected) == "function" then
        local blocked = SC.WorkTransport.foreignProtected(item, actor)
        if blocked == true then return true end
    end
    return false
end

local function ensureBaseState()
    local base = SC.BaseLife and SC.BaseLife.active() or nil
    if base ~= knownBase then
        knownBase = base
        scanState, knownPlots, supplyScans, seedScans = {}, {}, {}, {}
    end
    return base
end

local function storageItemRows(categories)
    ensureBaseState()
    local rows = {}
    for _, category in ipairs(categories or {}) do
        for _, storage in ipairs(SC.BaseLife.storageRows(category, true)) do
            local container = SC.BaseLife.resolveContainer(storage)
            if container then rows[#rows + 1] = {
                key = tostring(category) .. ":" .. tostring(storage.id),
                storage = storage, container = container,
            } end
        end
    end
    return rows
end

local function containerItems(container)
    local items, okay = invoke(container, "getItems")
    if not okay then items = type(container) == "table" and (container.items or container) or nil end
    return items
end

local function rowItems(row)
    local items = containerItems(row.container)
    local count = listSize(items)
    return items, count
end

-- Bounded depth-first inventory census used by harvest checkpoints. Unlike
-- inventoryItems(..., 256), it reaches the complete root and nested bags while
-- yielding between slices. Any endpoint-size mutation restarts the pass so a
-- partial census is never mistaken for a complete baseline.
local function scanActorInventory(actor, state, cursorKey, visitor, resetAccumulator)
    local root = U().inventory(actor)
    if root == nil then return "failed", "farm_inventory_unavailable" end
    local function itemsFor(inventory)
        local items = containerItems(inventory)
        if items == nil then return nil, nil end
        return items, listSize(items)
    end
    local function begin()
        if resetAccumulator then resetAccumulator() end
        local items, size = itemsFor(root)
        if items == nil then return nil end
        local cursor = {
            root = root,
            stack = { { inventory = root, items = items, size = size, index = 0 } },
            endpoints = { { inventory = root, size = size } },
            seen = { [root] = true },
        }
        state[cursorKey] = cursor
        return cursor
    end
    local cursor = state[cursorKey]
    local restart = cursor == nil or cursor.root ~= root
    if not restart then
        for _, endpoint in ipairs(cursor.endpoints or {}) do
            local _, size = itemsFor(endpoint.inventory)
            if size == nil or size ~= endpoint.size then restart = true break end
        end
    end
    if restart then cursor = begin() end
    if cursor == nil then return "failed", "farm_inventory_items_unavailable" end
    local budget = math.max(1, math.floor(config("campStorageItemBudget", 80)))
    local visited = 0
    while #cursor.stack > 0 and visited < budget do
        local frame = cursor.stack[#cursor.stack]
        if frame.index >= frame.size then
            table.remove(cursor.stack)
        else
            local item, available = listGet(frame.items, frame.index)
            frame.index = frame.index + 1
            visited = visited + 1
            if not available or item == nil then
                state[cursorKey] = nil
                return "pending", "farm_inventory_changed"
            end
            local okay, reason = visitor(item)
            if okay == false then
                state[cursorKey] = nil
                return "failed", reason or "farm_inventory_identity_failed"
            end
            local nested, nestedOk = invoke(item, "getInventory")
            if nestedOk and nested ~= nil and not cursor.seen[nested] then
                local nestedItems, nestedSize = itemsFor(nested)
                if nestedItems == nil then
                    state[cursorKey] = nil
                    return "failed", "farm_nested_inventory_unavailable"
                end
                cursor.seen[nested] = true
                cursor.endpoints[#cursor.endpoints + 1] = {
                    inventory = nested, size = nestedSize,
                }
                cursor.stack[#cursor.stack + 1] = {
                    inventory = nested, items = nestedItems, size = nestedSize, index = 0,
                }
            end
        end
    end
    if #cursor.stack == 0 then
        state[cursorKey] = nil
        return "complete"
    end
    return "pending", "farm_inventory_scanning"
end

local function resetStorageScan(state)
    state.rowIndex, state.itemIndex = 1, 0
    state.container, state.containerSize = nil, nil
    state.rowContainers, state.rowSizes = nil, nil
    state.count = 0
    state.matches, state.matchOrder, state.seedBuckets = nil, nil, nil
end

-- Walk registered containers in bounded, resumable slices. Changes to any
-- registered endpoint identity or size restart the census so a partial pass
-- cannot become a false proof of absence or retain a partial count from a
-- container that was replaced beneath the same marker.
local function scanStorage(state, categories, visitor)
    local rows = storageItemRows(categories)
    local signatureParts, rowContainers, rowSizes = {}, {}, {}
    local endpointsChanged = state.rowContainers == nil or state.rowSizes == nil
    for index, row in ipairs(rows) do
        signatureParts[#signatureParts + 1] = row.key
        row.items, row.count = rowItems(row)
        rowContainers[index], rowSizes[index] = row.container, row.count
        if not endpointsChanged and (state.rowContainers[index] ~= row.container
            or state.rowSizes[index] ~= row.count) then endpointsChanged = true end
    end
    local signature = table.concat(signatureParts, "|")
    if state.rowsSignature ~= signature or endpointsChanged then
        resetStorageScan(state)
        state.rowsSignature = signature
    end
    state.rowContainers, state.rowSizes = rowContainers, rowSizes
    local budget = math.max(1, math.floor(config("campStorageItemBudget", 80)))
    local visited = 0
    while state.rowIndex <= #rows and visited < budget do
        local row = rows[state.rowIndex]
        local items, count = row.items, row.count
        state.container, state.containerSize = row.container, count
        if state.itemIndex >= count then
            state.rowIndex, state.itemIndex = state.rowIndex + 1, 0
            state.container, state.containerSize = nil, nil
        else
            local item, available = listGet(items, state.itemIndex)
            state.itemIndex = state.itemIndex + 1
            visited = visited + 1
            if available and visitor(item, row.storage, row.container, state) == true then
                return "found", row.storage, row.container, item
            end
        end
    end
    if state.rowIndex > #rows then return "complete" end
    return "pending"
end

local function findSupply(actor, predicate, categories, scanKey)
    ensureBaseState()
    local key = tostring(scanKey or predicate) .. ":" .. tostring(actorId(actor) or "audit")
    local state = supplyScans[key] or {}
    supplyScans[key] = state
    state.matches, state.matchOrder = state.matches or {}, state.matchOrder or {}
    local status = scanStorage(state, categories, function(candidate, row, container)
        if predicate(candidate) and not protected(candidate, actor) then
            state.matches, state.matchOrder = state.matches or {}, state.matchOrder or {}
            local itemType = U().itemType(candidate)
            local bucketKey = tostring(row.id) .. "\0" .. tostring(itemType)
            local bucket = state.matches[bucketKey]
            if not bucket then
                bucket = { storage = row, container = container, item = candidate,
                    itemType = itemType, count = 0 }
                state.matches[bucketKey] = bucket
                state.matchOrder[#state.matchOrder + 1] = bucketKey
            end
            bucket.count = bucket.count + 1
        end
        return false
    end)
    if status == "complete" then
        local selected
        for _, bucketKey in ipairs(state.matchOrder or {}) do
            local bucket = state.matches[bucketKey]
            local reserve = type(SC.BaseLife.storageReserve) == "function"
                and SC.BaseLife.storageReserve(bucket.storage, bucket.itemType) or 0
            if bucket.count > reserve then selected = bucket break end
        end
        supplyScans[key] = nil
        if selected then
            return selected.storage, selected.container, selected.item, "found"
        end
        return nil, nil, nil, "absent"
    end
    return nil, nil, nil, "scanning"
end

local function hasSupply(predicate, categories, scanKey)
    local storage, _, _, status = findSupply(nil, predicate, categories, scanKey)
    if storage then return true, "found" end
    if status == "scanning" then return nil, status end
    return false, status
end

local function seedCount(cropType)
    ensureBaseState()
    local accepted = {}
    for _, itemType in ipairs(seedTypes(cropType)) do accepted[itemType] = true end
    local state = seedScans[cropType] or { count = 0, seedBuckets = {} }
    seedScans[cropType] = state
    state.seedBuckets = state.seedBuckets or {}
    local status = scanStorage(state, { "farming" }, function(item, storage, _, cursor)
        local itemType = U().itemType(item)
        if accepted[itemType] and goodSeed(item) and not protected(item, nil) then
            local bucketKey = tostring(storage.id) .. "\0" .. tostring(itemType)
            cursor.seedBuckets = cursor.seedBuckets or {}
            local bucket = cursor.seedBuckets[bucketKey]
            if not bucket then
                bucket = { storage = storage, itemType = itemType, count = 0 }
                cursor.seedBuckets[bucketKey] = bucket
            end
            bucket.count = bucket.count + 1
        end
        return false
    end)
    if status ~= "complete" then return nil, false end
    local count = 0
    for _, bucket in pairs(state.seedBuckets or {}) do
        local reserve = type(SC.BaseLife.storageReserve) == "function"
            and SC.BaseLife.storageReserve(bucket.storage, bucket.itemType) or 0
        count = count + math.max(0, bucket.count - reserve)
    end
    seedScans[cropType] = nil
    return count, true
end

local function zones()
    local base, result = ensureBaseState(), {}
    for _, zone in ipairs(base and base.zones or {}) do
        if zone.kind == "farm" then result[#result + 1] = zone end
    end
    table.sort(result, function(a, b) return tostring(a.id) < tostring(b.id) end)
    return result
end

local function zoneById(id)
    for _, zone in ipairs(zones()) do if zone.id == id then return zone end end
    return nil
end

local function allZonesScanned()
    local rows = zones()
    if #rows == 0 then return false end
    for _, zone in ipairs(rows) do
        if not scanState[zone.id] or (scanState[zone.id].cycles or 0) < 1 then return false end
    end
    return true
end

local function nonGrowbackPlots(cropType)
    local count = 0
    local activeZones = zones()
    for _, plot in pairs(knownPlots) do
        local covered = false
        for _, zone in ipairs(activeZones) do
            if zoneContains(zone, plot.x, plot.y, plot.z) then covered = true break end
        end
        if covered and plot.cropType == cropType and plot.growBack ~= true then
            count = count + 1
        end
    end
    return count
end

local function harvestAllowed(plant)
    local cropType = plant and plant.typeOfSeed or nil
    local props = propsFor(cropType)
    if not props then return false end
    if props.growBack then return true end
    if plant.hasSeeds == true then return true end
    if not allZonesScanned() then return false end
    local reserve = nonGrowbackPlots(cropType) + config("farmSeedSpareReserve", 2)
    local seeds, complete = seedCount(cropType)
    return complete == true and seeds >= reserve
end

local function selectCrop(preferred)
    local function available(cropType)
        local props = propsFor(cropType)
        return props and edibleCrop(props) and inSeason(props)
            and hasSupply(seedPredicate(cropType), { "farming" }, "seed:" .. tostring(cropType))
    end
    if type(preferred) == "string" and available(preferred) then return preferred end
    local current, candidates = month(), {}
    for _, cropType in ipairs(cropTypes()) do
        if available(cropType) then
            local props = propsFor(cropType)
            local rank = containsValue(props.bestMonth, current) and 0
                or containsValue(props.riskMonth, current) and 2 or 1
            candidates[#candidates + 1] = { cropType = cropType, rank = rank }
        end
    end
    table.sort(candidates, function(a, b)
        if a.rank ~= b.rank then return a.rank < b.rank end
        return a.cropType < b.cropType
    end)
    return candidates[1] and candidates[1].cropType or nil
end

local function openJobAt(base, _, x, y, z)
    for _, job in ipairs(base.jobs or {}) do
        local target = job.target
        if job.type == "farm" and job.state ~= "completed" and job.state ~= "cancelled"
            and type(target) == "table"
            and target.x == x and target.y == y and target.z == z then return true end
    end
    return false
end

local function cureAt(plant)
    for _, cure in ipairs(CURES) do
        if (tonumber(plant[cure.field]) or 0) > 0 then return cure end
    end
    return nil
end

local function curePredicate(itemType)
    return function(item)
        local kind = U().itemType(item)
        return (kind == itemType or string.match(kind, "[^%.]+$") == itemType)
            and drainableUses(item) > 0
    end
end

local function waterContainerPredicate(item)
    return waterUses(item) > 0 or fillableWaterContainer(item)
end

local function inspectPlot(base, zone, square, x, y, z)
    local plant = plantOn(square)
    local key = pointKey(x, y, z)
    if not plant then knownPlots[key] = nil return nil end
    local props = propsFor(plant.typeOfSeed)
    knownPlots[key] = plant.typeOfSeed and {
        cropType = plant.typeOfSeed, growBack = props and props.growBack ~= nil or false,
        x = x, y = y, z = z,
    } or nil
    if openJobAt(base, zone.id, x, y, z) then return nil end
    local inside = SC.BaseLife.isInside(square) == true
    local isDay = daylight()
    if not inside and not isDay then return nil end

    local canHarvest = select(1, invoke(plant, "canHarvest")) == true
    if canHarvest and harvestAllowed(plant) then
        return { operation = "harvest", priority = 5, cropType = plant.typeOfSeed }
    end
    local water = tonumber(plant.waterLvl) or 0
    local needed = tonumber(plant.waterNeeded) or 0
    local emergency = needed > 0 and water < math.floor(needed / 1.30)
    if emergency and hasSupply(waterContainerPredicate,
        { "farming", "water" }, "water") then
        return { operation = "water", priority = 5, emergency = true,
            uses = math.max(1, math.ceil((math.min(100, needed
                + config("farmWaterBuffer", 20)) - water) / 10)) }
    end
    if isDay and plant.state == "seeded" then
        local cure = cureAt(plant)
        if cure and hasSupply(curePredicate(cure.item),
            { "farming" }, "cure:" .. tostring(cure.item)) then
            return { operation = "cure", priority = 4, cure = cure.cure,
                cureItem = cure.item, diseaseField = cure.field, uses = 1, minFarming = 3 }
        end
        if needed > 0 and water < needed
            and hasSupply(waterContainerPredicate,
                { "farming", "water" }, "water") then
            return { operation = "water", priority = 3, emergency = false,
                uses = math.max(1, math.ceil((math.min(100, needed
                    + config("farmWaterBuffer", 20)) - water) / 10)) }
        end
    end
    if not isDay then return nil end
    if plant.state == "dead" or plant.state == "rotten" or plant.state == "destroyed"
        or plant.state == "harvested" then
        local cropType = selectCrop(plant.typeOfSeed)
        if cropType and hasSupply(function(item)
            local broken, ok = invoke(item, "isBroken")
            return U().itemHasTag(item, "DIG_PLOW") and (not ok or broken ~= true)
        end, { "farming", "tools" }, "dig_tool") then
            return { operation = "replant", priority = 3, cropType = cropType }
        end
    elseif plant.state == "plow" then
        local cropType = selectCrop(nil)
        if cropType then return { operation = "sow", priority = 3, cropType = cropType } end
    elseif plant.state == "seeded" and plant.compost ~= true
        and (tonumber(plant.nbOfGrow) or 0) <= 3
        and hasSupply(function(item)
            return U().itemHasTag(item, "COMPOST") or string.find(
                string.lower(U().itemType(item)), "compostbag", 1, true) ~= nil
        end, { "farming" }, "compost") then
        return { operation = "compost", priority = 2 }
    end
    return nil
end

local function nextScannedSquare(zone)
    local state = scanState[zone.id] or { index = 0, cycles = 0 }
    scanState[zone.id] = state
    local width, height = zone.x2 - zone.x1 + 1, zone.y2 - zone.y1 + 1
    local total = math.max(1, width * height)
    if state.index >= total then state.index, state.cycles = 0, state.cycles + 1 end
    local offset = state.index
    state.index = state.index + 1
    local x, y = zone.x1 + (offset % width), zone.y1 + math.floor(offset / width)
    return U().gridSquare(x, y, zone.z), x, y, zone.z
end

local function missingBorrowWasConsumed(receipt)
    local job = SC.BaseLife and SC.BaseLife.job and SC.BaseLife.job(receipt.jobId) or nil
    local target = job and type(job.target) == "table" and job.target or nil
    if not target then return false end
    local square = U().gridSquare(target.x, target.y, target.z)
    local plant = square and plantOn(square) or nil
    if not plant then return false end
    local itemType = receipt.itemType
    if target.operation == "sow" or target.operation == "replant" then
        if not containsValue(seedTypes(target.cropType), itemType) then return false end
        return plant.state == "seeded" and plant.typeOfSeed == target.cropType
    end
    if target.operation == "compost" then
        return string.find(string.lower(itemType), "compost", 1, true) ~= nil
            and plant.compost == true
    end
    if target.operation == "cure" then
        local tail = string.match(itemType, "[^%.]+$")
        return tail == target.cureItem and target.diseaseField ~= nil
            and (tonumber(plant[target.diseaseField]) or 0) <= 0
    end
    if target.operation == "water" then
        local needed = tonumber(plant.waterNeeded) or 0
        return needed > 0 and (tonumber(plant.waterLvl) or 0) >= needed
    end
    return false
end

local function receiptActivelyOwned(receipt)
    local job = SC.BaseLife and SC.BaseLife.job and SC.BaseLife.job(receipt.jobId) or nil
    if receipt.phase ~= "recovery" and job
        and (job.state == "reserved" or job.state == "active")
        and job.reservedBy == receipt.actorId then return true end
    for actor, state in pairs(states) do
        if receipt.phase ~= "recovery" and actorId(actor) == receipt.actorId
            and state.jobId == receipt.jobId then
            if state.borrowed and state.borrowed.receiptId == receipt.id then return true end
            for _, output in ipairs(type(state.outputs) == "table" and state.outputs or {}) do
                if output.receiptId == receipt.id then return true end
            end
        end
    end
    return false
end

local function recoverPending(limit)
    local receipts = SC.BaseLife and SC.BaseLife.farmReceipts
        and SC.BaseLife.farmReceipts(nil, false) or {}
    if #receipts == 0 then
        if SC.BaseLife and SC.BaseLife.farmRecoveryCursor then SC.BaseLife.farmRecoveryCursor(1) end
        return
    end
    local cursor = SC.BaseLife and SC.BaseLife.farmRecoveryCursor
        and SC.BaseLife.farmRecoveryCursor() or 1
    cursor = ((math.max(1, tonumber(cursor) or 1) - 1) % #receipts) + 1
    local inspected = 0
    while inspected < math.min(limit, #receipts) do
        local receipt = receipts[cursor]
        cursor = cursor % #receipts + 1
        inspected = inspected + 1
        if not receiptActivelyOwned(receipt) then
        local record = SC.Registry and SC.Registry.byId and SC.Registry.byId(receipt.actorId) or nil
        local actor = type(record) == "table" and (record.actor or record) or nil
        local inventory = actor and U().inventory(actor) or nil
        local item
        for _, candidate in ipairs(inventory and U().inventoryItems(inventory, 256) or {}) do
            if marker(candidate) == receipt.id then item = candidate break end
        end
        if item then
            local storage, container
            if receipt.kind == "borrowed" then
                storage = storageById(receipt.sourceStorageId)
                container = storage and SC.BaseLife.resolveContainer(storage) or nil
            else
                local rows = type(SC.BaseLife.depositStorageRows) == "function"
                    and SC.BaseLife.depositStorageRows(receipt.destinationCategory or "food")
                    or SC.BaseLife.storageRows(receipt.destinationCategory or "food", false)
                for _, row in ipairs(rows) do
                    local candidate = SC.BaseLife.resolveContainer(row)
                    local room = candidate and (not SC.WorkTransport
                        or not SC.WorkTransport.hasRoom
                        or SC.WorkTransport.hasRoom(candidate, actor, item) ~= false)
                    if room then storage, container = row, candidate break end
                end
            end
            if storage and container and SC.BaseWork and SC.BaseWork.restoreToStorage then
                unmark(item, receipt.id)
                local restore = receipt.kind == "output"
                    and SC.BaseWork.restoreDepositToStorage or SC.BaseWork.restoreToStorage
                local moved, reason = restore(actor, storage, container, item)
                if moved == true then
                    SC.BaseLife.updateFarmReceipt(receipt.id, {
                        phase = receipt.kind == "output" and "delivered" or "returned",
                        blocker = false,
                    })
                    metrics.recovered = metrics.recovered + 1
                else
                    mark(item, receipt.id)
                    SC.BaseLife.updateFarmReceipt(receipt.id, { phase = "recovery", blocker = reason })
                end
            end
        elseif receipt.kind == "borrowed" and missingBorrowWasConsumed(receipt) then
            SC.BaseLife.updateFarmReceipt(receipt.id, { phase = "consumed", blocker = false })
            metrics.recovered = metrics.recovered + 1
        end
        end
    end
    if SC.BaseLife and SC.BaseLife.farmRecoveryCursor then SC.BaseLife.farmRecoveryCursor(cursor) end
end

function FarmWork.audit(base)
    base = base or (SC.BaseLife and SC.BaseLife.active())
    if not base then return false, "base_missing" end
    recoverPending(math.max(1, math.floor(config("farmRecoveryPerPulse", 4))))
    local farmZones = zones()
    if #farmZones == 0 then return false, "farm_zone_missing" end
    local budget = math.max(1, math.floor(config("farmScanSquaresPerSlice", 16)))
    local best
    for _ = 1, budget do
        -- metrics.scans is already advanced once per square. Adding the loop
        -- index again makes every pass hit the same zone when there are two.
        local zone = farmZones[(metrics.scans % #farmZones) + 1]
        local square, x, y, z = nextScannedSquare(zone)
        metrics.scans = metrics.scans + 1
        if square then
            local candidate = inspectPlot(base, zone, square, x, y, z)
            if candidate and (not best or candidate.priority > best.priority) then
                candidate.zoneId, candidate.x, candidate.y, candidate.z = zone.id, x, y, z
                best = candidate
            end
        end
    end
    if not best then return false, "farm_scan_no_work" end
    local spec = { type = "farm", priority = best.priority, target = best }
    local queued, job = SC.BaseLife.enqueueJob(spec)
    if queued == true then metrics.jobsQueued = metrics.jobsQueued + 1 end
    return queued, job
end

local function stateFor(actor, job)
    local state = states[actor]
    if not state or state.jobId ~= job.id then
        state = { jobId = job.id, stage = job.target.operation == "replant" and "plow"
            or job.target.operation, phase = "starting" }
        states[actor] = state
    end
    return state
end

local function threatNearby(actor, runtime)
    local source = type(runtime) == "table" and runtime
        or (U().peekActorState and U().peekActorState(actor)) or nil
    local snapshot = type(source) == "table" and source.snapshot or nil
    local threats = type(snapshot) == "table" and snapshot.threats or nil
    if type(threats) ~= "table" then return false end
    local radius = config("productionLoudThreatRadius", 20)
    for index = 1, math.min(#threats, 32) do
        if (tonumber(threats[index].distanceSq) or math.huge) <= radius * radius then return true end
    end
    return false
end

-- Farm remarks are flavor only: a rejected or skipped line never gates the
-- native action. The existing danger snapshot, actor quiet time, deterministic
-- chance and one party cooldown keep field work from becoming a speech loop.
local function speak(actor, topic, arguments, salt, runtime)
    local spec = FARM_SPEECH[topic]
    if not spec or not SC.Dialogue or type(SC.Dialogue.say) ~= "function" then
        return false, "farm_speech_unavailable"
    end
    if threatNearby(actor, runtime) then return false, "farm_speech_unsafe" end
    local current = now()
    if current - lastFarmSpeechAt < config("farmSpeechGroupCooldownMs", 12000) then
        return false, "farm_speech_group_cooldown"
    end
    if spec.actorMs > 0 and type(SC.Dialogue.lastSpokenAt) == "function"
        and current - (tonumber(SC.Dialogue.lastSpokenAt(actor)) or -math.huge)
            < spec.actorMs then return false, "farm_speech_actor_cooldown" end
    local key = tostring(actorId(actor)) .. ":" .. topic .. ":" .. tostring(salt or current)
    if U().stableHash(key) % 100 >= spec.chance then return false, "farm_speech_chance" end
    local spoken, line = SC.Dialogue.say(actor, topic, nil, arguments, {
        recentLimit = 4, salt = key,
    })
    if spoken == true then lastFarmSpeechAt = current end
    return spoken == true, line
end

local function farmingRole(actor)
    local resident = SC.BaseLife.resident(actorId(actor))
    return resident and resident.role == "farmer"
end

local function approach(actor, square)
    local ax, ay, az = U().position(actor)
    local sx, sy, sz = U().position(square)
    if ax and sx and math.floor(az or 0) == math.floor(sz or 0)
        and math.max(math.abs(math.floor(ax) - math.floor(sx)),
            math.abs(math.floor(ay) - math.floor(sy))) == 1 then
        return "arrived", "farm_in_range"
    end
    if not SC.Navigation or type(SC.Navigation.requestAny) ~= "function" then
        return "failed", "navigation_unavailable"
    end
    local targets = SC.Navigation.interactionTargets(actor, square, { maximum = 8 })
    if #targets == 0 then return "failed", "farm_approach_missing" end
    local accepted, reason = SC.Navigation.requestAny(actor, targets, "walk", {
        action = "move_to_farm_plot", targetSquare = square, arrivalDistance = 0.8,
        workCampOnly = true, workReach = SC.BaseLife.isInside(square) ~= true,
    })
    if accepted ~= true then return "failed", reason or "farm_approach_failed" end
    return "pending", reason or "farm_approaching"
end

local function digTool(item)
    local broken, brokenOk = invoke(item, "isBroken")
    return U().itemHasTag(item, "DIG_PLOW") and (not brokenOk or broken ~= true)
end

local function compost(item)
    return U().itemHasTag(item, "COMPOST")
        or string.find(string.lower(U().itemType(item)), "compostbag", 1, true) ~= nil
end

local function operationSupply(target, operation)
    if operation == "plow" then return digTool, { "farming", "tools" }, "dig_tool" end
    if operation == "sow" then return seedPredicate(target.cropType), { "farming" },
        "seed:" .. tostring(target.cropType) end
    if operation == "water" then return waterContainerPredicate,
        { "farming", "water" }, "water" end
    if operation == "compost" then return compost, { "farming" }, "compost" end
    if operation == "cure" then return curePredicate(target.cureItem), { "farming" },
        "cure:" .. tostring(target.cureItem) end
    return nil, nil
end

local function allocateReceipt(actor, job, kind, item, storage, category)
    local nativeId = select(1, invoke(item, "getID"))
    local okay, receipt = SC.BaseLife.allocateFarmReceipt({
        jobId = job.id, actorId = actorId(actor), kind = kind,
        itemType = U().itemType(item), nativeId = nativeId,
        sourceStorageId = storage and storage.id or nil,
        destinationCategory = category,
        phase = kind == "output" and "carried" or "borrowed",
    })
    if okay ~= true then return nil, receipt end
    if not mark(item, receipt.id) then
        SC.BaseLife.updateFarmReceipt(receipt.id, { phase = "quarantined", blocker = "item_marker_failed" })
        return nil, "item_marker_failed"
    end
    return receipt
end

local function borrowSupply(actor, baseState, job, state, predicate, categories, scanKey)
    local pending = state.fetch
    if pending and (not U().inventoryContains(pending.container, pending.item)
        or not predicate(pending.item)) then state.fetch, pending = nil, nil end
    if not pending then
        local storage, container, item, scanStatus = findSupply(
            actor, predicate, categories, scanKey)
        if not storage then
            if scanStatus == "scanning" then return true, "farm_supply_scanning", false end
            if scanKey == "dig_tool" and state.toolSpeechAttempted ~= true then
                state.toolSpeechAttempted = true
                speak(actor, "farm.tool.trouble", nil, tostring(job.id) .. ":tool")
            end
            return false, "farm_supply_missing", true
        end
        pending = { storage = storage, container = container, item = item }
        state.fetch = pending
    end
    local moved, reason = SC.BaseWork.withdrawFromStorage(actor, baseState,
        pending.storage, pending.container, pending.item)
    if moved == true and reason == "base_supply_taken" then
        local receipt, receiptReason = allocateReceipt(actor, job, "borrowed", pending.item,
            pending.storage, nil)
        if not receipt then
            SC.BaseWork.restoreToStorage(actor, pending.storage, pending.container, pending.item)
            state.fetch = nil
            return false, receiptReason, true
        end
        state.borrowed = {
            storage = pending.storage, container = pending.container,
            item = pending.item, receiptId = receipt.id,
        }
        state.fetch = nil
        return true, "farm_supply_taken"
    end
    return moved == true, reason, moved ~= true and reason ~= "base_storage_looting"
end

local function consumeOrReturn(actor, baseState, state)
    local borrowed = state.borrowed
    if not borrowed then return true, "farm_supply_settled" end
    local inventory = U().inventory(actor)
    if not inventory or not U().inventoryContains(inventory, borrowed.item) then
        SC.BaseLife.updateFarmReceipt(borrowed.receiptId, { phase = "consumed", blocker = false })
        state.borrowed = nil
        return true, "farm_supply_consumed"
    end
    unmark(borrowed.item, borrowed.receiptId)
    local moved, reason = SC.BaseWork.returnToStorage(actor, baseState,
        borrowed.storage, borrowed.container, borrowed.item)
    if moved == true and reason == "base_supply_returned" then
        SC.BaseLife.updateFarmReceipt(borrowed.receiptId, { phase = "returned", blocker = false })
        state.borrowed = nil
        return true, "farm_supply_returned"
    end
    mark(borrowed.item, borrowed.receiptId)
    if moved == true then
        SC.BaseLife.updateFarmReceipt(borrowed.receiptId, {
            phase = "borrowed", blocker = false,
        })
        return false, reason or "farm_supply_return_pending", true
    end
    SC.BaseLife.updateFarmReceipt(borrowed.receiptId, { phase = "borrowed", blocker = reason })
    return false, reason, false
end

local function plantSnapshot(plant, operation)
    if operation == "water" then return tonumber(plant.waterLvl) or 0 end
    if operation == "cure" then return tonumber(plant._lfDiseaseBefore) or 0 end
    if operation == "compost" then return plant.compost == true end
    if operation == "harvest" then return select(1, invoke(plant, "canHarvest")) == true end
    return plant.state
end

local function actionProof(square, target, work)
    local plant = plantOn(square)
    if work.operation == "plow" then return plant and plant.state == "plow" end
    if work.operation == "sow" then
        return plant and plant.state == "seeded" and plant.typeOfSeed == target.cropType
    end
    if work.operation == "water" then
        return plant and (tonumber(plant.waterLvl) or 0) > (tonumber(work.before) or 0)
    end
    if work.operation == "compost" then return plant and plant.compost == true end
    if work.operation == "cure" then
        return plant and (tonumber(plant[target.diseaseField]) or 0) < (tonumber(work.before) or 0)
    end
    if work.operation == "harvest" then
        return plant == nil or select(1, invoke(plant, "canHarvest")) ~= true
    end
    if work.operation == "fill_water" then return waterUses(work.item) > (work.before or 0) end
    return false
end

local function seedOutput(item)
    local itemType = U().itemType(item)
    for _, cropType in ipairs(cropTypes()) do
        if containsValue(seedTypes(cropType), itemType) then return cropType end
    end
    return nil
end

local function outputCategory(item)
    local cropType = seedOutput(item)
    if cropType then
        local reserve = nonGrowbackPlots(cropType) + config("farmSeedSpareReserve", 2)
        local count, complete = seedCount(cropType)
        if string.find(string.lower(U().itemType(item)), "seed", 1, true)
            or complete ~= true or count < reserve then return "farming" end
    end
    local category = select(1, invoke(item, "getCategory"))
    return string.lower(tostring(category or "")) == "food" and "food" or "output"
end

local function plausibleHarvestOutput(item, target)
    local itemType = U().itemType(item)
    local props = propsFor(target and target.cropType)
    if props and itemType == props.vegetableName then return true end
    return containsValue(seedTypes(target and target.cropType), itemType)
end

local function encodeIdentitySet(values)
    local rows = {}
    for key, present in pairs(type(values) == "table" and values or {}) do
        if present == true then rows[#rows + 1] = "|" .. tostring(key) end
    end
    table.sort(rows)
    return table.concat(rows) .. (#rows > 0 and "|" or "")
end

local function prepareHarvestBaseline(actor, state)
    state.harvestBaseline = state.harvestBaseline or {}
    local status, reason = scanActorInventory(actor, state, "harvestBaselineCursor",
        function(item)
            local id = type(U().itemStableId) == "function"
                and U().itemStableId(item, true) or nil
            if id == nil then return false, "farm_item_identity_unavailable" end
            state.harvestBaseline[id] = true
            return true
        end,
        function() state.harvestBaseline = {} end)
    if status == "pending" then return nil, reason or "farm_harvest_snapshotting" end
    if status ~= "complete" then return false, reason end
    state.harvestBaselineEncoded = encodeIdentitySet(state.harvestBaseline)
    return true, nil, state.harvestBaseline
end

local function collectHarvest(actor, job, state, snapshot)
    if job.target.harvestActorId ~= actorId(actor) then
        return false, job.target.harvestActorId and "farm_harvest_actor_mismatch"
            or "farm_harvest_actor_unknown"
    end
    if type(snapshot) ~= "table" then return false, "farm_harvest_baseline_unresolved" end
    if state.harvestCandidatesReady ~= true then
        local status, scanReason = scanActorInventory(actor, state, "harvestCollectCursor",
            function(item)
                local stableId = type(U().itemStableId) == "function"
                    and U().itemStableId(item, true) or nil
                if stableId == nil then return false, "farm_item_identity_unavailable" end
                local receiptId = marker(item)
                local existing = receiptId and SC.BaseLife.farmReceipt
                    and SC.BaseLife.farmReceipt(receiptId) or nil
                if existing and existing.kind == "output" and existing.jobId == job.id
                    and existing.actorId == actorId(actor) then
                    state.harvestCandidates[#state.harvestCandidates + 1] = {
                        item = item, receipt = existing,
                    }
                elseif not snapshot[stableId] and receiptId == nil
                    and plausibleHarvestOutput(item, job.target) then
                    state.harvestCandidates[#state.harvestCandidates + 1] = { item = item }
                end
                return true
            end,
            function()
                state.harvestCandidates = {}
                state.harvestCandidateIndex = 1
            end)
        if status == "pending" then return nil, scanReason or "farm_harvest_collecting" end
        if status ~= "complete" then return false, scanReason end
        state.harvestCandidatesReady = true
    end
    state.outputs = state.outputs or {}
    local outputIds = {}
    for _, output in ipairs(state.outputs) do outputIds[output.receiptId] = true end
    local candidates = state.harvestCandidates or {}
    local index = math.max(1, math.floor(tonumber(state.harvestCandidateIndex) or 1))
    while index <= #candidates do
        local candidate = candidates[index]
        local existing = candidate.receipt
        if existing then
            if not outputIds[existing.id] then
                state.outputs[#state.outputs + 1] = {
                    item = candidate.item, receiptId = existing.id,
                    category = existing.destinationCategory or outputCategory(candidate.item),
                }
                outputIds[existing.id] = true
            end
        else
            local category = outputCategory(candidate.item)
            local receipt, reason = allocateReceipt(
                actor, job, "output", candidate.item, nil, category)
            if not receipt then
                state.harvestCandidateIndex = index
                state.collectingHarvest = true
                if reason == "farm_receipt_limit" then
                    return nil, "farm_harvest_receipt_wait"
                end
                return false, reason
            end
            state.outputs[#state.outputs + 1] = {
                item = candidate.item, receiptId = receipt.id, category = category,
            }
            outputIds[receipt.id] = true
        end
        index = index + 1
        state.harvestCandidateIndex = index
    end
    state.harvestCandidates, state.harvestCandidateIndex = nil, nil
    state.harvestCandidatesReady, state.collectingHarvest = nil, nil
    job.target.harvestStarted = nil
    job.target.harvestBeforeIds = nil
    job.target.harvestBeforeStableIds = nil
    job.target.harvestBaselineVersion = nil
    job.target.harvestActorId = nil
    noteOwnershipMutation()
    return true
end

local function restoredHarvestSnapshot(actor, target)
    if target.harvestActorId ~= actorId(actor) then
        return nil, target.harvestActorId and "farm_harvest_actor_mismatch"
            or "farm_harvest_actor_unknown"
    end
    if tonumber(target.harvestBaselineVersion) ~= 1
        or type(target.harvestBeforeStableIds) ~= "string" then
        return nil, "farm_harvest_baseline_unresolved"
    end
    local before = {}
    for stableId in string.gmatch(target.harvestBeforeStableIds, "|([^|]+)") do
        before[stableId] = true
    end
    return before
end

local function depositOutputs(actor, baseState, state)
    local output = state.outputs and state.outputs[1] or nil
    if not output then state.outputs = nil return true, "farm_outputs_deposited" end
    local storage, container
    local rows = type(SC.BaseLife.depositStorageRows) == "function"
        and SC.BaseLife.depositStorageRows(output.category)
        or SC.BaseLife.storageRows(output.category, false)
    for _, row in ipairs(rows) do
        local candidate = SC.BaseLife.resolveContainer(row)
        local room = candidate and (not SC.WorkTransport or not SC.WorkTransport.hasRoom
            or SC.WorkTransport.hasRoom(candidate, actor, output.item) ~= false)
        if room then storage, container = row, candidate break end
    end
    if not storage then return false, "farm_output_storage_missing", true end
    unmark(output.item, output.receiptId)
    local deposit = SC.BaseWork.depositToStorage or SC.BaseWork.returnToStorage
    local moved, reason = deposit(actor, baseState, storage, container, output.item)
    if moved == true and reason == "base_supply_returned" then
        SC.BaseLife.updateFarmReceipt(output.receiptId, { phase = "delivered", blocker = false })
        table.remove(state.outputs, 1)
        return true, "farm_output_deposited"
    end
    mark(output.item, output.receiptId)
    if moved == true then
        SC.BaseLife.updateFarmReceipt(output.receiptId, { phase = "depositing", blocker = false })
        return true, reason
    end
    SC.BaseLife.updateFarmReceipt(output.receiptId, { phase = "carried", blocker = reason })
    return false, reason
end

local function waterSourceObjects(square)
    local result = {}
    U().squareObjects(square, function(object)
        local amount, amountOk = invoke(object, "getFluidAmount")
        local has, hasOk = invoke(object, "hasFluid")
        if (amountOk and (tonumber(amount) or 0) > 0) or (hasOk and has == true) then
            result[#result + 1] = object
        end
    end, 64)
    return result
end

local function waterSourceUsable(object)
    if not object or not U().squareOf(object) then return false end
    local amount, amountOk = invoke(object, "getFluidAmount")
    local has, hasOk = invoke(object, "hasFluid")
    return amountOk and (tonumber(amount) or 0) > 0 or hasOk and has == true
end

local function waterSearchZones(activeZone)
    local base, result = SC.BaseLife.active(), { activeZone }
    for _, zone in ipairs(base and base.zones or {}) do
        if zone.kind == "area" then result[#result + 1] = zone end
    end
    return result
end

local function findWaterSource(state, activeZone, emergency)
    local rows = waterSearchZones(activeZone)
    state.waterCursor = state.waterCursor or { zone = 1, index = 0 }
    for _ = 1, math.max(1, math.floor(config("farmScanSquaresPerSlice", 16))) do
        local row = rows[state.waterCursor.zone]
        if not row then
            state.waterCursor = { zone = 1, index = 0 }
            if emergency and state.cleanWaterCandidate then
                local candidate = state.cleanWaterCandidate
                state.cleanWaterCandidate = nil
                return candidate
            end
            state.cleanWaterCandidate = nil
            return nil, "water_source_missing"
        end
        local width, total = row.x2 - row.x1 + 1,
            (row.x2 - row.x1 + 1) * (row.y2 - row.y1 + 1)
        if state.waterCursor.index >= total then
            state.waterCursor.zone, state.waterCursor.index = state.waterCursor.zone + 1, 0
        else
            local offset = state.waterCursor.index
            state.waterCursor.index = offset + 1
            local square = U().gridSquare(row.x1 + offset % width,
                row.y1 + math.floor(offset / width), row.z)
            for _, object in ipairs(square and waterSourceObjects(square) or {}) do
                local tainted, taintedOk = invoke(object, "isTaintedWater")
                local label = string.lower(U().objectLabel(object))
                local preferred = taintedOk and tainted == true
                    or string.find(label, "rain", 1, true) ~= nil
                if preferred then return object end
                if emergency and not state.cleanWaterCandidate then
                    state.cleanWaterCandidate = object
                end
            end
        end
    end
    return nil, "water_source_scanning"
end

local function startAction(actor, job, state, square, plant, operation)
    local inventorySnapshot
    if operation == "harvest" then
        local prepared, prepareReason, snapshot = prepareHarvestBaseline(actor, state)
        if prepared == nil then return true, prepareReason or "farm_harvest_snapshotting" end
        if prepared ~= true then return false, prepareReason end
        inventorySnapshot = snapshot
    end
    local supervisor = SC.ActionSupervisor
    if type(supervisor) ~= "table" or type(supervisor.begin) ~= "function" then
        return false, "farm_supervisor_unavailable"
    end
    local token, ownerReason = supervisor.begin(actor, {
        owner = "work", action = "farm_" .. tostring(operation),
        priority = supervisor.Priority and supervisor.Priority.WORK or 150,
        targetKey = tostring(job.id) .. ":" .. tostring(operation),
        targetLabel = "farm plot", ignoreRetry = true,
        interruptible = true,
    })
    if token == nil then return false, ownerReason or "farm_actor_owned" end
    local harvestPrepared = false
    local function fail(reason, detail)
        if harvestPrepared then
            job.target.harvestStarted, job.target.harvestBeforeIds = nil, nil
            job.target.harvestBeforeStableIds, job.target.harvestBaselineVersion = nil, nil
            job.target.harvestActorId = nil
            state.harvestBaseline, state.harvestBaselineEncoded = nil, nil
            state.harvestBaselineCursor = nil
            noteOwnershipMutation()
            harvestPrepared = false
        end
        if type(supervisor.isCurrent) == "function" and supervisor.isCurrent(token) then
            supervisor.fail(token, reason or "farm_start_failed", detail)
        end
        return false, reason
    end
    local target, item = job.target, state.borrowed and state.borrowed.item or nil
    local before
    if operation == "water" then before = tonumber(plant.waterLvl) or 0
    elseif operation == "cure" then before = tonumber(plant[target.diseaseField]) or 0
    elseif operation == "fill_water" then before = waterUses(item)
    else before = plantSnapshot(plant, operation) end
    if operation == "harvest" then
        target.cropType = target.cropType or (plant and plant.typeOfSeed)
        job.target.harvestStarted = true
        job.target.harvestBeforeIds = nil
        job.target.harvestBeforeStableIds = state.harvestBaselineEncoded
        job.target.harvestBaselineVersion = 1
        job.target.harvestActorId = actorId(actor)
        -- Bind the complete checkpoint to the actor inventory generation
        -- before the native harvest is allowed to mutate that inventory.
        noteOwnershipMutation()
        harvestPrepared = true
    end
    if SC.Navigation and type(SC.Navigation.cancel) == "function" then
        pcall(SC.Navigation.cancel, actor, "farm_interaction")
    end
    local stopped, stopReason
    if SC.NativeActions and type(SC.NativeActions.stopDirect) == "function" then
        local callOk
        callOk, stopped, stopReason = pcall(SC.NativeActions.stopDirect, actor)
        if not callOk then return fail("farm_stop_failed", stopped) end
    else stopped, stopReason = U().stop(actor), "farm_stopped" end
    if stopped ~= true then return fail(stopReason or "farm_stop_failed") end
    local transitioned, transitionReason = supervisor.transition(token, "committing")
    if transitioned ~= true then return fail(transitionReason or "farm_commit_rejected") end
    local started, reason = supervisor.commit(token, function()
        return SC.NativeActions.startFarm(actor, {
            operation = operation, item = item, square = square, plant = plant,
            object = state.waterSource, cropType = target.cropType,
            uses = operation == "water" and math.min(target.uses or 1, waterUses(item))
                or target.uses or 1,
            cure = target.cure, farmerRole = farmingRole(actor),
        })
    end)
    if started ~= true then
        if operation == "harvest" then
            job.target.harvestStarted, job.target.harvestBeforeIds = nil, nil
            job.target.harvestBeforeStableIds, job.target.harvestBaselineVersion = nil, nil
            job.target.harvestActorId = nil
            state.harvestBaseline, state.harvestBaselineEncoded = nil, nil
            state.harvestBaselineCursor = nil
            noteOwnershipMutation()
            harvestPrepared = false
        end
        return fail(reason or "farm_start_failed")
    end
    local verifying, verifyReason = supervisor.transition(token, "verifying")
    if verifying ~= true then return fail(verifyReason or "farm_verify_rejected") end
    local completed, completeReason = supervisor.complete(token, "farm_native_started", {
        operation = operation, jobId = job.id,
    })
    if completed ~= true then return false, completeReason or "farm_owner_release_failed" end
    state.work = {
        operation = operation, before = before, item = item,
        startedAt = now(), inventorySnapshot = inventorySnapshot,
    }
    state.harvestBaseline, state.harvestBaselineEncoded = nil, nil
    state.harvestBaselineCursor = nil
    state.phase = "working"
    local speechTopic = operation == "plow" and "farm.plot.start"
        or operation == "sow" and "farm.sow.start"
        or operation == "water" and "farm.water.start"
        or operation == "harvest" and "farm.harvest.start"
        or operation == "cure" and "farm.crop.diseased" or nil
    if speechTopic then
        speak(actor, speechTopic, nil,
            tostring(job.id) .. ":" .. tostring(operation) .. ":start")
    end
    return true, "farm_" .. operation .. "_started"
end

local function finishAction(actor, baseState, job, state, square)
    local work = state.work
    local kind = SC.NativeActions.workKind and SC.NativeActions.workKind(actor) or nil
    if SC.NativeActions.isWorkActive(actor) == true and kind == "farm_" .. work.operation then
        if now() - work.startedAt > config("farmActionMaxMs", 120000) then
            SC.NativeActions.cancelWork(actor, "farm_action_timeout")
            state.work = nil
            return false, "farm_action_timeout", true
        end
        return true, "farm_" .. work.operation .. "_active"
    end
    local finished, reason = SC.NativeActions.finishWork(actor)
    if finished ~= true then return false, reason or "farm_action_finish_failed", true end
    state.work = nil
    if not actionProof(square, job.target, work) then return false, "farm_action_incomplete", true end

    if work.operation == "harvest" then
        local collected, collectReason = collectHarvest(actor, job, state, work.inventorySnapshot)
        if collected == nil then
            state.stage = "collecting_harvest"
            return true, collectReason or "farm_harvest_collecting"
        end
        if collected ~= true then return false, collectReason, true end
        metrics.harvested = metrics.harvested + 1
        speak(actor, "farm.harvest.done", nil, tostring(job.id) .. ":harvest:done")
    elseif work.operation == "plow" and job.target.operation == "replant" then
        state.stage, state.afterReturn = "returning", "sow"
        return true, "farm_plowed"
    elseif work.operation == "fill_water" then
        state.waterSource, state.waterCursor, state.stage = nil, nil, "water"
        return true, "farm_water_container_filled"
    elseif work.operation == "water" then metrics.watered = metrics.watered + 1
    elseif work.operation == "sow" then
        metrics.sown = metrics.sown + 1
        if job.target.operation == "replant" then metrics.replanted = metrics.replanted + 1 end
    elseif work.operation == "compost" then metrics.composted = metrics.composted + 1
    elseif work.operation == "cure" then metrics.cured = metrics.cured + 1 end
    state.stage = "returning"
    state.afterReturn = "complete"
    return true, "farm_action_complete"
end

function FarmWork.jobModifier(actorIdValue, job, resident, record)
    local target = type(job.target) == "table" and job.target or nil
    if target and target.harvestStarted == true and target.harvestActorId ~= nil
        and target.harvestActorId ~= actorIdValue then return 0, false end
    local actor = type(record) == "table" and (record.actor or record) or nil
    local level = actor and U().perkLevel(actor, "Farming", 0) or 0
    local minimum = type(job.target) == "table" and tonumber(job.target.minFarming) or 0
    if level < minimum then return 0, false end
    return level * 3, true
end

function FarmWork.update(actor, baseState, job, runtime)
    if not SC.NativeActions or type(SC.NativeActions.startFarm) ~= "function" then
        return false, "native_farming_unavailable", true
    end
    local target, zone = type(job.target) == "table" and job.target or {},
        zoneById(type(job.target) == "table" and job.target.zoneId or nil)
    if not zone then return false, "farm_zone_missing", true end
    local square = U().gridSquare(target.x, target.y, target.z)
    if not square then return false, "farm_target_unloaded", true end
    local state = stateFor(actor, job)
    if SC.BaseLife.isInside(square) ~= true and not daylight() then
        -- Do not begin or continue remote farm work after dark. If the native
        -- action has just completed, reconcile it first so harvest output is
        -- not orphaned. Otherwise cancel it and let the ordinary return stage
        -- bring exact borrowed stock/output back into camp.
        local nightPlant = plantOn(square)
        if target.operation == "harvest" and target.harvestStarted == true
            and (not nightPlant or select(1, invoke(nightPlant, "canHarvest")) ~= true) then
            local snapshot, snapshotReason = restoredHarvestSnapshot(actor, target)
            if not snapshot then return false, snapshotReason, true end
            local collected, collectReason = collectHarvest(actor, job, state, snapshot)
            if collected == nil then return true, collectReason end
            if collected ~= true then return false, collectReason, true end
            state.stage, state.afterReturn = "returning", "complete"
        end
        if state.work then
            local kind = SC.NativeActions.workKind and SC.NativeActions.workKind(actor) or nil
            if SC.NativeActions.isWorkActive(actor) == true
                and kind == "farm_" .. tostring(state.work.operation) then
                SC.NativeActions.cancelWork(actor, "farm_outside_night")
                state.work = nil
            else
                return finishAction(actor, baseState, job, state, square)
            end
        end
        if not state.outputs
            and not (state.stage == "returning" and state.afterReturn == "complete") then
            state.stage, state.afterReturn = "returning", "blocked"
            state.blocker = "farm_outside_night"
        end
    end
    local farmThreat = threatNearby(actor, runtime)
    if farmThreat then
        if state.work and SC.NativeActions.workKind(actor)
            and string.sub(SC.NativeActions.workKind(actor), 1, 5) == "farm_" then
            SC.NativeActions.cancelWork(actor, "farm_threat")
            state.work = nil
        end
        state.stage, state.afterReturn = "returning", "blocked"
        state.blocker = "unsafe_area"
    end
    if not farmThreat and state.openingSpeechAttempted ~= true then
        local openingTopic = target.operation == "replant" and "farm.crop.ruined"
            or target.operation == "cure" and "farm.crop.diseased" or nil
        state.openingSpeechAttempted = true
        if openingTopic then
            speak(actor, openingTopic, nil,
                tostring(job.id) .. ":" .. tostring(target.operation), runtime)
        end
    end
    if state.work then return finishAction(actor, baseState, job, state, square) end
    if state.outputs then
        local handled, reason, terminal = depositOutputs(actor, baseState, state)
        if not state.outputs then
            state.stage = state.collectingHarvest and "collecting_harvest" or "returning"
        end
        return handled, reason, terminal
    end
    if state.collectingHarvest then
        local snapshot, snapshotReason = restoredHarvestSnapshot(actor, target)
        if not snapshot then return false, snapshotReason, true end
        local collected, collectReason = collectHarvest(actor, job, state, snapshot)
        if collected == nil then return true, collectReason or "farm_harvest_collecting" end
        if collected ~= true then return false, collectReason, true end
        metrics.harvested = metrics.harvested + 1
        if state.outputs and #state.outputs > 0 then return true, "farm_harvest_collected" end
        state.stage, state.afterReturn = "returning", "complete"
        return true, "farm_harvest_reconciled"
    end
    if state.stage == "returning" then
        local settled, reason, pending = consumeOrReturn(actor, baseState, state)
        if settled ~= true then return pending == true, reason end
        if state.afterReturn == "sow" then
            state.stage, state.afterReturn = "sow", nil
            return true, "farm_replant_ready_to_sow"
        end
        if state.afterReturn == "blocked" then
            local blocker = state.blocker or "farm_cancelled"
            states[actor] = nil
            return false, blocker, true
        end
        SC.BaseLife.completeJob(job.id, actorId(actor), "farm_" .. tostring(target.operation))
        states[actor] = nil
        return true, "farm_job_complete"
    end

    local operation = state.stage
    local plant = plantOn(square)
    if target.operation == "harvest" and target.harvestStarted == true
        and (not plant or select(1, invoke(plant, "canHarvest")) ~= true) then
        local snapshot, snapshotReason = restoredHarvestSnapshot(actor, target)
        if not snapshot then return false, snapshotReason, true end
        local collected, collectReason = collectHarvest(actor, job, state, snapshot)
        if collected == nil then return true, collectReason end
        if collected ~= true then return false, collectReason, true end
        if state.outputs and #state.outputs > 0 then return true, "farm_harvest_recovered" end
        state.stage, state.afterReturn = "returning", "complete"
        return true, "farm_harvest_reconciled"
    end
    if not plant then return false, "farm_plot_missing", true end
    if target.operation == "replant" and operation == "plow" and plant.state == "plow" then
        state.stage, operation = "sow", "sow"
    end
    local alreadyDone = target.operation == "sow"
            and plant.state == "seeded" and plant.typeOfSeed == target.cropType
        or target.operation == "replant" and plant.state == "seeded"
            and plant.typeOfSeed == target.cropType
        or target.operation == "water" and (tonumber(plant.waterNeeded) or 0) > 0
            and (tonumber(plant.waterLvl) or 0) >= (tonumber(plant.waterNeeded) or 0)
        or target.operation == "compost" and plant.compost == true
        or target.operation == "cure" and target.diseaseField ~= nil
            and (tonumber(plant[target.diseaseField]) or 0) <= 0
    if target.operation == "harvest" and select(1, invoke(plant, "canHarvest")) ~= true then
        if target.harvestStarted == true then
            local snapshot, snapshotReason = restoredHarvestSnapshot(actor, target)
            if not snapshot then return false, snapshotReason, true end
            local collected, collectReason = collectHarvest(actor, job, state, snapshot)
            if collected == nil then return true, collectReason end
            if collected ~= true then return false, collectReason, true end
            if state.outputs and #state.outputs > 0 then
                return true, "farm_harvest_recovered"
            end
        end
        alreadyDone = true
    end
    if alreadyDone then
        state.stage, state.afterReturn = "returning", "complete"
        return true, "farm_postcondition_reconciled"
    end
    if operation == "water" and state.borrowed and waterUses(state.borrowed.item) < 1 then
        local source, reason = state.waterSource, nil
        if not waterSourceUsable(source) then
            state.waterSource = nil
            source, reason = findWaterSource(state, zone, target.emergency == true)
            if not source then return reason == "water_source_scanning", reason,
                reason ~= "water_source_scanning" end
            state.waterSource = source
        end
        local sourceSquare = U().squareOf(source)
        local approachState, approachReason = approach(actor, sourceSquare)
        if approachState == "failed" then
            state.waterSource = nil
            return false, approachReason, true
        end
        if approachState ~= "arrived" then return true, approachReason end
        return startAction(actor, job, state, sourceSquare, plant, "fill_water")
    end
    local predicate, categories, supplyKey = operationSupply(target, operation)
    if predicate and not state.borrowed then
        return borrowSupply(actor, baseState, job, state, predicate, categories, supplyKey)
    end
    local depositRows = type(SC.BaseLife.depositStorageRows) == "function"
        and SC.BaseLife.depositStorageRows("food") or SC.BaseLife.storageRows("food", false)
    if operation == "harvest" and #depositRows == 0 then
        return false, "farm_food_storage_missing", true
    end
    local approachState, approachReason = approach(actor, square)
    if approachState == "failed" then return false, approachReason, true end
    if approachState ~= "arrived" then return true, approachReason end
    if operation == "harvest" and not harvestAllowed(plant) then
        return false, "farm_seed_reserve_changed", true
    end
    return startAction(actor, job, state, square, plant, operation)
end

local function restoreBorrowed(actor, state, reason)
    if not state then return true end
    if SC.NativeActions and SC.NativeActions.workKind(actor)
        and string.sub(SC.NativeActions.workKind(actor), 1, 5) == "farm_" then
        local cancelled, cancelReason = SC.NativeActions.cancelWork(actor, reason)
        if cancelled ~= true then return false, cancelReason end
    end
    if not state.borrowed then return true end
    local borrowed = state.borrowed
    local receipt = SC.BaseLife and SC.BaseLife.farmReceipt
        and SC.BaseLife.farmReceipt(borrowed.receiptId) or nil
    if receipt and receipt.phase == "consumed" then
        unmark(borrowed.item, borrowed.receiptId)
        state.borrowed = nil
        return true, "farm_supply_consumed"
    end
    local inventory = U().inventory(actor)
    if not inventory or not U().inventoryContains(inventory, borrowed.item) then
        if receipt and missingBorrowWasConsumed(receipt) then
            SC.BaseLife.updateFarmReceipt(borrowed.receiptId, {
                phase = "consumed", blocker = false,
            })
            state.borrowed = nil
            return true, "farm_supply_consumed"
        end
        SC.BaseLife.updateFarmReceipt(borrowed.receiptId, {
            phase = "recovery", blocker = "borrowed_supply_missing",
        })
        return false, "borrowed_supply_missing"
    end
    unmark(borrowed.item, borrowed.receiptId)
    local restored, restoreReason = SC.BaseWork.restoreToStorage(actor,
        borrowed.storage, borrowed.container, borrowed.item)
    if restored == true then
        SC.BaseLife.updateFarmReceipt(borrowed.receiptId, { phase = "returned", blocker = false })
        state.borrowed = nil
        return true
    end
    mark(borrowed.item, borrowed.receiptId)
    SC.BaseLife.updateFarmReceipt(borrowed.receiptId, { phase = "recovery", blocker = restoreReason })
    return false, restoreReason
end

function FarmWork.cancelActor(actor, reason)
    local state = states[actor]
    if not state then return true, "no_farm_work" end
    local job = SC.BaseLife and SC.BaseLife.job and SC.BaseLife.job(state.jobId) or nil
    if state.work and SC.NativeActions and SC.NativeActions.isWorkActive(actor) ~= true then
        local square = job and type(job.target) == "table"
            and U().gridSquare(job.target.x, job.target.y, job.target.z) or nil
        if not job or not square then return false, "farm_cancel_reconcile_unavailable" end
        local reconciled, reconcileReason = finishAction(actor, nil, job, state, square)
        if reconciled ~= true then return false, reconcileReason end
    end
    if state.outputs then
        for index = #state.outputs, 1, -1 do
            local receipt = SC.BaseLife and SC.BaseLife.farmReceipt
                and SC.BaseLife.farmReceipt(state.outputs[index].receiptId) or nil
            if receipt and (receipt.phase == "delivered" or receipt.phase == "returned"
                or receipt.phase == "consumed") then
                table.remove(state.outputs, index)
            end
        end
        if #state.outputs == 0 then state.outputs = nil end
    end
    -- Ledger pressure may require several recovery passes: allocate as many
    -- exact output receipts as capacity permits, recover that batch, then
    -- resume the same candidate cursor without ever completing the job early.
    if state.collectingHarvest and not state.outputs and job then
        local snapshot, snapshotReason = restoredHarvestSnapshot(actor, job.target)
        if not snapshot then return false, snapshotReason end
        local collected, collectReason = collectHarvest(actor, job, state, snapshot)
        if collected == false then return false, collectReason end
    end
    local restored, restoreReason = restoreBorrowed(actor, state, reason or "farm_cancelled")
    if restored ~= true then return false, restoreReason end
    if job and type(job.target) == "table" and state.work then
        job.target.harvestStarted, job.target.harvestBeforeIds = nil, nil
        job.target.harvestBeforeStableIds, job.target.harvestBaselineVersion = nil, nil
        job.target.harvestActorId = nil
        state.work = nil
        noteOwnershipMutation()
    end
    if state.outputs then
        for _, output in ipairs(state.outputs) do
            SC.BaseLife.updateFarmReceipt(output.receiptId, {
                phase = "recovery", blocker = reason or "farm_cancelled",
            })
        end
    end
    if (state.outputs and #state.outputs > 0) or state.collectingHarvest then
        return false, "farm_recovery_pending"
    end
    states[actor] = nil
    return true, reason or "farm_cancelled"
end

function FarmWork.cancelJob(jobId, reason)
    for actor, state in pairs(states) do
        if state.jobId == jobId then
            local cancelled, detail = FarmWork.cancelActor(actor, reason or "farm_job_cancelled")
            if cancelled ~= true then return false, detail end
        end
    end
    local receipts = SC.BaseLife.farmReceipts(jobId, false)
    return #receipts == 0, #receipts == 0 and "farm_job_cancelled" or "farm_recovery_pending"
end

function FarmWork.cancelZone(zoneId)
    local base = SC.BaseLife.active()
    for _, job in ipairs(base and base.jobs or {}) do
        if job.type == "farm" and type(job.target) == "table" and job.target.zoneId == zoneId then
            local replacement
            for _, zone in ipairs(zones()) do
                if zone.id ~= zoneId and zoneContains(zone,
                    job.target.x, job.target.y, job.target.z) then replacement = zone break end
            end
            if replacement then
                job.target.zoneId = replacement.id
            else
                local okay, reason = FarmWork.cancelJob(job.id, "farm_zone_removed")
                if okay ~= true then return false, reason end
            end
        end
    end
    return true
end

-- Called only after BaseLife has committed the zone mutation. Keeping pruning
-- on this side of the commit preserves overlapping coverage and leaves caches
-- untouched when removal is rejected by an active recovery obligation.
function FarmWork.zoneRemoved(zoneId)
    scanState[zoneId] = nil
    local activeZones = zones()
    for key, plot in pairs(knownPlots) do
        local covered = false
        for _, zone in ipairs(activeZones) do
            if zoneContains(zone, plot.x, plot.y, plot.z) then covered = true break end
        end
        if not covered then knownPlots[key] = nil end
    end
    supplyScans, seedScans = {}, {}
    return true
end

FarmWork._nonGrowbackPlotsForTests = nonGrowbackPlots
FarmWork._seedCountForTests = seedCount
FarmWork._speakForTests = speak

function FarmWork.reset(actor)
    if actor then
        FarmWork.cancelActor(actor, "farm_reset")
    else
        for value in pairs(states) do FarmWork.cancelActor(value, "farm_reset") end
        states = setmetatable({}, { __mode = "k" })
        scanState, knownPlots = {}, {}
        supplyScans, seedScans, knownBase = {}, {}, nil
        lastFarmSpeechAt = -math.huge
    end
end

function FarmWork.summary()
    local result = {}
    for key, value in pairs(metrics) do result[key] = value end
    local base, pending, active, blocked = SC.BaseLife and SC.BaseLife.active() or nil, 0, 0, 0
    for _, job in ipairs(base and base.jobs or {}) do
        if job.type == "farm" then
            if job.state == "blocked" then blocked = blocked + 1
            elseif job.state == "active" or job.state == "reserved" then active = active + 1
            else pending = pending + 1 end
        end
    end
    result.pending, result.active, result.blocked = pending, active, blocked
    result.knownPlots, result.receipts = 0, #(SC.BaseLife and SC.BaseLife.farmReceipts
        and SC.BaseLife.farmReceipts(nil, false) or {})
    for _ in pairs(knownPlots) do result.knownPlots = result.knownPlots + 1 end
    return result
end

return FarmWork
