-- SPDX-License-Identifier: MIT
-- Disposable-save latency checks. The production decision cadence, navigation,
-- farming, hauling and timed actions remain in control after fixture setup.
local Probe = {}
SCRealSandboxHarnessProbes = SCRealSandboxHarnessProbes or {}
SCRealSandboxHarnessProbes.SCBaseJobLatencyProbe = Probe

local function call(object, method, ...)
    if not object then return nil end
    local ok, value = pcall(function(...) return object[method](object, ...) end, ...)
    if ok then return value end
end

local function at(object)
    return string.format("%.2f:%.2f:%s", tonumber(call(object, "getX")) or -1,
        tonumber(call(object, "getY")) or -1, tostring(call(object, "getZ")))
end

local function emit(label, value)
    print("SC_REAL_SANDBOX|BASE_JOB_LATENCY|" .. label .. " " .. tostring(value))
end

local function boardCount(object)
    local most = 0
    for _, method in ipairs({ "getBarricadeOnSameSquare", "getBarricadeOnOppositeSquare" }) do
        most = math.max(most, tonumber(call(call(object, method), "getNumPlanks")) or 0)
    end
    return most
end

local function fillCan(inventory)
    local item = call(inventory, "AddItem", "Base.WateredCan")
    local fluid = call(item, "getFluidContainer")
    if fluid then
        call(fluid, "empty")
        call(fluid, "addFluid", Fluid.Water, call(fluid, "getCapacity"))
    else call(item, "setUsedDelta", 1) end
    return item
end

local function plantOn(square, server)
    local system = server and SFarmingSystem or CFarmingSystem
    return system and call(system.instance, "getLuaObjectOnSquare", square)
end

local function graveOn(SC, square, part)
    local found
    SC.GameplayUtil.squareObjects(square, function(object)
        local data = call(object, "getModData")
        if call(object, "getName") == "EmptyGraves" and data and data.spriteType == part
            and (tonumber(data.corpses) or 0) == 0 and data.filled ~= true then found = object end
        return found == nil
    end, 64)
    return found
end

local function ensureGrave(SC, actor, zone)
    local U = SC.GameplayUtil
    for y = zone.y1, zone.y2 do for x = zone.x1, zone.x2 do
        local square = U.gridSquare(x, y, zone.z)
        local grave = square and graveOn(SC, square, "sprite1")
        if grave then return grave end
    end end
    local tool = actor:getInventory():AddItem("Base.Shovel")
    local builder = ISEmptyGraves:new("location_community_cemetary_01_33",
        "location_community_cemetary_01_32", "location_community_cemetary_01_34",
        "location_community_cemetary_01_35", tool)
    builder.character, builder.player, builder.north = actor, actor:getPlayerNum(), false
    for y = zone.y1, zone.y2 do for x = zone.x1 + 1, zone.x2 do
        local square, partner = U.gridSquare(x, y, zone.z), U.gridSquare(x - 1, y, zone.z)
        if square and partner and U.isSquareFree(square) and U.isSquareFree(partner)
            and not call(square, "getRoom") and not call(partner, "getRoom")
            and not U.squareOccupyingObject(square) and not U.squareOccupyingObject(partner)
            and builder:isValid(square) then
            local primary, secondary = actor:getPrimaryHandItem(), actor:getSecondaryHandItem()
            actor:setPrimaryHandItem(tool) actor:setSecondaryHandItem(tool)
            builder:create(x, y, zone.z, false, "location_community_cemetary_01_33")
            actor:setPrimaryHandItem(primary) actor:setSecondaryHandItem(secondary)
            actor:getInventory():Remove(tool)
            return graveOn(SC, square, "sprite1")
        end
    end end
    actor:getInventory():Remove(tool)
end

