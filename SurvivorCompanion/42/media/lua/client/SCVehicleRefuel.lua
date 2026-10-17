-- SPDX-License-Identifier: MIT
-- A parked-car chore using the game's gasoline action and an exact, saved can.
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.VehicleRefuel = SC.VehicleRefuel or {}
local Refuel = SC.VehicleRefuel
local Fuel = SC.BaseFuel

local states = setmetatable({}, { __mode = "k" })
local EPSILON = 0.02

local function U() return SC.GameplayUtil end
local function call(object, method, ...)
    if object == nil then return nil end
    local value, okay = U().call(object, method, ...)
    if okay then return value end
    return nil
end
local function amount(object, method)
    return tonumber(call(object, method))
end
local marker, mark, clearMark = Fuel.marker, Fuel.mark, Fuel.clearMark
Refuel.gasAmount = Fuel.gasAmount

local function parked(vehicle)
    if not SC.ExpeditionCar then return nil end
    for _, zone in ipairs(SC.ExpeditionCar.parkingAreas()) do
        if SC.ExpeditionCar.fitsParking(vehicle, zone, {}) == true then
            return zone
        end
    end
    return nil
end

function Refuel.eligible(vehicle, manual, allowFull)
    if not SC.BaseLife or not SC.BaseLife.active() then return false, "base_missing" end
    if SC.TaxiCab and type(SC.TaxiCab.isOwned) == "function"
        and SC.TaxiCab.isOwned(vehicle) then return false, "service_cab_reserved" end
    local id = amount(vehicle, "getSqlId")
    if not id or id < 0 or id % 1 ~= 0
        or not SC.Vehicle or SC.Vehicle.loadedBySqlId(id) ~= vehicle then
        return false, "car_identity_unavailable"
    end
    if SC.Vehicle.isStationary(vehicle) ~= true then
        return false, "car_moving"
    end
    if call(vehicle, "isEngineRunning") ~= false
        or call(vehicle, "isEngineStarted") ~= false
        or call(vehicle, "isStarting") == true then
        return false, "car_engine_on"
    end
    local x, y, z = amount(vehicle, "getX"), amount(vehicle, "getY"),
        amount(vehicle, "getZ")
    if not x or not y or z ~= 0 then return false, "car_out_of_camp_reach" end
    local zone = parked(vehicle)
    if not zone and (manual ~= true or SC.BaseLife.withinWorkReach({
        x = x, y = y, z = z }) ~= true) then
        return false, "car_out_of_camp_reach"
    end
    local part = call(vehicle, "getPartById", "GasTank")
    local current = amount(part, "getContainerContentAmount")
    local capacity = amount(part, "getContainerCapacity")
    if not part or not current or not capacity or capacity <= 0 then
        return false, "car_fuel_tank_missing"
    end
    if not allowFull and current >= capacity - EPSILON then
        return false, "car_tank_full"
    end
    return true, { id = id, zoneId = zone and zone.id or nil,
        part = part, current = current, capacity = capacity,
        x = math.floor(x), y = math.floor(y), z = z }
end

local sourceCan = Fuel.sourceCan

local function openJob(vehicleId)
    local base = SC.BaseLife.active()
    for _, job in ipairs(base and base.jobs or {}) do
        if job.type == "refuel_vehicle" and job.state ~= "completed"
            and job.state ~= "cancelled" and type(job.target) == "table"
            and tonumber(job.target.vehicleId) == vehicleId then return job end
    end
    return nil
end

