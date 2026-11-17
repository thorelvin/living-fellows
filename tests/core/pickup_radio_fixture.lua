-- SPDX-License-Identifier: MIT
require=function() end
SurvivorCompanion={}
local SC=SurvivorCompanion
local F={hooks={},transmissions=0,clock=10,computers={}}
PICKUP_RADIO=F
function F.check(value,message) F.checks=(F.checks or 0)+1 if not value then error("pickup radio: "..message) end end
local function obj(x,y)
    local o={x=x,y=y,z=0,items={}}
    function o:getX() return self.x end
    function o:getY() return self.y end
    function o:getZ() return self.z end
    function o:getSquare() return self end
    function o:getObjectIndex() return 1 end
    function o:isDead() return self.dead==true end
    function o:getEquipedRadio() return self.equipped end
    function o:getInventory() return self.inventory end
    function o:getVehicle() return self.vehicle end
    return o
end
local function data()
    local d={channel=88000,power=1,on=true,mic=false,volume=.8,range=2000}
    function d:getChannel() return self.channel end
    function d:getPower() return self.power end
    function d:getIsTurnedOn() return self.on end
    function d:getHasBattery() return true end
    function d:getIsTwoWay() return true end
    function d:getIsPortable() return true end
    function d:getIsTelevision() return false end
    function d:getMicIsMuted() return self.mic end
    function d:getDeviceVolume() return self.volume end
    function d:isPlayingMedia() return self.media==true end
    function d:isNoTransmit() return self.noTransmit==true end
    function d:getTransmitRange() return self.range end
    return d
end
local function handset(owner)
    local item={radio=true,owner=owner,data=data()}
    local inventory={items={item}}
    function item:getContainer() return inventory end
    function item:getDeviceData() return self.data end
    owner.inventory=inventory owner.equipped=item
    return item
end
F.player=obj(100,100) F.driver=obj(800,800) F.driver.companion=true F.driver.camp=true
F.callerRadio=handset(F.player) F.driverRadio=handset(F.driver)
local function station(id,x,y,camp)
    local o=obj(x,y) o.id=id o.computer=true o.camp=camp o.generation=1 o.on=true
    o.data=data() o.item={} o.receiver={}
    F.computers[id]=o
    return o
end
F.callerPC=station("caller",100,100,false) F.campPC=station("camp",800,800,true)
SC.GameplayUtil={nowMs=function() F.clock=F.clock+1 return F.clock end,
    call=function(o,name,...) if o and o[name] then return o[name](o,...),true end return nil,false end,
    position=function(o) if o then return o.x,o.y,o.z end end,
    instanceOf=function(o,name) return o.radio and name=="Radio" end,
    containerContainsIdentity=function(c,item) for _,i in ipairs(c.items) do if i==item then return true end end return false end}
SC.Actor={isCompanion=function(o) return o and o.companion==true end}
SC.BaseLife={active=function() return {id="base-1"} end,
    isInside=function(o) return o and o.camp==true end,
    describeObject=function(o) return {id=o.id} end,resolveObject=function(ref) return F.computers[ref.id] end}
SC.Terminal={near=function(player,pc) return (player.x-pc.x)^2+(player.y-pc.y)^2<9 end,
    normalPowered=function(pc) return pc.on and not pc.borrowed end,
    isComputer=function(pc) return pc.computer end,peekState=function(pc) return {locked=pc.locked==true} end}
SC.TerminalHardware={state=function(pc) return {generation=pc.generation} end,
    receiver=function(pc) return pc.receiver,pc.data,pc.item end,powered=function(pc) return pc.on end,
    radioStations=function() return {F.callerPC,F.campPC} end}
SC.EmmaJump={active=function(_,pc) return pc.borrowed==true end}
Events={OnDeviceText={Add=function(fn) F.hooks[fn]=true end,Remove=function(fn) F.hooks[fn]=nil end}}
SCBridge={}
SC.Call={static=function(_,name,recipient,receiver,x,y,channel,text,guid,codes,range)
    F.transmissions=F.transmissions+1
    if F.mutate then F.mutate() end
    for fn in pairs(F.hooks) do
        if F.receive~=false then
            fn(F.wrongGuid and "stale" or guid,F.wrongCodes and "stale" or codes,
                x,y,0,F.distorted and "static" or text,F.wrongDevice and {} or receiver)
        end
    end
    return true,true
end}
function getSpecificPlayer(index) return index==0 and F.player or nil end
