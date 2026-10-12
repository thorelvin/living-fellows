-- SPDX-License-Identifier: MIT
-- Parked vehicle cargo is a base job. Item identity stays in the native trunk,
-- worker inventory, or marked destination at every step; no virtual cargo.
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.VehicleUnload = SC.VehicleUnload or {}
local Unload = SC.VehicleUnload

local states = setmetatable({}, { __mode = "k" })
local MARKER = "LF_CarUnloadJob"

local function U() return SC.GameplayUtil end
local function call(object, method, ...)
    if object == nil then return nil end
    local value, ok = U().call(object, method, ...)
    return ok and value or nil
end

local function itemMarker(item)
    local data = call(item, "getModData")
    return data and data[MARKER] or nil
end

local function mark(item, jobId)
    local data = call(item, "getModData")
    if not data then return false end
    data[MARKER] = jobId
    return true
end

local function trunkFor(vehicle)
    local part = call(vehicle, "getPartById", "TruckBed")
    local container = part and call(part, "getItemContainer") or nil
    if not container then return nil, nil, "car_trunk_missing" end
    if call(vehicle, "isTrunkLocked") == true then
        return nil, nil, "car_trunk_locked"
    end
    return part, container
end

local function parked(vehicle)
    if not vehicle or not SC.Vehicle or not SC.ExpeditionCar
        or SC.Vehicle.isStationary(vehicle) ~= true then return nil end
    for _, zone in ipairs(SC.ExpeditionCar.parkingAreas()) do
        if SC.ExpeditionCar.fitsParking(vehicle, zone, {}) == true then
            return zone
        end
    end
    return nil
end

function Unload.eligible(vehicle)
    local id = tonumber(call(vehicle, "getSqlId"))
    if not id or id < 0 or id % 1 ~= 0 then
        return false, "car_identity_unavailable"
    end
    local zone = parked(vehicle)
    if not zone then return false, "car_not_parked_at_base" end
    local part, trunk, reason = trunkFor(vehicle)
    if not trunk then return false, reason end
    return true, { id = id, zoneId = zone.id, part = part, trunk = trunk }
end

function Unload.rows()
    local rows = {}
    if not SC.Vehicle or type(SC.Vehicle.loadedVehicles) ~= "function" then return rows end
    for _, vehicle in ipairs(SC.Vehicle.loadedVehicles()) do
        local okay, info = Unload.eligible(vehicle)
        if okay then
            local items = U().inventoryItems(info.trunk, 4096)
            local name = call(vehicle, "getScriptName") or "Car"
            rows[#rows + 1] = {
                id = info.id, zoneId = info.zoneId, name = tostring(name),
                count = #items,
            }
        end
    end
    table.sort(rows, function(a, b) return a.id < b.id end)
    return rows
end

local function openJob(vehicleId)
    local base = SC.BaseLife and SC.BaseLife.active()
    for _, job in ipairs(base and base.jobs or {}) do
        if job.type == "unload_vehicle" and job.state ~= "completed"
            and job.state ~= "cancelled" and type(job.target) == "table"
            and tonumber(job.target.vehicleId) == vehicleId then return job end
    end
    return nil
end

function Unload.queue(vehicleId)
    vehicleId = tonumber(vehicleId)
    if not vehicleId or vehicleId < 0 or vehicleId % 1 ~= 0 then
        return false, "car_identity_unavailable"
    end
    local vehicle = SC.Vehicle and SC.Vehicle.loadedBySqlId(vehicleId)
    local okay, info = Unload.eligible(vehicle)
    if not okay then return false, info end
    if #U().inventoryItems(info.trunk, 4096) == 0 then
        return false, "car_trunk_empty"
    end
    local current = openJob(vehicleId)
    if current then return false, "car_unload_already_queued" end
    return SC.BaseLife.enqueueJob({ type = "unload_vehicle", priority = 3,
        target = { vehicleId = vehicleId, zoneId = info.zoneId,
            x = math.floor(tonumber(call(vehicle, "getX")) or 0),
            y = math.floor(tonumber(call(vehicle, "getY")) or 0), z = 0 } })
end

function Unload.audit()
    for _, row in ipairs(Unload.rows()) do
        if row.count > 0 and not openJob(row.id) then
            return Unload.queue(row.id)
        end
    end
    return false, "no_parked_car_cargo"
end

local function markedCargo(actor, jobId)
    local inventory = U().inventory(actor)
    for _, item in ipairs(U().inventoryItems(inventory, 1024)) do
        if itemMarker(item) == jobId then return item end
    end
    return nil
end

