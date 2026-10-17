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
function car.part:getArea() return nil end
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
function utility.itemHasTag(value, tag) return tag == "CHOP_TREE" and value.axe == true end
function utility.inventory(value) return value.bag end
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
local function cropAt(x, y, ripe)
    local tile = square(x, y)
    tile.plant = { ripe = ripe }
    function tile.plant:canHarvest() return self.ripe end
    return tile
end
local function finish(value, kind)
    if kind == "harvest" then
        value.pending.plant.ripe = false
        put(value.bag, item("Base.Cabbage"))
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
advance({ one, two }, 5)
check(Field.status().completed >= 1, "harvest has world proof")
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
for _ = 1, 35 do
    Field.update(one, player)
    if one.pending and one.pending.operation == "harvest" then
        finish(one, "harvest")
        break
    end
end
car.part.bag.room = false
for _ = 1, 90 do
    Field.update(one, player)
    if Field.status().phase == "paused" then break end
end
check(Field.status().phase == "paused"
    and Field.status().blocker == "car_trunk_full",
    "full trunk pauses the fixed car destination")
check(#one.bag.items == 1 and one.bag.items[1].data.LF_FieldOrder ~= nil,
    "full trunk keeps the exact crop with its worker")
car.part.bag.room = true
check(Field.resume() == true, "car order can resume after space is made")
advance({ one }, 50)
check(Field.status().phase == "complete" and #one.bag.items == 0,
    "resumed delivery reaches the same car")
Field.restore(nil)
one.follow = true
check(Field.start("harvest", square(100, 100), player) == true,
    "new order starts for leader leash")
player.x = 120
Field.leaderPulse(player)
check(Field.status().phase == "stopped"
    and Field.status().blocker == "leader_left_work_area",
    "leaving the field stops work and regroups")
player.x = 100
local bad = Field.restore({ schema = 1, serial = -1 })
check(bad == false, "malformed save rejected")
print("FIELD_WORK_PASS checks=" .. checks)
