-- SPDX-License-Identifier: MIT
-- Exercise the shipped native handcraft Lua body and the yard controller.
local SC, f = SurvivorCompanion, SurvivorCompanion.TestFixture
local U, Yard, N = SC.GameplayUtil, SC.LogYard, SC.NativeActions
local realBaseLife=SC.BaseLife
local checks = 0
local function check(value, message) checks=checks+1 assert(value, "yard "..checks..": "..message) end
local function list(values)
    values=values or {}
    function values:add(value) self[#self+1]=value end
    function values:size() return #self end
    function values:get(i) return self[i+1] end
    function values:remove(item) for i,v in ipairs(self) do if v==item then table.remove(self,i); return end end end
    return values
end
ArrayList={new=function() return list() end}
ItemContainer={new=function() local c=f.inventory({}); c.items=list(c.items); return c end}
function convertToPZNetTable(value) return value end
function log() end
function showDebugInfoInChat() end
DebugType={CraftLogic="craft"}
ISInventoryPage={dirtyUI=function() end}
local inputs={}
for _,n in ipairs({4,2}) do
    inputs[#inputs+1]={isKeep=function() return false end,getIntAmount=function() return n end}
end
local recipe={getInputs=function() return list(inputs) end,
    getIndexForIO=function(_,input) return input==inputs[1] and 0 or 1 end,
    getIOForIndex=function(_,i) return inputs[i+1] end,
    getTimedActionScript=function() end,getTags=function() end,getTime=function() return 60 end,
    getName=function() return "MakeFourLogStack" end,getTranslationName=function() return "Stack four logs" end}
local recipes={ ["Base.MakeFourLogStack"]=recipe }
for _,count in ipairs({2,3,4}) do
    local input={isKeep=function() return false end,getIntAmount=function() return 1 end}
    local r={unstackCount=count,getInputs=function() return list({input}) end,
        getIndexForIO=function() return 0 end,getIOForIndex=function() return input end}
    setmetatable(r,{__index=recipe})
    recipes["Base.Unstack"..({[2]="Two",[3]="Three",[4]="Four"})[count].."Logs"]=r
end
function getScriptManager() return {getCraftRecipe=function(_,name) return recipes[name] end} end
local nativeCrafts, failAfterOutput=0,false
local nativeItems,nextNativeId={},0
HandcraftLogic={new=function(actor)
    local logic={manual={},outputs=list()}
    function logic:setContainers(c) self.containers=c end
    function logic:setRecipe(value) self.recipe=value end
    function logic:setTargetVariableInputRatio() end
    function logic:setManualSelectInputs() end
    function logic:clearManualInputs() self.manual={} end
    function logic:setManualInputsFor(input,items) self.manual[input]=items return true end
    function logic:canPerformCurrentRecipe()
        if self.recipe.unstackCount then return #(self.manual[self.recipe:getIOForIndex(0)] or {})==1 end
        return self.manual[inputs[1]] and #self.manual[inputs[1]]==4
            and self.manual[inputs[2]] and #self.manual[inputs[2]]==2
    end
    function logic:getModelHandOne() end
    function logic:getModelHandTwo() end
    local consumed=list()
    local data={getAllInputItems=function() return consumed end,getAllConsumedItems=function() return consumed end}
    function data:luaCallOnCreate()
        if logic.recipe.unstackCount then
            for _,kind in pairs(consumed[1]:getModData().ropeItems) do
                actor.inventory:AddItem(f.item(kind,"Item",{tags={ROPE=true},weight=0.3}))
            end
            return
        end
        logic.outputs[1]:getModData().ropeItems={
            [0]=logic.manual[inputs[2]][1]:getFullType(),[1]=logic.manual[inputs[2]][2]:getFullType()}
    end
    function data:processDestroyAndUsedItems()
        if failAfterOutput then error("native interruption after output") end
        for _, item in ipairs(consumed) do
            local world=item:getWorldItem()
            if world then world:removeFromWorld(); world:removeFromSquare(); item:setWorldItem(nil) end
            local c=item:getContainer()
            if c then c:Remove(item); item.container=c end -- native references can lag removal
        end
    end
    function logic:getRecipeData() return data end
    function logic:performCurrentRecipe()
        nativeCrafts=nativeCrafts+1
        for _,input in ipairs(self.recipe:getInputs()) do for _,item in ipairs(self.manual[input]) do consumed:add(item) end end
        if self.recipe.unstackCount then
            for i=1,self.recipe.unstackCount do self.outputs:add(f.item("Base.Log","Item",{weight=9})) end
        else self.outputs:add(f.item("Base.LogStacks4","Item",{weight=12})) end
        return true
    end
    function logic:getCreatedOutputItems(items) for _,item in ipairs(self.outputs) do items:add(item) end end
    return logic
end}
Actions={addOrDropItem=function(actor,item) actor:getInventory():AddItem(item) end}
local sq=f.cell:getGridSquare(3,3,0)
local source,object=f.containerObject(f.cell:getGridSquare(2,3,0),{})
local storage={id="ropes",category="crafting"}
local base={jobs={},zones={{id="yard",kind="log_yard",x1=3,y1=3,x2=3,y2=3,z=0}}}
local serial=0
SC.BaseLife={active=function() return base end,isOutdoorSquare=function() return true end,
    zoneValid=function() return true end,withinWorkReach=function() return true end,
    storage=function(id) return id==storage.id and storage end,
    resolveContainer=function(s) return s==storage and source end,
    storageRows=function(category) return category=="crafting" and {storage} or {} end,
    availableCountExact=function(_,kind)
        local n=0 for _,item in ipairs(source.items) do if item.itemType==kind then n=n+1 end end return n
    end,
    job=function(id) for _,j in ipairs(base.jobs) do if j.id==id then return j end end end,
    enqueueJob=function(spec) serial=serial+1; spec.id="stack:"..serial; spec.state="pending"; base.jobs[#base.jobs+1]=spec; return true,spec end}
SC.PersonalItems=nil; SC.WorkTransport=nil
local withdrawn=0
SC.BaseWork.withdrawFromStorage=function(actor,_,s,c,item)
    check(s==storage and c==source,"only the registered rope source is withdrawn")
    c:Remove(item); actor.inventory:AddItem(item); withdrawn=withdrawn+1; return true,"rope_carried"
end
SC.BaseWork.restoreToStorage=function(actor,_,c,item)
    actor.inventory:Remove(item); c:AddItem(item); return true
end
local function worker(id)
    local actor=f.actor(id,3,3,{})
    actor.characterActions=list()
    function actor:getCharacterActions() return self.characterActions end
    -- Simulate a stale native id cache as well as a stale item.container.
    function actor.inventory:getItemById(id) return nativeItems[id] end
    function actor:hasAwkwardHands() return false end
    function actor:isTimedActionInstant() return false end
    return actor
end
local actor=worker("yard-worker")
local function loose()
    sq.worldItems={}
    local items={}
    for i=1,4 do items[i]=f.item("Base.Log","Item",{weight=9}); sq:AddWorldInventoryItem(items[i],0,0,0) end
    return items
end
local function rope(kind,c)
    local item=f.item(kind or "Base.Rope","Item",{tags={ROPE=true},weight=0.3})
    nextNativeId=nextNativeId+1; item.nativeId=nextNativeId; nativeItems[nextNativeId]=item
    function item:getID() return self.nativeId end
    c:AddItem(item); return item
end
local function queue()
    local okay=Yard.bundleAt(actor,sq); check(okay,"a full tile queues a camp job")
    local job=base.jobs[#base.jobs]; job.state="active"; job.reservedBy=actor.id; return job
end
local function advance(job)
    for i=1,200 do
        SC_TEST_CLOCK=SC_TEST_CLOCK+100
        local okay,reason,terminal,done=Yard.update(actor,{},job)
        if terminal or done or N.workKind(actor)=="stack_logs" then return okay,reason,terminal,done end
    end
    error("unbounded yard preparation")
end
local logs=loose()
local a,b=rope("Base.Rope",source),rope("Mod.StrongRope",source)
local job=queue()
local _,why=advance(job)
check(N.workKind(actor)=="stack_logs","real handcraft action starts: "..tostring(why))
local competitor={id="other-stack",type="stack_logs",state="pending",target={x=4,y=3,z=0}}
base.jobs[#base.jobs+1]=competitor
check(not Yard.canClaim(competitor),"a second stack job cannot split the last ropes between workers")
table.remove(base.jobs)
check(#sq.worldItems==4 and withdrawn==2 and nativeCrafts==0,"preparation does not consume logs or fabricate a bundle")
check(a:getContainer()==actor.inventory and b:getContainer()==actor.inventory,"native crafting uses both physically borrowed rope variants")
check(Yard.source(actor)==nil,"a second worker cannot take claimed logs")
local action=ISTimedActionQueue.getTimedActionQueue(actor).current
action:complete()
check(nativeCrafts==0 and #sq.worldItems==4,"single-player complete is not mistaken for consumption")
action:perform()
local realDrop=U.dropItem
U.dropItem=function(inventory,square,item)
    if item.itemType=="Base.LogStacks4" then return false,"test_output_drop_refused" end
    return realDrop(inventory,square,item)
end
local _,dropReason,_,dropDone=Yard.update(actor,{},job)
check(not dropDone and dropReason=="test_output_drop_refused" and nativeCrafts==1,
    "a refused output drop retains the real native result without replay")
U.dropItem=realDrop
local _,reason,_,done=Yard.update(actor,{},job)
check(done and reason=="log_yard_bundled","native result is delivered: "..tostring(reason))
check(#sq.worldItems==1 and sq.worldItems[1].item.itemType=="Base.LogStacks4","exactly one native four-log output is left in the yard")
local output=sq.worldItems[1].item
check(output:getModData().ropeItems[1]=="Mod.StrongRope","native rope metadata retains variant types")
action:performRecipe()
check(nativeCrafts==1,"repeated callbacks cannot craft twice")
job.state="completed"
logs=loose(); a,b=rope(nil,source),rope(nil,source); job=queue(); advance(job)
check(Yard.cancel(actor,job)==true,"cancellation stops only the matching craft")
check(#sq.worldItems==4 and a:getContainer()==source and b:getContainer()==source,"cancellation returns exact borrowed ropes and leaves four exact logs")
for _,item in ipairs(logs) do check(not Yard.reserved(item),"cancel releases each floor claim") end
job.state="cancelled"
source.items={}
local bagContents=f.inventory({})
local bag=f.item("Base.Bag_Schoolbag","Container",{nestedInventory=bagContents})
function bag:getItemContainer() return bagContents end
function bagContents:getContainingItem() return bag end
actor.inventory:AddItem(bag)
local personalA,personalB=rope(nil,bagContents),rope(nil,bagContents)
loose(); job=queue(); advance(job)
action=ISTimedActionQueue.getTimedActionQueue(actor).current; action:perform()
local _,bagReason,_,bagDone=Yard.update(actor,{},job)
check(bagDone and bagReason=="log_yard_bundled","personal bag rope completes despite stale native item references")
check(#bagContents.items==0 and not actor.inventory:contains(personalA) and not actor.inventory:contains(personalB),
    "native cleanup never returns consumed rope to its previous bag")
job.state="completed"; actor.inventory:Remove(bag)
-- A long shelf scan must resume before reporting missing rope.
source.items={}; for i=1,1500 do source:AddItem(f.item("Base.Nails","Item",{weight=0.01})) end
rope(nil,source); rope(nil,source); loose(); job=queue()
local okay,pending,terminal=Yard.update(actor,{},job)
check(okay and pending=="log_yard_rope_search_pending" and not terminal,"a bounded unfinished search is not a shortage")
advance(job); check(N.workKind(actor)=="stack_logs","late-shelf ropes are eventually discovered")
Yard.cancel(actor,job); job.state="cancelled"
source.items={}; rope(nil,source); loose(); job=queue()
local enough,missing,shortage=advance(job)
check(not enough and shortage and missing=="log_yard_rope_missing","one rope is a conclusive shortage")
check(#source.items==1 and not job.target.stage and not job.assignedId,
    "a shortage returns its single borrowed rope and releases preparation ownership")
job.state="cancelled"; rope(nil,source)
-- An output created before a native exception must never cause an automatic replay.
loose(); job=queue(); advance(job); failAfterOutput=true
action=ISTimedActionQueue.getTimedActionQueue(actor).current
local completed=pcall(action.performRecipe,action)
check(not completed and job.target.attempted==true,"native failure retains the attempt receipt")
local before=nativeCrafts
N.cancelWork(actor,"test-interrupt")
local _,uncertain,blocked=Yard.update(actor,{},job)
check(blocked and uncertain=="log_yard_craft_receipt_uncertain" and nativeCrafts==before,"ambiguous native failure blocks without recreating ingredients")
check(Yard.cancel(actor,job)==true,"explicit cancellation releases surviving items after uncertainty")
check(nativeCrafts==before,"cancellation never replays the recipe")
-- Open real native recipe outputs inside an existing parent job. The native
-- callback owns returning rope; the yard only moves the created log objects.
failAfterOutput=false
for i=#actor.inventory.items,1,-1 do
    local item=actor.inventory.items[i]
    if item.itemType=="Base.LogStacks4" then actor.inventory:Remove(item) end
end
local destination={zoneId="yard",x=3,y=3,z=0}
local function bundle(size)
    sq.worldItems={}
    local item=f.item("Base.LogStacks"..size,"Item",{weight=6})
    item:getModData().ropeItems={[0]="Base.Rope",[1]="Mod.StrongRope"}
    sq:AddWorldInventoryItem(item,0.5,0.5,0)
    return item
end
local function parentJob()
    local _,j=SC.BaseLife.enqueueJob({type="production",target={orderId="saw"}})
    j.state,j.reservedBy="active",actor.id
    return j
end
local function ropeCount(kind)
    local count=0 for _,item in ipairs(actor.inventory.items) do if item.itemType==kind then count=count+1 end end
    return count
end
for _,size in ipairs({2,3,4}) do
    actor.inventory.capacity=15
    local original=bundle(size)
    local plain,strong=ropeCount("Base.Rope"),ropeCount("Mod.StrongRope")
    local parent=parentJob()
    local started,why,item=Yard.takeOne(actor,destination,parent)
    check(started and why=="log_yard_unstacking" and not item,"unstack "..size.." starts without prematurely taking a log: "..tostring(why))
    check(original:getWorldItem() and #sq.worldItems==1,"original bundle survives until the native action performs")
    action=ISTimedActionQueue.getTimedActionQueue(actor).current
    action:complete(); action:perform()
    local taken,reason,log=Yard.takeOne(actor,Yard.source(actor,"yard",parent),parent)
    check(taken and reason=="log_yard_log_taken" and log and log.itemType=="Base.Log","native unstack "..size.." yields one selected exact log: "..tostring(reason))
    check(#Yard.contents(sq).logs==size-1 and #Yard.contents(sq).bundles==0,"remaining native logs stay on their yard tile")
    check(ropeCount("Base.Rope")==plain+1 and ropeCount("Mod.StrongRope")==strong+1,"native OnCreate returns the original rope variants once")
    check(not parent.target.yardUnstack and not Yard.contents(sq).splitPending,"the parent job and floor claims settle")
    local before=nativeCrafts; action:performRecipe(); check(nativeCrafts==before,"native unstack cannot be replayed")
    actor.inventory:Remove(log); parent.state="completed"
end
local original=bundle(4); local parent=parentJob()
Yard.takeOne(actor,destination,parent)
check(Yard.cancelUnstack(actor,parent),"cancel stops matching native unstack")
check(#sq.worldItems==1 and sq.worldItems[1].item==original and not Yard.splitReserved(original),"pre-consumption cancellation keeps the exact bundle and releases its claim")
parent.state="cancelled"
original=bundle(4); parent=parentJob(); Yard.takeOne(actor,destination,parent)
action=ISTimedActionQueue.getTimedActionQueue(actor).current; action:perform()
check(Yard.cancelUnstack(actor,parent) and #Yard.contents(sq).logs==4,"cancelling a completed unstack preserves all four real logs without reconstructing a bundle")
parent.state="cancelled"
-- A native drop refusal retains the same output identities for reconciliation.
original=bundle(3); parent=parentJob(); Yard.takeOne(actor,destination,parent)
action=ISTimedActionQueue.getTimedActionQueue(actor).current
local savedDrop=U.dropItem
U.dropItem=function(inv,square,item) if item.itemType=="Base.Log" then return false,"drop_refused" end return savedDrop(inv,square,item) end
action:perform(); local before=nativeCrafts
local pending,why=Yard.takeOne(actor,destination,parent)
check(pending and why=="log_yard_unstack_drop_pending" and nativeCrafts==before,"output drop failure never reruns native crafting")
U.dropItem=savedDrop
local taken,why,log=Yard.takeOne(actor,destination,parent)
check(taken and why=="log_yard_log_taken" and nativeCrafts==before,"drop recovery delivers the same native log")
actor.inventory:Remove(log); parent.state="completed"
-- Missing native rope metadata is refused before any recipe can create items.
actor.inventory.capacity=50
original=bundle(2); original:getModData().ropeItems=nil; parent=parentJob()
local taken,why=Yard.takeOne(actor,destination,parent)
check(not taken and why=="log_yard_bundle_metadata_missing" and #sq.worldItems==1,"a malformed bundle stays intact without guessed rope refunds")
parent.state="cancelled"
SC.BaseLife=realBaseLife
check(realBaseLife.create(sq,"Reload yard"),"create real persisted camp")
local queued,savedJob=realBaseLife.enqueueJob({type="stack_logs",target={x=3,y=3,z=0,
    stage="preparing",logs={"l1","l2","l3","l4"},
    ropes={{id="r1",sourceId="shelf"},{id="r2"}},
    yardUnstack={v=2,id="unstack:old",jobId="old",ownerId=actor.id,zoneId="yard",count=4,
        x=3,y=3,z=0,sourceId="bundle-token",attempted=true,nativeOK=true,outputs={"o1","o2","o3","o4"}}}})
check(queued,"real scheduler accepts a stack job")
local saved=realBaseLife.export()
check(realBaseLife.restore(saved),"real save normalization restores the optional work receipt")
local restored=realBaseLife.job(savedJob.id)
check(restored and restored.target.logs[4]=="l4" and restored.target.ropes[1].sourceId=="shelf"
    and restored.target.ropes[2].id=="r2","reload retains exact floor and borrowed rope identities")
check(restored.target.yardUnstack.outputs[4]=="o4" and restored.target.yardUnstack.attempted==true,
    "reload retains native unstack output receipts without replay")
print("LOG_YARD_PASS checks="..checks.." nativeCrafts="..nativeCrafts)
