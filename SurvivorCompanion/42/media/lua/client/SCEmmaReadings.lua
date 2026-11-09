-- SPDX-License-Identifier: MIT
-- Read-only answers. Native facts are cached for one question, never in memory.
require "SCEmmaReadingsData"
require "SCEmmaBody"
require "SCEmmaCalendar"
local SC=SurvivorCompanion
local R={} SC.EmmaReadings=R
R.intents={me_status=true,me_infected=true,me_need=true,me_look=true,me_kills=true,
    me_survived=true,me_where=true,me_skills=true,me_file=true,helicopter=true,water_off=true,
    power_off=true,forecast=true,daylight=true,calendar=true}
local eventFields={water_off="water",power_off="power",helicopter="helicopter"}
local function quiet(session) return SC.EmmaCare and SC.EmmaCare.quiet(session) end
local function read(turn,world,key,query)
    turn.cache=turn.cache or {}
    local id=key..":"..tostring(query or "")
    if turn.cache[id]~=nil then return turn.cache[id] or nil end
    local fn=world and world[key]
    local okay,value=false,nil
    if type(fn)=="function" then okay,value=pcall(fn,query,turn.slots) end
    value=okay and type(value)=="table" and value or false
    turn.cache[id]=value
    return value or nil
end
local function append(reply,line)
    if type(line)=="string" and line~="" then reply.lines[#reply.lines+1]=line end
end
local function pool(session,reply,id,fields)
    local picked=SC.TerminalBrain.pick(session,id)
    if type(picked)=="string" then append(reply,SC.TerminalBrain.fill(picked,fields or {})) end
end
local function duration(hours)
    return SC.TerminalBrain.duration(math.max(0,hours))
end
local function row(session)
    if not session.emmaMind or not SC.EmmaMind then return nil end
    local state,operator=SC.EmmaMind.refresh(session)
    if state then return operator,state end
end
local function domain(session,key)
    local _,state=row(session)
    return state and (state.domains[key] or 0)>0
end
function R.hasDomain(session,key) return domain(session,key)==true end
local function fields(session)
    return {name=type(session.operator)=="string" and session.operator~="" and session.operator or "operator"}
end
local needWords={hungry={"hungry","hunger","eat","food"},thirsty={"thirsty","thirst","drink","water"},
    tired={"tired","sleep","fatigue"},winded={"exhausted","endurance","breath","stamina"},drunk={"drunk","alcohol"},
    cold={"cold","freezing"},hot={"hot","overheating"},pain={"pain","hurts"},stress={"stressed","stress"},
    panic={"panic","afraid"},unhappy={"unhappy","sad"},heavy={"carrying","load"},wet={"wet","soaked"}}
local function has(text,values)
    text=" "..text.." "
    for _,value in ipairs(values) do if text:find(" "..value.." ",1,true) then return true end end
    return false
end
function R.slots(intent,text,match)
    local function includes(values)
        if not match then return has(text,values) end
        for _,value in ipairs(values) do if match(value) then return true end end
        return false
    end
    local slots={}
    if intent=="me_infected" then slots.estimate=includes({"how long","time left","until i turn"})
    elseif intent=="me_need" then
        for _,kind in ipairs({"hungry","thirsty","tired","winded","drunk","cold","hot","pain","stress","panic","unhappy","heavy","wet"}) do
            if includes(needWords[kind]) then slots.need=kind;break end
        end
    elseif intent=="daylight" then slots.dawn=includes({"dawn","sunrise","morning","sun come up","sun rise","sun rises"})
    elseif intent=="forecast" then
        local day=text:match("in (%d+) days?") or text:match("day (%d+)") or text:match("(%d+) days? from now")
        slots.day=day and tonumber(day) or includes({"today","tonight"}) and 0 or 1
        if includes({"day after tomorrow"}) then slots.day=2 end
        if includes({"week","month","next monday","next tuesday","next wednesday","next thursday","next friday","next saturday","next sunday"}) then slots.day=7 end
        if includes({"next","coming","when"}) then
            for _,kind in ipairs({"storm","snow","fog","frost"}) do
                if includes({kind,kind=="frost" and "freezing" or kind}) then slots.weather=kind;break end
            end
        end
    end
    return slots
end
function R.followup(session,text,match)
    local topic=SC.TerminalConversation.latest(session)
    local subject=topic and topic.reading
    if not subject then return nil end
    if subject=="body" then
        if text=="how long" or has(text,{"time do i have left","how much time"}) then return "me_infected",{estimate=true} end
        if has(text,{"is it infected","did it take","will that turn me"}) then return "me_infected",{} end
        if has(text,{"what do i need","what should i do","what now","how do i treat it","how can i treat it"}) then return "me_status",{treatment=true} end
        if has(text,{"what about my","and my"}) then return "me_need",R.slots("me_need",text,match) end
    elseif subject=="helicopter" then
        if text=="when" or text=="what time" or text=="is it here yet" or text=="is it still coming" then return "helicopter",{} end
        if has(text,{"what should i do","what do i do","is it rescue","will it land"}) then return "helicopter",{advice=true} end
    elseif subject=="water_off" or subject=="power_off" then
        if text=="when" or text=="how long" or text=="what day" or text=="how much longer" or text=="has it happened" then return subject,{} end
        if has(text,{"what should i do","how do i prepare","what do i need"}) then return subject,{advice=true} end
    elseif subject=="forecast" then
        if text=="tomorrow" or text=="tonight" or text=="today" or text=="and tomorrow"
            or text=="what about tomorrow" or text=="and tonight" or text=="what about tonight" then
            return "forecast",R.slots("forecast",text,match)
        end
        if has(text,{"how cold","how hot","what temperature"}) then return "forecast",{day=topic.readingDay or 1} end
    elseif subject=="daylight" and (text=="and dawn" or text=="and dusk" or text=="what about morning") then
        return "daylight",R.slots("daylight",text,match)
    end
end
local function unavailable(reply,what)
    append(reply,"I cannot verify "..what.." from the current readings. I will not substitute an old answer.")
end
local function episode(body)
    return body.infectionTime and "t:"..tostring(body.infectionTime) or "unknown"
end
local function reconcile(session,body)
    local operator=row(session)
    if operator and body.infected==false then operator.infectTold,operator.infectTimeTold=nil,nil
    elseif operator and body.infected==true and episode(body)~="unknown" then
        -- The native timestamp may become available after the first warning.
        -- Qualify that provisional receipt without announcing the same infection again.
        for _,key in ipairs({"infectTold","infectTimeTold"}) do
            if operator[key]=="unknown" then operator[key]=episode(body) end
        end
    end
    return operator
end
local function infected(session,reply,body,turn,world)
    reply.sensitive=true
    if body.infected==nil then unavailable(reply,"your Knox infection status");return end
    if quiet(session) then
        append(reply,body.infected and "Your current readings show Knox infection." or "Your current readings do not show Knox infection.")
    else pool(session,reply,body.infected and "me_infected" or body.fake and "me_fake" or "me_clean",fields(session)) end
    if not body.infected or not turn.slots.estimate then return end
    if quiet(session) then append(reply,"I will not give a countdown during this conversation. Let us focus on looking after you.");return end
    if body.mortality==7 then append(reply,"There is no infection-mortality deadline in the current records. I cannot give you a death estimate.");return end
    if not body.mortality then unavailable(reply,"the current infection-mortality rule");return end
    local started,total,now=body.infectionTime,body.infectionDuration,body.hoursSurvived
    if not started or not total or total<=0 or not now or started>now then unavailable(reply,"an infection time estimate");return end
    local operator=reconcile(session,body)
    if operator and operator.infectTimeTold==episode(body) then
        append(reply,"I have already given the estimate for this infection. It was approximate, not a promise.");return
    end
    local remaining=started+total-now
    if remaining<=0 then append(reply,"The recorded infection has reached its expected endpoint. I cannot give you a reliable countdown.");return end
    local clock=read(turn,world,"calendarClock")
    if not clock or clock.hour==nil then unavailable(reply,"the date of that estimate");return end
    local hour=clock.hour+remaining
    local date=SC.EmmaCalendar.date(clock,math.floor(hour/24))
    if not date then unavailable(reply,"the date of that estimate");return end
    append(reply,"By the current reading: around "..date.." at "..SC.EmmaCalendar.time(hour)..", about "..duration(remaining).." away. This is an estimate, not a promise.")
    if operator then operator.infectTimeTold=episode(body) end
end
local function woundLine(session,reply,wound,plain)
    local kind=wound.bleeding and not wound.bandaged and "bleeding" or wound.deep and "deep" or wound.fracture and "fracture"
        or (wound.glass or wound.bullet) and "lodged" or wound.burn and "burn" or wound.festering and "festering"
        or wound.bandaged and wound.dirty and "dirty" or wound.bite and "bite" or wound.cut and "cut" or "scratch"
    if plain then append(reply,wound.part..": "..kind..(wound.bandaged and ", bandaged." or "."))
    else pool(session,reply,"me_"..kind,{part=wound.part}) end
end
local function needLine(session,reply,need,plain)
    if plain or need.kind=="bleeding" or need.kind=="zombie" then
        append(reply,(need.label or need.kind:gsub("_"," ")).." (severity "..need.level.." of 4).")
    else
        local before=#reply.lines
        pool(session,reply,"me_"..need.kind,fields(session))
        if #reply.lines==before then append(reply,need.label or need.kind) end
    end
end
local function bodyAnswer(intent,session,reply,turn,world)
    reply.category,reply.sensitive,reply.reading="body",true,"body"
    if not domain(session,"body") then
        if quiet(session) then append(reply,"The medical index is not recovered yet. A clinic, pharmacy or research computer can provide it.")
        else pool(session,reply,intent=="news_bitten" and "news_bitten_blind" or intent=="news_hurt" and "news_hurt_blind" or "teaser_body") end
        return
    end
    local mode=intent=="me_infected" and "infection" or intent=="me_need" and "need" or "status"
    local body=read(turn,world,"body",mode)
    if not body then unavailable(reply,"your own condition");return end
    reconcile(session,body)
    if intent=="me_infected" then infected(session,reply,body,turn,world);return end
    local plain=quiet(session)
    if intent=="me_need" and turn.slots.need then
        local target
        for _,need in ipairs(body.needs or {}) do
            if need.kind==turn.slots.need or turn.slots.need=="cold" and need.kind=="windchill" then target=need;break end
        end
        if target then needLine(session,reply,target,plain)
        elseif body.needsComplete then append(reply,"No current "..turn.slots.need:gsub("_"," ").." warning in your needs readings.")
        else unavailable(reply,"that needs reading") end
        return
    end
    if body.infected then infected(session,reply,body,turn,world) end
    local seen={}
    for _,wound in ipairs(body.wounds or {}) do
        if #reply.lines>=3 then break end
        woundLine(session,reply,wound,plain);seen[wound.bleeding and "bleeding" or "injured"]=true
    end
    if body.fake and body.infected==false and #reply.lines<3 then
        if plain then append(reply,"The readings show false-infection symptoms, without a confirmed Knox infection.")
        else pool(session,reply,"me_fake",fields(session)) end
    end
    for _,need in ipairs(body.needs or {}) do
        if #reply.lines>=3 then break end
        if need.kind=="sick" or need.kind=="drunk" then needLine(session,reply,need,plain);seen[need.kind]=true end
    end
    for _,need in ipairs(body.needs or {}) do
        if #reply.lines>=3 then break end
        if not seen[need.kind] and need.kind~="zombie" then needLine(session,reply,need,plain);seen[need.kind]=true end
    end
    if #reply.lines==0 then
        if body.health and body.health<99 then append(reply,"Your overall health is "..math.floor(body.health+.5).."%. It has not fully recovered.")
        elseif body.infected==false and body.needsComplete and (mode=="need" or body.woundsComplete) then
            if mode=="need" then append(reply,"No current needs warning in the available readings.")
            elseif plain then append(reply,"No current wound or needs warning in the available readings.") else pool(session,reply,"me_fine",fields(session)) end
        else unavailable(reply,"a complete health assessment") end
    end
    if body.infected==nil then append(reply,"The Knox infection reading is unavailable; other readings do not prove that you are clear.") end
    if turn.slots.treatment then append(reply,"Ask how to treat a deep wound, remove glass, support a fracture or clean a wound for the relevant county reference.") end
end
local function fileAnswer(intent,session,reply,turn,world)
    reply.category="body"
    local file=read(turn,world,"self",intent)
    if not file then unavailable(reply,"your operator file");return end
    local f=fields(session)
    if intent=="me_kills" then
        if file.kills==nil then unavailable(reply,"your kill count");return end
        f.kills=math.floor(file.kills)
        if quiet(session) then append(reply,"Recorded zombie kills: "..f.kills..".")
        else pool(session,reply,f.kills==0 and "me_kills_none" or "me_kills",f) end
    elseif intent=="me_survived" or intent=="me_look" then
        if file.hours==nil then unavailable(reply,"your time survived");return end
        f.days=duration(file.hours)
        if quiet(session) then append(reply,"Time survived: "..f.days..".") else pool(session,reply,intent,f) end
    elseif intent=="me_where" then
        if not file.place then unavailable(reply,"your current location");return end
        if quiet(session) then append(reply,"Current location: "..file.place..".") else f.place=file.place;pool(session,reply,"me_where",f) end
    elseif intent=="me_skills" then
        local skills={}
        for _,skill in ipairs(file.skills or {}) do skills[#skills+1]=skill.name.." "..skill.level end
        if #skills==0 then append(reply,file.skillsComplete and "No trained skill levels in this reading." or "The skill record is incomplete.")
        elseif quiet(session) or not file.skillsComplete then append(reply,"Recorded skills: "..table.concat(skills,", ")..".")
        else f.skills=table.concat(skills,", ");pool(session,reply,"me_skills",f) end
    else
        append(reply,"Operator file: "..(file.name and file.name:match("%S") and file.name or f.name)..".")
        if file.hours then append(reply,"Time survived: "..duration(file.hours)..".") end
        if file.kills then append(reply,"Recorded zombie kills: "..math.floor(file.kills)..".") end
        if file.place then append(reply,"Location: "..file.place..".") end
        if #(file.traits or {})>0 then append(reply,"Recorded traits: "..table.concat(file.traits,", ")..".") end
    end
end
local function eventDate(clock,left)
    if not clock or clock.hour==nil or left==nil then return nil end
    return SC.EmmaCalendar.date(clock,math.floor((clock.hour+left)/24))
end
local function weatherAnswer(session,reply,turn,world)
    local requested=turn.slots.day or 1
    if requested<0 or requested>6 then append(reply,"I can read today and the next six days. Beyond that, I would be guessing.");return end
    local snapshot=read(turn,world,"calendar","forecast")
    if not snapshot then unavailable(reply,"the forecast");return end
    local weather=snapshot.forecast
    if not weather then
        if turn.slots.weather and snapshot.complete then append(reply,"No "..turn.slots.weather.." in the next seven days of forecast records. That is the limit of this reading.")
        else unavailable(reply,"a complete forecast for that period") end
        return
    end
    if weather.complete~=true then unavailable(reply,"a complete forecast for that period");return end
    local day=SC.EmmaCalendar.date(snapshot.clock,weather.offset)
    if not day then unavailable(reply,"the forecast date");return end
    local when=weather.offset==0 and "today" or weather.offset==1 and "tomorrow" or "on "..day
    if turn.slots.weather then
        if quiet(session) then append(reply,turn.slots.weather.." conditions are forecast "..when..".")
        else pool(session,reply,"forecast_"..(turn.slots.weather=="frost" and "cold" or turn.slots.weather),{when=when}) end
        if snapshot.complete~=true then append(reply,"Earlier forecast records are incomplete. An earlier occurrence is possible.") end
    elseif weather.temperature then
        local temperature=math.floor(weather.temperature+.5)
        if quiet(session) then append(reply,"Forecast for "..day..": "..weather.sky..", about "..temperature.." C.")
        else pool(session,reply,"forecast",{day=day,sky=weather.sky,tempC=temperature,tempF=math.floor(weather.temperature*1.8+32+.5)}) end
    else append(reply,"Forecast for "..day..": "..weather.sky..". The temperature reading is unavailable.") end
    reply.readingDay=weather.offset
end
local function eventAnswer(kind,session,reply,snapshot,advice)
    local clock=snapshot.clock
    if kind=="helicopter" then
        local heli=snapshot.helicopter
        if not heli then unavailable(reply,"the helicopter schedule");return end
        if advice then append(reply,"It is not a rescue. Stay indoors, away from windows, and avoid drawing it to your camp.");return end
        local dated=heli.state=="before" or heli.state=="soon" or heli.state=="after"
        local day=dated and heli.offset and SC.EmmaCalendar.date(clock,heli.offset)
        if dated and not day then unavailable(reply,"the helicopter date");return end
        if quiet(session) then
            if heli.state=="none" then append(reply,"No helicopter is currently scheduled.")
            elseif heli.state=="active" then append(reply,"The helicopter is currently active. Stay indoors.")
            elseif heli.state=="window" then append(reply,"The possible flight window is open. I cannot confirm that an aircraft is overhead.")
            else append(reply,(heli.state=="after" and "Recorded flight window: " or "Possible flight window: ")
                ..day..", "..SC.EmmaCalendar.time(heli.start).." to "..SC.EmmaCalendar.time(heli.finish)..".") end
        else
            local key=heli.state=="none" and "heli_none" or heli.state=="active" and "heli_now"
                or heli.state=="window" and "heli_window" or "heli_"..heli.state
            pool(session,reply,key,{day=day,start=SC.EmmaCalendar.time(heli.start),finish=SC.EmmaCalendar.time(heli.finish)})
        end
        if heli.repeatable and heli.state=="after" then append(reply,"Further flights are possible, but no later date is confirmed in this record.") end
        return
    end
    local event=snapshot[eventFields[kind]]
    if not event then unavailable(reply,kind=="water_off" and "the water schedule" or "the power schedule");return end
    local name=kind=="water_off" and "water" or "power"
    if advice then
        append(reply,name=="water" and "Fill clean containers while the taps run. Afterward, collect water and purify it before drinking."
            or "Prepare a safe outside generator or battery supply. Use fresh food before refrigeration is lost.");return
    end
    local stage=event.never and "never" or event.restored and "restored" or event.left<=0 and "after" or event.left<=24 and "soon" or "before"
    local day=not event.never and eventDate(clock,event.left)
    if not event.never and not day then unavailable(reply,"the "..name.." shutoff date");return end
    if quiet(session) then append(reply,event.never and "No "..name.." shutoff is scheduled."
        or name.." schedule: "..stage.."; recorded date "..day..".")
    else pool(session,reply,name.."_"..stage,{day=day,days=duration(event.left)}) end
    if event.restored and event.remainingHours then append(reply,"Current restored-grid window: about "..duration(event.remainingHours).." remaining.") end
end
local function calendarAnswer(intent,session,reply,turn,world)
    reply.category,reply.reading="calendar",intent
    if intent=="daylight" then
        local daylight=read(turn,world,"daylight")
        if not daylight then unavailable(reply,"dawn and dusk");return end
        local target=turn.slots.dawn and daylight.dawn or daylight.dusk
        local left=target-daylight.hour
        if left<=0 then left=left+24 end
        local day=target<=daylight.hour and "tomorrow" or "today"
        if quiet(session) then append(reply,(turn.slots.dawn and "Dawn" or "Dusk")..": "..day.." at "..SC.EmmaCalendar.time(target)..".")
        else pool(session,reply,turn.slots.dawn and "daylight_dawn" or "daylight_dusk",{day=day,time=SC.EmmaCalendar.time(target),hours=duration(left)}) end
        return
    end
    if not domain(session,"calendar") then
        if quiet(session) then append(reply,"The county calendar index is not recovered yet. An official computer, or twelve ordinary machines, can recover it.")
        else pool(session,reply,"teaser_calendar") end
        return
    end
    if intent=="forecast" then weatherAnswer(session,reply,turn,world);return end
    local snapshot=read(turn,world,"calendar",intent)
    if not snapshot then unavailable(reply,"the county calendar");return end
    if intent=="calendar" then
        if not quiet(session) then pool(session,reply,"calendar_lead") end
        local events,missing={},{}
        for _,kind in ipairs({"water_off","power_off","helicopter"}) do
            local event=snapshot[eventFields[kind]]
            if not event then missing[#missing+1]=kind end
            if event and not event.never and event.state~="none" and event.left and event.left>=0 then events[#events+1]={kind=kind,left=event.left} end
        end
        table.sort(events,function(a,b) return a.left<b.left end)
        if #events==0 then append(reply,"No upcoming dated event in the available schedule. Individual records may include past shutoffs or an active restored supply.")
        else for _,event in ipairs(events) do eventAnswer(event.kind,session,reply,snapshot) end end
        for _,kind in ipairs(missing) do unavailable(reply,"the "..eventFields[kind].." schedule") end
    else eventAnswer(intent,session,reply,snapshot,turn.slots.advice) end
end
function R.boot(session,world)
    if quiet(session) or not domain(session,"body") then return nil end
    local turn={cache={},slots={}}
    local body=read(turn,world,"body","infection")
    if not body then return nil end
    local operator=reconcile(session,body)
    if not operator or not body.infected or operator.infectTold==episode(body) then return nil end
    operator.infectTold=episode(body)
    local reply={lines={}}
    pool(session,reply,"boot_infected_lead",fields(session))
    pool(session,reply,"me_infected",fields(session))
    return reply.lines
end
function R.install()
    if R.installed then return end
    R.installed=true
    for intent in pairs(R.intents) do
        local id=intent
        SC.TerminalBrain.registerHandler(id,function(session,reply,turn,world)
            if id=="me_status" or id=="me_need" or id=="me_infected" then bodyAnswer(id,session,reply,turn,world)
            elseif id:find("^me_") then fileAnswer(id,session,reply,turn,world)
            else calendarAnswer(id,session,reply,turn,world) end
        end)
    end
    for _,intent in ipairs({"news_bitten","news_hurt"}) do
        local id=intent
        SC.TerminalBrain.registerHandler(id,function(session,reply,turn,world) bodyAnswer(id,session,reply,turn,world) end)
    end
end
return R
