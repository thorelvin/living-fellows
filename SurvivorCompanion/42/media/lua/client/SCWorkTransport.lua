-- SPDX-License-Identifier: MIT

if type(require) == "function" then
    pcall(require, "SCBaseLife")
    pcall(require, "SCPersistence")
    pcall(require, "SCNativeList")
end

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.WorkTransport = SC.WorkTransport or {}
local Transport = SC.WorkTransport

Transport.VERSION = 1
Transport.MARKERS = {
    id = "LF_WorkReceiptId",
    state = "LF_WorkReceiptState",
    build = "LF_WorkReceiptBuildId",
}

local liveItems = {}
local liveWorldItems = {}
local metrics = {
    reservations = 0, collections = 0, deliveries = 0,
    recoveryAttempts = 0, reconstructions = 0, quarantines = 0,
    firstReservationAt = nil, lastDeliveryAt = nil,
}
local terminalPhases = { delivered = true, released = true, cancelled = true }
local allowedProtectedOperations = {
    read = true, work_transport = true, release_work_cargo = true, player_move = true,
}

local function U()
    return SC.GameplayUtil
end

local function now()
    return U().nowMs()
end

local function invoke(object, name, ...)
    return U().call(object, name, ...)
end

local function clean(value, maximum)
    local text = tostring(value or "")
    text = string.gsub(text, "[%c]", "")
    if #text > (maximum or 160) then text = string.sub(text, 1, maximum or 160) end
    return text
end

local function itemData(item)
    if item == nil then return nil end
    local data, ok = invoke(item, "getModData")
    if ok and type(data) == "table" then return data end
    if type(item) == "table" then
        item.modData = item.modData or item.__modData or {}
        return item.modData
    end
    return nil
end

local function markerOf(item)
    local data = itemData(item)
    return data and data[Transport.MARKERS.id] or nil
end

local function markerState(item)
    local data = itemData(item)
    return data and data[Transport.MARKERS.state] or nil
end

local function mark(item, receipt, state)
    local data = itemData(item)
    if not data then return false, "work_item_mod_data_unavailable" end
    local existing = data[Transport.MARKERS.id]
    if existing ~= nil and existing ~= receipt.id then return false, "work_item_already_reserved" end
    local beforeId, beforeState, beforeBuild = data[Transport.MARKERS.id],
        data[Transport.MARKERS.state], data[Transport.MARKERS.build]
    data[Transport.MARKERS.id] = receipt.id
    data[Transport.MARKERS.state] = state
    data[Transport.MARKERS.build] = nil
    if data[Transport.MARKERS.id] ~= receipt.id
        or data[Transport.MARKERS.state] ~= state then
        data[Transport.MARKERS.id], data[Transport.MARKERS.state],
            data[Transport.MARKERS.build] = beforeId, beforeState, beforeBuild
        return false, "work_item_marker_not_retained"
    end
    return true
end

local function clearMarker(item, receiptId)
    local data = itemData(item)
    if not data then return false, "work_item_mod_data_unavailable" end
    if data[Transport.MARKERS.id] ~= receiptId then
        return false, "work_item_marker_identity_changed"
    end
    data[Transport.MARKERS.id] = nil
    data[Transport.MARKERS.state] = nil
    if data[Transport.MARKERS.build] == receiptId then
        data[Transport.MARKERS.build] = nil
    end
    if data[Transport.MARKERS.id] ~= nil or data[Transport.MARKERS.state] ~= nil then
        return false, "work_item_marker_clear_failed"
    end
    return true
end

local function itemNativeId(item)
    local value, ok = invoke(item, "getID")
    if ok and value ~= nil then return value end
    if type(item) == "table" then return item.id or item.nativeId end
    return nil
end

local function itemOwner(item)
    local owner, ok = invoke(item, "getContainer")
    if ok then return owner, true end
    if type(item) == "table" then return item.container, true end
    return nil, false
end

local function itemWorldLink(item)
    local worldItem, ok = invoke(item, "getWorldItem")
    if ok then return worldItem, true end
    if type(item) == "table" then return item.worldItem, true end
    return nil, false
end

local function listForContainer(container)
    local items, ok = invoke(container, "getItems")
    if ok and items ~= nil then return items, true end
    if type(container) == "table" and type(container.items) == "table" then
        return container.items, true
    end
    return nil, false
end

local function listCount(list)
    if type(list) == "table" then return #list, true end
    local count, ok = invoke(list, "size")
    count = ok and tonumber(count) or nil
    if count == nil then return nil, false end
    return math.max(0, math.floor(count)), true
end

local function listEntry(list, index)
    if SC.NativeList then return SC.NativeList.get(list, index) end
    if type(list) == "table" then return list[index + 1], true end
    return nil, false
end

