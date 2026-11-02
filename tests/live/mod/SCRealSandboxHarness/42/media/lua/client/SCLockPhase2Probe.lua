-- SPDX-License-Identifier: MIT
-- Native UI, physical handbook and serializable progress fixtures. No API mocks.
local Probe={}
SCRealSandboxHarnessProbes=SCRealSandboxHarnessProbes or {}
SCRealSandboxHarnessProbes.SCLockPhase2Probe=Probe
local function send(w,text) w:setEntryText(text) w:submit() end
local function press(w,number) w:setEntryText(tostring(number)) w:entryChanged() end
local function shot(H,name) getCore():TakeFullScreenshot(H.config.run_id.."-lock-phase2-"..name..".png") end
local function open(H,f,kind,seed,saved)
    local SC=SurvivorCompanion
    if SC.Terminal.window then SC.Terminal.window:close() end
    SC.TerminalDrawers.release(f.pc)
    local state=saved and SC.TerminalSystem.normalize(saved)
        or SC.TerminalSystem.create(seed,"police",false,false,"phase2-native:"..kind..":"..seed)
    if not saved then state.archive="dispatch_bell" state.lock.kind=kind state.lock.settled=true end
    f.pc:getModData().movableData.LF_LarchOS=state
    assert(SC.Terminal.open(H.player,f.pc),"native "..kind.." page did not open")
    f.window=SC.Terminal.window f.window:flush()
    return f.window.system
end
local function choose(w)
    local SC=SurvivorCompanion local E=SC.TerminalLockEmma local facts=E.facts(w)
    local weak,hard=E.temperament(w.system) local best,score
    for index,offer in ipairs(w.system.lock.emma.offers or {}) do
        local a=E.argument(offer.id) local actual=a.claim and facts[a.claim]
        local valid=not a.claim or type(actual)=="boolean" and actual or type(actual)=="number" and (offer.truthful or offer.number==actual)
        local value=valid and (a.kind==weak and 2 or a.kind==hard and -1 or 1) or -2
        if not score or value>score then best,score=index,value end
    end
    return best
end
local function click(w,value)
    for _,hit in ipairs(w.securityHits or {}) do
        if hit.value==value then w:onMouseDown(hit.x+hit.width/2,hit.y+(hit.height or w.rowHeight)/2) return true end
    end
    return false
end
local function finish(H,f,current,setPhase)
    if f.helper then SurvivorCompanion.Actor.remove(f.helper) f.helper=nil end
    if SurvivorCompanion.Terminal.window then SurvivorCompanion.Terminal.window:close() end
    setPhase("finish",current)
