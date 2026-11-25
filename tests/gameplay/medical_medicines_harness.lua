-- SPDX-License-Identifier: MIT
local SC=SurvivorCompanion
local M,D,P,F,T,U=SC.Medical,SC.MedicalMedicines,SC.MedicalProcedures,SC.TestMedicalMedicines,SC.TestFixture,SC.GameplayUtil
local checks=0
local function check(value,reason) checks=checks+1;assert(value,"medical medicines "..checks..": "..reason) end
local native,service,move,stop=SC.NativeActions,SC.ActionSupervisor,U.move,U.stop
SC.NativeActions,SC.ActionSupervisor=nil,nil
U.move=function() return true end;U.stop=function() return true end
local function pain(options)
    local pills=F.item("Base.Pills",options)
    local actor=F.actor(nil,{pills})
    return actor,pills
end
do
    local active,inside,provider=SC.BaseLife.active,SC.BaseLife.isInside,SC.MedicKit.medicineContext
    local calls=0
    SC.BaseLife.active=function() return {} end
    SC.BaseLife.isInside=function() return true end
    SC.MedicKit.medicineContext=function(_,_,context)
        calls=calls+1
        check(context.stage=="advisory","medicine discovery labels the stock observation advisory")
        return {stockKnown=true,antibioticDoses=2,disinfectantAvailable=false}
    end
    local subject=F.actor(nil,{})
    subject.moodles[MoodleType.PAIN]=0
    check(not D.need(subject,{wounds={}}) and not D.need(subject,{knoxInfected=true,wounds={}})
        and not D.need(subject,{wounds={{infected=false}}}) and calls==0,
        "healthy, Knox-only and uninfected wounds do not scan camp medicine stock")
    local infected={wounds={{infected=true,index=0,woundInfectionLevel=8}}}
    subject.moodles[MoodleType.PAIN]=2
    check(D.need(subject,infected).kind=="take_painkillers" and calls==0,
        "whole-body pain relief keeps priority and needs no antibiotic stock scan")
    subject.moodles[MoodleType.PAIN]=0
    check(D.need(subject,infected).kind=="take_antibiotics" and calls==1,
        "a locally infected wound proceeds to the stock policy")
    SC.BaseLife.active,SC.BaseLife.isInside,SC.MedicKit.medicineContext=active,inside,provider
end
local actor,pills=pain()
local need=M.careNeed(actor)
check(need and need.kind=="take_painkillers" and need.wholeBody and need.woundIndex==nil,
    "pain alone selects genuine whole-body medicine without a fake part")
local okay,reason=M.treat(actor,actor)
check(okay and reason=="painkillers_taken" and actor.pillCalls==1 and pills.uses==9,
    "existing Medical.treat gives one native pill and its native exact debit: "..tostring(reason).." calls="..tostring(actor.pillCalls).." uses="..tostring(pills.uses))
local state=P.readCare(actor,"medicalMedicineState")
local receipt=P.readCare(actor,"medicalMedicineRecovery")
check(state.painCount==1 and receipt.attempted and receipt.effectVerified and receipt.debitVerified,
    "dose publishes exact native proof and durable daily allowance")
check(not D.need(actor,M.assess(actor)) and not M.peek(actor),"active medicine releases treatment and prevents repeat")
for _,field in ipairs({"nativePainEffect","nativePainDelta","nativePainReduction"}) do
    local patient,stock=pain();patient[field]=1
    check(not D.need(patient,M.assess(patient)),field.." independently blocks pending or active redose")
    check(not M.treat(patient,patient) and stock.uses==10 and not patient.pillCalls,"active dose does not touch stock")
end
for _,level in ipairs({0,1}) do
    local patient,stock=pain();patient.moodles[MoodleType.PAIN]=level
    check(not M.careNeed(patient) and not M.treat(patient,patient) and stock.uses==10,"no painkillers below Pain 2")
end
for _,field in ipairs({"getPainEffect","getPainDelta"}) do
    local patient,stock=pain();patient[field]=function() return nil end
    check(not M.careNeed(patient) and stock.uses==10,"unreadable "..field.." fails closed")
end
do
    local patient,stock=pain();patient.body.getPainReduction=function() return nil end
    check(not M.careNeed(patient) and stock.uses==10,"unreadable food analgesia fails closed")
