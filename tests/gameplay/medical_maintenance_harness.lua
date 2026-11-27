-- SPDX-License-Identifier: MIT
-- Native body semantics are separately proven by MedicalCapabilities.lua.
-- Here exercise selection, exact resources, and interrupted redress ownership.
local SC=LivingFellows
local M,Care,F=SC.Medical,SC.MedicalMaintenance,SC.TestFixture
local checks=0
local function check(value,reason) checks=checks+1;assert(value,'medical maintenance '..checks..': '..reason) end
local function part(options)
    local p=F.bodyPart(options or {})
    function p:getBiteTime() return self.biteTime or 0 end
    function p:getScratchTime() return self.scratchTime or 0 end
    function p:getCutTime() return self.cutTime or 0 end
    function p:getDeepWoundTime() return self.deepTime or 0 end
    function p:getStitchTime() return self.stitchTime or 0 end
    function p:stitched() return self.stitchFlag==true end
    function p:isSplint() return self.splintFlag==true end
    function p:getSplintFactor() return self.splintFactor or 0 end
    function p:getSplintItem() return self.splintItem end
    function p:setSplint(enabled,factor) self.splintFlag=enabled;self.splintFactor=factor end
    function p:getAdditionalPain() return self.additionalPain or 0 end
    function p:setAdditionalPain(value) self.additionalPain=value end
    function p:isGetStitchXp() return false end
    function p:setInfectedWound(value) self.infectedWound=value end
    function p:setBandaged(enabled,life,alcoholic,kind)
        self.isBandaged,self.bandageLife,self.bandageAlcoholic,self.bandageType=enabled,life,alcoholic,kind
        self.stitchFlag=not enabled and self:getStitchTime()>0
    end
    function p:setStitched(enabled)
        if not enabled and not self.stitchFlag then return end
        if not enabled then
            self.removals=(self.removals or 0)+1
            if self:getStitchTime()<40 then self.deepTime=10;self.isBleeding=true
            else self.scratchTime=2 end
            self.stitchTime=0
        end
        self.stitchFlag=enabled
    end
    return p
end
local serial=0
local function actor(p,items)
    serial=serial+1
    local value=F.actor('maintenance-'..serial,20+(serial%20),30,{body=F.bodyDamage(100,{p}),inventory=F.inventory(items or {})})
    SC.GameplayUtil.actorState(value).snapshot={valid=true,time=SC.GameplayUtil.nowMs(),immediateCount=0,closeThreatCount=0,threatCount=0}
    return value
end
local function count(inv,kind)
    local amount=0;for _,item in ipairs(inv.items) do if item:getFullType()==kind then amount=amount+1 end end;return amount
end
do
    local bodyPart=part({scratchTime=9,isBandaged=true,dirty=true,bandageLife=0,bandageType="Base.Bandage"})
    local bag=F.item("Base.FirstAidKit","Container")
    local nested=F.inventory({F.item("Base.Junk","Item")})
    function bag:getInventory() return nested end
    function nested:getContainingItem() return bag end
    local subject=actor(bodyPart,{bag})
    local U=SC.GameplayUtil
    local clock,inventoryItems,assess,hash=F.clock,U.inventoryItems,M.assess,U.stableHash
    local reads,bodyReads=0,0
    local initial=assess(subject)
    U.stableHash=function(key)
        if key:find(":quiet-supply",1,true) then return 0 end
        return hash(key)
    end
    U.inventoryItems=function(inventory,...)
        if inventory==subject.inventory or inventory==nested then reads=reads+1 end
        return inventoryItems(inventory,...)
    end
    M.assess=function(character,...)
        if character==subject then bodyReads=bodyReads+1 end
        return assess(character,...)
    end
    check(not M.quietCareAvailable(subject,initial) and bodyReads==0 and reads>0,
        "quiet supply discovery uses its caller's assessment and searches the actual bag")
    local firstReads=reads
    F.clock=clock+999
    check(not M.quietCareAvailable(subject,initial) and reads==firstReads,
        "a missing quiet dressing skips the duplicate inventory search for one second")
    local bandage=F.item("Base.Bandage","Medical")
    U.addItem(nested,bandage)
    check(M.quietCareAvailable(subject,initial) and reads>firstReads and bodyReads==0,
        "a notified nested dressing appears immediately without another body assessment")
    nested:Remove(bandage)
    check(not M.quietCareAvailable(subject,initial),"positive supply readiness is not cached")
    nested:AddItem(bandage)
    check(not M.quietCareAvailable(subject,initial),"an unreported native inventory edit keeps only bounded advice")
    F.clock=clock+1999
    check(M.quietCareAvailable(subject,initial),"the expiry sees an unreported addition on the next quiet probe")
    nested:Remove(bandage)
    check(not M.quietCareAvailable(subject,initial),"an empty nested inventory can record a new miss")
    nested:AddItem(bandage)
    check(M.replaceDirtyBandage(subject) and not nested:contains(bandage) and bodyReads>0,
        "actual treatment bypasses the negative and uses the exact fresh inventory and wound")
    U.inventoryItems,M.assess,F.clock,U.stableHash=inventoryItems,assess,clock,hash
