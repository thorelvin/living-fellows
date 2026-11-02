-- SPDX-License-Identifier: MIT
-- One fixed fictional county transmitter; receipts come from native reception.
SurvivorCompanion=SurvivorCompanion or {}
local SC=SurvivorCompanion local R={} SC.TerminalLockRadio=R
R.CHANNEL=96400 R.TOWER={x=12000,y=9000,range=100000}
local broadcast,expected,lastPoll=nil,{},0
local function U() return SC.ControlUtil end
function R.code(seed,serial)
    local pick=SC.TerminalSystem.random(seed+tonumber(serial)) pick(2147483646)
    return string.format("%06d",pick(1000000)-1)
end
function R.night(hours,tod) return math.floor((hours-tod+.001)/24)-(tod<3 and 1 or 0) end
local function clock()
    local time=type(getGameTime)=="function" and getGameTime()
    local hours=U().hours() local tod=tonumber(U().call(time,"getTimeOfDay"))
    if hours and tod then return R.night(hours,tod),hours,tod end
end
function R.normalize(ledger)
    local V=SC.TerminalLockState local pending,heard={},{}
    for i,row in ipairs(type(ledger.pending)=="table" and ledger.pending or {}) do
        if i>16 then break end
        if type(row)=="table" and V.text(row.serial,8) and row.serial:match("^%d%d%d%d%d%d%d%d$")
            and V.text(row.identity,96) and V.number(row.seed,1,2147483646) and V.number(row.queuedNight,-1000000,1000000) then
            local duplicate=false for _,p in ipairs(pending) do if p.serial==row.serial or p.identity==row.identity then duplicate=true end end
            if not duplicate then pending[#pending+1]={serial=row.serial,identity=row.identity,seed=row.seed,queuedNight=math.floor(row.queuedNight)} end
        end
    end
    local inspected=0
    for serial,row in pairs(type(ledger.heard)=="table" and ledger.heard or {}) do
        inspected=inspected+1 if inspected>4096 then break end
        if V.text(serial,8) and serial:match("^%d%d%d%d%d%d%d%d$") and type(row)=="table" and V.text(row.identity,96) and V.number(row.at,0,100000000) then
            heard[serial]={identity=row.identity,at=row.at}
        end
    end
    ledger.pending,ledger.heard=pending,heard
    ledger.lastNight=V.number(ledger.lastNight,-1000000,1000000)
    ledger.radioHeardCount=math.floor(V.number(ledger.radioHeardCount,0,10000000) or 0)
    ledger.radioNamed=ledger.radioNamed==true
end
function R.register(state)
    local ledger=SC.TerminalLocks.ledger() local night=clock() if not ledger or not night then return false end
    local lock=state.lock
    if ledger.lastNight==nil or #ledger.pending==0 and not broadcast then ledger.lastNight=night end
    if lock.serial and (lock.heard or ledger.heard[lock.serial] and ledger.heard[lock.serial].identity==state.identity) then lock.heard=true return true end
    for _,row in ipairs(ledger.pending) do if row.identity==state.identity then lock.serial=row.serial return true end end
    if #ledger.pending>=16 then return false end
    local serial=lock.serial or string.format("%08d",10000000+state.seed%90000000)
    for _=1,81 do
        local collision=false
        for _,row in ipairs(ledger.pending) do if row.serial==serial and row.identity~=state.identity then collision=true end end
        local receipt=ledger.heard[serial] if receipt and receipt.identity~=state.identity then collision=true end
        if not collision then break end
        serial=string.format("%08d",10000000+(tonumber(serial)-10000000+7919)%90000000)
    end
    lock.serial=serial
    ledger.pending[#ledger.pending+1]={serial=serial,seed=state.seed,identity=state.identity,queuedNight=night}
    return true
end
function R.heard(state)
    if not state.lock.serial then return false end
    if state.lock.heard then return true end
    local ledger=SC.TerminalLocks.ledger() local row=ledger and ledger.heard[state.lock.serial]
    return row and row.identity==state.identity or false
end
local function audible(player,device,x,y)
    if not player or U().call(player,"isDead")==true then return false end
    local equipped=U().call(player,"getEquipedRadio")
    local radio=device or equipped
    if not radio then return false end
    local data=U().call(radio,"getDeviceData")
    if not data or U().call(data,"getIsTelevision")==true or U().call(data,"getChannel")~=R.CHANNEL
        or U().call(data,"getIsTurnedOn")~=true or (tonumber(U().call(data,"getDeviceVolume")) or 0)<=0
        or U().call(data,"isPlayingMedia")==true then return false end
    if radio==equipped then
        return U().owns(player,radio) and (radio==U().call(player,"getPrimaryHandItem") or radio==U().call(player,"getSecondaryHandItem") or radio==U().call(player,"getClothingItem_Back"))
            and U().call(data,"getHasBattery")==true and (tonumber(U().call(data,"getPower")) or 0)>0
    end
    return tonumber(x) and tonumber(y) and U().present(radio) and U().near(player,radio,math.min(20,(tonumber(U().call(data,"getDeviceVolumeRange")) or 10)))
end
function R.onDeviceText(guid,code,x,y,z,message,device)
    local item=expected[tostring(guid)] local now=U().now()
    if not item or now>item.expires or tostring(code)~="LF_LOCK_ESCROW" or tostring(message)~=item.text then return end
    local player=type(getSpecificPlayer)=="function" and getSpecificPlayer(0)
    if not audible(player,device,x,y) then return end
    local ledger=SC.TerminalLocks.ledger() if not ledger then return end
    if item.key and not ledger.heard[item.row.serial] then
        local count,oldest,at=0,nil,math.huge
        for serial,row in pairs(ledger.heard) do count=count+1 if row.at<at then oldest,at=serial,row.at end end
        if count>=4096 then ledger.heard[oldest]=nil end
        ledger.heard[item.row.serial]={identity=item.row.identity,at=U().hours() or 0}
        local window=SC.Terminal.window
        if window and window.system and window.system.identity==item.row.identity and window.system.lock
            and window.system.lock.serial==item.row.serial and SC.Terminal.ownsState(window.object,window.system) then window.system.lock.heard=true end
        for i=#ledger.pending,1,-1 do if ledger.pending[i].identity==item.row.identity then table.remove(ledger.pending,i) end end
        ledger.radioHeardCount=ledger.radioHeardCount+1
        item.call.heard=true
        if ledger.radioHeardCount==3 and not ledger.radioNamed then item.call.name=SC.TerminalLockCrew.name(player) end
        SC.Terminal.playFeedbackSound("LFNumbersTune")
        SC.TerminalLockCrew.react({player=player,system={seed=item.row.seed,lock={reactions={}}}},"radio",100)
    end
end
local function transmit(call,line,now,night)
    local row=call.row local key=R.code(row.seed,row.serial) local grouped=key:sub(1,3).." "..key:sub(4)
    local text=line==1 and "COUNTY KEY ESCROW. SERIAL "..row.serial..". STAND BY."
        or line<=3 and "SERIAL "..row.serial..". RECOVERY KEY "..grouped.."."
        or call.name and "GO TO BED, "..string.upper(call.name).."." or "END SERIAL "..row.serial.."."
    local ledger=SC.TerminalLocks.ledger()
    if line==4 and call.name then ledger.radioNamed=true end -- commit before native send
    local guid="LF_LOCKRADIO_"..night.."_"..row.serial.."_"..line
    expected[guid]={text=text,row=row,key=line==2 or line==3,call=call,expires=now+15000}
    local api=type(getZomboidRadio)=="function" and getZomboidRadio()
    if not api then expected[guid]=nil return false end
    local okay=pcall(function() api:SendTransmission(R.TOWER.x,R.TOWER.y,R.CHANNEL,text,guid,"LF_LOCK_ESCROW",.8,1,.8,R.TOWER.range,false) end)
    if not okay then expected[guid]=nil end
    return okay
end
function R.pulse(now)
    local ledger=SC.TerminalLocks.ledger()
    if not ledger or (#ledger.pending==0 and not broadcast) then return end
    now=now or U().now()
    if type(isGamePaused)=="function" and isGamePaused() then if broadcast then broadcast.nextAt=now+math.max(0,broadcast.nextAt-(broadcast.last or now)) broadcast.last=now end return end
    if now>=lastPoll and now-lastPoll<1000 then return end lastPoll=now
    for guid,item in pairs(expected) do if now>item.expires then expected[guid]=nil end end
    local night=clock() if not night then return end
    if not broadcast and ledger.lastNight and night>ledger.lastNight then
        ledger.lastNight=night -- fast-forward schedules one current night, never a backlog
        local kept={}
        for _,row in ipairs(ledger.pending) do
            if night-row.queuedNight<=14 and not ledger.heard[row.serial] then kept[#kept+1]=row end
        end
        ledger.pending=kept
        local calls={}
        for i=1,math.min(3,#kept) do calls[#calls+1]={row=table.remove(ledger.pending,1)} end
        for _,call in ipairs(calls) do ledger.pending[#ledger.pending+1]=call.row end
        if #calls>0 then broadcast={calls=calls,index=1,line=1,nextAt=now,night=night,last=now} end
    end
    if not broadcast then return end
    local b=broadcast b.last=now
    if now<b.nextAt then return end
    local call=b.calls[b.index]
    transmit(call,b.line,now,b.night) b.line=b.line+1 b.nextAt=now+6000
    if b.line>4 then b.line=1 b.index=b.index+1 end
    if b.index>#b.calls then broadcast=nil end
end
function R.lines(w)
    local lock=w.system.lock
    local rows={"COUNTY KEY ESCROW","96.4 MHz / 03:00 NIGHTLY","QUOTE SERIAL "..(lock.serial or "QUEUE FULL - REOPEN TO RETRY"),
        "Listen on a powered, audible radio.","Type its six-digit key here."}
    if U().skill(w.player)>=3 then
        local onAir=false for _,call in ipairs(broadcast and broadcast.calls or {}) do if call.row.serial==lock.serial then onAir=true break end end
        local _,_,tod=clock()
        if R.heard(w.system) then rows[#rows+1]="ELECTRICAL: RECOVERY KEY RECEIVED."
        elseif onAir then rows[#rows+1]="ELECTRICAL: CARRIER ACTIVE. LISTEN NOW."
        elseif tod then rows[#rows+1]=string.format("ELECTRICAL: NEXT CALL IN %.1f HOURS.",(3-tod+24)%24) end
    end
    if lock.codeWrong and R.heard(w.system) then table.insert(rows,4,"RECEIVED KEY: "..R.code(w.system.seed,lock.serial)) end
    if w.securityMessage then rows[#rows+1]=w.securityMessage end
    return rows
end
function R.input(w,raw)
    if raw:match("^%d%d%d%d%d%d$") then
        if R.heard(w.system) and raw==R.code(w.system.seed,w.system.lock.serial) then
            w.system.lock.heard=true w.lockCodeVerified=true SC.TerminalLocks.finishUnlock(w,"radio") w.lockCodeVerified=nil
        else w.system.lock.codeWrong=true SC.TerminalLocks.record(w,raw,"wrong") w.securityMessage="Broadcast key not accepted. Listen for your serial." end
    else w.securityMessage="Tune a radio to 96.4 MHz. Type the key after hearing your serial." end
    return true
end
function R.install()
    if R._listener then return true end
    if not Events or not Events.OnDeviceText then return false,"radio_event_unavailable" end
    R._listener=function(...) return R.onDeviceText(...) end Events.OnDeviceText.Add(R._listener) return true
end
function R.reset() broadcast,expected,lastPoll=nil,{},0 end
function R.remove() if R._listener then Events.OnDeviceText.Remove(R._listener) end R._listener=nil R.reset() end
function R.isInstalled() return R._listener~=nil end
return R
