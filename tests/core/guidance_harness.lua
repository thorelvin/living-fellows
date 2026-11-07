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
G.dismiss();check(G.view()==nil,"the card can be dismissed independently")
G.reopen();check(G.view()~=nil,"dismissal is reversible")
G.report("recruited");G.report("storage")
local file=disk["LivingFellows-guidance.txt"]
check(file:find("LF_GUIDANCE_1",1,true)==1 and file:find("done:invite",1,true),"memory is a small versioned file")
guidanceReload=true
print("GUIDANCE_KAHLUA_PASS checks="..checks)
