-- SPDX-License-Identifier: MIT
local SC=SurvivorCompanion
local P=SC.Persistence
local records,actors,removedOrder={}, {}, {}
local generation,flushOkay,primaryLoaded,failRemoval,slot,owner=7,false,false,nil,nil,"expedition"
local captures,flushes,spawns=0,0,0
local leaseToken,cancellations=51,0
local otherSpawns,storedItems=0,0
local camp={id="base:remote",arrival={x1=190,y1=190,x2=210,y2=210,z=0},core={x=200,y=200,z=0}}
local function square(x,y,z)
    return {getX=function() return x end,getY=function() return y end,getZ=function() return z end}
end
local function makeActor(id,x)
    local a={id=id,square=square(x,200,0),healthy=true,itemId=x+1000}
    function a:getCurrentSquare() return self.square end
    function a:isDead() return self.dead==true end
    function a:isCorpseReady() return self.corpseReady==true end
    function a:getVehicle() return nil end
    function a:isExistInTheWorld() return not self.detached end
    function a:isAddedToModelManager() return not self.detached end
    function a:isScheduled() return not self.detached end
    return a
end
for index=1,2 do
    local id="sc-remote-"..index
    local a=makeActor(id,199+index)
    actors[index]=a
    records[id]={id=id,actor=a,recruited=true,runtime={lastStablePosition={x=1,y=1,z=0},lastStableSnapshot={stale=true}}}
