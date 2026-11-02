-- SPDX-License-Identifier: MIT
local SC,T=SurvivorCompanion,TERMINAL_TEST
local G,L,S=SC.TerminalLockStory,SC.TerminalLocks,SC.TerminalSystem
local check,before=T.check,T.checks
local old={random=ZombRand,mod=ModData,registry=SC.Registry,community=SC.Community,factions=SC.Factions,oddballs=SC.Oddballs,
    paused=isGamePaused,clock=SC.Terminal._clock,perks=Perks,core=getCore,banter=SC.Banter,dialogue=SC.Dialogue,sandbox=SandboxVars}
local ledger={} ModData={getOrCreate=function() return ledger end} L.reset()
Perks={Electricity="Electricity"} SC.Terminal._clock=function() return T.now end
SandboxVars={LivingFellows={LockedComputerPercent=100,LockRealItems=false}}
local player=T.player(101,100,0) local pc=T.computer(T.square(100,100,0,true))
local function open(seed,saved)
    if SC.Terminal.window then SC.Terminal.window:close() end
    local s=saved and S.normalize(saved) or S.create(seed,"home",false,false,"story-test-"..seed)
    if not saved then s.lock.kind="story" s.lock.settled=true s.lock.realItems=false end
    pc.data.movableData=pc.data.movableData or {} pc.data.movableData.LF_LarchOS=s
    check(SC.Terminal.open(player,pc),"story opens through the real lock dispatcher")
    local w=SC.Terminal.window w:flush() return w,w.system
