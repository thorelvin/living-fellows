-- SPDX-License-Identifier: MIT
-- Evidence adapter for spoken memories. It reads the bounded Community ledger
-- and explicit on-screen told-by receipts, never hidden health or world lists.
LivingFellows=LivingFellows or {}
local SC=LivingFellows
local R={} SC.Recall=R
local cached,cacheUntil={},-math.huge
local places={}
local function U() return SC.GameplayUtil end
local function now() return SC.LifeEvents.now() end
local function id(actor) return U().idOf(actor) end
local function valid(value) return SC.DiaryText.validToken(value) end
local family={shared_escape="close_call",companion_close_call="close_call",combat_encounter="fight",
    rescued_player="player_close_call",player_rescued="player_close_call",player_close_call="player_close_call",
    companion_died="death",companion_death="death",expedition_homecoming="homecoming",
    supply_run_completed="homecoming",alarm_fought_off="alarm",first_camp_night="camp_night",
    first_meeting="meeting",recruited="recruitment",burial="burial",survival_milestone="milestone",companion_bitten="observed_bite"}
local landmarks={death=true,camp_night=true,meeting=true,player_close_call=true}
function R.when(row)
    local age=math.max(0,math.floor(now()/86400000)-math.floor((tonumber(row.at) or 0)/86400000))
    if age==0 then return "earlier today" end
    if age==1 then return "yesterday" end
    if age<7 then return "a few days back" end
    if age<14 then return "last week" end
    local month=select(1,U().call(type(getGameTime)=="function" and getGameTime() or nil,"getMonth"))
    if row.month and row.month>=5 and row.month<=7 and month and month>=8 then return "back when it was still summer" end
    if (tonumber(row.day) or math.huge)<7 then return "early on" end
    if age<35 then return "a few weeks back" end
    return "a while back"
end
local function summary(row,kind,tokens)
    if kind=="death" then return "the loss of "..tostring(tokens.name or "a companion") end
    if kind=="observed_bite" then return "the bite involving "..tostring(tokens.name or "a companion") end
    if kind=="homecoming" then return "the expedition's return" end
    if kind=="meeting" then return "that first meeting" end
    if kind=="recruitment" then return "joining the group" end
    if kind=="camp_night" then return "the first camp night" end
    if kind=="burial" then return "the burial" end
    if kind=="milestone" then return tokens.count and "day "..tostring(tokens.count) or "the milestone" end
    if kind=="alarm" then return "the alarm" end
    if kind=="fight" then return "the fight"..(valid(tokens.place) and " at "..tokens.place or "") end
    return "the close call"..(valid(tokens.place) and " at "..tokens.place or "")
end
function R.context(actor,row,player)
    local known,heardFrom,heardName,heardFacts=SC.Community.knowsEvent(actor,row)
    local kind=family[row.kind]
    if not known or not kind or row.factsQuarantined then return nil end
    local evidence={known=true,direct=not heardFrom,heard=heardFrom~=nil}
    evidence[kind]=true
    local tokens={place=row.place,when=R.when(row),name=row.targetName or row.subjectName or row.sourceName}
    tokens.who=row.sourceId==id(actor) and "I" or row.sourceName
    evidence.has_source=valid(row.sourceName)
    for _,participant in ipairs(row.participants or {}) do if participant==row.sourceId then evidence.source_present=true end end
    if kind=="fight" then
        tokens.name=row.sourceName
        tokens.who=row.sourceId==id(actor) and "I" or row.sourceName
        tokens.by=row.sourceId==id(actor) and "me" or row.sourceName
    end
    if kind=="meeting" then tokens.name=row.targetId==id(actor) and row.sourceName or row.targetName end
    if kind=="observed_bite" then tokens.name=row.sourceName or row.targetName end
    if kind=="recruitment" and row.sourceId~=id(actor) then evidence.recruitment=false end
    tokens.count=kind=="fight" and row.kills or row.count
    tokens.weapon=row.weapon
    local leader=type(getSpecificPlayer)=="function" and getSpecificPlayer(0)
        or type(getPlayer)=="function" and getPlayer() or nil
    tokens.you=player and "you" or leader and U().nameOf(leader) or "the person we're following"
    evidence.covered=row.outcome=="freed_with_cover"
    if kind=="player_close_call" then
        evidence.player_close_call=(row.wasGrabbed==true or row.wasDowned==true)
            and (row.outcome=="freed_with_cover" or row.outcome=="player_got_free")
    end
    evidence.all_clear=row.outcome=="all_clear"
    evidence.verified_haul=row.kind=="expedition_homecoming"
        and (row.outcome=="crew_returned" or row.outcome=="returned_with_losses") and type(row.count)=="number"
    local summaryFacts=""
    if heardFrom then
        local mask=heardFacts or ""
        local fields={name="n",place="p",when="t",count="c",weapon="w",you="y"}
        for field,key in pairs(fields) do if not mask:find(key,1,true) then tokens[field]=nil end end
        if tokens.name and (kind=="death" or kind=="observed_bite") then summaryFacts=summaryFacts.."n" end
        if tokens.place and (kind=="fight" or kind=="close_call" or kind=="player_close_call") then summaryFacts=summaryFacts.."p" end
        if tokens.count and kind=="milestone" then summaryFacts=summaryFacts.."c" end
    end
    for _,key in ipairs({"place","when","name","count","weapon","you"}) do evidence["has_"..key]=valid(tokens[key]) end
    if heardFrom then
        local source=U().resolveActor and U().resolveActor(heardFrom)
        tokens.heard_from=heardName or source and U().nameOf(source) or "someone from our group"
        tokens.summary=summary(row,kind,tokens)
        evidence.has_heard_from=valid(tokens.heard_from) evidence.has_summary=valid(tokens.summary)
    end
    return {evidence=evidence,tokens=tokens,eventId=row.id,heardFrom=heardFrom,family=kind,summaryFacts=summaryFacts}
