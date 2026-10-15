-- SPDX-License-Identifier: MIT
-- Companion driving at bounded speed. The native bridge presses the car's own
-- pedals and wheel every frame (SCCompanionDriver) and stops for anything its
-- lane scan finds ahead. SCVehicle owns getting in and out of the seat.
-- SCDriving owns a supervisor lease while the runtime polls bounded route jobs.
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.Driving = SC.Driving or {}
local Driving = SC.Driving
local jobs = {}
local outcomes = setmetatable({}, { __mode = "k" })
local nativeStop

local function finite(value)
    value = tonumber(value)
    if value == nil or value ~= value or value == math.huge or value == -math.huge then return nil end
    return value
end

local function nowMs()
    return SC.GameplayUtil and SC.GameplayUtil.nowMs and SC.GameplayUtil.nowMs()
        or (type(getTimestampMs) == "function" and getTimestampMs() or 0)
end

local function bridge()
    local api = type(_G) == "table" and rawget(_G, "SCBridge") or nil
    if api == nil or SC.Call == nil then return nil end
    return api
end

local function lastFailure(api, fallback)
    local ok, reason = SC.Call.static(api, "getLastFailure")
    if ok and type(reason) == "string" and reason ~= "" then return reason end
    return tostring(fallback or "native driving call failed")
end

local function call(name, ...)
    local api = bridge()
    if api == nil then return false, "driving bridge is unavailable" end
    local ok, accepted = SC.Call.static(api, name, ...)
    if not ok then return false, tostring(accepted) end
    if accepted ~= true then return false, lastFailure(api) end
    return true
end

local function method(object, name, ...)
    if object == nil then return false, nil end
    return SC.Call.method(object, name, ...)
end

local function vehicleOf(actor)
    local ok, vehicle = method(actor, "getVehicle")
    return ok and vehicle or nil
end

local function motionAllowed(actor)
    local job = jobs[actor]
    if job and job.managed == true then
        return false, job.parked == true and "drive_requires_release" or "drive_job_active"
    end
    return true
end

function Driving.available()
    local api = bridge()
    if api == nil then return false end
    for _, name in ipairs({ "driveStart", "driveSet", "driveStop", "driveStatus", "scanLane",
        "driveFollow", "driveFollowTuned", "driveFollowVehicle", "driveApproach", "driveTurnAround" }) do
        local ok, callback = pcall(function() return api[name] end)
        if not ok or callback == nil then return false end
    end
    return true
end

function Driving.passengerAvailable()
    if not Driving.available() then return false end
    local api = bridge()
    local exposed, callback = pcall(function()
        return api and api.driveStartWithPassenger
    end)
    return exposed and callback ~= nil
end

-- True when the companion sits in seat zero of its car.
function Driving.isDriver(actor)
    local vehicle = vehicleOf(actor)
    if vehicle == nil then return false end
    local ok, driver = method(vehicle, "getDriver")
    return ok and driver == actor
end

-- The companion carries this car's key. Without one the car starts only when
-- it is hot-wired, has keys in the ignition, or the sandbox allows easy use.
function Driving.hasKey(actor, vehicle)
    vehicle = vehicle or vehicleOf(actor)
    local keyOk, keyId = method(vehicle, "getKeyId")
    local inventoryOk, inventory = method(actor, "getInventory")
    if not keyOk or not inventoryOk or inventory == nil or type(keyId) ~= "number" then
        return false
    end
    local found, item = method(inventory, "haveThisKeyId", keyId)
    return found and item ~= nil
end

-- Gets into the driver's seat through SCVehicle's verified boarding.
function Driving.takeWheel(actor, vehicle, intent)
    if SC.Vehicle == nil or type(SC.Vehicle.boardDriver) ~= "function" then
        return false, "vehicle boarding is unavailable"
    end
    return SC.Vehicle.boardDriver(actor, vehicle, intent)
end

local function startNative(job)
    local accepted, reason
    if job.passenger then
        accepted, reason = call("driveStartWithPassenger", job.actor,
            job.passenger, Driving.hasKey(job.actor) == true)
    else
        accepted, reason = call("driveStart", job.actor,
            Driving.hasKey(job.actor) == true)
    end
    if not accepted then Driving.stop(job.actor, "bridge_failure") return false, reason end
    job.nativeStarted = true
    return true
