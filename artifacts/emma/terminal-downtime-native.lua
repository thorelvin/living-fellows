-- Disposable cloned-world check with a real companion and native timed action.
local run={step=0,next=0,deadline=0}
local function log(value)
    print("EMMA_DOWNTIME|"..value)
    local w=getFileWriter("SurvivorCompanionHarness/terminal-downtime.log",true,true)
    if w then w:write(value.."\n") w:close() end
end
local function command(actor) return SurvivorCompanion.Commands.peek(actor) end
local function beginAgain(now)
    local SC=SurvivorCompanion
    local state=SC.Downtime.peek(run.actor)
    if state.active and state.active.kind~="computer_use" then
        SC.Downtime.cancel(run.actor,"terminal_acceptance_next_scenario")
        run.blocked="other downtime: "..tostring(state.active and state.active.kind)
        return false
    end
    local queue=ISTimedActionQueue.getTimedActionQueue(run.actor)
    if queue and type(queue.queue)=="table" and #queue.queue>0 then
        run.blocked="native queue length="..#queue.queue return false
    end
    state.computerRetryAt=0
    local candidate=SC.ComputerUse.candidate(run.actor,state,now,{
        seatingStatus=SC.NativeActions.seatingStatus,reserved=function() return false end})
    if not candidate then run.blocked="no candidate; available="..tostring(SC.Terminal.companionAvailable(run.object)) return false end
    local begin=select(4,SC.Downtime._furnitureForTests())
    local okay,reason=begin(run.actor,state,candidate,command(run.actor),now)
    run.blocked=reason
    return okay==true
