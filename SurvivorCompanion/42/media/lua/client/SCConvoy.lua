-- SPDX-License-Identifier: MIT
-- One player-led follow car. The game owns the vehicle physics and seats;
-- this module only assigns them and supplies a bounded rolling trail.
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.Convoy = SC.Convoy or {}
local Convoy = SC.Convoy
local sessions = setmetatable({}, { __mode = "k" })

local function U() return SC.GameplayUtil end
local function now() return U().nowMs() end
local function value(object, name, ...)
    local result, okay = U().call(object, name, ...)
    return okay and result or nil
end
local function sql(vehicle)
    local id = tonumber(value(vehicle, "getSqlId"))
    return id and id >= 0 and id == math.floor(id) and id or nil
end
local function distance(a, b)
    local ax, ay, az = U().position(a)
    local bx, by, bz = U().position(b)
    if not ax or not bx or math.floor(az or 0) ~= math.floor(bz or 0) then
        return math.huge
    end
    return math.sqrt((ax - bx)^2 + (ay - by)^2)
end
local function state(actor)
    return SC.Commands and SC.Commands.peek and SC.Commands.peek(actor) or nil
end
local function selected(actor)
    local command = state(actor)
    return command and command.recruited == true and command.order == "follow"
        and tonumber(command.followCarSqlId) or nil
end
local function playerCar(player)
    local car = value(player, "getVehicle")
    return car and value(car, "getDriver") == player and car or nil
end
local function notify(player, actor, reason)
    if SC.Diagnostics and SC.Diagnostics.report then
        SC.Diagnostics.report("convoy", SC.Registry.idOf(actor), reason, reason)
    end
    if player then
        local sentence = SC.UI and type(SC.UI.baseFailureReason) == "function"
            and SC.UI.baseFailureReason(reason) or tostring(reason)
        local note = SC.UI and type(SC.UI.text) == "function"
            and SC.UI.text("UI_SC_Vehicle_FollowCarEnded", sentence)
            or ("Follow car stopped: " .. sentence)
        U().call(player, "setHaloNote", note)
    end
end
local function runtime(actor)
    local session = sessions[actor]
    if not session then
        session = { trail = {}, progress = 1, lastUpdate = 0, lastMove = now() }
        sessions[actor] = session
    end
    return session
end

function Convoy.preflight(actor, car, player)
    if not actor or not car or not player then return nil, "actor_or_car_missing" end
    local order = state(actor)
    if not order or order.recruited ~= true then return nil, "not_recruited" end
    if not SC.Driving or not SC.Driving.available() then
        return nil, "driving_bridge_unavailable"
    end
    if distance(actor, car) > 35 or distance(player, car) > 30 then
        return nil, "car_too_far"
    end
    if value(player, "getVehicle") == car then return nil, "player_in_car" end
    local id = sql(car)
    if not id then return nil, "car_identity_unavailable" end
    if SC.Vehicle.hasPlayerAboard(car) then return nil, "car_has_player" end
    if SC.Vehicle.isStationary(car) ~= true then return nil, "car_is_moving" end
    if value(car, "getDriver") ~= nil then return nil, "driver_seat_occupied" end
    if value(car, "isDriveable") == false then return nil, "car_not_driveable" end
    local tank = value(car, "getPartById", "GasTank")
    local fuel = tonumber(value(tank, "getContainerContentAmount"))
    if fuel ~= nil and fuel <= 0 then return nil, "car_has_no_fuel" end
    if not SC.Driving.hasKey(actor, car)
        and value(car, "isHotwired") ~= true
        and value(car, "isKeysInIgnition") ~= true then
        return nil, "car_needs_key_or_hotwire"
    end
    for _, other in ipairs(SC.Registry.living()) do
        if other ~= actor and selected(other) then
            return nil, "one_follow_car_at_a_time"
        end
    end
    return id
end

function Convoy.activate(actor)
    local session = runtime(actor)
    session.requested, session.failed, session.parked = true, nil, nil
    session.trail, session.progress = {}, 1
    session.lead, session.lastUpdate, session.lastMove = nil, 0, now()
    session.lastX, session.lastY = nil, nil
    session.leadLastX, session.leadLastY, session.leadLastMove = nil, nil, nil
end

