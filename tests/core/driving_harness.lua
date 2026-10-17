-- SPDX-License-Identifier: MIT
local SC, T = SurvivorCompanion, SC_DRIVING_TEST
local Driving, Supervisor = SC.Driving, SC.ActionSupervisor
local checks = 0
local function check(ok, message)
    checks = checks + 1
    assert(ok, "driving check " .. tostring(checks) .. ": " .. message)
end
local player = { id = "player", x = 99, y = 100, z = 0, getVehicle = function() return nil end }
local goal = { x = 200, y = 100, z = 0 }
local function manual(id)
    local actor = T.actor(id)
    check(Driving.start(actor), "native wheel starts under a drive lease")
    return actor
end
local function managed(id, options)
    local actor = T.actor(id)
    check(Driving.drive(actor, goal, options), "bounded driving job starts")
    return actor
end

do
    local actor = managed("taxi-corner-speed", { speedKmh = 20,
        cornerSpeedScale = 2 })
    check(T.tunedFollow and T.tunedFollow.actor == actor
        and T.tunedFollow.speed == 20 and T.tunedFollow.scale == 2,
        "taxi route forwards its corner setting to the native bridge")
    Driving.release(actor)
    T.tunedFollow = nil
end

do
    for _, entry in ipairs({ "begin", "drive" }) do
        local actor = T.actor("drive-urgent-" .. entry)
        local savedNativeActions, held, urgentToken = SC.NativeActions, true, nil
        SC.NativeActions = { activityStatus = function(candidate)
            if candidate == actor and held then return "active", "native", "held_action", SC_TEST_CLOCK end
            return "none"
        end }
        check(Supervisor.queueUrgent(actor, {
            owner = "survival", action = "flee", priority = Supervisor.Priority.SURVIVAL,
            dispatch = function(candidate)
                urgentToken = assert(Supervisor.begin(candidate, {
                    owner = "survival", action = "flee", priority = Supervisor.Priority.SURVIVAL,
                }))
                return true, "flee_started"
            end,
        }) and urgentToken == nil, "urgent work queues behind an existing native action")
        held = false
        local motion, parks, plans = T.motionCalls, T.parks, #T.plans
        local accepted, reason = Driving[entry](actor, goal)
        SC.NativeActions = savedNativeActions
        check(not accepted and string.find(tostring(reason), "deferred:", 1, true) == 1
            and Supervisor.containsDeferredStatus(reason) and Supervisor.current(actor) == urgentToken,
            entry .. " preserves the urgent owner's deferred response for a later retry")
        check(Driving.jobStatus(actor) == nil and not Driving.isDriving(actor)
            and T.motionCalls == motion and T.parks == parks and #T.plans == plans
            and (T.native[actor] == nil or not T.native[actor].active)
            and Supervisor.retryStatusAny(actor, "drive_route", "200:100:0") == nil,
            "deferring to urgent work creates no drive job, native control or retry refusal")
        check(Supervisor.cancel(actor, "urgent_finished", nil, true) and Driving.drive(actor, goal),
            "the deferred caller can start its route after urgent work releases ownership")
        Driving.release(actor)
    end
end

do
    local actor = T.actor("drive-preflight-wait")
    check(Driving.begin(actor, goal), "preflight claims the parked seat before planning")
    local exits = T.exits
    check(SC.Decision.update(actor, player, T.runtime()) and T.exits == exits,
        "normal AI cannot eject a waiting preflight driver")
    check(Driving.drive(actor, goal) and Driving.jobStatus(actor).phase == "following",
        "the job adopts its matching unstarted waiting lease")
    Driving.release(actor)
end

do
    local actor = manual("drive-held")
    T.block(actor, 145, 100)
    local exits, combat = T.exits, T.combatCalls
    local handled, reason = SC.Decision.update(actor, player, T.runtime())
    check(handled and reason == "driving" and T.exits == exits and T.combatCalls == combat,
        "a stopped blocked driver retains seat zero before combat and exit policy")
    SC_TEST_CLOCK = SC_TEST_CLOCK + 600000
    check(Supervisor.current(actor).owner == "drive", "a long wait has no arbitrary deadline")
    T.native[actor].mode, T.native[actor].state = "arrived", "arrived"
    Driving.tick()
    check(T.native[actor].active and Driving.isDriving(actor),
        "a manual route arrival keeps its wheel available for the caller's return turn")
    check(Driving.release(actor), "explicit release gives back the wheel and lease")
    check(Supervisor.current(actor) == nil and T.native[actor].active == false,
        "release clears both native and Lua ownership")
end

