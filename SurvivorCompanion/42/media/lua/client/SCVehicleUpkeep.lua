-- SPDX-License-Identifier: MIT
-- Low-priority parked-car washing and tire inflation using stock timed actions.
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.VehicleUpkeep = SC.VehicleUpkeep or {}
local Upkeep = SC.VehicleUpkeep

local MARKER = "LF_UpkeepJobId"
local EPSILON = 0.01
local KINDS = { inflate_tires = true, wash_vehicle = true }
local WASH_AREAS = {
    { id = "Front", area = "Engine" },
    { id = "Rear", area = "TruckBed" },
    { id = "Left", area = "SeatLeft" },
    { id = "Left", area = "SeatFrontLeft" },
    { id = "Right", area = "SeatRight" },
    { id = "Right", area = "SeatFrontRight" },
}
local states = setmetatable({}, { __mode = "k" })

local function U() return SC.GameplayUtil end
local function call(object, method, ...)
    if object == nil then return nil end
    local result, okay = U().call(object, method, ...)
    if okay then return result end
    return nil
end
local function number(object, method, ...)
    return tonumber(call(object, method, ...))
end
local function marker(item)
    local data = item and U().modData(item)
    return type(data) == "table" and data[MARKER] or nil
end
local function mark(item, id)
    local data = item and U().modData(item)
    if type(data) ~= "table" or data[MARKER] ~= nil then return false end
    data[MARKER] = id
    return data[MARKER] == id
end
local function clearMark(item, id)
    local data = item and U().modData(item)
    if type(data) ~= "table" or data[MARKER] ~= id then return false end
    data[MARKER] = nil
    return data[MARKER] == nil
end
local function water(item)
    local fluid = call(item, "getFluidContainer")
    local amount = number(fluid, "getAmount") or 0
    if amount < 1 then return 0, false end
    local tainted = type(Fluid) == "table" and Fluid.TaintedWater
        and call(fluid, "contains", Fluid.TaintedWater) == true
    local clean = type(Fluid) == "table" and Fluid.Water
        and call(fluid, "contains", Fluid.Water) == true
    return (tainted or clean) and amount or 0, tainted == true
end
local function supply(kind, actor)
    local best, score
    for _, storage in ipairs(SC.BaseLife.storageRows(nil, true)) do
        local container = SC.BaseLife.resolveContainer(storage)
        if container then
            local protectedByType, available = {}, {}
            local items = U().inventoryItems(container, math.huge)
            for _, item in ipairs(items) do
                local itemType = U().itemType(item)
                if itemType and (marker(item) ~= nil or (SC.WorkTransport
                    and SC.WorkTransport.foreignProtected
                    and SC.WorkTransport.foreignProtected(item, actor) == true)) then
                    protectedByType[itemType] = (protectedByType[itemType] or 0) + 1
                end
            end
            for _, item in ipairs(items) do
                local itemType = U().itemType(item)
                if itemType and marker(item) == nil
                    and not (SC.WorkTransport and SC.WorkTransport.foreignProtected
                        and SC.WorkTransport.foreignProtected(item, actor) == true) then
                    if available[itemType] == nil then
                        available[itemType] = math.max(0,
                            SC.BaseLife.availableCountExact(storage, itemType)
                            - (protectedByType[itemType] or 0))
                    end
                    local quantity, tainted = water(item)
                    local usable = kind == "inflate_tires"
                        and itemType == "Base.TirePump"
                        or kind == "wash_vehicle" and quantity >= 1
                    if usable and available[itemType] > 0 then
                        local rank = kind == "wash_vehicle"
                            and (tainted and 0 or 100000) or 0
                        local distance = actor and U().distanceSq(actor,
                            SC.BaseLife.resolveObject(storage)) or 0
                        rank = rank + (tonumber(distance) or 0)
                        if not best or rank < score then
                            best, score = { storage, container, item }, rank
                        end
                    end
                end
            end
        end
    end
    if best then return best[1], best[2], best[3] end
    return nil
