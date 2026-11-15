-- SPDX-License-Identifier: MIT
-- One speech-only scene lives in Banter.party.exchange. Bounded registry and
-- ledger views are supplied by Banter; this module never searches the world.
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
local S = {} SC.Scenes = S
local requests = {}
local clock = { active = 0 }
local nextInspect, pending, pendingCalm = 0, {}, {}
local lastSceneGame, lastSceneActive = -math.huge, -math.huge
local serial, cursor, selection = 0, 0, 0
local allTags = { agree=true, tease=true, pushback=true, comfort=true, deflect=true }
local function U() return SC.GameplayUtil end
local function gameMs() return SC.LifeEvents.now() end
local function state(actor) return SC.Commands.peek(actor) end
local function id(actor) return U().idOf(actor) end
local function hash(value) return math.abs(tonumber(U().stableHash(value)) or 0) end
local function contains(list, value)
    for _, item in ipairs(list or {}) do if item==value then return true end end
    return false
end
function S.tick(current)
    local game = gameMs()
    local paused = type(isGamePaused)=="function" and isGamePaused()==true
    if clock.wall and not paused and not clock.paused and game>clock.game then
        -- A suspended process cannot turn hours of wall time into chatter.
        clock.active=clock.active+math.max(0,math.min(10000,current-clock.wall))
    end
    clock.wall,clock.game,clock.paused=current,game,paused
    return not paused
end
function S.clock() return clock.active, gameMs() end

local families={companion_died="death",companion_death="death",shared_escape="close_call",
    rescued_player="close_call",player_rescued="close_call",player_close_call="close_call",
    expedition_homecoming="homecoming",supply_run_completed="homecoming",alarm_fought_off="alarm"}
local function eventKey(row)
    if families[row.kind]=="death" then return "death:"..tostring(row.targetId or row.sourceId) end
    return row.id
