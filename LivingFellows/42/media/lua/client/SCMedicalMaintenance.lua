-- SPDX-License-Identifier: MIT
-- Attachment removal belongs to the same patient claim as dressing care.
LivingFellows = LivingFellows or {}
local SC = LivingFellows
SC.MedicalMaintenance = SC.MedicalMaintenance or {}
local Care = SC.MedicalMaintenance
local obligations = {}
local recent = {}
local function patientKey(patient)
    return SC.MedicalProcedures and SC.MedicalProcedures.actorId(patient)
        or tostring(SC.GameplayUtil.idOf(patient) or patient)
end
local function confirmedDead(patient)
    if SC.GameplayUtil.isDead(patient) then return true end
    local body,okay=SC.GameplayUtil.call(patient,"getBodyDamage")
    local health,known=SC.GameplayUtil.call(body,"getHealth")
    return okay and known and type(health)=="number" and health==health and health<=0
end
local dirtyTypes = {
    ["Base.Bandage"]="Base.BandageDirty", ["Base.AlcoholBandage"]="Base.BandageDirty",
    ["Base.RippedSheets"]="Base.RippedSheetsDirty", ["Base.AlcoholRippedSheets"]="Base.RippedSheetsDirty",
    ["Base.DenimStrips"]="Base.DenimStripsDirty", ["Base.LeatherStrips"]="Base.LeatherStripsDirty",
}
local function call(value, method, ...)
    return SC.GameplayUtil.call(value, method, ...)
end
local function number(value, method)
    return tonumber((call(value, method))) or 0
end
local function verifiedNumber(value, method)
    local result,okay=call(value,method)
    if okay and type(result)=="number" and result==result
        and result>-math.huge and result<math.huge then return result end
    return nil
end
local function flag(value, method)
    return (call(value, method)) == true
end
local function sync(part, mask)
    if type(syncBodyPart)=="function" then pcall(syncBodyPart,part,mask) end
end
local allowedKinds={remove_bullet=true,remove_glass=true,clean_burn=true,disinfect_wound=true,stitch_wound=true,
    remove_stitches=true,remove_splint=true}
local function knownIndex(index)
    return type(index)=="number" and index>=0 and index<=31 and index==math.floor(index)
end
local function receipt(pending)
    if not pending then return nil end
    local out={version=1,patientId=pending.patientId,index=pending.index,kind=pending.kind,
        redress=pending.redress==true,returned=pending.returned==true,ownerId=pending.ownerId,
        helperId=pending.helperId,quarantined=pending.quarantined==true,
        terminalQuarantine=pending.terminalQuarantine==true,quarantineReason=pending.quarantineReason,returns={}}
    for i,entry in ipairs(pending.returns or {}) do
        if i<=2 then out.returns[i]={kind=entry.kind,delivered=entry.delivered==true,
            quarantined=entry.quarantined==true,outputId=entry.outputId} end
    end
    local data=pending.procedure
    if data then
        local entry=data.consumable
        out.procedure={kind=data.kind,ownerId=data.ownerId,debitDone=data.debitDone==true,
            debitAttempted=data.debitAttempted==true,quarantined=data.quarantined==true,
            painVerified=data.painVerified==true,xpRequested=data.xpRequested,nativeOutputId=data.nativeOutputId,
            consumableKind=entry and entry.kind,consumableId=entry and (entry.nativeId or verifiedNumber(entry.item,"getID")),
            amount=entry and entry.amount,uses=entry and entry.uses,power=entry and entry.power,outputType=entry and entry.outputType}
    end
    return out
end
function Care.preflightProcedure(helper,state,wound)
    local P=SC.MedicalProcedures
    local plan=state.procedurePlan
    if not P or not plan or not wound or not state.patient then return false end
    local pending={patientId=patientKey(state.patient),index=wound.index,kind=plan.kind,
        redress=true,ownerId=patientKey(helper),helperId=patientKey(helper),returns={{kind="Base.Bandage",outputId="2147483647"}},
        procedure={kind=plan.kind,ownerId=patientKey(helper),consumable=plan.consumable,
            debitDone=false,debitAttempted=true,painVerified=true,xpRequested=20,nativeOutputId="2147483647"}}
    local extra
    if plan.kind=="disinfect_wound" then
        if P.firstDisinfectHours(state.patient,wound.index)==false then return false end
        extra={medicalDisinfectHours={},medicalInfectionDisinfectHours={}}
        for _,field in ipairs({"medicalDisinfectHours","medicalInfectionDisinfectHours"}) do
            local old=P.readCare(state.patient,field)
            if old~=nil and type(old)~="table" then return false end
            for key,value in pairs(old or {}) do extra[field][key]=value end
            extra[field][tostring(wound.index)]=P.worldHours()
        end
    end
    return P.canWriteCare(state.patient,"medicalRecovery",receipt(pending),extra)
