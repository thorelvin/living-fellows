-- SPDX-License-Identifier: MIT
-- Native controls in a disposable cloned world. One generator and battery
-- are fixture supplies; no native action, power query or receipt is mocked.
local run={step=0,next=0}
local function log(text)
    print("EMMA_POWER|"..text)
    local writer=getFileWriter("SurvivorCompanionHarness/terminal-controls-power.log",true,true)
    if writer then writer:write(text.."\n") writer:close() end
end
local function shot(name) getCore():TakeFullScreenshot("emma-controls-"..name) end
local function findPC()
    local square=getCell():getGridSquare(12035,6739,0)
    if square then for i=0,square:getObjects():size()-1 do
        local object=square:getObjects():get(i)
        if SurvivorCompanion.Terminal.isComputer(object) then return object end
    end end
end
local function access(actor,object)
    local _,targets=SurvivorCompanion.GameplayUtil.directInteractionAccess(actor,object)
    for _,square in ipairs(targets) do
        if SurvivorCompanion.GameplayUtil.isSquareFree(square) then
            actor:teleportTo(square:getX()+0.5,square:getY()+0.5,square:getZ()) return true
        end
    end
end
local function tick()
    local SC=SurvivorCompanion local player=getSpecificPlayer(0) local now=getTimestampMs()
    if now<run.next or not player or not SC or not SC.GeneratorServices then return end
    if run.step==0 then
        player:setGodMod(true) player:setGhostMode(true) player:teleportTo(12036.5,6739.5,0)
        run.step,run.next=1,now+6000
    elseif run.step==1 then
        run.pc=assert(findPC(),"original desktop not loaded") assert(access(player,run.pc))
        for _=1,10 do if player:getPerkLevel(Perks.Electricity)<4 then player:LevelPerk(Perks.Electricity) end end
        local inv=player:getInventory()
        inv:AddItem("Base.Screwdriver") for _=1,10 do inv:AddItem("Base.ElectricWire") end
        for _=1,30 do inv:AddItem("Base.ElectronicsScrap") end inv:AddItem("Base.Amplifier")
        local battery=inv:AddItem("Base.CarBattery1") battery:setCondition(battery:getConditionMax()) SC.ControlUtil.setCharge(battery,0.8)
        assert(SC.TerminalHardware.install(player,run.pc,"ups",battery))
        assert(SC.BuildingControls.connect(player,run.pc)) run.panel=SC.BuildingControls.panel(run.pc,false)
        local square=assert(getCell():getGridSquare(12039,6746,0))
        local item=assert(instanceItem("Base.Generator"),"generator fixture script missing")
        run.generator=IsoGenerator.new(item,getCell(),square)
        run.generator:setConnected(true) run.generator:setFuel(8) run.generator:setCondition(100)
        run.generator:setActivated(false)
        assert(run.generator:getObjectIndex()>=0,"native generator fixture not on square")
        run.step,run.next=2,now+2500
    elseif run.step==2 then
        local inv=player:getInventory() local battery=inv:AddItem("Base.CarBattery1")
        battery:setCondition(battery:getConditionMax()) SC.ControlUtil.setCharge(battery,0.8)
        assert(access(player,run.generator)) run.starterBattery=battery
        run.step,run.next=3,now+1500
    elseif run.step==3 then
        run.row={id="native-starter",kind="generator"}
        local okay,reason=SC.GeneratorServices.fit(player,run.generator,run.row,run.starterBattery)
        assert(okay,"starter install: "..tostring(reason))
        assert(SC.GeneratorServices.remote(player,run.generator,"start",run.row))
        assert(run.generator:isActivated(),"native remote start failed at condition 100")
        local battery=SC.TerminalHardware.restorePart(run.row.starter)
        assert(battery:getID()==run.starterBattery:getID() and math.abs(SC.ControlUtil.charge(battery)-0.79)<0.0001,"starter charge/identity changed incorrectly")
        assert(SC.GeneratorServices.remote(player,run.generator,"stop",run.row))
        assert(not run.generator:isActivated(),"native remote stop did not stop generator")
        log("PASS native remote starter start/stop and exact battery drain")
        local helper
        for _,actor in ipairs(SC.Registry.living()) do
            local id=SC.Registry.idOf(actor) local record=SC.Registry.byId(id)
            if record and record.recruited and not SC.ExpeditionPrototype.isMember(actor) then helper=actor break end
        end
        run.helper=assert(helper,"no recruited actor for native generator service")
        local okay,why=SC.Commands.issue(SC.Registry.idOf(helper),"follow",nil,player)
        assert(okay,"helper follow order: "..tostring(why))
        helper:setGodMod(true) helper:setGhostMode(true) assert(access(helper,run.generator))
        run.step,run.next=4,now+2000
    elseif run.step==4 then
        local okay,reason=SC.GeneratorServices.requestLocal(player,run.generator,"start")
        assert(okay,"local start request: "..tostring(reason))
        run.step,run.next,run.deadline=5,now+500,now+45000
    elseif run.step==5 then
        if not run.generator:isActivated() then assert(now<run.deadline,"companion never completed native generator start") run.next=now+500 return end
        log("PASS companion native start")
        local okay,reason=SC.GeneratorServices.requestLocal(player,run.generator,"stop")
        if not okay then assert(now<run.deadline,"local stop request: "..tostring(reason)) run.next=now+500 return end
        run.step,run.next,run.deadline=6,now+500,now+45000
    elseif run.step==6 then
        if run.generator:isActivated() then assert(now<run.deadline,"companion never completed native generator stop") run.next=now+500 return end
        log("PASS companion native stop")
        run.generator:setCondition(96)
        local helper=run.helper local bag=helper:getInventory():AddItem("Base.Bag_Schoolbag")
        run.scrap=bag:getItemContainer():AddItem("Base.ElectronicsScrap") run.bag=bag
        run.step,run.next=7,now+1500
    elseif run.step==7 then
        local okay,reason=SC.GeneratorServices.requestLocal(player,run.generator,"repair")
        if not okay then run.next=now+500 run.waits=(run.waits or 0)+1 assert(run.waits<20,tostring(reason)) return end
        run.step,run.next,run.deadline=8,now+500,now+45000
    elseif run.step==8 then
        if run.generator:getCondition()<100 then assert(now<run.deadline,"companion never completed native repair") run.next=now+500 return end
        assert(run.scrap:getContainer()==nil,"native repair did not consume the exact bagged scrap")
        log("PASS companion native repair consumes bagged scrap")
        assert(access(player,run.pc))
        run.hydro=getWorld():isHydroPowerOn() getWorld():setHydroPowerOn(false)
        run.powerOption=getSandboxOptions():getOptionByName("ElecShutModifier")
        run.electricity=run.powerOption:getValue() run.powerOption:setValue(0)
        run.generators={}
        local x,y,z=SC.ControlUtil.position(run.pc)
        for dx=-24,24 do for dy=-24,24 do
            local square=getCell():getGridSquare(x+dx,y+dy,z)
            local gen=square and square:getGenerator()
            if gen and gen:isActivated() then run.generators[#run.generators+1]=gen gen:setActivated(false) end
        end end
        IsoGenerator.updateSurroundingNow()
        run.step,run.next=9,now+2500
    elseif run.step==9 then
        assert(not SC.ControlUtil.nativePower(run.pc),"native blackout fixture still has building power")
        assert(SC.TerminalHardware.powered(run.pc),"UPS did not supply PC during real blackout")
        local pcState=SC.Terminal.computerState(player,run.pc) pcState.locked=false
        assert(SC.Terminal.use(player,run.pc))
        log("PASS native blackout keeps only PC powered by UPS")
        run.step,run.next,run.deadline=10,now+500,now+30000
    elseif run.step==10 then
        local window=SC.Terminal.window
        if not window then assert(now<run.deadline,"UPS computer did not open") run.next=now+500 return end
        window:flush() SC.TerminalServices.input(window,"hardware") window:flush()
        run.step,run.next=101,now+1500
    elseif run.step==101 then
        shot("power")
        getWorld():setHydroPowerOn(run.hydro) for _,gen in ipairs(run.generators) do gen:setActivated(true) end
        run.powerOption:setValue(run.electricity)
        IsoGenerator.updateSurroundingNow()
        run.step,run.next=11,now+2500
    elseif run.step==11 then
        assert(SC.ControlUtil.nativePower(run.pc),"native power did not recover")
        assert(SC.BuildingSecurity.operate(run.panel,run.pc,"install_speaker",player))
        log("PA source="..tostring(run.panel.speaker.computer).." connected="..tostring(SC.BuildingControls.connected(run.pc,run.panel)))
        for candidate,owner in pairs(SC.BuildingControls.computers) do
            local data=candidate:getModData().movableData
            log("PA owner="..tostring(owner.id).." panel="..tostring(owner==run.panel).." identity="..tostring(data and data.LF_LarchOS and data.LF_LarchOS.identity))
        end
        local okay,reason=SC.BuildingSecurity.operate(run.panel,run.pc,"announce",player)
        assert(okay,"native PA: "..tostring(reason))
        assert(SC.BuildingSecurity.operate(run.panel,run.pc,"silence",player))
        assert(SC.BuildingSecurity.operate(run.panel,run.pc,"arm",player))
        assert(run.pc:getSquare():getBuildingDef():isAlarmed(),"native alarm flag was not armed")
        assert(SC.BuildingSecurity.operate(run.panel,run.pc,"disarm",player))
        assert(not run.pc:getSquare():getBuildingDef():isAlarmed(),"native alarm flag was not disarmed")
        local manager=getAmbientStreamManager()
        local def=run.pc:getSquare():getBuildingDef()
        local other
        local px,py,pz=SC.ControlUtil.position(run.pc)
        for dx=-24,24 do for dy=-24,24 do
            local square=getCell():getGridSquare(px+dx,py+dy,pz)
            local found=square and square:getBuildingDef()
            if found and found~=def and found:getRooms():size()>0 then other=found end
        end end
        assert(other,"second original building for alarm isolation did not load")
        other:setAlarmed(true) def:setAlarmed(true)
        manager:doAlarm(other:getRooms():get(0))
        manager:doAlarm(def:getRooms():get(0))
        assert(SCBridge.silenceControlBuildingAlarm(def,manager)>=1,"native targeted alarm silence found no alarm")
        assert(SCBridge.silenceControlBuildingAlarm(other,manager)>=1,"silencing the first building wrongly stopped the second alarm")
        local window=SC.Terminal.window SC.TerminalServices.input(window,"building services") window.menuPage="security_panel" window:flush()
        run.step,run.next=12,now+1500
    elseif run.step==12 then
        shot("security")
        log("PASS native PA, alarm arm/disarm and targeted silence")
        assert(getSpecificPlayer(0)==player and getSpecificPlayer(1)==nil,"services changed player/camera ownership")
        log("PASS native terminal controls power acceptance complete") run.step,run.next=99,now+1000000
    end
end
Events.OnTick.Add(function()
    local okay,reason=pcall(tick)
    if not okay then log("FAIL "..tostring(reason)) run.step,run.next=99,getTimestampMs()+1000000 end
end)
