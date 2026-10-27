-- SPDX-License-Identifier: MIT
-- Real terminal input and framebuffer captures in an existing disposable clone.
local run={step=0,next=0}
local function log(value)
    print("EMMA_KNOWLEDGE|"..value)
    local writer=getFileWriter("SurvivorCompanionHarness/terminal-knowledge.log",true,true)
    if writer then writer:write(value.."\n") writer:close() end
end
local function computer()
    local square=getCell():getGridSquare(12035,6739,0)
    if square then for i=0,square:getObjects():size()-1 do
        local object=square:getObjects():get(i)
        if SurvivorCompanion.Terminal.isComputer(object) then return object end
    end end
end
local function input(text,mode)
    local window=SurvivorCompanion.Terminal.window
    window:flush() window:setFocusMode(mode or "chat")
    window.entry:setText(text) window:submit() window:flush()
    return window
end
local function shot(name) getCore():TakeFullScreenshot("emma-knowledge-"..name) log("SHOT "..name) end
local function choose(field,value)
    local window=SurvivorCompanion.Terminal.window
    for index,option in ipairs(window:menuOptions()) do
        if option[field]==value then input(tostring(index),"menu") return true end
    end
    return false
end
local logoIds={"Twiggys","WestPointDIY","WizardsKeep","TacoDelPancho","MuldraughPolice","RosewoodFire",
    "MeadeCountyPolice","WestPointTownHall","HobbsPerkinsHardware","OvoFarms","LennysCarRepair","EkronCommunityCollege",
    "AlsAutoShop","StuartAndLog","DarkwallowGuestHouse","A1Hay","GunsUnlimited","GoldenSunset"}