end
function Care.save(patient)
    if SC.MedicalProcedures then
        return SC.MedicalProcedures.writeCare(patient,"medicalRecovery",receipt(obligations[patientKey(patient)]))
    end
end
local function restore(patient)
    local P=SC.MedicalProcedures
    local saved=P and P.readCare(patient,"medicalRecovery")
    if saved==nil then return nil end
    local id=patientKey(patient)
    local valid=type(saved)=="table" and saved.version==1 and saved.patientId==id
        and allowedKinds[saved.kind] and knownIndex(saved.index) and type(saved.returns)=="table"
        and type(saved.redress)=="boolean" and type(saved.returned)=="boolean"
        and type(saved.quarantined)=="boolean" and type(saved.terminalQuarantine)=="boolean"
    if valid and P.handles(saved.kind) then
        local data=saved.procedure
        valid=type(data)=="table" and data.kind==saved.kind and type(data.painVerified)=="boolean"
            and type(data.debitDone)=="boolean" and type(data.debitAttempted)=="boolean"
    end
    local pending={patientId=id,index=type(saved)=="table" and knownIndex(saved.index) and saved.index or nil,
        kind=type(saved)=="table" and allowedKinds[saved.kind] and saved.kind or nil,
        returns={},redress=valid and saved.redress==true,returned=valid and saved.returned==true,
        quarantined=not valid or saved.quarantined==true,terminalQuarantine=not valid or saved.terminalQuarantine==true,
        quarantineReason=valid and saved.quarantineReason or "medical_recovery_unreadable"}
    pending.wound={index=pending.index,seriousAfterProcedure=true}
    if valid then
        local count=0
        for i,entry in pairs(saved.returns) do
            count=count+1
            if count>2 or (i~=1 and i~=2) or type(entry)~="table" or type(entry.kind)~="string"
                or #entry.kind==0 or #entry.kind>256 or type(entry.delivered)~="boolean" or type(entry.quarantined)~="boolean" then
                pending.quarantined,pending.terminalQuarantine,pending.quarantineReason=true,true,"medical_recovery_unreadable";break
            end
            pending.returns[i]={kind=entry.kind,delivered=entry.delivered==true,
                quarantined=entry.quarantined==true,outputId=entry.outputId}
        end
        local data=saved.procedure
        if type(data)=="table" then
            pending.procedure={kind=pending.kind,ownerId=data.ownerId,debitDone=data.debitDone==true,
                debitAttempted=data.debitAttempted==true,quarantined=data.quarantined==true,
                painVerified=data.painVerified==true,xpRequested=data.xpRequested,nativeOutputId=data.nativeOutputId}
            if data.consumableKind~=nil then
                pending.procedure.consumable={kind=data.consumableKind,nativeId=data.consumableId,
                    amount=data.amount,uses=data.uses,power=data.power,outputType=data.outputType,ancestors={}}
                if not pending.procedure.debitDone then
                    pending.procedure.quarantined,pending.quarantined=true,true
                    pending.quarantineReason="medical_consumption_uncertain"
                end
            end
        end
    end
    -- Exact native handles never cross a save boundary. A published effect is
    -- proof of commitment, never permission to replay surgery or unknown debit.
    obligations[id]=pending
    if not pending.terminalQuarantine then Care.save(patient) end
    return pending
