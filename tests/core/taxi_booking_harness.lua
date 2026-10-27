-- SPDX-License-Identifier: MIT
local SC = SurvivorCompanion
local Booking = SC.TaxiBooking

local function check(condition, label)
    if not condition then error("taxi booking: " .. label) end
end

SC.GameplayUtil = {
    call = function(object, method, ...)
        local callback = object and object[method]
        if type(callback) ~= "function" then return nil, false end
        return callback(object, ...), true
    end,
    instanceOf = function(item, kind)
        return kind == "Radio" and item and item.radio == true
    end,
    containerContainsIdentity = function(container, item)
        for _, value in ipairs(container.items or {}) do
            if value == item then return true end
        end
        return false
    end,
    position = function(actor) return actor.x, actor.y, actor.z end,
}

local function container(holder)
    return { items = {}, getContainingItem = function() return holder end,
        contains = function(self, item)
            for _, value in ipairs(self.items) do
                if value == item then return true end
            end
            return false
        end }
end
local root = container(nil)
local actor = { x = 100.4, y = 200.8, z = 1,
    getInventory = function() return root end }
local data = { on = true, battery = true, power = 1, twoWay = true, television = false,
    range = 100, muted = false, noTransmit = false,
    getIsPortable = function() return true end,
    getIsTelevision = function(self) return self.television end,
    getIsTwoWay = function(self) return self.twoWay end,
    getTransmitRange = function(self) return self.range end,
    getIsTurnedOn = function(self) return self.on end,
    getHasBattery = function(self) return self.battery end,
    getPower = function(self) return self.power end,
    getMicIsMuted = function(self) return self.muted end,
    isNoTransmit = function(self) return self.noTransmit end }
local radio = { radio = true,
    getContainer = function(self) return self.container end,
    getDeviceData = function() return data end }
local bag = { getContainer = function(self) return self.container end }
local bagInside = container(bag)
bag.container = root
radio.container = bagInside
root.items = { bag }
bagInside.items = { radio }

check(Booking.checkRadio(actor, radio) == true, "owned radio in bag")
check(Booking.request(actor, radio) == true, "call from upper floor")
local first = Booking.current()
check(first and first.generation == 1 and first.requestedAt.z == 1
    and first.requestedAt.x == 100 and first.requestedAt.y == 200,
    "saved initial caller position")
data.television = true
check(select(2, Booking.checkRadio(actor, radio)) == "not_a_radio",
    "TV flag overrides Radio inheritance and even two-way-looking capabilities")
check(Booking.request(actor, radio) == false and Booking.updatePickup(actor, radio) == false
    and Booking.cancel(actor, radio) == false and Booking.current().generation == first.generation,
    "stale callbacks cannot use a television or change the existing booking")
data.television = false
local accepted, reason = Booking.request(actor, radio)
check(accepted and reason == "already_booked"
    and Booking.current().generation == 1, "duplicate call is idempotent")

actor.x, actor.y, actor.z = 119.2, 223.9, 0
check(Booking.updatePickup(actor, radio) == true, "update pickup")
local saved = Booking.export()
check(saved.active.requestedAt.x == 119 and saved.active.requestedAt.y == 223
    and saved.active.requestedAt.z == 0, "updated point stored")
saved.active.requestedAt.x = 999
check(Booking.current().requestedAt.x == 119, "export has no live alias")
saved = Booking.export()
check(Booking.reset() == true and Booking.current() == nil, "reset")
check(Booking.restore(saved) == true, "restore")
check(Booking.current().requestedAt.x == 119, "reload retained update")
saved.active.requestedAt.x = 999
check(Booking.current().requestedAt.x == 119, "restore has no caller alias")
check(Booking.restore({ schema = 1, nextGeneration = 2,
    active = { generation = 2, phase = "awaiting_pickup",
        requestedAt = { x = 1, y = 2, z = 0 } } }) == false
    and Booking.current().requestedAt.x == 119,
    "bad restore preserves current booking")

data.on = false
check(select(2, Booking.cancel(actor, radio)) == "radio_off"
    and Booking.current() ~= nil, "off handset cannot cancel")
data.on = true
data.power = 0
check(select(2, Booking.status(actor, radio)) == "radio_flat",
    "flat battery rejected")
data.power = 1
data.twoWay = false
check(select(2, Booking.updatePickup(actor, radio)) == "radio_receive_only",
    "receiver-only radio rejected")
data.twoWay = true
data.muted = true
check(select(2, Booking.status(actor, radio)) == "radio_muted",
    "muted radio rejected")
data.muted = false
bagInside.items = {}
check(select(2, Booking.cancel(actor, radio)) == "radio_not_owned",
    "moved exact handset rejected")
bagInside.items = { radio }
local second = { radio = true, container = nil,
    getContainer = function(self) return self.container end,
    getDeviceData = function() return data end }
check(select(2, Booking.status(actor, second)) == "radio_not_owned",
    "other radio cannot stand in for selected item")
check(Booking.cancel(actor, radio) == true and Booking.current() == nil,
    "cancel persisted booking")
check(Booking.request(actor, radio) == true
    and Booking.current().generation == 2, "next booking has new generation")
check(Booking.advance(2, "pickup_en_route") == true
    and select(2, Booking.cancel(actor, radio)) == "pickup_locked",
    "physical dispatch locks handset cancellation")
check(Booking.advance(2, "at_pickup") == true
    and Booking.advance(2, "in_transit") == true,
    "pickup and ride transitions")
local riding = Booking.export()
check(Booking.restore(riding) == true
    and Booking.current().phase == "in_transit",
    "booked ride survives reload")
check(Booking.advance(2, "at_destination") == true
    and Booking.complete(2) == true and Booking.current() == nil,
    "completed ride closes exact generation")
check(Booking.restore(nil) == true and Booking.current() == nil,
    "older save without taxi field starts empty")

print("taxi booking harness passed")
