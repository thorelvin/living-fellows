-- SPDX-License-Identifier: MIT
local SC, T = SurvivorCompanion, TERMINAL_TEST
local P, Terminal, System, Brands = SC.TerminalPresentation, SC.Terminal, SC.TerminalSystem, SC.TerminalBrands
local check, before = T.check, T.checks
local sizes = { {640,480}, {800,600}, {1280,720}, {1366,768}, {1920,1080},
    {2560,1440}, {3440,1440}, {3840,2160}, {480,540}, {960,1080} }
for _, size in ipairs(sizes) do
    for _, fh in ipairs({16,23,26,38}) do
        local view = { x = 37, y = 19, width = size[1], height = size[2] }
        local display = P.textHeight(view.height, fh)
        local layout = P.layout(view, display, display / 2)
        check(layout.x >= view.x and layout.y >= view.y
            and layout.x + layout.width <= view.x + view.width
            and layout.y + layout.height <= view.y + view.height, "terminal stays within its viewport")
        check(layout.top < layout.bottom and layout.bottom <= layout.hintY
            and layout.hintY + display <= layout.entryY and layout.entryY + layout.entryHeight < layout.height,
            "header, transcript, hints and input do not overlap")
        check(layout.columns * display / 2 <= layout.contentWidth, "font metrics determine usable columns")
        local campBox = P.headerLogoBox(layout,"_camp",display/2)
        check(campBox.x>=layout.left and campBox.x+campBox.width<=layout.right
            and (campBox.width==0 or campBox.x>=layout.left+layout.pad+display/2*25-0.001)
            and P.headerLogoBox(layout,"Fossoil",display/2)==layout.logo,
            "the larger camp logo reserves caption space without changing business headers")
        check(math.abs((layout.left + layout.right) / 2
            - (layout.screen.x + layout.screen.width / 2)) <= 1,
            "the content canvas stays centred inside the CRT opening")
        local bounded = #layout.skin.patches == 8
        for _, part in ipairs(layout.skin.patches) do
            bounded = bounded and part.x >= -0.001 and part.y >= -0.001
                and part.x + part.width <= view.width + 0.001
                and part.y + part.height <= view.height + 0.001
        end
        check(bounded and layout.left >= layout.screen.x and layout.right <= layout.screen.x + layout.screen.width
            and layout.titleY >= layout.screen.y
            and layout.entryY + layout.entryHeight <= layout.screen.y + layout.screen.height,
            "eight frame patches stay within the owning view and all controls fit the screen opening")
    end
end
local normal = P.layout({width=1920,height=1080},16,8)
check(normal.width == 1920 and normal.height == 1080 and normal.x == 0 and normal.y == 0,
    "the terminal fills the entire player viewport")
check(P.textHeight(1080,24) == 40 and P.textHeight(2160,24) == 80 and P.textHeight(720,24) == 28,
    "terminal text steps down to 28px at 720p, 40px at 1080p and 80px at 4K")
local fit = P.fitImage(710,100,{x=10,y=20,width=210,height=52})
check(fit.width <= 210 and fit.height <= 52 and math.abs(fit.width / fit.height - 7.1) < 0.001,
    "wide wordmarks retain their original proportions")
local rare, lockedRare = 0, 0
for seed = 1, 100000 do
    local branded = P.themeFor(seed, "Fossoil")
    if branded ~= "aqua" and branded ~= "purple" then error("Fossoil received an incompatible text colour") end
    if (branded == "purple") ~= (P.themeFor(seed) == "purple") then
        error("brand pairing changed rare-purple assignment")
    end
    if P.themeFor(seed) == "purple" then
        rare = rare + 1
        if seed % 100 < 40 then lockedRare = lockedRare + 1 end
    end
end
check(rare >= 900 and rare <= 1100, "purple appears about once in a hundred")
check(lockedRare / rare > 0.32 and lockedRare / rare < 0.48, "purple does not imply a password lock")
check(Brands.PALETTES.Fossoil == "aqua" and Brands.CROPS.Fossoil ~= nil
    and Brands.BY_ID.Fossoil.texture == "media/textures/Terminal/Fossoil.png",
    "Fossoil uses its transparent terminal artwork and aquamarine colour pairing")
local state = System.create(1923,"general",true,false)
state.theme, state.brand = "purple", "Fossoil"
check(System.normalize(state).theme == "purple" and System.normalize(state).brand == "Fossoil",
    "colour and owner branding persist independently")