local function traceActor(SC, label, record)
    local actor = record.actor
    local decision, nav = SC.Decision.peek(actor) or {}, SC.Navigation.status(actor) or {}
    local command = SC.Commands.peek(actor) or {}
    local job = SC.BaseLife.jobFor(record.id)
    local runtime = SC.GameplayUtil.peekActorState(actor) or {}
    local farm = SC.FarmWork.summary()
    emit(label, "at=" .. at(actor) .. " physical=" .. at(call(actor, "getCurrentSquare"))
        .. " order=" .. tostring(command.order) .. " decision=" .. tostring(decision.current)
        .. " intent=" .. tostring(decision.intent) .. " job=" .. tostring(job and job.id)
        .. "/" .. tostring(job and job.type) .. "/" .. tostring(job and job.blocker)
        .. " nav=" .. tostring(nav.action) .. "/" .. tostring(nav.lastMovementReason)
        .. " goal=" .. tostring(nav.target) .. " searchAge=" .. tostring(nav.pathSearchAgeMs)
        .. " expanded=" .. tostring(nav.expandedNodes) .. " slice=" .. tostring(nav.searchSliceBudgetMs)
        .. " blocker=" .. tostring(nav.blockerType) .. " native=" .. tostring(SC.NativeActions.workKind(actor))
        .. " drag=" .. tostring(SC.NativeActions.isDraggingCorpse(actor))
        .. " health=" .. tostring(call(actor, "getHealth"))
        .. " farmActive=" .. tostring(farm.active))
    if job and job.target then emit(label .. "_target", tostring(job.target.operation)
        .. " " .. tostring(job.target.x) .. ":" .. tostring(job.target.y)) end
    local pending = (SC.Navigation.peek(actor) or {}).pathSearch
    local rejected = pending and pending.route and pending.route.search and pending.route.search.rejections
    if rejected then for reason, count in pairs(rejected) do
        emit(label .. "_reject", tostring(reason) .. "=" .. tostring(count))
    end end
    if label == "farmer" then
        local load = SC.Logistics.status(actor)
        local surplus = load and load.surplus
        emit("farmer_load", "overloaded=" .. tostring(load and load.overloaded)
            .. " gear=" .. tostring(load and load.carryGearRatio)
            .. " surplus=" .. tostring(surplus and SC.GameplayUtil.itemType(surplus.item)))
    end
end

