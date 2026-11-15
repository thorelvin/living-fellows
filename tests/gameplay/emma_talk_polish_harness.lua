-- SPDX-License-Identifier: MIT
local SC=SurvivorCompanion
local F,D=SC.EmmaTalkPolishFixture,SC.EmmaTalkPolishData
local baseline=SC.EmmaTalkPolishBaseline or {passed={}}
local results,counts,regressions,wrong={},{},{},{}
local uncertain={fallback=true,fallback_echo=true,did_you_mean=true,did_you_mean_no=true,
    followup_clarify=true,topic_help=true,deflect=true,steer=true}
local function record(id,set,row,reply)
    local passed=F.fits(row,reply)
    local count=counts[set] or {0,0} counts[set]=count
    count[2]=count[2]+1 if passed then count[1]=count[1]+1 end
    if not passed and not uncertain[reply.intent or reply.layer] then wrong[set]=(wrong[set] or 0)+1 end
    results[#results+1]=(passed and "PASS " or "MISS ")..id.." | "..tostring(reply.intent or reply.layer)
    if not passed and baseline.passed[id] then regressions[#regressions+1]=id end
end
local function run(conversation,set,variants)
    local world=F.world()
    local state=conversation.voice~="emma" and SC.TerminalPersona.new(conversation.voice,11)
    local session=state and SC.TerminalPersona.session() or SC.TerminalBrain.newSession({operator="Thor",random=function() return 1 end})
    local previousText
    for _,row in ipairs(conversation.turns) do
        local originalRandom=session.random
        if row.identity_variant then
            local pool=SC.TerminalLines.POOLS.identity
            local selected
            for n,line in ipairs(pool) do if line:find(row.identity_variant,1,true) then selected=n break end end
            assert(selected,"the requested public identity variant is missing")
            session.recent.identity=nil
            session.random=function(n) return n==#pool and selected or originalRandom(n) end
        end
        if variants then
            for n,raw in ipairs(F.variants(row.input)) do
                local s=F.copy(session)
                local reply=SC.TerminalBrain.respond(s,raw,world)
                record(row.id.."-v"..n,"real-variants",row,reply)
            end
        end
        local reply=state and SC.TerminalPersona.respond(state,session,row.input,F.facts())
            or SC.TerminalBrain.respond(session,row.input,world)
        session.random=originalRandom
        if row.identity_variant then assert(F.text(reply):find(row.identity_variant,1,true),"the identity variant was not exercised") end
        if conversation.strict then
            assert(F.fits(row,reply),"public user session failed: "..row.id.." intent="..tostring(reply.intent))
            assert(previousText~=F.text(reply),"consecutive public session replies repeated: "..row.id)
        end
        previousText=F.text(reply)
        record(row.id,set,row,reply)
    end
end
for _,conversation in ipairs(D["real-talk"].conversations) do run(conversation,"real",true) end
for _,conversation in ipairs(D.predicted.conversations) do run(conversation,conversation.voice=="emma" and "predicted" or "persona",false) end
for _,chain in ipairs(D["real-talk"].chains) do
    local world=F.world()
    local session=SC.TerminalBrain.newSession({operator="Thor",random=function() return 1 end})
    for _,raw in ipairs(chain.prefix) do SC.TerminalBrain.respond(session,raw,world) end
    local converged=false
    for n,row in ipairs(chain.turns) do
        local reply=SC.TerminalBrain.respond(session,row.input,world)
        if n<=2 and F.fits(row,reply) then converged=true end
    end
    record(chain.id,"chains",{accept={"converged"}},{intent=converged and "converged" or "miss",lines={"chain"}})
end
-- Semantic scoring has a control: a correctly routed but unrelated answer fails.
assert(not F.fits({accept={"rule"},any={{"appointment"}}},{layer="rule",rows={{text="The drawer is closed."}}}),"content scoring control")
assert(not F.fits({accept={"guide"},reference={id="trapping",facet="make"}},
    {intent="guide",reference=true,referenceState={id="firearms",facet="make"},lines={"A trap."}}),"wrong reference subject fails")
assert(not F.fits({accept={"guide"},reference={id="trapping",facet="make"}},
    {intent="guide",reference=true,referenceState={id="trapping",facet="find"},lines={"A trap."}}),"wrong reference facet fails")
local report={}
for _,set in ipairs({"real","real-variants","predicted","persona","chains"}) do
    local c=counts[set] report[#report+1]="POLISH_SCORE "..set.." "..c[1].."/"..c[2]
    if baseline.floor and baseline.floor[set] and c[1]<baseline.floor[set] then regressions[#regressions+1]="floor:"..set end
end
for _,line in ipairs(results) do report[#report+1]=line end
for _,set in ipairs({"real","real-variants"}) do
    report[#report+1]="POLISH_WRONG "..set.." "..(wrong[set] or 0).."/"..counts[set][2]
end
SC_TEST_REPORT=(SC_TEST_REPORT or "")..table.concat(report,"\n").."\n"
assert(#regressions==0,"previously passing rows regressed: "..table.concat(regressions,", ").."\n"..table.concat(report,"\n"))
for set,rate in pairs({real=.90,["real-variants"]=.90,predicted=.85,persona=.95,chains=1}) do
    assert(counts[set][1]/counts[set][2]>=rate,"final conversation target: "..set.."\n"..table.concat(report,"\n"))
end
for _,set in ipairs({"real","real-variants"}) do
    assert((wrong[set] or 0)/counts[set][2]<=.03,"confident wrong-answer target: "..set)
end
