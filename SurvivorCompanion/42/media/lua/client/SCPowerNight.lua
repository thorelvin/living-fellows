-- SPDX-License-Identifier: MIT
-- County archive. Only native receiver acknowledgements admit an audience.
SurvivorCompanion=SurvivorCompanion or {}
local SC=SurvivorCompanion
SC.PowerNight=SC.PowerNight or {}
local N=SC.PowerNight
N.KEY="LF_PowerNightV1"
N.MARKER="LF_POWER_NIGHT"
local store,channels,inflight,lastMinute=nil,{},nil,nil
local receiverReady
local received=setmetatable({}, {__mode="k"})
local audience=setmetatable({}, {__mode="k"})
local surveys=setmetatable({}, {__mode="k"})
local function U() return SC.ControlUtil end
local function call(object,method,...) return U().call(object,method,...) end
local function catalog() return SC.PowerNightCatalog end
function N.supported()
    return not (type(isClient)=="function" and isClient())
        and not (type(isServer)=="function" and isServer())
end
local function state()
    if store then return store end
    if not N.supported() or not ModData or not ModData.getOrCreate then return nil end
    local raw=ModData.getOrCreate(N.KEY)
    if raw.schema~=nil and raw.schema~=1 then return nil end
    if raw.schema==nil then
        raw.schema,raw.discovered,raw.enabled,raw.serial=1,false,true,0
        raw.library,raw.viewers,raw.frequencies={},{},{}
    end
    if type(raw.library)~="table" or type(raw.viewers)~="table"
        or type(raw.frequencies)~="table" then return nil end
    store=raw
    return store
end
function N.gridOn()
    local time=type(getWorld)=="function" and getWorld()
    -- Uses the native active electricity state, including LF's grid lease.
    return call(time,"isHydroPowerOn")==true
end
local function clock()
    local time=type(getGameTime)=="function" and getGameTime()
    local hours=tonumber(call(time,"getWorldAgeHours"))
    local tod=tonumber(call(time,"getTimeOfDay"))
    if not hours or not tod or hours~=hours or tod~=tod then return nil end
    return {hours=hours,minute=math.floor(hours*60+.00001),day=math.floor((hours-tod)/24+.00001),tod=tod}
end
local function person(actor,create)
    local s=state()
    local md=U().data(actor)
    if not s or not md then return nil end
    local id=md.SC_Id or md.LF_HandoverCompanionId or md.LF_PowerNightPerson
    if not id and create then
        s.serial=(tonumber(s.serial) or 0)+1
        id="lf-pn-person-"..s.serial
        md.LF_PowerNightPerson=id
    end
    if type(id)~="string" then return nil end
    local row=s.viewers[id]
    if not row and create then row={lessons={}} s.viewers[id]=row end
    if row and (type(row)~="table" or type(row.lessons)~="table") then return nil end
    return row,id
end
function N.knowsLesson(actor,guid)
    local row=person(actor,false)
    return row and row.lessons[guid]==true or false
end
function N.noteLesson(actor,guid)
    if type(guid)~="string" or guid=="" or #guid>160 then return end
    local row=person(actor,true)
    if row then row.lessons[guid]=true end
end
function N.restoreKnowledge(actor)
    local row=person(actor,false)
    if row then for guid in pairs(row.lessons) do call(actor,"addKnownMediaLine",guid) end end
    local id=SC.Registry and SC.Registry.idOf(actor)
    local record=id and SC.Registry.byId(id)
    local old=record and record.state and record.state.downtime
    for _,guid in ipairs(old and old.mediaLines or {}) do call(actor,"addKnownMediaLine",guid) end
end
local function register(medium,s)
    local api=type(getZomboidRadio)=="function" and getZomboidRadio()
    local manager=call(api,"getScriptManager")
    if not api or not manager or not DynamicRadioChannel or not ChannelCategory then return false end
    local guid="LF_POWER_NIGHT_"..medium.."_V1"
    local current=call(manager,"getRadioChannel",guid)
    local frequency=tonumber(s.frequencies[medium])
    if frequency and (frequency~=frequency or frequency~=math.floor(frequency)) then frequency=nil end
    if current and call(current,"getGUID")==guid then
        channels[medium]=current
        s.frequencies[medium]=call(current,"GetFrequency")
        return true
    end
    local name=medium=="tv" and "EMMA Archive TV" or "EMMA Archive Radio"
    local category=medium=="tv" and ChannelCategory.Television or ChannelCategory.Radio
    local first,last,step=medium=="tv" and 202 or 96600,medium=="tv" and 999 or 108000,medium=="tv" and 1 or 200
    local function free(value)
        local name=value and call(api,"getChannelName",value)
        return value and (name==nil or name=="")
    end
    if not free(frequency) then frequency=nil end
    if not frequency then for candidate=first,last,step do if free(candidate) then frequency=candidate break end end end
    if not frequency then return false end
    local object=DynamicRadioChannel.new(name,frequency,category,guid)
    manager:AddChannel(object,false)
    if call(manager,"getRadioChannel",guid)~=object then return false end
    s.frequencies[medium],channels[medium]=frequency,object
    return true
