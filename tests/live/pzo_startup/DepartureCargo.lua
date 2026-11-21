-- SPDX-License-Identifier: MIT
-- Focused native departure test, not a complete wood collection trip. Seed a
-- cold sorting receipt using real native objects, then dispatch two recruits.
local SC, s = SurvivorCompanion, { phase='menu', checks=0, crew={}, items={} }
local function write(name,value) local w=assert(getFileWriter(name,true,false));w:write(value);w:close() end
local function check(ok,why) s.checks=s.checks+1;assert(ok,'departure cargo '..s.checks..': '..tostring(why)) end
local function phase(name) s.phase,s.at=name,getTimestampMs();write('pzo-departure-cargo-progress.txt',name..'\n') end
local function finish(ok,why)
    if s.done then return end;s.done=true
    write('pzo-departure-cargo-result.txt','result='..(ok and 'PASS' or 'FAIL')..'\nphase='..s.phase
        ..'\nchecks='..s.checks..'\nreason='..tostring(why)..'\nlast_work='..tostring(s.work)..'\n')
end
local function crate(x,category)
    local q=assert(getCell():getGridSquare(x,5449,0))
    local object=IsoThumpable.new(getCell(),q,'carpentry_01_16',false,{})
    object:setIsContainer(true);object:setContainer(ItemContainer.new('crate',q,object))
    object:getContainer():setCapacity(100);object:getContainer():setExplored(true)
    q:AddSpecialObject(object);q:RecalcAllWithNeighbours(true)
    local ok,row=SC.BaseLife.registerStorage(object,category);check(ok,'real marked crate: '..category)
    return row,object:getContainer()
end
local function spawn()
    local n=#s.crew+1
    s.ticket=assert(SC.Actor.beginSpawn(assert(getCell():getGridSquare(6429+n,5450,0)),
        {recruited=true,identity={forename=n==1 and 'Mike' or 'Kelly',surname='Departure',gender='woman',outfit='Generic01'}}))
    phase('spawn')
