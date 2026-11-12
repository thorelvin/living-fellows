-- SPDX-License-Identifier: MIT
local SC,f=SurvivorCompanion,SurvivorCompanion.TestFixture
local F,M,K,U=SC.FarmStorage,SC.ManureWork,SC.MedicKit,SC.GameplayUtil
local checks=0
local function check(ok,why) checks=checks+1 assert(ok,"farm care "..checks..": "..why) end
local function fluid(kind,amount,capacity)
    local fc={kind=kind,amount=amount,capacity=capacity}
    function fc:getAmount() return self.amount end
    function fc:getCapacity() return self.capacity end
    function fc:isPureFluid(which) return self.amount>0 and self.kind==which end
    function fc:canAddFluid() return not self.locked end
    function fc:isInputLocked() return self.locked==true end
    function fc:isOutputLocked() return false end
    return fc
end
Fluid=Fluid or {} Fluid.CowMilk="CowMilk" Fluid.SheepMilk="SheepMilk"
local a,b=f.actor("farm-care-a",2,2,{}),f.actor("farm-care-b",2,2,{})
local barrel={fc=fluid(nil,0,5)}
function barrel:getFluidContainer() return self.fc end
local row={id="storage:milk",category="milk",deposits=true}
local rows={milk={row},manure={}}
local records={[row.id]=row}
local receipts={}
local base={id="camp:care",jobs={}}
SC.BaseLife={active=function() return base end,isInside=function() return true end,
    withinWorkReach=function() return true end,
    depositStorageRows=function(category) return rows[category] or {} end,
    storageRows=function(category) return rows[category] or {} end,
    storage=function(id) return records[id] end,
    resolveFluidContainer=function(storage) return storage==row and barrel.fc or nil,barrel end,
    resolveContainer=function(storage) return storage.container,storage.object end,
    storageAcceptsDeposit=function(storage) return storage.deposits~=false end,
    updateFarmReceipt=function(id,fields)
        local r=receipts[id] if not r then return false end
        for k,value in pairs(fields) do r[k]=value end return true,r
    end,
    farmReceipt=function(id) return receipts[id] end,
    noteWorkOwnershipMutation=function() end,
    resident=function(id) return {role=id=="farm-care-a" and "medic" or "generalist"} end}
SC.PersonalItems={isProtected=function(item) return item.protected==true end}
local bucket=f.item("Base.Bucket","Item",{fluidContainer=fluid(Fluid.CowMilk,2,3)})
check(F.canMarkMilk(barrel),"an empty native-compatible fluid barrel can be marked")
barrel.fc.kind="Water" barrel.fc.amount=1
check(not F.canMarkMilk(barrel) and not F.milkDestination(a,bucket),"water is never discarded or mixed into milk")
barrel.fc.kind=Fluid.SheepMilk
check(not F.milkDestination(a,bucket),"cow and sheep milk stay separate")
barrel.fc.kind=Fluid.CowMilk
check(F.milkDestination(a,bucket)==row,"same-milk native destination is eligible")
barrel.fc.amount=5
check(not F.milkDestination(a,bucket),"a full fluid barrel is not a destination")
barrel.fc.amount=1 row.deposits=false
check(not F.milkDestination(a,bucket),"deposit permissions apply to fluids")
row.deposits=true
check(F.claim(row,a,{id="job:1"}) and not F.claim(row,b,{id="job:2"}),"workers cannot share a reserved milk destination")
check(not F.milkDestination(b,bucket),"destination selection respects the other worker")
F.release(a,{id="job:1"})
check(F.milkDestination(b,bucket)==row,"released destination becomes available")
local r={id="farm-receipt:1",milk={fluid="CowMilk",after=2,litres=2,pour={storageId=row.id,source=2,target=1}}}
receipts[r.id]=r
bucket.fluidContainer.amount=1.6 barrel.fc.amount=1.4
check(F.observePour(r,bucket,barrel,2,1) and math.abs(r.milk.poured-0.4)<0.00001,"only paired native deltas count as stored")
check(F.resumePour(r,bucket) and not r.milk.pour,"matching saved quantities reconcile without replay")
r.milk.pour={storageId=row.id,source=1.6,target=1.4}
bucket.fluidContainer.amount=1.4 barrel.fc.amount=1.6
check(F.resumePour(r,bucket) and math.abs(r.milk.poured-0.6)<0.00001,
    "reload accounts for a verified native increment after its last checkpoint exactly once")
r.milk.pour={storageId=row.id,source=1.4,target=1.6}
barrel.fc.kind=Fluid.SheepMilk
check(not F.resumePour(r,bucket) and r.milk.uncertain,
    "matching volumes with changed milk type cannot settle a saved pour")
