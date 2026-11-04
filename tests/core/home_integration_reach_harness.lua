-- SPDX-License-Identifier: MIT
-- Real Home camp fingerprint, Integration ownership and VehicleUnload.takeExact.
-- Only world geometry, movement/animation receipts and native item containers
-- are fixtures; no delivery, movement permission or transfer result is forced.
local SC,T=SurvivorCompanion,INTEGRATION_TEST
local I,H,V=SC.ExpeditionIntegration,SC.HomeTrip,SC.VehicleUnload
assert(SC.FieldWork and type(SC.FieldWork.unlockTrunkFor)=="function",
    "Home cargo regression requires the real SCFieldWork unlock transaction")
local checks=0
local function check(value,label)
    checks=checks+1 assert(value,"home integration reach "..checks..": "..label)
end
local current
local function inside(value,zone)
    return value and value.z==0 and value.x>=zone.x1 and value.x<zone.x2+1
        and value.y>=zone.y1 and value.y<zone.y2+1
end
local function fixture()
    I.reset() T.actors={} T.storages={} T.moves=0 T.now=T.now+1000
    local area={kind="area",x1=90,y1=90,x2=110,y2=100,z=0}
    local parking={kind="parking",id="home-parking",x1=97,y1=102,x2=104,y2=108,z=0}
    local base={id="camp:1",core={x=100,y=95,z=0},zones={area,parking}}
    local worker=T.actor("home-worker","Home worker",{})
    worker.x,worker.y,worker.z,worker.order=100.5,99.5,0,"follow"
    function worker:getVehicle() return self.vehicle end
    local cargo=T.item("home-cargo-501","tools","Base.NailsBox") cargo.nativeId=501
    function cargo:getID() return self.nativeId end
    local car={sqlId=88,x=100.5,y=105.5,z=0,trunk=T.container({cargo}),engine=false,moving=false}
    function car:getSqlId() return self.sqlId end
    function car:getX() return self.x end
    function car:getY() return self.y end
    function car:getZ() return self.z end
    function car:isEngineRunning() return self.engine end
    function car:isTrunkLocked()
        if current.lockReadFails then error("native lock read unavailable") end
        return self.locked==true
    end
    function car:getMaxPassengers() return 2 end
    function car:isSeatInstalled(seat) return seat==0 or seat==1 end
    function car:getCharacter(seat)
        return worker.vehicle==self and worker.seat==seat and worker or nil
    end
    function car:getSeat(actor) return actor.vehicle==self and actor.seat or -1 end
    function car:getPassengerDoor()
        return {getDoor=function() return {isLocked=function() return self.doorsLocked==true end} end}
    end
    function car:setTrunkLocked(locked)
        current.nativeUnlocks=current.nativeUnlocks+1
        if not current.failUnlock then self.locked=locked end
        if current.failLockReadAfterUnlock then current.lockReadFails=true end
    end
    local f={worker=worker,car=car,cargo=cargo,base=base,area=area,parking=parking,marked=true,
        requests={},visual={},boardRequests=0,exitRequests=0,nativeUnlocks=0}
    current=f
    local camp=assert(H.captureCamp(base))
    f.record={version=1,kind="home",tripId="home-reach-"..T.now,baseId=base.id,homeCamp=camp,
        carId=88,carSaveReceipt={version=1,sqlId=88,tagUUID="lf-home-reach",x=car.x,y=car.y,z=0,
            worldVersion=201,byteLength=500,sha256=string.rep("a",64)},restock=true,requested=1,
        items={{id=cargo.id,nativeId=501,itemType=cargo.fullType,finderId=worker.id,finderName=worker.name,
            carrierKind="trunk",carrierName="Car trunk",returned=false,stored=false,released=false}},
        members={{id=worker.id,name=worker.name,commandSerial=0,restockIndex=1,dutyDone=false,
            cleanupDone=true,restocked={},shortages={}}}}
    T.storage("home-tools","tools",{},99)
    check(I.valid(f.record),"the fixture uses an actual valid Home cargo/camp receipt")
    return f
end
SC.BaseLife.active=function() return current and current.base end
SC.BaseLife.isInside=function(value,kind)
    if not current then return false end
    if kind=="parking" then return current.marked and inside(value,current.parking) or false end
    return inside(value,current.area) or false
