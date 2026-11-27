-- SPDX-License-Identifier: MIT
-- Bounded, additive evidence for spoken history. No actor or world scans.
LivingFellows=LivingFellows or {}
local SC=LivingFellows
local H={} SC.SharedHistory=H
H.HISTORY_LIMIT,H.LANDMARK_LIMIT,H.TOLD_LIMIT=96,24,24
local textFields={place=80,sourceName=80,targetName=80,subjectName=80,participantNames=160,
    witnessNames=160,weapon=80,item=80,outcome=120,heardFrom=80,placeKey=100}
local numberFields={day={0,1000000},hour={0,24},month={0,11},year={1,9999},count={0,10000000},kills={0,10000000},wounds={0,1000}}
local booleanFields={"wasGrabbed","wasDowned","factsQuarantined","communityRecorded","aftermathDone"}
local landmarks={companion_died=true,companion_death=true,first_meeting=true,rescued_player=true,
    player_rescued=true,player_close_call=true,first_camp_night=true}
local function finite(value,minimum,maximum)
    return type(value)=="number" and value==value and value~=math.huge and value~=-math.huge
        and value>=minimum and value<=maximum
end
local function text(value,limit)
    if type(value)~="string" then return nil end
    return value:gsub("[%c]"," "):sub(1,limit)
end
local function factMask(value)
    if value=="all" then return "nptcwy" end
    local out=""
    for key in ("nptcwy"):gmatch(".") do
        if type(value)=="string" and value:find(key,1,true) then out=out..key end
    end
    return out
