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
for _,line in ipairs(failed) do
    SC_TEST_REPORT=(SC_TEST_REPORT or "").."EMMA_CHAT_FAIL "..line.."\n"
end
SC_TEST_REPORT=(SC_TEST_REPORT or "").."EMMA_CHAT_RESULT passed="..passed.." failed="..#failed.."\n"
assert(#failed==0,"public chat regressions: "..table.concat(failed,"; "))
