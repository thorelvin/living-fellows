-- SPDX-License-Identifier: MIT
-- Selection and native effects for elective care. Recovery belongs to the
-- shared MedicalMaintenance receipt; this module keeps no competing work owner.
LivingFellows=LivingFellows or {}
local SC=LivingFellows
SC.MedicalProcedures=SC.MedicalProcedures or {}
local P=SC.MedicalProcedures
-- Registered companions keep this bounded map in the existing saved care
-- state. The local fallback is only for providers without a persistent record.
local disinfectTimes={}
local kinds={remove_bullet=true,remove_glass=true,clean_burn=true,disinfect_wound=true,stitch_wound=true}
local visits={remove_bullet=true,remove_glass=true,clean_burn=true,disinfect_wound=true,
    stitch_wound=true,replace_bandage=true,remove_stitches=true,remove_splint=true}
local ranks={bandage=1,remove_bullet=2,remove_glass=3,apply_splint=4,clean_burn=5,
    disinfect_wound=6,stitch_wound=6.5,replace_bandage=8,remove_stitches=9,remove_splint=10}
local function U() return SC.GameplayUtil end
local function call(value,name,...) return U().call(value,name,...) end
local function number(value,name)
    local result,okay=call(value,name)
    if okay and type(result)=="number" and result==result and result>-math.huge and result<math.huge then return result end
end
local function flag(value,name)
    local result,okay=call(value,name)
    if okay and type(result)=="boolean" then return result end
end
function P.actorId(actor) return tostring(U().idOf(actor) or actor) end
function P.key(patient,index,kind) return P.actorId(patient)..":"..tostring(index)..":"..kind end
function P.handles(kind) return kinds[kind]==true end
function P.worldHours()
    if type(getGameTime)~="function" then return nil end
    local okay,time=pcall(getGameTime)
    return okay and number(time,"getWorldAgeHours") or nil
end
function P.careStore(patient,create)
    local id=U().idOf(patient)
    local record=id and SC.Registry and SC.Registry.byId and SC.Registry.byId(id)
    local care
    if record and record.actor==patient then
        local state=SC.Commands and SC.Commands.peek and SC.Commands.peek(patient)
        if state then
            if create and type(state.care)~="table" then state.care={} end
            care=state.care
            if type(care)=="table" then return care end
        end
        if create then
            record.state=record.state or {};record.state.personality=record.state.personality or {}
            record.state.personality.care=record.state.personality.care or {}
        end
        care=record.state and record.state.personality and record.state.personality.care
        if type(care)~="table" then return nil end
        return care
    end
    if type(getSpecificPlayer)=="function" and getSpecificPlayer(0)==patient then
        local data=select(1,call(patient,"getModData"))
        if type(data)~="table" then return false end
        if create and data.SC_MedicalCare==nil then data.SC_MedicalCare={medicalDisinfectHours=data.SC_MedicalDisinfectHours} end
        return data.SC_MedicalCare
    end
    if create then disinfectTimes[P.actorId(patient)]=disinfectTimes[P.actorId(patient)] or {} end
    return disinfectTimes[P.actorId(patient)]
end
function P.readCare(patient,field)
    local care=P.careStore(patient,false)
    if care~=nil and type(care)~="table" then return false end
    return care and care[field]
end
function P.canWriteCare(patient,field,value,extra)
    local care=P.careStore(patient,false)
    if care~=nil and type(care)~="table" then return false end
    if not SC.StableValue or type(SC.StableValue.copyStrict)~="function" then return false end
    local candidate={}
    for key,old in pairs(care or {}) do candidate[key]=old end
    if type(extra)=="table" then for key,new in pairs(extra) do candidate[key]=new end end
    candidate[field]=value
    local copied=SC.StableValue.copyStrict(candidate,{maxDepth=4,maxEntries=512})
    return copied~=nil,copied
