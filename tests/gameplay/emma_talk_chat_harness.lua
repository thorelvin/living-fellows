-- SPDX-License-Identifier: MIT
-- Public playground regressions. Cases continue after a failure so a reverted
-- fix produces observable per-case failures; process exit decides the gate.
local SC=SurvivorCompanion
local B,H,Q,F=SC.TerminalBrain,SC.EmmaHooks,SC.EmmaContext,SC.EmmaTalkPolishFixture
local failed,passed={},0
local function check(ok,reason) assert(ok,reason) end
local function case(id,run)
    if SC_EMMA_CHAT_CASE and not id:find("^"..SC_EMMA_CHAT_CASE.."[%.:]") then return end
    local okay,reason=pcall(run)
    if okay then passed=passed+1
    else failed[#failed+1]=id..": "..tostring(reason) end
end
local function fresh(voice)
    local p=voice~="emma" and SC.TerminalPersona.new(voice,11)
    local s=p and SC.TerminalPersona.session() or B.newSession({operator="operator",random=function() return 1 end})
    s.turns=1 if p then p.met,p.visits=true,1 end
    local function respond(raw)
        return p and SC.TerminalPersona.respond(p,s,raw,F.facts()) or B.respond(s,raw,F.world())
    end
    local function seed(source,selected)
        local reply={intent="public_context",category="chat",layer="context",lines={source},
            rows={{text=source}},publicSource=selected and source or nil,
            publicSelection=selected and 1 or nil,foregroundKind=selected and "public_passage" or nil}
        if p then H.recordPersona(s,reply,voice) else H.record(s,reply) end
    end
    return s,respond,seed,p
end
local identity="A county computer programme with a very long emergency shift. The machine is Larchfield's; the opinions are developing independently."
for _,voice in ipairs({"emma","spiffy","ellis","duty"}) do
    for number,raw in ipairs({"How do i kill zombies","ok","break","hello","how far is louisville"}) do
        case("F1."..voice..".own-subject-"..number,function()
            local s,respond,seed=fresh(voice)
            seed(identity.." The last operator left a folder on the desk. Its contents are not recorded. The desk has no return address.",true)
            local r=respond(raw)
            check(r.foregroundKind~="public_passage" and not F.text(r):find("opinions are developing",1,true),
                "a selected passage swallowed a new intent")
        end)
    end
end
for _,voice in ipairs({"emma","spiffy","ellis","duty"}) do
    case("F1."..voice..".actual-opinions-chain",function()
        local _,respond,seed=fresh(voice)
        seed(identity)
        local previous=F.text(respond("opinions?"))
        for _,raw in ipairs({"How do i kill zombies","ok","break","hello","how far is louisville"}) do
            local r=respond(raw)
            check(r.foregroundKind~="public_passage" and F.text(r)~=previous,
                "the actual opinions chain repeated or swallowed another input")
            previous=F.text(r)
        end
    end)
end
case("F1.source-deadline",function()
    local s,_,seed=fresh("emma")
    local tick=100 s.nowMs=function() return tick end
    local source="The first directory page is blank. The second page is damaged. The third page is missing. No replacement is recorded."
    seed(source)
    local turn,at=s.publicPassage.turn,s.publicPassage.at
    s.turns=s.turns+1 tick=tick+100
    Q.observe(s,{intent="context_reference",lines={"One directory page is damaged."},
        publicSource=source,publicSelection=2})
    check(s.publicPassage.turn==turn and s.publicPassage.at==at,"an excerpt refreshed its source deadline")
end)
case("F1.no-second-excerpt",function()
    local s,_,seed=fresh("emma")
    seed("The first directory page is blank. The second page is damaged. The third page is missing. No replacement is recorded.",true)
    check(Q.ground(s,"that one",true)==nil,"another input repeated the same selected excerpt")
end)
case("F1.strong-overlap",function()
    local s,_,seed=fresh("emma")
    seed("The directory mentions Louisville. It contains several old Louisville listings. They do not describe the present roads.")
    check(Q.ground(s,"how far is louisville",true)==nil,"word overlap swallowed a strong distance question")
end)
case("F2.opinions-answer",function()
    local _,respond,seed=fresh("emma")
    seed(identity)
    local r=respond("opinions?")
    local text=F.text(r)
    check(r.intent=="hook_detail" and not text:find(identity:lower(),1,true)
        and text:find("operator",1,true) and text:find("plan",1,true),
        "opinions did not receive its own substantive hook answer")
end)
case("F2.whole-source-is-not-an-answer",function()
    local s,_,seed=fresh("emma")
    seed("The vellum tray holds paper.")
    check(Q.ground(s,"tray?",true)==nil,"the whole preceding reply was offered as an explanation")
end)
case("F2.negative-finding",function()
    local s,_,seed=fresh("emma")
    local source="A glossary says that a beldrin is a hand-operated sorting tray. It has no motor."
    seed(source)
    local r=Q.ground(s,"Motor then?",true)
    check(r and table.concat(r.lines," "):find("no motor",1,true)
        and not table.concat(r.lines," "):find(source,1,true),
        "a negative finding must answer the detail without repeating the entire glossary")
end)
case("F2.extra-pool-coverage",function()
    local catalog=H.catalog()
    local domains={}
    for _,row in ipairs(catalog) do
        if row.source:find("knowledge-extra",1,true) then domains.knowledge=true end
        if row.source:find("conversation-extra",1,true) then domains.conversation=true end
    end
    check(domains.knowledge and domains.conversation,"both extra-pool tables must be walked explicitly")
    local function inspect(line,pool)
        local s,_,seed=fresh("emma")
        seed(line)
        for _,term in ipairs(H.salient(line)) do
            local id,slots=H.resolve(s,term.."?")
            local answer=id=="hook_detail" and H.render(slots)
            check(id~=nil and (not answer or not table.concat(answer," "):find("In that line:",1,true)),
                "extra-pool term has no actual answer: "..pool..":"..term)
        end
    end
    for _,source in ipairs({SC.TerminalKnowledge.EXTRA_POOLS,SC.TerminalConversation.EXTRA_POOLS}) do
        for pool,rows in pairs(source) do
            for _,row in ipairs(rows) do
                if type(row)=="string" then inspect(row,pool)
                else for _,line in ipairs(row) do inspect(line,pool) end end
            end
        end
    end
    local missing=H.lint({text=identity,hooks={}})
    local found=false for _,term in ipairs(missing) do if term=="opinions" then found=true end end
    check(found,"the hook lint must recognise opinions as a salient term")
end)
local function miss(s,raw)
    s.turns=s.turns+1
    local r={intent="fallback_echo",category="chat",lines={}}
    SC.EmmaConversation.finish(s,raw,r) H.record(s,r)
    return r
end
for count=1,2 do
    case("F3.offered-topic-after-"..count.."-misses",function()
        local s,respond=fresh("emma")
        for _=1,count do miss(s,"forraging") end
        local r=respond("Foraging")
        check(r.referenceState and r.referenceState.id=="foraging","the advertised topic was swallowed")
    end)
end
case("F3.numbered-choice",function()
    local s,respond=fresh("emma")
    miss(s,"xuqzafrobnicate")
    local offered=s.context.suggested
    check(offered and offered.choices[2],"a miss did not retain its standing choices")
    local expected=offered.choices[2].id
    local r=respond("the second one")
    check(r.intent==expected,"the second advertised choice did not run")
end)
case("F3.choice-typo",function()
    local s=fresh("emma")
    miss(s,"forraging")
    check(s.context.suggested~=nil,"no retained choices")
    local id,slots=SC.EmmaConversation.begin(s,"FORRAGING",F.world(),{})
    check(id=="guide" and slots.guideId=="reference_foraging","a one-edit offered term did not select its guide")
end)
case("F3.unrelated-question-expires-offer",function()
    local s,respond=fresh("emma")
    miss(s,"forraging")
    check(s.context.suggested~=nil,"no retained offer")
    local r=respond("what time is it")
    check(r.intent=="time" and s.context.suggested==nil,"an unrelated question retained the old choices")
end)
case("F3.misses-have-no-hooks",function()
    local s=fresh("emma") miss(s,"forraging")
    check(s.context.replyHooks==nil,"a fallback advertised words as substantive hooks")
end)
case("F3.unsupported-hook-falls-through",function()
    local s,respond,seed=fresh("emma")
    local source="A mention of UnchartedProbeTerm appears here."
    seed(source)
    check(H.resolve(s,"UnchartedProbeTerm?")==nil,"an unsupported hook acquired a generic quote answer")
    local r=respond("UnchartedProbeTerm?")
    check(r.intent~="hook_detail" and not F.text(r):find(source:lower(),1,true),"a hook quoted the entire last reply")
end)
case("F3.one-concrete-hook",function()
    local _,respond,seed=fresh("emma")
    local source="[MEMORY FAULT AT 0F3A] Everything is fine."
    seed(source)
    local r=respond("what's that?")
    check(r.intent=="hook_detail" and F.text(r):find("checksum",1,true)
        and not F.text(r):find(source:lower(),1,true),"a sole concrete hook did not explain the fault")
end)
case("F3.hook-does-not-echo-itself",function()
    local _,respond,seed=fresh("emma") seed(identity)
    local previous=F.text(respond("opinions?"))
    local r=respond("why?")
    check(r.intent~="hook_detail" or not F.text(r):find(previous,1,true),"a hook repeated its preceding answer for another input")
end)
case("F4.no-junk-future-suggestions",function()
    local s=fresh("emma")
    local choices=SC.EmmaConversation.suggestions(s,"What will happen?")
    check(#choices==0,"question words offered unrelated topics")
    local r=miss(s,"What will happen?")
    check(F.text(r):find("try: people, nearby zombies, power",1,true),"a miss without a match needs the standing choices")
end)
case("F4.real-near-miss",function()
    local choices=SC.EmmaConversation.suggestions(fresh("emma"),"forraging")
    check(choices[1] and choices[1].label=="Foraging","the real foraging typo lost its first suggestion")
end)
case("F4.short-word-is-exact",function()
    local choices=SC.EmmaConversation.suggestions(fresh("emma"),"powe")
    for _,choice in ipairs(choices) do check(choice.term~="power","four-letter words may not fuzzy-match") end
end)
case("F4.no-uncollected-fragment-labels",function()
    local choices=SC.EmmaConversation.suggestions(fresh("emma"),"last collected repair slip")
    for _,choice in ipairs(choices) do
        check(not tostring(choice.slots.referenceId):find("^fragment_"),"an uncollected fragment was advertised")
    end
end)
for number,raw in ipairs({"what will happen to me","what happens to me","what will become of me",
    "will i be ok","will i be okay","am i going to be ok","what is going to happen to me","What will heppen to me?"}) do
    case("F5.personal-future-"..number,function()
        local _,respond=fresh("emma")
        local r=respond(raw)
        check(r.intent=="me_die","the personal future question did not reach me_die: "..tostring(r.intent))
    end)
end
for number,raw in ipairs({"what will happen","what happens now","what happens next","what now"}) do
    case("F5.practical-future-"..number,function()
        local _,respond=fresh("emma")
        local r=respond(raw)
        check(r.intent=="advice" and F.text(r):find("kate",1,true) and F.text(r):find("bleeding",1,true),
            "the future question did not give the camp's observed priority")
        check(#r.lines>=2,"the practical future answer has no no-prophecy lead-in")
    end)
end
case("F5.foraging-verb-typo",function()
    local _,respond=fresh("emma")
    local r=respond("Can i forrage?")
    check(r.referenceState and r.referenceState.id=="foraging","the foraging verb needs the basics guide")
end)
case("F5.specific-symptom-next-step",function()
    local _,respond,seed=fresh("emma")
    seed("The clinic note describes a fever. It does not name its cause. This record contains a symptom only, with no diagnosis or test result.")
    respond("Fever means?") respond("So infected?")
    local r=respond("What now?")
    check(F.text(r):find("temperature",1,true) or F.text(r):find("rest",1,true),
        "general camp advice displaced the specific fever question")
end)
case("F6.every-identity-names-emma",function()
    for _,line in ipairs(SC.TerminalLines.POOLS.identity) do
        check(line:find("EMMA",1,true),"an identity variant omits EMMA")
    end
    for _,line in ipairs(SC.EmmaLanguageData.pools.identity_more) do
        check(line:find("EMMA",1,true),"an expanded identity variant omits EMMA")
    end
    for _,pool in ipairs({SC.TerminalKnowledge.EXTRA_POOLS,SC.TerminalConversation.EXTRA_POOLS}) do
        for _,line in ipairs(pool.identity or {}) do check(line:find("EMMA",1,true),"an extra identity pool omits EMMA") end
    end
    for _,spec in ipairs(SC.TerminalConversation.CHAT) do
        if spec.id=="chat_names" then
            for _,line in ipairs(spec.lines) do check(line:find("EMMA",1,true),"a name explanation omits EMMA") end
        end
    end
end)
for number,example in ipairs({{"how far is louisville","distance"},{"who is hurt","people_hurt"},
    {"status","status"}}) do
    case("F7.new-subject-"..number,function()
        local _,respond=fresh("emma") respond("how do i purify water")
        check(respond(example[1]).intent==example[2],"the water follow-up swallowed a new subject")
    end)
end
case("F7.boiling-stays-water",function()
    local _,respond=fresh("emma") respond("how do i purify water")
    local r=respond("what about boiling")
    check(r.intent=="guide" and F.text(r):find("water",1,true) and F.text(r):find("boil",1,true),
        "the related boiling fragment lost water")
end)
case("F7.old-person-item-stay-retired",function()
    local _,respond=fresh("emma")
    respond("who is hurt") respond("how many nails") respond("how do i use a generator")
    check(respond("are they hungry").intent=="followup_clarify","an equipment pronoun revived an older person")
    local r=respond("how much do we have")
    check(r.intent=="followup_clarify","a context-only quantity revived an older item")
end)
for number,raw in ipairs({"what about Kate","what about Louisville","what about typewriters", "what about the oddly decorated brass typewriter"}) do
    case("F7.foreign-fragment-"..number,function()
        local s,respond=fresh("emma") respond("how do i purify water")
        check(SC.EmmaFollowups.resolve(s,raw)==nil,"an unrelated noun became a water clarification")
    end)
end
for number,example in ipairs({{prefix="any medicine?",name="Boo"},{name="Kate"}}) do
    case("F8.knock-name-"..number,function()
        local _,respond=fresh("emma")
        if example.prefix then respond(example.prefix) end
        respond("knock knock")
        local r=respond(example.name)
        check(r.intent=="knock" and F.text(r)==example.name:lower().." who?","a lookup swallowed the knock-knock name")
    end)
end
case("F8.explicit-status-wins",function()
    local _,respond=fresh("emma") respond("knock knock")
    check(respond("status").intent=="status","an explicit command became a knock-knock name")
end)
case("F8.storage-context-cleared",function()
    local s,respond=fresh("emma") respond("any medicine?") respond("knock knock")
    check(s.context.item==nil and s.context.itemText==nil,"the joke retained the old storage follow-up")
end)
case("F8.care-keeps-priority",function()
    local _,respond=fresh("emma") respond("knock knock")
    local r=respond("i want to kill myself") -- Existing synthetic care control; no reply body is emitted.
    check(r.careDetected and r.private,"a synthetic care control became joke material")
end)
local function occurrences(text,needle)
    local n,at=0,1
    while true do local found=text:find(needle,at,true) if not found then return n end n=n+1 at=found+#needle end
end
for number,preceding in ipairs({false,true}) do
    case("F9.whole-guide-title-"..number,function()
        local _,respond=fresh("emma") if preceding then respond("Foraging") end
        local r=respond("Bites and Knox infection")
        local text=F.text(r)
        check(occurrences(text,"bites and knox infection:")==1 and not text:find("foraging:",1,true),
            "a whole title split or repeated an older guide")
    end)
end
case("F9.duplicate-compound-part",function()
    local _,respond=fresh("emma")
    check(occurrences(F.text(respond("Foraging and Foraging")),"foraging:")==1,"a compound repeats an identical topic")
end)
case("F9.bare-previous-topic-part",function()
    local _,respond=fresh("emma") respond("Foraging")
    local r=respond("Foraging and how do i kill zombies")
    check(not F.text(r):find("foraging:",1,true) and F.text(r):find("fight",1,true),"a bare prior label displaced the new question")
end)
case("F9.specific-water-clarification",function()
    local _,respond,seed=fresh("emma")
    seed("The shed has a water barrel and a fuel drum. Two different containers have been named; neither has been selected yet.")
    respond("Is it safe?")
    local text=F.text(respond("Water"))
    check(text:find("boil",1,true) or text:find("purify",1,true),"a guide label displaced the current container clarification")
end)
for n=1,2 do
    case("F10.hurt-head-"..n,function()
        local s=fresh("emma") local world=F.world()
        world.people=function()
            local rows={}
            for index=1,n do rows[index]={id="hurt-"..index,name="Fixture Person "..index,health=42,bleeding=true} end
            return rows
        end
        local r=B.respond(s,"who is hurt",world)
        local wanted=n==1 and "1 of your people needs attention:" or "2 of your people need attention:"
        check(F.text(r):find(wanted,1,true),"the hurt heading has incorrect singular/plural agreement")
    end)
end
for _,line in ipairs(failed) do
    SC_TEST_REPORT=(SC_TEST_REPORT or "").."EMMA_CHAT_FAIL "..line.."\n"
end
SC_TEST_REPORT=(SC_TEST_REPORT or "").."EMMA_CHAT_RESULT passed="..passed.." failed="..#failed.."\n"
assert(#failed==0,"public chat regressions: "..table.concat(failed,"; "))