end
local healed=actor(part({isBandaged=true,dirty=true,bandageLife=0,bandageType='Base.Bandage'}))
local assessment=M.assess(healed)
check(assessment.woundCount==0 and #assessment.wounds==1 and assessment.wounds[1].healed,'healed dirty covering remains a display row, not an active injury')
check(assessment.dirtyBandages==0 and not assessment.needsBandageChange,'healed covering never consumes replacement supplies')
local hidden=actor(part({isBandaged=true,biteTime=8,stitchTime=39}))
assessment=M.assess(hidden)
check(assessment.bites==1 and assessment.woundCount==1 and assessment.wounds[1].stitched,'covered native timers remain active even when booleans are hidden')
check(not assessment.needsMaintenance,'stitches below40 remain attached')
local unsafe=actor(part({stitchFlag=true,stitchTime=39}))
local early,earlyReason=Care.commit(unsafe,{patient=unsafe,maintenanceKind='remove_stitches'},
    {part=unsafe.body.parts[1],index=0},function() return false end)
check(not early and earlyReason=='stitches_not_ready' and unsafe.body.parts[1].stitchTime==39,
    'commit rejects stitch39 before reopening a deep wound')
local ready=actor(part({isBandaged=true,stitchTime=40,bandageType='Base.Bandage',bandageLife=10}))
check(M.assess(ready).needsMaintenance,'exact40 boundary requests safe removal')
local spent=actor(part({splintFlag=true,splintFactor=0,fracture=0,splintItem='Base.Plank'}))
assessment=M.assess(spent)
check(assessment.woundCount==0 and assessment.needsMaintenance and assessment.wounds[1].boneHealed,'true zero-factor spent attachment remains visible without inflating injury count')
local originalBridge,fillCalls=SCBridge,0
SCBridge={getProtocol=function() return '42.22-isocompanion-33' end,fillBodyFacts=function() fillCalls=fillCalls+1;return 0 end}
check(M.assess(hidden).woundCount==1 and fillCalls==0,'old bridge is rejected before a body tuple can be consumed')
SCBridge=originalBridge
-- Both tuple and direct-read paths must publish identical clinical facts.
for _,case in ipairs({
    {'healed_clean',{isBandaged=true,bandageLife=10},8,0,true,0},
    {'healed_dirty',{isBandaged=true,dirty=true,bandageLife=0},24,0,true,0},
    {'hidden_bite',{isBandaged=true,biteTime=9},8,1,false,0},
    {'hidden_scratch',{isBandaged=true,scratchTime=9},8,1,false,0},
    {'hidden_cut',{isBandaged=true,cutTime=9},8,1,false,0},
    {'hidden_deep',{isBandaged=true,deepTime=9},8,1,false,0},
    {'hidden_stitch',{isBandaged=true,stitchTime=45},4104,1,false,0},
    {'stitch_only',{stitchFlag=true},4096,1,false,0},
    {'splint_zero',{splintFlag=true,splintFactor=0},8192,0,false,0},
    {'splint_factor',{splintFlag=false,splintFactor=1},8192,0,false,0},
    {'all_flags',{isBandaged=true,dirty=true,fracture=5},16383,1,false,1},
}) do
    local patient=actor(part(case[2]))
    for mode=1,2 do
        local fallbackReads=0
        local oldParts=patient.body.getBodyParts
        patient.body.getBodyParts=function(self) fallbackReads=fallbackReads+1;return oldParts(self) end
        if mode==1 then
            SCBridge={getProtocol=function() return '42.22-isocompanion-38' end,
                fillBodyFacts=function(character,out)
                    out.health,out.infected,out.apparentInfection=100,false,0
                    out.infectionTime,out.infectionDuration,out.count=-1,-1,1
                    out[1],out[2],out[3],out[4]=patient.body.parts[1],0,case[3],'Foot_R'
                    return 1
                end}
        else SCBridge=nil end
        local facts=M.assess(patient)
        check(facts.woundCount==case[4] and facts.wounds[1].healed==case[5]
            and facts.dirtyBandages==case[6],case[1]..' clinical count/covering mode'..mode)
        if mode==1 then check(fallbackReads==0,case[1]..' protocol34 consumes native tuple flags') end
        patient.body.getBodyParts=oldParts
    end
end
SCBridge=originalBridge
local unknown=actor(part({isBandaged=true}))
unknown.body.parts[1].getCutTime=nil
check(not M.assess(unknown).wounds[1].healed,'unreadable injury timer never proves a healed covering')
local plain=F.item('Base.Bandage','Medical'),F.item('Base.Bandage','Medical')
local alcohol=F.item('Base.AlcoholBandage','Medical');function alcohol:isAlcoholic() return true end
check(M.dressingRank(plain,false,{scratched=true})<M.dressingRank(alcohol,false,{scratched=true}),'minor scratch uses plain dressing before alcohol stock')
check(M.dressingRank(alcohol,false,{deepWound=true})<M.dressingRank(plain,false,{deepWound=true}),'deep wound retains alcohol dressing preference')
local savedNative,savedSupervisor,savedMove,savedStop,savedRand=SC.NativeActions,SC.ActionSupervisor,SC.GameplayUtil.move,SC.GameplayUtil.stop,ZombRand
SC.NativeActions,SC.ActionSupervisor=nil,nil
SC.GameplayUtil.move=function() return true end;SC.GameplayUtil.stop=function() return true end;ZombRand=function() return 1 end
local fresh=F.item('Base.Bandage','Medical');ready.inventory:AddItem(fresh)
local okay,reason=M.replaceDirtyBandage(ready)
check(okay and reason=='stitches_removed','covered ready stitches finish through self-care pipeline')
check(ready.body.parts[1].removals==1 and ready.body.parts[1].stitchTime==0 and ready.body.parts[1].scratchTime>0,'native removal is final and leaves its scratch')
check(ready.body.parts[1].isBandaged and not ready.inventory:contains(fresh) and count(ready.inventory,'Base.Bandage')==1,'fresh exact supply consumed and previous clean covering returned once')
okay,reason=M.replaceDirtyBandage(spent)
check(okay and reason=='splint_removed' and not spent.body.parts[1].splintFlag,'spent zero-factor splint is removed')
check(count(spent.inventory,'Base.Plank')==1 and count(spent.inventory,'Base.RippedSheets')==1,'improvised splint provenance returns exact native materials')
local noFresh=actor(part({isBandaged=true,stitchTime=40,bandageType='Base.Bandage',bandageLife=0}))
okay,reason=M.replaceDirtyBandage(noFresh)
check(not okay and reason=='no_clean_dressing_for_stitches' and noFresh.body.parts[1].stitchTime==40,'no fresh dressing leaves covered stitches untouched')
local uncovered=actor(part({stitchFlag=true,stitchTime=40}))
okay,reason=M.replaceDirtyBandage(uncovered)
check(okay and reason=='stitches_removed' and uncovered.body.parts[1].scratchTime>0,'uncovered ready stitches may remove itemless and leave ordinary scratch care')
for _,fracture in ipairs({1,0/0}) do
    local guarded=actor(part({splintFlag=true,splintFactor=0,fracture=fracture,splintItem='Base.Splint'}))
    check(not M.assess(guarded).needsMaintenance,'positive or unknown fracture time never proves a healed bone')
    local accepted,why=Care.commit(guarded,{patient=guarded,maintenanceKind='remove_splint'},
        {part=guarded.body.parts[1],index=0},function() return false end)
    check(not accepted and why=='fracture_not_healed' and guarded.body.parts[1].splintFlag,'commit rechecks finite zero fracture time before removal')
end
local pendingFresh=F.item('Base.Bandage','Medical')
local pending=actor(part({isBandaged=true,stitchTime=45,bandageType='Base.Bandage',bandageLife=0}),{pendingFresh})
pending.body.rejectBandage=true
okay,reason=M.replaceDirtyBandage(pending)
check(okay and reason=='medical_redress_pending' and M.peek(pending).phase=='redressing','failed redress retains active patient-specific obligation')
check(M.treatmentHolder(pending)==pending and pending.inventory:contains(pendingFresh),'pending redress retains patient claim and exact unconsumed supply')
check(pending.body.parts[1].removals==1 and count(pending.inventory,'Base.BandageDirty')==1,'committed removal and old-covering return occur once')
M.cancel(pending,'test_handoff',true)
check(Care.pending(pending)~=nil and M.peek(pending)==nil,'clean cancellation hands off obligation without restoring stitches')
local laterFresh=F.item('Base.Bandage','Medical');pending.inventory:AddItem(laterFresh)
pending.inventory.items[1],pending.inventory.items[#pending.inventory.items]=laterFresh,pendingFresh
pending.body.rejectBandage=false
okay,reason=M.replaceDirtyBandage(pending)
check(okay and reason=='stitches_removed' and Care.pending(pending)==nil,'next patient-specific claim verifies redress')
check(pending.body.parts[1].removals==1 and count(pending.inventory,'Base.BandageDirty')==1 and not pending.inventory:contains(pendingFresh),'redress recovery never repeats native removal or duplicates outputs')
check(pending.inventory:contains(laterFresh),'handoff prefers the exact previously reserved fresh supply still carried')
local debt=actor(part({splintFlag=true,splintFactor=0,fracture=0,splintItem='Base.Plank'}))
local originalAdd=debt.inventory.AddItem
local rejectMaterial=true
debt.inventory.AddItem=function(inventory,kind)
    if rejectMaterial and kind=='Base.Plank' then return nil end
    return originalAdd(inventory,kind)
end
okay,reason=M.replaceDirtyBandage(debt)
check(okay and reason=='medical_redress_pending' and not debt.body.parts[1].splintFlag,'material-return failure keeps committed splint removal final')
M.cancel(debt,'return_handoff',true);rejectMaterial=false
okay,reason=M.replaceDirtyBandage(debt)
check(okay and reason=='splint_removed' and count(debt.inventory,'Base.Plank')==1
    and count(debt.inventory,'Base.RippedSheets')==1,'return-only obligation recovers without any dressing')
debt.inventory.AddItem=originalAdd
for _,resolution in ipairs({'player_dressed','healed_skin','unknown_timer'}) do
    local supply=F.item('Base.Bandage','Medical')
    local subject=actor(part({isBandaged=true,stitchTime=45,bandageType='Base.Bandage',bandageLife=0}),{supply})
    local rejectReturn=true
    local sourceAdd=subject.inventory.AddItem
    subject.inventory.AddItem=function(inventory,kind)
        if rejectReturn and kind=='Base.BandageDirty' then return nil end
        return sourceAdd(inventory,kind)
    end
    okay,reason=M.replaceDirtyBandage(subject)
    check(okay and reason=='medical_redress_pending' and Care.pending(subject)~=nil,
        resolution..' publishes exact committed old-covering return debt')
    M.cancel(subject,'external_resolution',true)
    subject.inventory:Remove(supply)
    local p=subject.body.parts[1]
    if resolution=='player_dressed' then p:setBandaged(true,12,false,'Base.Bandage')
    else p.scratchTime=0;p.isScratched=false end
    local originalCut=p.getCutTime
    if resolution=='unknown_timer' then p.getCutTime=nil end
    rejectReturn=false
    if resolution=='unknown_timer' then
        okay,reason=M.replaceDirtyBandage(subject)
        check(not okay and reason=='no_clean_dressing_for_stitches' and Care.pending(subject).redress,
            'unknown timer keeps redress obligation pending even on apparently healed skin')
        p.getCutTime=originalCut
    end
    okay,reason=M.replaceDirtyBandage(subject)
    check(okay and reason=='stitches_removed' and Care.pending(subject)==nil
        and count(subject.inventory,'Base.BandageDirty')==1 and subject.body.parts[1].removals==1,
        resolution..' finishes outstanding returns itemless without another removal')
    check(p.isBandaged==(resolution=='player_dressed') and not subject.inventory:contains(supply),
        resolution..' never spends or manufactures a fresh dressing after external resolution')
    subject.inventory.AddItem=sourceAdd
end
local erroredFresh=F.item('Base.Bandage','Medical')
local errored=actor(part({isBandaged=true,stitchTime=45,bandageType='Base.Bandage',bandageLife=12}),{erroredFresh})
local nativeRemove=errored.body.parts[1].setStitched
errored.body.parts[1].setStitched=function(self,enabled) nativeRemove(self,enabled);error('error after actual native effect') end
okay,reason=M.replaceDirtyBandage(errored)
check(okay and reason=='stitches_removed' and errored.body.parts[1].removals==1,'verified native removal remains committed when setter reports an error afterward')
local rollback=actor(part({isBandaged=true,stitchTime=45,bandageType='Base.AlcoholBandage',bandageLife=17,bandageAlcoholic=true}),{F.item('Base.Bandage','Medical')})
rollback.body.parts[1].setStitched=function() error('error before effect') end
okay,reason=M.replaceDirtyBandage(rollback)
check(not okay and rollback.body.parts[1].isBandaged and rollback.body.parts[1].bandageLife==17
    and rollback.body.parts[1].bandageAlcoholic and rollback.body.parts[1].bandageType=='Base.AlcoholBandage',
    'pre-removal failure restores exact dressing life alcohol and type')
local guardedFresh=F.item('Base.Bandage','Medical')
local guarded=actor(part({isBandaged=true,stitchTime=45,bandageType='Base.Bandage',bandageLife=12}),{guardedFresh})
local protectedNow=false;local originalProtected=SC.PersonalItems.isProtected
SC.PersonalItems.isProtected=function(item,...)
    if item==guardedFresh and protectedNow then return true end
    return originalProtected(item,...)
end
local visual='active'
SC.NativeActions={visualStatus=function() return visual end,clearVisual=function() end,cancelVisual=function() return true end}
okay=M.replaceDirtyBandage(guarded)
check(okay and M.peek(guarded)~=nil,'elective surgery reserves its exact fresh supply before visual')
protectedNow=true;visual='completed'
okay,reason=M.replaceDirtyBandage(guarded)
check(not okay and guarded.body.parts[1].stitchTime==45 and guarded.body.parts[1].isBandaged
    and guarded.inventory:contains(guardedFresh),'fresh protection is checked again before elective undressing')
SC.PersonalItems.isProtected=originalProtected
local unknownSafety=actor(part({stitchFlag=true,stitchTime=45}))
SC.GameplayUtil.actorState(unknownSafety).snapshot=nil
okay,reason=M.replaceDirtyBandage(unknownSafety)
check(not okay and reason=='danger_preempted' and unknownSafety.body.parts[1].stitchTime==45,
    'unknown snapshot never authorizes elective attachment removal')
for _,other in ipairs({false,true}) do
    for _,threat in ipairs({'immediateCount','closeThreatCount'}) do
        local supply=F.item('Base.Bandage','Medical')
        local patient=actor(part({isBandaged=true,stitchTime=45,bandageType='Base.Bandage',bandageLife=12}),other and {} or {supply})
        local helper=other and actor(part({}),{supply}) or patient
        if other then helper.square=patient.square end
        local runtime={snapshot={valid=true,time=SC.GameplayUtil.nowMs(),immediateCount=0,closeThreatCount=0,threatCount=0}}
        visual='active'
        okay=M.treat(helper,patient,runtime)
        check(okay and M.peek(helper)~=nil,'semi-safe elective removal starts for '..tostring(other)..' '..threat)
        runtime.snapshot[threat]=1;visual='completed'
        okay,reason=M.treat(helper,patient,runtime)
        check(not okay and reason=='danger_preempted' and patient.body.parts[1].stitchTime==45
            and patient.body.parts[1].isBandaged and helper.inventory:contains(supply),
            'new '..threat..' refuses elective commit for '..tostring(other)..' and preserves exact fresh supply')
        okay,reason=M.treat(helper,patient,runtime)
        check(not okay and reason=='danger_preempted' and M.peek(helper)==nil,
            'unsafe elective maintenance cannot restart under rescue-only safety bar')
    end
end
do
    SC.NativeActions=nil
    local P,clinical=SC.MedicalProcedures,SC.TestMedicalProcedures
    local function burn()
        return clinical.part({burn=10,needBurnWash=true,isBandaged=true,bandageType='Base.Bandage',bandageLife=10})
    end
    local first,other,stitches=burn(),burn(),part({stitchFlag=true,stitchTime=45})
    local splint=part({splintFlag=true,splintFactor=1,splintItem='Base.Splint',fracture=0})
    local patient=clinical.actor({first,other,stitches,splint},{clinical.item('Base.Bandage'),clinical.item('Base.Bandage')})
    P.writeCare(patient,'medicalRecovery',{version=1,patientId=P.actorId(patient),index=0,kind='clean_burn',
        redress=false,returned=true,quarantined=true,terminalQuarantine=true,returns={},
        procedure={kind='clean_burn',painVerified=false,debitDone=false,debitAttempted=true}})
    Care.forget(patient)
    local accepted,refusal=Care.commit(patient,{patient=patient,maintenanceKind='clean_burn'},{part=first,index=0})
    check(not accepted and refusal=='medical_consumption_uncertain' and not first.burnCleanCalls,
        'unloading before first restore retains the receipt and a stale commit cannot replay the uncertain burn')
    okay,reason=M.treat(patient,patient)
    check(okay and reason=='burn_cleaned' and not first.burnCleanCalls and other.burnCleanCalls==1,
        'an uncertain burn on one index permits the same operation on a different wound')
    local hold=M.pendingCare(patient)
    check(hold and hold.kind=='clean_burn' and hold.woundIndex==0 and hold.active==false,
        'another committed surgery preserves the exact inactive hold')
    Care.reset()
    M.invalidate(patient)
    okay,reason=M.treat(patient,patient)
    check(okay and reason=='stitches_removed' and stitches.removals==1 and not first.burnCleanCalls,
        'restored uncertainty permits native removal of mature stitches')
    -- The newly uncovered healed scratch is covered by the player.
    stitches.isBandaged,stitches.bandageLife,stitches.bandageType=true,10,'Base.Bandage'
    M.invalidate(patient)
    okay,reason=M.treat(patient,patient)
    check(okay and reason=='splint_removed' and not splint.splintFlag and count(patient.inventory,'Base.Splint')==1,
        'the healed fracture can shed its splint and return it exactly once during quarantine')
    first.burn=0;first.needBurnWash=false
    check(not M.pendingCare(patient) and not first.burnCleanCalls and other.burnCleanCalls==1,
        'the healed native burn clears its own hold without replaying the uncertain procedure')
    first.burn,first.needBurnWash=12,true
    patient.inventory:AddItem(clinical.item('Base.Bandage'));patient.inventory:AddItem(clinical.item('Base.Bandage'))
    M.invalidate(patient)
    okay,reason=M.treat(patient,patient)
    check(okay and reason=='burn_cleaned' and first.burnCleanCalls==1 and other.burnCleanCalls==1,
        'a later burn on the same native index receives exactly one new treatment')
end
do
    local P,clinical=SC.MedicalProcedures,SC.TestMedicalProcedures
    local wound=clinical.part({bullet=true,glass=true,isBandaged=true,bandageLife=10,bandageType='Base.Bandage'})
    local patient=clinical.actor({wound},{clinical.item('Base.Bandage'),clinical.item('Base.Tweezers')})
    P.writeCare(patient,'medicalRecovery',{version=-1,index=0,kind='remove_bullet'})
    okay,reason=M.treat(patient,patient)
    check(okay and reason=='glass_removed' and wound.bullet and not wound.glass and not wound.bulletCalls,
        'malformed receipt with recognizable scope allows another procedure on the very same index')
    wound.haveBullet=function() return nil end
    check(M.pendingCare(patient)~=nil,'an unreadable native bullet flag cannot clear its hold')
    wound.haveBullet=function() return false end
    check(not M.pendingCare(patient) and not wound.bulletCalls,'verified absent bullet retires the malformed hold without surgery')
end
SC.NativeActions,SC.ActionSupervisor,SC.GameplayUtil.move,SC.GameplayUtil.stop,ZombRand=savedNative,savedSupervisor,savedMove,savedStop,savedRand
print('Medical maintenance PASS checks='..checks)
