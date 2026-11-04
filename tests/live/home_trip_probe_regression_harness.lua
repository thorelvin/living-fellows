-- SPDX-License-Identifier: MIT
-- Pure probe controls: no game process, native actors, saves or real teleport.
local Probe=SCRealSandboxHarnessProbes.SCHomeTripProbe
local move=assert(Probe._tests.moveFixture,"home fixture movement seam missing")
local fixtureTargetTolerance=assert(Probe._tests.fixtureTargetTolerance,"home fixture tolerance seam missing")
local checks=0
local function expect(value,message)
    checks=checks+1
    assert(value,message)
end
local function actor(x,y,z)
    local value={x=x,y=y,z=z or 0,teleports=0,recoveries=0}
    function value:getX() return self.x end
    function value:getY() return self.y end
    function value:getZ() return self.z end
    function value:teleportTo(tx,ty,tz)
        self.teleports=self.teleports+1
        -- Model the live overload: coordinates coerce to integers and only
        -- become observable on a later engine tick.
        self.queued={x=math.floor(tx),y=math.floor(ty),z=math.floor(tz)}
    end
    function value:applyQueued()
        if self.queued then self.x,self.y,self.z=self.queued.x,self.queued.y,self.queued.z self.queued=nil end
    end
    function value:setBlockMovement(enabled) self.blocked=enabled end
    function value:isDead() return self.dead==true end
    function value:isGhostMode() return self.ghost==true end
    function value:setGhostMode(enabled) self.ghost=enabled end
    function value:isInvisible() return self.invisible==true end
    function value:setInvisible(enabled) self.invisible=enabled end
    function value:setGodMod() error("observer protection must not use God mode") end
    function value:setHealth() error("observer protection must not heal") end
    return value
end
local function context(x,targetX)
    local primary,member=actor(x,0),actor(x+2,2)
    local world={queries=0,recoveries=0,stays=0,allOccupied=false}
    function world:getGridSquare(sx,sy,sz)
        self.queries=self.queries+1
        local square={x=sx,y=sy,z=sz}
        function square:getX() return self.x end
        function square:getY() return self.y end
        function square:getZ() return self.z end
        return square
    end
    local record={id="sc-home-test",actor=member,recruited=true}
    local target={x=targetX,y=0,z=0}
    local f={primary=primary,crew={{id=record.id,actor=member,name="Home Tester"}},frames=100,
        startedAt=0,nextTraceAt=10000,primarySqlId=1,homePose={x=x,y=0,z=0},selection={}}
    local H={player=primary,homeTripAcceptance=f,config={run_id="probe-regression"}}
    SurvivorCompanion={
        Registry={byId=function(id) return id==record.id and record or nil end,snapshot=function() return {record} end},
        GameplayUtil={isSafeSpawnSquare=function(square)
            if world.allOccupied then return false end
            if square.x==math.floor(primary.x) and square.y==math.floor(primary.y) then return false end
            if square.x==math.floor(member.x) and square.y==math.floor(member.y) then return false end
            return true
        end},
        Actor={recover=function(object,square)
            world.recoveries=world.recoveries+1
            object.x,object.y,object.z=square:getX()+.5,square:getY()+.5,square:getZ()
            return true
        end},
        Commands={issue=function() world.stays=world.stays+1 return true end,
            peek=function() return {order="stay",commandSerial=11} end},
        Persistence={isPending=function() return false end},
        ExpeditionPrototype={lastDebrief=function() return nil end},
    }
    getCell=function() return world end
    getFileWriter=function() return nil end
    SCSplitScreenProbe={primaryAreaContains=function() return true end,releaseDiagnostics=function() return "fixture" end}
    return H,f,world,target,primary,member
end

expect(fixtureTargetTolerance==12,"the approved fixture target tolerance changed")
do
    local previousUi=UIManager
    local console={visible=true,changes=0,getClass=function() error("native getClass is not exposed") end}
    setmetatable(console,{__tostring=function() return "zombie.ui.UIDebugConsole@fixture" end})
    function console:setVisible(value) self.visible=value self.changes=self.changes+1 end
    local hud={visible=true}
    setmetatable(hud,{__tostring=function() return "zombie.ui.SpeedControls@fixture" end})
    function hud:setVisible() error("screenshot preparation must not hide ordinary HUD") end
    local reads=0
    UIManager={UI={size=function() return 300 end,get=function(_,index)
        reads=reads+1 expect(index<128,"console hide exceeded its bounded UI list scan")
        return index==1 and console or hud
    end}}
    expect(Probe._tests.hideDebugConsole()==1 and not console.visible and console.changes==1
        and hud.visible and reads==128,
        "screenshot console hiding changed normal HUD, used native reflection or lost the actual console")
    UIManager=previousUi
end
do
    local protect=assert(Probe._tests.protectObserver,"observer protection seam missing")
    local restore=assert(Probe._tests.restoreObserver,"observer restoration seam missing")
    for _,original in ipairs({false,true}) do
        local _,f,world,_,primary,member=context(0,200)
        primary.ghost,primary.invisible=original,original
        expect(protect(f)==true and primary.ghost and primary.invisible,
            "remote main observer did not receive both supported native protection flags")
        expect(f.ghost==original and f.invisible==original and not member.ghost and not member.invisible,
            "observer protection changed a companion or forgot the clone's original flags")
        primary.ghost,primary.invisible=false,false
        expect(protect(f)==true and primary.ghost and primary.invisible and f.observerFlagResets==1
            and string.find(f.lastObserverResetBefore,"invisible=false",1,true),
            "a joined-view flag reset was neither diagnosed nor repaired during owned remote observation")
        restore(f)
        expect(primary.ghost==original and primary.invisible==original and not f.observerProtected
            and primary.teleports==0 and member.teleports==0 and world.recoveries==0,
            "leaving remote observation failed to restore original flags or changed physical actors")
        primary.invisible=original
        Probe._tests.cleanup(f)
        expect(primary.invisible==original,"idempotent final cleanup changed the original invisibility flag")
    end
end