state.theme = nil
check(System.normalize(state).theme == P.themeFor(state.seed), "older system records gain a stable theme without a reroll")
check(#Brands.STOCK == 184 and Brands.BY_ID.FinneganResearchGroup ~= nil, "original business artwork is catalogued")
local first, done = P.bootFrame(0,42)
local later = P.bootFrame(1800,42)
local last, finished = P.bootFrame(P.BOOT_MS,42)
check(not done and finished and #later > #first and #last > #later, "POST advances deterministically through native-era diagnostics")
local hidden, revealing, settled = P.biosFrame(0), P.biosFrame(350), P.biosFrame(P.BIOS_MS)
check(hidden.reveal==0 and revealing.reveal>0 and revealing.reveal<1
    and settled.reveal==1 and not settled.active and P.BOOT_MS==P.BIOS_MS+3200,
    "animated BIOS image reveals before the complete POST sequence")
check(P.biosFrame(0/0).reveal==0 and P.biosFrame(math.huge).reveal==0,
    "invalid BIOS animation clocks keep bounded drawing geometry")

local oldCore, oldManager, oldWorld, oldTexture, oldFonts = getCore, getTextManager, SC.TerminalWorld.new, getTexture, UIFont
local oldLeft, oldTop, oldWidth, oldHeight = getPlayerScreenLeft,getPlayerScreenTop,getPlayerScreenWidth,getPlayerScreenHeight
local width,height,left,top = 1920,1080,0,0
local nativeFont, reads, artCalls = "CodeSmall",0,0
UIFont = {Code="Code",CodeSmall="CodeSmall",CodeMedium="CodeMedium",CodeLarge="CodeLarge",
    Small="Small",Medium="Medium",Large="Large",Massive="Massive"}
local heights = {Code=16,CodeSmall=16,CodeMedium=23,CodeLarge=26,Small=16,Medium=22,Large=26,Massive=45}
getCore = function() return {getScreenWidth=function() return width end,getScreenHeight=function() return height end} end
getTextManager = function() return {getCurrentCodeFont=function() return nativeFont end,
    getFontHeight=function(_,font) return heights[font] end,
    MeasureStringX=function(_,font,value) return #value * heights[font] / 2 end} end
SC.TerminalWorld.new = function()
    return {camp=function() return {inside=true,configured=true} end,
        clock=function() return {worldHours=T.hours,hour=10,minute=0,day=1,month=6,year=1993,days=2} end,
        people=function() reads=reads+1 return {} end,
        power=function() return {source="generator",fuel=80,condition=100} end,
        storage=function() reads=reads+1 return {groups={},items=0,containers=0} end}
end
getTexture = function(path)
    artCalls=artCalls+1
    if path:find("/Skin/",1,true) then
        return {getWidth=function() return 1586 end,getHeight=function() return 992 end}
    end
    if path:find("/Camp/emma-camp-v2.png",1,true) then
        return {getWidth=function() return 2172 end,getHeight=function() return 724 end}
    end
    return {getWidth=function() return 710 end,getHeight=function() return 100 end}
end
local actor = T.player(101,100,0)
local oldComputer = T.computer(T.square(100,100,0,true))
local oldState = System.create(1,"general",false,false)
oldState.brand, oldState.theme = "Fossoil", "green"
System.ensurePuzzle(oldState,0)
local oldAnswer = oldState.puzzle.answer
oldComputer.data.movableData = {LF_LarchOS=oldState}
local paired = Terminal.computerState(actor,oldComputer)
check(paired.theme == "aqua" and paired.paletteVersion == P.PALETTE_VERSION
    and paired.locked == oldState.locked and paired.puzzle.answer == oldAnswer,
    "an old brand gains its compatible colour without changing security or its puzzle")
local movedComputer = T.computer(T.square(102,100,0,true))
movedComputer.data.movableData = {LF_LarchOS=System.normalize(paired)}
local returned = Terminal.computerState(actor,movedComputer)
check(returned.theme == paired.theme and returned.paletteVersion == paired.paletteVersion,
    "a paired colour survives normalization and movement without rerolling")
local computer = T.computer(T.square(100,100,0,true))
computer.data.LF_ComputerBrand = "Fossoil"
check(Terminal.open(actor,computer), "responsive native window opens")
local window = Terminal.window
check(window:getWidth()==1920 and window:getHeight()==1080 and window.textZoom > 1,
    "the UI draws large terminal text at fullscreen scale without changing game font settings")
check(window.inputFont == "Massive" and window.layout.entryHeight > heights.Massive,
    "the editable native input also uses a large readable font with room for its caret")
check(window.state == "booting" and window.session == nil and reads == 0,
    "POST reads no camp records and counts no premature session")
local biosTexture = window.biosTexture
for _,theme in ipairs({"green","sand","aqua","purple"}) do
    window.colors=P.colors(theme)
    window:drawBios(350)
    local draw=T.lastTextureDraw
    check(draw.texture==biosTexture and draw.clip and draw.clip.height>0 and draw.clip.height<draw.height
        and draw.r==window.colors.title[2] and draw.g==window.colors.title[3]
        and draw.b==window.colors.title[4] and T.stencil==nil and reads==0,
        "BIOS reveal uses the matching "..theme.." phosphor without camp queries or leaked clipping")
end
window.colors=P.colors(window.system.theme)
local biosDraw=window.drawTextureScaled
window.drawTextureScaled=function() error("fixture lost BIOS image") end
window:drawBios(1000)
check(T.stencil==nil and window.biosTexture==nil and window.state=="booting",
    "lost BIOS art releases its stencil and leaves the normal text fallback usable")
window.drawTextureScaled,window.biosTexture=biosDraw,biosTexture
window:flush()
check(window.focusMode == "menu" and window.system.brand == "Fossoil" and window.brand == "_camp",
    "camp branding does not rewrite original ownership")
window:drawHeaderLogo()
local drawn, crop = T.lastTextureDraw, Brands.crop("_camp",window.system.theme)
local scale = drawn.width / window.logoTexture:getWidth()
check(drawn.clip ~= nil and math.abs(drawn.x + crop[1] * scale - drawn.clip.x) < 0.001
    and math.abs(drawn.y + crop[2] * scale - drawn.clip.y) < 0.001
    and math.abs(drawn.clip.height - crop[4] * scale) < 0.001
    and math.abs(drawn.clip.x-math.max(2,window.layout.unit)-(window.layout.right-window.layout.side))<0.001,
    "native clipping selects the camp emblem and aligns its left corner marks with the menu divider")
check(T.stencil == nil and drawn.a < 1 and drawn.a > 0.6
    and drawn.r==window.colors.title[2] and drawn.g==window.colors.title[3] and drawn.b==window.colors.title[4],
    "the neutral camp mark uses matching phosphor at restrained brightness and releases its stencil")
local savedTheme=window.system.theme
for _,theme in ipairs({"green","sand","aqua","purple"}) do
    window.system.theme=theme
    window.logoTexture=Brands.texture("_camp",theme)
    window:drawHeaderLogo()
    local draw,box=T.lastTextureDraw,Brands.crop("_camp",theme)
    local factor=draw.width/window.logoTexture:getWidth()
    check(math.abs(draw.y+box[2]*factor-draw.clip.y)<.001
        and box[2]+box[4]<=window.logoTexture:getHeight(),"correct source row and texture for camp "..theme)
end
check(Brands.crop("_camp","aqua")==Brands.crop("_camp","purple")
    and Brands.texture("_camp","green")==Brands.texture("_camp","sand")
    and Brands.isMonochrome("_camp") and Brands.BACKINGS._camp[1]<0.01,
    "all four camp themes share one neutral crop and keyed backing without atlas row or tint mismatches")
check(Brands.crop("Fossoil","purple")==Brands.CROPS.Fossoil,
    "camp palette correction preserves business logo colours")
window.system.theme=savedTheme
window.logoTexture=Brands.texture(window.brand,savedTheme)
local previousDraw = window.drawTextureScaled
window.drawTextureScaled = function() error("test texture loss") end
window:drawHeaderLogo()
check(T.stencil == nil and window.logoTexture == nil,
    "a failed logo draw releases clipping so the rest of the terminal can render")
window.drawTextureScaled, window.logoTexture = previousDraw, Brands.texture(window.brand,window.system.theme)
window:setFocusMode("chat")
window.entry:setText("remember nails 214")
window:otherKey(Keyboard.KEY_TAB)
check(window.focusMode == "menu" and window.entry:getText() == "", "Tab moves from a draft to the menu")
window:otherKey(Keyboard.KEY_TAB)
check(window.entry:getText() == "remember nails 214", "Tab restores the unfinished chat draft")
window.entry:setText("2")
window.entry:onTextChange()
check(window.focusMode == "chat" and window.menuPage == nil, "numbers typed in chat never trigger menu commands")
window:setFocusMode("menu")
window.entry:setText("2")
window.entry:onTextChange()
check(window.menuPage == "files", "a number selects a menu item immediately without Enter")
window:navigate(1)
check(window.menuSelection == 2, "menu arrows navigate independently of chat history")
window:otherKey(Keyboard.KEY_ESCAPE)
window:setFocusMode("chat")
window.entry:setText("unfinished question")
window:print(string.rep("long transcript ",10))
local visits, oldSession, beforeReads = window.session.visits, window.session, reads
width,height,left,top = 960,1080,960,0
getPlayerScreenLeft=function() return left end
getPlayerScreenTop=function() return top end
getPlayerScreenWidth=function() return width end
getPlayerScreenHeight=function() return height end
T.now=T.now+600
window:update()
check(window.x >= left and window.x + window:getWidth() <= left + width,
    "a live split-view transition reflows inside the owning player viewport")
check(window.entry:getText() == "unfinished question" and window.session == oldSession
    and window.session.visits == visits and reads == beforeReads,
    "reflow preserves drafts, sessions and visits without querying camp records")
width,height,left,top = 480,540,0,0
T.now=T.now+600
window:update()
check(window:sidebarWidth() == 0 and window:visibleRows() > 4, "a narrow viewport uses a readable single pane")
for _, row in ipairs(window:transcriptRows()) do
    check(#row.text <= window:columns(), "an existing transcript rewraps after resolution changes")
end
window:setFocusMode("menu")
window:prerender()
for _, box in ipairs(window:menuLayout()) do
    check(box.y >= window:viewTop() and box.y + box.height <= window:viewBottom(), "compact menu choices fit the content pane")
end
local oldServices = SC.TerminalServices
SC.TerminalServices = {menu=function() end}
window.menuPage, window.menuSelection = nil, 1
for _, size in ipairs({{1280,720},{1920,1080},{2560,1440},{3840,2160},{640,720},{960,540}}) do
    width,height = size[1],size[2]
    window:refreshLayout()
    for _, focus in ipairs({"menu","chat"}) do
        window:setFocusMode(focus)
        local choices, boxes = window:menuOptions(), window:menuLayout()
        check(#choices==5 and #boxes==5 and boxes[5].index==5,
            "all five home shortcuts stay visible without scrolling at "..width.."x"..height.." in "..focus)
        for index, box in ipairs(boxes) do
            check(box.y>=window:viewTop() and box.y+box.height<=window:viewBottom()
                and (index==1 or box.y>=boxes[index-1].y+boxes[index-1].height),
                "home shortcuts fit above input without overlap")
        end
    end
end
SC.TerminalServices = oldServices
width,height = 3840,2160
T.now=T.now+600
window:update()
check(window.font == "CodeLarge" and window.rowHeight >= 26, "4K chooses the larger native code font")
check(window.rowHeight >= 80 and window:getWidth()==3840 and window:getHeight()==2160,
    "4K fills the viewport with proportionally larger text and controls")
local beforeArt = artCalls
local skin, draft, beforePaintReads = window.layout.skin, window.entry:getText(), reads
local oldTextureDraw, oldTextDraw, frameDraws, glassReady, textReady = window.drawTextureScaled, window.drawText, 0, false, true
window.drawTextureScaled = function(self, texture, ...)
    if texture == self.skinFrame then frameDraws=frameDraws+1 end
    if texture == self.skinGlass then glassReady=true end
    return oldTextureDraw(self,texture,...)
end
window.drawText = function(self,...)
    textReady = textReady and glassReady
    return oldTextDraw(self,...)
end
window:prerender()
window:render()
check(frameDraws == 8 and glassReady and textReady and T.stencil == nil and window.layout.skin == skin
    and window.entry:getText() == draft and reads == beforePaintReads,
    "glass precedes live text, the frame omits its centre and clipping, drafts and world reads stay intact")
window.drawTextureScaled, window.drawText = oldTextureDraw, oldTextDraw
for _=1,50 do window:prerender() window:render() end
check(artCalls == beforeArt, "rendering does not reload logo textures")
T.now = 1793038852500
window:askEmma("how many nails")
for _=1,30 do T.now=T.now+37 window:update() window:prerender() end
check(not window.closed, "thinking animation remains valid with real epoch-millisecond timestamps")
window:close()
getCore,getTextManager,SC.TerminalWorld.new,getTexture,UIFont = oldCore,oldManager,oldWorld,oldTexture,oldFonts
getPlayerScreenLeft,getPlayerScreenTop,getPlayerScreenWidth,getPlayerScreenHeight = oldLeft,oldTop,oldWidth,oldHeight
SC_TEST_REPORT=SC_TEST_REPORT .. "; Responsive/POST/themes: " .. (T.checks-before) .. " checks passed"
