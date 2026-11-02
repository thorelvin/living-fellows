-- SPDX-License-Identifier: MIT
-- Native prerequisite checks, then production Phase 3 acceptance in clones.
local P={} SCRealSandboxHarnessProbes=SCRealSandboxHarnessProbes or {}
SCRealSandboxHarnessProbes.SCLockPhase3Probe=P
local function send(w,text) w:setEntryText(text) w:submit() end
local function open(H,f,kind,seed,saved)
    local SC=SurvivorCompanion
    if SC.Terminal.window then SC.Terminal.window:close() end
    SC.TerminalDrawers.release(f.pc)
    local os=saved and SC.TerminalSystem.normalize(saved) or SC.TerminalSystem.create(seed,"police",false,false,"phase3-native:"..kind..":"..seed)
    if not saved then os.lock.kind=kind os.lock.settled=true os.archive="dispatch_bell" os.lock.realItems=false end
    f.pc:getModData().movableData.LF_LarchOS=os
    assert(SC.Terminal.open(H.player,f.pc),"native "..kind.." did not open")
    f.window=SC.Terminal.window f.window:flush() return f.window.system
end
local function shot(H,name) getCore():TakeFullScreenshot(H.config.run_id.."-lock-phase3-"..name..".png") end
local function finish(H,f,current,setPhase)
    local SC=SurvivorCompanion
    if f.radioListener then Events.OnDeviceText.Remove(f.radioListener) f.radioListener=nil end
    SC.TerminalLockPhone.reset() SC.TerminalLockRadio.reset()
    if SC.Terminal.window then SC.Terminal.window:close() end
    setPhase("finish",current)
end
local function realRival(H,f)
    local SC=SurvivorCompanion
    local definition=SC.Oddballs.definition("fan_corey_biggs")
    for _,g in ipairs(SC.Factions.list(false)) do
        if g.oddball and g.oddball.id==definition.id and g.lifecycle~="destroyed" then
            assert(not (g.recruitment and g.recruitment.joinedActorId),"Corey already recruited in seed fixture")
            g.discovered=false return g
        end
    end
    local x,y,z=H.player:getX(),H.player:getY(),H.player:getZ() local point
    for radius=12,30 do for _,d in ipairs({{radius,0},{-radius,0},{0,radius},{0,-radius}}) do
        local sq=getCell():getGridSquare(math.floor(x+d[1]),math.floor(y+d[2]),math.floor(z))
        if not point and sq and sq:getRoom()==nil and SC.GameplayUtil.isClearActorSpawnSquare(sq) then point={x=sq:getX(),y=sq:getY(),z=sq:getZ()} end
    end end
    assert(point,"no native outdoor rival fixture square")
    local g,reason=SC.Factions.createOddballGroup({kind="roamer",spawn=point,anchor=point,
        house={id="locks-live-corey",anchor=point,bounds={x1=point.x-8,x2=point.x+8,y1=point.y-8,y2=point.y+8,z=point.z},
            interior={point},openings={},roomGroup="outdoor_fixture"}},definition,false)
    assert(g,reason) g.discovered=false return g
