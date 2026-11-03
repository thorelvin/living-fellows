-- SPDX-License-Identifier: MIT
-- Run the maintained live driver's input phases against the real dialogue engine.
-- Only native entry delivery/completion is adapted; this is not a live-game pass.
local SC,T=SurvivorCompanion,TERMINAL_TEST
local P,D,L,S=SC.TerminalPersona,SC.TerminalPersonaDiscovery,SC.TerminalLocks,SC.TerminalSystem
local probe=SCRealSandboxHarnessProbes.SCCampReleaseProbe
local oldMod=ModData local book={} ModData={getOrCreate=function() return book end} L.reset()
local check,before=T.check,T.checks
local system=S.create(17,"home",true,false,"camp-driver-dialogue")
system.locked=true system.lock={kind="persona",persona=P.new("spiffy",17)}
D.remember("spiffy")
local w={system=system,state="idle",personaSession=P.session()}
local buffer,inputs="",{}
w.setEntryText=function(_,text) buffer=text end
w.entry={javaObject={
    putCharacter=function(_,byte) buffer=buffer..string.char(byte) end,
    onKeyEnter=function()
        inputs[#inputs+1]=buffer
        w.lastReply=P.respond(system.lock.persona,w.personaSession,buffer,{hours=30,days=2,moodles={}})
        D.noteConversation(w) w.state="idle"
    end}}
local H={phase="persona_discovery_camp_greeting",phaseStartedAt=0,campAcceptance={w=w}}
local function phase(name,at) H.phase,H.phaseStartedAt=name,at end
local function assertion(name,okay,detail) check(okay,name..": "..tostring(detail)) return okay end
local function unexpected() error("dialogue input phase performed unrelated native work") end
probe.step(H,2000,assertion,unexpected,phase)
check(H.phase=="persona_discovery_camp_reply" and inputs[1]=="hello","live driver starts with a real greeting")
check(not L.ledger().persona.campReady.spiffy,"live greeting alone cannot queue EMMA's line")
probe.step(H,4000,assertion,unexpected,phase)
check(H.phase=="persona_discovery_camp_guest_reply" and inputs[2]=="no",
    "live driver explicitly refuses the requested name")
probe.step(H,6000,assertion,unexpected,phase)
check(H.phase=="persona_discovery_camp_story_complete" and #inputs==2,
    "live driver verifies the new milestone before closing the machine")
check(not system.lock.persona.name and (system.lock.persona.used.name_none or 0)>0,
    "live driver actually reached the nameless-guest branch")
check(L.ledger().persona.spiffyGuest==true and L.ledger().persona.campReady.spiffy,
    "live driver qualifies the same receipt ordinary EMMA will read")
ModData=oldMod L.reset()
SC_TEST_REPORT=SC_TEST_REPORT.."; Camp probe dialogue: "..(T.checks-before).." checks passed"
