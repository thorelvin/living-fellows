-- Disposable cloned-world UI acceptance; never installed in the user's game.
local run = { step = 0, next = 0, shots = 0 }
local function now() return getTimestampMs() end
local function log(text)
    print("EMMA_UI_ACCEPTANCE|" .. text)
    local writer = getFileWriter("SurvivorCompanionHarness/terminal-ui-evidence.log", true, true)
    if writer then writer:write(text .. "\n") writer:close() end
end
local function shot(label)
    getCore():TakeFullScreenshot("emma-office1993-" .. label)
    local w = SurvivorCompanion.Terminal.window
    log("SHOT " .. label .. " screen=" .. getCore():getScreenWidth() .. "x" .. getCore():getScreenHeight()
        .. " window=" .. w:getWidth() .. "x" .. w:getHeight() .. " font=" .. tostring(w.font)
        .. " row=" .. w.rowHeight .. " zoom=" .. w.textZoom .. " input=" .. tostring(w.inputFont)
        .. " columns=" .. w:columns() .. " sidebar=" .. w:sidebarWidth()
        .. " glass=" .. math.floor(w.layout.screen.width) .. "x" .. math.floor(w.layout.screen.height))
    run.shots = run.shots + 1
end
local function open(theme, brand)
    local SC = SurvivorCompanion
    if SC.Terminal.window then SC.Terminal.window:close() end
    local state = SC.Terminal.computerState(run.player, run.object)
    state.seed = 1
    state.locked, state.brand = false, brand
    state.theme = theme or SC.TerminalPresentation.themeFor(state.seed,brand)
    state.paletteVersion = SC.TerminalPresentation.PALETTE_VERSION
    assert(SC.Terminal.open(run.player, run.object))
    local window = SC.Terminal.window
    assert(window.skinFrame and window.skinGlass and window.skinFrame:getWidth()==1586
        and window.skinGlass:getHeight()==992, "generated CRT assets did not load")
    -- Explicit fixture branding tests the original artwork, independent of
    -- whether this particular saved desk sits inside the camp dashboard.
    window.brand,window.logoTexture = brand,SC.TerminalBrands.texture(brand)
    return window