end
local function choose(s,medium,day)
    local best,previous
    for id,entry in pairs(s.library) do
        local row=catalog().resolve(id)
        if row and row.medium==medium and type(entry)=="table" then
            local at=tonumber(entry.lastAired) or -math.huge
            if not best or at<previous or at==previous and id<best then best,previous=id,at end
        end
    end
    if best then s.library[best].lastAired=day end
    return best
end
local function lineup(s,c)
    if type(s.night)~="table" or s.night.day~=c.day then
        s.night={day=c.day,tv=choose(s,"tv",c.day),radio=choose(s,"radio",c.day)}
    end
    return s.night
end
function N.discover(player,computer)
    local s=state()
    if not s or not N.computerAccess(player,computer) then return false end
    if s.discovered then return false end
    s.discovered=true
    for _,id in ipairs(catalog().starters) do s.library[id]=s.library[id] or {} end
    register("tv",s) register("radio",s)
    return true
end
function N.computerAccess(player,computer)
    if not player or not computer or call(player,"isDead")==true or not U().present(computer)
        or not U().near(player,computer,3) or not SC.TerminalHardware.powered(computer) then return false end
    if SC.EmmaJump and SC.EmmaJump.active(player,computer) then return false end
    local from,to=U().square(player),U().square(computer)
    if from~=to and call(from,"canReachTo",to)~=true then return false end
    local md=U().data(computer)
    local os=md and md.movableData and SC.TerminalSystem.normalize(md.movableData.LF_LarchOS)
    return os~=nil and not os.locked
end
function N.copy(player,computer,item)
    local s=state()
    if not s or not s.discovered or not N.computerAccess(player,computer) or not U().owns(player,item) then
        return false,"Stay beside an unlocked, powered EMMA computer with the recording."
    end
    local row=catalog().item(item)
    if not row then return false,"This recording is unavailable or incompatible with the archive." end
    if s.library[row.id] then return false,"Already archived: "..row.title end
    s.library[row.id]={}
    return true,"Archived "..row.title..". You kept the original recording."
end
function N.setEnabled(player,computer,enabled)
    local s=state()
    if not s or not s.discovered or not N.computerAccess(player,computer) then return false,"Computer access was lost." end
    s.enabled=enabled==true
    received,audience=setmetatable({}, {__mode="k"}),setmetatable({}, {__mode="k"})
    return true,s.enabled and "Nightly broadcasts enabled." or "Nightly broadcasts disabled."
end
function N.isArchive(object)
    local s=state()
    local data=call(object,"getDeviceData")
    local medium=call(data,"getIsTelevision")==true and "tv" or "radio"
    return s and s.frequencies[medium]~=nil and call(data,"getChannel")==s.frequencies[medium],medium
end
function N.active()
    local s,c=state(),clock()
    return s and s.discovered==true and s.enabled==true and c and c.tod>=20 and c.tod<21
        and N.gridOn() and not (SC.Handover and SC.Handover.isPaused()) or false
end
function N.mayJoin(actor)
    if not N.active() or not SC.BaseLife or not SC.BaseLife.isInside(actor)
        or call(actor,"getVehicle") or call(actor,"isAsleep")==true then return false end
    local commands=SC.Commands and SC.Commands.peek(actor)
    local id=SC.Registry and SC.Registry.idOf(actor)
    local resident=id and SC.BaseLife.resident and SC.BaseLife.resident(id)
    if id and SC.BaseLife.guardStatus then
        if SC.BaseLife.guardStatus(id,U().now())==true then return false end
    elseif resident and resident.role=="guard" and resident.duty==true then return false end
    return commands and commands.recruited==true
        and (commands.order=="base_duty" or commands.order=="follow")
        and not (SC.ExpeditionPrototype and SC.ExpeditionPrototype.isMember(actor))
