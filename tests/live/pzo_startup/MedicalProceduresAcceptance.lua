-- SPDX-License-Identifier: MIT
-- Shipping self-care selection, owner, native visual and commit pipeline.
local Probe={}
local cases={
    {name='tool-protection-and-cancel',kind='remove_bullet',covered=true,mode='tools',fresh=1},
    {name='covered-missing-fresh',kind='remove_bullet',covered=true,mode='blocked',fresh=0,reason='no_clean_bandage'},
    {name='burn-needs-two-dressings',kind='clean_burn',covered=true,mode='blocked',fresh=1,reason='no_clean_dressing_for_burn'},
    {name='covered-bullet',kind='remove_bullet',covered=true,fresh=1},
    {name='uncovered-bullet',kind='remove_bullet',fresh=1},
    {name='covered-glass',kind='remove_glass',covered=true,fresh=1},
    {name='quiet-low-health-covered-glass',kind='remove_glass',covered=true,fresh=1,lowHealth=30},
    {name='uncovered-glass',kind='remove_glass',fresh=1},
    {name='covered-burn',kind='clean_burn',covered=true,fresh=3},
    {name='uncovered-burn',kind='clean_burn',fresh=3},
    {name='disinfect-low-fluid-refused',kind='disinfect_wound',covered=true,mode='blocked',fresh=1,reagent='lowfluid',reason='no_disinfectant'},
    {name='covered-disinfect-wipes',kind='disinfect_wound',covered=true,fresh=2,reagent='wipes'},
    {name='uncovered-disinfect-fluid',kind='disinfect_wound',fresh=2,reagent='fluid'},
}
local results={remove_bullet='bullet_removed',remove_glass='glass_removed',clean_burn='burn_cleaned',disinfect_wound='wound_disinfected'}
local function inventory(actor)
    local result={}
    for _,row in ipairs(assert(SurvivorCompanion.BandageWash.inventoryEntries(actor))) do result[row.item]=row.source end
    return result
end
local function refresh(s,check)
    local SC=SurvivorCompanion
    local context=SC.GameplayUtil.actorState(s.actor)
    local snapshot=SC.Senses.snapshot(s.actor,s.primary,context)
    check(type(snapshot)=='table' and snapshot.valid==true,'clinical acceptance observes actual loaded world')
    check(SC.Medical.canTreatNow(s.actor,snapshot)==true,'clinical fixture is actually semi-safe')
    return context
end
local function spawnSquare(s)
    local SC,U=SurvivorCompanion,SurvivorCompanion.GameplayUtil
    local origin=s.primary:getSquare();local room=origin:getRoom()
    local fallback
    for radius=1,10 do for dx=-radius,radius do for dy=-radius,radius do
        if math.abs(dx)==radius or math.abs(dy)==radius then
            local square=getCell():getGridSquare(origin:getX()+dx,origin:getY()+dy,origin:getZ())
            if square and U.isClearActorSpawnSquare(square) and square:isFree(false) then
                if square:getRoom()==room then return square end
                fallback=fallback or square
            end
        end
    end end end
    return fallback
end
local function protect(actor,item,key,check)
    local okay=SurvivorCompanion.PersonalItems.restoreMarker(item,{ownerId='native-medical-control',key=key,kind='medical'},true)
    check(okay and SurvivorCompanion.PersonalItems.isProtected(item,actor,'medical_consume'),'native fixture protection marker is authoritative')
end
local function unchanged(row,actor,check,label)
    local root=actor:getInventory()
    check(row.part:bandaged()==(row.case.covered==true),label..' leaves covering unchanged')
    if row.case.kind=='remove_bullet' then check(row.part:haveBullet(),label..' preserves lodged bullet') end
    if row.case.kind=='clean_burn' then check(row.part:isNeedBurnWash(),label..' preserves burn-care need') end
    if row.case.kind=='disinfect_wound' then
        check(row.part:getAlcoholLevel()==0 and row.part:isInfectedWound(),label..' preserves untreated infection')
        if row.fluid then check(math.abs(row.fluid:getAmount()-row.amount)<0.0001,label..' preserves exact reagent amount') end
    end
    for _,item in ipairs(row.fresh) do check(root:contains(item),label..' preserves exact fresh supply') end