end
function Care.injuryFree(part)
    for _,method in ipairs({"getBleedingTime","getBiteTime","getScratchTime","getCutTime",
        "getDeepWoundTime","getStitchTime","getBurnTime","getFractureTime"}) do
        local time=verifiedNumber(part,method)
        if time==nil or time>0 then return false end
    end
    for _,method in ipairs({"bleeding","bitten","scratched","isCut","deepWounded",
        "stitched","isInfectedWound","haveBullet","haveGlass"}) do
        local value,okay=call(part,method)
        if not okay or type(value)~="boolean" or value then return false end
    end
    return true
end
local function knownFalse(part,method)
    local value,known=call(part,method)
    return known and value==false
end
local function resolved(part,kind)
    if not part then return false end
    if kind=="remove_bullet" then return knownFalse(part,"haveBullet") end
    if kind=="remove_glass" then return knownFalse(part,"haveGlass") end
    if kind=="clean_burn" then return verifiedNumber(part,"getBurnTime")==0 end
    if kind=="disinfect_wound" then return knownFalse(part,"isInfectedWound") end
    if kind=="remove_splint" then
        -- These receipts are published after a verified removal. A currently
        -- attached, mature splint or stitch can be removed as a new operation.
        return knownFalse(part,"isSplint") and verifiedNumber(part,"getSplintFactor")==0
            or (flag(part,"isSplint") or (verifiedNumber(part,"getSplintFactor") or 0)>0)
                and verifiedNumber(part,"getFractureTime")==0
    end
    -- A covered wound can hide native flags. For stitching, include the
    -- timers and the existing attachment until this wound episode has ended.
    if kind=="remove_stitches" then
        local time=verifiedNumber(part,"getStitchTime")
        return time and (time>=40 or time==0 and knownFalse(part,"stitched"))
    end
    if kind=="stitch_wound" then
        return knownFalse(part,"stitched") and verifiedNumber(part,"getStitchTime")==0
            and knownFalse(part,"deepWounded") and verifiedNumber(part,"getDeepWoundTime")==0
    end
    return false
end
local function slot(index,kind) return tostring(index)..":"..kind end
local function firstKey(rows)
    if type(rows)=="table" then for key in pairs(rows) do return key end end
end
-- Finished uncertainty has no work owner or replayable inventory handles.
-- The compact set has at most one entry per native part and operation. Move
-- the old active receipt and its holds in one durable care-table write.
local function updateHolds(patient,terminal)
    local P=SC.MedicalProcedures
    local saved=P and P.readCare(patient,"medicalProcedureQuarantines")
    if not terminal and (saved==nil or type(saved)=="table" and not firstKey(saved)) then return nil end
    local body=select(1,call(patient,"getBodyDamage"))
    local parts=select(1,call(body,"getBodyParts"))
    local size=SC.GameplayUtil.listSize(parts)
    if size<1 or size>32 then return saved end
    local holds,changed,unknown={},false,saved~=nil and type(saved)~="table"
    for key,enabled in pairs(type(saved)=="table" and saved or {}) do
        local index,kind
        if type(key)=="string" then index,kind=key:match("^(%d+):([%a_]+)$") end
        index=tonumber(index)
        if not knownIndex(index) or not allowedKinds[kind] or key~=slot(index,kind) or enabled~=true then unknown=true;break end
        if resolved(SC.GameplayUtil.listGet(parts,index),kind) then changed=true
        else holds[key]=true end
    end
    if terminal or unknown then
        -- An old malformed receipt may only identify the part, the action or
        -- neither. Hold the plausible unresolved actions until native evidence
        -- rules them out; never turn that ambiguous record into an operation.
        for index=0,size-1 do
            if unknown or terminal.index==nil or terminal.index==index then
                local part=SC.GameplayUtil.listGet(parts,index)
                if not part then return saved end
                for kind in pairs(allowedKinds) do
                    if (unknown or not terminal.kind or terminal.kind==kind) and not resolved(part,kind) then
                        holds[slot(index,kind)]=true
                    end
                end
            end
        end
    end
    if terminal then
        if not P.writeCare(patient,"medicalRecovery",nil,{medicalProcedureQuarantines=holds}) then return saved end
        obligations[patientKey(patient)]=nil
    elseif changed or unknown then
        if not P.writeCare(patient,"medicalProcedureQuarantines",firstKey(holds) and holds or nil) then return saved end
    end
    return holds
end
function Care.holds(patient) return updateHolds(patient) end
function Care.held(holds,index,kind)
    return holds~=nil and (type(holds)~="table" or holds[slot(index,kind)]==true)
