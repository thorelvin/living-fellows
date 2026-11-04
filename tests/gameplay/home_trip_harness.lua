-- SPDX-License-Identifier: MIT
-- Production controller + home handover: no native actor duplication, no
-- one-member arrival shortcut, no search/site work hidden behind a home kind.
local SC=SurvivorCompanion
local E,H,I=SC.ExpeditionPrototype,SC.HomeTrip,SC.ExpeditionIntegration
local slot,owned,now,routeCalls,remoteReleases,joinedReleases=nil,false,1000,0,0,0
local available,roadAvailable,visible=true,true,true
local releaseFailure,removed,prepares,commits=false,false,0,0
local commitFailure,prepareFailure=false,false
local base={id="base:home-test",core={x=200,y=200,z=0},zones={{kind="area",x1=190,y1=190,x2=210,y2=210,z=0}}}
local records,orders,nativeActors={},{},{}
local corpseStageOkay,stagedCorpses,prepareAttempts,handoffs=true,{},0,0
local function at(actor,x,y,z) actor.x,actor.y,actor.z=x,y,z or 0 end
local function actor(id,x,y)
    local a={id=id,x=x,y=y,z=0,data={},inventory={}}
    function a:getX() return self.x end
    function a:getY() return self.y end
    function a:getZ() return self.z end
    function a:isDead() return self.dead==true end
    function a:isCorpseReady() return self.corpseReady==true end
    function a:getCurrentSquare() return self end
    function a:getRoom() return nil end
    function a:getVehicle() return self.vehicle end
    function a:getModData() return self.data end
    function a:getInventory() return self.inventory end
    return a
end
local player=actor("player",80,80)
for index=1,5 do
    local a=actor("sc-home-"..index,100+index,100)
    nativeActors[index]=a
    records[index]={id=a.id,actor=a,recruited=true,runtime={}}
    orders[a]={order="follow",commandSerial=0}
end
local function call(value,name,...)
    if value and type(value[name])=="function" then return value[name](value,...),true end
    return nil,false
end
local function distance(a,b) return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2) end
SC.GameplayUtil={call=call,position=function(a) return a and a.x,a and a.y,a and a.z end,
    nowMs=function() return now end,nameOf=function(a) return a.id end,idOf=function(a) return a.id end,
    isDead=function(a) return a.dead==true end,canSee=function() return visible end,
    sameFloor=function(a,b) return a.z==b.z end,distance=distance,
    nativeHealth=function() return 100 end,characterStatValue=function() return 0 end,
    config=function() return nil end,inventory=function(a) return a.inventory end,
    inventoryItemsDeep=function(inventory) return inventory end}
SC.GameplayUtil.gridSquare=function(x,y,z) return {x=x,y=y,z=z} end
SC.Registry={byId=function(id) for _,r in ipairs(records) do if r.id==id and not r.unregistered then return r end end end,
    isActive=function(a,id) local r=SC.Registry.byId(id) return not removed and r and r.actor==a end}
SC.Commands={peek=function(a) return orders[a] end,resumeBaseDutyIfUnchanged=function(id,serial)
    local r=SC.Registry.byId(id)
    if not r or orders[r.actor].commandSerial~=serial then return false,"new_player_order" end
    orders[r.actor].order="base_duty" return true
end}
SC.BaseLife={active=function() return base end,isInside=function(a)
    if not base then return false end
    for _,z in ipairs(base.zones) do if z.kind=="area" and a.z==z.z and a.x>=z.x1 and a.x<=z.x2 and a.y>=z.y1 and a.y<=z.y2 then return true end end
    return false
end,storageRows=function() return {} end}
SC.BaseWatch={current=function() return nil end}
SC.Vehicle={isNativeSeated=function(a) return a.vehicle~=nil,a.vehicle end}
SC.ViewSession={claim=function(_,a) slot,owned=a,true return true,a end,owner=function() return owned and "expedition" or nil end,
    slotSqlId=function() return 2 end,released=function() slot,owned=nil,false return true end,
    rememberSlotSqlId=function() end}
