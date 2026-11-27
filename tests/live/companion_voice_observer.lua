-- SPDX-License-Identifier: MIT
-- Copy into a disposable source payload only. Read-only native observation;
-- no actor positioning, commands, zombie flags, event injection or time edits.
local installed,nextSample,started=false,0,nil
local lines,scenes,completed,claims=0,{},0,0
local observedScene
local loggedInterruptions=setmetatable({}, {__mode="k"})
local transcript="LivingFellowsHarness/voice-transcript.txt"
local diagnostics="LivingFellowsHarness/voice-diagnostics.txt"
local function write(path,line)
    local writer=getFileWriter(path,true,true)
    if writer then writer:write(tostring(line):gsub("[\r\n]"," ").."\n") writer:close() end
end
local function stamp(SC)
    local hours=SC.LifeEvents.now()/3600000
    return string.format("Day %d %02d:%02d",math.floor(hours/24),math.floor(hours%24),math.floor(hours%1*60))
end
local function install()
    local SC=LivingFellows
    if installed or not SC or not SC.Dialogue or not SC.Scenes or not SC.GameplayUtil
        or not getPlayer() then return end
    installed=true started=SC.GameplayUtil.nowMs()
    write(transcript,"Native cloned-camp observation; Living Fellows "..tostring(SC.Identity.release))
    write(transcript,"Every line below was accepted by the real overhead speech adapter.")
    local original=SC.Dialogue.emitResolved
    SC.Dialogue.emitResolved=function(actor,topic,line,options)
        local spoken,result,receipt=original(actor,topic,line,options)
        if spoken and SC.GameplayUtil.isCompanion(actor)
            and (topic:find("^scene%.") or topic:find("^recall%.") or topic:find("^banter%.") or topic:find("^background%.")) then
            lines=lines+1
            local name=SC.GameplayUtil.nameOf(actor)
            write(transcript,stamp(SC).." | "..name.." | "..topic.." | "..line)
            local proof=options and options.evidence
            if options and options.recall then
                local event=proof and proof.eventId and SC.Community.historyRow(proof.eventId)
                if not event or not SC.Community.knowsEvent(actor,event) then claims=claims+1 end
            end
            if options and options.sceneId then
                local scene=scenes[options.sceneId] or {beats=0,speakers={}}
                scene.beats=scene.beats+1 scene.speakers[SC.GameplayUtil.idOf(actor)]=true
                scenes[options.sceneId]=scene
                if options.sceneBeat==options.sceneBeats then
                    completed=completed+1
                    local speakers=0 for _ in pairs(scene.speakers) do speakers=speakers+1 end
                    write(diagnostics,"SCENE completed="..completed.." beats="..scene.beats.." speakers="..speakers
                        .." kind="..tostring(options.sceneKind).." active_ms="..tostring(options.sceneActive))
                    if completed<=3 then pcall(function() getCore():TakeFullScreenshot("LF-02721-voice-scene-"..completed) end) end
                end
            end
        end
        return spoken,result,receipt
    end
end
local function sample()
    install()
    if not installed then return end
    local SC=LivingFellows
    local now=SC.GameplayUtil.nowMs()
    local scene=SC.Banter._partyForTests().exchange
    if scene and scene.generalized then observedScene=scene end
    if observedScene and observedScene.status=="interrupted" and not loggedInterruptions[observedScene] then
        loggedInterruptions[observedScene]=true
        write(diagnostics,"SCENE interrupted at="..stamp(SC).." step="..tostring(observedScene.step)
            .." reason="..tostring(observedScene.abortReason))
    end
    if now<nextSample then return end
    nextSample=now+15000
    local base=SC.BaseLife.active()
    write(diagnostics,"SAMPLE "..stamp(SC).." elapsed_ms="..(now-started).." lines="..lines.." completed_scenes="..completed
        .." unsupported_claims="..claims.." camp="..tostring(base and base.name or "none")
        .." speed="..tostring(type(getGameSpeed)=="function" and getGameSpeed() or "unknown"))
    local player=getPlayer()
    for _,record in ipairs(SC.Registry.records()) do
        local actor=record.actor
        if actor and not SC.GameplayUtil.isDead(actor) and SC.GameplayUtil.distance(actor,player)<=24 then
            local state=SC.Commands.peek(actor)
            local token=SC.ActionSupervisor.current(actor)
            local snapshot=record.runtime and record.runtime.senses and record.runtime.senses.current or {}
            write(diagnostics,"ACTOR "..SC.GameplayUtil.nameOf(actor).." gap="..string.format("%.1f",SC.GameplayUtil.distance(actor,player))
                .." order="..tostring(state.order).." token="..tostring(token and token.owner)..":"..tostring(token and token.action)
                .." threats="..tostring(snapshot.threatCount).." in_camp="..tostring(SC.BaseLife.isInside(actor))
                .." moving="..tostring(select(1,SC.GameplayUtil.call(actor,"isMoving"))))
        end
    end
end
Events.OnGameStart.Add(install)
Events.OnTick.Add(sample)