end
do
    local patient,stock=pain();patient.nativePainEffect=-0.0015716552734375
    okay,reason=M.treat(patient,patient)
    check(okay and reason=="painkillers_taken" and stock.uses==9,
        "proven native negative expired pain timer permits a legitimate new dose")
    local saved=SC.Commands.export(patient)
    SC.Commands.reset(patient);D.reset();check(SC.Commands.restore(patient,saved) and not D.pending(patient),
        "negative native pre-dose timer remains valid exact durable proof")
    patient=F.actor();patient.nativePainEffect=-0.0015716552734375;patient.nativePainDelta=0.45
    check(not D.need(patient,M.assess(patient)),"negative expired timer still waits for native pending delta to clear")
end
for dose=2,4 do
    F.clearPain(actor);F.refresh(actor)
    okay,reason=M.treat(actor,actor)
    check(okay and reason=="painkillers_taken" and pills.uses==10-dose,"daily dose "..dose.." consumes exactly once")
end
F.clearPain(actor);F.refresh(actor)
check(not M.careNeed(actor) and not M.treat(actor,actor) and pills.uses==6,"fifth dose in one game day is refused")
local exported=SC.Commands.export(actor)
SC.Commands.reset(actor);D.reset();P.reset()
check(SC.Commands.restore(actor,exported) and P.readCare(actor,"medicalMedicineState").painCount==4,
    "ordinary command roundtrip retains all four allowances")
check(not M.careNeed(actor) and pills.uses==6,"reload never refills the daily allowance")
do
    local patient,stock=pain()
    check(M.treat(patient,patient),"coherence control first establishes a verified real dose")
    F.clearPain(patient);F.refresh(patient)
    P.writeCare(patient,"medicalMedicineState",{version=1,painDay=math.floor(P.worldHours()/24),painCount=0})
    check(not M.treat(patient,patient) and stock.uses==9 and patient.pillCalls==1,
        "retained receipt without its matching durable allowance timestamp fails closed")
end
do
    local patient,stock=pain();patient.intoxicated=true
    okay,reason=M.treat(patient,patient)
    check(okay and reason=="painkillers_taken" and math.abs(patient.nativePainDelta-0.15)<0.00001 and stock.uses==9,
        "native intoxicated pill strength is verified without LF effect arithmetic")
end
for _,mode in ipairs({"favorite","protected","loan","manual","held","needs","moved","nativeId","wrongDelta"}) do
    local patient,stock=pain()
    local protected=SC.PersonalItems.isProtected
    if mode=="favorite" then stock.favorite=true
    elseif mode=="protected" then SC.PersonalItems.isProtected=function(item,...) return item==stock or protected(item,...) end
    elseif mode=="loan" then stock:getModData().LF_PlayerLoan="player"
    elseif mode=="manual" then stock:getModData().SC_ManualEquipFor="player"
    elseif mode=="held" then patient.getPrimaryHandItem=function() return stock end
    elseif mode=="needs" then SC.NativeActions={needsStatus=function() return true,"eat" end}
    elseif mode=="moved" then patient.inventory:Remove(stock)
    elseif mode=="nativeId" then stock.nativeId=0
    else stock.useDelta=0.2 end
    okay,reason=M.treat(patient,patient)
    check(not okay and not patient.pillCalls and stock.uses==10,mode.." medicine supply remains untouched")
    SC.PersonalItems.isProtected=protected;SC.NativeActions=nil
end
for _,mode in ipairs({"danger","playerCare","claim"}) do
    local patient,stock=pain()
    if mode=="danger" then U.actorState(patient).snapshot.immediateCount=1
    elseif mode=="playerCare" then M.noteReceivingCare(patient,T.player)
    else M.claimPatient(T.player,patient) end
    okay,reason=M.treat(patient,patient)
    check(not okay and stock.uses==10 and not patient.pillCalls,mode.." uses the existing treatment guards")
    M.clearReceivingCare(patient);M.releasePatient(nil,patient)
end
do
    local patient,stock=pain();local player=getSpecificPlayer
    getSpecificPlayer=function(index) return index==0 and patient or nil end
    check(not D.need(patient,M.assess(patient)) and not M.treat(patient,patient) and stock.uses==10,
        "player medicine is never administered, including explicit self care")
    getSpecificPlayer=player
end
do
    local patient=F.actor(nil,{})
    local stock=F.item("Base.Pills")
    local helper=F.actor(nil,{stock});helper.square=patient.square
    okay,reason=M.treat(helper,patient)
    check(okay and reason=="painkillers_taken" and stock.uses==9 and patient.pillCalls==1 and not helper.pillCalls,
        "helper-carried exact supply affects its patient and remains helper owned")