end
local function savedCargo(record,source,destination)
    local inv=record.actor:getInventory()
    -- Put the real claimed item past multiple 256-item recovery slices.
    for _=1,520 do assert(inv:AddItem('Base.Paperclip')) end
    local carried=assert(inv:AddItem('Base.Money'))
    local foreign=assert(s.primary:getInventory():AddItem('Base.Money'))
    local ok,job=SC.BaseLife.enqueueJob({type='sort',target={}});check(ok,'saved sorting job created')
    job.reservedBy,job.assignedId,job.state=record.id,record.id,'active'
    job.target.stockBatch={owner=record.id,sourceId=source.id,destinationId=destination.id,
        ids={carried:getID(),foreign:getID()},phase='deposit',assigned=true}
    carried:getModData().LF_SortBatchJob=job.id;foreign:getModData().LF_SortBatchJob=job.id
    s.items[#s.items+1]={actor=record.actor,carried=carried,foreign=foreign,job=job}
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
    SC.Scheduler.unregister('decision');SC.Scheduler.unregister('base-maintenance')
    s.primary=assert(getSpecificPlayer(0));s.primary:teleportTo(6428.5,5449.5,0);phase('load')
end)
local function step()
    if s.done or s.phase=='menu' then return end
    local now=getTimestampMs()
    if s.phase=='load' then
        if now-s.at<12000 then return end
        check(SCBridge and PZOEngine and SC.Actor.checkBridge(true),'real PZO 2.2 and production bridge')
        SC.BaseLife.reset();SC.Logistics.reset()
        check(SC.BaseLife.create(assert(getCell():getGridSquare(6428,5449,0)),'Departure cargo'),'real camp')
        local base=SC.BaseLife.active();base.settings.autoMaintenance=false;base.settings.routines=false
        base.settings.workload='essential'
        s.source,s.sourceContainer=crate(6434,'general')
        s.destination,s.destinationContainer=crate(6435,'construction')
        spawn()
    elseif s.phase=='spawn' then
        local actor,why=SC.Actor.pollSpawn(s.ticket)
        if not actor then assert(why=='spawn_pending' and now-s.at<15000,tostring(why));return end
        local id=assert(SC.Registry.idOf(actor));local record=assert(SC.Registry.byId(id))
        s.crew[#s.crew+1]=record
        check(SC.BaseLife.assign(id,'generalist',true),'crew camp duty')
        check(SC.Commands.issue(id,'base_duty',{},s.primary),'stored base duty order')
        local stats=actor:getStats();stats:set(CharacterStat.HUNGER,.05);stats:set(CharacterStat.THIRST,.05)
        stats:set(CharacterStat.FATIGUE,.05);stats:set(CharacterStat.ENDURANCE,1)
        local bag=assert(actor:getInventory():AddItem('Base.Bag_BigHikingBag'))
        actor:setClothingItem_Back(bag)
        if #s.crew==1 then
            local axe=assert(actor:getInventory():AddItem('Base.Axe'));actor:setPrimaryHandItem(axe)
            actor:setSecondaryHandItem(axe);spawn();return
        end
        savedCargo(s.crew[1],s.source,s.destination);savedCargo(s.crew[2],s.source,s.destination)
        -- Ordinary cancellation remains strict; expedition's explicit handoff
        -- alone may retire stale work affinity, never the foreign native item.
        for _,row in ipairs(s.items) do
            local stopped,reason
            for _=1,8 do stopped,reason=SC.BaseWork.cancel(row.actor,'ordinary_cancel');if reason~='haul_cargo_search_pending' then break end end
            check(not stopped and reason=='haul_cargo_owner_unknown' and row.job.target.stockBatch,
                'ordinary cancellation refuses unresolved native cargo')
        end
        local site={id='native-departure-fixture',label='Departure-only forest fixture',type='Forest',
            anchor={x=6470,y=5449,z=0},bounds={x1=6462,y1=5441,x2=6478,y2=5457,z=0},distance=40}
        local ok,reason=SC.ExpeditionPrototype.start(s.crew,{kind='wood',travelMode='straight',
            destination=site.anchor,wood={version=1,request={mode='count',quantity=2},sites={site},siteIndex=1,
                acquisitions={},preparation=true,preparationReason='wood_preparing_axes',workers={},loans={}}})
        check(ok,'public two-member wood mission: '..tostring(reason));phase('handoff')
    elseif s.phase=='handoff' then
        if s.lastUpdate and now-s.lastUpdate<300 then return end;s.lastUpdate=now
        local settled=0
        for _,record in ipairs(s.crew) do
            SC.ActionSupervisor.update(record.actor)
            local handled,why=SC.Decision.update(record.actor,s.primary,{},now)
            s.work=record.id..':'..tostring(handled)..'/'..tostring(why)
        end
        for _,row in ipairs(s.items) do
            check(row.foreign:getContainer()==s.primary:getInventory(),'foreign item stays with player')
            check(row.carried:getContainer()==row.actor:getInventory(),'carried item retains exact native owner')
            if not row.job.target.stockBatch then settled=settled+1 end
        end
        if settled==2 then
            for _,row in ipairs(s.items) do
                check(row.carried:getModData().LF_BaseReturnOwner==SC.Registry.idOf(row.actor),
                    'verified carried camp cargo remains accountable')
                check(not SC.SortBatch.protected(row.carried) and not SC.SortBatch.protected(row.foreign),
                    'old sorting claims retired for both crew')
            end
            check(#SC.ExpeditionPrototype.current().roster==2,'both original native companions remain in squad')
            finish(true,'both wood expedition handoffs progressed past cold stale sorting receipts; exact items retained')
        end
        assert(now-s.at<20000,'squad departure still blocked by previous camp cargo: '..tostring(s.work))
    end
end
Events.OnTick.Add(function() if s.done then return end;local ok,why=pcall(step);if not ok then finish(false,why) end end)
