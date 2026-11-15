-- SPDX-License-Identifier: MIT
local SC=SurvivorCompanion
local B,Q,H,F=SC.TerminalBrain,SC.EmmaContext,SC.EmmaHooks,SC.EmmaTalkPolishFixture
local checks=0
local function check(ok,why) checks=checks+1 assert(ok,why) end
local function fresh() return B.newSession({random=function() return 1 end}) end
local function seed(s,text) H.record(s,{intent="public_context",category="chat",lines={text}}) end
local function text(r) return F.text(r) end
local function ask(s,raw) return B.respond(s,raw,F.world()) end
do
    local s=fresh()
    seed(s,"The reserve means stored generator fuel, kept as a backup supply.")
    ask(s,"reserve")
    check(text(ask(s,"can I drink it")):find("do not drink fuel",1,true),"a known fuel reserve cannot become drinking water")
    seed(s,"The generator is off and empty.")
    local r=ask(s,"run in the shed")
    check(text(r):find("outside",1,true) and text(r):find("fumes",1,true),"a shed is a placement question, not a new loot topic")
    check(not r.command and not r.proposal,"instructions do not operate a generator")
end
do
    local s=fresh()
    seed(s,"I answered about a weapon; you meant a water pump. Its fault is unknown.")
    ask(s,"yes water")
    check(text(ask(s,"handle stuck")):find("water pump",1,true),"correction keeps the pump")
    check(not text(ask(s,"not a gun")):find("shotgun shells",1,true),"negated gun is not a firearms request")
    seed(s,"The clinic note reports a fever, with no diagnosis.")
    check(text(ask(s,"so infected")):find("does not prove",1,true),"a symptom does not establish a diagnosis")
end
do
    local s=fresh()
    local tick=100 s.nowMs=function() return tick end
    seed(s,"The generator is off and empty.")
    tick=tick+SC.TerminalConversation.MAX_IDLE_MS+1
    check(Q.resolve(s,"window open",true)==nil,"public context expires by the existing wall-clock limit")
    check(Q.ground(s,"generator",true)==nil,"the passage reader shares the same idle deadline")
    seed(s,"The generator is off and empty.")
    ask(s,"who are you")
    check(Q.resolve(s,"window open",true)==nil,"an unrelated subject ends the old context")
end
do
    local s=fresh()
    seed(s,"The generator is off and empty.")
    local original=Q.resolve
    Q.resolve=function() end
    local removed=ask(s,"run in the shed")
    Q.resolve=original
    check(not (text(removed):find("outside",1,true) and text(removed):find("fumes",1,true)),
        "removing the real context reader loses the placement answer")
end
do
    local s=fresh()
    ask(s,"sing")
    check(ask(s,"do it").command=="tone","answering the tone offer produces a real UI effect")
    s=fresh() ask(s,"sing") ask(s,"status")
    check(not ask(s,"do it").command,"the tone offer expires after an unrelated turn")
    s=fresh() ask(s,"sing")
    check(not ask(s,"nope").command,"declining a tone cannot play it")
end
do
    for _,voice in ipairs({"spiffy","ellis","duty"}) do
        local p,s=SC.TerminalPersona.new(voice,11),SC.TerminalPersona.session()
        SC.TerminalPersona.respond(p,s,"hello",F.facts())
        local r=SC.TerminalPersona.respond(p,s,"Quinn",F.facts())
        check(p.name=="Quinn" and r.private and not s.replyHooks,"a captured name is not a public hook: "..voice)
        r=SC.TerminalPersona.respond(p,s,"I am the governor",F.facts())
        check(r.private and not r.effects.drawer and not r.effects.unlock,"role is not authorisation: "..voice)
        H.recordPersona(s,{rows={{text="The generator is off and empty."}}},voice)
        r=SC.TerminalPersona.respond(p,s,"run in the shed",{})
        check(text(r):find("outside",1,true) and not r.effects.drawer,"shared reference keeps each voice's access boundary: "..voice)
    end
end
do
    local s=fresh()
    seed(s,"The generator is off and empty.")
    H.record(s,{intent="private_fixture",private=true,lines={"PRIVATE_CONTEXT_NONCE"}})
    check(not s.foregroundReference and not s.context.replyHooks,"private text never enters public reference context")