end
local unrelated=makeActor("sc-unrelated",50)
records[unrelated.id]={id=unrelated.id,actor=unrelated,recruited=true,runtime={}}
slot=actors[1]
SC.Registry={isValidId=function(id) return type(id)=="string" and string.sub(id,1,3)=="sc-" end,
    byId=function(id) return records[id] end,idOf=function(a) return a.id end,
    isActive=function(a,id) return records[id] and records[id].actor==a and not a.detached end,
    records=function() local rows={} for _,r in pairs(records) do rows[#rows+1]=r end return rows end}
SC.Actor={validateNative=function(a) return a.healthy end,isCompanion=function(a) return records[a.id]~=nil end,
    remove=function(a)
        removedOrder[#removedOrder+1]=a.id
        if failRemoval==a.id then failRemoval=nil return false,"injected partial cleanup" end
        a.detached,a.square=true,nil records[a.id]=nil return true
    end}
SC.HomeTrip={campUnchanged=function(c) return c==camp end}
SC.BaseLife={export=function() return {storedItems=storedItems} end,
    restore=function(saved) storedItems=saved.storedItems return true end}
SC.ViewSession={owner=function() return owner end,export=function() return {schema=1,slotSqlId=2} end,restore=function() return true end}
SC.ExpeditionPrototype={export=function() return {schema=9,scout={kind="home"}} end,
    exportRemoteArrival=function() return {schema=2,state="idle",slotSqlId=2,deliveries={{tripId="remote-trip"}},debrief={kind="home"}} end,
    restore=function(saved) assert(saved.schema==2 and saved.state=="idle") return true end}
SC.Vehicle=nil SC.Trade=nil
local captureFailure=nil
P.captureRecord=function(record)
    captures=captures+1
    if captureFailure==record.id then return nil,"injected fresh capture failure" end
    local sq=record.actor.square
    local roots=record.actor.carries==false and {} or {{id="i1",type="Base.Test",nativeId=record.actor.itemId,children={},weaponParts={}}}
    return {id=record.id,recruited=true,identity={forename="Exact",surname=record.id,gender="female"},
        position={x=sq:getX(),y=sq:getY(),z=sq:getZ()},order={current="base_duty"},skills={},vitals={generation=generation},
        inventory={schema=2,complete=true,count=#roots,roots=roots,
            legacy=false,equipment={worn={},attached={}}},freshGeneration=generation}
end
SCSplitScreenProbe={remoteArrivalSlotSqlId=function(token) assert(token==leaseToken) return 2 end,
    cancelRemoteArrival=function(token) assert(token==leaseToken) cancellations=cancellations+1 return true end,
    acknowledgeRemoteArrival=function(token,key,document)
        flushes=flushes+1
        assert(token==leaseToken and key==SC.Identity.worldSaveKey and SC_TEST_GLOBAL_MOD_DATA[key].document==document,"ack uses installed exact document")
        assert(document.expedition.state=="idle" and document.viewSlot.slotSqlId==2,"native barrier sees finalized mission and exact slot")
        for _,a in ipairs(actors) do
            local saved=document.companions[a.id]
            assert(saved.restorePrimaryOnly and saved.freshGeneration==generation and saved.inventory and saved.vitals,"complete fresh tagged roster snapshot")
        end
        return flushOkay
    end,
    primaryAreaContains=function(x,y,z) assert(z==0) return primaryLoaded end}
function getSpecificPlayer(index)
    if index==1 then return slot end
    if index==0 then return {} end
end
function getCell() return {getGridSquare=function(_,x,y,z) return square(x,y,z) end} end
local store=SC_TEST_SET_WORLD_STORE({document={prior=true}})
local okay,reason=P.commitRemoteArrival(actors,camp,leaseToken,{tripId="remote-trip"})
assert(not okay and #removedOrder==0 and flushes==1,"failed durable flush removes nobody")
local frozen=store.document
P.restorePulse({})
assert(P.pendingCount()==2 and P.pendingSnapshot()[actors[1].id].remoteHeld,"held entries survive original active registry records")
local saveOkay=P.save({})
assert(not saveOkay and not P.requestScheduledSave({}),"unflushed transaction cannot be overwritten by another save")
actors[1].square=square(202,200,0)
assert(P.abortRemoteArrival(leaseToken) and cancellations==1 and P.pendingCount()==0,"pre-ack moved source cancels its pinned lease and discards held snapshots")
assert(store.document.expedition.schema==9 and store.document.companions[actors[1].id].position.x==202,"abort publishes a fresh active mission instead of restoring stale staged data")
assert(P.save({}) and P.requestScheduledSave({}),"aborted staging permits ordinary saves and future capture")
P.cancelPendingSave("focused test")
leaseToken=52
-- A new attempt must capture again, rather than accepting the prior snapshot.
generation=8 captureFailure=actors[2].id
assert(not P.commitRemoteArrival(actors,camp,leaseToken,{}) and #removedOrder==0,"fresh capture failure never falls back to old saved inventory")
captureFailure=nil actors[2].healthy=false
assert(not P.commitRemoteArrival(actors,camp,leaseToken,{}) and #removedOrder==0,"unverified fresh native position refuses lastStablePosition fallback")
actors[2].healthy=true
local secondId=actors[2].itemId actors[2].itemId=actors[1].itemId
assert(not P.commitRemoteArrival(actors,camp,leaseToken,{}) and #removedOrder==0,"duplicate native item IDs across the complete crew refuse detachment")
actors[2].itemId=nil
assert(not P.commitRemoteArrival(actors,camp,leaseToken,{}) and #removedOrder==0,"unreadable native item ID refuses detachment")
actors[2].itemId=secondId flushOkay=true failRemoval=actors[1].id
okay=P.commitRemoteArrival(actors,camp,leaseToken,{})
assert(not okay and removedOrder[1]==actors[2].id and removedOrder[2]==actors[1].id,"followers detach first and failed leader cleanup retains transaction")
local cancelsBeforeDurableAbort=cancellations
assert(not P.abortRemoteArrival(leaseToken) and cancellations==cancelsBeforeDurableAbort,
    "durable partial teardown cannot cancel its native lease or discard exact held crew snapshots")
assert(P.pendingCount()==2 and P.pendingSnapshot()[actors[2].id].remoteHeld,"partially detached crew stays held")
P.restorePulse({})
assert(P.pendingCount()==2,"pending restore neither drops live member nor duplicates detached follower")
local beforeCaptures,beforeFlushes=captures,flushes
local acknowledgedDocument,frozenCrew=store.document,store.document.companions[actors[1].id]
unrelated.carries,storedItems=false,1
local saved,document=P.save({})
assert(saved and document==store.document and document.expedition.state=="idle","durable partial teardown overlays finalized idle document")
assert(document==acknowledgedDocument and document.companions[actors[1].id]==frozenCrew,"fresh unrelated save retains native acknowledged object and exact frozen crew objects")
assert(captures==beforeCaptures+1 and document.companions[unrelated.id].inventory.count==0 and document.baseLife.storedItems==1,"unrelated inventory transfer and camp storage are freshly saved during partial teardown")
assert(not P.requestScheduledSave({}) and P.pulse()=="idle","scheduled captures stay cancelled during teardown")
local capturesAfterSave=captures
assert(P.commitRemoteArrival(actors,camp,leaseToken,{}) and captures==capturesAfterSave and flushes==beforeFlushes,"partial retry uses exact frozen crew snapshots without recapture or reflushing")
assert(#removedOrder==3 and removedOrder[3]==actors[1].id,"already detached follower is never removed twice")
assert(not P.completeRemoteArrival(leaseToken),"pending crew remains held until native and Lua view close")
slot,owner=nil,nil
assert(P.completeRemoteArrival(leaseToken) and P.completeRemoteArrival(leaseToken),"completion unholds once and is idempotent after detachment")
assert(not P.pendingSnapshot()[actors[1].id].remoteHeld and not P.pendingBootstrap(actors[1].id),"dormant home crew cannot request a cold secondary bootstrap")
P.restoreAt=function(saved,sq)
    if saved.id==unrelated.id then
        otherSpawns=otherSpawns+1
        assert(saved.inventory.count==0 and storedItems==1,"cold restore preserves unrelated transfer without duplicating stored item")
        records[saved.id]={id=saved.id,actor=makeActor(saved.id,saved.position.x),recruited=true,runtime={}}
        return records[saved.id].actor,"restored"
    end
    spawns=spawns+1
    assert(saved.restorePrimaryOnly and saved.freshGeneration==8,"restore uses exact post-flush snapshot")
    records[saved.id]={id=saved.id,actor=makeActor(saved.id,saved.position.x),recruited=true,runtime={}}
    return records[saved.id].actor,"restored"
end
P.restorePulse({})
assert(spawns==0 and P.pendingCount()==2,"residual secondary cached squares never reactivate primary-only crew")
local crashDocument=store.document
assert(P.reset())
records={}
SC_TEST_SET_WORLD_STORE({document=crashDocument})
assert(P.restore({}) and P.pendingCount()==3,"cold idle restore keeps tagged dormant crew and unrelated companion")
P.restorePulse({})
P.restorePulse({})
assert(spawns==0 and otherSpawns==1 and P.pendingCount()==2,"primary-only policy survives crash while unrelated transfer restores fresh")
primaryLoaded=true SC_TEST_CLOCK=SC_TEST_CLOCK+100000
P.restorePulse({})
assert(spawns==2 and P.pendingCount()==0,"actual primary coverage reactivates exact crew once")
P.restorePulse({}) assert(spawns==2,"restored crew is never duplicated")
assert(P.reset())
crashDocument.companions[actors[1].id].restorePrimaryOnly="yes"
SC_TEST_SET_WORLD_STORE({document=crashDocument})
assert(P.restore({}) and P.quarantineSnapshot().companions[actors[1].id],"invalid primary-only flag is quarantined")
-- Exact IDs are installed on fresh objects before insertion. Legacy snapshots
-- continue using AddItem(type) and retain the factory-assigned identity.
local items,ignoreSet={},false
local function freshItem(kind)
    local item={kind=kind,nativeId=999}
    function item:getID() return self.nativeId end
    function item:setID(id) if not ignoreSet then self.nativeId=id end end
    return item
end
InventoryItemFactory={CreateItem=freshItem}
local inventory={getItems=function() return {size=function() return #items end,get=function(_,index) return items[index+1] end} end,
    AddItem=function(_,value)
        local item=type(value)=="string" and freshItem(value) or value
        if type(value)~="string" then assert(item:getID()==-2147483648,"setID precedes insertion") end
        items[#items+1]=item return item
    end,
    Remove=function(_,item) for index=#items,1,-1 do if items[index]==item then table.remove(items,index) end end end}
local inventoryActor={getInventory=function() return inventory end}
local exact={schema=2,complete=true,count=1,preserveNativeIds=true,roots={{id="i1",type="Base.Test",nativeId=-2147483648,children={},weaponParts={}}},equipment={worn={},attached={}}}
assert(P._applyInventoryForTests(inventoryActor,exact,"sc-exact") and items[1]:getID()==-2147483648,"exact restore preserves full signed native ID range")
local fallbackFactory,instanceCalls=InventoryItemFactory,0
InventoryItemFactory=nil
instanceItem=function(kind) instanceCalls=instanceCalls+1 return freshItem(kind) end
assert(P._applyInventoryForTests(inventoryActor,exact,"sc-live-factory")
    and instanceCalls==1 and items[1]:getID()==-2147483648,
    "live Build42 instanceItem creates the native object before exact ID insertion without InventoryItemFactory exposure")
instanceItem=function() error("injected native factory failure") end
assert(not P._applyInventoryForTests(inventoryActor,exact,"sc-live-factory") and #items==0,
    "native factory failure inserts no item and never weakens exact identity restoration")
instanceItem=nil InventoryItemFactory=fallbackFactory
ignoreSet=true
assert(not P._applyInventoryForTests(inventoryActor,exact,"sc-exact") and #items==0,"unverified native ID assignment inserts nothing")
ignoreSet=false exact.preserveNativeIds=nil
assert(P._applyInventoryForTests(inventoryActor,exact,"sc-legacy") and items[1]:getID()==999,"generic legacy restore retains factory IDs")
exact.preserveNativeIds=true exact.roots[1].nativeId=nil
assert(not P._applyInventoryForTests(inventoryActor,exact,"sc-exact"),"missing exact identity is rejected before restore")
assert(P.reset())
do
    actors={makeActor("sc-dead-arrival-1",200),makeActor("sc-dead-arrival-2",201)}
    records={}
    for _,a in ipairs(actors) do records[a.id]={id=a.id,actor=a,recruited=true,runtime={}} end
    unrelated=makeActor("sc-dead-arrival-unrelated",50)
    records[unrelated.id]={id=unrelated.id,actor=unrelated,recruited=true,runtime={}}
    removedOrder,flushOkay,leaseToken,slot,owner={},false,88,actors[1],"expedition"
    store=SC_TEST_SET_WORLD_STORE({document={schema=SC.Identity.saveSchema,companions={},factionActors={}}})
    assert(not P.commitRemoteArrival(actors,camp,leaseToken,{}) and P.pendingCount()==2,
        "failed preack flush retains the exact live crew snapshots for later death cleanup")
    local cancel=SCSplitScreenProbe.cancelRemoteArrival
    SCSplitScreenProbe.cancelRemoteArrival=function() return false end
    assert(not P.abortRemoteArrival(leaseToken) and P.pendingCount()==2,
        "failed preack native abort retains staged snapshots rather than guessing release")
    for _,a in ipairs(actors) do a.dead,a.corpseReady=true,true end
    local idle={schema=2,state="idle",slotSqlId=2,deliveries={}}
    assert(not P.completeDeadRemoteArrival(leaseToken,actors,idle) and P.pendingCount()==2
        and not P.save({}),"failed native/view release cannot discard held dead staging or unblock saves")
    slot,owner=nil,nil
    assert(not P.completeDeadRemoteArrival(leaseToken+1,actors,idle) and P.pendingCount()==2,
        "a different token cannot retire another dead crew's staging")
    assert(not P.completeDeadRemoteArrival(leaseToken,{actors[2],actors[1]},idle),
        "dead completion requires the exact captured native roster order")
    actors[2].corpseReady=false
    assert(not P.completeDeadRemoteArrival(leaseToken,actors,idle) and P.pendingCount()==2,
        "view closure alone cannot discard an unproved native corpse")
    actors[2].corpseReady=true
    local export=SC.ExpeditionPrototype.export
    SC.ExpeditionPrototype.export=function() return idle end
    local flush=SCSplitScreenProbe.flushGlobalModDataForWorldExit
    local deadFlushOkay,deadFlushes=false,0
    SCSplitScreenProbe.flushGlobalModDataForWorldExit=function()
        deadFlushes=deadFlushes+1
        assert(store.document.expedition.state=="idle" and store.document.companions[actors[1].id]==nil
            and store.document.companions[actors[2].id]==nil,"native flush sees the installed exact death outcome")
        return deadFlushOkay
    end
    local beforeSpawns=spawns
    local beforeCaptures=captures
    assert(not P.completeDeadRemoteArrival(leaseToken,actors,idle) and P.pendingCount()==2
        and P.pendingSnapshot()[actors[1].id].remoteHeld and deadFlushes==1,
        "failed LF death flush keeps exact held snapshots and completion authority for retry")
    assert(not P.abortRemoteArrival(leaseToken) and captures==beforeCaptures and not P.save({}),
        "a closed dead view cannot republish alive staging through ordinary abort or save while its death flush retries")
    deadFlushOkay=true
    assert(P.completeDeadRemoteArrival(leaseToken,actors,idle) and P.pendingCount()==0
        and store.document.companions[actors[1].id]==nil and store.document.companions[actors[2].id]==nil
        and store.document.expedition.state=="idle" and store.document.companions[unrelated.id]~=nil
        and deadFlushes==2,
        "successful exact dead teardown flushes before dropping held live snapshots without losing unrelated state")
    P.restorePulse({})
    assert(spawns==beforeSpawns and #removedOrder==0,"dead completion neither removes corpse actors nor reconstructs inventory")
    assert(P.save({}) and P.requestScheduledSave({}),"dead completion unblocks ordinary and scheduled saves")
    P.cancelPendingSave("dead completion regression")
    assert(store.document.companions[actors[1].id]==nil and store.document.companions[actors[2].id]==nil,
        "a later normal save never republishes retired preack crew snapshots")
    SC.ExpeditionPrototype.export,SCSplitScreenProbe.cancelRemoteArrival,
        SCSplitScreenProbe.flushGlobalModDataForWorldExit=export,cancel,flush
    assert(P.reset())
end
local function legacyHomeMember(id,order,serial)
    return {id=id,recruited=true,identity={forename="Old",surname="Trip",gender="female"},
        position={x=200,y=200,z=0},skills={},vitals={},order={current=order,commandSerial=serial},
        inventory={schema=2,complete=true,count=0,roots={},equipment={worn={},attached={}}}}
end
local originalSubsystemRestore=SC.ExpeditionPrototype.restore
SC.ExpeditionPrototype.restore=function() return true end
local legacy={schema=SC.Identity.saveSchema,companions={
    ["sc-serial-missing"]=legacyHomeMember("sc-serial-missing","follow"),
    ["sc-serial-newer"]=legacyHomeMember("sc-serial-newer","regroup",12),
    ["sc-serial-stay"]=legacyHomeMember("sc-serial-stay","stay")},factionActors={},
    expedition={schema=9,scout={kind="home",phase="inbound"},roster={"sc-serial-missing","sc-serial-newer","sc-serial-stay"},
        survivors={"sc-serial-missing","sc-serial-newer","sc-serial-stay"},
        commandSerials={["sc-serial-missing"]=7,["sc-serial-newer"]=8,["sc-serial-stay"]=9}}}
SC_TEST_SET_WORLD_STORE({document=legacy})
assert(P.restore({}))
local migrated=P.lastDocument().companions
assert(migrated["sc-serial-missing"].order.commandSerial==7
    and migrated["sc-serial-newer"].order.commandSerial==12
    and migrated["sc-serial-stay"].order.commandSerial==nil,
    "only missing revisions on coherent active-home Follow/Regroup records migrate; newer serials and changed orders win")
assert(legacy.companions["sc-serial-missing"].order.commandSerial==nil,"migration does not mutate caller-owned raw save document")
SC.ExpeditionPrototype.restore=originalSubsystemRestore
print("home_arrival_persistence_harness: passed fresh capture, flush barrier, held partial teardown, idempotence and primary-only cold restore")
