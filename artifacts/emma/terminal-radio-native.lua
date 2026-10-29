-- SPDX-License-Identifier: MIT
-- Native powered desktop/handset acceptance. All reception fixtures stay in
-- this disposable clone and enter through the actual IsoRadio text method.
local run={step=0,next=0}
local function log(value)
    print("LARCH_WAVE|"..value)
    local writer=getFileWriter("SurvivorCompanionHarness/terminal-radio.log",true,true)
    if writer then writer:write(value.."\n") writer:close() end
end
local function shot(name) getCore():TakeFullScreenshot("emma-radio-"..name) log("SHOT "..name) end
local function pcAt()
    local sq=getCell():getGridSquare(12035,6739,0)
    if sq then for i=0,sq:getObjects():size()-1 do
        local object=sq:getObjects():get(i)
        if SurvivorCompanion.Terminal.isComputer(object) then return object end
    end end
end
local function input(text,mode)
    local w=SurvivorCompanion.Terminal.window
    w:flush() w:setFocusMode(mode or "chat") w.entry:setText(text) w:submit() w:flush()
    local rt=SurvivorCompanion.TerminalRadio.ready(w) if rt then rt.lastPoll=nil end
    SurvivorCompanion.TerminalRadio.poll(w,getTimestampMs())
    return w
end
local function receive(text)
    local rx=SurvivorCompanion.TerminalHardware.receiver(run.pc)
    assert(rx,"native receiver unavailable")
    rx:AddDeviceText(text,0.55,0.9,0.85,"larch-wave-acceptance","LARCHWAVE",12)