end
local function itemFor(job, actor)
    local target = job.target
    local function matches(item)
        return marker(item) == job.id and (target.itemId == nil
            or tostring(call(item, "getID")) == tostring(target.itemId))
    end
    for _, item in ipairs(U().inventoryItems(U().inventory(actor), 1024)) do
        if matches(item) then return item, true end
    end
    local storage = target.sourceStorageId and SC.BaseLife.storage(target.sourceStorageId)
    local container = storage and SC.BaseLife.resolveContainer(storage)
    for _, item in ipairs(U().inventoryItems(container, 4096)) do
        if matches(item) then return item, false end
    end
    return nil
end
local function parked(vehicle)
    if not SC.ExpeditionCar then return nil end
    for _, zone in ipairs(SC.ExpeditionCar.parkingAreas()) do
        if SC.ExpeditionCar.fitsParking(vehicle, zone, {}) == true then
            return zone
        end
    end
    return nil
end
local function vehicleInfo(vehicle, manual)
    if not SC.BaseLife or not SC.BaseLife.active() then return nil, "base_missing" end
    if SC.TaxiCab and SC.TaxiCab.isOwned and SC.TaxiCab.isOwned(vehicle) then
        return nil, "service_cab_reserved"
    end
    local id = number(vehicle, "getSqlId")
    if not id or id < 0 or id % 1 ~= 0 or not SC.Vehicle
        or SC.Vehicle.loadedBySqlId(id) ~= vehicle then
        return nil, "car_identity_unavailable"
    end
    if SC.Vehicle.isStationary(vehicle) ~= true then return nil, "car_moving" end
    if call(vehicle, "isEngineRunning") ~= false
        or call(vehicle, "isEngineStarted") ~= false
        or call(vehicle, "isStarting") == true then return nil, "car_engine_on" end
    local seats = number(vehicle, "getMaxPassengers") or 0
    for seat = 0, math.min(seats, 32) - 1 do
        if call(vehicle, "getCharacter", seat) ~= nil then
            return nil, "car_occupied"
        end
    end
    local x, y, z = number(vehicle, "getX"), number(vehicle, "getY"),
        number(vehicle, "getZ")
    if not x or not y or z ~= 0 then return nil, "car_out_of_camp_reach" end
    local zone = parked(vehicle)
    if not zone and (manual ~= true or SC.BaseLife.withinWorkReach({
        x = x, y = y, z = z }) ~= true) then
        return nil, "car_out_of_camp_reach"
    end
    return { id = id, zoneId = zone and zone.id or nil,
        x = math.floor(x), y = math.floor(y), z = z }
end
local function nextTire(vehicle, manual)
    local count = number(vehicle, "getPartCount") or 0
    for index = 0, math.min(count, 64) - 1 do
        local part = call(vehicle, "getPartByIndex", index)
        if part and call(part, "getContainerContentType") == "Air"
            and call(part, "getInventoryItem") ~= nil then
            local current, capacity = number(part, "getContainerContentAmount"),
                number(part, "getContainerCapacity")
            if current and capacity and capacity > 0
                and current < capacity * (manual and 1 or 0.8) - EPSILON then
                return { part = part, partId = call(part, "getId"),
                    area = call(part, "getArea"), current = current,
                    capacity = capacity }
            end
        end
    end
    return nil
end
local function nextWash(vehicle, manual)
    local script = call(vehicle, "getScript")
    for _, row in ipairs(WASH_AREAS) do
        local intensity = number(vehicle, "getBloodIntensity", row.id)
        if script and call(script, "getAreaById", row.area) ~= nil
            and intensity and intensity >= (manual and EPSILON or 0.1) then
            return { area = row.area, areaId = row.id,
                current = intensity }
        end
    end
    return nil
end
local function nextNeed(kind, vehicle, manual)
    if kind == "inflate_tires" then return nextTire(vehicle, manual) end
    return nextWash(vehicle, manual)
end
function Upkeep.eligible(kind, vehicle, manual, allowSatisfied)
    if not KINDS[kind] then return false, "upkeep_kind_invalid" end
    local info, reason = vehicleInfo(vehicle, manual)
    if not info then return false, reason end
    local need = nextNeed(kind, vehicle, manual)
    if not need and not allowSatisfied then
        return false, kind == "inflate_tires" and "tires_at_rated_pressure"
            or "car_clean"
    end
    return true, info, need
end
local function openJob(kind, id)
    local base = SC.BaseLife.active()
    for _, job in ipairs(base and base.jobs or {}) do
        if job.type == kind and job.state ~= "completed"
            and job.state ~= "cancelled" and type(job.target) == "table"
            and tonumber(job.target.vehicleId) == id then return job end
    end
    return nil
