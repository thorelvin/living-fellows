-- SPDX-License-Identifier: MIT
local SC,T=SurvivorCompanion,TERMINAL_TEST
local Terminal,System,check=SC.Terminal,SC.TerminalSystem,T.check
local before=T.checks
local player=T.player(101,100,0)
local function open()
    local pc=T.computer(T.square(100,100,0,true))
    check(Terminal.open(player,pc),"hardening fixture opens")
    local w=Terminal.window w:flush()
    return w,pc
end
local w,pc=open()
w.session.notes={"stale notes"}
local replacement=System.normalize(w.system)
pc.data.movableData[System.MEMORY_KEY]=replacement
local fresh={notes={"fresh notes"},visits=3}
pc.data.movableData[Terminal.MEMORY_KEY],pc.data[Terminal.MEMORY_KEY]=fresh,fresh
w.entry:setText("remember stale overwrite") w:submit()
check(w.closed and Terminal.window==nil,"changed access record closes before processing input")
check(pc.data.movableData[Terminal.MEMORY_KEY]==fresh and fresh.notes[1]=="fresh notes",
    "a stale close cannot overwrite replacement computer memory")
w,pc=open()
pc.custom="Television"
w:watch(T.now+Terminal.WATCH_MS+1)
check(w.closed,"a repurposed object cannot retain a live computer session")
local television=T.computer(T.square(100,100,0,true),"Television")
check(not Terminal.open(player,television) and not Terminal.use(player,television),
    "direct open and queued use require an actual computer")
w,pc=open()
local oldMain=getSpecificPlayer
getSpecificPlayer=function() return T.player(101,100,0) end
w:watch(T.now+Terminal.WATCH_MS+1)
check(w.closed,"replacing the main player invalidates the old operator session")
getSpecificPlayer=oldMain
w,pc=open()
local oldRadio=SC.TerminalRadio
SC.TerminalRadio={leave=function() error("fixture failed radio cleanup") end}
check(pcall(w.close,w) and w.closed and not w.entry.focused and not w.inUI and Terminal.window==nil,
    "radio cleanup failure cannot trap the keyboard or computer window")
SC.TerminalRadio=oldRadio
print("TERMINAL_HARDENING_PASS checks="..(T.checks-before))
SC_TEST_REPORT=SC_TEST_REPORT.."; Terminal hardening: "..(T.checks-before).." checks passed"
