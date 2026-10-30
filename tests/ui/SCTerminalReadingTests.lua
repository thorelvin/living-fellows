-- SPDX-License-Identifier: MIT
-- Actual terminal painting and input paths at the resolutions seen in game.
local SC,T=SurvivorCompanion,TERMINAL_TEST
local Terminal,System=SC.Terminal,SC.TerminalSystem
local check,before=T.check,T.checks
local saved={core=getCore,world=SC.TerminalWorld.new,random=ZombRand,clock=Terminal._clock,
    left=getPlayerScreenLeft,top=getPlayerScreenTop,width=getPlayerScreenWidth,height=getPlayerScreenHeight}
local width,height,inside=1280,720,false
getCore=function() return {getScreenWidth=function() return width end,getScreenHeight=function() return height end} end
getPlayerScreenLeft,getPlayerScreenTop,getPlayerScreenWidth,getPlayerScreenHeight=nil,nil,nil,nil
ZombRand=function(maximum) return maximum>1000000 and 19 or 0 end
Terminal._clock=function() return T.now end
local people={}
for index=1,12 do people[index]={id="resident-"..index,name="Resident "..string.format("%02d",index),
    health=100,where="at camp",doing="sorting supplies"} end
SC.TerminalWorld.new=function() return {
    camp=function() return {inside=inside,configured=true,name="Home"} end,
    clock=function() return {worldHours=T.hours,hour=10,minute=0,day=1,month=6,year=1993,days=2} end,
    power=function() return {source="grid"} end,
    people=function() return people end,
    storage=function() return {groups={},items=0,containers=0} end,
} end
local player=T.player(101,100,0)
local function open()
    local computer=T.computer(T.square(100,100,0,true))
    check(Terminal.open(player,computer),"reading fixture opens")
    local window=Terminal.window window:flush()
    return window,computer
