-- SPDX-License-Identifier: MIT
-- The same observed camp used by the original public playground sessions.
local SC=SurvivorCompanion
SC.EmmaTalkPolishFixture={}
local F=SC.EmmaTalkPolishFixture
function F.world()
    return {
        camp=function() return {configured=true,inside=true,name="Rising"} end,
        clock=function() return {hour=14,minute=5,day=12,month=7,year=1993,worldHours=77,days=3} end,
        weather=function() return {temperature=14,rain=.4,fog=0,wind=.1,snow=false} end,
        power=function() return {source="generator",fuel=62,condition=88} end,
        people=function() return {
            {id="sc-1",name="Kate Miller",health=42,bleeding=true,doing="Chopping wood",
                where="at camp, 12 metres north-east",morale=40,stress=70},
            {id="sc-2",name="Bob Fisher",health=95,doing="Idle",where="at camp, right here",morale=60,stress=20},
            {id="sc-4",name="Dale",away=true}} end,
        jobs=function() return {active=1,pending=1,blocked=1,rows={
            {state="active",job="Chop wood",who="Kate Miller"},
            {state="blocked",job="Build wall",reason="Missing materials"},{state="pending",job="Farm"}}} end,
        storage=function() return {containers=3,items=30,groups={
            {name="Canned Beans",type="Base.TinnedBeans",category="Food",food=true,kcal=1800,count=6},
            {name="Water Bottle",type="Base.WaterBottle",category="Water",count=4},
            {name="Bandage",type="Base.Bandage",category="FirstAid",count=3}}} end,
        zombies=function() return {count=3,radius=40,nearest=17.4,dir="north-west"} end,
        expedition=function() return {active=false} end}
end
function F.copy(value,seen)
    if type(value)~="table" then return value end
    seen=seen or {} if seen[value] then return seen[value] end
    local out={} seen[value]=out
    for key,item in pairs(value) do out[key]=F.copy(item,seen) end
    return out
end
function F.text(reply)
    local out={}
    for _,line in ipairs(reply.lines or reply.rows or {}) do
        out[#out+1]=type(line)=="table" and line.text or line
    end
    return table.concat(out," "):lower()
end
function F.fits(row,reply)
    if not reply or reply.careDetected or reply.intent=="care"
        or reply.layer=="care" and not (row.contentOnly and reply.careIntent=="care_gentle") then return false end
    local text=F.text(reply)
    local intent=reply.intent or reply.layer
    if row.reference then
        local actual=reply.referenceState
        if not reply.reference or not actual then return false end
        for key,value in pairs(row.reference) do if actual[key]~=value then return false end end
    end
    if row.command and reply.command~=row.command then return false end
    local unresolved={fallback=true,fallback_echo=true,did_you_mean=true,did_you_mean_no=true,followup_clarify=true,deflect=true,["repeat"]=true}
    if unresolved[intent] and not row.contentOnly then
        local permitted=false for _,id in ipairs(row.accept or {}) do if intent==id then permitted=true end end
        if not permitted then return false end
    end
    if #(row.accept or {})>0 then
        local found=false for _,id in ipairs(row.accept) do if intent==id then found=true end end
        if not found then return false end
    elseif #(row.any or {})==0 then return false end
    for _,group in ipairs(row.any or {}) do
        local found=false for _,word in ipairs(group) do if text:find(word:lower(),1,true) then found=true end end
        if not found then return false end
    end
    for _,word in ipairs(row.forbid or {}) do if text:find(word:lower(),1,true) then return false end end
    -- An unresolved guess is never a fitting answer to an ordinary content row.
    return #text>0
end
function F.variants(raw)
    local terse=raw:lower():gsub("[?.!]$",""):gsub("^what is ",""):gsub("^what ",""):gsub("^tell me about ","")
    local typo=raw:gsub("(%a%a)(%a)(%a%a%a+)","%1%3",1)
    return {raw:upper():gsub("'",""),"emma, "..raw,terse,typo}
end
function F.facts()
    return {days=4,hours=77,time="2:05 PM",hour=14,minute=5,drawer="closed",
        zombies=3,companions=3,companion="Kate",moodles={}}
end
return F