end
function N.surveyDue(actor,medium,current)
    if not N.mayJoin(actor) then return false end
    local c=clock()
    local row=surveys[actor]
    if not row or row.day~=c.day then row={day=c.day} surveys[actor]=row end
    local last=row[medium]
    if last and current>=last and current-last<12000 then return false end
    row[medium]=current
    return true
end
local function canAir(medium)
    local s,c=state(),clock()
    if not s or not c then return false end
    if s.night and s.night.day==c.day then return catalog().resolve(s.night[medium])~=nil end
    for id in pairs(s.library) do
        local row=catalog().resolve(id)
        if row and row.medium==medium then return true end
    end
    return false
end
function N.candidate(actor,activity)
    if not activity then return nil end
    local archive=N.isArchive(activity.receiver or activity.object)
    if archive then
        local receiver=activity.receiver or activity.object
        local _,medium=N.isArchive(receiver)
        if activity.kind=="radio_setup" or not receiverReady(receiver,medium) or not N.mayJoin(actor)
            or not canAir(medium) then return nil end
        activity.powerNight=true
        -- An advertised camp evening can beat routine diary/chair choices;
        -- clinical care (75+) and sleep (78) still outrank it in downtime.
        activity.score=math.max((activity.score or 0)+18,60)
        activity.durationMs=3600000
    end
    return activity
end
local function primary(actor)
    return type(getSpecificPlayer)=="function" and getSpecificPlayer(0)==actor
end
receiverReady=function(object,medium)
    local archive,kind=N.isArchive(object)
    local data=call(object,"getDeviceData")
    if not archive or kind~=medium or call(data,"getIsTurnedOn")~=true
        or (tonumber(call(data,"getDeviceVolume")) or 0)<=0
        or call(data,"isPlayingMedia")==true or call(data,"isNoTransmit")==true then return false end
    if call(data,"getIsBatteryPowered")==true then
        return (tonumber(call(data,"getPower")) or 0)>0
    end
    return call(data,"canBePoweredHere")==true
end
local function eligible(actor,object,medium)
    if not actor or call(actor,"isDead")==true or call(actor,"isAsleep")==true then return false end
    if medium=="radio" then
        local deaf=false
        pcall(function() deaf=actor:hasTrait(CharacterTrait.DEAF) end)
        if deaf then return false end
    end
    if not primary(actor) then
        if not N.mayJoin(actor) then return false end
        local ds=SC.Downtime and SC.Downtime.peek(actor)
        local activity=ds and ds.active
        return activity and activity.object==object and activity.startedAt
            and (medium=="tv" and SC.TVWatching.valid(actor,activity,true)
                or medium=="radio" and activity.kind=="radio_listen" and SC.RadioListening.valid(actor,activity,true))
            or false
    end
    local data=call(object,"getDeviceData")
    local equipped=call(actor,"getEquipedRadio")==object
    if equipped then return medium=="radio" and U().owns(actor,object) end
    local a,b=U().square(actor),U().square(object)
    if not a or not b or call(a,"getRoom")~=call(b,"getRoom")
        or not SC.GameplayUtil.sameFloor(actor,object) or SC.GameplayUtil.distance(actor,object)>5 then return false end
    local range=tonumber(call(data,"getDeviceVolumeRange")) or 0
    if SC.GameplayUtil.distance(actor,object)>range then return false end
    if medium=="tv" then return call(object,"isFacing",actor)==true and SC.GameplayUtil.canSee(actor,b) end
    return (tonumber(call(data,"getHeadphoneType")) or -1)<0
end
local function rememberAttendance(actor,p,c)
    local row=person(actor,true)
    if not row then return end
    if row.day~=c.day then row.day,row.minutes,row.rewarded=c.day,0,false end
    local previous=audience[actor]
    -- Only count observed consecutive minutes. A load, a missing callback or a
    -- time skip cannot manufacture attendance.
    if previous and previous.day==c.day and c.hours>previous.hours
        and c.hours-previous.hours<=2/60 then
        row.minutes=math.min(60,(tonumber(row.minutes) or 0)+(c.hours-previous.hours)*60)
    end
    audience[actor]={day=c.day,hours=c.hours,object=p.object}
    if row.minutes>=15 then
        row.topic={id=p.programme,title=p.title,at=c.hours,partial=not (p.coverage and p.coverage[actor])}
        if not row.rewarded then
            row.rewarded=true
            if primary(actor) then
                local stats=call(actor,"getStats")
                if CharacterStat then call(stats,"add",CharacterStat.BOREDOM,-10) call(stats,"add",CharacterStat.UNHAPPINESS,-5) end
            elseif SC.Community then
                SC.Community.addThought(actor,{key="power_night",kind="power_night",
                    text="An evening with familiar voices. For a while, life felt ordinary.",
                    morale=5,stress=-3,at=c.hours*3600000,expiresAt=(c.hours+12)*3600000})
            end
        end
    end
