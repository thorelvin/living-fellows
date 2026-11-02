-- SPDX-License-Identifier: MIT
-- Phase 0 only: real native bindings and map fixtures in a disposable save.
SCRealSandboxHarnessProbes=SCRealSandboxHarnessProbes or {}
local Probe={} SCRealSandboxHarnessProbes.SCPersonaReadinessProbe=Probe
local function U() return SurvivorCompanion.ControlUtil end
local function call(object,method,...) return U().call(object,method,...) end
local function log(value) print("SC_PERSONA_ZERO|"..value) end
local function shot(H,name) getCore():TakeFullScreenshot(H.config.run_id.."-persona-zero-"..name..".png") end
local function clearZombies()
    local list=getCell():getZombieList()
    for i=list:size()-1,0,-1 do local z=list:get(i) z:removeFromWorld() z:removeFromSquare() end
end
local function standBeside(player,object)
    local sq=object:getSquare()
    for _,d in ipairs({{1,0},{0,1},{-1,0},{0,-1}}) do
        local at=getCell():getGridSquare(sq:getX()+d[1],sq:getY()+d[2],sq:getZ())
        if at and SurvivorCompanion.GameplayUtil.isSquareFree(at) then
            player:teleportTo(at:getX()+.5,at:getY()+.5,at:getZ()) return at
        end
    end
end
local function sampleStats(H,check)
    local stats,moodles=H.player:getStats(),H.player:getMoodles()
    for _,spec in ipairs({{"STRESS","STRESS"},{"UNHAPPINESS","UNHAPPY"},{"BOREDOM","BORED"}}) do
        local kind,mtype=CharacterStat[spec[1]],MoodleType[spec[2]]
        local saved=stats:get(kind) local maximum=kind:getMaximumValue()
        log("STAT|"..spec[1].."|min="..kind:getMinimumValue().."|max="..maximum.."|default="..kind:getDefaultValue())
        for _,fraction in ipairs({0,.1,.2,.25,.3,.4,.5,.6,.7,.8,.9,1}) do
            stats:set(kind,maximum*fraction) moodles:Update()
            log("MOODLE|"..spec[1].."|value="..stats:get(kind).."|level="..moodles:getMoodleLevel(mtype))
        end
        stats:set(kind,maximum*.5) stats:remove(kind,maximum*.2)
        local removed=stats:get(kind) stats:add(kind,maximum*.05)
        check("persona_stat_"..spec[1],math.abs(removed-maximum*.3)<.0001
            and math.abs(stats:get(kind)-maximum*.35)<.0001,"native measured get/set/add/remove; maximum="..maximum)
        local start=spec[1]=="STRESS" and .6 or spec[1]=="BOREDOM" and 60 or 50
        local relief=spec[1]=="STRESS" and .25 or spec[1]=="BOREDOM" and 25 or 20
        stats:set(kind,start) moodles:Update() local before=moodles:getMoodleLevel(mtype)
        stats:remove(kind,relief) moodles:Update()
        check("persona_one_level_"..spec[1],before-moodles:getMoodleLevel(mtype)==1,
            "native moodle "..before.." -> "..moodles:getMoodleLevel(mtype).." for reduction="..relief)
        stats:set(kind,saved) moodles:Update()
    end
    for _,name in ipairs({"Tired","Panic","Hungry","Pain","Drunk","Unhappy","Wet","Bored"}) do
        local okay,mixed=pcall(function() return MoodleType[name] end)
        local uppercase=string.upper(name)
        local native=MoodleType[uppercase]
        check("persona_moodle_"..name,native~=nil,"uppercase="..uppercase.." mixed="..tostring(okay and mixed or nil))
        log("MOODLE_KEY|"..name.."|mixed="..tostring(okay and mixed or nil).."|native="..tostring(native)
            .."|helper="..SurvivorCompanion.GameplayUtil.moodleLevel(H.player,uppercase,-1))
    end
