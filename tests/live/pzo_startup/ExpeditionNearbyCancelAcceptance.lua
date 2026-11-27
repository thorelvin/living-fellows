-- SPDX-License-Identifier: MIT
-- Real inventories, car and joined view in a disposable save. The local
-- parking and destination descriptor stands in for the reported itinerary.
require "ISUI/ISContextMenu"

local SC = LivingFellows
local state = { phase = "menu", notes = {}, modals = {} }

local function write(name, value)
    local file = assert(getFileWriter("pzo-expedition-cancel-" .. name .. ".txt", true, false))
    file:write(value .. "\n")
    file:close()
end

local function note(key, value)
    state.notes[#state.notes + 1] = key .. "=" .. tostring(value)
end

local function phase(name)
    state.phase, state.at = name, getTimestampMs()
    write("progress", name .. "\n" .. table.concat(state.notes, "\n"))
end

local function finish(result, reason)
    write("result", "result=" .. result .. "\nphase=" .. state.phase .. "\nreason=" .. tostring(reason)
        .. "\n" .. table.concat(state.notes, "\n"))
    state.phase = "done"
end

local function floor(x, y)
    local square = getCell():getGridSquare(x, y, 0)
    assert(square, "fixture floor is not loaded")
    return square
end

local function crate(x, y)
    local square = floor(x, y)
    local object = IsoThumpable.new(getCell(), square, "carpentry_01_16", false, {})
    object:setIsContainer(true)
    local inventory = ItemContainer.new("crate", square, object)
    inventory:setCapacity(100)
    inventory:setExplored(true)
    object:setContainer(inventory)
    square:AddSpecialObject(object)
    square:RecalcAllWithNeighbours(true)
    return object
end

local function menuOption(actor)
    local menu = ISContextMenu.get(0, 0, 0)
    SC.UIContext.fillWorldObjectContextMenu(0, menu, { actor }, false)
    menu:hideAndChildren()
    for _, option in ipairs(menu.options) do
        if option.scMenuKey == "expedition.cancel:" .. state.id then return option end
    end
end

Events.OnMainMenuEnter.Add(function() MainScreen.continueLatestSave("Sandbox", "PzoRestoreFixture") end)
Events.OnGameStart.Add(function()
    SC.Scheduler.unregister("decision")
    state.player = assert(getSpecificPlayer(0))
    state.player:teleportTo(6429.5, 5449.5, 0)
    phase("load")
end)

local function step()
    local E, W, U = SC.ExpeditionPrototype, SC.ExpeditionWood, SC.GameplayUtil
    local player, actor, car = state.player, state.actor, state.car
    if state.phase == "menu" then
        local modal = MainScreen.instance and MainScreen.instance.checkSavefileModal
        if modal and modal.yes and not state.modals[modal] then
            state.modals[modal] = true
            modal:onClick(modal.yes)
        end
        return
    end
    local age = getTimestampMs() - state.at
    assert(age < 75000, "phase timed out")
    if state.phase == "load" then
        if age < 12000 or not SC.Persistence.restoreStatus() then return end
        assert(SCBridge and PZOEngine, "native bridge and PZO required")
        note("release", SC.Identity.release)
        SC.BaseLife.reset()
        assert(SC.BaseLife.create(floor(6439, 5449), "Expedition test camp"))
        local base = SC.BaseLife.active()
        base.settings.autoMaintenance, base.settings.routines = false, false
        assert(SC.BaseLife.registerStorage(crate(6446, 5452), "construction"))
        state.car = assert(addVehicleDebug("Base.CarNormal", IsoDirections.W, nil, floor(6461, 5449)))
        state.ticket = assert(SC.Actor.beginSpawn(floor(6430, 5449), { recruited = true,
            identity = { forename = "Robin", surname = "Crew", gender = "woman", outfit = "Generic01" } }))
        phase("spawn")
    elseif state.phase == "spawn" then
        if not actor then
            local ready, reason = SC.Actor.pollSpawn(state.ticket)
            assert(ready or reason == "spawn_pending", tostring(reason))
            if not ready then return end
            state.actor, state.id = ready, assert(SC.Registry.idOf(ready))
            return
        end
        local sqlId = car:getSqlId()
        if sqlId < 0 or SC.Vehicle.loadedBySqlId(sqlId) ~= car or not SC.Vehicle.isStationary(car) then
            assert(age < 10000, "fixture car unavailable, SQL ID " .. tostring(sqlId))
            return
        end
        assert(SC.BaseLife.assign(state.id, "quartermaster", true))
        assert(SC.Commands.issue(state.id, "base_duty", {}, player))
        local inv = actor:getInventory()
        state.axe = assert(inv:AddItem("Base.Axe"))
        for _ = 1, 16 do
            if not W.carryDestination(actor) then break end
            assert(inv:AddItem("Base.Plank"))
        end
        assert(not W.carryDestination(actor), "fixture can carry a log within normal walking weight")
        local _, trunk = SC.Vehicle.cargoPart(car)
        assert(trunk and SC.ExpeditionIntegration.woodReturnShuttleAvailable(actor, sqlId), "no short home delivery")
        local log = W.createState({ mode = "count", quantity = 1 })
        local roster = { assert(SC.Registry.byId(state.id)) }
        local vehicle = { sqlId = sqlId }
        local distance = U.distance(actor, car)
        assert(distance > 25, "fixture needs the crew away from the car")
        assert(not W.carryDestination(actor, nil, { carId = sqlId, target = { x = 6446, y = 5452, z = 0 } }),
            "a real transfer still needs the actor by the car")
        note("distance_to_car_m", distance)
        local ready, why = W.departureReady(roster, log, vehicle)
        note("wood_gate", why)
        assert(ready, tostring(why))
        log.preparation, log.preparationReason = true, "wood_preparing_axes"
        local destination = { x = 6491, y = 5449, z = 0 }
        log.sites, log.siteIndex = { { id = "forest:6491:5449:Forest", label = "Expedition fixture", type = "Forest",
            anchor = destination, bounds = { x1 = 6483, y1 = 5441, x2 = 6499, y2 = 5457, z = 0 }, distance = 61 } }, 1
        local started, mission = E.start(roster, { kind = "wood", wood = log,
            travelMode = "straight", destination = destination, turnHomeAfterHours = 4 })
        assert(started, tostring(mission))
        log = mission.scout.wood
        log.tripId = mission.radioSession
        local descriptor, reason = SC.ExpeditionCar.copyDescriptor({ state = "walking_to_car", leg = "outbound",
            sqlId = sqlId, script = car:getScriptName(), seats = { [state.id] = 0 }, parkingZoneId = "fixture-parking",
            parking = { x1 = 6459, y1 = 5447, x2 = 6463, y2 = 5451, z = 0 },
            departure = { x = 6461, y = 5449, z = 0 }, home = mission.scout.returnPoint,
            siteStop = destination, departureFuel = 1, departureHeading = 0 }, mission.roster, state.id)
        assert(descriptor, tostring(reason))
        mission.scout.vehicle, mission.scout.travelMode, mission.scout.phase = descriptor, "drive", "walking_to_car"
        state.mission, state.carX, state.carY = mission, car:getX(), car:getY()
        assert(mission.scout.departurePreparation, "native departure preparation missing")
        assert(not car:isEngineRunning() and car:getDriver() == nil, "car must be parked and empty")
        phase("nearby")
    elseif state.phase == "nearby" then
        if getSpecificPlayer(1) ~= actor then
            assert(age < 7000, "native expedition view did not join the exact recruit")
            return
        end
        player:faceLocation(actor:getX(), actor:getY())
        local tripId, why = E.nearbyCancellation(player, actor)
        state.reach = tostring(why) .. " dist=" .. U.distance(player, actor)
        if not tripId and age < 4000 then return end
        assert(tripId == state.mission.radioSession, state.reach)
        assert(not E.cancelNearby(player, actor, "earlier-trip"), "a stale menu changed the live trip")
        local option = assert(menuOption(actor), "stock world context is missing Cancel expedition")
        local accepted, reason = option.onSelect(option.target, option.param1, option.param2)
        note("native_menu", reason)
        assert(accepted, tostring(reason))
        local scout = state.mission.scout
        assert(scout.phase == "awaiting_player" and scout.vehicle.state == "home_wait"
            and not scout.departurePreparation, "nearby recall should settle here without boarding")
        local saved = E.export()
        assert(saved.scout and saved.scout.vehicle and saved.scout.vehicle.state == "home_wait"
            and saved.scout.wood.endReason == "called_off_nearby", "the saved trip lost the local return")
        assert(not menuOption(actor), "an already recalled crew still exposes cancellation")
        phase("settling")
    elseif state.phase == "settling" then
        if E.current() then
            -- In production the session and actor decisions are scheduled.
            -- The test drives only the same session owner in this quiet world.
            E.pulse()
            return
        end
        assert(getSpecificPlayer(1) == nil and getSpecificPlayer(0) == player, "joined view was not released")
        assert(SC.Registry.byId(state.id).actor == actor and not actor:isDead()
            and SC.Commands.peek(actor).order == "base_duty", "the exact recruit did not resume camp duty")
        assert(not car:isEngineRunning() and car:getDriver() == nil and actor:getVehicle() == nil
            and math.abs(car:getX() - state.carX) < 0.1 and math.abs(car:getY() - state.carY) < 0.1,
            "cancellation moved the parked vehicle or seated the crew")
        assert(actor:getInventory():contains(state.axe), "personal axe was lost on cancellation")
        note("native_view", "released")
        note("crew", "same recruit back on base duty")
        note("car", "same parked position and empty seats")
        finish("PASS", "native camp departure and in-person cancellation")
    end
end

Events.OnTick.Add(function()
    if state.phase == "done" then return end
    local ok, failure = pcall(step)
    if not ok then finish("FAIL", failure) end
end)
