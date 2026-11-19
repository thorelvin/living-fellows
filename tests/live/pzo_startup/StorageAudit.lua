-- SPDX-License-Identifier: MIT
-- Full native catalogue, real destination selectors and optional physical sort.
-- Only disposable LF fixture actors receive work; zombie navigation is untouched.
require "SCStorageCategoryCases"
local SC, s = SurvivorCompanion, { phase='menu', index=0, count=0, errors=0, skipped=0, checks=0, cases=0, roles=0, routes=0, refused=0 }
local function field(v) return tostring(v == nil and '' or v):gsub('[\t\r\n]', ' ') end
local function write(name, value)
    local w=assert(getFileWriter(name,true,false));w:write(value);w:close()
end
local function check(value, reason)
    s.checks=s.checks+1;assert(value,'storage hardening '..s.checks..': '..reason)
end
local function call(o,m)
    local okay,value=pcall(function() return o[m](o) end)
    return okay and value or nil
end
local function finish(okay,reason)
    if s.done then return end;s.done=true
    if s.writer then s.writer:close();s.writer=nil end
    local text='result='..(okay and 'PASS' or 'FAIL')..'\nphase='..s.phase..'\nreason='..field(reason)
        ..'\nitems='..s.count..'\nskipped='..s.skipped..'\nerrors='..s.errors..'\nreviewed_cases='..s.cases
        ..'\nloadout_roles='..s.roles..'\nrouted_items='..s.routes..'\ncapacity_refusals='..s.refused..'\nphysical_items='..tostring(s.physicalCount or 0)
        ..'\nchecks='..s.checks..'\nmax_tick_gap_ms='..tostring(s.maxGap or 0)..'\nlast_work='..field(s.work)..'\n'
    write('pzo-storage-audit-result.txt',text);print('SC_PZO_STORAGE_AUDIT '..text)
end
local function phase(name,now)
    s.phase,s.at=name,now
    write('pzo-storage-audit-progress.txt',name..'\nitems='..s.count..'\n')
    print('SC_PZO_STORAGE_AUDIT phase='..name)
end
local function tags(item)
    local list,result=call(item,'getTags'),{}
    if list then local iterator=list:iterator()
        while iterator:hasNext() do local tag=iterator:next();result[#result+1]=field(call(tag,'getTranslationName') or tag) end
    end
    table.sort(result);return table.concat(result,';')
end
local function crate(index,category)
    local x=6430+((index-1)%4)*3;local y=5445+math.floor((index-1)/4)*3
    local square=assert(getCell():getGridSquare(x,y,0),'crate square unloaded')
    local object=IsoThumpable.new(getCell(),square,'carpentry_01_16',false,{})
    object:setIsContainer(true);object:setContainer(ItemContainer.new('crate',square,object))
    object:getContainer():setCapacity(100);object:getContainer():setExplored(true)
    square:AddSpecialObject(object);square:RecalcAllWithNeighbours(true)
    local okay,row=SC.BaseLife.registerStorage(object,category)
    check(okay,'registered real '..category..' shelf: '..tostring(row))
    return {row=row,container=object:getContainer()}
end
local function nativeExpected(item,case)
    local wanted,certain=SC.BaseWork.classifyItem(item)
    check(wanted==case.expected and certain==true,case.type..' expected '..case.expected..', got '..tostring(wanted))
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
    SC.Scheduler.unregister('decision')
    s.primary=assert(getSpecificPlayer(0));s.primary:teleportTo(6431.5,5449.5,0)
    phase('load',getTimestampMs())
end)
local function work()
    SC.ActionSupervisor.update(s.actor)
    if SC.NativeActions.pacingStatus(s.actor) then return end
    local okay,why=SC.BaseWork.update(s.actor,s.primary,{snapshot={threatCount=0,immediateCount=0}})
    s.work=tostring(okay)..'/'..tostring(why)
end
local function newSort()
    local okay,job=SC.BaseLife.enqueueJob({type='sort',priority=4,target={}})
    check(okay,'ordinary sort job admitted');job.assignedId=s.id;s.job=job.id