end
local function prototype(H,f)
    local SC=SurvivorCompanion
    assert(SC.Terminal.open(H.player,f.pc),"native terminal did not open")
    local w=SC.Terminal.window f.window=w w:flush()
    w.rows,w.queue,w.typing,w.state={}, {}, nil,"idle" w.startupReady=true
    w.closeButton:setVisible(false)
    w.entry.backgroundColor.a=0 w.entry.borderColor.a=0
    w.entry:setTextRGBA(0,0,0,0) w.entry.javaObject:setPlaceholderTextRGBA(0,0,0,0)
    w.entry:setPlaceholderText("")
    if w.entry.javaObject:getFrame() then w.entry:setFrameAlpha(0) end
    w.entry:setHasFrame(false)
    w.entry.javaObject:setClearButton(false)
    w.entry.onCommandEntered=function(box) f.entered=box:getText() box:setText("") end
    w.prerender=function(self)
        self:drawRect(0,0,self:getWidth(),self:getHeight(),1,.005,.008,.007)
        self.entry:setX(f.offscreen and -10000 or self.layout.left)
        self.entry:setY(f.offscreen and -10000 or self.layout.titleY+self.rowHeight*2)
        self:drawText(self.entry:getText().."_",self.layout.left,self.layout.titleY,.55,.9,.8,1,self.font)
    end
    w:setFocusMode("chat") w.entry:setText("") w.entry:focus() w.entry.javaObject:setIgnoreFirst(false)
    return w
end
local function nativeType(w,text)
    for i=1,#text do
        -- Kahlua's char converter takes a numeric code point, not a Lua string.
        w.entry.javaObject:putCharacter(string.byte(text,i))
    end
end
local function clean(H,f)
    local SC=SurvivorCompanion
    if SC.Terminal.window then SC.Terminal.window:close() end
    if f.generator then f.generator:setActivated(false) f.generator:removeFromWorld() f.generator:removeFromSquare() end
    if f.chair then f.chair:removeFromWorld() f.chair:removeFromSquare() end
    for _,z in ipairs(f.zombies or {}) do z:removeFromWorld() z:removeFromSquare() end
    getWorld():setHydroPowerOn(f.hydro)
    getSandboxOptions():set("ElecShutModifier",f.electricity) getSandboxOptions():toLua()
    H.player:setMaxWeightBase(f.maxWeight)
    H.player:setGhostMode(f.ghost) H.player:setGodMod(f.god)
