-- SPDX-License-Identifier: MIT
-- Exact expedition receipts are delivered by the carrier, through the same
-- approached/animated/verified storage transaction used by base workers.
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.ExpeditionIntegration = SC.ExpeditionIntegration or {}
local Integration = SC.ExpeditionIntegration
local states = setmetatable({}, { __mode = "k" })
local locationCache = setmetatable({}, { __mode = "k" })
local retryClocks = setmetatable({}, { __mode = "k" })
local settlementClocks = setmetatable({}, { __mode = "k" })
local ESSENTIALS = { "food", "water", "medicine", "ammunition" }
local WOOD_LIMIT, WOOD_RETRY_MS = 256, 180000
local woodToolsPending

local function U() return SC.GameplayUtil end
local function call(object, method, ...)
    local value, okay = U().call(object, method, ...)
    if okay then return value end
    return nil
end
local function validId(value, limit)
    return type(value) == "string" and #value > 0 and #value <= (limit or 160)
end
local function safeReason(reason)
    if reason == nil then return nil end
    return string.sub(tostring(reason), 1, 96)
end
local function woodRecord(record)
    return type(record) == "table" and record.version == 2 and record.kind == "wood"
end
local function remainingRetry(row)
    if row.retryRemainingMs == nil then return nil end
    local current = U().nowMs()
    local clock = retryClocks[row]
    if clock then
        row.retryRemainingMs = math.max(0, row.retryRemainingMs
            - math.max(0, current - clock))
    end
    retryClocks[row] = current
    return row.retryRemainingMs
end