local function containerMembership(container, item, maximum)
    if not container or not item then return nil end
    if U().containerContainsIdentity then
        local present = U().containerContainsIdentity(container, item,
            maximum or U().config("workRecoveryInventoryScanLimit") or 4096)
        if present ~= nil then return present end
    end
    local list, readable = listForContainer(container)
    if not readable then return nil end
    local count, countReadable = listCount(list)
    maximum = math.max(1, tonumber(maximum) or 4096)
    if not countReadable or count > maximum then return nil end
    for index = 0, count - 1 do
        local candidate, available = listEntry(list, index)
        if not available then return nil end
        if candidate == item then return true end
    end
    return false
end

local function verifiedContainerOwner(container, item)
    local present = containerMembership(container, item,
        U().config("workRecoveryInventoryScanLimit") or 4096)
    local owner, readable = itemOwner(item)
    if present == nil or not readable then return nil end
    return present == true and owner == container
end

local function capacity(container, actor, item)
    if not container or not actor or not item then return false, "capacity_context_missing" end
    local allowed, called = invoke(container, "hasRoomFor", actor, item)
    if not called then return false, "capacity_unavailable" end
    if allowed ~= true then return false, "destination_full" end
    return true
end

local function storageById(id)
    for _, storage in ipairs(SC.BaseLife and SC.BaseLife.storageRows
        and SC.BaseLife.storageRows(nil, false) or {}) do
        if storage.id == id then return storage end
    end
    return nil
end

local function actorById(id)
    local actor = U().resolveActor(id)
    return actor
end

local function receiptActor(receipt)
    return receipt and actorById(receipt.actorId) or nil
end

local function terminal(receipt)
    return receipt and terminalPhases[receipt.phase] == true
end

local function setFailure(receipt, reason, phase)
    if not receipt then return false, reason end
    receipt.phase = phase or receipt.phase or "recovery"
    receipt.blocker = clean(reason, 160)
    receipt.updatedAt = now()
    return false, receipt.blocker
end

local function retryDelay(attempts)
    local base = tonumber(U().config("workRecoveryRetryBaseMs")) or 500
    local maximum = tonumber(U().config("workRecoveryRetryMaximumMs")) or 5000
    return math.min(maximum, base * (2 ^ math.max(0, (attempts or 1) - 1)))
end

local function quarantine(receipt, reason, owner, preserveDetachedProof)
    metrics.quarantines = metrics.quarantines + 1
    receipt.phase = "quarantined"
    receipt.owner = owner or receipt.owner or "unknown"
    receipt.detachedProof = preserveDetachedProof == true and receipt.detachedProof == true
    receipt.blocker = clean(reason, 160)
    receipt.nextRetryAt = 0
    receipt.updatedAt = now()
    liveItems[receipt.id], liveWorldItems[receipt.id] = nil, nil
    if SC.BaseLife and SC.BaseLife.blockGatherOrder then
        SC.BaseLife.blockGatherOrder(receipt.orderId, receipt.blocker)
    end
    return false, receipt.blocker
end

function Transport.isCargoProtected(item, actorOrId, operation)
    local data = itemData(item)
    if not data then return false end
    local receiptId = data[Transport.MARKERS.id] or data[Transport.MARKERS.build]
    if receiptId == nil then return false end
    if allowedProtectedOperations[operation] then return false end
    local receipt = SC.BaseLife and SC.BaseLife.workReceipt
        and SC.BaseLife.workReceipt(receiptId) or nil
    return receipt == nil or not terminal(receipt)
end

function Transport.marker(item)
    return markerOf(item), markerState(item)
end

function Transport.foreignProtected(item, actor)
    local data = itemData(item)
    if not data then return true, "item_mod_data_unavailable" end
    if data.LF_TradeRecoveryId ~= nil or data.LF_TradeRecoveryBuildId ~= nil then
        return true, "trade_recovery_owned"
    end
    if data.LF_QuestItem == true or data.LF_QuestReward == true then
        return true, "quest_item_owned"
    end
    local workReceiptId = markerOf(item)
    if workReceiptId ~= nil then
        local receipt = SC.BaseLife and SC.BaseLife.workReceipt
            and SC.BaseLife.workReceipt(workReceiptId) or nil
        if receipt == nil or not terminal(receipt) then return true, "work_item_owned" end
    end
    if data[Transport.MARKERS.build] ~= nil then return true, "work_item_building" end
    local favorite, favoriteOk = invoke(item, "isFavorite")
    if favoriteOk and favorite == true then return true, "favorite_item" end
    if SC.PersonalItems and type(SC.PersonalItems.isProtected) == "function"
        and SC.PersonalItems.isProtected(item, actor, "work_gather") then
        return true, "personal_item_owned"
    end
    return false
end

function Transport.hasRoom(container, actor, item)
    return capacity(container, actor, item)
end

