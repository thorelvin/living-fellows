-- SPDX-License-Identifier: MIT
-- Phase 0 only: native effects on disposable fixture companions/items.
-- No LF production behavior or zombie navigation is replaced.
require 'TimedActions/ISStitch'
require 'TimedActions/ISSplint'
require 'TimedActions/ISWashClothing'
require 'TimedActions/ISCleanBandage'
require 'Entity/TimedActions/ISHandcraftAction'
local SC,s=SurvivorCompanion,{phase='menu',checks=0,notes={}}
local function write(name,value)
    local w=assert(getFileWriter(name,true,false));w:write(value);w:close()
end
local function check(value,reason)
    s.checks=s.checks+1;assert(value,'medical capabilities '..s.checks..': '..reason)
end
local function note(value) s.notes[#s.notes+1]=value;print('SC_MEDICAL_CAPABILITY '..value) end
local function finish(okay,reason)
    if s.done then return end;s.done=true
    local queue=s.primary and ISTimedActionQueue.getTimedActionQueue(s.primary)
    local primaryUnchanged=queue and queue.current==s.primaryCurrent and #queue.queue==s.primaryQueued
    if not primaryUnchanged then okay,reason=false,'primary queue changed' end
    local text='result='..(okay and 'PASS' or 'FAIL')..'\nphase='..s.phase..'\nreason='..tostring(reason)
        ..'\nchecks='..s.checks..'\nprimary_queue_untouched='..tostring(primaryUnchanged)..'\n'..table.concat(s.notes,'\n')..'\n'
    write('pzo-medical-capabilities-result.txt',text);print('SC_PZO_MEDICAL_CAPABILITIES '..text)
end
local function phase(name)
    s.phase,s.at=name,getTimestampMs();write('pzo-medical-capabilities-progress.txt',name..'\n')
end
local function list(items)
    local result=ArrayList.new();for _,item in ipairs(items) do result:add(item) end;return result
end
local function count(container,kind)
    local n=0;local items=container:getItems()
    for i=0,items:size()-1 do if items:get(i):getFullType()==kind then n=n+1 end end
    return n
end
local function partReset()
    s.actor:getBodyDamage():RestoreToFullHealth()
    local p=s.actor:getBodyDamage():getBodyPart(BodyPartType.Foot_R)
    p:setGetStitchXp(false);p:setGetSplintXp(false);return p
end
local function effects()
    local actor=s.actor;local p=partReset()
    local setters={
        {'bite','getBiteTime','bitten',function(q) q:SetBitten(true,true);q:setBiteTime(9) end},
        {'scratch','getScratchTime','scratched',function(q) q:setScratched(true,true);q:setScratchTime(9) end},
        {'cut','getCutTime','isCut',function(q) q:setCut(true,true);q:setCutTime(9) end},
        {'deep','getDeepWoundTime','deepWounded',function(q) q:setDeepWounded(true);q:setDeepWoundTime(9) end},
        {'stitch','getStitchTime','stitched',function(q) q:setStitched(true);q:setStitchTime(45) end},
    }
    for _,row in ipairs(setters) do
        p=partReset();row[4](p);p:setBandaged(true,15,false,'Base.Bandage')
        check(p[row[2]](p)>0,'bandage preserves '..row[1]..' timer')
        check(p[row[3]](p)==false,'bandage hides '..row[1]..' flag')
    end
    p=partReset();p:setStitched(true);p:setStitchTime(45);p:setBandaged(true,15,false,'Base.Bandage')
    p:setStitched(false)
    check(p:getStitchTime()==45,'direct removal while hidden cannot clear the stitch timer')
    p:setBandaged(false,0,false,nil)
    check(p:stitched(),'unbandaging restores hidden stitched flag')
    p:setStitched(false)
    check(p:getStitchTime()==0 and not p:stitched(),'uncovered ready stitches remove correctly')
    check(p:getScratchTime()>0,'ready removal leaves native scratch')
    p=partReset();p:setStitched(true);p:setStitchTime(39);p:setStitched(false)
    check(p:getDeepWoundTime()>0 and p:bleeding(),'39 reopens native deep wound and bleeding')
    p=partReset();p:setStitched(true);p:setStitchTime(40);p:setAdditionalPain(0)
    local doctor=actor:getPerkLevel(Perks.Doctor)
    local operation=ISStitch:new(actor,actor,nil,p,false)
    local originalRandom,originalSync=ZombRand,syncBodyPart
    local syncMask
    ZombRand=function() return 0 end
    syncBodyPart=function(part,mask) syncMask=mask;return originalSync(part,mask) end
    local completed,result=pcall(operation.complete,operation)
    ZombRand,syncBodyPart=originalRandom,originalSync
    check(completed and result==true,'stock stitch removal completes on native companion')
    check(p:getStitchTime()==0 and p:getDeepWoundTime()<=0 and p:getScratchTime()>0,'40 is safe native boundary')
    check(math.abs(p:getAdditionalPain()-math.max(0,5-doctor))<0.001,'stock stitch pain matches Doctor')
    check(p:isInfectedWound(),'stock removal infection roll takes effect at deterministic random boundary')
    check(syncMask==0x00570188,'stock stitch removal sends documented native sync mask')
    note('stitch_remove_sync=0x00570188; infection_roll=stock_ISStitch.complete_verified; doctor='..doctor)
    for _,kind in ipairs({'Base.Splint','Base.Plank'}) do
        p=partReset();p:setFractureTime(0);p:setSplint(true,0);p:setSplintItem(kind)
        check(p:isSplint() and p:getSplintFactor()==0,'zero-factor splint is still attached')
        local before=count(actor:getInventory(),kind);local rags=count(actor:getInventory(),'Base.RippedSheets')
        syncBodyPart=function(part,mask) syncMask=mask;return originalSync(part,mask) end
        local action=ISSplint:new(actor,actor,nil,nil,p,false)
        completed,result=pcall(action.complete,action)
        syncBodyPart=originalSync
        check(completed and result==true,'stock splint removal completes')
        check(syncMask==0x430000000,'stock splint removal sends documented native sync mask')
        check(not p:isSplint() and p:getSplintFactor()==0,'splint removal clears attachment')
        check(count(actor:getInventory(),kind)==before+1,'recorded splint material returned once')
        check(count(actor:getInventory(),'Base.RippedSheets')==rags+(kind=='Base.Splint' and 0 or 1),'improvised splint rag return matches vanilla')
    end
    p=partReset();p:setSplint(true,0);p:setSplintItem(nil)
    local before=actor:getInventory():getItems():size()
    ISSplint:new(actor,actor,nil,nil,p,false):complete()
    check(actor:getInventory():getItems():size()==before,'missing provenance creates no returned item')
    partReset();note('hidden_timers=bite,scratch,cut,deep,stitch; splint_remove_sync=0x430000000')
end
local function craft()
    local actor=s.actor;local root=actor:getInventory();local manager=getScriptManager()
    local legacy=manager:getRecipe('Base.Clean Bandage')
    local recipe=manager:getCraftRecipe('Base.CleanBandage') or manager:getCraftRecipe('CleanBandage')
    note('legacy_clean_bandage_recipe='..tostring(legacy~=nil)..'; legacy_action_class='..tostring(ISCleanBandage~=nil))
    check(recipe~=nil,'42.22 native CleanBandage craft recipe exists')
    local dirty=assert(root:AddItem('Base.BandageDirty'))
    local selected=assert(root:AddItem('Base.WaterBottle'))
    local clean=assert(root:AddItem('Base.WaterBottle'))
    local protected=assert(root:AddItem('Base.WaterBottle'))
    local sf,cf,pf=selected:getFluidContainer(),clean:getFluidContainer(),protected:getFluidContainer()
    check(sf and cf and pf,'real bottles expose native fluid containers')
    sf:Empty();sf:addFluid(Fluid.TaintedWater,1)
    cf:Empty();cf:addFluid(Fluid.Water,1)
    pf:Empty();pf:addFluid(Fluid.Water,1);protected:getModData().LF_TestProtectedWater=true
    local inputs=recipe:getInputs();note('craft_inputs='..inputs:size())
    local logic=HandcraftLogic.new(actor,nil,nil)
    logic:setContainers(list({root}));logic:setRecipe(recipe);logic:setManualSelectInputs(true);logic:clearManualInputs()
    for i=0,inputs:size()-1 do
        local input=inputs:get(i);local io=recipe:getIndexForIO(input)
        local kind=tostring(input:getResourceType())
        note('input'..i..'='..kind..'; amount='..tostring(input:getAmount())..'; line='..tostring(input:getOriginalLine()))
        local chosen=input:canUseItem(dirty,actor) and dirty or selected
        check(logic:setManualInputsFor(recipe:getIOForIndex(io),list({chosen})),'manual input '..i..' is pinned to exact approved item')
    end
    check(logic:canPerformCurrentRecipe(),'native recipe can run with pinned tainted bottle')
    local before=count(root,'Base.Bandage');local old=sf:getAmount()
    -- Vanilla owns output placement and destroy/use finalization too. Bare
    -- performCurrentRecipe is only the first step of this stock helper.
    ISHandcraftAction.performRecipe({logic=logic,character=actor})
    local outputs=ArrayList.new();logic:getCreatedOutputItems(outputs)
    check(outputs:size()==1 and outputs:get(0):getFullType()=='Base.Bandage','native HandcraftLogic produces exact clean dressing output')
    note('craft_after: dirty_container='..tostring(dirty:getContainer())..'; selected='..sf:getAmount()..'; clean='..cf:getAmount()..'; protected='..pf:getAmount())
    check(dirty:getContainer()~=root and count(root,'Base.Bandage')==before+1,'recipe replaces dirty input with one clean bandage')
    check(math.abs(sf:getAmount()-(old-0.5))<0.0001,'selected tainted water loses exactly 0.5L')
    check(math.abs(cf:getAmount()-1)<0.0001 and math.abs(pf:getAmount()-1)<0.0001,'clean reserve and protected bottle remain untouched')
    note('craft_tainted_consumed=0.5L; clean_reserve=1L; protected_water_untouched=true')
end
local function findSource()
    local U=SC.GameplayUtil;local origin=s.primary:getSquare()
    local ox,oy,oz=origin:getX(),origin:getY(),origin:getZ()
    for dx=-20,20 do for dy=-20,20 do
        local square=getCell():getGridSquare(ox+dx,oy+dy,oz)
        if square then
            local objects=square:getObjects()
            for i=0,objects:size()-1 do
                local object=objects:get(i)
                local okay,amount=pcall(function() return object:getFluidAmount() end)
                if okay and tonumber(amount) and amount>=8 and object:hasWater() and not object:isTaintedWater() then return object end
            end
        end
    end end
end
local function worldWash()
    local source=assert(findSource(),'fixture needs a real loaded clean water source')
    local root=s.actor:getInventory();local item=assert(root:AddItem('Base.BandageDirty'))
    local needed=ISWashClothing.GetRequiredWater(item);local water=source:getFluidAmount();local before=count(root,'Base.Bandage')
    local operation=ISWashClothing:new(s.actor,source,item,0,0,true)
    operation.soaps=list({});operation.noSoap=true
    check(operation:isValid(),'stock world-water washing is valid')
    check(operation:complete()==true,'stock ISWashClothing completes')
    check(item:getContainer()~=root and count(root,'Base.Bandage')==before+1,'world wash replaces exactly one dirty dressing')
    local remaining=source:getFluidAmount();local fluid=source:getFluidContainer()
    -- IsoObject.isWaterInfinite is private. Native getFluidAmount returns its
    -- 10000 sentinel for unlimited plumbing; stock useFluid succeeds unchanged.
    local finiteKnown=fluid~=nil and water<10000
    note('world_wash_required_water='..needed..'; source='..source:getSquare():getX()..','..source:getSquare():getY()
        ..'; hasWater='..tostring(source:hasWater())..'; before='..water..'; after='..remaining
        ..'; finiteKnown='..tostring(finiteKnown)..'; infinitePredicate=private_native')
    check(remaining>=0 and remaining<=water,'native source water never increases during wash')
    if finiteKnown then check(math.abs(remaining-(water-needed))<0.001,'known finite water consumed at native requirement') end
end
Events.OnInitGlobalModData.Add(function()
    ModData.getOrCreate(SC.Identity.worldSaveKey).document={schema=SC.Identity.saveSchema,companions={},factionActors={}}
end)
Events.OnMainMenuEnter.Add(function() MainScreen.continueLatestSave('Sandbox','PzoRestoreFixture') end)
local seen={}
Events.OnRenderTick.Add(function()
    local modal=MainScreen and MainScreen.instance and MainScreen.instance.checkSavefileModal
    if modal and modal.yes and not seen[modal] then seen[modal]=true;modal:onClick(modal.yes) end
end)
Events.OnGameStart.Add(function()
    SC.Scheduler.unregister('decision');s.primary=assert(getSpecificPlayer(0))
    local queue=ISTimedActionQueue.getTimedActionQueue(s.primary)
    s.primaryCurrent,s.primaryQueued=queue.current,#queue.queue
    phase('load')
end)
local function step()
    if s.done or s.phase=='menu' then return end
    if s.phase=='load' then
        if getTimestampMs()-s.at<12000 then return end
        check(SCBridge and PZOEngine and SC.Actor.checkBridge(true),'real PZO and production companion provider')
        local U=SC.GameplayUtil;local square=s.primary:getSquare();local spawn
        for r=1,8 do if not spawn then for dx=-r,r do for dy=-r,r do
            local candidate=getCell():getGridSquare(square:getX()+dx,square:getY()+dy,square:getZ())
            if candidate and U.isClearActorSpawnSquare(candidate)==true and candidate:isFree(false) then spawn=candidate;break end
        end if spawn then break end end end end
        check(spawn~=nil,'loaded safe companion spawn found')
        s.ticket=assert(SC.Actor.beginSpawn(spawn,{recruited=true,identity={forename='Medical',surname='Capabilities',gender='woman',outfit='Generic01'}}))
        phase('spawn')
    elseif s.phase=='spawn' then
        local actor,why=SC.Actor.pollSpawn(s.ticket)
        if not actor then check(why=='spawn_pending' and getTimestampMs()-s.at<15000,tostring(why));return end
        s.actor=actor;phase('effects')
    elseif s.phase=='effects' then effects();phase('craft')
    elseif s.phase=='craft' then craft();phase('world-wash')
    elseif s.phase=='world-wash' then
        worldWash()
        if SC.Identity.bridgeProtocol=='42.22-isocompanion-35' then
            s.findSource,s.count,s.partReset=findSource,count,partReset
            phase('acceptance-start')
        else finish(true,'native medical and washing capabilities verified') end
    elseif string.sub(s.phase,1,11)=='acceptance-' then
        s.acceptance=s.acceptance or require 'MedicalAcceptance'
        if s.acceptance.step(s,check,note,phase)==true then finish(true,'native clinical and washing production acceptance verified') end
    end
end
Events.OnTick.Add(function()
    if s.done then return end
    local okay,why=pcall(step);if not okay then finish(false,why) end
end)
