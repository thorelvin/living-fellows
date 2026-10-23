-- SPDX-License-Identifier: MIT
-- Exact floor intake, physical trash, blocked storage and reload recovery.
local SC = SurvivorCompanion
local Floor = SC.FloorSort
local realBaseWork, realUtil = SC.BaseWork, SC.GameplayUtil
local now = 1000
local serial = 0
local function check(value, message)
    if not value then error("floor sort: " .. message) end
end
local function call(object, method, ...)
    if object and type(object[method]) == "function" then
        return object[method](object, ...), true
    end
    return nil, false
end
local function square(x, y)
    return { x = x, y = y, z = 0, worldItems = {} }
end
local source = square(10, 10)
local trash = square(12, 10)
local squares = { ["10:10:0"] = source, ["12:10:0"] = trash }
local inventory = { items = {} }
local storage = { items = {} }
local alternateStorage = { items = {} }
local actor = { id = "resident:1", x = 10, y = 10, z = 0, inventory = inventory }
local base = { id = "base:1", jobs = {}, zones = {
    { id = "zone:sorting", kind = "sorting_floor",
        x1 = 10, x2 = 10, y1 = 10, y2 = 10, z = 0 },
    { id = "zone:trash", kind = "trash_pile",
        x1 = 12, x2 = 12, y1 = 10, y2 = 10, z = 0 },
} }
local function contains(container, item)
    for _, candidate in ipairs(container.items) do
        if candidate == item then return true end
    end
    return false
end
local function remove(container, item)
    for index, candidate in ipairs(container.items) do
        if candidate == item then table.remove(container.items, index) return true end
    end
    return false
end
local function item(id, trashItem)
    local result = { id = id, trash = trashItem, modData = {} }
    function result:getID() return self.id end
    function result:getModData() return self.modData end
    function result:getContainer() return self.container end
    function result:getWorldItem() return self.worldItem end
    return result
