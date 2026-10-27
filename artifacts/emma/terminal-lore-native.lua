-- Disposable native catalogue and owner/reference-file acceptance.
local run={step=0,next=0,page=1,mode="paper",shots=0}
local function log(value)
    print("EMMA_LORE|"..value)
    local w=getFileWriter("SurvivorCompanionHarness/terminal-lore.log",true,true)
    if w then w:write(value.."\n") w:close() end
end
local Gallery=ISPanel:derive("SCTerminalLoreGallery")
function Gallery:prerender()
    self:drawRect(0,0,self.width,self.height,1,0,0,0)
    local SC=SurvivorCompanion
    local list=run.mode=="paper" and run.dark or run.ids
    local cellW,cellH=self.width/4,self.height/4
    for slot=1,16 do
        local id=list[(run.page-1)*16+slot]
        if id then
            local x,y=((slot-1)%4)*cellW,math.floor((slot-1)/4)*cellH
            local theme=run.mode=="purple" and "purple" or SC.TerminalPresentation.themeFor(1,id)
            local colors=SC.TerminalPresentation.colors(theme)
            local bg=colors.background
            if run.mode=="paper" then self:drawRect(x+2,y+2,cellW-4,cellH-4,1,1,1,1)
            else self:drawRect(x+2,y+2,cellW-4,cellH-4,1,bg[2],bg[3],bg[4]) end
            self.system={theme=theme}
            self.brand=id
            self.logoTexture=SC.TerminalBrands.texture(id,theme)
            self.layout={brandHeight=cellH-45,unit=1,logo={x=x+10,y=y+25,width=cellW-20,height=cellH-55}}
            if self.logoTexture then
                SC.Terminal.Window.drawHeaderLogo(self)
                if self.lastNativeLogoDraw then self.nativeDraws=(self.nativeDraws or 0)+1 end
            end
            local c=run.mode=="paper" and {1,.1,.1,.1} or colors.title
            ISPanel.drawText(self,id.." / "..theme,x+10,y+5,c[2],c[3],c[4],1,UIFont.Small)
        end
    end
end
local function shot(name)
    getCore():TakeFullScreenshot(name)
    log("SHOT "..name)
    run.shots=run.shots+1
end
local function send(text)
    local w=SurvivorCompanion.Terminal.window
    w:setFocusMode("chat") w.entry.javaObject:SetText(text) w:submit() w:flush()
end
local presentations={{"DiMarcoCoffee","sand"},{"Fossoil","aqua"},
    {"KnoxBank","green"},{"RiverwoodBoatClub","purple"}}
local function companyScreen(index)
    local SC=SurvivorCompanion
    if SC.Terminal.window then SC.Terminal.window:close() end
    local state=SC.Terminal.computerState(getSpecificPlayer(0),run.object)
    state.theme=presentations[index][2]
    state.paletteVersion=SC.TerminalPresentation.PALETTE_VERSION
    assert(SC.Terminal.open(getSpecificPlayer(0),run.object))
    local w=SC.Terminal.window w:flush()
    -- Presentation fixture only. Assignment and camp access are tested above;
    -- show each actual native header against its paired glass here.
    w.brand=presentations[index][1]
    w.logoTexture=SC.TerminalBrands.texture(w.brand,state.theme)
    send("tell me about emma")
