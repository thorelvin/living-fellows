-- SPDX-License-Identifier: MIT
local SC=SurvivorCompanion
local T,C,H,E=SC.TestFixture,SC.Community,SC.SharedHistory,SC.LifeEvents
local checks=0
local function check(value,why) checks=checks+1 assert(value,"shared history "..checks..": "..why) end
local function copy(value)
    if type(value)~="table" then return value end
    local result={} for k,v in pairs(value) do result[k]=copy(v) end return result
end
local function sameOldFields(expected,actual,path)
    if type(expected)~="table" then return expected==actual,path end
    if type(actual)~="table" then return false,path end
    for key,value in pairs(expected) do
        local equal,where=sameOldFields(value,actual[key],path.."."..tostring(key))
        if not equal then return false,where end
    end
    return true
end
local hours=48
function getGameTime() return {getWorldAgeHours=function() return hours end} end
C.reset() E.reset()
check(type(SC_TEST_LEGACY_COMMUNITY)=="table","actual 0.27.18 fixture is loaded")
check(C.restore(SC_TEST_LEGACY_COMMUNITY),"actual 0.27.18 serialization loads")
local equal,where=sameOldFields(SC_TEST_LEGACY_COMMUNITY,C.export(),"community")
check(equal,"0.27.18 fields stay unchanged: "..tostring(where))
C.reset()
local row=E.emit("rescued_player",{participants={"sc-a"},witnesses={"sc-b"},sourceId="sc-a",
    day=2,hour=4,place="the firehouse",sourceName="June",targetName="Sam",count=3,
    kills=3,weapon="a hammer",outcome="all home",facts={invented="must disappear"}})
