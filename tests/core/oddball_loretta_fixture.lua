-- SPDX-License-Identifier: MIT
-- Small native-car double for Loretta's sealed-seat contract.

local SC = SurvivorCompanion
CharacterStat = { THIRST = "thirst", HUNGER = "hunger" }
SC_LORETTA_CLOCK = { hour = 100, ms = 1000, exits = 0, boards = 0,
    deaths = 0, zombies = 0, recoveries = 0, haloNotes = 0,
    bridgeCalls = 0, cheatCalls = 0, bridgeHistory = {},
    lines = {}, queued = {}, cars = {}, squares = {} }
local C = SC_LORETTA_CLOCK

local function list(items)
    return { size = function() return #items end,
        get = function(_, index) return items[index + 1] end }
end
local function indexedOnlyList(items)
    local value = {}
    for index, item in ipairs(items) do value[index] = item end
    function value:size() return #items end
    function value:get() return nil end
    return value
end
local function setLikeList(items, exposeIterator)
    local value = {}
    function value:size() return #items end
    function value:get() error("Set does not expose indexed get") end
    if exposeIterator then
        function value:iterator()
            local index = 0
            return {
                hasNext = function() return index < #items end,
                next = function()
                    index = index + 1
                    return items[index]
                end,
            }
        end
    end
    return value
end
SC.NativeList = {
    size = function(values) return values and values:size() or 0 end,
    get = function(values, index)
        if not values then return nil end
        local okay, item = pcall(values.get, values, index)
        return okay and item or nil
    end,
    each = function(values, limit, callback)
        for index = 0, math.min(values and values:size() or 0, limit or 100) - 1 do
            callback(values:get(index), index)
        end
    end,
}

local function square(x, y, z)
    local key = tostring(x) .. ":" .. tostring(y) .. ":" .. tostring(z or 0)
    if C.squares[key] then return C.squares[key] end
    local value = { x = x, y = y, z = z or 0 }
    function value:getX() return self.x end
    function value:getY() return self.y end
    function value:getZ() return self.z end
    function value:getRoom() return nil end
    function value:isOutside()
        return not (C.indoorSquares and C.indoorSquares[key] == true)
    end
    function value:isCanSee() return false end
    function value:getChunk() return {} end
    function value:getVehicleContainer()
        for _, car in ipairs(C.cars) do
            if math.floor(car.x) == self.x and math.floor(car.y) == self.y
                and math.floor(car.z) == self.z then return car end
        end
        return nil
    end
    C.squares[key] = value
    return value
end

