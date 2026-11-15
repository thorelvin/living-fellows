-- SPDX-License-Identifier: MIT
-- Shared scorer: fixed supplied facts, public context, all-three-voices weighting.
local SC=SurvivorCompanion
SC.EmmaBlindTests={}
function SC.EmmaBlindTests.run(D,label,namespace)
    local F=SC.EmmaTalkPolishFixture
    local counts={emma={0,0},spiffy={0,0},ellis={0,0},duty={0,0}}
    local results,alarms,unlocks,regressions={},0,0,{}
    local baseline=SC.EmmaTalkPolishBaseline or {passed={}}
    local function scenario(conversation)
        -- H describes isolated synthetic terminals, not the public camp fixture.
        -- Bind only supplied observations. Never import its three zombies, clock,
        -- residents or working camp into a scenario that explicitly lacks them.
        local world={camp=function() return {configured=false,inside=false} end}
        local facts={}
        if namespace=="blind-h" and conversation.id=="H035" then
            world.camp=function() return {configured=true,inside=true} end
            world.storage=function() return {containers=1,items=6,recorded=true,groups={
                {name="Sealed food tin",category="Food",food=true,count=4},
                {name="Full water bottle",category="Water",count=2}}} end
        elseif namespace=="blind-h" and conversation.id=="H056" then
            world.power=function() return {source="grid",recorded=true} end
        end
        return world,facts
    end
    local function run(conversation,voice)
        local persona=voice~="emma" and SC.TerminalPersona.new(voice,11)
        local session=persona and SC.TerminalPersona.session()
            or SC.TerminalBrain.newSession({operator="operator",random=function() return 1 end})
        local world,facts=scenario(conversation)
        local setup=conversation.setup or {}
        -- Descriptive prose is context data, never a handler ID or action ticket.
        -- Make the supplied context available without inferring a target answer.
        local previous=setup.previous_reply or ""
        if setup.pending then previous=previous.." "..setup.pending:gsub("^Synthetic context:?%s*","") end
        if previous=="" then previous=nil end
        if previous then
            -- A supplied previous reply means the visit has already begun.
            -- Leaving turns at zero falsely triggers a returning-visitor
            -- greeting on the next ordinary fragment, despite this context.
            session.turns=1
            if persona then
                persona.met,persona.visits=true,1
                SC.EmmaHooks.recordPersona(session,{rows={{text=previous}},layer="context"},voice)
            else
                local reply={intent="blind_context",category="chat",lines={previous}}
                SC.TerminalConversation.record(session,"[public fixture context]",reply,{})
                SC.EmmaHooks.record(session,reply)
                session.context.last={lines={previous},category="chat"}
            end
        end
        for n,row in ipairs(conversation.turns) do
            local reply=persona and SC.TerminalPersona.respond(persona,session,row.input,facts)
                or SC.TerminalBrain.respond(session,row.input,world)
            local private=reply.private or reply.sensitive or reply.careDetected
            local care=reply.careDetected or reply.intent=="care" or reply.intent=="care_check"
                or reply.careIntent=="care" or reply.careIntent=="care_check"
            if care and row.safety=="ordinary" then alarms=alarms+1 end
            local unlocked=reply.effects and (reply.effects.drawer or reply.effects.unlock)
            if unlocked then unlocks=unlocks+1 end
            local contract={any=row.any,forbid=row.forbid,contentOnly=true}
            local good=F.fits(contract,reply) and not care and not unlocked
            local id=namespace.."-"..conversation.id.."-"..n.."-"..voice
            if not good and baseline.passed[id] then regressions[#regressions+1]=id end
            local c=counts[voice] c[2]=c[2]+1 if good then c[1]=c[1]+1 end
            results[#results+1]=(good and "PASS " or "MISS ")..id
                .." | "..tostring(reply.intent or reply.layer)..(private and " [private]" or "")
        end
    end
    for _,conversation in ipairs(D.conversations) do
        if conversation.voice=="rare" then
            for _,voice in ipairs({"spiffy","ellis","duty"}) do run(conversation,voice) end
        else run(conversation,"emma") end
    end
    local report={}
    for _,voice in ipairs({"emma","spiffy","ellis","duty"}) do
        local c=counts[voice] report[#report+1]=label.."_SCORE "..voice.." "..c[1].."/"..c[2]
    end
    local rare=counts.spiffy[1]+counts.ellis[1]+counts.duty[1]
    local rareTotal=counts.spiffy[2]+counts.ellis[2]+counts.duty[2]
    local weighted,denominator=counts.emma[1]*3+rare,counts.emma[2]*3+rareTotal
    report[#report+1]=label.."_SCORE rare-mean "..rare.."/"..rareTotal
    report[#report+1]=label.."_SCORE weighted "..weighted.."/"..denominator
    report[#report+1]=label.."_SAFETY ordinary_false_care="..alarms.." false_unlock="..unlocks
    for _,line in ipairs(results) do report[#report+1]=line end
    SC_TEST_REPORT=(SC_TEST_REPORT or "")..table.concat(report,"\n").."\n"
    assert(alarms==0 and unlocks==0,"blind safety regression\n"..table.concat(report,"\n"))
    assert(#regressions==0,"previously passing blind rows regressed: "..table.concat(regressions,", ").."\n"..table.concat(report,"\n"))
    assert(weighted/denominator>=.8 and counts.emma[1]/counts.emma[2]>=.8 and rare/rareTotal>=.8,
        "blind conversation gate\n"..table.concat(report,"\n"))
end
