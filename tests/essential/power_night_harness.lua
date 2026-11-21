-- SPDX-License-Identifier: MIT
local SC=SurvivorCompanion
local N,C=SC.PowerNight,SC.PowerNightCatalog
local check=PN.check
for i,id in ipairs(C.starters) do PN.mediaRow(id,i<=3 and "Retail-VHS" or "CDs") end
PN.occupied=202
check(N.install() and N.install(),"hook installation is idempotent")
check(not N.active(),"no broadcasting before discovery")
check(N.discover(PN.player,PN.pc),"first unlocked EMMA access discovers archive")
check(not N.discover(PN.player,PN.pc),"repeat access does not reset archive")
local snap=N.snapshot()
check(#snap.library==6 and snap.tv~=202 and snap.radio~=snap.tv,"starter pack and collision-free channels")
local tv=PN.receiver("tv",snap.tv)
local tapeTv=PN.receiver("tv",snap.tv) tapeTv.data.media=true
PN.devices={tapeTv,tv}
local one,two=PN.actor("sc-one"),PN.actor("sc-two")
PN.members={one,two}
for _,a in ipairs(PN.members) do a.record={state={downtime={}}} a.activity={kind="tv_watch",object=tv,startedAt=1} end
local originalValid=SC.TVWatching.valid
SC.TVWatching.valid=function(a,activity) return activity==a.activity end
PN.at(19.99) N.pulse() check(#tv.lines==0,"silent before 20:00")
PN.at(20) N.pulse()
check(#tv.lines==1 and #tapeTv.lines==0,"native tape playback is protected without suppressing second TV")
check(N.candidate(one,{kind="tv_watch",object=tv,score=20}).powerNight,"available camp member prefers the archive")
check(N.surveyDue(one,"tv",1000),"advertised evening scans immediately instead of staggering first probe")
check(not N.surveyDue(one,"tv",1001),"event survey retains bounded cadence")
check(N.surveyDue(one,"radio",1001),"radio has its own first evening survey")
local preferred=N.candidate(one,{kind="tv_watch",object=tv,score=20})
check(preferred.score>=60 and preferred.score<75,"evening beats routine hobbies while clinical care and sleep retain priority")
tv.data.media=true
check(not N.candidate(one,{kind="tv_watch",object=tv,score=20}),"physical playback does not masquerade as an archive programme")
tv.data.media=false
two.commands.order="guard"
check(not N.candidate(two,{kind="tv_watch",object=tv,score=20}),"guard does not join")
SC.BaseLife.resident=function(id) if id==one.id then return {role="guard",duty=true} end end
check(not N.mayJoin(one),"a camp guard on shift cannot join under a base-duty order")
SC.BaseLife.resident=nil
SC.BaseLife.guardStatus=function(id) return id==one.id end
check(not N.mayJoin(one),"rotating and all-hands defense can guard a generalist")
SC.BaseLife.guardStatus=nil
check(not N.candidate(one,{kind="radio_setup",object=tv,score=20}),"archive never turns on a receiver for the player")
PN.at(20.1) N.pulse()
check(one.xp==50 and two.xp==0 and PN.player.xp==50,"only eligible native receiver audience learns")
check(one.recipe=="Soup" and PN.player.recipe=="Soup","source recipes use same reception")
local realGlobal=addXp
addXp=function() end
local nativeLearner=PN.actor('sc-native-xp');nativeLearner.record={state={downtime={}}}
PN.members[#PN.members+1]=nativeLearner
check(SC.TVWatching.learn(nativeLearner,'native-xp-lesson','COO+1') and nativeLearner.xp==50,
    "native NPC XP is awarded even when the stock global wrapper silently does nothing")
addXp=realGlobal
local count=#tv.lines N.pulse() check(#tv.lines==count,"same line is never sent twice per receiver")
for minute=7,24 do PN.at(20+minute/60) N.pulse() end
check(one.thought and one.thought.morale==5 and not two.thought,"physical attendance grants capped companion thought")
check(PN.player.bo==70 and PN.player.un==65,"player receives the gentle nightly cap")
check(N.topic(one) and not N.topic(two),"only attendees gain the Talk topic")
check(N.talk(one):find("didn't catch",1,true),"partial viewing cannot claim the whole show")
local before=#tv.lines
PN.grid=false PN.at(20.5) N.pulse() check(#tv.lines==before,"grid loss stops transmitter")
PN.grid=true PN.at(20.8) N.pulse() check(#tv.lines==before+1,"restored grid rejoins current programme")
check(PN.player.bo==70,"power cycling cannot farm mood")
N.reset() N.pulse() check(one.xp==50 and PN.player.xp==50,"cold Lua restore cannot replay a lesson")
check(N.snapshot().tv==snap.tv,"channel identity survives reset")
PN.at(21) N.pulse() before=#tv.lines
PN.at(22) N.pulse() check(#tv.lines==before,"broadcast ends at 21:00")
local media=PN.mediaRow("new-tape","Retail-VHS")
local item={carried=true,getMediaData=function() return media end}
check(N.copy(PN.player,PN.pc,item) and item.carried,"copy expands archive and preserves original item")
check(not N.copy(PN.player,PN.pc,item),"duplicate media IDs do not create archive duplicates")
item.carried=false check(not N.copy(PN.player,PN.pc,item),"stale item reference cannot authorize copying")
item.carried=true PN.pc.power=false check(not N.copy(PN.player,PN.pc,item),"copy completion rechecks PC power")
PN.pc.power=true PN.pc.md.movableData.LF_LarchOS.locked=true
check(not N.copy(PN.player,PN.pc,item),"copy completion rechecks PC lock")
PN.pc.md.movableData.LF_LarchOS.locked=false
check(N.setEnabled(PN.player,PN.pc,false),"explicit schedule control")
PN.at(44.1) N.pulse() check(not N.active(),"disabled night remains silent")
N.setEnabled(PN.player,PN.pc,true) N.pulse()
check(N.active() and #tv.lines>before,"next evening runs automatically")
-- Learning survives the old 2048-line cache being discarded on actor rebuild.
local ledger=PN.stores[N.KEY]
local saved=ledger.viewers[one.id]
check(saved.lessons and PN.any(saved.lessons),"educational receipts are durable per survivor")
local successor=PN.actor() successor.md.LF_HandoverCompanionId=one.id
N.restoreKnowledge(successor)
for guid in pairs(saved.lessons) do check(successor:isKnownMediaLine(guid),"Handover hydrates each native lesson") end
local newcomer=PN.actor()
N.restoreKnowledge(newcomer) check(PN.any(newcomer.known)==nil,"new character starts with own learning history")
check(N.snapshot().discovered and #N.snapshot().library==7,"world archive survives successor change")
tv.data.volume=0 before=#tv.lines PN.at(44.2) N.pulse() check(#tv.lines==before,"muted receiver earns no reception")
tv.data.volume=1 PN.facing=false local xp=PN.player.xp PN.at(44.4) N.pulse()
check(PN.player.xp==xp,"player facing away does not learn")
PN.facing=true PN.player.asleep=true PN.at(44.6) N.pulse()
check(PN.player.xp==xp,"sleeping player does not learn")
PN.player.asleep=false
PN.at(68.1) N.pulse() local prior=PN.player.bo
PN.at(68.8) N.pulse() check(PN.player.bo==prior,"large clock skip grants no retroactive attendance")
PN.at(92.1) N.pulse()
local attendance=PN.stores[N.KEY].viewers[one.id]
check(attendance.minutes==0,"new evening begins without carried attendance minutes")
tv.data.volume=0 PN.at(92.1+1/60) N.pulse()
tv.data.volume=1 PN.at(92.1+2/60) N.pulse()
check(attendance.minutes==0,"a muted minute breaks observed attendance instead of crediting the gap")
PN.media[C.starters[1]]=nil
check(#N.snapshot().library==7,"missing content preserves archive entries")
N.remove() check(not N.isInstalled(),"hook removal owns its callback")
SC.BaseLife.active=function() return nil end
SC.TerminalHardware.state=function() return {radio={}} end
SC.GridControl={visible=function() return true end}
SC.TerminalGridUI,SC.TerminalRadioUI={},{}
local window={player=PN.player,object=PN.pc,system={locked=false},menuPage="home_services_more"}
local services=SC.TerminalServices.menu(window)
local building,archive=false,false
for _,entry in ipairs(services) do
    if entry.serviceValue=="services" then building=true end
    if entry.serviceValue=="power_night" then archive=true end
end
check(building and archive,"grid and radio menus cannot hide Building services or Power Night")
PN.client=true N.reset() check(not N.snapshot().available,"unsupported network worlds stay inert")
SC.TVWatching.valid=originalValid
print("POWER_NIGHT_PASS checks="..PN.checks)
