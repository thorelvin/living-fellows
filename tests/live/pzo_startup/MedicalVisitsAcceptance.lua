-- SPDX-License-Identifier: MIT
-- Actual camp audit, job claims, walking, patient holds and native care effects.
local Probe={}
local scenarios={'positive','cancel','leaving','player-care','fallback','danger'}
local function refresh(actor,s,check)
    local SC=LivingFellows
    local runtime=SC.GameplayUtil.actorState(actor)
    local observed=SC.Senses.snapshot(actor,s.primary,runtime)
    check(type(observed)=='table' and observed.valid==true,'visit fixture observes the real loaded world')
    return runtime,observed
end
local function openJobs(base,patientId)
    local count,found=0,nil
    for _,job in ipairs(base.jobs or {}) do
        if job.type=='replace_bandage' and job.target and job.target.patientId==patientId
            and job.state~='completed' and job.state~='cancelled' then count,found=count+1,job end
    end
    return count,found
end
local function pairSquares(s)
    local U=LivingFellows.GameplayUtil
    local origin=s.primary:getSquare();local room=origin:getRoom();local all,same={},{}
    for radius=1,8 do for dx=-radius,radius do for dy=-radius,radius do
        if math.abs(dx)==radius or math.abs(dy)==radius then
            local square=getCell():getGridSquare(origin:getX()+dx,origin:getY()+dy,origin:getZ())
            if square and U.isClearActorSpawnSquare(square) and square:isFree(false) then
                all[#all+1]=square
                if square:getRoom()==room then same[#same+1]=square end
            end
        end
    end end end
    for _,rows in ipairs({same,all}) do
        for _,patient in ipairs(rows) do for _,doctor in ipairs(rows) do
            if U.distanceSq(patient,doctor)>=16 and U.distanceSq(patient,doctor)<=49 then return patient,doctor end
        end end
    end
end
local function supplies(actor,amount,withTool)
    local root=actor:getInventory();local result={}
    for _,row in ipairs(assert(LivingFellows.BandageWash.inventoryEntries(actor))) do
        if LivingFellows.Medical.dressingRank(row.item,true) or row.item:getType()=='Tweezers'
            or row.item:getType()=='SutureNeedle' or row.item:getType()=='Pills' or row.item:getType()=='AlcoholWipes'
            or row.item:getFluidContainer() then row.source:Remove(row.item) end
    end
    for index=1,amount do result[index]=assert(root:AddItem('Base.Bandage')) end
    local tool=withTool~=false and assert(root:AddItem('Base.Tweezers')) or nil
    -- Phase 3 legitimately continues the old glass visit: the native removal
    -- leaves a deep wound, and the intentionally low-health patient may hurt.
    -- Supply the complete new cycle instead of making that visit block after
    -- its Phase 2 effect. The original source fixtures remain unchanged.
    local careStock
    if withTool~=false then
        careStock={suture=assert(root:AddItem('Base.SutureNeedle')),pills=assert(root:AddItem('Base.Pills')),
            wipes=assert(root:AddItem('Base.AlcoholWipes'))}
        careStock.pillUses,careStock.wipeUses=careStock.pills:getCurrentUses(),careStock.wipes:getCurrentUses()
    end
    local stats=actor:getStats()
    stats:set(CharacterStat.HUNGER,0.05);stats:set(CharacterStat.THIRST,0.05)
    stats:set(CharacterStat.FATIGUE,0.05);stats:set(CharacterStat.ENDURANCE,1)
    return result,tool,careStock
end
local function coveredGlass(actor,second,low)
    actor:getBodyDamage():RestoreToFullHealth()
    local part=actor:getBodyDamage():getBodyPart(BodyPartType.Foot_R)
    part:setHaveGlass(true);part:setDeepWoundTime(12);part:setBleeding(false);part:setBleedingTime(0)
    part:setBandaged(true,15,false,'Base.Bandage')
    local dirty
    if second then
        dirty=actor:getBodyDamage():getBodyPart(BodyPartType.ForeArm_L)
        dirty:setScratchTime(20);dirty:setBleeding(false);dirty:setBleedingTime(0)
        dirty:setBandaged(true,0,false,'Base.Bandage')
    end
    if low then actor:getBodyDamage():ReduceGeneralHealth(70);actor:getBodyDamage():calculateOverallHealth() end
    LivingFellows.Medical.invalidate(actor)
    return part,dirty
end
local function register(s,check)
    local SC,U=LivingFellows,LivingFellows.GameplayUtil
    local v=s.visitState
    v.patientId,v.medicId=assert(U.idOf(v.patient)),assert(U.idOf(v.medic))
    check(SC.BaseLife.assign(v.patientId,'generalist',true),'native patient becomes an on-duty resident')
    check(SC.BaseLife.assign(v.medicId,'medic',true),'distinct native companion becomes camp medic')
    check(SC.Commands.issue(v.patientId,'base_duty',{},s.primary),'patient receives real base-duty command')
    check(SC.Commands.issue(v.medicId,'base_duty',{},s.primary),'medic receives real base-duty command')
    check(SC.Commands.issue(v.patientId,'set_group',{group='native-patient-squad'},s.primary),'patient retains its ordinary squad')
    check(SC.Commands.issue(v.medicId,'set_group',{group='native-medic-squad'},s.primary),'medic retains a different ordinary squad')
    check(SC.Commands.peek(v.patient).group~=SC.Commands.peek(v.medic).group,'native residents have distinct ordinary groups')
    v.fresh,v.tool,v.careStock=supplies(v.medic,5)
    v.patientFresh=supplies(v.patient,0,false)
    v.part,v.dirty=coveredGlass(v.patient,v.scenario=='positive',v.scenario=='positive')
    if v.scenario=='fallback' then v.patientFresh,v.patientTool,v.patientCareStock=supplies(v.patient,4) end
    v.context=refresh(v.medic,s,check);v.patientContext=refresh(v.patient,s,check)
    v.startX,v.startY,v.startZ=U.position(v.medic)
    v.patientX,v.patientY,v.patientZ=U.position(v.patient)
    v.initialDistance=U.distance(v.medic,v.patient)
    check(v.initialDistance>=3.5,'native visiting medic starts outside treatment contact')
    check(SC.BaseLife.isInside(v.medic) and SC.BaseLife.isInside(v.patient),'both native residents stand inside actual camp area')
end
local function unchanged(v,check)
    check(v.part:haveGlass() and v.part:bandaged(),'interrupted visit leaves covered lodged glass untouched')
    for _,item in ipairs(v.fresh) do check(v.medic:getInventory():contains(item),'interrupted visit keeps exact medic fresh supply') end
    if v.careStock then
        check(v.medic:getInventory():contains(v.careStock.suture) and v.careStock.pills:getCurrentUses()==v.careStock.pillUses
            and v.careStock.wipes:getCurrentUses()==v.careStock.wipeUses,'interrupted inherited visit preserves added exact Phase3 kit and medicines')
    end
end
local function drive(s,check)
    local SC,U=LivingFellows,LivingFellows.GameplayUtil
    local v=s.visitState
    v.context=refresh(v.medic,s,check);v.patientContext=refresh(v.patient,s,check)
    SC.ActionSupervisor.update(v.medic);SC.ActionSupervisor.update(v.patient)
    local helper=v.scenario=='fallback' and v.fallbackReady and v.patient or v.medic
    if not SC.NativeActions.pacingStatus(helper) then
        local context=helper==v.patient and v.patientContext or v.context
        local okay,why=SC.BaseWork.update(helper,s.primary,context)
        v.last=tostring(okay)..'/'..tostring(why)
    end
    local held=SC.MedicalVisits.isPatientHeld(v.patient,v.patientContext,SC.Medical.assess(v.patient),getTimestampMs())
    if held then
        v.sawHold=true
        check(SC.Medical.treatmentHolder(v.patient)==v.medic,'native hold belongs to the exact visiting medic')
        local heldOkay,heldReason=SC.Medical.update(v.patient,s.primary,v.patientContext)
        check(heldOkay and heldReason=='receiving_care','shipping medical patient branch honors actual visit hold')
        local x,y,z=U.position(v.patient)
        check(z==v.patientZ and (x-v.patientX)^2+(y-v.patientY)^2<0.2,'held patient stays in place through shipping medical updates')
    end
    local x,y,z=U.position(v.medic)
    if z==v.startZ and (x-v.startX)^2+(y-v.startY)^2>0.25 then v.sawWalk=true end
    return held
end
function Probe.step(s,check,note,phase)
    local SC,U,M,V,N=LivingFellows,LivingFellows.GameplayUtil,LivingFellows.Medical,LivingFellows.MedicalVisits,LivingFellows.NativeActions
    local now=getTimestampMs()
    if s.phase=='acceptance-visits-start' then
        check(SC.BaseWork.reset(),'prior native work releases before visiting-care fixtures')
        SC.BaseLife.reset();V.reset()
        check(SC.BaseLife.create(s.primary:getSquare(),'Native visiting medical care'),'actual visiting-care camp is created')
        local base=SC.BaseLife.active()
        base.settings.autoMaintenance,base.settings.routines,base.settings.workload=true,false,'essential'
        base.settings.workOutsideAtNight=true
        s.visitState={base=base,index=1}
        phase('acceptance-visits-spawn')
    elseif s.phase=='acceptance-visits-spawn' then
        local v=s.visitState
        if v.index>#scenarios then return true end
        if not v.patientTicket then
            v.scenario=scenarios[v.index]
            local patient,medic=pairSquares(s)
            check(patient and medic,'loaded free same-room visiting fixture tiles exist')
            v.patientSquare,v.medicSquare=patient,medic
            v.patientTicket=assert(SC.Actor.beginSpawn(patient,{recruited=true,identity={forename='Visit',surname='Patient',gender='woman',outfit='Generic01'}}))
        end
        if not v.patient then
            local actor,why=SC.Actor.pollSpawn(v.patientTicket)
            if not actor then check(why=='spawn_pending' and now-s.at<25000,'native visit patient spawns');return end
            v.patient=actor
            v.medicTicket=assert(SC.Actor.beginSpawn(v.medicSquare,{recruited=true,identity={forename='Visit',surname='Medic',gender='man',outfit='Generic01'}}))
        end
        if not v.medic then
            local actor,why=SC.Actor.pollSpawn(v.medicTicket)
            if not actor then check(why=='spawn_pending' and now-s.at<25000,'native visit medic spawns');return end
            v.medic=actor
        end
        register(s,check)
        v.deadline=now+120000
        phase('acceptance-visits-audit')
    elseif s.phase=='acceptance-visits-audit' then
        local v=s.visitState
        check(now<v.deadline,'shipping camp audit finds patient before deadline')
        refresh(v.medic,s,check);refresh(v.patient,s,check)
        SC.BaseWork.auditMaintenance(s.primary,function() return math.huge end)
        local count,job=openJobs(v.base,v.patientId)
        if not job then return end
        check(count==1 and job.assignedId==v.medicId and job.target.patientId==v.patientId,
            'shipping BaseWork audit assigns distinct medic while preserving exact patient')
        v.job=job
        V.audit(v.base,function() return math.huge end,{})
        check(openJobs(v.base,v.patientId)==1,'repeated actual medical audit deduplicates the native patient job')
        phase(v.scenario=='fallback' and 'acceptance-visits-fallback-wait' or 'acceptance-visits-running')
    elseif s.phase=='acceptance-visits-fallback-wait' then
        local v=s.visitState
        check(now<v.deadline,'native wait lease falls back within fixture deadline')
        refresh(v.medic,s,check);v.patientContext=refresh(v.patient,s,check)
        V.auditOpenJobs(v.base,function() return math.huge end)
        V.audit(v.base,function() return math.huge end,{})
        check(openJobs(v.base,v.patientId)==1 and SC.BaseLife.job(v.job.id)==v.job,'wait lease preserves same exact dedup job')
        if v.job.assignedId~=v.patientId then return end
        check(v.job.target.medicalVisit.selfFallback==true,'unclaimed medic wait lease enables real patient self fallback')
        v.fallbackReady=true
        note('production_visit_fallback=same_job_after_real_wait_lease; dedup=true')
        phase('acceptance-visits-running')
    elseif s.phase=='acceptance-visits-running' then
        local v=s.visitState
        check(now<v.deadline,'native '..v.scenario..' visiting care finishes; last='..tostring(v.last))
        local held=drive(s,check)
        if not v.nextDiagnostic or now>=v.nextDiagnostic then
            v.nextDiagnostic=now+1000
            local x,y,z=U.position(v.medic);local px,py,pz=U.position(v.patient)
            local nav=SC.Navigation.status(v.medic);local active=M.peek(v.medic)
            local telemetry=N.pathTelemetry(v.medic)
            note('visit_approach='..v.scenario..'; medic='..x..','..y..','..z..'; patient='..px..','..py..','..pz
                ..'; contact='..tostring(M.inContact(v.medic,v.patient))..'; medical='..tostring(active and active.phase)
                ..'; work='..tostring(v.last)..'; nav='..tostring(nav.phase)..'; target='..tostring(nav.target)
                ..'; movement='..tostring(nav.lastMovementReason)..'; blocker='..tostring(nav.blockerType)
                ..'; path='..tostring(telemetry.status)..'; pathactive='..tostring(telemetry.active))
        end
        if v.scenario=='positive' or v.scenario=='fallback' then
            check(v.job.state~='blocked' and v.job.state~='cancelled','native visiting care keeps valid job ownership: '..tostring(v.job.blocker)..'; '..tostring(v.last))
            if v.scenario=='fallback' then check(not held,'native self fallback never creates a self-hold') end
            if v.job.state~='completed' then return end
            check(not v.part:haveGlass() and v.part:bandaged(),'shipping visit/fallback actually clears glass and redresses exact patient')
            check(v.part:getDeepWoundTime()==0 and v.part:getStitchTime()>0,
                'inherited glass visit completes its new Phase3 native stitch cycle')
            local stitchingStock=v.scenario=='fallback' and v.patientCareStock or v.careStock
            check(stitchingStock.suture:getContainer()==nil,'inherited visit spends its exact Phase3 suture needle once')
            check(M.peek(v.medic)==nil and M.peek(v.patient)==nil and M.treatmentHolder(v.patient)==nil and not held,
                'completed native visit releases medical claim, treatment and patient hold')
            if v.scenario=='positive' then
                check(v.sawHold and v.sawWalk,'distinct camp medic really walks and holds its quiet low-health patient')
                check(v.dirty:bandaged() and v.dirty:getBandageLife()>0,'same visiting job also changes the second dirty native dressing')
                local spent=0;for _,item in ipairs(v.fresh) do if not v.medic:getInventory():contains(item) then spent=spent+1 end end
                check(spent>=2,'cross-resident care spends helper supplies for both real steps')
            else
                check(not v.patient:getInventory():contains(v.patientFresh[1]),'self fallback spends exact patient fresh supply')
                for _,item in ipairs(v.fresh) do check(v.medic:getInventory():contains(item),'waiting medic supplies stay untouched during self fallback') end
            end
            note('production_visit='..v.scenario..'; actual_native_effect=true; added_phase3_stitch_cycle=true; walk='..tostring(v.sawWalk)..'; hold='..tostring(v.sawHold)..'; released=true')
            phase('acceptance-visits-cleanup')
        elseif held then
            unchanged(v,check)
            if v.scenario=='cancel' then phase('acceptance-visits-public-cancel')
            elseif v.scenario=='leaving' then
                check(SC.BaseLife.assign(v.patientId,'generalist',false),'patient publicly leaves base duty during owned visit')
                check(not V.isPatientHeld(v.patient,v.patientContext,M.assess(v.patient),now),'leaving patient immediately ignores visit hold')
                phase('acceptance-visits-release')
            elseif v.scenario=='player-care' then
                M.noteReceivingCare(v.patient,s.primary,now)
                check(M.isReceivingCare(v.patient),'real player-care ledger is active without changing primary queue')
                phase('acceptance-visits-release')
            else
                local square=v.patient:getSquare();local spot,bestDistance
                for _,offset in ipairs({{1,0},{-1,0},{0,1},{0,-1},{1,1},{-1,-1}}) do
                    local target=getCell():getGridSquare(square:getX()+offset[1],square:getY()+offset[2],square:getZ())
                    if target and U.isSquareFree(target) and target:isFree(false)
                        and not U.squareOccupyingObject(target) and target:getRoom()==square:getRoom() then
                        local distance=U.distanceSq(target,v.medic)
                        if not bestDistance or distance>bestDistance then spot,bestDistance=target,distance end
                    end
                end
                check(spot~=nil,'owned danger fixture has a clear same-room neighboring tile')
                v.zombie=assert(createZombie(spot:getX()+0.5,spot:getY()+0.5,spot:getZ(),nil,0,IsoDirections.S))
                v.patient:faceThisObject(v.zombie);v.medic:faceThisObject(v.zombie)
                SC.Senses.reset(v.patient);SC.Senses.reset(v.medic)
                phase('acceptance-visits-danger')
            end
        end
    elseif s.phase=='acceptance-visits-public-cancel' then
        local v=s.visitState
        check(now-s.at<15000,'public camp-job cancellation settles')
        local okay=SC.BaseLife.cancelJob(v.job.id)
        if not okay and SC.BaseLife.job(v.job.id) then return end
        unchanged(v,check)
        check(M.peek(v.medic)==nil and M.treatmentHolder(v.patient)==nil
            and not V.isPatientHeld(v.patient,v.patientContext,M.assess(v.patient),now),'public cancellation releases exact visit and patient hold')
        note('production_visit_public_cancel=body_supplies_untouched; hold_and_claim_released=true')
        phase('acceptance-visits-cleanup')
    elseif s.phase=='acceptance-visits-release' then
        local v=s.visitState
        check(now-s.at<15000,'leaving/player-care visit cancellation settles')
        if v.scenario=='player-care' then M.noteReceivingCare(v.patient,s.primary,now) end
        drive(s,check)
        if M.peek(v.medic) then return end
        unchanged(v,check)
        check(M.treatmentHolder(v.patient)==nil and not V.isPatientHeld(v.patient,v.patientContext,M.assess(v.patient),now),
            'leaving/player care releases exact claim and hold')
        if v.scenario=='player-care' then
            check(M.isReceivingCare(v.patient),'visit cancellation preserves actual player-care ledger')
            M.clearReceivingCare(v.patient)
        end
        note('production_visit_release='..v.scenario..'; body_supplies_untouched=true; hold_released=true')
        phase('acceptance-visits-cleanup')
    elseif s.phase=='acceptance-visits-danger' then
        local v=s.visitState
        check(now-s.at<12000,'actual adjacent zombie becomes sensed before fixture deadline')
        local _,observed=refresh(v.patient,s,check)
        v.patientContext=U.actorState(v.patient);v.context=refresh(v.medic,s,check)
        if M.canTreatNow(v.patient,observed) then return end
        check(not V.isPatientHeld(v.patient,v.patientContext,M.assess(v.patient),now),'actual close danger immediately releases patient hold')
        SC.BaseWork.update(v.medic,s.primary,v.context)
        if M.peek(v.medic) then return end
        check(M.treatmentHolder(v.patient)==nil,'actual danger releases scoped medical claim')
        unchanged(v,check)
        local helperObserved
        v.context,helperObserved=refresh(v.medic,s,check)
        local directNeed=M.careNeed(v.patient)
        if M.canTreatNow(v.medic,helperObserved) and directNeed and directNeed.kind=='remove_glass' then
            local group=SC.Commands.peek(v.patient).group
            check(SC.Commands.issue(v.medicId,'set_group',{group=group},s.primary),'noncamp danger control joins the same ordinary group')
            check(M.sameCareGroup(v.medic,v.patient),'noncamp danger control has normal group eligibility')
            local okay,why=M.treat(v.medic,v.patient,v.context,{careKind=directNeed.kind,woundIndex=directNeed.woundIndex,careKey=directNeed.key})
            check(not okay and why=='danger_preempted' and M.peek(v.medic)==nil,'noncamp procedure refuses real patient-only current danger')
            unchanged(v,check)
            note('production_noncamp_patient_danger=real_patient_unsafe_helper_safe; surgery_refused=true')
        else
            note('production_noncamp_patient_danger=not_isolated; camp_real_danger_refusal_verified=true')
        end
        -- Retire only the specifically owned test zombie, never another
        -- population sweep and never any zombie path/movement/state override.
        v.zombie:removeFromWorld();v.zombie:removeFromSquare()
        local zombies=getCell():getZombieList();if zombies:contains(v.zombie) then zombies:remove(v.zombie) end
        v.zombie=nil
        note('production_visit_real_danger=unsafe_effects_refused; hold_claim_released=true; zombie_navigation_untouched=true')
        phase('acceptance-visits-cleanup')
    elseif s.phase=='acceptance-visits-cleanup' then
        local v=s.visitState
        check(now-s.at<20000,'disposable visit actors and jobs settle before next episode')
        if v.job and SC.BaseLife.job(v.job.id) and v.job.state~='completed' and v.job.state~='cancelled' then
            if not SC.BaseLife.cancelJob(v.job.id) then return end
        end
        for _,spec in ipairs({{v.medicId,'medic',v.medic},{v.patientId,'generalist',v.patient}}) do
            SC.BaseLife.assign(spec[1],spec[2],false)
            if not v.removed then v.removed={} end
            if not v.removed[spec[1]] then
                local okay=SC.Actor.remove(spec[3]);if not okay then return end
                v.removed[spec[1]]=true
            end
        end
        s.visitState={base=v.base,index=v.index+1}
        phase('acceptance-visits-spawn')
    end
end
return Probe
