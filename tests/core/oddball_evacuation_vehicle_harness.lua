-- SPDX-License-Identifier: MIT
local SC = LivingFellows
local Vehicle = SC.OddballEvacuationVehicle
local joy, brock, player = { id = "joy", x = 0.5, y = 0.5, z = 0 }, { id = "brock" }, {}
local group = { id = "evac", house = { anchor = { x = 0, y = 0, z = 0 } },
    oddball = { stage = "waiting" } }
local calls, claim, active, outside = {}, nil, nil, false
local database, saveReady, failFlush, roadClosed = "present", false, false, false
local function record(value) calls[#calls + 1] = value end

local function newCar(id, distance)
    local car = { id = id, x = distance, y = 0, z = 0, stopped = true,
        engine = true, doors = {}, seats = {}, data = {} }
    function car:getSqlId() return self.id end
    function car:getScriptName() return "Base.CarNormal" end
    function car:getModData() return self.data end
    function car:getMaxPassengers() return 4 end
    function car:getCharacter(seat) return self.seats[seat] end
    function car:getPassengerDoor(seat)
        return { getDoor = function()
            return { isLocked = function() return self.doors[seat] == true end }
        end }
    end
    function car:getVehicleTowing() return self.trailer end
    function car:getVehicleTowedBy() return self.tow end
    function car:isEngineRunning() return self.engine end
    function car:isEngineStarted() return self.engine end
    function car:isKeysInIgnition() return true end
    function car:shutOff() self.engine = false end
    return car
end

local near, farther, far = newCar(4, 10), newCar(5, 18), newCar(6, 26)
local loaded = { near, farther, far }
local driverSquare, passengerSquare = { x = 19, y = 1, z = 0 }, { x = 19, y = -1, z = 0 }
local function atSquare(actor, square)
    return actor.x == square.x + 0.5 and actor.y == square.y + 0.5 and actor.z == square.z
end
SC.GameplayUtil = {
    call = function(object, method, ...)
        if not object then return nil, false end
        if method == "getVehicle" then return object.vehicle, true end
        if not object[method] then return nil, false end
        return object[method](object, ...), true
    end,
    position = function(object) return object.x, object.y, object.z end,
    idOf = function(actor) return actor.id end,
    squareKey = function(square) return square.x .. ":" .. square.y .. ":" .. square.z end,
    arrived = atSquare,
}
SC.OddballKit = { livingActor = function(_, index) return index == 1 and joy or brock end }
SC.OddballKit.recordActor = SC.OddballKit.livingActor
SC.Registry = { byId = function() return {} end }
SC.Vehicle = {
    loadedVehicles = function() return loaded end,
    loadedBySqlId = function(id)
        for _, car in ipairs(loaded) do if car.id == id and not car.removed then return car end end
    end,
    serviceClaim = function(car) return claim and claim.car == car and claim or nil end,
    reserveService = function(id, car, seats)
        assert(seats.joy == 0 and seats.brock == 1)
        claim = { car = car, requestId = id }
        return true
    end,
    releaseService = function() claim = nil end,
    isStationary = function(car) return car.stopped end,
    boardingSquares = function(_, _, seat)
        if seat == 0 then return { passengerSquare, driverSquare } end
        return { passengerSquare }
    end,
    isSeatReserved = function() return false end,
    isNativeSeated = function(actor) return actor.vehicle ~= nil, actor.vehicle, actor.seat end,
    transactionStatus = function() end,
    exit = function(actor, car)
        record("exit-" .. actor.id)
        car.seats[actor.seat], actor.vehicle, actor.seat = nil, nil, nil
        return true
    end,
}
local staging
SC.Navigation = {
    requestAny = function(actor, candidates, gait, order)
        assert(actor == joy and gait == "walk" and order.preferVerifiedPath)
        assert(#candidates == 1 and candidates[1] == driverSquare, "staged Joy on a passenger contact")
        staging = { goalAction = order.action }
        if atSquare(actor, driverSquare) then return true, "arrived", driverSquare end
        record("stage-joy")
        return true, "walking"
    end,
    peek = function() return staging end,
    cancel = function() staging = nil end,
}
SC.ExpeditionCar = {
    planRoadAccess = function(car)
        if car ~= near and not roadClosed then return {} end
    end,
    displayName = function() return "Car" end,
    accessBetween = function() return true end,
    boardMember = function(actor, order)
        assert(order.gait == "walk")
        record("board-" .. actor.id)
        order.car.seats[order.seat], actor.vehicle, actor.seat = actor, order.car, order.seat
        return true
    end,
}
SC.TaxiService = {
    departureGoal = function(car, _, route)
        if route() then return { x = 58, y = 0, z = 0 }, nil, { x = car.x, y = 0, z = 0 } end
    end,
    outsideViews = function() return outside end,
}
SC.Driving = {
    available = function() return true end,
    jobStatus = function() return active end,
    drive = function(actor)
        assert(actor == joy and actor.vehicle.seats[1] == brock)
        active = { owned = true }
        record("drive")
        return true
    end,
    stop = function() active = nil return true end,
    hasKey = function() return false end,
}
SC.Persistence = { save = function() record("save") return true end }
SC.HomeTrip = { copyCarReceipt = function(receipt) return receipt end }
SCSplitScreenProbe = {
    homeVehicleSaveCapability = function() return true end,
    requestHomeVehicleSave = function(car)
        assert(car.seats[0] == nil and car.seats[1] == nil and not car.engine)
        car.data.SC_HomeVehicleSaveTag = "committed-tag"
        return 1
    end,
    pollHomeVehicleSave = function() return saveReady and "ready" or "pending" end,
    homeVehicleSaveReceipt = function() return { tagUUID = "committed-tag", x = farther.x, y = farther.y } end,
    cancelHomeVehicleSave = function() return true end,
    flushGlobalModDataForWorldExit = function() record("flush") return not failFlush end,
    vehicleRetirementStatus = function() return database end,
}
removeVehicle = function(_, car) record("remove") car.removed = true end

local report = assert(Vehicle.candidate(group, player))
assert(report.sqlId == farther.id and report.distance == 18 and report.seat == 1 and report.label == "Car")
assert(farther.data.SC_EvacuationDonation == nil and claim == nil, "menu inspection wrote state")
assert(Vehicle.candidate(group, player, near.id) == nil, "car without road access passed")
assert(Vehicle.candidate(group, player, far.id) == nil, "car outside range passed")
farther.engine = false
assert(Vehicle.candidate(group, player) == nil, "engine-off car passed")
farther.engine, farther.stopped = true, false
assert(Vehicle.candidate(group, player) == nil, "moving car passed")
farther.stopped, farther.seats[3] = true, player
assert(Vehicle.candidate(group, player) == nil, "occupied car passed")
farther.seats[3], farther.trailer = nil, far
assert(Vehicle.candidate(group, player) == nil, "towing car passed")
farther.trailer, farther.doors[0] = nil, true
assert(not Vehicle.accept(group, player, farther.id), "locked driver door passed")
farther.doors[0] = nil
SC.Registry.living = function() return { joy } end
SC.Commands = { peekExisting = function(actor)
    assert(actor == joy)
    return { recruited = true, order = "follow", followCarSqlId = farther.id }
end }
assert(Vehicle.candidate(group, player) == nil, "convoy car passed")
SC.Commands = nil
assert(Vehicle.accept(group, player, farther.id), "valid car rejected")
assert(claim and group.oddball.stage == "boarding")
assert(Vehicle.pulse(group, player, 0) == "pending" and calls[#calls] == "stage-joy"
    and not brock.vehicle and not joy.vehicle, "Brock boarded before Joy cleared the door")
joy.x, joy.y = driverSquare.x + 0.5, driverSquare.y + 0.5
assert(Vehicle.pulse(group, player, 300) == "pending" and calls[#calls] == "board-brock" and not staging)
assert(Vehicle.pulse(group, player, 600) == "pending" and calls[#calls] == "board-joy")
assert(Vehicle.pulse(group, player, 900) == "pending" and group.oddball.stage == "driving")
assert(Vehicle.pulse(group, player, 1200) == "pending" and calls[#calls] == "drive")
active.result, roadClosed = "failed", true
local status, reason = Vehicle.pulse(group, player, 4200)
assert(status == "pending" and reason == "evacuation_road_wait" and not active
    and group.oddball.stage == "driving" and not farther.removed,
    "a blocked route must hold the crew and car")
roadClosed = false
assert(Vehicle.pulse(group, player, 7100) == "pending" and not active,
    "the road retry must honor its cooldown")
assert(Vehicle.pulse(group, player, 7200) == "pending" and active and calls[#calls] == "drive",
    "the same crew retries driving when the road opens")
farther.x = 48
assert(Vehicle.pulse(group, player, 7350) == "pending" and group.oddball.stage == "driving",
    "visible travel entered retirement")
outside = true
assert(Vehicle.pulse(group, player, 7500) == "pending" and group.oddball.stage == "retiring")
assert(Vehicle.pulse(group, player, 8000) == "pending" and not farther.engine)
assert(Vehicle.pulse(group, player, 8500) == "pending")
assert(Vehicle.pulse(group, player, 9000) == "pending" and not farther.removed)
saveReady = true
assert(Vehicle.pulse(group, player, 9500) == "pending" and not farther.removed)
failFlush = true
assert(Vehicle.pulse(group, player, 10000) == "pending" and not farther.removed, "failed intent flush deleted car")
failFlush = false
assert(Vehicle.pulse(group, player, 10500) == "pending" and farther.removed and calls[#calls] == "remove")
assert(Vehicle.pulse(group, player, 11000) == "pending", "unloaded car passed as deleted")
database = "unknown"
assert(Vehicle.pulse(group, player, 11500) == "pending", "unknown database passed as deleted")
database = "absent"
assert(Vehicle.pulse(group, player, 12000) == "departed" and not claim)
assert(Vehicle.pulse(group, player, 12500) == "departed" and not Vehicle.cancel(group),
    "terminal removal could not be replayed")
print("EVACUATION_VEHICLE_PASS")
