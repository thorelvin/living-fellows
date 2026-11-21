-- SPDX-License-Identifier: MIT
-- Medicine is a whole-body step of Medical's existing claimed treatment.
-- Native JustTookPill/Eat perform both the effect and their own exact debit.
SurvivorCompanion=SurvivorCompanion or {}
local SC=SurvivorCompanion
SC.MedicalMedicines=SC.MedicalMedicines or {}
local M=SC.MedicalMedicines
local receipts={}
local kinds={take_painkillers=true,take_antibiotics=true}
local function U() return SC.GameplayUtil end
local function P() return SC.MedicalProcedures end
local function call(value,name,...) return U().call(value,name,...) end
local function finite(value) return type(value)=="number" and value==value and value>-math.huge and value<math.huge end
local function number(value,name)
    local result,known=call(value,name)
    if known and finite(result) then return result end
end
local function flag(value,name)
    local result,known=call(value,name)
    if known and type(result)=="boolean" then return result end
end
local function id(actor) return P().actorId(actor) end
local function hours() return P().worldHours() end
local function isPlayer(actor)
    if type(getSpecificPlayer)=="function" then
        for index=0,3 do local okay,player=pcall(getSpecificPlayer,index);if okay and player==actor then return true end end
    end
    return false
end
local function checkedTable(value,allowed,maximum)
    if type(value)~="table" then return false end
    local count=0
    for key in pairs(value) do count=count+1;if not allowed[key] or count>maximum then return false end end
    return true
end
local ledgerFields={version=true,painDay=true,painCount=true,lastPainHours=true,lastAntibioticHours=true}
local function ledger(patient,current)
    local saved=P().readCare(patient,"medicalMedicineState")
    if saved==nil then
        if P().readCare(patient,"medicalMedicineRecovery")~=nil then return nil end
        return {version=1,painDay=math.floor(current/24),painCount=0}
    end
    if not checkedTable(saved,ledgerFields,5) or saved.version~=1
        or not finite(saved.painDay) or saved.painDay<0 or saved.painDay~=math.floor(saved.painDay)
        or saved.painDay>math.floor(current/24) or not finite(saved.painCount)
        or saved.painCount<0 or saved.painCount>4 or saved.painCount~=math.floor(saved.painCount) then return nil end
    for _,key in ipairs({"lastPainHours","lastAntibioticHours"}) do
        local value=saved[key]
        if value~=nil and (not finite(value) or value<0 or value>current) then return nil end
    end
    if saved.painCount>0 and (saved.lastPainHours==nil or math.floor(saved.lastPainHours/24)~=saved.painDay)
        or saved.painCount==0 and saved.lastPainHours~=nil and math.floor(saved.lastPainHours/24)==saved.painDay then return nil end
    local prior=P().readCare(patient,"medicalMedicineRecovery")
    if prior~=nil then
        if type(prior)~="table" or not finite(prior.hours) then return nil end
        local last=prior.kind=="take_painkillers" and saved.lastPainHours
            or prior.kind=="take_antibiotics" and saved.lastAntibioticHours
        if not finite(last) or last<prior.hours then return nil end
    end
    local result={};for key,value in pairs(saved) do result[key]=value end
    if result.painDay<math.floor(current/24) then result.painDay,result.painCount=math.floor(current/24),0 end
    return result
end
-- A dose has a pending delta, a running native timer, and possibly separate
-- food analgesia. All three must be known and clear before another dose.
function M.nativeState(patient,kind)
    if kind=="take_painkillers" then
        local body=select(1,call(patient,"getBodyDamage"))
        local effect,delta,reduction=number(patient,"getPainEffect"),number(patient,"getPainDelta"),number(body,"getPainReduction")
        -- Native expiry may leave a small negative timer; the next update
        -- clears its pending delta. A negative timer alone is spent medicine.
        if effect==nil or delta==nil or reduction==nil or delta<0 or reduction<0 then return nil end
        return {effect=effect,delta=delta,reduction=reduction,active=effect>0 or delta>0 or reduction>0}
    elseif kind=="take_antibiotics" then
        local power=number(patient,"getReduceInfectionPower")
        if power==nil or power<0 or power>50 then return nil end
        return {power=power,active=power>0}
    end
end
local function moodle(patient)
    local level=U().moodleLevel(patient,"PAIN",-1)
    return finite(level) and level>=0 and level<=4 and level==math.floor(level) and level or nil