-- Strong synchronous boundary shared by new gathering and existing base hauling.
-- Native calls are invocation receipts; exact membership and getContainer agree
-- before a transfer is accepted.
function Transport.transferVerified(source, destination, item, actor)
    if not source or not destination or not item or not actor then
        return false, "invalid_work_transfer"
    end
    if source == destination then return false, "same_container" end
    local sourceOwned = verifiedContainerOwner(source, item)
    if sourceOwned ~= true then
        local destinationOwned = verifiedContainerOwner(destination, item)
        if sourceOwned == false and destinationOwned == true then
            return true, "already_transferred", { idempotent = true, item = item }
        end
        return false, sourceOwned == nil and "source_ownership_unknown"
            or "source_owner_pointer_conflict"
    end
    local room, roomReason = capacity(destination, actor, item)
    if not room then return false, roomReason end
    local moved, reason, details = U().transferItemVerified(source, destination, item)
    local sourceAfter = verifiedContainerOwner(source, item)
    local destinationAfter = verifiedContainerOwner(destination, item)
    if moved == true and sourceAfter == false and destinationAfter == true then
        return true, reason or "transferred", details
    end
    if sourceAfter == false and destinationAfter == true then
        return true, "transferred_postcondition", { item = item, idempotent = true }
    end
    if sourceAfter == true and destinationAfter == false then
        return false, reason or "transfer_rolled_back", details
    end
    return false, (sourceAfter == nil or destinationAfter == nil)
        and "transfer_ownership_unknown" or "transfer_rollback_failed", details
end

local function findMarkedInContainer(container, receiptId)
    if not container then return "unavailable" end
    local list, readable = listForContainer(container)
    if not readable then return "unavailable" end
    local count, countReadable = listCount(list)
    local maximum = U().config("workRecoveryInventoryScanLimit") or 4096
    if not countReadable or count > maximum then return "pending" end
    for index = 0, count - 1 do
        local item, available = listEntry(list, index)
        if not available then return "pending" end
        if markerOf(item) == receiptId then return "found", item end
    end
    return "absent"
end

local function findMarkedInWorld(receipt)
    if type(receipt.source) ~= "table" then return "unavailable" end
    local square = U().gridSquare(receipt.source.x, receipt.source.y, receipt.source.z)
    if not square then return "unavailable" end
    local list, readable = invoke(square, "getWorldObjects")
    if not readable and type(square) == "table" then list, readable = square.worldItems, true end
    if not readable or list == nil then return "unavailable" end
    local count, countReadable = listCount(list)
    if not countReadable or count > 4096 then return "pending" end
    for index = 0, count - 1 do
        local worldItem, available = listEntry(list, index)
        if not available then return "pending" end
        local item, itemReadable = invoke(worldItem, "getItem")
        if not itemReadable and type(worldItem) == "table" then item = worldItem.item end
        if item and markerOf(item) == receipt.id then
            local present = U().worldItemPresent(square, worldItem)
            local link, linkReadable = itemWorldLink(item)
            if present == true and linkReadable and link == worldItem then
                return "found", item, worldItem
            end
            return "conflict", item, worldItem
        end
    end
    return "absent"
end

local function finishDelivery(receipt, item, destination)
    if verifiedContainerOwner(destination, item) ~= true then
        return setFailure(receipt, "destination_owner_pointer_conflict", "recovery")
    end
    receipt.phase, receipt.owner, receipt.detachedProof = "delivered", "destination", false
    receipt.blocker, receipt.updatedAt = nil, now()
    liveItems[receipt.id], liveWorldItems[receipt.id] = item, nil
    local accounted, _, accountingReason = SC.BaseLife.accountGatherDelivery(
        receipt.orderId, receipt.id)
    if accounted ~= true then
        return setFailure(receipt, accountingReason or "delivery_accounting_failed", "recovery")
    end
    local cleared, clearReason = clearMarker(item, receipt.id)
    if not cleared then
        -- The physical delivery and receipt are already durable and exactly-once.
        -- A stale marker is harmless because terminal receipts are not protected.
        receipt.blocker = clean(clearReason, 160)
    end
    metrics.deliveries = metrics.deliveries + 1
    metrics.lastDeliveryAt = now()
    return true, accountingReason or "delivery_accounted"
end