end
local function tick()
    if now() < run.next then return end
    local SC = SurvivorCompanion
    if not SC or not SC.Terminal or not getSpecificPlayer(0) then return end
    local player = getSpecificPlayer(0)
    if not player:getCurrentSquare() then return end
    if run.step == 0 then
        run.player = player
        player:setGodMod(true)
        player:setGhostMode(true)
        local square = player:getCurrentSquare()
        run.object = IsoObject.new(getCell(), square, "appliances_com_01_72")
        square:AddTileObject(run.object)
        run.object:getModData().LF_Emma = {visits=1,notes={}}
        local previous = SC.Terminal.powered
        SC.Terminal.powered = function(object) return object == run.object or previous(object) end
        local window = open(nil,"Fossoil")
        assert(window.system.theme == "aqua", "Fossoil did not receive its aquamarine pairing")
        run.step,run.next = 1,now()+800
        log("START disposable native terminal fixture")
    elseif run.step == 1 then
        shot("post-1280")
        run.step,run.next = 2,now()+6500
    elseif run.step == 2 then
        SC.Terminal.window:flush()
        shot("aqua-fossoil-1280")
        local w = open("sand","Fossoil")
        w:flush()
        run.step,run.next = 3,now()+1200
    elseif run.step == 3 then
        shot("sand-fossoil-1280")
        local w = open("sand","FinneganResearchGroup")
        w:flush()
        run.step,run.next = 4,now()+1200
    elseif run.step == 4 then
        shot("sand-finnegan-1280")
        local w = open(nil,"Valutech")
        w:flush()
        run.step,run.next = 5,now()+1200
    elseif run.step == 5 then
        shot("green-valutech-1280")
        local w = open("purple","_lab")
        w:flush()
        getCore():setResolutionAndFullScreen(1920,1080,false)
        run.step,run.next = 6,now()+3500
    elseif run.step == 6 then
        local w = SC.Terminal.window
        w:refreshLayout()
        w:flush()
        shot("purple-1920")
        w:setFocusMode("chat")
        w.entry:setText("how many nails")
        w:submit()
        run.step,run.next = 7,now()+5000
    elseif run.step == 7 then
        SC.Terminal.window:flush()
        SC.Terminal.window.entry:setText("who needs medical attention?")
        run.step,run.next = 7.5,now()+750
    elseif run.step == 7.5 then
        shot("chat-1920")
        local w = SC.Terminal.window
        w:setFocusMode("menu")
        log("START_NATIVE_KEYBOARD_CALLBACKS")
        run.step,run.next = 8,now()+500
    elseif run.step == 8 then
        local w = SC.Terminal.window
        w.entry.javaObject:SetText("2")
        w.entry.javaObject:onTextChange()
        assert(w.menuPage == "files", "native text callback did not activate menu 2")
        log("PASS native instant number selection")
        run.step,run.next=9,now()+1000
    elseif run.step == 9 then
        shot("native-files-1920")
        local w = SC.Terminal.window
        w.entry.javaObject:onOtherKey(Keyboard.KEY_TAB)
        assert(w.focusMode == "chat", "native Tab did not enter chat")
        w.entry.javaObject:SetText("214")
        w.entry.javaObject:onTextChange()
        assert(w.focusMode == "chat", "numeric chat input triggered menu selection")
        w.entry.javaObject:onOtherKey(Keyboard.KEY_TAB)
        w.entry.javaObject:onOtherKey(Keyboard.KEY_TAB)
        assert(w.entry:getText() == "214", "native focus cycle lost the draft")
        local turns=w.session.turns
        w.entry.javaObject:onKeyEnter()
        assert(w.session.turns == turns+1, "native Enter did not send the numeric chat message")
        log("PASS native Tab, numeric chat, draft preservation and Enter")
        run.step,run.next=10,now()+3000
    elseif run.step == 10 then
        local w = SC.Terminal.window
        w:flush()
        w.entry.javaObject:onOtherKey(Keyboard.KEY_ESCAPE)
        assert(not w.closed and w.menuPage == nil, "native Escape did not return from files")
        w.entry.javaObject:onOtherKey(Keyboard.KEY_ESCAPE)
        assert(w.closed and SC.Terminal.window == nil and not w.entry.javaObject:isFocused(),
            "native Escape did not release the keyboard")
        log("PASS native Escape and keyboard release")
        for _,font in ipairs({UIFont.Code,UIFont.CodeSmall,UIFont.CodeMedium,UIFont.CodeLarge,UIFont.Large,UIFont.Massive}) do
            log("FONT " .. tostring(font) .. " height=" .. getTextManager():getFontHeight(font)
                .. " M10=" .. getTextManager():MeasureStringX(font,"MMMMMMMMMM"))
        end
        local loaded,total=0,0
        for id in pairs(SC.TerminalBrands.BY_ID) do
            total=total+1
            if SC.TerminalBrands.texture(id) then loaded=loaded+1 end
        end
        assert(loaded==total,"some registered artwork could not load")
        log("PASS artwork catalog objects=" .. loaded)
        assert(SC.TerminalBrands.CROPS and SC.TerminalBrands.CROPS._camp,
            "camp artwork source bounds were lost during bootstrap")
        getCore():setResolutionAndFullScreen(3840,2160,false)
        local nextWindow=open("purple","_camp")
        nextWindow:flush()
        run.step,run.next=11,now()+5000
    elseif run.step == 11 then
        SC.Terminal.window:refreshLayout()
        shot("camp-purple-4k")
        local originalWidth,originalHeight=getPlayerScreenWidth,getPlayerScreenHeight
        run.originalWidth,run.originalHeight=originalWidth,originalHeight
        getPlayerScreenWidth=function(index) return math.floor(originalWidth(index)/4) end
        getPlayerScreenHeight=function(index) return originalHeight(index) end
        SC.Terminal.window:refreshLayout()
        run.step,run.next=12,now()+1000
    elseif run.step == 12 then
        shot("narrow-native-fonts")
        getPlayerScreenWidth,getPlayerScreenHeight=run.originalWidth,run.originalHeight
        getCore():setResolutionAndFullScreen(1920,1080,false)
        local w = open("green","_camp")
        w:flush()
        w:setFocusMode("chat")
        w:askEmma("who is hurt")
        run.step,run.next=13,now()+6500
    elseif run.step == 13 then
        SC.Terminal.window:flush()
        shot("green-camp-1920")
        SC.Terminal.window:close()
        log("PASS native acceptance complete screenshots=" .. run.shots)
        run.step,run.next=99,now()+1000000
    end
end
Events.OnTick.Add(function()
    local okay,reason = pcall(tick)
    if not okay then log("FAIL " .. tostring(reason)) run.step,run.next=99,now()+1000000 end
end)
