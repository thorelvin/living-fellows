-- SPDX-License-Identifier: MIT
-- Farm destinations share base object identities and the existing work lane.
local SC = SurvivorCompanion
SC.FarmStorage = SC.FarmStorage or {}
local F = SC.FarmStorage
local claims = {}
local function U() return SC.GameplayUtil end
local function value(o,m,...) return select(1,U().call(o,m,...)) end
local function number(o,m,...) return tonumber((value(o,m,...))) end
local function S() return SC.FarmWork.animalSupport end
local function now() return U().nowMs() end

function F.isManure(item)
    return value(item,"isDung")==true or string.match(U().itemType(item) or "","^Base%.Dung_")~=nil
end
function F.manureCount(storage)
    local container=SC.BaseLife.resolveContainer(storage)
    if not container then return nil end
    local count=0
    for _,item in ipairs(U().inventoryItems(container,64)) do
        if F.isManure(item) then count=count+1 end
    end
    local size=SC.NativeList.size(value(container,"getItems")) or 0
    return tostring(count)..(size>64 and "+" or "")
end
function F.milkInfo(owner)
    local fc=value(owner,"getFluidContainer")
    local amount,capacity=number(fc,"getAmount"),number(fc,"getCapacity")
    if not fc or not amount or not capacity or amount<0 or capacity<=0 then return nil end
    local kind
    for _,name in ipairs({"CowMilk","SheepMilk"}) do
        if Fluid and Fluid[name] and value(fc,"isPureFluid",Fluid[name])==true then kind=name break end
    end
    return {container=fc,amount=amount,capacity=capacity,fluid=kind}
end
function F.canMarkMilk(object)
    local info=F.milkInfo(object)
    return info~=nil and (info.amount<0.0001 or info.fluid~=nil)
        and value(info.container,"isInputLocked")==false
        and (Fluid and (value(info.container,"canAddFluid",Fluid.CowMilk)==true
            or value(info.container,"canAddFluid",Fluid.SheepMilk)==true)) or false
end
function F.claim(storage,actor,job)
    local held=claims[storage.id]
    if held and held.untilMs>now() and (held.actor~=actor or held.job~=job.id) then return false end
    claims[storage.id]={actor=actor,job=job.id,untilMs=now()+30000}
    return true
end
function F.release(actor,job)
    for id,held in pairs(claims) do
        if held.actor==actor and (not job or held.job==job.id) then claims[id]=nil end
    end
end
local function available(storage,actor,job)
    local held=claims[storage.id]
    return not held or held.untilMs<=now() or held.actor==actor and (not job or held.job==job.id)
end
function F.milkDestination(actor,item,job,excluded)
    local donor=F.milkInfo(item)
    if not donor or not donor.fluid or donor.amount<=0 then return nil end
    for index,storage in ipairs(SC.BaseLife.depositStorageRows("milk")) do
        if index>32 then break end
        if storage.deposits~=false and SC.BaseLife.storage(storage.id)==storage
            and not (excluded and excluded[storage.id]) and available(storage,actor,job) then
            local fc,object=SC.BaseLife.resolveFluidContainer(storage)
            local target=object and F.milkInfo(object)
            if fc and target and (target.amount<0.0001 or target.fluid==donor.fluid)
                and value(fc,"isInputLocked")==false and value(donor.container,"isOutputLocked")~=true
                and target.capacity-target.amount>0.0001
                and value(fc,"canAddFluid",Fluid[donor.fluid])==true
                and SC.BaseLife.withinWorkReach(object)==true then return storage,object,target end
        end
    end
end
function F.isComposter(object)
    return U().instanceOf(object,"IsoCompost") or value(value(object,"getContainer"),"getType")=="composter"
