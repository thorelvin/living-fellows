-- SPDX-License-Identifier: MIT
-- A pure policy simulation; native claims and XP have separate live acceptance.
local SC=SurvivorCompanion local E,L=SC.TerminalLockEmma,SC.TerminalLocks
local facts,finish=E.facts,L.finishUnlock
local fixed={days=12,people=3,electrical=3,screwdriver=true,zombie=false,threatKnown=true,distance=0}
E.facts=function() return fixed end
L.finishUnlock=function(w,how)
    assert(how=="emma" and w.system.lock.emma.conviction>=4 and w.system.lock.emma.won,"simulation must meet the real win threshold")
    w.system.locked=false return true
end
local player={getPerkLevel=function() return 3 end}
local results={}
for _,policy in ipairs({"random","false-claim-first","informed"}) do
    local wins=0
    for seed=1,10000 do
        local w={player=player,system={seed=seed,locked=true,lock={kind="emma"}}}
        E.ensure(w.system) E.offers(w)
        local pick=SC.TerminalSystem.random(seed+49157)
        while w.system.locked and not w.system.lock.emma.retryUntil do
            local e=w.system.lock.emma local selected=pick(4)
            local weak,hard=E.temperament(w.system)
            local bestScore=-100
            for index,offer in ipairs(e.offers) do
                local a=E.argument(offer.id) local actual=a.claim and fixed[a.claim]
                local valid=not a.claim or type(actual)=="boolean" and actual or type(actual)=="number" and (offer.truthful or offer.number==actual)
                if policy=="false-claim-first" and not valid then selected=index break end
                if policy=="informed" then
                    local score=valid and (a.kind==weak and 2 or a.kind==hard and -1 or 1) or -2
                    if score>bestScore then bestScore=score selected=index end
                end
            end
            E.input(w,tostring(selected))
            for _,line in ipairs(e.history) do
                assert(not line.reply:find("{",1,true) and not (line.argument or ""):find("{",1,true),"all data placeholders are filled")
            end
        end
        if not w.system.locked then wins=wins+1 end
    end
    results[policy]=wins/100
end
E.facts,L.finishUnlock=facts,finish
assert(results.informed>=98,"informed players should nearly always succeed")
assert(results.random>=40 and results.random<=80,"random play remains viable without dominating informed play")
assert(results["false-claim-first"]<results.random,"a policy favouring caught lies should perform worse")
SC_TEST_REPORT=(SC_TEST_REPORT or "").."; EMMA 10,000 seeds/policy: random="..results.random.."% false-claim-first="..results["false-claim-first"].."% informed="..results.informed.."%"
