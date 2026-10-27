-- SPDX-License-Identifier: MIT
-- Disposable-world acceptance at an original map PC. Tools and hardware are
-- fixture supplies; the desktop, doors, lighting and power are native scenery.
local run={step=0,next=0,deadline=0}
local function log(text)
    print("EMMA_CONTROLS|"..text)
    local writer=getFileWriter("SurvivorCompanionHarness/terminal-controls.log",true,true)
    if writer then writer:write(text.."\n") writer:close() end
end
local function shot(name) getCore():TakeFullScreenshot("emma-controls-"..name) log("SHOT "..name) end
local function pcAt(x,y,z)
    local square=getCell():getGridSquare(x,y,z)
    if square then for i=0,square:getObjects():size()-1 do
        local object=square:getObjects():get(i)
        if SurvivorCompanion.Terminal.isComputer(object) then return object end
    end end
end
local function stand(player,object)
    local SC=SurvivorCompanion
    local _,targets=SC.GameplayUtil.directInteractionAccess(player,object)
    for _,square in ipairs(targets) do
        if SC.GameplayUtil.isSquareFree(square) and SC.GameplayUtil.squareOccupyingObject(square)==nil then
            player:teleportTo(square:getX()+0.5,square:getY()+0.5,square:getZ()) return true
        end
    end
    return false
