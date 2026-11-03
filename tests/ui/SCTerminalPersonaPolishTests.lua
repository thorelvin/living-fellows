-- SPDX-License-Identifier: MIT
-- World receipts, speech admission and live power reporting, not engine dialogue.
local SC,T=SurvivorCompanion,TERMINAL_TEST
local D,L,P,S=SC.TerminalPersonaDiscovery,SC.TerminalLocks,SC.TerminalPersona,SC.TerminalSystem
local check,before=T.check,T.checks
local old={mod=ModData,registry=SC.Registry,banter=SC.Banter,dialogue=SC.Dialogue,
    hardware=SC.TerminalHardware,grid=SC.GridControl,find=SC.TerminalDrawers.find,
    debug=isDebugEnabled,config=SCConfig}
local book={} ModData={getOrCreate=function() return book end} L.reset()
local player=T.player(100,100,0) local pc=T.computer(T.square(100,100,0,true))
local camp={inside=true}
local w={player=player,object=pc,world={camp=function() return camp end}}
local function persona(id)
    w.system=S.create(17,"home",false,false,"polish-"..id)
    w.system.locked=true w.system.lock={kind="persona",persona=P.new(id,17)}
    D.remember(id)
    return w.system.lock.persona
end
check(D.recoveryLine()==nil,"unseen stories add no recovery-log hint")
local p=persona("spiffy")
D.noteConversation(w)
check(not L.ledger().persona.talked.spiffy,"blank cursor does not count as a conversation")
p.met,p.spoken=true,1
SC.TerminalPersonaUI.finished(w)
check(L.ledger().persona.talked.spiffy,
    "finished native reply records conversation without forcing an unavailable speaker")
check(D.campLine(w)==nil,"locked persona cannot deliver ordinary EMMA follow-ups")
w.system.locked=false camp.inside=false
check(D.campLine(w)==nil and not book.persona.campMentions.spiffy,"outside camp preserves pending follow-up")
camp.inside=true w.world.camp=function() error("unknown camp") end
check(D.campLine(w)==nil and not book.persona.campMentions.spiffy,"failed camp lookup is not access")
w.world.camp=function() return camp end
local followup,followupId=D.campLine(w)
check(followup:find("valued guest",1,true)~=nil and not book.persona.campMentions.spiffy,
    "queuing a follow-up does not consume it before typing finishes")
camp.inside=false
check(not D.completeCampLine(w,followupId) and not book.persona.campMentions.spiffy,"camp access is revalidated before confirming the line")
camp.inside=true w.rows={}
SC.Terminal.Window.pushRow(w,"","emma",{text="",personaFollowup=followupId})
check(book.persona.campMentions.spiffy and D.campLine(w)==nil,"finished transcript row acknowledges the follow-up exactly once")
local recovered=L.recovery()
check(recovered:find("Recovery log: 0/",1,true) and recovered:find("questions of their own",1,true)
    and not book.seen.persona and not book.beaten.persona,"hint preserves ordinary recovery target and ledger")
local target=#L.requiredKinds()
for _,id in ipairs({"ellis","duty"}) do
    p=persona(id) p.met,p.spoken=true,2 D.noteConversation(w) w.system.locked=false
    check(D.campLine(w)==nil,"outcome follow-up waits for actual "..id.." milestone")
    if id=="ellis" then w.system.lock.effects={reliefDay=4} else p.flags.relieved=true end
    D.noteConversation(w)
    local line,receipt=D.campLine(w)
    check(type(line)=="string" and D.completeCampLine(w,receipt) and D.campLine(w)==nil,"one outcome follow-up for "..id)
