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
T.cars[#T.cars + 1] = T.car(45, 300, 300)
check(#Car.candidates(T.zone) == 1, "off-zone car is not offered")

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
T.entryX = 200
check(select(2, Car.preflight(T.team, T.zone.id, 44, destination))
    == "road_access_too_far", "long driveway connector refuses dispatch")
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
    home = { x = 103, y = 102, z = 0 },
    siteStop = { x = 160, y = 105, z = 0 },
    position = { x = 105, y = 102, z = 0 },
    departureFuel = 10,
    departureHeading = 0,
}
local saved = Car.copyDescriptor(descriptor, T.team, "leader")
check(saved and saved.seats.mate == 1, "stable descriptor copies the seat map")
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
print("EXPEDITION_CAR_PASS checks=" .. checks)
