-- SPDX-License-Identifier: MIT
-- A disposable camp and kit are arranged before the measurement. Thereafter
-- production AI, radio delivery, boarding, driving and persistence own the trip.
local P={}
local function call(o,name,...) return (SurvivorCompanion.GameplayUtil.call(o,name,...)) end
local function originalCargo(t,car)
    if not t.pickupCargoId then return true end
    local _,container=SurvivorCompanion.Vehicle.cargoPart(car)
    local items=container and container:getItems()
    if not items then return false end
    for index=0,items:size()-1 do
        local item=items:get(index)
        if item:getID()==t.pickupCargoId and item:getFullType()=="Base.NailsBox" then return true end
    end
    return false
end
local function originalKey(t,actor,car)
    local key=actor:getInventory():haveThisKeyId(car:getKeyId()) or car:getCurrentKey()
    if key then return key:getID()==t.pickupKeyId,"native="..tostring(key:getID()).." expected="..tostring(t.pickupKeyId) end
    local record=SurvivorCompanion.Registry.byId(t.pickupDriverId)
    if record and record.actor~=actor then
        key=record.actor:getInventory():haveThisKeyId(car:getKeyId())
        if key then return key:getID()==t.pickupKeyId,"restored="..tostring(key:getID()) end
    end
    local document=SurvivorCompanion.Persistence.lastDocument()
    local outcome=SurvivorCompanion.PickupService.export().outcome
    local completed=document and document.pickup
    if not outcome or not completed or completed.state~="idle" or not completed.outcome
        or completed.outcome.requestId~=outcome.requestId or completed.outcome.result~="returned" then
        return false,"key is not native and there is no matching durable return"
    end
    local saved=document and document.companions[t.pickupDriverId]
    for _,item in ipairs(saved and saved.inventory and saved.inventory.roots or {}) do
        if item.type=="Base.CarKey" and item.nativeId==t.pickupKeyId then return true,"exact key in durable returned-driver record" end
    end
    return false,"key absent from native inventory, ignition and durable returned-driver record"
