-- SPDX-License-Identifier: MIT
-- Real surveys and terminal rendering in disposable native save clones.
-- Setup adds a powered PC using normal hardware/connection APIs. No world,
-- scan, authorization, clock or UI function is replaced for acceptance.
local Probe={}
SCRealSandboxHarnessProbes=SCRealSandboxHarnessProbes or {}
SCRealSandboxHarnessProbes.SCBuildingScanProbe=Probe
local function call(object,name,...) return SurvivorCompanion.ControlUtil.call(object,name,...) end
local function log(text) print("SC_REAL_SANDBOX|BUILDING_SCAN|"..text) end
local function screenshot(H,suffix) getCore():TakeFullScreenshot(H.config.run_id.."-scan-"..suffix..".png") end
local function unlock(SC,state,player)
    if state.locked then
        local puzzle=SC.TerminalSystem.ensurePuzzle(state,SC.ControlUtil.skill(player))
        assert(SC.TerminalSystem.act(state,puzzle.answer,SC.ControlUtil.hours())=="success","native password action failed")
    end
end
local function locate(H,f,radius)
    local player=H.player
    local x,y=math.floor(player:getX()),math.floor(player:getY())
    local best,score
    for dx=-radius,radius do for dy=-radius,radius do
        local square=getCell():getGridSquare(x+dx,y+dy,0)
        local def=call(square,"getBuildingDef")
        if def and (not f.expectedDef or def==f.expectedDef) and call(square,"TreatAsSolidFloor")==true and not SurvivorCompanion.Topology.squareHasStairs(square)
            and SurvivorCompanion.GameplayUtil.isSquareFree(square) then
            local area=(def:getX2()-def:getX())*(def:getY2()-def:getY())
            local rank=f.site==3 and -area+math.abs(dx)+math.abs(dy) or dx*dx+dy*dy
            if not score or rank<score then best,score=square,rank end
        end
    end end
    return best
end
local function prepare(H,f,tile)
    local SC,player=SurvivorCompanion,H.player
    f.pc=IsoObject.new(tile,"appliances_com_01_72","Computer") tile:AddTileObject(f.pc)
    local inventory=player:getInventory()
    inventory:AddItem("Base.Screwdriver")
    for _=1,3 do inventory:AddItem("Base.ElectricWire") end
    for _=1,6 do inventory:AddItem("Base.ElectronicsScrap") end
    local battery=inventory:AddItem("Base.CarBattery1") assert(battery,"no native battery")
    SC.ControlUtil.setCharge(battery,.95)
    local okay,reason=SC.TerminalHardware.install(player,f.pc,"ups",battery) assert(okay,reason)
    assert(SC.Terminal.powered(f.pc),"real powered backup required")
    local system=SC.Terminal.computerState(player,f.pc) unlock(SC,system,player)
    okay,reason=SC.BuildingControls.connect(player,f.pc) assert(okay,reason)
    f.panel=SC.BuildingControls.panel(f.pc,false)
    -- Security is solved through its normal puzzle, not a spoofed flag.
    unlock(SC,f.panel.security,player)
    assert(SC.Terminal.open(player,f.pc),"native terminal open failed")
    f.window=SC.Terminal.window f.window:flush()
    f.draw={idleMs=0,idleCalls=0,runningMs=0,runningCalls=0}
    f.originalDraw=SC.TerminalScanUI.draw
    local original=f.originalDraw
    SC.TerminalScanUI.draw=function(window,now)
        local started=getTimestampMs()
        original(window,now)
        local prefix=f.measuring or "idle"
        f.draw[prefix.."Ms"]=f.draw[prefix.."Ms"]+getTimestampMs()-started
        f.draw[prefix.."Calls"]=f.draw[prefix.."Calls"]+1
    end
    local def=tile:getBuildingDef()
    log("site="..f.site.." nativeBounds="..def:getX()..","..def:getY().."-"..def:getX2()..","..def:getY2()
        .." floors="..def:getMinLevel()..".."..def:getMaxLevel().." Electrical="..SC.ControlUtil.skill(player))
    f.definition=def
    assert(SC.TerminalScanUI.open(f.window,false),"native Equipment open failed")
    f.lastIdleFrame=nil f.idleFrames={} f.frames={} f.seenFloors={} f.deviceOpened=false f.paused=false
    return true
