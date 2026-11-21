-- SPDX-License-Identifier: MIT
local F,SC=PICKUP_RADIO,SurvivorCompanion
local R,check=SC.HandoverRescue,F.check
local world={schema=1,crew={},retired={}}
local owner,secondary,records=nil,nil,{}
local order={order='follow',commandSerial=7,recruited=true,scavenge=true}
F.clock=100000
function getTimestampMs() return F.clock end
function getSpecificPlayer(i) return i==0 and F.player or i==1 and secondary end
ModData={getOrCreate=function() return world end}
SC.Handover={KEY='LF_HandoverV1',isPaused=function() return false end,retired=function(id) return world.retired[id]~=nil end}
SC.GameplayUtil.isDead=function(a) return a.dead==true end
SC.GameplayUtil.nameOf=function() return 'Alex' end
SC.Registry={idOf=function(a) return a.id end,byId=function(id) return records[id] end}
F.driver.id='crew';records.crew={id='crew',actor=F.driver}
function F.driver:getCurrentSquare() return {getRoom=function() return F.inside and {} or nil end} end
function F.player:setHaloNote() F.halos=(F.halos or 0)+1 end
SC.Commands={peek=function() return order end}
SC.ExpeditionPlaces={nearestLoadedShelter=function(_,_,excluded)
    F.scans=(F.scans or 0)+1
    for _,point in ipairs(F.shelters or {F.shelter}) do
        local key=point.buildingId or point.x..':'..point.y..':'..point.z
        if not excluded or not excluded[key] then return point end
    end
end}
SC.ViewSession={owner=function() return owner end,slotSqlId=function() return 2 end,
    claim=function(_,actor) owner,secondary='handover',actor;return true end,
    released=function() owner,secondary=nil,nil;return true end}
SCBridge.pollHandoverPlayerAdmission=function() end
SCSplitScreenProbe={releaseForWorldExit=function() F.releases=(F.releases or 0)+1;return true end,
    releaseHandoverView=function() F.releases=(F.releases or 0)+1;return true end,
    flushGlobalModDataForWorldExit=function() F.flushed=(F.flushed or 0)+1;return true end}
SC.Persistence={save=function() return true end,pendingRestoreStatus=function() end,retainForHandover=function(current)
    F.retained=current.id;return true end,restorePulse=function() end,pendingBootstrap=function() end}
SC.Actor.remove=function(actor) F.removed=actor.id;records[actor.id]=nil;return true end
local function crew()
    world.crew.crew={id='crew',serial=7,phase='waiting',x=F.driver.x,y=F.driver.y,z=0}
    return world.crew.crew
