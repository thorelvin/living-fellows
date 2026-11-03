-- SPDX-License-Identifier: MIT
-- Optional lock dispatch. Nothing here schedules background work.
SurvivorCompanion=SurvivorCompanion or {}
local SC=SurvivorCompanion local L={} SC.TerminalLocks=L
L.WEIGHTS={word=20,remember=27,wheel=15,emma=12,search=10,radio=5,phone=5,rival=3,story=3}
L.KINDS={"word","remember","wheel","emma","search","radio","phone","rival","story"}
L.NAMES={word="Password recovery",remember="Every wrong word remembers",wheel="Larchfield code wheel",
    emma="Talk to EMMA",search="UNDELETE.EXE",radio="County Key Escrow",phone="LARCH/DIAL-BACK",rival="USER2",story="Kobolds of Kentucky"}
local boosts={wheel={retail=true,electronics=true,hardware=true},
    emma={government=true,bank=true,research=true,security=true},
    search={media=true,education=true,clinic=true,home=true},radio={police=true,military=true,government=true,emergency=true,security=true},
    phone={clinic=true,police=true,emergency=true},story={home=true,education=true,entertainment=true}}
local rare={radio=true,phone=true,rival=true,story=true}
local ledgerSource,ledgerCache
function L.ledger()
    if not ModData or type(ModData.getOrCreate)~="function" then return nil end
    local raw=ModData.getOrCreate("LF_LockLedger")
    if raw==ledgerSource then return ledgerCache end
    local V=SC.TerminalLockState
    raw.opened=math.floor(V.number(raw.opened,0,10000000) or 0)
    for _,key in ipairs({"seen","beaten","usedArchives"}) do
        local clean,count,inspected={},0,0
        for id,value in pairs(type(raw[key])=="table" and raw[key] or {}) do
            inspected=inspected+1 if inspected>512 then break end
            local valid=key=="usedArchives" and id~="_factory" and SC.TerminalFiles.get(id) or L.WEIGHTS[id]
            if value==true and valid and count<(key=="usedArchives" and 256 or 9) then clean[id]=true count=count+1 end
        end
        raw[key]=clean
    end
    local drawers,count,inspected={},0,0
    for id,claim in pairs(type(raw.drawers)=="table" and raw.drawers or {}) do
        inspected=inspected+1 if inspected>256 or count>=32 then break end
        local d=type(claim)=="table" and V.location(claim.drawer)
        local pc=type(claim)=="table" and claim.pc
        if V.text(id,96) and type(pc)=="table" and d and V.number(pc.x,0,100000)
            and V.number(pc.y,0,100000) and V.number(pc.z,-32,32) then
            drawers[id]={id=id,pc={x=math.floor(pc.x),y=math.floor(pc.y),z=math.floor(pc.z)},drawer=d} count=count+1
        end
    end
    raw.drawers=drawers
    raw.lastRare=rare[raw.lastRare] and raw.lastRare or nil
    raw.licensee=V.text(raw.licensee,64)
    if SC.TerminalLockRadio then SC.TerminalLockRadio.normalize(raw) end
    if SC.TerminalPersonaDiscovery then SC.TerminalPersonaDiscovery.normalizeLedger(raw) end
    ledgerSource,ledgerCache=raw,raw
    return raw
end
function L.kind(state)
    local kind=state and state.lock and state.lock.kind
    return (kind=="persona" or L.WEIGHTS[kind]) and kind or "word"
