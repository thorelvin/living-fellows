-- SPDX-License-Identifier: MIT
-- Real pools and selectors; deterministic world/actor facts, no native work.
local SC = SurvivorCompanion
local D, B, A, R, P = SC.Dialogue, SC.BaseLife, SC.BaseAlert, SC.Relationship, SC.Production
local checks = 0
local function check(value, message)
    checks = checks + 1
    if not value then error("VOICE_DEPTH " .. tostring(message)) end
end
local topics = {
    "camp_alert.contact",
    "camp_alert.stand_to",
    "camp_alert.fall_back",
    "camp_alert.relay",
    "camp_alert.woken",
    "camp_alert.shake",
    "camp_alert.coming",
    "camp_alert.clear",
    "camp_alert.night.contact",
    "camp_alert.night.stand_to",
    "camp_alert.blind",
    "camp_alert.again",
    "camp_alert.clear.passed",
    "camp_alert.clear.fought",
    "camp_alert.hurt",
    "status.water",
    "status.food",
    "status.safety",
    "status.bandages",
    "status.ammunition",
    "status.medical",
    "status.shaken",
    "status.ready",
    "status.grief",
    "status.knox",
    "opinion.danger",
    "opinion.guard",
    "opinion.scavenge",
    "opinion.general",
    "supply.answer.soon",
    "supply.answer.join",
    "supply.answer.later",
    "supply.answer.cannot",
    "gift.accepted",
    "gift.declined",
    "encourage.recent",
    "encourage.not_needed",
    "praise.none",
    "status.rest",
    "opinion.camp",
    "burial.haul.start",
    "burial.haul.drag",
    "burial.haul.drop",
    "burial.haul.threat",
    "burial.dig.start",
    "burial.dig.done",
    "burial.lower",
    "burial.fallen",
    "burial.amen",
    "burn.ignite",
    "burn.watch",
    "burn.rain",
    "burn.prayer",
    "burn.gallows",
    "burn.fire_spread",
    "burial.haul.tally",
    "burial.haul.uniform",
    "burial.haul.dressed",
    "burn.night",
    "burial.dig.rain",
    "study.outfit.law",
    "study.outfit.medic",
    "study.outfit.patient",
    "study.outfit.military",
    "study.outfit.fire",
    "study.outfit.hazmat",
    "study.outfit.food",
    "study.outfit.farm",
    "study.outfit.office",
    "study.outfit.student",
    "study.outfit.sports",
    "study.outfit.jockey",
    "study.outfit.wedding",
    "study.outfit.inmate",
    "study.outfit.clergy",
    "study.outfit.home",
    "study.outfit.worker",
    "study.outfit.party",
    "study.outfit.santa",
    "study.outfit.reporter",
    "study.outfit.traveler",
    "study.outfit.raider",
    "study.outfit.survivor",
    "study.profession.doctor",
    "study.profession.nurse",
    "study.profession.policeofficer",
    "study.profession.veteran",
    "study.profession.parkranger",
    "study.profession.fireofficer",
    "study.profession.chef",
    "study.profession.farmer",
    "study.profession.mechanics",
    "study.profession.burglar",
    "study.profession.securityguard",
    "study.again",
    "study.night",
    "study.rain",
}
local roughWords = { "damn", "damned", "dammit", "goddamn", "hell", "shit", "shitty",
    "bullshit", "fuck", "fucking", "fucked", "ass", "asses", "dumbass", "bastard", "bastards", "bitch", "christ" }
local function rough(text)
    for _, word in ipairs(roughWords) do
        if string.find(string.lower(text), "%f[%a]"..word.."%f[%A]") then return true end
    end
    return false
