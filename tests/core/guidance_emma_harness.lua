-- SPDX-License-Identifier: MIT
local SC=SurvivorCompanion
local B=SC.TerminalBrain
local offered,enabled=false,true
SC.Guidance={enabled=function() return enabled end,offerShortVersion=function()
    if offered or not enabled then return false end;offered=true;return true
end}
local world={object={},camp=function() return {configured=true,inside=true} end,
    people=function() return {} end,clock=function() return {worldHours=3} end,
    power=function() return {source="grid"} end,grid=function() return {visible=false} end}
local function session() return B.newSession({operator="Thor",random=function() return 1 end}) end
local function has(reply,text) return table.concat(reply.lines,"\n"):find(text,1,true)~=nil end
local s=session()
assert(has(B.boot(s,world),"short version"),"first session offers the short tour")
local reply=B.respond(s,"yes",world)
assert(#reply.lines==5 and has(reply,"who is hurt") and not has(reply,"open radio"),"camp tour has five true commands and no imaginary hardware")
assert(not has(B.boot(session(),world),"short version"),"another computer does not repeat the install-wide offer")
offered=false;local n=session();B.boot(n,world)
assert(has(B.respond(n,"n",world),"Type 'help'"),"the existing Y/N conversation accepts a refusal")
offered=false;local out=session();world.camp=function() return {configured=true,inside=false} end;B.boot(out,world)
reply=B.respond(out,"y",world)
assert(not has(reply,"who is hurt") and not has(reply,"marked supplies"),"away terminals never advertise camp-only queries as local access")
assert(has(reply,"Camp records are available only"),"away tour explains the real access boundary")
offered=false;world.camp=function() return {configured=true,inside=true} end
SC.TerminalHardware={state=function() return {radio={}} end}
SC.BuildingControls={panel=function() return {} end,connected=function() return true end}
world.grid=function() return {visible=true} end
local equipped=session();B.boot(equipped,world);reply=B.respond(equipped,"yes",world)
assert(has(reply,"open radio") and has(reply,"Discover building") and has(reply,"LARCH/GRID"),"reachable installed services are included")
offered=false;enabled=false
assert(not has(B.boot(session(),world),"short version"),"tips off also silences EMMA's teaching offer")
print("GUIDANCE_EMMA_KAHLUA_PASS")
