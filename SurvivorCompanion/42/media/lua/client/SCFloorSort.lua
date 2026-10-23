-- SPDX-License-Identifier: MIT
-- Exact ground-item intake for marked camp sorting floors. The world item,
-- carrier inventory and destination are the only owners; no item is created.
if type(require) == "function" then
    pcall(require, "SCBaseLife")
    pcall(require, "SCWorkTransport")
    pcall(require, "SCNativeList")
end

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.FloorSort = SC.FloorSort or {}
local Floor = SC.FloorSort

local MARKER = "LF_FloorSortJob"
local scans = {}
local visuals = setmetatable({}, { __mode = "k" })
-- Session clock for carrying an item back to its floor tile, by job id.
local returning = {}
local RETURN_MS = 30000

local function U() return SC.GameplayUtil end
local function now() return U().nowMs() end
local function call(object, name, ...)
    local value, okay = U().call(object, name, ...)
    return okay and value or nil
end
local function itemId(item) return tonumber(call(item, "getID")) end
local function data(item) return call(item, "getModData") end
local function marker(item)
    local fields = data(item)
    return fields and fields[MARKER] or nil
end
local function mark(item, jobId)
    local fields = data(item)
    if not fields or fields[MARKER] ~= nil and fields[MARKER] ~= jobId then
        return false
    end
    fields[MARKER] = jobId
    return fields[MARKER] == jobId
end
local function clear(item, jobId)
    local fields = data(item)
    if not fields or fields[MARKER] ~= jobId then return false end
    fields[MARKER] = nil
    return fields[MARKER] == nil
end
local function zoneById(id, kind)
    local base = SC.BaseLife and SC.BaseLife.active()
    for _, zone in ipairs(base and base.zones or {}) do
        if zone.id == id and (kind == nil or zone.kind == kind) then return zone end
    end
    return nil
end
local function pointIn(zone, x, y, z)
    return zone and z == zone.z and x >= zone.x1 and x <= zone.x2
        and y >= zone.y1 and y <= zone.y2
end
local function count(list)
    if type(list) == "table" then return #list end
    return tonumber(call(list, "size"))
end
local function entry(list, index)
    if type(list) == "table" then return list[index + 1] end
    if SC.NativeList then return select(1, SC.NativeList.get(list, index)) end
    return call(list, "get", index)
end
local function worldItems(square)
    return call(square, "getWorldObjects")
        or type(square) == "table" and square.worldItems or nil
end
local function worldItemAt(square, id, jobId)
    local list = worldItems(square)
    local length = count(list)
    if not length or length > 4096 then return nil, nil end
    for index = 0, length - 1 do
        local worldItem = entry(list, index)
        local item = call(worldItem, "getItem")
            or type(worldItem) == "table" and worldItem.item or nil
        if item and itemId(item) == id and marker(item) == jobId
            and U().worldItemPresent(square, worldItem) == true then
            return item, worldItem
        end
    end
    return nil, nil
end
local function eligible(item, actor)
    if not item or not itemId(item) then return false end
    local ownerJob = marker(item)
    if ownerJob and (not SC.BaseLife or not SC.BaseLife.job
        or SC.BaseLife.job(ownerJob)) then return false end
    if ownerJob and not clear(item, ownerJob) then return false end
    if SC.WorkTransport and SC.WorkTransport.foreignProtected
        and SC.WorkTransport.foreignProtected(item, actor) then return false end
    if SC.BaseWork and SC.BaseWork.choreReserved
        and SC.BaseWork.choreReserved(item) then return false end
    return true
end

local function advance(scan, zone)
    scan.objectIndex = 0
    scan.x = scan.x + 1
    if scan.x > zone.x2 then scan.x, scan.y = zone.x1, scan.y + 1 end
    if scan.y > zone.y2 then
        scan.x, scan.y = zone.x1, zone.y1
        return true
    end
    return false
end

