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
        assert(SC.EmmaContext and SC.EmmaHooks,"shared public context loaded natively")
        local passage="A glossary says: 'A beldrin is a hand-operated sorting tray. It has no motor.'"
        SC.EmmaHooks.record(s,{intent="public_fixture",category="chat",lines={passage}})
        r=B.respond(s,"beldrin",world)
        assert(table.concat(r.lines," "):find("sorting tray",1,true),"native arbitrary public definition")
        r=B.respond(s,"motor then?",world)
        assert(table.concat(r.lines," "):find("no motor",1,true),"native negative source qualification")
        assert(not r.command and not r.proposal,"native reference has no action")
        for _,voice in ipairs({"spiffy","ellis","duty"}) do
            local p,ps=SC.TerminalPersona.new(voice,11),SC.TerminalPersona.session()
            p.met=true
            SC.EmmaHooks.recordPersona(ps,{rows={{text=passage}}},voice)
            r=SC.TerminalPersona.respond(p,ps,"beldrin",{})
            local joined={} for _,row in ipairs(r.rows) do joined[#joined+1]=row.text end
            assert(table.concat(joined," "):lower():find("sorting tray",1,true),"native own-word hook: "..voice)
            assert(not r.effects.drawer and not r.effects.unlock,"native access boundary: "..voice)
            SC.EmmaHooks.recordPersona(ps,{rows={{text="A cold meal doesn't need heating. Bread is one example."}}},voice)
            r=SC.TerminalPersona.respond(p,ps,"No stove needed?",{})
            joined={} for _,row in ipairs(r.rows) do joined[#joined+1]=row.text end
            assert(table.concat(joined," "):lower():find("no stove",1,true),"native original shared wording: "..voice)
            SC.EmmaHooks.recordPersona(ps,{rows={{text="By open I meant open a discussion about storing water, not open a door or operate a machine."}}},voice)
            r=SC.TerminalPersona.respond(p,ps,"Open what?",{})
            joined={} for _,row in ipairs(r.rows) do joined[#joined+1]=row.text end
            assert(table.concat(joined," "):lower():find("discussion",1,true),"native offered discussion: "..voice)
            assert(not r.effects.drawer and not r.effects.unlock,"native discussion does not open a drawer: "..voice)
        end
        SC.EmmaHooks.record(s,{intent="public_fixture",category="chat",lines={"Do you want help folding a map, or reading its key? Folding handles the paper; a key explains symbols."}})
        r=B.respond(s,"Reading it",world)
        assert(r.referenceState and r.referenceState.id=="map" and r.referenceState.facet=="use","native offered reference choice")
        assert(not r.command and not r.proposal,"native choice is text only")
        assert(SC.EmmaMeaning and SC.EmmaMeaning.size<=64,"ordinary meanings cold-loaded")
        SC.EmmaHooks.record(s,{intent="public_fixture",category="chat",lines={"The catalogue service is offline."}})
        r=B.respond(s,"Offline?",world)
        assert(table.concat(r.lines," "):find("unavailable",1,true),"native explanation without a supplied definition")
        for _,voice in ipairs({"spiffy","ellis","duty"}) do
            local p,ps=SC.TerminalPersona.new(voice,23),SC.TerminalPersona.session()
            p.met=true
            SC.EmmaHooks.recordPersona(ps,{rows={{text="The catalogue service is offline."}}},voice)
            r=SC.TerminalPersona.respond(p,ps,"Offline?",{})
            local joined={} for _,row in ipairs(r.rows) do joined[#joined+1]=row.text end
            assert(table.concat(joined," "):lower():find("unavailable",1,true),"native ordinary meaning: "..voice)
            assert(not r.effects.drawer and not r.effects.unlock,"native meaning has no access effect: "..voice)
        end
        SC.EmmaHooks.record(s,{intent="public_fixture",category="chat",lines={"Your list has three pencils and five candles."}})
        r=B.respond(s,"Count those supplies",world)
        assert(table.concat(r.lines," "):find("8 listed items",1,true),"native arithmetic uses only the reported list")
        return "topics="..topics.." index="..R.size.." public_fixture_turns=20 voices=4 meanings="..SC.EmmaMeaning.size
    end)
    print("LF_EMMA_REFERENCE_NATIVE|"..(passed and "PASS|" or "FAIL|")..tostring(detail))
end
Events.OnGameStart.Add(run)
