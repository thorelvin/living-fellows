-- SPDX-License-Identifier: MIT
-- Exercise the real save normalizer before the native-shaped farm fixture.
local SC=SurvivorCompanion
local B=SC.BaseLife
local function check(okay,message) assert(okay,"milk persistence: "..message) end
B.reset()
check(B.create({x=10,y=10,z=0},"Milk receipts"),"camp fixture creates")
local f=SC.TestFixture
local _,owner=f.containerObject(f.makeSquare(10,10,0),{})
function owner:getObjectIndex() return 0 end
local storageOkay,storage=B.registerStorage(owner,"farming")
check(storageOkay,"real source storage registers")
local okay,receipt=B.allocateFarmReceipt({jobId="job:1",actorId="farmer",kind="borrowed",
    itemType="Base.Bucket",nativeId="101",sourceStorageId=storage.id,
    milk={version=1,cowId=42,zoneId="10",day=4,fluid="CowMilk",before=0,after=1.7,litres=1.7,lost=0,
        urgent=true,staged=true,destinationStorageId=storage.id}})
check(okay,"exact borrowed milk receipt allocates")
check(SC.FarmWork.pendingMilkInventory("farmer") and not SC.FarmWork.pendingMilkInventory("another-farmer"),
    "only the outstanding milk receipt owner requests exact native-ID inventory persistence")
check(not B.updateFarmReceipt(receipt.id,{phase="delivered",milk={version=99}})
    and receipt.phase=="borrowed","invalid milk metadata cannot partially settle a receipt")
check(B.updateFarmReceipt(receipt.id,{kind="output",phase="carried",destinationCategory="fresh_food"}),
    "milk loan changes purpose without changing its identity")
local saved=B.export()
check(B.restore(saved),"real farm document reloads")
check(SC.FarmWork.pendingMilkInventory("farmer"),"reload retains the exact-inventory requirement until delivery")
check(B.updateFarmReceipt(receipt.id,{phase="delivered"}) and not SC.FarmWork.pendingMilkInventory("farmer"),
    "verified delivery returns the actor to ordinary inventory persistence")
B.updateFarmReceipt(receipt.id,{phase="carried"})
local restored=B.farmReceipt(receipt.id)
check(restored.nativeId=="101" and restored.sourceStorageId==storage.id
    and restored.kind=="output" and restored.milk.cowId==42 and restored.milk.after==1.7
    and restored.milk.litres==1.7 and restored.milk.day==4 and restored.milk.urgent
    and restored.milk.staged and restored.milk.destinationStorageId==storage.id,
    "reload retains owner, source, destination, staging and measured volumes")
B.animalDocument().zones["10"]={milked={["42"]={day=4,jobId="job:1"}}}
check(B.restore(B.export()) and B.animalDocument().zones["10"].milked["42"].day==4,
    "daily evidence survives in the existing animal schema")
B.animalDocument().zones["10"].milked={}
SC.AnimalWork.recoverReceipt(B.farmReceipt(receipt.id))
check(B.animalDocument().zones["10"].milked["42"].day==4,
    "a verified partial-load receipt rebuilds missing daily evidence without replaying milk")
local malformed=B.export()
malformed.bases[malformed.activeBaseId].farm.receipts[1].milk.version=99
check(B.restore(malformed) and B.farmReceipt(receipt.id).milkInvalid
    and B.farmReceipt(receipt.id).phase=="quarantined","unknown milk evidence preserves the save and fails closed")
B.reset() B.create({x=10,y=10,z=0},"Urgent welfare")
local worker=f.actor("milk-farmer",10,10)
worker.modData.SC_Order="base_duty"
f.registry["milk-farmer"]={id="milk-farmer",actor=worker,recruited=true}
B.assign("milk-farmer","farmer",true)
local oldConfig=SC.GameplayUtil.config
SC.GameplayUtil.config=function(name)
    if name=="animalCattleEnabled" or name=="animalMilkEnabled" then return 1 end
    return oldConfig(name)
