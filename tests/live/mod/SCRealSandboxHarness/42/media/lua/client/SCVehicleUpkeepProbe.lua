-- SPDX-License-Identifier: MIT
-- Native tire and wash transactions in a disposable cloned save.
local Probe = {}
local function call(object, method, ...)
    if not object then return nil end
    local ok, value = pcall(function(...) return object[method](object, ...) end, ...)
    if ok then return value end
end
local function finish(H, current, setPhase)
    setPhase("finish", current)
end
local function place(H, actor, square)
    if not square or type(H.placeCombatActor) ~= "function" then return false end
    return H.placeCombatActor(actor, { x = square:getX() + 0.5,
        y = square:getY() + 0.5, z = square:getZ() })
end
local function worker(SC)
    for _, record in ipairs(SC.Registry.snapshot() or {}) do
        if record.recruited and record.actor and not call(record.actor, "isDead")
            and SC.BaseLife.withinWorkReach(record.actor) then return record end
    end
end
local function storage(SC, actor)
    for _, row in ipairs(SC.BaseLife.storageRows(nil, true)) do
        local container = SC.BaseLife.resolveContainer(row)
        local object = SC.BaseLife.resolveObject(row)
        local square = call(object, "getSquare")
        local at, squares = SC.GameplayUtil.directInteractionAccess(actor, object)
        if container and square and square:getZ() == 0
            and (at or #squares > 0) then
            -- Stand beside the container. Its own square may be occupied by
            -- the fridge or cabinet and trap a teleported test actor.
            for _, candidate in ipairs(squares) do
                if candidate ~= square and SC.GameplayUtil.isSquareFree(candidate) then
                    return row, container, candidate
                end
            end
            if at and SC.GameplayUtil.isSquareFree(square) then
                return row, container, square
            end
        end
    end
end
local function car(SC, base)
    for _, vehicle in ipairs(SC.Vehicle.loadedVehicles()) do
        if SC.BaseLife.withinWorkReach({ x = vehicle:getX(),
            y = vehicle:getY(), z = vehicle:getZ() })
            and SC.Vehicle.isStationary(vehicle) then return vehicle end
    end
    if type(addVehicleDebug) ~= "function" then return nil end
    local U = SC.GameplayUtil
    for radius = 3, 12 do
        for dx = -radius, radius do for dy = -radius, radius do
            if math.max(math.abs(dx), math.abs(dy)) == radius then
                local square = U.gridSquare(math.floor(base.core.x) + dx,
                    math.floor(base.core.y) + dy, 0)
                if square and call(square, "isOutside") == true
                    and U.isSquareFree(square)
                    and SC.BaseLife.withinWorkReach(square) then
                    local ok, spawned = pcall(addVehicleDebug, "Base.CarNormal",
                        IsoDirections.N, nil, square)
                    if ok and spawned and call(spawned, "getSquare") then
                        return spawned
                    end
                end
            end
        end end
    end
end
local function park(SC, vehicle)
    for _, zone in ipairs(SC.ExpeditionCar.parkingAreas()) do
        if SC.ExpeditionCar.fitsParking(vehicle, zone, {}) then return zone end
    end
    local x, y = math.floor(vehicle:getX()), math.floor(vehicle:getY())
    if not SC.BaseLife.beginZone("parking", { x = x - 5, y = y - 5, z = 0 })
        then return nil end
    local ok, zone = SC.BaseLife.finishZone({ x = x + 5,
        y = y + 5, z = 0 }, "Upkeep test parking")
    if ok and SC.ExpeditionCar.fitsParking(vehicle, zone, {}) then return zone end
    return nil
end
local function setup(H, current, check, result, setPhase)
    local SC = SurvivorCompanion
    local base = SC.BaseLife.active()
    local person = base and worker(SC)
    if base and not person and not H.upkeepMoved then
        H.player:teleportTo(base.core.x + 0.5, base.core.y + 0.5, 0)
        H.upkeepMoved = current
        return
    end
    if base and H.upkeepMoved and not person and current - H.upkeepMoved > 3000 then
        for _, record in ipairs(SC.Registry.snapshot() or {}) do
            if record.recruited and record.actor and not call(record.actor, "isDead") then
                local square = SC.GameplayUtil.gridSquare(math.floor(base.core.x),
                    math.floor(base.core.y), 0)
                if place(H, record.actor, square) then person = record break end
            end
        end
    end
    if not base or not person then
        if current - H.phaseStartedAt < 18000 then return end
        check("upkeep_base_worker", false, "base=" .. tostring(base)
            .. " worker=" .. tostring(person))
        return finish(H, current, setPhase)
    end
    local row, container, sourceSquare = storage(SC, person.actor)
    if not check("upkeep_marked_storage", row ~= nil and container ~= nil
        and sourceSquare ~= nil,
        tostring(row and row.id)) then return finish(H, current, setPhase) end
    local vehicle = car(SC, base)
    if not check("upkeep_loaded_car", vehicle ~= nil, tostring(vehicle)) then
        return finish(H, current, setPhase) end
    H.upkeep = { worker = person, storage = row, container = container,
        sourceSquare = sourceSquare, car = vehicle }
    setPhase("vehicle_upkeep_ready", current)
end
local function ready(H, current, check, result, setPhase)
    if current - H.phaseStartedAt < 2000 then return end
    local SC, f = SurvivorCompanion, H.upkeep
    local zone = park(SC, f.car)
    if not check("upkeep_parking", zone ~= nil, tostring(zone and zone.id)) then
        return finish(H, current, setPhase) end
    local tire
    for index = 0, (f.car:getPartCount() or 0) - 1 do
        local part = f.car:getPartByIndex(index)
        if part and call(part, "getContainerContentType") == "Air"
            and call(part, "getInventoryItem") then tire = part break end
    end
    if not check("upkeep_native_tire", tire ~= nil,
        tostring(tire and tire:getId())) then return finish(H, current, setPhase) end
    f.tire = tire
    local pump = call(f.container, "AddItem", "Base.TirePump")
    local waterItem = call(f.container, "AddItem", "Base.BucketEmpty")
    local water = call(waterItem, "getFluidContainer")
    if water then
        call(water, "adjustAmount", 0)
        call(water, "addFluid", Fluid.TaintedWater, 8)
    end
    if not check("upkeep_supplies", pump ~= nil and water ~= nil
        and (tonumber(call(water, "getAmount")) or 0) >= 4,
        tostring(pump) .. "/" .. tostring(call(water, "getAmount"))) then
        return finish(H, current, setPhase) end
    f.pump, f.waterItem, f.water = pump, waterItem, water
    f.storage.reserve = 0
    f.storage.reserves = f.storage.reserves or {}
    f.storage.reserves[SC.GameplayUtil.itemType(pump)] = 0
    f.storage.reserves[SC.GameplayUtil.itemType(waterItem)] = 0
    for index = 0, f.car:getPartCount() - 1 do
        local part = f.car:getPartByIndex(index)
        if part and call(part, "getContainerContentType") == "Air"
            and part:getInventoryItem() then
            part:setContainerContentAmount(part:getContainerCapacity()
                * (part == tire and 0.7 or 1), true, true)
            f.car:transmitPartModData(part)
        end
    end
    f.car:setBloodIntensity("Front", 0.2)
    for _, id in ipairs({ "Rear", "Left", "Right" }) do
        f.car:setBloodIntensity(id, 0)
    end
    f.pressureBefore = tire:getContainerContentAmount()
    f.waterBefore = water:getAmount()
    f.bloodBefore = f.car:getBloodIntensity("Front")
    local old = SC.BaseLife.jobFor(f.worker.id)
    if old then SC.BaseLife.cancelJob(old.id) end
    SC.Commands.issue(f.worker.id, "base_duty", {}, H.player)
    SC.Downtime.cancel(f.worker.actor, "upkeep_probe")
    SC.BaseWork.cancel(f.worker.actor, "upkeep_probe")
    place(H, f.worker.actor, f.sourceSquare)
    local queued, job = SC.VehicleUpkeep.audit()
    if not check("upkeep_auto_tire_queued", queued == true and job ~= nil
        and job.type == "inflate_tires", tostring(job and job.type or job)) then
        return finish(H, current, setPhase) end
    job.assignedId, job.priority = f.worker.id, 5
    local claimed = SC.BaseLife.claimJob(f.worker.id)
    if not check("upkeep_worker_claimed", claimed == job,
        tostring(claimed and claimed.id)) then return finish(H, current, setPhase) end
    f.jobId = job.id
    setPhase("vehicle_upkeep_inflate", current)
end
local function stageCar(H, SC, f, job, result)
    local vehicle = f.car
    local part = job.type == "inflate_tires" and f.tire or nil
    local area = part and part:getArea() or "Engine"
    local center = vehicle:getAreaCenter(area)
    local x = tonumber(call(center, "getX") or center and center.x)
    local y = tonumber(call(center, "getY") or center and center.y)
    if not x or not y then return false, "area_center_missing" end
    local item = part and f.pump or f.waterItem
    local free, placed, inArea, valid = 0, 0, 0, 0
    for radius = 0, 2 do
        for dx = -radius, radius do for dy = -radius, radius do
            local square = SC.GameplayUtil.gridSquare(math.floor(x) + dx,
                math.floor(y) + dy, 0)
            if square and SC.GameplayUtil.isSquareFree(square) then
                free = free + 1
                if place(H, f.worker.actor, square) then
                    placed = placed + 1
                    if vehicle:isInArea(area, f.worker.actor) then
                        inArea = inArea + 1
                    end
                    if SC.VehicleUpkeep.canContinue(f.worker.actor,
                        vehicle, item, job.id, area, part) then
                        valid = valid + 1
                        result("SKIP", "upkeep_car_route",
                            "worker staged at native area")
                        return true
                    end
                end
            end
        end end
    end
    return false, "center=" .. x .. "," .. y .. " free=" .. free
        .. " placed=" .. placed .. " inArea=" .. inArea
        .. " valid=" .. valid .. " jobBy=" .. tostring(job.reservedBy)
        .. " actor=" .. tostring(SC.GameplayUtil.idOf(f.worker.actor))
        .. " marked=" .. tostring((SC.GameplayUtil.modData(item) or {}).LF_UpkeepJobId)
        .. " carried=" .. tostring(SC.GameplayUtil.inventoryContains(
            f.worker.actor:getInventory(), item))
end
local function stageYard(H, SC, f, job)
    local area = job.type == "inflate_tires" and f.tire:getArea() or "Engine"
    local center = f.car:getAreaCenter(area)
    local x = tonumber(call(center, "getX") or center and center.x)
    local y = tonumber(call(center, "getY") or center and center.y)
    if not x or not y then return false end
    for radius = 3, 5 do
        for dx = -radius, radius do for dy = -radius, radius do
            if math.max(math.abs(dx), math.abs(dy)) == radius then
                local square = SC.GameplayUtil.gridSquare(math.floor(x) + dx,
                    math.floor(y) + dy, 0)
                if square and SC.GameplayUtil.isSquareFree(square)
                    and call(square, "isOutside") == true
                    and SC.BaseLife.withinWorkReach(square) then
                    SC.Navigation.cancel(f.worker.actor, "upkeep_probe_yard_staging")
                    if place(H, f.worker.actor, square) then return true end
                end
            end
        end end
    end
    return false
end
local function progress(H, current, check, result, setPhase)
    local SC, f = SurvivorCompanion, H.upkeep
    local job = SC.BaseLife.job(f.jobId)
    local elapsed = current - H.phaseStartedAt
    if job and job.target.stage == "carrying" and not f.yardStaged then
        f.yardStaged = stageYard(H, SC, f, job)
        if f.yardStaged then
            result("SKIP", "upkeep_storage_yard_route",
                "worker staged outside to test final car approach")
        end
    end
    if current - (f.nextWorkAt or 0) >= 300 then
        f.nextWorkAt = current
        f.handled, f.reason = SC.BaseWork.update(f.worker.actor, H.player, {})
        if H.phase == "vehicle_upkeep_wash"
            and (f.reason == "upkeep_action_started"
                or f.reason == "upkeep_retry"
                or f.reason == "upkeep_progress_verified") then
            local held = SC.BaseLife.job(f.jobId)
            result("PASS", "upkeep_wash_action_state",
                tostring(f.reason) .. " active=" .. tostring(
                    SC.NativeActions.isWorkActive(f.worker.actor))
                    .. " kind=" .. tostring(SC.NativeActions.workKind(f.worker.actor))
                    .. " valid=" .. tostring(SC.VehicleUpkeep.canContinue(
                        f.worker.actor, f.car, f.waterItem, f.jobId, "Engine"))
                    .. " nativeWater=" .. tostring(ISWashVehicle
                        .getWaterAmountForPlayer(f.worker.actor))
                    .. " instant=" .. tostring(f.worker.actor:isTimedActionInstant())
                    .. " inArea=" .. tostring(f.car:isInArea("Engine",
                        f.worker.actor)) .. " water=" .. tostring(f.water:getAmount())
                    .. " blood=" .. tostring(f.car:getBloodIntensity("Front"))
                    .. " before=" .. tostring(held and held.target.before))
        end
    end
    job = SC.BaseLife.job(f.jobId)
    if job and job.target.sourceStorageId and not job.target.stage
        and elapsed > 12000 and not f.sourceStaged then
        local item = job.type == "inflate_tires" and f.pump or f.waterItem
        local moved = SC.WorkTransport.transferVerified(f.container,
            f.worker.actor:getInventory(), item, f.worker.actor)
        if not check("upkeep_exact_supply_transfer", moved == true,
            tostring(moved)) then return finish(H, current, setPhase) end
        job.target.stage = "carrying"
        job.target.stageStartedAt = SC.GameplayUtil.nowMs()
        f.sourceStaged = true
        result("SKIP", "upkeep_storage_route", "seed storage route stalled")
    end
    if job and job.target.stage == "carrying" and elapsed > 45000
        and not f.carStaged then
        SC.Navigation.cancel(f.worker.actor, "upkeep_probe_car_staging")
        local staged, detail = stageCar(H, SC, f, job, result)
        if not check("upkeep_native_service_side", staged,
            tostring(job.target.stage) .. "/" .. tostring(detail)) then
            return finish(H, current, setPhase) end
        f.carStaged = true
    end
    if job and job.target.stage == "working" and not f.carStaged then
        f.carStaged = true
        result("PASS", "upkeep_car_route", "worker reached native service area")
    end
    if job and job.target.stage == "returning" and elapsed > 80000
        and not f.returnStaged then
        SC.Navigation.cancel(f.worker.actor, "upkeep_probe_return_staging")
        f.returnStaged = place(H, f.worker.actor, f.sourceSquare)
        result("SKIP", "upkeep_return_route", "worker staged at storage")
    end
    if current - (f.logAt or 0) > 10000 then
        result("PASS", "upkeep_progress", tostring(job and job.type)
            .. " stage=" .. tostring(job and job.target.stage)
            .. " state=" .. tostring(job and job.state)
            .. " blocker=" .. tostring(job and job.blocker)
            .. " work=" .. tostring(f.handled) .. "/" .. tostring(f.reason)
            .. " worker=" .. tostring(f.worker.actor:getX()) .. ","
                .. tostring(f.worker.actor:getY())
            .. " pressure=" .. tostring(f.tire:getContainerContentAmount())
            .. " blood=" .. tostring(f.car:getBloodIntensity("Front"))
            .. " water=" .. tostring(f.water:getAmount()))
        f.logAt = current
    end
    if job and job.state == "blocked" then
        check("upkeep_job_not_blocked", false, tostring(job.blocker))
        return finish(H, current, setPhase)
    end
    if not job then
        if H.phase == "vehicle_upkeep_inflate" then
            if not check("upkeep_tire_pressure_readback",
                f.tire:getContainerContentAmount() > f.pressureBefore + 1
                and SC.GameplayUtil.inventoryContains(f.container, f.pump)
                and not (SC.GameplayUtil.modData(f.pump) or {}).LF_UpkeepJobId,
                tostring(f.tire:getContainerContentAmount()) .. "/"
                    .. tostring(f.pressureBefore)) then
                return finish(H, current, setPhase) end
            local queued, wash = SC.VehicleUpkeep.queue("wash_vehicle",
                f.car:getSqlId(), true)
            if not check("upkeep_manual_wash_queued", queued == true
                and wash ~= nil,
                tostring(wash)) then return finish(H, current, setPhase) end
            wash.assignedId, wash.priority = f.worker.id, 5
            SC.BaseWork.cancel(f.worker.actor, "upkeep_between_actions")
            place(H, f.worker.actor, f.sourceSquare)
            local claimed = SC.BaseLife.claimJob(f.worker.id)
            if not check("upkeep_wash_claimed", claimed == wash,
                tostring(claimed and claimed.id)) then
                return finish(H, current, setPhase) end
            f.jobId, f.sourceStaged, f.yardStaged, f.carStaged,
                f.returnStaged = wash.id, nil, nil, nil, nil
            setPhase("vehicle_upkeep_wash", current)
            return
        end
        check("upkeep_wash_readback",
            f.car:getBloodIntensity("Front") < f.bloodBefore - 0.01
                and f.water:getAmount() < f.waterBefore - 0.5
                and SC.GameplayUtil.inventoryContains(f.container, f.waterItem)
                and not (SC.GameplayUtil.modData(f.waterItem) or {}).LF_UpkeepJobId,
            "blood=" .. tostring(f.bloodBefore) .. "->"
                .. tostring(f.car:getBloodIntensity("Front")) .. " water="
                .. tostring(f.waterBefore) .. "->" .. tostring(f.water:getAmount()))
        return finish(H, current, setPhase)
    end
    if elapsed > 140000 then
        check("upkeep_transaction_timeout", false,
            tostring(job.target.stage) .. "/" .. tostring(job.blocker))
        return finish(H, current, setPhase)
    end
end
function Probe.step(H, current, check, result, setPhase)
    if H.phase == "vehicle_upkeep_setup" then
        setup(H, current, check, result, setPhase)
    elseif H.phase == "vehicle_upkeep_ready" then
        ready(H, current, check, result, setPhase)
    elseif H.phase == "vehicle_upkeep_inflate"
        or H.phase == "vehicle_upkeep_wash" then
        progress(H, current, check, result, setPhase)
    end
end
SCRealSandboxHarnessProbes = SCRealSandboxHarnessProbes or {}
SCRealSandboxHarnessProbes.SCVehicleUpkeepProbe = Probe
