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

T.base.jobs = {}
tainted.fluid.amount = 0
local cleanBefore = clean.fluid.amount
local emptyBucket = T.item(4, "Base.BucketEmpty", 0, false)
T.waterStorage.container.items = { emptyBucket }
local sinkQueued, sinkJob = Upkeep.queue("wash_vehicle", T.car.id, false)
check(sinkQueued and sinkJob.target.sourceStorageId == nil,
    "an empty vessel and sink allow a wash without stored tainted water")
Upkeep.update(T.actor, {}, sinkJob)
check(T.actor.inventory.items[1] == emptyBucket
    and sinkJob.target.sourceKind == "sink"
    and clean.fluid.amount == cleanBefore,
    "clean drinking water stays in storage while an empty bucket is borrowed")
local fillStarted, fillReason = Upkeep.update(T.actor, {}, sinkJob)
check(fillStarted and fillReason == "wash_sink_fill_started"
    and T.native().kind == "wash_vehicle_fill"
    and Upkeep.canFill(T.actor, emptyBucket, T.sink, sinkJob.id),
    "the borrowed bucket is filled at the clean sink through a native action")
T.finishFill(8)
T.resetNative()
local filled, filledReason = Upkeep.update(T.actor, {}, sinkJob)
check(filled and filledReason == "wash_sink_filled"
    and sinkJob.target.sinkFilled and emptyBucket.fluid.amount == 8
    and T.sink.amount == 2,
    "a completed sink fill is verified before washing")
local washStarted = Upkeep.update(T.actor, {}, sinkJob)
check(washStarted and T.native().kind == "wash_vehicle"
    and Upkeep.canContinue(T.actor, T.car, emptyBucket,
        sinkJob.id, "Engine"),
    "sink-filled bucket can wash a parked car")
T.finish(2)
T.resetNative()
Upkeep.update(T.actor, {}, sinkJob)
check(clean.fluid.amount == cleanBefore and T.sink.amount == 2
    and emptyBucket.fluid.amount == 6,
    "vehicle wash spends sink water but no clean drinking container")
check(Upkeep.cancel(T.actor, sinkJob) == true
    and T.waterStorage.container.items[1] == emptyBucket,
    "the partly used bucket returns to its marked storage")
T.base.jobs = {}
T.blood.Front = 0.25
emptyBucket.fluid.amount = 0
local _, movedZone = Upkeep.queue("wash_vehicle", T.car.id, true)
T.waterStorage.container.items = {}
T.actor.inventory.items = { emptyBucket }
emptyBucket.fluid.amount = 8
emptyBucket.data.LF_UpkeepJobId = movedZone.id
movedZone.target.stage = "carrying"
movedZone.target.sourceStorageId = T.waterStorage.id
movedZone.target.sourceKind = "sink"
movedZone.target.sinkFilled = true
movedZone.target.itemId = emptyBucket:getID()
movedZone.target.zoneId = "old-parking-zone"
okay, reason = Upkeep.update(T.actor, {}, movedZone)
check(okay and reason == "upkeep_returning_supply"
    and movedZone.target.stage == "returning"
    and emptyBucket.fluid.amount == 8,
    "a moved parking zone returns a full bucket without seeking another fill")
check(Upkeep.cancel(T.actor, movedZone) == true,
    "moved-zone wash releases its bucket receipt")
T.base.jobs = {}
T.blood.Front = 0.25
check(select(2, Upkeep.queue("wash_vehicle", T.car.id, false))
    == "base_wash_water_missing",
    "filled clean containers alone never supply a car wash")

-- A pump still marked by a job that no longer exists is free to borrow.
T.base.jobs = {}
T.tires[1].current = 20
T.storage.reserve = 0
T.storage.container.items = { pump }
T.actor.inventory.items = {}
pump.data.LF_UpkeepJobId = "job:gone"
local staleQueued, staleJob = Upkeep.queue("inflate_tires", T.car.id, true)
check(staleQueued == true, "an upkeep job queues: " .. tostring(staleJob))
okay, reason = Upkeep.update(T.actor, {}, staleJob)
check(okay and reason == "upkeep_supply_carried"
    and pump.data.LF_UpkeepJobId == staleJob.id,
    "a stale upkeep marker no longer hides the camp's tire pump")
T.actor.inventory.items = {}
okay, reason = Upkeep.update(T.actor, {}, staleJob)
check(okay and reason == "upkeep_supply_lost" and staleJob.target.stage == nil,
    "a pump taken from the worker drops the receipt instead of blocking it")

-- A worker who dies carrying the supply leaves the registry; a dormant one does not.
local registered = { worker = true }
SC.Registry = { byId = function(id) return registered[id] and {} or nil end }
staleJob.target.stage, staleJob.target.sourceStorageId = "carrying", T.storage.id
staleJob.target.itemId, staleJob.assignedId, staleJob.reservedBy = 99, "worker", "worker"
check(Upkeep.cancel(nil, staleJob) == false
    and Upkeep.releaseAffinity(nil, staleJob) == false,
    "an unloaded worker keeps its upkeep receipt")
staleJob.assignedId, staleJob.reservedBy = "ghost", "ghost"
check(Upkeep.releaseAffinity(nil, staleJob) == true
    and staleJob.assignedId == nil and staleJob.target.stage == nil,
    "a dead worker's upkeep receipt is released for another resident")
SC.Registry = nil