end
local function nextSite(H,f,current,result,setPhase)
    local SC=SurvivorCompanion
    if f.window then f.window:close() end
    if f.originalDraw then SC.TerminalScanUI.draw=f.originalDraw f.originalDraw=nil end
    f.site=f.site+1
    if f.site==2 and H.config.building_scan_seed_only=="true" then setPhase("finish",current) return end
    if f.site==2 then H.player:teleportTo(8140,11738,0)
    elseif f.site==3 then setPhase("building_scan_catalogue",current) return
    elseif f.site==4 and f.basement then
        f.expectedDef=f.basement
        H.player:teleportTo(f.basement:getX()+4,f.basement:getY()+4,0)
    elseif f.site==4 then
        result("SKIP","scan_live_basement","no bounded reachable basement found in native building metadata")
        setPhase("finish",current) return
    else setPhase("finish",current) return end
    setPhase("building_scan_load",current)
end
local function percentile(values,fraction)
    if #values==0 then return 0 end
    table.sort(values) return values[math.max(1,math.ceil(#values*fraction))]
end
function Probe.step(H,current,check,result,setPhase)
    local SC=SurvivorCompanion
    if H.phase=="building_scan_setup" then
        if current-H.phaseStartedAt<3000 then return end
        if SC.UI then SC.UI.close() end
        H.buildingScan={site=1} setPhase("building_scan_load",current) return
    end
    local f=H.buildingScan
    if H.phase=="building_scan_catalogue" then
        f.catalogue=f.catalogue or {list=getWorld():getMetaGrid():getBuildings(),index=0}
        local c=f.catalogue
        for _=1,256 do
            if c.index>=c.list:size() then break end
            local def=c.list:get(c.index) c.index=c.index+1
            local width,height=def:getX2()-def:getX()+1,def:getY2()-def:getY()+1
            local levels=def:getMaxLevel()-def:getMinLevel()+1
            local tiles=(width+12)*(height+12)*levels
            local distance=(def:getX()-8140)^2+(def:getY()-11738)^2
            if math.max(width,height)>=125 and math.max(width,height)<250 and tiles<35000 and def:getMinLevel()==0
                and (not c.largeDistance or distance<c.largeDistance) then f.large=def c.largeDistance=distance end
            if def:getMinLevel()<0 and def:getMaxLevel()>=0 and tiles<20000 and math.max(width,height)<100
                and (not c.basementDistance or distance<c.basementDistance) then f.basement=def c.basementDistance=distance end
        end
        if c.index<c.list:size() then return end
        if not f.large then result("FAIL","scan_large_native_site","no suitable large native building") setPhase("finish",current) return end
        f.expectedDef=f.large
        H.player:teleportTo(f.large:getX()+4,f.large:getY()+4,0)
        log("large native candidate="..f.large:getX()..","..f.large:getY().."-"..f.large:getX2()..","..f.large:getY2()
            .." basement="..tostring(f.basement and f.basement:getMinLevel()))
        setPhase("building_scan_load",current) return
    end
    if H.phase=="building_scan_load" then
        if current-H.phaseStartedAt<6000 then return end
        local tile=locate(H,f,f.site==1 and 12 or f.site==2 and 6 or 22)
        if not tile then
            if current-H.phaseStartedAt>45000 then result("FAIL","scan_native_site_"..f.site,"native building not loaded") setPhase("finish",current) end
            return
        end
        f.tile=tile H.player:teleportTo(tile:getX()+.5,tile:getY()+.5,tile:getZ())
        setPhase("building_scan_place",current) return
    end
    if H.phase=="building_scan_place" then
        if current-H.phaseStartedAt<1000 then return end
        prepare(H,f,f.tile) f.measuring="idle" setPhase("building_scan_idle",current) return
    end
    if H.phase=="building_scan_idle" then
        if f.lastIdleFrame then f.idleFrames[#f.idleFrames+1]=current-f.lastIdleFrame end f.lastIdleFrame=current
        if current-H.phaseStartedAt<1500 then return end
        check("scan_no_automatic_discovery_"..f.site,SC.BuildingScan.state(f.pc)==nil,"register/connect/Equipment remain idle")
        assert(SC.TerminalScanUI.open(f.window,true),"explicit start failed")
        f.started=current f.lastFrame=current f.measuring="running" setPhase("building_scan_running",current) return
    end
    if H.phase=="building_scan_pause" then
        if current-H.phaseStartedAt<2000 then return end
        local state=SC.BuildingScan.state(f.pc)
        check("scan_closed_holds",state.status=="paused" and state.processed==f.pauseCursor,"closed for two real seconds")
        assert(SC.Terminal.open(H.player,f.pc),"reopen failed") f.window=SC.Terminal.window f.window:flush()
        SC.TerminalScanUI.open(f.window,false)
        check("scan_reopen_requires_resume",SC.BuildingScan.state(f.pc).status=="paused","opening Equipment cannot resume")
        SC.TerminalScanUI.input(f.window,"scan building")
        f.started=f.started+current-H.phaseStartedAt f.lastFrame=current
        setPhase("building_scan_running",current) return
    end
    if H.phase=="building_scan_running" then
        local w=f.window local state=SC.BuildingScan.state(f.pc)
        if not state then result("FAIL","scan_native_state","lost native panel/connection") setPhase("finish",current) return end
        if w.closed then result("FAIL","scan_native_window","native terminal closed unexpectedly") setPhase("finish",current) return end
        if #f.frames<10000 then f.frames[#f.frames+1]=current-f.lastFrame end f.lastFrame=current
        for _,floor in ipairs(state.floors) do if floor.found>0 then f.seenFloors[floor.z]=true end end
        if not f.levelsChecked then
            f.levelsChecked=true
            local planned=f.definition:getMaxLevel()-f.definition:getMinLevel()+1
            check("scan_levels_shown_"..f.site,#state.floors==planned,"shown="..#state.floors.." planned="..planned)
        end
        if not f.earlyShot and current-f.started>7000 then
            screenshot(H,"site"..f.site.."-running") f.earlyShot=true
            log("early screenshot, progress="..state.percent.." total="..state.total.." rate="..state.rate)
        end
        if f.site==1 and not f.paused and state.percent>20 and not state.done then
            f.paused=true f.pauseCursor=state.processed w:close()
            setPhase("building_scan_pause",current) return
        end
        if not f.deviceOpened then
            for _,row in ipairs(SC.BuildingScan.rows(f.pc,true)) do if not row.readonly then
                SC.TerminalScanUI.input(w,"",{scanAction="row",scanValue=row})
                check("scan_device_during_survey_"..f.site,w.menuPage=="device" and SC.BuildingScan.state(f.pc).status=="running","existing device screen retains active scan")
                assert(SC.TerminalScanUI.returnDevice(w),"return from native device failed")
                f.deviceOpened=true break
            end end
        end
        if state.done then
            f.seconds=(current-f.started)/1000
            local expected=state.baseTotal/state.rate
            check("scan_rate_"..f.site,f.seconds>=expected*.9 and f.seconds<expected*1.5+3,
                "actual="..f.seconds.." expected="..expected.." tiles="..state.total.." planned="..state.baseTotal.." rate="..state.rate)
            local total,out=0,0
            for _,floor in ipairs(state.floors) do total=total+floor.done out=out+floor.outOfRange end
            check("scan_floor_accounting_"..f.site,total+(state.hiddenEmptyTiles or 0)==state.processed and out==state.outOfRange,
                "floors="..#state.floors.." processed="..state.processed.." out="..state.outOfRange)
            if f.site==2 then
                local seen=0 for _ in pairs(f.seenFloors) do seen=seen+1 end
                check("scan_real_multiple_floors",f.definition:getMaxLevel()>0 and seen>=2,"floors with native equipment="..seen)
            end
            if f.site==3 then check("scan_real_out_of_range",state.outOfRange>0 and (state.status=="partial" or state.status=="limited"),"out="..state.outOfRange.." state="..state.status) end
            if f.site==4 then
                local foundBelow=false for z in pairs(f.seenFloors) do if z<0 then foundBelow=true end end
                check("scan_real_basement",f.definition:getMinLevel()<0 and foundBelow,"native basement equipment detected="..tostring(foundBelow))
            end
            log("site="..f.site.." complete controls="..state.controls.." finds="..state.finds.." time="..f.seconds
                .." idleFrameP50="..percentile(f.idleFrames,.5).." idleFrameP95="..percentile(f.idleFrames,.95)
                .." frameP50="..percentile(f.frames,.5).." frameP95="..percentile(f.frames,.95)
                .." idleDrawMs="..f.draw.idleMs/math.max(1,f.draw.idleCalls)
                .." scanDrawMs="..f.draw.runningMs/math.max(1,f.draw.runningCalls))
            f.theme=1 setPhase("building_scan_colours",current) return
        end
        if current-f.started>720000 then result("FAIL","scan_native_deadline","survey exceeded twelve minutes") setPhase("finish",current) end
        return
    end
    if H.phase=="building_scan_colours" then
        if current-H.phaseStartedAt<700 then return end
        local theme=({"green","sand","aqua","purple"})[f.theme]
        if theme then
            if f.captureTheme~=theme then
                -- Reopen through the real theme/texture/entry setup. The native
                -- screenshot reads a rendered frame, so capture on a later tick.
                f.window.system.theme=theme f.window:close()
                assert(SC.Terminal.open(H.player,f.pc),"theme reopen failed")
                f.window=SC.Terminal.window f.window:flush()
                SC.TerminalScanUI.open(f.window,false)
                f.captureTheme=theme H.phaseStartedAt=current return
            end
            screenshot(H,"site"..f.site.."-"..theme)
            f.theme=f.theme+1 H.phaseStartedAt=current return
        end
        f.earlyShot=nil
        nextSite(H,f,current,result,setPhase)
    end
end
return Probe
