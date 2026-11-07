-- SPDX-License-Identifier: MIT
-- Player-observable guidance rules, using a fake clock and a real file format.
local SC=SurvivorCompanion
local checks=0
local function check(value,message) checks=checks+1;assert(value,message) end
if guidanceReload then
    check(SC.Guidance.load(),"install memory reloads")
    check(SC.Guidance.summary():find("invite",1,true)~=nil,"a different world retains learned recruitment")
    check(SC.Guidance.summary():find("storage",1,true)~=nil,"storage progress survives restart")
    print("GUIDANCE_RELOAD_PASS")
    return
end
local clock,show,records=0,true,{}
local disk={}
local player={}
function player:isDead() return false end
SC.UserOptions={get=function(key) if key=="showTips" then return show end end,
    setShowTips=function(value) show=value end}
SC.Registry={records=function() return records end}
SC.BaseLife={active=function() return nil end,resident=function() return nil end}
SC.GameplayUtil={
    nowMs=function() return clock end,
    text=function(_,fallback,argument) return (fallback:gsub("%%1",argument or "Home")) end,
    isDead=function(a) return a:isDead() end,
    sameFloor=function() return true end,distance=function() return 10 end,
    canSee=function() return true end,
    call=function(o,m,...) if o and type(o[m])=="function" then return o[m](o,...),true end return nil,false end,
}
SC.State.active=true
getFileReader=function(path)
    local content=disk[path];if not content then return nil end
    local rows={};for line in content:gmatch("([^\n]+)") do rows[#rows+1]=line end
    local i=0
    return {readLine=function() i=i+1;return rows[i] end,close=function() end}
end
getFileWriter=function(path)
    disk[path]=""
    return {write=function(_,line) disk[path]=disk[path]..line end,close=function() end}
end
local G=SC.Guidance
check(not G.load(),"missing install memory starts a dismissible tutorial")
G.pulse(player,clock)
check(G.view().id=="meet","fresh player starts at meeting a survivor")
local actor={isDead=function() return false end}
records={{id="sc-test",actor=actor,recruited=false}}
clock=1000;G.pulse(player,clock)
check(G.view().id=="invite","seeing an independent survivor completes meeting")
G.report("recruited",{actor=actor});records[1].recruited=true
clock=2000;G.pulse(player,clock)
check(G.view().id=="order","joining does not count as giving an order")
local parent={visible=true,isVisible=function(self) return self.visible end}
local control={}
G.control(control,"order",parent)
clock=3999;G.pulse(player,clock)
check(G.pointer()==nil,"pointer gives the player a grace period")
clock=4000;G.pulse(player,clock)
check(G.pointer() and G.pointer().control==control,"pointer marks the real current control")
clock=16000;G.pulse(player,clock)
check(G.pointer()==nil,"pointer ends after twelve seconds")
clock=17000;G.pulse(player,clock)
check(G.pointer()==nil,"expired pointer does not immediately repeat")
parent.visible=false;clock=18000;G.pulse(player,clock)
parent.visible=true;clock=20001;G.pulse(player,clock)
check(G.pointer()~=nil,"reopening the actual control permits another bounded pointer")
records[1].runtime={senses={current={threatCount=1}}}
clock=21000;G.pulse(player,clock)
check(G.view()==nil and G.pointer()==nil,"combat suppresses checklist and pointers")
records[1].runtime.senses.current={pressure=.1}
clock=22000;G.pulse(player,clock)
check(G.view()==nil,"pressure alone suppresses guidance")
records[1].runtime.senses.current={}
G.report("ordered");clock=23000;G.pulse(player,clock)
check(G.view().id=="camp","an accepted explicit order advances the checklist")
G.report("camp");G.report("storage");G.report("job");G.report("computer")
clock=24000;G.pulse(player,clock)
check(G.view().id=="complete","the checklist ends after real milestones")
check(#G.list()>=7,"seen instructions remain available to reread")
G.skip();check(show==false and G.view()==nil,"veteran skip turns off all tips")
G.resetTips();show=true;records={};clock=25000;G.pulse(player,clock)
check(G.view().id=="meet","reset teaches again without changing world actors")
local tabParent={visible=true,isVisible=function(self) return self.visible end}
local tabButton,quietTab={}, {}
G.control(tabButton,"expeditions",tabParent,false,true)
G.control(quietTab,"send_home",tabParent,false,true)
check(tabButton.tooltip==G.text("expeditions"),"an unexplored tab explains itself")
local firstButton={tooltip="Follow"}
G.control(firstButton,"order",tabParent)
for _=1,30 do G.control({tooltip="Stay"},"order",tabParent) end
check(firstButton.tooltip=="Follow","a control pushed out of the list gets its own tooltip back")
clock=25200;G.pulse(player,clock)
check(quietTab.tooltip==G.text("send_home"),"a pinned tab keeps its hint while other controls come and go")
G.report("expedition_used");clock=25500;G.pulse(player,clock)
check(tabButton.tooltip==nil,"a pinned tab keeps following what was learned")
show=false;clock=26000;G.pulse(player,clock)
check(quietTab.tooltip==nil,"tips off restores a pinned tab's own tooltip")
show=true;tabParent.visible=false;clock=26500;G.pulse(player,clock)
G.dismiss();check(G.view()==nil,"the card can be dismissed independently")
G.reopen();check(G.view()~=nil,"dismissal is reversible")
G.report("recruited");G.report("storage")
local file=disk["LivingFellows-guidance.txt"]
check(file:find("LF_GUIDANCE_1",1,true)==1 and file:find("done:invite",1,true),"memory is a small versioned file")
local spoken={}
SC.Dialogue={say=function(_,topic) spoken[#spoken+1]=topic;return true end,lastDisplayUntil=function() return 0 end}
G.resetTips();clock=100000;records={{id="sc-test",actor=actor,recruited=true}}
G.report("recruited",{actor=actor});show=false;clock=100000;G.pulse(player,clock)
check(#spoken==0,"tips off also silences the first recruit's teaching line")
show=true;clock=101000;G.pulse(player,clock)
check(spoken[1]=="guidance.recruit_hint","the recruit speaks after the joining line ends")
clock=102000;G.pulse(player,clock);check(#spoken==1,"a teaching line never repeats on this install")
G.report("ordered");G.report("camp");G.report("storage");G.report("job")
G.pulse(player,clock)
check(G.view().id=="computer" and G.tracker()==nil,"the optional computer step stays on the card, not beside the launcher")
local computer={}
SC.GameplayUtil.squareOf=function(a) return a end
SC.GameplayUtil.distance=function(_,a) return a==computer and 2 or 10 end
SC.Terminal={present=function() return true end,powered=function() return false end}
G.report("computer_near",{object=computer})
clock=106999;G.pulse(player,clock);check(#spoken==1,"unpowered-computer teaching has a five-second grace")
clock=107000;G.pulse(player,clock);check(spoken[2]=="guidance.dead_computer","a reached unpowered computer gets one truthful hint")
SC.Terminal.powered=function() return true end
G.report("locked_closed",{object=computer,system={locked=true}})
clock=108000;G.pulse(player,clock);check(#spoken==2,"a different nudge waits fifteen real minutes")
clock=1007001;G.pulse(player,clock);check(spoken[3]=="guidance.locked_computer","the waiting nudge can speak when spacing expires")
G.reset();clock=1008000;G.pulse(player,clock)
check(not G.notice(),"the first-load notice is not repeated after a runtime reload")
local base={storage={one={}}}
SC.BaseLife.active=function() return base end
G.resetTips();G.report("met");G.report("recruited");G.report("ordered");G.report("camp");G.report("storage");G.report("job")
records[2]={id="sc-two",actor=actor,recruited=true,runtime={lastDecision="idle"}}
G.dismiss()
clock=2000000;G.pulse(player,clock)
clock=2059999;G.pulse(player,clock);check(not G.dot("expeditions"),"feature nudges wait a minute")
clock=2060000;G.pulse(player,clock);check(G.dot("expeditions"),"a settled two-person camp gets one expedition nudge")
local function listed(id) for _,tip in ipairs(G.list()) do if tip.id==id then return true end end return false end
check(not listed("nudge_expeditions"),"a nudge is not spent before anything shows it")
local line=G.tracker()
check(line and line.kind=="nudge" and line.id=="nudge_expeditions" and line.tab=="expeditions"
    and line.text==G.text("nudge_expeditions"),"a dismissed checklist still lets a feature nudge show beside the launcher")
clock=2090000;G.pulse(player,clock)
check(G.tracker() and G.tracker().id=="nudge_expeditions","an unseen nudge waits for the screen")
clock=2100000;G.shown("nudge_expeditions");check(listed("nudge_expeditions"),"a nudge counts as seen once drawn")
clock=2111999;G.pulse(player,clock);check(G.tracker()~=nil,"a shown nudge stays twelve seconds from when it was drawn")
clock=2112000;G.pulse(player,clock)
check(G.tracker()==nil and G.dot("expeditions"),"after twelve seconds the line goes, the dot stays")
G.reset();clock=2113000;G.pulse(player,clock)
check(G.dot("expeditions"),"the dot survives a runtime reload until the tab is visited")
G.report("tab",{tab="expeditions"});clock=2114000;G.pulse(player,clock)
check(not G.dot("expeditions"),"visiting the actual tab clears its dot")
clock=3000000;G.pulse(player,clock);check(not G.dot("expeditions"),"visited features never nudge again")
G.resetTips();G.report("recruited");G.report("ordered");G.report("camp");G.report("storage");G.report("job")
records[1].runtime={lastDecision="idle"};SC.BaseLife.isInside=function() return true end
local hours=10;getGameTime=function() return {getWorldAgeHours=function() return hours end} end
clock=4000000;G.pulse(player,clock)
check(not G.dot("more"),"idle camp guidance waits an in-game hour")
hours=11;clock=4003000;G.pulse(player,clock)
check(spoken[#spoken]=="guidance.camp_jobs" and G.dot("more"),"one camp-job nudge combines the line and More dot")
G.report("tab",{tab="more"});clock=4004000;G.pulse(player,clock)
check(not G.dot("more"),"the More dot clears on its first visit")
G.dismiss();G.resetTips();G.report("recruited");G.report("storage")
guidanceReload=true
print("GUIDANCE_KAHLUA_PASS checks="..checks)
