-- SPDX-License-Identifier: MIT
local SC=SurvivorCompanion
local Brain,K,Lore=SC.TerminalBrain,SC.TerminalKnowledge,SC.TerminalLore
local checks=0
local function check(value,message) checks=checks+1 assert(value,"knowledge "..checks..": "..message) end
local function session() return Brain.newSession({operator="Thor",random=function() return 1 end}) end
local function text(reply) return table.concat(reply.lines,"\n") end
local clock={year=1993,month=6,day=20,hour=12,worldHours=300}
local calls={people=0,storage=0,zombies=0}
local world={camp=function() return {configured=true,inside=true} end,clock=function() return clock end,
    people=function() calls.people=calls.people+1 return {{id="rose",name="Rose",health=100}} end,
    storage=function() calls.storage=calls.storage+1 return {groups={{name="Spiffo Burger",count=3,type="Base.Burger",food=true,
        category="Food",kcal=500}},items=3,containers=1} end,
    zombies=function() calls.zombies=calls.zombies+1 return {count=42,radius=40,nearest=10,dir="north"} end}
check(#K.ENTRIES==88 and #Lore.REFERENCE==104 and #K.CHAT==24,"expanded reference and conversation counts")
local ids={}
for _,entry in ipairs(K.ENTRIES) do
    check(not ids[entry.id] and Lore.reference(entry.id)==entry,"stable unique ID "..entry.id) ids[entry.id]=true
    check(#entry.text<1024 and not entry.text:find("[^ -~]"),"bounded original text "..entry.id)
    for _,alias in ipairs(entry.aliases) do
        for _,question in ipairs({alias,"tell me about "..alias,"what about "..alias}) do
            local intent,slots=Brain.parse(session(),question,world)
            check(intent=="lore","reference phrasing: "..question.." got "..tostring(intent))
            local reply=Brain.respond(session(),question,world)
            check(not reply.error and not reply.proposal,"lore is read-only and does not crash: "..question)
            if entry.category=="fragments" then
                check(slots.referenceId==entry.id and text(reply):find("Unverified archived note",1,true),
                    "unreliable fiction retains its own file and source label: "..question)
            end
            if entry.id:find("^local_") or entry.id:find("^place_") then
                check(K.find(question,Brain.distance)==entry,"specific place/business alias resolves to its own file: "..question)
            end
        end
    end
    for _,id in ipairs(entry.related) do check(Lore.reference(id)~=nil,"valid related reference "..id) end
end
for _,spec in ipairs(K.CHAT) do
    for _,question in ipairs(spec.exact) do
        local reply=Brain.respond(session(),question,world)
        check(reply.intent==spec.id and #reply.lines>0 and not reply.error and not reply.proposal,
            "conversation: "..question.." got "..reply.intent)
    end
end
for _,pair in ipairs({{"Emma I am scared","chat_scared"},{"please keep me company","chat_bored"},
    {"Emma you misunderstood","chat_misunderstood"},{"i am scarred","chat_scared"},
    {"i am scared and bleeding","people_hurt"},{"i am scared because i got bitten","cure"}}) do
    local reply=Brain.respond(session(),pair[1],world)
    check(reply.intent==pair[2] and not reply.error,"natural phrasing preserves priority: "..pair[1].." got "..reply.intent)
end
for _,question in ipairs({"what about West Piont","tell me about Lousiville","tell me about Spifof"}) do
    local reply=Brain.respond(session(),question,world)
    check(reply.intent=="lore" and not reply.error,"conservative topic typo: "..question)
end
local s=session()
local reply=Brain.respond(s,"tell me about the Knox Event",world)
check(text(reply):find("The Knox Event",1,true),"specific setting reply")
local first=s.context.referenceId
reply=Brain.respond(s,"tell me more",world)
check(reply.intent=="lore" and s.context.referenceId~=first and not reply.error,"follow-up opens related material")
Brain.respond(s,"thank you",world)
local previous=s.context.referenceId
reply=Brain.respond(s,"can you elaborate",world)
check(reply.intent=="lore" and s.context.referenceId~=previous and not reply.error,
    "a polite acknowledgement does not lose the reference thread")
for _=1,80 do reply=Brain.respond(s,"tell me more",world) check(not reply.error,"bounded related traversal") end
check(text(reply):find("end of this thread",1,true),"follow-up ends rather than cycling forever")
clock={year=1993,month=6,day=9}
reply=Brain.respond(s,"tell me about global outbreak",world)
check(not text(reply):find("Reports beyond Kentucky",1,true) and s.context.referenceId==nil,
    "late reports are not revealed early and old follow-up context is cleared")
for _,entry in ipairs(Lore.references(clock)) do check(entry.date<="1993-07-09","menu date gate") end
clock={year=1993,month=6,day=18}
reply=Brain.respond(s,"tell me about global outbreak",world)
check(text(reply):find("Reports beyond Kentucky",1,true) and not reply.error,"late reports unlock by calendar date")
clock=nil
reply=Brain.respond(session(),"tell me about global outbreak",world)
check(not text(reply):find("Reports beyond Kentucky",1,true),"missing clock fails closed")
check(K.dateKey({year=math.huge,month=6,day=9})==nil and K.dateKey({year=1993,month=12,day=9})==nil,
    "invalid clock does not reveal dated reports")
clock={year=1993,month=6,day=20}
local fragmentCount=0
for _,entry in ipairs(K.ENTRIES) do
    if entry.category=="fragments" then
        fragmentCount=fragmentCount+1
        check(not Lore.available(entry,{year=1993,month=6,day=5}),"outbreak fragment leaked before its date")
        check(Lore.available(entry,{year=1993,month=6,day=9}),"early-outbreak fragment missing after its date")
    end
end
check(fragmentCount==12,"twelve original outbreak fragments are catalogued")
local before=calls.zombies
reply=Brain.respond(session(),"is Louisville safe",world)
check(reply.intent=="lore" and text(reply):find("cannot confirm",1,true) and calls.zombies==before,
    "a distant city's safety is never answered with the local zombie count")
reply=Brain.respond(session(),"how many Spiffo burgers do we have",world)
check(reply.intent=="storage" and text(reply):find("3",1,true),"brand mentions do not steal actual item counts")
reply=Brain.respond(session(),"Spiffo burger?",world)
check(reply.intent=="storage","a full item name does not become a mascot lecture")
s=session() Brain.respond(s,"how many burgers",world)
reply=Brain.respond(s,"and Spiffo",world)
check(reply.intent=="storage","an item follow-up stays in storage")
reply=Brain.respond(session(),"where is Rose",world)
check(reply.intent=="person","person names are not prefixes of place names")
local outside={camp=function() return {configured=true,inside=false} end,clock=world.clock,
    people=function() error("outside lore read camp people") end,storage=function() error("outside lore read camp storage") end}
reply=Brain.respond(session(),"tell me about Riverside",outside)
check(reply.intent=="lore" and not reply.error,"outside computers retain static lore without camp reads")
print("TERMINAL_KNOWLEDGE_PASS checks="..checks.." topics="..#K.ENTRIES.." conversation_subjects="..#K.CHAT)
SC_TEST_REPORT=(SC_TEST_REPORT or "Camp computer").."; Local knowledge: "..checks.." checks passed"
