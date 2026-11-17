-- SPDX-License-Identifier: MIT
-- A camp resident drives an existing car. Only that driver owns a remote view;
-- companions travelling with the caller keep their ordinary Follow orders.
SurvivorCompanion = SurvivorCompanion or {}
local SC=SurvivorCompanion
local S={}
SC.PickupService=S
local active,preview,outcome,preferred
local sequence=0
local function U() return SC.GameplayUtil end
local function D() return SC.PickupDispatch end
local function J() return SC.PickupJourney end
local function R() return SC.PickupRadio end
local function human() return getSpecificPlayer and getSpecificPlayer(0) end
local function now() return U().nowMs() end
local function call(object,name,...)
    if not object then return nil end
    return (U().call(object,name,...))
end
local function copy(value,depth)
    if type(value)~="table" then return value end
    if (depth or 0)>14 then return nil end
    local result={}
    for key,item in pairs(value) do
        if type(key)=="string" or type(key)=="number" then
            if type(item)=="table" then result[key]=copy(item,(depth or 0)+1)
            elseif type(item)=="string" or type(item)=="number" or type(item)=="boolean" then result[key]=item end
        end
    end
    return result
end
local function actorFor(ctx)
    local record=ctx.driverId and SC.Registry.byId(ctx.driverId)
    return record and record.actor or ctx.deadActor or ctx.release and ctx.release.actor
end
local function carFor(ctx) return ctx.carSqlId and SC.Vehicle.loadedBySqlId(ctx.carSqlId) end
local function phase(ctx,value)
    ctx.phase,ctx.phaseAt,ctx.reason=value,now(),nil
    ctx.driveStarted=nil
    ctx.finalApproachSince=nil
    ctx.driveProgressAt,ctx.driveProgressPoint=nil,nil
    if value~="outbound" and value~="pickup_handoff" and value~="waiting_board" then
        ctx.updateRequested,ctx.updateSource,ctx.updateSearch=nil,nil,nil
    end
end
local function held(ctx,reason)
    ctx.updateRequested,ctx.updateSource,ctx.updateSearch=nil,nil,nil
    if reason=="pickup_new_player_order" or reason=="pickup_driver_changed" then
        ctx.relinquished=true
        SC.Vehicle.releaseService(ctx.requestId)
    end
    if ctx.phase~="held" then ctx.resumePhase=ctx.phase end
    ctx.phase,ctx.reason="held",reason or "pickup_journey_held"
    if ctx.actor and not ctx.relinquished then SC.Driving.stop(ctx.actor,"pickup_held") end
    return false,ctx.reason
end
local function stop(ctx,car)
    if SC.Driving.isDriving(ctx.actor) then
        local okay,reason=SC.Driving.stop(ctx.actor,"pickup_waiting")
        if not okay then return false,reason end
    end
    if not SC.Vehicle.isStationary(car) then return false,"pickup_waiting_for_stop" end
    if call(car,"isEngineRunning")==true then call(car,"shutOff") return false,"pickup_waiting_for_stop" end
    return true
end
local function durable()
    if SC.Persistence.requestScheduledSave then SC.Persistence.requestScheduledSave(human()) end
end
local function contact(ctx,source,action,localOkay)
    if ctx.contacting then return false,"pickup_radio_busy" end
    ctx.player=human()
    local actor=actorFor(ctx)
    if not actor then return false,"pickup_driver_unavailable" end
    local state=SC.Commands.peek(actor)
    if not state then return false,"pickup_driver_unavailable" end
    local commandSerial=state.commandSerial or 0
    ctx.contacting=true
    local called,delivered,receipt=pcall(R().deliver,ctx,actor,source,action,localOkay)
    ctx.contacting=nil
    if not called then return false,"pickup_radio_unavailable" end
    local latest=SC.Commands.peek(actor)
    if delivered and (actorFor(ctx)~=actor or not latest or (latest.commandSerial or 0)~=commandSerial
        or active~=ctx and preview~=ctx) then return false,"pickup_request_changed" end
    return delivered,receipt
end
function S.available()
    if (isClient and isClient()) or (isServer and isServer()) then return false,"pickup_single_player_only" end
    return J().available(),"pickup_bridge_unavailable"
end
function S.current() return active end
function S.previewCurrent() return preview end
function S.describe()
    local ctx=active or preview
    if not ctx then return {active=false,outcome=copy(outcome)} end
    return {active=active~=nil,preview=preview~=nil,requestId=ctx.requestId,phase=ctx.phase,
        reason=ctx.reason,driverId=ctx.driverId,carSqlId=ctx.carSqlId,pickup=copy(ctx.pickup),
        destination=copy(ctx.destination),viewOwner=SC.ViewSession.owner(),restoring=ctx.restoring==true,
        watchPaused=ctx.watchPaused==true,watchWarning=ctx.watchWarning}