end
local function addWorld(where, candidate)
    local wrapper = { item = candidate, square = where }
    function wrapper:getItem() return self.item end
    function wrapper:getSquare() return self.square end
    where.worldItems[#where.worldItems + 1] = wrapper
    candidate.worldItem, candidate.container = wrapper, nil
    return wrapper
end
SC.GameplayUtil = {
    call = call, nowMs = function() return now end,
    idOf = function(value) return value.id end,
    gridSquare = function(x, y, z) return squares[x .. ":" .. y .. ":" .. z] end,
    squareOf = function(value) return squares[value.x .. ":" .. value.y .. ":" .. value.z] end,
    position = function(value) return value.x, value.y, value.z end,
    sameSquare = function(value, where)
        return value.x == where.x and value.y == where.y and value.z == where.z
    end,
    isSquareFree = function() return true end,
    distanceSq = function(value, where)
        return (value.x - where.x) ^ 2 + (value.y - where.y) ^ 2
    end,
    inventory = function(value) return value.inventory end,
    inventoryItemsDeep = function(container) return container.items end,
    inventoryContains = contains,
    worldItemPresent = function(where, wrapper)
        for _, candidate in ipairs(where.worldItems) do
            if candidate == wrapper then return true end
        end
        return false
    end,
    takeWorldItemVerified = function(wrapper, destination, expected)
        if wrapper.item ~= expected or not remove({ items = wrapper.square.worldItems }, wrapper) then
            return false, "world_changed"
        end
        destination.items[#destination.items + 1] = expected
        expected.container, expected.worldItem = destination, nil
        return true, "taken"
    end,
    dropItem = function(container, where, candidate)
        if not remove(container, candidate) then return false, "source_missing" end
        local wrapper = addWorld(where, candidate)
        return true, wrapper
    end,
    transferItemVerified = function(from, to, candidate)
        if not remove(from, candidate) then return false, "source_missing" end
        to.items[#to.items + 1] = candidate
        candidate.container = to
        return true, "transferred"
    end,
    move = function() return true end,
    stop = function() return true end,
}
SC.BaseLife = {
    active = function() return base end,
    dutyResidentIds = function() return { actor.id } end,
    job = function(id)
        for _, job in ipairs(base.jobs) do if job.id == id then return job end end
        return nil
    end,
    enqueueJob = function(spec)
        serial = serial + 1
        local job = { id = "job:" .. serial, type = spec.type,
            target = spec.target, state = "pending" }
        base.jobs[#base.jobs + 1] = job
        return true, job
    end,
}
SC.Registry = { byId = function() return { actor = actor } end }
SC.WorkTransport = {
    foreignProtected = function() return false end,
    hasRoom = function(_, _, candidate) return not (candidate and candidate.heavy) end,
}
SC.Logistics = { isTrash = function(candidate) return candidate.trash == true end }
SC.Navigation = {
    cancel = function() return true end,
    requestAny = function(value, targets)
        local target = targets[1]
        value.x, value.y, value.z = target.x, target.y, target.z
        return true, "arrived", target
    end,
}
SC.NativeActions = {
    stopDirect = function() return true end,
    visualStatus = function() return "completed" end,
    clearVisual = function() return true end,
    cancelVisual = function() return true end,
}
local destinationEnabled = true
local alternateEnabled, firstRouteBlocked = false, false
local yardEnabled = false
local goneWorkers = {}
SC.BaseWork = {
    choreReserved = function() return false end,
    workerUnregistered = function(id) return goneWorkers[id] == true end,
    floorDestinations = function(_, candidate)
        if yardEnabled then
            return { { destination = { kind = "log_yard", zoneId = "zone:yard",
                x = trash.x, y = trash.y, z = trash.z }, container = trash } },
                "construction"
        end
        if destinationEnabled then
            local rows = { { destination = { id = "storage:1" },
                container = storage } }
            if alternateEnabled then rows[#rows + 1] = {
                destination = { id = "storage:2" }, container = alternateStorage }
            end
            return rows, "tools"
        end
        return {}, "tools", "floor_storage_missing"
    end,
    depositToStorage = function(worker, state, destination, container, candidate, options)
        if yardEnabled then
            return realBaseWork.depositToStorage(worker, state,
                destination, container, candidate, options)
        end
        if firstRouteBlocked and container == storage then
            return false, "no_route"
        end
        if not remove(inventory, candidate) then return false, "carrier_missing" end
        container.items[#container.items + 1] = candidate
        candidate.container = container
        return true, "base_supply_returned"
    end,
}

local tool = item(101, false)
addWorld(source, tool)
local queued, job = Floor.audit(base)
check(queued and job.type == "sort_floor", "ground item queues a job")
local state = {}
local firstHandled, firstReason = Floor.update(actor, state, job)
check(firstReason == "floor_pickup_animation",
    "floor item gets a visible pickup: " .. tostring(firstReason))
check(select(2, Floor.update(actor, state, job)) == "floor_item_carried",
    "exact world item moves to carrier")
check(contains(inventory, tool) and tool.modData.LF_FloorSortJob == job.id,
    "carrier owns the claimed item")
state = {} -- runtime reset: the saved job target and native item still recover
check(select(2, Floor.update(actor, state, job)) == "floor_item_stored",
    "reload resumes exact delivery")
check(contains(storage, tool) and not contains(inventory, tool)
    and tool.modData.LF_FloorSortJob == nil, "verified delivery clears claim")
check(select(4, Floor.update(actor, state, job)) == true,
    "empty sorting floor completes the job")
table.remove(base.jobs, 1)

local rubbish = item(102, true)
addWorld(source, rubbish)
queued, job = Floor.audit(base)
check(queued, "trash queues a job")
state = {}
Floor.update(actor, state, job)
Floor.update(actor, state, job)
check(select(2, Floor.update(actor, state, job)) == "floor_item_discarded",
    "trash is physically dropped at the marked pile")
check(rubbish.worldItem and contains({ items = trash.worldItems }, rubbish.worldItem)
    and not contains(inventory, rubbish), "trash is not deleted")
table.remove(base.jobs, 1)

local waiting = item(103, false)
addWorld(source, waiting)
destinationEnabled = false
queued, job = Floor.audit(base)
check(queued, "unroutable item remains visible to audit")
state = {}
check(select(2, Floor.update(actor, state, job)) == "floor_item_waiting_storage",
    "missing category leaves item in place")
local _, reason, terminal = Floor.update(actor, state, job)
check(reason == "floor_storage_missing" and terminal == true
    and waiting.worldItem ~= nil and waiting.modData.LF_FloorSortJob == nil,
    "blocked job reports missing storage without taking item")
table.remove(base.jobs, 1)
destinationEnabled = true
now = now + 31000
remove({ items = source.worldItems }, waiting.worldItem)
waiting.worldItem = nil

local borrowed = item(104, false)
addWorld(source, borrowed)
queued, job = Floor.audit(base)
state = {}
Floor.update(actor, state, job)
Floor.update(actor, state, job)
check(contains(inventory, borrowed), "cancellation test has carried cargo")
check(Floor.zoneInUse("zone:sorting") == true,
    "source zone is protected during transfer")
check(Floor.cancel(actor, job) == true, "cancel returns exact item")
check(borrowed.worldItem and not contains(inventory, borrowed)
    and not Floor.zoneInUse("zone:sorting"),
    "returned cargo is visible on original floor")
remove({ items = source.worldItems }, borrowed.worldItem)
borrowed.worldItem = nil
table.remove(base.jobs, 1)

local rerouted = item(105, false)
addWorld(source, rerouted)
alternateEnabled, firstRouteBlocked = true, true
queued, job = Floor.audit(base)
check(queued, "alternate destination test queues")
state = {}
Floor.update(actor, state, job)
Floor.update(actor, state, job)
check(select(2, Floor.update(actor, state, job)) == "floor_destination_changed",
    "inaccessible first shelf moves to second marked shelf")
check(select(2, Floor.update(actor, state, job)) == "floor_item_stored"
    and contains(alternateStorage, rerouted)
    and not contains(storage, rerouted),
    "alternate shelf receives the exact item")
table.remove(base.jobs, 1)
alternateEnabled, firstRouteBlocked = false, false

-- Storage that disappears while the item is carried: the worker walks the
-- item back to its own floor tile before putting it down. dropItem places an
-- item on any tile at any distance, so without the walk it would jump there.
local shelf = square(15, 10)
squares["15:10:0"] = shelf
local stranded = item(106, false)
addWorld(source, stranded)
queued, job = Floor.audit(base)
check(queued, "carry-back test queues")
state = {}
Floor.update(actor, state, job)
Floor.update(actor, state, job)
check(contains(inventory, stranded), "carry-back test has carried cargo")
actor.x, actor.y = 15, 10
destinationEnabled = false
local walkedHandled, walkedReason, walkedTerminal = Floor.update(actor, state, job)
check(walkedHandled == true and walkedReason == "floor_storage_missing"
        and walkedTerminal == true and actor.x == 10 and actor.y == 10
        and stranded.worldItem ~= nil
        and contains({ items = source.worldItems }, stranded.worldItem)
        and not contains(inventory, stranded)
        and stranded.modData.LF_FloorSortJob == nil and job.target.floorCargo == nil,
    "an item with nowhere to go is walked back to its own tile: "
        .. tostring(walkedReason) .. " at " .. tostring(actor.x) .. "," .. tostring(actor.y))
remove({ items = source.worldItems }, stranded.worldItem)
stranded.worldItem = nil
table.remove(base.jobs, 1)
destinationEnabled = true

-- An interrupted worker puts the item down where it stands.
local interrupted = item(107, false)
addWorld(source, interrupted)
queued, job = Floor.audit(base)
check(queued, "interrupted-carry test queues")
state = {}
Floor.update(actor, state, job)
Floor.update(actor, state, job)
check(contains(inventory, interrupted), "interrupted carry has cargo")
actor.x, actor.y = 15, 10
check(Floor.cancel(actor, job) == true and interrupted.worldItem ~= nil
        and contains({ items = shelf.worldItems }, interrupted.worldItem)
        and not contains({ items = source.worldItems }, interrupted.worldItem)
        and job.target.floorCargo == nil,
    "a worker interrupted across the camp puts the item down at its own feet")
remove({ items = shelf.worldItems }, interrupted.worldItem)
interrupted.worldItem = nil
table.remove(base.jobs, 1)
actor.x, actor.y = 10, 10

-- A worker that is not yet restored keeps its claim; one gone for good
-- (dead or dismissed) releases it, so neither the job, the zone nor the camp
-- is held by cargo that can never be delivered or returned.
local lost = item(108, false)
addWorld(source, lost)
queued, job = Floor.audit(base)
check(queued, "lost test queues")
state = {}
Floor.update(actor, state, job)
Floor.update(actor, state, job)
check(contains(inventory, lost) and Floor.zoneInUse("zone:sorting") == true,
    "gone-worker test has carried cargo")
check(select(2, Floor.cancel(nil, job)) == "floor_worker_unavailable"
        and job.target.floorCargo ~= nil,
    "a worker not yet restored keeps its claim")
goneWorkers[actor.id] = true
check(Floor.zoneInUse("zone:sorting") == false,
    "cargo of a worker gone for good does not hold the zone")
check(Floor.cancel(nil, job) == true and job.target.floorCargo == nil
        and job.assignedId == nil,
    "cancelling the job of a worker gone for good succeeds")
goneWorkers[actor.id] = nil
table.remove(base.jobs, 1)

local orphaned = item(109, false)
addWorld(source, orphaned)
queued, job = Floor.audit(base)
check(queued, "orphaned test queues")
state = {}
Floor.update(actor, state, job)
Floor.update(actor, state, job)
check(contains(inventory, orphaned) and job.assignedId == actor.id,
    "orphaned-claim test has carried cargo")
goneWorkers[actor.id] = true
Floor.audit(base)
check(job.target.floorCargo == nil and job.assignedId == nil,
    "audit releases the claim of a worker gone for good")
goneWorkers[actor.id] = nil
table.remove(base.jobs, 1)

-- The player takes the item out of the carrier's inventory.
local taken = item(110, false)
addWorld(source, taken)
queued, job = Floor.audit(base)
check(queued, "taken test queues")
state = {}
Floor.update(actor, state, job)
Floor.update(actor, state, job)
check(contains(inventory, taken), "absent-cargo test has carried cargo")
remove(inventory, taken)
local absentHandled, absentReason, absentTerminal = Floor.update(actor, state, job)
check(absentHandled == true and absentReason == "floor_cargo_absent"
        and not absentTerminal and job.target.floorCargo == nil
        and Floor.zoneInUse("zone:sorting") == false,
    "cargo taken from the carrier releases the claim: " .. tostring(absentReason))

table.remove(base.jobs, 1)

-- An item the worker has no room for is set aside like one with no storage.
-- Lighter items are still stored, and the job stays open with the reason
-- instead of completing and being queued again for the same item.
local anvil = item(111, false)
anvil.heavy = true
local hammer = item(112, false)
addWorld(source, anvil)
addWorld(source, hammer)
queued, job = Floor.audit(base)
check(queued, "heavy-item test queues")
state = {}
local heavyReasons, heavyCompleted, heavyTerminal = {}, false, nil
for _ = 1, 12 do
    local _, reason, terminal, completed = Floor.update(actor, state, job)
    heavyReasons[#heavyReasons + 1] = tostring(reason)
    if completed then heavyCompleted = true break end
    if terminal then heavyTerminal = reason break end
end
check(not heavyCompleted and heavyTerminal == "floor_worker_full"
        and contains(storage, hammer) and anvil.worldItem ~= nil
        and contains({ items = source.worldItems }, anvil.worldItem),
    "an item without room is set aside while lighter items are stored: "
        .. table.concat(heavyReasons, ","))

table.remove(base.jobs, 1)
remove({ items = source.worldItems }, anvil.worldItem)
anvil.worldItem = nil

-- The real storage helper used to bundle the fourth log before floor intake
-- could verify its identity. A consumptive bundle must run after settlement.
yardEnabled = true
local log = item(113, false)
addWorld(source, log)
local bundles = 0
SC.LogYard = {
    tile = function() return trash end,
    deposit = function(worker, candidate)
        return SC.GameplayUtil.dropItem(worker.inventory, trash, candidate)
    end,
    bundleAt = function(_, where)
        check(log.modData.LF_FloorSortJob == nil and job.target.floorCargo == nil,
            "log claim settles before a consumptive bundle")
        check(remove({ items = where.worldItems }, log.worldItem),
            "bundler consumes delivered exact log")
        log.worldItem = nil
        bundles = bundles + 1
        return true, "log_yard_bundled"
    end,
}
queued, job = Floor.audit(base)
check(queued, "log yard regression queues")
state = {}
Floor.update(actor, state, job)
check(select(2, Floor.update(actor, state, job)) == "floor_item_carried",
    "log yard regression picks up exact log")
actor.x, actor.y, actor.z = trash.x, trash.y, trash.z
check(select(2, Floor.update(actor, state, job)) == "floor_item_stored"
    and bundles == 1 and job.target.floorCargo == nil
    and not contains(inventory, log),
    "log bundle consumption cannot strand the floor delivery receipt")
table.remove(base.jobs, 1)
yardEnabled = false

-- Exercise the real scan policy: an empty bag reserves 256 of the 1024
-- entries, so the root tail can be unread even below the total scan limit.
local originalCall, originalItems = realUtil.call, realUtil.inventoryItems
realUtil.call = call
realUtil.inventoryItems = function(container, limit)
    local result = {}
    for index = 1, math.min(#container.items, limit) do
        result[#result + 1] = container.items[index]
    end
    return result
end
SC.GameplayUtil.inventoryItemsDeep = realUtil.inventoryItemsDeep
inventory.items = {}
for index = 1, 768 do inventory.items[index] = item(2000 + index, false) end
local emptyBag = { items = {} }
inventory.items[1].getItemContainer = function() return emptyBag end
inventory.items[1].container = inventory
local hidden = item(114, false)
inventory.items[769] = hidden
hidden.container = inventory
SC.BaseLife.enqueueJob({ type = "sort_floor", target = {
    zoneId = "zone:sorting", x = 10, y = 10, z = 0,
    floorCargo = { zoneId = "zone:sorting", itemId = hidden.id,
        x = 10, y = 10, z = 0 },
} })
job = base.jobs[#base.jobs]
job.assignedId, hidden.modData.LF_FloorSortJob = actor.id, job.id
local scanned = realUtil.inventoryItemsDeep(inventory, 1024, 16)
check(#scanned == 768, "real scan leaves the root tail unread with an empty bag")
local function deliverByUpdates(label)
    local pending = 0
    for _ = 1, 20 do
        local handled, reason, terminal = Floor.update(actor, {}, job)
        if reason == "floor_item_stored" then
            check(contains(storage, hidden) and job.target.floorCargo == nil,
                label .. " deposits the exact cargo")
            return pending
        end
        check(handled == true and reason == "floor_cargo_search_pending"
            and terminal ~= true and job.target.floorCargo ~= nil
            and hidden.modData.LF_FloorSortJob == job.id,
            label .. " keeps its lease and ownership while searching: " .. tostring(reason))
        pending = pending + 1
    end
    error("floor sort: " .. label .. " did not finish its bounded search")
end
check(deliverByUpdates("crowded root") > 0 and not contains(inventory, hidden),
    "root-tail cargo is found across updates without rearranging inventory")
table.remove(base.jobs, 1)
remove(storage, hidden)

-- The exact lookup follows nested bags, including a cycle, which the general
-- one-level inventory scanner cannot read.
local inner = { items = {} }
local nestedBag = item(115, false)
nestedBag.getItemContainer = function() return inner end
emptyBag.items = { nestedBag }
nestedBag.container = emptyBag
inventory.items = { item(116, false) }
inventory.items[1].getItemContainer = function() return emptyBag end
inventory.items[1].container = inventory
inner.items = { hidden }
hidden.container = inner
SC.BaseLife.enqueueJob({ type = "sort_floor", target = {
    zoneId = "zone:sorting", x = 10, y = 10, z = 0,
    floorCargo = { zoneId = "zone:sorting", itemId = hidden.id,
        x = 10, y = 10, z = 0 },
} })
job = base.jobs[#base.jobs]
job.assignedId, hidden.modData.LF_FloorSortJob = actor.id, job.id
local cyclicBag = item(119, false)
cyclicBag.container = inner
cyclicBag.getItemContainer = function() return emptyBag end
inner.items = { cyclicBag, hidden }
deliverByUpdates("nested bag with cycle")
check(not contains(inner, hidden),
    "nested exact cargo transfers to the root and is delivered without rearranging bags")
table.remove(base.jobs, 1)
remove(storage, hidden)

-- A crowded root leaves only the reserved 256 slots for its first bag in the
-- general scan. The exact cursor eventually reads beyond that bag slice too.
inventory.items, emptyBag.items = {}, {}
for index = 1, 768 do inventory.items[index] = item(3000 + index, false) end
inventory.items[1].getItemContainer = function() return emptyBag end
inventory.items[1].container = inventory
for index = 1, 256 do emptyBag.items[index] = item(4000 + index, false) end
emptyBag.items[257], hidden.container = hidden, emptyBag
SC.BaseLife.enqueueJob({ type = "sort_floor", target = {
    zoneId = "zone:sorting", x = 10, y = 10, z = 0,
    floorCargo = { zoneId = "zone:sorting", itemId = hidden.id,
        x = 10, y = 10, z = 0 },
} })
job = base.jobs[#base.jobs]
job.assignedId, hidden.modData.LF_FloorSortJob = actor.id, job.id
check(deliverByUpdates("crowded bag") > 0 and not contains(emptyBag, hidden),
    "bag-tail cargo is delivered across updates without rearranging its contents")
table.remove(base.jobs, 1)
realUtil.call, realUtil.inventoryItems = originalCall, originalItems
SC.GameplayUtil.inventoryItemsDeep = function(container) return container.items end

-- Cancel a selected floor item before pickup, then assign another zone to
-- the same worker. Its cached candidate and native movement belong to A.
local otherSource = square(20, 10)
squares["20:10:0"] = otherSource
base.zones[#base.zones + 1] = { id = "zone:other", kind = "sorting_floor",
    x1 = 20, x2 = 20, y1 = 10, y2 = 10, z = 0 }
local firstSelection, secondSelection = item(117, false), item(118, false)
addWorld(source, firstSelection)
addWorld(otherSource, secondSelection)
local selectedForVisual, navigationCancels = nil, 0
SC.GameplayUtil.resolveActor = function() return actor end
SC.GameplayUtil.characterStatValue = function() return 0 end
SC.GameplayUtil.config = function() return nil end
SC.GameplayUtil.move = function(_, _, intent)
    selectedForVisual = intent.item
    return true
end
SC.Navigation.cancel = function()
    navigationCancels = navigationCancels + 1
    return true
end
SC.NativeActions.visualStatus = function() return "active" end
SC.BaseLife.resident = function() return { duty = true, role = "quartermaster" } end
SC.BaseLife.jobFor = function() return job end
SC.BaseLife.outdoorNightRestricted = function() return false end
SC.BaseLife.isInside = function() return true end
SC.BaseLife.guardStatus = function() return false end
SC.BaseLife.touchJob = function() return true end
SC.Downtime, SC.Fishing, SC.Production, SC.BaseWatch = nil, nil, nil, nil
queued, job = Floor.audit(base)
check(queued, "cancellation regression queues first zone")
job.reservedBy, job.state = actor.id, "reserved"
check(select(2, realBaseWork.update(actor)) == "floor_pickup_animation"
    and selectedForVisual == firstSelection,
    "first floor job owns its selected candidate")
local priorCancels = navigationCancels
check(realBaseWork.cancelJob(job.id, actor.id) == true
    and navigationCancels > priorCancels,
    "cancelling selected floor work stops its navigation")
table.remove(base.jobs, 1)
SC.BaseLife.enqueueJob({ type = "sort_floor", target = {
    zoneId = "zone:other", x = 20, y = 10, z = 0 } })
job = base.jobs[#base.jobs]
job.reservedBy, job.state = actor.id, "reserved"
check(select(2, realBaseWork.update(actor)) == "floor_pickup_animation"
    and selectedForVisual == secondSelection,
    "replacement floor job selects from its own zone")

SC_TEST_REPORT = "FLOOR_SORT_PASS pickup=verified reload=verified trash=physical blocked=reported cancel=returned alternate=verified carryback=walked interrupted=feet gone=released absent=released heavy=deferred log_bundle=settled cancel_selection=cleared crowded=root_and_bag_delivered nested=delivered"