function Refuel.queue(vehicleId, manual)
    vehicleId = tonumber(vehicleId)
    local vehicle = vehicleId and SC.Vehicle and SC.Vehicle.loadedBySqlId(vehicleId)
    local okay, info = Refuel.eligible(vehicle, manual == true)
    if not okay then return false, info end
    if manual ~= true and info.current / info.capacity >= 0.5 then
        return false, "car_above_auto_refuel_threshold"
    end
    local existing = openJob(vehicleId)
    if existing then
        if manual == true then
            existing.priority = 5
            existing.target.manual = true
            existing.target.x, existing.target.y = info.x, info.y
            if existing.state == "blocked" and existing.target.stage == nil then
                existing.retryAt = 0
            end
            return true, existing
        end
        return false, "car_refuel_already_queued"
    end
    if not sourceCan(nil) then return false, "base_gasoline_missing" end
    return SC.BaseLife.enqueueJob({ type = "refuel_vehicle",
        priority = manual == true and 5 or 2,
        target = { vehicleId = vehicleId, zoneId = info.zoneId,
            manual = manual == true, x = info.x, y = info.y, z = info.z } })
end

function Refuel.audit()
    if not SC.Vehicle or type(SC.Vehicle.loadedVehicles) ~= "function" then
        return false, "vehicle_scan_unavailable"
    end
    for _, vehicle in ipairs(SC.Vehicle.loadedVehicles()) do
        local okay, info = Refuel.eligible(vehicle, false)
        if okay and info.current / info.capacity < 0.5
            and not openJob(info.id) then
            return Refuel.queue(info.id, false)
        end
    end
    return false, "no_parked_car_needs_fuel"
end

local sourceFor, itemFor = Fuel.sourceFor, Fuel.itemFor
local function accessSquares(actor, vehicle, part)
    local area = call(part, "getArea")
    local centre = area and call(vehicle, "getAreaCenter", area) or nil
    local x = tonumber(centre and (call(centre, "getX") or centre.x))
        or amount(vehicle, "getX")
    local y = tonumber(centre and (call(centre, "getY") or centre.y))
        or amount(vehicle, "getY")
    local z = amount(vehicle, "getZ") or 0
    local result = {}
    if not x or not y then return result end
    for radius = 0, 2 do
        for dx = -radius, radius do
            for dy = -radius, radius do
                if math.max(math.abs(dx), math.abs(dy)) == radius then
                    local square = U().gridSquare(math.floor(x) + dx,
                        math.floor(y) + dy, math.floor(z))
                    if square and U().isSquareFree(square)
                        and not U().safehouseBlocker(square, actor)
                        and SC.BaseLife.withinWorkReach(square)
                        -- requestAny can stop 0.15 tiles from the square's
                        -- centre. Every accepted arrival must still be within
                        -- the 1.6-tile fuel interaction radius.
                        and (math.floor(x) + dx + 0.5 - x) ^ 2
                            + (math.floor(y) + dy + 0.5 - y) ^ 2
                            <= 1.45 ^ 2 then
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
function Refuel.atFuelSide(actor, vehicle, part)
    local area = call(part, "getArea")
    local centre = area and call(vehicle, "getAreaCenter", area) or nil
    local x = tonumber(centre and (call(centre, "getX") or centre.x))
        or amount(vehicle, "getX")
    local y = tonumber(centre and (call(centre, "getY") or centre.y))
        or amount(vehicle, "getY")
    local ax, ay, az = U().position(actor)
    local vz = amount(vehicle, "getZ")
    if not x or not y or not ax or not ay or not az or not vz then
        return false, "fuel_side_position_unavailable"
    end
    if math.floor(az) ~= math.floor(vz) then
        return false, "fuel_side_other_floor:"
            .. tostring(az) .. "/" .. tostring(vz)
    end
    local distance = math.sqrt((ax - x) ^ 2 + (ay - y) ^ 2)
    if distance > 1.6 then
        return false, "fuel_side_distance:" .. tostring(distance)
    end
    if SC.BaseLife.withinWorkReach(actor) ~= true then
        return false, "fuel_side_outside_work_reach"
    end
    if U().safehouseBlocker(U().squareOf(actor), actor) then
        return false, "fuel_side_safehouse_blocked"
    end
    return true, "fuel_side_reached"
end