end

-- Puts the seated driver under bridge control, held still.
function Driving.start(actor, passenger)
    local allowed, why = motionAllowed(actor)
    if not allowed then return false, why end
    if not Driving.isDriver(actor) then return false, "companion is not in the driver's seat" end
    local token, why = Driving.begin(actor, nil, passenger)
    if not token then return false, why end
    return startNative(jobs[actor])
end

-- Cruise at a bounded speed (km/h, capped natively) with steering in [-1, 1],
-- where -1 is the player's left key. Obstacle braking stays on unless the
-- caller passes false.
function Driving.cruise(actor, kmh, steering, brakeForObstacles)
    local allowed, why = motionAllowed(actor)
    if not allowed then return false, why end
    local speed = tonumber(kmh) or 0
    local steer = tonumber(steering) or 0
    return call("driveSet", actor, steer, speed, brakeForObstacles ~= false)
end

function Driving.hold(actor)
    local allowed, why = motionAllowed(actor)
    if not allowed then return false, why end
    return call("driveSet", actor, 0, 0, true)
end

-- Lets go of the wheel and parks. Safe when not driving.
function Driving.release(actor, reason)
    if not jobs[actor] then return nativeStop(actor) end
    return Driving.stop(actor, reason or "released")
end

-- The expedition road planner's route from where the car stands to a target.
function Driving.planRoute(actor, target)
    if SC.ExpeditionRoute == nil or type(SC.ExpeditionRoute.plan) ~= "function" then
        return nil, "road planner is unavailable"
    end
    return SC.ExpeditionRoute.plan(actor, target, true)
end

