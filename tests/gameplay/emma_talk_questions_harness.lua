-- SPDX-License-Identifier: MIT
local SC=LivingFellows
local B,C,F=SC.TerminalBrain,SC.EmmaConversation,SC.EmmaTalkPolishFixture
local checks=0
local function check(ok,why) checks=checks+1 assert(ok,why) end
local function fresh() return B.newSession({operator="Test",random=function() return 1 end}) end
local world=F.world()
for _,answer in ipairs({"hurt","wounded","injured","hungry","starving","hunted","chased","heartsick","lonely"}) do
    local s=fresh() B.respond(s,"please help",world)
    check(s.context.expect and s.context.expect.kind=="help_me","help question declares its answer kind")
    local r=B.respond(s,answer,world)
    check(r.intent=="guide" or r.intent=="hunted" or r.intent=="comfort","help answer routes: "..answer)
    check(not s.context.expect,"expectation consumed exactly once")
end
do
    local s=fresh() B.respond(s,"please help",world) B.respond(s,"weather",world)
    check(not s.context.expect,"unrelated question expires help expectation")
    local original=C.begin
    C.begin=function() end
    local changed=fresh() B.respond(changed,"please help",world)
    local r=B.respond(changed,"heartsick",world)
    C.begin=original
    check(r.intent~="comfort","negative control detects removal of answer resolver")
end
for answer in pairs(C.yes) do
    local s=fresh() s.context.pending={intent="weather",slots={}}
    check(B.respond(s,answer,world).intent=="weather","pending yes executes suggestion: "..answer)
end
for answer in pairs(C.no) do
    local s=fresh() s.context.pending={intent="weather",slots={}}
    local r=B.respond(s,answer,world)
    check(r.intent=="did_you_mean_no" and F.text(r):find("try:",1,true),"pending no helps: "..answer)
end
do
    local s=fresh() s.context.pending={intent="weather",slots={}}
    B.respond(s,"who is hurt",world)
    check(not s.context.pending,"unrelated known intent expires a suggestion")
    check(B.respond(s,"yes",world).intent~="weather","stale yes cannot run an old suggestion")
end
for _,raw in ipairs({"nonsensexyz","nonsensexyz","what?","unhandledzz","otherunhandledzz"}) do
    local s=fresh() local r=B.respond(s,raw,world)
    if r.intent=="fallback" or r.intent=="fallback_echo" or r.intent=="did_you_mean" then
        check(F.text(r):find("try:",1,true),"every miss offers a way forward")
        check(not F.text(r):find("was that english",1,true),"valid words never mocked")
    end
end
do
    local s=fresh() local menus=0
    for n=1,6 do
        local r=B.respond(s,"unhandledzz",world)
        if F.text(r):find("topics:",1,true) then menus=menus+1 end
    end
    check(menus==1,"compact menu appears once per session")
    check(C.distance("generstor","generator")<C.distance("generptor","generator"),"QWERTY substitution is cheaper")
    check(C.distance("generstor","generator")<1,"near-key correction remains confident")
end
for _,id in ipairs({"spiffy","ellis","duty"}) do
    local p,s=SC.TerminalPersona.new(id,11),SC.TerminalPersona.session()
    SC.TerminalPersona.respond(p,s,"Hi",F.facts())
    SC.TerminalPersona.respond(p,s,"Password?",F.facts())
    check(p.name~="Password","question is never captured as a name: "..id)
    local original=SC.TerminalPersona.captureName
    -- A direct name-reader control proves the test can distinguish the old
    -- two-word name capture from the guarded conversation path.
    check(original({"password"}," password ")==nil,"known command is not a name")
end
SC_TEST_REPORT=(SC_TEST_REPORT or "").."\nEMMA_QUESTIONS_PASS checks="..checks
