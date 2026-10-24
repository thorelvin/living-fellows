-- SPDX-License-Identifier: MIT
-- Real car boarding and requestAny policy; the ordinary route owner below
-- emulates a yielding detour and the world's eventual physical door arrival.
local SC, checks = SurvivorCompanion, 0
local Car, Navigation, U = SC.ExpeditionCar, SC.Navigation, SC.GameplayUtil
local function check(value, message)
    checks = checks + 1
    assert(value, "car boarding navigation " .. checks .. ": " .. message)
end
local now, nativeNearest, routeCalls, boardCalls, failures = 1000000, 0, 0, 0, 0
local diagnostics, printed = {}, {}
local oldPrint = print
function print(message) printed[#printed + 1] = tostring(message) end
local source = { x = 11979, y = 6921, z = 0 }
local target = { x = 11990, y = 6900, z = 0 }
for _, square in ipairs({ source, target }) do
    function square:getX() return self.x end
    function square:getY() return self.y end
    function square:getZ() return self.z end
    function square:getRoom() return nil end
end
local driver = { id = "leader", x = 11979.5, y = 6921.465, z = 0, square = source }
function driver:getX() return self.x end
function driver:getY() return self.y end
function driver:getZ() return self.z end
function driver:isDead() return false end
local car = { x = 11990, y = 6900, z = 0, occupied = {} }
function car:getX() return self.x end
function car:getY() return self.y end
function car:getZ() return self.z end
function car:getSqlId() return 46 end
local passenger = { id = "mate", car = car, seat = 1, isDead = function() return false end }
car.occupied[1] = passenger
local trip = { sqlId = 46, state = "boarding_home", leg = "home",
    seats = { leader = 0, mate = 1 }, boardStartedAt = now }
local mission = { leader = { id = "leader", actor = driver },
    roster = { { id = "leader", actor = driver }, { id = "mate", actor = passenger } },
    members = { [driver] = true, [passenger] = true },
    scout = { phase = "boarding_home", vehicle = trip } }
local token = { serial = 91 }
local beginBlocked, routeFailure
SC.Registry.idOf = function(actor) return actor.id end
SC.ExpeditionPrototype = { current = function() return mission end }
SC.Vehicle = {
    loadedBySqlId = function(id) return id == 46 and car or nil end,
    isNativeSeated = function(actor) return actor.car ~= nil, actor.car, actor.seat end,
    beginBoarding = function()
        if beginBlocked then return nil, "action_cooldown" end
        return { supervisorToken = token }
    end,
    preflightBoard = function(actor, vehicle, seat)
        if actor.square ~= target then return nil, "companion is not at the passenger door" end
        return { actorId = actor.id, vehicle = vehicle, seat = seat }
    end,
    boardingSquares = function() return { target }, 0 end,
    boardDriver = function(actor, vehicle, options)
        check(actor.square == target and options.allowVirtualSeat == false,
            "native entry requires the real reached driver door and forbids virtual seats")
        boardCalls = boardCalls + 1
        actor.car, actor.seat, vehicle.occupied[0] = vehicle, 0, actor
        return true, "native_seat"
    end,
    failTransaction = function(_, _, detail)
        failures = failures + 1
        check(detail.reason == routeFailure, "transaction failure keeps the exact route blocker")
    end,
}
SC.Driving = { hasKey = function() return false end }
SC.ActionSupervisor = {
    isCurrent = function(value) return value == token end,
    movementPermission = function() return true end,
}
SC.NativeActions = { pathToNearest = function()
    nativeNearest = nativeNearest + 1
    return false, "native_route_blocked_by_locked_door"
end }
U.nowMs = function() return now end
U.isValidActor = function(value) return value == driver end
U.squareOf = function(value) return value and (value.square or value) end
U.isSquareFree = function() return true end
U.safehouseBlocker = function() return false end
U.arrived = function(actor, square) return actor.square == square end
U.diagnostic = function(_, actor, text)
    diagnostics[#diagnostics + 1] = { actor = actor, text = text }
end
Navigation._maintainTraversalForRequest = function() return nil end
Navigation._readyForNavigation = function() return true end
Navigation.request = function(actor, goal, _, intent)
    routeCalls = routeCalls + 1
    check(actor == driver and goal == target and intent.supervisorToken == token,
        "the same vehicle owner retains each bounded detour planning slice")
    if intent.preferVerifiedPath then check(intent.verifiedSelectedGoal == true,
        "boarding requests immediate physical verification of its assigned seat contact route") end
    if routeFailure then return false, routeFailure end
    return true, "path_searching"
end

local accepted = Navigation.requestAny(driver, { target }, "walk", {
    action = "approach_vehicle", supervisorToken = token, arrivalDistance = 0.15,
})
check(accepted and nativeNearest == 1 and routeCalls == 1,
    "positive control proves an ordinary nearest request enters the opaque native shortcut")
now = now + 5001 -- Expire the positive control's native-failure cooldown.
routeCalls = 0
local order = Car.boardingOrderFor(driver)
for _ = 1, 2 do
    local handled, reason = Car.boardMember(driver, order, {})
    check(handled and reason == "path_searching" and nativeNearest == 1
            and failures == 0 and boardCalls == 0 and driver.square == source,
        "returning driver keeps the portal-aware detour instead of restarting a blocked native route")
end
check(routeCalls == 2 and trip.boardingStatus.leader.navigationReason == "path_searching",
    "yielding planning neither fails the seat transaction nor reports a completed boarding")
-- The world advances the body along that route; the boarding controller does
-- not change coordinates or force a seat while planning is incomplete.
driver.square, driver.x, driver.y = target, 11990.5, 6900.5
check(Car.boardMember(driver, order, {}) and boardCalls == 1 and driver.car == car,
    "the assigned native seat commits once after physical door arrival")
check(Car.boardMember(driver, order, {}) and boardCalls == 1,
    "rechecking an already occupied assigned seat never boards twice")

driver.car, driver.seat, car.occupied[0] = nil, nil, nil
driver.square, driver.x, driver.y = source, 11979.5, 6921.465
routeFailure = "path_blocked:door_locked"
local handled, reason = Car.boardMember(driver, order, {})
check(not handled and reason == routeFailure and failures == 1
        and diagnostics[#diagnostics].text:find(routeFailure, 1, true)
        and diagnostics[#diagnostics].text:find("11979.5", 1, true),
    "boarding failure reports its actual navigation reason and physical driver position")
beginBlocked = true
Car.boardMember(driver, order, {})
check(trip.boardingStatus.leader.reason == "action_cooldown"
        and trip.boardingStatus.leader.navigationReason == routeFailure,
    "a later supervisor cooldown cannot erase the last physical route failure")
now = now + 120001
check(Car.pulse(mission, now) and trip.state == "boarding_rollback"
        and trip.blocker == "boarding_deadline" and passenger.car == car,
    "a genuinely unreachable driver retains the bounded safe boarding deadline")
local explained = false
for _, message in ipairs(printed) do
    if message:find("action=boarding_deadline", 1, true)
        and message:find("actor=leader", 1, true)
        and message:find("navigation=" .. routeFailure, 1, true) then explained = true end
end
check(explained, "deadline diagnostics identify the missing driver and last blocked route")
print = oldPrint
SC_TEST_REPORT = "CAR_BOARDING_NAVIGATION_PASS checks=" .. checks
