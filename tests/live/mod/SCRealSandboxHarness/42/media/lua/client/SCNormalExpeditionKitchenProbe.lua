-- SPDX-License-Identifier: MIT
-- Disposable-save normal mission: real roster, parked car, mapped store and
-- production autonomous return. No crew placement, gear, loot, AI overrides,
-- manual return request or manual completion is used here.
local Probe = {}
local KITCHEN = { x = 12035.5, y = 6746.5, z = 0 }

local function call(object, method, ...)
    if not object then return nil end
    local indexed, fn = pcall(function() return object[method] end)
    if not indexed or type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, object, ...)
    if ok then return value end
end
local function position(actor)
    return tostring(call(actor, "getX")) .. "," .. tostring(call(actor, "getY")) .. "," .. tostring(call(actor, "getZ"))
end
local function poseStable(actor)
    local x, y, z = call(actor, "getX"), call(actor, "getY"), call(actor, "getZ")
    return type(x) == "number" and type(y) == "number" and type(z) == "number"
        and (x - KITCHEN.x)^2 + (y - KITCHEN.y)^2 <= 0.25^2 and math.abs(z - KITCHEN.z) < 0.05
end
local function primaryState(actor)
    local queue = ISTimedActionQueue and ISTimedActionQueue.queues and ISTimedActionQueue.queues[actor]
    local names = {}
    for index = 1, math.min(queue and queue.queue and #queue.queue or 0, 8) do
        names[#names + 1] = tostring(queue.queue[index].Type or queue.queue[index])
    end
    return "fsm=" .. tostring(call(actor, "getCurrentStateName"))
        .. ";action=" .. tostring(call(actor, "getActionStateName"))
        .. ";blocked=" .. tostring(call(actor, "isBlockMovement"))
        .. ";queue=" .. table.concat(names, ",")
end
local function count(rows)
    local result = 0
    for _ in pairs(type(rows) == "table" and rows or {}) do result = result + 1 end
    return result
end
local function tripEvidence(fixture)
    return fixture.sawDeparture == true and fixture.sawStoreEntry == true
end
local function healthy(actor)
    local body = call(actor, "getBodyDamage")
    return actor ~= nil and call(actor, "isDead") == false and call(actor, "isBridgeHealthy") == true
        and (tonumber(call(body, "getOverallBodyHealth")) or 0) >= 95
        and call(body, "getNumPartsBleeding") == 0
end
local function hidePanels()
    for _, getter in ipairs({ getPlayerInventory, getPlayerLoot }) do
        if type(getter) == "function" then
            local panel = getter(0)
            if panel then call(panel, "setVisible", false) end
        end
    end
    if ISConsole and ISConsole.instance then call(ISConsole.instance, "setVisible", false) end
end
local function capture(H, label)
    hidePanels()
    local name = tostring(H.config.run_id) .. "-normal-expedition-kitchen-" .. label .. ".png"
    local ok, why = pcall(function() getCore():TakeFullScreenshot(name) end)
    return ok, name .. "; queued, file and pixels require review; " .. tostring(why)
end
local function trace(fixture, label)
    local SC = SurvivorCompanion
    local mission = SC.ExpeditionPrototype.current()
    local scout = mission and mission.scout
    local car = fixture.car and fixture.car.vehicle
    local rows = { "phase=" .. tostring(scout and scout.phase or mission and "manual" or "idle"),
        "crewSize=" .. #(fixture.crew or {}),
        "carState=" .. tostring(scout and scout.vehicle and scout.vehicle.state),
        "acquired=" .. count(scout and scout.search and scout.search.acquisitions),
        "primary=" .. position(fixture.primary), "car=" .. position(car),
        primaryState(fixture.primary),
        "engine=" .. tostring(call(car, "isEngineRunning")) }
    for _, member in ipairs(fixture.crew or {}) do
        rows[#rows + 1] = member.id .. "@" .. position(member.actor)
            .. ";alive=" .. tostring(call(member.actor, "isDead") == false)
    end
    local line = label .. "|" .. table.concat(rows, "|")
    print("SC_REAL_SANDBOX|NORMAL_KITCHEN|" .. line)
    local writer = getFileWriter("SurvivorCompanionHarness/normal-expedition-kitchen.log", true, true)
    if writer then writer:writeln(line); writer:close() end
end
local function cleanup(fixture)
    if fixture.postRender then Events.OnPostRender.Remove(fixture.postRender) end
    if fixture.holdActive then
        call(fixture.primary, "setBlockMovement", fixture.previousBlockMovement)
        fixture.holdActive = false
    end
end
local function fail(fixture, result, setPhase, current, name, detail)
    result("FAIL", name, detail)
    cleanup(fixture)
    setPhase("finish", current)
end

local function setup(H, SC, check, result, setPhase, current)
    local crewSize = tonumber(H.config.normal_expedition_kitchen_crew_size) or 2
    if not check("normal_kitchen_crew_size_option", crewSize == 1 or crewSize == 2,
        "requested crew size=" .. tostring(crewSize)) then setPhase("finish", current) return end
    if (not SC.BaseLife.active() or #SC.Registry.records() < crewSize)
        and current - H.phaseStartedAt < 15000 then return end
    local fixture = { primary = H.player, crew = {}, places = {}, page = 0, frames = 0,
        startedAt = current, nextTraceAt = current, planIndex = 1, carIndex = 1 }
    H.normalKitchen = fixture
    if not check("normal_kitchen_no_prior_view", SC.ExpeditionPrototype.current() == nil
        and SC.BaseWatch.current() == nil and SC.ViewSession.owner() == nil
        and getSpecificPlayer(1) == nil, "refuse active mission/watch; never reset it") then
        setPhase("finish", current) return
    end
    local square = SC.GameplayUtil.gridSquare(math.floor(KITCHEN.x), math.floor(KITCHEN.y), KITCHEN.z)
    local roomName = call(call(square, "getRoom"), "getName")
    if not check("normal_kitchen_actual_room", type(roomName) == "string"
        and string.find(string.lower(roomName), "kitchen", 1, true) ~= nil
        and call(square, "TreatAsSolidFloor") == true and call(square, "hasFloor") == true,
        "point=12035.5,6746.5,0 actual_room=" .. tostring(roomName)) then setPhase("finish", current) return end
    -- The human is staged once. All NPC movement remains normal production AI.
    local placed, why = pcall(function()
        local actor = H.player
        actor:setX(KITCHEN.x); actor:setY(KITCHEN.y); actor:setZ(KITCHEN.z)
        actor:setNextX(KITCHEN.x); actor:setNextY(KITCHEN.y)
        actor:setLastX(KITCHEN.x); actor:setLastY(KITCHEN.y); actor:setLastZ(KITCHEN.z)
        actor:setCurrentSquareFromPosition(); actor:setSquare(actor:getCurrentSquare())
        actor:setMovingSquare(actor:getCurrentSquare())
    end)
    if not check("normal_kitchen_primary_pose", placed, why) then setPhase("finish", current) return end
    fixture.previousBlockMovement = call(H.player, "isBlockMovement")
    if not check("normal_kitchen_block_state_available", type(fixture.previousBlockMovement) == "boolean",
        primaryState(H.player)) then setPhase("finish", current) return end
    fixture.holdActive = true
    call(H.player, "setBlockMovement", true)
    if not check("normal_kitchen_primary_input_held", call(H.player, "isBlockMovement") == true,
        "native input movement block only; timed actions/orders unchanged; " .. primaryState(H.player)) then
        cleanup(fixture); setPhase("finish", current) return
    end
    for _, record in ipairs(SC.Registry.records()) do
        local state = record.actor and SC.Commands.peek(record.actor)
        if state and state.recruited == true and healthy(record.actor) and SC.BaseLife.isInside(record.actor) then
            fixture.crew[#fixture.crew + 1] = { id = record.id, actor = record.actor }
        end
    end
    table.sort(fixture.crew, function(a, b)
        local first = string.find(a.id, "990140", 1, true) ~= nil
        local second = string.find(b.id, "990140", 1, true) ~= nil
        if first ~= second then return first end
        local firstOutside = call(call(a.actor, "getCurrentSquare"), "getRoom") == nil
        local secondOutside = call(call(b.actor, "getCurrentSquare"), "getRoom") == nil
        if firstOutside ~= secondOutside then return firstOutside end
        return a.id < b.id
    end)
    while #fixture.crew > crewSize do table.remove(fixture.crew) end
    fixture.cars = SC.ExpeditionCar.parkedCars()
    if not check("normal_kitchen_real_crew_car", #fixture.crew == crewSize and #fixture.cars > 0,
        "requested crew=" .. crewSize .. " saved healthy recruited crew=" .. #fixture.crew
            .. " existing parked cars=" .. #fixture.cars) then
        cleanup(fixture); setPhase("finish", current) return
    end
    fixture.postRender = function()
        fixture.frames = fixture.frames + 1
        if fixture.holdActive and not poseStable(fixture.primary) then
            trace(fixture, "primary_drift")
            fail(fixture, result, setPhase, getTimestampMs(), "normal_kitchen_primary_drift",
                "scene moved beyond0.25tiles; no reposition/rescue; " .. position(fixture.primary)
                    .. ";" .. primaryState(fixture.primary))
            return
        end
        if fixture.awaitSoloCapture and not fixture.firstSoloCaptured then
            local diagnostic = SCSplitScreenProbe.releaseDiagnostics()
            if getSpecificPlayer(1) == nil and getPlayerScreenWidth(0) == getCore():getScreenWidth()
                and string.find(diagnostic, "frameIsPrimary=true", 1, true) then
                fixture.validSoloFrames = (fixture.validSoloFrames or 0) + 1
                if fixture.validSoloFrames == 2 then
                    local captured, detail = capture(H, tripEvidence(fixture)
                        and "natural-return-solo-frame2" or "failed-trip-solo-frame2")
                    check("normal_kitchen_first_valid_solo_screenshot_queued", captured, detail)
                    fixture.firstSoloCaptured = captured
                    trace(fixture, "return_valid_solo_frame2")
                end
            else fixture.validSoloFrames = 0 end
        end
    end
    Events.OnPostRender.Add(fixture.postRender)
    result("PASS", "normal_kitchen_time_limits", "wall deadline600s; UI return timer1hour; quantity2; speed1")
    setPhase("normal_kitchen_places", current)
end

function Probe.step(H, current, check, result, setPhase)
    local SC = SurvivorCompanion
    if H.phase == "normal_kitchen_setup" then return setup(H, SC, check, result, setPhase, current) end
    local fixture = H.normalKitchen
    if not fixture then result("FAIL", "normal_kitchen_fixture_missing", H.phase); setPhase("finish", current) return end
    if fixture.holdActive and not poseStable(fixture.primary) then
        trace(fixture, "primary_drift")
        return fail(fixture, result, setPhase, current, "normal_kitchen_primary_drift",
            "scene moved beyond0.25tiles; no return teleport; " .. position(fixture.primary)
                .. ";" .. primaryState(fixture.primary))
    end
    if current - fixture.startedAt > 600000 then
        trace(fixture, "deadline")
        local queued, detail = capture(H, "failed-trip-deadline")
        check("normal_kitchen_failure_screenshot_queued", queued, detail)
        return fail(fixture, result, setPhase, current, "normal_kitchen_deadline", "natural mission/return did not complete in600s; no manual rescue")
    end
    if H.phase == "normal_kitchen_places" then
        local leader = fixture.crew[1].actor
        local places, why, total = SC.ExpeditionPlaces.targetableNearby(math.floor(leader:getX()),
            math.floor(leader:getY()), 160, 32, fixture.page)
        if not places then return fail(fixture, result, setPhase, current, "normal_kitchen_places", tostring(why)) end
        for _, place in ipairs(places) do
            if place.kind == "store" and place.distance >= 75 and place.distance <= 150 then
                fixture.places[#fixture.places + 1] = place
            end
        end
        fixture.page = fixture.page + #places
        if #places > 0 and fixture.page < (total or fixture.page) and fixture.page < 256 then return end
        if not check("normal_kitchen_mapped_store", #fixture.places > 0,
            "real UI-selectable stores75..150tiles=" .. #fixture.places) then cleanup(fixture); setPhase("finish", current) return end
        setPhase("normal_kitchen_plan", current)
    elseif H.phase == "normal_kitchen_plan" then
        local place, car = fixture.places[fixture.planIndex], fixture.cars[fixture.carIndex]
        if not place then return fail(fixture, result, setPhase, current, "normal_kitchen_no_valid_route", tostring(fixture.lastPlanFailure)) end
        local approach, why = SC.ExpeditionPlaces.plannedApproach(place, fixture.crew[1].actor)
        local planned, reason
        if approach then planned, reason = SC.ExpeditionCar.preflight(fixture.crew, car.zone.id, car.sqlId, approach) end
        if planned then
            fixture.place, fixture.car = place, car
            fixture.departure = { x = call(car.vehicle, "getX"), y = call(car.vehicle, "getY") }
            trace(fixture, "before_dispatch")
            local captured, detail = capture(H, "before")
            check("normal_kitchen_before_screenshot_queued", captured, detail)
            local accepted, failure = SC.ExpeditionPrototype.startAtPlace(fixture.crew, place.id, "search", {
                travelMode = "drive", parkingZoneId = car.zone.id, vehicleSqlId = car.sqlId,
                request = { category = "useful", quantity = 2 }, restockBaseDuty = true,
                turnHomeAfterHours = 1, doctrine = "stealth" })
            if not check("normal_kitchen_production_dispatch", accepted == true,
                "store=" .. place.id .. " distance=" .. place.distance .. " car=" .. car.sqlId .. " reason=" .. tostring(failure)) then
                cleanup(fixture); setPhase("finish", current) return
            end
            fixture.dispatchedAt = current
            setPhase("normal_kitchen_mission", current)
        else
            fixture.lastPlanFailure = tostring(reason or why)
            fixture.carIndex = fixture.carIndex + 1
            if fixture.carIndex > #fixture.cars then fixture.carIndex, fixture.planIndex = 1, fixture.planIndex + 1 end
        end
    elseif H.phase == "normal_kitchen_mission" then
        local mission = SC.ExpeditionPrototype.current()
        if current >= fixture.nextTraceAt then fixture.nextTraceAt = current + 2000; trace(fixture, "mission") end
        fixture.sawJoined = fixture.sawJoined or getSpecificPlayer(1) ~= nil
        if mission ~= nil then
            local scout = mission.scout
            local vehicle = scout and scout.vehicle
            if vehicle and vehicle.leg == "outbound" and fixture.departure then
                local x, y = call(fixture.car.vehicle, "getX"), call(fixture.car.vehicle, "getY")
                if not fixture.sawDeparture and x and y
                    and (x - fixture.departure.x)^2 + (y - fixture.departure.y)^2 >= 64 then
                    fixture.sawDeparture = true
                    trace(fixture, "actual_outbound_departure")
                end
            end
            if scout and (scout.phase == "entering_site" or scout.phase == "searching"
                or scout.phase == "observing") and not fixture.sawStoreEntry
                and SC.ExpeditionPlaces.actorInsideSite(fixture.place.id, fixture.crew[1].actor) == true then
                fixture.sawStoreEntry = true
                trace(fixture, "actual_store_entry")
            end
            return
        end
        if not check("normal_kitchen_natural_return", fixture.sawJoined == true
            and getSpecificPlayer(1) == nil and SC.ViewSession.owner() == nil
            and SCSplitScreenProbe.isReleased() == true, "production mission ended without any probe completion call") then
            cleanup(fixture); setPhase("finish", current) return
        end
        fixture.returnedFrame = fixture.frames
        fixture.awaitSoloCapture, fixture.validSoloFrames = true, 0
        check("normal_kitchen_completed_trip", tripEvidence(fixture),
            "actual outbound movement=" .. tostring(fixture.sawDeparture)
                .. " actual store entry=" .. tostring(fixture.sawStoreEntry)
                .. "; boarding rollback/abort is a FAILED trip")
        trace(fixture, "natural_return")
        local captured, detail = capture(H, tripEvidence(fixture) and "natural-return"
            or "failed-trip-natural-abort")
        check("normal_kitchen_natural_return_screenshot_queued", captured, detail)
        setPhase("normal_kitchen_return_capture", current)
    elseif H.phase == "normal_kitchen_return_capture" then
        if fixture.frames - fixture.returnedFrame < 300 then return end
        local debrief = SC.ExpeditionPrototype.lastDebrief() or {}
        local stored = 0
        for _, item in pairs(debrief.integration and debrief.integration.items or {}) do if item.stored then stored = stored + 1 end end
        result(tripEvidence(fixture) and "PASS" or "FAIL", "normal_kitchen_outcome", "reason=" .. tostring(debrief.endReason)
            .. " collected=" .. count(debrief.acquisitions) .. " returned=" .. count(debrief.returnedIds)
            .. " stored=" .. stored .. " requested2 elapsedMs=" .. (current - fixture.dispatchedAt))
        local room = call(call(H.player, "getCurrentSquare"), "getRoom")
        check("normal_kitchen_return_room", string.find(string.lower(tostring(call(room, "getName"))), "kitchen", 1, true) ~= nil,
            "primary=" .. position(H.player))
        for _, member in ipairs(fixture.crew) do
            local currentRecord = SC.Registry.byId(member.id)
            check("normal_kitchen_crew_return_" .. member.id, currentRecord ~= nil
                and currentRecord.actor == member.actor and healthy(member.actor), "ended=" .. position(member.actor))
        end
        check("normal_kitchen_car_engine_stopped", call(fixture.car.vehicle, "isEngineRunning") == false,
            "car=" .. position(fixture.car.vehicle) .. " engine=" .. tostring(call(fixture.car.vehicle, "isEngineRunning")))
        check("normal_kitchen_solo_hud", getSpecificPlayer(1) == nil and getPlayerData(1) == nil
            and getPlayerScreenWidth(0) == getCore():getScreenWidth(), SCSplitScreenProbe.releaseDiagnostics())
        check("normal_kitchen_first_solo_capture_completed", fixture.firstSoloCaptured == true,
            "first two consecutive completed primary solo frames were captured")
        local captured, detail = capture(H, tripEvidence(fixture)
            and "natural-return-frame300" or "failed-trip-return-frame300")
        check("normal_kitchen_return_screenshot_queued", captured, detail)
        trace(fixture, "return_frame300")
        result("SKIP", "normal_kitchen_pixel_review", "inspect actual before/after PNGs; automatic evidence does not establish visual fix")
        fixture.captureQueuedAt = fixture.frames
        setPhase("normal_kitchen_complete", current)
    elseif H.phase == "normal_kitchen_complete" then
        if fixture.frames - fixture.captureQueuedAt < 3 then return end
        trace(fixture, "capture_complete_before_input_restore")
        cleanup(fixture)
        setPhase("finish", current)
    end
end

Probe._tests = { count = count, healthy = healthy, tripEvidence = tripEvidence,
    poseStable = poseStable, primaryState = primaryState }
SCRealSandboxHarnessProbes = SCRealSandboxHarnessProbes or {}
SCRealSandboxHarnessProbes.SCNormalExpeditionKitchenProbe = Probe
return Probe
