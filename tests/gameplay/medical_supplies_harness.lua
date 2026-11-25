-- SPDX-License-Identifier: MIT
-- Real camp storage policy and the production medicine context, read only.
local SC=SurvivorCompanion
local B,K,S,D,M,P=SC.BaseLife,SC.MedicKit,SC.MedicalSupplies,SC.MedicalMedicines,SC.Medical,SC.MedicalProcedures
local F,T,C=SC.TestMedicalMedicines,SC.TestFixture,SC.TestMedicalProcedures
local checks=0
local function check(value,reason) checks=checks+1;assert(value,"medical supplies "..checks..": "..reason) end
local function infected(level)
    return C.part({infectedWound=true,infectionLevel=level,scratchTime=5,isBandaged=true,bandageType="Base.Bandage",bandageLife=10})
end
local function resident(parts,role)
    local actor=F.actor(parts or {C.part({})},{})
    actor.square=T.cell:getGridSquare(5,5,0);actor.moodles[MoodleType.PAIN]=0
    SC.Commands.peek(actor).order="base_duty"
    check(B.assign(actor.id,role or "generalist",true),"actual resident is assigned to camp")
    return actor
end
local function setup(items)
    check(SC.BaseWork.reset(),"prior camp work is released")
    B.reset();S.reset()
    check(B.create(T.cell:getGridSquare(5,5,0),"Medicine stock observations"),"real camp is created")
    local helper=resident(nil,"medic")
    local patient=resident({infected(5)})
    local worst=resident({infected(25)})
    local shelf=T.cell:getGridSquare(6,5,0);shelf.objects={}
    local source,object=T.containerObject(shelf,items or {})
    function object:getObjectIndex()
        for index,candidate in ipairs(self.square.objects) do if candidate==self then return index-1 end end
        return -1
    end
    local okay,row=B.registerStorage(object,"medical")
    local resolved,_,reason=B.resolveContainer(okay and row or nil)
    check(okay and resolved==source,"actual medical storage resolves its native container: "..tostring(row).."/"..tostring(reason))
    return helper,patient,worst,source,row,object
end
local function complete(helper,patient)
    local context
    for _=1,40 do
        context=K.medicineContext(helper,patient,{})
        if context.stockKnown then return context end
    end
    return context
end
do
    local one=F.item("Base.Antibiotics")
    local helper,patient,worst,source,row=setup({one})
    local context=complete(helper,patient)
    check(context.stockKnown and context.antibioticDoses==1 and context.disinfectantAvailable==false,
        "complete permitted storage observation counts one exact usable dose and no reagent")
    check(context.worstInfectionPatientId==worst.id,"one scarce camp dose is reserved for the worst eligible wound infection")
    check(not D.need(patient,M.assess(patient),context),"less infected resident cannot use the scarce camp course")
    check(D.need(worst,M.assess(worst),K.medicineContext(helper,worst,{}))~=nil,"worst eligible resident may receive the scarce course")
    source:AddItem(F.item("Base.Antibiotics"))
    context=complete(helper,patient)
    check(context.stockKnown and context.antibioticDoses==2 and D.need(patient,M.assess(patient),context)~=nil,
        "two permitted camp doses release scarcity ordering for the next eligible resident")
    check(source:contains(one) and not patient.eatCalls and not worst.eatCalls,"stock observations never transfer or consume camp medicine")
    check(B.setReserve(row.id,"Base.Antibiotics",2),"public reserve policy protects both stored courses")
    context=K.medicineContext(helper,patient,{stage="commit"})
    check(context.stockKnown and context.antibioticDoses==0,"reserved storage stock contributes no usable doses")
    B.setReserve(row.id,"Base.Antibiotics",0)
    row.withdrawals=false
    context=K.medicineContext(helper,patient,{stage="commit"})
    check(context.stockKnown and context.antibioticDoses==0,"disabled withdrawals remove medicine from permitted stock")
    row.withdrawals=true
    check(B.setRestriction(helper.id,"quarantine","medical-supplies-test"),"public infection restriction removes the helper's work permission")
    context=K.medicineContext(helper,patient,{stage="commit"})
    check(context.stockKnown and context.antibioticDoses==0,"helper work restrictions exclude every otherwise permitted storage source")
    check(B.setRestriction(helper.id,nil,"medical-supplies-test"),"public work restriction can be cleared")
    context=K.medicineContext(helper,patient,{stage="commit"})
    check(context.stockKnown and context.antibioticDoses==2,"cleared work permission restores the actual allowed dose count")
