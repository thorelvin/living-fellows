-- SPDX-License-Identifier: MIT
-- Actual powered desktop and native framebuffer; disposable clone only.
local run={step=0,next=0}
local function log(value)
    print("EMMA_PLACES|"..value)
    local writer=getFileWriter("SurvivorCompanionHarness/terminal-places.log",true,true)
    if writer then writer:write(value.."\n") writer:close() end
end
local function input(text)
    local w=SurvivorCompanion.Terminal.window
    w:flush() w:setFocusMode("chat") w.entry:setText(text) w:submit() w:flush()
    return w
end
local function computer()
    local square=getCell():getGridSquare(12035,6739,0)
    if square then for i=0,square:getObjects():size()-1 do
        local object=square:getObjects():get(i)
        if SurvivorCompanion.Terminal.isComputer(object) then return object end
    end end
end
local function shot(name) getCore():TakeFullScreenshot("emma-places-"..name) log("SHOT "..name) end
local ids={"ArtGalleryLouisville","HomeSweetGnome","CircuitalHealing","IrvingtonSpeedway","SunsetPines","RoxysRollerRink",
    "CircuitalHealing","RoxysRollerRink"}
local function show(index)
    local SC=SurvivorCompanion local id=ids[index]
    SC.Terminal.window:close()
    local state=SC.Terminal.computerState(getSpecificPlayer(0),run.pc)
    local profile=SC.TerminalFiles.choose(SC.TerminalBrands.kind(id),1,id)
    assert(profile.brand==id,"new header has an unrelated owner")
    state.archive,state.theme=profile.id,index>6 and "purple" or SC.TerminalPresentation.themeFor(1,id)
    assert(SC.Terminal.open(getSpecificPlayer(0),run.pc),"preview failed to reopen")
    local w=SC.Terminal.window w:flush()
    w.brand,w.logoTexture=id,SC.TerminalBrands.texture(id,w.system.theme)
    assert(w.logoTexture and not SC.TerminalBrands.BACKINGS[id],"transparent header unavailable or has a backing")
    w.rows,w.renderRows,w.readingAnchor,w.scroll={},nil,nil,0
    w.menuPage,w.menuSelection="files",1 w:setFocusMode("chat")
    w:displayLocalFile(profile.entries[index==5 and 4 or 1],false)
    assert(#w:menuLayout()==5,"new four-entry owner shortcuts do not all fit")
end
local function tick()
    local SC=SurvivorCompanion local player=getSpecificPlayer(0) local now=getTimestampMs()
    if now<run.next or not player or not player:getSquare() or not SC or not SC.TerminalKnowledge then return end
    if run.step==0 then
        player:teleportTo(12034.5,6739.5,0)
        run.step,run.next,run.deadline=1,now+6000,now+45000
    elseif run.step==1 then
        run.pc=computer()
        if not run.pc then assert(now<run.deadline,"clone desktop unavailable") run.next=now+500 return end
        assert(SC.Terminal.use(player,run.pc),"native Use computer refused")
        run.step,run.next,run.deadline=2,now+1000,now+30000
    elseif run.step==2 then
        local w=SC.Terminal.window
        if not w then assert(now<run.deadline,"native Use computer did not finish") run.next=now+500 return end
        w:flush() if w.system.locked then input(w.system.puzzle.answer) end
        assert(#SC.TerminalFiles.all()==142 and #SC.TerminalLore.REFERENCE==150,"expanded content did not load")
        run.archive,run.theme=w.system.archive,w.system.theme
        for _,pair in ipairs({{"Art Gallery of Louisville","local_artgallery"},{"Home Sweet Gnome","local_homesweetgnome"},
            {"Circuital Healing","local_circuitalhealing"},{"Irvington Speedway","local_irvingtonspeedway"},
            {"Sunset Pines","local_sunsetpines"},{"Roxy's Roller Rink","local_roxysrollerrink"},
            {"the fourth switch","fragment_fourthswitch"},{"last collected","fragment_collectionslip"},
            {"July mittens","fragment_mittens"},{"the second bell","fragment_secondbell"},
            {"pencil rubbings","fragment_rubbings"},{"parking bay six","fragment_baysix"},
            {"the wrong hymn","fragment_wronghymn"},{"for the morning staff","fragment_morningstaff"}}) do
            input("tell me about "..pair[1])
            assert(w.session.context.intent=="lore" and w.session.context.referenceId==pair[2],"native topic alias failed: "..pair[1])
        end
        assert(w.system.archive==run.archive,"reading new lore replaced the saved owner")
        input("county files")
        for _,entry in ipairs(w.referenceCatalog) do assert(SC.TerminalLore.available(entry,w:referenceClock()),"future record exposed") end
        log("PASS native fourteen new read-only topic aliases, date-gated directory and retained old owner; available="..#w.referenceCatalog)
        input("back") input("tell me about for the morning staff")
        run.step,run.next=3,now+1500
    elseif run.step==3 then
        shot("outbreak")
        run.index=1 show(run.index)
        run.step,run.next=4,now+1500
    elseif run.step==4 then
        local w=SC.Terminal.window local id=ids[run.index]
        assert(w.lastNativeLogoDraw and not SC.Terminal.nativeLogoUnavailable,"native logo renderer failed")
        shot("logo-"..id..(run.index>6 and "-purple" or ""))
        log("PASS native header "..id.." theme="..w.system.theme.." owner="..w.system.archive.." font="..w.rowHeight)
        run.index=run.index+1
        if run.index<=#ids then show(run.index) run.next=now+1500
        else
            w.system.archive,w.system.theme=run.archive,run.theme
            assert(getSpecificPlayer(1)==nil,"terminal claimed a secondary player slot")
            w:close()
            log("PASS native terminal places acceptance complete")
            run.step,run.next=99,now+1000000
        end
    end
end
Events.OnTick.Add(function()
    local okay,reason=pcall(tick)
    if not okay then log("FAIL "..tostring(reason)) run.step,run.next=99,getTimestampMs()+1000000 end
end)