function Refuel.canContinue(actor, vehicle, part, item, jobId)
    local job = SC.BaseLife and SC.BaseLife.job(jobId)
    if not job or job.type ~= "refuel_vehicle"
        or job.reservedBy ~= U().idOf(actor) or marker(item) ~= jobId
        or U().inventoryContains(U().inventory(actor), item) ~= true then
        return false
    end
    local okay, info = Refuel.eligible(vehicle, job.target.manual == true, true)
    return okay == true and info.part == part
        and Refuel.atFuelSide(actor, vehicle, part)
end

local function settleFuel(actor, job, item)
    local target = job.target
    local vehicle = SC.Vehicle and SC.Vehicle.loadedBySqlId(target.vehicleId)
    local part = vehicle and call(vehicle, "getPartById", "GasTank") or nil
    local currentTank = amount(part, "getContainerContentAmount")
    local currentCan = amount(call(item, "getFluidContainer"), "getAmount")
    if not currentTank or not currentCan or not target.tankBefore
        or not target.canBefore then return false, "car_refuel_receipt_unreadable" end
    local gain = currentTank - target.tankBefore
    local loss = target.canBefore - currentCan
    if gain < -EPSILON or loss < -EPSILON or math.abs(gain - loss) > 0.11 then
        return false, "car_refuel_conservation_uncertain"
    end
    if gain <= EPSILON then
        target.refuelAttempts = (tonumber(target.refuelAttempts) or 0) + 1
        if target.refuelAttempts >= 3 then
            return false, "car_refuel_no_effect"
        end
        target.stage, target.tankBefore, target.canBefore = "carrying", nil, nil
        target.stageStartedAt = U().nowMs()
        return true, "car_refuel_retry"
    end
    target.stage, target.tankBefore, target.canBefore = "returning", nil, nil
    target.stageStartedAt = U().nowMs()
    return true, "car_refuel_verified"
end

local function clearCargo(target)
    target.stage, target.sourceStorageId, target.itemId = nil, nil, nil
    target.tankBefore, target.canBefore = nil, nil
    target.refuelAttempts, target.actionStartedAt, target.stageStartedAt = nil, nil, nil
end
local NATIVE_KINDS = { vehicle_refuel = true }
-- Drop a receipt that has nothing left to protect.
local function dropReceipt(target)
    clearCargo(target)
    target.finishReason = nil
end

