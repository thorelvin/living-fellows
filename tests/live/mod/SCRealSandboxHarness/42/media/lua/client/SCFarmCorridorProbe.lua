-- SPDX-License-Identifier: MIT
-- Disposable-save proof of real farm reach and one-tile hallway clearance.
SCRealSandboxHarnessProbes = SCRealSandboxHarnessProbes or {}
local Probe = {}
SCRealSandboxHarnessProbes.SCFarmCorridorProbe = Probe

local function call(object, method, ...)
    if not object then return nil end
    local ok, value = pcall(function(...) return object[method](object, ...) end, ...)
    return ok and value or nil
end

local function position(value)
    local x, y, z = call(value, "getX"), call(value, "getY"), call(value, "getZ")
    return tonumber(x), tonumber(y), tonumber(z) or 0
end

local function fluid(item)
    local container = call(item, "getFluidContainer")
    return tonumber(call(container, "getAmount")) or 0
end

local function useLane(SC, actor, object)
    local U = SC.GameplayUtil
    local x, y, z = position(U.squareOf(object))
    if not x then return nil end
    for _, step in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
        local near = U.gridSquare(x + step[1], y + step[2], z)
        local far = U.gridSquare(x + step[1] * 2, y + step[2] * 2, z)
        if near and far and U.isSquareFree(near) and U.isSquareFree(far)
            and not U.squareOccupyingObject(near)
            and not U.edgeBlocked(near, far)
            and not U.edgeBlocked(near, U.squareOf(object)) then
            local targets = SC.Navigation.interactionTargets(actor, object,
                { cardinalOnly = true, requireDirectAccess = true })
            for _, target in ipairs(targets) do
                if U.sameSquare(target, near) then
                    return { square = U.squareOf(object), object = object,
                        near = near, far = far }
                end
            end
        end
    end
    return nil
end

local function waterFixtureLabel(object)
    local sprite = call(object, "getSprite")
    return tostring(call(object, "getObjectName") or "") .. "/"
        .. tostring(call(object, "getSpriteName")
            or call(sprite, "getName") or "")
end

local function fixtures(SC, actor)
    local U = SC.GameplayUtil
    local base = SC.BaseLife.active()
    local source, bathtub, crop
    local farming = type(CFarmingSystem) == "table" and CFarmingSystem.instance or nil
    local checked = 0
    for _, zone in ipairs(base and base.zones or {}) do
        if zone.kind == "area" or zone.kind == "farm" then
            for y = zone.y1, zone.y2 do for x = zone.x1, zone.x2 do
                checked = checked + 1
                if checked > 1200 then break end
                local square = U.gridSquare(x, y, zone.z)
                if square and not crop and farming then
                    local plant = call(farming, "getLuaObjectOnSquare", square)
                    if plant and (tonumber(plant.waterLvl) or 0) < 90 then
                        local lane = useLane(SC, actor, square)
                        if lane then lane.plant = plant crop = lane end
                    end
                end
                if square and not bathtub then
                    U.squareObjects(square, function(object)
                        if call(object, "hasFluid") == true
                            and (tonumber(call(object, "getFluidAmount")) or 0) > 1 then
                            local lane = useLane(SC, actor, object)
                            if lane then
                                lane.label = waterFixtureLabel(object)
                                local label = string.lower(lane.label)
                                if string.find(label, "bath", 1, true)
                                    or string.find(label, "tub", 1, true) then
                                    bathtub = lane
                                elseif not source then source = lane end
                            end
                        end
                        return true
                    end, 48)
                end
            end if checked > 1200 then break end end
        end
        if checked > 1200 then break end
    end
    return bathtub or source, crop, checked, bathtub ~= nil
end

