-- SPDX-License-Identifier: MIT
-- Diagnostic only: a real player path action and recruited followers on a
-- 50-tile Riverside street. Runs solely inside the cloned live sandbox.

SCRealSandboxHarnessProbes = SCRealSandboxHarnessProbes or {}
local Probe = {}
SCRealSandboxHarnessProbes.SCFollowRoadProbe = Probe

local START_X, ROAD_Y, DISTANCE = 6100.5, 5400.5, 50

local function put(line)
    print("SC_FOLLOW_ROAD|" .. string.gsub(line, "\t", "|"))
end

local function xy(actor)
    if not actor then return nil end
    local ok, x, y = pcall(function() return actor:getX(), actor:getY() end)
    if ok and tonumber(x) and tonumber(y) then return tonumber(x), tonumber(y) end
    return nil
end

local function roadName(square)
    local ok, name = pcall(function()
        local floor = square and square:getFloor()
        local sprite = floor and floor:getSprite()
        return sprite and sprite:getName()
    end)
    return ok and tostring(name or "none") or "unavailable"
end

local function clearCorridor()
    local SC = SurvivorCompanion
    local list = select(1, SC.GameplayUtil.call(getCell(), "getZombieList"))
    local count = list and tonumber(tostring(select(1,
        SC.GameplayUtil.call(list, "size")))) or 0
    local remove = {}
    for index = 0, math.floor(count or 0) - 1 do
        local zombie = select(1, SC.GameplayUtil.call(list, "get", index))
        local x, y = xy(zombie)
        if x and x >= START_X - 22 and x <= START_X + DISTANCE + 22
            and math.abs(y - ROAD_Y) <= 22 then
            remove[#remove + 1] = zombie
        end
    end
    for _, zombie in ipairs(remove) do
        pcall(function()
            zombie:setTarget(nil)
            zombie:removeFromWorld()
            zombie:removeFromSquare()
        end)
    end
    return #remove
end

local function sample(harness, current)
    local SC = SurvivorCompanion
    local run = harness.followRoad
    local px, py = xy(harness.player)
    if not px then return false end
    local elapsed = (current - run.startedAt) / 1000
    local dt = run.lastSampleAt and (current - run.lastSampleAt) / 1000 or 0
    local playerSpeed = dt > 0 and math.sqrt((px - run.lastPx)^2
        + (py - run.lastPy)^2) / dt or 0
    run.lastPx, run.lastPy, run.lastSampleAt = px, py, current
    local progress = px - START_X
    run.maxProgress = math.max(run.maxProgress or 0, progress)
    local phase = run.arrivedAt and "catchup" or "run"
    if not run.lastPerfAt or current - run.lastPerfAt >= 1000 then
        local perf = SC.Performance and SC.Performance.snapshot() or {}
        put(table.concat({ "SC_FOLLOW_PERF", string.format("%.2f", elapsed),
            tostring(perf.frames), tostring(perf.overBudgetFrames),
            tostring(perf.deferredFrames), tostring(perf.yieldedJobs),
            string.format("%.3f", tonumber(perf.p95FrameMs) or 0),
            tostring(perf.loadLevel) }, "\t"))
        run.lastPerfAt = current
    end
    for _, follower in ipairs(run.followers) do
        local actor = follower.actor
        local x, y = xy(actor)
        local speed = dt > 0 and x and follower.lastX
            and math.sqrt((x - follower.lastX)^2
                + (y - follower.lastY)^2) / dt or 0
        follower.lastX, follower.lastY = x, y
        local gap = x and math.sqrt((px - x)^2 + (py - y)^2) or math.huge
        local trail = x and px - x or math.huge
        follower.maxGap = math.max(follower.maxGap or 0, gap)
        follower.finalGap = gap
        if playerSpeed >= 1.5 and speed < 0.3 then
            follower.stillSeconds = (follower.stillSeconds or 0) + dt
            follower.currentPause = (follower.currentPause or 0) + dt
            follower.longestPause = math.max(follower.longestPause or 0,
                follower.currentPause)
        else
            follower.currentPause = 0
        end
        local decision = SC.Decision.peek(actor) or {}
        local commands = SC.Commands.peek(actor) or {}
        local navigation = SC.Navigation.peek(actor) or {}
        local navStatus = SC.Navigation.status(actor) or {}
        local formation = SC.Positioning.debug(actor) or {}
        local treatment = SC.Medical and SC.Medical.peek(actor) or nil
        local assessment = SC.Medical and SC.Medical.assessCached(actor, nil, 100)
            or {}
        local playerMoving = select(1, SC.GameplayUtil.call(
            harness.player, "isMoving"))
        local fields = {
            string.format("%.2f", elapsed), phase,
            string.format("%.2f", progress), string.format("%.2f", playerSpeed),
            tostring(follower.id), tostring(follower.name),
            string.format("%.2f", gap), string.format("%.2f", trail),
            string.format("%.2f", speed),
            tostring(decision.current), tostring(decision.intent),
            tostring(navigation.pathReason), tostring(navigation.terminalReason),
            tostring(navigation.blockerType),
            tostring(formation.formationMode), tostring(formation.formationShape),
            tostring(formation.holdingFormation),
            tostring(formation.catchUpActive), tostring(formation.catchUpReason),
            tostring(actor:isRunning()), tostring(harness.player:isRunning()),
            tostring(playerMoving),
            tostring(SC.Positioning.playerMoveMode(harness.player)),
            tostring(treatment and treatment.phase),
            tostring(treatment and treatment.patient
                and SC.GameplayUtil.idOf(treatment.patient)),
            tostring(assessment.health), tostring(assessment.bleedingCount),
            tostring(navStatus.phase), tostring(navStatus.pathSearchAgeMs),
            tostring(navStatus.expandedNodes),
            tostring(navStatus.lastPlanDurationMs),
            tostring(navStatus.lastFirstMotionMs),
            tostring(formation.targetKey),
            string.format("%.2f", tonumber(formation.predictionDistance) or 0),
            tostring(formation.slotLag),
            tostring(formation.openProofReason),
            tostring(x), tostring(y),
            tostring(commands.followDistance), tostring(formation.columnIndex),
            tostring(formation.travelIndex),
            tostring(commands.moveMode),
            tostring(navigation.routeReplanCount),
            tostring(navigation.yieldSince and current - navigation.yieldSince),
            tostring(navigation.yieldBlocker and SC.GameplayUtil.idOf(
                navigation.yieldBlocker)),
            tostring(navStatus.lastMovementReason),
            tostring(navigation.pathSearchYieldReason),
        }
        put(table.concat(fields, "\t"))
    end
    return true
end

local function vehicleStep(H, current, check, result, setPhase)
    local SC, run = SurvivorCompanion, H.followRoad
    if H.phase == "follow_road_car_prepare" then
        local square = getCell():getGridSquare(math.floor(START_X + DISTANCE - 5),
            math.floor(ROAD_Y + 2), 0)
        local okay, car = pcall(addVehicleDebug, "Base.CarNormal", IsoDirections.E, nil, square)
        if not check("follow_car_spawn", okay and car and car:getSquare() ~= nil,
            tostring(car)) then setPhase("finish", current) return end
        run.car = car
        car:setAlarmed(false)
        for index = 0, car:getPartCount() - 1 do
            local door = car:getPartByIndex(index):getDoor()
            if door then door:setLocked(false) end
        end
        if not check("follow_car_player_seat", car:enter(0, H.player) == true,
            "native driver seat for stationary fixture") then setPhase("finish", current) return end
        for _, row in ipairs(run.followers) do
            SC.Commands.issue(row.id, "set_ride_with_player", { enabled = true }, H.player)
        end
        setPhase("follow_road_car_board", current)
        return
    end
    if H.phase == "follow_road_car_board" then
        local ready = true
        for _, row in ipairs(run.followers) do
            if row.actor:getVehicle() ~= run.car then ready = false end
        end
        if ready then
            local seats = {}
            for _, row in ipairs(run.followers) do seats[run.car:getSeat(row.actor)] = true end
            local count = 0 for _ in pairs(seats) do count = count + 1 end
            if not check("follow_car_three_native_passengers", count == 3 and not seats[0],
                "distinct real passenger seats=" .. count) then setPhase("finish", current) return end
            require "Vehicles/TimedActions/ISExitVehicle"
            ISTimedActionQueue.add(ISExitVehicle:new(H.player))
            setPhase("follow_road_car_player_exit", current)
        elseif current - H.phaseStartedAt > 60000 then
            check("follow_car_three_native_passengers", false, "boarding timed out")
            setPhase("finish", current)
        end
        return
    end
    if H.phase == "follow_road_car_player_exit" then
        if H.player:getVehicle() == nil then
            require "Vehicles/TimedActions/ISPathFindAction"
            ISTimedActionQueue.add(ISPathFindAction:pathToLocationF(H.player,
                START_X + DISTANCE + 10, ROAD_Y, 0))
            H.player:setRunning(false)
            run.playerExitedAt = current
            setPhase("follow_road_car_resume", current)
        elseif current - H.phaseStartedAt > 15000 then
            check("follow_car_player_exit", false, "stock exit action timed out")
            setPhase("finish", current)
        end
        return
    end
    local allResumed = true
    for _, row in ipairs(run.followers) do
        if row.actor:getVehicle() == nil and not row.exitedAt then
            row.exitedAt, row.exitX, row.exitY = current, xy(row.actor)
        end
        local x, y = xy(row.actor)
        if row.exitedAt and not row.resumedAt and x
            and (x - row.exitX)^2 + (y - row.exitY)^2 >= 0.35^2 then
            row.resumedAt = current
        end
        if not row.resumedAt then allResumed = false end
    end
    if current >= (run.nextCarTraceAt or 0) then
        run.nextCarTraceAt = current + 1000
        for _, row in ipairs(run.followers) do
            local decision = SC.Decision.peek(row.actor) or {}
            local nav = SC.Navigation.status(row.actor) or {}
            print("SC_FOLLOW_CAR|" .. row.name .. "|in_car=" .. tostring(row.actor:getVehicle() ~= nil)
                .. "|decision=" .. tostring(decision.current) .. "|intent=" .. tostring(decision.intent)
                .. "|nav=" .. tostring(nav.pathReason) .. "|phase=" .. tostring(nav.phase)
                .. "|search_ms=" .. tostring(nav.pathSearchAgeMs)
                .. "|gap=" .. SC.GameplayUtil.distance(row.actor, H.player))
        end
    end
    if allResumed and current - run.playerExitedAt >= 10000
        or current - H.phaseStartedAt > 25000 then
        for index, row in ipairs(run.followers) do
            local delay = row.resumedAt and row.exitedAt and row.resumedAt - row.exitedAt
            check("follow_car_resume_" .. index, delay ~= nil and delay <= 3000,
                "exit_ms=" .. tostring(row.exitedAt and row.exitedAt - run.playerExitedAt)
                    .. " first_motion_ms=" .. tostring(delay)
                    .. " gap=" .. SC.GameplayUtil.distance(row.actor, H.player))
        end
        pcall(function() getCore():TakeFullScreenshot(H.config.run_id .. "-follow-car-resumed") end)
        setPhase("finish", current)
    end
end

function Probe.step(harness, current, check, result, setPhase)
    local phase = harness.phase
    local SC = SurvivorCompanion
    if phase:find("follow_road_car_", 1, true) == 1 then
        return vehicleStep(harness, current, check, result, setPhase)
    end
    if phase == "follow_road_prepare" then
        if current - harness.phaseStartedAt < 5500 then return end
        local followers = {}
        for _, record in ipairs(SC.Registry.records() or {}) do
            if record.actor and record.recruited == true
                and record.actor:isDead() ~= true then
                followers[#followers + 1] = {
                    actor = record.actor, id = record.id,
                    name = tostring(SC.GameplayUtil.nameOf(record.actor)),
                }
            end
        end
        if #followers < 3 and current - harness.phaseStartedAt < 25000 then return end
        if not check("follow_road_roster", #followers >= 3,
            "recruited=" .. tostring(#followers)) then
            setPhase("finish", current) return
        end
        while #followers > 3 do table.remove(followers) end
        harness.followRoad = { followers = followers, zombiesRemoved = 0 }
        -- Normalize only the disposable clone. The source observer carries
        -- 132 kg and several residents have old wounds that draw medics off
        -- Follow; either would obscure movement timing on this road.
        harness.player:setMaxWeightBase(200)
        harness.player:setMaxWeight(200)
        for _, record in ipairs(SC.Registry.records() or {}) do
            local body = record.actor and record.actor:getBodyDamage()
            if body then body:RestoreToFullHealth() end
        end
        result("PASS", "follow_road_fixture_weight",
            "weight=" .. tostring(harness.player:getInventoryWeight())
                .. " limit=" .. tostring(harness.player:getMaxWeight()))
        harness.player:teleportTo(START_X, ROAD_Y, 0)
        setPhase("follow_road_stage", current)
        return
    end
    local run = harness.followRoad
    if phase == "follow_road_stage" then
        if current - harness.phaseStartedAt < 2200 then return end
        local cell = getCell()
        local sites = {}
        local roadCount = 0
        for _, offset in ipairs({ 0, 10, 20, 30, 40, 50 }) do
            local square = cell:getGridSquare(math.floor(START_X) + offset,
                math.floor(ROAD_Y), 0)
            local name = roadName(square)
            sites[#sites + 1] = tostring(offset) .. ":" .. name
            if string.find(string.lower(name), "street", 1, true)
                or string.find(string.lower(name), "road", 1, true) then
                roadCount = roadCount + 1
            end
        end
        result("PASS", "follow_road_surface_survey", table.concat(sites, ","))
        if not check("follow_road_street", roadCount >= 3,
            "road_samples=" .. tostring(roadCount)) then
            setPhase("finish", current) return
        end
        run.zombiesRemoved = clearCorridor()
        if harness.config.follow_road_isolated == "true" then
            -- The cloned save can retain care claims even after wounds are
            -- healed. Keep this road probe about formation movement only.
            if SC.Medical then
                for _, record in ipairs(SC.Registry.records() or {}) do
                    if record.actor and type(SC.Medical.cancel) == "function" then
                        SC.Medical.cancel(record.actor, "follow_road_isolation", true)
                    end
                end
                if type(SC.Medical.hasActionableNeed) == "function" then
                    SC.Medical.hasActionableNeed = function() return false end
                end
                if type(SC.Medical.sameCareGroup) == "function" then
                    SC.Medical.sameCareGroup = function(helper, patient)
                        return helper == patient
                    end
                end
                if type(SC.Medical.travelRescueEligible) == "function" then
                    SC.Medical.travelRescueEligible = function(helper, patient)
                        return helper == patient
                    end
                end
            end
            local measured = {}
            for _, follower in ipairs(run.followers) do
                measured[follower.id] = true
            end
            local parked = 0
            for _, record in ipairs(SC.Registry.records() or {}) do
                if record.actor and record.recruited == true
                    and record.actor:isDead() ~= true
                    and not measured[record.id] then
                    local accepted = SC.Commands.issue(record.id, "stay",
                        nil, harness.player)
                    if accepted then
                        parked = parked + 1
                        record.actor:teleportTo(START_X - 18 - parked,
                            ROAD_Y - 10, 0)
                    end
                end
            end
            result("PASS", "follow_road_isolated", "parked=" .. parked)
        end
        local fanOut = harness.config.follow_road_fan_out == "true"
        local enabled, reason = SC.Commands.issue(nil,
            "set_follow_fan_out", { scope = "team", enabled = fanOut },
            harness.player)
        result(enabled and "PASS" or "FAIL", "follow_road_fan_out",
            tostring(reason))
        if not enabled then setPhase("finish", current) return end
        local ordered = 0
        for index, follower in ipairs(run.followers) do
            local actor = follower.actor
            actor:teleportTo(START_X - (index + 1), ROAD_Y + (index - 2), 0)
            local accepted, reason = SC.Commands.issue(follower.id, "follow",
                nil, harness.player)
            result(accepted and "PASS" or "FAIL", "follow_road_order_" .. index,
                "id=" .. tostring(follower.id) .. " reason=" .. tostring(reason))
            if accepted then ordered = ordered + 1 end
        end
        if ordered < #run.followers then setPhase("finish", current) return end
        setPhase("follow_road_settle", current)
        return
    end
    if phase == "follow_road_settle" then
        if current - harness.phaseStartedAt < 2500 then return end
        require "Vehicles/TimedActions/ISPathFindAction"
        local action = ISPathFindAction:pathToLocationF(harness.player,
            START_X + DISTANCE, ROAD_Y, 0)
        local queued, failure = pcall(function() ISTimedActionQueue.add(action) end)
        if not check("follow_road_player_path", queued,
            tostring(failure)) then setPhase("finish", current) return end
        harness.player:setRunning(true)
        run.startedAt = current
        run.lastPx, run.lastPy = xy(harness.player)
        run.nextSampleAt = current
        put("seconds\tphase\tplayer_progress\tplayer_speed\tid\tname\tgap\ttrail\tfollower_speed\tdecision\tintent\tnav_reason\tnav_terminal\tnav_blocker\tformation\tshape\tholding\tcatchup\tcatchup_reason\tfollower_running\tplayer_running\tplayer_isMoving\tplayer_mode\tmedical_phase\tmedical_patient\thealth\tbleeding\tnav_phase\tsearch_age_ms\texpanded_nodes\tlast_plan_ms\tfirst_motion_ms\tformation_target\tprediction_distance\tslot_lag\topen_proof\tx\ty\tfollow_distance\tcolumn_index\ttravel_index\tmove_mode\treplans\tyield_wait_ms\tyield_blocker\tlast_movement_reason\tsearch_yield_reason")
        setPhase("follow_road_run", current)
        return
    end
    if phase == "follow_road_run" or phase == "follow_road_catchup" then
        harness.player:setRunning(phase == "follow_road_run")
        if current >= run.nextSampleAt then
            run.zombiesRemoved = run.zombiesRemoved + clearCorridor()
            sample(harness, current)
            run.nextSampleAt = current + 250
        end
        local px = xy(harness.player)
        if phase == "follow_road_run" and px and px - START_X >= 49 then
            run.arrivedAt = current
            result("PASS", "follow_road_player_50_tiles",
                string.format("elapsed=%.2fs progress=%.2f removed_zombies=%d",
                    (current - run.startedAt) / 1000, px - START_X,
                    run.zombiesRemoved))
            setPhase("follow_road_catchup", current)
        elseif phase == "follow_road_run" and current - run.startedAt > 100000 then
            result("FAIL", "follow_road_player_50_tiles",
                "timeout progress=" .. tostring(run.maxProgress))
            setPhase("finish", current)
        elseif phase == "follow_road_catchup"
            and current - run.arrivedAt >= 12000 then
            for index, follower in ipairs(run.followers) do
                result("PASS", "follow_road_follower_" .. index,
                    string.format("max_gap=%.2f final_gap=%.2f still_while_player_running=%.1fs longest_pause=%.1fs",
                        follower.maxGap or 0, follower.finalGap or 0,
                        follower.stillSeconds or 0, follower.longestPause or 0))
            end
            result("PASS", "follow_road_trace",
                "cache/console.txt SC_FOLLOW_ROAD lines")
            setPhase(harness.config.follow_road_vehicle == "true"
                and "follow_road_car_prepare" or "finish", current)
        end
    end
end

return Probe
