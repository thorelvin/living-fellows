-- SPDX-License-Identifier: MIT
-- Production readers, parser, shared receipts and replies in the existing UI suite.
local SC,T=SurvivorCompanion,TERMINAL_TEST
local B,M,R=SC.TerminalBrain,SC.EmmaMind,SC.EmmaReadings
local check=T.check
local checksBefore=T.checks
local old={mod=ModData,specific=getSpecificPlayer,time=getGameTime,world=getWorld,climate=getClimateManager,
    moodles=MoodleType,perks=PerkFactory,vars=SandboxVars,options=getSandboxOptions,grid=SC.GridControl}
local buckets={}
ModData={getOrCreate=function(key) buckets[key]=buckets[key] or {};return buckets[key] end}
local player=T.player(101,100,0)
local actorData={}
function player:getModData() return actorData end
function player:getHoursSurvived() return 84 end
function player:getZombieKills() return 12 end
function player:getPerkLevel() return 3 end
function player:getDescriptor() return {getForename=function() return "Thor" end,getSurname=function() return "Test" end} end
getSpecificPlayer=function(index) return index==0 and player or nil end
local flags,levels,bodyReads,forecastReads={}, {},0,0
MoodleType={}
for _,spec in ipairs(SC.EmmaBody.MOODLES) do MoodleType[spec[1]]=spec[1] end
local part={}
for _,method in ipairs({"bitten","scratched","isCut","isDeepWounded","bleeding","isBurnt","haveGlass","haveBullet","bandaged","isBandageDirty","isInfectedWound"}) do
    local key=method;part[key]=function() return flags[key]==true end
end
function part:getType() return "ForeArm_L" end
function part:getFractureTime() return flags.fracture or 0 end
local body={infected=false,fake=false,started=0,duration=96,health=100}
function body:getParentChar() return player end
function body:IsInfected() return self.infected end
function body:IsFakeInfected() return self.fake end
function body:getHealth() return self.health end
function body:getInfectionTime() return self.started end
function body:getInfectionMortalityDuration() return self.duration end
function body:getBodyParts() return {size=function() return 1 end,get=function() return part end} end
function player:getBodyDamage() bodyReads=bodyReads+1;return body end
function player:getMoodles() return {getMoodleLevel=function(_,kind) return levels[kind] or 0 end,
    getMoodleDisplayString=function(_,kind) return kind end} end
