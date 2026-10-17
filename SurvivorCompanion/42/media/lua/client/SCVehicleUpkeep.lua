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
local sinkScans = setmetatable({}, { __mode = "k" })
local avoidedSinks = setmetatable({}, { __mode = "k" })

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
-- SCBaseFuel owns the shared chore-reservation rules: a marker counts only
-- while its open job still names the item, so a stale one never hides it.
local function marker(item) return SC.BaseFuel.marker(item, MARKER) end
local function mark(item, id) return SC.BaseFuel.mark(item, id, MARKER) end
local function clearMark(item, id) return SC.BaseFuel.clearMark(item, id, MARKER) end
local NATIVE_KINDS = { wash_vehicle = true, wash_vehicle_fill = true,
    inflate_tires = true, vehicle_area_approach = true }
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
local function washWater(item, target)
    local amount, tainted = water(item)
    if tainted or target and target.sourceKind == "sink"
        and target.sinkFilled == true then return amount end
    return 0
end
local function emptyWaterVessel(item)
    local fluid = call(item, "getFluidContainer")
    local amount = number(fluid, "getAmount")
    local capacity = number(fluid, "getCapacity")
    local category = string.lower(tostring(call(item, "getDisplayCategory") or ""))
    return amount ~= nil and amount < EPSILON and capacity and capacity >= 1
        and (category == "watercontainer" or category == "water")
end
local function cleanSink(object)
    local square = U().squareOf(object)
    return square ~= nil and SC.BaseLife.withinWorkReach(square) == true
        and call(object, "isWaterSource") == true
        and (number(object, "getFluidAmount") or 0) >= 1
        and call(object, "isTaintedWater") == false
        and (avoidedSinks[object] or 0) <= U().nowMs()
