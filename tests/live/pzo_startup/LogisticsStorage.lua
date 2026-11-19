-- SPDX-License-Identifier: MIT
-- Disposable native PZO regression: public camp changes during a Loot pose.
-- Only LF companions receive orders; zombie navigation is untouched.
local SC, s = SurvivorCompanion, { phase='menu', checks=0, caseIndex=0, completed=0 }
local kinds = { 'unmarked', 'relabeled', 'unchanged' }
local function write(name, value)
    local writer=assert(getFileWriter(name,true,false));writer:write(value);writer:close()
end
local function field(value) return tostring(value == nil and '' or value):gsub('[\r\n]', ' ') end
local function check(value, reason)
    s.checks=s.checks+1;assert(value,'logistics storage '..s.checks..': '..reason)
end
local function finish(okay, reason)
    if s.done then return end;s.done=true
    local text='result='..(okay and 'PASS' or 'FAIL')..'\nphase='..s.phase
        ..'\nreason='..field(reason)..'\nchecks='..s.checks..'\ncompleted_cases='..s.completed
        ..'\ncase='..field(s.kind)..'\nlast_work='..field(s.work)
        ..'\nmax_tick_gap_ms='..tostring(s.maxGap or 0)..'\n'
    print('SC_PZO_LOGISTICS_STORAGE '..text);write('pzo-logistics-storage-result.txt',text)
end
local function phase(name, now)
    s.phase,s.at=name,now
    write('pzo-logistics-storage-progress.txt',name..'\ncase='..field(s.kind)..'\ncompleted='..s.completed..'\n')
    print('SC_PZO_LOGISTICS_STORAGE phase='..name..' case='..field(s.kind))
end
local function update()
    SC.ActionSupervisor.update(s.actor)
    if SC.NativeActions.pacingStatus(s.actor) then s.work='normal_action_pacing';return end
    local okay,why=SC.Logistics.update(s.actor,s.primary,
        {snapshot={threatCount=0,immediateCount=0,pressure=0}})
    s.work=tostring(okay)..'/'..tostring(why)
end
local function identity()
    check(s.item:getID()==s.itemId,'exact seed identity retained')
