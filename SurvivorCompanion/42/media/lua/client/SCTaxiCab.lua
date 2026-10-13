-- SPDX-License-Identifier: MIT
-- The game's native vehicle save is the authority for the cab and its cargo.
-- This ledger only binds its stable SQL identity to Markus's service. An
-- unloaded or uncertain cab must be recovered, never cloned from this record.
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.TaxiCab = SC.TaxiCab or {}
local Cab = SC.TaxiCab

local MARKER = "LF_MarkusCab"
local record, nextVisit = nil, 1
local DEFAULT_BLOOD = { Front = 0.78, Rear = 0.28,
    Left = 0.46, Right = 0.54 }
local BLOOD_AREAS = { "Front", "Rear", "Left", "Right" }
local bloodAppearance = nil

local function U() return SC.GameplayUtil end
local function call(object, method, ...)
    return object and select(1, U().call(object, method, ...)) or nil
end
local function integer(value)
    return type(value) == "number" and value == value and value >= 0
        and value <= 2147483647 and value == math.floor(value)
end
local function marker(vehicle)
    local data = call(vehicle, "getModData")
    return type(data) == "table" and data[MARKER] or nil, data
end
local function copy()
    if not record then return nil end
    return { visitGeneration = record.visitGeneration,
        bookingGeneration = record.bookingGeneration,
        originVisitGeneration = record.originVisitGeneration,
        originBookingGeneration = record.originBookingGeneration,
        ownershipToken = record.ownershipToken,
        state = record.state, sqlId = record.sqlId,
        script = record.script }
end

function Cab.current() return copy() end

-- Called before native spawning. Once this succeeds, even a failed callback
-- cannot start another car until the first creation is positively resolved.
function Cab.prepareSpawn(bookingGeneration)
    local booking = SC.TaxiBooking and SC.TaxiBooking.current()
    if not booking or booking.generation ~= bookingGeneration then
        return false, "booking_changed"
    end
    if record then return false, "cab_visit_unresolved" end
    if not integer(nextVisit) or nextVisit < 1 or nextVisit >= 2147483647 then
        return false, "visit_generation_exhausted"
    end
    local token = "markus:" .. tostring(bookingGeneration) .. ":" .. tostring(nextVisit)
    record = { visitGeneration = nextVisit,
        bookingGeneration = bookingGeneration, ownershipToken = token,
        originVisitGeneration = nextVisit,
        originBookingGeneration = bookingGeneration,
        state = "spawn_pending", script = "Base.CarTaxi" }
    nextVisit = nextVisit + 1
    return true, token, copy()
end

-- Only the native spawn callback holding this visit's token may claim a cab.
-- The SQL id and marker are read back before the ledger starts trusting it.
function Cab.claimSpawn(vehicle, token)
    if not record or token ~= record.ownershipToken
        or record.state ~= "spawn_pending" and record.state ~= "claimed" then
        return false, "stale_spawn"
    end
    if record.state == "claimed" then
        if not Cab.matches(vehicle) then return false, "cab_identity_conflict" end
        -- A reload may have happened after marking the car but before the
        -- initial stock snapshot. Retrying the snapshot now could classify a
        -- customer's later deposit as Markus's property; leave it unresolved.
        if SC.TaxiFares and type(SC.TaxiFares.hasBaseline) == "function"
            and SC.TaxiFares.hasBaseline(record.sqlId) ~= true then
            return false, "cab_stock_unresolved"
        end
        return true, "cab_already_claimed", copy()
    end
    local sqlId = tonumber(call(vehicle, "getSqlId"))
    if not integer(sqlId) or sqlId < 1
        or call(vehicle, "getScriptName") ~= "Base.CarTaxi" then
        return false, "cab_identity_unavailable"
    end
    local existing, data = marker(vehicle)
    if type(data) ~= "table" or existing ~= nil
        and (type(existing) ~= "table"
            or existing.token ~= record.ownershipToken) then
        return false, "cab_owner_conflict"
    end
    data[MARKER] = { service = "markus", token = record.ownershipToken }
    local stamped = marker(vehicle)
    if type(stamped) ~= "table" or stamped.token ~= record.ownershipToken
        or tonumber(call(vehicle, "getSqlId")) ~= sqlId then
        return false, "cab_marker_not_verified"
    end
    record.sqlId, record.state = sqlId, "claimed"
    if SC.TaxiFares and type(SC.TaxiFares.captureBaseline) == "function" then
        local captured, reason = SC.TaxiFares.captureBaseline(vehicle)
        if not captured then return false, reason or "cab_stock_unresolved", copy() end
    end
    return true, "cab_claimed", copy()
end

function Cab.isOwned(vehicle)
    if not vehicle then return false end
    local value = marker(vehicle)
    if type(value) == "table" and value.service == "markus" then return true end
    local sqlId = tonumber(call(vehicle, "getSqlId"))
    return record ~= nil and record.sqlId ~= nil and sqlId == record.sqlId
