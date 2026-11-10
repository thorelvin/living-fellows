-- SPDX-License-Identifier: MIT
local SC,F=SurvivorCompanion,FarmLifecycleFixture
local A,U=SC.AnimalWork,SC.GameplayUtil
local checks,oldConfig=0,U.config
local cattleEnabled=1
local function check(okay,message) checks=checks+1 assert(okay,"cattle: "..message) end
U.config=function(name)
    if name=="animalCattleEnabled" then return cattleEnabled end
    if name=="animalCloseEnabled" then return 1 end
    return oldConfig(name)
end
ArrayList={new=function()
    local list={rows={}}
    function list:addAll(values) for _,item in ipairs(values) do self.rows[#self.rows+1]=item end end
    function list:size() return #self.rows end
    function list:get(index) return self.rows[index+1] end
    return list
end}
getGameTime=function() return {getWorldAgeHours=function() return 100 end,
    getTimeOfDay=function() return F.hour end} end
local function animal(id,kind,baby,female)
    return {x=4,y=4,z=0,stress=0,getAnimalID=function() return id end,getAnimalType=function() return kind end,
        getModData=function() return {} end,getHealth=function() return 1 end,
        isBaby=function() return baby==true end,getCustomName=function() return "" end,
        isHeld=function() return false end,getAge=function() return baby and 10 or 500 end,
        getData=function() return {isFemale=function() return female==true end} end,
        getStress=function(self) return self.stress end,isAnimalAttacking=function(self) return self.attacking==true end,
        canBePutInHutch=function() return kind=="hen" end}
end
local function fresh(animals,width,height)
    SC.FarmWork.reset() F.reset() SC.Performance=nil
    F.base.zones[1].x2,F.base.zones[1].y2=40,40
    F.base.farm.animals={version=1,zones={}}
    SC.BaseLife.animalDocument=function() return F.base.farm.animals end
    local zone={animals=animals,w=width or 2,h=height or 1,hutches={},troughs={}}
    function zone:getId() return 42 end
    function zone:getX() return 2 end function zone:getY() return 2 end function zone:getZ() return 0 end
    function zone:getW() return self.w end function zone:getH() return self.h end
    function zone:getFullZoneSize() return self.w*self.h end
    function zone:isFullyStreamed() return true end
    function zone:getHutchs() return self.hutches end function zone:getTroughs() return self.troughs end
    function zone:getAnimalsInZone()
        self.animals.size=function(rows) return #rows end return self.animals
    end
    DesignationZoneAnimal={getAllZones=function() return {zone} end}
    for x=2,zone.w+1 do for y=2,zone.h+1 do
        local square=F.square(x,y)
        function square:getAnimals() return x==2 and y==2 and zone.animals or {} end
    end end
    for index=1,2 do
        local trough={x=index+1,y=2,z=0,water=0,feed=0,container=F.container()}
        trough.square=F.squares[tostring(index+1)..":2:0"]
        function trough:getWater() return self.water end function trough:getMaxWater() return 100 end
        function trough:getCurrentFeedAmount() return self.feed end function trough:getMaxFeed() return 100 end
        function trough:getContainer() return self.container end function trough:getSquare() return self.square end
        function trough:getObjectIndex() return 0 end
        zone.troughs[index]=trough
    end
    return zone
end
local hen,cow,bull,calf=animal(1,"hen",false,true),animal(2,"cow",false,true),
    animal(3,"bull",false,false),animal(4,"cowcalf",true,false)
local zone=fresh({hen,cow,bull,calf})
check(A.candidate(F.base).operation=="animal_water","mixed pen retains shared care")
local saved=F.base.farm.animals.zones["42"]
check(saved.census.chicken.hens==1 and saved.census.cattle.cows==1
    and saved.census.cattle.bulls==1 and saved.census.cattle.calves==1,"species have separate complete counts")
check(#saved.flockIds==1 and saved.flockIds[1]==1,"cattle never enter retained chicken identities")
check(saved.minimumEnclosureTiles==80,"native enclosure minimum is not multiplied by herd count")
zone=fresh({cow}) cow.x,cow.y=2.5,2.5
for _,square in pairs(F.squares) do function square:getAnimals() return {} end end
check(A.candidate(F.base).operation=="animal_water"
    and F.base.farm.animals.zones["42"].census.cattle.cows==1,
    "native zone membership recovers a moving cow missed by the tile frontier")
cow.x,cow.y=4,4
zone=fresh({cow})
A.candidate(F.base)
check(F.base.farm.animals.zones["42"].blocker=="animal_cattle_enclosure_small",
    "small cattle pasture reports informational space without requiring a hutch")
zone=fresh({hen,animal(5,"sheep",false,true)})
check(A.candidate(F.base).operation=="animal_water","unsupported species does not suppress supported care")
check(F.base.farm.animals.zones["42"].census.unsupported,"unsupported species remains incomplete for irreversible policy")
check(not A.breedingPlan({complete=true,capacity=20,unsupported=true},
    {verified=true,stock=100,dailyPerBird=1}).verified,"unsupported population cannot authorize breeding")

zone=fresh({cow},32,32)
local originalGrid,reads=U.gridSquare,0
U.gridSquare=function(...) reads=reads+1 return originalGrid(...) end
local candidate,reason,pending=A.candidate(F.base,2)
check(candidate==nil and pending and reads<=2,"large pasture yields within requested square slice")
for _=1,600 do
    local before=reads candidate,reason,pending=A.candidate(F.base,2)
    check(reads-before<=2,"continuations retain the same square budget")
    if candidate then break end
end
U.gridSquare=originalGrid
check(candidate and candidate.operation=="animal_water","1024-tile cattle pasture finishes across bounded slices")
zone=fresh({hen},32,32)
for _=1,70 do candidate=A.candidate(F.base,16) end
check(candidate==nil and F.base.farm.animals.zones["42"]==nil,"large chicken-only pen cannot gain cattle permission")
cattleEnabled=0 zone=fresh({cow})
check(A.candidate(F.base)==nil,"disabled cattle cannot admit work")
cattleEnabled=1 zone=fresh({hen,cow})
zone.troughs[1].water,zone.troughs[2].feed=100,100
local hutch={x=2,y=2,z=0,occupants={hen},square=F.squares["2:2:0"]}
function hutch:getHutch() return "hutchhen" end function hutch:getSquare() return self.square end
function hutch:getObjectIndex() return 0 end function hutch:getMaxAnimals() return 8 end
function hutch:getMaxNestBox() return 0 end function hutch:getAnimalInNestBox() return nil end
function hutch:isDoorClosed() return false end
function hutch:getAnimalInside() return {size=function() return #self.occupants end,
    values=function() return self.occupants end} end
zone.hutches={{getHutch=function() return hutch end}}
F.hour=22
candidate=A.candidate(F.base)
check(candidate and candidate.operation=="animal_close","registered cattle cannot block sheltered chickens closing")
hutch.occupants={} F.clock=F.clock+1000
check(A.candidate(F.base)==nil,"mixed pen still keeps a missing chicken's door open")

zone=fresh({cow})
zone.troughs[1].water=100
candidate=A.candidate(F.base)
local farmer=F.actor("farmer",2,2)
local feedJob=F.job("animal_feed",3,2,candidate)
local apple=F.item("Base.Apple",201)
function apple:getAnimalFeedType() return "Fruits" end
function apple:getHungerChange() return -.12 end
F.addStorage("storage:farming","farming",{apple})
local handled,why=SC.FarmWork.update(farmer,{},feedJob,{})
check(handled==false and why=="farm_supply_missing","cattle care does not donate human fruit even from farming storage")
local feed=F.item("Base.AnimalFeedBag",202)
function feed:getAnimalFeedType() return "AnimalFeed" end
function feed:getCurrentUses() return 20 end
local source,sourceContainer=F.addStorage("storage:cattle-feed","farming",{feed})
handled,why=SC.FarmWork.update(farmer,{},feedJob,{})
check(handled and feed:getContainer()==farmer.inventory and SC.FarmWork.isItemProtected(feed),
    "cattle feed uses the exact protected borrowing receipt")
local seeds=F.item("Base.SunflowerSeeds",203)
function seeds:getAnimalFeedType() return "Seeds" end
check(A.isFeed(seeds,"chicken") and not A.isFeed(seeds,"cattle"),"chicken-only feed is not offered to cattle")

zone=fresh({cow})
candidate=A.candidate(F.base)
zone.troughs[1].water=30
local waterJob=F.job("animal_water",2,2,candidate)
waterJob.target.waterTrips=2
F.base.farm.animals.zones["42"].refills={[waterJob.target.deviceKey]=true}
farmer=F.actor("farmer",2,2)
local state={jobId=waterJob.id}
handled,why=A.update(farmer,{},waterJob,{},state)
check(handled and state.animalReturn,"two donor trips yield the cattle water job with cargo intact")
A.update(farmer,{},waterJob,{},state)
check(waterJob.state=="completed","yielded water work closes its existing job")
candidate=A.candidate(F.base)
check(candidate and candidate.operation=="animal_water","next audit continues the high-water target above the low mark")
zone.troughs[1].water=90
candidate=A.candidate(F.base)
check(candidate and candidate.operation=="animal_feed","reaching high water clears its continuation")
local risk={cattle={animals={{id=3,kind="bull"}}},members={[3]=bull}}
check(not A.cattleThreat(farmer,risk),"a calm nearby bull does not invent danger")
bull.stress=70
check(A.cattleThreat(farmer,risk),"a stressed nearby bull blocks cattle work")
bull.stress=0 bull.attacking=true
check(A.cattleThreat(farmer,risk),"native animal aggression blocks cattle work")
bull.attacking=false

local milkSettings={animalCattleEnabled=1,animalMilkEnabled=1}
U.config=function(name) return milkSettings[name] or oldConfig(name) end
local data={quantity=5,capacity=10,genetic=20,lactating=true}
function data:getMilkQuantity() return self.quantity end
function data:getMaxMilkActual() return self.capacity end
function data:getMaxMilk() return self.genetic end
function data:isFemale() return true end
function data:canHaveMilk() return self.lactating end
function data:getAttachedPlayer() return self.player end
function data:getAttachedTree() return nil end
function cow:getData() return data end
function cow:getMilkType() return "CowMilk" end
function cow:getBabies() return self.babies or {} end
local milkRow={cattle={animals={}}}
F.hour=12
check(A.milkPlan(cow,milkRow,{}).reserve==0,"adult lactating cow admits at fifty percent")
data.quantity=4.99
check(A.milkPlan(cow,milkRow,{})==nil,"ordinary threshold does not round up")
data.quantity=8
check(A.milkPlan(cow,milkRow,{}).urgent,"eighty percent is welfare priority")
milkRow.cattle.animals={{baby=true,motherId=2}}
local plan=A.milkPlan(cow,milkRow,{})
check(plan.calf and plan.reserve==4,"matching calf retains forty percent of current capacity")
data.quantity=6.99
check(A.milkPlan(cow,milkRow,{})==nil,"nursing cow waits until seventy percent")
check(A.milkPlan(cow,milkRow,{},"job:new")==nil,"newly claimed work revalidates its start threshold")
milkRow.cattle.animals[1].motherId=99
check(not A.milkPlan(cow,milkRow,{}).calf,"known unrelated mother does not reserve every cow")
milkRow.cattle.animals[1].motherId=nil
check(A.milkPlan(cow,milkRow,{})==nil,"unknown mother conservatively reserves every cow")
data.quantity=7
check(A.milkPlan(cow,milkRow,{}).calf,"nursing admission includes exact seventy percent")
cow.stress=40.01
check(A.milkPlan(cow,milkRow,{})==nil,"native spill stress blocks milking")
cow.stress=40
check(A.milkPlan(cow,milkRow,{})~=nil,"exact forty stress remains allowed")
milkRow.cattle.animals={}
cow.babies={calf}
check(A.milkPlan(cow,milkRow,{}).calf,"a native newborn is protected before the next zone census")
cow.babies=nil
cow.stress=0 data.player={}
check(A.milkPlan(cow,milkRow,{})==nil,"led cattle are excluded")
data.player=nil data.lactating=false
check(A.milkPlan(cow,milkRow,{})==nil,"dry cows are excluded despite species milkability")
data.lactating=true
check(A.milkPlan(bull,milkRow,{})==nil and A.milkPlan(calf,milkRow,{})==nil,"bulls and calves cannot be milked")
local savedMilk={milked={["2"]={day=4,jobId="job:daily"}}}
check(A.milkPlan(cow,milkRow,savedMilk)==nil,"saved daily limit survives runtime reset")
check(A.milkPlan(cow,milkRow,savedMilk,"job:daily")~=nil,"the same daily job may make another delivery trip")
F.hour=22
check(A.milkPlan(cow,milkRow,{})==nil,"night policy never permits milking after dark")
F.hour=12
Fluid={CowMilk={}}
local bucket=F.item("Base.Bucket",250)
local fc={amount=0,capacity=10,locked=false}
function fc:getAmount() return self.amount end function fc:getCapacity() return self.capacity end
function fc:isInputLocked() return self.locked end function fc:canAddFluid(fluid) return fluid==Fluid.CowMilk end
function bucket:getFluidContainer() return fc end
check(A.milkContainer(bucket) and SC.FarmWork.isFarmingSupply(bucket),"empty compatible milk container is a Farming supply")
fc.amount=.01
check(not A.milkContainer(bucket),"part-filled containers never receive borrowed milk")
fc.amount=0 fc.locked=true
check(not A.milkContainer(bucket),"input-locked containers fail closed")
fc.locked=false
local projected,weight=U.projectedCarryLoad, U.itemWeight
U.projectedCarryLoad=function() return 8,10 end
U.itemWeight=function() return .5 end
check(math.abs(A.milkRoom(farmer,bucket,false)-1.4)<.001,"load projection reserves shell weight and carrying headroom")
U.projectedCarryLoad=function() return 0,20 end
local small=F.item("Base.Bucket",251)
function small:getFluidContainer()
    return {getAmount=function() return 0 end,getCapacity=function() return 1 end,
        isInputLocked=function() return false end,canAddFluid=function() return true end}
end
F.addStorage("storage:milk-buckets","farming",{small,bucket})
local loanState={jobId="job:milk"}
local borrowed=SC.FarmWork.animalSupport.borrow(farmer,{},F.job("animal_milk",2,2),loanState,
    A.milkContainer,{"farming"},"milk-rank",function(item) return A.milkRoom(farmer,item,false) end)
check(borrowed and loanState.borrowed and loanState.borrowed.item==bucket,
    "bounded borrowing chooses the largest safe container even within the same item type")
U.projectedCarryLoad,U.itemWeight=projected,weight
U.config=oldConfig
print("CATTLE_WORK_PASS checks="..checks)