end
function Care.pending(patient)
    local pending=obligations[patientKey(patient)] or restore(patient)
    if pending and pending.terminalQuarantine then
        updateHolds(patient,pending)
        return obligations[patientKey(patient)]
    end
    if pending and not pending.terminalQuarantine and not pending.part and SC.GameplayUtil.isValidActor(patient) then
        local body=select(1,call(patient,"getBodyDamage"))
        local parts=select(1,call(body,"getBodyParts"))
        SC.GameplayUtil.each(parts,32,function(part,index)
            if index==pending.index then pending.part=part;if pending.wound then pending.wound.part=part end end
        end)
        if pending.part then pending.patientUnavailable=false end
    end
    if pending and pending.redress and (confirmedDead(patient) or flag(pending.part,"bandaged") or Care.injuryFree(pending.part)) then
        pending.redress=false
        Care.save(patient)
    end
    return pending
end
function Care.choose(patient, assessment)
    local pending=Care.pending(patient)
    if pending then
        local kind=pending.redress and "redress" or pending.kind
        for _,wound in ipairs(assessment.wounds or {}) do
            if wound.index==pending.index then return wound,kind,not pending.redress end
        end
        return pending.wound,kind,not pending.redress
    end
    local holds=Care.holds(patient)
    for _,wound in ipairs(assessment.wounds or {}) do
        if wound.stitchReady and not Care.held(holds,wound.index,"remove_stitches") then return wound,"remove_stitches" end
    end
    for _,wound in ipairs(assessment.wounds or {}) do
        if wound.boneHealed and not Care.held(holds,wound.index,"remove_splint") then return wound,"remove_splint" end
    end
end
function Care.supplyAllowed(helper,item,source)
    if item==nil or source==nil then return false end
    if SC.PersonalItems and type(SC.PersonalItems.isProtected)=="function"
        and SC.PersonalItems.isProtected(item,helper,"medical_consume") then return false end
    if not SC.GameplayUtil.containerContainsIdentity(source,item) then return false end
    for _,candidate in ipairs(SC.GameplayUtil.inventoryItemsDeep(SC.GameplayUtil.inventory(helper),400,16)) do
        if candidate==item then return true end
    end
    return false
end
function Care.preferredFresh(helper,pending)
    if pending and Care.supplyAllowed(helper,pending.fresh,pending.source) then
        return pending.fresh,pending.source
    end
end
local function inventorySnapshot(inventory)
    local items,okay=call(inventory,"getItems")
    if not okay or items==nil then return nil end
    local size,known=call(items,"size")
    if not known and type(items)=="table" then size=#items end
    if type(size)~="number" or size<0 or size>1024 then return nil end
    local result={}
    SC.GameplayUtil.each(items,1024,function(item)
        local id=verifiedNumber(item,"getID")
        local key=id and id>0 and tostring(id) or tostring(item)
        result[key]={item=item,kind=SC.GameplayUtil.itemType(item)}
    end)
    return result
end
local function deliverReturns(helper,pending)
    local inventory=SC.GameplayUtil.inventory(helper)
    if not inventory then return false,"medical_redress_pending" end
    for _,entry in ipairs(pending.returns or {}) do
        if entry.quarantined then return false,"medical_return_uncertain" end
        if not entry.delivered then
            local before=inventorySnapshot(inventory)
            if not before then return false,"medical_redress_pending" end
            local created=select(1,call(inventory,"AddItem",entry.kind))
            local after=inventorySnapshot(inventory)
            if not after then entry.quarantined=true;return false,"medical_return_uncertain" end
            local found,count=nil,0
            for id,row in pairs(after) do
                if row.kind==entry.kind and not before[id] then found,count=id,count+1 end
            end
            if count==1 then
                entry.delivered,entry.outputId=true,found
                SC.GameplayUtil.touchInventoryIndex(inventory)
            elseif count>1 or created~=nil then
                entry.quarantined=true;return false,"medical_return_uncertain"
            else return false,"medical_redress_pending" end
        end
    end
    pending.returned=true
    return true
end

