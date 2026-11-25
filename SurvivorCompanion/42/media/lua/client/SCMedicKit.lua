-- SPDX-License-Identifier: MIT
-- Medic equipment uses the existing logistics decision; no event/timer service.
local SC=SurvivorCompanion
SC.MedicKit=SC.MedicKit or {}
local K=SC.MedicKit
local states=setmetatable({},{__mode="k"})
local claims=setmetatable({},{__mode="k"})
local MARKER="LF_MedicKitLoan"
local function U() return SC.GameplayUtil end
local function v(o,m,...) return select(1,U().call(o,m,...)) end
local function now() return U().nowMs() end
local function role(actor) return SC.Logistics.roleOf(actor)=="medic" end
local function protected(actor,item)
    return SC.PersonalItems and SC.PersonalItems.isProtected(item,actor,"logistics_take")==true
end
function K.isKit(item)
    if not U().instanceOf(item,"InventoryContainer") and v(item,"getCategory")~="Container" then return false end
    if not v(item,"getInventory") then return false end
    local script=v(item,"getScriptItem")
    if v(script,"isMedicalLoot")==true then return true end
    local okay,medical=pcall(function() return script and script.medical end)
    return okay and medical==true or string.match(U().itemType(item) or "","^Base%.FirstAidKit")~=nil
end
local function dressing(item)
    return SC.Medical and SC.Medical.dressingRank and SC.Medical.dressingRank(item,false)
end
local function carriedSupplyAllowed(actor,item)
    return SC.MedicalMedicines and SC.MedicalMedicines.itemAllowed(actor,item)==true
end
local function resource(item,purpose)
    local kind=U().itemType(item)
    local condition=tonumber((v(item,"getCondition")))
    local uses=tonumber((v(item,"getCurrentUses")))
    if purpose=="painkiller" then
        local doses=SC.MedicalMedicines and SC.MedicalMedicines.supplyDoses(item,"take_painkillers")
        return doses and doses>0
    elseif purpose=="suture" then return kind=="Base.SutureNeedle" and uses and uses>0
    elseif purpose=="needle" then
        return (kind=="Base.Needle" or U().itemHasTag(item,"SewingNeedle")) and condition and condition>0
    elseif purpose=="thread" then return (kind=="Base.Thread" or U().itemHasTag(item,"Thread")) and uses and uses>0
    elseif purpose=="tweezers" then
        return (kind=="Base.Tweezers" or kind=="Base.SutureNeedleHolder"
            or U().itemHasTag(item,"RemoveBullet") and U().itemHasTag(item,"RemoveGlass")) and condition and condition>0
    elseif purpose=="antibiotic" then
        local doses=SC.MedicalMedicines and SC.MedicalMedicines.supplyDoses(item,"take_antibiotics")
        return doses and doses>0
    elseif purpose=="disinfectant" then
        return SC.MedicalMedicines and SC.MedicalMedicines.disinfectantItem(item)==true
    end
    return false
end
K.resourceMatches=resource
local function loan(item)
    local marks=item and U().modData(item)
    return marks and type(marks[MARKER])=="table" and marks[MARKER] or nil
end
function K.mayUseContents(actor,kit)
    local receipt=loan(kit)
    return role(actor) and K.isKit(kit) and K.owns(actor,kit) and receipt
        and receipt.actorId==U().idOf(actor) and type(receipt.storageId)=="string"
end
function K.medicineContext(helper,patient,context)
    if not SC.MedicalSupplies then return nil end
    return SC.MedicalSupplies.context(helper or patient,patient,context)
end
function K.retained(actor,item,source)
    local function retainedKit(kit)
        return K.isKit(kit) and (role(actor) or loan(kit) and loan(kit).actorId==U().idOf(actor))
    end
    if retainedKit(item) then return true end
    if role(actor) and states[actor] and states[actor].retained and states[actor].retained[item] then return true end
    local parent=source or v(item,"getContainer")
    for _=1,3 do
        local owner=v(parent,"getContainingItem")
        if not owner then break end
        if retainedKit(owner) then return true end
        parent=v(owner,"getContainer")
    end
    return false