end
local function startCase(now)
    s.caseIndex=s.caseIndex+1;s.kind=kinds[s.caseIndex]
    s.item=assert(s.actor:getInventory():AddItem('Base.TomatoSeed'))
    s.itemId=s.item:getID()
    check(not s.ids[s.itemId],'new case has a distinct native item ID');s.ids[s.itemId]=true
    s.items[#s.items+1]=s.item
    check(SC.Logistics.itemCategory(s.item)=='farming','native seed exercises proactive ordinary shelving')
    phase('start',now)
end
Events.OnInitGlobalModData.Add(function()
    ModData.getOrCreate(SC.Identity.worldSaveKey).document={
        schema=SC.Identity.saveSchema,companions={},factionActors={}}
end)
Events.OnMainMenuEnter.Add(function() MainScreen.continueLatestSave('Sandbox','PzoRestoreFixture') end)
local seen={}
Events.OnRenderTick.Add(function()
    local modal=MainScreen and MainScreen.instance and MainScreen.instance.checkSavefileModal
    if modal and modal.yes and not seen[modal] then seen[modal]=true;modal:onClick(modal.yes) end
end)
Events.OnGameStart.Add(function()
    SC.Scheduler.unregister('decision')
    s.primary=assert(getSpecificPlayer(0));s.primary:teleportTo(6428.5,5449.5,0)
    phase('load',getTimestampMs())
end)
local function step()
    if s.done or s.phase=='menu' then return end
    local now=getTimestampMs()
    if s.lastTick and s.phase~='load' then s.maxGap=math.max(s.maxGap or 0,now-s.lastTick) end;s.lastTick=now
    if s.phase=='load' then
        if now-s.at<12000 then return end
        check(SCBridge and PZOEngine and SC.Actor.checkBridge(true),'actual PZO loader and production companion bridge')
        SC.BaseLife.reset();SC.Logistics.reset()
        check(SC.BaseLife.create(assert(getCell():getGridSquare(6428,5449,0)),
            'Native logistics storage'),'native camp created')
        local base=SC.BaseLife.active()
        base.settings.autoMaintenance,base.settings.routines,base.settings.workload=false,false,'essential'
        local square=assert(getCell():getGridSquare(6433,5449,0))
        s.object=IsoThumpable.new(getCell(),square,'carpentry_01_16',false,{})
        s.object:setIsContainer(true);s.object:setContainer(ItemContainer.new('crate',square,s.object))
        s.container=s.object:getContainer();s.container:setCapacity(100);s.container:setExplored(true)
        square:AddSpecialObject(s.object);square:RecalcAllWithNeighbours(true)
        local okay,row=SC.BaseLife.registerStorage(s.object,'farming')
        check(okay,'real Farming crate registered');s.row=row
        s.ticket=assert(SC.Actor.beginSpawn(assert(getCell():getGridSquare(6430,5450,0)),
            {recruited=true,identity={forename='Storage',surname='Courier',gender='woman',outfit='Generic01'}}))
        phase('spawn',now)
    elseif s.phase=='spawn' then
        local actor,why=SC.Actor.pollSpawn(s.ticket)
        if not actor then check(why=='spawn_pending' and now-s.at<15000,tostring(why));return end
        s.actor,s.id=actor,assert(SC.Registry.idOf(actor))
        check(SC.BaseLife.assign(s.id,'farmer',true),'native resident assigned')
        check(SC.Commands.issue(s.id,'base_duty',{},s.primary),'native resident ordered to camp duty')
        local stats=actor:getStats()
        stats:set(CharacterStat.HUNGER,0.05);stats:set(CharacterStat.THIRST,0.05)
        stats:set(CharacterStat.FATIGUE,0.05);stats:set(CharacterStat.ENDURANCE,1)
        s.ids,s.items={},{};startCase(now)
    elseif s.phase=='start' then
        update();identity()
        check(s.item:getContainer()==s.actor:getInventory(),'seed remains carried before active native pose')
        local progress=SC.Logistics.progress(s.actor)
        if progress.phase=='visual' and SC.NativeActions.visualStatus(s.actor,'loot_container')=='active' then
            check(SC.ActionSupervisor.peekOwner(s.actor)=='logistics','ordinary logistics owns the native pose')
            if s.kind=='unmarked' then
                check(SC.BaseLife.removeStorage(s.row.id),'public unmark succeeds while ordinary transfer is pending')
                check(not SC.BaseLife.storageAcceptsDeposit(s.row,s.container),'unmarked storage rejects deposits')
            elseif s.kind=='relabeled' then
                check(SC.BaseLife.setStorageCategory(s.row.id,'medical'),'public category change succeeds while transfer is pending')
                check(s.row.category=='medical','crate is now marked Medical')
            end
            phase(s.kind=='unchanged' and 'control' or 'changed',now)
        end
        assert(now-s.at<60000,'ordinary native seed shelving never reached its Loot pose: '..tostring(s.work))
    elseif s.phase=='changed' then
        update();identity()
        check(s.item:getContainer()==s.actor:getInventory(),'changed storage must retain the exact seed with its carrier')
        if not SC.Logistics.busy(s.actor) then
            check(SC.ActionSupervisor.peekOwner(s.actor)~='logistics','rejected deposit releases its action owner')
            check(SC.NativeActions.visualStatus(s.actor,'loot_container')~='active','rejected deposit releases its native pose')
            if s.kind=='unmarked' then
                local okay,row=SC.BaseLife.registerStorage(s.object,'farming')
                check(okay,'same physical crate can be publicly registered again');s.row=row
            else check(SC.BaseLife.setStorageCategory(s.row.id,'farming'),'publicly restore correct Farming category') end
            check(SC.BaseLife.storageAcceptsDeposit(s.row,s.container),'restored destination permits ordinary retry')
            phase('retry',now)
        end
        assert(now-s.at<15000,'changed deposit did not settle: '..tostring(s.work))
    elseif s.phase=='retry' or s.phase=='control' then
        update();identity()
        local owner=s.item:getContainer()
        check(owner==s.actor:getInventory() or owner==s.container,'seed never escapes the exact carrier/destination pair')
        if owner==s.container then
            check(s.row.category=='farming','successful transfer uses the current correct category')
            check(not SC.Logistics.busy(s.actor),'successful transfer releases ordinary logistics')
            s.completed=s.completed+1
            if s.caseIndex<#kinds then startCase(now) else
                check(s.container:getItems():size()==#kinds,'crate contains exactly the three original case items')
                check(s.actor:getBodyDamage():getOverallBodyHealth()>=99.9,'worker healthy at completion')
                phase('stable',now)
            end
        end
        assert(now-s.at<100000,'normal native retry/control did not complete: '..tostring(s.work))
    elseif s.phase=='stable' then
        update()
        for _,item in ipairs(s.items) do
            check(item:getContainer()==s.container and s.ids[item:getID()],'all exact native items retain their correct owner')
        end
        if now-s.at>=15000 then finish(true,'public unmark/relabel rejected, normal retries and unchanged native control completed') end
    end
end
Events.OnTick.Add(function()
    if s.done then return end
    local okay,why=pcall(step);if not okay then finish(false,why) end
end)
