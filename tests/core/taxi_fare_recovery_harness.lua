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

local serviceRing = item(101, "Base.Ring_Left_RingFinger_Gold")
glove.items.values = { serviceRing }
check(Booking.request(player, radio) == true, "initial booking")
local booked = Booking.current()
local prepared, token = Cab.prepareSpawn(booked.generation)
check(prepared and token == "markus:1:1", "durable spawn token")
check(Cab.prepareSpawn(booked.generation) == false, "second spawn blocked")
check(select(2, Cab.recover()) == "cab_spawn_unresolved", "pending spawn recovery")
check(Cab.claimSpawn(vehicle, token) == true, "claim native taxi and baseline")
check(Cab.applyAppearance(vehicle) == true
        and vehicle:getBloodIntensity("Front") > 0.7,
    "new taxi receives native blood without damaging parts")
check(Cab.isOwned(vehicle) and Cab.matches(vehicle), "service ownership readback")
check(select(1, Cab.recover()) == true, "loaded cab recovery")
check(select(2, Fare.offer(player, vehicle, serviceRing)) == "fare_item_protected",
    "Markus's original ring cannot be paid back to him")

local customerSilver = item(202, "Base.Ring_Left_RingFinger_Silver")
glove.items.values[#glove.items.values + 1] = customerSilver
check(Fare.offer(player, vehicle, customerSilver) == true, "explicit loose offer")
local free = Fare.quote(250)
check(free.promotion and free.required == 0, "first ride free")
check(Fare.reserve(player, vehicle, 250) == true, "free reservation")
local freeReceipt = Fare.export()
check(Fare.reset() and Fare.restore(freeReceipt)
    and Fare.current().promotion == true
    and Fare.current().phase == "reserved",
    "free reservation survives reload")
check(Fare.cancel(vehicle) == true, "cancel preserves actual item")
check(Fare.quote(250).required == 0, "failed free trip did not consume offer")
check(Fare.reserve(player, vehicle, 250) == true, "reserve free ride again")
check(Fare.commit(vehicle) == true, "safe dropoff consumes promotion")
check(select(2, Fare.commit(vehicle)) == "already_committed",
    "second settlement has no extra credit")
check(Fare.quote(250).required == 3, "next ride charged")
check(select(2, Fare.retirementStatus(vehicle)) == "customer_property_in_cab",
    "unselected deposit blocks retirement")
glove.items.values = { serviceRing }
check(Fare.retirementStatus(vehicle) == true, "service stock can remain")

check(Booking.cancel(player, radio) == true, "close old booking")
check(Booking.request(player, radio) == true, "second booking")
check(Cab.beginVisit(vehicle, Booking.current().generation) == true,
    "second journey reuses same cab")
check(Cab.current().sqlId == 771 and Cab.current().visitGeneration == 2,
    "same SQL id, new visit generation")
local gold = item(303, "Base.Ring_Right_RingFinger_Gold")
local silver = item(304, "Base.Ring_Right_RingFinger_Silver")
glove.items.values[#glove.items.values + 1] = gold
trunk.items.values[#trunk.items.values + 1] = silver
check(Fare.offer(player, vehicle, gold) == true, "gold in glovebox")
check(Fare.offer(player, vehicle, silver) == true, "silver in trunk")
check(Fare.reserve(player, vehicle, 250) == true, "paid reservation")
local receipt = Fare.current()
check(receipt.paidValue == 3 and #receipt.items == 1
    and receipt.items[1].itemId == 303, "lowest sufficient set")
check(Fare.verify(vehicle) == true, "native custody verified")
glove.items.values = { serviceRing }
trunk.items.values[#trunk.items.values + 1] = gold
check(Fare.verify(vehicle) == true, "fare moved between cab containers")
check(Fare.commit(vehicle) == true, "paid item settled once")
check(select(2, Fare.offer(player, vehicle, gold)) == "fare_item_protected",
    "committed piece cannot pay again")

local saveBooking, saveCab, saveFare = Booking.export(), Cab.export(), Fare.export()
check(Booking.reset() and Cab.reset() and Fare.reset(), "world teardown")
check(Booking.restore(saveBooking) and Cab.restore(saveCab)
    and Fare.restore(saveFare), "reload all three ledgers")
check(Cab.recover() == true and Fare.current().phase == "committed",
    "recover same native cab and receipt")
loaded = nil
player.vehicle = vehicle
check(Cab.recover() == true,
    "cold passenger seat resolves cab before the cell vehicle list")
player.vehicle = nil
check(select(2, Cab.recover()) == "cab_unloaded_or_missing",
    "unloaded cab remains unresolved")
check(Cab.prepareSpawn(Booking.current().generation) == false,
    "missing loaded cab cannot authorize a clone")
loaded = vehicle
vehicle.data.LF_MarkusCab.token = "foreign"
check(select(2, Cab.recover()) == "cab_identity_conflict",
    "conflicting loaded cab blocks recovery")
vehicle.data.LF_MarkusCab.token = Cab.current().ownershipToken
check(Cab.recover() == true, "matching cab recovers again")
check(Cab.restore({ schema = 1, nextVisit = 3,
    record = { state = "claimed" } }) == false
    and Cab.current().sqlId == 771, "bad restore leaves live ledger intact")

trunk.items.values = { gold }
check(Booking.cancel(player, radio) and Booking.request(player, radio),
    "third booking after reload")
check(Cab.beginVisit(vehicle, Booking.current().generation) == true,
    "third visit waits until customer luggage is collected")
local interrupted = item(405, "Base.Ring_Left_RingFinger_Gold")
glove.items.values[#glove.items.values + 1] = interrupted
check(Fare.offer(player, vehicle, interrupted) == true
    and Fare.reserve(player, vehicle, 250) == true,
    "exact item reserved for third fare")
local partial = Fare.export()
partial.receipt.phase = "settlement_pending"
interrupted.data.LF_TaxiPaid = partial.receipt.id
check(Fare.reset() and Fare.restore(partial),
    "restore partial settlement")
check(select(2, Fare.cancel(vehicle)) == "fare_released"
    and interrupted.data.LF_TaxiPaid == nil
    and interrupted.data.LF_TaxiReceipt == nil,
    "cancellation clears only the interrupted payment")
check(Fare.offer(player, vehicle, interrupted) == true
    and Fare.reserve(player, vehicle, 250) == true,
    "released item can fund a new receipt")
local malformed = Fare.export()
malformed.receipt.paidValue = malformed.receipt.paidValue + 1
check(Fare.restore(malformed) == false
    and Fare.current().phase == "reserved",
    "malformed fare cannot replace live receipt")
glove.items.values = { serviceRing }
check(select(2, Fare.verify(vehicle)) == "fare_item_missing"
    and select(2, Fare.commit(vehicle)) == "fare_item_missing",
    "removed item cannot be charged")
check(select(2, Fare.cancel(vehicle)) == "refund_item_unresolved",
    "missing fare becomes recovery claim, not duplicate refund")
local pending = Fare.export()
check(Fare.reset() and Fare.restore(pending)
    and Fare.current().phase == "refund_due",
    "unresolved refund survives reload")
check(Fare.retireRemoved(771) == false,
    "unsettled receipt cannot be retired")

-- A completed visit removes its physical cab. The next call gets a new native
-- identity while the used free ride and any fare credit stay in this save.
check(Booking.restore(saveBooking) and Cab.restore(saveCab)
    and Fare.restore(saveFare), "restore settled cab for retirement")
check(Fare.retirementStatus(vehicle) == true,
    "settled cab contains no customer luggage")
local oldToken = Cab.current().ownershipToken
vehicle:setBloodIntensity("Front", 0.31)
local washedBlood = Cab.captureAppearance(vehicle)
check(Fare.retireRemoved(771) == true
    and Cab.retireRemoved(771, oldToken, washedBlood) == true,
    "remove exact settled cab ledger")
local savedAppearance = Cab.export()
check(Cab.reset() and Cab.restore(savedAppearance),
    "cab appearance survives a cold save reload")
check(Cab.current() == nil and Fare.current() == nil
    and Fare.quote(250).required == 3,
    "next cab keeps fare history without stale vehicle identity")
check(Booking.cancel(player, radio) and Booking.request(player, radio),
    "new booking after verified taxi departure")
glove.items.values, trunk.items.values = {}, {}
local replacement = setmetatable({ sqlId = 772, script = "Base.CarTaxi",
    data = {}, seats = {}, blood = {} }, { __index = vehicle })
loaded = replacement
local newReady, newToken = Cab.prepareSpawn(Booking.current().generation)
check(newReady and Cab.claimSpawn(replacement, newToken) == true
    and Cab.current().sqlId == 772 and Fare.hasBaseline(772),
    "new booking claims a new cab with its own native stock baseline")
check(Cab.applyAppearance(replacement) == true
        and math.abs(replacement:getBloodIntensity("Front") - 0.31) < 0.01,
    "a washed blood level carries into Markus's next physical cab")

print("taxi fare and cab recovery harness passed")
