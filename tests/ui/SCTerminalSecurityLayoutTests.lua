-- SPDX-License-Identifier: MIT
-- Deliberately proportional font metrics must still paint a fixed ASCII grid.
local SC,T=SurvivorCompanion,TERMINAL_TEST
local oldCore,oldManager=getCore,getTextManager
local before=T.checks
local function width(g) return g:match("%p") and 5 or g==" " and 4 or g=="W" and 13 or 8 end
local measured=0
getTextManager=function() return {getFontHeight=function() return 16 end,
    MeasureStringX=function(_,_,text) measured=measured+1 local n=0 for g in text:gmatch(".") do n=n+width(g) end return n end} end
for _,size in ipairs({{480,540},{640,480},{1280,720},{2560,1440}}) do
    getCore=function() return {getScreenWidth=function() return size[1] end,getScreenHeight=function() return size[2] end} end
    local player=T.player(101,100,0) local pc=T.computer(T.square(100,100,0,true))
    SC.Terminal.computerState(player,pc).locked=true
    T.check(SC.Terminal.open(player,pc),"password fixture opens")
    local w=SC.Terminal.window w:flush()
    local strokes={} local mx,my,over=0,0,false
    w.drawText=function() end
    w.drawTextZoomed=function(_,text,x,y,zoom) strokes[#strokes+1]={text=text,x=x,y=y,zoom=zoom,clip=T.stencil} end
    function w:isMouseOver() return over end function w:getMouseX() return mx end function w:getMouseY() return my end
    w:drawSecurity()
    local grid,rows=w:securityGrid(),w:securityRows()
    local y=w:viewTop()+#w:securityHeaderRows()*w.rowHeight local index=1
    for _,s in ipairs(strokes) do if s.y==y then
        while rows[1].text:sub(index,index)==" " do index=index+1 end
        local glyph=rows[1].text:sub(index,index) local cell=w.layout.left+(index-1)*grid.width
        T.check(s.text==glyph and s.clip.x==cell and s.clip.width==grid.width,"every glyph, including punctuation, owns one equally wide clipped cell")
        T.check(s.x>=cell and s.x+width(glyph)*grid.zoom<=cell+grid.width,"glyph advance and hover margin fit their own cell")
        index=index+1
    end end
    T.check(index>#rows[1].text and #rows[1].text*grid.width<=w:transcriptWidth(),"complete board fits at this resolution")
    for _,span in ipairs(rows[1].spans) do
        local found=false
        for _,hit in ipairs(w.securityHits) do if hit.value==span.value then
            found=true T.check(hit.x==w.layout.left+(span.start-1)*grid.width and hit.width==span.length*grid.width,"hit box exactly matches character cells")
        end end
        T.check(found,"visible password remains clickable")
    end
    local prior=measured w:drawSecurity() T.check(measured==prior,"painting never repeats font measurement")
    local target for _,hit in ipairs(w.securityHits) do if hit.value:match("^[A-Z]+$") and hit.value~=w.system.puzzle.answer then target=hit break end end
    T.check(target~=nil,"visible wrong-word target")
    local function boldCells(hit)
        local cells={} for _,s in ipairs(strokes) do if s.y==hit.y and s.clip and s.clip.x>=hit.x and s.clip.x<hit.x+hit.width then cells[s.clip.x]=(cells[s.clip.x] or 0)+1 end end
        local n=0 for _,count in pairs(cells) do if count==2 then n=n+1 end end return n
    end
    mx,my,over=target.x+target.width/2,target.y+w.rowHeight/2,true strokes={}
    local tries=w.system.puzzle.tries w:drawSecurity()
    T.check(boldCells(target)==#target.value and w.system.puzzle.tries==tries,"hover bolds the entire word without spending a guess")
    over=false strokes={} w:drawSecurity() T.check(boldCells(target)==0,"leaving the board removes bold")
    w:onMouseDown(mx,my) T.check(w.system.puzzle.tries==tries-1,"click spends one guess")
    local bracket local tokens=SC.TerminalSystem.brackets(w.system)
    for scroll=0,#w:securityRows() do
        w.securityScroll=scroll w:drawSecurity()
        for _,hit in ipairs(w.securityHits) do for _,token in ipairs(tokens) do if hit.value==token then bracket=hit end end end
        if bracket then break end
    end
    T.check(bracket~=nil,"matching brackets remain reachable by scroll")
    mx,my,over=bracket.x+bracket.width/2,bracket.y+w.rowHeight/2,true strokes={} w:drawSecurity()
    T.check(boldCells(bracket)==#bracket.value,"hover emphasizes the entire matching bracket group")
    w:onMouseDown(mx,my) w:drawSecurity()
    for _,hit in ipairs(w.securityHits) do T.check(hit.value~=bracket.value,"spent brackets lose their click target") end
    w.system.puzzle.tries=0 w.system.puzzle.lockoutUntil=T.hours+1 w:drawSecurity()
    for _,hit in ipairs(w.securityHits) do T.check(not hit.value:match("^[A-Z]+$") and not hit.value:match("^[%[({<]"),"lockout has no puzzle targets") end
    T.check(T.stencil==nil,"drawing restores stencil state") w:close()
end
getCore,getTextManager=oldCore,oldManager
SC_TEST_REPORT=SC_TEST_REPORT.."; Fixed password grid: "..(T.checks-before).." checks passed"
