-- SPDX-License-Identifier: MIT
-- LF-side shelter and remote-view ownership for a deceased player's followers.
local SC=SurvivorCompanion
local R={} SC.HandoverRescue=R
local nextPulse,loadingId,bootstrap,detachedUI=0,nil,nil,nil
local shelterAttempts=setmetatable({},{__mode='k'})
local function store() return ModData.getOrCreate(SC.Handover.KEY) end
local function alive(actor) return actor and not SC.GameplayUtil.isDead(actor) end
local function primary() return getSpecificPlayer(0) end
local function record(id) return SC.Registry.byId(id) end
local function flush()
    local okay,why=SC.Persistence.save(primary());if not okay then return false,why end
    return SCSplitScreenProbe.flushGlobalModDataForWorldExit()
end
local function releaseView(worldExit)
    if SC.ViewSession.owner()~='handover' then return true end
    local actor=getSpecificPlayer(1)
    if actor and destroyPlayerData and detachedUI~=actor then destroyPlayerData(actor);detachedUI=actor end
    local released
    if worldExit then released=SCSplitScreenProbe.releaseForWorldExit()
    else released=SCSplitScreenProbe.releaseHandoverView() end
    if not released then return false,'The survivor view could not be released.' end
    return SC.ViewSession.released('handover',SC.ViewSession.slotSqlId(),worldExit==true)
end
local function suspendRemote(selected)
    local world=store()
    local owner=SC.ViewSession.owner()
    if world.suspended and world.suspended.phase=='paused' then return true end
    if world.suspended then owner=world.suspended.owner end
    if owner==nil or owner=='handover' then return true end
    if owner~='expedition' and owner~='base_watch' then return false,'Finish the current pickup transfer before Handover.' end
    local api=owner=='expedition' and SC.ExpeditionPrototype or SC.BaseWatch
    if not world.suspended then
        local saved,why=api.export();if not saved then return false,why or 'The remote activity could not be saved.' end
        world.suspended={owner=owner,document=saved,phase='prepared'}
        if not flush() then world.suspended=nil;return false,'The remote activity has not been durably saved.' end
    end
    if world.suspended.phase~='retiring' then
        local ready,why=api.prepareReset();if not ready then return false,why end
        if not api.current or api.current() then
            local updated=api.export()
            if updated then world.suspended.document=updated end
        end
        world.suspended.phase='retiring'
        if not flush() then return false,'The suspended activity could not be saved.' end
    end
    local ids=owner=='expedition' and world.suspended.document.roster or {world.suspended.document.leaderId}
    for _,id in ipairs(ids or {}) do
        local current=record(id)
        if id~=selected and current and current.actor then
            local retained,reason=SC.Persistence.retainForHandover(current)
            if not retained then return false,reason end
            local removed,detail=SC.Actor.remove(current.actor);if not removed then return false,detail end
        end
    end
    local reset,reason=api.reset();if reset==false then return false,reason end
    world.suspended.phase='paused'
    return flush()
end
local function contains(ids,id)
    for _,value in ipairs(ids or {}) do if value==id then return true end end
    return false
end
local function activity()
    local suspended=store().suspended
    if suspended then return suspended.owner,suspended.document end
    local expedition=SC.ExpeditionPrototype
    if expedition and expedition.current and expedition.current() then return 'expedition',expedition.export() end
end
function R.candidateReason(id)
    local owner,saved=activity()
    if owner~='expedition' or not saved or not contains(saved.roster,id) then return end
    local scout=saved.scout
    if scout and (scout.vehicle or scout.wood or scout.fuel or scout.home) then
        return 'Finish their expedition vehicle or resource transfer before takeover.'
    end
    if saved.integration or #(saved.deliveries or {})>0 then return 'Their expedition delivery must finish before takeover.' end
    for _,row in ipairs(scout and scout.search and scout.search.acquisitions or {}) do
        if row.memberId==id then return 'Deliver their expedition cargo before takeover.' end
    end