end
function F.manureRows(item,actor,compostersOnly)
    local preferred,overflow={},{}
    for index,storage in ipairs(SC.BaseLife.depositStorageRows("manure")) do
        if index>32 then break end
        local container,object=SC.BaseLife.resolveContainer(storage)
        local composter=object and F.isComposter(object)
        local processing=not composter or (number(object,"getCompost") or 100)<100
        local room=not item
        if item and actor then room=SC.WorkTransport.hasRoom(container,actor,item)==true
        elseif item then
            local used,capacity=number(container,"getCapacityWeight"),number(container,"getCapacity")
            room=used~=nil and capacity~=nil and used+U().itemWeight(item)<=capacity
        end
        if container and processing and available(storage,actor) and (not compostersOnly or composter)
            and SC.BaseLife.storageAcceptsDeposit(storage,container)==true
            and room then
            local rows=composter and preferred or overflow
            rows[#rows+1]=storage
        end
    end
    for _,storage in ipairs(overflow) do preferred[#preferred+1]=storage end
    return preferred
end

local function updateReceipt(receipt)
    return SC.BaseLife.updateFarmReceipt(receipt.id,{milk=receipt.milk})==true
end
-- Called after each synchronous native increment, before another save/event.
-- Source and destination deltas must agree; no scripted fluid deduction occurs.
function F.observePour(receipt,item,object,beforeSource,beforeTarget)
    local a,b=F.milkInfo(item),F.milkInfo(object)
    if not a or not b or a.amount>0.0001 and a.fluid~=receipt.milk.fluid
        or b.amount>0.0001 and b.fluid~=receipt.milk.fluid then return false end
    local loss,gain=beforeSource-a.amount,b.amount-beforeTarget
    if loss< -0.005 or gain< -0.005 or math.abs(loss-gain)>0.005 then return false end
    if math.abs(loss)<0.000001 and math.abs(gain)<0.000001 then return true end
    receipt.milk.poured=(receipt.milk.poured or 0)+math.max(0,gain)
    receipt.milk.after=a.amount
    local pour=receipt.milk.pour
    if pour then pour.source,pour.target=a.amount,b.amount end
    return updateReceipt(receipt)
end
function F.resumePour(receipt,item)
    local pour=receipt.milk and receipt.milk.pour
    if not pour then return true end
    local storage=SC.BaseLife.storage(pour.storageId)
    local object
    if storage then local ignored; ignored,object=SC.BaseLife.resolveFluidContainer(storage) end
    local donor,target=F.milkInfo(item),object and F.milkInfo(object)
    local loss=donor and pour.source-donor.amount
    local gain=target and target.amount-pour.target
    if not donor or not target or donor.amount>0.0001 and donor.fluid~=receipt.milk.fluid
        or target.amount>0.0001 and target.fluid~=receipt.milk.fluid
        or loss< -0.005 or gain< -0.005 or math.abs(loss-gain)>0.005 then
        receipt.milk.uncertain=true updateReceipt(receipt)
        return false,"animal_milk_uncertain"
    end
    receipt.milk.poured=(receipt.milk.poured or 0)+math.max(0,gain)
    receipt.milk.after=donor.amount
    receipt.milk.pour=nil
    return updateReceipt(receipt)
end

function F.cancelPour(actor,job,state,reason)
    local work=state.milkPour
    if not work then F.release(actor,job) return true end
    if SC.NativeActions.workKind(actor)=="farm_milk_store" then
        local stopped,why=SC.NativeActions.cancelWork(actor,reason or "milk_delivery_cancelled")
        if stopped~=true then return false,why end
    end
    if work.token and SC.ActionSupervisor.isCurrent(work.token) then SC.ActionSupervisor.cancel(actor,reason) end
    local receipt=SC.BaseLife.farmReceipt(work.receiptId)
    if receipt and receipt.milk then receipt.milk.pour=nil updateReceipt(receipt) end
    state.milkPour=nil F.release(actor,job)
    return true
end

-- nil means the ordinary filled-container food-storage fallback should run.
function F.deliverMilk(actor,baseState,job,state,output)
    local receipt=output and SC.BaseLife.farmReceipt(output.receiptId)
    if not state.milkPour and #SC.BaseLife.depositStorageRows("milk")==0
        and not (receipt and receipt.milk and (receipt.milk.pour
            or (receipt.milk.poured or 0)>0 and receipt.milk.after<=0.0001)) then return nil end
    if not receipt or not receipt.milk then return false,"animal_milk_receipt_missing",true end
    if receipt.milk.uncertain then return false,"animal_milk_uncertain",true end
    local item=output.item
    local donor=F.milkInfo(item)
    if not donor then return false,"animal_milk_container_missing",true end
    if donor.amount>0.0001 and donor.fluid~=receipt.milk.fluid then return false,"animal_milk_uncertain",true end
    if receipt.milk.pour and not state.milkPour then
        local okay,why=F.resumePour(receipt,item)
        if not okay then return false,why,true end
    end
    local work=state.milkPour
    if work then
        if F.claim(work.storage,actor,job)~=true then return false,"animal_milk_storage_reserved",true end
        if SC.NativeActions.isWorkActive(actor) then
            if now()-work.startedAt<120000 and not S().threat(actor) then
                SC.ActionSupervisor.progress(work.token,"milk-pour:"..tostring(donor.amount))
                return true,"animal_milk_pouring"
            end
            local stopped,why=SC.NativeActions.cancelWork(actor,"milk_delivery_interrupted")
            if stopped~=true then return true,why end
        end
        local released,why=SC.NativeActions.finishWork(actor)
        if released~=true then return true,why end
        if SC.ActionSupervisor.isCurrent(work.token) then SC.ActionSupervisor.complete(work.token) end
        if not work.observed then
            state.milkExcluded=state.milkExcluded or {} state.milkExcluded[work.storage.id]=true
        end
        receipt.milk.pour=nil updateReceipt(receipt)
        state.milkPour=nil F.release(actor,job)
        donor=F.milkInfo(item)
        if not donor or work.uncertain then return false,"animal_milk_uncertain",true end
    end
    if donor.amount<=0.0001 and (receipt.milk.poured or 0)>0 then
        local source=SC.BaseLife.storage(receipt.sourceStorageId)
        local container=source and SC.BaseLife.resolveContainer(source)
        if not source or not container then return false,"animal_milk_container_return_pending",true end
        table.remove(state.outputs,1)
        if #state.outputs==0 then state.outputs=nil end
        state.borrowed={item=item,receiptId=receipt.id,storage=source,container=container}
        SC.BaseLife.updateFarmReceipt(receipt.id,{phase="borrowed",blocker=false})
        return true,"animal_milk_stored"
    end
    if not donor.fluid then return false,"animal_milk_uncertain",true end
    -- Native completion includes a short human pause. Asking navigation during
    -- that pause rejects every standing tile and can blacklist a usable barrel.
    if SC.NativeActions and SC.NativeActions.pacingStatus and SC.NativeActions.pacingStatus(actor) then
        return true,"animal_milk_seeking_storage"
    end
    local storage,object,target=F.milkDestination(actor,item,job,state.milkExcluded)
    if not storage then return nil end
    if not F.claim(storage,actor,job) then return true,"animal_milk_storage_reserved" end
    local approach=state.milkApproach
    local distance=U().distance(actor,object)
    if not approach or approach.id~=storage.id then
        approach={id=storage.id,at=now(),progressAt=now(),best=distance} state.milkApproach=approach
    elseif distance<approach.best-0.25 then approach.best,approach.progressAt=distance,now() end
    if now()-approach.progressAt>15000 or now()-approach.at>45000 then
        state.milkExcluded=state.milkExcluded or {} state.milkExcluded[storage.id]=true
        state.milkApproach=nil F.release(actor,job)
        if SC.Navigation then SC.Navigation.cancel(actor,"milk_storage_route_blocked") end
        return true,"animal_milk_seeking_storage"
    end
    local phase,why=S().approach(actor,U().squareOf(object),object,true)
    if phase=="failed" then
        state.milkExcluded=state.milkExcluded or {} state.milkExcluded[storage.id]=true
        F.release(actor,job) return true,"animal_milk_seeking_storage"
    end
    if phase~="arrived" then return true,why end
    state.milkApproach=nil
    local token,reason=SC.ActionSupervisor.begin(actor,{owner="work",action="farm_milk_store",
        targetKey=job.id,targetLabel="milk barrel",priority=SC.ActionSupervisor.Priority.WORK,
        ignoreRetry=true,interruptible=true})
    if not token then return false,reason end
    if SC.Navigation then SC.Navigation.cancel(actor,"milk_storage_interaction") end
    local stopped,stopReason=SC.NativeActions.stopDirect(actor)
    if not stopped then SC.ActionSupervisor.fail(token,stopReason) return false,stopReason end
    work={storage=storage,object=object,receiptId=receipt.id,token=token,startedAt=now()}
    state.milkPour=work
    receipt.milk.pour={storageId=storage.id,source=donor.amount,target=target.amount}
    if not updateReceipt(receipt) then return false,"animal_milk_uncertain",true end
    local function valid()
        local held=claims[storage.id]
        local fc,current=SC.BaseLife.resolveFluidContainer(storage)
        local a,b=F.milkInfo(item),F.milkInfo(object)
        local valid=held and held.actor==actor and held.job==job.id and held.untilMs>now()
            and SC.BaseLife.job(job.id)==job and job.reservedBy==U().idOf(actor)
            and not U().isDead(actor) and not S().threat(actor)
            and SC.BaseLife.storage(storage.id)==storage and storage.deposits~=false
            and current==object and fc~=nil and a and b and a.fluid==receipt.milk.fluid
            and (b.amount<=0.0001 or b.fluid==a.fluid)
            and value(item,"getContainer")==U().inventory(actor)
            and U().directInteractionAccess(actor,object,{cardinalOnly=false})==true
            and U().sameFloor(actor,object) and U().distance(actor,object)<=2.5
        work.validation=valid and "valid" or ("guard:job="..tostring(SC.BaseLife.job(job.id)==job)
            .." owner="..tostring(job.reservedBy==U().idOf(actor))
            .." access="..tostring(U().directInteractionAccess(actor,object,{cardinalOnly=false}))
            .." source="..tostring(a and a.fluid).." target="..tostring(b and b.fluid))
        return valid
    end
    local accepted,detail=SC.NativeActions.startFarmFluidDeposit(actor,item,object,
        math.min(donor.amount,target.capacity-target.amount),job.id,valid,function(a,b)
            local before=receipt.milk.poured or 0
            local okay=F.observePour(receipt,item,object,a,b)
            work.observed=work.observed or (receipt.milk.poured or 0)>before+0.000001
            work.uncertain=not okay
            if not okay then receipt.milk.uncertain=true updateReceipt(receipt) end
            return okay
        end)
    if not accepted then
        F.cancelPour(actor,job,state,detail)
        SC.ActionSupervisor.fail(token,detail)
        return false,detail,true
    end
    SC.ActionSupervisor.transition(token,"animating")
    return true,"animal_milk_pouring"
end

return F