end
local function tick()
    local now=getTimestampMs()
    if now<run.next then return end
    local SC=SurvivorCompanion
    local player=getSpecificPlayer(0)
    if not SC or not SC.ComputerUse or not SC.Registry or not player or not player:getCurrentSquare() then return end
    if run.step==0 then
        player:setGodMod(true) player:setGhostMode(true)
        if SC.UI and SC.UI.instance then SC.UI.instance:setVisible(false) end
        if run.deadline==0 then
            run.deadline=now+30000
            log("START native computer downtime release="..SC.Identity.release)
        end
        for _,record in ipairs(SC.Registry.snapshot()) do
            local actor=record.actor
            local square=actor and actor:getCurrentSquare()
            if actor and actor~=player and square and square:getRoom()
                and SC.BaseLife.isInside(actor) and command(actor).recruited==true
                and not (SC.BaseWatch and SC.BaseWatch.isLeaderId(record.id)) then
                for _,offset in ipairs({{2,0},{-2,0},{0,2},{0,-2},{1,0},{-1,0},{0,1},{0,-1}}) do
                    local target=getCell():getGridSquare(square:getX()+offset[1],square:getY()+offset[2],square:getZ())
                    if target and target:getRoom()==square:getRoom() and SC.BaseLife.isInside(target)
                        and SC.GameplayUtil.isSquareFree(target)
                        and not SC.GameplayUtil.movingBlocker(target,actor) then
                        run.actor,run.id,run.square=actor,record.id,target break
                    end
                end
            end
            if run.actor then break end
        end
        if not run.actor then
            assert(now<run.deadline,"no loaded indoor recruited companion in the cloned camp")
            run.next=now+1000 return
        end
        run.actor:setGodMod(true)
        SC.Downtime.cancel(run.actor,"terminal_acceptance_setup")
        if SC.ActionSupervisor.current(run.actor) then
            SC.ActionSupervisor.cancel(run.actor,"terminal_acceptance_setup",nil,true)
        end
        assert(SC.BaseLife.setDuty(run.id,false),"test companion could not leave active base jobs")
        assert(SC.Commands.issue(run.id,"stay",{},player),"stay order was rejected")
        SC.Decision.cancelWork(run.actor,"terminal_acceptance_setup")
        -- Advance this actor's downtime explicitly. The normal decision loop
        -- may correctly choose scavenging after an interrupted visit; that
        -- would prevent the next controlled handoff scenario from starting.
        -- Other actors, native updates and the action supervisor keep running.
        local originalDecision=SC.Decision.update
        SC.Decision.update=function(actor,...)
            if actor==run.actor then return true,"terminal_acceptance_manual" end
            return originalDecision(actor,...)
        end
        run.object=IsoObject.new(getCell(),run.square,"appliances_com_01_72")
        run.square:AddTileObject(run.object)
        local originalPower=SC.Terminal.powered
        run.powered=true
        SC.Terminal.powered=function(object)
            if object==run.object then return run.powered end
            return originalPower(object)
        end
        -- Other real desktops can be closer after the actor moves. Keep the
        -- controlled power/ownership scenarios bound to this exact fixture.
        local originalAvailable=SC.Terminal.companionAvailable
        SC.Terminal.companionAvailable=function(object)
            return object==run.object and originalAvailable(object)
        end
        assert(SC.Terminal.companionAvailable(run.object),"fresh camp computer should not require a prior player session")
        local system=SC.Terminal.computerState(player,run.object)
        assert(system and system.locked==false,"new camp desk should be unlocked")
        log("TARGET isComputer="..tostring(SC.Terminal.isComputer(run.object))
            .." available="..tostring(SC.Terminal.companionAvailable(run.object))
            .." custom="..tostring(run.object:getProperties():get("CustomName"))
            .." room="..tostring(run.square:getRoom():getName())
            .." camp="..tostring(SC.BaseLife.isInside(run.object)))
        assert(SC.Terminal.companionAvailable(run.object),"fixture must be a real eligible desktop")
        run.archive=system.archive
        run.object:getModData().movableData.LF_Emma={operator="Fixture operator",visits=7,notes={"Private operator note"}}
        run.runtime={snapshot={threatCount=0,immediateCount=0,player={danger=0}}}
        run.initialDistance=SC.GameplayUtil.distance(run.actor,run.object)
        log("SETUP companion="..run.id.." distance="..tostring(run.initialDistance))
        run.step,run.next,run.deadline=1,now+500,now+60000
    elseif run.step==1 then
        SC.Downtime.update(run.actor,player,run.runtime,"computer_use")
        local state=SC.Downtime.peek(run.actor)
        local active=state and state.active
        if active and active.kind=="computer_use" and active.startedAt then
            assert(active.object==run.object,"native visit selected a different computer")
            assert(SC.ComputerUse.valid(run.actor,active,true),"companion has not reached a genuine keyboard use position")
            local token=SC.ActionSupervisor.current(run.actor)
            assert(token and token.owner=="downtime" and token.action=="computer_use","native supervisor lost the computer action")
            assert(SC.NativeActions.visualStatus(run.actor,"computer_use")=="active","computer pose was not a real native action")
            log("PASS native approach, direct access, ownership and active hand-work pose")
            run.captureAt=now+2500
            run.step,run.next,run.deadline=2,now+500,now+70000
        else
            assert(now<run.deadline,"companion never reached or started the camp computer")
            run.next=now+500
        end
    elseif run.step==2 then
        SC.Downtime.update(run.actor,player,run.runtime,"computer_use")
        if run.captureAt and now>=run.captureAt then
            getCore():TakeFullScreenshot("emma-computer-downtime-active") run.captureAt=nil
        end
        local state=SC.Downtime.peek(run.actor)
        if state and not state.active and state.lastFact and state.lastFact.activity=="computer_use" then
            assert(state.lastFact.referenceId and SC.TerminalLore.reference(state.lastFact.referenceId),"completion did not name a real local file")
            local memory=run.object:getModData().movableData.LF_Emma
            assert(memory.operator=="Fixture operator" and memory.visits==7 and #memory.notes==1
                and memory.notes[1]=="Private operator note","NPC use changed the player's memory or notes")
            assert(SC.Terminal.computerState(player,run.object).archive==run.archive,"NPC use rerolled the owner archive")
            log("PASS verified native completion reference="..state.lastFact.referenceId.." operator-memory=unchanged")
            run.step,run.next,run.deadline=21,now+3000,now+30000
        else
            assert(now<run.deadline,"native computer action did not finish or verify") run.next=now+500
        end
    elseif run.step==21 or run.step==31 then
        if beginAgain(now) then
            run.step,run.next,run.deadline=run.step==21 and 3 or 4,now+500,now+15000
        else
            assert(now<run.deadline,"next owned scenario unavailable after cleanup: "..tostring(run.blocked))
            run.next=now+1000
        end
    elseif run.step==3 then
        SC.Downtime.update(run.actor,player,run.runtime,"computer_use")
        local active=SC.Downtime.peek(run.actor).active
        if active and active.startedAt then
            assert(active.object==run.object,"power-loss scenario changed computers")
            run.powered=false
            SC.Downtime.update(run.actor,player,run.runtime,"computer_use")
            local state=SC.Downtime.peek(run.actor)
            assert(not state.active and state.computerRetryAt>now,"power loss did not cancel and pause the visit")
            log("PASS native power-loss cancellation and retry pause")
            run.powered=true
            run.step,run.next,run.deadline=31,now+3000,now+30000
        else assert(now<run.deadline,"second native visit failed to start") run.next=now+500 end
    elseif run.step==4 then
        SC.Downtime.update(run.actor,player,run.runtime,"computer_use")
        local active=SC.Downtime.peek(run.actor).active
        if active and active.startedAt then
            assert(SC.ComputerUse.yieldToPlayer(run.object),"player priority failed to cancel the NPC visit")
            assert(not SC.Downtime.peek(run.actor).active,"NPC retained ownership after yielding")
            log("PASS native player-priority cancellation")
            run.square:RemoveTileObject(run.object)
            log("PASS native terminal downtime acceptance complete")
            run.step,run.next=99,now+1000000
        else assert(now<run.deadline,"third native visit failed to start") run.next=now+500 end
    end
end
Events.OnTick.Add(function()
    local okay,reason=pcall(tick)
    if not okay then log("FAIL "..tostring(reason)) run.step,run.next=99,getTimestampMs()+1000000 end
end)
