-- SPDX-License-Identifier: MIT
SurvivorCompanion = {}
local SC = SurvivorCompanion
SC_TEST = { ms = 0, calls = {}, door = nil, player = nil }
local T = SC_TEST
BodyPartType = { LowerLeg_L = "left_lower_leg" }

local function inventory()
    local result = { items = {} }
    function result:AddItem(kind)
        local item = { fullType = kind, container = self }
        function item:getContainer() return self.container end
        if kind == "Base.WalkieTalkie2" then
            item.className = "Radio"
            local data = { battery = false, power = 0, channel = 0,
                on = false, presets = {} }
            function data:getIsPortable() return true end
            function data:getIsTwoWay() return true end
            function data:getHasBattery() return self.battery end
            function data:getPower() return self.power end
            function data:getBattery() self.battery = false end
            function data:addBattery(battery)
                self.battery, self.power = true, 1
                battery.container:Remove(battery)
            end
            function data:getChannel() return self.channel end
            function data:setChannel(channel) self.channel = channel end
            function data:getIsTurnedOn() return self.on end
            function data:setIsTurnedOn(on) self.on = on end
            function data:setDeviceVolume(volume) self.volume = volume end
            function data:getTransmitRange() return 550 end
            function data:getDevicePresets()
                local presets = self.presets
                return { getPresets = function() return {
                        size = function() return #presets end,
                    } end,
                    getMaxPresets = function() return 4 end,
                    addPreset = function(_, name, channel)
                        presets[#presets + 1] = { name = name, channel = channel }
                    end }
            end
            function item:getDeviceData() return data end
        end
        self.items[#self.items + 1] = item
        return item
    end
    function result:Remove(item)
        for index, candidate in ipairs(self.items) do
            if candidate == item then
                table.remove(self.items, index)
                item.container = nil
                return
            end
        end
    end
    return result
end

local part = { fracture = 0, scratch = false, bandage = false, factor = 0 }
function part:setFractureTime(value) self.fracture = value end
function part:getFractureTime() return self.fracture end
function part:setScratched(value) self.scratch = value end
function part:getSplintFactor() return self.factor end
function part:bandaged() return self.bandage end

local actor = { x = 10, y = 10, z = 0, inventory = inventory() }
function actor:getInventory() return self.inventory end
function actor:getBodyDamage() return {
        getBodyPart = function(_, name)
            return name == "left_lower_leg" and part or nil
        end }
end
function actor:setSecondaryHandItem(item) self.secondary = item end
function actor:getSecondaryHandItem() return self.secondary end
function actor:isSitOnGround() return self.seated == true end

local player = { x = 13, y = 10, z = 0, inventory = inventory() }
function player:getInventory() return self.inventory end
T.actor, T.player, T.part = actor, player, part

local door = { className = "IsoDoor", open = false, locked = false }
function door:IsOpen() return self.open end
function door:isLocked() return self.locked end
function door:setLocked(value) self.locked = value end
T.door = door

local U = {}
SC.GameplayUtil = U
function U.call(object, method, ...)
    if not object or type(object[method]) ~= "function" then return nil, false end
    return object[method](object, ...), true
end
function U.nowMs() return T.ms end
function U.inventory(value) return value and value.inventory end
function U.inventoryItemsDeep(container)
    return container and container.items or {}
end
function U.itemType(item) return item and item.fullType end
function U.addItem(container, kind) return container:AddItem(kind) end
function U.isValidActor(value) return value ~= nil end
function U.instanceOf(value, className)
    return value and value.className == className
end
function U.distance(a, b)
    return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
end
function U.gridSquare(x, y)
    if x == 11 and y == 10 then
        return { getObjects = function() return { door } end }
    end
    return nil
end
function U.say(value, line) value.lastLine = line end
SC.NativeList = { get = function(list, index) return list[index + 1] end }
SC.Registry = { byId = function(id)
    return id == "eli" and { actor = actor } or nil
end }
SC.Oddballs = {
    setZombieShelter = function(value, wanted)
        value.sheltered = wanted
        return true
    end,
}
SC.OddballRoomGuard = { release = function(id)
    T.calls.guardRelease = (T.calls.guardRelease or 0) + 1
end }
SC.Actor = { setMovement = function(value, mode, intent)
    value.lastAction = intent.action
    if intent.action == "sit_ground" then value.seated = true end
    if intent.action == "stand_ground" then value.seated = false end
    return true
end }
SC.MedicalUI = { open = function(patient, doctor)
    T.calls.panel = (T.calls.panel or 0) + 1
    return true, "health_opened"
end }
SC.Factions = { forceStanding = function(id, standing)
    T.calls.standing = standing
    return true
end }
SC.FactionRecruitment = { ask = function(id, doctor)
    T.calls.recruited = true
    return true
end }

T.group = { id = "garage-1", members = { { actorId = "eli" } },
    oddball = { id = "garage_rescue_eli_rourke", stage = "trapped",
        site = { spawn = { x = 10, y = 10, z = 0 },
            rescueDoor = { x = 11, y = 10, z = 0, objectIndex = 0 } } } }