end
function S.isDriver(actor) return active~=nil and actor~=nil and actorFor(active)==actor end
function S.ownsInventory(id) return active~=nil and active.driverId==id end
function S.isBookedPassenger(player,car)
    return active~=nil and player==human() and car==carFor(active)
        and call(player,"getVehicle")==car and (tonumber(call(car,"getSeat",player)) or -1)>0
end
function S.ownsSeat(actor,car)
    return S.isDriver(actor) and not active.relinquished and carFor(active)==car and active.phase~="exit_driver"
        and active.phase~="camp_arrival" and active.phase~="finish"
        and active.reason~="pickup_new_player_order" and active.reason~="pickup_driver_changed"
end
function S.contextFor(actor,player)
    if S.isDriver(actor) and not active.relinquished and SC.ViewSession.owner()=="pickup" then return actor end
    return player
end
function S.beginPreview(player,source)
    if active then return false,"pickup_already_active" end
    if preview then return true,preview end
    local available,reason=S.available()
    if not available then return false,reason end
    if player~=human() or call(player,"getVehicle")~=nil then return false,"pickup_caller_on_foot_required" end
    local endpoint,why=R().caller(player,source)
    if not endpoint then return false,why end
    local base=SC.BaseLife.active()
    local camp,reason=SC.HomeTrip.captureCamp(base)
    if not camp then return false,reason end
    local at=D().point(player)
    if not at or at.z~=0 then return false,"pickup_ground_floor_required" end
    sequence=sequence+1
    local ctx={requestId="pickup-"..tostring(now()).."-"..sequence,phase="preview",
        phaseAt=now(),camp=camp,player=player,source=endpoint,target=at,
        candidateIds=D().ids(camp.id),party=D().party(player),
        preferredDriver=preferred and preferred.driverId,preferredCar=preferred and preferred.carSqlId}
    local reserved,why=J().reserve(ctx)
    if not reserved then return false,why end
    preview=ctx
    return true,ctx
end
function S.select(driverId,carSqlId)
    if not preview then return false,"pickup_loading_camp" end
    if preview.contacting then return false,"pickup_radio_busy" end
    preview.selectedDriver,preview.selectedCar=driverId,carSqlId
    preview.plan,preview.pickup,preview.ready,preview.search=nil,nil,nil,nil
    preview.scanDriver,preview.scanCar=1,1
    return true
end
function S.closePreview()
    if not preview then return true end
    if preview.contacting then return false,"pickup_radio_busy" end
    preview.closing=true
    local okay,reason=J().closePreview(preview)
    if okay then preview=nil end
    return okay,reason
end
local function scan(ctx)
    if ctx.retryScanAt then
        if now()<ctx.retryScanAt then return end
        ctx.drivers,ctx.cars,ctx.search,ctx.lastReason,ctx.retryScanAt=nil,nil,nil,nil,nil
    end
    if not ctx.drivers then
        ctx.drivers=D().drivers(ctx)
        ctx.cars=SC.ExpeditionCar.parkedCars(nil,true)
        table.sort(ctx.cars,function(a,b)
            if a.sqlId==ctx.preferredCar then return true end
            if b.sqlId==ctx.preferredCar then return false end
            return a.sqlId<b.sqlId
        end)
        ctx.scanDriver,ctx.scanCar=1,1
        ctx.stations=R().stations(ctx.player,ctx.camp.id)
    end
    local driver=ctx.drivers[ctx.scanDriver]
    local car=ctx.cars[ctx.scanCar]
    if not driver or #ctx.cars==0 then
        ctx.reason=ctx.lastReason or "pickup_no_available_driver_or_car"
        ctx.retryScanAt=now()+2000
        return
    end
    if ctx.selectedDriver and ctx.selectedDriver~=driver.id
        or ctx.selectedCar and ctx.selectedCar~=car.sqlId then
        ctx.search=nil
    else
        local selectedPlan
        local stop,reason,search=SC.TaxiService.findRoadsideStop(ctx.target,ctx.search,function(candidate)
            local plan,why=D().plan(ctx,driver,car,candidate)
            if not plan then return false,why end
            local path,why=R().path(ctx,driver.actor,ctx.source)
            if not path then return false,why end
            selectedPlan=plan
            return true
        end)
        ctx.search=search
        if search then return end
        if stop then
            ctx.driverId,ctx.carSqlId,ctx.plan,ctx.pickup=driver.id,car.sqlId,selectedPlan,stop
            ctx.ready,ctx.reason=true,nil
            return
        end
        ctx.lastReason=reason
    end
    ctx.scanCar=ctx.scanCar+1
    if ctx.scanCar>#ctx.cars then ctx.scanCar=1 ctx.scanDriver=ctx.scanDriver+1 end
