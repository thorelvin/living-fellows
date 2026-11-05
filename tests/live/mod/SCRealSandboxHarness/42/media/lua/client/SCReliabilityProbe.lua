-- SPDX-License-Identifier: MIT
-- Opt-in disposable fixtures only. Reuse the existing wood/real-building probes.
local P = {}
local function call(o, method, ...)
    local ok, value = pcall(function(...) return o[method](o, ...) end, ...)
    if ok then return value end
end
local function shot(H, label)
    getCore():TakeFullScreenshot(H.config.run_id .. "-reliability-" .. label)
end
function P.parking(SC, result)
    for _, car in ipairs(SC.Vehicle.loadedVehicles()) do
        if tonumber(call(car, "getSqlId")) == 46 then
            local poly = SC.ExpeditionCar.footprint(car)
            if not poly or not SC.Vehicle.isStationary(car) then return false, "saved car is not stopped/readable" end
            local x1, y1, x2, y2 = 30000, 30000, 0, 0
            for i = 1, 4 do
                x1, y1 = math.min(x1, poly["x" .. i]), math.min(y1, poly["y" .. i])
                x2, y2 = math.max(x2, poly["x" .. i]), math.max(y2, poly["y" .. i])
            end
            local ok, why = SC.BaseLife.beginZone("parking", { x = math.floor(x1), y = math.floor(y1), z = 0 })
            if ok then ok, why = SC.BaseLife.finishZone({ x = math.floor(x2), y = math.floor(y2), z = 0 }, "Reliability parking fixture") end
            result(ok and "PASS" or "FAIL", "wood_reliability_parking", "expanded cloned outline only; saved car46 never moved")
            return ok, why
        end
    end
    return false, "saved car46 not loaded"
end
function P.obstruct(H, f, check, result)
    local SC, car = SurvivorCompanion, f.car
    if f.obstacle then
        if getTimestampMs()-f.obstacleAt < 1500 then return nil end
        local a = f.access
        if f.obstacleClearedAt then
            if getTimestampMs()-f.obstacleClearedAt < 1500 then return nil end
            local route, reason = SC.ExpeditionCar.planRoadAccess(car.vehicle, a.at, a.destination)
            return check("wood_reliability_cleared_access", route ~= nil,
                "normal trip after removing only the probe-created blocker; reason=" .. tostring(reason))
        end
        local clear, blocked = SC.ExpeditionCar.accessBetween(car.vehicle, a.at, a.entry)
        local alternate, failure, mapped = SC.ExpeditionCar.planRoadAccess(car.vehicle, a.at, a.destination)
        local changed = mapped and (mapped.entryX-a.entry.x)^2+(mapped.entryY-a.entry.y)^2 >= 4
        if not check("wood_reliability_nearest_blocked", clear == false and blocked == "road_access_vehicle_blocked",
            "native parked fixture occupies the nearest access strip") then return false end
        shot(H, "blocked-connector")
        if not alternate then
            -- The utility pole/fence and the saved parked neighbour can block
            -- every alternative. A safe refusal is the required result there,
            -- not permission to drive through the newly recognised pole.
            local refused = failure == "road_access_vehicle_blocked" or failure == "road_access_blocked"
            if not check("wood_reliability_blocked_access", refused
                and car.vehicle:isEngineRunning() == false
                and math.abs(car.vehicle:getCurrentSpeedKmHour()) < 0.1
                and (car.vehicle:getX()-a.at.x)^2+(car.vehicle:getY()-a.at.y)^2 <= 0.01,
                "all checked exits refused=" .. tostring(failure)
                    .. ";saved car speed=" .. car.vehicle:getCurrentSpeedKmHour()
                    .. ";engine=" .. tostring(car.vehicle:isEngineRunning())) then return false end
            local removed, why = pcall(f.obstacle.permanentlyRemove, f.obstacle)
            if not check("wood_reliability_fixture_removed", removed,
                "only the probe-created parked car; saved cars unchanged; " .. tostring(why)) then return false end
            f.obstacleClearedAt = getTimestampMs()
            return nil
        end
        if not check("wood_reliability_alternate_access", changed == true,
            "nearest=" .. tostring(blocked) .. ";alternate=" .. tostring(failure)
            .. ";old=" .. a.entry.x .. "," .. a.entry.y .. ";new=" .. tostring(mapped and mapped.entryX)
            .. "," .. tostring(mapped and mapped.entryY) .. ";obstacle=" .. f.obstacle:getX() .. "," .. f.obstacle:getY()) then return false end
        return true
    end
    local preview, why = SC.ExpeditionPrototype.previewWoodCollection(f.crew, {
        travelMode = "drive", vehicleSqlId = car.sqlId, parkingZoneId = car.zone.id })
    if not preview and (why == "forest_scan_pending" or why == "DATA_NOT_READY") then return nil end
    if not check("wood_reliability_initial_preview", preview ~= nil, tostring(why)) then return false end
    local at = { x = car.vehicle:getX(), y = car.vehicle:getY(), z = 0 }
    local route, reason, native = SC.ExpeditionRoute.planFromPoint(at, preview.site.anchor)
    if not check("wood_reliability_native_attachment", route ~= nil and native ~= nil and native.entryX ~= nil,
        tostring(reason)) then return false end
    local entry = { x = native.entryX, y = native.entryY, z = 0 }
    local dx, dy = entry.x-at.x, entry.y-at.y
    local square = getCell():getGridSquare(math.floor(at.x+dx*.65), math.floor(at.y+dy*.65), 0)
    if not check("wood_reliability_obstacle_ground", square ~= nil and dx*dx+dy*dy >= 64,
        "requires at least eight tiles between saved car and nearest road") then return false end
    f.obstacle = addVehicleDebug("Base.CarNormal", math.abs(dx) > math.abs(dy) and IsoDirections.N or IsoDirections.E, nil, square)
    if not check("wood_reliability_native_obstacle", f.obstacle ~= nil and f.obstacle:getSquare() ~= nil,
        "one real parked car across nearest connector; no driving collision overrides") then return false end
    f.access, f.obstacleAt = { at = at, entry = entry, destination = preview.site.anchor }, getTimestampMs()
    return nil -- Let Bullet and native square occupancy register the parked obstacle.