local function setup(H, SC, current, check, result, setPhase)
    if current - H.phaseStartedAt < 6000 then return end
    local base = SC.BaseLife.active()
    local rows, named = {}, {}
    for _, record in ipairs(SC.Registry.snapshot() or {}) do
        if record.recruited == true and record.actor and call(record.actor, "getCurrentSquare") then
            rows[#rows + 1] = record
            local name = tostring(SC.GameplayUtil.nameOf(record.actor) or record.name or "")
            named[name:match("^(%S+)") or name] = record
            emit("resident", "id=" .. tostring(record.id) .. " name=" .. name .. " at=" .. at(record.actor))
        end
    end
    if not check("latency_camp_and_three_workers", base and #rows >= 3,
        "loaded=" .. #rows .. " sourceVersion=" .. tostring(SC.VERSION or SC.version)) then
        setPhase("finish", current) return
    end
    local fixture = { base = base, startedAt = current, plots = {}, excluded = {} }
    H.baseJobLatency = fixture
    fixture.farmer = named.Tess or rows[1]
    fixture.keeper = named.Jill or rows[2]
    fixture.maintainer = named.Sanghwa or rows[3]
    local selected = { [fixture.farmer.id] = "farmer", [fixture.keeper.id] = "corpsekeeper",
        [fixture.maintainer.id] = "maintainer" }
    -- Use the same public cancellation/assignment paths as player orders. Do
    -- not erase receipts, production cargo or native queues behind their backs.
    for _, record in ipairs(rows) do
        if selected[record.id] then
            SC.Downtime.cancel(record.actor, "latency_fixture")
            local released, releaseReason = SC.BaseWork.cancel(record.actor, "latency_fixture")
            if not check("latency_release_" .. selected[record.id], released == true, tostring(releaseReason)) then
                setPhase("finish", current) return
            end
            local cancelled, reason = SC.Decision.cancelWork(record.actor, "latency_fixture")
            if not check("latency_cancel_" .. selected[record.id], cancelled == true, tostring(reason)) then
                setPhase("finish", current) return
            end
            SC.BaseLife.assign(record.id, selected[record.id], true)
            SC.Commands.issue(record.id, "base_duty", nil, H.player)
        end
    end
    SC.BaseLife.setPolicy("workOutsideAtNight", true)
    -- Stable daylight permits the normal farming auditor, rather than calling
    -- FarmWork.update directly or replacing the decision controller.
    getGameTime():setTimeOfDay(12)
    for _, zone in ipairs(base.zones or {}) do
        emit("zone", tostring(zone.id) .. " " .. tostring(zone.kind) .. " "
            .. zone.x1 .. ":" .. zone.y1 .. "-" .. zone.x2 .. ":" .. zone.y2 .. ":" .. zone.z)
        if zone.kind == "burial" then fixture.burial = fixture.burial or zone end
        if zone.kind == "farm" then
            for y = zone.y1, zone.y2 do for x = zone.x1, zone.x2 do
                local square = SC.GameplayUtil.gridSquare(x, y, zone.z)
                local plant, server = plantOn(square), plantOn(square, true)
                if plant and server and (tonumber(plant.waterNeeded) or 0) > 0
                    and plant.state == "seeded" and #fixture.plots < 12 then
                    server.waterLvl, plant.waterLvl = 0, 0
                    server:stateToIsoObject(server:getIsoObject())
                    fixture.plots[#fixture.plots + 1] = { square = square, plant = plant, server = server }
                end
            end end
        end
    end
    fixture.can = fillCan(fixture.farmer.actor:getInventory())
    check("latency_carried_watering_can", #fixture.plots == 12 and fixture.can ~= nil
        and (tonumber(call(call(fixture.can, "getFluidContainer"), "getAmount")) or 0) > 0,
        "plots=" .. #fixture.plots
        .. " can=" .. tostring(call(fixture.can, "getFullType")) .. " water="
        .. tostring(call(call(fixture.can, "getFluidContainer"), "getAmount")))
    -- Select the exact reported front window, while leaving map geometry intact.
    local windowSquare = SC.GameplayUtil.gridSquare(12034, 6748, 0)
    if windowSquare then SC.GameplayUtil.squareObjects(windowSquare, function(object)
        if instanceof(object, "IsoWindow") then fixture.window = object end
        return true
    end, 64) end
    local registered, target
    if fixture.window then registered, target = SC.BaseLife.registerMaintenanceTarget(fixture.window, "barricade") end
    if fixture.window and registered then
        emit("window", "north=" .. tostring(call(fixture.window, "getNorth"))
            .. " object=" .. tostring(call(fixture.window, "getSpriteName")))
        for _, side in ipairs({ "same", "opposite" }) do
            local square, reason = SC.Navigation.barricadeWorkSquare(fixture.maintainer.actor,
                fixture.window, windowSquare, side, { workCampOnly = true, workReach = true })
            local x, y, z = call(square, "getX"), call(square, "getY"), call(square, "getZ")
            local nativeStand = x and call(fixture.maintainer.actor, "canStandAt", x + 0.5, y + 0.5, z)
            emit("window_side", side .. " at=" .. at(square) .. " reason=" .. tostring(reason)
                .. " room=" .. tostring(call(call(square, "getRoom"), "getName"))
                .. " nativeCanStand=" .. tostring(nativeStand))
            if square then SC.GameplayUtil.squareObjects(square, function(object)
                emit("window_object", side .. " name=" .. tostring(call(object, "getObjectName"))
                    .. " sprite=" .. tostring(call(object, "getSpriteName"))
                    .. " surface=" .. tostring(call(object, "getSurfaceOffset")))
                return true
            end, 48) end
        end
        for dy = -1, 1 do for dx = -1, 1 do
            local square = SC.GameplayUtil.gridSquare(12034 + dx, 6748 + dy, 0)
            emit("front_geometry", at(square) .. " free=" .. tostring(call(square, "isFree", true))
                .. " staticFree=" .. tostring(SC.GameplayUtil.isSquareFree(square))
                .. " furniture=" .. tostring(SC.GameplayUtil.squareOccupyingObject(square))
                .. " room=" .. tostring(call(call(square, "getRoom"), "getName")))
            if dx ~= 0 or dy ~= 0 then
                local edge = SC.Topology.classifyEdge(fixture.maintainer.actor, square, windowSquare,
                    { actor = fixture.maintainer.actor })
                emit("front_edge", at(square) .. " kind=" .. tostring(edge and edge.affordance)
                    .. " traversable=" .. tostring(edge and edge.traversable) .. " reason=" .. tostring(edge and edge.reason))
            end
        end end
        fixture.windowBefore = boardCount(fixture.window)
        for _, row in ipairs(base.maintenanceTargets or {}) do
            if row.kind == "barricade" and row.id ~= target.id then
                SC.BaseLife.setMaintenanceTargetEnabled(row.id, false)
            end
        end
        for _, row in ipairs(base.storages or {}) do
            if SC.BaseLife.withdrawable(row) then
                local container = SC.BaseLife.resolveContainer(row)
                if container and row.z == 0 and math.abs(row.x - 12034) + math.abs(row.y - 6748) <= 24 then
                    fixture.supply = row
                    container:AddItem("Base.Hammer")
                    for _ = 1, 8 do container:AddItem("Base.Plank") end
                    for _ = 1, 16 do container:AddItem("Base.Nails") end
                    break
                end
            end
        end
        local job
        for _, candidate in ipairs(base.jobs or {}) do
            if candidate.type == "barricade" and candidate.target.maintenanceId == target.id
                and candidate.state ~= "completed" and candidate.state ~= "cancelled" then job = candidate break end
        end
        if not job then
            local made, queued = SC.BaseLife.enqueueJob({ type = "barricade", priority = 5,
                assignedId = fixture.maintainer.id, target = {
                    x = target.x, y = target.y, z = target.z,
                    maintenanceId = target.id, objectIndex = target.objectIndex,
                    objectId = target.objectId, objectSignature = target.objectSignature,
                    north = call(fixture.window, "getNorth") == true,
                } })
            if made then job = queued end
        end
        if job then job.assignedId, job.priority = fixture.maintainer.id, 5 end
        fixture.windowJob = job
        check("latency_front_window_job", job ~= nil, tostring(job and job.id))
        fixture.windowTarget = target
    end
    check("latency_front_window_fixture", fixture.window ~= nil and registered == true,
        "at=12034:6748 before=" .. tostring(fixture.windowBefore) .. " target=" .. tostring(target and target.id))
    -- Reversible exclusions keep the requested body first in the real scan.
    local seen = {}
    for _, zone in ipairs(base.zones or {}) do
        if zone.kind == "area" or zone.kind == "burial" or zone.kind == "lumber" then
            for y = zone.y1, zone.y2 do for x = zone.x1, zone.x2 do
                local square = SC.GameplayUtil.gridSquare(x, y, zone.z)
                local bodies = call(square, "getStaticMovingObjects")
                for i = 0, (tonumber(call(bodies, "size")) or 0) - 1 do
                    local body = bodies:get(i)
                    if instanceof(body, "IsoDeadBody") and not seen[body] then
                        local data = body:getModData()
                        seen[body] = true
                        fixture.excluded[#fixture.excluded + 1] = { data = data, old = data[SC.Production.BURNED_TAG] }
                        data[SC.Production.BURNED_TAG] = "latency_fixture_excluded"
                    end
                end
            end end
        end
    end
    if fixture.burial then
        fixture.grave = ensureGrave(SC, fixture.keeper.actor, fixture.burial)
        local square, stand
        for _, point in ipairs({ { 12033, 6744 }, { 12032, 6745 }, { 12030, 6744 }, { 12029, 6743 } }) do
            local candidate = SC.GameplayUtil.gridSquare(point[1], point[2], 0)
            if candidate and call(candidate, "getRoom") and SC.GameplayUtil.isSquareFree(candidate)
                and not SC.GameplayUtil.squareOccupyingObject(candidate)
                and not SC.GameplayUtil.movingBlocker(candidate, fixture.keeper.actor) then
                local targets = SC.Navigation.interactionTargets(fixture.keeper.actor, candidate,
                    { cardinalOnly = true, requireDirectAccess = true })
                for _, target in ipairs(targets) do
                    if SC.Navigation.standingSquareClear(fixture.keeper.actor, target)
                        and call(fixture.keeper.actor, "canStandAt", target:getX() + 0.5, target:getY() + 0.5, 0) == true then
                        square, stand = candidate, target break
                    end
                end
            end
            if stand then break end
        end
        if square and stand then
            local bx, by = square:getX() + 0.5, square:getY() + 0.5
            local zombie = createZombie(bx, by, 0, nil, 0, IsoDirections.S)
            fixture.body = zombie and IsoDeadBody.new(zombie, false)
            if fixture.body then
                fixture.body:setX(bx)
                fixture.body:setY(by)
                fixture.keeperStand = stand
            end
        end
        if fixture.body and fixture.grave then
            local made, order = SC.BaseLife.createProductionOrder({ operation = "collect_bodies",
                zoneId = fixture.burial.id, requested = 1, workers = { fixture.keeper.id },
                settings = { fromCamp = true, fromLumber = true, withBelongings = true } })
            if made then
                fixture.order = order
                for _, job in ipairs(base.jobs or {}) do
                    if job.type == "production" and job.target.orderId == order.id then job.priority = 5 end
                end
            end
        end
    end
    if not check("latency_corpse_fixture", fixture.body ~= nil and fixture.grave ~= nil and fixture.order ~= nil,
        "body=" .. at(fixture.body) .. " grave=" .. at(call(fixture.grave, "getSquare"))
            .. " order=" .. tostring(fixture.order and fixture.order.id)) then
        setPhase("finish", current) return
    end
    if H.config.base_job_latency_natural == "true" then
        emit("setup", "realDecision=true decisionCadenceUnchanged=true initialFixtureStaging=false noWorkerTeleport=true")
        fixture.startedAt = current
        setPhase("base_job_latency_observe", current)
        return
    end
    -- Isolate action/doorway latency from the clone's pre-existing inventory
    -- errands and actors sharing the corpse's initial tile. Staging is only a
    -- fixture operation; require native physics to settle before timing work.
    fixture.stages = {
        { record = fixture.farmer, x = 12038.5, y = 6727.5, role = "farmer" },
        { record = fixture.maintainer, x = 12035.5, y = 6750.5, role = "maintainer" },
        { record = fixture.keeper, x = fixture.keeperStand:getX() + 0.5,
            y = fixture.keeperStand:getY() + 0.5, role = "corpsekeeper" },
    }
    for _, stage in ipairs(fixture.stages) do
        local actor = stage.record.actor
        SC.Decision.cancelWork(actor, "latency_staging")
        SC.Commands.issue(stage.record.id, "stay", {}, H.player)
        local staged, reason = H.placeCombatActor(actor, { x = stage.x, y = stage.y, z = 0 })
        if not check("latency_stage_" .. stage.role, staged == true, tostring(reason)) then
            setPhase("finish", current) return
        end
    end
    for _, record in ipairs(rows) do
        if not selected[record.id] then
            SC.Decision.cancelWork(record.actor, "latency_other_worker")
            SC.Commands.issue(record.id, "stay", {}, H.player)
            local placed, reason = H.placeCombatActor(record.actor, { x = 12029.5, y = 6744.5, z = 0 })
            check("latency_other_worker_clear", placed == true, tostring(reason))
        end
    end
    -- Supply gathering already has its own natural baseline above. This
    -- window control measures access and native plank placement themselves.
    local inventory = fixture.maintainer.actor:getInventory()
    inventory:AddItem("Base.Hammer")
    for _ = 1, 4 do inventory:AddItem("Base.Plank") end
    for _ = 1, 8 do inventory:AddItem("Base.Nails") end
    fixture.stagedAt = current
    emit("setup", "realDecision=true decisionCadenceUnchanged=true initialFixtureStaging=true noTeleportDuringWork=true")
    setPhase("base_job_latency_staged", current)
end

function Probe.step(H, current, check, result, setPhase)
    local SC = SurvivorCompanion
    if H.phase == "base_job_latency_setup" then return setup(H, SC, current, check, result, setPhase) end
    local f = H.baseJobLatency
    if not f then setPhase("finish", current) return end
    if H.phase == "base_job_latency_staged" then
        if current - f.stagedAt < 500 then return end
        for _, stage in ipairs(f.stages) do
            local actor = stage.record.actor
            local square = call(actor, "getCurrentSquare")
            local correct = math.abs(actor:getX() - stage.x) <= 0.1
                and math.abs(actor:getY() - stage.y) <= 0.1
                and square == SC.GameplayUtil.gridSquare(stage.x, stage.y, 0)
            if not correct and current - f.stagedAt < 3000 then return end
            if not check("latency_physical_stage_" .. stage.role, correct,
                "actor=" .. at(actor) .. " physical=" .. at(square)) then setPhase("finish", current) return end
        end
        for _, stage in ipairs(f.stages) do
            SC.BaseLife.assign(stage.record.id, stage.role, true)
            SC.Commands.issue(stage.record.id, "base_duty", nil, H.player)
        end
        local admitted, job = SC.FarmWork.audit(f.base)
        check("latency_farm_carried_admission", admitted == true and job.assignedId == f.farmer.id,
            "result=" .. tostring(job and job.id or job) .. " carried="
                .. tostring(SC.FarmWork.carriedWaterContainer(f.farmer.actor, true) ~= nil))
        f.startedAt = current
        setPhase("base_job_latency_observe", current)
        return
    end
    local elapsed = current - f.startedAt
    local moveObserverAfter = math.max(0, math.min(300000,
        (tonumber(H.config.base_job_latency_observer_move_seconds) or 120) * 1000))
    if elapsed >= moveObserverAfter and H.config.base_job_latency_move_observer == "true" and not f.observerMovedAt then
        local square = SC.GameplayUtil.gridSquare(12027, 6753, 0)
        if not check("latency_observer_clear_tile", square and SC.GameplayUtil.isSquareFree(square)
            and not SC.GameplayUtil.squareOccupyingObject(square), at(square)) then setPhase("finish", current) return end
        local before = at(H.player)
        H.player:teleportTo(12027.5, 6753.5, 0)
        f.observerMovedAt = elapsed
        result("PASS", "latency_observer_moved_control", "from=" .. before .. " to=" .. at(H.player)
            .. " atMs=" .. elapsed .. " companionsUntouched=true")
    end
    local watered = 0
    for _, row in ipairs(f.plots) do
        if math.max(tonumber(row.plant.waterLvl) or 0, tonumber(row.server.waterLvl) or 0) > 0 then
            watered = watered + 1
        end
    end
    if watered > 0 and not f.waterAt then
        f.waterAt = elapsed
        result("PASS", "latency_first_water", "afterMs=" .. elapsed .. " watered=" .. watered)
    end
    local planks = f.window and boardCount(f.window) or 0
    if planks > (f.windowBefore or 0) and not f.plankAt then
        f.plankAt = elapsed
        result("PASS", "latency_front_window_first_plank", "afterMs=" .. elapsed .. " boards=" .. planks)
    end
    local corpses = tonumber((call(f.grave, "getModData") or {}).corpses) or 0
    if corpses > 0 and not f.buriedAt then
        f.buriedAt = elapsed
        result("PASS", "latency_body_buried", "afterMs=" .. elapsed .. " corpses=" .. corpses)
    end
    if current >= (f.nextTraceAt or 0) then
        f.nextTraceAt = current + 5000
        emit("progress", "elapsedMs=" .. elapsed .. " watered=" .. watered .. "/" .. #f.plots
            .. " boards=" .. planks .. " corpses=" .. corpses)
        traceActor(SC, "farmer", f.farmer)
        traceActor(SC, "maintainer", f.maintainer)
        traceActor(SC, "keeper", f.keeper)
        if f.order then emit("order", tostring(f.order.state) .. "/" .. tostring(f.order.blocker)
            .. " completed=" .. tostring(f.order.completed)) end
        for _, job in ipairs(f.base.jobs or {}) do
            if job.state ~= "cancelled" and job.state ~= "completed"
                and (job.type == "farm" or job.type == "barricade" or job.type == "production") then
                emit("job", tostring(job.id) .. "/" .. tostring(job.type) .. "/" .. tostring(job.state)
                    .. "/" .. tostring(job.blocker) .. " owner=" .. tostring(job.reservedBy)
                    .. " assigned=" .. tostring(job.assignedId))
            end
        end
    end
    if elapsed >= 45000 and not f.stockCanAttempted then
        local storage = SC.BaseLife.storageRows("farming", true)[1]
            or SC.BaseLife.storageRows("water", true)[1]
        local container = storage and SC.BaseLife.resolveContainer(storage)
        if container then
            f.stockCan = fillCan(container) or false
            check("latency_stored_can_control", f.stockCan ~= false, "atMs=" .. elapsed .. " storage=" .. storage.id
                .. " category=" .. storage.category .. " carriedWater="
                .. tostring(call(call(f.can, "getFluidContainer"), "getAmount")))
        else f.stockCan = false result("FAIL", "latency_stored_can_control", "no permitted farming/water storage") end
        f.stockCanAttempted = true
    end
    if elapsed >= 45000 and H.config.base_job_latency_clear_window == "true" and not f.benchCleared then
        f.benchCleared = true
        local job = f.windowJob and SC.BaseLife.job(f.windowJob.id)
        check("latency_front_window_explained", job and job.state == "blocked"
            and job.blocker == "work_side_blocked", "state=" .. tostring(job and job.state)
                .. " reason=" .. tostring(job and job.blocker) .. " beforeAnyLayoutChange=true")
        local square = call(f.window, "getSquare")
        local bench
        if square then SC.GameplayUtil.squareObjects(square, function(object)
            if call(object, "getSpriteName") == "furniture_seating_outdoor_01_17"
                and call(object, "getContainer") == nil then bench = object end
            return true
        end, 48) end
        if bench then
            square:RemoveTileObject(bench)
            square:RecalcProperties()
            square:RecalcAllWithNeighbours(true)
            check("latency_front_window_bench_control", call(bench, "getObjectIndex") == -1,
                "onlyOneInventorylessBenchRemoved=true sourceSaveUntouched=true")
            local retried, reason = SC.BaseLife.retryJob(job.id)
            check("latency_front_window_retry", retried == true, tostring(reason))
        else result("FAIL", "latency_front_window_bench_control", "reported bench missing") end
    end
    local deadline = math.max(30000, math.min(600000,
        (tonumber(H.config.base_job_latency_seconds) or 300) * 1000))
    if (f.waterAt and f.plankAt and f.buriedAt and elapsed > 90000) or elapsed >= deadline then
        check("latency_water_progress", f.waterAt ~= nil, "firstWaterMs=" .. tostring(f.waterAt))
        check("latency_front_window_progress", f.plankAt ~= nil, "firstPlankMs=" .. tostring(f.plankAt))
        check("latency_burial_progress", f.buriedAt ~= nil, "buriedMs=" .. tostring(f.buriedAt))
        for _, row in ipairs(f.excluded) do row.data[SC.Production.BURNED_TAG] = row.old end
        setPhase("finish", current)
    end
end

return Probe