local function inventory()
    local value = { items = {} }
    function value:AddItem(kind)
        local item = type(kind) == "table" and kind
            or { kind = kind, fullType = kind }
        if type(item.getFullType) ~= "function" then
            function item:getFullType() return self.fullType end
        end
        if type(item.setName) ~= "function" then
            function item:setName(name) self.name = name end
        end
        if type(item.getContainer) ~= "function" then
            function item:getContainer() return self.container end
        end
        item.container = self
        self.items[#self.items + 1] = item
        return item
    end
    function value:getItems() return list(self.items) end
    function value:contains(item)
        for _, row in ipairs(self.items) do if row == item then return true end end
        return false
    end
    return value
end

function SC_LORETTA_CAR(sqlId, x, y)
    local car = { sqlId = sqlId or 8, x = x or 10, y = y or 10, z = 0,
        gas = 20, alarmed = false, alarmCount = 0, speed = 0,
        removed = false, occupants = {}, parts = {}, maxPassengers = 4 }
    local gasContainer = { amount = car.gas }
    function gasContainer:setAmount(amount)
        self.amount = amount
        car.gas = amount
    end
    function gasContainer:getAmount() return self.amount end
    local function door()
        local value = { locked = false, open = false, lockChanges = 0 }
        function value:setLocked(enabled)
            self.locked = enabled
            self.lockChanges = self.lockChanges + 1
        end
        function value:isLocked() return self.locked end
        function value:isOpen() return self.open end
        function value:setOpen(enabled) self.open = enabled end
        return value
    end
    local function window()
        local value = { destroyed = false, open = false }
        function value:isDestroyed() return self.destroyed end
        function value:isOpen() return self.open end
        function value:isHittable() return not self.destroyed end
        function value:getHealth() return self.destroyed and 0 or 100 end
        function value:hit()
            self.destroyed = true
            if car.alarmed then car.alarmCount = car.alarmCount + 1 end
        end
        return value
    end
    local function part(id, item)
        local value = { id = id, door = item and item.door,
            window = item and item.window,
            container = item and item.container,
            inventoryItem = item and item.inventoryItem }
        function value:getId() return self.id end
        function value:getDoor() return self.door end
        function value:getWindow() return self.window end
        function value:getItemContainer() return self.container end
        function value:getInventoryItem() return self.inventoryItem end
        function value:setContainerContentAmount(amount)
            if self.container then self.container:setAmount(amount) end
        end
        return value
    end
    car.parts = {
        part("GasTank", { container = gasContainer, inventoryItem = {} }),
        part("DoorFrontLeft", { door = door(), inventoryItem = {} }),
        part("DoorFrontRight", { door = door(), inventoryItem = {} }),
        part("DoorRearLeft", { door = door(), inventoryItem = {} }),
        part("DoorRearRight", { door = door(), inventoryItem = {} }),
        part("WindowFrontLeft", { window = window(), inventoryItem = {} }),
        part("WindowFrontRight", { window = window(), inventoryItem = {} }),
        part("WindowRearLeft", { window = window(), inventoryItem = {} }),
        part("WindowRearRight", { window = window(), inventoryItem = {} }),
    }
    function car:getSqlId() return self.sqlId end
    function car:getId() return self.sqlId + 1000 end
    function car:getScriptName() return "Base.CarNormal" end
    function car:getX() return self.x end
    function car:getY() return self.y end
    function car:getZ() return self.z end
    function car:getCurrentSpeedKmHour() return self.speed end
    function car:getMaxPassengers() return self.maxPassengers end
    function car:isSeatInstalled(seat) return seat >= 0 and seat < 4 end
    function car:isSeatOccupied(seat) return self.occupants[seat] ~= nil end
    function car:getCharacter(seat) return self.occupants[seat] end
    function car:getSeat(actor)
        for seat, passenger in pairs(self.occupants) do
            if passenger == actor then return seat end
        end
        return -1
    end
    function car:getPartById(id)
        for _, row in ipairs(self.parts) do if row.id == id then return row end end
    end
    function car:getParts() return list(self.parts) end
    function car:getPartCount() return #self.parts end
    function car:getPartByIndex(index) return self.parts[index + 1] end
    function car:getPassengerDoor(seat)
        return self:getPartById(seat == 2 and "DoorRearLeft"
            or seat == 3 and "DoorRearRight" or "DoorFrontRight")
    end
    function car:getPassengerWindow(seat)
        return self:getPartById(seat == 2 and "WindowRearLeft"
            or seat == 3 and "WindowRearRight" or "WindowFrontRight")
    end
    function car:getEnterSeatDistance() return 1 end
    function car:getSquare() return square(self.x, self.y, self.z) end
    function car:isRemovedFromWorld() return self.removed end
    function car:setAlarmed(enabled) self.alarmed = enabled end
    function car:isAlarmed() return self.alarmed end
    function car:getAlarmed() return self.alarmed end
    function car:createVehicleKey()
        self.keyCreates = (self.keyCreates or 0) + 1
        local key = { kind = "Base.CarKey", fullType = "Base.CarKey" }
        function key:getFullType() return self.fullType end
        return key
    end
    C.cars[#C.cars + 1] = car
    return car
end

function getGameTime()
    return { getWorldAgeHours = function() return C.hour end }
end
function getCell()
    return { getVehicles = function()
            if C.vehicleListMode == "indexed_only" then
                return indexedOnlyList(C.cars)
            elseif C.vehicleListMode == "set_iterator" then
                return setLikeList(C.cars, true)
            elseif C.vehicleListMode == "set_unreadable" then
                return setLikeList(C.cars, false)
            end
            return list(C.cars)
        end,
        getZombieList = function()
            return list(C.lastZombie and { C.lastZombie } or {})
        end }
end
function getPlayer() return SC_LORETTA_PLAYER end
function addZombiesInOutfit(x, y, z, count, outfit)
    C.zombies = C.zombies + count
    local zombie = { x = x, y = y, z = z, outfit = outfit, inv = inventory() }
    function zombie:getInventory() return self.inv end
    function zombie:getX() return self.x end
    function zombie:getY() return self.y end
    function zombie:getZ() return self.z end
    C.lastZombie = zombie
    return list({ zombie })
end

SC.GameplayUtil = {
    call = function(object, method, ...)
        if not object or type(object[method]) ~= "function" then return nil, false end
        local okay, value = pcall(object[method], object, ...)
        if not okay then return nil, false end
        return value, true
    end,
    nowMs = function() return C.ms end,
    config = function(key)
        local values = {
            oddballLorettaRescueHours = 72,
            oddballLorettaDarrenRadius = 20,
            oddballLorettaThirst = 0.8,
            oddballLorettaHunger = 0.6,
            oddballBackseatRemarkMs = 90000,
            oddballBackseatSpeedKmh = 80,
            oddballBackseatBrakeKmh = 30,
            profanityEnabled = C.profanityEnabled,
        }
        return values[key]
    end,
    position = function(value)
        if not value then return nil end
        return value.x or value:getX(), value.y or value:getY(),
            value.z or value:getZ()
    end,
    distance = function(a, b)
        if not a or not b then return math.huge end
        local ax, ay = a.x or a:getX(), a.y or a:getY()
        local bx, by = b.x or b:getX(), b.y or b:getY()
        return math.sqrt((ax - bx)^2 + (ay - by)^2)
    end,
    gridSquare = square,
    squareOf = function(value) return value and square(value.x, value.y, value.z) end,
    isSafeSpawnSquare = function(value)
        return value ~= nil and value ~= C.occupiedDoorSquare
    end,
    canSee = function(observer, target)
        if not observer or observer.visible ~= true or not target then return false end
        return SC.GameplayUtil.distance(observer, target) <= 4
    end,
    isValidActor = function(actor) return actor and actor.dead ~= true end,
    inventory = function(actor) return actor and actor.inv end,
    inventoryItemsDeep = function(inv) return inv and inv.items or {} end,
    itemType = function(item) return item and item.fullType end,
    modData = function(value)
        if not value then return nil end
        value.data = value.data or {}
        return value.data
    end,
    addItem = function(inv, kind) return inv and inv:AddItem(kind) end,
    transferItemVerified = function(source, destination, item)
        if not source or not destination or not item then return false end
        for index, row in ipairs(source.items or {}) do
            if row == item then
                table.remove(source.items, index)
                destination.items[#destination.items + 1] = item
                item.container = destination
                return true
            end
        end
        return false
    end,
    say = function(actor, line)
        actor.lastLine = line
        C.lines[#C.lines + 1] = line
        return true
    end,
}

function SC_LORETTA_ACTOR(x, y)
    local actor = { x = x or 10, y = y or 10, z = 0, inv = inventory(),
        immunity = false, stats = { thirst = 0, hunger = 0 } }
    function actor:getX() return self.x end
    function actor:getY() return self.y end
    function actor:getZ() return self.z end
    function actor:getCurrentSquare() return square(self.x, self.y, self.z) end
    function actor:getInventory() return self.inv end
    function actor:getStats() return self.stats end
    function actor:getVehicle() return self.vehicle end
    function actor:isDead() return self.dead == true end
    function actor:getBodyDamage()
        return { getHealth = function() return self.health or 100 end }
    end
    function actor:setZombiesDontAttack()
        C.cheatCalls = C.cheatCalls + 1
        error("non-local companion cannot call cheat-gated immunity setter")
    end
    function actor:isZombiesDontAttack() return self.immunity end
    function actor:getFullName() return self.name or "Loretta Biddle" end
    function actor:Say(line) self.lastLine = line C.lines[#C.lines + 1] = line end
    function actor:setHaloNote(line)
        C.haloNotes = C.haloNotes + 1
        self.lastHalo = line
    end
    function actor.stats:setThirst(value) self.thirst = value end
    function actor.stats:setHunger(value) self.hunger = value end
    function actor.stats:set(stat, value) self[stat] = value end
    function actor.stats:remove(stat, amount)
        self[stat] = math.max(0, (self[stat] or 0) - amount)
    end
    return actor
end

SC.Registry = { records = {}, byId = function(id) return SC.Registry.records[id] end,
    idOf = function(actor) return actor and actor.id end }
SC.Registry.living = function() return SC.Registry.livingActors or {} end
SC.Call = { method = function(object, name, ...)
    if not object or type(object[name]) ~= "function" then return false, nil end
    local okay, value = pcall(object[name], object, ...)
    return okay, value
end,
    static = function(object, name, ...)
        if not object or type(object[name]) ~= "function" then return false, nil end
        return pcall(object[name], ...)
    end }
SCBridge = { setStoryZombieIgnored = function(actor, enabled)
    C.bridgeCalls = C.bridgeCalls + 1
    C.bridgeHistory[#C.bridgeHistory + 1] = { actor = actor,
        enabled = enabled }
    actor.immunity = enabled
    return true
end }
SC.Config = { get = function(key)
    local values = { vehicleBoardRangeSquared = 2.56,
        vehicleBoardMaxSpeedKph = 0.5, vehicleManifestLimit = 8 }
    return values[key]
end }
SC.Diagnostics = { report = function() end }
SC.Commands = { peek = function(actor) return actor and actor.commands end }
SC.Factions = {
    member = function(group, key) return group.members and group.members[key] end,
    adjustStanding = function() return true end,
    groups = {},
    forceStanding = function(id, standing)
        local group = SC.Factions.groups[id]
        if not group then return false end
        group.standing = standing
        return true
    end,
    describeLocation = function() return "the old lot" end,
    markDiscovered = function(group) group.discovered = true return true end,
}
SC.Oddballs = {
    state = function(group) return group.oddball end,
    groupForActor = function(actor) return actor and actor.group end,
}
SC.Actor = { endLife = function(actor)
    C.deaths = C.deaths + 1 actor.dead = true return true
end,
    recover = function(actor, target)
        C.recoveries = C.recoveries + 1
        actor.x, actor.y, actor.z = target.x, target.y, target.z
        return true, "recovered"
    end,
    isCompanion = function(actor) return actor and actor.id ~= nil end }
SC.Vehicle = {
    isStationary = function(car) return car.speed == 0 end,
    isNativeSeated = function(actor)
        local car = actor and actor.vehicle
        return car ~= nil and car:getSeat(actor) >= 0, car,
            car and car:getSeat(actor) or nil
    end,
    board = function(actor, car, seat)
        C.boards = C.boards + 1
        car.occupants[seat] = actor
        actor.vehicle = car
        return true, "native_seat"
    end,
    exit = function(actor)
        C.exits = C.exits + 1
        local car = actor.vehicle
        if car then car.occupants[car:getSeat(actor)] = nil end
        actor.vehicle = nil
        return true, "native_exit"
    end,
}
ISTimedActionQueue = { add = function(action)
    C.queued[#C.queued + 1] = action
    return true
end }
ISSmashVehicleWindow = { new = function(_, player, part)
    return { character = player, part = part }
end }
function require() return true end

function SC_LORETTA_GROUP(car, actor)
    actor.id = "loretta-" .. tostring(car.sqlId)
    SC.Registry.records[actor.id] = { id = actor.id, actor = actor, recruited = false }
    local member = { actorId = actor.id }
    local group = { id = "loretta-group-" .. tostring(car.sqlId),
        members = { member, ["member-1"] = member },
        oddball = { id = "loretta_ten_and_two", stage = "unmet",
            carSqlId = car.sqlId, seat = 2,
            site = { spawn = { x = car.x, y = car.y + 1, z = 0 },
                vehicle = { sqlId = car.sqlId, seat = 2,
                    door = { x = car.x, y = car.y + 1, z = 0 } } } } }
    actor.group = group
    SC.Factions.groups[group.id] = group
    return group
end
