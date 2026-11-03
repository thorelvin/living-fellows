-- SPDX-License-Identifier: MIT
-- Legacy readiness is ambiguous; actual dialogue qualifies new pending lines.
local SC,T=SurvivorCompanion,TERMINAL_TEST
local D,L,P,S=SC.TerminalPersonaDiscovery,SC.TerminalLocks,SC.TerminalPersona,SC.TerminalSystem
local check,before=T.check,T.checks
local old={mod=ModData,find=SC.TerminalDrawers.find,debug=isDebugEnabled,config=SCConfig}
local book={} ModData={getOrCreate=function() return book end}
local player=T.player(100,100,0) local pc=T.computer(T.square(100,100,0,true))
local w={player=player,object=pc,world={camp=function() return {inside=true} end}}
local function ordinary()
    w.system=S.create(17,"home",true,false,"migration-emma")
end
local function legacy(mentioned)
    book={persona={boots=7,met={spiffy=true},talked={spiffy=true},
        campReady={spiffy=true},campMentions=mentioned and {spiffy=true} or {}}}
    L.reset() ordinary()
    return L.ledger().persona
end
local migrated=legacy(false)
check(migrated.met.spiffy and migrated.talked.spiffy and not migrated.campReady.spiffy,
    "legacy greeting-only readiness is removed without forgetting the encounter")
check(D.campLine(w)==nil and not D.completeCampLine(w,"spiffy"),
    "legacy pending or already queued SPIFFY line cannot be delivered")
L.reset()
check(not L.ledger().persona.campReady.spiffy,"legacy migration is stable after another reload")

-- Even an already cached legacy ledger must not bypass the new qualification.
L.ledger().persona.campReady.spiffy=true
check(D.campLine(w)==nil and not D.completeCampLine(w,"spiffy"),
    "cached unqualified readiness cannot select or acknowledge a follow-up")
book.persona.spiffyGuest="true" L.reset()
check(not L.ledger().persona.spiffyGuest and D.campLine(w)==nil,
    "a truthy corrupt qualification is not a real dialogue receipt")

local function conversation(name)
    w.system=S.create(17,"home",true,false,"migration-spiffy")
    w.system.locked=true w.system.lock={kind="persona",persona=P.new("spiffy",17)}
    D.remember("spiffy")
    local p=w.system.lock.persona local session=P.session()
    local facts={hours=30,days=2,moodles={}}
    P.respond(p,session,"hello",facts) D.noteConversation(w)
    check(not p.used.name_none,"the greeting has not filed an unnamed guest")
    P.respond(p,session,name,facts) D.noteConversation(w)
    return p
end
legacy(false)
local named=conversation("my name is Ada")
check(named.name=="Ada" and not named.used.name_none,"real named dialogue stays outside the nameless branch")
w.system.locked=false
check(D.campLine(w)==nil,"a named player cannot revive migrated pending readiness")

local guest=conversation("no")
check(not guest.name and (guest.used.name_none or 0)>0,"real name refusal fires the supplied VALUED GUEST line")
check(L.ledger().persona.spiffyGuest==true and L.ledger().persona.campReady.spiffy,
    "verified dialogue requalifies a migrated pending follow-up")
ordinary() L.reset()
check(L.ledger().persona.spiffyGuest==true and D.campLine(w)~=nil,
    "verified pending qualification survives save normalization")
SC.TerminalDrawers.find=function() return nil end isDebugEnabled=function() return false end SCConfig={}
D.settle(S.create(19,"home",false,false,"migration-director"),player,pc,false)
check(L.ledger().persona.spiffyGuest==true and D.campLine(w)~=nil,
    "a later Director decision preserves pending qualification")
check(D.completeCampLine(w,"spiffy"),"verified follow-up is acknowledged once")
L.reset()
check(L.ledger().persona.campMentions.spiffy and D.campLine(w)==nil,
    "verified delivered follow-up cannot repeat after reload")

local delivered=legacy(true)
check(delivered.campMentions.spiffy and D.campLine(w)==nil,
    "legacy delivered receipt survives removal of ambiguous readiness")
L.reset()
check(L.ledger().persona.campMentions.spiffy,"legacy delivered receipt survives repeated normalization")
conversation("no") ordinary() L.reset()
check(L.ledger().persona.spiffyGuest and L.ledger().persona.campMentions.spiffy
    and D.campLine(w)==nil,"later requalification never replays a legacy delivered line")

book={persona={boots=7,met={ellis=true,duty=true},talked={ellis=true,duty=true},
    campReady={ellis=true,duty=true},campMentions={}}} L.reset() ordinary()
local line,id=D.campLine(w)
check(id=="ellis" and D.completeCampLine(w,id),"legacy therapist readiness is unchanged")
line,id=D.campLine(w)
check(id=="duty" and D.completeCampLine(w,id),"legacy officer readiness is unchanged")
book={persona={spiffyGuest=true,talked={spiffy=true},campReady={spiffy=true}}} L.reset()
check(not L.ledger().persona.spiffyGuest and D.campLine(w)==nil,
    "qualification without a recorded encounter is discarded")
ModData,SC.TerminalDrawers.find,isDebugEnabled,SCConfig=old.mod,old.find,old.debug,old.config
L.reset()
SC_TEST_REPORT=SC_TEST_REPORT.."; Persona receipt migration: "..(T.checks-before).." checks passed"
