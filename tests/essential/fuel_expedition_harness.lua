-- SPDX-License-Identifier: MIT
-- Native Lua action bodies plus physical, identity-preserving containers.
local SC,F=SurvivorCompanion,SurvivorCompanion.ExpeditionFuel
function getText(key) return key end
function sendItemStats() end
local checks=0
local function check(value,message) checks=checks+1 assert(value,"fuel check "..checks..": "..message) end
local function list()
    local value={}
    function value:add(item) self[#self+1]=item end
    function value:remove(item) for i,v in ipairs(self) do if v==item then table.remove(self,i) return end end end
    function value:size() return #self end
    function value:get(index) return self[index+1] end
    function value:isEmpty() return #self==0 end
    return value
end
local function container(capacity)
    local c={items=list(),capacity=capacity or 100}
    function c:getItems() return self.items end
    function c:getCapacity() return self.capacity end
    function c:getCapacityWeight() local n=0 for _,item in ipairs(self.items) do n=n+item:getUnequippedWeight() end return n end
    function c:getFreeCapacity() return self.capacity-self:getCapacityWeight() end
    function c:hasRoomFor(actor,item) return self:getFreeCapacity()+0.0001>=item:getUnequippedWeight() end
    return c
end
Fluid={Petrol="Petrol"}
ISFluidContainer={new=function(_,fc) return {
    getFluidContainer=function() return fc end,getOwner=function() return fc:getOwner() end,sync=function() end} end}
ISFluidUtil={validateContainer=function(c) return c~=nil end,getTransferActionTimePerLiter=function() return 50 end,
    getMinTransferActionTime=function() return 20 end}
FluidContainer={CanTransfer=function(a,b) return a:getAmount()>0 and b:getFreeCapacity()>0 end,
    Transfer=function(a,b,n) local moved=math.min(n,a:getAmount(),b:getFreeCapacity()) a:adjustAmount(a:getAmount()-moved) b:addFluid(Fluid.Petrol,moved) end}
SandboxVars={AllowExteriorGenerator=true,FuelStationGasInfinite=false}
ZomboidGlobals={EquippedOrWornEncumbranceMultiplier=0.3}
local nextId=0
local function can(amount,capacity,kind)
    nextId=nextId+1
    local item={id=nextId,data={},kind=kind or "Base.PetrolCan",petrolTag=true}
    local fc={amount=amount,capacity=capacity or 10,owner=item}
    function fc:getAmount() return self.amount end
    function fc:getCapacity() return self.capacity end
    function fc:getFreeCapacity() return math.max(0,self.capacity-self.amount) end
    function fc:getSpecificFluidAmount() return self.contaminated and self.amount/2 or self.amount end
    function fc:contains() return self.amount>0 end
    function fc:isMixture() return self.contaminated==true end
    function fc:isInputLocked() return self.locked==true end
    function fc:canAddFluid() return not self.locked end
    function fc:addFluid(_,n) self.amount=math.min(self.capacity,self.amount+n) end
    function fc:adjustAmount(n) self.amount=math.max(0,math.min(self.capacity,n)) end
    function fc:getOwner() return self.owner end
    function item:getFluidContainer() return fc end
    function item:getActualWeight() return 1.6 end
    function item:getContentsWeight() return fc.amount end
    function item:getUnequippedWeight() return self:getActualWeight()+self:getContentsWeight() end
    function item:getContainer() return self.container end
    function item:getID() return self.id end
    function item:getFullType() return self.kind end
    function item:getModData() return self.data end
    function item:hasModData() return true end
    function item:isBroken() return false end
    function item:getStaticModel() return "GasCan" end
    function item:syncItemFields() end
    function item:setJobType() end
    function item:setJobDelta() end
    return item
end
local function put(c,item)
    if item.container then item.container.items:remove(item) end
    item.container=c c.items:add(item)
end
local actor={id="worker",x=100,y=100,z=0,inventory=container(50),characterActions=list()}
function actor:getInventory() return self.inventory end
function actor:getPrimaryHandItem() return self.primary end
function actor:getSecondaryHandItem() return self.secondary end
function actor:setPrimaryHandItem(item) self.primary=item end
function actor:setSecondaryHandItem(item) self.secondary=item end
function actor:isPrimaryHandItem(item) return self.primary==item end
function actor:isSecondaryHandItem(item) return self.secondary==item end
function actor:isHandItem(item) return self.primary==item or self.secondary==item end
function actor:getCharacterActions() return self.characterActions end
function actor:getFreeInventoryCapacity() return self.inventory:getFreeCapacity() end
function actor:isTimedActionInstant() return false end
function actor:hasFullInventory() return self.inventory:getFreeCapacity()<=0 end
function actor:faceThisObject() end
function actor:faceLocation() end
function actor:shouldBeTurning() return false end
function actor:playSound(name) self.lastSound=name return name end
function actor:stopOrTriggerSound() end
function actor:getEmitter() return {isPlaying=function() return false end} end
function actor:reportEvent() end
function actor:SetVariable() end
function actor:setMetabolicTarget() end
function actor:isDead() return self.dead==true end
function actor:getX() return self.x end
function actor:getY() return self.y end
function actor:getZ() return self.z end
function actor:getCurrentSquare() return {getRoom=function() end} end
local gen={fuel=0,condition=100,connected=false,running=false,data={}}
local square={x=100,y=100,z=0}
function square:getX() return self.x end
function square:getY() return self.y end
function square:getZ() return self.z end
function square:hasGridPower() return self.grid==true end
function square:haveElectricity() return gen.running and gen.connected end
function square:isOutside() return true end
function gen:getSquare() return square end
function gen:getObjectIndex() return 1 end
function gen:getFuel() return self.fuel end
function gen:getMaxFuel() return 10 end
function gen:getFuelPercentage() return self.fuel*10 end
function gen:getCondition() return self.condition end
function gen:isConnected() return self.connected end
function gen:setConnected(value) self.connected=value end
function gen:isActivated() return self.running end
function gen:setActivated(value) self.running=value end
function gen:sync() end
function gen:setFuel(value) self.fuel=value end
function gen:failToStart() end
function gen:getModData() return self.data end
local pump={stock=200}
function pump:getSquare() return square end
function pump:getPipedFuelAmount() return self.stock end
function pump:setPipedFuelAmount(value) self.stock=math.floor(math.max(0,value)) end
function pump:getSprite() return {getName=function() return "pump" end} end
local cargo=container(80)
local car={}
local tank={current=25,capacity=50}
function tank:getContainerContentAmount() return self.current end
function tank:setContainerContentAmount(value) self.current=value end
function tank:getContainerCapacity() return self.capacity end
function tank:getVehicle() return car end
function tank:getArea() return "GasTank" end
function car:getPartById(name) return name=="GasTank" and tank or nil end
function car:isInArea() return false end
function car:getSquare() return square end
function car:isEngineRunning() return false end
function car:transmitPartModData() end
local shelves=container(200)
local storage={id="tools",category="tools",container=shelves}
local registry={id=actor.id,actor=actor,name="Fuel tester"}
local base={id="camp",core={x=100,y=100,z=0}}
local function transfer(from,to,item)
    if item.container~=from or not to:hasRoomFor(actor,item) then return false,"destination_full" end
    put(to,item) return true
end
local U={
    call=function(o,m,...) if o and type(o[m])=="function" then return o[m](o,...),true end return nil,false end,
    modData=function(o) return o.data end,itemHasTag=function(item) return item.petrolTag==true end,
    itemWeight=function(item) return item:getActualWeight() end,itemType=function(item) return item.kind end,
    inventory=function(a) return a.inventory end,idOf=function(a) return a.id end,
    listSize=function(v) return v and #v or 0 end,listGet=function(v,i) return v[i+1] end,
    nowMs=function() return SC_TEST_CLOCK end,isDead=function(a) return a.dead==true end,
    position=function(a) return a.x or 100,a.y or 100,a.z or 0 end,
    distance=function() return 0 end,directInteractionAccess=function() return true end,
    gridSquare=function() return square end,carryLoad=function(a) return a.inventory:getCapacityWeight(),30 end,
    inventoryContains=function(c,item) return c and item.container==c end,
    containerHasRoom=function(c,a,item) return c:hasRoomFor(a,item) end,
    itemStableId=function(item,create) if create then item.data.id=item.data.id or "can:"..item.id end return item.data.id end,
}
SC.GameplayUtil=U
SC.LoggingWork={inventoryEntries=function(a)
    local rows={}
    local function visit(source)
        for _,item in ipairs(source.items) do
            rows[#rows+1]={item=item,source=source,id=U.itemStableId(item,false)}
            if item.getInventory then visit(item:getInventory()) end
        end
    end
    visit(a.inventory) return rows
end,cargo=function() return car,cargo end,transfer=function(from,to,a,item) return transfer(from,to,item) end,
    approach=function() return true,"arrived" end}
SC.Vehicle={loadedBySqlId=function(id) return id==41 and car or nil end,cargoPart=function() return {},cargo end,
    isStationary=function() return true end}
SC.VehicleRefuel={physicalAccess=function() return true end}
SC.BaseLife={active=function() return base end,storageRows=function() return {storage} end,
    storage=function(id) return id==storage.id and storage or nil end,withdrawable=function() return true end,
    resolveContainer=function(s) return s.container end,availableCountExact=function() return 100 end,
    depositStorageRows=function(category) return category=="tools" and {storage} or {} end,
    withinWorkReach=function() return true end,describeObject=function() return {id="generator"} end,
    resolveObject=function() return gen end}
SC.WorkTransport={foreignProtected=function(item) return item.protected==true end}
SC.BaseFuel={reserved=function() return false end}
SC.PersonalItems=nil
SC.Logistics=nil
SC.BaseWork={withdrawFromStorage=function(a,state,s,c,item) local moved,why=transfer(c,a.inventory,item) return moved,moved and "base_supply_taken" or why end,
    returnToStorage=function(a,state,s,c,item) local moved,why=transfer(a.inventory,c,item) return moved,moved and "base_supply_returned" or why end,
    depositToStorage=function(a,state,s,c,item) local moved,why=transfer(a.inventory,c,item) return moved,moved and "base_supply_returned" or why end}
SC.Registry={byId=function(id) return id==actor.id and registry or nil end}
SC.Commands={peek=function() return {commandSerial=0,order="base_duty"} end}
SC.ExpeditionWood={outsideWorkAllowed=function() return true end,safety=function() end}
local active
SC.ExpeditionPrototype={current=function() return active end,
    fuelMarkerLive=function(marker) return F.markerLive(active,marker) end}
local originalScan,originalGenerators=SC.FuelStations.scanSite,SC.FuelStations.generators
SC.FuelStations.pump=function(o) return o==pump end
SC.FuelStations.scanSite=function() return true,{pump} end
SC.FuelStations.generators=function() return {gen} end
function square:getObjects() return {pump} end
ISVehiclePartMenu={getNearbyFuelPump=function() return nil end}
local function completeCurrent()
    local action=ISTimedActionQueue.getTimedActionQueue(actor).current
    if action then action:complete() action:perform() end
    return action
end
local nativeComplete=ISTakeFuel.complete
local sample=can(0.25)
put(actor.inventory,sample)
square.grid=true pump.stock=4
local accepted,failure=SC.NativeActions.startExpeditionFuel(actor,{kind="pump_can",pump=pump,item=sample,validate=function() return true end})
check(accepted,"native can action starts: "..tostring(failure))
local action=ISTimedActionQueue.getTimedActionQueue(actor).current
action:updateUse(0.13) action:updateUse(0.51) action:updateUse(0.99)
completeCurrent()
check(math.abs(sample:getFluidContainer():getAmount()-4.25)<0.0001 and pump.stock==0,"fractional completion consumes finite pump stock exactly once")
action:complete()
check(pump.stock==0 and sample:getFluidContainer():getAmount()==4.25,"duplicate completion cannot create fuel")
check(ISTakeFuel.complete==nativeComplete,"global native completion remains untouched")
check(SC.NativeActions.finishWork(actor),"native tools are released after completion")
sample:getFluidContainer().contaminated=true
check(not F.canInfo(sample),"mixed petrol is rejected")
sample:getFluidContainer().contaminated=false sample.petrolTag=false
check(not F.canInfo(sample),"arbitrary drinking containers are not borrowed")
actor.inventory=container(50)
local first,second,full,protected=can(2),can(0),can(10),can(0)
check(math.abs(F.canInfo(first).fullWeight-11.6)<0.001,"full-can reservation includes native fluid contents for partially filled cans")
protected.protected=true
for _,item in ipairs({first,second,full,protected}) do put(shelves,item) end
local site={id="90:90:110:110",label="Gas station",anchor={x=100,y=100,z=0},bounds={x=90,y=90,x2=110,y2=110},groundFloor=true}
local fuel=F.create({mode="count",quantity=2},{site},true)
fuel.tripId="trip" fuel.workerId=actor.id fuel.preparation=true
active={radioSession="trip",homeBaseId="camp",roster={registry},commandSerials={[actor.id]=0},
    scout={fuel=fuel,kind="fuel",phase="walking_to_car",vehicle={sqlId=41}}}
local prepared=false
local preparationWhy={}
for i=1,30 do
    local okay,why=F.prepare(active,actor,{})
    preparationWhy[#preparationWhy+1]=tostring(why)
    SC_TEST_CLOCK=SC_TEST_CLOCK+100
    if fuel.prepared then prepared=true break end
end
check(prepared and #fuel.acquisitions==2 and #cargo.items==2,"permitted cans are physically packed before departure: "..table.concat(preparationWhy,",").." receipts="..#fuel.acquisitions.." trunk="..#cargo.items)
check(full.container==shelves and protected.container==shelves,"full and protected stock stays home")
check(first.container==cargo and second.container==cargo,"the exact selected cans occupy the trunk")
check(F.copy(fuel)~=nil,"prepared state is persistable")
square.grid=false pump.stock=200 tank.current=25
fuel.preparation=nil active.scout.phase="fuel_working"
local originalAccess=SC.VehicleRefuel.physicalAccess
SC.VehicleRefuel.physicalAccess=function() return false end
SC.VehicleRefuel.physicalTargets=function() return {square} end
SC.Navigation={requestAny=function(a,goals,mode,intent)
    check(a==actor and #goals>0 and intent.arrivalDistance==0.15,
        "fuel worker uses the checked inlet goals and precise arrival radius")
    return true,"arrived"
end}
square.grid=true
local approaching,approachReason=F.update(actor,{active=active,fuel=fuel},{})
check(approaching and approachReason=="fuel_approaching_tank" and not fuel.operation,
    "a short movement arrival does not start pouring outside actual inlet reach")
SC.VehicleRefuel.physicalAccess=originalAccess
SC.Navigation=nil square.grid=false
local history={}
for i=1,180 do
    local okay,why=F.update(actor,{active=active,fuel=fuel},{})
    local pending=ISTimedActionQueue.getTimedActionQueue(actor).current
    if pending then history[#history+1]=pending.Type end
    completeCurrent()
    SC_TEST_CLOCK=SC_TEST_CLOCK+100
    if fuel.cleaned then break end
end
check(fuel.cleaned==true,"a finite station pass finishes and cleans up")
check(F.requestFor(active,actor)==nil,"completed station work yields to boarding and home travel")
check(tank.current==50,"the actual car tank is topped up")
check(first:getFluidContainer():getAmount()==10 and second:getFluidContainer():getAmount()==10,"both original cans are filled")
check(first.container==cargo and second.container==cargo and #cargo.items==2,"filled cans are physically returned to the trunk")
check(not gen.running and not gen.connected,"the expedition-started generator is stopped and its borrowed connection removed")
check(math.abs(fuel.generatorFuelUsed-2)<0.001 and math.abs(fuel.carFuelAdded-25)<0.001,"generator and car consumption are tracked separately")
check(math.abs(fuel.pumpLitres-45)<0.001 and pump.stock==155,"initial owned gasoline is excluded from newly pumped fuel")
check(table.concat(history,","):find("ISPlugGenerator",1,true) and table.concat(history,","):find("ISActivateGenerator",1,true),"native generator actions are used")
local report=F.delivery(active)
local deliveryBag=can(0,1,"Base.Bag_BigHikingBag")
deliveryBag.petrolTag=false
local bagInventory=container(50)
function deliveryBag:getInventory() return bagInventory end
put(actor.inventory,deliveryBag)
SC.Logistics={preferredLootDestination=function() return bagInventory end}
check(F.validDelivery(report) and report.version==3,"delivery receipts preserve exact fuel ownership")
local saved=F.copyDelivery(report)
check(saved and saved.items[1]==saved.fuelWork.acquisitions[1],"restored delivery uses one canonical receipt list")
shelves.capacity=shelves:getCapacityWeight()
local handled,reason=F.deliveryUpdate(report,actor)
check(not handled and reason=="fuel_storage_full","full storage pauses delivery")
check(not F.deliveryWants(report,actor),"blocked delivery does not busy-loop")
local paused=F.copyDelivery(report)
F.reset()
check(not F.deliveryWants(paused,actor),"the delivery pause survives reload")
shelves.capacity=200
check(F.retryDelivery(report),"manual retry remains available")
for i=1,20 do F.deliveryUpdate(report,actor) SC_TEST_CLOCK=SC_TEST_CLOCK+100 end
local summary=F.deliverySummary(report)
check(summary.stored==2 and summary.storedLitres==20 and summary.complete,"delivery counts actual final storage")
check(#cargo.items==0 and first.container==shelves and second.container==shelves,"the expedition car is unloaded at home")
check(not F.reserved(first) and not F.reserved(second),"delivered cans release their reservations")
check(#bagInventory.items==0,"bag-carried fuel is staged into root inventory for the native storage transaction")
SC.Logistics=nil
-- A running generator owned by the player is never stopped by cleanup.
gen.running,gen.connected=true,true
fuel.generator={target={id="generator"},wasRunning=true,wasConnected=true}
fuel.cleanupRequested=true fuel.cleaned=nil
check(select(3,F.cleanup(active,actor,{}))==true and gen.running,"an originally running generator stays on")
local claimed=false
gen.running=false gen.connected=true gen.fuel=2
check(SC.NativeActions.startExpeditionFuel(actor,{kind="generator_start",generator=gen,validate=function() return true end,
    completed=function() claimed=true end}),"a generator start can be staged")
gen.running=true -- somebody else starts it before the LF action commits.
completeCurrent() SC.NativeActions.finishWork(actor)
check(not claimed and gen.running,"a concurrent start is not claimed as an LF-owned change")
-- Missing cargo remains missing; receipt restoration never creates another can.
report.items[1].stored=false report.items[1].storageId=nil
first.container.items:remove(first) first.container=nil
report.items[2].stored=false report.items[2].storageId=nil
second.data.LF_ExpeditionFuel={tripId=report.tripId,id=report.items[2].id,nativeId=second.id,ownerId=actor.id}
put(cargo,second)
F.reset() F.retryDelivery(report)
local before=nextId
local okay,why=F.deliveryUpdate(report,actor)
check(okay and second.container==shelves and report.items[2].stored,
    "an unresolved receipt does not prevent delivery of another verified can")
okay,why=F.deliveryUpdate(report,actor)
check(not okay and why=="fuel_cargo_pending" and nextId==before,"ambiguous missing cargo is retained, never recreated")
-- Preparation borrows concentrate only long enough to measure starter fuel,
-- then returns that same donor before the car can depart.
shelves.items=list() cargo.items=list() actor.inventory=container(50)
local empty,donor=can(0),can(10)
put(shelves,empty) put(shelves,donor)
fuel=F.create({mode="count",quantity=1},{site},true)
fuel.tripId="starter" fuel.workerId=actor.id fuel.preparation=true
active.radioSession="starter" active.scout.fuel=fuel
for i=1,40 do
    F.update(actor,{active=active,fuel=fuel},{}) completeCurrent() SC_TEST_CLOCK=SC_TEST_CLOCK+100
    if fuel.prepared then break end
end
check(fuel.prepared and empty.container==cargo and empty:getFluidContainer():getAmount()==2,"native measured transfer prepares two litres of starter fuel")
check(donor.container==shelves and donor:getFluidContainer():getAmount()==8 and fuel.donor.returned,"the exact donor returns home with the measured remainder")
-- Reload after a native fill committed but before its receipt was settled.
fuel.operation={kind="pump_can",id=fuel.acquisitions[1].id,beforeCan=2,beforeTank=tank.current}
empty:getFluidContainer():adjustAmount(4)
local restored=F.copy(fuel)
check(restored~=nil,"an unfinished operation has a valid save descriptor")
F.reset() active.scout.fuel=restored F.stop(active,"reload")
check(restored.pumpLitres==2 and restored.operation==nil,"reload reconciles the actual committed litres")
F.stop(active,"reload")
check(restored.pumpLitres==2 and empty:getFluidContainer():getAmount()==4,"repeated cleanup neither replays nor double counts fuel")
put(actor.inventory,empty)
restored.acquisitions[1].carrierKind="member"
restored.operation={kind="pump_can",id=restored.acquisitions[1].id,beforeCan=4,beforeTank=tank.current}
empty:getFluidContainer():adjustAmount(6)
registry.actor=nil F.reset()
check(F.stop(active,"unloaded")==false and restored.operation~=nil and restored.pumpLitres==2,
    "unloaded native transfer evidence remains pending rather than being discarded")
registry.actor=actor F.reset()
check(F.stop(active,"loaded") and restored.operation==nil and restored.pumpLitres==4,
    "streaming the original can back reconciles its committed transfer exactly once")
-- A queued callback must still belong to the current trip at commit time.
local currentTrip=active
square.grid=true
local beforeRetirement,beforeStock=empty:getFluidContainer():getAmount(),pump.stock
F.update(actor,{active=active,fuel=restored},{})
check(restored.operation and restored.operation.kind=="pump_can","a real native fill is queued before retirement")
active=nil completeCurrent()
check(empty:getFluidContainer():getAmount()==beforeRetirement and pump.stock==beforeStock,
    "a retired fuel mission cannot complete a queued transfer")
active=currentTrip F.stop(active,"retired") SC.NativeActions.finishWork(actor)
-- A donor loan can remain in hand when preparation is cancelled. Walking or
-- an asynchronous storage action is progress, not a three-minute shortage.
restored.donor.returned=false
donor.data.LF_ExpeditionFuel={tripId=active.radioSession,id=restored.donor.id,nativeId=donor.id,ownerId=actor.id}
put(actor.inventory,donor)
local donorReport=F.delivery(active)
local nativeReturn,returnCalls=SC.BaseWork.returnToStorage,0
SC.BaseWork.returnToStorage=function(...)
    returnCalls=returnCalls+1
    if returnCalls<3 then return true,"base_approaching_storage" end
    return nativeReturn(...)
end
F.reset()
check(F.deliveryUpdate(donorReport,actor),"borrowed donor starts returning")
check(F.deliveryWants(donorReport,actor),"normal donor-return progress does not start the shortage retry delay")
for i=1,3 do
    if donorReport.fuelWork.donor.returned then break end
    F.deliveryUpdate(donorReport,actor) SC_TEST_CLOCK=SC_TEST_CLOCK+100
end
check(donorReport.fuelWork.donor.returned and donor.container==shelves,
    "the same donor finishes its asynchronous return without waiting three minutes")
SC.BaseWork.returnToStorage=nativeReturn restored.donor.returned=true
-- A crew member can stream in after another member has begun delivery.
-- Missing native actors are not evidence that their carried cargo died.
put(actor.inventory,empty)
restored.acquisitions[1].carrierKind="member"
local unloadedReport=F.delivery(active)
local relief=setmetatable({id="relief",dead=false,inventory=container(50)},{__index=actor})
local originalRegistry=SC.Registry.byId
SC.Registry.byId=function(id)
    if id==actor.id then return {id=actor.id,name=registry.name} end
    if id==relief.id then return {id=relief.id,name="Relief",actor=relief} end
end
unloadedReport.members[2]={id=relief.id,name="Relief",commandSerial=0,dutyDone=true,shortages={},restockIndex=1}
F.reset() F.deliveryWants(unloadedReport,relief)
check(not unloadedReport.items[1].released and empty.container==actor.inventory,
    "an unloaded hauler retains its exact carried-cargo obligation")
SC.Registry.byId=originalRegistry F.reset()
check(F.deliveryUpdate(unloadedReport,actor) and unloadedReport.items[1].stored,
    "the returning hauler can deliver its original cargo after streaming resumes")
local deathReport=F.copyDelivery(unloadedReport)
deathReport.items[1].stored,deathReport.items[1].storageId=false,nil
deathReport.fuelWork.workerId=actor.id
put(actor.inventory,empty)
empty.data.LF_ExpeditionFuel={tripId=deathReport.tripId,id=deathReport.items[1].id,nativeId=empty.id,ownerId=actor.id}
actor.dead=true
SC.Registry.byId=function(id)
    if id==actor.id then return registry end
    if id==relief.id then return {id=relief.id,name="Relief",actor=relief} end
end
local nativeKind,nativeCancel=SC.NativeActions.workKind,SC.NativeActions.cancelWork
SC.NativeActions.workKind=function(a) if a==actor then return "expedition_fuel" end end
SC.NativeActions.cancelWork=function() return false,"native_release_pending" end
F.reset()
check(not F.deliveryWants(deathReport,relief) and deathReport.fuelWork.workerId==actor.id
        and not deathReport.items[1].released,
    "hauler replacement waits for pending native action removal")
SC.NativeActions.workKind=function() end -- native supervisor has now released the old action
SC.NativeActions.cancelWork=nativeCancel
F.reset() local deathWants=F.deliveryWants(deathReport,relief)
check(deathReport.items[1].released and empty.container==actor.inventory,
    "confirmed carrier death releases the receipt without removing the corpse's item: released="
        ..tostring(deathReport.items[1].released)..";owner="..tostring(deathReport.fuelWork.workerId)
        ..";carried="..tostring(empty.container==actor.inventory)..";wants="..tostring(deathWants))
local missingAfterDeath=F.copyDelivery(deathReport)
missingAfterDeath.items[1].released=false
missingAfterDeath.fuelWork.workerId=actor.id
missingAfterDeath.fuelWork.operation={kind="pump_can",id=missingAfterDeath.items[1].id,beforeCan=6,beforeTank=tank.current}
actor.inventory.items:remove(empty) empty.container=nil
local issuedBeforeDeath=nextId
F.reset() F.deliveryWants(missingAfterDeath,relief)
check(missingAfterDeath.items[1].released and missingAfterDeath.fuelWork.operation==nil
        and missingAfterDeath.fuelWork.warning=="fuel_lost_with_worker" and nextId==issuedBeforeDeath,
    "confirmed death retires missing transfer evidence with a warning, without blocking survivors or recreating cargo")
SC.NativeActions.workKind=nativeKind
actor.dead=false SC.Registry.byId=originalRegistry
-- Discovery performs a bounded slice rather than scanning a whole forecourt.
local gridCalls=0
U.gridSquare=function() gridCalls=gridCalls+1 return nil end
local done=originalScan(site,{})
check(not done and gridCalls==64,"pump discovery inspects at most 64 squares per work tick")
gridCalls=0
local generators=originalGenerators(pump,{})
check(generators==nil and gridCalls==64,"generator discovery is also sliced")
check(F.normalizeRequest({mode="count",quantity=0})==nil and F.normalizeRequest({mode="car"}).mode=="car","invalid counts and explicit car-only requests are distinguished")
print("FUEL_EXPEDITION_PASS checks="..checks)