end
SC.BaseLife.withinWorkReach=function(value)
    return value and value.z==0 and value.x>=70 and value.x<=130 and value.y>=70 and value.y<=130
end
SC.Vehicle.loadedBySqlId=function(id) return current and not current.unloaded and id==88 and (current.replacement or current.car) or nil end
SC.Vehicle.loadedVehicles=function() return current and not current.unloaded and {current.car} or {} end
SC.Vehicle.isStationary=function(car) return car.moving~=true end
SC.Vehicle.cargoPart=function(car)
    return not current.missingPart and {} or nil,car and not current.missingContainer and car.trunk or nil
end
SC.Vehicle.boardingSquares=function() return {{x=100,y=104,z=0}} end
SC.Vehicle.exit=function(actor,car,seat)
    check(actor==current.worker and car==current.car and seat==actor.seat,
        "the real unlock helper requests exit only for its actual seated worker")
    current.exitRequests=current.exitRequests+1
    return true,"exiting_vehicle"
end
SC.ExpeditionCar={parkingAreas=function() return current.marked and {current.parking} or {} end,
    fitsParking=function(car,zone) return current.marked and inside(car,zone) end,
    boardMember=function(actor,request)
        check(actor==current.worker and request.car==current.car and request.fieldWork==true,
            "the real unlock helper requests normal boarding of its exact car")
        current.boardRequests=current.boardRequests+1
        current.requestedSeat=request.seat
        return true,"boarding_vehicle"
    end}
SC.Driving={hasKey=function(actor,car) return actor==current.worker and car==current.car and current.hasKey==true end}
SC.GameplayUtil.gridSquare=function(x,y,z) return {x=x,y=y,z=z} end
SC.GameplayUtil.isSquareFree=function() return true end
SC.GameplayUtil.safehouseBlocker=function() return nil end
SC.GameplayUtil.distanceSq=function(a,b) return (a.x-b.x)^2+(a.y-b.y)^2 end
SC.GameplayUtil.sameSquare=function(a,b)
    return math.floor(a.x)==math.floor(b.x) and math.floor(a.y)==math.floor(b.y) and a.z==b.z
end
SC.GameplayUtil.move=function(actor,_,intent)
    check(intent.action=="loot_container","only the real trunk animation adapter requests a native action")
    current.visual[actor]="completed" return true
end
SC.NativeActions={visualStatus=function(actor) return current.visual[actor] or "idle" end,
    visualToken=function() return 1 end,clearVisual=function(actor) current.visual[actor]=nil end}