end
local function needsIdle(actor)
    if SC.NativeActions and type(SC.NativeActions.needsStatus)=="function" then
        local okay,active,tracked=pcall(SC.NativeActions.needsStatus,actor)
        return okay and active~=true and tracked==nil
    end
    return true
end
local function prohibited(actor,item,ancestor)
    if not SC.PersonalItems or type(SC.PersonalItems.isProtected)~="function"
        or SC.PersonalItems.isProtected(item,actor,"medical_consume") then return true end
    if flag(item,"isFavorite")~=false then return true end
    if select(1,call(actor,"getPrimaryHandItem"))==item or select(1,call(actor,"getSecondaryHandItem"))==item then return true end
    local data,known=call(item,"getModData")
    if not known or type(data)~="table" then return true end
    for key,value in pairs(data) do
        if type(key)=="string" and value~=nil and value~=false then
            local lower=string.lower(key)
            if string.sub(lower,1,3)=="sc_" or string.sub(lower,1,3)=="lf_" then
                if string.find(lower,"loan",1,true) or string.find(lower,"borrow",1,true)
                    or string.find(lower,"manual",1,true) then
                    local ownKit=ancestor and key=="LF_MedicKitLoan" and SC.MedicKit
                        and SC.MedicKit.mayUseContents and SC.MedicKit.mayUseContents(actor,item)==true
                    if not ownKit then return true end
                end
            end
        end
    end
    return false
end
function M.itemAllowed(actor,item)
    if not item or not needsIdle(actor) then return false end
    local okay,entry=P().itemAllowed(actor,item,false)
    if not okay then return false end
    for _,candidate in ipairs({item,unpack(entry.ancestors or {})}) do if prohibited(actor,candidate,candidate~=item) then return false end end
    return true,entry
end
function M.supplyDoses(item,kind)
    if kind=="painkillers" or kind=="Base.Pills" then kind="take_painkillers" end
    if kind=="antibiotics" or kind=="Base.Antibiotics" then kind="take_antibiotics" end
    local expected=kind=="take_painkillers" and "Base.Pills" or kind=="take_antibiotics" and "Base.Antibiotics" or nil
    if not expected or U().itemType(item)~=expected then return 0 end
    if kind=="take_painkillers" then
        local uses,delta=number(item,"getCurrentUses"),number(item,"getUseDelta")
        if flag(item,"IsDrainable")~=true or not uses or uses<0 or uses>10 or uses~=math.floor(uses)
            or not delta or math.abs(delta-0.1)>0.000001 then return nil end
        return uses
    else
        if number(item,"getReduceInfectionPower")~=50 or number(item,"getHungerChange")~=0
            or flag(item,"isRotten")~=false or flag(item,"isBurnt")~=false
            or number(item,"getPoisonPower")~=0 then return nil end
        return 1
    end
end
function M.disinfectantItem(item)
    local fluid,known=call(item,"getFluidContainer")
    if not known then return nil end
    if fluid then
        local amount=number(fluid,"getAmount")
        local properties=select(1,call(fluid,"getProperties"))
        local alcohol=number(properties,"getAlcohol")
        if amount==nil or alcohol==nil then return nil end
        return amount>0.15 and alcohol/amount+0.001>=0.4
    end
    local drainable=flag(item,"IsDrainable")
    if drainable==nil then return nil end
    if not drainable then return false end
    local power,uses=number(item,"getAlcoholPower"),number(item,"getCurrentUses")
    if power==nil or uses==nil then return nil end
    return power==4 and uses>=1
end
local function stock(actor,item,kind)
    local doses=M.supplyDoses(item,kind)
    if not doses or doses<1 then return nil end
    local allowed,entry=M.itemAllowed(actor,item)
    if not allowed then return nil end
    local nativeId=number(item,"getID")
    if not nativeId or nativeId<=0 or nativeId~=math.floor(nativeId) then return nil end
    entry.nativeId,entry.itemType=nativeId,U().itemType(item)
    if kind=="take_painkillers" then entry.uses=doses else entry.present=true end
    return entry
