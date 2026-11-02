-- SPDX-License-Identifier: MIT
-- A saved, fictional shareware adventure. No actor AI, inventory or health writes.
SurvivorCompanion=SurvivorCompanion or {}
local SC=SurvivorCompanion local G={} SC.TerminalLockStory=G
local phases={title=true,intro=true,scene=true,rolling=true,result=true,dead=true,win=true}
local function D() return SC.TerminalLockStoryData end
local function U() return SC.ControlUtil end
function G.class(id) for _,c in ipairs(D().classes) do if c.id==id then return c end end end
function G.scene(id) for _,s in ipairs(D().scenes) do if s.id==id then return s end end end
local function text(value,limit)
    value=tostring(value or ""):gsub("[%c]"," ")
    -- Preserve UTF-8 names: byte limits in persisted fields must not split a codepoint.
    local count,last=0,#value
    for i=1,#value do local b=value:byte(i) if b<128 or b>=192 then count=count+1 if count>(limit or 16) then last=i-1 break end end end
    return value:sub(1,last):upper()
end
function G.fill(line,values)
    return (line:gsub("{([A-Z]+)}",function(key) return tostring(values[key] or "?") end))
end
local function weighted(pick)
    local n=pick(100)
    for _,c in ipairs(D().classes) do n=n-c.weight if n<=0 then return c end end
