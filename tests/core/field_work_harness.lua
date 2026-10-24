-- SPDX-License-Identifier: MIT
local SC = SurvivorCompanion
local Field = SC.FieldWork
local checks = 0
local function check(value, message)
    checks = checks + 1
    if not value then error("field work check " .. checks .. ": " .. message) end
end
local tick, serial = 1000, 0
local squares, actors = {}, {}
local function square(x, y)
    local id = x .. ":" .. y
    if not squares[id] then squares[id] = { x = x, y = y, z = 0, world = {} } end
    local result = squares[id]
    function result:getTree() return self.tree end
    function result:getWorldObjects() return self.world end
    return result
end
local function item(kind, axe)
    serial = serial + 1
    local value = { kind = kind, id = "item-" .. serial, data = {}, axe = axe }
    function value:getModData() return self.data end
    function value:getContainer() return self.container end
    function value:isBroken() return false end
    return value
end
local function inventory()
    return { items = {}, room = true }
end
local function put(bag, value)
    bag.items[#bag.items + 1] = value
    value.container = bag
end
local function actor(id, x, y)
    local value = { id = id, x = x, y = y, z = 0, bag = inventory(),
        data = {}, active = false }
    function value:getInventory() return self.bag end
    function value:getModData() return self.data end
    function value:getVehicle() return self.car end
    actors[#actors + 1] = value
    return value
end
local player = { x = 100, y = 100, z = 0 }
local one, two = actor("one", 100, 99), actor("two", 101, 99)
local car = { x = 101, y = 101, z = 0, id = 42, locked = false,
    part = { bag = inventory() } }
function car:getSqlId() return self.id end
function car:isTrunkLocked() return self.locked end
function car:setTrunkLocked(value)
    if not self.failUnlock then self.locked = value end
end
function car:getMaxPassengers() return 2 end
function car:isSeatInstalled(seat) return seat == 0 or seat == 1 end
function car:getCharacter(seat)
    for _, value in ipairs(actors) do
        if value.car == self and value.seat == seat then return value end
    end
end
function car:getPassengerDoor()
    return { getDoor = function()
        return { isLocked = function() return car.doorsLocked == true end }
    end }
end
function car:getSeat(value) return value.seat end
function car:getTrunkPart() return self.part end
function car.part:getItemContainer() return self.bag end
function car.part:getArea() return "Trunk" end
function car:getAreaCenter(area)
    return area == "Trunk" and { x = self.x, y = self.y, z = self.z }
        or nil
end
local utility = {}
function utility.call(object, method, ...)
    if not object then return nil, false end
    local member = object[method]
    if type(member) ~= "function" then return nil, false end
    return member(object, ...), true
end
function utility.position(value)
    return value and value.x, value and value.y, value and value.z or 0
end
function utility.gridSquare(x, y, z)
    if z ~= 0 then return nil end
    return square(x, y)
end
function utility.nowMs() tick = tick + 250 return tick end
function utility.config() return nil end
function utility.registryLiving() return actors end
function utility.idOf(value) return value.id end
function utility.modData(value) return value.data end
function utility.itemStableId(value) return value.id end
function utility.itemType(value) return value.kind end
function utility.itemWeight() return 1 end
function utility.itemHasTag(value, tag) return tag == "CHOP_TREE" and value.axe == true end
function utility.inventory(value) return value.bag end
function utility.inventoryContains(bag, sought)
    for _, value in ipairs(bag and bag.items or {}) do
        if value == sought then return true end
    end
    return false
end
function utility.inventoryItems(bag, limit)
    local result = {}
    for i = 1, math.min(#(bag and bag.items or {}), limit or 4096) do
        result[#result + 1] = bag.items[i]
    end
    return result
end
function utility.inventoryLoad(value)
    return #value.bag.items, 10, #value.bag.items / 10, value.bag
end
-- Every fake item weighs 1. The physical inventory holds 10; a worker's
-- Strength limit is the same unless a test lowers carryCapacity.
function utility.carryLoad(value)
    local limit = value.carryCapacity or 10
    return #value.bag.items, limit, #value.bag.items / limit, value.bag
end
function utility.each(values, limit, callback)
    for i = 1, math.min(#(values or {}), limit or 999) do callback(values[i]) end
end
function utility.isSquareFree() return true end
function utility.safehouseBlocker() return false end
function utility.sameSquare(a, b) return a.x == b.x and a.y == b.y end
function utility.transferItemVerified(from, to, value)
    if to.room == false then return false, "destination_full" end
    for index, entry in ipairs(from.items) do
        if entry == value then
            table.remove(from.items, index)
            put(to, value)
            return true, "transferred"
        end
    end
    return false, "source_missing"
end
function utility.takeWorldItemVerified(wrapper, bag, expected)
    if wrapper.item ~= expected then return false, "wrong_item" end
    local from = wrapper.square.world
    for i, entry in ipairs(from) do
        if entry == wrapper then table.remove(from, i) put(bag, expected)
            return true, "taken" end
    end
    return false, "world_item_missing"
end
function utility.move(value, mode, intent)
    value.active = true
    value.pending = intent
    return true, "started"
end
SC.GameplayUtil = utility
SC.Commands = { peek = function(value)
    return { recruited = true, order = value.follow == false and "stay" or "follow" }
end }
SC.BaseLife = { isInside = function() return false end }
SC.Vehicle = { loadedBySqlId = function(id) return id == 42 and car or nil end,
    cargoPart = function(vehicle)
        local part = vehicle and (vehicle.cargoOverride or vehicle.part)
        return part, part and part.bag, part == nil and "car_trunk_missing" or nil
    end,
    isStationary = function() return true end,
    boardingSquares = function(value, vehicle, seat)
        if vehicle == car and seat < 2 then return { square(101, 102) }, seat end
    end,
    cancelTransaction = function(value)
        value.boardCancelled = true
        return true
    end,
    exit = function(value, vehicle)
        if value.car ~= vehicle then return false, "wrong_car" end
        value.car, value.seat = nil, nil
        return true
    end,
}
SC.ExpeditionCar = { boardMember = function(value, order)
    value.car, value.seat = order.car, order.seat
    return true, "native_seat"
end }
local trunkLines = 0
SC.Dialogue = { say = function(_, topic)
    if topic == "vehicle.trunk.unlocked" then trunkLines = trunkLines + 1 end
    return true
end }
SC.TaxiCab = { isOwned = function() return false end }
SC.WorkTransport = { hasRoom = function(bag)
    if bag.room == false then return false, "destination_full" end
    return true
end }
SC.Navigation = {
    interactionTargets = function(value, target)
        return { square(target.x + 1, target.y) }
    end,
    requestAny = function(value, choices)
        local target = choices[1]
        value.x, value.y = target.x, target.y
        return true, "arrived", target
    end,
    cancel = function() return true end,
}
SC.NativeActions = {
    stopDirect = function() return true end,
    startFarm = function(value, intent)
        value.active = true
        value.pending = intent
        return true, "started"
    end,
    isWorkActive = function(value) return value.active end,
    finishWork = function(value) value.pending = nil return true end,
    cancelWork = function(value) value.active = false return true end,
}
CFarmingSystem = { instance = { getLuaObjectOnSquare = function(self, tile)
    return tile.plant
end } }
farming_vegetableconf = { props = {
    Cabbages = { vegetableName = "Base.Cabbage", seedName = "Base.CabbageSeed" },
} }
local function cropAt(x, y, ripe, seedType)
    local tile = square(x, y)
    tile.plant = { ripe = ripe, typeOfSeed = seedType or "Cabbages" }
    function tile.plant:canHarvest() return self.ripe end
    return tile
end
local function finish(value, kind, yieldCount)
    if kind == "harvest" then
        local plant = value.pending.plant
        local props = farming_vegetableconf.props[plant.typeOfSeed]
        local destination = value.harvestDestination or value.bag
        plant.ripe = false
        for _ = 1, yieldCount or 1 do
            if props.vegetableName then put(destination, item(props.vegetableName)) end
            if props.produceExtra then put(destination, item(props.produceExtra)) end
        end
        if plant.hasSeed and props.seedName then
            put(destination, item(props.seedName))
        end
    elseif kind == "chop" then
        local tree = value.pending.tree
        tree.index = -1
        tree.square.tree = nil
        local wood = item("Base.Log")
        tree.square.world[#tree.square.world + 1] = {
            item = wood, square = tree.square,
            getItem = function(self) return self.item end,
        }
    end
    value.active = false
end
local function advance(workers, count)
    for _ = 1, count do
        for _, value in ipairs(workers) do Field.update(value, player) end
    end
end
local placedMarkers = {}
function getWorldMarkers()
    return { addGridSquareMarker = function(_, target)
        local marker = { square = target, removed = false }
        function marker:remove() self.removed = true end
        placedMarkers[#placedMarkers + 1] = marker
        return marker
    end }
end

check(Field.restore(nil) == true, "old save restores idle")
cropAt(100, 100, true)
cropAt(102, 100, true)
local unripe = cropAt(99, 100, false)
Field.observePlayerVehicle(car)
check(Field.start("harvest", square(100, 100), player) == true,
    "field order starts with recent car")
check(#placedMarkers == 1 and placedMarkers[1].square == square(100, 100),
    "field order marks only the clicked tile")
check(Field.status().carId == 42, "car selected by SQL identity")
advance({ one, two }, 40)
check(one.pending and one.pending.operation == "harvest"
    or two.pending and two.pending.operation == "harvest", "ripe crop action started")
local first = one.pending and one or two
local claimed = Field.export().active.workers
check(claimed.one.target ~= claimed.two.target,
    "followers do not claim the same crop")
finish(first, "harvest")
local unrelated = item("Base.Pen")
put(first.bag, unrelated)
advance({ one, two }, 5)
check(Field.status().completed >= 1, "harvest has world proof")
check(unrelated.data.LF_FieldOrder == nil,
    "a concurrent unrelated inventory addition is not adopted as crop yield")
for index, value in ipairs(first.bag.items) do
    if value == unrelated then table.remove(first.bag.items, index) break end
end
check(Field.export().active.done["99:100:0"] == nil,
    "unripe crop is not harvested")
local saved = Field.export()
check(Field.restore(saved) == true, "order and receipts restore")
local other = first == one and two or one
check(other.pending ~= nil, "second worker owns distinct crop")
finish(other, "harvest")
advance({ one, two }, 80)
check(Field.status().phase == "complete", "ripe-crop sweep completes")
check(#car.part.bag.items == 2 and #one.bag.items == 0
    and #two.bag.items == 0, "native harvest output is loaded by identity")
check(unripe.plant.ripe == false,
    "unripe crop remains untouched")
car.locked = true
local result = Field.stop("test")
check(result == true, "stop releases order")
check(placedMarkers[1].removed == true,
    "stopping field work removes the clicked-tile marker")
local unlockOk, unlockReason = Field.start("harvest", square(100, 100), player)
check(unlockOk == true and unlockReason == "field_trunk_unlocking"
    and Field.status().phase == "unlocking" and Field.status().carId == 42,
    "locked recent car is retained while a follower opens its trunk")
check(Field.wants(one, player, SC.Commands.peek(one)) == true
    and Field.wants(two, player, SC.Commands.peek(two)) == false,
    "only one follower owns the unlock step")
check(Field.update(two, player) == false and car.locked,
    "other workers cannot start before the trunk is open")
local savedUnlock = Field.export()
check(Field.restore(savedUnlock) == true
    and Field.status().phase == "unlocking",
    "unfinished unlock step survives save and load")
for _ = 1, 8 do
    Field.update(one, player)
    if Field.status().phase == "working" then break end
end
check(Field.status().phase == "working" and not car.locked
    and one:getVehicle() == nil and trunkLines == 1,
    "follower boards, unlocks, exits, then says one cheeky line: phase=" .. tostring(Field.status().phase)
        .. " locked=" .. tostring(car.locked) .. " seated=" .. tostring(one:getVehicle() ~= nil)
        .. " lines=" .. tostring(trunkLines) .. " stage=" .. tostring(Field.export().active and Field.export().active.unlock and Field.export().active.unlock.stage))
Field.stop("test")
car.locked, car.doorsLocked = true, true
check(Field.start("harvest", square(100, 100), player) == false
    and car.locked and one:getVehicle() == nil,
    "locked doors reject entry without breaking the player's window")
car.doorsLocked = false
car.failUnlock = true
local lockedChopOk, lockedChopReason = Field.start("chop", square(100, 100), player)
check(lockedChopOk == true and lockedChopReason == "field_trunk_unlocking"
    and Field.status().carId == 42,
    "woodcutting waits for the trunk even without an equipped axe")
for _ = 1, 8 do
    Field.update(one, player)
    if Field.status().phase == "paused" then break end
end
check(Field.status().phase == "paused"
    and Field.status().blocker == "car_trunk_unlock_failed"
    and car.locked and one:getVehicle() == nil and trunkLines == 1,
    "failed native unlock exits and pauses without claiming success")
car.failUnlock = false
check(Field.resume() == true and Field.status().phase == "unlocking",
    "failed unlock can be retried after the car becomes operable")
for _ = 1, 8 do
    Field.update(one, player)
    if Field.status().phase == "working" then break end
end
check(Field.status().phase == "working" and not car.locked
    and one:getVehicle() == nil and trunkLines == 2,
    "retry exits before woodcutting and speaks once")
Field.stop("test")
car.locked = false
Field.restore(nil)
one.x, one.y, two.x, two.y = 100, 99, 101, 99
put(one.bag, item("Base.Axe", true))
for x = 100, 105 do
    local tile = square(x, 100)
    tile.tree = { index = 1, square = tile, health = 50 }
    function tile.tree:getObjectIndex() return self.index end
    function tile.tree:getSize() return 3 end
    function tile.tree:getHealth() return self.health end
end
check(Field.start("chop", square(100, 100), player) == true
    and Field.status().carId == nil, "wood trip runs without a car")
for _ = 1, 220 do
    Field.update(one, player)
    Field.update(two, player)
    if one.pending and one.pending.action == "chop_tree" and one.active then
        finish(one, "chop")
    end
    if Field.status().phase == "complete" then break end
end
check(Field.status().completed == 6, "all nearby trees are cleared")
check(square(105, 100).tree == nil, "sixth tree is felled too")
check(#one.bag.items >= 7, "logs carried without a car")
check(Field.status().phase == "complete", "no-car order completes")
Field.restore(nil)
two.follow = false
one.x, one.y = 100, 99
local carriedAxe
for index, value in ipairs(one.bag.items) do
    if value.axe then
        carriedAxe = value
        table.remove(one.bag.items, index)
        break
    end
end
check(carriedAxe ~= nil, "no-car worker kept its axe")
put(car.part.bag, carriedAxe)
local remainingTree = square(105, 100)
remainingTree.tree = { index = 1, square = remainingTree, health = 50 }
function remainingTree.tree:getObjectIndex() return self.index end
function remainingTree.tree:getSize() return 3 end
function remainingTree.tree:getHealth() return self.health end
Field.observePlayerVehicle(car)
check(Field.start("chop", square(100, 100), player) == true,
    "second tree order selects car")
for _ = 1, 220 do
    Field.update(one, player)
    if one.pending and one.pending.action == "chop_tree" and one.active then
        finish(one, "chop")
    end
    if Field.status().phase == "complete" then break end
end
check(Field.status().phase == "complete" and Field.status().completed == 1,
    "single eligible follower fells the next tree: "
        .. tostring(Field.status().phase) .. "/"
        .. tostring(Field.status().completed) .. "/"
        .. tostring(Field.status().blocker) .. "/"
        .. tostring(Field.export().active.workers.one.phase) .. "/"
        .. tostring(Field.export().active.workers.one.scan) .. "/"
        .. tostring(Field.export().active.workers.one.axeId))
local axeBack = false
for _, value in ipairs(car.part.bag.items) do
    if value == carriedAxe then axeBack = true end
end
check(axeBack and carriedAxe.data.LF_FieldBorrowedAxe == nil,
    "borrowed axe returned to same car")
Field.restore(nil)
one.bag = inventory()
one.x, one.y = 100, 99
local extraCrop = cropAt(100, 101, true)
Field.observePlayerVehicle(car)
check(Field.start("harvest", extraCrop, player) == true,
    "harvest order starts for trunk-full recovery")
local cropStarted = false
for _ = 1, 80 do
    Field.update(one, player)
    if one.pending and one.pending.operation == "harvest" then
        cropStarted = true
        finish(one, "harvest")
        break
    end
end
check(cropStarted, "full-trunk fixture reaches its crop before testing delivery")
car.part.bag.room = false
for _ = 1, 90 do
    Field.update(one, player)
    if Field.status().phase == "complete" then break end
end
check(Field.status().phase == "complete"
    and Field.status().note:find("trunk is full", 1, true),
    "full trunk ends the trip with an explanation: "
        .. tostring(Field.status().phase) .. "/" .. tostring(Field.status().note))
check(#one.bag.items == 1 and one.bag.items[1].data.LF_FieldOrder == nil
    and one.bag.items[1].data.LF_FieldCarryWorker == "one"
    and Field.reserved(one.bag.items[1]) == true,
    "full trunk keeps the exact crop protected with its worker")
car.part.bag.room = true
check(Field.resume() == false, "a completed partial trip cannot resume unexpectedly")
Field.restore(nil)
one.bag, car.part.bag = inventory(), inventory()
one.x, one.y = 100, 99
local distantCrop = cropAt(115, 100, true)
Field.observePlayerVehicle(car)
check(Field.start("harvest", square(100, 100), player) == true,
    "extended harvest sweep starts")
for _ = 1, 70 do
    Field.update(one, player)
    if one.pending and one.pending.operation == "harvest" and one.active then break end
end
check(one.pending and one.pending.plant == distantCrop.plant,
    "harvest reaches ripe crops 15 tiles from the marked center")
player.x = 130
Field.leaderPulse(player)
check(Field.status().phase == "working",
    "harvest continues when player moves 30 tiles from marked center")
finish(one, "harvest", 12)
local firstCargoBatch
for _ = 1, 120 do
    Field.update(one, player)
    if not firstCargoBatch and Field.status().loaded > 0 then
        firstCargoBatch = Field.status().loaded
    end
    if Field.status().phase == "complete" then break end
end
check(firstCargoBatch == 8,
    "car unloading batches eight exact harvested items per decision beat")
check(Field.status().phase == "complete" and #car.part.bag.items == 12,
    "extended harvest delivers all crops to the recently used car")
player.x = 100
Field.restore(nil)
one.follow = true
check(Field.start("harvest", square(100, 100), player) == true,
    "new order starts for leader leash")
player.x = 133
Field.leaderPulse(player)
check(Field.status().phase == "stopped"
    and Field.status().blocker == "leader_left_work_area",
    "leaving the field stops work and regroups")
player.x = 100
Field.restore(nil)
one.bag, two.bag, car.part.bag = inventory(), inventory(), inventory()
one.follow, two.follow = true, true
one.x, one.y, two.x, two.y = 100, 99, 101, 99
local sharedAxe = item("Base.Axe", true)
put(car.part.bag, sharedAxe)
local sharedTree = square(100, 100)
sharedTree.tree = { index = 1, square = sharedTree, health = 50 }
function sharedTree.tree:getObjectIndex() return self.index end
function sharedTree.tree:getSize() return 3 end
function sharedTree.tree:getHealth() return self.health end
Field.observePlayerVehicle(car)
check(Field.start("chop", sharedTree, player) == true,
    "shared axe order starts")
Field.update(one, player)
Field.update(two, player)
Field.update(one, player)
Field.update(two, player)
check(Field.status().phase == "working"
    and Field.export().active.workers.two.phase == "waiting_axe"
    and sharedAxe.container == one.bag,
    "unequipped worker waits locally while first owns shared axe")
for _ = 1, 15 do Field.update(one, player) end
check(one.pending and one.pending.action == "chop_tree",
    "equipped worker starts chopping despite shared-axe contention")
car.locked = true
Field.stop("test")
check(sharedAxe.data.LF_FieldBorrowedAxe ~= nil
    and Field.wants(one, player, SC.Commands.peek(one)) == false
    and Field.status().pendingAxeReturns == 1,
    "stopped woodcut keeps an exact axe return obligation while car is locked")
local returnSave = Field.export()
check(Field.restore(returnSave) == true,
    "borrowed axe obligation survives save and restore")
local function deepCopy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = deepCopy(child) end
    return result
end
local corruptions = {
    function(returns) returns.one = "not-a-return" end,
    function(returns) returns.one.center = nil end,
    function(returns) returns.one.kind = "mine" end,
    function(returns) returns.one.carId = "42" end,
    function(returns) returns.one.blocker = 7 end,
    function(returns) returns[5] = deepCopy(returns.one) end,
}
for index, corrupt in ipairs(corruptions) do
    local damaged = deepCopy(Field.export())
    corrupt(damaged.pendingAxeReturns)
    local restored, restoreReason = Field.restore(damaged)
    local live = Field.export().pendingAxeReturns
    check(restored == false and restoreReason == "invalid_field_axe_return_save"
            and Field.status().pendingAxeReturns == 1
            and type(live.one) == "table" and live.one.center ~= nil
            and live.one.kind == "chop" and type(live.one.carId) == "number"
            and live.one.blocker ~= 7 and live[5] == nil,
        "a malformed axe return is rejected and the live obligation kept: "
            .. tostring(index))
end
car.locked = false
car.part.bag.room = false
check(Field.wants(one, player, SC.Commands.peek(one)) == false
    and sharedAxe.container == one.bag,
    "full trunk pauses axe return without taking the worker's item")
car.part.bag.room = true
check(Field.wants(one, player, SC.Commands.peek(one)) == true,
    "axe return resumes after car becomes accessible")
for _ = 1, 8 do
    if sharedAxe.container == car.part.bag then break end
    Field.update(one, player)
end
check(sharedAxe.container == car.part.bag
    and sharedAxe.data.LF_FieldBorrowedAxe == nil,
    "cancelled woodcut returns the same borrowed axe to its car")
Field.restore(nil)
one.x, one.y, player.x, player.y = 100, 99, 100, 100
two.follow = false
Field.observePlayerVehicle(car)
check(Field.start("chop", square(100, 100), player) == true,
    "another woodcut starts before relocating its borrowed car")
for _ = 1, 12 do
    Field.update(one, player)
    if sharedAxe.container == one.bag then break end
end
check(sharedAxe.container == one.bag, "worker borrows the original axe")
Field.stop("relocate")
car.x, car.y, one.x, one.y = 201, 201, 200, 199
player.x, player.y = 200, 200
car.locked = true
check(Field.start("harvest", square(200, 200), player) == true,
    "unrelated field work starts with an outstanding axe return")
local pendingHandled, pendingReason = Field.update(one, player)
check(pendingHandled == true and pendingReason ~= "car_trunk_locked"
    and sharedAxe.container == one.bag
    and Field.status().pendingAxeReturns == 1,
    "inaccessible old return does not consume the new worker's update")
car.locked = false
check(Field.wants(one, player, SC.Commands.peek(one)) == true,
    "old axe return follows its original car after a 100-tile move")
for _ = 1, 8 do
    if sharedAxe.container == car.part.bag then break end
    Field.update(one, player)
end
check(sharedAxe.container == car.part.bag
    and sharedAxe.data.LF_FieldBorrowedAxe == nil
    and Field.status().pendingAxeReturns == 0,
    "moved car receives the exact axe once before new work resumes")
car.x, car.y, one.x, one.y = 101, 101, 100, 99
player.x, player.y = 100, 100
-- A worker who still owes an axe to a car that is gone keeps using that axe
-- for new woodcutting instead of sitting out every later order.
Field.restore(nil)
one.bag, two.bag, car.part.bag = inventory(), inventory(), inventory()
one.follow, two.follow = true, false
one.pending, one.active = nil, false
local owedAxe = item("Base.Axe", true)
put(car.part.bag, owedAxe)
Field.observePlayerVehicle(car)
check(Field.start("chop", sharedTree, player) == true,
    "owed-axe woodcut starts")
for _ = 1, 12 do
    Field.update(one, player)
    if owedAxe.container == one.bag then break end
end
check(owedAxe.container == one.bag, "worker borrows the axe it will owe")
car.locked = true
Field.stop("car_left")
check(Field.status().pendingAxeReturns == 1
    and owedAxe.data.LF_FieldBorrowedAxe ~= nil,
    "stopped woodcut leaves an exact axe return")
local originalLoadedBySqlId = SC.Vehicle.loadedBySqlId
car.id, car.locked = 43, false
SC.Vehicle.loadedBySqlId = function(id) return id == car.id and car or nil end
one.pending, one.active = nil, false
Field.observePlayerVehicle(car)
check(Field.start("chop", sharedTree, player) == true,
    "new woodcut starts after the original car is gone")
for _ = 1, 20 do
    Field.update(one, player)
    if one.pending and one.pending.action == "chop_tree" then break end
end
check(one.pending and one.pending.action == "chop_tree"
    and one.pending.tool == owedAxe
    and Field.status().phase == "working"
    and Field.status().pendingAxeReturns == 1
    and owedAxe.data.LF_FieldBorrowedAxe ~= nil,
    "worker chops with the axe it still owes instead of leaving the order: "
        .. tostring(Field.status().phase) .. "/"
        .. tostring(Field.export().active
            and Field.export().active.workers.one.phase))
Field.stop("test")
SC.Vehicle.loadedBySqlId = originalLoadedBySqlId
car.id = 42
Field.restore(nil)
one.bag, two.bag, car.part.bag = inventory(), inventory(), inventory()
two.follow = false
for _ = 1, 7 do put(one.bag, item("Base.Pen")) end
local fullCrop = cropAt(100, 100, true)
check(Field.start("harvest", fullCrop, player) == true,
    "no-car capacity test starts")
for _ = 1, 80 do
    Field.update(one, player)
    if one.pending and one.pending.operation == "harvest" then break end
end
check(one.pending and one.pending.operation == "harvest",
    "no-car capacity fixture reaches its crop")
finish(one, "harvest")
-- The closing check of the 16-tile harvest area takes about 13 updates.
advance({ one }, 20)
check(Field.status().phase == "complete"
    and Field.wants(one, player, SC.Commands.peek(one)) == false,
    "no-car full worker completes and releases follow ownership")
local carried = one.bag.items[#one.bag.items]
check(carried and carried.data.LF_FieldCarryWorker == "one"
    and Field.reserved(carried) == true,
    "no-car harvest remains protected for player pickup after completion")
local carriedAudit = { items = { { item = carried, category = "food",
        source = one.bag } }, counts = { food = 10 },
    profile = { target = { food = 1 }, keep = { food = 0 } },
    ratio = 0.95, hardRatio = 0.9 }
check(SC.Logistics.selectSurplus(one, carriedAudit) == nil,
    "completed no-car harvest does not drop one crop at a time")
table.remove(one.bag.items, #one.bag.items)
check(Field.reserved(carried) == false
    and carried.data.LF_FieldCarryWorker == nil,
    "manual removal releases the carried-crop reservation")
local orphan = item("Base.Cabbage")
orphan.data.LF_FieldCarryWorker = "retired"
check(Field.reserved(orphan) == true,
    "unknown carrier is protected during initial restore grace")
for _ = 1, 125 do utility.nowMs() end
check(Field.reserved(orphan) == false
    and orphan.data.LF_FieldCarryWorker == nil,
    "permanently absent carrier eventually releases stale harvest cargo")
Field.restore(nil)
farming_vegetableconf.props.ModCrop = {
    vegetableName = "OtherMod.Blueberry",
    produceExtra = "OtherMod.Stem",
    seedName = "OtherMod.BlueberrySeed",
}
one.bag, car.part.bag = inventory(), inventory()
one.follow, two.follow = true, false
one.x, one.y = 100, 99
local modCrop = cropAt(100, 102, true, "ModCrop")
modCrop.plant.hasSeed = true
Field.observePlayerVehicle(car)
check(Field.start("harvest", modCrop, player) == true,
    "modded crop order begins")
for _ = 1, 80 do
    Field.update(one, player)
    if one.pending and one.pending.operation == "harvest" and one.active then break end
end
check(one.pending and one.pending.plant == modCrop.plant,
    "modded crop native action starts")
finish(one, "harvest")
advance({ one }, 50)
check(Field.status().phase == "complete" and #car.part.bag.items == 3,
    "registered mod crop produce, extra yield and seed reach the car")
Field.restore(nil)
one.bag, car.part.bag = inventory(), inventory()
put(car.part.bag, item("Base.Axe", true))
Field.observePlayerVehicle(car)
check(Field.start("chop", sharedTree, player) == true,
    "contact test starts")
local originalInteraction = SC.Navigation.interactionTargets
SC.Navigation.interactionTargets = function(value, target, options)
    if target.x == car.x and target.y == car.y then
        check(options.requireDirectAccess == true,
            "trunk approach requires direct contact")
        return {}
    end
    return originalInteraction(value, target, options)
end
Field.update(one, player)
Field.update(one, player)
check(Field.status().phase == "paused"
    and #car.part.bag.items == 1 and #one.bag.items == 0,
    "blocked trunk contact cannot transfer shared tool")
SC.Navigation.interactionTargets = originalInteraction
Field.stop("test")
Field.restore(nil)
local orphan = item("Base.Cabbage")
orphan.data.LF_FieldOrder = "field:obsolete"
orphan.data.LF_FieldWorker = "dead"
check(Field.reserved(orphan) == false
    and orphan.data.LF_FieldOrder == nil,
    "orphan cargo marker releases after order retirement")
local orphanAxe = item("Base.Axe", true)
orphanAxe.data.LF_FieldBorrowedAxe = "field:obsolete"
orphanAxe.data.LF_FieldWorker = "dead"
check(Field.reserved(orphanAxe) == false
    and orphanAxe.data.LF_FieldBorrowedAxe == nil,
    "orphan axe marker releases after order retirement")
one.bag, car.part.bag = inventory(), inventory()
one.x, one.y = 100, 99
one.follow, two.follow = true, false
check(Field.start("harvest", square(100, 100), player) == true,
    "field cargo ownership test starts")
local harvested = item("Base.Cabbage")
harvested.data.LF_FieldOrder = Field.export().active.id
harvested.data.LF_FieldWorker = "one"
put(one.bag, harvested)
local audit = { items = { { item = harvested, category = "food", source = one.bag } },
    counts = { food = 10 }, profile = { target = { food = 1 },
        keep = { food = 0 } }, ratio = 0.95, hardRatio = 0.9 }
check(SC.Logistics.selectSurplus(one, audit) == nil,
    "generic overload handling cannot drop reserved harvest cargo")
local unowned = item("Base.Cabbage")
put(one.bag, unowned)
audit.items[#audit.items + 1] = { item = unowned, category = "food", source = one.bag }
check(SC.Logistics.selectSurplus(one, audit).item == unowned,
    "ordinary surplus still unloads while harvest cargo is reserved")
Field.stop("test")
check(harvested.data.LF_FieldCarryWorker == "one"
    and Field.reserved(harvested) == true,
    "stopping an order retains undelivered crops for player pickup")
-- Playtest: a no-car harvest kept for pickup must never make a companion
-- shed his own gear, and one plant must not carry him past his capacity.
Field.restore(nil)
one.bag, two.bag, car.part.bag = inventory(), inventory(), inventory()
one.x, one.y, player.x, player.y = 100, 99, 100, 100
one.follow, two.follow = true, false
one.pending, one.active = nil, false
for _, entry in pairs(squares) do entry.plant = nil end
for _ = 1, 3 do put(one.bag, item("Base.Pen")) end
local firstCrop, secondCrop = cropAt(100, 100, true), cropAt(101, 100, true)
check(Field.start("harvest", firstCrop, player) == true,
    "capacity-aware harvest starts without a car")
for _ = 1, 80 do
    Field.update(one, player)
    if one.pending and one.pending.operation == "harvest" and one.active then break end
end
check(one.pending and one.pending.operation == "harvest",
    "first crop harvest starts at 30% load")
local firstPlant = one.pending.plant
finish(one, "harvest", 4)
advance({ one }, 40)
check(Field.status().phase == "complete"
    and (firstPlant == firstCrop.plant and secondCrop.plant.ripe == true
        or firstPlant == secondCrop.plant and firstCrop.plant.ripe == true)
    and #one.bag.items == 7,
    "a second four-item yield from 70% load would exceed capacity, so the "
        .. "worker stops instead: " .. tostring(Field.status().phase) .. "/"
        .. tostring(#one.bag.items))
utility.hasMethod = utility.hasMethod or function(value, name)
    return type(value) == "table" and type(value[name]) == "function"
end
utility.instanceOf = utility.instanceOf or function() return false end
local function edible(value) value.getCalories = function() return 50 end return value end
for _, value in ipairs(one.bag.items) do
    if value.kind == "Base.Cabbage" then edible(value) end
end
local ration = edible(item("Base.Apple"))
local idCard = item("Base.IDcard")
put(one.bag, ration)
put(one.bag, idCard)
local keptCabbages = 0
for _, value in ipairs(one.bag.items) do
    if value.data.LF_FieldCarryWorker == "one" and Field.reserved(value) then
        keptCabbages = keptCabbages + 1
    end
end
local load = SC.Logistics.status(one)
check(keptCabbages == 4 and load.ratio > load.softRatio
    and load.surplus == nil and load.shouldUnload == false
    and (load.gearRatio or 1) < load.softRatio,
    "kept harvest weight does not make the companion drop its own gear: "
        .. tostring(load.ratio) .. "/" .. tostring(load.gearRatio) .. "/"
        .. tostring(load.surplus and load.surplus.item.kind))
SC.BaseLife.isInside = function() return true end
for _ = 1, 3 do utility.nowMs() end
load = SC.Logistics.status(one)
check(load.fieldReturnCleanup == true and load.fieldReturnCargo == true
    and load.surplus ~= nil and load.surplus.keptHarvest == true,
    "returning crop cargo preempts ordinary follow without shedding gear")
local returnBag = one.bag
one.bag = inventory()
put(one.bag, item("Base.EmptyCan"))
for _ = 1, 3 do utility.nowMs() end
load = SC.Logistics.status(one)
check(load.ratio < load.softRatio and load.shouldUnload == true
    and load.surplus.item.kind == "Base.EmptyCan",
    "field return shelves ordinary surplus even below overload threshold")
one.bag = returnBag
SC.BaseLife.isInside = function() return false end
local cabbageCount = 0
for _, value in ipairs(one.bag.items) do
    if value.kind == "Base.Cabbage" then cabbageCount = cabbageCount + 1 end
end
for _ = 1, 3 do put(one.bag, item("Base.Pen")) end
for _ = 1, 3 do utility.nowMs() end -- past the 500 ms audit cache
load = SC.Logistics.status(one)
check((load.gearRatio or 0) > load.softRatio and load.surplus ~= nil
    and load.surplus.item ~= ration
    and load.surplus.item.data.LF_FieldCarryWorker == nil
    and cabbageCount == 4,
    "genuine gear overload still sheds, but rations are not inflated into "
        .. "surplus by the kept harvest: "
        .. tostring(load.surplus and load.surplus.item.kind))
-- Owned items WorkTransport already refuses to move are not pack surplus
-- either, even when the companion is genuinely over its unload threshold.
one.bag = inventory()
local owned = {}
for index = 1, 8 do
    local value = item("Base.Notebook")
    if index <= 3 then value.data.LF_QuestItem = true
    elseif index <= 6 then value.data.SC_ChefSupplyReceipt = "job:chef:" .. index
    else value.data.LF_TradeRecoveryId = "trade:" .. index end
    owned[value] = true
    put(one.bag, value)
end
for _ = 1, 3 do utility.nowMs() end
load = SC.Logistics.status(one)
check(load.ratio > load.softRatio and load.surplus == nil
    and load.shouldUnload == false,
    "quest items, chef supplies and trade recovery are never shed as surplus: "
        .. tostring(load.surplus and load.surplus.item.kind))
-- One native harvest can add the vegetable, an equal number of extra items,
-- and seeds at once. Reserve room for the whole yield before starting it.
Field.restore(nil)
one.bag, two.bag = inventory(), inventory()
one.x, one.y, player.x, player.y = 100, 99, 100, 100
one.follow, two.follow, one.pending, one.active = true, false, nil, false
for _, entry in pairs(squares) do entry.plant = nil end
for _ = 1, 4 do put(one.bag, item("Base.Pen")) end
local heavyCrop = cropAt(100, 100, true, "YieldHeavy")
heavyCrop.plant.hasSeed, heavyCrop.plant.bonusYield = true, true
farming_vegetableconf.props.YieldHeavy = {
    vegetableName = "Base.Cabbage", produceExtra = "Base.Cabbage",
    seedName = "Base.CabbageSeed", maxVegAutorized = 3,
}
local oldManager, oldPerks = getScriptManager, Perks
Perks = { Farming = "Farming" }
one.getPerkLevel = function() return 0 end
getScriptManager = function()
    return { FindItem = function()
        return { getActualWeight = function() return 1 end }
    end }
end
check(Field.start("harvest", heavyCrop, player) == true,
    "heavy crop order starts before capacity assessment")
for _ = 1, 80 do
    Field.update(one, player)
    if Field.status().blocker == "field_carry_limit_reached" then break end
end
check(Field.status().blocker == "field_carry_limit_reached"
    and heavyCrop.plant.ripe == true and one.pending == nil,
    "extra produce, bonus yield, and seeds prevent an over-capacity harvest")
getScriptManager, Perks, one.getPerkLevel = oldManager, oldPerks, nil
-- A pumpkin plant can outweigh an average companion's whole Strength limit.
-- An empty-handed worker still takes that one plant when it physically fits,
-- then ends the trip instead of starting a second.
do
    Field.restore(nil)
    one.bag, two.bag, car.part.bag = inventory(), inventory(), inventory()
    one.x, one.y, player.x, player.y = 100, 99, 100, 100
    one.follow, two.follow, one.pending, one.active = true, false, nil, false
    for _, entry in pairs(squares) do entry.plant = nil end
    put(one.bag, item("Base.Pen"))
    one.carryCapacity = 4
    farming_vegetableconf.props.YieldBulky = {
        vegetableName = "Base.Pumpkin", maxVegAutorized = 5,
    }
    local bulky = cropAt(100, 100, true, "YieldBulky")
    local nextBulky = cropAt(101, 100, true, "YieldBulky")
    local savedManager, savedPerks = getScriptManager, Perks
    Perks = { Farming = "Farming" }
    one.getPerkLevel = function() return 0 end
    getScriptManager = function()
        return { FindItem = function()
            return { getActualWeight = function() return 1 end }
        end }
    end
    check(Field.start("harvest", bulky, player) == true,
        "bulky crop order starts without a car")
    for _ = 1, 60 do
        Field.update(one, player)
        if one.pending and one.pending.operation == "harvest" then break end
    end
    check(one.pending and one.pending.operation == "harvest"
            and one.pending.plant == bulky.plant,
        "an empty-handed worker starts one plant heavier than its Strength limit: "
            .. tostring(Field.status().blocker))
    finish(one, "harvest", 5)
    for _ = 1, 60 do
        Field.update(one, player)
        if one.pending and one.pending.plant == nextBulky.plant then break end
    end
    check(nextBulky.plant.ripe == true
            and not (one.pending and one.pending.plant == nextBulky.plant),
        "with that harvest carried, the worker does not start a second plant")
    getScriptManager, Perks, one.getPerkLevel = savedManager, savedPerks, nil
    one.carryCapacity = nil
    farming_vegetableconf.props.YieldBulky = nil
end
-- A worker who died mid-order can never report done. Once the shared rule
-- says the companion is gone, the others complete the order; a dormant
-- worker (no living actor yet, not proven gone) still holds it open.
do
    Field.restore(nil)
    one.bag, two.bag, car.part.bag = inventory(), inventory(), inventory()
    one.x, one.y, two.x, two.y, player.x, player.y = 100, 99, 101, 99, 100, 100
    one.follow, two.follow, one.pending, one.active = true, true, nil, false
    two.pending, two.active = nil, false
    for _, entry in pairs(squares) do entry.plant = nil end
    local lastCrop = cropAt(100, 100, true)
    check(Field.start("harvest", lastCrop, player) == true,
        "two-worker order starts")
    local twoIndex
    for index, value in ipairs(actors) do
        if value == two then twoIndex = index end
    end
    table.remove(actors, twoIndex)
    local savedFuel, gone = SC.BaseFuel, false
    SC.BaseFuel = { workerIdGone = function(id) return gone and id == "two" end }
    for _ = 1, 60 do
        Field.update(one, player)
        if one.pending and one.pending.operation == "harvest" then break end
    end
    finish(one, "harvest")
    for _ = 1, 60 do Field.update(one, player) end
    check(Field.status().phase ~= "complete",
        "a dormant worker who may still return keeps the order open")
    gone = true
    -- The closing check of the 16-tile harvest area takes about 13 updates.
    for _ = 1, 20 do
        Field.update(one, player)
        if Field.status().phase == "complete" then break end
    end
    check(Field.status().phase == "complete",
        "a worker who is gone for good no longer holds the order open: "
            .. tostring(Field.status().phase))
    table.insert(actors, twoIndex, two)
    SC.BaseFuel = savedFuel
    two.follow = false
end
Field.restore(nil)
one.bag, two.bag, car.part.bag = inventory(), inventory(), inventory()
one.x, one.y, player.x, player.y = 100, 99, 100, 100
one.follow, two.follow, one.pending, one.active = true, false, nil, false
for _, entry in pairs(squares) do entry.plant = nil end
local backpack = item("Base.Duffelbag")
local insideBackpack = inventory()
function backpack:getItemContainer() return insideBackpack end
put(one.bag, backpack)
one.harvestDestination = insideBackpack
local bagCrop = cropAt(100, 100, true)
bagCrop.plant.hasSeed = true
Field.observePlayerVehicle(car)
check(Field.start("harvest", bagCrop, player) == true,
    "bag harvest starts with the selected car")
for _ = 1, 60 do
    Field.update(one, player)
    if one.pending and one.pending.operation == "harvest" then break end
end
check(one.pending and one.pending.operation == "harvest",
    "bag harvest reaches the native crop action")
finish(one, "harvest")
for _ = 1, 100 do
    Field.update(one, player)
    if Field.status().phase == "complete" then break end
end
one.harvestDestination = nil
check(Field.status().phase == "complete" and Field.status().loaded == 2
    and #insideBackpack.items == 0 and #car.part.bag.items == 2
    and #one.bag.items == 1,
    "produce and seeds move by identity from the worn bag into the trunk")
check(one.data and one.data.LF_FieldReturnCleanup ~= nil,
    "completed field trip schedules camp inventory cleanup")
-- A car within ten tiles is not silently chosen unless it was recently used.
-- When no car is assigned, carry capacity limits collection, not clearing.
local spoken = {}
utility.say = function(_, line) spoken[#spoken + 1] = line end
local function standingTree(x, y)
    local tile = square(x, y)
    tile.tree = { index = 1, square = tile, health = 50 }
    function tile.tree:getObjectIndex() return self.index end
    function tile.tree:getSize() return 3 end
    function tile.tree:getHealth() return self.health end
    return tile
end
Field.restore(nil)
one.bag, two.bag, car.part.bag = inventory(), inventory(), inventory()
one.x, one.y, player.x, player.y, car.x, car.y = 300, 299, 300, 300, 310, 300
one.follow, two.follow, one.pending, one.active = true, false, nil, false
one.carryCapacity = 2
put(one.bag, item("Base.Axe", true))
for x = 300, 302 do standingTree(x, 300) end
check(Field.start("chop", square(300, 300), player) == true
    and Field.status().carId == nil, "a nearby unused car is not silently claimed")
for _ = 1, 220 do
    Field.update(one, player)
    if one.pending and one.pending.action == "chop_tree" and one.active then
        finish(one, "chop")
    end
    if Field.status().phase == "complete" then break end
end
check(Field.status().phase == "complete" and Field.status().completed == 3,
    "full inventory does not stop a three-tree clearing order")
check(#one.bag.items == 1 and #square(300, 300).world == 1
    and #square(301, 300).world == 1 and #square(302, 300).world == 1,
    "the overloaded worker leaves all new logs on the ground")
check(#spoken == 3 and spoken[1]:find("clear the trees", 1, true)
    and spoken[2]:find("no car is assigned", 1, true)
    and spoken[3]:find("All the trees", 1, true)
    and Field.status().blocker:find("no car is assigned", 1, true),
    "the worker announces the order, collection limit, and verified clearing")

-- A full trunk must also leave an active tree-clearing order running.
Field.restore(nil)
one.bag, car.part.bag = inventory(), inventory()
one.x, one.y, player.x, player.y, car.x, car.y = 320, 319, 320, 320, 330, 320
one.pending, one.active, one.carryCapacity = nil, false, 10
for _ = 1, 6 do put(one.bag, item("Base.Pen")) end
local fullTrunkAxe = item("Base.Axe", true)
put(car.part.bag, fullTrunkAxe)
for x = 320, 322 do standingTree(x, 320) end
car.part.bag.room = false
Field.observePlayerVehicle(car)
check(Field.start("chop", square(320, 320), player) == true
    and Field.status().carId == 42, "the used car ten tiles away is assigned")
local restoredFullTrunk = false
for _ = 1, 220 do
    Field.update(one, player)
    if one.pending and one.pending.action == "chop_tree" and one.active then
        finish(one, "chop")
    end
    if not restoredFullTrunk and Field.export().active.workers.one.skipPickup then
        check(Field.restore(Field.export()) == true,
            "full-trunk clearing state survives save and load")
        restoredFullTrunk = true
    end
    if Field.status().phase == "complete" then break end
end
check(restoredFullTrunk and Field.status().phase == "complete"
    and Field.status().completed == 3,
    "a full trunk does not stop a three-tree clearing order")
check(#car.part.bag.items == 0 and #one.bag.items == 8
    and #square(320, 320).world == 0
    and #square(321, 320).world == 1 and #square(322, 320).world == 1,
    "one exact log stays carried and later logs stay on the ground")
check(#spoken == 6 and spoken[4]:find("clear the trees", 1, true)
    and spoken[5]:find("trunk are full", 1, true)
    and spoken[6]:find("All the trees", 1, true)
    and Field.export().active.note:find("trunk are full", 1, true)
    and Field.status().pendingAxeReturns == 1,
    "the worker announces the order, full trunk, and verified clearing")
car.part.bag.room = true
for _ = 1, 8 do
    if Field.status().pendingAxeReturns == 0 then break end
    Field.update(one, player)
end
check(Field.status().pendingAxeReturns == 0
    and fullTrunkAxe.container == car.part.bag,
    "the borrowed axe returns after trunk space opens")

-- A real log (9) beside an axe (3) is over 80% of an average companion's
-- Strength limit (12). With a car, a worker holding none of the order's logs
-- still takes one and walks it to the trunk, one log per trip.
Field.restore(nil)
one.bag, car.part.bag = inventory(), inventory()
one.x, one.y, player.x, player.y, car.x, car.y = 350, 349, 350, 350, 358, 350
one.pending, one.active, one.carryCapacity = nil, false, 2
put(one.bag, item("Base.Axe", true))
for x = 350, 352 do standingTree(x, 350) end
Field.observePlayerVehicle(car)
check(Field.start("chop", square(350, 350), player) == true
    and Field.status().carId == 42, "the heavy-log car order starts with the car")
for _ = 1, 300 do
    Field.update(one, player)
    if one.pending and one.pending.action == "chop_tree" and one.active then
        finish(one, "chop")
    end
    if Field.status().phase == "complete" then break end
end
local trunkLogs = 0
for _, entry in ipairs(car.part.bag.items) do
    if entry.kind == "Base.Log" then trunkLogs = trunkLogs + 1 end
end
check(Field.status().phase == "complete" and trunkLogs == 3
    and #square(350, 350).world == 0 and #square(351, 350).world == 0
    and #square(352, 350).world == 0
    and not Field.export().active.workers.one.skipPickup,
    "every log reaches the car although each one is over the Strength limit: logs="
        .. trunkLogs .. " phase=" .. tostring(Field.status().phase))

Field.restore(nil)
one.bag, one.carryCapacity = inventory(), nil
one.x, one.y, player.x, player.y = 340, 339, 340, 340
put(one.bag, item("Base.Axe", true))
standingTree(340, 340)
check(Field.start("chop", square(340, 340), player) == true,
    "the 25-tile leader range test starts")
player.x = 364
Field.leaderPulse(player)
check(Field.status().phase == "working", "chopping continues at 24 tiles")
player.x = 366
Field.leaderPulse(player)
check(Field.status().phase == "stopped"
    and Field.status().blocker == "leader_left_work_area",
    "chopping regroups when the player moves beyond 25 tiles")

-- Skipped, unreachable trees must not be announced as cleared.
Field.restore(nil)
one.bag, one.carryCapacity = inventory(), nil
one.x, one.y, player.x, player.y = 380, 379, 380, 380
put(one.bag, item("Base.Axe", true))
local unreachableTree = standingTree(380, 380)
local priorSpeechCount = #spoken
local normalInteraction = SC.Navigation.interactionTargets
SC.Navigation.interactionTargets = function(value, target, options)
    if target == unreachableTree then return {} end
    return normalInteraction(value, target, options)
end
check(Field.start("chop", unreachableTree, player) == true,
    "unreachable-tree clearing order starts")
for _ = 1, 100 do
    Field.update(one, player)
    if Field.status().phase == "complete" then break end
end
SC.Navigation.interactionTargets = normalInteraction
check(Field.status().phase == "complete" and unreachableTree.tree ~= nil
    and #spoken == priorSpeechCount + 2
    and spoken[#spoken]:find("still standing", 1, true),
    "the companion reports remaining unreachable trees instead of claiming all clear")

-- Away harvest keeps exact produce, leaves crops growing at the carry limit,
-- and reports the incomplete area instead of silently dropping vegetables.
Field.restore(nil)
spoken = {}
one.bag, car.part.bag = inventory(), inventory()
one.x, one.y, player.x, player.y = 400, 399, 400, 400
one.pending, one.active, one.carryCapacity = nil, false, 10
for _ = 1, 3 do put(one.bag, item("Base.Pen")) end
local noCarCrops = {
    cropAt(400, 400, true), cropAt(401, 400, true), cropAt(402, 400, true),
}
check(Field.start("harvest", noCarCrops[1], player) == true
    and Field.status().carId == nil, "away harvest starts without a car")
for _ = 1, 220 do
    Field.update(one, player)
    if one.pending and one.pending.operation == "harvest" and one.active then
        finish(one, "harvest", 4)
    end
    if Field.status().phase == "complete" then break end
end
local ripe = 0
for _, tile in ipairs(noCarCrops) do
    if tile.plant.ripe then ripe = ripe + 1 end
end
local kept = 0
for _, value in ipairs(one.bag.items) do
    if value.data.LF_FieldCarryWorker == "one" and Field.reserved(value) then
        kept = kept + 1
    end
end
check(Field.status().phase == "complete" and Field.status().completed == 1
    and ripe == 2 and kept == 4 and #one.bag.items == 7,
    "full bag safely ends the trip with four exact crops and two plants still growing")
check(#spoken == 3 and spoken[1]:find("harvest the ready crops", 1, true)
    and spoken[2]:find("no car is assigned", 1, true)
    and spoken[3]:find("still growing", 1, true),
    "away farmer announces start, capacity limit, and partial finish")

-- If the assigned trunk fills, keep already harvested items on the worker.
-- A save/load during that transition must not duplicate or drop produce.
Field.restore(nil)
spoken = {}
one.bag, car.part.bag = inventory(), inventory()
one.x, one.y, player.x, player.y, car.x, car.y = 420, 419, 420, 420, 430, 420
one.pending, one.active = nil, false
for _ = 1, 3 do put(one.bag, item("Base.Pen")) end
local trunkCrops = {
    cropAt(420, 420, true), cropAt(421, 420, true), cropAt(422, 420, true),
}
car.part.bag.room = false
Field.observePlayerVehicle(car)
check(Field.start("harvest", trunkCrops[1], player) == true
    and Field.status().carId == 42, "away harvest selects the recently used car")
local savedFullHarvest = false
for _ = 1, 220 do
    Field.update(one, player)
    if one.pending and one.pending.operation == "harvest" and one.active then
        finish(one, "harvest", 4)
    end
    if not savedFullHarvest and Field.export().active.workers.one.skipDeposit then
        check(Field.restore(Field.export()) == true,
            "harvest with full trunk survives save and load")
        savedFullHarvest = true
    end
    if Field.status().phase == "complete" then break end
end
ripe, kept = 0, 0
for _, tile in ipairs(trunkCrops) do
    if tile.plant.ripe then ripe = ripe + 1 end
end
for _, value in ipairs(one.bag.items) do
    if value.data.LF_FieldCarryWorker == "one" and Field.reserved(value) then
        kept = kept + 1
    end
end
check(savedFullHarvest and Field.status().phase == "complete"
    and Field.status().completed == 1 and ripe == 2 and kept == 4
    and #car.part.bag.items == 0,
    "full trunk leaves later crops growing and keeps exact produce with worker")
check(#spoken == 3 and spoken[1]:find("harvest the ready crops", 1, true)
    and spoken[2]:find("bag and the trunk are full", 1, true)
    and spoken[3]:find("still growing", 1, true),
    "farmer announces full trunk and partial completion once each")
car.part.bag.room = true

-- The existing 16-tile harvest circle finishes every reachable plant and
-- leaves a plant just outside the marked area alone.
Field.restore(nil)
spoken = {}
one.bag = inventory()
one.x, one.y, player.x, player.y = 440, 439, 440, 440
one.pending, one.active = nil, false
local centerCrop = cropAt(440, 440, true)
local edgeCrop = cropAt(456, 440, true)
local outsideCrop = cropAt(457, 440, true)
check(Field.start("harvest", centerCrop, player) == true,
    "sixteen-tile harvest area starts")
for _ = 1, 220 do
    Field.update(one, player)
    if one.pending and one.pending.operation == "harvest" and one.active then
        finish(one, "harvest")
    end
    if Field.status().phase == "complete" then break end
end
check(Field.status().phase == "complete" and Field.status().completed == 2
    and centerCrop.plant.ripe == false and edgeCrop.plant.ripe == false
    and outsideCrop.plant.ripe == true and #one.bag.items == 2,
    "all crops inside the existing radius are harvested and kept in the bag")
check(#spoken == 2 and spoken[1]:find("harvest the ready crops", 1, true)
    and spoken[2]:find("All the ripe crops", 1, true),
    "farmer announces start and verified complete harvest")

-- A heavier next plant can require an unloading trip. The farmer must
-- revisit that exact plant after depositing rather than skip it in the scan.
Field.restore(nil)
spoken = {}
one.bag, car.part.bag = inventory(), inventory()
one.x, one.y, player.x, player.y, car.x, car.y = 460, 459, 460, 460, 470, 460
one.pending, one.active = nil, false
for _ = 1, 4 do put(one.bag, item("Base.Pen")) end
local lightCrop = cropAt(460, 460, true)
local heavyNext = cropAt(461, 460, true, "YieldFive")
farming_vegetableconf.props.YieldFive = {
    vegetableName = "Base.Cabbage", maxVegAutorized = 5,
}
local savedManager, savedPerks = getScriptManager, Perks
Perks = { Farming = "Farming" }
one.getPerkLevel = function() return 0 end
getScriptManager = function()
    return { FindItem = function()
        return { getActualWeight = function() return 1 end }
    end }
end
Field.observePlayerVehicle(car)
check(Field.start("harvest", lightCrop, player) == true,
    "mixed-yield harvest starts with a car")
for _ = 1, 260 do
    Field.update(one, player)
    if one.pending and one.pending.operation == "harvest" and one.active then
        finish(one, "harvest", one.pending.plant == heavyNext.plant and 5 or 1)
    end
    if Field.status().phase == "complete" then break end
end
check(Field.status().phase == "complete" and Field.status().completed == 2
    and Field.status().loaded == 6 and lightCrop.plant.ripe == false
    and heavyNext.plant.ripe == false and #car.part.bag.items == 6,
    "farmer unloads then revisits the skipped heavy plant within the same order")
getScriptManager, Perks, one.getPerkLevel = savedManager, savedPerks, nil
farming_vegetableconf.props.YieldFive = nil

Field.restore(nil)
one.bag = inventory()
one.x, one.y, player.x, player.y = 530, 500, 500, 500
one.follow, two.follow = true, false
local longReachCrop = cropAt(500, 500, true)
check(Field.available(player, "harvest") == true
    and Field.available(player, "chop") == false
    and Field.start("harvest", longReachCrop, player) == true,
    "away harvest can use a follower within its 32-tile leash")
Field.stop("test")

-- The closing check of what is left covers about 800 tiles for a harvest.
-- It runs a slice per update, never the whole area in one frame.
Field.restore(nil)
spoken = {}
one.bag = inventory()
one.x, one.y, player.x, player.y = 600, 599, 600, 600
one.pending, one.active, one.carryCapacity = nil, false, 10
local slicedCrop = cropAt(600, 600, true)
check(Field.start("harvest", slicedCrop, player) == true,
    "sliced closing-check harvest starts")
local plainGrid = utility.gridSquare
local lookups, busiest = 0, 0
utility.gridSquare = function(...)
    lookups = lookups + 1
    return plainGrid(...)
end
for _ = 1, 300 do
    lookups = 0
    Field.update(one, player)
    busiest = math.max(busiest, lookups)
    if one.pending and one.pending.operation == "harvest" and one.active then
        finish(one, "harvest", 1)
    end
    if Field.status().phase == "complete" then break end
end
utility.gridSquare = plainGrid
check(Field.status().phase == "complete" and slicedCrop.plant.ripe == false
        and spoken[#spoken]:find("All the ripe crops", 1, true)
        and busiest <= 200,
    "the closing check is spread over updates: busiest update read "
        .. busiest .. " tiles, last line " .. tostring(spoken[#spoken]))

-- A full trunk can keep the only borrowed axe with the cutter. A second
-- worker waiting for that axe must not hold completion and its saved exact
-- return receipt open forever.
do
    Field.restore(nil)
    spoken = {}
    one.bag, two.bag, car.part.bag = inventory(), inventory(), inventory()
    one.x, one.y, two.x, two.y, player.x, player.y, car.x, car.y =
        600, 599, 601, 599, 600, 600, 610, 600
    one.follow, two.follow, one.pending, one.active, two.pending, two.active =
        true, true, nil, false, nil, false
    one.carryCapacity, two.carryCapacity = 10, 10
    for _ = 1, 6 do put(one.bag, item("Base.Pen")) end
    local sharedAxe = item("Base.Axe", true)
    put(car.part.bag, sharedAxe)
    car.part.bag.room = false
    for x = 600, 602 do standingTree(x, 600) end
    Field.observePlayerVehicle(car)
    check(Field.start("chop", square(600, 600), player) == true,
        "two-worker shared axe order starts with a full trunk")
    for _ = 1, 220 do
        for _, member in ipairs({ one, two }) do
            Field.update(member, player)
            if member.pending and member.pending.action == "chop_tree"
                and member.active then finish(member, "chop") end
        end
        if Field.status().phase == "complete" then break end
    end
    check(Field.status().phase == "complete" and Field.status().completed == 3
        and Field.status().pendingAxeReturns == 1,
        "waiting for a shared axe does not deadlock completed tree clearing")
    check(sharedAxe.container == one.bag and #car.part.bag.items == 0
        and #square(600, 600).world == 0
        and #square(601, 600).world == 1 and #square(602, 600).world == 1,
        "the exact axe stays carried and uncollected logs remain on the ground")
    check(Field.restore(Field.export()) == true,
        "completed shared axe return survives save and load")
    car.part.bag.room = true
    for _ = 1, 8 do
        if Field.status().pendingAxeReturns == 0 then break end
        Field.update(one, player)
    end
    check(Field.status().pendingAxeReturns == 0
        and sharedAxe.container == car.part.bag and #car.part.bag.items == 1,
        "the exact shared axe returns once after trunk space opens")
end

-- A worker whose tool broke can still own an unfinished tree. Hand that
-- claim back to a finished equipped cutter before releasing the waiter.
do
    Field.restore(nil)
    one.bag, two.bag, car.part.bag = inventory(), inventory(), inventory()
    one.x, one.y, two.x, two.y, player.x, player.y, car.x, car.y =
        620, 619, 621, 619, 620, 620, 630, 620
    one.pending, one.active, two.pending, two.active = nil, false, nil, false
    put(one.bag, item("Base.Axe", true))
    standingTree(620, 620)
    Field.observePlayerVehicle(car)
    check(Field.start("chop", square(620, 620), player) == true,
        "unfinished shared tree fixture starts")
    local state = Field.export().active
    state.workers.one.phase, state.workers.one.scan = "done", 17 * 17
    state.workers.two.phase, state.workers.two.target = "waiting_axe", "620:620:0"
    state.workers.two.x, state.workers.two.y = 620, 620
    Field.update(two, player)
    check(state.workers.one.phase == "seek" and state.workers.one.scan == 0
        and state.workers.two.phase == "done" and state.workers.two.target == nil,
        "an unfinished waiting claim restarts the equipped cutter's scan")
    for _ = 1, 150 do
        Field.update(one, player)
        if one.pending and one.pending.action == "chop_tree" and one.active then
            finish(one, "chop")
        end
        if Field.status().phase == "complete" then break end
    end
    check(Field.status().phase == "complete" and Field.status().completed == 1
        and square(620, 620).tree == nil,
        "the handed-back tree is cleared before the order completes")
end

-- A native rejection with room available is not a full trunk. Preserve exact
-- nested harvest cargo and allow the paused order to retry after save/load.
(function()
    local plainRoom = SC.WorkTransport.hasRoom
    -- The real cargo resolver is covered by the vehicle harness. Here the
    -- F-350 shape proves field work honors that resolver instead of selecting
    -- the hidden compatibility TruckBed part by name.
    Field.restore(nil)
    spoken = {}
    one.bag = inventory()
    one.x, one.y, player.x, player.y, car.x, car.y = 760, 759, 760, 760, 770, 760
    one.follow, two.follow, one.pending, one.active = true, false, nil, false
    one.carryCapacity = 10
    local originalPart, originalGetter, originalById = car.part, car.getTrunkPart, car.getPartById
    local placeholder = { id = "TruckBed", bag = inventory() }
    placeholder.bag.room, placeholder.bag.capacity = false, 0
    function placeholder:getItemContainer() return self.bag end
    function placeholder:getArea() return "TruckBed" end
    local realCargo = { id = "F3502Trunk", bag = inventory() }
    realCargo.bag.capacity, realCargo.bag.effectiveCapacity, realCargo.bag.weight = 155, 201, 84.7
    function realCargo:getItemContainer() return self.bag end
    function realCargo:getArea() return "Trunk" end
    car.part, car.cargoOverride, car.getTrunkPart = placeholder, realCargo, nil
    function car:getPartById(id) return id == "TruckBed" and placeholder or nil end
    local crop = cropAt(760, 760, true)
    Field.observePlayerVehicle(car)
    check(Field.start("harvest", crop, player) == true, "F-350 custom cargo-part harvest starts")
    SC.WorkTransport.hasRoom = function(destination, worker, exact)
        check(destination == realCargo.bag and worker == one,
            "field harvest checks the real155-unit F-350 trunk, never hidden zero-capacity TruckBed")
        return plainRoom(destination, worker, exact)
    end
    for _ = 1, 180 do
        Field.update(one, player)
        if one.pending and one.pending.operation == "harvest" and one.active then
            finish(one, "harvest", 3)
        end
        if Field.status().phase == "complete" then break end
    end
    check(Field.status().phase == "complete" and Field.status().loaded == 3
            and #realCargo.bag.items == 3 and #placeholder.bag.items == 0
            and #one.bag.items == 0 and Field.export().active.capacityNotice == nil,
        "a partly filled custom F-350 trunk receives the exact harvest without a false-full warning")
    car.part, car.cargoOverride, car.getTrunkPart, car.getPartById =
        originalPart, nil, originalGetter, originalById
    SC.WorkTransport.hasRoom = plainRoom
    local cases = {
        { name = "restricted item", reason = "destination_item_rejected" },
        { name = "unavailable capacity", reason = "capacity_unavailable" },
        { name = "unknown adapter result" },
        { name = "native adapter error", throws = true },
        { name = "missing adapter", missing = true },
    }
    for index, scenario in ipairs(cases) do
        Field.restore(nil)
        spoken = {}
        one.bag, car.part.bag = inventory(), inventory()
        one.x, one.y, player.x, player.y, car.x, car.y =
            800 + index * 40, 799, 800 + index * 40, 800, 810 + index * 40, 800
        one.follow, two.follow, one.pending, one.active = true, false, nil, false
        one.carryCapacity = 10
        local backpack, contents = item("Base.Duffelbag"), inventory()
        function backpack:getItemContainer() return contents end
        put(one.bag, backpack)
        one.harvestDestination = contents
        local crop = cropAt(player.x, player.y, true)
        crop.plant.hasSeed = true
        Field.observePlayerVehicle(car)
        check(Field.start("harvest", crop, player) == true,
            scenario.name .. " recovery order starts")
        local blocked = true
        if scenario.missing then SC.WorkTransport.hasRoom = nil
        else
            SC.WorkTransport.hasRoom = function(destination, worker, exact)
                check(destination == car.part.bag and worker == one and exact.container == contents,
                    "capacity checks use the assigned trunk, actual carrier and exact nested item")
                if blocked then
                    if scenario.throws then error("injected native capacity failure") end
                    return false, scenario.reason
                end
                return plainRoom(destination, worker, exact)
            end
        end
        for _ = 1, 180 do
            Field.update(one, player)
            if one.pending and one.pending.operation == "harvest" and one.active then
                finish(one, "harvest", 3)
            end
            if Field.status().phase == "paused" then break end
        end
        one.harvestDestination = nil
        local expected = scenario.reason or "capacity_unavailable"
        local saved = Field.export()
        local worker = saved.active.workers.one
        check(Field.status().phase == "paused" and Field.status().blocker == expected
                and Field.status().loaded == 0 and worker.skipDeposit ~= true
                and saved.active.capacityNotice == nil and #contents.items == 4
                and #car.part.bag.items == 0 and #crop.world == 0
                and not string.find(tostring(Field.status().note), "trunk is full", 1, true),
            scenario.name .. " pauses without claiming a full trunk or abandoning delivery")
        local exactCargo = {}
        for _, exact in ipairs(contents.items) do
            exactCargo[#exactCargo + 1] = exact
            check(exact.data.LF_FieldOrder == saved.active.id and Field.reserved(exact),
                "paused cargo keeps its exact order reservation")
        end
        check(Field.restore(saved) == true and Field.resume() == true,
            scenario.name .. " delivery remains resumable across save/load")
        blocked = false
        if scenario.missing then SC.WorkTransport.hasRoom = plainRoom end
        for _ = 1, 180 do
            Field.update(one, player)
            if Field.status().phase == "complete" then break end
        end
        check(Field.status().phase == "complete" and Field.status().loaded == 4
                and #contents.items == 0 and #one.bag.items == 1 and #car.part.bag.items == 4,
            scenario.name .. " resumes and unloads produce and seed without moving the worn bag")
        for _, exact in ipairs(exactCargo) do
            check(exact.container == car.part.bag and exact.data.LF_FieldOrder == nil
                    and not Field.reserved(exact),
                "each resumed item reaches the assigned trunk exactly once")
        end
        SC.WorkTransport.hasRoom = plainRoom
    end

    -- A failed check partway through an eight-item batch must not re-transfer
    -- already verified deposits when the same order resumes.
    Field.restore(nil)
    spoken = {}
    one.bag, car.part.bag = inventory(), inventory()
    one.x, one.y, player.x, player.y, car.x, car.y = 1100, 1099, 1100, 1100, 1110, 1100
    one.pending, one.active = nil, false
    local crop = cropAt(1100, 1100, true)
    Field.observePlayerVehicle(car)
    check(Field.start("harvest", crop, player) == true, "partial cargo batch order starts")
    local checksAtTrunk, reject = 0, true
    SC.WorkTransport.hasRoom = function(destination, worker, exact)
        checksAtTrunk = checksAtTrunk + 1
        if reject and checksAtTrunk == 3 then return false, "capacity_unavailable" end
        return plainRoom(destination, worker, exact)
    end
    for _ = 1, 180 do
        Field.update(one, player)
        if one.pending and one.pending.operation == "harvest" and one.active then
            finish(one, "harvest", 12)
        end
        if Field.status().phase == "paused" then break end
    end
    check(Field.status().phase == "paused" and Field.status().loaded == 2
            and #car.part.bag.items == 2 and #one.bag.items == 10,
        "only successful exact deposits count before a mid-batch check failure")
    reject = false
    check(Field.resume() == true, "a partial batch can resume")
    for _ = 1, 180 do
        Field.update(one, player)
        if Field.status().phase == "complete" then break end
    end
    local seen = {}
    for _, exact in ipairs(car.part.bag.items) do
        check(not seen[exact], "resuming a partial batch never duplicates an item")
        seen[exact] = true
    end
    check(Field.status().phase == "complete" and Field.status().loaded == 12
            and #car.part.bag.items == 12 and #one.bag.items == 0,
        "partial-batch recovery verifies all cargo once and finishes")
    SC.WorkTransport.hasRoom = plainRoom
end)()

Field.restore(nil)
local bad = Field.restore({ schema = 1, serial = -1 })
check(bad == false, "malformed save rejected")
print("FIELD_WORK_PASS checks=" .. checks)
