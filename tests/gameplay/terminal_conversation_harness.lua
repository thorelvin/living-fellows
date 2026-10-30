-- SPDX-License-Identifier: MIT
-- Subject identity, ambiguity, recency and fresh facts across real multi-turn
-- exchanges. The provider is mutable so cached answers cannot satisfy these.
local SC=SurvivorCompanion
local B,C=SC.TerminalBrain,SC.TerminalConversation
local checks=0
local function check(value,message) checks=checks+1 assert(value,"conversation "..checks..": "..message) end
local function text(r) return table.concat(r.lines or {},"\n") end
local function has(r,s) return text(r):find(s,1,true)~=nil end
local function session() return B.newSession({operator="Thor",random=function() return 1 end}) end
local stock=214
local roster={
    {id="kate",name="Kate Miller",health=42,bleeding=true,where="at camp, north",morale=31,stress=72,
        hunger=.2,thirst=.3,endurance=.65,fatigue=.9,skills={{name="First Aid",level=6}}},
    {id="bob-f",name="Bob Fisher",health=95,where="at camp, south",skills={{name="Carpentry",level=5}}},
    {id="bob-m",name="Bob Miller",health=100,where="at camp, east"},
}
local calls={people=0,storage=0}
local inside=true
local world={camp=function() return {configured=true,inside=inside} end,
    clock=function() return {year=1993,month=6,day=20,worldHours=300} end,
    people=function() calls.people=calls.people+1 return roster end,
    storage=function() calls.storage=calls.storage+1 return {containers=1,items=stock+50,groups={
        {name="Nails",type="Base.Nails",count=stock,where={"garage shelf"}},
        {name="Screws",type="Base.Screws",count=50,where={"tool crate"}}}} end,
    power=function() return {source="generator",fuel=62,condition=88} end,
    zombies=function() return {count=3,radius=40} end}

