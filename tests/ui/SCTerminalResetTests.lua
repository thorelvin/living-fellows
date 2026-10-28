-- SPDX-License-Identifier: MIT
-- Single-machine destructive requests must stay explicit, local and portable.
local SC, T = SurvivorCompanion, TERMINAL_TEST
local Terminal, Actions = SC.Terminal, SC.TerminalActions
local check, before = T.check, T.checks
local savedMain, savedLife, savedNow = getSpecificPlayer, SC.BaseLife, SC.GameplayUtil.nowMs
local player = T.player(101,100,0)
getSpecificPlayer = function(index) return index == 0 and player or nil end
SC.GameplayUtil.nowMs = function() return T.now end
-- Factory setup is available away from home without granting camp access.
SC.BaseLife = { active=function() return nil end, isInside=function() return false end }
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {} for key, entry in pairs(value) do result[key] = copy(entry) end
    return result
end
local function send(window, raw)
    window:setFocusMode("chat") window.entry:setText(raw) window:submit()
    if Terminal.window == window then window:flush() end
end
local function open(computer)
    check(Terminal.open(player,computer), "reset fixture opens")
    local window=Terminal.window window:flush() return window
end
local computer=T.computer(T.square(100,100,0,true))
local state=SC.TerminalSystem.create(9999,"office",false,true,"factory-test","Fossil")
state.brand,state.theme,state.xpAwarded,state.paletteVersion="Fossil","purple",true,SC.TerminalPresentation.PALETTE_VERSION
computer.data.movableData={ [SC.TerminalSystem.MEMORY_KEY]=state }
local window=open(computer)
send(window,"remember the spare key is upstairs")
send(window,"call me Morgan")
send(window,"how many nails")
local oldSession,oldState=window.session,window.system
local hardware={radio={id=123,charge=.62},ups={id=456,charge=.4}}
computer.data.movableData.LF_TerminalHardware=hardware
computer.data.movableData.otherMod={keep=true}
computer.data.otherMod={keep=true}
local other=T.computer(T.square(100,101,0,true))
local otherState=Terminal.computerState(player,other)
local otherSession=Terminal.sessionFor(player,other)
otherSession.notes={"Keep this note"}
Terminal.writeMemory(other,otherSession,T.hours)

send(window,"factory reset")
check(window.requestTicket and window.system==oldState and window.session==oldSession,
    "asking outside camp only proposes a reset")
local prompt={} for _,row in ipairs(window.rows) do prompt[#prompt+1]=row.text end
check(table.concat(prompt," "):find("Permanently erase",1,true) and table.concat(prompt," "):find("[Y/N]",1,true),
    "confirmation discloses the permanent local wipe")
send(window,"n")
check(not window.requestTicket and #Terminal.readMemory(computer).notes==1,"no preserves notes and system")
send(window,"factory reset") send(window,"time") send(window,"yes")
check(window.system==oldState and #Terminal.readMemory(computer).notes==1,"another question cancels the wipe")
send(window,"factory reset") local ticket=window.requestTicket
T.now=T.now+Actions.TTL_MS+1 send(window,"y")
check(Terminal.window==window and window.system==oldState and Actions.execute(window,ticket)==false,
    "expired reset is consumed without clearing anything")
send(window,"factory reset") ticket=window.requestTicket
computer.square.generatorPower=false
check(Actions.execute(window,ticket)==false and window.system==oldState,"power is rechecked at confirmation")
computer.square.generatorPower=true window:cancelRequest()
send(window,"factory reset") ticket=window.requestTicket player.x=110
check(Actions.execute(window,ticket)==false and window.system==oldState,"walking away invalidates reset")
player.x=101 window:cancelRequest()
send(window,"factory reset") ticket=window.requestTicket oldState.locked=true
check(Actions.execute(window,ticket)==false and #Terminal.readMemory(computer).notes==1,"locked machines cannot be wiped")
oldState.locked=false window:cancelRequest()
send(window,"factory reset") ticket=window.requestTicket
local replacement=copy(oldState)
window.system=replacement computer.data.movableData[SC.TerminalSystem.MEMORY_KEY]=replacement
check(Actions.execute(window,ticket)==false,"a newly bound system cannot inherit a prior reset confirmation")
window.system=oldState computer.data.movableData[SC.TerminalSystem.MEMORY_KEY]=oldState window:cancelRequest()
send(window,"factory reset") ticket=window.requestTicket
send(window,"yes")
local fresh=Terminal.window
check(window.closed and fresh and fresh~=window and fresh.state=="booting","confirmed wipe reopens the actual boot screen")
check(Actions.execute(fresh,ticket)==false,"confirmation is consumed exactly once")
check(fresh.system.archive=="_factory" and fresh.system.brand=="_camp" and fresh.brand=="_camp",
    "clean machine has no previous owner or firm logo even outside camp")
check(fresh.system.theme=="purple" and fresh.system.seed==oldState.seed
    and fresh.system.identity==oldState.identity and fresh.system.xpAwarded,"physical identity, colour and earned XP persist")
check(not fresh.session and not computer.data[Terminal.MEMORY_KEY]
    and not computer.data.movableData[Terminal.MEMORY_KEY],"both legacy and portable user memory are erased before boot")
check(#fresh.history==0 and #fresh.rows==0 and not fresh.requestTicket,"new window has no old transcript, input or proposals")
check(computer.data.movableData.LF_TerminalHardware==hardware and hardware.radio.charge==.62
    and computer.data.movableData.otherMod.keep and computer.data.otherMod.keep,"mounted parts and unrelated records are preserved exactly")
fresh:flush()
check(fresh.session~=oldSession and #fresh.session.notes==0 and fresh.session.operator~="Morgan"
    and fresh.session.visits==1 and fresh.session.context.item==nil,"new session has fresh visits, name, notes and conversational context")
send(fresh,"files")
check(#fresh:menuOptions()==1 and fresh:menuOptions()[1].systemCommand=="back","empty personal directory keeps a working Back command")
fresh:setFocusMode("menu") fresh.entry:setText("1") fresh:submit() fresh:flush()
check(fresh.menuPage==nil,"keyboard shortcut leaves the empty directory")
check(Terminal.sessionFor(player,other)==otherSession and other.data.movableData[SC.TerminalSystem.MEMORY_KEY]==otherState
    and Terminal.readMemory(other).notes[1]=="Keep this note","other computers retain their exact system, cached session and notes")
fresh:close() Terminal.resetSessions()
-- Native furniture movement serializes movableData; simulate that boundary.
local moved=T.computer(T.square(100,100,0,true))
moved.data.movableData=copy(computer.data.movableData)
fresh=open(moved)
check(fresh.system.archive=="_factory" and fresh.system.brand=="_camp" and fresh.system.theme=="purple"
    and fresh.system.xpAwarded and #fresh.session.notes==0,"pickup/reload cannot rediscover old files, branding or memory")
send(fresh,"remember another note") send(fresh,"factory reset") send(fresh,"y")
fresh=Terminal.window fresh:flush()
check(fresh.system.xpAwarded and fresh.system.identity==oldState.identity and #fresh.session.notes==0,
    "a second reset preserves the one-time XP record and clears only the new user memory")
fresh:close()
getSpecificPlayer,SC.BaseLife,SC.GameplayUtil.nowMs=savedMain,savedLife,savedNow
print("TERMINAL_FACTORY_RESET_PASS checks="..(T.checks-before))
SC_TEST_REPORT=(SC_TEST_REPORT and SC_TEST_REPORT.."; " or "").."Factory reset: "..(T.checks-before).." checks passed"