end
function P.step(H,current,check,result,setPhase)
    local SC,f=SurvivorCompanion,H.lockProbe
    if H.phase=="lock_probe_phase3_begin" then
        if H.config.lock_phase3_reload=="true" then
            f.progress=assert(f.pc:getModData().LF_LockPhase3,"no native saved progress")
            local os=open(H,f,"phone",nil,f.progress.phone)
            check("phase3_reload_phone",os.lock.heard and os.lock.phone and not SC.TerminalLockPhone.ringing(),"heard internal code and real coordinates survive; calls do not resume")
            send(f.window,SC.TerminalLockPhone.code(os)) check("phase3_reload_phone_finish",not os.locked,"saved heard callback completes")
            os=open(H,f,"radio",nil,f.progress.radio)
            check("phase3_reload_radio",os.lock.serial==f.progress.radio.lock.serial and SC.TerminalLockRadio.heard(os),"escrow serial and native hearing receipt persist")
            send(f.window,SC.TerminalLockRadio.code(os.seed,os.lock.serial)) check("phase3_reload_radio_finish",not os.locked,"saved radio key completes")
            os=open(H,f,"rival",nil,f.progress.rival)
            check("phase3_reload_rival",#os.lock.rival.guesses==1 and os.lock.rival.remainingMs>0,"rival's actual guess and remaining delay survive")
            send(f.window,os.puzzle.answer)
            check("phase3_reload_rival_finish",not os.locked and os.lock.rival.winner=="player","saved race completes normally")
            finish(H,f,current,setPhase) return
        end
        assert(f.phone,"no real phone in native computer building")
        local sq=f.phone:getSquare()
        check("phase3_phone_same_building",sq:getBuildingDef()==f.pc:getSquare():getBuildingDef(),"real phone at "..sq:getX()..","..sq:getY()..","..sq:getZ())
        f.phoneEmitter=getWorld():getFreeEmitter(sq:getX()+.5,sq:getY()+.5,sq:getZ())
        getWorld():takeOwnershipOfEmitter(f.phoneEmitter)
        f.phoneHandle=f.phoneEmitter:playSound("LFPhoneRing")
        check("phase3_native_ring",GameSounds.isKnownSound("LFPhoneRing") and f.phoneHandle~=0,"original ring event handle="..tostring(f.phoneHandle))
        addSound(nil,sq:getX(),sq:getY(),sq:getZ(),18,60)
        local eligible={}
        for _,g in ipairs(SC.Factions.list(false)) do
            local d=type(g.oddball)=="table" and SC.Oddballs.definition(g.oddball.id)
            local p=g.location and g.location.coordinates or g.house and g.house.anchor
            if d and d.recruitment and not g.discovered and g.lifecycle~="destroyed" and p and p.x and p.y then eligible[#eligible+1]=g.id end
        end
        print("SC_PHASE3_CENSUS|eligible="..#eligible.." ids="..table.concat(eligible,","))
        result(#eligible>0 and "PASS" or "SKIP","phase3_seed_real_people","eligible seeded undiscovered groups="..#eligible)
        local inv=H.player:getInventory() f.receiver=inv:AddItem("Base.RadioBlack")
        local data=f.receiver:getDeviceData()
        if not data:getHasBattery() then data:addBattery(inv:AddItem("Base.Battery")) end
        data:setPower(1) data:setChannel(96400) data:setDeviceVolume(1) data:setIsTurnedOn(true)
        H.player:setPrimaryHandItem(f.receiver)
        f.radioListener=function(guid,code,x,y,z,message,device)
            if tostring(message)=="COUNTY KEY ESCROW BINDING 4471" then f.bindingHeard=true end
        end
        Events.OnDeviceText.Add(f.radioListener)
        setPhase("lock_probe_phase3_binding_radio",current) return
    elseif H.phase=="lock_probe_phase3_binding_radio" then
        if current-H.phaseStartedAt<2500 then return end
        f.phoneEmitter:stopAll() getWorld():returnOwnershipOfEmitter(f.phoneEmitter) f.phoneEmitter=nil
        if not f.bindingSent then
            -- Fixed county source, over 2,000 tiles from this real radio.
            getZomboidRadio():SendTransmission(12000,9000,96400,"COUNTY KEY ESCROW BINDING 4471","LF_LOCKRADIO_BINDING","LF_LOCK_BINDING",.8,1,.8,100000,false)
            f.bindingSent=current
        end
        if not f.bindingHeard and current-f.bindingSent<12000 then return end
        check("phase3_plain_radio_fixed_tower",f.bindingHeard==true,"native RadioBlack receives from fixed county source")
        Events.OnDeviceText.Remove(f.radioListener) f.radioListener=nil
        if H.config.lock_phase3_bindings_only=="true" then f.window:close() setPhase("finish",current) return end
        -- Explicit calm population fixture for interactive native action checks.
        local zombies=getCell():getZombieList() local removed=0
        for i=zombies:size()-1,0,-1 do local z=zombies:get(i)
            if (z:getX()-H.player:getX())^2+(z:getY()-H.player:getY())^2<1600 then z:removeFromWorld() z:removeFromSquare() removed=removed+1 end
        end
        print("SC_PHASE3_FIXTURE|calm_scene_removed="..removed)
        f.progress={} open(H,f,"phone",711)
        setPhase("lock_probe_phase3_phone_search",current) return
    elseif H.phase=="lock_probe_phase3_phone_search" then
        if f.window.lockPhoneSearch then return end
        local os=f.window.system
        if not f.phoneSearchChecked then
            check("phase3_actual_phone_search",os.lock.kind=="phone" and os.lock.phone and SC.TerminalLockPhone.resolve(os.lock.phone)==f.phone,"production bounded scan finds the actual same-building telephone")
            f.phoneSearchChecked=true
        end
        assert(os.lock.kind=="phone","real phone not found by production scan")
        if current-H.phaseStartedAt<1500 then return end
        shot(H,"phone")
        send(f.window,"1")
        setPhase("lock_probe_phase3_phone_walk",current) return
    elseif H.phase=="lock_probe_phase3_phone_walk" then
        local ringing=SC.TerminalLockPhone.ringing() if not ringing then return end
        local sq=f.phone:getSquare() local stand
        for _,d in ipairs({{1,0},{0,1},{-1,0},{0,-1}}) do
            local candidate=getCell():getGridSquare(sq:getX()+d[1],sq:getY()+d[2],sq:getZ())
            if candidate and candidate:canReachTo(sq) and SC.GameplayUtil.isSquareFree(candidate) then stand=candidate break end
        end
        assert(stand,"actual phone has no reachable answer square")
        H.player:teleportTo(stand:getX()+.5,stand:getY()+.5,stand:getZ())
        f.window:close()
        check("phase3_ring_closed_crt",SC.TerminalLockPhone.ringing()~=nil,"physical ring continues when CRT is closed")
        setPhase("lock_probe_phase3_phone_context",current) return
    elseif H.phase=="lock_probe_phase3_phone_context" then
        if current-H.phaseStartedAt<300 or not SC.TerminalLockPhone.ringing() then return end
        local context=ISContextMenu.get(0,100,100)
        SC.TerminalLockPhone.context(0,context,{f.phone},false)
        local answer
        for _,option in ipairs(context.options) do if option.name=="Answer the telephone" then answer=option break end end
        local px,py,pz=SC.ControlUtil.position(H.player) local tx,ty,tz=SC.ControlUtil.position(f.phone)
        check("phase3_answer_context",answer~=nil,"native context option; player="..tostring(px)..","..tostring(py)..","..tostring(pz).." phone="..tx..","..ty..","..tz)
        assert(answer,"no answer option") answer.onSelect(answer.target) context:setVisible(false)
        setPhase("lock_probe_phase3_phone_answer",current) return
    elseif H.phase=="lock_probe_phase3_phone_answer" then
        local os=SC.Terminal.peekState(f.pc)
        if not os.lock.heard and current-H.phaseStartedAt<10000 then return end
        if not f.phoneAnsweredAt then
            check("phase3_native_answer_action",os.lock.heard==true and not SC.TerminalLockPhone.ringing(),"native queued handset action records code and stops ring")
        end
        assert(os.lock.heard,"native phone answer did not complete")
        if not f.phoneAnsweredAt then f.phoneAnsweredAt=current return end
        if current-f.phoneAnsweredAt<300 then return end
        shot(H,"phone-answer")
        f.progress.phone=SC.TerminalSystem.normalize(os)
        local sq=f.pc:getSquare()
        H.player:teleportTo(sq:getX()+.5,sq:getY()+1.5,sq:getZ())
        os=open(H,f,"phone",nil,f.progress.phone)
        send(f.window,"999999")
        check("phase3_phone_typed_hint",table.concat(SC.TerminalLockPhone.lines(f.window)," "):find(SC.TerminalLockPhone.code(os),1,true)~=nil,"heard code appears after one wrong typed entry")
        send(f.window,SC.TerminalLockPhone.code(os))
        check("phase3_phone_unlock",not os.locked and os.xpAwarded,"real callback finishes common native payoff")
        os=open(H,f,"radio",719)
        local ledger=SC.TerminalLocks.ledger()
        ledger.radioHeardCount=2 ledger.radioNamed=false -- two prior heard calls, explicit history fixture
        getGameTime():setTimeOfDay(3.01)
        ledger.lastNight=SC.TerminalLockRadio.night(getGameTime():getWorldAgeHours(),getGameTime():getTimeOfDay())-1
        f.radioListener=function(guid,code,x,y,z,message)
            if tostring(guid):find("LF_LOCKRADIO_",1,true)==1 and tostring(message):find("GO TO BED,",1,true)==1 then f.namedHeard=true end
        end
        Events.OnDeviceText.Add(f.radioListener)
        setPhase("lock_probe_phase3_radio_hear",current) return
    elseif H.phase=="lock_probe_phase3_radio_hear" then
        if current-H.phaseStartedAt<1500 then return end
        if not f.radioPicture then shot(H,"radio") f.radioPicture=true end
        if not SC.TerminalLockRadio.heard(f.window.system) or not f.namedHeard then
            if current-H.phaseStartedAt>55000 then error("native escrow key/name not heard; check receiver and pending ledger") end return
        end
        local os=f.window.system local ledger=SC.TerminalLocks.ledger()
        check("phase3_native_escrow_receipt",SC.TerminalLockRadio.heard(os) and ledger.radioHeardCount==3,"plain receiver hears real queued fixed-tower key")
        check("phase3_native_named_third_call",f.namedHeard and ledger.radioNamed,"third heard call ends with actual player's name once")
        f.progress.radio=SC.TerminalSystem.normalize(os)
        send(f.window,SC.TerminalLockRadio.code(os.seed,os.lock.serial))
        check("phase3_radio_unlock",not os.locked and os.xpAwarded,"native-heard typed key unlocks and pays once")
        f.rivalGroup=realRival(H,f)
        check("phase3_real_rival_group",SC.TerminalLockRival.eligible(f.rivalGroup),"authored group="..f.rivalGroup.id.." definition="..f.rivalGroup.oddball.id.." with original native member identity and location")
        local state=SC.TerminalSystem.create(727,"police",false,false,"phase3-rival-win") state.lock.kind="rival" state.lock.settled=true state.lock.rivalGroup=f.rivalGroup.id state.lock.realItems=false
        os=open(H,f,"rival",nil,state)
        send(f.window,os.puzzle.answer)
        check("phase3_player_race_win",not os.locked and f.rivalGroup.discovered and os.lock.rival.winner=="player","player win reveals the exact authored group")
        f.rivalGroup.discovered=false
        state=SC.TerminalSystem.create(733,"police",false,false,"phase3-rival-timed") state.lock.kind="rival" state.lock.settled=true state.lock.rivalGroup=f.rivalGroup.id state.lock.realItems=false
        open(H,f,"rival",nil,state)
        setPhase("lock_probe_phase3_rival_race",current) return
    elseif H.phase=="lock_probe_phase3_rival_race" then
        local os=f.window.system local r=os.lock.rival
        if not f.rivalPicture and current-H.phaseStartedAt>1500 then shot(H,"rival") f.rivalPicture=true end
        if not f.rivalDelayChecked and current-H.phaseStartedAt>14000 then
            check("phase3_native_rival_wait",#r.guesses==0,"USER2 makes no guess in the first fourteen real seconds") f.rivalDelayChecked=true
        end
        if #r.guesses==1 and not f.rivalResumeChecked then
            f.progress.rival=SC.TerminalSystem.normalize(os) f.remaining=r.remainingMs
            f.window:close() setPhase("lock_probe_phase3_rival_closed",current) return
        end
        if not os.locked then
            check("phase3_native_rival_fifth",#r.guesses>=5 and r.winner=="user2","real timed USER2 cannot win before its fifth guess")
            check("phase3_native_rival_result",f.rivalGroup.discovered and SC.TerminalPayoff.rewardTier(os)==2 and os.xpAwarded,"USER2 reveals the correct group with reduced reward")
            setPhase("lock_probe_phase3_rival_result",current) return
        end
    elseif H.phase=="lock_probe_phase3_rival_result" then
        if f.window.payoff or current-H.phaseStartedAt<3500 then return end
        f.window:flush() shot(H,"rival-result")
        f.pc:getModData().LF_LockPhase3=f.progress
        finish(H,f,current,setPhase) return
    elseif H.phase=="lock_probe_phase3_rival_closed" then
        if current-H.phaseStartedAt<2000 then return end
        assert(SC.Terminal.open(H.player,f.pc)) f.window=SC.Terminal.window f.window:flush()
        check("phase3_native_rival_closed_pause",math.abs(f.window.system.lock.rival.remainingMs-f.remaining)<500,"closing the CRT preserves remaining real-time delay")
        f.rivalResumeChecked=true setPhase("lock_probe_phase3_rival_race",current-15000) return
    end
end
return P
