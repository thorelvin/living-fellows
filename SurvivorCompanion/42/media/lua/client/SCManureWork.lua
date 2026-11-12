-- SPDX-License-Identifier: MIT
-- Small, receipt-backed farm jobs; discovery piggybacks on the animal census.
local SC=SurvivorCompanion
SC.ManureWork=SC.ManureWork or {}
local M=SC.ManureWork
local function U() return SC.GameplayUtil end
local function v(o,m,...) return select(1,U().call(o,m,...)) end
local function S() return SC.FarmWork.animalSupport end
local function H() return SC.AnimalWork.manureSupport end
local function id(item) return tostring(v(item,"getID")) end
local function changed() SC.BaseLife.noteWorkOwnershipMutation() end
local function open(base,key)
    for _,job in ipairs(base.jobs or {}) do
        if job.type=="farm" and job.target and job.target.deviceKey==key
            and job.state~="completed" and job.state~="cancelled" then return true end
    end
end
function M.items(square)
    local objects,known=U().call(square,"getWorldObjects")
    local count=known and SC.NativeList.size(objects)
    if not count or count>64 then return nil end
    local items,weight={},0
    for index=0,count-1 do
        local object=select(1,SC.NativeList.get(objects,index))
        local item=v(object,"getItem")
        if item and SC.FarmStorage.isManure(item) then
            if #items>=32 then return nil end
            local w=tonumber(U().itemWeight(item))
            if not w or w<0 then return nil end
            items[#items+1]=item weight=weight+w
        end
    end
    return items,weight
end
function M.inspectSquare(row,square)
    if v(square,"checkHaveDung")~=true then return end
    if #SC.BaseLife.depositStorageRows("manure")==0 then return end
    row.manure=row.manure or {}
    row.manureSeen=row.manureSeen or {}
    if #row.manure>=8 then return end
    local items=M.items(square)
    if items and #items>0 and not row.manureSeen[square] then
        row.manure[#row.manure+1]=square row.manureSeen[square]=true
    end
end
local function target(row,operation,point,key)
    local x,y,z=U().position(point)
    return {animal=true,operation=operation,priority=1,nativeZoneId=row.id,zoneId="animal:"..row.id,
        deviceKey=key,x=math.floor(x),y=math.floor(y),z=math.floor(z),
        cattle=#row.cattle.animals>0 or nil,sheep=#row.sheep.animals>0 or nil}
end
function M.candidate(row,base)
    if #SC.FarmStorage.manureRows(nil,nil)==0 then return nil end
    for _,square in ipairs(row.manure or {}) do
        local x,y,z=U().position(square)
        local key="dung:"..x..":"..y..":"..z
        if not open(base,key) and v(square,"checkHaveDung")==true then
            return target(row,"animal_manure",square,key)
        end
    end
    -- One retained container cursor, at most 64 items; never drain composters.
    local rows=SC.BaseLife.storageRows("manure",true)
    if #rows==0 then return nil end
    M.cursor=(M.cursor or 0)%#rows+1
    local source=rows[M.cursor]
    local container,object=SC.BaseLife.resolveContainer(source)
    local key="manure-store:"..source.id
    if not container or SC.FarmStorage.isComposter(object) or open(base,key) then return nil end
    for _,item in ipairs(U().inventoryItems(container,64)) do
        if SC.FarmStorage.isManure(item) and not S().protected(item,nil,"farm_borrow")
            and SC.BaseLife.availableCountExact(source,U().itemType(item))>0
            and #SC.FarmStorage.manureRows(item,nil,true)>0 then
            local result=target(row,"animal_manure_move",object,key)
            result.sourceStorageId,result.manureItemId=source.id,id(item)
            return result
        end
    end
end
local function tool(item)
    return U().itemHasTag(item,"TAKE_DUNG") and v(item,"isBroken")~=true
end
local function attachOutputs(actor,job,state)
    local root=U().inventory(actor)
    local owned={}
    for _,item in ipairs(U().inventoryItems(root,256)) do owned[id(item)]=item end
    local outputs={} local uncollected=false
    for _,receipt in ipairs(SC.BaseLife.farmReceipts(job.id,false)) do
        if receipt.kind=="output" and receipt.destinationCategory=="manure" then
            local item=owned[tostring(receipt.nativeId)]
            if item and U().itemType(item)==receipt.itemType then
                local marks=U().modData(item)
                if not marks or marks[SC.FarmWork.ITEM_MARKER]~=receipt.id then return false,"animal_manure_uncertain" end
                SC.BaseLife.updateFarmReceipt(receipt.id,{phase="carried",blocker=false})
                outputs[#outputs+1]={item=item,receiptId=receipt.id,category="manure",manure=true,
                    compostOnly=job.target.operation=="animal_manure_move"}
            elseif receipt.phase~="selected" then return false,"animal_manure_uncertain"
            else uncollected=true end
        end
    end
    state.outputs=#outputs>0 and outputs or nil
    if #outputs>0 and not uncollected then job.target.manureCommitted=true changed() end
    return true
end
local function allocate(actor,job,item,storage)
    for _,receipt in ipairs(SC.BaseLife.farmReceipts(job.id,false)) do
        if receipt.destinationCategory=="manure" and tostring(receipt.nativeId)==id(item) then return receipt end
    end
    local receipt,why=S().receipt(actor,job,"output",item,storage,"manure")
    if receipt then SC.BaseLife.updateFarmReceipt(receipt.id,{phase="selected"}) end
    return receipt,why
end
function M.recoverReceipt(receipt)
    if receipt.destinationCategory~="manure" then return false end
    local job=SC.BaseLife.job(receipt.jobId)
    -- The same job must reconcile selected world/source items before repeating.
    return job and job.target and (job.target.operation=="animal_manure"
        or job.target.operation=="animal_manure_move") and job.state~="cancelled"
        and job.state~="completed" or false
end
function M.cancel(actor,job,state,reason)
    if state.manureWork then
        local stopped,why=SC.NativeActions.cancelWork(actor,reason or "manure_cancelled")
        if not stopped then return false,why end
        local token=state.manureWork.token
        if SC.ActionSupervisor.isCurrent(token) then SC.ActionSupervisor.cancel(actor,reason) end
        state.manureWork=nil
    end
    local okay,why=attachOutputs(actor,job,state)
    if not okay then return false,why end
    local square=U().gridSquare(job.target.x,job.target.y,job.target.z)
    local source=job.target.sourceStorageId and SC.BaseLife.storage(job.target.sourceStorageId)
    local sourceContainer=source and SC.BaseLife.resolveContainer(source)
    local items=sourceContainer and U().inventoryItems(sourceContainer,256) or M.items(square) or {}
    for _,receipt in ipairs(SC.BaseLife.farmReceipts(job.id,false)) do
        if receipt.destinationCategory=="manure" and receipt.phase=="selected" then
            local found
            for _,item in ipairs(items) do
                if id(item)==tostring(receipt.nativeId) then
                    S().unmark(item,receipt.id)
                    SC.BaseLife.updateFarmReceipt(receipt.id,{phase="returned",blocker=false}) found=true break
                end
            end
            if not found then return false,"animal_manure_uncertain" end
        end
    end
    SC.FarmStorage.release(actor,job) H().release(actor,job)
    return true
end
function M.update(actor,baseState,job,runtime,state)
    local target=job.target
    if not state.manureRecovered then
        local okay,why=attachOutputs(actor,job,state)
        if not okay then return false,why,true end
        state.manureRecovered=true
    end
    if state.outputs then
        local output=state.outputs[1]
        if output then
            local storage=SC.FarmStorage.manureRows(output.item,actor,output.compostOnly)[1]
            if not storage then return false,"animal_manure_storage_missing",true end
            if not SC.FarmStorage.claim(storage,actor,job) then return true,"animal_work_reserved" end
        end
        local handled,why,pending=S().deposit(actor,baseState,state)
        if handled and why=="farm_output_deposited" then SC.FarmStorage.release(actor,job) end
        return handled,why,pending
    end
    if state.manureWork then
        H().claim(actor,job)
        local work=state.manureWork
        if SC.NativeActions.isWorkActive(actor) then
            if U().nowMs()-work.at<120000 and not S().threat(actor,runtime) then
                SC.ActionSupervisor.progress(work.token,"manure:"..tostring(U().nowMs()))
                return true,"animal_manure_collecting"
            end
            local stopped,why=SC.NativeActions.cancelWork(actor,"manure_interrupted")
            if not stopped then return true,why end
        end
        local finished,why=SC.NativeActions.finishWork(actor)
        if not finished then return true,why end
        state.manureWork=nil
        if SC.ActionSupervisor.isCurrent(work.token) then SC.ActionSupervisor.complete(work.token) end
        local okay,detail=attachOutputs(actor,job,state)
        if not okay then return false,detail,true end
        if not target.manureCommitted then return false,"animal_manure_uncertain",true end
        return true,"animal_manure_delivering"
    end
    if target.manureCommitted then
        local settled,why,pending=S().settle(actor,baseState,state)
        if not settled then return pending==true,why end
        H().release(actor,job)
        local okay,detail=SC.BaseLife.completeJob(job.id,U().idOf(actor),"manure_delivered")
        return okay==true,okay and "farm_job_complete" or detail
    end
    local object,row=H().findDevice(target)
    if not object then
        if row=="animal_audit_pending" then H().refreshTarget(target) return true,row end
        return false,row,true
    end
    if not H().claim(actor,job) then return true,"animal_work_reserved" end
    if S().threat(actor,runtime) or SC.AnimalWork.cattleThreat(actor,row) then return false,"animal_cattle_unsafe",true end
    if target.operation=="animal_manure_move" then
        local source=SC.BaseLife.storage(target.sourceStorageId)
        local container=source and SC.BaseLife.resolveContainer(source)
        if not source or not container or not SC.BaseLife.withdrawable(source) then return false,"animal_manure_storage_missing",true end
        local item
        for _,candidate in ipairs(U().inventoryItems(container,64)) do
            if id(candidate)==target.manureItemId then item=candidate break end
        end
        if not item then return false,"animal_manure_changed",true end
        if #SC.FarmStorage.manureRows(item,actor,true)==0 then return false,"animal_manure_storage_missing",true end
        local receipt,why=allocate(actor,job,item,source)
        if not receipt then return false,why,true end
        S().unmark(item,receipt.id)
        local moved,detail=SC.BaseWork.withdrawFromStorage(actor,baseState,source,container,item)
        S().mark(item,receipt.id)
        if moved and detail=="base_supply_taken" then
            SC.BaseLife.updateFarmReceipt(receipt.id,{phase="carried"})
            target.manureCommitted=true changed()
            state.manureRecovered=nil
        end
        return moved==true,detail,moved~=true
    end
    local items,weight=M.items(object)
    if not items or #items==0 then return false,"animal_manure_changed",true end
    local carried,capacity=U().carryLoad(actor)
    if not carried or not capacity or carried+weight>capacity
        or #SC.FarmStorage.manureRows(items[1],actor)==0 then return false,"animal_manure_capacity",true end
    local toolItem=state.borrowed and state.borrowed.item or state.dungTool
    if not toolItem then
        for _,item in ipairs(U().inventoryItems(U().inventory(actor),128)) do
            if tool(item) and not S().protected(item,actor,"farm_borrow") then state.dungTool=item toolItem=item break end
        end
    end
    if not toolItem then return S().borrow(actor,baseState,job,state,tool,{"farming","tools"},"manure_tool") end
    local phase,why=S().approach(actor,object,nil,true)
    if phase~="arrived" then return phase~="failed",why,phase=="failed" end
    local receipts={}
    for _,item in ipairs(items) do
        local marks=U().modData(item)
        local existing=marks and marks[SC.FarmWork.ITEM_MARKER]
        local receipt=existing and SC.BaseLife.farmReceipt(existing)
        if existing and (not receipt or receipt.jobId~=job.id)
            or SC.PersonalItems and SC.PersonalItems.isProtected(item,actor,"farm_borrow") then
            return false,"animal_manure_reserved",true
        end
        local receipt,reason=allocate(actor,job,item,nil)
        if not receipt then return false,reason,true end
        receipts[#receipts+1]=receipt
    end
    local token,reason=SC.ActionSupervisor.begin(actor,{owner="work",action="farm_animal_manure",
        targetKey=job.id,targetLabel="collect manure",priority=SC.ActionSupervisor.Priority.WORK,
        ignoreRetry=true,interruptible=true})
    if not token then return false,reason end
    if SC.Navigation then SC.Navigation.cancel(actor,"manure_interaction") end
    local stopped,detail=SC.NativeActions.stopDirect(actor)
    if not stopped then SC.ActionSupervisor.fail(token,detail) return false,detail end
    local function valid(committing)
        if not tool(toolItem) or not SC.AnimalWork.canUse(actor,job,object,toolItem) then return false end
        if committing~=true then return true end
        local current,w=M.items(object)
        local load,limit=U().carryLoad(actor)
        if not current or #current~=#items or not load or not limit or load+w>limit then return false end
        local expected={}
        for _,item in ipairs(items) do expected[item]=true end
        for _,item in ipairs(current) do if not expected[item] then return false end end
        return true
    end
    local started,why=SC.NativeActions.startFarmManure(actor,toolItem,object,job.id,valid,function()
        for index,item in ipairs(items) do
            if v(item,"getContainer")~=U().inventory(actor) or v(item,"getWorldItem")~=nil then return false end
            SC.BaseLife.updateFarmReceipt(receipts[index].id,{phase="carried"})
        end
        target.manureCommitted=true changed()
        return true
    end)
    if not started then SC.ActionSupervisor.fail(token,why) return false,why,true end
    state.manureWork={token=token,at=U().nowMs()}
    SC.ActionSupervisor.transition(token,"animating")
    return true,"animal_manure_collecting"
end
return M
