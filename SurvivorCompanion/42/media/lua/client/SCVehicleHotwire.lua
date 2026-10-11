-- SPDX-License-Identifier: MIT
-- A player order to hotwire a parked car. Boarding uses the same verified
-- driver-door transaction as an expedition; the engine decides whether the
-- attempt succeeds, just as it does for the player's timed action.
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.VehicleHotwire = SC.VehicleHotwire or {}
local Hotwire = SC.VehicleHotwire
local jobs = setmetatable({}, { __mode = "k" })

local function call(object, method, ...)
    if object == nil or not SC.Call then return false, nil end
    return SC.Call.method(object, method, ...)
end

local function nowMs()
    return SC.GameplayUtil and SC.GameplayUtil.nowMs and SC.GameplayUtil.nowMs()
        or (type(getTimestampMs) == "function" and getTimestampMs() or 0)
end

local function note(job, message)
    local player = job.player
    if player then call(player, "setHaloNote", message) end
end

function Hotwire.canHotwire(actor)
    if not actor or not Perks then return false end
    local electricOk, electric = call(actor, "getPerkLevel", Perks.Electricity)
    local mechanicOk, mechanic = call(actor, "getPerkLevel", Perks.Mechanics)
    local burglarOk, burglar = false, false
    if CharacterTrait and CharacterTrait.BURGLAR then
        burglarOk, burglar = call(actor, "hasTrait", CharacterTrait.BURGLAR)
    end
    return burglarOk and burglar == true or electricOk and mechanicOk
        and tonumber(electric) >= 1 and tonumber(mechanic) >= 2
end

local function validCar(actor, car, player)
    if not Hotwire.canHotwire(actor) then return false, "hotwire_skill_required" end
    if not SC.Vehicle or not SC.Vehicle.isStationary then
        return false, "vehicle_adapter_unavailable"
    end
    local still, reason = SC.Vehicle.isStationary(car)
    if not still then return false, reason or "vehicle_moving" end
    local hotOk, hot = call(car, "isHotwired")
    if not hotOk then return false, "hotwire_state_unavailable" end
    if hot then return false, "already_hotwired" end
    local brokenOk, broken = call(car, "isHotwiredBroken")
    if brokenOk and broken then return false, "hotwire_broken" end
    local engineOk, running = call(car, "isEngineRunning")
    if engineOk and running then return false, "engine_running" end
    local driverOk, driver = call(car, "getDriver")
    if not driverOk or driver ~= nil and driver ~= actor then
        return false, "driver_seat_occupied"
    end
    local playerCarOk, playerCar = call(player, "getVehicle")
    if playerCarOk and playerCar == car then return false, "player_in_car" end
    local actorCarOk, actorCar = call(actor, "getVehicle")
    if not actorCarOk or actorCar ~= nil and actorCar ~= car then
        return false, "companion_in_other_car"
    end
    if actorCar == nil then
        local squares, _, why = SC.Vehicle.boardingSquares(actor, car, 0, true)
        if not squares or #squares == 0 then return false, why or "driver_door_blocked" end
    end
    return true
end

function Hotwire.request(actor, car, player)
    if not actor or not car or not player then return false, "vehicle_unavailable" end
    if jobs[actor] then return false, "hotwire_already_ordered" end
    local axOk, ax = call(actor, "getX")
    local ayOk, ay = call(actor, "getY")
    local azOk, az = call(actor, "getZ")
    local pxOk, px = call(player, "getX")
    local pyOk, py = call(player, "getY")
    local pzOk, pz = call(player, "getZ")
    if not axOk or not ayOk or not azOk or not pxOk or not pyOk or not pzOk
        or tonumber(az) ~= tonumber(pz)
        or (tonumber(ax) - tonumber(px))^2
            + (tonumber(ay) - tonumber(py))^2 > 16^2 then
        return false, "companion_too_far"
    end
    local ok, reason = validCar(actor, car, player)
    if not ok then return false, reason end
    -- A manual order may interrupt downtime, but never a live expedition.
    if SC.ExpeditionPrototype and SC.ExpeditionPrototype.isMember
        and SC.ExpeditionPrototype.isMember(actor) then
        return false, "expedition_leader_radio_required"
    end
    if SC.BaseWork and type(SC.BaseWork.cancel) == "function" then
        local cancelled, why = SC.BaseWork.cancel(actor, "player_hotwire_order")
        if cancelled ~= true then return false, why or "base_work_busy" end
    end
    if SC.NativeActions and type(SC.NativeActions.interruptOwnedActivity) == "function" then
        local interrupted, why = SC.NativeActions.interruptOwnedActivity(
            actor, "player_hotwire_order")
        if interrupted ~= true then return false, why or "companion_busy" end
    end
    jobs[actor] = { car = car, player = player, phase = "boarding",
        expires = nowMs() + 60000 }
    return true, "hotwire_ordered"
end

