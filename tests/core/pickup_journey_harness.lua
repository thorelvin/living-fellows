-- SPDX-License-Identifier: MIT
local F,SC=PICKUP,LivingFellows
local J,check=SC.PickupJourney,PICKUP.check
local watch={leaderActor=F.follower,leaderId="sc-follower",pickupOwner=nil}
F.view,F.viewActor="base_watch",F.follower
local walks=0
SC.Navigation={request=function(actor,target,mode,intent)
    check(actor==F.driver and type(target)=="table" and type(target.x)=="number"
        and target~=F.follower,"navigation receives coordinates, never an actor userdata")
    check(intent.followRecovery==true,"occupied resident square allows ordinary adjacent approach")
    walks=walks+1
    return true
end}
SC.BaseWatch={current=function() return watch end,
    pauseForPickup=function(id) watch.pickupOwner=id return true,F.follower end,
    pickupResumeCandidate=function() return SC.Registry.byId("sc-follower") end,
    resumeFromPickup=function(id,actor)
        check(watch.pickupOwner==id and actor==F.viewActor,"native successor exists before Watch resumes")
        F.view="base_watch" watch.pickupOwner=nil return true
    end}
SC.ViewSession.transfer=function(from,to,actor)
    check(F.view==from and F.viewActor==actor,"view transfer follows exact native actor")
    F.view=to return true
end
SC.ViewSession.adopt=function(mode,actor)
    check(F.view==mode and F.viewActor==actor,"only exact native leader is adopted") return true
end
SCSplitScreenProbe.handoffLiving=function(actor) F.viewActor=actor return actor end
SCSplitScreenProbe.leaderSqlId=function() return 2 end
local ctx={requestId="journey-fixture",driverId="sc-driver"}
local acquired,reason=J.acquire(ctx,F.driver)
check(not acquired and reason=="pickup_handoff_approach" and walks==1 and F.driver.x==100,
    "far driver approaches through ordinary navigation without relocation")
F.driver.x=F.follower.x-5
check(J.acquire(ctx,F.driver) and F.view=="pickup" and ctx.slotSqlId==2,
    "near driver receives the existing view and SQL slot")
check(J.restoreWatch(ctx,F.driver) and F.view=="base_watch" and F.viewActor==F.follower,
    "return hands the real view back to the original resident")
F.view="pickup"
SC.ViewSession.reservedFor=function(owner,id) return owner=="pickup" and id==ctx.requestId end
SCSplitScreenProbe.secondaryAreaContains=function() return true end
ctx.restoring,ctx.restorePoint=true,{x=500,y=500,z=0}
J.setContext(ctx)
check(J.canRestore(ctx.driverId,{x=501,y=500,z=0}),"owned cold loader permits ordinary free-neighbour restoration")
check(not J.canRestore(ctx.driverId,{x=507,y=500,z=0})
    and not J.canRestore(ctx.driverId,{x=500,y=500,z=1}),"saved driver restore remains bounded to its saved floor and neighbourhood")
SCSplitScreenProbe.secondaryAreaContains=function() return false end
check(not J.canRestore(ctx.driverId,{x=500,y=500,z=0}),"cached square cannot grant cold restore authority")
F.view,F.viewActor=nil,nil
SC.BaseWatch.current=function() return nil end
SC.GameplayUtil.gridSquare=function() return {} end
SCSplitScreenProbe.primaryAreaContains=function() return false end
SCSplitScreenProbe.pickupJourneyCapability=function() return true end
SC.ViewSession.reserve=function() return true end
local loader={}
SC.ViewSession.loadPickupArea=function(id,anchor)
    check(id==ctx.requestId and anchor==ctx.restorePoint,"loader uses the validated saved driver anchor")
    F.view,F.viewActor="pickup",loader return true,loader
end
check(not J.warm(ctx) and ctx.loader==loader,"cached unowned square still starts an owned cold loader")
SCSplitScreenProbe.secondaryAreaContains=function() return true end
check(J.warm(ctx),"only the loaded owned secondary area finishes warming")
local uiReleased=false
destroyPlayerData=function(actor) check(actor==loader,"only the exact cold loader's UI is removed") uiReleased=true end
SCSplitScreenProbe.isColdProbe=function(actor) return actor==loader end
SCSplitScreenProbe.cancelColdCompanionProbe=function()
    check(uiReleased,"vanilla UI is destroyed before its cold player slot disappears")
    F.viewActor=nil return true
end
SC.ViewSession.unreserve=function() return true end
check(J.closePreview(ctx) and F.view==nil,"cold preview cancellation releases its exact native slot and UI")
SC_TEST_REPORT="PICKUP_JOURNEY_PASS checks="..tostring(F.checks)