end
function Probe.step(H,current,check,result,setPhase)
    local SC=SurvivorCompanion local f=H.personaZero
    if H.phase=="persona_zero_setup" then
        if current-H.phaseStartedAt<4000 then return end
        f={hydro=getWorld():isHydroPowerOn(),ghost=H.player:isGhostMode(),god=H.player:isGodMod(),zombies={},
            electricity=getSandboxOptions():getElecShutModifier(),maxWeight=H.player:getMaxWeightBase()}
        H.personaZero=f H.player:setGhostMode(true) clearZombies()
        if SC.UI then SC.UI.close() end
        for _,actor in ipairs(SC.Registry.living()) do SC.Actor.remove(actor) end
        sampleStats(H,check)
        H.player:setMaxWeightBase(1000)
        local x,y,z=math.floor(H.player:getX()),math.floor(H.player:getY()),math.floor(H.player:getZ())
        f.scan={x=x-32,y=y-32,z=z,width=65,height=65,cursor=0}
        getSandboxOptions():set("ElecShutModifier",2147483647) getSandboxOptions():toLua()
        getWorld():setHydroPowerOn(true)
        setPhase("persona_zero_home_scan",current) return
    elseif H.phase=="persona_zero_home_scan" then
        local s=f.scan
        for _=1,128 do
            if s.cursor>=s.width*s.height then break end
            local n=s.cursor s.cursor=n+1
            local tile=getCell():getGridSquare(s.x+n%s.width,s.y+math.floor(n/s.width),s.z)
            for _,object in ipairs(U().list(call(tile,"getObjects"),64)) do
                if not f.pc and SC.Terminal.isComputer(object) then f.pc=object end
            end
        end
        if not f.pc and s.cursor<s.width*s.height then return end
        if not check("persona_real_desktop",f.pc~=nil,"real loaded home desktop") then clean(H,f) setPhase("finish",current) return end
        f.stand=standBeside(H.player,f.pc)
        check("persona_stand",f.stand~=nil,"native reachable adjacent square")
        setPhase("persona_zero_ui_begin",current) return
    elseif H.phase=="persona_zero_ui_begin" then
        if current-H.phaseStartedAt<1000 then return end
        check("persona_home_grid_power",SC.Terminal.powered(f.pc),"native hydro on; no power adapter replaced")
        local w=prototype(H,f)
        nativeType(w,"hello0123")
        check("persona_alpha_input",w.entry.javaObject:getInternalText()=="hello0123" and w.entry.javaObject:isFocused(),
            "internal="..w.entry.javaObject:getInternalText().." focus="..tostring(w.entry.javaObject:isFocused()))
        w.entry.javaObject:resetBlink()
        setPhase("persona_zero_ui_alpha",current) return
    elseif H.phase=="persona_zero_ui_alpha" then
        if current-H.phaseStartedAt<300 then return end
        f.window.entry.javaObject:resetBlink() shot(H,"alpha-native-caret")
        f.window.entry.javaObject:onKeyEnter()
        check("persona_native_enter",f.entered=="hello0123","native Enter reaches Lua consumer with digits intact")
        f.offscreen=true f.window.entry:focus() f.window.entry.javaObject:setIgnoreFirst(false)
        setPhase("persona_zero_ui_offscreen",current) return
    elseif H.phase=="persona_zero_ui_offscreen" then
        if current-H.phaseStartedAt<700 then return end
        nativeType(f.window,"hello0123")
        setPhase("persona_zero_ui_offscreen_read",current) return
    elseif H.phase=="persona_zero_ui_offscreen_read" then
        if current-H.phaseStartedAt<400 then return end
        check("persona_offscreen_input",f.window.entry:getText()=="hello0123" and f.window.entry.javaObject:isFocused(),"off-screen native child remains focused and editable")
        shot(H,"offscreen-custom-prompt")
        f.window.entry.javaObject:onOtherKey(Keyboard.KEY_ESCAPE)
        check("persona_hidden_close_escape",SC.Terminal.window==nil and f.window.closed==true,"native OtherKey -> real Escape handler closes with X hidden")
        -- A real seat fixture, immediately beside the real computer.
        for index=0,127 do
            local candidate=IsoObject.new(f.stand,"furniture_seating_indoor_01_"..index,"Persona readiness chair")
            if SeatingManager.getInstance():getTilePositionCount(candidate)>0 then
                f.chair=candidate
                log("SEAT_SPRITE|index="..index.."|positions="..SeatingManager.getInstance():getTilePositionCount(candidate)
                    .."|facing="..tostring(SeatingManager.getInstance():getFacingDirection(candidate)))
                break
            end
        end
        assert(f.chair,"no native seating-data chair fixture")
        f.stand:AddTileObject(f.chair)
        require "Vehicles/TimedActions/ISPathFindAction"
        assert(standBeside(H.player,f.chair),"no clear approach to native chair fixture")
        setPhase("persona_zero_seat_prepare",current) return
    elseif H.phase=="persona_zero_seat_prepare" then
        if current-H.phaseStartedAt<1000 then return end
        -- The vanilla Rest menu queues the path AND the sit/rest action. A
        -- pathToSitOnFurniture action alone only reaches the sitting position.
        ISWorldObjectContextMenu.onRest(f.chair,H.player:getPlayerNum())
        setPhase("persona_zero_seat",current) return
    elseif H.phase=="persona_zero_seat" then
        if not H.player:isSittingOnFurniture() and current-H.phaseStartedAt<12000 then return end
        f.seated=H.player:isSittingOnFurniture()
        check("persona_seat_binding",f.seated,"vanilla Rest result="..tostring(f.seated).." fsm="..tostring(call(H.player,"getActionStateName"))
            .." position="..H.player:getX()..","..H.player:getY())
        if f.seated then
            H.player:getStats():set(CharacterStat.ENDURANCE,1)
            check("persona_seated_use_accepted",SC.Terminal.use(H.player,f.pc)==true,"real terminal Loot timed action queued while sitting")
        end
        setPhase("persona_zero_seat_use",current) return
    elseif H.phase=="persona_zero_seat_use" then
        if current-H.phaseStartedAt<5000 then return end
        log("SEATED_USE|before="..tostring(f.seated).."|after="..tostring(H.player:isSittingOnFurniture()).."|opened="..tostring(SC.Terminal.window~=nil))
        if SC.Terminal.window then SC.Terminal.window:close() end
        ISTimedActionQueue.clear(H.player) call(H.player:getPathFindBehavior2(),"cancel")
        H.player:setSittingOnFurniture(false) H.player:setSitOnFurnitureObject(nil)
        H.player:setGodMod(true)
        H.player:teleportTo(5544.5,12463.5,0)
        setPhase("persona_zero_deep_load",current) return
    elseif H.phase=="persona_zero_deep_load" then
        if current-H.phaseStartedAt<8000 then return end
        f.deepScan={x=5496,y=12415,z=-13,width=96,height=96,cursor=0}
        f.deepPCs={} f.deepDrawers=0
        setPhase("persona_zero_deep_scan",current) return
    elseif H.phase=="persona_zero_deep_scan" then
        local s=f.deepScan
        for _=1,128 do
            if s.cursor>=s.width*s.height then break end
            local n=s.cursor s.cursor=n+1
            local tile=getCell():getGridSquare(s.x+n%s.width,s.y+math.floor(n/s.width),s.z)
            for _,object in ipairs(U().list(call(tile,"getObjects"),64)) do
                if SC.Terminal.isComputer(object) then
                    local drawer=SC.TerminalDrawers.find(object)
                    f.deepPCs[#f.deepPCs+1]=object
                    log("DEEP_PC|"..object:getX()..","..object:getY()..","..object:getZ().."|drawer="..tostring(drawer and drawer.type))
                    if drawer then f.deepDrawers=f.deepDrawers+1 f.deepPC=f.deepPC or object end
                end
            end
        end
        if s.cursor<s.width*s.height then return end
        if not check("persona_deep_map_computers",#f.deepPCs>0,"real floor -13 computers="..#f.deepPCs) then clean(H,f) setPhase("finish",current) return end
        check("persona_deep_drawer_finder",f.deepDrawers>0,"real floor -13 D.find successes="..f.deepDrawers)
        f.deepPC=f.deepPC or f.deepPCs[1]
        f.deepStand=standBeside(H.player,f.deepPC)
        setPhase("persona_zero_deep_power_on",current) return
    elseif H.phase=="persona_zero_deep_power_on" then
        if current-H.phaseStartedAt<1000 then return end
        local p=SC.TerminalWorld.powerState(f.deepPC:getSquare())
        log("DEEP_POWER|setting="..getSandboxOptions():getElecShutModifier().."|hydro="..tostring(getWorld():isHydroPowerOn()).."|grid="..tostring(p.grid).."|generator="..tostring(p.generator).."|terminal="..tostring(SC.Terminal.powered(f.deepPC)))
        getSandboxOptions():set("ElecShutModifier",0) getSandboxOptions():toLua()
        getWorld():setHydroPowerOn(false)
        setPhase("persona_zero_deep_power_off",current) return
    elseif H.phase=="persona_zero_deep_power_off" then
        if current-H.phaseStartedAt<1000 then return end
        local p=SC.TerminalWorld.powerState(f.deepPC:getSquare())
        log("DEEP_POWER|setting="..getSandboxOptions():getElecShutModifier().."|hydro="..tostring(getWorld():isHydroPowerOn()).."|grid="..tostring(p.grid).."|generator="..tostring(p.generator).."|terminal="..tostring(SC.Terminal.powered(f.deepPC)))
        local item=instanceItem("Base.Generator_Old")
        f.generator=IsoGenerator.new(item,getCell(),f.deepStand)
        f.generator:setConnected(true) f.generator:setFuel(f.generator:getMaxFuel()*.5)
        f.generator:setActivated(true) f.generator:sync()
        setPhase("persona_zero_deep_generator",current) return
    elseif H.phase=="persona_zero_deep_generator" then
        if current-H.phaseStartedAt<4000 then return end
        local p=SC.TerminalWorld.powerState(f.deepPC:getSquare())
        check("persona_deep_generator_binding",p.generator==true and SC.Terminal.powered(f.deepPC),"z=-13 activated="..tostring(f.generator:isActivated()).." connected="..tostring(f.generator:isConnected()).." supply="..tostring(p.generator).." terminal="..tostring(SC.Terminal.powered(f.deepPC)))
        shot(H,"deep-computer")
        f.generator:setActivated(false)
        H.player:teleportTo(6100.5,5400.5,0)
        setPhase("persona_zero_noise_load",current) return
    elseif H.phase=="persona_zero_noise_load" then
        if current-H.phaseStartedAt<7000 then return end
        clearZombies()
        for _,distance in ipairs({10,25,39,45}) do
            local list=addZombiesInOutfit(6100+distance,5400,0,1,nil,0)
            local z=list and list:get(0)
            if z then z:setTarget(nil) f.zombies[#f.zombies+1]=z
                log("NOISE_START|distance="..distance.."|x="..z:getX().."|y="..z:getY()) end
        end
        setPhase("persona_zero_noise_settle",current) return
    elseif H.phase=="persona_zero_noise_settle" then
        if current-H.phaseStartedAt<1500 then return end
        addSound(nil,6100,5400,0,40,40)
        check("persona_noise_native",#f.zombies==4,"one native world sound, radius=40 volume=40; invisible observer")
        setPhase("persona_zero_noise_observe",current) return
    elseif H.phase=="persona_zero_noise_observe" then
        if current-H.phaseStartedAt<10000 then return end
        for _,z in ipairs(f.zombies) do
            log("NOISE_END|x="..z:getX().."|y="..z:getY().."|target="..tostring(call(z,"getPathTargetX"))..","..tostring(call(z,"getPathTargetY")).."|fsm="..tostring(call(z,"getActionStateName")))
        end
        shot(H,"noise-scene") clean(H,f) setPhase("finish",current)
    end
end