end
local function percentile(values, fraction)
    table.sort(values)
    return values[math.max(1, math.ceil(#values*fraction))] or 0
end
function P.camp(H, f, now, check, result, phase)
    local SC, r = SurvivorCompanion, f.reliability
    local function finish(reason)
        if r.originalScan then SC.BuildingScan.step = r.originalScan end
        if SC.Terminal.window then SC.Terminal.window:close() end
        SC.UI.close()
        result(reason and "FAIL" or "PASS", "camp_reliability_completed", reason or "four timed phases; normal decisions active")
        phase("finish", now)
    end
    if not r.ready then
        if not r.resetBase then
            local base = SC.BaseLife.active()
            for _, job in ipairs(base.jobs or {}) do
                if job.state ~= "completed" and job.state ~= "cancelled" then SC.BaseLife.cancelJob(job.id) end
            end
            base.storages = {} -- Replace the cloned old-camp registrations, not their native contents.
            r.resetBase = true
        end
        if not r.generator then
            local square = getCell():getGridSquare(math.floor((f.x1+f.x2)/2), f.y2+1, 0)
            if not square or not square:isOutside() then return finish("no outdoor generator fixture tile") end
            r.generator = square:getGenerator()
                or IsoGenerator.new(instanceItem("Base.Generator"), getCell(), square)
            if not r.generator then return finish("native generator fixture unavailable") end
            r.generator:setConnected(true)
            r.generator:setFuel(r.generator:getMaxFuel()*.8)
            r.generator:setActivated(true)
            result("PASS", "camp_reliability_native_power", "cloned native outdoor generator; normal room lights; no visibility override")
        end
        if not r.scanned then
        for _ = 1, 24 do
            local square = getCell():getGridSquare(r.x, r.y, r.z)
            if square and square:getBuilding() == f.building then
                SC.GameplayUtil.squareObjects(square, function(object)
                    if instanceof(object, "IsoLightSwitch") then object:setActive(true) end
                    r.storeCounts = r.storeCounts or { [0] = 0, [1] = 0 }
                    if r.storeCounts[r.z] < 12 and object:getContainer() then
                        local ok, storage = SC.BaseLife.registerStorage(object, "food")
                        if ok then
                            r.stores[#r.stores+1] = storage
                            r.storeCounts[r.z] = r.storeCounts[r.z]+1
                            r.floors = r.floors or {} r.floors[r.z] = true
                            local container = object:getContainer()
                            for i = 1, 16 do container:AddItem("Base.Paperclip") end
                            container:AddItem("Base.Apple")
                        end
                    end
                    if not r.pc and SC.Terminal.isComputer(object) then r.pc = object end
                end, 32)
            end
            r.x = r.x+1
            if r.x > f.x2 then r.x, r.y = f.x1, r.y+1 end
            if r.y > f.y2 then r.x, r.y, r.z = f.x1, f.y1, r.z+1 end
            if r.z > 1 then break end
        end
        if r.z <= 1 then return end
        r.scanned = true
        if not check("camp_reliability_two_floors", r.floors and r.floors[0] and r.floors[1]
            and #r.stores >= 8 and r.pc ~= nil, "marked stores=" .. #r.stores .. ";pc=" .. tostring(r.pc)) then
            return finish("native building fixture incomplete") end
        end
        local existing, retained, restoring = {}, 0, false
        for _, record in ipairs(SC.Registry.records()) do
            local actor, identity = record.actor, record.identity or {}
            if identity.forename == "Reliability" and tostring(identity.surname):match("^Worker[1-4]$") then
                retained = retained+1
                if not actor then restoring = true
                elseif not actor:isDead() then existing[#existing+1] = { actor = actor } end
            end
        end
        if retained > 4 then return finish("retained clone has extra fixture workers; use a clean seed") end
        if restoring then
            r.workerRestoreAt = r.workerRestoreAt or now
            if now-r.workerRestoreAt > 20000 then return finish("retained fixture workers did not restore") end
            return -- Never spawn replacements while the saved actors are still restoring.
        end
        for i = 1, 4 do
            if existing[i] then
                r.crew[i] = existing[i]
                local id = SC.Registry.idOf(existing[i].actor)
                SC.Commands.issue(id, "base_duty", nil, H.player)
                SC.BaseLife.assign(id, "generalist", true)
            else
            local sq = f.ground[i*3]
            local ticket, why = SC.Actor.beginSpawn(sq, { recruited = true,
                identity = { forename = "Reliability", surname = "Worker" .. i, outfit = "Generic01" } })
            if not ticket then return finish("spawn request: " .. tostring(why)) end
            r.crew[i] = { ticket = ticket }
            end
        end
        r.ready, r.spawnAt = true, now
        return
    end
    for _, row in ipairs(r.crew) do
        if not row.actor then
            local actor, why = SC.Actor.pollSpawn(row.ticket)
            if not actor then
                if why ~= "spawn_pending" or now-r.spawnAt > 20000 then return finish(tostring(why)) end
                return
            end
            row.actor = actor
            local id = SC.Registry.idOf(actor)
            SC.Commands.issue(id, "base_duty", nil, H.player)
            SC.BaseLife.assign(id, "generalist", true)
            actor:getStats():set(CharacterStat.HUNGER, .76)
        end
    end
    if r.openAt then
        if now-r.openAt < 1000 then return end
        if not SC.ControlUtil.near(H.player, r.pc, 3) then
            if now-r.openAt > 10000 then return finish("observer did not arrive beside the computer") end
            return
        end
        local hardware = SC.TerminalHardware.state(r.pc, false)
        if not hardware or not hardware.ups then
        H.player:setPerkLevelDebug(Perks.Electricity, math.max(4, H.player:getPerkLevel(Perks.Electricity)))
        local inventory = H.player:getInventory()
        inventory:AddItem("Base.Screwdriver") inventory:AddItem("Base.ElectricWire")
        for _ = 1, 4 do inventory:AddItem("Base.ElectronicsScrap") end
        local battery = inventory:AddItem("Base.CarBattery1")
        SC.ControlUtil.setCharge(battery, .95)
        local mounted, mountReason = SC.TerminalHardware.install(H.player, r.pc, "ups", battery)
        if not mounted then return finish("backup installation: " .. tostring(mountReason)) end
        end
        local state = SC.Terminal.computerState(H.player, r.pc)
        if state then state.locked = false end
        local ok, why = SC.Terminal.open(H.player, r.pc)
        if not ok then return finish("terminal open: " .. tostring(why)) end
        r.index, r.started, r.lastFrame, r.gaps, r.scanCalls, r.openAt = 3, now, now, {}, 0, nil
        SC.Performance.reset()
        return
    end
    if not r.started then
        -- The original observer point is a windowless storeroom. Use the
        -- largest retained ground-floor room for a representative camp view.
        local rooms, largest = {}, nil
        for index=1,math.min(#f.ground,1024) do
            local square=f.ground[index]
            local room=square:getRoom()
            if room then
                local row=rooms[room] or { count=0 }
                rooms[room]=row row.count=row.count+1
                local distance=(square:getX()-(f.x1+f.x2)/2)^2+(square:getY()-(f.y1+f.y2)/2)^2
                if (not row.distance or distance<row.distance)
                    and SC.GameplayUtil.isClearActorSpawnSquare(square) then row.square,row.distance=square,distance end
            end
        end
        for _,row in pairs(rooms) do if row.square and (not largest or row.count>largest.count) then largest=row end end
        if not largest then return finish("no clear ground-floor observer tile") end
        H.player:teleportTo(largest.square:getX()+.5,largest.square:getY()+.5,0)
        result("PASS", "camp_reliability_observer_room", "retained native room tiles=" .. largest.count
            .. ";observer=" .. largest.square:getX() .. "," .. largest.square:getY() .. ";crew unchanged")
        getGameTime():setTimeOfDay(12) -- Daylit disposable fixture for a meaningful rendered-scene sample.
        if not check("camp_reliability_daylight", math.abs(getGameTime():getTimeOfDay()-12) < 0.1,
            "cloned world only; crew decisions and surrounding population remain active") then
            return finish("daylight fixture unavailable") end
        r.index, r.started, r.lastFrame, r.gaps = 1, now, now, {}
        SC.UI.close()
        H.player:setGhostMode(true)
        r.scanCalls, r.originalScan = 0, SC.BuildingScan.step
        SC.BuildingScan.step = function(...)
            r.scanCalls = r.scanCalls+1
            return r.originalScan(...)
        end
        SC.Performance.reset()
    end
    if r.index == 3 and (not SC.Terminal.window or SC.Terminal.window.closed) then
        return finish("EMMA closed before its timed sample completed")
    end
    local elapsed = now-r.started
    if elapsed >= 8000 then r.gaps[#r.gaps+1] = now-r.lastFrame end
    r.lastFrame = now
    if elapsed < 45000 then return end
    local names = { "closed", "base", "emma", "closed-again" }
    local report, snapshot = SC.Performance.summary()
    result("PASS", "camp_reliability_" .. names[r.index], "samples=" .. #r.gaps
        .. ";frame_p50_ms=" .. percentile(r.gaps,.5) .. ";frame_p95_ms=" .. percentile(r.gaps,.95)
        .. ";frame_max_ms=" .. percentile(r.gaps,1) .. ";ai_p95_ms=" .. snapshot.p95FrameMs
        .. ";building_scan_calls=" .. r.scanCalls)
    if r.index == 1 or r.index == 4 then
        check("camp_reliability_idle_scan_" .. r.index, r.scanCalls == 0,
            "building discovery does no work with the terminal closed")
    end
    print("SC_RELIABILITY_PERFORMANCE|" .. names[r.index] .. "\n" .. report)
    shot(H, names[r.index])
    if r.index == 4 then return finish() end
    if r.index == 1 then SC.UI.open("base", SC.Registry.idOf(r.crew[1].actor))
    elseif r.index == 2 then
        SC.UI.close()
        local square = r.pc:getSquare()
        local standing, distance
        for dx = -2, 2 do for dy = -2, 2 do
            local sq = getCell():getGridSquare(square:getX()+dx, square:getY()+dy, square:getZ())
            local score = dx*dx+dy*dy
            if sq and sq:getBuilding() == f.building and (not distance or score < distance)
                and SC.GameplayUtil.isClearActorSpawnSquare(sq) then standing, distance = sq, score end
        end end
        if not standing then return finish("no free operator tile beside the computer") end
        H.player:teleportTo(standing:getX()+.5, standing:getY()+.5, standing:getZ())
        r.openAt = now
        return
    elseif SC.Terminal.window then SC.Terminal.window:close() end
    r.index, r.started, r.lastFrame, r.gaps, r.scanCalls = r.index+1, now, now, {}, 0
    SC.Performance.reset()
end
SCRealSandboxHarnessProbes = SCRealSandboxHarnessProbes or {}
SCRealSandboxHarnessProbes.SCReliabilityProbe = P
return P