end
local function send(w,n) w:setEntryText(tostring(n)) w:submit() end
local records={}
SC.Registry={records=function() return records end}
SC.Community={recentDeaths=function() return {} end}
ZombRand=function(n) return n==20 and 19 or 42 end
local w,s=open(401)
check(not L.finishUnlock(w,"story"),"unfinished adventure cannot claim a story win")
local data=SC.TerminalLockStoryData local slots={} local ids={}
local placeholders={OWNER="LEONARD BELL",ROOM="OFFICE",COMPANION="RUTH",CLASS="ROGUE",NAME="JILL",N=2,ROLL=12,DC=8}
local function prose(line,max)
    check(type(line)=="string" and #line<=max and line==line:upper(),"supplied story prose fits its uppercase limit")
    for key in line:gmatch("{([A-Z]+)}") do check(placeholders[key]~=nil,"every placeholder has a defined source") end
    check(not G.fill(line,placeholders):find("{",1,true),"fill all placeholders before measuring")
end
for _,scene in ipairs(data.scenes) do
    check(not ids[scene.id] and #scene.options==3 and scene.action==nil,"twenty unique scenes have exactly three choices and no scripted action") ids[scene.id]=true
    slots[scene.slot]=(slots[scene.slot] or 0)+1 prose(scene.text,300)
    for _,option in ipairs(scene.options) do
        prose(option.text,66) prose(option.good,140) prose(option.bad,140)
        check(option.action==nil and (option.result=="good" or option.result=="bad"),"options contain data, not gameplay commands")
        for class,line in pairs(option.class or {}) do check(G.class(class),"alternate choice has a known class") prose(line,66) end
    end
    for _,c in ipairs(data.classes) do
        local plan=G.plan(13,1) plan.class=c.id plan.step=scene.slot
        check(scene.options[G.best(plan,scene)].result=="good","ghost always recommends a good choice for every class and scene")
    end
end
for slot=1,5 do check(slots[slot]>=4,"each of the five stages has four scenes") end
for seed=1,500 do local plan=G.plan(seed,1) check(plan.rolls[2]-plan.rolls[1]>=2 and #plan.rolls==2,"all seeds keep exactly two separated rolls") end
check(s.lock.story.phase=="title" and SC.TerminalLockUI.primary(w),"story has an original launch page")
send(w,1) local g=s.lock.story
check(#g.party==1 and g.party[1].name=="GARY" and g.maxHp==2+G.class(g.class).hp,"solo game uses fictional Gary and exact class HP")
send(w,1)
local planned=0 for _,step in ipairs(g.rolls) do planned=planned+1 check(step>=2 and step<=5,"roll slots are bounded") end
check(planned==2 and g.rolls[2]-g.rolls[1]>=2,"exactly two separated roll scenes")
while g.phase~="win" do
    if g.phase=="scene" then send(w,G.best(g))
    elseif g.phase=="rolling" then
        local roll=g.pending.roll local hp=g.hp
        local reloaded=SC.TerminalLockState.normalize(s.lock,true)
        check(reloaded.kind=="story" and reloaded.story.pending.roll==roll,"committed dice survive normalization")
        T.now=T.now+250 G.update(w,T.now)
        check(g.hp==hp,"dice animation does not prematurely apply a result")
        for _=1,4 do T.now=T.now+250 G.update(w,T.now) end
        check(g.phase=="result" and g.last.roll==roll,"one roll resolves once")
        hp=g.hp G.update(w,T.now+5000) check(g.hp==hp,"late frames never replay the roll")
    elseif g.phase=="result" then
        check(G.normalize(g)~=nil,"resolved results contain no replayable pending transfer") send(w,1)
    else error("unexpected story phase "..g.phase) end
end
check(g.won and s.locked and G.code(s):match("^%d%d%d%d%d%d$"),"victory shows its code before restoring access")
check(not L.finishUnlock({system=s,player=player,object=pc},"phone"),"other lock proofs cannot unlock the story")
send(w,1)
check(not s.locked and s.lock.rewardTier==3 and ledger.beaten.story,"only winning the game records a rare-tier direct completion")
check(not L.finishUnlock(w,"story"),"story XP and reward receipts are one-shot")

for _,c in ipairs(SC.TerminalLockStoryData.classes) do
    local run=G.plan(77,1) run.class=c.id run.hp=2+c.hp run.maxHp=run.hp run.step=2
    local option=G.scene(run.scenes[2]).options[1]
    local crit=G.outcome(run,option,20,0) local fail=G.outcome(run,option,1,10)
    check(crit.good and crit.delta==1 and not fail.good and fail.delta==-2,"natural rolls override ordinary skill and DC for "..c.id)
end
local run=G.plan(13,1) run.finale=1 run.gameOver=1 run.usedGhosts={} run.party={{name="GARY",class="hireling",join=1}}
for _,change in ipairs({function(v) v.rolls={2,3} end,function(v) v.scenes[3]="not-a-scene" end,
    function(v) v.phase="rolling" end,function(v) v.party[1].id={} end,function(v) v.won=true end}) do
    local clean=G.normalize(run) check(clean~=nil,"well-formed game survives load") change(clean)
    check(G.normalize(clean)==nil,"malformed game progress cannot invent a win or repeat a roll")
end
-- Ghosts are actual recruited death records; marked once at display, not planning.
local dead={subjectId="fallen-jill",subjectName="Jill Kelvin",subjectDisplayName="Jill"}
SC.Community.recentDeaths=function() return {dead} end
local ghost
for seed=1,60 do
    ZombRand=function(n) return n==20 and 0 or seed end
    w,s=open(seed+900) send(w,1) g=s.lock.story
    if g.ghost then ghost=g.ghost break end
end
check(ghost~=nil and not g.usedGhosts[dead.subjectId],"only real death history can plan a quiet ghost")
g.step=ghost.step G.enter(w)
check(g.usedGhosts[dead.subjectId] and G.scene(g.scenes[g.step]).options[ghost.choice].result=="good","ghost is consumed once and marks a genuinely good choice")
send(w,3) if g.phase=="rolling" then G.resolve(w) end
check(not g.partyDeath,"a ghost run never kills a named party member")
-- The party names actual nearby living recruits, never a distant/dead actor.
local alice,bob,far,deadActor=T.player(101,101,0),T.player(102,101,0),T.player(150,150,0),T.player(101,101,0)
for _,actor in ipairs({alice,bob,far,deadActor}) do
    function actor:getX() return self.x end function actor:getY() return self.y end function actor:getZ() return self.z end
end
function alice:getDescriptor() return {getForename=function() return "Alice" end} end
function bob:getDescriptor() return {getForename=function() return "Bob" end} end
function deadActor:isDead() return true end
records={{id="alice",actor=alice,recruited=true},{id="bob",actor=bob,recruited=true},
    {id="far",actor=far,recruited=true},{id="dead",actor=deadActor,recruited=true}}
local party=G.party(w,SC.TerminalSystem.random(55))
check(#party==2 and party[1].id~=party[2].id and party[1].id~="far" and party[2].id~="dead","fictional party uses two distinct nearby living recruits")
local canSpeak,spoken,spent=true,nil,0
SC.Banter={availableSpeaker=function() return canSpeak end,budgetAllows=function() return true end,spendBudget=function() spent=spent+1 end}
SC.Dialogue={has=function() return false end,register=function() end,say=function(actor,topic) spoken={actor=actor,topic=topic} return true end}
SC.Community.recentDeaths=function() return {} end
w,s=open(1700) send(w,1) send(w,1) g=s.lock.story
local scene=G.scene(g.scenes[g.step]) local bad
for i,o in ipairs(scene.options) do if o.result=="bad" then bad=i break end end
spent,spoken=0,nil
send(w,bad)
local killed for _,m in ipairs(g.party) do if m.dead then killed=m end end
check(killed and spoken and spoken.actor==(killed.id=="alice" and alice or bob) and spent==1,"only the named fictional casualty reacts through the dialogue budget")
check(not alice:isDead() and not bob:isDead(),"a fictional casualty never kills the real companion")
canSpeak=false spoken=nil
check(not SC.TerminalLockCrew.storyReact(w,killed.id,"storyWin") and spoken==nil,"sleep/combat/availability gates can suppress a story reaction")
records={} SC.Banter,SC.Dialogue=old.banter,old.dialogue
-- Deaths retain their machine-local history and offer alternatives after three.
SC.Community.recentDeaths=function() return {} end
ZombRand=function(n) return n==20 and 0 or 101 end
w,s=open(700)
for death=1,10 do
    if death==1 then send(w,1) else send(w,1) end g=s.lock.story send(w,1)
    while g.hp>0 do
        local scene=G.scene(g.scenes[g.step]) local bad
        for i,o in ipairs(scene.options) do if o.result=="bad" then bad=i break end end
        send(w,bad or 3)
        if g.phase=="rolling" then G.resolve(w) end
        send(w,1)
        if g.phase=="win" then error("death fixture unexpectedly survived") end
    end
    check(g.phase=="dead" and g.deathCount==death and #s.lock.fame==math.min(8,death),"deaths have no timer; Hall of Fame stays bounded")
end
check(s.lock.bypass and not ledger.beaten.word,"three deaths offer alternatives without pretending the puzzle was solved")
-- Exhausted groups are distinct from discovered recruitable people.
local group={oddball={id="actual"},lifecycle="active",discovered=true}
SC.Factions={list=function() return {group} end} SC.Oddballs={definition=function() return {recruitment=true} end}
check(#L.requiredKinds()==9,"discovered but unrecruited people still require USER2")
group.recruitment={joinedActorId="now-a-companion"}
check(#L.requiredKinds()==8,"exhausted recruitable people do not make the title impossible")
SC.Oddballs.hasUnseededRecruitable=function() return true end
check(#L.requiredKinds()==9,"not-yet-spawned recruitable encounters still count")
SC.Oddballs.hasUnseededRecruitable=function() return false end
ledger.beaten={} for _,kind in ipairs(L.requiredKinds()) do ledger.beaten[kind]=true end ledger.beaten.story=nil
check(not L.awardLicense(player),"bypassing a rare puzzle cannot earn the licence")
ledger.beaten.story=true
check(L.awardLicense(player) and ledger.licensee and not L.awardLicense(player),"all built direct wins award a persistent title once")
check(L.recovery():find("8/8",1,true),"Recovery Log uses its reachable target")
-- Every normal and compact layout retains bounded, reachable numbered choices.
for _,size in ipairs({{480,540},{800,600},{1280,720},{2560,1369}}) do
    getCore=function() return {getScreenWidth=function() return size[1] end,getScreenHeight=function() return size[2] end} end
    w,s=open(1231) send(w,1) send(w,1)
    for step=1,5 do
        g=s.lock.story g.step=step G.enter(w) w:drawSecurity()
        local choices={}
        for _,hit in ipairs(w.securityHits) do
            check(hit.x>=w.layout.left and hit.x+hit.width<=w.layout.right+.1 and hit.y>=w:viewTop()
                and hit.y+w.rowHeight<=w:viewBottom()+.1,"story hits never overlap the input or leave the screen")
            if hit.value:match("^[1-3]$") then choices[hit.value]=true end
        end
        local _,_,_,_,available=SC.TerminalLockUI.storyParts(w)
        if available>=4 then check(choices["1"] and choices["2"] and choices["3"],"all three choices stay visible while the scene scrolls") end
        local max=SC.TerminalLockUI.rowCount(w) w:scrollBy(-10000) w:drawSecurity()
        check(w.securityScroll<=max,"compact scenes remain scrollable")
    end
    -- No power, ownership or life revalidation can be bypassed with a number.
    pc.index=-1 send(w,1) check(w.closed,"removed machines close rather than accept story input") pc.index=3
end
if SC.Terminal.window then SC.Terminal.window:close() end
ZombRand,ModData,SC.Registry,SC.Community,SC.Factions,SC.Oddballs,isGamePaused,SC.Terminal._clock,Perks,getCore,SandboxVars=
    old.random,old.mod,old.registry,old.community,old.factions,old.oddballs,old.paused,old.clock,old.perks,old.core,old.sandbox
L.reset()
SC_TEST_REPORT=(SC_TEST_REPORT or "").."; Phase 4 story: "..(T.checks-before).." checks passed"