end
local function copy(value)
    if type(value)~='table' then return value end
    local result={};for key,entry in pairs(value) do result[key]=copy(entry) end;return result
end
local function without(ids,id)
    local result={};for _,value in ipairs(ids or {}) do if value~=id then result[#result+1]=value end end;return result
end
-- Called at the same durable boundary as retirement. Preparation/cancellation
-- leaves the mission intact; a committed successor cannot rejoin its old roster.
function R.detachCandidate(id)
    local world=store();local before=world.suspended
    if not before then return nil end
    local nextState=copy(before);local saved=nextState.document
    if nextState.owner=='expedition' and contains(saved.roster,id) then
        assert(not R.candidateReason(id),'expedition inventory is still owned')
        saved.roster,saved.survivors=without(saved.roster,id),without(saved.survivors,id)
        if saved.rosterNames then saved.rosterNames[id]=nil end
        if saved.commandSerials then saved.commandSerials[id]=nil end
        if saved.leaderId==id then saved.leaderId=saved.survivors[1] end
        if not saved.leaderId or #saved.survivors==0 then nextState=nil end
    elseif nextState.owner=='base_watch' and saved.leaderId==id then
        local replacement
        for _,row in ipairs(SC.BaseWatch.candidates()) do if row.id~=id then replacement=row.id;break end end
        if replacement then saved.leaderId=replacement else nextState=nil end
    end
    world.suspended=nextState
    return before
end
function R.restoreDetached(value) store().suspended=value end
function R.prepareChoice(selected)
    local ready,why=suspendRemote(selected);if not ready then return false,why end
    local leader=getSpecificPlayer(1)
    if SC.ViewSession.owner()=='handover' and leader and SC.Registry.idOf(leader)==selected then
        local replacement
        for id in pairs(store().crew or {}) do local current=record(id)
            if id~=selected and current and alive(current.actor) and current.actor:getCurrentSquare() then replacement=current.actor;break end
        end
        if replacement then SCSplitScreenProbe.handoffLiving(replacement)
        else local released,reason=releaseView();if not released then return false,reason end end
    end
    if SC.ViewSession.owner()==nil then
        for id in pairs(store().crew or {}) do local current=record(id)
            if id~=selected and current and alive(current.actor) and current.actor:getCurrentSquare() then
                local claimed,reason=SC.ViewSession.claim('handover',current.actor)
                if not claimed then return false,reason end;break
            end
        end
    end
    SCBridge.pollHandoverPlayerAdmission()
    return true
end
function R.loadCandidate(id)
    local candidate=SC.Persistence.pendingBootstrap(id)
    if not candidate then return false,'This saved companion has an unresolved transfer or vehicle state.' end
    local ready,why=suspendRemote();if not ready then return false,why end
    if SC.ViewSession.owner()=='handover' then
        if not flush() then return false,'Survivor positions could not be saved.' end
        local released,reason=releaseView();if not released then return false,reason end
    end
    local loader,reason=SC.ViewSession.loadHandoverArea(candidate)
    if not loader then return false,reason end
    loadingId,bootstrap=id,loader;return true
end
function R.pollPreparation()
    SCBridge.pollHandoverPlayerAdmission()
    -- A loader can lose its native view during cleanup. Do not keep waiting
    -- on its stale Lua ticket after both ownership and slot have
    -- gone; the bounded rescue pulse may request the saved area again.
    if loadingId and SC.ViewSession.owner()~='handover' and getSpecificPlayer(1)~=bootstrap then
        loadingId,bootstrap=nil,nil
        return
    end
    if loadingId then
        SC.Persistence.restorePulse(primary())
        local current=record(loadingId)
        if current and alive(current.actor) and getSpecificPlayer(1)==bootstrap then
            SCSplitScreenProbe.replaceColdProbeWithRestoredLeader(current.actor,SC.ViewSession.slotSqlId() or -1)
            SC.ViewSession.adopt('handover',current.actor,SCSplitScreenProbe.leaderSqlId())
            loadingId,bootstrap=nil,nil
        end
    end
end
local function near(actor,player)
    local x,y,z=SC.GameplayUtil.position(actor);local px,py,pz=SC.GameplayUtil.position(player)
    return x and px and math.floor(z)==math.floor(pz) and (x-px)^2+(y-py)^2<=100
end
local function receiveAt(player)
    local endpoint=SC.PickupRadio.driver(player)
    if endpoint and SC.RadioEndpoints.ready(endpoint) then return endpoint end
    SC.RadioEndpoints.release(endpoint)
    local base=SC.BaseLife.active()
    local selected
    if base then for _,station in ipairs(SC.PickupRadio.stations(player,base.id)) do
        local x,y,z=SC.RadioEndpoints.origin(station);local px,py,pz=SC.GameplayUtil.position(player)
        if not selected and x and px and math.floor(z)==math.floor(pz) and (x-px)^2+(y-py)^2<=100 then selected=station
        else SC.RadioEndpoints.release(station) end
    end end
    return selected
end
local function report(actor,row,now)
    local kind=row.phase=='sheltered' and 'shelter' or 'help'
    if row.reportKind~=kind then row.reportKind,row.nextReportAt=kind,0 end
    if row[kind..'Reported'] or now<(row.nextReportAt or 0) then return end
    local source=SC.PickupRadio.driver(actor);local target=receiveAt(primary())
    R.lastReport={id=row.id,kind=kind,source=source~=nil,target=target~=nil}
    if not source or not target then SC.RadioEndpoints.release(source);SC.RadioEndpoints.release(target);return end
    row.nextReportAt=now+30000
    local x,y=SC.GameplayUtil.position(actor)
    local text=SC.GameplayUtil.nameOf(actor)..(kind=='shelter' and ': I have reached shelter near ' or ': I need help near ')
        ..math.floor(x)..', '..math.floor(y)..'. Waiting for you or a pickup.'
    local delivered,reason=SC.PickupRadio.send(source,target,text,'LF-HANDOVER-'..row.id..'-'..kind,'HANDOVER-'..kind)
    SC.RadioEndpoints.release(source);SC.RadioEndpoints.release(target)
    R.lastReport.delivered,R.lastReport.reason=delivered,reason
    if delivered then
        row[kind..'Reported']=true;row.reportedX,row.reportedY=math.floor(x),math.floor(y);primary():setHaloNote(text)
    end
end
local function shelterKey(point)
    return point and point.x..':'..point.y..':'..point.z
end
local function rejectedShelters(row,now)
    local excluded,count={},0
    for key,untilAt in pairs(row.rejectedShelters or {}) do
        if type(untilAt)=='number' and now<untilAt then excluded[key]=true;count=count+1
        else row.rejectedShelters[key]=nil end
    end
    return excluded,count
end
local function releaseShelter(actor,row,reason,now,failed)
    if failed then
        local target=row.target
        local building=target.buildingId
        if not building and SC.ExpeditionPlaces.atPoint then
            local place=SC.ExpeditionPlaces.atPoint(target);building=place and place.id
        end
        row.rejectedShelters=row.rejectedShelters or {}
        row.rejectedShelters[building or shelterKey(target)]=now+300000
        row.shelterFailures=(row.shelterFailures or 0)+1
        row.lastShelterFailure=reason
    end
    row.lastShelterReselectReason=reason
    row.target,row.phase,row.nextShelterAt=nil,'holding',now
    row.shelterActiveMs=nil
    shelterAttempts[actor]=nil
    if SC.Navigation and SC.Navigation.cancel then SC.Navigation.cancel(actor,'handover_shelter_reselect') end
end
local function rejectShelter(actor,row,reason,now) releaseShelter(actor,row,reason,now,true) end
local function pathNodes(value)
    local count=tonumber(value)
    if not count or count~=count or count<=0 then return 80 end
    return math.min(80,math.max(1,math.ceil(count)))
end
local function attemptLimit(target) return 60000+1500*pathNodes(target.pathNodes) end
local function atShelter(actor,target,x,y,z)
    local square=actor:getCurrentSquare()
    return x and square and square:getRoom() and math.floor(z)==target.z
        and (x-target.x)^2+(y-target.y)^2<=9
end
-- Only the tactical shelter controller reports these results. Combat, needs
-- and other routes must neither reject a shelter nor consume its stall budget.
function R.navigationResult(actor,target,handled,reason)
    local world=store();local row=world.crew and world.crew[SC.Registry.idOf(actor)]
    if not row or row.phase~='seeking_shelter' or not target
        or shelterKey(row.target)~=shelterKey(target) then return end
    local now=getTimestampMs()
    local x,y,z=SC.GameplayUtil.position(actor)
    if not x then return end
    if atShelter(actor,row.target,x,y,z) then row.phase='sheltered';shelterAttempts[actor]=nil;return end
    if handled~=true and (reason=='path_blocked:door_locked' or reason=='path_blocked:blocked_static'
        or reason=='shelter_unavailable'
        or type(reason)=='string' and reason:find('^recovery_exhausted:')) then
        rejectShelter(actor,row,reason,now);return
    end
    local attempt=shelterAttempts[actor]
    if not attempt or attempt.row~=row or attempt.target~=row.target then
        attempt={row=row,target=row.target,x=x,y=y,z=z,progressAt=now}
        shelterAttempts[actor]=attempt
    end
    if reason=='shelter_unloaded' then
        if not attempt.unloadedSince or now<attempt.unloadedSince then
            attempt.unloadedSince=now
            attempt.lastAt=nil
            if SC.Navigation and SC.Navigation.cancel then SC.Navigation.cancel(actor,'handover_shelter_wait_loaded') end
        end
        if now-attempt.unloadedSince>=30000 then releaseShelter(actor,row,'shelter_unloaded_timeout',now,false) end
        return
    end
    if attempt.unloadedSince then
        attempt.unloadedSince,attempt.lastAt=nil,nil
        attempt.x,attempt.y,attempt.z,attempt.progressAt=x,y,z,now
    end
    local gap=attempt.lastAt and math.max(0,now-attempt.lastAt) or 0
    local elapsed=tonumber(row.shelterActiveMs) or 0
    if elapsed~=elapsed or elapsed<0 then elapsed=0 end
    -- Keep consumed service time across movement and reloads, but never charge
    -- a long emergency/offline gap as continuous shelter work.
    row.shelterActiveMs=elapsed+math.min(gap,1000)
    if not attempt.lastAt or now<attempt.lastAt or gap>3000 then
        attempt.x,attempt.y,attempt.z,attempt.progressAt=x,y,z,now
    elseif math.floor(z)~=math.floor(attempt.z) or (x-attempt.x)^2+(y-attempt.y)^2>=.25 then
        attempt.x,attempt.y,attempt.z,attempt.progressAt=x,y,z,now
    end
    attempt.lastAt=now
    if now-attempt.progressAt>=20000 then rejectShelter(actor,row,'shelter_no_progress',now)
    elseif row.shelterActiveMs>=attemptLimit(row.target) then rejectShelter(actor,row,'shelter_attempt_timeout',now) end
end
-- Modify the decision's copy; preserve standing Follow and normal emergency control.
function R.commands(actor,player,commands)
    local id=SC.Registry.idOf(actor);local world=store();local row=world.crew and world.crew[id]
    if not row then return commands end
    if commands.order~='follow' and commands.order~='regroup' or (commands.commandSerial or 0)~=row.serial then world.crew[id]=nil;shelterAttempts[actor]=nil;return commands end
    if near(actor,player) then world.crew[id]=nil;shelterAttempts[actor]=nil;return commands end
    if (not row.target or row.phase=='holding') and getTimestampMs()>=(row.nextShelterAt or 0) then
        row.nextShelterAt=getTimestampMs()+30000
        local excluded,count=rejectedShelters(row,getTimestampMs())
        local point
        if count<8 then point=SC.ExpeditionPlaces.nearestLoadedShelter(actor,nil,excluded) end
        if point then
            row.target={x=point.x,y=point.y,z=point.z,buildingId=point.buildingId,pathNodes=pathNodes(point.pathNodes)}
            row.phase,row.shelterActiveMs='seeking_shelter',0
        else local x,y,z=SC.GameplayUtil.position(actor);row.target={x=math.floor(x),y=math.floor(y),z=math.floor(z)};row.phase='holding' end
    end
    if row.target then
        local x,y,z=SC.GameplayUtil.position(actor)
        if atShelter(actor,row.target,x,y,z) then row.phase='sheltered' end
        local copy={};for key,value in pairs(commands) do copy[key]=value end
        copy.order,copy.anchor,copy.scavenge='stay',row.target,false
        copy.handoverShelter=row.phase=='seeking_shelter'
        return copy
    end
    return commands
end
local function parkCrew(world,player)
    local dormant={}
    for id in pairs(world.crew or {}) do
        local current=record(id)
        if current and alive(current.actor) and not near(current.actor,player) then
            local retained=SC.Persistence.retainForHandover(current)
            if not retained then return false end
            dormant[#dormant+1]=current.actor
        end
    end
    if #dormant>0 and not flush() then return false end
    local released=releaseView();if not released then return false end
    for _,actor in ipairs(dormant) do
        local removed=SC.Actor.remove(actor);if not removed then return false end
    end
    return #dormant==0 or flush()
end
function R.pulse()
    local player=primary();if not alive(player) or SC.Handover.isPaused() then return end
    local now=getTimestampMs();if now<nextPulse then return end;nextPulse=now+1000
    local world=store()
    if world.suspended and world.suspended.phase~='paused' then
        local ready=suspendRemote();if not ready then return end
    end
    for id,row in pairs(world.crew or {}) do
        if SC.Handover.retired(id) then world.crew[id]=nil
        else local current=record(id)
            if current and not alive(current.actor) then world.crew[id]=nil
            elseif current and near(current.actor,player) then world.crew[id]=nil
            else
                if current and alive(current.actor) then
                    R.commands(current.actor,player,SC.Commands.peek(current.actor))
                    if world.crew[id]==row then report(current.actor,row,now) end
                elseif row.phase~='sheltered' and not loadingId and SC.ViewSession.owner()==nil then R.loadCandidate(id) end
            end
        end
    end
    R.pollPreparation()
    local any,allSheltered,missing,loadedSheltered=false,true,false,true
    for id,row in pairs(world.crew or {}) do
        any=true
        if row.phase~='sheltered' then
            allSheltered=false
            if record(id) then loadedSheltered=false else missing=true end
        end
    end
    -- One native remote slot can visit several separated groups. Park the
    -- settled group before streaming the next; the expedition stays suspended.
    if missing and loadedSheltered and not loadingId and SC.ViewSession.owner()=='handover' then
        parkCrew(world,player);return
    end
    if not any or allSheltered then
        if SC.ViewSession.owner()=='handover' then
            if not parkCrew(world,player) then return end
        end
        if world.suspended then
            local saved=world.suspended;local api=saved.owner=='expedition' and SC.ExpeditionPrototype or SC.BaseWatch
            local restored=api.restore(saved.document);if restored then world.suspended=nil;flush() end
        end
    end
end
function R.prepareReset() return releaseView(true) end
function R.suspends(owner)
    local world=store();return world.suspended~=nil and world.suspended.owner==owner
end
function R.reset()
    nextPulse,loadingId,bootstrap,detachedUI=0,nil,nil,nil
    shelterAttempts=setmetatable({},{__mode='k'})
end
return R