end
function N.onDeviceText(guid,codes,x,y,z,text,object)
    local p=inflight
    if codes~=N.MARKER or not p or object~=p.object or text~=p.line.text or guid~=nil
        or not N.active() or not receiverReady(object,p.medium) then return end
    received[object]=p
    local listeners={}
    local player=type(getSpecificPlayer)=="function" and getSpecificPlayer(0)
    if player then listeners[#listeners+1]=player end
    for _,actor in ipairs(SC.Registry and SC.Registry.living() or {}) do
        if actor~=player then listeners[#listeners+1]=actor end
    end
    for _,actor in ipairs(listeners) do
        if eligible(actor,object,p.medium) then
            p.heard=p.heard or setmetatable({}, {__mode="k"})
            p.heard[actor]=true
            local receipt=person(actor,true)
            if receipt then
                if receipt.coverageDay~=p.day then receipt.coverageDay,receipt.coverage=p.day,{} end
                local coverage=receipt.coverage[p.programme] or {}
                receipt.coverage[p.programme]=coverage
                if p.index>0 and p.index<=p.count then coverage[tostring(p.index)]=true end
                p.coverage=p.coverage or setmetatable({}, {__mode="k"})
                local count=0 for _ in pairs(coverage) do count=count+1 end
                p.coverage[actor]=count>=p.count
            end
            if p.line.codes~="" and p.line.guid then
                N.restoreKnowledge(actor)
                if primary(actor) then
                    if ISRadioInteractions and ISRadioInteractions.getInstance then
                        ISRadioInteractions:getInstance().checkPlayer(actor,p.line.guid,p.line.codes,x,y,z,text,object)
                        if call(actor,"isKnownMediaLine",p.line.guid)==true then N.noteLesson(actor,p.line.guid) end
                    end
                elseif SC.TVWatching.learn then SC.TVWatching.learn(actor,p.line.guid,p.line.codes) end
            end
            if not primary(actor) and SC.Dialogue and SC.Banter and SC.Banter.incidentalBudgetAllows(U().now()) then
                local row=person(actor,true)
                if row and (tonumber(row.lastCommentDay)~=p.day or (tonumber(row.comments) or 0)<2)
                    and (U().now()<(tonumber(row.lastCommentAt) or -math.huge)
                        or U().now()-(tonumber(row.lastCommentAt) or -math.huge)>45000) then
                    if row.lastCommentDay~=p.day then row.comments=0 end
                    local said=SC.Dialogue.say(actor,"power_night.comment",nil,{p.title},{salt=p.programme..":"..p.index})
                    if said then row.lastCommentDay,row.comments,row.lastCommentAt=p.day,(row.comments or 0)+1,U().now() SC.Banter.spendBudget(U().now()) end
                end
            end
        end
    end
end
local function programmeLine(row,elapsed)
    -- Two game minutes each for the introduction and closing; original lines
    -- share the middle 56 minutes. Absolute offsets survive outages and loads.
    if elapsed<2 then return 0,{text="EMMA: Good evening. From the archive: "..row.title..".",codes="",r=.7,g=.9,b=.85} end
    if elapsed>=58 then return row.count+1,{text="EMMA: That was "..row.title..". Same time tomorrow, while the lights hold.",codes="",r=.7,g=.9,b=.85} end
    local index=math.min(row.count,math.floor((elapsed-2)/56*row.count)+1)
    return index,catalog().line(row,index)
end
function N.pulse()
    local s,c=state(),clock()
    if not s or not c or not s.discovered then return end
    if not channels.tv then register("tv",s) end
    if not channels.radio then register("radio",s) end
    if not N.active() then received,audience=setmetatable({}, {__mode="k"}),setmetatable({}, {__mode="k"}) lastMinute=nil return end
    local night=lineup(s,c)
    local api=type(getZomboidRadio)=="function" and getZomboidRadio()
    local devices=U().list(call(api,"getDevices"),512)
    local player=type(getSpecificPlayer)=="function" and getSpecificPlayer(0)
    local radio=call(player,"getEquipedRadio")
    if radio then devices[#devices+1]=radio end
    local seen={}
    local attending={}
    for _,object in ipairs(devices) do if not seen[object] then
        seen[object]=true
        local archive,medium=N.isArchive(object)
        local row=archive and channels[medium] and catalog().resolve(night[medium])
        if row and receiverReady(object,medium) then
            local index,line=programmeLine(row,(c.tod-20)*60)
            local old=received[object]
            if line and line.text and (not old or old.day~=c.day or old.programme~=row.id or old.index~=index) then
                local p={object=object,medium=medium,programme=row.id,title=row.title,count=row.count,
                    index=index,line=line,day=c.day}
                inflight=p
                -- Native per-receiver delivery avoids the game's early return
                -- when an unrelated receiver is playing recorded media.
                local okay,err=pcall(function() object:AddDeviceText(line.text,line.r,line.g,line.b,nil,N.MARKER,-1) end)
                inflight=nil
                if not okay and SC.Diagnostics then SC.Diagnostics.report("power-night",nil,"receiver delivery failed",tostring(err)) end
                old=received[object]
            end
            if c.minute~=lastMinute and old and old.day==c.day then
                for actor in pairs(old.heard or {}) do
                    if eligible(actor,object,medium) then
                        attending[actor]=true
                        rememberAttendance(actor,old,c)
                    end
                end
            end
        end
    end end
    if c.minute~=lastMinute then
        -- A receiver going silent must break continuity even when no native
        -- text callback arrives. Another audible receiver may keep it alive.
        for actor in pairs(audience) do if not attending[actor] then audience[actor]=nil end end
    end
    lastMinute=c.minute
end
function N.topic(actor)
    local row=person(actor,false)
    local c=clock()
    return row and row.topic and c and c.hours>=row.topic.at and c.hours-row.topic.at<=24 and row.topic or nil
end
function N.talk(actor)
    local topic=N.topic(actor)
    if not topic then return "I haven't caught enough of a programme lately to talk about it." end
    local commands=SC.Commands and SC.Commands.peek(actor) or {}
    local voice=commands.personalityProfile and commands.personalityProfile.archetype or commands.personality
    local lines={brave="A little normal life. I'll take it.",cautious="I kept an ear on the door. Still, it was good to sit down.",
        caring="Hearing familiar voices helped. I hope it helped you too.",practical="Useful to have something besides work to think about."}
    return "About "..topic.title..": "..(lines[voice] or lines.practical)
        ..(topic.partial and " I didn't catch the whole thing." or "")
end
function N.snapshot()
    local s,c=state(),clock()
    if not s then return {available=false,reason="Power Night requires a supported single-player world."} end
    local rows={}
    for id in pairs(s.library) do local row=catalog().resolve(id) rows[#rows+1]={id=id,title=row and row.title or id.." (unavailable)",medium=row and row.medium,available=row~=nil} end
    table.sort(rows,function(a,b) return a.title<b.title end)
    local night=s.night and c and s.night.day==c.day and s.night
    return {available=true,discovered=s.discovered,enabled=s.enabled,grid=N.gridOn(),active=N.active(),
        tv=s.frequencies.tv,radio=s.frequencies.radio,library=rows,night=night}
end
function N.install()
    if N._hook then return true end
    if not Events or not Events.OnDeviceText then return false,"device_text_event_unavailable" end
    N._hook=function(...) N.onDeviceText(...) end
    Events.OnDeviceText.Add(N._hook)
    if SC.Dialogue then SC.Dialogue.register("power_night.comment",{common={"I remember this one. %1.","For a minute, that almost felt normal."},
        brave={"Still got an evening left in us."},cautious={"Keep the volume sensible. I want to hear the door."},
        caring={"It's good to hear people laughing again."},practical={"A break won't hurt. We've earned one."}}) end
    return true
end
function N.reset()
    -- Clear Lua userdata only. Owned channels belong to the native radio world;
    -- rebind them by GUID after a load, never remove someone else's frequency.
    store,channels,inflight,lastMinute=nil,{},nil,nil
    surveys=setmetatable({}, {__mode="k"})
    received,audience=setmetatable({}, {__mode="k"}),setmetatable({}, {__mode="k"})
end
function N.remove()
    if N._hook and Events and Events.OnDeviceText then Events.OnDeviceText.Remove(N._hook) end
    N._hook=nil N.reset()
end
function N.isInstalled() return N._hook~=nil end
return N
