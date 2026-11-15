-- SPDX-License-Identifier: MIT
-- Copy into a disposable native payload only. Checks the engine's cold module
-- load and pure terminal reference; no UI, save, actor or world mutation.
local function run()
    local passed,detail=pcall(function()
        local SC=SurvivorCompanion
        assert(SC and SC.EmmaReference and SC.EmmaUnderstand,"reference loaded by native module loader")
        local R,B=SC.EmmaReference,SC.TerminalBrain
        assert(R.size>200 and R.size<=1800,"bounded noun index")
        local topics=0
        for _,topic in ipairs(SC.EmmaReferenceData) do
            topics=topics+1
            for _,facet in ipairs({"what","make","use","find","why","dangers"}) do
                assert(type(R.definition(topic.id).facets[facet])=="string","missing reference facet")
            end
        end
        local s=B.newSession({operator="Native fixture",random=function() return 1 end})
        local world={camp=function() return {configured=false,inside=false} end}
        local r=B.respond(s,"traps",world)
        assert(r.referenceState and r.referenceState.id=="trapping","cold noun answer")
        r=B.respond(s,"how do I make one",world)
        assert(r.referenceState and r.referenceState.facet=="make","cold facet follow-up")
        r=B.respond(s,"how exactly",world)
        assert(r.referenceState and r.referenceState.exact,"cold exact follow-up")
        return "topics="..topics.." index="..R.size.." public_fixture_turns=3"
    end)
    print("LF_EMMA_REFERENCE_NATIVE|"..(passed and "PASS|" or "FAIL|")..tostring(detail))
end
Events.OnGameStart.Add(run)
