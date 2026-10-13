-- SPDX-License-Identifier: MIT
-- Fares reserve exact, loose items in the native cab. No item is copied,
-- removed from the player, or accepted merely because it appeared in a car.
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.TaxiFares = SC.TaxiFares or {}
local Fare = SC.TaxiFares

local OFFER, RECEIPT, PAID = "LF_TaxiOffer", "LF_TaxiReceipt", "LF_TaxiPaid"
local firstRideUsed, credit, nextReceipt = false, 0, 1
local offers, paidItems, receipt = {}, {}, nil
local serviceItems, baselineSqlId = {}, nil

-- Exact full types verified in the installed 42.21 clothing scripts. Mods can
-- register additional types explicitly; a display name or substring never pays.
local values = {
    ["Base.Necklace_Silver"] = 1, ["Base.Necklace_Gold"] = 3,
    ["Base.Necklace_GoldRuby"] = 6, ["Base.Necklace_GoldDiamond"] = 6,
    ["Base.Necklace_SilverDiamond"] = 6,
    ["Base.Earring_Stud_Silver"] = 1,
    ["Base.Earring_Stud_Gold"] = 3,
    ["Base.Earring_Stone_Ruby"] = 6,
    ["Base.Earring_Dangly_Diamond"] = 6,
}
for _, finger in ipairs({ "Right_MiddleFinger", "Left_MiddleFinger",
    "Right_RingFinger", "Left_RingFinger" }) do
    values["Base.Ring_" .. finger .. "_Silver"] = 1
    values["Base.Ring_" .. finger .. "_Gold"] = 3
    values["Base.Ring_" .. finger .. "_SilverDiamond"] = 6
    values["Base.Ring_" .. finger .. "_GoldRuby"] = 6
    values["Base.Ring_" .. finger .. "_GoldDiamond"] = 6
end

local function U() return SC.GameplayUtil end
local function call(object, method, ...)
    return object and select(1, U().call(object, method, ...)) or nil
end
local function integer(value)
    return type(value) == "number" and value == value and value >= 0
        and value <= 2147483647 and value == math.floor(value)
end
local function copyEntry(entry)
    return { itemId = entry.itemId, itemType = entry.itemType,
        partId = entry.partId, value = entry.value,
        bookingGeneration = entry.bookingGeneration }