local function corridor(SC, actor, requester)
    local U = SC.GameplayUtil
    local px, py, pz = position(actor)
    if not px then return nil end
    local best, linear, narrow, bays = nil, 0, 0, 0
    for radius = 0, 40 do
        for dx = -radius, radius do for dy = -radius, radius do
            if math.max(math.abs(dx), math.abs(dy)) == radius then
                for _, axis in ipairs({ { 1, 0 }, { 0, 1 } }) do
                    local x, y, z = math.floor(px) + dx,
                        math.floor(py) + dy, math.floor(pz)
                    local run = {}
                    local valid = true
                    for n = 0, 5 do
                        local square = U.gridSquare(x + n * axis[1],
                            y + n * axis[2], z)
                        if not square or not U.isSquareFree(square)
                            or not call(square, "getRoom")
                            or (n > 0 and U.edgeBlocked(run[n], square)) then
                            valid = false break
                        end
                        run[n + 1] = square
                        if n >= 1 and n <= 4 then
                            local left = U.gridSquare(x + n * axis[1] - axis[2],
                                y + n * axis[2] + axis[1], z)
                            local right = U.gridSquare(x + n * axis[1] + axis[2],
                                y + n * axis[2] - axis[1], z)
                            if (left and U.isSquareFree(left)
                                    and not U.edgeBlocked(square, left))
                                or (right and U.isSquareFree(right)
                                    and not U.edgeBlocked(square, right)) then
                                valid = false break
                            end
                        end
                    end
                    if valid then
                        narrow = narrow + 1
                        local bay
                        for _, side in ipairs({ -1, 1 }) do
                            local endX, endY = x + 5 * axis[1], y + 5 * axis[2]
                            local square = U.gridSquare(endX + side * axis[2],
                                endY - side * axis[1], z)
                            if square and U.isSquareFree(square)
                                and not U.edgeBlocked(run[6], square) then
                                bay = square break
                            end
                        end
                        if bay then
                            bays = bays + 1
                            best = { run = run, bay = bay }
                            return best
                        end
                    elseif #run >= 6 then
                        linear = linear + 1
                    end
                end
            end
        end end
    end
    return best, "linear=" .. tostring(linear)
        .. " narrow=" .. tostring(narrow) .. " bays=" .. tostring(bays)
end

local function actualChoke(SC, actor)
    local U = SC.GameplayUtil
    local px, py, pz = position(actor)
    if not px then return nil end
    local z = math.floor(pz)
    local function ghost(square)
        local x, y = position(square)
        return { getX = function() return x + 0.5 end,
            getY = function() return y + 0.5 end,
            getZ = function() return z end,
            getSquare = function() return square end }
    end
    for radius = 0, 40 do
        for ox = -radius, radius do for oy = -radius, radius do
            if math.max(math.abs(ox), math.abs(oy)) == radius then
                local x, y = math.floor(px) + ox, math.floor(py) + oy
                for _, direction in ipairs({ { 1, 0 }, { -1, 0 },
                        { 0, 1 }, { 0, -1 } }) do
                    local dx, dy = direction[1], direction[2]
                    local retreat = U.gridSquare(x - dx, y - dy, z)
                    local start = U.gridSquare(x, y, z)
                    local blocker = U.gridSquare(x + dx, y + dy, z)
                    local after = U.gridSquare(x + dx * 2, y + dy * 2, z)
                    local goal = U.gridSquare(x + dx * 3, y + dy * 3, z)
                    if retreat and start and blocker and after and goal
                        and U.isSquareFree(retreat) and U.isSquareFree(start)
                        and U.isSquareFree(blocker) and U.isSquareFree(after)
                        and U.isSquareFree(goal)
                        and not U.edgeBlocked(retreat, start)
                        and not U.edgeBlocked(start, blocker)
                        and not U.edgeBlocked(blocker, after)
                        and not U.edgeBlocked(after, goal) then
                        local sideA = U.gridSquare(x + dx - dy, y + dy + dx, z)
                        local sideB = U.gridSquare(x + dx + dy, y + dy - dx, z)
                        local blockedA = not sideA or not U.isSquareFree(sideA)
                            or U.edgeBlocked(blocker, sideA)
                        local blockedB = not sideB or not U.isSquareFree(sideB)
                            or U.edgeBlocked(blocker, sideB)
                        if blockedA and blockedB then
                            local bay = SC.Navigation._crowdClearanceSquareForRequest(
                                ghost(blocker), ghost(start), blocker, {}, true)
                            if bay and not U.sameSquare(bay, retreat)
                                and not U.sameSquare(bay, start) then
                                return { run = { retreat, start, blocker, after,
                                    goal, goal }, bay = bay }
                            end
                        end
                    end
                end
            end
        end end
    end
    return nil
end