end
function Upkeep.queue(kind, vehicleId, manual)
    vehicleId = tonumber(vehicleId)
    local vehicle = vehicleId and SC.Vehicle and SC.Vehicle.loadedBySqlId(vehicleId)
    local okay, info = Upkeep.eligible(kind, vehicle, manual == true)
    if not okay then return false, info end
    local existing = openJob(kind, vehicleId)
    if existing then
        if manual == true then
            existing.priority, existing.target.manual = 5, true
            if existing.state == "blocked" and existing.target.stage == nil then
                existing.retryAt = 0
            end
            return true, existing
        end
        return false, "upkeep_already_queued"
    end
    if not supply(kind) then
        return false, kind == "inflate_tires" and "base_tire_pump_missing"
            or "base_wash_water_missing"
    end
    return SC.BaseLife.enqueueJob({ type = kind,
        priority = manual == true and 5 or 2,
        target = { vehicleId = vehicleId, zoneId = info.zoneId,
            x = info.x, y = info.y, z = info.z, manual = manual == true } })
end
function Upkeep.audit()
    if not SC.Vehicle or not SC.Vehicle.loadedVehicles then
        return false, "vehicle_scan_unavailable"
    end
    for _, vehicle in ipairs(SC.Vehicle.loadedVehicles()) do
        for _, kind in ipairs({ "inflate_tires", "wash_vehicle" }) do
            local okay, info = Upkeep.eligible(kind, vehicle, false)
            if okay and not openJob(kind, info.id) then
                local queued, result = Upkeep.queue(kind, info.id, false)
                if queued then return true, result end
            end
        end
    end
    return false, "no_parked_car_needs_upkeep"
end
local function areaSquares(actor, vehicle, area, tire)
    local center = call(vehicle, "getAreaCenter", area)
    local x = tonumber(center and (call(center, "getX") or center.x))
    local y = tonumber(center and (call(center, "getY") or center.y))
    local z = number(vehicle, "getZ") or 0
    local result = {}
    if not x or not y then return result end
    local point = Vector3f and Vector3f.new and Vector3f.new() or nil
    local limit = tire and 2.05 or 2.45
    for radius = 0, 3 do
        for dx = -radius, radius do
            for dy = -radius, radius do
                if math.max(math.abs(dx), math.abs(dy)) == radius then
                    local square = U().gridSquare(math.floor(x) + dx,
                        math.floor(y) + dy, math.floor(z))
                    local sx, sy = math.floor(x) + dx, math.floor(y) + dy
                    local inArea = true
                    if not tire and point then
                        call(point, "set", sx + 0.5, sy + 0.5, z)
                        inArea = call(vehicle, "isInArea", area, point) == true
                    end
                    if square and U().isSquareFree(square) and inArea
                        and call(square, "getVehicleContainer") ~= vehicle
                        and not U().safehouseBlocker(square, actor)
                        and SC.BaseLife.withinWorkReach(square)
                        and (sx + 0.5 - x) ^ 2 + (sy + 0.5 - y) ^ 2
                            <= limit ^ 2 then
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
local function atServiceArea(actor, vehicle, area, tire)
    if not tire then return call(vehicle, "isInArea", area, actor) == true end
    -- Build 42's stock tire action does not use isInArea: some tire areas
    -- report false even while the mechanic stands beside the wheel.
    local center = call(vehicle, "getAreaCenter", area)
    local x = tonumber(center and (call(center, "getX") or center.x))
    local y = tonumber(center and (call(center, "getY") or center.y))
    local ax, ay = number(actor, "getX"), number(actor, "getY")
    return x and y and ax and ay and (ax - x) ^ 2 + (ay - y) ^ 2 <= 2.25 ^ 2
        or false
end
function Upkeep.canContinue(actor, vehicle, item, jobId, area, part)
    local job = SC.BaseLife and SC.BaseLife.job(jobId)
    if not job or not KINDS[job.type] or job.reservedBy ~= U().idOf(actor)
        or marker(item) ~= jobId
        or U().inventoryContains(U().inventory(actor), item) ~= true then return false end
    local okay, info = Upkeep.eligible(job.type, vehicle,
        job.target.manual == true, true)
    if not okay or (job.target.zoneId and info.zoneId ~= job.target.zoneId)
        or SC.BaseLife.withinWorkReach(actor) ~= true
        or not atServiceArea(actor, vehicle, area, part ~= nil) then return false end
    if part then
        return call(vehicle, "getPartById", call(part, "getId")) == part
            and call(part, "getInventoryItem") ~= nil
    end
    return water(item) >= 1
