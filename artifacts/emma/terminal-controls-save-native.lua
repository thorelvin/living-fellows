-- SPDX-License-Identifier: MIT
-- Two real game processes: save a fitted map desktop, then load that clone.
local mode=LF_CONTROLS_SAVE_MODE or "savesetup"
local run={step=0,next=0}
local function log(text)
    print("EMMA_CONTROLS_SAVE|"..text)
    local writer=getFileWriter("SurvivorCompanionHarness/terminal-controls-"..mode..".log",true,true)
    if writer then writer:write(text.."\n") writer:close() end
end
local function computer()
    local square=getCell():getGridSquare(12035,6739,0)
    if square then for i=0,square:getObjects():size()-1 do
        local object=square:getObjects():get(i)
        if SurvivorCompanion.Terminal.isComputer(object) then return object end
    end end
end
local function tick()
    local SC=SurvivorCompanion local player=getSpecificPlayer(0) local now=getTimestampMs()
    if now<run.next or not SC or not SC.TerminalServices or not player or not player:getSquare() then return end
    if run.step==0 then
        player:setGodMod(true) player:setGhostMode(true)
        player:teleportTo(12034.5,6739.5,0)
        run.step,run.next,run.deadline=1,now+6000,now+40000
    elseif run.step==1 then
        run.pc=computer()
        if not run.pc then assert(now<run.deadline,"original desktop did not stream") run.next=now+500 return end
        if mode=="saveverify" then
            local expected=ModData.getOrCreate("LF_AcceptanceStation")
            assert(expected.identity,"setup world records missing after reload")
            local hardware=assert(SC.TerminalHardware.state(run.pc,false),"mounted hardware missing after reload")
            assert(hardware.radio.id==expected.radioId and hardware.ups.id==expected.batteryId,"mounted identities changed after reload")
            local radio=assert(SC.TerminalHardware.restorePart(hardware.radio))
            local battery=assert(SC.TerminalHardware.restorePart(hardware.ups))
            assert(radio:getID()==expected.radioId and radio:getModData().LF_Acceptance=="save-radio","native radio payload changed")
            assert(battery:getID()==expected.batteryId and battery:getModData().LF_Acceptance=="save-battery","native battery payload changed")
            assert(math.abs(SC.ControlUtil.charge(battery)-expected.charge)<0.0001,"original battery charge changed")
            local state=SC.Terminal.computerState(player,run.pc)
            assert(state.identity==expected.identity,"computer identity changed")
            local panel=assert(SC.BuildingControls.panel(run.pc,false),"building records missing")
            assert(panel.id==expected.panelId and SC.BuildingControls.connected(run.pc,panel),"building connection changed")
            local found=false
            for _,entry in ipairs(panel.history) do if entry.text=="Native save/reload acceptance marker" then found=true end end
            assert(found,"building history missing after reload")
            run.endpoint=assert(SC.RadioEndpoints.station(player,run.pc))
            assert(SC.RadioEndpoints.validate(player,run.endpoint),"mounted receiver did not reconstruct")
            for _,item in ipairs(SC.ControlUtil.items(player)) do
                assert(item:getID()~=expected.radioId and item:getID()~=expected.batteryId,"mounted hardware duplicated in inventory")
            end
            assert(getSpecificPlayer(1)==nil,"reloading station acquired a player slot")
            log("PASS full native world reload identity="..state.identity.." radioId="..radio:getID().." batteryId="..battery:getID())
            log("PASS native terminal controls saveverify acceptance complete")
            run.step,run.next=99,now+1000000
            return
        end
        local inventory=player:getInventory()
        for _=1,6 do inventory:AddItem("Base.ElectricWire") inventory:AddItem("Base.ElectronicsScrap") end
        for _=1,8 do inventory:AddItem("Base.ElectronicsScrap") end
        inventory:AddItem("Base.Screwdriver")
        for _=1,10 do if player:getPerkLevel(Perks.Electricity)<4 then player:LevelPerk(Perks.Electricity) end end
        run.radio=inventory:AddItem("Base.WalkieTalkie2") run.radio:getModData().LF_Acceptance="save-radio"
        run.battery=inventory:AddItem("Base.CarBattery1") run.battery:setUsedDelta(0.8)
        run.battery:setCondition(run.battery:getConditionMax()) run.battery:getModData().LF_Acceptance="save-battery"
        local state=SC.Terminal.computerState(player,run.pc)
        state.locked=false
        assert(SC.BuildingControls.connect(player,run.pc))
        run.panel=assert(SC.BuildingControls.panel(run.pc,false))
        SC.BuildingControls.log(run.panel,"Native save/reload acceptance marker")
        assert(SC.TerminalServices.install(player,run.pc,function() return SC.TerminalHardware.install(player,run.pc,"radio",run.radio) end))
        run.step,run.next,run.deadline=2,now+500,now+35000
    elseif run.step==2 then
        local hardware=SC.TerminalHardware.state(run.pc,false)
        if not hardware or not hardware.radio then assert(now<run.deadline,"radio fit timed out") run.next=now+500 return end
        assert(SC.TerminalServices.install(player,run.pc,function() return SC.TerminalHardware.install(player,run.pc,"ups",run.battery) end))
        run.step,run.next,run.deadline=3,now+500,now+35000
    elseif run.step==3 then
        local hardware=SC.TerminalHardware.state(run.pc,false)
        if not hardware.ups then assert(now<run.deadline,"backup fit timed out") run.next=now+500 return end
        run.endpoint=assert(SC.RadioEndpoints.station(player,run.pc))
        assert(SC.RadioEndpoints.validate(player,run.endpoint))
        assert(SC.TerminalHardware.flush(run.pc))
        local expected=ModData.getOrCreate("LF_AcceptanceStation")
        expected.identity=SC.Terminal.computerState(player,run.pc).identity
        expected.radioId,expected.batteryId=hardware.radio.id,hardware.ups.id
        expected.charge=SC.ControlUtil.charge(SC.TerminalHardware.restorePart(hardware.ups))
        expected.panelId=run.panel.id
        save(true)
        log("PASS full native world save identity="..expected.identity.." radioId="..expected.radioId.." batteryId="..expected.batteryId)
        run.step,run.next=4,now+5000
    elseif run.step==4 then
        log("PASS native terminal controls savesetup acceptance complete")
        run.step,run.next=99,now+1000000
    end
end
Events.OnTick.Add(function()
    local okay,reason=pcall(tick)
    if not okay then log("FAIL "..tostring(reason)) run.step,run.next=99,getTimestampMs()+1000000 end
end)
