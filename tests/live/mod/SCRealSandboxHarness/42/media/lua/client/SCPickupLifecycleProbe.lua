-- SPDX-License-Identifier: MIT
-- Isolated native lifecycle proof, before the pickup service/UI is installed.
-- Real seats, wheel leases, co-op maps and passenger physics; no replacement car.
require "SCPickupJourney"
local P = {}
local function value(object, name, ...)
    return (LivingFellows.GameplayUtil.call(object, name, ...))
end
function P.step(H, current, check, result, setPhase)
    local SC, test = LivingFellows, H.driveTest
    local actor, car = test.actor, test.vehicle
    local function fail(name, detail)
        check(name, false, detail)
        setPhase("finish", current)
    end
    if current - H.phaseStartedAt > 45000 then
        fail("pickup_lifecycle_deadline", H.phase .. " reason=" .. tostring(test.pickupReleaseReason or test.pickupClaimReason)) return
    end
    if H.phase == "drive_pickup_claim" then
        if not test.pickup then
            test.pickup = { requestId = H.config.run_id .. "-lifecycle", carSqlId = value(car, "getSqlId") }
            -- Initial fixture placement only; movement below is native physics.
            H.player:teleportTo(car:getX() - test.road.ay * 5,
                car:getY() + test.road.ax * 5, 0)
            test.originalActor, test.originalCar = actor, car
            test.originalPlayer = H.player
            test.originalPrimarySql = SCSplitScreenProbe.debugPlayerSqlId(H.player)
            local kit=SC.ExpeditionPrototype.provisionTestRadios(H.player,{SC.Registry.byId(SC.Registry.idOf(actor))})
            test.radioKit=kit
            require "SCPickupRadioFixture"
            if not SCRealSandboxHarnessProbes.SCPickupRadioFixture.prepare(H,test,check) then setPhase("finish",current) return end
            test.pickupRadioAt=current
            return
        end
        if test.radioPCBuild then
            local ready=SCRealSandboxHarnessProbes.SCPickupRadioFixture.install(H,test,check)
            if ready==nil then return end
            if not ready then setPhase("finish",current) return end
        end
        if not test.pickupRadioReady then
            local kit=test.radioKit
            local caller=SC.PickupRadio.caller(H.player,kit.player)
            local receiver=SC.PickupRadio.driver(actor)
            if (not caller or not receiver) and current-test.pickupRadioAt<10000 then return end
            local okay,why=SC.PickupRadio.exchange(caller,receiver,test.pickup.requestId,"request")
            local attempt=SC.PickupRadio.lastAttempt or {}
            local reception=SC.PickupRadio.lastReception or {}
            check("pickup_radio_native_diagnostic",true,"called="..tostring(attempt.called)
                .." accepted="..tostring(attempt.accepted).." received="..tostring(attempt.received)
                .." exact="..tostring(reception.exact).." guid="..tostring(reception.guid)
                .." codes="..tostring(reception.codes).." text="..tostring(reception.text)
                .." target="..tostring(attempt.target).." caller="..tostring(caller~=nil).." receiver="..tostring(receiver~=nil))
            if not check("pickup_lifecycle_native_radio_ack",okay,
                "exact equipped native handsets before view acquisition; "..tostring(why)) then setPhase("finish",current) return end
            local device=kit.team[1]:getDeviceData()
            local originalChannel=device:getChannel()
            device:setChannel(originalChannel+200)
            local wrong=SC.PickupRadio.exchange(caller,receiver,test.pickup.requestId,"cancel")
            if not check("pickup_lifecycle_radio_wrong_channel",wrong~=true,"no acknowledged command on another channel") then setPhase("finish",current) return end
            device:setChannel(originalChannel)
            device:setMicIsMuted(true)
            local muted=SC.PickupRadio.exchange(caller,receiver,test.pickup.requestId,"cancel")
            if not check("pickup_lifecycle_radio_muted",muted~=true,"reply requires a working microphone") then setPhase("finish",current) return end
            device:setMicIsMuted(false)
            if not SCRealSandboxHarnessProbes.SCPickupRadioFixture.measure(H,test,check) then setPhase("finish",current) return end
            test.pickupRadioReady=true
            test.pickupCycle = 1
            local reserved, why = SC.PickupJourney.reserve(test.pickup)
            if not check("pickup_lifecycle_reserved", reserved, tostring(why)) then setPhase("finish", current) return end
            local started, reason = SC.Driving.start(actor)
            if not check("pickup_lifecycle_empty_owner", started, tostring(reason)) then setPhase("finish", current) return end
        end
        if test.radioNoHandset then
            local ready=SCRealSandboxHarnessProbes.SCPickupRadioFixture.relay(H,test,check)
            if ready==nil then return end
            if not ready then setPhase("finish",current) return end
        end
        local acquired, why = SC.PickupJourney.acquire(test.pickup, actor)
        if not acquired then
            test.pickupClaimReason = why
            return
        end
        local slotId = SCSplitScreenProbe.leaderSqlId()
        if not check("pickup_lifecycle_seated_view_" .. test.pickupCycle,
            getSpecificPlayer(1) == actor and value(car,"getDriver") == actor
                and (not test.firstSlotId or slotId == test.firstSlotId),
            "slot_sql=" .. tostring(slotId)) then setPhase("finish", current) return end
        setPhase("drive_pickup_near", current)
        return
    end
    if H.phase == "drive_pickup_near" then
        local stopped, why = SC.Driving.release(actor, "pickup_probe_primary_handoff")
        if not stopped then return end
        local released, reason = SC.PickupJourney.releaseNear(test.pickup, actor, car)
        if not released then test.pickupReleaseReason = reason return end
        test.firstSlotId = test.firstSlotId or test.pickup.slotSqlId
        if not check("pickup_lifecycle_primary_handoff_" .. test.pickupCycle,
            getSpecificPlayer(1) == nil and getSpecificPlayer(0) == test.originalPlayer
                and car == test.originalCar and actor == test.originalActor
                and value(car,"getDriver") == actor,
            "exact driver and car retained by primary map") then setPhase("finish", current) return end
        local entered, accepted = pcall(car.enter, car, 1, H.player)
        if not check("pickup_lifecycle_real_passenger_" .. test.pickupCycle,
            entered and accepted == true and H.player:getVehicle() == car
                and car:getSeat(H.player) == 1,
            "stock vehicle enter seat 1") then setPhase("finish", current) return end
        car:setCharacterPosition(H.player,1,"inside")
        car:transmitCharacterPosition(1,"inside")
        car:playPassengerAnim(1,"idle")
        triggerEvent("OnEnterVehicle",H.player)
        test.rideStartX, test.rideStartY = car:getX(), car:getY()
        test.rideTop = 0
        local goal = { x = car:getX() + test.dirX * 18,
            y = car:getY() + test.dirY * 18, z = 0 }
        local started, driveReason = SC.Driving.drive(actor, goal,
            { passenger = H.player, speedKmh = 10 })
        if not check("pickup_lifecycle_passenger_owner_" .. test.pickupCycle,
            started, tostring(driveReason)) then setPhase("finish", current) return end
        setPhase("drive_pickup_ride", current)
        return
    end
    if H.phase == "drive_pickup_ride" then
        test.rideTop = math.max(test.rideTop, math.abs(car:getCurrentSpeedKmHour()))
        local state = SC.Driving.jobStatus(actor)
        if state and state.result == "failed" then fail("pickup_lifecycle_passenger_motion", state.reason) return end
        if state and state.result == "arrived" then
            local moved = math.sqrt((car:getX() - test.rideStartX)^2 + (car:getY() - test.rideStartY)^2)
            if not check("pickup_lifecycle_passenger_motion_" .. test.pickupCycle,
                moved >= 8 and test.rideTop > 3 and H.player:getVehicle() == car
                    and getSpecificPlayer(1) == nil,
                "metres=" .. tostring(moved) .. " top=" .. tostring(test.rideTop)) then setPhase("finish", current) return end
            local stopped = SC.Driving.release(actor, "pickup_probe_dropoff")
            if not stopped then return end
            local exited, accepted = pcall(car.exit, car, H.player)
            if not check("pickup_lifecycle_real_exit_" .. test.pickupCycle,
                exited and accepted == true and H.player:getVehicle() == nil,
                "stock vehicle exit") then setPhase("finish", current) return end
            local started = SC.Driving.start(actor)
            if not started then fail("pickup_lifecycle_return_owner", "empty driver rejected") return end
            test.pickupCycle = test.pickupCycle + 1
            if test.pickupCycle <= 2 then setPhase("drive_pickup_claim", current)
            else setPhase("drive_pickup_finish", current) end
        end
        return
    end
    if H.phase == "drive_pickup_finish" then
        local same = actor == test.originalActor and car == test.originalCar
            and getSpecificPlayer(0) == test.originalPlayer
            and SCSplitScreenProbe.debugPlayerSqlId(H.player) == test.originalPrimarySql
            and getSpecificPlayer(1) == nil
        if not check("pickup_lifecycle_exact_identity", same,
            "same driver/car/player after two view/passenger cycles") then setPhase("finish", current) return end
        SC.Driving.release(actor, "pickup_probe_finished")
        local exited, reason = SC.Vehicle.exit(actor, car, nil, { restoreByDoor = true })
        if not exited then test.pickupExitReason = reason return end
        local released, why = SC.PickupJourney.releaseReservation(test.pickup)
        if not check("pickup_lifecycle_reservation_released", released, tostring(why)) then setPhase("finish",current) return end
        test.coldCycle=1
        setPhase("drive_pickup_cold_setup",current)
        return
    end
    if H.phase=="drive_pickup_cold_setup" then
        local x,y=math.floor(car:getX()+600+test.coldCycle*40),math.floor(car:getY()+600)
        local okay,reason=SC.BaseLife.create({x=x,y=y,z=0},"Cold pickup query")
        if not check("pickup_cold_camp_"..test.coldCycle,okay,tostring(reason)) then setPhase("finish",current) return end
        SC.BaseLife.beginZone("area",{x=x-8,y=y-8,z=0})
        local marked,why=SC.BaseLife.finishZone({x=x+8,y=y+8,z=0},"Cold query area")
        if not check("pickup_cold_area_"..test.coldCycle,marked,tostring(why)) then setPhase("finish",current) return end
        local camp=SC.HomeTrip.captureCamp(SC.BaseLife.active())
        test.coldQuery={requestId=H.config.run_id.."-cold-"..test.coldCycle,camp=camp,candidateIds={}}
        if not check("pickup_cold_outside_primary_"..test.coldCycle,
            SCSplitScreenProbe.primaryAreaContains(x,y,0)==false,"query streams its own distant area") then setPhase("finish",current) return end
        setPhase("drive_pickup_cold_warm",current)
        return
    end
    if H.phase=="drive_pickup_cold_warm" then
        local ready,reason=SC.PickupJourney.warm(test.coldQuery)
        if not ready then test.pickupClaimReason=reason return end
        if not check("pickup_cold_owned_loader_"..test.coldCycle,
            getSpecificPlayer(1)~=nil and SCSplitScreenProbe.isColdProbe(getSpecificPlayer(1))==true
                and SC.ViewSession.owner()=="pickup" and SC.ViewSession.slotSqlId()==test.firstSlotId
                and (SCSplitScreenProbe.leaderSqlId()==-1 or SCSplitScreenProbe.leaderSqlId()==test.firstSlotId),
            "native_slot="..tostring(SCSplitScreenProbe.leaderSqlId()).." remembered="..tostring(SC.ViewSession.slotSqlId())
                .." expected="..tostring(test.firstSlotId).." cold="..tostring(SCSplitScreenProbe.isColdProbe(getSpecificPlayer(1)))
                .." owner="..tostring(SC.ViewSession.owner())) then setPhase("finish",current) return end
        setPhase("drive_pickup_cold_close",current)
        return
    end
    if H.phase=="drive_pickup_cold_close" then
        local closed,reason=SC.PickupJourney.closePreview(test.coldQuery)
        if not closed then test.pickupReleaseReason=reason return end
        if not check("pickup_cold_cancel_releases_"..test.coldCycle,
            getSpecificPlayer(1)==nil and SC.ViewSession.owner()==nil and not SC.ViewSession.blockedFor("expedition"),
            "only the query loader and reservation are released") then setPhase("finish",current) return end
        test.coldCycle=test.coldCycle+1
        setPhase(test.coldCycle<=2 and "drive_pickup_cold_setup" or "finish",current)
    end
end
SCRealSandboxHarnessProbes = SCRealSandboxHarnessProbes or {}
SCRealSandboxHarnessProbes.SCPickupLifecycleProbe = P
return P
