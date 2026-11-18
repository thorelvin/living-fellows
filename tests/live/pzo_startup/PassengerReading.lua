-- SPDX-License-Identifier: MIT
-- Disposable world only: real PZO, native seats, native driving and a complete
-- native reading action. No zombie navigation or actor pose/velocity writes.
local SC, state = SurvivorCompanion, {phase='menu',distance=0,maxGap=0}
local function write(name,text)
    local w=assert(getFileWriter(name,true,false),'fixture writer unavailable')
    w:write(text);w:close()
end
local function finish(ok,reason)
    if state.done then return end
    state.done=true
    if state.driver then SC.Driving.hold(state.driver) end
    local text='result='..(ok and 'PASS' or 'FAIL')..'\nphase='..state.phase
        ..'\nreason='..tostring(reason)..'\ndistance='..tostring(state.distance)
        ..'\nmax_tick_gap_ms='..tostring(state.maxGap)..'\nduration_ms='..tostring(state.duration)
        ..'\nnative_max_ticks='..tostring(state.nativeMaxTicks)..'\nactual_chapter_ms='..tostring(state.actualDuration)
        ..'\ncompleted_pages='..tostring(state.pagesAfter)..'\n'
    print('SC_PZO_PASSENGER '..text)
    write('pzo-passenger-result.txt',text)
end
local function phase(name,now)
    state.phase,state.at=name,now
    print('SC_PZO_PASSENGER phase='..name)
    write('pzo-passenger-progress.txt',name..'\n')
end
local function pages()
    local data=state.reader:getModData()
    return data.SC_ReadingPages and data.SC_ReadingPages[state.book:getFullType()] or 0
end
local function prepare(car)
    for index=0,car:getPartCount()-1 do
        local part=car:getPartByIndex(index)
        part:setCondition(100)
        local item=part:getInventoryItem()
        if item then item:setCondition(item:getConditionMax()) end
        if string.find(part:getId(),'Tire',1,true) then
            part:setContainerContentAmount(part:getContainerCapacity())
        end
        local door=part:getDoor();if door then door:setLocked(false) end
    end
    car:updatePartStats()
    local tank=car:getPartById('GasTank')
    if tank then tank:setContainerContentAmount(tank:getContainerCapacity()) end
    local battery=car:getBattery();local item=battery and battery:getInventoryItem()
    if item then item:setCurrentUsesFloat(1) end