-- Build a disposable, physically blocked aisle when the loaded save has no
-- natural long hallway. These are real full-square blocking IsoThumpables,
-- not mocked pathing results.
local function physicalCorridor(SC, actor)
    local U = SC.GameplayUtil
    local px, py, pz = position(actor)
    if not px then return nil, "actor_unavailable" end
    local z = math.floor(pz)
    -- Vanilla's moveable furniture uses this shelf sprite and explicitly sets
    -- blockAllTheSquare/canPassThrough; mirror that native construction here.
    local blockerSprite = "carpentry_02_68"

    for radius = 0, 25 do
        for ox = -radius, radius do for oy = -radius, radius do
            if math.max(math.abs(ox), math.abs(oy)) == radius then
                local x, y = math.floor(px) + ox, math.floor(py) + oy
                for _, axis in ipairs({ { 1, 0 }, { 0, 1 } }) do
                    local dx, dy = axis[1], axis[2]
                    local run, sides = {}, {}
                    local clear = true
                    for n = 0, 7 do
                        local middle = U.gridSquare(x + n * dx, y + n * dy, z)
                        if not middle or not U.isSquareFree(middle)
                            or U.squareOccupyingObject(middle)
                            or (n > 0 and U.edgeBlocked(run[n], middle)) then
                            clear = false break
                        end
                        run[n + 1] = middle
                        if n <= 6 then
                            for _, side in ipairs({ -1, 1 }) do
                                if not (n >= 5 and side == 1) then
                                    local sx = x + n * dx - side * dy
                                    local sy = y + n * dy + side * dx
                                    local block = U.gridSquare(sx, sy, z)
                                    if not block or not U.isSquareFree(block)
                                        or U.squareOccupyingObject(block)
                                        or U.edgeBlocked(middle, block) then
                                        clear = false break
                                    end
                                    sides[#sides + 1] = block
                                end
                            end
                        end
                        if not clear then break end
                    end
                    local bay = U.gridSquare(x + 6 * dx - dy,
                        y + 6 * dy + dx, z)
                    if clear and bay and U.isSquareFree(bay)
                        and not U.squareOccupyingObject(bay) then
                        local placed = true
                        for _, square in ipairs(sides) do
                            local object = IsoThumpable.new(getCell(), square,
                                blockerSprite, false, {})
                            if not object then placed = false break end
                            object:setBlockAllTheSquare(true)
                            object:setCanPassThrough(false)
                            object:setIsThumpable(true)
                            square:AddSpecialObject(object, square:getObjects():size())
                            square:RecalcProperties()
                            square:RecalcAllWithNeighbours(true)
                            if U.isSquareFree(square) then placed = false break end
                        end
                        if placed then
                            return { run = run, bay = bay },
                                "sprite=" .. tostring(blockerSprite)
                        end
                        return nil, "blocker_sprite_did_not_block"
                    end
                end
            end
        end end
    end
    return nil, "no_open_eight_by_three_area"
end

local function stage(H, SC, actor, square)
    local x, y, z = position(square)
    return H.placeCombatActor(actor, { x = x + 0.5, y = y + 0.5, z = z })
end

local function stageUseEdge(H, SC, actor, fixture)
    local sx, sy = position(fixture.square)
    local nx, ny, nz = position(fixture.near)
    return H.placeCombatActor(actor, {
        x = nx + 0.5 + (nx - sx) * 0.4,
        y = ny + 0.5 + (ny - sy) * 0.4, z = nz,
    })
end

local function readyNativeAction(SC, actor)
    if SC.Logistics and type(SC.Logistics.reset) == "function" then
        SC.Logistics.reset(actor)
    end
    if SC.ActionSupervisor and type(SC.ActionSupervisor.cancel) == "function" then
        SC.ActionSupervisor.cancel(actor, "farm_corridor_probe", nil, true)
    end
    SC.NativeActions.cancelWork(actor, "farm_reach_probe_ready")
    if type(ISTimedActionQueue) == "table"
        and type(ISTimedActionQueue.clear) == "function" then
        ISTimedActionQueue.clear(actor)
    end
    return SC.NativeActions.stopDirect(actor)
end

local function releaseControl(H)
    local fixture = H.farmCorridor
    if fixture and fixture.decisionUpdate then
        SurvivorCompanion.Decision.update = fixture.decisionUpdate
        fixture.decisionUpdate = nil
    end
end

local function finish(H, current, setPhase)
    releaseControl(H)
    setPhase("finish", current)
end

local function nextCorridor(H, SC, current, result, setPhase)
    local actors = H.farmCorridor.actors
    if #actors < 2 then
        result("SKIP", "corridor_live_passage", "cloned save has only one recruited companion")
        finish(H, current, setPhase) return
    end
    local site, corridorReason = corridor(SC, actors[1], actors[2])
    local kind = site and "natural" or nil
    if not site then
        result("SKIP", "corridor_live_passage",
            "no loaded indoor run with four consecutive narrow tiles; "
                .. tostring(corridorReason))
        local fixtureReason
        site, fixtureReason = physicalCorridor(SC, actors[1])
        if site then
            kind = "fixture"
            result("PASS", "corridor_physical_fixture", fixtureReason)
        else
            result("SKIP", "corridor_physical_fixture", tostring(fixtureReason))
            site = actualChoke(SC, actors[1])
            if site then kind = "choke" end
        end
    end
    if not site then
        result("SKIP", "choke_live_passage", "no loaded passable choke with a bay")
        finish(H, current, setPhase) return
    end
    H.farmCorridor.hall = site
    H.farmCorridor.hallResultKey = kind == "natural" and "corridor_live_passage"
        or kind == "fixture" and "corridor_fixture_passage"
        or "choke_live_passage"
    stage(H, SC, actors[1], site.run[2])
    stage(H, SC, actors[2], site.run[3])
    local clearance = SC.Navigation._crowdClearanceSquareForRequest(
        actors[2], actors[1], site.run[3],
        { allies = { { actor = actors[1] }, { actor = actors[2] } } }, true)
    local cx, cy = position(clearance)
    local bx, by = position(site.bay)
    result(clearance and "PASS" or "FAIL",
        kind == "natural" and "corridor_connected_passing_space"
            or kind == "fixture" and "corridor_fixture_passing_space"
            or "choke_connected_passing_space",
        "clearance=" .. tostring(cx) .. "," .. tostring(cy)
            .. " bay=" .. tostring(bx) .. "," .. tostring(by))
    H.farmCorridor.lastAt = 0
    setPhase("farm_corridor_passage", current)
end

function Probe.step(H, current, check, result, setPhase)
    local SC = SurvivorCompanion
    local U = SC.GameplayUtil
    if H.phase == "farm_corridor_setup" then
        if current - H.phaseStartedAt < 6000 then return end
        local actors, ids = {}, {}
        for _, record in ipairs(SC.Registry.snapshot() or {}) do
            if record.recruited == true and record.actor
                and call(record.actor, "isDead") ~= true then
                actors[#actors + 1] = record.actor
                ids[#ids + 1] = record.id
            end
        end
        if #actors == 0 then
            result("FAIL", "farm_reach_actor", "no recruited companion in cloned save")
            finish(H, current, setPhase) return
        end
        local source, crop, checked, bathtub = fixtures(SC, actors[1])
        H.farmCorridor = { actors = actors, source = source, crop = crop }
        local controlled = H.farmCorridor
        controlled.decisionUpdate = SC.Decision.update
        SC.Decision.update = function(actor, ...)
            for index = 1, math.min(2, #controlled.actors) do
                if actor == controlled.actors[index] then
                    return true, "harness_controls_navigation"
                end
            end
            return controlled.decisionUpdate(actor, ...)
        end
        for index = 1, math.min(2, #actors) do
            SC.BaseWork.cancel(actors[index], "farm_corridor_probe")
            local ordered, reason = SC.Commands.issue(ids[index], "stay", {}, H.player)
            result(ordered and "PASS" or "FAIL", "farm_probe_stay_order_" .. index,
                tostring(reason))
            if SC.Downtime and type(SC.Downtime.cancel) == "function" then
                SC.Downtime.cancel(actors[index], "farm_corridor_probe")
            end
        end
        result("PASS", "farm_reach_fixtures", "squares=" .. tostring(checked)
            .. " bathtub=" .. tostring(bathtub) .. " source=" .. tostring(source ~= nil)
            .. " source_label=" .. tostring(source and source.label)
            .. " crop=" .. tostring(crop ~= nil))
        if not source then
            result("SKIP", "farm_live_fill", "no loaded water fixture with a two-tile approach")
            nextCorridor(H, SC, current, result, setPhase) return
        end
        stageUseEdge(H, SC, actors[1], source)
        H.farmCorridor.fillCan = call(call(actors[1], "getInventory"),
            "AddItem", "Base.WateredCan")
        H.farmCorridor.lastAt = 0
        setPhase("farm_corridor_fill_approach", current)
        return
    end
    local f = H.farmCorridor
    if H.phase == "farm_corridor_fill_approach" then
        if current - f.lastAt < 150 then return end
        f.lastAt = current
        local status, reason = SC.FarmWork._approachForHarness(
            f.actors[1], f.source.square, f.source.object)
        if status == "arrived" then
            local arrived, distance = U.arrived(f.actors[1], f.source.square,
                { targetKind = "square", distance = 1.25 })
            check("farm_live_source_reach", arrived == true,
                "distance=" .. tostring(distance) .. " reason=" .. tostring(reason))
            if not f.fillCan then
                result("FAIL", "farm_live_fill", "watering can could not be created")
                nextCorridor(H, SC, current, result, setPhase) return
            end
            f.beforeFluid = fluid(f.fillCan)
            local stopped, stopReason = readyNativeAction(SC, f.actors[1])
            result(stopped and "PASS" or "FAIL", "farm_live_fill_actor_ready",
                tostring(stopReason))
            local started, detail = SC.NativeActions.startFarm(f.actors[1], {
                operation = "fill_water", item = f.fillCan, object = f.source.object,
            })
            if not check("farm_live_fill_started", started == true,
                tostring(detail)) then
                nextCorridor(H, SC, current, result, setPhase) return
            end
            setPhase("farm_corridor_fill_action", current)
        elseif current - H.phaseStartedAt > 30000 then
            result("FAIL", "farm_live_source_reach",
                "timeout " .. tostring(status) .. "/" .. tostring(reason))
            nextCorridor(H, SC, current, result, setPhase)
        end
        return
    end
    if H.phase == "farm_corridor_fill_action" then
        local amount = fluid(f.fillCan)
        local uses = type(ISFarmingMenu) == "table"
            and type(ISFarmingMenu.getWaterUsesInteger) == "function"
            and ISFarmingMenu.getWaterUsesInteger(f.fillCan) or 0
        if uses >= 1 then
            result("PASS", "farm_live_fill", tostring(f.beforeFluid) .. "->" .. tostring(amount))
            SC.NativeActions.cancelWork(f.actors[1], "farm_reach_probe_filled")
            if not f.crop then
                result("SKIP", "farm_live_water", "no loaded crop requiring water")
                nextCorridor(H, SC, current, result, setPhase) return
            end
            stageUseEdge(H, SC, f.actors[1], f.crop)
            f.lastAt = 0
            setPhase("farm_corridor_water_approach", current)
        elseif current - H.phaseStartedAt > 20000 then
            result("FAIL", "farm_live_fill", "no fluid added; amount=" .. tostring(amount))
            nextCorridor(H, SC, current, result, setPhase)
        end
        return
    end
    if H.phase == "farm_corridor_water_approach" then
        if current - f.lastAt < 150 then return end
        f.lastAt = current
        local status, reason = SC.FarmWork._approachForHarness(
            f.actors[1], f.crop.square)
        if status == "arrived" then
            local arrived, distance = U.arrived(f.actors[1], f.crop.square,
                { targetKind = "square", distance = 1.25 })
            check("farm_live_crop_reach", arrived == true,
                "distance=" .. tostring(distance) .. " reason=" .. tostring(reason))
            f.beforeWater = tonumber(f.crop.plant.waterLvl) or 0
            f.waterUsesBefore = type(ISFarmingMenu) == "table"
                and type(ISFarmingMenu.getWaterUsesInteger) == "function"
                and ISFarmingMenu.getWaterUsesInteger(f.fillCan) or 0
            local stopped, stopReason = readyNativeAction(SC, f.actors[1])
            result(stopped and "PASS" or "FAIL", "farm_live_water_actor_ready",
                tostring(stopReason))
            local started, detail = SC.NativeActions.startFarm(f.actors[1], {
                operation = "water", item = f.fillCan, square = f.crop.square,
                plant = f.crop.plant, uses = 1,
            })
            if not check("farm_live_water_started", started == true,
                tostring(detail)) then
                nextCorridor(H, SC, current, result, setPhase) return
            end
            setPhase("farm_corridor_water_action", current)
        elseif current - H.phaseStartedAt > 30000 then
            result("FAIL", "farm_live_crop_reach",
                "timeout " .. tostring(status) .. "/" .. tostring(reason))
            nextCorridor(H, SC, current, result, setPhase)
        end
        return
    end
    if H.phase == "farm_corridor_water_action" then
        local server = type(SFarmingSystem) == "table"
            and SFarmingSystem.instance
            and call(SFarmingSystem.instance, "getLuaObjectOnSquare", f.crop.square)
            or nil
        local amount = math.max(tonumber(f.crop.plant.waterLvl) or 0,
            tonumber(server and server.waterLvl) or 0)
        if amount <= f.beforeWater and current - H.phaseStartedAt >= 2500
            and SC.NativeActions.isWorkActive(f.actors[1]) ~= true
            and not f.waterReconciled then
            SC.NativeActions.finishWork(f.actors[1])
            local work = { operation = "water", before = f.beforeWater,
                waterUsesBefore = f.waterUsesBefore, usesRequested = 1,
                item = f.fillCan }
            f.waterReconciled = true
            local applied = SC.FarmWork._reconcileWaterForHarness(
                f.actors[1], f.crop.square, work, "live-probe")
            result(applied and "PASS" or "FAIL", "farm_live_water_reconcile",
                "spent=" .. tostring(f.waterUsesBefore -
                    (type(ISFarmingMenu) == "table"
                        and ISFarmingMenu.getWaterUsesInteger(f.fillCan) or 0)))
            amount = math.max(tonumber(f.crop.plant.waterLvl) or 0,
                tonumber(server and server.waterLvl) or 0)
        end
        if amount > f.beforeWater then
            result("PASS", "farm_live_water", tostring(f.beforeWater) .. "->" .. tostring(amount))
            SC.NativeActions.cancelWork(f.actors[1], "farm_reach_probe_watered")
            nextCorridor(H, SC, current, result, setPhase)
        elseif current - H.phaseStartedAt > 20000 then
            result("FAIL", "farm_live_water", "crop unchanged=" .. tostring(amount)
                .. " can=" .. tostring(fluid(f.fillCan)))
            nextCorridor(H, SC, current, result, setPhase)
        end
        return
    end
    if H.phase == "farm_corridor_passage" then
        if current - f.lastAt < 100 then return end
        f.lastAt = current
        local a, b = f.actors[1], f.actors[2]
        local snapshotA = { allies = { { actor = b } }, immediateCount = 0,
            pressure = 0 }
        local snapshotB = { allies = { { actor = a } }, immediateCount = 0,
            pressure = 0 }
        local goal = f.hall.run[#f.hall.run]
        SC.Navigation.request(a, goal, "walk", {
            action = "corridor_probe", movementPriority = 70,
            snapshot = snapshotA, continuousApproach = true,
        })
        local yielded = SC.Navigation.serviceCrowdYield(b, snapshotB)
        if yielded ~= true then
            SC.Navigation.request(b, f.hall.run[1], "walk", {
                action = "corridor_probe", movementPriority = 40,
                snapshot = snapshotB, continuousApproach = true,
            })
        end
        if U.arrived(a, goal, { targetKind = "square", distance = 0.75 }) then
            result("PASS", f.hallResultKey,
                f.hallResultKey == "corridor_live_passage"
                    and "requester crossed six-tile indoor corridor"
                    or f.hallResultKey == "corridor_fixture_passage"
                        and "requester crossed eight-tile physical corridor"
                    or "requester crossed short choke")
            finish(H, current, setPhase)
        elseif current - H.phaseStartedAt > 45000 then
            local ax, ay = position(a)
            local bx, by = position(b)
            result("FAIL", f.hallResultKey, "timeout a=" .. tostring(ax)
                .. "," .. tostring(ay) .. " b=" .. tostring(bx) .. "," .. tostring(by))
            finish(H, current, setPhase)
        end
    end
end

return Probe