end

function Cab.matches(vehicle)
    if not record or record.state ~= "claimed" or not vehicle then return false end
    if tonumber(call(vehicle, "getSqlId")) ~= record.sqlId
        or call(vehicle, "getScriptName") ~= record.script then return false end
    local value = marker(vehicle)
    return type(value) == "table" and value.service == "markus"
        and value.token == record.ownershipToken
end

local function copyBlood(values)
    if type(values) ~= "table" then return nil end
    local copy = {}
    for _, area in ipairs(BLOOD_AREAS) do
        local intensity = tonumber(values[area])
        if not intensity or intensity ~= intensity or intensity < 0
            or intensity > 1 then return nil end
        copy[area] = intensity
    end
    return copy
end

-- Native blood is cosmetic; no mechanical part condition is reduced to make
-- the taxi look used. Read the actual cab before retirement so washing and
-- fresh splashes survive the next service visit.
function Cab.applyAppearance(vehicle)
    if not Cab.matches(vehicle) then return false, "cab_identity_conflict" end
    local levels = bloodAppearance or DEFAULT_BLOOD
    for _, area in ipairs(BLOOD_AREAS) do
        local called = select(2, U().call(vehicle,
            "setBloodIntensity", area, levels[area]))
        local observed = tonumber(call(vehicle, "getBloodIntensity", area))
        if not called or not observed
            or math.abs(observed - levels[area]) > 0.02 then
            return false, "cab_blood_unavailable"
        end
    end
    call(vehicle, "transmitBlood")
    return true, "cab_blood_applied"
end

function Cab.captureAppearance(vehicle)
    if not Cab.matches(vehicle) then return nil, "cab_identity_conflict" end
    local values = {}
    for _, area in ipairs(BLOOD_AREAS) do
        values[area] = tonumber(call(vehicle, "getBloodIntensity", area))
    end
    local captured = copyBlood(values)
    return captured, captured and "cab_blood_captured" or "cab_blood_unavailable"
end

function Cab.recover()
    if not record then return false, "no_cab_visit" end
    if record.state == "spawn_pending" then
        return false, "cab_spawn_unresolved", copy()
    end
    if not SC.Vehicle or type(SC.Vehicle.loadedBySqlId) ~= "function" then
        return false, "cab_lookup_unavailable", copy()
    end
    local vehicle = SC.Vehicle.loadedBySqlId(record.sqlId)
    -- On a cold load the native passenger's vehicle can be ready before it
    -- appears in the cell vehicle collection. That exact native seat is a
    -- safe second lookup source; matches() still verifies SQL id and marker.
    if not vehicle and type(getSpecificPlayer) == "function" then
        local passenger = getSpecificPlayer(0)
        local seated = call(passenger, "getVehicle")
        if seated and tonumber(call(seated, "getSqlId")) == record.sqlId then
            vehicle = seated
        end
    end
    if not vehicle then return false, "cab_unloaded_or_missing", copy() end
    if not Cab.matches(vehicle) then return false, "cab_identity_conflict", copy() end
    if SC.TaxiFares and type(SC.TaxiFares.hasBaseline) == "function"
        and SC.TaxiFares.hasBaseline(record.sqlId) ~= true then
        return false, "cab_stock_unresolved", copy()
    end
    return true, vehicle, copy()
end

-- A later booking reuses the same physical cab and its supplies/damage. The
-- ownership token stays stable; only the journey generation advances.
function Cab.beginVisit(vehicle, bookingGeneration)
    local booking = SC.TaxiBooking and SC.TaxiBooking.current()
    if not booking or booking.generation ~= bookingGeneration then
        return false, "booking_changed"
    end
    if not Cab.matches(vehicle) then return false, "cab_identity_conflict" end
    if record.bookingGeneration == bookingGeneration then
        return true, "visit_already_bound", copy()
    end
    if not integer(nextVisit) or nextVisit >= 2147483647 then
        return false, "visit_generation_exhausted"
    end
    local seats = tonumber(call(vehicle, "getMaxPassengers"))
    if not integer(seats) or seats > 16 then return false, "cab_seats_unavailable" end
    for seat = 0, seats - 1 do
        if call(vehicle, "getCharacter", seat) ~= nil then
            return false, "cab_still_occupied"
        end
    end
    if SC.Vehicle and type(SC.Vehicle.isStationary) == "function"
        and SC.Vehicle.isStationary(vehicle) ~= true then
        return false, "cab_not_parked"
    end
    if not SC.TaxiFares or type(SC.TaxiFares.retirementStatus) ~= "function" then
        return false, "cab_property_unavailable"
    end
    local clear, reason = SC.TaxiFares.retirementStatus(vehicle)
    if not clear then return false, reason end
    record.visitGeneration = nextVisit
    record.bookingGeneration = bookingGeneration
    nextVisit = nextVisit + 1
    return true, "visit_bound", copy()
