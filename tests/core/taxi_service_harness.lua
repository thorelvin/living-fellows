-- SPDX-License-Identifier: MIT
local SC = SurvivorCompanion
local Service = SC.TaxiService
local function check(value, message)
    if not value then error("taxi service: " .. message) end
end

local car = { x = 100, y = 200, z = 0, seats = {} }
function car:getX() return self.x end
function car:getY() return self.y end
function car:getZ() return self.z end
function car:getSeat(actor)
    for seat, occupant in pairs(self.seats) do
        if occupant == actor then return seat end
    end
    return -1
end
function car:getCharacter(seat) return self.seats[seat] end
function car:getMaxPassengers() return 4 end
function car:getSqlId() return 771 end
function car:isRemovedFromWorld() return self.removed == true end
local passengerDoor = { locked = true, opened = true }
function passengerDoor:isLocked() return self.locked end
function passengerDoor:setLocked(value) self.locked = value end
function passengerDoor:isOpen() return self.opened end
function passengerDoor:setOpen(value) self.opened = value end
function car:getPassengerDoor(seat)
    return seat == 1 and { getDoor = function() return passengerDoor end } or nil
end
function car:transmitPartDoor() end

local caller = { x = 100, y = 200, z = 0, vehicle = car }
function caller:getVehicle() return self.vehicle end
function getSpecificPlayer(index) return index == 0 and caller or nil end
car.seats[1] = caller
local chauffeur = { vehicle = car, data = { LF_MarkusDriver = "markus:1:1" } }
function chauffeur:getVehicle() return self.vehicle end
function chauffeur:getModData() return self.data end
car.seats[0] = chauffeur
local spoken = {}

