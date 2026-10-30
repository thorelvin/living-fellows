-- SPDX-License-Identifier: MIT
-- Visual sleep/wake acceptance in the disposable camp clone. Setup places the
-- fixture beside an existing bed; entry, sleep and exit use production paths.
local run={step=0,next=0,beds={},scan=0,zeroSeatingOnly=SC_TEST_ZERO_SEATING_BED==true}
local function log(value)
    print("BED_SLEEP|"..value)
    local writer=getFileWriter("SurvivorCompanionHarness/bed-sleep.log",true,true)
    if writer then writer:write(value.."\n") writer:close() end
end
local function tick()
    local now=getTimestampMs()
    if now<run.next then return end
    local SC=SurvivorCompanion
    local player=getSpecificPlayer(0)
    if not SC or not player or not player:getSquare() or not SC.Downtime then return end
    local U=SC.GameplayUtil
    if run.step==0 then
        local actor
        for _,candidate in ipairs(SC.Registry.living()) do
            if candidate:getSquare() and SC.Commands.describe(SC.Registry.idOf(candidate),player).recruited then
                actor=actor or candidate
                if U.nameOf(candidate):find("Tess",1,true) then actor=candidate break end
            end
        end
        if not actor then run.next=now+500 return end
        run.actor,run.id=actor,SC.Registry.idOf(actor)
        run.manualRest=true
        run.originalDecision=SC.Decision.update
        SC.Decision.update=function(candidate,...)
            if candidate==run.actor and run.manualRest then return true,"bed_visual_acceptance" end
            return run.originalDecision(candidate,...)
        end
        run.recoveries=0
        local stockRecover=SC.Actor.recover
        SC.Actor.recover=function(candidate,...)
            if candidate==run.actor then run.recoveries=run.recoveries+1 end
            return stockRecover(candidate,...)
        end
        local stockMove=SC.Actor.setMovement
        SC.Actor.setMovement=function(candidate,mode,intent,...)
            if candidate==run.actor and run.zoomHold then
                return SC.Actor.stop(candidate)
            end
            local function observed(...)
                local accepted,why=...
                if candidate==run.actor and intent and intent.action=="rest_bed" then
                    log("ENTRY "..tostring(accepted)..":"..tostring(why)
                        .." object="..intent.object:getSprite():getName())
                    run.sawEntry=accepted==true
                    run.bedRecord=SC.NativeActions._bedRestForTests(candidate)
                    if not accepted then run.entryFailure=why or "rejected" end
                end
                return ...
            end
            return observed(stockMove(candidate,mode,intent,...))
        end
        local radius=run.zeroSeatingOnly and 48 or 35
        run.span=radius*2+1
        run.ox,run.oy=math.floor(player:getX())-radius,math.floor(player:getY())-radius
        run.kind=SC.Downtime._furnitureForTests()
        player:setGodMod(true) player:setGhostMode(true)
        getGameTime():setTimeOfDay(12)
        SC.UI.close()
        local info=getPlayerInfoPanel(0)
        if info then info:setVisible(false) end
        local mini=getPlayerMiniMap(0)
        if mini then mini:setVisible(false) end
        run.step=1
    elseif run.step==1 then
        for _=1,300 do
            if run.scan>=run.span*run.span then break end
            local x,y=run.ox+run.scan%run.span,run.oy+math.floor(run.scan/run.span)
            run.scan=run.scan+1
            local square=getCell():getGridSquare(x,y,0)
            if square then
                for index=0,math.min(31,square:getObjects():size()-1) do
                    local object=square:getObjects():get(index)
                    local sprite=object:getSprite()
                    if sprite and sprite:getSpriteGrid() and run.kind(object)=="rest_bed"
                        and (not run.zeroSeatingOnly or SeatingManager.getInstance():getTilePositionCount(object)==0) then
                        run.beds[#run.beds+1]=object
                    end
                end
            end
        end
        if run.scan<run.span*run.span then run.next=now+100 return end
        assert(#run.beds>0,"no existing sprite-grid bed in the loaded fixture")
        table.sort(run.beds,function(a,b)return U.distance(run.actor,a)<U.distance(run.actor,b)end)
        local entry,observer
        for _,bed in ipairs(run.beds) do
            local room=bed:getSquare():getRoom()
            local normalized,point,why=SC.BedGeometry.entry(bed,run.actor)
            log("GEOMETRY "..bed:getSprite():getName().." "..tostring(why)
                .." entry="..tostring(point and point.x)..","..tostring(point and point.y))
            local options={}
            for dx=-3,3 do for dy=-3,3 do
                local square=getCell():getGridSquare(bed:getX()+dx,bed:getY()+dy,0)
                if square and square:getRoom()==room and U.isSafeSpawnSquare(square)
                    and (not point or math.floor(point.x)~=square:getX() or math.floor(point.y)~=square:getY()) then
                    options[#options+1]=square
                end
            end end
            if normalized and point and #options>=1 then
                run.bed=normalized
                entry=getCell():getGridSquare(math.floor(point.x),math.floor(point.y),point.z)
                observer=options[#options]
                break
            end
        end
        assert(entry and observer,"bedroom has no two clear setup tiles")
        assert(SC.Commands.issue(run.id,"stay",nil,player))
        SC.Downtime.cancel(run.actor,"bed_sleep_fixture_setup")
        SC.Decision.cancelWork(run.actor,"bed_sleep_fixture_setup")
        SC.Encounter.cancelScavenge(run.actor,"bed_sleep_fixture_setup")
        SC.ActionSupervisor.cancel(run.actor,"bed_sleep_fixture_setup",nil,true)
        SC.BaseLife.setDuty(run.id,false)
        player:teleportTo(observer:getX()+0.5,observer:getY()+0.5,observer:getZ())
        assert(SC.Actor.recover(run.actor,entry),"fixture placement failed")
        -- Recovery can reapply the camp order at its original home anchor.
        -- The selected bed may be in another loaded house; establish the
        -- fixture's Stay order after placement, against the current actor.
        run.actor=SC.Registry.byId(run.id).actor
        assert(run.actor and run.actor:getSquare(),"fixture recovery lost its actor")
        SC.BaseLife.setDuty(run.id,false)
        assert(SC.Commands.issue(run.id,"stay",nil,player))
        log("FIXTURE order="..tostring(SC.Commands.peek(run.actor).order))
        run.actor:getStats():set(CharacterStat.FATIGUE,0.9)
        run.actor:getStats():set(CharacterStat.HUNGER,0.1)
        run.actor:getStats():set(CharacterStat.THIRST,0.1)
        run.entryRecoveries,run.entryHealth=run.recoveries,run.actor:getBodyDamage():getHealth()
        run.initialDialogueSay=SC.Dialogue.say
        SC.Dialogue.say=function(actor,...)
            if actor==run.actor then return false,"speech_capture_fixture" end
            return run.initialDialogueSay(actor,...)
        end
        run.singleLine="I will watch the road."
        assert(U.say(run.actor,run.singleLine),"awake speech fixture was rejected")
        assert(run.actor:hasCompanionSpeech(),"awake speech fixture has no visible line")
        log("FIXTURE existing bed="..run.bed:getSprite():getName().." actor="..U.nameOf(run.actor))
        if run.zeroSeatingOnly then
            assert(SeatingManager.getInstance():getTilePositionCount(run.bed)==0,
                "zero-seat native acceptance selected a chair-capable bed")
            log("PASS native zero-chair-position bed selected")
        end
        run.step,run.next,run.deadline=1.5,now+1000,now+120000
    elseif run.step==1.5 then
        assert(run.actor:getSayLine()==run.singleLine,"speech refresh changed the single-line text")
        run.capture="speech-single-line"
        log("PASS single-line speech retains exact text through native refresh")
        run.step,run.next=1.6,now+1000
    elseif run.step==1.6 then
        run.multiLine="The road is clear.\nI will stay here."
        assert(U.say(run.actor,run.multiLine),"multiline speech fixture was rejected")
        run.step,run.next=1.7,now+1000
    elseif run.step==1.7 then
        assert(run.actor:getSayLine()==run.multiLine,"speech refresh changed the multiline text")
        run.capture="speech-multi-line"
        log("PASS multiline speech retains only its authored line break through native refresh")
        SC.Dialogue.say=run.initialDialogueSay
        run.initialDialogueSay=nil
        run.step,run.next=2,now+1000
    elseif run.step==2 then
        local actor=run.actor
        local accepted,reason=SC.Downtime.update(actor,player,{snapshot={threatCount=0,immediateCount=0,
            pressure=0,threats={},player={danger=0},indoors=true}},"rest_bed")
        assert(not run.entryFailure,"bed entry was rejected: "..tostring(run.entryFailure))
        if run.sawEntry and reason=="cooldown" then
            local record=run.bedRecord or {}
            log("BED_FAILURE "..tostring(record.failure).." failed="..tostring(record.failed)
                .." cancelled="..tostring(record.cancelled).." moving="..tostring(actor:isMoving())
                .." getup="..tostring(actor:getVariableBoolean("forceGetUp"))
                .." alignment="..tostring(record.alignmentFailure)
                .." pos="..actor:getX()..","..actor:getY()
                .." pillow="..tostring(record.bedEntry and record.bedEntry.pillow and record.bedEntry.pillow.x)
                ..","..tostring(record.bedEntry and record.bedEntry.pillow and record.bedEntry.pillow.y))
            for _,entry in ipairs(SC.ActionSupervisor.history(actor,12)) do
                log("HISTORY "..tostring(entry.event)..":"..tostring(entry.reason).." phase="..tostring(entry.phase))
            end
            error("native bed entry was cancelled before sleeping")
        end
        local clips=actor:getCompanionActiveAnimationNames()
        if now>=(run.traceAt or 0) then
            log("TRACE "..tostring(accepted)..":"..tostring(reason).." onBed="..tostring(actor:isOnBed())
                .." asleep="..tostring(actor:isAsleep()).." anim="..actor:getVariableString("OnBedAnim").." clips="..clips)
            run.traceAt=now+5000
        end
        if actor:isAsleep() and actor:isOnBed() and actor:getVariableString("OnBedAnim")=="Asleep"
            and clips:find("Bob_Asleep",1,true) and not clips:find("ToAsleep",1,true)
            and not clips:find("GetInBed",1,true) and not clips:find("Bob_Awake",1,true) then
            assert(not actor:hasCompanionSpeech(),"the awake speech bubble survived sleep entry")
            assert(not U.say(actor,"This must stay silent."),"sleep speech was accepted")
            local spokenAt=SC.Dialogue.lastSpokenAt(actor)
            assert(not SC.Dialogue.say(actor,"sleep.probe",{"No talking in sleep."}),"sleep dialogue was accepted")
            assert(not SC.Dialogue.emitResolved(actor,"sleep.probe","No sleeping transcript.",
                {transcriptAccepted=true}),"sleep transcript was accepted")
            assert(SC.Dialogue.lastSpokenAt(actor)==spokenAt,"sleep suppression issued a speech receipt")
            assert(not actor:setCompanionSpeechDisplayMillis(30000),"sleep accepted a native speech lease")
            actor:addLineChatElement("Direct native speech must stay silent.")
            assert(not actor:hasCompanionSpeech(),"direct native speech bypassed sleep suppression")
            log("PASS sleep clears awake bubble and rejects Lua, resolved and direct native speech")
            assert(getNumActivePlayers()==1 and getSpecificPlayer(1)==nil,"sleep changed view ownership")
            log("PASS native lying sleep clip="..clips.." health="..actor:getBodyDamage():getHealth()
                .." pos="..actor:getX()..","..actor:getY().." direction="..actor:getVariableString("OnBedDirection"))
            run.capture="bed-sleep-lying"
            run.step,run.next=3,now+3000
        else
            assert(now<run.deadline,"native bed sleep did not settle: "..tostring(reason))
            run.next=now+250
        end
    elseif run.step==3 then
        assert(run.actor:isAsleep() and not run.actor:hasCompanionSpeech(),
            "native refresh revived speech during sleep")
        assert(SC.Downtime.wakeForAlarm(run.actor),"ordinary alarm wake failed")
        assert(not run.actor:isAsleep() and run.actor:getVariableString("OnBedAnim")=="Awake",
            "wake did not restore the awake bed animation")
        log("PASS ordinary wake restores Awake and clears native sleep")
        run.step,run.next,run.deadline=4,now+250,now+30000
    elseif run.step==4 then
        local actor=run.actor
        SC.NativeActions.leaveSeating(actor)
        if SC.NativeActions.seatingStatus(actor)=="standing" and not actor:isOnBed() then
            assert(actor:getSquare(),"wake lost native world membership")
            local okay,reason=SC.Actor.validateNative(actor)
            assert(okay,"wake invalidated actor: "..tostring(reason))
            local wakeLine=actor:getSayLine() or ""
            log("WAKE_SPEECH current="..wakeLine:gsub("\n"," / "))
            -- Ordinary ambient speech may start after waking while native
            -- get-up finishes. Reject replayed fixture lines, not fresh speech.
            assert(wakeLine~=run.singleLine and wakeLine~=run.multiLine
                and wakeLine~="This must stay silent."
                and wakeLine~="No talking in sleep."
                and wakeLine~="No sleeping transcript."
                and wakeLine~="Direct native speech must stay silent.",
                "waking replayed a suppressed sleeping line")
            assert(U.say(actor,"I am awake now.") and actor:hasCompanionSpeech(),
                "ordinary speech did not resume after getting up")
            log("PASS waking restores fresh speech without replaying suppressed lines")
            log("PASS native get-up completed at "..actor:getX()..","..actor:getY()
                .." health="..actor:getBodyDamage():getHealth())
            if run.zeroSeatingOnly then
                -- This mode targets bed discovery and native sleep/wake in
                -- cramped bunk rooms. Standard mode separately exercises the
                -- longer walk-away and speech/zoom matrix in a larger room.
                assert(run.recoveries==run.entryRecoveries,"sleep/wake used actor recovery")
                assert(actor:isCollidable() and actor:getBodyDamage():getHealth()>=run.entryHealth-0.01,
                    "zero-chair bed sleep/wake changed health or collision")
                log("PASS focused zero-chair-position sleep/wake complete; health retained and no recovery")
                log("PASS native bed sleep acceptance complete")
                run.step=99
                return
            end
            local room=actor:getSquare():getRoom()
            local best
            for dx=-5,5 do for dy=-5,5 do
                local square=getCell():getGridSquare(math.floor(actor:getX())+dx,math.floor(actor:getY())+dy,0)
                if square and square:getRoom()==room and U.isSafeSpawnSquare(square)
                    and U.distance(actor,square)>=2 and U.distance(actor,square)<=6
                    and U.distance(run.bed,square)>=2.25 then
                    for _,offset in ipairs({{0,-1},{-1,0}}) do
                        local observer=getCell():getGridSquare(square:getX()+offset[1],square:getY()+offset[2],0)
                        if observer and observer:getRoom()==room and U.isSafeSpawnSquare(observer) then
                            local score=U.distance(actor,square)
                            if not best or score<best.score then best={square=square,observer=observer,score=score} end
                        end
                    end
                end
            end end
            assert(best,"no clear in-room walk destination away from the mattress")
            run.walkTarget,run.walkObserver=best.square,best.observer
            run.walkStartX,run.walkStartY=actor:getX(),actor:getY()
            run.walkRecoveries=run.recoveries
            actor:getStats():set(CharacterStat.FATIGUE,0.1)
            actor:getStats():set(CharacterStat.HUNGER,0.1)
            actor:getStats():set(CharacterStat.THIRST,0.1)
            run.manualRest=false
            local moved,why=SC.Commands.issue(run.id,"move_to",{square=run.walkTarget},player)
            assert(moved,"ordinary walk-away order was rejected: "..tostring(why))
            log("WALK requested target="..run.walkTarget:getX()..","..run.walkTarget:getY())
            run.step,run.next,run.deadline=4.5,now+100,now+45000
        else assert(now<run.deadline,"native bed exit never completed") run.next=now+250 end
    elseif run.step==4.5 then
        local actor=run.actor
        assert(run.recoveries==run.walkRecoveries,"walk-away used recovery instead of walking")
        local travelled=math.sqrt((actor:getX()-run.walkStartX)^2+(actor:getY()-run.walkStartY)^2)
        if not run.walkCaptured and travelled>0.6 then
            run.capture,run.walkCaptured="bed-walking-away",true
            log("WALK progress distance="..travelled.." clips="..actor:getCompanionActiveAnimationNames())
        end
        if U.sameSquare(actor,run.walkTarget) and U.distance(actor,run.walkTarget)<0.8 then
            assert(travelled>=1.5 and run.walkCaptured,"walk-away made insufficient physical progress")
            assert(not actor:isOnBed() and actor:isCollidable()
                and SC.NativeActions.seatingStatus(actor)=="standing","walk-away retained a bed pose or collision problem")
            assert(SC.Commands.issue(run.id,"stay",nil,player),"stay after walking was rejected")
            run.zoomHold=true
            run.manualRest=true
            SC.Actor.stop(actor)
            assert(U.isSafeSpawnSquare(run.walkObserver),"nearby camera observer tile became blocked")
            player:teleportTo(run.walkObserver:getX()+0.5,run.walkObserver:getY()+0.5,0)
            log("PASS walked clear of bed distance="..travelled.." recoveries=0 health="..actor:getBodyDamage():getHealth())
            run.step,run.next=4.6,now+1000
        else assert(now<run.deadline,"companion could not walk away from the bed edge") run.next=now+100 end
    elseif run.step==4.6 then
        assert(U.say(run.actor,"I am awake now."),"speech after walking was rejected")
        run.capture="bed-sleep-awake"
        run.step,run.next=5,now+1500
    elseif run.step==5 then
        local core=getCore()
        SC.Downtime.cancel(run.actor,"zoom_capture_setup")
        SC.Actor.stop(run.actor)
        run.originalZoom,run.originalAutoZoom=core:getZoom(0),core:getAutoZoom(0)
        core:setAutoZoom(0,false)
        for _=1,24 do core:doZoomScroll(0,-1) end
        run.actor:getStats():set(CharacterStat.FATIGUE,0.1)
        run.actor:getStats():set(CharacterStat.HUNGER,0.1)
        run.actor:getStats():set(CharacterStat.THIRST,0.1)
        run.zoomCases={
            {key="short",text="I will watch the road."},
            {key="multiline",text="The road is clear.\nI will stay here."},
            {key="wrapped",text="I checked the road and the houses beyond the fence. There is enough room to bring the car home, but keep an eye on the bend by the trees."},
        }
        run.zoomLevels,run.zoomCase=0,1
        -- Keep this actor's ambient dialogue out of the controlled samples.
        -- Speech emission and refresh themselves remain the production paths.
        run.originalDialogueSay=SC.Dialogue.say
        SC.Dialogue.say=function(actor,...)
            if actor==run.actor then return false,"zoom_capture_fixture" end
            return run.originalDialogueSay(actor,...)
        end
        run.step,run.next,run.zoomDeadline=6,now+1000,now+10000
    elseif run.step==6 then
        local zoom=getCore():getZoom(0)
        if not run.lastZoom or math.abs(zoom-run.lastZoom)>0.001 then run.zoomStableAt=now end
        run.lastZoom=zoom
        assert(now<run.zoomDeadline,"camera zoom did not settle")
        if now-(run.zoomStableAt or now)<300 then run.next=now+100 return end
        if run.zoomCase==1 then
            run.zoomLevels=run.zoomLevels+1
            assert(run.zoomLevels<=16,"unexpected unbounded zoom levels")
            run.zoomPercent=math.floor(zoom*100+0.5)
        end
        assert(run.actor:clearCompanionSpeech(),"zoom sample could not clear prior dialogue")
        run.zoomText=run.zoomCases[run.zoomCase].text
        assert(U.say(run.actor,run.zoomText),"zoom speech sample was rejected")
        run.step,run.next=7,now+500
    elseif run.step==7 then
        assert(run.actor:getSayLine()==run.zoomText,"zoom sample text changed during refresh")
        local key=run.zoomCases[run.zoomCase].key
        run.capture=string.format("speech-zoom-%03d-%s",run.zoomPercent,key)
        log("PASS zoom="..run.zoomPercent.." case="..key.." native-text-exact=true")
        if run.zoomCase<#run.zoomCases then
            run.zoomCase=run.zoomCase+1
            run.step,run.next=6,now+300
        else
            local core=getCore()
            local nextZoom=core:getNextZoom(0,1)
            if nextZoom>core:getZoom(0)+0.001 then
                core:doZoomScroll(0,1)
                run.zoomCase,run.lastZoom,run.zoomStableAt=1,nil,nil
                run.step,run.next,run.zoomDeadline=6,now+300,now+10000
            else
                run.step,run.next=8,now+1000
            end
        end
    elseif run.step==8 then
        local core=getCore()
        for _=1,24 do
            if core:getNextZoom(0,-1)<run.originalZoom-0.001 then break end
            core:doZoomScroll(0,-1)
        end
        core:setAutoZoom(0,run.originalAutoZoom)
        SC.Dialogue.say=run.originalDialogueSay
        run.zoomHold=false
        SC.Decision.update=run.originalDecision
        run.manualRest=false
        log("PASS zoom speech capture complete levels="..run.zoomLevels.." samples="..(run.zoomLevels*#run.zoomCases))
        log("PASS native bed sleep acceptance complete")
        run.step=99
    end
end
local function guarded()
    local okay,reason=pcall(tick)
    if not okay then log("FAIL "..tostring(reason)) Events.OnTick.Remove(guarded) end
end
Events.OnTick.Add(guarded)
Events.OnPostUIDraw.Add(function()
    if run.capture then getCore():TakeFullScreenshot(run.capture) run.capture=nil end
end)
