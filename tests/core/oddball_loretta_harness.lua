-- SPDX-License-Identifier: MIT

local SC = SurvivorCompanion
local Loretta = SC.OddballLoretta
local C = SC_LORETTA_CLOCK
local checks = 0

local function check(name, okay, detail)
    if not okay then
        error("LORETTA_FAIL " .. name .. " " .. tostring(detail or ""), 2)
    end
    checks = checks + 1
end

local function scene(sqlId)
    local car = SC_LORETTA_CAR(sqlId, sqlId * 10, 10)
    local actor = SC_LORETTA_ACTOR(car.x, car.y + 1)
    local player = SC_LORETTA_ACTOR(car.x, car.y + 3)
    player.visible = true
    SC_LORETTA_PLAYER = player
    local group = SC_LORETTA_GROUP(car, actor)
    return car, actor, player, group
end

local car, actor, player, group = scene(8)
-- The newly spawned actor occupies her own door tile, so a free-spawn check
-- would reject the native boarding operation.
C.occupiedDoorSquare = SC.GameplayUtil.gridSquare(car.x, car.y + 1, 0)
local spawned, spawnReason = Loretta.onSpawn(group, actor)
C.occupiedDoorSquare = nil
check("native_spawn", spawned == true and C.boards == 1,
    spawnReason)
check("same_rear_seat", SC.Vehicle.isNativeSeated(actor) == true
    and actor.vehicle == car and car:getSeat(actor) == 2)
check("initial_setup", group.oddball.carPrepared == true
    and car.gas == 0 and car.alarmed == true
    and car:getPartById("DoorRearLeft"):getDoor():isLocked() == true)
check("darren_once", group.oddball.darrenSpawned == true
    and C.zombies == 1 and C.lastZombie.outfit == "Student"
    and #C.lastZombie.inv.items == 1
    and C.lastZombie.inv.items[1].fullType == "Base.CarKey")
check("needs_set", actor.stats.thirst >= 0.8
    and actor.stats.hunger >= 0.6)
local sealed, sealedReason = Loretta.zombiesIgnore(actor, group)
check("sealed_gate", sealed == true and actor.immunity == true,
    sealedReason)