end
function S.request(player,source)
    local ctx=preview
    if active or not ctx or not ctx.ready or player~=human() then return false,"pickup_preview_not_ready" end
    if not SC.HomeTrip.campUnchanged(ctx.camp) then return false,"pickup_camp_changed" end
    local driver=actorFor(ctx)
    local car=carFor(ctx)
    local eligible=false
    for _,record in ipairs(D().drivers(ctx)) do if record.actor==driver then eligible=true end end
    if not eligible then return false,"pickup_driver_unavailable" end
    ctx.party=D().party(player)
    local plan,reason=SC.ExpeditionCar.preflight({SC.Registry.byId(ctx.driverId)},ctx.plan.zone.id,ctx.carSqlId,ctx.pickup)
    if not plan then return false,reason end
    local seats,playerSeat=D().seats(car,ctx.driverId,ctx.party)
    if not seats then return false,playerSeat end
    local reserved,why=SC.Vehicle.reserveService(ctx.requestId,car,seats,playerSeat)
    if not reserved then return false,why end
    local commandSerial=SC.Commands.peek(driver).commandSerial or 0
    local delivered,receipt=contact(ctx,source or ctx.source,"request",false)
    if not delivered then SC.Vehicle.releaseService(ctx.requestId) return false,receipt end
    if preview~=ctx or active or SC.Commands.peek(driver).commandSerial~=commandSerial
        or call(driver,"getVehicle")~=nil or carFor(ctx)~=car then
        SC.Vehicle.releaseService(ctx.requestId) return false,"pickup_request_changed"
    end
    ctx.plan,ctx.seats,ctx.playerSeat=plan,seats,playerSeat
    ctx.actor=driver
    ctx.commandSerial=commandSerial
    ctx.ack=receipt
    ctx.drivers,ctx.cars,ctx.source,ctx.search,ctx.ready=nil,nil,nil,nil,nil
    active,preview=ctx,nil
    phase(ctx,"acquire")
    durable()
    return true
end
function S.radioStatus(source)
    if not active then return false,"pickup_not_active" end
    return contact(active,source,"status",true)
end
function S.updatePickup(source)
    local ctx=active
    if not ctx or ctx.phase~="outbound" and ctx.phase~="waiting_board"
        and ctx.phase~="pickup_handoff" then return false,"pickup_update_unavailable" end
    if call(human(),"getVehicle")~=nil then return false,"pickup_caller_on_foot_required" end
    local at=D().point(human())
    local stopPoint,reason,search=SC.TaxiService.findRoadsideStop(at,ctx.updateSearch,function(candidate)
        local route,why=D().route(ctx,carFor(ctx),candidate,true)
        return route~=nil,why
    end)
    ctx.updateSearch=search
    if search then
        ctx.updateRequested,ctx.updateSource=true,source
        return false,"pickup_finding_road"
    end
    ctx.updateRequested,ctx.updateSource=nil,nil
    if not stopPoint then return false,reason end
    local delivered,why=contact(ctx,source,"update",true)
    if not delivered then return false,why end
    ctx.pickup=stopPoint
    phase(ctx,"acquire_outbound")
    durable()
    return true
end
function S.cancel(source)
    local ctx=active
    if not ctx then return S.closePreview() end
    if ctx.relinquished and (not carFor(ctx) or call(actorFor(ctx),"getVehicle")~=nil
        and call(actorFor(ctx),"getVehicle")~=carFor(ctx)) then return false,"pickup_driver_changed" end
    local delivered,why=contact(ctx,source,"cancel",true)
    if not delivered then return false,why end
    ctx.cancelled=true
    ctx.commandSerial=SC.Commands.peek(actorFor(ctx)).commandSerial or ctx.commandSerial
    ctx.relinquished=nil
    phase(ctx,"drop_wait")
    durable()
    return true
