-- SPDX-License-Identifier: MIT
-- Isolated cloned-save probe: ignite one real corpse with the native action.
local Probe = {}

local function call(object, method, ...)
    if object == nil then return nil end
    local ok, value = pcall(function(...) return object[method](object, ...) end, ...)
    return ok and value or nil
end

local function position(actor)
    return tonumber(call(actor, "getX")), tonumber(call(actor, "getY")),
        tonumber(call(actor, "getZ"))
end

local directions = {
    { 1, 0 }, { 1, 1 }, { 0, 1 }, { -1, 1 },
    { -1, 0 }, { -1, -1 }, { 0, -1 }, { 1, -1 },
    { 2, 1 }, { 1, 2 }, { -1, 2 }, { -2, 1 },
    { -2, -1 }, { -1, -2 }, { 1, -2 }, { 2, -1 },
}

local function clearViewSquare(U, x, y)
    for radius = 5, 7 do
        for _, direction in ipairs(directions) do
            local dx, dy = direction[1], direction[2]
            local length = math.max(math.abs(dx), math.abs(dy))
            local square = U.gridSquare(x + math.floor(radius * dx / length),
                y + math.floor(radius * dy / length), 0)
            if square and U.isSquareFree(square)
                and call(square, "getRoom") == nil then return square end
        end
    end
    return nil
end

local function chooseSite(SC, originX, originY, workerId)
    local U, base = SC.GameplayUtil, SC.BaseLife.active()
    local lastReason
    for _, radius in ipairs({ 8, 12, 16, 20, 24, 28 }) do
        for _, direction in ipairs(directions) do
            local dx, dy = direction[1], direction[2]
            local length = math.max(math.abs(dx), math.abs(dy))
            local x = math.floor(originX + radius * dx / length)
            local y = math.floor(originY + radius * dy / length)
            local square = U.gridSquare(x, y, 0)
            local zone = { kind = "pyre", x1 = x, y1 = y,
                x2 = x, y2 = y, z = 0 }
            if square and U.isSquareFree(square)
                and SC.BaseLife.lumberZoneReachable(zone, base.zones) then
                local safe, reason = SC.Production.validatePyreZone(zone)
                if safe == true then
                    local view = clearViewSquare(U, x, y)
                    local approach = U.gridSquare(x + 1, y, 0)
                    local bystander = false
                    for _, record in ipairs(SC.Registry.records() or {}) do
                        if record.id ~= workerId and record.actor then
                            local bx, by = position(record.actor)
                            if bx and math.max(math.abs(bx - x), math.abs(by - y)) < 4 then
                                bystander = true
                                break
                            end
                        end
                    end
                    if view and approach and U.isSquareFree(approach)
                        and not bystander then
                        return square, approach, view
                    end
                    lastReason = "no_clear_view_or_approach"
                else
                    lastReason = reason
                end
            end
        end
    end
    return nil, nil, nil, lastReason or "no_safe_loaded_pyre_site"
end

local function chooseSource(SC, pyreSquare)
    local U, base = SC.GameplayUtil, SC.BaseLife.active()
    local px, py = pyreSquare:getX(), pyreSquare:getY()
    local best, bestScore
    for _, zone in ipairs(base.zones or {}) do
        if zone.kind == "area" and (tonumber(zone.z) or 0) == 0 then
            for y = zone.y1, zone.y2 do
                for x = zone.x1, zone.x2 do
                    local gap = math.max(math.abs(x - px), math.abs(y - py))
                    if gap >= 5 and gap <= 24 then
                        local square = U.gridSquare(x, y, 0)
                        if square and U.isSquareFree(square) then
                            local outside = call(square, "getRoom") == nil
                            local score = gap + (outside and 0 or 20)
                            if bestScore == nil or score < bestScore then
                                best, bestScore = square, score
                            end
                        end
                    end
                end
            end
        end
    end
    return best
end

local function makeCorpse(square)
    if type(createZombie) ~= "function" or IsoDeadBody == nil then
        return nil, "native_corpse_fixture_unavailable"
    end
    local zombie = createZombie(square:getX(), square:getY(), 0,
        nil, 0, IsoDirections.S)
    if not zombie then return nil, "zombie_fixture_failed" end
    local ok, body = pcall(IsoDeadBody.new, zombie, false)
    if not ok or not body then return nil, tostring(body) end
    if call(body, "getStaticMovingObjectIndex") == nil
        or call(body, "getStaticMovingObjectIndex") < 0 then
        return nil, "corpse_not_on_pyre_square"
    end
    return body
end