check(row.witnesses[1]=="sc-b" and row.participants[1]=="sc-a","two separate identity lists survive emit")
check(row.facts==nil and row.place=="the firehouse" and row.count==3,"flat facts survive; arbitrary nested data does not")
check(C.processEvents()==1,"community drains the queue")
local id=row.id
check(C.historyRow(id).weapon=="a hammer","history retains actual event detail")
check(C.knowsEvent("sc-a",row) and C.knowsEvent("sc-b",row),"participant and witness know the event")
check(not C.knowsEvent("sc-outsider",row),"absence is not knowledge")
check(not C.tellEvent("sc-outsider","sc-c",id,true),"an uninformed speaker cannot teach a memory")
check(not C.tellEvent("sc-a","sc-c",id,false),"an unheard line cannot teach a memory")
check(C.tellEvent("sc-a","sc-c",id,true),"an accepted on-screen telling transmits the event")
local known,from=C.knowsEvent("sc-c",row)
check(known and from=="sc-a","heard-from metadata is retained")
local saved=C.export()
check(C.restore(saved),"new ledger restores")
known,from=C.knowsEvent("sc-c",C.historyRow(id))
check(known and from=="sc-a","heard-from survives save/load")
for n=1,200 do E.emit("worked",{participants={"sc-a"},count=n}) if n%32==0 then C.processEvents(32) end end
while C.processEvents(64)>0 do end
check(#C.export().history==96,"history stays capped at 96")
check(C.historyRow(id) and C.historyRow(id).place=="the firehouse","landmark outlives ordinary history eviction")
for n=1,40 do E.emit("first_meeting",{participants={"sc-a","sc-new-"..n}}) end
while C.processEvents(64)>0 do end
check(#C.export().landmarks==24 and C.historyRow(id),"landmarks have a separate permanent 24-row cap")
E.reset()
for n=1,160 do E.emit("worked",{count=n}) end
check(#E.peek()==128 and E.peek()[1].count==33,"event queue retains only 128 rows")
E.reset()
local malformed=copy(saved)
malformed.history[1].place=function() end
malformed.history[1].kills=0/0
malformed.history[1].witnesses={false,"sc-valid"}
check(C.restore(malformed),"malformed optional facts do not reject the world")
local repaired=C.export().history[1]
check(repaired.place==nil and repaired.kills==nil and repaired.factsQuarantined,
    "malformed facts are removed and marked")
check(repaired.witnesses[1]=="sc-valid","malformed witnesses cannot create a false identity")
check(type(malformed.history[1].place)=="function","restore never mutates its input")
local cleaner=H.cleanDocument H.cleanDocument=function(value) return value end
local negative=C.restore(malformed)
H.cleanDocument=cleaner
check(not negative,"negative control detects removal of fact quarantine")
local legacy=copy(saved)
legacy.landmarks,legacy.heardEvents,legacy.historyFlags=nil,nil,nil
for _,r in ipairs(legacy.history) do
    r.witnesses=nil r.place=nil r.day=nil r.hour=nil r.count=nil r.weapon=nil r.sourceName=nil r.targetName=nil r.outcome=nil
end
check(C.restore(legacy),"pre-extension community document restores")
local loaded=C.export()
check(loaded.version==legacy.version and loaded.history[1].id==legacy.history[1].id,
    "legacy version and event identity are unchanged")
local heardCount=0 for _ in pairs(loaded.heardEvents) do heardCount=heardCount+1 end
check(#loaded.landmarks==0 and heardCount==0,"old save starts with no invented facts or told memories")
do
    C.reset() E.reset()
    local actor=T.actor("sc-clock",1,1,{recruited=true})
    local state=SC.Commands.peek(actor)
    local active,inside=SC.BaseLife.active,SC.BaseLife.isInside
    SC.BaseLife.active=function() return {id="camp-1",name="Rising"} end
    SC.BaseLife.isInside=function() return true end
    local document=C.export()
    hours=7*24+21 H.observeClock(document,actor,state) H.observeClock(document,actor,state)
    local events=E.peek()
    check(#events==2 and events[1].kind=="survival_milestone" and events[2].kind=="first_camp_night",
        "observed milestone and first night emit once")
    check(events[1].count==7 and events[2].place=="Rising","clock facts use the actual day and camp")
    SC.BaseLife.active,SC.BaseLife.isInside=active,inside
    E.reset() document.historyFlags={} hours=45*24 H.observeClock(document,actor,state)
    check(#E.peek()==0,"old saves do not fabricate missed day-seven/month milestones")
end
do
    C.reset() E.reset()
    local actor=T.actor("sc-observer",1,1,{recruited=true})
    local player=T.player
    local state=SC.Commands.peek(actor)
    function player:isBeingGrappled() return self.historyGrabbed==true end
    function player:isKnockedDown() return self.historyDowned==true end
    player.historyDowned=true T.clock=10000
    SC.Relationship.reset(actor)
    SC.Relationship.observe(actor,player,{},state)
    player.historyDowned=false T.clock=12000
    SC.Relationship.observe(actor,player,{},state)
    local found
    for _,event in ipairs(E.peek()) do if event.kind=="player_close_call" then found=event end end
    check(found and found.wasDowned and found.outcome=="player_got_free","a witnessed player recovery keeps its actual restriction facts")
    check(found.targetId=="player:local","player facts are not attributed to another companion")
    E.reset() SC.Relationship.reset(actor)
    local sight=SC.GameplayUtil.canSee SC.GameplayUtil.canSee=function() return false end
    player.historyDowned=true T.clock=14000 SC.Relationship.observe(actor,player,{},state)
    SC.GameplayUtil.canSee=sight
    player.historyDowned=false T.clock=16000 SC.Relationship.observe(actor,player,{},state)
    check(#E.peek()==0,"negative control: nobody remembers an unseen knockdown")
    E.reset() SC.Relationship.reset(actor)
    local peek=SC.Combat.peek
    local attacker={getTarget=function() return player end}
    player.historyDowned=true T.clock=18000 SC.Relationship.observe(actor,player,{},state)
    SC.Combat.peek=function() return {lastAcceptedOffenseAt=19000,lastOffensiveTarget=attacker} end
    player.historyDowned=false T.clock=20000 SC.Relationship.observe(actor,player,{},state)
    SC.Combat.peek=peek
    local rescue
    for _,event in ipairs(E.peek()) do if event.kind=="rescued_player" then rescue=event end end
    check(rescue and rescue.wasDowned and rescue.outcome=="freed_with_cover","actual accepted cover against the player's attacker distinguishes a rescue")
end
do
    C.reset()
    for n=1,16 do
        for m=1,12 do C.addThought("sc-size-"..n,{key="t"..m,kind="worked",text="A remembered event.",
            stress=1,morale=1,at=1,expiresAt=999999999999}) end
    end
    for n=1,16 do for m=n+1,16 do
        for k=1,8 do C.adjustRelation("sc-size-"..n,"sc-size-"..m,{memory={id="pair-"..k,kind="worked",at=1,text="A shared day."}}) end
    end end
    local maximum=C.export()
    maximum.history={} maximum.landmarks={} maximum.heardEvents={}
    local participants,witnesses={},{}
    for n=1,16 do participants[n]="sc-size-"..n witnesses[n]="sc-witness-"..n end
    for n=1,120 do
        local event={id="size-event-"..n,kind="rescued_player",at=1,participants=copy(participants),
            witnesses=copy(witnesses),sourceId=participants[1],place="the firehouse",day=2,hour=1,count=3}
        for k=1,20 do event["detail"..k]="A bounded flat field." end
        if n<=24 then maximum.landmarks[#maximum.landmarks+1]=event else maximum.history[#maximum.history+1]=event end
    end
    for n=1,64 do
        local heard={}
        for m=1,24 do heard[m]={eventId="size-event-"..m,from=participants[1],fromName="A companion",facts="nptcwy"} end
        maximum.heardEvents["sc-listener-"..n]=heard
    end
    if SC.VoiceMemory then
        for n=1,64 do for k=1,96 do
            SC.VoiceMemory.note("sc-size-voice-"..n,"banter.routine","Bounded voice "..n.." line "..k)
        end end
        maximum.voiceMemory=C.export().voiceMemory
    end
    local restored,why=C.restore(maximum)
    check(restored,"legal bounded ledger, pair memories and heard receipts fit the world copy budget: "..tostring(why))
    check(C.export()~=nil,"a full bounded ledger remains saveable")
end
SC_TEST_REPORT="SHARED_HISTORY_PASS checks="..checks
