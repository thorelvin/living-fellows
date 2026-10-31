-- SPDX-License-Identifier: MIT
function require() return true end
GRID_TEST={hours=1000,days=40,now=1000,checks=0,clocks=0,powerReads=0,squareReads=0,writes=0,reads=0}
local T=GRID_TEST
local SC={}
SurvivorCompanion=SC
function T.check(value,text) T.checks=T.checks+1 assert(value,"grid "..T.checks..": "..text) end
function T.near(a,b) return math.abs(a-b)<0.00001 end
function T.empty(value) for _ in pairs(value) do return false end return true end
function isClient() return T.client==true end
function isServer() return false end
function getSandboxOptions()
    return {getElecShutModifier=function() T.reads=T.reads+1 return T.shut end,
        set=function(_,key,value) assert(key=="ElecShutModifier") T.shut=value T.writes=T.writes+1 end,
        toLua=function() end}
end
function getWorld() return {getWorldAgeDays=function() return T.days+(T.hours-1000)/24 end} end
ModData={getOrCreate=function(key) T.bucket=T.bucket or {} return T.bucket end,
    get=function() return T.bucket end}
local U={}
SC.ControlUtil=U
function U.call(object,name,...)
    if object and type(object[name])=="function" then return object[name](object,...) end
    return nil
end
function U.hours() T.clocks=T.clocks+1 return T.hours end
function U.now() return T.now end
function U.square(object) return object and object.square end
function U.data(object) return object and object.md end
function U.present(object) return object and object.present~=false and object.square~=nil end
function U.position(object) local square=object.square or object return square.x,square.y,square.z end
function U.skill(player) return player and player.skill or 0 end
function U.list(items) return items or {} end
SC.GameplayUtil={isDead=function(actor) return actor.dead==true end}
SC.Terminal={isComputer=function(object) return object and object.computer==true end}
SC.TerminalSystem={normalize=function(state) return state and state.valid~=false and state end}
SC.TerminalHardware={state=function(object) return object and object.hardware end,
    powered=function(object) T.powerReads=T.powerReads+1 return object and object.powered==true end}
SC.TerminalWorld={powerState=function(square) return {generator=square.generator==true} end}
SC.BaseLife={isInside=function(object) return object.inCamp==true end,resident=function(id) return T.residents[id] end}
SC.Registry={living=function() return T.crew end,idOf=function(actor) return actor.id end}
SC.FactionLife={addMapAnnotation=function() T.marked=(T.marked or 0)+1 return true end}
function getCell()
    return {getGridSquare=function(_,x,y,z) T.squareReads=T.squareReads+1 return T.tiles[x..":"..y..":"..z] end}
end
function T.pc(x,y,atCamp)
    T.ids=T.ids+1
    local square={x=x,y=y,z=0,generator=true,objects={}}
    function square:getX() return self.x end
    function square:getY() return self.y end
    function square:getZ() return self.z end
    function square:getObjects() return self.objects end
    local object={computer=true,powered=true,inCamp=atCamp,square=square,
        md={movableData={LF_LarchOS={identity="pc:"..T.ids,locked=false}}},
        hardware={on=true,radio={id=T.ids}}}
    square.objects={object} T.tiles[x..":"..y..":0"]=square
    return object
end
function T.reset(shut)
    T.hours,T.days,T.now,T.shut,T.ids=1000,40,1000,shut or 26,0
    T.bucket,T.tiles,T.crew,T.residents,T.client=nil,{},{},{},false
    T.clocks,T.powerReads,T.squareReads,T.writes,T.reads,T.marked=0,0,0,0,0,0
    if SC.GridControl then SC.GridControl.reset() end
end
function T.step(hours) T.hours=T.hours+hours T.now=T.now+hours*3600000 end
function T.link(siteIndex)
    local site=SC.GridControl.SITES[siteIndex or 1]
    local pc=T.pc(site.x,site.y,false)
    assert(SC.GridControl.startConnect(pc)) T.step(0.5) SC.GridControl.sample(pc)
    assert(T.bucket.sites[site.id])
    return pc,site
end
function T.ready(skill,sites)
    local G=SC.GridControl
    T.reset()
    local home=T.pc(12000,6800,true)
    local player={skill=skill or 0}
    for index=1,(sites or 1) do
        local _,site=T.link(index)
        assert(G.startCrack(home,player,site.id))
        local task=T.bucket.jobs[home.md.movableData.LF_LarchOS.identity]
        T.step(task.requiredHours) G.sample(home)
        assert(T.bucket.sites[site.id].online)
    end
    return home,player
end