end
local function inspectEvents(current)
    if current<nextInspect then return end
    nextInspect=current+10000
    local rows, seen={},{}
    for _,row in ipairs(SC.Community.historyRows()) do
        local key=eventKey(row)
        if families[row.kind] and not row.aftermathDone and not seen[key] then
            seen[key]=true rows[#rows+1]=row
        end
    end
    table.sort(rows,function(a,b)
        local ap,bp=families[a.kind]=="death",families[b.kind]=="death"
        if ap~=bp then return ap end
        if a.at==b.at then return a.id<b.id end
        return a.at<b.at
    end)
    pending=rows
    local kept={}
    for _,row in ipairs(rows) do kept[eventKey(row)]=pendingCalm[eventKey(row)] end
    pendingCalm=kept
end

function S.griefAge()
    local newest
    for _,row in ipairs(SC.Community.recentDeaths(32)) do
        local at=tonumber(row.startedAt)
        if at and (not newest or at>newest) then newest=at end
    end
    return newest and math.max(0,(gameMs()-newest)/86400000) or math.huge
end

function S.branch(first, second, card, grief)
    local pair=SC.Community.relation(id(first),id(second),false) or {}
    local commands=state(second)
    local profile=commands.personalityProfile or {}
    local personality=commands.personality
    local tag
    if (tonumber(pair.tension) or 0)>=55 or (tonumber(pair.opinion) or 0)<-15 then tag="pushback"
    elseif personality=="caring" then tag="comfort"
    elseif personality=="cautious" then tag="pushback"
    elseif personality=="brave" and not grief and (tonumber(pair.familiarity) or 0)>=20 then tag="tease"
    elseif personality=="practical" then tag="agree"
    elseif (tonumber(profile.compassion) or 0)>=70 then tag="comfort"
    else tag="deflect" end
    if not card["reply_"..tag] then tag=card.reply_comfort and "comfort" or "agree" end
    return tag
end

local reasons={supply_run_rough="last_run",supply_run_completed="last_run",
    hidden_bite_revealed="hidden_bite",fled_fight="fled_fight",food_eaten="food_eaten",door_left_open="door_open"}
local reasonNames={last_run="the supply run",hidden_bite="the concealed bite",
    fled_fight="leaving the fight",food_eaten="the shared food",door_open="the open door"}
function S.argumentReason(first,second)
    local pair=SC.Community.relation(id(first),id(second),false)
    for n=#(pair and pair.memories or {}),1,-1 do
        local memory=pair.memories[n]
        local reason=reasons[memory.kind]
        if reason then
            local row=memory.eventId and SC.Community.historyRow(memory.eventId)
            -- Disclosure/food/flight/door accusations require actual shared
            -- evidence. A memory label alone cannot expose a concealed bite.
            if reason=="last_run" or row and row.sourceId==id(second)
                and (reason~="food_eaten" or row.outcome=="shared_reserve")
                and SC.Community.knowsEvent(first,row)
                and SC.Community.knowsEvent(second,row) then return reason,row or memory end
        end
    end
end
function S.requestArgument(first,second)
    local reason,row=S.argumentReason(first,second)
    if not reason then return nil,"no_shared_argument_reason" end
    for _,request in ipairs(requests) do
        if request.first==first and (request.status=="pending" or request.status=="running") then return request end
    end
    if #requests>=4 then return nil,"scene_requests_full" end
    local ticket={first=first,second=second,reason=reason,row=row,status="pending",at=clock.active}
    requests[#requests+1]=ticket
    return ticket
end
function S.cancel(ticket)
    if ticket and (ticket.status=="pending" or ticket.status=="running") then ticket.status="cancelled" end
end

local function eventContext(row,family,first,player)
    local evidence={known=true}
    evidence[family]=true
    local name=row.targetName or row.subjectName or row.sourceName
    if row.targetId=="player:local" or row.sourceId=="player:local" then name=U().nameOf(player) end
    local tokens={name=name,place=row.place}
    evidence.has_name=SC.DiaryText.validToken(name)
    evidence.has_place=SC.DiaryText.validToken(row.place)
    evidence.crew_returned=contains(row.participants,id(first))
        and (row.kind=="supply_run_completed" or row.outcome=="crew_returned" or row.outcome=="returned_with_losses")
    evidence.all_clear=row.kind=="alarm_fought_off" and row.outcome=="all_clear"
    return {evidence=evidence,tokens=tokens}
end
local function rolesReady(scene,records,host)
    if scene.ticket and scene.ticket.status=="cancelled" then return false end
    for n,role in ipairs(scene.roles) do
        local other=n==2 and scene.first or scene.second
        local record=host.record(records,role.actor)
        local view=scene
        if n==3 then view={id=scene.id,kind="scene",faceToFace=false} end
        if not host.ready(record,role.actor,other,view,true)
            or state(role.actor).order=="guard" or state(role.actor).order=="work"
            or (tonumber(state(role.actor).commandSerial) or 0)~=role.commandSerial
            or not host.unchanged(role.actor,role.spokenAt,role.topic)
            or not U().sameFloor(scene.first,role.actor)
            or U().distance(scene.first,role.actor)>10
            or n>1 and not (U().canSee(scene.first,role.actor) or U().canSee(role.actor,scene.first))
            or SC.Factions and SC.Factions.isHostileBetween
                and SC.Factions.isHostileBetween(scene.first,role.actor,scene.player) then return false end
    end
    return true
end
local function beat(scene,number)
    if scene.beats then
        local row=scene.beats[number]
        return scene.roles[row.role],scene.card[row.phase],row.tag,row.accepts
    end
    if number==1 then return scene.roles[1],scene.card.open,"deflect",allTags end
    if number==2 then return scene.roles[2],scene.card["reply_"..scene.branch],scene.branch,allTags end
    if number==3 then return scene.roles[1],scene.card["follow_"..scene.branch],"agree",{[scene.branch]=true} end
    return scene.roles[3] or scene.roles[2],scene.card.close,"agree",allTags
end
local function speakBeat(scene,current,host)
    local role,pool,tag,accepts=beat(scene,scene.step)
    if not pool or scene.lastTag and not accepts[scene.lastTag] then return false,"scene_tag_mismatch" end
    local context=scene.context or {evidence={},tokens={}}
    if scene.event then
        context.evidence.known=SC.Community.knowsEvent(role.actor,scene.event)==true
    end
    local lines,proofs=SC.DiaryText.spokenCandidates(context,pool.packets)
    if #lines==0 then return false,"scene_evidence_missing" end
    local options={state=state(role.actor),sceneId=scene.id,sceneKind=scene.sceneKind,
        tag=tag,accepts=accepts,eventId=scene.event and scene.event.id,
        tone=scene.card.kind=="joke" and "light" or "serious",aboutDead=scene.family=="death",
        salt=scene.id..":"..scene.step}
    if scene.event and scene.step==1 then
        options.recall=true options.evidence={known=context.evidence.known,eventId=scene.event.id}
    end
    local spoken,line,detail=host.say(role.actor,pool.topic,{common=lines},options)
    if not spoken then return false,line or "scene_speech_rejected" end
    if not proofs[line] then return false,"scene_packet_receipt_missing" end
    role.spokenAt,role.topic=SC.Dialogue.lastSpokenAt(role.actor),pool.topic
    role.displayUntil=SC.Dialogue.lastDisplayUntil(role.actor)
    scene.lastTag=tag scene.step=scene.step+1
    scene.nextAt=clock.active+2800
    host.spend(current)
    -- A spoken first-hand account teaches only those actually in this scene.
    if scene.event then
        for _,listener in ipairs(scene.roles) do
            if listener.actor~=role.actor then SC.Community.tellEvent(id(role.actor),id(listener.actor),scene.event.id,true) end
        end
    end
    return true,pool.topic
end
local function life(kind,first,second,fields)
    fields=fields or {}
    fields.participants={id(first),id(second)} fields.targetId=id(second) fields.targetName=U().nameOf(second)
    return SC.LifeEvents.observed(kind,first,fields)
end
local function complete(scene)
    if scene.event and scene.sceneKind=="aftermath" then SC.Community.completeAftermath(scene.event) nextInspect=0 end
    if scene.sceneKind=="argument" then
        local first,second=scene.first,scene.second
        life("argument",first,second,{reason=scene.reason,eventId=scene.event and scene.event.id})
        local resolved=scene.branch=="agree" or scene.branch=="comfort"
        local pair=SC.Community.relation(id(first),id(second),true)
        local compassion=tonumber((state(first).personalityProfile or {}).compassion) or 50
        local shove=not resolved and pair.tension>=75 and compassion<70
            and U().distance(first,second)<=2.25 and hash(scene.id..":shove")%100<5
        if resolved then
            SC.Community.clearGrudge(first,second) life("reconciled",first,second)
        else
            SC.Community.setGrudge(first,second,scene.reason,scene.reasonEventId,gameMs()+72*3600000)
        end
        if scene.ticket then scene.ticket.outcome=shove and "shove" or resolved and "resolved" or "walk_away" end
    elseif scene.sceneKind=="makeup" then
        SC.Community.clearGrudge(scene.first,scene.second)
        life("reconciled",scene.first,scene.second)
    elseif scene.sceneKind=="comfort" then
        SC.Community.addThought(scene.first,{key="companion_comfort:"..scene.id,kind="received_support",
            text="Someone sat with me while I steadied myself.",stress=-4,morale=2,
            at=gameMs(),expiresAt=gameMs()+6*3600000})
    end
    if scene.ticket then scene.ticket.status="finished" end
end

function S.advance(scene,records,current,host)
    if not rolesReady(scene,records,host) or clock.active>=scene.expiresActive then
        if scene.ticket then scene.ticket.status="cancelled" end
        host.release(scene,"scene_interrupted")
        return false,"scene_interrupted",false
    end
    if clock.active<scene.nextAt then return false,"scene_waiting",true end
    local role=beat(scene,scene.step)
    if current<(role.displayUntil or 0) then return false,"scene_reading",true end
    local spoken,reason=speakBeat(scene,current,host)
    if not spoken then
        if scene.ticket then scene.ticket.status="cancelled" end
        host.release(scene,reason) return false,reason,false
    end
    if scene.step>#scene.beats then
        complete(scene) host.release(scene,"scene_finished") return true,reason,false
    end
    return true,reason,true
end

local function start(first,second,third,card,player,current,host,settings)
    settings=settings or {}
    serial=serial+1
    local scene={id="scene:"..gameMs()..":"..serial,kind="scene",generalized=true,
        sceneKind=settings.kind or card.kind,card=card,first=first.actor,second=second.actor,
        roles={},player=player,step=1,nextAt=clock.active,expiresActive=clock.active+75000,
        faceToFace=false,context=settings.context,event=settings.event,family=settings.family,
        reason=settings.reason,reasonEventId=settings.reasonEventId,ticket=settings.ticket}
    local grief=S.griefAge()<3 or settings.family=="death"
    scene.branch=S.branch(scene.first,scene.second,card,grief)
    for _,candidate in ipairs({first,second,third}) do
        scene.roles[#scene.roles+1]={actor=candidate.actor,
            commandSerial=tonumber(state(candidate.actor).commandSerial) or 0,
            spokenAt=SC.Dialogue.lastSpokenAt(candidate.actor) or -math.huge,topic=SC.Dialogue.lastSpokenTopic(candidate.actor)}
    end
    scene.beats=settings.beats or {
        {role=1,phase="open",tag="deflect",accepts=allTags},
        {role=2,phase="reply_"..scene.branch,tag=scene.branch,accepts=allTags},
        {role=1,phase="follow_"..scene.branch,tag="agree",accepts={[scene.branch]=true}},
        {role=scene.roles[3] and 3 or 2,phase="close",tag="agree",accepts=allTags},
    }
    if #scene.beats<3 or #scene.beats>6 then return nil,"scene_beat_limit" end
    for _,entry in ipairs(scene.beats) do
        if not scene.roles[entry.role] or not card[entry.phase] or not allTags[entry.tag]
            or type(entry.accepts)~="table" then return nil,"scene_invalid_beat" end
    end
    if first.freeToFace and second.freeToFace and host.face then
        scene.faceToFace=host.face(scene.first,scene.second,scene.id)==true
        if not scene.faceToFace then return nil,"scene_pose_unavailable" end
    end
    if not rolesReady(scene,host.records,host) then host.release(scene,"scene_not_ready") return nil,"scene_not_ready" end
    local spoken,reason=speakBeat(scene,current,host)
    if not spoken then host.release(scene,reason) return nil,reason end
    if settings.ticket then settings.ticket.status="running" end
    lastSceneGame,lastSceneActive=gameMs(),clock.active
    selection=selection+1
    return scene,reason
end

local function candidates(player,records,current,host)
    local rows={}
    for n=1,math.min(64,#records) do
        local record=records[n]
        local commands,free=host.quiet(record,player,current,14)
        if commands and select(1,U().call(record.actor,"isMoving"))~=true then
            rows[#rows+1]={actor=record.actor,commands=commands,freeToFace=free,
                atCamp=host.atCamp(record.actor)}
        end
    end
    return rows
end
local function together(a,b)
    return a~=b and U().sameFloor(a.actor,b.actor) and U().distance(a.actor,b.actor)<=10
        and (U().canSee(a.actor,b.actor) or U().canSee(b.actor,a.actor))
        and not (SC.Factions and SC.Factions.isHostileBetween
            and SC.Factions.isHostileBetween(a.actor,b.actor))
end
local function byActor(rows,actor)
    for _,row in ipairs(rows) do if row.actor==actor then return row end end
end
local function thirdFor(rows,first,second)
    for _,row in ipairs(rows) do if row~=first and row~=second and together(first,row) and together(second,row) then return row end end
end
local function escapedSince(pair,at)
    for _,memory in ipairs(pair.memories or {}) do
        if memory.kind=="shared_escape" and (tonumber(memory.at) or 0)>=at then return true end
    end
    return false
end
local function affected(rows,event,family)
    local best,score
    for _,row in ipairs(rows) do if SC.Community.knowsEvent(row.actor,event) then
        local value=0
        if family=="death" then
            local pair=SC.Community.relation(id(row.actor),event.targetId or event.sourceId,false) or {}
            value=(pair.opinion or 0)+(pair.trust or 0)+(pair.familiarity or 0)*.5
        elseif id(row.actor)==event.sourceId or id(row.actor)==event.targetId then value=1000
        elseif contains(event.participants,id(row.actor)) then value=100 end
        if family~="homecoming" or contains(event.participants,id(row.actor)) then
            if not best or value>score then best,score=row,value end
        end
    end end
    return best
end

function S.tryStart(player,records,current,host,priorityOnly)
    inspectEvents(current)
    for n=1,math.min(64,#records) do
        if host.calm and not host.calm(records[n]) then pendingCalm={} return nil,"scene_danger" end
    end
    local rows=candidates(player,records,current,host)
    if #rows<2 then
        pendingCalm={} return nil,"scene_no_pair"
    end
    if not host.budget(current) then return nil,"scene_budget" end
    host.records=records
    if #rows>1 then
        local rotated={}
        for n=1,#rows do rotated[n]=rows[(n-1+selection)%#rows+1] end
        rows=rotated
    end
    -- One pending event is considered per pulse, round-robin when its people
    -- are absent. Candidate and history caps are independent of world size.
    if #pending>0 then
        cursor=cursor%#pending+1
        local row=pending[cursor]
        local family=families[row.kind]
        local first=affected(rows,row,family)
        local second
        if first then for _,candidate in ipairs(rows) do
            if together(first,candidate) and (family~="homecoming"
                or not contains(row.participants,id(candidate.actor))) then second=candidate break end
        end end
        local key=eventKey(row)
        local context=first and eventContext(row,family,first.actor,player)
        if first and second and #SC.DiaryText.spokenCandidates(context,SC.SceneLines.aftermath[family].open.packets)==0 then
            first,second=nil,nil
        end
        if first and second then
            pendingCalm[key]=pendingCalm[key] or clock.active
            if clock.active-pendingCalm[key]>=30000 then
                local scene,reason=start(first,second,thirdFor(rows,first,second),SC.SceneLines.aftermath[family],
                    player,current,host,{kind="aftermath",event=row,family=family,context=context})
                if scene then return scene,reason end
            end
        else pendingCalm[key]=nil end
        -- Eligible aftermaths have the next slot, ahead of optional chatter.
        if first and second then return nil,"aftermath_settling",true end
    end
    for n=#requests,1,-1 do
        local ticket=requests[n]
        if ticket.status~="pending" or clock.active-ticket.at>30000 then
            if ticket.status=="pending" then ticket.status="cancelled" end
            table.remove(requests,n)
        else
            local first,second=byActor(rows,ticket.first),byActor(rows,ticket.second)
            if first and second and together(first,second) then
                return start(first,second,nil,SC.SceneLines.arguments[ticket.reason],player,current,host,
                    {kind="argument",reason=ticket.reason,reasonEventId=ticket.row.id,ticket=ticket})
            end
        end
    end
    if priorityOnly then return nil,"no_priority_scene" end
    local multiplier=SC.Banter.chatterMultiplier()
    if gameMs()-lastSceneGame<2*3600000*multiplier or clock.active-lastSceneActive<180000*multiplier then
        return nil,"scene_cooldown"
    end
    -- Reconciliation has priority over choosing any unrelated quiet pair.
    for a=1,#rows do for b=a+1,#rows do
        local first,second=rows[a],rows[b]
        local pair=SC.Community.relation(id(first.actor),id(second.actor),false)
        local grudge=pair and pair.grudge
        if grudge and together(first,second) then
            if gameMs()>=grudge.untilAt or escapedSince(pair,grudge.startedAt) then
                return start(first,second,thirdFor(rows,first,second),SC.SceneLines.makeup,player,current,host,
                    {kind="makeup",context={evidence={has_reason=true},tokens={reason=reasonNames[grudge.reason]}}})
            end
        end
    end end
    for firstIndex=1,#rows do
        local first=rows[firstIndex]
        for secondIndex=firstIndex+1,#rows do
            local second=rows[secondIndex]
            if together(first,second) then
                local pair=SC.Community.relation(id(first.actor),id(second.actor),false) or {}
                local camp=first.atCamp and second.atCamp
                if camp or hash(tostring(math.floor(gameMs()/3600000)))%3==0 then
                    local stressed=(tonumber(first.commands.stress) or 0)>=45 or SC.Community.activeGrief(first.actor)~=nil
                    local helpful=second.commands.personality=="caring" or (pair.opinion or 0)>=35
                    local choices={}
                    for _,card in ipairs(SC.SceneLines.cards) do
                        if card.kind=="plans" or card.kind=="comfort" and stressed and helpful
                            or card.kind=="joke" and not stressed and S.griefAge()>=3 and (pair.familiarity or 0)>=20 then
                            choices[#choices+1]=card
                        end
                    end
                    local card
                    if stressed and helpful then
                        local comfort={} for _,entry in ipairs(choices) do if entry.kind=="comfort" then comfort[#comfort+1]=entry end end
                        if #comfort>0 then card=comfort[hash(id(first.actor)..gameMs())%#comfort+1] end
                    end
                    card=card or choices[hash(id(first.actor)..":"..gameMs()..":"..selection)%#choices+1]
                    return start(first,second,thirdFor(rows,first,second),card,player,current,host)
                end
            end
        end
    end
    return nil,"scene_no_pair"
end

function S.reset()
    requests={} clock={active=0} nextInspect=0 pending={} pendingCalm={}
    lastSceneGame,lastSceneActive=-math.huge,-math.huge serial=0 cursor=0 selection=0
end
function S._startForTests(...) return start(...) end
function S._pendingForTests() return pending end
return S