end
if not SC_TEST_SHELTER_REVIEW_CASE then
local row=crew();F.shelter={x=802,y=803,z=0}
local copy=R.commands(F.driver,F.player,order)
check(copy~=order and copy.order=='stay' and order.order=='follow','shelter uses decision copy and preserves saved Follow')
check(copy.anchor.x==802 and row.phase=='seeking_shelter','verified shelter target drives companion-side anchor')
check(copy.handoverShelter==true,'shelter approach requires exact indoor-tile entry rather than ordinary Stay tolerance')
check(order.scavenge==true and copy.scavenge==false,'shelter preempts routine scavenging without rewriting order')
F.driver.x,F.driver.y=802,803;F.inside=true
R.commands(F.driver,F.player,order)
check(row.phase=='sheltered','shelter requires real indoor arrival')
F.player.x,F.player.y=802,803
check(R.commands(F.driver,F.player,order)==order and world.crew.crew==nil,'reunion restores original Follow')
do
    F.player.x,F.player.y=100,100;F.inside=false
    local cancelled=0
    SC.Navigation={cancel=function(actor,why)
        check(actor==F.driver and why=='handover_shelter_reselect','only the failed companion route is released')
        cancelled=cancelled+1;return true
    end}
    local a,b={x=804,y=805,z=0,buildingId='locked-house'}, {x=810,y=812,z=0,buildingId='other-house'}
    F.shelters={a,b};row=crew();R.commands(F.driver,F.player,order)
    local function result(point,handled,why)
        if R.navigationResult then R.navigationResult(F.driver,point,handled,why) end
    end
    result(a,false,'path_blocked:door_locked')
    R.commands(F.driver,F.player,order)
    check(row.target.x==b.x and row.target.buildingId==b.buildingId and cancelled==1,
        'locked shelter is rejected and a different building is selected instead of retrying forever')
    check(order.order=='follow' and order.commandSerial==7 and not row.shelterReported,
        'reselection preserves standing Follow and cannot invent an indoor arrival report')
    result(a,false,'native_path_failed')
    check(row.target.x==b.x and cancelled==1,'late failure for the old anchor cannot invalidate its replacement')
    result(b,false,'recovery_exhausted:blocked_static');R.commands(F.driver,F.player,order)
    check(row.phase=='holding' and not R.commands(F.driver,F.player,order).handoverShelter,
        'exhausted candidates hold without another invalid indoor destination')
    local scans=F.scans
    R.commands(F.driver,F.player,order)
    check(F.scans==scans,'failed shelter discovery is bounded by its retry cooldown')
    F.clock=F.clock+30001;R.commands(F.driver,F.player,order)
    check(row.phase=='holding','a failed building stays excluded across discovery retries')
    R.reset();F.clock=F.clock+30001;R.commands(F.driver,F.player,order)
    check(row.phase=='holding','saved rejection survives runtime reset')
    F.clock=F.clock+300001;R.commands(F.driver,F.player,order)
    check(row.phase=='seeking_shelter' and row.target.buildingId==a.buildingId,
        'temporary building rejection expires so a subsequently opened house can be reconsidered')
    result(a,true,'planning');F.clock=F.clock+1000;result(a,false,'blocked_by_companion')
    check(row.target~=nil,'planning and transient companion crowding do not immediately reject a shelter')
    -- Only actual route service contributes to the no-progress clock. Combat
    -- can interrupt this controller without making its shelter inaccessible.
    F.clock=F.clock+30000;result(a,true,'walking')
    check(row.target~=nil,'an interruption restarts the progress window')
    for _=1,8 do F.clock=F.clock+1000;F.driver.x=F.driver.x+.6;result(a,true,'walking') end
    check(row.target~=nil,'real companion movement keeps a shelter route alive')
    for _=1,21 do F.clock=F.clock+1000;result(a,true,'walking') end
    check(row.target==nil and row.lastShelterFailure=='shelter_no_progress',
        'a continuously serviced route that stops moving gets a bounded fallback')
    -- Old 0.27.46 saves omit the selected footprint ID.
    row=crew();row.target={x=a.x,y=a.y,z=0};row.phase='seeking_shelter'
    SC.ExpeditionPlaces.atPoint=function() return {id=a.buildingId} end
    result(a,false,'recovery_exhausted:blocked_static');R.commands(F.driver,F.player,order)
    check(row.target.buildingId==b.buildingId,'legacy saved targets resolve their failed building before reselection')
    SC.ExpeditionPlaces.atPoint=nil
    local before=cancelled;order.commandSerial=8;R.commands(F.driver,F.player,order)
    result(b,false,'native_path_failed')
    check(world.crew.crew==nil and cancelled==before,'a new player order ends rescue and ignores old route results')
    order.commandSerial=7;row=crew();F.shelters={}
    for i=1,9 do F.shelters[i]={x=820+i,y=820,z=0,buildingId='blocked-'..i} end
    for i=1,8 do
        R.commands(F.driver,F.player,order)
        check(row.target.buildingId=='blocked-'..i,'bounded fallback visits each fresh building once')
        result(row.target,false,'path_blocked:blocked_static')
    end
    local scans=F.scans;R.commands(F.driver,F.player,order)
    check(row.phase=='holding' and F.scans==scans,'eight failed buildings exhaust the bounded retry window')
    F.clock=F.clock+300001;R.commands(F.driver,F.player,order)
    check(row.target.buildingId=='blocked-1','retry window reopens after old failures expire')
    order.commandSerial=7;F.shelters=nil;SC.Navigation=nil
