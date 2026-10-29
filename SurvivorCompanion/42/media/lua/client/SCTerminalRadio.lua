-- SPDX-License-Identifier: MIT
-- LARCH/WAVE: one real handset, bounded event-driven reception, no station
-- catalogue or future scripts used to discover supposedly audible channels.
SurvivorCompanion=SurvivorCompanion or {}
local SC=SurvivorCompanion
SC.TerminalRadio=SC.TerminalRadio or {}
local R=SC.TerminalRadio
R.KEY="LF_LarchWave"
R.MAX_LOG=48 R.MAX_FOUND=32 R.MAX_SCAN=5000 R.STEP=200 R.DWELL=3000
local tracked=setmetatable({}, {__mode="k"})
local owners=setmetatable({}, {__mode="kv"})
local function U() return SC.ControlUtil end
local function call(object,method,...) return U().call(object,method,...) end
local function finite(n) return type(n)=="number" and n==n and math.abs(n)<math.huge end
local function integer(n) return finite(n) and n==math.floor(n) end
local function clean(value,limit)
    return type(value)=="string" and value:gsub("[%c]"," "):gsub("<[^>]*>",""):gsub("%s+"," "):match("^%s*(.-)%s*$"):sub(1,limit) or ""
end
local function frequency(n) return integer(n) and n>0 and n<=2147483647 end
local function reportCopy(report,id)
    if type(report)~="table" then return nil end
    local result={mission=clean(id or report.mission,128),kind=clean(report.kind,24),phase=clean(report.phase,64)}
    if finite(report.at) and report.at>=0 then result.at=report.at end
    for _,key in ipairs({"collected","requested","carried","stored"}) do
        local value=report[key]
        if finite(value) and value>=0 and value<=1000000 then result[key]=value end
    end
    return result
end
function R.format(n) return frequency(n) and string.format("%.3f MHz",n/1000) or "Unknown frequency" end
function R.teamChannel() return SC.ExpeditionPrototype and SC.ExpeditionPrototype.TEAM_RADIO_CHANNEL or 90000 end
local function mission()
    local E=SC.ExpeditionPrototype
    local trip=E and type(E.current)=="function" and E.current()
        or E and type(E.active)=="function" and E.active() or nil
    return trip and not trip.terminal and trip.radioSession or nil
