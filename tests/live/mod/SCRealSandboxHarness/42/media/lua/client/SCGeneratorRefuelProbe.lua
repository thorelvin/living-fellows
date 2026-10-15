-- SPDX-License-Identifier: MIT
-- Native generator refueling in an isolated cloned save.
local Probe = {}
local function call(object, method, ...)
    if not object then return nil end
    local ok, value = pcall(function(...) return object[method](object, ...) end, ...)
    return ok and value or nil
end
local function finish(H, current, setPhase)
    setPhase("finish", current)
end
local function workerNearBase(SC)
    for _, record in ipairs(SC.Registry.snapshot() or {}) do
        if record.recruited and record.actor and call(record.actor, "isDead") ~= true
            and SC.BaseLife.withinWorkReach(record.actor) then return record end
    end
end
local function anyWorker(SC)
    for _, record in ipairs(SC.Registry.snapshot() or {}) do
        if record.recruited and record.actor and call(record.actor, "isDead") ~= true then
            return record
        end
    end
end
local function storageNear(SC, worker)
    for _, row in ipairs(SC.BaseLife.storageRows(nil, true)) do
        local container = SC.BaseLife.resolveContainer(row)
        local object = SC.BaseLife.resolveObject(row)
        if container and object and call(object, "getSquare")
            and row.category ~= "memorial" then return row, container end
    end
end
local function generatorSquare(SC, base)
    local U = SC.GameplayUtil
    for _, zone in ipairs(base.zones or {}) do
        if zone.kind == "area" and zone.z == 0 then
            for x = zone.x1 - 6, zone.x2 + 6 do
                for y = zone.y1 - 6, zone.y2 + 6 do
                    local square = U.gridSquare(x, y, 0)
                    if square and call(square, "isOutside") == true
                        and U.isSquareFree(square)
                        and call(square, "getGenerator") == nil
                        and U.distanceSq(base.core, square) > 4 then
                        return square
                    end
                end
            end
        end
    end
end
local function stageWorker(H, actor, target, why)
    local SC = SurvivorCompanion
    local at, squares = SC.GameplayUtil.directInteractionAccess(actor, target)
    if at then return true end
    local square = squares and squares[1]
    if not square then return false, "no_access_square" end
    SC.Navigation.cancel(actor, why)
    local x, y, z = SC.GameplayUtil.position(square)
    return H.placeCombatActor(actor, {
        x = math.floor(x) + 0.5, y = math.floor(y) + 0.5, z = math.floor(z) })
