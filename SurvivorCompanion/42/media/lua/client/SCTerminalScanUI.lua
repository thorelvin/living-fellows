-- SPDX-License-Identifier: MIT
-- Survey display: update samples the world; draw consumes plain cached data.
SurvivorCompanion=SurvivorCompanion or {}
local SC=SurvivorCompanion
local UI={}
SC.TerminalScanUI=UI
local function D() return SC.BuildingScan end
local function B() return SC.BuildingControls end
local function nowMs() return SC.ControlUtil.now() end
local function mod(v,n) return v-math.floor(v/n)*n end -- Kahlua signed remainder
local function floorName(z) return z==nil and "--" or z<0 and "B"..(-z) or "F"..z end
local kinds={door="DOOR",shutter="SHUTTER",light="LIGHT",generator="GEN",cabinet="CABINET",
    fridge="FRIDGE",tv="TV",radio="RADIO",computer="PC",alarm="ALARM"}
local function option(label,action,value,key)
    return {label=label,scanAction=action,scanValue=value,key=key or action}
end
local function clip(w,text,width)
    text=tostring(text or "")
    local manager=type(getTextManager)=="function" and getTextManager() or nil
    local function fits(value)
        local pixels=SC.ControlUtil.call(manager,"MeasureStringX",w.font,value)
        return (tonumber(pixels) and pixels*(w.textZoom or 1) or #value*w.charWidth)<=math.max(1,width-4)
    end
    if fits(text) then return text end
    local low,high=0,#text
    while low<high do
        local middle=math.floor((low+high+1)/2)
        if fits(text:sub(1,middle).."...") then low=middle else high=middle-1 end
    end
    return low>0 and text:sub(1,low).."..." or ""
end
function UI.active(w)
    return w and not w.closed and w.system and not w.system.locked and w.scanPage~=nil
end
function UI.notice(w,text) w.scanNotice=tostring(text or "") w.scanSampleAt=nil end
function UI.layout(w)
    local left,right,top,bottom=w.layout.left,w.layout.right,w:viewTop(),w:viewBottom()
    local row,cw=w.rowHeight,w.charWidth
    local rows=math.max(1,math.floor((bottom-top)/row))
    local columns=math.max(1,math.floor((right-left)/cw))
    local compact=rows<6 or columns<48
    local footer=bottom-row
    local rain=not compact and columns>=48 and cw*1.5 or 0
    local split=compact and left or left+rain+(right-left-rain)*0.45
    local listX=compact and left or split+cw
    local capacity=math.max(1,math.min(5,rows-2))
    return {left=left,right=right,top=top,bottom=bottom,row=row,cw=cw,rows=rows,columns=columns,
        compact=compact,footer=footer,contentTop=top+row,contentBottom=footer,
        rain=rain,split=split,listX=listX,listWidth=right-listX,capacity=capacity}
end
local function selectedKey(w)
    local buttons=w.scanSnapshot and w.scanSnapshot.buttons or {}
    local selected=buttons[w.menuSelection or 1]
    if selected and w.scanLastSelection~=w.menuSelection then
        w.scanUserSelected=true w.scanSelectedKey=selected.key
    end
    return w.scanSelectedKey
end
local function valid(w)
    local panel,reason=B().panel(w.object,false)
    if not panel or not B().connected(w.object,panel) then return nil,reason or "Connect this computer at its current location first." end
    return panel
end
function UI.open(w,start)
    local panel,reason=valid(w)
    if not panel then
        w.menuPage="services" w:startReply({lines={reason},thinkMs=0}) return false,reason
    end
    if start then
        local okay,why=B().startScan(w.object,w.player)
        if not okay then w:startReply({lines={why},thinkMs=0}) return false,why end
    end
    w.scanPage=start and "scan" or "equipment"
    w.menuPage,w.gridPage,w.radioPage=nil,nil,nil
    w.scanOffset,w.scanSelectedKey,w.scanUserSelected=0,nil,false
    w.scanSampleAt,w.menuSelection,w.scanLastSelection=nil,1,1
    w.scanNotice=nil w:setFocusMode("menu") UI.update(w,nowMs())
    return true
end
function UI.back(w)
    if w.requestTicket then w:cancelRequest() end
    w.scanPage,w.scanReturn,w.menuPage=nil,nil,"services"
    w.menuSelection=1 w:setFocusMode("menu")
end
function UI.returnDevice(w)
    local saved=w.scanReturn
    if not saved then return false end
    w.scanReturn=nil w.scanPage=saved.page or "equipment" w.menuPage=nil
    w.scanOffset,w.scanSelectedKey,w.scanUserSelected=saved.offset,saved.key,true
    w.scanSampleAt=nil w:setFocusMode("menu") UI.update(w,nowMs())
    return true
end
function UI.options(w) return not w.requestTicket and w.scanSnapshot and w.scanSnapshot.buttons or {} end
local function statusLabel(row,status,object)
    if row.readonly then return row.kind=="computer" and row.x==object.x and row.y==object.y and row.z==object.z and "THIS PC" or "NO CONTROL" end
    return tostring(status or "..."):match("^[^;]+") or "..."
end
local function rowText(w,row,index,width,status,object)
    local kind=kinds[row.kind] or string.upper(row.kind or "DEVICE")
    local tail=floorName(row.z).." "..statusLabel(row,status,object)
    local label=row.named and row.label or row.room or row.label or "Unknown"
    local prefix="["..index.."] "..kind.." "
    local tailWidth=(#tail+1)*w.charWidth
    local room=clip(w,label,width-#prefix*w.charWidth-tailWidth)
    if room=="" then return clip(w,prefix..tail,width) end
    return clip(w,prefix..room.." "..tail..(row.new and " *" or ""),width)
end
local function report(w,result)
    local pools=SC.TerminalLines.BUILDING_SCAN or {}
    local key
    if result.cappedControls or result.cappedFinds then key="limited"
    elseif result.outOfRange>0 then key="partial"
    elseif result.controls+result.finds==0 then key="empty" else key="complete" end
    local pool=pools[key] or {"Survey finished: {controls} controls, {finds} read-only finds, {floors} floors."}
    local line=pool[mod(result.generation-1,#pool)+1]
    local fields={controls=result.controls,finds=result.finds,floors=#result.floors,outOfRange=result.outOfRange}
    line=line:gsub("{(%w+)}",function(name) return tostring(fields[name] or "?") end)
    w:print(line,"emma") UI.notice(w,line)
    SC.Terminal.playFeedbackSound("LFTerminalScanDone")
end
function UI.update(w,now)
    if not D() then return end
    D().observeWindow(w,now)
    if w.closed or not w.system or w.system.locked then return end
    if w.scanSampleAt and now>=w.scanSampleAt and now-w.scanSampleAt<200 then return end
    w.scanSampleAt=now
    local state=B().scanState(w.object)
    w.scanHint=state and state.status=="running" and ("SCAN "..math.floor(state.percent).."%") or nil
    local completed=D().takeResult(w.object)
    if completed then report(w,completed) end
    if state and state.status=="running" then
        if w.scanSoundGeneration~=state.generation then w.scanSoundGeneration=state.generation w.scanSoundCount=state.newCount end
        if state.newCount>(w.scanSoundCount or 0) and now-(w.scanBlipAt or -10000)>=250 then
            SC.Terminal.playFeedbackSound("LFTerminalScanBlip") w.scanBlipAt=now w.scanSoundCount=state.newCount
        end
        if UI.active(w) then
            local turn=math.floor(now/3000)
            if w.scanPingTurn~=turn then SC.Terminal.playFeedbackSound("LFTerminalScanPing") w.scanPingTurn=turn end
        end
    end
    if not UI.active(w) then return end
    local panel,reason=valid(w)
    if not panel then UI.back(w) w:startReply({lines={reason},thinkMs=0}) return end
    local key=selectedKey(w)
    local geometry=UI.layout(w)
    local rows=D().rows(w.object,w.scanPage=="scan")
    local offset=math.max(0,tonumber(w.scanOffset) or 0)
    if not w.scanUserSelected and state and state.status=="running" and #rows>0 then
        offset=math.floor((#rows-1)/geometry.capacity)*geometry.capacity
        key="row:"..rows[#rows].id
    elseif key then
        for i,row in ipairs(rows) do if key=="row:"..row.id then offset=math.floor((i-1)/geometry.capacity)*geometry.capacity break end end
    end
    offset=math.min(offset,math.max(0,math.floor(math.max(0,#rows-1)/geometry.capacity)*geometry.capacity))
    w.scanOffset=offset
    local object={}
    object.x,object.y,object.z=SC.ControlUtil.position(w.object)
    local buttons={}
    for i=offset+1,math.min(#rows,offset+geometry.capacity) do
        local row=rows[i]
        local button=option(row.label or row.kind,"row",row,"row:"..row.id)
        button.row=row buttons[#buttons+1]=button
    end
    local dataCount=#buttons
    if #rows>geometry.capacity then buttons[#buttons+1]=option(geometry.compact and ">" or "More","more") end
    local floors=state and state.floors or panel.lastScan and panel.lastScan.floors or {}
    if #floors>1 and #buttons<7 then buttons[#buttons+1]=option(geometry.compact and "F" or "Floor","floor") end
    local running=state and state.status=="running"
    buttons[#buttons+1]=option(running and (geometry.compact and "X" or "Abort scan")
        or geometry.compact and "Go" or state and state.status=="paused" and "Resume" or "Discover",running and "abort" or "start")
    buttons[#buttons+1]=option(geometry.compact and "<" or "Back","back")
    local chosen=1
    for i,button in ipairs(buttons) do if button.key==key then chosen=i break end end
    w.menuSelection,w.scanLastSelection,w.scanSelectedKey=chosen,chosen,buttons[chosen].key
    if not w.scanFloorManual then
        local row=buttons[chosen].row
        w.scanFloor=row and row.z or state and state.lastProbe and state.lastProbe.z or floors[1] and floors[1].z or 0
    end
    local statuses=w.scanStatuses or {} w.scanStatuses=statuses
    if not w.scanStatusAt or now<w.scanStatusAt or now-w.scanStatusAt>=1000 then
        w.scanStatusAt=now
        for i=1,dataCount do local row=buttons[i].row
            if not row.readonly then statuses[row.id]=B().status(row) end
        end
    end
    local texts={}
    for i=1,dataCount do texts[i]=rowText(w,buttons[i].row,i,geometry.listWidth,statuses[buttons[i].row.id],object) end
    local footerWidth=(geometry.right-geometry.left)/math.max(1,#buttons-dataCount)
    local hits={}
    for i,button in ipairs(buttons) do
        if i<=dataCount then hits[#hits+1]={x=geometry.listX,y=geometry.contentTop+(i-1)*geometry.row,width=geometry.listWidth,height=geometry.row,index=i}
        else
            local x=geometry.left+(i-dataCount-1)*footerWidth
            hits[#hits+1]={x=x,y=geometry.footer,width=footerWidth,height=geometry.row,index=i}
            texts[i]=clip(w,"["..i.."] "..button.label,footerWidth)
        end
    end
    local label=state and (state.cappedControls or state.cappedFinds) and "LIMIT REACHED"
        or running and "DISCOVERING" or state and string.upper(state.status) or "EQUIPMENT"
    local controls,finds=0,0
    if state then controls,finds=state.controls,state.finds
    else for _,row in ipairs(rows) do if row.readonly then finds=finds+1 else controls=controls+1 end end end
    local header=geometry.compact and (label..(state and " "..math.floor(state.percent).."%" or "").." "..controls.."C/"..finds.."R")
        or label..(state and " "..math.floor(state.percent).."%" or "").." / "..controls.." CONTROLS / "..finds.." READ-ONLY / "..#floors.." FLOORS"
    local probe=state and state.lastProbe
    local probeText=probe and string.format("%04X %s %d:%d PROBE",mod(state.processed,65536),floorName(probe.z),probe.x,probe.y) or "Choose Discover to survey loaded equipment."
    if state and state.lastFind and now-state.lastFind.at<700 then
        local found=state.lastFind probeText="ACK "..(kinds[found.kind] or found.kind).." "..(found.room or "")
    end
    local blips={}
    local bounds=state and state.bounds
    if bounds then
        local cx,cy=(bounds.x+bounds.x2+1)/2,(bounds.y+bounds.y2+1)/2
        local span=math.max(bounds.x2-bounds.x+1,bounds.y2-bounds.y+1)/2
        for _,row in ipairs(rows) do if row.z==w.scanFloor and row.x and row.y then
            local x,y=(row.x+.5-cx)/span,(row.y+.5-cy)/span
            blips[#blips+1]={x=x,y=y,angle=math.atan2(y,x),readonly=row.readonly}
        end end
    end
    w.scanSnapshot={geometry=geometry,buttons=buttons,texts=texts,hits=hits,dataCount=dataCount,
        state=state,floors=floors,floor=w.scanFloor,blips=blips,header=clip(w,header,geometry.right-geometry.left),
        probe=clip(w,probeText,geometry.right-geometry.listX),notice=clip(w,w.scanNotice or "",geometry.listWidth),
        empty=#rows==0 and "No equipment recorded. Discover building to begin." or nil}
    if w.requestTicket then
        local prompt=w.scanPrompt and w.scanPrompt.ticket==w.requestTicket and w.scanPrompt.text or "Confirm Y/N."
        w.scanSnapshot.promptRows=SC.Terminal.wrap(prompt,geometry.columns)
    end
end
local function act(w,action,value)
    if action=="back" then UI.back(w)
    elseif action=="start" then
        local okay,why=B().startScan(w.object,w.player)
        UI.notice(w,why) if okay then w.scanPage="scan" w.scanUserSelected=false end
    elseif action=="abort" then local _,why=B().abortScan(w.object) UI.notice(w,why)
    elseif action=="more" then
        local s=w.scanSnapshot local rows=D().rows(w.object,w.scanPage=="scan")
        w.scanOffset=(w.scanOffset or 0)+s.geometry.capacity
        if w.scanOffset>=#rows then w.scanOffset=0 end
        w.scanSelectedKey=nil w.scanUserSelected=true
    elseif action=="floor" then
        local floors=w.scanSnapshot.floors
        for i,floor in ipairs(floors) do if floor.z==w.scanFloor then w.scanFloor=floors[mod(i,#floors)+1].z break end end
        w.scanFloorManual=true
    elseif action=="row" then
        w.scanSelectedKey="row:"..value.id w.scanUserSelected=true
        if value.readonly then UI.notice(w,(kinds[value.kind] or value.kind)..", "..(value.room or "Building")..", "..floorName(value.z)
            ..": no control. "..(value.kind=="alarm" and "Use Alarms and speakers." or "Check it in person."))
        else
            w.scanReturn={page=w.scanPage,offset=w.scanOffset,key=w.scanSelectedKey}
            w.scanPage=nil
            SC.TerminalServices.input(w,"",{serviceAction="device",serviceValue=value.id})
        end
    else return false end
    w.scanSampleAt=nil
    if UI.active(w) then UI.update(w,nowMs()) end
    return true
end
function UI.input(w,raw,chosen)
    if not UI.active(w) then return false end
    if chosen and chosen.scanAction then return act(w,chosen.scanAction,chosen.scanValue) end
    local lower=string.lower(tostring(raw or "")):match("^%s*(.-)%s*$")
    if lower=="abort scan" or lower=="stop scan" then return act(w,"abort") end
    if lower=="back" or lower=="exit" then return act(w,"back") end
    if lower=="discover building" or lower=="scan building" or lower=="scan the building" or lower=="find devices" then return act(w,"start") end
    if w.focusMode=="chat" and lower~="" then UI.back(w) w:setFocusMode("chat") end
    return false
end
function UI.scroll(w,delta)
    if not UI.active(w) then return false end
    if w.requestTicket then return true end
    local s=w.scanSnapshot
    if not s then return true end
    if delta>0 then act(w,"more") else
        w.scanOffset=math.max(0,(w.scanOffset or 0)-s.geometry.capacity)
        w.scanSelectedKey=nil w.scanUserSelected=true w.scanSampleAt=nil UI.update(w,nowMs())
    end
    return true
end
function UI.click(w,x,y)
    if not UI.active(w) then return false end
    if w.requestTicket then return true end
    for _,hit in ipairs(w.scanSnapshot and w.scanSnapshot.hits or {}) do
        if x>=hit.x and x<hit.x+hit.width and y>=hit.y and y<hit.y+hit.height then
            w:playClickSound() w.menuSelection=hit.index w.scanLastSelection=hit.index
            w.scanSelectedKey=w.scanSnapshot.buttons[hit.index].key w.scanUserSelected=true
            return act(w,w.scanSnapshot.buttons[hit.index].scanAction,w.scanSnapshot.buttons[hit.index].scanValue)
        end
    end
    return true
end
local circle={}
for i=0,36 do local angle=i/36*math.pi*2 circle[i+1]={math.cos(angle),math.sin(angle)} end
function UI.draw(w,now)
    local s=w.scanSnapshot if not s then return end
    local g=s.geometry local ink,title=w.colors.emma,w.colors.title
    local function text(value,x,y,color,alpha)
        color=color or ink w:drawText(value,x,y,color[2],color[3],color[4],alpha or 1,w.font)
    end
    local function line(x1,y1,x2,y2,alpha,color,thickness)
        color=color or ink
        if w.javaObject and Texture and Texture.getWhite then
            w.javaObject:DrawLine(Texture.getWhite(),x1,y1,x2,y2,thickness or 1,color[2],color[3],color[4],alpha)
        end
    end
    w:setStencilRect(g.left,g.top,g.right-g.left,g.bottom-g.top)
    if w.requestTicket then
        for i,value in ipairs(s.promptRows or {"Confirm Y/N."}) do
            local y=g.top+(i-1)*g.row
            if y+g.row<=g.bottom then text(value,g.left,y,title) end
        end
        w:clearStencilRect() return
    end
    text(s.header,g.left,g.top,title)
    for i,hit in ipairs(s.hits) do
        if w.focusMode=="menu" and hit.index==w.menuSelection then
            w:drawRectBorder(hit.x,hit.y+1,hit.width-2,hit.height-2,.8,title[2],title[3],title[4])
        end
        local readonly=i<=s.dataCount and s.buttons[i].row.readonly
        text(s.texts[i],hit.x+2,hit.y,readonly and ink or title,readonly and .65 or 1)
    end
    if s.empty and s.dataCount==0 then text(s.empty,g.listX,g.contentTop,ink,.65) end
    if not g.compact then
        line(g.split,g.contentTop,g.split,g.footer,.35)
        local floors=s.floors
        local centre=1 for i,floor in ipairs(floors) do if floor.z==s.floor then centre=i end end
        local first=math.max(1,math.min(centre-1,#floors-2))
        local shown=math.min(3,#floors)
        local floorTop=g.contentBottom-(shown+(#floors>3 and 1 or 0))*g.row
        for index=0,shown-1 do
            local floor=floors[first+index]
            local y=floorTop+index*g.row
            local percent=math.floor(floor.done/math.max(1,floor.total)*100)
            local label=floorName(floor.z)
            local extra=floor.outOfRange>0 and ("!"..math.ceil(floor.outOfRange/floor.total*100).."% OUT") or percent.."%"
            text(label,g.left+g.rain,y,floor.z==s.floor and title or ink)
            local x=g.left+g.rain+g.cw*3
            local width=math.max(1,g.split-x-g.cw*(#extra+2))
            w:drawRect(x,y+g.row*.35,width,g.row*.25,.15,ink[2],ink[3],ink[4])
            w:drawRect(x,y+g.row*.35,width*percent/100,g.row*.25,.75,title[2],title[3],title[4])
            text(extra,x+width+g.cw*.5,y,ink)
        end
        if #floors>3 then text("+"..(#floors-3).." MORE",g.left+g.rain,floorTop+shown*g.row,ink,.65) end
        local left=g.left+g.rain
        local radius=math.min((g.split-left)*.45,(floorTop-g.contentTop)*.46)
        if radius>=g.row*1.6 then
            local cx,cy=left+(g.split-left)/2,g.contentTop+(floorTop-g.contentTop)/2
            for ring=1,3 do
                local r=radius*ring/3
                for i=2,#circle do line(cx+circle[i-1][1]*r,cy+circle[i-1][2]*r,cx+circle[i][1]*r,cy+circle[i][2]*r,ring==3 and .65 or .22) end
            end
            line(cx-radius,cy,cx+radius,cy,.18) line(cx,cy-radius,cx,cy+radius,.18)
            local running=s.state and s.state.status=="running"
            local angle=(running and now or s.state and s.state.generation*1000 or 0)/3000*math.pi*2
            if running then for trail=0,21 do
                local a=angle-trail*.045
                line(cx,cy,cx+math.cos(a)*radius,cy+math.sin(a)*radius,(trail==0 and .85 or .3)*(1-trail/22),nil,trail==0 and 2 or 1)
            end end
            for _,blip in ipairs(s.blips) do
                local brightness=running and math.max(.2,1-mod(angle-blip.angle,math.pi*2)/3) or .8
                w:drawRect(cx+blip.x*radius-2,cy+blip.y*radius-2,4,4,brightness,title[2],title[3],title[4])
            end
        elseif floorTop>=g.contentTop+g.row then
            text(({"|","/","-","\\"})[mod(math.floor(now/200),4)+1],left,g.contentTop,title)
        end
        local spare=g.contentTop+s.dataCount*g.row
        if spare+g.row<=g.contentBottom then text(s.notice~="" and s.notice or s.probe,g.listX,spare,ink,.6) end
        local glyphs="0123456789ABCDEF#/\\"
        local rows=math.floor((g.footer-g.contentTop)/g.row)
        local head=mod(math.floor(now/100),rows+6)
        for i=0,rows-1 do
            local distance=mod(head-i,rows+6)
            if distance<8 then local n=mod(i*7+math.floor(now/160),#glyphs)+1
                text(glyphs:sub(n,n),g.left,g.contentTop+i*g.row,distance==0 and title or ink,(1-distance/8)*.5)
            end
        end
    end
    w:clearStencilRect()
end
return UI