-- Cold saves may contain the temporary invisible flag. The checkpoint's
-- original bucket owns restoration, and an already-near main stays visible.
do
    for _,remote in ipairs({true,false}) do
        local H,_,_,_,primary=context(200,200)
        primary.ghost,primary.invisible=true,true
        H.phase,H.phaseStartedAt="home_trip_setup",0
        H.config.home_trip_mode="resume_active"
        -- Persistence diagnostics have their own seam below; this case runs
        -- the real cold setup against only its required boundary APIs.
        H.homeTripPreflightLogged=true
        local cp={schema=1,state="walking",camp={core={x=0,y=0,z=0}},homePose={x=0,y=0,z=0},
            departure={x=200,y=0,z=0},crew={},primarySqlId=1,observerOriginalInvisible=false,observerOriginalGhost=false}
        SurvivorCompanion.HomeTrip={remoteAvailable=function() return true end,current=function() return nil end}
        SurvivorCompanion.Persistence.commitRemoteArrival=function() return true end
        SCSplitScreenProbe.primaryAreaContains=function() return not remote end
        SCSplitScreenProbe.debugPlayerSqlId=function() return 1 end
        Events={OnPostRender={Add=function() end,Remove=function() end}}
        ModData={get=function() return cp end}
        local failures={}
        local function result(status,label,detail)
            if status=="FAIL" then failures[#failures+1]=label..":"..tostring(detail) end
        end
        local function check(label,value) result(value and "PASS" or "FAIL",label) return value==true end
        local function phase(value,at) H.phase,H.phaseStartedAt=value,at end
        Probe.step(H,0,check,result,phase)
        local f=H.homeTripAcceptance
        expect(#failures==0 and H.phase=="home_trip_resume" and f.invisible==false and f.ghost==false,
            "cold resume forgot the persisted original observer flags; phase="..tostring(H.phase).."; "..table.concat(failures,";"))
        expect(primary.invisible==remote and primary.ghost==remote and f.observerProtected==remote,
            "cold resume protected a near main or exposed a genuinely remote observer")
        Probe._tests.cleanup(f)
        expect(primary.invisible==false and primary.ghost==false,"cold-resume cleanup persisted a temporary invisible observer")
    end
end

-- Death is a failed observation even if the production trip is still active.
-- Restore immediately: a game-over transition may prevent finish_wait ticks.
do
    local H,f,_,_,primary,member=context(200,200)
    Probe._tests.protectObserver(f)
    primary.dead=true H.phase,H.phaseStartedAt="home_trip_walk",0
    local failures,details={},{}
    getCore=function() return {TakeFullScreenshot=function() end} end
    local function result(status,label,detail) if status=="FAIL" then failures[#failures+1]=label details[#details+1]=detail end end
    local function phase(value,at) H.phase,H.phaseStartedAt=value,at end
    Probe.step(H,100,function() error("dead observer must fail before ordinary phase checks") end,result,phase)
    expect(#failures==1 and failures[1]=="home_trip_main_observer_dead" and H.phase=="home_trip_finish_wait"
        and string.find(details[1],"dead=true;ghost=true;invisible=true",1,true),
        "a dead main observer was not rejected with its actual native flag state")
    expect(not primary.invisible and not primary.ghost and not member.invisible and primary.teleports==0,
        "failed observation left temporary flags behind or moved an actor")
end

-- The wrapper observes exactly one existing result, including the first,
-- bounded bends and last point; it neither replans nor edits route/circles.
do
    local _,f=context(0,200)
    local points={} for index=1,100 do points[index]={x=index*2,y=(index%2)*3} end
    local planned,native={points=points},{status="READY"}
    local actorArg,target,circles={}, {x=200,y=100,z=0},{{x=40,y=2,radius=8}}
    local calls=0
    local function original(who,goal,avoid)
        calls=calls+1
        expect(who==actorArg and goal==target and avoid==circles,"route capture replaced the existing planner arguments")
        return planned,"existing-result",native
    end
    SurvivorCompanion.ExpeditionRoute={planAvoidingAll=original}
    Probe._tests.captureRoutes(f)
    local route,reason,receipt=SurvivorCompanion.ExpeditionRoute.planAvoidingAll(actorArg,target,circles)
    expect(calls==1 and route==planned and reason=="existing-result" and receipt==native
        and #points==100 and points[2].x==4 and circles[1].radius==8,
        "route capture replanned, altered data or changed an original return value")
    local count=0 for _ in string.gmatch(f.lastRouteCaptureLine,"|p%d+=") do count=count+1 end
    expect(count==32 and string.find(f.lastRouteCaptureLine,"|p1=2,3",1,true)
        and string.find(f.lastRouteCaptureLine,"|p2=4,0",1,true)
        and string.find(f.lastRouteCaptureLine,"|p3=6,3",1,true)
        and string.find(f.lastRouteCaptureLine,"|p100=200,0",1,true)
        and string.find(f.lastRouteCaptureLine,"|circle1=40,2,8",1,true),
        "route capture lost an endpoint/circle or exceeded its 32-point bound")
    Probe._tests.cleanup(f)
    expect(SurvivorCompanion.ExpeditionRoute.planAvoidingAll==original,"cleanup left the route observer installed")
end
do
    local _,f,_,_,_,member=context(0,200)
    local reads=0 local status={mode="follow",state="following",backward=false,centerDistance=8,heading="not exported"}
    local jobReads,historyReads=0,0
    local job={phase="arrived",result="arrived",reason="road_arrived",parked=true,managed=true,owned=true}
    SurvivorCompanion.Driving={status=function(who)
        reads=reads+1 expect(who==member,"native status observed a different driver") return status
    end,scanLane=function() error("status diagnostics requested a new lane scan") end,
        jobStatus=function(who) jobReads=jobReads+1 expect(who==member,"job diagnostic observed a different driver") return job end}
    SurvivorCompanion.ActionSupervisor={current=function() error("diagnostic serviced current ownership") end,
        snapshot=function() error("diagnostic serviced snapshot ownership") end,
        history=function(who,limit)
            historyReads=historyReads+1 expect(who==member and limit==4,"diagnostic requested an unbounded or different history")
            local rows={} for index=1,6 do rows[index]={event="event"..index,owner="drive",action="drive_route",phase="waiting",reason="reason"..index} end
            return rows
        end}
    local active={leader={actor=member},scout={vehicle={sqlId=99}}}
    Probe._tests.observeDriveStatus(f,active)
    Probe._tests.observeDriveStatus(f,active)
    expect(reads==2 and jobReads==1 and historyReads==1 and f.nativeDriveChanges==1 and string.find(f.lastDriveStatusLine,"centerDistance=8",1,true)
        and not string.find(f.lastDriveStatusLine,"heading",1,true),
        "bounded native status logging read extra data, replanned or emitted an unchanged mode twice")
    status.mode,status.turnState,status.backward="turning","reverse",true
    Probe._tests.observeDriveStatus(f,active)
    expect(reads==3 and f.nativeDriveChanges==2 and string.find(f.lastDriveStatusLine,"backward=true",1,true)
        and status.heading=="not exported","first native reverse mode was lost or source status was changed")
    local historyCount=0 for _ in string.gmatch(f.lastDriveOwnershipLine,"history%d+%.event=") do historyCount=historyCount+1 end
    expect(historyCount==4 and string.find(f.lastDriveOwnershipLine,"job.managed=true;job.leaseCurrent=true",1,true)
        and string.find(f.lastDriveOwnershipLine,"reason3",1,true) and string.find(f.lastDriveOwnershipLine,"reason6",1,true)
        and not string.find(f.lastDriveOwnershipLine,"reason2",1,true),
        "ownership trace lost the exact job lease or exceeded the last-four-history bound")
    active.scout.vehicle.state,active.scout.vehicle.blocker="held","parking_requires_arrived_drive"
    job.owned,job.reason=false,"survival_priority"
    Probe._tests.observeDriveStatus(f,active)
    expect(reads==4 and jobReads==3 and historyReads==3 and f.nativeDriveChanges==3
        and string.find(f.lastDriveOwnershipLine,"job.leaseCurrent=false",1,true)
        and string.find(f.lastDriveOwnershipLine,"job.reason=survival_priority",1,true),
        "a new parking refusal failed to capture a released lease while native idle mode was unchanged")
    SurvivorCompanion.ActionSupervisor=nil
end
do
    local value=actor(0,0)
    local body={health=100,bleeding=0}
    function body:getOverallBodyHealth() return self.health end
    function body:getNumPartsBleeding() return self.bleeding end
    function value:getBodyDamage() return body end
    function value:isBridgeHealthy() return true end
    function value:isDead() return self.dead==true end
    function value:getVehicle() return self.car end
    value.car={}
    expect(not Probe._tests.healthy(value) and Probe._tests.healthy(value,true),
        "a living healthy seated driver was confused with a damaged walking recruit")
    body.health=94
    expect(not Probe._tests.healthy(value,true),"driver health failure was waived")
    body.health=100 body.bleeding=1
    expect(not Probe._tests.healthy(value,true),"bleeding driver was accepted")
    body.bleeding=0 value.dead=true
    expect(not Probe._tests.healthy(value,true),"dead seated driver was accepted")
end
do
    local _,f,_,_,primary=context(0,200)
    f.departure={x=0,y=0,z=0} f.drive={}
    primary.x=.2166
    expect(Probe._tests.primaryFixed(f),"native boarding crowd separation falsely counted as observer travel")
    primary.x=.751
    expect(not Probe._tests.primaryFixed(f),"observer drift larger than the sub-tile bound was accepted")
    primary.x=0 primary.z=.3
    expect(not Probe._tests.primaryFixed(f),"observer floor change was accepted")
    primary.z=0 primary.x=.2166 f.drive=nil
    expect(not Probe._tests.primaryFixed(f),"walking observer bound changed with the driving fixture")
    expect(primary.teleports==0,"observer drift proof moved the observer")
end

-- Trace-only serial diagnostics tolerate missing optional APIs and retain the
-- real handover/command comparison when both diagnostics are available.
do
    local H,f=context(0,200)
    local trace=assert(Probe._tests.trace,"home diagnostic trace seam missing")
    SurvivorCompanion.ExpeditionPrototype.lastDebrief=function()
        return {integration={members={{id=f.crew[1].id,commandSerial=11,dutyDone=true,cleanupDone=false}}}}
    end
    local line=trace(f,"serial-diagnostic")
    expect(string.find(line,"expectedSerial=11;actualSerial=11",1,true)~=nil,
        "serial diagnostics lost the handover-to-command comparison")
    SurvivorCompanion.ExpeditionPrototype=nil SurvivorCompanion.Commands=nil
    expect(pcall(trace,f,"missing-diagnostic-modules"),"missing optional diagnostic modules stopped the probe")
    SurvivorCompanion.ExpeditionPrototype={} SurvivorCompanion.Commands={}
    expect(pcall(trace,f,"missing-diagnostic-methods"),"missing optional diagnostic methods stopped the probe")
    SurvivorCompanion.ExpeditionPrototype.lastDebrief=function() error("diagnostic debrief unavailable") end
    SurvivorCompanion.Commands.peek=function() error("diagnostic command unavailable") end
    expect(pcall(trace,f,"failed-diagnostic-read"),"an unavailable diagnostic read stopped the probe")
end

-- The periodic final-approach trace reads retained state only. In particular,
-- Supervisor.current/snapshot service update and must never be diagnostics.
do
    local _,f,world,_,primary,member=context(0,200)
    member.x,member.y=12031.462,6753.697
    local follower=actor(12030.594,6754.258,.25)
    f.crew[2]={id="sc-home-follower",actor=follower,name="Follower"}
    local originalById=SurvivorCompanion.Registry.byId
    SurvivorCompanion.Registry.byId=function(id)
        if id==f.crew[2].id then return {id=id,actor=follower} end
        return originalById(id)
    end
    local core={x=12034,y=6738,z=0}
    local active={leader={id=f.crew[1].id,actor=member},testWaypoint=core,
        scout={kind="home",phase="inbound",home={camp={core=core},blocker="home_member_not_home"},
            lastStalledTarget={x=12032,y=6752,z=0},lastPlanFailure="no_route",lastRoadFailure="road_failed",
            replans=3,bestDistanceToWaypoint=16.1,lastProgressAt=40000,waypointStagedAt=30000,returnRetryAt=51000}}
    local reads={clock=0,navigation=0,decision=0,history=0,job=0,forbidden=0}
    local function forbidden()
        reads.forbidden=reads.forbidden+1 error("diagnostic attempted a state-changing operation")
    end
    local navigation={active=true,phase="recovering",action="ordered_move",target="12034:6738:0",
        stuckAttempts=2,pathReason="search_yield",pathSearchAgeMs=12000,expandedNodes=320,
        terminalRetryMs=2000,lastMovementReason="blocked_edge",blockerType="door",actorState="walking",
        recoveryResult="retry",searchSliceBudgetMs=2,searchSliceBudgetReason="frame_budget"}
    local decision={current="move_to",intent="ordered_move",lastHandledAt=49500}
    SurvivorCompanion.GameplayUtil.nowMs=function() reads.clock=reads.clock+1 return 50000 end
    SurvivorCompanion.HomeTrip={current=function() return active end,
        finalApproachFor=function(who) expect(who==member,"final-approach diagnostic read another actor") return true end}
    SurvivorCompanion.Navigation={status=function(who)
        reads.navigation=reads.navigation+1 expect(who==member,"navigation diagnostic read another actor") return navigation
    end,request=forbidden,cancel=forbidden,resumePathSearch=forbidden}
    SurvivorCompanion.Decision={peek=function(who)
        reads.decision=reads.decision+1 expect(who==member,"decision diagnostic read another actor") return decision
    end,update=forbidden}
    SurvivorCompanion.Driving={jobStatus=function(who)
        reads.job=reads.job+1 expect(who==member,"job diagnostic read another actor")
        return {phase="arrived",result="arrived",reason="expedition_unload",parked=true,managed=true,owned=false}
    end}
    SurvivorCompanion.ActionSupervisor={current=forbidden,snapshot=forbidden,summary=forbidden,update=forbidden,
        history=function(who,limit)
            reads.history=reads.history+1 expect(who==member and limit==4,"walk diagnostic requested an unbounded history")
            return {{event="completed",owner="navigation",action="ordered_move",phase="done",reason="prior_goal"}}
        end}
    local walkTrace=assert(Probe._tests.walkTraceLine,"pure home walk diagnostic seam missing")
    local line=Probe._tests.trace(f,"walk-diagnostic")
    for _,field in ipairs({"walk.leader=sc-home-test","walk.at=12031.462,6753.697,0",
        "walk.core=12034,6738,0","walk.waypoint=12034,6738,0","walk.lastStalledTarget=12032,6752,0",
        "walk.replans=3","walk.bestDistance=16.1","walk.progressAgeMs=10000","walk.waypointAgeMs=20000",
        "walk.returnRetryMs=1000","gate.homeRelease=false","gate.recalling=false","gate.coreLoaded=true",
        "gate.cohesion=false","gate.pause=false","walk.finalApproach=true","nav.phase=recovering",
        "nav.action=ordered_move","nav.pathSearchAgeMs=12000","nav.expandedNodes=320","nav.stuckAttempts=2",
        "nav.terminalRetryMs=2000","nav.lastMovementReason=blocked_edge","nav.blockerType=door",
        "decision.current=move_to","decision.handledAgeMs=500","walk.ownerRead=history_only",
        "job.leaseCurrent=false","history1.owner=navigation","sc-home-follower@12030.594,6754.258,0.25"}) do
        expect(string.find(line,field,1,true)~=nil,"walk diagnostic lost retained field: "..field)
    end
    expect(reads.clock==1 and reads.navigation==1 and reads.decision==1 and reads.history==1 and reads.job==1
        and reads.forbidden==0 and world.queries==1 and primary.teleports==0 and member.teleports==0
        and follower.teleports==0 and world.recoveries==0 and world.stays==0,
        "periodic walk diagnostic advanced navigation/ownership or scanned beyond its one core-square read")
    expect(active.testWaypoint==core and active.scout.lastProgressAt==40000 and active.scout.waypointStagedAt==30000
        and active.scout.replans==3 and navigation.pathSearchAgeMs==12000 and decision.lastHandledAt==49500,
        "walk diagnostic mutated retained mission, planner or decision state")
    active.homeRelease={committed=false}
    active.technicalIssue={reason="view_wait"} active.cohesionHold={reason="member_wait"}
    active.scout.pause={reason="return_route_stuck"} active.scout.home.recalling=true
    SurvivorCompanion.HomeTrip.finalApproachFor=function() return false end
    world.getGridSquare=function() return nil end
    line=walkTrace(active)
    for _,field in ipairs({"gate.homeRelease=true","gate.committed=false","gate.technical=view_wait",
        "gate.cohesion=true","gate.cohesionReason=member_wait","gate.pause=true",
        "gate.pauseReason=return_route_stuck","gate.recalling=true","gate.coreLoaded=false","walk.finalApproach=false"}) do
        expect(string.find(line,field,1,true)~=nil,"walk diagnostic lost active gate: "..field)
    end
    navigation.pathReason=string.rep("long;|\n",1000)
    line=walkTrace(active)
    expect(#line<8192 and not string.find(line,"\n",1,true) and string.find(line,"nav.pathReason=long___",1,true),
        "walk diagnostic emitted an unbounded or multiline reason")
    SurvivorCompanion.Navigation.status=function() error("status unavailable") end
    SurvivorCompanion.Decision.peek=function() error("decision unavailable") end
    world.getGridSquare=function() error("cell unavailable") end
    line=walkTrace(active)
    expect(string.find(line,"nav.status=unavailable",1,true) and string.find(line,"decision.status=unavailable",1,true)
        and string.find(line,"gate.coreLoaded=nil",1,true) and reads.forbidden==0,
        "an unavailable pure reader stopped diagnostics or was replaced by a mutating reader")
    SurvivorCompanion.Navigation,SurvivorCompanion.Decision,SurvivorCompanion.Driving,SurvivorCompanion.ActionSupervisor=nil,nil,nil,nil
    expect(pcall(walkTrace,active) and walkTrace(nil)==nil,"missing optional walk diagnostic modules stopped the probe")
end

-- Post-arrival delivery diagnostics reuse the current debrief overlay and may
-- inspect only bounded retained navigation/history, never service an owner.
do
    local _,f,world,_,primary,member=context(0,200)
    f.drive,f.phase={},"home_trip_duty"
    local records={[f.crew[1].id]={id=f.crew[1].id,actor=member}}
    for index=2,5 do
        local id="sc-delivery-"..index local companion=actor(index,2)
        f.crew[index]={id=id,actor=companion,name="Returned "..index}
        records[id]={id=id,actor=companion}
    end
    SurvivorCompanion.Registry.byId=function(id) return records[id] end
    local reads={summary=0,navigation=0,nativePath=0,decision=0,clock=0,history=0,car=0,stationary=0,eligible=0,forbidden=0}
    local function forbidden() reads.forbidden=reads.forbidden+1 error("delivery diagnostic attempted to service or rediscover work") end
    local active
    local integration={kind="home",carId=49,members={},items={}}
    local summary={trunkPending=8,stored=3,pending=9,carried=1,released=2,complete=false,
        items={{nativeId=101,stored=true},{nativeId=102,released=true}}}
    for index=3,14 do summary.items[index]={nativeId=100+index,itemType="Base.NailsBox",carrierKind=index==3 and "member" or "trunk",
        carrierId=f.crew[1].id,reason=index==3 and "car_item_carried" or string.rep("blocked;|\n",100)} end
    SurvivorCompanion.HomeTrip={current=function() return active end}
    SurvivorCompanion.ExpeditionPrototype={lastDebrief=function() return {integration=integration} end,integrationFor=forbidden}
    SurvivorCompanion.ExpeditionIntegration={wants=forbidden,update=forbidden,summary=function(record)
        reads.summary=reads.summary+1 expect(record==integration,"delivery trace replaced the already current debrief integration") return summary
    end}
    local car=actor(12030.5,6759.5)
    function car:getSqlId() return 49 end
    function car:getCurrentSpeedKmHour() return 0 end
    function car:isEngineRunning() return false end
    function car:isTrunkLocked() return true end
    local eligibility={okay=false,reason="car_trunk_locked"}
    SurvivorCompanion.Vehicle={loadedBySqlId=function(id)
        reads.car=reads.car+1 expect(id==49,"delivery trace looked up a different or second car") return car
    end,isStationary=function(value)
        reads.stationary=reads.stationary+1 expect(value==car,"stationary diagnostic inspected another car") return true
    end}
    SurvivorCompanion.VehicleUnload={eligible=function(value)
        reads.eligible=reads.eligible+1 expect(value==car,"unload diagnostic inspected another car")
        return eligibility.okay,eligibility.okay and {zoneId="parking:1",trunk=setmetatable({},{__tostring=forbidden})} or eligibility.reason
    end,update=forbidden,takeExact=forbidden}
    SurvivorCompanion.Navigation={status=function(who)
        reads.navigation=reads.navigation+1
        expect(who~=f.crew[5].actor,"delivery diagnostic exceeded four crew")
        return {phase="planning",action="expedition_delivery",target="12030:6759:0",pathReason="storage_route_pending",
            pathSearchAgeMs=12000,pathFailureClass="budget_exhausted",searchSliceBudgetMs=3,searchSliceBudgetReason="load_pressure",
            expandedNodes=85,terminalReason="budget",actorState="idle",recoveryResult="retry",
            blockerType="car",lastMovementReason="blocked_edge"}
    end,request=forbidden,cancel=forbidden,serviceCrowdYield=forbidden}
    SurvivorCompanion.NativeActions={pathTelemetry=function(who)
        reads.nativePath=reads.nativePath+1 expect(who~=f.crew[5].actor,"native path diagnostic exceeded four crew")
        return {available=true,status="pending",active=true,pending=true,shouldBeMoving=true,hasStartedMoving=false,
            movingUsingPathFind=true,pathNextIsSet=true,pathNextX=12030,pathNextY=6759,behavior=setmetatable({},{__tostring=forbidden})}
    end,pathNearest=forbidden,visualStatus=forbidden,update=forbidden}
    SurvivorCompanion.GameplayUtil.nowMs=function() reads.clock=reads.clock+1 return 50000 end
    SurvivorCompanion.Decision={peek=function(who)
        reads.decision=reads.decision+1 expect(who~=f.crew[5].actor,"delivery decision diagnostic exceeded four crew")
        return {current="expedition_delivery",intent="storage_route_pending",lastReason="path_search_deferred",lastHandledAt=49500}
    end,update=forbidden}
    SurvivorCompanion.ActionSupervisor={current=forbidden,snapshot=forbidden,summary=forbidden,update=forbidden,
        history=function(who,limit)
            reads.history=reads.history+1 expect(limit==2 and who~=f.crew[5].actor,"delivery diagnostic history was unbounded")
            local rows={} for index=1,10 do rows[index]={event="yielded",owner="navigation",action="expedition_delivery",phase="approach",reason="history-"..index} end
            return rows
        end}
    local line=Probe._tests.trace(f,"delivery-diagnostic")
    for _,field in ipairs({"delivery.trunkPending=8","delivery.stored=3","delivery.pending=9",
        "delivery.car.expectedSqlId=49","delivery.car.sqlId=49","delivery.car.x=12030.5","delivery.car.y=6759.5",
        "delivery.car.speedKph=0","delivery.car.stationary=true","delivery.car.engineRunning=false",
        "delivery.car.trunkLocked=true","delivery.car.unloadEligible=false","delivery.car.unloadReason=car_trunk_locked",
        "delivery.receipt1.nativeId=103","delivery.receipt1.itemType=Base.NailsBox","delivery.receipt1.carrierKind=member","delivery.receipt1.reason=car_item_carried",
        "delivery.receipt6.nativeId=108","delivery.crew1.nav.phase=planning","delivery.crew1.nav.action=expedition_delivery",
        "delivery.crew1.nav.target=12030:6759:0","delivery.crew1.nav.pathReason=storage_route_pending",
        "delivery.crew1.nav.pathSearchAgeMs=12000","delivery.crew1.nav.blockerType=car",
        "delivery.crew1.nav.pathFailureClass=budget_exhausted","delivery.crew1.nav.searchSliceBudgetMs=3",
        "delivery.crew1.nav.searchSliceBudgetReason=load_pressure",
        "delivery.crew1.nav.expandedNodes=85","delivery.crew1.nav.terminalReason=budget",
        "delivery.crew1.nav.actorState=idle","delivery.crew1.nav.recoveryResult=retry",
        "delivery.crew1.nativePath.status=pending","delivery.crew1.nativePath.pending=true",
        "delivery.crew1.nativePath.hasStartedMoving=false","delivery.crew1.nativePath.pathNextX=12030",
        "delivery.crew1.decision.current=expedition_delivery","delivery.crew1.decision.intent=storage_route_pending",
        "delivery.crew1.decision.lastReason=path_search_deferred","delivery.crew1.decision.handledAgeMs=500",
        "delivery.crew1.history1.reason=history-9","delivery.crew1.history2.reason=history-10"}) do
        expect(string.find(line,field,1,true),"delivery diagnostic lost actual retained field: "..field)
    end
    local receiptCount,historyCount=0,0
    for _ in string.gmatch(line,"delivery%.receipt%d+%.nativeId=") do receiptCount=receiptCount+1 end
    for _ in string.gmatch(line,"delivery%.crew%d+%.history%d+%.event=") do historyCount=historyCount+1 end
    expect(reads.summary==1 and reads.navigation==4 and reads.nativePath==4 and reads.decision==4 and reads.clock==1
        and reads.history==4 and reads.car==1 and reads.stationary==1 and reads.eligible==1 and reads.forbidden==0
        and receiptCount==6 and historyCount==8 and not line:find("delivery.crew5",1,true)
        and not line:find("\n",1,true) and #line<16000 and world.queries==0
        and primary.teleports==0 and member.teleports==0 and world.recoveries==0 and world.stays==0,
        "delivery trace must remain bounded, single-line and read-only without repeated wants lookups")
    eligibility.okay=true
    line=Probe._tests.trace(f,"eligible-delivery-car")
    expect(line:find("delivery.car.unloadEligible=true",1,true) and line:find("delivery.car.parkingZoneId=parking:1",1,true)
        and not line:find("car_trunk_locked",1,true) and reads.forbidden==0,
        "successful unload eligibility must expose only its parking ID, never stringify native trunk/behavior references")
    f.phase="home_trip_walk" Probe._tests.trace(f,"not-delivery-phase")
    f.phase,f.drive="home_trip_duty",nil Probe._tests.trace(f,"walking-duty")
    expect(reads.clock==2,"inactive delivery diagnostics performed an extra clock read")
    -- The pre-existing active-mission walk trace reads one clock even when its
    -- optional leader is absent; delivery-specific readers must still stay off.
    f.drive,active={},{} Probe._tests.trace(f,"active-mission")
    expect(reads.summary==2 and reads.navigation==8 and reads.nativePath==8 and reads.decision==8 and reads.clock==3
        and reads.history==8 and reads.car==2 and reads.stationary==2 and reads.eligible==2 and reads.forbidden==0,
        "delivery-specific reads escaped drive/no-mission/duty gating")
    expect(summary.items[3].reason=="car_item_carried" and integration.kind=="home",
        "delivery diagnostic changed retained receipt or integration state")
end

-- A global capture blocker may name a companion outside the home crew. Read
-- exactly that one record without turning plausible raw XYZ into an anchor.
do
    local _,f,world,_,primary,member=context(0,200)
    local other=actor(999,888)
    local runtime={inactive=false,positionUnstableUntil=15000}
    local record={id="sc-capture-other",actor=other,runtime=runtime}
    local reads={registry=0,clock=0,validation=0,forbidden=0}
    local function forbidden() reads.forbidden=reads.forbidden+1 error("capture diagnostic used raw position as authority or serviced an actor") end
    SurvivorCompanion.Registry.byId=function(id)
        reads.registry=reads.registry+1 expect(id==record.id,"capture diagnostic inspected an unreferenced companion") return record
    end
    SurvivorCompanion.GameplayUtil.nowMs=function() reads.clock=reads.clock+1 return 10000 end
    SurvivorCompanion.Actor={validateNative=function(value)
        reads.validation=reads.validation+1 expect(value==other,"capture diagnostic validated a different actor")
        return false,"living native companion has no current world square;|\n"
    end,recover=forbidden,stop=forbidden}
    SurvivorCompanion.Persistence.noteStablePosition=forbidden SurvivorCompanion.Persistence.captureRecord=forbidden
    SCSplitScreenProbe.primaryAreaContains=forbidden
    local active={scout={home={blocker="active companion capture failed: sc-capture-other: no verified position; active companion capture failed: sc-second"}}}
    local line=Probe.captureBlockerTraceLine(active)
    for _,value in ipairs({"capture.actor.id=sc-capture-other","capture.actor.currentSquarePresent=false",
        "capture.actor.rawXYZ=999,888,0","capture.actor.stablePositionPresent=false","capture.actor.stableSnapshotPresent=false",
        "capture.actor.inactive=false","capture.actor.positionUnstableRemainingMs=5000","capture.actor.nativeValid=false"}) do
        expect(line:find(value,1,true),"capture diagnostic lost bounded restore-anchor evidence: "..value)
    end
    expect(reads.registry==1 and reads.clock==1 and reads.validation==1 and reads.forbidden==0 and not line:find("\n",1,true)
        and #line<2048 and other.teleports==0 and member.teleports==0 and primary.teleports==0 and world.recoveries==0,
        "capture blocker diagnostic scanned beyond one record, mutated state or emitted unbounded text")
    runtime.lastStablePosition,runtime.lastStableSnapshot={x=1,y=2,z=0},{position={x=1,y=2,z=0}}
    runtime.positionUnstableUntil=9000
    function other:getCurrentSquare() return {} end
    line=Probe.captureBlockerTraceLine(active)
    expect(line:find("currentSquarePresent=true",1,true) and line:find("stablePositionPresent=true",1,true)
        and line:find("stableSnapshotPresent=true",1,true) and line:find("positionUnstableRemainingMs=0",1,true)
        and runtime.lastStablePosition.x==1 and other.x==999,"capture diagnostic replaced a durable anchor with raw coordinates")
    active.scout.home.blocker="home_car_save_pending"
    expect(Probe.captureBlockerTraceLine(active)==nil and reads.registry==2 and reads.clock==2 and reads.validation==2,
        "unrelated blockers triggered an extra companion/clock/native validation read")
end

-- Reproduce the live 8.514693m remainder on valid floor. The arbitrary setup
-- target has no free floor nearby, but setup is already within its bounded goal.
do
    local H,f,world,target,primary=context(12228,12234.5)
    primary.y,target.y=6744,6738.5
    world.allOccupied=true
    local done=move(H,f,target,true)
    expect(done==true,"an already-near primary searched occupied squares instead of completing setup")
    expect(world.queries==0 and primary.teleports==0 and world.recoveries==0,
        "near-target convergence moved actors or depended on finding another free square")
end
do
    local H,f,world,target=context(200-fixtureTargetTolerance,200)
    world.allOccupied=true
    expect(move(H,f,target,false)==true,"the approved named twelve-metre setup boundary did not converge")
    expect(world.queries==0,"exactly-twelve-metre convergence queried occupied floor")
end
do
    local H,f,world,target,primary=context(200-fixtureTargetTolerance-1,200)
    world.allOccupied=true
    local done=move(H,f,target,true)
    expect(done==nil and world.queries>0,"a primary outside the setup tolerance was falsely marked complete")
    expect(primary.teleports==0 and world.recoveries==0,"unavailable safe floor triggered a forced fixture movement")
end

-- A successful queued/coerced step reports progress first. On the next tick it
-- must converge inside the same tolerance without demanding unoccupied floor.
do
    local H,f,world,target,primary=context(0,32+fixtureTargetTolerance-.5)
    local done=move(H,f,target,true)
    expect(done==nil and primary.teleports==1 and primary.x==0,
        "queued teleport was treated as immediate failure or fabricated arrival")
    expect(primary.queued and primary.queued.x==32 and world.recoveries==1 and world.stays==1,
        "fixture step did not preserve the integer teleport/public companion recovery contract")
    primary:applyQueued()
    expect(math.abs(primary.x-target.x)>8 and math.abs(primary.x-target.x)<=fixtureTargetTolerance,
        "queued integer fixture did not reproduce the former eight/twelve tolerance gap")
    world.allOccupied=true
    local queries=world.queries
    done=move(H,f,target,true)
    expect(done==true and primary.teleports==1 and world.queries==queries and world.recoveries==1,
        "queued integer teleport stalled near target or moved crew again after convergence")
end
do
    local H,f,world,target,primary=context(0,32+fixtureTargetTolerance-.5)
    expect(move(H,f,target,false)==nil,"queued revisit setup fabricated immediate arrival")
    expect(world.recoveries==0 and world.stays==0,"primary revisit moved or commanded companions")
    primary:applyQueued() world.allOccupied=true
    expect(move(H,f,target,false)==true,"primary revisit did not converge with occupied final floor")
end

-- A saved dispatch checkpoint can diagnose a later pending delivery without
-- inventing its missing precommit capture or replaying physical trip setup.
do
    local oldArrayList=ArrayList
    local function fixture()
        local H,f,world,_,primary,member=context(0,200)
        local id=f.crew[1].id
        local state={events={},shots={},nativeActors={member},pending=1,stored=0,complete=false,holder="trunk",order="base_duty",forbidden=0}
        local function forbidden() state.forbidden=state.forbidden+1 error("delivery replay changed setup, ownership or normal trip proof") end
        local function list(rows) return {size=function() return #rows end,get=function(_,index) return rows[index+1] end} end
        local camp={id="camp:delivery",core={x=0,y=0,z=0},fingerprint="camp:delivery|original"}
        local cargo={id="native:cargo",nativeId=201,itemType="Base.NailsBox"}
        local receipt={sqlId=49,x=10,y=0,z=0,valid=true}
        local integration={kind="home",tripId="trip:delivery",carId=49,members={{id=id}},items={{id=cargo.id,nativeId=201,itemType=cargo.itemType,carrierKind="trunk"}}}
        local report={kind="home",endReason="home",camp=camp,vehicleSqlId=49,carSaveReceipt=receipt,integration=integration}
        local vitals={health=1,overallHealth=100,infected=false,parts={}}
        local item={id=101}
        function item:getID() return self.id end function item:getFullType() return "Base.Hammer" end function item:getCondition() return 10 end
        state.crewItems={item}
        function member:getInventory() return {getItems=function() return list(state.crewItems) end} end
        function member:isBridgeHealthy() return not state.unhealthy end
        function member:getBodyDamage() return {getOverallBodyHealth=function() return state.unhealthy and 80 or 100 end,getNumPartsBleeding=function() return 0 end} end
        function member:hasModData() return true end function member:getModData() return {SC_Id=id} end
        function member:getFullName() return "Home Tester" end
        local car=actor(10,0)
        function car:getSqlId() return state.carId or 49 end
        function car:isEngineRunning() return state.engine==true end
        function car:getCurrentSpeedKmHour() return state.speed or 0 end
        local saved={id=id,recruited=true,identity={forename="Home",surname="Tester"},
            inventory={schema=2,complete=true,count=1,equipment={worn={},attached={}},preserveNativeIds=true,
                roots={{id="i1",nativeId=101,type="Base.Hammer",condition=10,children={},weaponParts={}}}},vitals=vitals}
        local document={companions={[id]=saved},expedition={state="idle",debrief={kind="home",vehicleSqlId=49,
            integration={tripId="trip:delivery",carId=49}},deliveries={{kind="home",tripId="trip:delivery",carId=49}}}}
        local cp={schema=1,state="walking",camp=camp,homePose={x=0,y=0,z=0},departure={x=200,y=0,z=0},
            primarySqlId=1,crew={{id=id,name="Home Tester"}},drive={variant="parking",sqlId=49,cargo={cargo}},walls={},cars={},
            observerOriginalInvisible=false,observerOriginalGhost=false}
        H.config.home_trip_mode,H.config.home_trip_transport="resume_delivery","drive"
        H.phase,H.phaseStartedAt,H.homeTripPreflightLogged="home_trip_setup",0,true
        f.mode,f.camp,f.drive,f.primarySqlId="resume_delivery",camp,cp.drive,1
        SurvivorCompanion.HomeTrip={remoteAvailable=function() return true end,current=function() return state.active end,
            campUnchanged=function(value) return not state.campChanged and value and value.fingerprint==camp.fingerprint end,
            validCarReceipt=function(value,wanted) return value and value.valid==true and value.sqlId==wanted end}
        SurvivorCompanion.ExpeditionPrototype={current=function() return state.expedition end,lastDebrief=function() return report end,integrationFor=forbidden}
        SurvivorCompanion.ExpeditionIntegration={summary=function(value)
            return {pending=state.pending,stored=state.stored,complete=state.complete,items=value.items,members={}}
        end}
        SurvivorCompanion.BaseWatch={current=function() return state.watch end}
        SurvivorCompanion.ViewSession={owner=function() return state.view end}
        SurvivorCompanion.BaseLife={isInside=function() return not state.outside end,withinWorkReach=function() return not state.outsideReach end}
        SurvivorCompanion.Vitals={capture=function() return state.vitals or vitals end}
        local originalById=SurvivorCompanion.Registry.byId
        SurvivorCompanion.Registry.byId=function(wanted) if not state.crewMissing then return originalById(wanted) end end
        SurvivorCompanion.Registry.idOf=function(value) return value==member and id or nil end
        SurvivorCompanion.Registry.isActive=function(value,wanted) return not state.inactive and value==member and wanted==id end
        SurvivorCompanion.Commands.peek=function() return {order=state.order} end
        SurvivorCompanion.Persistence={lastDocument=function() return document end,isPending=function() return state.restorePending==true end,commitRemoteArrival=forbidden,
            validateDetachedItem=function(snapshot)
                local root=snapshot.roots[1]
                if type(root)~="table" or type(root.type)~="string" or root.type=="" or type(root.id)~="string" then return nil,"invalid inventory node" end
                if snapshot.preserveNativeIds==true and type(root.nativeId)~="number" then return nil,"missing saved native item identity" end
                return {roots={root},count=1}
            end}
        SurvivorCompanion.Vehicle={loadedBySqlId=function(wanted)
            state.carReads=(state.carReads or 0)+1
            if not state.carMissing and wanted==49 then return car end
        end,
            isStationary=function() return not state.moving end}
        IsoPlayer={getInstance=function() return state.singleton or primary end}
        getSpecificPlayer=function(index) if index==0 then return primary elseif index==1 then return state.secondary end end
        SCSplitScreenProbe.isReleased=function() return not state.unreleased end
        SCSplitScreenProbe.primaryAreaContains=function() return not state.unloaded end
        SCSplitScreenProbe.debugPlayerSqlId=function() return state.primaryId or 1 end
        function world:getObjectList() return list(state.nativeActors) end
        ArrayList={new=function(value) return value end}
        Events={OnPostRender={Add=function() end,Remove=function() end}}
        ModData={get=function() return cp end,getOrCreate=forbidden}
        getCore=function() return {TakeFullScreenshot=function(_,filename) state.shots[#state.shots+1]=filename end} end
        local function result(status,label,detail) state.events[#state.events+1]={status=status,label=label,detail=detail} end
        local function check(label,value,detail) result(value and "PASS" or "FAIL",label,detail) return value==true end
        local function phase(value,at) H.phase,H.phaseStartedAt=value,at end
        function state:step(at,frames)
            if H.homeTripAcceptance then H.homeTripAcceptance.frames=frames or 0 end
            Probe.step(H,at,check,result,phase)
        end
        state.item,state.car,state.report,state.document,state.integration,state.check=item,car,report,document,integration,check
        state.drive={auditDelivery=function()
            if state.auditFailure then return false,state.auditFailure end
            if state.auditPending then return nil,"bounded_native_cargo_audit_pending" end
            return true,{[201]=state.holder},{[201]=state.carrier}
        end,afterRestored=forbidden,checkFinal=forbidden,prepareCamp=forbidden,prepareField=forbidden}
        return H,f,cp,state,world,primary,member
    end
    local function pickupFixture()
        local H,f,cp,state,world,primary,member=fixture()
        local id=f.crew[1].id
        H.config.home_trip_mode="save_delivery" H.phase="home_trip_duty"
        f.mode,f.dutyReported="save_delivery",{}
        f.drive={variant="parking",sqlId=49,cargo={{id="native:cargo",nativeId=201,itemType="Base.NailsBox"}},
            beforeCommit={position={x=10,y=0,z=0},carSaveReceipt=state.report.carSaveReceipt}}
        state.holder,state.carrier="crew",id
        local saved=state.document.companions[id].inventory
        saved.roots[2]={id="iCargo",nativeId=201,type="Base.NailsBox",condition=10,children={},weaponParts={},modData={LF_ItemStableId="native:cargo"}}
        saved.count=2
        local root={getID=function() return 201 end,getFullType=function() return "Base.NailsBox" end,
            getCondition=function() return 10 end,getModData=function() return {LF_ItemStableId="native:cargo"} end}
        state.crewItems[2]=root
        state.saves,state.flushes,state.checkpointWrites=0,0,0
        SurvivorCompanion.Runtime={save=function()
            expect(cp.state=="walking","pickup checkpoint was published before its ordinary save returned verified identities")
            state.saves=state.saves+1
            if state.saveFailure then return false,"ordinary save failed" end
            return true,state.document
        end}
        ModData={get=function() return cp end,getOrCreate=function()
            state.checkpointWrites=state.checkpointWrites+1 return cp
        end}
        SCSplitScreenProbe.flushGlobalModDataForWorldExit=function() state.flushes=state.flushes+1 return true end
        return H,f,cp,state,world,primary,member
    end
    do
        local H,f,cp,state,world,primary,member=pickupFixture()
        local previousDrive=Probe._tests.setDriveForTests(state.drive)
        state:step(1000,100)
        local id=f.crew[1].id
        expect(H.phase=="home_trip_finish_wait" and state.saves==1 and state.flushes==1 and state.checkpointWrites==1
            and cp.state=="delivery" and cp.deliveryCarryWitness.members[id][1].nativeId==201
            and cp.deliveryCarryWitness.members[id][1].id=="native:cargo" and cp.drive.beforeCommit~=nil
            and primary.teleports==0 and member.teleports==0 and world.recoveries==0 and world.stays==0 and state.forbidden==0,
            "actual pickup phase must save and flush exact carried native roots before publishing a truthful delivery checkpoint")
        H.config.home_trip_mode,H.phase,H.phaseStartedAt="resume_delivery","home_trip_setup",2000
        state:step(2000,0)
        expect(H.phase=="home_trip_restored" and H.homeTripAcceptance.crew[1].actor==member
            and cp.state=="delivery" and state.saves==1 and state.checkpointWrites==1 and state.forbidden==0,
            "a delivery checkpoint must resume through strict saved personal native IDs without rewriting its state")
        state.document.companions[id].inventory.preserveNativeIds=nil
        H.phase,H.phaseStartedAt="home_trip_setup",3000 state:step(3000,0)
        expect(H.phase=="home_trip_finish_wait" and cp.state=="delivery" and state.saves==1 and state.checkpointWrites==1,
            "an explicit carried-root checkpoint must never fall back to the legacy ordinary-inventory diagnostic skip")
        Probe._tests.setDriveForTests(previousDrive)
        for _,holder in ipairs({"trunk","storage","other_car"}) do
            H,f,cp,state,world,primary,member=pickupFixture() state.holder=holder
            previousDrive=Probe._tests.setDriveForTests(state.drive)
            expect(Probe.saveDeliveryPickup(H,f,1000,state.check,function() end,function() end)==false
                and cp.state=="walking" and state.saves==0 and state.checkpointWrites==0,
                "only an original root held by exact crew can trigger pickup checkpoint: "..holder)
            Probe._tests.setDriveForTests(previousDrive)
        end
        H,f,cp,state,world,primary,member=pickupFixture() state.carrier="unrelated-companion"
        previousDrive=Probe._tests.setDriveForTests(state.drive)
        expect(Probe.saveDeliveryPickup(H,f,1000,state.check,function() end,function() end)==false and state.saves==0,
            "an unrelated registered carrier must not satisfy the exact trip-crew pickup witness")
        Probe._tests.setDriveForTests(previousDrive)
        local bad={no_native_marker=function(f,s) s.document.companions[f.crew[1].id].inventory.preserveNativeIds=nil end,
            changed_native_id=function(f,s) s.document.companions[f.crew[1].id].inventory.roots[2].nativeId=202 end,
            changed_stable_id=function(f,s) s.document.companions[f.crew[1].id].inventory.roots[2].modData.LF_ItemStableId="changed" end,
            save_failed=function(f,s) s.saveFailure=true end,
            duplicate_native=function(f,s) s.auditFailure="duplicate_live_cargo_native_id:201" end,
            active_view=function(f,s) s.view="expedition" end,
            moving_car=function(f,s) s.speed=1 end}
        for label,mutate in pairs(bad) do
            H,f,cp,state,world,primary,member=pickupFixture() mutate(f,state)
            previousDrive=Probe._tests.setDriveForTests(state.drive) state:step(1000,100)
            expect(H.phase=="home_trip_finish_wait" and cp.state=="walking" and cp.deliveryCarryWitness==nil
                and state.checkpointWrites==0 and state.flushes==0 and primary.teleports==0 and member.teleports==0
                and world.recoveries==0 and world.stays==0 and state.forbidden==0,
                "failed pickup save must never publish delivery state or bypass native ownership/identity: "..label)
            Probe._tests.setDriveForTests(previousDrive)
        end
    end
    local validate=assert(Probe._tests.resumeDelivery,"delivery replay validator missing")
    local H,f,cp,state,world,primary,member=fixture()
    local okay,proof=validate(H,f,cp)
    expect(okay and proof.tripId=="trip:delivery" and cp.state=="walking" and not cp.drive.beforeCommit and state.forbidden==0,
        "strict delivery replay rejected its saved pending trip or invented a precommit capture")
    state.outside=true
    expect(validate(H,f,cp)==true,"a healthy exact worker inside existing camp work reach was rejected")
    f.deliveryTripId="trip:delivery"
    state.pending,state.stored,state.complete=0,1,true state.integration.items[1].stored=true
    local auditDrive=Probe._tests.setDriveForTests(state.drive)
    expect(Probe._tests.deliveryReplayFinal(H,f)==nil,"stored receipts alone must not prove physical permitted storage")
    state.auditFailure="duplicate_live_cargo_native_id:201"
    expect(Probe._tests.deliveryReplayFinal(H,f)==false,"duplicate native cargo must fail diagnostic completion")
    state.auditFailure=nil state.holder="storage"
    expect(Probe._tests.deliveryReplayFinal(H,f)==true,"exact stored cargo and verified receipts should complete diagnostic delivery")
    state.integration.items[1].stored=false
    expect(Probe._tests.deliveryReplayFinal(H,f)==false,"unverified individual receipt must fail diagnostic completion")
    Probe._tests.setDriveForTests(auditDrive)
    local invalid={checkpoint=function(H,f,cp) cp.state="dormant" end,no_drive=function(H,f,cp) cp.drive=nil end,
        wrong_sql=function(H,f) f.drive.sqlId=50 end,camp=function(H,f,cp,s) s.campChanged=true end,
        unloaded=function(H,f,cp,s) s.unloaded=true end,primary_id=function(H,f,cp,s) s.primaryId=2 end,
        active_home=function(H,f,cp,s) s.active={} end,expedition=function(H,f,cp,s) s.expedition={} end,
        watch=function(H,f,cp,s) s.watch={} end,view=function(H,f,cp,s) s.view="expedition" end,
        secondary=function(H,f,cp,s) s.secondary=actor(0,0) end,unreleased=function(H,f,cp,s) s.unreleased=true end,
        wrong_trip=function(H,f,cp,s) s.document.expedition.debrief.integration.tripId="another-trip" end,
        no_pending=function(H,f,cp,s) s.document.expedition.deliveries={} end,
        cargo=function(H,f,cp,s) s.integration.items[1].nativeId=999 end,receipt=function(H,f,cp,s) s.report.carSaveReceipt.valid=false end,
        wrong_loaded_car=function(H,f,cp,s) s.carId=50 end,car_moved=function(H,f,cp,s) s.car.x=20 end,
        engine=function(H,f,cp,s) s.engine=true end,speed=function(H,f,cp,s) s.speed=1 end,
        complete=function(H,f,cp,s) s.pending=0 end,crew=function(H,f,cp,s) s.integration.members[1].id="another-crew" end,
        unhealthy=function(H,f,cp,s) s.unhealthy=true end,inactive=function(H,f,cp,s) s.inactive=true end,
        outside_reach=function(H,f,cp,s) s.outside,s.outsideReach=true,true end,
        native_duplicate=function(H,f,cp,s) s.nativeActors[2]=s.nativeActors[1] end,
        inventory_absent=function(H,f,cp,s) s.document.companions[f.crew[1].id].inventory=nil end,
        inventory_incomplete=function(H,f,cp,s) s.document.companions[f.crew[1].id].inventory.complete=false end,
        inventory_count=function(H,f,cp,s) s.document.companions[f.crew[1].id].inventory.count=2 end,
        inventory_node=function(H,f,cp,s) s.document.companions[f.crew[1].id].inventory.roots[1].type=false end,
        inventory_native_proof=function(H,f,cp,s) s.document.companions[f.crew[1].id].inventory.roots[1].nativeId=nil end,
        saved_record=function(H,f,cp,s) s.document.companions[f.crew[1].id].id="another-actor" end,
        saved_vitals=function(H,f,cp,s) s.document.companions[f.crew[1].id].vitals.health=nil end}
    for label,mutate in pairs(invalid) do
        H,f,cp,state,world,primary,member=fixture() mutate(H,f,cp,state)
        expect(validate(H,f,cp)==false and primary.teleports==0 and member.teleports==0 and world.recoveries==0 and world.stays==0 and state.forbidden==0,
            "delivery replay must reject altered context without repairing it: "..label)
    end
    H,f,cp,state,world,primary,member=fixture()
    primary.invisible,primary.ghost=true,true state.auditPending=true
    local previousDrive=Probe._tests.setDriveForTests(state.drive)
    state:step(0,0)
    f=H.homeTripAcceptance
    expect(H.phase=="home_trip_restored" and f.crew[1].actor==member and f.restored[f.crew[1].id]
        and primary.invisible and primary.ghost and cp.state=="walking" and cp.arrival==nil and cp.drive.beforeCommit==nil
        and not f.originalCommit and not f.routeObserver and state.forbidden==0,
        "actual delivery replay setup lost current observer flags or changed checkpoint/setup/precommit ownership")
    state:step(3000,60)
    expect(H.phase=="home_trip_restored","delivery replay skipped its bounded initial native cargo audit")
    state.auditPending=false state:step(3500,62)
    expect(H.phase=="home_trip_duty","delivery replay did not enter ordinary physical duty monitoring after current-ID proof")
    state:step(4000,64) state:step(5000,66)
    expect(H.phase=="home_trip_duty","delivery replay treated pending receipts as completed delivery")
    state.pending,state.stored,state.complete,state.holder=0,1,true,"storage"
    state.integration.items[1].stored=true
    state:step(5500,68)
    local passed=false
    for _,event in ipairs(state.events) do
        if event.label=="home_trip_reload_delivery_complete" and event.status=="PASS" then passed=true end
        expect(event.status~="FAIL","delivery replay positive actual phases failed: "..tostring(event.label)..":"..tostring(event.detail))
    end
    expect(passed and H.phase=="home_trip_finish_wait" and cp.state=="walking" and not cp.drive.beforeCommit
        and primary.teleports==0 and member.teleports==0 and world.recoveries==0 and world.stays==0 and state.forbidden==0,
        "diagnostic delivery completion altered actors/checkpoint or claimed ordinary full-trip proof")
    Probe._tests.setDriveForTests(previousDrive)
    H,f,cp,state,world,primary,member=fixture()
    primary.invisible,primary.ghost=true,true state.carMissing=true
    previousDrive=Probe._tests.setDriveForTests(state.drive)
    state:step(0,0)
    expect(H.phase=="home_trip_delivery_resume_wait" and state.carReads==1,
        "an initially unloaded car must enter the bounded natural-load wait")
    state.carMissing=false state:step(999,1)
    expect(H.phase=="home_trip_delivery_resume_wait" and state.carReads==1,"delivery warmup retried before its one-second cadence")
    state:step(1000,2)
    expect(H.phase=="home_trip_restored" and state.carReads==2 and primary.invisible and primary.ghost
        and cp.state=="walking" and primary.teleports==0 and member.teleports==0 and state.forbidden==0,
        "natural car load did not resume strict validation without observer/world changes")
    Probe._tests.setDriveForTests(previousDrive)
    H,f,cp,state,world,primary,member=fixture()
    state.crewMissing,state.restorePending=true,true
    previousDrive=Probe._tests.setDriveForTests(state.drive) state:step(0,0)
    expect(H.phase=="home_trip_delivery_resume_wait","missing restored crew must receive the same bounded warmup")
    state.crewMissing=false state:step(1000,2)
    expect(H.phase=="home_trip_delivery_resume_wait","genuinely pending restore was mistaken for a healthy ready crew")
    state.restorePending=false state:step(2000,4)
    expect(H.phase=="home_trip_restored" and primary.teleports==0 and member.teleports==0 and state.forbidden==0,
        "naturally committed exact crew failed delivery warmup or required a repair")
    Probe._tests.setDriveForTests(previousDrive)
    H,f,cp,state,world,primary,member=fixture()
    state.carMissing=true
    previousDrive=Probe._tests.setDriveForTests(state.drive) state:step(0,0)
    for at=1000,19000,1000 do state:step(at,at/500) end
    expect(H.phase=="home_trip_delivery_resume_wait","delivery warmup failed before its bounded20-second deadline")
    state:step(20000,40)
    local deadline=false
    for _,event in ipairs(state.events) do if event.status=="FAIL" and event.label=="home_trip_delivery_replay_load_deadline" then
        deadline=event.detail:find("delivery_car_not_loaded",1,true)~=nil
    end end
    expect(deadline and H.phase=="home_trip_finish_wait" and cp.state=="walking" and primary.teleports==0
        and member.teleports==0 and state.forbidden==0,"a car that never loads must fail at20 seconds without manufacturing state")
    Probe._tests.setDriveForTests(previousDrive)
    H,f,cp,state,world,primary,member=fixture()
    state.carId=50
    previousDrive=Probe._tests.setDriveForTests(state.drive) state:step(0,0)
    local mismatch=false
    for _,event in ipairs(state.events) do if event.status=="FAIL" and event.label=="home_trip_delivery_replay_context" then
        mismatch=event.detail:find("saved_car_sql_mismatch:expected=49;actual=50",1,true)~=nil
    end end
    expect(mismatch and H.phase=="home_trip_finish_wait" and not H.homeTripAcceptance.deliveryResumeStartedAt,
        "a real wrong loaded car must fail immediately rather than enter a warmup retry")
    Probe._tests.setDriveForTests(previousDrive)
    H,f,cp,state,world,primary,member=fixture()
    local personal=state.document.companions[f.crew[1].id].inventory
    personal.preserveNativeIds,personal.roots[1].nativeId=nil,nil
    state.item.id=999
    previousDrive=Probe._tests.setDriveForTests(state.drive) state:step(0,0)
    local skipped=false
    for _,event in ipairs(state.events) do
        if event.status=="SKIP" and event.label:find("home_trip_delivery_reload_personal_native_ids_unavailable_",1,true) then
            skipped=event.detail:find("exact native-ID save marker missing",1,true)~=nil
        end
        expect(event.status~="FAIL","ordinary validated personal save failed diagnostic replay: "..tostring(event.detail))
    end
    f=H.homeTripAcceptance
    expect(skipped and H.phase=="home_trip_restored" and f.crew[1].actor==member and f.deliveryExpected[f.crew[1].id].items==nil
        and personal.preserveNativeIds==nil and personal.roots[1].nativeId==nil and state.item.id==999
        and f.drive.cargo[1].nativeId==201 and cp.state=="walking" and not cp.drive.beforeCommit
        and primary.teleports==0 and member.teleports==0 and state.forbidden==0,
        "ordinary personal save must explicitly skip only historical native IDs without inventing a baseline or weakening original cargo")
    Probe._tests.setDriveForTests(previousDrive)
    H,f,cp,state,world,primary,member=fixture()
    state.item.id=999
    previousDrive=Probe._tests.setDriveForTests(state.drive) state:step(0,0)
    expect(H.phase=="home_trip_finish_wait" and cp.state=="walking" and primary.teleports==0 and member.teleports==0,
        "actual replay setup accepted a crew native inventory differing from its saved document")
    Probe._tests.setDriveForTests(previousDrive)
    ArrayList=oldArrayList
end

-- A nickname can legitimately change while walking. Restoration must match
-- the durable arrival name while keeping the stable companion ID unchanged.
do
    local H,f,world,target,primary,member=context(0,200)
    local observe=assert(Probe._tests.observeRestored,"home restoration observation seam missing")
    local id=f.crew[1].id
    local vitals={health=1,overallHealth=100,infected=false,parts={}}
    local body={getOverallBodyHealth=function() return 100 end,getNumPartsBleeding=function() return 0 end}
    function member:getInventory() return {getItems=function() return {size=function() return 0 end} end} end
    function member:getBodyDamage() return body end
    function member:isDead() return false end
    function member:isBridgeHealthy() return true end
    function member:getVehicle() return nil end
    member.displayName="Home 'Crash' Tester"
    SurvivorCompanion.Names={displayName=function(value) return value.displayName end}
    SurvivorCompanion.Vitals={capture=function() return vitals end}
    SurvivorCompanion.Registry.idOf=function(value) return value==member and id or nil end
    SurvivorCompanion.Registry.isActive=function(value,wanted) return value==member and wanted==id end
    SurvivorCompanion.Commands.peek=function() return {order="base_duty"} end
    SurvivorCompanion.ExpeditionPrototype={integrationFor=function() return nil end}
    SurvivorCompanion.BaseLife={isInside=function() return true end}
    f.arrival={[id]={items={},vitals=vitals,name=member.displayName}}
    local failed={}
    local function check(label,value) if not value then failed[#failed+1]=label end return value==true end
    expect(observe(f,check)==true and #failed==0,
        "a legitimate departure-to-arrival nickname change failed restored identity")
    f.restored={}
    member.displayName="Wrong Restored Name"
    expect(observe(f,check)==true and #failed==1 and failed[1]=="home_trip_restored_name_"..id,
        "a restored name differing from its durable arrival snapshot was accepted")
end

-- A resumed final approach proves only newly observed movement. Saved
-- departure displacement remains diagnostic and cannot inflate this segment.
do
    local validate=assert(Probe._tests.checkPhysicalTravel,"home physical observation seam missing")
    local events={}
    local function result(status,label,detail) events[#events+1]={status=status,label=label,detail=detail} end
    local function check(label,value,detail) result(value and "PASS" or "FAIL",label,detail) return value==true end
    local function run(f)
        events={}
        local okay=validate(f,check,result)
        return okay,events[1]
    end
    local f={mode="resume_active",travelled=0,samples=0,sawSecondView=true,arrival={},resumeDisplacement=178}
    local okay,event=run(f)
    expect(okay and event.status=="SKIP" and event.label=="home_trip_physical_resume_segment" and f.travelled==0,
        "saved pre-quit displacement was counted as a newly observed physical segment")
    f.travelled=.5
    okay,event=run(f)
    expect(okay and event.status=="SKIP","exactly half a metre claimed final-approach movement proof")
    f.travelled=.5001 f.samples=1
    okay,event=run(f)
    expect(okay and event.status=="PASS" and event.label=="home_trip_physical_resume_segment",
        "a real post-reload segment was mislabeled as a full home walk")
    for _,missing in ipairs({"sawSecondView","arrival"}) do
        local original=f[missing] f[missing]=nil
        okay,event=run(f)
        expect(not okay and event.status=="FAIL","resumed movement passed without "..missing)
        f[missing]=original
    end
    f.continuityFailed=true
    okay,event=run(f)
    expect(not okay and event.status=="FAIL","resumed movement passed after a position jump")
    f.continuityFailed=nil
    for _,mode in ipairs({"walk","resume_midtrip","resume_midtrip_save_dormant"}) do
        f.mode=mode f.travelled=19.99
        okay,event=run(f)
        expect(not okay and event.label=="home_trip_physical_home_walk",mode.." lost its twenty-metre minimum")
        f.travelled=20
        okay,event=run(f)
        expect(okay and event.status=="PASS" and event.label=="home_trip_physical_home_walk",mode.." twenty-metre walk did not pass")
    end
end

-- Exercise the combined mode at its actual dormant boundary. No checkpoint
-- or flush may occur before the unchanged newly sampled movement proof passes.
do
    local function dormantCase(travelled)
        local H,f,world,target,primary=context(200,200)
        local id=f.crew[1].id
        local document={companions={[id]={restorePrimaryOnly=true,inventory={preserveNativeIds=true,roots={}}}}}
        local checkpoint,operations,failed={},{},{}
        H.phase,H.phaseStartedAt="home_trip_dormant",0
        f.mode,f.travelled,f.samples,f.sawSecondView="resume_midtrip_save_dormant",travelled,10,true
        f.camp={core={x=0,y=0,z=0}} f.departure={x=200,y=0,z=0}
        f.arrival={[id]={items={}}}
        f.walls={{x=1,y=2,bit=1,hidden=false}} f.cars={{sqlId=9,position={x=3,y=4,z=0}}}
        SurvivorCompanion.HomeTrip={current=function() return nil end}
        SurvivorCompanion.Registry.byId=function() return nil end
        SurvivorCompanion.Persistence.isPending=function() return true end
        SurvivorCompanion.Persistence.lastDocument=function() return document end
        SurvivorCompanion.Runtime={save=function()
            operations[#operations+1]="save"
            expect(checkpoint.state=="dormant","combined resume saved LF state before setting its dormant checkpoint")
            return true,document
        end}
        function world:getObjectList() return {size=function() return 0 end} end
        ArrayList={new=function(value) return value end}
        IsoPlayer={getInstance=function() return primary end}
        getSpecificPlayer=function(index) if index==0 then return primary end end
        SCSplitScreenProbe.isReleased=function() return true end
        SCSplitScreenProbe.primaryAreaContains=function() return false end
        SCSplitScreenProbe.flushGlobalModDataForWorldExit=function() operations[#operations+1]="flush" return true end
        ModData={getOrCreate=function() return checkpoint end}
        getCore=function() return {TakeFullScreenshot=function() end} end
        Probe._tests.protectObserver(f)
        local function result(status,label) if status=="FAIL" then failed[#failed+1]=label end end
        local function check(label,value) result(value and "PASS" or "FAIL",label) return value==true end
        local function phase(value,at) H.phase,H.phaseStartedAt=value,at end
        Probe.step(H,2500,check,result,phase)
        return H,f,checkpoint,operations,failed
    end
    local H,f,checkpoint,operations,failed=dormantCase(19.99)
    expect(#operations==0 and #failed==1 and failed[1]=="home_trip_physical_home_walk",
        "combined resume saved dormant state after insufficient newly observed movement")
    H,f,checkpoint,operations,failed=dormantCase(20)
    expect(#failed==0 and #operations==2 and operations[1]=="save" and operations[2]=="flush"
        and H.phase=="home_trip_finish_wait" and f.primary.teleports==0,
        "combined resume did not save/flush/quit before any primary revisit")
    expect(checkpoint.state=="dormant" and checkpoint.crew[1].id==f.crew[1].id and checkpoint.arrival~=f.arrival,
        "combined resume did not preserve the same crew and fresh arrival in the dormant checkpoint")
    expect(checkpoint.observerOriginalInvisible==false and checkpoint.observerOriginalGhost==false
        and f.primary.invisible==false and f.primary.ghost==false,
        "dormant save lost the original flag bucket or finish left its temporary observer invisible")
    expect(checkpoint.walls~=f.walls and checkpoint.walls[1].hidden==false
        and checkpoint.cars~=f.cars and checkpoint.cars[1].position.x==3,
        "combined resume lost primitive wall/car witnesses while checkpointing")
end

-- Let the normal UI refresh/render catch up with the last real duty command.
-- Loss of duty resets the wait; an honest pending deadline still stays pending.
do
    local function dutyFixture(crewCount)
        local H,f,world,target,primary,member=context(0,200)
        local state={order="base_duty",shots={},events={},checkpoint={},visible=true,zoom=1,zoomCalls=0,commands={},jobs={}}
        state.world,state.member,state.cars=world,member,{actor(8,2),actor(10,2)}
        state.members={member}
        local records={[f.crew[1].id]=SurvivorCompanion.Registry.byId(f.crew[1].id)}
        for index=2,crewCount or 1 do
            local companion=actor(2+index*3,4)
            local id="sc-home-test-"..index
            f.crew[index]={id=id,actor=companion,name="Home Tester "..index}
            records[id]={id=id,actor=companion,recruited=true}
            state.members[index]=companion
        end
        state.records=records
        f.camp={id="home-test-camp"}
        state.base={id=f.camp.id}
        state.residents={}
        for _,entry in ipairs(f.crew) do
            state.residents[entry.id]={baseId=f.camp.id,duty=true}
            local companion=entry.actor
            function companion:isBridgeHealthy() return not self.damaged end
            function companion:getBodyDamage() return {
                getOverallBodyHealth=function() return companion.damaged and 80 or 100 end,
                getNumPartsBleeding=function() return 0 end,
            } end
        end
        state.minimapVisible,state.minimapRemoved,state.savedMinimapVisible=true,0,true
        H.phase,H.phaseStartedAt="home_trip_duty",0
        f.dutyReported={}
        f.cars={{sqlId=9,position={x=8,y=2,z=0}},{sqlId=10,position={x=10,y=2,z=0}}}
        SurvivorCompanion.HomeTrip={current=function() return state.active end,
            campUnchanged=function(camp) return camp==f.camp and not state.campChanged end}
        SurvivorCompanion.Registry.byId=function(id) if not state.dormant then return records[id] end end
        SurvivorCompanion.Registry.isActive=function(value,id) return not state.dormant and value~=state.inactiveActor and records[id] and records[id].actor==value end
        SurvivorCompanion.Commands.peek=function(value) return state.commands[value] or {order=state.order} end
        SurvivorCompanion.GameplayUtil.nowMs=function() return state.now or 0 end
        SurvivorCompanion.ViewSession={owner=function() return nil end}
        SurvivorCompanion.GameplayUtil.isSquareFree=function(square)
            for _,car in ipairs(state.cars) do if square.x==car.x and square.y==car.y then return false end end
            return true
        end
        for _,car in ipairs(state.cars) do
            function car:isEngineRunning() return false end
            function car:getCurrentSpeedKmHour() return 0 end
        end
        SurvivorCompanion.Vehicle={loadedBySqlId=function(id) return state.cars[id-8] end}
        IsoPlayer={getInstance=function() return primary end}
        getSpecificPlayer=function(index) if index==0 then return primary end end
        SCSplitScreenProbe.isReleased=function() return true end
        SCSplitScreenProbe.primaryAreaContains=function() return not state.primaryDenied end
        SurvivorCompanion.BaseLife={active=function() return state.base end,
            snapshotResident=function(id)
                local row=state.residents[id]
                if not row then return {present=false} end
                return {present=true,value={baseId=row.baseId,duty=row.duty}}
            end,
            isInside=function(value) return value~=state.outsideActor end,
            job=function(id) return state.jobs[id] end,
            barricadeJobCurrent=function(id,actorId,objectId)
                local job=state.jobs[id]
                state.barricadeReads=(state.barricadeReads or 0)+1
                return state.barricadeCurrent~=false and job and job.reservedBy==actorId and job.target.objectId==objectId
            end,
            jobFor=function() error("duty evidence must not claim or renew a job") end,
            resident=function() error("duty evidence must not initialize a resident") end}
        SurvivorCompanion.ExpeditionPrototype.integrationFor=function(value)
            if value~=state.noObligationActor then return {kind="home"} end
        end
        SurvivorCompanion.ExpeditionIntegration={summary=function()
            return {members={{id=f.crew[1].id,cleanupDone=false,dutyDone=false}}}
        end}
        SurvivorCompanion.UI={instance={settings={collapsed=false},
            setVisible=function(_,value) state.visible=value end,isVisible=function() return state.visible end}}
        getPlayerMiniMap=function(index)
            expect(index==0,"photo accessed a secondary minimap")
            return {removeFromUIManager=function() state.minimapRemoved=state.minimapRemoved+1 state.minimapVisible=false end,
                isReallyVisible=function() return state.minimapVisible end}
        end
        WorldMapSettings={getInstance=function() error("photo changed persistent minimap settings") end}
        getCore=function() return {
            TakeFullScreenshot=function(_,filename) state.shots[#state.shots+1]=filename end,
            getZoom=function(_,playerIndex) expect(playerIndex==0,"scene read a secondary zoom") return state.zoom end,
            doZoomScroll=function(_,playerIndex,direction)
                expect(playerIndex==0 and direction==1,"scene used an unapproved zoom API or direction")
                state.zoomCalls=state.zoomCalls+1 state.zoom=state.zoom+.25
                expect(state.zoom<=1.5,"scene zoom exceeded the requested depth")
            end,
        } end
        ModData={getOrCreate=function() return state.checkpoint end}
        local function result(status,label,detail) state.events[#state.events+1]={status=status,label=label,detail=detail} end
        local function check(label,value) result(value and "PASS" or "FAIL",label) return value==true end
        local function phase(value,at) H.phase,H.phaseStartedAt=value,at end
        function state:step(at,frames)
            self.now=at
            f.frames=frames
            Probe.step(H,at,check,result,phase)
        end
        return state,H,f
    end
    for _,case in ipairs({{expected=180000},{value=0,expected=180000},{value=-1,expected=180000},
        {value=999,expected=180000},{value="invalid",expected=180000},{value=math.huge,expected=180000},
        {value=-math.huge,expected=180000},{value=1000,expected=1000},{value="600000",expected=600000},
        {value=999999999,expected=600000}}) do
        expect(Probe.dutyTimeoutMs({config={home_trip_duty_timeout_ms=case.value}})==case.expected,
            "duty timeout must stay positive, finite and at most600 seconds")
    end
    local state,H,f=dutyFixture()
    H.config.home_trip_duty_timeout_ms=600000 state.order="follow" f.drive={cargo={}}
    state:step(180001,100) state:step(599999,102)
    expect(H.phase=="home_trip_duty" and #state.shots==0 and not f.dutyReadyAt,
        "explicit600-second duty override must permit bounded unfinished physical delivery beyond the default180 seconds")
    state:step(600000,104)
    local timedOut=false
    for _,event in ipairs(state.events) do if event.status=="FAIL" and event.label=="home_trip_drive_delivery_deadline" then timedOut=true end end
    expect(timedOut and H.phase=="home_trip_finish_wait" and f.primary.teleports==0 and state.member.teleports==0
        and state.world.recoveries==0 and state.world.stays==0,
        "unfinished delivery must fail at the explicit600-second bound without creating progress")
    state,H,f=dutyFixture()
    Probe._tests.protectObserver(f)
    state:step(1000,100)
    expect(not f.primary.invisible and not f.primary.ghost and not f.observerProtected,
        "main observer protection survived into the final duty/scene phases")
    expect(#state.shots==0 and f.dutyReadyAt==1000,"last duty command queued its screenshot in the same tick")
    state:step(1999,101)
    expect(#state.shots==0,"duty screenshot did not receive the full one-second UI settling interval")
    state:step(2000,101)
    expect(#state.shots==0,"duty screenshot was taken after only one rendered frame")
    state:step(2000,102)
    expect(#state.shots==1 and string.find(state.shots[1],"base-duty",1,true) and state.visible and state.zoomCalls==0
        and H.phase=="home_trip_scene_ui_wait","settled duty failed to preserve its UI screenshot before hiding")
    state:step(2499,103)
    expect(state.visible and state.zoomCalls==0,"scene hid the duty UI before its full screenshot interval")
    state:step(2500,103)
    expect(state.visible and state.zoomCalls==0,"scene hid the duty UI after only one rendered frame")
    state:step(2500,104)
    expect(not state.visible and SurvivorCompanion.UI.instance.settings.collapsed==false and state.zoomCalls==2
        and state.minimapRemoved==1 and not state.minimapVisible and state.savedMinimapVisible
        and H.phase=="home_trip_scene_wait","scene did not hide existing UI/minimap without saved settings and use bounded vanilla zoom")
    state:step(2999,105)
    expect(#state.shots==1,"solo scene screenshot skipped its 500ms settling interval")
    state:step(3000,105)
    expect(#state.shots==1,"solo scene screenshot skipped its two-render-frame boundary")
    state:step(3000,106)
    expect(#state.shots==2 and string.find(state.shots[2],"solo-scene",1,true)
        and H.phase=="home_trip_photo_next" and f.primary.teleports==0,"original-pose solo scene moved its observer before capture")
    state:step(3499,107) state:step(3500,107)
    expect(f.primary.teleports==0,"observer photo moved before the original scene PNG settled")
    state:step(3500,108)
    expect(f.primary.teleports==1 and H.phase=="home_trip_photo_wait","existing car witness did not receive main-only camera setup")
    f.primary:applyQueued()
    state:step(3999,109) state:step(4000,109)
    expect(#state.shots==2,"car photo skipped its time or rendered-frame wait")
    state:step(4000,110)
    expect(#state.shots==3 and string.find(state.shots[3],"car-scene",1,true),"settled existing car witness was not photographed")
    state:step(4500,112) f.primary:applyQueued() state:step(5000,114)
    expect(#state.shots==4 and string.find(state.shots[4],"car-scene-2",1,true),"second existing car witness was not photographed")
    state:step(5500,116) f.primary:applyQueued() state:step(6000,118)
    expect(#state.shots==5 and string.find(state.shots[5],"name-scene",1,true),"actual returned companion was not photographed")
    state:step(6500,120)
    expect(state.checkpoint.state=="complete" and H.phase=="home_trip_finish_wait" and f.primary.teleports==3
        and state.member.teleports==0 and state.world.recoveries==0 and state.world.stays==0
        and state.cars[1].teleports==0 and state.cars[2].teleports==0,"postproof photos moved crew/cars or failed to finish")
    for _,crewCount in ipairs({3,5}) do
        state,H,f=dutyFixture(crewCount)
        state:step(1000,100) state:step(2000,102) state:step(2500,104) state:step(3000,106)
        local names,seen={},{}
        for _,job in ipairs(f.photoJobs or {}) do
            if job.kind=="name" then
                names[#names+1]=job
                expect(not seen[job.id],"returned crew member received duplicate name photo jobs")
                seen[job.id]=true
            end
        end
        expect(#names==math.min(4,crewCount) and f.primary.teleports==0
            and #state.shots==2 and H.phase=="home_trip_photo_next",
            "actual postproof scene must queue one bounded name photo per returned crew member without moving the original camera")
        for index,job in ipairs(names) do
            expect(job.id==f.crew[index].id and job.label==(index==1 and "name-scene" or "name-scene-"..index),
                "returned crew photo jobs lost exact member order or compatible screenshot labels")
        end
        local at,frames=3500,108
        for _=1,#f.photoJobs do
            state:step(at,frames) f.primary:applyQueued() state:step(at+500,frames+2)
            at,frames=at+1000,frames+4
        end
        state:step(at,frames)
        expect(state.checkpoint.state=="complete" and #state.shots==2+#f.photoJobs
            and f.primary.teleports==#f.photoJobs and state.world.recoveries==0 and state.world.stays==0
            and state.cars[1].teleports==0 and state.cars[2].teleports==0,
            "each scheduled returned-crew photo must run once through the unchanged postproof main-only camera path")
        for _,companion in ipairs(state.members) do
            expect(companion.teleports==0,"returned-name photography moved a companion")
        end
    end
    do
        local function work(state,f,index)
            local member=f.crew[index or 1]
            local target={kind="barricade",baseJobId="job:returned-duty",objectId="door:camp",
                x=5,y=5,z=0,objectIndex=1,objectSignature="fixture-door",barricadeSide="same"}
            local job={id=target.baseJobId,type="barricade",state="active",reservedBy=member.id,leaseUntil=45000,
                target={objectId=target.objectId,x=5,y=5,z=0,objectIndex=1,objectSignature="fixture-door",barricadeSide="same"}}
            local command={order="work",returnOrder="base_duty",workMode="build",workTarget=target}
            state.commands[member.actor],state.jobs[job.id]=command,job
            return command,job
        end
        local function pendingCrew()
            local state,H,f=dutyFixture(2)
            state.commands[f.crew[2].actor]={order="follow"}
            state:step(1000,100)
            expect(f.dutyReported[f.crew[1].id]==true and f.dutyReported[f.crew[2].id]==nil
                and H.phase=="home_trip_duty","actual base duty must be observed before any normal-work continuation")
            return state,H,f
        end
        state,H,f=pendingCrew()
        local maintained,maintenanceJob=work(state,f)
        maintained.workTarget.barricadeSide,maintenanceJob.target.barricadeSide=nil,nil
        maintenanceJob.target.maintenanceId="maintenance:returned-door"
        state.noObligationActor=f.crew[1].actor
        state:step(1500,102)
        expect(H.phase=="home_trip_duty" and f.dutyReported[f.crew[1].id]
            and state.base.residents==nil and state.residents[f.crew[1].id].duty==true
            and (state.barricadeReads or 0)>0 and #state.shots==0,
            "verified automatic maintenance barricade work with no explicit side must preserve prior duty while another crew member is pending")
        state.commands[f.crew[2].actor]=nil
        state:step(2000,104) state:step(3000,106)
        expect(H.phase=="home_trip_scene_ui_wait" and #state.shots==1,
            "normal leased camp work must allow the actual settled-crew proof to finish")
        state:step(3500,108) state:step(4000,110) state:step(4500,112)
        expect(H.phase=="home_trip_photo_wait" and f.primary.teleports==1
            and state.members[1].teleports==0 and state.members[2].teleports==0,
            "postproof main-only photographs must accept the same verified normal camp work without moving crew")
        state,H,f=dutyFixture()
        work(state,f) state.noObligationActor=f.crew[1].actor state:step(1000,100)
        expect(H.phase=="home_trip_finish_wait" and not f.dutyReported[f.crew[1].id] and #state.shots==1,
            "returnOrder base_duty and a valid lease must never replace an initial actual base-duty observation")
        local mutations={
            follow=function(state,f,command) command.order="follow" end,
            stay=function(state,f,command) command.order="stay" end,
            arbitrary_work=function(state,f,command) command.workTarget.kind="chop" end,
            wrong_return=function(state,f,command) command.returnOrder="follow" end,
            wrong_mode=function(state,f,command) command.workMode="auto" end,
            missing_job=function(state) state.jobs={} end,
            wrong_owner=function(state,f,command,job) job.reservedBy=f.crew[2].id end,
            wrong_state=function(state,f,command,job) job.state="pending" end,
            expired_lease=function(state,f,command,job) job.leaseUntil=1500 end,
            nonfinite_lease=function(state,f,command,job) job.leaseUntil=math.huge end,
            wrong_target=function(state,f,command) command.workTarget.x=6 end,
            wrong_side=function(state,f,command) command.workTarget.barricadeSide="opposite" end,
            ended_maintenance=function(state) state.barricadeCurrent=false end,
            resident_off=function(state,f) state.residents[f.crew[1].id].duty=false end,
            resident_missing=function(state,f) state.residents[f.crew[1].id]=nil end,
            resident_other_base=function(state,f) state.residents[f.crew[1].id].baseId="another-camp" end,
            camp_changed=function(state) state.campChanged=true end,
            other_camp=function(state) state.base.id="different-camp" end,
            outside=function(state,f) state.outsideActor=f.crew[1].actor end,
            actor_changed=function(state,f,command)
                local replacement=actor(2,2)
                replacement.isBridgeHealthy=f.crew[1].actor.isBridgeHealthy
                replacement.getBodyDamage=f.crew[1].actor.getBodyDamage
                state.commands[replacement]=command
                expect(Probe._tests.healthy(replacement),"actor-replacement control must isolate identity from health")
                state.records[f.crew[1].id].actor=replacement state.noObligationActor=replacement
            end,
            inactive=function(state,f) state.inactiveActor=f.crew[1].actor end,
            unhealthy=function(state,f) f.crew[1].actor.damaged=true end,
        }
        for label,mutate in pairs(mutations) do
            state,H,f=pendingCrew()
            local command,job=work(state,f)
            state.noObligationActor=f.crew[1].actor
            mutate(state,f,command,job) state:step(1500,102)
            local failure
            for _,event in ipairs(state.events) do if event.status=="FAIL" and event.label=="home_trip_handover_obligation_lost" then failure=event end end
            expect(failure and H.phase=="home_trip_finish_wait" and not f.dutyReported[f.crew[1].id]
                and #state.shots==1 and string.find(state.shots[1],"failed-home_trip_handover_obligation_lost",1,true)
                and f.primary.teleports==0 and state.world.recoveries==0 and state.world.stays==0,
                "invalid normal-work continuation must clear prior duty and fail without inventing proof: "..label)
            expect(failure.detail and failure.detail:find("returnOrder=",1,true) and failure.detail:find("workMode=",1,true)
                and failure.detail:find("baseJobId=",1,true) and failure.detail:find("residentDuty=",1,true),
                "unsupported normal-work failure must retain exact command/resident diagnostics: "..label)
        end
        state,H,f=pendingCrew()
        state.commands[f.crew[1].actor]={order="follow"} state:step(1500,102)
        work(state,f) state:step(2000,104)
        expect(H.phase=="home_trip_duty" and not f.dutyReported[f.crew[1].id] and #state.shots==0,
            "a queued home obligation must not let later work reuse duty proof invalidated by a manual order")
        state.commands[f.crew[1].actor]=nil state:step(2500,106)
        expect(f.dutyReported[f.crew[1].id]==true,"fresh actual base duty can restore proof after an invalid continuation")
    end
    state,H,f=dutyFixture()
    state:step(1000,100)
    state.order="follow" state:step(1500,101)
    expect(f.dutyReadyAt==nil and #state.shots==0,"a lost duty state retained its successful screenshot timer")
    state.order="base_duty" state:step(2000,102) state:step(2500,104)
    expect(#state.shots==0,"restored duty reused an earlier partial settling interval")
    state:step(3000,105)
    expect(#state.shots==1 and H.phase=="home_trip_scene_ui_wait" and state.visible,
        "stable duty did not start its UI screenshot interval after freshly settling")
    do
        local setDrive=assert(Probe._tests.setDriveForTests,"drive audit fixture seam missing")
        local priorDrive=setDrive(nil)
        local function slicedAudit(s,fixture)
            fixture.drive={sqlId=111,variant="roadside"}
            s.auditCalls,s.auditStarts,s.auditPasses=0,0,0
            setDrive({checkFinal=function(_,currentFixture,_,_,result)
                expect(currentFixture==fixture,"duty audited a different trip")
                s.auditCalls=s.auditCalls+1
                fixture._homeDrive=fixture._homeDrive or {}
                local job=fixture._homeDrive.finalAudit
                if not job then
                    job={cursor=0} fixture._homeDrive.finalAudit=job
                    s.auditStarts=s.auditStarts+1
                end
                job.cursor=job.cursor+1
                if job.cursor<3 then return nil,"bounded_native_cargo_audit_pending" end
                -- Match the real audit: completion drops its job, so a later
                -- call would begin another multi-tick audit from scratch.
                fixture._homeDrive.finalAudit=nil
                if s.missingCargo then return false,"missing_exact_native_cargo_id" end
                s.auditPasses=s.auditPasses+1
                result("PASS","home_drive_physical_cargo_final","complete exact-ID audit")
                return true
            end})
        end
        state,H,f=dutyFixture() slicedAudit(state,f)
        state:step(1000,100) state:step(1999,102)
        expect(state.auditCalls==0 and f.dutyReadyAt==1000,
            "drive cargo audit began before the actual crew settled for one second")
        state:step(2000,102)
        expect(state.auditCalls==1 and state.auditStarts==1 and f.dutyReadyAt==1000
            and #state.shots==0 and H.phase=="home_trip_duty",
            "a pending cargo slice reset the stable-crew clock or claimed a duty screenshot")
        state:step(2033,103) state:step(2066,104)
        expect(state.auditCalls==3 and state.auditStarts==1 and state.auditPasses==1
            and #state.shots==1 and string.find(state.shots[1],"base-duty",1,true)
            and H.phase=="home_trip_scene_ui_wait" and f.dutyProofGranted,
            "a completed multi-tick cargo audit restarted instead of advancing once to photographs")
        state:step(2100,105)
        expect(state.auditCalls==3 and state.auditPasses==1 and #state.shots==1,
            "the completed final audit ran again after the photo phase began")

        state,H,f=dutyFixture() slicedAudit(state,f)
        state:step(1000,100) state:step(2000,102)
        local interrupted=f._homeDrive.finalAudit
        state.order="follow" state:step(2033,103)
        expect(f.dutyReadyAt==nil and f._homeDrive.finalAudit==nil and state.auditCalls==1
            and #state.shots==0,"an actual crew-state break retained its settled clock or partial cargo audit")
        state.order="base_duty" state:step(3000,104) state:step(3999,106)
        expect(state.auditCalls==1 and f.dutyReadyAt==3000,
            "the crew reused its pre-break stability interval")
        state:step(4000,106)
        expect(state.auditStarts==2 and f._homeDrive.finalAudit~=interrupted,
            "the newly settled crew reused an interrupted exact-ID audit")
        state:step(4033,107) state:step(4066,108)
        expect(state.auditCalls==4 and state.auditPasses==1 and #state.shots==1
            and H.phase=="home_trip_scene_ui_wait",
            "a real crew break did not require a fresh stable interval and complete cargo audit")

        state,H,f=dutyFixture() slicedAudit(state,f) state.missingCargo=true
        state:step(1000,100) state:step(2000,102) state:step(2033,103) state:step(2066,104)
        local missingFailed=false
        for _,event in ipairs(state.events) do
            if event.status=="FAIL" and event.label=="home_trip_drive_final_cargo" then missingFailed=true end
        end
        expect(missingFailed and state.auditCalls==3 and state.auditPasses==0 and not f.dutyProofGranted
            and H.phase=="home_trip_finish_wait",
            "stable crew skipped a failed exact-ID audit and entered successful photographs")
        setDrive(priorDrive)
    end
    state,H,f=dutyFixture()
    H.config.home_trip_duty_timeout_ms=1000 state.order="follow" state:step(1000,100)
    expect(#state.shots==1 and string.find(state.shots[1],"cleanup-pending",1,true)
        and state.checkpoint.state=="cleanup_pending" and f.dutyReadyAt==nil and state.visible and state.zoomCalls==0
        and state.minimapRemoved==0 and f.primary.teleports==0 and H.phase=="home_trip_finish_wait",
        "a legitimate pending handover was changed into successful settled duty")
    for _,blocked in ipairs({"active","dormant","primaryDenied","no_safe_floor","unproved"}) do
        state,H,f=dutyFixture()
        H.phase="home_trip_photo_next" f.photoAt,f.photoFrame,f.photoIndex=0,100,1
        f.photoJobs={{kind="name",label="name-scene",id=f.crew[1].id}}
        f.dutyProofGranted=blocked~="unproved"
        if blocked=="active" then state.active={} elseif blocked=="no_safe_floor" then state.world.allOccupied=true
        else state[blocked]=true end
        state:step(500,102)
        expect(f.primary.teleports==0 and state.member.teleports==0 and state.world.recoveries==0
            and #state.shots==0 and f.photoIndex==2,"observer camera moved in blocked photo context: "..blocked)
    end
end

-- Exercise the actual sheet phase, not a duplicated timing predicate. The
-- screenshot request must get both 500ms and two rendered frames before Send.
do
    local H,f= context(0,38.5)
    H.phase,H.phaseStartedAt="home_trip_sheet",0
    local sent,shots,failures=0,0,0
    local sheet={pending=false,review={canStart=true}}
    local root={detail={homeTripSheet=sheet}}
    local active
    SurvivorCompanion.HomeTrip={current=function() return active end,draft=function() return {canStart=true,distance=200} end}
    SurvivorCompanion.UI={open=function() return root end}
    SurvivorCompanion.UIHomeTrip={onButton=function(detail,button)
        expect(detail==root.detail and button.scHomeAction=="send","probe bypassed the public Send handler")
        sent=sent+1 sheet.sendPending=true
    end}
    getCore=function() return {TakeFullScreenshot=function() shots=shots+1 end} end
    ModData={getOrCreate=function() return {} end}
    local function result(status) if status=="FAIL" then failures=failures+1 end end
    local function check(_,value) if not value then failures=failures+1 end return value==true end
    local function phase(value,at) H.phase,H.phaseStartedAt=value,at end
    Probe.step(H,2000,check,result,phase)
    expect(shots==1 and sent==0 and H.phase=="home_trip_sheet","review capture sent the trip in the same tick")
    f.frames=101 Probe.step(H,2499,check,result,phase)
    expect(sent==0,"review capture did not receive the full 500ms settling interval")
    Probe.step(H,2500,check,result,phase)
    expect(sent==0,"review capture launched after only one rendered frame")
    f.frames=102 Probe.step(H,2500,check,result,phase)
    expect(sent==1 and shots==1 and H.phase=="home_trip_dispatch" and active==nil and failures==0,
        "review capture failed to queue exactly one departure after both settling boundaries")
    Probe.step(H,2600,check,result,phase)
    expect(sent==1 and H.phase=="home_trip_dispatch" and failures==0,
        "queued departure was treated as an immediate mission or submitted twice")
    sheet.sendPending=nil
    active={roster=f.crew,scout={kind="home"}}
    Probe.step(H,2700,check,result,phase)
    expect(sent==1 and H.phase=="home_trip_walk" and failures==0,
        "probe did not wait for the production scheduled departure")
end
-- Stale public reviews may ask for another ordinary review. The probe never
-- starts a mission itself or clicks again while the live sheet is queued.
do
    local function fixture(action)
        local H,f,world,_,primary,member=context(0,200)
        H.phase,H.phaseStartedAt="home_trip_sheet",0
        local state={action=action or "queue",calls=0,drafts=0,invalidates=0,forbidden=0,events={},shots={}}
        local sheet={pending=false,revision=0,reviewAvailabilityKey="review:0",review={canStart=true}}
        local root={detail={tab="groups",homeTripSheet=sheet}}
        state.root,state.originalSheet=root,sheet
        local function forbidden() state.forbidden=state.forbidden+1 error("probe bypassed public/scheduled departure") end
        SurvivorCompanion.HomeTrip={current=function() return state.active end,start=forbidden,draft=function()
            state.drafts=state.drafts+1 return {canStart=true,distance=200}
        end}
        SurvivorCompanion.UI={instance=root,open=function() return root end}
        SurvivorCompanion.UIHomeTrip={update=forbidden,onButton=function(detail,button)
            expect(detail==SurvivorCompanion.UI.instance.detail and button.scHomeAction=="send","Send targeted a stale public detail")
            state.calls=state.calls+1
            local current=detail.homeTripSheet
            if state.action=="stale" then
                current.pending,current.review,current.reviewAvailabilityKey=true,nil,nil current.revision=current.revision+1
            elseif state.action=="replace" then
                SurvivorCompanion.UI.instance={detail={tab="groups",homeTripSheet={pending=false,sendPending=true,
                    revision=1,reviewAvailabilityKey="replacement",review={canStart=true}}}}
            elseif state.action=="hard" then
                current.review={canStart=false,blocker="home_no_camp"} current.revision=current.revision+1
            elseif state.action~="silent" then current.sendPending=true end
        end,invalidate=function(detail)
            state.invalidates=state.invalidates+1
            local current=detail.homeTripSheet
            current.pending,current.review=true,nil current.revision=current.revision+1
        end}
        function state:sheet() return SurvivorCompanion.UI.instance.detail.homeTripSheet end
        function state:ready()
            local current=self:sheet()
            current.pending,current.sendPending=false,nil current.review={canStart=true}
            current.reviewAvailabilityKey="review:"..current.revision
        end
        local function result(status,label,detail) state.events[#state.events+1]={status=status,label=label,detail=detail} end
        local function check(label,value,detail) result(value and "PASS" or "FAIL",label,detail) return value==true end
        local function phase(value,at) H.phase,H.phaseStartedAt=value,at end
        function state:step(at,frames) f.frames=frames Probe.step(H,at,check,result,phase) end
        function state:failed(label)
            for _,event in ipairs(self.events) do if event.status=="FAIL" and (not label or event.label==label) then return true end end
            return false
        end
        getCore=function() return {TakeFullScreenshot=function(_,name) state.shots[#state.shots+1]=name end} end
        ModData={getOrCreate=function() return {} end}
        return state,H,f,world,primary,member
    end
    local state,H,f,world,primary,member=fixture("stale")
    state:step(2000,100) state:step(2500,102)
    expect(state.calls==1 and H.phase=="home_trip_sheet" and state:sheet().pending and not state:failed(),
        "an explicit stale-review decline must wait for ordinary review instead of failing or double-clicking")
    state:step(3000,104)
    expect(state.calls==1 and state.drafts==1,"pending ordinary review triggered another Send or backend draft")
    state:ready() state.action="queue" state:step(3100,106) state:step(3599,107) state:step(3600,107)
    expect(state.calls==1,"refreshed review skipped its full500ms/two-frame boundary")
    state:step(3600,108) state:step(3700,109)
    expect(state.calls==2 and H.phase=="home_trip_dispatch" and state:sheet().sendPending and not state:failed()
        and state.invalidates==0 and state.forbidden==0 and primary.teleports==0 and member.teleports==0,
        "fresh ordinary review must queue once without forcing planning/start or repeating an actual pending Send")
    state,H,f=fixture("replace") state:step(2000,100) state:step(2500,102) state:step(2600,103)
    expect(state.calls==1 and not state.originalSheet.sendPending and state:sheet().sendPending
        and f.sendRoot==SurvivorCompanion.UI.instance and H.phase=="home_trip_dispatch" and not state:failed(),
        "a replaced real detail/sheet must be reacquired before checking pending and must never receive a duplicate Send")
    state,H,f=fixture() state:sheet().sendPending=true state:step(2000,100) state:step(3000,102)
    expect(state.calls==0 and H.phase=="home_trip_dispatch" and not state:failed(),"an already queued live sheet must never be clicked by the probe")
    state,H,f=fixture() state:step(2000,100) state:step(2500,102)
    state:sheet().sendPending=nil state:sheet().revision=1
    state:sheet().reviewNotice="Review changed."
    state:step(2600,103) state:ready() state:step(2700,104) state:step(3200,106)
    expect(state.calls==2 and state.invalidates==1 and H.phase=="home_trip_dispatch" and not state:failed()
        and state.forbidden==0,"a scheduled review-change refusal must queue ordinary refresh and return through a fresh public review")
    state,H,f=fixture("stale")
    for attempt=1,3 do
        if attempt>1 then state:ready() end
        state:step(2000+(attempt-1)*600,100+(attempt-1)*4)
        state:step(2500+(attempt-1)*600,102+(attempt-1)*4)
    end
    expect(state.calls==3 and f.sendAttempts==3 and H.phase=="home_trip_finish_wait"
        and state:failed("home_trip_public_send_retry_limit") and state.forbidden==0,
        "perpetually stale reviews must stop after exactly three real public attempts")
    state,H,f=fixture() state:sheet().pending=true state:sheet().review=nil
    state:step(2000,100) state:step(14999,102)
    expect(H.phase=="home_trip_sheet" and state.calls==0 and not state:failed(),"review wait ended before its15-second bound")
    state:step(15000,104)
    expect(state:failed("home_trip_public_review_deadline") and H.phase=="home_trip_finish_wait" and state.calls==0,
        "a review that never becomes ready must fail at15 seconds without any Send")
    for _,action in ipairs({"hard","silent"}) do
        state,H,f=fixture(action) state:step(2000,100) state:step(2500,102)
        expect(state.calls==1 and state.invalidates==0 and H.phase=="home_trip_finish_wait" and state:failed()
            and state.forbidden==0,"hard blockers and unexplained declines must not be retried: "..action)
    end
    state,H,f=fixture() state:sheet().review={canStart=false,blocker="home_no_camp"}
    state:step(2000,100)
    expect(state.calls==0 and state.drafts==0 and state.invalidates==0 and state:failed("home_trip_public_review_blocked"),
        "a visible hard blocker must remain a failure without automated review refresh or Send")
end
print("HOME_TRIP_PROBE_REGRESSION_PASS checks="..checks.." occupied-near=true queued-int=true arrival-name=true resume-segment=true dormant-boundary=true duty-settle=true solo-scene=true review-frame-boundary=true bounded-public-review-retry=true")
