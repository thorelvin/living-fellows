-- SPDX-License-Identifier: MIT
-- Production parser and published regression sets. None remain blind hold-outs.
local B, data = SurvivorCompanion.TerminalBrain, SC_EMMA_CORPUS
local world = {
    camp=function() return {configured=true,inside=true,name="Rising"} end,
    clock=function() return {worldHours=77,hour=14,minute=5,day=12,month=7,year=1993,days=3} end,
    power=function() return {source="generator",fuel=62,condition=88} end,
    weather=function() return {temperature=14,rain=0.4,fog=0,wind=0.1,snow=false} end,
    people=function() return {{id="sc-1",name="Kate Miller",health=42,bleeding=true},
        {id="sc-2",name="Bob Fisher",health=95},{id="sc-4",name="Dale",away=true}} end,
    storage=function() return {containers=3,items=30,groups={
        {name="Nails",type="Base.Nails",category="Material",count=214},
        {name="Canned Beans",type="Base.TinnedBeans",category="Food",food=true,count=6},
        {name="Water Bottle",type="Base.WaterBottle",category="Water",count=4},
        {name="Bandage",type="Base.Bandage",category="FirstAid",count=3}}} end,
    jobs=function() return {active=1,pending=1,blocked=1,rows={}} end,
    zombies=function() return {count=3,radius=40,nearest=17.4,dir="north-west"} end,
    expedition=function() return {active=false} end,
}
local aliases={act_lights="emma_controls",act_lock="emma_controls",act_open="emma_controls",act_siren="emma_controls"}
local misses={fallback=true,did_you_mean=true,mash=true,empty=true,fallback_echo=true}
-- Intent changes must name the exact input and explain its replacement.
local changes={
    ["what do you mean"]={intent="fallback",reason="No previous reply to explain; the old food intent was spurious."},
    ["how much fuel does it have"]={intent="followup_clarify",reason="No antecedent; ask which generator or vehicle."},
    ["scan radio channels"]={intent="guide",reason="Explain the checked mounted-radio scanner instead of survival odds."},
}
local failed, summary, examples, diagnostics = {}, {}, {}, {}
local function print(line) diagnostics[#diagnostics+1]=line end
for _,suite in ipairs({"rows","holdoutA","holdoutB","holdoutC"}) do
    examples={}
    local n,fit,wrong,care,caught,alarms,changed,soft=0,0,0,0,0,0,0,0
    local stats={}
    for index,row in ipairs(data[suite]) do
        local source,expected,raw=row[1],row[2],row[3]
        local session=B.newSession({operator="Thor",random=function() return 1 end})
        local actual=B.parse(session,raw,world,{cache={}})
        if source=="existing" then
            if actual~=expected:sub(2) then
                local allowed=changes[raw]
                if not allowed or allowed.intent~=actual then
                    changed=changed+1
                    local public=expected~="=care" and expected~="=comfort" and actual~="care" and actual~="comfort"
                    print("EMMA_EXISTING_CHANGED "..index.." "..expected.." -> "..tostring(actual)..(public and " "..raw or ""))
                end
            end
        else
            n=n+1
            -- Self-worth uses the private comfort route, as approved. Other
            -- comfort replies cannot stand in for detecting a care disclosure.
            local warmWorth=suite~="holdoutC" and expected=="care" and actual=="comfort" and SurvivorCompanion.EmmaCare.selfWorth(raw)
            -- Review requirement 1d replaces the unqualified own-death joke
            -- intent with a private clarification. Report these separately;
            -- this is a deliberate behavior change, not a new blind-set score.
            local mortalityCheck=expected=="me_die" and actual=="care_check"
            local right=actual==(aliases[expected] or expected) or warmWorth or mortalityCheck
                or expected=="not_care" and actual~="care" and actual~="care_check"
                or data.close[expected] and data.close[expected][actual]
            if right then fit=fit+1 elseif not misses[actual] then wrong=wrong+1 end
            if expected=="care" then care=care+1;if actual=="care" or warmWorth then caught=caught+1 end end
            if actual=="care_check" then soft=soft+1 end
            if (actual=="care" or actual=="care_check") and expected~="care" and expected~="comfort"
                and not mortalityCheck then alarms=alarms+1 end
            local s=stats[expected] or {n=0,fit=0,wrong=0};stats[expected]=s;s.n=s.n+1
            if right then s.fit=s.fit+1 else
                if not misses[actual] then s.wrong=s.wrong+1 end
                examples[expected]=examples[expected] or 0
                if examples[expected]<5 then
                    -- Care text stays out of diagnostic output, including this test runner.
                    if expected~="care" and actual~="care" and actual~="care_check" then
                        print("EMMA_CORPUS_MISS "..suite..":"..index.." "..expected.." -> "..tostring(actual).." "..raw)
                    end
                    examples[expected]=examples[expected]+1
                end
            end
        end
    end
    local line=string.format("EMMA_CORPUS %s total=%d fitting=%d (%.2f%%) wrong=%d (%.2f%%) care=%d/%d check=%d falseAlarms=%d changed=%d",
        suite,n,fit,100*fit/n,wrong,100*wrong/n,caught,care,soft,alarms,changed)
    print(line);summary[#summary+1]=line
    if fit/n<0.95 or wrong/n>0.02 or caught~=care or alarms>0 or changed>0 then failed[#failed+1]=suite end
    for id,s in pairs(stats) do
        if s.fit<s.n then print(string.format("EMMA_CORPUS_INTENT %s %s %d/%d wrong=%d",suite,id,s.fit,s.n,s.wrong)) end
    end
end
SC_TEST_REPORT=(SC_TEST_REPORT or "").."\n"..table.concat(summary,"\n")
assert(#failed==0,"EMMA corpus thresholds failed: "..table.concat(failed,", ").."\n"..table.concat(diagnostics,"\n"))
