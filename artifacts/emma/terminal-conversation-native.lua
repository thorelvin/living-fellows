-- SPDX-License-Identifier: MIT
-- Real computer, actual camp provider and native terminal input in a fresh copy.
local run={step=0,next=0}
local function log(value)
    print("EMMA_CONVERSATION|"..value)
    local writer=getFileWriter("SurvivorCompanionHarness/emma-conversation.log",true,true)
    if writer then writer:write(value.."\n") writer:close() end
end
Events.OnMainMenuEnter.Add(function()
    if run.entered then return end run.entered=true
    require "OptionScreens/MainScreen"
    local ok,err=pcall(MainScreen.continueLatestSave,"Rising","LF-Skills5-Test-2026-10-29")
    if not ok then log("FAIL autoload "..tostring(err)) end
end)
local function computer()
    local square=getCell():getGridSquare(12035,6739,0)
    if square then for i=0,square:getObjects():size()-1 do
        local object=square:getObjects():get(i)
        if SurvivorCompanion.Terminal.isComputer(object) then return object end
    end end
end
local function send(line)
    local w=run.window
    w:setFocusMode("chat") w.entry:setText(line) w:submit() w:flush()
    assert(not w.closed,"native question closed terminal")
    assert(not w.session.context.last or w.session.context.last.category~="error","native reply failed")
    return table.concat(w.session.context.last and w.session.context.last.lines or {},"\n")
end
local function tick()
    local SC=SurvivorCompanion local player=getSpecificPlayer(0) local now=getTimestampMs()
    if now<run.next or not SC or not SC.Terminal or not player or not player:getSquare() then return end
    if run.step==0 then
        run.player=player player:setGodMod(true) player:setGhostMode(true)
        player:teleportTo(12034.5,6739.5,0)
        run.step,run.next,run.deadline=1,now+6000,now+45000
    elseif run.step==1 then
        run.pc=computer()
        if not run.pc then assert(now<run.deadline,"native desktop not streamed") run.next=now+500 return end
        assert(SC.Terminal.open(player,run.pc),"native terminal refused open")
        run.window=SC.Terminal.window run.window:flush()
        if run.window.system.locked then
            run.window.entry:setText(run.window.system.puzzle.answer) run.window:submit() run.window:flush()
        end
        local people=run.window.world.people()
        for _,person in ipairs(people or {}) do if not person.away then run.person=person break end end
        assert(run.person and run.person.id,"native camp person unavailable")
        send("how is "..run.person.name) send("thank you")
        local reply=send("how tired is she")
        local topic=SC.TerminalConversation.latest(run.window.session,{person=true})
        assert(topic and topic.id==run.person.id,"native pronoun changed actor identity")
        assert(reply:find("tiredness",1,true) and reply:find("stamina",1,true),"native needs readings missing")
        log("PASS live person, acknowledgement and fatigue/stamina follow-up: "..run.person.name)
        run.step,run.next=2,now+2500
    elseif run.step==2 then
        run.capture="emma-conversation-needs" run.step,run.next=3,now+1500
    elseif run.step==3 then
        run.session=run.window.session run.window:close()
        assert(SC.Terminal.open(player,run.pc),"native brief reopen failed")
        run.window=SC.Terminal.window run.window:flush()
        assert(run.window.session==run.session,"native reopen discarded recent thread")
        local reply=send("what is she good at")
        assert(reply:find("recorded skills",1,true),"native skill follow-up lost subject")
        reply=send("what were we talking about")
        assert(reply:find("how tired is she",1,true),"native history missing previous question")
        log("PASS native brief reopen, current skills and conversational recap")
        run.step,run.next=4,now+2500
    elseif run.step==4 then
        run.capture="emma-conversation-history" run.step,run.next=5,now+1500
    elseif run.step==5 then
        send("how do i find broadcasts") send("tell me more")
        local topic=SC.TerminalConversation.latest(run.window.session)
        assert(topic.kind=="guide" and topic.id=="scanner" and topic.page==2,"native operating-help continuation failed")
        send("tell me about Louisville")
        local reply=send("is it safe")
        assert(reply:find("cannot confirm",1,true),"native distant-place follow-up became a local safety claim")
        assert(not run.window.requestTicket,"read-only conversation created a request ticket")
        log("PASS native operating help, related detail, distant-place uncertainty and no action proposal")
        run.window:close()
        assert(SC.Terminal.window==nil and getSpecificPlayer(1)==nil,"native conversation leaked a window or view")
        log("PASS native EMMA conversation acceptance complete") run.step=99
    end
end
local function safeTick()
    local ok,err=pcall(tick)
    if not ok then log("FAIL "..tostring(err)) Events.OnTick.Remove(safeTick) end
end
Events.OnTick.Add(safeTick)
Events.OnPostUIDraw.Add(function()
    if run.capture then getCore():TakeFullScreenshot(run.capture) log("SHOT "..run.capture) run.capture=nil end
end)
