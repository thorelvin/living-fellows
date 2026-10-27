-- SPDX-License-Identifier: MIT
-- A normal native scout trip launched and recalled through the PC session.
local mode=LF_CONTROLS_TRIP_MODE or "tripwalk"
local run={step=0,next=0}
local function log(text)
    print("EMMA_TRIP|"..text)
    local writer=getFileWriter("SurvivorCompanionHarness/terminal-controls-"..mode..".log",true,true)
    if writer then writer:write(text.."\n") writer:close() end
end
local function order(window,request)
    local actions=SurvivorCompanion.TerminalActions
    local ticket,prompt=actions.prepare(window,{kind="control",request=request})
    if not ticket then return false,prompt end
    return actions.execute(window,ticket)
end
local function tick()
    local SC=SurvivorCompanion local player=getSpecificPlayer(0) local now=getTimestampMs()
    if now<run.next or not player or not SC or not SC.TerminalServices then return end
    if run.step==0 then
        player:setGodMod(true) player:setGhostMode(true) player:teleportTo(12036.5,6739.5,0)
        run.step,run.next=1,now+6000
    elseif run.step==1 then
        local square=getCell():getGridSquare(12035,6739,0)
        for i=0,square:getObjects():size()-1 do local object=square:getObjects():get(i)
            if SC.Terminal.isComputer(object) then run.pc=object end
        end
        assert(run.pc,"original desktop not loaded")
        local _,access=SC.GameplayUtil.directInteractionAccess(player,run.pc)
        local target=assert(access[1]) player:teleportTo(target:getX()+0.5,target:getY()+0.5,target:getZ())
        local inv=player:getInventory()
        inv:AddItem("Base.Screwdriver") inv:AddItem("Base.ElectricWire") inv:AddItem("Base.ElectronicsScrap") inv:AddItem("Base.ElectronicsScrap")
        for _=1,10 do if player:getPerkLevel(Perks.Electricity)<2 then player:LevelPerk(Perks.Electricity) end end
        local radio=inv:AddItem("Base.WalkieTalkie5")
        radio:getDeviceData():setChannel(88100)
        assert(SC.TerminalHardware.install(player,run.pc,"radio",radio))
        run.records={}
        for _,actor in ipairs(SC.Registry.living()) do
            local id=SC.Registry.idOf(actor) local record=SC.Registry.byId(id)
            if record and record.recruited and not SC.ExpeditionPrototype.isMember(actor) and #run.records<1 then
                assert(SC.Commands.issue(id,"follow",nil,player))
                actor:setGodMod(true) actor:setGhostMode(true)
                local crewRadio=actor:getInventory():AddItem("Base.WalkieTalkie5")
                local data=crewRadio:getDeviceData() data:setChannel(88100) data:setHasBattery(true) data:setPower(0.9)
                data:setIsTurnedOn(true) data:setDeviceVolume(0.3) data:setMicIsMuted(false)
                actor:setSecondaryHandItem(crewRadio) run.records[#run.records+1]=record
            end
        end
        assert(#run.records==1,"no recruited crew available")
        if mode=="tripdrive" then
            local nearest,distance
            for _,vehicle in ipairs(SC.Vehicle.loadedVehicles()) do
                local x,y=vehicle:getX(),vehicle:getY()
                local d=(x-12035)^2+(y-6739)^2
                local score=d+(vehicle:getScriptName():find("Taxi",1,true) and 100000 or 0)
                if d<50^2 and (not distance or score<distance) then nearest,distance=vehicle,score end
            end
            local car=assert(nearest,"no loaded native car near the fixture camp")
            local cx,cy=math.floor(car:getX()),math.floor(car:getY())
            log("CAR_FIXTURE "..car:getScriptName().." at="..cx..","..cy.." parking="..#SC.ExpeditionCar.parkingAreas())
            local okay,why=SC.BaseLife.beginZone("parking",getCell():getGridSquare(cx-2,cy-3,0))
            assert(okay,"native parking start: "..tostring(why))
            okay,why=SC.BaseLife.finishZone(getCell():getGridSquare(cx+2,cy+3,0),"Station acceptance parking")
            assert(okay,"native parking finish: "..tostring(why))
            car:repair() car:setHotwired(true)
            local tank=car:getPartById("GasTank") tank:setContainerContentAmount(tank:getContainerCapacity())
            local battery=car:getPartById("Battery"):getInventoryItem() battery:setUsedDelta(1)
            log("CAR_FIXTURE native parking and service supplies ready")
        end
        assert(SC.Terminal.use(player,run.pc))
        run.step,run.next,run.deadline=2,now+500,now+30000
    elseif run.step==2 then
        local window=SC.Terminal.window
        if not window then assert(now<run.deadline,"terminal never opened") run.next=now+500 return end
        window:flush()
        if window.system.locked then
            SC.TerminalSystem.ensurePuzzle(window.system,4)
            window.entry.javaObject:SetText(window.system.puzzle.answer) window.entry.javaObject:onKeyEnter() window:flush()
        end
        local x,y=SC.GameplayUtil.position(run.records[1].actor)
        local places,lookupReason,total=SC.ExpeditionPrototype.placeCandidates(run.records[1].id,1)
        log("PLACES count="..tostring(places and #places).." total="..tostring(total).." reason="..tostring(lookupReason).." actor="..x..","..y)
        if not places then
            run.lookupDeadline=run.lookupDeadline or now+60000
            assert(now<run.lookupDeadline,"destination lookup: "..tostring(lookupReason)) run.next=now+2000 return
        end
        local selected
        for _,place in ipairs(places or {}) do
            local approach,why=SC.ExpeditionPlaces.plannedApproach(place,run.records[1].actor)
            if not approach then log("APPROACH "..tostring(place.id).." "..tostring(why)) end
            if approach and (approach.x-x)^2+(approach.y-y)^2>25^2 then selected=place break end
        end
        run.place=assert(selected,"no normal nearby scout destination")
        window.stationDraft={kind="scout",travelMode=mode=="tripdrive" and "drive" or "road",quantity=4,category="food",hours=2,
            crew={run.records[1].id},placeId=selected.id}
        run.step,run.next,run.deadline=3,now+1000,now+45000
    elseif run.step==3 then
        local window=SC.Terminal.window
        local okay,reason=SC.TerminalServices.review(window)
        if not okay then
            log("REVIEW "..tostring(reason)) assert(now<run.deadline,"station review never completed: "..tostring(reason)) run.next=now+2000 return
        end
        local okay,reason=order(window,{operation="launch"})
        assert(okay,"station launch failed: "..tostring(reason))
        run.trip=assert(SC.ExpeditionPrototype.current())
        log("PASS station launched normal scout "..mode.." destination="..run.place.label)
        run.step,run.next,run.deadline=4,now+1000,now+150000
    elseif run.step==4 then
        local trip=SC.ExpeditionPrototype.current()
        assert(trip,"expedition ended before station report")
        local leader=trip.leader.actor local x,y=SC.ControlUtil.position(leader) local sx,sy=SC.ControlUtil.position(run.pc)
        local car=trip.scout.vehicle
        if car and car.state=="abandoned" then error("normal driving expedition abandoned its car: "..tostring(car.reason or car.endReason)) end
        if car and car.state~="driving_out" then assert(now<run.deadline,"car never began its outbound drive: "..tostring(car.state)) run.next=now+1000 return end
        if math.abs(x-sx)<3 or math.abs(y-sy)<3 then assert(now<run.deadline,"leader did not depart the camp") run.next=now+1000 return end
        local okay,reason=order(SC.Terminal.window,{operation="radio",command="progress_report",payload="status"})
        if not okay then log("REPORT "..tostring(reason)) assert(now<run.deadline,"station never received native report") run.next=now+1000 return end
        assert(trip.lastProgressReport and trip.lastProgressReport.kind=="scout","station did not record real scouting report")
        log("PASS native two-way station report: "..tostring(reason))
        okay,reason=order(SC.Terminal.window,{operation="radio",command="return_now",payload="now"})
        assert(okay,"station recall failed: "..tostring(reason))
        log("PASS native station recall")
        run.carSql=car and car.sqlId
        log("CONTEXT terminal remains open during native view return")
        run.step,run.next,run.deadline=5,now+1000,now+180000
    elseif run.step==5 then
        local trip=SC.ExpeditionPrototype.current()
        if trip then
            local car=trip.scout.vehicle
            if car and car.state=="abandoned" and not run.roadside then
                local vehicle=assert(SC.Vehicle.loadedBySqlId(car.sqlId),"fallback car disappeared")
                assert(not vehicle:isEngineRunning(),"roadside fallback left engine running")
                run.roadside=true log("LIMIT native parking fallback; car stopped; crew continuing home on foot")
            end
            if trip.scout.phase=="awaiting_player" and not run.meeting then
                local finished,why=SC.ExpeditionPrototype.finishAtPlayer(player)
                log("RETURN_CHECK "..tostring(finished).." "..tostring(why))
                if not finished then
                    local square=getCell():getGridSquare(12031,6746,0)
                    ISTimedActionQueue.add(ISWalkToTimedAction:new(player,square))
                    run.meeting=true log("CONTEXT main player walking into the kitchen to meet returned crew")
                end
            end
            assert(now<run.deadline,"normal station expedition did not finish returning") run.next=now+1000 return
        end
        assert(getSpecificPlayer(0)==player and getSpecificPlayer(1)==nil,"return did not restore solo player ownership")
        assert(not run.records[1].actor:isDead(),"returning crew died")
        if run.carSql then
            local car=assert(SC.Vehicle.loadedBySqlId(run.carSql),"returned car disappeared")
            assert(not car:isEngineRunning(),"returned car engine is still running")
        end
        run.step,run.next,run.deadline=6,now+500,now+30000
    elseif run.step==6 then
        local window=SC.Terminal.window
        if not window then assert(now<run.deadline,"terminal did not reopen after solo return") run.next=now+500 return end
        window:flush() SC.TerminalServices.input(window,"expedition station") window:flush()
        getCore():TakeFullScreenshot("emma-controls-"..mode)
        log("PASS solo return, living crew and stopped car")
        log("PASS native terminal controls "..mode.." acceptance complete")
        run.step,run.next=99,now+1000000
    end
end
Events.OnTick.Add(function()
    local okay,reason=pcall(tick)
    if not okay then log("FAIL "..tostring(reason)) run.step,run.next=99,getTimestampMs()+1000000 end
end)
