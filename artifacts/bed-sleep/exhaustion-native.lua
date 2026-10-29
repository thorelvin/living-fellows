-- SPDX-License-Identifier: MIT
-- Automatic chair-to-bed recovery in the disposable camp clone.
local run={step=0,next=0,scan=0,beds={},chairs={}}
local function log(value)
    print("EXHAUSTED_SLEEP|"..value)
    local w=getFileWriter("SurvivorCompanionHarness/exhaustion-sleep.log",true,true)
    if w then w:write(value.."\n") w:close() end
end
local quiet={snapshot={threatCount=0,immediateCount=0,threats={},indoors=true,player={danger=0}}}
local function tick()
    local now=getTimestampMs()
    if now<run.next then return end
    local SC=SurvivorCompanion local player=getSpecificPlayer(0)
    if not SC or not player or not player:getSquare() or not SC.Downtime then return end
    local U,D=SC.GameplayUtil,SC.Downtime
    if run.step==0 then
        for _,actor in ipairs(SC.Registry.living()) do
            if actor:getSquare() and SC.Commands.describe(SC.Registry.idOf(actor),player).recruited then
                run.actor=run.actor or actor
                if U.nameOf(actor):find("Tess",1,true) then run.actor=actor break end
            end
        end
        if not run.actor then run.next=now+500 return end
        run.originalDecision=SC.Decision.update
        SC.Decision.update=function(actor,...)
            if actor==run.actor then return true,"sleep_acceptance_owned" end
            return run.originalDecision(actor,...)
        end
        local originalBedStatus=SC.NativeActions.bedStatus
        run.originalBedStatus=originalBedStatus
        SC.NativeActions.bedStatus=function(actor)
            local bed=actor==run.actor and SC.NativeActions._bedRestForTests(actor)
            local pillow=bed and bed.bedEntry and bed.bedEntry.pillow
            local x,y=math.floor(actor:getX()),math.floor(actor:getY())
            if actor==run.actor and run.pillowClearPending then
                if run.blockedPillow:getMovingObjects():contains(player) then return "entering" end
                run.pillowClearPending=nil
            elseif not run.occupiedPillowChecked and pillow and actor:isOnBed()
                and actor:getVariableBoolean("OnBedStarted")
                and ((x==pillow.x and y==pillow.y+1)
                    or (y==pillow.y and math.abs(x-pillow.x)==1)) then
                if not run.observerBeforeBlock then
                    run.observerBeforeBlock={player:getX(),player:getY(),player:getZ()}
                    run.blockedPillow=getCell():getGridSquare(pillow.x,pillow.y,pillow.z)
                    player:teleportTo(pillow.x+0.5,pillow.y+0.5,pillow.z)
                    return "entering"
                end
                -- Native teleport updates moving-square membership on the
                -- next player update; coordinates alone do not block a tile.
                if not run.blockedPillow:getMovingObjects():contains(player) then return "entering" end
                local ax,ay=actor:getX(),actor:getY()
                local accepted=SCBridge.shiftOnBedPoseTowardPillow(actor,pillow.x,pillow.y,pillow.z)
                local reason=SCBridge.getLastFailure()
                local previous=run.observerBeforeBlock
                player:teleportTo(previous[1],previous[2],previous[3])
                assert(not accepted and tostring(reason):find("occupied",1,true)
                    and actor:getX()==ax and actor:getY()==ay,
                    "occupied pillow must reject alignment without moving the sleeper: "..tostring(reason))
                run.occupiedPillowChecked,run.pillowClearPending=true,true
                log("PASS occupied pillow rejects native correction without moving sleeper")
                return "entering"
            end
            local state,at=originalBedStatus(actor)
            if actor==run.actor and state=="failed" then
                local bed=SC.NativeActions._bedRestForTests(actor) or {}
                log("BED_FAILURE reason="..tostring(bed.failure).." alignment="..tostring(bed.alignmentFailure)
                    .." fallback="..tostring(bed.fallbackGround).." cancelled="..tostring(bed.cancelled)
                    .." pose="..tostring(bed.pose).." onBed="..tostring(actor:isOnBed())
                    .." started="..tostring(actor:getVariableBoolean("OnBedStarted"))
                    .." pos="..actor:getX()..","..actor:getY()
                    .." pillow="..tostring(bed.bedEntry and bed.bedEntry.pillow and bed.bedEntry.pillow.x)
                    ..","..tostring(bed.bedEntry and bed.bedEntry.pillow and bed.bedEntry.pillow.y))
                local other=bed.bedEntry and bed.bedEntry.otherPillow
                local _,x=SC.Call.method(actor,"getX")
                log("BED_TYPES x="..type(x).." other="..tostring(other and other.x)..","..tostring(other and other.y))
            end
            return state,at
        end
        run.x,run.y=math.floor(player:getX())-35,math.floor(player:getY())-35
        run.kind=select(1,D._furnitureForTests())
        player:setGodMod(true) player:setGhostMode(true)
        getGameTime():setTimeOfDay(12)
        SC.UI.close()
        pcall(function() getPlayerInventory(0):setVisible(false) end)
        pcall(function() getPlayerLoot(0):setVisible(false) end)
        pcall(function() getPlayerInfoPanel(0):setVisible(false) end)
        pcall(function() getPlayerMiniMap(0):setVisible(false) end)
        run.step=1
    elseif run.step==1 then
        for _=1,400 do
            if run.scan>=71*71 then break end
            local x,y=run.x+run.scan%71,run.y+math.floor(run.scan/71)
            run.scan=run.scan+1
            local sq=getCell():getGridSquare(x,y,0)
            if sq and sq:getRoom() then
                for i=0,math.min(31,sq:getObjects():size()-1) do
                    local object=sq:getObjects():get(i) local kind=run.kind(object)
                    if kind=="rest_bed" then run.beds[#run.beds+1]=object
                    elseif kind=="sit" then run.chairs[#run.chairs+1]=object end
                end
            end
        end
        if run.scan<71*71 then run.next=now+100 return end
        local best
        for _,bed in ipairs(run.beds) do
            local normalized,entry=SC.BedGeometry.entry(bed,run.actor)
            if normalized and entry then
                for _,chair in ipairs(run.chairs) do
                    if chair:getSquare():getRoom()==bed:getSquare():getRoom()
                        and U.distance(bed,chair)<7 then
                        local score=U.distance(bed,player)+(SC.BaseLife.isInside(bed) and -100 or 0)
                        if not best or score<best.score then best={bed=normalized,chair=chair,entry=entry,score=score} end
                    end
                end
            end
        end
        assert(best,"no real bedroom with usable bed and chair in clone")
        run.bed,run.chair=best.bed,best.chair
        local room=run.bed:getSquare():getRoom()
        local squares=room:getSquares() local observer
        for i=0,squares:size()-1 do
            local sq=squares:get(i)
            if U.isClearActorSpawnSquare(sq) then observer=sq break end
        end
        assert(observer,"bedroom observer needs clear floor")
        player:teleportTo(observer:getX()+0.5,observer:getY()+0.5,0)
        local actor=run.actor local id=SC.Registry.idOf(actor)
        SC.Commands.issue(id,"stay",nil,player)
        D.cancel(actor,"sleep_acceptance_setup")
        SC.Decision.cancelWork(actor,"sleep_acceptance_setup")
        SC.Encounter.cancelScavenge(actor,"sleep_acceptance_setup")
        SC.ActionSupervisor.cancel(actor,"sleep_acceptance_setup",nil,true)
        SC.BaseLife.setDuty(id,false)
        actor:teleportTo(observer:getX()+0.5,observer:getY()+0.5,0)
        actor:getStats():set(CharacterStat.FATIGUE,0.2)
        actor:getStats():set(CharacterStat.HUNGER,0.1) actor:getStats():set(CharacterStat.THIRST,0.1)
        if SC.BaseLife.isInside(run.bed) then
            local minX,minY,maxX,maxY=30000,30000,0,0
            for i=0,squares:size()-1 do local sq=squares:get(i)
                minX,minY=math.min(minX,sq:getX()),math.min(minY,sq:getY())
                maxX,maxY=math.max(maxX,sq:getX()),math.max(maxY,sq:getY())
            end
            local begun=SC.BaseLife.beginZone("rest",getCell():getGridSquare(minX,minY,0))
            local marked=begun and SC.BaseLife.finishZone(getCell():getGridSquare(maxX,maxY,0),"Sleep acceptance bedroom")
            log("FIXTURE marked-rest="..tostring(marked))
        end
        local begin=select(4,D._furnitureForTests()) local stateFor=select(12,D._furnitureForTests())
        local started,why=begin(actor,stateFor(actor),{kind="sit",object=run.chair,
            square=run.chair:getSquare(),fact={activity="sit"}},SC.Commands.peek(actor),now)
        assert(started,"native chair fixture failed: "..tostring(why))
        run.step,run.deadline,run.next=2,now+90000,now+250
    elseif run.step==2 then
        local handled,why=D.update(run.actor,player,quiet,"sit")
        if SC.NativeActions.furnitureStatus(run.actor)=="entered" then
            run.actor:getStats():set(CharacterStat.FATIGUE,1)
            log("PASS native chair occupied; fatigue raised to 100 percent")
            run.capture="exhaustion-chair"
            run.step,run.deadline,run.next=3,now+120000,now+250
        else assert(now<run.deadline,"native chair did not settle: "..tostring(why)) run.next=now+250 end
    elseif run.step==3 then
        local handled,why=D.update(run.actor,player,quiet)
        if why=="standing_for_sleep" then run.sawSwitch=true log("PASS automatic chair rest cancelled for available bed") end
        local state=D.peek(run.actor)
        local active=state and state.active
        if active and active.kind=="rest_bed" then run.sawBedLease=true end
        if run.sawBedLease and active and active.kind=="read" then
            log("UNEXPECTED fatigue="..U.characterStatValue(run.actor,"FATIGUE",-1)
                .." lastWake="..tostring(state.lastBedWakeHour).." sleepCheck="..tostring(state.sleepReason)
                .." fact="..tostring(state.lastFact and state.lastFact.activity)
                .." nowHour="..getGameTime():getWorldAgeHours())
            for _,event in ipairs(SC.ActionSupervisor.history(run.actor,24)) do
                log("HISTORY "..tostring(event.event).." action="..tostring(event.action)
                    .." phase="..tostring(event.phase).." reason="..tostring(event.reason))
            end
            error("bed sleep was replaced by reading")
        end
        local clips=run.actor:getCompanionActiveAnimationNames()
        if now>=(run.traceAt or 0) then
            log("TRACE "..tostring(why).." seating="..SC.NativeActions.seatingStatus(run.actor)
                .." asleep="..tostring(run.actor:isAsleep()).." clips="..clips)
            run.traceAt=now+5000
        end
        if run.actor:isAsleep() and run.actor:isOnBed() and clips:find("Bob_Asleep",1,true)
            and not clips:find("ToAsleep",1,true) then
            assert(run.sawSwitch,"sleep did not follow the automatic chair transition")
            assert(run.occupiedPillowChecked,"native occupied-pillow rejection was not exercised")
            assert(getSpecificPlayer(1)==nil,"sleep created a second view")
            local squares=run.actor:getSquare():getRoom():getSquares()
            local observer,gap
            for i=0,squares:size()-1 do
                local sq=squares:get(i)
                if not sq:isSolid() and not sq:isSolidTrans() and sq:TreatAsSolidFloor()
                    and U.squareOccupyingObject(sq)==nil and sq:getMovingObjects():size()==0 then
                    local distance=U.distance(run.actor,sq)
                    if not gap or distance<gap then observer,gap=sq,distance end
                end
            end
            if observer then player:teleportTo(observer:getX()+0.5,observer:getY()+0.5,0) end
            getCore():setAutoZoom(0,false)
            for _=1,20 do getCore():doZoomScroll(0,-1) end
            run.sleepShotAt=now+2000
            log("PASS automatic native bed sleep clip="..clips)
            run.step,run.next=4,now+5000
        else assert(now<run.deadline,"automatic native sleep timed out: "..tostring(why)) run.next=now+250 end
    elseif run.step==4 then
        D.update(run.actor,player,quiet)
        local fatigue=U.characterStatValue(run.actor,"FATIGUE",1)
        assert(run.actor:isAsleep() and fatigue<1,"real sleep did not lower fatigue")
        log("PASS fatigue recovering="..fatigue.." health="..run.actor:getBodyDamage():getHealth())
        assert(D.wakeForAlarm(run.actor),"ordinary wake rejected")
        assert(not run.actor:isAsleep(),"alarm wake left the actor asleep")
        SC.Decision.update=run.originalDecision
        SC.NativeActions.bedStatus=run.originalBedStatus
        log("PASS native exhaustion sleep acceptance complete") run.step=99
    end
end
local function safeTick()
    local ok,err=pcall(tick)
    if not ok then log("FAIL "..tostring(err)) Events.OnTick.Remove(safeTick) end
end
Events.OnTick.Add(safeTick)
Events.OnPostUIDraw.Add(function()
    if run.capture then getCore():TakeFullScreenshot(run.capture) run.capture=nil end
    if run.sleepShotAt and getTimestampMs()>=run.sleepShotAt then
        getCore():TakeFullScreenshot("exhaustion-sleeping") run.sleepShotAt=nil
    end
end)