barrel.fc.kind=Fluid.CowMilk r.milk.uncertain=false
bucket.fluidContainer.amount=1.6 barrel.fc.amount=1.4
r.milk.pour={storageId=row.id,source=1.6,target=1.4}
barrel.fc.amount=2
check(not F.resumePour(r,bucket) and r.milk.uncertain,"changed destination evidence quarantines an ambiguous pour")
check(bucket.fluidContainer.amount==1.6 and barrel.fc.amount==2,"reconciliation never manufactures or rolls back fluid")
barrel.fc.amount=1
function barrel:getX() return 2 end
function barrel:getY() return 1 end
function barrel:getZ() return 0 end
r.milk.uncertain=false r.milk.pour=nil
local approach=SC.FarmWork.animalSupport.approach
SC.FarmWork.animalSupport.approach=function() return "pending","path_searching" end
local delivery={}
local priorNative=SC.NativeActions
SC.NativeActions={pacingStatus=function() return true end}
check(F.deliverMilk(a,{}, {id="job:route"},delivery,{item=bucket,receiptId=r.id})==true
    and delivery.milkApproach==nil and delivery.milkExcluded==nil,
    "native pacing cannot blacklist a reachable milk destination")
SC.NativeActions=priorNative
check(F.deliverMilk(a,{}, {id="job:route"},delivery,{item=bucket,receiptId=r.id})==true,"milk approaches use the ordinary navigation lane")
f.clock=f.clock+16001
local moved,why=F.deliverMilk(a,{}, {id="job:route"},delivery,{item=bucket,receiptId=r.id})
check(moved and why=="animal_milk_seeking_storage" and delivery.milkExcluded[row.id],
    "a non-progressing approach is bounded and excluded before fallback")
check(bucket.fluidContainer.amount==1.6 and F.milkDestination(b,bucket)==row,"blocked approaches preserve cargo and release destination claims")
SC.FarmWork.animalSupport.approach=approach

local dung=f.item("Base.Dung_Cow","Food",{weight=1})
check(F.isManure(dung) and SC.Logistics.itemCategory(dung)=="manure"
    and SC.BaseWork.classifyItem(dung)=="manure","dung never follows food heuristics")
local world={{getItem=function() return dung end}}
local square={getWorldObjects=function() return world end,checkHaveDung=function() return true end}
local items,weight=M.items(square)
check(items and #items==1 and weight>0,"the whole native pickup footprint is inspected")
for i=2,65 do world[i]={getItem=function() return dung end} end
check(M.items(square)==nil,"oversized tile evidence is refused before collection")
local compost={id="storage:compost",category="manure",deposits=true,container=f.inventory({}),
    object={getCompost=function() return 100 end,getContainer=function() return {getType=function() return "composter" end} end}}
local overflow={id="storage:overflow",category="manure",deposits=true,container=f.inventory({}),object={}}
records[compost.id],records[overflow.id]=compost,overflow rows.manure={overflow,compost}
local room=SC.WorkTransport.hasRoom
SC.WorkTransport.hasRoom=function() return true end
check(F.manureRows(dung,a)[1]==overflow,"100-percent composter uses overflow")
compost.object.getCompost=function() return 20 end
check(F.manureRows(dung,a)[1]==compost,"processing composter precedes crate regardless of registration order")
check(#F.manureRows(dung,a,true)==1,"overflow recovery can target composters only")
SC.WorkTransport.hasRoom=room

local kit=f.item("Base.FirstAidKit_NewPro","Container",{})
local inventory=f.inventory({})
function kit:getInventory() return inventory end
function inventory:getContainingItem() return kit end
a.inventory:AddItem(kit)
local bandage=f.item("Base.Bandage","Item",{})
inventory:AddItem(bandage)
local splint=f.item("Base.Splint","Item",{})
a.inventory:AddItem(splint)
local audit={inventoryComplete=true,items={{item=kit,source=a.inventory},{item=bandage,source=inventory},{item=splint,source=a.inventory}}}
local facts=K.view(a,audit)
check(facts.kit==kit and facts.dressings==1 and facts.kitDressings==1 and facts.splints==1,
    "kit shell and nested treatment supplies have distinct counts")
check(SC.Logistics.itemCategory(kit)=="container" and SC.Logistics.itemCategory(splint)=="medicine",
    "an empty kit is not medicine; a usable splint is")
check(K.retained(a,kit) and K.retained(a,bandage,inventory),"packing retains the kit and its existing contents")
check(not SC.PersonalItems.isProtected(bandage,a,"medical_consume"),"packing retention does not forbid medical consumption")
check(K.needsWork(a,audit),"a medic with too few dressings requests replenishment")
bandage.protected=true
check(K.view(a,audit).dressings==0,"protected dressings cannot satisfy usable medical stock")
bandage.protected=false
local modded=f.item("Other.FieldMedicalCase","Container",{})
function modded:getInventory() return inventory end
function modded:getScriptItem() return {medical=true} end
check(K.isKit(modded),"medical-container metadata supports compatible modded kits")
check(not K.retained(b,bandage,inventory),"another actor's generalist role gains no kit packing protection")
check(K.owns(a,kit) and not K.owns(b,kit),"packing verifies actual kit ownership independently of role")
check(U.transferItemVerified(a.inventory,b.inventory,kit),"move the exact borrowed kit to its carrier")
kit:getModData().LF_MedicKitLoan={actorId=U.idOf(b),storageId="storage:medical"}
check(K.retained(b,kit) and K.retained(b,bandage,inventory),"a borrowed kit and its contents stay together after a role change")
print("FARM_STORAGE_MEDIC_PASS checks="..checks)
