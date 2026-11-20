-- SPDX-License-Identifier: MIT
-- Real camp shelves, physical native kit packing and MedicalVisits audit jobs.
local Probe={}
local function refresh(s,actor,check)
    local SC=SurvivorCompanion;local context=SC.GameplayUtil.actorState(actor)
    local seen=SC.Senses.snapshot(actor,s.primary,context)
    check(type(seen)=='table' and seen.valid and SC.Medical.canTreatNow(actor,seen),'native Phase3 camp sees actual semi-safe world')
    return context
end
local function clear(actor)
    local SC=SurvivorCompanion
    actor:getBodyDamage():RestoreToFullHealth();actor:setPainEffect(0);actor:setPainDelta(0);actor:setReduceInfectionPower(0)
    actor:getBodyDamage():setPainReduction(0)
    local stats=actor:getStats()
    for _,stat in ipairs({CharacterStat.HUNGER,CharacterStat.THIRST,CharacterStat.FATIGUE,CharacterStat.PAIN}) do stats:set(stat,0) end
    stats:set(CharacterStat.ENDURANCE,1)
    for _,entry in ipairs(assert(SC.BandageWash.inventoryEntries(actor))) do
        local kind=entry.item:getFullType()
        if SC.Medical.dressingRank(entry.item,true) or SC.MedicKit.isKit(entry.item) or entry.item:getFluidContainer()
            or kind=='Base.Splint' or kind=='Base.Pills' or kind=='Base.Antibiotics' or kind=='Base.AlcoholWipes'
            or kind=='Base.Needle' or kind=='Base.Thread' or kind=='Base.SutureNeedle' or kind=='Base.Tweezers'
            or kind=='Base.SutureNeedleHolder' then entry.source:Remove(entry.item) end
    end
    for _,field in ipairs({'medicalMedicineState','medicalMedicineRecovery','medicalInfectionDisinfectHours','medicalDisinfectHours'}) do
        SC.MedicalProcedures.writeCare(actor,field,nil)
    end
    SC.Medical.invalidate(actor)