end
local function prepare(H, current, check, result, setPhase)
    local SC = SurvivorCompanion
    local base = SC.BaseLife.active()
    local worker = base and workerNearBase(SC) or nil
    if base and not worker and not H.generatorRefuelTravelAt then
        H.player:teleportTo(base.core.x + 0.5, base.core.y + 0.5, 0)
        H.generatorRefuelTravelAt = current
        return
    end
    if base and not worker and H.generatorRefuelTravelAt
        and current - H.generatorRefuelTravelAt > 3000 then
        local candidate = anyWorker(SC)
        if candidate then
            H.placeCombatActor(candidate.actor, { x = base.core.x + 0.5,
                y = base.core.y + 0.5, z = 0 })
            worker = workerNearBase(SC)
        end
    end
    if not worker and current - H.phaseStartedAt < 18000 then return end
    if not check("generator_base_worker", base ~= nil and worker ~= nil,
        "base=" .. tostring(base and base.id)
            .. " worker=" .. tostring(worker and worker.id)) then
        return finish(H, current, setPhase)
    end
    local storage, container = storageNear(SC, worker)
    if not check("generator_marked_storage", storage ~= nil and container ~= nil,
        tostring(storage and storage.id)) then
        return finish(H, current, setPhase)
    end
    local square = generatorSquare(SC, base)
    if not check("generator_outdoor_square", square ~= nil,
        tostring(square)) then return finish(H, current, setPhase) end
    local item = instanceItem("Base.Generator")
    local generator = item and IsoGenerator.new(item, getCell(), square) or nil
    if generator then
        generator:setConnected(true)
        generator:setFuel(generator:getMaxFuel() * 0.2)
        generator:setActivated(true)
        generator:sync()
    end
    if not check("generator_native_object", generator ~= nil
        and call(square, "getGenerator") == generator,
        tostring(generator)) then return finish(H, current, setPhase) end
    local eligible, eligibilityReason = SC.GeneratorRefuel.eligible(generator, false)
    if not check("generator_live_eligible", eligible == true,
        "reason=" .. tostring(eligibilityReason)
            .. " active=" .. tostring(call(generator, "isActivated"))
            .. " index=" .. tostring(call(generator, "getObjectIndex"))
            .. " fuel=" .. tostring(call(generator, "getFuel"))) then
        return finish(H, current, setPhase)
    end
    local can = call(container, "AddItem", "Base.PetrolCan")
    local fluid = call(can, "getFluidContainer")
    if fluid then
        call(fluid, "adjustAmount", 0)
        call(fluid, "addFluid", Fluid.Petrol, 10)
    end
    storage.reserve = 0
    storage.reserves = storage.reserves or {}
    if can then storage.reserves[SC.GameplayUtil.itemType(can)] = 0 end
    if not check("generator_native_can", can and fluid
        and SC.BaseFuel.gasAmount(can) > 1,
        tostring(fluid and call(fluid, "getAmount"))) then
        return finish(H, current, setPhase)
    end
    local old = SC.BaseLife.jobFor(worker.id)
    if old then SC.BaseLife.cancelJob(old.id) end
    local ordered, orderReason = SC.Commands.issue(worker.id,
        "base_duty", {}, H.player)
    if not check("generator_worker_on_duty", ordered == true,
        tostring(orderReason)) then return finish(H, current, setPhase) end
    SC.Downtime.cancel(worker.actor, "generator_refuel_probe")
    local cancelled, cancelReason = SC.BaseWork.cancel(worker.actor,
        "generator_refuel_probe")
    if not check("generator_worker_free", cancelled == true,
        tostring(cancelReason)) then return finish(H, current, setPhase) end
    local source = SC.BaseLife.resolveObject(storage)
    local placed, placeReason = stageWorker(H, worker.actor, source,
        "generator_storage_staging")
    if not check("generator_worker_at_storage", placed,
        tostring(placeReason)) then return finish(H, current, setPhase) end
    local tiles = 0
    for _, zone in ipairs(base.zones or {}) do
        if zone.kind == "area" then
            tiles = tiles + (zone.x2 - zone.x1 + 13)
                * (zone.y2 - zone.y1 + 13)
        end
    end
    local queued, job
    local passes = math.min(1024, math.ceil(tiles / 256) + 2)
    for _ = 1, passes do
        queued, job = SC.GeneratorRefuel.audit()
        if queued then break end
    end
    if not check("generator_auto_queued", queued == true
        and job.type == "refuel_generator",
        tostring(job and job.id or job) .. " tiles=" .. tostring(tiles)
            .. " passes=" .. tostring(passes)) then
        return finish(H, current, setPhase)
    end
    job.assignedId, job.priority = worker.id, 5
    local claimed, reason = SC.BaseLife.claimJob(worker.id)
    if not check("generator_worker_claimed", claimed == job,
        tostring(reason)) then return finish(H, current, setPhase) end
    H.generatorRefuel = { worker = worker, storage = storage,
        container = container, generator = generator, can = can, fluid = fluid,
        beforeFuel = generator:getFuel(), beforeCan = fluid:getAmount(),
        jobId = job.id, lastLogAt = current }
    result("PASS", "generator_refuel_scene",
        tostring(square:getX()) .. "," .. tostring(square:getY()))
    setPhase("generator_refuel_work", current)
