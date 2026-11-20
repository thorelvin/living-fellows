-- SPDX-License-Identifier: MIT
-- Shipping Phase 3 owner/visual/commit acceptance on real disposable companions.
local Probe={}
local function refresh(s,actor,check)
    local SC=SurvivorCompanion;local runtime=SC.GameplayUtil.actorState(actor)
    local observed=SC.Senses.snapshot(actor,s.primary,runtime)
    check(type(observed)=='table' and observed.valid==true,'Phase3 observes actual loaded world')
    check(SC.Medical.canTreatNow(actor,observed),'Phase3 actual world is semi-safe')
    return runtime
end
local function clear(actor)
    local SC=SurvivorCompanion
    actor:getBodyDamage():RestoreToFullHealth();actor:setPainEffect(0);actor:setPainDelta(0)
    actor:getBodyDamage():setPainReduction(0);actor:setReduceInfectionPower(0)
    local stats=actor:getStats()
    for _,stat in ipairs({CharacterStat.HUNGER,CharacterStat.THIRST,CharacterStat.FATIGUE,CharacterStat.PAIN}) do stats:set(stat,0) end
    stats:set(CharacterStat.ENDURANCE,1)
    for _,entry in ipairs(assert(SC.BandageWash.inventoryEntries(actor))) do
        if SC.Medical.dressingRank(entry.item,true) or entry.item:getFluidContainer()
            or ({['Base.Needle']=true,['Base.Thread']=true,['Base.SutureNeedle']=true,
                ['Base.SutureNeedleHolder']=true,['Base.Pills']=true,['Base.Antibiotics']=true,['Base.AlcoholWipes']=true})[entry.item:getFullType()] then
            entry.source:Remove(entry.item)
        end
    end
    SC.Medical.invalidate(actor)
end
local function wound(actor,glass)
    local part=actor:getBodyDamage():getBodyPart(BodyPartType.Foot_R)
    part:setDeepWounded(true);part:setDeepWoundTime(15);part:setBleeding(false);part:setBleedingTime(0)
    part:setHaveGlass(glass==true);part:setGetStitchXp(true);part:setAdditionalPain(0)
    part:setBandaged(true,15,false,'Base.Bandage')
    SurvivorCompanion.Medical.invalidate(actor)
    return part
end
local function protect(actor,item,check)
    local P=SurvivorCompanion.PersonalItems
    check(P.restoreMarker(item,{ownerId='phase3-native-control',key='phase3-native-protected',kind='medical'},true),'native protected supply marker is authoritative')
    check(P.isProtected(item,actor,'medical_consume'),'native marked supply is protected')
end
local function options(need,extra)
    local out={careKind=need.kind,woundIndex=need.woundIndex,careKey=need.key}
    for key,value in pairs(extra or {}) do out[key]=value end
    return out
end
local function setupStitch(s,check,helper,patient,kind)
    local SC,M=SurvivorCompanion,SurvivorCompanion.Medical
    clear(patient);if helper~=patient then clear(helper) end
    local root=helper:getInventory();local part=wound(patient)
    local fresh=assert(root:AddItem('Base.Bandage'))
    local needle=assert(root:AddItem(kind=='thread' and 'Base.Needle' or 'Base.SutureNeedle'))
    local consumable=kind=='thread' and assert(root:AddItem('Base.Thread')) or needle
    local need=M.careNeed(patient,nil,{helper=helper})
    check(need and need.kind=='stitch_wound','shipping native selector picks stitch before ordinary dressing')
    return {helper=helper,patient=patient,part=part,fresh=fresh,needle=needle,consumable=consumable,
        uses=consumable:getCurrentUses(),kind=kind,options=options(need),xpBefore=helper:getXp():getXP(Perks.Doctor)}
end
local function drive(s,row,check)
    local SC,M=SurvivorCompanion,SurvivorCompanion.Medical
    refresh(s,row.patient,check)
    return M.treat(row.helper,row.patient,refresh(s,row.helper,check),row.options)
end
local function painSetup(s,check)
    local actor=s.actor;local parts=actor:getBodyDamage():getBodyParts()
    for i=0,parts:size()-1 do parts:get(i):setAdditionalPain(20) end
    actor:getStats():set(CharacterStat.PAIN,65)
    SurvivorCompanion.Medical.invalidate(actor)
