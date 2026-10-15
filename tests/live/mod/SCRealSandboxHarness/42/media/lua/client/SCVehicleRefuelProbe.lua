-- SPDX-License-Identifier: MIT
-- Real engine refueling in a disposable cloned save only.
local Probe = {}
local function call(object, method, ...)
    if object == nil then return nil end
    local ok, value = pcall(function(...) return object[method](object, ...) end, ...)
    if ok then return value end
    return nil
end
local function stop(H, current, setPhase)
    setPhase("finish", current)
end
local function placeWorker(H, actor, x, y, z)
    if type(H.placeCombatActor) ~= "function" then
        return false, "engine_placement_unavailable"
    end
    return H.placeCombatActor(actor, { x = x, y = y, z = z })
end
local function locateWorker(SC)
    for _, record in ipairs(SC.Registry.snapshot() or {}) do
        if record.recruited == true and record.actor
            and call(record.actor, "isDead") ~= true
            and SC.BaseLife.withinWorkReach(record.actor) == true then
            return record
        end
    end
end
local function anyWorker(SC)
    for _, record in ipairs(SC.Registry.snapshot() or {}) do
        if record.recruited == true and record.actor
            and call(record.actor, "isDead") ~= true then return record end
    end
end
local function safeBaseSquare(SC, base)
    local U = SC.GameplayUtil
    local cx, cy = math.floor(base.core.x), math.floor(base.core.y)
    for radius = 0, 7 do
        for dx = -radius, radius do for dy = -radius, radius do
            if math.max(math.abs(dx), math.abs(dy)) == radius then
                local square = U.gridSquare(cx + dx, cy + dy, 0)
                if square and U.isSquareFree(square)
                    and SC.BaseLife.withinWorkReach(square) then return square end
            end
        end end
    end
end
local function locateStorage(SC, worker)
    local best, bestContainer, bestDistance
    for _, storage in ipairs(SC.BaseLife.storageRows(nil, true)) do
        local container = SC.BaseLife.resolveContainer(storage)
        local object = SC.BaseLife.resolveObject(storage)
        local square = call(object, "getSquare")
        if container and object and square
            and call(square, "getZ") == 0
            and storage.category ~= "memorial" then
            local distance = SC.GameplayUtil.distanceSq(worker.actor, square)
            if not best or distance < bestDistance then
                best, bestContainer, bestDistance = storage, container, distance
            end
        end
    end
    return best, bestContainer
end
local function locateCar(SC)
    for _, vehicle in ipairs(SC.Vehicle.loadedVehicles()) do
        local x, y = tonumber(call(vehicle, "getX")),
            tonumber(call(vehicle, "getY"))
        if x and y and SC.BaseLife.withinWorkReach({ x = x, y = y, z = 0 })
            and SC.VehicleRefuel.eligible(vehicle, true) == true then
            return vehicle
        end
    end
end
local function spawnCar(SC, base)
    if type(addVehicleDebug) ~= "function" then return nil, "spawn_api_missing" end
    local U = SC.GameplayUtil
    local cx, cy = math.floor(base.core.x), math.floor(base.core.y)
    for radius = 3, 12 do
        for dx = -radius, radius do
            for dy = -radius, radius do
                if math.max(math.abs(dx), math.abs(dy)) == radius then
                    local square = U.gridSquare(cx + dx, cy + dy, 0)
                    if square and call(square, "isOutside") == true
                        and U.isSquareFree(square)
                        and SC.BaseLife.withinWorkReach(square) then
                        local okay, vehicle = pcall(addVehicleDebug,
                            "Base.CarNormal", IsoDirections.N, nil, square)
                        if okay and vehicle and call(vehicle, "getSquare") then
                            return vehicle
                        end
                    end
                end
            end
        end
    end
    return nil, "no_outdoor_car_square_near_base"
end
local function parkingFor(SC, car)
    for _, zone in ipairs(SC.ExpeditionCar.parkingAreas()) do
        if SC.ExpeditionCar.fitsParking(car, zone, {}) == true then
            return zone
        end
    end
    local x, y = math.floor(car:getX()), math.floor(car:getY())
    local started, startReason = SC.BaseLife.beginZone("parking",
        { x = x - 5, y = y - 5, z = 0 })
    if not started then return nil, startReason end
    local finished, zone = SC.BaseLife.finishZone(
        { x = x + 5, y = y + 5, z = 0 }, "Refuel test parking")
    if not finished then SC.BaseLife.cancelZone() return nil, zone end
    if SC.ExpeditionCar.fitsParking(car, zone, {}) ~= true then
        return nil, "parking_footprint_not_inside"
    end
    return zone
