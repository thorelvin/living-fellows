-- SPDX-License-Identifier: MIT
-- Stock installed timed-action Lua, with deterministic native engine boundaries.
local SC, f = SurvivorCompanion, SurvivorCompanion.TestFixture
local C, N, U = SC.NativeCareActions, SC.NativeActions, SC.GameplayUtil
local checks = 0
local function check(value, message) checks = checks + 1; assert(value, "care " .. checks .. ": " .. message) end
local function list(items)
    items = items or {}
    function items:size() return #self end
    function items:get(i) return self[i+1] end
    function items:add(v) self[#self+1] = v end
    function items:remove(v) for i,x in ipairs(self) do if x==v then table.remove(self,i); return end end end
    function items:isEmpty() return #self==0 end
    return items
end
ArrayList={new=function() return list() end}
function ISBaseTimedAction:adjustMaxTime(value) return value end
local function item(kind, options)
    local x=f.item(kind,"Item",options)
    function x:setJobType(value) self.jobType=value end
    function x:setJobDelta(value) self.jobDelta=value end
    function x:getOutermostContainer() return self.outer or self.container end
    function x:getBloodLevel() return self.blood or 0 end
    function x:setBloodLevel(value) self.blood=value end
    function x:getDirtiness() return self.dirt or 0 end
    function x:setDirtiness(value) self.dirt=value end
    function x:getItemAfterCleaning() return self.cleanType end
    function x:hasComponent() return false end
    function x:getCurrentUses() return self.uses end
    return x
end
local actor=f.actor("care-worker",3,3,{})
actor.characterActions=list()
function actor:getCharacterActions() return self.characterActions end
function actor:hasAwkwardHands() return false end
function actor:isTimedActionInstant() return false end
function actor:updateHandEquips() end
function actor:resetModel() end
function actor:faceThisObject() end
function actor:faceThisObjectAlt() end
function actor:shouldBeTurning() return false end
function actor:getWornItem() end
function actor:reportEvent() end
function actor:playSound() return 1 end
function actor:getEmitter() return {isPlaying=function() return false end} end
function actor:isPrimaryHandItem(x) return self:getPrimaryHandItem()==x end
function actor:isSecondaryHandItem(x) return self:getSecondaryHandItem()==x end
CharacterStat.UNHAPPINESS={name="UNHAPPINESS"}
function actor:getStats() return {remove=function() end} end
ItemBodyLocation=ItemBodyLocation or {}
local root=actor:getInventory()
function root:setDrawDirty() end
local add=root.AddItem
function root:AddItem(value) return add(self,type(value)=="string" and item(value) or value) end
local soaps=list()
function root:getSoapList() return soaps end
SC.PersonalItems={isProtected=function(x) return x.protected==true end}
function sendReplaceItemInContainer() end
function sendEquip() end
function sendHumanVisual() end
function sendRemoveItemFromContainer() end
function sendAddItemToContainer() end
function syncItemFields() end
function syncVisuals() end
function triggerEvent() end
function log() end
function showDebugInfoInChat() end
function getText(key) return key end
ISInventoryPage={dirtyUI=function() end}
Math={ceil=math.ceil}
ComponentType={FluidContainer="fluid"}
local sink={water=100,hasWater=function(self) return self.water>0 end,
    getFluidAmount=function(self) return self.water end,
    useFluid=function(self,n) self.water=self.water-n; return n end,transmitModData=function() end}
local recipes={}
local dressingRecipe={getResult=function() return {getType=function() return "Base.Bandage" end} end,
    getName=function() return "Clean Bandage" end,getTimeToMake=function() return 40 end}
function getScriptManager() return {getRecipe=function(_,name) return name=="Base.Clean Bandage" and dressingRecipe end,
    getCraftRecipe=function(_,name) return recipes[name] end,
    FindItem=function() return {getStaticModel=function() return "Soap" end} end} end
local function begin(activity)
    activity.fact=activity.fact or {activity=activity.kind}
    check(C.prepare(actor,activity),"prepare exact input list")
    local okay,why=N.startDowntimeAction(actor,activity,function() return activity.cancelled~=true end)
    check(okay,"native action starts: "..tostring(why))
    return ISTimedActionQueue.getTimedActionQueue(actor).current
end
local function complete(activity,action)
    action:complete(); action:perform()
    check(N.finishWork(actor),"native action releases actor and staged inventory")
    check(activity.nativeCompleted==true,"the stock action owns the effect")
end
-- A real failed repair remains a completed native attempt; no flat condition bonus.
local weapon=item("Base.FryingPan",{condition=2,conditionMax=10})
local tape=item("Base.DuctTape",{uses=4}); root:AddItem(weapon); root:AddItem(tape)
local fixer={getNumberOfUse=function() return 2 end,getFixerName=function() return "DuctTape" end,getFixerSkills=function() return list() end}
local fixing={getFixers=function() return list({fixer}) end,getGlobalItem=function() end,
    countUses=function() return tape.uses end,getRequiredItems=function() return list({tape}) end}
local calls,successful=0,false
FixingManager={getFixes=function() return list({fixing}) end,
    fixItem=function(target,worker)
        check(target==weapon and worker==actor,"repair touches only the intended actor and item")
        calls=calls+1; tape.uses=tape.uses-2
        if successful then target.condition=target.condition+3 end
    end}
local a=C.repairCandidate(actor,{weapon,tape}); check(a~=nil,"native requirements admit a repair")
local action=begin(a); complete(a,action)
check(calls==1 and weapon.condition==2 and tape.uses==2 and a.fact.repairImproved==false,"failed native roll consumes real uses without scripted healing")
action:complete(); check(calls==1,"completion cannot repair twice")
successful=true; a=C.repairCandidate(actor,{weapon,tape}); action=begin(a); complete(a,action)
check(weapon.condition==5 and tape.uses==0 and a.fact.repairImproved,"native repair result replaces the old flat bonus")
tape.uses=4; tape.protected=true
check(C.repairCandidate(actor,{weapon,tape})==nil,"protected repair stock is excluded")
tape.protected=false; a=C.repairCandidate(actor,{weapon,tape}); action=begin(a); tape.protected=true
action:complete(); action:perform(); N.finishWork(actor)
check(not a.nativeAttempted and calls==2,"protection added during the action prevents consumption")
tape.protected=false
a=C.repairCandidate(actor,{weapon,tape}); action=begin(a); a.cancelled=true
check(N.cancelWork(actor,"test_cancelled"),"native cancellation releases its own action")
action:complete(); check(calls==2 and root:contains(tape),"a late callback after cancellation cannot spend supplies")
-- Dirty dressing in a bag is staged, natively replaced and returned to that bag.
local bag=f.inventory({}); local dirty=item("Base.BandageDirty",{customName="My dressing"})
root:AddItem(item("Base.Bag_Schoolbag",{nestedInventory=bag})); bag:AddItem(dirty); dirty.outer=root
a={kind="wash_bandage",item=dirty,itemContainer=bag,object=sink,cleanType="Base.Bandage"}
local water=sink.water; action=begin(a); complete(a,action)
check(not bag:contains(dirty) and bag:contains(a.nativeOutput) and sink.water==water-1,"one native dressing consumes exactly native water and stays in its original bag")
check(a.nativeOutput:getName()=="My dressing","custom name follows the actual native replacement")
action:complete(); check(sink.water==water-1,"bandage completion cannot spend water twice")
local retryDirty=item("Base.BandageDirty"); retryDirty.outer=root; bag:AddItem(retryDirty)
a={kind="wash_bandage",item=retryDirty,itemContainer=bag,object=sink,cleanType="Base.Bandage"}
action=begin(a); action:complete(); action:perform(); bag.rejectAdd=true
check(not N.finishWork(actor) and N.ownsDowntimeAction(actor,a) and root:contains(a.nativeOutput),
    "a refused bag return retains ownership and the actual native replacement")
bag.rejectAdd=false; check(N.finishWork(actor) and bag:contains(a.nativeOutput),"bag return retries without washing again")
local dryDirty=item("Base.BandageDirty"); root:AddItem(dryDirty)
a={kind="wash_bandage",item=dryDirty,itemContainer=root,object=sink,cleanType="Base.Bandage"}
action=begin(a); water=sink.water; sink.water=0; action:complete(); action:perform(); N.finishWork(actor)
check(not a.nativeAttempted and root:contains(dryDirty),"water disappearing before native completion preserves the dressing")
sink.water=water
-- Stock body washing is partial when water runs out and cannot affect the player.
local blood,dirt={[0]=1,[1]=0},{[0]=0,[1]=1}
local visual={getBlood=function(_,p) return blood[p] end,getDirt=function(_,p) return dirt[p] end,
    setBlood=function(_,p,n) blood[p]=n end,setDirt=function(_,p,n) dirt[p]=n end}
function actor:getHumanVisual() return visual end
BloodBodyPartType={MAX={index=function() return 2 end},FromIndex=function(i) return i end}
sink.water=1; a={kind="wash_self",object=sink}; action=begin(a); complete(a,action)
check(blood[0]==0 and dirt[1]==1 and sink.water==0,"native self wash cleans only the available-water body part")
local soap=item("Base.Soap2",{uses=2,__class="DrainableComboItem"})
function soap:getCurrentUses() return self.uses end
function soap:UseAndSync() self.uses=self.uses-1 end
soaps[1]=soap; root:AddItem(soap); soap.protected=true
sink.water=10; blood[0]=1
a={kind="wash_self",object=sink}; action=begin(a)
check(action.soaps:isEmpty(),"native body wash never consumes protected soap")
complete(a,action); check(soap.uses==2,"protected soap survives the native body wash")
-- Ordinary equipment uses stock water requirements, soap and wetness behavior.
local pan=item("Base.FryingPan",{blood=1}); root:AddItem(pan)
function pan:hasComponent() return false end
soap.protected=false
a={kind="wash_equipment",object=sink,item=pan}; water=sink.water; action=begin(a); complete(a,action)
check(pan.blood==0 and sink.water==water-7 and soap.uses==1,"native equipment wash accounts for blood, water and soap once")
-- Crafting uses the installed ISHandcraftAction; Java recipe mechanics are the boundary below.
function convertToPZNetTable(value) return value end
DebugType={CraftLogic="craft"}
local craftCalls=0
local surface={getObjectIndex=function() return 0 end,getX=function() return 3 end,
    getY=function() return 3 end,getZ=function() return 0 end}
for _,spec in ipairs({{"Base.MakeSplint","Base.Splint",2},{"Base.CraftSheetRope","Base.SheetRope",1}}) do
    local inputs=list()
    for i=1,spec[3] do inputs:add({isKeep=function() return false end,getIntAmount=function() return 1 end}) end
    local r={output=spec[2],getInputs=function() return inputs end,getTimedActionScript=function() end,
        getTags=function() end,getTime=function() return 50 end,getName=function() return spec[1] end,getTranslationName=function() return spec[1] end,
        getIOForIndex=function(_,i) return inputs[i+1] end,
        getIndexForIO=function(_,input) for i,v in ipairs(inputs) do if input==v then return i-1 end end end}
    recipes[spec[1]]=r
end
HandcraftLogic={new=function(worker,bench,object)
    local logic={manual={},outputs=list(),consumed=list(),object=object}
    function logic:findCraftSurface() return surface end
    function logic:setIsoObject(value) self.object=value end
    function logic:setContainers() end
    function logic:setRecipe(r) self.recipe=r end
    function logic:setTargetVariableInputRatio() end
    function logic:setManualSelectInputs() end
    function logic:clearManualInputs() self.manual={} end
    function logic:setManualInputsFor(input,items) self.manual[input]=items; return true end
    function logic:canPerformCurrentRecipe() return not self.noRecheck end
    function logic:canCharacterPerformRecipe() return not self.noSkill end
    function logic:getModelHandOne() end
    function logic:getModelHandTwo() end
    function logic:performCurrentRecipe()
        craftCalls=craftCalls+1
        for input,items in pairs(self.manual) do
            if not input:isKeep() then for _,x in ipairs(items) do self.consumed:add(x) end end
        end
        if self.recipe.output then self.outputs:add(item(self.recipe.output)) end
        return true
    end
    function logic:getCreatedOutputItems(out) for _,x in ipairs(self.outputs) do out:add(x) end end
    function logic:getRecipeData() return {getAllInputItems=function() return logic.consumed end,
        getAllConsumedItems=function() return logic.consumed end,luaCallOnCreate=function()
            if logic.recipe.repair then weapon.condition=weapon.condition+2 end
        end,
        processDestroyAndUsedItems=function() for _,x in ipairs(logic.consumed) do root:Remove(x); x.container=root end end} end
    return logic
end}
Actions={addOrDropItem=function(worker,x) worker:getInventory():AddItem(x) end}
for _,spec in ipairs({{"Base.RippedSheets","Base.Plank","Base.Splint"},{"Base.Sheet",nil,"Base.SheetRope"}}) do
    local scraps={item(spec[1])}; root:AddItem(scraps[1])
    if spec[2] then scraps[2]=item(spec[2]); root:AddItem(scraps[2]) end
    a=C.craftCandidate(actor,scraps); check(a and a.outputType==spec[3],"stock supply recipe is selected")
    action=begin(a); action:complete(); check(not a.nativeAttempted,"single-player craft complete is not the consumption point")
    local nativeLogic=action.logic; nativeLogic.noRecheck=true
    local stateFor=select(12,SC.Downtime._furnitureForTests())
    local state=stateFor(actor); state.active=a
    check(SC.Downtime.prepareForSave(actor) and N.ownsDowntimeAction(actor,a) and N.isWorkActive(actor),
        "periodic inventory capture does not cancel a native craft")
    state.active=nil
    action:perform(); check(N.finishWork(actor) and a.nativeCompleted,"native recipe completes without repeating a destructive late UI preflight")
    check(action.logic==nativeLogic,"instance-only native result observer restores the original logic object")
    check(a.nativeOutput and root:contains(a.nativeOutput) and not root:contains(scraps[1]),"one real native output replaces exact recipe inputs")
    local before=craftCalls; action:performRecipe(); check(craftCalls==before,"craft callback cannot run twice")
end
-- Current melee repairs have a kept target and no item output. The same stock
-- handcraft action must reach its OnCreate callback, without consuming the tool.
FixingManager.getFixes=function() return list() end
local keep={isKeep=function() return true end,getIntAmount=function() return 1 end,
    canUseItem=function(_,x) return x==weapon end}
local use={isKeep=function() return false end,getIntAmount=function() return 2 end,
    canUseItem=function(_,x) return x==tape end}
local inputs=list({keep,use})
local r={repair=true,isAnySurfaceCraft=function() return true end,getInputs=function() return inputs end,getTimedActionScript=function() end,
    getTags=function() end,getTime=function() return 180 end,getName=function() return "FixWithDuctTape" end,
    getTranslationName=function() return "FixWithDuctTape" end,
    getIOForIndex=function(_,i) return inputs[i+1] end,
    getIndexForIO=function(_,input) return input==keep and 0 or 1 end}
recipes["Base.FixWithDuctTape"]=r
weapon.condition=2; tape.uses=4
a=C.repairCandidate(actor,{weapon,tape})
check(a and a.recipeName=="Base.FixWithDuctTape","current melee repair uses the actual native recipe path")
action=begin(a); action:perform()
check(N.finishWork(actor) and a.nativeCompleted and root:contains(weapon) and weapon.condition==4,
    "repair recipe keeps the exact weapon and applies native OnCreate with zero crafted outputs")
check(not root:contains(tape),"native recipe owns repair ingredient consumption")
local careStateFor=select(12,SC.Downtime._furnitureForTests())
local settledState=careStateFor(actor); settledState.active=a
local settledCommands=SC.Commands.peek(actor); settledCommands.order="stay"; a.commandSerial=settledCommands.commandSerial or 0
check(SC.Downtime.update(actor,f.player,{snapshot={threatCount=0}}) and settledState.active==nil,
    "verified work still commits its report when the status facade has already restored the inventory")
root:AddItem(tape); weapon.condition=2; tape.uses=4
a=C.repairCandidate(actor,{weapon,tape}); action=begin(a)
local _,_,_,_,_,_,_,_,_,reserve,_,stateFor,_,reserveActivity=SC.Downtime._furnitureForTests()
local state=stateFor(actor); state.active=a
local commands=SC.Commands.peek(actor); commands.order="stay"; a.commandSerial=commands.commandSerial or 0
check(reserveActivity(actor,a,SC_TEST_CLOCK),"a long native repair reserves its real work surface")
local clockBefore=SC_TEST_CLOCK; SC_TEST_CLOCK=clockBefore+24000
check(SC.Downtime.update(actor,f.player,{snapshot={threatCount=0}}),"long repair advances without losing the native queue")
check(not reserve(surface,f.actor("other-worker",3,3,{}),clockBefore+40000),"native work renews its surface claim beyond the initial 30-second reservation")
SC_TEST_CLOCK=clockBefore; state.active=nil; a.cancelled=true; N.cancelWork(actor,"test_done")
weapon.condition=2; tape.protected=true
check(C.repairCandidate(actor,{weapon,tape})==nil,"current repair recipes cannot pin protected ingredients")
check(C.repairCandidate(actor,{item("Base.Unrepairable"),tape})==nil,"unsupported equipment is skipped")
print("NATIVE_CARE_PASS checks="..checks)