function Hotwire.cancel(actor, reason)
    local job = jobs[actor]
    if not job then return false end
    if job.sound then
        local emitterOk, emitter = call(actor, "getEmitter")
        local playingOk, playing = call(emitter, "isPlaying", job.sound)
        if emitterOk and playingOk and playing then
            call(actor, "stopOrTriggerSound", job.sound)
        end
    end
    if job.phase == "boarding" and SC.Vehicle and SC.Vehicle.cancelTransaction then
        SC.Vehicle.cancelTransaction(actor, reason or "hotwire_cancelled")
    end
    jobs[actor] = nil
    return true
end

function Hotwire.active(actor)
    return jobs[actor] ~= nil
end

local function finish(actor, job, message)
    Hotwire.cancel(actor, "hotwire_finished")
    note(job, message)
    local carOk, current = call(actor, "getVehicle")
    if carOk and current == job.car and SC.Vehicle and SC.Vehicle.exit then
        SC.Vehicle.exit(actor, job.car, 0, { playerCommand = true })
    end
end

-- Called by Decision before the ordinary follow/vehicle-exit policy. The
-- companion stays seated while the native engine resolves its attempt.
function Hotwire.step(actor, snapshot)
    local job = jobs[actor]
    if not job then return nil end
    local car = job.car
    if nowMs() > job.expires then
        finish(actor, job, "Hotwire cancelled: took too long.")
        return false, "hotwire_timeout"
    end
    if (tonumber(snapshot and snapshot.immediateCount) or 0) > 0 then
        finish(actor, job, "Hotwire interrupted by danger.")
        return false, "hotwire_danger"
    end
    local still, reason = SC.Vehicle.isStationary(car)
    if not still then
        finish(actor, job, "Hotwire interrupted: " .. tostring(reason or "car moving"))
        return false, "hotwire_car_moved"
    end
    local hotOk, hot = call(car, "isHotwired")
    if not hotOk or (hot and job.phase ~= "verifying") then
        finish(actor, job, hot and "Car is already hotwired." or "Car is unavailable.")
        return hot == true, hot and "already_hotwired" or "hotwire_state_unavailable"
    end
    local driverOk, driver = call(car, "getDriver")
    if not driverOk or driver ~= nil and driver ~= actor then
        finish(actor, job, "Hotwire interrupted: driver seat occupied.")
        return false, "hotwire_driver_changed"
    end
    local carOk, current = call(actor, "getVehicle")
    if not carOk or current ~= nil and current ~= car then
        finish(actor, job, "Hotwire interrupted: seat changed.")
        return false, "hotwire_seat_changed"
    end
    if current == nil then
        if job.phase ~= "boarding" then
            finish(actor, job, "Hotwire interrupted: left car.")
            return false, "hotwire_left_car"
        end
        local boarded, why = SC.ExpeditionCar.boardMember(actor,
            { car = car, seat = 0, hotwire = true }, snapshot)
        if not boarded and why ~= "already_active"
            and why ~= "companion is not at the passenger door"
            and why ~= "path_pending" and why ~= "pathing" then
            -- Navigation can report a pending route under several names; keep
            -- the bounded order alive unless boarding is definitively refused.
            if type(why) == "string" and (string.find(why, "rejected", 1, true)
                or string.find(why, "unavailable", 1, true)
                or string.find(why, "blocked", 1, true)) then
                finish(actor, job, "Cannot reach driver's door: " .. why)
                return false, why
            end
        end
        return true, why or "hotwire_approaching"
    end
    if not driverOk or driver ~= actor then
        finish(actor, job, "Hotwire interrupted: driver seat changed.")
        return false, "hotwire_driver_changed"
    end
    if job.phase == "boarding" then
        local electricOk, electric = call(actor, "getPerkLevel", Perks.Electricity)
        job.phase = "working"
        job.readyAt = nowMs() + math.max(1000,
            (200 - (electricOk and tonumber(electric) or 0) * 3) * 20)
        local emitterOk, emitter = call(actor, "getEmitter")
        if emitterOk then
            local soundOk, sound = call(emitter, "playSound", "VehicleHotwireStart")
            if soundOk then job.sound = sound end
        end
        return true, "hotwire_working"
    end
    if job.phase == "working" and nowMs() >= job.readyAt then
        local electricOk, electric = call(actor, "getPerkLevel", Perks.Electricity)
        local attemptOk = call(car, "tryHotwire", electricOk and electric or 0)
        if not attemptOk then
            finish(actor, job, "Hotwire failed: vehicle rejected the attempt.")
            return false, "hotwire_call_failed"
        end
        job.phase = "verifying"
        job.readyAt = nowMs() + 1500
        return true, "hotwire_verifying"
    end
    if job.phase == "verifying" and nowMs() >= job.readyAt then
        local hotOk, hot = call(car, "isHotwired")
        finish(actor, job, hotOk and hot
            and "Car hotwired. No key needed to drive it."
            or "Hotwire failed. You can order another attempt.")
        return hotOk and hot == true, hotOk and hot and "hotwired" or "hotwire_failed"
    end
    return true, "hotwire_" .. job.phase
end

function Hotwire.reset()
    for actor in pairs(jobs) do Hotwire.cancel(actor, "runtime_reset") end
end

return Hotwire
