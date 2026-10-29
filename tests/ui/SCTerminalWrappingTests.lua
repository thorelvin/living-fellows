-- SPDX-License-Identifier: MIT
-- Native glyph advances can differ from the M-based layout estimate.
local SC,T=SurvivorCompanion,TERMINAL_TEST
local Terminal,check=SC.Terminal,T.check
local before=T.checks
local oldCore,oldManager=getCore,getTextManager
getCore=function() return {getScreenWidth=function() return 1280 end,getScreenHeight=function() return 720 end} end
local previousManager=oldManager()
local function width(value)
    local _,wide=tostring(value):gsub("W","")
    return #tostring(value)*8+wide*5
end
getTextManager=function() return {
    getFontHeight=function(_,font) return previousManager:getFontHeight(font) end,
    MeasureStringX=function(_,font,value) return width(value) end,
} end
local player=T.player(101,100,0)
local pc=T.computer(T.square(100,100,0,true))
Terminal.computerState(player,pc).locked=false
check(Terminal.open(player,pc),"pixel-wrap fixture opens")
local w=Terminal.window w:flush()
w.rows={} w.renderRows=nil w:setFocusMode("chat")
local paragraph="WWW Wide words belong inside the transcript. "..string.rep("W",120).." End of archive."
w:displayLocalFile({date="1993-07-01",title="Summer reading",text=paragraph},false)
check(w:sidebarWidth()>0,"pixel-wrap fixture has the real menu divider")
local function verifyRows()
    local source={}
    for _,row in ipairs(w:transcriptRows()) do
        check(width(row.text)*w.textZoom<=w:contentWidth()-w.layout.pad/2+0.001,
            "every rendered line fits in pixels before the menu gutter")
        if row.source.text==paragraph then source[#source+1]=row.text end
    end
    check(table.concat(source," "):gsub("%s+",""):find(paragraph:gsub("%s+",""),1,true)==1,
        "wrapping preserves all archive words and long-token characters")
end
verifyRows()
local typingText=string.rep("W",95)
w.typing={text=typingText,shown=#typingText,kind="emma"} w.state="typing"
for _,row in ipairs(w:readingFrame(T.now).extra) do
    check(width(row.text)*w.textZoom<=w:contentWidth()-w.layout.pad/2,
        "typewriter text and cursor obey the same pixel budget")
end
w.typing=nil w.state="thinking" w.thinkStart=T.now w.thinkEnd=T.now+1000 w.thinkSteps={typingText}
for _,row in ipairs(w:readingFrame(T.now).extra) do
    check(width(row.text)*w.textZoom<=w:contentWidth()-w.layout.pad/2,
        "thinking text also wraps before the menu gutter")
end
w.state="idle"
local columns,rows=w:columns(),w:transcriptRows()
w.layout.right=w.layout.right-0.25
check(w:columns()==columns,"subpixel fixture retains the same estimated column count")
check(w:transcriptRows()~=rows,"pixel-width changes invalidate wrapping even without a column-count change")
verifyRows()
local originalDraw=w.drawRow local clipped=false
w.drawRow=function(self,...)
    check(T.stencil and T.stencil.x+T.stencil.width<self.layout.right-self:sidebarWidth(),
        "the painted transcript is clipped before the menu divider")
    clipped=true return originalDraw(self,...)
end
w:prerender()
check(clipped and T.stencil==nil,"transcript painting releases its clip before other UI draws")
w.drawRow=function() error("fixture transcript renderer unavailable") end
check(pcall(w.prerender,w) and T.stencil==nil,"a paint failure cannot leave other UI clipped")
w.drawRow=originalDraw
w:close()
getCore,getTextManager=oldCore,oldManager
SC_TEST_REPORT=SC_TEST_REPORT.."; Pixel transcript wrapping: "..(T.checks-before).." checks passed"