function Probe.step(H, current, check, result, setPhase)
    local SC = SurvivorCompanion
    if H.phase == "pyre_burn_setup" then
        if current - H.phaseStartedAt < 4000 then return end
        local base = SC.BaseLife.active()
        if not check("pyre_base", base ~= nil,
            "base=" .. tostring(base and base.id)) then
            setPhase("finish", current) return
        end
        local wx, wy = position(H.player)
        local square, approach, view, siteReason =
            chooseSite(SC, wx, wy, nil)
        if not check("pyre_safe_site", square ~= nil,
            tostring(siteReason) .. " near=" .. tostring(wx) .. "," .. tostring(wy)) then
            setPhase("finish", current) return
        end
        local sourceSquare = chooseSource(SC, square)
        if not check("pyre_collection_source", sourceSquare ~= nil,
            "source=" .. tostring(sourceSquare and sourceSquare:getX()) .. ","
                .. tostring(sourceSquare and sourceSquare:getY())
                .. " pyre=" .. tostring(square:getX()) .. ","
                .. tostring(square:getY())) then
            setPhase("finish", current) return
        end
        local begun, beginReason = SC.BaseLife.beginZone("pyre", square)
        local made, zone
        if begun then
            made, zone = SC.BaseLife.finishZone(square, "Harness pyre")
        else
            made, zone = false, beginReason
        end
        if not check("pyre_zone_created", made == true,
            tostring(made == true and zone.id or zone)) then
            SC.BaseLife.cancelZone()
            setPhase("finish", current) return
        end
        pcall(function() getGameTime():setTimeOfDay(12.0) end)
        local ticket, spawnReason = SC.Actor.beginSpawn(approach, {
            recruited = true,
            identity = { forename = "Pyre", surname = "Tester",
                gender = "man", outfit = "Generic01" },
        })
        if not check("pyre_worker_spawn_requested", ticket ~= nil,
            tostring(spawnReason)) then
            setPhase("finish", current) return
        end
        H.pyreSetup = { square = square, sourceSquare = sourceSquare,
            approach = approach, view = view, zone = zone, ticket = ticket }
        setPhase("pyre_burn_spawn", current)
        return
    end
    if H.phase == "pyre_burn_spawn" then
        local setup = H.pyreSetup
        local actor, spawnReason = SC.Actor.pollSpawn(setup.ticket)
        if actor == nil then
            if spawnReason ~= "spawn_pending"
                or current - H.phaseStartedAt > 12000 then
                result("FAIL", "pyre_worker_spawn", tostring(spawnReason))
                setPhase("finish", current)
            end
            return
        end
        local worker = { actor = actor, id = SC.Registry.idOf(actor) }
        if not check("pyre_worker_spawn", worker.id ~= nil,
            "id=" .. tostring(worker.id)) then
            setPhase("finish", current) return
        end
        local square, sourceSquare, approach, view, zone = setup.square,
            setup.sourceSquare, setup.approach, setup.view, setup.zone
        if SC.Scheduler then SC.Scheduler.unregister("decision") end
        local body, bodyReason = makeCorpse(sourceSquare)
        if not check("pyre_real_corpse", body ~= nil,
            tostring(bodyReason) .. " at=" .. tostring(sourceSquare:getX())
                .. "," .. tostring(sourceSquare:getY())) then
            setPhase("finish", current) return
        end
        local inventory = call(worker.actor, "getInventory")
        local petrol = inventory and call(inventory, "AddItem", "Base.PetrolCan")
        local matchbox = inventory and call(inventory, "AddItem", "Base.Matchbox")
        local fuel = tonumber(call(call(petrol, "getFluidContainer"), "getAmount")) or 0
        local firestarter = matchbox and SC.GameplayUtil.itemHasTag(matchbox, "StartFire")
        if not check("pyre_supplies", petrol ~= nil and firestarter == true
            and fuel >= (tonumber(ZomboidGlobals.BurnCorpsePetrolAmount) or 0.1),
            "fuel=" .. tostring(fuel) .. " matchboxTag=" .. tostring(firestarter)) then
            setPhase("finish", current) return
        end
        if SC.Downtime then SC.Downtime.cancel(worker.actor, "pyre_fixture") end
        if SC.BaseWork then SC.BaseWork.cancel(worker.actor, "pyre_fixture") end
        local ordered, orderReason = SC.Commands.issue(worker.id,
            "set_base_role", { role = "corpsekeeper" }, H.player)
        if not check("pyre_worker_on_duty", ordered == true, tostring(orderReason)) then
            setPhase("finish", current) return
        end
        local moved, moveReason = pcall(function()
            worker.actor:teleportTo(approach:getX() + 0.5,
                approach:getY() + 0.5, 0)
            H.player:teleportTo(view:getX() + 0.5, view:getY() + 0.5, 0)
        end)
        if not check("pyre_fixture_positioned", moved, tostring(moveReason)) then
            setPhase("finish", current) return
        end
        local created, order = SC.BaseLife.createProductionOrder({
            operation = "collect_bodies", zoneId = zone.id, requested = 1,
            workers = { worker.id },
            settings = { fromCamp = true, withBelongings = true,
                requireDry = false },
        })
        if not check("pyre_burn_order", created == true,
            tostring(created and order.id or order)) then
            setPhase("finish", current) return
        end
        H.pyreFixture = { worker = worker, body = body, square = square,
            sourceSquare = sourceSquare, observed = {},
            zone = zone, order = order, petrol = petrol, matchbox = matchbox,
            fuelBefore = fuel,
            counterBefore = SC.BaseLife.productionCounters().pyresLit or 0 }
        setPhase("pyre_burn_wait", current)
        return
    end
    if H.phase == "pyre_burn_wait" then
        local fixture = H.pyreFixture
        if current - H.phaseStartedAt > 180000 then
            result("FAIL", "pyre_lit", "timeout order="
                .. tostring(fixture.order.state) .. "/"
                .. tostring(fixture.order.blocker) .. " workerPhase="
                .. tostring(SC.Production.workerPhase(fixture.order.id,
                    fixture.worker.id)))
            setPhase("finish", current) return
        end
        if current >= (H.pyreNextUpdate or 0) then
            H.pyreNextUpdate = current + 250
            local handled, reason, terminal = SC.Production.update(
                fixture.worker.actor, {},
                { type = "production", state = "active",
                    target = { orderId = fixture.order.id } }, {})
            local phase = SC.Production.workerPhase(fixture.order.id,
                fixture.worker.id)
            fixture.observed[tostring(reason)] = true
            fixture.observed[tostring(phase)] = true
            if current >= (H.pyreNextTrace or 0) then
                H.pyreNextTrace = current + 3000
                print("SC_REAL_SANDBOX|PYRE_TRACE|handled=" .. tostring(handled)
                    .. " reason=" .. tostring(reason)
                    .. " terminal=" .. tostring(terminal)
                    .. " order=" .. tostring(fixture.order.state) .. "/"
                    .. tostring(fixture.order.blocker)
                    .. " phase=" .. tostring(SC.Production.workerPhase(
                        fixture.order.id, fixture.worker.id)))
            end
        end
        if fixture.order.state == "blocked" then
            result("FAIL", "pyre_lit", "blocked: " .. tostring(fixture.order.blocker))
            setPhase("finish", current) return
        end
        local counters = SC.BaseLife.productionCounters()
        if call(fixture.square, "haveFire") == true
            and (counters.pyresLit or 0) > fixture.counterBefore then
            check("pyre_body_grabbed", fixture.observed.grabbing == true
                or fixture.observed.production_grabbing == true,
                "grab action observed=" .. tostring(fixture.observed.grabbing))
            check("pyre_body_dragged", fixture.observed.dragging == true
                or fixture.observed.production_dragging == true,
                "drag action observed=" .. tostring(fixture.observed.dragging))
            check("pyre_body_placed", fixture.observed.placing == true
                or fixture.observed.production_placing == true,
                "place action observed=" .. tostring(fixture.observed.placing))
            local remaining = tonumber(call(call(fixture.petrol,
                "getFluidContainer"), "getAmount")) or 0
            check("pyre_lit", true, "native fire at "
                .. tostring(fixture.square:getX()) .. ","
                .. tostring(fixture.square:getY())
                .. " fuel=" .. tostring(fixture.fuelBefore) .. "->"
                .. tostring(remaining) .. " firestarter=Base.Matchbox")
            check("pyre_petrol_consumed", remaining < fixture.fuelBefore,
                tostring(fixture.fuelBefore) .. "->" .. tostring(remaining))
            setPhase("pyre_burn_capture", current)
        end
        return
    end
    if H.phase == "pyre_burn_capture" then
        if current - H.phaseStartedAt < 750 then return end
        local name = tostring(H.config.run_id) .. "-pyre-lit"
        local ok, failure = pcall(function() getCore():TakeFullScreenshot(name) end)
        check("pyre_lit_screenshot", ok, name .. ".png " .. tostring(failure))
        setPhase("pyre_burn_finish", current)
        return
    end
    if H.phase == "pyre_burn_finish" and current - H.phaseStartedAt > 1800 then
        setPhase("finish", current)
    end
end

SCRealSandboxHarnessProbes = SCRealSandboxHarnessProbes or {}
SCRealSandboxHarnessProbes.SCPyreBurnProbe = Probe
return Probe
