-- SPDX-License-Identifier: MIT
SurvivorCompanion=SurvivorCompanion or {}
local SC=SurvivorCompanion local UI={} SC.TerminalLockUI=UI
local textures={}
function UI.preload(name)
    local asset=SC.TerminalLockArt and SC.TerminalLockArt[name]
    for _,tile in ipairs(asset and asset.tiles or {}) do
        if textures[tile.file]==nil then
            local okay,texture=pcall(getTexture,tile.file) textures[tile.file]=okay and texture or false
        end
    end
end
function UI.art(w,name,box)
    if w:columns()<45 or w:visibleRows()<7 then return false end
    local asset=SC.TerminalLockArt and SC.TerminalLockArt[name]
    if not asset or not SCBridge or not SCBridge.drawTerminalLogo or not w.javaObject then return false end
    UI.preload(name)
    local loaded={}
    for _,tile in ipairs(asset.tiles) do
        local texture=textures[tile.file]
        if not texture or texture:getWidth()<=0 or SC.ControlUtil.call(texture,"isReady")==false then return false end
        loaded[#loaded+1]=texture
    end
    local view=asset.view or {0,0,asset.width,asset.height}
    local fit=SC.TerminalPresentation.fitImage(view[3],view[4],box)
    if not fit then return false end
    local ink=w.colors.title
    local scale=fit.width/view[3]
    local ox,oy=fit.x-view[1]*scale,fit.y-view[2]*scale
    for index,tile in ipairs(asset.tiles) do
        local core=tile.clip
        local x,y=math.max(core[1],view[1]),math.max(core[2],view[2])
        local right,bottom=math.min(core[1]+core[3],view[1]+view[3]),math.min(core[2]+core[4],view[2]+view[4])
        w:setStencilRect(ox+x*scale,oy+y*scale,math.max(0,right-x)*scale,math.max(0,bottom-y)*scale)
        local okay,result=pcall(SCBridge.drawTerminalLogo,w.javaObject,loaded[index],ox+tile.x*scale,oy+tile.y*scale,
            tile.width*scale,tile.height*scale,1,ink[2],ink[3],ink[4],0,0,0,true,true,false)
        w:clearStencilRect()
        if not okay or not result then return false end
    end
    w.lockArtDrawn=w.lockArtDrawn or {} w.lockArtDrawn[name]=true
    return true,fit
end
function UI.wrapped(w,lines,columns)
    local rows={}
    for _,line in ipairs(lines) do
        local value=type(line)=="table" and line.text or line
        local command=value:match("^%[(%d+)%]")
        if value:find("%[%d+%].-%[%d+%]") then command=nil end
        for _,wrapped in ipairs(SC.Terminal.wrap(value,columns or w:columns())) do
            local row={text=wrapped,spans={}}
            if type(line)=="table" and line.searchWords then
                for at,word in wrapped:gmatch("()([A-Za-z]+)") do
                    if word~="INDEX" and SC.TerminalLockSearch.valid(word) then row.spans[#row.spans+1]={start=at,length=#word,value=word:lower()} end
                end
            else
                local buttons={}
                for at,number in wrapped:gmatch("()%[(%d+)%]") do buttons[#buttons+1]={at=at,number=number} end
                for i,button in ipairs(buttons) do
                    local last=buttons[i+1] and buttons[i+1].at-1 or #wrapped
                    row.spans[#row.spans+1]={start=button.at,length=last-button.at+1,value=button.number}
                end
                if #buttons==0 and command then row.spans[1]={start=1,length=#wrapped,value=command} end
            end
            rows[#rows+1]=row
        end
    end
    return rows
end
function UI.rows(w,lines,now,columns,width)
    local rows=UI.wrapped(w,lines,columns)
    local visible=w.lockPanelVisible or w:visibleRows()
    local first=math.max(1,math.min(#rows-visible+1,(w.securityScroll or 0)+1))
    w.securityScroll=first-1 w.securityHits={}
    for i=first,math.min(#rows,first+visible-1) do
        local y=w:viewTop()+(i-first)*w.rowHeight
        if width then w:setStencilRect(w.layout.left,y,width,w.rowHeight) end
        w:drawRow(rows[i].text,y,"system")
        for _,run in ipairs(w:securityRowRuns(rows[i])) do
            if run.span then
                local x=w.layout.left+run.x
                local visibleWidth=math.max(0,math.min(run.width,w:transcriptWidth()-run.x,(width or w:transcriptWidth())-run.x))
                if visibleWidth>0 then w.securityHits[#w.securityHits+1]={x=x,y=y,width=visibleWidth,value=run.span.value} end
                local over=SC.ControlUtil.call(w,"isMouseOver")==true
                local mx,my=SC.ControlUtil.call(w,"getMouseX"),SC.ControlUtil.call(w,"getMouseY")
                if over and mx and my and mx>=x and mx<x+run.width and my>=y and my<y+w.rowHeight then
                    local c=w.colors.title
                    pcall(w.drawTextZoomed,w,run.text,x+1,y,w.textZoom or 1,c[2],c[3],c[4],1,w.font)
                end
            end
        end
        if width then w:clearStencilRect() end
    end
    w:drawHints({first=first,last=math.min(#rows,first+visible-1),total=#rows,visible=visible})
end
function UI.primary(w)
    if w.lockPage then return false end
    local kind=SC.TerminalLocks.kind(w.system)
    return kind=="wheel" or kind=="search" or kind=="emma" or kind=="phone" or kind=="radio" or kind=="story"
end
function UI.instantChoice(w,raw)
    if w.lockConfirm or not raw:match("^[1-9]$") then return false end
    local number=tonumber(raw) local kind=SC.TerminalLocks.kind(w.system)
    if w.lockPage=="manual" then return number<=4 or w.lockManualPage==5 and number<=9 end
    if w.lockPage then return false end
    if kind=="story" then
        local g=w.system.lock.story
        return g and g.phase~="rolling" and number<=(g.phase=="scene" and 3 or 1)
    end
    if kind=="emma" then
        local e=w.system.lock.emma
        return e and (e.offers and number<=#e.offers or e.retryUntil and number==1)
    end
    return kind=="wheel" and number==1
end
function UI.panel(w) return UI.primary(w) or w.lockPage~=nil end
function UI.primaryLines(w)
    local kind=SC.TerminalLocks.kind(w.system)
    if kind=="wheel" then return SC.TerminalLockWheel.lines(w)
    elseif kind=="search" then return SC.TerminalLockSearch.lines(w)
    elseif kind=="emma" then return SC.TerminalLockEmma.lines(w) end
    if kind=="phone" then return SC.TerminalLockPhone.lines(w) end
    if kind=="radio" then return SC.TerminalLockRadio.lines(w) end
    if kind=="story" then return SC.TerminalLockStory.lines(w) end
    return {}
end
function UI.drawFooter(w,width)
    local options=UI.footer(w) local count=width and #options or math.ceil(#options/2)
    for index,option in ipairs(options) do
        local x=w.layout.left+(width and 0 or (index-1)%2*w:transcriptWidth()/2)
        local y=w:viewTop()+(w:visibleRows()-count+(width and index-1 or math.floor((index-1)/2)))*w.rowHeight
        local available=width or w:transcriptWidth()/2
        w:setStencilRect(x,y,available,w.rowHeight)
        w:drawText(option.label,x,y,w.colors.title[2],w.colors.title[3],w.colors.title[4],1,w.font)
        w:clearStencilRect()
        w.securityHits[#w.securityHits+1]={x=x,y=y,width=available,value=option.value}
    end
end
function UI.storyParts(w)
    local beside=w:columns()>=65 and w:visibleRows()>=8
    local width=beside and w:transcriptWidth()*.73 or w:transcriptWidth()
    local columns=beside and math.floor(w:columns()*.73)-1 or w:columns()
    local body,choices={},{}
    for _,line in ipairs(SC.TerminalLockStory.lines(w)) do
        if line:match("^%[%d%]") then choices[#choices+1]=line else body[#body+1]=line end
    end
    local buttons=UI.wrapped(w,choices,columns)
    local footer=math.ceil(#UI.footer(w)/2)
    local available=math.max(1,w:visibleRows()-footer)
    if #buttons>available-1 and available>=4 then
        body[#body+1]="CHOICES IN FULL (SCROLL TO READ):"
        for _,line in ipairs(choices) do body[#body+1]=line end
        local compact={}
        for _,line in ipairs(choices) do compact[#compact+1]=#line>columns and line:sub(1,math.max(5,columns-3)).."..." or line end
        buttons=UI.wrapped(w,compact,columns)
    end
    return body,buttons,width,columns,available,beside
end
function UI.drawStory(w,now)
    local body,buttons,width,columns,available,beside=UI.storyParts(w)
    if available<4 then
        w.lockPanelVisible=available UI.rows(w,SC.TerminalLockStory.lines(w),now)
        UI.drawFooter(w) w.lockPanelVisible=nil return
    end
    w.lockPanelVisible=math.max(1,available-#buttons)
    UI.rows(w,body,now,columns,width)
    -- Choices remain pinned while the scene scrolls. A numbered option must
    -- never disappear below the fold while the player is deciding.
    for i,row in ipairs(buttons) do
        local y=w:viewTop()+(available-#buttons+i-1)*w.rowHeight
        w:setStencilRect(w.layout.left,y,width,w.rowHeight)
        w:drawRow(row.text,y,"input") w:clearStencilRect()
        local span=row.spans[1]
        if span then w.securityHits[#w.securityHits+1]={x=w.layout.left,y=y,width=width,value=span.value} end
    end
    if beside then UI.art(w,SC.TerminalLockStory.art(w),
        {x=w.layout.left+w:transcriptWidth()*.77,y=w:viewTop(),width=w:transcriptWidth()*.23,height=available*w.rowHeight}) end
    UI.drawFooter(w) w.lockPanelVisible=nil
end
function UI.rowCount(w)
    local lines=w.lockPage=="logins" and SC.TerminalPayoff.failedLogins(w.system)
        or w.lockPage=="case" and SC.TerminalLockCase.lines(w)
        or w.lockPage=="crack" and SC.TerminalLockCrack.lines(w,SC.GameplayUtil.nowMs())
        or w.lockPage=="manual" and SC.TerminalLockWheel.manualLines(w)
        or UI.primary(w) and UI.primaryLines(w) or {}
    local total=0
    local columns=(w.lockPage=="case" or w.lockPage=="crack") and w:columns()>=65 and w:visibleRows()>=8 and math.floor(w:columns()*.58) or w:columns()
    local kind=SC.TerminalLocks.kind(w.system)
    if not w.lockPage and kind=="story" then
        local body,buttons,_,columns,available=UI.storyParts(w)
        if available<4 then return #UI.wrapped(w,SC.TerminalLockStory.lines(w),columns) end
        return #UI.wrapped(w,body,columns)+#buttons
    end
    if not w.lockPage and (kind=="phone" or kind=="radio") and w:columns()>=65 and w:visibleRows()>=8 then columns=math.floor(w:columns()*.58)-1 end
    if w.lockPage=="manual" and w:columns()>=65 then columns=math.floor(w:columns()*(w.lockManualPage==5 and .52 or .58)) end
    for _,line in ipairs(lines) do total=total+#SC.Terminal.wrap(type(line)=="table" and line.text or line,columns) end
    return total
end
function UI.draw(w,now)
    if w.payoff then
        local licensed=w.licenseAwarded and w:columns()>=65 and w:visibleRows()>=8
        UI.rows(w,SC.TerminalPayoff.lines(w,now),now,licensed and math.floor(w:columns()*.58)-1 or nil,licensed and w:transcriptWidth()*.58 or nil)
        if licensed then
            UI.art(w,"RecoveryLicense",{x=w.layout.left+w:transcriptWidth()*.62,y=w:viewTop()+w.rowHeight*.5,
                width=w:transcriptWidth()*.38,height=(w:visibleRows()-1)*w.rowHeight})
        elseif not w.licenseAwarded and now-w.payoff.started<1000 then
            local fade=math.max(0,1-(now-w.payoff.started)/300)
            if SC.TerminalLamp.mode()=="flash" and w.payoff.flash then local c=w.colors.title w:drawRect(w.layout.left,w:viewTop(),w:transcriptWidth(),w.rowHeight*w:visibleRows(),.25*fade,c[2],c[3],c[4]) end
            UI.art(w,"AccessGranted",{x=w.layout.left,y=w:viewTop()+w.rowHeight*2,width=w:transcriptWidth(),height=w.rowHeight*4})
        end
        return true
    end
    if w.lockPage=="manual" then return SC.TerminalLockWheelUI.draw(w,now) end
    if w.lockPage=="crack" then
        local beside=w:columns()>=65 and w:visibleRows()>=8
        UI.rows(w,SC.TerminalLockCrack.lines(w,now),now,beside and math.floor(w:columns()*.58) or nil,beside and w:transcriptWidth()*.58 or nil)
        if beside then UI.art(w,"CrackTitle",{x=w.layout.left+w:transcriptWidth()*.62,y=w:viewTop()+w.rowHeight*2,width=w:transcriptWidth()*.38,height=w.rowHeight*3}) end
        return true
    end
    if w.lockPage=="logins" then UI.rows(w,SC.TerminalPayoff.failedLogins(w.system),now) return true end
    if w.lockPage=="case" then
        local beside=w:columns()>=65 and w:visibleRows()>=8
        local width=beside and w:transcriptWidth()*.58 or w:transcriptWidth()
        UI.rows(w,SC.TerminalLockCase.lines(w),now,beside and math.floor(w:columns()*.58) or nil,width)
        -- Text remains complete when the texture is absent. At ten rows the
        -- board lives beside the text; its clicks follow the image's fit.
        if beside then
            local drawn,fit=UI.art(w,"Case486",{x=w.layout.left+w:transcriptWidth()*.62,y=w:viewTop()+w.rowHeight,
                width=w:transcriptWidth()*.38,height=(w:visibleRows()-2)*w.rowHeight})
            if drawn then
                local regions={{.77,.27,.11,.1,"1"},{.74,.56,.18,.25,"2"}}
                for _,r in ipairs(regions) do
                    if r[5]~="2" or not SC.TerminalLockCase.soldered(w.system) then
                        w.securityHits[#w.securityHits+1]={x=fit.x+r[1]*fit.width,y=fit.y+r[2]*fit.height,
                            width=r[3]*fit.width,height=r[4]*fit.height,value=r[5]}
                    end
                end
            end
        end
        return true
    end
    if UI.primary(w) then
        if SC.TerminalLocks.kind(w.system)=="story" then UI.drawStory(w,now) return true end
        w.lockPanelVisible=math.max(1,w:visibleRows()-math.ceil(#UI.footer(w)/2))
        local kind=SC.TerminalLocks.kind(w.system)
        local beside=(kind=="phone" or kind=="radio") and w:columns()>=65 and w:visibleRows()>=8
        UI.rows(w,UI.primaryLines(w),now,beside and math.floor(w:columns()*.58)-1 or nil,beside and w:transcriptWidth()*.58 or nil)
        if SC.TerminalLocks.kind(w.system)=="search" and w.securityScroll==0 and w:columns()>=65 then
            local width=w:transcriptWidth()*.26
            UI.art(w,"UndeleteTitle",{x=w.layout.left+w:transcriptWidth()-width,y=w:viewTop(),width=width,height=w.rowHeight*1.8})
        end
        if beside then
            UI.art(w,kind=="phone" and "DialBackTitle" or "CountyKeyEscrow",
                {x=w.layout.left+w:transcriptWidth()*.62,y=w:viewTop()+w.rowHeight*.5,width=w:transcriptWidth()*.38,height=(w.lockPanelVisible-1)*w.rowHeight})
        end
        UI.drawFooter(w) w.lockPanelVisible=nil
        return true
    end
    return false
end
function UI.footer(w)
    local options={{label=w:columns()>=60 and "Fine. Other ways in." or "Other ways in",value="other ways in"}}
    if w.system.lock.bypass then options={{label="Open case",value="open the case"},{label="CRACK.EXE",value="run crack.exe"}} end
    if w.system.lock.kind=="rival" then options={} end
    local helper=SC.TerminalLockCrew.helper(w)
    if helper then options[#options+1]={label="Ask "..SC.TerminalLockCrew.name(helper),value="ask for help"} end
    options[#options+1]={label="Failed logins",value="failed logins"}
    return options
end
return UI
