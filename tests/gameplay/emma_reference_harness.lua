-- SPDX-License-Identifier: MIT
local SC=LivingFellows
local B,R,F=SC.TerminalBrain,SC.EmmaReference,SC.EmmaTalkPolishFixture
local checks=0
local function check(ok,why) checks=checks+1 assert(ok,why) end
local function fresh() return B.newSession({operator="Test",random=function() return 1 end}) end
local function ask(s,raw,w) return B.respond(s,raw,w or F.world()) end
local function text(r) return F.text(r) end
check(R.size>200 and R.size<=1800,"noun index is bounded and built at load")
local size=R.size
for _,topic in ipairs(SC.EmmaReferenceData) do
    for _,facet in ipairs({"what","make","use","find","why","dangers"}) do
        local line=topic.facets[facet]
        check(type(line)=="string" and #line>40,"six useful facets: "..topic.id..":"..facet)
        check(not line:find("[^ -~]") and not line:find("{[%w_]+}"),"authored facet is printable and complete")
        check(not line:lower():find("sandbox",1,true) and not line:lower():find("game survival",1,true),"first answer stays in-world")
    end
    for _,line in pairs(topic.exact) do check(line:find("Game survival reference:",1,true)==1,"exact steps are marked") end
    check(type(topic.source)=="string" and #topic.source>20,"source paths accompany facts")
end
for word,id in pairs({traps="trapping",pistol="firearms",foraging="foraging",bandages="dressings",
    gasoline="fuel",generator="generator",hammer="tools",clothing="clothing",stealth="stealth",
    warehouse="loot",vehicle="vehicle",winter="winter",bite="bite",axe="weapons",fire="fire",night="night"}) do
    local r=ask(fresh(),word)
    check(r.reference and r.referenceState.id==id,"known noun reaches reference: "..word)
    check(not text(r):find("game survival reference",1,true),"first noun answer is in-world: "..word)
end
for _,row in ipairs({
    {"How do I make bandages","dressings","make","rip"},
    {"How do I use bandages","dressings","use","wound"},
    {"Where do I find gasoline","fuel","find","pump"},
    {"Why use a gun","firearms","why","melee"},
    {"Is a shotgun loud","firearms","noise","attract"},
    {"What do traps catch","trapping","catch","rabbit"},
}) do
    local r=ask(fresh(),row[1])
    check(r.reference and r.referenceState.id==row[2] and r.referenceState.facet==row[3]
        and text(r):find(row[4],1,true),"subject and facet: "..row[1])
end
do
    local s=fresh()
    local first=ask(s,"how do i make traps")
    local exact=ask(s,"how exactly")
    local summary=ask(s,"how exactly")
    check(first.referenceState.facet=="make" and not text(first):find("game survival reference",1,true),"recipe starts in-world")
    check(exact.referenceState.facet=="make" and text(exact):find("game survival reference",1,true)
        and text(exact):find("three planks",1,true),"how exactly retains the recipe facet")
    check(text(exact)~=text(summary),"immediate repeat does not repeat the exact page")
    check(not text(ask(s,"how exactly")):find("game survival reference",1,true),
        "further repeats cannot alternate back to the exact page")
    local one=ask(s,"how do I make one")
    check(one.referenceState and one.referenceState.id=="trapping" and one.referenceState.facet=="make",
        "one keeps the native cold-load reference subject")
    local other=ask(s,"what country are we in")
    check(text(other):find("united states",1,true),"complete new subject beats an old reference")
end
do
    local s=fresh()
    ask(s,"gasoline")
    local found=ask(s,"where do i find it")
    check(found.referenceState.id=="fuel" and found.referenceState.facet=="find"
        and text(found):find("siphon",1,true),"pronoun keeps fuel instead of drifting to water")
end
do
    local s=fresh()
    local kate=ask(s,"Kate got bitten")
    local follow=ask(s,"will she turn")
    check(kate.referenceState.patient=="Kate Miller" and text(kate):find("for kate miller",1,true),"bite report names its patient")
    check(follow.referenceState.patient=="Kate Miller" and not text(follow):find("your blood",1,true),"bite follow-up stays about Kate")
    check(not text(kate):find("kate is infected",1,true),"typed report does not manufacture a diagnosis")
    local outside=F.world()
    outside.camp=function() return {configured=true,inside=false} end
    outside.people=function() error("outside terminal cannot read people") end
    local denied=ask(fresh(),"Kate got bitten",outside)
    check(not (denied.referenceState and denied.referenceState.patient),"outside terminal does not identify a private camp patient")
end
do
    local s=fresh()
    ask(s,"Horde!")
    local count=ask(s,"how many")
    check(count.intent=="zombies" and text(count):find("3",1,true),"count after horde counts actual zombies")
end
do
    local s=fresh()
    ask(s,"power") ask(s,"for now") ask(s,"how long will it last")
    local condition=ask(s,"condition")
    check(condition.intent=="power" and text(condition):find("88",1,true)
        and text(condition):find("repair",1,true),"generator context survives the runtime exchange")
    s=fresh()
    ask(s,"Dale") ask(s,"call him") ask(s,"radio") ask(s,"when is he back")
    local findings=ask(s,"what did he find")
    check(findings.intent=="expedition" and text(findings):find("no current expedition report",1,true),
        "an away marker does not manufacture cargo or a return time")
    local recall=ask(s,"tell him to come home")
    check(recall.intent=="guide" and text(recall):find("recall",1,true),"recall follow-up explains the real radio control")
end
do
    local s=fresh()
    ask(s,"fire") ask(s,"how do I put it out")
    local spreading=ask(s,"its spreading")
    check(spreading.referenceState.id=="fire" and spreading.referenceState.facet=="dangers"
        and text(spreading):find("get clear",1,true),"spreading fire does not become infection advice")
    local r=ask(fresh(),"password")
    check(r.intent=="guide" and not r.command and not r.request and not r.effects,
        "password reference cannot grant access or issue a request")
    check(text(ask(fresh(),"alarm")):find("no current camp-alarm record",1,true),"missing alarm reader is explicit")
    s=fresh() ask(s,"im bitten")
    local turning=ask(s,"will i turn")
    check(turning.referenceState and turning.referenceState.id=="bite" and turning.private
        and text(turning):find("no verified cure",1,true),"bite follow-up offers facts without diagnosing the operator")
end
do
    local s=fresh()
    local r=ask(s,"work was awful")
    check(r.intent=="session_kindness" and r.private and text(r):find("tiring",1,true),"real day receives private kindness")
    check(not s.context.replyHooks,"kindness is not copied into public hook metadata")
    for _,raw in ipairs({"can you refuel the generator","please refuel the generator","refuel generator"}) do
        check(B.parse(fresh(),raw,F.world(),{cache={}})=="request","noun index preserves checked requests: "..raw)
    end
end
do
    local r=ask(fresh(),"Pistol")
    check(text(r):find("no pistol in marked camp storage",1,true) and text(r):find("ammunition",1,true),"stock answer includes useful firearms reference")
end
do
    local original=R.resolve
    R.resolve=function() end
    check(not ask(fresh(),"traps").reference,"removing noun routing loses the known trap answer")
    R.resolve=original
end
for n=1,100 do R.find("unrecognised fixture word "..n) end
check(R.size==size,"arbitrary input cannot grow the noun index")
SC_TEST_REPORT=(SC_TEST_REPORT or "").."EMMA_REFERENCE_PASS checks="..checks.." index="..R.size.."\n"
