-- SPDX-License-Identifier: MIT
-- Exercise the real BaseWork night gate before the farm-specific fixture.
local SC,f=SurvivorCompanion,SurvivorCompanion.TestFixture
local B=SC.BaseLife
local worker=f.actor("night-farmer",2,1,{})
f.registry[worker.id]={actor=worker}
worker.modData.SC_Order="base_duty"
B.create(worker.square,"Night care camp")
B.assign(worker.id,"farmer",true)
B.active().settings.routines=false
f.worldHour=22
SC.Config.values.animalCloseEnabled=1
local okay,door=B.enqueueJob({type="farm",priority=4,target={animal=true,
    operation="animal_close",nativeZoneId="42",zoneId="animal:42",
    deviceKey="hutch:2:1:0",x=2,y=1,z=0}})
f.check(okay,"night door work enters the ordinary farm queue")
f.check(B.priorityWorkFor(worker.id)==door,
    "unassigned door safety outranks optional supply searches for an eligible Farmer")
local oldUpdate=SC.FarmWork.update
SC.FarmWork.update=function() return true,"closing_probe" end
SC.BaseWork.update(worker,f.player,{})
f.check(B.jobFor(worker.id)==door and door.reservedBy==worker.id,
    "an outdoor farmer claims authorized hutch closing before the nighttime return-inside branch")
SC.FarmWork.update=oldUpdate
B.releaseJob(door.id,worker.id,"test")
local other=f.actor("night-generalist",3,1,{})
f.registry[other.id]={actor=other}
B.assign(other.id,"generalist",true)
f.check(B.claimJob(other.id,SC.AnimalWork.nightClosingJob)==nil,
    "the narrow night exception retains ordinary Farmer eligibility")
f.check(B.priorityWorkFor(other.id)==nil,"door urgency cannot admit an ineligible worker")
B.cancelJob(door.id)
f.worldHour=7
local openOkay,opening=B.enqueueJob({type="farm",priority=4,target={animal=true,
    operation="animal_open",nativeZoneId="42",zoneId="animal:42",
    deviceKey="hutch:2:1:0",x=2,y=1,z=0}})
f.check(openOkay and B.priorityWorkFor(worker.id)==opening,
    "dawn opening also outranks optional packing")
local S=SC.ActionSupervisor
local token=S.begin(worker,{owner="downtime",action="gear_check",priority=10,
    interruptible=true,metadata={commandSerial=0}})
f.check(token~=nil,"optional downtime owns the actor before the door is offered")
local peek,cancel,update=SC.Downtime.peek,SC.Downtime.cancel,SC.Downtime.update
local activity,release={kind="gear_check"},false
SC.Downtime.peek=function() return {active=activity} end
SC.Downtime.cancel=function()
    if not release then return false,"cleanup_pending" end
    activity=nil S.complete(token,"released") return true
end
SC.Downtime.update=function() return true,"optional_owned" end
SC.FarmWork.update=function() return true,"closing_probe" end
local quiet,healthy={threatCount=0,immediateCount=0,threats={}}, {health=100,alive=true,bleedingCount=0}
local commands={order="base_duty",recruited=true,commandSerial=0}
SC.Decision._holdOwnedActivityOrPacingForTests(worker,f.player,quiet,healthy,{},commands,{},f.clock,{})
SC.Decision._holdOwnedActivityOrPacingForTests(worker,f.player,quiet,healthy,{},commands,{},f.clock+1001,{})
f.check(S.current(worker)==token and B.jobFor(worker.id)==opening,
    "door priority waits for the optional owner's pending cleanup; owner="..tostring(S.current(worker)==token)
        .." job="..tostring(B.jobFor(worker.id) and B.jobFor(worker.id).id))
release=true
local decision={}
SC.Decision._holdOwnedActivityOrPacingForTests(worker,f.player,quiet,healthy,{},commands,decision,f.clock+2000,{})
f.check(decision.current=="base_work" and S.current(worker)==nil,
    "a released optional activity hands the actor to dawn opening")
SC.Downtime.peek,SC.Downtime.cancel,SC.Downtime.update=peek,cancel,update
SC.FarmWork.update=oldUpdate
local candidate,inside,reach=SC.AnimalWork.candidate,B.isInside,B.withinWorkReach
local audits=0
SC.AnimalWork.candidate=function() audits=audits+1 return nil end
B.isInside=function(subject) if subject==worker then return false end return inside(subject) end
B.withinWorkReach=function(subject) return subject==worker end
SC.FarmWork.audit()
f.check(audits==1,"chicken discovery continues while its Farmer transits the bounded camp reach")
B.withinWorkReach=function() return false end
SC.FarmWork.audit()
f.check(audits==1,"a distant absent Farmer cannot trigger chicken scanning")
SC.AnimalWork.candidate,B.isInside,B.withinWorkReach=candidate,inside,reach
SC.BaseWork.reset(worker)
B.reset()
SC.Config.values.animalCloseEnabled=nil
f.worldHour=12
