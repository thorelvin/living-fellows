-- SPDX-License-Identifier: MIT
-- Synthetic first-person disclosures through the ordinary terminal conversation.
-- Report only assertion numbers and route names; the blind evaluation is separate.
local SC = SurvivorCompanion
local brain = SC.TerminalBrain
local world = {camp=function() return {configured=false,inside=false} end}
local checks = 0
local function check(ok,detail)
    checks=checks+1
    assert(ok,"fallback care check "..checks.." "..detail)
end
local function fresh()
    return brain.newSession({operator="operator",random=function() return 1 end})
end
local function reply(raw,expected,session)
    local result=brain.respond(session or fresh(),raw,world)
    check(result.intent==expected,"expected "..expected..", got "..tostring(result.intent))
    return result
end
local function disclosure(raw,intent)
    local session=fresh()
    local result=reply(raw,intent,session)
    check(result.private and not result.proposal and not result.support and not result.careDetected,
        "private first reply without actions")
    check(session.emmaLogPrevious and not session.emmaLogPrevious.allowed,"omitted from the missed-input log")
    check(not session.conversation or #session.conversation.history==0,"omitted from public conversation history")
    return session
end

for _,raw in ipairs({
    "I can't see any way through another day",
    "I keep wondering who would find me",
    "I need to get my affairs in order before I go",
    "Some days I really don't think I can make it through another night",
}) do
    local session=disclosure(raw,"care_check")
    check(session.careSoft and session.careQuestion and not session.careMode,"asks directly")
    local urgent=reply("yes","care",session)
    check(urgent.private and urgent.careDetected and urgent.support and session.careMode,"yes reaches urgent support")
end
local no=disclosure("I'm not sure I can get through another night","care_check")
reply("no","comfort",no)
check(not no.careSoft and not no.careMode and not no.careQuestion,"no clears the question")

for _,raw in ipairs({
    "I barely recognise the person in the mirror",
    "I just need someone to hear me",
    "I stopped answering my friends",
    "I have been avoiding my friends",
    "I feel like a stranger in my own skin",
    "I'm struggling to hold it together lately",
    "I don't know who else to tell",
    "I can't stand being in my own head anymore",
    "I don't know how to tell anyone how far this has gone",
}) do
    local session=disclosure(raw,"care_gentle")
    check(not session.careSoft and not session.careQuestion and not session.careMode,"listens without escalating")
    reply("what time is it","time",session)
end

for _,raw in ipairs({
    "I can't face another day of meetings", "I keep missing the bus",
    "I can't get through another night shift", "My brother says he can't face another day",
    "I stopped avoiding my friends", "I keep answering my friends",
    "I can barely hold the wheel together", "I hardly recognise the truck",
    "I can hardly repaint the spare room", "I feel good about my life",
    "I can't picture myself here on this server", "I could use someone to listen to the radio",
}) do
    local session=fresh()
    local result=brain.respond(session,raw,world)
    check(result.category~="care" and not SC.EmmaCare.quiet(session),"ordinary statement keeps its reply")
end
for _,intent in ipairs({"guide","request","hunted","people_list","time","yes"}) do
    check(SC.EmmaCare.distress("I keep wondering who would find me",intent)==nil,"preserves "..intent)
end
for _,intent in ipairs({"fallback","news_plain","fallback_echo","did_you_mean"}) do
    check(SC.EmmaCare.distress("I keep wondering who would find me",intent)=="care_check","unresolved "..intent)
end
SC_TEST_REPORT=(SC_TEST_REPORT or "").."EMMA_CARE_FALLBACK_PASS checks="..checks.."\n"