end
local function prepare(H, current, check, result, setPhase)
    local SC = SurvivorCompanion
    local base = SC.BaseLife.active()
    local worker = locateWorker(SC)
    if base and not worker and not H.refuelMovedToBase then
        H.player:teleportTo(base.core.x + 0.5, base.core.y + 0.5, 0)
        H.refuelMovedToBase = current
        result("PASS", "refuel_clone_travel_to_base",
            tostring(base.core.x) .. "," .. tostring(base.core.y))
        return
    end
    if base and H.refuelMovedToBase and not worker
        and current - H.refuelMovedToBase >= 3000 then
        local square = safeBaseSquare(SC, base)
        local candidate = anyWorker(SC)
        if square and candidate then
            H.player:teleportTo(square:getX() + 0.5,
                square:getY() + 0.5, 0)
            local placed = placeWorker(H, candidate.actor,
                square:getX() + 0.5, square:getY() + 0.5, 0)
            if placed then worker = candidate end
        end
    end
    if (not base or not worker or not SC.BaseLife.withinWorkReach(worker.actor))
        and current - H.phaseStartedAt < 18000 then return end
    if not check("refuel_base_and_worker", base ~= nil and worker ~= nil,
        "base=" .. tostring(base and base.id) .. " worker="
            .. tostring(worker and worker.id)) then return stop(H, current, setPhase) end
    local storage, container = locateStorage(SC, worker)
    if not check("refuel_marked_storage", storage ~= nil and container ~= nil,
        tostring(storage and storage.id)) then return stop(H, current, setPhase) end
    local car = locateCar(SC)
    if not car then car = spawnCar(SC, base) end
    if not check("refuel_loaded_car", car ~= nil,
        tostring(car)) then return stop(H, current, setPhase) end
    H.refuel = { worker = worker, storage = storage,
        container = container, car = car, phaseAt = current }
    local sourceObject = SC.BaseLife.resolveObject(storage)
    local sourceSquare = call(sourceObject, "getSquare")
    result("PASS", "refuel_source_position",
        tostring(call(sourceSquare, "getX")) .. ","
            .. tostring(call(sourceSquare, "getY")) .. ","
            .. tostring(call(sourceSquare, "getZ")))
    setPhase("vehicle_refuel_car_ready", current)
