-- SPDX-License-Identifier: MIT
local SC,T=SurvivorCompanion,TERMINAL_TEST
local R,UI=SC.TerminalRadio,SC.TerminalRadioUI
local check,before=T.check,T.checks
local oldH,oldE,oldLife,oldMain,oldNow,oldRadio,oldEvents=SC.TerminalHardware,SC.ExpeditionPrototype,SC.BaseLife,getSpecificPlayer,SC.GameplayUtil.nowMs,getZomboidRadio,Events
local player=T.player(101,100,0)
getSpecificPlayer=function(index) return index==0 and player or nil end
SC.GameplayUtil.nowMs=function() return T.now end
SC.BaseLife={active=function() return nil end,isInside=function() return false end}
local trip
SC.ExpeditionPrototype={TEAM_RADIO_CHANNEL=90000,active=function() return trip end}
local flushes,nativeCalls=0,0
local function list(rows) return {size=function() nativeCalls=nativeCalls+1 return #rows end,get=function(_,i) nativeCalls=nativeCalls+1 return rows[i+1] end} end
local function device()
    local d={channel=99000,low=88000,high=108000,volume=.3,mic=false,receiving=false,entries={}}
    local p={}
    function p:getPresets() return list(d.entries) end function p:getMaxPresets() return 4 end
    function p:addPreset(name,frequency)
        d.entries[#d.entries+1]={name=name,frequency=frequency,getName=function(self) return self.name end,getFrequency=function(self) return self.frequency end}
    end
    function p:setPresetName(i,name) d.entries[i+1].name=name end
    p:addPreset("Team",90000) p:addPreset("Weather",94000)
    function d:getDevicePresets() nativeCalls=nativeCalls+1 return p end
    function d:getChannel() nativeCalls=nativeCalls+1 return self.channel end function d:setChannel(n) self.channel=n end
    function d:getMinChannelRange() return self.low end function d:getMaxChannelRange() return self.high end
    function d:getIsTurnedOn() return true end function d:isReceivingSignal() return self.receiving end
    function d:isPlayingMedia() return self.recorded==true end function d:getDeviceVolume() return self.volume end
    function d:setDeviceVolume(v) self.volume=v end function d:getMicIsMuted() return self.mic end function d:setMicIsMuted(v) self.mic=v end
    return d,p
end
local function setup()
    local pc=T.computer(T.square(100,100,0,true))
    local d,p=device() pc.device=d pc.presets=p
    pc.radioItem={getDeviceData=function() return d end,getCondition=function() return 100 end}
    pc.receiver={getDeviceData=function() return d end}
    pc.hardware={generation=1,radio={id=101,monitorVolume=.3}}
    return pc
end
SC.TerminalHardware={
    state=function(pc) return pc.hardware end,
    powered=function(pc) return pc.square and pc.square.generatorPower==true end,
    receiver=function(pc) if pc.square.generatorPower and pc.hardware.radio then return pc.receiver,pc.device,pc.radioItem end end,
    flush=function(pc) flushes=flushes+1 pc.savedChannel=pc.device.channel return true end,
}
getZomboidRadio=function() return {getChannelName=function(_,n) return n==94000 and "Weather service" or nil end} end
local pc=setup()
SC.Terminal.computerState(player,pc).locked=false
check(SC.Terminal.open(player,pc),"radio fixture opens")
local w=SC.Terminal.window w:flush()
local function send(text)
    w:setFocusMode("chat") w.entry:setText(text) w:submit() w:flush()
end
local function poll(ms) T.now=T.now+(ms or 300) R.poll(w,T.now) end
send("open radio")
check(UI.active(w) and #w:menuOptions()==6,"radio opens without adding a sixth terminal home shortcut")
check(R.format(94000)=="94.000 MHz" and R.snapshot(w).frequency==99000,"readout uses native frequency units")
local drawCalls=nativeCalls
w:prerender() w:prerender()
check(nativeCalls==drawCalls,"visual rendering makes no native device or preset reads")
R.poll(w,T.now+1) R.poll(w,T.now+2)
check(nativeCalls==drawCalls,"native polling is throttled before hardware and preset reads")
local installs=0 local hook
Events={OnDeviceText={Add=function(callback) installs=installs+1 hook=callback end}}
R.install() R.install()
check(installs==1 and type(hook)=="function","radio event subscription is installed once")
send("tune to 94.0 MHz") poll()
check(pc.device.channel==94000 and pc.savedChannel==94000,"manual tuning changes and saves the actual handset")
send("tune 400") check(pc.device.channel==94000,"out-of-band tuning is refused")
send("volume 60") poll() check(pc.device.volume==.6 and pc.hardware.radio.monitorVolume==.6,"volume controls the real speaker and portable monitor setting")
send("mute radio") poll() check(pc.device.volume==0,"speaker mute sets actual native volume")
send("unmute radio") poll() check(pc.device.volume==.6,"unmute restores the previous listening level")
send("mute microphone") poll() check(pc.device.mic,"microphone mute is distinct from the speaker")
send("unmute microphone") poll() check(not pc.device.mic,"microphone state can be restored explicitly")
send("save this channel as County Weather")
check(pc.device.entries[2].name=="County Weather" and #pc.device.entries==2,"saving current frequency renames native preset without duplicates")
send("tune 96") send("save this channel as Spare") send("tune 98") send("save this channel as Other")
send("tune 100") send("save this channel as Overflow")
check(#pc.device.entries==4,"native maximum presets cannot be exceeded")
R.tune(w,99000) poll()
send("scan for broadcasts")
check(R.snapshot(w).scan and pc.device.channel==90000,"preset scan tunes a real preset")
local activeScan=R.snapshot(w).scan
local originalSetter=pc.device.setChannel
pc.device.setChannel=function(self,n) if n~=99000 then originalSetter(self,n) end end
check(not R.stop(pc,true) and R.snapshot(w).scan==activeScan,
    "failed original-channel restoration keeps a retryable scan lease")
local previousDrawText=w.drawText local pendingLabel=false
w.drawText=function(self,value,...) if tostring(value):find("RESTORE PENDING",1,true) then pendingLabel=true end return previousDrawText(self,value,...) end
w:prerender() w.drawText=previousDrawText
check(pendingLabel,"a failed restore is visibly pending rather than reported as active scanning")
poll(R.DWELL+300)
check(pc.device.channel==90000 and not R.scan(w,"band"),
    "pending restoration cannot advance or be replaced by another scan")
pc.device.setChannel=originalSetter
check(R.stop(pc,true) and pc.device.channel==99000 and not R.snapshot(w).scan,
    "retry restores the exact original channel before releasing the lease")
send("scan for broadcasts")
local previousFlush=SC.TerminalHardware.flush
SC.TerminalHardware.flush=function() return false,"fixture storage unavailable" end
check(not R.stop(pc,true) and pc.device.channel==99000 and R.snapshot(w).scan.restoring,
    "restored tuning remains owned until the exact handset payload is saved")
local originalMemory=pc.data.movableData[R.KEY] local originalSystem=w.system
check(not SC.Terminal.factoryReset(w) and pc.data.movableData[R.KEY]==originalMemory
    and pc.data.movableData[SC.TerminalSystem.MEMORY_KEY]==originalSystem,
    "failed restore persistence cannot erase radio memory or factory-reset the computer")
SC.TerminalHardware.flush=previousFlush
check(R.stop(pc,true) and not R.snapshot(w).scan and pc.savedChannel==99000,
    "serialization recovery saves the original channel before releasing the pending restore")
send("scan for broadcasts") activeScan=R.snapshot(w).scan
send("tune 400")
check(R.snapshot(w).scan==activeScan and pc.device.channel==90000,
    "an invalid frequency cannot cancel scanning or strand the handset on a temporary channel")
poll(R.DWELL+300) check(pc.device.channel==94000,"scanner advances in bounded listening windows")
R.onDeviceText("g","c",100,100,0,"Wrong nearby radio",{})
check(#R.snapshot(w).memory.log==0,"co-located radios cannot inject notebook text")
pc.device.receiving=true
R.onDeviceText("g","c",100,100,0,"Forecast received at the computer.",pc.receiver)
poll()
check(#R.snapshot(w).memory.log==1 and R.snapshot(w).scan.hold,"actual device reception logs text and pauses scan")
check(R.snapshot(w).memory.log[1].frequency==94000 and R.snapshot(w).memory.found[1].frequency==94000,
    "heard frequencies come only from received events, never the native station catalogue")
local held=pc.device.channel poll(R.DWELL*3) check(pc.device.channel==held,"held speech is not skipped by the scan timer")
send("continue scanning")
check(pc.device.channel==96000,"Continue moves to the next preset even while the previous signal remains active")
send("stop scanning")
check(pc.device.channel==99000 and not R.snapshot(w).scan,"stop restores the exact pre-scan channel")
pc.device.receiving=false poll()
send("scan band") check(pc.device.channel==88000,"band scan begins at native lower bound")
poll(R.DWELL+300) check(pc.device.channel==88200,"band sweep uses native 0.2 MHz steps")
pc.device.channel=97000 poll()
check(not R.snapshot(w).scan and pc.device.channel==97000,"external tuning cancels scan without overwriting the new owner's choice")
trip={radioSession="trip-1"}
send("scan for broadcasts")
check(w.requestTicket and not R.snapshot(w).scan,"away team requires explicit confirmation before scanning")
send("n") check(not w.requestTicket and not R.snapshot(w).scan,"refusing scan leaves team listening intact")
send("scan for broadcasts") local ticket=w.requestTicket
pc.hardware.generation=2 send("yes") poll()
check(not R.snapshot(w).scan and SC.TerminalActions.execute(w,ticket)==false,"changed radio generation invalidates and consumes scan consent")
poll() send("scan for broadcasts") send("y") poll()
check(R.snapshot(w).scan~=nil,"confirmed scan may retune during the same expedition")
trip={radioSession="replacement"} poll()
check(not R.snapshot(w).scan and pc.device.channel==97000,"replacement mission stops scan and restores previous listening")
trip=nil poll() send("scan presets")
pc.square.generatorPower=false poll()
check(pc.device.channel==97000,"power loss cancels scan and preserves its original configured frequency")
local quietVolume=pc.device.volume
local unmuteOkay=pcall(UI.input,w,"unmute radio")
local presetOkay=pcall(UI.input,w,"next preset")
check(unmuteOkay and presetOkay and pc.device.volume==quietVolume,
    "radio commands after power loss fail readably without indexing absent native state")
pc.square.generatorPower=true poll()
trip={radioSession="finished",terminal=true}
send("scan presets") check(not w.requestTicket and R.snapshot(w).scan,"completed trips do not leave expedition scan restrictions behind")
send("stop scanning") trip=nil
pc.device.recorded=true send("scan band") check(not R.snapshot(w).scan,"recorded media cannot be mistaken for a live band scan")
R.onDeviceText("g","c",100,100,0,"A tape recording.",pc.receiver)
check(R.snapshot(w).memory.log[1].recorded and #R.snapshot(w).memory.found==1,"recordings are labelled and do not discover broadcast frequencies")
pc.device.recorded=false
for i=1,70 do T.hours=T.hours+.01 R.onDeviceText("g","c",100,100,0,"Received line "..i,pc.receiver) end
check(#R.snapshot(w).memory.log==R.MAX_LOG,"notebook length is bounded")
local archive=w.system.archive
hook("g","c",100,100,0,"factory reset",pc.receiver)
check(w.system.archive==archive and not w.requestTicket,"received instructions remain inert notebook text")
pc.device.low,pc.device.high=200,2000000
send("scan band")
check(R.snapshot(w).scan.count==R.MAX_SCAN and R.snapshot(w).scan.limited,"full-band scan is capped at 5,000 tuning steps")
send("stop scanning") pc.device.low,pc.device.high=88000,108000
send("what did we hear") check(w.radioPage=="notebook","natural-language notebook command opens actual received entries")
w:setFocusMode("menu") w.entry:setText("1") w:submit() w:flush()
check(w.radioPage=="reading" and #w:menuOptions()==1,"numbered notebook entry opens its text with a Back choice")
check(UI.scroll(w,4),"notebook supports paging long entries")
for _,size in ipairs({{1280,720},{1920,1080},{2560,1440},{640,720},{960,540}}) do
    getCore=function() return {getScreenWidth=function() return size[1] end,getScreenHeight=function() return size[2] end} end
    w:refreshLayout()
    for _,page in ipairs({"home","scan","audio","presets","notebook","reading","team","library"}) do
        w.radioPage=page w:prerender()
        for _,box in ipairs(w.radioHits) do
            check(box.height>=w.rowHeight and box.x>=w.layout.left and box.x+box.width<=w.layout.right and box.y>=w:viewTop()
                and box.y+box.height<=w:viewBottom(),"radio controls fit viewport "..size[1].."x"..size[2].." / "..page)
        end
    end
end
getCore=function() return {getScreenWidth=function() return 1920 end,getScreenHeight=function() return 1080 end} end
w:refreshLayout()
send("return to the expedition channel") poll() check(pc.device.channel==90000,"team command restores the configured LF channel")
send("next preset") poll() check(pc.device.channel==94000,"next preset uses native saved stations")
send("listen to County Weather") poll() check(pc.device.channel==94000,"named preset command tunes the saved native name")
send("previous preset") poll() check(pc.device.channel==90000,"previous preset returns through native station list")
trip={radioSession="elsewhere",lastProgressReport={kind="wood",collected=99,at=T.hours}}
check(R.lastReport(pc)==nil,"another receiver's cached expedition report is not exposed as this PC's reception")
R.acknowledged(pc,"local-ack",{kind="wood",collected=4,stored=2,at=T.hours,actor=player})
check(R.lastReport(pc).collected==4 and R.lastReport(pc).actor==nil,"local acknowledgement saves only bounded report data without actor references")
trip=nil
local prepare,execute=SC.TerminalServices.prepare,SC.TerminalServices.execute
local controls=0
SC.TerminalServices.prepare=function(_,proposal)
    check(proposal.kind=="control" and proposal.request.operation=="taxi","radio shortcut uses checked station service preparation")
    return {operation="taxi"},"Book Marcus? [Y/N]"
end
SC.TerminalServices.execute=function(_,request) controls=controls+1 return true,"Booking request accepted." end
w.radioPage="team" w:setFocusMode("menu") w.entry:setText("4") w:submit() w:flush()
check(w.requestTicket and controls==0,"Marcus shortcut only proposes the existing service request")
send("n") check(controls==0,"declining Marcus shortcut has no external effects")
w.radioPage="team" w:setFocusMode("menu") w.entry:setText("4") w:submit() w:flush() send("y")
check(controls==1,"confirmed shortcut delegates exactly once to station services")
SC.TerminalServices.prepare,SC.TerminalServices.execute=prepare,execute
local count=#pc.data.movableData[R.KEY].log
w:close() R.reset()
check(SC.Terminal.open(player,pc),"radio reopens after runtime reset") w=SC.Terminal.window w:flush() send("open radio")
check(#R.snapshot(w).memory.log==count,"bounded notebook persists independently of runtime caches")
send("factory reset") send("yes") w=SC.Terminal.window w:flush() send("open radio")
check(#R.snapshot(w).memory.log==0 and #pc.device.entries==4 and pc.hardware.radio.id==101,
    "factory reset clears radio notebook while preserving exact mounted handset and native presets")
local mounted=pc.hardware.radio
send("scan presets") pc.hardware.radio=nil poll()
check(R.snapshot(w)==nil and #w:menuOptions()==1,"removing hardware clears stale reception and leaves an accessible exit")
check(pcall(UI.input,w,"unmute radio") and pcall(UI.input,w,"previous preset"),
    "removed hardware cannot crash direct radio commands")
w:prerender()
check(#w.radioHits==1 and w.radioHits[1].option.radioAction=="leave","missing-radio display draws the same exit that its keyboard menu selects")
pc.hardware.radio=mounted send("open radio") poll()
local condition=pc.radioItem.getCondition
pc.radioItem.getCondition=function() return 0 end poll()
check(R.snapshot(w)==nil,"a broken handset cannot continue reporting reception")
pc.radioItem.getCondition=condition send("open radio") poll()
send("scan presets") w:close()
check(pc.device.channel==90000,"closing the terminal restores its original channel")
R.reset()
SC.TerminalHardware,SC.ExpeditionPrototype,SC.BaseLife,getSpecificPlayer,SC.GameplayUtil.nowMs,getZomboidRadio,Events=oldH,oldE,oldLife,oldMain,oldNow,oldRadio,oldEvents
print("LARCH_WAVE_PASS checks="..(T.checks-before))
SC_TEST_REPORT=(SC_TEST_REPORT or "").."; LARCH/WAVE: "..(T.checks-before).." checks passed"