function Convoy.release(actor, reason)
    local session = sessions[actor]
    if SC.Driving and SC.Driving.isDriving(actor) then
        local stopped, why = SC.Driving.release(actor, reason or "convoy_released")
        if stopped ~= true then return false, why end
    end
    if session then session.parked, session.requested = true, false end
    return true
end

-- Give the assignment up once the follow car cannot work: a failed drive, a
-- car beyond the loaded area, or the player taking it. Kept, it parked the
-- companion in that car and barred it from the player's own seats.
local function abandon(actor, player, session, reason, quiet)
    if SC.Driving and SC.Driving.isDriving(actor) then
        local stopped = SC.Driving.release(actor, reason or "convoy_abandoned")
        if stopped ~= true then return false end
    end
    if session then
        session.parked, session.requested = true, false
        if not quiet and not session.notified then
            session.notified = true
            notify(player, actor, reason)
        end
    end
    return SC.Commands and type(SC.Commands.releaseFollowCar) == "function"
        and SC.Commands.releaseFollowCar(actor, reason) == true or false
end

function Convoy.suspendForSurvival(actor, suspended)
    if selected(actor) == nil then return false end
    local session = suspended and runtime(actor) or sessions[actor]
    if session then session.survivalSuspended = suspended == true or nil end
    return true
end

function Convoy.isSurvivalSuspended(actor)
    local session = sessions[actor]
    return session ~= nil and session.survivalSuspended == true
end

function Convoy.ownsSeat(actor, car, player)
    local assigned = selected(actor)
    if assigned ~= nil and sql(car) == assigned then
        local session = sessions[actor]
        return (session ~= nil or playerCar(player) ~= nil)
            and not (session and (session.failed or session.parked
                or session.survivalSuspended))
    end
    local order = state(actor)
    if not order or order.recruited ~= true or order.order ~= "follow"
        or order.rideWithPlayer == false then return false end
    if playerCar(player) == nil then return false end
    for _, other in ipairs(SC.Registry.living()) do
        if selected(other) == sql(car) and value(car, "getDriver") == other then
            return true
        end
    end
    return false
end

local function board(actor, car, seat, snapshot)
    local seated, current, actual = SC.Vehicle.isNativeSeated(actor)
    if seated then return current == car and actual == seat, "already_seated" end
    local transaction, reason = SC.Vehicle.beginBoarding(actor, car, seat,
        { driverSeat = seat == 0, followPlayer = true })
    if not transaction then return false, reason end
    local prepared, why = SC.Vehicle.preflightBoard(actor, car, seat, seat == 0)
    if prepared then
        U().stop(actor)
        local intent = { driverSeat = seat == 0, preflight = prepared,
            allowVirtualSeat = false, followPlayer = true,
            supervisorToken = transaction.supervisorToken }
        if seat == 0 then return SC.Vehicle.boardDriver(actor, car, intent) end
        return SC.Vehicle.board(actor, car, seat, intent)
    end
    if why ~= "companion is not at the passenger door" then
        SC.Vehicle.failTransaction(actor, "convoy_board_failed", { reason = why })
        return false, why
    end
    local squares, _, squareReason = SC.Vehicle.boardingSquares(actor, car, seat, seat == 0)
    if not squares then
        SC.Vehicle.failTransaction(actor, "convoy_no_door", { reason = squareReason })
        return false, squareReason
    end
    local accepted, moveReason = SC.Navigation.requestAny(actor, squares, "walk", {
        action = "approach_vehicle", vehicle = car, seat = seat,
        snapshot = snapshot, desiredDistance = 0, arrivalDistance = 0.15,
        continuousApproach = true, movementPriority = 30,
        supervisorToken = transaction.supervisorToken,
    })
    if accepted ~= true then
        SC.Vehicle.failTransaction(actor, "convoy_approach_failed", { reason = moveReason })
    end
    return accepted, moveReason or "approaching_follow_car"
end

