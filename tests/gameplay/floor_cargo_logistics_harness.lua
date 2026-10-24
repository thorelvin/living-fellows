-- SPDX-License-Identifier: MIT
-- The intake worker must deliver its exact claim before generic packing.
local SC = SurvivorCompanion
local checks, current, moves = 0, 1000, 0
local function check(okay, message)
    checks = checks + 1
    if not okay then error("floor cargo/logistics " .. checks .. ": " .. message) end
end
local function call(value, method, ...)
    if value and type(value[method]) == "function" then return value[method](value, ...), true end
    return nil, false
end
local function container()
    local value = { items = {} }
    function value:getItems() return self.items end
    function value:getContainingItem() return self.holder end
    return value
end
local function item(id, fullType, category)
    local value = { id = id, fullType = fullType, category = category, modData = {}, weight = 1 }
    function value:getID() return self.id end
    function value:getFullType() return self.fullType end
    function value:getCategory() return self.category end
    function value:getDisplayCategory() return self.category end
    function value:getModData() return self.modData end
    function value:getContainer() return self.container end
    function value:getInventory() return self.nested end
    function value:getItemContainer() return self.nested end
    function value:getBodyLocation() return self.location end
    function value:getCapacity() return self.nested and 30 or 0 end
    function value:getWeightReduction() return self.nested and 80 or 0 end
    return value
