-- SPDX-License-Identifier: MIT
-- A real undiscovered recruitable group, never a fabricated second player.
SurvivorCompanion=SurvivorCompanion or {}
local SC=SurvivorCompanion local R={} SC.TerminalLockRival=R
local function U() return SC.ControlUtil end
function R.position(group)
    return group and (group.location and group.location.coordinates or group.house and group.house.anchor)
end
function R.eligible(group)
    local definition=group and type(group.oddball)=="table" and SC.Oddballs and SC.Oddballs.definition(group.oddball.id)
    local p=R.position(group)
    return definition and definition.recruitment==true and group.discovered~=true and group.lifecycle~="destroyed"
        and not (group.recruitment and group.recruitment.joinedActorId) and p and tonumber(p.x) and tonumber(p.y) and true or false
end
function R.candidates()
    local groups=SC.Factions and SC.Factions.list(false) or {} local found={}
    for i=1,math.min(#groups,256) do if R.eligible(groups[i]) then found[#found+1]=groups[i] end end
    table.sort(found,function(a,b) return a.id<b.id end) return found
end
-- Discovered people still count: discovering a group is not recruiting it.
function R.hasRecruitable()
    local groups=SC.Factions and SC.Factions.list(false) or {}
    for i=1,math.min(#groups,256) do
        local g=groups[i]
        local d=g.oddball and SC.Oddballs and SC.Oddballs.definition(g.oddball.id)
        if d and d.recruitment==true and g.lifecycle~="destroyed" and not (g.recruitment and g.recruitment.joinedActorId) then return true end
    end
    return SC.Oddballs and SC.Oddballs.hasUnseededRecruitable and SC.Oddballs.hasUnseededRecruitable() or false
end
function R.ensure(state,player)
    local lock=state.lock
    if not lock.rivalGroup then
        local groups=R.candidates() if #groups==0 then return false end
        lock.rivalGroup=groups[state.seed%#groups+1].id
    end
    SC.TerminalSystem.ensurePuzzle(state,SC.Terminal.electricalSkill(player))
    lock.rival=lock.rival or {remainingMs=15000,guesses={}}
    return true
end
function R.group(state)
    return SC.Factions and SC.Factions.group(state.lock.rivalGroup)
end
function R.complete(w,winner)
    local r=w.system.lock.rival r.winner=winner
    local group=R.group(w.system) local p=R.position(group)
    if group and group.lifecycle~="destroyed" and p then
        group.discovered=true
        local definition=SC.Oddballs.definition(group.oddball.id)
        local name=definition and definition.identity and definition.identity.forename or "someone"
        name=tostring(name):sub(1,16)
        local x,y=U().position(w.object) local dx,dy=p.x-x,p.y-y
        local distance=math.floor(math.sqrt(dx*dx+dy*dy)/10)*10
        r.message=(winner=="player" and "USER2: ok. you're real. I'm " or "USER2: too slow. door's open anyway. I'm ")..name..". "
            ..SC.TerminalWorld.direction(dx,dy)..", about "..distance.." tiles."
        group.oddball.terminalRace=winner
    else r.message="USER2: connection lost. The recovery line is open." end
end
function R.pick(state)
    local p,r=state.puzzle,state.lock.rival local used={} local observations={}
    for word,n in pairs(p.guessed) do observations[#observations+1]={word,n} used[word]=true end
    for _,guess in ipairs(r.guesses) do observations[#observations+1]={guess.word,guess.likeness} used[guess.word]=true end
    local fits,fallback={},{}
    for _,word in ipairs(p.words) do
        if not used[word] and not p.removed[word] and (word~=p.answer or #r.guesses>=4) then
            fallback[#fallback+1]=word local valid=true
            for _,o in ipairs(observations) do if SC.TerminalSystem.likeness(word,o[1])~=o[2] then valid=false break end end
            if valid then fits[#fits+1]=word end
        end
    end
    local pool=#fits>0 and fits or fallback
    local pick=SC.TerminalSystem.random(state.seed+#r.guesses*929+71)
    if #pool>0 then return pool[pick(#pool)] end
    if #r.guesses>=4 then return p.answer end
    for _,word in ipairs(p.words) do if word~=p.answer then return word end end
end
function R.update(w,now)
    if not w.system.locked or w.system.lock.kind~="rival" then return end
    local previous=w.rivalLastFrame or now w.rivalLastFrame=now
    if w.lockPage or w.state=="booting" or type(isGamePaused)=="function" and isGamePaused() then return end
    if not SC.Terminal.ownsState(w.object,w.system) or not SC.Terminal.powered(w.object) or not SC.Terminal.near(w.player,w.object) then return end
    local r=w.system.lock.rival if not r or r.winner then return end
    local group=R.group(w.system)
    if not group or group.lifecycle=="destroyed" then
        R.complete(w,"user2") r.lost=true SC.TerminalLocks.finishUnlock(w,"rival") return
    end
    r.remainingMs=math.max(0,r.remainingMs-math.max(0,math.min(250,now-previous)))
    if r.remainingMs>0 then return end
    local word=R.pick(w.system) local likeness=SC.TerminalSystem.likeness(word,w.system.puzzle.answer)
    r.guesses[#r.guesses+1]={word=word,likeness=likeness}
    if likeness==6 then R.complete(w,"user2") SC.TerminalLocks.finishUnlock(w,"rival") return end
    local pick=SC.TerminalSystem.random(w.system.seed+#r.guesses*433)
    r.remainingMs=15000+pick(10001)-1
    w.securityMessage="USER2 > "..word..": "..likeness.."/6. "..({"who is this","you're fast","still there?","don't unplug it","one of us gets through"})[(#r.guesses-1)%5+1]
    w.securityBoard=nil
end
function R.lines(state)
    local rows={"USER2 ATTEMPTING ACCESS"} local r=state.lock.rival
    for _,guess in ipairs(r and r.guesses or {}) do rows[#rows+1]="USER2 > "..guess.word.." / "..guess.likeness.."/6" end
    return rows
end
return R