end
function P.writeCare(patient,field,value,extra)
    local valid,copied=P.canWriteCare(patient,field,value,extra)
    if not valid then return false end
    local care=P.careStore(patient,true)
    if type(care)~="table" then return false end
    for key in pairs(care) do care[key]=nil end
    for key,new in pairs(copied) do care[key]=new end
    local id=U().idOf(patient)
    local record=id and SC.Registry and SC.Registry.byId and SC.Registry.byId(id)
    if record and record.actor==patient then
        record.state=record.state or {};record.state.personality=record.state.personality or {}
        record.state.personality.care=record.state.personality.care or {}
        record.state.personality.care=care
    end
    return true
end
local function timeStore(patient,create)
    local store=P.readCare(patient,"medicalDisinfectHours")
    if create and (store==nil or type(store)=="table") then
        local copied={};for key,value in pairs(store or {}) do copied[key]=value end;store=copied
    end
    return store
end
function P.firstDisinfectHours(patient,index)
    local store=P.readCare(patient,"medicalInfectionDisinfectHours")
    if store==nil then return nil end
    if type(store)~="table" then return false end
    local current=P.worldHours()
    local count=0
    for key,value in pairs(store) do
        count=count+1
        local slot=tonumber(key)
        if count>32 or not slot or slot<0 or slot>31 or slot~=math.floor(slot)
            or type(value)~="number" or value~=value or value<0 or value==math.huge
            or not current or value>current then return false end
    end
    return store[tostring(index)] or store[index]
end
function P.refreshInfectionEpisodes(patient,assessment)
    local store=P.readCare(patient,"medicalInfectionDisinfectHours")
    if type(store)~="table" or P.firstDisinfectHours(patient,0)==false then return end
    local infected={}
    for _,wound in ipairs(assessment.wounds or {}) do if wound.infected then infected[tostring(wound.index)]=true end end
    local changed,copied=false,{}
    for index,value in pairs(store) do
        if infected[tostring(index)] then copied[index]=value else changed=true end
    end
    if changed then P.writeCare(patient,"medicalInfectionDisinfectHours",copied) end
end
function P.disinfectReady(patient,index,alcohol)
    if type(alcohol)~="number" or alcohol~=alcohol or alcohol>0 or alcohol<0 then return false end
    local current=P.worldHours()
    if current==nil or current<0 then return false end
    local store=timeStore(patient,false)
    if store~=nil and type(store)~="table" then return false end
    local count=0
    for key,value in pairs(store or {}) do
        local part=tonumber(key)
        if not part or part<0 or part>31 or part~=math.floor(part) or type(value)~="number"
            or value~=value or value<0 or value==math.huge or value>current then return false end
        count=count+1
    end
    if count>32 then return false end
    local last=store and store[tostring(index)]
    if last==nil and store then last=store[index] end
    if last==nil then return true end
    if type(last)~="number" or last~=last or last<0 or last==math.huge then return false end
    local minimum=tonumber(U().config("medicalDisinfectMinimumHours")) or 2
    if minimum~=minimum or minimum==math.huge or minimum==-math.huge then minimum=2 end
    return current~=nil and current>=last and current-last>=math.max(2,minimum)
end
local function descriptor(patient,wound,kind,rank,pending)
    return {kind=kind,patient=patient,woundIndex=wound.index,key=P.key(patient,wound.index,kind),rank=rank or ranks[kind],
        visitEligible=visits[kind]==true,pending=pending==true,wound=wound}
end
function P.need(patient,assessment)
    local wounds=assessment.wounds or {}
    -- Fresh undressed bleeding always outranks a new elective procedure.
    for _,w in ipairs(wounds) do
        if w.bleeding and not w.bandaged then return descriptor(patient,w,"bandage",1) end
    end
    local pending=SC.MedicalMaintenance and SC.MedicalMaintenance.pending(patient)
    if pending and not pending.terminalQuarantine then
        local wound=pending.wound
        for _,w in ipairs(wounds) do if w.index==pending.index then wound=w break end end
        if wound then return descriptor(patient,wound,pending.kind,0,true) end
    end
    local Care=SC.MedicalMaintenance
    local holds=Care and Care.holds(patient)
    for _,kind in ipairs({"remove_bullet","remove_glass","apply_splint","clean_burn","disinfect_wound","stitch_wound",
        "bandage","replace_bandage","remove_stitches","remove_splint"}) do
        for _,w in ipairs(wounds) do
            local allowed=(not pending or not pending.terminalQuarantine or kind=="apply_splint" or kind=="bandage" or kind=="replace_bandage")
                and (not Care or not Care.held(holds,w.index,kind))
            local needed=allowed and (kind=="remove_bullet" and w.bullet
                or kind=="remove_glass" and w.glass
                or kind=="apply_splint" and w.needsSplint
                or kind=="clean_burn" and w.burned and w.needBurnWash
                or kind=="disinfect_wound" and w.infected and P.disinfectReady(patient,w.index,w.alcoholLevel)
                or kind=="stitch_wound" and w.deepWound and not w.glass
                or kind=="bandage" and w.openWound
                or kind=="replace_bandage" and w.dirtyBandage and w.active
                or kind=="remove_stitches" and w.stitchReady
                or kind=="remove_splint" and w.boneHealed)
            if needed then return descriptor(patient,w,kind,kind=="bandage" and 7 or ranks[kind]) end
        end
    end
