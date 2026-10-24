-- SPDX-License-Identifier: MIT
-- Exact expedition receipts are delivered by the carrier, through the same
-- approached/animated/verified storage transaction used by base workers.
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.ExpeditionIntegration = SC.ExpeditionIntegration or {}
local Integration = SC.ExpeditionIntegration
local states = setmetatable({}, { __mode = "k" })
local locationCache = setmetatable({}, { __mode = "k" })
local ESSENTIALS = { "food", "water", "medicine", "ammunition" }

local function U() return SC.GameplayUtil end
local function call(object, method, ...)
    local value, okay = U().call(object, method, ...)
    return okay and value or nil
end
local function validId(value, limit)
    return type(value) == "string" and #value > 0 and #value <= (limit or 160)
end
local function safeReason(reason)
    if reason == nil then return nil end
    return string.sub(tostring(reason), 1, 96)
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
    state.retryByReceipt[row.id] = U().nowMs() + delay
end
local function copyRow(row)
    return { id = row.id, itemType = row.itemType,
        finderId = row.finderId, finderName = row.finderName,
        carrierId = row.carrierId, carrierName = row.carrierName,
        carrierKind = row.carrierKind, returned = row.returned == true,
        stored = row.stored == true, storageId = row.storageId,
        reason = row.reason }
end