function Care.handoff(state)
    local pending=state and obligations[patientKey(state.patient)]
    if pending then
        pending.helper=nil
        local data=pending.procedure
        pending.ownerId=data and data.consumable and not data.debitDone and not data.quarantined and data.ownerId or nil
        Care.save(state.patient)
    end
    return true,"medical_recovery_handed_off"
end
-- Only the terminal camp visit that pinned this exact obligation can retire it.
-- Other treatment paths may still own a verifiable material return.
function Care.retireVisit(id,key,patient)
    local pending=obligations[id] or (patient and restore(patient))
    if pending and key==id..":"..tostring(pending.index)..":"..tostring(pending.kind) then
        obligations[id]=nil
        if patient then SC.MedicalProcedures.writeCare(patient,"medicalRecovery",nil) end
    end
end
function Care.forget(patient)
    local pending=obligations[patientKey(patient)]
    if not pending then return end
    if pending.procedure or not pending.returned or pending.redress then
        if confirmedDead(patient) then pending.redress=false end
        pending.part=nil
        if pending.wound then pending.wound.part=nil end
        pending.patientUnavailable=true
        Care.save(patient)
        return
    end
    obligations[patientKey(patient)]=nil
    Care.save(patient)
end
function Care.releaseActor(actor)
    local id=patientKey(actor)
    Care.forget(actor)
    for _,pending in pairs(obligations) do
        local data=pending.procedure
        if pending.helperId==id then pending.helper,pending.fresh,pending.source=nil,nil,nil end
        if data and data.ownerId==id and data.consumable and not data.debitDone then
            data.quarantined=true;pending.ownerId=nil
            local item=data.consumable.item
            data.consumable.nativeId=item and number(item,"getID") or data.consumable.nativeId
            data.consumable.item,data.consumable.source,data.consumable.fluid=nil,nil,nil
            data.consumable.ancestors={}
            pending.fresh,pending.source=nil,nil
        end
        local record=SC.Registry and SC.Registry.byId and SC.Registry.byId(pending.patientId)
        if record and record.actor then Care.save(record.actor) end
    end
end
function Care.reset()
    obligations={};recent={}
end
function Care.pendingView(patient)
    local pending=Care.pending(patient)
    if not pending then
        local holds=Care.holds(patient)
        local key=firstKey(holds)
        if type(key)~="string" then return nil end
        local index,kind=key:match("^(%d+):([%a_]+)$")
        if not index or not allowedKinds[kind] then return nil end
        return {kind=kind,key=SC.MedicalProcedures.key(patient,tonumber(index),kind),woundIndex=tonumber(index),
            committed=true,pending=true,quarantined=true,terminalQuarantine=true,active=false}
    end
    if not pending.kind or pending.index==nil then return nil end
    return {kind=pending.kind,key=SC.MedicalProcedures and SC.MedicalProcedures.key(patient,pending.index,pending.kind)
        or patientKey(patient)..":"..pending.index..":"..pending.kind,
        woundIndex=pending.index,owner=pending.ownerId,committed=true,pending=true,returnOnly=not pending.redress,
        quarantined=pending.quarantined==true or pending.procedure and pending.procedure.quarantined==true,
        terminalQuarantine=pending.terminalQuarantine==true,active=pending.terminalQuarantine~=true,
        patientUnavailable=pending.patientUnavailable==true}
end
function Care.cancelOwned(helper,patient,key)
    local pending=Care.pending(patient)
    local view=Care.pendingView(patient)
    if not pending or not view or view.key~=key then return true,"no_active_treatment" end
    if pending.ownerId and pending.ownerId~=patientKey(helper) then return false,"medical_pending_owned" end
    local data=pending.procedure
    if data and data.consumable and not data.debitDone and not data.quarantined then return false,"medical_pending_owned" end
    pending.ownerId,pending.helper=nil,nil
    Care.save(patient)
    return true,"medical_recovery_handed_off"
