-- SPDX-License-Identifier: MIT
-- Native Phase 0 evidence only; source save, player queue and installation stay owned by the user.
require 'TimedActions/ISStitch'
require 'TimedActions/ISTakePillAction'
require 'TimedActions/ISEatFoodAction'
require 'XpSystem/ISUI/ISHealthPanel'
local SC,s=SurvivorCompanion,{phase='menu',checks=0,notes={},actors={}}
local function write(name,value) local w=assert(getFileWriter(name,true,false));w:write(value);w:close() end
local function check(value,reason) s.checks=s.checks+1;assert(value,'medical phase3 '..s.checks..': '..reason) end
local function note(value) s.notes[#s.notes+1]=value;print('SC_MEDICAL_PHASE3 '..value) end
local function phase(name) s.phase,s.at=name,getTimestampMs();write('pzo-medical-phase3-progress.txt',name..'\n') end
local function finish(okay,reason)
    if s.done then return end;s.done=true
    if s.multiplier then getGameTime():setMultiplier(s.multiplier) end
    local queue=s.primary and ISTimedActionQueue.getTimedActionQueue(s.primary)
    local untouched=queue and queue.current==s.primaryCurrent and #queue.queue==s.primaryQueued
    if not untouched then okay,reason=false,'primary queue changed' end
    local text='result='..(okay and 'PASS' or 'FAIL')..'\nphase='..s.phase..'\nreason='..tostring(reason)
        ..'\nchecks='..s.checks..'\nprimary_queue_untouched='..tostring(untouched)..'\n'..table.concat(s.notes,'\n')..'\n'
    write('pzo-medical-phase3-result.txt',text);print('SC_PZO_MEDICAL_PHASE3 '..text)
end
local function reset(actor)
    actor:getBodyDamage():RestoreToFullHealth();actor:setPainEffect(0);actor:setPainDelta(0)
    actor:getBodyDamage():setPainReduction(0);actor:setReduceInfectionPower(0)
    local part=actor:getBodyDamage():getBodyPart(BodyPartType.Foot_R)
    part:setAdditionalPain(0);part:setAlcoholLevel(0);part:setWoundInfectionLevel(0);part:setInfectedWound(false)
    return part
end
local function removeKinds(actor,kinds)
    local root=actor:getInventory();local items=root:getItems()
    for i=items:size()-1,0,-1 do if kinds[items:get(i):getFullType()] then root:Remove(items:get(i)) end end
end
local function stitch()
    local actor,root=s.actor,s.actor:getInventory()
    local kinds={['Base.Thread']=true,['Base.Needle']=true,['Base.SutureNeedle']=true,['Base.SutureNeedleHolder']=true}
    for _,case in ipairs({{kind='thread',holder=false,roll=1},{kind='thread',holder=true,roll=0},{kind='suture',holder=false,roll=1}}) do
        removeKinds(actor,kinds)
        local part=reset(actor);part:setDeepWounded(true);part:setDeepWoundTime(15);part:setBleedingTime(12);part:setGetStitchXp(true)
        local needle=assert(root:AddItem(case.kind=='thread' and 'Base.Needle' or 'Base.SutureNeedle'))
        local spent=case.kind=='thread' and assert(root:AddItem('Base.Thread')) or needle
        local holder=case.holder and assert(root:AddItem('Base.SutureNeedleHolder')) or nil
        local before=spent:getCurrentUses();local needleBefore=needle:getCurrentUses();local xpBefore=actor:getXp():getXP(Perks.Doctor)
        local operation=ISStitch:new(actor,actor,spent,part,true);local doctor=operation.doctorLevel
        local base=(case.kind=='suture' or holder) and 10 or 20
        check(operation:getDuration()==((base==10 and 150 or 200)-doctor*4),'stock stitch duration follows tool and Doctor')
        local oldRand,oldFloat,oldXp,oldSync=ZombRand,ZombRandFloat,addXp,syncBodyPart
        local request,rollLimit,floatMin,floatMax,sync,xpCalls=nil,nil,nil,nil,nil,0
        ZombRand=function(limit) rollLimit=limit;return case.roll end
        ZombRandFloat=function(a,b) floatMin,floatMax=a,b;return 3 end
        addXp=function(who,perk,amount,...)
            check(who==actor and perk==Perks.Doctor,'native stitch XP targets exact helper')
            request=amount;xpCalls=xpCalls+1;return oldXp(who,perk,amount,...)
        end
        syncBodyPart=function(p,mask,...) check(p==part,'native stitch sync exact part');sync=mask;return oldSync(p,mask,...) end
        local okay,result=pcall(operation.complete,operation)
        ZombRand,ZombRandFloat,addXp,syncBodyPart=oldRand,oldFloat,oldXp,oldSync
        check(okay and result==true,'stock ISStitch completes: '..tostring(result))
        check(part:stitched() and not part:isDeepWounded() and not part:bleeding() and part:getDeepWoundTime()==0 and part:getBleedingTime()==0,'stock stitch clears native deep wound and bleeding')
        check(math.abs(part:getStitchTime()-(1+doctor)/2*3)<0.001,'native stitchTime uses proved random range')
        check(floatMin==2 and floatMax==5 and rollLimit==5+doctor*2.5,'stock stitch random and infection roll exact arguments')
        check(part:isInfectedWound()==(case.roll==0),'native infection roll boundary affects real wound')
        check(math.abs(part:getAdditionalPain()-math.max(0,base-doctor))<0.001,'native stitch pain exact vanilla amount')
        check(request==15 and xpCalls==1 and sync==0x00570188,'native stitch XP15 request and sync mask')
        if case.kind=='thread' then
            check(spent:getCurrentUses()==before-1 and root:contains(needle) and needle:getCurrentUses()==needleBefore,'native stitching debits one exact thread use and keeps needle')
        else check(not root:contains(spent),'native suture needle consumed once') end
        if holder then check(root:contains(holder),'native holder retained') end
        note('stitch_case='..case.kind..'; holder='..tostring(case.holder)..'; doctor='..doctor..'; duration='..operation:getDuration()
            ..'; pain='..part:getAdditionalPain()..'; stitch_time='..part:getStitchTime()..'; xp_request='..request
            ..'; xp_actual='..(actor:getXp():getXP(Perks.Doctor)-xpBefore)..'; thread_uses_before='..before..'; uses_after='..spent:getCurrentUses())
        part:setBandaged(true,100,false,'Base.Bandage');check(part:getStitchTime()>0,'fresh cover preserves native stitches')
    end
    reset(actor)
end
local function xpProof()
    local actor=s.actor;local xp=actor:getXp()
    xp:setXPToLevel(Perks.Doctor,0)
    local perks=actor:getPerkList()
    local function doctorInfoPresent()
        for index=0,perks:size()-1 do if perks:get(index).perk==Perks.Doctor then return true end end
        return false
    end
    for index=perks:size()-1,0,-1 do local info=perks:get(index);if info.perk==Perks.Doctor then perks:remove(info) end end
    local before=xp:getXP(Perks.Doctor)
    check(before==0 and actor:getPerkLevel(Perks.Doctor)==0 and not doctorInfoPresent(),'native fractional-XP fixture starts Doctor0 without PerkInfo')
    local primary=getSpecificPlayer(0);local actorSlot=actor:getPlayerNum();local primarySlot=primary:getPlayerNum()
    check(primary==s.primary and actor~=primary and actor:isLocalPlayer()==false,'native XP proof starts on exact nonlocal companion')
    xp:AddXP(Perks.Doctor,15)
    local wrapped=xp:getXP(Perks.Doctor)
    check(wrapped==before,'native two-argument XP wrapper ignores nonlocal companion without identity override')
    xp:AddXP(Perks.Doctor,15,true,true,false,false)
    local after=xp:getXP(Perks.Doctor);local delta=after-wrapped
    check(delta>0 and delta==delta and delta<1000,'native Lua-exposed six-argument XP overload awards normally scaled First Aid')
    check(actor:getPerkLevel(Perks.Doctor)==0 and not doctorInfoPresent(),'native fractional Doctor XP exists in XP map before any PerkInfo')
    check(actor:isLocalPlayer()==false and getSpecificPlayer(0)==primary and primary==s.primary
        and actor:getPlayerNum()==actorSlot and primary:getPlayerNum()==primarySlot,'native XP overload preserves companion and primary player identities')
    note('native_xp_overload_proof: base_request=15; flags=true,true,false,false; two_argument_delta='..(wrapped-before)
        ..'; six_argument_delta='..delta..'; default_unboosted_expected=3.75; actual_Doctor_level='..actor:getPerkLevel(Perks.Doctor)
        ..'; companion_local=false; companion_slot='..actorSlot..'; primary_slot='..primarySlot..'; primary_identity_unchanged=true; no_identity_override=true')
    local record=assert(SC.Registry.byId(SC.GameplayUtil.idOf(actor)))
    local captured,why=SC.Persistence.captureRecord(record)
    check(captured and type(captured.skills)=='table','native fractional XP captureRecord succeeds: '..tostring(why))
    local savedDoctor
    for _,entry in ipairs(captured.skills) do if entry.id=='Doctor' then savedDoctor=entry end end
    check(savedDoctor and savedDoctor.level==0 and math.abs(savedDoctor.xp-after)<0.00001,
        'native capture includes positive fractional Doctor0 XP absent from PerkInfo')
    xp:setXPToLevel(Perks.Doctor,0)
    check(xp:getXP(Perks.Doctor)==0,'native XP reset creates real restore precondition')
    local restored,reason=SC.Persistence._applySkillsForTests(actor,captured.skills)
    check(restored and math.abs(xp:getXP(Perks.Doctor)-savedDoctor.xp)<0.00001,
        'native fractional Doctor XP restores exactly without applying multipliers twice: '..tostring(reason))
    restored,reason=SC.Persistence._applySkillsForTests(actor,captured.skills)
    check(restored and math.abs(xp:getXP(Perks.Doctor)-savedDoctor.xp)<0.00001,
        'reapplying saved native skills cannot duplicate fractional Doctor XP: '..tostring(reason))
    check(actor:isLocalPlayer()==false and getSpecificPlayer(0)==primary and actor:getPlayerNum()==actorSlot
        and primary:getPlayerNum()==primarySlot,'native skill capture/restore preserves all actor and player identities')
    note('native_xp_persistence_proof: Doctor_level=0; PerkInfo_absent_at_capture=true; captured_xp='..savedDoctor.xp
        ..'; restored_xp='..xp:getXP(Perks.Doctor)..'; repeated_restore_exact=true; multipliers_not_reapplied=true; player_identity_unchanged=true')
    local threshold=PerkFactory.getPerk(Perks.Doctor):getTotalXpForLevel(1)
    local needed=threshold-xp:getXP(Perks.Doctor)
    check(needed>0,'native earned-level fixture starts below actual Doctor1 threshold')
    -- A native XP award earns the level at its exact engine threshold. Flat
    -- fixture awards isolate the boundary; production surgery keeps all normal
    -- descriptor/trait/book/sandbox modifiers enabled as proved above.
    xp:AddXP(Perks.Doctor,needed,true,false,false,false)
    check(actor:getPerkLevel(Perks.Doctor)==1 and math.abs(xp:getXP(Perks.Doctor)-threshold)<0.00001,
        'native XP award actually earns Doctor1 at the exact engine XP boundary')
    local function earnedRoundtrip(label)
        local saved,captureReason=SC.Persistence.captureRecord(record)
        check(saved and type(saved.skills)=='table','native earned '..label..' capture succeeds: '..tostring(captureReason))
        local doctor
        for _,entry in ipairs(saved.skills) do if entry.id=='Doctor' then doctor=entry end end
        check(doctor and doctor.level==1 and math.abs(doctor.xp-xp:getXP(Perks.Doctor))<0.00001,
            'native earned '..label..' capture preserves actual Doctor1 and exact XP')
        actor:setPerkLevelDebug(Perks.Doctor,0);xp:setXPToLevel(Perks.Doctor,0)
        check(actor:getPerkLevel(Perks.Doctor)==0 and xp:getXP(Perks.Doctor)==0,'native earned '..label..' restore starts from real level0/XP0')
        for pass=1,2 do
            local okay,restoreReason=SC.Persistence._applySkillsForTests(actor,saved.skills)
            check(okay and actor:getPerkLevel(Perks.Doctor)==1 and math.abs(xp:getXP(Perks.Doctor)-doctor.xp)<0.00001,
                'native earned '..label..' restore '..pass..' preserves level and exact XP without duplicate modifiers: '..tostring(restoreReason))
        end
        note('native_earned_xp_persistence: case='..label..'; native_award_earned_level=1; captured_level='..doctor.level
            ..'; captured_xp='..doctor.xp..'; restored_level='..actor:getPerkLevel(Perks.Doctor)..'; restored_xp='..xp:getXP(Perks.Doctor)
            ..'; twice_exact=true; no_identity_override=true')
    end
    earnedRoundtrip('exact_boundary')
    xp:AddXP(Perks.Doctor,0.375,true,false,false,false)
    check(actor:getPerkLevel(Perks.Doctor)==1 and math.abs(xp:getXP(Perks.Doctor)-(threshold+0.375))<0.00001,
        'native earned Doctor1 retains an actual fractional XP remainder')
    earnedRoundtrip('fractional_remainder')
    local baselineOkay,baselineReason=SC.Persistence._applySkillsForTests(actor,captured.skills)
    check(baselineOkay and actor:getPerkLevel(Perks.Doctor)==0 and math.abs(xp:getXP(Perks.Doctor)-savedDoctor.xp)<0.00001,
        'native fixture restores its Doctor0 fractional baseline before surgical acceptance: '..tostring(baselineReason))
    check(actor:isLocalPlayer()==false and getSpecificPlayer(0)==primary and actor:getPlayerNum()==actorSlot
        and primary:getPlayerNum()==primarySlot,'native earned-level restore keeps companion/player identities and slots')
end
local function prepareMedicine()
    local actor,helper,control=s.actor,s.helper,s.control
    local part=reset(actor);local controlPart=reset(control);reset(helper)
    for _,who in ipairs({actor,control}) do
        local parts=who:getBodyDamage():getBodyParts()
        for i=0,parts:size()-1 do parts:get(i):setAdditionalPain(20) end
        who:getStats():set(CharacterStat.PAIN,65);who:getMoodles():Update()
    end
    for _,p in ipairs({part,controlPart}) do
        p:setScratchTime(25);p:setInfectedWound(true);p:setWoundInfectionLevel(5);p:setAlcoholLevel(0);p:setBandaged(true,1000,false,'Base.Bandage')
    end
    s.medicineParts={part,controlPart}
    phase('medicine-ready')
end
local function startMedicine()
    local actor,helper,control=s.actor,s.helper,s.control
    local part,controlPart=s.medicineParts[1],s.medicineParts[2]
    local helperRoot=helper:getInventory()
    local pills=assert(helperRoot:AddItem('Base.Pills'));local pillReserve=assert(helperRoot:AddItem('Base.Pills'))
    local antibiotic=assert(helperRoot:AddItem('Base.Antibiotics'));local antibioticReserve=assert(helperRoot:AddItem('Base.Antibiotics'))
    local uses=pills:getCurrentUses();local reserveUses=pillReserve:getCurrentUses();local foodUses=antibiotic:getCurrentUses()
    check(antibiotic:getReduceInfectionPower()==50 and antibiotic:getHungerChange()==0,'native antibiotic food has power50 and no hunger value')
    local beforeMoodle=actor:getMoodles():getMoodleLevel(MoodleType.PAIN)
    check(beforeMoodle>=2,'real native pain moodle is at least2 before pill')
    actor:getBodyDamage():JustTookPill(pills)
    check(pills:getCurrentUses()==uses-1 and pillReserve:getCurrentUses()==reserveUses,'native helper-carried pill debits exact dose once')
    check(math.abs(actor:getPainEffect()-5400)<0.001 and math.abs(actor:getPainDelta()-0.45)<0.001,'native companion pill starts painEffect5400 and painDelta0.45')
    check(actor:getBodyDamage():getPainReduction()==0 and helper:getPainEffect()==0,'painEffect belongs to patient; food painReduction stays zero')
    actor:getBodyDamage():setInfected(true)
    local operation=ISEatFoodAction:new(actor,antibiotic,1)
    check(operation:complete()==true,'native eat path accepts exact helper-carried antibiotic for patient')
    check(actor:getReduceInfectionPower()==50 and helper:getReduceInfectionPower()==0,'native antibiotic effect belongs to exact patient')
    check(not helperRoot:contains(antibiotic) and helperRoot:contains(antibioticReserve),'native eat consumes exactly one antibiotic; reserve stays')
    check(actor:getBodyDamage():isInfected(),'native antibiotic does not cure Knox on completion')
    note('medicine_start: pills_uses='..uses..'->'..pills:getCurrentUses()..'; antibiotic_uses='..foodUses..'->'..antibiotic:getCurrentUses()
        ..'; antibiotic_container='..tostring(antibiotic:getContainer())..'; patient_pain_moodle='..beforeMoodle..'; pain_effect='..actor:getPainEffect()
        ..'; pain_delta='..actor:getPainDelta()..'; food_pain_reduction='..actor:getBodyDamage():getPainReduction()
        ..'; antibiotic_power='..actor:getReduceInfectionPower()..'; native_eat_duration='..operation:getDuration()..'; helper_supply=true')
    s.medicine={part=part,controlPart=controlPart,pills=pills,uses=pills:getCurrentUses(),pillReserve=pillReserve,reserveUses=reserveUses,
        antibioticReserve=antibioticReserve,beforeMoodle=beforeMoodle,beforePain=actor:getStats():get(CharacterStat.PAIN),started=getGameTime():getWorldAgeHours(),last=-1,
        minimumMoodle=beforeMoodle,minimumPain=actor:getStats():get(CharacterStat.PAIN)}
    s.multiplier=getGameTime():getTrueMultiplier();getGameTime():setMultiplier(100);phase('medicine-evolution')
end
local function evolution()
    local e=s.medicine;local actor,control=s.actor,s.control;local elapsed=getGameTime():getWorldAgeHours()-e.started
    check(getTimestampMs()-s.at<240000,'native medicine evolution stays bounded')
    local moodle=actor:getMoodles():getMoodleLevel(MoodleType.PAIN);local pain=actor:getStats():get(CharacterStat.PAIN)
    e.minimumMoodle=math.min(e.minimumMoodle,moodle);e.minimumPain=math.min(e.minimumPain,pain)
    if not e.painEnded and actor:getPainEffect()<=0 and actor:getPainDelta()<=0 then
        e.painEnded=elapsed;note('pain_effect_ended_gamehours='..elapsed..'; minimum_moodle='..e.minimumMoodle..'; minimum_pain='..e.minimumPain)
    end
    if not e.antibioticEnded and actor:getReduceInfectionPower()<=0 then
        e.antibioticEnded=elapsed;note('antibiotic_effect_ended_gamehours='..elapsed..'; wound_infection='..e.part:getWoundInfectionLevel())
    end
    local half=math.floor(elapsed*2)
    if half~=e.last then
        e.last=half;note('evolution_gamehours='..elapsed..'; pain_effect='..actor:getPainEffect()..'; pain_delta='..actor:getPainDelta()
            ..'; pain_reduction='..actor:getBodyDamage():getPainReduction()..'; pain='..pain..'; pain_moodle='..moodle
            ..'; untreated_pain='..control:getStats():get(CharacterStat.PAIN)..'; antibiotic_power='..actor:getReduceInfectionPower()
            ..'; wound_infection='..e.part:getWoundInfectionLevel()..'; untreated_infection='..e.controlPart:getWoundInfectionLevel()
            ..'; knox='..tostring(actor:getBodyDamage():isInfected())..'; health='..actor:getBodyDamage():getOverallBodyHealth())
    end
    if elapsed>=2 and not e.twoHours then
        e.twoHours=true
        check(e.part:getWoundInfectionLevel()<5 and e.part:getWoundInfectionLevel()<e.controlPart:getWoundInfectionLevel(),'native antibiotic lowers real local wound infection over2gamehours')
        check(actor:getBodyDamage():isInfected(),'native antibiotic does not cure Knox over2gamehours')
        check(e.minimumMoodle<e.beforeMoodle and e.minimumPain<e.beforePain,'one native pill lowers real pain and pain moodle')
        check(e.pills:getCurrentUses()==e.uses and e.pillReserve:getCurrentUses()==e.reserveUses,'evolution takes no second pill dose')
        -- Knox persistence has been proved. Remove only this fixture injury so
        -- the remaining duration observation does not end in a disposable death.
        actor:getBodyDamage():setInfected(false)
    end
    if not (e.twoHours and e.painEnded and e.antibioticEnded) then return end
    check(s.helper:getInventory():contains(e.antibioticReserve),'antibiotic duration uses no second course')
    note('active_reads=painEffect>0 OR painDelta>0 OR foodPainReduction>0; antibiotic_reduceInfectionPower>0; duration_depends_on_native_time_and_wound_count')
    getGameTime():setMultiplier(s.multiplier)
    if SC_MEDICAL_PHASE3_ACCEPTANCE then phase('acceptance-phase3-start') else finish(true,'native Phase3 effects, exact stock debits, duration and player queue verified') end
end
local function beginSpawn()
    local U=SC.GameplayUtil;local origin=s.primary:getSquare();local square
    for r=1,8 do if not square then for dx=-r,r do for dy=-r,r do
        local candidate=getCell():getGridSquare(origin:getX()+dx,origin:getY()+dy,origin:getZ())
        if candidate and U.isClearActorSpawnSquare(candidate)==true and candidate:isFree(false) then square=candidate;break end
    end if square then break end end end end
    check(square~=nil,'constructor-safe loaded native spawn uses LF clear floor plus native isFree(false)')
    s.ticket=assert(SC.Actor.beginSpawn(square,{recruited=true,identity={forename='Phase3',surname='Native'..(#s.actors+1),gender='woman',outfit='Generic01'}}))
    phase('spawn')
end
Events.OnInitGlobalModData.Add(function() ModData.getOrCreate(SC.Identity.worldSaveKey).document={schema=SC.Identity.saveSchema,companions={},factionActors={}} end)
Events.OnMainMenuEnter.Add(function() MainScreen.continueLatestSave('Sandbox','PzoRestoreFixture') end)
local seen={}
Events.OnRenderTick.Add(function()
    local modal=MainScreen and MainScreen.instance and MainScreen.instance.checkSavefileModal
    if modal and modal.yes and not seen[modal] then seen[modal]=true;modal:onClick(modal.yes) end
end)
Events.OnGameStart.Add(function()
    SC.Scheduler.unregister('decision');s.primary=assert(getSpecificPlayer(0));local queue=ISTimedActionQueue.getTimedActionQueue(s.primary)
    s.primaryCurrent,s.primaryQueued=queue.current,#queue.queue;phase('load')
end)
local function step()
    if s.done or s.phase=='menu' then return end
    if s.phase=='load' then
        if getTimestampMs()-s.at<12000 then return end
        check(SCBridge and PZOEngine and SC.Actor.checkBridge(true),'actual official PZO and production native companion provider')
        -- Disposable-clone cleanup only. No zombie paths, flags or states change.
        local zombies,removed=getCell():getZombieList(),0
        for i=zombies:size()-1,0,-1 do local z=zombies:get(i);z:removeFromWorld();z:removeFromSquare();if zombies:contains(z) then zombies:remove(z) end;removed=removed+1 end
        note('fixture_loaded_zombies_removed_once='..removed..'; zombie_navigation_unchanged=true')
        beginSpawn()
    elseif s.phase=='spawn' then
        local actor,why=SC.Actor.pollSpawn(s.ticket)
        if not actor then check(why=='spawn_pending' and getTimestampMs()-s.at<15000,tostring(why));return end
        s.actors[#s.actors+1]=actor
        if #s.actors<3 then beginSpawn() else s.actor,s.helper,s.control=s.actors[1],s.actors[2],s.actors[3];phase('stitch') end
    elseif s.phase=='stitch' then stitch();xpProof();phase('medicine-start')
    elseif s.phase=='medicine-start' then prepareMedicine()
    elseif s.phase=='medicine-ready' then if getTimestampMs()-s.at>=5500 then startMedicine() end
    elseif s.phase=='medicine-evolution' then evolution()
    elseif string.find(s.phase,'acceptance-phase3-',1,true)==1 then
        s.acceptance=s.acceptance or require 'MedicalPhase3Acceptance'
        if s.acceptance.step(s,check,note,phase)==true then finish(true,'native Phase3 production acceptance verified') end
    end
end
Events.OnTick.Add(function() if not s.done then local okay,why=pcall(step);if not okay then finish(false,why) end end end)