end
function S.retry(source)
    local ctx=active
    if not ctx or ctx.phase~="held" then return false,"pickup_not_held" end
    if ctx.restoring and ctx.restoreHeld then
        ctx.restoreHeld=nil ctx.restoreWaitAt=now()
        phase(ctx,ctx.resumePhase or "acquire")
        durable()
        return true
    end
    if ctx.cleanupHeld and ctx.release then
        local retried,reason=J().retryArrival(ctx)
        if not retried then return false,reason end
        ctx.cleanupHeld=nil ctx.cleanupWaitAt=now()
        phase(ctx,"finish")
        return true
    end
    if ctx.relinquished and (not carFor(ctx) or call(actorFor(ctx),"getVehicle")~=nil
        and call(actorFor(ctx),"getVehicle")~=carFor(ctx)) then return false,"pickup_driver_changed" end
    local delivered,why=contact(ctx,source,"retry",true)
    if not delivered then return false,why end
    if ctx.release then
        local retried,reason=J().retryArrival(ctx)
        if not retried then return false,reason end
    end
    ctx.commandSerial=SC.Commands.peek(actorFor(ctx)).commandSerial or ctx.commandSerial
    ctx.relinquished=nil
    ctx.carSaveAttempts,ctx.carSaveAt,ctx.suspended=nil,nil,nil
    local resume=ctx.resumePhase or "acquire_return"
    if resume=="outbound" then resume="acquire_outbound"
    elseif resume=="ride" then resume="ride_start"
    elseif resume=="returning" then resume="acquire_return" end
    if resume=="finish" or resume=="camp_arrival" or resume=="drop_wait" then phase(ctx,resume)
    elseif call(actorFor(ctx),"getVehicle")==nil then ctx.afterBoard=resume phase(ctx,"board_driver")
    else phase(ctx,resume) end
    durable()
    return true
end
function S.depart(target,leaveMissing)
    local ctx=active
    if not ctx or ctx.phase~="waiting_board" then return false,"pickup_not_ready_to_depart" end
    local car=carFor(ctx)
    if not S.isBookedPassenger(human(),car) then return false,"pickup_board_first" end
    if not R().localContact(human(),actorFor(ctx)) then return false,"pickup_driver_unavailable" end
    if not leaveMissing then
        for id,seat in pairs(ctx.seats) do
            local record=SC.Registry.byId(id)
            if id~=ctx.driverId and D().stillComing(id,car) and (not record or call(car,"getCharacter",seat)~=record.actor)
                then return false,"pickup_waiting_for_companions" end
        end
    end
    local route,reason=D().route(ctx,car,target,true)
    if not route then return false,reason end
    local bay=ctx.plan.departure
    if (target.x-bay.x)^2+(target.y-bay.y)^2>.25 then target=route.exit end
    ctx.destination=copy(target)
    phase(ctx,"ride_start")
    durable()
    return true
end
function S.departHome(leaveMissing)
    if not active then return false,"pickup_not_active" end
    if not SC.HomeTrip.campUnchanged(active.camp) then return false,"pickup_camp_changed" end
    local target={x=active.camp.core.x,y=active.camp.core.y,z=0}
    -- The passenger gets out at the original car bay, with its proven access.
    target=copy(active.plan.departure)
    return S.depart(target,leaveMissing)
end
function S.step(actor,player,snapshot)
    local ctx=active
    if not ctx or actor~=actorFor(ctx) then return nil end
    if ctx.relinquished then return nil end
    if ctx.suspended then return nil end
    if ctx.reason=="pickup_new_player_order" or ctx.reason=="pickup_driver_changed" then return nil end
    if SC.Logistics and SC.Logistics.busy(actor) then
        local released,reason=SC.Logistics.yieldToWork(actor)
        if not released then
            local record=SC.Registry.byId(ctx.driverId)
            SC.Logistics.update(actor,player,record and record.runtime or {})
            return true,reason
        end
    end
    if not ctx.workYielded then
        if SC.BaseWork then
            local cancelled,reason=SC.BaseWork.cancel(actor,"pickup_departure")
            if not cancelled then return true,reason end
        end
        if SC.Decision and SC.Decision.cancelWork then
            local cancelled,reason=SC.Decision.cancelWork(actor,"pickup_departure")
            if not cancelled then return true,reason end
        end
        ctx.workYielded=true
    end
    local car=carFor(ctx)
    if ctx.phase=="board_driver" and car then
        return SC.ExpeditionCar.boardMember(actor,{car=car,seat=0,sqlId=ctx.carSqlId,
            permittedPassenger=S.isBookedPassenger(human(),car) and human() or nil},snapshot)
    elseif ctx.phase=="exit_driver" and car then
        return SC.Vehicle.exit(actor,car,0,{playerCommand=true})
    elseif ctx.phase=="camp_arrival" then
        local a=ctx.camp.arrival
        return SC.Navigation.request(actor,{x=(a.x1+a.x2+1)/2,y=(a.y1+a.y2+1)/2,z=a.z},"walk",
            {action="pickup_camp_arrival",arrivalDistance=1,continuousApproach=true})
    elseif ctx.phase~="acquire" and ctx.phase~="acquire_outbound" and ctx.phase~="acquire_return"
        and ctx.phase~="finish" then
        U().stop(actor)
    end
    return true,"pickup_"..ctx.phase
end
function S.noteDeath(actor)
    if S.isDriver(actor) then active.deadActor=actor active.reason="pickup_driver_died" end