end
function R.toldFacts(proof,context)
    local used=proof and proof.usedTokens or {}
    local mask=""
    if used.name or used.who or used.by then mask=mask.."n" end
    if used.place then mask=mask.."p" end
    if used.when then mask=mask.."t" end
    if used.count then mask=mask.."c" end
    if used.weapon then mask=mask.."w" end
    if used.you then mask=mask.."y" end
    if used.summary then mask=mask..tostring(context and context.summaryFacts or "") end
    return mask
end
local function poolsFor(context)
    local e=context.evidence
    if e.heard then return {e.has_when and SC.RecallLines.pools.heard or SC.RecallLines.pools.heard_undated} end
    local keys={}
    if e.close_call then keys={"escape"}
    elseif e.fight then keys={"counted_fight","fight_plain"}
    elseif e.player_close_call then keys=e.covered and {"cover","player_free"} or {"player_free"}
    elseif e.death then keys={"death"}
    elseif e.homecoming then keys=e.verified_haul and {"haul","homecoming"} or {"homecoming"}
    elseif e.alarm then keys={"alarm"}
    elseif e.camp_night then keys={"camp_night"}
    elseif e.meeting then keys={"meeting"}
    elseif e.recruitment then keys={"recruitment"}
    elseif e.burial then keys={"burial"}
    elseif e.milestone then keys={"milestone"}
    elseif e.observed_bite then keys={"bite"} end
    local out={} for _,key in ipairs(keys) do if SC.RecallLines.pools[key] then out[#out+1]=SC.RecallLines.pools[key] end end
    return out
end
local function rows(force)
    local current=U().nowMs()
    if force or current>=cacheUntil then cached=SC.Community.historyRows() cacheUntil=current+10000 end
    return cached
end
function R.observePlace(actor)
    local key=SC.Tales and SC.Tales.placeKey and SC.Tales.placeKey(actor)
    local actorId=id(actor)
    local prior=places[actorId]
    if not prior or prior.key~=key then
        local count=0 for _ in pairs(places) do count=count+1 end
        if count>=64 and not prior then places={} end
        places[actorId]={key=key,pending=key~=nil}
    end
    return places[actorId]
end
function R.pick(actor,options)
    options=options or {}
    local choices={}
    local visit=R.observePlace(actor)
    local place=visit and visit.key
    local newestClose
    local history=rows(options.force)
    for _,row in ipairs(history) do
        if family[row.kind]=="close_call" or family[row.kind]=="player_close_call" then
            if not newestClose or row.at>newestClose.at then newestClose=row end
        end
    end
    for _,row in ipairs(history) do
        local context=R.context(actor,row,options.player)
        if context then
            local age=math.max(0,(now()-row.at)/86400000)
            local count=SC.VoiceMemory and SC.VoiceMemory.count(actor,"event:"..row.id) or 0
            local weight=(landmarks[context.family] and 8 or 2)+math.max(0,6-age)+(count==0 and 5 or 0)
            weight=weight/(1+count)
            local trigger="camp"
            local anniversaryKey
            local placeKey,similarKey
            if place and row.placeKey==place then
                weight=weight+8
                if visit.pending then trigger="place" placeKey=place end
            end
            if (context.family=="death" or context.family=="camp_night")
                and (age>=7 and age<8 or age>=30 and age<31) then
                anniversaryKey="anniversary:"..row.id..":"..(age<8 and "7" or "30")
                if not SC.VoiceMemory or SC.VoiceMemory.count(actor,anniversaryKey)==0 then
                    weight=weight+15 trigger="anniversary"
                else anniversaryKey=nil end
            end
            if newestClose and newestClose.id~=row.id and now()-newestClose.at<86400000
                and (context.family=="close_call" or context.family=="player_close_call") then
                local key="similar:"..newestClose.id
                if not SC.VoiceMemory or SC.VoiceMemory.count(actor,key)==0 then
                    weight=weight+8 similarKey=key
                    if not anniversaryKey and not placeKey then trigger="similar" end
                end
            end
            for _,pool in ipairs(poolsFor(context)) do
                local lines=SC.DiaryText.spokenCandidates(context,pool.packets)
                if #lines>0 then
                    if SC.VoiceMemory then lines=SC.VoiceMemory.filter(actor,pool.topic,lines,function(v) return v[1] end,#lines) end
                    if #lines>=(options.scene and 2 or 1) then
                        choices[#choices+1]={row=row,context=context,pool=pool,weight=math.max(1,math.floor(weight)),trigger=trigger,
                            anniversaryKey=anniversaryKey,placeKey=placeKey,similarKey=similarKey}
                    end
                end
            end
        end
    end
    if #choices==0 then return nil end
    local anniversaries={}
    for _,choice in ipairs(choices) do if choice.anniversaryKey then anniversaries[#anniversaries+1]=choice end end
    if #anniversaries>0 then choices=anniversaries
    else
        local returns,similar={},{}
        for _,choice in ipairs(choices) do
            if choice.placeKey then returns[#returns+1]=choice end
            if choice.similarKey then similar[#similar+1]=choice end
        end
        if #returns>0 then choices=returns elseif #similar>0 then choices=similar end
    end
    table.sort(choices,function(a,b) if a.row.id==b.row.id then return a.pool.topic<b.pool.topic end return a.row.id<b.row.id end)
    local total=0 for _,choice in ipairs(choices) do total=total+choice.weight end
    local roll=SC.DiaryText.stableHash(id(actor)..":"..now()..":"..tostring(options.salt or ""))%total
    for _,choice in ipairs(choices) do
        if roll<choice.weight then return choice end
        roll=roll-choice.weight
    end
end
function R.prepare(actor,options)
    local choice=R.pick(actor,options)
    if not choice then return nil end
    local lines,proofs=SC.DiaryText.spokenCandidates(choice.context,choice.pool.packets)
    local line,detail=SC.Dialogue.choose(actor,choice.pool.topic,{common=lines},nil,{salt=choice.row.id})
    if not line then return nil end
    return line,{eventId=choice.row.id,known=true,heardFrom=choice.context.heardFrom,
        topic=choice.pool.topic,trigger=choice.trigger,detail=detail,anniversaryKey=choice.anniversaryKey,
        placeKey=choice.placeKey,similarKey=choice.similarKey,packetProof=proofs[line]}
end
function R.note(actor,receipt)
    if receipt and receipt.known and receipt.eventId and SC.VoiceMemory then SC.VoiceMemory.noteKey(actor,"event:"..receipt.eventId) end
    if receipt and receipt.anniversaryKey and SC.VoiceMemory then SC.VoiceMemory.noteKey(actor,receipt.anniversaryKey) end
    if receipt and receipt.similarKey and SC.VoiceMemory then SC.VoiceMemory.noteKey(actor,receipt.similarKey) end
    if receipt and receipt.placeKey and places[id(actor)] and places[id(actor)].key==receipt.placeKey then places[id(actor)].pending=false end
end

local function plainPool(id,lines)
    local variants={} for n,line in ipairs(lines) do variants[#variants+1]={id=tostring(n),text=line,clean=line} end
    local topic="scene.memory_"..id
    local packets={{id=topic,scene=topic,ideaId=topic,shape="memory_reply",voiceWeights={common=1},
        requires={},asserts={},variants=variants}}
    SC.RecallLines.catalogs[#SC.RecallLines.catalogs+1]=packets
    SC.Dialogue.register(topic,{common=lines})
    return {topic=topic,packets=packets}
end
local replies={
    agree={"That one stays with you, doesn't it?","I can see why you remember.",
        "No hurry. I'm listening.","Some days stick harder than others.",
        "Let it have its minute, then let it rest.","All right. Tell it how you remember it.",
        "I'll listen to the ordinary version.","We've got time for the rest of it."},
    tease={"No adding another dozen when you tell it next week.","Let's keep the story small enough to fit through the door.",
        "Is this the edition where you keep both feet on the ground?","Careful. Next telling you'll need a bigger chair.",
        "I'll believe the useful bits. The heroics can take a number.","Does the story get taller every time we sit down?",
        "You should put a warning on the dramatic pauses.","I'm keeping an ear out for the imaginary brass band."},
    pushback={"Careful which part you blame yourself for.","It doesn't have to mean the same thing to everyone.",
        "Don't turn one moment into the whole story.","You can remember it without going through it again.",
        "Leave room for somebody else's way of carrying it.","We can talk without deciding what it says about you.",
        "I hear you. I just don't want it eating the rest of the evening.","That memory gets a chair, not the whole room."},
    comfort={"Take your time. I'm here.","Some things are easier to carry with another person nearby.",
        "You don't have to make it sound smaller for us.","I can sit with you while you tell it.",
        "Let it out at your own pace.","I'd rather hear it than have you alone with it.",
        "There's room for the feeling too.","Thank you for trusting us with that."},
    deflect={"I haven't got much to add, but I'm listening.","Let me hear the rest before I try to find the words.",
        "I don't want to put words into your memory.","I can keep you company without interrupting it.",
        "I'd rather listen for a minute.","Some stories don't need another voice in every gap.",
        "I don't know what to say to that just yet.","Give me a moment. I'm trying to hear what matters to you."}}
local replyPools,closing,griefReplies,griefClose={}
local function scenePools()
    if closing then return end
    for tag,lines in pairs(replies) do replyPools[tag]=plainPool(tag,lines) end
    closing=plainPool("close",{"We can leave the memory there for a while.","Keep the person and the place in it. That's enough.",
        "No need to turn it into a lesson before we're ready.","A plain story, kept together.",
        "All right. Let it rest beside us a while.","The evening has room for an ordinary thought too.",
        "Thanks for telling it. We can sit a little longer.","Leave the memory here with the company for a minute."})
    griefReplies={}
    for _,tag in ipairs({"agree","pushback","comfort","deflect"}) do
        local lines={}
        for _,packet in ipairs(SC.SceneLines.aftermath.death["reply_"..tag].packets) do
            for _,variant in ipairs(packet.variants) do if not variant.text:find("{",1,true) then lines[#lines+1]=variant.text end end
        end
        griefReplies[tag]=plainPool("grief_"..tag,lines)
    end
    local lines={}
    for _,packet in ipairs(SC.SceneLines.aftermath.death.close.packets) do
        for _,variant in ipairs(packet.variants) do lines[#lines+1]=variant.text end
    end
    griefClose=plainPool("grief_close",lines)
end
function R.scene(actor,options)
    options=options or {} options.scene=true
    local choice=R.pick(actor,options)
    if not choice then return nil end
    scenePools()
    local card={id="memory_"..choice.row.id,kind="shared_story",open=choice.pool,close=closing}
    for tag,pool in pairs(replyPools) do
        if choice.context.family=="death" then
            card["reply_"..tag]=griefReplies[tag]
        else
            card["reply_"..tag]=pool
            if options.addDetail and options.listener then
                local listener=R.context(options.listener,choice.row)
                if listener and listener.evidence.direct and listener.evidence.has_source and listener.evidence.source_present then
                    card["reply_"..tag]=SC.RecallLines.pools["detail_"..tag]
                end
            end
        end
        card["follow_"..tag]=choice.pool
    end
    if choice.context.family=="death" then card.close=griefClose end
    -- An exhausted optional reply does not strand a two-beat story. Keep the
    -- ordinary camp cards available until these larger pools have rested.
    if options.listener and SC.VoiceMemory then
        local branch=SC.Scenes.branch(actor,options.listener,card,SC.Scenes.griefAge()<3 or choice.context.family=="death")
        local reply=card["reply_"..branch]
        local listenerContext=R.context(options.listener,choice.row) or {evidence={},tokens={}}
        local lines=SC.DiaryText.spokenCandidates(listenerContext,reply.packets)
        local eligible=SC.VoiceMemory.filter(options.listener,reply.topic,lines,function(v) return v[1] end,#lines)
        if #eligible==0 then return nil end
    end
    if options.closer and SC.VoiceMemory then
        local lines=SC.DiaryText.spokenCandidates({evidence={},tokens={}},card.close.packets)
        if #SC.VoiceMemory.filter(options.closer,card.close.topic,lines,function(v) return v[1] end,#lines)==0 then return nil end
    end
    return card,{event=choice.row,context=choice.context,family=choice.context.family,
        recallScene=true,recallTrigger=choice.trigger,anniversaryKey=choice.anniversaryKey,
        placeKey=choice.placeKey,similarKey=choice.similarKey}
end
function R.reset() cached={} cacheUntil=-math.huge places={} end
scenePools()
return R
