-- SPDX-License-Identifier: MIT
-- Started from user_comfort_harness: drives the production Banter/Tales APIs,
-- retaining their budgets. Game time advances 24 times faster than wall time.
local SC=SurvivorCompanion
local T,U=SC.TestFixture,SC.GameplayUtil
local days=SC_VOICE_SOAK_DAYS or 60
local clock,gameHours,paused=0,24,false
function getTimestampMs() return clock end
function isGamePaused() return paused end
function getGameTime() return {
    getWorldAgeHours=function() return gameHours end,
    getHour=function() return math.floor(gameHours%24) end,
    getTimeOfDay=function() return gameHours%24 end,
    getDay=function() return math.floor(gameHours/24) end,
    getMonth=function() return 6 end,getYear=function() return 1993 end} end
local random=19430706
function ZombRand(n) random=(random*1664525+1013904223)%4294967296 return math.floor(random%math.max(1,n)) end
local player=T.player
local records,commands={},{}
for n,name in ipairs({"June","Sam","Nick"}) do
    local actor=T.actor("sc-soak-"..n,n+1,1,{recruited=true})
    actor.name=name
    function actor:getForename() return self.name end
    function actor:getDescriptor() return {
        getForename=function() return self.name end,getSurname=function() return "" end} end
    function actor:isAsleep() return false end
    local state=SC.Commands.peek(actor)
    state.recruited=true state.order="hold" state.behavior="idle"
    state.personality=n==1 and "caring" or n==2 and "cautious" or "brave"
    commands[actor]=state
    records[#records+1]={id=U.idOf(actor),actor=actor,recruited=true,identity={forename=name,surname=""},
        runtime={senses={current={threatCount=0,immediateCount=0,pressure=0}}}}
    T.registry[U.idOf(actor)]=records[#records]
end
local fallen=T.actor("sc-soak-fallen",3,2,{recruited=true}) fallen.name="Wade"
function fallen:getDescriptor() return {getForename=function() return "Wade" end,getSurname=function() return "" end} end
T.registry[U.idOf(fallen)]={id=U.idOf(fallen),actor=fallen,recruited=true}
SC.Registry.records=function() return records end
-- A known camp boundary and a harmless reading action replace native world
-- discovery. They never replace the dialogue chooser or the scene scheduler.
SC.BaseLife.isInside=function() return true end
local nativeToken=SC.ActionSupervisor.current
SC.ActionSupervisor.current=function(actor)
    if commands[actor] then return {owner="downtime",action="read"} end
    return nativeToken(actor)
end
SC.UserOptions={get=function(key) if key=="chatter" then return "normal" end end}
SC.Community.reset() SC.LifeEvents.reset() SC.Banter.reset() SC.Tales.reset() SC.Dialogue.reset()
local lines,sceneRows,eventRows,reasonCounts={},{},{},{}
local lastLines,repeatCount,minRepeat={},0,math.huge
local total,recalls,falseClaims,hash=0,0,0,5381
local aftermathEvents,tagErrors={},0
local teaseInGrief,lightAboutDead=0,0
local deathAt
local topicCounts={}
local function mix(text)
    for n=1,#text do hash=(hash*33+text:byte(n))%2147483647 end
end
local originalEmit=SC.Dialogue.emitResolved
local tickLines={}
SC.Dialogue.emitResolved=function(actor,topic,line,options)
    local spoken,result,receipt=originalEmit(actor,topic,line,options)
    if not spoken then return spoken,result,receipt end
    local id=U.idOf(actor) total=total+1
    local day=math.floor(gameHours/24)
    local key=id..":"..line
    local prior=lastLines[key]
    if prior then
        local gap=(gameHours-prior)/24 minRepeat=math.min(minRepeat,gap)
        if gap<3 and SC.Dialogue.poolSize(topic,actor,commands[actor])>=8 then repeatCount=repeatCount+1 end
    end
    lastLines[key]=gameHours
    topicCounts[topic]=(topicCounts[topic] or 0)+1
    local recall=topic:find("^recall%.")~=nil or options and options.recall==true
    if recall then
        recalls=recalls+1
        -- New recall implementations pass an explicit evidence receipt.
        local proof=options and options.evidence
        if not proof or proof.known~=true or not proof.eventId then falseClaims=falseClaims+1 end
    end
    local row={id=id,topic=topic,line=line,day=day,hour=gameHours%24,options=options}
    if options and options.sceneId then
        local scene=sceneRows[options.sceneId] or {beats=0,speakers={},kind=options.sceneKind}
        scene.beats=scene.beats+1 scene.speakers[id]=true
        if scene.lastTag and options.accepts and not options.accepts[scene.lastTag] then tagErrors=tagErrors+1 end
        scene.lastTag=options.tag
        sceneRows[options.sceneId]=scene
        if options.sceneKind=="aftermath" and options.eventId then aftermathEvents[options.eventId]=true end
    end
    if deathAt then
        local age=(gameHours-deathAt)/24
        if age<3 and options and options.tag=="tease" then teaseInGrief=teaseInGrief+1 end
        if age<7 and options and options.aboutDead and options.tone=="light" then lightAboutDead=lightAboutDead+1 end
    end
    tickLines[#tickLines+1]=row
    if day>=18 and day<25 then lines[#lines+1]=row end
    mix(id.."|"..topic.."|"..line.."\n")
    return spoken,result,receipt
end
local function observed(kind,day)
    local fields={day=day,hour=gameHours%24,place="the firehouse",
        participants={"sc-soak-1","sc-soak-2"},witnesses={"sc-soak-3"},
        sourceId="sc-soak-1",sourceName="June",targetId="sc-soak-2",targetName="Sam",
        count=3,kills=3,weapon="a hammer",outcome="all home",witnessNames="Nick"}
    if kind=="companion_death" then
        fields.sourceId,fields.targetId=fallen.id,fallen.id
        fields.sourceName,fields.targetName="Wade","Wade"
        fields.participants={fallen.id}
        fields.witnesses={"sc-soak-1","sc-soak-2","sc-soak-3"}
        fields.outcome="died" fields.count=nil fields.kills=nil fields.weapon=nil
    end
    local row=SC.LifeEvents.emit(kind,fields)
    eventRows[#eventRows+1]=row
end
local lastDay,reloads=-1,0
local totalTicks=math.floor(days*24*3600000/24/5000)
for step=1,totalTicks do
    clock=step*5000 SC_TEST_CLOCK=clock
    gameHours=24+clock*24/3600000
    local day=math.floor(gameHours/24)
    if day~=lastDay then
        lastDay=day
        if day%5==0 then observed("shared_escape",day) SC.Tales.noteCloseCall(records[1].actor,"grabbed",clock) end
        if day%7==0 then observed("supply_run_completed",day) end
        if day%11==0 then observed("alarm_fought_off",day) end
        if day==20 then
            deathAt=gameHours
            fallen.dead=true
            observed("companion_death",day)
            SC.Community.noteCompanionDeath({id=fallen.id,actor=fallen,name="Wade",recruited=true})
        end
        if day%7==0 then
            local saved=SC.Community.export()
            assert(SC.Community.restore(saved),"soak save/restore failed")
            SC.Dialogue.reset() reloads=reloads+1
        end
    end
    SC.Community.processEvents(32)
    -- A brief fight every fifth evening blocks optional speech through the
    -- same threat snapshot used by real Banter.exchangeParticipantReady.
    local danger=day%5==0 and gameHours%24>=17 and gameHours%24<17.25
    for _,record in ipairs(records) do
        record.runtime.senses.current.threatCount=danger and 3 or 0
        record.runtime.senses.current.immediateCount=danger and 1 or 0
        record.runtime.senses.current.pressure=danger and 1 or 0
    end
    tickLines={}
    local before=SC.Banter._partyForTests().exchange
    local ok,reason=SC.Banter.update(player,records,clock)
    reasonCounts[tostring(reason)]=(reasonCounts[tostring(reason)] or 0)+1
    local exchange=SC.Banter._partyForTests().exchange or before
    if exchange and exchange.id then
        local scene=sceneRows[exchange.id] or {beats=0,speakers={},kind=exchange.kind}
        for _,row in ipairs(tickLines) do if not (row.options and row.options.sceneId) then scene.beats=scene.beats+1 scene.speakers[row.id]=true end end
        sceneRows[exchange.id]=scene
    end
end
SC.Dialogue.emitResolved=originalEmit
local scenes,twoBeat,threeBeat,oneSpeaker=0,0,0,0
for _,scene in pairs(sceneRows) do
    if scene.beats>0 then scenes=scenes+1 end
    if scene.beats==2 then twoBeat=twoBeat+1 end
    if scene.beats>=3 then threeBeat=threeBeat+1 end
    local speakers=0 for _ in pairs(scene.speakers) do speakers=speakers+1 end
    if scene.beats>0 and speakers<2 then oneSpeaker=oneSpeaker+1 end
end
local aftermath=0 for _ in pairs(aftermathEvents) do aftermath=aftermath+1 end
local report={"VOICE_SOAK_METRIC days="..days.." ticks="..totalTicks.." game_to_real=24 reloads="..reloads,
    "VOICE_SOAK_METRIC lines="..total.." specific_recall="..recalls.." false_claims="..falseClaims,
    "VOICE_SOAK_METRIC repeat_under_3_days="..repeatCount.." min_repeat_days="..tostring(minRepeat),
    "VOICE_SOAK_METRIC scenes="..scenes.." two_beat="..twoBeat.." three_plus="..threeBeat,
    "VOICE_SOAK_METRIC scripted_events="..#eventRows.." aftermath="..aftermath,
    "VOICE_SOAK_METRIC one_speaker_scenes="..oneSpeaker.." tag_errors="..tagErrors.." tagged_tease_in_grief="..teaseInGrief.." light_about_dead_before_7="..lightAboutDead,
    "VOICE_SOAK_HASH "..hash,"VOICE_TRANSCRIPT_BEGIN"}
for _,row in ipairs(lines) do
    report[#report+1]=string.format("Day %02d %02d:%02d | %s | %s | %s",row.day,
        math.floor(row.hour),math.floor(row.hour%1*60),row.id,row.topic,row.line)
end
report[#report+1]="VOICE_TRANSCRIPT_END"
local reasons={} for reason,n in pairs(reasonCounts) do reasons[#reasons+1]=reason.."="..n end table.sort(reasons)
report[#report+1]="VOICE_SOAK_REASONS "..table.concat(reasons,",")
SC_TEST_REPORT=table.concat(report,"\n")
assert(total>0,"soak produced no speech; "..table.concat(reasons,","))
assert(falseClaims==0,"recall made unsupported claims")
if SC_VOICE_SOAK_STRICT then
    assert(total>0 and recalls/total>=.125 and recalls/total<=1/3,"specific recall share outside its gate")
    assert(repeatCount==0,"exact line repeated within three game days")
    assert(threeBeat>0 and twoBeat==0,"group scenes need three or more beats")
    assert(oneSpeaker==0 and tagErrors==0,"scene speakers or branch tags failed")
    assert(teaseInGrief==0 and lightAboutDead==0,"grief tone window failed")
end