end
F.player.x,F.player.y=100,100;F.inside=false;F.shelter=nil;row=crew()
local scans=F.scans;R.commands(F.driver,F.player,order);R.commands(F.driver,F.player,order)
check(row.phase=='holding' and F.scans==scans+1,'missing shelter holds and bounds rescans')
F.clock=F.clock+30001;F.shelter={x=804,y=805,z=0};R.commands(F.driver,F.player,order)
check(row.phase=='seeking_shelter','shelter can be retried after cooldown')
order.commandSerial=8;R.commands(F.driver,F.player,order)
check(world.crew.crew==nil,'explicit new orders end automatic rescue')
order.commandSerial=7;row=crew();F.shelter={x=804,y=805,z=0}
local before=F.transmissions;F.receive=false;F.clock=F.clock+31000;R.pulse()
check(F.transmissions==before+1 and not row.helpReported and not F.halos,'a dropped native packet cannot become a help report')
F.receive=true;F.clock=F.clock+31000;R.pulse()
check(row.helpReported and F.halos==1,'real matching receiver acknowledges help once')
F.clock=F.clock+1001;R.pulse()
check(F.halos==1,'acknowledged help does not repeat')
F.driver.x,F.driver.y=804,805;F.inside=true;F.clock=F.clock+1001;R.pulse()
check(row.shelterReported and F.halos==2,'physical shelter arrival bypasses the help cooldown and delivers its distinct update')
F.callerRadio.data.on=false;row=crew();F.clock=F.clock+31000;before=F.transmissions;R.pulse()
check(F.transmissions==before and not row.helpReported,'unpowered receiver cannot receive magical notification')
F.callerRadio.data.on=true
world.crew={};owner='expedition'
records.expedition={id='expedition',actor={id='expedition'}}
SC.ExpeditionPrototype={export=function() return {roster={'expedition'},leaderId='expedition'} end,
    prepareReset=function() owner,secondary=nil,nil;return true end,reset=function() F.suspended=true;return true end,
    restore=function() F.resumed=true;owner='expedition';return true end}
row=crew();F.inside=false
check(R.prepareChoice()==true and F.suspended and F.retained=='expedition' and F.removed=='expedition','expedition saved and suspended before rescue owns its view')
check(world.suspended and owner=='handover','paused expedition remains in durable journal')
F.player.x,F.player.y=F.driver.x,F.driver.y;F.clock=F.clock+31000;R.pulse()
check(F.resumed and world.suspended==nil and owner=='expedition','reunion releases rescue view and resumes expedition')
check(F.releases==1,'rescue view released exactly once')
F.resumed=nil;F.player.x,F.player.y=100,100;F.inside=true
owner='expedition';row=crew();F.shelter={x=F.driver.x,y=F.driver.y,z=0}
check(R.prepareChoice()==true,'second rescue can preempt expedition')
F.clock=F.clock+31000;R.pulse()
check(row.phase=='sheltered' and F.resumed and world.suspended==nil,'expedition resumes once the separated crew reaches real shelter')
check(records.crew==nil and F.retained=='crew' and F.removed=='crew','remote shelter position is retained before planned dormancy')
owner='expedition';F.resumed=nil
records.expedition={id='expedition',actor={id='expedition'}}
local remove=SC.Actor.remove;local failures=0
SC.Actor.remove=function(actor)
    if actor.id=='expedition' and failures==0 then failures=1;return false,'injected retirement failure' end
    return remove(actor)
