-- SPDX-License-Identifier: MIT
-- Focused policy check against the real SCVehicle seat planner.

local SC = SurvivorCompanion
local checks = 0
local function check(name, okay, detail)
    if not okay then error("LORETTA_VEHICLE_FAIL " .. name .. " "
        .. tostring(detail or ""), 2) end
    checks = checks + 1
end

local car = SC_LORETTA_CAR(100, 100, 10)
local player = SC_LORETTA_ACTOR(100, 10)
player.id, player.vehicle = "driver", car
car.occupants[0] = player
local loretta = SC_LORETTA_ACTOR(101, 10)
local group = SC_LORETTA_GROUP(car, loretta)
local lorettaRecord = SC.Registry.byId(loretta.id)
lorettaRecord.recruited = true
loretta.commands = { recruited = true, rideWithPlayer = true,
    order = "follow" }
loretta.health = 100
local other = SC_LORETTA_ACTOR(102, 10)
other.id = "ordinary-follower"
other.commands = { recruited = true, rideWithPlayer = true,
    order = "follow" }
other.health = 20
SC.Registry.records[other.id] = { id = other.id, actor = other,
    recruited = true }
SC.Registry.livingActors = { other, loretta }

local rear, rearReason = SC.Vehicle.preflightBoard(loretta, car, 2)
check("rear_seat_rejected", rear == nil
    and rearReason == "requested vehicle seat is unavailable", rearReason)
local front, frontReason = SC.Vehicle.preflightBoard(loretta, car, 1)
check("front_seat_allowed", front ~= nil and front.seat == 1, frontReason)

local assignedLoretta, lorettaReason = SC.Vehicle.assignmentFor(
    loretta, car, player)
local assignedOther, otherReason = SC.Vehicle.assignmentFor(other, car, player)
check("front_reserved_for_loretta", assignedLoretta ~= nil
    and assignedLoretta.seat == 1, lorettaReason)
check("other_follower_rear", assignedOther ~= nil
    and assignedOther.seat == 2, otherReason)

SC.Vehicle.invalidateManifests(car)
local stranger = SC_LORETTA_ACTOR(100, 10)
car.occupants[1] = stranger
assignedLoretta, lorettaReason = SC.Vehicle.assignmentFor(
    loretta, car, player)
local status = SC.Vehicle.statusFor(loretta, player)
check("occupied_front_waits", assignedLoretta == nil
    and lorettaReason == "vehicle_capacity_wait"
    and status.status == "on_foot" and status.capacityWait == true,
    lorettaReason)
assignedOther, otherReason = SC.Vehicle.assignmentFor(other, car, player)
check("other_follower_can_use_rear", assignedOther ~= nil
    and assignedOther.seat == 2, otherReason)

SC_TEST_REPORT = "LORETTA_VEHICLE_PASS " .. tostring(checks) .. " checks"