-- At most sixteen tiles and thirty-two world objects per call, including an
-- unreadable square. Each zone keeps its cursor between maintenance pulses.
local function nextItem(zone, actor)
    local scan = scans[zone.id]
    if not scan or scan.x < zone.x1 or scan.x > zone.x2
        or scan.y < zone.y1 or scan.y > zone.y2 then
        scan = { x = zone.x1, y = zone.y1, objectIndex = 0,
            blocked = {}, blockedOrder = {}, blockedReason = nil, sawBlocked = false,
            incomplete = false }
        scans[zone.id] = scan
    end
    local squares, objects = 0, 0
    local function passResult()
        local reason = scan.incomplete and "floor_source_unloaded"
            or scan.sawBlocked and scan.blockedReason or "floor_empty"
        scan.incomplete, scan.sawBlocked = false, false
        if reason == "floor_empty" then scan.blockedReason = nil end
        return nil, reason
    end
    while squares < 16 and objects < 32 do
        local square = U().gridSquare(scan.x, scan.y, zone.z)
        local list = square and worldItems(square) or nil
        local length = count(list)
        if not square or length == nil or length > 4096 then
            scan.incomplete = true
            squares = squares + 1
            if advance(scan, zone) then return passResult() end
        elseif scan.objectIndex >= length then
            squares = squares + 1
            if advance(scan, zone) then return passResult() end
        else
            local worldItem = entry(list, scan.objectIndex)
            scan.objectIndex = scan.objectIndex + 1
            objects = objects + 1
            local item = call(worldItem, "getItem")
                or type(worldItem) == "table" and worldItem.item or nil
            local nativeId = item and itemId(item)
            local cooldown = nativeId and scan.blocked[nativeId]
            if cooldown and cooldown <= now() then
                scan.blocked[nativeId] = nil
                for orderIndex = #scan.blockedOrder, 1, -1 do
                    if scan.blockedOrder[orderIndex] == nativeId then
                        table.remove(scan.blockedOrder, orderIndex)
                    end
                end
                local anyBlocked = false
                for _ in pairs(scan.blocked) do anyBlocked = true break end
                if not anyBlocked then scan.blockedReason = nil end
                cooldown = nil
            end
            if cooldown then scan.sawBlocked = true end
            if not cooldown and eligible(item, actor)
                and U().worldItemPresent(square, worldItem) == true then
                return { item = item, worldItem = worldItem, square = square }
            end
        end
    end
    return nil, "floor_scan_pending"
end