-- Several unfinished trips may share one carrier. Keep their runtime routes
-- and receipt retries separate, with a bound above the saved delivery limit.
local function stateFor(record, actor, create)
    local bucket = states[actor]
    if not bucket then
        if not create then return nil end
        bucket = { byId = {}, order = {} }
        states[actor] = bucket
    end
    local state = bucket.byId[record.tripId]
    if not state and create then
        if #bucket.order >= 8 then
            bucket.byId[table.remove(bucket.order, 1)] = nil
        end
        state = { tripId = record.tripId, retryByReceipt = {} }
        bucket.byId[record.tripId] = state
        bucket.order[#bucket.order + 1] = record.tripId
    end
    return state
end

local function deferReceipt(state, row, delay)
    if row.retryRemainingMs ~= nil then
        row.retryRemainingMs = WOOD_RETRY_MS
        retryClocks[row] = U().nowMs()
    else state.retryByReceipt[row.id] = U().nowMs() + delay end
end
local function copyRow(row)
    local destination = row.destination
    return { id = row.id, itemType = row.itemType,
        finderId = row.finderId, finderName = row.finderName,
        carrierId = row.carrierId, carrierName = row.carrierName,
        carrierKind = row.carrierKind, returned = row.returned == true,
        stored = row.stored == true, released = row.released == true, storageId = row.storageId,
        reason = row.reason, retryRemainingMs = remainingRetry(row),
        destination = type(destination) == "table" and {
            kind = destination.kind, id = destination.id, zoneId = destination.zoneId,
            x = destination.x, y = destination.y, z = destination.z } or nil }
end

function Integration.valid(value)
    local wood = woodRecord(value)
    if type(value) ~= "table" or (value.version ~= 1 and not wood)
        or not validId(value.tripId, 128)
        or (value.baseId ~= nil and not validId(value.baseId, 128))
        or (value.carId ~= nil and (type(value.carId) ~= "number"
            or value.carId < 0 or value.carId > 2147483647
            or value.carId ~= math.floor(value.carId)))
        or type(value.restock) ~= "boolean"
        or type(value.requested) ~= "number" or value.requested < 1
        or value.requested > (wood and WOOD_LIMIT or 8) or value.requested ~= math.floor(value.requested)
        or (wood and value.requestedMode ~= "count" and value.requestedMode ~= "full")
        or (wood and (type(value.retryRemainingMs) ~= "number"
            or value.retryRemainingMs < 0 or value.retryRemainingMs > WOOD_RETRY_MS
            or value.retryRemainingMs ~= math.floor(value.retryRemainingMs)))
        or (wood and type(value.returnedToBase) ~= "boolean")
        or (wood and value.toolReason ~= nil and (type(value.toolReason) ~= "string" or #value.toolReason > 96))
        or (wood and value.woodWork ~= nil and (not SC.ExpeditionWood
            or not SC.ExpeditionWood.valid(value.woodWork)))
        or type(value.items) ~= "table" or #value.items > (wood and WOOD_LIMIT or 16)
        or type(value.members) ~= "table" or #value.members > 4 then return false end
    local ids = {}
    for _, row in ipairs(value.items) do
        if type(row) ~= "table" or not validId(row.id)
            or ids[row.id] or not validId(row.itemType)
            or not validId(row.finderId, 128)
            or not validId(row.finderName, 80)
            or (row.carrierId ~= nil and not validId(row.carrierId, 128))
            or (row.carrierName ~= nil and not validId(row.carrierName, 80))
            or (row.carrierKind ~= nil and row.carrierKind ~= "member"
                and row.carrierKind ~= "trunk")
            or type(row.returned) ~= "boolean"
            or type(row.stored) ~= "boolean"
            or (row.released ~= nil and type(row.released) ~= "boolean")
            or (row.stored and row.released == true)
            or (row.storageId ~= nil and not validId(row.storageId, 128))
            or (row.reason ~= nil and (type(row.reason) ~= "string"
                or #row.reason > 96))
            or (wood and (row.itemType ~= "Base.Log"
                or type(row.retryRemainingMs) ~= "number"
                or row.retryRemainingMs < 0 or row.retryRemainingMs > WOOD_RETRY_MS
                or row.retryRemainingMs ~= math.floor(row.retryRemainingMs)))
            or (row.stored and (not row.returned or row.storageId == nil)) then
            return false
        end
        if row.destination ~= nil then
            local destination = row.destination
            if not wood or type(destination) ~= "table"
                or (destination.kind ~= "container" and destination.kind ~= "log_yard") then return false end
            if destination.kind == "container" then
                if not validId(destination.id, 128) then return false end
            else
                if not validId(destination.zoneId, 128) then return false end
                for _, axis in ipairs({ "x", "y", "z" }) do
                    local coordinate = destination[axis]
                    if type(coordinate) ~= "number" or coordinate ~= math.floor(coordinate)
                        or coordinate < (axis == "z" and -32 or 0)
                        or coordinate > (axis == "z" and 31 or 30000) then return false end
                end
            end
        end
        ids[row.id] = true
    end
    local members = {}
    for _, row in ipairs(value.members) do
        if type(row) ~= "table" or not validId(row.id, 128)
            or members[row.id] or not validId(row.name, 80)
            or type(row.commandSerial) ~= "number"
            or row.commandSerial < 0 or row.commandSerial > 10000000
            or row.commandSerial ~= math.floor(row.commandSerial)
            or type(row.restockIndex) ~= "number"
            or row.restockIndex < 1 or row.restockIndex > #ESSENTIALS + 1
            or row.restockIndex ~= math.floor(row.restockIndex)
            or type(row.dutyDone) ~= "boolean"
            or (row.dutyReason ~= nil and (type(row.dutyReason) ~= "string"
                or #row.dutyReason > 96))
            or type(row.shortages) ~= "table" then return false end
        for key, amount in pairs(row.shortages) do
            if key ~= "food" and key ~= "water" and key ~= "medicine"
                and key ~= "ammunition" or type(amount) ~= "number"
                or amount < 0 or amount > 100 then return false end
        end
        members[row.id] = true
    end
    return true
end

function Integration.copy(value)
    if not Integration.valid(value) then return nil end
    local copy = { version = value.version, kind = value.kind,
        requestedMode = value.requestedMode, tripId = value.tripId,
        retryRemainingMs = remainingRetry(value),
        returnedToBase = value.returnedToBase,
        toolReason = value.toolReason,
        woodWork = woodRecord(value) and value.woodWork and SC.ExpeditionWood.copy(value.woodWork) or nil,
        baseId = value.baseId, carId = value.carId,
        restock = value.restock, requested = value.requested,
        items = {}, members = {} }
    for index, row in ipairs(value.items) do copy.items[index] = copyRow(row) end
    for index, row in ipairs(value.members) do
        local shortages = {}
        for key, amount in pairs(row.shortages) do shortages[key] = amount end
        copy.members[index] = { id = row.id, name = row.name,
            commandSerial = row.commandSerial,
            restockIndex = row.restockIndex, dutyDone = row.dutyDone,
            dutyReason = row.dutyReason, shortages = shortages }
    end
    return copy
end

function Integration.create(mission)
    local scout = mission and mission.scout
    local wood = scout and scout.kind == "wood"
    local search = scout and (wood and scout.wood or scout.search)
    if not search then return nil end
    local base = SC.BaseLife and SC.BaseLife.active()
    local request = search.request or {}
    local record = { version = wood and 2 or 1, kind = wood and "wood" or nil,
        requestedMode = wood and request.mode or nil, tripId = mission.radioSession,
        retryRemainingMs = wood and 0 or nil,
        woodWork = wood and SC.ExpeditionWood and SC.ExpeditionWood.copy(search) or nil,
        baseId = mission.homeBaseId or base and base.id or nil,
        carId = scout.vehicle and scout.vehicle.sqlId or nil,
        requested = wood and request.mode == "full" and WOOD_LIMIT or request.quantity,
        restock = mission.restockBaseDuty == true,
        items = {}, members = {} }
    if wood then record.returnedToBase = false end
    local names = {}
    for _, member in ipairs(mission.roster) do
        names[member.id] = member.name or member.id
        local state = member.actor and SC.Commands and SC.Commands.peek(member.actor)
        record.members[#record.members + 1] = {
            id = member.id, name = names[member.id],
            commandSerial = mission.commandSerials
                and mission.commandSerials[member.id]
                or tonumber(state and state.commandSerial) or 0,
            restockIndex = 1, dutyDone = not record.restock,
            shortages = {},
        }
    end
    for _, receipt in ipairs(search.acquisitions) do
        record.items[#record.items + 1] = {
            id = receipt.id, itemType = receipt.itemType,
            finderId = receipt.memberId,
            finderName = names[receipt.memberId] or receipt.memberId,
            returned = false, stored = false,
            reason = record.baseId == nil and "base_missing" or nil,
            retryRemainingMs = wood and 0 or nil,
        }
    end
    return record
end

local function scan(container, wanted, result, holder, member, kind,
        depth, seen, budget)
    if container == nil or depth > 4 or seen[container] or budget.left <= 0 then
        return
    end
    seen[container] = true
    for _, item in ipairs(U().inventoryItems(container,
            math.min(budget.left, 2048))) do
        budget.left = budget.left - 1
        local id = U().itemStableId(item, false)
        if wanted[id] and result[id] == nil
            and U().itemType(item) == wanted[id] then
            result[id] = { item = item, source = container,
                holder = holder, member = member, kind = kind }
        end
        local nested = call(item, "getItemContainer") or call(item, "getInventory")
        if nested and nested ~= container then
            scan(nested, wanted, result, holder, member, kind,
                depth + 1, seen, budget)
        end
        if budget.left <= 0 then break end
    end
end

local function locations(record)
    local now = U().nowMs()
    local cached = locationCache[record]
    if cached and now - cached.at >= 0 and now - cached.at < 750 then
        return cached.rows
    end
    local wanted, result = {}, {}
    for _, row in ipairs(record.items) do
        if not row.stored and not row.released then wanted[row.id] = row.itemType end
    end
    for _, member in ipairs(record.members) do
        local registered = SC.Registry and SC.Registry.byId(member.id)
        local actor = registered and registered.actor
        if actor and not U().isDead(actor) then
            scan(U().inventory(actor), wanted, result, actor, member, nil,
                0, {}, { left = 2048 })
        end
    end
    local car = record.carId and SC.Vehicle
        and SC.Vehicle.loadedBySqlId(record.carId)
    local _, trunk
    if car and type(SC.Vehicle.cargoPart) == "function" then _, trunk = SC.Vehicle.cargoPart(car) end
    if trunk then
        scan(trunk, wanted, result, car, nil, "trunk",
            0, {}, { left = 2048 })
    end
    locationCache[record] = { at = now, rows = result }
    return result
end

local function sourceWithin(source, root)
    local current, seen = source, {}
    for _ = 1, 12 do
        if current == root then return true end
        if current == nil or seen[current] then return false end
        seen[current] = true
        local holder = call(current, "getContainingItem")
        local parent = holder and call(holder, "getContainer")
        if not parent or not U().inventoryContains(parent, holder) then
            return false
        end
        current = parent
    end
    return false
end

local function locate(record, row, rescanned)
    local entry = locations(record)[row.id]
    if entry and U().inventoryContains(entry.source, entry.item)
        and call(entry.item, "getContainer") == entry.source then
        local root
        if entry.kind == "trunk" then
            local car = record.carId and SC.Vehicle
                and SC.Vehicle.loadedBySqlId(record.carId)
            if car and type(SC.Vehicle.cargoPart) == "function" then
                local ignored
                ignored, root = SC.Vehicle.cargoPart(car)
            end
        else
            root = entry.holder and U().inventory(entry.holder)
        end
        if root and sourceWithin(entry.source, root) then
            return entry.item, entry.source, entry.holder,
                entry.member, entry.kind
        end
    end
    if entry and not rescanned then
        -- A player can rearrange a bag inside the cache window. A mismatched
        -- source invalidates the snapshot; it never proves the item is absent.
        locationCache[record] = nil
        return locate(record, row, true)
    end
    return nil
end

-- Ordinary discovery is cached and bounded. Only a transition that could
-- release work needs this complete, fresh inspection of authorized holders.
local function inspectCargo(record)
    local found, complete = {}, true
    local wanted = {}
    for _, row in ipairs(record.items) do
        if not row.stored and not row.released then wanted[row.id] = row.itemType end
    end
    local function inspect(root)
        if root == nil then complete = false return end
        local pending, seen, examined, containers = { root }, {}, 0, 0
        while #pending > 0 do
            local container = table.remove(pending)
            containers = containers + 1
            if seen[container] or containers > 64 then complete = false return end
            seen[container] = true
            local items, readable = U().call(container, "getItems")
            if not readable or items == nil then complete = false return end
            local count, counted = U().call(items, "size")
            if not counted and type(items) == "table" and type(items.size) ~= "function" then
                count = #items
                for index in pairs(items) do
                    if type(index) ~= "number" or index < 1 or index > count
                        or index ~= math.floor(index) then complete = false return end
                end
                counted = true
            end
            if not counted or type(count) ~= "number" or count ~= count
                or count < 0 or count ~= math.floor(count) or examined + count > 4096 then
                complete = false return
            end
            for index = 0, count - 1 do
                local item, read = U().call(items, "get", index)
                if not read and type(items) == "table" and type(items.get) ~= "function" then
                    item, read = items[index + 1], true
                end
                if not read or item == nil then complete = false return end
                examined = examined + 1
                if call(item, "getContainer") ~= container then complete = false return end
                local id = U().itemStableId(item, false)
                if wanted[id] and U().itemType(item) == wanted[id] then found[id] = true end
                local nested
                for _, method in ipairs({ "getItemContainer", "getInventory" }) do
                    local value, okay = U().call(item, method)
                    local hasMethod = U().hasMethod and U().hasMethod(item, method)
                        or type(item) == "table" and type(item[method]) == "function"
                    if not okay and hasMethod then complete = false return end
                    nested = nested or value
                end
                if nested then pending[#pending + 1] = nested end
            end
        end
    end
    for _, member in ipairs(record.members) do
        local registered = SC.Registry and SC.Registry.byId(member.id)
        local actor = registered and registered.actor
        if actor and not U().isDead(actor) then inspect(U().inventory(actor)) end
    end
    if record.carId ~= nil then
        local car = SC.Vehicle and SC.Vehicle.loadedBySqlId(record.carId)
        local _, trunk
        if car and SC.Vehicle.cargoPart then _, trunk = SC.Vehicle.cargoPart(car) end
        inspect(trunk)
    end
    return found, complete
end

local function woodMarker(item)
    local data = U().modData and U().modData(item) or call(item, "getModData")
    return data and data.LF_ExpeditionWood, data
end
local function ownsWood(record, row, item)
    if not woodRecord(record) then return true end
    local marker = woodMarker(item)
    return marker == nil or type(marker) == "table"
        and marker.tripId == record.tripId and marker.id == row.id
end
local function finishWoodStorage(record, row, item, storageId)
    if not ownsWood(record, row, item) then
        row.reason = "cargo_claim_changed"
        return false
    end
    local marker, data = woodMarker(item)
    if marker ~= nil and data then data.LF_ExpeditionWood = nil end
    row.stored, row.returned, row.storageId, row.reason = true, true, storageId, nil
    row.retryRemainingMs = 0
    retryClocks[row] = nil
    locationCache[record] = nil
    return true
end
local function exactIn(container, row)
    if not container then return nil end
    for _, item in ipairs(U().inventoryItems(container, 4096)) do
        if U().itemStableId(item, false) == row.id and U().itemType(item) == row.itemType
            and call(item, "getContainer") == container
            and U().inventoryContains(container, item) then return item end
    end
    return nil
end
-- The destination is journalled before the native effect. A mutation followed
-- by an exception is reconciled by exact identity, never by making another log.
local function reconcileWoodStorage(record, row)
    local destination = row.destination
    if not woodRecord(record) or row.stored or row.released or not destination then return false end
    local item, storageId
    if destination.kind == "container" then
        for _, storage in ipairs(SC.BaseLife and SC.BaseLife.storageRows(nil, false) or {}) do
            if storage.id == destination.id then
                item = exactIn(SC.BaseLife.resolveContainer(storage), row)
                storageId = storage.id
                break
            end
        end
    else
        local yard = SC.LogYard
        local square = yard and yard.tile(destination.x, destination.y,
            destination.z, destination.zoneId)
        local objects = square and call(square, "getWorldObjects")
        local count = objects and U().listSize and U().listSize(objects)
        if type(count) == "number" and count <= 128 then
            for index = 0, count - 1 do
                local world = U().listGet(objects, index)
                local candidate = world and call(world, "getItem")
                if candidate and U().itemStableId(candidate, false) == row.id
                    and U().itemType(candidate) == row.itemType
                    and call(candidate, "getContainer") == nil
                    and call(candidate, "getWorldItem") == world
                    and U().worldItemPresent(square, world) == true then
                    item, storageId = candidate, destination.zoneId
                    break
                end
            end
        end
    end
    if item then
        if locate(record, row) then
            row.reason = "cargo_ownership_ambiguous"
            return false
        end
        return finishWoodStorage(record, row, item, storageId)
    end
    return false
end

local function atBase(holder)
    if not SC.BaseLife then return false end
    return SC.BaseLife.isInside(holder) == true
        or SC.BaseLife.isInside(holder, "parking") == true
end

local function woodCarAtHome(record, car)
    if not woodRecord(record) or not car or record.carId == nil
        or not SC.Vehicle or SC.Vehicle.loadedBySqlId(record.carId) ~= car
        or type(SC.Vehicle.isStationary) ~= "function"
        or SC.Vehicle.isStationary(car) ~= true
        or call(car, "isEngineRunning") ~= false then return false end
    if atBase(car) then return true end
    if not SC.BaseLife or type(SC.BaseLife.withinWorkReach) ~= "function"
        or SC.BaseLife.withinWorkReach(car) ~= true then return false end
    -- A stopped owned car in the reach band is home only after an actual crew
    -- member has returned to camp. Passing the boundary outbound is not return.
    if record.returnedToBase == true then return true end
    for _, member in ipairs(record.members) do
        local registered = SC.Registry and SC.Registry.byId(member.id)
        if registered and registered.actor and not U().isDead(registered.actor)
            and atBase(registered.actor) then record.returnedToBase = true return true end
    end
    return false
end

local function returnedCarrierNearBase(record, actor)
    if not SC.BaseLife or type(SC.BaseLife.withinWorkReach) ~= "function"
        or SC.BaseLife.withinWorkReach(actor) ~= true then return false end
    -- A delivery may need a standing tile just beyond the marked camp edge.
    -- Only an item already credited at camp keeps that route alive; an
    -- expedition merely passing through the reach band must still return.
    for _, row in ipairs(record.items) do
        if row.returned and not row.stored and not row.released then
            local item, _, holder = locate(record, row)
            if item and holder == actor then return true end
        end
    end
    return false
end

function Integration.refresh(record)
    if not Integration.valid(record) then return false end
    for _, row in ipairs(record.items) do
        if not row.stored and not row.released then
            reconcileWoodStorage(record, row)
            local item, _, holder, member, kind = locate(record, row)
            if item then
                if atBase(holder, kind) or kind == "trunk" and woodCarAtHome(record, holder) then row.returned = true end
                if woodRecord(record) and atBase(holder) then record.returnedToBase = true end
                if kind == "trunk" then row.carrierKind = "trunk"
                elseif row.carrierKind ~= "trunk" then
                    row.carrierKind = "member"
                end
                row.carrierId = member and member.id or nil
                row.carrierName = member and member.name or "Car trunk"
                if woodRecord(record) and not row.returned then row.reason = "cargo_pending"
                elseif not woodRecord(record) or (remainingRetry(row) or 0) <= 0
                    and (remainingRetry(record) or 0) <= 0 then
                    row.reason = record.baseId == nil and "base_missing" or nil
                end
            elseif row.stored then
                row.reason = nil
            elseif row.returned then
                row.reason = woodRecord(record) and "cargo_pending" or "item_no_longer_with_squad"
            else
                row.reason = woodRecord(record) and "cargo_pending" or "item_not_found"
            end
        end
    end
    return true
end

function Integration.woodDestinationAvailable(actor)
    local base = SC.BaseLife and SC.BaseLife.active and SC.BaseLife.active()
    if not base then return false, "wood_base_missing" end
    if SC.LogYard and SC.LogYard.hasZone and SC.LogYard.hasZone() then
        return true, "wood_log_yard_registered"
    end
    for _, category in ipairs({ "construction", "general" }) do
        for _, storage in ipairs(SC.BaseLife.depositStorageRows(category)) do
            if storage.deposits ~= false then return true, "wood_storage_registered" end
        end
    end
    return false, "wood_storage_missing"
end

local function woodStoragePoint(storage)
    if storage.kind == "log_yard" then return { x = storage.x, y = storage.y, z = storage.z } end
    local object = SC.BaseLife.resolveObject and SC.BaseLife.resolveObject(storage)
    local x, y, z = U().position(object)
    if type(x) == "number" and type(y) == "number" and type(z) == "number" then
        return { x = x, y = y, z = z }
    end
end

-- This checks geometry, including a currently full destination: space may
-- become available during the trip, but a heavy crew cannot walk across camp.
function Integration.woodReturnShuttleAvailable(actor, carId)
    local car = SC.Vehicle and SC.Vehicle.loadedBySqlId(carId)
    local x, y, z = U().position(car)
    if type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number"
        or SC.Vehicle.isStationary(car) ~= true then return false end
    local function near(target)
        return target and target.z == z and (target.x - x)^2 + (target.y - y)^2 <= 400
    end
    local base = SC.BaseLife.active()
    for _, zone in ipairs(base and base.zones or {}) do
        if zone.kind == "log_yard" and zone.z == z and near({ z = z,
            x = math.max(zone.x1, math.min(x, zone.x2)),
            y = math.max(zone.y1, math.min(y, zone.y2)) }) then return true end
    end
    for _, category in ipairs({ "construction", "general" }) do
        for _, storage in ipairs(SC.BaseLife.depositStorageRows(category)) do
            if storage.deposits ~= false and near(woodStoragePoint(storage)) then return true end
        end
    end
    return false
end

function Integration.summary(record)
    if not Integration.valid(record) then return nil end
    local result = { version = record.version, kind = record.kind, tripId = record.tripId,
        requested = record.requested, collected = #record.items,
        requestedMode = record.requestedMode, requestMode = record.requestedMode,
        broughtBack = 0, returned = 0, carried = 0, stored = 0, released = 0, unknown = 0, pending = 0,
        deliveryPending = false, complete = false, items = {}, members = {} }
    result.retryRemainingMs = remainingRetry(record)
    for _, row in ipairs(record.items) do
        if row.returned then result.broughtBack = result.broughtBack + 1 end
        if row.stored then result.stored = result.stored + 1
        elseif row.released then result.released = result.released + 1
        else
            result.pending = result.pending + 1
            if locate(record, row) then result.carried = result.carried + 1
            else result.unknown = result.unknown + 1 end
        end
        result.items[#result.items + 1] = copyRow(row)
    end
    result.returned = result.broughtBack
    result.toolsPending = woodToolsPending and woodToolsPending(record) or false
    result.toolReason = record.toolReason
    result.deliveryPending = result.pending > 0 or result.toolsPending
    result.complete = not result.deliveryPending
    for _, member in ipairs(record.members) do
        local shortages = {}
        for key, amount in pairs(member.shortages) do shortages[key] = amount end
        result.members[#result.members + 1] = { id = member.id,
            name = member.name, dutyDone = member.dutyDone,
            dutyReason = member.dutyReason, shortages = shortages }
    end
    return result
end

local function restoreFinished()
    local persistence = SC.Persistence
    return type(persistence) ~= "table"
        or type(persistence.restoreStatus) ~= "function"
        or persistence.restoreStatus() == true
end

-- "unknown" covers a dormant or not-yet-respawned companion: its inventory
-- cannot be inspected, so nothing it might carry can be declared lost.
local function memberPresence(member)
    local registered = SC.Registry and SC.Registry.byId(member.id)
    local actor = registered and registered.actor
    if actor then
        if U().isDead(actor) then return "gone" end
        return "present", actor
    end
    if registered then
        local runtime = registered.runtime
        if type(runtime) == "table" and runtime.unrecoverable == true then
            return "gone"
        end
        return "unknown"
    end
    if not restoreFinished() then return "unknown" end
    local persistence = SC.Persistence
    if type(persistence) == "table" and type(persistence.isPending) == "function"
        and persistence.isPending(member.id) == true then return "unknown" end
    return "gone"
end

-- A borrowed axe stays owed while its borrower may still carry it. The loan
-- ends without a return once the borrower is gone, the borrower's whole
-- inventory was read without the exact axe (the player took it), or the
-- storage it came from is no longer marked. A loan nothing can repay must not
-- hold the trip record, and with it the axe's protection, forever.
local function woodLoansSettled(record, lostBase)
    local loans = record.woodWork and record.woodWork.loans
    if type(loans) ~= "table" then return true end
    local worker = SC.ExpeditionWood
    local base = SC.BaseLife
    for memberId, loan in pairs(loans) do
        local presence, actor = memberPresence({ id = memberId })
        local orphaned = restoreFinished() and base and type(base.storage) == "function"
            and type(loan) == "table" and base.storage(loan.storageId) == nil
        if not lostBase and presence ~= "gone" and not orphaned then
            if presence ~= "present" or not worker or type(worker.loanState) ~= "function"
                or worker.loanState(record.woodWork, memberId, actor) ~= "missing" then
                return false
            end
        end
    end
    return true
end

-- A trip record ends once nothing it waits for can still happen: an item
-- eaten, dropped or handed over before storage, a dead or reassigned
-- restocking member, or a camp that was moved. Without this the bounded
-- delivery list fills with records that can never finish.
function Integration.settle(record)
    if not Integration.valid(record) then return true end
    local wood = woodRecord(record)
    -- Exact logs follow the same evidence rule as supply rows below: a log
    -- stays owed while any crew member is unknown or the trunk is unloaded,
    -- and is released only once every possible holder was inspected.
    if wood then Integration.refresh(record) end
    local base = SC.BaseLife and SC.BaseLife.active and SC.BaseLife.active()
    local lostBase = restoreFinished() and (base == nil and "camp_missing"
        or record.baseId ~= nil and base.id ~= record.baseId
            and "camp_changed") or nil
    local settled, conclusive = true, true
    for _, member in ipairs(record.members) do
        local presence, actor = memberPresence(member)
        if presence == "unknown" then conclusive = false end
        if record.restock and not member.dutyDone then
            local command = actor and SC.Commands and SC.Commands.peek(actor)
            if lostBase then
                member.dutyDone, member.dutyReason = true, lostBase
            elseif presence == "gone" then
                member.dutyDone, member.dutyReason = true, "member_unavailable"
            elseif command and tonumber(command.commandSerial) ~= member.commandSerial
                and command.order ~= "base_duty" then
                member.dutyDone, member.dutyReason = true, "new_player_order"
            else
                settled = false
            end
        end
    end
    if record.carId ~= nil and not (SC.Vehicle and SC.Vehicle.loadedBySqlId
        and SC.Vehicle.loadedBySqlId(record.carId)) then conclusive = false end
    local inspected, complete
    for _, row in ipairs(record.items) do
        if not row.stored and not row.released then
            if lostBase then
                row.reason, row.released = lostBase, true
            elseif locate(record, row) then
                settled = false
            elseif conclusive then
                if inspected == nil then inspected, complete = inspectCargo(record) end
                if complete and not inspected[row.id] then
                    row.reason = row.returned and "item_no_longer_with_squad" or "item_not_found"
                    row.released = true
                else settled = false end
            else
                settled = false
            end
        end
    end
    if wood and settled then settled = woodLoansSettled(record, lostBase) end
    return settled
end

local function accessFailure(reason)
    return type(reason) == "string" and (reason == "no_interaction_targets"
        or reason == "no_reachable_interaction_target"
        or reason == "invalid_destination"
        or reason == "engine_path_rejected"
        or reason == "work_path_outside_camp"
        or reason == "navigation_unavailable"
        or reason == "base_storage_action_rejected"
        or string.sub(reason, 1, 13) == "path_blocked:")
end

local function approachTimedOut(state, actor, storage, row)
    local now = U().nowMs()
    local x, y, z = U().position(actor)
    local watch = state.deliveryApproach
    if not watch or watch.storageId ~= storage.id or watch.itemId ~= row.id
        or now < watch.at then
        state.deliveryApproach = {
            storageId = storage.id, itemId = row.id,
            x = x, y = y, z = z, at = now,
        }
        return false
    end
    if x ~= nil and y ~= nil and watch.x ~= nil and watch.y ~= nil
        and z == watch.z
        and (x - watch.x) ^ 2 + (y - watch.y) ^ 2 >= 0.75 ^ 2 then
        watch.x, watch.y, watch.z, watch.at = x, y, z, now
        return false
    end
    -- Storage routes can spend up to 75 seconds planning a valid door detour.
    -- Give the carrier time to walk the result before declaring this container
    -- unreachable; actual movement resets the watch above.
    return now - watch.at >= 180000
end

local function selectStorage(actor, item, state)
    if not SC.BaseWork or not SC.BaseLife then return nil, nil, "base_unavailable" end
    local category = SC.BaseWork.classifyItem(item)
    if category == "food" or category == "fresh_food" then
        category = SC.BaseLife.foodDepositCategory(item)
    end
    local rows = SC.BaseLife.depositStorageRows(category)
    if #rows == 0 then rows = SC.BaseLife.depositStorageRows("general") end
    if #rows == 0 then return nil, nil, "matching_storage_missing" end
    local unavailable = "matching_storage_full"
    local choices = {}
    for _, storage in ipairs(rows) do
        local blockedUntil = state.blockedStorage
            and state.blockedStorage[storage.id] or 0
        local container = blockedUntil <= U().nowMs()
            and SC.BaseLife.resolveContainer(storage) or nil
        if blockedUntil > U().nowMs() then
            unavailable = "matching_storage_unreachable"
        elseif container then
            local accepts = SC.BaseLife.storageAcceptsDeposit(storage, container)
            local room = SC.WorkTransport and SC.WorkTransport.hasRoom
                and SC.WorkTransport.hasRoom(container, actor, item)
            if accepts == true and room == true then
                if not SC.Navigation
                    or type(SC.Navigation.selectInteraction) ~= "function"
                    or type(SC.BaseLife.resolveObject) ~= "function" then
                    return storage, container
                end
                local object = SC.BaseLife.resolveObject(storage)
                if object then
                    choices[#choices + 1] = {
                        id = storage.id, object = object,
                        storage = storage, container = container,
                    }
                end
            end
        else
            unavailable = "matching_storage_unloaded"
        end
    end
    if #choices > 0 then
        if SC.Navigation and type(SC.Navigation.selectInteraction) == "function" then
            local selected, reason = SC.Navigation.selectInteraction(actor, state,
                "expedition_delivery:" .. tostring(state.currentReceiptId),
                choices, { nodeBudget = 1800, workCampOnly = true,
                    workReach = true })
            if selected then
                return selected.storage, selected.container
            end
            if reason == "pending" then
                return nil, nil, "storage_route_pending"
            end
            if reason == "unknown" then
                return nil, nil, "storage_route_unknown"
            end
            return nil, nil, "matching_storage_unreachable"
        end
        return choices[1].storage, choices[1].container
    end
    return nil, nil, unavailable
end

local function selectWoodStorage(actor, item, state, carId)
    local function canCarry(storage)
        if not carId then return true end
        local worker = SC.ExpeditionWood
        if sourceWithin(call(item, "getContainer"), U().inventory(actor)) and U().carryLoad then
            local weight, maximum = U().carryLoad(actor)
            if type(weight) == "number" and type(maximum) == "number" and weight <= maximum then return true end
        elseif worker and worker.carryDestination and worker.carryDestination(actor, item) then return true end
        -- The worker may still need to walk empty-handed to the trunk.
        -- Exact actor proximity and physical admission are checked after that
        -- approach, before taking the log, by woodTakeExact.
        local car = SC.Vehicle and SC.Vehicle.loadedBySqlId(carId)
        local x, y, z = U().position(car)
        local target = woodStoragePoint(storage)
        return target and type(x) == "number" and type(y) == "number" and target.z == z
            and (target.x - x)^2 + (target.y - y)^2 <= 400
            and SC.Vehicle.isStationary(car) == true
    end
    local yard = SC.LogYard
    if yard and yard.hasZone and yard.hasZone() and type(yard.select) == "function" then
        local selected = yard.select(actor)
        if selected then
            selected.id = "yard:" .. tostring(selected.zoneId) .. ":"
                .. tostring(selected.x) .. ":" .. tostring(selected.y) .. ":" .. tostring(selected.z)
            if canCarry(selected) and (not state.blockedStorage
                or (state.blockedStorage[selected.id] or 0) <= U().nowMs()) then
                return selected, selected.square
            end
        end
    end
    local unavailable = "matching_storage_missing"
    for _, category in ipairs({ "construction", "general" }) do
        local choices = {}
        for _, storage in ipairs(SC.BaseLife.depositStorageRows(category)) do
            local blockedUntil = state.blockedStorage and state.blockedStorage[storage.id] or 0
            local container = blockedUntil <= U().nowMs() and SC.BaseLife.resolveContainer(storage) or nil
            if blockedUntil > U().nowMs() then unavailable = "matching_storage_unreachable"
            elseif container then
                local accepts = SC.BaseLife.storageAcceptsDeposit(storage, container)
                local room = accepts == true and SC.WorkTransport and SC.WorkTransport.hasRoom
                    and SC.WorkTransport.hasRoom(container, actor, item)
                if accepts == true and room == true and canCarry(storage) then
                    local object = SC.BaseLife.resolveObject and SC.BaseLife.resolveObject(storage)
                    if object then choices[#choices + 1] = { id = storage.id, object = object,
                        storage = storage, container = container }
                    elseif not SC.BaseLife.resolveObject then return storage, container end
                else unavailable = "matching_storage_full" end
            else unavailable = "matching_storage_unloaded" end
        end
        if #choices > 0 then
            if SC.Navigation and SC.Navigation.selectInteraction then
                local selected, reason = SC.Navigation.selectInteraction(actor, state,
                    "wood_delivery:" .. tostring(state.currentReceiptId), choices,
                    { nodeBudget = 1800, workCampOnly = true, workReach = true })
                if selected then return selected.storage, selected.container end
                if reason == "pending" then return nil, nil, "storage_route_pending" end
                unavailable = "matching_storage_unreachable"
            else return choices[1].storage, choices[1].container end
        end
    end
    return nil, nil, unavailable
end

local function rememberWoodDestination(row, storage)
    if storage.kind == "log_yard" then
        row.destination = { kind = "log_yard", zoneId = storage.zoneId,
            x = storage.x, y = storage.y, z = storage.z }
    else row.destination = { kind = "container", id = storage.id } end
end

local function woodDeposit(actor, state, storage, destination, item, source, record, row)
    local root = U().inventory(actor)
    if not sourceWithin(source, root) or not U().inventoryContains(source, item)
        or call(item, "getContainer") ~= source or not ownsWood(record, row, item) then
        return false, "wood_cargo_ownership_changed"
    end
    if storage.kind == "log_yard" then
        local square = SC.LogYard and SC.LogYard.tile(storage.x, storage.y, storage.z, storage.zoneId)
        local contents = square and SC.LogYard.contents(square)
        if not square then return false, "log_yard_unloaded" end
        if not contents or contents.units >= 4 or contents.splitPending then return false, "destination_full" end
        if not U().sameSquare(actor, square) then
            if not SC.Navigation or not SC.Navigation.requestAny then return false, "navigation_unavailable" end
            return SC.Navigation.requestAny(actor, { square }, "walk", {
                action = "expedition_wood_storage", targetSquare = square, arrivalDistance = 0.45,
                workCampOnly = true, workReach = true, movementPriority = 60 })
        end
        rememberWoodDestination(row, storage)
        local dropped, world = U().dropItem(source, square, item)
        if not U().inventoryContains(source, item) and call(item, "getContainer") == nil
            and world and call(world, "getItem") == item and call(item, "getWorldItem") == world
            and U().worldItemPresent(square, world) == true then
            if SC.LogYard.arrange then SC.LogYard.arrange(square) end
            return true, "wood_supply_deposited"
        end
        if reconcileWoodStorage(record, row) then
            if SC.LogYard.arrange then SC.LogYard.arrange(square) end
            return true, "wood_supply_deposited"
        end
        return false, dropped and "wood_drop_unverified" or world or "wood_drop_failed"
    end
    if SC.BaseLife.storageAcceptsDeposit(storage, destination) ~= true
        or SC.BaseLife.resolveContainer(storage) ~= destination then
        return false, "base_storage_deposits_disabled"
    end
    local object = SC.BaseLife.resolveObject and SC.BaseLife.resolveObject(storage)
    if not object then return false, "base_storage_unloaded" end
    local atStorage, targets, why = U().directInteractionAccess(actor, object)
    if atStorage ~= true then
        if not targets or #targets == 0 then return false, why or "no_interaction_targets" end
        if not SC.Navigation or not SC.Navigation.requestAny then return false, "navigation_unavailable" end
        return SC.Navigation.requestAny(actor, targets, "walk", {
            action = "expedition_wood_storage", targetSquare = U().squareOf(object), object = object,
            arrivalDistance = 0.35, requireSameSquare = true, continuousApproach = true,
            workCampOnly = true, workReach = true, movementPriority = 60 })
    end
    local native = SC.NativeActions
    if not native or not native.visualStatus then return false, "wood_storage_animation_unavailable" end
    if state.visualAt ~= nil then
        if state.storageVisualToken ~= nil and native.visualToken
            and native.visualToken(actor, "loot_container") ~= state.storageVisualToken then
            state.visualAt, state.storageVisualToken = nil, nil
            return false, "wood_storage_visual_changed"
        end
        local status = native.visualStatus(actor, "loot_container")
        if status == "active" then return true, "base_storage_looting" end
        state.visualAt, state.storageVisualToken = nil, nil
        if status ~= "completed" then return false, "wood_storage_animation_" .. tostring(status) end
        if native.clearVisual then native.clearVisual(actor) end
    else
        if SC.Navigation and SC.Navigation.cancel then SC.Navigation.cancel(actor, "wood_storage_interaction") end
        if native.stopDirect then native.stopDirect(actor) elseif U().stop then U().stop(actor) end
        if U().move(actor, "walk", { action = "loot_container", container = destination,
            item = item, baseStorage = true }) ~= true then return false, "base_storage_action_rejected" end
        local status = native.visualStatus(actor, "loot_container")
        if status == "active" then
            state.visualAt = U().nowMs()
            state.storageVisualToken = native.visualToken and native.visualToken(actor, "loot_container")
            return true, "base_storage_looting"
        end
        if status ~= "completed" then return false, "wood_storage_animation_" .. tostring(status) end
        if native.clearVisual then native.clearVisual(actor) end
    end
    if SC.BaseLife.storageAcceptsDeposit(storage, destination) ~= true then return false, "base_storage_deposits_disabled" end
    local room, why = SC.WorkTransport.hasRoom(destination, actor, item)
    if room ~= true then return false, why or "destination_full" end
    rememberWoodDestination(row, storage)
    local moved, reason = SC.WorkTransport.transferVerified(source, destination, item, actor)
    if moved == true and U().inventoryContains(destination, item)
        and call(item, "getContainer") == destination and not U().inventoryContains(source, item) then
        return true, "wood_supply_deposited"
    end
    if reconcileWoodStorage(record, row) then return true, "wood_supply_deposited" end
    return false, reason or "wood_deposit_unverified"
end

local function itemForWorker(record, actor, state)
    if woodRecord(record) and (remainingRetry(record) or 0) > 0 then return nil end
    for _, row in ipairs(record.items) do
        if not row.stored and not row.released and (not state or not state.retryByReceipt
            or (state.retryByReceipt[row.id] or 0) <= U().nowMs())
            and (remainingRetry(row) or 0) <= 0 then
            local item, source, holder, member, kind = locate(record, row)
            if item and (holder == actor or kind == "trunk"
                and (atBase(holder) or woodCarAtHome(record, holder))) then
                return row, item, source, holder, kind
            end
        end
    end
    return nil
end

function Integration.retry(record, receiptId)
    if not Integration.valid(record) then return false, "invalid_delivery_record" end
    local found = receiptId == nil
    if receiptId ~= nil then
        for _, row in ipairs(record.items) do
            if not row.stored and not row.released and row.id == receiptId then found = true break end
        end
    end
    if not found then return false, "delivery_receipt_missing" end
    if woodRecord(record) then
        record.retryRemainingMs = 0
        retryClocks[record] = nil
    end
    for _, row in ipairs(record.items) do
        if not row.stored and not row.released and (receiptId == nil or receiptId == row.id) then
            if row.retryRemainingMs ~= nil then row.retryRemainingMs = 0 end
            retryClocks[row] = nil
            row.reason = nil
        end
    end
    for _, bucket in pairs(states) do
        local state = bucket.byId[record.tripId]
        if state then
            if receiptId then state.retryByReceipt[receiptId] = nil
            else state.retryByReceipt = {} end
            state.blockedStorage, state.woodStorage = nil, nil
        end
    end
    locationCache[record] = nil
    return true, "delivery_retry_queued"
end

local function memberFor(record, actor)
    local id = U().idOf(actor)
    for _, member in ipairs(record.members) do
        if member.id == id then return member end
    end
    return nil
end

woodToolsPending = function(record, actor)
    if not woodRecord(record) or not record.woodWork then return false end
    local id = actor and U().idOf(actor)
    if SC.ExpeditionWood and SC.ExpeditionWood.toolsPending then
        if id then return SC.ExpeditionWood.toolsPending(record.woodWork, id) == true end
        for _, member in ipairs(record.members) do
            if SC.ExpeditionWood.toolsPending(record.woodWork, member.id) then return true end
        end
        return false
    end
    local loans = record.woodWork.loans
    if type(loans) ~= "table" then return false end
    if id then return loans[id] ~= nil end
    for _ in pairs(loans) do return true end
    return false
end

local function returnWoodTools(record, actor)
    if not woodToolsPending(record, actor) then return true, "wood_tools_returned", true end
    local worker = SC.ExpeditionWood
    if not worker or not worker.returnTools then return false, "wood_tool_return_unavailable", false end
    local roster = {}
    for _, member in ipairs(record.members) do
        local registered = SC.Registry and SC.Registry.byId(member.id)
        roster[#roster + 1] = { id = member.id, name = member.name, actor = registered and registered.actor }
    end
    return worker.returnTools(actor, { missionId = record.tripId, wood = record.woodWork,
        roster = roster, carId = record.carId, phase = "return_tools" })
end

local function woodDeliveryReach(record, actor)
    if not woodRecord(record) or not SC.BaseLife.withinWorkReach
        or SC.BaseLife.withinWorkReach(actor) ~= true then return false end
    if woodToolsPending(record, actor) then return true end
    local car = record.carId and SC.Vehicle and SC.Vehicle.loadedBySqlId(record.carId)
    if not woodCarAtHome(record, car) then return false end
    for _, row in ipairs(record.items) do
        if not row.stored and not row.released then
            local item, _, holder, _, kind = locate(record, row)
            if item and kind == "trunk" and holder == car then return true end
        end
    end
    return false
end

local function woodTakeExact(record, actor, item, source, state, row, storage)
    if not ownsWood(record, row, item) then return false, "wood_cargo_ownership_changed" end
    local car = record.carId and SC.Vehicle and SC.Vehicle.loadedBySqlId(record.carId)
    if not woodCarAtHome(record, car) then return false, "cargo_pending" end
    local logging, worker = SC.LoggingWork, SC.ExpeditionWood
    if not logging or not logging.cargo or not worker or not worker.carryDestination then
        return false, "wood_cargo_transfer_unavailable"
    end
    local vehicle, trunk, why, handled = logging.cargo(actor, record.carId, state, nil,
        { workCampOnly = true, workReach = true, movementPriority = 60 })
    if not vehicle then
        local moving = handled == true or why == "wood_approaching" or why == "wood_unlocking_trunk"
            or why == "pending" or why == "arrived"
        return moving, why
    end
    if vehicle ~= car or not woodCarAtHome(record, vehicle)
        or call(item, "getContainer") ~= source or not sourceWithin(source, trunk)
        or U().inventoryContains(source, item) ~= true then
        return false, "wood_cargo_ownership_changed"
    end
    local destination, reason = worker.carryDestination(actor, item,
        { carId = record.carId, target = woodStoragePoint(storage) })
    if not destination then return false, reason or "wood_carry_capacity" end
    if not sourceWithin(destination, U().inventory(actor)) then return false, "wood_carrier_changed" end
    local native = SC.NativeActions
    if not native or not native.visualStatus then return false, "wood_cargo_animation_unavailable" end
    if state.receiptItem ~= item then
        if U().move(actor, "walk", { action = "loot_container", container = trunk,
            item = item, baseStorage = true }) ~= true then return false, "car_trunk_action_rejected" end
        local status = native.visualStatus(actor, "loot_container")
        if status ~= "active" and status ~= "completed" then return false, "car_unload_visual_" .. tostring(status) end
        state.receiptItem = item
        state.receiptVisualToken = native.visualToken and native.visualToken(actor, "loot_container")
        return true, "car_trunk_looting"
    end
    if state.receiptVisualToken ~= nil and native.visualToken
        and native.visualToken(actor, "loot_container") ~= state.receiptVisualToken then
        state.receiptItem, state.receiptVisualToken = nil, nil
        return false, "car_trunk_visual_changed"
    end
    local status = native.visualStatus(actor, "loot_container")
    if status == "active" then return true, "car_trunk_looting" end
    state.receiptItem, state.receiptVisualToken = nil, nil
    if status ~= "completed" then return false, "car_unload_visual_" .. tostring(status) end
    if native.clearVisual then native.clearVisual(actor) end
    local moved, failure = SC.WorkTransport.transferVerified(source, destination, item, actor)
    if call(item, "getContainer") == destination and U().inventoryContains(destination, item) == true
        and U().inventoryContains(source, item) ~= true then return true, "car_item_carried" end
    return false, failure or (moved and "car_receipt_transfer_unverified" or "wood_cargo_transfer_failed")
end

local function safeSupply(item, category, actor)
    if category == "food" then
        return SC.Needs and SC.Needs.isSafeFoodItem
            and SC.Needs.isSafeFoodItem(item) == true
    elseif category == "water" then
        return SC.Needs and SC.Needs.isSafeWaterItem
            and SC.Needs.isSafeWaterItem(item) == true
    elseif category == "medicine" then
        local itemType = U().itemType(item)
        if SC.Logistics.itemCategory(item) ~= "medicine"
            or type(itemType) == "string"
                and string.find(string.lower(itemType), "dirty", 1, true)
            or call(item, "isDirty") == true then return false end
        return true
    end
    local weapon = call(actor, "getPrimaryHandItem")
    if not weapon or call(weapon, "isRanged") ~= true then
        weapon = call(actor, "getSecondaryHandItem")
    end
    if not weapon or call(weapon, "isRanged") ~= true then return false end
    local ammo = call(weapon, "getAmmoType")
    local magazine = call(weapon, "getMagazineType")
    local itemType = U().itemType(item)
    if magazine and magazine ~= "" and itemType == magazine then
        return (tonumber(call(item, "getCurrentAmmoCount")) or 0) > 0
    end
    return ammo ~= nil and ammo ~= "" and itemType == ammo
end

local function restock(actor, member, record, state)
    local category = ESSENTIALS[member.restockIndex]
    if not category then
        if not member.dutyDone then
            local okay, reason = SC.Commands.resumeBaseDutyIfUnchanged(
                member.id, member.commandSerial, record.baseId)
            member.dutyDone, member.dutyReason = true,
                okay and "base_duty_resumed" or reason
        end
        return true, member.dutyReason or "restock_complete"
    end
    local minimums = SC.Logistics and SC.Logistics.roleMinimums(actor) or {}
    local target = tonumber(minimums[category]) or 0
    if category == "ammunition" then
        local primary = call(actor, "getPrimaryHandItem")
        local secondary = call(actor, "getSecondaryHandItem")
        if call(primary, "isRanged") ~= true
            and call(secondary, "isRanged") ~= true then target = 0 end
    end
    if target == 0 then member.restockIndex = member.restockIndex + 1
        return true, "restock_not_needed" end
    local held = 0
    for _, item in ipairs(U().inventoryItemsDeep(U().inventory(actor), 512, 24)) do
        if safeSupply(item, category, actor) then held = held + 1 end
    end
    if held >= target then member.restockIndex = member.restockIndex + 1
        state.restockSince, state.restock = nil, nil
        return true, "restock_minimum_met" end
    state.restockSince = state.restockSince or U().nowMs()
    if U().nowMs() - state.restockSince >= 30000 then
        member.shortages[category] = target - held
        member.restockIndex = member.restockIndex + 1
        state.restockSince, state.restock = nil, nil
        return true, "restock_unreachable_" .. category
    end
    local storageCategory = category == "medicine" and "medical" or category
    local rows = category == "food" and SC.BaseLife.foodDepositRows
        and (function()
            local fresh = SC.BaseLife.storageRows("fresh_food", true)
            local stable = SC.BaseLife.storageRows("food", true)
            for _, row in ipairs(fresh) do stable[#stable + 1] = row end
            return stable
        end)() or SC.BaseLife.storageRows(storageCategory, true)
    if #rows == 0 then rows = SC.BaseLife.storageRows("general", true) end
    local blocked = false
    for _, storage in ipairs(rows) do
        local blockedUntil = state.restockBlocked
            and state.restockBlocked[storage.id] or 0
        if blockedUntil > U().nowMs() then
            blocked = true
        else
            local container = SC.BaseLife.resolveContainer(storage)
            if container then
                for _, item in ipairs(U().inventoryItems(container, 512)) do
                    if safeSupply(item, category, actor) then
                        state.restock = state.restock or {}
                        local taken, reason = SC.BaseWork.withdrawFromStorage(
                            actor, state.restock, storage, container, item)
                        if taken ~= true and accessFailure(reason) then
                            state.restockBlocked = state.restockBlocked or {}
                            state.restockBlocked[storage.id] = U().nowMs() + 15000
                        end
                        if taken == true and reason == "base_supply_taken" then
                            if not U().inventoryContains(U().inventory(actor), item)
                                or U().inventoryContains(container, item) then
                                return false, "restock_transfer_unverified"
                            end
                        end
                        return taken, reason
                    end
                end
            end
        end
    end
    if blocked then return false, "restock_storage_unreachable" end
    member.shortages[category] = target - held
    member.restockIndex = member.restockIndex + 1
    state.restockSince, state.restock = nil, nil
    return true, "restock_shortage_" .. category
end

function Integration.wants(record, actor)
    if not Integration.valid(record) or not actor or U().isDead(actor)
        or not memberFor(record, actor) then return false end
    local base = SC.BaseLife and SC.BaseLife.active()
    if base and record.baseId == nil then record.baseId = base.id end
    if not base or record.baseId ~= base.id then return false end
    if not atBase(actor) and not returnedCarrierNearBase(record, actor)
        and not woodDeliveryReach(record, actor) then
        return false
    end
    local member = memberFor(record, actor)
    local command = SC.Commands and SC.Commands.peek(actor)
    if command and tonumber(command.commandSerial) ~= member.commandSerial
        and command.order ~= "base_duty" then
        if record.restock and not member.dutyDone then
            member.dutyDone, member.dutyReason = true, "new_player_order"
        end
        return false
    end
    local state = stateFor(record, actor, false)
    if woodRecord(record) and (remainingRetry(record) or 0) > 0 then return false end
    if itemForWorker(record, actor, state) then return true end
    if woodRecord(record) then
        local unfinished = false
        for _, row in ipairs(record.items) do
            if not row.stored and not row.released then unfinished = true break end
        end
        if unfinished then
            local now, last = U().nowMs(), settlementClocks[record]
            if last == nil or now < last or now - last >= 5000 then
                settlementClocks[record] = now
                Integration.settle(record)
            end
            for _, row in ipairs(record.items) do
                if not row.stored and not row.released then return false end
            end
        end
        if woodToolsPending(record, actor) then return true end
        if woodToolsPending(record) then return false end
    end
    return record.restock and member.dutyDone ~= true
end

function Integration.update(record, actor)
    if not Integration.wants(record, actor) then return false, "delivery_not_ready" end
    local state = stateFor(record, actor, true)
    local row, item, source, holder, kind = itemForWorker(record, actor, state)
    if not row then
        if woodRecord(record) then
            local handled, reason, done = returnWoodTools(record, actor)
            if done ~= true then
                record.toolReason = safeReason(reason)
                if handled ~= true then
                    record.retryRemainingMs = WOOD_RETRY_MS
                    retryClocks[record] = U().nowMs()
                end
                return handled, reason
            end
            record.toolReason = nil
            if not record.restock then return handled, reason end
        end
        return restock(actor, memberFor(record, actor), record, state)
    end
    if state.currentReceiptId ~= row.id then
        state.deliveryApproach, state.visualAt, state.storageVisualToken = nil, nil, nil
        state.currentReceiptId = row.id
    end
    row.returned = true
    row.carrierKind = kind or row.carrierKind or "member"
    if kind == "trunk" then row.carrierId = nil
    else row.carrierId = U().idOf(actor) end
    row.carrierName = kind and "Car trunk"
        or memberFor(record, actor).name
    local storage, container, why
    if woodRecord(record) then storage, container, why = selectWoodStorage(actor, item, state,
        (kind == "trunk" or row.carrierKind == "trunk") and record.carId or nil)
    else storage, container, why = selectStorage(actor, item, state) end
    if not storage then
        if why == "storage_route_pending" then return true, why end
        state.deliveryApproach = nil
        row.reason = why
        deferReceipt(state, row, 5000)
        if woodRecord(record) then
            record.retryRemainingMs = WOOD_RETRY_MS
            retryClocks[record] = U().nowMs()
            return false, why
        end
        local member = memberFor(record, actor)
        if record.restock and member and not member.dutyDone then
            return restock(actor, member, record, state)
        end
        return false, why
    end
    if kind == "trunk" then
        state.deliveryApproach = nil
        if not woodRecord(record) and (not SC.VehicleUnload or not SC.VehicleUnload.takeExact) then
            row.reason = "trunk_transfer_unavailable"
            return false, row.reason
        end
        local taken, reason
        if woodRecord(record) then taken, reason = woodTakeExact(record, actor, item, source, state, row, storage)
        else taken, reason = SC.VehicleUnload.takeExact(actor, record.carId, item, state, source) end
        row.reason = safeReason(reason)
        if taken == true and reason == "car_item_carried" then
            locationCache[record] = nil
            row.carrierId, row.carrierName, row.carrierKind =
                U().idOf(actor), memberFor(record, actor).name, "trunk"
        elseif woodRecord(record) and taken ~= true then
            deferReceipt(state, row, WOOD_RETRY_MS)
        end
        return taken, reason
    end
    if woodRecord(record) then
        local moved, reason = woodDeposit(actor, state, storage, container, item, source, record, row)
        if moved == true and reason == "wood_supply_deposited" then
            if finishWoodStorage(record, row, item,
                storage.kind == "log_yard" and storage.zoneId or storage.id) then
                state.visualAt, state.deliveryApproach = nil, nil
                return true, "expedition_supply_stored"
            end
            return false, row.reason
        end
        row.reason = safeReason(reason)
        if moved == true and reason == "base_storage_looting" then state.deliveryApproach = nil
        elseif moved == true and approachTimedOut(state, actor, storage, row) then
            state.blockedStorage = state.blockedStorage or {}
            state.blockedStorage[storage.id] = U().nowMs() + WOOD_RETRY_MS * 2
            state.deliveryApproach = nil
            row.reason = "expedition_storage_approach_timeout"
            deferReceipt(state, row, WOOD_RETRY_MS)
            return false, row.reason
        elseif moved ~= true then
            state.deliveryApproach = nil
            if accessFailure(reason) then
                state.blockedStorage = state.blockedStorage or {}
                state.blockedStorage[storage.id] = U().nowMs() + WOOD_RETRY_MS * 2
            end
            deferReceipt(state, row, WOOD_RETRY_MS)
        end
        return moved, reason
    end
    local inventory = U().inventory(actor)
    if source ~= inventory then
        state.deliveryApproach = nil
        local staged, reason = SC.WorkTransport.transferVerified(
            source, inventory, item, actor)
        if not staged then row.reason = safeReason(reason)
            return false, reason end
        if call(item, "getContainer") ~= inventory then
            return false, "bag_transfer_unverified"
        end
        locationCache[record] = nil
        return true, "receipt_taken_from_bag"
    end
    local moved, reason = SC.BaseWork.depositToStorage(
        actor, state, storage, container, item, { movementPriority = 60 })
    if moved == true and reason == "base_supply_returned" then
        if call(item, "getContainer") ~= container
            or U().inventoryContains(inventory, item)
            or not U().inventoryContains(container, item) then
            row.reason = "deposit_unverified"
            return false, row.reason
        end
        row.stored, row.storageId, row.reason = true, storage.id, nil
        locationCache[record] = nil
        state.visualAt = nil
        state.deliveryApproach = nil
        return true, "expedition_supply_stored"
    end
    if moved == true and reason == "base_storage_looting" then
        state.deliveryApproach = nil
    elseif moved == true and approachTimedOut(state, actor, storage, row) then
        state.blockedStorage = state.blockedStorage or {}
        state.blockedStorage[storage.id] = U().nowMs() + 15000
        state.deliveryApproach = nil
        row.reason = "expedition_storage_approach_timeout"
        deferReceipt(state, row, 2500)
        return false, row.reason
    end
    row.reason = safeReason(reason)
    if moved ~= true then
        state.deliveryApproach = nil
        if accessFailure(reason) then
            state.blockedStorage = state.blockedStorage or {}
            state.blockedStorage[storage.id] = U().nowMs() + 15000
        end
        deferReceipt(state, row, 2500)
    end
    return moved, reason
end

function Integration.reset()
    states = setmetatable({}, { __mode = "k" })
    locationCache = setmetatable({}, { __mode = "k" })
    retryClocks = setmetatable({}, { __mode = "k" })
    settlementClocks = setmetatable({}, { __mode = "k" })
end

return Integration