SC.Persistence={restoreStatus=function() return true end,completeRemoteArrival=function(token) assert(token==42+prepares) return true end,
abortRemoteArrival=function() return commitFailure end,
commitRemoteArrival=function(actors,camp,token,integration)
    commits=commits+1
    if commitFailure then return false,"injected pre-ack failure" end
    assert(#actors==2,"remote persistence receives the complete crew")
    assert(I.valid(integration) and integration.kind=="home","durable home obligation accompanies actor snapshots")
    assert(H.campUnchanged(camp) and token==42+prepares,"exact captured camp and native ticket")
    local final=E.exportRemoteArrival(integration)
    assert(final and final.state=="idle" and final.schema==2 and #final.deliveries==1
        and final.debrief.kind=="home" and E.current(),"durable finished descriptor leaves live mission owned until teardown")
    return true
end}
SC.Logistics={roleMinimums=function() return {} end,update=function(a)
    a.data.LF_FieldReturnCleanup=nil return false,"load_balanced"
end}
SC.ExpeditionRoute={plan=function(a,target)
    routeCalls=routeCalls+1
    if not roadAvailable then return nil,"no_road" end
    return {points={{x=a.x,y=a.y,z=0,street=""},{x=target.x,y=target.y,z=0,street=""}},
        index=1,roadLength=250,inferredJunctions=0,fingerprint="home-test",goal=target}
end,verifyEntry=function() return true end,descriptor=function(route,phase)
    return {version=1,phase=phase,fingerprint=route.fingerprint,goal=route.goal}
end,validDescriptor=function(d) return type(d)=="table" and d.version==1 and d.phase=="inbound" end}
SCSplitScreenProbe={remoteArrivalCapability=function() return available end,
    prepareRemoteArrival=function(actors)
        prepareAttempts=prepareAttempts+1
        assert(#actors==2)
        for _,a in ipairs(actors) do assert(not a.dead,"remote snapshot roster excludes casualties") end
        for _,a in ipairs(nativeActors) do
            if a.dead then assert(stagedCorpses[a],"known corpse is retained before remote prepare") end
        end
        if prepareFailure then error("injected prepare refusal") end
        prepares=prepares+1 return 42+prepares
    end,
    remoteArrivalSlotSqlId=function() return 2 end,releaseRemoteArrival=function()
        if releaseFailure then releaseFailure=false return false end
        remoteReleases=remoteReleases+1 return true
    end,
    leaderSqlId=function() return 2 end,canReleaseJoinedLeader=function() return true end,
    persistJoinedLeaderSlotForReuse=function() return 2 end,
    releaseJoinedLeader=function() joinedReleases=joinedReleases+1 return true end,
    stageDeadCorpseChunk=function(a)
        assert(a.dead and a.corpseReady,"only a ready native corpse can be retained")
        if not corpseStageOkay then return false end
        stagedCorpses[a]=true return true
    end,
    handoff=function(a) handoffs=handoffs+1 slot=a return a end,
    releaseForWorldExit=function() slot=nil return true end,isLeader=function(a) return a==slot end}
function getSpecificPlayer(index) return index==0 and player or index==1 and slot or nil end
function getGameTime() return {getWorldAgeHours=function() return 100 end} end
function destroyPlayerData() end
Events=nil
local selection={records={records[1],records[2]},travelMode="road"}
local function reset()
    if E.current() then assert(E.prepareReset()) end
    assert(E.reset()) H.reset()
    available,roadAvailable,visible=true,true,true
    releaseFailure,removed=false,false
    commitFailure,prepareFailure=false,false
    corpseStageOkay,stagedCorpses=true,{}
    for index,r in ipairs(records) do
        r.actor,r.unregistered=nativeActors[index],nil
        r.actor.dead,r.actor.corpseReady=nil,nil
        at(r.actor,100+index,100) r.actor.vehicle=nil r.recruited=true
        orders[r.actor]={order="follow",commandSerial=0}
    end
    at(player,80,80)
end
local function blocked(reason,chosen)
    local d=H.draft(chosen or selection,true)
    assert(d.canStart==false and d.blocker==reason,"expected blocker "..reason..", got "..tostring(d.blocker))
end
available=false blocked("home_safe_handover_unavailable") available=true
SC.BaseWatch.current=function() return {} end blocked("home_view_base_watch") SC.BaseWatch.current=function() end
local savedBase=base base=nil blocked("home_no_camp") base=savedBase
blocked("home_too_many",{records=records})
blocked("home_duplicate_member",{records={records[1],records[1]}})
local original=records[1].actor records[1].actor=nil blocked("home_member_unavailable",{record=records[1]}) records[1].actor=original
base.core.z=1 blocked("home_camp_ground_area_required") base.core.z=0
orders[records[1].actor].order="guard"
local roster=H.roster(selection)
assert(#roster.records==1 and #roster.exclusions==1,"Stay/Guard members are explicitly excluded")
blocked("home_leader_unavailable",{records=selection.records,leaderId=records[1].id})
orders[records[1].actor].order="follow"
records[1].actor.z=1 blocked("home_ground_floor_only",{record=records[1]}) records[1].actor.z=0
records[1].actor.vehicle={} blocked("home_member_seated",{record=records[1]}) records[1].actor.vehicle=nil
records[1].recruited=false
assert(H.eligibility({record=records[1]}).hidden,"unrecruited menu is hidden") records[1].recruited=true
at(records[1].actor,200,200)
assert(H.eligibility({record=records[1]}).hidden,"already-home menu is hidden") at(records[1].actor,101,100)
local before=routeCalls H.eligibility(selection) H.roster(selection)
assert(routeCalls==before,"menus never plan routes")
local draft=H.draft(selection,true)
assert(draft.canStart and draft.travelMode=="road" and draft.estimatedHours>0 and #draft.streets==0,"honest one-way preview has no invented street")
before=routeCalls H.draft(selection) assert(routeCalls==before,"unchanged selection uses cached route")
roadAvailable=false
draft=H.draft(selection,true)
assert(draft.canStart and draft.routeFallback and draft.travelMode=="straight","road failure explicitly falls back to straight")
at(records[1].actor,1500,100) blocked("home_too_far",{record=records[1],travelMode="straight"}) at(records[1].actor,101,100)
roadAvailable=true
local okay,active=H.start(selection)
assert(okay and active.scout.kind=="home" and active.scout.phase=="inbound" and not active.scout.search and not active.scout.site,"home starts inbound with no outbound work")
blocked("home_view_trip")
assert(H.describe(player).observed and not H.canRecall(player),"second view grants knowledge, never earshot")
local saved=E.export()
assert(saved.schema==9 and saved.scout.home.camp.fingerprint and saved.scout.kind=="home","home exports dedicated schema")
assert(E.prepareReset() and E.reset())
assert(E.restore(saved) and E.current().scout.kind=="home" and E.current().restoring,"mid-trip home restore retains kind and expected survivors")
assert(E.prepareReset() and E.reset())
saved.scout.home.camp.core.x=201
assert(not E.restore(saved),"mutated home target rejected")
reset()
okay,active=H.start(selection) assert(okay)
at(records[1].actor,200,200)
assert(not E.finishHome() and remoteReleases==0,"leader alone cannot complete arrival")
local absent=active.roster[2].actor active.roster[2].actor=nil
assert(not E.finishHome(),"unresolved expected survivor blocks release") active.roster[2].actor=absent
at(records[2].actor,201,200) records[2].actor.vehicle={}
assert(not E.finishHome(),"seated member blocks arrival") records[2].actor.vehicle=nil
base.core.x=201
assert(not E.finishHome(),"same camp ID with moved core blocks arrival") base.core.x=200
base.zones[1].x1=189
assert(not E.finishHome(),"same camp ID with changed bounds blocks arrival") base.zones[1].x1=190
SC.ActionSupervisor={current=function(a) return a==records[2].actor and {} or nil end}
assert(not E.finishHome() and active.homeRelease==nil,"active item or vitals action finishes before native prepare")
SC.ActionSupervisor=nil
releaseFailure=true
assert(not E.finishHome() and E.current().homeRelease.committed,"failed native teardown retains committed transaction")
assert(H.handoverOwns(records[1].actor) and not H.handoverOwns(records[3].actor),"handover freezes only exact travelling crew")
local nested={getContainingItem=function() return {getContainer=function() return records[1].actor.inventory end} end}
assert(H.inventoryContainerFrozen(nested) and not H.inventoryContainerFrozen(records[3].actor.inventory),"nested held inventory stays frozen without affecting unrelated companions")
local deepest=records[1].actor.inventory
for _=1,12 do
    local parent=deepest
    deepest={getContainingItem=function() return {getContainer=function() return parent end} end}
end
assert(H.inventoryContainerFrozen(deepest),"depth-limit bag fallback checks the held root after twelve ancestry links")
local prepareBefore,commitBefore=prepares,commits
removed=true
assert(E.pulse() and remoteReleases==1 and E.current()==nil,"detached crew safely retry native release without casualty handling")
assert(prepares==prepareBefore and commits==commitBefore,"native retry reuses exact ticket and durable snapshot")
removed=false
local debrief=E.lastDebrief()
assert(debrief.kind=="home" and I.valid(debrief.integration) and #debrief.integration.items==0,"home empty acquisition ledger is not cargo delivery")
local summary=I.summary(debrief.integration)
assert(summary.deliveryPending and not summary.complete and summary.stored==0,"cleanup and restock remain explicitly pending without invented deliveries")
local idle=E.export()
assert(#idle.deliveries==1 and idle.deliveries[1].members[1].cleanupDone==false,"pending cleanup persists after view closes")
assert(E.reset() and E.restore(idle),"idle home debrief and durable pending handover restore")
local delivery=idle.deliveries[1]
for _,r in ipairs(selection.records) do for step=1,7 do I.update(delivery,r.actor) end end
assert(I.summary(delivery).complete,"loaded cleanup and role restock settle through ordinary storage policy")
reset()
at(player,100,100)
okay,active=H.start(selection) assert(okay)
at(records[2].actor,140,100)
assert(H.cancel(player) and E.current() and joinedReleases==0,"near recall stages the whole crew")
assert(not E.finishAtPlayer(player) and E.current(),"seeing leader never releases distant follower")
records[2].actor.vehicle={} at(records[2].actor,102,100)
assert(not E.finishAtPlayer(player),"near recall requires everyone unseated") records[2].actor.vehicle=nil
assert(E.finishAtPlayer(player) and joinedReleases==1,"assembled recall uses joined release")
assert(E.lastDebrief().endReason=="recalled_nearby" and not E.lastDebrief().integration,"recall does not deliver inventory at player")
reset()
okay,active=H.start(selection) assert(okay)
at(records[1].actor,213.04785,200.5029) at(records[2].actor,214,200)
active.scout.phase="awaiting_player"
active.scout.legPlan={blockedExteriorSurvey=true}
local releaseBeforeApproach=remoteReleases
assert(not H.pulse(active) and active.scout.phase=="inbound"
    and active.testWaypoint and active.testWaypoint.x==200 and active.testWaypoint.y==200
    and active.scout.legPlan==nil and H.finalApproachFor(records[1].actor),
    "outside-camp leader13m away resumes a real core waypoint instead of waiting at exterior fence")
assert(not E.finishHome() and remoteReleases==releaseBeforeApproach,"final approach never weakens every-member inside arrival")
local walk=H.describe(player)
assert(walk.finalApproach and walk.walkWaypoint and walk.walkWaypoint.x==200,"observed home card exposes actual final waypoint for diagnosis")
do
    -- Use an actual straight Home mission here: this watchdog regression
    -- owns no road/horde planner, which the cheap draft fixture omits.
    reset()
    local started,active=H.start({records=selection.records,travelMode="straight"})
    assert(started)
    at(records[1].actor,213.04785,200.5029) at(records[2].actor,214,200)
    assert(not H.pulse(active) and active.testWaypoint,"watchdog fixture stages its actual final approach")
    local previousNavigation,previousDecision,previousSupervisor,previousTraversal=
        SC.Navigation,SC.Decision,SC.ActionSupervisor,SC.NativeTraversalActions
    local previousNow=now
    local scout=active.scout
    local waypoint=active.testWaypoint
    local cancels,statusReads=0,0
    -- Navigation.status gives recovery priority over planning, but still
    -- reports the retained pathSearch age. This is its real simultaneous
    -- stuckAttempts>0 + pathSearch shape, not a completed/failed search.
    local navigation={active=true,phase="planning",action="ordered_move",stuckAttempts=0,pathSearchAgeMs=9000}
    SC.Navigation={status=function(a)
        assert(a==records[1].actor,"the watchdog observes only its actual leader")
        statusReads=statusReads+1 return navigation
    end,cancel=function(a,reason)
        assert(a==records[1].actor and reason=="scout_stalled","only the expired expedition route may be cancelled")
        cancels=cancels+1
    end}
    SC.Decision,SC.ActionSupervisor,SC.NativeTraversalActions=nil,nil,nil
    local function stalledWaypoint(age)
        active.testWaypoint=waypoint
        scout.bestDistanceToWaypoint=distance(records[1].actor,waypoint)
        scout.lastProgressAt,scout.waypointStagedAt=now-age,now-age
        scout.lastPlanAt,scout.replans,scout.lastStalledTarget=now,0,nil
    end
    now=previousNow+10000
    stalledWaypoint(9000)
    E.pulse()
    assert(active.testWaypoint==waypoint and cancels==0 and statusReads==1,
        "control: an ordered-move search in planning retains its Home core waypoint")
    now=now+10000
    navigation.phase,navigation.stuckAttempts="recovering",1
    stalledWaypoint(9000)
    E.pulse()
    assert(active.testWaypoint==waypoint and cancels==0 and statusReads==2,
        "recovering ordered_move with a live 9000ms pathSearch must retain its frontier until the 30000ms waypoint ceiling")
    local function expires(age,searchAge,searchActive,action,message)
        now=now+10000
        navigation.pathSearchAgeMs,navigation.active,navigation.action=searchAge,searchActive,action
        local prior=cancels
        stalledWaypoint(age)
        E.pulse()
        assert(active.testWaypoint==nil and cancels==prior+1,message)
    end
    expires(9000,nil,true,"ordered_move","recovery without a retained search still cancels after the eight-second movement watchdog")
    expires(9000,30000,true,"ordered_move","a search at thirty seconds cannot retain the stalled Home waypoint")
    expires(30000,9000,true,"ordered_move","a fresh retained search cannot extend the thirty-second waypoint ceiling")
    expires(9000,-1,true,"ordered_move","a negative search age cannot suppress the movement watchdog")
    expires(9000,"9000",true,"ordered_move","a nonnumeric search age cannot suppress the movement watchdog")
    expires(9000,9000,false,"ordered_move","an inactive navigation goal cannot retain the stalled Home waypoint")
    expires(9000,9000,true,"drink_source","an unrelated retained search cannot retain the expedition waypoint")
    SC.Navigation,SC.Decision,SC.ActionSupervisor,SC.NativeTraversalActions=
        previousNavigation,previousDecision,previousSupervisor,previousTraversal
    now=previousNow
end
reset()
okay,active=H.start(selection) assert(okay)
at(records[1].actor,200,200) at(records[2].actor,201,200)
local savedFinish=E.finishHome
E.finishHome=function() return false,"injected_finish_refusal" end
assert(H.pulse(active) and active.scout.home.blocker=="injected_finish_refusal","arrival refusal is visible rather than silently walking forever")
E.finishHome=savedFinish
reset()
okay,active=H.start(selection) assert(okay)
at(records[1].actor,200,200) at(records[2].actor,201,200) at(player,200,200)
prepareFailure=true
assert(not E.finishHome() and active.homeRelease==nil,"native prepare refusal leaves a cancellable trip")
assert(orders[records[1].actor].order=="follow" and records[1].actor.data.LF_FieldReturnCleanup==nil,"prepare refusal mutates no command or cleanup flag")
assert(H.cancel(player) and active.integration==nil and E.finishAtPlayer(player),"prepare refusal then near recall drops uncommitted home obligation")
assert(orders[records[1].actor].order=="follow" and not E.lastDebrief().integration and #E.pendingDeliveryReports()==0,"cancelled prepare leaves Follow and no home delivery obligation")
reset()
okay,active=H.start(selection) assert(okay)
at(records[1].actor,200,200) at(records[2].actor,201,200)
commitFailure=true
local prepareBaseline=prepares
assert(not E.finishHome() and active.homeRelease==nil and active.integration==nil,"pre-ack failure aborts the old lease and staged obligation")
at(records[1].actor,202,200)
commitFailure=false
assert(E.finishHome() and prepares==prepareBaseline+2,"moved source prepares a fresh lease after abort")
local function casualtyCase(deadIndex)
    reset()
    local crew={records[1],records[2],records[3]}
    local started,trip=H.start({records=crew,travelMode="straight"})
    assert(started,"three-member home casualty fixture starts")
    local fallen=nativeActors[deadIndex]
    local survivors={}
    for index=1,3 do if index~=deadIndex then survivors[#survivors+1]=nativeActors[index] end end
    fallen.dead=true
    records[deadIndex].actor,records[deadIndex].unregistered=nil,true
    assert(trip.roster[deadIndex].actor==fallen,"mission retains the exact corpse pointer after registry death retirement")
    at(survivors[1],200,200) at(survivors[2],201,200)
    local beforePrepare,beforeRelease,beforeHandoff=prepareAttempts,remoteReleases,handoffs
    local finished,reason=E.finishHome()
    assert(not finished and reason=="home_corpse_pending" and prepareAttempts==beforePrepare
        and remoteReleases==beforeRelease and E.current()==trip,
        "a pending native corpse holds the home view before any remote ticket")
    fallen.corpseReady,corpseStageOkay=true,false
    finished,reason=E.finishHome()
    assert(not finished and reason=="home_corpse_retention_failed" and prepareAttempts==beforePrepare,
        "failed corpse retention cannot cross remote preparation or release")
    corpseStageOkay=true
    at(survivors[2],225,200)
    E.pulse()
    assert(stagedCorpses[fallen] and E.current()==trip and trip.leader.actor==survivors[1]
        and slot==survivors[1] and handoffs==beforeHandoff+(deadIndex==1 and 1 or 0),
        "leader loss hands the home view to the living follower; follower loss preserves its leader")
    local checkpoint=E.export()
    assert(#checkpoint.roster==3 and #checkpoint.survivors==2
        and checkpoint.leaderId==survivors[1].id and checkpoint.scout.kind=="home",
        "home casualty history stays separate from the exact saved living roster")
    assert(not E.finishHome() and prepareAttempts==beforePrepare,
        "a casualty never permits release while another surviving member is outside camp")
    at(survivors[2],201,200) survivors[2].vehicle={}
    assert(not E.finishHome() and prepareAttempts==beforePrepare,
        "every surviving casualty-crew member must still be unseated")
    survivors[2].vehicle=nil
    releaseFailure=true
    assert(not E.finishHome() and trip.homeRelease.committed
        and #trip.homeRelease.actors==2 and H.handoverOwns(survivors[1])
        and H.handoverOwns(survivors[2]) and not H.handoverOwns(fallen),
        "remote retirement owns only the two exact surviving actors while teardown retries")
    local final=E.exportRemoteArrival(trip.integration)
    assert(final and #final.debrief.names==2 and #final.debrief.casualties==1
        and final.debrief.casualties[1]==fallen.id and #final.deliveries==1,
        "durable casualty debrief names only actual arrivals and retains camp handover")
    removed=true
    assert(E.pulse() and not E.current() and remoteReleases==beforeRelease+1,
        "retained survivor handover completes its original native ticket")
    removed=false
    for _,survivor in ipairs(survivors) do
        assert(E.integrationFor(survivor),"each living arrival retains its own cleanup and duty obligation")
    end
    assert(not E.integrationFor(fallen),"a fallen member never acquires a camp duty obligation")
    local idle=E.export()
    assert(#idle.deliveries==1 and #idle.debrief.names==2 and #idle.debrief.casualties==1,
        "saving after casualty arrival preserves surviving handover and loss history")
    assert(E.reset() and E.restore(idle),"idle casualty handover restores")
    for _,survivor in ipairs(survivors) do
        assert(E.integrationFor(survivor),"surviving cleanup and duty ownership survives idle save/reload")
    end
end
casualtyCase(2)
casualtyCase(1)
do
    reset()
    local previousCar,previousUnload,previousDriving=SC.ExpeditionCar,SC.VehicleUnload,SC.Driving
    local oldAdopt=SC.ViewSession.adopt
    SC.ViewSession.adopt=function(ownerName,value) return ownerName=="expedition" and owned and slot==value end
    local oldLoaded,oldCargo,oldKeys,oldStationary=SC.Vehicle.loadedBySqlId,SC.Vehicle.cargoPart,
        SC.Vehicle.prepareDriverKeyReset,SC.Vehicle.isStationary
    local oldItems,oldId,oldType,oldContains=SC.GameplayUtil.inventoryItems,SC.GameplayUtil.itemStableId,
        SC.GameplayUtil.itemType,SC.GameplayUtil.inventoryContains
    local function clone(value)
        if type(value)~="table" then return value end
        local result={} for key,item in pairs(value) do result[key]=clone(item) end return result
    end
    local car={id="car",x=188,y=200,z=0}
    function car:getSqlId() return 33 end
    local trunk={items={}}
    function trunk:getItems() return self.items end
    for index=1,2 do
        local item={nativeId=500+index,itemType="Base.Cargo"..index,container=trunk}
        function item:getID() return self.nativeId end
        function item:getContainer() return self.container end
        trunk.items[index]=item
    end
    SC.Vehicle.loadedBySqlId=function(id) return id==33 and car or nil end
    SC.Vehicle.cargoPart=function(value) assert(value==car) return {},trunk end
    SC.Vehicle.prepareDriverKeyReset=function() return true end
    local stationary=true
    SC.Vehicle.isStationary=function() return stationary end
    SC.Driving={release=function() return true end}
    SC.GameplayUtil.inventoryItems=function(container) return container.items or {} end
    SC.GameplayUtil.itemStableId=function(item,create)
        if create and not item.stableId then item.stableId="cargo:"..item.nativeId end
        return item.stableId
    end
    SC.GameplayUtil.itemType=function(item) return item.itemType end
    SC.GameplayUtil.inventoryContains=function(container,item)
        for _,candidate in ipairs(container.items or {}) do if candidate==item then return true end end return false
    end
    local stop={kind="roadside",point={x=188,y=200,z=0},roadEntry={x=188,y=200,z=0},label="Roadside"}
    local drivePlans,prepared,fingerprint,engineOff,canStop,takes=0,0,"car-original",false,false,0
    local nativeAPIs={"homeVehicleSaveCapability","requestHomeVehicleSave","pollHomeVehicleSave","homeVehicleSaveReceipt",
        "restoreHomeVehicleSave","attachRemoteArrivalVehicleSave","cancelHomeVehicleSave","primaryRetainsHomeVehicle"}
    local priorAPIs={} for _,name in ipairs(nativeAPIs) do priorAPIs[name]=SCSplitScreenProbe[name] end
    local carSaveReady,carRequests,carRestores,carAttaches=false,0,0,0
    local rejectCarRequest,carSaveStatus=false,nil
    local primaryRetained,primaryChecks,carCancels=false,0,0
    local receipt={version=1,sqlId=33,tagUUID="lf-home-proof",x=188,y=200,z=0,worldVersion=201,byteLength=100,sha256=string.rep("a",64)}
    SCSplitScreenProbe.homeVehicleSaveCapability=function() return true end
    SCSplitScreenProbe.requestHomeVehicleSave=function(value) assert(value==car) carRequests=carRequests+1 return rejectCarRequest and 0 or 66 end
    SCSplitScreenProbe.pollHomeVehicleSave=function(ticket) assert(ticket==66) return carSaveStatus or (carSaveReady and "ready" or "pending") end
    SCSplitScreenProbe.homeVehicleSaveReceipt=function(ticket) assert(ticket==66) return clone(receipt) end
    SCSplitScreenProbe.restoreHomeVehicleSave=function(saved) assert(saved.tagUUID==receipt.tagUUID) carRestores=carRestores+1 return 66 end
    SCSplitScreenProbe.attachRemoteArrivalVehicleSave=function(ticket,vehicleTicket)
        assert(ticket==42+prepares and vehicleTicket==66 and carSaveReady,"only committed exact car proof attaches before crew durability")
        carAttaches=carAttaches+1 return true
    end
    SCSplitScreenProbe.cancelHomeVehicleSave=function(ticket) assert(ticket==66) carCancels=carCancels+1 return true end
    SCSplitScreenProbe.primaryRetainsHomeVehicle=function(value,sqlId)
        assert(value==car and sqlId==33,"native retention checks the exact selected loaded car and SQL identity")
        primaryChecks=primaryChecks+1
        return primaryRetained and engineOff and records[1].actor.vehicle==nil and records[2].actor.vehicle==nil
    end
    local fieldPlan={field=true,vehicle=car,sqlId=33,script="Base.TestCar",name="Test car",distance=4000,
        estimatedHours=.2,homeStop=stop,seats={[records[1].id]=0,[records[2].id]=1},
        fuel=10,departure={x=100,y=100,z=0},heading=0}
    SC.ExpeditionCar={fieldFingerprint=function() return fingerprint end,
        preflightField=function() drivePlans=drivePlans+1 return fieldPlan,nil,{name="Test car",seats=2,neededSeats=2} end,
        prepareField=function(input,value,baseValue,options)
            assert(value==car and options.reviewedPlan==fieldPlan,"dispatch retains the exact reviewed car route")
            prepared=prepared+1 return fieldPlan
        end,
        validFieldStop=function(value) return value and value.kind=="roadside" end,
        fieldDescriptor=function(plan,camp)
            return {field=true,state="walking_to_car",leg="home",sqlId=33,script=plan.script,seats=clone(plan.seats),
                homeStop=clone(stop),home=clone(camp.core),departure=clone(stop.point),siteStop=clone(stop.point),
                homeRoadEntry=clone(stop.roadEntry),parkingZoneId="roadside",parking={x1=187,y1=199,x2=189,y2=201,z=0},
                departureFuel=10,departureHeading=0}
        end,
        copyDescriptor=function(value) return clone(value) end,
        exportDescriptor=function(value) return clone(value) end,
        restoreDescriptor=function(value) local saved=clone(value) if saved.state=="driving_home" then saved.state="interrupted_by_load" end return saved end,
        homeArrivalReady=function(trip) return trip.scout.vehicle.state=="home_wait" and engineOff or trip.scout.vehicle.state=="abandoned" and engineOff,"home_car_unsettled" end,
        cancelField=function(trip)
            if not canStop then return false,"drive_stop_pending" end
            engineOff=true
            local ready,reason=H.carStopReady(trip,car)
            if not ready then return false,reason end
            trip.scout.vehicle.state,trip.scout.vehicle.engineStopped="abandoned",true
            return true
        end}
    SC.VehicleUnload={eligible=function() return false,"car_not_parked_at_base" end,
        takeExact=function() takes=takes+1 return false,"must_not_take_roadside_cargo" end}
    local chosen={records=selection.records,travelMode="drive",vehicle=car,vehicleSqlId=33}
    records[1].actor.vehicle=car
    assert(H.recordEligibility(records[1],player,chosen),"only selected parked-car occupants may begin a driving home trip")
    assert(not H.recordEligibility(records[1],player,{travelMode="straight"}),"walking still rejects seated travellers")
    stationary=false
    assert(not H.recordEligibility(records[1],player,chosen),"a moving selected car never bypasses seated-crew eligibility")
    stationary=true records[1].actor.vehicle=nil
    local review=H.draft(chosen,true)
    assert(review.canStart and review.measuredDistance==4000 and review.estimatedHours==.2 and review.homeStop.kind=="roadside",
        "drive preview uses measured one-way car distance and genuine car ETA up to5000m")
    assert(not trunk.items[1].stableId,"car review reads exact cargo without creating item identity or transferring it")
    H.draft(chosen) assert(drivePlans==1,"unchanged drive review never replans the cached road route")
    fingerprint="car-changed"
    local accepted,why=H.start(chosen,review)
    assert(not accepted and why=="home_review_changed" and prepared==0,"stale car review never silently selects another car or dispatches")
    fingerprint="car-original"
    local started,trip=H.start(chosen,review)
    assert(started and prepared==1 and drivePlans==1 and trip.scout.vehicle.leg=="home"
        and trip.scout.phase=="walking_to_car" and not trip.scout.search and not trip.scout.site,
        "field car starts only its home leg, reusing its reviewed route without outbound work")
    trip.scout.vehicle.state,trip.scout.phase="driving_home","driving_home"
    local saved=E.export()
    assert(saved.schema==9 and saved.scout.home.cargo[1].nativeId==501 and saved.scout.vehicle.sqlId==33,
        "drive persistence keeps exact initial trunk identities and stopped-car SQL identity")
    assert(E.prepareReset() and E.reset() and E.restore(saved) and E.current().scout.kind=="home"
        and E.current().scout.vehicle.state=="interrupted_by_load","driving home restores through the proven vehicle restart descriptor")
    assert(E.prepareReset() and E.reset())
    started,trip=H.start(chosen,review) assert(started)
    at(records[1].actor,200,200) at(records[2].actor,201,200)
    local beforePrepare=prepareAttempts
    assert(not E.finishHome() and prepareAttempts==beforePrepare,"crew inside camp cannot close an unsettled car trip")
    trip.scout.vehicle.state="home_wait"
    assert(not E.finishHome() and prepareAttempts==beforePrepare,"a running car cannot cross the remote handover boundary")
    engineOff=true
    rejectCarRequest=true
    assert(not E.finishHome() and carRequests==1 and prepareAttempts==beforePrepare
        and H.inventoryContainerFrozen(trunk),"a refused settling-car request holds its exact trunk without preparing a crew lease")
    assert(not E.finishHome() and carRequests==1,"failed initial car snapshot request does not spin within the same tick")
    now=now+499
    assert(not E.finishHome() and carRequests==1,"car snapshot refusal waits a bounded500ms before retrying")
    now=now+1 rejectCarRequest=false
    assert(not E.finishHome() and carRequests==2 and prepareAttempts==beforePrepare
        and H.inventoryContainerFrozen(trunk),"settled car retries initial request and waits for real DB durability before crew prepare")
    local bag={getContainingItem=function() return {getContainer=function() return trunk end} end}
    assert(H.inventoryContainerFrozen(bag),"nested trunk containers freeze with the actual car DB snapshot")
    carSaveReady=true
    local attached={scout={home={vehicleSqlId=33}},homeCarSave={car=car,ticket=66,receipt=clone(receipt)},
        homeRelease={carAttached=true,committed=true}}
    carSaveStatus="failed"
    assert(not H.carStopReady(attached,car) and carRequests==2,"an attached durable crew lease never replaces its failed car ticket")
    attached.homeCarSave.ticket=nil
    assert(not H.carStopReady(attached,car) and carRequests==2,"missing attached car proof never restarts acknowledged crew capture")
    attached.scout.home.recalling,attached.scout.home.recallStopping,primaryRetained=true,true,true
    assert(not H.carStopReady(attached,car) and carRequests==2,"near recall cannot waive an attached or durable crew lease")
    primaryRetained=false
    carSaveStatus=nil
    assert(E.finishHome(),"stopped roadside car and every unseated survivor inside camp permit handover")
    local report=E.lastDebrief()
    assert(report.homeStop.kind=="roadside" and report.vehicleSqlId==33 and report.vehicleState=="home_wait"
        and #report.integration.items==2 and report.integration.items[1].nativeId==501
        and report.integration.carSaveReceipt.tagUUID==receipt.tagUUID and carAttaches==1,
        "roadside debrief carries the actual car outcome and exact initial trunk receipt ledger")
    local pending=E.export()
    do
        local canceled=clone(pending)
        for _,member in ipairs(canceled.deliveries[1].members) do
            member.cleanupDone,member.dutyDone=true,true
            member.cleanupReason,member.dutyReason="new_player_order","new_player_order"
        end
        assert(E.reset() and E.restore(canceled),"partial Home delivery restores canceled member duties")
        assert(not E.pendingHomeMember(records[1].id) and E.pendingHomeInventory(records[1].id)
            and E.pendingHomeInventory(records[2].id) and not E.pendingHomeInventory("sc-unrelated"),
            "pure persistence ownership preserves unfinished Home cargo for recorded members after UI duty ownership ends")
        local stillPending=E.export()
        assert(#stillPending.deliveries==1 and not stillPending.deliveries[1].items[1].stored
            and not stillPending.deliveries[1].items[1].released,
            "the identity query neither settles nor edits any exact pending receipt")
        for _,item in ipairs(canceled.deliveries[1].items) do item.released=true end
        assert(E.reset() and E.restore(canceled) and not E.pendingHomeInventory(records[1].id),
            "completed Home receipts and duties grant no further exact inventory scope")
        canceled=clone(pending) canceled.deliveries[1].kind=nil
        assert(E.reset() and E.restore(canceled) and not E.pendingHomeInventory(records[1].id),
            "an ordinary expedition delivery never grants Home native-inventory preservation")
    end
    assert(E.reset() and E.restore(pending),"roadside cargo and crew cleanup survive idle reload")
    local delivery=E.integrationFor(records[1].actor)
    for step=1,7 do I.update(delivery,records[1].actor) end
    assert(takes==0 and I.summary(delivery).stored==0 and I.summary(delivery).trunkPending==2,
        "roadside trunk stays physically intact and explicitly pending until actual marked parking")
    reset()
    started,trip=H.start(chosen,review) assert(started)
    trip.scout.vehicle.state,trip.scout.vehicle.engineStopped="abandoned",true
    trip.scout.vehicle.lastFailure={reason="fuel_empty"}
    trip.scout.phase,trip.scout.travelMode="inbound","straight"
    trip.scout.home.carSaveReceipt=clone(receipt)
    at(records[1].actor,200,200) at(records[2].actor,201,200)
    SC.Vehicle.loadedBySqlId=function() return nil end
    assert(E.finishHome() and carRestores==1 and E.lastDebrief().vehicleState=="abandoned"
        and E.lastDebrief().vehicleIssue=="fuel_empty" and #E.lastDebrief().integration.items==2,
        "far abandoned car uses persisted committed DB proof without recreating a car or losing exact trunk receipts")
    SC.Vehicle.loadedBySqlId=function(id) return id==33 and car or nil end

    do
        local abort,attach,prepare=SC.Persistence.abortRemoteArrival,
            SCSplitScreenProbe.attachRemoteArrivalVehicleSave,SCSplitScreenProbe.prepareRemoteArrival
        local previousCanStop=canStop
        local abortOkay,abortCalls=true,0
        SC.Persistence.abortRemoteArrival=function(token)
            assert(E.current().homeRelease.token==token,"abort targets the exact prepared home release")
            abortCalls=abortCalls+1
            return abortOkay and not E.current().homeRelease.committed
        end
        local function arrivedDrive()
            reset()
            local accepted,current=H.start(chosen,review) assert(accepted)
            at(records[1].actor,200,200) at(records[2].actor,201,200) at(player,200,200)
            current.scout.vehicle.state="home_wait"
            engineOff,carSaveReady,carSaveStatus=true,true,nil
            return current
        end
        trip=arrivedDrive()
        SCSplitScreenProbe.prepareRemoteArrival=function(...)
            local token=prepare(...)
            E.current().homeCarSave=nil
            return token
        end
        local commitBefore,prepareBefore=commits,prepares
        local finished,why=E.finishHome()
        assert(not finished and why=="home_car_save_pending" and abortCalls==1
            and not trip.homeRelease and not trip.integration and commits==commitBefore
            and not H.handoverOwns(records[1].actor) and trip.technicalIssue==nil,
            "missing car proof after native prepare aborts the pre-ack crew lease without detachment or stale handover ownership")
        SCSplitScreenProbe.prepareRemoteArrival=prepare
        canStop=true
        assert(H.canRecall(player) and H.cancel(player) and E.finishAtPlayer(player)
            and prepares==prepareBefore+1 and not E.lastDebrief().integration,
            "an aborted missing-proof handover can safely regroup and recall without a home cleanup obligation")

        trip=arrivedDrive()
        SCSplitScreenProbe.attachRemoteArrivalVehicleSave=function() return false end
        commitBefore,prepareBefore=commits,prepares
        finished,why=E.finishHome()
        assert(not finished and why=="home_car_save_failed" and abortCalls==2
            and not trip.homeRelease and not trip.integration and commits==commitBefore
            and H.canRecall(player) and not H.handoverOwns(records[2].actor),
            "failed car attachment releases the exact pre-ack crew lease and preserves its truthful failure reason")
        at(records[1].actor,202,200)
        SCSplitScreenProbe.attachRemoteArrivalVehicleSave=attach
        assert(E.finishHome() and prepares==prepareBefore+2 and commits==commitBefore+1
            and #E.lastDebrief().integration.items==2,
            "later car-proof recovery prepares a fresh moved crew lease and retains exact pending cargo")

        trip=arrivedDrive()
        abortOkay=false
        SCSplitScreenProbe.attachRemoteArrivalVehicleSave=function() error("injected car proof refusal") end
        commitBefore=commits
        finished,why=E.finishHome()
        local held,obligation=trip.homeRelease,trip.integration
        assert(not finished and why=="home_car_save_failed" and held and obligation
            and H.handoverOwns(records[1].actor) and commits==commitBefore,
            "failed pre-ack abort retains its exact native crew lease and obligation")
        local recall,recallReason=H.canRecall(player)
        assert(not recall and recallReason=="home_finish_busy","an unverified abort cannot release the frozen crew for recall")
        abortOkay=true
        finished,why=E.finishHome()
        assert(not finished and why=="home_car_save_failed" and not trip.homeRelease
            and not trip.integration and H.canRecall(player),
            "a later verified pre-ack abort clears only the retained failed attachment transaction")
        SCSplitScreenProbe.attachRemoteArrivalVehicleSave=attach
        assert(E.finishHome(),"a verified abort leaves the original home trip able to finish with fresh proof")

        trip=arrivedDrive()
        releaseFailure=true
        assert(not E.finishHome() and trip.homeRelease.committed,"durable fixture waits for native view teardown")
        held,obligation=trip.homeRelease,trip.integration
        local finishHome,retries=E.finishHome,0
        E.finishHome=function() retries=retries+1 return false,"durable_retry" end
        for _,record in ipairs(trip.roster) do record.actor.dead=true end
        E.pulse()
        assert(retries==1 and E.current()==trip,"an explicitly committed lease always retains its handover retry gate")
        for _,record in ipairs(trip.roster) do record.actor.dead=false end
        held.committed=false
        local detached=records[2].actor records[2].actor=nil
        E.pulse()
        assert(retries==2 and E.current()==trip,"missing detached roster actors never prove that a durable partial crew has all died")
        records[2].actor,held.committed=detached,true
        E.finishHome=finishHome
        local carProof=trip.homeCarSave
        held.carAttached,trip.homeCarSave=false,nil
        commitBefore=commits
        finished,why=E.finishHome()
        assert(not finished and why=="home_car_save_pending" and trip.homeRelease==held
            and trip.integration==obligation and H.handoverOwns(records[1].actor) and commits==commitBefore,
            "missing car proof cannot abort an already durable crew transaction or discard its exact obligation")
        held.carAttached,trip.homeCarSave=true,carProof
        assert(E.finishHome() and commits==commitBefore,"durable teardown retries its original committed roster without recapture")

        trip=arrivedDrive()
        trip.scout.vehicle.state,trip.scout.vehicle.engineStopped="abandoned",true
        abortOkay=false
        SCSplitScreenProbe.attachRemoteArrivalVehicleSave=function() return false end
        assert(not E.finishHome() and trip.homeRelease,"all-dead preack fixture retains a failed abort")
        held=trip.homeRelease
        local persistDead,releaseDead,completeDead=SCSplitScreenProbe.persistDeadLeaderSlotForReuse,
            SCSplitScreenProbe.releaseDeadLeader,SC.Persistence.completeDeadRemoteArrival
        local deadReleaseOkay,completionOkay,deadReleases,completions=false,false,0,0
        SCSplitScreenProbe.persistDeadLeaderSlotForReuse=function() return 2 end
        SCSplitScreenProbe.releaseDeadLeader=function() deadReleases=deadReleases+1 return deadReleaseOkay end
        SC.Persistence.completeDeadRemoteArrival=function(token,actors,idle)
            completions=completions+1
            assert(token==held.token and actors==held.actors and idle.state=="idle" and slot==nil and not owned,
                "dead staging completion follows exact native and Lua view closure")
            return completionOkay,"injected_dead_completion_pending"
        end
        E.pulse()
        assert(E.current()==trip and deadReleases==0,"living preack crew keeps its retained handover retry")
        for _,record in ipairs(trip.roster) do record.actor.dead=true record.actor.corpseReady=false end
        assert(not E.pulse() and E.current()==trip and deadReleases==0,
            "real all-dead preack crew reaches corpse readiness instead of the permanently failed live handover")
        for _,record in ipairs(trip.roster) do record.actor.corpseReady=true end
        corpseStageOkay=false
        assert(not E.pulse() and E.current()==trip and trip.homeRelease==held and deadReleases==0 and completions==0,
            "failed corpse retention preserves the exact preack lease and never drops pending snapshots")
        corpseStageOkay=true
        local cancelled=carCancels
        assert(not E.pulse() and E.current()==trip and deadReleases==1 and completions==0 and carCancels==cancelled,
            "failed native all-dead release retains car proof and staging authority")
        deadReleaseOkay=true
        assert(not E.pulse() and E.current()==trip and held.deadViewReleased and deadReleases==2
            and completions==1 and carCancels==cancelled+1,
            "post-view metadata failure keeps a completion retry without unloading or cancelling twice")
        completionOkay=true
        assert(E.pulse() and E.current()==nil and deadReleases==2 and completions==2 and carCancels==cancelled+1,
            "post-view retry completes exact dead staging without repeating native corpse teardown")
        SCSplitScreenProbe.persistDeadLeaderSlotForReuse,SCSplitScreenProbe.releaseDeadLeader,
            SC.Persistence.completeDeadRemoteArrival=persistDead,releaseDead,completeDead
        SC.Persistence.abortRemoteArrival,SCSplitScreenProbe.attachRemoteArrivalVehicleSave,
            SCSplitScreenProbe.prepareRemoteArrival=abort,attach,prepare
        canStop=previousCanStop
    end

    do
        reset()
        started,trip=H.start(chosen,review) assert(started)
        engineOff,carSaveReady,carSaveStatus=true,true,nil
        trip.scout.vehicle.state,trip.scout.vehicle.engineStopped="abandoned",true
        assert(H.carStopReady(trip,car) and trip.homeCarSave.ticket==66,"all-dead fixture owns a ready unattached stopped-car proof")
        for _,record in ipairs(trip.roster) do record.actor.dead,record.actor.corpseReady=true,true end
        local persistDead,releaseDead=SCSplitScreenProbe.persistDeadLeaderSlotForReuse,SCSplitScreenProbe.releaseDeadLeader
        local deadReleaseOkay=false
        SCSplitScreenProbe.persistDeadLeaderSlotForReuse=function() return 2 end
        SCSplitScreenProbe.releaseDeadLeader=function() return deadReleaseOkay end
        local cancelled=carCancels
        assert(not E.pulse() and E.current()==trip and trip.homeCarSave.ticket==66 and carCancels==cancelled,
            "failed all-dead native teardown retains the ready vehicle proof and original mission")
        deadReleaseOkay=true
        assert(E.pulse() and E.current()==nil and carCancels==cancelled+1 and trip.homeCarSave==nil,
            "successful all-dead view teardown retires its unattached car-save ticket exactly once")
        E.pulse() assert(carCancels==cancelled+1,"idle pulses cannot retire the completed all-dead vehicle proof twice")
        SCSplitScreenProbe.persistDeadLeaderSlotForReuse,SCSplitScreenProbe.releaseDeadLeader=persistDead,releaseDead
    end
    reset()
    started,trip=H.start(chosen,review) assert(started)
    at(player,100,100)
    assert(H.cancel(player) and trip.scout.home.recallStopping and trip.scout.destination.x==200,
        "near drive recall stages physical stop before changing the walking goal")
    assert(trip.scout.home.blocker=="drive_stop_pending","near recall preserves the actual physical stop failure reason")
    assert(not E.finishAtPlayer(player),"staged car recall cannot instantly close the joined view")
    canStop=true H.pulse(trip)
    assert(not trip.scout.home.recallStopping and trip.scout.home.recalling and trip.scout.vehicle.state=="abandoned"
        and trip.scout.destination.x==100,"verified stop/engine-off/unseat precede the recalled walking goal")
    assert(E.prepareReset() and E.reset())
    reset()
    started,trip=H.start(chosen,review) assert(started)
    at(player,100,100)
    carSaveReady,carSaveStatus,primaryRetained=false,"failed",true
    trip.homeCarSave={car=car,ticket=66}
    local primaryBefore=primaryChecks
    base.core.x=201
    H.pulse(trip)
    assert(not trip.scout.home.recalling and trip.homeCarSave.ticket==66 and primaryChecks==primaryBefore,
        "camp-changed stopping never invokes the explicit near-recall primary-retention exception")
    base.core.x=200
    local cancellationBefore,requestsBefore=carCancels,carRequests
    assert(H.cancel(player) and not trip.scout.home.recallStopping and trip.scout.home.recallCarPrimary
        and trip.scout.vehicle.state=="abandoned" and not trip.homeCarSave and carCancels==cancellationBefore+1,
        "explicit nearby cancellation retires an unattached failed DB ticket only after native primary retention proof")
    assert(carRequests==requestsBefore and not trip.scout.home.carSaveReceipt,
        "primary-retained recall neither invents durable car proof nor resnapshots failed remote cargo")
    local stoppedSave=E.export()
    assert(stoppedSave.scout.home.recallCarPrimary and E.prepareReset() and E.reset() and E.restore(stoppedSave)
        and E.current().scout.home.recallCarPrimary,"primary-retained recall survives actual home descriptor save/reload")
    E.pulse()
    trip=E.current()
    assert(trip and not trip.restoring and not trip.homeRecallCar,"cold restored recall binds no native car before fresh retention proof")
    local joinedBefore=joinedReleases
    at(records[2].actor,140,100)
    assert(not E.finishAtPlayer(player) and joinedReleases==joinedBefore,"primary-retained car never bypasses whole-crew regroup")
    at(records[2].actor,102,100)
    primaryRetained=false
    local finished,reason=E.finishAtPlayer(player)
    assert(not finished and reason=="home_recall_car_not_retained" and joinedReleases==joinedBefore,
        "losing actual primary car ownership blocks recalled joined release")
    local destroy=destroyPlayerData
    primaryRetained=true
    destroyPlayerData=function() primaryRetained=false end
    finished,reason=E.finishAtPlayer(player)
    assert(not finished and reason=="home_recall_car_not_retained" and joinedReleases==joinedBefore,
        "car ownership is rechecked after UI callbacks immediately before native joined release")
    destroyPlayerData=destroy primaryRetained=true
    assert(E.finishAtPlayer(player) and joinedReleases==joinedBefore+1 and not E.current()
        and E.lastDebrief().endReason=="recalled_nearby" and not E.lastDebrief().integration,
        "retained stopped car and assembled crew finish joined recall without remote durability waiver")
    SC.ExpeditionCar,SC.VehicleUnload,SC.Driving=previousCar,previousUnload,previousDriving
    SC.ViewSession.adopt=oldAdopt
    for _,name in ipairs(nativeAPIs) do SCSplitScreenProbe[name]=priorAPIs[name] end
    SC.Vehicle.loadedBySqlId,SC.Vehicle.cargoPart,SC.Vehicle.prepareDriverKeyReset,SC.Vehicle.isStationary=
        oldLoaded,oldCargo,oldKeys,oldStationary
    SC.GameplayUtil.inventoryItems,SC.GameplayUtil.itemStableId,SC.GameplayUtil.itemType,SC.GameplayUtil.inventoryContains=
        oldItems,oldId,oldType,oldContains
end
do
    reset()
    local oldEvents,oldSend,oldContext=Events,SCSplitScreenProbe.sendTestRadioWithLeaderText,
        SCSplitScreenProbe.isLeaderRadioTextContextActive
    local listener,inContext,sends,dropRequest,dropReply,changeAfterReceive=nil,false,0,false,false,nil
    local sendException=false
    local lastRequest,returnReceipts
    Events={OnDeviceText={Add=function(callback) listener=callback end,
        Remove=function(callback) assert(listener==callback) listener=nil end}}
    local function radioFor(owner)
        local data={channel=88000,power=1,range=1000,on=true,battery=true,twoWay=true,muted=false,noTransmit=false}
        function data:getChannel() return self.channel end
        function data:getPower() return self.power end
        function data:getTransmitRange() return self.range end
        function data:getIsTurnedOn() return self.on end
        function data:getHasBattery() return self.battery end
        function data:getIsTwoWay() return self.twoWay end
        function data:getMicIsMuted() return self.muted end
        function data:isNoTransmit() return self.noTransmit end
        local item={owner=owner,data=data}
        function item:getContainer() return self.owner.inventory end
        function item:getDeviceData() return self.data end
        owner.radio=item
        function owner:getEquipedRadio() return self.radio end
        function owner:getPrimaryHandItem() return self.radio end
        function owner:getSecondaryHandItem() return nil end
        function owner:getClothingItem_Back() return nil end
        return item,data
    end
    local sender,senderData=radioFor(player)
    local receiver,receiverData=radioFor(records[1].actor)
    SCSplitScreenProbe.isLeaderRadioTextContextActive=function() return inContext end
    SCSplitScreenProbe.sendTestRadioWithLeaderText=function(_,_,_,text,guid,codes)
        if sendException then error("injected native radio dispatch exception") end
        sends=sends+1
        local isRequest=string.sub(codes,1,9)=="HOME-CMD-"
        if isRequest then
            lastRequest=E.current().homeRadioRequest
            local accepted,why=H.requestRadio(player,"status",E.current().radioSession)
            assert(not accepted and why=="home_radio_busy","one real exchange retains busy ownership across its receiver callback")
        end
        if not (isRequest and dropRequest or not isRequest and dropReply) then
            inContext=true
            listener(guid,codes,0,0,0,text,isRequest and receiver or sender)
            inContext=false
            if not isRequest then returnReceipts=(returnReceipts or 0)+1 end
        end
        if isRequest and changeAfterReceive then changeAfterReceive() end
    end
    local function startRadio()
        reset()
        sender,senderData=radioFor(player)
        receiver,receiverData=radioFor(records[1].actor)
        local accepted,trip=H.start(selection) assert(accepted and trip.radioTextHooked and listener)
        return trip
    end
    local function send(trip,verb)
        assert(H.requestRadio(player,verb,trip.radioSession))
        lastRequest=trip.homeRadioRequest
        H.serviceRadio(trip)
        return H.radioState(player).lastReply
    end
    local trip=startRadio()
    assert(not H.requestRadio(player,"status","stale-trip"),"a stale card cannot target a later Home mission")
    for _,change in ipairs({function() player.radio=nil end,function() senderData.on=false end,
        function() senderData.power=0 end,function() senderData.twoWay=false end,
        function() receiverData.channel=77000 end,function() receiverData.range=1 end,
        function() receiverData.battery=false end,function() receiverData.muted=true end}) do
        sender,senderData=radioFor(player) receiver,receiverData=radioFor(records[1].actor)
        change()
        assert(not H.radioState(player).actions.status.enabled and not H.requestRadio(player,"status",trip.radioSession),
            "equipped powered two-way channel/range failures cannot enqueue a radio order")
    end
    sender,senderData=radioFor(player) receiver,receiverData=radioFor(records[1].actor)
    assert(H.requestRadio(player,"hold",trip.radioSession))
    local forged=trip.homeRadioRequest
    assert(not H.applyRadioRequest(trip,forged,player) and not trip.scout.home.radioHold,
        "a queued request without an exact native authorization cannot apply Hold")
    dropReply=true H.serviceRadio(trip) dropReply=false
    assert(not trip.scout.home.radioHold and not H.radioState(player).lastReply.acknowledged,
        "an outbound receiver receipt without a real portable return receipt cannot apply Hold")
    assert(not H.applyRadioRequest(trip,forged,player),"a completed failed receipt cannot be replayed")
    dropRequest=true
    local reply=send(trip,"hold") dropRequest=false
    assert(not reply.acknowledged and not trip.scout.home.radioHold,"missing native command receipt never mutates movement")
    assert(H.requestRadio(player,"hold",trip.radioSession))
    sender=radioFor(player)
    H.serviceRadio(trip)
    assert(not trip.scout.home.radioHold and H.radioState(player).lastReply.reason=="home_radio_stale",
        "changing the physical radio after enqueue invalidates its bound request")
    sender,senderData=radioFor(player) receiver,receiverData=radioFor(records[1].actor)
    changeAfterReceive=function() receiverData.channel=77000 end
    reply=send(trip,"hold") changeAfterReceive=nil receiverData.channel=88000
    assert(not reply.acknowledged and not trip.scout.home.radioHold,
        "channel revalidation after the native receipt refuses a stale acknowledgement")
    local function cleaned(label)
        assert(not trip.homeRadioRequest and not trip.pendingRadio and not trip.pendingReport
            and not trip.radioAuthorization and not trip.scout.home.radioHold,
            label.." releases every exact request-owned field without applying Hold")
        assert(not H.applyRadioRequest(trip,lastRequest,player),label.." discards its issued weak receipt")
    end
    sendException=true reply=send(trip,"hold") sendException=false
    assert(not reply.acknowledged) cleaned("an exception before the native request receipt")
    local originalText=getText
    getText=function() error("injected reply translation exception after request receipt") end
    reply=send(trip,"hold") getText=originalText
    assert(not reply.acknowledged) cleaned("an exception after the command receipt but before its return acknowledgement")
    local applyRadio=H.applyRadioRequest
    local ackBefore=returnReceipts or 0
    H.applyRadioRequest=function(active,request,operator)
        assert(E.radioCommandAuthorized(active.leader.actor,"home_radio",request,operator),
            "the injected post-ack exception runs inside only its exact temporary authorization")
        error("injected authorized application exception")
    end
    reply=send(trip,"hold") H.applyRadioRequest=applyRadio
    assert(not reply.acknowledged and returnReceipts==ackBefore+1)
    cleaned("an exception after the real return acknowledgement")
    local unrelatedReport={owner="unrelated report"}
    changeAfterReceive=function() trip.pendingReport=unrelatedReport end
    reply=send(trip,"status") changeAfterReceive=nil
    assert(not reply.acknowledged and trip.pendingReport==unrelatedReport
        and not trip.pendingRadio and not trip.homeRadioRequest and not trip.radioAuthorization,
        "a callback's unrelated pending report is neither overwritten by Home ACK nor erased by cleanup")
    trip.pendingReport=nil
    assert(H.requestRadio(player,"status",trip.radioSession))
    local canceledRequest=trip.homeRadioRequest
    assert(H.cancelRadio(trip) and not trip.homeRadioRequest
        and not H.applyRadioRequest(trip,canceledRequest,player),
        "explicit queued cancellation discards its exact receipt before transmission")
    assert(H.requestRadio(player,"status",trip.radioSession))
    canceledRequest=trip.homeRadioRequest
    H.reset()
    assert(not trip.homeRadioRequest and not H.applyRadioRequest(trip,canceledRequest,player),
        "module reset clears live queued fields before replacing the issued weak-receipt map")
    local before=sends
    reply=send(trip,"status")
    assert(reply.acknowledged and sends==before+2 and returnReceipts>0
        and trip.scout.home.radioReport.at==100 and trip.scout.home.radioReport.distance>0
        and trip.scout.home.radioReport.place==nil,
        "Status requires both real event directions and stores only the dated truthful Home report")
    assert(not H.radioState(player).actions.push_on.enabled,"Push on is unavailable during ordinary travel")
    reply=send(trip,"hold")
    assert(reply.acknowledged and trip.scout.home.radioHold and trip.scout.home.radioHeldAt==100
        and H.pulse(trip)==true and H.radioState(player).holding and not H.radioState(player).actions.hold.enabled,
        "an acknowledged walking Hold consumes travel without changing mission ownership")
    local held=E.export()
    assert(H.validState(held.scout.home) and held.scout.home.radioHold and held.scout.home.radioReport.state=="holding",
        "actual Home export retains acknowledged Hold and its dated report but no request authority")
    assert(H.requestRadio(player,"status",trip.radioSession))
    local queuedBeforeReset=trip.homeRadioRequest
    assert(E.prepareReset() and not trip.homeRadioRequest and E.reset()
        and not H.applyRadioRequest(trip,queuedBeforeReset,player),
        "successful world teardown/reset explicitly drops queued receipt ownership and stale authorization")
    local adopt=SC.ViewSession.adopt
    SC.ViewSession.adopt=function() return true end
    assert(E.restore(held) and E.pulse(),"an acknowledged walking radio Hold restores through the real expedition path")
    SC.ViewSession.adopt=adopt
    trip=E.current()
    assert(trip and not trip.restoring and trip.scout.home.radioHold and not trip.homeRadioRequest
        and not trip.homeRadioReply and not trip.radioAuthorization and H.radioState(player).pending==nil
        and trip.scout.home.radioReport.at==100 and H.radioState(player).actions.push_on.enabled,
        "reload preserves the dated acknowledged Hold, never queued native receipts or old call replies")
    reply=send(trip,"push_on")
    assert(reply.acknowledged and not trip.scout.home.radioHold,"an acknowledged Push on resumes a held journey")
    send(trip,"hold")
    at(player,70,75)
    assert(H.requestRadio(player,"come_back",trip.radioSession))
    at(player,72,77)
    H.serviceRadio(trip)
    assert(trip.scout.home.recalling and trip.scout.home.recallByRadio
        and trip.scout.home.recallPoint.x==70 and trip.scout.home.recallPoint.y==75
        and trip.scout.returnPoint.x==70 and not trip.homeBaseId and not trip.integration,
        "Hold then Come back uses the real call-time main position and never creates camp handover")
    local recalled=E.export()
    assert(recalled.scout.home.recallByRadio and H.validState(recalled.scout.home),
        "radio recall point and receipt-derived state survive Home persistence")
    at(records[1].actor,70,75) at(records[2].actor,110,100)
    assert(not E.finishAtPlayer(player),"radio recall cannot close the view with only one survivor assembled")
    at(records[2].actor,71,75)
    assert(E.finishAtPlayer(player) and not E.current() and E.lastDebrief().endReason=="recalled_radio"
        and not E.lastDebrief().integration and orders[records[1].actor].order=="follow"
        and orders[records[2].actor].order=="follow",
        "all unseated survivors physically rejoin the real player before Follow and solo release")
    trip=startRadio()
    at(player,75,75)
    assert(send(trip,"come_back").acknowledged)
    at(records[1].actor,76,75) at(records[2].actor,77,75)
    local joinedBeforeHold=joinedReleases
    assert(send(trip,"hold").acknowledged)
    trip.scout.phase="awaiting_player"
    assert(H.pulse(trip)==true and H.pulse(trip)==true and E.current()==trip
        and trip.scout.home.radioHold and not trip.testWaypoint and joinedReleases==joinedBeforeHold
        and records[1].actor.x==76 and records[2].actor.x==77,
        "Come back then Hold consumes walking recall pulses without movement or automatic reunion release")
    local finished,holdReason=E.finishAtPlayer(player)
    assert(not finished and holdReason=="home_radio_holding" and H.validState(E.export().scout.home),
        "even an assembled held recall refuses direct completion and persists its recall target")
    assert(send(trip,"push_on").acknowledged and not trip.scout.home.radioHold
        and trip.scout.home.recalling and trip.scout.returnPoint.x==75 and not trip.homeBaseId,
        "Push on releases a walking recall Hold without redirecting the crew to camp")
    assert(E.finishAtPlayer(player) and joinedReleases==joinedBeforeHold+1,
        "only resumed recall can complete the existing strict actual-player reunion")
    trip=startRadio()
    at(player,74,74) send(trip,"come_back") send(trip,"hold")
    at(player,90,90)
    assert(send(trip,"come_back").acknowledged and not trip.scout.home.radioHold
        and trip.scout.returnPoint.x==90 and trip.scout.returnPoint.y==90 and trip.scout.home.recalling,
        "a new Come back both retargets and resumes a held walking recall")
    at(records[1].actor,90,90) at(records[2].actor,91,90)
    assert(E.finishAtPlayer(player))
    trip=startRadio()
    send(trip,"come_back") send(trip,"hold")
    at(records[1].actor,82,82) at(records[2].actor,83,82)
    assert(H.cancel(player) and not trip.scout.home.radioHold and not trip.scout.home.recallByRadio
        and E.finishAtPlayer(player) and E.lastDebrief().endReason=="recalled_nearby",
        "an actual nearby Call off also overrides a held recall without an idempotent ignored order")
    do
        -- The real Car controller's stop/resume gates have their own harness;
        -- these adapters prove Home never skips a pending physical result.
        local oldCar,oldDriving,oldKeys=SC.ExpeditionCar,SC.Driving,SC.Vehicle.prepareDriverKeyReset
        local stopped,resumable,holds,resumes,cancels=false,false,0,0,0
        trip=startRadio()
        local car={engine=true,moving=true}
        trip.scout.vehicle={field=true,sqlId=55,state="driving_home"}
        trip.scout.home.vehicleSqlId=55
        for _,member in ipairs(trip.roster) do member.actor.vehicle=car end
        SC.ExpeditionCar={holdHome=function(active)
            assert(active==trip and records[1].actor.vehicle==car and records[2].actor.vehicle==car,
                "a driving radio Hold retains the exact chosen car and both actual seats")
            holds=holds+1
            if not stopped then return false,"drive_stop_pending" end
            car.engine,car.moving=false,false
            return true,"home_radio_holding"
        end,resumeHome=function(active)
            resumes=resumes+1
            assert(active==trip and not car.engine and not car.moving and records[1].actor.vehicle==car,
                "Push on asks the retained vehicle owner to revalidate the same physically stopped seated car")
            if not resumable then return false,"driver_needs_key" end
            car.engine,car.moving=true,true
            return true,"driving_home"
        end,cancelField=function(active)
            cancels=cancels+1
            assert(active==trip,"radio recall stops only its exact Home vehicle controller")
            if not stopped then return false,"drive_stop_pending" end
            car.engine,car.moving=false,false
            for _,member in ipairs(active.roster) do member.actor.vehicle=nil end
            active.scout.vehicle.state="abandoned"
            return true,"car_abandoned"
        end}
        SC.Driving={release=function() return true end}
        SC.Vehicle.prepareDriverKeyReset=function() return true end
        reply=send(trip,"hold")
        assert(reply.acknowledged and H.pulse(trip)==true and trip.scout.home.radioHoldStopping
            and holds==1 and records[1].actor.vehicle==car and not H.radioState(player).actions.push_on.enabled,
            "driving Hold remains pending until the actual controller proves a safe physical stop")
        stopped=true H.pulse(trip)
        assert(not trip.scout.home.radioHoldStopping and trip.scout.home.radioVehicleHold
            and not car.engine and not car.moving and records[2].actor.vehicle==car,
            "completed Hold shuts off the same car without unseating or abandoning cargo")
        reply=send(trip,"push_on")
        assert(not reply.acknowledged and trip.scout.home.radioHold and not car.engine and resumes==1,
            "a failed fresh vehicle resume check keeps the radio Hold and stopped car")
        resumable=true reply=send(trip,"push_on")
        assert(reply.acknowledged and not trip.scout.home.radioHold and car.engine and car.moving and resumes==2,
            "only accepted fresh vehicle continuation releases Hold without stranding its chosen car")
        send(trip,"hold") stopped=false H.pulse(trip)
        at(player,60,65)
        reply=send(trip,"come_back")
        assert(reply.acknowledged and trip.scout.home.recalling and trip.scout.home.recallStopping
            and records[1].actor.vehicle==car and cancels==1
            and trip.scout.returnPoint.x==base.core.x and not trip.integration,
            "Come back from a driving Hold waits for physical stopping/unseating before replacing the camp route")
        local queued,holdWhy=H.requestRadio(player,"hold",trip.radioSession)
        assert(not queued and holdWhy=="home_radio_recall_stopping"
            and H.radioState(player).actions.status.enabled and H.radioState(player).actions.come_back.enabled
            and not trip.scout.home.radioHold,
            "a driving recall truthfully refuses Hold until its safe stop and physical exit finish")
        stopped=true H.pulse(trip)
        assert(not trip.scout.home.recallStopping and trip.scout.vehicle.state=="abandoned"
            and records[1].actor.vehicle==nil and records[2].actor.vehicle==nil
            and trip.scout.returnPoint.x==60 and trip.scout.returnPoint.y==65
            and not car.engine and not car.moving and trip.scout.home.recallByRadio and not trip.integration,
            "only completed safe exit starts the snapshot-point walking recall and preserves a stopped real car")
        local resumedBefore=resumes
        assert(send(trip,"hold").acknowledged and H.pulse(trip)==true and trip.scout.home.radioHold
            and not E.finishAtPlayer(player) and not car.engine and not car.moving
            and records[1].actor.vehicle==nil and records[2].actor.vehicle==nil,
            "after a driving recall safely exits, Hold suppresses its walking continuation and completion")
        assert(send(trip,"push_on").acknowledged and trip.scout.home.recalling
            and trip.scout.returnPoint.x==60 and trip.scout.returnPoint.y==65
            and not trip.scout.home.radioHold and trip.scout.vehicle.state=="abandoned" and resumes==resumedBefore,
            "Push on resumes the recall on foot without reopening the abandoned car or camp route")
        send(trip,"hold") at(player,62,67)
        assert(send(trip,"come_back").acknowledged and not trip.scout.home.radioHold
            and trip.scout.returnPoint.x==62 and trip.scout.returnPoint.y==67 and not car.engine,
            "Come back retargets and resumes a held driving-origin recall without restarting its car")
        assert(E.prepareReset() and E.reset())
        SC.ExpeditionCar,SC.Driving,SC.Vehicle.prepareDriverKeyReset=oldCar,oldDriving,oldKeys
    end
    Events=oldEvents
    SCSplitScreenProbe.sendTestRadioWithLeaderText,SCSplitScreenProbe.isLeaderRadioTextContextActive=oldSend,oldContext
    player.radio,records[1].actor.radio=nil,nil
end
reset()
assert(E.start({records[1]},{kind="scout",destination={x=150,y=150,z=0},travelMode="straight"}),"legacy scout starts")
assert(E.current().scout.phase=="outbound" and E.export().schema~=9,"legacy scout retains outbound and prior schema")
blocked("home_view_expedition")
assert(E.prepareReset() and E.reset())
print("home_trip_harness: passed blockers, cached planning, persistence, strict surviving arrival, casualty handoff, pending handover, staged recall and legacy compatibility")
