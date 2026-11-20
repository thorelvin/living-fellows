-- SPDX-License-Identifier: MIT
-- Live stripe cells and candidate buttons; the optional reader art has no data.
SurvivorCompanion=SurvivorCompanion or {}
local SC=SurvivorCompanion
local UI={} SC.TerminalLockCardUI=UI
local function text(w,value,x,y,width,ink)
    local c=ink or w.colors.system
    w:setStencilRect(x,y,math.max(0,width),w.rowHeight)
    w:drawText(tostring(value),x,y,c[2],c[3],c[4],1,w.font)
    w:clearStencilRect()
end
local function hit(w,x,y,width,height,value)
    local left,top=w.layout.left,w:viewTop()
    local right,bottom=left+w:transcriptWidth(),top+w:visibleRows()*w.rowHeight
    local rx,by=math.min(right,x+width),math.min(bottom,y+height)
    x,y=math.max(left,x),math.max(top,y)
    if rx>x and by>y then w.securityHits[#w.securityHits+1]={x=x,y=y,width=rx-x,height=by-y,value=value} end
end
local function glyph(w,value,box,ink,maximum)
    local grid=w:securityGrid() local base=w.textZoom or 1
    local factor=math.min(maximum or 1.8,box.height/w.rowHeight*.8,box.width/grid.width*.8)
    local zoom=base*factor
    local width=(grid.glyphs[value] or w.charWidth)*(zoom/grid.zoom)
    local y=box.y+(box.height-w.rowHeight*factor)/2
    w:setStencilRect(box.x,box.y,box.width,box.height)
    w:drawTextZoomed(value,box.x+(box.width-width)/2,y,zoom,ink[2],ink[3],ink[4],1,w.font)
    w:clearStencilRect()
end
local function message(view)
    if view.lockedMinutes then return "READER LOCKED. TRY AGAIN IN "..view.lockedMinutes.." MINUTES. SWIPES ARE SAVED." end
    return view.message or "Choose a stripe gap, then a digit. Correct digits stay locked in."
end
-- Carry spans through text wrapping so a narrow window keeps every candidate
-- reachable. Bare digits always mean stripe input, never footer shortcuts.
function UI.rows(w,view)
    view=view or SC.TerminalLockCard.view(w)
    local raw={}
    local function add(value,spans) raw[#raw+1]={text=value,spans=spans or {}} end
    add("CARDHOLDER: "..view.board.owner)
    add("MISMATCHES LEFT: "..view.attemptsLeft)
    local disabled=view.lockedMinutes~=nil or w.lockConfirm~=nil
    local prefix="STRIPE " local spans={}
    for i,p in ipairs(view.positions) do
        if p.open and not disabled then spans[#spans+1]={start=#prefix+(i<=5 and 4+i or 5+i),length=1,value="gap "..i} end
    end
    add(prefix..view.stripe,spans)
    add("CHECK: THE BADGE DIGITS ADD UP TO THE LAST TWO.")
    if view.cursor then
        add("GAP "..view.cursor.." READ AS")
        local p=view.positions[view.cursor] local candidates=table.concat(p.candidates," ") local choices={}
        for i,digit in ipairs(p.candidates) do
            local tried=p.tried:find(digit,1,true)~=nil
            choices[#choices+1]={start=(i-1)*2+1,length=1,value=digit,tried=tried,disabled=tried or disabled}
        end
        add(candidates,choices)
    end
    local gaps,gapSpans={},{} local offset=1
    for i,p in ipairs(view.positions) do if p.open then
        local label="GAP "..i
        gapSpans[#gapSpans+1]={start=offset,length=#label,value="gap "..i,disabled=disabled}
        gaps[#gaps+1]=label offset=offset+#label+3
    end end
    if #gaps>1 then add(table.concat(gaps," / "),gapSpans) end
    add(message(view))
    local skill=SC.Terminal.electricalSkill(w.player)
    if skill>=3 then add("ELECTRICAL "..skill..": YOU CLEAN THE READ HEAD.") end
    local drawer=w.system.lock.drawer
    if drawer and not drawer.open and not drawer.forced then add("DRAWER INTERLOCK: ENGAGED") end
    local key={tostring(w.font),tostring(w.textZoom),tostring(w:columns()),tostring(w:transcriptWidth())}
    for _,row in ipairs(raw) do
        key[#key+1]=row.text
        for _,span in ipairs(row.spans) do key[#key+1]=span.value..":"..tostring(span.tried)..":"..tostring(span.disabled) end
    end
    key=table.concat(key,"\n")
    if w.lockCardRowsCache and w.lockCardRowsCache.key==key then return w.lockCardRowsCache.rows end
    local rows,measured={},{}
    local function fits(value)
        if measured[value]==nil then
            local okay,width=pcall(function() return getTextManager():MeasureStringX(w.font,value) end)
            measured[value]=(okay and tonumber(width) or #value*w.charWidth/(w.textZoom or 1))*(w.textZoom or 1)
        end
        return measured[value]<=w:transcriptWidth()
    end
    for _,row in ipairs(raw) do
        local cursor=1
        for _,line in ipairs(SC.Terminal.wrap(row.text,w:columns(),fits)) do
            local at=row.text:find(line,cursor,true) or cursor
            local wrapped={text=line,spans={}}
            for _,span in ipairs(row.spans) do
                local first,last=math.max(at,span.start),math.min(at+#line,span.start+span.length)
                if last>first then wrapped.spans[#wrapped.spans+1]={start=first-at+1,length=last-first,value=span.value,tried=span.tried,disabled=span.disabled} end
            end
            w:securityRowRuns(wrapped)
            rows[#rows+1]=wrapped cursor=at+#line
        end
    end
    w.lockCardRowsCache={key=key,rows=rows} return rows
end
function UI.large(w)
    local available=w:visibleRows()-math.ceil(#SC.TerminalLockUI.footer(w)/2)
    if w:columns()<70 or w:visibleRows()<10 or available<8 then return false end
    local view=SC.TerminalLockCard.view(w)
    return #SC.Terminal.wrap(message(view),w:columns())<=math.floor(available-(available>=11 and 8.4 or 5.95))
end
function UI.rowCount(w)
    if UI.large(w) then return math.max(1,w:visibleRows()-math.ceil(#SC.TerminalLockUI.footer(w)/2)) end
    return #UI.rows(w)
end
function UI.compact(w,view)
    local rows=UI.rows(w,view) local visible=math.max(1,w:visibleRows()-math.ceil(#SC.TerminalLockUI.footer(w)/2))
    local first=math.max(1,math.min(math.max(1,#rows-visible+1),(w.securityScroll or 0)+1))
    w.securityScroll=first-1 w.securityHits={}
    for i=first,math.min(#rows,first+visible-1) do
        local y=w:viewTop()+(i-first)*w.rowHeight
        for _,run in ipairs(w:securityRowRuns(rows[i])) do
            local x=w.layout.left+run.x local width=math.max(0,math.min(run.width,w:transcriptWidth()-run.x))
            if width>0 then
                text(w,run.text,x,y,width,run.span and w.colors.title or nil)
                if run.span and run.span.tried then
                    local c=w.colors.title w:drawRect(x,y+w.rowHeight*.45,width,1,.8,c[2],c[3],c[4])
                end
                if run.span and not run.span.disabled then hit(w,x,y,width,w.rowHeight,run.span.value) end
            end
        end
    end
    SC.TerminalLockUI.drawFooter(w)
    w:drawHints({first=first,last=math.min(#rows,first+visible-1),total=#rows,visible=visible})
end
function UI.draw(w,now)
    local view=SC.TerminalLockCard.view(w)
    if not UI.large(w) then UI.compact(w,view) return true end
    local x,y,width,row=w.layout.left,w:viewTop(),w:transcriptWidth(),w.rowHeight
    local available=w:visibleRows()-math.ceil(#SC.TerminalLockUI.footer(w)/2)
    local extended=available>=11 local c=w.colors.title
    local smallArt=not extended and w:columns()>70
    w.securityScroll=0 w.securityHits={}
    text(w,"CARDHOLDER: "..view.board.owner,x,y,width*(smallArt and .53 or .72),c)
    text(w,"LEFT: "..view.attemptsLeft,x+width*(smallArt and .55 or .75),y,width*(smallArt and .20 or .25),c)
    if smallArt then
        SC.TerminalLockUI.art(w,"LarchKeyTitle",{x=x+width*.78,y=y,width=width*.22,height=row*.95})
    end
    if extended then
        local date=view.board.lastDate or ""
        if date:match("^%d%d%d%d%-%d%d%-%d%d") then date=date:sub(6,7).."/"..date:sub(9,10).."/93" end
        text(w,"OWNER'S LAST SWIPE "..date.."  "..view.lastRead,x,y+row,width*.75)
        text(w,"YOUR SWIPE  "..(view.yourRead or "NO CARD. SWIPE ONE TO READ IT."),x,y+row*2,width*.75)
        SC.TerminalLockUI.art(w,"LarchKeyTitle",{x=x+width*.78,y=y+row,width=width*.22,height=row*1.9})
    end
    local cellY=y+row*(extended and 3.2 or 1.1)
    local cellH=row*(extended and 2.0 or 1.8)
    local gap=math.max(3,width*.009) local siteWidth=width*.18 local separator=width*.035
    local cellW=(width-siteWidth-separator-gap*6)/7
    text(w,view.board.site.."-",x,cellY+(cellH-row)/2,siteWidth,c)
    for i,p in ipairs(view.positions) do
        local bx=x+siteWidth+(i-1)*(cellW+gap)+(i>5 and separator or 0)
        local box={x=bx,y=cellY,width=cellW,height=cellH}
        if i==6 then text(w,"-",bx-separator,cellY+(cellH-row)/2,separator,c) end
        if view.cursor==i then w:drawRect(bx,cellY,cellW,cellH,.13,c[2],c[3],c[4]) end
        w:drawRectBorder(bx,cellY,cellW,cellH,view.cursor==i and 1 or .55,c[2],c[3],c[4])
        if view.cursor==i then w:drawRectBorder(bx+2,cellY+2,cellW-4,cellH-4,.7,c[2],c[3],c[4]) end
        glyph(w,p.known and p.digit or "_",box,p.solved and c or w.colors.system)
        if p.open and not view.lockedMinutes and not w.lockConfirm then hit(w,bx,cellY,cellW,cellH,"gap "..i) end
    end
    local candidateY=cellY+cellH+row*.45 local candidateH=row*(extended and 1.4 or 1.25)
    if view.cursor then
        local p=view.positions[view.cursor]
        text(w,"GAP "..view.cursor.." READ AS",x,candidateY+(candidateH-row)/2,width*.28,c)
        local bw=width*.13 local step=width*.16
        for i,digit in ipairs(p.candidates) do
            local bx=x+width*.30+(i-1)*step local tried=p.tried:find(digit,1,true)~=nil
            local box={x=bx,y=candidateY,width=bw,height=candidateH}
            w:drawRectBorder(bx,candidateY,bw,candidateH,tried and .3 or .8,c[2],c[3],c[4])
            glyph(w,digit,box,tried and w.colors.system or c,1.4)
            if tried then w:drawRect(bx+bw*.15,candidateY+candidateH*.5,bw*.7,1,.9,c[2],c[3],c[4])
            elseif not view.lockedMinutes and not w.lockConfirm then hit(w,bx,candidateY,bw,candidateH,digit) end
        end
    end
    local ruleY=candidateY+candidateH+row*.35
    text(w,"CHECK: THE BADGE DIGITS ADD UP TO THE LAST TWO.",x,ruleY,width,c)
    local statusY=ruleY+row
    local statusLines=SC.Terminal.wrap(message(view),w:columns())
    for index,line in ipairs(statusLines) do
        local at=statusY+(index-1)*row
        if at+row<=y+available*row then text(w,line,x,at,width) end
    end
    local drawer=w.system.lock.drawer
    if extended and drawer and not drawer.open and not drawer.forced and statusY+#statusLines*row<=y+(available-1)*row then
        text(w,"DRAWER INTERLOCK: ENGAGED",x,y+(available-1)*row,width)
    end
    SC.TerminalLockUI.drawFooter(w) w:drawHints()
    return true
end
return UI