function Transport.reserve(order, job, actor, item, worldItem, square)
    if not order or order.state ~= "running" or not actor or not item or not worldItem then
        return nil, "invalid_gather_reservation"
    end
    if U().itemType(item) ~= order.itemType then return nil, "gather_item_type_changed" end
    local protected, protectionReason = Transport.foreignProtected(item, actor)
    if protected then return nil, protectionReason end
    local destination = storageById(order.destinationStorageId)
    local destinationContainer = destination and SC.BaseLife.resolveContainer(destination) or nil
    if not destinationContainer then return nil, "destination_storage_unloaded" end
    local actorInventory = U().inventory(actor)
    local room, roomReason = capacity(actorInventory, actor, item)
    if not room then return nil, roomReason == "destination_full" and "worker_overloaded" or roomReason end
    room, roomReason = capacity(destinationContainer, actor, item)
    if not room then return nil, roomReason end
    local present = U().worldItemPresent(square, worldItem)
    local link, linkReadable = itemWorldLink(item)
    if present ~= true or not linkReadable or link ~= worldItem then
        return nil, present == nil and "world_item_presence_unknown"
            or "world_item_identity_changed"
    end
    local snapshot, snapshotReason = SC.Persistence.captureDetachedItem(item)
    if not snapshot then return nil, snapshotReason or "work_item_capture_failed" end
    local accepted, receipt = SC.BaseLife.allocateWorkReceipt({
        orderId = order.id,
        jobId = job and job.id or nil,
        actorId = U().idOf(actor),
        source = { x = select(1, U().position(square)), y = select(2, U().position(square)),
            z = select(3, U().position(square)) },
        nativeId = itemNativeId(item),
        snapshot = snapshot,
    })
    if accepted ~= true then return nil, receipt end
    local marked, markerReason = mark(item, receipt, "selected")
    if not marked then
        receipt.phase, receipt.owner, receipt.accounted = "cancelled", "world", true
        receipt.blocker, receipt.updatedAt = clean(markerReason, 160), now()
        return nil, markerReason
    end
    liveItems[receipt.id], liveWorldItems[receipt.id] = item, worldItem
    metrics.reservations = metrics.reservations + 1
    metrics.firstReservationAt = metrics.firstReservationAt or now()
    return receipt, "work_item_reserved"
end

local function detachedEvidence(receipt, item, worldItem, sourceSquare, actorInventory,
        destinationContainer)
    local present = sourceSquare and worldItem and U().worldItemPresent(sourceSquare, worldItem) or nil
    local link, linkReadable = itemWorldLink(item)
    local owner, ownerReadable = itemOwner(item)
    local scanLimit = U().config("workRecoveryInventoryScanLimit") or 4096
    local actorHas = containerMembership(actorInventory, item, scanLimit)
    local destinationHas
    if destinationContainer ~= nil then
        destinationHas = containerMembership(destinationContainer, item, scanLimit)
    end
    return present == false and linkReadable and link == nil and ownerReadable and owner == nil
        and actorHas == false and destinationHas == false
end

function Transport.collect(receipt, actor, item, worldItem)
    if not receipt or receipt.phase ~= "selected" or markerOf(item) ~= receipt.id then
        return false, "work_receipt_not_collectable"
    end
    local actorInventory = U().inventory(actor)
    local sourceSquare = U().gridSquare(receipt.source.x, receipt.source.y, receipt.source.z)
    local present = U().worldItemPresent(sourceSquare, worldItem)
    local linkedWorld, linkReadable = itemWorldLink(item)
    local wrappedItem, wrapperReadable = invoke(worldItem, "getItem")
    if not wrapperReadable and type(worldItem) == "table" then
        wrappedItem, wrapperReadable = worldItem.item, true
    end
    if present == nil or not linkReadable or not wrapperReadable then
        return setFailure(receipt, "work_ownership_evidence_incomplete", "selected")
    end
    if present ~= true or linkedWorld ~= worldItem or wrappedItem ~= item then
        -- Type, square and markers are deliberately insufficient: a replacement
        -- object must never satisfy the reservation for a vanished native item.
        return quarantine(receipt, "reserved_world_item_identity_changed", "unknown")
    end
    local storage = storageById(receipt.destinationStorageId)
    local destinationContainer = storage and SC.BaseLife.resolveContainer(storage) or nil
    local room, roomReason = capacity(actorInventory, actor, item)
    if not room then return setFailure(receipt,
        roomReason == "destination_full" and "worker_overloaded" or roomReason, "selected") end
    if not destinationContainer then return setFailure(receipt, "destination_storage_unloaded", "selected") end
    room, roomReason = capacity(destinationContainer, actor, item)
    if not room then return setFailure(receipt, roomReason, "selected") end
    local taken, reason, details = U().takeWorldItemVerified(worldItem, actorInventory, item)
    if verifiedContainerOwner(actorInventory, item) == true
        and select(1, itemWorldLink(item)) == nil
        and U().worldItemPresent(sourceSquare, worldItem) == false then
        receipt.phase, receipt.owner, receipt.detachedProof = "carried", "actor", false
        receipt.blocker, receipt.updatedAt = nil, now()
        local marked, markerReason = mark(item, receipt, "carried")
        if not marked then return quarantine(receipt, markerReason, "actor") end
        liveItems[receipt.id], liveWorldItems[receipt.id] = item, nil
        metrics.collections = metrics.collections + 1
        return true, taken and "work_item_collected" or "work_item_collected_postcondition"
    end
    if U().worldItemPresent(sourceSquare, worldItem) == true then
        receipt.phase, receipt.owner, receipt.detachedProof = "selected", "world", false
        receipt.blocker, receipt.updatedAt = clean(reason, 160), now()
        return false, reason or "world_pickup_rejected"
    end
    if detachedEvidence(receipt, item, worldItem, sourceSquare, actorInventory,
        destinationContainer) then
        receipt.phase, receipt.owner, receipt.detachedProof = "recovery", "detached", true
        receipt.blocker, receipt.updatedAt = clean(reason or "pickup_detached", 160), now()
        liveItems[receipt.id], liveWorldItems[receipt.id] = item, worldItem
        return false, receipt.blocker
    end
    return quarantine(receipt, reason or (details and details.owner)
        or "pickup_ownership_ambiguous", "unknown")