end
do
    local favorite=F.item("Base.Antibiotics",{favorite=true})
    local loan=F.item("Base.Antibiotics");loan:getModData().SC_PlayerLoan="player"
    local manual=F.item("Base.Antibiotics");manual:getModData().SC_ManualEquipFor="player"
    local protected=F.item("Base.Antibiotics")
    local helper,patient,_,source=setup({favorite,loan,manual,protected})
    local previous=SC.PersonalItems.isProtected
    SC.PersonalItems.isProtected=function(item,...) return item==protected or previous(item,...) end
    local context=K.medicineContext(helper,patient,{stage="commit"})
    check(context.stockKnown and context.antibioticDoses==0,"favorite, loaned, manual and protected camp medicines are unusable")
    check(#source.items==4,"protected stock identities stay present and untouched")
    SC.PersonalItems.isProtected=previous
end
do
    local items={}
    for index=1,150 do items[index]=C.item("Base.Junk") end
    items[#items+1]=F.item("Base.Antibiotics")
    local helper,patient=setup(items)
    local first=K.medicineContext(helper,patient,{})
    check(not first.stockKnown,"first bounded 128-item slice cannot assert absence in the unscanned tail")
    local context=complete(helper,patient)
    check(context.stockKnown and context.antibioticDoses==1,"continued bounded observation reaches the dose beyond item 128")
end
do
    local dose,junk=F.item("Base.Antibiotics"),C.item("Base.Junk")
    local helper,patient,_,source=setup({dose,junk})
    local initial=complete(helper,patient)
    check(initial.stockKnown and initial.disinfectantAvailable==false,"same-count replacement control first proves no disinfectant")
    source:Remove(junk)
    local wipes=C.item("Base.AlcoholWipes",{drainable=true,alcoholPower=4,uses=2})
    source:AddItem(wipes)
    local fresh=K.medicineContext(helper,patient,{stage="commit"})
    check(fresh.stockKnown and fresh.disinfectantAvailable==true and fresh.antibioticDoses==1,
        "commit scans exact contents again when same-count replacement adds a permitted disinfectant")
    check(not D.antibioticEligible(patient,M.assess(patient),{helper=helper,disinfectantAvailable=fresh.disinfectantAvailable}),
        "new disinfectant stops the no-reagent antibiotic exception before a verified twelve-hour window")
    P.writeCare(patient,"medicalInfectionDisinfectHours",{["0"]=P.worldHours()-11.999})
    check(not D.antibioticEligible(patient,M.assess(patient),{helper=helper,disinfectantAvailable=true}),
        "real context still waits at 11.999 hours after verified disinfection")
    P.writeCare(patient,"medicalInfectionDisinfectHours",{["0"]=P.worldHours()-12})
    check(D.antibioticEligible(patient,M.assess(patient),{helper=helper,disinfectantAvailable=true}),
        "persistent actual wound infection becomes eligible at twelve verified game hours")
    check(source:contains(wipes) and source:contains(dose) and not patient.eatCalls,"context and eligibility are read-only over exact identities")
end
do
    local helper,patient,_,source,row,object=setup({F.item("Base.Antibiotics")})
    check(complete(helper,patient).antibioticDoses==1,"source replacement control first observes one course")
    local replacement=T.inventory({F.item("Base.Antibiotics"),F.item("Base.Antibiotics")})
    function object:getContainer() return replacement end
    local context=K.medicineContext(helper,patient,{stage="commit"})
    check(context.stockKnown and context.antibioticDoses==2 and B.resolveContainer(row)==replacement,
        "source-container replacement is re-resolved before counting usable stock")
    check(#source.items==1 and #replacement.items==2,"source changes never move or compensate for stock")
    check(B.setStorageCategory(row.id,"memorial"),"public category policy changes the permitted source")
    context=K.medicineContext(helper,patient,{stage="commit"})
    check(context.stockKnown and context.antibioticDoses==0,"memorial category immediately prevents medication withdrawal")
end
do
    local helper,patient=setup({})
    for index=1,401 do helper.inventory:AddItem(C.item("Base.Junk")) end
    local context=K.medicineContext(helper,patient,{stage="commit"})
    check(not context.stockKnown and context.disinfectantAvailable==nil and context.antibioticDoses==nil,
        "unknown carried scan remains unknown in the actual camp context without arithmetic failure")
end
for _,mode in ipairs({"size","entry"}) do
    local helper,patient,_,source=setup({})
    local list
    if mode=="size" then list={size=function() error("unreadable native size") end}
    else list={size=function() return 1 end,get=function() error("unreadable native entry") end} end
    function source:getItems() return list end
    local context=K.medicineContext(helper,patient,{stage="commit"})
    check(not context.stockKnown,"unreadable stored "..mode.." cannot prove medicine or disinfectant absence")
end
do
    local dose=F.item("Base.Antibiotics")
    local helper,patient,worst,source,row=setup({dose})
    local utility=SC.GameplayUtil
    local clock,carriedDoses,hash=T.clock,D.carriedDoses,utility.stableHash
    utility.stableHash=function(key)
        if key:find(":camp%-stock:",1) then return 0 end
        return hash(key)
    end
    local reads=0
    D.carriedDoses=function(...)
        reads=reads+1
        return carriedDoses(...)
    end
    local function advise()
        return S.context(helper,patient,{stage="advisory"})
    end
    local cold=advise()
    local before=reads
    check(cold.stockKnown and cold.worstInfectionPatientId==worst.id and before>0,
        "a complete cold advisory verifies carriers and the scarce-dose winner")
    T.clock=clock+1999
    local warm=advise()
    check(warm.observedAt==cold.observedAt and warm.worstInfectionPatientId==worst.id and reads==before,
        "complete advisory stock and eligibility avoid repeated carrier searches inside two seconds")
    T.clock=clock+2000
    check(advise().observedAt>cold.observedAt and reads>before,
        "advisory freshness expires at two seconds from stock observation")
    before=reads
    check(B.setReserve(row.id,"Base.Antibiotics",1) and advise().antibioticDoses==0 and reads>before,
        "a revised reserve invalidates complete stock advice immediately")
    B.setReserve(row.id,"Base.Antibiotics",0)
    check(advise().antibioticDoses==1,"cleared reserve is visible on the next advisory")
    local kit=C.item("Base.FirstAidKit")
    kit.nestedInventory=T.inventory({})
    function kit.nestedInventory:getContainingItem() return kit end
    helper.inventory:AddItem(kit)
    SC.InventoryIndex.touch(helper)
    check(advise().antibioticDoses==1,"a newly carried empty kit preserves existing stock")
    local added=F.item("Base.Antibiotics")
    SC.GameplayUtil.addItem(kit.nestedInventory,added)
    check(advise().antibioticDoses==2,"a notified nested inventory change invalidates advice")
    local junk=C.item("Base.Junk")
    source:Remove(dose)
    source:AddItem(junk)
    check(S.context(helper,patient,{stage="prepare"}).antibioticDoses==1
        and S.context(helper,patient,{stage="commit"}).antibioticDoses==1,
        "prepare and commit both see unreported same-count changes during a warm advisory")
    D.carriedDoses,T.clock,utility.stableHash=carriedDoses,clock,hash
end
SC_TEST_REPORT="MEDICAL_SUPPLIES_PASS checks="..checks
print(SC_TEST_REPORT)
