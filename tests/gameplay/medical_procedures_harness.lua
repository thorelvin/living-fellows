-- SPDX-License-Identifier: MIT
local SC=LivingFellows
local M,F=SC.Medical,SC.TestMedicalProcedures
local checks=0
local function check(value,reason) checks=checks+1;assert(value,'medical procedures '..checks..': '..reason) end
do
    local native,supervisor,move,stop=SC.NativeActions,SC.ActionSupervisor,SC.GameplayUtil.move,SC.GameplayUtil.stop
    SC.NativeActions,SC.ActionSupervisor=nil,nil
    SC.GameplayUtil.move=function() return true end;SC.GameplayUtil.stop=function() return true end
    local p=F.part({bullet=true,isBandaged=true,bandageType='Base.Bandage',bandageLife=10})
    local subject=F.actor({p},{F.item('Base.Bandage'),F.item('Base.Tweezers')})
    local okay,why=M.treat(subject,subject)
    SC.NativeActions,SC.ActionSupervisor,SC.GameplayUtil.move,SC.GameplayUtil.stop=native,supervisor,move,stop
    check(okay and why=='bullet_removed' and not p.bullet and p.isBandaged,
        'covered bullet is actually removed and redressed through existing Medical.treat')
end
check(type(M.careNeed)=='function' and type(M.campCareNeed)=='function' and type(M.pendingCare)=='function',
    'core exposes read-only pinned care and shared pending proof')
local kinds={
    {'remove_bullet',{bullet=true}}, {'remove_glass',{glass=true}}, {'apply_splint',{fracture=8}},
    {'clean_burn',{burn=8,needBurnWash=true}}, {'disinfect_wound',{infectedWound=true,scratchTime=4}},
    {'bandage',{scratchTime=8}}, {'replace_bandage',{scratchTime=8,isBandaged=true,dirty=true}},
    {'remove_stitches',{stitchFlag=true,stitchTime=40}}, {'remove_splint',{splintFlag=true,fracture=0}},
}
for index,entry in ipairs(kinds) do
    local patient=F.actor({F.part(entry[2])})
    local need=M.careNeed(patient)
    check(need and need.kind==entry[1] and need.woundIndex==0,'triage selects '..entry[1])
    local same=M.careNeed(patient)
    check(same.key==need.key,'care key remains stable without native mutation')
    local camp=M.campCareNeed(patient)
    local eligible=entry[1]~='bandage' and entry[1]~='apply_splint'
    check((camp~=nil)==eligible,'camp visit eligibility follows requested procedure set for '..entry[1])
    if index<#kinds then
        local pair=F.actor({F.part(entry[2]),F.part(kinds[index+1][2])})
        check(M.careNeed(pair).kind==entry[1],'triage respects '..entry[1]..' before '..kinds[index+1][1])
    end
end
local urgent=F.actor({F.part({bullet=true,isBandaged=true}),F.part({isBleeding=true})})
check(M.careNeed(urgent).kind=='bandage' and not M.campCareNeed(urgent),
    'undressed bleeding preempts elective surgery and visiting care')
local oldNative,oldSupervisor,oldMove,oldStop=SC.NativeActions,SC.ActionSupervisor,SC.GameplayUtil.move,SC.GameplayUtil.stop
SC.NativeActions,SC.ActionSupervisor=nil,nil
SC.GameplayUtil.move=function() return true end;SC.GameplayUtil.stop=function() return true end
local fresh,tool=F.item('Base.Bandage'),F.item('Base.Tweezers')
local bullet=F.part({bullet=true,isBandaged=true,bandageType='Base.Bandage',bandageLife=10})
local patient=F.actor({bullet},{fresh,tool})
local need=M.careNeed(patient)
local okay,reason=M.treat(patient,patient,nil,{careKind=need.kind,woundIndex=need.woundIndex,careKey=need.key})
check(okay and reason=='bullet_removed' and not bullet.bullet and bullet.deepTime>0,'bullet removal creates native deep wound and verified completion')
check(not patient.inventory:contains(fresh) and patient.inventory:contains(tool) and bullet.isBandaged,
    'surgery uses exact fresh dressing and retains its exact tweezers')
local missing=F.actor({F.part({glass=true,isBandaged=true,bandageType='Base.Bandage',bandageLife=11})},{F.item('Base.Bandage')})
okay,reason=M.treat(missing,missing)
check(not okay and reason=='no_tweezers' and missing.body.parts[1].isBandaged and missing.body.parts[1].glass,
    'missing permitted tool leaves covered glass untouched without bare hands')
