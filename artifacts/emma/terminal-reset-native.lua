-- SPDX-License-Identifier: MIT
-- Factory-reset acceptance through real input on a disposable saved desktop.
local run={step=0,next=0}
local function log(value)
    print("EMMA_RESET|"..value)
    local writer=getFileWriter("SurvivorCompanionHarness/terminal-reset.log",true,true)
    if writer then writer:write(value.."\n") writer:close() end
end
local function computer()
    local square=getCell():getGridSquare(12035,6739,0)
    if square then for i=0,square:getObjects():size()-1 do
        local object=square:getObjects():get(i)
        if SurvivorCompanion.Terminal.isComputer(object) then return object end
    end end
end
local function input(text)
    local w=SurvivorCompanion.Terminal.window
    w:flush() w:setFocusMode("chat") w.entry:setText(text) w:submit()
    if SurvivorCompanion.Terminal.window==w then w:flush() end
    return SurvivorCompanion.Terminal.window
end
local function shot(name) getCore():TakeFullScreenshot("emma-reset-"..name) log("SHOT "..name) end
local function tick()
    local SC=SurvivorCompanion local player=getSpecificPlayer(0) local now=getTimestampMs()
    if now<run.next or not player or not player:getSquare() or not SC or not SC.Terminal then return end
    if run.step==0 then
        player:teleportTo(12034.5,6739.5,0)
        run.step,run.next,run.deadline=1,now+6000,now+45000
    elseif run.step==1 then
        run.pc=computer()
        if not run.pc then assert(now<run.deadline,"clone desktop unavailable") run.next=now+500 return end
        assert(SC.Terminal.use(player,run.pc),"native Use computer refused")
        run.step,run.next,run.deadline=2,now+1000,now+30000
    elseif run.step==2 then
        local w=SC.Terminal.window
        if not w then assert(now<run.deadline,"native Use computer did not finish") run.next=now+500 return end
        w:flush()
        if w.system.locked then input(w.system.puzzle.answer) end
        -- Seed old software on the clone only; the reset itself uses chat.
        w.system.archive,w.system.brand="office_walter","Fossil"
        run.identity,run.seed,run.theme,run.xp=w.system.identity,w.system.seed,w.system.theme,w.system.xpAwarded
        input("remember the spare key is under the mat")
        input("call me Morgan")
        run.oldSession=w.session
        run.kept={}
        for key,value in pairs(run.pc:getModData().movableData) do
            if key~=SC.Terminal.MEMORY_KEY and key~=SC.TerminalSystem.MEMORY_KEY then run.kept[key]=value end
        end
        input("factory reset")
        assert(w.requestTicket,"factory reset did not require confirmation")
        assert(w.system.archive=="office_walter" and #w.session.notes>0,"proposal erased data before confirmation")
        log("PASS native proposal retains old files and user notes until explicit confirmation")
        run.step,run.next=3,now+1500
    elseif run.step==3 then
        shot("confirmation")
        input("no")
        local w=SC.Terminal.window
        assert(not w.requestTicket and w.system.archive=="office_walter" and #w.session.notes>0,"no did not cancel")
        input("Emma, reset this computer to factory settings")
        run.ticket=w.requestTicket
        local fresh=input("yes")
        assert(w.closed and fresh~=w and fresh.state=="booting","reset failed to reopen POST")
        assert(fresh.system.archive=="_factory" and fresh.system.brand=="_camp","old software survived reset")
        assert(not fresh.session and not run.pc:getModData()[SC.Terminal.MEMORY_KEY],"old session was written back on close")
        log("PASS native no cancels; yes consumes confirmation and opens clean POST")
        run.step,run.next=4,now+500
    elseif run.step==4 then
        shot("boot")
        local w=SC.Terminal.window w:flush()
        assert(w.session~=run.oldSession and #w.session.notes==0 and w.session.operator~="Morgan" and w.session.visits==1,
            "factory setup retained cached operator memory")
        assert(w.system.identity==run.identity and w.system.seed==run.seed and w.system.theme==run.theme
            and w.system.xpAwarded==run.xp,"reset changed machine identity, phosphor colour or XP record")
        for key,value in pairs(run.kept) do assert(run.pc:getModData().movableData[key]==value,"reset changed mounted hardware or local services") end
        assert(SC.TerminalActions.execute(w,run.ticket)==false,"reset ticket replayed")
        input("files")
        assert(#w:menuOptions()==1 and w:menuOptions()[1].systemCommand=="back","empty directory has stale entries")
        assert(getSpecificPlayer(1)==nil,"local reset changed player ownership")
        log("PASS native clean operator, empty directory, stable physical identity and unrelated payload; no secondary slot")
        run.step,run.next=5,now+1500
    elseif run.step==5 then
        shot("empty-files")
        SC.Terminal.window:close() SC.Terminal.resetSessions()
        assert(SC.Terminal.open(player,run.pc),"clean machine failed to reopen")
        local w=SC.Terminal.window w:flush()
        assert(w.system.archive=="_factory" and w.system.brand=="_camp" and #w.session.notes==0,"reopen restored old software")
        input("county files")
        assert(#w.referenceCatalog>0,"factory reset removed installed county reference software")
        input("back")
        log("PASS native reopen preserves clean setup and installed reference library")
        run.step,run.next=6,now+1500
    elseif run.step==6 then
        shot("clean-emma")
        SC.Terminal.window:close()
        log("PASS native terminal reset acceptance complete")
        run.step,run.next=99,now+1000000
    end
end
Events.OnTick.Add(function()
    local okay,reason=pcall(tick)
    if not okay then log("FAIL "..tostring(reason)) run.step,run.next=99,getTimestampMs()+1000000 end
end)