end
function Probe.step(H,current,check,result,setPhase)
    local SC,f=SurvivorCompanion,H.lockProbe
    if H.phase=="lock_probe_phase2_begin" then
        SandboxVars.LivingFellows.LockRealItems=false
        if H.config.lock_phase2_reload=="true" then
            f.progress=f.pc:getModData().LF_LockPhase2
            assert(f.progress,"no saved native progress marker")
            local book=SC.TerminalLockWheel.carried(H.player)
            check("phase2_reload_manual_id",book and tostring(book:getID())==f.progress.bookId,"the same carried native handbook survives, without recreation")
            local state=open(H,f,"wheel",nil,f.progress.wheel)
            check("phase2_reload_wheel",state.lock.wheel.correct==1 and state.lock.wheel.required==3,"the carried handbook does not shorten an already-started three-challenge save")
            send(f.window,SC.TerminalLockWheel.answer(state)) send(f.window,SC.TerminalLockWheel.answer(state))
            check("phase2_reload_wheel_finish",not state.locked,"saved wheel progress resumes through the normal input route")
            state=open(H,f,"search",nil,f.progress.search)
            check("phase2_reload_search",#state.lock.found==1,"one restored file survives native serialization")
            for _=1,3 do send(f.window,SC.TerminalLockSearch.nextIndex(state)) end
            check("phase2_reload_search_finish",not state.locked,"saved sector recovery can be completed")
            state=open(H,f,"emma",nil,f.progress.emma)
            check("phase2_reload_emma",state.lock.emma.round==1 and state.lock.emma.lie and #state.lock.emma.offers==4,"the recorded lie and current arguments survive")
            local offers=state.lock.emma.offers
            for i,offer in ipairs(offers) do check("phase2_reload_offer_"..i,offer.id==f.progress.emma.lock.emma.offers[i].id,"opening does not reroll an argument") end
            for _=1,4 do if not state.locked or state.lock.emma.retryUntil then break end press(f.window,choose(f.window)) end
            check("phase2_reload_emma_finish",not state.locked,"saved argument progress finishes without a parser or reset")
            finish(H,f,current,setPhase) return
        end
        f.progress={}
        local state=open(H,f,"wheel",103)
        local book=SC.TerminalLockWheel.nearby(H.player)
        check("phase2_manual_native_item",book and book:getFullType()==SC.TerminalLockWheel.ITEM and math.abs(book:getWeight()-.3)<.001,
            "native handbook; spawnId="..tostring(state.lock.manualItemId).." factory="..type(instanceItem).." player="..H.player:getX()..","..H.player:getY())
        assert(book,"physical handbook was not placed") f.book=book f.progress.bookId=tostring(book:getID())
        check("phase2_manual_world_receipt",state.lock.manualSpawned and state.lock.manualItemId==f.progress.bookId and book:getWorldItem()~=nil,"once-only spawn records the real world item")
        press(f.window,1)
        check("phase2_manual_number_key",f.window.lockPage=="manual","one number opens the nearby physical manual without Enter")
        setPhase("lock_probe_phase2_manual_picture",current) return
    elseif H.phase=="lock_probe_phase2_manual_picture" then
        if current-H.phaseStartedAt<1200 then return end
        check("phase2_manual_cover_native",f.window.lockArtDrawn and f.window.lockArtDrawn.ManualCover,"generated manual cover draws in the active CRT theme")
        shot(H,"manual") press(f.window,4)
        setPhase("lock_probe_phase2_wheel_picture",current) return
    elseif H.phase=="lock_probe_phase2_wheel_picture" then
        if current-H.phaseStartedAt<1200 then return end
        shot(H,"wheel")
        check("phase2_wheel_live_vectors",f.window.lockWheelGeometry and f.window.lockArtDrawn.WheelCentre,"live rings, pointer and hub draw together")
        local wheel=f.window.system.lock.wheel local before=wheel.rotation
        f.window:onMouseWheel(1) f.window:otherKey(Keyboard.KEY_LEFT)
        check("phase2_wheel_native_controls",wheel.rotation==before,"mouse wheel and arrow keys operate the same rotation")
        f.originalTheme=f.window.system.theme f.themeIndex=1
        f.window.system.theme="green" f.window.colors=SC.TerminalPresentation.colors("green")
        setPhase("lock_probe_phase2_theme",current) return
    elseif H.phase=="lock_probe_phase2_theme" then
        if current-H.phaseStartedAt<500 then return end
        local themes={"green","sand","aqua","purple"}
        local theme=themes[f.themeIndex]
        shot(H,"wheel-"..theme)
        f.themeIndex=f.themeIndex+1
        if themes[f.themeIndex] then
            f.window.system.theme=themes[f.themeIndex] f.window.colors=SC.TerminalPresentation.colors(themes[f.themeIndex])
            setPhase("lock_probe_phase2_theme",current) return
        end
        f.window.system.theme=f.originalTheme f.window.colors=SC.TerminalPresentation.colors(f.originalTheme)
        check("phase2_native_themes",f.window.lockWheelGeometry~=nil,"four native phosphor-theme draws completed with live glyphs")
        setPhase("lock_probe_phase2_align",current) return
    elseif H.phase=="lock_probe_phase2_align" then
        local state=f.window.system local c=SC.TerminalLockWheel.challenge(state)
        local target=SC.TerminalLockWheel.rotationFor(c)
        for _=1,26 do if state.lock.wheel.rotation==target then break end f.window:onMouseWheel(1) end
        f.windowValue="answer "..SC.TerminalLockWheel.read(target,c.window)
        setPhase("lock_probe_phase2_window_click",current) return
    elseif H.phase=="lock_probe_phase2_window_click" then
        if current-H.phaseStartedAt<200 then return end
        check("phase2_window_click",click(f.window,f.windowValue),"the requested live window has an actual clickable answer")
        local state=f.window.system
        if state.lock.wheel.correct==1 then f.progress.wheel=SC.TerminalSystem.normalize(state) end
        if state.locked then setPhase("lock_probe_phase2_align",current) return end
        check("phase2_wheel_three",state.lock.wheel.correct==3 and state.xpAwarded,"three genuine wheel challenges complete the common payoff")
        local world=f.book:getWorldItem()
        world:removeFromWorld() world:removeFromSquare() f.book:setWorldItem(nil) H.player:getInventory():AddItem(f.book)
        check("phase2_manual_pickup_id",tostring(f.book:getID())==f.progress.bookId and f.book:getContainer()==H.player:getInventory(),"physical pickup retains exact handbook identity")
        state=open(H,f,"wheel",105)
        check("phase2_manual_reuse",state.lock.wheel.required==1 and not state.lock.manualItemId,"an already carried copy gives one challenge and no extra manual")
        send(f.window,SC.TerminalLockWheel.answer(state))
        check("phase2_wheel_one",not state.locked,"reused manual finishes its one-challenge route")
        open(H,f,"search",109)
        local base=f.pc:getSquare() local spot
        for dx=-3,3 do for dy=-3,3 do
            local tile=getCell():getGridSquare(base:getX()+dx,base:getY()+dy,base:getZ())
            if not spot and SC.GameplayUtil.isClearActorSpawnSquare(tile) then spot=tile end
        end end
        assert(spot,"no native helper standing square")
        f.helperTicket=SC.Actor.beginSpawn(spot,{recruited=true,identity={forename="Ruth",surname="Fielding",gender="woman",outfit="Generic01"}})
        setPhase("lock_probe_phase2_helper_spawn",current) return
    elseif H.phase=="lock_probe_phase2_helper_spawn" then
        local actor,reason=SC.Actor.pollSpawn(f.helperTicket)
        if not actor then if reason=="spawn_pending" and current-H.phaseStartedAt<15000 then return end error(tostring(reason)) end
        f.helper=actor actor:setPerkLevelDebug(Perks.Electricity,10)
        SC.Commands.issue(SC.Registry.idOf(actor),"stay",nil,H.player)
        setPhase("lock_probe_phase2_search_picture",current) return
    elseif H.phase=="lock_probe_phase2_search_picture" then
        if current-H.phaseStartedAt<1200 then return end
        check("phase2_undelete_native_art",f.window.lockArtDrawn and f.window.lockArtDrawn.UndeleteTitle,"UNDELETE title draws beside readable indexes")
        shot(H,"search")
        setPhase("lock_probe_phase2_search_click",current) return
    elseif H.phase=="lock_probe_phase2_search_click" then
        if current-H.phaseStartedAt<200 then return end
        local word=SC.TerminalLockSearch.nextIndex(f.window.system)
        check("phase2_search_index_click",click(f.window,word),"the next archive index can be followed with the mouse")
        local state=f.window.system
        if #state.lock.found==1 then
            f.progress.search=SC.TerminalSystem.normalize(state)
            send(f.window,"%")
            check("phase2_search_junk",#state.lock.found==1 and f.window.securityMessage:find("Too many sectors",1,true),"malformed query does not alter progress or execute a pattern")
            if not f.hintDone then setPhase("lock_probe_phase2_search_hint",current) return end
        end
        if state.locked then setPhase("lock_probe_phase2_search_click",current) return end
        check("phase2_search_restored",#state.lock.found==4 and state.xpAwarded,"all four real owner files restored")
        local selected
        for seed=1,64 do
            local s=SC.TerminalSystem.create(seed,"police",false,false,"emma-seed-fixture") s.lock.kind="emma"
            local test={system=s,player=H.player}
            for _,offer in ipairs(SC.TerminalLockEmma.offers(test)) do
                local a=SC.TerminalLockEmma.argument(offer.id)
                if (a.claim=="days" or a.claim=="people" or a.claim=="electrical") and not offer.truthful then selected=seed break end
            end
            if selected then break end
        end
        assert(selected,"no bounded numeric-claim fixture found")
        open(H,f,"emma",selected)
        setPhase("lock_probe_phase2_emma_picture",current) return
    elseif H.phase=="lock_probe_phase2_search_hint" then
        if not f.hintCalmPrepared then
            -- A speech-only hint requires a calm speaker. Loaded indoor zombies
            -- vary between clones; make this population fixture explicit rather
            -- than weakening perception or replacing the native speech gates.
            local zombies=getCell():getZombieList() local removed=0
            assert(zombies:size()<=4096,"hint fixture exceeded its population bound")
            for i=zombies:size()-1,0,-1 do
                local zombie=zombies:get(i) local dx,dy=zombie:getX()-H.player:getX(),zombie:getY()-H.player:getY()
                if dx*dx+dy*dy<=1600 then zombie:removeFromWorld() zombie:removeFromSquare() removed=removed+1 end
            end
            check("phase2_hint_calm_fixture",true,"removed "..removed.." nearby native zombies in the disposable hint scene; perception and speech gates unchanged")
            f.hintCalmPrepared=true
        end
        local helper=SC.TerminalLockCrew.helper(f.window)
        if not helper or not SC.Banter.budgetAllows(current) then
            if not f.hintDiagnosticAt or current-f.hintDiagnosticAt>=10000 then
                f.hintDiagnosticAt=current
                local actor=f.helper local U=SC.GameplayUtil local record
                for _,candidate in ipairs(SC.Registry.records()) do if candidate.actor==actor then record=candidate break end end
                local senses=record and record.runtime and record.runtime.senses
                local snapshot=senses and senses.current or record and record.runtime and record.runtime.snapshot
                print("SC_LOCK_HINT_DIAGNOSTIC|helper="..tostring(helper).." budget="..tostring(SC.Banter.budgetAllows(current))
                    .." valid="..tostring(U.isValidActor(actor)).." dead="..tostring(U.isDead(actor)).." asleep="..tostring(actor:isAsleep())
                    .." fatigue="..tostring(U.characterStatValue(actor,"FATIGUE",-1)).." distance="..tostring(U.distance(actor,H.player))
                    .." floor="..tostring(U.sameFloor(actor,H.player)).." skill="..tostring(SC.ControlUtil.skill(actor)).." playerSkill="..tostring(SC.ControlUtil.skill(H.player))
                    .." recruited="..tostring(SC.Commands.peek(actor).recruited).." action="..tostring(SC.ActionSupervisor.current(actor))
                    .." spokenAge="..tostring(current-SC.Dialogue.lastSpokenAt(actor)).." threats="..tostring(snapshot and snapshot.threatCount)
                    .." pressure="..tostring(snapshot and snapshot.pressure).." topic="..tostring(SC.Dialogue.lastSpokenTopic(actor)))
            end
            if current-H.phaseStartedAt<60000 then return end
        end
        local word=SC.TerminalLockSearch.nextIndex(f.window.system)
        SC.TerminalLockCrew.hint(f.window)
        local lock=f.window.system.lock
        check("phase2_native_spoken_hint",lock.crewHint and lock.crewClue and lock.crewClue.value==word
            and SC.Dialogue.has("terminal.lock.hint.search"),"a real higher-skilled companion speaks the actual next index")
        check("phase2_hint_no_task",SC.Commands.peek(f.helper).order=="stay" and SC.ActionSupervisor.current(f.helper)==nil,
            "the hint changes neither orders nor action ownership")
        f.progress.search=SC.TerminalSystem.normalize(f.window.system) f.hintDone=true
        setPhase("lock_probe_phase2_search_click",current) return
    elseif H.phase=="lock_probe_phase2_emma_picture" then
        if current-H.phaseStartedAt<1200 then return end
        shot(H,"emma")
        local e=f.window.system.lock.emma local picked
        for index,offer in ipairs(e.offers) do
            local a=SC.TerminalLockEmma.argument(offer.id)
            if (a.claim=="days" or a.claim=="people" or a.claim=="electrical") and not offer.truthful then picked=index break end
        end
        assert(picked,"seeded false numeric offer changed")
        press(f.window,picked)
        check("phase2_emma_real_claim",e.round==1 and e.lie and e.lie.actual~=e.lie.claimed and e.patience==1,"a single number chooses and verifies the real claim without Enter")
        f.progress.emma=SC.TerminalSystem.normalize(f.window.system)
        setPhase("lock_probe_phase2_emma_finish",current) return
    elseif H.phase=="lock_probe_phase2_emma_finish" then
        if current-H.phaseStartedAt<250 then return end
        local state=f.window.system
        if state.locked and not state.lock.emma.retryUntil then
            press(f.window,choose(f.window)) setPhase("lock_probe_phase2_emma_finish",current) return
        end
        if not f.emmaWonChecked then
            check("phase2_emma_convinced",not state.locked and state.lock.emma.won and state.xpAwarded,"honest numbered arguments can recover after one caught lie")
            f.emmaWonChecked=true
        end
        if state.locked then finish(H,f,current,setPhase) return end
        if f.window.payoff then return end
        f.window:close() assert(SC.Terminal.open(H.player,f.pc)) f.window=SC.Terminal.window f.window:flush()
        local e=f.window.system.lock.emma
        check("phase2_emma_remembers",e.mentions==1 and e.lie.actual==f.progress.emma.lock.emma.lie.actual
            and e.lie.claimed==f.progress.emma.lock.emma.lie.claimed,"returning to the same computer preserves the actual lie")
        shot(H,"emma-memory")
        f.pc:getModData().LF_LockPhase2=f.progress
        finish(H,f,current,setPhase) return
    end
end
return Probe