function Convoy.step(actor, player, snapshot)
    local id = selected(actor)
    if id == nil then return nil end
    local session = runtime(actor)
    if session.survivalSuspended then return nil, "survival_priority" end
    local lead = playerCar(player)
    if session.failed then
        return value(actor, "getVehicle") ~= nil and true or nil, "follow_car_lost"
    end
    if session.parked and lead == nil then return nil end
    if lead == nil and session.requested ~= true then return nil end
    local car = SC.Vehicle.loadedBySqlId(id)
    if not car then
        -- A car outside the loaded area cannot be boarded. Keep following on
        -- foot, and release it once the player has driven off in another car.
        if lead and value(actor, "getVehicle") == nil then
            session.unreachableSince = session.unreachableSince or now()
            if now() - session.unreachableSince >= 5000 then
                abandon(actor, player, session, "follow_car_out_of_reach")
            end
        else
            session.unreachableSince = nil
        end
        return nil, "follow_car_unloaded"
    end
    session.unreachableSince = nil
    if car == lead then
        -- The player is driving the follow car; the companion rides along.
        abandon(actor, player, session, "player_took_follow_car", true)
        return nil, "follow_car_is_player_car"
    end
    local current = value(actor, "getVehicle")
    if current and current ~= car then
        if SC.Vehicle.isStationary(current) ~= true then
            return true, "waiting_for_safe_exit"
        end
        return U().move(actor, "walk", {
            action = "exit_vehicle", vehicle = current, transactional = true,
            restoreByDoor = true, followPlayer = true,
        })
    end
    if not current then
        if lead and SC.Vehicle.isStationary(car) ~= true then
            return true, "follow_car_moving_before_board"
        end
        local boarded, why = board(actor, car, 0, snapshot)
        return boarded == true, why
    end
    session.parked = nil
    if not lead then return true, "waiting_for_player_car" end
    if not SC.Driving.isDriving(actor) then
        local started, why = SC.Driving.start(actor)
        return started == true, why or "starting_follow_car"
    end
    return true, "following_player_car"
end

