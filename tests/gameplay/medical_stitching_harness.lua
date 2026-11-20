-- SPDX-License-Identifier: MIT
local SC=SurvivorCompanion
local M,P,C,U,F,T=SC.Medical,SC.MedicalProcedures,SC.MedicalMaintenance,SC.GameplayUtil,SC.TestMedicalStitching,SC.TestFixture
local checks=0
local function check(value,message) checks=checks+1;assert(value,'medical stitching '..checks..': '..message) end
local native,supervisor,move,stop,randomFloat,randomInt,xp=SC.NativeActions,SC.ActionSupervisor,U.move,U.stop,ZombRandFloat,ZombRand,addXp
SC.NativeActions,SC.ActionSupervisor=nil,nil
U.move=function() return true end;U.stop=function() return true end
local randomBounds,rollBound,xpRequests
ZombRandFloat=function(low,high) randomBounds={low,high};return 3 end
ZombRand=function(limit) rollBound=limit;return 1 end
addXp=function() xpRequests=(xpRequests or 0)+1 end

for _,kit in ipairs({'thread','holder','suture'}) do
    local actor,part,fresh,consume,needle=F.patient({getStitchXp=true},kit)
    local holder=kit=='holder' and F.item('Base.SutureNeedleHolder') or nil
    if holder then actor.inventory:AddItem(holder) end
    actor.perks={[Perks.Doctor]=2}
    local need=M.careNeed(actor)
    check(need and need.kind=='stitch_wound' and M.campCareNeed(actor).key==need.key,'deep wound selects stable visiting stitch need for '..kit)
    local plan=P.prepare(actor,P.need(actor,M.assess(actor)),function(item) return item:isCanBandage() and 1 or nil end)
    check(plan and plan.durationTicks==(kit=='thread' and 192 or 142),'duration uses native kit and Doctor for '..kit)
    local okay,why=M.treat(actor,actor,nil,{careKind=need.kind,careKey=need.key,woundIndex=need.woundIndex})
    check(okay and why=='wound_stitched' and part.stitchCalls==1 and part.deepTime==0 and not part.isBleeding,
        'verified native stitch clears deep wound and bleeding for '..kit)
    check(not part.stitchWhileCovered and part.isBandaged and not actor.inventory:contains(fresh),'fresh dressing reserved before uncover and applied after '..kit)
    check(part.stitchTime==4.5 and randomBounds[1]==2 and randomBounds[2]==5 and rollBound==10,'native random/time/infection formula for '..kit)
    check(part.additionalPain==(kit=='thread' and 18 or 8) and actor.medicalXpRequested==15,'native pain and conditional XP request for '..kit)
    check(consume.useCalls==1 and (kit=='suture' and not actor.inventory:contains(consume) or kit~='suture' and consume.uses==19),
        'exact native kit input consumed once for '..kit)
    check((not needle or actor.inventory:contains(needle)) and (not holder or actor.inventory:contains(holder)), 'reusable needle and holder retained for '..kit)
    local requested=actor.medicalXpCalls[1]
    check(#actor.medicalXpCalls==1 and requested and requested.count==6 and requested[1]==Perks.Doctor
        and requested[2]==15 and requested[3]==true and requested[4]==true and requested[5]==false and requested[6]==false,
        'stitch XP uses the exact native six-argument vanilla multiplier flags for '..kit)
    check((xpRequests or 0)==0,'stitch XP bypasses only the native NPC-gated global wrapper for '..kit)
    local before=consume.useCalls
    M.treat(actor,actor)
    check(part.stitchCalls==1 and consume.useCalls==before,'finished stitched care never replays surgery or supply debit for '..kit)
    check(#actor.medicalXpCalls==1,'completed stitch never repeats the six-argument XP request for '..kit)
end

do
    local actor,part,fresh,thread=F.patient({glass=true})
    check(M.careNeed(actor).kind=='remove_glass','glass removal precedes stitching')
    local need={kind='stitch_wound',woundIndex=0,key='forced',patient=actor,wound=M.assess(actor).wounds[1]}
    local plan,why=P.prepare(actor,need,function(item) return item:isCanBandage() and 1 or nil end)
    check(not plan and why=='glass_before_stitching' and part.isBandaged and thread.useCalls==nil,'glass cannot reach a stitch plan even through explicit API')
end
for _,mode in ipairs({'noThread','noNeedle','noFresh','protectedThread','loanedNeedle','protectedFresh'}) do
    local actor,part,fresh,thread,needle=F.patient()
    local protected=SC.PersonalItems.isProtected
    if mode=='noThread' then actor.inventory:Remove(thread)
    elseif mode=='noNeedle' then actor.inventory:Remove(needle)
    elseif mode=='noFresh' then actor.inventory:Remove(fresh);actor.inventory:AddItem(F.item('Base.TShirt',{category='Clothing'}))
    elseif mode=='loanedNeedle' then needle:getModData().LF_TestLoan='player'
    else SC.PersonalItems.isProtected=function(item,...) return item==(mode=='protectedFresh' and fresh or thread) or protected(item,...) end end
    local okay,why=M.treat(actor,actor)
    check(not okay and (part.stitchCalls or 0)==0 and part.isBandaged and thread.useCalls==nil,mode..' preserves cover and exact kit')
    SC.PersonalItems.isProtected=protected
end
do
    local actor,part,fresh,thread=F.patient({rejectStitch=true})
    local okay,why=M.treat(actor,actor)
    check(not okay and why=='medical_procedure_unverified' and part.isBandaged and part.deepTime==20,
        'rejected native stitch restores the previous cover')
    check(actor.inventory:contains(fresh) and thread.useCalls==nil and not M.pendingCare(actor),'unverified native stitch consumes nothing and publishes no committed receipt')
end
for _,kind in ipairs({'thread','needle','suture','fresh'}) do
    local actor,part,fresh,consume,needle=F.patient(nil,kind=='suture' and 'suture' or 'thread')
    local chosen=kind=='needle' and needle or kind=='fresh' and fresh or consume
    chosen.favorite=true
    check(not SC.PersonalItems.isProtected(chosen,actor,'medical_consume'),'ordinary favorite has no personal marker for '..kind)
    local okay,why=M.treat(actor,actor)
    check(not okay and not part.stitchCalls and part.isBandaged and consume.useCalls==nil,
        'plain favorite '..kind..' is refused before stitching or consumption')
end
do
    local part=F.part({glass=true,isBandaged=true,bandageType='Base.Bandage',bandageLife=12})
    local fresh,tool=F.item('Base.Bandage'),F.item('Base.Tweezers',{favorite=true})
    local actor=SC.TestMedicalProcedures.actor({part},{fresh,tool})
    local okay,why=M.treat(actor,actor)
    check(not okay and why=='no_tweezers' and part.glass and part.isBandaged and actor.inventory:contains(fresh),
        'plain favorite reusable medical tool is refused without uncovering')
end
for _,mode in ipairs({'heldThread','manualThread','heldNeedle','manualNeedle','brokenNeedle','heldSuture','manualSuture','emptySuture'}) do
    local suture=string.find(mode,'Suture',1,true)~=nil
    local actor,part,fresh,consume,needle=F.patient(nil,suture and 'suture' or 'thread')
    local chosen=string.find(mode,'Needle',1,true) and needle or consume
    if string.find(mode,'held',1,true) then actor.primary=chosen
    elseif string.find(mode,'manual',1,true) then chosen:getModData().SC_ManualEquipFor='player'
    elseif mode=='brokenNeedle' then needle.condition=0
    else consume.uses=0 end
    local okay,why=M.treat(actor,actor)
    check(not okay and why=='no_stitching_kit' and not part.stitchCalls and part.isBandaged and consume.useCalls==nil,
        mode..' refuses an unusable stitching resource before uncovering')
end
do
    local actor,part=F.patient()
    local holder=F.item('Base.SutureNeedleHolder')
    actor.inventory:AddItem(holder);actor.primary=holder
    local okay,why=M.treat(actor,actor)
    check(okay and why=='wound_stitched' and part.additionalPain==20 and not holder.useCalls,
        'held optional needle holder is ignored and cannot lower stitch pain')
end
do
    local actor,part,fresh,thread=F.patient({isBandaged=false,isBleeding=true})
    check(M.careNeed(actor).kind=='bandage','undressed deep bleeding always takes priority one')
    U.actorState(actor).snapshot.immediateCount=1
    local okay=M.treat(actor,actor)
    check(not part.stitchCalls and thread.useCalls==nil,'danger never begins deep wound stitching while emergency dressing remains allowed')
    M.cancel(actor,'fixture_complete')
end
do
    local actor,part,fresh,thread=F.patient()
    U.actorState(actor).snapshot.closeThreatCount=1
    local okay,why=M.treat(actor,actor)
    check(not okay and why=='danger_preempted' and part.isBandaged and not part.stitchCalls and thread.useCalls==nil,
        'covered deep wound refuses elective stitching in close danger')
end
do
    local actor,part=F.patient({getStitchXp=false})
    local before=xpRequests
    ZombRand=function(limit) rollBound=limit;return 0 end
    local okay,why=M.treat(actor,actor)
    check(okay and why=='wound_stitched' and part.infectedWound and xpRequests==before,'native infection roll is preserved and XP false never requests gain')
    check(#actor.medicalXpCalls==0,'native six-argument XP request is omitted when isGetStitchXp is false')
    ZombRand=function(limit) rollBound=limit;return 1 end
end
do
    local patient,part,ownFresh,ownThread=F.patient()
    patient.perks={[Perks.Doctor]=1}
    local fresh,thread,needle=F.item('Base.Bandage'),F.item('Base.Thread',{drainable=true,uses=8}),F.item('Base.Needle')
    local helper=SC.TestMedicalProcedures.actor({F.part({})},{fresh,thread,needle})
    helper.perks={[Perks.Doctor]=3};helper.square=patient.square
    for _,actor in ipairs({patient,helper}) do
        T.registry[actor.id]={id=actor.id,actor=actor,recruited=true,state={personality={}},runtime={}}
        SC.Commands.peek(actor)
    end
    local snapshot=U.actorState(patient).snapshot;snapshot.allies={{actor=helper}}
    check(M.preferredStitchHelper(patient,snapshot)==helper,'free nearby companion with First Aid two higher is preferred')
    helper.perks[Perks.Doctor]=2
    check(not M.preferredStitchHelper(patient,snapshot),'one extra First Aid level does not displace self care')
    helper.perks[Perks.Doctor]=3
    SC.ActionSupervisor={current=function(actor) return actor==helper and {owner='work'} or nil end}
    check(not M.preferredStitchHelper(patient,snapshot),'another supervisor owner keeps the nearby helper busy')
    SC.ActionSupervisor=nil
    local sameGroup=M.sameCareGroup
    M.sameCareGroup=function(a,b) return a==b end
    check(not M.preferredStitchHelper(patient,snapshot),'a separate care group cannot lend its nearby medic')
    M.sameCareGroup=sameGroup
    local okay,why=M.update(patient,nil,U.actorState(patient))
    check(okay and why=='wound_stitched' and part.stitchTime==6 and part.additionalPain==17,
        'outside camp actual automatic care uses the qualified helper skill')
    check(thread.uses==7 and not helper.inventory:contains(fresh) and ownThread.useCalls==nil and patient.inventory:contains(ownFresh),
        'preferred helper spends only their exact permitted carried kit and dressing')
end

local visual='active'
SC.NativeActions={visualStatus=function() return visual end,clearVisual=function() end,cancelVisual=function() return true end}
for _,mode in ipairs({'newDanger','newPatientDanger','urgentBleed','helperUrgentBleed','resolvedNeed','lateGlass','lateLoan','lateProtection','lateFavorite',
    'lateHeld','lateManual','lateBrokenNeedle','lateEmptySuture','outOfContact','patientClaim'}) do
    local patient,part,fresh,thread,needle=F.patient(nil,mode=='lateEmptySuture' and 'suture' or 'thread')
    local helper=patient
    if mode=='newPatientDanger' or mode=='helperUrgentBleed' or mode=='outOfContact' or mode=='patientClaim' then
        patient.inventory:Remove(fresh);patient.inventory:Remove(thread)
        helper=SC.TestMedicalProcedures.actor({F.part({})},{fresh,thread,F.item('Base.Needle')})
        helper.square=patient.square
    end
    local okay,why=M.treat(helper,patient)
    check(okay and M.peek(helper),'pinned animation starts for '..mode)
    local protected=SC.PersonalItems.isProtected
    if mode=='newDanger' then U.actorState(helper).snapshot.immediateCount=1
    elseif mode=='newPatientDanger' then U.actorState(patient).snapshot.closeThreatCount=1
    elseif mode=='urgentBleed' then patient.body.parts[2]=F.part({isBleeding=true})
    elseif mode=='helperUrgentBleed' then helper.body.parts[1]=F.part({isBleeding=true,scratchTime=6})
    elseif mode=='resolvedNeed' then part.deepTime,part.deep=0,false
    elseif mode=='lateGlass' then part.glass=true
    elseif mode=='lateLoan' then thread:getModData().SC_TestLoan='player'
    elseif mode=='lateProtection' then SC.PersonalItems.isProtected=function(item,...) return item==thread or protected(item,...) end
    elseif mode=='lateFavorite' then thread.favorite=true
    elseif mode=='lateHeld' then helper.primary=thread
    elseif mode=='lateManual' then thread:getModData().SC_ManualEquipFor='player'
    elseif mode=='lateBrokenNeedle' then needle.condition=0
    elseif mode=='lateEmptySuture' then thread.uses=0
    elseif mode=='outOfContact' then helper.square=T.cell:getGridSquare(patient.square.x+4,patient.square.y,0)
    else
        M.releasePatient(helper,patient)
        local other=SC.TestMedicalProcedures.actor({F.part({})})
        M.claimPatient(other,patient)
    end
    visual='completed';okay,why=M.treat(helper,patient)
    check(not okay and not part.stitchCalls and part.isBandaged and thread.useCalls==nil,mode..' cancels pinned stitch before uncover or debit')
    SC.PersonalItems.isProtected=protected;visual='active'
end
SC.NativeActions=nil

do
    local actor,part,fresh,thread=F.patient({throwAfterStitch=true,getStitchXp=true})
    T.registry[actor.id]={id=actor.id,actor=actor,recruited=true,state={personality={}},runtime={}}
    SC.Commands.peek(actor)
    thread.rejectUse=true
    local okay,why=M.treat(actor,actor)
    check(okay and why=='medical_redress_pending' and part.stitchCalls==1 and thread.useCalls==1,'post-effect native exception preserves irreversible stitch proof and exact debt')
    local saved=P.readCare(actor,'medicalRecovery')
    check(saved and saved.kind=='stitch_wound' and saved.procedure.consumableId==thread.nativeId,'pending stitching receipt persists exact native supply identity')
    local exported=SC.Commands.export(actor)
    M.releaseActor(actor);SC.Commands.reset(actor);C.reset();P.reset()
    check(SC.Commands.restore(actor,exported),'ordinary Commands restore accepts the committed stitching receipt')
    actor.inventory:AddItem(F.item('Base.Bandage'))
    okay,why=M.treat(actor,actor)
    check(okay and part.isBandaged and part.stitchCalls==1 and thread.useCalls==1,'save boundary redresses without replaying stitch or unknown debit')
    check(#actor.medicalXpCalls==1 and saved.procedure.xpRequested==15,'save boundary retains exact stitch XP request without replay')
    local debt=M.pendingCare(actor)
    check(debt and debt.terminalQuarantine and debt.active==false,'unknown native handle becomes inactive durable forensic proof')
    actor.body.parts[2]=F.part({scratchTime=6});actor.inventory:AddItem(F.item('Base.Bandage'))
    okay,why=M.treat(actor,actor)
    check(okay and why=='bandaged' and actor.body.parts[2].isBandaged,'unknown stitching debt allows basic care after recovery')
end
do
    local actor,part,fresh,thread=F.patient({rejectStitchTime=true})
    local okay,why=M.treat(actor,actor)
    check(okay and why=='medical_procedure_unverified' and part.stitchCalls==1,'partial secondary stitch effect is quarantined without claiming success')
    M.treat(actor,actor)
    check(part.stitchCalls==1 and thread.useCalls==1,'failed stitch time never repeats the irreversible procedure')
end
do
    local actor,part,fresh,thread=F.patient()
    local care=P.careStore(actor,true)
    for index=1,512 do care['oversized'..index]=index end
    local okay,why=M.treat(actor,actor)
    check(not okay and why=='medical_recovery_unreadable' and not part.stitchCalls and part.isBandaged and thread.useCalls==nil,
        'oversized durable care rejects stitching before any uncovered or native effect')
    check(care.oversized512==512 and care.medicalRecovery==nil,'failed preflight preserves existing care metadata intact')
end
do
    -- Drive the real scored candidate, delegate and owned-visual paths. Only
    -- world services and the native animation endpoint are isolated here.
    local patient,part=F.patient()
    patient.inventory=T.inventory({})
    local fresh,thread,needle=F.item('Base.Bandage'),F.item('Base.Thread',{drainable=true,uses=8}),F.item('Base.Needle')
    local helper=SC.TestMedicalProcedures.actor({F.part({})},{fresh,thread,needle})
    helper.perks={[Perks.Doctor]=3};helper.square=patient.square
    for _,actor in ipairs({patient,helper}) do
        T.registry[actor.id]={id=actor.id,actor=actor,recruited=true,state={personality={}},runtime={}}
        SC.Commands.peek(actor)
    end
    local services={}
    for _,name in ipairs({'Positioning','Navigation','Senses','Combat','Needs','InfectionCrisis','Autonomy',
        'Encounter','Logistics','FactionBehavior','Personality','Objectives','Downtime','Dialogue','Locomotion',
        'Performance','FieldWork','MedicalVisits','BaseLife','BaseWork','FloorSort','Lighting','WorkVoice'}) do
        services[name]=SC[name];SC[name]=nil
    end
    local commands=SC.Commands
    local effective,pendingOrder=commands.effective,commands.updatePendingOrder
    local follow={recruited=true,order='follow',moveMode='walk',care={}}
    commands.effective=function() return follow end;commands.updatePendingOrder=nil
    SC.Positioning={formationTarget=function(_,leader) return leader end,shouldHold=function() return false end,
        followMode=function() return 'walk' end,playerMoveMode=function() return 'walk' end}
    SC.Navigation={request=function(actor) actor.followCalls=(actor.followCalls or 0)+1;return true,'followed' end}
    SC.ActionSupervisor=supervisor
    local phase='active'
    SC.NativeActions={visualStatus=function() return phase end,clearVisual=function() end,cancelVisual=function() return true end,
        activityStatus=function(actor) return M.peek(actor) and 'active' or 'none','visual','kneel_treat' end}
    U.stop=function(actor) actor.stopCalls=(actor.stopCalls or 0)+1;return true end
    local clockBefore=SC_TEST_CLOCK
    local patientRuntime,helperRuntime=U.actorState(patient),U.actorState(helper)
    local function refresh()
        for _,runtime in ipairs({patientRuntime,helperRuntime}) do
            runtime.snapshot={valid=true,time=U.nowMs(),threats={},immediateAttackers={},escapeSquares={},sounds={},
                threatCount=0,immediateCount=0,closeThreatCount=0,pressure=0,allies={}}
        end
        patientRuntime.snapshot.allies={{actor=helper}};helperRuntime.snapshot.allies={{actor=patient}}
    end
    local function proposals(actor,runtime)
        return SC.Decision._evaluateForTests(actor,T.player,runtime.snapshot,follow,M.assess(actor),{}, {},U.nowMs())
    end
    local function hasMedical(rows,mode)
        for _,row in ipairs(rows) do
            if row.kind=='medical' and (not mode or row.detail and row.detail.mode==mode) then return true end
        end
        return false
    end
    refresh();proposals(patient,patientRuntime)
    SC_TEST_CLOCK=SC_TEST_CLOCK+6000;refresh()
    check(not M.canReplaceDirtyBandage(patient) and M.preferredStitchHelper(patient,patientRuntime.snapshot,T.player)==helper,
        'patient without any kit has an exact capable nearby helper')
    check(hasMedical(proposals(patient,patientRuntime),'wound_care'),
        'Decision offers quiet stitching through a qualified helper when patient carries no kit')
    local okay,why
    for _=1,5 do
        okay,why=SC.Decision.update(patient,T.player,patientRuntime)
        if M.peek(helper) then break end
        SC_TEST_CLOCK=SC_TEST_CLOCK+300;refresh()
    end
    check(okay and M.peek(helper) and not M.peek(patient) and part.stitchCalls==nil,
        'actual Decision dispatch starts the helper visual for the patient without self supplies '..tostring(okay)..'/'..tostring(why))
    SC_TEST_CLOCK=SC_TEST_CLOCK+300;refresh()
    check(M.isCompanionCareHeld(patient,patientRuntime,M.assess(patient),U.nowMs()),
        'noncamp hold requires the exact active helper claim and medical owner')
    local stops=patient.stopCalls or 0
    okay,why=SC.Decision.update(patient,T.player,patientRuntime)
    check(okay and (patient.stopCalls or 0)>stops and not patient.followCalls and M.peek(helper),
        'patient Decision holds during the companion visual instead of following away')
    SC_TEST_CLOCK=SC_TEST_CLOCK+300;refresh()
    okay,why=SC.Decision.update(helper,T.player,helperRuntime)
    check(okay and M.peek(helper) and not helper.followCalls and why=='treatment_animation_active',
        'healthy helper Decision polls Medical through its generic owned native visual')
    phase='completed';SC_TEST_CLOCK=SC_TEST_CLOCK+300;refresh()
    okay,why=SC.Decision.update(helper,T.player,helperRuntime)
    check(okay and why=='wound_stitched' and part.stitchCalls==1 and thread.uses==7 and part.isBandaged and not M.peek(helper),
        'healthy helper Decision verifies and completes stitching exactly once')
    check(not M.isCompanionCareHeld(patient,patientRuntime,M.assess(patient),U.nowMs()),
        'completed exact helper owner immediately releases the noncamp patient hold')
    for _=1,5 do
        SC_TEST_CLOCK=SC_TEST_CLOCK+300;refresh()
        SC.Decision.update(helper,T.player,helperRuntime);SC.Decision.update(patient,T.player,patientRuntime)
        if helper.followCalls and patient.followCalls then break end
    end
    check((helper.followCalls or 0)>0 and (patient.followCalls or 0)>0 and part.stitchCalls==1 and thread.uses==7,
        'both Decision routes resume Follow after verified care without replay')
    -- A new elective attempt must yield to its helper's own fresh bleeding.
    part.deepTime,part.stitchTime,part.deep,part.stitchFlag=20,0,false,false
    helper.inventory:AddItem(F.item('Base.Bandage'));M.invalidate(patient)
    SC.Decision.reset(helper);SC.Decision.reset(patient)
    phase='active'
    for _=1,5 do
        SC_TEST_CLOCK=SC_TEST_CLOCK+300;refresh()
        SC.Decision.update(patient,T.player,patientRuntime)
        if M.peek(helper) then break end
    end
    check(M.peek(helper) and M.peek(helper).patient==patient,'Decision begins a second uncommitted helper stitch before own-bleeding control')
    local ownBleed=F.part({isBleeding=true,scratchTime=6})
    helper.body.parts[2]=ownBleed;M.invalidate(helper);refresh()
    check(not M.isCompanionCareHeld(patient,patientRuntime,M.assess(patient),U.nowMs()),
        'new helper undressed bleeding immediately releases the scoped patient hold')
    phase='completed';SC_TEST_CLOCK=SC_TEST_CLOCK+300;refresh()
    SC.Decision.update(helper,T.player,helperRuntime)
    check(part.stitchCalls==1 and part.deepTime==20 and thread.uses==7
        and (not M.peek(helper) or M.peek(helper).patient==helper),
        'actual healthy-helper Decision cancels uncommitted other care when helper starts bleeding')
    for _=1,5 do
        SC_TEST_CLOCK=SC_TEST_CLOCK+300;refresh()
        SC.Decision.update(helper,T.player,helperRuntime)
        if ownBleed.isBandaged then break end
    end
    check(ownBleed.isBandaged and not ownBleed.isBleeding and part.stitchCalls==1 and thread.uses==7,
        'Decision treats the helpers own urgent wound before any further elective stitch')
    SC.Decision.reset(helper);SC.Decision.reset(patient)
    commands.effective,commands.updatePendingOrder=effective,pendingOrder
    for name,value in pairs(services) do SC[name]=value end
    SC.NativeActions,SC.ActionSupervisor=nil,nil
    U.stop=stop;U.move=function() return true end
    SC_TEST_CLOCK=clockBefore
end

do
    local actor,part,fresh,thread=F.patient({getStitchXp=true})
    actor.throwAfterXp=true;thread.rejectUse=true
    local okay,why=M.treat(actor,actor)
    check(okay and why=='medical_redress_pending' and #actor.medicalXpCalls==1 and part.stitchCalls==1,
        'native XP exception leaves one published request beside the irreversible stitch')
    thread.rejectUse=false
    M.treat(actor,actor)
    check(#actor.medicalXpCalls==1 and part.stitchCalls==1,
        'exact debt recovery never repeats a native XP request that threw after effect')
end

SC.NativeActions,SC.ActionSupervisor,U.move,U.stop,ZombRandFloat,ZombRand,addXp=native,supervisor,move,stop,randomFloat,randomInt,xp
print('MEDICAL_STITCHING_PASS checks='..checks)
