-- SPDX-License-Identifier: MIT
-- A responsive program page inside the existing terminal, not another player
-- view. Native state is sampled by poll; drawing only animates cached activity.
SurvivorCompanion=SurvivorCompanion or {}
local SC=SurvivorCompanion
SC.TerminalRadioUI=SC.TerminalRadioUI or {}
local UI=SC.TerminalRadioUI
local function R() return SC.TerminalRadio end
local function U() return SC.ControlUtil end
local function option(label,action,value) return {label=label,radioAction=action,radioValue=value} end
local function trimmed(s) return tostring(s or ""):lower():gsub("[?!%.]+$",""):gsub("%s+"," "):match("^%s*(.-)%s*$") end
function UI.active(w) return w and not w.closed and w.system and w.menuPage=="radio_desk" and not w.system.locked end
function UI.notice(w,text) w.radioNotice=tostring(text or "") end
function UI.open(w)
    local rt,reason=R().ready(w)
    if not rt then w:print(reason,"system") return false end
    if not UI.active(w) then w.radioReturn=w.menuPage end
    w.menuPage,w.radioPage,w.radioOffset,w.menuSelection="radio_desk","home",0,1
    w.radioNotice="LARCH/WAVE ready. Presets, scanning, audio and your reception notebook."
    if R().hasMission() then
        local _,message=R().tune(w,R().teamChannel())
        w.radioNotice="Active expedition: team channel selected where available. "..tostring(message or "")
    end
    w:setFocusMode("menu") R().poll(w)
    return true
end
function UI.leave(w)
    R().leave(w)
    w.menuPage,w.menuSelection=w.radioReturn,1
    w.radioReturn=nil w.radioHits=nil
end
function UI.back(w)
    if w.requestTicket then w:cancelRequest() end
    if w.radioPage~="home" then w.radioPage,w.radioOffset,w.menuSelection="home",0,1
    else UI.leave(w) end
