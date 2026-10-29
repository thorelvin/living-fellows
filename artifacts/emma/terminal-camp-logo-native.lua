-- SPDX-License-Identifier: MIT
-- Camp-header preview through the native UI in a disposable clone.
local run={step=0,next=0,index=1}
local themes={"green","sand","aqua","purple"}
local function log(value)
    print("EMMA_CAMP_LOGO|"..value)
    local writer=getFileWriter("SurvivorCompanionHarness/terminal-camp-logo.log",true,true)
    if writer then writer:write(value.."\n") writer:close() end
end
local function computer()
    local square=getCell():getGridSquare(12035,6739,0)
    if square then for index=0,square:getObjects():size()-1 do
        local object=square:getObjects():get(index)
        if SurvivorCompanion.Terminal.isComputer(object) then return object end
    end end
end
local function show()
    local SC=SurvivorCompanion
    if SC.Terminal.window then SC.Terminal.window:close() end
    local state=SC.Terminal.computerState(run.player,run.pc)
    state.theme=themes[run.index] state.paletteVersion=SC.TerminalPresentation.PALETTE_VERSION
    assert(SC.Terminal.open(run.player,run.pc),"native preview reopen failed")
    local w=SC.Terminal.window w:flush()
    if w.system.locked then w.entry:setText(w.system.puzzle.answer) w:submit() w:flush() end
    assert(w.brand=="_camp","real desktop is not inside the active camp")
    assert(w.logoTexture==SC.TerminalBrands.texture("_camp",themes[run.index]),"camp source mismatch")
    run.window=w run.next=getTimestampMs()+700
end
local function tick()
    local SC=SurvivorCompanion local player=getSpecificPlayer(0) local now=getTimestampMs()
    if now<run.next or not SC or not SC.Terminal or not player or not player:getSquare() then return end
    if run.step==0 then
        run.player=player player:setGodMod(true) player:setGhostMode(true)
        player:teleportTo(12034.5,6739.5,0)
        run.step,run.next,run.deadline=1,now+6000,now+45000
    elseif run.step==1 then
        run.pc=computer()
        if not run.pc then assert(now<run.deadline,"native desktop did not stream") run.next=now+500 return end
        assert(SC.Terminal.powered(run.pc),"real desktop is not powered")
        local original=SC.Terminal.computerState(player,run.pc)
        run.originalTheme,run.originalArchive,run.originalIdentity=original.theme,original.archive,original.identity
        show() run.step=2
    elseif run.step==2 then
        local w=run.window
        assert(w.lastNativeLogoDraw,"native keyed logo draw unavailable")
        assert(w.system.archive==run.originalArchive and w.system.identity==run.originalIdentity,
            "artwork changed the saved owner or computer identity")
        local box=SC.TerminalPresentation.headerLogoBox(w.layout,w.brand,w.charWidth)
        assert(box.x>=w.layout.left+w.layout.pad+w.charWidth*25 and box.x+box.width<=w.layout.right,
            "camp header intrudes into captions or leaves the CRT canvas")
        local color=w.colors.title
        log("PASS "..themes[run.index].." native keyed monochrome header; palette="..color[2]..","..color[3]..","..color[4])
        run.capture="emma-camp-v2-"..themes[run.index]
        run.step,run.next=3,now+400
    elseif run.step==3 then
        if run.index<#themes then run.index=run.index+1 show() run.step=2
        else
            run.window:close()
            SC.Terminal.computerState(player,run.pc).theme=run.originalTheme
            assert(SC.Terminal.window==nil and getSpecificPlayer(1)==nil,"preview leaked a window or player view")
            log("PASS native camp logo acceptance complete") run.step=99
        end
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