local aliases=0
for _,g in ipairs(C.GUIDES) do
    check(#g.pages==2 and #g.questions>=4,"real operating help: "..g.id)
    for _,page in ipairs(g.pages) do for _,line in ipairs(page) do
        check(#line<=240 and not line:find("[^ -~]"),"bounded ASCII operating note "..g.id)
    end end
    for _,question in ipairs(g.questions) do
        local r=B.respond(session(),question,world)
        check(r.intent=="guide" and not r.error and has(r,g.title),question.." -> "..r.intent.." "..text(r))
        check(not r.proposal and not r.command,"operating help never executes a request")
        aliases=aliases+1
    end
end
for _,spec in ipairs(C.CHAT) do
    for _,question in ipairs(spec.exact) do
        local r=B.respond(session(),question,world)
        check(r.intent==spec.id and not r.error and not r.proposal,question.." -> "..r.intent)
    end
end
check(#C.GUIDES>=35 and #C.CHAT>=18 and aliases>=150,"substantial practical and conversational coverage")
for _,q in ipairs({"Emma, please how do I start a camp?","how can we start a camp","how can i start a camp","how do i strt a camp"}) do
    check(B.respond(session(),q,world).intent=="guide","polite, plural and conservative typo help: "..q)
end
for _,pair in ipairs({{"how do i label containers","storage"},{"how can we gather wood","wood"},
    {"how to find broadcasts","scanner"},{"how do i enable the lights","lights"},
    {"where can i change jobs","jobs"},{"how do i give a wound some bandages","medicine"}}) do
    local r=B.respond(session(),pair[1],world)
    check(r.intent=="guide" and has(r,C.guide(pair[2]).title),"flexible instructions: "..pair[1].." -> "..r.intent)
end

local s=session()
B.respond(s,"how many nails",world)
B.respond(s,"thank you",world)
local r=B.respond(s,"where are they?",world)
check(r.intent=="storage" and has(r,"214 nails") and has(r,"garage shelf"),"thanks preserves item and location")
local prior=calls.storage
stock=220
r=B.respond(s,"check again",world)
check(has(r,"220 nails") and calls.storage==prior+1,"refresh reads live inventory once")
r=B.respond(s,"is that enough?",world)
check(has(r,"How many do you need?") and not has(r,"covers that amount"),"no invented construction requirement")
r=B.respond(s,"enough for 250",world)
check(has(r,"you need 30 more"),"follow-up target compares current quantity")
r=B.respond(s,"is that enough for 250",world)
check(has(r,"you need 30 more"),"a complete natural comparison retains the item")
stock=240
r=B.respond(s,"how many more?",world)
check(has(r,"you need 10 more"),"comparison target retained; stock is refreshed")
r=B.respond(s,"and for 1,000?",world)
check(has(r,"you need 760 more"),"comma-formatted quantities are not misread as one")
r=B.respond(s,"and screws?",world)
check(has(r,"50 screws") and not has(r,"760 more"),"new item clears the old requirement")
r=B.respond(s,"no, I meant nails",world)
check(has(r,"240 nails"),"a subject correction does not become an item named meant")
r=B.respond(s,"inventory",world)
check(has(r,"2 different") or has(r,"items") and not has(r,"50 screws in camp storage"),"explicit overview is not a pronoun")
check(C.quantity("enough for 1e309")==nil and C.quantity("enough for 1000001")==nil,"invalid targets do not become numeric prefixes")
check(C.quantity("enough for -5")==nil and C.quantity("enough for 2.5")==nil and C.quantity("enough for 1,2")==nil,
    "negative, fractional and malformed grouped targets are not silently changed")

s=session()
B.respond(s,"how is Kate",world)
B.respond(s,"thanks",world)
r=B.respond(s,"how tired is she",world)
check(r.intent=="person" and has(r,"tiredness 90%") and has(r,"stamina 65%"),"person needs survive an acknowledgement")
r=B.respond(s,"what is she good at",world)
check(has(r,"First Aid: level 6"),"skill follow-up stays with the same person")
r=B.respond(s,"is she stressed",world)
check(has(r,"morale 31") and has(r,"stress 72"),"mood follow-up uses actual readings")
r=B.respond(s,"send medic to her",world)
check(r.proposal and r.proposal.kind=="medic" and r.proposal.query=="Kate Miller","explicit pronoun request only proposes care")
r=B.respond(s,"check again",world)
check(not r.proposal and r.intent=="person","a refresh cannot replay the medic request")
B.respond(s,"who is hurt",world)
r=B.respond(s,"where is she",world)
check(r.intent=="person" and has(r,"Kate Miller"),"one reported patient supplies an unambiguous subject")

s=session()
r=B.respond(s,"where is Bob",world)
check(r.intent=="clarify_person" and has(r,"Bob Fisher") and has(r,"Bob Miller"),"shared first name asks rather than picking one")
r=B.respond(s,"the second one",world)
check(r.intent=="person" and has(r,"Bob Miller"),"ordinal selection resolves against the current roster")
r=B.respond(s,"where is Bob Fisher",world)
check(r.intent=="person" and has(r,"Bob Fisher"),"full name resolves shared first and last names")
r=B.respond(session(),"where is Miler",world)
check(r.intent=="clarify_person","a fuzzy tie is not dictionary-order actor selection")
B.respond(s,"where is Bob",world)
B.respond(s,"yes",world)
check(s.context.personChoices~=nil,"yes does not silently select an ambiguous actor")
r=B.respond(s,"1",world)
check(r.intent=="person" and has(r,"Bob Fisher"),"a number typed in chat can select a clarification")
B.respond(s,"who is here",world)
r=B.respond(s,"is she hurt",world)
check(r.intent=="clarify_person","a group does not invent a singular subject")

s=session()
B.respond(s,"how is Kate",world)
local saved=roster[1]
roster[1]={id="different-kate",name="Kate Miller",health=100}
r=B.respond(s,"where is she",world)
check(r.intent=="conversation_missing" and not has(r,"health 100"),"reused name cannot replace remembered actor identity")
r=B.respond(s,"treat her",world)
check(not r.proposal and r.intent=="conversation_missing","a removed patient is not used by a new proposal")
roster[1]=saved

s=session()
B.respond(s,"how many nails",world)
B.respond(s,"power",world)
r=B.respond(s,"back to nails",world)
check(r.intent=="storage" and has(r,"240 nails"),"return to an earlier item thread")
r=B.respond(s,"go back to the previous topic",world)
check(r.intent=="power" and has(r,"62 percent"),"previous topic restores its read-only query")
r=B.respond(s,"how much fuel does it have",world)
check(r.intent=="power" and not has(r,"nails"),"a generator pronoun does not jump to an older inventory subject")
r=B.respond(s,"what were we talking about",world)
check(r.intent=="conversation_history" and has(r,"how many nails") and not r.proposal,"bounded conversational recap")
B.respond(s,"remember the red key is in the van",world)
B.respond(s,"forget that conversation",world)
check(#C.state(s).topics==0 and #C.state(s).history==0 and #s.notes==1,"forget thread does not erase saved notes")
r=B.respond(s,"where is she",world)
check(r.intent~="person","forget thread removes pronoun subjects")
local exported=B.exportMemory(s,301)
check(exported.conversation==nil and exported.context==nil and exported.notes[1]=="the red key is in the van",
    "temporary threads and requests never enter persistent notes")

s=session()
B.respond(s,"how do i start a camp",world)
r=B.respond(s,"tell me more",world)
check(r.intent=="guide" and has(r,"More > Base") and not r.proposal,"guide follow-up advances to practical detail")
B.respond(s,"thanks",world)
r=B.respond(s,"what do you mean",world)
check(r.intent=="guide" and not r.error,"small acknowledgements preserve help thread")
check(has(r,"end of this operating note"),"guide detail ends rather than pretending to add new information")
s=session()
local joke=B.respond(s,"tell me a joke",world)
r=B.respond(s,"another one",world)
check(r.intent=="joke" and text(r)~=text(joke),"another one varies entertainment instead of counting stock")
s=session()
B.respond(s,"12 * 3",world)
B.respond(s,"thanks",world)
r=B.respond(s,"double it",world)
check(r.intent=="math" and has(r,"72"),"arithmetic can reuse its own last result")
r=B.respond(s,"minus 2",world)
check(r.intent=="math" and has(r,"70"),"arithmetic follow-up chains are pure numeric operations")
check(not B.respond(s,"divide it by 0",world).error,"zero division follow-up remains a finite-answer refusal")
for _,case in ipairs({
    {"plus -2",8}, {"minus -2",12}, {"times -2",-20},
    {"multiply it by 0.5",5}, {"divide it by -0.5",-20}, {"and plus 0.25?",10.25},
}) do
    s=session()
    B.respond(s,"5 + 5",world)
    r=B.respond(s,case[1],world)
    local topic=C.latest(s)
    check(r.intent=="math" and not r.error and topic and topic.value==case[2],
        "arithmetic follow-up preserves signs and decimals: "..case[1].." -> "..text(r))
end
s=session()
B.respond(s,"tell me about Louisville",world)
r=B.respond(s,"is it safe",world)
check(r.intent=="lore" and has(r,"cannot confirm") and not has(r,"3 of them"),"distant-place pronouns do not become local threat scans")

local now=1000
s=B.newSession({operator="Thor",random=function() return 1 end,nowMs=function() return now end})
B.respond(s,"how is Kate",world)
now=now+C.MAX_IDLE_MS-1
check(B.respond(s,"where is she",world).intent=="person","brief absence preserves the subject")
now=now+C.MAX_IDLE_MS+1
r=B.respond(s,"is she hurt",world)
check(r.intent~="person" and s.context.person==nil,"idle expiry clears both new and legacy actor context")
now=1
check(not B.respond(s,"what were we talking about",world).error,"a reversed clock cannot keep an old thread alive")

now=1000
s=B.newSession({operator="Thor",random=function() return 1 end,nowMs=function() return now end})
B.respond(s,"how many nails",world)
now=now+C.MAX_IDLE_MS+1
r=B.respond(s,"how is Bob",world)
check(r.intent=="clarify_person" and s.context.personChoices~=nil,
    "the first question after idle expiry keeps its new clarification")
r=B.respond(s,"2",world)
check(r.intent=="person" and has(r,"Bob Miller"),"a fresh clarification still accepts the chosen person after expiry")
now=now+C.MAX_IDLE_MS+1
r=B.respond(s,"tell me about Louisville",world)
local topic=C.latest(s)
check(r.intent=="lore" and topic and topic.kind=="lore",
    "the first lore question after expiry becomes the new follow-up subject")

s=session()
B.respond(s,"how is Kate",world)
for _=1,C.MAX_AGE+1 do B.respond(s,"ok",world) end
r=B.respond(s,"is she hurt",world)
check(r.intent~="person","person pronouns expire rather than using immortal context")
s=session()
B.respond(s,"tell me about Louisville",world)
r=B.respond(s,"continue",world)
check(r.intent=="lore" and not r.error,"lore-specific continuation wording retains the current archive thread")
for _=1,C.MAX_AGE+1 do B.respond(s,"ok",world) end
check(C.latest(s)==nil,"the old archive subject expires after the bounded turn history")
r=B.respond(s,"tell me more",world)
check(r.intent~="lore","legacy reference fields cannot resurrect an expired archive thread")
check(B.respond(s,"continue",world).intent~="lore","lore-specific wording also respects subject expiry")
for _,g in ipairs(C.GUIDES) do B.respond(s,g.questions[1],world) end
check(#C.state(s).topics<=C.MAX_TOPICS and #C.state(s).history<=C.MAX_HISTORY,"history and topic lists are bounded")
inside=false
prior=calls.storage
r=B.respond(s,"how many nails",world)
check(calls.storage==prior and not has(r,"240 nails"),"history never bypasses camp access")
check(B.respond(session(),"how do i mount a radio",world).intent=="guide","read-only help works away from camp")
inside=true
print("TERMINAL_CONVERSATION_PASS checks="..checks.." guides="..#C.GUIDES.." chat="..#C.CHAT.." aliases="..aliases)
SC_TEST_REPORT=(SC_TEST_REPORT or "Camp computer").."; Conversation: "..checks.." checks passed"