end
function P.step(H,current,check,result,setPhase)
    local SC,t=SurvivorCompanion,H.driveTest
    local actor,car=t.actor,t.vehicle
    local S=SC.PickupService
    local function fail(name,detail) check(name,false,detail) setPhase("finish",current) end
    local budget=H.config.pickup_cold_service_probe=="true" and 600000 or 240000
    if current-H.phaseStartedAt>budget then
        local c=S.current() or S.previewCurrent()
        fail("pickup_service_deadline",H.phase.." state="..tostring(c and c.phase).." reason="..tostring(c and c.reason)) return
    end
    if H.phase=="drive_pickup_service_resume" then
        local proof=ModData.get("SC_PickupProbe")
        if not proof or proof.schema~=1 then fail("pickup_service_reload_proof","retained native stage proof missing") return end
        local ctx=S.current()
        if not ctx then fail("pickup_service_reload_active","active pickup journal missing") return end
        local record=SC.Registry.byId(proof.driverId)
        local loadedCar=SC.Vehicle.loadedBySqlId(proof.carId)
        if not record or not record.actor or not loadedCar or ctx.restoring then return end
        t.actor,t.vehicle=record.actor,loadedCar
        t.pickupDriverId,t.pickupCarId,t.pickupKeyId=proof.driverId,proof.carId,proof.keyItemId
        t.pickupCargoId=proof.cargoId
        t.pickupKit={player=H.player:getEquipedRadio()}
        t.pickupOriginal=ctx.plan.departure
        t.pickupReloadPhase=proof.phase
        t.road={ax=proof.roadX,ay=proof.roadY}
        t.pickupBoardAt=current-2000
        if not check("pickup_service_native_reload_identity",ctx.driverId==proof.driverId and ctx.carSqlId==proof.carId,
            "saved_phase="..tostring(proof.phase).." current_phase="..tostring(ctx.phase)) then setPhase("finish",current) return end
        setPhase("drive_pickup_service_journey",current)
        return
    end
    if H.phase=="drive_pickup_service_setup" then
        if call(actor,"getVehicle") then
            local okay,reason=SC.Vehicle.exit(actor,car,nil,{restoreByDoor=true})
            if not okay then t.exitReason=reason return end
        end
        local x,y=math.floor(car:getX()),math.floor(car:getY())
        if H.config.pickup_watch_probe=="true" then
            require "SCPickupWatchFixture"
            if not SCRealSandboxHarnessProbes.SCPickupWatchFixture.prepare(H,t,check) then setPhase("finish",current) return end
        end
        local core=t.pickupWatchCore or {x=x,y=y,z=0}
        local okay,reason=SC.BaseLife.create(core,"Pickup probe camp")
        if not check("pickup_service_camp",okay,tostring(reason)) then setPhase("finish",current) return end
        local okay,reason=SC.BaseLife.beginZone("area",{x=math.min(x-12,core.x-4),y=math.min(y-10,core.y-4),z=0})
        if okay then okay,reason=SC.BaseLife.finishZone({x=math.max(x+12,core.x+4),y=math.max(y+10,core.y+4),z=0},"Pickup camp") end
        if not check("pickup_service_camp_area",okay,tostring(reason)) then setPhase("finish",current) return end
        local okay,reason=SC.BaseLife.beginZone("parking",{x=x-7,y=y-5,z=0})
        if okay then okay,reason=SC.BaseLife.finishZone({x=x+7,y=y+5,z=0},"Pickup parking") end
        if not check("pickup_service_parking",okay,tostring(reason)) then setPhase("finish",current) return end
        local okay,reason=SC.Commands.issue(SC.Registry.idOf(actor),"base_duty",{},H.player)
        if not check("pickup_service_duty",okay,tostring(reason)) then setPhase("finish",current) return end
        t.pickupKit=SC.ExpeditionPrototype.provisionTestRadios(H.player,{SC.Registry.byId(SC.Registry.idOf(actor))})
        t.pickupDriverId=SC.Registry.idOf(actor)
        t.pickupCarId=car:getSqlId()
        t.pickupKeyId=t.key and t.key:getID()
        t.pickupOriginal={x=car:getX(),y=car:getY(),z=0}
        local _,trunk=SC.Vehicle.cargoPart(car)
        local cargo=trunk and trunk:AddItem("Base.NailsBox")
        if not check("pickup_service_real_cargo_fixture",cargo~=nil,"actual trunk item before measurement") then setPhase("finish",current) return end
        t.pickupCargoId=cargo:getID()
        if t.pickupWatcher then
            H.player:teleportTo(x+2.5,y+3.5,0)
            local okay,reason=SC.Commands.issue(t.pickupWatcher.id,"base_duty",{},H.player)
            if not check("pickup_watch_camp_duty",okay,tostring(reason)) then setPhase("finish",current) return end
            setPhase("drive_pickup_service_watch_join",current)
            return
        end
        -- Setup only: caller is already waiting farther along this real road.
        H.player:teleportTo(car:getX()+t.road.ax*24-t.road.ay*6,
            car:getY()+t.road.ay*24+t.road.ax*6,0)
        t.pickupMeasurementAt=current
        t.pickupLastPhase=nil
        setPhase("drive_pickup_service_preview",current)
        return
    end
    if H.phase=="drive_pickup_service_watch_join" then
        local ready=SCRealSandboxHarnessProbes.SCPickupWatchFixture.join(H,t,current,check)
        if ready==nil then return end
        if not ready then setPhase("finish",current) return end
        H.player:teleportTo(car:getX()+t.road.ax*24-t.road.ay*6,
            car:getY()+t.road.ay*24+t.road.ax*6,0)
        t.pickupMeasurementAt=current
        setPhase("drive_pickup_service_preview",current)
        return
    end
    if H.phase=="drive_pickup_service_cold_unload" then
        local pending=SC.Persistence.pendingSnapshot()[t.pickupDriverId]
        local retained=SC.Registry.byId(t.pickupDriverId)
        if SC.Vehicle.loadedBySqlId(t.pickupCarId)~=nil
            or not (pending and pending.restorePrimaryOnly or retained and retained.runtime.restorePrimaryOnly) then
            if current>=(t.pickupUnloadLog or 0) then
                t.pickupUnloadLog=current+5000
                result("PASS","pickup_cold_unload_progress","retained="..tostring(retained~=nil).." pending="..tostring(pending~=nil)
                    .." car="..tostring(SC.Vehicle.loadedBySqlId(t.pickupCarId)~=nil))
            end
            return
        end
        if not check("pickup_cold_primary_only_resident",not SCSplitScreenProbe.primaryAreaContains(
            t.pickupOriginal.x,t.pickupOriginal.y,0),"actual returned resident and car unloaded outside primary map") then setPhase("finish",current) return end
        setPhase("drive_pickup_service_preview",current)
        return
    end
    if H.phase=="drive_pickup_service_preview" then
        if not S.previewCurrent() then
            local okay,reason=S.beginPreview(H.player,t.pickupKit.player)
            if not okay then
                if current-H.phaseStartedAt>15000 then fail("pickup_service_preview_open",tostring(reason)) end
                return
            end
        end
        local ctx=S.previewCurrent()
        if not ctx.ready then
            if current>=(t.pickupNextLog or 0) then
                t.pickupNextLog=current+5000
                result("PASS","pickup_service_preview_progress",tostring(ctx.reason).." drivers="..tostring(ctx.drivers and #ctx.drivers).." cars="..tostring(ctx.cars and #ctx.cars))
            end
            return
        end
        if not check("pickup_service_exact_selection",ctx.driverId==t.pickupDriverId and ctx.carSqlId==t.pickupCarId,
            "driver="..tostring(ctx.driverId).." car="..tostring(ctx.carSqlId)) then setPhase("finish",current) return end
        if t.pickupColdCycle then
            t.actor=SC.Registry.byId(ctx.driverId).actor
            t.vehicle=SC.Vehicle.loadedBySqlId(ctx.carSqlId)
            local key=t.vehicle and t.actor:getInventory():haveThisKeyId(t.vehicle:getKeyId())
            if not check("pickup_cold_restored_identity",(t.pickupColdCancelled or t.actor~=t.pickupRetiredActor) and t.vehicle~=nil
                and key and key:getID()==t.pickupKeyId and originalCargo(t,t.vehicle),
                "same survivor, SQL car and saved native key after cold restoration") then setPhase("finish",current) return end
            if not t.pickupColdCancelled then
                if not check("pickup_cold_cancel_with_resident",S.closePreview(),"cancel only the owned cold loader") then setPhase("finish",current) return end
                t.pickupColdCancelled=true t.pickupRetiredActor=t.actor
                setPhase("drive_pickup_service_cold_unload",current)
                return
            end
        end
        check("pickup_service_party_selected",#ctx.party<=2,"nearby eligible followers="..#ctx.party)
        if not t.pickupReviewAt then
            local opened,reason=SC.PickupUI.open(H.player,t.pickupKit.player)
            if not check("pickup_service_review_sheet",opened,tostring(reason)) then setPhase("finish",current) return end
            t.pickupReviewAt=current
            return
        end
        if current-t.pickupReviewAt<1000 then return end
        pcall(function() getCore():TakeFullScreenshot(H.config.run_id.."-pickup-review") end)
        local okay,reason=S.request(H.player,t.pickupKit.player)
        if not check("pickup_service_native_dispatch",okay,tostring(reason)) then setPhase("finish",current) return end
        setPhase("drive_pickup_service_journey",current)
        return
    end
    if H.phase=="drive_pickup_service_journey" then
        local ctx=S.current()
        if not ctx then
            local saved=S.export()
            local last=saved.outcome
            local noReservation=not SC.ViewSession.blockedFor("expedition")
            local viewReady=t.pickupWatcher and SC.ViewSession.owner()=="base_watch"
                and getSpecificPlayer(1)==t.pickupWatcher.actor or not t.pickupWatcher and getSpecificPlayer(1)==nil
            if not check("pickup_service_durable_return",last and last.result=="returned"
                and last.driverId==t.pickupDriverId and last.carId==t.pickupCarId
                and last.carSaveReceipt and last.carSaveReceipt.sqlId==t.pickupCarId
                and noReservation and viewReady,
                "result="..tostring(last and last.result).." view="..tostring(SC.ViewSession.owner())) then setPhase("finish",current) return end
            local keyOkay,keyDetail=originalKey(t,actor,car)
            check("pickup_service_original_car_key",car==t.vehicle and car:getSqlId()==t.pickupCarId and keyOkay,keyDetail)
            check("pickup_service_original_trunk_item",originalCargo(t,car),"same actual cargo item ID and type")
            if t.pickupWatcher then
                check("pickup_watch_native_resumed",SC.BaseWatch.current() and SC.BaseWatch.current().leaderId==t.pickupWatcher.id
                    and not SC.BaseWatch.current().pickupOwner and SCSplitScreenProbe.leaderSqlId()==t.pickupWatchSlot,
                    "original Watch resident and same native SQL slot restored")
            end
            if H.config.pickup_cold_service_probe=="true" and not t.pickupColdCycle then
                t.pickupColdCycle=true t.pickupRetiredActor=actor
                t.pickupReviewAt,t.pickupLastPhase,t.pickupBoardAt=nil,nil,nil
                -- Begin a separate cold-loading measurement after the complete
                -- physical journey. Only the observer is staged at a known road;
                -- the actual returned survivor, inventory and car stay at camp.
                H.player:teleportTo(5752,5402,0)
                setPhase("drive_pickup_service_cold_unload",current)
                return
            end
            setPhase("finish",current) return
        end
        if ctx.phase~=t.pickupLastPhase then
            t.pickupLastPhase=ctx.phase
            result("PASS","pickup_service_phase",ctx.phase.." view="..tostring(SC.ViewSession.owner()).." reason="..tostring(ctx.reason))
            if ctx.phase=="outbound" or ctx.phase=="waiting_board" or ctx.phase=="ride" then
                pcall(function() getCore():TakeFullScreenshot(H.config.run_id.."-pickup-"..ctx.phase) end)
            end
            if t.pickupWatcher and ctx.phase=="board_driver" then
                check("pickup_watch_native_borrowed",SC.BaseWatch.current() and SC.BaseWatch.current().pickupOwner==ctx.requestId
                    and getSpecificPlayer(1)==actor and SCSplitScreenProbe.leaderSqlId()==t.pickupWatchSlot,
                    "native living handoff from watched resident to selected driver")
            end
        end
        if t.pickupColdCycle and ctx.phase=="outbound" and SC.Driving.isDriving(actor)
            and math.abs(car:getCurrentSpeedKmHour())>=3 then
            local key=actor:getInventory():haveThisKeyId(car:getKeyId()) or car:getCurrentKey()
            if not check("pickup_cold_dispatch_motion",getSpecificPlayer(1)==actor and key
                and key:getID()==t.pickupKeyId and car:getSqlId()==t.pickupCarId and originalCargo(t,car),
                "view="..tostring(getSpecificPlayer(1)==actor).." key="..tostring(key and key:getID())
                    .." expected="..tostring(t.pickupKeyId).." same_car="..tostring(car:getSqlId()==t.pickupCarId)) then setPhase("finish",current) return end
            local saved,reason=SC.Runtime.save()
            if not check("pickup_cold_departure_saved",saved==true and SCSplitScreenProbe.flushGlobalModDataForWorldExit()==true,
                tostring(reason)) then setPhase("finish",current) return end
            setPhase("finish",current)
            return
        end
        if H.config.pickup_save_phase~="" and H.config.pickup_save_phase~=nil and ctx.phase==H.config.pickup_save_phase then
            if ctx.phase=="waiting_board" then
                t.pickupStageAt=t.pickupStageAt or current
                if current-t.pickupStageAt<500 then return end
                pcall(function() getCore():TakeFullScreenshot(H.config.run_id.."-pickup-waiting-board-settled") end)
            end
            local movingPhase=ctx.phase=="outbound" or ctx.phase=="ride" or ctx.phase=="returning"
            if movingPhase and (not SC.Driving.isDriving(actor) or math.abs(car:getCurrentSpeedKmHour())<3) then return end
            local proof=ModData.getOrCreate("SC_PickupProbe")
            proof.schema,proof.phase,proof.driverId,proof.carId=1,ctx.phase,t.pickupDriverId,t.pickupCarId
            proof.keyItemId,proof.roadX,proof.roadY=t.pickupKeyId,t.road.ax,t.road.ay
            proof.cargoId=t.pickupCargoId
            local saved,reason=SC.Runtime.save()
            if not check("pickup_service_saved_"..ctx.phase,saved==true,tostring(reason)) then setPhase("finish",current) return end
            local flushed=SCSplitScreenProbe.flushGlobalModDataForWorldExit()
            if not check("pickup_service_stage_flushed",flushed==true,"native global ModData flush") then setPhase("finish",current) return end
            setPhase("finish",current)
            return
        end
        if t.pickupUpdatePending and not ctx.updateRequested then
            if not check("pickup_service_acknowledged_update",ctx.pickup~=t.pickupBeforeUpdate,
                "one explicit update completed its bounded search and native request/reply") then setPhase("finish",current) return end
            t.pickupUpdatePending,t.pickupUpdated=nil,true
        end
        if not t.pickupUpdated and not t.pickupUpdatePending and not t.pickupColdCycle and ctx.phase=="outbound" and SC.Driving.isDriving(actor)
            and math.abs(car:getCurrentSpeedKmHour())>=3 then
            t.pickupBeforeUpdate=ctx.pickup
            local okay,reason=S.updatePickup(t.pickupKit.player)
            if not okay and reason=="pickup_finding_road" then t.pickupUpdatePending=true return end
            if not check("pickup_service_acknowledged_update",okay and ctx.phase=="acquire_outbound",tostring(reason)) then setPhase("finish",current) return end
            t.pickupUpdated=true
            return
        end
        if current>=(t.pickupNextJourneyLog or 0) then
            t.pickupNextJourneyLog=current+5000
            local job=SC.Driving.jobStatus(actor)
            result("PASS","pickup_service_progress",ctx.phase.." reason="..tostring(ctx.reason)
                .." job="..tostring(job and job.phase).." job_reason="..tostring(job and job.reason)
                .." car="..math.floor(car:getX())..","..math.floor(car:getY())
                .." passenger="..tostring(H.player:getVehicle()==car))
        end
        if ctx.phase=="held" then
            if (ctx.reason=="turn_failed" or ctx.reason=="parking_alignment_failed") and (t.pickupRetries or 0)<2 then
                t.pickupRetries=(t.pickupRetries or 0)+1
                local okay,reason=S.retry(t.pickupKit.player)
                if not check("pickup_service_acknowledged_retry_"..t.pickupRetries,okay,tostring(reason)) then setPhase("finish",current) return end
                return
            end
            fail("pickup_service_not_held",tostring(ctx.reason)) return
        end
        if ctx.phase=="waiting_board" and H.player:getVehicle()==nil then
            if not check("pickup_service_primary_handoff",getSpecificPlayer(1)==nil and car:getDriver()==actor
                and SC.ViewSession.blockedFor("expedition"),"reserved job with full primary view") then setPhase("finish",current) return end
            local okay,entered=pcall(car.enter,car,ctx.playerSeat,H.player)
            if not check("pickup_service_stock_boarding",okay and entered==true,"stock passenger enter") then setPhase("finish",current) return end
            car:setCharacterPosition(H.player,ctx.playerSeat,"inside")
            car:transmitCharacterPosition(ctx.playerSeat,"inside")
            car:playPassengerAnim(ctx.playerSeat,"idle")
            triggerEvent("OnEnterVehicle",H.player)
            if not check("pickup_service_seat_identity",H.player:getVehicle()==car
                and car:getCharacter(ctx.playerSeat)==H.player,"vanilla entry completion retains the exact player") then setPhase("finish",current) return end
            t.pickupBoardAt=current
        elseif ctx.phase=="waiting_board" and H.player:getVehicle()==car and current-t.pickupBoardAt>1200 then
            local destination={x=car:getX()+t.road.ax*20,y=car:getY()+t.road.ay*20,z=0}
            local okay,reason
            if t.pickupColdCycle or t.pickupReloadPhase=="waiting_board" then okay,reason=S.departHome(false)
            else okay,reason=S.depart(destination,false) end
            if not okay and reason=="pickup_waiting_for_companions" then t.pickupDepartReason=reason return end
            if not check("pickup_service_local_destination",okay,tostring(reason)) then setPhase("finish",current) return end
            local exact=true
            for id,seat in pairs(ctx.seats) do
                local record=SC.Registry.byId(id)
                if not record or car:getCharacter(seat)~=record.actor then exact=false end
            end
            check("pickup_service_actual_party_seats",exact,"ordinary followers boarded their reserved native seats")
        elseif ctx.phase=="ride" then
            t.pickupRideTop=math.max(t.pickupRideTop or 0,math.abs(car:getCurrentSpeedKmHour()))
        elseif ctx.phase=="drop_wait" and H.player:getVehicle()==car then
            if not SC.Vehicle.isStationary(car) then return end
            local okay,exited=pcall(car.exit,car,H.player)
            if not check("pickup_service_stock_exit",okay and exited==true,"stock passenger exit") then setPhase("finish",current) return end
            check("pickup_service_real_passenger_motion",(t.pickupRideTop or 0)>3,"top_kmh="..tostring(t.pickupRideTop))
        end
    end
end
SCRealSandboxHarnessProbes=SCRealSandboxHarnessProbes or {}
SCRealSandboxHarnessProbes.SCPickupServiceProbe=P
return P