end
local function owners()
    local count=0
    for _,entry in ipairs(s.physical) do
        check(entry.item:getID()==entry.id,'physical item identity retained')
        if entry.item:getContainer()==s.stores[entry.expected].container then count=count+1 end
    end
    return count
end
local function step()
    if s.done or s.phase=='menu' then return end
    local now=getTimestampMs()
    if s.lastTick and s.phase~='load' then s.maxGap=math.max(s.maxGap or 0,now-s.lastTick) end;s.lastTick=now
    if s.phase=='load' then
        if now-s.at<12000 then return end
        check(SCBridge and PZOEngine and SC.Actor.checkBridge(true),'actual PZO and production bridge')
        -- This first reviewed failure is deterministic in the baseline negative.
        nativeExpected(assert(instanceItem(SC_STORAGE_CATEGORY_CASES[1].type)),SC_STORAGE_CATEGORY_CASES[1])
        SC.BaseLife.reset()
        check(SC.BaseLife.create(assert(getCell():getGridSquare(6434,5449,0)),'Storage hardening'),'native camp created')
        local base=SC.BaseLife.active();base.settings.autoMaintenance,base.settings.routines,base.settings.workload=false,false,'essential'
        s.stores={}
        for index,category in ipairs({'food','fresh_food','water','medical','tools','construction','crafting','literature',
            'weapons','ammunition','clothing','valuables','farming','manure','general','output'}) do s.stores[category]=crate(index,category) end
        s.expected={};for _,case in ipairs(SC_STORAGE_CATEGORY_CASES) do s.expected[case.type]=case end
        s.baseline={}
        local reader=assert(getFileReader('pzo-storage-role-baseline.txt',false))
        while true do
            local line=reader:readLine();if not line then break end
            local kind,role=line:match('^([^#\t]+)\t([^\t]+)$')
            if kind then s.baseline[kind]=role end
        end
        reader:close()
        s.items=getAllItems();s.writer=assert(getFileWriter('pzo-storage-audit-items.txt',true,false))
        s.writer:write('type\tcategory\tdisplay\tcamp\tcertain\tlogistics\ttags\tstatus\n')
        phase('catalogue',now)
    elseif s.phase=='catalogue' then
        local precise=SC.Performance.preciseNowMs;local started=precise()
        for _=1,8 do
            if s.index>=s.items:size() then
                check(s.errors==0 and s.skipped==0,'complete catalogue has no errors or skipped instances')
                check(s.cases==#SC_STORAGE_CATEGORY_CASES,'every reviewed category case was observed')
                check(s.roles==s.count,'every loadout role was compared with 0.27.40')
                s.writer:close();s.writer=nil
                if not SC_STORAGE_PHYSICAL then return finish(true,'native catalogue, reviewed cases, roles and real destination selectors') end
                s.ticket=assert(SC.Actor.beginSpawn(assert(getCell():getGridSquare(6430,5450,0)),{recruited=true,
                    identity={forename='Storage',surname='Tester',gender='woman',outfit='Generic01'}}))
                phase('spawn',now);return
            end
            local script=s.items:get(s.index);s.index=s.index+1;local kind=script:getFullName()
            local okay,row=pcall(function()
                local item=instanceItem(kind)
                if not item then s.skipped=s.skipped+1;return kind..'\t\t\t\t\t\t\tno_native_instance\n' end
                local wanted,certain=SC.BaseWork.classifyItem(item)
                local role=SC.Logistics.itemCategory(item)
                check(s.baseline[kind]~=nil,'baseline role exists for '..kind)
                if kind=='Base.Garbagebag' then
                    check(role=='container' and not SC.Logistics.isTrash(item),'a reusable native garbage bag is never loose trash')
                else
                    check(role==s.baseline[kind],'loadout role retained for '..kind..': '..tostring(s.baseline[kind])..' -> '..role)
                end
                s.roles=s.roles+1
                local case=s.expected[kind];if case then nativeExpected(item,case);s.cases=s.cases+1 end
                local routes,category,why=SC.BaseWork.floorDestinations(s.primary,item)
                local destination=SC.BaseWork.destinationForCarItem(s.primary,item)
                if #routes==0 then
                    check(category==wanted and why=='floor_storage_full'
                        and not s.stores[wanted].container:hasRoomFor(s.primary,item),
                        'an unroutable item retains native capacity refusal: '..kind)
                    check(destination==nil,'a rejected item cannot escape through an unrelated car fallback: '..kind)
                    s.refused=s.refused+1
                else
                    check(category==wanted and routes[1].destination.category==wanted,'floor destination '..kind..': '..tostring(why))
                    check(destination and destination.category==wanted,'car destination '..kind)
                    s.routes=s.routes+1
                end
                if certain==true then check(SC.Logistics.depositCategory(item,role)==wanted,'logistics destination '..kind) end
                s.count=s.count+1
                return table.concat({field(kind),field(item:getCategory()),field(item:getDisplayCategory()),field(wanted),
                    field(certain),field(role),tags(item),'okay'},'\t')..'\n'
            end)
            if not okay then s.errors=s.errors+1;row=field(kind)..'\t\t\t\t\t\t\tERROR:'..field(row)..'\n' end
            s.writer:write(row)
            if precise()-started>=2 then break end
        end
        if now-(s.progressAt or s.at)>=5000 then
            write('pzo-storage-audit-progress.txt',s.phase..'\nitems='..s.count..'\nerrors='..s.errors..'\n')
            s.progressAt=now
        end
        if now-s.at>360000 then finish(false,'bounded catalogue timed out') end
    elseif s.phase=='spawn' then
        local actor,why=SC.Actor.pollSpawn(s.ticket)
        if not actor then assert(why=='spawn_pending' and now-s.at<15000,tostring(why));return end
        s.actor,s.id=actor,assert(SC.Registry.idOf(actor))
        check(SC.BaseLife.assign(s.id,'quartermaster',true),'native quartermaster assigned')
        check(SC.Commands.issue(s.id,'base_duty',{},s.primary),'native quartermaster ordered to work')
        local stats=actor:getStats();stats:set(CharacterStat.HUNGER,0.05);stats:set(CharacterStat.THIRST,0.05)
        stats:set(CharacterStat.FATIGUE,0.05);stats:set(CharacterStat.ENDURANCE,1)
        s.physical={}
        for _,case in ipairs(SC_STORAGE_CATEGORY_CASES) do if case.physical then
            local item=assert(s.stores.general.container:AddItem(case.type))
            s.physical[#s.physical+1]={item=item,id=item:getID(),expected=case.expected}
        end end
        s.physicalCount=#s.physical;s.jobs=1;newSort();phase('physical-sort',now)
    elseif s.phase=='physical-sort' then
        work()
        local count=owners()
        if now-(s.progressAt or s.at)>=5000 then
            local job=SC.BaseLife.job(s.job)
            write('pzo-storage-audit-progress.txt',s.phase..'\nitems='..s.count..'\ndelivered='..count
                ..'\nwork='..field(s.work)..'\njob='..field(job and job.state)..'\n')
            s.progressAt=now
        end
        if count==s.physicalCount then
            check(s.stores.general.container:getItems():isEmpty(),'General source emptied into typed shelves')
            check(s.stores.output.container:getItems():isEmpty(),'no output fallback was used')
            check(s.actor:getBodyDamage():getOverallBodyHealth()>=99.9,'native worker remains healthy')
            phase('stable',now);return
        end
        local job=SC.BaseLife.job(s.job)
        if not job then
            check(s.jobs<s.physicalCount,'each ordinary batch makes progress')
            s.jobs=s.jobs+1;newSort()
        else assert(job.state~='blocked','physical sorting blocked: '..tostring(job.blocker)..' '..tostring(s.work)) end
        assert(now-s.at<240000,'physical sorting timed out: '..tostring(s.work)..' delivered='..count)
    elseif s.phase=='stable' then
        work();check(owners()==s.physicalCount,'proper shelves retain every exact item without sorting churn')
        if now-s.at>=15000 then finish(true,'full native catalogue, destination agreement, mixed physical sorting and stable exact owners') end
    end
end
Events.OnTick.Add(function()
    if s.done then return end
    local okay,why=pcall(step);if not okay then finish(false,why) end
end)