local one=F.item('Base.Bandage')
local burn=F.actor({F.part({burn=9,needBurnWash=true,isBandaged=true,bandageType='Base.Bandage',bandageLife=11})},{one})
okay,reason=M.treat(burn,burn)
check(not okay and reason=='no_clean_dressing_for_burn' and burn.body.parts[1].isBandaged and burn.body.parts[1].needBurnWash,
    'one clean dressing never serves both burn cleaning and reserved redress')
local clean,redress=F.item('Base.Bandage'),F.item('Base.Bandage')
burn=F.actor({F.part({burn=9,needBurnWash=true,isBandaged=true,bandageType='Base.Bandage',bandageLife=11})},{clean,redress})
okay,reason=M.treat(burn,burn)
check(okay and reason=='burn_cleaned' and not burn.body.parts[1].needBurnWash and burn.body.parts[1].isBandaged,
    'two distinct clean dressings finish native burn clean and redress')
check(not burn.inventory:contains(clean) and not burn.inventory:contains(redress) and F.count(burn.inventory,'Base.BandageDirty')==1,
    'burn wash consumes one exact native dressing into dirty output and separately applies fresh redress')
local U,P,C=SC.GameplayUtil,SC.MedicalProcedures,SC.MedicalMaintenance
local function surgery()
    local fresh,tool=F.item('Base.Bandage'),F.item('Base.Tweezers')
    local part=F.part({bullet=true,isBandaged=true,bandageType='Base.Bandage',bandageLife=12})
    return F.actor({part},{fresh,tool}),part,fresh,tool
end
for _,mode in ipairs({'empty','invalid','stale','future','unknownCounts'}) do
    local subject,part,fresh=surgery()
    local snapshot=U.actorState(subject).snapshot
    if mode=='empty' then snapshot={}
    elseif mode=='invalid' then snapshot.valid=false
    elseif mode=='stale' then snapshot.time=U.nowMs()-100000
    elseif mode=='future' then snapshot.time=U.nowMs()+1
    else snapshot.closeThreatCount=nil end
    U.actorState(subject).snapshot=snapshot
    okay,reason=M.treat(subject,subject)
    check(not okay and reason=='danger_preempted' and part.bullet and part.isBandaged and subject.inventory:contains(fresh),
        mode..' observation refuses elective native effect before undressing')
end
local distant=surgery()
local observed=U.actorState(distant).snapshot
observed.threatCount=1;observed.escapeSquares={distant.square}
check(M.isCareSnapshotSafe(distant,observed),'fresh distant threat with escape retains semi-safe care policy')
local player=SC.TestFixture.player
local priorQueue,priorPlayer=ISTimedActionQueue,getSpecificPlayer
getSpecificPlayer=function(index) return index==0 and player or nil end
for _,kind in ipairs({'ISApplyBandage','ISSplint','ISStitch','ISRemoveBullet','ISRemoveGlass','ISCleanBurn','ISDisinfect'}) do
    local subject,part,fresh=surgery()
    ISTimedActionQueue={queues={[player]={queue={{Type=kind,character=player,otherPlayer=subject}}}}}
    okay,reason=M.treat(subject,subject)
    check(not okay and reason=='player_self_care_started' and part.bullet and subject.inventory:contains(fresh),
        'queued player '..kind..' owns its companion target before native work')
end
local held,heldPart=surgery()
ISTimedActionQueue={queues={[player]={queue={{Type='HealthPanelAction',character=player,handler={panel={character=held}}}}}}}
check(M.playerSelfCareActive(held),'queued vanilla health panel handler owns its exact patient')
ISTimedActionQueue=priorQueue
M.noteReceivingCare(held,player)
okay,reason=M.treat(held,held)
check(not okay and reason=='player_self_care_started' and heldPart.bullet,'live player receiving-care hold is preserved')
M.clearReceivingCare(held)
getSpecificPlayer=priorPlayer
local visual='active'
SC.NativeActions={visualStatus=function() return visual end,clearVisual=function() end,cancelVisual=function() return true end}
for _,mode in ipairs({'needResolved','urgentBleed','lateToolProtection','lateLoan','lateDanger'}) do
    local subject,part,fresh,tool=surgery()
    okay,reason=M.treat(subject,subject)
    check(okay and M.peek(subject)~=nil,'native visual starts pinned procedure for '..mode)
    local previousProtected=SC.PersonalItems.isProtected
    if mode=='needResolved' then part.bullet=false;part.scratchTime=8
    elseif mode=='urgentBleed' then subject.body.parts[2]=F.part({isBleeding=true,scratchTime=6})
    elseif mode=='lateToolProtection' then SC.PersonalItems.isProtected=function(item,...) return item==tool or previousProtected(item,...) end
    elseif mode=='lateLoan' then tool:getModData().SC_TestLoanOwner='player'
    else U.actorState(subject).snapshot.immediateCount=1 end
    visual='completed';okay,reason=M.treat(subject,subject)
    check(not okay and (part.bulletCalls or 0)==0 and part.isBandaged and subject.inventory:contains(fresh),
        mode..' cancels exact operation without retargeting or spending fresh')
    SC.PersonalItems.isProtected=previousProtected;visual='active'