end
function Upkeep.canApproach(actor, vehicle, jobId)
    local job = SC.BaseLife and SC.BaseLife.job(jobId)
    if not job or job.type ~= "wash_vehicle"
        or job.reservedBy ~= U().idOf(actor) then return false end
    local okay, info = Upkeep.eligible(job.type, vehicle,
        job.target.manual == true, true)
    return okay == true
        and (not job.target.zoneId or info.zoneId == job.target.zoneId)
        and SC.BaseLife.withinWorkReach(actor) == true
end
local function clearTarget(target)
    target.stage, target.sourceStorageId, target.itemId = nil, nil, nil
    target.partId, target.areaId, target.area = nil, nil, nil
    target.before, target.waterBefore = nil, nil
    target.actionStartedAt, target.stageStartedAt = nil, nil
    target.attempts = nil
end
local function settle(job, item, vehicle)
    local target = job.target
    if not vehicle or target.before == nil then return false, "upkeep_receipt_unreadable" end
    local after, used
    if job.type == "inflate_tires" then
        local part = call(vehicle, "getPartById", target.partId)
        after = number(part, "getContainerContentAmount")
        if not after or after < target.before - EPSILON then
            return false, "tire_pressure_uncertain"
        end
    else
        after = number(vehicle, "getBloodIntensity", target.areaId)
        local remaining = number(call(item, "getFluidContainer"), "getAmount")
        if not after or not remaining or target.waterBefore == nil then
            return false, "wash_receipt_unreadable"
        end
        used = target.waterBefore - remaining
        local removed = target.before - after
        if used < -EPSILON or removed < -EPSILON
            or removed > used * 0.05 + 0.02 then
            return false, "wash_consumption_uncertain"
        end
    end
    local changed = job.type == "inflate_tires"
        and after > target.before + EPSILON
        or job.type == "wash_vehicle" and after < target.before - EPSILON
    if not changed then
        target.attempts = (tonumber(target.attempts) or 0) + 1
        if target.attempts >= 3 then return false, "upkeep_no_effect" end
    else
        target.attempts = 0
    end
    target.before, target.waterBefore = nil, nil
    target.stage, target.stageStartedAt = "carrying", U().nowMs()
    return true, changed and "upkeep_progress_verified" or "upkeep_retry"