end
function UI.options(w)
    local rt=R().snapshot(w)
    if not rt then return {option("Back to EMMA","leave")} end
    local p=w.radioPage
    if p=="reading" then return {option("Back to notebook","page","notebook")}
    elseif p=="library" then return {option("Received text","page","notebook"),option("Heard stations","page","heard"),option("Back","back")}
    elseif p=="presets" or p=="heard" or p=="notebook" then
        local rows=p=="presets" and R().presets(w.object) or rt and rt.memory[p=="heard" and "found" or "log"] or {}
        local result={} local offset=w.radioOffset or 0
        for i=offset+1,math.min(offset+3,#rows) do
            local row=rows[i]
            local label=R().format(row.frequency).." / "..(row.name~="" and row.name or "Unnamed")
            if p=="notebook" then label=R().format(row.frequency).." / "..string.format("%.1fh",row.at)..(row.recorded and " / Recording" or " / Received") end
            result[#result+1]=option(label,p=="notebook" and "read" or "tune",p=="notebook" and i or row.frequency)
        end
        if offset>0 then result[#result+1]=option("Previous","offset",math.max(0,offset-3)) end
        if offset+3<#rows then result[#result+1]=option("More","offset",offset+3) end
        result[#result+1]=option("Back","back")
        return result
    elseif p=="scan" then
        return {option("Scan presets","scan","presets"),option("Band sweep","scan","band"),
            option("Stay on this channel","stay"),option("Continue scanning","continue"),
            option("Stop / restore","stop"),option("Back","back")}
    elseif p=="audio" then
        return {option("Volume -","volume",-0.1),option("Volume +","volume",0.1),option("Speaker "..(rt and rt.volume>0 and "mute" or "unmute"),"mute"),
            option("Microphone "..(rt and rt.mic and "mute" or "open"),"mic"),option("Visual: "..(rt and rt.memory.mode or "bars"),"visual"),option("Back","back")}
    elseif p=="team" then
        return {option("Tune team channel","team"),option("Progress report","control",{operation="radio",command="progress_report",payload="status"}),
            option("Recall expedition","control",{operation="radio",command="return_now",payload="now"}),
            option("Book Marcus","control",{operation="taxi",verb="book"}),option("Last report","lastReport"),option("Back","back")}
    end
    return {option("Presets","page","presets"),option("Scanner","page","scan"),option("Audio / visual","page","audio"),
        option("Notebook","page","library"),option("Team / Marcus","page","team"),option("Back to EMMA","leave")}
end
local function result(w,okay,message,proposal)
    if proposal then
        w:cancelRequest()
        local ticket,prompt=SC.TerminalActions.prepare(w,proposal)
        w.requestTicket=ticket UI.notice(w,prompt)
        w:setFocusMode("chat")
    else UI.notice(w,message) end
    return true
end
local function act(w,action,value)
    if action=="open" then UI.open(w) return true
    elseif action=="page" then w.radioPage,w.radioOffset,w.menuSelection=value,0,1 return true
    elseif action=="offset" then w.radioOffset,w.menuSelection=value,1 return true
    elseif action=="back" then UI.back(w) return true
    elseif action=="leave" then UI.leave(w) return true
    elseif action=="read" then
        local snap=R().snapshot(w) local row=snap and snap.memory.log[value]
        if row then w.radioReading=row w.radioReadOffset=0 w.radioPage="reading" UI.notice(w,"") end
        return true
    elseif action=="lastReport" then
        local report=R().lastReport(w.object)
        local detail=report and (report.kind=="scout" and "scouting" or tostring(report.collected or "unknown").." collected")
        if report and report.stored~=nil then detail=detail.."; "..tostring(report.stored).." stored" end
        return result(w,true,report and ("Last confirmed report: "..tostring(report.phase or "working").."; "..detail
            ..". Heard at "..tostring(report.at or "unknown").." game hours.") or "No report has been acknowledged at this PC. Request a fresh report from the expedition.")
    end
    local rt,reason=R().ready(w)
    if not rt then return result(w,false,reason) end
    rt.lastPoll=nil
    if action=="control" then
        R().stop(w.object,true)
        if value.operation=="radio" then
            local okay,detail=R().tune(w,R().teamChannel())
            if not okay then return result(w,false,detail) end
        end
        return result(w,nil,nil,{kind="control",request=value})
    end
    if action=="scan" then return result(w,R().scan(w,value))
    elseif action=="tune" or action=="team" then return result(w,R().tune(w,action=="team" and R().teamChannel() or value))
    elseif action=="continue" then return result(w,R().continue(w))
    elseif action=="stay" then R().stop(w.object,false) return result(w,true,"Staying here. Type: save this channel as Weather")
    elseif action=="stop" then R().stop(w.object,true) return result(w,true,rt.notice)
    elseif action=="visual" then R().cycleMode(w.object) return result(w,true,"Visualisation follows native radio reception activity.")
    elseif action=="mic" then return result(w,R().audio(w,"mic",not (U().call(rt.data,"getMicIsMuted")==true)))
    elseif action=="volume" then return result(w,R().audio(w,"volume",math.max(0,math.min(1,(U().call(rt.data,"getDeviceVolume") or 0)+value))))
    elseif action=="mute" then
        local part=SC.TerminalHardware.state(w.object,false).radio
        return result(w,R().audio(w,"volume",(U().call(rt.data,"getDeviceVolume") or 0)>0 and 0 or part.lastMonitorVolume or .3))
    elseif action=="save" then return result(w,R().savePreset(w,value)) end
    return false
end
function UI.input(w,raw,chosen)
    local text=trimmed(raw):gsub("^emma[,:%s]+",""):gsub("^please%s+","")
    local request,argument
    if chosen and chosen.radioAction then return act(w,chosen.radioAction,chosen.radioValue) end
    if text=="open radio" or text=="open the radio" or text=="radio desk" or text=="radio software" or text=="larch/wave" then request="open"
    elseif text=="scan for broadcasts" or text=="scan channels" or text=="scan presets" then request,argument="scan","presets"
    elseif text=="scan the band" or text=="scan band" then request,argument="scan","band"
    elseif text=="return to the expedition channel" or text=="team channel" then request="team"
    elseif text=="what did we hear" or text=="radio notebook" or text=="show radio log" then request,argument="page","notebook"
    elseif text=="heard stations" then request,argument="page","heard"
    elseif text=="next preset" then request,argument="presetStep",1
    elseif text=="previous preset" then request,argument="presetStep",-1
    elseif text=="continue scanning" then request="continue"
    elseif text=="stop scanning" then request="stop"
    elseif text=="stay here" and UI.active(w) then request="stay"
    elseif text=="mute radio" then request,argument="setVolume",0
    elseif text=="unmute radio" then request="unmute"
    elseif text=="mute microphone" then request,argument="setMic",true
    elseif text=="unmute microphone" then request,argument="setMic",false
    else
        local words=raw:gsub("^[Ee][Mm][Mm][Aa][,:%s]+",""):gsub("^[Pp]lease%s+","")
        argument=words:match("^[Ss]ave this channel as%s+(.+)$")
            or words:match("^[Ss]ave channel as%s+(.+)$")
        if argument then request="save" end
        if not request then
            local number=text:match("^tune%s+to%s+([%d%.]+)%s*mhz$") or text:match("^tune%s+([%d%.]+)%s*mhz$")
                or text:match("^tune%s+to%s+([%d%.]+)$") or text:match("^tune%s+([%d%.]+)$")
            if number then request,argument="tune",tonumber(number) and tonumber(number)*1000 end
        end
        if not request then
            argument=text:match("^listen to%s+(.+)$")
            if argument then request="namedPreset" end
        end
        if not request then
            local number=text:match("^channel%s+(%d+)$")
            if number then request,argument="tune",tonumber(number) end
        end
        if not request then
            local number=text:match("^volume%s+(%d+)%%?$")
            if number then request,argument="setVolume",tonumber(number)/100 end
        end
    end
    if request then
        if not UI.active(w) and not UI.open(w) then return true end
        if request=="open" then return true end
        -- The program can remain open after an outage or component removal.
        -- Direct commands must revalidate before reading presets or hardware;
        -- the last rendered snapshot is not authority for a new action.
        local rt,reason=R().ready(w)
        if not rt then R().leave(w) return result(w,false,reason) end
        rt.lastPoll=nil
        local fresh,detail=R().poll(w)
        if not fresh then return result(w,false,detail) end
        if request=="presetStep" or request=="namedPreset" then
            local presets=R().presets(w.object) local selected
            if request=="presetStep" then
                local snapshot=R().snapshot(w) local at=argument==1 and 0 or 1
                for i,p in ipairs(presets) do if p.frequency==snapshot.frequency then at=i break end end
                if #presets>0 then selected=presets[((at-1+argument)%#presets)+1] end
            else
                for _,p in ipairs(presets) do
                    if trimmed(p.name)==argument then
                        if selected then return result(w,false,"Several presets have that name. Select a frequency from Presets.") end
                        selected=p
                    end
                end
            end
            if selected then return act(w,"tune",selected.frequency) end
            return result(w,false,"No matching preset. Open Presets or save the current frequency.")
        end
        if request=="setVolume" or request=="setMic" then return result(w,R().audio(w,request=="setMic" and "mic" or "volume",argument)) end
        if request=="unmute" then
            local part=SC.TerminalHardware.state(w.object,false).radio
            return result(w,R().audio(w,"volume",part.lastMonitorVolume or .3))
        end
        return act(w,request,argument)
    end
    if UI.active(w) then
        if text=="back" or text=="menu" then UI.back(w) return true end
        -- Ordinary EMMA questions leave this program. Closing a scan restores
        -- its previous channel, and the normal transcript remains available.
        UI.leave(w) w.menuPage=nil w:setFocusMode("chat")
    end
    return false
end
function UI.key(w,key)
    if UI.active(w) and w.focusMode=="menu" and not w.requestTicket then
        if key==Keyboard.KEY_LEFT then UI.input(w,"previous preset") return true end
        if key==Keyboard.KEY_RIGHT then UI.input(w,"next preset") return true end
    end
    return false
end
function UI.update(w,now)
    if UI.active(w) then
        local rt,reason=R().poll(w,now)
        if not rt then UI.notice(w,reason) end
    end
end
function UI.boxes(w)
    local options=UI.options(w) local boxes={}
    local pad=math.max(3,math.floor(w.layout.pad/3))
    local grid=#options>1 and (w.radioPage=="home" or w.radioPage=="scan" or w.radioPage=="audio" or w.radioPage=="team")
    local cols=grid and (w:columns()>=48 and 3 or 2) or 1
    local rows=math.ceil(#options/cols)
    local gap=grid and pad or 2
    local h=w.rowHeight+gap
    local y=w:viewBottom()-rows*h
    local width=(w.layout.right-w.layout.left)/cols
    for i,o in ipairs(options) do
        boxes[#boxes+1]={x=w.layout.left+((i-1)%cols)*width,y=y+math.floor((i-1)/cols)*h,
            width=width-pad,height=h-gap,index=i,option=o}
    end
    return boxes,y-pad
end
function UI.scroll(w,delta)
    if UI.active(w) and w.radioPage=="reading" then
        w.radioReadOffset=math.max(0,(w.radioReadOffset or 0)+delta) return true
    end
    return false
end
function UI.click(w,x,y)
    if not UI.active(w) then return false end
    for _,box in ipairs(w.radioHits or {}) do
        if x>=box.x and x<box.x+box.width and y>=box.y and y<box.y+box.height then
            w:setFocusMode("menu") w.menuSelection=box.index
            act(w,box.option.radioAction,box.option.radioValue) return true
        end
    end
    return false
end
function UI.draw(w,now)
    local snap=R().snapshot(w) local colors=w.colors local ink=colors.emma local title=colors.title
    local left,top,width=w.layout.left,w:viewTop(),w.layout.right-w.layout.left
    local row=w.rowHeight
    local function text(value,x,y,color)
        color=color or ink
        w:drawText(value,x,y,color[2],color[3],color[4],1,w.font)
    end
    local function lines(value,y,bottom,color)
        for _,line in ipairs(SC.Terminal.wrap(value,w:columns())) do
            if y+row>bottom then break end
            text(line,left,y,color) y=y+row
        end
        return y
    end
    if w.requestTicket then
        lines(w.radioNotice or "Confirm Y/N.",top,w:viewBottom(),colors.alert)
        w.radioHits={} return
    end
    local boxes,buttonTop=UI.boxes(w)
    w.radioHits=boxes
    if not snap then
        lines(w.radioNotice or "Radio unavailable.",top,buttonTop)
        for _,box in ipairs(boxes) do
            w:drawRectBorder(box.x,box.y,box.width,box.height,.6,title[2],title[3],title[4])
            text("[1] Back to EMMA",box.x+2,box.y+1,title)
        end
        return
    end
    if w.radioReceipts~=snap.receipts then w.radioReceipts=snap.receipts w.radioNotice=nil end
    local state=snap.tx and "TRANSMITTING" or snap.scan and (snap.scan.hold and "HOLDING SIGNAL" or "SCANNING")
        or snap.receiving and "RECEIVING" or "LISTENING"
    text(R().format(w.radioPage=="reading" and w.radioReading.frequency or snap.frequency).." / "..state,left,top,title)
    local detail=string.format("Vol %d%% / Mic %s / %s",math.floor(snap.volume*100+.5),snap.mic and "open" or "muted",snap.name)
    text(SC.Terminal.wrap(detail,w:columns())[1],left,top+row)
    local plotY=top+row*2+2
    local plotH=math.max(0,math.min(row*2.4,buttonTop-plotY-row*2))
    if w.radioPage=="reading" then plotH=0 end
    w.radioBars=w.radioBars or {} w.radioPeaks=w.radioPeaks or {}
    local dt=math.min(.1,math.max(0,(now-(w.radioFrameAt or now))/1000)) w.radioFrameAt=now
    for i=1,24 do
        local target=(snap.receiving or snap.tx) and (.18+.82*math.abs(math.sin(now/290+i*1.7)*math.cos(now/530-i*.38))) or 0
        w.radioBars[i]=target>(w.radioBars[i] or 0) and target or math.max(target,(w.radioBars[i] or 0)-dt*1.6)
        w.radioPeaks[i]=math.max(w.radioBars[i],(w.radioPeaks[i] or 0)-dt*.36)
        if plotH>4 then
            local cw=width/24
            if snap.memory.mode=="bars" then
                local block=math.max(3,plotH/10) local count=math.floor(w.radioBars[i]*plotH/block)
                for step=1,count do w:drawRect(left+(i-1)*cw,plotY+plotH-step*block,cw-3,block-2,.9,ink[2],ink[3],ink[4]) end
                w:drawRect(left+(i-1)*cw,plotY+plotH-w.radioPeaks[i]*plotH,cw-3,2,.85,title[2],title[3],title[4])
            elseif snap.memory.mode=="wave" then
                local yy=plotY+plotH/2+math.sin(now/180+i*.85)*w.radioBars[i]*plotH*.45
                w:drawRect(left+(i-1)*cw,yy,cw-2,3,.9,ink[2],ink[3],ink[4])
            else
                w:drawRect(left+(i-1)*cw,plotY+plotH*.35,cw-3,plotH*.3,snap.receiving and .9 or .12,ink[2],ink[3],ink[4])
            end
        end
    end
    local y=plotY+plotH+3
    if w.radioPage=="reading" and w.radioReading then
        local saved=w.radioReading
        y=lines((saved.recorded and "Recording / " or "Received / ")..string.format("%.1f game hours",saved.at),y,buttonTop,title)
        local observation=saved.recorded and "EMMA: Recorded media; not a live contact." or saved.text:lower():find("weather",1,true)
            and "EMMA: Weather is mentioned in this reception." or "EMMA: Text received here; identity and completeness may be uncertain."
        local content=SC.Terminal.wrap(saved.text.."\n"..observation,w:columns()) local visible=math.max(1,math.floor((buttonTop-y)/row))
        w.radioReadOffset=math.min(w.radioReadOffset or 0,math.max(0,#content-visible))
        for i=w.radioReadOffset+1,math.min(#content,w.radioReadOffset+visible) do text(content[i],left,y) y=y+row end
    else
        local message=w.radioNotice or snap.notice or "Signal activity; this display is not an audio frequency measurement."
        if snap.scan then message=snap.notice.." "..snap.scan.index.."/"..snap.scan.count end
        if w.radioPage=="notebook" then message=#snap.memory.log==0 and "Nothing recorded here yet. Entries contain received text and game time." or "Choose a reception to read. Recordings are marked separately."
        elseif w.radioPage=="heard" then message="Only frequencies actually received by this PC are listed."
        elseif w.radioPage=="presets" then message="Presets belong to the mounted handset. Type: save this channel as Weather" end
        lines(message,y,buttonTop)
    end
    for _,box in ipairs(boxes) do
        w:drawRectBorder(box.x,box.y,box.width,box.height,.6,title[2],title[3],title[4])
        if w.focusMode=="menu" and w.menuSelection==box.index then w:drawRect(box.x,box.y,box.width,box.height,.10,title[2],title[3],title[4]) end
        local label="["..box.index.."] "..box.option.label
        local limit=math.floor(box.width/w.charWidth)-1
        if #label>limit then label=label:sub(1,math.max(1,limit-3)).."..." end
        text(label,box.x+2,box.y+1,title)
    end
end
return UI
