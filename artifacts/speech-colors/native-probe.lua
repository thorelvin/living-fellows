-- SPDX-License-Identifier: MIT
-- Only injected into the disposable camp clone. Production speech/render/save
-- paths; staged people/clock/camera keep the visual comparisons repeatable.
local run = { step = 0, next = 0, actors = {}, index = 1 }
local function log(text)
    print("SPEECH_COLOURS|" .. text)
    local writer = getFileWriter("SurvivorCompanionHarness/speech-colors.log", true, true)
    if writer then writer:write(text .. "\n") writer:close() end
end
local function clear()
    for _, actor in ipairs(run.actors) do assert(actor:clearCompanionSpeech()) end
end
local function tick()
    local now, SC, player = getTimestampMs(), SurvivorCompanion, getSpecificPlayer(0)
    if now < run.next or not SC or not SC.State.active or not player or not player:getSquare() then return end
    local U, core = SC.GameplayUtil, getCore()
    if run.step == 0 then
        run.actors = {}
        for _, actor in ipairs(SC.Registry.living()) do run.actors[#run.actors+1] = actor end
        if #run.actors < 4 then run.next = now + 500 return end
        run.oldDecision, run.oldDialogue = SC.Decision.update, SC.Dialogue.say
        SC.Decision.update = function() return true, "speech_colour_fixture" end
        SC.Dialogue.say = function() return false, "speech_colour_fixture" end
        for _, actor in ipairs(run.actors) do
            local id = SC.Registry.idOf(actor)
            SC.Downtime.cancel(actor, "speech_colour_fixture")
            SC.Decision.cancelWork(actor, "speech_colour_fixture")
            SC.Encounter.cancelScavenge(actor, "speech_colour_fixture")
            SC.ActionSupervisor.cancel(actor, "speech_colour_fixture", nil, true)
            SC.BaseLife.setDuty(id, false)
            actor:setAsleep(false)
            actor:getStats():set(CharacterStat.FATIGUE, .1)
        end
        SC.UI.close()
        local info, mini = getPlayerInfoPanel(0), getPlayerMiniMap(0)
        if info then info:setVisible(false) end
        if mini then mini:setVisible(false) end
        player:setGodMod(true) player:setGhostMode(true)
        getGameTime():setTimeOfDay(12)
        run.places = {}
        -- Clear lawn near the saved camp. All fixture recovery is setup only.
        for radius = 3, 24 do
            if #run.places >= 17 then break end
            for dx = -radius, radius, 3 do
                local sq = getCell():getGridSquare(math.floor(player:getX()) + dx,
                    math.floor(player:getY()) - radius, 0)
                if sq and not sq:getRoom() and U.isSafeSpawnSquare(sq) then
                    run.places[#run.places + 1] = sq
                end
            end
        end
        assert(#run.places >= 17, "no bounded clear lawn fixture")
        run.observer = run.places[1]
        player:teleportTo(run.observer:getX() + .5, run.observer:getY() + .5, 0)
        for i, actor in ipairs(run.actors) do
            assert(SC.Actor.recover(actor, run.places[i + 1]), "fixture placement rejected")
            SC.Actor.stop(actor)
        end
        run.oldMove = SC.Actor.setMovement
        SC.Actor.setMovement = function(actor) return SC.Actor.stop(actor) end
        run.originalGet = SC.UserOptions.get
        run.mode = "speaker"
        SC.UserOptions.get = function(key)
            if key == "speechColors" then return run.mode end
            return run.originalGet(key)
        end
        run.step, run.next = 1, now + 500
        log("FIXTURE font-option=" .. core:getOptionFontSize() .. " small-height="
            .. getTextManager():getFontHeight(UIFont.Small) .. " existing=" .. #run.actors)
    elseif run.step == 1 then
        if #run.actors < 16 then
            if not run.ticket then
                local i = #run.actors + 1
                local ticket, reason = SC.Actor.beginSpawn(run.places[i + 1], {
                    id = "sc-speech-fixture-" .. i, recruited = true,
                    identity = { forename = "Speaker", surname = tostring(i), gender = "female" },
                })
                assert(ticket, "fixture spawn: " .. tostring(reason))
                run.ticket = ticket
            end
            local actor, reason = SC.Actor.pollSpawn(run.ticket)
            if actor then
                run.actors[#run.actors + 1] = actor
                actor:setGodMod(true)
                run.ticket = nil
            else assert(reason == "spawn_pending", "fixture poll: " .. tostring(reason)) end
            run.next = now + 100 return
        end
        for _, actor in ipairs(run.actors) do
            local record = SC.Registry.byId(SC.Registry.idOf(actor))
            local captured, reason = SC.Persistence.captureRecord(record)
            assert(captured and captured.speechColorKey == record.speechColorKey,
                "native person capture lost its colour: " .. tostring(reason))
            log("PERSON " .. record.id .. " " .. U.nameOf(actor) .. " " .. record.speechColorKey)
        end
        for _, count in ipairs({1, 4, 16}) do
            for _, mode in ipairs({"white", "speaker"}) do
                run.mode = mode
                local started = getTimestampMs()
                for _ = 1, 2000 do for i = 1, count do
                    SC.SpeechColors.forRecord(SC.Registry.byId(SC.Registry.idOf(run.actors[i])))
                end end
                log("PERF actors=" .. count .. " mode=" .. mode .. " lookups=" .. count * 2000
                    .. " ms=" .. (getTimestampMs() - started))
            end
        end
        run.mode = "speaker"
        clear()
        run.retainedWords = "I checked the road and both houses. We have a clear way home, with room for the car."
        assert(U.say(run.actors[1], run.retainedWords))
        -- ChatElement computes its visibility flags on the following update.
        run.step, run.next = 1.5, now + 600
    elseif run.step == 1.5 then
        run.capture = "colour-retained-early"
        run.step, run.next = 2, now + 8500
    elseif run.step == 2 then
        assert(run.actors[1]:getSayLine() == run.retainedWords,
            "native refresh lost the retained line")
        run.capture = "colour-retained-late"
        log("PASS native colour reading interval >8 seconds text-exact=true")
        run.step, run.next = 2.1, now + 300
    elseif run.step == 2.1 then
        run.actors[1]:setAsleep(true)
        assert(not U.say(run.actors[1], "Sleep must remain silent"))
        assert(not run.actors[1]:emitCompanionSpeech("Native sleep", 1, .8, .8, 8000))
        run.actors[1]:setAsleep(false)
        run.originalZoom, run.originalAutoZoom = core:getZoom(0), core:getAutoZoom(0)
        core:setAutoZoom(0, false)
        for _ = 1, 24 do core:doZoomScroll(0, -1) end
        run.cases = {
            {key="short", text="I will watch the road."},
            {key="multiline", text="The road is clear.\nI will stay here."},
            {key="wrapped", text="I checked the road and the houses beyond the fence. There is enough room to bring the car home, but keep an eye on the bend by the trees."},
        }
        run.case, run.step, run.next = 1, 3, now + 1400
    elseif run.step == 3 then
        clear()
        run.words = run.cases[run.case].text
        assert(U.say(run.actors[1], run.words))
        run.step, run.next = 4, now + 600
    elseif run.step == 4 then
        assert(run.actors[1]:getSayLine() == run.words, "zoom refresh changed words")
        local zoom, kind = math.floor(core:getZoom(0)*100 + .5), run.cases[run.case].key
        run.capture = string.format("colour-zoom-%03d-%s", zoom, kind)
        log("PASS zoom=" .. zoom .. " case=" .. kind)
        if run.case < #run.cases then
            run.case, run.step, run.next = run.case + 1, 3, now + 100
        elseif core:getNextZoom(0,1) > core:getZoom(0) + .001 then
            core:doZoomScroll(0,1)
            run.case, run.step, run.next = 1, 3, now + 1400
        else
            for _=1,24 do
                if core:getNextZoom(0,-1) < 1-.001 then break end
                core:doZoomScroll(0,-1)
            end
            run.step, run.next = 5, now + 1400
        end
    elseif run.step == 5 then
        clear()
        -- A separate open lawn keeps the four colour samples unmuffled and
        -- inside the viewport. Native recovery validates every staged position;
        -- this is fixture setup, not a gameplay travel/teleport assertion.
        local offsets = {{-2,-2},{2,-2},{-2,2},{2,2}}
        local selected
        for dx=-20,-4,4 do for dy=-20,-4,4 do
            if not selected then
                local x,y=run.observer:getX()+dx,run.observer:getY()+dy
                local centre=getCell():getGridSquare(x,y,0)
                local targets,okay={},centre and not centre:getRoom() and U.isSafeSpawnSquare(centre)
                for i,offset in ipairs(offsets) do
                    local sq=getCell():getGridSquare(x+offset[1],y+offset[2],0)
                    targets[i]=sq
                    if not sq or sq:getRoom() or not U.isSafeSpawnSquare(sq) then okay=false end
                end
                if okay then
                    for i=1,4 do
                        if SC.Actor.recover(run.actors[i],targets[i])~=true then okay=false end
                    end
                    if okay then selected=centre end
                end
            end
        end end
        assert(selected,"no native-validated open four-speaker lawn")
        player:teleportTo(selected:getX()+.5,selected:getY()+.5,0)
        run.step,run.next=5.1,now+1600
    elseif run.step == 5.1 then
        clear()
        for i=1,4 do assert(U.say(run.actors[i], "I am ready when you are.")) end
        run.step, run.next = 5.5, now + 600
    elseif run.step == 5.5 then
        run.capture, run.step, run.next = "colour-four-speakers", 6, now + 1000
    elseif run.step == 6 then
        clear()
        run.mode = "white"
        assert(U.say(run.actors[1], "White text option. Same person, same saved colour."))
        run.step, run.next = 6.5, now + 600
    elseif run.step == 6.5 then
        run.capture, run.step, run.next = "colour-white-option", 7, now + 1200
    elseif run.step == 7 then
        clear() run.mode = "speaker"
        getGameTime():setTimeOfDay(0)
        run.step, run.next = 8, now + 1500
    elseif run.step == 8 then
        assert(U.say(run.actors[1], "I will keep watch until morning."))
        run.step, run.next = 8.5, now + 600
    elseif run.step == 8.5 then
        run.capture, run.step, run.next = "colour-night", 9, now + 1500
    elseif run.step == 9 then
        clear() getGameTime():setTimeOfDay(12)
        if not SC_SPEECH_TEST_VIEW then
            log("LIMIT secondary transition skipped; see separate Lighting64 crash evidence")
            run.step, run.next = 13, now+1000 return
        end
        -- Nearby secondary view exercises native per-viewport rows. No travel.
        run.viewActor = run.actors[1]
        local accepted, reason = SC.ViewSession.claim("base_watch",run.viewActor)
        assert(accepted,"secondary claim: " .. tostring(reason))
        run.step, run.next, run.deadline = 10, now+1500, now+30000
    elseif run.step == 10 then
        if getSpecificPlayer(1) ~= run.viewActor then
            assert(now<run.deadline,"secondary view did not join") run.next=now+250 return
        end
        clear()
        assert(U.say(run.viewActor,"Both views should hear the same person."))
        run.step, run.next = 10.5, now + 600
    elseif run.step == 10.5 then
        run.capture, run.step, run.next = "colour-secondary-view", 11, now+2000
    elseif run.step == 11 then
        assert(SCSplitScreenProbe.releaseJoinedLeader())
        assert(SC.ViewSession.released("base_watch",SC.ViewSession.slotSqlId(),false))
        run.step, run.next = 12, now+2500
    elseif run.step == 12 then
        assert(getSpecificPlayer(1)==nil,"secondary view remained active")
        clear()
        assert(U.say(run.viewActor,"Back together. I will keep the same colour."))
        run.step, run.next = 12.5, now + 600
    elseif run.step == 12.5 then
        run.capture, run.step, run.next = "colour-solo-return", 13, now+1500
        log("PASS secondary view and solo return retained actor identity")
    elseif run.step == 13 then
        -- Existing bright interior floor, separately from the outdoor samples.
        local sq=getCell():getGridSquare(12025,6742,0)
        local observer
        if sq then for dx=-1,1 do for dy=-1,1 do
            local candidate=getCell():getGridSquare(sq:getX()+dx,sq:getY()+dy,0)
            if not observer and (dx~=0 or dy~=0) and candidate
                and candidate:getRoom()==sq:getRoom() and U.isSafeSpawnSquare(candidate) then observer=candidate end
        end end end
        assert(sq and observer and U.isSafeSpawnSquare(sq),"interior fixture unavailable")
        assert(SC.Actor.recover(run.actors[1],sq))
        player:teleportTo(observer:getX()+.5,observer:getY()+.5,0)
        run.step,run.next=14,now+1400
    elseif run.step == 14 then
        clear() assert(U.say(run.actors[1],"The kitchen is quiet. I checked the door."))
        run.step,run.next=14.5,now+600
    elseif run.step == 14.5 then
        run.capture,run.step,run.next="colour-bright-floor",15,now+1000
    elseif run.step == 15 then
        SC.Decision.update, SC.Dialogue.say, SC.Actor.setMovement = run.oldDecision, run.oldDialogue, run.oldMove
        SC.UserOptions.get = run.originalGet
        log("PASS native speech colour acceptance complete")
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