end
local function tick()
    local SC=SurvivorCompanion local player=getSpecificPlayer(0) local now=getTimestampMs()
    if now<run.next or not SC or not SC.TerminalServices or not player or not player:getCurrentSquare() then return end
    if run.step==0 then
        player:setGodMod(true) player:setGhostMode(true)
        if SC.UI and SC.UI.instance then SC.UI.instance:setVisible(false) end
        player:teleportTo(12036.5,6739.5,0)
        run.step,run.next,run.deadline=1,now+6000,now+45000
    elseif run.step==1 then
        run.computer=pcAt(12035,6739,0)
        if not run.computer then assert(now<run.deadline,"original camp desktop did not stream") run.next=now+500 return end
        assert(stand(player,run.computer),"no clear interaction tile at original desktop")
        assert(SC.Terminal.powered(run.computer),"original desktop lacks real power")
        local inv=player:getInventory()
        for _=1,8 do inv:AddItem("Base.ElectricWire") end
        for _=1,20 do inv:AddItem("Base.ElectronicsScrap") end
        inv:AddItem("Base.Screwdriver")
        for _=1,10 do if player:getPerkLevel(Perks.Electricity)<4 then player:LevelPerk(Perks.Electricity) end end
        run.radio=inv:AddItem("Base.WalkieTalkie2") run.radio:getModData().LF_Acceptance="station-exact-radio"
        run.battery=inv:AddItem("Base.CarBattery1") run.battery:setUsedDelta(0.8)
        run.battery:setCondition(run.battery:getConditionMax())
        run.battery:getModData().LF_Acceptance="station-exact-battery"
        run.radioId,run.batteryId=run.radio:getID(),run.battery:getID()
        run.radioPower=run.radio:getDeviceData():getPower()
        local packed=SCBridge.packTerminalItem(run.radio)
        assert(type(packed)=="string","native radio serialization failed")
        local unpacked=SCBridge.unpackTerminalItem(packed)
        assert(unpacked and unpacked:getID()==run.radioId and unpacked:getModData().LF_Acceptance=="station-exact-radio","native item serialization lost identity or mod data")
        log("PASS native item serialization radioId="..run.radioId.." batteryId="..run.batteryId)
        assert(SC.Terminal.use(player,run.computer),"native Use computer action refused")
        run.step,run.next,run.deadline=2,now+1000,now+30000
    elseif run.step==2 then
        local window=SC.Terminal.window
        if not window then assert(now<run.deadline,"native terminal action never opened") run.next=now+500 return end
        window:flush()
        if window.system.locked then
            SC.TerminalSystem.ensurePuzzle(window.system,player:getPerkLevel(Perks.Electricity))
            window.entry.javaObject:SetText(window.system.puzzle.answer) window.entry.javaObject:onKeyEnter() window:flush()
        end
        assert(SC.BuildingControls.connect(player,run.computer),"building connection failed")
        run.panel=SC.BuildingControls.panel(run.computer,false)
        if run.panel.security.locked then
            SC.TerminalSystem.ensurePuzzle(run.panel.security,4)
            assert(SC.BuildingControls.security(run.computer,run.panel.security.puzzle.answer,4),"building recovery failed")
        end
        assert(SC.TerminalServices.install(player,run.computer,function() return SC.TerminalHardware.install(player,run.computer,"radio",run.radio) end))
        run.step,run.next,run.deadline=3,now+500,now+30000
    elseif run.step==3 then
        local hardware=SC.TerminalHardware.state(run.computer,false)
        if not hardware or not hardware.radio then assert(now<run.deadline,"native radio installation did not complete") run.next=now+500 return end
        assert(hardware.radio.id==run.radioId and not SC.ControlUtil.owns(player,run.radio),"mounted radio has duplicate or changed ownership")
        log("PASS native timed radio installation")
        local accepted,reason,action=SC.TerminalServices.install(player,run.computer,function()
            local okay,why=SC.TerminalHardware.install(player,run.computer,"ups",run.battery)
            log("BACKUP_INSTALL result="..tostring(okay).." reason="..tostring(why).." condition="..run.battery:getCondition().." charge="..tostring(SC.ControlUtil.charge(run.battery)))
            return okay,why
        end)
        assert(accepted,tostring(reason)) run.backupAction=action
        run.step,run.next,run.deadline=4,now+500,now+30000
    elseif run.step==4 then
        local hardware=SC.TerminalHardware.state(run.computer,false)
        if not hardware.ups then
            if now>=run.deadline then log("BACKUP_ACTION done="..tostring(run.backupAction and run.backupAction.done).." result="..tostring(run.backupAction and run.backupAction.lastReason)) end
            assert(now<run.deadline,"native backup installation did not complete") run.next=now+500 return
        end
        assert(hardware.ups.id==run.batteryId,"backup battery identity changed")
        run.endpoint=assert(SC.RadioEndpoints.station(player,run.computer))
        assert(SC.RadioEndpoints.validate(player,run.endpoint),"station endpoint unavailable")
        local square=run.endpoint.receiver:getSquare()
        assert(square==run.computer:getSquare(),"world receiver is not at the real PC")
        assert(getSpecificPlayer(0)==player and getSpecificPlayer(1)==nil,"station changed player ownership")
        run.endpoint.data:setChannel(88100)
        log("RECEIVER on="..tostring(run.endpoint.data:getIsTurnedOn()).." volume="..tostring(run.endpoint.data:getDeviceVolume())
            .." iso="..tostring(run.endpoint.data:isIsoDevice()).." channel="..tostring(run.endpoint.data:getChannel())
            .." power="..tostring(run.endpoint.data:getPower()).." nearby="..tostring(run.endpoint.receiver:HasPlayerInRange()))
        assert(SC.TerminalHardware.flush(run.computer))
        local exact=SC.TerminalHardware.restorePart(hardware.radio)
        assert(exact:getID()==run.radioId and exact:getModData().LF_Acceptance=="station-exact-radio","mounted payload lost native item identity")
        assert(math.abs(exact:getDeviceData():getPower()-run.radioPower)<0.0001,"station changed original battery charge")
        log("PASS mounted receiver and original battery isolation")
        local window=SC.Terminal.window window:flush()
        SC.TerminalServices.input(window,"expedition station") window:flush()
        run.step,run.next=5,now+4500
    elseif run.step==5 then
        shot("station")
        run.received=false
        run.radioHook=function(guid,codes,x,y,z,message,device)
            if tostring(guid)=="LF-CONTROL-ACCEPTANCE" then
                log("RX device="..tostring(device).." expected="..tostring(run.endpoint.receiver).." text="..tostring(message))
                if device==run.endpoint.receiver then run.received=true end
            end
        end
        Events.OnDeviceText.Add(run.radioHook)
        local x,y=SC.ControlUtil.position(run.computer)
        -- Vanilla suppresses world-radio reception when either source axis is
        -- identical to the receiver. Use a distinct physical source on both.
        ZomboidRadio.getInstance():SendTransmission(x+3,y+3,88100,"Expedition station receiver check.","LF-CONTROL-ACCEPTANCE","RX-1",0.8,0.9,1,1200,false)
        run.step,run.next=6,now+4000
    elseif run.step==6 then
        Events.OnDeviceText.Remove(run.radioHook)
        assert(run.received,"native station radio did not receive a real transmission")
        log("PASS native world radio reception")
        local window=SC.Terminal.window window:flush()
        SC.TerminalServices.input(window,"building services") window:flush()
        run.step,run.next=7,now+4000
    elseif run.step==7 then
        shot("services")
        local rows=SC.BuildingControls.list(run.computer)
        log("EQUIPMENT count="..#rows.." profile="..run.panel.label)
        for _,row in ipairs(rows) do log("DEVICE "..row.kind.." "..row.label.." "..SC.BuildingControls.status(row)) end
        assert(#rows>0,"no native equipment was discovered")
        local row
        for _,candidate in ipairs(rows) do
            local object=SC.BuildingControls.resolve(candidate)
            if candidate.kind=="door" and object then
                local blocked=SCBridge.isControlDoorObstructed(object)
                log("CLEARANCE "..candidate.label.." blocked="..tostring(blocked).." reason="..SCBridge.controlDoorClearanceDiagnostic())
                if not blocked then row=candidate break end
            end
        end
        assert(row,"no native door discovered")
        run.doorRow=row run.door=SC.BuildingControls.resolve(row)
        SC.Terminal.window:close()
        assert(stand(player,run.door),"no real access tile at native door")
        run.step,run.next=70,now+1500
    elseif run.step==70 then
        local okay,reason=SC.BuildingControls.install(player,run.computer,run.doorRow.id,"relay")
        assert(okay,"lock relay installation failed: "..tostring(reason))
        okay,reason=SC.BuildingControls.install(player,run.computer,run.doorRow.id,"motor")
        assert(okay,"motor installation failed: "..tostring(reason))
        local footprint=run.door:getOppositeSquare()
        player:teleportTo(footprint:getX()+0.5,footprint:getY()+0.5,footprint:getZ())
        run.step,run.next=71,now+1500
    elseif run.step==71 then
        assert(SCBridge.isControlDoorObstructed(run.door),"door footprint failed to see a real standing player")
        local x,y,z=SC.ControlUtil.position(run.computer)
        player:teleportTo(x+4.5,y+4.5,z)
        run.step,run.next=8,now+2000
    elseif run.step==8 then
        if SCBridge.isControlDoorObstructed(run.door) then
            log("DOOR_OBSTRUCTED "..run.doorRow.label)
            error("original door remains occupied; choose a clear fixture")
        end
        local ticket=assert(SC.BuildingControls.prepare(run.computer,"unlock",run.doorRow.id,player))
        local okay,reason=SC.BuildingControls.execute(ticket)
        assert(okay,"native unlock failed: "..tostring(reason))
        assert(SC.BuildingControls.execute(ticket)==false,"native command replayed")
        local before=SC.BuildingControls.status(run.doorRow)
        ticket=assert(SC.BuildingControls.prepare(run.computer,before=="Open" and "close" or "open",run.doorRow.id,player))
        okay,reason=SC.BuildingControls.execute(ticket)
        assert(okay,"native door movement failed: "..tostring(reason))
        assert(SC.BuildingControls.status(run.doorRow)~=before,"native door state did not change")
        log("PASS native door obstruction, lock and movement")
        assert(stand(player,run.computer))
        local hardware=SC.TerminalHardware.state(run.computer,false)
        assert(SC.TerminalHardware.beforePickup(run.computer))
        local roundTrip=SC.TerminalHardware.restorePart(hardware.ups)
        assert(roundTrip:getID()==run.batteryId and roundTrip:getModData().LF_Acceptance=="station-exact-battery","backup payload lost identity")
        log("PASS native exact backup payload")
        run.step,run.next=9,now+1500
    elseif run.step==9 then
        local pc=run.computer local square=pc:getSquare() local sprite=pc:getSprite():getName()
        local props=ISMoveableSpriteProps.new(sprite)
        local memory=SC.Terminal.computerState(player,pc).identity
        local furniture=props:pickUpMoveableInternal(player,square,pc,nil,sprite,true,true)
        assert(furniture and SC.ControlUtil.owns(player,furniture),"native furniture pickup lost PC")
        local hardware=furniture:getModData().movableData.LF_TerminalHardware
        assert(hardware and hardware.radio.id==run.radioId and hardware.ups.id==run.batteryId,"assembly pickup lost hardware")
        assert(not SC.BuildingControls.connected(pc,run.panel),"moving PC retained building connection")
        assert(SC.RadioEndpoints.validate(player,run.endpoint)==false,"packed station retained radio authority")
        props:placeMoveable(player,square,sprite,true)
        assert(not SC.ControlUtil.owns(player,furniture),"native placement retained duplicate assembly")
        run.computer=assert(pcAt(square:getX(),square:getY(),square:getZ()),"native desktop was not placed")
        assert(SC.Terminal.computerState(player,run.computer).identity==memory,"placement lost computer memory")
        assert(SC.TerminalHardware.state(run.computer,false).radio.id==run.radioId,"placed hardware changed identity")
        log("PASS native complete assembly pickup and placement")
        run.step,run.next=10,now+1500
    elseif run.step==10 then
        -- The baseline harness carries a large combat kit. Put spare supplies
        -- down physically so the native removal uses ordinary carrying limits.
        local inventory=player:getInventory()
        local part=SC.TerminalHardware.state(run.computer,false).radio
        local hand=SC.TerminalHardware.restorePart(part)
        for _,candidate in ipairs(SC.ControlUtil.items(player)) do
            if inventory:hasRoomFor(player,hand) then break end
            if candidate:getFullType()~="Base.Screwdriver" and not candidate:isEquipped() then
                local owner=candidate:getContainer()
                owner:Remove(candidate)
                player:getSquare():AddWorldInventoryItem(candidate,0.2,0.2,0)
            end
        end
        local okay,reason=SC.TerminalHardware.remove(player,run.computer,"radio")
        assert(okay,"radio unmount failed: "..tostring(reason))
        assert(SC.RadioEndpoints.validate(player,run.endpoint)==false,"unmounted receiver retained authority")
        local found=0
        for _,item in ipairs(SC.ControlUtil.items(player)) do if item:getID()==run.radioId then found=found+1 end end
        assert(found==1,"radio was duplicated or lost on removal")
        log("PASS native removal exact-once")
        local pc=run.computer local square=pc:getSquare() local sprite=pc:getSprite():getName()
        local props=ISMoveableSpriteProps.new(sprite)
        props.doBreakTest=function() return true end
        props:pickUpMoveableInternal(player,square,pc,nil,sprite,true,false)
        assert(not SC.ControlUtil.present(pc),"break fixture did not remove native PC")
        local batteryFound=0
        for i=0,square:getWorldObjects():size()-1 do
            local entry=square:getWorldObjects():get(i):getItem()
            if entry and entry:getID()==run.batteryId then batteryFound=batteryFound+1 end
        end
        assert(batteryFound==1,"broken furniture did not return its exact mounted battery once")
        log("PASS native pickup break recovers exact component")
        log("PASS native terminal controls acceptance complete")
        run.step,run.next=99,now+1000000
    end
end
Events.OnTick.Add(function()
    local okay,reason=pcall(tick)
    if not okay then log("FAIL "..tostring(reason)) run.step,run.next=99,getTimestampMs()+1000000 end
end)