end

-- Forget only a cab whose native vehicle has already been removed. The
-- caller verifies every seat, its contents, and the world's removal result.
function Cab.retireRemoved(sqlId, token, blood)
    if not record or record.state ~= "claimed"
        or record.sqlId ~= sqlId or record.ownershipToken ~= token then
        return false, "cab_identity_conflict"
    end
    if blood ~= nil then
        local checked = copyBlood(blood)
        if not checked then return false, "cab_blood_invalid" end
        bloodAppearance = checked
    end
    record = nil
    return true, "cab_retired"
end

-- Enumerate direct items only. A bag is one piece of luggage; its contents
-- are never silently offered as fare. Fail closed on overlarge inventories.
function Cab.looseItems(vehicle)
    if not Cab.matches(vehicle) then return nil, "cab_identity_conflict" end
    -- Build 42 exposes part access through BaseVehicle in Lua. The Java-only
    -- getParts() collection is not callable from a client script.
    local count = tonumber(call(vehicle, "getPartCount"))
    if not integer(count) or count > 160 then
        return nil, "cab_parts_unavailable"
    end
    local rows, seenContainers, seenParts = {}, {}, {}
    for index = 0, count - 1 do
        local part = call(vehicle, "getPartByIndex", index)
        if not part then return nil, "cab_part_unavailable" end
        local partId = call(part, "getId")
        local container = call(part, "getItemContainer")
        if container and not seenContainers[container] then
            if type(partId) ~= "string" or partId == "" then
                return nil, "cab_part_identity_unavailable"
            end
            if seenParts[partId] then return nil, "cab_part_identity_conflict" end
            seenParts[partId] = true
            seenContainers[container] = true
            local items = call(container, "getItems")
            local size = tonumber(call(items, "size"))
            if not integer(size) or size > 4096 then
                return nil, "cab_container_unavailable"
            end
            for itemIndex = 0, size - 1 do
                local item = call(items, "get", itemIndex)
                if not item then return nil, "cab_item_unavailable" end
                rows[#rows + 1] = { partId = partId, container = container,
                    item = item, itemId = tonumber(call(item, "getID")),
                    itemType = call(item, "getFullType") }
                if #rows > 4096 then return nil, "cab_inventory_too_large" end
            end
        end
    end
    return rows
end

function Cab.export()
    return { schema = 1, nextVisit = nextVisit, record = copy(),
        bloodAppearance = copyBlood(bloodAppearance) }
end

function Cab.restore(saved)
    if saved == nil then record, nextVisit, bloodAppearance = nil, 1, nil; return true end
    if type(saved) ~= "table" or saved.schema ~= 1
        or not integer(saved.nextVisit) or saved.nextVisit < 1 then
        return false, "invalid_taxi_cab"
    end
    local candidate = saved.record
    if candidate ~= nil then
        local bookingGeneration = type(candidate) == "table"
            and candidate.bookingGeneration or nil
        local visitGeneration = type(candidate) == "table"
            and candidate.visitGeneration or nil
        local originBooking = type(candidate) == "table"
            and candidate.originBookingGeneration or nil
        local originVisit = type(candidate) == "table"
            and candidate.originVisitGeneration or nil
        if type(candidate) ~= "table" or not integer(bookingGeneration)
            or bookingGeneration < 1 or not integer(visitGeneration)
            or visitGeneration < 1 or visitGeneration >= saved.nextVisit
            or not integer(originBooking) or originBooking < 1
            or not integer(originVisit) or originVisit < 1
            or originVisit > visitGeneration
            or candidate.ownershipToken ~= "markus:"
                .. tostring(originBooking) .. ":" .. tostring(originVisit)
            or candidate.script ~= "Base.CarTaxi"
            or candidate.state ~= "spawn_pending" and candidate.state ~= "claimed"
            or candidate.state == "claimed" and (not integer(candidate.sqlId)
                or candidate.sqlId < 1)
            or candidate.state == "spawn_pending" and candidate.sqlId ~= nil then
            return false, "invalid_taxi_cab"
        end
        candidate = { visitGeneration = visitGeneration,
            bookingGeneration = bookingGeneration,
            originVisitGeneration = originVisit,
            originBookingGeneration = originBooking,
            ownershipToken = candidate.ownershipToken,
            state = candidate.state, sqlId = candidate.sqlId,
            script = candidate.script }
    end
    local blood = saved.bloodAppearance
    if blood ~= nil then
        blood = copyBlood(blood)
        if blood == nil then return false, "invalid_taxi_cab" end
    end
    record, nextVisit, bloodAppearance = candidate, saved.nextVisit, blood
    return true
end

function Cab.reset()
    record, nextVisit, bloodAppearance = nil, 1, nil
    return true
end

return Cab
