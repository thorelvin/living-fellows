-- SPDX-License-Identifier: MIT
-- Sheep output participates in the existing farm lane and farm receipt ledger.
local SC=SurvivorCompanion
SC.AnimalShearing=SC.AnimalShearing or {}
local W=SC.AnimalShearing
local function U() return SC.GameplayUtil end
local function B() return SC.BaseLife end
local function S() return SC.FarmWork.animalSupport end
local function A() return SC.AnimalWork end
local function C() return A().shearingSupport end
local function value(o,m,...) return select(1,U().call(o,m,...)) end
local function number(o,m,...) return tonumber((value(o,m,...))) end
local function config(k,d) return tonumber(U().config(k)) or d end
local function note() B().noteWorkOwnershipMutation() end
local function enabled()
    return A().speciesEnabled("sheep") and config("animalWorkEnabled",1)==1 and config("animalShearEnabled",0)==1
end

function W.facts(animal,continuing)
    if not enabled() then return nil,"animal_shear_disabled" end
    local kind=value(animal,"getAnimalType")
    local data=value(animal,"getData")
    local marks,known=U().call(animal,"getModData")
    local attached,playerKnown=U().call(data,"getAttachedPlayer")
    local tree,treeKnown=U().call(data,"getAttachedTree")
    if (kind~="ewe" and kind~="ram") or value(animal,"isBaby")~=false
        or (number(animal,"getAge") or -1)<200
        or (number(animal,"getHealth") or 0)<=0 or value(animal,"isHeld")~=false
        or not known or type(marks)~="table" or marks.lfOddballGroupId or marks.lfWendellGroupId
        or not playerKnown or not treeKnown or attached or tree or value(animal,"canBeSheared")~=true then
        return nil,"animal_shear_not_ready"
    end
    local amount,maximum,stress=number(data,"getWoolQuantity"),number(data,"getMaxWool"),number(animal,"getStress")
    if not amount or amount~=amount or amount==math.huge or not maximum or maximum<=0 or maximum==math.huge
        or amount>maximum+.005
        or not stress or stress~=stress then return nil,"animal_shear_uncertain" end
    if stress>math.min(40,config("animalShearMaxStressPercent",40)) then return nil,"animal_shear_stressed" end
    if amount<1 then return nil,"animal_shear_finished" end
    if not continuing and (amount<=1 or amount<maximum*math.max(0,math.min(100,config("animalShearStartPercent",80)))/100) then
        return nil,"animal_shear_not_ready"
    end
    local gt=type(getGameTime)=="function" and getGameTime()
    local hour=number(gt,"getTimeOfDay")
    if not hour or hour<7 or hour>=20 then return nil,"farm_outside_night" end
    return {amount=amount,maximum=maximum,stress=stress}
end

local function electric(item)
    return U().itemType(item)=="Base.SheepElectricShears"
        or value(item,"IsDrainable")==true or U().instanceOf(item,"DrainableComboItem")
end
function W.tool(item)
    if not item or not U().itemHasTag(item,"SHEAR") or value(item,"isBroken")~=false then return false end
    if electric(item) then
        return (number(item,"getCurrentUsesFloat") or 0)>0
    end
    return true
end
local function toolRank(item)
    return (electric(item) and 0 or 100)+(number(item,"getCondition") or 0)/100
end

