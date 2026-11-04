-- SPDX-License-Identifier: MIT
local SC = SurvivorCompanion
local Booking, Cab, Fare = SC.TaxiBooking, SC.TaxiCab, SC.TaxiFares
local function check(ok, label)
    if not ok then error("taxi fare/recovery: " .. label) end
end
local function list(values)
    return { values = values,
        size = function(self) return #self.values end,
        get = function(self, index) return self.values[index + 1] end }
end
local function container(values)
    return { items = list(values or {}),
        getItems = function(self) return self.items end,
        contains = function(self, item)
            for _, value in ipairs(self.items.values) do
                if value == item then return true end
            end
            return false
        end }
end
local function item(id, fullType)
    local value = { id = id, fullType = fullType, data = {} }
    function value:getID() return self.id end
    function value:getFullType() return self.fullType end
    function value:getModData() return self.data end
    function value:isFavorite() return false end
    function value:isQuestItem() return false end
    return value
end
local glove, trunk = container(), container()
local parts = {
    { getId = function() return "GloveBox" end,
        getItemContainer = function() return glove end },
    { getId = function() return "TruckBed" end,
        getItemContainer = function() return trunk end },
}
local vehicle = { sqlId = 771, script = "Base.CarTaxi", data = {},
    seats = {}, blood = {} }
function vehicle:getSqlId() return self.sqlId end
function vehicle:getScriptName() return self.script end
function vehicle:getModData() return self.data end
function vehicle:getX() return 100 end
function vehicle:getY() return 200 end
function vehicle:getZ() return 0 end
function vehicle:getPartCount() return #parts end
function vehicle:getPartByIndex(index) return parts[index + 1] end
function vehicle:getMaxPassengers() return 4 end
function vehicle:getCharacter(seat) return self.seats[seat] end
function vehicle:setBloodIntensity(area, value) self.blood[area] = value end
function vehicle:getBloodIntensity(area) return self.blood[area] or 0 end
function vehicle:transmitBlood() end
local loaded = vehicle
SC.Vehicle = { loadedBySqlId = function(id)
    return loaded and loaded.sqlId == id and loaded or nil
end, isStationary = function() return true end }

local inventory = container()
local radioData = { on = true,
    getIsPortable = function() return true end,
    getIsTwoWay = function() return true end,
    getTransmitRange = function() return 100 end,
    getIsTurnedOn = function(self) return self.on end,
    getHasBattery = function() return true end,
    getPower = function() return 1 end,
    getMicIsMuted = function() return false end,
    isNoTransmit = function() return false end }
local radio = { radio = true,
    getContainer = function() return inventory end,
    getDeviceData = function() return radioData end }
inventory.items.values = { radio }
local player = { x = 100, y = 200, z = 0,
    getInventory = function() return inventory end }
function player:getVehicle() return self.vehicle end
function getSpecificPlayer(index) return index == 0 and player or nil end
SC.GameplayUtil = {
    call = function(object, method, ...)
        local callback = object and object[method]
        if type(callback) ~= "function" then return nil, false end
        return callback(object, ...), true
    end,
    instanceOf = function(value, kind) return kind == "Radio" and value.radio == true end,
    containerContainsIdentity = function(source, value)
        return source:contains(value)
    end,
    position = function(actor)
        if actor.getX then return actor:getX(), actor:getY(), actor:getZ() end
        return actor.x, actor.y, actor.z
    end,
}

SC.TaxiTestFixture = {
    check = check, item = item, glove = glove, trunk = trunk, vehicle = vehicle,
    player = player, radio = radio,
    setLoaded = function(value) loaded = value end,
}
