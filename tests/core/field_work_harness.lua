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
    local value = { id = id, x = x, y = y, z = 0, bag = inventory(), active = false }
    function value:getInventory() return self.bag end
    function value:getVehicle() return nil end
    actors[#actors + 1] = value
    return value
end
local player = { x = 100, y = 100, z = 0 }
local one, two = actor("one", 100, 99), actor("two", 101, 99)
local car = { x = 101, y = 101, z = 0, id = 42, locked = false,
    part = { bag = inventory() } }
function car:getSqlId() return self.id end
function car:isTrunkLocked() return self.locked end
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
    isStationary = function() return true end }
SC.TaxiCab = { isOwned = function() return false end }
SC.WorkTransport = { hasRoom = function(bag) return bag.room ~= false end }
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
        plant.ripe = false
        for _ = 1, yieldCount or 1 do
            if props.vegetableName then put(value.bag, item(props.vegetableName)) end
            if props.produceExtra then put(value.bag, item(props.produceExtra)) end
        end
        if plant.hasSeed and props.seedName then
            put(value.bag, item(props.seedName))
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

check(Field.restore(nil) == true, "old save restores idle")
cropAt(100, 100, true)
cropAt(102, 100, true)
local unripe = cropAt(99, 100, false)
Field.observePlayerVehicle(car)
check(Field.start("harvest", square(100, 100), player) == true,
    "field order starts with recent car")
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
check(Field.start("harvest", square(100, 100), player) == true
    and Field.status().phase == "paused", "locked selected car pauses")
check(Field.resume() == false, "locked car cannot silently resume")
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
check(Field.status().completed == 5, "five-tree limit enforced")
check(square(105, 100).tree ~= nil, "sixth tree remains standing")
check(#one.bag.items >= 6, "logs carried without a car")
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
    "single eligible follower fells remaining tree: "
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
    if Field.status().phase == "paused" then break end
end
check(Field.status().phase == "paused"
    and Field.status().blocker == "car_trunk_full",
    "full trunk pauses the fixed car destination: "
        .. tostring(Field.status().phase) .. "/" .. tostring(Field.status().blocker)
        .. "/" .. tostring(Field.export().active.workers.one.phase)
        .. "/" .. tostring(Field.export().active.workers.one.scan))
check(#one.bag.items == 1 and one.bag.items[1].data.LF_FieldOrder ~= nil,
    "full trunk keeps the exact crop with its worker")
car.part.bag.room = true
check(Field.resume() == true, "car order can resume after space is made")
advance({ one }, 50)
check(Field.status().phase == "complete" and #one.bag.items == 0,
    "resumed delivery reaches the same car")
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
advance({ one }, 10)
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
Field.restore(nil)
local bad = Field.restore({ schema = 1, serial = -1 })
check(bad == false, "malformed save rejected")
print("FIELD_WORK_PASS checks=" .. checks)