function Refuel.update(actor, baseState, job)
    local target = job.target
    job.assignedId = job.assignedId or U().idOf(actor)
    local state = states[actor]
    if not state or state.jobId ~= job.id then
        state = { jobId = job.id }
        states[actor] = state
    end
    local item, carried = itemFor(job, actor)
    local stage = target.stage or "selecting"
    target.stageStartedAt = tonumber(target.stageStartedAt) or U().nowMs()
    if stage ~= "refueling" and U().nowMs() - target.stageStartedAt > 90000 then
        -- The job is blocked after this return. Start a fresh approach clock
        -- when it is claimed again, while keeping the exact can and receipt.
        target.stageStartedAt = nil
        return false, "car_refuel_" .. stage .. "_timeout", true
    end
    if stage == "selecting" then
        local storage, container
        if target.sourceStorageId then
            storage, container = sourceFor(job)
            if not item then
                -- The reserved can is gone: the player took it, or it moved.
                -- Choose another rather than retrying for this one forever.
                if Fuel.sourceState(job) == "unloaded" then
                    return false, "base_storage_unloaded", true
                end
                target.sourceStorageId, target.itemId = nil, nil
                return true, "car_refuel_can_reselecting"
            end
        else
            storage, container, item = sourceCan(actor)
            if not item then return true, "car_refuel_fuel_exhausted", false, true end
            if not mark(item, job.id) then return false, "car_refuel_can_reserved", true end
            target.sourceStorageId = storage.id
            target.itemId = call(item, "getID")
        end
        if carried then
            target.stage = "carrying"
            target.stageStartedAt = U().nowMs()
            return true, "car_refuel_can_carried"
        end
        if not storage or not container then return false, "base_storage_unloaded", true end
        local taken, reason = SC.BaseWork.withdrawFromStorage(actor, baseState,
            storage, container, item)
        if U().inventoryContains(U().inventory(actor), item) == true then
            target.stage = "carrying"
            target.stageStartedAt = U().nowMs()
            return true, "car_refuel_can_carried"
        end
        return taken == true, reason or "car_refuel_can_pending",
            taken ~= true and reason ~= "approaching_base_storage"
    end
    if not item then
        if Fuel.sourceState(job) == "unloaded" then
            return false, "base_storage_unloaded", true
        end
        -- Neither the worker nor the loaded storage holds the can any more
        -- (the player took it from the worker). Start over with another.
        local stopped, why = Fuel.stopNative(actor, NATIVE_KINDS, "car_refuel_can_lost")
        if stopped ~= true then return false, why, true end
        dropReceipt(target)
        return true, "car_refuel_can_lost"
    end
    if stage == "refueling" then
        local native = SC.NativeActions
        if native and native.workKind(actor) == "vehicle_refuel" then
            if native.isWorkActive(actor) == true then
                local vehicle = SC.Vehicle.loadedBySqlId(target.vehicleId)
                local okay = Refuel.eligible(vehicle, target.manual == true, true)
                if okay and U().nowMs() - (tonumber(target.actionStartedAt) or 0) < 120000 then
                    return true, "car_refuel_action_active"
                end
                local stopped, reason = native.cancelWork(actor, "car_refuel_interrupted")
                if stopped ~= true then return false, reason, true end
            else
                local finished, reason = native.finishWork(actor)
                if finished ~= true then return false, reason, true end
            end
        end
        local settled, reason = settleFuel(actor, job, item)
        return settled, reason, settled ~= true
    end
    if stage == "carrying" then
        if not carried then return false, "car_refuel_can_not_carried", true end
        local vehicle = SC.Vehicle.loadedBySqlId(target.vehicleId)
        local okay, info = Refuel.eligible(vehicle, target.manual == true)
        if not okay or (target.zoneId and info.zoneId ~= target.zoneId) then
            target.stage = "returning"
            target.stageStartedAt = U().nowMs()
            target.finishReason = okay and "car_parking_area_changed" or info
            return true, "car_refuel_returning_can"
        end
        local gas = Refuel.gasAmount(item)
        if gas <= EPSILON then
            target.stage = "returning"
            target.stageStartedAt = U().nowMs()
            return true, "car_refuel_empty_can"
        end
        local squares = accessSquares(actor, vehicle, info.part)
        if #squares == 0 then return false, "car_fuel_side_unreachable", true end
        if not Refuel.atFuelSide(actor, vehicle, info.part) then
            local moving, reason = SC.Navigation.requestAny(actor, squares, "walk", {
                action = "move_to_car_fuel", vehicle = vehicle,
                targetSquare = squares[1], arrivalDistance = 0.15,
                workCampOnly = true, workReach = true,
            })
            return moving == true, reason or "approaching_car_fuel",
                moving ~= true and reason == "no_route"
        end
        target.tankBefore, target.canBefore = info.current, gas
        target.actionStartedAt, target.stage = U().nowMs(), "refueling"
        target.stageStartedAt = U().nowMs()
        local started, reason = SC.NativeActions.startVehicleRefuel(actor,
            vehicle, info.part, item, job.id)
        if started ~= true then
            target.stage, target.tankBefore, target.canBefore = "carrying", nil, nil
            target.stageStartedAt = U().nowMs()
            return false, reason, true
        end
        return true, "car_refuel_action_started"
    end
    if stage ~= "returning" then return false, "car_refuel_stage_invalid", true end
    local home, storage, container = Fuel.sourceState(job)
    if home == "removed" then
        -- The player unmarked the can's storage. The worker keeps the can,
        -- unreserved, and ordinary camp hauling decides where it goes.
        if not clearMark(item, job.id) then
            return false, "car_refuel_marker_uncertain", true
        end
        dropReceipt(target)
        return true, "car_refuel_source_removed", false, true
    end
    if home ~= "loaded" then return false, "base_storage_unloaded", true end
    if carried then
        local returned, reason = SC.BaseWork.returnToStorage(actor, baseState,
            storage, container, item)
        -- A just-finished gasoline action can make the cosmetic shelf pose
        -- reject even though the worker has reached this exact container.
        -- Preserve the can receipt and commit only the verified identity
        -- transfer at a real use square in that case.
        if returned ~= true and reason == "base_storage_action_rejected"
            and type(U().directInteractionAccess) == "function" then
            local object = SC.BaseLife.resolveObject(storage)
            local atStorage = object and U().directInteractionAccess(actor, object)
            if atStorage == true then
                returned, reason = SC.BaseWork.restoreToStorage(actor,
                    storage, container, item)
            end
        end
        if returned ~= true or U().inventoryContains(container, item) ~= true then
            return returned == true, reason or "car_refuel_return_pending",
                returned ~= true and reason ~= "approaching_base_storage"
        end
    elseif U().inventoryContains(container, item) ~= true then
        return false, "car_refuel_can_owner_uncertain", true
    end
    if not clearMark(item, job.id) then return false, "car_refuel_marker_uncertain", true end
    clearCargo(target)
    local finishReason = target.finishReason
    target.finishReason = nil
    if finishReason then return true, finishReason, false, true end
    local vehicle = SC.Vehicle.loadedBySqlId(target.vehicleId)
    local okay, info = Refuel.eligible(vehicle, target.manual == true)
    if not okay then return true, info, false, true end
    if not sourceCan(actor) then return true, "car_refuel_fuel_exhausted", false, true end
    return true, "car_refuel_next_can"