end
function K.owns(actor,item)
    local root=U().inventory(actor)
    local source=v(item,"getContainer")
    for _=1,4 do
        if source==root then return true end
        local holder=v(source,"getContainingItem")
        if not holder then return false end
        source=v(holder,"getContainer")
    end
    return false
end
local function usableKit(actor,item)
    if not K.isKit(item) or protected(actor,item) or v(item,"isFavorite")==true then return false end
    if v(actor,"getPrimaryHandItem")==item or v(actor,"getSecondaryHandItem")==item then return false end
    local marks=v(item,"getModData")
    if type(marks)~="table" then return false end
    for key,value in pairs(marks) do
        if value~=nil and value~=false and type(key)=="string" then
            local lower=string.lower(key)
            if (lower:sub(1,3)=="lf_" or lower:sub(1,3)=="sc_")
                and (lower:find("manual",1,true) or lower:find("borrow",1,true) or lower:find("loan",1,true)) then
                if key~=MARKER or not K.mayUseContents(actor,item) then return false end
            end
        end
    end
    return true
end
function K.view(actor,audit)
    local result={dressings=0,splints=0,kitDressings=0,kitSplints=0,retained={}}
    for _,record in ipairs(audit.items or {}) do
        local item=record.item
        local returnedKit=not role(actor) and loan(item) and loan(item).actorId==U().idOf(actor)
            and K.owns(actor,item) and not protected(actor,item) and v(item,"isFavorite")~=true
        if (usableKit(actor,item) or returnedKit) and (not result.kit or loan(item) and loan(item).actorId==U().idOf(actor)) then
            result.kit,result.container=item,v(item,"getInventory")
        end
        local allowed=carriedSupplyAllowed(actor,item)
        if dressing(item) and allowed then result.dressings=result.dressings+1 end
        if U().itemType(item)=="Base.Splint" and allowed then
            result.splints=result.splints+1 result.splintItem=result.splintItem or item
        end
        if allowed then
            for _,purpose in ipairs({"painkiller","suture","needle","thread","tweezers","antibiotic","disinfectant"}) do
                if not result[purpose.."Item"] and resource(item,purpose) then result[purpose.."Item"]=item end
            end
        end
    end
    if result.kit then
        for _,record in ipairs(audit.items or {}) do
            local allowed=carriedSupplyAllowed(actor,record.item)
            if allowed and record.source==result.container and dressing(record.item) then result.kitDressings=result.kitDressings+1 end
            if allowed and record.source==result.container and U().itemType(record.item)=="Base.Splint" then result.kitSplints=result.kitSplints+1 end
        end
    end
    result.stitchingKit=result.sutureItem~=nil or result.needleItem~=nil and result.threadItem~=nil
    for _,purpose in ipairs({"painkiller","tweezers","antibiotic","disinfectant"}) do
        if result[purpose.."Item"] then result.retained[result[purpose.."Item"]]=true end
    end
    if result.sutureItem then result.retained[result.sutureItem]=true
    else
        if result.needleItem then result.retained[result.needleItem]=true end
        if result.threadItem then result.retained[result.threadItem]=true end
    end
    local state=states[actor] or {};states[actor]=state;state.retained=result.retained
    return result
end
local function atCamp(actor)
    return SC.BaseLife and SC.BaseLife.active() and SC.BaseLife.isInside(actor)==true
        and v(actor,"getVehicle")==nil
