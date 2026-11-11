-- SPDX-License-Identifier: MIT
local SC,F=SurvivorCompanion,FarmLifecycleFixture
local A,W,U=SC.AnimalWork,SC.AnimalShearing,SC.GameplayUtil
local checks=0
local function check(okay,text) checks=checks+1 assert(okay,"sheep: "..text) end
local old=U.config
U.config=function(name)
    if name=="animalSheepEnabled" or name=="animalSheepMilkEnabled" or name=="animalMilkEnabled"
        or name=="animalShearEnabled" then return 1 end
    return old(name)
end
local data={wool=16,milk=9,capacity=10}
function data:getWoolQuantity() return self.wool end
function data:getMaxWool() return 20 end
function data:getAttachedPlayer() return nil end
function data:getAttachedTree() return nil end
function data:isFemale() return true end
function data:canHaveMilk() return true end
function data:getMilkQuantity() return self.milk end
function data:getMaxMilkActual() return self.capacity end
function data:getMaxMilk() return 10 end
local ewe={x=4,y=4,z=0,stress=0,kind="ewe",marks={}}
function ewe:getData() return data end
function ewe:getAnimalID() return 202 end
function ewe:getAnimalType() return self.kind end
function ewe:isBaby() return self.kind=="lamb" end
function ewe:getHealth() return 1 end
function ewe:getAge() return self.age or 500 end
function ewe:isHeld() return false end
function ewe:getModData() return self.marks end
function ewe:getStress() return self.stress end
function ewe:canBeSheared() return true end
function ewe:getMilkType() return "SheepMilk" end
function ewe:getBabies() return {} end
getGameTime=function() return {getTimeOfDay=function() return F.hour end,getWorldAgeHours=function() return 100 end} end
F.hour=12
check(A.speciesFor("ewe")=="sheep" and A.speciesFor("ram")=="sheep" and A.speciesFor("lamb")=="sheep","all sheep kinds recognized")
check(W.facts(ewe,false)~=nil,"native mature fleece at eighty percent is eligible")
ewe.age=180 check(W.facts(ewe,false)==nil,"native pre-200-day sheep cannot debit wool safely") ewe.age=500
data.wool=15.9 check(W.facts(ewe,false)==nil and W.facts(ewe,true)~=nil,"continuing job can finish a partial fleece")
data.wool=.9 local _,why=W.facts(ewe,true) check(why=="animal_shear_finished","sub-unit fleece cannot produce another item")
data.wool=16 ewe.kind="lamb" check(W.facts(ewe,false)==nil,"lambs excluded")
ewe.kind="ram" check(W.facts(ewe,false)~=nil,"adult rams can be sheared")
ewe.stress=41 check(W.facts(ewe,false)==nil,"stressed sheep skipped") ewe.stress=0
ewe.marks.lfOddballGroupId="protected" check(W.facts(ewe,false)==nil,"Strange Folk animals protected") ewe.marks={}
F.hour=22 check(W.facts(ewe,false)==nil,"shearing waits for daylight") F.hour=12 ewe.kind="ewe"
local row={id="42",sheep={animals={{id=203,baby=true,motherId=202}}}}
local facts=A.milkFacts(ewe,row)
check(facts and facts.fluid=="SheepMilk" and facts.species=="sheep" and facts.reserve==4,"ewe milk retains exact lamb reserve and fluid")
row.sheep.animals[1].motherId=999
check(A.milkFacts(ewe,row).reserve==0,"unrelated lamb does not consume this ewe's reserve")
row.sheep.animals[1].motherId=nil
check(A.milkFacts(ewe,row).reserve==4,"unknown mother identity conservatively protects lambs")
local plan=A.milkPlan(ewe,row,{})
check(plan and plan.urgent,"ewe shares native urgent milk lane")
data.milk=6.9 check(A.milkPlan(ewe,row,{})==nil,"nursing ewe waits for seventy percent") data.milk=9
check(A.milkPlan(ewe,row,{milked={["202"]={day=4,jobId="job:old"}}})==nil,"ewe daily limit preserved")
local manual=F.item("Base.SheepShears",1,{tags={SHEAR=true}})
check(W.tool(manual),"manual shears accepted by native tag")
local electric=F.item("Base.SheepElectricShears",2,{tags={SHEAR=true}})
function electric:IsDrainable() return true end
function electric:getCurrentUsesFloat() return self.charge or 0 end
check(not W.tool(electric),"depleted shears refused") electric.charge=.1 check(W.tool(electric),"charged electric shears accepted")
function manual:isBroken() return true end
check(not W.tool(manual),"broken manual shears refused")
check(SC.Logistics.itemCategory(F.item("Base.WoolRaw",3))=="crafting","wool sorts to crafting, not farming feed")
F.reset() A.reset()
local actor=F.actor("shepherd",4,4)
function actor.inventory:getCapacityWeight() return 0 end
function actor.inventory:getEffectiveCapacity() return 20 end
local square=F.square(4,4)
ewe.square=square
square.worlds={}
function square:getWorldObjects() return self.worlds end
function ewe:getSquare() return square end
ewe.kind,ewe.age,ewe.stress,ewe.marks="ewe",500,0,{}
data.wool=16
manual=F.item("Base.SheepShears",10,{tags={SHEAR=true}})
actor.inventory:AddItem(manual)
local job=F.job("animal_shear",4,4,{animal=true,animalId=202,deviceKey="animal:202",nativeZoneId="42",actorId=actor.id})
local state={personalShears=manual}
local oldStorage=SC.BaseLife.storage
SC.BaseLife.storage=function(id)
    for _,row in ipairs(F.storages) do if row.id==id then return row end end