end

function Transport.deposit(receipt, actor, item)
    if not receipt or (receipt.phase ~= "carried" and receipt.phase ~= "depositing") then
        return false, "work_receipt_not_carried"
    end
    local source = U().inventory(actor)
    if verifiedContainerOwner(source, item) ~= true or markerOf(item) ~= receipt.id then
        return setFailure(receipt, "carried_item_ownership_changed", "recovery")
    end
    local storage = storageById(receipt.destinationStorageId)
    local destination = storage and SC.BaseLife.resolveContainer(storage) or nil
    if not storage or storage.deposits == false then
        return setFailure(receipt, "destination_storage_invalid", "carried")
    end
    if not destination then return setFailure(receipt, "destination_storage_unloaded", "carried") end
    receipt.phase, receipt.updatedAt = "depositing", now()
    local marked, markerReason = mark(item, receipt, "depositing")
    if not marked then
        receipt.phase, receipt.owner = "carried", "actor"
        return quarantine(receipt, markerReason, "actor")
    end
    local moved, reason = Transport.transferVerified(source, destination, item, actor)
    if moved == true and verifiedContainerOwner(destination, item) == true then
        return finishDelivery(receipt, item, destination)
    end
    if verifiedContainerOwner(source, item) == true then
        receipt.phase, receipt.owner, receipt.detachedProof = "carried", "actor", false
        receipt.blocker, receipt.updatedAt = clean(reason, 160), now()
        local remarked, remarkReason = mark(item, receipt, "carried")
        if not remarked then return quarantine(receipt, remarkReason, "actor") end
        return false, reason
    end
    local owner, ownerReadable = itemOwner(item)
    if ownerReadable and owner == nil
        and containerMembership(source, item,
            U().config("workRecoveryInventoryScanLimit") or 4096) == false
        and containerMembership(destination, item,
            U().config("workRecoveryInventoryScanLimit") or 4096) == false then
        receipt.phase, receipt.owner, receipt.detachedProof = "recovery", "detached", true
        receipt.blocker, receipt.updatedAt = clean(reason or "deposit_detached", 160), now()
        return false, receipt.blocker
    end
    return quarantine(receipt, reason or "deposit_ownership_ambiguous", "unknown")
end

function Transport.receiptForActor(orderId, actorId)
    local fallback
    for _, receipt in ipairs(SC.BaseLife and SC.BaseLife.workReceipts
        and SC.BaseLife.workReceipts(orderId, false) or {}) do
        if receipt.actorId == actorId then
            if receipt.phase == "carried" or receipt.phase == "depositing"
                or receipt.phase == "recovery" then return receipt end
            fallback = fallback or receipt
        end
    end
    return fallback
end

function Transport.abandonSelected(receipt, reason)
    if not receipt or receipt.phase ~= "selected" then return false, "work_receipt_not_selected" end
    local item, worldItem = liveItems[receipt.id], liveWorldItems[receipt.id]
    local square = receipt.source and U().gridSquare(
        receipt.source.x, receipt.source.y, receipt.source.z) or nil
    if not item or not worldItem or U().worldItemPresent(square, worldItem) ~= true then
        return false, "selected_work_item_ownership_unknown"
    end
    local cleared, clearReason = clearMarker(item, receipt.id)
    if not cleared then return false, clearReason end
    receipt.phase, receipt.owner, receipt.accounted = "cancelled", "world", true
    receipt.blocker, receipt.updatedAt = clean(reason, 160), now()
    liveItems[receipt.id], liveWorldItems[receipt.id] = nil, nil
    return true, "work_selection_released"
end