local skills={{getName=function() return "Carpentry" end}}
PerkFactory={PerkList={size=function() return #skills end,get=function(_,i) return skills[i+1] end}}
function player:getCharacterTraits() return {getKnownTraits=function() return {} end} end
local values={mortality=5,heli=2,water=12,power=13,age=10.5,nights=50,hour=20,heliDay=53,active=false}
SandboxVars={ZombieLore={Mortality=5},Helicopter=2}
getSandboxOptions=function() return {
    getOptionByName=function(_,name) return {getValue=function() return name=="Helicopter" and values.heli or values.mortality end} end,
    getWaterShutModifier=function() return values.water end,getElecShutModifier=function() return values.power end} end
getGameTime=function() return {getYear=function() return 1993 end,getMonth=function() return 6 end,getDay=function() return 8 end,
    getTimeOfDay=function() return values.hour end,getHour=function() return math.floor(values.hour) end,
    getMinutes=function() return 0 end,getNightsSurvived=function() return values.nights end,
    getWorldAgeHours=function() return 10000 end,getHelicopterDay1=function() return values.heliDay end,
    getHelicopterStartHour=function() return 9 end,getHelicopterEndHour=function() return 13 end} end
getWorld=function() return {getWorldAgeDays=function() return values.age end,helicopter={isActive=function() return values.active end}} end
local days={}
local function day(offset)
    local fact=days[offset] or {}
    if fact.missing then return nil end
    return {getIndexOffset=function() return offset end,isWeatherStarts=function() return fact.rain==true end,
        getWeatherOverlap=function() return nil end,isHasBlizzard=function() return false end,isHasTropicalStorm=function() return false end,
        isHasStorm=function() if fact.partial then return nil end;return fact.storm==true end,isHasHeavyRain=function() return false end,
        isChanceOnSnow=function() return fact.snow==true end,isHasFog=function() return fact.fog==true end,
        getCloudiness=function() return {getDayMean=function() return fact.badClouds and 0/0 or .1 end} end,
        getTemperature=function() return {getDayMean=function() return 20+offset end,getDayMax=function() return 24+offset end,
            getTotalMin=function() return fact.frost and -2 or 12 end} end}
end
getClimateManager=function() return {
    getSeason=function() return {getDawn=function() return 6 end,getDusk=function() return 21 end} end,
    getClimateForecaster=function() return {getForecast=function(_,offset) forecastReads=forecastReads+1;return day(offset) end,
        getForecasts=function() error("raw list includes past weather") end} end} end
SC.GridControl=nil
local clock=0
local function session(kind,id)
    local pc={identity=id or kind,locked=false}
    local entry=M.enter(player,pc,{}, {name="Thor",kind=kind,hours=100},{})
    local s=B.newSession({operator="Thor",random=function() return 1 end,nowMs=function() return clock end})
    s.emmaMind={world=entry.world,operator=entry.operator,computer=pc.identity}
    return s
end
local world={camp=function() return {configured=true,inside=false} end,people=function() error("not camp people") end,
    storage=function() error("not camp stock") end,body=function(mode) return SC.EmmaBody.read(player,mode) end,
    self=function(mode) return SC.EmmaBody.file(player,mode) end,calendar=function(kind,query) return SC.EmmaCalendar.read(kind,query) end,
    calendarClock=SC.EmmaCalendar.clock,daylight=SC.EmmaCalendar.daylight}
local function ask(s,q,id)
    local reply=B.respond(s,q,world)
    check(not reply.error,"body/calendar handler error: "..q.." / "..tostring(reply.error))
    if id then check(reply.intent==id,q.." reaches "..id..", got "..reply.intent) end
    return table.concat(reply.lines," "),reply
end
local s=session("home")
ask(s,"how am i","me_status")
check(bodyReads==0,"locked body domain makes no health read")
ask(s,"when is the helicopter","helicopter")
check(forecastReads==0,"locked calendar makes no forecast read")
local text=ask(s,"when is dawn","daylight")
check(text:find("tomorrow",1,true) and text:find("06:00",1,true),"daylight is free and wraps after today's dawn")
text=ask(s,"my kills","me_kills")
check(text:find("12",1,true),"operator file works before the medical domain")
text=ask(s,"what are my skills","me_skills")
check(text:find("Carpentry 3",1,true),"operator skills use native perk objects")
s=session("clinic")
local classifications={"how am i","am i infected","am i hungry","how many zombies have i killed","days survived",
    "what town is this","what are my skills","what do you know about me"}
for _,q in ipairs(classifications) do ask(s,q) end
flags.bleeding=true
levels.HUNGRY=4
text=ask(s,"how am i","me_status")
check(text:find("left forearm",1,true) and text:find("bleeding",1,true),"actual operator bleeding precedes hunger")
flags={}
for _,case in ipairs({{"isDeepWounded","deep wound"},{"fracture","fractured"},{"haveGlass","Glass or lead"},
    {"haveBullet","Glass or lead"},{"isBurnt","Burned"},{"isInfectedWound","ordinary infection"},
    {"isCut","cut"},{"scratched","scratch"},{"bitten","bite"}}) do
    flags[case[1]]=case[1]=="fracture" and 10 or true
    text=ask(s,"check me","me_status")
    check(text:find(case[2],1,true),"real wound report: "..case[1])
    flags={}
end
flags.bandaged,flags.isBandageDirty=true,true
text=ask(s,"check me","me_status")
check(text:find("filthy",1,true),"dirty dressing is distinct from infection")
flags={};levels={}
for _,spec in ipairs(SC.EmmaBody.MOODLES) do
    levels[spec[1]]=2
    local snapshot=SC.EmmaBody.read(player,"need")
    check(#snapshot.needs==1 and snapshot.needs[1].kind==spec[2],"native needs classification: "..spec[1])
    levels={}
end
levels.SICK=2;body.fake=true
text=ask(s,"am i infected","me_infected")
check(text:find("false-infection",1,true) and not text:find("Knox infection, confirmed",1,true),"false infection never becomes Knox infection")
body.fake=false;flags.isInfectedWound=true
text=ask(s,"am i infected","me_infected")
check(text:find("No Knox",1,true),"ordinary wound infection never becomes Knox infection")
body.infected=true;flags={};levels={}
local notice=R.boot(s,world)
check(notice and #notice==2 and R.boot(s,world)==nil,"infection is announced once at boot")
check(not table.concat(notice," "):find("July",1,true),"automatic reveal contains no countdown")
buckets[M.KEY]=M.normalize(buckets[M.KEY])
check(R.boot(s,world)==nil,"infection receipt survives normalization/reload")
text=ask(s,"how long do i have","me_infected")
check(text:find("July 10, 1993 at 08:00",1,true),"infection estimate uses 84 survived hours, not 10000 world hours")
text=ask(s,"how long","me_infected")
check(text:find("already given",1,true),"short follow-up cannot replay the one-time estimate")
values.mortality=7;body.started=1
text=ask(s,"how long do i have","me_infected")
check(text:find("no infection-mortality deadline",1,true),"nonlethal infection never gets a death date")
body.infected=false
ask(s,"am i infected")
check(R.boot(s,world)==nil,"a confirmed clear reading resets the infection episode")
body.infected=true;values.mortality=5;body.started=2
s.careMode=true;s.careQuestion=false
local before=bodyReads
check(R.boot(s,world)==nil and bodyReads==before,"care suppresses automatic medical reads and notices")
text=ask(s,"how long do i have","me_infected")
check(text:find("will not give a countdown",1,true) and not text:find("July",1,true),"care health questions stay plain and have no countdown")
s.careMode=nil
check(R.boot(s,world)~=nil,"suppressed infection notice remains available in a fresh ordinary session")
body.infected=false;ask(s,"am i infected")
text=ask(s,"what should i do","me_status")
check(not text:find("camp",1,true),"body treatment follow-up stays on the operator")
s=session("police")
for _,case in ipairs({{12,"before"},{11,"soon"},{10,"after"},{2147483647,"never"}}) do
    values.water=case[1]
    check(SC.EmmaCalendar.read("water_off").water~=nil,"water schedule source remains available")
    text=ask(s,"when will the water stop","water_off")
    check(case[2]~="never" or text:find("no shutoff",1,true),"never water does not invent a future date")
end
values.water=12;values.power=13
text=ask(s,"when will the power go out","power_off")
check(text:find("July",1,true),"power schedule has a real date")
text=ask(s,"how long","power_off")
check(text:find("grid fails",1,true),"short power follow-up refreshes the same event")
SC.GridControl={snapshot=function() return {visible=true,on=true,originalShut=1,remainingHours=8} end}
text=ask(s,"when does the power go off","power_off")
check(text:find("brought some of it back",1,true),"restored grid keeps the original shutoff and reports restoration")
SC.GridControl=nil
values.heliDay=53;values.heli=2
text=ask(s,"when is the helicopter","helicopter")
check(text:find("July 12, 1993",1,true),"helicopter uses nights survived, independently of world age")
values.heliDay=values.nights;values.hour=10
text=ask(s,"is it here yet","helicopter")
check(text:find("cannot confirm",1,true) and not text:find("is active",1,true),"flight window is not proof of a live helicopter")
values.active=true
text=ask(s,"helicopter","helicopter")
check(text:find("is active",1,true),"native active flight can be reported")
values.active=false;values.heli=1
text=ask(s,"helicopter","helicopter")
check(text:find("No flights",1,true),"never setting suppresses a stale flight date")
values.heli=3;values.heliDay=49
text=ask(s,"helicopter","helicopter")
check(text:find("Further flights",1,true),"repeatable helicopter is not declared the last flight")
forecastReads=0;days[1]={rain=true};days[3]={storm=true}
text=ask(s,"weather tomorrow","forecast")
check(text:find("rain",1,true) and text:find("21 C",1,true) and forecastReads==1,"tomorrow reads native offset one, never the raw list")
text=ask(s,"what temperature","forecast")
check(text:find("21 C",1,true),"forecast follow-up preserves the requested day")
forecastReads=0
text=ask(s,"next storm","forecast")
check(text:find("Storm conditions",1,true) and forecastReads==4,"next storm search stops on the first matching day")
days={};forecastReads=0
text=ask(s,"next storm","forecast")
check(text:find("No storm",1,true) and forecastReads==7,"no-event conclusion requires all seven records")
days[2]={missing=true}
text=ask(s,"next storm","forecast")
check(text:find("cannot verify",1,true) and not text:find("No storm",1,true),"missing forecast cannot become a false all-clear")
text=ask(s,"forecast in 9 days","forecast")
check(text:find("next six days",1,true),"forecast horizon is explicitly bounded")
values.hour=6
text=ask(s,"when is dawn","daylight")
check(text:find("tomorrow",1,true) and text:find("24 hours",1,true),"exact dawn schedules the next day's dawn, not zero hours")
check(SC.EmmaCalendar.date({year=2000,month=1,day=27},1)=="February 29, 2000","calendar formatting handles leap day without host time")
check(B.exportMemory(s).notes and not B.exportMemory(s).conversation,"readings and follow-up facts do not enter exported memory")
for _,question in ipairs({"when does the sun rise","when does the sun come up","when is dawm"}) do
    local intent,slots=B.parse(session("police"),question,world,{cache={}})
    check(intent=="daylight" and slots.dawn==true,"sunrise wording and tolerated typos retain the dawn facet: "..question)
end
for _,case in ipairs({{"how much food for tomorrow","food"},{"how much water do we have for tonight","storage"},
    {"will it be cold tomorrow","forecast"}}) do
    local intent=B.parse(session("police"),case[1],world,{cache={}})
    check(intent==case[2],"a date alone cannot steal another subject: "..case[1].." / "..intent)
end
body.infected=nil;body.fake=true;flags={};levels={}
text=ask(session("clinic"),"how am i")
check(text:find("Knox infection reading is unavailable",1,true) and not text:find("No Knox",1,true)
    and not text:find("Not infected",1,true),"false symptoms cannot prove an unavailable Knox reading negative")
body.infected=true;body.fake=false;body.started=-1
local pendingInfection=session("clinic")
check(R.boot(pendingInfection,world)~=nil,"infection can warn before its native timestamp is initialized")
buckets[M.KEY]=M.normalize(buckets[M.KEY]);body.started=5
check(R.boot(pendingInfection,world)==nil,"a later timestamp qualifies the provisional warning without repeating it")
buckets[M.KEY]=M.normalize(buckets[M.KEY])
check(R.boot(pendingInfection,world)==nil,"the qualified warning receipt survives normalization")
body.started=6
check(R.boot(pendingInfection,world)~=nil,"a genuinely different infection timestamp still permits its own warning")
local infectedSession=session("clinic")
local original=ask(infectedSession,"am i infected")
local repeated,repeatReply=ask(infectedSession,"REPEAT","repeat")
check(repeated==original and repeatReply.sensitive,"repeating a medical answer cannot prepend a shout joke")
original=ask(infectedSession,"my kills and am i infected")
repeated,repeatReply=ask(infectedSession,"REPEAT","repeat")
check(repeated==original and repeatReply.sensitive,"a compound answer retains the sensitive flag of its medical clause")
body.infected=false;levels.HUNGRY=4
local needsSession=session("clinic")
text=ask(needsSession,"am i thirsy","me_need")
check(text:find("No current thirsty warning",1,true),"a tolerated need typo keeps the requested need instead of switching to hunger")
text=ask(needsSession,"check again","me_need")
check(text:find("No current thirsty warning",1,true),"refresh retains the specific need and reads it again")
days={[3]={storm=true}}
local weatherSession=session("police")
ask(weatherSession,"next storm");days={[4]={storm=true}}
forecastReads=0;text=ask(weatherSession,"check again","forecast")
check(text:find("Storm conditions",1,true) and text:find("July 13, 1993",1,true) and forecastReads==5,
    "refresh searches again for the next storm instead of reusing the old day offset")
text=ask(weatherSession,"tomorrow","forecast")
check(text:find("July 10, 1993",1,true),"a bare date remains a valid follow-up after a forecast")
values.water=nil;values.power=13;values.heli=2;values.heliDay=53
text=ask(session("police"),"what is on the calendar","calendar")
check(text:find("cannot verify the water schedule",1,true) and not text:find("The water stops",1,true)
    and text:find("grid fails",1,true) and text:find("helicopter",1,true),"missing water cannot borrow a power or helicopter date")
values.water=12;values.power=nil
text=ask(session("police"),"what is on the calendar","calendar")
check(text:find("cannot verify the power schedule",1,true) and not text:find("grid fails",1,true)
    and text:find("water stops",1,true),"missing power cannot borrow the helicopter event")
days={[1]={partial=true}}
text=ask(session("police"),"weather tomorrow","forecast")
check(text:find("cannot verify",1,true) and not text:find("clear skies",1,true),"an incomplete daily forecast cannot claim clear weather")
days={[1]={badClouds=true}}
text=ask(session("police"),"weather tomorrow","forecast")
check(text:find("cannot verify",1,true),"a non-finite cloud reading is unavailable, not clear skies")
days={[1]={missing=true},[3]={storm=true}}
text=ask(session("police"),"next storm","forecast")
check(text:find("Storm conditions",1,true) and text:find("Earlier forecast records are incomplete",1,true),
    "a later confirmed storm does not prove the missing earlier days were clear")
local calendarCare=session("police");calendarCare.careMode=true;calendarCare.careQuestion=false
text=ask(calendarCare,"when is the helicopter","helicopter")
check(text:find("July 12, 1993",1,true) and text:find("09:00 to 13:00",1,true),
    "plain care answers retain the actual flight date and interval")
ModData,getSpecificPlayer,getGameTime,getWorld,getClimateManager=old.mod,old.specific,old.time,old.world,old.climate
MoodleType,PerkFactory,SandboxVars,getSandboxOptions,SC.GridControl=old.moodles,old.perks,old.vars,old.options,old.grid
SC_TEST_REPORT=(SC_TEST_REPORT or "").."\nEMMA_BODY_CALENDAR_PASS checks="..(T.checks-checksBefore)