end
local function tick()
    local now=getTimestampMs()
    if now<run.next then return end
    local SC=SurvivorCompanion
    local player=getSpecificPlayer(0)
    if not SC or not SC.TerminalLore or not player or not player:getCurrentSquare() then return end
    if run.step==0 then
        player:setGodMod(true) player:setGhostMode(true)
        run.ids,run.dark={}, {"Chuggs","knoxknews","LiveMusic","MaisonDuBouef","NewspaperNationalLogo",
            "NewspaperNewEraLogo","PoshBox","ScarletOakDistillery","TheBlackSaddle","TheExquisitePearl",
            "TheKentuckyHerald","TheSlugger","TheVelvetTassel","TopcrownPlaza","WestMapleCountryClub","YuriDesign"}
        for id in pairs(SC.TerminalBrands.BY_ID) do
            if SC.TerminalBrands.canonical(id)==id then run.ids[#run.ids+1]=id end
        end
        table.sort(run.ids)
        run.gallery=Gallery:new(0,0,getCore():getScreenWidth(),getCore():getScreenHeight())
        run.gallery:initialise() run.gallery:addToUIManager()
        run.gallery:setAlwaysOnTop(true)
        run.step,run.next=1,now+1500
        log("START native catalogue unique-identities="..#run.ids)
    elseif run.step==1 then
        shot("emma-lore-gallery-"..run.mode.."-"..string.format("%02d",run.page))
        local list=run.mode=="paper" and run.dark or run.ids
        if run.page*16<#list then run.page=run.page+1
        elseif run.mode=="paper" then run.mode,run.page="paired",1
        elseif run.mode=="paired" then run.mode,run.page="purple",1
        else run.step=2 end
        run.next=now+550
    elseif run.step==2 then
        assert((run.gallery.nativeDraws or 0)>32,"native shader did not draw the catalogue")
        assert(not SC.Terminal.nativeLogoUnavailable,"native shader fell back after a draw error")
        log("PASS native shader catalogue draws="..run.gallery.nativeDraws)
        run.gallery:removeFromUIManager()
        local square=player:getCurrentSquare()
        run.object=IsoObject.new(getCell(),square,"appliances_com_01_72")
        square:AddTileObject(run.object)
        run.object:getModData().LF_ComputerBrand="FamilyDentistry"
        local powered=SC.Terminal.powered
        SC.Terminal.powered=function(object) return object==run.object or powered(object) end
        local state=SC.Terminal.computerState(player,run.object)
        state.locked=false
        assert(state.archive=="dentist_marion","brand-specific owner archive was not assigned")
        assert(SC.Terminal.open(player,run.object))
        local w=SC.Terminal.window w:flush()
        w:setFocusMode("menu") w.entry.javaObject:SetText("2") w.entry.javaObject:onTextChange()
        assert(w.menuPage=="files","native owner-file shortcut failed")
        w.entry.javaObject:SetText("3") w.entry.javaObject:onTextChange()
        w:flush()
        run.archive=state.archive
        run.step,run.next=3,now+1200
    elseif run.step==3 then
        shot("emma-lore-owner-file")
        local w=SC.Terminal.window
        w:otherKey(Keyboard.KEY_ESCAPE)
        w.entry.javaObject:SetText("3") w.entry.javaObject:onTextChange()
        assert(w.menuPage=="lore","native county-file shortcut failed")
        assert(#w:menuOptions()<=9,"reference page exceeds immediate numeric shortcuts")
        w.entry.javaObject:SetText("1") w.entry.javaObject:onTextChange()
        w:flush()
        run.step,run.next=4,now+1200
    elseif run.step==4 then
        shot("emma-lore-reference-file")
        local w=SC.Terminal.window
        for page=1,5 do
            local options=w:menuOptions()
            local moved
            for index,option in ipairs(options) do
                if option.referencePage and option.referencePage==(w.referencePage or 0)+1 then
                    w.entry.javaObject:SetText(tostring(index)) w.entry.javaObject:onTextChange() moved=true break
                end
            end
            assert(moved and #w:menuOptions()<=9,"reference pagination lost its native shortcut")
        end
        w.entry.javaObject:SetText("1") w.entry.javaObject:onTextChange() w:flush()
        assert(w.system.archive==run.archive,"reading reference files changed the owner's save identity")
        run.step,run.next=5,now+1200
    elseif run.step==5 then
        shot("emma-lore-last-page")
        SC.Terminal.window:close()
        assert(SC.Terminal.open(player,run.object))
        assert(SC.Terminal.window.system.archive==run.archive,"reopening rerolled owner files")
        SC.Terminal.window:close()
        log("PASS native owner assignment, files, all reference pages, shortcuts and identity retention")
        run.presentIndex=1 companyScreen(1)
        run.step,run.next=6,now+1200
    elseif run.step==6 then
        local p=presentations[run.presentIndex]
        shot("emma-lore-company-"..p[1].."-"..p[2])
        if run.presentIndex<#presentations then
            run.presentIndex=run.presentIndex+1 companyScreen(run.presentIndex)
            run.next=now+1200
            return
        end
        SC.Terminal.window:close()
        log("PASS native terminal lore acceptance complete shots="..run.shots)
        run.step,run.next=99,now+1000000
    end
end
Events.OnTick.Add(function()
    local okay,reason=pcall(tick)
    if not okay then log("FAIL "..tostring(reason)) run.step,run.next=99,getTimestampMs()+1000000 end
end)