local function reconstruct(receipt, actor)
    if receipt.detachedProof ~= true or receipt.owner ~= "detached"
        or type(receipt.snapshot) ~= "table" then
        return quarantine(receipt, "detached_reconstruction_unproven", "unknown")
    end
    if not actor then return setFailure(receipt, "work_actor_unavailable", "recovery") end
    local item, reason, partial, partialNativeId, cleaned = SC.Persistence.restoreDetachedItem(
        actor, receipt.snapshot, receipt.id, Transport.MARKERS)
    if item then
        if verifiedContainerOwner(U().inventory(actor), item) ~= true
            or markerOf(item) ~= receipt.id or markerState(item) ~= "verified" then
            return quarantine(receipt, "reconstructed_work_item_unverified", "unknown")
        end
        receipt.phase, receipt.owner, receipt.detachedProof = "carried", "actor", false
        receipt.nativeId = itemNativeId(item)
        receipt.blocker, receipt.updatedAt = nil, now()
        local marked, markerReason = mark(item, receipt, "carried")
        if not marked then return quarantine(receipt, markerReason, "actor") end
        liveItems[receipt.id], liveWorldItems[receipt.id] = item, nil
        metrics.reconstructions = metrics.reconstructions + 1
        return true, "work_item_reconstructed"
    end
    if cleaned == false or partial ~= nil then
        receipt.nativeId = partialNativeId or receipt.nativeId
        return quarantine(receipt, reason or "work_reconstruction_cleanup_unverified", "unknown")
    end
    return setFailure(receipt, reason or "work_reconstruction_failed", "recovery")
end

function Transport.reconcile(receipt, actor)
    if not receipt or terminal(receipt) then return true, "work_receipt_terminal" end
    if receipt.phase == "quarantined" then return false, receipt.blocker or "work_quarantined" end
    actor = actor or receiptActor(receipt)
    local actorInventory = actor and U().inventory(actor) or nil
    local storage = storageById(receipt.destinationStorageId)
    local destination = storage and SC.BaseLife.resolveContainer(storage) or nil
    local destinationState, destinationItem = findMarkedInContainer(destination, receipt.id)
    local actorState, actorItem = findMarkedInContainer(actorInventory, receipt.id)
    local worldState, worldItem, worldWrapper = findMarkedInWorld(receipt)
    local found = (destinationState == "found" and 1 or 0)
        + (actorState == "found" and 1 or 0) + (worldState == "found" and 1 or 0)
    if found > 1 then return quarantine(receipt, "work_item_has_multiple_owners", "unknown") end
    if destinationState == "pending" or actorState == "pending" or worldState == "pending"
        or destinationState == "unavailable" or actorState == "unavailable"
        or worldState == "unavailable" then
        return setFailure(receipt, "work_ownership_evidence_incomplete", receipt.phase)
    end
    if destinationState == "found" then
        if verifiedContainerOwner(destination, destinationItem) ~= true then
            return quarantine(receipt, "destination_owner_pointer_conflict", "unknown")
        end
        return finishDelivery(receipt, destinationItem, destination)
    end
    if actorState == "found" then
        if verifiedContainerOwner(actorInventory, actorItem) ~= true then
            return quarantine(receipt, "actor_owner_pointer_conflict", "unknown")
        end
        receipt.phase, receipt.owner, receipt.detachedProof = "carried", "actor", false
        receipt.blocker, receipt.updatedAt = nil, now()
        local marked, markerReason = mark(actorItem, receipt, "carried")
        if not marked then return quarantine(receipt, markerReason, "actor") end
        liveItems[receipt.id], liveWorldItems[receipt.id] = actorItem, nil
        return true, "work_item_carried"
    end
    if worldState == "found" then
        receipt.phase, receipt.owner, receipt.detachedProof = "selected", "world", false
        receipt.blocker, receipt.updatedAt = nil, now()
        liveItems[receipt.id], liveWorldItems[receipt.id] = worldItem, worldWrapper
        local order = SC.BaseLife and SC.BaseLife.workOrder
            and SC.BaseLife.workOrder(receipt.orderId) or nil
        if order and order.state ~= "running" then
            return Transport.abandonSelected(receipt, "gather_" .. tostring(order.state))
        end
        return true, "work_item_at_source"
    end
    if worldState == "conflict" then
        return quarantine(receipt, "world_item_pointer_conflict", "unknown")
    end
    if receipt.phase == "recovery" and receipt.detachedProof == true then
        return reconstruct(receipt, actor)
    end
    return quarantine(receipt, "work_item_absence_unproven", "unknown")
end

local function settleQuarantinedDelivery(receipt)
    local storage = storageById(receipt and receipt.destinationStorageId)
    local destination = storage and SC.BaseLife.resolveContainer(storage) or nil
    local state, item = findMarkedInContainer(destination, receipt and receipt.id)
    if state ~= "found" then return false, state == "pending" and
        "work_ownership_evidence_incomplete" or "quarantined_destination_not_verified" end
    if verifiedContainerOwner(destination, item) ~= true then
        return false, "destination_owner_pointer_conflict"
    end
    return finishDelivery(receipt, item, destination)
