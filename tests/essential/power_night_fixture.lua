-- SPDX-License-Identifier: MIT
LivingFellows={}
local SC=LivingFellows
PN={hours=19,tod=19,grid=true,ms=100000,media={},devices={},channels={},stores={},members={},checks=0}
function require() end
ISBaseTimedAction={derive=function() return {} end}
function PN.check(value,message) PN.checks=PN.checks+1 if not value then error(message) end end
function PN.any(value) for key in pairs(value) do return key end return nil end
function PN.at(hours) PN.hours,PN.tod=hours,hours%24 PN.ms=PN.ms+1000 end
local function event()
    local e={handlers={}}
    function e.Add(fn) e.handlers[fn]=true end
    function e.Remove(fn) e.handlers[fn]=nil end
    function e.fire(...) for fn in pairs(e.handlers) do fn(...) end end
    return e
end
Events={OnDeviceText=event()}
ModData={getOrCreate=function(key) PN.stores[key]=PN.stores[key] or {} return PN.stores[key] end}
function isClient() return PN.client==true end
function isServer() return false end
function getGameTime() return {getWorldAgeHours=function() return PN.hours end,getTimeOfDay=function() return PN.tod end} end
function getWorld() return {isHydroPowerOn=function() return PN.grid end} end
local room={}
function PN.square(x,y,z)
    return {getX=function() return x end,getY=function() return y end,getZ=function() return z or 0 end,
        getRoom=function() return room end,canReachTo=function() return PN.reachable~=false end}
end
function PN.actor(id)
    local a={id=id,md=id and {SC_Id=id} or {},known={},xp=0,square=PN.square(10,11),
        commands={recruited=true,order="base_duty"},bo=80,un=70}
    function a:getSquare() return self.square end
    function a:getModData() return self.md end
    function a:isDead() return self.dead==true end
    function a:isAsleep() return self.asleep==true end
    function a:isKnownMediaLine(guid) return self.known[guid]==true end
    function a:addKnownMediaLine(guid) self.known[guid]=true end
    function a:getPerkLevel() return self.level or 0 end
    function a:getXp() return {AddXP=function(_,perk,amount) a.xp=a.xp+amount end} end
    function a:learnRecipe(recipe) self.recipe=recipe end
    function a:getStats() return {add=function(_,stat,amount) if stat=="BOREDOM" then a.bo=a.bo+amount else a.un=a.un+amount end end} end
    function a:getEquipedRadio() return self.equipped end
    return a
end
PN.player=PN.actor()
function getSpecificPlayer(index) if index==0 then return PN.player end end
SC.ControlUtil={}
local U=SC.ControlUtil
function U.call(o,m,...) if o and type(o[m])=="function" then return o[m](o,...) end return nil end
function U.data(o) return U.call(o,"getModData") end
function U.square(o) return U.call(o,"getSquare") end
function U.present(o) return o and o.present~=false end
function U.near() return PN.near~=false end
function U.owns(_,item) return item and item.carried==true end
function U.list(list) return list or {} end
function U.now() return PN.ms end
function U.items() return PN.items or {} end
SC.GameplayUtil={}
function SC.GameplayUtil.call(o,m,...) return U.call(o,m,...),o~=nil and type(o[m])=="function" end
function SC.GameplayUtil.nowMs() return PN.ms end
function SC.GameplayUtil.sameFloor(a,b) return a:getSquare():getZ()==b:getSquare():getZ() end
function SC.GameplayUtil.distance(a,b) return math.abs(a:getSquare():getX()-b:getSquare():getX())+math.abs(a:getSquare():getY()-b:getSquare():getY()) end
function SC.GameplayUtil.canSee() return PN.visible~=false end
SC.Registry={living=function() return PN.members end,idOf=function(a) return a.id end,
    byId=function(id) for _,a in ipairs(PN.members) do if a.id==id then return a.record end end end}
SC.Commands={peek=function(a) return a.commands end}
SC.Downtime={peek=function(a) return {active=a.activity} end}
SC.RadioListening={valid=function(a,activity) return a.activity==activity end}
SC.BaseLife={isInside=function(a) return a.outside~=true end}
SC.TerminalHardware={powered=function(pc) return pc.power~=false end}
SC.TerminalSystem={normalize=function(os) return os end}
SC.Community={addThought=function(a,thought) a.thought=thought end}
SC.Dialogue={register=function() end}
CharacterStat={BOREDOM="BOREDOM",UNHAPPINESS="UNHAPPINESS"}
Perks={Cooking="Cooking"}
SandboxVars={LevelForMediaXPCutoff=10}
function addXp(a,_,amount) a.xp=a.xp+amount end
ISRadioInteractions={getInstance=function() return {checkPlayer=function(a,guid,codes)
    if a.known[guid] then return end
    a:addKnownMediaLine(guid)
    if codes:find("COO+1",1,true) and a:getPerkLevel()<10 then addXp(a,Perks.Cooking,50) end
    if codes:find("RCP=Soup",1,true) then a:learnRecipe("Soup") end
end} end}
ChannelCategory={Television="tv",Radio="radio"}
DynamicRadioChannel={new=function(name,freq,cat,guid)
    return {getGUID=function() return guid end,GetFrequency=function() return freq end,name=name,freq=freq,category=cat}
end}
local manager={getRadioChannel=function(_,guid) return PN.channels[guid] end,
    AddChannel=function(_,ch,overwrite) PN.check(overwrite==false,"existing channels must not be overwritten") PN.channels[ch:getGUID()]=ch end}
local api={getScriptManager=function() return manager end,
    getChannelName=function(_,freq)
        for _,ch in pairs(PN.channels) do if ch.freq==freq then return ch.name end end
        if PN.occupied==freq then return "Another mod" end
    end,
    getRecordedMedia=function() return {getMediaData=function(_,id) return PN.media[id] end} end,
    getDevices=function() return PN.devices end}
function getZomboidRadio() return api end
function PN.mediaRow(id,category)
    local lines={
        {getTranslatedText=function() return "First line" end,getTextGuid=function() return id.."-1" end,getCodes=function() return "BOR-1,COO+1,RCP=Soup" end},
        {getTranslatedText=function() return "Second line" end,getTextGuid=function() return id.."-2" end,getCodes=function() return "BOR-1" end},
        {getTranslatedText=function() return "Final line" end,getTextGuid=function() return id.."-3" end,getCodes=function() return "BOR-1" end}}
    local media={getId=function() return id end,getCategory=function() return category end,
        getLineCount=function() return #lines end,getTranslatedTitle=function() return id end,getLine=function(_,index) return lines[index+1] end}
    PN.media[id]=media return media
end
function PN.receiver(medium,freq)
    local d={channel=freq,on=true,volume=1,media=false,power=true}
    function d:getIsTelevision() return medium=="tv" end
    function d:getChannel() return self.channel end
    function d:getIsTurnedOn() return self.on end
    function d:getDeviceVolume() return self.volume end
    function d:getDeviceVolumeRange() return 10 end
    function d:isPlayingMedia() return self.media end
    function d:canBePoweredHere() return self.power end
    local o={data=d,square=PN.square(10,10),lines={}}
    function o:getSquare() return self.square end
    function o:getDeviceData() return self.data end
    function o:isFacing() return PN.facing~=false end
    function o:AddDeviceText(text,r,g,b,guid,codes)
        self.lines[#self.lines+1]=text
        Events.OnDeviceText.fire(guid,codes,10,10,0,text,self)
    end
    return o
end
PN.pc={md={movableData={LF_LarchOS={locked=false}}},getSquare=function() return PN.player:getSquare() end,
    getModData=function(self) return self.md end}