end
B.enqueueJob({type="farm",priority=5,target={animal=true,cattle=true,operation="animal_water",x=10,y=10,z=0}})
local queued,milkJob=B.enqueueJob({type="farm",priority=6,target={animal=true,cattle=true,
    operation="animal_milk",urgent=true,cowId=42,nativeZoneId="10",x=11,y=10,z=0}})
check(queued and milkJob.priority==5,"milking respects the existing job priority range")
check(B.priorityWorkFor("milk-farmer")==milkJob,"unassigned urgent milking interrupts optional camp activity")
check(B.claimJob("milk-farmer")==milkJob,"urgent milking scores above the nearer water job")
B.releaseJob(milkJob.id,"milk-farmer","fixture")
B.cancelJob(milkJob.id)
local _,nextMilk=B.enqueueJob({type="farm",priority=5,target={animal=true,cattle=true,
    operation="animal_milk",urgent=true,cowId=43,nativeZoneId="10",x=11,y=10,z=0}})
local S=SC.ActionSupervisor
local token=S.begin(worker,{owner="downtime",action="gear_check",priority=10,
    interruptible=true,metadata={commandSerial=0}})
local peek,cancel,update,work=SC.Downtime.peek,SC.Downtime.cancel,SC.Downtime.update,SC.FarmWork.update
SC.Downtime.peek=function() return {active={kind="gear_check"}} end
SC.Downtime.cancel=function() S.complete(token,"released") return true end
SC.Downtime.update=function() return true,"optional_activity" end
SC.FarmWork.update=function() return true,"milk_work" end
local decision={}
check(B.priorityWorkFor("milk-farmer")==nextMilk and SC.AnimalWork.urgentMilkJob(nextMilk),
    "fresh urgent work remains eligible: priority="..tostring(B.priorityWorkFor("milk-farmer") and B.priorityWorkFor("milk-farmer").id)
        .." milk="..tostring(SC.AnimalWork.urgentMilkJob(nextMilk)))
SC.Decision._holdOwnedActivityOrPacingForTests(worker,f.player,
    {threatCount=0,immediateCount=0,threats={}},{health=100,alive=true,bleedingCount=0},{},
    {order="base_duty",recruited=true,commandSerial=0},decision,f.clock+2000,{})
SC.Decision._holdOwnedActivityOrPacingForTests(worker,f.player,
    {threatCount=0,immediateCount=0,threats={}},{health=100,alive=true,bleedingCount=0},{},
    {order="base_duty",recruited=true,commandSerial=0},decision,f.clock+3001,{})
check(B.jobFor("milk-farmer")==nextMilk and decision.current=="base_work" and S.current(worker)==nil,
    "urgent milk releases optional activity: job="..tostring(B.jobFor("milk-farmer") and B.jobFor("milk-farmer").id)
        .." expected="..nextMilk.id.." decision="..tostring(decision.current).." intent="..tostring(decision.intent)
        .." owner="..tostring(S.current(worker) and S.current(worker).owner))
SC.Downtime.peek,SC.Downtime.cancel,SC.Downtime.update,SC.FarmWork.update=peek,cancel,update,work
local cowMilk=Fluid.CowMilk
Fluid.CowMilk={name="CowMilk"}
local milkBottle=f.item("Base.WaterBottle","Drainable")
local milkFluid={amount=2}
function milkFluid:getAmount() return self.amount end
function milkFluid:isPureFluid(kind) return self.amount>0 and kind==Fluid.CowMilk end
function milkBottle:getFluidContainer() return milkFluid end
check(SC.Logistics.itemCategory(milkBottle)=="food" and B.foodStorageCategory(milkBottle)=="fresh_food",
    "native numeric fluid readings classify a milk-filled water bottle as fresh food without tonumber varargs")
milkFluid.amount=0
check(SC.Logistics.itemCategory(milkBottle)~="food","an emptied milk bottle loses its food classification")
Fluid.CowMilk=cowMilk
SC.GameplayUtil.config=oldConfig
print("CATTLE_RECEIPT_PASS")