end
function P.publicNeed(need)
    if not need then return nil end
    return {kind=need.kind,woundIndex=need.woundIndex,key=need.key,rank=need.rank,
        visitEligible=need.visitEligible,pending=need.pending,terminalQuarantine=need.terminalQuarantine}
end
local function loanMarked(item,allowKitContents)
    local data,okay=call(item,"getModData")
    if not okay or type(data)~="table" then return true end
    for key,value in pairs(data) do
        if type(key)=="string" and value~=nil and value~=false
            and (string.sub(key,1,3)=="SC_" or string.sub(key,1,3)=="LF_") then
            local lower=string.lower(key)
            if (string.find(lower,"loan",1,true) or string.find(lower,"borrow",1,true))
                and not (allowKitContents and key=="LF_MedicKitLoan") then return true end
        end
    end
    return false
end
function P.itemAllowed(actor,item,spirits)
    if not item or not SC.PersonalItems or type(SC.PersonalItems.isProtected)~="function" then return false end
    local root=U().inventory(actor)
    local current,seen,ancestors=item,{},{}
    for _=1,8 do
        if current==nil or seen[current] then return false end
        seen[current]=true
        local ownKit=current~=item and SC.MedicKit and type(SC.MedicKit.mayUseContents)=="function"
            and SC.MedicKit.mayUseContents(actor,current)==true
        if flag(current,"isFavorite")==true or SC.PersonalItems.isProtected(current,actor,"medical_consume")
            or loanMarked(current,ownKit) then return false end
        if spirits then
            local data=select(1,call(current,"getModData"))
            if flag(current,"isFavorite") or type(data)~="table"
                or data.SC_ManualEquipFor~=nil or data.SC_ManualEquipSerial~=nil or data.SC_ManualWearFor~=nil then return false end
        end
        local source,okay=call(current,"getContainer")
        if not okay or not source or not U().containerContainsIdentity(source,current) then return false end
        if source==root then
            if spirits then
                if select(1,call(actor,"getPrimaryHandItem"))==item or select(1,call(actor,"getSecondaryHandItem"))==item then return false end
                if SC.Needs and (SC.Needs.isSafeWaterItem(item) or SC.Needs.isDrinkingContainer(item)) then return false end
            end
            return true,{item=item,source=select(1,call(item,"getContainer")),ancestors=ancestors}
        end
        local bag,known=call(source,"getContainingItem")
        if not known or not bag then return false end
        ancestors[#ancestors+1]=bag;current=bag
    end
    return false
end
local function allItems(actor) return U().inventoryItemsDeep(U().inventory(actor),400,16) end
local function sourceItems(source)
    local items,okay=call(source,"getItems")
    if not okay or not items then return nil end
    local size,known=call(items,"size")
    if not known and type(items)=="table" then size=#items end
    if type(size)~="number" or size<0 or size>1024 then return nil end
    local result={}
    U().each(items,1024,function(item) result[#result+1]=item end)
    if #result~=size then return nil end
    return result
end
local function toolFor(actor,kind,items)
    for _,item in ipairs(items) do
        local name=string.lower(U().itemType(item))
        local eligible=name=="base.tweezers" or name=="base.sutureneedleholder"
            or U().itemHasTag(item,kind=="remove_bullet" and "RemoveBullet" or "RemoveGlass")
        local condition=number(item,"getCondition")
        local allowed,entry=P.itemAllowed(actor,item,false)
        if eligible and condition~=nil and condition>0 and allowed then return entry end
    end
end
local function stitchKit(actor,items)
    local needle,thread,suture,holder
    for _,item in ipairs(items) do
        local name=string.lower(U().itemType(item))
        local strict=SC.MedicalMedicines and SC.MedicalMedicines.itemAllowed
        local allowed,entry
        if type(strict)=="function" then allowed,entry=strict(actor,item) end
        if allowed then
            if name=="base.sutureneedle" and not suture and (number(item,"getCurrentUses") or 0)>0 then
                entry.kind="item";suture=entry
            elseif (name=="base.needle" or U().itemHasTag(item,"SewingNeedle")) and not needle then
                local condition=number(item,"getCondition")
                if condition and condition>0 then needle=entry end
            elseif (name=="base.thread" or U().itemHasTag(item,"Thread")) and not thread then
                local uses=number(item,"getCurrentUses")
                if flag(item,"IsDrainable")==true and uses and uses>=1 then entry.kind="uses";entry.uses=uses;thread=entry end
            end
            if name=="base.sutureneedleholder" and not holder then
                local condition=number(item,"getCondition")
                if condition and condition>0 then holder=entry end
            end
        end
    end
    if suture then return suture,nil,holder,true end
    if needle and thread then return thread,needle,holder,false end
end
local function reagent(actor,item)
    local name=string.lower(U().itemType(item))
    local fluid=select(1,call(item,"getFluidContainer"))
    local drainable=flag(item,"IsDrainable")==true
    local legacy=drainable and number(item,"getAlcoholPower") or 0
    local power,rank,amount,uses,fluidPower
    if fluid then
        amount=number(fluid,"getAmount")
        local properties=select(1,call(fluid,"getProperties"))
        local alcohol=number(properties,"getAlcohol")
        if not amount or amount<=0.15 or not alcohol or alcohol/amount+0.001<0.4 then return nil end
        fluidPower=4*alcohol/amount
        power=(drainable and legacy or 0)+fluidPower
        if not power or power~=power then return nil end
        local primary=select(1,call(fluid,"getPrimaryFluid"))
        local fluidName=string.lower(tostring(select(1,call(primary,"getFluidTypeString")) or ""))
        rank=name=="base.disinfectant" and 2 or fluidName=="rubbingalcohol" and 3 or 4
    elseif drainable and legacy==4 then
        uses=number(item,"getCurrentUses")
        if not uses or uses<1 then return nil end
        power,rank=4,(name=="base.alcoholwipes" or name=="base.alcoholedcottonballs") and 1 or 2
    else return nil end
    local allowed,entry=P.itemAllowed(actor,item,rank==4)
    if not allowed then return nil end
    entry.fluid,entry.amount,entry.uses,entry.power,entry.painPower,entry.rank=fluid,amount,uses,power,fluidPower or power,rank
    entry.kind=fluid and "fluid" or "uses"
    return entry
end
function P.hasDisinfectant(actor)
    local root=U().inventory(actor)
    if not root then return nil end
    local queue,seen,count={root},{[root]=true},0
    local index=1
    while index<=#queue do
        local items=sourceItems(queue[index]);index=index+1
        if not items then return nil end
        for _,item in ipairs(items) do
            count=count+1
            if count>400 then return nil end
            if reagent(actor,item) then return true end
            local nested,known=U().containedInventory(item)
            if known and nested and not seen[nested] then
                if #queue>=16 then return nil end
                seen[nested]=true;queue[#queue+1]=nested
            elseif U().instanceOf(item,"InventoryContainer")
                or select(1,call(item,"getCategory"))=="Container" then
                if not known then return nil end
            end
        end
    end
    return false
end
local function dressing(actor,items,wound,rankFunction,excluded,cleaning)
    local best,bestRank
    for _,item in ipairs(items) do
        if not excluded[item] then
            local rank=rankFunction(item,false,wound)
            local power=number(item,"getBandagePower")
            local allowed,entry=P.itemAllowed(actor,item,false)
            if rank and allowed and (not cleaning or power and power>=2) then
                if cleaning then
                    local name=string.lower(U().itemType(item))
                    rank=(flag(item,"isAlcoholic") or string.find(name,"steril",1,true)) and 10 or (power or 0)
                end
                if not bestRank or rank<bestRank then best,bestRank=entry,rank end
            end
        end
    end
    return best
end
function P.prepare(actor,need,rankFunction)
    if not P.handles(need.kind) then return nil,"medical_need_changed" end
    if SC.NativeActions and type(SC.NativeActions.needsStatus)=="function" then
        local _,tracked=SC.NativeActions.needsStatus(actor)
        if tracked~=nil then return nil,"medical_needs_active" end
    end
    local items=allItems(actor)
    local serious={}
    for key,value in pairs(need.wound) do serious[key]=value end
    serious.seriousAfterProcedure=true
    local plan={kind=need.kind,woundIndex=need.woundIndex,key=need.key,resources={}}
    local excluded={}
    local fresh=dressing(actor,items,serious,rankFunction,excluded,false)
    if not fresh then return nil,need.kind=="clean_burn" and "no_clean_dressing_for_burn" or "no_clean_bandage" end
    plan.fresh=fresh;excluded[fresh.item]=true
    if need.kind=="remove_bullet" or need.kind=="remove_glass" then
        plan.tool=toolFor(actor,need.kind,items)
        if not plan.tool then return nil,"no_tweezers" end
    elseif need.kind=="clean_burn" then
        plan.consumable=dressing(actor,items,serious,rankFunction,excluded,true)
        if not plan.consumable then return nil,"no_clean_dressing_for_burn" end
        plan.consumable.kind="bandage"
    elseif need.kind=="disinfect_wound" then
        for _,item in ipairs(items) do
            local candidate=reagent(actor,item)
            if candidate and (not plan.consumable or candidate.rank<plan.consumable.rank) then plan.consumable=candidate end
        end
        if not plan.consumable then return nil,"no_disinfectant" end
    elseif need.kind=="stitch_wound" then
        if need.wound.glass then return nil,"glass_before_stitching" end
        plan.consumable,plan.needle,plan.holder,plan.suture=stitchKit(actor,items)
        if not plan.consumable then return nil,"no_stitching_kit" end
        plan.durationTicks=math.max(1,(plan.suture or plan.holder) and 150 or 200)-4*math.max(0,U().perkLevel(actor,"Doctor",0))
    end
    local seen={}
    for _,entry in pairs({fresh=plan.fresh,tool=plan.tool,consumable=plan.consumable,needle=plan.needle,holder=plan.holder}) do
        if entry then
            for _,item in ipairs({entry.item,unpack(entry.ancestors or {})}) do
                if not seen[item] then seen[item]=true;plan.resources[#plan.resources+1]=item end
            end
        end
    end
    if need.patient and SC.MedicalMaintenance and SC.MedicalMaintenance.preflightProcedure then
        local ready=SC.MedicalMaintenance.preflightProcedure(actor,{patient=need.patient,procedurePlan=plan},need.wound)
        if not ready then return nil,"medical_recovery_unreadable" end
    end
    return plan
end
function P.validatePlan(actor,plan)
    if type(plan)~="table" or not P.handles(plan.kind) then return false,"medical_need_changed" end
    for label,entry in pairs({fresh=plan.fresh,tool=plan.tool,consumable=plan.consumable,needle=plan.needle,holder=plan.holder}) do
        local allowed=true
        if entry then
            if plan.kind=="stitch_wound" and label~="fresh" then
                local strict=SC.MedicalMedicines and SC.MedicalMedicines.itemAllowed
                allowed=type(strict)=="function" and strict(actor,entry.item)==true
            else allowed=P.itemAllowed(actor,entry.item,label=="consumable" and entry.rank==4) end
        end
        if entry and (select(1,call(entry.item,"getContainer"))~=entry.source or not allowed) then
            return false,plan.kind=="stitch_wound" and label~="fresh" and "no_stitching_kit" or label=="tool" and "no_tweezers" or label=="consumable" and plan.kind=="disinfect_wound" and "no_disinfectant" or "no_clean_bandage"
        end
    end
    if plan.tool then
        local condition=number(plan.tool.item,"getCondition")
        if not condition or condition<=0 then return false,"no_tweezers" end
    end
    if plan.consumable then
        local entry=plan.consumable
        if entry.kind=="bandage" then
            local power=number(entry.item,"getBandagePower")
            if not power or power<2 or flag(entry.item,"isDirty") then return false,"no_clean_dressing_for_burn" end
            if not sourceItems(entry.source) then return false,"medical_resources_unreadable" end
        elseif plan.kind=="stitch_wound" then
            if entry.kind=="uses" and (number(entry.item,"getCurrentUses")~=entry.uses or entry.uses<1) then return false,"no_stitching_kit" end
            if entry.kind=="item" and (string.lower(U().itemType(entry.item))~="base.sutureneedle"
                or (number(entry.item,"getCurrentUses") or 0)<=0) then return false,"no_stitching_kit" end
            if plan.needle then
                local condition=number(plan.needle.item,"getCondition")
                if not condition or condition<=0 then return false,"no_stitching_kit" end
            end
            if plan.holder then
                local condition=number(plan.holder.item,"getCondition")
                if not condition or condition<=0 then return false,"no_stitching_kit" end
            end
        else
            local current=reagent(actor,entry.item)
            if not current or current.kind~=entry.kind or current.power~=entry.power
                or current.fluid~=entry.fluid then return false,"no_disinfectant" end
            if entry.kind=="uses" and current.uses~=entry.uses
                or entry.kind=="fluid" and math.abs(current.amount-entry.amount)>0.000001 then return false,"no_disinfectant" end
        end
    end
    return true
end
local function sync(part,mask) if type(syncBodyPart)=="function" then pcall(syncBodyPart,part,mask) end end
function P.start(helper,state,wound)
    local plan=state.procedurePlan
    local valid,reason=P.validatePlan(helper,plan)
    if not valid then return nil,reason end
    local part=wound.part
    local pain=number(part,"getAdditionalPain")
    if pain==nil then return nil,"medical_procedure_unverified" end
    local doctor=math.max(0,U().perkLevel(helper,"Doctor",0))
    local data={kind=plan.kind,painBefore=pain,doctor=doctor,ownerId=P.actorId(helper),consumable=plan.consumable}
    if plan.kind=="remove_bullet" then
        if flag(part,"haveBullet")~=true then return nil,"medical_need_changed" end
        data.pain,data.xp,data.mask=80-doctor,20,0x40460108
    elseif plan.kind=="remove_glass" then
        if flag(part,"haveGlass")~=true then return nil,"medical_need_changed" end
        data.pain,data.xp,data.mask=30-doctor,15,0x00480000
    elseif plan.kind=="clean_burn" then
        if flag(part,"isNeedBurnWash")~=true then return nil,"medical_need_changed" end
        data.pain,data.xp,data.mask=60-doctor,10,0x380400000
    elseif plan.kind=="stitch_wound" then
        if flag(part,"haveGlass")~=false then return nil,"glass_before_stitching" end
        if not wound.deepWound or flag(part,"stitched")==true then return nil,"medical_need_changed" end
        local getsXp=flag(part,"isGetStitchXp")
        if getsXp==nil or type(ZombRandFloat)~="function" or type(ZombRand)~="function" then return nil,"medical_procedure_unverified" end
        local randomOkay,randomTime=pcall(ZombRandFloat,2,5)
        local infectionOkay,infectionRoll=pcall(ZombRand,5+doctor*2.5)
        if not randomOkay or type(randomTime)~="number" or randomTime~=randomTime or randomTime<2 or randomTime>5
            or not infectionOkay or type(infectionRoll)~="number" or infectionRoll~=infectionRoll
            or infectionRoll<0 or infectionRoll>=5+doctor*2.5 then return nil,"medical_procedure_unverified" end
        data.stitchTime=(1+doctor)/2*randomTime;data.infect=infectionRoll==0
        data.pain=math.max(0,((plan.suture or plan.holder) and 10 or 20)-doctor)
        data.xp=getsXp and 15 or nil;data.mask=0x00570188
    else
        data.alcoholBefore=number(part,"getAlcoholLevel")
        if flag(part,"isInfectedWound")~=true or not P.disinfectReady(state.patient,wound.index,data.alcoholBefore) then return nil,"medical_need_changed" end
        data.alcoholAfter=data.alcoholBefore+plan.consumable.power
        data.pain,data.mask=plan.consumable.painPower*13-doctor/2,0x00608200
    end
    local Care=SC.MedicalMaintenance
    local previous,why=Care.uncover(helper,state,wound)
    if not previous then return nil,why end
    if plan.kind=="remove_bullet" then call(part,"setHaveBullet",false,doctor)
    elseif plan.kind=="remove_glass" then call(part,"setHaveGlass",false)
    elseif plan.kind=="clean_burn" then call(part,"setNeedBurnWash",false)
    elseif plan.kind=="stitch_wound" then call(part,"setStitched",true)
    else call(part,"setAlcoholLevel",data.alcoholAfter) end
    local alcoholAfter=number(part,"getAlcoholLevel")
    local verified=plan.kind=="remove_bullet" and flag(part,"haveBullet")==false
        or plan.kind=="remove_glass" and flag(part,"haveGlass")==false
        or plan.kind=="clean_burn" and flag(part,"isNeedBurnWash")==false
        or plan.kind=="stitch_wound" and flag(part,"stitched")==true
        or plan.kind=="disinfect_wound" and alcoholAfter~=nil and math.abs(alcoholAfter-data.alcoholAfter)<0.0001
    if not verified then Care.restoreCover(part,previous);return nil,"medical_procedure_unverified" end
    local pending=Care.publishProcedure(helper,state,wound,previous,data)
    -- Publish irreversible proof before secondary calls or consumption. Neither
    -- an exception nor recovery may re-run the native procedure or XP request.
    data.secondaryAttempted=true
    call(part,"setAdditionalPain",pain+data.pain)
    local actualPain=number(part,"getAdditionalPain")
    data.painVerified=actualPain~=nil and math.abs(actualPain-(pain+data.pain))<0.0001
    if plan.kind=="stitch_wound" then
        call(part,"setStitchTime",data.stitchTime)
        if data.infect then call(part,"setInfectedWound",true) end
        local actualTime=number(part,"getStitchTime")
        data.painVerified=data.painVerified and actualTime~=nil and math.abs(actualTime-data.stitchTime)<0.0001
            and number(part,"getDeepWoundTime")==0 and number(part,"getBleedingTime")==0
            and flag(part,"deepWounded")==false and flag(part,"bleeding")==false
            and (not data.infect or flag(part,"isInfectedWound")==true)
    end
    if data.xp and Perks and Perks.Doctor then
        -- The stock global wrapper discards NPC requests. This public native
        -- overload keeps vanilla's multipliers and one published request.
        data.xpRequested=data.xp
        local experience=select(1,call(helper,"getXp"))
        call(experience,"AddXP",Perks.Doctor,data.xp,true,true,false,false)
    end
    if plan.kind~="disinfect_wound" and CharacterTrait and CharacterStat then
        local okay,hemophobic=pcall(function() return helper:hasTrait(CharacterTrait.HEMOPHOBIC) end)
        if okay and hemophobic then
            local stats=select(1,call(helper,"getStats"));call(stats,"add",CharacterStat.PANIC,50)
            if type(syncPlayerStats)=="function" then pcall(syncPlayerStats,helper,0x00000100) end
        end
    end
    if plan.kind=="disinfect_wound" then
        local store=timeStore(state.patient,true)
        if type(store)=="table" then
            store[tostring(wound.index)]=P.worldHours() or false
            if not P.writeCare(state.patient,"medicalDisinfectHours",store) then
                pending.quarantined=true;pending.quarantineReason="medical_recovery_unreadable"
            end
        end
        local existing=P.readCare(state.patient,"medicalInfectionDisinfectHours")
        local first={}
        if existing==nil or type(existing)=="table" and P.firstDisinfectHours(state.patient,wound.index)~=false then
            for key,value in pairs(existing or {}) do first[key]=value end
            first[tostring(wound.index)]=first[tostring(wound.index)] or first[wound.index] or P.worldHours()
            if not P.writeCare(state.patient,"medicalInfectionDisinfectHours",first) then
                pending.quarantined=true;pending.quarantineReason="medical_recovery_unreadable"
            end
        else pending.quarantined=true;pending.quarantineReason="medical_recovery_unreadable" end
    end
    sync(part,data.mask)
    return pending
end
local function nativeIdentity(item)
    local id=number(item,"getID")
    return id and id>0 and tostring(id) or tostring(item)
end
local function debitState(entry)
    if entry.kind=="fluid" then return number(entry.fluid,"getAmount") end
    if entry.kind=="uses" then return number(entry.item,"getCurrentUses") end
    return select(1,call(entry.item,"getContainer"))==entry.source and "present" or "absent"
end
function P.settle(helper,pending)
    local data=pending.procedure
    if not data or not data.consumable or data.debitDone then return true end
    if data.quarantined then return false,"medical_consumption_uncertain" end
    if P.actorId(helper)~=data.ownerId then return false,"medical_pending_owned" end
    local entry=data.consumable
    local current=debitState(entry)
    local before=entry.kind=="fluid" and entry.amount or entry.kind=="uses" and entry.uses or "present"
    local after=entry.kind=="fluid" and entry.amount-0.15 or entry.kind=="uses" and entry.uses-1 or "absent"
    local function matches(value,target)
        return type(target)=="number" and type(value)=="number" and math.abs(value-target)<0.00001 or value==target
    end
    if data.debitAttempted and matches(current,after) then data.debitDone=true;return true end
    if not matches(current,before) or not P.itemAllowed(helper,entry.item,entry.rank==4) then
        data.quarantined=true;return false,"medical_consumption_uncertain"
    end
    local prior={}
    if entry.kind=="bandage" then
        local inputs=sourceItems(entry.source)
        if not inputs then return false,"medical_redress_pending" end
        for _,item in ipairs(inputs) do prior[nativeIdentity(item)]=true end
        entry.outputType=select(1,call(entry.item,"getReplaceOnUseFullType"))
            or (string.find(U().itemType(entry.item),"RippedSheets",1,true) and "Base.RippedSheetsDirty" or "Base.BandageDirty")
    end
    data.debitAttempted=true
    if entry.kind=="fluid" then
        call(entry.fluid,"adjustAmount",after)
        if type(sendItemStats)=="function" then pcall(sendItemStats,entry.item) end
    else call(entry.item,"UseAndSync") end
    current=debitState(entry)
    if entry.kind=="bandage" then
        local output
        local outputs=sourceItems(entry.source)
        if not outputs then data.quarantined=true;return false,"medical_consumption_uncertain" end
        for _,item in ipairs(outputs) do
            if U().itemType(item)==entry.outputType and not prior[nativeIdentity(item)] then
                if output~=nil then data.quarantined=true;return false,"medical_consumption_uncertain" end
                output=item
            end
        end
        if output then data.nativeOutputId=nativeIdentity(output) end
        -- An output with an unconsumed original is a partial native effect,
        -- never proof that UseAndSync may be replayed safely.
        if output and not matches(current,after) or not output and matches(current,after) then
            data.quarantined=true;return false,"medical_consumption_uncertain"
        end
    end
    if matches(current,after) then
        data.debitDone=true;return true
    end
    if not matches(current,before) then data.quarantined=true;return false,"medical_consumption_uncertain" end
    return false,"medical_redress_pending"
end
function P.result(kind)
    return ({remove_bullet="bullet_removed",remove_glass="glass_removed",clean_burn="burn_cleaned",
        disinfect_wound="wound_disinfected",stitch_wound="wound_stitched"})[kind]
end
function P.release(actor,confirmedDead)
    -- Durable per-part timestamps survive release/dormancy. Death is the only
    -- terminal point for a provider's non-persistent fallback.
    if confirmedDead then disinfectTimes[P.actorId(actor)]=nil end
end
function P.reset() disinfectTimes={} end
return P