end
local function paint(window)
    local painted,hint,securityRows={},nil,{}
    local drawRow,drawText=window.drawRow,window.drawText
    window.drawRow=function(self,value,y,kind)
        check(y>=self:viewTop() and y+self.rowHeight<=self:viewBottom()+2,
            "every painted content row remains above the hints and input")
        if not self.system.locked then painted[#painted+1]=value end
        return drawRow(self,value,y,kind)
    end
    window.drawText=function(self,value,x,y,...)
        if y==self.layout.hintY then hint=value end
        if self.system.locked and y>=self:viewTop() and y+self.rowHeight<=self:viewBottom()+2 then
            -- Password rows now paint measured colour runs rather than
            -- repainting a second copy of each highlighted word.
            if not securityRows[y] then securityRows[y]=#painted+1 painted[#painted+1]="" end
            local index=securityRows[y]
            painted[index]=painted[index]..value
        end
        return drawText(self,value,x,y,...)
    end
    window:prerender()
    window.drawRow,window.drawText=drawRow,drawText
    return painted,hint
end
local function contains(rows,fragment) return table.concat(rows,"\n"):find(fragment,1,true)~=nil end
local function send(window,raw)
    window:setFocusMode("chat") window.entry:setText(raw) window:submit()
end

local w=open()
check(w.system.locked,"outside desktop starts with its real recovery puzzle")
local p=w.system.puzzle
local words=table.concat(p.words,",")
local shown=paint(w)
check(contains(shown,"Attempts: 4/4") and contains(shown,p.words[1]),
    "a 720p recovery screen opens at its first candidates with attempts visible")
w:scrollBy(-10000)
check(#w.securityHits==0,"paging invalidates old clickable word coordinates before the next paint")
local last,hint=paint(w)
check(contains(last,"Attempts: 4/4") and contains(last,System.brackets(w.system)[4]),
    "scrolling to the last bracket groups keeps attempts pinned")
check(hint and hint:find("PgUp/PgDn",1,true),"recovery paging is explained outside the clickable board")
w:otherKey(Keyboard.KEY_PRIOR) paint(w)
w:scrollBy(10000) paint(w)
local hit
for _,box in ipairs(w.securityHits) do
    if box.value:match("^[A-Z]+$") and box.value~=p.answer then hit=box break end
end
check(hit~=nil,"the top page exposes a real incorrect word")
local wrong=hit.value
w:onMouseDown(hit.x+1,hit.y+1)
check(p.tries==3 and #w.securityHits==0,"a word click spends exactly one attempt and retires old hit targets")
w:scrollBy(-10000)
shown=paint(w)
check(contains(shown,"Attempts: 3/4") and contains(shown,wrong..":"),
    "the latest likeness and remaining attempts stay visible above the last page")
for _,word in ipairs(p.words) do
    if word~=p.answer and p.guessed[word]==nil then send(w,word) end
    if p.tries==0 then break end
end
shown=paint(w)
check(contains(shown,"Retry: 60 game min") and #w.securityHits==0,
    "lockout pins its game-time countdown and exposes no actionable candidates")
T.hours=T.hours+System.LOCK_HOURS T.now=T.now+Terminal.WATCH_MS+1
w:watch(T.now)
shown=paint(w)
check(contains(shown,"Attempts: 4/4") and not contains(shown,"No attempts remain")
    and #w.securityHits>0 and table.concat(p.words,",")==words,
    "lockout expiry clears stale failure feedback while preserving the original puzzle")
for _,size in ipairs({{480,480},{480,540},{640,480},{1280,720},{1920,1080},{3840,2160}}) do
    width,height=size[1],size[2] w:refreshLayout() w:scrollBy(10000)
    shown=paint(w)
    check(contains(shown,"Attempts: 4/4") and contains(shown,p.words[1]),
        "attempts and at least the first candidate fit at "..width.."x"..height)
    for _,row in ipairs(w:securityRows()) do
        check(#row.text<=w:columns(),"recovery history wraps inside the available screen")
    end
end
w:close()

width,height,inside=1280,720,true
local computer
w,computer=open()
send(w,"clear")
for index=1,30 do w:print("Earlier message "..index) end
local identity,archive,visits,notes=w.system.identity,w.system.archive,w.session.visits,#w.session.notes
send(w,"who is here") w:flush()
shown,hint=paint(w)
check(shown[1]=="> who is here" and contains(shown,"Resident 01") and w.scroll>0,
    "a completed long reply starts at its question and first people, not the clipped tail")
check(hint and hint:find("PgUp/PgDn",1,true),"long replies expose paging guidance")
w:scrollBy(-10000) shown=paint(w)
check(w.scroll==0 and contains(shown,"Resident 12"),"paging forward reaches the last people in the report")

w.pendingPrompt=w:print("> extended report","input")
local report={}
for index=1,24 do report[index]="Incoming report row "..index end
w:startReply({lines=report,thinkMs=0})
w:scrollBy(5)
shown=paint(w)
local firstReading=shown[1]
for _=1,10 do T.now=T.now+250 w:advance(T.now) paint(w) end
shown=paint(w)
check(shown[1]==firstReading,"incoming typewriter rows do not move the text being read")
w:flush() shown=paint(w)
check(shown[1]==firstReading,"finishing an answer respects a manual reading position")
w:scrollBy(-10000) shown=paint(w)
check(w.scroll==0 and contains(shown,"Incoming report row 24"),"returning to the latest output remains available")

w:displayLocalFile({date="1993-07-01",title="A long local record",text=string.rep("Original archive text. ",30)},true)
shown=paint(w)
check(shown[1]:find("1993-07-01",1,true)==1,"long archive records still start at their dated heading")
-- Native font metrics can leave a sidebar where the coarse fixture font does
-- not. Reproduce the full-menu -> chat width change without resizing the UI.
local oldServices,oldSide=SC.TerminalServices,w.layout.side
SC.TerminalServices={menu=function() end}
w.layout.side=240 w.menuPage="lore" w:setFocusMode("menu")
local wide=w:columns() w:transcriptRows()
w:setFocusMode("chat")
check(w:columns()<wide,"native sidebar fixture narrows text without a viewport resize")
local archiveRows={}
for _,row in ipairs(w:transcriptRows()) do
    check(#row.text<=w:columns(),"cached archive text reflows before the sidebar can cover it")
    if row.source.text:find("Original archive text.",1,true) then archiveRows[#archiveRows+1]=row.text end
end
for index=1,#archiveRows-1 do
    check(#archiveRows[index]>=w:columns()-9,"paragraph reflow does not leave old short-line fragments")
end
SC.TerminalServices,w.layout.side=oldServices,oldSide w.menuPage=nil
width,height=480,540 w:refreshLayout() shown=paint(w)
check(shown[1]:find("1993-07-01",1,true)==1,"resizing preserves the original heading while rewrapping it")
for index=1,Terminal.SCROLLBACK_ROWS+50 do w:print("Retained "..index) end
shown=paint(w)
check(#w.rows==Terminal.SCROLLBACK_ROWS and shown[1]==w.rows[1].text,
    "history trimming bounds memory and falls back to the oldest retained reading position")
check(w.system.identity==identity and w.system.archive==archive and w.session.visits==visits
    and #w.session.notes==notes,"reading and paging do not change portable records, visits or notes")
computer.square.generatorPower=false T.now=T.now+Terminal.WATCH_MS+1
w:watch(T.now) shown=paint(w)
check(w.state=="closing" and contains(shown,"POWER FAILURE"),
    "power failure overrides the reading anchor so its warning remains visible")
w:close()
getCore,SC.TerminalWorld.new,ZombRand=saved.core,saved.world,saved.random
Terminal._clock=saved.clock
getPlayerScreenLeft,getPlayerScreenTop,getPlayerScreenWidth,getPlayerScreenHeight=saved.left,saved.top,saved.width,saved.height
SC_TEST_REPORT=SC_TEST_REPORT.."; Recovery and reading: "..(T.checks-before).." checks passed"