function Integration.valid(value)
    if type(value) ~= "table" or value.version ~= 1
        or not validId(value.tripId, 128)
        or (value.baseId ~= nil and not validId(value.baseId, 128))
        or (value.carId ~= nil and (type(value.carId) ~= "number"
            or value.carId < 0 or value.carId > 2147483647
            or value.carId ~= math.floor(value.carId)))
        or type(value.restock) ~= "boolean"
        or type(value.requested) ~= "number" or value.requested < 1
        or value.requested > 8 or value.requested ~= math.floor(value.requested)
        or type(value.items) ~= "table" or #value.items > 16
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
            or (row.storageId ~= nil and not validId(row.storageId, 128))
            or (row.reason ~= nil and (type(row.reason) ~= "string"
                or #row.reason > 96))
            or (row.stored and (not row.returned or row.storageId == nil)) then
            return false
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
    local copy = { version = 1, tripId = value.tripId,
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
    local search = scout and scout.search
    if not search then return nil end
    local base = SC.BaseLife and SC.BaseLife.active()
    local record = { version = 1, tripId = mission.radioSession,
        baseId = mission.homeBaseId or base and base.id or nil,
        carId = scout.vehicle and scout.vehicle.sqlId or nil,
        requested = search.request.quantity,
        restock = mission.restockBaseDuty == true,
        items = {}, members = {} }
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
        if not row.stored then wanted[row.id] = row.itemType end
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

local function locate(record, row)
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
    return nil
end

local function atBase(holder)
    if not SC.BaseLife then return false end
    return SC.BaseLife.isInside(holder) == true
        or SC.BaseLife.isInside(holder, "parking") == true
end

local function returnedCarrierNearBase(record, actor)
    if not SC.BaseLife or type(SC.BaseLife.withinWorkReach) ~= "function"
        or SC.BaseLife.withinWorkReach(actor) ~= true then return false end
    -- A delivery may need a standing tile just beyond the marked camp edge.
    -- Only an item already credited at camp keeps that route alive; an
    -- expedition merely passing through the reach band must still return.
    for _, row in ipairs(record.items) do
        if row.returned and not row.stored then
            local item, _, holder = locate(record, row)
            if item and holder == actor then return true end
        end
    end
    return false
end

function Integration.refresh(record)
    if not Integration.valid(record) then return false end
    for _, row in ipairs(record.items) do
        if not row.stored then
            local item, _, holder, member, kind = locate(record, row)
            if item then
                if atBase(holder, kind) then row.returned = true end
                if kind == "trunk" then row.carrierKind = "trunk"
                elseif row.carrierKind ~= "trunk" then
                    row.carrierKind = "member"
                end
                row.carrierId = member and member.id or nil
                row.carrierName = member and member.name or "Car trunk"
                row.reason = record.baseId == nil and "base_missing" or nil
            elseif row.returned then
                row.reason = "item_no_longer_with_squad"
            else
                row.reason = "item_not_found"
            end
        end
    end
    return true
end

function Integration.summary(record)
    if not Integration.valid(record) then return nil end
    local result = { requested = record.requested, collected = #record.items,
        broughtBack = 0, stored = 0, pending = 0, items = {}, members = {} }
    for _, row in ipairs(record.items) do
        if row.returned then result.broughtBack = result.broughtBack + 1 end
        if row.stored then result.stored = result.stored + 1
        else result.pending = result.pending + 1 end
        result.items[#result.items + 1] = copyRow(row)
    end
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

-- A trip record ends once nothing it waits for can still happen: an item
-- eaten, dropped or handed over before storage, a dead or reassigned
-- restocking member, or a camp that was moved. Without this the bounded
-- delivery list fills with records that can never finish.
function Integration.settle(record)
    if not Integration.valid(record) then return true end
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
    for _, row in ipairs(record.items) do
        if not row.stored then
            if lostBase then
                row.reason = lostBase
            elseif locate(record, row) then
                settled = false
            elseif conclusive then
                row.reason = row.returned and "item_no_longer_with_squad"
                    or "item_not_found"
            else
                settled = false
            end
        end
    end
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

local function itemForWorker(record, actor, state)
    for _, row in ipairs(record.items) do
        if not row.stored and (not state or not state.retryByReceipt
            or (state.retryByReceipt[row.id] or 0) <= U().nowMs()) then
            local item, source, holder, member, kind = locate(record, row)
            if item and (holder == actor or kind == "trunk"
                and atBase(holder)) then
                return row, item, source, holder, kind
            end
        end
    end
    return nil
end

local function memberFor(record, actor)
    local id = U().idOf(actor)
    for _, member in ipairs(record.members) do
        if member.id == id then return member end
    end
    return nil
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
    if not atBase(actor) and not returnedCarrierNearBase(record, actor) then
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
    if itemForWorker(record, actor, state) then return true end
    return record.restock and member.dutyDone ~= true
end

function Integration.update(record, actor)
    if not Integration.wants(record, actor) then return false, "delivery_not_ready" end
    local state = stateFor(record, actor, true)
    local row, item, source, holder, kind = itemForWorker(record, actor, state)
    if not row then
        return restock(actor, memberFor(record, actor), record, state)
    end
    if state.currentReceiptId ~= row.id then
        state.deliveryApproach, state.visualAt = nil, nil
        state.currentReceiptId = row.id
    end
    row.returned = true
    row.carrierKind = kind or row.carrierKind or "member"
    if kind == "trunk" then row.carrierId = nil
    else row.carrierId = U().idOf(actor) end
    row.carrierName = kind and "Car trunk"
        or memberFor(record, actor).name
    local storage, container, why = selectStorage(actor, item, state)
    if not storage then
        if why == "storage_route_pending" then return true, why end
        state.deliveryApproach = nil
        row.reason = why
        deferReceipt(state, row, 5000)
        local member = memberFor(record, actor)
        if record.restock and member and not member.dutyDone then
            return restock(actor, member, record, state)
        end
        return false, why
    end
    if kind == "trunk" then
        state.deliveryApproach = nil
        if not SC.VehicleUnload or not SC.VehicleUnload.takeExact then
            row.reason = "trunk_transfer_unavailable"
            return false, row.reason
        end
        local taken, reason = SC.VehicleUnload.takeExact(
            actor, record.carId, item, state, source)
        row.reason = safeReason(reason)
        if taken == true and reason == "car_item_carried" then
            locationCache[record] = nil
            row.carrierId, row.carrierName, row.carrierKind =
                U().idOf(actor), memberFor(record, actor).name, "trunk"
        end
        return taken, reason
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
end

return Integration