check("bridge_owns_sealed_immunity", C.bridgeCalls >= 1
    and C.bridgeHistory[#C.bridgeHistory].actor == actor
    and C.bridgeHistory[#C.bridgeHistory].enabled == true
    and C.cheatCalls == 0)
actor.immunity = false -- engine-side drift after the module cached the gate
local bridgeBefore = C.bridgeCalls
Loretta.pulse(group, player, C.ms + 1)
check("native_immunity_drift_repaired", actor.immunity == true
    and Loretta.zombiesIgnore(actor, group) == true
    and C.bridgeCalls == bridgeBefore + 1 and C.cheatCalls == 0)

local locks = car:getPartById("DoorRearLeft"):getDoor().lockChanges
local keys, zombies, boards = car.keyCreates, C.zombies, C.boards
Loretta.onSpawn(group, actor)
check("setup_once", car.gas == 0 and car.keyCreates == keys
    and C.zombies == zombies and C.boards == boards
    and car:getPartById("DoorRearLeft"):getDoor().lockChanges == locks)

local broken = car:getPartById("WindowRearLeft"):getWindow()
broken.destroyed = true
local ignored = Loretta.zombiesIgnore(actor, group)
check("broken_window_drops_gate", ignored == false)
local exits = C.exits
Loretta.pulse(group, player, C.ms)
check("window_exit_once", C.exits == exits + 1
    and group.oddball.freed == true and group.oddball.freedBy == "window"
    and actor.vehicle == nil and actor.immunity == false
    and C.bridgeHistory[#C.bridgeHistory].actor == actor
    and C.bridgeHistory[#C.bridgeHistory].enabled == false
    and C.cheatCalls == 0)
Loretta.pulse(group, player, C.ms + 100)
check("window_no_repeat_exit", C.exits == exits + 1)

local keyCar, keyActor, keyPlayer, keyGroup = scene(9)
Loretta.onSpawn(keyGroup, keyActor)
local door = keyCar:getPartById("DoorRearLeft"):getDoor()
door.open = true
check("opened_door_drops_gate", Loretta.zombiesIgnore(keyActor, keyGroup) == false)
exits = C.exits
Loretta.pulse(keyGroup, keyPlayer, C.ms + 200)
check("key_exit_once", C.exits == exits + 1
    and keyGroup.oddball.freed == true and keyGroup.oddball.freedBy == "key"
    and keyActor.vehicle == nil and keyCar.alarmCount == 0)
Loretta.pulse(keyGroup, keyPlayer, C.ms + 300)
check("key_no_repeat_exit", C.exits == exits + 1)
check("water_before_recruitment", Loretta.canRecruit(keyGroup) == false
    and Loretta.action(keyGroup, "recruit_now", keyPlayer) == false)
Fluid = { TaintedWater = "tainted" }
local function waterBottle(tainted)
    local item = keyPlayer.inv:AddItem("Base.WaterBottle")
    function item:isWaterSource() return true end
    local fluid = { amount = 1 }
    function fluid:isEmpty() return self.amount <= 0 end
    function fluid:getAmount() return self.amount end
    function fluid:getPrimaryFluid()
        return { getFluidTypeString = function() return "Water" end }
    end
    function fluid:contains() return tainted == true end
    function fluid:adjustAmount(amount) self.amount = amount end
    function item:getFluidContainer() return fluid end
    return item, fluid
end
local taintedItem, taintedFluid = waterBottle(true)
check("tainted_water_rejected",
    Loretta.action(keyGroup, "give_water", keyPlayer) == false
    and keyGroup.oddball.waterReceived ~= true
    and taintedItem.container == keyPlayer.inv
    and taintedFluid.amount == 1)
local cleanItem, cleanFluid = waterBottle(false)
local thirstBefore = keyActor.stats.thirst
local drank, drinkReason = Loretta.action(keyGroup, "give_water", keyPlayer)
check("native_water_handoff_and_one_use", drank == true
    and keyGroup.oddball.waterReceived == true
    and cleanItem.container == keyActor.inv
    and math.abs(cleanFluid.amount - 0.88) < 0.001
    and keyActor.stats.thirst < thirstBefore, drinkReason)
check("recruit_after_water", Loretta.canRecruit(keyGroup) == true)

local gateCar, gateActor, gatePlayer, gateGroup = scene(13)
Loretta.onSpawn(gateGroup, gateActor)
local otherDoor = gateCar:getPartById("DoorFrontLeft"):getDoor()
otherDoor.open = true
check("any_open_door_drops_gate", Loretta.zombiesIgnore(gateActor, gateGroup) == false)
exits = C.exits
Loretta.pulse(gateGroup, gatePlayer, C.ms + 350)
check("other_door_does_not_free", C.exits == exits and gateGroup.oddball.freed ~= true
    and gateActor.immunity == false)
otherDoor.open = false
Loretta.pulse(gateGroup, gatePlayer, C.ms + 360)
check("closed_car_restores_gate", Loretta.zombiesIgnore(gateActor, gateGroup) == true
    and gateActor.immunity == true)
gateCar:getPartById("WindowFrontLeft"):getWindow().destroyed = true
check("any_broken_window_drops_gate",
    Loretta.zombiesIgnore(gateActor, gateGroup) == false)

local timedCar, timedActor, timedPlayer, timedGroup = scene(10)
local clipboard = timedActor.inv:AddItem("Base.Clipboard")
Loretta.onSpawn(timedGroup, timedActor)
C.hour = 300
Loretta.pulse(timedGroup, timedPlayer, C.ms + 400)
check("first_sight_starts_clock", timedGroup.oddball.firstSeenHour == 300)
local deaths = C.deaths
C.hour = 371.9
Loretta.pulse(timedGroup, timedPlayer, C.ms + 500)
check("before_deadline_alive", C.deaths == deaths)
C.hour = 372
Loretta.pulse(timedGroup, timedPlayer, C.ms + 600)
check("deadline_kills_once", C.deaths == deaths + 1
    and timedGroup.oddball.dead == true)
check("death_writes_clipboard", clipboard.name ~= nil
    and clipboard.name:find("Day four", 1, true) ~= nil)
Loretta.pulse(timedGroup, timedPlayer, C.ms + 700)
check("death_not_repeated", C.deaths == deaths + 1)
local notes = C.haloNotes
timedCar:getPartById("DoorRearLeft"):getDoor().open = true
Loretta.pulse(timedGroup, timedPlayer, C.ms + 710)
check("clipboard_shown_once", C.haloNotes == notes + 1
    and timedGroup.oddball.clipboardShown == true)
Loretta.pulse(timedGroup, timedPlayer, C.ms + 720)
check("clipboard_not_repeated", C.haloNotes == notes + 1)

local rescuedCar, rescuedActor, rescuedPlayer, rescuedGroup = scene(11)
C.hour = 400
Loretta.onSpawn(rescuedGroup, rescuedActor)
Loretta.pulse(rescuedGroup, rescuedPlayer, C.ms + 800)
rescuedCar:getPartById("DoorRearLeft"):getDoor().open = true
Loretta.pulse(rescuedGroup, rescuedPlayer, C.ms + 900)
C.hour = 500
deaths = C.deaths
Loretta.pulse(rescuedGroup, rescuedPlayer, C.ms + 1000)
check("freed_timer_cancelled", C.deaths == deaths and rescuedGroup.oddball.dead ~= true)

local actionCar, actionActor, actionPlayer, actionGroup = scene(12)
Loretta.onSpawn(actionGroup, actionActor)
local hasSmash = false
for _, option in ipairs(Loretta.menuOptions(actionGroup, actionPlayer) or {}) do
    if option.id == "break_window" then hasSmash = true end
end
check("nearby_smash_option", hasSmash)
actionPlayer.x = actionPlayer.x + 20
check("distant_smash_rejected",
    Loretta.action(actionGroup, "break_window", actionPlayer) == false)
actionPlayer.x = actionPlayer.x - 20
local queuedBefore = #C.queued
local accepted = Loretta.action(actionGroup, "break_window", actionPlayer)
check("vanilla_smash_queued", accepted == true
    and #C.queued == queuedBefore + 1
    and C.queued[#C.queued].part == actionCar:getPartById("WindowRearLeft"))

local oldCar, streamedActor, streamedPlayer, streamedGroup = scene(14)
Loretta.onSpawn(streamedGroup, streamedActor)
local boardsBefore, spawnsBefore = C.boards, C.zombies
-- The module cached oldCar by SQL id during onSpawn. Simulate a removed
-- vehicle object, then a newly loaded Java object with the same durable id.
oldCar.occupants[2], streamedActor.vehicle = nil, nil
streamedActor.x = streamedActor.x + 30
streamedPlayer.visible = false
C.cars = {}
Loretta.pulse(streamedGroup, streamedPlayer, C.ms + 1100)
check("unloaded_car_does_not_reseat", C.boards == boardsBefore
    and streamedActor.vehicle == nil and streamedActor.immunity == false)
local reloadedCar = SC_LORETTA_CAR(14, oldCar.x, oldCar.y)
reloadedCar.gas = 7
reloadedCar:getPartById("GasTank").container.amount = 7
local recoveriesBefore = C.recoveries
Loretta.pulse(streamedGroup, streamedPlayer, C.ms + 1200)
check("sql_id_reboard", C.boards == boardsBefore + 1
    and C.recoveries == recoveriesBefore + 1
    and streamedActor.vehicle == reloadedCar
    and reloadedCar:getSeat(streamedActor) == 2
    and streamedActor.immunity == true)
check("reload_setup_not_repeated", reloadedCar.gas == 7
    and reloadedCar.alarmed == false and reloadedCar.keyCreates == nil
    and C.zombies == spawnsBefore)

local drivingCar = SC_LORETTA_CAR(15, 150, 10)
drivingCar.occupants[0] = keyPlayer
drivingCar.occupants[1] = keyActor
keyPlayer.vehicle, keyActor.vehicle = drivingCar, drivingCar
drivingCar.speed = 90
local linesBefore = #C.lines
Loretta.pulseRecruited(keyGroup, keyActor, keyPlayer, 100000)
check("speed_remark", #C.lines == linesBefore + 1
    and C.lines[#C.lines]:find("Derby", 1, true) ~= nil)
drivingCar.speed = 20
Loretta.pulseRecruited(keyGroup, keyActor, keyPlayer, 101000)
check("brake_shared_cooldown", #C.lines == linesBefore + 1)
drivingCar.speed = 70
Loretta.pulseRecruited(keyGroup, keyActor, keyPlayer, 191001)
drivingCar.speed = 20
Loretta.pulseRecruited(keyGroup, keyActor, keyPlayer, 192001)
check("brake_remark_after_cooldown", #C.lines == linesBefore + 2
    and C.lines[#C.lines]:find("Gently", 1, true) ~= nil)
drivingCar.speed = 25
C.ms = 192100
local zombie = { x = 151, y = 10, z = 0 }
check("zombie_hit_shared_cooldown",
    Loretta.onZombieDead(keyGroup, zombie, keyPlayer, keyPlayer) == false
    and #C.lines == linesBefore + 2)
C.ms = 283000
check("zombie_hit_remark_after_cooldown",
    Loretta.onZombieDead(keyGroup, zombie, keyPlayer, keyPlayer) == true
    and #C.lines == linesBefore + 3
    and C.lines[#C.lines]:find("Pedestrian", 1, true) ~= nil)

local siteCar = SC_LORETTA_CAR(42, 420, 10)
local observer = SC_LORETTA_ACTOR(420, 22)
observer.visible = false
local site = Loretta.siteFor(observer, false, 1, 55)
check("existing_vehicle_site", site ~= nil and site.vehicle ~= nil
    and site.vehicle.sqlId == 42 and site.vehicle.seat >= 2,
    site and site.vehicle and site.vehicle.sqlId)
SC.Vehicle.isSeatReserved = function(_, seat) return seat == 2 end
check("reserved_car_rejected", Loretta.siteFor(observer, false, 1, 55) == nil)
SC.Vehicle.isSeatReserved = nil
siteCar.speed = 20
check("moving_car_rejected", Loretta.siteFor(observer, false, 1, 55) == nil)
siteCar.speed = 0
siteCar:getPartById("WindowRearLeft"):getWindow().destroyed = true
siteCar:getPartById("WindowRearRight"):getWindow().destroyed = true
check("broken_car_rejected", Loretta.siteFor(observer, false, 1, 55) == nil)

local indexedCar, indexedActor, indexedPlayer, indexedGroup = scene(51)
local indexedObserver = SC_LORETTA_ACTOR(indexedCar.x, indexedCar.y + 12)
indexedObserver.visible = false
C.vehicleListMode = "indexed_only"
local indexedSite = Loretta.siteFor(indexedObserver, false, 1, 55)
check("indexed_vehicle_list_site", indexedSite ~= nil
    and indexedSite.vehicle.sqlId == 51)
local indexedSpawned, indexedReason = Loretta.onSpawn(indexedGroup, indexedActor)
check("indexed_vehicle_list_native_board", indexedSpawned == true
    and indexedActor.vehicle == indexedCar
    and indexedCar:getSeat(indexedActor) == 2, indexedReason)
C.vehicleListMode = nil

local setCar, setActor, setPlayer, setGroup = scene(53)
local setObserver = SC_LORETTA_ACTOR(setCar.x - 10, setCar.y)
setObserver.visible = false
C.vehicleListMode = "set_iterator"
local iteratorSite = Loretta.siteFor(setObserver, false, 1, 20)
check("set_iterator_vehicle_site", iteratorSite ~= nil
    and iteratorSite.vehicle.sqlId == 53)
C.vehicleListMode = "set_unreadable"
local spatialSite
for _ = 1, 8 do
    spatialSite = Loretta.siteFor(setObserver, false, 1, 20)
    if spatialSite then break end
end
check("unreadable_set_spatial_site", spatialSite ~= nil
    and spatialSite.vehicle.sqlId == 53)
local spatialSpawned, spatialReason = Loretta.onSpawn(setGroup, setActor)
check("unreadable_set_sql_reseat", spatialSpawned == true
    and setActor.vehicle == setCar and setCar:getSeat(setActor) == 2,
    spatialReason)
C.vehicleListMode = nil

local hurtCar, hurtActor, hurtPlayer, hurtGroup = scene(52)
Loretta.onSpawn(hurtGroup, hurtActor)
C.profanityEnabled = false
Loretta.action(hurtGroup, "hurt", hurtPlayer)
Loretta.action(hurtGroup, "hurt", hurtPlayer)
check("hurt_radio_edit", hurtActor.lastLine ==
    "You ought to be ashamed. Get away from my car.")
C.profanityEnabled = true
Loretta.action(hurtGroup, "hurt", hurtPlayer)
check("hurt_profanity_enabled", hurtActor.lastLine ==
    "Damn you. Get away from my car.")
C.profanityEnabled = nil

local outdoorCar = SC_LORETTA_CAR(54, 540, 10)
local outdoorObserver = SC_LORETTA_ACTOR(540, 22)
outdoorObserver.visible = false
local outdoorSite = Loretta.siteFor(outdoorObserver, false, 1, 20)
check("outdoor_car_baseline", outdoorSite ~= nil
    and outdoorSite.vehicle.sqlId == 54)
C.indoorSquares = { ["540:10:0"] = true }
check("indoor_car_anchor_rejected",
    Loretta.siteFor(outdoorObserver, false, 1, 20) == nil)
C.indoorSquares = {}
for dx = -4, 4 do
    for dy = -4, 4 do
        if dx ~= 0 or dy ~= 0 then
            C.indoorSquares[tostring(540 + dx) .. ":"
                .. tostring(10 + dy) .. ":0"] = true
        end
    end
end
C.occupiedDoorSquare = SC.GameplayUtil.gridSquare(540, 10, 0)
check("indoor_rear_door_tile_rejected",
    Loretta.siteFor(outdoorObserver, false, 1, 20) == nil)
C.occupiedDoorSquare, C.indoorSquares = nil, nil

SC_TEST_REPORT = "LORETTA_PASS " .. tostring(checks) .. " checks"