end
function Care.uncover(helper,state,wound)
    local plan=state.procedurePlan
    if not plan or not SC.MedicalProcedures.validatePlan(helper,plan) then return nil,"no_clean_bandage" end
    if not Care.preflightProcedure(helper,state,wound) then return nil,"medical_recovery_unreadable" end
    local count=0;for _ in pairs(obligations) do count=count+1 end
    if count>=128 then return nil,"medical_recovery_capacity" end
    local part=wound.part
    local previous={bandaged=flag(part,"bandaged"),life=verifiedNumber(part,"getBandageLife"),
        alcoholic=flag(part,"isAlcoholicBandage"),kind=select(1,call(part,"getBandageType"))}
    if previous.bandaged then
        if previous.life==nil then return nil,"medical_procedure_unverified" end
        call(part,"setBandaged",false,0,false,nil)
        if flag(part,"bandaged") then return nil,"medical_procedure_unverified" end
    end
    return previous
end
function Care.restoreCover(part,previous)
    if previous and previous.bandaged then call(part,"setBandaged",true,previous.life,previous.alcoholic,previous.kind) end
end
function Care.publishProcedure(helper,state,wound,previous,data)
    local returns={}
    if previous.bandaged and type(previous.kind)=="string" and previous.kind~="" then
        returns[1]={kind=previous.life<=0 and (dirtyTypes[previous.kind] or previous.kind) or previous.kind}
    end
    local pending={part=wound.part,index=wound.index,wound=wound,patientId=patientKey(state.patient),
        kind=data.kind,redress=true,returns=returns,procedure=data,fresh=state.bandage,source=state.inventory,
        helperId=patientKey(helper),ownerId=data.consumable and patientKey(helper) or nil}
    obligations[patientKey(state.patient)]=pending
    if Care.save(state.patient)==false then
        pending.quarantined=true;pending.quarantineReason="medical_recovery_unreadable"
        data.quarantined=true
    end
    state.removalCommitted=true
    return pending
end
function Care.recent() return recent end