end

function Transport.recoverPending(maximum)
    local receipts = SC.BaseLife and SC.BaseLife.workReceipts
        and SC.BaseLife.workReceipts(nil, false) or {}
    if #receipts == 0 then return true, "no_work_recovery" end
    maximum = math.max(1, math.floor(tonumber(maximum)
        or U().config("workRecoveryPerPulse") or 2))
    local start = math.min(#receipts, math.max(1, SC.BaseLife.workRecoveryCursor()))
    local visited, attempted = 0, 0
    while visited < #receipts and attempted < maximum do
        local index = ((start + visited - 1) % #receipts) + 1
        local receipt = receipts[index]
        visited = visited + 1
        if receipt and receipt.phase ~= "quarantined" and not terminal(receipt)
            and now() >= (receipt.nextRetryAt or 0) then
            attempted = attempted + 1
            metrics.recoveryAttempts = metrics.recoveryAttempts + 1
            local ok, reason = Transport.reconcile(receipt)
            if not ok then
                if reason == "work_ownership_evidence_incomplete" then
                    -- Unloaded actor/source/destination state is not a failed
                    -- recovery attempt. Poll sparsely until the relevant chunk
                    -- returns instead of converting unknown into quarantine.
                    receipt.nextRetryAt = now()
                        + (U().config("workRecoveryRetryMaximumMs") or 5000)
                else
                    receipt.attempts = (receipt.attempts or 0) + 1
                    receipt.nextRetryAt = now() + retryDelay(receipt.attempts)
                    if receipt.attempts >= (U().config("workRecoveryMaxAttempts") or 8) then
                        quarantine(receipt, reason or "work_recovery_exhausted", receipt.owner,
                            receipt.detachedProof == true)
                    end
                end
            else
                receipt.attempts, receipt.nextRetryAt = 0, 0
            end
        end
    end
    SC.BaseLife.workRecoveryCursor(((start + visited - 1) % #receipts) + 1)
    return true, attempted
end

function Transport.retryOrder(orderId)
    local restored, blocked = 0, false
    for _, receipt in ipairs(SC.BaseLife.workReceipts(orderId, true)) do
        if receipt.phase == "quarantined" then
            local settled = settleQuarantinedDelivery(receipt)
            if settled == true then
                restored = restored + 1
            elseif receipt.owner == "detached" and receipt.detachedProof == true
                and type(receipt.snapshot) == "table" then
                receipt.phase, receipt.attempts, receipt.nextRetryAt = "recovery", 0, 0
                receipt.blocker, receipt.updatedAt = nil, now()
                restored = restored + 1
            else
                blocked = true
            end
        end
    end
    if blocked then return false, "work_cargo_manual_release_required" end
    return true, restored > 0 and "work_recovery_retried" or "no_work_recovery_blocker"
end

function Transport.pauseOrder(orderId, reason)
    for _, receipt in ipairs(SC.BaseLife.workReceipts(orderId, false)) do
        if receipt.phase == "selected" then
            if not liveItems[receipt.id] or not liveWorldItems[receipt.id] then
                Transport.reconcile(receipt)
            end
            if receipt.phase == "selected" then
                local released, releaseReason = Transport.abandonSelected(receipt, reason)
                if not released then
                    receipt.blocker, receipt.updatedAt = clean(
                        releaseReason or "selected_release_pending", 160), now()
                end
            end
        end
    end
    return true
end

function Transport.cancelOrder(orderId, reason)
    Transport.pauseOrder(orderId, reason)
    for _, receipt in ipairs(SC.BaseLife.workReceipts(orderId, false)) do
        if receipt.phase == "selected" then
            receipt.blocker = receipt.blocker or "cancelled_release_pending"
        elseif receipt.phase == "carried" or receipt.phase == "depositing"
            or receipt.phase == "recovery" then
            receipt.blocker = "cancelled_with_carried_cargo"
        end
        receipt.updatedAt = now()
    end
    return true
end

function Transport.releaseCarriedCargo(orderId, actorId)
    local released = 0
    for _, receipt in ipairs(SC.BaseLife.workReceipts(orderId, true)) do
        if actorId == nil or receipt.actorId == actorId then
            local actor = receiptActor(receipt)
            local state, item = findMarkedInContainer(actor and U().inventory(actor), receipt.id)
            if state == "found" and verifiedContainerOwner(U().inventory(actor), item) == true then
                local cleared = clearMarker(item, receipt.id)
                if cleared then
                    receipt.phase, receipt.owner, receipt.accounted = "released", "released", true
                    receipt.detachedProof, receipt.blocker, receipt.updatedAt = false, nil, now()
                    liveItems[receipt.id], liveWorldItems[receipt.id] = nil, nil
                    released = released + 1
                end
            end
        end
    end
    return released > 0, released > 0 and "work_cargo_released" or "no_verified_carried_cargo",
        released
end

function Transport.yieldActor(actorId, reason)
    local affectedOrders = {}
    for _, order in ipairs(SC.BaseLife.workOrders(false)) do
        for _, workerId in ipairs(type(order.workers) == "table" and order.workers or {}) do
            if workerId == actorId then affectedOrders[order.id] = true break end
        end
    end
    for _, receipt in ipairs(SC.BaseLife.workReceipts(nil, false)) do
        if receipt.actorId == actorId and not terminal(receipt) then
            affectedOrders[receipt.orderId] = true
            if receipt.phase == "selected" then
                if not liveItems[receipt.id] or not liveWorldItems[receipt.id] then
                    Transport.reconcile(receipt, receiptActor(receipt))
                end
                if receipt.phase == "selected" then
                    local released, releaseReason = Transport.abandonSelected(receipt, reason)
                    if not released then
                        receipt.blocker, receipt.updatedAt = clean(
                            releaseReason or "selected_release_pending", 160), now()
                    end
                end
            end
        end
    end
    for orderId in pairs(affectedOrders) do
        -- Carried cargo is already in the worker's personal inventory. Release
        -- its marker in place instead of stopping unrelated workers.
        Transport.releaseCarriedCargo(orderId, actorId)
        local order = SC.BaseLife.workOrder(orderId)
        if order and type(order.workers) == "table" then
            for index = #order.workers, 1, -1 do
                if order.workers[index] == actorId then table.remove(order.workers, index) end
            end
            if order.state == "running" and #order.workers == 0 then
                order.state, order.blocker = "paused", clean(reason, 160)
            elseif order.state == "running" then
                order.blocker = nil
            end
            order.updatedAt = now()
        end
    end
    return true
end

function Transport.prepareActorRetirement(actor)
    local actorId = U().idOf(actor)
    for _, receipt in ipairs(SC.BaseLife.workReceipts(nil, false)) do
        if receipt.actorId == actorId then
            if receipt.phase == "selected" then
                if not liveItems[receipt.id] or not liveWorldItems[receipt.id] then
                    Transport.reconcile(receipt, actor)
                end
                local released = Transport.abandonSelected(receipt, "worker_retired")
                if not released then
                    quarantine(receipt, "worker_retired_selection_unresolved", "retired")
                end
            else
                local state, item = findMarkedInContainer(U().inventory(actor), receipt.id)
                if state == "found" and verifiedContainerOwner(U().inventory(actor), item) == true then
                    quarantine(receipt, "worker_retired_with_native_cargo", "retired")
                else
                    quarantine(receipt, "worker_retired_ownership_unresolved", "retired")
                end
            end
            liveItems[receipt.id], liveWorldItems[receipt.id] = nil, nil
        end
    end
    return true
end

function Transport.runtimeItem(receiptId)
    return liveItems[receiptId], liveWorldItems[receiptId]
end

function Transport.diagnostics()
    local result = {}
    for key, value in pairs(metrics) do result[key] = value end
    local current = now()
    local oldestCreatedAt = nil
    local pending = 0
    local receipts = SC.BaseLife and SC.BaseLife.workReceipts
        and SC.BaseLife.workReceipts(nil, false) or {}
    for _, receipt in ipairs(receipts) do
        if receipt and not terminal(receipt) then
            pending = pending + 1
            local createdAt = tonumber(receipt.createdAt)
            if createdAt and (not oldestCreatedAt or createdAt < oldestCreatedAt) then
                oldestCreatedAt = createdAt
            end
        end
    end
    result.pendingReceipts = pending
    result.oldestWaitingMs = oldestCreatedAt and math.max(0, current - oldestCreatedAt) or 0
    local startAt = tonumber(metrics.firstReservationAt)
    local elapsedMs = startAt and math.max(1, current - startAt) or 0
    result.deliveriesPerMinute = elapsedMs > 0
        and ((metrics.deliveries or 0) * 60000 / elapsedMs) or 0
    return result
end

function Transport.reset(actor)
    if actor then
        local id = U().idOf(actor)
        for _, receipt in ipairs(SC.BaseLife and SC.BaseLife.workReceipts
            and SC.BaseLife.workReceipts(nil, true) or {}) do
            if receipt.actorId == id then
                liveItems[receipt.id], liveWorldItems[receipt.id] = nil, nil
            end
        end
    else
        liveItems, liveWorldItems = {}, {}
        metrics = {
            reservations = 0, collections = 0, deliveries = 0,
            recoveryAttempts = 0, reconstructions = 0, quarantines = 0,
            firstReservationAt = nil, lastDeliveryAt = nil,
        }
    end
end

return Transport