end
function H.ids(source)
    local out,seen={},{}
    if type(source)~="table" then return out,source~=nil end
    local bad,inspected=false,0
    for key,value in pairs(source) do
        inspected=inspected+1 if inspected>32 then bad=true break end
        if type(key)~="number" or key<1 or key>16 or key~=math.floor(key) or type(value)~="string" then bad=true end
    end
    for n=1,16 do
        local value=source[n]
        if value~=nil then
            local id=text(value,80)
            if id and id~="" and not seen[id] then out[#out+1]=id seen[id]=true else bad=true end
        end
    end
    return out,bad
end
-- Preserve old event fields; quarantine only the new optional evidence fields.
function H.cleanRow(source)
    if type(source)~="table" then return source end
    local row={} for key,value in pairs(source) do row[key]=value end
    local bad=false
    for key,limit in pairs(textFields) do if source[key]~=nil then
        row[key]=text(source[key],limit) if row[key]==nil then bad=true end
    end end
    for key,bounds in pairs(numberFields) do if source[key]~=nil then
        if finite(source[key],bounds[1],bounds[2]) and (key~="hour" or source[key]<24)
            and ((key~="day" and key~="kills" and key~="wounds" and key~="month" and key~="year") or source[key]==math.floor(source[key])) then row[key]=source[key]
        else row[key]=nil bad=true end
    end end
    for _,key in ipairs(booleanFields) do if source[key]~=nil and type(source[key])~="boolean" then row[key]=nil bad=true end end
    if source.witnesses~=nil then local invalid row.witnesses,invalid=H.ids(source.witnesses) bad=bad or invalid end
    if bad then row.factsQuarantined=true end
    return row
end
function H.cleanDocument(source)
    if type(source)~="table" then return source end
    local out={} for key,value in pairs(source) do out[key]=value end
    if SC.VoiceMemory then out.voiceMemory=SC.VoiceMemory.clean(source.voiceMemory) end
    if source.voiceSceneAt~=nil and not finite(source.voiceSceneAt,0,math.huge) then out.voiceSceneAt=nil end
    for _,key in ipairs({"history","landmarks"}) do
        if type(source[key])=="table" then
            local rows={} local inspected=0
            for index,row in pairs(source[key]) do
                inspected=inspected+1 if inspected>512 then rows._invalidHistorySize=true break end
                rows[index]=H.cleanRow(row)
            end
            out[key]=rows
        end
    end
    return out
end
function H.normalize(document)
    document.landmarks=type(document.landmarks)=="table" and document.landmarks or {}
    document.heardEvents=type(document.heardEvents)=="table" and document.heardEvents or {}
    document.historyFlags=type(document.historyFlags)=="table" and document.historyFlags or {}
    local kept,seen={},{}
    for _,row in ipairs(document.landmarks) do
        if type(row)=="table" and type(row.id)=="string" and landmarks[row.kind] and not seen[row.id] then
            kept[#kept+1]=H.cleanRow(row) seen[row.id]=true
            if #kept>=H.LANDMARK_LIMIT then break end
        end
    end
    document.landmarks=kept
    local heard,count={},0
    for id,rows in pairs(document.heardEvents) do
        if type(id)=="string" and type(rows)=="table" and count<64 then
            local values={}
            for _,row in ipairs(rows) do
                if type(row)=="table" and type(row.eventId)=="string" and type(row.from)=="string" then
                    values[#values+1]={eventId=text(row.eventId,100),from=text(row.from,80),fromName=text(row.fromName,80),facts=factMask(row.facts)}
                    if #values>=H.TOLD_LIMIT then break end
                end
            end
            heard[text(id,80)]=values count=count+1
        end
    end
    document.heardEvents=heard
    -- Only fixed milestone flags and one current camp key are retained.
    local flags=document.historyFlags
    document.historyFlags={camp=text(flags.camp,100),firstNight=flags.firstNight==true,
        day=finite(flags.day,0,1000000) and flags.day or nil,
        day7=flags.day7==true,day30=flags.day30==true,day100=flags.day100==true}
    return document
end
function H.retain(document,row)
    H.normalize(document)
    if not landmarks[row.kind] or type(row.id)~="string" then return end
    for _,prior in ipairs(document.landmarks) do if prior.id==row.id then return end end
    if #document.landmarks<H.LANDMARK_LIMIT then document.landmarks[#document.landmarks+1]=H.cleanRow(row) end
end
function H.find(document,id)
    for _,rows in ipairs({document.landmarks or {},document.history or {}}) do
        for n=#rows,1,-1 do if rows[n].id==id then return rows[n] end end
    end
end
function H.known(document,id,row)
    if type(row)~="table" or type(id)~="string" then return false end
    if row.sourceId==id or row.targetId==id then return true end
    for _,list in ipairs({row.participants or {},row.witnesses or {}}) do
        for _,other in ipairs(list) do if other==id then return true end end
    end
    for _,heard in ipairs((document.heardEvents or {})[id] or {}) do
        if heard.eventId==row.id then return true,heard.from,heard.fromName,heard.facts end
    end
    return false
end
function H.tell(document,from,to,eventId,onScreen,facts)
    local row=H.find(document,eventId)
    local knows,source,_,sourceFacts=H.known(document,from,row)
    if onScreen~=true or not knows or not to or to==from then return false end
    -- A retelling remains explicitly hearsay; it cannot seed another person's
    -- first stored account. New knowledge comes from a first-hand teller.
    if source then return false end
    local mask=factMask(facts==nil and "all" or facts)
    H.normalize(document)
    local rows=document.heardEvents[to] or {}
    local already,teller=H.known(document,to,row)
    if already and not teller then return false end
    if document.heardEvents[to]==nil then
        local count=0 for _ in pairs(document.heardEvents) do count=count+1 end
        if count>=64 then return false end
    end
    local actor=SC.GameplayUtil and SC.GameplayUtil.resolveActor and SC.GameplayUtil.resolveActor(from)
    local name=actor and SC.GameplayUtil.nameOf(actor) or row.sourceId==from and row.sourceName or nil
    for _,heard in ipairs(rows) do if heard.eventId==eventId then
        if heard.from==from then heard.facts=factMask(heard.facts..mask) return true end
        return false
    end end
    rows[#rows+1]={eventId=eventId,from=from,fromName=text(name,80),facts=mask}
    while #rows>H.TOLD_LIMIT do table.remove(rows,1) end
    document.heardEvents[to]=rows return true
end
function H.observeClock(document,actor,state)
    if not state or state.recruited~=true or not SC.LifeEvents or not SC.LifeEvents.observed then return end
    H.normalize(document)
    local flags=document.historyFlags
    local age=SC.LifeEvents.now()/3600000
    local day=math.floor(age/24)
    for _,milestone in ipairs({7,30,100}) do
        local key="day"..milestone
        if not flags[key] and day>=milestone then
            flags[key]=true
            -- Loading an old save never invents an event on an earlier day.
            if day==milestone then SC.LifeEvents.observed("survival_milestone",actor,{
                participants={SC.GameplayUtil.idOf(actor)},count=milestone,outcome="world_day"}) end
        end
    end
    flags.day=day
    local base=SC.BaseLife and SC.BaseLife.active and SC.BaseLife.active()
    if not base or not SC.BaseLife.isInside(actor) then return end
    local key=tostring(base.id or "camp"):sub(1,100)
    if flags.camp~=key then flags.camp=key flags.firstNight=false end
    if not flags.firstNight and (age%24>=20 or age%24<5) then
        flags.firstNight=true
        SC.LifeEvents.observed("first_camp_night",actor,{participants={SC.GameplayUtil.idOf(actor)},
            place=type(base.name)=="string" and base.name or nil,outcome="nightfall"})
    end
end
return H
