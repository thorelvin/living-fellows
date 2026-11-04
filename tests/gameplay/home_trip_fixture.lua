-- SPDX-License-Identifier: MIT
-- Production controller + home handover: no native actor duplication, no
-- one-member arrival shortcut, no search/site work hidden behind a home kind.
local SC=SurvivorCompanion
local E,H,I=SC.ExpeditionPrototype,SC.HomeTrip,SC.ExpeditionIntegration
local F={owned=false,now=1000,routeCalls=0,remoteReleases=0,joinedReleases=0,
    available=true,roadAvailable=true,visible=true,releaseFailure=false,removed=false,prepares=0,commits=0,
    commitFailure=false,prepareFailure=false,corpseStageOkay=true,stagedCorpses={},prepareAttempts=0,handoffs=0,
    base={id="base:home-test",core={x=200,y=200,z=0},zones={{kind="area",x1=190,y1=190,x2=210,y2=210,z=0}}},
    records={},orders={},nativeActors={}}
local function at(actor,x,y,z) actor.x,actor.y,actor.z=x,y,z or 0 end
local function actor(id,x,y)
    local a={id=id,x=x,y=y,z=0,data={},inventory={}}
    function a:getX() return self.x end
    function a:getY() return self.y end
    function a:getZ() return self.z end
    function a:isDead() return self.dead==true end
    function a:isCorpseReady() return self.corpseReady==true end
    function a:getCurrentSquare() return self end
    function a:getRoom() return nil end
    function a:getVehicle() return self.vehicle end
    function a:getModData() return self.data end
    function a:getInventory() return self.inventory end
    return a
end
F.player=actor("player",80,80)
for index=1,5 do
    local a=actor("sc-home-"..index,100+index,100)
    F.nativeActors[index]=a
    F.records[index]={id=a.id,actor=a,recruited=true,runtime={}}
    F.orders[a]={order="follow",commandSerial=0}
end
local function call(value,name,...)
    if value and type(value[name])=="function" then return value[name](value,...),true end
    return nil,false
end
local function distance(a,b) return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2) end
SC.GameplayUtil={call=call,position=function(a) return a and a.x,a and a.y,a and a.z end,
    nowMs=function() return F.now end,nameOf=function(a) return a.id end,idOf=function(a) return a.id end,
    isDead=function(a) return a.dead==true end,canSee=function() return F.visible end,
    sameFloor=function(a,b) return a.z==b.z end,distance=distance,
    nativeHealth=function() return 100 end,characterStatValue=function() return 0 end,
    config=function() return nil end,inventory=function(a) return a.inventory end,
    inventoryItemsDeep=function(inventory) return inventory end}
SC.GameplayUtil.gridSquare=function(x,y,z) return {x=x,y=y,z=z} end
SC.Registry={byId=function(id) for _,r in ipairs(F.records) do if r.id==id and not r.unregistered then return r end end end,
    isActive=function(a,id) local r=SC.Registry.byId(id) return not F.removed and r and r.actor==a end}
SC.Commands={peek=function(a) return F.orders[a] end,resumeBaseDutyIfUnchanged=function(id,serial)
    local r=SC.Registry.byId(id)
    if not r or F.orders[r.actor].commandSerial~=serial then return false,"new_player_order" end
    F.orders[r.actor].order="base_duty" return true
end}
SC.BaseLife={active=function() return F.base end,isInside=function(a)
    if not F.base then return false end
    for _,z in ipairs(F.base.zones) do if z.kind=="area" and a.z==z.z and a.x>=z.x1 and a.x<=z.x2 and a.y>=z.y1 and a.y<=z.y2 then return true end end
    return false
end,storageRows=function() return {} end}
SC.BaseWatch={current=function() return nil end}
SC.Vehicle={isNativeSeated=function(a) return a.vehicle~=nil,a.vehicle end}
SC.ViewSession={claim=function(_,a) F.slot,F.owned=a,true return true,a end,owner=function() return F.owned and "expedition" or nil end,
    slotSqlId=function() return 2 end,released=function() F.slot,F.owned=nil,false return true end,
    rememberSlotSqlId=function() end}
