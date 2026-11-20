-- SPDX-License-Identifier: MIT
-- Bounded observations of permitted camp medicine; never moves or consumes it.
local SC=SurvivorCompanion
SC.MedicalSupplies=SC.MedicalSupplies or {}
local S=SC.MedicalSupplies
local states=setmetatable({},{__mode="k"})
local function U() return SC.GameplayUtil end
local function v(o,m,...) return select(1,U().call(o,m,...)) end
local function now() return U().nowMs() end
local function D() return SC.MedicalMedicines end
local function available(actor,item)
    if not item or v(item,"isFavorite")==true then return false end
    if SC.PersonalItems and SC.PersonalItems.isProtected(item,actor,"medical_consume") then return false end
    local marks=v(item,"getModData")
    if type(marks)~="table" then return false end
    for key,value in pairs(marks) do
        if value~=nil and value~=false and type(key)=="string" then
            local lower=string.lower(key)
            if (lower:sub(1,3)=="sc_" or lower:sub(1,3)=="lf_")
                and (lower:find("loan",1,true) or lower:find("borrow",1,true)
                    or lower:find("manual",1,true)) then return false end
        end
    end
    return true
end
S.availableItem=available
local function rowsFor(actor)
    local rows={}
    for _,storage in ipairs(SC.BaseLife.storageRows(nil,true)) do
        local permitted=not SC.BaseLife.workPermitted
            or SC.BaseLife.workPermitted(U().idOf(actor),{type="replace_bandage",target=storage})==true
        if permitted then rows[#rows+1]=storage end
    end
    return rows
end
local function sizeOf(container)
    local list,known=U().call(container,"getItems")
    if not known or not list then return nil end
    local count,read=U().call(list,"size")
    if not read then
        if type(list)=="table" and list.size==nil then count=#list else return nil end
    end
    if type(count)~="number" or count<0 or count~=count or count==math.huge or count~=math.floor(count) then return nil end
    return count,list
end
local function eligible(actor,row,item)
    local source=SC.BaseLife.resolveContainer(row)
    return source and v(item,"getContainer")==source and U().containerContainsIdentity(source,item)
        and SC.BaseLife.storage(row.id)==row and SC.BaseLife.withdrawable(row)
        and available(actor,item) and SC.BaseLife.availableCountExact(row,U().itemType(item))>0
end
local function newScan(actor,base)
    return {base=base,rows=rowsFor(actor),row=1,index=0,observations={},antibiotics={},
        antibioticCount=0,reagent=nil,antibioticsUnknown=false,reagentUnknown=false}
end
local function sourceValid(actor,entry)
    return entry and SC.BaseLife.resolveContainer(entry.storage)==entry.source
        and U().containerContainsIdentity(entry.source,entry.item)
        and eligible(actor,entry.storage,entry.item)
end
local function cacheValid(actor,cache)
    if not cache or now()-cache.at>5000 then return false end
    local current=rowsFor(actor)
    if #current~=#cache.rows then return false end
    for index,row in ipairs(current) do if row~=cache.rows[index] then return false end end
    for _,entry in ipairs(cache.observations) do
        local container=SC.BaseLife.resolveContainer(entry.storage)
        local count=container and sizeOf(container)
        if container~=entry.source or count~=entry.count then return false end
        if SC.BaseLife.availableCountExact(entry.storage,"Base.Antibiotics")~=entry.availableAntibiotics then return false end
    end
    for _,entry in ipairs(cache.antibiotics) do
        if not sourceValid(actor,entry) or D().supplyDoses(entry.item,"take_antibiotics")~=entry.doses then return false end
    end
    if cache.reagent and (not sourceValid(actor,cache.reagent) or D().disinfectantItem(cache.reagent.item)~=true) then return false end
    return true
end
local function observe(actor,base)
    local state=states[actor]
    if not state or state.base~=base then state={base=base};states[actor]=state end
    if not cacheValid(actor,state.cache) then state.cache=nil end
    if not state.scan and (not state.cache or now()-state.cache.at>=1000) then state.scan=newScan(actor,base) end
    local scan=state.scan
    if scan then
        local budget,containers=128,0
        while budget>0 and containers<8 do
            local storage=scan.rows[scan.row]
            if not storage then
                scan.at=now();state.cache=scan;state.scan=nil;break
            end
            local source=SC.BaseLife.resolveContainer(storage)
            local count,list
            if source then count,list=sizeOf(source) end
            if count==nil then
                scan.antibioticsUnknown,scan.reagentUnknown=true,true
                scan.row,scan.index=scan.row+1,0;containers=containers+1
            else
                if not scan.current or scan.current.storage~=storage then
                    scan.current={storage=storage,source=source,count=count,
                        availableAntibiotics=SC.BaseLife.availableCountExact(storage,"Base.Antibiotics"),usedAntibiotics=0}
                    scan.observations[#scan.observations+1]=scan.current
                elseif scan.current.source~=source or scan.current.count~=count then
                    state.scan=newScan(actor,base);return state.cache
                end
                while scan.index<count and budget>0 do
                    local item,read=SC.NativeList.get(list,scan.index)
                    scan.index=scan.index+1;budget=budget-1
                    if read~=true or not item then scan.antibioticsUnknown,scan.reagentUnknown=true,true
                    elseif available(actor,item) then
                        local doses=D().supplyDoses(item,"take_antibiotics")
                        if doses==nil then scan.antibioticsUnknown=true
                        elseif doses>0 and scan.antibioticCount<2 and eligible(actor,storage,item)
                            and scan.current.usedAntibiotics<scan.current.availableAntibiotics then
                            scan.antibiotics[#scan.antibiotics+1]={item=item,source=source,storage=storage,doses=doses}
                            scan.antibioticCount=math.min(2,scan.antibioticCount+doses)
                            scan.current.usedAntibiotics=scan.current.usedAntibiotics+1
                        end
                        local reagent=D().disinfectantItem(item)
                        if reagent==nil then scan.reagentUnknown=true
                        elseif reagent and not scan.reagent and eligible(actor,storage,item) then
                            scan.reagent={item=item,source=source,storage=storage}
                        end
                    end
                end
                if scan.index>=count then scan.row,scan.index,scan.current=scan.row+1,0,nil;containers=containers+1 end
            end
        end
    end
    if not cacheValid(actor,state.cache) then state.cache=nil end
    return state.cache
end
local function observeCommit(actor,base)
    local scan=newScan(actor,base)
    local total=0
    -- A dose is infrequent. Recheck the complete bounded source set at its
    -- commit boundary so same-size inventory swaps cannot prove absence.
    for _,storage in ipairs(scan.rows) do
        local source=SC.BaseLife.resolveContainer(storage)
        local count,list
        if source then count,list=sizeOf(source) end
        if count==nil or #scan.observations>=64 or total+count>4096 then return nil end
        total=total+count
        local observation={storage=storage,source=source,count=count,
            availableAntibiotics=SC.BaseLife.availableCountExact(storage,"Base.Antibiotics"),usedAntibiotics=0}
        scan.observations[#scan.observations+1]=observation
        for index=0,count-1 do
            local item,read=SC.NativeList.get(list,index)
            if read~=true or not item then return nil end
            if available(actor,item) then
                local doses=D().supplyDoses(item,"take_antibiotics")
                if doses==nil then scan.antibioticsUnknown=true
                elseif doses>0 and scan.antibioticCount<2 and observation.usedAntibiotics<observation.availableAntibiotics
                    and eligible(actor,storage,item) then
                    scan.antibiotics[#scan.antibiotics+1]={item=item,source=source,storage=storage,doses=doses}
                    scan.antibioticCount=math.min(2,scan.antibioticCount+doses)
                    observation.usedAntibiotics=observation.usedAntibiotics+1
                end
                local reagent=D().disinfectantItem(item)
                if reagent==nil then scan.reagentUnknown=true
                elseif reagent and not scan.reagent and eligible(actor,storage,item) then
                    scan.reagent={item=item,source=source,storage=storage}
                end
            end
        end
    end
    scan.at=now()
    return scan
end
local function resident(actor,base)
    if not actor or not U().isValidActor(actor) or U().isDead(actor) then return false end
    local id=U().idOf(actor)
    local row=SC.BaseLife.resident(id)
    local command=SC.Commands and SC.Commands.peek(actor)
    return row and row.baseId==base.id and row.duty==true and command and command.recruited==true
        and SC.BaseLife.isInside(actor)==true
end
function S.context(helper,patient,input)
    local base=SC.BaseLife and SC.BaseLife.active()
    local result={helper=helper,observedAt=now(),camp=false}
    if not base or not SC.BaseLife.isInside(patient) then
        result.disinfectantAvailable=D().disinfectantCarried(helper or patient)
        result.antibioticDoses=D().carriedDoses(helper or patient,"take_antibiotics")
        return result
    end
    helper=helper or patient
    result.camp,result.baseId=true,base.id
    local cache
    if input and input.stage=="commit" then cache=observeCommit(helper,base)
    else cache=observe(helper,base) end
    local count=cache and cache.antibioticCount or 0
    local disinfectant=cache and cache.reagent~=nil or false
    local seen,unknownAntibiotics,unknownReagent={},false,false
    local carriers={helper,patient}
    for _,id in ipairs(SC.BaseLife.dutyResidentIds()) do
        local actor=U().resolveActor(id)
        local row=SC.BaseLife.resident(id)
        if row and row.role=="medic" and resident(actor,base) then carriers[#carriers+1]=actor end
    end
    for _,actor in ipairs(carriers) do
        if actor and not seen[actor] then
            seen[actor]=true
            local carried=D().carriedDoses(actor,"take_antibiotics")
            if carried==nil then unknownAntibiotics=true else count=math.min(2,count+carried) end
            local reagent=D().disinfectantCarried(actor)
            if reagent==nil then unknownReagent=true elseif reagent then disinfectant=true end
        end
    end
    if count>=2 or cache and not cache.antibioticsUnknown and not unknownAntibiotics then result.antibioticDoses=count end
    if disinfectant then result.disinfectantAvailable=true
    elseif cache and not cache.reagentUnknown and not unknownReagent then result.disinfectantAvailable=false end
    result.stockKnown=result.antibioticDoses~=nil and result.disinfectantAvailable~=nil
    if result.antibioticDoses~=nil and result.antibioticDoses<2 and result.disinfectantAvailable~=nil then
        local best,bestId,unknown
        local patients,seenPatients={patient},{}
        for _,id in ipairs(SC.BaseLife.dutyResidentIds()) do
            local actor=U().resolveActor(id)
            if actor then patients[#patients+1]=actor end
        end
        for _,actor in ipairs(patients) do
            local id=U().idOf(actor)
            if not seenPatients[id] and (actor==patient or resident(actor,base))
                and (not SC.Factions or not SC.Factions.areAlliesBetween
                or SC.Factions.areAlliesBetween(helper,actor)==true) then
                seenPatients[id]=true
                local assessment=SC.Medical.assess(actor)
                local candidateContext={helper=helper,disinfectantAvailable=result.disinfectantAvailable}
                if D().antibioticEligible(actor,assessment,candidateContext) then
                    local infection=D().worstInfection(assessment)
                    if infection==nil then unknown=true
                    elseif not best or infection>best or infection==best and tostring(id)<tostring(bestId) then best,bestId=infection,id end
                end
            end
        end
        if not unknown then result.worstInfectionPatientId=bestId end
    end
    return result
end
function S.reset(actor)
    if actor then states[actor]=nil else states=setmetatable({},{__mode="k"}) end
end
return S