end
do
    local visual="active"
    SC.NativeActions={visualStatus=function() return visual end,clearVisual=function() end,cancelVisual=function() return true end}
    for _,mode in ipairs({"lateFavorite","lateProtection","lateLoan","lateMove","lateStockDebit","lateDanger","latePainResolved"}) do
        local patient,stock=pain()
        visual="active";okay,reason=M.treat(patient,patient)
        check(okay and M.peek(patient)~=nil,"medicine pins its exact supply before visual: "..mode)
        local protected=SC.PersonalItems.isProtected
        if mode=="lateFavorite" then stock.favorite=true
        elseif mode=="lateProtection" then SC.PersonalItems.isProtected=function(item,...) return item==stock or protected(item,...) end
        elseif mode=="lateLoan" then stock:getModData().LF_PlayerLoan="player"
        elseif mode=="lateMove" then patient.inventory:Remove(stock)
        elseif mode=="lateStockDebit" then stock.uses=9
        elseif mode=="lateDanger" then U.actorState(patient).snapshot.closeThreatCount=1
        else patient.moodles[MoodleType.PAIN]=0 end
        visual="completed";okay,reason=M.treat(patient,patient)
        check(not okay and not patient.pillCalls and not M.peek(patient),mode.." prevents native commit and releases its treatment")
        SC.PersonalItems.isProtected=protected
    end
    SC.NativeActions=nil
end
do
    local stock=F.item("Base.Pills")
    local kit=SC.TestMedicalProcedures.item("Base.FirstAidKit")
    kit.nestedInventory=T.inventory({stock})
    function kit.nestedInventory:getContainingItem() return kit end
    local patient=F.actor(nil,{kit})
    kit:getModData().LF_MedicKitLoan={actorId=patient.id,storageId="medical"}
    local mayUse=SC.MedicKit.mayUseContents
    SC.MedicKit.mayUseContents=function(helper,candidate) return helper==patient and candidate==kit end
    okay,reason=M.treat(patient,patient)
    check(okay and reason=="painkillers_taken" and stock.uses==9,"validated own camp-kit ancestor permits its ordinary medicine contents")
    F.clearPain(patient);F.refresh(patient);kit:getModData().SC_PlayerLoan="player"
    check(not M.treat(patient,patient) and stock.uses==9,"own camp-kit exception never overrides another player loan marker")
    kit:getModData().SC_PlayerLoan=nil;stock:getModData().LF_MedicKitLoan={actorId=patient.id,storageId="medical"}
    check(not M.treat(patient,patient) and stock.uses==9,"camp-kit exemption applies only to its ancestor, never a loan-marked dose")
    SC.MedicKit.mayUseContents=mayUse
end
for _,mode in ipairs({"rejectMedicine","throwAfterEffect","throwAfterDose","rejectUse"}) do
    local patient,stock=pain()
    if mode=="rejectUse" then stock.rejectUse=true else patient[mode]=true end
    okay,reason=M.treat(patient,patient)
    local debit=stock.useCalls or 0
    check(okay and (mode=="throwAfterDose" and reason=="painkillers_taken" or mode~="throwAfterDose" and reason=="medical_consumption_uncertain"),
        mode.." is classified by native postconditions")
    F.clearPain(patient);F.refresh(patient)
    local saved=SC.Commands.export(patient)
    SC.Commands.reset(patient);D.reset();check(SC.Commands.restore(patient,saved),mode.." receipt survives reload")
    if mode~="throwAfterDose" then
        local pending=M.pendingCare(patient)
        check(pending and pending.terminalQuarantine and not pending.active,"uncertain exact debit becomes inactive forensic proof")
        check(not M.treat(patient,patient) and patient.pillCalls==1 and (stock.useCalls or 0)==debit,
            mode.." never replays effects, consumes again, refunds or creates stock")
        patient.body.parts={SC.TestMedicalProcedures.part({isBleeding=true,scratchTime=5})}
        patient.inventory:AddItem(SC.TestMedicalProcedures.item("Base.Bandage"));F.refresh(patient)
        check(M.treat(patient,patient),"medicine quarantine still permits urgent basic wound care")
    end
