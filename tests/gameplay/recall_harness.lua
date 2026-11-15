-- SPDX-License-Identifier: MIT
local SC=SurvivorCompanion
local R,C,E,T,U,V=SC.Recall,SC.Community,SC.LifeEvents,SC.TestFixture,SC.GameplayUtil,SC.VoiceMemory
local checks,clock,age,month=0,100000,240,6
local function check(ok,why) checks=checks+1 assert(ok,"recall check "..checks..": "..why) end
function getTimestampMs() return clock end
function getGameTime() return {getWorldAgeHours=function() return age end,getMonth=function() return month end,getYear=function() return 1993 end} end
local actors,states,records={},{},{}
for n=1,3 do
    local actor=T.actor("sc-recall-"..n,n+1,1,{recruited=true})
    actor.name=({"June","Sam","Nick"})[n]
    function actor:getDescriptor() return {getForename=function() return self.name end,getSurname=function() return "" end} end
    function actor:isAsleep() return false end
    actors[n]=actor states[n]=SC.Commands.peek(actor)
    states[n].recruited=true states[n].trust=90 states[n].bond=90
    states[n].reveals.background=7
    records[n]={id=U.idOf(actor),actor=actor,recruited=true,runtime={senses={current={threatCount=0}}}}
    T.registry[U.idOf(actor)]=records[n]
end
SC.Registry.records=function() return records end
local a,b,outsider=actors[1],actors[2],actors[3]
local function reset() C.reset() E.reset() SC.Banter.reset() age=240 month=6 clock=100000 end
local function event(kind,extra)
    local fields={participants={U.idOf(a)},witnesses={U.idOf(b)},place="the firehouse",sourceName="June"}
    for k,v in pairs(extra or {}) do fields[k]=v end
    local row=E.observed(kind,a,fields) C.processEvents(32) return row
