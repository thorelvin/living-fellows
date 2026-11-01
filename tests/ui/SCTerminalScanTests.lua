-- SPDX-License-Identifier: MIT
-- Real terminal dispatch/rendering with a deterministic survey snapshot.
local SC,T=SurvivorCompanion,TERMINAL_TEST
local UI=SC.TerminalScanUI
local check=T.check
local pc=T.computer(T.square(100,100,0,true))
local player=T.player(101,100,0)
local panel={id="building:test",devices={},finds={}}
local rows,state={},nil
local calls={status=0,snapshot=0,start=0,observe=0}
local sounds={}
SC.GameplayUtil.nowMs=function() return T.now end
SC.Terminal._clock=function() return T.now end
SC.Terminal.playFeedbackSound=function(name) sounds[#sounds+1]={name=name,at=T.now} end
SC.BaseLife={active=function() return nil end,isInside=function() return false end}
SC.BuildingControls={panel=function() return panel end,connected=function() return true end,
    scanState=function() calls.snapshot=calls.snapshot+1 return state end,
    startScan=function() calls.start=calls.start+1 return true,"Started." end,
    abortScan=function() state.status="aborted" return true,"Aborted." end,
    list=function() return {} end,status=function(row) calls.status=calls.status+1 return "Closed" end}
SC.BuildingScan={observeWindow=function() calls.observe=calls.observe+1 end,
    rows=function() return rows end,takeResult=function() local value=T.result T.result=nil return value end}
SC.Terminal.computerState(player,pc).locked=false
check(SC.Terminal.open(player,pc),"survey fixture opens the real terminal")
local w=SC.Terminal.window w:flush()
local realServices=SC.TerminalServices
SC.TerminalServices={input=function(window,raw,chosen)
    window.menuPage="device" window.deviceId=chosen.serviceValue return true
end}
for i=1,12 do rows[i]={id="device"..i,kind=i==1 and "fridge" or "door",room="Long room name that must truncate",x=100+i,y=100,z=i<7 and 0 or 1,readonly=i==1} end
state={generation=1,status="running",percent=25,controls=11,finds=1,newCount=0,processed=20,
    outOfRange=0,floors={{z=0,done=20,total=40,outOfRange=0},{z=1,done=0,total=40,outOfRange=0}},
    bounds={x=94,y=94,x2=112,y2=112},lastProbe={x=100,y=100,z=0}}
check(UI.open(w,false) and calls.start==0,"opening Equipment never starts discovery")
check(w:sidebarWidth()==0 and UI.active(w),"survey occupies the existing screen without sidebar")
w.menuSelection=1 w:navigate(-1)
check(w.menuSelection==#w:menuOptions(),"Up from the first option wraps correctly in Kahlua")
w:navigate(1) check(w.menuSelection==1,"Down from the last option wraps to the first")
w.scanUserSelected=true w.scanSelectedKey="row:device1" w.scanLastSelection=w.menuSelection
w.scanSampleAt=nil UI.update(w,T.now)
check(UI.options(w)[1].row.readonly,"read-only item stays in the shared list")
UI.input(w,"",UI.options(w)[1])
check(UI.active(w) and not w.deviceId,"read-only selection opens no controls")
UI.input(w,"",UI.options(w)[2])
check(w.scanPage==nil and w.deviceId=="device2" and w.scanReturn.key=="row:device2","device opens with return context")
check(UI.returnDevice(w) and UI.active(w) and w.scanSelectedKey=="row:device2","device Back restores row selection")
rows[#rows+1]={id="later",kind="tv",room="Office",x=103,y=101,z=1,readonly=true}
T.now=T.now+200 UI.update(w,T.now)
check(w.scanSelectedKey=="row:device2","arriving rows do not steal selection")
UI.scroll(w,1)
check(w.scanOffset==w.scanSnapshot.geometry.capacity,"wheel advances a page")
UI.scroll(w,-1)
check(w.scanOffset==0,"wheel returns a page")
local hit=w.scanSnapshot.hits[1]
UI.click(w,hit.x+1,hit.y+1)
check(UI.active(w) and w.scanSelectedKey=="row:device1","click uses the visible read-only row")
w.scanSelectedKey="row:device5" w.scanSampleAt=nil UI.update(w,T.now)
for i=1,5 do table.insert(rows,1,{id="prefix"..i,kind="tv",room="Office",readonly=true,z=0}) end
w.scanSampleAt=nil UI.update(w,T.now)
check(w.scanSelectedKey=="row:device5" and w.scanOffset==5,"stable selection follows its row across a page boundary")
for _=1,5 do table.remove(rows,1) end
w.scanSelectedKey="row:device1" w.scanSampleAt=nil UI.update(w,T.now)

local oldTop,oldBottom=w.viewTop,w.viewBottom
local oldLayout,oldZoom=w.layout,w.textZoom
for _,height in ipairs({3,6,10}) do
    for _,color in ipairs({{1,.2,1,.4},{1,.95,.75,.4},{1,.3,.9,.85},{1,.8,.6,1}}) do
        w.colors={emma=color,title=color}
        w.viewTop=function() return 0 end w.viewBottom=function() return height*w.rowHeight end
        w.layout={left=0,right=60*w.charWidth,skin=oldLayout.skin} w.scanSampleAt=nil UI.update(w,T.now)
        local s=w.scanSnapshot
        check(s.geometry.compact==(height==3),"three rows drop radar; larger layouts retain it")
        check(#UI.options(w)<=9,"all actions retain single-digit shortcuts")
        for _,box in ipairs(s.hits) do
            check(box.y>=w.rowHeight and box.y+box.height<=w:viewBottom(),"row and footer stay in content bounds")
        end
        for i=1,s.dataCount do
            check(#s.texts[i]*8*(w.textZoom or 1)<=s.geometry.listWidth,"measured text cannot cross the list boundary")
        end
        local beforeStatus,beforeSnapshot=calls.status,calls.snapshot
        for n=1,60 do UI.draw(w,T.now+n*16) w:menuOptions() end
        check(calls.status==beforeStatus and calls.snapshot==beforeSnapshot,"render and menu queries make no world reads")
        check(T.stencil==nil,"draw always releases its clip")
    end
end
w.viewTop,w.viewBottom,w.layout,w.textZoom=oldTop,oldBottom,oldLayout,oldZoom
local oldFloors,oldDrawText=state.floors,w.drawText
state.floors={}
for z=0,4 do state.floors[#state.floors+1]={z=z,total=40,done=0,outOfRange=0} end
w.viewTop=function() return 0 end w.viewBottom=function() return 6*w.rowHeight end
w.layout={left=0,right=60*w.charWidth,skin=oldLayout.skin}
w.scanSampleAt=nil UI.update(w,T.now)
local spinner=false
w.drawText=function(_,value,x,y)
    if x==w.scanSnapshot.geometry.left+w.scanSnapshot.geometry.rain and y==w.scanSnapshot.geometry.contentTop
        and (value=="|" or value=="/" or value=="-" or value=="\\") then spinner=true end
end
UI.draw(w,T.now)
check(not spinner,"six-row screen with five floors drops spinner before it overlaps the floor bars")
state.floors=oldFloors w.drawText=oldDrawText
w.viewTop,w.viewBottom,w.layout=oldTop,oldBottom,oldLayout
w.scanSampleAt=nil w.scanStatusAt=nil calls.status=0 UI.update(w,T.now)
local visible=0 for _,button in ipairs(w.scanSnapshot.buttons) do if button.row and not button.row.readonly then visible=visible+1 end end
check(calls.status==visible,"status polling touches visible controllable rows only")
local sampled=calls.snapshot
UI.update(w,T.now+199)
check(calls.snapshot==sampled,"snapshots are limited to five per second")
UI.update(w,T.now+200)
check(calls.status==visible,"status remains cached within its one-second interval")
UI.update(w,T.now+1000)
check(calls.status==visible*2,"visible status refreshes once a second")

w.requestTicket={kind="test"}
w:startReply({lines={"Authorize this change? Y/N"},thinkMs=0})
w.scanSampleAt=nil UI.update(w,T.now+1200)
check(#UI.options(w)==0 and w.scanSnapshot.promptRows[1]=="Authorize this change? Y/N","confirmation takes priority over scan controls")
local promptOffset,promptDevice=w.scanOffset,w.deviceId
local hidden=w.scanSnapshot.hits[2]
UI.click(w,hidden.x+1,hidden.y+1) UI.scroll(w,1)
check(w.scanPage~=nil and w.deviceId==promptDevice and w.scanOffset==promptOffset,"confirmation blocks hidden list clicks and paging")
local drawn={} local oldDraw=w.drawText
w.drawText=function(_,value) drawn[#drawn+1]=value end
UI.draw(w,T.now)
check(#drawn==1 and drawn[1]=="Authorize this change? Y/N","scan visuals never overwrite confirmation")
w.drawText=oldDraw w.requestTicket=nil w.scanSampleAt=nil
T.now=T.now+2000 UI.update(w,T.now)
local soundStart=#sounds
for n=1,20 do T.now=T.now+200 state.newCount=n UI.update(w,T.now) end
local lastBlip,blips=nil,0
for i=soundStart+1,#sounds do if sounds[i].name=="LFTerminalScanBlip" then
    check(not lastBlip or sounds[i].at-lastBlip>=250,"discovery blips are throttled to four per second")
    lastBlip=sounds[i].at blips=blips+1
end end
check(blips>0,"new discoveries produce feedback")
state.status="complete" state.done=true state.percent=100 state.finds=1
T.result=state T.now=T.now+200 UI.update(w,T.now)
T.now=T.now+200 UI.update(w,T.now)
local done=0 for _,sound in ipairs(sounds) do if sound.name=="LFTerminalScanDone" then done=done+1 end end
check(done==1,"completion feedback occurs once")
check(w.scanNotice:find("11",1,true) and w.scanNotice:find("1",1,true),"report uses real counts")
state.cappedControls=true w.scanSampleAt=nil UI.update(w,T.now)
check(w.scanSnapshot.header:find("LIMIT",1,true),"limit warning stays visible even with no spare notice row")
state.cappedControls=false
UI.input(w,"scan building")
check(calls.start==1,"typed building scan explicitly starts discovery")
w:setFocusMode("chat")
check(not UI.input(w,"scan radio channels") and not UI.active(w),"radio phrasing passes to ordinary radio dispatch")
state=nil UI.open(w,false)
check(w.scanSnapshot.header:find("2 READ-ONLY",1,true),"saved read-only counts remain correct without a runtime scan after reload")
SC.TerminalServices=realServices
w:close()
print("TERMINAL_SCAN_UI_PASS")
