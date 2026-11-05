-- SPDX-License-Identifier: MIT
local SC=SurvivorCompanion
local checks,clock,poses,phase,transfers=0,1000,0,"active",0
local function check(ok,msg) checks=checks+1;assert(ok,"sorting batch "..checks..": "..msg) end
local function container()
    local c={items={},capacity=1000}
    function c:getItems() return self.items end
    function c:getCapacityWeight() local n=0;for _,i in ipairs(self.items) do n=n+i.weight end;return n end
    function c:hasRoomFor(_,item) return self:getCapacityWeight()+item.weight<=self.capacity end
    return c
end
local serial=0
local function item(kind,weight,group)
    serial=serial+1
    local i={id=serial,kind=kind or "Base.Money",weight=weight or .01,group=group or 1,data={}}
    function i:getID() return self.id end
    function i:getFullType() return self.kind end
    function i:getModData() return self.data end
    function i:getContainer() return self.owner end
    function i:getCategory() return "Item" end
    function i:CanStack() return false end -- exact native 42.21 behaviour
    function i:getCondition() return self.group end
    function i:getDisplayName() return self.kind end
    return i
end
local function add(c,i) c.items[#c.items+1]=i;i.owner=c end
local function contains(c,i) for _,v in ipairs(c and c.items or {}) do if v==i then return true end end;return false end
local function transfer(a,b,i)
    if not b:hasRoomFor(nil,i) then return false,"destination_full" end
    for n,v in ipairs(a.items) do if v==i then table.remove(a.items,n);add(b,i);transfers=transfers+1;return true,"transferred" end end
        return false,"source_missing"
end
local root,source,dest=container(),container(),container()
local actor={id="batch-worker",inventory=root,carry=12,x=1,y=1,z=0}
local from={id="storage:source",category="general",withdrawals=true,deposits=true,reserve=0}
local to={id="storage:destination",category="valuables",deposits=true}
local object={x=1,y=1,z=0}
local job={id="job:701",type="sort",state="active",reservedBy=actor.id,target={}}
local activeJob=job
local function call(o,m,...) if o and type(o[m])=="function" then return o[m](o,...),true end;return nil,false end
SC.GameplayUtil={call=call,nowMs=function() return clock end,config=function() return nil end,
    idOf=function(a) return a.id end,inventory=function(a) return a.inventory end,
    inventoryContains=contains,transferItemVerified=transfer,itemType=function(i) return i.kind end,
    itemWeight=function(i) return i.weight end,itemHasTag=function() return false end,
    instanceOf=function() return false end,hasMethod=function(o,m) return o and type(o[m])=="function" end,
    modData=function(o) return o.data end,listSize=function(t) return #(t or {}) end,
    listGet=function(t,n) return t and t[n+1] end,
    each=function(t,limit,fn,offset) for n=(offset or 0)+1,math.min(#(t or {}),(offset or 0)+limit) do if fn(t[n])==false then break end end end,
    inventoryLoad=function() return root:getCapacityWeight(),50 end,
    carryLoad=function() return root:getCapacityWeight(),actor.carry end,
    characterStatValue=function(_,_,fallback) return fallback end,
    directInteractionAccess=function() return true,{object},"arrived" end,
    squareOf=function() return object end,position=function(o) return o.x,o.y,o.z end,
    move=function() poses=poses+1;phase="active";return true end,stop=function() return true end,
    actorState=function(_,state) return state or {} end,clamp=function(n,a,b) return math.max(a,math.min(b,n)) end}
SC.BaseLife={active=function() return {jobs={job},storages={from,to}} end,
    job=function(id) return id==job.id and job end,jobFor=function() return activeJob end,
    resident=function() return {role="generalist",duty=true} end,
    isInside=function() return true end,outdoorNightRestricted=function() return false end,
    storage=function(id) return id==from.id and from or id==to.id and to end,
    storageRows=function() return {from,to} end,
    depositStorageRows=function(category)
        local rows={};for _,r in ipairs({from,to}) do if r.deposits and (not category or r.category==category) then rows[#rows+1]=r end end;return rows
    end,
    resolveContainer=function(r) return r==from and source or r==to and dest end,
    resolveObject=function() return object end,withdrawable=function(r) return r.withdrawals~=false end,
    storageReserve=function(r) return r.reserve or 0 end,
    availableCountExact=function(r,kind)
        local c=r==from and source or dest;local n=0
        for _,i in ipairs(c.items) do if i.kind==kind then n=n+1 end end;return math.max(0,n-(r.reserve or 0))
    end,
    storageAcceptsDeposit=function(r,c) return r.deposits~=false and (r==from and c==source or r==to and c==dest),"base_storage_deposits_disabled" end,
    isValuableItem=function(i) return i.kind=="Base.Money" or i.kind=="Base.MoneyBundle" or i.kind=="Base.GoldBar" end,
    touchJob=function() return true end,
    completeJob=function() job.state="completed";activeJob=nil;return true end,
    blockJob=function(_,_,why) job.state="blocked";job.blocker=why;return true end,
    releaseJob=function() return true end}
SC.NativeActions={visualStatus=function() return phase end,clearVisual=function() return true end,
    cancelVisual=function() phase="completed";return true end,stopDirect=function() return true end}
SC.Navigation={cancel=function() return true end}
SC.PersonalItems={isProtected=function(i) return i.protected==true end,ownedBy=function(i,a) return contains(a.inventory,i) end}
SC.BaseWatch,SC.Downtime,SC.ChefWork,SC.Production,SC.GatherWork,SC.FarmWork,SC.Combat,SC.Registry=nil,nil,nil,nil,nil,nil,nil,nil
local function update() clock=clock+1100;return SC.BaseWork.update(actor,nil,{}) end
local function reset(n,weight)
    SC.BaseWork.cancel(actor,"test_reset");SC.BaseWork.reset(actor)
    root.items,source.items,dest.items={},{},{};root.capacity,source.capacity,dest.capacity=1000,1000,1000
    from.category,from.withdrawals,from.reserve,to.deposits="general",true,0,true
    actor.carry=12;job={id="job:701",type="sort",state="active",reservedBy=actor.id,target={}};activeJob=job
    poses,transfers,phase=0,0,"active"
    for _=1,n or 0 do add(source,item(nil,weight)) end
end
local function finish() phase="completed";update();phase="completed";update() end
reset(35)
local original={} for _,i in ipairs(source.items) do original[i.id]=i end
check(update() and #source.items==35 and #job.target.stockBatch.ids==20,"selection reserves a bounded twenty-item native stack without moving it")
local competing={id="other-worker",inventory=container(),x=1,y=1,z=0}
local competingJob,competingItem={type="sort",target={}},nil
for _=1,8 do
    local _,_,_,_,candidate,why=SC.BaseWork.sortTransfer(competingJob,competing)
    competingItem=candidate
    if why~="haul_scan_pending" then break end
end
check(competingItem and not SC.BaseWork.choreReserved(competingItem),"another sorter skips claimed identities and may select only the remaining stack")
phase="completed";check(update() and #root.items==20 and #source.items==15,"one pickup pose carries twenty distinct money identities")
for _,i in ipairs(root.items) do check(SC.BaseWork.cargoReserved(actor,i) and SC.WorkTransport.isCargoProtected(i,actor),"every carried member is protected from packing and other work") end
phase="completed";check(update() and #dest.items==20 and #root.items==0 and poses==2,"one deposit pose delivers the entire stack")
for _,i in ipairs(dest.items) do check(original[i.id]==i and not SC.SortBatch.protected(i),"delivered stack preserves identities and releases exact claims") end
check(job.target.stockBatch==nil and transfers==40,"twenty pickups plus twenty deposits, without replay")
reset(10);dest.capacity=.025
update();phase="completed";update();phase="completed";update();phase="completed";update()
check(#dest.items==2 and #source.items==8 and #root.items==0,
    "a destination filling midway preserves delivered identities and returns only the remainder")
reset(20,1);from.reserve=5
update();finish()
check(#source.items>=5 and #dest.items<=11 and root:getCapacityWeight()==0,"batch respects source reserves and safe aggregate carry weight")
reset(2);from.reserve=1;update()
check(#job.target.stockBatch.ids==1,"selection claims only available stock, leaving reserved items outside the batch")
finish()
reset(10);source.items[2].protected=true;source.items[3].group=2
local protected,variant=source.items[2],source.items[3]
update();finish()
check(contains(source,protected) and contains(source,variant) and #dest.items==8,"protected and nonmatching native stack members remain untouched")
reset(10);update();phase="completed";update()
check(#root.items==10,"cancellation fixture carries a complete stack")
check(SC.BaseWork.cancel(actor,"cancel_stack") and #source.items==10 and #root.items==0,"cancellation returns every exact member, not only the first")
reset(10);update();from.withdrawals=false;phase="completed";update()
check(#root.items==0 and #source.items==10,"revoked source permission cannot withdraw any selected stack member")
check(SC.BaseWork.cancel(actor,"cancel_selection") and job.target.stockBatch==nil,"cancel before pickup releases all selected claims")
reset(10);update();phase="completed";update();to.deposits=false;phase="completed";update()
check(#root.items==0 and #source.items==10 and #dest.items==0,"revoked destination permission returns the stack safely")
reset(1);from.category="valuables"
update();check(#source.items==1 and #dest.items==0 and poses==0,"sorting leaves money already on its proper shelf")
reset(1)
local resolveContainer=SC.BaseLife.resolveContainer
SC.BaseLife.resolveContainer=function() return source end
update()
check(#source.items==1 and #root.items==0 and poses==0,
    "different markers resolving to one physical shelf cannot create a transfer loop")
SC.BaseLife.resolveContainer=resolveContainer
reset(0)
for _=1,80 do add(source,item("Base.Misc")) end
for _=1,35 do add(source,item("Base.Money")) end
for _=1,20 do update();if job.target.stockBatch then break end end
finish()
check(#dest.items==20 and #source.items==95,
    "bounded rotating shelf search collects a full stack beyond the first eighty objects")
reset(7);update();phase="completed";update()
SC.GameplayUtil.resolveActor=function() return nil end
check(not SC.BaseWork.cancelJob(job.id,actor.id) and #root.items==7 and job.target.stockBatch~=nil,
    "temporarily unloaded workers retain cargo and the persistent receipt")
SC.BaseFuel={workerIdGone=function(id) return id==actor.id end}
check(SC.BaseWork.cancelJob(job.id,actor.id) and #root.items==7 and job.target.stockBatch==nil
    and job.assignedId==nil, "confirmed death releases work affinity while leaving every native corpse item untouched")
check(not SC.BaseWork.storageInUse(from.id),"a confirmed dead carrier cannot lock its source marker indefinitely")
SC.BaseFuel=nil
local audit={counts={},profile={target={food=2,water=2,crafting=1},keep={}},capacity=50,weight=0,hardRatio=.95}
local cash=item("Base.Money")
check(SC.Logistics.canTake(actor,cash,"valuables",audit)==true,"money can still be collected away from marked camp storage")
check(SC.Logistics.canTake(actor,cash,"valuables",audit,nil,from)==false,"marked valuables cannot be scavenged and shelved in a loop")
for _,category in ipairs({"general","literature","trash","valuables"}) do
    check(not SC.Logistics.canTake(actor,cash,category,audit,nil,from),"non-loadout camp category cannot loop: "..category)
end
audit.counts.food=2
check(not SC.Logistics.canTake(actor,cash,"food",audit,nil,from),"temporary hunger target cannot withdraw surplus personal rations from camp")
audit.counts.food=1
check(SC.Logistics.canTake(actor,cash,"food",audit,nil,from),"needed personal rations remain available from camp stock")
local clothingUpgrade,bagUpgrade=SC.Logistics.clothingUpgrade,SC.Logistics.bagUpgrade
SC.Logistics.clothingUpgrade=function() return true end
SC.Logistics.bagUpgrade=function() return true end
check(SC.Logistics.canTake(actor,cash,"clothing",audit,nil,from),"a real clothing upgrade can still replace equipped gear")
check(SC.Logistics.canTake(actor,cash,"container",audit,nil,from),"a real bag upgrade remains available even without a spare-bag target")
SC.Logistics.clothingUpgrade,SC.Logistics.bagUpgrade=clothingUpgrade,bagUpgrade
SC.Combat={weaponOperational=function() return true end,weaponAvailability=function() return nil,0 end}
audit.profile.target.weapon=1;audit.counts.weapon=2
check(SC.Logistics.canTake(actor,cash,"weapon",audit,nil,from),
    "broken carried weapons do not prevent replacing them with a usable camp weapon")
SC.Combat=nil
audit.counts.crafting=1
check(not SC.Logistics.canTake(actor,cash,"crafting",audit,nil,from),"field collection policy cannot cycle stocked camp crafting supplies")
-- Leave a real carried receipt, then reload the production BaseWork module.
local function checkpoint()
    job.target=SC.StableValue.copyStrict(job.target,{maxDepth=3,maxEntries=96})
    check(job.target and job.target.stockBatch and #job.target.stockBatch.ids==7,
        "saved shelf receipt contains only bounded plain values and seven exact native IDs")
end
reset(7);update();phase="completed";update()
check(#root.items==7 and job.target.stockBatch~=nil,"cold-runtime fixture retains only native IDs in the saved job")
checkpoint()
local reloadPhase=0
local missing
SORTING_BATCH_TEST={resume=function()
    if reloadPhase==0 then
        check(SC.BaseWork.storageInUse(from.id),"saved batch prevents unmarking its source before runtime restoration")
        local second=job.target.stockBatch.ids[2]
        job.target.stockBatch.ids[2]=job.target.stockBatch.ids[1]
        check(not SC.BaseWork.cancel(actor,"invalid_receipt") and #root.items==7 and #source.items==0,
            "duplicate native IDs in a saved receipt block recovery without touching cargo")
        job.target.stockBatch.ids[2]=second
        check(SC.BaseWork.cancel(actor,"cancel_after_reload") and #root.items==0 and #source.items==7,
            "cancel immediately after reload reconciles and returns the entire saved stack")
        reset(7);update();phase="completed";update();checkpoint();reloadPhase=1;return
    elseif reloadPhase==1 then
        phase="completed";update();phase="completed";update()
        check(#dest.items==7 and #root.items==0 and job.target.stockBatch==nil,"reloaded controller delivers the exact saved identities")
        reset(7);update();phase="completed";update()
        check(transfer(root,dest,root.items[1]),"fixture stops after native deposit and before clearing its Lua receipt")
        checkpoint()
        reloadPhase=2;return
    elseif reloadPhase==2 then
        phase="completed";update();phase="completed";update()
        check(#dest.items==7 and #root.items==0 and transfers==14,
            "native deposit receipt gap reload does not duplicate or return an already delivered item")
        reset(7);update();phase="completed";update()
        missing=table.remove(root.items,1);missing.owner=nil;checkpoint();reloadPhase=3;return
    end
    phase="completed";update()
    check(#root.items==6 and #dest.items==0 and #job.target.stockBatch.ids==7,
        "reload never recreates an ambiguous missing member or discards its receipt")
    add(root,missing)
    check(SC.BaseWork.cancel(actor,"reconcile_missing") and #source.items==7,
        "returning the same missing identity allows a later reconciliation and cancellation")
    print("SORTING_BATCH_PASS checks="..checks)
    SC_TEST_REPORT="SORTING_BATCH_PASS checks="..checks
end}