end
local function setup(s,check,note)
    local SC,M=SurvivorCompanion,SurvivorCompanion.Medical
    local state=s.procedureState;local spec=cases[state.index]
    local actor,root=s.actor,s.actor:getInventory()
    for item,container in pairs(inventory(actor)) do
        if M.dressingRank(item,true) or item:getFluidContainer() or item:getType()=='Tweezers'
            or item:getType()=='SutureNeedleHolder' then container:Remove(item) end
    end
    actor:getBodyDamage():RestoreToFullHealth()
    local part=actor:getBodyDamage():getBodyPart(BodyPartType.Foot_R)
    part:setAdditionalPain(0);part:setAlcoholLevel(0)
    if spec.kind=='remove_bullet' then part:setHaveBullet(true,0)
    elseif spec.kind=='remove_glass' then part:setHaveGlass(true);part:setDeepWoundTime(12)
    elseif spec.kind=='clean_burn' then part:setBurnTime(30);part:setNeedBurnWash(true)
    else part:setScratchTime(25);part:setInfectedWound(true);part:setWoundInfectionLevel(5) end
    -- Isolate elective care from the separate bleeding-first episode.
    part:setBleeding(false);part:setBleedingTime(0)
    if spec.covered then part:setBandaged(true,15,false,'Base.Bandage') end
    if spec.lowHealth then
        actor:getBodyDamage():ReduceGeneralHealth(100-spec.lowHealth)
        actor:getBodyDamage():calculateOverallHealth()
    end
    local row={case=spec,part=part,fresh={},before=inventory(actor),doctor=actor:getPerkLevel(Perks.Doctor),xpBefore=actor:getXp():getXP(Perks.Doctor)}
    for index=1,spec.fresh do row.fresh[index]=assert(root:AddItem('Base.Bandage')) end
    if spec.mode~='tools' and (spec.kind=='remove_bullet' or spec.kind=='remove_glass') then
        row.tool=assert(root:AddItem('Base.Tweezers'))
    end
    if spec.reagent=='wipes' then
        row.reagent=assert(root:AddItem('Base.AlcoholWipes'));row.uses=row.reagent:getCurrentUses()
    elseif spec.reagent=='fluid' or spec.reagent=='lowfluid' then
        if spec.reagent=='fluid' then
            row.protected=assert(root:AddItem('Base.Disinfectant'))
            protect(actor,row.protected,'protected-disinfectant',check)
            row.protectedAmount=row.protected:getFluidContainer():getAmount()
        end
        row.reagent=assert(root:AddItem('Base.Disinfectant'))
        local fluid=row.reagent:getFluidContainer();fluid:Empty();fluid:addFluid(assert(Fluid.Get('RubbingAlcohol')),spec.reagent=='lowfluid' and 0.149 or 0.3)
        row.fluid,row.amount=fluid,fluid:getAmount()
    end
    if spec.reagent=='lowfluid' then
        -- Phase 3 correctly prefers antibiotics when the only reagent is too
        -- small. Start an actual native course in this isolated fixture so
        -- the original disinfection preflight remains the selected need.
        local dose=assert(root:AddItem('Base.Antibiotics'))
        check(actor:Eat(dose,1,false)==true and dose:getContainer()==nil and actor:getReduceInfectionPower()==50,
            'isolated low-fluid fixture starts one real native antibiotic course without a simulated active flag')
        note('inherited_lowfluid_isolation=one_native_antibiotic_consumed; active_course=true; original_disinfect_refusal_preserved=true')
    end
    row.before=inventory(actor)
    M.invalidate(actor)
    if spec.lowHealth then
        local assessment=M.assess(actor)
        check(assessment.alive and assessment.health<40 and part:bandaged() and not part:bleeding(),
            'quiet low-health covered native patient remains alive without active bleeding')
    end
    local need=M.careNeed(actor)
    check(need and need.kind==spec.kind,'shipping selector identifies '..spec.name)
    row.options={careKind=need.kind,woundIndex=need.woundIndex,careKey=need.key}
    state.row=row
    return row