local savedContainer = T.storage.container
T.storage.container = nil
staleJob.target.stage, staleJob.target.sourceStorageId = "carrying", T.storage.id
staleJob.target.itemId, staleJob.assignedId = pump:getID(), "worker"
pump.data.LF_UpkeepJobId = staleJob.id
T.actor.inventory.items = { pump }
T.actor.dead = true
local retired, retiredReason = Upkeep.cancel(T.actor, staleJob)
check(retired and retiredReason == "upkeep_worker_retired"
    and staleJob.target.stage == nil and staleJob.assignedId == nil
    and T.actor.inventory.items[1] == pump
    and pump.data.LF_UpkeepJobId == nil,
    "dead upkeep worker releases its pump receipt with storage unloaded")
T.actor.dead, T.storage.container = false, savedContainer

-- Cancelling an older chore must not stop the worker's action for a newer one.
T.base.jobs = {}
T.resetNative()
T.actor.inventory.items = {}
T.storage.container.items = { pump }
pump.data.LF_UpkeepJobId = nil
T.tires[1].current = 20
local _, older = Upkeep.queue("inflate_tires", T.car.id, true)
okay, reason = Upkeep.update(T.actor, {}, older)
check(okay and reason == "upkeep_supply_carried", "the older tire job holds the pump")
T.blood.Front = 0.25
local bucket = T.item(5, "Base.Bucket", 8, true)
T.waterStorage.container.items = { bucket }
local _, newer = Upkeep.queue("wash_vehicle", T.car.id, true)
Upkeep.update(T.actor, {}, newer)
Upkeep.update(T.actor, {}, newer)
check(T.native() and T.native().kind == "wash_vehicle" and T.native().active,
    "the newer wash owns the worker's native action")
check(Upkeep.cancel(T.actor, older) == true and T.native() and T.native().active
        and SC.GameplayUtil.inventoryContains(T.storage.container, pump),
    "cancelling the older tire job returns its pump without stopping the newer wash")
T.resetNative()

-- A tire reading that does not add up ends the job with the pump home.
T.base.jobs = {}
T.blood.Front = 0
T.actor.inventory.items = {}
T.storage.container.items = { pump }
pump.data.LF_UpkeepJobId = nil
T.tires[1].current, T.tires[2].current = 20, 35
local _, odd = Upkeep.queue("inflate_tires", T.car.id, true)
Upkeep.update(T.actor, {}, odd)
okay, reason = Upkeep.update(T.actor, {}, odd)
check(okay and reason == "upkeep_action_started", "the tire action starts")
T.resetNative()
T.tires[1].current = 10 -- pressure fell during the action: cannot be ours
local terminal
okay, reason, terminal = Upkeep.update(T.actor, {}, odd)
check(okay and not terminal and reason == "upkeep_returning_supply"
        and odd.target.stage == "returning"
        and odd.target.finishReason == "tire_pressure_uncertain",
    "an uncertain tire reading takes the pump home instead of retrying hourly")
local finished
okay, reason, _, finished = Upkeep.update(T.actor, {}, odd)
check(okay and finished and reason == "tire_pressure_uncertain"
        and SC.GameplayUtil.inventoryContains(T.storage.container, pump)
        and pump.data.LF_UpkeepJobId == nil,
    "the job ends, reporting the uncertain reading, once the pump is home")

T.car.occupied = true
check(select(2, Upkeep.eligible("wash_vehicle", T.car, true))
    == "car_occupied", "occupied car is excluded")
T.car.occupied = false
T.car.engine = true
check(select(2, Upkeep.eligible("wash_vehicle", T.car, true))
    == "car_engine_on", "running car is excluded")
T.car.engine = false

-- A large camp may have many taps. All valid sinks must reach the route
-- chooser; eight inaccessible sinks must not hide a later usable one.
local oldGrid, oldChoice, oldZones = SC.GameplayUtil.gridSquare,
    SC.Navigation.selectInteraction, T.base.zones
local sinkTiles = {}
for x = 10, 18 do
    local tile = { x = x, y = 10, z = 0, objects = {} }
    local source = { square = tile, amount = 10 }
    function source:getSquare() return self.square end
    function source:isWaterSource() return true end
    function source:getFluidAmount() return self.amount end
    function source:isTaintedWater() return false end
    tile.objects[1], sinkTiles[x] = source, tile
end
T.base.zones = { { kind = "area", x1 = 10, x2 = 18, y1 = 10, y2 = 10, z = 0 } }
SC.GameplayUtil.gridSquare = function(x, y, z)
    if y == 10 and z == 0 and sinkTiles[x] then return sinkTiles[x] end
    return oldGrid(x, y, z)
end
local sinkChoices = 0
SC.Navigation.selectInteraction = function(_, _, key, choices)
    if key == "vehicle_wash_sink" then
        sinkChoices = #choices
        return choices[#choices]
    end
    return choices[1]
end
SC_REFUEL_TEST.clock(SC_REFUEL_TEST.clock() + 30001) -- expire the earlier scan
T.base.jobs, T.actor.inventory.items = {}, {}
T.blood.Front, emptyBucket.fluid.amount = 0.25, 0
T.waterStorage.container.items = { emptyBucket }
local manyQueued, manyWash = Upkeep.queue("wash_vehicle", T.car.id, true)
check(manyQueued == true, "wash can queue with nine camp sinks")
Upkeep.update(T.actor, {}, manyWash)
check(sinkChoices == 9 and manyWash.target.sourceKind == "sink",
    "wash scans beyond eight sinks before choosing an accessible water source")
Upkeep.cancel(T.actor, manyWash)
SC.GameplayUtil.gridSquare, SC.Navigation.selectInteraction, T.base.zones =
    oldGrid, oldChoice, oldZones
print("VEHICLE_UPKEEP_PASS checks=" .. tostring(checks))