do
    local savedFaction = SC.FactionBehavior
    local zombie = { x = 101, y = 100, z = 0 }
    local human = { actor = { x = 102, y = 100, z = 0 }, distance = 2, visible = true }
    local healthy = { downed = false, critical = false, bleedingCount = 0 }
    for _, mode in ipairs({ "stopped", "moving", "turning" }) do
        local actor = manual("drive-foot-threat-" .. mode)
        if mode == "moving" then
            check(Driving.followRoute(actor, { { x = 100, y = 100 }, { x = 200, y = 100 } }),
                "the healthy threat fixture follows a moving route")
        elseif mode == "turning" then
            check(Driving.turnAround(actor, true), "the healthy threat fixture turns its car")
        end
        for _, threat in ipairs({
            { name = "immediate zombie contact", snapshot = { immediateCount = 1,
                immediateAttackers = { { actor = zombie } }, threats = { { actor = zombie } }, threatCount = 1 } },
            { name = "engagement pressure", snapshot = { pressure = 4 } },
            { name = "player danger", snapshot = { player = { danger = 2 } } },
            { name = "human threat", snapshot = { humanThreat = human } },
        }) do
            local runtime = T.runtime()
            for key, value in pairs(threat.snapshot) do runtime.snapshot[key] = value end
            SC.FactionBehavior = { humanThreatFor = function() return threat.snapshot.humanThreat end }
            local exits, parks = T.exits, T.parks
            local handled, reason = SC.Decision.update(actor, player, runtime)
            check(handled and reason == "driving" and T.exits == exits and T.parks == parks
                and T.native[actor].active and Supervisor.current(actor).owner == "drive",
                "healthy " .. mode .. " driver retains its wheel and seat during " .. threat.name)
            check(SC.Decision._ownerNeedsImmediatePreemptionForTests(
                "work", runtime.snapshot, healthy, {}, { order = "follow" }) == true,
                threat.name .. " still preempts the existing on-foot work owner")
        end
        Driving.release(actor)
    end
    SC.FactionBehavior = savedFaction
end

do
    local savedNeeds = SC.Needs
    SC.Needs = { assess = function(actor) return { emergency = actor.needsEmergency == true } end }
    for _, emergency in ipairs({ "critical", "downed", "needsEmergency", "retreat" }) do
        local actor = manual("drive-emergency-" .. emergency)
        if emergency == "retreat" then
            actor.data.SC_Order = "retreat"
            SC.Commands.reset(actor)
        else actor[emergency] = true end
        check(SC.Decision.update(actor, player, T.runtime())
            and Driving.jobStatus(actor).reason == "survival_priority"
            and not T.native[actor].active and Supervisor.current(actor) == nil,
            emergency .. " still parks and releases a seated driver")
    end
    SC.Needs = savedNeeds
end

do
    local actor = manual("drive-medical")
    actor.bleeding = true
    local exits = T.exits
    check(SC.Decision.update(actor, player, T.runtime()), "survival preemption reaches normal control")
    check(Driving.jobStatus(actor).reason == "survival_priority"
        and T.native[actor].active == false and Supervisor.current(actor) == nil
        and T.exits == exits + 1, "bleeding parks before the ordinary safe-exit policy")
end

do
    local actor = manual("drive-hostile")
    actor.data.SC_Recruited, T.records[actor.id].recruited = false, false
    SC.Commands.reset(actor)
    SC.FactionBehavior = { intentFor = function() return { mode = "hostile" } end }
    check(SC.Decision.update(actor, player, T.runtime()), "hostile faction policy preempts the lease")
    check(Driving.jobStatus(actor).reason == "faction_priority" and not T.native[actor].active,
        "faction emergency uses the existing immediate-control policy")
    SC.FactionBehavior = nil
end

do
    local actor = manual("drive-orders")
    check(SC.Commands.issue(actor.id, "set_follow_distance", 5, player),
        "a valid policy change remains available while driving")
    check(Driving.isDriving(actor), "policy controls do not release the wheel")
    check(not SC.Commands.issue(actor.id, "unknown_command", nil, player)
        and Driving.isDriving(actor), "a rejected non-order does not interrupt driving")
    check(SC.Commands.issue(actor.id, "follow", nil, player), "player movement order is accepted")
    check(Driving.jobStatus(actor).reason == "player_order"
        and Supervisor.current(actor) == nil and not T.native[actor].active,
        "player order parks before changing physical control")
end

