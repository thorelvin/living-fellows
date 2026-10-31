-- SPDX-License-Identifier: MIT
local SC,T=SurvivorCompanion,GRID_TEST
local R,U=SC.GridRadio,SC.ControlUtil
local check,before=T.check,T.checks
local calls,contacts,hooks={},0,0
T.reset()
local player={square={x=100,y=100,z=0},dead=false}
function player:isDead() return self.dead end
function player:getSecondaryHandItem() return self.radio end
function player:getEquipedRadio() return self.nativeRadio or self.radio end
function player:setHaloNote(text) self.note=text end
function getSpecificPlayer(index) return index==0 and player or nil end
function U.owns(actor,item) return item.owner==actor end
SC.GameplayUtil.position=U.position
local function device()
    local d={on=true,power=1,twoWay=true,channel=90000,range=500}
    function d:getIsTelevision() return self.tv==true end
    function d:getIsTurnedOn() return self.on end
    function d:getHasBattery() return true end
    function d:getPower() return self.power end
    function d:isPlayingMedia() return self.media==true end
    function d:isNoTransmit() return false end
    function d:getIsTwoWay() return self.twoWay end
    function d:getMicIsMuted() return self.mute==true end
    function d:getTransmitRange() return self.range end
    function d:getChannel() return self.channel end
    return d
end
local handset={device=device(),owner=player}
function handset:getDeviceData() return self.device end
player.radio=handset
local home=T.pc(120,100,true) home.device=device()
SC.TerminalHardware.radioStations=function() return {home} end
SC.TerminalHardware.receiver=function(object)
    if object.powered and object.hardware.radio then return object,object.device end
end
SC.GridControl={}
SC.GridControl.snapshot=function(object)
    contacts=contacts+1
    check(object==home,"radio settles only the answering computer")
    return {visible=true,on=false,online=2,heat=10,crack={label="Muldraugh",percent=41.2}}
end
getZomboidRadio=function() return {SendTransmission=function(_,x,y,channel,text,guid,code)
    calls[#calls+1]={x=x,y=y,channel=channel,text=text,guid=guid,code=code}
end} end
Events={OnDeviceText={Add=function(callback) hooks=hooks+1 T.callback=callback end}}
R.install() R.install() R.reset()
check(hooks==1,"radio event is installed once across repeated initialization")
local clocks=T.clocks
local originalNow,reads=U.now,0
U.now=function() reads=reads+1 return originalNow() end
for _=1,1000 do R.onDeviceText("other",nil,0,0,0,"noise") end
check(T.clocks==clocks and contacts==0 and reads==0,"unrelated radio traffic never queries power, grid or world time")
local okay,message=R.request(player,handset)
check(okay and #calls==2 and contacts==1,"one request sends a native call and response")
local sent=calls[2]
check(sent.text:find("41.2%",1,true)~=nil,"response uses the settled controller progress")
local function receive(overrides)
    local v=overrides or {}
    R.onDeviceText(v.guid or sent.guid,v.code or sent.code,v.x or sent.x,v.y or sent.y,0,v.text or sent.text,v.device)
end
receive({guid="stale"}) receive({code="wrong"}) receive({x=sent.x+1}) receive({text="forged"}) receive({device={}})
receive({x=-1,y=-1})
check(R.lastReport(player)==nil,"foreign or mismatched receipt cannot acknowledge a report")
handset.device.channel=94000 receive()
check(R.lastReport(player)==nil,"retuning before reception invalidates acknowledgement")
handset.device.channel=90000 handset.owner=nil receive()
check(R.lastReport(player)==nil,"dropping the handset invalidates acknowledgement")
handset.owner=player player.dead=true receive()
check(R.lastReport(player)==nil,"dead players cannot receive an active contact")
player.dead=false receive({device=handset,x=-1,y=-1})
check(R.lastReport(player)==sent.text and player.note==sent.text,"native handset receipt shows EMMA's report")
R.reset() calls={}
check(R.request(player,handset),"six-argument receipt fixture starts")
sent=calls[2] receive()
check(R.lastReport(player)==sent.text,"source coordinates and the native equipped handset prove a six-argument receipt")
R.reset() calls={}
check(R.request(player,handset),"a subsequent contact is independent")
sent=calls[2] T.now=T.now+15001 receive()
check(R.lastReport(player)==nil,"late native events cannot acknowledge expired contacts")
reads=0
for _=1,1000 do receive() end
check(reads==0,"expired requests stop examining later radio traffic")
local function refused(field,value)
    local d=handset.device local previous=d[field] d[field]=value
    check(not R.request(player,handset),"unusable handset refused: "..field) d[field]=previous
end
refused("on",false) refused("power",0) refused("twoWay",false) refused("tv",true)
refused("mute",true) refused("media",true)
home.device.channel=94000
check(not R.request(player,handset),"both ends must share a channel")
home.device.channel=90000 home.device.mute=true
check(not R.request(player,handset),"station microphone must be open")
home.device.mute=false home.inCamp=false
check(not R.request(player,handset),"yard and outside-camp computers cannot answer as home")
home.inCamp=true home.md.movableData.LF_LarchOS.locked=true
check(not R.request(player,handset),"locked base computers cannot answer")
home.md.movableData.LF_LarchOS.locked=false home.powered=false
check(not R.request(player,handset),"flat or unpowered base computers cannot answer")
home.powered=true player.square.x=119
check(not R.request(player,handset),"native co-located radio exclusion is respected")
player.square.x=100 handset.device.range=10
check(not R.request(player,handset),"handset transmit range limits both-way contact")
handset.device.range=500 home.device.range=10
check(not R.request(player,handset),"station range limits the reply")
home.device.range=500 player.radio=nil
check(not R.request(player,handset),"owning a radio in a bag is insufficient")
player.radio=handset
player.nativeRadio={}
check(not R.request(player,handset),"the engine's receiving handset must match the equipped selection")
player.nativeRadio=nil
getZomboidRadio=function() return {SendTransmission=function() error("native failure") end} end
check(not R.request(player,handset),"native transmission errors are contained")
receive()
check(R.lastReport(player)==nil,"failed native send leaves no pending acknowledgement")
R.reset()
check(hooks==1,"reset clears contacts without duplicate handlers")
SC_TEST_REPORT="GRID_RADIO_PASS checks="..(T.checks-before)
