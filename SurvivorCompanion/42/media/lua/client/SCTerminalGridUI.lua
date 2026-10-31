-- SPDX-License-Identifier: MIT
-- Interaction-time sampling only. Drawing uses the cached plain snapshot.
SurvivorCompanion=SurvivorCompanion or {}
local SC=SurvivorCompanion
SC.TerminalGridUI=SC.TerminalGridUI or {}
local UI=SC.TerminalGridUI
local function G() return SC.GridControl end
local function option(label,action,value) return {label=label,gridAction=action,gridValue=value} end
function UI.active(w) return w and not w.closed and w.system and not w.system.locked and w.gridPage~=nil end
function UI.notice(w,text) w.gridNotice=tostring(text or "") end
function UI.open(w)
    w.menuPage,w.radioPage,w.gridPage,w.gridOffset,w.menuSelection=nil,nil,"status",0,1
    w.gridSampleAt=nil w:setFocusMode("menu")
    UI.update(w,0)
end
function UI.back(w)
    if w.requestTicket then w:cancelRequest() end
    if w.gridPage=="sites" then w.gridPage="status" w.gridOffset=0
    else
        w.gridPage=nil
        if w.gridSite then w.menuPage=nil else w.menuPage="home_services" end
    end
    w.menuSelection=1 w:setFocusMode("menu")