local function commit(helper,state,wound,applyDressing)
    local part=wound.part
    local pending=Care.pending(state.patient)
    if pending and pending.terminalQuarantine then return false,pending.quarantineReason or "medical_consumption_uncertain" end
    if not pending and Care.held(Care.holds(state.patient),wound.index,state.maintenanceKind) then
        return false,"medical_consumption_uncertain"
    end
    if not pending and SC.MedicalProcedures and SC.MedicalProcedures.handles(state.maintenanceKind) then
        local reason
        pending,reason=SC.MedicalProcedures.start(helper,state,wound)
        if not pending then return false,reason end
    end
    if not pending then
        if state.maintenanceKind=="redress" then return false,"medical_maintenance_unverified" end
        local count=0;for _ in pairs(obligations) do count=count+1 end
        if count>=128 then return false,"medical_recovery_capacity" end
        local returns={}
        if state.maintenanceKind=="remove_stitches" then
            local stitchTime=verifiedNumber(part,"getStitchTime")
            if stitchTime==nil or stitchTime<40 then return false,"stitches_not_ready" end
            -- The exact fresh supply is already reserved by the shared owner.
            local covered=flag(part,"bandaged")
            if covered and state.bandage==nil then return false,"no_clean_dressing_for_stitches" end
            if covered and not Care.supplyAllowed(helper,state.bandage,state.inventory) then
                return false,"no_clean_dressing_for_stitches"
            end
            if covered and state.supervisorToken and SC.ActionSupervisor then
                local reserved=SC.ActionSupervisor.reserve(state.supervisorToken,state.bandage,"medical_supply")
                if reserved~=true then return false,"no_clean_dressing_for_stitches" end
            end
            local oldType=(call(part,"getBandageType"))
            local oldLife=number(part,"getBandageLife")
            local oldAlcoholic=flag(part,"isAlcoholicBandage")
            if covered then
                local _,okay=call(part,"setBandaged",false,0,false,nil)
                if flag(part,"bandaged") then return false,"medical_maintenance_unverified" end
            end
            local _,okay=call(part,"setStitched",false)
            local remaining=verifiedNumber(part,"getStitchTime")
            if remaining==nil or remaining>0 or flag(part,"stitched") then
                if covered then call(part,"setBandaged",true,oldLife,oldAlcoholic,oldType) end
                return false,"medical_maintenance_unverified"
            end
            if covered and type(oldType)=="string" and oldType~="" then
                returns[#returns+1]={kind=oldLife<=0 and (dirtyTypes[oldType] or oldType) or oldType}
            end
            pending={part=part,index=wound.index,wound=wound,redress=covered or state.bandage~=nil,returns=returns,
                kind="remove_stitches",patientId=patientKey(state.patient),helperId=patientKey(helper),fresh=state.bandage,source=state.inventory}
            -- Publish proof immediately after the irreversible native removal.
            obligations[patientKey(state.patient)]=pending
            Care.save(state.patient)
            state.removalCommitted=true
            local doctor=math.max(0,SC.GameplayUtil.perkLevel(helper,"Doctor",0))
            call(part,"setAdditionalPain",number(part,"getAdditionalPain")+math.max(0,5-doctor))
            if flag(part,"isGetStitchXp") and type(addXp)=="function" and Perks then
                pcall(addXp,helper,Perks.Doctor,15)
            end
            if type(ZombRand)=="function" and ZombRand(5+doctor*2.5)==0 then call(part,"setInfectedWound",true) end
            sync(part,0x00570188)
        elseif state.maintenanceKind=="remove_splint" then
            local fractureTime=verifiedNumber(part,"getFractureTime")
            if fractureTime==nil or fractureTime~=0 then return false,"fracture_not_healed" end
            if not flag(part,"isSplint") and number(part,"getSplintFactor")<=0 then
                return false,"medical_maintenance_unverified"
            end
            local kind=(call(part,"getSplintItem"))
            local _,okay=call(part,"setSplint",false,0)
            if flag(part,"isSplint") or number(part,"getSplintFactor")>0 then
                return false,"medical_maintenance_unverified"
            end
            if type(kind)=="string" and kind~="" then
                returns[#returns+1]={kind=kind}
                if kind~="Base.Splint" then returns[#returns+1]={kind="Base.RippedSheets"} end
            end
            pending={part=part,index=wound.index,wound=wound,returns=returns,kind="remove_splint",patientId=patientKey(state.patient),helperId=patientKey(helper)}
            obligations[patientKey(state.patient)]=pending
            Care.save(state.patient)
            state.removalCommitted=true
            sync(part,0x430000000)
        else return false,"medical_maintenance_unverified" end
    end
    if pending.procedure then
        local settled,reason=SC.MedicalProcedures.settle(helper,pending)
        if not settled and reason~="medical_consumption_uncertain" then return true,"medical_redress_pending" end
        if reason=="medical_consumption_uncertain" then pending.quarantined=true;pending.ownerId=nil end
        if settled then pending.ownerId=nil end
        if pending.procedure.painVerified==false then
            pending.quarantined,pending.quarantineReason=true,"medical_procedure_unverified"
        end
    end
    local returned,returnReason=deliverReturns(helper,pending)
    if not returned and returnReason=="medical_return_uncertain" then pending.quarantined=true;pending.quarantineReason=returnReason
    elseif not returned then return true,"medical_redress_pending" end
    if pending.redress then
        local dressed=applyDressing()
        if dressed~=true then return true,"medical_redress_pending" end
        pending.redress=false
    end
    if pending.quarantined then
        pending.terminalQuarantine=true
        pending.ownerId,pending.fresh,pending.source,pending.part,pending.helper=nil,nil,nil,nil,nil
        if pending.wound then pending.wound.part=nil end
        if pending.procedure and pending.procedure.consumable then
            local entry=pending.procedure.consumable
            entry.nativeId=entry.item and number(entry.item,"getID") or entry.nativeId
            entry.item,entry.source,entry.fluid=nil,nil,nil;entry.ancestors={}
        end
    else obligations[patientKey(state.patient)]=nil end
    local result=pending.quarantined and (pending.quarantineReason or "medical_consumption_uncertain")
        or SC.MedicalProcedures and SC.MedicalProcedures.result(pending.kind)
        or (pending.kind=="remove_splint" and "splint_removed" or "stitches_removed")
    recent[#recent+1]={patientId=pending.patientId or patientKey(state.patient),kind=pending.kind,
        result=result,consumptionVerified=not pending.procedure or not pending.procedure.consumable or pending.procedure.debitDone==true}
    if #recent>16 then table.remove(recent,1) end
    return true,result
end
function Care.commit(helper,state,wound,applyDressing)
    local okay,reason=commit(helper,state,wound,applyDressing)
    Care.save(state.patient)
    return okay,reason
end