local function deferItem(zone, item, reason)
    local scan = scans[zone.id]
    local nativeId = item and itemId(item)
    if not scan or not nativeId then return end
    if scan.blocked[nativeId] == nil then
        scan.blockedOrder[#scan.blockedOrder + 1] = nativeId
    end
    scan.blocked[nativeId] = now() + 30000
    while #scan.blockedOrder > 128 do
        local old = table.remove(scan.blockedOrder, 1)
        scan.blocked[old] = nil
    end
    scan.blockedReason = reason
    scan.sawBlocked = true
end

local function rewind(zone)
    local scan = scans[zone.id]
    if scan then
        scan.x, scan.y, scan.objectIndex = zone.x1, zone.y1, 0
    end
end

-- A worker that died or was dismissed for good can never deliver or return
-- what it carried (SCBaseFuel's rule: a companion not yet restored from the
-- save still counts as present).
local function workerGone(id)
    if id == nil then return true end
    return SC.BaseWork ~= nil and type(SC.BaseWork.workerUnregistered) == "function"
        and SC.BaseWork.workerUnregistered(id) == true
end

local function openJob(base, zoneId)
    for _, job in ipairs(base.jobs or {}) do
        if job.type == "sort_floor" and job.state ~= "completed"
            and job.state ~= "cancelled" and type(job.target) == "table"
            and job.target.zoneId == zoneId then return job end
    end
    return nil
end

function Floor.audit(base)
    if not base then return false, "base_missing" end
    -- No other resident may take a job assigned to a worker, so a claim left
    -- by one who died or was dismissed would stop its floor for good.
    for _, job in ipairs(base.jobs or {}) do
        if job.type == "sort_floor" and type(job.target) == "table"
            and job.target.floorCargo and workerGone(job.assignedId) then
            Floor.cancel(nil, job)
        end
    end
    local actor
    for _, id in ipairs(SC.BaseLife.dutyResidentIds()) do
        local record = SC.Registry and SC.Registry.byId and SC.Registry.byId(id)
        if record and record.actor then actor = record.actor break end
    end
    if not actor then return false, "floor_worker_missing" end
    for _, zone in ipairs(base.zones or {}) do
        if zone.kind == "sorting_floor" and not openJob(base, zone.id) then
            local candidate, reason = nextItem(zone, actor)
            if candidate then
                -- Audit is only a probe. Let the worker examine this exact
                -- slot again rather than beginning after the sole item.
                local scan = scans[zone.id]
                scan.objectIndex = math.max(0, scan.objectIndex - 1)
                local x = math.floor((zone.x1 + zone.x2) / 2)
                local y = math.floor((zone.y1 + zone.y2) / 2)
                return SC.BaseLife.enqueueJob({ type = "sort_floor", priority = 2,
                    target = { zoneId = zone.id, x = x, y = y, z = zone.z } })
            end
            if reason == "floor_scan_pending" then return false, reason end
        end
    end
    return false, "no_floor_items"
end

local function trashDestination(actor, job)
    local target = job and job.target or nil
    local point = target and target.trashPoint or nil
    local zone = target and zoneById(target.trashZoneId, "trash_pile") or nil
    if zone and point and pointIn(zone, point.x, point.y, point.z) then
        local square = U().gridSquare(point.x, point.y, point.z)
        if square and U().isSquareFree(square) then
            return { zoneId = zone.id, square = square }
        end
    end
    local base = SC.BaseLife and SC.BaseLife.active()
    local best, bestDistance
    local marked = false
    for _, zone in ipairs(base and base.zones or {}) do
        if zone.kind == "trash_pile" then
            marked = true
            for y = zone.y1, zone.y2 do
                for x = zone.x1, zone.x2 do
                    local square = U().gridSquare(x, y, zone.z)
                    if square and U().isSquareFree(square) then
                        local distance = U().distanceSq(actor, square)
                        if not bestDistance or distance < bestDistance then
                            best, bestDistance = { zoneId = zone.id,
                                square = square }, distance
                        end
                    end
                end
            end
        end
    end
    return best, best and nil or marked and "floor_trash_pile_unavailable"
        or "floor_trash_pile_missing"
end

local function destination(actor, item, job)
    if SC.Logistics and SC.Logistics.isTrash(item) then
        local pile, reason = trashDestination(actor, job)
        return pile and { kind = "trash", zoneId = pile.zoneId,
            square = pile.square } or nil, "trash", reason
    end
    if not SC.BaseWork or not SC.BaseWork.floorDestinations then
        return nil, nil, "floor_sorter_unavailable"
    end
    local rows, category, reason = SC.BaseWork.floorDestinations(actor, item)
    if #rows == 0 then return nil, category, reason end
    local failed = job and job.target and job.target.failedFloorDestinations or nil
    for _, row in ipairs(rows) do
        local storage = row.destination
        local key = storage and (storage.id or storage.zoneId and
            (storage.zoneId .. ":" .. tostring(storage.x) .. ":" .. tostring(storage.y)))
        if not failed or not failed[key] then
            return { kind = "storage", storage = storage,
                container = row.container, key = key }, category
        end
    end
    return nil, category, "floor_storage_unavailable"
end

-- The third value is true only when the whole inventory was read, so a miss
-- proves the item is no longer carried.
local function carried(actor, claim, jobId)
    local root = U().inventory(actor)
    if not root then return nil, nil, false end
    local items, containers = U().inventoryItemsDeep(root, 1024, 16)
    for _, item in ipairs(items) do
        if itemId(item) == claim.itemId and marker(item) == jobId then
            local owner = call(item, "getContainer")
            if owner and U().inventoryContains(owner, item) then
                return item, owner, true
            end
        end
    end
    return nil, nil, #items < 1024 and #(containers or {}) < 16
end

local function releaseClaim(job)
    job.target.floorCargo, job.target.trashZoneId,
        job.target.trashPoint = nil, nil, nil
    job.target.failedFloorDestinations, job.target.floorReturnReason = nil, nil
    job.assignedId = nil
    returning[job.id] = nil
end

local function releaseWorldClaim(job, item)
    if item and marker(item) == job.id then clear(item, job.id) end
    releaseClaim(job)
end

local function putDown(job, item, owner, square)
    if not square then return false, "floor_drop_square_missing" end
    local dropped, wrapper = U().dropItem(owner, square, item)
    if not dropped or U().worldItemPresent(square, wrapper) ~= true
        or U().inventoryContains(owner, item) ~= false then
        return false, dropped and "floor_return_unverified" or wrapper
    end
    if not clear(item, job.id) then return false, "floor_marker_clear_failed" end
    releaseClaim(job)
    return true, "floor_item_returned"
end

-- Carried cargo is put down on its own floor tile when the worker stands on
-- it or beside it, and otherwise on the worker's own tile. dropItem places an
-- item on any tile at any distance; nothing crosses the camp without its
-- carrier.
local function setDown(actor, job, claim, item, owner)
    local ax, ay, az = U().position(actor)
    local square = zoneById(claim.zoneId, "sorting_floor")
        and U().gridSquare(claim.x, claim.y, claim.z) or nil
    local beside = ax ~= nil and square ~= nil
        and math.floor(az or 0) == claim.z
        and math.abs(math.floor(ax) - claim.x) <= 1
        and math.abs(math.floor(ay) - claim.y) <= 1
    return putDown(job, item, owner, beside and square or U().squareOf(actor))
end

local function approach(actor, square, worldItem, action)
    if U().sameSquare(actor, square) and U().isSquareFree(square) then
        return true, "arrived"
    end
    if not SC.Navigation or not SC.Navigation.requestAny then
        return false, "navigation_unavailable"
    end
    local free = U().isSquareFree(square)
    local targets = free and { square }
        or SC.Navigation.interactionTargets(actor, worldItem or square,
            { requireDirectAccess = true })
    if not targets or #targets == 0 then return false, "no_interaction_targets" end
    local moving, reason, reached = SC.Navigation.requestAny(actor, targets, "walk", {
        action = action, targetSquare = square,
        object = worldItem, requireSameSquare = not free,
        arrivalDistance = free and 0.45 or nil,
        workCampOnly = true, workReach = true,
    })
    return moving == true and reason == "arrived"
        and (reached == nil or U().sameSquare(actor, reached)),
        moving == true and reason or reason or "floor_approach_failed", moving == true
end

-- An item with nowhere to go is carried back to its own floor tile and put
-- down there. A worker that cannot get there within half a minute, or whose
-- intake zone is gone, puts it down where it stands instead. The first reason
-- is kept for the job's blocker while the worker walks.
local function carryBack(actor, job, claim, item, owner, why)
    job.target.floorReturnReason = job.target.floorReturnReason or why
    local reason = job.target.floorReturnReason
    returning[job.id] = returning[job.id] or now()
    local square = zoneById(claim.zoneId, "sorting_floor")
        and U().gridSquare(claim.x, claim.y, claim.z) or nil
    if square and now() - returning[job.id] < RETURN_MS then
        local arrived, approachReason, moving = approach(actor, square, nil,
            "return_to_sorting_floor")
        if not arrived and moving then return true, approachReason, false end
    end
    local okay, dropReason = setDown(actor, job, claim, item, owner)
    local zone = okay and zoneById(claim.zoneId, "sorting_floor") or nil
    if zone then rewind(zone) end
    return okay, okay and reason or dropReason, true
end

local function pickupVisual(actor, state, item, wrapper, square)
    local visual = visuals[actor]
    if visual and visual.item == item then
        local status = SC.NativeActions and SC.NativeActions.visualStatus
            and SC.NativeActions.visualStatus(actor, "loot_container") or nil
        if status == "active" and now() - visual.startedAt < 5000 then
            return false, "floor_pickup_animation", false
        end
        if status == "completed" and SC.NativeActions.clearVisual then
            SC.NativeActions.clearVisual(actor)
        end
        visuals[actor] = nil
        return status == "completed" or status == nil,
            status == "completed" and "floor_pickup_ready"
                or status == nil and "floor_pickup_ready"
                or "floor_pickup_animation_failed", status ~= nil and status ~= "completed"
    end
    if SC.Navigation and SC.Navigation.cancel then
        SC.Navigation.cancel(actor, "floor_pickup")
    end
    if SC.NativeActions and SC.NativeActions.stopDirect then
        SC.NativeActions.stopDirect(actor)
    else U().stop(actor) end
    local accepted = U().move(actor, "walk", {
        action = "loot_container", item = item, worldItem = wrapper,
        targetSquare = square, lootPosition = "Low", floorSort = true,
    })
    if accepted ~= true then return false, "floor_pickup_animation_rejected", true end
    visuals[actor] = { item = item, startedAt = now() }
    return false, "floor_pickup_animation", false
end

function Floor.update(actor, baseState, job)
    local zone = type(job.target) == "table"
        and zoneById(job.target.zoneId, "sorting_floor") or nil
    if not zone then return false, "floor_zone_missing", true end
    local claim = job.target.floorCargo
    if claim then
        if job.assignedId and job.assignedId ~= U().idOf(actor) then
            return false, "floor_cargo_other_worker", true
        end
        local item, owner, complete = carried(actor, claim, job.id)
        if not item then
            local square = U().gridSquare(claim.x, claim.y, claim.z)
            if not square then return false, "floor_source_unloaded", true end
            local worldItem, wrapper = worldItemAt(square, claim.itemId, job.id)
            if worldItem and wrapper then
                -- A reload before the verified pickup leaves the exact item
                -- on the floor. Release the claim and select it again.
                releaseWorldClaim(job, worldItem)
                rewind(zone)
                return true, "floor_item_still_on_ground"
            end
            if complete then
                -- Neither carried nor on its tile: the player took it or it
                -- was used up. Nothing is left to deliver, and a claim kept
                -- for it would hold the zone and its job forever.
                releaseClaim(job)
                rewind(zone)
                return true, "floor_cargo_absent"
            end
            return false, "floor_cargo_owner_unknown", true
        end
        local root = U().inventory(actor)
        if owner ~= root then
            local moved, reason = U().transferItemVerified(owner, root, item)
            if not moved then return false, reason or "floor_bag_transfer_failed", true end
            owner = root
        end
        local chosen, category, why = destination(actor, item, job)
        job.target.floorCategory = category
        if not chosen then
            return carryBack(actor, job, claim, item, owner, why)
        end
        if chosen.kind == "trash" then
            job.target.trashZoneId = chosen.zoneId
            local tx, ty, tz = U().position(chosen.square)
            job.target.trashPoint = { x = tx, y = ty, z = tz }
            local arrived, reason, moving = approach(actor, chosen.square, nil,
                "move_to_trash_pile")
            if not arrived then return moving, reason, not moving end
            local dropped, wrapper = U().dropItem(owner, chosen.square, item)
            if not dropped or U().worldItemPresent(chosen.square, wrapper) ~= true
                or U().inventoryContains(owner, item) ~= false then
                return false, dropped and "floor_trash_drop_unverified" or wrapper, true
            end
            if not clear(item, job.id) then return false, "floor_marker_clear_failed", true end
            releaseClaim(job)
            rewind(zone)
            return true, "floor_item_discarded"
        end
        job.target.trashZoneId, job.target.trashPoint = nil, nil
        local moved, reason = SC.BaseWork.depositToStorage(actor, baseState,
            chosen.storage, chosen.container, item)
        if moved and reason == "base_supply_returned" then
            local present = chosen.storage.kind == "log_yard"
                and call(item, "getWorldItem") ~= nil
                or U().inventoryContains(chosen.container, item) == true
            if not present or U().inventoryContains(owner, item) ~= false then
                return false, "floor_deposit_unverified", true
            end
            if not clear(item, job.id) then return false, "floor_marker_clear_failed", true end
            releaseClaim(job)
            rewind(zone)
            return true, "floor_item_stored"
        end
        if not moved then
            job.target.failedFloorDestinations =
                job.target.failedFloorDestinations or {}
            job.target.failedFloorDestinations[chosen.key] = true
            local alternate = destination(actor, item, job)
            if alternate then
                baseState.visualAt = nil
                return true, "floor_destination_changed"
            end
            return carryBack(actor, job, claim, item, owner,
                reason == "destination_full" and "floor_storage_full" or reason)
        end
        return moved == true, reason or "floor_deposit_pending", false
    end

    local selected = baseState.floorCandidate
    if not selected or not selected.item or not selected.worldItem
        or U().worldItemPresent(selected.square, selected.worldItem) ~= true then
        selected = nil
        baseState.floorCandidate = nil
    end
    if not selected then
        local reason
        selected, reason = nextItem(zone, actor)
        if not selected then
            if reason == "floor_scan_pending" then return true, reason end
            if reason ~= "floor_empty" then return false, reason, true end
            return true, "floor_sort_complete", false, true
        end
        baseState.floorCandidate = selected
    end
    local chosen, category, why = destination(actor, selected.item, job)
    job.target.floorCategory = category
    if not chosen then
        baseState.floorCandidate = nil
        deferItem(zone, selected.item, why)
        return true, "floor_item_waiting_storage"
    end
    local root = U().inventory(actor)
    local hasRoom = SC.WorkTransport and SC.WorkTransport.hasRoom
        and SC.WorkTransport.hasRoom(root, actor, selected.item) == true
    if not hasRoom then
        baseState.floorCandidate = nil
        return false, "floor_worker_full", true
    end
    local arrived, reason, moving = approach(actor, selected.square,
        selected.worldItem, "move_to_floor_item")
    if not arrived then return moving, reason, not moving end
    local ready, visualReason, failed = pickupVisual(actor, baseState,
        selected.item, selected.worldItem, selected.square)
    if not ready then return not failed, visualReason, failed end
    local x, y, z = U().position(selected.square)
    if not pointIn(zone, x, y, z) or not itemId(selected.item)
        or U().worldItemPresent(selected.square, selected.worldItem) ~= true then
        baseState.floorCandidate = nil
        return false, "floor_source_changed", true
    end
    local receipt = { zoneId = zone.id, itemId = itemId(selected.item),
        x = x, y = y, z = z }
    job.target.floorCargo = receipt
    job.assignedId = U().idOf(actor)
    if not mark(selected.item, job.id) then
        job.target.floorCargo, job.assignedId = nil, nil
        return false, "floor_item_claim_failed", true
    end
    local taken, takeReason = U().takeWorldItemVerified(selected.worldItem,
        root, selected.item)
    baseState.floorCandidate = nil
    if not taken then
        if U().worldItemPresent(selected.square, selected.worldItem) == true then
            releaseWorldClaim(job, selected.item)
            rewind(zone)
        end
        return false, takeReason or "floor_pickup_unverified", true
    end
    if U().inventoryContains(root, selected.item) ~= true then
        return false, "floor_pickup_unverified", true
    end
    return true, "floor_item_carried"
end

function Floor.cancel(actor, job)
    if not job or type(job.target) ~= "table" or not job.target.floorCargo then
        if actor and visuals[actor] then
            if SC.NativeActions and SC.NativeActions.cancelVisual then
                SC.NativeActions.cancelVisual(actor, "floor_sort_cancelled")
            end
            visuals[actor] = nil
        end
        return true
    end
    local claim = job.target.floorCargo
    local sourceZone = zoneById(claim.zoneId, "sorting_floor")
    local square = U().gridSquare(claim.x, claim.y, claim.z)
    if not actor then
        -- A dormant worker may still come back with the item. One gone for
        -- good took it with it, and refusing here would keep the job, its
        -- zone and the camp itself from ever being cancelled or removed.
        if not workerGone(job.assignedId) then return false, "floor_worker_unavailable" end
        releaseWorldClaim(job, square and worldItemAt(square, claim.itemId, job.id) or nil)
        if sourceZone then rewind(sourceZone) end
        return true, "floor_worker_gone"
    end
    local item, owner, complete = carried(actor, claim, job.id)
    if item then
        local okay, reason = setDown(actor, job, claim, item, owner)
        if okay then
            visuals[actor] = nil
            if sourceZone then rewind(sourceZone) end
        end
        return okay, reason
    end
    local worldItem = square and worldItemAt(square, claim.itemId, job.id)
    if worldItem then
        releaseWorldClaim(job, worldItem)
        if sourceZone then rewind(sourceZone) end
        visuals[actor] = nil
        return true, "floor_item_still_on_ground"
    end
    if complete and square then
        releaseClaim(job)
        if sourceZone then rewind(sourceZone) end
        visuals[actor] = nil
        return true, "floor_cargo_absent"
    end
    return false, "floor_cargo_owner_unknown"
end

function Floor.cancelActor(actor)
    local id = actor and U().idOf(actor)
    local base = SC.BaseLife and SC.BaseLife.active()
    for _, job in ipairs(base and base.jobs or {}) do
        if job.type == "sort_floor" and job.assignedId == id
            and type(job.target) == "table" and job.target.floorCargo then
            local okay, reason = Floor.cancel(actor, job)
            if not okay then return false, reason end
        end
    end
    return true
end

function Floor.zoneInUse(id)
    local base = SC.BaseLife and SC.BaseLife.active()
    for _, job in ipairs(base and base.jobs or {}) do
        if job.type == "sort_floor" and type(job.target) == "table"
            and job.target.floorCargo and not workerGone(job.assignedId)
            and (job.target.zoneId == id or job.target.trashZoneId == id) then
            return true
        end
    end
    return false
end

return Floor