function W.depositRows()
    local rows={}
    for _,category in ipairs({"crafting","general"}) do
        for i,row in ipairs(B().depositStorageRows(category)) do
            if i>32 then break end rows[#rows+1]=row
        end
    end
    return rows
end

function W.candidate(row,base)
    if not enabled() or not row.sheep or #row.sheep.animals==0 then return nil end
    local saved=B().animalDocument().zones[row.id]
    local count=#row.sheep.animals
    local cursor=math.floor(tonumber(saved and saved.shearCursor) or 0)%count
    for _=1,math.min(4,count) do
        cursor=cursor%count+1
        local entry=row.sheep.animals[cursor]
        local animal=row.members[entry.id]
        if animal and not C().openJob(base,animal) and W.facts(animal,false) then
            if saved then saved.shearCursor=cursor end
            local target=C().candidateAt(row,"animal_shear",animal,3)
            target.animalId,target.species=entry.id,"sheep"
            return target
        end
    end
    if saved then saved.shearCursor=cursor end
end

local function floorItems(square)
    local list,known=U().call(square,"getWorldObjects")
    if not known or SC.NativeList.size(list)>32 then return nil end
    local result={}
    for i=0,SC.NativeList.size(list)-1 do
        local world=select(1,SC.NativeList.get(list,i))
        local item=value(world,"getItem")
        local id=item and value(item,"getID")
        if not item or id==nil then return nil end
        if result[tostring(id)] then return nil end
        result[tostring(id)]={item=item,world=world}
    end
    return result
end

local function receipts(job,terminal) return B().farmReceipts(job.id,terminal==true) end
local function woolWeight()
    local script=ScriptManager and ScriptManager.instance
    local item=script and value(script,"getItem","Base.WoolRaw")
    local weight=number(item,"getActualWeight") or number(item,"getWeight")
    return weight and weight>0 and weight<math.huge and weight or nil
end

function W.beforeIncrement(actor,job,state,animal)
    local facts,why=W.facts(animal,true)
    if not facts then return nil,why end
    if not W.tool(state.personalShears or state.borrowed and state.borrowed.item)
        or state.personalShears and S().protected(state.personalShears,actor) then return nil,"animal_shear_tool_unavailable" end
    local pending=0
    for _,r in ipairs(receipts(job)) do if r.wool then pending=pending+1 end end
    local all=B().farmReceipts(nil,false)
    if #all>=config("farmReceiptLimit",128) then return nil,"farm_receipt_limit" end
    local weight,limit=U().projectedCarryLoad(actor,false)
    local each=woolWeight()
    local inventory=U().inventory(actor)
    local used,capacity=number(inventory,"getCapacityWeight"),number(inventory,"getEffectiveCapacity",actor)
    if not weight or not limit or not each or not used or not capacity then return nil,"animal_shear_capacity_unknown" end
    if weight+(pending+1)*each+.1>limit or used+(pending+1)*each>capacity then
        return nil,"animal_shear_load_full"
    end
    local reserved,unassigned={},0
    for _,r in ipairs(all) do
        if r.wool then
            local id=r.wool.destinationStorageId
            if id then reserved[id]=(reserved[id] or 0)+1 else unassigned=unassigned+1 end
        end
    end
    local destination
    for _,row in ipairs(W.depositRows()) do
        local container=B().resolveContainer(row)
        local stock,max=number(container,"getCapacityWeight"),number(container,"getEffectiveCapacity",actor)
        if container and B().storageAcceptsDeposit(row,container)==true and stock and max
            and stock+((reserved[row.id] or 0)+unassigned+1)*each<=max then destination=row.id break end
    end
    if not destination then return nil,"animal_wool_storage_missing" end
    local square=U().squareOf(animal)
    local items=floorItems(square)
    if not items then return nil,"animal_shear_floor_unavailable" end
    return {items=items,square=square,before=facts.amount,storageId=destination}
end

function W.afterIncrement(actor,job,state,animal,proof)
    local after=number(value(animal,"getData"),"getWoolQuantity")
    local items=floorItems(proof.square)
    if not after or not items or U().squareOf(animal)~=proof.square then return false,"animal_shear_uncertain" end
    local found,count=nil,0
    for id,row in pairs(items) do
        if not proof.items[id] and U().itemType(row.item)=="Base.WoolRaw" then found,count=row,count+1 end
    end
    if math.abs(proof.before-after)<.0001 and count==0 then return true end -- Native refusal; no effect to replay.
    if math.abs(proof.before-after-1)>.005 or count~=1 then return false,"animal_shear_uncertain" end
    local marks=U().modData(found.item)
    if type(marks)~="table" or marks[SC.FarmWork.ITEM_MARKER]~=nil
        or job.reservedBy~=U().idOf(actor) or B().job(job.id)~=job then return false,"animal_shear_uncertain" end
    local x,y,z=U().position(proof.square)
    local okay,r=B().allocateFarmReceipt({jobId=job.id,actorId=U().idOf(actor),kind="output",
        itemType="Base.WoolRaw",nativeId=tostring(value(found.item,"getID")),destinationCategory="crafting",phase="selected",
        wool={version=1,animalId=job.target.animalId,x=math.floor(x),y=math.floor(y),z=math.floor(z),
            destinationStorageId=proof.storageId,before=proof.before,after=after}})
    if not okay then return false,"animal_shear_uncertain" end
    if not S().mark(found.item,r.id) then
        B().updateFarmReceipt(r.id,{phase="quarantined",blocker="animal_shear_uncertain"})
        return false,"animal_shear_uncertain"
    end
    job.target.woolCollected=(tonumber(job.target.woolCollected) or 0)+1
    note()
    return true
end

local function findItem(actor,r)
    local function matches(item)
        return U().itemType(item)==r.itemType and tostring(value(item,"getID"))==tostring(r.nativeId)
    end
    for _,item in ipairs(U().inventoryItems(U().inventory(actor),256)) do
        if matches(item) and value(item,"getContainer")==U().inventory(actor) then return item,nil,"carried" end
    end
    if r.wool.destinationStorageId then
        local row=B().storage(r.wool.destinationStorageId)
        local container=row and B().resolveContainer(row)
        if container and B().storageAcceptsDeposit(row,container)==true then
            for _,item in ipairs(U().inventoryItems(container,256)) do
                if matches(item) and value(item,"getContainer")==container then return item,nil,"delivered" end
            end
        end
    end
    local square=U().gridSquare(r.wool.x,r.wool.y,r.wool.z)
    if not square or B().withinWorkReach(square)~=true then return nil end
    local items=floorItems(square)
    local row=items and items[tostring(r.nativeId)]
    if row and matches(row.item) then return row.item,row.world,"selected" end
end

local function counted(job,r)
    local ids=job.target.woolDeliveredIds or {}
    if not ids[r.id] then
        ids[r.id]=true job.target.woolDeliveredIds=ids
        job.target.woolStored=(tonumber(job.target.woolStored) or 0)+1 note()
    end
end

local function collect(actor,job,state)
    local queued={}
    for _,output in ipairs(state.outputs or {}) do queued[output.receiptId]=true end
    for _,r in ipairs(receipts(job)) do
        if r.woolInvalid or r.wool and r.phase=="quarantined" then return false,"animal_shear_uncertain",true end
        if r.wool and not queued[r.id] then
            local item,world,phase=findItem(actor,r)
            if not item then return false,"animal_wool_missing",true end
            local marks=U().modData(item)
            if phase=="delivered" then
                if not marks or marks[SC.FarmWork.ITEM_MARKER] and marks[SC.FarmWork.ITEM_MARKER]~=r.id then
                    return false,"animal_shear_uncertain",true
                end
                S().unmark(item,r.id) B().updateFarmReceipt(r.id,{phase="delivered",blocker=false}) counted(job,r)
                return true,"animal_wool_stored"
            end
            if not marks or marks[SC.FarmWork.ITEM_MARKER]~=r.id then return false,"animal_shear_uncertain",true end
            if r.actorId~=U().idOf(actor) then
                -- Only a proven floor item may pass to the job's new Farmer.
                -- Carried or missing items remain with their original owner.
                if phase~="selected" or job.reservedBy~=U().idOf(actor) then return false,"animal_wool_carrier_unavailable",true end
                r.actorId=U().idOf(actor) note()
            end
            if phase=="carried" then
                B().updateFarmReceipt(r.id,{phase="carried",blocker=false})
                state.outputs=state.outputs or {}
                state.outputs[#state.outputs+1]={item=item,receiptId=r.id,category="crafting",wool=true}
                return true,"animal_wool_delivering"
            end
            local square=U().squareOf(world)
            if SC.WorkTransport.hasRoom(U().inventory(actor),actor,item)~=true then
                if state.outputs and #state.outputs>0 then return nil end
                return false,"animal_carry_capacity_low",true
            end
            local status,why=S().approach(actor,square,world,true)
            if status~="arrived" then return status~="failed",why,status=="failed" end
            if state.woolPickupAt then
                if SC.NativeActions.visualToken(actor,"loot_container")~=state.woolPickupToken then
                    state.woolPickupAt,state.woolPickupToken=nil,nil
                    return false,"animal_wool_pickup_interrupted",true
                end
                local visual=SC.NativeActions.visualStatus(actor,"loot_container")
                if visual=="active" then return true,"animal_wool_collecting" end
                state.woolPickupAt,state.woolPickupToken=nil,nil
                SC.NativeActions.clearVisual(actor)
                if visual~="completed" then return false,"animal_wool_pickup_interrupted",true end
                if value(item,"getWorldItem")~=world or U().worldItemPresent(square,world)~=true then return false,"animal_wool_missing",true end
                local taken,detail=U().takeWorldItemVerified(world,U().inventory(actor),item)
                if not taken then return false,detail,true end
                B().updateFarmReceipt(r.id,{phase="carried",blocker=false})
                state.outputs=state.outputs or {}
                state.outputs[#state.outputs+1]={item=item,receiptId=r.id,category="crafting",wool=true}
                return true,"animal_wool_collected"
            end
            SC.Navigation.cancel(actor,"animal_wool_pickup") SC.NativeActions.stopDirect(actor)
            local accepted,detail=U().move(actor,"walk",{action="loot_container",item=item,lootPosition="Low",faceTarget=world})
            if not accepted then
                -- The completed native shearing action can still be retiring
                -- its animation. Give that transition a short, bounded grace.
                state.woolPickupWaitAt=state.woolPickupWaitAt or U().nowMs()
                if U().nowMs()-state.woolPickupWaitAt<5000 then return true,"animal_wool_collecting" end
                return false,detail or "animal_wool_pickup_interrupted",true
            end
            state.woolPickupWaitAt=nil
            state.woolPickupAt=U().nowMs()
            state.woolPickupToken=SC.NativeActions.visualToken(actor,"loot_container")
            return true,"animal_wool_collecting"
        end
    end
end

function W.recoverReceipt(r)
    if r.woolInvalid or r.phase=="quarantined" then return true end
    if not r.wool then return false end
    local job=B().job(r.jobId)
    if job and job.state~="cancelled" and job.state~="completed"
        and not job.target.shearCancelled then return true end
    -- Cancelled floor output remains a real world item. Release its exact
    -- reservation for ordinary camp sorting; never report it as delivered.
    local item,world,phase=findItem(nil,r)
    if item and world and phase=="selected" then
        local marks=U().modData(item)
        if marks and marks[SC.FarmWork.ITEM_MARKER]==r.id then
            S().unmark(item,r.id)
            B().updateFarmReceipt(r.id,{phase="returned",blocker=false})
        end
        return true
    elseif item and phase=="delivered" then
        local marks=U().modData(item)
        if not marks or marks[SC.FarmWork.ITEM_MARKER] and marks[SC.FarmWork.ITEM_MARKER]~=r.id then return true end
        S().unmark(item,r.id)
        B().updateFarmReceipt(r.id,{phase="delivered",blocker=false})
        return true
    end
    return false -- Existing farm recovery can deposit carried outputs of an ended job.
end

function W.retainAfterCarrierLoss(r)
    if r.woolInvalid or r.phase=="quarantined" then return true end
    local square=r.wool and U().gridSquare(r.wool.x,r.wool.y,r.wool.z)
    local items=square and floorItems(square)
    -- An unloaded or crowded source is not proof of loss. Exact floor wool
    -- remains recoverable by the next Farmer even after its creator dies.
    return not items or items[tostring(r.nativeId)]~=nil
end

function W.progress(job)
    local carried,stored=0,0
    for _,r in ipairs(receipts(job,true)) do
        if r.wool then
            if r.phase=="carried" or r.phase=="depositing" then carried=carried+1 end
            if r.phase=="delivered" then stored=stored+1 end
        end
    end
    return {collected=tonumber(job.target.woolCollected) or 0,carried=carried,
        stored=math.max(stored,tonumber(job.target.woolStored) or 0)}
end

function W.cancel(actor,job,state,reason)
    job.target.shearCancelled=true note()
    if state.animalWork then
        local okay,why=SC.NativeActions.cancelWork(actor,reason or "animal_shear_interrupted")
        if not okay then return false,why end
        state.animalWork=nil
    end
    if state.shear and state.shear.cleanup then state.shear.cleanup() end
    state.shear=nil
    if state.woolPickupAt then
        local okay,why=SC.NativeActions.cancelVisualOwned(actor,state.woolPickupToken,reason)
        if not okay then return false,why end
        state.woolPickupAt,state.woolPickupToken=nil,nil
    end
    C().release(actor,job)
    if state.borrowed then
        local okay,why=S().restore(actor,state,reason or "animal_shear_interrupted")
        if not okay then return false,why end
    end
    for _,r in ipairs(receipts(job)) do
        if r.wool and r.phase~="quarantined" then
            B().updateFarmReceipt(r.id,{phase="recovery",blocker=reason or "farm_cancelled"})
            W.recoverReceipt(r)
        end
    end
    if #receipts(job)>0 then return false,"farm_recovery_pending" end
    return true
end

local function finish(actor,baseState,job,state,blocked)
    local settled,detail,waiting=S().settle(actor,baseState,state)
    if not settled then return waiting==true,detail end
    state.personalShears=nil C().release(actor,job)
    if blocked then return false,blocked,true end
    local okay,why=B().completeJob(job.id,U().idOf(actor),"sheep_care")
    return okay==true,okay and "farm_job_complete" or why
end

function W.update(actor,baseState,job,runtime,state)
    local target=job.target
    if not enabled() then target.shearCancelled=true end
    if state.animalWork then
        C().refresh(target)
        if not C().claim(actor,job) then
            local stopped,why=SC.NativeActions.cancelWork(actor,"animal_work_reserved")
            if not stopped then return true,why end
            state.shear.reason="animal_shear_interrupted"
        end
        if S().threat(actor,runtime) then
            local okay,why=SC.NativeActions.cancelWork(actor,"animal_shear_interrupted")
            if not okay then return true,why end
            state.shear.reason="animal_shear_interrupted"
        elseif SC.NativeActions.isWorkActive(actor) then
            if U().nowMs()-state.animalWork.startedAt<=config("farmActionMaxMs",120000) then return true,"farm_animal_shear_active" end
            local okay,why=SC.NativeActions.cancelWork(actor,"animal_action_timeout")
            if not okay then return true,why end state.shear.reason="animal_action_timeout"
        end
        local finished,why=SC.NativeActions.finishWork(actor)
        if not finished then return true,why end
        if state.shear and state.shear.cleanup then state.shear.cleanup() end
        state.animalWork=nil C().release(actor,job)
        if state.shear.reason=="animal_shear_uncertain" then target.shearUncertain=true note() end
        state.shear=nil
    end
    if S().threat(actor,runtime) then return C().fail(actor,job,"animal_sheep_unsafe") end
    local handled,why,pending=collect(actor,job,state)
    if handled~=nil then return handled,why,pending end
    if state.outputs then
        local out=state.outputs[1] local r=out and B().farmReceipt(out.receiptId)
        local handled,why,pending=S().deposit(actor,baseState,state)
        if r and r.phase=="delivered" then counted(job,r) end
        if why=="farm_output_storage_missing" then why="animal_wool_storage_missing" end
        return handled,why,pending
    end
    if target.shearCancelled or target.shearUncertain then
        return finish(actor,baseState,job,state,target.shearUncertain and "animal_shear_uncertain" or nil)
    end
    local animal,row=C().findDevice(target)
    if not animal then
        if row=="animal_audit_pending" then C().refresh(target) return true,row end
        return C().fail(actor,job,row)
    end
    local facts,reason=W.facts(animal,target.shearStarted==true)
    if reason=="animal_shear_finished" then
        return finish(actor,baseState,job,state)
    end
    if not facts or S().threat(actor,runtime) or A().cattleThreat(actor,row) then
        return C().fail(actor,job,reason or "animal_sheep_unsafe")
    end
    if not C().claim(actor,job) then return true,"animal_work_reserved" end
    if not state.borrowed and not state.personalShears then
        local best
        for _,item in ipairs(U().inventoryItems(U().inventory(actor),256)) do
            if W.tool(item) and not S().protected(item,actor) and (not SC.PersonalItems or not SC.PersonalItems.isProtected
                or SC.PersonalItems.isProtected(item,actor,"farm_tool")~=true)
                and (not best or toolRank(item)>toolRank(best)) then best=item end
        end
        if best and toolRank(best)>=100 then state.personalShears=best else
            -- Owned electric shears are still a fallback. Finish the bounded
            -- camp search for manual shears before spending their battery.
            local predicate=best and function(item) return W.tool(item) and toolRank(item)>=100 end or W.tool
            local okay,why,pending=S().borrow(actor,baseState,job,state,predicate,{"farming","tools"},"animal_shears",toolRank)
            if not okay and why=="farm_supply_missing" then
                if best then state.personalShears=best else why="animal_shear_tool_unavailable" end
            end
            if not state.personalShears then return okay,why,pending end
        end
    end
    local tool=state.personalShears or state.borrowed and state.borrowed.item
    if not W.tool(tool) then
        local settled,detail,waiting=S().settle(actor,baseState,state)
        if not settled then return waiting==true,detail end
        state.personalShears=nil return C().fail(actor,job,"animal_shear_tool_unavailable")
    end
    local proof,detail=W.beforeIncrement(actor,job,state,animal)
    if not proof then return C().fail(actor,job,detail) end
    local status,detail=S().approach(actor,U().squareOf(animal),animal,true)
    if status~="arrived" then return status~="failed",detail,status=="failed" end
    state.shear={}
    state.shear.before=function() return W.beforeIncrement(actor,job,state,animal) end
    state.shear.after=function(proof) return W.afterIncrement(actor,job,state,animal,proof) end
    target.shearStarted=true note()
    return C().begin(actor,job,state,animal,tool,"animal_shear")
end

return W