end
do
    local patient,part=surgery()
    local fresh=F.item('Base.Bandage')
    local helper=F.actor({F.part({})},{fresh,F.item('Base.Tweezers')})
    helper.square=patient.square
    local snapshot=U.actorState(patient).snapshot
    snapshot.closeThreatCount=1
    okay,reason=M.treat(helper,patient)
    check(not okay and reason=='danger_preempted' and part.bullet and part.isBandaged
        and helper.inventory:contains(fresh) and not M.peek(helper),
        'noncamp surgery refuses patient close danger even while the helper is safe')
    snapshot.closeThreatCount=0
    visual='active';okay,reason=M.treat(helper,patient)
    check(okay and M.peek(helper)~=nil,'noncamp surgery starts only after both actors are observed safe')
    snapshot.closeThreatCount=1
    visual='completed';okay,reason=M.treat(helper,patient)
    check(not okay and reason=='danger_preempted' and (part.bulletCalls or 0)==0 and part.isBandaged
        and helper.inventory:contains(fresh) and not M.peek(helper),
        'new noncamp patient danger during visual prevents native removal and preserves reserved fresh')
end
do
    local patient,part=surgery()
    patient.worldX,patient.worldY=patient.square.x+0.05,patient.square.y+0.05
    local fresh=F.item('Base.Bandage')
    local helper=F.actor({F.part({})},{fresh,F.item('Base.Tweezers')})
    helper.square=SC.TestFixture.cell:getGridSquare(patient.square.x+4,patient.square.y-4,0)
    local navigation=SC.Navigation
    local request,interactions=navigation.requestAny,navigation.interactionTargets
    local captured,query
    navigation.interactionTargets=function(actor,target,options)
        query=options;return interactions(actor,target,options)
    end
    navigation.requestAny=function(actor,targets,mode,intent)
        captured={targets=targets,intent=intent};return true,'native_pathing'
    end
    visual='active';okay,reason=M.treat(helper,patient)
    check(okay and captured and #captured.targets>0 and query.cardinalOnly==true,
        'medical approach requests cardinal goals for the actual shifted patient')
    local arrival=captured.intent.arrivalDistance
    check(arrival>0 and arrival<=0.15,'medical approach uses a tight native arrival radius')
    for _,target in ipairs(captured.targets) do
        local _,distance=U.arrived(patient,target,{targetKind='square',distance=0})
        check(distance+arrival<=(tonumber(U.config('medicalRange')) or 1.35)+0.000001,
            'every shifted-patient goal plus arrival slack lies inside exact clinical contact')
    end
    local target=captured.targets[1]
    local x,y=U.targetPosition(target,'square')
    local px,py=U.position(patient)
    local distance=math.sqrt((x-px)^2+(y-py)^2)
    helper.square=target
    helper.worldX,helper.worldY=x+arrival*(x-px)/distance,y+arrival*(y-py)/distance
    check(M.inContact(helper,patient),'the farthest permitted arrival point reaches the actual patient')
    okay,reason=M.treat(helper,patient)
    check(okay and reason=='treatment_animation_started' and M.peek(helper).phase=='bandaging',
        'a permitted medical arrival starts treatment instead of repeating arrived until timeout')
    check(part.bullet and helper.inventory:contains(fresh),'approach verification does not synthesize native surgery')
    M.cancel(helper,'fixture_complete')
    navigation.requestAny,navigation.interactionTargets=request,interactions
end
SC.NativeActions=nil
local infected=F.actor({F.part({infectedWound=true,scratchTime=8})})
local at=P.worldHours()
P.writeCare(infected,'medicalDisinfectHours',{['0']=at})
local config=U.config
for _,minimum in ipairs({0,-4,1,0/0}) do
    U.config=function(key) if key=='medicalDisinfectMinimumHours' then return minimum end return config(key) end
    check(not P.disinfectReady(infected,0,0),'configuration cannot shorten native two-game-hour repeat guard')
