-- SPDX-License-Identifier: MIT
-- Loads after expedition_car_fixture.lua and SCExpeditionCar.lua. No native
-- objects are constructed: these controls prove the read-only field contract.
local SC,T=SurvivorCompanion,CAR_TEST
local Car=SC.ExpeditionCar
local checks=0
local function check(value,label) checks=checks+1 assert(value,"home car "..checks..": "..label) end
local function distance(a,b) return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2) end
local transfers=0
local transfer=SC.GameplayUtil.transferItemVerified
SC.GameplayUtil.transferItemVerified=function(...) transfers=transfers+1 return transfer(...) end
SC.Names={displayName=function(record) return record.name or record.id end}
SC.HomeTrip={carStopReady=function()
    if T.stopSavePending then return false,"home_car_save_pending" end
    return true
end}
T.base.core={x=100,y=100,z=0}
T.key=nil T.fuel=10 T.entryX,T.entryY=400,100
local car=T.car(44,400,100)
local parts={}
for _,id in ipairs({"Engine","TireFrontLeft","TireFrontRight","TireRearLeft","TireRearRight","GasTank"}) do
    local part={condition=90,item={}}
    function part:getCondition() return self.condition end
    function part:getInventoryItem() return self.item end
    function part:getContainerContentAmount() return T.fuel end
    function part:getContainerCapacity() return 40 end
    parts[id]=part
end
function car:getPartById(id) return parts[id] end
local installed={[0]=true,[1]=false,[2]=true,[3]=true}
function car:isSeatInstalled(seat) return installed[seat]==true end
T.cars={car}
for index,record in ipairs(T.team) do
    record.actor.x,record.actor.y,record.actor.z=397+index,100,0
    function record.actor:getZ() return self.z end
    function record.actor:getVehicle() return self.car end
end
T.player={inventory={items={}},getVehicle=function(self) return self.car end}
local key={container=T.team[2].actor.inventory,getKeyId=function() return 44 end,
    getContainer=function(self) return self.container end,getID=function() return 501 end}
