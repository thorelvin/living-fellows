-- SPDX-License-Identifier: MIT
-- Exact timber delivery is exercised separately from ordinary search receipts.
local SC, T = SurvivorCompanion, INTEGRATION_TEST
local I, U = SC.ExpeditionIntegration, SC.GameplayUtil
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
    for index, candidate in ipairs(source.items) do
        if candidate == item then
            table.remove(source.items, index)
            item.container = nil
            local world = { item = item }
            function world:getItem() return self.item end
            item.world = world
            square.worlds[#square.worlds + 1] = world
            T.moves = T.moves + 1
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

clear()
local item = log("walking:1")
local a = T.actor("a", "Alice", {})
local bag = bagFor(a, { item })
a.inventory.capacity = 1 -- root cannot stage the log out of the bag
local construction = T.storage("construction:1", "construction", {}, 1)
local record = create(a, { item })
I.refresh(record)
local status = I.summary(record)
check(status.kind == "wood" and status.version == 2 and status.tripId == "wood:1"
    and status.requestMode == "count" and status.requested == 12,
    "UI receives wood kind, trip and request mode")
check(status.collected == 1 and status.carried == 1 and status.returned == 1
    and status.stored == 0 and status.pending == 1 and not status.complete,
    "returned cargo does not count as stored")
check(select(2, I.update(record, a)) == "expedition_supply_stored"
    and item.container == construction.container and #bag.items == 0
    and #a.inventory.items == 1 and T.moves == 1 and T.animations == 1,
    "exact bag log deposits directly with native loot pose and no overloaded staging")
check(item.data.LF_ExpeditionWood == nil and I.summary(record).complete
    and not I.wants(record, a) and a.order == nil,
    "verified deposit clears cargo protection and does not require resume-duty option")

clear()
item = log("visual:log")
a = T.actor("a", "Alice", { item })
construction = T.storage("construction:1", "construction", {}, 1)
record = create(a, { item })
local visualState, visualToken = "active", 7
SC.NativeActions.visualStatus = function() return visualState end
SC.NativeActions.visualToken = function() return visualToken end
check(select(2, I.update(record, a)) == "base_storage_looting" and T.moves == 0,
    "active storage pose keeps cargo in its exact original owner")
visualState, visualToken = "completed", 8
check(select(2, I.update(record, a)) == "wood_storage_visual_changed"
    and item.container == a.inventory and T.moves == 0,
    "another native animation cannot finish this deposit")
SC.NativeActions.visualStatus = function() return "completed" end
SC.NativeActions.visualToken = function() return 7 end

clear()
local logs = {}
for index = 1, 256 do logs[index] = log("limit:" .. index) end
a = T.actor("a", "Alice", logs)
record = create(a, logs, { request = { mode = "full" } })
check(record.requested == 256 and #I.copy(record).items == 256,
    "full-load ledger and copy support 256 exact receipts")
record.items[257] = clone(record.items[1])
record.items[257].id = "too-many"
check(not I.valid(record), "257th wood receipt is rejected")
record.items[257] = nil
record.version, record.kind = 1, nil
check(not I.valid(record), "ordinary receipt schema cannot inherit the wood ceiling")
record.requested = 8
while #record.items > 17 do table.remove(record.items) end
check(not I.valid(record), "ordinary 16-receipt ceiling is retained")
table.remove(record.items)
check(I.valid(record), "older 16-receipt records still load")

clear()
item = log("yard:log")
a = T.actor("a", "Alice", { item })
yard()
construction = T.storage("construction:1", "construction", {}, 2)
T.storage("general:1", "general", {}, 2)
record = create(a, { item })
check(select(2, I.update(record, a)) == "expedition_supply_stored"
    and item.container == nil and item.world == T.yard.worlds[1]
    and item.world:getItem() == item and #construction.container.items == 0
    and record.items[1].storageId == "yard:1",
    "Log Yard is preferred and verifies the exact native world wrapper")

clear()
item = log("general:log")
a = T.actor("a", "Alice", { item })
T.storage("construction:full", "construction", { T.item("existing", "construction") }, 1)
local denied = T.storage("general:denied", "general", {}, 2)
denied.deposits = false
local general = T.storage("general:1", "general", {}, 2)
record = create(a, { item })
check(select(2, I.update(record, a)) == "expedition_supply_stored"
    and item.container == general.container and #denied.container.items == 0,
    "wood falls through full Construction to deposit-permitted General")

clear()
item = log("route:log")
a = T.actor("a", "Alice", { item })
construction = T.storage("construction:blocked", "construction", {}, 2)
construction.unreachable = true
general = T.storage("general:reachable", "general", {}, 2)
record = create(a, { item })
check(select(2, I.update(record, a)) == "expedition_supply_stored"
    and item.container == general.container,
    "unreachable Construction does not starve reachable General")

clear()
item = log("full:log")
a = T.actor("a", "Alice", { item })
construction = T.storage("construction:full", "construction", { T.item("existing", "construction") }, 1)
record = create(a, { item })
check(I.woodDestinationAvailable(a) == true, "full registered storage is permitted before departure")
local moved, reason = I.update(record, a)
check(not moved and reason == "matching_storage_full" and item.container == a.inventory
    and record.items[1].retryRemainingMs == 180000
    and record.retryRemainingMs == 180000 and not I.wants(record, a),
    "full storage preserves exact cargo and pauses for three minutes")
T.now = 60000
local saved = I.copy(record)
check(saved.retryRemainingMs == 120000 and saved.items[1].retryRemainingMs == 120000,
    "save stores remaining pause rather than process-clock deadline")
I.reset()
T.now = 0
construction.container.items = {}
check(not I.wants(saved, a) and not I.settle(saved), "reload preserves paused delivery obligation")
T.now = 120001
check(I.wants(saved, a) and select(2, I.update(saved, a)) == "expedition_supply_stored"
    and item.container == construction.container,
    "delivery automatically retries after the persisted pause")

clear()
item = log("manual:log")
a = T.actor("a", "Alice", { item })
record = create(a, { item })
check(I.woodDestinationAvailable(a) == false, "missing permitted storage is a preparation blocker")
I.update(record, a)
construction = T.storage("construction:added", "construction", {}, 1)
check(not I.wants(record, a) and I.retry(record) == true and I.wants(record, a)
    and select(2, I.update(record, a)) == "expedition_supply_stored",
    "manual Retry clears the saved delay and attempts actual storage")

clear()
item = log("container:fault")
a = T.actor("a", "Alice", { item })
construction = T.storage("construction:1", "construction", {}, 1)
record = create(a, { item })
T.transferFault = true
check(select(2, I.update(record, a)) == "expedition_supply_stored" and T.moves == 1
    and item.container == construction.container and record.items[1].stored,
    "native mutation followed by false return reconciles exact destination without copying")
check(I.update(record, a) == false and T.moves == 1, "reconciled container transaction cannot deliver twice")

clear()
item = log("yard:fault")
a = T.actor("a", "Alice", { item })
yard()
record = create(a, { item })
T.dropFault = true
check(select(2, I.update(record, a)) == "expedition_supply_stored"
    and #T.yard.worlds == 1 and T.moves == 1,
    "native drop mutation followed by false return reconciles its native world wrapper")
saved = I.copy(record)
saved.items[1].stored, saved.items[1].returned, saved.items[1].storageId = false, false, nil
I.reset()
I.refresh(saved)
check(saved.items[1].stored and saved.items[1].storageId == "yard:1"
    and I.summary(saved).stored == 1 and T.moves == 1,
    "reload repairs a journalled ground deposit by exact ID and ownership proof")

clear()
item = log("missing:log")
a = T.actor("a", "Alice", { item })
record = create(a, { item })
record.items[1].destination = { kind = "container", id = "construction:1" }
construction = T.storage("construction:1", "construction", { log("different:native:id") }, 2)
a.inventory.items, item.container = {}, nil
I.refresh(record)
check(not record.items[1].stored and I.summary(record).carried == 0
    and record.items[1].reason == "cargo_pending" and not I.settle(record) and T.moves == 0,
    "missing cargo never becomes a different log or a completed obligation")
a.dead = true
check(not I.settle(record) and not I.wants(record, a), "death preserves ambiguous cargo without creating replacements")
T.actors.a = nil
I.reset()
check(not I.settle(I.copy(record)), "unloaded or cancelled crew do not silently erase wood receipts")

clear()
item = log("ambiguous:log")
a = T.actor("a", "Alice", { item })
record = create(a, { item })
record.items[1].destination = { kind = "container", id = "construction:1" }
construction = T.storage("construction:1", "construction", { log("ambiguous:log") }, 2)
I.refresh(record)
check(not record.items[1].stored and item.container == a.inventory
    and #construction.container.items == 1 and T.moves == 0,
    "duplicate stable ID in a destination is ambiguous while the original is still carried")

clear()
item = log("yard:blocked")
a = T.actor("a", "Alice", { item })
yard()
a.x = 11
construction = T.storage("construction:1", "construction", {}, 1)
record = create(a, { item })
local requestAny = SC.Navigation.requestAny
SC.Navigation.requestAny = function() return false, "path_blocked:wall" end
check(I.update(record, a) == false and item.container == a.inventory,
    "blocked Log Yard keeps the physical log")
T.now = 180001
check(select(2, I.update(record, a)) == "expedition_supply_stored"
    and item.container == construction.container,
    "after its pause, unreachable Log Yard yields to reachable Construction")
SC.Navigation.requestAny = requestAny

clear()
item = log("claim:log")
a = T.actor("a", "Alice", { item })
construction = T.storage("construction:1", "construction", {}, 2)
record = create(a, { item })
item.data.LF_ExpeditionWood.tripId = "another:trip"
check(select(2, I.update(record, a)) == "wood_cargo_ownership_changed"
    and item.container == a.inventory and #construction.container.items == 0
    and item.data.LF_ExpeditionWood.tripId == "another:trip",
    "changed mission claim prevents deposit and marker cleanup")

clear()
item = log("car:log")
a = T.actor("a", "Alice", {})
bag = bagFor(a, {})
a.carry, a.inventory.capacity = bag, 1
local car = carFor(item)
construction = T.storage("construction:1", "construction", {}, 1)
record = create(a, { item }, { car = car })
I.refresh(record)
check(record.items[1].returned and I.wants(record, a),
    "stopped mission car within camp work reach can unload after actual crew return")
a.inside = false
check(I.wants(record, a), "authorized roadside route remains active while hauler leaves camp boundary")
check(select(2, I.update(record, a)) == "car_trunk_looting" and item.container == car.trunk
    and T.cargoOptions.workReach == true and T.cargoOptions.workCampOnly == true,
    "roadside extraction approaches through bounded camp work navigation and plays native loot")
check(select(2, I.update(record, a)) == "car_item_carried" and item.container == bag
    and T.moves == 1 and #a.inventory.items == 1,
    "roadside trunk log physically transfers into the admitted bag")
check(select(2, I.update(record, a)) == "expedition_supply_stored"
    and item.container == construction.container and T.moves == 2,
    "roadside fallback cargo still requires a separate verified storage transfer")

clear()
item = log("unsafe:car")
a = T.actor("a", "Alice", {})
car = carFor(item)
construction = T.storage("construction:1", "construction", {}, 1)
record = create(a, { item }, { car = car })
car.running = true
check(not I.wants(record, a), "running roadside engine prevents timber unloading")
car.running, car.moving = false, true
check(not I.wants(record, a), "moving roadside car cannot be a delivery source")
car.moving, car.reach = false, false
check(not I.wants(record, a), "car beyond camp work reach remains cargo pending")
car.reach, a.inside = true, false
check(not I.wants(record, a), "outbound crew in reach band do not count as having returned")
a.inside = true
car.locked = true
check(select(2, I.update(record, a)) == "unlock_car_door"
    and record.items[1].retryRemainingMs == 0 and I.wants(record, a),
    "accepted trunk unlocking retains its lease without starting failure cooldown")
car.locked = false
local actual = car
T.car = { id = 73, trunk = actual.trunk }
check(not I.wants(record, a), "another loaded car cannot substitute for the expedition car")
T.car = nil
I.refresh(record)
check(record.items[1].reason == "cargo_pending" and not I.settle(record),
    "unloaded expedition car retains exact delivery obligation")

clear()
item = log("trunk:claim")
a = T.actor("a", "Alice", {})
car = carFor(item)
construction = T.storage("construction:1", "construction", {}, 1)
record = create(a, { item }, { car = car })
item.data.LF_ExpeditionWood.tripId = "another:trip"
check(select(2, I.update(record, a)) == "wood_cargo_ownership_changed"
    and item.container == car.trunk and T.moves == 0 and T.animations == 0,
    "a changed trunk cargo claim is checked before any extraction")

clear()
item = log("loan:log")
a = T.actor("a", "Alice", { item })
construction = T.storage("construction:1", "construction", {}, 1)
record = create(a, { item }, { loans = { a = { itemId = "axe:1", storageId = "tools:1" } } })
check(T.toolCalls == 0 and select(2, I.update(record, a)) == "expedition_supply_stored"
    and T.toolCalls == 0 and I.summary(record).stored == 1 and not I.summary(record).complete,
    "tool return waits for wood deposit and keeps completed-log delivery record alive")
saved = I.copy(record)
I.reset()
check(saved.woodWork.loans.a.itemId == "axe:1" and I.wants(saved, a),
    "loan exact identity survives view release and reload")
check(select(2, I.update(saved, a)) == "wood_axe_returned" and T.toolCalls == 1
    and T.toolContext.missionId == "wood:1" and T.toolContext.roster[1].actor == a
    and I.summary(saved).complete and a.order == nil and not I.wants(saved, a),
    "loan resolves before completion without enabling optional restock or base duty")

clear()
a = T.actor("a", "Alice", {})
record = create(a, {}, { restock = true, loans = { a = { itemId = "axe:2", storageId = "tools:2" } } })
T.blockToolReturn = true
check(I.update(record, a) == false and I.summary(record).toolReason == "wood_tool_source_unavailable"
    and not I.wants(record, a) and a.order == nil and not I.settle(record),
    "unavailable axe destination pauses delivery and cannot resume base duty")
T.blockToolReturn = false
check(I.retry(record) == true and I.wants(record, a), "manual retry also resumes tool return")
for _ = 1, 6 do I.update(record, a) end
check(a.order == "base_duty" and I.summary(record).complete,
    "optional restock and base duty run only after borrowed tool delivery")

SC_TEST_REPORT = "Wood expedition integration: " .. checks .. " checks passed"