end
reset()
local row=event("shared_escape")
check(R.context(a,row).evidence.direct and R.context(b,row).evidence.direct,"participant and witness have direct knowledge")
check(R.context(outsider,row)==nil and R.prepare(outsider,{force=true})==nil,"unaware companion cannot recall the event")
local line,receipt=R.prepare(a,{force=true,player=T.player})
check(line and receipt.eventId==row.id and receipt.known,"prepared recall has a specific truthful receipt")
check(not C.tellEvent(U.idOf(a),U.idOf(outsider),row.id,false),"an unspoken account teaches nobody")
check(C.tellEvent(U.idOf(a),U.idOf(outsider),row.id,true),"accepted on-screen telling creates knowledge")
line,receipt=R.prepare(outsider,{force=true})
check(line and receipt.heardFrom==U.idOf(a) and line:find("June",1,true),"heard account retains the named teller")
local saved=C.export() check(C.restore(saved),"told-by receipt persists")
local known,from,fromName=C.knowsEvent(outsider,row)
check(known and from==U.idOf(a) and fromName=="June","saved teller name remains a flat receipt")
local context=R.context(outsider,row)
local own=SC.DiaryText.spokenCandidates(context,SC.RecallLines.pools.escape.packets)
check(#own==0,"a heard account cannot use a witnessed first-hand packet")
reset()
row=event("companion_died",{targetName="Wade",targetId="sc-wade"})
check(C.tellEvent(U.idOf(a),U.idOf(outsider),row.id,true,"n"),"a named loss can be told without a date")
local partial=R.context(outsider,row)
check(not partial.evidence.has_when and partial.tokens.when==nil,"an unspoken date is not learned from the ledger")
line,receipt=R.prepare(outsider,{force=true})
check(line and receipt.topic=="recall.heard_undated" and not line:find("earlier today",1,true),"partial account uses an honestly undated packet")
check(C.tellEvent(U.idOf(a),U.idOf(outsider),row.id,true,"t"),"later actual speech can supply the date")
check(R.context(outsider,row).evidence.has_when,"only the later spoken date unlocks dated recall")
check(R.toldFacts({usedTokens={name=true}},partial)=="n","named-token receipt carries exactly the spoken fact")
local fourth=T.actor("sc-recall-unaware",4,1,{recruited=true})
check(not C.tellEvent(U.idOf(outsider),U.idOf(fourth),row.id,true,"nt") and R.context(fourth,row)==nil,
    "hearsay cannot seed another first-hand account")
reset()
row=event("shared_escape")
local originalKnown=C.knowsEvent C.knowsEvent=function() return false end
check(R.prepare(a,{force=true})==nil,"knowledge-removal negative control blocks the real selector")
C.knowsEvent=originalKnown
check(R.when(row)=="earlier today","same-day date")
age=age+24 check(R.when(row)=="yesterday","yesterday date")
age=age+72 check(R.when(row)=="a few days back","several-day date")
age=age+144 check(R.when(row)=="last week","last-week date")
age=age+240 month=8 check(R.when(row)=="back when it was still summer","season uses an observed event month")
row.month=nil check(R.when(row)=="a few weeks back","missing month never invents a season")

reset()
local function building(x)
    return {getDef=function() return {getX=function() return x end,getY=function() return 10 end,
        getW=function() return 8 end,getH=function() return 6 end} end}
end
a.square.building=building(10)
function a.square:getBuilding() return self.building end
local key=SC.Tales.placeKey(a)
check(key=="b:10:10:8:6","stable building bounds form the place key")
row=event("shared_escape",{placeKey=key})
local choice=R.pick(a,{force=true})
check(choice and choice.trigger=="place" and choice.row.id==row.id,"same building offers a place memory")
R.note(a,{known=true,eventId=row.id,placeKey=key})
check(R.pick(a,{force=true}).trigger~="place","a place trigger is consumed only after delivery")
a.square.building=building(90) R.observePlace(a)
check(SC.Tales.placeKey(a)~=key and R.pick(a,{force=true}).trigger~="place","same room label in a different building does not match")
a.square.building=building(10) R.observePlace(a)
check(R.pick(a,{force=true}).trigger=="place","returning to the actual building triggers again")
local placeReader=SC.Tales.placeKey SC.Tales.placeKey=function() return nil end R.reset()
check(R.pick(a,{force=true}).trigger~="place","place-match removal negative control loses the return trigger")
SC.Tales.placeKey=placeReader a.square.building=nil

for _,kind in ipairs({"companion_died","first_camp_night"}) do
    reset()
    row=event(kind,{targetName="Wade",targetId="sc-wade"})
    age=age+7*24
    choice=R.pick(a,{force=true})
    check(choice and choice.trigger=="anniversary","week anniversary: "..kind)
    R.note(a,{known=true,eventId=row.id,anniversaryKey=choice.anniversaryKey})
    check(R.pick(a,{force=true}).trigger~="anniversary","anniversary is once per recipient/window")
    age=age+23*24 choice=R.pick(a,{force=true})
    check(choice and choice.trigger=="anniversary","month anniversary: "..kind)
end
reset()
local older=event("shared_escape") age=age+8*24
local newer=event("shared_escape")
choice=R.pick(a,{force=true})
check(choice and choice.trigger=="similar" and choice.row.id==older.id,"new close call brings back an older actual escape")
R.note(a,{known=true,eventId=older.id,similarKey=choice.similarKey})
check(R.pick(a,{force=true}).trigger~="similar","similarity prompt is not repeated throughout the whole day")
local sawOlder=false
for n=1,20 do
    local result,_,_,_,proof=SC.Relationship.respond("memory",a,T.player,states[1],{})
    if proof and proof.eventId==older.id then sawOlder=true end
    if proof then
        SC.Dialogue.emitResolved(a,proof.topic,result,{evidence=proof,recall=true}) R.note(a,proof)
    end
    clock=clock+1000 age=age+.01
end
check(sawOlder,"Talk Memory can choose an older weighted memory instead of always the newest")
local empty=C.export() empty.history={} empty.landmarks={}
check(C.restore(empty) and R.prepare(a,{force=false})==nil,"restoring another history invalidates cached rows immediately")

reset()
row=event("rescued_player",{targetId="player:local",outcome="unknown"})
check(R.prepare(a,{force=true})==nil,"an old rescue label cannot invent a grabbed/downed release")
row=event("rescued_player",{targetId="player:local",wasDowned=true,outcome="freed_with_cover"})
line,receipt=R.prepare(a,{force=true,player=T.player})
check(line and receipt.eventId==row.id,"observed restriction and accepted cover support the rescue packets")

reset()
local originalSee=U.canSee
U.canSee=function(observer,target) return observer~=b or target~=nil and target.visible~=false end
for n=1,4 do
    local target={visible=n<=2}
    SC.Tales.noteKill(a,target,clock) clock=clock+1000
end
clock=clock+40000 age=age+.3
SC.Tales.update(T.player,records,clock) C.processEvents(32)
local combat
for _,item in ipairs(C.historyRows()) do if item.kind=="combat_encounter" then combat=item end end
check(combat and combat.kills==4 and not C.knowsEvent(b,combat),"partial witness cannot quote the full fight count")
check(C.knowsEvent(a,combat),"confirmed killer can remember the count")
U.canSee=originalSee

reset()
local originalTier=SC.Relationship.tier
local state=states[1]
state.background=SC.Background.initialize("depth",{profession="carpenter",fear="the_dark",value="honesty"})
state.reveals={background=7} state.trust=90 state.bond=90
V.observeTogether(a,true)
for n=1,7*48 do age=age+.5 V.observeTogether(a,true) end
local selected,deep=SC.DeepBackground.prepare(a,state)
check(selected and deep.backgroundReveal=="depth_profession","day seven and trusted tier unlock the profession story")
check(not state.reveals.depth_profession,"preparing a story cannot mark it heard")
SC.DeepBackground.commit(a,deep)
check(state.reveals.depth_profession and SC.DeepBackground.prepare(a,state)==nil,"accepted story is revealed once")
for n=1,23*48 do age=age+.5 V.observeTogether(a,true) end
selected,deep=SC.DeepBackground.prepare(a,state)
check(selected and deep.backgroundReveal=="depth_fear","day thirty unlocks the close-tier fear story")
SC.DeepBackground.commit(a,deep)
for n=1,70*48 do age=age+.5 V.observeTogether(a,true) end
selected,deep=SC.DeepBackground.prepare(a,state)
check(selected and deep.backgroundReveal=="depth_value","day one hundred unlocks the family-tier value story")
state.bond=0 state.trust=0
check(SC.DeepBackground.prepare(a,state)==nil,"time cannot bypass the relationship tier")
local late={"A late line.",clean="A late line.",after_day=100,tier="family"}
check(not SC.VoiceLayers.allowed(late,state),"late layer is locked at low trust")
state.trust=90 state.bond=90 age=50*24
check(not SC.VoiceLayers.allowed(late,state),"high trust cannot bypass the day gate")
age=110*24 check(SC.VoiceLayers.allowed(late,state),"both gates unlock the deeper layer")
check(#SC.DeepBackground.catalogs>=37,"every profession, fear and value has additional past")
SC_TEST_REPORT="RECALL_PASS checks="..checks