end
function L.choose(seed,ledger,machineKind,available)
    available=available or {phone=true,rival=true}
    local function can(kind) return kind~="phone" and kind~="rival" or available[kind]==true and (kind~="phone" or machineKind~="home" and machineKind~="agriculture") end
    local pick=SC.TerminalSystem.random(seed) pick(2147483646) pick(2147483646)
    local n=ledger.opened+1
    if n==1 then return "remember" elseif n==2 then return "word" end
    local unseen={}
    for _,kind in ipairs(L.KINDS) do
        if not ledger.seen[kind] and can(kind) and (n~=3 or kind=="wheel" or kind=="emma" or kind=="search") then unseen[#unseen+1]=kind end
    end
    if n>=5 and n<17 and not ledger.seen.phone and can("phone") then return "phone" end
    if n<17 and #unseen>0 then
        if n%2==0 then return pick(100)<=40 and "word" or "remember" end
        return unseen[pick(#unseen)]
    end
    local rows,total={},0
    for _,kind in ipairs(L.KINDS) do
        local weight=can(kind) and L.WEIGHTS[kind]*(boosts[kind] and boosts[kind][machineKind] and (kind=="story" and 3 or 2) or 1) or 0
        if rare[kind] and (not ledger.seen[kind] or not (ledger.beaten and ledger.beaten[kind])) then weight=weight*3 end
        total=total+weight rows[#rows+1]={kind=kind,limit=total}
    end
    local roll=pick(total)
    for _,row in ipairs(rows) do if roll<=row.limit then return rare[row.kind] and ledger.lastRare==row.kind and "word" or row.kind end end
end
function L.markSeen(state)
    local ledger=L.ledger() local lock=state.lock
    if ledger and L.WEIGHTS[lock.kind] and not lock.legacy and not lock.classic and not lock.seenRecorded then
        ledger.seen[lock.kind]=true lock.seenRecorded=true
        if rare[lock.kind] then ledger.lastRare=lock.kind end
    end
end
local function owner(state,ledger)
    if not ledger.usedArchives[state.archive] then ledger.usedArchives[state.archive]=true return end
    local current=SC.TerminalFiles.get(state.archive) local pool={}
    for _,profile in ipairs(SC.TerminalFiles.all()) do
        if current and profile.kind==current.kind and not ledger.usedArchives[profile.id] then pool[#pool+1]=profile end
    end
    if #pool==0 and current and (current.kind=="office" or current.kind=="general") then
        for _,profile in ipairs(SC.TerminalFiles.all()) do
            if (profile.kind=="office" or profile.kind=="general") and not ledger.usedArchives[profile.id] then pool[#pool+1]=profile end
        end
    end
    if #pool>0 then state.archive=pool[(state.seed%#pool)+1].id end
    ledger.usedArchives[state.archive]=true
end
local function prepare(state,player,object)
    local lock=state.lock local kind=L.kind(state)
    if kind=="remember" then SC.TerminalLockWords.ensure(state,SC.Terminal.electricalSkill(player))
    elseif kind=="wheel" then SC.TerminalLockWheel.ensure(state,player,object)
    elseif kind=="emma" then SC.TerminalLockEmma.ensure(state)
    elseif kind=="story" then SC.TerminalLockStory.ensure(state)
    elseif kind=="search" and SC.TerminalLockSearch.ensure(state) then
        -- Archive indexes are fixed; no sector search runs while drawing.
    elseif kind=="phone" or kind=="radio" then
        -- Phone is provisional until the bounded in-window search succeeds.
    elseif kind=="rival" and SC.TerminalLockRival.ensure(state,player) then
    else lock.kind="word" SC.TerminalSystem.ensurePuzzle(state,SC.Terminal.electricalSkill(player)) end
    if lock.kind~="phone" or lock.phone then L.markSeen(state) end
end
function L.prompt(state)
    local kind=L.kind(state)
    return kind=="emma" and "Choose an argument: 1-4." or kind=="search" and "Search a word or click an index."
        or kind=="story" and "Choose an adventure option: 1-3."
        or kind=="wheel" and "Open the manual or type a window letter."
        or (kind=="phone" or kind=="radio") and "Type the six-digit recovery code."
        or "Select or type a displayed word or bracket group."
end
function L.rechoosePhone(w)
    local state=w.system local lock=state.lock
    if lock.kind~="phone" or lock.phone then return false end
    local ledger=L.ledger()
    if ledger and not lock.legacy and not lock.classic then
        -- Reuse this opening's selection slot; a failed line search is not
        -- another computer and must not advance discovery or claim loot again.
        local selection={opened=math.max(0,ledger.opened-1),seen=ledger.seen,
            beaten=ledger.beaten,lastRare=ledger.lastRare}
        local profile=SC.TerminalFiles.get(state.archive)
        lock.kind=L.choose(state.seed,selection,lock.machineKind or profile and profile.kind,
            {phone=false,rival=SC.TerminalLockRival and #SC.TerminalLockRival.candidates()>0})
    else lock.kind="word" end
    prepare(state,w.player,w.object)
    w.lockPage=nil w.lockConfirm=nil w.securityScroll=0 w.securityHits={}
    L.open(w)
    if w.entry then pcall(function() w.entry:setPlaceholderText(L.prompt(state)) end) end
    return true
end
function L.settle(state,player,object,insideCamp)
    if SC.TerminalPersonaDiscovery and SC.TerminalPersonaDiscovery.settle(state,player,object,insideCamp) then return end
    if not state.locked then return end
    state.lock=SC.TerminalLockState.normalize(state.lock,true)
    local lock=state.lock
    if lock.kind=="persona" then
        SC.TerminalPersonaDiscovery.remember(lock.persona.id)
        state.theme=SC.TerminalPersonaData[lock.persona.id].theme
        SC.TerminalDrawers.claim(player,object,state)
        return
    end
    SC.TerminalLockCrack.catchUp(state,SC.ControlUtil.hours(),SC.Terminal.powered(object))
    if lock.legacy and not lock.settled then
        local options=SandboxVars and SandboxVars.LivingFellows or {}
        lock.realItems=options.LockRealItems~=false lock.settled=true
    end
    if lock.kind=="pending" then
        local settings=SandboxVars and SandboxVars.LivingFellows or {}
        local ledger=L.ledger()
        if ledger then owner(state,ledger) end
        if settings.ClassicLocksOnly==true then lock.kind="word" lock.classic=true
        elseif ledger then
            local profile=SC.TerminalFiles.get(state.archive)
            lock.kind=L.choose(state.seed,ledger,lock.machineKind or profile and profile.kind,
                {phone=object and SC.ControlUtil.call(SC.ControlUtil.square(object),"getBuildingDef")~=nil,
                    rival=SC.TerminalLockRival and #SC.TerminalLockRival.candidates()>0})
            -- The debug override is single-use and only active in engine debug.
            if type(isDebugEnabled)=="function" and isDebugEnabled() and SCConfig and L.WEIGHTS[SCConfig.debugLockKind] then
                lock.kind=SCConfig.debugLockKind SCConfig.debugLockKind=nil
            end
            ledger.opened=ledger.opened+1
        else lock.kind="word" lock.legacy=true end
        lock.realItems=settings.LockRealItems~=false lock.settled=true
    end
    prepare(state,player,object)
    if SC.TerminalDrawers then SC.TerminalDrawers.claim(player,object,state) end
end
function L.open(w)
    if SC.TerminalLockPhone then SC.TerminalLockPhone.closeCaption() end
    if L.kind(w.system)=="emma" then SC.TerminalLockEmma.offers(w) end
    if L.kind(w.system)=="phone" then SC.TerminalLockPhone.beginSearch(w) end
    if L.kind(w.system)=="radio" then SC.TerminalLockRadio.register(w.system) end
    if L.kind(w.system)=="story" then SC.TerminalLockStory.ensure(w.system) end
    if SC.TerminalLockUI then
        local art=L.kind(w.system)=="search" and "UndeleteTitle" or L.kind(w.system)=="wheel" and "ManualCover"
            or L.kind(w.system)=="phone" and "DialBackTitle" or L.kind(w.system)=="radio" and "CountyKeyEscrow" or L.kind(w.system)=="rival" and "User2Sign" or L.kind(w.system)=="story" and "StoryTitle"
        if art then SC.TerminalLockUI.preload(art) end
    end
end
function L.record(window,raw,result)
    local lock=window.system.lock if not lock then return end
    lock.attempts=lock.attempts or {}
    local descriptor=SC.ControlUtil.call(window.player,"getDescriptor")
    local name=SC.ControlUtil.call(descriptor,"getForename") or "Operator"
    local row={name=tostring(name):sub(1,64),day=math.floor((window.gameHours or 0)/24),guess=tostring(raw):sub(1,96),result=result}
    table.insert(lock.attempts,1,row) while #lock.attempts>6 do table.remove(lock.attempts) end
end
function L.active(w) return w.system and w.system.locked and not w.securityPanel end
function L.input(w,raw,option)
    if not L.active(w) then return false end
    local lower=string.lower(raw:match("^%s*(.-)%s*$"))
    local lock=w.system.lock
    local kind=L.kind(w.system)
    if kind~="word" and kind~="remember" then
        if not SC.Terminal.ownsState(w.object,w.system) or not SC.Terminal.present(w.object)
            or not SC.Terminal.near(w.player,w.object) or not SC.Terminal.powered(w.object)
            or SC.ControlUtil.call(w.player,"isDead")==true then
            if w.close then w:close() end
            return true
        end
    end
    if lower:match("^%d+$") and not w.lockPointerSubmit and type(w.playClickSound)=="function" then w:playClickSound() end
    if not w.lockPage and not w.lockConfirm and (kind=="word" or kind=="remember" or kind=="rival")
        and lower:match("^%d+$") and SC.TerminalLockUI then
        local choice=SC.TerminalLockUI.footer(w)[tonumber(lower)]
        if choice then lower=choice.value raw=choice.value else w.securityMessage="Choose a displayed option." return true end
    end
    if lower=="log off" or lower=="exit" then w:close() return true end
    if kind=="rival" and (lower=="other ways in" or lower=="fine. other ways in." or lower=="bypass"
        or lower=="case" or lower=="open the case" or lower=="crack" or lower=="run crack.exe") then
        w.securityMessage="USER2 is still working. The race opens this machine either way." return true
    end
    if w.lockPage=="logins" then
        if lower=="1" or lower=="back" then w.lockPage=nil w.securityScroll=0 end
        return true
    end
    if lower=="failed logins" then w.lockPage="logins" w.securityScroll=0 return true end
    if w.lockConfirm then
        if lower=="yes" or lower=="y" then lock.bypass=true w.securityMessage="Noted. I note everything."
        elseif lower~="no" and lower~="n" then w.securityMessage="Choose yes or no." return true end
        w.lockConfirm=nil return true
    end
    if lower=="fine. other ways in." or lower=="other ways in" or lower=="bypass" then
        w.lockConfirm=true w.securityMessage="Use another way in? [Y/N]" return true
    end
    if lower=="crack" or lower=="run crack.exe" then
        if lock.bypass then SC.TerminalLockCrack.open(w) else w.securityMessage="Confirm Other ways in first." end
        return true
    end
    if lower=="case" or lower=="open the case" then
        if lock.bypass and SC.TerminalLockCase then SC.TerminalLockCase.open(w) else w.securityMessage="Case recovery is not available yet." end
        return true
    end
    if w.lockPage=="crack" then return SC.TerminalLockCrack.input(w,raw,option) end
    if w.lockPage=="case" and SC.TerminalLockCase then return SC.TerminalLockCase.input(w,raw,option) end
    if lower=="ask for help" and SC.TerminalLockCrew then return SC.TerminalLockCrew.hint(w) end
    local kind=L.kind(w.system)
    if kind=="wheel" then return SC.TerminalLockWheel.input(w,raw) end
    if kind=="search" then return SC.TerminalLockSearch.input(w,raw) end
    if kind=="emma" then return SC.TerminalLockEmma.input(w,raw) end
    if kind=="phone" then return SC.TerminalLockPhone.input(w,raw) end
    if kind=="radio" then return SC.TerminalLockRadio.input(w,raw) end
    if kind=="story" then return SC.TerminalLockStory.input(w,raw) end
    return false
end
function L.afterGuess(w,raw,code)
    if not L.active(w) then return end
    if code=="wrong" or code=="failed" then
        L.record(w,raw,code)
        if code=="failed" and L.kind(w.system)~="rival" then w.system.lock.bypass=true end
        if L.kind(w.system)=="remember" then w.lockMemory=SC.TerminalLockWords.sentence(w.system,string.upper(raw)) end
        if SC.TerminalLockCrew then SC.TerminalLockCrew.react(w,"failure",50) end
    end
end
function L.finishUnlock(w,how)
    if not w or not w.system or not w.system.lock then return false end
    local s=w.system local U=SC.ControlUtil
    if s.lock.unlockApplied then return false end
    local known={word=true,case=true,slip=true,crack=true,crack_early=true,wheel=true,search=true,emma=true,radio=true,phone=true,rival=true,story=true}
    if not known[how] then return false end
    if not SC.Terminal.ownsState(w.object,s) or not SC.Terminal.present(w.object)
        or not SC.Terminal.near(w.player,w.object) or U.call(w.player,"isDead")==true then s.locked=true return false end
    if how~="case" and how~="slip" and not SC.Terminal.powered(w.object) then s.locked=true return false end
    if how=="word" and (not s.puzzle or s.puzzle.guessed[s.puzzle.answer]~=6) then s.locked=true return false end
    if (how=="case" or how=="slip") and not s.lock.caseFinished then return false end
    if how=="crack" and (not s.lock.crack or s.lock.crack.doneHours<s.lock.crack.requiredHours) then return false end
    if how=="crack_early" and not w.crackAnswerVerified then return false end
    if how=="wheel" and (L.kind(s)~="wheel" or not s.lock.wheel or s.lock.wheel.correct<s.lock.wheel.required) then return false end
    if how=="search" and (L.kind(s)~="search" or #(s.lock.found or {})~=4) then return false end
    if how=="emma" and (L.kind(s)~="emma" or not s.lock.emma or not s.lock.emma.won or s.lock.emma.conviction<4) then return false end
    if how=="story" and (L.kind(s)~="story" or not s.lock.story or s.lock.story.phase~="win" or not s.lock.story.won or s.lock.story.hp<=0 or s.lock.story.step~=5) then return false end
    if how=="phone" and (L.kind(s)~="phone" or not s.lock.heard or not w.lockCodeVerified) then return false end
    if how=="radio" and (L.kind(s)~="radio" or not SC.TerminalLockRadio.heard(s) or not w.lockCodeVerified) then return false end
    if how=="rival" and (L.kind(s)~="rival" or not s.lock.rival or s.lock.rival.winner~="user2"
        or not s.lock.rival.lost and (not s.lock.rival.guesses[#s.lock.rival.guesses] or s.lock.rival.guesses[#s.lock.rival.guesses].likeness~=6)) then return false end
    if how=="word" and L.kind(s)=="rival" then SC.TerminalLockRival.complete(w,"player") end
    s.lock.unlockApplied=true
    s.locked=false w.securityHits={} w.lockPage=nil w.lockConfirm=nil
    pcall(function() w.entry:setPlaceholderText("Type a menu number or ask EMMA.") end)
    local ledger=L.ledger()
    if (how=="word" or how=="wheel" or how=="search" or how=="emma" or how=="radio" or how=="phone" or how=="rival" or how=="story") and not s.lock.legacy and ledger then
        ledger.beaten[L.kind(s)]=true ledger.seen[L.kind(s)]=true
        w.licenseAwarded=L.awardLicense(w.player)
    end
    local tier=not s.lock.legacy and (rare[L.kind(s)] and 3 or (L.kind(s)=="wheel" or L.kind(s)=="search" or L.kind(s)=="emma") and 2) or 1
    if how=="case" or how=="crack" or how=="crack_early" then tier=math.max(1,tier-1) end
    local amount=how=="slip" and 0 or ({15,30,60})[tier]
    if how=="rival" then amount=amount/2 end
    s.lock.rewardTier=how=="rival" and math.max(1,tier-1) or tier
    if how=="crack_early" then amount=amount*2 end
    local sensed,threat=pcall(SC.TerminalWorld.nearestThreat,w.player,{},SC.GameplayUtil.nowMs())
    if sensed and threat.distance and threat.distance<=5 then amount=amount*2 w.lockClutch=true end
    SC.Terminal.awardUnlockXP(w.player,w.object,s,amount,how)
    if SC.TerminalPayoff then SC.TerminalPayoff.begin(w,how) else w:startEmma() end
    return true
end
function L.requiredKinds()
    local result={}
    for _,kind in ipairs(L.KINDS) do
        if kind~="rival" or not SC.TerminalLockRival or SC.TerminalLockRival.hasRecruitable() then result[#result+1]=kind end
    end
    return result
end
function L.awardLicense(player)
    local ledger=L.ledger() if not ledger or ledger.licensee then return false end
    for _,kind in ipairs(L.requiredKinds()) do if not ledger.beaten[kind] then return false end end
    local desc=SC.ControlUtil.call(player,"getDescriptor")
    local name=SC.TerminalLockState.text(SC.ControlUtil.call(desc,"getForename"),64)
    if not name or name=="" then return false end
    ledger.licensee=name:upper() return true
end
function L.recovery(player)
    if player then L.awardLicense(player) end
    local ledger=L.ledger() local names={} local beaten=0
    local target=#L.requiredKinds()
    for _,kind in ipairs(L.KINDS) do
        if ledger and ledger.beaten[kind] and (kind~="rival" or target==#L.KINDS) then beaten=beaten+1 end
        if ledger and ledger.seen[kind] then names[#names+1]=L.NAMES[kind]..(ledger.beaten[kind] and " / recovered" or " / not recovered") end
    end
    local note=SC.TerminalPersonaDiscovery and SC.TerminalPersonaDiscovery.recoveryLine()
    return "Recovery log: "..beaten.."/"..target..(ledger and ledger.licensee and ("\nLICENSED TO "..ledger.licensee) or "").."\n"..table.concat(names,"\n")..(note and ("\n"..note) or "")
end
function L.reset() ledgerSource,ledgerCache=nil,nil end
return L