end
local function shelves(origin,check)
    local U=SurvivorCompanion.GameplayUtil;local result={}
    for radius=2,6 do for dx=-radius,radius do for dy=-radius,radius do
        if math.abs(dx)==radius or math.abs(dy)==radius then
            local square=getCell():getGridSquare(origin:getX()+dx,origin:getY()+dy,origin:getZ())
            if square and U.isClearActorSpawnSquare(square)==true and square:isFree(false) then
                local separated=true
                for _,candidate in ipairs(result) do if U.distanceSq(candidate,square)<4 then separated=false end end
                if separated then result[#result+1]=square;if #result==3 then return result end end
            end
        end
    end end end
    check(false,'three actual clear camp storage squares exist')
end
local function crate(square,category,check)
    local object=IsoThumpable.new(getCell(),square,'carpentry_01_16',false,{})
    object:setIsContainer(true);object:setContainer(ItemContainer.new('crate',square,object))
    local container=object:getContainer();container:setCapacity(100);container:setExplored(true)
    square:AddSpecialObject(object);square:RecalcAllWithNeighbours(true)
    local okay,row=SurvivorCompanion.BaseLife.registerStorage(object,category)
    check(okay and SurvivorCompanion.BaseLife.resolveContainer(row)==container,'real camp registers exact '..category..' source')
    return {object=object,container=container,row=row}
end
local function findJob(state)
    local count,found=0,nil
    for _,job in ipairs(state.base.jobs) do
        if job.type=='replace_bandage' and job.target and job.target.patientId==state.patientId
            and job.state~='completed' and job.state~='cancelled' then count,found=count+1,job end
    end
    return count,found
end
local function audit(s,check,kind)
    local SC,state=SurvivorCompanion,s.phase3Camp
    refresh(s,state.medic,check);refresh(s,state.patient,check)
    local need=SC.Medical.campCareNeed(state.patient)
    check(need and need.kind==kind,'actual camp selector requests '..kind)
    SC.MedicalVisits.audit(state.base,function() return math.huge end,{})
    local count,job=findJob(state)
    check(count==1 and job.assignedId==state.medicId,'actual MedicalVisits audit assigns exact distinct medic to '..kind)
    SC.MedicalVisits.audit(state.base,function() return math.huge end,{})
    check(findJob(state)==1,'actual repeated Phase3 camp audit deduplicates patient')
    state.job,state.sawHold,state.jobStarted=job,false,getTimestampMs()
    state.patientX,state.patientY,state.patientZ=SC.GameplayUtil.position(state.patient)
end
local function drive(s,check)
    local SC,state=SurvivorCompanion,s.phase3Camp
    local context=refresh(s,state.medic,check);local patientContext=refresh(s,state.patient,check)
    SC.ActionSupervisor.update(state.medic)
    if not SC.NativeActions.pacingStatus(state.medic) then
        local okay,why=SC.BaseWork.update(state.medic,s.primary,context);state.last=tostring(okay)..'/'..tostring(why)
    end
    if SC.MedicalVisits.isPatientHeld(state.patient,patientContext,SC.Medical.assess(state.patient),getTimestampMs()) then
        state.sawHold=true
        check(SC.Medical.treatmentHolder(state.patient)==state.medic,'actual Phase3 patient hold belongs to exact medic')
        local held,why=SC.Medical.update(state.patient,s.primary,patientContext)
        check(held and why=='receiving_care','actual Phase3 receiving-care branch honors visit hold')
        local x,y,z=SC.GameplayUtil.position(state.patient)
        check(z==state.patientZ and (x-state.patientX)^2+(y-state.patientY)^2<0.2,'actual Phase3 held patient remains in place')
    end
    check(state.job.state~='blocked' and state.job.state~='cancelled','native camp care retains valid job: '..tostring(state.job.blocker)..'/'..tostring(state.last))
    return state.job.state=='completed'
end
function Probe.step(s,check,note,phase)
    local SC,K,M,N,B=SurvivorCompanion,SurvivorCompanion.MedicKit,SurvivorCompanion.Medical,SurvivorCompanion.NativeActions,SurvivorCompanion.BaseLife
    local now=getTimestampMs()
    if s.phase=='acceptance-phase3-camp-start' then
        if N.pacingStatus(s.actor) or N.pacingStatus(s.helper) then check(now-s.at<30000,'prior medicine pacing settles before real camp');return end
        check(SC.BaseWork.reset(),'prior native medical work releases before camp stocking')
        B.reset();SC.MedicalVisits.reset();SC.MedicalSupplies.reset()
        clear(s.actor);clear(s.helper)
        check(B.create(s.primary:getSquare(),'Native Phase3 kit and medic'),'actual Phase3 camp is created')
        local base=B.active();base.settings.autoMaintenance,base.settings.routines,base.settings.workload=false,false,'essential';base.settings.workOutsideAtNight=true
        local state={base=base,medic=s.helper,patient=s.actor,medicId=SC.GameplayUtil.idOf(s.helper),patientId=SC.GameplayUtil.idOf(s.actor),deadline=now+210000}
        s.phase3Camp=state
        for _,row in ipairs({{state.medicId,'medic'},{state.patientId,'generalist'}}) do
            check(B.assign(row[1],row[2],true),'native Phase3 resident assigned '..row[2])
            check(SC.Commands.issue(row[1],'base_duty',{},s.primary),'native Phase3 resident receives camp duty')
        end
        local squares=shelves(s.primary:getSquare(),check)
        state.medical,state.crafting,state.tools=crate(squares[1],'medical',check),crate(squares[2],'crafting',check),crate(squares[3],'tools',check)
        local stock=state.medical.container
        state.kit=assert(stock:AddItem('Base.FirstAidKit'))
        state.dressings={assert(stock:AddItem('Base.Bandage')),assert(stock:AddItem('Base.Bandage'))}
        state.splint=assert(stock:AddItem('Base.Splint'));state.pills=assert(stock:AddItem('Base.Pills'))
        state.wipes=assert(stock:AddItem('Base.AlcoholWipes'))
        state.antibiotics={assert(stock:AddItem('Base.Antibiotics')),assert(stock:AddItem('Base.Antibiotics'))}
        state.protected=assert(stock:AddItem('Base.Tweezers'));state.protected:setFavorite(true)
        for _=1,90 do assert(state.crafting.container:AddItem('Base.Paperclip')) end
        state.needle=assert(state.crafting.container:AddItem('Base.Needle'))
        state.thread=assert(state.tools.container:AddItem('Base.Thread'));state.threadUses=state.thread:getCurrentUses()
        state.tweezers=assert(state.tools.container:AddItem('Base.Tweezers'))
        phase('acceptance-phase3-camp-kit-ready')
    elseif s.phase=='acceptance-phase3-camp-kit-ready' then
        local state=s.phase3Camp
        refresh(s,state.medic,check)
        check(B.isInside(state.medic) and SC.Logistics.roleOf(state.medic)=='medic','actual camp medic has valid role and location')
        -- Public order/Decision changes deliberately cancel old logistics and
        -- keep its ordinary 15-second retry. Observe that real cooldown instead
        -- of treating this newly reused actor as a fresh subsystem instance.
        if not K.needsWork(state.medic,SC.Logistics.audit(state.medic)) then
            check(now-s.at<30000,'actual empty native medic requests kit after normal cancellation cooldown');return
        end
        note('production_camp_kit_initial_cooldown_wait_ms='..(now-s.at))
        state.deadline=now+210000
        phase('acceptance-phase3-camp-stock')
    elseif s.phase=='acceptance-phase3-camp-stock' then
        local state=s.phase3Camp
        check(now<state.deadline,'actual native kit stocking finishes; last='..tostring(state.last))
        refresh(s,state.medic,check);SC.ActionSupervisor.update(state.medic)
        if N.workKind(state.medic)=='medic_kit' then state.sawNativePack=true end
        local facts=K.view(state.medic,SC.Logistics.audit(state.medic))
        if K.needsWork(state.medic,SC.Logistics.audit(state.medic)) and not N.pacingStatus(state.medic) then
            local okay,why=K.step(state.medic,SC.Logistics.audit(state.medic));state.last=tostring(okay)..'/'..tostring(why)
        end
        check(state.protected:getContainer()==state.medical.container and state.protected:isFavorite(),'actual favorite stock is never fetched')
        check(state.medical.row.category=='medical' and state.crafting.row.category=='crafting' and state.tools.row.category=='tools','native medic-only resource wants preserve all shelf categories')
        facts=K.view(state.medic,SC.Logistics.audit(state.medic))
        if not (facts.kit==state.kit and facts.kitDressings>=2 and facts.kitSplints>=1 and facts.painkillerItem==state.pills
            and facts.needleItem==state.needle and facts.threadItem==state.thread and facts.tweezersItem==state.tweezers
            and facts.disinfectantItem==state.wipes and facts.antibioticItem and not K.busy(state.medic)
            and not K.needsWork(state.medic,SC.Logistics.audit(state.medic))) then return end
        check(state.sawNativePack and state.kit:getContainer()==state.medic:getInventory(),'actual native kit action packs borrowed physical case')
        local receipt=state.kit:getModData().LF_MedicKitLoan
        check(receipt and receipt.actorId==state.medicId and receipt.storageId==state.medical.row.id,'native physical kit loan retains exact shelf and actor')
        check(K.mayUseContents(state.medic,state.kit) and SC.MedicalMedicines.itemAllowed(state.medic,state.pills),'native borrowed medic-kit contents remain consumable by exact medic')
        check(state.needle:getContainer()==state.kit:getInventory() and state.thread:getContainer()==state.kit:getInventory(),'native bounded fallback fetches and packs needle beyond90 craft items plus tool-shelf thread')
        note('production_camp_kit=native_stock_withdrawals_and_native_physical_packing; min_dressings=2; exact_pills_needle_thread_tweezers=true; source_categories_unchanged=true; favorite_control_untouched=true')
        phase('acceptance-phase3-camp-stitch-setup')
    elseif s.phase=='acceptance-phase3-camp-stitch-setup' then
        local state=s.phase3Camp
        if N.pacingStatus(state.medic) then check(now-s.at<30000,'kit pacing settles before actual patient audit');return end
        local part=state.patient:getBodyDamage():getBodyPart(BodyPartType.Foot_R)
        part:setDeepWounded(true);part:setDeepWoundTime(15);part:setBleeding(false);part:setBleedingTime(0);part:setGetStitchXp(true);part:setBandaged(true,15,false,'Base.Bandage')
        state.part,state.xpBefore=part,state.medic:getXp():getXP(Perks.Doctor)
        M.invalidate(state.patient);audit(s,check,'stitch_wound');phase('acceptance-phase3-camp-stitch-running')
    elseif s.phase=='acceptance-phase3-camp-stitch-running' then
        local state=s.phase3Camp;check(now-s.at<90000,'actual audited camp stitch completes: '..tostring(state.last))
        if not drive(s,check) then return end
        check(state.sawHold and state.part:bandaged() and state.part:getStitchTime()>0 and state.part:getDeepWoundTime()==0,'actual camp medic stitches held resident and restores covering')
        check(state.thread:getCurrentUses()==state.threadUses-1 and K.owns(state.medic,state.needle),'actual audited camp stitch spends one exact borrowed-kit thread use and retains needle')
        check(state.medic:getXp():getXP(Perks.Doctor)>state.xpBefore and state.medic:isLocalPlayer()==false,
            'actual camp stitch awards native First Aid to the exact nonlocal medic')
        check(M.pendingCare(state.patient)==nil and M.treatmentHolder(state.patient)==nil,'completed native camp stitch releases claim and obligation')
        note('production_camp_stitch=actual_MedicalVisits_audit_exact_medic_job; held_patient=true; native_thread_debit=1; stitched_and_redressed=true')
        phase('acceptance-phase3-camp-pill-setup')
    elseif s.phase=='acceptance-phase3-camp-pill-setup' then
        local state=s.phase3Camp
        if N.pacingStatus(state.medic) then check(now-s.at<30000,'camp surgical pacing settles before pill');return end
        state.patient:getBodyDamage():RestoreToFullHealth();state.patient:setPainEffect(0);state.patient:setPainDelta(0)
        local parts=state.patient:getBodyDamage():getBodyParts()
        for index=0,parts:size()-1 do parts:get(index):setAdditionalPain(20) end
        state.patient:getStats():set(CharacterStat.PAIN,65);M.invalidate(state.patient)
        state.pillUses=state.pills:getCurrentUses();phase('acceptance-phase3-camp-pill-ready')
    elseif s.phase=='acceptance-phase3-camp-pill-ready' then
        if now-s.at<5500 then return end
        audit(s,check,'take_painkillers');phase('acceptance-phase3-camp-pill-running')
    elseif s.phase=='acceptance-phase3-camp-pill-running' then
        local state=s.phase3Camp;check(now-s.at<60000,'actual audited camp medicine completes: '..tostring(state.last))
        if not drive(s,check) then return end
        check(state.sawHold and state.pills:getCurrentUses()==state.pillUses-1 and state.patient:getPainEffect()>0 and state.medic:getPainEffect()<=0,'actual camp medic gives held patient one exact dose from borrowed kit')
        check(M.pendingCare(state.patient)==nil and M.treatmentHolder(state.patient)==nil,'actual native camp pill releases receipt and scoped claim')
        note('production_camp_painkiller=actual_MedicalVisits_audit_patient_hold; own_borrowed_kit_consumption=true; exact_native_dose=1; patient_effect=true')
        phase('acceptance-phase3-camp-antibiotic-setup')
    elseif s.phase=='acceptance-phase3-camp-antibiotic-setup' then
        local state=s.phase3Camp
        if N.pacingStatus(state.medic) then check(now-s.at<30000,'camp pill pacing settles before local infection');return end
        -- This distinct fixture episode has no disinfectant available. Retire
        -- only its owned reagent to exercise the normal no-reagent exception.
        local source=state.wipes:getContainer();if source then source:Remove(state.wipes) end
        state.patient:getBodyDamage():RestoreToFullHealth()
        state.patient:getStats():set(CharacterStat.PAIN,0)
        local part=state.patient:getBodyDamage():getBodyPart(BodyPartType.Foot_R)
        part:setScratchTime(25);part:setBleeding(false);part:setBleedingTime(0);part:setInfectedWound(true);part:setWoundInfectionLevel(5);part:setBandaged(true,1000,false,'Base.Bandage')
        state.part=part;M.invalidate(state.patient);SC.MedicalSupplies.reset()
        phase('acceptance-phase3-camp-antibiotic-ready')
    elseif s.phase=='acceptance-phase3-camp-antibiotic-ready' then
        if now-s.at<5500 then return end
        local state=s.phase3Camp
        local context=K.medicineContext(state.medic,state.patient,{stage='commit'})
        check(context.stockKnown and context.disinfectantAvailable==false and context.antibioticDoses==2,'actual camp observes two usable antibiotic courses and no disinfectant')
        for _,item in ipairs(state.antibiotics) do if K.owns(state.medic,item) then state.course=item end end
        check(state.course~=nil,'actual kit stock includes exact helper-carried native antibiotic')
        audit(s,check,'take_antibiotics');phase('acceptance-phase3-camp-antibiotic-running')
    elseif s.phase=='acceptance-phase3-camp-antibiotic-running' then
        local state=s.phase3Camp;check(now-s.at<75000,'actual audited camp antibiotic completes: '..tostring(state.last))
        drive(s,check)
        if state.patient:getReduceInfectionPower()<=0 or M.peek(state.medic) then return end
        check(state.sawHold and not K.owns(state.medic,state.course) and state.patient:getReduceInfectionPower()>0 and state.medic:getReduceInfectionPower()==0,'actual camp medic spends exact carried antibiotic on held patient')
        local remaining=0;for _,item in ipairs(state.antibiotics) do if item:getContainer()~=nil then remaining=remaining+1 end end
        check(remaining==1 and M.pendingCare(state.patient)==nil and M.treatmentHolder(state.patient)==nil,'actual camp leaves one exact reserve course and settles claim')
        -- Wound disinfection remains a separate unmet need in this deliberately
        -- reagent-free fixture. End only this owned test visit via public API.
        if B.job(state.job.id) and state.job.state~='completed' and state.job.state~='cancelled' then
            check(B.cancelJob(state.job.id),'public cancellation releases the completed test medicine visit')
        end
        note('production_camp_antibiotic=actual_MedicalVisits_audit_real_camp_stock_context; held_patient=true; exact_native_course=1; reserve_course=1')
        return true
    end
end
return Probe