local function trunkSquares(actor, vehicle, part)
    local area = call(part, "getArea")
    local centre = area and call(vehicle, "getAreaCenter", area) or nil
    local x = tonumber(centre and (call(centre, "getX") or centre.x))
        or tonumber(call(vehicle, "getX"))
    local y = tonumber(centre and (call(centre, "getY") or centre.y))
        or tonumber(call(vehicle, "getY"))
    local z = tonumber(call(vehicle, "getZ")) or 0
    if not x or not y then return {} end
    local result = {}
    for radius = 0, 2 do
        for dx = -radius, radius do
            for dy = -radius, radius do
                if math.max(math.abs(dx), math.abs(dy)) == radius then
                    local square = U().gridSquare(math.floor(x) + dx,
                        math.floor(y) + dy, math.floor(z))
                    if square and U().isSquareFree(square)
                        and not U().safehouseBlocker(square, actor) then
                        result[#result + 1] = square
                    end
                end
            end
        end
    end
    table.sort(result, function(a, b)
        return U().distanceSq(actor, a) < U().distanceSq(actor, b)
    end)
    return result
end

local function atAnySquare(actor, squares)
    for _, square in ipairs(squares) do
        if U().sameSquare(actor, square) then return true end
    end
    return false
end

local function visualStatus(actor)
    if not SC.NativeActions or type(SC.NativeActions.visualStatus) ~= "function" then
        return nil
    end
    return SC.NativeActions.visualStatus(actor, "loot_container")
end

local function clearVisual(actor)
    if SC.NativeActions and type(SC.NativeActions.clearVisual) == "function" then
        SC.NativeActions.clearVisual(actor)
    end
end

local function visualToken(actor)
    if SC.NativeActions and type(SC.NativeActions.visualToken) == "function" then
        return SC.NativeActions.visualToken(actor, "loot_container")
    end
    return nil
end

local function cancelOwnedVisual(actor, state)
    local token = state.trunkVisualToken or state.storageVisualToken
    if not token then
        if (state.phase == "taking" or state.visualAt ~= nil)
            and visualStatus(actor) == "active" then
            return false, "car_unload_visual_ownership_unknown"
        end
        return true
    end
    if not SC.NativeActions
        or type(SC.NativeActions.cancelVisualOwned) ~= "function" then
        return false, "car_unload_visual_ownership_unknown"
    end
    return SC.NativeActions.cancelVisualOwned(actor, token,
        "car_unload_cancelled")
end

function Unload.update(actor, baseState, job)
    local target = type(job.target) == "table" and job.target or {}
    local vehicle = SC.Vehicle and SC.Vehicle.loadedBySqlId(target.vehicleId)
    local eligible, info = Unload.eligible(vehicle)
    job.assignedId = job.assignedId or U().idOf(actor)
    local state = states[actor]
    if not state or state.jobId ~= job.id then
        state = { jobId = job.id, phase = "select" }
        states[actor] = state
    end
    local item = markedCargo(actor, job.id)
    if item then
        local storage, container, why = SC.BaseWork.destinationForCarItem(actor, item)
        if not storage then
            if not eligible then return false, info, true end
            local returned, reason = SC.WorkTransport.transferVerified(
                U().inventory(actor), info.trunk, item, actor)
            if not returned then return false, reason or why, true end
            mark(item, nil)
            state.phase, state.item = "select", nil
            return false, why, true
        end
        if state.visualAt ~= nil and state.storageVisualToken ~= nil
            and visualToken(actor) ~= state.storageVisualToken then
            return false, "car_storage_visual_changed", true
        end
        local moved, reason = SC.BaseWork.depositToStorage(
            actor, state, storage, container, item)
        if moved == true and reason == "base_supply_returned" then
            if U().inventoryContains(container, item) ~= true
                or U().inventoryContains(U().inventory(actor), item) ~= false
                or call(item, "getContainer") ~= container then
                return false, "car_delivery_unverified", true
            end
            mark(item, nil)
            state.phase, state.item, state.visualAt = "select", nil, nil
            state.storageVisualToken = nil
            return true, "car_item_stored"
        end
        if moved == true and reason == "base_storage_looting" then
            state.storageVisualToken = visualToken(actor)
        end
        -- Accepted navigation and an active loot pose are progress, not a
        -- verified deposit. Keep their lease and exact recovery marker.
        return moved == true, reason or "car_item_delivery_pending"
    end
    if not eligible then return false, info, true end
    if info.zoneId ~= target.zoneId then
        return false, "car_parking_area_changed", true
    end
    if state.phase == "taking" then
        if state.trunkVisualToken ~= nil
            and visualToken(actor) ~= state.trunkVisualToken then
            return false, "car_trunk_visual_changed", true
        end
        local status = visualStatus(actor)
        if status == "active" then return true, "car_trunk_looting" end
        if status ~= "completed" then
            state.phase, state.item, state.trunkVisualToken = "select", nil, nil
            return false, "car_unload_visual_" .. tostring(status), true
        end
        clearVisual(actor)
        item = state.item
        state.phase, state.item, state.trunkVisualToken = "select", nil, nil
        if not item or not U().inventoryContains(info.trunk, item) then
            return false, "car_trunk_item_changed", true
        end
        if not mark(item, job.id) then return false, "car_item_marker_unavailable", true end
        local taken, reason = SC.WorkTransport.transferVerified(
            info.trunk, U().inventory(actor), item, actor)
        if not taken then mark(item, nil) return false, reason, true end
        return true, "car_item_carried"
    end
    item = nil
    local trunkItems = U().inventoryItems(info.trunk, 4096)
    local storageFound, capacityBlocked = false, false
    for _, candidate in ipairs(trunkItems) do
        local storage = SC.BaseWork.destinationForCarItem(actor, candidate)
        if storage and (itemMarker(candidate) == nil
            or itemMarker(candidate) == job.id) then
            storageFound = true
            local room = SC.WorkTransport
                and type(SC.WorkTransport.hasRoom) == "function"
                and SC.WorkTransport.hasRoom(U().inventory(actor), actor, candidate)
            if room == true then
                item = candidate
                break
            end
            capacityBlocked = true
        end
    end
    if not item then
        if #trunkItems == 0 then
            states[actor] = nil
            return true, "car_trunk_unloaded", false, true
        end
        if storageFound and capacityBlocked then
            return false, "car_unload_worker_capacity", true
        end
        return false, "car_unload_storage_full_or_missing", true
    end
    local squares = trunkSquares(actor, vehicle, info.part)
    if #squares == 0 then return false, "car_trunk_unreachable", true end
    if not atAnySquare(actor, squares) then
        local moving, reason = SC.Navigation.requestAny(actor, squares, "walk", {
            action = "move_to_car_trunk", vehicle = vehicle,
            targetSquare = squares[1], arrivalDistance = 0.35,
            requireSameSquare = true, workCampOnly = true, workReach = true,
        })
        return moving == true, reason or "approaching_car_trunk",
            moving ~= true and reason == "no_route"
    end
    local accepted, reason = U().move(actor, "walk", {
        action = "loot_container", container = info.trunk, item = item,
        baseStorage = true,
    })
    if accepted ~= true then return false, reason or "car_trunk_action_rejected", true end
    local status = visualStatus(actor)
    if status ~= "active" and status ~= "completed" then
        return false, "car_unload_visual_" .. tostring(status), true
    end
    state.phase, state.item = "taking", item
    state.trunkVisualToken = visualToken(actor)
    return true, "car_trunk_looting"
end

-- A blocked job may choose another worker only when its first worker holds
-- neither marked cargo nor an unclaimed native loot action for this job.
function Unload.releaseAffinity(actor, job)
    if not actor or not job then return false end
    if markedCargo(actor, job.id) then return false end
    local state = states[actor]
    if state and state.jobId == job.id then
        if state.phase == "taking" then return false end
        local token = state.storageVisualToken or state.trunkVisualToken
        if token and visualToken(actor) == token then return false end
        states[actor] = nil
    end
    if job.assignedId == U().idOf(actor) then job.assignedId = nil end
    return true
end

function Unload.cancel(actor, job)
    if not job then return true end
    if not actor then
        return job.assignedId == nil, "car_unload_worker_unavailable"
    end
    local state = states[actor]
    local ownedState = state and state.jobId == job.id and state or nil
    if ownedState then
        local cancelled, cancelReason = cancelOwnedVisual(actor, ownedState)
        if cancelled ~= true then return false, cancelReason end
    end
    local item = markedCargo(actor, job.id)
    if item then
        local car = SC.Vehicle and SC.Vehicle.loadedBySqlId(job.target.vehicleId)
        local okay, info = Unload.eligible(car)
        if not okay then return false, info end
        local restored, reason = SC.WorkTransport.transferVerified(
            U().inventory(actor), info.trunk, item, actor)
        if not restored then return false, reason end
        mark(item, nil)
    end
    if ownedState then states[actor] = nil end
    if job.assignedId == U().idOf(actor) then job.assignedId = nil end
    return true
end

return Unload