end
-- A run's fiction is seeded once and saved. Only actual dice throws use live RNG.
function G.plan(seed,run)
    local pick=SC.TerminalSystem.random(seed)
    local c=weighted(pick) local scenes={}
    for slot=1,5 do
        local candidates={}
        for _,s in ipairs(D().scenes) do if s.slot==slot then candidates[#candidates+1]=s.id end end
        scenes[slot]=candidates[pick(#candidates)]
    end
    local pairs={{2,4},{2,5},{3,5}} local rolls=pairs[pick(3)]
    return {schema=1,run=run,class=c.id,seed=seed,scenes=scenes,rolls={rolls[1],rolls[2]},step=1,
        hp=2+c.hp,maxHp=2+c.hp,phase="intro",party={},deathCount=0}
end
function G.ensure(state)
    state.lock.story=state.lock.story or {schema=1,run=0,phase="title",deathCount=0,usedGhosts={}}
    state.lock.fame=state.lock.fame or {}
    return state.lock.story
end
function G.isRoll(g) return g.rolls and (g.rolls[1]==g.step or g.rolls[2]==g.step) end
function G.code(state) return string.format("%06d",(state.seed*37+1993)%1000000) end
function G.context(w)
    local profile=SC.TerminalFiles.get(w.system.archive)
    local room=U().call(U().square(w.object),"getRoom")
    local name=U().call(room,"getName")
    local g=w.system.lock.story local member
    for _,m in ipairs(g and g.party or {}) do if not m.dead then member=m break end end
    member=member or g and g.party and g.party[1]
    return {OWNER=text(profile and profile.owner or "",64),ROOM=text(name or "CELLAR",48),
        COMPANION=member and member.name or D().hireling,
        CLASS=member and G.class(member.class) and G.class(member.class).name or D().hireling_class}
end
local function name(actor)
    return text(SC.TerminalLockCrew.name(actor),16)
end
function G.party(w,pick)
    local found={}
    local records=SC.Registry and SC.Registry.records() or {}
    for i=1,math.min(256,#records) do
        local r=records[i]
        if r.recruited==true and r.actor and r.actor~=w.player and U().call(r.actor,"isDead")~=true
            and U().near(r.actor,w.object,12) and type(r.id)=="string" then
            found[#found+1]={id=r.id,name=name(r.actor)}
        end
    end
    table.sort(found,function(a,b) return a.id<b.id end)
    local party={}
    while #found>0 and #party<2 do
        local member=table.remove(found,pick(#found))
        member.class=weighted(pick).id member.join=pick(#D().party)
        party[#party+1]=member
    end
    if #party==0 then party[1]={name=D().hireling,class="hireling",join=pick(#D().party)} end
    return party
end
function G.best(g,scene)
    scene=scene or G.scene(g.scenes[g.step])
    local best,score=1,-100
    for i,option in ipairs(scene.options) do
        local value=option.result=="good" and 100 or 0
        if G.isRoll(g) then value=value+G.class(g.class).bonus[option.approach]-option.dc end
        if value>score then best,score=i,value end
    end
    return best
end
function G.worst(state)
    local g=G.ensure(state) if g.phase~="scene" then return nil end
    local scene=G.scene(g.scenes[g.step]) local worst,score=nil,100
    for i,o in ipairs(scene.options) do
        local value=(o.result=="good" and 100 or 0)+(G.class(g.class).bonus[o.approach] or 0)-o.dc
        if value<score then worst,score=i,value end
    end
    return tostring(worst),g.step
end
function G.start(w)
    local old=G.ensure(w.system)
    local g=G.plan(ZombRand(2147483646)+1,old.run+1)
    g.deathCount=old.deathCount g.usedGhosts=old.usedGhosts or {}
    local pick=SC.TerminalSystem.random(g.seed+317)
    g.party=G.party(w,pick)
    local used=0 for _ in pairs(g.usedGhosts) do used=used+1 end
    if pick(3)==1 and used<64 then
        local deaths=SC.Community and SC.Community.recentDeaths and SC.Community.recentDeaths(64) or {}
        local candidates={}
        for _,row in ipairs(deaths) do if not g.usedGhosts[row.subjectId] then candidates[#candidates+1]=row end end
        if #candidates>0 then
            local row=candidates[pick(#candidates)]
            g.ghost={id=row.subjectId,name=text(row.subjectDisplayName or row.subjectName,16),step=pick(4)+1,line=pick(#D().ghost),leave=pick(#D().ghost_leave)}
        end
    end
    g.finale=pick(#D().finale) g.gameOver=pick(#D().game_over)
    w.system.lock.story=g w.securityScroll=0 w.securityMessage=nil
    return g
end
function G.enter(w)
    local g=G.ensure(w.system) g.phase="scene" w.securityScroll=0
    if g.ghost and g.ghost.step==g.step then
        g.ghost.choice=G.best(g) g.usedGhosts[g.ghost.id]=true
    end
end
-- Pure result accounting is shared by the UI and the difficulty simulation.
function G.outcome(g,option,roll,skill)
    local c=G.class(g.class) local good=option.result=="good"
    local bonus=c.bonus[option.approach]+((skill or 0)>=3 and 2 or 0)
    local message,delta
    if roll==20 then good=true delta=1 message=D().crits[c.id].twenty
    elseif roll==1 then good=false delta=-2 message=D().crits[c.id].one
    else
        if roll then good=roll+bonus>=option.dc end
        delta=good and 0 or -option.damage message=good and option.good or option.bad
    end
    return {good=good,text=message,delta=delta,roll=roll,dc=option.dc,bonus=bonus}
end
local function values(g,member)
    return {COMPANION=member.name,CLASS=member.class=="hireling" and D().hireling_class or G.class(member.class).name}
end
function G.resolve(w)
    local g=G.ensure(w.system) local p=g.pending if not p then return end
    local scene=G.scene(g.scenes[g.step])
    local result=G.outcome(g,scene.options[p.option],p.roll,p.skill)
    result.text=G.fill(result.text,G.context(w))
    g.hp=math.max(0,math.min(g.maxHp,g.hp+result.delta))
    -- Commit result before reactions; retry/reload cannot apply it twice.
    g.pending=nil g.last=result g.phase="result" w.securityScroll=0
    local pick=SC.TerminalSystem.random(g.seed+g.step*713)
    if not result.good and not g.partyDeath and not g.ghost then
        local member=g.party[pick(#g.party)] member.dead=true g.partyDeath=true
        result.party=G.fill(D().deaths[pick(#D().deaths)],values(g,member))
        if member.id then SC.TerminalLockCrew.storyReact(w,member.id,"storyDeath") end
    end
    if g.ghost and g.ghost.step==g.step then result.ghost=G.fill(D().ghost_leave[g.ghost.leave],{NAME=g.ghost.name}) end
    -- Reuse the real, bounded lock sensor. No world scan is added here.
    local threat=w.lockThreat
    if g.hp>0 and g.step<5 and threat and not threat.unknown and not threat.partial
        and type(threat.distance)=="number" and threat.distance<=6 then
        result.noise=D().scratching[pick(#D().scratching)]
    end
    if g.hp<=0 then
        g.deathCount=math.min(1000000,g.deathCount+1)
        local desc=U().call(w.player,"getDescriptor")
        local line=G.fill(D().fame,{NAME=text(U().call(desc,"getForename") or "OPERATOR",16),CLASS=G.class(g.class).name,N=g.step})
        table.insert(w.system.lock.fame,1,line) while #w.system.lock.fame>8 do table.remove(w.system.lock.fame) end
        if g.deathCount>=3 then w.system.lock.bypass=true end
    end
end
function G.update(w,now)
    local g=w.system and w.system.lock and w.system.lock.story
    local previous=w.storyLastFrame or now w.storyLastFrame=now
    if not g or g.phase~="rolling" or w.lockPage or w.state=="booting" or not w.system.locked
        or type(isGamePaused)=="function" and isGamePaused() then return end
    if not SC.Terminal.ownsState(w.object,w.system) or not SC.Terminal.near(w.player,w.object) or not SC.Terminal.powered(w.object) then return end
    g.pending.remainingMs=math.max(0,g.pending.remainingMs-math.max(0,math.min(250,now-previous)))
    if g.pending.remainingMs==0 then G.resolve(w) end
end
function G.input(w,raw)
    local g=G.ensure(w.system) local number=tonumber(raw)
    if g.phase=="title" or g.phase=="dead" then if number==1 then G.start(w) end
    elseif g.phase=="intro" then if number==1 then G.enter(w) end
    elseif g.phase=="scene" and number and number==math.floor(number) and number>=1 and number<=3 then
        g.pending={option=number,skill=SC.Terminal.electricalSkill(w.player)}
        if G.isRoll(g) then
            g.pending.roll=ZombRand(20)+1 g.pending.remainingMs=1000 g.phase="rolling"
            w.storyLastFrame=SC.GameplayUtil.nowMs()
            SC.Terminal.playFeedbackSound("LFDiceRoll")
        else G.resolve(w) end
        w.securityScroll=0
    elseif g.phase=="result" and number==1 then
        if g.hp<=0 then g.phase="dead"
        elseif g.step==5 then
            g.phase="win" g.won=true
            for _,member in ipairs(g.party) do if member.id and not member.dead then SC.TerminalLockCrew.storyReact(w,member.id,"storyWin") break end end
        else g.step=g.step+1 G.enter(w) end
        w.securityScroll=0
    elseif g.phase=="win" and number==1 then SC.TerminalLocks.finishUnlock(w,"story") end
    return true
end
function G.lines(w)
    local g=G.ensure(w.system) local rows={}
    local function add(line) rows[#rows+1]=line end
    if w.securityMessage then add(w.securityMessage) end
    if g.phase=="title" then
        for _,line in ipairs(D().title) do add(line) end
        local profile=SC.TerminalFiles.get(w.system.archive)
        add("") add(G.fill(D().notes[profile and profile.kind] or D().notes.default,G.context(w)))
        add("") add("[1] NEW GAME") return rows
    end
    local c=G.class(g.class)
    add(c.name.." / HP "..g.hp.."/"..g.maxHp.." / SCENE "..g.step.."/5")
    if g.phase=="intro" then
        add(c.intro)
        for _,member in ipairs(g.party) do add(G.fill(D().party[member.join],values(g,member))) end
        add("PARTY ROLES ARE FICTIONAL. YOUR COMPANIONS KEEP THEIR REAL JOBS.") add("[1] ENTER THE DUNGEON")
    elseif g.phase=="scene" then
        local s=G.scene(g.scenes[g.step])
        if G.isRoll(g) then add(D().roll_prompt..(SC.Terminal.electricalSkill(w.player)>=3 and " ELECTRICAL TRAINING: +2." or "")) else add("NO DICE: YOUR CHOICE DECIDES.") end
        if g.ghost and g.ghost.step==g.step and g.ghost.choice then add(G.fill(D().ghost[g.ghost.line],{NAME=g.ghost.name,N=g.ghost.choice})) end
        add(G.fill(s.text,G.context(w)))
        for i,o in ipairs(s.options) do
            local clue=w.system.lock.crewClue
            add("["..i.."] "..G.fill(o.class and o.class[c.id] or o.text,G.context(w))..(clue and clue.kind=="story" and clue.stage==g.step and clue.value==tostring(i) and " [AVOID]" or ""))
        end
    elseif g.phase=="rolling" then
        local face=math.floor((1000-g.pending.remainingMs)/80)%20+1
        add(D().roll_prompt) add("D20 ["..string.format("%02d",face).."] ROLLING...")
    elseif g.phase=="result" then
        local r=g.last
        if r.roll then add(G.fill(D().roll_result,{ROLL=r.roll,DC=math.max(2,r.dc-r.bonus)})) end
        add(r.text)
        if r.party then add(r.party) end if r.ghost then add(r.ghost) end if r.noise then add(r.noise) end
        add(r.delta>0 and "RESTORED 1 HP." or r.delta<0 and ("LOST "..(-r.delta).." HP.") or "NO HP LOST.")
        add("[1] CONTINUE")
    elseif g.phase=="dead" then
        add(D().game_over[g.gameOver])
        for _,line in ipairs(w.system.lock.fame) do add(line) end
        add("[1] NEW ADVENTURER / NO LOCKOUT")
    elseif g.phase=="win" then
        add(G.fill(D().finale[g.finale],G.context(w))) add(D().finale_code)
        add("RESET CODE: "..G.code(w.system)) add("[1] RESTORE ACCESS")
    end
    return rows
end
function G.art(w)
    local g=G.ensure(w.system)
    if g.phase=="title" then return "StoryTitle" end
    if g.phase=="intro" then return G.class(g.class).art end
    if g.phase=="rolling" then return "StoryDice" end
    if g.phase=="dead" then return "StoryGameOver" end
    if g.phase=="win" then return "StoryOwner" end
    if g.ghost and g.ghost.step==g.step then return "StoryGhost" end
    return G.scene(g.scenes[g.step]).art
end
-- Conservative, bounded load validation. No native references are persisted.
function G.normalize(v)
    local V=SC.TerminalLockState
    local function integer(n,a,b) return V.number(n,a,b) and n==math.floor(n) end
    if type(v)~="table" or v.schema~=1 or not phases[v.phase] or not integer(v.run,0,1000000)
        or not integer(v.deathCount,0,1000000) then return nil end
    local g={schema=1,phase=v.phase,run=v.run,deathCount=v.deathCount,usedGhosts={}}
    local count=0
    for id,used in pairs(type(v.usedGhosts)=="table" and v.usedGhosts or {}) do
        count=count+1 if count>64 or not V.text(id,96) or used~=true then return nil end
        g.usedGhosts[id]=true
    end
    if v.phase=="title" then return v.run==0 and g or nil end
    local c=G.class(v.class)
    if not c or not integer(v.seed,1,2147483646) or not integer(v.step,1,5) or v.maxHp~=2+c.hp
        or not integer(v.hp,0,v.maxHp) or not integer(v.finale,1,#D().finale) or not integer(v.gameOver,1,#D().game_over)
        or type(v.scenes)~="table" or #v.scenes~=5 or type(v.rolls)~="table" or #v.rolls~=2 then return nil end
    g.class,g.seed,g.step,g.hp,g.maxHp,g.finale,g.gameOver=v.class,v.seed,v.step,v.hp,v.maxHp,v.finale,v.gameOver
    g.scenes={} for i,id in ipairs(v.scenes) do local s=G.scene(id) if not s or s.slot~=i then return nil end g.scenes[i]=id end
    if not ((v.rolls[1]==2 and (v.rolls[2]==4 or v.rolls[2]==5)) or v.rolls[1]==3 and v.rolls[2]==5) then return nil end
    g.rolls={v.rolls[1],v.rolls[2]} g.party={} g.partyDeath=v.partyDeath==true
    if type(v.party)~="table" or #v.party<1 or #v.party>2 then return nil end
    local ids={} local killed=0
    for _,m in ipairs(v.party) do
        if type(m)~="table" or not V.text(m.name,64) or not integer(m.join,1,#D().party)
            or (m.id~=nil and (not V.text(m.id,96) or ids[m.id])) or not (G.class(m.class) or m.id==nil and m.class=="hireling") then return nil end
        if m.id then ids[m.id]=true end if m.dead then killed=killed+1 end
        g.party[#g.party+1]={id=m.id,name=m.name,class=m.class,join=m.join,dead=m.dead==true}
    end
    if killed>1 or (killed==1)~=g.partyDeath then return nil end
    if v.ghost~=nil then
        local a=v.ghost
        if type(a)~="table" or g.partyDeath or not V.text(a.id,96) or ids[a.id] or not V.text(a.name,64)
            or not integer(a.step,2,5) or not integer(a.line,1,#D().ghost) or not integer(a.leave,1,#D().ghost_leave)
            or a.choice~=nil and not integer(a.choice,1,3) then return nil end
        g.ghost={id=a.id,name=a.name,step=a.step,line=a.line,leave=a.leave,choice=a.choice}
    end
    if v.pending~=nil then
        local p=v.pending
        if type(p)~="table" or v.phase~="rolling" or not G.isRoll(g) or not integer(p.option,1,3)
            or not integer(p.roll,1,20) or not integer(p.skill,0,10) or not V.number(p.remainingMs,0,1000) then return nil end
        g.pending={option=p.option,roll=p.roll,skill=p.skill,remainingMs=p.remainingMs}
    elseif v.phase=="rolling" then return nil end
    if v.last~=nil then
        local r=v.last
        if type(r)~="table" or not V.text(r.text,300) or not integer(r.delta,-2,1)
            or r.roll~=nil and not integer(r.roll,1,20) or not integer(r.dc,1,30) or not integer(r.bonus,-1,10) then return nil end
        g.last={text=r.text,delta=r.delta,good=r.good==true,roll=r.roll,dc=r.dc,bonus=r.bonus,
            party=V.text(r.party,200),ghost=V.text(r.ghost,200),noise=V.text(r.noise,200)}
    elseif v.phase=="result" or v.phase=="dead" or v.phase=="win" then return nil end
    if (v.phase=="dead" and g.hp~=0) or ((v.phase=="scene" or v.phase=="intro" or v.phase=="rolling") and g.hp<=0) then return nil end
    g.won=v.won==true
    if g.won~=(v.phase=="win") or g.won and (g.step~=5 or g.hp<=0 or not g.last or g.last.delta<-2) then return nil end
    return g
end
return G
