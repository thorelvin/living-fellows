-- SPDX-License-Identifier: MIT
local SC, T = SurvivorCompanion, CAR_TEST
local Car = SC.ExpeditionCar
local checks = 0
local function check(value, label)
    checks = checks + 1
    assert(value, "car expedition " .. tostring(checks) .. ": " .. label)
end
local destination = { x = 160, y = 105, z = 0 }

check(#Car.parkingAreas() == 1, "only valid marked parking is offered")
check(Car.areaById("zone:42") == T.zone, "stable parking ID resolves")
check(Car.areaById("zone:missing") == nil, "deleted zone is rejected")
check(#Car.candidates(T.zone) == 1, "only the car actually in the zone is offered")
check(Car.candidates(T.zone)[1].name == "Masterson Horizon",
    "parking choice uses the game's translated model name")
T.cars[#T.cars + 1] = T.car(45, 300, 300)
check(#Car.candidates(T.zone) == 1, "off-zone car is not offered")
check(#Car.parkedCars() == 1 and Car.parkedCars()[1].sqlId == 44,
    "all-area parking discovery excludes cars outside every bay")

T.player = { modData = {}, getModData = function(self) return self.modData end }
check(Car.setPreference("alpha", T.zone.id, 44)
    and Car.preference("alpha").sqlId == 44,
    "a squad's preferred car is saved with its parking area")
check(Car.preference("bravo") == nil, "squad preferences stay separate")
T.base.id = "base:2"
check(Car.preference("alpha") == nil,
    "a preference from another base is not reused")
check(Car.setPreference("alpha", nil, nil),
    "a second base can keep its own automatic car choice")
T.base.id = "base:1"
check(Car.preference("alpha").sqlId == 44,
    "returning to the original base restores its car choice")
check(Car.setPreference("alpha", nil, nil)
    and Car.preference("alpha").sqlId == nil,
    "choosing any parked car clears the fixed vehicle preference")
T.player = nil

local second = T.car(46, 106, 106)
second.script = "Base.Van"
T.cars[#T.cars + 1] = second
check(#Car.parkedCars() == 2
    and Car.parkedCars()[2].name == "Franklin Valuline",
    "parking discovery includes each car's readable model")
local automatic = Car.preflight(T.team, nil, nil, destination)
check(automatic and automatic.sqlId == 44,
    "no car or area choice selects a usable parked car")
check(Car.preflight(T.team, T.zone.id, nil, destination).sqlId == 44,
    "a parking area without a car choice uses any usable car in that area")
T.cars[1].occupied[0] = { id = "other" }
automatic = Car.preflight(T.team, nil, nil, destination)
check(automatic and automatic.sqlId == 46,
    "automatic choice skips a parked car with an occupied driver seat")
check(select(2, Car.preflight(T.team, nil, 44, destination))
    == "seat_unavailable", "explicit car choice never changes cars")
second.occupied[0] = { id = "another" }
check(select(2, Car.preflight(T.team, nil, nil, destination))
    == "seat_unavailable", "automatic choice reports why all parked cars fail")
T.cars[1].occupied[0] = nil
second.occupied[0] = nil
table.remove(T.cars)

local ready, reason = Car.preflight(T.team, T.zone.id, 44, destination)
check(ready ~= nil and reason == nil, "usable car passes preflight")
check(T.routeCalls[1].origin.x == 102 and T.routeCalls[1].origin.z == 0,
    "route starts from car, not upstairs leader")
check(ready.seats.leader == 0 and ready.seats.mate == 1,
    "driver and passenger get exact physical seats")
check(ready.fuelRequired > 0 and ready.fuelRequired < ready.fuel,
    "measured fuel model includes reserve")
check(Car.fitsParking(T.cars[1], T.zone, ready.seats),
    "actual vehicle corners and exits fit the marked parking area")
T.polyOffset = 12
check(#Car.candidates(T.zone) == 0,
    "selector omits cars whose footprint is outside the parking area")
check(select(2, Car.fitsParking(T.cars[1], T.zone, ready.seats))
    == "parking_footprint_outside_area",
    "centre inside the area cannot conceal an outside vehicle corner")
T.polyOffset = nil
T.exitBlocked = 1
check(select(2, Car.fitsParking(T.cars[1], T.zone, ready.seats))
    == "parking_exit_blocked", "parking requires passenger exit clearance")
T.exitBlocked = nil

T.key = false
check(select(2, Car.preflight(T.team, T.zone.id, 44, destination))
    == "driver_needs_key", "missing key refuses dispatch")
T.cars[1].hotwired = true
check(Car.preflight(T.team, T.zone.id, 44, destination) ~= nil
    and Car.ensureDriverKey(T.team, T.cars[1]) == true,
    "hotwired car dispatches and starts without inventing or transferring a key")
T.cars[1].script = "Base.Van"
local hotwiredVan = Car.preflight(T.team, T.zone.id, 44, destination)
check(hotwiredVan ~= nil and hotwiredVan.fuelRequired > ready.fuelRequired,
    "a hotwired non-CarNormal vehicle uses a conservative fuel budget and can depart")
T.cars[1].script = "Base.CarNormal"
T.cars[1].hotwired = false
T.key = nil
local passengerInventory = T.team[2].actor.inventory
local leaderInventory = T.team[1].actor.inventory
local key = { container = passengerInventory,
    getKeyId = function() return 44 end,
    getContainer = function(self) return self.container end }
passengerInventory.items[1] = key
check(Car.preflight(T.team, T.zone.id, 44, destination) ~= nil,
    "passenger-owned exact key qualifies without inventing a copy")
check(Car.ensureDriverKey(T.team, T.cars[1])
    and key.container == leaderInventory
    and #leaderInventory.items == 1 and #passengerInventory.items == 0,
    "verified exact passenger key transfer reaches driver")
leaderInventory.items = {}
key.container = nil
T.key = true
T.fuel = 0
check(select(2, Car.preflight(T.team, T.zone.id, 44, destination))
    == "fuel_insufficient", "empty tank refuses dispatch")
T.fuel = nil
T.installedSeats = 1
check(select(2, Car.preflight(T.team, T.zone.id, 44, destination))
    == "seat_unavailable", "missing installed passenger seat refuses dispatch")
T.installedSeats = nil
T.entryX = 150
local longAccess = Car.preflight(T.team, T.zone.id, 44, destination)
check(longAccess and longAccess.access > 45,
    "a clear driveway beyond fifteen tiles remains eligible for car travel")
T.entryX = 203
check(select(2, Car.preflight(T.team, T.zone.id, 44, destination))
    == "road_access_too_far", "connector beyond the native road limit refuses dispatch")
T.entryX = nil
T.accessBlocked = true
check(select(2, Car.preflight(T.team, T.zone.id, 44, destination))
    == "road_access_blocked", "wall across driveway refuses dispatch")
T.accessBlocked = nil
T.doorBlocked = 1
check(select(2, Car.preflight(T.team, T.zone.id, 44, destination))
    == "door_inaccessible", "blocked passenger door refuses dispatch")
T.doorBlocked = nil

local descriptor = {
    state = "driving_out", leg = "outbound", sqlId = 44,
    script = "Base.CarNormal", seats = { leader = 0, mate = 1 },
    parkingZoneId = T.zone.id,
    parking = { x1 = 100, y1 = 100, x2 = 110, y2 = 110, z = 0 },
    departure = { x = 102, y = 102, z = 0 },
    homeRoadEntry = { x = 90, y = 102, z = 0 },
    home = { x = 103, y = 102, z = 0 },
    siteStop = { x = 160, y = 105, z = 0 },
    position = { x = 105, y = 102, z = 0 },
    departureFuel = 10,
    departureHeading = 0,
}
local saved = Car.copyDescriptor(descriptor, T.team, "leader")
check(saved and saved.seats.mate == 1, "stable descriptor copies the seat map")
check(saved.homeRoadEntry.x == 90,
    "verified outbound road attachment survives the car descriptor copy")
saved.homeRoadEntry.x = 91
check(descriptor.homeRoadEntry.x == 90,
    "saved road attachment does not alias the live trip")
saved.seats.mate = 3
check(descriptor.seats.mate == 1, "descriptor does not alias live seat map")
local resumed = Car.restoreDescriptor(descriptor, T.team, "leader")
check(resumed.state == "interrupted_by_load" and resumed.leg == "outbound",
    "moving car becomes checked interruption on load")
descriptor.state, descriptor.resumeState = "held", "driving_out"
local held = Car.restoreDescriptor(descriptor, T.team, "leader")
check(held.state == "held" and held.resumeState == "driving_out",
    "explicit player hold survives load")
descriptor.state, descriptor.resumeState = "driving_out", nil
descriptor.seats.mate = 0
check(Car.restoreDescriptor(descriptor, T.team, "leader") == nil,
    "duplicate driver seat quarantines car descriptor")
descriptor.seats.mate = 1

T.mission = { roster = T.team, leader = T.team[1],
    members = { [T.team[1].actor] = true, [T.team[2].actor] = true },
    scout = { vehicle = Car.restoreDescriptor(descriptor, T.team, "leader"),
        phase = "interrupted_by_load" } }
T.mission.scout.vehicle.position = { x = 102, y = 102, z = 0 }
local preparingTrip = T.mission.scout.vehicle
local priorState, priorPhase = preparingTrip.state, T.mission.scout.phase
preparingTrip.state, T.mission.scout.phase = "walking_to_car", "walking_to_car"
T.mission.scout.wood = { preparation = true, loans = { leader = { itemId = "axe-1" } } }
check(Car.boardingOrderFor(T.team[1].actor) == nil and Car.boardingOrderFor(T.team[2].actor) == nil,
    "wood gear preparation suppresses early driver and passenger boarding orders")
local staleOrder = { car = T.cars[1], seat = 0, sqlId = 44 }
check(not Car.boardMember(T.team[1].actor, staleOrder) and T.team[1].actor.car == nil,
    "a stale boarding order cannot take native ownership during wood preparation")
local beforePreparationDrive = T.driveCalls
check(Car.pulse(T.mission, 999, 999) and preparingTrip.state == "walking_to_car"
    and T.driveCalls == beforePreparationDrive,
    "car pulse holds deadlines, key transfers and travel until wood preparation finishes")
T.mission.scout.wood.preparation = nil
check(Car.boardingOrderFor(T.team[1].actor) ~= nil,
    "verified wood preparation completion immediately releases ordinary boarding")
T.mission.scout.wood.preparation = true
T.mission.scout.wood.pendingReturnReason = "radio_return"
local originalWood, stopReady = SC.ExpeditionWood, false
SC.ExpeditionWood = { stop = function() return stopReady, "wood_work_settling" end }
check(not Car.requestReturn(T.mission, 999) and preparingTrip.state == "walking_to_car"
    and T.mission.scout.wood.pendingCarReturnReason == "radio_return",
    "predeparture recall waits for native wood gear actions to settle")
stopReady = true
check(Car.requestReturn(T.mission, 1000) and preparingTrip.state == "boarding_rollback"
    and not T.mission.scout.wood.preparation and T.mission.scout.wood.endReason == "radio_return"
    and T.mission.scout.wood.pendingCarReturnReason == nil
    and T.mission.scout.wood.pendingReturnReason == nil
    and T.mission.scout.wood.loans.leader.itemId == "axe-1",
    "settled recall clears preparation and retains exact borrowed-tool obligations")
preparingTrip.state, preparingTrip.leg = "held", "outbound"
T.mission.scout.wood.preparation = true
check(not Car.requestReturn(T.mission, 1001, "wood_night")
    and T.mission.scout.wood.pendingCarReturnReason == "wood_night"
    and not T.mission.scout.wood.preparation,
    "held car recall settles preparation but keeps its requested direction queued during recovery")
preparingTrip.state, preparingTrip.leg = "parked_at_site", "outbound"
T.mission.scout.wood.doneReason = "wood_quantity_met"
check(Car.requestReturn(T.mission, 1002, "wood_quantity_met")
    and preparingTrip.state == "returning_to_car" and preparingTrip.leg == "home"
    and T.mission.scout.phase == "returning_to_car"
    and T.mission.scout.wood.pendingCarReturnReason == nil,
    "wood quota completion at the forest changes the native car leg before boarding home")
SC.ExpeditionWood = originalWood
T.mission.scout.wood = nil
preparingTrip.state, preparingTrip.leg, T.mission.scout.phase = priorState, "outbound", priorPhase
preparingTrip.blocker = nil
T.mission.scout.fishingPreparation = { reason = "fishing_preparing_rod" }
check(Car.boardingOrderFor(T.team[1].actor) == nil and Car.pulse(T.mission, 1000)
    and preparingTrip.state == priorState,
    "the same native boarding gate also preserves fishing preparation")
T.mission.scout.fishingPreparation = nil
check(Car.boardingOrderFor(T.team[1].actor) == nil,
    "load interruption cannot board before car and roster revalidation")
check(Car.pulse(T.mission, 1000) and
    T.mission.scout.vehicle.state == "boarding_out",
    "healthy restored car and team automatically begin reboarding")
local driver = Car.boardingOrderFor(T.team[1].actor)
check(driver and driver.seat == 0, "original leader is assigned driver door")
check(Car.boardMember(T.team[1].actor, driver), "leader boards exact seat")
local passenger = Car.boardingOrderFor(T.team[2].actor)
check(Car.boardMember(T.team[2].actor, passenger), "passenger boards exact seat")
check(Car.ownsSeat(T.team[2].actor, T.cars[1]),
    "expedition owns passenger seat before drive lease")
check(Car.pulse(T.mission, 2000) and T.driveCalls == 1
    and T.mission.scout.vehicle.state == "driving_out",
    "car starts only after full roster occupies assigned seats")
check(Car.requestReturn(T.mission, 2500) and
    T.mission.scout.vehicle.state == "boarding_home"
    and T.mission.scout.vehicle.leg == "home",
    "radio return stops outbound driving before planning home leg")
local homeTrip = T.mission.scout.vehicle
check(Car.pulse(T.mission, 2600) and homeTrip.state == "driving_home"
        and T.lastDriveOptions and T.lastDriveOptions.roadAccessExit
        and T.lastDriveOptions.roadAccessExit.entry == homeTrip.homeRoadEntry
        and T.lastDriveOptions.roadAccessExit.bay == homeTrip.departure,
    "the home drive is told to turn into the planned driveway toward the bay: "
        .. tostring(homeTrip.state) .. " " .. tostring(homeTrip.blocker))

T.team[1].actor.car, T.team[1].actor.seat = nil, nil
T.team[2].actor.car, T.team[2].actor.seat = nil, nil
T.mission.scout.vehicle.state = "interrupted_by_load"
T.fuel = 0
local drives = T.driveCalls
check(Car.pulse(T.mission, 3000) and
    T.mission.scout.vehicle.state == "fallback_unloading"
        and T.driveCalls == drives,
    "fuel removed on load triggers verified walking fallback")
T.fuel = nil
T.team[1].actor.car, T.team[1].actor.seat = T.cars[1], 0
T.team[2].actor.car, T.team[2].actor.seat = T.cars[1], 1
T.cars[1].x = 96
T.mission.scout.vehicle = Car.copyDescriptor(descriptor, T.team, "leader")
T.mission.scout.vehicle.state = "parking_home"
T.mission.scout.vehicle.leg = "home"
T.mission.scout.phase = "parking_home"
T.driveStatus = { result = "arrived" }
local parkingPulse = Car.pulse(T.mission, 4000)
check(parkingPulse and T.approaches == 1
    and T.approachGoal.x == 102
    and T.mission.scout.vehicle.state == "parking_home",
    "arrival outside the bay starts one bounded precise approach: "
        .. tostring(T.mission.scout.vehicle.state) .. " / "
        .. tostring(T.mission.scout.vehicle.blocker) .. " / "
        .. tostring(T.approaches))
T.cars[1].x = 102
T.driveStatus = { result = "arrived" }
T.ready = false
check(Car.pulse(T.mission, 4500)
        and T.mission.scout.vehicle.state == "parking_home"
        and T.approaches == 1,
    "a coasting car inside the bay settles before any new parking drive")
T.ready = true
check(Car.pulse(T.mission, 5000) and
    T.mission.scout.vehicle.state == "unloading_home",
    "verified footprint and heading permit home unloading")
T.mission.scout.vehicle.state = "parking_home"
T.mission.scout.vehicle.approachStartedAt = nil
T.cars[1].x = 96
T.accessBlocked = true
check(Car.pulse(T.mission, 6000) and
    T.mission.scout.vehicle.state == "held" and T.approaches == 1,
    "blocked access never starts a second parking approach")
T.accessBlocked = nil

T.team[1].actor.car, T.team[1].actor.seat = nil, nil
T.team[2].actor.car, T.team[2].actor.seat = nil, nil
T.cars[1].occupied = {}
T.cars[1].x = 102
T.mission.scout.vehicle = Car.restoreDescriptor(descriptor, T.team, "leader")
T.mission.scout.vehicle.position = { x = 102, y = 102, z = 0 }
T.mission.scout.phase = "interrupted_by_load"
local retained = T.cars[1]
T.cars = {}
check(Car.pulse(T.mission, 40000) and
    T.mission.scout.vehicle.state == "interrupted_by_load",
    "unloaded car waits before restart decision")
check(Car.pulse(T.mission, 72000) and
    T.mission.scout.vehicle.state == "held"
        and T.mission.scout.vehicle.blocker == "car_not_loaded",
    "bounded unloaded wait reports a recoverable hold")
T.cars = { retained }
check(Car.pulse(T.mission, 74000) and
    T.mission.scout.vehicle.state == "interrupted_by_load",
    "late car load automatically reopens checked restart")
check(Car.pulse(T.mission, 75000) and
    T.mission.scout.vehicle.state == "boarding_out",
    "late car load rechecks team and begins fresh boarding: "
        .. tostring(T.mission.scout.vehicle.state) .. "/"
        .. tostring(T.mission.scout.vehicle.blocker))
T.mission.scout.vehicle = Car.restoreDescriptor(descriptor, T.team, "leader")
T.mission.scout.vehicle.position = { x = 102, y = 102, z = 0 }
T.accessBlocked = true
check(Car.pulse(T.mission, 76000) and
    T.mission.scout.vehicle.state == "held"
        and T.mission.scout.vehicle.blocker == "road_access_blocked",
    "restart checks vehicle-width road access before boarding")
T.accessBlocked = nil
T.mission.scout.vehicle = Car.restoreDescriptor(descriptor, T.team, "leader")
T.mission.scout.vehicle.position = { x = 102, y = 102, z = 0 }
T.doorBlocked, T.doorReason = 1, "no safe loaded passenger-door square"
check(Car.pulse(T.mission, 77000) and
    T.mission.scout.vehicle.state == "held"
        and T.mission.scout.vehicle.blocker == "restart_door_not_loaded",
    "an unloaded door square waits instead of abandoning the car")
T.doorBlocked, T.doorReason = nil, nil
T.mission.scout.vehicle = Car.restoreDescriptor(descriptor, T.team, "leader")
T.mission.scout.vehicle.position = { x = 102, y = 102, z = 0 }
T.health = 20
check(Car.pulse(T.mission, 78000) and
    T.mission.scout.vehicle.state == "held"
        and T.mission.scout.vehicle.blocker == "restart_team_unfit",
    "an injured teammate prevents automatic reboarding")
T.health = nil
T.mission.scout.vehicle = Car.restoreDescriptor(descriptor, T.team, "leader")
T.mission.scout.vehicle.position = { x = 102, y = 102, z = 0 }
T.cars[1].occupied[2] = { id = "stranger" }
check(Car.pulse(T.mission, 79000) and
    T.mission.scout.vehicle.state == "fallback_unloading"
        and T.mission.scout.vehicle.blocker == "car_has_other_occupants",
    "a stranger in the exact car prevents reboarding")
T.cars[1].occupied[2] = nil
T.mission.scout.vehicle = Car.copyDescriptor(descriptor, T.team, "leader")
T.mission.scout.vehicle.state = "fallback_unloading"
T.mission.scout.vehicle.leg = "outbound"
T.mission.scout.phase = "fallback_unloading"
T.mission.scout.returnRequested = nil
for index, member in ipairs(T.team) do
    member.actor.car, member.actor.seat = T.cars[1], index - 1
    T.cars[1].occupied[index - 1] = member.actor
end
T.exitBlocked = 1
check(Car.pulse(T.mission, 80000) and
    T.mission.scout.vehicle.state == "fallback_unloading"
        and T.mission.scout.vehicle.blocker == "exit_blocked"
        and T.team[2].actor.car == T.cars[1],
    "a blocked passenger exit prevents walking fallback")
T.exitBlocked = nil
check(Car.pulse(T.mission, 81000) and
    T.mission.scout.vehicle.state == "abandoned"
        and T.team[1].actor.car == nil
        and T.team[2].actor.car == nil
        and T.mission.scout.phase == "outbound",
    "walking fallback starts only after the whole team exits")

local function freshTrip(state, leg)
    local trip = Car.copyDescriptor(descriptor, T.team, "leader")
    trip.state, trip.leg = state, leg or "outbound"
    T.mission.scout.vehicle = trip
    T.mission.scout.phase = state
    T.mission.scout.search = { request = { category = "scavenge" } }
    T.mission.scout.search.endReason = nil
    T.mission.scout.returnRequested = nil
    return trip
end

local nearRoadFailure = freshTrip("driving_home", "home")
T.cars[1].x, T.cars[1].y = 89, 102
T.driveStatus = { result = "failed", reason = "route_blocked",
    roadGoal = { x = 90, y = 102, z = 0 } }
check(Car.pulse(T.mission, 81000)
        and nearRoadFailure.state == "parking_home"
        and nearRoadFailure.parkingRecovery == true,
    "a stationary failed home drive near the saved road entry tries parking")
local approachesAtRoad = T.approaches
check(Car.pulse(T.mission, 82000)
        and T.approaches == approachesAtRoad + 1
        and nearRoadFailure.parkingRecovery == nil,
    "near-road recovery starts one checked parking segment")
local farRoadFailure = freshTrip("driving_home", "home")
T.cars[1].x = 50
T.driveStatus = { result = "failed", reason = "route_blocked" }
check(Car.pulse(T.mission, 83000)
        and farRoadFailure.state == "fallback_unloading",
    "a failed drive far from the verified road entry uses safe walking fallback")
T.cars[1].x, T.cars[1].y = 102, 102
T.driveStatus = nil

local early = freshTrip("boarding_out")
check(Car.requestReturn(T.mission, 82000, "radio_return")
    and early.leg == "home" and early.state == "boarding_rollback"
    and T.mission.scout.search.endReason == "radio_return",
    "recall before boarding preserves return intent and Search reason")
check(Car.pulse(T.mission, 83000) and early.state == "abandoned"
    and T.mission.scout.phase == "inbound",
    "pre-departure recall returns on foot instead of resuming outbound")

local deadline = freshTrip("walking_to_car")
T.mission.scout.turnHomeAtHour = 10
check(Car.pulse(T.mission, 84000, 11)
    and deadline.leg == "home"
    and T.mission.scout.search.endReason == "return_time_reached",
    "scheduled recall records its actual early Search reason")
T.mission.scout.turnHomeAtHour = nil

local deferred = freshTrip("boarding_out")
for index, member in ipairs(T.team) do
    member.actor.car, member.actor.seat = T.cars[1], index - 1
    T.cars[1].occupied[index - 1] = member.actor
end
T.deferDrive = true
check(Car.pulse(T.mission, 85000) and deferred.state == "boarding_out"
    and deferred.blocker == "deferred:urgent_action_pending",
    "temporary supervisor deferral keeps the team aboard")
check(Car.pulse(T.mission, 86000) and deferred.state == "driving_out",
    "deferred car drive retries successfully")
local expiredDeferral = freshTrip("boarding_out")
expiredDeferral.boardStartedAt = 1000
T.deferDrive = true
check(Car.pulse(T.mission, 125000)
    and expiredDeferral.state == "boarding_rollback"
    and expiredDeferral.blocker == "drive_deferred_deadline",
    "persistent drive deferral eventually follows the bounded fallback")

local deadDriver = freshTrip("driving_out")
local previousDead = T.team[1].actor.isDead
T.team[1].actor.isDead = function() return true end
T.stopPending = true
check(select(2, Car.recoverDeadDriver(T.mission)) == "drive_stop_pending"
    and deadDriver.state == "driving_out",
    "failed native stop is retried before handoff")
T.exitBlocked = 1
local recovered, recoveryReason = Car.recoverDeadDriver(T.mission)
check(recovered == false and recoveryReason == "exit_blocked"
    and deadDriver.state == "driving_out",
    "surviving passenger waits for a safe exit: " .. tostring(recoveryReason))
T.exitBlocked = nil
check(Car.recoverDeadDriver(T.mission) == true
    and deadDriver.state == "abandoned"
    and T.team[2].actor.car == nil
    and T.mission.scout.phase == "outbound",
    "dead driver leaves the living passenger on foot for leader handoff")
T.team[1].actor.isDead = previousDead

local alreadyAbandoned = freshTrip("abandoned")
check(Car.recoverDeadDriver(T.mission) == true
    and alreadyAbandoned.state == "abandoned",
    "former driver death on a walking trip does not hold the lifecycle")
local parked = freshTrip("parked_at_site")
T.mission.scout.phase = "searching"
T.team[1].actor.isDead = function() return true end
check(Car.recoverDeadDriver(T.mission) == true
    and parked.state == "abandoned"
    and T.mission.scout.phase == "searching",
    "death after unloading preserves a walking Search phase for handoff")
T.team[1].actor.isDead = previousDead
local allDead = freshTrip("driving_out")
T.team[1].actor.isDead = function() return true end
local mateDead = T.team[2].actor.isDead
T.team[2].actor.isDead = function() return true end
check(Car.recoverDeadDriver(T.mission) == true
    and allDead.state == "abandoned",
    "all-dead car trip advances to the ordinary corpse teardown")
T.team[1].actor.isDead = previousDead
T.team[2].actor.isDead = mateDead

local longDriveway = freshTrip("parking_home", "home")
T.cars[1].x, T.cars[1].y = 86, 102
T.driveStatus = { result = "arrived",
    roadGoal = { x = 90, y = 102, z = 0 } }
local roadApproaches = T.approaches
check(Car.pulse(T.mission, 180000)
    and longDriveway.approachStage == "road"
    and T.approaches == roadApproaches + 1,
    "early road stop centers at the road attachment before a long driveway")
T.cars[1].x = 90
T.driveStatus = { result = "arrived",
    roadGoal = { x = 90, y = 102, z = 0 } }
check(Car.pulse(T.mission, 181000)
    and longDriveway.approachStage == nil
    and longDriveway.approachStartedAt == nil,
    "verified road centering releases the final parking stage")
check(Car.pulse(T.mission, 182000)
    and longDriveway.approachStage == "bay"
    and T.approaches == roadApproaches + 2,
    "the checked driveway approach starts from the actual road end")
T.driveStatus = nil

local extendedDriveway = freshTrip("parking_home", "home")
T.cars[1].x, T.cars[1].y = 54, 102
for index, expectedX in ipairs({ 66, 78, 90, 102 }) do
    T.driveStatus = { result = "arrived",
        roadGoal = { x = 54, y = 102, z = 0 } }
    local pulsed = Car.pulse(T.mission, 183000 + index * 2000)
    check(pulsed and T.approachGoal
            and math.abs(T.approachGoal.x - expectedX) < 0.01
            and extendedDriveway.approachStage == (index == 4 and "bay" or "driveway"),
        "long home driveway advances one checked parking segment at a time: "
            .. tostring(index) .. " stage=" .. tostring(extendedDriveway.approachStage)
            .. " goal=" .. tostring(T.approachGoal and T.approachGoal.x)
            .. " blocker=" .. tostring(extendedDriveway.blocker))
    T.cars[1].x = expectedX
    T.driveStatus = { result = "arrived",
        roadGoal = { x = 54, y = 102, z = 0 } }
    Car.pulse(T.mission, 184000 + index * 2000)
end
check(extendedDriveway.state == "unloading_home",
    "the segmented driveway reaches the marked bay without an endless road approach")
T.driveStatus = nil

local recoveringParking = freshTrip("held", "home")
recoveringParking.resumeState = "parking_home"
recoveringParking.blocker = "road_access_blocked"
T.cars[1].x = 96
T.accessBlocked = true
check(Car.pulse(T.mission, 190000)
    and recoveringParking.state == "parking_home",
    "held parking retries its original state during the grace period")
T.accessBlocked = nil
local approachesBeforeRecovery = T.approaches
check(Car.pulse(T.mission, 191000)
    and recoveringParking.state == "parking_home"
    and T.approaches == approachesBeforeRecovery + 1,
    "cleared parking access can resume its car approach")

local blockedParking = freshTrip("held", "home")
blockedParking.resumeState = "parking_home"
blockedParking.blocker = "road_access_blocked"
for index, member in ipairs(T.team) do
    member.actor.car, member.actor.seat = T.cars[1], index - 1
    T.cars[1].occupied[index - 1] = member.actor
end
T.accessBlocked = true
check(Car.pulse(T.mission, 200000)
    and blockedParking.state == "parking_home"
    and Car.pulse(T.mission, 201000)
    and blockedParking.state == "held",
    "persistent parking obstruction is rechecked during its grace period")
check(Car.pulse(T.mission, 216000)
    and blockedParking.state == "fallback_unloading",
    "a persistent parking hold enters the verified walking fallback")
T.accessBlocked = nil
T.exitBlocked = 1
check(Car.pulse(T.mission, 217000)
    and blockedParking.state == "fallback_unloading"
    and T.team[2].actor.car == T.cars[1],
    "fallback does not walk through a blocked passenger door")
T.exitBlocked = nil
check(Car.pulse(T.mission, 218000)
    and blockedParking.state == "abandoned"
    and T.mission.scout.phase == "inbound",
    "crew exits the blocked car and continues home on foot")
T.cars[1].x = 102

local missingDuringDrive = freshTrip("driving_out")
for index, member in ipairs(T.team) do
    member.actor.car, member.actor.seat = T.cars[1], index - 1
    T.cars[1].occupied[index - 1] = member.actor
end
local unloadedCar = T.cars[1]
T.cars = {}
check(Car.pulse(T.mission, 220000)
    and Car.pulse(T.mission, 251000)
    and missingDuringDrive.state == "held"
    and missingDuringDrive.blocker == "car_not_loaded",
    "a missing car stops an active trip with a visible blocker")
check(Car.pulse(T.mission, 252000)
    and Car.pulse(T.mission, 268000)
    and missingDuringDrive.state == "held",
    "seated crew never abandons an unloaded vehicle")
T.cars = { unloadedCar }
check(Car.pulse(T.mission, 269000)
    and missingDuringDrive.state == "fallback_unloading"
    and Car.pulse(T.mission, 270000)
    and missingDuringDrive.state == "abandoned",
    "a returned car lets an interrupted crew exit and walk")

local missingOnFoot = freshTrip("returning_to_car", "home")
T.cars = {}
check(Car.pulse(T.mission, 280000)
    and Car.pulse(T.mission, 311000)
    and Car.pulse(T.mission, 312000)
    and Car.pulse(T.mission, 328000)
    and missingOnFoot.state == "abandoned"
    and T.mission.scout.phase == "inbound",
    "on-foot crew walks home when its parked car is gone")

local missingAfterLoad = freshTrip("interrupted_by_load", "home")
check(Car.pulse(T.mission, 340000)
    and Car.pulse(T.mission, 371000)
    and missingAfterLoad.state == "held",
    "restored trip waits for a late car load")
check(Car.pulse(T.mission, 372000)
    and Car.pulse(T.mission, 433000)
    and missingAfterLoad.state == "abandoned"
    and T.mission.scout.phase == "inbound",
    "restored crew continues home on foot if the car never loads")
local incompleteRoster = freshTrip("held", "home")
incompleteRoster.resumeState = "returning_to_car"
incompleteRoster.blocker = "car_not_loaded"
local missingMate = T.team[2].actor
T.team[2].actor = nil
check(Car.pulse(T.mission, 440000)
    and Car.pulse(T.mission, 456000)
    and incompleteRoster.state == "held",
    "missing roster member prevents an unverified walking fallback")
T.team[2].actor = missingMate
check(Car.pulse(T.mission, 457000)
    and incompleteRoster.state == "abandoned",
    "walking fallback resumes after the full roster is present")
T.cars = { unloadedCar }

local occupiedBay = freshTrip("held", "home")
occupiedBay.resumeState = "parking_home"
occupiedBay.blocker = "parking_bay_occupied"
check(Car.pulse(T.mission, 458000) and occupiedBay.state == "parking_home",
    "temporarily occupied parking footprint receives the bounded retry")

local recalledUnload = freshTrip("unloading_site")
for index, member in ipairs(T.team) do
    member.actor.car, member.actor.seat = T.cars[1], index - 1
    T.cars[1].occupied[index - 1] = member.actor
end
check(Car.requestReturn(T.mission, 459000, "radio_return")
    and T.mission.scout.returnRequested == true,
    "accepted unload-time recall is retained at mission level")
local originalDead = T.team[1].actor.isDead
T.team[1].actor.isDead = function() return true end
check(Car.recoverDeadDriver(T.mission) == true
    and recalledUnload.state == "abandoned"
    and T.mission.scout.phase == "inbound",
    "driver casualty during recalled unload sends living passenger home")
T.team[1].actor.isDead = originalDead
T.team[1].actor.car, T.team[2].actor.car = nil, nil
T.cars[1].occupied = {}

local casualty = T.team[2].actor
T.team[2].actor = nil
T.mission.members[casualty] = nil
T.mission.survivors = { leader = true }
local survivingDriver = freshTrip("interrupted_by_load", "home")
survivingDriver.position = { x = T.cars[1].x, y = T.cars[1].y, z = 0 }
check(Car.pulse(T.mission, 460000)
    and survivingDriver.state == "boarding_home",
    "reload reboards a surviving driver without waiting for a saved casualty")
local missingWithCasualty = freshTrip("interrupted_by_load", "home")
T.cars = {}
check(Car.pulse(T.mission, 461000)
    and Car.pulse(T.mission, 492000)
    and Car.pulse(T.mission, 493000)
    and Car.pulse(T.mission, 554000)
    and missingWithCasualty.state == "abandoned"
    and T.mission.scout.phase == "inbound",
    "missing car falls back on foot once every saved survivor is present")
local missingLiving = freshTrip("interrupted_by_load", "home")
T.mission.survivors = { leader = true, mate = true }
check(Car.pulse(T.mission, 555000)
    and Car.pulse(T.mission, 586000)
    and Car.pulse(T.mission, 587000)
    and Car.pulse(T.mission, 648000)
    and missingLiving.state == "held",
    "a genuinely missing living passenger still blocks walking fallback")
T.team[2].actor = casualty
T.mission.members[casualty] = true
T.mission.survivors = nil
T.cars = { unloadedCar }

do
    local car = T.cars[1]
    local function seatedTrip(state, leg)
        local trip = freshTrip(state, leg)
        car.occupied, car.engine, car.starting = {}, true, false
        for index, member in ipairs(T.team) do
            member.actor.car, member.actor.seat = car, index - 1
            car.occupied[index - 1] = member.actor
        end
        return trip
    end
    local unrelated = T.car(99, 108, 108)
    unrelated.engine = true
    T.cars[2] = unrelated
    for index, state in ipairs({ "unloading_site", "unloading_home",
        "fallback_unloading", "boarding_rollback" }) do
        local trip = seatedTrip(state, state == "unloading_site" and "outbound" or "home")
        local stops = car.engineStops or 0
        check(Car.pulse(T.mission, 700000 + index * 10000)
                and car.engine == false and car.engineStops == stops + 1
                and T.team[1].actor.car == nil and T.team[2].actor.car == nil,
            state .. " switches off the exact expedition car before any member exits")
        check(trip.state == (state == "unloading_site" and "parked_at_site"
                or state == "unloading_home" and "home_wait" or "abandoned"),
            state .. " completes only after verified engine shutdown and exits")
    end
    check(unrelated.engine and not unrelated.engineStops,
        "unloading never shuts off another parked car")
    T.cars[2] = nil

    local delayed = seatedTrip("unloading_home", "home")
    car.stopDelayed = true
    local stops = car.engineStops or 0
    check(Car.pulse(T.mission, 750000) and delayed.state == "unloading_home"
            and delayed.blocker == "engine_shutdown_pending"
            and car.engineStops == stops + 1 and T.team[1].actor.car == car
            and T.team[2].actor.car == car,
        "a shutdown request that has not taken effect retains the whole seated crew")
    check(Car.pulse(T.mission, 750500) and car.engineStops == stops + 1,
        "engine shutdown does not repeat every frame while waiting")
    car.occupied[2] = { id = "player" }
    check(Car.pulse(T.mission, 753000) and car.engineStops == stops + 1
            and car.engine and delayed.state == "unloading_home",
        "a player boarding during shutdown revokes further engine-control authority")
    car.occupied[2] = nil
    car.engine, car.stopDelayed = false, nil
    check(Car.pulse(T.mission, 754000) and delayed.state == "home_wait"
            and car.engineStops == stops + 1,
        "an observed eventual shutdown completes unloading without another effect")

    local starting = seatedTrip("boarding_rollback", "home")
    car.engine, car.starting = false, true
    stops = car.engineStops or 0
    check(Car.pulse(T.mission, 760000) and starting.state == "abandoned"
            and car.starting == false and car.engineStops == stops + 1,
        "a starting engine is switched off even though isEngineRunning is false")

    local failed = seatedTrip("fallback_unloading", "home")
    car.stopError = true
    stops = car.engineStops or 0
    for index = 1, 3 do Car.pulse(T.mission, 770000 + index * 2000) end
    check(Car.pulse(T.mission, 790000) and car.engineStops == stops + 3
            and failed.state == "fallback_unloading"
            and failed.blocker == "engine_shutdown_failed"
            and T.team[1].actor.car == car and T.team[2].actor.car == car,
        "failed native shutdown has three spaced attempts and cannot falsely finish or burst forever")
    car.engine, car.stopError = false, nil
    check(Car.pulse(T.mission, 791000) and failed.state == "abandoned",
        "external engine recovery unblocks a retained failed unload")

    local unreadable = seatedTrip("unloading_home", "home")
    local engineProbe = car.isEngineRunning
    car.isEngineRunning = function() return nil end
    stops = car.engineStops or 0
    check(Car.pulse(T.mission, 800000) and unreadable.state == "unloading_home"
            and unreadable.blocker == "engine_state_unreadable"
            and (car.engineStops or 0) == stops and T.team[1].actor.car == car,
        "unreadable engine state fails closed without calling shutdown or exiting")
    car.isEngineRunning = engineProbe
    T.ready = false
    check(Car.pulse(T.mission, 801000) and (car.engineStops or 0) == stops
            and T.team[1].actor.car == car,
        "a moving car is never switched off as part of unloading")
    T.ready = true
    local playerDriver = { id = "player-driver" }
    car.occupied[0] = playerDriver
    check(Car.pulse(T.mission, 802000) and car.engine
            and (car.engineStops or 0) == stops,
        "a replacement driver prevents shutdown of a car no longer owned by the crew")
    car.occupied[0] = T.team[1].actor
    Car.pulse(T.mission, 803000)

    local wrongIdentity = seatedTrip("unloading_home", "home")
    local loader = SC.Vehicle.loadedBySqlId
    SC.Vehicle.loadedBySqlId = function() return unrelated end
    check(Car.pulse(T.mission, 804000) and wrongIdentity.state == "unloading_home"
            and wrongIdentity.blocker == "car_identity_changed"
            and unrelated.engine and not unrelated.engineStops,
        "a resolver returning the wrong vehicle identity cannot stop that vehicle")
    SC.Vehicle.loadedBySqlId = loader
    Car.pulse(T.mission, 805000)

    local failedRoad = seatedTrip("driving_home", "home")
    car.x, car.y = 160, 160
    local nativeStatus = SC.Driving.status
    SC.Driving.status = function() return { obstacleKind = "solid" } end
    T.driveStatus = { result = "failed", reason = "route_blocked", attempts = 3 }
    check(Car.pulse(T.mission, 806000) and failedRoad.lastFailure.reason == "route_blocked"
        and failedRoad.lastFailure.obstacle == "solid" and failedRoad.lastFailure.at.x == 160,
        "a failed native home drive retains the original reason, obstacle and physical position")
    T.driveStatus = nil
    check(Car.pulse(T.mission, 807000) and failedRoad.state == "abandoned",
        "failed drive cleanup still switches off and leaves the actual blocked car")
    local retainedFailure = Car.copyDescriptor(failedRoad, T.team, "leader")
    check(retainedFailure and retainedFailure.lastFailure.reason == "route_blocked"
        and retainedFailure.lastFailure.obstacle == "solid",
        "precise drive failure survives abandonment and stable descriptor export")
    retainedFailure.lastFailure.at.x = 0
    check(failedRoad.lastFailure.at.x == 160, "saved failure coordinates cannot alias the live trip")
    SC.Driving.status = nativeStatus
    car.x, car.y = 102, 102

    local dead = seatedTrip("driving_home", "home")
    local aliveDriver, alivePassenger = T.team[1].actor.isDead, T.team[2].actor.isDead
    T.team[1].actor.isDead = function() return true end
    check(Car.recoverDeadDriver(T.mission) and dead.state == "abandoned"
            and car.engine == false and T.team[2].actor.car == nil,
        "dead-driver recovery switches off the owned car before its living passenger exits")
    local allDeadTrip = seatedTrip("driving_out")
    T.team[2].actor.isDead = function() return true end
    check(Car.recoverDeadDriver(T.mission) and allDeadTrip.state == "abandoned"
            and car.engine == false,
        "all-dead trip cleanup still switches off its own unattended car")
    T.team[1].actor.isDead, T.team[2].actor.isDead = aliveDriver, alivePassenger
    for _, member in ipairs(T.team) do member.actor.car, member.actor.seat = nil, nil end
    car.occupied = {}
end
print("EXPEDITION_CAR_PASS checks=" .. checks)