end
do
    local patient,stock=pain()
    local write=P.writeCare
    P.writeCare=function(subject,field,value)
        if field=="medicalMedicineRecovery" and value.effectVerified then return false end
        return write(subject,field,value)
    end
    okay,reason=M.treat(patient,patient)
    check(okay and reason=="medical_consumption_uncertain" and stock.uses==9 and patient.pillCalls==1,
        "post-native metadata failure retains uncertainty instead of reporting unqualified success")
    P.writeCare=write
    F.clearPain(patient);F.refresh(patient);D.reset()
    local pending=M.pendingCare(patient)
    check(pending and pending.terminalQuarantine and not pending.active and not M.treat(patient,patient)
        and patient.pillCalls==1 and stock.uses==9,"durable pre-effect attempt prevents replay after lost postcondition capture")
end
local function antibiotic(parts)
    local stock=F.item("Base.Antibiotics")
    local patient=F.actor(parts or {SC.TestMedicalProcedures.part({infectedWound=true,infectionLevel=25,scratchTime=4})},{stock})
    patient.moodles[MoodleType.PAIN]=0
    return patient,stock
end
do
    local patient,stock=antibiotic({SC.TestMedicalProcedures.part({isBitten=true})})
    patient.body.infected=true;patient.body.infectionLevel=40
    check(not D.need(patient,M.assess(patient),{disinfectantAvailable=false}) and not patient.eatCalls,
        "Knox alone never qualifies for antibiotics")
    check(patient.inventory:contains(stock),"Knox refusal preserves the exact antibiotic stock")
end
do
    local patient,stock=antibiotic()
    local context={disinfectantAvailable=true}
    check(not D.need(patient,M.assess(patient),context),"local infection with disinfectant first waits for verified disinfect")
    P.writeCare(patient,"medicalInfectionDisinfectHours",{["0"]=P.worldHours()-11.999})
    check(not D.need(patient,M.assess(patient),context),"antibiotic twelve-hour boundary refuses 11.999 hours")
    P.writeCare(patient,"medicalInfectionDisinfectHours",{["0"]=P.worldHours()-12})
    local selected=D.need(patient,M.assess(patient),context)
    check(selected and selected.kind=="take_antibiotics","infection persisting twelve verified game hours qualifies")
    okay,reason=M.treat(patient,patient,nil,{supplyContext=context})
    check(okay and reason=="antibiotics_taken" and patient.eatCalls==1 and not patient.inventory:contains(stock)
        and patient.nativeAntibioticPower==50,"native Eat consumes exactly one whole antibiotic and sets native power")
    F.refresh(patient)
    check(not D.need(patient,M.assess(patient),context),"active native antibiotic course cannot overlap")
end
do
    local patient,stock=antibiotic()
    okay,reason=M.treat(patient,patient,nil,{supplyContext={disinfectantAvailable=false}})
    check(okay and reason=="antibiotics_taken" and patient.eatCalls==1 and not patient.inventory:contains(stock),
        "no permitted disinfectant enables antibiotics through the same treatment")
end
do
    local patient,stock=antibiotic()
    P.writeCare(patient,"medicalInfectionDisinfectHours",{["0"]=P.worldHours()+1})
    check(not D.need(patient,M.assess(patient),{disinfectantAvailable=false}) and patient.inventory:contains(stock),
        "future disinfect metadata fails closed even with no reagent")
end
do
    local patient,stock=antibiotic()
    for index=1,400 do patient.inventory:AddItem(T.item("Base.Junk","Item")) end
    check(D.carriedDoses(patient,"take_antibiotics")==nil and D.disinfectantCarried(patient)==nil,
        "bounded partial carried scans report unknown rather than asserting usable stock or no disinfectant")
    check(not D.need(patient,M.assess(patient)) and patient.inventory:contains(stock),
        "unknown carried reagent availability cannot authorize antibiotics")
end
do
    local patient,stock=antibiotic()
    local active,inside=SC.BaseLife.active,SC.BaseLife.isInside
    local contextProvider=SC.MedicKit.medicineContext
    SC.BaseLife.active=function() return true end;SC.BaseLife.isInside=function() return true end
    SC.MedicKit.medicineContext=nil
    local context={disinfectantAvailable=false,antibioticDoses=1,worstInfectionPatientId="different"}
    check(not D.need(patient,M.assess(patient),context),"one scarce camp dose is reserved for the worst local infection")
    context.worstInfectionPatientId=patient.id
    check(D.need(patient,M.assess(patient),context)~=nil,"worst local infection receives scarce camp stock priority")
    context.antibioticDoses=2;context.worstInfectionPatientId="different"
    check(D.need(patient,M.assess(patient),context)~=nil,"two usable camp doses permit the next eligible patient")
    context.antibioticDoses=nil
    check(not D.need(patient,M.assess(patient),context),"unknown camp dose count fails closed")
    SC.BaseLife.active,SC.BaseLife.isInside=active,inside;SC.MedicKit.medicineContext=contextProvider