end
-- Search at most one small slice per work tick. The cached source is rechecked
-- before use; a dry sink or a newly blocked approach never remains selected.
local function findCleanSink()
    local base = SC.BaseLife.active()
    if not base then return nil, "base_missing" end
    local scan = sinkScans[base]
    if scan and cleanSink(scan.source) then return scan.source end
    if not scan or scan.done and U().nowMs() - (scan.finishedAt or 0) >= 30000 then
        scan = { zones = {}, zone = 1, index = 0 }
        for _, area in ipairs(base.zones or {}) do
            if area.kind == "area" then scan.zones[#scan.zones + 1] = area end
        end
        sinkScans[base] = scan
    end
    if scan.done then return nil, "wash_sink_missing" end
    scan.source = nil
    for _ = 1, 128 do
        local area = scan.zones[scan.zone]
        if not area then
            scan.done, scan.finishedAt = true, U().nowMs()
            return nil, "wash_sink_missing"
        end
        local width = area.x2 - area.x1 + 1
        local total = width * (area.y2 - area.y1 + 1)
        if scan.index >= total then
            scan.zone, scan.index = scan.zone + 1, 0
        else
            local offset = scan.index
            scan.index = offset + 1
            local square = U().gridSquare(area.x1 + offset % width,
                area.y1 + math.floor(offset / width), area.z)
            if square then
                U().squareObjects(square, function(object)
                    if cleanSink(object) then scan.source = object return false end
                end, 48)
                if scan.source then return scan.source end
            end
        end
    end
    return nil, "wash_sink_scanning"
end
local function avoidSink(source)
    avoidedSinks[source] = U().nowMs() + 60000
    local base = SC.BaseLife.active()
    if base then sinkScans[base] = nil end
end
local function supply(kind, actor)
    local best, score, empty, emptyScore
    for _, storage in ipairs(SC.BaseLife.storageRows(nil, true)) do
        local container = SC.BaseLife.resolveContainer(storage)
        if container then
            local protectedByType, available = {}, {}
            local items = U().inventoryItems(container, math.huge)
            for _, item in ipairs(items) do
                local itemType = U().itemType(item)
                if itemType and (SC.BaseFuel.reserved(item) or (SC.WorkTransport
                    and SC.WorkTransport.foreignProtected
                    and SC.WorkTransport.foreignProtected(item, actor) == true)) then
                    protectedByType[itemType] = (protectedByType[itemType] or 0) + 1
                end
            end
            for _, item in ipairs(items) do
                local itemType = U().itemType(item)
                if itemType and not SC.BaseFuel.reserved(item)
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
                        or kind == "wash_vehicle" and tainted and quantity >= 1
                    if usable and available[itemType] > 0 then
                        local distance = actor and U().distanceSq(actor,
                            SC.BaseLife.resolveObject(storage)) or 0
                        local rank = tonumber(distance) or 0
                        if not best or rank < score then
                            best, score = { storage, container, item }, rank
                        end
                    elseif kind == "wash_vehicle" and available[itemType] > 0
                        and emptyWaterVessel(item) then
                        local rank = actor and U().distanceSq(actor,
                            SC.BaseLife.resolveObject(storage)) or 0
                        rank = tonumber(rank) or 0
                        if not empty or rank < emptyScore then
                            empty, emptyScore = { storage, container, item }, rank
                        end
                    end
                end
            end
        end
    end
    if best then return best[1], best[2], best[3] end
    if empty then
        local source, reason = findCleanSink()
        if source or reason == "wash_sink_scanning" then
            return empty[1], empty[2], empty[3], "sink"
        end
    end
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
    return washWater(item, job.target) >= 1
end
function Upkeep.canFill(actor, item, source, jobId)
    local job = SC.BaseLife and SC.BaseLife.job(jobId)
    return job and job.type == "wash_vehicle"
        and job.reservedBy == U().idOf(actor)
        and job.target.stage == "filling_water"
        and job.target.sourceKind == "sink"
        and marker(item) == jobId
        and U().inventoryContains(U().inventory(actor), item) == true
        and cleanSink(source) == true or false
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
    target.sourceKind, target.sinkFilled, target.fillBefore = nil, nil, nil
    target.partId, target.areaId, target.area = nil, nil, nil
    target.before, target.waterBefore = nil, nil
    target.actionStartedAt, target.stageStartedAt = nil, nil
    target.attempts = nil
end
-- Drop a receipt that has nothing left to protect.
local function dropReceipt(target)
    clearTarget(target)
    target.finishReason = nil
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
    if stage ~= "working" and stage ~= "filling_water"
        and U().nowMs() - target.stageStartedAt > 90000 then
        target.stageStartedAt = nil
        return false, "upkeep_" .. stage .. "_timeout", true
    end
    if stage == "selecting" then
        local storage, container
        if target.sourceStorageId then
            storage = SC.BaseLife.storage(target.sourceStorageId)
            container = storage and SC.BaseLife.resolveContainer(storage)
            if not item then
                -- The reserved supply is gone: the player took it, or it
                -- moved. Choose another rather than retrying for it forever.
                if SC.BaseFuel.sourceState(job) == "unloaded" then
                    return false, "base_storage_unloaded", true
                end
                target.sourceStorageId, target.itemId = nil, nil
                target.sourceKind, target.sinkFilled = nil, nil
                return true, "upkeep_supply_reselecting"
            end
        else
            local sourceKind
            storage, container, item, sourceKind = supply(job.type, actor)
            if not item then return true, "upkeep_supply_exhausted", false, true end
            if not mark(item, job.id) then return false, "upkeep_supply_reserved", true end
            target.sourceStorageId, target.itemId = storage.id, call(item, "getID")
            target.sourceKind = sourceKind or (job.type == "wash_vehicle" and "tainted" or nil)
        end
        -- Older jobs may have reserved a clean drinking container. Return it
        -- without washing; only tainted water or a sink-filled vessel qualifies.
        if job.type == "wash_vehicle" and target.sourceKind ~= "sink"
            and washWater(item, target) < 1 then
            target.stage, target.finishReason = "returning", "clean_water_reserved"
            target.stageStartedAt = U().nowMs()
            return true, "upkeep_returning_supply"
        end
        if carried then
            target.stage = target.sourceKind == "sink" and "seeking_water" or "carrying"
            target.stageStartedAt = U().nowMs()
            return true, "upkeep_supply_carried"
        end
        if not storage or not container then return false, "base_storage_unloaded", true end
        local taken, reason = SC.BaseWork.withdrawFromStorage(actor, baseState,
            storage, container, item)
        if U().inventoryContains(U().inventory(actor), item) == true then
            target.stage = target.sourceKind == "sink" and "seeking_water" or "carrying"
            target.stageStartedAt = U().nowMs()
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
    if not item then
        if SC.BaseFuel.sourceState(job) == "unloaded" then
            return false, "base_storage_unloaded", true
        end
        -- Neither the worker nor the loaded storage holds the supply any more
        -- (the player took it from the worker). Start over with another.
        local stopped, why = SC.BaseFuel.stopNative(actor, NATIVE_KINDS,
            "upkeep_supply_lost")
        if stopped ~= true then return false, why, true end
        dropReceipt(target)
        return true, "upkeep_supply_lost"
    end
    local vehicle = SC.Vehicle and SC.Vehicle.loadedBySqlId(target.vehicleId)
    if stage == "seeking_water" then
        if not carried then return false, "upkeep_supply_not_carried", true end
        local source, searchReason = findCleanSink()
        if not source then
            if searchReason == "wash_sink_scanning" then
                return true, searchReason
            end
            target.stage, target.finishReason = "returning", "base_wash_sink_missing"
            target.stageStartedAt = U().nowMs()
            return true, "upkeep_returning_supply"
        end
        local at, targets, accessReason = U().directInteractionAccess(actor, source)
        if at ~= true then
            if accessReason == "no_interaction_targets" then
                avoidSink(source)
                return true, "wash_sink_retry"
            end
            local moving, reason = SC.Navigation.requestAny(actor, targets,
                "walk", { action = "move_to_wash_water", object = source,
                    targetSquare = U().squareOf(source), arrivalDistance = 0.35,
                    requireSameSquare = true, continuousApproach = true,
                    workCampOnly = true, workReach = true })
            if moving ~= true then
                avoidSink(source)
                return true, "wash_sink_retry"
            end
            return true, reason or "approaching_wash_sink"
        end
        target.fillBefore = number(call(item, "getFluidContainer"), "getAmount") or 0
        target.stage, target.stageStartedAt = "filling_water", U().nowMs()
        target.actionStartedAt = U().nowMs()
        local started, reason = SC.NativeActions.startVehicleWashFill(
            actor, item, source, job.id)
        if started ~= true then
            target.stage, target.fillBefore = "seeking_water", nil
            return false, reason or "wash_sink_fill_rejected", true
        end
        return true, "wash_sink_fill_started"
    end
    if stage == "filling_water" then
        local native = SC.NativeActions
        if native.workKind(actor) == "wash_vehicle_fill" then
            if native.isWorkActive(actor) == true then
                if U().nowMs() - (tonumber(target.actionStartedAt) or 0)
                    < 120000 then return true, "wash_sink_fill_active" end
                local stopped, reason = native.cancelWork(actor, "wash_sink_fill_timeout")
                if stopped ~= true then return false, reason, true end
            else
                local finished, reason = native.finishWork(actor)
                if finished ~= true then return false, reason, true end
            end
        end
        local amount = water(item)
        target.stage, target.stageStartedAt = amount >= 1
            and "carrying" or "seeking_water", U().nowMs()
        if amount > (tonumber(target.fillBefore) or 0) + EPSILON then
            target.sinkFilled = true
        end
        target.fillBefore, target.actionStartedAt = nil, nil
        return true, amount >= 1 and target.sinkFilled
            and "wash_sink_filled" or "wash_sink_fill_retry"
    end
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
        if okay ~= true then
            -- Readings that do not add up, or a car driven out of reach, never
            -- clear by waiting. Take the supply home and end the job.
            target.stage, target.finishReason = "returning", reason
            target.before, target.waterBefore = nil, nil
            target.stageStartedAt = U().nowMs()
            return true, "upkeep_returning_supply"
        end
        return true, reason
    end
    if stage == "carrying" then
        if not carried then return false, "upkeep_supply_not_carried", true end
        local okay, info, need = Upkeep.eligible(job.type, vehicle,
            target.manual == true, true)
        local zoneChanged = okay and target.zoneId and info.zoneId ~= target.zoneId
        local waterMissing = job.type == "wash_vehicle"
            and washWater(item, target) < 1
        if not okay or zoneChanged or not need or waterMissing then
            if okay and not zoneChanged and need and waterMissing
                and target.sourceKind == "sink" then
                target.stage, target.stageStartedAt = "seeking_water", U().nowMs()
                return true, "wash_sink_refill_needed"
            end
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
    local home, storage, container = SC.BaseFuel.sourceState(job)
    if home == "removed" then
        -- The player unmarked the supply's storage. The worker keeps it,
        -- unreserved, and ordinary camp hauling decides where it goes.
        if not clearMark(item, job.id) then return false, "upkeep_marker_uncertain", true end
        dropReceipt(target)
        return true, "upkeep_source_removed", false, true
    end
    if home ~= "loaded" then return false, "base_storage_unloaded", true end
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
    if not actor then
        -- A worker who died or was removed can never finish this receipt.
        return SC.BaseFuel.workerGone(job) and Upkeep.cancel(nil, job) == true or false
    end
    local item, carried = itemFor(job, actor)
    if carried or job.target.stage == "working" or (SC.NativeActions
        and NATIVE_KINDS[SC.NativeActions.workKind(actor) or ""]) then
        return false
    end
    if item and marker(item) ~= job.id then return false end
    job.assignedId, states[actor] = nil, nil
    return true
end
-- Cancelling refuses only while the supply may still come back: a dormant
-- worker, an unloaded storage or a native action that will not stop. It never
-- waits on pressure or blood readings; the supply simply goes home.
function Upkeep.cancel(actor, job)
    if not job then return true end
    local target = job.target
    if not actor then
        if target.stage ~= nil and not SC.BaseFuel.workerGone(job) then
            return false, "upkeep_worker_unavailable"
        end
        SC.BaseFuel.clearStoredMark(job, MARKER)
        dropReceipt(target)
        job.assignedId = nil
        return true, "upkeep_receipt_released"
    end
    local item, carried = itemFor(job, actor)
    -- Stop only this job's own action; the worker may be on a newer chore.
    if states[actor] == job.id
        and NATIVE_KINDS[SC.NativeActions.workKind(actor) or ""] then
        local stopped, reason = SC.NativeActions.cancelWork(actor,
            "upkeep_cancelled")
        if stopped ~= true then return false, reason end
    end
    if U().isDead(actor) then
        SC.BaseFuel.prepareActorRetirement(actor)
        SC.BaseFuel.clearStoredMark(job, MARKER)
        dropReceipt(target)
        job.assignedId, states[actor] = nil, nil
        return true, "upkeep_worker_retired"
    end
    local home, storage, container = SC.BaseFuel.sourceState(job)
    if home == "unloaded" then return false, "base_storage_unloaded" end
    if item then
        if home == "loaded" and carried then
            local returned, reason = SC.BaseWork.restoreToStorage(actor,
                storage, container, item)
            if returned ~= true then return false, reason end
        elseif home == "loaded" and U().inventoryContains(container, item) ~= true then
            return false, "upkeep_supply_owner_uncertain"
        end
        if not clearMark(item, job.id) then return false, "upkeep_marker_uncertain" end
    end
    dropReceipt(target)
    job.assignedId, states[actor] = nil, nil
    return true
end
return Upkeep