end
local storage=F.addStorage("storage:wool","crafting",{})
local container=F.storageContainers[storage.id]
container.capacity=20
function container:getCapacityWeight() return 0 end
function container:getEffectiveCapacity() return self.capacity end
local projected,scriptManager=U.projectedCarryLoad,ScriptManager
local loadLimit=20
U.projectedCarryLoad=function() return 0,loadLimit end
ScriptManager={instance={getItem=function() return {getActualWeight=function() return .2 end} end}}
local function raw(id)
    local item=F.item("Base.WoolRaw",id)
    local world={getItem=function() return item end,getSquare=function() return square end}
    function item:getWorldItem() return world end
    square.worlds[#square.worlds+1]=world
    return item
end
local oldWool=raw(500)
local proof=W.beforeIncrement(actor,job,state,ewe)
check(proof~=nil,"bounded shearing snapshot admits an owned usable tool and storage")
local wool=raw(501) data.wool=15
check(W.afterIncrement(actor,job,state,ewe,proof),"one native fleece unit binds one new actual floor item")
check(job.target.woolCollected==1 and #F.receipts==1
    and wool.modData[SC.FarmWork.ITEM_MARKER]==F.receipts[1].id
    and not oldWool.modData[SC.FarmWork.ITEM_MARKER],"pre-existing wool is never adopted")
check(not W.afterIncrement(actor,job,state,ewe,proof) and #F.receipts==1,
    "repeated completion cannot allocate a second receipt for the same native drop")
proof=W.beforeIncrement(actor,job,state,ewe)
raw(502) raw(503) data.wool=14
check(not W.afterIncrement(actor,job,state,ewe,proof) and #F.receipts==1 and #square.worlds==4,
    "ambiguous native outputs stop without deleting or recreating cargo")
container.capacity=0
local p,reason=W.beforeIncrement(actor,job,state,ewe)
check(not p and reason=="animal_wool_storage_missing","full storage stops the next native debit")
container.capacity=20 loadLimit=.1
p,reason=W.beforeIncrement(actor,job,state,ewe)
check(not p and reason=="animal_shear_load_full","pending floor cargo reserves safe carrying space")
loadLimit=20
container.capacity=.2
F.receipts[1].jobId="job:other-shepherd"
p,reason=W.beforeIncrement(actor,job,state,ewe)
check(not p and reason=="animal_wool_storage_missing","another Farmer's reserved wool cannot spend the same storage slot")
F.receipts[1].jobId=job.id container.capacity=20
local general=F.addStorage("storage:wool-general","general",{})
local rows=W.depositRows()
check(rows[1].id==storage.id and rows[2].id==general.id,"wool uses actual Crafting then General categories")
for i=1,33 do raw(600+i) end
p,reason=W.beforeIncrement(actor,job,state,ewe)
check(not p and reason=="animal_shear_floor_unavailable","crowded floor yields instead of sweeping unbounded items")
check(A.shearingSupport.claim(actor,job),"first sheep worker acquires shared animal claim")
local second=F.actor("other-shepherd",4,4)
local secondJob=F.job("animal_milk",4,4,{cowId=202,deviceKey="animal:202",nativeZoneId="42",actorId=second.id})
check(not A.shearingSupport.claim(second,secondJob),"another Farmer cannot milk an actively claimed shearing sheep")
A.shearingSupport.release(actor,job)
check(A.shearingSupport.claim(second,secondJob),"releasing owned claim permits the next worker")
for i=#square.worlds,5,-1 do table.remove(square.worlds,i) end
local receipt=F.receipts[1]
check(W.retainAfterCarrierLoss(receipt),"death of the shearer cannot consume wool still on the pasture floor")
local progress=W.progress(job)
check(progress.collected==1 and progress.carried==0 and progress.stored==0,"created floor wool is not reported as delivered")
receipt.phase="carried"
check(W.progress(job).carried==1,"carried wool has a separate visible count")
receipt.phase="selected"
check(W.recoverReceipt(receipt) and receipt.phase=="selected","live job keeps its exact floor reservation after reload")
job.target.shearCancelled=true
check(W.recoverReceipt(receipt) and receipt.phase=="returned"
    and not SC.FarmWork.isItemProtected(wool),"cancellation releases proven floor wool for ordinary camp sorting")
receipt.phase="selected" wool.modData[SC.FarmWork.ITEM_MARKER]=receipt.id
table.remove(square.worlds,2)
check(not W.retainAfterCarrierLoss(receipt),"proven missing floor output may settle with its lost carrier without replacement")
check(not W.recoverReceipt(receipt) and receipt.phase=="selected" and #square.worlds==3,
    "ambiguous missing cargo is never manufactured during recovery")
receipt.phase="delivered"
check(W.progress(job).stored==1 and W.progress(job).carried==0,"only a verified delivered receipt contributes to stored wool")
local source=F.addStorage("storage:shears-source","farming",{})
local okay,loan=SC.BaseLife.allocateFarmReceipt({jobId=job.id,actorId=actor.id,kind="borrowed",
    itemType=manual.fullType,nativeId=tostring(manual:getID()),sourceStorageId=source.id,phase="borrowed"})
check(okay,"borrowed shears have their own exact receipt")
manual.modData[SC.FarmWork.ITEM_MARKER]=loan.id
state.personalShears=nil state.borrowed={item=manual,receiptId=loan.id,storage=source,container=F.storageContainers[source.id]}
local returnNormally=SC.BaseWork.returnToStorage
SC.BaseWork.returnToStorage=function(_,baseState) assert(baseState,"normal return needs a live BaseWork state") end
check(W.cancel(actor,job,state,"farm_job_cancelled") and manual:getContainer()==F.storageContainers[source.id]
    and loan.phase=="returned" and not state.borrowed,"cancel uses exact cancellation return, without a missing normal-work state")
SC.BaseWork.returnToStorage=returnNormally SC.BaseLife.storage=oldStorage
A.reset() U.projectedCarryLoad=projected ScriptManager=scriptManager
U.config=old
print("SHEEP_WORK_PASS checks="..checks)