end
check(R.prepareChoice()==false and owner==nil and world.suspended.phase=='retiring','partial suspension retains its durable phase after the remote view has released')
check(R.prepareChoice()==true and world.suspended.phase=='paused' and records.expedition==nil,'retry finishes retirement without recapturing the partly removed mission')
SC.Actor.remove=remove
world.suspended={owner='expedition',phase='paused',document={roster={'lead','mate'},survivors={'lead','mate'},
    leaderId='lead',rosterNames={lead='Lead',mate='Mate'},commandSerials={lead=3,mate=4},scout={kind='search',search={acquisitions={}}}}}
check(R.candidateReason('lead')==nil,'an on-foot expedition recruit is eligible regardless of role')
local original=R.detachCandidate('lead');local saved=world.suspended.document
check(saved.leaderId=='mate' and #saved.roster==1 and saved.roster[1]=='mate' and saved.rosterNames.lead==nil and saved.commandSerials.lead==nil,
    'permanent takeover detaches the member and hands expedition leadership to a surviving recruit')
R.restoreDetached(original)
check(world.suspended==original and #original.document.roster==2,'failed transfer can restore its unchanged activity descriptor')
original.document.scout.search.acquisitions={{memberId='lead'}}
check(R.candidateReason('lead')~=nil and R.candidateReason('mate')==nil,'unsettled exact-owner cargo blocks only its carrier')
original.document.scout.vehicle={}
check(R.candidateReason('mate')~=nil,'vehicle ownership must settle before a mission member transfers')
original.document.scout=nil
R.detachCandidate('lead');R.detachCandidate('mate')
check(world.suspended==nil,'taking the last living member ends the empty suspended mission')
records.crew={id='crew',actor=F.driver};owner,secondary='handover',F.driver
row=crew();row.phase='sheltered';row.target={x=F.driver.x,y=F.driver.y,z=0}
world.crew.cold={id='cold',serial=7,phase='waiting'}
F.clock=F.clock+31000;R.pulse()
check(owner==nil and records.crew==nil and world.crew.cold.phase=='waiting','a sheltered remote group releases the slot so another separated group can load')
end

local function scenario(name,run)
    if SC_TEST_SHELTER_REVIEW_CASE and SC_TEST_SHELTER_REVIEW_CASE~=name then return end
    run()
end
local function context(nodes)
    R.reset();F.clock=F.clock+1000000
    world.crew,world.retired,world.suspended={},{},nil
    owner,secondary=nil,nil;records.crew={id='crew',actor=F.driver}
    F.driver.x,F.driver.y,F.player.x,F.player.y,F.inside=800,800,100,100,false
    order.order,order.commandSerial='follow',7
    local a={x=804,y=805,z=0,buildingId='first',pathNodes=nodes or 4}
    local b={x=810,y=812,z=0,buildingId='second',pathNodes=20}
    F.shelters={a,b};local row=crew();local cancelled={}
    SC.Navigation={cancel=function(actor,reason)
        check(actor==F.driver,'shelter review cancels only its companion')
        cancelled[#cancelled+1]=reason;return true
    end}
    R.commands(F.driver,F.player,order)
    local function result(handled,reason,advance,moving)
        F.clock=F.clock+(advance or 0)
        if moving then F.driver.x=F.driver.x==800 and 801 or 800 end
        R.navigationResult(F.driver,row.target,handled,reason)
    end
    return row,a,b,result,cancelled
end
scenario('terminal',function()
    for _,reason in ipairs({'path_blocked:door_locked','path_blocked:blocked_static','recovery_exhausted:blocked_static'}) do
        local row,a,b,result=context()
        result(false,reason)
        check(row.target==nil and row.shelterFailures==1 and row.lastShelterFailure==reason,
            'real navigation terminal reason rejects immediately: '..reason)
        check(row.rejectedShelters.first==F.clock+300000,'terminal rejection retains the five-minute exclusion')
        R.commands(F.driver,F.player,order)
        check(row.target.buildingId==b.buildingId,'terminal reason selects a different loaded house')
    end
    for _,reason in ipairs({'path_blocked:drag_unverified_native_edge','path_blocked:cross_floor_dragging','planning'}) do
        local row,a,b,result=context();result(false,reason)
        check(row.target and not row.shelterFailures,'unrelated path prefixes do not reject a shelter: '..reason)
    end
end)
scenario('transient',function()
    for _,reason in ipairs({'native_path_failed','native_path_timeout','native_path_stalled'}) do
        local row,a,b,result=context();result(false,reason)
        check(row.target and not row.shelterFailures and not row.rejectedShelters,
            'one native step failure keeps the reachable shelter: '..reason)
        result(true,'walking',1000,true)
        check(row.target.buildingId==a.buildingId,'movement after native recovery keeps the original house')
        for _=1,21 do if row.target then result(false,reason,1000) end end
        check(row.target==nil and row.lastShelterFailure=='shelter_no_progress',
            'repeated native failures without movement are bounded by no progress')
    end
end)
scenario('unloaded',function()
    local row,a,b,result,cancelled=context()
    result(true,'shelter_unloaded')
    local scans=F.scans
    check(row.target and not row.shelterFailures and not row.rejectedShelters,
        'unloaded target enters grace without a failure or exclusion')
    for _=1,29 do result(true,'shelter_unloaded',1000);R.commands(F.driver,F.player,order) end
    check(row.target and #cancelled==1 and cancelled[1]=='handover_shelter_wait_loaded' and F.scans==scans,
        'streaming grace holds the same target and cancels its route only once')
    F.shelters={b};result(true,'shelter_unloaded',1000)
    check(row.target==nil and row.lastShelterReselectReason=='shelter_unloaded_timeout',
        'repeated unloaded observations cannot renew the thirty-second grace')
    check(not row.shelterFailures and not row.rejectedShelters,'streaming expiry is not evidence of a bad house')
    R.commands(F.driver,F.player,order)
    check(row.target.buildingId==b.buildingId,'streaming expiry reselects a loaded alternative')
end)
scenario('streaming_interruptions',function()
    local row,a,b,result=context()
    for _=1,30 do
        result(true,'shelter_unloaded',1000)
        result(true,'path_searching',1000)
    end
    check(row.target and row.target.buildingId==a.buildingId and row.shelterActiveMs==0,
        'intermittent streaming does not spend the walking budget')
    F.shelters={b}
    result(true,'shelter_unloaded',1000)
    check(row.target==nil and row.lastShelterReselectReason=='shelter_unloaded_timeout',
        'one loaded observation between waits cannot renew the streaming allowance')
    check(not row.shelterFailures and not row.rejectedShelters,'intermittent streaming never bans the house')
    R.commands(F.driver,F.player,order)
    check(row.target.buildingId==b.buildingId,'intermittent streaming releases the follower to a loaded house')

    row,a,b,result=context(80)
    result(true,'shelter_unloaded')
    result(true,'walking',1000,true)
    for _=1,35 do result(true,'walking',1000,true) end
    result(true,'shelter_unloaded',1000)
    result(true,'shelter_unloaded',28000)
    check(row.target and row.shelterActiveMs==35000,'loaded walking time does not spend streaming grace')
    F.driver.x,F.driver.y,F.inside=a.x,a.y,true
    result(true,'arrived',1000)
    check(row.phase=='sheltered' and not row.shelterFailures,'an intermittently loaded house can still be reached')

    row,a,b,result=context()
    result(true,'shelter_unloaded')
    result(true,'walking',300000,true)
    result(true,'shelter_unloaded',1000)
    check(row.target and row.target.buildingId==a.buildingId,
        'an emergency gap ending with a loaded square cannot exhaust the next streaming wait')
end)
scenario('reload',function()
    local row,a,b,result=context(80)
    row.shelterActiveMs=12000
    row.target={x=a.x,y=a.y,z=a.z,buildingId=a.buildingId,pathNodes=80}
    R.reset();F.clock=F.clock+300000
    result(true,'shelter_unloaded')
    check(row.target.buildingId==a.buildingId and row.shelterActiveMs==12000,
        'saved seeking target receives fresh streaming grace without consuming offline time')
    result(true,'shelter_unloaded',5000)
    result(true,'walking',1000,true)
    check(row.target.buildingId==a.buildingId and not row.shelterFailures and row.shelterActiveMs==12000,
        'loading the saved target resumes the same house and saved attempt budget')
    result(true,'walking',1000,true)
    check(row.shelterActiveMs==13000,'restored route continues its consumed service budget')
end)
scenario('loop',function()
    local row,a,b,result=context(4)
    check(row.target.pathNodes==4,'selected path node count survives on the rescue target')
    result(true,'walking')
    for _=1,65 do result(true,'walking',1000,true) end
    check(row.target~=nil,'moving detour remains valid before its route-based deadline')
    result(true,'walking',1000,true)
    check(row.target==nil and row.lastShelterFailure=='shelter_attempt_timeout',
        'a continuously moving loop expires at the overall route deadline')
end)
scenario('cap',function()
    local row,a,b,result=context(80)
    row.target.pathNodes=1000000
    result(true,'walking')
    for _=1,179 do result(true,'walking',1000,true) end
    check(row.target~=nil,'long routes retain their conservative three-minute allowance')
    result(true,'walking',1000,true)
    check(row.target==nil and row.lastShelterFailure=='shelter_attempt_timeout','malformed path metadata cannot create an unbounded attempt')
end)
scenario('interrupt',function()
    local row,a,b,result=context(80)
    result(true,'walking')
    for _=1,20 do result(true,'walking',1000,true) end
    result(true,'walking',300000,true)
    check(row.target and row.shelterActiveMs==21000,'long emergency interruption counts at most one new service slice')
    R.reset();result(true,'walking',300000,true)
    check(row.shelterActiveMs==21000,'runtime reset retains consumed budget without charging offline time')
    result(true,'shelter_unloaded',1000)
    result(true,'shelter_unloaded',29000)
    result(true,'walking',1000,true)
    check(row.target and row.shelterActiveMs==21000,'unloaded wait contributes no active route budget')
end)
scenario('arrival',function()
    local row,a,b,result=context(80)
    result(true,'walking')
    for _=1,100 do result(true,'walking',1000,true) end
    check(row.target~=nil,'long legitimate detours are not judged by distance to the house')
    row.shelterActiveMs=180000
    F.driver.x,F.driver.y,F.inside=a.x,a.y,true
    result(true,'arrived',1000)
    R.commands(F.driver,F.player,order)
    check(row.phase=='sheltered' and not row.shelterFailures,'physical indoor arrival wins over deadline expiry')
end)
scenario('loader',function()
    context();records.crew=nil
    SC.Persistence.pendingBootstrap=function(id) return {id=id,x=800,y=800,z=0} end
    local loads=0
    SC.ViewSession.loadHandoverArea=function()
        loads=loads+1;owner='handover';return {}
    end
    check(R.loadCandidate('crew')==true,'rescue starts a real pending area load')
    for _=1,3 do F.clock=F.clock+1001;R.pollPreparation();R.pulse() end
    check(loads==1 and owner=='handover','a still-owned pending loader is not restarted while its native slot is joining')
    owner,secondary=nil,nil
    R.pollPreparation();F.clock=F.clock+1001;R.pulse()
    check(loads==2 and owner=='handover','lost startup loader ownership permits the saved seeking area to load again')
    owner,secondary='expedition',{}
    R.pollPreparation();F.clock=F.clock+1001;R.pulse()
    check(loads==2 and owner=='expedition','rescue retry never releases or replaces another view owner')
end)
SC_TEST_REPORT='HANDOVER_RESCUE_PASS checks='..F.checks