end
function M.carriedDoses(actor,kind)
    if kind=="painkillers" or kind=="Base.Pills" then kind="take_painkillers" end
    if kind=="antibiotics" or kind=="Base.Antibiotics" then kind="take_antibiotics" end
    local inventory=U().inventory(actor)
    if not inventory then return nil end
    local items,containers=U().inventoryItemsDeep(inventory,400,15)
    local sources={inventory};local seen={[inventory]=true}
    for _,container in ipairs(containers) do sources[#sources+1]=container;seen[container]=true end
    local expected=0
    for _,source in ipairs(sources) do
        local list,known=call(source,"getItems")
        if not known or not list then return nil end
        local count,read=call(list,"size")
        if not read and type(list)=="table" and not U().hasMethod(list,"size") then count=#list end
        if not finite(count) or count<0 or count~=math.floor(count) then return nil end
        expected=expected+count
        if expected>400 then return nil end
    end
    if expected~=#items then return nil end
    local total,seenItems=0,{}
    for _,item in ipairs(items) do
        if seenItems[item] then return nil end
        seenItems[item]=true
        local nested=U().containedInventory(item)
        if nested and not seen[nested] or not nested and (U().instanceOf(item,"InventoryContainer")
            or select(1,call(item,"getCategory"))=="Container") then return nil end
        local entry=stock(actor,item,kind)
        if entry then total=total+(entry.uses or 1) end
    end
    return total
end
local function carriedDisinfectant(actor)
    if not needsIdle(actor) then return nil end
    if type(P().hasDisinfectant)=="function" then return P().hasDisinfectant(actor) end
    return nil
end
function M.disinfectantCarried(actor) return carriedDisinfectant(actor) end
local function supplyContext(helper,patient,context)
    local provider=M.supplyContext or SC.MedicKit and SC.MedicKit.medicineContext
    if type(provider)~="function" then return nil end
    local okay,value=pcall(provider,helper or patient,patient,context)
    return okay and type(value)=="table" and value or nil
end
function M.disinfectantAvailable(helper,patient,context)
    context=type(context)=="table" and context or {}
    local carried=carriedDisinfectant(helper or patient)
    if carried==true then return true end
    if type(context.disinfectantAvailable)=="boolean" then return context.disinfectantAvailable end
    local provided=supplyContext(helper,patient,context)
    if provided and type(provided.disinfectantAvailable)=="boolean" then return provided.disinfectantAvailable end
    if SC.BaseLife and SC.BaseLife.active and SC.BaseLife.active()
        and SC.BaseLife.isInside and SC.BaseLife.isInside(patient) then return nil end
    return carried
end
function M.worstInfection(assessment)
    local worst=0
    for _,wound in ipairs(assessment and assessment.wounds or {}) do
        if wound.infected==true then
            if not finite(wound.woundInfectionLevel) or wound.woundInfectionLevel<0 then return nil end
            worst=math.max(worst,wound.woundInfectionLevel)
        end
    end
    return worst
end
local function antibioticEligible(patient,assessment,context,helper,current,ranking)
    local infected=false
    local camp=SC.BaseLife and SC.BaseLife.active and SC.BaseLife.active()
        and SC.BaseLife.isInside and SC.BaseLife.isInside(patient)
    local supplied=context
    if camp and not ranking and (M.supplyContext or SC.MedicKit and SC.MedicKit.medicineContext) then
        supplied=supplyContext(helper,patient,context)
        if not supplied or supplied.stockKnown~=true then return false,"medical_supplies_unreadable" end
    end
    local available=carriedDisinfectant(helper or patient)
    if available~=true then
        available=supplied and supplied.disinfectantAvailable
        if type(available)~="boolean" then available=M.disinfectantAvailable(helper,patient,context) end
    end
    for _,wound in ipairs(assessment.wounds or {}) do
        if wound.infected==true then
            infected=true
            local first=P().firstDisinfectHours and P().firstDisinfectHours(patient,wound.index)
            if first==false then return false,"medical_medicine_unreadable" end
            if available==false or finite(first) and first>=0 and first<=current and current-first>=12 then
                if camp and not ranking then
                    local doses=supplied and supplied.antibioticDoses
                    if not finite(doses) or doses<0 or doses~=math.floor(doses) then return false,"medical_supplies_unreadable" end
                    if doses<2 and (not supplied.worstInfectionPatientId or tostring(supplied.worstInfectionPatientId)~=id(patient)) then
                        return false,"antibiotics_reserved_for_worst"
                    end
                end
                return true
            end
        end
    end
    return false,infected and "antibiotics_waiting_disinfect" or "no_local_wound_infection"
end
function M.antibioticEligible(patient,assessment,context)
    local current=hours()
    if not current or current<0 or isPlayer(patient) then return false end
    context=type(context)=="table" and context or {}
    local native=M.nativeState(patient,"take_antibiotics")
    if not native or native.active or M.pending(patient,"take_antibiotics") or not ledger(patient,current) then return false end
    return antibioticEligible(patient,assessment or {},context,context.helper or patient,current,true)
end
function M.handles(kind) return kinds[kind]==true end
function M.key(patient,kind) return id(patient)..":whole:"..kind end
local receiptFields={version=true,patientId=true,helperId=true,kind=true,itemId=true,itemType=true,hours=true,
    attempted=true,effectVerified=true,debitVerified=true,quarantined=true,terminalQuarantine=true,
    reason=true,usesBefore=true,usesAfter=true,effectBefore=true,deltaBefore=true,reductionBefore=true,
    powerBefore=true,effectAfter=true,deltaAfter=true,reductionAfter=true,powerAfter=true}
local function receiptValid(saved,patient,current)
    if not checkedTable(saved,receiptFields,24) or saved.version~=1 or saved.patientId~=id(patient)
        or not kinds[saved.kind] or type(saved.helperId)~="string" or #saved.helperId>128
        or not finite(saved.itemId) or saved.itemId<=0 or saved.itemId~=math.floor(saved.itemId)
        or saved.itemType~=(saved.kind=="take_painkillers" and "Base.Pills" or "Base.Antibiotics")
        or not finite(saved.hours) or saved.hours<0 or saved.hours>current then return false end
    for _,key in ipairs({"attempted","effectVerified","debitVerified","quarantined","terminalQuarantine"}) do
        if type(saved[key])~="boolean" then return false end
    end
    for _,key in ipairs({"usesBefore","usesAfter","effectBefore","deltaBefore","reductionBefore","powerBefore",
        "effectAfter","deltaAfter","reductionAfter","powerAfter"}) do
        if saved[key]~=nil and (not finite(saved[key]) or key~="effectBefore" and saved[key]<0) then return false end
    end
    if not saved.attempted then return false end
    if saved.kind=="take_painkillers" then
        if not finite(saved.usesBefore) or saved.usesBefore<1 or saved.usesBefore~=math.floor(saved.usesBefore)
            or not finite(saved.effectBefore) or saved.effectBefore>0 or saved.deltaBefore~=0 or saved.reductionBefore~=0 then return false end
        if saved.effectVerified and (saved.effectAfter~=5400 or not finite(saved.deltaAfter)
            or math.abs(saved.deltaAfter-0.45)>0.00001 and math.abs(saved.deltaAfter-0.15)>0.00001) then return false end
        if saved.debitVerified and saved.usesAfter~=saved.usesBefore-1 then return false end
    elseif saved.powerBefore~=0 or saved.effectVerified and saved.powerAfter~=50 then return false end
    return true
end
local doseKinds={"take_painkillers","take_antibiotics"}
local holdFields={since=true,itemId=true,archivedHours=true}
local function holdView(patient,kind,reason)
    return {kind=kind,patientId=id(patient),quarantined=true,terminalQuarantine=true,
        reason=reason or "medical_consumption_uncertain"}
end
-- Keep one forensic row per kind. An unrelated dose can own the ordinary
-- recovery slot immediately. An archived row is evidence only, never a dose.
function M.pending(patient,wanted)
    local P=P()
    local current=hours()
    local live=receipts[id(patient)]
    local saved=P.readCare(patient,"medicalMedicineRecovery")
    if saved==nil and live then saved=live.saved end
    local holds=P.readCare(patient,"medicalMedicineQuarantines")
    if saved==nil and holds==nil then return nil end
    if not current or current<0 then
        return holdView(patient,wanted or doseKinds[1],"medical_medicine_unreadable")
    end
    local rows,changed={},false
    if holds~=nil and not checkedTable(holds,kinds,2) then
        for _,kind in ipairs(doseKinds) do rows[kind]={since=current} end
        changed=true
    else
        for _,kind in ipairs(doseKinds) do rows[kind]=holds and holds[kind] end
    end
    local valid=saved~=nil and receiptValid(saved,patient,current)
    if saved~=nil and not (valid and saved.effectVerified and saved.debitVerified and not saved.quarantined) then
        if live and valid and not live.terminalQuarantine and not saved.quarantined
            and live.saved.itemId==saved.itemId and live.saved.hours==saved.hours and live.saved.helperId==saved.helperId then return live end
        local knownKind=type(saved)=="table" and kinds[saved.kind] and saved.kind
        local since=valid and saved.hours or current
        for _,kind in ipairs(doseKinds) do
            if not knownKind or knownKind==kind then
                rows[kind]={since=since,itemId=valid and saved.itemId or nil}
            end
        end
        if not P.writeCare(patient,"medicalMedicineRecovery",nil,{medicalMedicineQuarantines=rows}) then
            return holdView(patient,wanted or knownKind or doseKinds[1],"medical_medicine_unreadable")
        end
        receipts[id(patient)]=nil
    end
    local pending
    for _,kind in ipairs(doseKinds) do
        local row=rows[kind]
        if row~=nil and (not wanted or kind==wanted) then
            if not checkedTable(row,holdFields,3) or not finite(row.since) or row.since<0 or row.since>current
                or row.itemId~=nil and (not finite(row.itemId) or row.itemId<=0 or row.itemId~=math.floor(row.itemId)) then
                row={since=current};rows[kind]=row;changed=true
            end
            if not finite(row.archivedHours) or row.archivedHours<row.since+24 or row.archivedHours>current then
                local native=current-row.since>=24 and M.nativeState(patient,kind)
                -- The game can leave a spent pain timer fractionally below zero.
                -- nativeState requires a clear delta/reduction or antibiotic power.
                if native and not native.active then
                    rows[kind]={since=row.since,itemId=row.itemId,archivedHours=current};changed=true
                elseif not pending then pending=holdView(patient,kind) end
            end
        end
    end
    if changed and not P.writeCare(patient,"medicalMedicineQuarantines",rows) then
        return holdView(patient,wanted or doseKinds[1],"medical_medicine_unreadable")
    end
    return pending
end
function M.pendingView(patient)
    local pending=M.pending(patient)
    if not pending then return nil end
    return {kind=pending.kind,key=M.key(patient,pending.kind),wholeBody=true,pending=true,committed=true,
        quarantined=pending.quarantined==true,terminalQuarantine=pending.terminalQuarantine==true,
        active=pending.terminalQuarantine~=true,owner=pending.terminalQuarantine~=true and pending.helperId or nil}
end
local function policy(patient,kind,assessment,context,helper)
    if isPlayer(patient) then return false,"player_takes_own_medicine" end
    local current=hours()
    if not current or current<0 then return false,"medical_medicine_unreadable" end
    local pending=M.pending(patient,kind)
    if pending then return false,pending.reason or "medical_consumption_uncertain" end
    local state=ledger(patient,current)
    if not state then return false,"medical_medicine_unreadable" end
    local native=M.nativeState(patient,kind)
    if not native then return false,"medical_medicine_unreadable" end
    if native.active then return false,kind=="take_painkillers" and "painkillers_still_working" or "antibiotics_still_working" end
    if kind=="take_painkillers" then
        local pain=moodle(patient)
        if not pain then return false,"medical_medicine_unreadable" end
        if pain<2 then return false,"no_painkiller_need" end
        if state.painCount>=4 then return false,"painkiller_daily_limit" end
    else
        local eligible,reason=antibioticEligible(patient,assessment,context,helper,current)
        if not eligible then return false,reason end
    end
    return true,nil,state,native,current
end
function M.need(patient,assessment,context)
    if not patient or isPlayer(patient) then return nil end
    context=type(context)=="table" and context or {}
    local pending=M.pending(patient)
    if pending and not pending.terminalQuarantine then
        return {kind=pending.kind,key=M.key(patient,pending.kind),wholeBody=true,rank=0,visitEligible=true,pending=true}
    end
    for _,kind in ipairs({"take_painkillers","take_antibiotics"}) do
        if policy(patient,kind,assessment or {},context,context.helper or patient) then
            return {kind=kind,key=M.key(patient,kind),wholeBody=true,rank=kind=="take_painkillers" and 11 or 12,visitEligible=true}
        end
    end
end
function M.prepare(helper,patient,need,context)
    if not need or not kinds[need.kind] then return nil,"medical_need_changed" end
    context=type(context)=="table" and context or {}
    local okay,reason=policy(patient,need.kind,SC.Medical.assess(patient),context,helper)
    if not okay then return nil,reason end
    if not needsIdle(helper) or not needsIdle(patient) then return nil,"medical_needs_active" end
    for _,item in ipairs(U().inventoryItemsDeep(U().inventory(helper),400,16)) do
        local entry=stock(helper,item,need.kind)
        if entry then
            local resources={item};for _,ancestor in ipairs(entry.ancestors or {}) do resources[#resources+1]=ancestor end
            return {kind=need.kind,key=need.key,patientId=id(patient),helperId=id(helper),entry=entry,resources=resources}
        end
    end
    return nil,need.kind=="take_painkillers" and "no_painkillers" or "no_antibiotics"
end
function M.validatePlan(helper,patient,plan,context)
    if type(plan)~="table" or not kinds[plan.kind] or plan.patientId~=id(patient) or plan.helperId~=id(helper)
        or plan.key~=M.key(patient,plan.kind) or not plan.entry then return false,"medical_need_changed" end
    local entry=stock(helper,plan.entry.item,plan.kind)
    if not entry or entry.nativeId~=plan.entry.nativeId or entry.source~=plan.entry.source
        or entry.uses~=plan.entry.uses then return false,plan.kind=="take_painkillers" and "no_painkillers" or "no_antibiotics" end
    if not needsIdle(patient) then return false,"medical_needs_active" end
    return policy(patient,plan.kind,SC.Medical.assess(patient),context,helper)
end
local function saveReceipt(patient,saved)
    if P().writeCare(patient,"medicalMedicineRecovery",saved)~=true then return false end
    local actual=P().readCare(patient,"medicalMedicineRecovery")
    return type(actual)=="table" and actual.patientId==saved.patientId and actual.helperId==saved.helperId
        and actual.itemId==saved.itemId and actual.hours==saved.hours and actual.attempted==saved.attempted
        and actual.effectVerified==saved.effectVerified and actual.debitVerified==saved.debitVerified
end
function M.commit(helper,state)
    local patient,plan=state.patient,state.medicinePlan
    local context={};for key,value in pairs(state.medicineContext or {}) do context[key]=value end
    context.stage="commit";context.helper=helper
    local valid,reason,counters,before,current=M.validatePlan(helper,patient,plan,context)
    if not valid then return false,reason end
    local medical=SC.Medical
    if not medical or medical.treatmentHolder(patient)~=helper or not medical.inContact(helper,patient)
        or medical.playerSelfCareActive(patient) or not medical.electiveSafe(helper,patient,state.runtime,state.campVisit) then
        return false,"medical_context_changed"
    end
    if state.supervisorToken and SC.ActionSupervisor then
        for _,resource in ipairs(plan.resources) do
            if SC.ActionSupervisor.reserve(state.supervisorToken,resource,"medical_supply")~=true then return false,"reservation_lost" end
        end
    end
    local entry=plan.entry
    local saved={version=1,patientId=id(patient),helperId=id(helper),kind=plan.kind,itemId=entry.nativeId,itemType=entry.itemType,
        hours=current,attempted=true,effectVerified=false,debitVerified=false,quarantined=false,terminalQuarantine=false,
        usesBefore=entry.uses,effectBefore=before.effect,deltaBefore=before.delta,reductionBefore=before.reduction,powerBefore=before.power}
    -- Reserve the daily allowance before any irreversible native call. An
    -- uncertain attempt never refunds the allowance or receives a free retry.
    if plan.kind=="take_painkillers" then counters.painCount=counters.painCount+1;counters.lastPainHours=current
    else counters.lastAntibioticHours=current end
    local maximum={};for key,value in pairs(saved) do maximum[key]=value end
    maximum.effectAfter,maximum.deltaAfter,maximum.reductionAfter,maximum.powerAfter=5400,0.45,0,50
    maximum.usesAfter=entry.uses and entry.uses-1 or nil
    maximum.reason="medical_consumption_uncertain"
    if type(P().canWriteCare)~="function" or not P().canWriteCare(patient,"medicalMedicineRecovery",maximum,
        {medicalMedicineState=counters}) then return false,"medical_metadata_unavailable" end
    if P().writeCare(patient,"medicalMedicineState",counters)~=true or not saveReceipt(patient,saved) then
        return false,"medical_metadata_unavailable"
    end
    local live={saved=saved,entry=entry,patient=patient,kind=saved.kind,patientId=saved.patientId,helperId=saved.helperId}
    receipts[id(patient)]=live
    state.removalCommitted=true
    if plan.kind=="take_painkillers" then call(select(1,call(patient,"getBodyDamage")),"JustTookPill",entry.item)
    else call(patient,"Eat",entry.item,1,false) end
    local after=M.nativeState(patient,plan.kind)
    if after then
        saved.effectAfter,saved.deltaAfter,saved.reductionAfter,saved.powerAfter=after.effect,after.delta,after.reduction,after.power
        if plan.kind=="take_painkillers" then
            -- The timer is reset to 5400 and the pending dose increases by
            -- 0.45 sober or 0.15 while intoxicated, as native JustTookPill does.
            local delta=after.delta-before.delta
            saved.effectVerified=after.effect==5400 and (math.abs(delta-0.45)<0.00001 or math.abs(delta-0.15)<0.00001)
        else saved.effectVerified=after.power==50 end
    end
    local source=select(1,call(entry.item,"getContainer"))
    if plan.kind=="take_painkillers" then
        local uses=number(entry.item,"getCurrentUses");saved.usesAfter=uses
        saved.debitVerified=uses~=nil and uses==entry.uses-1
            and (uses==0 and source==nil or uses>0 and source==entry.source and U().containerContainsIdentity(entry.source,entry.item))
    else saved.debitVerified=source==nil and not U().containerContainsIdentity(entry.source,entry.item) end
    if not saved.effectVerified or not saved.debitVerified then
        saved.quarantined,saved.terminalQuarantine,saved.reason=true,true,"medical_consumption_uncertain"
        live.quarantined,live.terminalQuarantine,live.reason=true,true,saved.reason
    end
    local captured=saveReceipt(patient,saved)
    if not captured then
        saved.quarantined,saved.terminalQuarantine,saved.reason=true,true,"medical_consumption_uncertain"
        live.quarantined,live.terminalQuarantine,live.reason=true,true,saved.reason
        -- The published attempted receipt remains authoritative if an
        -- unexpected metadata change prevents recording native postconditions.
        -- Retain the live forensic proof until a later restore can quarantine
        -- that attempted receipt; never report an unqualified completion.
        captured=saveReceipt(patient,saved)
    end
    U().touchInventoryIndex(entry.source)
    if medical.invalidate then medical.invalidate(patient) end
    if captured then receipts[id(patient)]=nil end
    return true,saved.quarantined and saved.reason or plan.kind=="take_painkillers" and "painkillers_taken" or "antibiotics_taken"
end
function M.recover(_,state)
    local pending=M.pending(state.patient,state.medicineKind)
    if not pending then return true,"medicine_already_taken" end
    if pending.saved then
        pending.saved.quarantined,pending.saved.terminalQuarantine,pending.saved.reason=true,true,"medical_consumption_uncertain"
        saveReceipt(state.patient,pending.saved)
    end
    receipts[id(state.patient)]=nil
    return true,"medical_consumption_uncertain"
end
function M.handoff(state)
    if state and state.patient then
        local live=receipts[id(state.patient)]
        if live then
            live.saved.quarantined,live.saved.terminalQuarantine,live.saved.reason=true,true,"medical_consumption_uncertain"
            saveReceipt(state.patient,live.saved);receipts[id(state.patient)]=nil
        end
    end
    return true,"medical_recovery_handed_off"
end
function M.releaseActor(actor)
    for patientId,live in pairs(receipts) do
        if patientId==id(actor) or live.helperId==id(actor) then
            live.saved.quarantined,live.saved.terminalQuarantine,live.saved.reason=true,true,"medical_consumption_uncertain"
            if live.patient then saveReceipt(live.patient,live.saved) end
            receipts[patientId]=nil
        end
    end
end
function M.reset() receipts={} end
function M.retireVisit(patientId,careKey,patient)
    local key=tostring(patientId)
    local live=receipts[key]
    if live and careKey==key..":whole:"..live.kind then receipts[key]=nil end
    if patient and id(patient)==key then
        local saved=P().readCare(patient,"medicalMedicineRecovery")
        if type(saved)=="table" and kinds[saved.kind] and careKey==key..":whole:"..saved.kind then
            P().writeCare(patient,"medicalMedicineRecovery",nil)
        end
    end
end
return M
