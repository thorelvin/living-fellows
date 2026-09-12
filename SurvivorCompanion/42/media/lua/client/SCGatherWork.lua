-- SPDX-License-Identifier: MIT

if type(require) == "function" then
    pcall(require, "SCBaseLife")
    pcall(require, "SCWorkTransport")
    pcall(require, "SCNativeList")
end

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.GatherWork = SC.GatherWork or {}
local Gather = SC.GatherWork

local scans = {}
local actorVisuals = {}
local metrics = {
    scannedSquares = 0, examinedObjects = 0, scanYields = 0,
    incompletePasses = 0, candidates = 0, candidateFailures = 0,
    dormantCandidates = 0,
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

local function actorId(actor)
    return U().idOf(actor)
end

local function zoneFor(order)
    local base = SC.BaseLife and SC.BaseLife.active and SC.BaseLife.active() or nil
    for _, zone in ipairs(base and base.zones or {}) do
        if zone.id == order.zoneId and zone.kind == "work" then return zone end
    end
    return nil
end

local function storageFor(order)
    for _, storage in ipairs(SC.BaseLife and SC.BaseLife.storageRows
        and SC.BaseLife.storageRows(nil, false) or {}) do
        if storage.id == order.destinationStorageId and storage.deposits ~= false then
            return storage
        end
    end
    return nil
end

function Gather.validateZone(order)
    local zone = type(order) == "table" and zoneFor(order) or nil
    if not zone then return false, "invalid_gather_work_zone" end
    local tiles = (zone.x2 - zone.x1 + 1) * (zone.y2 - zone.y1 + 1)
    if tiles < 1 or tiles > (U().config("workGatherMaximumTiles") or 256) then
        return false, "gather_work_zone_too_large"
    end
    if not SC.BaseLife.zoneInsideAreaUnion(zone) then
        return false, "gather_work_zone_outside_camp"
    end
    return true, zone
end

local function listCount(list)
    if type(list) == "table" then return #list, true end
    local count, readable = invoke(list, "size")
    count = readable and tonumber(count) or nil
    if count == nil then return nil, false end
    return math.max(0, math.floor(count)), true
end

local function listEntry(list, index)
    if SC.NativeList then return SC.NativeList.get(list, index) end
    if type(list) == "table" then return list[index + 1], true end
    return nil, false
end

local function worldObjects(square)
    local list, readable = invoke(square, "getWorldObjects")
    if readable and list ~= nil then return list, true end
    if type(square) == "table" and type(square.worldItems) == "table" then
        return square.worldItems, true
    end
    return nil, false
end

local function advanceSquare(scan, zone)
    scan.objectIndex = 0
    scan.x = scan.x + 1
    if scan.x > zone.x2 then
        scan.x = zone.x1
        scan.y = scan.y + 1
    end
    if scan.y > zone.y2 then
        scan.x, scan.y = zone.x1, zone.y1
        scan.pass = (scan.pass or 0) + 1
        scan.completed = true
    end
end

local function stateFor(order, zone)
    local scan = scans[order.id]
    if not scan or scan.zoneId ~= zone.id then
        scan = {
            zoneId = zone.id, x = zone.x1, y = zone.y1, objectIndex = 0,
            pass = 0, incomplete = false, completed = false,
            cooldowns = {}, failures = {}, cooldownOrder = {},
        }
        scans[order.id] = scan
    end
    return scan
end

local function rewindScanAfterWorldMutation(order, zone)
    local scan = scans[order.id]
    zone = zone or zoneFor(order)
    if not scan or not zone then return end
    -- Removing a wrapper compacts IsoGridSquare.getWorldObjects(). Continuing
    -- at the old index would skip the item that shifted into that slot.
    scan.x, scan.y, scan.objectIndex = zone.x1, zone.y1, 0
    scan.incomplete, scan.completed = false, false
end

local function candidateKey(item, square, objectIndex)
    local nativeId, idReadable = invoke(item, "getID")
    if idReadable and nativeId ~= nil then return "native:" .. tostring(nativeId) end
    local x, y, z = U().position(square)
    return table.concat({ "square", tostring(x), tostring(y), tostring(z),
        tostring(objectIndex), U().itemType(item) }, ":")
end

local function cooldownActive(scan, key)
    local expires = tonumber(scan.cooldowns[key]) or 0
    if expires <= now() then
        scan.cooldowns[key] = nil
        return false
    end
    return true
end

function Gather.noteCandidateFailure(orderId, candidate, reason)
    local scan = scans[orderId]
    if not scan or type(candidate) ~= "table" or not candidate.key then return false end
    local key = candidate.key
    if scan.cooldowns[key] == nil then scan.cooldownOrder[#scan.cooldownOrder + 1] = key end
    local failures = (scan.failures[key] or 0) + 1
    scan.failures[key] = failures
    metrics.candidateFailures = metrics.candidateFailures + 1
    local maximum = U().config("workGatherCandidateMaxAttempts") or 3
    if failures >= maximum then
        scan.cooldowns[key] = math.huge
        metrics.dormantCandidates = metrics.dormantCandidates + 1
    else
        local base = U().config("workGatherCandidateCooldownMs") or 15000
        scan.cooldowns[key] = now() + base * (2 ^ math.max(0, failures - 1))
    end
    while #scan.cooldownOrder > 32 do
        local removed = table.remove(scan.cooldownOrder, 1)
        scan.cooldowns[removed] = nil
        scan.failures[removed] = nil
    end
    scan.lastFailure = tostring(reason or "candidate_failed")
    return true
end

function Gather.nextCandidate(order, actor)
    local valid, zoneOrReason = Gather.validateZone(order)
    if not valid then return nil, zoneOrReason, true end
    local zone, scan = zoneOrReason, stateFor(order, zoneOrReason)
    scan.completed = false
    local squareBudget = math.max(1, U().config("workGatherSquaresPerSlice") or 16)
    local objectBudget = math.max(1, U().config("workGatherObjectsPerSlice") or 32)
    local squares, objects = 0, 0
    while squares < squareBudget and objects < objectBudget do
        local square = U().gridSquare(scan.x, scan.y, zone.z)
        if not square then
            scan.incomplete = true
            squares = squares + 1
            metrics.scannedSquares = metrics.scannedSquares + 1
            advanceSquare(scan, zone)
        else
            local list, readable = worldObjects(square)
            if not readable then
                scan.incomplete = true
                squares = squares + 1
                metrics.scannedSquares = metrics.scannedSquares + 1
                advanceSquare(scan, zone)
            else
                local count, countReadable = listCount(list)
                if not countReadable or count > 4096 then
                    scan.incomplete = true
                    squares = squares + 1
                    metrics.scannedSquares = metrics.scannedSquares + 1
                    advanceSquare(scan, zone)
                elseif scan.objectIndex >= count then
                    squares = squares + 1
                    metrics.scannedSquares = metrics.scannedSquares + 1
                    advanceSquare(scan, zone)
                else
                    local index = scan.objectIndex
                    local worldItem, available = listEntry(list, index)
                    scan.objectIndex = scan.objectIndex + 1
                    objects = objects + 1
                    metrics.examinedObjects = metrics.examinedObjects + 1
                    if not available then
                        scan.incomplete = true
                    elseif worldItem then
                        local item, itemReadable = invoke(worldItem, "getItem")
                        if not itemReadable and type(worldItem) == "table" then item = worldItem.item end
                        if item and U().itemType(item) == order.itemType then
                            local key = candidateKey(item, square, index)
                            local protected = SC.WorkTransport.foreignProtected(item, actor)
                            local present = U().worldItemPresent(square, worldItem)
                            if not protected and not cooldownActive(scan, key) and present == true then
                                metrics.candidates = metrics.candidates + 1
                                return {
                                    item = item, worldItem = worldItem, square = square,
                                    key = key, x = scan.x, y = scan.y, z = zone.z,
                                }, "gather_candidate_found", false
                            elseif present == nil then
                                scan.incomplete = true
                            end
                        end
                    end
                end
            end
        end
        if scan.completed then
            local incomplete = scan.incomplete
            scan.incomplete = false
            if incomplete then
                metrics.incompletePasses = metrics.incompletePasses + 1
                return nil, "gather_area_scan_incomplete", false
            end
            return nil, "gather_area_empty", true
        end
    end
    metrics.scanYields = metrics.scanYields + 1
    return nil, "gather_scan_pending", false
end

local function cancelVisual(actor, reason)
    actorVisuals[actor] = nil
    if SC.NativeActions and type(SC.NativeActions.cancelVisual) == "function" then
        pcall(SC.NativeActions.cancelVisual, actor, reason or "gather_cancelled")
    end
end

local function runVisual(actor, receipt, kind, context)
    local visual = actorVisuals[actor]
    local settled = false
    if visual and (visual.receiptId ~= receipt.id or visual.kind ~= kind) then
        cancelVisual(actor, "gather_phase_changed")
        visual = nil
    end
    if visual and visual.phase == "settle" then
        if now() < (visual.settleUntil or 0) then return false, "gather_settling" end
        local moving, movingReadable = invoke(actor, "isMoving")
        if movingReadable and moving == true then
            visual.settleUntil = now() + (U().config("workInteractionSettleMs") or 250)
            return false, "gather_settling"
        end
        actorVisuals[actor] = nil
        visual = nil
        settled = true
    elseif visual then
        local status
        if SC.NativeActions and type(SC.NativeActions.visualStatus) == "function" then
            local ok, value = pcall(SC.NativeActions.visualStatus, actor, "loot_container")
            if ok then status = value end
        end
        if status == "active" then return false, "gather_interacting" end
        actorVisuals[actor] = nil
        if status == "completed" then
            if SC.NativeActions and type(SC.NativeActions.clearVisual) == "function" then
                pcall(SC.NativeActions.clearVisual, actor)
            end
            return true, "gather_interaction_complete"
        end
        if status ~= nil then return false, "gather_interaction_" .. tostring(status), true end
    end
    if SC.Navigation and type(SC.Navigation.cancel) == "function" then
        pcall(SC.Navigation.cancel, actor, "gather_interaction")
    end
    if SC.NativeActions and type(SC.NativeActions.stopDirect) == "function" then
        pcall(SC.NativeActions.stopDirect, actor)
    else U().stop(actor) end
    if not settled then
        actorVisuals[actor] = {
            receiptId = receipt.id, kind = kind, phase = "settle", startedAt = now(),
            settleUntil = now() + (U().config("workInteractionSettleMs") or 250),
        }
        return false, "gather_settling"
    end
    context = type(context) == "table" and context or {}
    context.action = "loot_container"
    context.workReceiptId = receipt.id
    context.workInteraction = kind
    if kind == "pickup" then context.lootPosition = "Low" end
    local accepted = U().move(actor, "walk", context)
    if accepted ~= true then return false, "gather_interaction_rejected", true end
    local status
    if SC.NativeActions and type(SC.NativeActions.visualStatus) == "function" then
        local ok, value = pcall(SC.NativeActions.visualStatus, actor, "loot_container")
        if ok then status = value end
    end
    if status == "completed" then
        if SC.NativeActions and type(SC.NativeActions.clearVisual) == "function" then
            pcall(SC.NativeActions.clearVisual, actor)
        end
        return true, "gather_interaction_complete"
    end
    if status ~= nil and status ~= "active" then
        return false, "gather_interaction_" .. tostring(status), true
    end
    actorVisuals[actor] = {
        receiptId = receipt.id, kind = kind, phase = "visual", startedAt = now(),
    }
    return false, "gather_interacting"
end

local function approach(actor, target, action)
    if U().distance(actor, target) <= 1.5 then return true, "gather_in_range" end
    if not SC.Navigation or type(SC.Navigation.requestAny) ~= "function" then
        return false, "navigation_unavailable", true
    end
    local approaches = SC.Navigation.interactionTargets(actor, target)
    if type(approaches) ~= "table" or #approaches == 0 then
        local square = U().squareOf(target) or target
        approaches = { square }
    end
    local accepted, reason = SC.Navigation.requestAny(actor, approaches, "walk", {
        action = action, targetSquare = U().squareOf(target) or target,
        object = target, arrivalDistance = 1.0, workCampOnly = true,
    })
    return accepted == true, reason or "gather_approaching", accepted ~= true
end

local function updateSelected(actor, order, receipt, candidate)
    local item, worldItem = SC.WorkTransport.runtimeItem(receipt.id)
    if not item or not worldItem then
        local reconciled, reason = SC.WorkTransport.reconcile(receipt, actor)
        if not reconciled then return false, reason, receipt.phase == "quarantined" end
        item, worldItem = SC.WorkTransport.runtimeItem(receipt.id)
    end
    if receipt.phase ~= "selected" then return true, "gather_receipt_reconciled" end
    local square = U().gridSquare(receipt.source.x, receipt.source.y, receipt.source.z)
    if not square or not worldItem then return false, "gather_source_unloaded", true end
    local arrived, reason, terminal = approach(actor, worldItem, "move_to_gather_item")
    if not arrived then
        if terminal and receipt.phase == "selected" then
            local released = SC.WorkTransport.abandonSelected(receipt, reason)
            if released then
                Gather.noteCandidateFailure(order.id, candidate or {
                    key = candidateKey(item, square, 0),
                }, reason)
            end
        end
        return false, reason, terminal
    end
    local visualComplete, visualReason, visualTerminal = runVisual(actor, receipt, "pickup", {
        item = item, worldItem = worldItem, targetSquare = square,
    })
    if not visualComplete then
        if visualTerminal and receipt.phase == "selected" then
            local released = SC.WorkTransport.abandonSelected(receipt, visualReason)
            if released then
                Gather.noteCandidateFailure(order.id, candidate or {
                    key = candidateKey(item, square, 0),
                }, visualReason)
            end
            return false, visualReason, true
        end
        return true, visualReason, false
    end
    local collected, collectReason = SC.WorkTransport.collect(receipt, actor, item, worldItem)
    if collected then rewindScanAfterWorldMutation(order) end
    if not collected and receipt.phase == "selected" and receipt.owner == "world" then
        local released = SC.WorkTransport.abandonSelected(receipt, collectReason)
        if released then Gather.noteCandidateFailure(order.id, candidate or {
            key = candidateKey(item, square, 0),
        }, collectReason) end
    end
    return collected == true, collectReason, not collected
end

local function updateCarried(actor, order, receipt)
    local item = SC.WorkTransport.runtimeItem(receipt.id)
    if not item then
        local reconciled, reason = SC.WorkTransport.reconcile(receipt, actor)
        if not reconciled then return false, reason, receipt.phase == "quarantined" end
        item = SC.WorkTransport.runtimeItem(receipt.id)
    end
    if receipt.phase == "delivered" then return true, "gather_delivery_reconciled" end
    if receipt.phase ~= "carried" and receipt.phase ~= "depositing" then
        return false, receipt.blocker or "gather_receipt_not_carried", true
    end
    local storage = storageFor(order)
    local container, object = storage and SC.BaseLife.resolveContainer(storage) or nil, nil
    if storage then container, object = SC.BaseLife.resolveContainer(storage) end
    if not storage or storage.deposits == false then
        SC.BaseLife.blockGatherOrder(order.id, "destination_storage_invalid")
        return false, "destination_storage_invalid", true
    end
    if not container or not object then
        SC.BaseLife.blockGatherOrder(order.id, "destination_storage_unloaded")
        return false, "destination_storage_unloaded", true
    end
    local room, roomReason = SC.WorkTransport.hasRoom(container, actor, item)
    if not room then
        SC.BaseLife.blockGatherOrder(order.id, roomReason)
        return false, roomReason, true
    end
    local arrived, reason, terminal = approach(actor, object, "move_to_gather_destination")
    if not arrived then
        if terminal then SC.BaseLife.blockGatherOrder(order.id, reason) end
        return false, reason, terminal
    end
    local visualComplete, visualReason, visualTerminal = runVisual(actor, receipt, "deposit", {
        item = item, container = container, object = object, targetSquare = U().squareOf(object),
    })
    if not visualComplete then
        if visualTerminal then SC.BaseLife.blockGatherOrder(order.id, visualReason) end
        return not visualTerminal, visualReason, visualTerminal
    end
    local delivered, deliveryReason = SC.WorkTransport.deposit(receipt, actor, item)
    return delivered == true, deliveryReason, not delivered
end

function Gather.update(actor, state, job)
    local orderId = type(job.target) == "table" and job.target.orderId or nil
    local order = SC.BaseLife.workOrder(orderId)
    if not order then return false, "gather_order_missing", true end
    if order.state == "paused" then return false, "gather_order_paused", false end
    if order.state == "cancelled" or order.state == "completed" then
        return false, "gather_order_" .. order.state, true
    end
    if order.state == "blocked" and (job.state ~= "blocked" or job.retryAt <= now()) then
        order.state, order.blocker, order.updatedAt = "running", nil, now()
    end
    if order.state ~= "running" then return false, order.blocker or "gather_blocked", false end

    local id = actorId(actor)
    local permitted = false
    for _, workerId in ipairs(order.workers) do
        if workerId == id then permitted = true break end
    end
    if not permitted then return false, "gather_worker_not_assigned", true end

    local receipt = SC.WorkTransport.receiptForActor(order.id, id)
    if receipt then
        if receipt.phase == "recovery" then
            local reconciled, reason = SC.WorkTransport.reconcile(receipt, actor)
            if not reconciled then return false, reason, receipt.phase == "quarantined" end
        end
        if receipt.phase == "selected" then return updateSelected(actor, order, receipt) end
        if receipt.phase == "carried" or receipt.phase == "depositing" then
            return updateCarried(actor, order, receipt)
        end
        if receipt.phase == "quarantined" then
            return false, receipt.blocker or "work_receipt_quarantined", true
        end
    end

    if order.delivered >= order.requested then return false, "gather_order_completed", true end
    local candidate, reason, complete = Gather.nextCandidate(order, actor)
    if not candidate then
        if complete or reason == "gather_area_scan_incomplete" then
            SC.BaseLife.blockGatherOrder(order.id, reason)
            return false, reason, true
        end
        return not complete, reason, complete
    end
    local reserved, reserveReason = SC.WorkTransport.reserve(order, job, actor,
        candidate.item, candidate.worldItem, candidate.square)
    if not reserved then
        Gather.noteCandidateFailure(order.id, candidate, reserveReason)
        return false, reserveReason, reserveReason ~= "gather_quota_reserved"
    end
    return true, "gather_item_reserved"
end

function Gather.retryOrder(orderId)
    scans[orderId] = nil
    return true
end

function Gather.cancelActor(actor, reason)
    cancelVisual(actor, reason)
    actorVisuals[actor] = nil
    if SC.Navigation and type(SC.Navigation.cancel) == "function" then
        pcall(SC.Navigation.cancel, actor, reason or "gather_cancelled")
    end
    return true
end

function Gather.diagnostics()
    local result = {}
    for key, value in pairs(metrics) do result[key] = value end
    result.activeScans = 0
    for _ in pairs(scans) do result.activeScans = result.activeScans + 1 end
    return result
end

function Gather.reset(actor)
    if actor then
        Gather.cancelActor(actor, "gather_reset")
    else
        for value in pairs(actorVisuals) do cancelVisual(value, "gather_reset") end
        scans, actorVisuals = {}, {}
        metrics = {
            scannedSquares = 0, examinedObjects = 0, scanYields = 0,
            incompletePasses = 0, candidates = 0, candidateFailures = 0,
            dormantCandidates = 0,
        }
    end
end

return Gather