end
local function verify(s,check,note)
    local SC,M=SurvivorCompanion,SurvivorCompanion.Medical
    local row,actor=s.procedureState.row,s.actor
    local root=actor:getInventory();local kind=row.case.kind
    check(row.part:bandaged(),'successful surgical procedure finishes with fresh covering')
    check(M.pendingCare(actor)==nil and M.treatmentHolder(actor)==nil,'successful care releases pending transaction and patient claim')
    local spent=0
    for _,item in ipairs(row.fresh) do if not root:contains(item) then spent=spent+1 end end
    check(spent==(kind=='clean_burn' and 2 or 1),'exact fresh consumption for '..row.case.name)
    local returned,dirty=0,0
    for item in pairs(inventory(actor)) do
        if not row.before[item] and item:getFullType()=='Base.Bandage' then returned=returned+1 end
        if not row.before[item] and item:getFullType()=='Base.BandageDirty' then dirty=dirty+1 end
    end
    check(returned==(row.case.covered and 1 or 0),'previous covering returns exactly once for '..row.case.name)
    if row.tool then check(root:contains(row.tool),'exact native medical tool survives procedure') end
    if kind=='remove_bullet' then
        check(not row.part:haveBullet() and row.part:getDeepWoundTime()>0,'shipping bullet removal leaves native deep wound under fresh dressing')
    elseif kind=='remove_glass' then
        check(not row.part:haveGlass() and row.part:getDeepWoundTime()>0,'shipping glass removal preserves injury under fresh dressing')
    elseif kind=='clean_burn' then
        check(not row.part:isNeedBurnWash() and row.part:getBurnTime()>0 and dirty==1,'shipping burn cleanup creates one actual dirty replacement')
    else
        check(row.part:getAlcoholLevel()>0 and row.part:getWoundInfectionLevel()>0,'shipping disinfection adds native alcohol without invented instant cure')
        if row.fluid then
            check(math.abs(row.amount-row.fluid:getAmount()-0.15)<0.0001,'shipping disinfect consumes exact0.15L dose')
            check(math.abs(row.protected:getFluidContainer():getAmount()-row.protectedAmount)<0.0001,'protected native disinfectant remains untouched')
        else check(row.reagent:getCurrentUses()==row.uses-1,'shipping wipes spend one exact native use') end
        -- Leave a real spare dressing/reagent available. The active alcohol and
        -- cooldown must prevent a second expensive treatment after pacing.
        row.repeatUses=row.reagent:getCurrentUses()
        row.repeatAmount=row.fluid and row.fluid:getAmount()
        row.repeatInventory=inventory(actor)
    end
    check(row.part:getAdditionalPain()>0,'shipping native procedure adds actual pain')
    if kind~='disinfect_wound' then
        check(actor:getXp():getXP(Perks.Doctor)>row.xpBefore and actor:isLocalPlayer()==false,
            'shipping native '..kind..' awards normally scaled First Aid without actor identity overrides')
    end
    note('production_procedure='..row.case.name..'; result='..results[kind]..'; exactfreshspent='..spent
        ..'; oldcoverreturned='..returned..'; nativepain='..row.part:getAdditionalPain()..'; primary_queue_untouched=true')
