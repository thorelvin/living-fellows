-- SPDX-License-Identifier: MIT
-- Physical fuel collection. This module owns no player slot, engine, global
-- action wrapper or background service. Travel remains with ExpeditionCar.
SurvivorCompanion = SurvivorCompanion or {}
local SC=SurvivorCompanion
SC.ExpeditionFuel=SC.ExpeditionFuel or {}
local F=SC.ExpeditionFuel
local runtime=setmetatable({}, {__mode="k"})
local MARK,EPS,LIMIT="LF_ExpeditionFuel",0.02,256
local function U() return SC.GameplayUtil end
local function call(object,method,...)
    local value,okay=U().call(object,method,...)
    if okay then return value end
end
local function weight(item)
    return tonumber(call(item,"getUnequippedWeight")) or U().itemWeight(item)
end
local function number(value) return type(value)=="number" and value==value and math.abs(value)<math.huge end
local function text(value) return type(value)=="string" and #value>0 and #value<=160 end
local function array(value,maximum)
    if type(value)~="table" or #value>maximum then return false end
    local count=0
    for key in pairs(value) do
        if not number(key) or key~=math.floor(key) or key<1 or key>#value then return false end
        count=count+1
    end
    return count==#value
end
local function rt(value) runtime[value]=runtime[value] or {} return runtime[value] end
local function plain(value,depth,budget)
    if value==nil or type(value)=="boolean" then return value end
    if type(value)=="number" then assert(number(value),"fuel number") return value end
    if type(value)=="string" then assert(#value<=2048,"fuel string") return value end
    assert(type(value)=="table" and depth<12,"fuel state")
    budget.count=budget.count+1 assert(budget.count<=8192,"fuel state limit")
    local result={}
    for key,entry in pairs(value) do
        assert(type(key)=="string" or type(key)=="number","fuel key")
        result[key]=plain(entry,depth+1,budget)
    end
    return result
end
function F.normalizeRequest(value)
    value=value or {mode="full"}
    if type(value)~="table" then return nil,"fuel_request_invalid" end
    if value.mode=="full" or value.mode=="car" then return {mode=value.mode} end
    if value.mode=="count" and number(value.quantity) and value.quantity==math.floor(value.quantity)
        and value.quantity>=1 and value.quantity<=LIMIT then return {mode="count",quantity=value.quantity} end
    return nil,"fuel_request_invalid"
end
function F.canInfo(item)
    if not item or not U().itemHasTag(item,"Petrol") or call(item,"isBroken")==true then return nil end
    local fc=call(item,"getFluidContainer")
    local amount,capacity=tonumber(call(fc,"getAmount")),tonumber(call(fc,"getCapacity"))
    if not number(amount) or not number(capacity) or amount<0 or capacity<=0 or capacity>1000
        or call(fc,"isInputLocked")==true then return nil end
    local petrol=Fluid and Fluid.Petrol
    local pure=petrol and tonumber(call(fc,"getSpecificFluidAmount",petrol)) or 0
    if amount>EPS and (not pure or math.abs(amount-pure)>EPS or call(fc,"isMixture")==true) then return nil end
    if petrol and call(fc,"canAddFluid",petrol)==false then return nil end
    return {amount=amount,capacity=capacity,free=math.max(0,capacity-amount),
        fullWeight=weight(item)+math.max(0,capacity-amount)}
end
function F.reserved(item)
    local data=item and U().modData(item)
    return data and data[MARK] and SC.ExpeditionPrototype and SC.ExpeditionPrototype.fuelMarkerLive
        and SC.ExpeditionPrototype.fuelMarkerLive(data[MARK])==true or false
end
local function carFor(active)
    local descriptor=active.scout and active.scout.vehicle
    return descriptor and SC.Vehicle.loadedBySqlId(descriptor.sqlId)
end
local function trunk(car)
    if not car then return nil end
    local ignored,container=SC.Vehicle.cargoPart(car)
    return container
end
local function free(container,actor)
    local amount=tonumber(call(container,"getFreeCapacity",actor))
    if amount then return math.max(0,amount) end
    local capacity=tonumber(call(container,"getCapacity"))
    local weight=tonumber(call(container,"getCapacityWeight"))
    return capacity and weight and math.max(0,capacity-weight) or nil
end
local function entries(container,limit)
    local result={}
    local items=call(container,"getItems")
    for i=0,math.min(limit or 4096,U().listSize(items))-1 do result[#result+1]=U().listGet(items,i) end
    return result
end
local function locate(active,row,reconciled)
    local fuel=active.scout.fuel
    local state=rt(fuel)
    local cache=state.locations
    if not cache or U().nowMs()>cache.untilAt then
        cache={untilAt=U().nowMs()+1000,index={},containers={}}
        state.locations=cache
    end
    local function index(container,holder)
        if not container or cache.containers[container] then return end
        cache.containers[container]=true
        for _,item in ipairs(entries(container,4096)) do
            local data=call(item,"hasModData")~=false and U().modData(item)
            local marker=data and data[MARK]
            if marker and marker.tripId==active.radioSession then
                cache.index[marker.id]={item=item,source=container,holder=holder}
            end
        end
    end
    local car=carFor(active)
    local cargo=trunk(car)
    index(cargo)
    for _,member in ipairs(active.roster or {}) do
        if member.actor then
            local root=U().inventory(member.actor)
            if root and not cache.containers[root] then
                for _,entry in ipairs(SC.LoggingWork.inventoryEntries(member.actor) or {}) do index(entry.source,member.actor) end
                cache.containers[root]=true
            end
        end
    end
    for _,id in ipairs({row.storageId or false,row.sourceStorageId or false}) do
        local storage=id and SC.BaseLife and SC.BaseLife.storage(id)
        if storage then index(SC.BaseLife.resolveContainer(storage)) end
    end
    local result=cache.index[row.id]
    if result and tonumber(call(result.item,"getID"))==row.nativeId then
        if call(result.item,"getContainer")==result.source then return result.item,result.source,result.holder end
        -- A supervised transfer committed since the last snapshot.
        state.locations=nil
        if not reconciled then return locate(active,row,true) end
    end
end
local function worker(active)
    local fuel=active.scout.fuel
    local previousDead=false
    for _,member in ipairs(active.roster) do
        if member.id==fuel.workerId and member.actor then
            previousDead=U().isDead(member.actor)==true
            if not previousDead then return member.actor end
        end
    end
    if fuel.workerId and F.stop then
        local stopped,why=F.stop(active,"fuel_worker_unavailable")
        if not stopped and (not previousDead or why~="fuel_reconciling_transfer") then return nil end
        for _,row in ipairs(fuel.acquisitions) do
            local item,source,holder=locate(active,row)
            -- A streamed-out actor is not proof that its inventory was lost.
            if holder and U().isDead(holder) or previousDead and not item
                and row.memberId==fuel.workerId and row.carrierKind=="member" then
                row.released,row.reason=true,"fuel_lost_with_worker"
                if item then U().modData(item)[MARK]=nil end
            end
        end
        if fuel.donor and not fuel.donor.returned then
            local item,source,holder=locate(active,fuel.donor)
            if holder and U().isDead(holder) then
                fuel.donor.returned,fuel.donor.lost=true,true U().modData(item)[MARK]=nil
            end
        end
        if not stopped then
            fuel.warning=fuel.warning or "fuel_lost_with_worker"
            if not F.stop(active,"fuel_worker_unavailable") then return nil end
        end
    end
    for _,member in ipairs(active.roster) do
        if member.actor and not U().isDead(member.actor) then fuel.workerId=member.id return member.actor end
    end
end
local function generator(fuel)
    return fuel.generator and SC.BaseLife.resolveObject(fuel.generator.target) or nil
end
local function pump(fuel)
    local at=fuel.pump
    local square=at and U().gridSquare(at.x,at.y,at.z)
    local objects=square and call(square,"getObjects")
    for i=0,math.min(255,U().listSize(objects))-1 do
        local object=U().listGet(objects,i)
        if SC.FuelStations.pump(object) and call(call(object,"getSprite"),"getName")==at.sprite then return object end
    end
end
local function atObject(actor,object)
    return U().directInteractionAccess(actor,object)==true
end
local function approach(actor,object,state)
    if atObject(actor,object) then return true,"arrived" end
    local square=call(object,"getSquare") or object
    return SC.LoggingWork.approach(actor,square,"expedition_fuel",false,{movementPriority=70})
end
local function stopped(car)
    return car and SC.Vehicle.isStationary(car)==true and call(car,"isEngineRunning")~=true
        and call(car,"isEngineStarted")~=true and call(car,"isEngineStarting")~=true
end
local function rowFor(fuel,id)
    for _,row in ipairs(fuel.acquisitions) do if row.id==id then return row end end
end
local function register(active,item,storageId,utility)
    local fuel=active.scout.fuel
    local id=U().itemStableId(item,true)
    local info=F.canInfo(item)
    if not id or not info then return nil end
    local existing=rowFor(fuel,id)
    if existing then return existing end
    if #fuel.acquisitions>=LIMIT then return nil end
    local row={id=id,nativeId=tonumber(call(item,"getID")),itemType=U().itemType(item),
        memberId=fuel.workerId,sourceStorageId=storageId,startAmount=info.amount,
        amount=info.amount,capacity=info.capacity,fullWeight=info.fullWeight,utility=utility==true}
    if not number(row.nativeId) then return nil end
    U().modData(item)[MARK]={tripId=active.radioSession,id=id,nativeId=row.nativeId,ownerId=fuel.workerId}
    fuel.acquisitions[#fuel.acquisitions+1]=row
    rt(fuel).locations=nil
    return row
end
function F.valid(fuel)
    if type(fuel)~="table" or fuel.version~=1 or not F.normalizeRequest(fuel.request)
        or not array(fuel.acquisitions,LIMIT)
        or not array(fuel.sites,3) or #fuel.sites<1
        or not number(fuel.siteIndex) or fuel.siteIndex<1 or fuel.siteIndex>#fuel.sites
        or fuel.siteIndex~=math.floor(fuel.siteIndex) or not text(fuel.stage) then return false end
    for _,site in ipairs(fuel.sites) do
        local a,b=type(site)=="table" and site.anchor,type(site)=="table" and site.bounds
        if type(site)~="table" or not text(site.id) or not text(site.label) or type(a)~="table" or type(b)~="table"
            or not number(a.x) or not number(a.y) or a.z~=0 or a.x<0 or a.y<0 or a.x>30000 or a.y>30000
            or not number(b.x) or not number(b.y) or not number(b.x2) or not number(b.y2)
            or b.x2<=b.x or b.y2<=b.y or b.x<0 or b.y<0 or b.x2>30000 or b.y2>30000 then return false end
    end
    for _,field in ipairs({"pumpLitres","carFuelAdded","generatorFuelUsed"}) do
        if not number(fuel[field]) or fuel[field]<0 or fuel[field]>1000000 then return false end
    end
    if fuel.workerId~=nil and not text(fuel.workerId) then return false end
    if fuel.startedHour~=nil and (not number(fuel.startedHour) or fuel.startedHour<0 or fuel.startedHour>100000000) then return false end
    if fuel.generator then
        local g=fuel.generator
        if type(g)~="table" or type(g.target)~="table" or type(g.wasRunning)~="boolean" or type(g.wasConnected)~="boolean"
            or g.wasRunning and g.started==true then return false end
    end
    local seen={}
    for _,row in ipairs(fuel.acquisitions) do
        if type(row)~="table" or not text(row.id) or seen[row.id] or not number(row.nativeId) or not text(row.itemType)
            or not number(row.startAmount) or row.startAmount<0 or not number(row.capacity) or row.capacity<=0
            or row.startAmount>row.capacity+EPS or not number(row.amount) or row.amount<0
            or row.amount>row.capacity+EPS or not text(row.memberId) then return false end
        seen[row.id]=true
    end
    if fuel.donor then
        local row=fuel.donor
        if type(row)~="table" or not text(row.id) or seen[row.id] or not number(row.nativeId)
            or not text(row.sourceStorageId) or not text(row.memberId) or not text(row.itemType)
            or not number(row.capacity) or row.capacity<=0 or not number(row.amount) or row.amount<0
            or row.amount>row.capacity+EPS or not number(row.startAmount) or row.startAmount<0
            or row.startAmount>row.capacity+EPS then return false end
    end
    if fuel.operation then
        local o=fuel.operation
        local allowed={pump_can=true,pump_car=true,can_car=true,starter=true,generator_fuel=true,
            generator_start=true,generator_stop=true,generator_connect=true,generator_disconnect=true}
        if type(o)~="table" or not allowed[o.kind] or o.id and not seen[o.id]
            or not number(o.beforeCan) or o.beforeCan<0 or not number(o.beforeTank) or o.beforeTank<0 then return false end
    end
    local ok=pcall(plain,fuel,0,{count=0})
    return ok
end
function F.copy(fuel)
    if not F.valid(fuel) then return nil end
    return plain(fuel,0,{count=0})
end
function F.create(request,sites,mapSelected)
    local normalized,why=F.normalizeRequest(request)
    if not normalized then return nil,why end
    return {version=1,request=normalized,sites=sites,siteIndex=1,selected=mapSelected==true,
        stage="packing_crew",acquisitions={},pumpLitres=0,carFuelAdded=0,generatorFuelUsed=0}
end
function F.plan(records,options)
    options=options or {}
    if not records or not records[1] then return nil,"leader_unavailable" end
    local sites,why
    if options.mapTarget then
        local fresh,reason=SC.ExpeditionTargets.validate(options.mapTarget,SC.ExpeditionTargets.context(records[1].actor,"drive"))
        if not fresh or fresh.kind~="fuel" then return nil,reason or "fuel_station_missing" end
        sites={fresh.place}
    else sites,why=SC.FuelStations.candidates(records[1].actor) end
    if not sites then return nil,why end
    local chosen,failures={}
    for _,site in ipairs(sites) do
        local trip,reason=SC.ExpeditionCar.preflight(records,options.parkingZoneId,options.vehicleSqlId,site.anchor)
        if trip then
            chosen[#chosen+1]=site
            if #chosen==3 then break end
        else failures=reason end
    end
    if #chosen==0 then return nil,failures or why or "fuel_station_unreachable" end
    local fuel=F.create(options.request,chosen,options.mapTarget~=nil)
    if not fuel then return nil,"fuel_request_invalid" end
    local x,y,z=U().position(records[1].actor)
    fuel.origin={x=math.floor(x),y=math.floor(y),z=math.floor(z)}
    return fuel
end
function F.preview(records,options)
    local fuel,why=F.plan(records,options)
    if not fuel then return nil,why end
    local result,reason=SC.ExpeditionPrototype.previewDrive(records,fuel.sites[1],false,
        options and options.parkingZoneId,options and options.vehicleSqlId)
    if result then result.site=fuel.sites[1] result.fuelRequest=fuel.request end
    return result,reason
end
function F.requestFor(active,actor)
    local scout=active and active.scout
    if not scout or not scout.fuel or active.restoring or active.terminal or active.suspended then return nil end
    local fuel=scout.fuel
    if fuel.cleaned then return nil end
    if fuel.preparation or scout.phase=="fuel_working" or fuel.cleanupRequested then
        if worker(active)==actor then return {active=active,fuel=fuel} end
    end
end
local function availableItem(actor,item)
    return not F.reserved(item) and not (SC.BaseFuel and SC.BaseFuel.reserved(item))
        and not SC.WorkTransport.foreignProtected(item,actor)
        and not (SC.PersonalItems and SC.PersonalItems.isProtected(item,actor,"camp_supply"))
end
local function safeSource(actor,storage,container,item)
    return SC.BaseLife.storage(storage.id)==storage and SC.BaseLife.withdrawable(storage)
        and SC.BaseLife.resolveContainer(storage)==container and U().inventoryContains(container,item)
        and availableItem(actor,item)
        and SC.BaseLife.availableCountExact(storage,U().itemType(item))>0
end
local function handles(actor,info,item)
    local root=U().inventory(actor)
    local space=free(root,actor)
    local weight,maximum=U().carryLoad(actor)
    if not space or not number(weight) or not number(maximum) or maximum<=0 then return false end
    local carried=call(item,"getContainer")==root and weight(item) or 0
    if space+carried+EPS<info.fullWeight then return false end
    if weight-carried+info.fullWeight<=maximum+EPS then return true end
    for _,entry in ipairs(SC.LoggingWork.inventoryEntries(actor) or {}) do
        local bag=call(entry.item,"getInventory")
        if bag and entry.source==root and (call(actor,"isEquippedClothing",entry.item)==true
            or call(actor,"getClothingItem_Back")==entry.item or call(actor,"isHandItem",entry.item)==true) then
            local reduction=math.max(0,math.min(100,tonumber(call(entry.item,"getWeightReduction")) or 0))
            local room=free(bag,actor)
            if room and room+EPS>=info.fullWeight and weight+info.fullWeight*(1-reduction/100)<=maximum+EPS then return true end
        end
    end
    return false
end
local function reserveRoom(active,item,info)
    local fuel,actor=active.scout.fuel,worker(active)
    local cargo=trunk(carFor(active))
    local room=free(cargo,actor)
    if not room or not handles(actor,info,item) then return false end
    local pending=info.fullWeight
    for _,row in ipairs(fuel.acquisitions) do
        local owned,source=locate(active,row)
        if owned then pending=pending+math.max(0,row.fullWeight-(source==cargo and weight(owned) or 0)) end
    end
    if call(item,"getContainer")==cargo then pending=pending-weight(item) end
    return room+EPS>=pending
end
local function cargoAccess(active,actor,state,snapshot)
    local car,cargo,why,moving=SC.LoggingWork.cargo(actor,active.scout.vehicle.sqlId,state,snapshot,{movementPriority=70})
    if not cargo then return nil,nil,moving and "fuel_approaching_trunk" or why,moving==true end
    if not stopped(car) then return nil,nil,"fuel_car_not_stopped" end
    return car,cargo
end
local function loadRow(active,actor,row,state,snapshot)
    local item,source=locate(active,row)
    if not item then return false,"fuel_can_missing" end
    if not F.canInfo(item) then return false,"fuel_contents_changed" end
    local car,cargo,why,moving=cargoAccess(active,actor,state,snapshot)
    if not cargo then return moving==true,why,false end
    if source~=cargo then
        local moved,reason=SC.LoggingWork.transfer(source,cargo,actor,item)
        if not moved then return false,reason or "fuel_trunk_capacity" end
    end
    row.amount=F.canInfo(item).amount
    row.carrierKind,row.carId="trunk",active.scout.vehicle.sqlId
    return true,"fuel_can_loaded",true
end
local function takeRow(active,actor,row,state,snapshot)
    local item,source,holder=locate(active,row)
    if not item then return nil,"fuel_can_missing" end
    local root=U().inventory(actor)
    if source~=root then
        if source==trunk(carFor(active)) then
            local car,cargo,why=cargoAccess(active,actor,state,snapshot)
            if not cargo then return nil,why end
        elseif holder~=actor then return nil,"fuel_can_other_owner" end
        local destination=SC.Logistics and SC.Logistics.preferredLootDestination
            and SC.Logistics.preferredLootDestination(actor,item,"tools") or root
        if source~=(destination or root) then
            local moved,why=SC.LoggingWork.transfer(source,destination or root,actor,item)
            if not moved then return nil,why end
        end
    end
    row.carrierKind,row.memberId="member",U().idOf(actor)
    return item
end
local function settleOperation(active)
    local fuel=active.scout.fuel
    local op=fuel.operation
    if not op then return true end
    local row=op.id and rowFor(fuel,op.id)
    local item=row and locate(active,row)
    local info=item and F.canInfo(item)
    if row and not row.released and not info then return false end
    if info then row.amount=info.amount end
    if op.kind=="pump_can" and info then fuel.pumpLitres=fuel.pumpLitres+math.max(0,info.amount-op.beforeCan)
    elseif op.kind=="pump_car" or op.kind=="can_car" then
        local tank=call(carFor(active),"getPartById","GasTank")
        local after=tonumber(call(tank,"getContainerContentAmount"))
        if not number(after) then return false end
        local gained=math.max(0,after-op.beforeTank)
        fuel.carFuelAdded=fuel.carFuelAdded+gained
        if op.kind=="pump_car" then fuel.pumpLitres=fuel.pumpLitres+gained end
    elseif op.kind=="generator_fuel" and info then fuel.generatorFuelUsed=fuel.generatorFuelUsed+math.max(0,op.beforeCan-info.amount)
    elseif op.kind=="generator_start" then
        local object=generator(fuel)
        if not object then return false end
        if op.changed and object and call(object,"isActivated")==true then fuel.generator.started=true end
    elseif op.kind=="generator_connect" then
        local object=generator(fuel)
        if not object then return false end
        if op.changed and object and call(object,"isConnected")==true then fuel.generator.connected=true end
    end
    fuel.operation=nil
    return true
end
local function runAction(active,actor,intent,row)
    local fuel=active.scout.fuel
    local item=intent.item
    local tank=intent.part or call(carFor(active),"getPartById","GasTank")
    local op={kind=intent.kind,id=row and row.id,beforeCan=item and F.canInfo(item) and F.canInfo(item).amount or 0,
        beforeTank=tonumber(call(tank,"getContainerContentAmount")) or 0}
    fuel.operation=op
    local expected=active.radioSession
    intent.completed=function(wasRunning,wasConnected)
        if intent.kind=="generator_start" then op.changed=wasRunning==false and call(intent.generator,"isActivated")==true
        elseif intent.kind=="generator_connect" then op.changed=wasConnected==false and call(intent.generator,"isConnected")==true end
    end
    if intent.kind=="generator_start" then fuel.generatorAttempts=(fuel.generatorAttempts or 0)+1 end
    intent.validate=function()
        if not SC.ExpeditionPrototype or SC.ExpeditionPrototype.current()~=active
            or active.radioSession~=expected or not active.scout or active.scout.fuel~=fuel
            or U().idOf(actor)~=fuel.workerId or U().isDead(actor) then return false end
        local owned,source,holder
        if row then owned,source,holder=locate(active,row) end
        if item and (not row or not F.canInfo(item) or owned~=item or holder~=actor
            or U().itemStableId(item,false)~=row.id or tonumber(call(item,"getID"))~=row.nativeId) then return false end
        if intent.pump and (pump(fuel)~=intent.pump or not SC.FuelStations.powered(intent.pump)) then return false end
        if intent.generator and (generator(fuel)~=intent.generator or (tonumber(call(intent.generator,"getObjectIndex")) or -1)<0) then return false end
        if intent.generator and not atObject(actor,intent.generator) then return false end
        if intent.pump and intent.kind=="pump_can" and not atObject(actor,intent.pump) then return false end
        if intent.part and (not stopped(carFor(active)) or call(intent.part,"getVehicle")~=carFor(active)
            or SC.VehicleRefuel.physicalAccess(actor,carFor(active),intent.part)~=true) then return false end
        if intent.kind=="generator_fuel" and call(intent.generator,"isActivated")==true then return false end
        if intent.donor and (call(intent.donor,"getContainer")~=U().inventory(actor)
            or not F.canInfo(intent.donor) or F.canInfo(intent.donor).amount<=EPS) then return false end
        return true
    end
    local started,why=SC.NativeActions.startExpeditionFuel(actor,intent)
    if not started then fuel.operation=nil return false,why end
    return true,"fuel_"..intent.kind,false
end
local function returnDonor(active,actor,state)
    local loan=active.scout.fuel.donor
    if not loan or loan.returned then return true,"fuel_starter_ready",true end
    local item,source=locate(active,loan)
    local storage=SC.BaseLife.storage(loan.sourceStorageId)
    local container=storage and SC.BaseLife.resolveContainer(storage)
    if not item or not container then return false,"fuel_starter_loan_pending",false end
    if source~=container then
        if source~=U().inventory(actor) then return false,"fuel_starter_loan_pending",false end
        state.donorReturn=state.donorReturn or {}
        local moved,why=SC.BaseWork.returnToStorage(actor,state.donorReturn,storage,container,item)
        if call(item,"getContainer")~=container then return moved==true,why,false end
    end
    U().modData(item)[MARK]=nil
    loan.returned=true state.donorReturn=nil
    return true,"fuel_starter_ready",true
end
local function prepareStarter(active,actor,state,snapshot)
    local fuel=active.scout.fuel
    local loan=fuel.donor
    if not loan or loan.returned then fuel.starterDone=true return true,"fuel_starter_ready",true end
    local receiver=rowFor(fuel,fuel.starterCanId)
    local bucket=receiver and locate(active,receiver)
    local info=bucket and F.canInfo(bucket)
    if not info then return false,"fuel_can_missing",false end
    local target=math.min(2,info.capacity)
    if info.amount+EPS<target then
        local donor,source=locate(active,loan)
        if not donor then return false,"fuel_starter_loan_pending",false end
        local storage=SC.BaseLife.storage(loan.sourceStorageId)
        local container=storage and SC.BaseLife.resolveContainer(storage)
        if source==container and container then
            state.donorWithdraw=state.donorWithdraw or {}
            local moved,why=SC.BaseWork.withdrawFromStorage(actor,state.donorWithdraw,storage,container,donor)
            if call(donor,"getContainer")~=U().inventory(actor) then return moved==true,why,false end
            state.donorWithdraw=nil
        elseif source~=U().inventory(actor) then return false,"fuel_starter_loan_pending",false end
        local item,why=takeRow(active,actor,receiver,state,snapshot)
        if not item then return true,why,false end
        local amount=math.min(target-info.amount,F.canInfo(donor).amount)
        if amount>EPS then return runAction(active,actor,{kind="starter",item=item,donor=donor,amount=amount},receiver) end
    end
    local handled,why,done=returnDonor(active,actor,state)
    if done then fuel.starterDone=true end
    return handled,why,done
end
function F.prepare(active,actor,snapshot)
    local fuel,state=active.scout.fuel,rt(active.scout.fuel)
    if fuel.retryAt and U().nowMs()<fuel.retryAt then return true,fuel.blocker,false end
    fuel.retryAt=nil
    local car=carFor(active)
    if not stopped(car) then return false,"fuel_car_not_stopped",false end
    if fuel.donor and not fuel.starterDone then return prepareStarter(active,actor,state,snapshot) end
    for _,row in ipairs(fuel.acquisitions) do
        local item,source=locate(active,row)
        if not item and not row.released then fuel.blocker="fuel_can_missing" return false,fuel.blocker,false end
        if item and row.withdrawing then
            local storage=row.sourceStorageId and SC.BaseLife.storage(row.sourceStorageId)
            local original=storage and SC.BaseLife.resolveContainer(storage)
            if source==original and original then
                state.withdraw=state.withdraw or {}
                local moved,why=SC.BaseWork.withdrawFromStorage(actor,state.withdraw,storage,original,item)
                if call(item,"getContainer")~=U().inventory(actor) then return moved==true,why,false end
            elseif source~=U().inventory(actor) and source~=trunk(car) then return false,"fuel_can_transfer_uncertain",false end
            row.withdrawing=nil state.withdraw=nil
        end
        if item and source~=trunk(car) then return loadRow(active,actor,row,state,snapshot) end
    end
    if not state.scan then state.scan={rows=SC.BaseLife.storageRows(nil,true),row=0,index=0,found={},donors={}} end
    local scan=state.scan
    local inspected,containers=0,0
    while scan.row<=#scan.rows and inspected<64 and containers<4 do
        local storage=scan.rows[scan.row]
        local container=scan.row==0 and trunk(car) or storage and SC.BaseLife.resolveContainer(storage)
        local items=container and call(container,"getItems")
        local count=math.min(4096,U().listSize(items))
        if scan.index>=count then scan.row,scan.index,containers=scan.row+1,0,containers+1
        else
            local item=U().listGet(items,scan.index)
            scan.index,inspected=scan.index+1,inspected+1
            local info=F.canInfo(item)
            if info and info.amount>EPS and storage and #scan.donors<LIMIT and safeSource(actor,storage,container,item) then
                scan.donors[#scan.donors+1]={item=item,storage=storage,container=container,info=info}
            end
            if info and info.free>EPS and #scan.found<LIMIT and availableItem(actor,item) and (not storage or safeSource(actor,storage,container,item)) then
                scan.found[#scan.found+1]={item=item,storage=storage,container=container,info=info}
            end
        end
    end
    if scan.row<=#scan.rows then return true,"fuel_finding_cans",false end
    if #fuel.acquisitions==0 and not fuel.handlingChecked then
        fuel.handlingChecked=true
        local fits=false
        for _,candidate in ipairs(scan.found) do if handles(actor,candidate.info,candidate.item) then fits=true break end end
        if not fits then
            for _,member in ipairs(active.roster) do
                if member.actor and member.actor~=actor and not U().isDead(member.actor) then
                    for _,candidate in ipairs(scan.found) do
                        if handles(member.actor,candidate.info,candidate.item) then
                            fuel.workerId=member.id state.scan=nil
                            return true,"fuel_assigning_hauler",false
                        end
                    end
                end
            end
        end
    end
    local wanted=fuel.request.mode=="car" and 1 or fuel.request.mode=="count" and fuel.request.quantity or LIMIT
    if #fuel.acquisitions<wanted then
        for _,candidate in ipairs(scan.found) do
            if not candidate.used and reserveRoom(active,candidate.item,candidate.info) then
                if not availableItem(actor,candidate.item) or call(candidate.item,"getContainer")~=candidate.container
                    or candidate.storage and not safeSource(actor,candidate.storage,candidate.container,candidate.item) then candidate.used=true
                else
                    local row=register(active,candidate.item,candidate.storage and candidate.storage.id,fuel.request.mode=="car")
                    if not row then return false,"fuel_can_identity",false end
                    candidate.used=true
                    if candidate.storage then
                        state.withdraw=state.withdraw or {}
                        -- Register first: a save between withdrawal and receipt
                        -- settlement still names the original exact container.
                        local moved,why=SC.BaseWork.withdrawFromStorage(actor,state.withdraw,candidate.storage,candidate.container,candidate.item)
                        if call(candidate.item,"getContainer")~=U().inventory(actor) then
                            row.withdrawing=true
                            return moved==true,why,false
                        end
                        row.withdrawing=nil state.withdraw=nil
                    end
                    return loadRow(active,actor,row,state,snapshot)
                end
            elseif not candidate.used then candidate.used=true scan.capacityBlocked=true end
        end
    end
    if #fuel.acquisitions==0 and fuel.request.mode~="car" then
        state.scan=nil fuel.handlingChecked=nil
        fuel.blocker=scan.capacityBlocked and "fuel_carry_capacity" or "fuel_cans_missing" fuel.retryAt=U().nowMs()+180000
        return false,fuel.blocker,false
    end
    if #fuel.acquisitions==0 and fuel.request.mode=="car" then
        for _,candidate in ipairs(scan.donors) do
            if reserveRoom(active,candidate.item,candidate.info) and safeSource(actor,candidate.storage,candidate.container,candidate.item) then
                local row=register(active,candidate.item,candidate.storage.id,true)
                if row then row.withdrawing=true return true,"fuel_finding_cans",false end
            end
        end
        state.scan=nil
        fuel.blocker="fuel_utility_can_missing" fuel.retryAt=U().nowMs()+180000
        return false,fuel.blocker,false
    end
    if not fuel.starterDone then
        local receiver=fuel.acquisitions[1]
        for _,row in ipairs(fuel.acquisitions) do
            local item=locate(active,row)
            if item and F.canInfo(item).amount>=math.min(2,F.canInfo(item).capacity)-EPS then fuel.starterDone=true break end
        end
        if not fuel.starterDone and receiver then
            for _,candidate in ipairs(scan.donors) do
                local item=candidate.item
                if not F.reserved(item) and safeSource(actor,candidate.storage,candidate.container,item)
                    and U().containerHasRoom(U().inventory(actor),actor,item)==true then
                    local id=U().itemStableId(item,true)
                    local nativeId=tonumber(call(item,"getID"))
                    if id and nativeId then
                        fuel.donor={id=id,nativeId=nativeId,itemType=U().itemType(item),sourceStorageId=candidate.storage.id,
                            startAmount=candidate.info.amount,amount=candidate.info.amount,capacity=candidate.info.capacity,memberId=fuel.workerId}
                        U().modData(item)[MARK]={tripId=active.radioSession,id=id,nativeId=nativeId,ownerId=fuel.workerId}
                        state.locations=nil
                        fuel.starterCanId=receiver.id
                        return prepareStarter(active,actor,state,snapshot)
                    end
                end
            end
        end
        fuel.starterDone=true
    end
    if not SC.ExpeditionWood.outsideWorkAllowed() then return true,"fuel_waiting_for_daylight",false end
    if fuel.request.mode=="count" and #fuel.acquisitions<fuel.request.quantity then fuel.partialReason="fuel_partial_load" end
    fuel.preparation,fuel.prepared,fuel.stage=nil,true,"travelling"
    fuel.blocker=nil
    return true,"fuel_ready",true
end
local function chooseCan(active,needFuel)
    local missing=false
    for _,row in ipairs(active.scout.fuel.acquisitions) do
        local item=not row.released and locate(active,row)
        local info=item and F.canInfo(item)
        if not row.released and not info then missing=true end
        if info and (needFuel and info.amount>EPS or not needFuel and info.free>EPS) then return row end
    end
    return nil,missing
end
function F.cleanup(active,actor,snapshot)
    local fuel,state=active.scout.fuel,rt(active.scout.fuel)
    if fuel.donor and not fuel.donor.returned then
        local handled,why=returnDonor(active,actor,state)
        return handled,why,false
    end
    for _,row in ipairs(fuel.acquisitions) do
        local item,source,holder=locate(active,row)
        if item and holder==actor and source~=trunk(carFor(active)) then
            local handled,why,done=loadRow(active,actor,row,state,snapshot)
            if not done then return handled,why,false end
            return true,"fuel_loading_return_cargo",false
        end
    end
    local owned=fuel.generator
    local object=generator(fuel)
    if owned and (owned.started or owned.connected) and not object then return false,"fuel_generator_unloaded",false end
    if object and owned.started and call(object,"isActivated")==true then
        local okay,why=approach(actor,object,state)
        if why~="arrived" then return okay,"fuel_approaching_generator",false end
        return runAction(active,actor,{kind="generator_stop",generator=object})
    end
    if object and owned.connected and not owned.wasConnected and call(object,"isConnected")==true then
        local okay,why=approach(actor,object,state)
        if why~="arrived" then return okay,"fuel_approaching_generator",false end
        return runAction(active,actor,{kind="generator_disconnect",generator=object})
    end
    if object then U().modData(object).LF_ExpeditionFuelGenerator=nil end
    fuel.generator=nil
    return true,"fuel_generator_restored",true
end
function F.requestReturn(active,reason,emergency)
    local fuel=active.scout.fuel
    fuel.endReason=fuel.endReason or reason or "fuel_finished"
    fuel.nextStation,fuel.tryAnotherPump=nil,nil
    fuel.cleanupRequested=true
    fuel.emergency=emergency==true or fuel.emergency
    if fuel.emergency and not fuel.cleanupDeadline then fuel.cleanupDeadline=U().nowMs()+10000 end
    return fuel.cleaned==true
end
local function failSite(active,reason)
    local fuel=active.scout.fuel
    fuel.siteFailure=reason
    fuel.cleanupRequested=true
    if fuel.pump and reason~="fuel_car_not_stopped" and reason~="fuel_tank_unreadable" then
        local at=fuel.pump
        fuel.rejectedPumps=fuel.rejectedPumps or {}
        fuel.rejectedPumps[at.x..":"..at.y..":"..at.z]=true
        fuel.tryAnotherPump=true
    end
    fuel.nextStation=not fuel.selected and fuel.siteIndex<3
    if not fuel.nextStation then fuel.endReason=reason end
    return true,reason,false
end
local function tankSide(active,actor,state)
    local car=carFor(active)
    local part=call(car,"getPartById","GasTank")
    if not stopped(car) or not part then return nil,"fuel_car_not_stopped" end
    if SC.VehicleRefuel.physicalAccess(actor,car,part)==true then return part end
    local targets=SC.VehicleRefuel.physicalTargets(actor,car,part)
    if #targets==0 then return nil,"fuel_tank_inaccessible" end
    local okay,why=SC.Navigation.requestAny(actor,targets,"walk",{
        action="move_to_car_fuel",vehicle=car,targetSquare=targets[1],
        arrivalDistance=0.15,movementPriority=70,
    })
    return nil,okay and "fuel_approaching_tank" or why
end
local function power(active,actor,snapshot,p)
    local fuel,state=active.scout.fuel,rt(active.scout.fuel)
    if SC.FuelStations.powered(p) then return true,"fuel_power_ready",true end
    if not SandboxVars or SandboxVars.AllowExteriorGenerator~=true then return failSite(active,"fuel_pump_no_power") end
    local object=generator(fuel)
    if not fuel.generator then
        state.power=state.power or {}
        local candidates=SC.FuelStations.generators(p,state.power)
        if not candidates then return true,"fuel_finding_generator",false end
        for _,candidate in ipairs(candidates) do
            if (tonumber(call(candidate,"getCondition")) or 0)>50 and call(call(candidate,"getSquare"),"isOutside")==true
                and not F.generatorReserved(candidate) then
                local descriptor=SC.BaseLife.describeObject(candidate,true)
                if descriptor then
                    fuel.generator={target=descriptor,wasRunning=call(candidate,"isActivated")==true,
                        wasConnected=call(candidate,"isConnected")==true}
                    U().modData(candidate).LF_ExpeditionFuelGenerator=active.radioSession
                    object=candidate break
                end
            end
        end
    end
    if not object then return failSite(active,"fuel_generator_missing") end
    local owned=fuel.generator
    if owned.wasRunning and call(object,"isActivated")==true then return failSite(active,"fuel_generator_out_of_range") end
    if (tonumber(call(object,"getFuel")) or 0)<=EPS then
        local row=chooseCan(active,true)
        if not row then return failSite(active,"fuel_generator_needs_starter_fuel") end
        local item,why=takeRow(active,actor,row,state,snapshot)
        if not item then return true,why,false end
        local okay,reason=approach(actor,object,state)
        if reason~="arrived" then
            if not okay then return failSite(active,reason) end
            return true,"fuel_approaching_generator",false
        end
        return runAction(active,actor,{kind="generator_fuel",generator=object,item=item,targetFuel=2},row)
    end
    local okay,why=approach(actor,object,state)
    if why~="arrived" then
        if not okay then return failSite(active,why) end
        return true,"fuel_approaching_generator",false
    end
    if call(object,"isConnected")~=true then
        return runAction(active,actor,{kind="generator_connect",generator=object})
    end
    if call(object,"isActivated")~=true then
        if (tonumber(call(object,"getCondition")) or 0)<=50 or (fuel.generatorAttempts or 0)>=2 then return failSite(active,"fuel_generator_start_failed") end
        return runAction(active,actor,{kind="generator_start",generator=object})
    end
    return failSite(active,"fuel_generator_out_of_range")
end
function F.update(actor,ctx,snapshot)
    local active,fuel=ctx.active,ctx.fuel
    local state=rt(fuel)
    local actions=SC.NativeActions
    if actions.isWorkActive(actor) then return true,fuel.operation and "fuel_"..fuel.operation.kind or "fuel_working",false end
    if actions.workKind(actor)=="expedition_fuel" then
        local finished,why=actions.finishWork(actor)
        if not finished then return true,why,false end
    end
    if not settleOperation(active) then return true,"fuel_reconciling_transfer",false end
    if fuel.cleanupRequested then
        fuel.preparation=nil
        local okay,why,done=F.cleanup(active,actor,snapshot)
        if done then
            if fuel.tryAnotherPump then
                fuel.pump,fuel.generator,fuel.cleanupRequested,fuel.tryAnotherPump=nil,nil,nil,nil
                fuel.endReason=nil fuel.stage="inspecting_station"
                state.power=nil
                return true,"fuel_inspecting_station",false
            elseif fuel.nextStation then
                if not fuel.sites[fuel.siteIndex+1] then
                    fuel.alternativeDeadline=fuel.alternativeDeadline or U().nowMs()+30000
                    local sites,scanReason=SC.FuelStations.candidates(actor,false,fuel.origin)
                    local used={}
                    for _,site in ipairs(fuel.sites) do used[site.id]=true end
                    for _,site in ipairs(sites or {}) do
                        if not used[site.id] and #fuel.sites<3 then fuel.sites[#fuel.sites+1]=site used[site.id]=true end
                    end
                    if not fuel.sites[fuel.siteIndex+1] and scanReason=="fuel_station_scan_pending"
                        and U().nowMs()<fuel.alternativeDeadline then return true,"fuel_station_scan_pending",false end
                end
                local nextSite=fuel.sites[fuel.siteIndex+1]
                local accepted,reason=SC.ExpeditionCar.retargetFuelStation(active,nextSite)
                if accepted then
                    fuel.siteIndex=fuel.siteIndex+1
                    fuel.pump,fuel.generator,fuel.nextStation,fuel.cleanupRequested=nil,nil,nil,nil
                    fuel.stage="travelling" state.site,state.power=nil,nil
                    fuel.generatorAttempts,fuel.alternativeDeadline=nil,nil
                else fuel.nextStation=nil fuel.endReason=reason or fuel.siteFailure fuel.cleaned=true end
            else fuel.cleaned=true end
        end
        return okay,why,done
    end
    if fuel.preparation then
        local handled,why,done=F.prepare(active,actor,snapshot)
        if not handled and not fuel.retryAt then fuel.retryAt=U().nowMs()+180000 fuel.blocker=why end
        return handled,why,done
    end
    local unsafe=SC.ExpeditionWood.safety(actor,{snapshot=snapshot})
    if unsafe then F.requestReturn(active,unsafe:gsub("^wood_","fuel_"),unsafe~="wood_night") return true,"fuel_returning",false end
    local car=carFor(active)
    if not stopped(car) then return failSite(active,"fuel_car_not_stopped") end
    local site=fuel.sites[fuel.siteIndex]
    if not fuel.pump then
        state.site=state.site or {}
        local done,pumps=SC.FuelStations.scanSite(site,state.site)
        for _,object in ipairs(pumps) do
            local square=call(object,"getSquare")
            local key=square and square:getX()..":"..square:getY()..":"..square:getZ()
            if not fuel.rejectedPumps or not fuel.rejectedPumps[key] then
                local d=U().distance(actor,square)
                if d<=64 then
                    local props=call(object,"getSprite")
                    fuel.pump={x=square:getX(),y=square:getY(),z=square:getZ(),sprite=call(props,"getName")}
                    fuel.stage="power" break
                end
            end
        end
        if not fuel.pump then
            if done then return failSite(active,fuel.siteFailure or "fuel_pump_missing") end
            return true,"fuel_inspecting_station",false
        end
    end
    local p=pump(fuel)
    if not p then return failSite(active,"fuel_pump_missing") end
    local ready,why,powered=power(active,actor,snapshot,p)
    if not powered then return ready,why,false end
    if (tonumber(call(p,"getPipedFuelAmount")) or 0)<=0 then return failSite(active,"fuel_pump_empty") end
    local tank=call(car,"getPartById","GasTank")
    local amount,capacity=tonumber(call(tank,"getContainerContentAmount")),tonumber(call(tank,"getContainerCapacity"))
    if not amount or not capacity then return failSite(active,"fuel_tank_unreadable") end
    if amount+EPS<capacity then
        fuel.stage="refuelling_car"
        local nearby=ISVehiclePartMenu and ISVehiclePartMenu.getNearbyFuelPump and ISVehiclePartMenu.getNearbyFuelPump(car)
        if nearby==p then
            local part,reason=tankSide(active,actor,state)
            if not part then
                if reason=="fuel_approaching_tank" then return true,reason,false end
                return failSite(active,"fuel_tank_inaccessible")
            end
            return runAction(active,actor,{kind="pump_car",pump=p,part=part})
        end
        local row=chooseCan(active,true) or chooseCan(active,false)
        if not row then return failSite(active,"fuel_car_needs_utility_can") end
        local item,reason=takeRow(active,actor,row,state,snapshot)
        if not item then return true,reason,false end
        local info=F.canInfo(item)
        if info.amount>EPS then
            local part,issue=tankSide(active,actor,state)
            if not part then
                if issue=="fuel_approaching_tank" then return true,issue,false end
                return failSite(active,"fuel_tank_inaccessible")
            end
            return runAction(active,actor,{kind="can_car",part=part,item=item},row)
        end
        local okay,issue=approach(actor,p,state)
        if issue~="arrived" then
            if not okay then return failSite(active,issue) end
            return true,"fuel_approaching_pump",false
        end
        return runAction(active,actor,{kind="pump_can",pump=p,item=item},row)
    end
    if fuel.request.mode=="car" then F.requestReturn(active,"fuel_target_met") return true,"fuel_returning",false end
    local row,missing=chooseCan(active,false)
    if not row then
        F.requestReturn(active,missing and "fuel_cargo_pending" or fuel.partialReason or "fuel_target_met")
        return true,"fuel_returning",false
    end
    -- A filled can is loaded before another is retrieved.
    for _,receipt in ipairs(fuel.acquisitions) do
        local item,source,holder=locate(active,receipt)
        if item and holder==actor and receipt.id~=row.id then return loadRow(active,actor,receipt,state,snapshot) end
    end
    local item,reason=takeRow(active,actor,row,state,snapshot)
    if not item then return true,reason,false end
    local okay,issue=approach(actor,p,state)
    if issue~="arrived" then
        if not okay then return failSite(active,issue) end
        return true,"fuel_approaching_pump",false
    end
    fuel.stage="filling_cans"
    return runAction(active,actor,{kind="pump_can",pump=p,item=item},row)
end
function F.stop(active,reason)
    local fuel=active and active.scout and active.scout.fuel
    if not fuel then return true end
    for _,member in ipairs(active.roster or {}) do
        local actor=member.actor
        if actor and SC.NativeActions.workKind(actor)=="expedition_fuel" then
            local okay,why=SC.NativeActions.cancelWork(actor,reason)
            if not okay then return false,why end
        end
    end
    if not settleOperation(active) then return false,"fuel_reconciling_transfer" end
    return true
end
function F.progress(active)
    local fuel=active.scout.fuel
    local result={kind="fuel",stage=fuel.stage,reason=fuel.blocker or fuel.endReason,warning=fuel.warning or fuel.generatorWarning,
        collected=fuel.pumpLitres,carFuelAdded=fuel.carFuelAdded,generatorFuelUsed=fuel.generatorFuelUsed,
        cans=#fuel.acquisitions,requested=fuel.request.quantity or #fuel.acquisitions,filled=0,carried=0,stored=0,storedLitres=0,carriedLitres=0}
    for _,row in ipairs(fuel.acquisitions) do
        local item=locate(active,row)
        local info=item and F.canInfo(item)
        if info and not row.released then
            row.amount=info.amount
            if info.free<=EPS then result.filled=result.filled+1 end
            if not row.stored then result.carried=result.carried+1 result.carriedLitres=result.carriedLitres+info.amount end
        end
        if not info and not row.released and row.amount+EPS>=row.capacity then result.filled=result.filled+1 end
        if row.stored then result.stored=result.stored+1 result.storedLitres=result.storedLitres+(row.amount or 0) end
    end
    return result
end
function F.validReport(report)
    if type(report)~="table" or report.kind~="fuel" or not number(report.at) or report.at<0
        or not text(report.phase) then return false end
    for _,key in ipairs({"collected","carFuelAdded","generatorFuelUsed","carriedLitres","storedLitres","filled","cans","requested"}) do
        if not number(report[key]) or report[key]<0 or report[key]>1000000 then return false end
    end
    return report.cans<=LIMIT and report.filled<=report.cans and report.requested<=LIMIT
end
function F.retryPreparation(active)
    local fuel=active and active.scout and active.scout.fuel
    if not fuel or not fuel.preparation then return false,"fuel_preparation_inactive" end
    fuel.retryAt,fuel.handlingChecked=nil,nil
    local state=rt(fuel)
    if not state.withdraw and not fuel.donor then state.scan=nil end
    return true,"fuel_preparation_retry"
end
function F.markerLive(active,marker)
    local fuel=active and active.scout and active.scout.fuel
    local row=fuel and marker and fuel.tripId==marker.tripId and rowFor(fuel,marker.id)
    if not row and fuel and marker and fuel.tripId==marker.tripId and fuel.donor and not fuel.donor.returned
        and fuel.donor.id==marker.id then row=fuel.donor end
    return row and row.nativeId==marker.nativeId and not row.stored and not row.released or false
end
function F.generatorReserved(object)
    local data=object and U().modData(object)
    local trip=data and data.LF_ExpeditionFuelGenerator
    local active=SC.ExpeditionPrototype and SC.ExpeditionPrototype.current()
    return trip and active and active.radioSession==trip and active.scout and active.scout.fuel
        and active.scout.fuel.generator~=nil and generator(active.scout.fuel)==object or false
end
function F.delivery(active)
    local fuel=F.copy(active.scout.fuel)
    local members={}
    for _,member in ipairs(active.roster) do
        members[#members+1]={id=member.id,name=member.name or member.id,commandSerial=active.commandSerials[member.id] or 0,
            dutyDone=not active.restockBaseDuty,shortages={},restockIndex=1}
    end
    return {version=3,kind="fuel",tripId=active.radioSession,baseId=active.homeBaseId,
        carId=active.scout.vehicle.sqlId,restock=active.restockBaseDuty==true,
        requested=fuel.request.quantity or #fuel.acquisitions,requestedMode=fuel.request.mode,
        fuelWork=fuel,items=fuel.acquisitions,members=members,retryRemainingMs=0}
end
function F.validDelivery(record)
    if type(record)~="table" or record.version~=3 or record.kind~="fuel" or not text(record.tripId)
        or not number(record.carId) or not text(record.baseId) or not F.valid(record.fuelWork)
        or record.fuelWork.tripId~=record.tripId or not array(record.items,LIMIT)
        or #record.items~=#record.fuelWork.acquisitions or not array(record.members,4)
        or #record.members<1 or #record.members>4 or type(record.restock)~="boolean"
        or not number(record.requested) or record.requested<0 or record.requested>LIMIT
        or not number(record.retryRemainingMs) or record.retryRemainingMs<0 or record.retryRemainingMs>180000 then return false end
    local members={}
    for _,member in ipairs(record.members) do
        if type(member)~="table" or not text(member.id) or members[member.id] or not text(member.name) or not number(member.commandSerial)
            or type(member.dutyDone)~="boolean" or type(member.shortages)~="table" then return false end
        members[member.id]=true
    end
    for i,row in ipairs(record.items) do
        if type(row)~="table" or row.id~=record.fuelWork.acquisitions[i].id or row.nativeId~=record.fuelWork.acquisitions[i].nativeId
            or not members[row.memberId] then return false end
    end
    local okay=pcall(plain,record,0,{count=0})
    return okay
end
function F.copyDelivery(record)
    if not F.validDelivery(record) then return nil end
    F.deliveryRetryRemaining(record)
    local result=plain(record,0,{count=0})
    result.items=result.fuelWork.acquisitions
    return result
end
local function deliveryActive(record)
    local roster={}
    for _,member in ipairs(record.members) do
        local registered=SC.Registry and SC.Registry.byId(member.id)
        roster[#roster+1]={id=member.id,name=member.name,actor=registered and registered.actor}
    end
    return {radioSession=record.tripId,homeBaseId=record.baseId,roster=roster,
        scout={fuel=record.fuelWork,vehicle={sqlId=record.carId}}}
end
function F.deliverySummary(record)
    if not F.validDelivery(record) then return nil end
    local result=F.progress(deliveryActive(record))
    result.version,result.tripId,result.requested=3,record.tripId,record.requested
    result.retryRemainingMs=F.deliveryRetryRemaining(record)
    result.items,result.members={},record.members
    result.pending,result.released,result.returned=0,0,0
    for _,row in ipairs(record.items) do
        if not row.stored and not row.released then result.pending=result.pending+1 end
        if row.released then result.released=result.released+1 end
        if row.returned then result.returned=result.returned+1 end
        result.items[#result.items+1]=plain(row,0,{count=0})
    end
    if record.fuelWork.donor and not record.fuelWork.donor.returned then result.pending=result.pending+1 end
    result.broughtBack=result.returned
    result.deliveryPending=result.pending>0
    result.complete=not result.deliveryPending
    for _,member in ipairs(record.members) do if record.restock and not member.dutyDone then result.complete=false end end
    return result
end
function F.deliveryWants(record,actor)
    if not actor or U().isDead(actor) then return false end
    local state=rt(record)
    if not state.validated then
        if not F.validDelivery(record) then return false end
        state.validated=true
    end
    local base=SC.BaseLife.active()
    if not base or base.id~=record.baseId or not SC.BaseLife.withinWorkReach(actor) then return false end
    local member
    for _,row in ipairs(record.members) do if row.id==U().idOf(actor) then member=row break end end
    if not member then return false end
    local command=SC.Commands and SC.Commands.peek(actor)
    if command and tonumber(command.commandSerial)~=member.commandSerial and command.order~="base_duty" then return false end
    if F.deliveryRetryRemaining(record)>0 then return false end
    -- One carrier owns a delivery pass; other crew can resume their own work.
    local active=deliveryActive(record)
    return worker(active)==actor and F.deliveryPending(record)
end
function F.deliveryPending(record)
    if record.fuelWork and record.fuelWork.donor and not record.fuelWork.donor.returned then return true end
    for _,row in ipairs(record.items or {}) do if not row.stored and not row.released then return true end end
    return false
end
function F.deliveryRetryRemaining(record)
    local state=rt(record)
    local now=U().nowMs()
    local remaining=math.max(0,tonumber(record.retryRemainingMs) or 0)
    if state.retryClock then remaining=math.max(0,remaining-math.max(0,now-state.retryClock)) end
    record.retryRemainingMs=remaining state.retryClock=now
    return remaining
end
local function deferDelivery(record)
    record.retryRemainingMs=180000
    rt(record).retryClock=U().nowMs()
end
function F.retryDelivery(record)
    if not F.validDelivery(record) then return false,"fuel_delivery_invalid" end
    rt(record).retryClock=U().nowMs() record.retryRemainingMs=0
    return true,"fuel_delivery_retry_queued"
end
function F.deliveryUpdate(record,actor)
    if not F.deliveryWants(record,actor) then return false,"delivery_not_ready" end
    local active,state=deliveryActive(record),rt(record)
    if not settleOperation(active) then
        deferDelivery(record)
        return false,"fuel_reconciling_transfer"
    end
    if record.fuelWork.donor and not record.fuelWork.donor.returned then
        local handled,why,done=returnDonor(active,actor,state)
        if not handled and not done then deferDelivery(record) end
        return handled,why
    end
    local pendingReason
    for _,row in ipairs(record.items) do
        if not row.stored and not row.released then
            local item,source,holder=locate(active,row)
            if not item then
                row.reason="fuel_cargo_pending" pendingReason=row.reason
            else
            local info=F.canInfo(item)
            if not info then row.reason="fuel_contents_changed" deferDelivery(record) return false,row.reason end
            local target,container
            if info.amount<=EPS and row.sourceStorageId then
                local original=SC.BaseLife.storage(row.sourceStorageId)
                local destination=original and original.deposits~=false and SC.BaseLife.resolveContainer(original)
                if destination and U().containerHasRoom(destination,actor,item)==true then target,container=original,destination end
            end
            if not target then
                for _,category in ipairs({"tools","general"}) do
                    for _,storage in ipairs(SC.BaseLife.depositStorageRows(category)) do
                        local destination=SC.BaseLife.resolveContainer(storage)
                        if destination and U().containerHasRoom(destination,actor,item)==true then target,container=storage,destination break end
                    end
                    if target then break end
                end
            end
            if not target or not container then
                row.reason="fuel_storage_full" deferDelivery(record)
                return false,row.reason
            end
            -- Save the exact destination before the native transfer can commit.
            row.storageId=target.id
            if source==trunk(carFor(active)) then
                if not SC.BaseLife.withinWorkReach(carFor(active)) then row.reason="fuel_cargo_outside_camp_reach" deferDelivery(record) return false,row.reason end
                local taken,why=takeRow(active,actor,row,state)
                if not taken then return true,why end
                item,source,holder=locate(active,row)
                if not item then return true,"fuel_reconciling_transfer" end
            end
            -- Storage's native loot transaction expects a root-inventory item.
            -- Keep a heavy can in its real bag while walking, then stage that
            -- exact item only after reaching the registered storage object.
            local bagSource
            if source~=U().inventory(actor) then
                if holder~=actor then row.reason="fuel_can_other_owner" deferDelivery(record) return false,row.reason end
                local object=SC.BaseLife.resolveObject(target)
                if not object then row.reason="base_storage_unloaded" deferDelivery(record) return false,row.reason end
                local reached,why=approach(actor,object,state)
                if why~="arrived" then
                    if not reached then row.reason=why deferDelivery(record) end
                    return reached,why
                end
                bagSource=source
                local moved,why=SC.LoggingWork.transfer(source,U().inventory(actor),actor,item)
                if not moved then row.reason=why deferDelivery(record) return false,why end
            end
            state.deposit=state.deposit or {}
            local moved,why=SC.BaseWork.depositToStorage(actor,state.deposit,target,container,item,{movementPriority=60})
            if call(item,"getContainer")==container and U().inventoryContains(container,item) then
                row.stored,row.returned,row.amount,row.reason=true,true,info.amount,nil
                U().modData(item)[MARK]=nil state.deposit=nil
                return true,"fuel_can_stored"
            end
            if not moved then
                if bagSource and call(item,"getContainer")==U().inventory(actor) then SC.LoggingWork.transfer(U().inventory(actor),bagSource,actor,item) end
                row.reason=why deferDelivery(record) state.deposit=nil
            end
            return moved,why
            end
        end
    end
    if pendingReason then deferDelivery(record) return false,pendingReason end
    return true,"fuel_delivery_complete"
end
function F.settleDelivery(record)
    if not F.validDelivery(record) then return nil end
    local active=deliveryActive(record)
    settleOperation(active)
    for _,row in ipairs(record.items) do
        if not row.stored and row.storageId then
            local item,source=locate(active,row)
            local storage=SC.BaseLife.storage(row.storageId)
            if item and storage and source==SC.BaseLife.resolveContainer(storage) then
                row.stored,row.returned=true,true U().modData(item)[MARK]=nil
            end
        end
    end
    return F.deliverySummary(record)
end
function F.debrief(active)
    local s=active.scout
    return {kind="fuel",destination=plain(s.destination,0,{count=0}),returnPoint=plain(s.returnPoint,0,{count=0}),
        endReason=s.fuel.endReason or s.endReason or "fuel_finished",integration=active.integration and F.copyDelivery(active.integration)}
end
function F.copyDebrief(value)
    if type(value)~="table" or value.kind~="fuel" or type(value.endReason)~="string"
        or type(value.destination)~="table" or type(value.returnPoint)~="table"
        or value.integration and not F.validDelivery(value.integration) then return nil end
    local okay,result=pcall(plain,value,0,{count=0})
    return okay and result or nil
end
function F.reset() runtime=setmetatable({}, {__mode="k"}) end
function F.reason(reason)
    local lines={fuel_station_scan_pending="Finding a known gas station…",fuel_station_missing="No known gas station found. Choose one on your map.",
        fuel_starter_ready="Starter gasoline prepared",fuel_starter="Preparing starter gasoline",
        fuel_reconciling_transfer="Waiting to verify the original fuel transfer before continuing.",
        fuel_lost_with_worker="Cargo was lost with a dead crew member.",
        fuel_carry_capacity="The crew needs room to safely carry a filled can. Free space or provide a suitable bag.",
        fuel_utility_can_missing="The crew needs one permitted gas can to shuttle fuel to the car. Preparation retries in three minutes.",
        fuel_partial_load="Returned a partial load: available cans or safe carrying space limited departure.",
        fuel_assigning_hauler="Assigning a crew member with enough carrying space",fuel_finding_generator="Looking for an existing station generator",
        fuel_generator_start_failed="The station generator could not be safely started.",
        fuel_starter_loan_pending="Returning the borrowed starter-fuel can before departure.",fuel_waiting_for_daylight="Waiting for daylight before leaving",
        fuel_station_unreachable="No safe driving route to the station.",fuel_request_invalid="Choose a valid number of cans.",
        fuel_base_missing="Establish camp before collecting fuel.",fuel_delivery_queue_full="Finish pending deliveries before sending another fuel trip.",
        fuel_finding_cans="Finding gas cans",fuel_cans_missing="No permitted empty or partly filled gas cans. Preparation retries in three minutes.",
        fuel_can_missing="A reserved gas can is missing; its contents have not been recreated.",fuel_car_not_stopped="Waiting for the car to stop with its engine off.",
        fuel_approaching_trunk="Walking to the trunk",fuel_approaching_pump="Walking to the pump",fuel_inspecting_station="Checking the station's pumps",
        fuel_approaching_generator="Walking to the generator",fuel_approaching_tank="Walking to the fuel inlet",
        fuel_generator_connect="Connecting the station generator",fuel_generator_start="Starting the station generator",
        fuel_generator_stop="Stopping the station generator",fuel_generator_disconnect="Disconnecting the borrowed generator connection",
        fuel_generator_fuel="Fuelling the station generator",fuel_generator_missing="No safe, usable generator at this station.",
        fuel_generator_out_of_range="The generator does not power the pumps.",fuel_generator_needs_starter_fuel="The station generator needs starter gasoline.",
        fuel_pump_no_power="The pumps have no usable electricity.",fuel_pump_empty="The pump is empty.",fuel_pump_missing="No accessible pump found.",
        fuel_tank_inaccessible="The car's fuel inlet cannot be reached.",fuel_car_needs_utility_can="The car is too far from the pump and no utility can is available.",
        fuel_pump_can="Filling a gas can",fuel_pump_car="Topping up the car",fuel_can_car="Pouring gasoline into the car",
        fuel_trunk_capacity="The trunk cannot hold the filled cans.",fuel_ready="Gas cans packed",fuel_can_loaded="Gas can loaded",
        fuel_storage_full="Fuel delivery paused: permitted storage is full or missing.",fuel_cargo_pending="Fuel cargo is pending recovery.",
        fuel_cargo_outside_camp_reach="The fuel car is outside camp's unloading reach.",fuel_contents_changed="The can's contents changed. Delivery needs inspection.",
        fuel_can_stored="Gas can stored",fuel_target_met="Car topped up and selected cans filled",fuel_return_timer="Returning with available fuel: time limit reached.",
        fuel_night="Returning with available fuel: night work is disabled.",fuel_unsafe="Withdrawing from danger with available fuel.",
        fuel_injured="Returning for medical attention.",fuel_returning="Packing up to return home",fuel_generator_cleanup_pending="Restoring the station generator before leaving",
        fuel_generator_restored="Station generator restored",fuel_generator_unloaded="Waiting to reach the generator for shutdown.",
        fuel_generator_left_for_manual_recovery="The crew could not restore the station generator. It needs manual inspection.",
        fuel_loading_return_cargo="Loading fuel for the return trip",fuel_delivery_complete="Fuel delivered",fuel_finished="Fuel trip finished"}
    return lines[reason] or reason
end
return F