function Convoy.boardOverflow(actor, player, snapshot)
    local lead = playerCar(player)
    if not lead then return nil end
    local driver, car
    for _, other in ipairs(SC.Registry.living()) do
        local id = selected(other)
        if id then driver, car = other, SC.Vehicle.loadedBySqlId(id) break end
    end
    if not car or not driver or SC.Vehicle.isStationary(car) ~= true then return nil end
    if value(car, "getDriver") ~= driver then return nil end
    local waiting = {}
    for _, other in ipairs(SC.Registry.living()) do
        local order = state(other)
        if other ~= driver and order and order.recruited and order.order == "follow"
            and order.rideWithPlayer ~= false and not selected(other) then
            local alreadyHere = value(other, "getVehicle") == car
            local assignment, reason
            if not alreadyHere then
                assignment, reason = SC.Vehicle.assignmentFor(other, lead, player)
            end
            if alreadyHere or assignment == nil and reason == "vehicle_capacity_wait" then
                waiting[#waiting + 1] = other
            end
        end
    end
    table.sort(waiting, function(a, b)
        return tostring(SC.Registry.idOf(a)) < tostring(SC.Registry.idOf(b))
    end)
    local waitingById = {}
    for _, other in ipairs(waiting) do
        waitingById[tostring(SC.Registry.idOf(other))] = other
    end
    local assigned, free = {}, {}
    local count = tonumber(value(car, "getMaxPassengers")) or 0
    for candidate = 1, math.min(count, 32) - 1 do
        if value(car, "isSeatInstalled", candidate) == true then
            local reserved, owner = SC.Vehicle.isSeatReserved(car, candidate)
            local occupant = value(car, "getCharacter", candidate)
            if occupant then
                -- A native occupant owns its actual seat, regardless of roster order.
                if waitingById[tostring(SC.Registry.idOf(occupant))] == occupant then
                    assigned[occupant] = candidate
                end
            elseif reserved then
                local reservedActor = waitingById[tostring(owner)]
                if reservedActor and not assigned[reservedActor] then
                    assigned[reservedActor] = candidate
                end
            else
                free[#free + 1] = candidate
            end
        end
    end
    local nextFree = 1
    for _, other in ipairs(waiting) do
        if not assigned[other] and free[nextFree] then
            assigned[other] = free[nextFree]
            nextFree = nextFree + 1
        end
    end
    local seat = assigned[actor]
    if not seat then return nil end
    local boarded, why = board(actor, car, seat, snapshot)
    return boarded == true, why or "boarding_follow_car"
end

local function appendTrail(session, lead)
    local x, y, z = U().position(lead)
    if not x or math.floor(z or -1) ~= 0 then return end
    local trail = session.trail
    local last = trail[#trail]
    if last and (last.x - x)^2 + (last.y - y)^2 < 6.25 then return end
    trail[#trail + 1] = { x = x, y = y, width = 6 }
    if #trail > 96 then
        table.remove(trail, 1)
        session.progress = math.max(1, (session.progress or 1) - 1)
    end
end

local function routeFor(session, car, lead)
    local x, y, z = U().position(car)
    if not x or math.floor(z or -1) ~= 0 then return nil end
    local trail = session.trail
    local first = math.max(1, (session.progress or 1) - 1)
    local best, bestDistance = first, math.huge
    for index = first, math.min(#trail, first + 30) do
        local point = trail[index]
        local d = (x - point.x)^2 + (y - point.y)^2
        if d < bestDistance then best, bestDistance = index, d end
    end
    if bestDistance > 900 then return nil, "trail_out_of_range" end
    session.progress = math.max(session.progress or 1, best)
    local route = { { x = x, y = y, width = 6 } }
    for index = best + 1, #trail do route[#route + 1] = trail[index] end
    local lx, ly = U().position(lead)
    if lx and ((route[#route].x - lx)^2 + (route[#route].y - ly)^2 >= 1) then
        route[#route + 1] = { x = lx, y = ly, width = 6 }
    end
    if #route < 2 then return nil end
    return route
end

local function disembark(actor, player, session, car)
    -- Release the native driver as soon as the player leaves. Waiting for a
    -- distance threshold can strand a follower just beyond the gap limit.
    if SC.Driving.isDriving(actor) then
        local released = Convoy.release(actor, "player_left_car")
        if released ~= true then return true end
    end
    if SC.Vehicle.isStationary(car) ~= true then return true end
    local exited, why = SC.Vehicle.exit(actor, car, nil, {
        restoreByDoor = true, followPlayer = true,
    })
    if exited == true then
        session.parked, session.requested, session.exitPending = true, false, nil
        session.lead = nil
    else
        session.exitPending = true
        if now() - (session.lastExitNotice or 0) >= 10000 then
            notify(player, actor, why or "no_safe_exit")
            session.lastExitNotice = now()
        end
    end
    return true
end

function Convoy.tick(current)
    current = tonumber(current) or now()
    local player = type(getPlayer) == "function" and getPlayer() or nil
    for actor, session in pairs(sessions) do
        local id = selected(actor)
        if not id then sessions[actor] = nil
        else
            local car = SC.Vehicle.loadedBySqlId(id)
            local lead = playerCar(player)
            if lead and lead ~= session.lead then
                session.lead, session.trail, session.progress = lead, {}, 1
                session.leadLastX, session.leadLastY = nil, nil
            end
            local leadMoved = false
            if lead then
                appendTrail(session, lead)
                local lx, ly = U().position(lead)
                if lx and session.leadLastX then
                    leadMoved = (lx - session.leadLastX)^2
                        + (ly - session.leadLastY)^2 >= 1
                end
                if lx and (not session.leadLastX or leadMoved) then
                    session.leadLastX, session.leadLastY = lx, ly
                    session.leadLastMove = current
                end
            end
            if car and value(actor, "getVehicle") == car then
                if not lead and session.lead then
                    disembark(actor, player, session, car)
                elseif lead and SC.Driving.isDriving(actor) then
                    if current - (session.lastUpdate or 0) >= 500 then
                        local route, why = routeFor(session, car, lead)
                        if route then
                            local accepted, reason = SC.Driving.followVehicle(actor, lead, route, 50)
                            if accepted then session.lastUpdate = current
                            else session.failed = reason or "route_rejected" end
                        elseif why then session.failed = why end
                    end
                    local status = SC.Driving.status(actor)
                    if status and status.state == "engine_failed" then
                        session.failed = "engine_failed"
                    end
                    local x, y = U().position(car)
                    if x and (not session.lastX or (x - session.lastX)^2
                        + (y - session.lastY)^2 >= 1) then
                        session.lastX, session.lastY, session.lastMove = x, y, current
                    elseif session.lastUpdate > 0 and session.leadLastMove
                        and current - session.lastMove > 10000
                        and current - session.leadLastMove < 2000
                        and distance(car, lead) > 25 then
                        session.failed = "road_blocked"
                    end
                end
                if session.failed then
                    abandon(actor, player, session, session.failed)
                end
            end
        end
    end
    return true
end

function Convoy.reset()
    sessions = setmetatable({}, { __mode = "k" })
end

return Convoy