local function showLogo(index)
    local SC=SurvivorCompanion local id=logoIds[index]
    -- Header presentation fixture on the clone's actual powered computer.
    -- Production assignment and saved identities are checked headlessly.
    local kind=SC.TerminalBrands.kind(id)
    if index>6 then assert(not SC.TerminalBrands.BACKINGS[id],"transparent header acquired a foreground-removal key") end
    local profile=SC.TerminalFiles.choose(kind,1,id)
    assert(profile.kind==kind,"logo preview has the wrong archive context")
    assert(profile.brand==id,"named archive replaced in logo preview")
    SC.Terminal.window:close()
    local system=SC.Terminal.computerState(getSpecificPlayer(0),run.pc)
    system.archive,system.theme=profile.id,SC.TerminalPresentation.themeFor(1,id)
    assert(SC.Terminal.open(getSpecificPlayer(0),run.pc),"preview computer failed to reopen")
    local w=SC.Terminal.window w:flush()
    assert(w.colors==SC.TerminalPresentation.colors(system.theme),"preview glass/text retained the previous computer's palette")
    w.brand,w.logoTexture=id,SC.TerminalBrands.texture(id,w.system.theme)
    assert(w.logoTexture,"new logo did not load")
    w.rows,w.renderRows,w.readingAnchor,w.scroll={},nil,nil,0
    w.menuPage,w.menuSelection="files",1
    w:setFocusMode("chat") w:displayLocalFile(profile.entries[1],false)
    assert(#w:menuLayout()==#w:menuOptions(),"new owner menu choices are clipped")
end
local function tick()
    local SC=SurvivorCompanion local player=getSpecificPlayer(0) local now=getTimestampMs()
    if now<run.next or not player or not player:getSquare() or not SC or not SC.TerminalKnowledge then return end
    if run.step==0 then
        player:teleportTo(12034.5,6739.5,0)
        run.step,run.next,run.deadline=1,now+6000,now+45000
    elseif run.step==1 then
        run.pc=computer()
        if not run.pc then assert(now<run.deadline,"original clone desktop unavailable") run.next=now+500 return end
        assert(SC.Terminal.use(player,run.pc),"native Use computer refused")
        run.step,run.next,run.deadline=2,now+1000,now+30000
    elseif run.step==2 then
        local w=SC.Terminal.window
        if not w then assert(now<run.deadline,"native Use computer did not finish") run.next=now+500 return end
        w:flush()
        if w.system.locked then
            SC.TerminalSystem.ensurePuzzle(w.system,player:getPerkLevel(Perks.Electricity))
            w.entry:setText(w.system.puzzle.answer) w:submit() w:flush()
        end
        assert(#SC.TerminalLore.REFERENCE==120,"new reference module did not load")
        input("Emma I am scared")
        assert(w.session.context.intent=="chat_scared","expanded natural-language reply not selected")
        local choices,boxes=w:menuOptions(),w:menuLayout()
        assert(#choices==5 and #boxes==5 and boxes[5].index==5,"home shortcut 5 requires scrolling")
        for index,box in ipairs(boxes) do
            assert(box.y>=w:viewTop() and box.y+box.height<=w:viewBottom()
                and (index==1 or box.y>=boxes[index-1].y+boxes[index-1].height),"home menu overlaps or clips")
        end
        log("PASS native all five home shortcuts visible font="..w.rowHeight.." viewport="..w.width.."x"..w.height)
        run.step,run.next=3,now+1500
    elseif run.step==3 then
        shot("conversation")
        input("county files")
        local w=SC.Terminal.window
        local clock=w:referenceClock()
        for _,record in ipairs(w.referenceCatalog) do assert(SC.TerminalLore.available(record,clock),"future record in native menu") end
        assert(#w:menuLayout()==#w:menuOptions(),"category choices are hidden behind input")
        log("PASS native dated catalog available="..#w.referenceCatalog.." categories="..#w.referenceCategories)
        run.step,run.next=4,now+1500
    elseif run.step==4 then
        shot("categories")
        local selected=false
        for _=1,8 do
            if choose("referenceCategory","places") then selected=true break end
            assert(choose("referencePage",SC.Terminal.window.referencePage+1),"places category missing")
        end
        assert(selected and #SC.Terminal.window:menuLayout()==#SC.Terminal.window:menuOptions(),"native place menu does not fit")
        assert(choose("referenceId","place_muldraugh"),"Muldraugh file missing")
        run.step,run.next=5,now+1500
    elseif run.step==5 then
        shot("town")
        local w=SC.Terminal.window
        assert(w:displayLocalFile({date="2099-12-31",title="future fixture",text="must remain hidden"},true)==false,
            "direct reference selection bypassed its date")
        input("back") input("tell me about the Knox Event")
        local previous=w.session.context.referenceId
        input("tell me more")
        assert(w.session.context.intent=="lore" and w.session.context.referenceId~=previous,"native follow-up repeated its first file")
        input("how many Spiffo burgers do we have")
        assert(w.session.context.intent=="storage","native inventory question became static lore")
        assert(getSpecificPlayer(1)==nil,"knowledge browser claimed another player slot")
        log("PASS native conversation, archive keyboard navigation, date refusal, related follow-up and live inventory intent")
        run.originalArchive,run.originalTheme=w.system.archive,w.system.theme
        input("county files")
        local selected=false
        for _=1,8 do
            if choose("referenceCategory","fragments") then selected=true break end
            assert(choose("referencePage",SC.Terminal.window.referencePage+1),"outbreak category missing")
        end
        assert(selected and choose("referenceId","fragment_phone"),"dated outbreak note unreachable by number")
        run.step,run.next=7,now+1500
    elseif run.step==7 then
        shot("outbreak")
        local w=SC.Terminal.window
        assert(w.system.archive==run.originalArchive,"reading a dark note replaced the saved owner")
        input("back") input("tell me about the empty bus")
        assert(w.session.context.referenceId=="fragment_bus","typed dark-note alias lost its archived source")
        log("PASS native dated outbreak category, numbered note access, reading anchor and typed alias")
        for _,row in ipairs({{"Meade County Police","local_meadepolice"},{"West Point Town Hall","local_wptownhall"},
            {"Hobbs and Perkins","local_hobbs"},{"Ovo Farms","local_ovo"},{"Lenny's Car Repair","local_lennys"},
            {"Ekron Community College","local_ekroncollege"},{"Al's Auto Shop","local_als"},{"Stuart and Log","local_stuart"},
            {"Darkwallow Lake Guest House","local_darkwallow"},{"A-1 Hay","local_a1hay"},
            {"Guns Unlimited","local_gunsunlimited"},{"Golden Sunset Nursing Home","local_goldensunset"},
            {"the second guest register","fragment_register"},{"the erased delivery address","fragment_delivery"},
            {"the blue van's return weight","fragment_weighbridge"},{"meals after discharge","fragment_meals"}}) do
            input("tell me about "..row[1])
            assert(w.session.context.intent=="lore" and w.session.context.referenceId==row[2],"native business or fragment alias: "..row[1])
        end
        assert(w.system.archive==run.originalArchive and getSpecificPlayer(1)==nil,"new files changed owner or player slots")
        log("PASS native twelve business references and four new outbreak fragments; original owner retained")
        run.step,run.next=8,now+1500
    elseif run.step==8 then
        shot("rural-files")
        run.logoIndex=1 showLogo(run.logoIndex)
        run.step,run.next=6,now+1500
    elseif run.step==6 then
        local w=SC.Terminal.window local id=logoIds[run.logoIndex]
        shot("logo-"..id)
        assert(not SC.Terminal.nativeLogoUnavailable and w.lastNativeLogoDraw,"new logo did not use native transparency/phosphor drawing")
        log("PASS native logo "..id.." theme="..w.system.theme.." owner="..w.system.archive)
        run.logoIndex=run.logoIndex+1
        if run.logoIndex<=#logoIds then showLogo(run.logoIndex) run.next=now+1500
        else
            w.system.archive,w.system.theme=run.originalArchive,run.originalTheme
            w:close()
            log("PASS native terminal knowledge acceptance complete")
            run.step,run.next=99,now+1000000
        end
    end
end
Events.OnTick.Add(function()
    local okay,reason=pcall(tick)
    if not okay then log("FAIL "..tostring(reason)) run.step,run.next=99,getTimestampMs()+1000000 end
end)
