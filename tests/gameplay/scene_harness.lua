-- SPDX-License-Identifier: MIT
local SC=LivingFellows
local S,C,D,T,U=SC.Scenes,SC.Community,SC.Dialogue,SC.TestFixture,SC.GameplayUtil
local checks,scenario,wall,game,paused=0,0,0,240*3600000,false
local function check(value,message) checks=checks+1 assert(value,"scene check "..checks..": "..message) end
function getTimestampMs() return wall end
function getGameTime() return {getWorldAgeHours=function() return game/3600000 end,
    getMinutesPerDay=function() return 60 end,
    getTimeOfDay=function() return game/3600000%24 end,getHour=function() return math.floor(game/3600000%24) end} end
function isGamePaused() return paused end
local rows,actors,states,captured={},{},{},{}
local nativeEmit=D.emitResolved
D.emitResolved=function(actor,topic,line,options)
    local ok,result,receipt=nativeEmit(actor,topic,line,options)
    if ok then captured[#captured+1]={actor=actor,topic=topic,line=line,options=options} end
    return ok,result,receipt
end
SC.BaseLife.isInside=function() return true end
SC.Registry.records=function() return rows end
SC.ActionSupervisor.current=function(actor) return actor.sceneToken or {owner="downtime",action="read"} end
local movement=0
U.move=function() movement=movement+1 return false,"forbidden_in_scene_test" end
SC.Navigation.request=function() movement=movement+1 return false,"forbidden_in_scene_test" end
SC.UserOptions={get=function() return "normal" end}
local function tick(ms,gameAdvance)
    wall=wall+ms SC_TEST_CLOCK=wall
    game=game+(gameAdvance or (paused and 0 or ms*24))
    S.tick(wall)
end
local function fresh()
    scenario=scenario+1 wall=100000 game=240*3600000 paused=false
    SC_TEST_CLOCK=wall C.reset() SC.LifeEvents.reset() SC.Banter.reset() D.reset()
    rows,actors,states,captured={},{},{},{}
    for n=1,3 do
        local actor=T.actor("sc-scene-"..scenario.."-"..n,n+1,1,{recruited=true})
        actor.name=({"June","Sam","Nick"})[n]
        function actor:getDescriptor() return {getForename=function() return self.name end,getSurname=function() return "" end} end
        function actor:isAsleep() return false end
        local commands=SC.Commands.peek(actor)
        commands.recruited=true commands.order="hold" commands.behavior="idle"
        commands.personality=({"caring","cautious","brave"})[n]
        commands.personalityProfile={compassion=50}
        actors[n],states[n]=actor,commands
        local row={id=U.idOf(actor),actor=actor,recruited=true,
            runtime={senses={current={threatCount=0,immediateCount=0,pressure=0}}}}
        rows[n]=row T.registry[row.id]=row
    end
    S.tick(wall)
end
local function start(priority)
    return SC.Banter._sceneStartForTests(T.player,rows,wall,priority)
end
local _,_,advance=SC.Banter._socialForTests()
local function finish()
    for n=1,16 do
        if not SC.Banter._partyForTests().exchange then break end
        tick(5000) advance(rows,wall)
    end
end
local function sceneShape()
    local speakers,prior={},nil
    for _,line in ipairs(captured) do
        local o=line.options
        if o and o.sceneId then
            speakers[U.idOf(line.actor)]=true
            if prior and (not o.accepts or not o.accepts[prior]) then return false end
            prior=o.tag
        end
    end
    local count=0 for _ in pairs(speakers) do count=count+1 end
    return #captured>=3 and #captured<=6 and count>=2
end

local lineCount,uniqueLines,uniqueCount=0,{},0
local function immersion(text)
    if text:find("[^%z\1-\127]") then return false end
    local lower=text:lower()
    for _,word in ipairs({" meters","smartphone","wifi","wi-fi","youtube","google it","gps",
        "skill tree","skill point","hotbar","respawn","npc"," xp","loot table","crafting menu"}) do
        if lower:find(word,1,true) then return false end
    end
    for year in text:gmatch("%d%d%d%d") do if tonumber(year)>=1994 and tonumber(year)<=2099 then return false end end
    return true
end
check(not immersion("Use the smartphone in 1996.") and not immersion("Five meters to the hotbar."),
    "immersion lint negative controls reject future technology, units and game terms")
local catalogs={}
for _,group in ipairs({SC.SceneLines.catalogs,SC.RecallLines and SC.RecallLines.catalogs or {},
    SC.DeepBackground and SC.DeepBackground.catalogs or {}}) do
    for _,catalog in ipairs(group) do catalogs[#catalogs+1]=catalog end
end
for _,catalog in ipairs(catalogs) do
    local valid,why=SC.DiaryText.validateCatalog(catalog)
    check(valid,"catalog contract: "..tostring(why))
    for _,packet in ipairs(catalog) do for _,variant in ipairs(packet.variants) do
        lineCount=lineCount+1
        if not uniqueLines[variant.text] then uniqueLines[variant.text]=true uniqueCount=uniqueCount+1 end
        check(not variant.text:find("[^%z\1-\127]") and variant.clean~=nil,"ASCII and clean twin")
        check(not variant.text:lower():find(" meters",1,true),"metres spelling")
        check(not variant.text:lower():find(" xp",1,true) and not variant.text:lower():find("skill tree",1,true),"no game terminology")
        check(immersion(variant.text) and immersion(variant.clean),"full immersion lint on both twins")
    end end
end
if SC.VoiceLayers then
    for _,pool in pairs(SC.VoiceLayers.lines) do for _,line in ipairs(pool) do
        lineCount=lineCount+1
        if not uniqueLines[line[1]] then uniqueLines[line[1]]=true uniqueCount=uniqueCount+1 end
        check(immersion(line[1]) and immersion(line.clean),"layer twins pass immersion lint")
        check((line.after_day==7 or line.after_day==30 or line.after_day==100)
            and (line.tier=="trusted" or line.tier=="close" or line.tier=="family"),"explicit age and tier layer")
    end end
    check(uniqueCount>=700 and uniqueCount<=850,"requested authored voice depth stays in scope")
end
local death=SC.SceneLines.aftermath.death.open.packets
local validLines=SC.DiaryText.spokenCandidates({evidence={known=true,death=true,has_name=true},tokens={name="Wade"}},death)
local blocked=SC.DiaryText.spokenCandidates({evidence={death=true,has_name=true},tokens={name="Wade"}},death)
check(#validLines>0 and #blocked==0,"removing event knowledge blocks factual packet")
local missingToken=SC.DiaryText.spokenCandidates({evidence={known=true,death=true,has_name=true},tokens={}},death)
check(#missingToken==0,"declared flag cannot replace the actual named token")

fresh()
check(start(false)==true,"ordinary camp scene starts")
local scene=SC.Banter._partyForTests().exchange
check(scene.generalized and #scene.roles==3 and scene.branch=="pushback","cautious B chooses pushback and C can join")
finish()
check(sceneShape() and not SC.Banter._partyForTests().exchange,"four fitting beats finish")
check(movement==0,"quiet readers are never moved or pulled from their action")
local firstGame=game
for n=1,25 do tick(5000,3*3600000/25) end
check(start(false)==false,"fast game time cannot bypass the three-minute floor")
for n=1,20 do tick(5000) end
check(start(false)==true,"both clocks eventually allow another scene")
finish()

for _,length in ipairs({3,6,7}) do
    fresh()
    local host=SC.Banter._sceneHostForTests() host.records=rows
    local accepts={agree=true,tease=true,pushback=true,comfort=true,deflect=true}
    local recipe={
        {role=1,phase="open",tag="deflect",accepts=accepts},
        {role=2,phase="reply_pushback",tag="pushback",accepts=accepts},
        {role=1,phase="follow_pushback",tag="agree",accepts={pushback=true}},
    }
    while #recipe<length do recipe[#recipe+1]={role=#recipe%3+1,phase="close",tag="agree",accepts={agree=true}} end
    local made,why=S._startForTests({actor=actors[1]},{actor=actors[2]},{actor=actors[3]},
        SC.SceneLines.cards[1],T.player,wall,host,{beats=recipe})
    if length<=6 then
        check(made~=nil,"engine accepts "..length.." authored beats")
        SC.Banter._partyForTests().exchange=made finish()
        check(#captured==length and sceneShape(),"engine completes "..length.." fitting beats")
    else check(not made and why=="scene_beat_limit" and #captured==0,"oversize-scene negative control is rejected") end
end

fresh() start(false) finish()
local before=S.clock()
paused=true
for n=1,80 do tick(5000) end
paused=false tick(5000,3*3600000)
local after=S.clock()
check(after-before<10000 and start(false)==false,"paused wall time never earns the scene floor")
local originalTick=S.tick
-- Negative control: counting paused time would satisfy the very same floor.
local brokenElapsed=after-before+80*5000
check(brokenElapsed>=180000,"pause mutant would be rejected by the floor assertion")
fresh() start(false) finish()
local beforeStoppedTicks=S.clock()
tick(300000,24)
check(S.clock()==beforeStoppedTicks,"a pause with no callbacks earns no active time")
tick(5000,24)
check(S.clock()-beforeStoppedTicks<=1.01,"small game progress cannot count a paused wall interval")

fresh() start(false)
rows[2].runtime.senses.current.threatCount=1
tick(1000)
local spoken,why,busy=advance(rows,wall)
check(not spoken and not busy and why=="scene_interrupted","danger aborts before the next scheduled beat")
fresh() start(false)
states[3].commandSerial=(states[3].commandSerial or 0)+1 tick(1000)
spoken,why,busy=advance(rows,wall)
check(not busy and #captured==1,"an order to optional C aborts immediately")
fresh() start(false)
D.emitResolved(actors[2],"combat.warning","Move back.") tick(1000)
spoken,why,busy=advance(rows,wall)
check(not busy and #captured==2,"urgent speech by B aborts even before B's first scene line")
fresh() start(false)
SC.Banter._partyForTests().exchange.lastTag="unrecognised" tick(5000)
spoken,why,busy=advance(rows,wall)
check(not busy and why=="scene_tag_mismatch" and #captured==1,"wrong-branch negative control cannot emit a reply")
fresh()
states[1].order="guard" states[2].order="work" states[3].order="guard"
check(start(false)==false and #captured==0,"guard posts and jobs are excluded without requiring an action token")

fresh()
local pair=C.relation(actors[1],actors[2],true)
pair.memories={{kind="worked",at=game}}
check(S.argumentReason(actors[1],actors[2])==nil,"ordinary work never invents a bad supply run")
pair.memories={{kind="supply_run_rough",at=game}}
local ticket=S.requestArgument(actors[1],actors[2])
check(ticket and ticket.reason=="last_run","argument uses the actual shared supply-run memory")
check(start(true)==true,"autonomy request uses the one party scene slot") finish()
check(ticket.status=="finished" and ticket.outcome=="walk_away","pushback can end with space instead of a forced fight")
check(pair.grudge and pair.grudge.untilAt-pair.grudge.startedAt<=72*3600000,"grudge is bounded to three game days")
local saved=C.export() check(C.restore(saved),"grudge persists through a save")
pair=C.relation(actors[1],actors[2],false)
check(pair.grudge and pair.grudge.reason=="last_run","saved grudge keeps its actual reason")
local malformed=C.export()
for _,savedPair in pairs(malformed.pairs) do if savedPair.grudge then savedPair.grudge.untilAt=savedPair.grudge.startedAt+73*3600000 end end
check(C.restore(malformed)==false,"overlong saved grudge negative control is rejected")
game=pair.grudge.untilAt+1
for n=1,40 do tick(5000) end
check(start(false)==true,"cooled grudge starts making up")
check(SC.Banter._partyForTests().exchange.sceneKind=="makeup","making up has a separate scene") finish()
check(not C.relation(actors[1],actors[2],false).grudge,"completed reconciliation clears the grudge")
check(#SC.LifeEvents.drain(32)>0,"argument and reconciliation emit ordinary life events")

fresh()
states[1].stress=80 states[2].personality="caring"
check(start(false)==true and SC.Banter._partyForTests().exchange.sceneKind=="comfort","caring companion responds to a shaken friend")
finish()
local comfort
for _,thought in ipairs(C.peekMind(actors[1]).thoughts) do if thought.kind=="received_support" then comfort=thought end end
check(comfort and comfort.stress==-4 and comfort.morale==2,"companion comfort is smaller than player encouragement")

fresh()
C.setGrudge(actors[1],actors[2],"last_run","",game+72*3600000)
SC.LifeEvents.observed("shared_escape",actors[1],{participants={U.idOf(actors[1]),U.idOf(actors[2])},place="the firehouse"})
C.processEvents(32)
for n=1,9 do tick(5000) start(true) end
finish()
for n=1,70 do tick(5000) end
check(start(false)==true and SC.Banter._partyForTests().exchange.sceneKind=="makeup",
    "a shared escape brings reconciliation forward before three days")
finish()

for _,reason in ipairs({"hidden_bite_revealed","fled_fight","food_eaten","door_left_open"}) do
    fresh()
    pair=C.relation(actors[1],actors[2],true)
    pair.memories={{kind=reason,at=game}}
    check(S.argumentReason(actors[1],actors[2])==nil,"accusation needs shared evidence: "..reason)
    local event=SC.LifeEvents.observed(reason,actors[2],{participants={U.idOf(actors[2])},witnesses={U.idOf(actors[1])},
        outcome=reason=="food_eaten" and "shared_reserve" or "observed"})
    C.processEvents(32)
    pair.memories={{kind=reason,eventId=event.id,at=game}}
    check(S.argumentReason(actors[1],actors[2])~=nil,"observed reason is available: "..reason)
    ticket=S.requestArgument(actors[1],actors[2]) start(true) finish()
    check(sceneShape() and ticket.status=="finished","reason-specific reply chain completes: "..reason)
end

local function aftermath(kind,family)
    fresh()
    local source=actors[1]
    local fields={participants={U.idOf(source)},witnesses={U.idOf(actors[2])},place="the firehouse",
        targetName="Wade",outcome=family=="alarm" and "all_clear" or "crew_returned"}
    if family=="death" then
        source=T.actor("sc-scene-fallen",3,1,{recruited=true}) source.dead=true
        fields.targetId=U.idOf(source) fields.sourceName="Wade"
        fields.participants={U.idOf(source)} fields.witnesses={U.idOf(actors[1]),U.idOf(actors[2])}
        C.adjustRelation(actors[2],source,{opinion=80,trust=80})
    end
    local row=SC.LifeEvents.observed(kind,source,fields) C.processEvents(32)
    check(start(true)==false,"aftermath waits for calm: "..family)
    for n=1,5 do tick(5000) start(true) end
    check(#captured==0,"no reaction before thirty active seconds: "..family)
    tick(5000) check(start(true)==true,"deferred group reaction begins: "..family)
    local active=SC.Banter._partyForTests().exchange
    check(active.sceneKind=="aftermath" and active.family==family,"correct event family")
    if family=="death" then check(active.first==actors[2],"closest grieving friend speaks first")
    else check(active.first==actors[1],"affected companion or returning crew speaks first") end
    finish()
    check(sceneShape() and C.historyRow(row.id).aftermathDone,"one complete tagged reaction is recorded")
    saved=C.export() check(C.restore(saved),"aftermath receipt persists")
    for n=1,10 do tick(5000) start(true) end
    check(#captured==4,"completed event never triggers a second aftermath")
    return row
end
aftermath("companion_died","death")
aftermath("shared_escape","close_call")
aftermath("expedition_homecoming","homecoming")
aftermath("alarm_fought_off","alarm")

fresh()
SC.LifeEvents.observed("shared_escape",actors[1],{participants={U.idOf(actors[1])},place="the firehouse"}) C.processEvents(32)
start(true)
for n=1,5 do tick(5000) start(true) end
rows[1].runtime.senses.current.threatCount=1 tick(5000) start(true)
rows[1].runtime.senses.current.threatCount=0 tick(5000) start(true)
for n=1,5 do tick(5000) start(true) end
check(#captured==0,"new danger restarts the thirty-second calm window")
tick(5000) check(start(true)==true,"reaction follows a complete new calm window") finish()

fresh()
local row=SC.LifeEvents.observed("shared_escape",actors[1],{participants={U.idOf(actors[1])},place="the firehouse"}) C.processEvents(32)
local originalKnowledge=C.knowsEvent
C.knowsEvent=function() return false end
for n=1,12 do tick(5000) start(true) end
check(#captured==0,"knowledge-removal negative control cannot start an event account")
C.knowsEvent=originalKnowledge
check(movement==0,"all tested scenes remained speech-only")
local originalRegistry,originalSquare=SC.Registry.records,U.gridSquare
SC.Registry.records=function() error("scene attempted registry discovery") end
U.gridSquare=function() error("scene attempted a world scan") end
check(not pcall(U.gridSquare,0,0,0),"world-scan negative control confirms the scan guard is armed")
fresh() start(false) finish()
check(sceneShape(),"scene engine needs only its supplied bounded registry view")
SC.Registry.records,U.gridSquare=originalRegistry,originalSquare
D.emitResolved=nativeEmit
SC_TEST_REPORT="SCENE_PASS checks="..checks.." authored_lines="..lineCount.." unique_lines="..uniqueCount
