-- SPDX-License-Identifier: MIT
local SC, T = SurvivorCompanion, SC_UPKEEP_TEST
local Upkeep = SC.VehicleUpkeep
local checks = 0
local function check(value, message)
    checks = checks + 1
    assert(value, "vehicle upkeep check " .. checks .. ": " .. message)
end
local pump = T.item(1, "Base.TirePump")
local clean = T.item(2, "Base.WaterBottle", 8, false)
local tainted = T.item(3, "Base.Bucket", 8, true)
T.storage.container.items = { pump, clean }
T.waterStorage.container.items = { tainted }

T.tires[1].current = 29
T.tires[2].current = 35
check(select(2, Upkeep.eligible("inflate_tires", T.car, false))
    == "tires_at_rated_pressure", "automatic inflation waits until below 80 percent")
check(Upkeep.eligible("inflate_tires", T.car, true) == true,
    "manual inflation accepts any underfilled tire")
T.tires[1].current, T.tires[2].current = 20, 20
local queued, tireJob = Upkeep.queue("inflate_tires", T.car.id, false)
check(queued and tireJob.priority == 2 and #T.base.jobs == 1,
    "automatic tire job is queued once")
check(Upkeep.queue("inflate_tires", T.car.id, true) == true
    and #T.base.jobs == 1 and tireJob.priority == 5,
    "manual request upgrades the existing job")
check(select(2, Upkeep.queue("inflate_tires", T.car.id, false))
    == "upkeep_already_queued", "duplicate job is rejected")
local okay, reason = Upkeep.update(T.actor, {}, tireJob)
check(okay and reason == "upkeep_supply_carried"
    and pump.data.LF_UpkeepJobId == tireJob.id,
    "an exact pump is reserved and carried")
check(Upkeep.releaseAffinity(T.actor, tireJob) == false,
    "another worker cannot claim a carried pump")
okay, reason = Upkeep.update(T.actor, {}, tireJob)
check(okay and reason == "upkeep_action_started"
    and T.native().part == T.tires[1], "first tire uses native action")
T.finish(15)
T.resetNative() -- native action state does not survive reload
okay, reason = Upkeep.update(T.actor, {}, tireJob)
check(okay and reason == "upkeep_progress_verified"
    and T.tires[1].current == 35,
    "saved pressure reading reconciles completed inflation")
Upkeep.update(T.actor, {}, tireJob)
check(T.native() and T.native().part == T.tires[2],
    "same job services the next tire")
T.finish(15)
Upkeep.update(T.actor, {}, tireJob)
Upkeep.update(T.actor, {}, tireJob)
okay, reason, _, done = Upkeep.update(T.actor, {}, tireJob)
check(okay and done and reason == "upkeep_complete"
    and SC.GameplayUtil.inventoryContains(T.storage.container, pump)
    and pump.data.LF_UpkeepJobId == nil,
    "pump is returned after all tires reach rated pressure")

T.base.jobs = {}
T.blood.Front = 0.25
T.storage.reserve = 1 -- protected pump does not affect water selection
local washed, washJob = Upkeep.queue("wash_vehicle", T.car.id, false)
check(washed and washJob.priority == 2,
    "visible blood queues a washing job")
Upkeep.update(T.actor, {}, washJob)
check(T.actor.inventory.items[1] == tainted
    and tainted.data.LF_UpkeepJobId == washJob.id,
    "tainted water is preferred to stored clean drinking water")
check(Upkeep.canContinue(T.actor, T.car, tainted,
    washJob.id, "Engine") == true,
    "exact reserved water is accepted at the wash side")
Upkeep.update(T.actor, {}, washJob)
T.finish(2)
T.resetNative()
okay, reason = Upkeep.update(T.actor, {}, washJob)
check(okay and reason == "upkeep_progress_verified"
    and T.blood.Front < 0.25 and tainted.fluid.amount == 6,
    "partial native wash reconciles blood and water after reload")
check(Upkeep.cancel(T.actor, washJob) == true
    and T.waterStorage.container.items[1] == tainted
    and tainted.data.LF_UpkeepJobId == nil,
    "cancellation returns the partly used water without duplication")

T.car.occupied = true
check(select(2, Upkeep.eligible("wash_vehicle", T.car, true))
    == "car_occupied", "occupied car is excluded")
T.car.occupied = false
T.car.engine = true
check(select(2, Upkeep.eligible("wash_vehicle", T.car, true))
    == "car_engine_on", "running car is excluded")
T.car.engine = false
print("VEHICLE_UPKEEP_PASS checks=" .. tostring(checks))