end
local function progress(H, current, check, result, setPhase)
    local SC, f = SurvivorCompanion, H.generatorRefuel
    if current - (f.nextWorkAt or 0) >= 300 then
        f.nextWorkAt = current
        f.handled, f.reason = SC.BaseWork.update(f.worker.actor, H.player, {})
    end
    local job = SC.BaseLife.job(f.jobId)
    local elapsed = current - H.phaseStartedAt
    if job and job.target.stage == "selecting"
        and elapsed > 12000 and not f.sourceStaged then
        local moved = SC.WorkTransport.transferVerified(f.container,
            f.worker.actor:getInventory(), f.can, f.worker.actor)
        if moved then
            job.target.stage = "carrying"
            job.target.stageStartedAt = SC.GameplayUtil.nowMs()
            f.sourceStaged = true
            result("SKIP", "generator_storage_route", "exact can staged")
        end
    end
    if job and job.target.stage == "carrying"
        and elapsed > 24000 and not f.generatorStaged then
        local placed, reason = stageWorker(H, f.worker.actor, f.generator,
            "generator_fuel_staging")
        if not check("generator_native_use_square", placed,
            tostring(reason)) then return finish(H, current, setPhase) end
        f.generatorStaged = true
        result("SKIP", "generator_route", "worker staged at native use square")
    end
    if job and job.target.stage == "returning"
        and elapsed > 50000 and not f.returnStaged then
        local source = SC.BaseLife.resolveObject(f.storage)
        local placed = stageWorker(H, f.worker.actor, source,
            "generator_return_staging")
        if placed then f.returnStaged = true end
    end
    if current - (f.lastLogAt or 0) >= 8000 then
        result("PASS", "generator_refuel_progress",
            "stage=" .. tostring(job and job.target.stage)
                .. " blocker=" .. tostring(job and job.blocker)
                .. " fuel=" .. tostring(f.generator:getFuel())
                .. " can=" .. tostring(f.fluid:getAmount())
                .. " work=" .. tostring(f.handled) .. "/" .. tostring(f.reason))
        f.lastLogAt = current
    end
    if job and job.state == "blocked" then
        check("generator_job_not_blocked", false, tostring(job.blocker))
        return finish(H, current, setPhase)
    end
    if not job and SC.GameplayUtil.inventoryContains(f.container, f.can) then
        local gain = f.generator:getFuel() - f.beforeFuel
        local loss = f.beforeCan - f.fluid:getAmount()
        check("generator_native_fuel_transfer", gain > 0.2 and loss > 0.5
            and f.generator:isActivated() == (f.manual ~= true)
            and (SC.GameplayUtil.modData(f.can) or {}).LF_RefuelJobId == nil,
            "generator+=" .. tostring(gain) .. " can-=" .. tostring(loss))
        if not f.manual then
            f.generator:setActivated(false)
            f.generator:setFuel(f.generator:getMaxFuel() * 0.7)
            f.generator:sync()
            f.fluid:addFluid(Fluid.Petrol, 8)
            local queued, manual = SC.GeneratorRefuel.queue(f.generator, true)
            if not check("generator_manual_queued", queued == true
                and manual.target.manual == true,
                tostring(manual and manual.id or manual)) then
                return finish(H, current, setPhase)
            end
            manual.assignedId, manual.priority = f.worker.id, 5
            local source = SC.BaseLife.resolveObject(f.storage)
            stageWorker(H, f.worker.actor, source, "generator_manual_staging")
            local claimed, claimReason = SC.BaseLife.claimJob(f.worker.id)
            if not check("generator_manual_claimed", claimed == manual,
                tostring(claimReason)) then return finish(H, current, setPhase) end
            f.manual, f.jobId = true, manual.id
            f.beforeFuel, f.beforeCan = f.generator:getFuel(),
                f.fluid:getAmount()
            f.sourceStaged, f.generatorStaged, f.returnStaged = nil, nil, nil
            f.lastLogAt = current
            setPhase("generator_refuel_manual_work", current)
            return
        end
        return finish(H, current, setPhase)
    end
    if elapsed > 120000 then
        check("generator_refuel_timeout", false,
            "stage=" .. tostring(job and job.target.stage)
                .. " reason=" .. tostring(f.reason))
        finish(H, current, setPhase)
    end
end
function Probe.step(H, current, check, result, setPhase)
    if H.phase == "generator_refuel_setup" then
        prepare(H, current, check, result, setPhase)
    elseif H.phase == "generator_refuel_work"
        or H.phase == "generator_refuel_manual_work" then
        progress(H, current, check, result, setPhase)
    end
end
SCRealSandboxHarnessProbes = SCRealSandboxHarnessProbes or {}
SCRealSandboxHarnessProbes.SCGeneratorRefuelProbe = Probe