end
local function releaseEnded(ctx,result)
    if SC.BaseWatch then
        local resumed=SC.BaseWatch.resumeUntransferredPickup and SC.BaseWatch.resumeUntransferredPickup(ctx.requestId)
        if not resumed then SC.BaseWatch.finishPickupPause(ctx.requestId) end
    end
    local released,reason=J().releaseReservation(ctx)
    if not released then return false,reason end
    J().clearCarSave(ctx)
    SC.Vehicle.releaseService(ctx.requestId)
    outcome={requestId=ctx.requestId,driverId=ctx.driverId,carId=ctx.carSqlId,result=result}
    active=nil
    durable()
    return true
end
function S.endHere()
    local ctx=active
    if not ctx then return false,"pickup_not_active" end
    local actor=actorFor(ctx)
    if not R().localContact(human(),actor) then return false,"pickup_primary_view_pending" end
    if actor and not ctx.relinquished and SC.Driving.isDriving(actor) then
        local okay,reason=SC.Driving.stop(actor,"pickup_ended_locally")
        if not okay then return false,reason end
    end
    local released,reason=J().releaseLocal(ctx,actor)
    if not released then return false,reason end
    return releaseEnded(ctx,"ended")
end
function S.suspendForSurvival(actor,value)
    if S.isDriver(actor) and not active.relinquished then
        local owner=SC.ActionSupervisor and SC.ActionSupervisor.current(actor)
        active.suspended=value==true or owner and (owner.owner=="medical" or owner.owner=="needs") or false
        if active.suspended and active.phase~="held" then held(active,"pickup_survival_priority") end
    end
end
local function startDrive(ctx,car,target,passenger,returning)
    local route,reason=D().route(ctx,car,target,passenger~=nil)
    if not route then return held(ctx,reason) end
    local needsExit=returning or (route.exit.x-target.x)^2+(route.exit.y-target.y)^2>.25
    local goal=needsExit and route.exit or target
    local okay,why=SC.Driving.drive(ctx.actor,goal,{passenger=passenger,speedKmh=passenger and 40 or 30,
        cornerSpeedScale=2,blockWaitMs=6000,roadAccessEntry=route.entry,
        roadAccessExit=needsExit and {entry=route.exit,bay=target} or nil})
    if not okay then return held(ctx,why) end
    ctx.driveStarted=true
    ctx.driveProgressAt,ctx.driveProgressPoint=now(),D().point(car)
    return true
end
local function monitorDrive(ctx,car,target,nextPhase,passenger,returning)
    if not ctx.driveStarted then return startDrive(ctx,car,target,passenger,returning) end
    local job=SC.Driving.jobStatus(ctx.actor)
    local at=D().point(car)
    local last=ctx.driveProgressPoint
    if at and (not last or (at.x-last.x)^2+(at.y-last.y)^2>=.25) then
        ctx.driveProgressAt,ctx.driveProgressPoint=now(),at
    end
    if now()-(ctx.driveProgressAt or now())>=30000 then return held(ctx,"pickup_route_blocked") end
    if job and job.result=="arrived" then
        if not at then return held(ctx,"car_position_unavailable") end
        local bay=ctx.plan.departure
        local parking=returning or (target.x-bay.x)^2+(target.y-bay.y)^2<=.25
        local gap=at and math.sqrt((at.x-target.x)^2+(at.y-target.y)^2) or math.huge
        if parking and (gap>6 or not SC.ExpeditionCar.fitsParking(car,ctx.plan.zone,ctx.seats)) then
            ctx.finalApproachSince=ctx.finalApproachSince or now()
            if now()-ctx.finalApproachSince>120000 then return held(ctx,"parking_approach_timeout") end
            local clear,reason=SC.ExpeditionCar.accessBetween(car,at,target)
            if not clear then return held(ctx,reason) end
            local fraction=math.min(1,12/math.max(.01,gap))
            local waypoint={x=at.x+(target.x-at.x)*fraction,y=at.y+(target.y-at.y)*fraction,z=0}
            local started,reason=SC.Driving.approach(ctx.actor,waypoint,30000,false,true)
            if not started then return held(ctx,reason) end
            ctx.reason="pickup_parking_approach"
            return true
        end
        local stopped,why=stop(ctx,car)
        if not stopped then ctx.reason=why return end
        local ready,why=D().stopReady(ctx,car,target)
        if not ready then return held(ctx,why) end
        phase(ctx,nextPhase)
    elseif not job or job.result or job.phase=="held" or job.phase=="failed" then
        held(ctx,job and (job.reason or job.result) or "pickup_drive_interrupted")
    end