end
local function add(owner, value)
    owner.items[#owner.items + 1], value.container = value, owner
end
local function contains(owner, value)
    for _, candidate in ipairs(owner and owner.items or {}) do if candidate == value then return true end end
    return false
end
local function transfer(source, destination, value)
    for index, candidate in ipairs(source.items) do
        if candidate == value then
            table.remove(source.items, index)
            add(destination, value)
            return true, "transferred"
        end
    end
    return false, "source_missing"
end
local root, bagInventory, store = container(), container(), container()
local bag = item(100, "Base.Bag_ALICEpack", "Container")
bag.nested, bag.location, bagInventory.holder = bagInventory, "Back", bag
local cargo = item(101, "Base.TinCan", "Item")
local stale = item(102, "Base.TinCan", "Item")
local actor = { id = "resident:floor", inventory = root, x = 10, y = 10, z = 0, modData = {} }
function actor:getModData() return self.modData end
function actor:getWornItem(location) return location == "Back" and bag or nil end
function actor:isEquippedClothing(value) return value == bag end
add(root, bag)
add(root, cargo)
local zone = { id = "zone:intake", kind = "sorting_floor", x1 = 9, x2 = 9, y1 = 10, y2 = 10, z = 0 }
local job = { id = "job:115", type = "sort_floor", assignedId = actor.id,
    target = { zoneId = zone.id, floorCargo = { zoneId = zone.id, itemId = cargo.id, x = 9, y = 10, z = 0 } } }
local base = { zones = { zone }, jobs = { job } }
local storage = { id = "storage:tools" }
local object = { x = 10, y = 10, z = 0 }
local utility = {
    call = call, nowMs = function() return current end, config = function() return nil end,
    idOf = function(value) return value.id end,
    inventory = function(value) return value.inventory end,
    inventoryContains = contains, transferItemVerified = transfer,
    each = function(values, limit, visit)
        for index = 1, math.min(#(values or {}), limit) do if visit(values[index]) == false then break end end
    end,
    itemType = function(value) return value.fullType end,
    itemWeight = function(value) return value.weight end,
    itemHasTag = function() return false end,
    instanceOf = function() return false end,
    hasMethod = function(value, method) return type(value[method]) == "function" end,
    clamp = function(value, minimum, maximum) return math.max(minimum, math.min(maximum, value)) end,
    inventoryLoad = function() return 2, 50, .04, root end,
    carryLoad = function() return 2, 12 end,
    containerHasRoom = function() return true end,
    actorState = function(_, runtime) return runtime or {} end,
    directInteractionAccess = function() return true, { object }, "at_interaction_target" end,
    position = function(value) return value.x, value.y, value.z end,
    gridSquare = function() return object end,
    squareOf = function() return object end,
    move = function() moves = moves + 1 return true end,
    stop = function() return true end,
}
SC.GameplayUtil = utility
SC.BaseLife = {
    active = function() return base end,
    job = function(id) return id == job.id and job or nil end,
    resident = function() return { role = "generalist" } end,
    isInside = function() return true end,
    resolveObject = function() return object end,
    resolveContainer = function() return store end,
    storageAcceptsDeposit = function() return true end,
}
SC.NativeActions = { stopDirect = function() return true end,
    visualStatus = function() return "completed" end,
    clearVisual = function() return true end }
SC.Navigation = { cancel = function() return true end }
SC.PersonalItems, SC.Combat, SC.Background, SC.Registry = nil, nil, nil, nil
SC.FarmWork, SC.ExpeditionPrototype, SC.FieldWork = nil, nil, nil
SC.BaseWork.floorDestinations = function()
    return { { destination = storage, container = store } }, "general"
end
cargo.modData.LF_FloorSortJob, stale.modData.LF_FloorSortJob = job.id, job.id
check(SC.WorkTransport.isCargoProtected(cargo, actor, "loadout"), "the exact carried floor claim is protected")
check(SC.WorkTransport.isCargoProtected(stale, actor, "loadout") == false, "same-job stale identity is not protected")
local audit = SC.Logistics.status(actor)
check(audit.packMove == nil and audit.cargoWeight == 1, "real Logistics excludes the exact claim from packing and gear weight")
for _ = 1, 4 do
    current = current + 1000
    local _, reason = SC.Logistics.update(actor, nil, { snapshot = {} })
    check(reason == "load_balanced" and cargo.container == root and moves == 0,
        "normal logistics beats leave the intake cargo rooted without restarting Loot")
end
add(root, stale)
current = current + 1000
audit = SC.Logistics.status(actor)
check(audit.packMove and audit.packMove.item == stale, "an unrelated stale-marked item is still normally packable")
root.items[#root.items] = nil
stale.container = nil
-- Start in a nested bag as a save or another inventory operation can do.
check(transfer(root, bagInventory, cargo), "the exact fixture cargo can begin nested")
current = current + 1000
local handled, reason = SC.FloorSort.update(actor, {}, job)
check(handled and reason == "floor_item_stored" and cargo.container == store,
    "the real intake controller stages then physically deposits its protected exact cargo")
check(not contains(root, cargo) and not contains(bagInventory, cargo) and contains(store, cargo)
    and cargo.modData.LF_FloorSortJob == nil and job.target.floorCargo == nil,
    "verified delivery has one owner and clears both marker and receipt")

-- Ordinary shelf sorting keeps its receipt in BaseWork rather than on the
-- item. Exercise that production controller alongside the real Logistics path.
local shelfSource, shelfDestination = container(), container()
local sourceRow = { id = "storage:source", category = "general" }
local destinationRow = { id = "storage:destination", category = "crafting" }
local shelfCargo = item(103, "Base.TinCan", "Item")
local shelfJob = { id = "job:116", type = "sort", state = "active",
    reservedBy = actor.id, target = {} }
base.jobs = { shelfJob }
SC.BaseWatch, SC.Downtime, SC.ChefWork, SC.Production, SC.GatherWork = nil, nil, nil, nil, nil
SC.BaseLife.job = function(id) return id == shelfJob.id and shelfJob or nil end
SC.BaseLife.jobFor = function() return shelfJob.state == "active" and shelfJob or nil end
SC.BaseLife.resident = function() return { role = "generalist", duty = true } end
SC.BaseLife.outdoorNightRestricted = function() return false end
SC.BaseLife.storageRows = function() return { sourceRow } end
SC.BaseLife.depositStorageRows = function() return { destinationRow } end
SC.BaseLife.storage = function(id)
    return id == sourceRow.id and sourceRow or id == destinationRow.id and destinationRow or nil
end
SC.BaseLife.resolveContainer = function(row)
    return row == sourceRow and shelfSource or row == destinationRow and shelfDestination or nil
end
SC.BaseLife.storageReserve = function() return 0 end
SC.BaseLife.availableCountExact = function() return 1 end
SC.BaseLife.withdrawable = function() return true end
SC.BaseLife.isValuableItem = function() return false end
SC.BaseLife.touchJob = function() return true end
SC.BaseLife.completeJob = function() shelfJob.state = "completed" return true end
SC.BaseLife.releaseJob = function() shelfJob.state = "pending" return true end
utility.listSize = function(values) return #(values or {}) end
utility.listGet = function(values, index) return values[index + 1] end
utility.characterStatValue = function(_, _, fallback) return fallback end
utility.modData = function(value) return value.modData end
local visualPhase = "active"
utility.move = function() moves = moves + 1 visualPhase = "active" return true end
SC.NativeActions.visualStatus = function() return visualPhase end
SC.NativeActions.cancelVisual = function() return true end
SC.Logistics.reset(actor)
add(root, shelfCargo)
current = current + 2000
local packing, packReason = SC.Logistics.update(actor, nil, { snapshot = {} })
check(packing and packReason == "logistics_action_active",
    "an ordinary unclaimed shelf item can start a real packing transaction")
-- The cached selection predates the work receipt. The item is now withdrawn
-- by the shelf job before that old packing transaction gets its commit turn.
check(transfer(root, shelfSource, shelfCargo), "the cached item can return to its source shelf")
local startedShelf = SC.BaseWork.update(actor, nil, {})
visualPhase = "completed"
local tookShelf = SC.BaseWork.update(actor, nil, {})
check(startedShelf and tookShelf and contains(root, shelfCargo)
    and SC.BaseWork.cargoReserved(actor, shelfCargo)
    and not SC.BaseWork.cargoReserved({ id = "other" }, shelfCargo)
    and not SC.BaseWork.cargoReserved(actor, stale),
    "the real shelf withdrawal reserves only its exact item for this worker")
local movesBeforeRecheck = moves
local packedCargo, reservedReason = SC.Logistics.update(actor, nil, { snapshot = {} })
check(not packedCargo and reservedReason == "logistics_item_reserved"
    and shelfCargo.container == root and moves == movesBeforeRecheck,
    "a cached pack transaction refuses newly owned shelf cargo before another Loot or transfer")
current = current + 2000
audit = SC.Logistics.status(actor)
check(audit.packMove == nil and audit.cargoWeight == 1,
    "live shelf cargo is excluded from packing and ordinary gear load")
add(root, stale)
current = current + 2000
audit = SC.Logistics.status(actor)
check(audit.packMove and audit.packMove.item == stale,
    "shelf cargo protection leaves unrelated loose items packable")
root.items[#root.items], stale.container = nil, nil
visualPhase = "completed"
local deliveredShelf, deliveredReason = SC.BaseWork.update(actor, nil, {})
check(deliveredShelf and deliveredReason == "base_transfer_complete"
    and shelfCargo.container == shelfDestination
    and not SC.BaseWork.cargoReserved(actor, shelfCargo),
    "the protected shelf cargo still delivers normally and releases its runtime receipt")

-- Cancelling a later haul also releases protection only after its exact item
-- has been verified back at the registered source.
check(transfer(shelfDestination, shelfSource, shelfCargo), "the next haul starts at its shelf")
shelfJob.state = "active"
local startedReturn = SC.BaseWork.update(actor, nil, {})
visualPhase = "completed"
local tookReturn = SC.BaseWork.update(actor, nil, {})
check(startedReturn and tookReturn and SC.BaseWork.cargoReserved(actor, shelfCargo),
    "the next shelf haul owns its newly withdrawn cargo")
local cancelledShelf = SC.BaseWork.cancel(actor, "test_shelf_cancelled")
check(cancelledShelf and shelfCargo.container == shelfSource
    and not SC.BaseWork.cargoReserved(actor, shelfCargo),
    "verified cancellation returns shelf cargo and releases its protection")
check(transfer(shelfSource, root, shelfCargo), "a later unreserved gift can be carried normally")
SC.Logistics.reset(actor)
current = current + 2000
audit = SC.Logistics.status(actor)
check(audit.packMove and audit.packMove.item == shelfCargo,
    "released shelf cargo becomes packable again")
local resumedPacking = SC.Logistics.update(actor, nil, { snapshot = {} })
visualPhase = "completed"
local finishedPacking, finishedReason = SC.Logistics.update(actor, nil, { snapshot = {} })
check(resumedPacking and finishedPacking and finishedReason == "item_packed"
    and shelfCargo.container == bagInventory,
    "normal packing physically resumes after shelf ownership ends")

-- Fishing preparation reserves its carried gear through its own controller.
-- Logistics must honor that claim even if its packing choice predates it.
local fishingRod = item(104, "Base.FishingRod", "Item")
local fishingBait = item(105, "Base.Worm", "Item")
local fishingMission = false
SC.Fishing = { gearReserved = function(worker, value)
    return fishingMission and worker == actor
        and (value == fishingRod or value == fishingBait)
end }
add(root, fishingRod)
add(root, fishingBait)
SC.Logistics.reset(actor)
current = current + 2000
local packingRod, rodPackReason = SC.Logistics.update(actor, nil, { snapshot = {} })
check(packingRod and rodPackReason == "logistics_action_active",
    "fishing gear without a mission remains normally packable")
fishingMission = true
local reservedRod, rodReason = SC.Logistics.update(actor, nil, { snapshot = {} })
check(not reservedRod and rodReason == "logistics_item_reserved"
    and fishingRod.container == root and fishingBait.container == root,
    "a newly reserved fishing rod cannot finish its old packing transaction")
current = current + 2000
audit = SC.Logistics.status(actor)
check(audit.packMove == nil and audit.cargoWeight == 2,
    "the mission's exact rod and bait stay ready rather than becoming surplus or packing targets")
add(root, stale)
current = current + 2000
audit = SC.Logistics.status(actor)
check(audit.packMove and audit.packMove.item == stale,
    "reserving fishing gear still allows unrelated items to be packed")
root.items[#root.items], stale.container = nil, nil
fishingMission = false
current = current + 31000
audit = SC.Logistics.status(actor)
check(audit.packMove and (audit.packMove.item == fishingRod
        or audit.packMove.item == fishingBait) and audit.cargoWeight == 0,
    "ending the mission releases fishing gear back to ordinary inventory management: "
        .. tostring(audit.packMove and audit.packMove.item.fullType)
        .. "/" .. tostring(audit.cargoWeight))
print("FLOOR_CARGO_LOGISTICS_PASS checks=" .. checks)