do
    local savedBaseLife, assignments = SC.BaseLife, 0
    SC.BaseLife = {
        ROLES = { farmer = true },
        active = function() return { core = { x = 100, y = 100, z = 0 } } end,
        assign = function() return true end,
        applyResidentAssignment = function(assignment)
            local actor = T.records[assignment.actorId].actor
            if T.native[actor].active or Supervisor.current(actor) ~= nil then
                return false, "driver_not_parked"
            end
            assignments = assignments + 1
            return true
        end,
    }
    for _, parked in ipairs({ false, true }) do
        local actor = managed(parked and "drive-parked-base-role" or "drive-active-base-role")
        if parked then
            actor.vehicle.x, actor.vehicle.y = goal.x, goal.y
            T.native[actor].state, T.native[actor].mode = "arrived", "arrived"
            Driving.tick()
        end
        local assigned, reason = SC.Commands.issue(actor.id, "set_base_role", { role = "farmer" }, player)
        check(assigned and actor.data.SC_Order == "base_duty" and not T.native[actor].active
            and Supervisor.current(actor) == nil and Driving.jobStatus(actor).reason == "player_order",
            "a base-role order parks and releases the drive before assignment: " .. tostring(reason))
    end
    local actor = managed("drive-base-role-park-rejected")
    T.stopRejected = true
    check(not SC.Commands.issue(actor.id, "set_base_role", { role = "farmer" }, player)
        and assignments == 2 and actor.data.SC_Order == "follow" and T.native[actor].active,
        "a rejected park cannot commit the base-role assignment")
    T.stopRejected = false
    Driving.release(actor)
    SC.BaseLife = savedBaseLife
end

do
    local actor = manual("drive-player")
    actor.vehicle.playerAboard = true
    Driving.tick()
    check(Driving.jobStatus(actor).reason == "player_aboard"
        and Supervisor.current(actor) == nil and not T.native[actor].active,
        "player boarding releases native and Lua ownership")
    local cachedApi = SCBridge
    actor = manual("drive-bridge-loss")
    SCBridge = nil
    Driving.tick()
    check(not T.native[actor].active and Supervisor.current(actor) == nil
        and Driving.jobStatus(actor).reason == "bridge_failure",
        "missing global bridge parks through cached cleanup authority")
    SCBridge = cachedApi
    actor = manual("drive-native-release")
    T.native[actor].active, T.native[actor].reason = false, "no_controller"
    Driving.tick()
    check(Supervisor.current(actor) == nil and Driving.jobStatus(actor).reason == "no_controller",
        "native driver release cannot strand its Lua owner")
    actor = manual("drive-death")
    actor.dead = true
    Driving.tick()
    check(Supervisor.current(actor) == nil and not T.native[actor].active,
        "a driver death releases both ownership layers")
end

do
    local actor = manual("drive-open-health")
    SC.UI = { openHealth = function(patient)
        return patient == actor and T.native[actor].active == false
            and Supervisor.current(actor) == nil
    end }
    check(SC.Commands.issue(actor.id, "open_health", nil, player),
        "player treatment panel opens only after parking and releasing the drive")
    SC.UI = nil
    local first, second = manual("drive-group-one"), manual("drive-group-two")
    first.data.SC_Group, second.data.SC_Group = "alpha", "alpha"
    SC.Commands.reset(first)
    SC.Commands.reset(second)
    check(SC.Commands.issue(first.id, "stay", { scope = "group", group = "alpha" }, player)
        and not T.native[first].active and not T.native[second].active,
        "a committed group movement order preempts every driving group member")
end