end
function Upkeep.update(actor, baseState, job)
    if not job or not KINDS[job.type] then return false, "upkeep_job_invalid", true end
    local target = job.target
    job.assignedId = job.assignedId or U().idOf(actor)
    states[actor] = job.id
    local item, carried = itemFor(job, actor)
    local stage = target.stage or "selecting"
    target.stageStartedAt = tonumber(target.stageStartedAt) or U().nowMs()
    if stage ~= "working" and U().nowMs() - target.stageStartedAt > 90000 then
        target.stageStartedAt = nil
        return false, "upkeep_" .. stage .. "_timeout", true
    end
    if stage == "selecting" then
        local storage, container
        if target.sourceStorageId then
            storage = SC.BaseLife.storage(target.sourceStorageId)
            container = storage and SC.BaseLife.resolveContainer(storage)
            if not item then return false, "upkeep_supply_missing", true end
        else
            storage, container, item = supply(job.type, actor)
            if not item then return true, "upkeep_supply_exhausted", false, true end
            if not mark(item, job.id) then return false, "upkeep_supply_reserved", true end
            target.sourceStorageId, target.itemId = storage.id, call(item, "getID")
        end
        if carried then
            target.stage, target.stageStartedAt = "carrying", U().nowMs()
            return true, "upkeep_supply_carried"
        end
        if not storage or not container then return false, "base_storage_unloaded", true end
        local taken, reason = SC.BaseWork.withdrawFromStorage(actor, baseState,
            storage, container, item)
        if U().inventoryContains(U().inventory(actor), item) == true then
            target.stage, target.stageStartedAt = "carrying", U().nowMs()
            return true, "upkeep_supply_carried"
        end
        if reason == "base_storage_action_rejected" then
            -- A completed native action can still own the movement slot for
            -- one pulse. Retry this exact reserved item before blocking.
            return true, "upkeep_storage_busy"
        end
        return taken == true, reason or "upkeep_supply_pending",
            taken ~= true and reason ~= "approaching_base_storage"
    end
    if not item then return false, "upkeep_supply_missing", true end
    local vehicle = SC.Vehicle and SC.Vehicle.loadedBySqlId(target.vehicleId)
    if stage == "working" then
        local native = SC.NativeActions
        local kind = job.type == "inflate_tires" and "inflate_tires"
            or "wash_vehicle"
        if native and native.workKind(actor) == kind then
            if native.isWorkActive(actor) == true then
                local okay = Upkeep.eligible(job.type, vehicle,
                    target.manual == true, true)
                if okay and U().nowMs() - (tonumber(target.actionStartedAt) or 0)
                    < 120000 then return true, "upkeep_action_active" end
                local stopped, reason = native.cancelWork(actor, "upkeep_interrupted")
                if stopped ~= true then return false, reason, true end
            else
                local finished, reason = native.finishWork(actor)
                if finished ~= true then return false, reason, true end
            end
        end
        local okay, reason = settle(job, item, vehicle)
        return okay, reason, okay ~= true
    end
    if stage == "carrying" then
        if not carried then return false, "upkeep_supply_not_carried", true end
        local okay, info, need = Upkeep.eligible(job.type, vehicle,
            target.manual == true, true)
        if not okay or (target.zoneId and info.zoneId ~= target.zoneId)
            or not need or (job.type == "wash_vehicle" and water(item) < 1) then
            target.stage, target.stageStartedAt = "returning", U().nowMs()
            target.finishReason = not okay and info or not need and "upkeep_complete"
                or "wash_water_exhausted"
            return true, "upkeep_returning_supply"
        end
        if job.type == "wash_vehicle"
            and not atServiceArea(actor, vehicle, need.area, false) then
            local native = SC.NativeActions
            if native.workKind(actor) == "vehicle_area_approach" then
                if native.isWorkActive(actor) then
                    return true, "upkeep_approach_active"
                end
                local finished, finishReason = native.finishWork(actor)
                if finished ~= true then return false, finishReason, true end
                if not atServiceArea(actor, vehicle, need.area, false) then
                    return false, "car_service_side_unreachable", true
                end
                -- The path action can release its tracked slot before the
                -- native queue removes its completed entry. Start washing on
                -- a later pulse, after the queue has advanced.
                return true, "upkeep_approach_finished"
            else
                SC.Navigation.cancel(actor, "upkeep_native_vehicle_area")
                local started, approachReason = native.startVehicleAreaApproach(
                    actor, vehicle, need.area, job.id)
                return started == true,
                    approachReason or "upkeep_approaching_car",
                    started ~= true
            end
        end
        if not atServiceArea(actor, vehicle, need.area,
            job.type == "inflate_tires") then
            local squares = areaSquares(actor, vehicle, need.area,
                job.type == "inflate_tires")
            if #squares == 0 then
                return false, "car_service_side_unreachable", true
            end
            local moving, reason = SC.Navigation.requestAny(actor, squares, "walk", {
                action = "move_to_car_service", vehicle = vehicle,
                targetSquare = squares[1], arrivalDistance = 0.15,
                workCampOnly = true, workReach = true,
            })
            return moving == true, reason or "approaching_car_service",
                moving ~= true and (reason == "no_route"
                    or reason == "no_reachable_interaction_target"
                    or reason == "no_interaction_targets")
        end
        target.partId, target.areaId, target.area = need.partId,
            need.areaId, need.area
        target.before = need.current
        target.waterBefore = job.type == "wash_vehicle"
            and number(call(item, "getFluidContainer"), "getAmount") or nil
        target.stage, target.stageStartedAt = "working", U().nowMs()
        target.actionStartedAt = U().nowMs()
        local started, reason
        if job.type == "inflate_tires" then
            started, reason = SC.NativeActions.startTireInflation(actor, vehicle,
                need.part, item, job.id, need.capacity)
        else
            started, reason = SC.NativeActions.startVehicleWash(actor, vehicle,
                need.areaId, need.area, item, job.id)
        end
        if started ~= true then
            target.stage, target.before, target.waterBefore = "carrying", nil, nil
            if reason == "actor already has a native timed action" then
                return true, "upkeep_native_queue_busy"
            end
            return false, reason or "upkeep_action_rejected", true
        end
        return true, "upkeep_action_started"
    end
    if stage ~= "returning" then return false, "upkeep_stage_invalid", true end
    local storage = target.sourceStorageId and SC.BaseLife.storage(target.sourceStorageId)
    local container = storage and SC.BaseLife.resolveContainer(storage)
    if not storage or not container then return false, "base_storage_unloaded", true end
    if carried then
        local returned, reason = SC.BaseWork.returnToStorage(actor, baseState,
            storage, container, item)
        if returned ~= true and reason == "base_storage_action_rejected"
            and U().directInteractionAccess then
            local object = SC.BaseLife.resolveObject(storage)
            if object and U().directInteractionAccess(actor, object) == true then
                returned, reason = SC.BaseWork.restoreToStorage(actor,
                    storage, container, item)
            end
        end
        if returned ~= true or U().inventoryContains(container, item) ~= true then
            return returned == true, reason or "upkeep_return_pending",
                returned ~= true and reason ~= "approaching_base_storage"
        end
    elseif U().inventoryContains(container, item) ~= true then
        return false, "upkeep_supply_owner_uncertain", true
    end
    if not clearMark(item, job.id) then return false, "upkeep_marker_uncertain", true end
    local finishReason = target.finishReason
    target.finishReason = nil
    clearTarget(target)
    if finishReason == "wash_water_exhausted" and supply(job.type, actor) then
        return true, "upkeep_next_water_container"
    end
    return true, finishReason or "upkeep_complete", false, true
