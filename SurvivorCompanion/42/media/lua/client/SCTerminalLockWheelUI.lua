-- SPDX-License-Identifier: MIT
-- Rings and glyphs remain live vectors; only the hub and handbook are bitmaps.
SurvivorCompanion=SurvivorCompanion or {}
local SC=SurvivorCompanion
local UI={} SC.TerminalLockWheelUI=UI
function UI.drawWheel(w,box)
    local c=w.colors.title local wheel=w.system.lock.wheel local data=SC.TerminalLockWheelData
    local radius=math.min(box.width/2,box.height/2-w.rowHeight*.8)
    if radius<55 then return false end
    local cx,cy=box.x+box.width/2,box.y+box.height/2-w.rowHeight*.4
    local function line(x1,y1,x2,y2,alpha)
        if w.javaObject and Texture and Texture.getWhite then
            w.javaObject:DrawLine(Texture.getWhite(),x1,y1,x2,y2,1,c[2],c[3],c[4],alpha or .8)
        end
    end
    local function point(index,r) local angle=index*math.pi*2/26-math.pi/2 return cx+math.cos(angle)*r,cy+math.sin(angle)*r end
    local function circle(r)
        for i=1,64 do
            local a,b=(i-1)*math.pi/32,i*math.pi/32
            line(cx+math.cos(a)*r,cy+math.sin(a)*r,cx+math.cos(b)*r,cy+math.sin(b)*r,.55)
        end
    end
    local zoom=(w.textZoom or 1)*.75 local size=w.rowHeight*.75
    local function glyph(text,x,y)
        pcall(w.drawTextZoomed,w,text,x-w.charWidth*.28,y-size/2,zoom,c[2],c[3],c[4],1,w.font)
    end
    circle(radius*.90) circle(radius*.72)
    for index=0,25 do
        local x,y=point(index,radius) glyph(data.outer:sub(index+1,index+1),x,y)
        x,y=point(index+wheel.rotation,radius*.63) glyph(data.inner:sub(index+1,index+1),x,y)
    end
    for index,marker in ipairs(data.markers) do
        local x,y=point(marker.position+wheel.rotation,radius*.82) local d=math.max(4,radius*.035)
        if index==1 then line(x,y-d,x+d,y) line(x+d,y,x,y+d) line(x,y+d,x-d,y) line(x-d,y,x,y-d)
        elseif index==2 then
            for j=1,12 do local a,b=(j-1)*math.pi/6,j*math.pi/6 line(x+math.cos(a)*d,y+math.sin(a)*d,x+math.cos(b)*d,y+math.sin(b)*d) end
        elseif index==3 then line(x,y-d,x+d,y+d) line(x+d,y+d,x-d,y+d) line(x-d,y+d,x,y-d)
        else line(x-d,y-d,x+d,y-d) line(x+d,y-d,x+d,y+d) line(x+d,y+d,x-d,y+d) line(x-d,y+d,x-d,y-d) end
    end
    local challenge=SC.TerminalLockWheel.challenge(w.system)
    for index,position in ipairs(data.windows) do
        local x,y=point(position,radius*.63) local d=math.max(size*.6,9)
        local highlighted=SC.Terminal.electricalSkill(w.player)>=3 and wheel.correct==0 and index==challenge.window
        w:drawRectBorder(x-d,y-d,d*2,d*2,highlighted and 1 or .5,c[2],c[3],c[4])
        local tx,ty=point(position,radius*.40) glyph(tostring(index),tx,ty)
        w.securityHits[#w.securityHits+1]={x=x-d,y=y-d,width=d*2,height=d*2,
            value="answer "..SC.TerminalLockWheel.read(wheel.rotation,index)}
    end
    SC.TerminalLockUI.art(w,"WheelCentre",{x=cx-radius*.38,y=cy-radius*.38,width=radius*.76,height=radius*.76})
    local y=cy+radius+w.rowHeight*.15
    for _,button in ipairs({{x=box.x,label="< TURN",value="left"},{x=box.x+box.width*.6,label="TURN >",value="right"}}) do
        w:drawText(button.label,button.x,y,c[2],c[3],c[4],1,w.font)
        w.securityHits[#w.securityHits+1]={x=button.x,y=y,width=box.width*.4,height=w.rowHeight,value=button.value}
    end
    w.lockWheelGeometry={x=box.x,y=box.y,width=box.width,height=box.height}
    return true
end
function UI.draw(w,now)
    local beside=w:columns()>=65 and w:visibleRows()>=8
    local lockUI=SC.TerminalLockUI
    local largeWheel=beside and w.lockManualPage==5
    local textShare=largeWheel and .52 or .58
    w.lockPanelVisible=math.max(1,w:visibleRows()-(largeWheel and #lockUI.footer(w) or math.ceil(#lockUI.footer(w)/2))-1)
    local compactWheel=not beside and w.lockManualPage==5
    if compactWheel then w.lockPanelVisible=math.max(1,w.lockPanelVisible-2) end
    local lines,art=SC.TerminalLockWheel.manualLines(w)
    lockUI.rows(w,lines,now,beside and math.floor(w:columns()*textShare) or nil,beside and w:transcriptWidth()*textShare or nil)
    if beside then
        local box={x=w.layout.left+w:transcriptWidth()*(largeWheel and .58 or .62),y=w:viewTop()+w.rowHeight*.25,
            width=w:transcriptWidth()*(largeWheel and .42 or .38),height=((largeWheel and w:visibleRows() or w.lockPanelVisible)-.5)*w.rowHeight}
        if w.lockManualPage==5 then UI.drawWheel(w,box) elseif art then lockUI.art(w,art,box) end
    end
    local y=w:viewTop()+w.lockPanelVisible*w.rowHeight
    local controls={not largeWheel and w:columns()>=43 and "[1] Previous  [2] Next  [3] Back  [4] Wheel" or "[1]Prev [2]Next [3]Back [4]Wheel"}
    if compactWheel then
        local values={}
        for i=1,3 do values[#values+1]="["..(i+6).."] "..i.."="..SC.TerminalLockWheel.read(w.system.lock.wheel.rotation,i) end
        controls={"[5] < TURN    [6] TURN >",table.concat(values,"  "),controls[1]}
    end
    for _,control in ipairs(controls) do
        local row=lockUI.wrapped(w,{control})[1]
        w:drawRow(control,y,"system")
        for _,run in ipairs(w:securityRowRuns(row)) do
            if run.span then w.securityHits[#w.securityHits+1]={x=w.layout.left+run.x,y=y,width=run.width,value=run.span.value} end
        end
        y=y+w.rowHeight
    end
    lockUI.drawFooter(w,largeWheel and w:transcriptWidth()*textShare or nil) w.lockPanelVisible=nil
    return true
end
return UI