end
function K.needsWork(actor,audit,facts)
    local state=states[actor]
    if state and state.work then return true end
    if not atCamp(actor) or audit.inventoryComplete==false then return false end
    facts=facts or K.view(actor,audit)
    if not role(actor) then
        if state and (state.retryAt or 0)>now() then return false end
        return facts.kit and loan(facts.kit) and loan(facts.kit).actorId==U().idOf(actor) or false
    end
    local missing=not facts.kit or facts.dressings<2 or facts.splints<1
        or not facts.painkillerItem or not facts.stitchingKit
    if state and (state.retryAt or 0)>now() and (not missing or state.message~="medic_kit_ready") then return false end
    if missing then return true end
    if facts.kitSplints<1 and facts.splintItem
        and SC.WorkTransport.hasRoom(facts.container,actor,facts.splintItem)==true then return true end
    if facts.kitDressings<math.min(2,facts.dressings) then
        for _,record in ipairs(audit.items) do
            if record.source~=facts.container and dressing(record.item) and carriedSupplyAllowed(actor,record.item)
                and SC.WorkTransport.hasRoom(facts.container,actor,record.item)==true then return true end
        end
    end
    -- Optional tools/medicines are sought between jobs, with the ordinary
    -- bounded retry if the camp has none. Loose selected supplies stay kept.
    return not facts.tweezersItem or not facts.disinfectantItem or not facts.antibioticItem
end
function K.summary(actor,audit)
    local facts=K.view(actor,audit or SC.Logistics.audit(actor))
    return facts,states[actor] and states[actor].message
end
local function wait(state,message)
    state.retryAt=now()+180000 state.search=nil state.pending=nil state.message=message state.stitchChoice=nil state.optionalMissing=nil
    return false,message
end
local function current(actor,state)
    return states[actor]==state and not U().isDead(actor) and role(actor) and atCamp(actor)
end
local function mayTake(actor,storage,container,item)
    return SC.BaseLife.storage(storage.id)==storage and SC.BaseLife.withdrawable(storage)
        and SC.BaseLife.resolveContainer(storage)==container and U().inventoryContains(container,item)
        and not protected(actor,item)
        and (not SC.MedicalSupplies or SC.MedicalSupplies.availableItem(actor,item))
        and SC.BaseLife.availableCountExact(storage,U().itemType(item))>0
