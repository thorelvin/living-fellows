-- SPDX-License-Identifier: MIT
local SC,T=SurvivorCompanion,TERMINAL_TEST
local Terminal,check,before=SC.Terminal,T.check,T.checks
local computer=T.computer(T.square(100,100,0,true))
local player=T.player(101,100,0)
check(Terminal.companionAvailable(computer),"a fresh camp desktop does not need a prior player session")
local state=Terminal.computerState(player,computer)
state.locked=false
check(Terminal.companionAvailable(computer),"unlocked powered computer is eligible for ambient use")
state.locked=true
check(not Terminal.companionAvailable(computer),"portable password lock also blocks companion use")
state.locked=false
local saved,yields=SC.ComputerUse,0
SC.ComputerUse={yieldToPlayer=function(object) check(object==computer,"player yields only the selected terminal") yields=yields+1 return true end}
check(Terminal.open(player,computer) and yields==1,"opening the terminal first releases its NPC user")
check(not Terminal.companionAvailable(computer),"an open player window prevents NPC use")
Terminal.window:close()
SC.ComputerUse.yieldToPlayer=function() return false end
check(not Terminal.open(player,computer) and Terminal.window==nil,"failed owner cancellation cannot overlap the player window")
computer.index=-1
check(not Terminal.companionAvailable(computer),"removed computers are excluded before any position read")
computer.index=3
computer.data.movableData="broken"
check(not Terminal.companionAvailable(computer),"malformed portable data fails closed")
computer.data.movableData={[SC.TerminalSystem.MEMORY_KEY]=false}
check(not Terminal.companionAvailable(computer),"corrupt system records are not mistaken for fresh computers")
SC.ComputerUse=saved
SC_TEST_REPORT=SC_TEST_REPORT.."; Companion terminal access: "..(T.checks-before).." checks passed"
