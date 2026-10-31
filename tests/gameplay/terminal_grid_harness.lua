-- SPDX-License-Identifier: MIT
local SC=SurvivorCompanion
local Brain=SC.TerminalBrain
local checks=0
local function check(value,text) checks=checks+1 assert(value,"terminal grid "..checks..": "..text) end
local function session() return Brain.newSession({operator="Thor",random=function() return 1 end}) end
local snapshot={visible=true,on=false,heat=0,online=0,linked=0,originalShut=26,daysLeft=0,
    nearest={id="muldraugh",label="Muldraugh"},distance=220}
local world={camp=function() return {configured=true,inside=true} end,
    clock=function() return {year=1993,month=6,day=20,hour=12,worldHours=300} end,
    power=function() return {source="generator",fuel=63,condition=91} end,
    grid=function() return snapshot end}
for _,phrase in ipairs({"substation","substations","transformer","restore power","turn the power back on",
    "power back on","connect to grid","connect to the grid","grid control","shutoff date",
    "when does the grid fail","energize grid","grid heat","controller crack"}) do
    local reply=Brain.respond(session(),phrase,world)
    check(reply.intent=="grid_control","grid phrase routes to live controller facts: "..phrase)
    check(table.concat(reply.lines,"\n"):find("Muldraugh",1,true)~=nil,"nearest site has a human-readable name")
end
for _,phrase in ipairs({"power","generator fuel","electricity","how much fuel","grid"}) do
    local reply=Brain.respond(session(),phrase,world)
    check(reply.intent=="power","ordinary power and fuel questions retain their existing handler: "..phrase)
end
world.power=function() return {source="substation"} end
local reply=Brain.respond(session(),"power",world)
check(table.concat(reply.lines," "):find("substation",1,true)~=nil,"EMMA names the controller's own supply")
snapshot.crack={label="Muldraugh",percent=42.5,requiredHours=120,doneHours=51}
reply=Brain.respond(session(),"controller crack",world)
check(table.concat(reply.lines," "):find("42.5%",1,true)~=nil,"query reports actual persisted progress")
snapshot.crack=nil snapshot.on=true snapshot.remainingHours=12.3
reply=Brain.respond(session(),"grid control",world)
check(table.concat(reply.lines," "):find("13 game hours",1,true)~=nil,"running grid reports the heat deadline")
snapshot.on=false snapshot.locked=true snapshot.coolingHours=40
reply=Brain.respond(session(),"grid heat",world)
check(table.concat(reply.lines," "):find("cool completely",1,true)~=nil,"tripped breaker explains the restart lock")
snapshot.standDown="Another program is managing the grid."
reply=Brain.respond(session(),"substation",world)
check(table.concat(reply.lines," "):find(snapshot.standDown,1,true)~=nil,"foreign ownership is explained")
snapshot={visible=false,reason="The power grid never shuts off in this world."}
reply=Brain.respond(session(),"grid control",world)
check(table.concat(reply.lines," "):find("never shuts off",1,true)~=nil,"never-shuts worlds have a readable answer")
SC_TEST_REPORT=(SC_TEST_REPORT or "").."; TERMINAL_GRID_PASS checks="..checks