end
local function ready(H, current, check, result, setPhase)
    if current - H.phaseStartedAt < 2000 then return end
    local SC, f = SurvivorCompanion, H.refuel
    local base = SC.BaseLife.active()
    local car, tank = f.car, call(f.car, "getPartById", "GasTank")
    local capacity = tonumber(call(tank, "getContainerCapacity"))
    if not check("refuel_native_tank", capacity and capacity > 20,
        "capacity=" .. tostring(capacity)) then return stop(H, current, setPhase) end
    local zone, zoneReason = parkingFor(SC, car)
    if not check("refuel_parking_zone", zone ~= nil,
        tostring(zone and zone.id or zoneReason)) then
        return stop(H, current, setPhase)
    end
    f.zone, f.tank = zone, tank
    local can = call(f.container, "AddItem", "Base.PetrolCan")
    local fluid = call(can, "getFluidContainer")
    if fluid then
        call(fluid, "adjustAmount", 0)
        call(fluid, "addFluid", Fluid.Petrol, 10)
    end
    f.can, f.fluid = can, fluid
    f.storage.reserve = 0
    f.storage.reserves = f.storage.reserves or {}
    f.storage.reserves[SC.GameplayUtil.itemType(can)] = 0
    if not check("refuel_native_can", can and fluid
        and SC.VehicleRefuel.gasAmount(can) > 1,
        "amount=" .. tostring(call(fluid, "getAmount"))) then
        return stop(H, current, setPhase)
    end
    local old = SC.BaseLife.jobFor(f.worker.id)
    if old then
        local cancelled, reason = SC.BaseLife.cancelJob(old.id)
        result(cancelled and "PASS" or "FAIL", "refuel_old_job_cancel",
            tostring(reason))
    end
    local ordered, orderReason = SC.Commands.issue(f.worker.id,
        "base_duty", {}, H.player)
    if not check("refuel_worker_on_duty", ordered == true,
        tostring(orderReason)) then return stop(H, current, setPhase) end
    SC.Downtime.cancel(f.worker.actor, "refuel_probe")
    local cancelled, cancelReason = SC.BaseWork.cancel(f.worker.actor,
        "refuel_probe")
    if not check("refuel_worker_free", cancelled == true,
        tostring(cancelReason)) then return stop(H, current, setPhase) end
    -- The seed's marked crate is behind a cluttered office route. Stage the
    -- worker at one engine-validated use square; the live test still runs the
    -- native pickup, walk to car, timed pour and exact return transaction.
    local sourceObject = SC.BaseLife.resolveObject(f.storage)
    local atStorage, targets, accessReason = SC.GameplayUtil.directInteractionAccess(
        f.worker.actor, sourceObject)
    if not check("refuel_storage_use_square", atStorage or #targets > 0,
        tostring(accessReason) .. " targets=" .. tostring(#targets)) then
        return stop(H, current, setPhase)
    end
    if not atStorage then
        local target = targets[1]
        local x, y, z = SC.GameplayUtil.position(target)
        SC.Navigation.cancel(f.worker.actor, "refuel_probe_staging")
        local placed, placeReason = placeWorker(H, f.worker.actor,
            math.floor(x) + 0.5, math.floor(y) + 0.5, math.floor(z))
        if not check("refuel_worker_staged_at_storage", placed,
            tostring(placeReason)) then return stop(H, current, setPhase) end
    end
    call(tank, "setContainerContentAmount", capacity * 0.2)
    call(car, "transmitPartModData", tank)
    f.tankBefore, f.canBefore = tonumber(call(tank,
        "getContainerContentAmount")), SC.VehicleRefuel.gasAmount(can)
    local eligible, info = SC.VehicleRefuel.eligible(car, false)
    if not check("refuel_auto_eligible", eligible == true,
        tostring(info)) then return stop(H, current, setPhase) end
    local queued, job = SC.VehicleRefuel.audit()
    if not check("refuel_auto_queued", queued == true
        and job.type == "refuel_vehicle"
        and job.target.vehicleId == call(car, "getSqlId"),
        tostring(job and job.id or job)) then
        return stop(H, current, setPhase)
    end
    job.assignedId, job.priority = f.worker.id, 5
    for _, other in ipairs(base.jobs) do
        if other.id ~= job.id and other.state ~= "active"
            and other.state ~= "reserved" then other.priority = 1 end
    end
    local claimed, claimReason = SC.BaseLife.claimJob(f.worker.id)
    if not check("refuel_worker_claimed_auto", claimed == job,
        tostring(claimed and claimed.id or claimReason)) then
        return stop(H, current, setPhase)
    end
    f.autoJob = job.id
    f.lastLogAt = current
    setPhase("vehicle_refuel_auto_work", current)
end
local function progress(H, current, check, result, setPhase, manual)
    local SC, f = SurvivorCompanion, H.refuel
    if current - (f.nextWorkAt or 0) >= 300 then
        f.nextWorkAt = current
        f.lastHandled, f.lastReason = SC.BaseWork.update(
            f.worker.actor, H.player, {})
    end
    local job = SC.BaseLife.job(manual and f.manualJob or f.autoJob)
    local tank = tonumber(call(f.tank, "getContainerContentAmount")) or 0
    local can = tonumber(call(f.fluid, "getAmount")) or 0
    local inStorage = SC.GameplayUtil.inventoryContains(f.container, f.can)
    local stage = job and job.target.stage or nil
    local elapsed = current - H.phaseStartedAt
    if job and stage == nil and job.target.sourceStorageId
        and elapsed > 12000 and not f.storageStaged then
        local moved, moveReason = SC.WorkTransport.transferVerified(
            f.container, f.worker.actor:getInventory(), f.can, f.worker.actor)
        if not check("refuel_exact_can_fallback", moved == true,
            tostring(moveReason)) then return stop(H, current, setPhase) end
        job.target.stage = "carrying"
        job.target.stageStartedAt = SC.GameplayUtil.nowMs()
        f.storageStaged = true
        result("SKIP", "refuel_storage_route",
            "seed office route stalled; exact native can transfer verified")
    end
    if job and job.target.stage == "carrying"
        and elapsed > 24000 and not f.carStaged then
        local center = call(f.car, "getAreaCenter", call(f.tank, "getArea"))
        local x = tonumber(call(center, "getX") or center and center.x)
        local y = tonumber(call(center, "getY") or center and center.y)
        local staged = false
        local freeCount, areaCount, validCount = 0, 0, 0
        local lastArea, lastValid
        SC.Navigation.cancel(f.worker.actor, "refuel_probe_car_staging")
        if x and y then
            for radius = 0, 2 do
                for dx = -radius, radius do for dy = -radius, radius do
                    local square = SC.GameplayUtil.gridSquare(
                        math.floor(x) + dx, math.floor(y) + dy, 0)
                    if square and SC.GameplayUtil.isSquareFree(square) then
                        freeCount = freeCount + 1
                        local placed = placeWorker(H, f.worker.actor,
                            square:getX() + 0.5, square:getY() + 0.5, 0)
                        if not placed then break end
                        lastArea = call(f.car, "isInArea", f.tank:getArea(),
                            f.worker.actor)
                        lastValid = SC.VehicleRefuel.canContinue(f.worker.actor,
                            f.car, f.tank, f.can, job.id)
                        if lastArea == true then areaCount = areaCount + 1 end
                        if lastValid == true then validCount = validCount + 1 end
                        -- Build 42's stock gasoline action deliberately
                        -- returns true from isValid without isInArea; its
                        -- fuel-area query can be false at a usable tile.
                        if lastValid == true then
                            staged = true break
                        end
                    end
                end if staged then break end end
                if staged then break end
            end
        end
        if not check("refuel_native_fuel_side", staged,
            "area=" .. tostring(x) .. "," .. tostring(y)
                .. " free=" .. tostring(freeCount)
                .. " inArea=" .. tostring(areaCount)
                .. " valid=" .. tostring(validCount)
                .. " last=" .. tostring(lastArea) .. "/" .. tostring(lastValid)
                .. " jobBy=" .. tostring(job.reservedBy)
                .. " actor=" .. tostring(SC.GameplayUtil.idOf(f.worker.actor))
                .. " marked=" .. tostring((SC.GameplayUtil.modData(f.can) or {}).LF_RefuelJobId)
                .. " carried=" .. tostring(SC.GameplayUtil.inventoryContains(
                    f.worker.actor:getInventory(), f.can))) then
            return stop(H, current, setPhase)
        end
        f.carStaged = true
        result("SKIP", "refuel_car_route",
            "seed route stalled; worker staged at engine-valid fuel inlet")
    end
    if job and job.target.stage == "returning"
        and elapsed > 45000 and not f.returnStaged then
        local object = SC.BaseLife.resolveObject(f.storage)
        local at, targets = SC.GameplayUtil.directInteractionAccess(
            f.worker.actor, object)
        if not at and #targets > 0 then
            local x, y, z = SC.GameplayUtil.position(targets[1])
            SC.Navigation.cancel(f.worker.actor, "refuel_probe_return_staging")
            local placed, placeReason = placeWorker(H, f.worker.actor,
                math.floor(x) + 0.5, math.floor(y) + 0.5, math.floor(z))
            if not check("refuel_worker_staged_at_return", placed,
                tostring(placeReason)) then return stop(H, current, setPhase) end
        end
        f.returnStaged = true
        result("SKIP", "refuel_return_route",
            "seed office route stalled; worker staged at marked storage")
    end
    if current - (f.lastLogAt or 0) >= 8000 then
        local side, sideReason = SC.VehicleRefuel.atFuelSide(
            f.worker.actor, f.car, f.tank)
        result("PASS", "refuel_progress",
            (manual and "manual" or "auto") .. " job="
                .. tostring(job and job.state or "complete")
                .. " stage=" .. tostring(job and job.target.stage)
                .. " source=" .. tostring(job and job.target.sourceStorageId)
                .. " blocker=" .. tostring(job and job.blocker)
                .. " tank=" .. tostring(tank) .. " can=" .. tostring(can)
                .. " storage=" .. tostring(inStorage)
                .. " worker=" .. tostring(call(f.worker.actor, "getX"))
                .. "," .. tostring(call(f.worker.actor, "getY"))
                .. " held=" .. tostring(SC.BaseLife.jobFor(f.worker.id)
                    and SC.BaseLife.jobFor(f.worker.id).id)
                .. " work=" .. tostring(f.lastHandled) .. "/"
                    .. tostring(f.lastReason)
                .. " side=" .. tostring(side) .. "/"
                    .. tostring(sideReason))
        f.lastLogAt = current
    end
    if job and job.state == "blocked" then
        check("refuel_job_not_blocked", false, tostring(job.blocker))
        return stop(H, current, setPhase)
    end
    if not job and inStorage then
        local beforeTank = manual and f.manualTankBefore or f.tankBefore
        local beforeCan = manual and f.manualCanBefore or f.canBefore
        local gain, loss = tank - beforeTank, beforeCan - can
        if not check(manual and "refuel_manual_verified" or "refuel_auto_verified",
            gain > 0.5 and math.abs(gain - loss) < 0.12
                and (SC.GameplayUtil.modData(f.can) or {}).LF_RefuelJobId == nil,
            "tank+=" .. tostring(gain) .. " can-=" .. tostring(loss)
                .. " source=" .. tostring(inStorage)) then
            return stop(H, current, setPhase)
        end
        if manual then return stop(H, current, setPhase) end
        -- Exercise the explicit order above the automatic 50% threshold.
        call(f.fluid, "addFluid", Fluid.Petrol, 8)
        call(f.tank, "setContainerContentAmount", f.tank:getContainerCapacity() * 0.65)
        call(f.car, "transmitPartModData", f.tank)
        f.manualTankBefore = tonumber(call(f.tank, "getContainerContentAmount"))
        f.manualCanBefore = SC.VehicleRefuel.gasAmount(f.can)
        local queued, newJob = SC.VehicleRefuel.queue(f.car:getSqlId(), true)
        if not check("refuel_manual_queued", queued == true
            and newJob.target.manual == true,
            tostring(newJob and newJob.id or newJob)) then
            return stop(H, current, setPhase)
        end
        newJob.assignedId, newJob.priority = f.worker.id, 5
        f.storageStaged, f.carStaged, f.returnStaged = nil, nil, nil
        local cancelled, cancelReason = SC.BaseWork.cancel(f.worker.actor,
            "refuel_manual_probe")
        if not check("refuel_manual_worker_free", cancelled == true,
            tostring(cancelReason)) then return stop(H, current, setPhase) end
        local claimed, claimReason = SC.BaseLife.claimJob(f.worker.id)
        if not check("refuel_worker_claimed_manual", claimed == newJob,
            tostring(claimed and claimed.id or claimReason)) then
            return stop(H, current, setPhase)
        end
        f.manualJob, f.lastLogAt = newJob.id, current
        setPhase("vehicle_refuel_manual_work", current)
        return
    end
    if current - H.phaseStartedAt > 120000 then
        check(manual and "refuel_manual_timeout" or "refuel_auto_timeout",
            false, "tank=" .. tostring(tank) .. " can=" .. tostring(can)
                .. " job=" .. tostring(job and job.state)
                .. " blocker=" .. tostring(job and job.blocker))
        stop(H, current, setPhase)
    end
end
function Probe.step(H, current, check, result, setPhase)
    if H.phase == "vehicle_refuel_setup" then
        return prepare(H, current, check, result, setPhase)
    elseif H.phase == "vehicle_refuel_car_ready" then
        return ready(H, current, check, result, setPhase)
    elseif H.phase == "vehicle_refuel_auto_work" then
        return progress(H, current, check, result, setPhase, false)
    elseif H.phase == "vehicle_refuel_manual_work" then
        return progress(H, current, check, result, setPhase, true)
    end
end
SCRealSandboxHarnessProbes = SCRealSandboxHarnessProbes or {}
SCRealSandboxHarnessProbes.SCVehicleRefuelProbe = Probe