end
Events.OnInitGlobalModData.Add(function()
    ModData.getOrCreate(SC.Identity.worldSaveKey).document={
        schema=SC.Identity.saveSchema,companions={},factionActors={}}
end)
Events.OnMainMenuEnter.Add(function()
    MainScreen.continueLatestSave('Sandbox','PzoRestoreFixture')
end)
local seen={}
Events.OnRenderTick.Add(function()
    local modal=MainScreen and MainScreen.instance and MainScreen.instance.checkSavefileModal
    if modal and modal.yes and not seen[modal] then
        seen[modal]=true;modal:onClick(modal.yes)
    end
end)
Events.OnGameStart.Add(function()
    SC.Scheduler.unregister('decision')
    state.primary=assert(getSpecificPlayer(0))
    state.primary:teleportTo(7108.5,8318.5,0)
    phase('load',getTimestampMs())
end)
local function step()
    if state.done or state.phase=='menu' then return end
    local now=getTimestampMs()
    if state.lastTick and state.phase~='load' then
        state.maxGap=math.max(state.maxGap,now-state.lastTick)
    end
    state.lastTick=now
    if state.phase=='load' then
        if now-state.at<12000 then return end
        assert(SCBridge and PZOEngine and SC.Driving.available(),'real PZO/bridge/driving required')
        local square=assert(getCell():getGridSquare(7111,8316,0),'car floor unloaded')
        state.car=assert(addVehicleDebug('Base.CarNormal',IsoDirections.W,nil,square),'native car spawn failed')
        assert(state.car:getSquare(),'native car has no world square')
        prepare(state.car)
        local d=assert(getCell():getGridSquare(7111,8313,0))
        local r=assert(getCell():getGridSquare(7109,8313,0))
        state.driverTicket=assert(SC.Actor.beginSpawn(d,{recruited=true,
            identity={forename='TripDriver',surname='Fixture',gender='woman',outfit='Generic01'}}))
        state.readerTicket=assert(SC.Actor.beginSpawn(r,{recruited=true,
            identity={forename='TripReader',surname='Fixture',gender='woman',outfit='Generic01'}}))
        phase('actors',now)
    elseif state.phase=='actors' then
        if not state.driver then
            local actor,why=SC.Actor.pollSpawn(state.driverTicket)
            if actor then state.driver=actor else assert(why=='spawn_pending',tostring(why)) end
        end
        if not state.reader then
            local actor,why=SC.Actor.pollSpawn(state.readerTicket)
            if actor then state.reader=actor else assert(why=='spawn_pending',tostring(why)) end
        end
        if not state.driver or not state.reader then
            assert(now-state.at<15000,'native companion spawn timed out');return
        end
        if now-state.at<2500 then return end
        state.driver:getInventory():AddItem(state.car:createVehicleKey())
        assert(state.car:enter(0,state.driver)==true,'native driver entry failed')
        assert(state.car:enter(1,state.reader)==true,'native reader entry failed')
        assert(state.car:enter(2,state.primary)==true,'native primary passenger entry failed')
        assert(state.car:getDriver()==state.driver and state.car:getSeat(state.reader)==1,
            'native seats do not match the fixture')
        state.book=assert(state.reader:getInventory():AddItem('Base.BookCarpentry1'),'native book missing')
        assert(state.book:getNumberOfPages()==220,'pinned native chapter book changed')
        state.book:getModData().SC_PzoPassengerReceipt='read-02739'
        assert(SC.Commands.issue(SC.Registry.idOf(state.reader),'follow',nil,state.primary))
        assert(SC.Downtime.canReadOnTrip(state.reader,state.primary),'native passenger is not eligible')
        assert(not SC.Downtime.canReadOnTrip(state.driver,state.primary),'driver was allowed to read')
        phase('reading',now)
    elseif state.phase=='reading' then
        SC.Downtime.update(state.reader,state.primary,{snapshot={threatCount=0,immediateCount=0}},'read')
        local active=SC.Downtime.peek(state.reader).active
        if not active then assert(now-state.at<30000,'native passenger reading did not start');return end
        assert(active.kind=='read','unexpected passenger activity')
        local visual=SC.NativeActions.visualStatus(state.reader,'read')
        if visual~='active' then assert(now-state.at<30000,'native read animation did not become active: '..tostring(visual));return end
        state.token=assert(SC.ActionSupervisor.current(state.reader),'reading token missing')
        state.duration=active.durationMs
        state.readStarted=now
        state.pagesBefore=pages()
        state.startX,state.startY=state.car:getX(),state.car:getY()
        assert(SC.Driving.start(state.driver,state.primary),'native driving did not start')
        assert(SC.Driving.cruise(state.driver,8,0,true),'native cruise refused')
        phase('moving',now)
    elseif state.phase=='moving' then
        state.distance=math.sqrt((state.car:getX()-state.startX)^2+(state.car:getY()-state.startY)^2)
        SC.ActionSupervisor.update(state.reader)
        local summary=SC.ActionSupervisor.summary(state.reader,true)
        assert(SC.ActionSupervisor.isCurrent(state.token),
            'moving passenger lost reading: '..tostring(summary.lastFailure and summary.lastFailure.reason))
        SC.Downtime.update(state.reader,state.primary,{snapshot={threatCount=0,immediateCount=0}},'read')
        assert(state.reader:getVehicle()==state.car and state.car:getSeat(state.reader)==1,'passenger seat lost')
        assert(pages()==state.pagesBefore,'unfinished moving chapter credited pages')
        if state.distance>=8 then SC.Driving.hold(state.driver);phase('complete-chapter',now)
        else assert(now-state.at<30000,'native car did not travel eight metres') end
    elseif state.phase=='complete-chapter' then
        local visual=SC.NativeActions.visualToken(state.reader,'read')
        if visual then state.nativeMaxTicks=visual.maxTime end
        SC.ActionSupervisor.update(state.reader)
        SC.Downtime.update(state.reader,state.primary,{snapshot={threatCount=0,immediateCount=0}},'read')
        if SC.Downtime.peek(state.reader).active then
            -- Vanilla adjusts maxTime for moodles and the actor's native time
            -- modifier. Honor the production supervisor's existing 2x window.
            assert(now-state.at<state.duration*2+15000,'native chapter timed out');return
        end
        state.actualDuration=now-state.readStarted
        state.pagesAfter=pages()
        assert(state.pagesAfter==state.pagesBefore+11,'native chapter did not grant exactly one eleven-page chapter')
        assert(state.book:getContainer()==state.reader:getInventory(),'native book changed owner')
        phase('second-chapter',now)
    elseif state.phase=='second-chapter' then
        SC.Downtime.update(state.reader,state.primary,{snapshot={threatCount=0,immediateCount=0}},'read')
        local active=SC.Downtime.peek(state.reader).active
        if not active then
            local repeatDelay=SC.Config.get('ambientRepeatCooldownMs')
            assert(now-state.at<(tonumber(repeatDelay) or 60000)+30000,'second chapter did not start')
            return
        end
        local token=SC.ActionSupervisor.current(state.reader)
        if not token or SC.NativeActions.visualStatus(state.reader,'read')~='active' then return end
        state.car:exit(state.reader)
        assert(state.reader:getVehicle()==nil,'native passenger exit failed')
        SC.ActionSupervisor.update(state.reader)
        assert(not SC.ActionSupervisor.isCurrent(token),'leaving the car retained the reading owner')
        assert(pages()==state.pagesAfter,'interrupted chapter granted pages')
        assert(state.book:getContainer()==state.reader:getInventory(),'interruption lost the marked book')
        assert(SC.ActionSupervisor.summary(state.reader,true).lastFailure.reason=='passenger_read_interrupted',
            'native exit used the wrong interruption reason')
        phase('soak',now)
    elseif state.phase=='soak' then
        assert(pages()==state.pagesAfter,'completed chapter was credited twice')
        if now-state.at>=60000 then
            assert(state.reader:getBodyDamage():getOverallBodyHealth()>=99.9,'native reader was injured')
            finish(true,'moving native chapter, exact pages/book, driver exclusion, native exit and 60-second soak')
        end
    end
end
Events.OnTick.Add(function()
    if state.done then return end
    local ok,why=pcall(step)
    if not ok then finish(false,why) end
end)
