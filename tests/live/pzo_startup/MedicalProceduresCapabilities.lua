-- SPDX-License-Identifier: MIT
-- Native Phase 2 capability evidence in an owned disposable save clone.
require 'TimedActions/ISRemoveBullet'
require 'TimedActions/ISRemoveGlass'
require 'TimedActions/ISCleanBurn'
require 'TimedActions/ISDisinfect'
require 'XpSystem/ISUI/ISHealthPanel'
local SC,s=SurvivorCompanion,{phase='menu',checks=0,notes={}}
local function write(name,value) local w=assert(getFileWriter(name,true,false));w:write(value);w:close() end
local function check(value,reason) s.checks=s.checks+1;assert(value,'medical procedures '..s.checks..': '..reason) end
local function note(value) s.notes[#s.notes+1]=value;print('SC_MEDICAL_PROCEDURE '..value) end
local function phase(name) s.phase,s.at=name,getTimestampMs();write('pzo-medical-procedures-progress.txt',name..'\n') end
local function primaryQueue()
    local q=ISTimedActionQueue.getTimedActionQueue(s.primary)
    return q.current,#q.queue
end
local function finish(okay,reason)
    if s.done then return end;s.done=true
    if s.multiplier then getGameTime():setMultiplier(s.multiplier) end
    local primaryUnchanged
    if s.primary then
        local current,count=primaryQueue()
        primaryUnchanged=current==s.primaryCurrent and count==s.primaryQueued
        if not primaryUnchanged then okay,reason=false,'primary queue changed' end
    end
    local text='result='..(okay and 'PASS' or 'FAIL')..'\nphase='..s.phase..'\nreason='..tostring(reason)
        ..'\nchecks='..s.checks..'\nprimary_queue_untouched='..tostring(primaryUnchanged)..'\n'..table.concat(s.notes,'\n')..'\n'
    write('pzo-medical-procedures-result.txt',text);print('SC_PZO_MEDICAL_PROCEDURES '..text)
end
local function rootItems()
    local result={};local items=s.actor:getInventory():getItems()
    for i=0,items:size()-1 do result[items:get(i)]=true end
    return result
end
local function freshPart(kind)
    s.actor:getBodyDamage():RestoreToFullHealth()
    local part=s.actor:getBodyDamage():getBodyPart(kind or BodyPartType.Foot_R)
    part:setAdditionalPain(0);part:setAlcoholLevel(0);part:setWoundInfectionLevel(0);part:setInfectedWound(false)
    return part
end
local function handlers(part)
    local captured
    local panel={character=s.actor,getAbsoluteX=function() return 0 end,getAbsoluteY=function() return 0 end,
        checkItems=function(_,rows) captured=rows;error('captured native health handlers') end}
    local previous=ISContextMenu.get
    ISContextMenu.get=function() return {} end
    pcall(ISHealthPanel.doBodyPartContextMenu,panel,part,0,0)
    ISContextMenu.get=previous
    check(type(captured)=='table' and #captured==13,'stock health handlers captured without player UI/queue')
    return {disinfect=captured[6],glass=captured[9],bullet=captured[12],burn=captured[13]}
end
local function accepts(handler,item)
    handler.items.ITEMS={};handler:checkItem(item);return #handler.items.ITEMS>0
end
local function effect(operation,expectedXp,expectedSync)
    local oldXp,oldSync=addXp,syncBodyPart
    local request,mask,xpCalls=nil,nil,0
    local before=s.actor:getXp():getXP(Perks.Doctor)
    addXp=function(actor,perk,amount,...)
        check(actor==s.actor and perk==Perks.Doctor,'stock XP belongs to exact companion')
        xpCalls=xpCalls+1;request=amount;return oldXp(actor,perk,amount,...)
    end
    syncBodyPart=function(part,value,...)
        check(part==operation.bodyPart,'stock sync belongs to exact native body part')
        mask=value;return oldSync(part,value,...)
    end
    local okay,result=pcall(operation.complete,operation)
    addXp,syncBodyPart=oldXp,oldSync
    check(okay and result==true,'stock native complete succeeds: '..tostring(result))
    check(mask==expectedSync,'stock body sync mask '..tostring(mask))
    check(expectedXp and xpCalls==1 and request==expectedXp or not expectedXp and xpCalls==0,'stock XP request matches procedure')
    local after=s.actor:getXp():getXP(Perks.Doctor)
    check(after>=before,'native Doctor XP does not decrease')
    return after-before
end
local function procedures()
    local actor,root=s.actor,s.actor:getInventory()
    local tweezers=assert(root:AddItem('Base.Tweezers'))
    local holder=assert(root:AddItem('Base.SutureNeedleHolder'))
    local lookalike=assert(root:AddItem('Base.ButterKnife'))
    local part=freshPart();part:setHaveBullet(true,0)
    local h=handlers(part)
    check(accepts(h.bullet,tweezers) and accepts(h.bullet,holder),'native bullet tools accept tweezers and suture holder')
    check(accepts(h.glass,tweezers) and accepts(h.glass,holder),'native glass tools accept tweezers and suture holder')
    check(not accepts(h.bullet,lookalike) and not accepts(h.glass,lookalike),'tool lookalikes are refused by native handlers')
    note('tools=ItemTag.REMOVE_BULLET/REMOVE_GLASS or Tweezers/SutureNeedleHolder; hands_not_allowed_by_LF')
    part:setBandaged(true,15,false,'Base.Bandage')
    check(not h.bullet:isInjured(),'native health handler rejects covered bullet treatment')
    local operation=ISRemoveBullet:new(actor,actor,part)
    check(operation:isValid(),'stock timed action alone does not enforce dressing/tool guard')
    part:setBandaged(false,0,false,nil);part:setAdditionalPain(0)
    local doctor=operation.doctorLevel
    local xp=effect(operation,20,0x40460108)
    check(not part:haveBullet() and part:getDeepWoundTime()>0,'bullet removal leaves native deep wound')
    check(math.abs(part:getAdditionalPain()-(80-doctor))<0.001,'bullet pain follows native Doctor level')
    check(root:contains(tweezers) and root:contains(holder),'bullet procedure keeps exact tools')
    note('bullet_pain='..part:getAdditionalPain()..'; doctor='..doctor..'; xp_delta='..xp..'; deep='..part:getDeepWoundTime())
    part=freshPart();part:setHaveGlass(true);part:setDeepWoundTime(12)
    h=handlers(part);part:setBandaged(true,15,false,'Base.Bandage')
    check(not h.glass:isInjured(),'native health handler rejects covered glass treatment')
    part:setBandaged(false,0,false,nil);part:setAdditionalPain(0)
    operation=ISRemoveGlass:new(actor,actor,part,false);doctor=operation.doctorLevel
    xp=effect(operation,15,0x00480000)
    check(not part:haveGlass() and part:getDeepWoundTime()>0,'glass removal clears exact flag and leaves wound')
    check(math.abs(part:getAdditionalPain()-(30-doctor))<0.001,'tool-assisted glass pain follows native number')
    check(root:contains(tweezers) and root:contains(holder),'glass procedure keeps exact tools')
    note('glass_pain='..part:getAdditionalPain()..'; doctor='..doctor..'; xp_delta='..xp)
    part=freshPart();part:setBurnTime(20);part:setNeedBurnWash(true)
    local washing=assert(root:AddItem('Base.Bandage'));local reserve=assert(root:AddItem('Base.Bandage'))
    local before=rootItems();h=handlers(part)
    check(accepts(h.burn,washing),'native burn cleaner requires bandagePower>=2')
    part:setBandaged(true,15,false,'Base.Bandage');check(not h.burn:isInjured(),'native burn handler rejects covered part')
    check(root:contains(washing) and root:contains(reserve),'separate cleaner and fresh redress exist before uncovering')
    part:setBandaged(false,0,false,nil);part:setAdditionalPain(0)
    operation=ISCleanBurn:new(actor,actor,washing,part);doctor=operation.doctorLevel
    xp=effect(operation,10,0x380400000)
    local replacement
    for item in pairs(rootItems()) do if not before[item] and item:getFullType()=='Base.BandageDirty' then
        check(not replacement,'burn produces exactly one dirty replacement');replacement=item
    end end
    check(not root:contains(washing) and replacement and root:contains(reserve),'native burn uses clean input once, creates dirty item, keeps separate fresh reserve')
    check(not part:isNeedBurnWash() and part:getBurnTime()>0,'burn wash clears need, preserves injury')
    check(math.abs(part:getAdditionalPain()-(60-doctor))<0.001,'burn pain follows native Doctor level')
    note('burn_pain='..part:getAdditionalPain()..'; xp_delta='..xp..'; clean_replaced_dirty=true; fresh_reserve_untouched=true; lastwash='..part:getLastTimeBurnWash())
end
local function disinfect()
    local actor,root=s.actor,s.actor:getInventory()
    local rubbing=assert(Fluid.Get('RubbingAlcohol'),'registered native rubbing alcohol fluid')
    local part=freshPart();part:setScratchTime(20);part:setInfectedWound(true);part:setWoundInfectionLevel(5)
    local wipes=assert(root:AddItem('Base.AlcoholWipes'));local uses=wipes:getCurrentUses()
    local h=handlers(part)
    check(accepts(h.disinfect,wipes),'native handler accepts alcoholPower4 drainable wipes')
    part:setBandaged(true,15,false,'Base.Bandage');check(not h.disinfect:isInjured(),'native disinfect handler requires uncovered injury')
    part:setBandaged(false,0,false,nil);part:setAdditionalPain(0)
    local operation=ISDisinfect:new(actor,actor,wipes,part);local doctor=operation.doctorLevel
    effect(operation,nil,0x00608200)
    check(wipes:getCurrentUses()==uses-1 and math.abs(part:getAlcoholLevel()-4)<0.001,'native wipes spend one use and add4 alcohol')
    check(math.abs(part:getAdditionalPain()-(52-doctor/2))<0.001,'native wipes pain matches alcohol power')
    check(math.abs(part:getWoundInfectionLevel()-5)<0.001,'disinfect completion does not immediately erase infection')
    note('wipes_power=4; uses_delta=1; pain='..part:getAdditionalPain()..'; infection_after_complete='..part:getWoundInfectionLevel())
    for _,amount in ipairs({0.149,0.15,0.151,0.3}) do
        part=freshPart();part:setScratchTime(20)
        local item=assert(root:AddItem('Base.Disinfectant'));local fluid=assert(item:getFluidContainer())
        fluid:Empty();fluid:addFluid(rubbing,amount)
        local actual=fluid:getAmount();local power=4*fluid:getProperties():getAlcohol()/actual
        check(actual>0,'native reagent has real measured fluid')
        h=handlers(part);local eligible=accepts(h.disinfect,item)
        operation=ISDisinfect:new(actor,actor,item,part);doctor=operation.doctorLevel
        effect(operation,nil,0x00608200)
        local delta=actual-fluid:getAmount()
        note('fluid_debug_nominal='..amount..'; actual='..actual..'; fraction_power='..power..'; actual_alcohol='..part:getAlcoholLevel()
            ..'; drainable='..tostring(item:IsDrainable())..'; legacy_power='..item:getAlcoholPower()..'; pain='..part:getAdditionalPain()..'; consumed='..delta)
        check(math.abs(part:getAlcoholLevel()-power)<0.001,'native fluid disinfect power uses actual concentration')
        check(math.abs(part:getAdditionalPain()-(power*13-doctor/2))<0.001,'native fluid disinfect pain matches concentration')
        if eligible then check(math.abs(delta-0.15)<0.0001,'eligible native fluid consumes exactly0.15L')
        else check(math.abs(delta)<0.0001,'ineligible low fluid demonstrates effect without spend if caller skips handler guard') end
        note('fluid_nominal='..amount..'; actual='..actual..'; handler_eligible='..tostring(eligible)..'; consumed='..delta..'; power='..power)
    end
    part=freshPart();part:setScratchTime(20)
    local diluted=assert(root:AddItem('Base.Disinfectant'));local fc=diluted:getFluidContainer()
    fc:Empty();fc:addFluid(rubbing,0.1);fc:addFluid(Fluid.Water,0.3)
    h=handlers(part);check(not accepts(h.disinfect,diluted),'native handler rejects diluted alcohol below40percent')
    note('native_fluid_threshold=alcoholFraction+0.001>=0.4 and amount>0.15; direct_complete_guard_required=true')
end
local function startEvolution()
    freshPart()
    local treated=s.actor:getBodyDamage():getBodyPart(BodyPartType.Foot_R)
    local control=s.actor:getBodyDamage():getBodyPart(BodyPartType.Foot_L)
    for _,part in ipairs({treated,control}) do
        part:setScratchTime(25);part:setInfectedWound(true);part:setWoundInfectionLevel(5)
        part:setBandaged(true,1000,false,'Base.Bandage');part:setAlcoholLevel(0)
    end
    -- Apply stock disinfect uncovered, then restore the separate fresh cover.
    treated:setBandaged(false,0,false,nil)
    local wipes=assert(s.actor:getInventory():AddItem('Base.AlcoholWipes'))
    effect(ISDisinfect:new(s.actor,s.actor,wipes,treated),nil,0x00608200)
    treated:setBandaged(true,1000,false,'Base.Bandage')
    local before,alcohol=treated:getWoundInfectionLevel(),treated:getAlcoholLevel()
    treated:DamageUpdate();control:DamageUpdate()
    check(treated:getWoundInfectionLevel()<before and treated:getAlcoholLevel()<alcohol,'actual BodyPart.DamageUpdate treats existing infection while spending alcohol')
    s.evolution={treated=treated,control=control,before=treated:getWoundInfectionLevel(),controlBefore=control:getWoundInfectionLevel(),
        alcoholBefore=treated:getAlcoholLevel(),started=getGameTime():getWorldAgeHours(),last=-1}
    s.multiplier=getGameTime():getTrueMultiplier()
    getGameTime():setMultiplier(20)
    phase('evolution')
end
local function evolution()
    local e=s.evolution;local elapsed=getGameTime():getWorldAgeHours()-e.started
    check(getTimestampMs()-s.at<180000,'two game-hour evolution completes within fixture deadline')
    local quarter=math.floor(elapsed*4)
    if quarter~=e.last then
        e.last=quarter
        note('evolution_hours='..elapsed..'; treated_infection='..e.treated:getWoundInfectionLevel()..'; untreated_infection='..e.control:getWoundInfectionLevel()
            ..'; alcohol='..e.treated:getAlcoholLevel()..'; health='..s.actor:getBodyDamage():getOverallBodyHealth())
    end
    if elapsed<2 then return end
    check(e.treated:getWoundInfectionLevel()<e.before and e.treated:getWoundInfectionLevel()<e.control:getWoundInfectionLevel(),'native alcohol genuinely reduces established infection over2 gamehours')
    check(e.treated:getAlcoholLevel()<e.alcoholBefore,'native alcohol effect is spent over time')
    note('alcohol_policy=genuine_treatment; do_not_repeat_while_alcohol_positive; recheck_persisting_infection_after_effect_exhaustion; minimum_repeat_2_game_hours')
    if SC_MEDICAL_PROCEDURES_ACCEPTANCE then
        getGameTime():setMultiplier(s.multiplier)
        phase('acceptance-procedures-start')
    else finish(true,'native procedure effects and alcohol evolution verified') end
end
Events.OnInitGlobalModData.Add(function() ModData.getOrCreate(SC.Identity.worldSaveKey).document={schema=SC.Identity.saveSchema,companions={},factionActors={}} end)
Events.OnMainMenuEnter.Add(function() MainScreen.continueLatestSave('Sandbox','PzoRestoreFixture') end)
local seen={}
Events.OnRenderTick.Add(function()
    local modal=MainScreen and MainScreen.instance and MainScreen.instance.checkSavefileModal
    if modal and modal.yes and not seen[modal] then seen[modal]=true;modal:onClick(modal.yes) end
end)
Events.OnGameStart.Add(function()
    SC.Scheduler.unregister('decision');s.primary=assert(getSpecificPlayer(0));s.primaryCurrent,s.primaryQueued=primaryQueue();phase('load')
end)
local function step()
    if s.done or s.phase=='menu' then return end
    if s.phase=='load' then
        if getTimestampMs()-s.at<12000 then return end
        check(SCBridge and PZOEngine and SC.Actor.checkBridge(true),'actual PZO and companion provider')
        local U=SC.GameplayUtil;local source=s.primary:getSquare();local spawn
        for r=1,8 do if not spawn then for dx=-r,r do for dy=-r,r do
            local square=getCell():getGridSquare(source:getX()+dx,source:getY()+dy,source:getZ())
            if square and U.isClearActorSpawnSquare(square)==true and square:isFree(false) then spawn=square;break end
        end if spawn then break end end end end
        check(spawn~=nil,'safe loaded native fixture spawn')
        s.ticket=assert(SC.Actor.beginSpawn(spawn,{recruited=true,identity={forename='Procedure',surname='Capabilities',gender='woman',outfit='Generic01'}}))
        phase('spawn')
    elseif s.phase=='spawn' then
        local actor,why=SC.Actor.pollSpawn(s.ticket)
        if not actor then check(why=='spawn_pending' and getTimestampMs()-s.at<15000,tostring(why));return end
        s.actor=actor
        local zombies,removed=getCell():getZombieList(),0
        for index=zombies:size()-1,0,-1 do
            local zombie=zombies:get(index)
            zombie:removeFromWorld();zombie:removeFromSquare()
            if zombies:contains(zombie) then zombies:remove(zombie) end
            removed=removed+1
        end
        note('fixture_loaded_zombies_removed_once='..removed..'; navigation_unchanged=true')
        if SC_MEDICAL_VISITS_DIAGNOSTIC_ONLY then
            note('diagnostic_only=visiting_care; clinical_and_capability_cases_not_run=true')
            phase('acceptance-visits-start')
        else phase('procedures') end
    elseif s.phase=='procedures' then procedures();phase('disinfect')
    elseif s.phase=='disinfect' then disinfect();phase('start-evolution')
    elseif s.phase=='start-evolution' then startEvolution()
    elseif s.phase=='evolution' then evolution()
    elseif string.find(s.phase,'acceptance-procedures-',1,true)==1 then
        s.proceduresProbe=s.proceduresProbe or require 'MedicalProceduresAcceptance'
        if s.proceduresProbe.step(s,check,note,phase)==true then phase('acceptance-visits-start') end
    elseif string.find(s.phase,'acceptance-visits-',1,true)==1 then
        s.visitsProbe=s.visitsProbe or require 'MedicalVisitsAcceptance'
        if s.visitsProbe.step(s,check,note,phase)==true then
            finish(true,SC_MEDICAL_VISITS_DIAGNOSTIC_ONLY and 'visiting care diagnostic only; full medical acceptance not run'
                or 'native Phase2 medical and visiting medic acceptance verified')
        end
    end
end
Events.OnTick.Add(function() if not s.done then local okay,why=pcall(step);if not okay then finish(false,why) end end end)
