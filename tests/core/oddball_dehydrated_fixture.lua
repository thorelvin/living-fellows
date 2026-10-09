-- SPDX-License-Identifier: MIT
SurvivorCompanion = { GameplayUtil = {}, Registry = {}, NativeList = {},
    OddballRoomGuard = {}, Oddballs = {}, Actor = {} }
local SC = SurvivorCompanion
local U = SC.GameplayUtil
DehydratedFixture = { now = 1000, lines = {}, releases = 0,
    poses = {}, shelters = {}, paused = false }
local F = DehydratedFixture
CharacterStat = { THIRST = "thirst" }
Fluid = { TaintedWater = "tainted" }
function getGameTime()
    return { getMultiplier = function()
        return F.paused and 0 or 1
    end }
end

local room = {}
local door = { __class = "IsoDoor", open = false }
function door:IsOpen() return self.open end
F.door = door
local squares = {}
local function square(x, y, z, assignedRoom, objects)
    local value = { x = x, y = y, z = z, room = assignedRoom,
        objects = objects or {} }
    function value:getRoom() return self.room end
    function value:getObjects() return self.objects end
    squares[x .. ":" .. y .. ":" .. z] = value
    return value
end
F.roomSquare = square(10, 10, 0, room, { door })
F.spawnSquare = square(11, 10, 0, room)
F.outside = square(9, 10, 0, nil)
function U.gridSquare(x, y, z) return squares[x .. ":" .. y .. ":" .. z] end
function U.squareOf(value) return value and value.square end
function U.call(object, method, ...)
    local fn = object and object[method]
    if type(fn) ~= "function" then return nil, false end
    return fn(object, ...), true
end
function U.position(object) return object.x, object.y, object.z end
function U.distance(a, b)
    return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
end
function U.isValidActor(actor) return actor ~= nil end
function U.instanceOf(item, class) return item and item.__class == class end
function U.nowMs() return F.now end
function U.say(actor, text)
    F.lines[#F.lines + 1] = text
    return true
end
function U.inventory(actor) return actor and actor.inventory end
function U.itemType(item) return item and item.fullType end
function U.inventoryItemsDeep(inv)
    local result = {}
    local function walk(container)
        for _, item in ipairs(container.items) do
            result[#result + 1] = item
            if item.inner then walk(item.inner) end
        end
    end
    walk(inv)
    return result
end
local function inventory()
    local inv = { items = {} }
    function inv:add(item)
        self.items[#self.items + 1] = item
        item.container = self
        return item
    end
    function inv:remove(item)
        for index, value in ipairs(self.items) do
            if value == item then table.remove(self.items, index); return true end
        end
        return false
    end
    return inv
end
F.inventory = inventory
local function makeItem(kind)
    local item = { fullType = kind, __class = kind == "Base.WalkieTalkie2"
        and "Radio" or nil }
    function item:getContainer() return self.container end
    function item:isWaterSource() return self.fluid ~= nil end
    function item:getFluidContainer() return self.fluid end
    if kind == "Base.WaterBottle" then
        item.fluid = { amount = 1 }
        function item.fluid:adjustAmount(amount) self.amount = amount end
        function item.fluid:getAmount() return self.amount end
    end
    if kind == "Base.WalkieTalkie2" then
        local data = { battery = false, power = 0, channel = 0, on = false }
        function data:getIsTwoWay() return true end
        function data:getIsPortable() return true end
        function data:getHasBattery() return self.battery end
        function data:getPower() return self.power end
        function data:getTransmitRange() return 1200 end
        function data:getMicIsMuted() return self.muted == true end
        function data:setMicIsMuted(value) self.muted = value end
        function data:isNoTransmit() return false end
        function data:getBattery() self.battery = false end
        function data:addBattery() self.battery, self.power = true, 100 end
        function data:setChannel(channel) self.channel = channel end
        function data:getChannel() return self.channel end
        function data:setDeviceVolume(volume) self.volume = volume end
        function data:setIsTurnedOn(on) self.on = on end
        function data:getIsTurnedOn() return self.on end
        function item:getDeviceData() return data end
    end
    return item
end
F.makeItem = makeItem
function U.addItem(inv, kind) return inv:add(makeItem(kind)) end
function U.transferItemVerified(source, destination, item)
    if not source:remove(item) then return false end
    destination:add(item)
    return true
end
function SC.NativeList.get(items, index) return items[index + 1] end
function SC.OddballRoomGuard.release() F.releases = F.releases + 1 end
function SC.Oddballs.setZombieShelter(actor, enabled)
    actor.sheltered = enabled
    F.shelters[#F.shelters + 1] = enabled
    return true
end
function SC.Actor.setMovement(actor, mode, intent)
    F.poses[#F.poses + 1] = intent.action
    if intent.action == "sit_ground" then actor.sitting = true end
    if intent.action == "stand_ground" then actor.sitting = false end
    return true
end
F.nate = { x = 11, y = 10, z = 0, square = F.spawnSquare,
    inventory = inventory(), stats = { thirst = 0 } }
function F.nate:getStats() return self.stats end
function F.nate:setSecondaryHandItem(item) self.secondary = item end
function F.nate:getSecondaryHandItem() return self.secondary end
function F.nate:getEquipedRadio() return self.secondary end
function F.nate:isZombiesDontAttack() return self.sheltered == true end
function F.nate:isSitOnGround() return self.sitting == true end
function F.nate.stats:set(kind, value) self[kind] = value end
function F.nate.stats:remove(kind, value)
    self[kind] = math.max(0, self[kind] - value)
end
F.player = { x = 9, y = 10, z = 0, square = F.outside,
    inventory = inventory() }
F.records = { nate = { actor = F.nate } }
function SC.Registry.byId(id) return F.records[id] end
F.group = { id = "rescue-nate-group", standing = "Neutral",
    discovered = false, members = { { actorId = "nate" } },
    oddball = { id = "radio_rescue_nate_duvall", stage = "unmet",
        site = { spawn = { x = 11, y = 10, z = 0 },
            rescueDoor = { x = 10, y = 10, z = 0, objectIndex = 0 } } } }
function F.water(amount, kind)
    local item = makeItem("Base.WaterBottle")
    local fluid = { amount = amount, kind = kind or "Water", tainted = false }
    function fluid:getAmount() return self.amount end
    function fluid:getPrimaryFluid()
        return { getFluidTypeString = function() return self.kind end,
            kind = self.kind }
    end
    function fluid:contains() return self.tainted end
    function fluid:adjustAmount(amount) self.amount = amount end
    item.fluid = fluid
    return item
end
