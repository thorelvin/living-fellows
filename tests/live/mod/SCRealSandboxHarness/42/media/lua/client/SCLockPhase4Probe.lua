-- SPDX-License-Identifier: MIT
-- Explicit cloned-world fixtures. Native actors, font rendering and save data;
-- no gameplay API, random generator, damage or inventory implementation mocked.
local P={} SCRealSandboxHarnessProbes=SCRealSandboxHarnessProbes or {}
SCRealSandboxHarnessProbes.SCLockPhase4Probe=P
local function snapshot(w)
    local SC=SurvivorCompanion local before={}
    for _,r in ipairs(SC.Registry.records()) do if r.recruited and r.actor and SC.ControlUtil.near(r.actor,w.object,12) then
        local a=r.actor before[#before+1]={actor=a,health=a:getBodyDamage():getOverallBodyHealth(),
            order=SC.Commands.peek(a).order,action=SC.ActionSupervisor.current(a),inventory=a:getInventory():getItems():size()}
    end end
    return before
end
local function unchanged(before)
    local SC=SurvivorCompanion
    for _,v in ipairs(before) do local a=v.actor
        assert(v.health==a:getBodyDamage():getOverallBodyHealth() and v.order==SC.Commands.peek(a).order
            and v.action==SC.ActionSupervisor.current(a) and v.inventory==a:getInventory():getItems():size(),
            "fictional story changed a real companion's health, inventory, order or action")
    end
end
local function press(w,n)
    local before=w.system.lock and w.system.lock.kind=="story" and snapshot(w) or {}
    w:setEntryText(tostring(n)) w:entryChanged() unchanged(before)
    w.storyIsolationChecks=(w.storyIsolationChecks or 0)+#before
end
local function open(H,f,kind,seed,saved)
    local SC=SurvivorCompanion
    if SC.Terminal.window then SC.Terminal.window:close() end
    SC.TerminalDrawers.release(f.pc)
    local os=saved and SC.TerminalSystem.normalize(saved) or SC.TerminalSystem.create(seed,"home",false,false,"phase4-native:"..kind..":"..seed)
    if not saved then os.lock.kind=kind os.lock.settled=true os.archive="dispatch_bell" os.lock.realItems=false end
    f.pc:getModData().movableData.LF_LarchOS=os
    assert(SC.Terminal.open(H.player,f.pc),"native "..kind.." did not open")
    f.window=SC.Terminal.window f.window:flush() return f.window.system
end
local function shot(H,name) getCore():TakeFullScreenshot(H.config.run_id.."-lock-phase4-"..name..".png") end
local function finish(H,f,current,setPhase)
    local SC=SurvivorCompanion
    if f.originalResolve then SC.TerminalLockStory.resolve=f.originalResolve end
    for _,actor in ipairs(f.party or {}) do SC.Actor.remove(actor) end
    if SC.Terminal.window then SC.Terminal.window:close() end
    setPhase("finish",current)
