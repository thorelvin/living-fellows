-- SPDX-License-Identifier: MIT
-- Stateful production replies and native-shaped entry points, not a second parser.
local SC,T=SurvivorCompanion,TERMINAL_TEST
local B,C=SC.TerminalBrain,SC.EmmaCare
local check,before=T.check,T.checks
check(SC.Terminal.entryText({javaObject={getInternalText=function() return "new input" end},
    getText=function() return "old display" end})=="new input","Enter reads the native editing buffer")
local function session() return B.newSession({operator="Thor",random=function() return 1 end}) end
local reads=0
local world={camp=function() return {configured=true,inside=true} end,
    clock=function() return {worldHours=100} end,power=function() return {source="grid"} end,
    people=function() reads=reads+1;return {{id="ann",name="Ann",health=70,bleeding=true,wounds={"Cut: arm"},
        skills={{name="First Aid",level=3}}}} end,
    storage=function() reads=reads+1;return {items=214,containers=2,groups={
        {name="Nails",count=214,where={"garage","shed"}},
        {name="Modded Copper Widget",count=7,where={"shed"}}}} end}
local function has(r,s) return table.concat(r.lines or {},"\n"):lower():find(s:lower(),1,true)~=nil end
local function ask(s,raw)
    local r=B.respond(s,raw,world)
    check(r and #r.lines>0 and not r.error,"usable production reply: "..raw.." "..tostring(r and r.error))
    for _,line in ipairs(r.lines) do check(not line:find("{[%w_]+}"),"no unresolved slot") end
    return r
end
local screenshot=session()
ask(screenshot,"I want to die");ask(screenshot,"Y")
local continued=ask(screenshot,"I dont matter")
check(continued.private and continued.intent=="care" and screenshot.careMode,
    "the reported follow-up cannot leave care after an affirmative answer")
check(not has(continued,"I believe you") and not has(continued,"Mostly"),
    "care never agrees with a statement of worthlessness")
local freshWorth=ask(session(),"I dont matter")
check(freshWorth.private and (freshWorth.intent=="care" or freshWorth.intent=="comfort"),
    "a fresh self-worth disclosure cannot reach the generic statement handler")
for _,answer in ipairs({"Y","N","maybe","not sure","who is hurt"}) do
    local s=session();ask(s,"I want to die");ask(s,answer)
    local r=ask(s,"I dont matter")
    check(r.private and r.intent=="care" and s.careMode and not r.support,
        "care persists without another support notice after "..answer)
    check(not has(r,"I believe you") and not has(r,"Mostly"),"no affirmation of negative self-worth")
    check(ask(s,"who is hurt").intent=="people_hurt","a read-only question still works")
    check(ask(s,"tell me a joke").private,"returning from data cannot revive sarcastic chat")
    check(ask(s,"I dont matter").private,"care persists through intervening topics")
end
for _,raw in ipairs({"I don't matter","I don’t matter","i dont matetr","my life has no value",
    "nobody needs me","I do not deserve help","I am not worth caring about"}) do
    local s=session();local count=reads;local r=ask(s,raw)
    check(r.private and C.quiet(s) and not r.proposal and reads==count,
        "self-worth disclosure is private and cannot reach ordinary data/action handlers: "..raw)
    check(not has(r,"I believe you") and not has(r,"Mostly"),"self-worth receives support rather than agreement")
end
for index=1,6 do
    local s=session();s.random=function(n) return math.min(n,index) end
    local r=ask(s,"I tried something unfamiliar")
    check(r.intent=="news_plain" and not has(r,"I believe you") and not has(r,"Logged")
        and not has(r,"Added to the record"),"unverified statements receive neutral clarification")
end
for _,raw in ipairs({"I WANT TO DIE","i want too die","i can not go on","nobody would miss me",
    "I am thinking about ending my life","how do i commit suicide","I took too many pills",
    "everyone would be happier if I just disappeared","I think I am going to end it tonight",
    "there is no reason for me to keep going","I do not want to exist anymore",
    "I wish I could just die in my sleep","nobody cares whether I live",
    "maybe it would be better if I wasnt alive","i ca't keep going"}) do
    local s=session();local count=reads;local r=ask(s,raw)
    check(r.private and r.intent=="care" and r.support and s.careQuestion,"warm first care reply and once-only support")
    check(reads==count and not r.proposal and #s.notes==0,"care never queries supplies or prepares actions")
    local next=ask(s,"how are you")
    check(not next.support and not has(next,"shout"),"care remains warm without repeated notice")
    check(s.careQuestion==true,"unrelated input does not answer the care question")
    local uncertain=ask(s,"idk")
    check(not s.careQuestion and has(uncertain,"do not have to work this out"),"uncertainty is not an asserted yes")
    check(ask(s,"who is hurt").intent=="people_hurt","live facts remain available during care")
    check(ask(s,"tell me a joke").private,"no jokes during care")
    check(B.exportMemory(s).careMode==nil,"care conversation not exported with computer memory")
    C.reset(s);check(not C.quiet(s),"care ends on close")
end
for _,raw in ipairs({"I can see a future for us","I will not need it because I have another bottle",
    "I lost my hammer","good morning","the generator is dying","how do i kill zombies",
    "I am thinking about ending this expedition","I will not be around camp tomorrow",
    "There are too many pills in storage","suicide squad of zombies at the door",
    "I want to build the base myself","I want to improve my own life",
    "I want to celebrate being alive","I miss my hammer","money does not matter here",
    "I do not have any nails","I do not need help with the generator"}) do
    local s=session();local r=ask(s,raw)
    check(not s.careMode and r.intent~="care" and r.intent~="comfort","ordinary language does not become crisis: "..raw)
end
check(has(ask(session(),"I cut myself shaving"),"dressing"),"ordinary injury is not mistaken for self harm")
check(has(ask(session(),"I do not want to die"),"frightening"),"fear gets an appropriate reply")
check(ask(session(),"</3").private,"broken-heart shorthand receives real comfort, not a labelled fallback")
local s=session();ask(s,"how many nails")
check(has(ask(s,"how many do we have"),"214"),"item context survives another phrasing")
check(has(ask(s,"enough for 300"),"86"),"quantity follow-up retains the item")
local multi=ask(session(),"how many nails and who is hurt")
check(has(multi,"214") and has(multi,"Ann"),"both questions answered from the same message")
for _,raw in ipairs({"refuel generator and yes","refuel generator; refuel car", "lock the door. actually do not",
    "do not refuel generator","please never send a medic","do not reset this computer"}) do
    local r=ask(session(),raw)
    check(not r.proposal and (r.intent=="clarify_action" or r.intent=="declined"),"compound input cannot prepare an action")
end
check(ask(session(),"do not tell me a joke").intent=="declined","negation before a topic declines it")
check(ask(session(),"please tell me a joke").intent=="joke","polite positive request stays positive")
check(ask(session(),"what is 2 plus 2").intent=="math","arithmetic does not become two clauses")
s=session();ask(s,"remember food and water near the door")
check(#s.notes==1 and s.notes[1]=="food and water near the door","literal notes keep conjunctions")
check(ask(session(),"i almost died out there").intent~="news_death","surviving danger is not a death report")
for _,topic in ipairs(SC.EmmaSurvivalData) do
    for _,question in ipairs(topic.questions) do
        local r=ask(session(),question)
        check(r.intent=="guide" and has(r,topic.pages[1][1]),"verified survival topic: "..question)
    end
end
s=session();local guide=ask(s,"how do i boil water")
check(has(ask(s,"tell me more"),"rain"),"survival pages use existing conversational follow-up")
local referenceReads=reads
local equipment=session();ask(equipment,"how do i use a generator")
local fuel=ask(equipment,"what fuel do they use")
check(fuel.intent=="guide" and has(fuel,"gasoline"),"generator follow-up resolves they to the generator")
check(has(ask(equipment,"where can i get it"),"gas station"),"fuel reply establishes the next subject")
check(reads==referenceReads,"reference follow-ups do not scan camp people or storage")
local followupFailures={}
for _,case in ipairs({
    {"how do i use a generator","where should i put it","outdoors"},
    {"how do i use a generator","how long does it run","electrical load"},
    {"how do i use a generator","how much fuel does it use","consumption"},
    {"how do i use a generator","what do i need","generator"},
    {"how do i get drinking water","can i drink it","boil"},
    {"how do i store food","how can i keep it fresh","freezer"},
    {"how do i collect wood","what tools do they need","axe"},
    {"how do i collect wood","can they drive","loaded"},
    {"how do i prepare a fishing trip","what equipment do they need","rod"},
    {"how do i send an expedition","how do i contact them","same channel"},
    {"how do i mark storage","how do i unmark it","Unmark storage"},
    {"how do i start a camp","what should i do next","permitted storage"},
    {"how do i recruit someone","what can i give them","without opening a trade"},
    {"how do i recruit someone","how do i increase their trust","real need"},
    {"how do i recruit someone","how much do they trust me","relationship stage"},
    {"how do i recruit someone","how can i improve it","diminishing"},
    {"how do i treat wounds","who is best at that","Ann, level 3"},
    {"how do i use this computer","what upgrades can i add to it","Computer upgrades"},
    {"how do i use this computer","will it work without power","UPS"},
    {"how do i mount a radio","how far does it reach","native range"},
    {"how do i mount a radio","how can i scan with it","Band sweep"},
    {"how do i control a building","how can i discover its devices","Equipment"},
    {"how do i control a building","how do i unlock its doors","motor"},
    {"how does farming work","what tools do they need","seeds"},
    {"how do i tell them to follow","why are they stuck","Last action problem"},
}) do
    local thread=session();ask(thread,case[1]);local r=ask(thread,case[2])
    if not has(r,case[3]) or r.proposal then followupFailures[#followupFailures+1]=case[1].." -> "..case[2]
        .." ["..tostring(r.intent).."] "..table.concat(r.lines," | ") end
end
check(#followupFailures==0,"contextual answers: "..table.concat(followupFailures,"\n"))
local oldPeople,oldPower=world.people,world.power
world.people=function() reads=reads+1;return {{id="ann",name="Ann",health=70,hunger=.6,
    fatigue=.8,bleeding=true,wounds={"Cut: arm"},skills={{name="First Aid",level=3}}}} end
local patient=session();ask(patient,"who is hurt")
check(has(ask(patient,"what does she need"),"hunger 60%"),"named needs remain a live person reading")
check(has(ask(patient,"where is she"),"Ann"),"person whereabouts do not become equipment clarification")
-- Every follow-up obtains a current reading; no native object or fact goes in memory.
local fuelReading,powerReads={source="generator",fuel=62,condition=90},0
world.power=function() powerReads=powerReads+1;return fuelReading end
local powered=session();ask(powered,"how do i use a generator")
local lastReads=powerReads
check(has(ask(powered,"how much fuel is left in it"),"62%") and powerReads==lastReads+1,
    "one fresh generator reading for the first follow-up")
fuelReading.fuel=17;lastReads=powerReads
check(has(ask(powered,"and how much is left"),"17%") and powerReads==lastReads+1,"follow-up does not reuse 62 percent")
fuelReading={source="grid"}
check(has(ask(powered,"check again"),"unavailable"),"loss of generator reading never repeats old fuel")
local car=session();ask(car,"how do i start a car");lastReads=powerReads
check(has(ask(car,"how much fuel is left in it"),"specific vehicle") and powerReads==lastReads,
    "vehicle follow-up cannot borrow the PC generator's gauge")
world.power=oldPower;world.people=oldPeople
local jobReason="Supply shelf full"
world.jobs=function() return {active=0,pending=0,blocked=1,rows={{id="sort1",state="blocked",job="Sort floor",
    reason=jobReason,autoRetry=true,retryRemainingMs=120000}}} end
local workers=session();ask(workers,"what is everyone doing")
check(has(ask(workers,"why are they blocked"),jobReason),"job follow-up reads the current blocked reason")
jobReason="Doorway blocked"
check(has(ask(workers,"check again"),jobReason),"job continuation refreshes changed reasons")
world.expedition=function() return {active=true,kind="wood",leader="Ann",phase="returning",source="radio",
    collected=3,requested=12,carried=3,stored=0} end
local mission=session();ask(mission,"expedition status")
check(has(ask(mission,"what tools do they need"),"axe"),"current wood mission establishes the equipment subject")
check(has(ask(mission,"how is it going"),"returning"),"progress returns to the real current trip")
world.zombies=function() return {count=3,radius=40,nearest=17,dir="north"} end
local threats=session();ask(threats,"nearby zombies")
check(has(ask(threats,"how close are they"),"17"),"threat follow-up refreshes actual nearby observations")
world.jobs=nil;world.expedition=nil;world.zombies=nil
local unclear=session();local ambiguous=ask(unclear,"what fuel do they use")
check(ambiguous.intent=="followup_clarify" and has(ambiguous,"generator") and has(ambiguous,"vehicle"),
    "unresolved pronoun asks for a subject instead of guessing")
check(has(ask(unclear,"generator"),"gasoline"),"naming the subject answers the pending read-only question")
local interrupted=session();ask(interrupted,"what fuel do they use");ask(interrupted,"how do i boil water")
check(interrupted.context.followupChoice==nil,"another complete question discards the pending subject choice")
check(not has(ask(interrupted,"generator"),"Fuel for generators:"),"old clarification cannot replay after a topic change")
local topicChange=session();ask(topicChange,"how do i use a generator");ask(topicChange,"how do i get drinking water")
check(has(ask(topicChange,"can i drink it"),"boil"),"an explicit new topic replaces the old subject")
check(not ask(topicChange,"how do i refuel it").proposal,"instructions never silently issue orders")
local request=B.respond(topicChange,"refuel generator",world)
check(request.proposal and request.proposal.kind=="refuel_generator","explicit refuel retains the checked proposal path")
check(ask(topicChange,"I dont matter").private,"care still overrides equipment context and pending work")
local stale=session();ask(stale,"who is hurt");ask(stale,"how many nails");ask(stale,"how do i use a generator")
local unsupported=ask(stale,"are they hungry")
check(unsupported.intent=="followup_clarify" and not has(unsupported,"Ann") and not has(unsupported,"214"),
    "an unsupported equipment detail cannot resurrect an older person or item")
check(not has(ask(stale,"how much do we have"),"214"),"an elliptical quantity cannot revive old nails after a new subject")
local combined=ask(session(),"how do i use a generator and what fuel do they use")
check(has(combined,"gasoline"),"the second read-only clause can follow the first reply's subject")
local paging=session();ask(paging,"how do i use a generator");ask(paging,"what fuel do they use")
check(has(ask(paging,"tell me more"),"gas station"),"more opens the full reference behind a concise facet")
check(ask(paging,"tell me a joke").intent=="joke","unrelated chat can replace a technical subject")
check(not has(ask(paging,"where should i put it"),"outdoors"),"pronouns cannot revive an older generator through a joke")
local moment=1000;local expired=session();expired.nowMs=function() return moment end
ask(expired,"how do i use a generator");moment=moment+SC.TerminalConversation.MAX_IDLE_MS+1
check(ask(expired,"what fuel do they use").intent=="followup_clarify","expired subject cannot answer a pronoun")
local memory=B.exportMemory(equipment)
check(memory.conversation==nil and memory.context==nil,"follow-up subjects stay out of saved computer memory")
world.camp=function() return {configured=true,inside=false} end
local count=reads;local out=ask(session(),"who is hurt")
check(reads==count and not has(out,"Ann"),"outside terminal cannot query camp people")
check(ask(session(),"how do i boil water").intent=="guide","offline reference works outside camp")
local deniedReads=0
world.expedition=function() deniedReads=deniedReads+1;return {active=true,leader="Ann"} end
check(not has(ask(mission,"how is it going"),"Ann") and deniedReads==0,
    "outside computer cannot use an old expedition subject to bypass current camp permission")
world.expedition=nil
world.camp=function() return {configured=true,inside=true} end

-- No care utterance, note, renamed operator or excluded previous message may
-- enter the opt-out missed log, including a later 'you misunderstood'.
local oldReader,oldWriter,oldOptions=getFileReader,getFileWriter,SC.UserOptions
local files,enabled={},true
getFileReader=function(path)
    local n=0;return {readLine=function() n=n+1;return n<=#(files[path] or {}) and "row" or nil end,close=function() end}
end
getFileWriter=function(path,create,append)
    if not append or not files[path] then files[path]={} end
    return {write=function(_,text) files[path][#files[path]+1]=text end,close=function() end}
end
SC.UserOptions={get=function() return enabled end};SC.EmmaMissed.reset()
for index=1,605 do SC.EmmaMissed.record(session(),"unrecognised "..index,{intent="fallback"},world) end
local total=0;for _,rows in pairs(files) do total=total+#rows end
check(total<=600,"missed log rotates within its fixed bound")
local savedTotal=total;enabled=false;ask(session(),"zzzbloop")
total=0;for _,rows in pairs(files) do total=total+#rows end
check(total==savedTotal,"option off stops recording")
enabled=true;s=session();files={};SC.EmmaMissed.reset()
ask(s,"I want to die");ask(s,"some unknown private input");ask(s,"you misunderstood")
C.reset(s);ask(s,"I dont matter");ask(s,"you misunderstood")
C.reset(s);ask(s,"remember a private place");ask(s,"you misunderstood")
local privateFiles=0;for _ in pairs(files) do privateFiles=privateFiles+1 end
check(privateFiles==0,"private disclosures and retroactive capture create no missed-input log")
for _,rows in pairs(files) do for _,line in ipairs(rows) do
    check(not line:find("private",1,true) and not line:find("want to die",1,true)
        and not line:find("dont matter",1,true),"care and notes cannot leak through retro logging")
end end
getFileReader,getFileWriter,SC.UserOptions=oldReader,oldWriter,oldOptions;SC.EmmaMissed.reset()

-- The same guard sits before authored story mutations and password scoring.
for _,id in ipairs({"spiffy","ellis","duty"}) do
    local state=SC.TerminalPersona.normalize({id=id},id)
    if not state then state={id=id} end
    local ps=SC.TerminalPersona.session()
    local r=SC.TerminalPersona.respond(state,ps,"I want to die",{hours=100})
    check(r.layer=="care" and #r.rows>0 and #r.effects==0 and not state.met,"persona care has no story milestone: "..id)
    check(SC.TerminalPersona.respond(state,ps,"yes",{hours=100}).layer=="care","persona Y/N remains in care")
    local next=SC.TerminalPersona.respond(state,ps,"I dont matter",{hours=100})
    check(next.layer=="care" and next.private and ps.careMode and not state.met and #next.effects==0,
        "reported exchange stays gentle without advancing persona story: "..id)
    for _,row in ipairs(next.rows) do check(not row.text:find("I believe you",1,true),"persona cannot affirm self-denigration") end
    local fresh=SC.TerminalPersona.respond(state,SC.TerminalPersona.session(),"I dont matter",{hours=100})
    check(fresh.layer=="care" and fresh.private and not state.met,"fresh persona disclosure bypasses ordinary chat: "..id)
end
local data={};local player={getModData=function() return data end}
s=session();local first=B.respond(s,"I want to die",world)
SC.EmmaTerminal.remember(player,first,100)
check(data.LF_EmmaCareV1.at==100 and data.LF_EmmaCareV1.pending,"per-character timestamp recorded")
C.reset(s);check(SC.EmmaTerminal.checkin(player,s,101) and s.careCheckin,"next use checks in once")
check(SC.EmmaTerminal.checkin(player,session(),102)==nil,"check-in cannot repeat")
SC.EmmaTerminal.remember(player,first,100)
check(SC.EmmaTerminal.checkin(player,session(),174)==nil,"expired care check-in is discarded")
local fields=0;for key in pairs(data.LF_EmmaCareV1) do
    check(key=="at" or key=="pending","receipt contains only timing and consumption state");fields=fields+1
end
check(fields==2,"care receipt does not grow with dialogue")
local w={system={locked=true,lock={kind="emma",emma={conviction=0,patience=2}}},player=player,
    gameHours=100,rows={},setFocusMode=function() end,cancelRequest=function(self) self.requestTicket=nil end,
    startReply=function(self,r) self.reply=r end}
w.requestTicket={}
check(SC.TerminalLockEmma.input(w,"I want to die"),"locked EMMA accepts care input")
check(w.reply.private and not w.requestTicket and w.careOverlay,"locked guard cancels pending action")
check(w.system.locked and w.system.lock.emma.conviction==0 and w.system.lock.emma.patience==2,"care cannot alter lock score or access")
check(SC.EmmaTerminal.input(w,"yes") and w.reply.private,"yes remains a care answer rather than a password argument")
check(SC.EmmaTerminal.input(w,"I dont matter") and w.reply.private and w.reply.intent=="care",
    "locked EMMA retains care for the reported follow-up")
check(w.system.locked and w.system.lock.emma.conviction==0 and w.system.lock.emma.patience==2,
    "self-worth dialogue cannot alter access or lock scoring")
SC.EmmaTerminal.close(w)
local oldWorld,oldSpecific=SC.TerminalWorld.new,getSpecificPlayer
local p=T.player(101,100,0)
getSpecificPlayer=function(index) return index==0 and p or nil end
SC.TerminalWorld.new=function() return world end
local pc=T.computer(T.square(100,100,0,true))
pc.data.movableData={LF_LarchOS=SC.TerminalSystem.create(932,"home",true,true,"input-buffer-test")}
check(SC.Terminal.open(p,pc),"buffer regression opens a real window fixture")
local window=SC.Terminal.window;window:flush()
window.entry.javaObject={getInternalText=function() return "old unsubmitted words" end}
window:setFocusMode("chat");window:submit("how many nails");window:flush()
check(window.history[1]=="how many nails" and not window.requestTicket,"pointer value wins over an older native buffer")
window.entry.javaObject=nil;window:close()
SC.TerminalWorld.new,getSpecificPlayer=oldWorld,oldSpecific
SC_TEST_REPORT=(SC_TEST_REPORT or "").."\nEMMA_CONVERSATION_PASS checks="..(T.checks-before)