SC.Navigation={requestAny=function(actor,squares,_,intent)
    current.requests[#current.requests+1]={actor=actor,squares=squares,intent=intent}
    return true,"approaching_car_trunk"
end}

local f=fixture()
check(I.wants(f.record,f.worker),"the returned crew member initially owns its cargo at camp")
f.worker.y=101.5
check(not SC.BaseLife.isInside(f.worker) and not SC.BaseLife.isInside(f.worker,"parking")
    and I.wants(f.record,f.worker),"the exact parked-cargo owner survives the unmarked gap before pickup")
local handled,reason=I.update(f.record,f.worker)
local requested=f.requests[1]
check(handled and reason=="approaching_car_trunk" and requested and requested.intent.workCampOnly==true
    and requested.intent.workReach==true and requested.intent.requireSameSquare==true and requested.intent.arrivalDistance==.35
    and f.cargo.container==f.car.trunk and T.moves==0,
    "real takeExact retains ordinary bounded work reach/same-square movement and leaves cargo physical until arrival")
f.worker.y=103.5
check(I.wants(f.record,f.worker),"the same ownership continues on the actual marked parking floor")
check(select(2,I.update(f.record,f.worker))=="car_trunk_looting" and T.moves==0,
    "real takeExact obtains its animation receipt before transfer")
check(select(2,I.update(f.record,f.worker))=="car_item_carried" and T.moves==1
    and f.cargo.container==f.worker.inventory and #f.car.trunk.items==0,
    "the actual exact-item transfer moves one native object out of its original trunk")
f.worker.y=101.5
check(I.wants(f.record,f.worker),"the existing returned-carrier path owns the same receipt while crossing back through the gap")
f.worker.y=99.5
check(select(2,I.update(f.record,f.worker))=="expedition_supply_stored" and T.moves==2
    and f.cargo.container==T.storages[1].container and f.record.items[1].stored==true,
    "return to camp deposits the same native cargo object with a verified storage receipt")
f.worker.y=101.5
check(not I.wants(f.record,f.worker),"completed cargo cannot grant an empty worker permanent reach outside camp")
f.worker.y=99.5
for _=1,6 do I.update(f.record,f.worker) end
check(f.worker.order=="base_duty" and I.summary(f.record).complete,
    "delivery completes ordinary role restock/base duty after the physical return")

f=fixture() f.worker.y=101.5
local unlocked,unlockReason=SC.FieldWork.unlockTrunkFor(f.worker,f.car,{})
check(unlocked and unlockReason=="field_trunk_unlocked" and f.boardRequests==0 and f.nativeUnlocks==0
    and f.cargo.container==f.car.trunk and T.moves==0,
    "the real helper recognizes a known native false lock value without boarding or touching cargo")
check(#V.rows()==1 and V.rows()[1].count==1,
    "ordinary parked-car enumeration observes this actual fixture car and cargo before it is locked")
f.car.locked,f.car.doorsLocked,f.hasKey=true,true,true
check(select(2,V.eligible(f.car))=="car_trunk_locked" and #V.rows()==0
    and select(2,V.queue(f.car.sqlId))=="car_trunk_locked",
    "ordinary parked-car rows and queued unloading still reject the locked trunk")
check(V.eligible(f.car,{allowLocked=true})==true and f.car.locked and f.nativeUnlocks==0,
    "receipt-only eligibility is read-only while retaining every physical cargo prerequisite")
I.refresh(f.record)
check(f.record.items[1].reason~="home_trunk_waiting_parking" and I.wants(f.record,f.worker),
    "a locked exact Home receipt remains owned across the gap and is not mislabeled as unparked")
handled,reason=I.update(f.record,f.worker)
check(not handled and reason=="car_trunk_locked" and f.boardRequests==1 and f.nativeUnlocks==0
    and f.car.locked and f.worker:getVehicle()==nil and f.cargo.container==f.car.trunk and T.moves==0,
    "Home reaches the real unlock helper and waits for actual boarding without changing lock or cargo")
f.worker.vehicle,f.worker.seat=f.car,f.requestedSeat
handled,reason=I.update(f.record,f.worker)
check(handled and reason=="field_trunk_unlocking" and f.car.locked and f.nativeUnlocks==0
    and f.cargo.container==f.car.trunk and T.moves==0,
    "the seated native unlock transaction observes its ordinary delay before changing the lock")
T.now=T.now+701
handled,reason=I.update(f.record,f.worker)
check(handled and reason=="field_trunk_exiting" and not f.car.locked and f.nativeUnlocks==1
    and f.exitRequests==1 and f.worker:getVehicle()==f.car and f.cargo.container==f.car.trunk and T.moves==0,
    "only the real unlock helper changes the native lock and cargo waits for actual exit")
f.worker.vehicle,f.worker.seat,f.worker.y=nil,nil,103.5
check(select(2,I.update(f.record,f.worker))=="car_trunk_looting" and T.moves==0,
    "normal receipt looting starts only after the fixture reports the real native seat has cleared")
check(select(2,I.update(f.record,f.worker))=="car_item_carried" and T.moves==1
    and f.cargo.container==f.worker.inventory and #f.car.trunk.items==0,
    "the unlocked Home receipt still transfers its one original native cargo object")

f=fixture() f.worker.y=101.5 f.car.locked,f.car.doorsLocked=true,true
check(I.wants(f.record,f.worker),"missing keys do not discard an exact locked Home receipt owner")
handled,reason=I.update(f.record,f.worker)
check(not handled and reason=="car_entry_locked" and f.record.items[1].reason=="car_entry_locked"
    and f.boardRequests==0 and f.nativeUnlocks==0 and f.car.locked
    and f.cargo.container==f.car.trunk and T.moves==0 and I.wants(f.record,f.worker),
    "missing key reports the actual deferred entry blocker while preserving ownership and all physical cargo")
f.hasKey=true
I.update(f.record,f.worker)
check(f.boardRequests==1 and f.car.locked and f.nativeUnlocks==0 and T.moves==0,
    "a subsequently available real key permits a normal boarding retry without a synthetic unlock")
do
    local previousTaxi=SC.TaxiCab
    SC.TaxiCab={isOwned=function(car) return car==f.car end}
    check(select(2,V.eligible(f.car,{allowLocked=true}))=="service_cab_reserved",
        "locked receipt eligibility never grants access to an owned service cab")
    SC.TaxiCab=previousTaxi
end

f=fixture() f.worker.y=101.5 f.car.locked,f.lockReadFails=true,true
handled,reason=I.update(f.record,f.worker)
check(not handled and reason=="car_trunk_lock_unavailable" and f.boardRequests==0
    and f.nativeUnlocks==0 and f.car.locked and f.cargo.container==f.car.trunk and T.moves==0,
    "an unreadable native lock is not treated as either unlocked or permission to board")

f=fixture() f.worker.y=101.5 f.car.locked,f.failLockReadAfterUnlock=true,true
f.worker.vehicle,f.worker.seat=f.car,1
check(select(2,I.update(f.record,f.worker))=="field_trunk_unlocking",
    "the unreadable-postcondition fixture begins the ordinary seated unlock delay")
T.now=T.now+701
handled,reason=I.update(f.record,f.worker)
check(not handled and reason=="car_trunk_unlock_failed" and not f.car.locked and f.nativeUnlocks==1
    and f.exitRequests==0 and f.cargo.container==f.car.trunk and T.moves==0,
    "a failed native post-unlock read cannot claim success, request exit, or release cargo")
f.lockReadFails,f.failLockReadAfterUnlock=false,false
handled,reason=I.update(f.record,f.worker)
check(handled and reason=="field_trunk_exiting" and f.exitRequests==1 and f.nativeUnlocks==1
    and f.cargo.container==f.car.trunk and T.moves==0,
    "a later verified native false lock resumes physical exit without repeating the unlock or moving cargo")

f=fixture() f.worker.y=101.5 f.car.locked,f.failUnlock=true,true
f.worker.vehicle,f.worker.seat=f.car,1
I.update(f.record,f.worker)
T.now=T.now+701
handled,reason=I.update(f.record,f.worker)
check(not handled and reason=="car_trunk_unlock_failed" and f.car.locked and f.nativeUnlocks==1
    and f.exitRequests==0 and f.cargo.container==f.car.trunk and T.moves==0,
    "a native lock write that leaves the trunk locked cannot fabricate a successful Home cargo unlock")

local function reject(label,change)
    local candidate=fixture() candidate.worker.y=101.5
    check(I.wants(candidate.record,candidate.worker),label.." begins with a verified live gap owner")
    change(candidate)
    check(not I.wants(candidate.record,candidate.worker),label.." cannot keep Home delivery ownership in the gap")
    check(T.moves==0,"a rejected "..label.." makes no inventory transfer")
end
reject("unmarked roadside car",function(v) v.marked=false end)
reject("unloaded car",function(v) v.unloaded=true end)
reject("moving car",function(v) v.car.moving=true end)
reject("missing native cargo part",function(v) v.missingPart=true end)
reject("missing native cargo container",function(v) v.missingContainer=true end)
reject("engine-on car",function(v) v.car.engine=true end)
reject("far car",function(v) v.car.y=140 end)
reject("out-of-reach worker",function(v) v.worker.y=140 end)
reject("wrong native car SQL",function(v) v.car.sqlId=99 end)
reject("changed base identity",function(v) v.base.id="camp:2" end)
reject("same-id moved camp",function(v) v.base.core.x=101 end)
reject("same-id redrawn camp",function(v) v.area.y2=99 end)
reject("missing exact cargo",function(v) v.car.trunk.items={} v.cargo.container=nil end)
reject("wrong native cargo ID",function(v) v.cargo.nativeId=777 end)
reject("wrong exact cargo type",function(v) v.cargo.fullType="Base.Other" end)
reject("released cargo",function(v) v.record.items[1].released=true end)
reject("swapped loaded car",function(v)
    v.replacement={sqlId=88,x=v.car.x,y=v.car.y,z=0,trunk=T.container({}),moving=false,engine=false,
        getSqlId=v.car.getSqlId,isEngineRunning=v.car.isEngineRunning}
end)
f=fixture() f.worker.y=101.5
local stranger=T.actor("stranger","Stranger",{}) stranger.x,stranger.y,stranger.z=100.5,101.5,0
check(not I.wants(f.record,stranger),"an unrelated actor never inherits the recorded crew's car delivery")
local stale={id=f.worker.id,x=100.5,y=101.5,z=0,inventory=T.container({}),serial=0,order="follow"}
check(not I.wants(f.record,stale),"a stale same-id actor pointer cannot inherit the registered crew member's reach")

-- Exercise the real Integration -> takeExact chain while the destination
-- adapter expires its 15-second winner or rejects a moved survey origin.
-- A second survey deliberately yields, so a reselection would skip the real
-- trunk movement request rather than merely incrementing a test counter.
local originalResolveContainer=SC.BaseLife.resolveContainer
local originalAccepts=SC.BaseLife.storageAcceptsDeposit
local originalDeposit=SC.BaseWork.depositToStorage
local originalRequestAny=SC.Navigation.requestAny
SC.BaseLife.resolveContainer=function(row)
    return not row.unloaded and originalResolveContainer(row) or nil
end
SC.BaseLife.resolveObject=function(row) return not row.objectUnloaded and row.object or nil end
SC.BaseLife.storageAcceptsDeposit=function(row,container)
    return row.deposits~=false and originalAccepts(row,container)
end
SC.Navigation.selectInteraction=function(actor,owner,_,choices)
    local candidate=current
    candidate.surveyCalls=(candidate.surveyCalls or 0)+1
    candidate.selectionState=owner
    if candidate.surveyPending then return nil,"pending" end
    local previous=owner.navigationChoice
    if previous and (T.now>=previous.expiresAt
        or (actor.x-previous.originX)^2+(actor.y-previous.originY)^2>16) then
        return nil,"pending"
    end
    owner.navigationChoice={winnerId=choices[1].id,expiresAt=T.now+15000,
        originX=actor.x,originY=actor.y}
    return choices[1],"selected"
end
local function selectedFixture(configure)
    local candidate=fixture()
    candidate.destination=T.storages[1]
    candidate.destination.object={x=99,y=96,z=0}
    if configure then configure(candidate) end
    local accepted,why=I.update(candidate.record,candidate.worker)
    check(accepted and why=="approaching_car_trunk" and candidate.surveyCalls==1
        and #candidate.requests==1 and candidate.selectionState.homeStorage~=nil,
        "a real Home receipt selects one live destination before approaching its exact trunk item")
    return candidate
end
f=selectedFixture()
T.now=T.now+16001
check(T.now>f.selectionState.navigationChoice.expiresAt,
    "the selected destination's ordinary navigation survey has actually expired")
handled,reason=I.update(f.record,f.worker)
check(handled and reason=="approaching_car_trunk" and f.surveyCalls==1 and #f.requests==2,
    "an expired 15-second survey cannot interrupt the same Home receipt's retained trunk approach")
f.worker.x=f.worker.x+5
handled,reason=I.update(f.record,f.worker)
check(handled and reason=="approaching_car_trunk" and f.surveyCalls==1 and #f.requests==3
    and f.cargo.container==f.car.trunk and T.moves==0,
    "movement beyond the survey's four-metre origin allowance still resumes the exact physical trunk approach")
T.now=T.now+16001
check(select(2,I.update(f.record,f.worker))=="approaching_car_trunk" and #f.requests==4,
    "repeated expired-survey polls keep servicing trunk movement rather than starving its retained search")

f=selectedFixture()
f.worker.x=f.worker.x+5
check(T.now<f.selectionState.navigationChoice.expiresAt
    and select(2,I.update(f.record,f.worker))=="approaching_car_trunk"
    and f.surveyCalls==1 and #f.requests==2,
    "origin movement alone cannot restart destination planning during the same receipt")

f=selectedFixture()
T.now=T.now+16001 f.worker.y=103.5
check(select(2,I.update(f.record,f.worker))=="car_trunk_looting"
    and select(2,I.update(f.record,f.worker))=="car_item_carried",
    "an expired destination survey still permits actual approached and animated exact pickup")
f.worker.y=99.5
check(select(2,I.update(f.record,f.worker))=="expedition_supply_stored" and T.moves==2
    and f.record.items[1].stored and f.cargo.container==f.destination.container
    and f.selectionState.homeStorage==nil,
    "the retained destination completes a verified physical return and releases runtime selection")

f=fixture() f.destination=T.storages[1] f.destination.object={}
f.record.kind="search"
check(I.valid(f.record) and select(2,I.update(f.record,f.worker))=="approaching_car_trunk",
    "an ordinary search delivery still uses its existing destination selection")
T.now=T.now+16001
check(select(2,I.update(f.record,f.worker))=="storage_route_pending" and f.surveyCalls==2
    and #f.requests==1 and f.selectionState.homeStorage==nil,
    "Home destination retention does not change other expedition job survey expiry")

local function invalidSelection(label,change,configure)
    local candidate=selectedFixture(configure)
    candidate.surveyPending=true
    change(candidate)
    I.update(candidate.record,candidate.worker)
    check(candidate.selectionState.homeStorage==nil and #candidate.requests==1
        and candidate.cargo.container==candidate.car.trunk and T.moves==0,
        label.." invalidates retained storage before any further trunk movement or cargo transfer")
end
invalidSelection("an unloaded destination container",function(v) v.destination.unloaded=true end)
invalidSelection("an unloaded destination object",function(v) v.destination.objectUnloaded=true end)
invalidSelection("a replaced destination container",function(v) v.destination.container=T.container({}) end)
invalidSelection("a replaced destination object",function(v) v.destination.object={} end)
invalidSelection("disabled deposit permission",function(v) v.destination.deposits=false end)
invalidSelection("exhausted destination capacity",function(v) v.destination.container.capacity=0 end)
invalidSelection("a removed marked destination",function() T.storages={} end)
invalidSelection("a blocked destination",function(v)
    v.selectionState.blockedStorage={[v.destination.id]=T.now+15000}
end)
invalidSelection("a changed item category",function(v)
    v.cargo.category="medical"
    T.storage("home-medical","medical",{},99).object={}
end)
invalidSelection("a newly available category-specific destination",function()
    T.storage("home-specific-tools","tools",{},99).object={}
end,function(v) v.destination.category="general" end)
invalidSelection("a replaced exact receipt",function(v)
    local copy={} for key,value in pairs(v.record.items[1]) do copy[key]=value end
    v.record.items[1]=copy
end)

f=selectedFixture()
check(I.retry(f.record,f.record.items[1].id)==true and f.selectionState.homeStorage==nil
    and f.selectionState.navigationChoice==nil,
    "explicit receipt retry discards both runtime destination selection and its survey")
f.surveyPending=true
check(select(2,I.update(f.record,f.worker))=="storage_route_pending" and f.surveyCalls==2
    and #f.requests==1,"a retried receipt must complete a fresh destination survey before trunk movement")

f=selectedFixture()
local copied=I.copy(f.record)
I.reset() f.record=copied
check(select(2,I.update(f.record,f.worker))=="approaching_car_trunk" and f.surveyCalls==2,
    "save-copy and runtime reset never persist selected destination authority")

f=selectedFixture()
f.worker.y=103.5
I.update(f.record,f.worker)
check(select(2,I.update(f.record,f.worker))=="car_item_carried" and f.selectionState.homeStorage~=nil,
    "the same valid destination survives actual exact pickup for the return leg")
f.worker.y=99.5
SC.BaseWork.depositToStorage=function() return false,"path_blocked:blocked_static" end
I.update(f.record,f.worker)
check(f.selectionState.homeStorage==nil and f.selectionState.navigationChoice==nil
    and f.cargo.container==f.worker.inventory and not f.record.items[1].stored,
    "a real destination access failure clears retained selection without claiming delivery")
SC.BaseWork.depositToStorage=originalDeposit
SC.Navigation.requestAny=originalRequestAny
print("HOME_INTEGRATION_REACH_PASS checks="..checks)