end
do
    -- Unlisted words and relations must come from the actual public passage,
    -- not a topic-specific table or the test's expected answer.
    local s=fresh()
    seed(s,"A glossary says: 'A beldrin is a hand-operated sorting tray. It has no motor.'")
    local r=ask(s,"Beldrin?")
    check(text(r):find("sorting tray",1,true),"a new own-word hook is grounded in its definition")
    check(not r.command and not r.proposal,"a quoted apparatus cannot become an action")
    r=ask(s,"Motor then?")
    check(text(r):find("no motor",1,true),"an excerpt retains the source's negative qualification")
    check(s.publicPassage and #s.publicPassage.text<=900,"the public passage has a fixed bound")
    check(Q.ground(s,"start the motor",false)==nil,"quoted apparatus instructions cannot consume checked actions")
    check(Q.ground(s,"shotgun",false)==nil,"a new complete reference subject wins over an unrelated passage")
    ask(s,"traps")
    seed(s,"A glossary says: 'A beldrin is a hand-operated sorting tray. It has no motor.'")
    check(text(ask(s,"beldrin")):find("sorting tray",1,true),"a new public source cannot inherit the preceding guide's hook target")
    ask(s,"who are you")
    check(Q.ground(s,"beldrin",false)==nil,"a complete new topic replaces the old passage")
    seed(s,"A glossary says: 'A beldrin is a hand-operated sorting tray.'")
    local saved,planner=Q.ground,SC.EmmaAnswers.answer
    Q.ground=function() end SC.EmmaAnswers.answer=function() end
    r=ask(s,"Beldrin?")
    Q.ground=saved
    SC.EmmaAnswers.answer=planner
    check(not text(r):find("sorting tray",1,true),"removing the real public answer path loses an arbitrary definition")
    seed(s,"A glossary says: 'A beldrin is a hand-operated sorting tray.'")
    H.record(s,{intent="notes",lines={"PRIVATE_PASSAGE_NONCE"}})
    check(not s.publicPassage,"private intent clears the passage even without an optional privacy flag")
    for _,voice in ipairs({"spiffy","ellis","duty"}) do
        local p,ps=SC.TerminalPersona.new(voice,11),SC.TerminalPersona.session()
        p.met=true
        H.recordPersona(ps,{rows={{text="A glossary says: 'A beldrin is a hand-operated sorting tray. It has no motor.'"}}},voice)
        local answer=SC.TerminalPersona.respond(p,ps,"beldrin",{})
        check(text(answer):find("sorting tray",1,true) and not answer.effects.drawer,"each voice grounds an unlisted word without opening a drawer: "..voice)
    end
end
do
    local s=fresh()
    local operator=s.operator
    check(ask(s,"rename you").private,"a machine nickname stays out of public logs")
    local r=ask(s,"I will call you Dot")
    check(r.private and s.operator==operator,"a machine nickname cannot rename the operator")
    r=ask(s,"still the same?")
    check(r.private and text(r):find("same",1,true),"a nickname keeps the programme's identity")
    ask(s,"imagine my face")
    r=ask(s,"accurate?")
    check(r.private and text(r):find("cannot verify",1,true),"an imagined appearance cannot become an observation")
    r=ask(s,"hat and beard")
    check(r.private and not s.publicPassage and not s.context.replyHooks,"a supplied appearance never enters public context")
    seed(s,"You can take the quartermaster's part for this exchange.")
    r=ask(s,"quartermaster reporting")
    check(r.private and not r.command and not r.proposal,"an offered role is conversation, not authority")
    s.conversationCallSign="PRIVATE_CALL_SIGN_NONCE"
    ask(s,"forget our conversation")
    check(not s.conversationCallSign,"forgetting conversation clears its private call sign")
end
do
    for _,voice in ipairs({"spiffy","ellis","duty"}) do
        local p,s=SC.TerminalPersona.new(voice,11),SC.TerminalPersona.session()
        p.met=true
        H.recordPersona(s,{rows={{text="By open I meant open a discussion about storing water, not open a door or operate a machine."}}},voice)
        local r=SC.TerminalPersona.respond(p,s,"Open what?",{})
        check(text(r):find("discussion",1,true) and not r.effects.drawer,"a discussion is not a drawer command: "..voice)
        H.recordPersona(s,{rows={{text="A cold meal doesn't need heating. Bread is one example."}}},voice)
        r=SC.TerminalPersona.respond(p,s,"No stove needed?",{})
        check(text(r):find("no stove",1,true),"shared words survive the small persona spelling dictionary: "..voice)
        H.recordPersona(s,{rows={{text="You can play the radio operator in this conversation. A call sign is an identifier here; no radio link has been established."}}},voice)
        r=SC.TerminalPersona.respond(p,s,"This is operator Kilo calling",{})
        check(r.private and not r.effects.drawer and not r.effects.noise,"a call sign is private conversation: "..voice)
        r=SC.TerminalPersona.respond(p,s,"repeat my call sign",{})
        check(r.private and text(r):find("kilo",1,true) and not s.publicPassage,"a private identifier is recalled without entering public context: "..voice)
    end
end
do
    for _,voice in ipairs({"emma","spiffy","ellis","duty"}) do
        local p=voice~="emma" and SC.TerminalPersona.new(voice,11)
        local s=p and SC.TerminalPersona.session() or fresh()
        if p then p.met=true end
        local function supplied(source)
            if p then H.recordPersona(s,{rows={{text=source}}},voice) else seed(s,source) end
        end
        local function respond(input)
            return p and SC.TerminalPersona.respond(p,s,input,{}) or ask(s,input)
        end
        supplied("First inspect the label, then fill the marked container. No work has been performed.")
        local r=respond("Pour now?")
        local body=text(r)
        check(body:find("inspect",1,true) and body:find("fill",1,true) and body:find("not performed",1,true),"a proposed next step retains the unperformed prerequisite: "..voice)
        check(not r.command and not r.proposal and not (r.effects and r.effects.unlock),"a sequence answer is not dispatched: "..voice)
        supplied("This computer was not built in 1984. Its creation date is unknown.")
        r=respond("Built when?")
        check(not text(r):find("1984",1,true) and text(r):find("no verified creation date",1,true),"a negated date cannot become a creation date: "..voice)
        supplied("An exit is a marked way out. It does not certify an unseen route.")
        r=respond("Exit?")
        check(text(r):find("marked way out",1,true) and not (r.effects and r.effects.close),"a question about a supplied word does not log off: "..voice)
        check(text(r):find("does not certify",1,true),"a definition keeps its adjacent negative qualification: "..voice)
        if p then
            r=respond("exit")
            check(r.layer=="rule" and (r.effects.close or p.expect),"literal exit retains its native leave procedure: "..voice)
        else
            check(Q.resolve(s,"exit",true)==nil,"literal exit cannot be consumed by a public definition")
        end
    end
end
SC_TEST_REPORT=(SC_TEST_REPORT or "").."EMMA_CONTEXT_PASS checks="..checks.."\n"