end
function P.step(H,current,check,result,setPhase)
    local SC,f=SurvivorCompanion,H.lockProbe local G=SC.TerminalLockStory
    if H.phase=="lock_probe_phase4_begin" then
        SandboxVars.LivingFellows.LockRealItems=false
        -- Observe the genuine resolver synchronously. Delegate the exact original
        -- implementation; no RNG, native method, result or argument is replaced.
        f.originalResolve=G.resolve
        G.resolve=function(w)
            local before=snapshot(w) f.originalResolve(w) unchanged(before)
            f.resolveChecks=(f.resolveChecks or 0)+1
        end
        -- A calm speech/UI fixture only in the disposable clone.
        local zs=getCell():getZombieList()
        for i=zs:size()-1,0,-1 do local z=zs:get(i) if SC.GameplayUtil.distance(z,H.player)<40 then z:removeFromWorld() z:removeFromSquare() end end
        if H.config.lock_phase4_reload=="true" then
            f.progress=assert(f.pc:getModData().LF_LockPhase4,"missing saved native story")
            local os=open(H,f,"story",nil,f.pc:getModData().movableData.LF_LarchOS)
            local g=os.lock.story
            check("phase4_reload_roll",g and g.phase=="rolling" and g.pending.roll==f.progress.roll and g.class==f.progress.class,
                "actual world serialization retains the committed roll and class")
            f.reloaded=true f.reloadHp=g.hp
            setPhase("lock_probe_phase4_play",current) return
        end
        f.party={} f.progress={}
        local os=open(H,f,"word",985)
        f.originalZoom=f.window.textZoom
        setPhase("lock_probe_phase4_grid",current) return
    elseif H.phase=="lock_probe_phase4_grid" then
        if current-H.phaseStartedAt<1400 then return end
        local w=f.window local grid=w:securityGrid() local ok=true
        for _,row in ipairs(w:securityRows()) do if row.grid then
            local _,width=w:securityRowRuns(row) if width>w:transcriptWidth()+.01 then ok=false end
            for _,span in ipairs(row.spans) do
                for _,hit in ipairs(w.securityHits) do if hit.value==span.value then
                    if math.abs(hit.x-w.layout.left-(span.start-1)*grid.width)>.01 or math.abs(hit.width-span.length*grid.width)>.01 then ok=false end
                end end
            end
        end end
        check("phase4_native_fixed_grid_"..(f.smallFont and "small" or "normal"),ok,
            "font="..tostring(w.font).." zoom="..grid.zoom.." equalCell="..grid.width.." screen="..getCore():getScreenWidth().."x"..getCore():getScreenHeight())
        shot(H,f.smallFont and "password-small" or "password-grid")
        if not f.smallFont then
            f.smallFont=true w.textZoom=f.originalZoom*.8 w.securityBoard=nil w.passwordGrid=nil
            setPhase("lock_probe_phase4_grid",current) return
        end
        local hit
        for _,h in ipairs(w.securityHits) do if h.value:match("^[A-Z]+$") and h.value~=w.system.puzzle.answer then hit=h break end end
        assert(hit,"no native wrong candidate") local tries=w.system.puzzle.tries
        w:onMouseDown(hit.x+hit.width/2,hit.y+w.rowHeight/2)
        check("phase4_native_word_click",w.system.puzzle.tries==tries-1,"fixed-cell hit box invokes exactly one real guess")
        w:close()
        local base=f.pc:getSquare() local spot
        for dx=-3,3 do for dy=-3,3 do
            local sq=getCell():getGridSquare(base:getX()+dx,base:getY()+dy,base:getZ())
            if not spot and SC.GameplayUtil.isClearActorSpawnSquare(sq) and SC.GameplayUtil.distance(sq,H.player)>1 then spot=sq end
        end end
        assert(spot,"no native party fixture square") f.spot=spot
        local why
        f.ticket,why=SC.Actor.beginSpawn(spot,{recruited=true,identity={forename="Ruth",surname="Fielding",gender="woman",outfit="Generic01"}})
        assert(f.ticket,tostring(why))
        setPhase("lock_probe_phase4_party",current) return
    elseif H.phase=="lock_probe_phase4_party" then
        local actor,reason=SC.Actor.pollSpawn(f.ticket)
        if not actor then if reason=="spawn_pending" and current-H.phaseStartedAt<15000 then return end error(tostring(reason)) end
        f.party[#f.party+1]=actor SC.Commands.issue(SC.Registry.idOf(actor),"stay",nil,H.player)
        if #f.party==1 then
            local base=f.pc:getSquare() local spot
            for dx=-3,3 do for dy=-3,3 do
                local sq=getCell():getGridSquare(base:getX()+dx,base:getY()+dy,base:getZ())
                if not spot and sq~=f.spot and SC.GameplayUtil.isClearActorSpawnSquare(sq) and SC.GameplayUtil.distance(sq,H.player)>1 then spot=sq end
            end end
            assert(spot,"no second clear party square")
            local why
            f.ticket,why=SC.Actor.beginSpawn(spot,{recruited=true,identity={forename="Martha",surname="Cole",gender="woman",outfit="Generic01"}})
            assert(f.ticket,tostring(why))
            setPhase("lock_probe_phase4_party",current) return
        end
        f.health={H.player:getBodyDamage():getOverallBodyHealth()}
        for _,a in ipairs(f.party) do f.health[#f.health+1]=a:getBodyDamage():getOverallBodyHealth() end
        open(H,f,"story",987)
        setPhase("lock_probe_phase4_title",current) return
    elseif H.phase=="lock_probe_phase4_title" then
        if current-H.phaseStartedAt<1600 then return end
        check("phase4_native_title",f.window.lockArtDrawn and f.window.lockArtDrawn.StoryTitle,"original shareware art uses the native phosphor renderer")
        shot(H,"title") press(f.window,1)
        local g=f.window.system.lock.story
        check("phase4_native_party",#g.party==2 and g.party[1].id~=g.party[2].id,"two actual recruited nearby companions join only the fiction")
        setPhase("lock_probe_phase4_intro",current) return
    elseif H.phase=="lock_probe_phase4_intro" then
        if current-H.phaseStartedAt<1400 then return end
        local w=f.window local g=w.system.lock.story
        check("phase4_native_class_art",w.lockArtDrawn and w.lockArtDrawn[G.class(g.class).art],"class portrait loads beside readable party text")
        shot(H,"party") press(w,1)
        setPhase("lock_probe_phase4_play",current) return
    elseif H.phase=="lock_probe_phase4_play" then
        if current-H.phaseStartedAt<250 then return end
        local w=f.window local os=w.system local g=os.lock.story
        if g.phase=="scene" then
            if not f.sceneShot then
                f.sceneAt=f.sceneAt or current
                if current-f.sceneAt<1500 then return end
                f.sceneShot=true shot(H,"scene")
            end
            press(w,G.best(g))
            if g.phase=="rolling" and not f.progress.story and not f.reloaded then
                f.progress.story=SC.TerminalSystem.normalize(os) f.progress.roll=g.pending.roll f.progress.class=g.class
                f.pc:getModData().LF_LockPhase4=f.progress
                check("phase4_pending_committed",f.progress.story.lock.story.pending.roll>=1,"roll receipt saved before any result is applied")
            end
        elseif g.phase=="rolling" then return
        elseif g.phase=="result" then
            if f.reloaded and not f.reloadApplied then
                local r=g.last local before=f.reloadHp
                check("phase4_reload_once",g.hp==math.max(0,math.min(g.maxHp,before+r.delta)) and r.roll==f.progress.roll,
                    "saved roll resolves once, with its exact saved outcome") f.reloadApplied=true
            end
            if not f.rollShot and g.last.roll then f.rollShot=true shot(H,"dice-result") end
            press(w,1)
        elseif g.phase=="dead" then
            f.failed=(f.failed or 0)+1 check("phase4_native_death_"..f.failed,#os.lock.fame<=8 and g.deathCount==f.failed,"real choices can die and immediately retry without a clock lockout")
            assert(f.failed<20,"sensible play failed twenty live runs") press(w,1) press(w,1)
        elseif g.phase=="win" then
            if not f.winAt then f.winAt=current return end
            if current-f.winAt<1500 then return end
            check("phase4_native_owner",w.lockArtDrawn and w.lockArtDrawn.StoryOwner and G.lines(w)[2]:find("LEONARD BELL",1,true),"final office names the machine's real archived owner")
            shot(H,"victory")
            if not f.reloaded then
                -- Explicit prerequisite fixture for the final award. The other
                -- eight puzzles have separate acceptance runs; do not claim a
                -- whole-world nine-puzzle tour from this fixture.
                local ledger=SC.TerminalLocks.ledger() ledger.licensee=nil
                for _,kind in ipairs(SC.TerminalLocks.KINDS) do if kind~="story" then ledger.beaten[kind]=true ledger.seen[kind]=true end end
            end
            press(w,1)
            check("phase4_native_unlock",not os.locked and os.xpAwarded and os.lock.rewardTier==3,"normal UI completes shared XP and rare reward path")
            setPhase(not f.reloaded and "lock_probe_phase4_certificate" or "lock_probe_phase4_done",current) return
        end
        setPhase("lock_probe_phase4_play",current) return
    elseif H.phase=="lock_probe_phase4_certificate" then
        if current-H.phaseStartedAt<900 then return end
        local ledger=SC.TerminalLocks.ledger()
        check("phase4_native_license",ledger.licensee==H.player:getDescriptor():getForename():upper()
            and f.window.lockArtDrawn and f.window.lockArtDrawn.RecoveryLicense,
            "real story win completes the explicitly seeded prerequisite ledger and displays the named certificate")
        shot(H,"licensed") setPhase("lock_probe_phase4_done",current) return
    elseif H.phase=="lock_probe_phase4_done" then
        if f.window.payoff then return end
        if not f.reloaded then
            local okay=f.window.storyIsolationChecks and f.window.storyIsolationChecks>=10 and (f.resolveChecks or 0)>=5
            for i,a in ipairs(f.party) do
                print("SC_REAL_SANDBOX|PHASE4_ACTOR_AFTER|"..a:getDescriptor():getForename().." health="..a:getBodyDamage():getOverallBodyHealth()
                    .." order="..tostring(SC.Commands.peek(a).order).." action="..tostring(SC.ActionSupervisor.current(a)))
            end
            check("phase4_fiction_isolation",okay,"synchronous before/after checks preserve real health, inventories, orders and action queues; ordinary AI remains active between inputs")
            open(H,f,"story",1109) press(f.window,1) press(f.window,1)
            setPhase("lock_probe_phase4_checkpoint",current) return
        end
        finish(H,f,current,setPhase) return
    elseif H.phase=="lock_probe_phase4_checkpoint" then
        local w=f.window local g=w.system.lock.story
        if g.phase=="scene" then press(w,G.best(g))
        elseif g.phase=="result" then press(w,1)
        elseif g.phase=="dead" then press(w,1) press(w,1) end
        if g.phase=="rolling" then
            f.pc:getModData().LF_LockPhase4={roll=g.pending.roll,class=g.class}
            check("phase4_actual_pending_save",f.pc:getModData().movableData.LF_LarchOS==w.system,
                "leave the real primary PC state mid-roll, close its window and save; no restored snapshot is substituted on reload")
            finish(H,f,current,setPhase) return
        end
    end
end
return P