end
function Probe.step(s,check,note,phase)
    local SC,M,N=SurvivorCompanion,SurvivorCompanion.Medical,SurvivorCompanion.NativeActions
    local now=getTimestampMs()
    if s.phase=='acceptance-procedures-start' then
        s.procedureState={index=1,actors={},capabilityActor=s.actor}
        phase('acceptance-procedures-spawn')
    elseif s.phase=='acceptance-procedures-spawn' then
        local state=s.procedureState
        if state.index>#cases then s.actor=state.capabilityActor;return true end
        if not state.ticket then
            local square=assert(spawnSquare(s),'loaded safe isolated clinical spawn')
            state.ticket=assert(SC.Actor.beginSpawn(square,{recruited=true,identity={forename='Clinical',surname='Fixture',gender='woman',outfit='Generic01'}}))
        end
        local actor,why=SC.Actor.pollSpawn(state.ticket)
        if not actor then check(why=='spawn_pending' and now-s.at<20000,'clinical actor spawn: '..tostring(why));return end
        state.ticket=nil;s.actor=actor;state.actors[#state.actors+1]=actor
        local commands=SC.Commands.peek(actor);commands.order='stay'
        phase('acceptance-procedures-setup')
    elseif s.phase=='acceptance-procedures-setup' then
        if N.pacingStatus(s.actor) then check(now-s.at<30000,'prior native action pacing settles');return end
        refresh(s,check)
        local row=setup(s,check,note)
        local context=refresh(s,check)
        local okay,why=M.treat(s.actor,s.actor,context,row.options)
        if row.case.mode=='blocked' then
            check(not okay and why==row.case.reason and M.peek(s.actor)==nil,'shipping preflight refuses '..row.case.name..': '..tostring(why))
            unchanged(row,s.actor,check,row.case.name)
            note('production_refusal='..row.case.name..'; reason='..tostring(why)..'; body_and_supplies_unchanged=true')
            phase('acceptance-procedures-next')
        elseif row.case.mode=='tools' then
            check(not okay and why=='no_tweezers','shipping procedure refuses missing tools')
            unchanged(row,s.actor,check,'missing tool')
            row.protected=assert(s.actor:getInventory():AddItem('Base.Tweezers'))
            protect(s.actor,row.protected,'protected-tweezers',check)
            okay,why=M.treat(s.actor,s.actor,context,row.options)
            check(not okay and why=='no_tweezers','shipping procedure refuses protected tool lookalike')
            unchanged(row,s.actor,check,'protected tool')
            row.tool=assert(s.actor:getInventory():AddItem('Base.Tweezers'))
            okay,why=M.treat(s.actor,s.actor,context,row.options)
            check(okay and M.peek(s.actor),'shipping care starts with exact eligible tool before cancellation')
            row.cancelled=M.cancel(s.actor,'native_medical_precommit_cancel')
            phase('acceptance-procedures-cancel')
        else
            check(okay and M.peek(s.actor),'shipping native visual starts for '..row.case.name..': '..tostring(why))
            phase('acceptance-procedures-running')
        end
    elseif s.phase=='acceptance-procedures-cancel' then
        local row=s.procedureState.row
        if M.peek(s.actor) then
            check(now-s.at<15000,'precommit cancellation releases native owner')
            M.cancel(s.actor,'native_medical_precommit_cancel');return
        end
        unchanged(row,s.actor,check,'precommit cancel')
        check(M.pendingCare(s.actor)==nil and M.treatmentHolder(s.actor)==nil,'cancel clears patient claim and pending care')
        note('production_precommit_cancel=body_and_exact_supplies_unchanged; patient_claim_released=true')
        phase('acceptance-procedures-next')
    elseif s.phase=='acceptance-procedures-running' then
        check(now-s.at<60000,'shipping '..s.procedureState.row.case.name..' finishes within60 seconds')
        local context=refresh(s,check)
        local okay,why=M.treat(s.actor,s.actor,context,s.procedureState.row.options)
        if M.peek(s.actor) then check(okay,'shipping procedure retains own active transaction: '..tostring(why));return end
        check(okay and why==results[s.procedureState.row.case.kind],'shipping operation reports verified native result: '..tostring(why))
        verify(s,check,note)
        phase(s.procedureState.row.case.kind=='disinfect_wound' and 'acceptance-procedures-repeat' or 'acceptance-procedures-next')
    elseif s.phase=='acceptance-procedures-repeat' then
        check(now-s.at<30000,'disinfect result pacing settles before repeat guard')
        if N.pacingStatus(s.actor) then return end
        local row=s.procedureState.row;local context=refresh(s,check)
        local okay=M.treat(s.actor,s.actor,context,row.options)
        check(not okay and M.peek(s.actor)==nil,'shipping disinfection cannot repeat while native alcohol is active')
        if row.fluid then check(math.abs(row.fluid:getAmount()-row.repeatAmount)<0.0001,'repeat guard preserves remaining fluid')
        else check(row.reagent:getCurrentUses()==row.repeatUses,'repeat guard preserves wipe uses') end
        local current=inventory(s.actor)
        for item in pairs(row.repeatInventory) do check(current[item]~=nil,'repeat guard preserves every existing exact carried identity') end
        note('production_disinfect_repeat_guard=passed; real_alcohol='..row.part:getAlcoholLevel())
        if row.fluid then
            row.retryStarted=getGameTime():getWorldAgeHours()
            row.priorMultiplier=getGameTime():getTrueMultiplier()
            getGameTime():setMultiplier(20)
            phase('acceptance-procedures-exhaust')
        else phase('acceptance-procedures-next') end
    elseif s.phase=='acceptance-procedures-exhaust' then
        local row=s.procedureState.row
        check(now-s.at<180000,'actual native alcohol exhaustion/cooldown interval completes')
        refresh(s,check)
        local elapsed=getGameTime():getWorldAgeHours()-row.retryStarted
        if elapsed<2.02 then return end
        getGameTime():setMultiplier(row.priorMultiplier)
        check(row.part:getAlcoholLevel()<=0 and row.part:isInfectedWound(),'native effect is exhausted while infection still needs care')
        local need=M.careNeed(s.actor)
        check(need and need.kind=='disinfect_wound','shipping selector permits legitimate disinfect retry after2gamehours')
        row.retryOptions={careKind=need.kind,woundIndex=need.woundIndex,careKey=need.key}
        for _,item in ipairs(row.fresh) do if s.actor:getInventory():contains(item) then row.retryFresh=item;break end end
        check(row.retryFresh~=nil,'legitimate repeat retains an exact separate fresh dressing')
        row.retryAmount=row.fluid:getAmount()
        local okay,why=M.treat(s.actor,s.actor,refresh(s,check),row.retryOptions)
        check(okay and M.peek(s.actor),'shipping retry starts after native exhaustion: '..tostring(why))
        note('production_disinfect_retry_hours='..elapsed..'; alcohol_before_retry='..row.part:getAlcoholLevel())
        phase('acceptance-procedures-retry-running')
    elseif s.phase=='acceptance-procedures-retry-running' then
        local row=s.procedureState.row
        check(now-s.at<60000,'legitimate native disinfect retry completes')
        local okay,why=M.treat(s.actor,s.actor,refresh(s,check),row.retryOptions)
        if M.peek(s.actor) then check(okay,'legitimate retry retains exact transaction: '..tostring(why));return end
        check(okay and why=='wound_disinfected' and row.part:getAlcoholLevel()>0,'legitimate retry reports actual native disinfection')
        check(math.abs(row.retryAmount-row.fluid:getAmount()-0.15)<0.0001,'legitimate repeat consumes final nominal0.15L exactly once')
        check(not s.actor:getInventory():contains(row.retryFresh) and row.part:bandaged(),'legitimate repeat consumes its reserved exact fresh covering')
        check(M.pendingCare(s.actor)==nil and M.treatmentHolder(s.actor)==nil,'legitimate repeat releases patient and transaction')
        note('production_disinfect_retry=one_verified_native_dose_after_exhaustion; final_nominal0.15L_spent=true')
        phase('acceptance-procedures-next')
    elseif s.phase=='acceptance-procedures-next' then
        check(M.peek(s.actor)==nil and M.pendingCare(s.actor)==nil,'clinical episode settles before next isolated actor')
        local removed,why=SC.Actor.remove(s.actor)
        if removed~=true then
            check(now-s.at<20000,'disposable clinical actor cleanup settles: '..tostring(why))
            return
        end
        s.procedureState.index=s.procedureState.index+1
        phase('acceptance-procedures-spawn')
    end
end
return Probe