end
function Upkeep.releaseAffinity(actor, job)
    if not job or not job.assignedId then return true end
    if not actor then return false end
    local item, carried = itemFor(job, actor)
    if carried or job.target.stage == "working" or (SC.NativeActions
        and (SC.NativeActions.workKind(actor) == "wash_vehicle"
            or SC.NativeActions.workKind(actor) == "inflate_tires"
            or SC.NativeActions.workKind(actor) == "vehicle_area_approach")) then
        return false
    end
    if item and marker(item) ~= job.id then return false end
    job.assignedId, states[actor] = nil, nil
    return true
end
function Upkeep.cancel(actor, job)
    if not job then return true end
    if not actor then
        return job.target.stage == nil, job.target.stage == nil
            and "upkeep_not_started" or "upkeep_worker_unavailable"
    end
    local item, carried = itemFor(job, actor)
    if SC.NativeActions.workKind(actor) == "vehicle_area_approach" then
        local stopped, reason = SC.NativeActions.cancelWork(actor,
            "upkeep_cancelled")
        if stopped ~= true then return false, reason end
    end
    if job.target.stage == "working" then
        local kind = job.type == "inflate_tires" and "inflate_tires"
            or "wash_vehicle"
        if SC.NativeActions.workKind(actor) == kind then
            local stopped, reason = SC.NativeActions.cancelWork(actor,
                "upkeep_cancelled")
            if stopped ~= true then return false, reason end
        end
        if not item then return false, "upkeep_supply_missing" end
        local vehicle = SC.Vehicle and SC.Vehicle.loadedBySqlId(job.target.vehicleId)
        local settled, reason = settle(job, item, vehicle)
        if not settled then return false, reason end
    end
    if item then
        local storage = job.target.sourceStorageId
            and SC.BaseLife.storage(job.target.sourceStorageId)
        local container = storage and SC.BaseLife.resolveContainer(storage)
        if not container then return false, "base_storage_unloaded" end
        if carried then
            local returned, reason = SC.BaseWork.restoreToStorage(actor,
                storage, container, item)
            if returned ~= true then return false, reason end
        elseif U().inventoryContains(container, item) ~= true then
            return false, "upkeep_supply_owner_uncertain"
        end
        if not clearMark(item, job.id) then return false, "upkeep_marker_uncertain" end
    elseif job.target.sourceStorageId then
        return false, "upkeep_supply_missing"
    end
    clearTarget(job.target)
    job.assignedId, states[actor] = nil, nil
    return true
end
return Upkeep