end
local function tick()
    local SC=SurvivorCompanion local player=getSpecificPlayer(0) local now=getTimestampMs()
    if now<run.next or not player or not player:getSquare() or not SC or not SC.TerminalRadio then return end
    local R,UI=SC.TerminalRadio,SC.TerminalRadioUI
    if run.step==0 then
        player:teleportTo(12034.5,6739.5,0)
        run.step,run.next,run.deadline=1,now+6000,now+45000
    elseif run.step==1 then
        run.pc=pcAt()
        if not run.pc then assert(now<run.deadline,"clone PC not streamed") run.next=now+500 return end
        assert(SC.Terminal.use(player,run.pc),"native Use computer refused")
        run.step,run.next,run.deadline=2,now+1000,now+30000
    elseif run.step==2 then
        local w=SC.Terminal.window
        if not w then assert(now<run.deadline,"native terminal did not open") run.next=now+500 return end
        w:flush() if w.system.locked then input(w.system.puzzle.answer) end
        local state=SC.TerminalHardware.state(run.pc,false)
        if not state or not state.radio then
            local inv=player:getInventory()
            inv:AddItem("Base.Screwdriver") inv:AddItem("Base.ElectricWire")
            inv:AddItem("Base.ElectronicsScrap") inv:AddItem("Base.ElectronicsScrap")
            for _=1,10 do if player:getPerkLevel(Perks.Electricity)<2 then player:LevelPerk(Perks.Electricity) end end
            assert(SC.TerminalHardware.install(player,run.pc,"radio",inv:AddItem("Base.WalkieTalkie2")),"native handset mount refused")
        end
        local rx,data,item=SC.TerminalHardware.receiver(run.pc)
        assert(rx and data and item,"mounted receiver not native")
        run.radioId,run.oldChannel,run.oldTheme=item:getID(),data:getChannel(),w.system.theme
        local low,high=data:getMinChannelRange(),data:getMaxChannelRange()
        run.first=low<=90000 and high>=94000 and 90000 or low
        run.second=math.min(high,run.first+400)
        local presets=data:getDevicePresets()
        presets:clearPresets() presets:addPreset("Acceptance One",run.first) presets:addPreset("Acceptance Two",run.second)
        assert(SC.TerminalHardware.flush(run.pc),"native presets not serializable")
        input("open radio")
        assert(UI.active(w) and #w:menuOptions()==6,"radio app not opened through real input")
        input("volume 35") input("tune "..tostring(run.second/1000).." MHz")
        receive("Weather reception fixture: rain is mentioned. This line was injected into the clone's actual native receiver.")
        run.step,run.next=3,now+300
    elseif run.step==3 then
        local w=SC.Terminal.window local snap=R.snapshot(w)
        assert(#snap.memory.log>0 and snap.memory.log[1].text:find("Weather reception fixture",1,true),"native device event did not record exact received text")
        assert(snap.frequency==run.second,"radio displayed another frequency")
        local peaks=0 for _,v in ipairs(w.radioPeaks or {}) do peaks=peaks+v end
        assert(peaks>0,"native receive signal did not animate bars")
        for _,b in ipairs(w.radioHits) do assert(b.y>=w:viewTop() and b.y+b.height<=w:viewBottom(),"native radio button clipped") end
        shot("bars") log("PASS native exact-device text, native frequency/volume, animated bars and six visible controls")
        R.cycleMode(run.pc) receive("Second received fixture for the waveform preview.")
        run.step,run.next=4,now+300
    elseif run.step==4 then
        shot("wave")
        input("2","menu") input("1","menu")
        local w=SC.Terminal.window if w.requestTicket then input("yes") end
        assert(R.snapshot(w).scan,"native saved-preset scan failed")
        receive("Scanner hold fixture: a genuine receiver callback pauses this channel.")
        run.step,run.next=5,now+350
    elseif run.step==5 then
        local w=SC.Terminal.window
        assert(R.snapshot(w).scan.hold,"received text failed to hold native scan")
        shot("hold") input("save this channel as Accepted Signal")
        assert(not R.snapshot(w).scan,"saved native preset did not stay on received channel")
        local data=select(2,SC.TerminalHardware.receiver(run.pc))
        assert(data:getDevicePresets():getPresetName(0)=="Accepted Signal","native preset rename failed")
        input("what did we hear")
        run.step,run.next=6,now+500
    elseif run.step==6 then
        shot("notebook")
        input("1","menu")
        assert(SC.Terminal.window.radioPage=="reading","notebook entry not keyboard-selectable")
        run.step,run.next=7,now+500
    elseif run.step==7 then
        shot("entry")
        SC.TerminalRadioUI.back(SC.Terminal.window)
        input("5","menu")
        run.step,run.next=9,now+350
    elseif run.step==9 then
        shot("team")
        local w=SC.Terminal.window
        UI.back(w)
        w.colors=SC.TerminalPresentation.colors("purple") w.system.theme="purple"
        w.logoTexture=SC.TerminalBrands.texture(w.brand,"purple")
        receive("Purple display fixture received on the same native handset.")
        assert(UI.active(w),"purple preview left the radio program")
        run.step,run.next=8,now+300
    elseif run.step==8 then
        shot("purple")
        local w=SC.Terminal.window local count=#R.snapshot(w).memory.log
        assert(SC.TerminalHardware.flush(run.pc),"native radio state not saved")
        local hardware=SC.TerminalHardware.state(run.pc,false)
        local saved=SC.TerminalHardware.restorePart(hardware.radio)
        assert(saved and saved:getID()==run.radioId and saved:getDeviceData():getDevicePresets():getPresetName(0)=="Accepted Signal",
            "serialized mounted handset lost identity or presets")
        w.system.theme=run.oldTheme w:close() SC.Terminal.resetSessions()
        assert(SC.Terminal.open(player,run.pc),"native radio PC did not reopen")
        SC.Terminal.window:flush() input("open radio")
        assert(#R.snapshot(SC.Terminal.window).memory.log==count,"notebook disappeared on reopen")
        assert(getSpecificPlayer(1)==nil,"radio app created a secondary player view")
        local current=R.snapshot(SC.Terminal.window).frequency
        local radio=getZomboidRadio()
        local function broadcast(x,y,channel,text,range)
            radio:DistributeTransmission(x,y,channel,text,"larch-wave-rf","LARCHWAVE",0.55,0.9,0.85,range,false)
        end
        broadcast(12043,6747,current+200,"Wrong-frequency native RF fixture",100)
        assert(#R.snapshot(SC.Terminal.window).memory.log==count,"wrong-frequency RF entered notebook")
        broadcast(15035,6747,current,"Out-of-range native RF fixture",5)
        assert(#R.snapshot(SC.Terminal.window).memory.log==count,"out-of-range RF entered notebook")
        broadcast(12043,6747,current,"Matched-frequency native RF acceptance fixture",100)
        assert(R.snapshot(SC.Terminal.window).memory.log[1].text=="Matched-frequency native RF acceptance fixture",
            "in-range matched-frequency native RF did not reach notebook")
        log("PASS native RF distribution rejects wrong channel and out-of-range traffic; accepts actual in-range tuned transmission")
        log("PASS native scanner hold, saved preset, notebook keyboard reading, original handset identity and portable blob; no secondary slot")
        local window=SC.Terminal.window
        local H=SC.TerminalHardware
        local inv=player:getInventory()
        inv:AddItem("Base.Screwdriver")
        -- This source clone is overburdened. Isolate the ownership test from
        -- carry limits; full-inventory refusal is exercised by the UI suite.
        local oldMaxWeight,oldCapacity=player:getMaxWeight(),inv:getCapacity()
        player:setMaxWeight(100) inv:setCapacity(100)
        local stash,stashed=ItemContainer.new(),{}
        for _,candidate in ipairs(SC.ControlUtil.list(inv:getItems(),2048)) do
            if inv:hasRoomFor(player,saved) then break end
            if candidate:getFullType()~="Base.Screwdriver" then
                inv:Remove(candidate) stash:AddItem(candidate)
                assert(candidate:getContainer()==stash,"fixture could not retain an exact carried item")
                stashed[#stashed+1]=candidate
            end
        end
        assert(inv:hasRoomFor(player,saved),"native transfer fixture still has no room for its handset")
        assert(R.tune(window,current),"native removal fixture could not select original channel")
        assert(R.scan(window,"band"),"native removal fixture could not begin a scan")
        assert(R.snapshot(window).scan,"native removal fixture has no active scan")
        local activeScan=R.snapshot(window).scan
        local scanChannel=select(2,H.receiver(run.pc)):getChannel()
        assert(not R.tune(window,2147483647) and R.snapshot(window).scan==activeScan
            and select(2,H.receiver(run.pc)):getChannel()==scanChannel,
            "invalid native tuning request cancelled or changed a scan")
        local removalOkay,removalReason=H.remove(player,run.pc,"radio")
        assert(removalOkay,"native scanning handset could not be removed: "..tostring(removalReason))
        local removed
        for _,candidate in ipairs(SC.ControlUtil.items(player)) do
            if candidate:getID()==run.radioId then assert(not removed,"removed native handset duplicated") removed=candidate end
        end
        assert(removed and removed:getDeviceData():getChannel()==current,
            "removed native handset retained a temporary scan frequency")
        assert(pcall(UI.input,window,"unmute radio") and pcall(UI.input,window,"next preset"),
            "native radio commands crashed after handset removal")
        inv:AddItem("Base.ElectricWire") inv:AddItem("Base.ElectronicsScrap") inv:AddItem("Base.ElectronicsScrap")
        for _=1,2 do if player:getPerkLevel(Perks.Electricity)<2 then player:LevelPerk(Perks.Electricity) end end
        assert(H.install(player,run.pc,"radio",removed),"native handset could not be remounted")
        local remounted,remountedData,remountedItem=H.receiver(run.pc)
        assert(remounted and remountedItem:getID()==run.radioId and remountedData:getChannel()==current,
            "native remount changed handset identity or listening channel")
        for _,candidate in ipairs(stashed) do
            stash:Remove(candidate) inv:AddItem(candidate)
            assert(candidate:getContainer()==inv,"fixture did not restore an exact carried item")
        end
        player:setMaxWeight(oldMaxWeight) inv:setCapacity(oldCapacity)
        log("PASS native scan-to-removal restores original channel; absent-radio commands are safe; remount preserves exact handset")
        SC.Terminal.window:close()
        log("PASS native terminal radio acceptance complete")
        run.step,run.next=99,now+1000000
    end
end
Events.OnTick.Add(function()
    local okay,reason=pcall(tick)
    if not okay then log("FAIL "..tostring(reason)) run.step,run.next=99,getTimestampMs()+1000000 end
end)
