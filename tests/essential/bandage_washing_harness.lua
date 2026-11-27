-- SPDX-License-Identifier: MIT
-- Installed stock timed actions, with deterministic Java fluid/recipe boundaries.
local SC, f = LivingFellows, LivingFellows.TestFixture
local W, C, N, D, U = SC.BandageWash, SC.NativeCareActions, SC.NativeActions, SC.Downtime, SC.GameplayUtil
local checks = 0
local function check(value, message) checks = checks + 1; assert(value, "bandage wash " .. checks .. ": " .. message) end
local function list(values)
    values = values or {}
    function values:size() return #self end
    function values:get(i) return self[i + 1] end
    function values:add(item) self[#self + 1] = item end
    function values:remove(item) for i,x in ipairs(self) do if x==item then table.remove(self,i); return end end end
    function values:isEmpty() return #self == 0 end
    return values
end
ArrayList = {new=function() return list() end}
function ISBaseTimedAction:adjustMaxTime(value) return value end
function convertToPZNetTable(value) return value end
function showDebugInfoInChat() end
function log() end
function getText(key) return key end
function syncItemFields() end
function syncVisuals() end
function sendRemoveItemFromContainer() end
function sendAddItemToContainer() end
function triggerEvent() end
DebugType = {CraftLogic="craft"}
Math = {ceil=math.ceil}
ComponentType = {FluidContainer="fluid"}
ISInventoryPage = {dirtyUI=function() end}
local function item(kind, options)
    local x = f.item(kind, "Item", options)
    function x:getOutermostContainer() return self.outer or self.container end
    function x:setJobType() end
    function x:setJobDelta() end
    function x:getBloodLevel() return 0 end
    function x:setBloodLevel() end
    function x:getDirtiness() return 0 end
    function x:getItemAfterCleaning() return W.cleanType(self) end
    function x:setCustomName(value) self.customNameFlag = value end
    return x
end
local worker = f.actor("bandage-washer", 3, 3, {})
local root = worker:getInventory()
worker.characterActions = list()
function worker:getCharacterActions() return self.characterActions end
function worker:hasAwkwardHands() return false end
function worker:isTimedActionInstant() return false end
function worker:faceThisObject() end
function worker:updateHandEquips() end
function worker:resetModel() end
function worker:reportEvent() end
function worker:isPrimaryHandItem(x) return self:getPrimaryHandItem() == x end
function worker:isSecondaryHandItem(x) return self:getSecondaryHandItem() == x end
local add = root.AddItem
function root:AddItem(x) return add(self, type(x)=="string" and item(x) or x) end
function root:getSoapList() return list() end
local savedPersonal, savedTransport, savedNavigation = SC.PersonalItems, SC.WorkTransport, SC.Navigation
SC.PersonalItems = {isProtected=function(x) return x.protected == true end}
SC.WorkTransport = {foreignProtected=function(x)
    if x.cargo then return true,"work_item_owned" end
    if x:isFavorite() then return true,"favorite_item" end
    return false
end}
local function bottle(amount, tainted, protected, extra)
    local x = item("Base.WaterBottle", {protected=protected})
    local fluid = {amount=amount, water=amount-(tainted or 0), tainted=tainted or 0, capacity=3, extra=extra or 0}
    fluid.amount = fluid.amount + fluid.extra
    function fluid:getAmount() return self.amount end
    function fluid:getCapacity() return self.capacity end
    function fluid:getSpecificFluidAmount(kind) return kind==Fluid.Water and self.water or kind==Fluid.TaintedWater and self.tainted or 0 end
    function fluid:contains(kind) return self:getSpecificFluidAmount(kind)>0 end
    function fluid:isEmpty() return self.amount <= 0 end
    function fluid:canPlayerEmpty() return true end
    function fluid:isPoisonous() return self.extra > 0 end
    function fluid:isTainted() return self.tainted > 0 end
    function fluid:isWaterOnlySource() return self.tainted == 0 and self.extra == 0 end
    function x:getFluidContainer() return fluid end
    root:AddItem(x)
    return x, fluid
end
local function remove(x) local holder=x:getContainer(); if holder then holder:Remove(x) end end
local safe, safeFluid = bottle(1.49)
check(W.carriedWaterPlan(worker)==nil,"1.49L cannot spend the last usable litre")
safeFluid.amount, safeFluid.water = 1.5, 1.5
check(W.carriedWaterPlan(worker).item==safe,"exactly1.5L admits one0.5L wash")
safeFluid.amount, safeFluid.water = 1.499, 1.499
check(W.carriedWaterPlan(worker)==nil,"a measurable reserve shortfall is refused")
local protected, protectedFluid = bottle(3, 0, true)
check(W.carriedWaterPlan(worker)==nil,"protected water contributes zero drinking reserve")
local loan = bottle(3); loan:getModData().LF_PlayerLoan={owner="player"}
check(W.carriedWaterPlan(worker)==nil,"loaned water contributes zero drinking reserve")
local mixed = bottle(1, 0.5)
safeFluid.amount, safeFluid.water = 2, 2
check(W.carriedWaterPlan(worker).item==mixed,"Water/TaintedWater mixture wins over safe water")
remove(safe); remove(protected); remove(loan)
check(W.carriedWaterPlan(worker).item==mixed,"tainted washing needs no safe drinking reserve")
local cleaner = bottle(1, 0, false, 0.2)
remove(mixed)
check(W.carriedWaterPlan(worker)==nil,"cleaner/alcohol/unknown admixture is rejected")
remove(cleaner)
local washBottle, washFluid = bottle(2, 2)
local outerBag, innerBag = f.inventory({}), f.inventory({})
local outer = item("Base.Bag", {nestedInventory=outerBag})
local inner = item("Base.FirstAidKit", {nestedInventory=innerBag})
root:AddItem(outer); outerBag:AddItem(inner)
local dirty = item("Base.BandageDirty", {favorite=true,customName="Road dressing"})
dirty.outer=root; innerBag:AddItem(dirty)
local entries = W.inventoryEntries(worker)
check(W.carriedEntry(worker,dirty,entries).source==innerBag,"deep nesting retains the actual source bag")
check(W.isInputAllowed(worker,dirty,nil,entries),"native AllowFavorite washing preserves a favorite dressing")
outer.protected=true
check(not W.isInputAllowed(worker,dirty),"protected ancestor prevents personal washing")
outer.protected=false
root:Remove(washBottle); innerBag:AddItem(washBottle); washBottle.outer=root
inner:getModData().LF_MedicKitLoan={actorId="worker"}
check(W.carriedWaterPlan(worker)==nil,"a loaned kit ancestor protects its bottle")
inner:getModData().LF_MedicKitLoan=nil
innerBag:Remove(washBottle); root:AddItem(washBottle)
local selected, consumed, outputs, calls = nil, list(), list(), 0
local fluidChild = {getAmount=function() return 0.5 end,isFluidMixture=function() return true end}
local dirtyIO = {getIntAmount=function() return 1 end,canUseItem=function(_,x) return W.cleanType(x)~=nil end}
local waterIO = {getConsumeFromItemScript=function() return fluidChild end,
    canUseItem=function(_,x) return x:getFluidContainer()~=nil end}
local inputs = list({dirtyIO,waterIO})
local recipe = {getInputs=function() return inputs end,getTimedActionScript=function() end,getTags=function() end,
    getTime=function() return 40 end,getName=function() return "CleanBandage" end,getTranslationName=function() return "CleanBandage" end,
    getIndexForIO=function(_,input) return input==dirtyIO and 0 or 1 end,getIOForIndex=function(_,i) return inputs[i+1] end}
function getScriptManager() return {getCraftRecipe=function(_,name) if name=="Base.CleanBandage" or name=="CleanBandage" then return recipe end end,
    FindItem=function() return {getStaticModel=function() return "Soap" end} end} end
HandcraftLogic = {new=function(actor)
    local logic={manual={},outputs=list(),consumed=list()}
    function logic:setContainers() end
    function logic:setRecipe() end
    function logic:setTargetVariableInputRatio() end
    function logic:setManualSelectInputs() end
    function logic:clearManualInputs() self.manual={} end
    function logic:setManualInputsFor(input,items) self.manual[input]=items; return true end
    function logic:canPerformCurrentRecipe() return self.manual[dirtyIO]~=nil and self.manual[waterIO]~=nil end
    function logic:getModelHandOne() end
    function logic:getModelHandTwo() end
    function logic:performCurrentRecipe()
        calls=calls+1
        local input, vessel=self.manual[dirtyIO][1],self.manual[waterIO][1]
        selected=vessel
        local fluid=vessel:getFluidContainer()
        local fraction=0.5/fluid.amount
        fluid.water,fluid.tainted=fluid.water*(1-fraction),fluid.tainted*(1-fraction)
        fluid.amount=fluid.amount-0.5
        self.consumed:add(input); self.outputs:add(item(W.cleanType(input)))
        return true
    end
    function logic:getCreatedOutputItems(target) for _,x in ipairs(self.outputs) do target:add(x) end end
    function logic:getRecipeData() return {getAllInputItems=function() return list() end,getAllConsumedItems=function() return logic.consumed end,
        luaCallOnCreate=function() end,processDestroyAndUsedItems=function()
            for _,x in ipairs(logic.consumed) do root:Remove(x) end
        end} end
    return logic
end}
Actions={addOrDropItem=function(actor,x) actor:getInventory():AddItem(x) end}
local function begin(activity)
    check(C.prepare(worker,activity),"prepare exact dirty and bottle inputs")
    local okay,why=N.startDowntimeAction(worker,activity,function() return activity.cancelled~=true end)
    check(okay,"queue stock action: "..tostring(why))
    return ISTimedActionQueue.getTimedActionQueue(worker).current
end
local activity = W.makeActivity(worker,dirty,{waterPlan=W.carriedWaterPlan(worker)})
local operation=begin(activity); operation:perform()
check(N.finishWork(worker) and activity.nativeCompleted,"stock recipe verifies and settles")
check(selected==washBottle and washFluid.amount==1.5 and calls==1,"only exact pinned tainted bottle spends0.5L")
check(innerBag:contains(activity.nativeOutput) and not innerBag:contains(dirty),"verified clean object returns to exact nested bag")
check(activity.nativeOutput:isFavorite() and activity.nativeOutput:getName()=="Road dressing"
    and activity.nativeOutput.customNameFlag,"favorite and explicit custom-name metadata follow native output")
check(activity.resultVerification.input==dirty and activity.resultVerification.output==activity.nativeOutput,"exact transformation mapping is exposed")
operation:performRecipe(); check(calls==1,"duplicate stock callback cannot wash twice")
local nextDirty=item("Base.RippedSheetsDirty"); root:AddItem(nextDirty)
activity=W.makeActivity(worker,nextDirty,{waterPlan=W.carriedWaterPlan(worker)})
operation=begin(activity); activity.cancelled=true
check(N.cancelWork(worker,"test_cancelled"),"cancel releases exact native action")
operation:performRecipe()
check(calls==1 and root:contains(nextDirty) and innerBag:contains(activity.nativeOutput)==false,"cancel leaves prior clean result and untouched next dirty input")
local claim={jobId="wash-job",validate=function() return true end,ownsInput=function(_,x) return x==nextDirty end}
nextDirty.cargo=true
check(W.makeActivity(worker,nextDirty,{waterPlan=W.carriedWaterPlan(worker),claim=claim})==nil,"claim cannot bypass protections without the scoped transport helper")
nextDirty.cargo=false
local washCandidate=select(9,D._washForTests())
SC.Navigation=nil
local state={}
local candidate=washCandidate(worker,{},state,f.clock)
check(candidate==nil,"unrelated carried clean output blocks emergency bottle washing")
remove(innerBag.items[1])
candidate=washCandidate(worker,{},state,f.clock)
check(candidate==nil,"unknown safety snapshot cannot authorize emergency bottle washing")
candidate=washCandidate(worker,{},state,f.clock,{threatCount=1,closeThreatCount=1,escapeSquares={}})
check(candidate==nil,"close threat prevents emergency bottle washing")
candidate=washCandidate(worker,{},state,f.clock,{threatCount=0,immediateCount=0})
check(candidate and candidate.score==85 and candidate.waterItem==washBottle,"no clean dressing gives washing score85")
local sink={water=100,getFluidAmount=function(self) return self.water end,isTaintedWater=function() return false end,
    hasWater=function(self) return self.water>0 end,useFluid=function(self,n) self.water=self.water-n end,
    transmitModData=function() end,getObjectIndex=function() return 0 end,getSquare=function() return worker:getSquare() end}
local square=worker:getSquare(); square.objects[#square.objects+1]=sink
local clean=item("Base.Bandage"); root:AddItem(clean)
candidate=washCandidate(worker,{},state,f.clock)
check(candidate and candidate.score==74 and candidate.object==sink,"clean supply lowers world washing to74")
remove(clean)
SC.Navigation={beginPathSearch=function() return {} end,resumePathSearch=function() return "pending" end,interactionTargets=function() return {} end}
square.objects={}
candidate=washCandidate(worker,{}, {}, f.clock)
check(candidate==nil,"pending world-source survey cannot trigger carried fallback")
SC.Navigation=nil
for i=1,10 do root:AddItem(item("Base.BandageDirty")) end
square.objects={sink}
candidate=washCandidate(worker,{}, {}, f.clock)
check(candidate and #candidate.washBatch==8,"one visit pins at most eight exact dirty inputs")
local _,_,_,_,_,_,_,_,_,_,beginBatch=D._washForTests()
local stateFor=select(12,D._furnitureForTests())
state=stateFor(worker)
local commands=SC.Commands.peek(worker); commands.order="stay"
local direct=U.directInteractionAccess
U.directInteractionAccess=function() return true,{},nil end
local accepted,why=beginBatch(worker,state,candidate,commands,f.clock)
check(accepted,"one supervised batch starts: "..tostring(why))
for index=1,8 do
    operation=ISTimedActionQueue.getTimedActionQueue(worker).current
    check(operation~=nil,"piece"..index.." has its own stock native action")
    operation:complete(); operation:perform()
    check(D.update(worker,f.player,{snapshot={threatCount=0}}),"piece settles through ordinary downtime update")
    if index<8 then
        check(state.active==candidate and candidate.washBatchWaiting,"settled piece retains the same source visit")
        check(D.update(worker,f.player,{snapshot={threatCount=0}})
            and ISTimedActionQueue.getTimedActionQueue(worker).current==nil,"ordinary result pacing prevents immediate next wash")
        f.clock=f.clock+5000
        check(D.update(worker,f.player,{snapshot={threatCount=0}}),"next piece starts after result pacing")
    end
end
check(state.active==nil and candidate.fact.washedCount==8,"batch completes after exactly eight verified native results")
local dirtyLeft=0
for _,row in ipairs(W.inventoryEntries(worker)) do if W.cleanType(row.item) then dirtyLeft=dirtyLeft+1 end end
check(dirtyLeft==3,"unselected dirty stock is preserved for a later visit")
local guarded=item("Base.BandageDirty"); guarded.outer=root; innerBag:AddItem(guarded)
activity=W.makeActivity(worker,guarded,{object=sink,square=square})
operation=begin(activity); outer.protected=true
operation:complete(); operation:perform()
check(not activity.nativeAttempted and root:contains(guarded),"late ancestor protection blocks effect after native staging")
check(not N.finishWork(worker),"protected original bag cannot receive a staged item")
outer.protected=false
check(N.finishWork(worker) and innerBag:contains(guarded),"unspent input returns when original bag is available again")
root:Remove(washBottle); innerBag:AddItem(washBottle); washBottle.outer=root
activity=W.makeActivity(worker,guarded,{waterPlan=W.carriedWaterPlan(worker)})
operation=begin(activity)
local before=washFluid.amount
inner:getModData().LF_MedicKitLoan={actorId="new-owner"}
operation:perform()
check(not activity.nativeAttempted and washFluid.amount==before,"late ancestor loan blocks pinned bottle after staging: "
    ..tostring(activity.nativeAttempted).."/"..tostring(washFluid.amount).."/"..tostring(before).."/"..tostring(#activity.washWaterPlan.ancestors))
check(not N.finishWork(worker) and root:contains(washBottle),"loaned original bag retains staged bottle for safe settlement")
inner:getModData().LF_MedicKitLoan=nil
check(N.finishWork(worker) and innerBag:contains(washBottle),"clearing late loan returns exact surviving bottle")
activity=W.makeActivity(worker,guarded,{object=sink,square=square})
operation=begin(activity); operation:complete(); operation:perform(); outer.protected=true
check(activity.nativeCompleted and not N.finishWork(worker) and root:contains(activity.nativeOutput),
    "late return protection keeps real clean output rather than rebuilding consumed dirty input")
outer.protected=false
check(N.finishWork(worker) and innerBag:contains(activity.nativeOutput),"verified clean output returns after protection clears")
U.directInteractionAccess=direct
SC.PersonalItems,SC.WorkTransport,SC.Navigation=savedPersonal,savedTransport,savedNavigation
print("bandage washing checks="..checks)
