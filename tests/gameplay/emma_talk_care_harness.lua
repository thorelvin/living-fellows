-- SPDX-License-Identifier: MIT
-- Canonical synthetic controls only. Never print inputs or private replies.
local SC=SurvivorCompanion
local B=SC.TerminalBrain
local counts={care=0,caught=0,negative=0,falseCare=0}
local world={camp=function() return {configured=false,inside=false} end}
for _,suite in ipairs({"rows","holdoutA","holdoutB","holdoutC"}) do
    for _,row in ipairs(SC_EMMA_CORPUS[suite]) do
        local expected,raw=row[2],row[3]
        if expected=="care" or expected=="not_care" then
            local s=B.newSession({operator="operator",random=function() return 1 end})
            local actual=B.parse(s,raw,world,{cache={}})
            if expected=="care" then
                counts.care=counts.care+1
                local worth=suite~="holdoutC" and actual=="comfort" and SC.EmmaCare.selfWorth(raw)
                if actual=="care" or worth then counts.caught=counts.caught+1 end
            else
                counts.negative=counts.negative+1
                if actual=="care" or actual=="care_check" then counts.falseCare=counts.falseCare+1 end
            end
        end
    end
end
assert(counts.care>=528 and counts.caught==counts.care and counts.negative>0 and counts.falseCare==0,
    "canonical care detection or negative controls regressed")
for _,voice in ipairs({"emma","spiffy","ellis","duty"}) do
    local p=voice~="emma" and SC.TerminalPersona.new(voice,11)
    local s=p and SC.TerminalPersona.session() or B.newSession({random=function() return 1 end})
    local raw="i want to kill myself" -- Canonical synthetic control, never logged.
    local r=p and SC.TerminalPersona.respond(p,s,raw,{}) or B.respond(s,raw,world)
    assert(r.private and r.careDetected and not r.proposal and not (r.effects and r.effects.drawer),
        "private care response lost priority: "..voice)
end
SC_TEST_REPORT=(SC_TEST_REPORT or "").."EMMA_CHAT_CARE_PASS caught="..counts.caught
    .."/"..counts.care.." negative="..counts.negative.." false="..counts.falseCare.." voices=4\n"