end
local function words(text) local count=0 for _ in string.gmatch(text,"%S+") do count=count+1 end return count end
local inspected=0
for _,topic in ipairs(topics) do
    local pool=D._poolForTests(topic)
    check(type(pool)=="table", "missing planned topic "..topic)
    local seen,cleanSeen={},{}
    local function lint(rows)
        for key,entry in pairs(rows) do
            if type(key)=="number" then
                local raw=type(entry)=="table" and entry[1] or entry
                local clean=type(entry)=="table" and entry.clean or entry
                check(type(raw)=="string" and type(clean)=="string", "malformed or missing clean twin "..topic)
                check(not rough(clean),"rough clean twin "..topic..": "..clean)
                check(not seen[raw] and not cleanSeen[clean],"duplicate line "..topic..": "..raw)
                seen[raw],cleanSeen[clean]=true,true
                local fills={{"Ann","one"},{"Mary Anne Carter","one"},{"someone from our group","one"}}
                if string.find(topic,"^camp_alert%.") and topic~="camp_alert.hurt" then
                    fills={}
                    for _,place in ipairs({"right here","on the north side","on the northeast side","on the east side",
                        "on the southeast side","on the south side","on the southwest side","on the west side","on the northwest side"}) do
                        for _,count in ipairs({"one","two","three or four","a handful","a whole crowd"}) do fills[#fills+1]={place,count} end
                    end
                elseif topic=="burial.haul.tally" then fills={{"five"},{"ten"},{"fifteen"},{"twenty"},{"thirty"},{"forty"},{"fifty"}}
                elseif topic=="study.again" then
                    fills={} for _,phrase in pairs(SC.Downtime._studyForTests().OUTFIT_PHRASES) do fills[#fills+1]={phrase} end
                end
                for _,text in ipairs({raw,clean}) do
                    check(not string.find(text,"[^\032-\126]") and words(text)<=18,"ASCII/word cap "..topic..": "..text)
                    for _,fill in ipairs(fills) do
                        local rendered=D._interpolateForTests(text,fill)
                        check(rendered and not string.find(rendered,"%%[0-9]") and not string.find(rendered,"  ",1,true),
                            "render "..topic..": "..text)
                        check(words(rendered)<=18,"rendered word cap "..topic..": "..rendered)
                    end
                end
                inspected=inspected+1
            elseif type(entry)=="table" then lint(entry) end
        end
    end
    lint(pool)
    for _,voice in ipairs({"brave","cautious","caring","practical"}) do
        for _,mood in ipairs({"steady","hopeful","stressed","low","uneasy","shaken","grieving"}) do
            check(D.poolSize(topic,nil,{}, {voice=voice,mood=mood,includeRegisters=false})>=8,
                "depth floor "..topic.."/"..voice.."/"..mood)
        end
    end
end
-- The same world reader drives every new context; unavailable clocks do not
-- create a day or a remembered event.
local world={hour=12,age=60,rain=0,fog=0}
getGameTime=function() return {getTimeOfDay=function() return world.hour end,getWorldAgeHours=function() return world.age end} end
getClimateManager=function() return {getPrecipitationIntensity=function() return world.rain end,getFogIntensity=function() return world.fog end} end
local hour,day,rain,fog,age=D.worldState()
check(hour==12 and day==2 and rain==0 and fog==0 and age==60,"shared native weather/clock read")
local clock=100000
local U=SC.GameplayUtil
local originalConfig=U.config
U.config=function(key)
    if key=="baseAlertClearContactMs" or key=="baseAlertClearMs" then return 20000 end
    return originalConfig(key)
end
U.nowMs=function() return clock end
U.position=function(value) return value and value.x,value and value.y,value and value.z or 0 end
U.idOf=function(actor) return actor and actor.id end
U.nameOf=function(actor) return actor and actor.name or "Resident" end
U.isValidActor=function(actor) return actor~=nil and not actor.invalid end
U.isDead=function(actor) return actor.dead==true end
local actors={}
local function person(id,x)
    local actor={id=id,name=id=="a" and "Ann Carter" or "Bill Clay",x=x,y=0,z=0}
    actor.square={x=x,y=0,z=0,getBuilding=function() return false end}
    actors[id]=actor return actor
end
local a,b=person("a",0),person("b",4)
U.resolveActor=function(id) return actors[id] end
U.squareOf=function(actor) return actor.square end
U.canSee=function(observer) return not observer.occluded end
U.moodleLevel=function() return 0 end
local ok,base=B.create({x=0,y=0,z=0},"Voice Camp")
check(ok==true,"real camp created")
local baseId=base.id
local duty={"a","b"}
B.dutyResidentIds=function() return duty end
B.guardStatus=function() return false end
local residents={a={baseId=baseId},b={baseId=baseId}}
B.resident=function(id) return residents[id] end
SC.Downtime.peek=function(actor) return actor.asleep and {active={kind="rest_bed",sleepStarted=true}} end
SC.Downtime.wakeForAlarm=function(actor) actor.asleep=false return true end
SC.Downtime.alarmOver=function() end
local medical={}
SC.Medical.assessCached=function(actor) return medical[actor] or {woundCount=0,bites=0,bleedingCount=0} end
local supervisorUpdate=SC.ActionSupervisor.update
SC.ActionSupervisor.update=function() error("voice observation must not update action ownership") end
check(SC.ActionSupervisor.peekOwner(a)==nil,"pure action-owner observation")
SC.ActionSupervisor.update=supervisorUpdate
local combatRecords={}
SC.Combat.peek=function(actor) return combatRecords[actor] end
local spoken={}
D.say=function(actor,topic,_,arguments)
    spoken[#spoken+1]={actor=actor,topic=topic,args=arguments}
    actor.lastSpoken=clock return true
end
D.lastSpokenAt=function(actor) return actor.lastSpoken end
local ordinaryHas=D.has
local missing={}
D.has=function(topic) return not missing[topic] and ordinaryHas(topic) end
local commands={recruited=true,order="base_duty"}
local function snapshot(count)
    local result={threats={},immediateCount=0}
    for i=1,count do result.threats[i]={x=base.zones[1].x2+2+i*.1,y=0,z=0,distanceSq=25} end
    return result
end
local function begin(count,keepLast)
    local last=A.lastCleared
    A.reset() if keepLast then A.lastCleared=last end
    spoken={} a.lastSpoken=nil b.lastSpoken=nil
    check(A.observe(a,nil,snapshot(count or 1),commands,clock)==true,"actual alarm raised")
    return spoken[1].topic
end
local function clearAlarm()
    clock=clock+21000 A.pulse(clock)
    check(A.peek()==nil,"alarm clears through actual pulse")
    return spoken[#spoken].topic
end
world.hour=22
check(begin()=="camp_alert.night.contact","night contact")
check(begin(3)=="camp_alert.night.stand_to","night stand-to")
check(begin(9)=="camp_alert.fall_back","context never replaces fall-back")
missing["camp_alert.night.contact"]=true
check(begin()=="camp_alert.contact","missing night falls back to level") missing["camp_alert.night.contact"]=nil
world.hour=12 world.fog=.5
check(begin()=="camp_alert.blind","fog contact")
world.fog=0 world.rain=.7
check(begin()=="camp_alert.blind","heavy rain contact")
check(begin(3)=="camp_alert.stand_to","blind does not replace stand-to")
missing["camp_alert.blind"]=true
check(begin()=="camp_alert.contact","missing blind falls back") missing["camp_alert.blind"]=nil
world.rain=0
begin()
check(clearAlarm()=="camp_alert.clear.passed","all-clear after no combat")
check(A.lastCleared.hour==60 and A.lastCleared.baseId==baseId,"clear stores real camp/game-hour")
world.hour=22 world.fog=.9
check(begin(1,true)=="camp_alert.again","again precedes night and blind")
missing["camp_alert.again"]=true
check(begin(1,true)=="camp_alert.contact","missing again falls back to level") missing["camp_alert.again"]=nil
world.age=61.01 world.hour=12 world.fog=0
check(begin(1,true)=="camp_alert.contact","again expires after a game hour")
combatRecords[b]={lastAcceptedOffenseAt=clock-1}
begin()
check(clearAlarm()=="camp_alert.clear.passed","old combat does not turn a later alarm into a fight")
begin() clock=clock+1 combatRecords[b]={lastAcceptedOffenseAt=clock} A.pulse(clock)
check(clearAlarm()=="camp_alert.clear.fought","accepted offense changes all-clear")
combatRecords[b]=nil
missing["camp_alert.clear.fought"]=true
begin() clock=clock+1100 combatRecords[b]={lastAcceptedOffenseAt=clock} A.pulse(clock)
check(clearAlarm()=="camp_alert.clear","missing fought falls back") missing["camp_alert.clear.fought"]=nil
combatRecords[b]=nil
missing["camp_alert.clear.passed"]=true
begin() check(clearAlarm()=="camp_alert.clear","missing passed falls back") missing["camp_alert.clear.passed"]=nil
begin()
medical[b]={woundCount=1,bites=0,bleedingCount=1}
clock=clock+5000 A.pulse(clock)
check(spoken[#spoken].topic=="camp_alert.hurt" and spoken[#spoken].actor==a
    and spoken[#spoken].args[1]==b.name,"nearby visible buddy reports a newly hurt resident")
local before=#spoken
medical[b].woundCount=2 clock=clock+5000 A.pulse(clock)
check(#spoken==before,"hurt is once per resident per alarm")
medical={} begin()
b.x=30 medical[a]={woundCount=1,bites=1,bleedingCount=1}
clock=clock+5000 A.pulse(clock)
check(#spoken==1,"a distant resident cannot report the wound")
b.x=4 b.occluded=true clock=clock+5000 A.pulse(clock)
check(#spoken==1,"walls hide the wound from the witness")
b.occluded=false b.asleep=true clock=clock+5000 A.pulse(clock)
check(#spoken==1,"sleepers do not witness injuries")
b.asleep=false clock=clock+1100 A.pulse(clock)
check(spoken[#spoken].topic=="camp_alert.hurt" and spoken[#spoken].actor==b,"pending wound waits for a real awake witness")
medical={} begin() A.peek().told.b=nil
medical[b]={woundCount=1,bites=0,bleedingCount=1}
clock=clock+5000 A.pulse(clock)
check(spoken[#spoken].topic=="camp_alert.hurt" and spoken[#spoken].actor==a,
    "a visible wounded resident need not have heard the alarm")
medical={} begin() A.peek().told.b=nil
medical[a]={woundCount=1,bites=0,bleedingCount=1}
clock=clock+5000 A.pulse(clock)
check(spoken[#spoken].topic=="camp_alert.hurt" and spoken[#spoken].actor==b
    and A.peek().told.b==nil,"witnessing a wound does not invent alarm knowledge")
medical={} missing["camp_alert.hurt"]=true begin()
medical[b]={woundCount=1,bites=0,bleedingCount=1}
clock=clock+5000 A.pulse(clock)
check(spoken[#spoken].topic=="camp_alert.contact" and spoken[#spoken].actor==a,
    "missing hurt topic uses the ordinary alarm fallback")
medical={} begin() A.peek().told.b=nil
medical[a]={woundCount=1,bites=0,bleedingCount=1}
clock=clock+5000 A.pulse(clock)
check(#spoken==1,"fallback does not give an uninformed witness threat knowledge")
missing["camp_alert.hurt"]=nil
medical={} A.reset()

-- Real Talk dispatch, including the UI describer's existing fatigue field.
local chosen
D.choose=function(_,topic) chosen=topic return "answer" end
SC.Senses.cached=function() return nil end
local state={recruited=true,order="follow",personality="practical",stress=10}
local description={health=100,hunger=.2,thirst=.2,fatigue=.69,supplies={bandages=2},ammunition=5}
R.respond("status",a,nil,state,description) check(chosen=="status.rest","status admits serious tiredness")
R.respond("needs",a,nil,state,description) check(chosen=="status.rest","needs admits serious tiredness")
description.fatigue=.67 R.respond("needs",a,nil,state,description)
check(chosen~="status.rest","below serious tiredness does not ask for sleep")
description.fatigue=.9 description.thirst=.8 R.respond("needs",a,nil,state,description)
check(chosen=="status.water","water remains above rest priority")
description.thirst=.2 description.hunger=.8 R.respond("needs",a,nil,state,description)
check(chosen=="status.food","food remains above rest priority")
description.hunger=.2 description.woundCount=1 R.respond("needs",a,nil,state,description)
check(chosen=="status.medical","wounds remain above rest priority")
description.woundCount=0 description.fatigue=.2 state.order="base_duty"
R.respond("opinion",a,nil,state,description) check(chosen=="opinion.camp","base-duty resident camp opinion")
state.order="follow" R.respond("opinion",a,nil,state,description)
check(chosen=="opinion.camp","following resident inside camp can discuss camp")
a.x=100 R.respond("opinion",a,nil,state,description)
check(chosen~="opinion.camp","following resident outside camp keeps travel opinion") a.x=0
description.immediateCount=1 R.respond("opinion",a,nil,state,description)
check(chosen=="opinion.danger","danger precedes camp opinion") description.immediateCount=0
SC.Senses.cached=function() return {threatCount=1} end
R.respond("opinion",a,nil,state,description) check(chosen=="opinion.danger","cached visible threats prevent safe-camp opinion")
SC.Senses.cached=function() return {threatCount=0,humanThreat={actor=b,visible=true}} end
R.respond("opinion",a,nil,state,description)
check(chosen=="opinion.danger","cached hostile humans prevent safe-camp opinion")
SC.Senses.cached=function() return {threatCount=0,protectedActors={b}} end
R.respond("opinion",a,nil,state,description)
check(chosen=="opinion.camp","a protected bystander does not become a human threat")
SC.Senses.cached=function() return nil end
local fakeChoose=D.choose
D.choose=function() return nil end
description.fatigue=.69
local fallback=R.respond("needs",a,nil,state,description)
check(string.find(string.lower(fallback),"sleep",1,true)~=nil,"rest retains readable fallback without its pool")
fallback=R.respond("opinion",a,nil,state,description)
check(string.find(fallback,"ours",1,true)~=nil,"camp opinion retains readable fallback without its pool")
D.choose=fakeChoose

local disposal,speak=P._voiceForTests()
local study=SC.Downtime._studyForTests()
check(SC.Downtime.outfitGroup==study.outfitGroup and SC.Downtime.outfitGroup("Police") == "law","hauling shares actual outfit classification")
world.hour=22 world.age=70 world.rain=.3
check(disposal.contextVoice("burn.ignite")=="burn.night","night pyre choice")
check(disposal.contextVoice("burial.dig.start")=="burial.dig.rain","rain grave choice")
check(disposal.contextVoice("burial.haul.start",{outfitGroup="law"})=="burial.haul.uniform","uniform hauling choice")
check(disposal.contextVoice("burial.haul.start",{outfitGroup="wedding"})=="burial.haul.dressed","dressed hauling choice")
world.hour=5 world.rain=.29
check(disposal.contextVoice("burn.ignite")=="burn.ignite" and disposal.contextVoice("burial.dig.start")=="burial.dig.start","day/dry boundaries keep ordinary topics")
check(disposal.contextVoice("burial.haul.start",{outfitGroup="home"})=="burial.haul.start","ordinary clothes keep ordinary hauling")
check(P.reset()==true,"production voice fixture resets ordinary pacing")
local oldHash=U.stableHash
U.stableHash=function() return 0 end
a.lastSpoken,b.lastSpoken=nil,nil clock=clock+120000
local safe={snapshot={threats={}}}
local danger={snapshot={threats={{distanceSq=4}}}}
before=#spoken
check(not speak(a,"burial.haul.uniform",nil,"kit",danger,"burial.haul.start") and #spoken==before,
    "new hauling voice stays quiet near threats")
check(speak(a,"burial.haul.uniform",nil,"kit",safe,"burial.haul.start") and spoken[#spoken].topic=="burial.haul.uniform",
    "context voice uses original admitted speech path")
check(not speak(b,"burial.haul.dressed",nil,"kit",safe,"burial.haul.start"),"context voice keeps party gap")
clock=clock+13000
check(not speak(a,"burial.haul.dressed",nil,"kit",safe,"burial.haul.start"),"context voice keeps actor cooldown")
clock=clock+61000 missing["burial.haul.uniform"]=true
check(speak(a,"burial.haul.uniform",nil,"kit",safe,"burial.haul.start") and spoken[#spoken].topic=="burial.haul.start",
    "unavailable uniform pool falls back through actual speech") missing["burial.haul.uniform"]=nil
for _,row in ipairs({{"burial.haul.dressed","burial.haul.start"},{"burn.night","burn.ignite"},{"burial.dig.rain","burial.dig.start"}}) do
    clock=clock+61000 missing[row[1]]=true
    check(speak(a,row[1],nil,"kit",safe,row[2]) and spoken[#spoken].topic==row[2],"missing context pool falls back "..row[1])
    missing[row[1]]=nil
end
clock=clock+61000 U.stableHash=function() return 99 end
check(not speak(a,"burial.haul.drop",nil,"roll",safe),"ordinary drop retains its chance")
check(speak(a,"burial.haul.tally",{"five"},"roll",safe,"burial.haul.drop"),"milestone has full chance with unchanged cooldowns")
U.stableHash=oldHash
local function corpse(outfit)
    local data={}
    return {getModData=function() return data end,getOutfitName=function() return outfit or "Police" end}
end
local delivered={}
for i=1,10 do
    delivered[i]=corpse()
    local topic,args=disposal.dropVoice(delivered[i])
    local expected=(i==5 or i==10) and "burial.haul.tally" or "burial.haul.drop"
    check(topic==expected,"haul tally milestone "..i)
    if i==5 or i==10 then check(args[1]==(i==5 and "five" or "ten"),"tally number is spoken as a word") end
end
check(B.voiceDay(2).hauls==10,"daily tally includes quiet drops")
check(disposal.dropVoice(delivered[5])=="burial.haul.drop" and B.voiceDay(2).hauls==10,"same physical body cannot inflate a tally")
local saved=B.export()
check(B.restore(saved)==true and B.voiceDay(2).hauls==10,"daily tally survives real camp export/restore")
local twoCamps=B.export()
local second=B.export().bases[baseId]
second.id,second.voiceDay="base:voice-second",nil
for index,zone in ipairs(second.zones) do zone.id="zone:voice-second:"..index end
twoCamps.bases[second.id],twoCamps.activeBaseId=second,second.id
check(B.restore(twoCamps)==true and B.voiceDay(2).hauls==0,"another camp starts its own daily count")
disposal.dropVoice(delivered[5])
check(B.voiceDay(2).hauls==1,"the same body is counted separately at another camp")
twoCamps=B.export() twoCamps.activeBaseId=baseId
check(B.restore(twoCamps)==true and B.voiceDay(2).hauls==10,"switching back preserves the first camp count")
disposal.dropVoice(delivered[5])
check(B.voiceDay(2).hauls==10,"switching camps cannot replay a body's first receipt")
world.age=72
check(disposal.dropVoice(corpse())=="burial.haul.drop" and B.voiceDay(3).hauls==1,"new game day resets tally")
local tooMany={day=3,hauls=5,groups={}}
for i=1,100 do tooMany.groups["group"..string.char(97+(i%26))..string.char(97+math.floor(i/26))]=3 end
local bounded=B.normalizeVoiceDay(tooMany) local groupCount=0 for _ in pairs(bounded.groups) do groupCount=groupCount+1 end
check(groupCount==0 and B.normalizeVoiceDay({day=0/0})==nil,"persisted voice context rejects unknown groups and invalid time")
local known={day=3,hauls=5,groups={}}
for group in pairs(study.OUTFIT_PHRASES) do known.groups[group]=3 end
local restored=B.normalizeVoiceDay(known)
for group in pairs(study.OUTFIT_PHRASES) do
    check(restored.groups[group]==3,"every supported outfit group survives normalization "..group)
end
local capped=corpse()
local receipts={[baseId]=2}
for i=1,7 do receipts["base:visited-"..i]=2 end
capped.getModData().LF_HaulVoiceReceipts=receipts
disposal.dropVoice(capped)
check(B.voiceDay(3).hauls==2 and receipts[baseId]==3,
    "a full receipt table still updates its existing camp on a new day")
local unknown=corpse() local unknownData=unknown.getModData()
unknownData.LF_HaulVoiceReceipts={}
for i=1,8 do unknownData.LF_HaulVoiceReceipts["base:visited-"..i]=3 end
disposal.dropVoice(unknown)
check(B.voiceDay(3).hauls==2 and unknownData.LF_HaulVoiceReceipts[baseId]==nil,
    "body voice receipts stay bounded across camps")
world.age=73 world.hour=12 world.rain=0
local body=corpse("Police")
local lines=study.lines(a,{personalityProfile={archetype="practical"}},body,clock)
check(lines[1].topic=="study.outfit.law","first actual outfit study")
check(B.voiceDay(3).groups.law==nil,"selecting study lines does not remember an unexamined body")
local activity,studyState={object=body},{}
before=#spoken
study.prepare(a,activity,{},studyState,clock)
check(activity.lines[1].topic=="study.outfit.law" and activity.studyOutfitGroup=="law"
    and B.voiceDay(3).groups.law==nil and body.getModData().LF_Studied==nil and #spoken==before,
    "preparing an approach stages its outfit without speech or completed-study memory")
activity=nil -- The approach is aborted before its first bark or finish hook.
check(B.voiceDay(3).groups.law==nil and body.getModData().LF_Studied==nil,
    "an aborted study leaves its body and daily outfit memory untouched")
activity={object=body}
study.prepare(a,activity,{},studyState,clock+1)
check(activity.lines[1].topic=="study.outfit.law","retrying the same unexamined body is still the first outfit study")
study.finish(a,activity,clock+2)
check(B.voiceDay(3).groups.law==3 and body.getModData().LF_Studied==true
    and activity.studyOutfitGroup==nil,"finishing the real study commits its body marker and outfit memory")
lines=study.lines(a,{personalityProfile={archetype="practical"}},corpse("Police"),clock+3)
check(lines[1].topic=="study.again" and lines[1].arguments[1]=="with a badge","same-day repeated outfit study")
check(B.restore(B.export())==true,"completed study outfit memory survives real camp export/restore")
lines=study.lines(a,{},corpse("Police"),clock+4)
check(lines[1].topic=="study.again","a distinct body recalls the completed outfit study after reload")
missing["study.again"]=true
lines=study.lines(a,{},corpse("Police"),clock+5)
check(lines[1].topic=="study.outfit.law","missing repeated-study topic falls back") missing["study.again"]=nil
world.age=96
lines=study.lines(a,{},corpse("Police"),clock+6)
check(lines[1].topic=="study.outfit.law" and B.voiceDay(4).groups.law==nil,
    "new day forgets the previous completed study without recording an unexamined outfit")
body=corpse("Police") body.isSkeleton=function() return true end
activity={object=body}
study.prepare(a,activity,{},studyState,clock+7)
check(activity.lines[1].topic=="study.skeleton" and activity.studyOutfitGroup==nil,
    "a skeleton opening stages no outfit memory")
study.finish(a,activity,clock+8)
check(B.voiceDay(4).groups.law==nil,"finishing a skeleton study does not remember its outfit")
local oldStudyHash=study.hash
study.hash=function() return 0 end
body=corpse("Police") body.isCrawling=function() return true end
activity={object=body}
study.prepare(a,activity,{},studyState,clock+9)
study.hash=oldStudyHash
check(activity.lines[1].topic=="study.crawler" and activity.studyOutfitGroup==nil,
    "a crawler opening stages no outfit memory")
study.finish(a,activity,clock+10)
check(B.voiceDay(4).groups.law==nil,"finishing a crawler study does not remember its outfit")
activity={object=corpse("Police")}
study.prepare(a,activity,{},studyState,clock+11)
check(activity.lines[1].topic=="study.outfit.law","skeleton and crawler studies leave the first normal outfit opening available")
study.finish(a,activity,clock+12)
check(B.voiceDay(4).groups.law==4,"a completed normal study starts the new day's outfit memory")
local oldPick=study.pick local candidates
study.pick=function(options) candidates=candidates or options return options[1] end
world.hour=22 world.rain=.3
study.lines(a,{},corpse(),clock+4)
local night,rainSeen=false,false
for _,choice in ipairs(candidates) do
    if choice.topic=="study.night" and choice.weight==2 then night=true end
    if choice.topic=="study.rain" and choice.weight==2 then rainSeen=true end
end
check(night and rainSeen,"night and rain enter actual middle candidates at weight two")
candidates=nil missing["study.night"],missing["study.rain"]=true,true
study.lines(a,{},corpse(),clock+5)
for _,choice in ipairs(candidates) do check(choice.topic~="study.night" and choice.topic~="study.rain","missing weather study falls back") end
study.pick=oldPick missing["study.night"],missing["study.rain"]=nil,nil
SC_TEST_REPORT="VOICE_DEPTH_PASS checks="..checks.." topics="..#topics.." lines="..inspected
print(SC_TEST_REPORT)
