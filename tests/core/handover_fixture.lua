-- SPDX-License-Identifier: MIT
local F={now=1795200000000,speed=1,records={},world={},log={},snapshots={},serial=0}
SC_HANDOVER_TEST=F
SurvivorCompanion={Identity={worldSaveKey='SC_WorldV1'}}
local SC=SurvivorCompanion
function F.actor(id,companion)
    local a={id=id,companion=companion,md={},x=10,y=20,z=0,health=83,cut=17}
    function a:isDead() return self.dead==true end
    function a:getVehicle() return self.car end
    function a:getModData() return self.md end
    function a:getDescriptor() return {getForename=function() return id end,getSurname=function() return 'Survivor' end} end
    function a:getBodyDamage() return {getOverallBodyHealth=function() return a.health end} end
    return a
end
F.primary=F.actor('Original',false)
function getSpecificPlayer(i) if i==0 then return F.primary end end
function getTimestampMs() return F.now end
function getGameTime() return {getWorldAgeHours=function() return 72 end} end
function setGameSpeed(v) F.speed=v end
function ZombRand() return 123456 end
function isClient() return false end
function isServer() return false end
ModData={getOrCreate=function(key) F.world[key]=F.world[key] or {};return F.world[key] end,get=function(key) return F.world[key] end}
SC.GameplayUtil={isDead=function(a) return a.dead==true end,modData=function(a) return a and a.md end,
    position=function(a) if a then return a.x,a.y,a.z end end,
    call=function(a,k,...) if a and a[k] then return a[k](a,...),true end;return nil,false end}
SC.Actor={isCompanion=function(a) return a.companion end,remove=function(a)
    F.log[#F.log+1]='remove:'..a.id;F.records[a.id]=nil;return true end}
SC.Registry={byId=function(id) return F.records[id] end,idOf=function(a) return a.id end,
    records=function() local r={};for _,row in pairs(F.records) do r[#r+1]=row end;return r end}
function F.recruit(id)
    local a=F.actor(id,true)
    F.records[id]={id=id,actor=a,recruited=true,runtime={},state={order={current='follow',commandSerial=7}}}
    return a
end
SC.Persistence={save=function()
    F.log[#F.log+1]='save'
    if F.saveFail then return false,'injected save refusal' end
    return true
end,pendingBootstrap=function() end}
SCSplitScreenProbe={flushGlobalModDataForWorldExit=function()
    local p=F.world.LF_HandoverV1 and F.world.LF_HandoverV1.pending
    F.log[#F.log+1]='durable:'..(p and p.phase or 'none');return true
end}
SC.HandoverRescue={prepareChoice=function() return true end,pollPreparation=function() end,pulse=function() end}
SC.ActionSupervisor={cancel=function() return true end}
F.car={getSqlId=function() return 11 end,getSeat=function(car,actor) return car.passenger==actor and 1 or -1 end,
    getCharacter=function(car) return car.passenger end,
    exit=function(car,actor) assert(car.passenger==actor,'wrong seat owner');car.passenger=nil;actor.car=nil;F.log[#F.log+1]='exit:'..actor.id end,
    enter=function(car,_,actor) assert(car.passenger==nil,'seat occupied');car.passenger=actor;actor.car=car end,
    setCharacterPosition=function() end,transmitCharacterPosition=function() end,playPassengerAnim=function() end}
SC.Vehicle={stateFor=function(a) return a.car and {vehicle={sqlId=11},seat=1} end,loadedBySqlId=function() return F.car end}
SC.BaseLife={active=function() return F.base end,zoneCenter=function() return F.base and F.base.core end,
    isInside=function() return true end,restoreResident=function() return true end}
F.base={id='base:1',core={x=10,y=20,z=0}}
function getCell() return {getGridSquare=function(_,x,y,z)
    if F.noTiles then return nil end
    return {getX=function() return x end,getY=function() return y end,getZ=function() return z end,
        TreatAsSolidFloor=function() return true end,isSolid=function() return false end,
        isSolidTrans=function() return false end,haveFire=function() return false end,isFree=function() return not F.blockTiles end}
end} end
SC.EmmaMind={operatorId=function(a) return 'operator:'..a.id end,noteDeath=function() end}
CoopCharacterCreation={newPlayerMouse=function() F.creator=true end}
SCBridge={finalizeHandoverDeath=function() return true end,captureHandoverPlayer=function(a)
    F.serial=F.serial+1;local key='snapshot:'..F.serial
    F.snapshots[key]={id=a.id,health=a.health,cut=a.cut,x=a.x,y=a.y,z=a.z};return key
end,prepareHandoverPlayer=function(snapshot,token)
    local source=assert(F.snapshots[snapshot]);local a=F.actor(source.id,false)
    a.health,a.cut,a.x,a.y,a.z=source.health,source.cut,source.x,source.y,source.z
    a.md.LF_HandoverToken=token;return a
end,admitHandoverPlayer=function(a)
    if F.admitFail then error('injected native admission failure') end
    F.log[#F.log+1]='admit';F.next=a;return true
end,recoverHandoverPlayer=function(a)
    F.recoveries=(F.recoveries or 0)+1;F.next=a;return true
end,pollHandoverPlayerAdmission=function() if F.next then F.primary=F.next;F.next=nil end;return not F.primary.dead and F.primary or nil end,
requestHandoverPlayerSave=function() F.log[#F.log+1]='queue-player-save';return true end,
handoverPlayerSaved=function() return F.ack==true end}
local function event() return {Add=function() end,Remove=function() end} end
Events={OnPlayerDeath=event(),OnRenderTick=event()}