end
function R.hasMission() return mission()~=nil end
local function memory(object)
    local data=U().data(object)
    local portable=data and data.movableData
    if type(portable)~="table" then return nil end
    local state=portable[R.KEY]
    local rt=tracked[object]
    if type(state)=="table" and rt and rt.memory==state then return state end
    local saved=type(state)=="table" and state.schema==1 and state or {}
    state={schema=1,log={},found={},mode=({bars=true,wave=true,signal=true})[saved.mode] and saved.mode or "bars"}
    state.lastReport=reportCopy(saved.lastReport)
    for index,row in ipairs(type(saved.log)=="table" and saved.log or {}) do
        if index>R.MAX_LOG then break end
        if type(row)=="table" and frequency(row.frequency) and finite(row.at) and type(row.text)=="string" then
            state.log[#state.log+1]={frequency=row.frequency,at=row.at,text=clean(row.text,360),
                name=clean(row.name,48),recorded=row.recorded==true}
        end
    end
    local seen={}
    for index,row in ipairs(type(saved.found)=="table" and saved.found or {}) do
        if index>R.MAX_FOUND then break end
        if type(row)=="table" and frequency(row.frequency) and finite(row.at) and not seen[row.frequency] then
            seen[row.frequency]=true
            state.found[#state.found+1]={frequency=row.frequency,at=row.at,name=clean(row.name,48)}
        end
    end
    portable[R.KEY]=state
    if rt then rt.memory=state end
    return state
end
function R.observe(object,receiver,data,item)
    if not receiver or not data then return end
    local hardware=SC.TerminalHardware.state(object,false)
    if not hardware or not hardware.radio then return end
    local rt=tracked[object]
    if not rt or rt.receiver~=receiver or rt.generation~=hardware.generation or rt.item~=item then
        rt={receiver=receiver,data=data,item=item,generation=hardware.generation,receiving=false,notice="Listening for local transmissions."}
        tracked[object]=rt
    end
    memory(object)
    owners[receiver]=object
end
local function current(object,rt,unpowered)
    local state=SC.TerminalHardware.state(object,false)
    return rt and state and state.radio and state.generation==rt.generation
        and U().present(object) and (unpowered or SC.TerminalHardware.powered(object))
        and (unpowered or (tonumber(call(rt.item,"getCondition")) or 0)>0)
        and call(rt.item,"getDeviceData")==rt.data and (unpowered or call(rt.data,"getIsTurnedOn")==true)
end
function R.ready(window)
    if not window or window.closed or SC.Terminal.window~=window or not window.system or window.system.locked
        or type(getSpecificPlayer)~="function" or getSpecificPlayer(0)~=window.player
        or call(window.player,"isDead")==true or not U().present(window.object)
        or not SC.Terminal.near(window.player,window.object) or not SC.Terminal.powered(window.object) then
        return nil,"Stand at an unlocked, powered computer."
    end
    local md=U().data(window.object)
    if not md or not md.movableData or md.movableData[SC.TerminalSystem.MEMORY_KEY]~=window.system then
        return nil,"This computer's access record changed. Reopen the terminal."
    end
    local receiver,data,item=SC.TerminalHardware.receiver(window.object)
    if not receiver then return nil,"Mount a usable two-way walkie-talkie first." end
    if not item or (tonumber(call(item,"getCondition")) or 0)<=0 then return nil,"The mounted walkie-talkie is broken. Replace or repair it first." end
    R.observe(window.object,receiver,data,item)
    return tracked[window.object]
end
local function flush(object) return SC.TerminalHardware.flush(object) end
local function saved(object,message)
    if flush(object)==false then return false,"Radio changed, but mounted memory could not be saved. Stay at the PC and try again." end
    return true,message
end
local function tune(object,rt,n)
    local low,high=call(rt.data,"getMinChannelRange"),call(rt.data,"getMaxChannelRange")
    if not frequency(n) or not integer(low) or not integer(high) or n<low or n>high then
        return false,"Frequency is outside this handset's tuning range."
    end
    call(rt.data,"setChannel",n)
    if call(rt.data,"getChannel")~=n then return false,"The handset did not accept that frequency." end
    rt.receiving=false rt.lastReception=nil rt.needQuiet=true rt.tunedAt=U().now()
    return true
end
function R.stop(object,restore)
    local rt=tracked[object]
    local scan=rt and rt.scan
    if not scan then return true end
    rt.scan=nil
    if restore and current(object,rt,true) and call(rt.data,"getChannel")==scan.expected then
        local okay,reason=tune(object,rt,scan.original)
        if not okay then rt.notice=reason return false,reason end
        flush(object)
    end
    rt.notice=restore and "Scan stopped. Previous channel restored where unchanged." or "Staying on this frequency."
    return true
end
function R.leave(window)
    if window then R.stop(window.object,true) end
end
local function readPresets(rt)
    local result={}
    local presets=rt and call(rt.data,"getDevicePresets")
    for _,entry in ipairs(U().list(call(presets,"getPresets"),32)) do
        local n=call(entry,"getFrequency")
        if frequency(n) then result[#result+1]={frequency=n,name=clean(call(entry,"getName"),48)} end
    end
    return result
end
function R.presets(object) local rt=tracked[object] return rt and rt.presets or {} end
local function stationName(object,n)
    for _,p in ipairs(R.presets(object)) do if p.frequency==n and p.name~="" then return p.name end end
    local rt=tracked[object]
    for _,p in ipairs(rt and rt.memory and rt.memory.found or {}) do if p.frequency==n and p.name~="" then return p.name end end
    return "Unknown station"
end
function R.onDeviceText(guid,codes,x,y,z,text,device)
    if type(text)~="string" or text=="" or not device then return end
    local object=owners[device]
    local rt=object and tracked[object]
    if rt then
        -- The actual native device, not matching coordinates, owns reception.
        if device==rt.receiver and current(object,rt) then
            local n=call(rt.data,"getChannel")
            local at=U().hours()
            if frequency(n) and finite(at) then
                local line=clean(text,360)
                if line~="" then
                    local m=memory(object)
                    local name=stationName(object,n)
                    local radio=type(getZomboidRadio)=="function" and getZomboidRadio()
                    if name=="Unknown station" then name=clean(call(radio,"getChannelName",n),48) end
                    if name=="" then name="Unknown station" end
                    local recorded=call(rt.data,"isPlayingMedia")==true
                    local last=m.log[1]
                    if not last or last.frequency~=n or last.text~=line or math.abs(at-last.at)>.002 then
                        table.insert(m.log,1,{frequency=n,at=at,text=line,name=name,recorded=recorded})
                        while #m.log>R.MAX_LOG do table.remove(m.log) end
                    end
                    if not recorded then
                        local found
                        for index,row in ipairs(m.found) do if row.frequency==n then found=index break end end
                        if found then table.remove(m.found,found) end
                        table.insert(m.found,1,{frequency=n,at=at,name=name})
                        while #m.found>R.MAX_FOUND do table.remove(m.found) end
                    end
                    rt.lastReception=U().now()
                    rt.receipts=((rt.receipts or 0)+1)%1000000
                    rt.needQuiet=false
                    rt.notice=recorded and "EMMA: Recorded media received; this is not a live contact."
                        or "EMMA: Transmission received. Stored in your notebook."
                    if rt.scan and not rt.scan.skipping and n==rt.scan.expected and not recorded then
                        rt.scan.hold=true
                        rt.notice="Transmission received. Holding frequency; save it, stay here or continue scanning."
                    end
                end
            end
        end
    end
end
function R.poll(window,now)
    now=now or U().now()
    local previous=window and tracked[window.object]
    if previous and previous.lastPoll and now>=previous.lastPoll and now-previous.lastPoll<250 then return previous end
    local rt,reason=R.ready(window)
    if not rt then
        R.leave(window)
        if previous then previous.view=nil previous.receiving=false previous.lastReception=nil end
        return nil,reason
    end
    rt.lastPoll=now
    rt.presets=readPresets(rt)
    local receiving=call(rt.data,"isReceivingSignal")==true
    if not receiving then rt.needQuiet=false end
    if rt.needQuiet then receiving=false end
    local scan=rt.scan
    if scan then
        if mission()~=scan.mission then R.stop(window.object,true) rt.notice="Expedition changed. Scan stopped; check the team channel."
        elseif call(rt.data,"getChannel")~=scan.expected then R.stop(window.object,false) rt.notice="Tuning changed elsewhere. Scan cancelled."
        elseif call(rt.data,"isPlayingMedia")==true then R.stop(window.object,true) rt.notice="Recorded media is playing. Scanning stopped."
        else
            -- Discard a previous channel's still-decaying receive flag. Text
            -- events above can hold immediately; raw carrier must go quiet first.
            if not receiving then scan.armed=true end
            if scan.skipping then scan.armed=false scan.hold=false end
            if receiving and scan.armed then scan.hold=true rt.notice="Signal received. Holding frequency." end
            if not scan.hold and now>=scan.nextAt then
                scan.index=scan.index+1
                if scan.index>scan.count then
                    local limited=scan.limited
                    R.stop(window.object,true)
                    rt.notice=limited and "Scan limit reached (5,000 steps). Previous channel restored."
                        or "Scan complete. Nothing further heard during these listening windows. Previous channel restored."
                else
                    local n=scan.channels and scan.channels[scan.index] or scan.low+(scan.index-1)*R.STEP
                    local okay,detail=tune(window.object,rt,n)
                    if not okay then R.stop(window.object,true) rt.notice=detail
                    else scan.expected=n scan.nextAt=now+R.DWELL scan.armed=not receiving scan.skipping=nil end
                end
            end
        end
    end
    rt.receiving=receiving
    rt.view={frequency=call(rt.data,"getChannel"),name=stationName(window.object,call(rt.data,"getChannel")),
        volume=call(rt.data,"getDeviceVolume") or 0,mic=call(rt.data,"getMicIsMuted")~=true,
        scan=rt.scan,notice=rt.notice,memory=memory(window.object)}
    return rt
end
function R.snapshot(window)
    local rt=tracked[window.object]
    local view=rt and rt.view
    if not view then return nil end
    view.receiving=rt.receiving or rt.lastReception and U().now()-rt.lastReception<500
    view.tx=rt.txUntil and U().now()<rt.txUntil
    view.scan,view.notice=rt.scan,rt.notice
    view.receipts=rt.receipts or 0
    return view
end
local function start(window,rt,mode,allow)
    if mode~="presets" and mode~="band" then return false,"Unknown scan mode." end
    if call(rt.data,"isPlayingMedia")==true then return false,"Stop recorded media before scanning." end
    local trip=mission()
    if trip and not allow then return nil,"Scanning retunes this handset and can miss expedition calls.",{kind="radio_desk",mode=mode} end
    R.stop(window.object,true)
    rt.presets=readPresets(rt)
    local channels,low,high,count
    if mode=="presets" then
        channels={} local seen={}
        for _,p in ipairs(R.presets(window.object)) do
            if not seen[p.frequency] then seen[p.frequency]=true channels[#channels+1]=p.frequency end
        end
        count=#channels
        if count==0 then return false,"No saved presets. Tune a frequency and save it first." end
    else
        low,high=call(rt.data,"getMinChannelRange"),call(rt.data,"getMaxChannelRange")
        if not frequency(low) or not frequency(high) or high<low then return false,"The handset's band limits are unavailable." end
        count=math.floor((high-low)/R.STEP)+1
    end
    rt.scan={original=call(rt.data,"getChannel"),expected=call(rt.data,"getChannel"),mode=mode,
        index=0,count=math.min(count,R.MAX_SCAN),limited=count>R.MAX_SCAN,channels=channels,low=low,
        mission=trip,nextAt=U().now(),armed=call(rt.data,"isReceivingSignal")~=true}
    rt.notice="Scanning "..mode..". Three seconds per position; silent channels remain unverified."
    rt.lastPoll=nil
    R.poll(window,U().now())
    return true,rt.notice
end
function R.scan(window,mode) local rt,reason=R.ready(window) if not rt then return false,reason end return start(window,rt,mode,false) end
function R.prepare(window,proposal)
    local rt,reason=R.ready(window)
    if not rt then return nil,reason end
    if proposal.mode~="presets" and proposal.mode~="band" then return nil,"Unknown scan request." end
    return {receiver=rt.receiver,item=rt.item,channel=call(rt.data,"getChannel"),generation=rt.generation,mission=mission(),mode=proposal.mode},
        "Scan away from the team channel on THIS walkie? Expedition calls may be missed. "
        .."The scan stops if the mission changes. Close Radio Desk to restore the previous channel. [Y/N]"
end
function R.execute(window,request)
    local rt,reason=R.ready(window)
    if not rt then return false,reason end
    if rt.receiver~=request.receiver or rt.item~=request.item or call(rt.data,"getChannel")~=request.channel
        or rt.generation~=request.generation or mission()~=request.mission then
        return false,"The radio or expedition changed. Ask again."
    end
    return start(window,rt,request.mode,true)
end
function R.tune(window,n)
    local rt,reason=R.ready(window) if not rt then return false,reason end
    local okay,detail=tune(window.object,rt,n)
    if okay then
        R.stop(window.object,false)
        rt.notice="Tuned to "..R.format(n)..". Listening does not transmit."
        return saved(window.object,rt.notice)
    end
    return okay,detail or rt.notice
end
function R.continue(window)
    local rt,reason=R.ready(window) if not rt then return false,reason end
    if not rt.scan then return false,"No scan is paused." end
    rt.scan.hold=false rt.scan.armed=false rt.scan.skipping=true rt.scan.nextAt=U().now()
    rt.notice="Continuing the scan after this listening window."
    rt.lastPoll=nil R.poll(window,U().now())
    return true,rt.notice
end
function R.savePreset(window,name)
    local rt,reason=R.ready(window) if not rt then return false,reason end
    name=clean(name,32) if name=="" then return false,"Name the preset: save this channel as Weather." end
    local n=call(rt.data,"getChannel")
    local presets=call(rt.data,"getDevicePresets")
    local list=U().list(call(presets,"getPresets"),32)
    if not frequency(n) or not presets then return false,"Native presets are unavailable." end
    local index
    for i,p in ipairs(list) do if call(p,"getFrequency")==n then index=i-1 break end end
    if index then call(presets,"setPresetName",index,name)
    elseif #list>=math.min(32,tonumber(call(presets,"getMaxPresets")) or 0) then return false,"The handset's preset list is full. Rename an existing preset or use its radio controls."
    else call(presets,"addPreset",name,n) end
    local found=false
    rt.presets=readPresets(rt)
    for _,p in ipairs(R.presets(window.object)) do if p.frequency==n and p.name==name then found=true end end
    if not found then return false,"The handset did not save that preset." end
    R.stop(window.object,false)
    return saved(window.object,"Saved "..name.." at "..R.format(n)..". Staying on this channel.")
end
function R.audio(window,kind,value)
    local rt,reason=R.ready(window) if not rt then return false,reason end
    local hardware=SC.TerminalHardware.state(window.object,false)
    if kind=="mic" then
        call(rt.data,"setMicIsMuted",value==true)
        if call(rt.data,"getMicIsMuted")~=(value==true) then return false,"Microphone control is unavailable." end
    else
        local volume=tonumber(value)
        if not finite(volume) or volume<0 or volume>1 then return false,"Volume must be 0 to 100 percent." end
        local old,oldLast=hardware.radio.monitorVolume,hardware.radio.lastMonitorVolume
        hardware.radio.monitorVolume=volume
        if volume>0 then hardware.radio.lastMonitorVolume=volume end
        call(rt.data,"setDeviceVolume",volume)
        if math.abs((call(rt.data,"getDeviceVolume") or -1)-volume)>.02 then
            hardware.radio.monitorVolume,hardware.radio.lastMonitorVolume=old,oldLast
            return false,"Speaker control is unavailable."
        end
    end
    return saved(window.object,kind=="mic" and (value and "Microphone muted. Radio orders require an open microphone." or "Microphone open. This does not send a command.")
        or "Speaker volume: "..math.floor(value*100+.5).."%. Native world audibility is retained.")
end
function R.cycleMode(object)
    local m=memory(object) if not m then return end
    m.mode=({bars="wave",wave="signal",signal="bars"})[m.mode] or "bars"
end
function R.transmitted(object) local rt=tracked[object] if rt then rt.txUntil=U().now()+700 end end
function R.acknowledged(object,id,report)
    local m=memory(object) if m then m.lastReport=reportCopy(report,id) end
end
function R.lastReport(object) local m=memory(object) return m and m.lastReport end
function R.factoryReset(object)
    R.stop(object,true) tracked[object]=nil
    local md=U().data(object) if md and type(md.movableData)=="table" then md.movableData[R.KEY]=nil end
end
function R.install()
    if not R._deviceTextHook and Events and Events.OnDeviceText and type(Events.OnDeviceText.Add)=="function" then
        R._deviceTextHook=function(...) if SC.TerminalRadio then SC.TerminalRadio.onDeviceText(...) end end
        Events.OnDeviceText.Add(R._deviceTextHook)
    end
end
function R.reset()
    for object in pairs(tracked) do R.stop(object,true) end
    tracked=setmetatable({}, {__mode="k"}) owners=setmetatable({}, {__mode="kv"})
end
R.install()
return R
