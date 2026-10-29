-- SPDX-License-Identifier: MIT
-- Real desktop, native UI renderer and ordinary boot timing in a disposable clone.
local run={step=0,next=0}
local function log(value)
    print("LARCH_BIOS|"..value)
    local w=getFileWriter("SurvivorCompanionHarness/terminal-bios.log",true,true)
    if w then w:write(value.."\n") w:close() end
end
local function pcAt()
    local sq=getCell():getGridSquare(12035,6739,0)
    if sq then for i=0,sq:getObjects():size()-1 do
        local object=sq:getObjects():get(i)
        if SurvivorCompanion.Terminal.isComputer(object) then return object end
    end end
end
local function selectTheme(theme)
    local SC=SurvivorCompanion
    local state=SC.Terminal.computerState(run.player,run.pc)
    state.theme=theme state.paletteVersion=SC.TerminalPresentation.PALETTE_VERSION
end
local function reopen(theme)
    local terminal=SurvivorCompanion.Terminal
    if terminal.window then terminal.window:close() end
    selectTheme(theme)
    assert(terminal.open(run.player,run.pc),"native terminal reopen failed")
    run.window=terminal.window
end
local function requestShot(name)
    run.capture="emma-bios-"..name
end
local function tick()
    local SC=SurvivorCompanion local player=getSpecificPlayer(0) local now=getTimestampMs()
    if now<run.next or not SC or not SC.Terminal or not player or not player:getSquare() then return end
    if run.step==0 then
        run.player=player player:setGodMod(true) player:setGhostMode(true)
        player:teleportTo(12034.5,6739.5,0)
        run.step,run.next,run.deadline=1,now+6000,now+45000
    elseif run.step==1 then
        run.pc=pcAt()
        if not run.pc then assert(now<run.deadline,"real desktop not streamed") run.next=now+500 return end
        assert(SC.Terminal.powered(run.pc),"native desktop lacks real power")
        run.originalTheme=SC.Terminal.computerState(player,run.pc).theme
        selectTheme("aqua")
        assert(SC.Terminal.use(player,run.pc),"native Use computer refused")
        run.step,run.deadline=2,now+30000
    elseif run.step==2 then
        local w=SC.Terminal.window
        if not w then assert(now<run.deadline,"native computer action did not open") return end
        run.window=w
        assert(w.biosTexture,"native BIOS texture not loaded")
        run.step=3
    elseif run.step==3 then
        local w=run.window local elapsed=now-w.postStarted
        if elapsed>=250 and not run.reveal then
            assert(w.state=="booting" and w.session==nil,"BIOS queried EMMA too early")
            requestShot("reveal-aqua") run.reveal=true
        elseif elapsed>=1050 and not run.full then
            assert(w.lastBiosNativeDraw,"BIOS did not use the native keyed phosphor renderer")
            requestShot("aqua") run.full=true
            log("PASS native animated BIOS reveal, aquamarine phosphor and no premature EMMA session")
        elseif elapsed>=SC.TerminalPresentation.BIOS_MS+850 and not run.post then
            assert(w.state=="booting" and w.session==nil,"POST skipped or read camp records")
            requestShot("post") run.post=true
        elseif elapsed>=SC.TerminalPresentation.BOOT_MS+1300 then
            assert(w.state~="booting","native POST never completed")
            if w.system.locked then
                w:flush() w.entry:setText(w.system.puzzle.answer) w:submit()
            end
            w:flush() assert(w.session,"EMMA failed to start after BIOS and POST")
            requestShot("welcome")
            log("PASS native POST completes before ordinary EMMA starts")
            run.step,run.next=4,now+500
        end
    elseif run.step==4 then
        reopen("sand") run.step=5
    elseif run.step==5 then
        if now-run.window.postStarted>=1050 then
            assert(run.window.lastBiosNativeDraw,"sand BIOS renderer unavailable")
            requestShot("sand") run.step,run.next=6,now+500
        end
    elseif run.step==6 then
        reopen("purple") run.step=7
    elseif run.step==7 then
        if now-run.window.postStarted>=1050 then
            assert(run.window.lastBiosNativeDraw,"purple BIOS renderer unavailable")
            requestShot("purple") run.step,run.next=8,now+500
        end
    elseif run.step==8 then
        local w=run.window
        w:submit()
        assert(w.state~="booting","Enter did not skip BIOS and POST")
        w:close()
        selectTheme(run.originalTheme)
        assert(SC.Terminal.window==nil and getSpecificPlayer(1)==nil,"boot leaked UI or created a secondary player")
        log("PASS native sand and purple BIOS, Enter skip and ordinary close")
        log("PASS native terminal BIOS acceptance complete") run.step=99
    end
end
local function safeTick()
    local okay,reason=pcall(tick)
    if not okay then log("FAIL "..tostring(reason)) Events.OnTick.Remove(safeTick) end
end
Events.OnTick.Add(safeTick)
Events.OnPostUIDraw.Add(function()
    if run.capture then getCore():TakeFullScreenshot(run.capture) log("SHOT "..run.capture) run.capture=nil end
end)
