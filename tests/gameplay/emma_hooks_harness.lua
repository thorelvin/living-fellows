-- SPDX-License-Identifier: MIT
local SC=LivingFellows
local H,B,F=SC.EmmaHooks,SC.TerminalBrain,SC.EmmaTalkPolishFixture
local count=0
local function check(ok,why) count=count+1 assert(ok,why) end
local function fresh() return B.newSession({operator="Test",random=function() return 1 end}) end
local function text(r) return F.text(r) end
local world=F.world()
do
    local salient=H.salient
    local calls=0
    H.salient=function(line)
        calls=calls+1
        return salient(line)
    end
    local session=fresh()
    local reply=B.respond(session,"what time is it",world)
    check(reply.intent=="time" and session.context.replyHooks,"first question returns a tracked time reply")
    check(calls>0 and calls<=#reply.lines,"first reply only extracts hooks for its own lines")

    local entry=SC.TerminalLore.reference("knox_exclusion")
    local archiveReply={intent="lore",lines={entry.text}}
    calls=0
    H.record(fresh(),archiveReply)
    check(calls==1 and archiveReply.hooks["quarantine zone"]=="lore:knox_exclusion",
        "an authored archive line preserves its aliases on first use")
    H.record(fresh(),archiveReply)
    check(calls==1,"the same authored line reuses its extracted hooks across sessions")
    H.salient=salient
end
local catalog=H.catalog()
check(#catalog>700,"complete public authored catalog is indexed")
local domains={}
for _,row in ipairs(catalog) do
    domains[row.source:match("^[^:]+")]=true
    check(#H.lint(row)==0,"uncovered hooks in "..row.source..": "..table.concat(H.lint(row),", "))
end
for _,id in ipairs({"emma","lore","spiffy","ellis","duty"}) do check(domains[id],"hook catalog covers "..id) end
local probe={text="A note about UnchartedProbeTerm and a memory fault.",hooks={}}
check(#H.lint(probe)>=2,"lint detects capitalised and curated salient terms")
probe.closed=true check(#H.lint(probe)==0,"explicit closed line is permitted")
do
    local row
    for _,candidate in ipairs(catalog) do if candidate.hooks.state then row=candidate break end end
    local old=row.hooks.state row.hooks.state=nil
    check(#H.lint(row)>0,"removing a real declared hook fails the lint")
    row.hooks.state=old
end
for _,input in ipairs({"state?","what state","what's state","explain state","tell me about state","state is what"}) do
    local s=fresh()
    H.record(s,{intent="her_origin",category="chat",lines={"The state ran out of money before version one."}})
    local reply=B.respond(s,input,world)
    check(text(reply):find("kentucky",1,true),"reply hook catches fragment: "..input)
end
do
    local s=fresh()
    H.record(s,{intent="her_origin",category="chat",lines={"The state ran out of money before version one."}})
    local r=B.respond(s,"how do i make bandages",world)
    check(r.intent~="hook_detail" and r.intent~="followup_clarify","complete own-subject question beats stale hooks")
    B.respond(s,"zombies",world)
    check(B.respond(s,"how do i kill them",world).intent=="guide","known complete intent beats pronoun clarification")
end
for _,input in ipairs({"memory fault?","what's that?","is everything fine?","why?","how?"}) do
    local s=fresh()
    H.record(s,{intent="hello",category="chat",lines={"[MEMORY FAULT AT 0F3A] Everything is fine."}})
    check(B.respond(s,input,world).intent=="hook_detail","glitch hooks: "..input)
end
for _,role in ipairs({"the governor","the president","head of state","a soldier","a doctor","police",
    "a scientist","Knox Telecommunications","a carpenter"}) do
    local s=fresh() local r=B.respond(s,"I'm "..role,world)
    check(r.intent=="session_role" and s.context.role,"role claim routes: "..role)
    check(not r.proposal and not r.command,"role does not grant an action")
    check(not fresh().context.role,"role is session-only")
    check(r.private and not s.context.replyHooks,"role is not copied into public hook or miss logging")
end
for _,intent in ipairs({"remember","callme","notes","recall","whoami","comfort","conversation_history"}) do
    local s=fresh()
    H.record(s,{intent=intent,lines={"PrivateFixtureName has a memory fault."}})
    check(not s.context.replyHooks,"private subject never becomes a public hook: "..intent)
end
for _,condition in ipairs({"hungry","cold","sick","hurt","tired","lost","stuck","hunted"}) do
    local r=B.respond(fresh(),"im "..condition,world)
    check(r.intent=="guide" or r.intent=="hook_condition" or r.intent=="hunted"
        or condition=="tired" and r.intent=="session_kindness" and text(r):find("tiring",1,true),"practical condition: "..condition)
end
for _,line in ipairs(SC.TerminalLines.POOLS.weather_talk) do
    local declared=H.retiredWeather[line]
    for _,row in ipairs(H.weather) do if row.text==line then declared=true end end
    check(declared,"every legacy weather quip is tagged or explicitly retired: "..line)
end
for _,entry in ipairs(SC.TerminalLore.REFERENCE) do
    for _,facet in ipairs({"what","why","how","where","when","who"}) do
        local lines=H.render({hook="lore:"..entry.id,hookFacet=facet})
        check(type(lines[1])=="string" and #lines[1]>20,"lore has honest facet: "..entry.id..":"..facet)
    end
end
do
    local s=fresh()
    H.record(s,{intent="lore",category="lore",lines={"A pencil rests beside the green screen."}})
    check(text(B.respond(s,"pencil?",world)):find("graphite",1,true),"small talk noun has substance")
end
do
    local s=fresh()
    local first=B.respond(s,"tell me about the Knox Event",world)
    local more=B.respond(s,"more",world)
    check(more.intent=="lore" and text(first)~=text(more),"a lore hook continuation advances to a related file")
end
for _,id in ipairs({"spiffy","ellis","duty"}) do
    local p,s=SC.TerminalPersona.new(id,11),SC.TerminalPersona.session()
    SC.TerminalPersona.respond(p,s,"hello",F.facts())
    local r=SC.TerminalPersona.respond(p,s,"im the governor",F.facts())
    check(r.layer=="role" and s.role and not r.effects.drawer,"persona role stays a session claim: "..id)
    if id=="duty" then check(text(r):find("authorisation",1,true),"Duty asks for authorisation") end
end
do
    local p,s=SC.TerminalPersona.new("spiffy",11),SC.TerminalPersona.session()
    p.met=true
    H.recordPersona(s,{rows={{text="Kyle is still clocked in. His Smile Score is excellent."}}},"spiffy")
    check(text(SC.TerminalPersona.respond(p,s,"Kyle?",F.facts())):find("time card",1,true),"SPIFFY explains Kyle")
    H.recordPersona(s,{rows={{text="The Smile Score remains our measure."}}},"spiffy")
    check(text(SC.TerminalPersona.respond(p,s,"Smile score?",F.facts())):find("rating",1,true),"SPIFFY explains his score")
end
local scenarios={
    {{rain=.8,snow=false,fog=0,cloud=.9},{month=6}},
    {{rain=.8,snow=true,fog=0,cloud=.9,temperature=-2},{month=0,hour=14}},
    {{rain=0,snow=false,fog=.8,cloud=.9},{month=3}},
    {{rain=0,snow=false,fog=0,cloud=0,temperature=30},{month=6,hour=14}},
    {{rain=0,snow=false,fog=0,cloud=0,temperature=14},{month=6,hour=2}},
    {{rain=0,snow=false,fog=0,cloud=.8},{month=0}},
    {{rain=0,snow=false,fog=0},{month=6}},
}
local badUnfiltered=false
for _,scenario in ipairs(scenarios) do
    for turn=1,50 do
        local line=H.weatherLine({turns=turn},scenario[1],scenario[2])
        local valid=false
        for _,row in ipairs(H.weather) do if row.text==line then valid=H.weatherMatches(row,scenario[1],scenario[2]) end end
        check(valid,"selected weather agrees with actual conditions")
    end
    for _,row in ipairs(H.weather) do if not H.weatherMatches(row,scenario[1],scenario[2]) then badUnfiltered=true end end
end
check(badUnfiltered,"negative control rejects removing the weather filter")
do
    local original=H.weatherMatches
    H.weatherMatches=function() return true end
    local bad=false
    for _,scenario in ipairs(scenarios) do for turn=1,50 do
        local line=H.weatherLine({turns=turn},scenario[1],scenario[2])
        for _,row in ipairs(H.weather) do
            if row.text==line and not original(row,scenario[1],scenario[2]) then bad=true end
        end
    end end
    H.weatherMatches=original
    check(bad,"production selector fails the truth check when its filter is removed")
end
local s=fresh()
local original=H.resolve
H.record(s,{intent="hello",category="chat",lines={"A Paperclip rests here."}})
local unsupported=B.respond(s,"paperclip?",world)
check(unsupported.intent~="hook_detail" and not text(unsupported):find("a paperclip rests here",1,true),
    "an unsupported public hook falls through without quoting its source")
s=fresh()
H.record(s,{intent="identity",category="chat",lines={"My opinions are developing independently."}})
check(B.respond(s,"opinions?",world).intent=="hook_detail","a supported public hook has a real definition")
H.resolve=function() end
s=fresh()
H.record(s,{intent="identity",category="chat",lines={"My opinions are developing independently."}})
check(B.respond(s,"opinions?",world).intent~="hook_detail","negative control detects removed resolver")
H.resolve=original
SC_TEST_REPORT=(SC_TEST_REPORT or "").."EMMA_HOOKS_PASS checks="..count.." catalog="..#catalog.."\n"
