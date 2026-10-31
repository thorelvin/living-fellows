-- SPDX-License-Identifier: MIT
-- Native power acceptance in a disposable cache. Every fixture is clone-only.
local Probe={}
local transformer={electricity_pylon_136=true,electricity_pylon_137=true,electricity_pylon_138=true,
    electricity_pylon_139=true,electricity_pylon_162=true,electricity_pylon_163=true,
    electricity_pylon_176=true,electricity_pylon_181=true}
local function call(object,name,...)
    if not object then return nil end
    local okay,value=pcall(function(...) return object[name](object,...) end,...)
    if okay then return value end
end
local function shot(H,name)
    getCore():TakeFullScreenshot(H.config.run_id.."-grid-"..name)
end
local function closeComputer(SC)
    if SC.Terminal.window then SC.Terminal.window:close() end
end
local function quiet(player)
    local zombies=getCell():getZombieList()
    for index=zombies:size()-1,0,-1 do
        local zombie=zombies:get(index)
        if (zombie:getX()-player:getX())^2+(zombie:getY()-player:getY())^2<2500 then
            zombie:removeFromWorld() zombie:removeFromSquare()
        end
    end
end
local function square(x,y,z) return getCell():getGridSquare(x,y,z or 0) end
local function list(value)
    local rows={}
    if value then for i=0,value:size()-1 do rows[#rows+1]=value:get(i) end end
    return rows
end
local function cleanFloor(SC,tile)
    return tile and call(tile,"TreatAsSolidFloor")==true
        and not SC.Topology.squareHasStairs(tile) and SC.GameplayUtil.isSquareFree(tile)
        and SC.GameplayUtil.squareOccupyingObject(tile)==nil
end
local function findComputer(x,y,z)
    local tile=square(x,y,z)
    for _,object in ipairs(list(call(tile,"getObjects"))) do
        if SurvivorCompanion.Terminal.isComputer(object) then return object end
    end
end
local function pc(SC,player,tile)
    local object=IsoObject.new(tile,"appliances_com_01_72","Computer")
    tile:AddTileObject(object)
    local os=SC.Terminal.computerState(player,object)
    if not os then return nil,"computer identity unavailable" end
    os.locked=false -- access is an explicit fixture, independently regression-tested
    local inventory=player:getInventory()
    inventory:AddItem("Base.Screwdriver")
    for _=1,3 do inventory:AddItem("Base.ElectricWire") end
    for _=1,8 do inventory:AddItem("Base.ElectronicsScrap") end
    local radio=inventory:AddItem("Base.WalkieTalkie2")
    if not radio then return nil,"native walkie item unavailable" end
    local okay,reason=SC.TerminalHardware.install(player,object,"radio",radio)
    if not okay then return nil,reason end
    local battery=inventory:AddItem("Base.CarBattery1")
    if battery then
        SC.ControlUtil.setCharge(battery,0.9)
        okay,reason=SC.TerminalHardware.install(player,object,"ups",battery)
        if not okay then return nil,reason end
    end
    return object
end
local function sampleAppliances(f)
    local result={fridges={},switches={}}
    local x,y=math.floor(f.home:getX()),math.floor(f.home:getY())
    for dx=-18,18 do for dy=-18,18 do
        local tile=square(x+dx,y+dy,0)
        if tile and call(tile,"haveElectricity")~=true then
            for _,object in ipairs(list(tile:getObjects())) do
                local container=call(object,"getContainerByType","fridge")
                if container then result.fridges[#result.fridges+1]=container end
                if instanceof(object,"IsoLightSwitch") then result.switches[#result.switches+1]=object end
            end
        end
    end end
    return result
end
local function applianceCounts(f)
    local fridge,lights=0,0
    for _,container in ipairs(f.appliances.fridges) do if call(container,"isPowered")==true then fridge=fridge+1 end end
    for _,switch in ipairs(f.appliances.switches) do if call(switch,"hasGridPower")==true then lights=lights+1 end end
    return fridge,lights
end
local function showGrid(H,SC,object)
    closeComputer(SC)
    local okay,reason=SC.Terminal.open(H.player,object)
    if not okay then return false,reason end
    local w=SC.Terminal.window
    w.postStarted=0 w.state="idle" w:flush()
    SC.TerminalGridUI.open(w)
    SC.TerminalGridUI.update(w,getTimestampMs())
    return true
end
local function startSite(H,f,current,setPhase)
    local site=SurvivorCompanion.GridControl.SITES[f.siteIndex]
    if not site then
        local first=SurvivorCompanion.GridControl.SITES[1]
        H.player:teleportTo(first.x,first.y,0)
        setPhase("grid_control_yard_load",current) return
    end
    f.site=site
    H.player:teleportTo(site.x,site.y,0)
    setPhase("grid_control_site_load",current)
end
function Probe.step(H,current,check,result,setPhase)
    local SC=SurvivorCompanion
    local G,U=SC.GridControl,SC.ControlUtil
    if H.phase=="grid_control_setup" then
        SC.Scheduler.unregister("decision")
        local f={original=getSandboxOptions():getElecShutModifier(),siteIndex=1}
        H.gridControl=f
        f.origin={x=H.player:getX(),y=H.player:getY(),z=H.player:getZ()}
        if H.config.grid_control_resume=="true" then
            local saved=ModData.get("LF_GridAcceptance")
            if not check("grid_reload_fixture",saved and saved.homeX~=nil,"retained clone checkpoint") then
                setPhase("finish",current) return
            end
            f.saved=saved H.player:teleportTo(saved.homeX+0.5,saved.homeY+0.5,saved.homeZ)
            G.restore()
            setPhase("grid_control_reload_load",current) return
        end
        G.reset()
        getSandboxOptions():set("ElecShutModifier",0) getSandboxOptions():toLua()
        G.restore()
        if not check("grid_real_ambient",tostring(getAmbientStreamManager()):find("Dummy",1,true)==nil,
            tostring(getAmbientStreamManager())) then setPhase("finish",current) return end
        startSite(H,f,current,setPhase) return
    end
    local f=H.gridControl
    quiet(H.player)
    if H.phase=="grid_control_site_load" then
        if current-H.phaseStartedAt<4000 then return end
        local centre=square(f.site.x,f.site.y,0)
        if not centre then
            if current-H.phaseStartedAt>35000 then result("FAIL","grid_site_loaded",f.site.id) setPhase("finish",current) end
            return
        end
        f.scanX,f.scanY,f.transformers=f.site.x-40,f.site.y-40,0
        setPhase("grid_control_site_scan",current) return
    end
    if H.phase=="grid_control_site_scan" then
        for _=1,96 do
            local tile=square(f.scanX,f.scanY,0)
            for _,object in ipairs(list(call(tile,"getObjects"))) do
                local name=call(call(object,"getSprite"),"getName")
                if transformer[name] then f.transformers=f.transformers+1 end
            end
            f.scanX=f.scanX+1
            if f.scanX>f.site.x+40 then f.scanX=f.site.x-40 f.scanY=f.scanY+1 end
            if f.scanY>f.site.y+40 then break end
        end
        if f.scanY<=f.site.y+40 then return end
        if not check("grid_site_"..f.site.id,f.transformers>0,"native transformer tiles="..f.transformers
            .." centre="..f.site.x..","..f.site.y) then setPhase("finish",current) return end
        f.siteIndex=f.siteIndex+1 startSite(H,f,current,setPhase) return
    end
    if H.phase=="grid_control_yard_load" then
        if current-H.phaseStartedAt<5000 then return end
        local site=G.SITES[1]
        local chosen,generatorSquare
        for dx=-18,18 do for dy=-18,18 do
            local tile=square(site.x+dx,site.y+dy,0)
            local adjacent=square(site.x+dx+2,site.y+dy,0)
            if not chosen and cleanFloor(SC,tile) and cleanFloor(SC,adjacent)
                and call(tile,"getRoom")==nil then chosen,generatorSquare=tile,adjacent end
        end end
        if not check("grid_outdoor_floor",chosen~=nil,"clear floor within station radius") then setPhase("finish",current) return end
        H.player:teleportTo(chosen:getX()+0.5,chosen:getY()+0.5,0)
        f.yardTile,f.generatorTile=chosen,generatorSquare
        setPhase("grid_control_yard_fixture",current) return
    end
    if H.phase=="grid_control_yard_fixture" then
        if current-H.phaseStartedAt<500 then return end
        local computer,why=pc(SC,H.player,f.yardTile)
        if not check("grid_physical_pc",computer~=nil,tostring(why)) then setPhase("finish",current) return end
        f.yard=computer
        local state=SC.TerminalHardware.state(computer,false)
        check("grid_battery_not_generator",SC.TerminalHardware.powered(computer) and G.startConnect(computer)==false,
            tostring(G.connectBlocker(computer)))
        local item=instanceItem("Base.Generator_Old")
        local generator=item and IsoGenerator.new(item,getCell(),f.generatorTile)
        if not check("grid_native_generator",generator~=nil,"native outdoor generator fixture") then setPhase("finish",current) return end
        generator:setConnected(true) generator:setFuel(generator:getMaxFuel()*0.5)
        generator:setActivated(true) generator:sync() f.generator=generator
        setPhase("grid_control_yard_power",current) return
    end
    if H.phase=="grid_control_yard_power" then
        if SC.TerminalWorld.powerState(f.yard:getSquare()).generator~=true then
            if current-H.phaseStartedAt>20000 then
                result("FAIL","grid_outdoor_generator_supply","haveElectricity stayed false") setPhase("finish",current)
            end
            return
        end
        check("grid_outdoor_generator_supply",true,"native haveElectricity powers the outdoor PC")
        local okay,why=G.startConnect(f.yard)
        if not check("grid_connect_started",okay,tostring(why)) then setPhase("finish",current) return end
        local record=ModData.get(G.KEY).connections.muldraugh
        record.lastHours=record.lastHours-0.5 -- advance this fixture receipt, not the world clock
        G.sample(f.yard)
        check("grid_connected_once",ModData.get(G.KEY).sites.muldraugh~=nil,"native PC and radio bound")
        f.generator:setActivated(false) f.generator:sync()
        setPhase("grid_control_yard_independent",current) return
    end
    if H.phase=="grid_control_yard_independent" then
        if current-H.phaseStartedAt<4000 then return end
        check("grid_yard_supply",not SC.TerminalWorld.powerState(f.yard:getSquare()).generator
            and SC.TerminalHardware.powered(f.yard),"the bound computer works with its generator stopped")
        local state=SC.TerminalHardware.state(f.yard,false)
        local radioId=state.radio.id
        local props=ISMoveableSpriteProps.new(f.yard:getSprite())
        check("grid_cursor_pinned",props:canPickUpMoveable(H.player,f.yard:getSquare(),f.yard)==false,"vanilla cursor refuses")
        check("grid_native_pickup_pinned",props:pickUpMoveableInternal(H.player,f.yard:getSquare(),f.yard)==nil,
            "native pickup wrapper refuses before moving inventory")
        check("grid_radio_pinned",SC.TerminalHardware.remove(H.player,f.yard,"radio")==false
            and state.radio.id==radioId,"exact radio remains installed")
        if check("grid_yard_window",showGrid(H,SC,f.yard),"native substation terminal") then
            setPhase("grid_control_yard_photo",current)
        else setPhase("finish",current) end
        return
    end
    if H.phase=="grid_control_yard_photo" then
        if current-H.phaseStartedAt<2500 then return end
        shot(H,"substation") closeComputer(SC)
        H.player:teleportTo(f.origin.x,f.origin.y,f.origin.z)
        setPhase("grid_control_base_load",current) return
    end
    if H.phase=="grid_control_base_load" then
        if current-H.phaseStartedAt<5000 then return end
        local home
        local x,y,z=math.floor(f.origin.x),math.floor(f.origin.y),math.floor(f.origin.z)
        for dx=-12,12 do for dy=-12,12 do
            local tile=square(x+dx,y+dy,z)
            if tile and SC.BaseLife.isInside(tile) then
                for _,object in ipairs(list(tile:getObjects())) do if SC.Terminal.isComputer(object) then home=home or object end end
            end
        end end
        if not home then
            local tile=square(x,y,z)
            if cleanFloor(SC,tile) then H.player:teleportTo(x+0.5,y+0.5,z) home=pc(SC,H.player,tile) end
        end
        if not check("grid_base_computer",home~=nil,"real marked camp computer") then setPhase("finish",current) return end
        f.home=home
        H.player:teleportTo(home:getX()+0.5,home:getY()+0.5,home:getZ())
        setPhase("grid_control_base_equipment",current) return
    end
    if H.phase=="grid_control_base_equipment" then
        if current-H.phaseStartedAt<500 then return end
        local home=f.home
        local os=SC.Terminal.computerState(H.player,home) os.locked=false
        local state=SC.TerminalHardware.state(home,false)
        if not state or not state.radio then
            local inventory=H.player:getInventory()
            inventory:AddItem("Base.Screwdriver") inventory:AddItem("Base.ElectricWire")
            for _=1,2 do inventory:AddItem("Base.ElectronicsScrap") end
            local radio=inventory:AddItem("Base.WalkieTalkie2")
            local okay,why=SC.TerminalHardware.install(H.player,home,"radio",radio)
            if not check("grid_base_radio",okay,tostring(why)) then setPhase("finish",current) return end
        end
        state=SC.TerminalHardware.state(home,false)
        if not state.ups then
            local inventory=H.player:getInventory()
            inventory:AddItem("Base.ElectricWire") for _=1,4 do inventory:AddItem("Base.ElectronicsScrap") end
            local battery=inventory:AddItem("Base.CarBattery1") U.setCharge(battery,0.9)
            local okay,why=SC.TerminalHardware.install(H.player,home,"ups",battery)
            if not check("grid_base_backup",okay,tostring(why)) then setPhase("finish",current) return end
        end
        local okay,why=G.startCrack(home,H.player,"muldraugh")
        if not check("grid_base_crack",okay,tostring(why)) then setPhase("finish",current) return end
        local id=home:getModData().movableData.LF_LarchOS.identity
        f.job=ModData.get(G.KEY).jobs[id]
        f.job.lastHours=f.job.lastHours-f.job.requiredHours*0.4
        local before=f.job.doneHours
        for _=1,1000 do G.pulse() end
        check("grid_idle_no_cracking",f.job.doneHours==before,"idle calls do no controller work")
        G.snapshot(home)
        check("grid_contact_catchup",f.job.doneHours>=f.job.requiredHours*0.4,"query settles elapsed time on a computer that still has power")
        showGrid(H,SC,home)
        setPhase("grid_control_crack_photo",current) return
    end
    if H.phase=="grid_control_crack_photo" then
        if current-H.phaseStartedAt<2500 then return end
        shot(H,"cracking") closeComputer(SC)
        local handset=H.player:getInventory():AddItem("Base.WalkieTalkie2")
        local data=handset and handset:getDeviceData()
        if not data then result("FAIL","grid_handset","native handset missing") setPhase("finish",current) return end
        if not data:getHasBattery() then data:addBattery(H.player:getInventory():AddItem("Base.Battery")) end
        data:setPower(1) data:setChannel(90000) data:setMicIsMuted(false) data:setIsTurnedOn(true)
        H.player:setPrimaryHandItem(handset) f.handset=handset
        local _,station=SC.TerminalHardware.receiver(f.home)
        if not station then result("FAIL","grid_station_receiver","native receiver missing") setPhase("finish",current) return end
        station:setChannel(90000) station:setMicIsMuted(false)
        local x,y,z=math.floor(f.home:getX()),math.floor(f.home:getY()),f.home:getZ()
        local destination
        for dx=15,30 do
            local tile=square(x+dx,y,z)
            if not destination and cleanFloor(SC,tile) then destination=tile end
        end
        if not destination then result("FAIL","grid_radio_standing_room","clear receiving tile missing") setPhase("finish",current) return end
        H.player:teleportTo(destination:getX()+0.5,destination:getY()+0.5,z)
        SC.GridRadio.reset()
        setPhase("grid_control_radio_send",current) return
    end
    if H.phase=="grid_control_radio_send" then
        if current-H.phaseStartedAt<1000 then return end
        if H.player:getEquipedRadio()~=f.handset and current-H.phaseStartedAt<6000 then return end
        if not check("grid_handset_native_equipped",H.player:getEquipedRadio()==f.handset,"engine receiver is the exact requested handset") then
            setPhase("finish",current) return
        end
        local okay,why=SC.GridRadio.request(H.player,f.handset)
        if not check("grid_radio_request",okay,tostring(why)) then setPhase("finish",current) return end
        setPhase("grid_control_radio_receive",current) return
    end
    if H.phase=="grid_control_radio_receive" then
        local report=SC.GridRadio.lastReport(H.player)
        if not report and current-H.phaseStartedAt<15000 then return end
        if not check("grid_radio_native_receipt",report and report:find("Muldraugh crack 40",1,true)~=nil,tostring(report)) then
            setPhase("finish",current) return
        end
        f.idleDone=f.job.doneHours f.idleSamples={}
        local original=G.pulse f.originalPulse=original
        G.pulse=function()
            local start=SC.Performance.preciseNowMs()
            original()
            local elapsed=SC.Performance.preciseNowMs()-start
            if #f.idleSamples<512 then f.idleSamples[#f.idleSamples+1]=elapsed end
        end
        SC.Performance.reset()
        setPhase("grid_control_idle_cost",current) return
    end
    if H.phase=="grid_control_idle_cost" then
        if current-H.phaseStartedAt<120000 then return end
        G.pulse=f.originalPulse
        check("grid_idle_timestamp_only",f.job.doneHours==f.idleDone,"120 seconds with the terminal closed did no cracking work")
        table.sort(f.idleSamples)
        local samples=f.idleSamples
        check("grid_idle_timer_profile",#samples>=60,string.format("samples=%d p95_ms=%.6f max_ms=%.6f",#samples,
            samples[math.max(1,math.ceil(#samples*.95))] or -1,samples[#samples] or -1))
        for _,metric in ipairs(SC.Performance.snapshot().topSystems) do
            if metric.key=="scheduler.computer-services" then
                result("PASS","grid_computer_services_profile",string.format("samples=%d p95_ms=%.6f max_ms=%.6f",
                    metric.runs or 0,metric.p95Ms,metric.maxMs))
            end
        end
        H.player:teleportTo(f.home:getX()+0.5,f.home:getY()+0.5,f.home:getZ())
        setPhase("grid_control_finish_crack",current) return
    end
    if H.phase=="grid_control_finish_crack" then
        if current-H.phaseStartedAt<1000 then return end
        f.job.doneHours=f.job.requiredHours-0.25 f.job.lastHours=f.job.lastHours-0.25
        G.snapshot(f.home)
        if not check("grid_crack_complete",ModData.get(G.KEY).sites.muldraugh.online,"controller published once") then setPhase("finish",current) return end
        f.appliances=sampleAppliances(f)
        getGameTime():setTimeOfDay(23)
        local active,message=G.energize(f.home,H.player)
        if not check("grid_energize",active,tostring(message)) then setPhase("finish",current) return end
        setPhase("grid_control_native_on",current) return
    end
    if H.phase=="grid_control_reload_load" then
        if current-H.phaseStartedAt<5000 then return end
        f.home=findComputer(f.saved.homeX,f.saved.homeY,f.saved.homeZ)
        local s=ModData.get(G.KEY)
        check("grid_reload_lease",s and s.on and getSandboxOptions():getElecShutModifier()==s.written,"native value matches persisted lease")
        check("grid_reload_heat",s and s.heat>=f.saved.heat and s.heat<f.saved.heat+10,"heat continues from checkpoint")
        check("grid_reload_hydro",getWorld():isHydroPowerOn(),"real AmbientStreamManager restored power")
        if not check("grid_reload_computer",f.home~=nil,"exact saved computer loaded") then setPhase("finish",current) return end
        f.appliances=sampleAppliances(f)
        f.original=f.saved.original
        setPhase("grid_control_native_on",current) return
    end
    if H.phase=="grid_control_native_on" then
        if not getWorld():isHydroPowerOn() then
            if current-H.phaseStartedAt>15000 then result("FAIL","grid_hydro_on","real hydro flag stayed off") setPhase("finish",current) end
            return
        end
        local fridges,lights=applianceCounts(f)
        check("grid_hydro_on",true,"real hydro flag true")
        check("grid_native_lights",#f.appliances.switches>0 and lights==#f.appliances.switches,
            "powered="..lights.."/"..#f.appliances.switches)
        if #f.appliances.fridges>0 then check("grid_native_fridges",fridges==#f.appliances.fridges,"powered="..fridges.."/"..#f.appliances.fridges)
        else result("SKIP","grid_native_fridges","no grid-only fridge loaded beside this fixture") end
        if H.config.grid_control_stage=="true" then
            local saved=ModData.getOrCreate("LF_GridAcceptance")
            saved.homeX,saved.homeY,saved.homeZ=f.home:getX(),f.home:getY(),f.home:getZ()
            saved.heat,saved.original=ModData.get(G.KEY).heat,f.original
            check("grid_reload_checkpoint",true,"retained energized clone for second run")
            setPhase("finish",current) return
        end
        showGrid(H,SC,f.home)
        setPhase("grid_control_on_photo",current) return
    end
    if H.phase=="grid_control_on_photo" then
        if current-H.phaseStartedAt<2500 then return end
        shot(H,"energized") closeComputer(SC)
        local s=ModData.get(G.KEY)
        s.heat=99.9 s.heatHours=U.hours()-0.1
        G.pulse()
        check("grid_breaker_trip",not s.on and s.lockedUntilCold,"native shutoff restored at heat limit")
        setPhase("grid_control_native_off",current) return
    end
    if H.phase=="grid_control_native_off" then
        if current-H.phaseStartedAt<5000 then return end
        local fridges,lights=applianceCounts(f)
        check("grid_hydro_off",not getWorld():isHydroPowerOn(),"native blackout marker switched hydro off")
        check("grid_lights_off",lights==0,"grid-only switches off="..lights)
        check("grid_fridges_off",fridges==0,"grid-only fridges off="..fridges)
        check("grid_trip_lock",G.energize(f.home,H.player)==false,"warm tripped breaker refuses restart")
        shot(H,"blackout")
        getSandboxOptions():set("ElecShutModifier",f.original) getSandboxOptions():toLua()
        setPhase("finish",current)
    end
end
SCRealSandboxHarnessProbes=SCRealSandboxHarnessProbes or {}
SCRealSandboxHarnessProbes.SCGridControlProbe=Probe
return Probe