SC.GameplayUtil = {
    call = function(object, name, ...)
        local method = object and object[name]
        if type(method) ~= "function" then return nil, false end
        return method(object, ...), true
    end,
    position = function(value)
        return value.x, value.y, value.z
    end,
    nowMs = function() return 1000 end,
    say = function(actor, line)
        check(actor == chauffeur, "Markus speaks his own line")
        spoken[#spoken + 1] = line
        return true
    end,
}
local booking = { generation = 1, phase = "at_pickup" }
SC.TaxiBooking = {
    current = function() return booking end,
    checkRadio = function() return true end,
    advance = function(generation, phase)
        check(generation == booking.generation, "booking generation")
        booking.phase = phase
        return true
    end,
    complete = function(generation)
        check(generation == booking.generation
            and booking.phase == "at_destination", "complete booking")
        booking = nil
        return true
    end,
    abort = function() booking = nil return true end,
}
local loaded = car
local cabRetired = 0
SC.TaxiCab = {
    recover = function()
        return loaded ~= nil, loaded or "cab_unloaded_or_missing"
    end,
    retireRemoved = function(sqlId, token)
        check(sqlId == 771 and token == "markus:1:1",
            "retire only the owned cab")
        cabRetired = cabRetired + 1
        return true
    end,
    captureAppearance = function()
        return { Front = 0.7, Rear = 0.2, Left = 0.4, Right = 0.5 }
    end,
}
local actorRetired = 0
SC.Actor = {
    isCompanion = function(actor)
        return actor == chauffeur and actor.removed ~= true
    end,
    remove = function(actor)
        check(actor == chauffeur and actor.vehicle == nil,
            "remove Markus only after he exits")
        actor.removed = true
        actorRetired = actorRetired + 1
        return true
    end,
}
SC.Registry = { byId = function(id)
    return id == "markus-driver" and { actor = chauffeur } or nil
end }
SC.ExpeditionCar = { parkingAreas = function()
    return { { id = "base-parking", name = "Home",
        x1 = 248, x2 = 252, y1 = 298, y2 = 302 } }
end }
SC.ExpeditionRoute = { planFromPoint = function(origin, target)
    local distance = math.sqrt((origin.x - target.x)^2
        + (origin.y - target.y)^2)
    return { roadLength = origin.x >= 250 and distance or 250 }, nil,
        { entryX = origin.x, entryY = origin.y,
            exitX = target.x, exitY = target.y }
end }
local fareReserved, fareCommitted, fareCancelled = 0, 0, 0
local fareWaiting = false
local fareRetired = 0
local luggageBlocked = false
SC.TaxiFares = {
    quote = function() return { required = 0 } end,
    reserve = function(_, vehicle, distance)
        check(vehicle == car and distance == 250, "reserve exact car and route")
        if fareWaiting then return false, "fare_waiting" end
        fareReserved = fareReserved + 1
        return true
    end,
    cancel = function()
        fareCancelled = fareCancelled + 1
        return true
    end,
    commit = function(vehicle)
        check(vehicle == car, "commit exact native cab")
        fareCommitted = fareCommitted + 1
        return true
    end,
    retirementStatus = function(vehicle)
        check(vehicle == car, "inspect exact cab before deletion")
        if luggageBlocked then return false, "customer_property_in_cab" end
        return true
    end,
    retireRemoved = function(sqlId)
        check(sqlId == 771, "retire matching fare ledger")
        fareRetired = fareRetired + 1
        return true
    end,
}
local driveCalls, releaseCalls, activeJob = 0, 0, nil
SC.Driving = {
    isDriver = function(actor) return actor == chauffeur and car.seats[0] == actor end,
    start = function(actor, passenger)
        check(actor == chauffeur and passenger == caller, "resume held car")
        return true
    end,
    drive = function(actor, target, options)
        check(actor == chauffeur, "drive with Markus")
        if options.passenger then
            check(options.passenger == caller
                and target.x == 250.5 and target.y == 300.5,
                "ride exact passenger to selected destination")
            check(options.speedKmh == 50 and options.cornerSpeedScale == 2,
                "taxi ride retains cruise and doubles corner target")
        else
            check(target.x > car.x + 25, "departure heads away on road")
            check(options.speedKmh == 30 and options.cornerSpeedScale == 2,
                "taxi departure retains cruise and doubles corner target")
        end
        driveCalls = driveCalls + 1
        activeJob = {}
        return true
    end,
    release = function() releaseCalls = releaseCalls + 1 return true end,
    jobStatus = function() return activeJob end,
}
SC.Vehicle = {
    isStationary = function(vehicle) return vehicle == car end,
    loadedBySqlId = function(sqlId)
        return sqlId == 771 and loaded or nil
    end,
    exit = function(actor, vehicle)
        check(actor == chauffeur and vehicle == car, "exit exact car")
        car.seats[0], chauffeur.vehicle = nil, nil
        return true
    end,
}
SC.GameplayUtil.gridSquare = function(x, y)
    return { getX = function() return x end, getY = function() return y end }
end
isoToScreenX = function(_, x) return (x - 250) * 20 end
isoToScreenY = function(_, _, y) return (y - 300) * 20 end
getPlayerScreenLeft = function() return -250 end
getPlayerScreenTop = function() return -250 end
getPlayerScreenWidth = function() return 500 end
getPlayerScreenHeight = function() return 500 end
removeVehicle = function(playerActor, vehicle)
    check(playerActor == caller and vehicle == car,
        "remove only the delivered taxi")
    check(vehicle.seats[0] == nil and vehicle.seats[1] == nil,
        "empty cab before native removal")
    vehicle.removed, loaded = true, nil
end

local saved = { schema = 1, driverId = "markus-driver",
    visit = { bookingGeneration = 1, phase = "ready_to_depart",
        cabToken = "markus:1:1", cabSqlId = 771,
        driverId = "markus-driver",
        pickup = { x = 100, y = 200, z = 0 } } }
check(Service.restore(saved), "restore waiting taxi")
check(Service.tick(1000), "reattach exact driver and cab")
check(Service.tick(10999) and #spoken == 0,
    "destination reminder waits ten real seconds")
check(Service.tick(11000) and #spoken == 1
    and string.find(spoken[1], "map", 1, true)
    and string.find(spoken[1], "places to be", 1, true),
    "Markus asks for the map once")
check(Service.tick(12000) and #spoken == 1,
    "waiting taxi does not repeat the reminder")
check(Service.restore(saved) and Service.tick(1000),
    "fresh boarding starts a new reminder timer")
check(#Service.destinations(caller, {}) == 1, "base parking offered")
local pin = Service.previewPoint(caller, { x = 252, y = 302, z = 0 })
check(pin and pin.target.x == 252 and pin.required == 0,
    "map pin quotes a nearby road stop")
check(Service.previewPoint(caller, { x = 252, y = 302, z = 1 }) == nil,
    "upper-floor map point refused")
fareWaiting = true
check(Service.departToPoint(caller, {}, { x = 252, y = 302, z = 0 }) == false,
    "valid map point may await fare")
check(Service.tick(11000) and #spoken == 1
    and Service.current().destinationProvided == true,
    "fare waiting does not nag after a map destination was supplied")
fareWaiting = false
check(Service.depart(caller, {}, "base-parking") == true,
    "paid or free receipt reserved before driving")
check(fareReserved == 1 and driveCalls == 1 and releaseCalls == 1
        and not passengerDoor.locked and not passengerDoor.opened,
    "one departure transaction")
local cold = Service.export()
check(Service.reset() and Service.restore(cold), "cold restart journal")
loaded = nil
check(Service.tick(2000) and driveCalls == 1,
    "unloaded cab waits without creating another car")
loaded = car
check(Service.tick(3000) and driveCalls == 2,
    "loaded exact cab resumes ride")
activeJob.result = "arrived"
car.x, car.y = 250.5, 300.5
check(Service.tick(4000) and Service.current().phase == "waiting_exit",
    "road arrival waits for passenger exit")
check(Service.tick(5000) and fareCommitted == 0,
    "seated passenger cannot settle")
caller.vehicle, car.seats[1] = nil, nil
check(Service.tick(6000) and fareCommitted == 1,
    "dropoff settles once after real exit")
car.seats[2] = {}
check(Service.tick(7000) and Service.current().phase == "finishing"
    and driveCalls == 2, "remaining rider holds departure")
car.seats[2] = nil
luggageBlocked = true
check(Service.tick(12000) and Service.current().phase == "finishing"
    and driveCalls == 2, "customer luggage holds departure")
luggageBlocked = false
check(Service.tick(17000) and Service.current().phase == "departing"
    and car.seats[0] == chauffeur, "Markus drives away after dropoff")
car.x = 298.5
activeJob.result = "arrived"
check(Service.tick(18000) and Service.current() == nil and booking == nil
    and actorRetired == 1 and loaded == nil and car.removed == true,
    "cab despawns after moving out of view")
check(cabRetired == 1 and fareRetired == 1,
    "cab and fare ownership retire once")
check(fareCancelled == 0, "successful ride retains payment")

-- A nonrecruited service driver is absent from ordinary companion saves. The
-- exact saved cab and passenger remain; rebuild Markus with his stable id,
-- board him beside the already seated customer, and resume the same fare.
booking = { generation = 1, phase = "in_transit" }
caller.vehicle, car.seats[1], car.seats[0] = car, caller, nil
car.removed, loaded = false, car
chauffeur = nil
local restoredDriver, restoreTicket
SC.TaxiCab.current = function()
    return { ownershipToken = "markus:1:1", sqlId = 771 }
end
SC.Registry.idOf = function(actor)
    return actor == chauffeur and "markus-driver" or nil
end
SC.Registry.snapshot = function() return {} end
SC.Actor.beginSpawn = function(square, profile)
    check(square ~= nil and profile.id == "markus-driver"
        and profile.recruited == false, "restore only the saved taxi driver")
    restoreTicket = { profile = profile }
    return restoreTicket
end
SC.Actor.pollSpawn = function(ticket)
    check(ticket == restoreTicket, "poll the one recovery spawn")
    restoredDriver = { vehicle = nil, data = {} }
    function restoredDriver:getVehicle() return self.vehicle end
    function restoredDriver:getModData() return self.data end
    chauffeur = restoredDriver
    check(ticket.profile.initialize(chauffeur), "mark recovered driver")
    return chauffeur
end
SC.GameplayUtil.gridSquare = function(x, y)
    return { getX = function() return x end, getY = function() return y end }
end
SC.GameplayUtil.isClearActorSpawnSquare = function() return true end
Vector3f = { new = function() return {} end }
function car:getPassengerPosition() return {} end
function car:getPassengerPositionWorldPos()
    return { x = function() return 100 end, y = function() return 200 end }
end
function car:getEnterSeatDistance() return 1 end
SC.Vehicle.preflightDriver = function(actor, vehicle, passenger)
    check(actor == chauffeur and vehicle == car and passenger == caller,
        "preflight with the booked passenger already seated")
    return { driver = actor }
end
SC.Driving.hasKey = function() return true end
SC.Driving.takeWheel = function(actor, vehicle, intent)
    check(actor == chauffeur and vehicle == car
        and intent.taxiPassenger == caller,
        "board exact recovered driver without moving passenger")
    car.seats[0], actor.vehicle = actor, car
    return true
end
local resumed = { schema = 1, driverId = "markus-driver",
    visit = { bookingGeneration = 1, phase = "in_transit",
        cabToken = "markus:1:1", cabSqlId = 771,
        driverId = "markus-driver", destinationId = "base-parking",
        pickup = { x = 100, y = 200, z = 0 },
        destination = { x = 250.5, y = 300.5, z = 0 },
        roadTiles = 250 } }
check(Service.restore(resumed), "restore ride missing only its driver")
check(Service.tick(1000) and restoreTicket == nil,
    "wait briefly for an existing actor to register")
check(Service.tick(6000) and restoreTicket ~= nil,
    "spawn one replacement only after cab recovery")
check(Service.tick(7000) and car.seats[0] == restoredDriver
    and driveCalls == 4 and Service.current().phase == "in_transit",
    "same ride resumes with stable driver identity")
check(Service.isBookedPassenger(caller, car),
    "driver boarding exception is limited to the booked passenger")

Service.reset()
local invalid = { schema = 1, driverId = "markus-driver",
    visit = { bookingGeneration = 1, phase = "invented" } }
check(Service.restore(invalid) == false and Service.current() == nil,
    "invalid saved phase cannot replace clean state")

-- A new radio call must not promise a second taxi while the original native
-- vehicle is outside the loaded cell. Its saved SQL identity remains owned.
SC.Driving.passengerAvailable = function() return true end
SC.TaxiCab.current = function() return { sqlId = 771 } end
SC.TaxiBooking.request = function() error("booking must not be opened") end
addVehicleDebug = function() error("must not spawn a replacement") end
loaded = nil
check(select(2, Service.request(caller, {})) == "cab_unloaded_or_missing",
    "unloaded old cab blocks an impossible repeat booking")

print("taxi service harness passed")
