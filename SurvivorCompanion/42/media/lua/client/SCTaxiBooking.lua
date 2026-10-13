-- SPDX-License-Identifier: MIT
-- Markus's radio booking ledger. The physical service owns transitions; a
-- handset cannot invent arrival or consume a fare on its own.
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.TaxiBooking = SC.TaxiBooking or {}
local Booking = SC.TaxiBooking

Booking.dispatchReady = true

local active, nextGeneration = nil, 1

local function U() return SC.GameplayUtil end
local function call(object, method, ...)
    return object and select(1, U().call(object, method, ...)) or nil
end
local function finite(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

-- The chosen handset must still be this player's exact item when a delayed
-- menu callback executes. A different working radio does not authorize it.
local function owned(actor, item)
    local root = call(actor, "getInventory")
    local current = call(item, "getContainer")
    if not root or not current then return false end
    local seen = {}
    for _ = 1, 12 do
        if seen[current] or U().containerContainsIdentity(current, item) ~= true then
            return false
        end
        if current == root then return true end
        seen[current] = true
        local holder = call(current, "getContainingItem")
        if not holder then return false end
        item = holder
        current = call(holder, "getContainer")
        if not current then return false end
    end
    return false
end

function Booking.checkRadio(actor, item)
    if not actor or not item or not U() or not U().instanceOf(item, "Radio") then
        return false, "not_a_radio"
    end
    if not owned(actor, item) then return false, "radio_not_owned" end
    local data = call(item, "getDeviceData")
    if not data or call(data, "getIsPortable") ~= true then
        return false, "radio_not_portable"
    end
    if call(data, "getIsTwoWay") ~= true
        or (tonumber(call(data, "getTransmitRange")) or 0) <= 0 then
        return false, "radio_receive_only"
    end
    if call(data, "getIsTurnedOn") ~= true then
        return false, "radio_off"
    end
    if call(data, "getHasBattery") ~= true
        or (tonumber(call(data, "getPower")) or 0) <= 0 then
        return false, "radio_flat"
    end
    if call(data, "getMicIsMuted") == true or call(data, "isNoTransmit") == true then
        return false, "radio_muted"
    end
    return true, "radio_ready"
end

local function callerPoint(actor)
    local x, y, z = U().position(actor)
    if not finite(x) or not finite(y) or not finite(z) then return nil end
    return { x = math.floor(x), y = math.floor(y), z = math.floor(z) }
end

local function snapshot()
    if not active then return nil end
    local point = active.requestedAt
    return { generation = active.generation, phase = active.phase,
        requestedAt = { x = point.x, y = point.y, z = point.z } }
end

function Booking.current()
    return snapshot()
end

function Booking.request(actor, radio)
    local valid, reason = Booking.checkRadio(actor, radio)
    if not valid then return false, reason end
    if active then return true, "already_booked", snapshot() end
    local point = callerPoint(actor)
    if not point then return false, "caller_position_unavailable" end
    local generation = nextGeneration
    active = { generation = generation, phase = "awaiting_pickup",
        requestedAt = point }
    nextGeneration = generation + 1
    return true, "booking_received", snapshot()
end

function Booking.status(actor, radio)
    local valid, reason = Booking.checkRadio(actor, radio)
    if not valid then return false, reason end
    if not active then return false, "no_booking" end
    return true, active.phase, snapshot()
end

function Booking.updatePickup(actor, radio)
    local valid, reason = Booking.checkRadio(actor, radio)
    if not valid then return false, reason end
    if not active then return false, "no_booking" end
    if active.phase ~= "awaiting_pickup" then return false, "pickup_locked" end
    local point = callerPoint(actor)
    if not point then return false, "caller_position_unavailable" end
    active.requestedAt = point
    return true, "pickup_updated", snapshot()
end

function Booking.cancel(actor, radio)
    local valid, reason = Booking.checkRadio(actor, radio)
    if not valid then return false, reason end
    if not active then return false, "no_booking" end
    if active.phase ~= "awaiting_pickup" then return false, "pickup_locked" end
    active = nil
    return true, "booking_cancelled"
end

local servicePhases = {
    awaiting_pickup = { pickup_en_route = true, at_pickup = true },
    pickup_en_route = { at_pickup = true },
    at_pickup = { in_transit = true },
    in_transit = { at_destination = true },
    at_destination = {},
}

function Booking.advance(generation, phase)
    if not active or active.generation ~= generation then
        return false, "booking_changed"
    end
    if active.phase == phase then return true, "phase_unchanged" end
    if not (servicePhases[active.phase] or {})[phase] then
        return false, "invalid_booking_transition"
    end
    active.phase = phase
    return true, phase, snapshot()
end

function Booking.abort(generation)
    if not active or active.generation ~= generation then
        return false, "booking_changed"
    end
    active = nil
    return true, "booking_cancelled"
end

function Booking.complete(generation)
    if not active or active.generation ~= generation
        or active.phase ~= "at_destination" then
        return false, "booking_not_complete"
    end
    active = nil
    return true, "booking_completed"
end

function Booking.export()
    return { schema = 1, nextGeneration = nextGeneration, active = snapshot() }
end

function Booking.restore(saved)
    if saved == nil then active, nextGeneration = nil, 1; return true end
    if type(saved) ~= "table" or saved.schema ~= 1
        or not finite(saved.nextGeneration) or saved.nextGeneration < 1
        or saved.nextGeneration ~= math.floor(saved.nextGeneration) then
        return false, "invalid_taxi_booking"
    end
    local candidate = saved.active
    if candidate ~= nil then
        local point = type(candidate) == "table" and candidate.requestedAt or nil
        if type(candidate) ~= "table" or not servicePhases[candidate.phase]
            or not finite(candidate.generation)
            or candidate.generation < 1
            or candidate.generation ~= math.floor(candidate.generation)
            or candidate.generation >= saved.nextGeneration
            or type(point) ~= "table" or not finite(point.x)
            or not finite(point.y) or not finite(point.z)
            or point.x ~= math.floor(point.x) or point.y ~= math.floor(point.y)
            or point.z ~= math.floor(point.z) then
            return false, "invalid_taxi_booking"
        end
        candidate = { generation = candidate.generation, phase = candidate.phase,
            requestedAt = { x = point.x, y = point.y, z = point.z } }
    end
    active, nextGeneration = candidate, saved.nextGeneration
    return true
end

function Booking.reset()
    active, nextGeneration = nil, 1
    return true
end

return Booking
