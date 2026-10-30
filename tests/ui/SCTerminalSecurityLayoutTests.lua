-- SPDX-License-Identifier: MIT
-- Password ink and mouse targets must use the same native pixel advances.
local SC,T=SurvivorCompanion,TERMINAL_TEST
local oldCore,oldManager=getCore,getTextManager
local before=T.checks
local function width(text)
    local pixels=0
    for character in tostring(text):gmatch(".") do
        pixels=pixels+(character:match("%p") and 5 or character==" " and 4 or character=="W" and 13 or 8)
    end
    return pixels
end
local measurements=0
getTextManager=function() return {
    getFontHeight=function() return 16 end,
    MeasureStringX=function(_,_,text) measurements=measurements+1 return width(text) end,
} end
for _,size in ipairs({{480,540},{640,480},{1280,720},{2560,1440}}) do
    getCore=function() return {getScreenWidth=function() return size[1] end,getScreenHeight=function() return size[2] end} end
    local player=T.player(101,100,0)
    local pc=T.computer(T.square(100,100,0,true))
    local state=SC.Terminal.computerState(player,pc) state.locked=true
    T.check(SC.Terminal.open(player,pc),"password pixel-layout fixture opens")
    local window=SC.Terminal.window window:flush()
    local draws={}
    window.drawText=function(_,text,x,y) draws[#draws+1]={text=text,x=x,y=y} end
    window:drawSecurity()
    local rows=window:securityRows()
    local y=window:viewTop()+#window:securityHeaderRows()*window.rowHeight
    local painted,expectedX={},window.layout.left
    for _,draw in ipairs(draws) do
        if draw.y==y then
            T.check(math.abs(draw.x-expectedX)<0.001,"password runs touch without overlapping or gaps")
            painted[#painted+1]=draw.text expectedX=expectedX+width(draw.text)*window.textZoom
        end
    end
    T.check(table.concat(painted)==rows[1].text,"each password character is painted once, including highlighted words")
    T.check(expectedX<=window.layout.left+window:transcriptWidth()+0.001,"the complete password row fits its pixel budget")
    for _,span in ipairs(rows[1].spans) do
        local found
        for _,hit in ipairs(window.securityHits) do
            if hit.value==span.value then
                found=hit
                T.check(math.abs(hit.x-window.layout.left-width(rows[1].text:sub(1,span.start-1))*window.textZoom)<0.001
                    and math.abs(hit.width-width(span.value)*window.textZoom)<0.001,
                    "click bounds follow the exact painted word at every display scale")
            end
        end
        T.check(found~=nil,"each visible password candidate remains selectable")
    end
    local measured=measurements
    window:drawSecurity()
    T.check(measurements==measured,"unchanged password painting reuses measured runs")
    local target
    for _,hit in ipairs(window.securityHits) do
        if hit.value:match("^[A-Z]+$") and hit.value~=window.system.puzzle.answer then target=hit break end
    end
    T.check(target~=nil,"fixture has a visible wrong word")
    local tries=window.system.puzzle.tries
    local mouseX,mouseY=target.x+target.width/2,target.y+window.rowHeight/2
    local over,bold=true,{}
    function window:getMouseX() return mouseX end
    function window:getMouseY() return mouseY end
    function window:isMouseOver() return over end
    window.drawTextZoomed=function(_,text,x,y)
        bold[#bold+1]={text=text,x=x,y=y,clip=T.stencil}
    end
    window:drawSecurity()
    T.check(#bold==1 and bold[1].text==target.value and bold[1].x==target.x+1
        and bold[1].clip.x==target.x and bold[1].clip.width==target.width and T.stencil==nil,
        "hover adds a bold code-font stroke only within the whole candidate's existing bounds")
    T.check(window.system.puzzle.tries==tries,"hover does not guess or spend an attempt")
    bold={} mouseX=window.layout.left+1
    window:drawSecurity()
    T.check(#bold==0,"decorative junk and memory addresses do not become bold")
    bold={} mouseX=target.x+target.width/2 over=false
    window:drawSecurity()
    T.check(#bold==0,"leaving the terminal removes hover emphasis")
    window:onMouseDown(target.x+target.width/2,target.y+window.rowHeight/2)
    T.check(window.system.puzzle.tries==tries-1,"clicking the painted word spends exactly one attempt")
    window.securityScroll=10000 window:drawSecurity()
    local bracket
    for _,hit in ipairs(window.securityHits) do if not hit.value:match("^[A-Z]+$") then bracket=hit break end end
    T.check(bracket~=nil,"the final page exposes real matching bracket groups")
    over=true mouseX,mouseY=bracket.x+bracket.width/2,bracket.y+window.rowHeight/2 bold={}
    window:drawSecurity()
    T.check(#bold==1 and bold[1].text==bracket.value,"hovering either side of a bracket group emphasizes its complete matching span")
    window:onMouseDown(mouseX,mouseY) bold={}
    window:drawSecurity()
    T.check(#bold==0,"used bracket groups lose their hover emphasis with their click target")
    window.system.puzzle.tries=0 window.system.puzzle.lockoutUntil=T.hours+1 bold={}
    window:drawSecurity()
    T.check(#bold==0 and #window.securityHits==0,"lockout cannot leave a bold actionable password target")
    window:close()
end
getCore,getTextManager=oldCore,oldManager
SC_TEST_REPORT=SC_TEST_REPORT.."; Password pixel layout: "..(T.checks-before).." checks passed"