do
    local actor = managed("drive-replan")
    local before = #T.plans
    T.block(actor, 147, 106)
    Driving.tick(1000)
    Driving.tick(6000)
    local status = Driving.jobStatus(actor)
    check(status.attempts == 1 and #status.circles == 1
        and status.circles[1].x == 147 and status.circles[1].y == 106
        and T.plans[#T.plans].circles == "147.00,106.00,12.00" and #T.plans == before + 1,
        "replanning avoids the reported world point, never blockedAt distance")
    T.block(actor, 169, 102)
    Driving.tick(7000)
    Driving.tick(12000)
    check(T.plans[#T.plans].circles == "147.00,106.00,12.00;169.00,102.00,12.00",
        "later replanning retains all earlier avoidance circles")
    actor.vehicle.x, actor.vehicle.y = goal.x, goal.y
    T.native[actor].mode, T.native[actor].state = "arrived", "arrived"
    Driving.tick(12250)
    status = Driving.jobStatus(actor)
    check(status.phase == "arrived" and status.result == "arrived" and status.parked
        and not T.native[actor].active and Driving.isDriving(actor),
        "arrival releases pedals and preserves the parked seat lease")
    local exits = T.exits
    check(SC.Decision.update(actor, player, T.runtime()) and T.exits == exits,
        "arrival is not an implicit request to get out")
    actor.vehicle.playerAboard = true
    Driving.tick()
    check(Supervisor.current(actor) == nil, "player boarding also ends a terminal parked lease")
end

do
    T.planEnd = { x = 150, y = 100 }
    local actor = T.actor("drive-road-exit-arrival")
    local route = SC.ExpeditionRoute.planAvoidingAll(actor, goal, {})
    check(route and route.points[#route.points].x == 150 and route.goal.x == 200,
        "the expedition planner keeps its road exit distinct from the requested off-road goal")
    check(Driving.drive(actor, goal), "a route to a different road exit starts under managed control")
    T.planEnd = nil
    actor.vehicle.x, actor.vehicle.y = 150, 100
    T.native[actor].state, T.native[actor].mode, T.native[actor].remaining = "arrived", "arrived", 0
    Driving.tick()
    local status = Driving.jobStatus(actor)
    check(status.phase == "arrived" and status.result == "arrived"
        and status.parked and not T.native[actor].active and Driving.isDriving(actor),
        "the road attachment completes before the separate off-road approach")
    local exits = T.exits
    check(SC.Decision.update(actor, player, T.runtime()) and T.exits == exits,
        "road arrival parks and retains the job's seat lease for the next approach")
    Driving.release(actor)
    actor = managed("drive-near-goal-arrival")
    actor.vehicle.x, actor.vehicle.y = goal.x - 5, goal.y + 2.5
    T.native[actor].state, T.native[actor].mode = "arrived", "arrived"
    Driving.tick()
    check(Driving.jobStatus(actor).phase == "arrived" and not T.native[actor].active,
        "vehicle readback accepts the normal near-end window and right-lane offset")
    Driving.release(actor)
    actor = managed("drive-arrival-position-unavailable")
    actor.vehicle.getX = nil
    T.native[actor].state, T.native[actor].mode = "arrived", "arrived"
    Driving.tick()
    check(Driving.jobStatus(actor).reason == "goal_position_unavailable"
        and not T.native[actor].active and Driving.isDriving(actor),
        "an unreadable car position cannot verify managed arrival")
    Driving.release(actor)
end

do
    local actor = managed("drive-streaming-wait")
    local plans = #T.plans
    T.block(actor, 145, 100)
    T.native[actor].obstacleKind = "unloaded"
    Driving.tick(60000)
    Driving.tick(70000)
    local status = Driving.jobStatus(actor)
    check(status.phase == "streaming_wait" and #status.circles == 0
        and #T.plans == plans,
        "unloaded chunks wait for streaming without spending avoidance circles")
    Driving.tick(90001)
    status = Driving.jobStatus(actor)
    check(status.reason == "streaming_stalled" and #status.circles == 0
        and #T.plans == plans,
        "bounded streaming stall parks for recovery without a fake obstruction")
    Driving.release(actor)
end

do
    T.planEnd = { x = 190, y = 100 }
    local actor = managed("drive-road-attachment")
    actor.vehicle.x, actor.vehicle.y = 190, 100
    T.native[actor].state, T.native[actor].mode = "arrived", "arrived"
    Driving.tick()
    check(Driving.jobStatus(actor).result == "arrived",
        "road leg accepts its routed attachment before the separate driveway approach")
    Driving.release(actor)
    T.planEnd = nil

    actor = managed("drive-safety-brake")
    local plans = #T.plans
    T.native[actor].state, T.native[actor].mode = "safety_blocked", "follow"
    T.native[actor].blockedX, T.native[actor].blockedY = 105, 100
    Driving.tick(100000)
    Driving.tick(105000)
    check(Driving.jobStatus(actor).attempts == 1 and #T.plans == plans + 1,
        "real bumper safety brake enters the bounded route recovery despite FOLLOW")
    Driving.release(actor)

    actor = managed("drive-physical-stall")
    plans = #T.plans
    T.native[actor].engineRunning = true
    T.native[actor].cruiseKmh = 10
    T.native[actor].speedKmh = 0
    Driving.tick(120000)
    Driving.tick(132000)
    Driving.tick(137000)
    check(Driving.jobStatus(actor).attempts == 1 and #T.plans == plans + 1,
        "an engine-running car without physical displacement cannot follow forever")
    Driving.release(actor)
end

do
    local actor = managed("drive-limit")
    local planCount = #T.plans
    for attempt = 1, 4 do
        T.block(actor, 140 + attempt * 10, 100)
        Driving.tick(attempt * 6000)
        Driving.tick(attempt * 6000 + 5000)
    end
    local status = Driving.jobStatus(actor)
    check(status.phase == "failed" and status.reason == "route_blocked"
        and status.attempts == 3 and #T.plans == planCount + 3 and #status.circles == 3,
        "three replans are a hard bound, then route_blocked is reported")
    check(not T.native[actor].active and Driving.isDriving(actor),
        "a route-blocked driver parks and stays with the car until release")
    Driving.release(actor)
    local circles = {}
    for index = 1, 8 do circles[index] = { x = 50 + index, y = 90, radius = 12 } end
    actor = managed("drive-circle-cap", { circles = circles })
    T.block(actor, 150, 100)
    Driving.tick(40000)
    Driving.tick(45000)
    status = Driving.jobStatus(actor)
    check(status.reason == "route_blocked" and #status.circles == 8,
        "a blocked job never creates a ninth avoidance circle")
    Driving.release(actor)
    circles[9] = { x = 60, y = 90, radius = 12 }
    local plans = #T.plans
    check(SC.ExpeditionRoute.planAvoidingAll(actor, goal, circles) == nil and #T.plans == plans,
        "the public multi-circle Lua planner rejects nine circles before native dispatch")
    actor = T.actor("drive-nine-circles")
    check(not Driving.drive(actor, goal, { circles = circles })
        and Supervisor.current(actor) == nil, "invalid initial avoidance bounds release the lease")
end

do
    T.planStatus = "NO_ROUTE"
    local actor = managed("drive-no-route")
    check(Driving.jobStatus(actor).reason == "no_route" and not T.native[actor].active,
        "unavailable alternate route is reported with a parked car")
    Driving.release(actor)
    T.planStatus = "READY"
    actor = managed("drive-turn-failure")
    T.native[actor].mode = "turn_failed"
    Driving.tick()
    check(Driving.jobStatus(actor).reason == "turn_failed" and not T.native[actor].active,
        "turn failure terminates the bounded job and parks")
    Driving.release(actor)
    actor = managed("drive-missing-block-position")
    T.block(actor, nil, nil)
    local plans = #T.plans
    Driving.tick(50000)
    Driving.tick(55000)
    check(Driving.jobStatus(actor).reason == "invalid_blocked_position" and #T.plans == plans,
        "missing world coordinates fail safely instead of guessing a blocked point")
    Driving.release(actor)
    actor = managed("drive-engine-failure")
    T.native[actor].state = "engine_failed"
    Driving.tick()
    check(Driving.jobStatus(actor).reason == "engine_failed" and not T.native[actor].active,
        "exhausted native engine-start attempts cannot leave the job following forever")
    Driving.release(actor)
end

do
    for _, result in ipairs({ "arrived", "failed" }) do
        local actor = managed("drive-terminal-" .. result)
        if result == "arrived" then actor.vehicle.x, actor.vehicle.y = goal.x, goal.y end
        T.native[actor].state, T.native[actor].mode = result == "arrived" and "arrived" or "turn_failed",
            result == "arrived" and "arrived" or "turn_failed"
        Driving.tick()
        local token, calls = Supervisor.current(actor), T.motionCalls
        local route = { { x = 100, y = 100 }, { x = 200, y = 100 } }
        for _, attempt in ipairs({
            { name = "start", call = function() return Driving.start(actor) end },
            { name = "followRoute", call = function() return Driving.followRoute(actor, route, 10) end },
            { name = "turnAround", call = function() return Driving.turnAround(actor, true) end },
            { name = "cruise", call = function() return Driving.cruise(actor, 10, 0, true) end },
            { name = "hold", call = function() return Driving.hold(actor) end },
        }) do
            local accepted, reason = attempt.call()
            check(accepted == false and reason == "drive_requires_release" and T.motionCalls == calls,
                result .. " managed lease rejects " .. attempt.name .. " before native motion dispatch")
        end
        local status = Driving.jobStatus(actor)
        check(status.phase == result and status.result == result and status.parked
            and Supervisor.current(actor) == token and not T.native[actor].active and Driving.isDriving(actor),
            "rejected motion preserves the terminal result and parked seat lease")
        check(Driving.release(actor) and Driving.drive(actor, goal)
            and T.native[actor].active and Driving.jobStatus(actor).phase == "following",
            "explicit release permits a fresh managed route after " .. result)
        Driving.release(actor)
    end
end

do
    local actor = managed("drive-active-motion-guard")
    local token, calls = Supervisor.current(actor), T.motionCalls
    local route = { { x = 100, y = 100 }, { x = 150, y = 100 } }
    for _, attempt in ipairs({
        { name = "start", call = function() return Driving.start(actor) end },
        { name = "followRoute", call = function() return Driving.followRoute(actor, route, 10) end },
        { name = "turnAround", call = function() return Driving.turnAround(actor, true) end },
        { name = "cruise", call = function() return Driving.cruise(actor, 10, 0, true) end },
        { name = "hold", call = function() return Driving.hold(actor) end },
    }) do
        local accepted, reason = attempt.call()
        check(accepted == false and reason == "drive_job_active" and T.motionCalls == calls,
            "the active managed route rejects public " .. attempt.name .. " before native dispatch")
    end
    Driving.tick()
    check(Driving.jobStatus(actor).phase == "following" and T.native[actor].state == "following"
        and Supervisor.current(actor) == token, "rejected manual motion leaves the managed route following")
    check(Driving.release(actor) and Driving.start(actor),
        "manual driving remains available after explicitly releasing a managed route")
    Driving.release(actor)
    check(Driving.jobStatus(actor) ~= nil and Driving.releaseActor(actor)
        and Driving.jobStatus(actor) == nil, "actor retirement explicitly clears the completed drive outcome")
    actor = managed("drive-retirement-park-rejected")
    T.stopRejected = true
    check(SC.Runtime.releaseActor(actor) == false and Supervisor.current(actor) ~= nil
        and Driving.jobStatus(actor) ~= nil and T.native[actor].active,
        "retirement retains the drive token and cleanup authority when parking fails")
    T.stopRejected = false
    check(SC.Runtime.releaseActor(actor) and Driving.jobStatus(actor) == nil
        and Supervisor.current(actor) == nil and not T.native[actor].active,
        "runtime retirement retries parking and clears the drive outcome after verification")
end

do
    local actor = managed("drive-precise-parking")
    actor.vehicle.x, actor.vehicle.y = goal.x, goal.y
    T.native[actor].state, T.native[actor].mode = "arrived", "arrived"
    Driving.tick()
    local token, before = Supervisor.current(actor), T.approaches or 0
    check(Driving.approach(actor, { x = 205, y = 100, z = 0 })
        and T.approaches == before + 1
        and Supervisor.current(actor) == token
        and Driving.jobStatus(actor).phase == "approaching",
        "precise approach reuses the arrived managed lease under native control")
    actor.vehicle.x = 204.8
    T.native[actor].state, T.native[actor].mode = "arrived", "arrived"
    Driving.tick()
    check(Driving.jobStatus(actor).result == "arrived"
        and Driving.jobStatus(actor).parked,
        "approach arrival uses a one-tile position readback")
    Driving.release(actor)

    actor = managed("drive-parking-blocked")
    actor.vehicle.x, actor.vehicle.y = goal.x, goal.y
    T.native[actor].state, T.native[actor].mode = "arrived", "arrived"
    Driving.tick()
    check(Driving.approach(actor, { x = 205, y = 100, z = 0 }),
        "second managed approach starts from a parked result")
    local plans = #T.plans
    T.native[actor].state, T.native[actor].mode = "blocked", "blocked"
    Driving.tick()
    check(Driving.jobStatus(actor).result == "failed"
        and Driving.jobStatus(actor).reason == "parking_approach_blocked"
        and #T.plans == plans,
        "blocked parking stops without road avoidance or a replanned detour")
    Driving.release(actor)
end

do
    local first, second = manual("drive-reset-one"), manual("drive-reset-two")
    T.stopRejected = true
    check(Driving.stop(first, "player_order") == false and Supervisor.current(first) ~= nil
        and Driving.jobStatus(first).phase == "stopping",
        "unverified native release keeps its token and cleanup authority for retry")
    local exits = T.exits
    check(SC.Decision.update(first, player, T.runtime()) and T.exits == exits,
        "an unverified park cannot fall through and walk the native driver out")
    check(SC.Runtime.reset(true) == false and Supervisor.current(first) ~= nil,
        "teardown cannot hide a native driver which rejected parking")
    T.stopRejected = false
    check(SC.Runtime.reset(true) and not T.native[first].active and not T.native[second].active
        and Driving.jobStatus(first) == nil and Driving.jobStatus(second) == nil,
        "runtime teardown releases every driver and leaves no resumable job")
end

do
    local Convoy = SC.Convoy
    local actor = T.actor("convoy-driver")
    local follower = actor.vehicle
    follower.sqlId = 501
    function follower:getSqlId() return self.sqlId end
    local lead = { x = 110, y = 100, z = 0 }
    local localPlayer = { x = 110, y = 100, z = 0, vehicle = lead }
    function localPlayer:getVehicle() return self.vehicle end
    function lead:getDriver() return localPlayer.vehicle and localPlayer or nil end
    local oldPlayer, oldPeek, oldLiving = getPlayer, SC.Commands.peek, SC.Registry.living
    local oldLoaded = SC.Vehicle.loadedBySqlId
    getPlayer = function() return localPlayer end
    SC.Commands.peek = function(candidate)
        if candidate == actor then
            return { recruited = true, order = "follow", followCarSqlId = 501 }
        end
        return nil
    end
    SC.Registry.living = function() return { actor } end
    SC.Vehicle.loadedBySqlId = function(id) return id == 501 and follower or nil end
    Convoy.activate(actor)
    check(Convoy.step(actor, localPlayer, {}) == true and Driving.isDriving(actor),
        "assigned driver takes the native wheel while the player is in another car")
    local started = SC_TEST_CLOCK + 1000
    Convoy.tick(started)
    check(T.convoyFollow and T.convoyFollow.actor == actor
        and T.convoyFollow.leader == lead and T.convoyFollow.speed == 50,
        "rolling route targets the player's car at the convoy speed cap")
    local calls = T.motionCalls
    Convoy.tick(started + 11000)
    check(Driving.isDriving(actor) and T.motionCalls >= calls,
        "a parked player car does not falsely mark the convoy blocked")
    actor.bleeding = true
    local exitsBeforeCare = T.exits
    SC.Decision.update(actor, localPlayer, T.runtime())
    check(not Driving.isDriving(actor) and Convoy.isSurvivalSuspended(actor)
        and T.exits == exitsBeforeCare + 1,
        "bleeding convoy driver parks and reaches the safe-exit policy")
    SC.Decision.update(actor, localPlayer, T.runtime())
    check(not Driving.isDriving(actor) and Convoy.isSurvivalSuspended(actor),
        "the follow-car order cannot restart during the same emergency")
    actor.bleeding = false
    SC.Decision.update(actor, localPlayer, T.runtime())
    check(not Convoy.isSurvivalSuspended(actor) and Driving.isDriving(actor),
        "convoy resumes after the emergency clears")
    -- A lead car can finish just beyond the desired following gap. The driver
    -- must still park and leave the car when the player gets out.
    lead.x = 150
    localPlayer.vehicle = nil
    local exits = T.exits
    Convoy.tick(started + 11500)
    check(not Driving.isDriving(actor) and T.exits == exits + 1,
        "on player exit beyond the gap limit, the follower parks and gets out")
    Convoy.reset()
    getPlayer, SC.Commands.peek, SC.Registry.living = oldPlayer, oldPeek, oldLiving
    SC.Vehicle.loadedBySqlId = oldLoaded
end

do
    local Convoy = SC.Convoy
    local driver = T.actor("overflow-driver")
    local earlier = T.actor("overflow-A")
    local seated = T.actor("overflow-B")
    local car = driver.vehicle
    car.sqlId = 777
    function car:getSqlId() return self.sqlId end
    function car:getMaxPassengers() return 3 end
    function car:isSeatInstalled(seat) return seat == 1 or seat == 2 end
    function car:getCharacter(seat) return seat == 1 and seated or nil end
    seated.vehicle, earlier.vehicle = car, nil
    local lead = { x = 110, y = 100, z = 0 }
    local localPlayer = { x = 110, y = 100, z = 0, vehicle = lead }
    function localPlayer:getVehicle() return self.vehicle end
    function lead:getDriver() return localPlayer end
    local oldPeek, oldLiving, oldLoaded = SC.Commands.peek,
        SC.Registry.living, SC.Vehicle.loadedBySqlId
    local oldAssignment, oldReserved, oldSeated = SC.Vehicle.assignmentFor,
        SC.Vehicle.isSeatReserved, SC.Vehicle.isNativeSeated
    local oldBegin, oldPreflight, oldBoard = SC.Vehicle.beginBoarding,
        SC.Vehicle.preflightBoard, SC.Vehicle.board
    local optOut, boardedSeat = false, nil
    SC.Commands.peek = function(candidate)
        return { recruited = true, order = "follow",
            followCarSqlId = candidate == driver and 777 or nil,
            rideWithPlayer = candidate ~= seated or not optOut }
    end
    SC.Registry.living = function() return { driver, earlier, seated } end
    SC.Vehicle.loadedBySqlId = function(id) return id == 777 and car or nil end
    SC.Vehicle.assignmentFor = function() return nil, "vehicle_capacity_wait" end
    SC.Vehicle.isSeatReserved = function() return false end
    SC.Vehicle.isNativeSeated = function(candidate)
        if candidate == seated then return true, car, 1 end
        return false
    end
    SC.Vehicle.beginBoarding = function() return { supervisorToken = 1 } end
    SC.Vehicle.preflightBoard = function(_, _, seat) return { seat = seat } end
    SC.Vehicle.board = function(_, _, seat)
        boardedSeat = seat
        return true, "boarded"
    end
    check(Convoy.boardOverflow(earlier, localPlayer, {}) == true
        and boardedSeat == 2,
        "a new follower uses the free seat instead of displacing a seated follower")
    check(Convoy.ownsSeat(seated, car, localPlayer),
        "an opted-in overflow passenger owns the seated follow-car place")
    optOut = true
    check(not Convoy.ownsSeat(seated, car, localPlayer),
        "ride opt-out releases an overflow passenger's seat for safe exit")
    seated.data.SC_RideWithPlayer = false
    SC.Commands.reset(seated)
    local oldStationary, moving = SC.Vehicle.isStationary, true
    SC.Vehicle.isStationary = function()
        return not moving, moving and "vehicle is moving" or nil
    end
    local exitsBeforeOptOut = T.exits
    local waiting, waitReason = SC.Decision.update(seated, localPlayer, T.runtime())
    check(waiting and waitReason == "waiting_for_safe_exit"
        and T.exits == exitsBeforeOptOut,
        "an opted-out passenger waits inside a moving follow car")
    moving = false
    local exited, exitReason = SC.Decision.update(seated, localPlayer, T.runtime())
    check(exited and exitReason == "exiting_vehicle"
        and T.exits == exitsBeforeOptOut + 1,
        "an opted-out passenger exits once the follow car stops")
    SC.Vehicle.isStationary = oldStationary
    SC.Commands.peek, SC.Registry.living, SC.Vehicle.loadedBySqlId =
        oldPeek, oldLiving, oldLoaded
    SC.Vehicle.assignmentFor, SC.Vehicle.isSeatReserved,
        SC.Vehicle.isNativeSeated = oldAssignment, oldReserved, oldSeated
    SC.Vehicle.beginBoarding, SC.Vehicle.preflightBoard, SC.Vehicle.board =
        oldBegin, oldPreflight, oldBoard
    Convoy.reset()
end
do
    -- A follow car that cannot work is given up: one note, the wheel
    -- released and the assignment dropped, so the companion is not parked in
    -- that car or barred from the player's seats until a new order.
    local Convoy = SC.Convoy
    local actor = T.actor("convoy-lost")
    local car = actor.vehicle
    car.sqlId = 611
    function car:getSqlId() return self.sqlId end
    local lead = { x = 110, y = 100, z = 0 }
    local halos = 0
    local localPlayer = { x = 110, y = 100, z = 0, vehicle = lead }
    function localPlayer:getVehicle() return self.vehicle end
    function localPlayer:setHaloNote() halos = halos + 1 end
    function lead:getDriver() return localPlayer.vehicle == lead and localPlayer or nil end
    local oldPlayer, oldLiving, oldLoaded = getPlayer, SC.Registry.living,
        SC.Vehicle.loadedBySqlId
    local loaded = true
    getPlayer = function() return localPlayer end
    SC.Registry.living = function() return { actor } end
    SC.Vehicle.loadedBySqlId = function(id) return loaded and id == 611 and car or nil end
    local function assign()
        actor.data.SC_FollowCarSqlId = 611
        SC.Commands.reset(actor)
        Convoy.reset()
        Convoy.activate(actor)
    end
    assign()
    check(SC.Commands.peek(actor).followCarSqlId == 611,
        "the companion's command state names its follow car")
    check(Convoy.step(actor, localPlayer, {}) == true and Driving.isDriving(actor),
        "the assigned driver takes the wheel behind the player's car")
    local follow = SCBridge.driveFollowVehicle
    SCBridge.driveFollowVehicle = function() return false end
    local started = SC_TEST_CLOCK + 20000
    Convoy.tick(started)
    SCBridge.driveFollowVehicle = follow
    for pulse = 1, 8 do Convoy.tick(started + pulse * 250) end
    check(halos == 1, "a failed follow car is reported once, not on every convoy tick")
    check(not Driving.isDriving(actor)
        and SC.Commands.peek(actor).followCarSqlId == nil
        and actor.data.SC_FollowCarSqlId == nil,
        "a failed follow car releases the wheel and the saved assignment")
    check(Convoy.step(actor, localPlayer, {}) == nil,
        "the released companion is no longer held by the convoy")

    -- A blocked follower must eventually release its car even when the lead
    -- stops far ahead; leader motion is not evidence of follower progress.
    assign()
    lead.x, lead.y = 110, 100
    check(Convoy.step(actor, localPlayer, {}) == true,
        "reassigned follower resumes the same car")
    local savedFollow = Driving.followVehicle
    Driving.followVehicle = function() return true end
    local stalledAt = SC_TEST_CLOCK + 1000
    Convoy.tick(stalledAt)
    lead.x = 140
    Convoy.tick(stalledAt + 1000)
    Convoy.tick(stalledAt + 12000)
    check(SC.Commands.peek(actor).followCarSqlId == nil
        and not Driving.isDriving(actor),
        "stationary distant leader no longer masks a stalled follow car: assignment="
            .. tostring(SC.Commands.peek(actor).followCarSqlId)
            .. " driving=" .. tostring(Driving.isDriving(actor))
            .. " car=" .. tostring(car.x) .. " lead=" .. tostring(lead.x))
    Driving.followVehicle = savedFollow

    -- The car is outside the loaded area while the player drives another one.
    assign()
    actor.vehicle, loaded = nil, false
    local handled, reason = Convoy.step(actor, localPlayer, {})
    check(handled == nil and reason == "follow_car_unloaded"
        and SC.Commands.peek(actor).followCarSqlId == 611,
        "an unreachable follow car does not freeze the companion in place")
    local savedClock = SC_TEST_CLOCK
    SC_TEST_CLOCK = SC_TEST_CLOCK + 5000
    Convoy.step(actor, localPlayer, {})
    SC_TEST_CLOCK = savedClock
    check(SC.Commands.peek(actor).followCarSqlId == nil,
        "an out-of-reach follow car is released while the player drives off")

    -- The player drives the follow car; the companion should ride with them.
    assign()
    loaded, car.driver, localPlayer.vehicle = true, localPlayer, car
    local before = halos
    handled, reason = Convoy.step(actor, localPlayer, {})
    check(handled == nil and SC.Commands.peek(actor).followCarSqlId == nil
        and halos == before,
        "a player taking the follow car quietly hands it over")
    Convoy.reset()
    getPlayer, SC.Registry.living, SC.Vehicle.loadedBySqlId = oldPlayer, oldLiving, oldLoaded
end
SC_TEST_REPORT = "DRIVING_HARNESS_PASS checks=" .. tostring(checks)
print(SC_TEST_REPORT)
