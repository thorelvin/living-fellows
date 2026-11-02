-- SPDX-License-Identifier: MIT
local SC, T = SurvivorCompanion, TERMINAL_TEST
local Lamp, World, check = SC.TerminalLamp, SC.TerminalWorld, T.check
local checksBefore=T.checks
local oldU, oldRegistry, oldFactions, oldCell = SC.GameplayUtil, SC.Registry, SC.Factions, getCell
local function actor(x,y,z,kind)
    local a={x=x,y=y,z=z,kind=kind or "zombie"}
    function a:isDead() return self.dead==true end
    function a:isFakeDead() return self.fake==true end
    function a:isUseless() return self.useless==true end
    function a:getTarget() return self.target end
    return a
end
SC.GameplayUtil={position=function(a) return a.x,a.y,a.z end,
    nowMs=function() return 1000 end, idOf=function(a) return a.id end,
    isExternalHuman=function(a) return a.kind=="external" end,
    isZombie=function(a) return a.kind=="zombie" end,
    call=function(o,m,...) if o and type(o[m])=="function" then return o[m](o,...),true end return nil,false end}
local p=actor(0,0,0,"player")
local zombies,people={},{}
getCell=function() return {getZombieList=function() return {
    size=function() return #zombies end,get=function(_,i) return zombies[i+1] end} end} end
SC.Registry={living=function() return people end,byId=function(id) return id=="crew" and {recruited=true} end}
SC.Factions={isHostileBetween=function(a) return a.hostile==true end}
local a,b,c=actor(3,0,0),actor(1,0,0),actor(2,0,0)
b.fake=true c.useless=true zombies={a,b,c}
local memory={}
local threat=World.nearestThreat(p,memory,1000)
check(threat.distance==3 and threat.actor==a and threat.count==1,"lamp never reveals fake-dead or useless zombies")
check(Lamp.target(threat)==.8,"a nearby stationary threat stays slow")
a.target=p
check(Lamp.target(World.nearestThreat(p,memory,1500))==3,"targeting operator enables closing rate")
a.target=nil a.x=2.4
check(World.nearestThreat(p,memory,2000).closingDistance==2.4,"half-tile movement is measured within 1.5 seconds")
a.x=3
check(World.nearestThreat(p,memory,2001).closingDistance==nil,"retreating threat does not enable fast flashes")
a.z=1
check(World.nearestThreat(p,{},3000).distance==9,"adjacent floor carries six-tile attenuation")
a.z=2
check(World.nearestThreat(p,{},3000).distance==nil,"two floors away is ignored")
local attenuated=actor(20,0,1)
function attenuated:isDead() error("out-of-range native status must not be queried") end
zombies={attenuated}
local outside=World.nearestThreat(p,{},3000)
check(outside.distance==nil and not outside.unknown,
    "adjacent-floor attenuation rejects the outer annulus before reading combat state")
local ally=actor(1,0,0,"human") ally.id="crew" ally.hostile=true
local friendly=actor(2,0,0,"human")
local hostile=actor(8,0,0,"human") hostile.hostile=true
local external=actor(5,0,0,"external") external.hostile=true
people={ally,friendly,hostile,external} zombies={external}
threat=World.nearestThreat(p,{},3000)
check(threat.actor==external and threat.count==2,"hostile native/external humans count once; companions and friendly people excluded")
people={} zombies={}
local state={}
local pulses=0
for now=0,10000,10 do if Lamp.advance(state,{distance=1,closingDistance=1},now) then pulses=pulses+1 end end
check(state.rate<=3 and pulses<=30,"flashing never exceeds three pulses per second")
local prior=state.rate
Lamp.advance(state,{distance=25},11000)
check(prior-state.rate<=.3751,"long frame is capped at 250ms and 1.5Hz/s easing")
Lamp.advance(state,{unknown=true},11250)
check(state.target==0,"unknown cannot invent a new threat")
state.target=2
Lamp.advance(state,{partial=true},11500)
check(state.target==2,"truncated population cannot falsely announce all clear")
Lamp.advance(state,{distance=4},11750)
Lamp.advance(state,{},12000)
check(state.distance==nil,"complete clear discards stale distance for clutch rewards and tick sound")
local before={health=100,bites=0,scratches=0,knocked=false}
check(not Lamp.hit(before,{health=98,bites=0,scratches=0},"HUNGRY"),"hunger damage leaves terminal open")
check(not Lamp.hit(before,{health=98,bites=0,scratches=0},"HEAVYLOAD"),"overburden damage leaves terminal open")
check(not Lamp.hit(before,{health=98,bites=0,scratches=0},"BLEEDING"),"existing bleeding leaves terminal open even with material health loss")
check(Lamp.hit(before,{health=98,bites=1,scratches=0},"BLEEDING"),"a new bite still closes during existing bleeding")
check(Lamp.hit(before,{health=98,bites=0,scratches=0,knocked=true},"BLEEDING"),"knockdown still closes during existing bleeding")
check(Lamp.hit(before,{health=100,bites=1,scratches=0}),"new bite closes without waiting for aggregate health")
check(Lamp.hit(before,{health=100,bites=0,scratches=0},"WEAPONHIT"),"real weapon hit closes without a health delta")
check(not Lamp.hit(before,{health=99.8,bites=0,scratches=0}),"sub-threshold incidental damage is ignored")
check(Lamp.hit(before,{health=99,bites=0,scratches=0}),"unclassified material damage closes")
SC.GameplayUtil,SC.Registry,SC.Factions,getCell=oldU,oldRegistry,oldFactions,oldCell
SC_TEST_REPORT=(SC_TEST_REPORT or "").."; Lamp: "..(T.checks-checksBefore).." bounded sensor/display checks passed"