-- The bridge's route text, "x,y,width;...", from route points. Bounded.
function Driving.routeText(points)
    if type(points) ~= "table" then return nil, "route has no points" end
    local parts = {}
    for index, point in ipairs(points) do
        if index > 512 then return nil, "route has too many points" end
        local x = type(point) == "table" and tonumber(point.x) or nil
        local y = type(point) == "table" and tonumber(point.y) or nil
        if not x or not y then return nil, "route point " .. index .. " is invalid" end
        parts[#parts + 1] = string.format("%.2f,%.2f,%.1f", x, y, tonumber(point.width) or 0)
    end
    if #parts < 2 then return nil, "route has fewer than two points" end
    return table.concat(parts, ";")
end

local function followNative(actor, route, kmh, cornerSpeedScale)
    local points = type(route) == "table" and (route.points or route) or nil
    local text, why = Driving.routeText(points)
    if not text then return false, why end
    local followed, reason
    if cornerSpeedScale and cornerSpeedScale > 1 then
        followed, reason = call("driveFollowTuned", actor, text,
            tonumber(kmh) or 10, cornerSpeedScale)
    else
        followed, reason = call("driveFollow", actor, text, tonumber(kmh) or 10)
    end
    if followed and jobs[actor] then jobs[actor].phase, jobs[actor].result = "following", nil end
    return followed, reason
end

-- Drives a route: the planner's table, or a plain list of {x, y, width}
-- points. The bridge keeps right, slides round wrecks in the lane, stops when
-- the road is blocked edge to edge, and stops at the end.
function Driving.followRoute(actor, route, kmh)
    local allowed, reason = motionAllowed(actor)
    if not allowed then return false, reason end
    return followNative(actor, route, kmh)
end

-- A live leader car supplies a rolling trail; the bridge retargets its current
-- follower instead of constructing a fresh steering controller each pulse.
function Driving.followVehicle(actor, leaderVehicle, route, kmh)
    local allowed, reason = motionAllowed(actor)
    if not allowed then return false, reason end
    if not Driving.isDriving(actor) then return false, "driver_not_owned" end
    local points = type(route) == "table" and (route.points or route) or nil
    local encoded, why = Driving.routeText(points)
    if not encoded then return false, why end
    return call("driveFollowVehicle", actor, leaderVehicle, encoded,
        math.min(50, math.max(1, tonumber(kmh) or 30)))
end

-- Turns round with a three-point turn; with followBack, drives the route back.
function Driving.turnAround(actor, followBack)
    local allowed, why = motionAllowed(actor)
    if not allowed then return false, why end
    local turned, reason = call("driveTurnAround", actor, followBack == true)
    if turned and jobs[actor] then jobs[actor].phase, jobs[actor].result = "turning", nil end
    return turned, reason
end

function Driving.status(actor)
    local api = bridge()
    if api == nil then return nil, "driving bridge is unavailable" end
    local out = {}
    local ok, accepted = SC.Call.static(api, "driveStatus", actor, out)
    if not ok then return nil, tostring(accepted) end
    if accepted ~= true then return nil, lastFailure(api) end
    return out
end

-- One lane scan for the car the companion sits in, lookAhead tiles past the
-- front bumper. Read-only.
function Driving.scanLane(actor, lookAhead)
    local api = bridge()
    if api == nil then return nil, "driving bridge is unavailable" end
    local out = {}
    local ok, accepted = SC.Call.static(api, "scanLane", actor, tonumber(lookAhead) or 0, out)
    if not ok then return nil, tostring(accepted) end
    if accepted ~= true then return nil, lastFailure(api) end
    return out
end

-- Job results and the seat lease are separate: an arrived/failed car is parked
-- with no pedal held, while its driver remains protected until explicitly released.
local function snapshot(job)
    local circles = {}
    for _, circle in ipairs(job.circles or {}) do
        circles[#circles + 1] = { x = circle.x, y = circle.y, radius = circle.radius }
    end
    local roadGoal = job.roadGoal
    return { phase = job.phase, result = job.result, reason = job.reason,
        attempts = job.attempts or 0, circles = circles, parked = job.parked == true,
        roadGoal = roadGoal and { x = roadGoal.x, y = roadGoal.y, z = roadGoal.z } or nil }
end

nativeStop = function(actor, job)
    local api = job and job.api or bridge()
    if not api or not SC.Call then return false, "driving bridge is unavailable" end
    local okay, accepted = SC.Call.static(api, "driveStop", actor)
    if okay and accepted == true then return true end
    if job and job.nativeStarted ~= true then return true, "drive_not_started" end
    return false, okay and lastFailure(api, "drive release rejected") or tostring(accepted)
end

local function forget(actor, job, reason)
    job.phase, job.reason = "released", reason
    job.result = job.result or "interrupted"
    outcomes[actor] = snapshot(job)
    jobs[actor] = nil
end

local function playerAboard(vehicle)
    if SC.Vehicle and type(SC.Vehicle.hasPlayerAboard) == "function" then
        return SC.Vehicle.hasPlayerAboard(vehicle)
    end
    local okay, seats = method(vehicle, "getMaxPassengers")
    if not okay or not finite(seats) then return true end
    for seat = 0, math.min(32, seats) - 1 do
        local called, occupant = method(vehicle, "getCharacter", seat)
        if not called then return true end
        if occupant and (not SC.Actor or not SC.Actor.isCompanion
            or SC.Actor.isCompanion(occupant) ~= true) then return true end
    end
    return false
end

local function bookedPassengerAboard(vehicle, passenger)
    if vehicle == nil or passenger == nil then return false end
    local okay, seats = method(vehicle, "getMaxPassengers")
    seats = okay and finite(seats) or nil
    if not seats or seats < 2 or seats > 32 then return false end
    local present = false
    for seat = 0, seats - 1 do
        local read, occupant = method(vehicle, "getCharacter", seat)
        if not read then return false end
        if occupant == passenger then
            if seat == 0 then return false end
            present = true
        elseif occupant ~= nil and (not SC.Actor
            or type(SC.Actor.isCompanion) ~= "function"
            or SC.Actor.isCompanion(occupant) ~= true) then
            return false
        end
    end
    local read, current = method(passenger, "getVehicle")
    return present and read and current == vehicle
end

function Driving.begin(actor, goal, passenger)
    if not Driving.isDriver(actor) then return nil, "not_driver" end
    local vehicle = vehicleOf(actor)
    if passenger then
        if not bookedPassengerAboard(vehicle, passenger) then
            return nil, "booked_passenger_not_seated"
        end
        local api = bridge()
        local exposed, callback = pcall(function()
            return api and api.driveStartWithPassenger
        end)
        if not exposed or callback == nil then
            return nil, "passenger_driving_bridge_unavailable"
        end
    elseif playerAboard(vehicle) then return nil, "player_aboard" end
    local initialStatus, statusReason = Driving.status(actor)
    if not initialStatus then return nil, statusReason or "driving_bridge_unavailable" end
    local x = type(goal) == "table" and finite(goal.x) or nil
    local y = type(goal) == "table" and finite(goal.y) or nil
    if goal ~= nil and (not x or not y
        or x < 0 or x > 30000 or y < 0 or y > 30000 or goal.z ~= 0) then
        return nil, "invalid_drive_goal"
    end
    local prior = jobs[actor]
    if prior then return prior.token, "already_owned" end
    local supervisor = SC.ActionSupervisor
    if not supervisor or type(supervisor.begin) ~= "function" then
        return nil, "driving_supervisor_unavailable"
    end
    local job = { actor = actor, vehicle = vehicle, api = bridge(),
        passenger = passenger,
        nativeStatus = initialStatus, nativeStarted = initialStatus.active == true,
        goal = goal and { x = x, y = y, z = 0 } or nil,
        phase = "waiting", attempts = 0, circles = {} }
    local token, why = supervisor.begin(actor, {
        owner = "drive", action = "drive_route", priority = supervisor.Priority.TRAVEL,
        targetKey = goal and (tostring(goal.x) .. ":" .. tostring(goal.y) .. ":0") or "manual",
        deadlines = { selected = 0, waiting = 0 },
        onCancel = function(_, reason)
            local called, stopped, stopReason = pcall(nativeStop, actor, job)
            if not called or not stopped then
                job.phase, job.reason = "stopping", called and stopReason or stopped
                return false, job.reason
            end
            forget(actor, job, reason or "cancelled")
            return true
        end,
    })
    if not token then
        if supervisor.containsDeferredStatus and supervisor.containsDeferredStatus(why) then
            -- Urgent work took this pulse. Keep its status available to callers
            -- so they can retry without starting a native drive or recording a refusal.
            return nil, "deferred:" .. tostring(why)
        end
        return nil, why
    end
    job.token = token
    jobs[actor], outcomes[actor] = job, nil
    local waiting, transitionReason = supervisor.transition(token, "waiting")
    if not waiting then Driving.stop(actor, "drive_begin_failed") return nil, transitionReason end
    return token, "drive_owned"
end

function Driving.stop(actor, reason)
    local job = jobs[actor]
    if not job then return true, "no_drive" end
    job.releaseReason = reason or "released"
    local supervisor = SC.ActionSupervisor
    if supervisor and supervisor.isCurrent(job.token) then
        return supervisor.cancel(actor, reason or "released", nil, false)
    end
    local stopped, why = nativeStop(actor, job)
    if stopped then forget(actor, job, reason or "released") end
    return stopped, why
end

-- Kahlua keeps weak table keys. Retirement explicitly removes the outcome
-- only after native cleanup succeeds, retaining retry authority on failure.
function Driving.releaseActor(actor, reason)
    if actor == nil then return false, "actor_missing" end
    local stopped, why = Driving.stop(actor, reason or "actor_released")
    if stopped ~= true then return false, why end
    outcomes[actor] = nil
    return true, why
end

-- The gate also services native release events, so Decision cannot retain a stale
-- owner after a player boards or the bridge releases its companion driver.
function Driving.isDriving(actor)
    local job = jobs[actor]
    if not job then return false end
    local supervisor = SC.ActionSupervisor
    local dead = SC.GameplayUtil and SC.GameplayUtil.isDead
        and SC.GameplayUtil.isDead(actor) == true
    local reason = dead and "driver_dead"
        or not Driving.isDriver(actor) and "left_driver_seat"
        or job.passenger and not bookedPassengerAboard(job.vehicle, job.passenger)
            and "booked_passenger_left"
        or not job.passenger and playerAboard(job.vehicle) and "player_aboard"
        or (not supervisor or not supervisor.isCurrent(job.token)) and "drive_owner_lost"
    if reason then
        local stopped = Driving.stop(actor, reason)
        return stopped ~= true and jobs[actor] == job
            and supervisor and supervisor.isCurrent(job.token) or false
    end
    local status, why = Driving.status(actor)
    if not status then
        local stopped = Driving.stop(actor, "bridge_failure")
        return stopped ~= true and jobs[actor] == job and supervisor.isCurrent(job.token)
    end
    if job.nativeStarted and status.active ~= true and not job.parked then
        local stopped = Driving.stop(actor, status.reason ~= "" and status.reason or "native_released")
        return stopped ~= true and jobs[actor] == job and supervisor.isCurrent(job.token)
    end
    job.nativeStatus = status
    return true
end

local function parkResult(job, result, reason)
    local stopped, why = nativeStop(job.actor, job)
    if not stopped then
        job.phase, job.reason = "stopping", why
        job.pendingResult, job.pendingReason = result, reason
        return false
    end
    job.phase, job.result, job.reason = result, result, reason or result
    job.parked = true
    job.pendingResult, job.pendingReason = nil, nil
    return true
end

local function reachedGoal(job)
    local xOk, x = method(job.vehicle, "getX")
    local yOk, y = method(job.vehicle, "getY")
    local zOk, z = method(job.vehicle, "getZ")
    x, y, z = finite(x), finite(y), finite(z)
    if not xOk or not yOk or not zOk or not x or not y or not z
        or x < 0 or x > 30000 or y < 0 or y > 30000 then
        return false, "goal_position_unavailable"
    end
    -- The road leg ends at the router's physical road attachment. A driveway
    -- is a separate, checked parking approach owned by SCExpeditionCar.
    local tolerance = job.precise and 1 or 36
    local goal = job.precise and job.goal or job.roadGoal
    if not goal then return false, "road_goal_unavailable" end
    return math.floor(z) == job.goal.z
        and (x - goal.x)^2 + (y - goal.y)^2 <= tolerance,
        "goal_not_reached"
end

-- The original managed lease remains owned while its arrived car is parked.
-- Start a fresh native driver under that lease for one short, clear parking
-- segment. The mission owner checks the entire footprint after arrival.
function Driving.approach(actor, target, seconds)
    local job = jobs[actor]
    if not job or job.managed ~= true or job.parked ~= true
        or job.result ~= "arrived" or not SC.ActionSupervisor
        or not SC.ActionSupervisor.isCurrent(job.token) then
        return false, "parking_requires_arrived_drive"
    end
    local vehicle = vehicleOf(actor)
    local xOk, x = method(vehicle, "getX")
    local yOk, y = method(vehicle, "getY")
    local zOk, z = method(vehicle, "getZ")
    x, y, z = finite(x), finite(y), finite(z)
    local tx = type(target) == "table" and finite(target.x) or nil
    local ty = type(target) == "table" and finite(target.y) or nil
    if not xOk or not yOk or not zOk or not x or not y or z ~= 0
        or not tx or not ty or target.z ~= 0
        or (x - tx)^2 + (y - ty)^2 > 225 then
        return false, "parking_approach_out_of_range"
    end
    local routeText = string.format("%.3f,%.3f,5;%.3f,%.3f,5",
        x, y, tx, ty)
    local started, reason = startNative(job)
    if not started then return false, reason end
    local followed, followReason = call("driveApproach", actor, routeText, 5)
    if not followed then
        Driving.stop(actor, "parking_approach_rejected")
        return false, followReason
    end
    job.goal = { x = tx, y = ty, z = 0 }
    job.precise = true
    job.phase, job.result, job.reason = "approaching", nil, nil
    job.parked = false
    job.approachDeadline = nowMs() + math.min(30000,
        math.max(1000, finite(seconds) or 30000))
    return true
end

local function planJob(job)
    local route, reason
    if not SC.ExpeditionRoute or not SC.ExpeditionRoute.planAvoidingAll then
        return parkResult(job, "failed", "no_route")
    end
    route, reason = SC.ExpeditionRoute.planAvoidingAll(job.actor, job.goal, job.circles)
    if not route then
        job.detail = reason
        return parkResult(job, "failed", "no_route")
    end
    if job.stopShortTiles > 0 and type(route.points) == "table" then
        local last = route.points[#route.points]
        local before = route.points[#route.points - 1]
        if last and before then
            local dx, dy = last.x - before.x, last.y - before.y
            local length = math.sqrt(dx * dx + dy * dy)
            -- Keep the original planner path and its junction choices. Only
            -- shorten a sufficiently long last straight so the car turns
            -- away from roadside poles after the squad walks to the site.
            if length >= job.stopShortTiles + 2 then
                last.x = last.x - dx / length * job.stopShortTiles
                last.y = last.y - dy / length * job.stopShortTiles
                route.roadLength = math.max(0,
                    (tonumber(route.roadLength) or 0) - job.stopShortTiles)
            end
        end
    end
    local endpoint = route.points and route.points[#route.points]
    local roadX = type(endpoint) == "table" and finite(endpoint.x)
    local roadY = type(endpoint) == "table" and finite(endpoint.y)
    if not roadX or not roadY then
        return parkResult(job, "failed", "road_goal_unavailable")
    end
    local followed, followReason = followNative(job.actor, route,
        job.speedKmh, job.cornerSpeedScale)
    if not followed then
        job.result, job.reason, job.detail = "failed", "bridge_failure", followReason
        Driving.stop(job.actor, "bridge_failure")
        return false
    end
    job.roadGoal = { x = roadX, y = roadY, z = job.goal.z }
    job.route, job.phase, job.blockedSince = route, "following", nil
    job.lastProgressAt, job.lastProgressX, job.lastProgressY = nil, nil, nil
    return true
end

function Driving.drive(actor, goal, options)
    options = type(options) == "table" and options or {}
    local prior = jobs[actor]
    if prior and (prior.managed or prior.nativeStarted or prior.parked or prior.releaseReason
        or prior.phase ~= "waiting" or not SC.ActionSupervisor.isCurrent(prior.token)) then
        return false, "drive_already_owned"
    end
    if prior and (type(goal) ~= "table" or not finite(goal.x) or not finite(goal.y)
        or goal.z ~= 0 or not prior.goal or prior.goal.x ~= finite(goal.x)
        or prior.goal.y ~= finite(goal.y)) then return false, "drive_goal_changed" end
    local token, why = Driving.begin(actor, goal, options.passenger)
    if not token then return false, why end
    if not goal then Driving.stop(actor, "invalid_drive_goal") return false, "invalid_drive_goal" end
    local job = jobs[actor]
    job.managed, job.phase = true, "planning"
    -- The booked player's cab ride can use the native 50 km/h ceiling;
    -- ordinary companion and expedition drives keep their 30 km/h limit.
    local ceiling = job.passenger and 50 or 30
    job.speedKmh = math.max(0, math.min(ceiling,
        finite(options.speedKmh) or 10))
    job.cornerSpeedScale = math.max(1, math.min(2,
        finite(options.cornerSpeedScale) or 1))
    job.stopShortTiles = math.max(0,
        math.min(10, finite(options.stopShortTiles) or 0))
    job.blockWaitMs = math.max(1000, math.min(30000, finite(options.blockWaitMs) or 5000))
    if options.circles ~= nil then
        if type(options.circles) ~= "table" or #options.circles > 8 then
            Driving.stop(actor, "invalid_road_avoidance") return false, "invalid_road_avoidance"
        end
        for key in pairs(options.circles) do
            if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > #options.circles then
                Driving.stop(actor, "invalid_road_avoidance") return false, "invalid_road_avoidance"
            end
        end
        for _, circle in ipairs(options.circles) do
            local x = type(circle) == "table" and finite(circle.x) or nil
            local y = type(circle) == "table" and finite(circle.y) or nil
            local radius = type(circle) == "table" and finite(circle.radius) or nil
            if not x or not y or not radius or x < 0 or x > 30000 or y < 0 or y > 30000
                or radius < 4 or radius > 32 then
                Driving.stop(actor, "invalid_road_avoidance") return false, "invalid_road_avoidance"
            end
            job.circles[#job.circles + 1] = { x = x, y = y, radius = radius }
        end
    end
    local started, startReason = startNative(job)
    if not started then return false, startReason end
    planJob(job)
    return true, job.reason or "driving"
end

function Driving.jobStatus(actor)
    local job = jobs[actor]
    return job and snapshot(job) or outcomes[actor]
end

function Driving.tick(current)
    current = finite(current) or nowMs()
    local active = {}
    for actor in pairs(jobs) do active[#active + 1] = actor end
    for _, actor in ipairs(active) do
        local job = jobs[actor]
        if job and Driving.isDriving(actor) then
            if job.releaseReason then
                Driving.stop(actor, job.releaseReason)
            elseif job.pendingResult then
                parkResult(job, job.pendingResult, job.pendingReason)
            elseif not job.parked then
                local status = job.nativeStatus
                -- The actual bumper scan can brake a car while the route
                -- follower still sees a clear lane and reports FOLLOW.
                local state = status.state == "safety_blocked"
                    and "blocked" or status.mode or status.state
                if job.managed and not job.precise and (state == "follow"
                    or state == "avoiding") and status.engineRunning == true
                    and (finite(status.cruiseKmh) or 0) > 0 then
                    local xOk, x = method(job.vehicle, "getX")
                    local yOk, y = method(job.vehicle, "getY")
                    x, y = xOk and finite(x), yOk and finite(y)
                    if x and y then
                        if not job.lastProgressAt or not job.lastProgressX
                            or (x - job.lastProgressX)^2
                                + (y - job.lastProgressY)^2 >= 0.25 then
                            job.lastProgressAt = current
                            job.lastProgressX, job.lastProgressY = x, y
                        elseif current - job.lastProgressAt >= 12000
                            and math.abs(finite(status.speedKmh) or 0) < 1 then
                            state = "blocked"
                            status.blockedX, status.blockedY = x, y
                        end
                    end
                else
                    job.lastProgressAt = nil
                end
                if job.managed and status.state == "engine_failed" then
                    parkResult(job, "failed", "engine_failed")
                elseif state == "arrived" then
                    if job.managed then
                        local reached, reason = reachedGoal(job)
                        parkResult(job, reached and "arrived" or "failed", reached and "arrived" or reason)
                    else job.phase, job.result = "arrived", "arrived" end
                elseif state == "turn_failed" or status.turnState == "failed" then
                    parkResult(job, "failed", "turn_failed")
                elseif job.precise and job.approachDeadline
                    and current >= job.approachDeadline then
                    parkResult(job, "failed", "parking_approach_timeout")
                elseif job.precise and state == "blocked" then
                    parkResult(job, "failed", status.obstacleKind == "unloaded"
                        and "parking_streaming_stalled" or "parking_approach_blocked")
                elseif job.managed and state == "blocked" then
                    if status.obstacleKind == "unloaded" then
                        job.phase = "streaming_wait"
                        job.streamingSince = job.streamingSince or current
                        job.blockedSince = nil
                        if current - job.streamingSince >= 30000 then
                            parkResult(job, "failed", "streaming_stalled")
                        end
                    else
                    job.streamingSince = nil
                    job.phase = "blocked"
                    job.blockedSince = job.blockedSince or current
                    if current - job.blockedSince >= job.blockWaitMs then
                        local x, y = finite(status.blockedX), finite(status.blockedY)
                        if not x or not y or x < 0 or x > 30000 or y < 0 or y > 30000 then
                            parkResult(job, "failed", "invalid_blocked_position")
                        elseif job.attempts >= 3 or #job.circles >= 8 then
                            parkResult(job, "failed", "route_blocked")
                        else
                            job.circles[#job.circles + 1] = { x = x, y = y, radius = 12 }
                            job.attempts, job.phase = job.attempts + 1, "replanning"
                            planJob(job)
                        end
                    end
                    end
                elseif job.managed then
                    job.phase, job.blockedSince = "following", nil
                    job.streamingSince = nil
                end
            end
        end
    end
    return true
end

function Driving.reset()
    local active, failures = {}, {}
    for actor in pairs(jobs) do active[#active + 1] = actor end
    for _, actor in ipairs(active) do
        local stopped, why = Driving.stop(actor, "interrupted_by_load")
        if not stopped then failures[#failures + 1] = tostring(why) end
    end
    if #failures > 0 then return false, table.concat(failures, "; ") end
    outcomes = setmetatable({}, { __mode = "k" })
    return true
end

return Driving
