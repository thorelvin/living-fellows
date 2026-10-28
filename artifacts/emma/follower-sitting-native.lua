-- SPDX-License-Identifier: MIT
-- Real furniture and walking in the existing disposable clone. Controlled
-- second entry bypasses candidate cooldown to test interruption separately.
local run={step=0,next=0,manual=true}
local function log(text)
    print("FOLLOWER_SITTING|"..text)
    local w=getFileWriter("SurvivorCompanionHarness/follower-sitting.log",true,true)
    if w then w:write(text.."\n") w:close() end
end
local function shot(name) getCore():TakeFullScreenshot("emma-follower-sitting-"..name) log("SHOT "..name) end
local function tick()
    local now=getTimestampMs()
    if now<run.next then return end
    local SC=SurvivorCompanion local player=getSpecificPlayer(0)
    if not SC or not SC.Registry or not SC.Downtime or not player or not player:getSquare() then return end
    local D,U=SC.Downtime,SC.GameplayUtil
    local _,seat,_,begin,_,_,_,_,_,_,_,stateFor=D._furnitureForTests()
    if run.step==0 then
        run.deadline=run.deadline or now+45000
        for _,record in ipairs(SC.Registry.snapshot()) do
            local actor=record.actor
            if actor and actor~=player and actor:getSquare() and actor:getSquare():getRoom()
                and SC.Commands.peek(actor).recruited then
                local candidate=seat(actor,stateFor(actor),now,true)
                if candidate and U.distance(actor,candidate.object)<=3 then
                    local s=candidate.object:getSquare()
                    for _,o in ipairs({{1,0},{-1,0},{0,1},{0,-1},{1,1},{-1,-1}}) do
                        local t=getCell():getGridSquare(s:getX()+o[1],s:getY()+o[2],s:getZ())
                        if t and t:getRoom()==s:getRoom() and U.isSquareFree(t)
                            and not U.movingBlocker(t,actor) and U.distance(actor,t)<=4 then
                            run.actor,run.id,run.chair,run.anchor=actor,record.id,candidate.object,t break
                        end
                    end
                end
            end
            if run.actor then break end
        end
        if not run.actor then assert(now<run.deadline,"no companion near a genuine native chair") run.next=now+500 return end
        player:setGodMod(true) player:setGhostMode(true)
        player:teleportTo(run.anchor:getX()+0.5,run.anchor:getY()+0.5,run.anchor:getZ())
        run.actor:setGodMod(true)
        D.cancel(run.actor,"sitting_acceptance_setup")
        if SC.ActionSupervisor.current(run.actor) then SC.ActionSupervisor.cancel(run.actor,"sitting_acceptance_setup",nil,true) end
        assert(SC.BaseLife.setDuty(run.id,false),"could not leave base duty in clone")
        assert(SC.Commands.issue(run.id,"follow",{},player),"Follow refused")
        SC.Commands.peek(run.actor).scavenge=false
        local stats=run.actor:getStats()
        for _,name in ipairs({"HUNGER","THIRST","FATIGUE"}) do stats:set(CharacterStat[name],0.1) end
        stats:set(CharacterStat.ENDURANCE,1)
        run.originalDecision=SC.Decision.update
        SC.Decision.update=function(actor,...)
            if actor==run.actor and run.manual then return true,"sitting_acceptance_controlled" end
            return run.originalDecision(actor,...)
        end
        run.state=stateFor(run.actor)
        run.runtime={snapshot={indoors=true,threatCount=0,immediateCount=0,player={danger=0}}}
        if SC.UI and SC.UI.instance then SC.UI.instance:setVisible(false) end
        run.step,run.next=1,now+1000
        log("SETUP actor="..run.id.." chair="..tostring(run.chair:getSprite():getName()))
    elseif run.step==1 then
        if not run.readyAt then
            D.update(run.actor,player,run.runtime,"sit")
            run.readyAt=run.state.followStillSince+SC.Config.get("followSitDelayMs")
        elseif now>=run.readyAt then
            local a={kind="sit",object=run.chair,square=run.chair:getSquare(),fact={activity="sit"}}
            local okay,why=begin(run.actor,run.state,a,SC.Commands.peek(run.actor),now)
            assert(okay,"chair entry refused: "..tostring(why))
            run.step,run.deadline=2,now+45000
            log("PASS native short leader pause did not start sitting") return
        else D.update(run.actor,player,run.runtime,"sit") end
        assert(not run.state.active,"sat before stillness delay") run.next=now+250
    elseif run.step==2 or run.step==4 then
        D.update(run.actor,player,run.runtime,"sit")
        local a=run.state.active
        if a and a.startedAt then
            assert(a.furnitureEntered and a.durationMs==15000 and a.gameDurationHours==nil,"rest lost short duration")
            assert(SC.NativeActions.seatingStatus(run.actor)=="furniture","not physically sitting on chair")
            run.startedAt,run.activity=a.startedAt,a
            run.step,run.next=run.step==2 and 3 or 5,now+1000
            log("PASS native chair entered durationMs="..a.durationMs)
        else assert(now<run.deadline,"native chair entry stalled") run.next=now+100 end
    elseif run.step==3 then
        if not run.sitShot then shot("short-pause") run.sitShot=true end
        D.update(run.actor,player,run.runtime,"sit")
        if not run.state.active then
            log("COMPLETE preserve="..tostring(run.activity.preserveSeating).." exitRequired="..tostring(run.activity.exitRestRequired))
            assert(now-run.startedAt>=15000 and now-run.startedAt<26000,"sit ended outside bound")
            run.step,run.deadline=31,now+10000
        else run.next=now+100 end
    elseif run.step==31 then
        if SC.NativeActions.seatingStatus(run.actor)~="standing" then
            assert(now<run.deadline,"routine pause did not get up") run.next=now+100 return
        end
        assert(not SC.ActionSupervisor.current(run.actor),"finished sit retained ownership")
        assert(not D.canPerform(run.actor,"sit"),"repeat cooldown missing")
        log("PASS native routine rest finished, stood up and retained repeat cooldown") shot("finished")
        run.step,run.deadline,run.next=32,now+30000,now+1000
    elseif run.step==32 then
        local queue=ISTimedActionQueue.getTimedActionQueue(run.actor)
        local pacing=SC.NativeActions.pacingStatus(run.actor,now)
        if pacing or queue and type(queue.queue)=="table" and #queue.queue>0 then
            assert(now<run.deadline,"first sit's native feedback did not finish") run.next=now+250 return
        end
        local a={kind="sit",object=run.chair,square=run.chair:getSquare(),fact={activity="sit"}}
        local okay,why=begin(run.actor,run.state,a,SC.Commands.peek(run.actor),now)
        if not okay then
            log("DEFER controlled second sit: "..tostring(why))
            assert(now<run.deadline,"controlled second sit refused: "..tostring(why))
            run.next=now+1000 return
        end
        run.step,run.deadline,run.next=4,now+45000,now+100
    elseif run.step==5 then
        local s=player:getSquare() local target
        for _,o in ipairs({{1,0},{-1,0},{0,1},{0,-1}}) do
            local t=getCell():getGridSquare(s:getX()+o[1],s:getY()+o[2],s:getZ())
            if t and t:getRoom()==s:getRoom() and U.isSquareFree(t)
                and not U.movingBlocker(t,player) and U.distance(run.actor,t)<4 then target=t break end
        end
        assert(target,"no nearby native walking target")
        run.playerX,run.playerY=player:getX(),player:getY()
        run.manual=false
        ISTimedActionQueue.add(ISWalkToTimedAction:new(player,target))
        run.step,run.deadline,run.next=6,now+10000,now+100
    elseif run.step==6 then
        run.moved=run.moved or player:isMoving() or (player:getX()-run.playerX)^2+(player:getY()-run.playerY)^2>0.04
        if run.moved and not run.state.active and SC.NativeActions.seatingStatus(run.actor)=="standing" then
            assert(U.distance(run.actor,player)<4.5,"only interrupted after leaving follow radius")
            assert(not SC.ActionSupervisor.current(run.actor),"movement retained sitting ownership")
            log("PASS native nearby walking leader interrupted sit inside follow radius")
            local status=D.status(run.actor)
            log("STATUS kind="..status.kind.." fatigue="..tostring(status.fatigue).." endurance="..tostring(status.endurance))
            shot("follow-resumed") SC.Decision.update=run.originalDecision
            log("PASS native follower sitting acceptance complete")
            run.step,run.next=99,now+1000000
        else assert(now<run.deadline,"nearby native walking did not interrupt sitting") run.next=now+100 end
    end
end
Events.OnTick.Add(function()
    local okay,reason=pcall(tick)
    if not okay then log("FAIL "..tostring(reason)) run.step,run.next=99,getTimestampMs()+1000000 end
end)