end

function Refuel.releaseAffinity(actor, job)
    if not job or not job.assignedId then return true end
    if not actor then
        -- A worker who died or was removed can never finish this receipt.
        return Fuel.workerGone(job) and Refuel.cancel(nil, job) == true or false
    end
    local item, carried = itemFor(job, actor)
    if carried or job.target.stage == "refueling" or (SC.NativeActions
        and SC.NativeActions.workKind(actor) == "vehicle_refuel") then
        return false
    end
    if item and marker(item) ~= job.id then return false end
    job.assignedId = nil
    states[actor] = nil
    return true
end

-- Cancelling refuses only while the can may still come back: a dormant
-- worker, an unloaded storage or a native action that will not stop. It never
-- waits on fuel readings; nothing more is poured and the can goes home.
function Refuel.cancel(actor, job)
    if not job then return true end
    local target = job.target
    if not actor then
        if target.stage ~= nil and not Fuel.workerGone(job) then
            return false, "car_refuel_worker_unavailable"
        end
        Fuel.clearStoredMark(job)
        dropReceipt(target)
        job.assignedId = nil
        return true, "car_refuel_receipt_released"
    end
    local item, carried = itemFor(job, actor)
    -- Stop only this job's own pour; the worker may be on a newer chore.
    local owned = states[actor] and states[actor].jobId == job.id
    if owned and SC.NativeActions.workKind(actor) == "vehicle_refuel" then
        local stopped, reason = SC.NativeActions.cancelWork(actor, "car_refuel_cancelled")
        if stopped ~= true then return false, reason end
    end
    local home, storage, container = Fuel.sourceState(job)
    if home == "unloaded" then return false, "base_storage_unloaded" end
    if item then
        if home == "loaded" and carried then
            local returned, reason = SC.BaseWork.restoreToStorage(actor,
                storage, container, item)
            if returned ~= true then return false, reason end
        elseif home == "loaded" and U().inventoryContains(container, item) ~= true then
            return false, "car_refuel_can_owner_uncertain"
        end
        if not clearMark(item, job.id) then return false, "car_refuel_marker_uncertain" end
    end
    dropReceipt(target)
    job.assignedId = nil
    states[actor] = nil
    return true
end

return Refuel