key.container.items={key}
SC.ExpeditionRoute.planFromPoint=function(origin,target)
    T.routeCalls[#T.routeCalls+1]={origin=origin,destination=target}
    if T.routeFailure then return nil,T.routeFailure end
    return {points={{x=origin.x,y=origin.y,z=0,width=T.roadWidth or 8,street="Actual Road"},
        {x=target.x,y=target.y,z=0,width=T.roadWidth or 8,street="Actual Road"}},roadLength=distance(origin,target)},nil,
        {entryX=origin.x,entryY=origin.y,exitX=target.x,exitY=target.y}
end
local plan,reason,review=Car.preflightField(T.team,car,T.base)
check(plan and not reason and plan.field and plan.homeStop.kind=="parking","field car outside all camp parking can drive home")
check(plan.seats.leader==0 and plan.seats.mate==2 and review.seats==3,"removed seat is skipped; actual installed seats are counted")
check(plan.keyHolderId=="mate" and plan.fuelPercent==25 and plan.requiredFuelPercent>0,"review reports actual key holder and route fuel reserve")
check(plan.homeStop.provisional and plan.homeStop.clearanceOnArrival,"marked/mapped review never claims loaded arrival clearance")
check(transfers==0 and not T.team[1].actor.car and not T.team[2].actor.car and car.x==400 and not car.engine,"preflight does not move keys, actors, seats, car or engine")
installed[1],T.doorBlocked=true,1
local accessible=Car.preflightField(T.team,car,T.base)
check(accessible and accessible.seats.mate==2,
    "Send Home uses a reachable rear seat when the installed front passenger door is blocked")
T.doorBlocked=0
check(select(2,Car.preflightField(T.team,car,T.base))=="door_inaccessible",
    "Send Home still requires an accessible driver door")
T.doorBlocked=nil T.blockedDoors={[1]=true,[2]=true,[3]=true}
check(select(2,Car.preflightField(T.team,car,T.base))=="door_inaccessible",
    "Send Home refuses a car when every passenger door is blocked")
T.blockedDoors=nil
T.team[2].actor.car,T.team[2].actor.seat=car,3 car.occupied[3]=T.team[2].actor
T.doorBlocked=3
accessible=Car.preflightField(T.team,car,T.base)
check(accessible and accessible.seats.mate==3,
    "an already seated traveller keeps the exact seat despite another available seat")
T.team[2].actor.car,T.team[2].actor.seat=nil,nil car.occupied[3]=nil
installed[1],T.doorBlocked=false,nil
local calls=#T.routeCalls
local rows=Car.fieldCandidates(T.team,T.player)
check(#rows==1 and rows[1].vehicle==car and rows[1].canUse and #T.routeCalls==calls,"cheap candidates do not plan a route")
local signature=Car.fieldFingerprint(car,T.team,T.player)
car.occupied[3]={id="outsider"}
check(Car.fieldFingerprint(car,T.team,T.player)~=signature and select(2,Car.preflightField(T.team,car,T.base))=="car_has_other_occupants","outsiders invalidate review and block dispatch")
car.occupied[3]=nil
car.occupied[0]=T.team[2].actor
check(select(2,Car.preflightField(T.team,car,T.base))=="field_driver_mismatch","an already occupied crew driver requires selecting that actual driver")
car.occupied[0]=nil
T.team[1].actor.car,T.team[1].actor.seat=car,2 car.occupied[2]=T.team[1].actor
check(select(2,Car.preflightField(T.team,car,T.base))=="field_driver_mismatch","a seated passenger leader is not silently moved to the wheel")
T.team[1].actor.car,T.team[1].actor.seat=nil,nil car.occupied[2]=nil
T.player.car=car
check(select(2,Car.preflightField(T.team,car,T.base))=="player_car","the real player must leave the selected car")
T.player.car=nil
T.ready=false
check(not Car.preflightField(T.team,car,T.base),"a moving field car is refused")
T.ready=true
parts.Engine.condition=0
check(select(2,Car.preflightField(T.team,car,T.base))=="engine_unusable","broken engine blocks field trip")
parts.Engine.condition=90 parts.TireRearRight.item=nil
check(select(2,Car.preflightField(T.team,car,T.base))=="wheel_unusable","missing wheel blocks field trip")
parts.TireRearRight.item={}
installed[2],installed[3]=false,false
check(select(2,Car.preflightField(T.team,car,T.base))=="too_few_seats","nominal maximum seats cannot replace missing installed seats")
installed[2],installed[3]=true,true
key.container.items={}
car.hotwired=true
check(select(2,Car.preflightField(T.team,car,T.base))=="driver_needs_key","hotwire/ignition cannot fabricate the required trip-held physical key")
T.player.inventory.items={key} key.container=T.player.inventory
check(select(2,Car.preflightField(T.team,car,T.base))=="driver_needs_key_from_player","player-only key is not transferred during review")
T.player.inventory.items={} key.container=T.team[2].actor.inventory key.container.items={key} car.hotwired=false
T.fuel=.0001
check(select(2,Car.preflightField(T.team,car,T.base))=="fuel_insufficient","nonempty fuel still needs one-way route plus reserve")
T.fuel=10
T.routeFailure="NO_ROUTE"
check(select(2,Car.preflightField(T.team,car,T.base))=="NO_ROUTE","failed mapped route is not replaced by invented road travel")
T.routeFailure=nil
plan=assert(Car.preflightField(T.team,car,T.base))
calls=#T.routeCalls
local prepared=Car.prepareField(T.team,car,T.base,{reviewedPlan=plan})
check(prepared and #T.routeCalls==calls and transfers==1 and key.container==T.team[1].actor.inventory,
    "unchanged reviewed plan reuses route and transfers the same real key only at dispatch")
check(not T.team[1].actor.car and not T.team[2].actor.car and car.x==400,"prepare does not fake seat boarding or car travel")
installed[1]=true
local seatReview=assert(Car.preflightField(T.team,car,T.base))
check(seatReview.seats.mate==1,"review initially selects the clear front passenger seat")
T.doorBlocked=1 calls=#T.routeCalls
local changedSeat=Car.prepareField(T.team,car,T.base,{reviewedPlan=seatReview})
check(changedSeat and changedSeat.seats.mate==2 and #T.routeCalls==calls,
    "cached Send Home dispatch uses the freshly reachable rear seat without replanning the road route")
installed[1],T.doorBlocked=false,nil
plan=assert(Car.preflightField(T.team,car,T.base))
local oldX2=T.zone.x2 T.zone.x2=oldX2-1
calls=#T.routeCalls
check(select(2,Car.prepareField(T.team,car,T.base,{reviewedPlan=plan}))=="home_review_changed" and #T.routeCalls==calls,
    "changed marked stop refuses cached dispatch without replanning a different stop")
T.zone.x2=oldX2
plan=assert(Car.preflightField(T.team,car,T.base))
local descriptor=assert(Car.fieldDescriptor(plan,{id=T.base.id,core=T.base.core}))
check(descriptor.field and descriptor.leg=="home" and descriptor.state=="walking_to_car" and descriptor.departure.x==plan.homeStop.point.x,
    "field descriptor starts the shared physical home leg at the chosen stop")
local saved=assert(Car.copyDescriptor(descriptor,T.team,"leader"))
check(saved.homeStop~=descriptor.homeStop and saved.homeStop.boundaries~=descriptor.homeStop.boundaries,"stable field stop metadata never aliases live review data")
local resumed=assert(Car.restoreDescriptor(saved,T.team,"leader"))
check(resumed.field and resumed.state=="interrupted_by_load" and resumed.homeStop.kind=="parking","field home leg survives a checked cold interruption")
local mission={roster=T.team,leader=T.team[1],members={[T.team[1].actor]=true,[T.team[2].actor]=true},scout={vehicle=descriptor,phase="walking_to_car",kind="home"}}
T.mission=mission
Car.pulse(mission,0,0)
check(descriptor.state=="boarding_home" and mission.scout.phase=="boarding_home","field trip never takes the normal outbound site leg")
check(not Car.homeArrivalReady(mission),"stopped but still boarding car cannot finish Home")
descriptor.state="home_wait" car.x,car.y=descriptor.departure.x,descriptor.departure.y
check(Car.homeArrivalReady(mission),"only an actually parked stopped empty engine-off car can finish Home")
car.engine=true
check(not Car.homeArrivalReady(mission),"running engine blocks remote Home completion")
car.engine=false
local parking=T.base.zones[2] T.base.zones={T.base.zones[1]}
car.x,car.y=400,100
local roadside=assert(Car.preflightField(T.team,car,T.base))
check(roadside.homeStop.kind=="roadside" and distance(roadside.homeStop.point,T.base.core)<=40
    and roadside.homeStop.point.x>111,"roadside selection is mapped and wholly outside the camp boundary")
local roadDescriptor=assert(Car.fieldDescriptor(roadside,{id=T.base.id,core=T.base.core}))
mission.scout.vehicle=roadDescriptor
roadDescriptor.state="parking_home" car.x,car.y=roadDescriptor.departure.x,roadDescriptor.departure.y
Car.pulse(mission,100,0)
check(roadDescriptor.state=="unloading_home","roadside endpoint still needs loaded footprint and exit validation")
T.stopSavePending=true
roadDescriptor.lastFailure={reason="turn_failed",obstacle="solid",at={x=car.x,y=car.y,z=0}}
local parkingFailure=roadDescriptor.lastFailure
Car.pulse(mission,101,0)
check(roadDescriptor.state=="unloading_home" and roadDescriptor.blocker=="home_car_save_pending",
    "pending real vehicle save prevents home_wait and walking away")
T.stopSavePending=false Car.pulse(mission,102,0)
check(roadDescriptor.state=="home_wait" and mission.scout.phase=="inbound" and roadDescriptor.engineStopped
    and roadDescriptor.blocker==nil and roadDescriptor.lastFailure==parkingFailure,
    "confirmed roadside save clears only the resolved wait and preserves the original parking failure")
check(Car.homeArrivalReady(mission),"verified roadside stop is ready while strict walking arrival remains Home-owned")
car.x,car.y=100,100
check(not Car.fieldStopClear(mission,roadDescriptor,car),"an arbitrary inside-camp parked car cannot masquerade as roadside")
car.x,car.y=400,100 T.roadWidth=2
check(select(2,Car.preflightField(T.team,car,T.base))=="home_stop_unavailable","unverified narrow map geometry cannot invent a drivable roadside bay")
T.roadWidth=nil
local oldAreaX2=T.base.zones[1].x2 T.base.zones[1].x2=150
check(select(2,Car.preflightField(T.team,car,T.base))=="home_stop_unavailable","no outside road within40m remains an honest blocker")
T.base.zones[1].x2=oldAreaX2 T.base.zones[2]=parking
mission.scout.vehicle=descriptor descriptor.state="driving_home"
for _,record in ipairs(T.team) do local seat=descriptor.seats[record.id] record.actor.car,record.actor.seat=car,seat car.occupied[seat]=record.actor end
car.engine=true T.driving=true T.stopPending=true
SC.Driving.isDriving=function(actor) return T.driving and actor==T.team[1].actor end
check(not Car.cancelField(mission,200) and T.team[1].actor.car==car,"near recall waits for native driving release before exiting")
local beforeX,beforeY=car.x,car.y
T.stopSavePending=true
check(not Car.cancelField(mission,201) and descriptor.state=="driving_home" and not T.team[1].actor.car,
    "stopped unseated recall still waits for actual vehicle save before walking")
T.stopSavePending=false
check(Car.cancelField(mission,201) and descriptor.state=="abandoned" and descriptor.engineStopped
    and not T.team[1].actor.car and not T.team[2].actor.car and not car.engine and car.x==beforeX and car.y==beforeY,
    "near recall safely stops engine and physically unseats crew without moving the car")

-- A failed field drive keeps the crew aboard for recovery before the existing
-- stopped-car save barrier can authorize a physical walking fallback.
descriptor.state,mission.scout.phase="driving_home","driving_home"
for _,record in ipairs(T.team) do local seat=descriptor.seats[record.id] record.actor.car,record.actor.seat=car,seat car.occupied[seat]=record.actor end
car.engine=true T.driving=false
SC.Driving.status=function() return {obstacleKind="tree"} end
T.driveStatus={result="failed",reason="no_route",attempts=3}
Car.pulse(mission,300,0)
local roadFailure=descriptor.lastFailure
check(descriptor.state=="held" and descriptor.blocker=="no_route" and descriptor.recovery.kind=="road"
    and roadFailure.reason=="no_route" and roadFailure.obstacle=="tree"
    and T.team[1].actor.car==car and T.team[2].actor.car==car,
    "Send Home retains the exact seated crew and route failure during car recovery")
local recoverySave=assert(Car.copyDescriptor(descriptor,T.team,"leader"))
local recoveryReload=assert(Car.restoreDescriptor(recoverySave,T.team,"leader"))
check(recoverySave.field and recoverySave.recovery.remainingMs==300000
    and recoveryReload.state=="interrupted_by_load" and recoveryReload.resumeState==nil
    and recoveryReload.recovery.remainingMs==300000 and recoveryReload.recovery.lastAt==nil,
    "field recovery persists its remaining allowance without reusing native timers or a drive lease")
T.driveStatus=nil T.stopSavePending=true
Car.pulse(mission,299999,0)
check(descriptor.state~="fallback_unloading" and descriptor.state~="abandoned"
    and T.team[1].actor.car==car and T.team[2].actor.car==car,
    "Send Home does not unload before the five-minute recovery allowance expires")
Car.pulse(mission,300300,0)
check(descriptor.state=="fallback_unloading" and T.team[1].actor.car==car,
    "recovery exhaustion still leaves physical stop and exit verification pending")
Car.pulse(mission,300301,0)
check(descriptor.state=="fallback_unloading" and mission.scout.phase=="fallback_unloading"
    and descriptor.blocker=="home_car_save_pending" and descriptor.lastFailure==roadFailure
    and not T.team[1].actor.car and not T.team[2].actor.car and not car.engine,
    "pending native save retains the stopped fallback without allowing walking or erasing the driving failure")
T.stopSavePending=false Car.pulse(mission,300302,0)
check(descriptor.state=="abandoned" and mission.scout.phase=="inbound" and descriptor.blocker==nil
    and descriptor.lastFailure==roadFailure and roadFailure.reason=="no_route" and roadFailure.obstacle=="tree",
    "ready native save resumes fallback walking with its original failure and no stale save blocker")
local failureCopy=assert(Car.copyDescriptor(descriptor,T.team,"leader"))
check(failureCopy.blocker==nil and failureCopy.lastFailure.reason=="no_route"
    and failureCopy.lastFailure.obstacle=="tree",
    "abandoned descriptor persists the actual driving failure without a resolved save warning")
descriptor.state,descriptor.blocker="fallback_unloading","exit_blocked"
mission.scout.phase="fallback_unloading"
Car.pulse(mission,303,0)
check(descriptor.state=="abandoned" and descriptor.blocker=="exit_blocked" and descriptor.lastFailure==roadFailure,
    "successful field save does not clear an unrelated car blocker")

do
    local first="parking bay requires a clear forward approach"
    local parkingTrip=assert(Car.fieldDescriptor(plan,{id=T.base.id,core=T.base.core}))
    parkingTrip.state="parking_home"
    mission.scout.vehicle,mission.scout.phase=parkingTrip,"parking_home"
    car.x,car.y=parkingTrip.departure.x+6,parkingTrip.departure.y
    for _,record in ipairs(T.team) do local seat=parkingTrip.seats[record.id] record.actor.car,record.actor.seat=car,seat car.occupied[seat]=record.actor end
    car.engine=true
    local approach=SC.Driving.approach
    local requests=0
    SC.Driving.approach=function(_,_,_,_,allowAlignment)
        requests=requests+1
        check(allowAlignment==true,"only the field home parking caller opts into bounded alignment")
        T.driveStatus={phase="parking_aligning",managed=true,owned=true,parked=false,firstParkingRefusal=first}
        return true
    end
    T.driveStatus={phase="arrived",result="arrived",managed=true,owned=true,parked=true,
        roadGoal={x=car.x,y=car.y,z=0}}
    Car.pulse(mission,500,0)
    Car.pulse(mission,501,0)
    check(parkingTrip.state=="parking_home" and mission.scout.phase=="parking_home"
        and parkingTrip.parkingAligning and requests==1 and parkingTrip.parkingRefusal==first,
        "alignment keeps the public parking phase, exact crew and first refusal without claiming arrival")
    T.driveStatus={phase="approaching",managed=true,owned=true,parked=false,firstParkingRefusal=first}
    Car.pulse(mission,525,0)
    check(parkingTrip.approachStartedAt==525 and not parkingTrip.parkingAligning and requests==1,
        "a physical alignment leaves the final guarded leg its own bounded approach window")
    T.driveStatus={phase="failed",result="failed",reason="parking_alignment_room_changed",
        managed=true,owned=true,parked=true,firstParkingRefusal=first}
    Car.pulse(mission,526,0)
    check(parkingTrip.state=="fallback_unloading" and parkingTrip.blocker=="parking_alignment_room_changed"
        and parkingTrip.lastFailure.reason==first and parkingTrip.parkingRefusal==first and requests==1,
        "unsafe alignment preserves its first actual refusal and takes the physical walking fallback")
    local transferCount=transfers
    T.stopSavePending=true Car.pulse(mission,527,0)
    check(parkingTrip.state=="fallback_unloading" and parkingTrip.blocker=="home_car_save_pending"
        and not car.engine and not T.team[1].actor.car and not T.team[2].actor.car and transfers==transferCount,
        "parking fallback stops and unseats everyone but cannot walk or claim cargo movement before native save")
    T.stopSavePending=false Car.pulse(mission,528,0)
    check(parkingTrip.state=="abandoned" and mission.scout.phase=="inbound" and parkingTrip.blocker==nil
        and parkingTrip.lastFailure.reason==first and requests==1,
        "confirmed stopped-car save permits walking with the truthful parking failure retained")
    check(Car.copyDescriptor(parkingTrip,T.team,"leader").parkingRefusal==first,
        "the original parking refusal survives descriptor persistence")

    parkingTrip=assert(Car.fieldDescriptor(plan,{id=T.base.id,core=T.base.core}))
    mission.scout.vehicle,mission.scout.phase=parkingTrip,"driving_home"
    parkingTrip.state="driving_home"
    T.driveStatus={phase="released",result="arrived",managed=true,owned=false,parked=true,
        reason="parking_approach_rejected",firstParkingRefusal=first}
    Car.pulse(mission,600,0)
    check(parkingTrip.state=="fallback_unloading" and parkingTrip.lastFailure.reason==first and requests==1,
        "a released arrived outcome cannot be reused as authority for another parking drive")
    parkingTrip.state,parkingTrip.resumeState,parkingTrip.blocker="held","parking_home","parking_requires_arrived_drive"
    Car.pulse(mission,601,0)
    check(parkingTrip.state=="fallback_unloading" and parkingTrip.lastFailure.reason==first and requests==1,
        "a legacy held parking refusal cannot cycle back into the same released arrived outcome")

    parkingTrip.state,parkingTrip.resumeState="parking_home",nil
    parkingTrip.position={x=car.x,y=car.y,z=0}
    parkingTrip.approachStartedAt,parkingTrip.parkingAligning=600,true
    local savedParking=assert(Car.copyDescriptor(parkingTrip,T.team,"leader"))
    local restoredParking=assert(Car.restoreDescriptor(savedParking,T.team,"leader"))
    check(restoredParking.state=="interrupted_by_load" and not restoredParking.approachStartedAt
        and not restoredParking.parkingAligning and restoredParking.parkingRefusal==first,
        "save/load retains the physical car and refusal but never an ephemeral alignment job or token")
    mission.scout.vehicle,mission.scout.phase=restoredParking,"interrupted_by_load"
    Car.pulse(mission,700,0)
    check(restoredParking.state=="boarding_home" and requests==1 and not car.engine
        and not T.team[1].actor.car and not T.team[2].actor.car,
        "loaded parking restart revalidates the exact stopped car and starts fresh boarding rather than reusing old arrival authority")
    savedParking.state,savedParking.resumeState="held","parking_home"
    local restoredHeld=assert(Car.restoreDescriptor(savedParking,T.team,"leader"))
    check(restoredHeld.state=="interrupted_by_load" and restoredHeld.resumeState==nil,
        "a saved held home parking state also revalidates a fresh owner after load")
    SC.Driving.approach=approach T.driveStatus=nil
end
do
    local heldTrip=assert(Car.fieldDescriptor(plan,{id=T.base.id,core=T.base.core}))
    heldTrip.state="driving_home"
    mission.scout.vehicle,mission.scout.phase=heldTrip,"driving_home"
    car.x,car.y=400,100
    for _,record in ipairs(T.team) do
        local seat=heldTrip.seats[record.id]
        record.actor.car,record.actor.seat=car,seat car.occupied[seat]=record.actor
    end
    local release,drive,stopOwned=SC.Driving.release,SC.Driving.drive,SC.Driving._stopOwnedVehicle
    local byId=SC.Registry.byId
    local staleLeader,foreignToken=false,false
    SC.Registry.byId=function(id)
        if staleLeader and id==T.team[1].id then return {id=id,actor={}} end
        for _,record in ipairs(T.team) do if record.id==id then return record end end
    end
    local actorStop,navCancel,cancelTransaction=SC.Actor.stop,SC.Navigation.cancel,SC.Vehicle.cancelTransaction
    local stoppedActors,cancelledBoarding,releases=0,0,0
    SC.Actor.stop=function() stoppedActors=stoppedActors+1 return true end
    SC.Navigation.cancel=function() return true end
    SC.Vehicle.cancelTransaction=function() cancelledBoarding=cancelledBoarding+1 return true end
    SC.Driving.release=function()
        releases=releases+1
        if T.radioStopPending then T.radioStopPending=nil return false,"drive_stop_pending" end
        T.driving=false T.driveStatus={phase="released",owned=false,result="interrupted"}
        return true
    end
    SC.Driving._stopOwnedVehicle=function(actor,expected,why)
        if not T.driving then return false,"drive_not_owned" end
        if foreignToken or actor~=T.team[1].actor or expected~=car then return false,"drive_owner_mismatch" end
        return SC.Driving.release(actor,why)
    end
    local malformed={leader=T.team[1],scout={vehicle={field=true,leg="home"}}}
    local called,accepted=pcall(Car.holdHome,malformed,999)
    check(called and accepted==false,"partial Hold context refuses without indexing missing seat/member tables")
    T.driving=true car.engine=true installed[2]=false
    local beforeRelease=releases
    check(select(2,Car.holdHome(mission,999))=="seat_unavailable"
        and releases==beforeRelease+1 and not T.driving
        and car.occupied[0]==T.team[1].actor and car.occupied[2]==T.team[2].actor,
        "an exact owned job brakes before a newly missing passenger seat rejects Hold")
    installed[2]=true heldTrip.radioResumeState,heldTrip.radioHoldCar=nil,nil
    T.driving=true staleLeader=true beforeRelease=releases
    check(select(2,Car.holdHome(mission,999))=="restart_team_unavailable" and releases==beforeRelease and T.driving,
        "stale captured actor identity cannot brake another registered actor's job")
    staleLeader=false foreignToken=true
    check(select(2,Car.holdHome(mission,999))=="drive_owner_mismatch" and releases==beforeRelease and T.driving,
        "a mismatched managed token refuses without falling back to generic native release")
    foreignToken=false car.id=45
    check(select(2,Car.holdHome(mission,999))=="car_not_loaded" and releases==beforeRelease and T.driving,
        "a mismatched loaded car SQL cannot authorize an early native stop")
    car.id=44
    local cargo={getID=function() return 7001 end}
    car.radioCargo=cargo
    local beforeTransfers,beforeRoutes,beforeDrives=transfers,#T.routeCalls,T.driveCalls
    car.engine=true T.driving=true T.radioStopPending=true
    check(not Car.holdHome(mission,1000) and heldTrip.radioResumeState=="driving_home"
        and heldTrip.state=="driving_home" and car.engine and T.team[1].actor.car==car,
        "radio Hold retains the car and seats while native release is still pending")
    T.ready=false
    check(not Car.holdHome(mission,1001) and car.engine and not T.driving,
        "radio Hold waits for physical braking before switching off the engine")
    T.ready=true car.stopDelayed=true
    check(not Car.holdHome(mission,1002) and car.engine and car.engineStops>0,
        "engine shutdown acknowledgement alone cannot complete radio Hold")
    car.stopDelayed=nil car.engine=false
    check(Car.holdHome(mission,1003) and not car.engine and heldTrip.radioHoldCar==car,
        "radio Hold completes only with the exact stopped engine-off car")
    local heldSeat0,heldSeat2=car.occupied[0],car.occupied[2]
    check(Car.pulse(mission,999999,0) and heldTrip.state=="driving_home"
        and car.occupied[0]==heldSeat0 and car.occupied[2]==heldSeat2
        and Car.ownsSeat(T.team[2].actor,car) and car.radioCargo==cargo
        and transfers==beforeTransfers and #T.routeCalls==beforeRoutes and T.driveCalls==beforeDrives,
        "long radio Hold preserves assigned seat authority and exact cargo without driving or timed abandonment")
    local replacement=T.car(44,400,100)
    T.cars={replacement}
    check(select(2,Car.resumeHome(mission,1004))=="car_identity_changed" and heldTrip.radioResumeState,
        "the same SQL number on a replacement loaded object cannot resume a live Hold")
    T.cars={car}
    car.script="Base.Van"
    check(select(2,Car.resumeHome(mission,1004))=="car_identity_changed" and T.driveCalls==beforeDrives,
        "a changed native vehicle script cannot resume the held car")
    car.script=heldTrip.script installed[2]=false
    check(select(2,Car.resumeHome(mission,1004))=="seat_unavailable" and car.occupied[2]==heldSeat2,
        "a missing installed assigned seat blocks resume without moving its passenger")
    installed[2]=true
    car.occupied[3]={id="outsider"}
    check(select(2,Car.resumeHome(mission,1005))=="car_has_other_occupants" and T.driveCalls==beforeDrives,
        "Push on rechecks native occupants before granting throttle")
    car.occupied[3]=nil
    parts.Engine.condition=0
    check(select(2,Car.resumeHome(mission,1006))=="engine_unusable" and heldTrip.radioResumeState,
        "a newly damaged engine keeps the same car held")
    parts.Engine.condition=90 T.routeFailure="NO_ROUTE"
    check(select(2,Car.resumeHome(mission,1007))=="NO_ROUTE" and heldTrip.radioResumeState,
        "Push on cannot replay a stale route when actual-pose route validation fails")
    T.routeFailure=nil
    beforeRelease=releases
    SC.Driving.drive=function() return false,"start_failed" end
    check(select(2,Car.resumeHome(mission,1008))=="start_failed" and heldTrip.radioResumeState
        and releases==beforeRelease+2,
        "a rejected fresh drive is explicitly stopped and retains the held trip for retry")
    SC.Driving.drive=drive
    check(Car.resumeHome(mission,1009) and heldTrip.radioResumeState==nil
        and heldTrip.state=="driving_home" and mission.scout.phase=="driving_home"
        and T.driveCalls==beforeDrives+1 and T.lastGoal==heldTrip.homeRoadEntry
        and T.lastDriveOptions.roadAccessExit.bay==heldTrip.departure
        and car.occupied[0]==heldSeat0 and car.occupied[2]==heldSeat2 and car.radioCargo==cargo,
        "Push on starts a fresh checked home route and preserves the exact car, seats and cargo")

    check(Car.holdHome(mission,1010),"the resumed physical journey can be held again")
    local heldSave=assert(Car.exportDescriptor(heldTrip,T.team,"leader"))
    local cold=assert(Car.restoreDescriptor(heldSave,T.team,"leader"))
    check(cold.radioResumeState=="interrupted_by_load" and cold.state=="interrupted_by_load"
        and cold.radioHoldCar==nil,
        "cold radio Hold preserves intent without importing an old native car pointer or driving job")
    heldSave.radioResumeState="abandoned"
    check(not Car.copyDescriptor(heldSave,T.team,"leader"),"malformed held car metadata cannot grant resume authority")
    for _,record in ipairs(T.team) do
        car.occupied[record.actor.seat]=nil record.actor.car,record.actor.seat=nil,nil
    end
    mission.scout.vehicle,mission.scout.phase=cold,"interrupted_by_load"
    check(Car.holdHome(mission,1011) and not Car.boardingOrderFor(T.team[1].actor)
        and stoppedActors==2 and cancelledBoarding==2,
        "cold Hold stops the on-foot crew and suppresses physical boarding until Push on")
    key.container.items={} key.container=T.team[2].actor.inventory key.container.items={key}
    local oldDrives=T.driveCalls
    check(Car.resumeHome(mission,1012) and cold.state=="boarding_home" and not cold.radioResumeState
        and T.driveCalls==oldDrives and not T.team[1].actor.car and not T.team[2].actor.car
        and key.container==T.team[1].actor.inventory and key:getID()==501,
        "cold Push on revalidates recovery and transfers the same real key before physical boarding")
    check(Car.boardingOrderFor(T.team[1].actor)~=nil,"accepted cold continuation releases the boarding gate")

    mission.scout.vehicle,mission.scout.phase=heldTrip,"driving_home"
    heldTrip.state="driving_home"
    for _,record in ipairs(T.team) do
        local seat=heldTrip.seats[record.id]
        record.actor.car,record.actor.seat=car,seat car.occupied[seat]=record.actor
    end
    car.engine=true T.driving=true
    check(Car.holdHome(mission,1013),"recall fixture begins with a genuine stopped seated radio Hold")
    T.stopSavePending=true
    check(not Car.cancelField(mission,1014) and heldTrip.radioResumeState
        and not T.team[1].actor.car and car.radioCargo==cargo,
        "Hold to Come back physically unloads but retains authority until the car save barrier succeeds")
    T.stopSavePending=false
    check(Car.cancelField(mission,1015) and heldTrip.state=="abandoned"
        and not heldTrip.radioResumeState and not heldTrip.radioHoldCar
        and not T.team[2].actor.car and car.radioCargo==cargo,
        "successful Come back clears the radio hold only after normal stop, exit and durable car handoff")
    SC.Driving.release,SC.Driving.drive,SC.Driving._stopOwnedVehicle=release,drive,stopOwned
    SC.Registry.byId=byId
    SC.Actor.stop,SC.Navigation.cancel,SC.Vehicle.cancelTransaction=actorStop,navCancel,cancelTransaction
    car.radioCargo=nil T.driving=false T.driveStatus=nil
end
print("HOME_CAR_PASS checks="..checks)