end
L.reset()
local reloaded=L.ledger().persona
check(reloaded.talked.spiffy and reloaded.campMentions.ellis and reloaded.campReady.duty
    and D.campLine(w)==nil and #L.requiredKinds()==target,"all three receipts survive cold normalization")
local legacy={persona={boots=3,met={ellis=true},talked={ellis=true,unknown=true},campReady="bad",campMentions={duty=true}}}
D.normalizeLedger(legacy)
check(legacy.persona.met.ellis and legacy.persona.talked.ellis and not legacy.persona.campReady.ellis
    and not legacy.persona.campMentions.duty and not legacy.persona.talked.unknown,"old/corrupt optional receipts normalize conservatively")
SC.TerminalDrawers.find=function() return nil end isDebugEnabled=function() return false end SCConfig={}
D.settle(S.create(19,"home",false,false,"next-boot"),player,pc,false)
check(L.ledger().persona.campMentions.spiffy and L.ledger().persona.campReady.duty,
    "a later fresh-computer Director decision preserves follow-up receipts")

local actor={} local available,budget=true,true local said,spent,registered=0,0,{}
SC.Registry={records=function() return {{recruited=true,actor=actor}} end}
SC.Banter={availableSpeaker=function() return available end,budgetAllows=function() return budget end,
    spendBudget=function() spent=spent+1 end}
SC.Dialogue={has=function(topic) return registered[topic]~=nil end,
    register=function(topic,rows) registered[topic]=rows end,
    say=function(actual,topic) check(actual==actor and registered[topic]~=nil,"speech uses selected companion/topic") said=said+1 return true end}
for _,id in ipairs(P.ORDER) do
    persona(id)
    check(SC.TerminalLockCrew.react(w,"persona_"..id,100),"eligible companion can react to "..id)
    w.system=S.normalize(w.system)
    check(not SC.TerminalLockCrew.react(w,"persona_"..id,100),"reaction cannot repeat after save/reload")
end
check(said==3 and spent==3,"three reactions spend exactly three existing speech-budget slots")
local long="UNDERSTOOD, SIR. I WILL REMAIN AS YOUR ADJUTANT. OLD HABIT. ASK ME FOR A SITREP WHEN YOU WANT ONE."
persona("duty") w.queue,w.rows={},{} w.columns=function() return 12 end
w.wrapTranscript=function(_,value) return SC.Terminal.wrap(value,12) end
w.pushRow=SC.Terminal.Window.pushRow
SC.Terminal.Window.enqueue(w,{long},"emma") SC.Terminal.Window.print(w,long,"emma")
check(#w.queue==1 and w.queue[1].text==long and #w.rows==1 and w.rows[1].text==long,
    "persona text stays intact until measured render wrapping, including streaming")
available=false persona("ellis")
check(not SC.TerminalLockCrew.react(w,"persona_ellis",100) and said==3,"sleeping/busy speakers rejected by existing availability policy")
check(not w.system.lock.reactions.persona_ellis,"unavailable crew does not consume a future reaction")
available=true budget=false persona("spiffy")
check(not SC.TerminalLockCrew.react(w,"persona_spiffy",100) and said==3 and spent==3,"exhausted banter budget cannot produce speech")


check(not w.system.lock.reactions.persona_spiffy,"busy speech budget preserves a later reaction")
budget=true
local visible={}
w.print=function(_,text,kind) visible[#visible+1]={text=text,kind=kind} end
SC.Dialogue.say=function() said=said+1 return true,"The exact spoken line." end
check(SC.TerminalLockCrew.react(w,"persona_spiffy",100),"available crew can retry the same missed opportunity")
check(#visible==1 and visible[1].text:find("nearby: The exact spoken line.",1,true)
    and visible[1].kind=="system","CRT transcript echoes only the line actually emitted")
check(not SC.TerminalLockCrew.react(w,"persona_spiffy",100) and #visible==1,
    "accepted reaction and visible echo remain once-only")

local mounted={on=true} local backup={source="battery",charge=62}
SC.TerminalHardware={state=function() return mounted end,backupPower=function() return backup end}
SC.GridControl={yardSupply=function() return false end}
pc.square.haveElectricity=function() return false end pc.square.hasGridPower=function() return false end
pc.square.room={}
local provider=T.originalWorldNew(player,pc)
check(provider.power().source=="battery" and provider.power().charge==62,"world provider reports a live backup without a generator survey")
local brain=SC.TerminalBrain
local text=table.concat(brain.boot(brain.newSession({name="Thor"}),provider).lines,"\n")
check(text:find("battery backup, charge 62%",1,true)~=nil,"ordinary EMMA boot displays actual backup charge")
mounted.on=false check(provider.power().source=="off","off switch wins over installed backup")
mounted.on=true backup=nil check(provider.power().source=="none","absent/depleted backup does not claim power")
pc.square.hasGridPower=function() return true end
check(provider.power().source=="grid","real grid has priority over backup")
SC.GridControl.yardSupply=function() return true end
check(provider.power().source=="substation","existing substation label keeps priority over its powered native square")

ModData,SC.Registry,SC.Banter,SC.Dialogue=old.mod,old.registry,old.banter,old.dialogue
SC.TerminalHardware,SC.GridControl=old.hardware,old.grid
SC.TerminalDrawers.find,isDebugEnabled,SCConfig=old.find,old.debug,old.config
L.reset()
SC_TEST_REPORT=SC_TEST_REPORT.."; Persona polish: "..(T.checks-before).." checks passed"