end
function UI.options(w)
    local snap=w.gridSnapshot or {}
    if snap.visible==false then return {option("Back to EMMA","back")} end
    if snap.site then return {option("Back to EMMA","back")} end
    if w.gridPage=="sites" then
        local rows={}
        local offset=w.gridOffset or 0
        for index=offset+1,math.min(#(snap.sites or {}),offset+3) do
            local site=snap.sites[index]
            local status=site.online and "Online" or site.crack and "Cracking" or site.linked and "Locked" or "Not linked"
            rows[#rows+1]=option(site.label.." / "..status,"site",site.id)
        end
        if offset+3<#(snap.sites or {}) then rows[#rows+1]=option("More substations","offset",offset+3)
        elseif offset>0 then rows[#rows+1]=option("First substations","offset",0) end
        rows[#rows+1]=option("Back","back")
        return rows
    end
    return {option(snap.on and "Switch grid off" or "Energize grid",snap.on and "cut" or "energize"),
        option("Substations and controller cracks","sites"),option("Mark next substation","mark"),
        option("Back to EMMA","back")}
end
local function propose(w,operation,site)
    w:cancelRequest()
    local ticket,prompt=SC.TerminalActions.prepare(w,{kind="grid_control",operation=operation,site=site})
    w.requestTicket=ticket UI.notice(w,prompt)
    if ticket then w:setFocusMode("chat") end
    if not UI.active(w) then w:startReply({lines={prompt},thinkMs=0}) end
end
local function act(w,action,value)
    if action=="open" then UI.open(w)
    elseif action=="back" then UI.back(w)
    elseif action=="sites" then w.gridPage="sites" w.menuSelection=1
    elseif action=="offset" then w.gridOffset=value w.menuSelection=1
    elseif action=="mark" then
        local okay=G().markNearest(w.object)
        UI.notice(w,okay and "Nearest unlinked substation marked on your map." or "No new substation marker is available.")
    elseif action=="site" then
        local selected
        for _,site in ipairs(w.gridSnapshot and w.gridSnapshot.sites or {}) do if site.id==value then selected=site break end end
        if not selected then return false end
        if selected.online then UI.notice(w,selected.label.." is online. It reduces cooling time.")
        elseif selected.crack then UI.notice(w,selected.label..": "..string.format("%.1f",selected.crack.doneHours/selected.crack.requiredHours*100).."% cracked. Use the cracking computer or contact EMMA to refresh its status.")
        elseif not selected.linked then UI.notice(w,"Bring a spare computer with a mounted radio and a generator within 40 tiles of "..selected.label..". The computer and radio stay there.")
        else propose(w,"crack",value) end
    else propose(w,action) end
    return true
end
function UI.input(w,raw,selected)
    if selected and selected.gridAction then return act(w,selected.gridAction,selected.gridValue) end
    if not UI.active(w) then return false end
    local lower=string.lower(tostring(raw or ""))
    if lower=="back" or lower=="exit" then UI.back(w) return true end
    if lower=="energize grid" then return act(w,"energize") end
    if lower=="switch grid off" then return act(w,"cut") end
    -- Tab still reaches EMMA's ordinary language parser.
    return false
end
function UI.scroll(w,delta)
    if not UI.active(w) or w.gridPage~="sites" then return false end
    w.gridOffset=math.max(0,math.min(6,(w.gridOffset or 0)+(delta>0 and 3 or -3)))
    w.menuSelection=1 return true
end
function UI.click(w,x,y)
    if not UI.active(w) then return false end
    for _,box in ipairs(w.gridHits or {}) do
        if x>=box.x and x<box.x+box.width and y>=box.y and y<box.y+box.height then
            w:playClickSound() w.menuSelection=box.index w:setFocusMode("menu")
            return act(w,box.option.gridAction,box.option.gridValue)
        end
    end
    return true
end
function UI.update(w,now)
    if w.closed or not w.system or w.system.locked then return end
    if not w.gridAnnounced and w.state=="idle" then
        G().sample(w.object)
        local lines=G().announce(w.object)
        for _,line in ipairs(lines) do w:print(line,"emma") end
        w.gridAnnounced=true
    end
    if not UI.active(w) then return end
    if w.gridSampleAt and now>=w.gridSampleAt and now-w.gridSampleAt<1000 then return end
    w.gridSampleAt=now w.gridSnapshot=G().snapshot(w.object)
    local notices,last=G().notices(w.gridNoticeSerial)
    w.gridNoticeSerial=last
    if #notices>0 then UI.notice(w,notices[#notices].text) end
end
local function duration(hours)
    hours=math.max(0,math.ceil(tonumber(hours) or 0))
    return math.floor(hours/24).."d "..(hours%24).."h"
end
function UI.draw(w,now)
    local snap=w.gridSnapshot or {}
    local ink,title=w.colors.emma,w.colors.title
    local left,width,row=w.layout.left,w.layout.right-w.layout.left,w.rowHeight
    local y=w:viewTop()
    local function text(value,x,at,color)
        color=color or ink
        local lines=w:wrapTranscript(tostring(value or ""))
        local shown=lines[1] or ""
        if #lines>1 and #shown>3 then shown=shown:sub(1,#shown-3).."..." end
        w:drawText(shown,x,at,color[2],color[3],color[4],1,w.font)
    end
    if w.requestTicket then
        local columns=math.max(8,math.floor(width/w.charWidth))
        for _,line in ipairs(SC.Terminal.wrap(w.gridNotice or "Confirm Y/N.",columns)) do
            if y+row>w:viewBottom() then break end text(line,left,y,title) y=y+row end
        w.gridHits={} return
    end
    local buttons=UI.options(w)
    local gap=math.max(4,math.floor(row/4))
    local bottom=w:viewBottom()-#buttons*(row+gap)
    local function line(value,color)
        if y+row>bottom-gap then return false end
        text(value,left,y,color) y=y+row return true
    end
    local function bar(percent,label)
        if y+row>bottom-gap then return end
        local start=label and left+math.min(width*.3,w.charWidth*12) or left
        local span=width-(start-left)
        w:drawRect(start,y+row*.3,span,row*.4,.15,title[2],title[3],title[4])
        w:drawRect(start,y+row*.3,span*math.max(0,math.min(100,percent))/100,row*.4,.75,title[2],title[3],title[4])
        if label then text(label,left,y,title) end
        y=y+row
    end
    if snap.visible==false then line(snap.reason or "Grid control unavailable.")
    else
        local heat=math.max(0,math.min(100,snap.heat or 0))
        local status=snap.on and "GRID ON / "..duration(snap.remainingHours).." TO TRIP"
            or (snap.daysLeft or 0)>0 and "ORIGINAL GRID ON"
            or snap.locked and "GRID OFF / BREAKER LOCKED" or "GRID OFF / MANUAL START"
        line(status.." / HEAT "..math.floor(heat).."%",title)
        -- Put progress and restart information before optional decoration.
        -- At large fonts the viewport may only have room for three status rows.
        local crack=snap.crack
        if crack then
            line(crack.label.." / CRACK "..string.format("%.1f",crack.percent).."% / "..duration(crack.requiredHours-crack.doneHours).." LEFT")
            bar(crack.percent)
            line(crack.paused and ("PAUSED: "..crack.paused) or "LAST KNOWN SUPPLY / REFRESHED ON CONTACT")
        elseif snap.connecting then
            line("CONNECTING "..string.format("%.1f",snap.connecting.percent).."% / KEEP THE GENERATOR ON")
            bar(snap.connecting.percent)
        else
            if snap.locked then line("COOLING: "..duration(snap.coolingHours).." TO COLD / "..(snap.cooldownDays or 7).." DAYS FROM FULL") end
            if heat>0 or snap.site then bar(heat,"HEAT "..math.floor(heat).."%") end
            if heat>0 and not snap.locked then line("COOLING: "..duration(snap.coolingHours).." TO COLD / "..(snap.cooldownDays or 7).." DAYS FROM FULL") end
        end
        line(snap.standDown or w.gridNotice or snap.blocker or "Each linked controller needs its own crack.")
        line((snap.online or 0).." OF 5 CONTROLLERS ONLINE / "..(snap.linked or 0).." LINKED")
        if snap.site then line("CONTROLLER: "..snap.site.label.." / THIS COMPUTER STAYS HERE") end
        line((snap.daysLeft or 0)>0 and ("ORIGINAL SHUTOFF IN "..duration(snap.daysLeft*24))
            or ("ORIGINAL SHUTOFF: DAY "..tostring(snap.originalShut).." / PASSED"))
        if crack then
            local attempted=math.floor(crack.percent/100*2887000)
            line("TRIED "..attempted.." / 2887000 / LAST "..string.format("%X",attempted*17%16777216).." REJECTED")
        end
    end
    w.gridHits={}
    for index,button in ipairs(buttons) do
        local at=bottom+(index-1)*(row+gap)
        local box={x=left,y=at,width=width,height=row,index=index,option=button}
        w.gridHits[#w.gridHits+1]=box
        if w.focusMode=="menu" and w.menuSelection==index then
            w:drawRectBorder(left-2,at-1,width+4,row+2,.8,title[2],title[3],title[4])
        end
        text("["..index.."] "..button.label,left,at,title)
    end
end
return UI