end
do
    local patient,stock=antibiotic()
    local active,inside,provider=SC.BaseLife.active,SC.BaseLife.isInside,SC.MedicKit.medicineContext
    SC.BaseLife.active=function() return true end;SC.BaseLife.isInside=function() return true end
    local sawCommit=false
    SC.MedicKit.medicineContext=function(_,_,context)
        if context.stage=="commit" then sawCommit=true end
        return {stockKnown=true,disinfectantAvailable=context.stage=="commit",antibioticDoses=2}
    end
    local visual="active"
    SC.NativeActions={visualStatus=function() return visual end,clearVisual=function() end,cancelVisual=function() return true end}
    okay,reason=M.treat(patient,patient,nil,{supplyContext={disinfectantAvailable=false}})
    check(okay and M.peek(patient)~=nil,"antibiotic selection pins the then-unavailable reagent context")
    visual="completed";okay,reason=M.treat(patient,patient)
    check(not okay and sawCommit and not patient.eatCalls and patient.inventory:contains(stock),
        "commit recomputes permitted camp stock and refuses stale no-disinfectant eligibility")
    SC.NativeActions=nil
    SC.BaseLife.active,SC.BaseLife.isInside,SC.MedicKit.medicineContext=active,inside,provider
end
for _,mode in ipairs({"active","unknown","future"}) do
    local patient,stock=antibiotic()
    if mode=="active" then patient.nativeAntibioticPower=1
    elseif mode=="unknown" then patient.getReduceInfectionPower=function() return nil end
    else patient.nativeAntibioticPower=51 end
    check(not D.need(patient,M.assess(patient),{disinfectantAvailable=false}) and not patient.eatCalls
        and patient.inventory:contains(stock),mode.." native antibiotic state fails closed")
end
do
    local patient,stock=pain();local current=P.worldHours()
    P.writeCare(patient,"medicalMedicineState",{version=1,painDay=math.floor(current/24)+1,painCount=0})
    check(not M.treat(patient,patient) and stock.uses==10,"future daily counter fails closed")
    P.writeCare(patient,"medicalMedicineState",{version=1,painDay=math.floor(current/24),painCount=1,lastPainHours=current+1})
    check(not M.treat(patient,patient) and stock.uses==10,"future dose timestamp fails closed")
end
do
    local patient,stock=pain();local care=P.careStore(patient,true)
    for index=1,510 do care["tooDense"..index]=index end
    check(not M.treat(patient,patient) and stock.uses==10 and not patient.pillCalls,"full optional care budget refuses before native medicine")
    for index=1,510 do care["tooDense"..index]=nil end
    check(M.treat(patient,patient),"recovered optional metadata budget permits a later legitimate dose")
end
check(not SC.Needs.isSafeFoodItem(F.item("Base.Antibiotics")) and not SC.Needs.foodTier(F.item("Base.Antibiotics")),
    "normal food selection never picks antibiotics")
check(not SC.Needs.isSafeFoodItem(F.item("Base.Pills")) and not SC.Needs.foodTier(F.item("Base.Pills")),
    "normal food selection never picks pills")
do
    SC_TEST_CLOCK=SC_TEST_CLOCK+24*3600000
    F.refresh(actor)
    okay,reason=M.treat(actor,actor)
    check(okay and reason=="painkillers_taken" and pills.uses==5
        and P.readCare(actor,"medicalMedicineState").painCount==1,"next game day renews the allowance once without refilling native stock")
