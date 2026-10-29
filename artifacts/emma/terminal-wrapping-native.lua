-- SPDX-License-Identifier: MIT
-- Reproduce the reported Brooks Library record in the real native UI.
local run={step=0,next=0}
local function log(value)
    print("EMMA_WRAP|"..value)
    local writer=getFileWriter("SurvivorCompanionHarness/terminal-wrapping.log",true,true)
    if writer then writer:write(value.."\n") writer:close() end
end
local function computer()
    local sq=getCell():getGridSquare(12035,6739,0)
    if sq then for i=0,sq:getObjects():size()-1 do
        local object=sq:getObjects():get(i)
        if SurvivorCompanion.Terminal.isComputer(object) then return object end
    end end
end
local function verify(w)
    local divider=w.layout.right-w:sidebarWidth()
    assert(w:sidebarWidth()>0,"native menu divider is missing")
    local parts,maxWidth={},0
    for _,row in ipairs(w:transcriptRows()) do
        local span=getTextManager():MeasureStringX(w.font,row.text)*w.textZoom
        assert(span<=w:transcriptWidth()+0.01,"native text crosses its pixel budget")
        maxWidth=math.max(maxWidth,span)
        if row.source.text==run.entry.text then parts[#parts+1]=row.text end
    end
    assert(table.concat(parts," "):gsub("%s+","")==run.entry.text:gsub("%s+",""),
        "native wrapping lost or duplicated archive characters")
    local glow=w.layout.skin.glow
    assert(w.layout.left+w:transcriptWidth()+glow<divider,"native clip reaches the divider")
    log("PASS native glyph width="..maxWidth.." budget="..w:transcriptWidth().." divider="..divider.."; exact archive text preserved")
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
        if not run.pc then assert(now<run.deadline,"native desktop not streamed") run.next=now+500 return end
        local state=SC.Terminal.computerState(player,run.pc)
        run.originalArchive,run.originalTheme=state.archive,state.theme
        state.archive,state.theme="brooks_irma","purple"
        assert(SC.Terminal.open(player,run.pc),"native terminal refused")
        local w=SC.Terminal.window w:flush()
        if w.system.locked then w.entry:setText(w.system.puzzle.answer) w:submit() w:flush() end
        w.brand,w.logoTexture="BrooksLibrary",SC.TerminalBrands.texture("BrooksLibrary","purple")
        run.entry=SC.TerminalFiles.get("brooks_irma").entries[1]
        assert(run.entry.title=="Summer reading","reported archive fixture changed")
        w.rows,w.renderRows,w.readingAnchor,w.scroll={},nil,nil,0
        w.menuPage="files" w:setFocusMode("menu")
        w:displayLocalFile(run.entry,false)
        w:setFocusMode("chat")
        run.window=w run.step,run.next=2,now+700
    elseif run.step==2 then
        verify(run.window)
        run.capture="emma-wrap-brooks"
        run.step,run.next=3,now+500
    elseif run.step==3 then
        local w=run.window
        w:setFocusMode("menu") w:transcriptRows()
        w:setFocusMode("chat") verify(w)
        run.capture="emma-wrap-focus-return"
        run.step,run.next=4,now+500
    elseif run.step==4 then
        run.window:close()
        local state=SC.Terminal.computerState(player,run.pc)
        state.archive,state.theme=run.originalArchive,run.originalTheme
        assert(SC.Terminal.window==nil and getSpecificPlayer(1)==nil,"native wrapping preview leaked UI or a view")
        log("PASS native terminal wrapping acceptance complete") run.step=99
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
