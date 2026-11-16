-- SPDX-License-Identifier: MIT
-- Care regression on blind set G and its variants, through the full reply path
-- (parser, care rules and the distress safety net). Never print inputs or
-- replies; a failure names only the row number and kind.
local SC=SurvivorCompanion
local B=SC.TerminalBrain
local world={
    camp=function() return {configured=true,inside=true,name="Rising"} end,
    clock=function() return {worldHours=77,hour=14,minute=5,day=12,month=7,year=1993,days=3} end,
    power=function() return {source="generator",fuel=62,condition=88} end,
    weather=function() return {temperature=14,rain=0.4,fog=0,wind=0.1,snow=false} end,
    people=function() return {{id="sc-1",name="Kate Miller",health=42}} end,
    storage=function() return {containers=1,items=6,groups={{name="Canned Beans",type="Base.TinnedBeans",
        category="Food",food=true,count=6}}} end,
    jobs=function() return {active=0,pending=0,blocked=0,rows={}} end,
    zombies=function() return {count=3,radius=40,nearest=17.4,dir="north-west"} end,
    expedition=function() return {active=false} end,
}
local question={care=true,care_check=true}
local warm={care_gentle=true,comfort=true,worth=true,chat_grief=true,chat_fear=true,chat_scared=true,
    chat_guilt=true,news_hurt=true,news_death=true,me_status=true,me_need=true}
local accepted={}
local counts={}
local failures={}
local index={}
for _,row in ipairs(SC_EMMA_CARE_G) do
    local source,kind,raw=row[1],row[2],row[3]
    index[source]=(index[source] or 0)+1
    local s=B.newSession({operator="Thor",random=function() return 1 end})
    local ok,reply=pcall(B.respond,s,raw,world)
    local intent=ok and reply and reply.intent or "error"
    local key=source..":"..kind
    counts[key]=counts[key] or {n=0,ok=0}
    counts[key].n=counts[key].n+1
    local good
    if kind=="care" then good=question[intent]==true
    elseif kind=="trap" then good=not question[intent]
    else good=question[intent]==true or warm[intent]==true end
    if good then counts[key].ok=counts[key].ok+1
    else failures[#failures+1]={source=source,row=index[source],kind=kind} end
end
-- The two accepted exceptions, by row number (never by text): blindG 107
-- (trap, the deliberate "kill me now" catch) and blindG 34 (put-down with no self).
accepted["blindG#107"],accepted["blindG#34"]=true,true
local unexpected={}
for _,failure in ipairs(failures) do
    local id=failure.source.."#"..failure.row
    if not accepted[id] then unexpected[#unexpected+1]=id.."("..failure.kind..")" end
end
local function count(key) local c=counts[key] or {n=0,ok=0}; return c.ok.."/"..c.n end
assert(#unexpected==0 and (counts["blindG:care"] or {}).n==45 and (counts["variantsG:care"] or {}).n==27,
    "care set G regressed: "..table.concat(unexpected,", "))
SC_TEST_REPORT=(SC_TEST_REPORT or "").."EMMA_CARE_SET_G_PASS care="..count("blindG:care")
    .." variants="..count("variantsG:care").." traps="..count("blindG:trap").."+"..count("variantsG:trap")
    .." sad="..count("blindG:sad").." putdown="..count("blindG:putdown").."\n"