end
local function finish(ctx,car)
    if not ctx.release then
        local saved,reason=J().carSaved(ctx,car)
        if not saved then
            if reason=="pickup_car_save_failed" then return held(ctx,reason) end
            ctx.reason=reason return
        end
        local resumed,why=J().restoreWatch(ctx,ctx.actor)
        if not resumed then ctx.reason=why return end
    end
    local integration={requestId=ctx.requestId,result="returned",driverId=ctx.driverId,
        carId=ctx.carSqlId,carSaveReceipt=ctx.carSaveReceipt,cancelled=ctx.cancelled==true,
        watchWarning=ctx.watchWarning}
    local function waiting(why)
        ctx.reason=why
        ctx.cleanupWaitAt=ctx.cleanupWaitAt or now()
        if now()-ctx.cleanupWaitAt>=30000 then
            ctx.phase,ctx.resumePhase,ctx.cleanupHeld,ctx.reason="held","finish",true,"pickup_arrival_retry"
        end
    end
    if ctx.release then
        local completed,why=J().finishRemote(ctx,ctx.actor,car,integration)
        if not completed then waiting(why) return end
    elseif SC.ViewSession.owner()=="pickup" then
        local near=SCSplitScreenProbe.canReleaseJoinedLeader()==true
            and SCSplitScreenProbe.primaryRetainsHomeVehicle(car,ctx.carSqlId)==true
        if near then
            -- At home the player owns the parked car; release on foot.
            local okay,slot=pcall(SCSplitScreenProbe.persistJoinedLeaderSlotForReuse)
            if not okay or slot<2 then ctx.reason="pickup_slot_save_failed" return end
            ctx.slotSqlId=slot
            if not ctx.uiDetached then
                local okay=type(destroyPlayerData)=="function" and pcall(destroyPlayerData,ctx.actor)
                if not okay then ctx.reason="pickup_ui_release_pending" return end
                ctx.uiDetached=true
            end
            if SCSplitScreenProbe.releaseJoinedLeader()~=true then ctx.reason="pickup_view_release_pending" return end
            SC.ViewSession.released("pickup",slot)
        else
            local completed,why=J().finishRemote(ctx,ctx.actor,car,integration)
            if not completed then waiting(why) return end
        end
    end
    local released,why=J().releaseReservation(ctx)
    if not released then ctx.reason=why return end
    SC.Vehicle.releaseService(ctx.requestId)
    J().clearCarSave(ctx)
    outcome=integration
    preferred={driverId=ctx.driverId,carSqlId=ctx.carSqlId}
    active=nil
    durable()