end
do
    local start=SC_TEST_CLOCK
    local patient,stock=pain()
    patient.throwAfterEffect=true
    okay,reason=M.treat(patient,patient)
    check(okay and reason=="medical_consumption_uncertain","native pain effect without exact debit creates a hold")
    patient.throwAfterEffect=nil
    F.clearPain(patient)
    local antibioticStock=F.item("Base.Antibiotics")
    patient.inventory:AddItem(antibioticStock)
    patient.body.parts[1]=SC.TestMedicalProcedures.part({infectedWound=true,infectionLevel=25,scratchTime=4,
        isBandaged=true,bandageType="Base.Bandage",bandageLife=10})
    F.refresh(patient)
    okay,reason=M.treat(patient,patient,nil,{supplyContext={disinfectantAvailable=false}})
    check(okay and reason=="antibiotics_taken" and patient.eatCalls==1 and not patient.inventory:contains(antibioticStock),
        "uncertain painkillers permit a real antibiotic dose")
    local saved=SC.Commands.export(patient)
    SC.Commands.reset(patient);D.reset();SC.Commands.restore(patient,saved)
    local function held() return D.pending(patient,"take_painkillers") end
    SC_TEST_CLOCK=start+24*3600000-1000
    check(held() and P.readCare(patient,"medicalMedicineState").painCount==1,
        "successful unrelated medicine and reload preserve the full cooldown and charged daily allowance")
    SC_TEST_CLOCK=start+24*3600000
    for _,field in ipairs({"nativePainEffect","nativePainDelta","nativePainReduction"}) do
        patient[field]=1
        check(held(),field.." must reach zero before pain quarantine archives")
        patient[field]=0
    end
    patient.nativePainDelta=nil
    check(held(),"unknown analgesic activity cannot retire an uncertain dose")
    patient.nativePainDelta=0
    check(not held() and P.readCare(patient,"medicalMedicineQuarantines").take_painkillers.archivedHours==P.worldHours()
        and stock.uses==10 and patient.pillCalls==1 and P.readCare(patient,"medicalMedicineState").painCount==1,
        "native clearance at 24 hours archives without replaying, debiting or refunding painkillers")
    patient.body.parts[1]=SC.TestMedicalProcedures.part({})
    F.refresh(patient)
    okay,reason=M.treat(patient,patient)
    check(okay and reason=="painkillers_taken" and patient.pillCalls==2 and stock.uses==9,
        "new eligible pain gets one newly accounted dose after archival")
    SC_TEST_CLOCK=start
end
do
    local start=SC_TEST_CLOCK
    local patient,stock=antibiotic()
    patient.throwAfterEffect=true
    M.treat(patient,patient,nil,{supplyContext={disinfectantAvailable=false}})
    patient.throwAfterEffect=nil
    patient.body.parts[1]=SC.TestMedicalProcedures.part({})
    patient.moodles[MoodleType.PAIN]=2
    patient.inventory:AddItem(F.item("Base.Pills"));F.refresh(patient)
    okay,reason=M.treat(patient,patient)
    check(okay and reason=="painkillers_taken" and patient.pillCalls==1,
        "uncertain antibiotics permit a real analgesic dose")
    SC_TEST_CLOCK=start+24*3600000
    check(D.pending(patient,"take_antibiotics"),"active native antibiotic power retains its own hold at 24 hours")
    patient.nativeAntibioticPower=0
    check(not D.pending(patient,"take_antibiotics") and P.readCare(patient,"medicalMedicineQuarantines").take_antibiotics.archivedHours
        and patient.eatCalls==1 and patient.inventory:contains(stock),"cleared antibiotic power archives without a second dose or stock change")
    SC_TEST_CLOCK=start
end
do
    local start=SC_TEST_CLOCK
    local patient=pain()
    P.writeCare(patient,"medicalMedicineState",{version=1,painDay=math.floor(P.worldHours()/24),
        painCount=3,lastPainHours=P.worldHours()})
    P.writeCare(patient,"medicalMedicineRecovery",{version=-1,kind="take_antibiotics"})
    check(not D.pending(patient,"take_painkillers") and D.pending(patient,"take_antibiotics")
        and P.readCare(patient,"medicalMedicineState").painCount==3,
        "a malformed legacy receipt preserves its recognizable kind and the already charged daily count")
    P.writeCare(patient,"medicalMedicineRecovery",{version=-1,kind="unknown"})
    check(D.pending(patient,"take_painkillers") and D.pending(patient,"take_antibiotics"),
        "an unidentifiable legacy dose conservatively holds both possible medicines")
    SC_TEST_CLOCK=start+24*3600000
    patient.nativePainEffect=-0.0015716552734375
    check(not D.pending(patient) and not patient.pillCalls and not patient.eatCalls,
        "malformed receipts also expire from first observation and clear native evidence without replay")
    SC_TEST_CLOCK=start
end
SC.NativeActions,SC.ActionSupervisor,U.move,U.stop=native,service,move,stop
SC_TEST_REPORT="MEDICAL_MEDICINES_PASS checks="..checks
print(SC_TEST_REPORT)