end
function Probe.step(s,check,note,phase)
    local SC,M,P,N=SurvivorCompanion,SurvivorCompanion.Medical,SurvivorCompanion.MedicalProcedures,SurvivorCompanion.NativeActions
    local now=getTimestampMs()
    if s.phase=='acceptance-phase3-start' then
        clear(s.actor);clear(s.helper);clear(s.control)
        for _,actor in ipairs({s.actor,s.helper,s.control}) do SC.Commands.peek(actor).order='stay' end
        for _,kind in ipairs({'take_painkillers','take_antibiotics'}) do
            local plan,why=SC.MedicalMedicines.prepare(s.helper,s.primary,{kind=kind},{disinfectantAvailable=false})
            check(not plan and why=='player_takes_own_medicine','native player medicine is refused before stock or effects')
        end
        s.phase3={doseReceipts={},doseCount=0};phase('acceptance-phase3-refusals')
    elseif s.phase=='acceptance-phase3-refusals' then
        local actor,root=s.actor,s.actor:getInventory();local part=wound(actor,true)
        local fresh=assert(root:AddItem('Base.Bandage'));local needle=assert(root:AddItem('Base.SutureNeedle'))
        local need=M.careNeed(actor)
        check(need and need.kind=='remove_glass','native glass precedes stitching')
        local okay,why=M.treat(actor,actor,refresh(s,actor,check),{careKind='stitch_wound'})
        check(not okay and not M.peek(actor) and part:haveGlass() and part:getDeepWoundTime()>0,'shipping glass refusal keeps native wound and covering')
        check(root:contains(fresh) and root:contains(needle),'glass refusal keeps exact kit and dressing')
        clear(actor);part=wound(actor);fresh=assert(root:AddItem('Base.Bandage'))
        need=M.careNeed(actor);check(need and need.kind=='stitch_wound','deep native wound without glass requests stitching')
        okay,why=M.treat(actor,actor,refresh(s,actor,check),options(need))
        check(not okay and why=='no_stitching_kit' and not M.peek(actor),'shipping refuses missing stitching kit')
        needle=assert(root:AddItem('Base.SutureNeedle'));protect(actor,needle,check)
        okay,why=M.treat(actor,actor,refresh(s,actor,check),options(need))
        check(not okay and why=='no_stitching_kit' and part:bandaged() and root:contains(fresh) and root:contains(needle),'shipping refuses protected stitching kit without uncovering')
        s.phase3.row=setupStitch(s,check,actor,actor,'thread')
        okay,why=drive(s,s.phase3.row,check)
        check(okay and M.peek(actor),'shipping native stitch visual starts before cancellation: '..tostring(why))
        M.cancel(actor,'native_phase3_precommit_cancel');phase('acceptance-phase3-cancel')
    elseif s.phase=='acceptance-phase3-cancel' then
        local row=s.phase3.row
        if M.peek(row.helper) then check(now-s.at<20000,'native Phase3 cancellation settles');M.cancel(row.helper,'native_phase3_precommit_cancel');return end
        check(row.part:bandaged() and row.part:getDeepWoundTime()>0 and row.part:getStitchTime()==0,'precommit native stitch cancellation preserves original covering and wound')
        check(row.helper:getInventory():contains(row.fresh) and row.consumable:getCurrentUses()==row.uses,'precommit cancellation spends no exact native supplies')
        check(M.pendingCare(row.patient)==nil and M.treatmentHolder(row.patient)==nil,'precommit cancellation releases exact patient and receipt')
        note('production_stitch_refusals=glass,missing_kit,protected_kit,precommit_cancel; native_body_and_stock_untouched=true')
        phase('acceptance-phase3-thread-setup')
    elseif s.phase=='acceptance-phase3-thread-setup' or s.phase=='acceptance-phase3-suture-setup' then
        if N.pacingStatus(s.actor) or N.pacingStatus(s.helper) then check(now-s.at<30000,'prior Phase3 native pacing settles');return end
        local kind=s.phase=='acceptance-phase3-thread-setup' and 'thread' or 'suture'
        s.phase3.row=setupStitch(s,check,kind=='thread' and s.actor or s.helper,s.actor,kind)
        local okay,why=drive(s,s.phase3.row,check)
        check(okay and M.peek(s.phase3.row.helper),'shipping '..kind..' stitch native visual starts: '..tostring(why))
        phase('acceptance-phase3-stitch-running')
    elseif s.phase=='acceptance-phase3-stitch-running' then
        local row=s.phase3.row
        check(now-s.at<65000,'shipping native stitching finishes within bound')
        local okay,why=drive(s,row,check)
        if M.peek(row.helper) then check(okay,'shipping stitch keeps claimed owner: '..tostring(why));return end
        check(okay and why=='wound_stitched','shipping native stitch reports verified success: '..tostring(why))
        check(row.part:bandaged() and row.part:getStitchTime()>0 and row.part:getDeepWoundTime()==0 and row.part:getBleedingTime()==0,'shipping stitch clears real deep wound and bleeding under fresh covering')
        check(not row.helper:getInventory():contains(row.fresh),'shipping stitch consumes reserved exact fresh dressing')
        if row.kind=='thread' then
            check(row.consumable:getCurrentUses()==row.uses-1 and row.helper:getInventory():contains(row.needle),'shipping exact thread use is one; needle retained')
        else check(not row.helper:getInventory():contains(row.consumable),'shipping exact suture needle consumed once') end
        check(M.pendingCare(row.patient)==nil and M.treatmentHolder(row.patient)==nil,'successful native stitch settles receipt and patient claim')
        check(row.helper:getXp():getXP(Perks.Doctor)>row.xpBefore and row.helper:isLocalPlayer()==false,
            'shipping stitch awards real normally scaled First Aid to exact nonlocal helper')
        note('production_stitch='..row.kind..'; helper='..P.actorId(row.helper)..'; patient='..P.actorId(row.patient)
            ..'; stitch_time='..row.part:getStitchTime()..'; pain='..row.part:getAdditionalPain()..'; xp_actual='..(row.helper:getXp():getXP(Perks.Doctor)-row.xpBefore))
        if row.kind=='thread' then phase('acceptance-phase3-suture-setup') else
            row.part:setInfectedWound(false);row.part:setWoundInfectionLevel(0);row.part:setStitchTime(45)
            s.actor:setPainEffect(0);s.actor:setPainDelta(0);s.actor:getStats():set(CharacterStat.PAIN,0)
            M.invalidate(s.actor);phase('acceptance-phase3-remove-setup')
        end
    elseif s.phase=='acceptance-phase3-remove-setup' then
        if N.pacingStatus(s.actor) or N.pacingStatus(s.helper) then check(now-s.at<30000,'stitch cycle pacing settles');return end
        local row=s.phase3.row
        row.helper=s.actor;row.fresh=assert(s.actor:getInventory():AddItem('Base.Bandage'))
        local need=M.careNeed(s.actor)
        check(need and need.kind=='remove_stitches','shipping ready stitched native wound enters inherited removal cycle')
        row.options=options(need)
        local okay,why=drive(s,row,check)
        check(okay and M.peek(row.helper),'shipping cycle starts inherited stitch removal: '..tostring(why))
        phase('acceptance-phase3-remove-running')
    elseif s.phase=='acceptance-phase3-remove-running' then
        local row=s.phase3.row;check(now-s.at<65000,'shipping native stitch removal finishes')
        local okay,why=drive(s,row,check)
        if M.peek(row.helper) then check(okay,'native stitch removal keeps owner: '..tostring(why));return end
        check(okay and why=='stitches_removed' and row.part:getStitchTime()==0 and row.part:getDeepWoundTime()==0 and row.part:getScratchTime()>0,'Phase3 stitch cycle ends with inherited native healed removal')
        note('production_stitch_cycle=created_stitches_then_native45_ready_removal; deep_wound_not_reopened=true')
        phase('acceptance-phase3-pain-setup')
    elseif s.phase=='acceptance-phase3-pain-setup' then
        if N.pacingStatus(s.actor) then check(now-s.at<30000,'medical cycle pacing settles before medicine');return end
        clear(s.actor);clear(s.helper)
        P.writeCare(s.actor,'medicalMedicineState',nil);P.writeCare(s.actor,'medicalMedicineRecovery',nil)
        s.phase3.pills=assert(s.actor:getInventory():AddItem('Base.Pills'))
        s.phase3.pillUses=s.phase3.pills:getCurrentUses()
        local need=M.careNeed(s.actor)
        check(not need or need.kind~='take_painkillers','native Pain below2 never requests pills')
        painSetup(s,check);phase('acceptance-phase3-pain-ready')
    elseif s.phase=='acceptance-phase3-pain-ready' then
        if now-s.at<5500 then return end
        local need=M.careNeed(s.actor)
        local ledger=P.readCare(s.actor,'medicalMedicineState')
        if ledger and ledger.painCount==4 then
            local uses=s.phase3.pills:getCurrentUses()
            local record=assert(SC.Registry.byId(SC.GameplayUtil.idOf(s.actor)))
            local captured,captureReason=SC.Persistence.captureRecord(record)
            check(captured and captured.personality and captured.personality.care
                and captured.personality.care.medicalMedicineState.painCount==4,
                'native Persistence.captureRecord retains actual daily medicine ledger: '..tostring(captureReason))
            local exported=assert(SC.Commands.export(s.actor))
            SC.Commands.reset(s.actor);SC.MedicalMedicines.reset()
            local restored,restoreReason=SC.Commands.restore(s.actor,exported)
            check(restored and P.readCare(s.actor,'medicalMedicineState').painCount==4,
                'native Commands roundtrip preserves four-dose cap: '..tostring(restoreReason))
            local proof=P.readCare(s.actor,'medicalMedicineRecovery')
            check(proof and proof.effectVerified and proof.debitVerified and not SC.MedicalMedicines.pending(s.actor),
                'verified native dose receipt survives durable Commands roundtrip without replay')
            check(not need or need.kind~='take_painkillers','native fifth same-game-day dose is not selected')
            local okay=M.treat(s.actor,s.actor,refresh(s,s.actor,check),{careKind='take_painkillers'})
            check(not okay and not M.peek(s.actor) and s.phase3.pills:getCurrentUses()==uses,'shipping daily limit preserves exact remaining native pills')
            note('production_pain_daily_limit=4; native_persistence_capture_and_commands_roundtrip=true; actual_native_doses='..s.phase3.doseCount..'; receipts='..table.concat(s.phase3.doseReceipts,','))
            phase('acceptance-phase3-antibiotic-setup');return
        end
        check(need and need.kind=='take_painkillers' and need.wholeBody,'shipping real Pain moodle selects whole-body pill care')
        s.phase3.row={helper=s.actor,patient=s.actor,options=options(need)}
        local okay,why=drive(s,s.phase3.row,check)
        check(okay and M.peek(s.actor),'shipping native pill visual starts: '..tostring(why))
        phase('acceptance-phase3-pain-running')
    elseif s.phase=='acceptance-phase3-pain-running' then
        check(now-s.at<45000,'shipping native pill visual finishes')
        local okay,why=drive(s,s.phase3.row,check)
        if M.peek(s.actor) then check(okay,'shipping pill keeps exact owner: '..tostring(why));return end
        check(okay and why=='painkillers_taken','shipping native pill reports verified success: '..tostring(why))
        s.phase3.doseCount=s.phase3.doseCount+1
        check(s.phase3.pills:getCurrentUses()==s.phase3.pillUses-s.phase3.doseCount,'each shipping pill spends exactly one native use')
        check(s.actor:getPainEffect()>0 and s.actor:getPainDelta()>0,'shipping pill starts proved native active state')
        local ledger=P.readCare(s.actor,'medicalMedicineState')
        check(ledger and ledger.painCount>=1 and ledger.painCount<=4,'native actual dose updates durable daily bound')
        s.phase3.doseReceipts[#s.phase3.doseReceipts+1]=ledger.painDay..':'..ledger.painCount
        local need=M.careNeed(s.actor)
        check(not need or need.kind~='take_painkillers','shipping active native dose cannot be selected again')
        check(M.pendingCare(s.actor)==nil and M.treatmentHolder(s.actor)==nil,'verified native pill releases receipt and claim')
        s.phase3.previousMultiplier=getGameTime():getTrueMultiplier();getGameTime():setMultiplier(100)
        phase('acceptance-phase3-pain-exhaust')
    elseif s.phase=='acceptance-phase3-pain-exhaust' then
        check(now-s.at<20000,'real native pill timer exhausts under accelerated fixture time')
        if s.actor:getPainEffect()>0 or s.actor:getPainDelta()>0 then return end
        getGameTime():setMultiplier(s.phase3.previousMultiplier)
        check(SC.MedicalMedicines.nativeState(s.actor,'take_painkillers')~=nil,'shipping native state accepts naturally expired negative painEffect')
        check(s.phase3.doseCount<9,'native daily-bound test reaches four doses within at most two days')
        painSetup(s,check);phase('acceptance-phase3-pain-ready')
    elseif s.phase=='acceptance-phase3-antibiotic-setup' then
        if N.pacingStatus(s.actor) or N.pacingStatus(s.helper) then check(now-s.at<30000,'pill pacing settles before antibiotic');return end
        clear(s.actor);clear(s.helper)
        s.actor:getBodyDamage():setInfected(true)
        local need=M.careNeed(s.actor,nil,{helper=s.helper,disinfectantAvailable=false})
        check(not need or need.kind~='take_antibiotics','native Knox alone never selects antibiotics')
        s.actor:getBodyDamage():setInfected(false)
        local part=s.actor:getBodyDamage():getBodyPart(BodyPartType.Foot_R)
        part:setScratchTime(25);part:setBleeding(false);part:setBleedingTime(0);part:setInfectedWound(true);part:setWoundInfectionLevel(5);part:setBandaged(true,1000,false,'Base.Bandage')
        M.invalidate(s.actor)
        local root=s.helper:getInventory();local medicine=assert(root:AddItem('Base.Antibiotics'));local reserve=assert(root:AddItem('Base.Antibiotics'))
        need=M.careNeed(s.actor,nil,{helper=s.helper,disinfectantAvailable=false})
        check(need and need.kind=='take_antibiotics' and need.wholeBody,'real infected wound without disinfectant selects native antibiotic')
        s.phase3.row={helper=s.helper,patient=s.actor,part=part,item=medicine,reserve=reserve,
            options=options(need,{supplyContext={disinfectantAvailable=false}})}
        local okay,why=drive(s,s.phase3.row,check)
        check(okay and M.peek(s.helper),'distinct native medic begins giving patient medicine: '..tostring(why))
        phase('acceptance-phase3-antibiotic-running')
    elseif s.phase=='acceptance-phase3-antibiotic-running' then
        check(now-s.at<60000,'shipping native antibiotic visual finishes')
        local row=s.phase3.row;local okay,why=drive(s,row,check)
        if M.peek(row.helper) then check(okay,'shipping antibiotic retains exact owner: '..tostring(why));return end
        check(okay and why=='antibiotics_taken','shipping native antibiotic reports verified success: '..tostring(why))
        check(not row.helper:getInventory():contains(row.item) and row.helper:getInventory():contains(row.reserve),'shipping antibiotic spends exact one helper item and retains reserve')
        check(row.patient:getReduceInfectionPower()>0 and row.helper:getReduceInfectionPower()==0,'shipping medicine affects exact patient from medic supply')
        check(M.pendingCare(row.patient)==nil and M.treatmentHolder(row.patient)==nil,'verified antibiotic settles native receipt and claim')
        local need=M.careNeed(row.patient,nil,{helper=row.helper,disinfectantAvailable=false})
        check(not need or need.kind~='take_antibiotics','shipping active native course prevents a second course')
        note('production_antibiotic=distinct_native_helper_stock_patient_effect; exact_one_item_spent=true; active_course_guard=true; Knox_only_refused=true')
        phase('acceptance-phase3-outside-setup')
    elseif s.phase=='acceptance-phase3-outside-setup' then
        if N.pacingStatus(s.actor) or N.pacingStatus(s.helper) then check(now-s.at<30000,'prior medicine pacing settles before autonomous helper case');return end
        check(SC.BaseWork.reset(),'prior owned work releases before outside-camp decisions')
        SC.BaseLife.reset()
        clear(s.actor);clear(s.helper)
        SC.Decision.reset(s.actor);SC.Decision.reset(s.helper)
        for _,actor in ipairs({s.actor,s.helper}) do
            check(SC.Commands.issue(P.actorId(actor),'stay',{},s.primary),'native autonomous fixture receives stationary public order')
        end
        local patientLevel=s.actor:getPerkLevel(Perks.Doctor)
        for _=1,10 do if s.helper:getPerkLevel(Perks.Doctor)<patientLevel+2 then s.helper:LevelPerk(Perks.Doctor,false) end end
        check(s.helper:getPerkLevel(Perks.Doctor)>=patientLevel+2,'actual native helper First Aid is at least two levels higher')
        check(M.sameCareGroup(s.helper,s.actor),'actual outside-camp actors share expedition eligibility')
        local root=s.helper:getInventory()
        local row={part=wound(s.actor),suture=assert(root:AddItem('Base.SutureNeedle')),fresh=assert(root:AddItem('Base.Bandage')),
            patientFresh=assert(s.actor:getInventory():AddItem('Base.Bandage')),helper=s.helper,patient=s.actor}
        row.startX,row.startY,row.startZ=SC.GameplayUtil.position(s.actor)
        s.phase3.outside=row
        local ready,why=M.canReplaceDirtyBandage(s.actor)
        check(not ready and why=='no_stitching_kit','actual patient lacks own sewing kit despite carrying fresh dressing')
        refresh(s,s.actor,check);refresh(s,s.helper,check)
        phase('acceptance-phase3-outside-running')
    elseif s.phase=='acceptance-phase3-outside-running' then
        local row=s.phase3.outside
        check(now-s.at<90000,'autonomous outside-camp helper completes through both Decision.update calls')
        refresh(s,row.patient,check);refresh(s,row.helper,check)
        SC.ActionSupervisor.update(row.patient);SC.ActionSupervisor.update(row.helper)
        SC.Decision.update(row.patient,s.primary,SC.GameplayUtil.actorState(row.patient),now)
        SC.Decision.update(row.helper,s.primary,SC.GameplayUtil.actorState(row.helper),now)
        local active=M.peek(row.helper)
        if active then
            row.sawHelperOwner=true
            check(active.patient==row.patient and M.treatmentHolder(row.patient)==row.helper,'autonomous medical owner and claim belong to qualified exact helper')
        end
        local x,y,z=SC.GameplayUtil.position(row.patient)
        check(z==row.startZ and (x-row.startX)^2+(y-row.startY)^2<0.2,'autonomous patient stays quiet while qualified helper treats')
        if row.part:getStitchTime()<=0 or M.peek(row.helper) then return end
        check(row.sawHelperOwner and row.part:bandaged() and row.part:getDeepWoundTime()==0,'autonomous qualified helper stitches and redresses native patient')
        check(not row.helper:getInventory():contains(row.suture) and not row.helper:getInventory():contains(row.fresh)
            and row.patient:getInventory():contains(row.patientFresh),'autonomous helper spends exact own kit and dressing while patient supply stays')
        check(M.pendingCare(row.patient)==nil and M.treatmentHolder(row.patient)==nil,'autonomous outside-camp care settles claim and receipt')
        note('production_outside_helper=both_actual_Decision.update_only; patient_has_no_sewing_kit=true; native_helper_FirstAid='..row.helper:getPerkLevel(Perks.Doctor)
            ..'; patient_FirstAid='..row.patient:getPerkLevel(Perks.Doctor)..'; qualified_owner_observed=true; patient_quiet=true; exact_helper_supplies_spent=true')
        SC.Decision.reset(row.patient);SC.Decision.reset(row.helper)
        phase('acceptance-phase3-camp-start')
    elseif string.find(s.phase,'acceptance-phase3-camp-',1,true)==1 then
        s.phase3CampProbe=s.phase3CampProbe or require 'MedicalPhase3CampAcceptance'
        return s.phase3CampProbe.step(s,check,note,phase)
    end
end
return Probe