end
U.config=config
P.writeCare(infected,'medicalDisinfectHours',{['0']=at+1})
check(not P.disinfectReady(infected,0,0),'future durable dose time fails closed')
P.writeCare(infected,'medicalDisinfectHours',{['0']='unknown'})
check(not P.disinfectReady(infected,0,0),'unknown durable dose time fails closed')
P.writeCare(infected,'medicalDisinfectHours',{['0']=at-2})
check(P.disinfectReady(infected,0,0) and not P.disinfectReady(infected,0,0.01),'two hours and exhausted alcohol are both required')
local protectedAncestor=F.item('Base.Bag')
local child=F.item('Base.Tweezers')
local source=SC.TestFixture.inventory({child})
function source:getContainingItem() return protectedAncestor end
function protectedAncestor:getInventory() return source end
local carrier=F.actor({F.part({})},{protectedAncestor})
protectedAncestor:getModData().SC_TestLoanOwner='player'
check(not P.itemAllowed(carrier,child,false),'ancestor loan marker protects an exact nested surgical tool')
local critical,criticalPart=surgery();critical.body.health=15
okay,reason=M.treat(critical,critical)
check(okay and reason=='bullet_removed' and not criticalPart.bullet,'quiet covered low-health patient remains clinically treatable')
local asleepClean,asleepFresh=F.item('Base.Bandage',{rejectUse=true}),F.item('Base.Bandage')
local asleepPart=F.part({burn=10,needBurnWash=true,isBandaged=true,bandageType='Base.Bandage',bandageLife=10})
-- Fresh is deliberately first, so the failed cleanup is the distinct input.
local asleep=F.actor({asleepPart},{asleepFresh,asleepClean})
okay,reason=M.treat(asleep,asleep)
check(okay and reason=='medical_redress_pending' and asleepPart.burnCleanCalls==1,'pending native burn retains exact failed consumption receipt')
M.releaseActor(asleep)
local asleepDebt=M.pendingCare(asleep)
check(asleepDebt and asleepDebt.quarantined and asleepDebt.committed,
    'dormancy preserves committed proof and quarantines unavailable exact debit handles')
okay,reason=M.treat(asleep,asleep)
check(okay and asleepPart.isBandaged and asleepPart.burnCleanCalls==1 and asleepClean.useCalls==1,
    'waking actor redresses without replaying burn or unknown consumption')
check(M.pendingCare(asleep).terminalQuarantine and not M.pendingCare(asleep).active,
    'settled forensic debt releases active medical work')
local open=F.part({scratchTime=8})
asleep.body.parts[2]=open;asleep.inventory:AddItem(F.item('Base.Bandage'));M.invalidate(asleep)
okay,reason=M.treat(asleep,asleep)
check(okay and reason=='bandaged' and open.isBandaged and M.pendingCare(asleep).terminalQuarantine,
    'forensic surgery quarantine permits ordinary dressing on another body part without deleting proof')
local fracture=F.part({fracture=9})
asleep.body.parts[3]=fracture;asleep.inventory:AddItem(F.item('Base.Splint'));M.invalidate(asleep)
okay,reason=M.treat(asleep,asleep)
check(okay and reason=='splinted' and fracture.splintFlag and M.pendingCare(asleep).terminalQuarantine,
    'forensic surgery quarantine permits basic fracture splinting without overwriting proof')
local spent=F.part({splintFlag=true,fracture=0,splintItem='Base.Splint'})
local deceased=F.actor({spent});deceased.inventory.rejectAdd=true
okay,reason=M.treat(deceased,deceased)
check(okay and reason=='medical_redress_pending' and not spent.splintFlag,'native splint removal can owe only an exact material return')
deceased.dead=true;M.releaseActor(deceased);deceased.inventory.rejectAdd=false
local livingHelper=F.actor({F.part({})})
okay,reason=M.treat(livingHelper,deceased)
check(okay and reason=='splint_removed' and F.count(livingHelper.inventory,'Base.Splint')==1 and not M.pendingCare(deceased),
    'confirmed death preserves owed material and settles itemless without resurrecting removal')
SC.NativeActions,SC.ActionSupervisor,SC.GameplayUtil.move,SC.GameplayUtil.stop=oldNative,oldSupervisor,oldMove,oldStop
print('Medical procedures PASS checks='..checks)