end
local function search(actor,state,purpose)
    if not state.search or state.search.purpose~=purpose then
        local rows=SC.BaseLife.storageRows("medical",true)
        if purpose=="suture" or purpose=="needle" or purpose=="thread" or purpose=="tweezers" then
            for _,category in ipairs({"crafting","tools","general"}) do
                for _,storage in ipairs(SC.BaseLife.storageRows(category,true)) do rows[#rows+1]=storage end
            end
        end
        if purpose~="kit" and purpose~="dressing" and purpose~="splint" then
            local seen={};for _,storage in ipairs(rows) do seen[storage.id]=true end
            for _,storage in ipairs(SC.BaseLife.storageRows(nil,true)) do
                if not seen[storage.id] then rows[#rows+1]=storage;seen[storage.id]=true end
            end
        end
        state.search={purpose=purpose,rows=rows,row=1,index=0}
    end
    local scan=state.search
    local budget,containers=64,0
    while budget>0 and containers<4 do
        local storage=scan.rows[scan.row]
        if not storage then state.search=nil return false end
        containers=containers+1
        local container=SC.BaseLife.resolveContainer(storage)
        local list=container and v(container,"getItems")
        local size=list and SC.NativeList.size(list) or 0
        while scan.index<size and budget>0 do
            local item=select(1,SC.NativeList.get(list,scan.index))
            scan.index=scan.index+1 budget=budget-1
            local matches=purpose=="kit" and K.isKit(item)
                or purpose=="dressing" and dressing(item)~=nil
                or purpose=="splint" and U().itemType(item)=="Base.Splint"
                or resource(item,purpose)
            local held=claims[item]
            if matches and mayTake(actor,storage,container,item)
                and (not held or held.actor==actor or held.untilMs<=now())
                and SC.WorkTransport.hasRoom(U().inventory(actor),actor,item)==true then
                state.search=nil
                claims[item]={actor=actor,untilMs=now()+30000}
                return {storage=storage,container=container,item=item,purpose=purpose}
            end
        end
        if scan.index>=size then scan.row=scan.row+1 scan.index=0 end
    end
    return nil
end
function K.cancel(actor,reason)
    local state=states[actor]
    if state and state.work then
        if SC.NativeActions.workKind(actor)=="medic_kit" then
            local stopped,why=SC.NativeActions.cancelWork(actor,reason or "medic_kit_cancelled")
            if stopped~=true then return false,why end
        end
        if SC.ActionSupervisor.isCurrent(state.work.token) then
            local stopped,why=SC.ActionSupervisor.cancel(actor,reason)
            if stopped~=true then return false,why or "medic_kit_cleanup_pending" end
        end
        state.work=nil
    end
    for item,held in pairs(claims) do if held.actor==actor then claims[item]=nil end end
    if state then state.pending=nil state.search=nil state.retryAt=now()+15000 end
    return true
end
function K.busy(actor) return states[actor] and states[actor].work~=nil or false end
function K.step(actor,audit)
    local state=states[actor] or {} states[actor]=state
    if state.work then
        local work=state.work
        if not current(actor,state) then return K.cancel(actor,"medic_role_changed") end
        if SC.NativeActions.isWorkActive(actor) then
            if now()-work.at<30000 then
                SC.ActionSupervisor.progress(work.token,"medic-kit:"..tostring(now()))
                return true,"medic_kit_packing"
            end
            local stopped,why=SC.NativeActions.cancelWork(actor,"medic_kit_timeout")
            if stopped~=true then return true,why end
        end
        local finished,why=SC.NativeActions.finishWork(actor)
        if not finished then return true,why end
        if SC.ActionSupervisor.isCurrent(work.token) then
            local released,detail=SC.ActionSupervisor.complete(work.token)
            if released~=true then return true,detail or "medic_kit_cleanup_pending" end
        end
        state.work=nil
        if not U().inventoryContains(work.destination,work.item) then return wait(state,"medic_kit_transfer_failed") end
        state.message=nil
        return true,"medic_kit_packed"
    end
    if not atCamp(actor) then return false,"medic_kit_camp_only" end
    local facts=K.view(actor,audit)
    if not role(actor) then
        local receipt=facts.kit and loan(facts.kit)
        if not receipt or receipt.actorId~=U().idOf(actor) then return false,"medic_kit_not_needed" end
        local storage=SC.BaseLife.storage(receipt.storageId)
        if not storage or storage.category~="medical" then
            -- Its medical shelf was removed or now holds something else, so the
            -- loan can never be settled. The kit becomes ordinary gear that
            -- logistics may sort, instead of a retry every three minutes.
            U().modData(facts.kit)[MARKER]=nil
            return false,"medic_kit_storage_gone"
        end
        local container=SC.BaseLife.resolveContainer(storage)
        if not container then return wait(state,"medic_kit_return_pending") end
        local moved,why=SC.BaseWork.returnToStorage(actor,state,storage,container,facts.kit)
        if moved and why=="base_supply_returned" then U().modData(facts.kit)[MARKER]=nil return true,"medic_kit_returned" end
        return moved==true,why
    end
    if state.pending then
        local p=state.pending
        if not mayTake(actor,p.storage,p.container,p.item) then
            claims[p.item]=nil state.pending=nil return wait(state,"medic_kit_supplies_changed")
        end
        local held=claims[p.item]
        if held and held.actor~=actor and held.untilMs>now() then return wait(state,"medic_kit_supplies_reserved") end
        claims[p.item]={actor=actor,untilMs=now()+30000}
        local moved,why=SC.BaseWork.withdrawFromStorage(actor,state,p.storage,p.container,p.item)
        if moved and why=="base_supply_taken" then
            if p.purpose=="kit" then
                U().modData(p.item)[MARKER]={actorId=U().idOf(actor),storageId=p.storage.id}
                U().itemStableId(p.item,true)
            end
            claims[p.item]=nil state.pending=nil
            return true,"medic_kit_supplies_taken"
        end
        if moved~=true then claims[p.item]=nil return wait(state,why or "medic_kit_supplies_missing") end
        return true,why
    end
    if facts.kit then
        local candidates={}
        for _,record in ipairs(audit.items) do
            local rank=facts.kitDressings<2 and dressing(record.item)
                or facts.kitSplints<1 and record.item==facts.splintItem and 100
                or facts.retained[record.item] and 110
            if rank and record.source~=facts.container and carriedSupplyAllowed(actor,record.item)
                and SC.WorkTransport.hasRoom(facts.container,actor,record.item)==true then
                candidates[#candidates+1]={record=record,rank=rank}
            end
        end
        table.sort(candidates,function(a,b) return a.rank<b.rank end)
        local move=candidates[1] and candidates[1].record
        if move then
            local token,why=SC.ActionSupervisor.begin(actor,{owner="logistics",action="pack",
                targetKey="medic-kit",targetLabel="stock first aid kit",
                priority=SC.ActionSupervisor.Priority.LOGISTICS or 100,interruptible=true,
                onCancel=function(cancelActor,reason)
                    if cancelActor~=actor then return false,"medic_kit_owner_changed" end
                    if SC.NativeActions.workKind(actor)=="medic_kit" then
                        local stopped,detail=SC.NativeActions.cancelWork(actor,reason)
                        if stopped~=true then return false,detail end
                    end
                    state.work=nil
                    return true
                end})
            if not token then return false,why end
            if SC.Navigation then SC.Navigation.cancel(actor,"medic_kit_packing") end
            local stopped,reason=SC.NativeActions.stopDirect(actor)
            if not stopped then SC.ActionSupervisor.fail(token,reason) return false,reason end
            local started,reason=SC.NativeActions.startMedicKitTransfer(actor,move.item,move.source,
                facts.container,facts.kit,function()
                    return SC.ActionSupervisor.isCurrent(token) and current(actor,state)
                        and v(facts.kit,"getInventory")==facts.container
                        and K.owns(actor,facts.kit) and carriedSupplyAllowed(actor,move.item)
                        and K.retained(actor,facts.kit)
                end)
            if not started then SC.ActionSupervisor.fail(token,reason) return wait(state,reason) end
            state.work={item=move.item,destination=facts.container,token=token,at=now()}
            SC.ActionSupervisor.transition(token,"animating")
            return true,"medic_kit_packing"
        end
    end
    local purpose=not facts.kit and "kit" or facts.dressings<2 and "dressing" or facts.splints<1 and "splint"
        or not facts.painkillerItem and "painkiller"
        or not facts.stitchingKit and (facts.needleItem and "thread" or state.stitchChoice or "suture")
    if not purpose then
        state.optionalMissing=state.optionalMissing or {}
        for _,optional in ipairs({"tweezers","disinfectant","antibiotic"}) do
            if not facts[optional.."Item"] and not state.optionalMissing[optional] then purpose=optional;break end
        end
    end
    if purpose then
        local found=search(actor,state,purpose)
        if found==false and purpose=="suture" then
            -- A reusable sewing needle plus thread is a complete alternative.
            state.stitchChoice="needle"
            found=search(actor,state,"needle")
        end
        if found==false then
            local optional=purpose=="tweezers" or purpose=="disinfectant" or purpose=="antibiotic"
            if optional then state.optionalMissing[purpose]=true;return true,"medic_kit_finding_supplies" end
            return wait(state,purpose=="kit" and "medic_kit_unavailable" or "medic_kit_supplies_missing")
        end
        state.pending=found or nil
        return true,"medic_kit_finding_supplies"
    end
    return wait(state,"medic_kit_ready")
end
return K
