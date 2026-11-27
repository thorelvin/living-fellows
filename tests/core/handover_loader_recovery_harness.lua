-- SPDX-License-Identifier: MIT
local F,SC=SC_HANDOVER_TEST,LivingFellows
local H,R=SC.Handover,SC.HandoverRescue
local owner,slot,lastLoader,status,loads,releases,restoreNext
local checks=0
local function check(result,message) checks=checks+1;assert(result,message) end
function getSpecificPlayer(i) if i==0 then return F.primary elseif i==1 then return slot end end
SC.Persistence.pendingBootstrap=function(id)
    if status[id]=='quarantined' or status[id]=='spawn_pending' then return nil end
    return {id=id,x=800,y=800,z=0}
end
SC.Persistence.pendingRestoreStatus=function(id) return status[id] end
SC.Persistence.restorePulse=function()
    if restoreNext then
        local actor=F.recruit(restoreNext)
        actor.x,actor.y=800,800
        function actor:getCurrentSquare() return {getRoom=function() return {} end} end
        status[restoreNext],restoreNext=nil,nil
    end
end
SC.Persistence.retainForHandover=function() return true end
SC.Commands={peek=function() return {order='follow',commandSerial=7} end}
SC.ViewSession={owner=function() return owner end,slotSqlId=function() return 2 end,
    released=function() owner,slot=nil,nil;return true end,
    loadHandoverArea=function(point)
        check(not owner and not slot,'cold load requires a free view')
        loads[#loads+1]=point.id
        lastLoader=F.actor('loader',true);owner='handover'
        return lastLoader
    end,
    adopt=function(mode,actor)
        check(owner==mode and slot==actor,'native slot must match before adoption');return true
    end}
SCSplitScreenProbe.releaseHandoverView=function() releases=releases+1;return true end
SCSplitScreenProbe.leaderSqlId=function() return 2 end
SCSplitScreenProbe.replaceColdProbeWithRestoredLeader=function(actor)
    check(slot==lastLoader,'replace only the joined loader');slot=actor;return true
end
local function fresh()
    H.reset();R.reset()
    F.primary=F.actor('Original',false)
    F.world,F.records={},{}
    owner,slot,lastLoader,status,loads,releases,restoreNext=nil,nil,nil,{},{},0,nil
    SC.ExpeditionPrototype=nil
    F.now=F.now+100000
    F.world.SC_WorldV1={document={companions={
        one={recruited=true,identity={forename='One'},position={x=800,y=800,z=0}}
    }}}
end
local function deathAndChoice()
    fresh();F.primary.dead=true
    check(H.begin(F.primary) and H.install(),'death chooser starts')
    check(H.chooseCompanion('one') and H.current().phase=='loading','choose a real pending successor')
end
local function render(ms) F.now=F.now+ms;H._render() end
local function loseView() owner,slot=nil,nil;render(1) end
local function pulse() F.now=F.now+1001;R.pulse() end

if not SC_TEST_SHELTER_REVIEW_CASE or SC_TEST_SHELTER_REVIEW_CASE=='takeover_loader' then
    deathAndChoice();loseView()
    render(999);check(#loads==1,'retry is paced while the game is paused')
    render(1);check(#loads==2 and loads[2]=='one','lost active chooser loader retries the selected survivor')
    restoreNext='one';render(1)
    check(F.records.one and H.current().phase=='loading','registered actor waits for its native loader slot')
    slot=lastLoader;render(1)
    check(H.pendingReceipt() and H.pendingReceipt().id=='one' and H.retired('one'),'joined retry commits the chosen survivor once')

    deathAndChoice();loseView();status.one='spawn_pending'
    for i=1,12 do render(1000) end
    check(H.current().phase=='loading' and #loads==1,'a native spawn in the previously streamed area keeps its ticket')
    restoreNext='one';render(1000)
    check(H.retired('one') and #loads==1,'ordinary restore completes takeover without a duplicate loader')

    deathAndChoice()
    for attempt=1,3 do loseView();render(1000) end
    check(#loads==3 and H.isChoosing() and not H.pendingReceipt() and not H.retired('one'),
        'repeated losses reopen selection without consuming the recruit')
    check(H.startNew(true) and H.current().phase=='creating','ordinary respawn works after the failed takeover')

    deathAndChoice();slot=F.actor('foreign',true)
    render(1)
    check(H.isChoosing() and releases==0 and #loads==1,'unexpected native occupant reopens chooser without releasing it')
    local foreign=slot;F.recruit('alternate')
    check(H.chooseCompanion('alternate') and slot==foreign and releases==0,'another loaded successor leaves the foreign view alone')

    deathAndChoice();owner,slot='pickup',F.actor('pickup driver',true)
    render(1);render(1000)
    check(H.isChoosing() and owner=='pickup' and releases==0 and #loads==1,'an automatic retry never suspends a new view owner')
end

if not SC_TEST_SHELTER_REVIEW_CASE or SC_TEST_SHELTER_REVIEW_CASE=='quarantined_loader' then
    fresh();H.retired('one') -- initialize the production Handover journal
    local world=F.world.LF_HandoverV1
    world.crew.one={id='one',phase='seeking_shelter',serial=7}
    pulse();check(#loads==1 and loads[1]=='one','first cold survivor starts loading')
    world.crew.two={id='two',phase='seeking_shelter',serial=7}
    status.one='spawn_pending';slot=lastLoader
    for i=1,3 do pulse() end
    check(#loads==1 and releases==0,'an in-flight spawn is not a terminal restore')
    status.one='quarantined';pulse();pulse()
    check(releases==1 and #loads==2 and loads[2]=='two',
        'terminal first restore releases the owned view for the waiting second survivor')
    check(world.crew.one and status.one=='quarantined','quarantined crew and its restore record remain available for retry')
    slot,restoreNext=lastLoader,'two';R.pollPreparation()
    world.crew.two.phase='sheltered';world.crew.two.target={x=800,y=800,z=0};world.crew.two.shelterReported=true
    world.suspended={phase='paused',owner='expedition',document={}}
    SC.ExpeditionPrototype={restore=function() owner='expedition';return true end}
    pulse()
    check(owner=='expedition' and not world.suspended and releases==2,
        'a terminal crew member does not prevent a settled group returning its view to the suspended activity')

    deathAndChoice();slot=lastLoader;status.one='quarantined';render(1)
    check(H.isChoosing() and releases==1 and not H.pendingReceipt(),'terminal active candidate returns to the chooser')
end
SC_TEST_REPORT='HANDOVER_COLD_LOADER_PASS checks='..checks