SC.Persistence={restoreStatus=function() return true end,completeRemoteArrival=function(token) assert(token==42+F.prepares) return true end,
abortRemoteArrival=function() return F.commitFailure end,
commitRemoteArrival=function(actors,camp,token,integration)
    F.commits=F.commits+1
    if F.commitFailure then return false,"injected pre-ack failure" end
    assert(#actors==2,"remote persistence receives the complete crew")
    assert(I.valid(integration) and integration.kind=="home","durable home obligation accompanies actor snapshots")
    assert(H.campUnchanged(camp) and token==42+F.prepares,"exact captured camp and native ticket")
    local final=E.exportRemoteArrival(integration)
    assert(final and final.state=="idle" and final.schema==2 and #final.deliveries==1
        and final.debrief.kind=="home" and E.current(),"durable finished descriptor leaves live mission owned until teardown")
    return true
end}
SC.Logistics={roleMinimums=function() return {} end,update=function(a)
    a.data.LF_FieldReturnCleanup=nil return false,"load_balanced"
end}
SC.ExpeditionRoute={plan=function(a,target)
    F.routeCalls=F.routeCalls+1
    if not F.roadAvailable then return nil,"no_road" end
    return {points={{x=a.x,y=a.y,z=0,street=""},{x=target.x,y=target.y,z=0,street=""}},
        index=1,roadLength=250,inferredJunctions=0,fingerprint="home-test",goal=target}
end,verifyEntry=function() return true end,descriptor=function(route,phase)
    return {version=1,phase=phase,fingerprint=route.fingerprint,goal=route.goal}
end,validDescriptor=function(d) return type(d)=="table" and d.version==1 and d.phase=="inbound" end}
SCSplitScreenProbe={remoteArrivalCapability=function() return F.available end,
    prepareRemoteArrival=function(actors)
        F.prepareAttempts=F.prepareAttempts+1
        assert(#actors==2)
        for _,a in ipairs(actors) do assert(not a.dead,"remote snapshot roster excludes casualties") end
        for _,a in ipairs(F.nativeActors) do
            if a.dead then assert(F.stagedCorpses[a],"known corpse is retained before remote prepare") end
        end
        if F.prepareFailure then error("injected prepare refusal") end
        F.prepares=F.prepares+1 return 42+F.prepares
    end,
    remoteArrivalSlotSqlId=function() return 2 end,releaseRemoteArrival=function()
        if F.releaseFailure then F.releaseFailure=false return false end
        F.remoteReleases=F.remoteReleases+1 return true
    end,
    leaderSqlId=function() return 2 end,canReleaseJoinedLeader=function() return true end,
    persistJoinedLeaderSlotForReuse=function() return 2 end,
    releaseJoinedLeader=function() F.joinedReleases=F.joinedReleases+1 return true end,
    stageDeadCorpseChunk=function(a)
        assert(a.dead and a.corpseReady,"only a ready native corpse can be retained")
        if not F.corpseStageOkay then return false end
        F.stagedCorpses[a]=true return true
    end,
    handoff=function(a) F.handoffs=F.handoffs+1 F.slot=a return a end,
    releaseForWorldExit=function() F.slot=nil return true end,isLeader=function(a) return a==F.slot end}
function getSpecificPlayer(index) return index==0 and F.player or index==1 and F.slot or nil end
function getGameTime() return {getWorldAgeHours=function() return 100 end} end
function destroyPlayerData() end
Events=nil
F.selection={records={F.records[1],F.records[2]},travelMode="road"}
local function reset()
    if E.current() then assert(E.prepareReset()) end
    assert(E.reset()) H.reset()
    F.available,F.roadAvailable,F.visible=true,true,true
    F.releaseFailure,F.removed=false,false
    F.commitFailure,F.prepareFailure=false,false
    F.corpseStageOkay,F.stagedCorpses=true,{}
    for index,r in ipairs(F.records) do
        r.actor,r.unregistered=F.nativeActors[index],nil
        r.actor.dead,r.actor.corpseReady=nil,nil
        at(r.actor,100+index,100) r.actor.vehicle=nil r.recruited=true
        F.orders[r.actor]={order="follow",commandSerial=0}
    end
    at(F.player,80,80)
end
local function blocked(reason,chosen)
    local d=H.draft(chosen or F.selection,true)
    assert(d.canStart==false and d.blocker==reason,"expected blocker "..reason..", got "..tostring(d.blocker))
end

F.at,F.actor,F.reset,F.blocked=at,actor,reset,blocked
F.call,F.distance=call,distance
SC.HomeTestFixture=F