end
function S.tick(current)
    current=tonumber(current) or now()
    if preview then
        local ctx=preview
        if ctx.closing or current-ctx.phaseAt>180000 then return S.closePreview() end
        local warmed,reason=J().warm(ctx)
        if warmed then ctx.reason=nil else ctx.reason=reason end
        if warmed and not ctx.ready then scan(ctx) end
    end
    local ctx=active
    if not ctx then return true end
    ctx.player=human()
    ctx.actor=actorFor(ctx)
    if not ctx.player or call(ctx.player,"isDead")==true then return held(ctx,"pickup_caller_unavailable") end
    if ctx.restoring then
        if ctx.restoreHeld then return true end
        ctx.restoreWaitAt=ctx.restoreWaitAt or current
        if current-ctx.restoreWaitAt>=90000 then
            ctx.restoreHeld=true
            return held(ctx,"pickup_restore_retry")
        end
        if not ctx.restoreAnchorAdopted then
            local anchor=ctx.actor and D().point(ctx.actor)
                or SC.Persistence.pendingPickupDriver and SC.Persistence.pendingPickupDriver(ctx.driverId)
            if anchor then ctx.restorePoint=anchor ctx.restoreAnchorAdopted=true end
        end
        local warmed,reason=J().warm(ctx)
        if not warmed then ctx.reason=reason return true end
        if not ctx.actor then ctx.reason="pickup_restoring_driver" return true end
        if ctx.relinquished then
            local joined,reason=J().acquire(ctx,ctx.actor)
            if not joined then ctx.reason=reason return true end
            ctx.restoring=nil
            ctx.restoreWaitAt=nil
        else
            local car=carFor(ctx)
            if not car then ctx.reason="pickup_loading_car" return true end
            if call(car,"getScriptName")~=ctx.plan.script then return held(ctx,"pickup_car_identity_changed") end
            local claimed,reason=SC.Vehicle.reserveService(ctx.requestId,car,ctx.seats,ctx.playerSeat)
            if not claimed then return held(ctx,reason) end
            local joined,reason=J().acquire(ctx,ctx.actor)
            if not joined then ctx.reason=reason return true end
            ctx.restoring=nil
            local savedPhase=ctx.phase
            if savedPhase=="held" then ctx.phaseAt=current return true end
            if call(ctx.actor,"getVehicle")==nil then
                if savedPhase=="camp_arrival" or savedPhase=="finish" or savedPhase=="drop_wait" then
                    ctx.phaseAt=current
                elseif savedPhase=="exit_driver" or savedPhase=="parked" then phase(ctx,"camp_arrival")
                else
                    ctx.afterBoard=savedPhase=="ride" and "ride_start"
                        or savedPhase=="outbound" and "outbound"
                        or savedPhase=="returning" and "returning"
                        or savedPhase=="waiting_board" and "pickup_handoff" or savedPhase
                    phase(ctx,"board_driver")
                end
            end
        end
    end
    if ctx.relinquished then
        local released=J().releaseLocal(ctx,ctx.actor)
        if released then return releaseEnded(ctx,"ended") end
        return true
    end
    if ctx.release and ctx.cleanupHeld then return true end
    -- The durable native arrival owns this exact actor after Registry detaches
    -- it. Finish that frozen transaction before ordinary live-driver checks.
    if ctx.phase=="finish" and ctx.release then finish(ctx,carFor(ctx)) return true end
    if not ctx.actor then return held(ctx,"pickup_driver_unavailable") end
    if call(ctx.actor,"isDead")==true then
        ctx.deadActor=ctx.actor
        SC.Driving.stop(ctx.actor,"pickup_driver_died")
        local finalized={schema=1,state="idle",sequence=sequence,
            outcome={requestId=ctx.requestId,result="driver_lost",driverId=ctx.driverId,carId=ctx.carSqlId}}
        local okay,reason=J().finishDead(ctx,ctx.actor,finalized)
        if not okay then ctx.reason=reason return true end
        return releaseEnded(ctx,"driver_lost")
    end
    local command=SC.Commands.peek(ctx.actor)
    if not command then return held(ctx,"pickup_driver_unavailable") end
    if command.commandSerial~=ctx.commandSerial then return held(ctx,"pickup_new_player_order") end
    local car=carFor(ctx)
    if not car then return held(ctx,"pickup_car_unavailable") end
    if call(car,"getScriptName")~=ctx.plan.script then return held(ctx,"pickup_car_identity_changed") end
    if call(car,"getDriver")~=nil and call(car,"getDriver")~=ctx.actor then return held(ctx,"pickup_driver_changed") end
    if ctx.phase=="held" then stop(ctx,car) return true end
    if ctx.suspended then return true end
    local purposeful=ctx.phase=="waiting_board" or ctx.phase=="drop_wait"
    local travelling=ctx.phase=="outbound" or ctx.phase=="ride" or ctx.phase=="returning"
    if not purposeful and not travelling and current-(ctx.phaseAt or current)>180000 then
        return held(ctx,"pickup_wait_timed_out")
    end
    if ctx.updateRequested then
        ctx.updateRequested=nil
        local changed,reason=S.updatePickup(ctx.updateSource)
        if reason~="pickup_finding_road" then
            ctx.updateSource,ctx.updateSearch=nil,nil
            if SC.PickupUI then SC.PickupUI.note(ctx.player,changed,reason) end
        end
    end
    if ctx.phase=="acquire" or ctx.phase=="acquire_outbound" or ctx.phase=="acquire_return" then
        local stopped,reason=stop(ctx,car)
        if not stopped then ctx.reason=reason return true end
        local joined,reason=J().acquire(ctx,ctx.actor)
        if not joined then ctx.reason=reason
        else
            local reserved,reason=SC.Vehicle.reserveService(ctx.requestId,car,ctx.seats,ctx.playerSeat)
            if not reserved then return held(ctx,reason) end
            local nextPhase=ctx.phase=="acquire_return" and "returning" or "outbound"
            if call(ctx.actor,"getVehicle")==nil then ctx.afterBoard=nextPhase phase(ctx,"board_driver")
            else phase(ctx,nextPhase) end
        end
    elseif ctx.phase=="board_driver" then
        if call(car,"getDriver")==ctx.actor then
            local key,reason=SC.ExpeditionCar.ensureDriverKey({SC.Registry.byId(ctx.driverId)},car)
            if not key then return held(ctx,reason) end
            phase(ctx,ctx.afterBoard or "outbound")
            ctx.afterBoard=nil
        end
    elseif ctx.phase=="outbound" then monitorDrive(ctx,car,ctx.pickup,"pickup_handoff")
    elseif ctx.phase=="pickup_handoff" then
        if SC.Vehicle.unlockPassengerDoors then
            local opened,reason=SC.Vehicle.unlockPassengerDoors(ctx.actor,car)
            if not opened then ctx.reason=reason return true end
        end
        local okay,reason=J().releaseNear(ctx,ctx.actor,car)
        if okay then phase(ctx,"waiting_board") durable() else ctx.reason=reason end
    elseif ctx.phase=="waiting_board" then
        stop(ctx,car)
        if S.isBookedPassenger(human(),car) then
            local actual=tonumber(call(car,"getSeat",human()))
            if actual~=ctx.playerSeat then
                if call(car,"getCharacter",ctx.playerSeat)~=nil then return held(ctx,"pickup_seat_changed") end
                local seats=S.copy(ctx.seats)
                for id,seat in pairs(seats) do if seat==actual then seats[id]=ctx.playerSeat end end
                local reserved,reason=SC.Vehicle.reserveService(ctx.requestId,car,seats,actual)
                if not reserved then return held(ctx,reason) end
                ctx.seats,ctx.playerSeat=seats,actual
            end
        end
        if S.isBookedPassenger(human(),car) and not ctx.boardNotified then
            ctx.boardNotified=true
            if SC.PickupUI then SC.PickupUI.open(human(),nil) end
        end
    elseif ctx.phase=="ride_start" then
        if not S.isBookedPassenger(human(),car) then return held(ctx,"pickup_passenger_left") end
        local released,reason=stop(ctx,car)
        if not released then ctx.reason=reason return true end
        if SC.ViewSession.owner()=="pickup" then
            local released,reason=J().releaseNear(ctx,ctx.actor,car)
            if not released then ctx.reason=reason return true end
        end
        phase(ctx,"ride")
    elseif ctx.phase=="ride" then
        if not S.isBookedPassenger(human(),car) then phase(ctx,"drop_wait")
        else monitorDrive(ctx,car,ctx.destination,"drop_wait",human()) end
    elseif ctx.phase=="drop_wait" then
        local stopped,reason=stop(ctx,car)
        if not stopped then ctx.reason=reason return true end
        if not D().passengersEmpty(car) then ctx.reason="pickup_waiting_for_passengers_to_exit" return true end
        phase(ctx,"acquire_return")
    elseif ctx.phase=="returning" then
        if not D().passengersEmpty(car) then return held(ctx,"pickup_return_has_passengers") end
        if not SC.HomeTrip.campUnchanged(ctx.camp) then return held(ctx,"pickup_camp_changed") end
        local at=D().point(car)
        local home=ctx.plan.departure
        local alreadyHome=at and (at.x-home.x)^2+(at.y-home.y)^2<=36
            and SC.Vehicle.isStationary(car) and SC.ExpeditionCar.fitsParking(car,ctx.plan.zone,{[ctx.driverId]=0})
        if alreadyHome then
            local stopped,reason=stop(ctx,car)
            if stopped then phase(ctx,"parked") else ctx.reason=reason end
        else monitorDrive(ctx,car,home,"parked",nil,true) end
    elseif ctx.phase=="parked" then
        local fits,reason=SC.ExpeditionCar.fitsParking(car,ctx.plan.zone,{[ctx.driverId]=0})
        if not fits then return held(ctx,reason) end
        phase(ctx,"exit_driver")
    elseif ctx.phase=="exit_driver" then
        if call(ctx.actor,"getVehicle")==nil then phase(ctx,"camp_arrival") end
    elseif ctx.phase=="camp_arrival" then
        local at=D().point(ctx.actor)
        local a=ctx.camp.arrival
        if at and math.floor(at.z)==a.z and at.x>=a.x1 and at.x<a.x2+1
            and at.y>=a.y1 and at.y<a.y2+1 then
            U().stop(ctx.actor)
            SC.Commands.resumeBaseDutyIfUnchanged(ctx.driverId,ctx.commandSerial,ctx.camp.id)
            phase(ctx,"finish")
        end
    elseif ctx.phase=="finish" then finish(ctx,car)
    end
    return true
end

S.copy=copy
function S.prepareReset()
    local ctx=active or preview
    if not ctx then return true end
    if ctx.actor and SC.Driving.isDriving(ctx.actor) then
        local stopped,reason=SC.Driving.stop(ctx.actor,"pickup_world_exit")
        if not stopped then return false,reason end
    end
    return J().prepareReset()
end
function S.reset()
    if active then SC.Vehicle.releaseService(active.requestId) end
    active,preview,outcome,preferred=nil,nil,nil,nil
    sequence=0
    J().reset() R().reset()
    return true
end
-- The journal owns validation and restores only scalar ids and agreed orders.
function S.journalState() return active,outcome,preferred,sequence end
function S.setJournal(value,last,pair,serial)
    active,outcome,preferred,sequence=value,last,pair,serial
    if value then
        value.restoring=true value.phaseAt=now() value.player=human()
        value.restoreHeld=value.phase=="held" and value.reason=="pickup_restore_retry" or nil
        J().setContext(value)
        return J().reserve(value)
    end
    return true
end
return S