end
local function copyReceipt()
    if not receipt then return nil end
    local entries = {}
    for _, entry in ipairs(receipt.items) do entries[#entries + 1] = copyEntry(entry) end
    return { id = receipt.id, bookingGeneration = receipt.bookingGeneration,
        visitGeneration = receipt.visitGeneration, vehicleSqlId = receipt.vehicleSqlId,
        phase = receipt.phase, baseFare = receipt.baseFare,
        required = receipt.required, creditUsed = receipt.creditUsed,
        paidValue = receipt.paidValue, overpay = receipt.overpay,
        promotion = receipt.promotion, items = entries }
end
local function bookingAndCab(vehicle)
    local booking = SC.TaxiBooking and SC.TaxiBooking.current()
    local cab = SC.TaxiCab and SC.TaxiCab.current()
    if not booking or not cab or cab.bookingGeneration ~= booking.generation
        or not SC.TaxiCab.matches(vehicle) then
        return nil, nil, "cab_booking_mismatch"
    end
    return booking, cab
end
local function primary(actor)
    return type(getSpecificPlayer) == "function"
        and actor ~= nil and getSpecificPlayer(0) == actor
end
local function customerAtCab(actor, vehicle)
    if call(actor, "getVehicle") == vehicle then return true end
    local ax, ay, az = U().position(actor)
    local vx, vy, vz = U().position(vehicle)
    if not ax or not vx or math.floor(az or 0) ~= math.floor(vz or 0) then
        return false
    end
    local dx, dy = ax - vx, ay - vy
    return dx * dx + dy * dy <= 9
end
local function itemId(item)
    local id = tonumber(call(item, "getID"))
    return integer(id) and id >= 1 and id or nil
end
local function protected(item, data)
    return call(item, "isFavorite") == true
        or call(item, "isQuestItem") == true
        or data.SC_PersonalOwnerId ~= nil
        or data.LF_TradeRecoveryId ~= nil
        or data.LF_TradeRecoveryState ~= nil
        or data.LF_TradeRecoveryBuildId ~= nil
        or data.LF_CarUnloadJob ~= nil
end

function Fare.registerValue(fullType, value)
    if type(fullType) ~= "string" or not fullType:match("^[%w_]+%.[%w_]+$")
        or fullType:sub(1, 5) == "Base."
        or not integer(value) or value < 1 or value > 100 then
        return false, "invalid_fare_type"
    end
    values[fullType] = value
    return true
end

function Fare.valueFor(item)
    return values[call(item, "getFullType")]
end

function Fare.hasBaseline(sqlId)
    return baselineSqlId ~= nil and baselineSqlId == tonumber(sqlId)
end

-- Capture Markus's original stores immediately after the newly spawned cab
-- is claimed, before the player can use its containers. Never re-baseline an
-- existing cab on reload: that would launder customer luggage into stock.
function Fare.captureBaseline(vehicle)
    local cab = SC.TaxiCab and SC.TaxiCab.current()
    if not cab or not SC.TaxiCab.matches(vehicle) then
        return false, "cab_identity_conflict"
    end
    if baselineSqlId ~= nil then
        return baselineSqlId == cab.sqlId,
            baselineSqlId == cab.sqlId and "baseline_present" or "baseline_conflict"
    end
    if receipt then return false, "fare_receipt_active" end
    for _ in pairs(offers) do return false, "fare_offer_already_exists" end
    local rows, reason = SC.TaxiCab.looseItems(vehicle)
    if not rows then return false, reason end
    local found = {}
    local count = 0
    for _, row in ipairs(rows) do
        count = count + 1
        if count > 512 then return false, "cab_stock_too_large" end
        if not integer(row.itemId) or row.itemId < 1
            or type(row.itemType) ~= "string" or row.itemType == ""
            or found[tostring(row.itemId)] then
            return false, "cab_stock_identity_unavailable"
        end
        found[tostring(row.itemId)] = row.itemType
    end
    serviceItems, baselineSqlId = found, cab.sqlId
    return true, "baseline_recorded"
end

function Fare.offer(actor, vehicle, item)
    if not primary(actor) then return false, "not_booked_customer" end
    if not customerAtCab(actor, vehicle) then return false, "customer_not_near_cab" end
    local booking, _, reason = bookingAndCab(vehicle)
    if not booking then return false, reason end
    if baselineSqlId ~= tonumber(call(vehicle, "getSqlId")) then
        return false, "fare_baseline_missing"
    end
    if receipt and receipt.phase ~= "committed" then
        return false, "fare_receipt_active"
    end
    local rows, rowsReason = SC.TaxiCab.looseItems(vehicle)
    if not rows then return false, rowsReason end
    local row
    for _, candidate in ipairs(rows) do
        if candidate.item == item then row = candidate; break end
    end
    if not row or not itemId(item) then return false, "fare_item_not_loose_in_cab" end
    local value = Fare.valueFor(item)
    if not value then return false, "fare_item_not_jewelry" end
    local data = call(item, "getModData")
    if type(data) ~= "table" or protected(item, data)
        or serviceItems[tostring(row.itemId)] ~= nil
        or paidItems[tostring(row.itemId)] ~= nil or data[PAID] ~= nil
        or data[RECEIPT] ~= nil then return false, "fare_item_protected" end
    local existing = offers[tostring(row.itemId)]
    if existing and existing.bookingGeneration == booking.generation then
        return true, "already_offered", copyEntry(existing)
    end
    local count = 0
    for _ in pairs(offers) do count = count + 1 end
    if not existing and count >= 128 then return false, "fare_offer_limit" end
    local marker = "markus:" .. tostring(booking.generation)
        .. ":" .. tostring(row.itemId)
    data[OFFER] = marker
    if data[OFFER] ~= marker then return false, "fare_marker_failed" end
    local entry = { itemId = row.itemId, itemType = row.itemType,
        partId = row.partId, value = value,
        bookingGeneration = booking.generation }
    offers[tostring(row.itemId)] = entry
    return true, "fare_offered", copyEntry(entry)
end

function Fare.quote(roadTiles)
    local distance = tonumber(roadTiles)
    if not distance or distance ~= distance or distance < 0
        or distance == math.huge then return nil, "fare_route_unavailable" end
    local base = distance <= 100 and 1 or distance <= 500 and 3 or 6
    if not firstRideUsed then
        return { baseFare = base, required = 0, creditUsed = 0,
            promotion = true }
    end
    local used = math.min(credit, base)
    return { baseFare = base, required = base - used,
        creditUsed = used, promotion = false }
end

local function looseById(vehicle)
    local rows, reason = SC.TaxiCab.looseItems(vehicle)
    if not rows then return nil, reason end
    local byId = {}
    for _, row in ipairs(rows) do
        if row.itemId and integer(row.itemId) and row.itemId >= 1 then
            if byId[tostring(row.itemId)] then
                return nil, "duplicate_fare_item_identity"
            end
            byId[tostring(row.itemId)] = row
        end
    end
    return byId
end

local function offeredRows(vehicle, bookingGeneration)
    local byId, reason = looseById(vehicle)
    if not byId then return nil, reason end
    local result = {}
    for id, entry in pairs(offers) do
        if entry.bookingGeneration == bookingGeneration then
            local row = byId[id]
            local data = row and call(row.item, "getModData") or nil
            if row and row.itemType == entry.itemType
                and type(data) == "table"
                and data[OFFER] == "markus:" .. tostring(bookingGeneration)
                    .. ":" .. id
                and not protected(row.item, data)
                and data[PAID] == nil and data[RECEIPT] == nil then
                local current = copyEntry(entry)
                current.partId = row.partId
                result[#result + 1] = current
            end
        end
    end
    table.sort(result, function(a, b) return a.itemId < b.itemId end)
    return result, byId
end

local function selectFare(entries, required)
    if required == 0 then return {}, 0 end
    local choices = { [0] = {} }
    local maximum = 0
    for _, entry in ipairs(entries) do
        for sum = maximum, 0, -1 do
            local prior = choices[sum]
            if prior then
                local candidate = {}
                for _, value in ipairs(prior) do candidate[#candidate + 1] = value end
                candidate[#candidate + 1] = entry
                local total = sum + entry.value
                if not choices[total] or #candidate < #choices[total] then
                    choices[total] = candidate
                end
            end
        end
        maximum = maximum + entry.value
    end
    for sum = required, maximum do
        if choices[sum] then return choices[sum], sum end
    end
    return nil, maximum
end

local function finishReservation(vehicle)
    if not receipt or receipt.phase ~= "reserving" then
        return false, "fare_not_reserving"
    end
    local byId, reason = looseById(vehicle)
    if not byId then return false, reason end
    -- Prove every selected object before writing any marker. A half-finished
    -- reservation can then be retried after save/load without selecting new
    -- jewelry or creating a second receipt.
    for _, entry in ipairs(receipt.items) do
        local row = byId[tostring(entry.itemId)]
        local data = row and call(row.item, "getModData") or nil
        if not row or row.itemType ~= entry.itemType
            or type(data) ~= "table" or data[OFFER] ~= "markus:"
                .. tostring(receipt.bookingGeneration) .. ":"
                .. tostring(entry.itemId)
            or data[RECEIPT] ~= nil and data[RECEIPT] ~= receipt.id
            or data[PAID] ~= nil then
            return false, "fare_reservation_pending"
        end
    end
    for _, entry in ipairs(receipt.items) do
        local data = call(byId[tostring(entry.itemId)].item, "getModData")
        data[RECEIPT] = receipt.id
        if data[RECEIPT] ~= receipt.id then
            return false, "fare_reservation_pending"
        end
    end
    receipt.phase = "reserved"
    return true, "fare_reserved", copyReceipt()
end

function Fare.reserve(actor, vehicle, roadTiles)
    if not primary(actor) then return false, "not_booked_customer" end
    if not customerAtCab(actor, vehicle) then return false, "customer_not_near_cab" end
    if not SC.Vehicle or type(SC.Vehicle.isStationary) ~= "function"
        or SC.Vehicle.isStationary(vehicle) ~= true then
        return false, "cab_not_parked"
    end
    local booking, cab, reason = bookingAndCab(vehicle)
    if not booking then return false, reason end
    if baselineSqlId ~= cab.sqlId then return false, "fare_baseline_missing" end
    if receipt and receipt.bookingGeneration == booking.generation then
        if receipt.phase == "reserving" then
            return finishReservation(vehicle)
        end
        if receipt.phase == "committed" then
            return false, "fare_already_committed", copyReceipt()
        end
        return receipt.phase == "reserved", "fare_receipt_active", copyReceipt()
    end
    if receipt and receipt.phase ~= "committed" then
        return false, "fare_receipt_active"
    end
    local quote, quoteReason = Fare.quote(roadTiles)
    if not quote then return false, quoteReason end
    local entries, byId = offeredRows(vehicle, booking.generation)
    if not entries then return false, byId end
    local selected, total = selectFare(entries, quote.required)
    if not selected then return false, "fare_waiting", {
        required = quote.required, offered = total } end
    local paidCount = 0
    for _ in pairs(paidItems) do paidCount = paidCount + 1 end
    if paidCount + #selected > 512 then return false, "fare_ledger_full" end
    if not integer(nextReceipt) or nextReceipt >= 2147483647 then
        return false, "fare_receipts_exhausted"
    end
    local id = "markus-fare:" .. tostring(nextReceipt)
    local candidate = { id = id, bookingGeneration = booking.generation,
        visitGeneration = cab.visitGeneration, vehicleSqlId = cab.sqlId,
        phase = "reserving", baseFare = quote.baseFare,
        required = quote.required, creditUsed = quote.creditUsed,
        paidValue = total, overpay = total - quote.required,
        promotion = quote.promotion, items = selected }
    receipt = candidate
    nextReceipt = nextReceipt + 1
    return finishReservation(vehicle)
end

function Fare.verify(vehicle)
    if not receipt then return false, "no_fare_receipt" end
    if receipt.phase == "committed" then return true, "fare_committed" end
    local cab = SC.TaxiCab and SC.TaxiCab.current()
    if not cab or not SC.TaxiCab.matches(vehicle)
        or cab.sqlId ~= receipt.vehicleSqlId
        or cab.visitGeneration ~= receipt.visitGeneration then
        return false, "cab_identity_conflict"
    end
    local byId, reason = looseById(vehicle)
    if not byId then return false, reason end
    for _, entry in ipairs(receipt.items) do
        local row = byId[tostring(entry.itemId)]
        local data = row and call(row.item, "getModData") or nil
        if not row or row.itemType ~= entry.itemType
            or type(data) ~= "table" or data[RECEIPT] ~= receipt.id then
            return false, "fare_item_missing"
        end
    end
    return true, "fare_verified"
end

-- Call only after a verified safe dropoff. A failed pickup never consumes the
-- promotion. Repeated settlement cannot add credit or mark payment twice.
function Fare.commit(vehicle)
    if not receipt then return false, "no_fare_receipt" end
    if receipt.phase == "committed" then return true, "already_committed" end
    if receipt.phase ~= "reserved" and receipt.phase ~= "settlement_pending" then
        return false, "fare_not_reserved"
    end
    local verified, reason = Fare.verify(vehicle)
    if not verified then return false, reason end
    receipt.phase = "settlement_pending"
    local byId = looseById(vehicle)
    for _, entry in ipairs(receipt.items) do
        local row = byId[tostring(entry.itemId)]
        local data = call(row.item, "getModData")
        data[PAID] = receipt.id
        if data[PAID] ~= receipt.id then return false, "fare_settlement_pending" end
    end
    for _, entry in ipairs(receipt.items) do
        paidItems[tostring(entry.itemId)] = entry.itemType
    end
    for id, entry in pairs(offers) do
        if entry.bookingGeneration == receipt.bookingGeneration then
            offers[id] = nil
        end
    end
    credit = credit - receipt.creditUsed + receipt.overpay
    if receipt.promotion then firstRideUsed = true end
    receipt.phase = "committed"
    return true, "fare_committed", copyReceipt()
end

-- No synthetic refund: the exact objects stay in the native cab. If the cab
-- cannot be inspected yet, leave a durable refund-due claim for recovery.
function Fare.cancel(vehicle)
    if not receipt then return false, "no_fare_receipt" end
    if receipt.phase == "committed" then return false, "fare_already_committed" end
    receipt.phase = "refund_due"
    if not vehicle or not SC.TaxiCab.matches(vehicle) then
        return true, "refund_waiting_for_cab", copyReceipt()
    end
    local byId = looseById(vehicle)
    if not byId then return true, "refund_waiting_for_cab", copyReceipt() end
    for _, entry in ipairs(receipt.items) do
        local row = byId[tostring(entry.itemId)]
        local data = row and call(row.item, "getModData") or nil
        if type(data) ~= "table" or data[RECEIPT] ~= receipt.id then
            return true, "refund_item_unresolved", copyReceipt()
        end
    end
    for _, entry in ipairs(receipt.items) do
        local data = call(byId[tostring(entry.itemId)].item, "getModData")
        data[RECEIPT] = nil
        -- Settlement may have marked some native items before interruption.
        -- Only unwind this receipt's marks; older paid fares stay protected.
        if data[PAID] == receipt.id then
            data[PAID] = nil
            paidItems[tostring(entry.itemId)] = nil
        end
    end
    for id, entry in pairs(offers) do
        if entry.bookingGeneration == receipt.bookingGeneration then
            offers[id] = nil
        end
    end
    receipt = nil
    return true, "fare_released"
end

function Fare.retirementStatus(vehicle)
    local rows, reason = SC.TaxiCab.looseItems(vehicle)
    if not rows then return false, reason end
    if receipt and receipt.phase ~= "committed" then
        return false, "fare_unsettled"
    end
    for _, row in ipairs(rows) do
        local id = row.itemId and tostring(row.itemId) or nil
        local data = call(row.item, "getModData")
        if not id or serviceItems[id] ~= row.itemType
            and (paidItems[id] ~= row.itemType
                or type(data) ~= "table" or data[PAID] == nil) then
            return false, "customer_property_in_cab"
        end
    end
    return true, "cab_property_clear"
end

-- The service calls this after the matching native cab is positively removed.
-- The fare history on its physical items is gone with it; credit and the
-- first-ride entitlement remain with the save for the next cab.
function Fare.retireRemoved(sqlId)
    if baselineSqlId ~= sqlId or not receipt
        or receipt.vehicleSqlId ~= sqlId or receipt.phase ~= "committed" then
        return false, "fare_retirement_unresolved"
    end
    offers, paidItems, serviceItems, receipt = {}, {}, {}, nil
    baselineSqlId = nil
    return true, "fare_cab_retired"
end

function Fare.current()
    return copyReceipt()
end

function Fare.export()
    local savedOffers, savedPaid, savedService = {}, {}, {}
    for id, entry in pairs(offers) do savedOffers[id] = copyEntry(entry) end
    for id, kind in pairs(paidItems) do savedPaid[id] = kind end
    for id, kind in pairs(serviceItems) do savedService[id] = kind end
    return { schema = 1, firstRideUsed = firstRideUsed,
        credit = credit, nextReceipt = nextReceipt,
        offers = savedOffers, paidItems = savedPaid,
        serviceItems = savedService, baselineSqlId = baselineSqlId,
        receipt = copyReceipt() }
end

local function validEntry(entry)
    return type(entry) == "table" and integer(entry.itemId)
        and entry.itemId >= 1 and type(entry.itemType) == "string"
        and entry.itemType ~= "" and type(entry.partId) == "string"
        and entry.partId ~= "" and integer(entry.value) and entry.value <= 100
        and integer(entry.bookingGeneration) and entry.bookingGeneration >= 1
end

function Fare.restore(saved)
    if saved == nil then
        firstRideUsed, credit, nextReceipt = false, 0, 1
        offers, paidItems, serviceItems, receipt = {}, {}, {}, nil
        baselineSqlId = nil
        return true
    end
    if type(saved) ~= "table" or saved.schema ~= 1
        or type(saved.firstRideUsed) ~= "boolean"
        or not integer(saved.credit) or not integer(saved.nextReceipt)
        or saved.nextReceipt < 1 or type(saved.offers) ~= "table"
        or type(saved.paidItems) ~= "table"
        or type(saved.serviceItems) ~= "table"
        or saved.baselineSqlId ~= nil
            and (not integer(saved.baselineSqlId) or saved.baselineSqlId < 1) then
        return false, "invalid_taxi_fares_header"
    end
    local newOffers, newPaid, newService = {}, {}, {}
    local count = 0
    for id, entry in pairs(saved.offers) do
        count = count + 1
        if count > 128 or type(id) ~= "string" or not validEntry(entry)
            or id ~= tostring(entry.itemId) then
            return false, "invalid_taxi_fares_offer"
        end
        newOffers[id] = copyEntry(entry)
    end
    count = 0
    for id, kind in pairs(saved.paidItems) do
        count = count + 1
        if count > 512 or type(id) ~= "string" or not integer(tonumber(id))
            or type(kind) ~= "string" or kind == "" then
            return false, "invalid_taxi_fares_paid_item"
        end
        newPaid[id] = kind
    end
    count = 0
    for id, kind in pairs(saved.serviceItems) do
        count = count + 1
        if count > 512 or type(id) ~= "string" or not integer(tonumber(id))
            or type(kind) ~= "string" or kind == "" then
            return false, "invalid_taxi_fares_service_item"
        end
        newService[id] = kind
    end
    local candidate = saved.receipt
    if candidate ~= nil then
        local receiptNumber = type(candidate) == "table"
            and type(candidate.id) == "string"
            and tonumber(candidate.id:match("^markus%-fare:(%d+)$")) or nil
        if type(candidate) ~= "table" or type(candidate.id) ~= "string"
            or not integer(receiptNumber)
            or receiptNumber < 1 or receiptNumber >= saved.nextReceipt
            or not integer(candidate.bookingGeneration)
            or not integer(candidate.visitGeneration)
            or not integer(candidate.vehicleSqlId)
            or not integer(candidate.baseFare) or not integer(candidate.required)
            or not integer(candidate.creditUsed) or not integer(candidate.paidValue)
            or not integer(candidate.overpay)
            or type(candidate.promotion) ~= "boolean"
            or type(candidate.items) ~= "table" or #candidate.items > 64
            or candidate.vehicleSqlId ~= saved.baselineSqlId
            or candidate.required > candidate.baseFare
            or candidate.creditUsed > candidate.baseFare
            or not candidate.promotion
                and candidate.creditUsed + candidate.required ~= candidate.baseFare
            or candidate.overpay ~= candidate.paidValue - candidate.required
            or candidate.promotion and (candidate.required ~= 0
                or candidate.creditUsed ~= 0)
            or (candidate.phase ~= "reserving"
                and candidate.phase ~= "reserved"
                and candidate.phase ~= "settlement_pending"
                and candidate.phase ~= "refund_due"
                and candidate.phase ~= "committed") then
            return false, "invalid_taxi_fares_receipt"
        end
        local items, seen, total = {}, {}, 0
        for _, entry in ipairs(candidate.items) do
            if not validEntry(entry) or seen[entry.itemId]
                or entry.bookingGeneration ~= candidate.bookingGeneration then
                return false, "invalid_taxi_fares_receipt_item"
            end
            seen[entry.itemId] = true
            items[#items + 1] = copyEntry(entry)
            total = total + entry.value
        end
        if total ~= candidate.paidValue then
            return false, "invalid_taxi_fares_receipt_total"
        end
        candidate = { id = candidate.id,
            bookingGeneration = candidate.bookingGeneration,
            visitGeneration = candidate.visitGeneration,
            vehicleSqlId = candidate.vehicleSqlId, phase = candidate.phase,
            baseFare = candidate.baseFare, required = candidate.required,
            creditUsed = candidate.creditUsed, paidValue = candidate.paidValue,
            overpay = candidate.overpay, promotion = candidate.promotion,
            items = items }
    end
    firstRideUsed, credit, nextReceipt = saved.firstRideUsed,
        saved.credit, saved.nextReceipt
    offers, paidItems, serviceItems, receipt = newOffers, newPaid,
        newService, candidate
    baselineSqlId = saved.baselineSqlId
    return true
end

function Fare.reset()
    firstRideUsed, credit, nextReceipt = false, 0, 1
    offers, paidItems, serviceItems, receipt = {}, {}, {}, nil
    baselineSqlId = nil
    return true
end

return Fare
