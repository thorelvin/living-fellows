-- SPDX-License-Identifier: MIT
local SC,F=SurvivorCompanion,CalebFixture
local C=SC.OddballCaleb
local function check(value,message) assert(value,message) end
local function tick()
    F.now=F.now+500
    C.pulse(F.group,F.player,F.now)
    return C.update(F.actor,F.player,{},C.intentFor(F.actor,F.player,{},F.group),F.group)
end
F.reset()
check(F.group.oddball.site,"outdoor clearing found")
local s=SC.GameplayUtil.gridSquare(11,11,0)
s.tree={}; check(not C.siteFor(SC.GameplayUtil.gridSquare(10,10,0),F.player,true),"odd-offset tree blocks fire site")
s.tree=nil; s.camp=true
check(not C.siteFor(SC.GameplayUtil.gridSquare(10,10,0),F.player,true),"camp excluded")
s.camp=false
check(not C.siteFor(SC.GameplayUtil.gridSquare(10,10,0),F.player,false),"no seeding in sight")
check(C.onSpawn(F.group,F.actor),"spawn scene")
check(F.created==3 and F.actor.holes==2,"real bodies and torn clothing")
check(C.onSpawn(F.group,F.actor) and F.created==3,"reload cannot duplicate family")
for i=1,120 do tick() end
check(F.group.oddball.stage=="burning" and F.actor.burning,"complete tale, real hauling, then native ignition")
check(F.fires==1 and F.lines[#F.lines]=="I WILL JOIN YOU IN DEATH!","one farewell and one fire")
F.now=F.now+3600000
tick(); C.onSpawn(F.group,F.actor)
check(F.group.oddball.stage=="burning" and not F.actor.dead and F.fires==1,"no timed death or replayed ignition")
check(not C.canRecruit(),"cannot recruit")
F.actor.burning=false; tick()
check(F.group.oddball.stage=="burning","brief clothing flame gap does not end a live ground fire")
SC.GameplayUtil.gridSquare(10,10,0).fire=false; tick()
check(F.group.oddball.outcome=="fire_extinguished" and F.fires==1,"extinguishing respected")
F.group.oddball.stage="burning"; F.actor.burning=true; F.actor.dead=true
C.onMemberDeath(F.group,F.actor)
check(F.group.oddball.stage=="dead" and F.group.oddball.outcome=="died_in_fire","native death completes scene")
F.reset(); F.failCreate=true
check(not C.onSpawn(F.group,F.actor),"ambiguous creation rejected")
F.failCreate=false
check(not C.onSpawn(F.group,F.actor) and F.created==1,"ambiguous body is never recreated")
F.reset(); C.onSpawn(F.group,F.actor)
F.group.oddball.met=true; F.group.oddball.taleFinished=true
F.actor.target={x=10,y=10,z=0,data={LF_FamilyPyre="somebody-else",LF_FamilyPyreSlot=1}}
F.group.oddball.activeSlot=1
tick()
check(F.group.oddball.problem=="foreign_drag" and not F.actor.target,"foreign target checked despite stale active slot")
F.reset(); C.onSpawn(F.group,F.actor)
F.group.oddball.met=true; F.group.oddball.workPhase="grabbing"; F.group.oddball.workAt=F.now
F.group.oddball.activeSlot=1
local source=SC.GameplayUtil.gridSquare(7,10,0)
F.actor.target=table.remove(source.bodies,1)
F.pickupLocked=true
F.session=true
check(C.ownsCorpseDrag(F.actor,F.group),"scene claims only its tagged native haul")
tick(); local x=F.actor.x
tick()
check(F.group.oddball.workPhase=="dragging" and F.actor.x==x and F.actor.target,
    "native pickup lock keeps its grapple without navigation or regrabbing")
F.pickupLocked=false; tick()
check(F.actor.x~=x,"hauling resumes after native pickup releases movement")
F.reset(); C.onSpawn(F.group,F.actor)
F.group.oddball.met=true; F.group.oddball.workPhase="grabbing"; F.group.oddball.workAt=1
F.busy=true; F.now=17000; tick()
check(F.group.oddball.problem=="family_work_timeout" and not F.busy,"stuck native work cancelled after bounded wait")
print("PASS Caleb: gathering, story, native fire, reload receipts, interruption and ownership")
