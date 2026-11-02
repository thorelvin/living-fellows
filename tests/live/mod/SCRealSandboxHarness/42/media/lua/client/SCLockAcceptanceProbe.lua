-- SPDX-License-Identifier: MIT
-- Real timed actions, furniture, fluids, XP, item identities and screen draws.
-- Program fixtures are named explicitly; no native access function is replaced.
local Probe={}
SCRealSandboxHarnessProbes=SCRealSandboxHarnessProbes or {}
SCRealSandboxHarnessProbes.SCLockAcceptanceProbe=Probe
local function call(o,m,...) return SurvivorCompanion.ControlUtil.call(o,m,...) end
local function shot(H,name) getCore():TakeFullScreenshot(H.config.run_id.."-lock-acceptance-"..name..".png") end
local function send(w,text) w:setFocusMode("chat") w.entry:setText(text) w:submit() end
local function contents(stash)
    local SC=SurvivorCompanion local c=stash and stash.location and SC.TerminalDrawers.container(stash.location)
    if not c then return false end
    local seen={}
    local function collect(container,depth)
        if depth>2 then return end
        for _,item in ipairs(SC.ControlUtil.list(call(container,"getItems"),256)) do
            seen[tostring(call(item,"getID"))]=call(item,"getFullType")
            local bag=call(item,"getInventory") if bag then collect(bag,depth+1) end
        end
    end
    collect(c,0)
    for _,receipt in ipairs(stash.items or {}) do if seen[receipt.id]~=receipt.type then return false end end
    return #stash.items>0
end
local function fresh(H,f,kind,seed)
    local SC=SurvivorCompanion
    if SC.Terminal.window then SC.Terminal.window:close() end
    SC.TerminalDrawers.release(f.pc)
    -- A fresh, documented program fixture on a real native office desktop.
    -- The test still has to solve its puzzle or complete its timed repair.
    local state=SC.TerminalSystem.create(seed,"police",false,false,"lock-test:"..kind..":"..seed)
    state.archive="dispatch_bell" state.lock.kind=kind state.lock.legacy=true
    f.pc:getModData().movableData.LF_LarchOS=state
    assert(SC.Terminal.open(H.player,f.pc),"native program fixture would not open")
    f.window=SC.Terminal.window f.window:flush()
    return f.window.system
end
local function complete(H,f,current,result,setPhase)
    if f.actor then SurvivorCompanion.Actor.remove(f.actor) f.actor=nil end
    if SurvivorCompanion.Terminal.window then SurvivorCompanion.Terminal.window:close() end
    if f.oldGod~=nil then H.player:setGodMod(f.oldGod) end
    if f.oldGhost~=nil then H.player:setGhostMode(f.oldGhost) end
    result("SKIP","lock_acceptance_optional_inventory_mod","Inventory Tetris not enabled; custom-button omission is covered by automated tests")
    result("SKIP","lock_acceptance_future_locks","phone sound and few-day rival census await their later phase checks")
    setPhase("finish",current)
end
function Probe.step(H,current,check,result,setPhase)
    local SC,f=SurvivorCompanion,H.lockProbe
    if H.phase=="lock_probe_accept_begin" then
        local marker=f.pc:getModData().LF_LockAcceptance
        if H.config.lock_acceptance_reload=="true" then
            local state=SC.Terminal.peekState(f.pc)
            if state and state.locked then
                local drawer=state.lock and state.lock.drawer
                local container=drawer and SC.TerminalDrawers.container(drawer)
                check("lock_reload_interlock",container and SC.TerminalDrawers.locked(container)
                    and not drawer.open and not drawer.forced,
                    "a previously saved plain desk remains locked through the persisted ownership ledger")
                check("lock_reload_pending",(state.lock.kind=="remember" or state.lock.kind=="word") and not state.xpAwarded
                    and not state.lock.unlockApplied and #(state.lock.stash and state.lock.stash.items or {})==0,
                    "a pending saved puzzle does not gain XP or reward items on reload; kind="..tostring(state.lock.kind))
                shot(H,"locked-reload")
                local selected
                for seed=1,1000 do
                    if seed%4~=0 and SC.TerminalLockCase.roll({seed=seed})>SC.TerminalLockCase.risk(state,SC.ControlUtil.skill(H.player),true) then selected=seed break end
                end
                fresh(H,f,"word",selected)
                send(f.window,"other ways in") send(f.window,"yes")
                H.player:getInventory():AddItem("Base.Screwdriver") H.player:getInventory():AddItem("Base.ElectronicsScrap")
                f.window:close() f.batteryStarted=SC.ControlUtil.hours()
                local okay,why=SC.TerminalLockCase.queue(H.player,f.pc,true) assert(okay,why)
                setPhase("lock_probe_accept_battery",current) return
            end
            check("lock_reload_receipts",marker and contents(marker),"same native desk contents and exact item IDs survive world save/reload")
            check("lock_reload_program",state and state.lock and state.locked==false and state.xpAwarded==true,"schema-one unlocked state and XP receipt survive")
            complete(H,f,current,result,setPhase) return
        end
        local state=f.window.system
        check("lock_live_director_first",state.locked and state.lock.kind=="remember","first native open chooses the implemented archive lock")
        local wrong
        for _,word in ipairs(state.puzzle.words) do if word~=state.puzzle.answer and SC.TerminalLockWords.sentence(state,word) then wrong=word break end end
        assert(wrong,"archive puzzle has no actual archive decoy")
        local tries=state.puzzle.tries send(f.window,wrong)
        check("lock_live_memory",state.puzzle.tries==tries-1 and f.window.lockMemory~=nil,"wrong archive word recalls a genuine previous-owner sentence")
        shot(H,"remember")
        setPhase("lock_probe_accept_memory_picture",current) return
    elseif H.phase=="lock_probe_accept_battery" then
        local state=SC.Terminal.peekState(f.pc)
        if state.locked and current-H.phaseStartedAt<45000 then return end
        check("lock_live_battery",not state.locked and state.lock.caseFinished and not state.lock.slip,
            "native CMOS battery action completes with files preserved")
        local elapsed=(SC.ControlUtil.hours()-f.batteryStarted)*60
        check("lock_live_battery_delay",elapsed>=5,"native action includes at least five additional game minutes; elapsed="..elapsed)
        complete(H,f,current,result,setPhase) return
    elseif H.phase=="lock_probe_accept_memory_picture" then
        if current-H.phaseStartedAt<1000 then return end
        shot(H,"remember")
        local state=f.window.system
        f.xpBefore=H.player:getXp():getXP(Perks.Electricity)
        send(f.window,state.puzzle.answer)
        check("lock_live_word_unlock",not state.locked and state.xpAwarded and f.window.payoff~=nil,"real word answer enters the one-time payoff")
        setPhase("lock_probe_accept_payoff",current) return
    elseif H.phase=="lock_probe_accept_payoff" then
        if current-H.phaseStartedAt<700 then return end
        if not f.grantedShot then
            check("lock_live_granted_art",f.window.lockArtDrawn and f.window.lockArtDrawn.AccessGranted,
                "the native access stamp is ready during its short payoff moment")
            shot(H,"access-granted") f.grantedShot=true
        end
        if f.window.payoff then return end
        local state=f.window.system
        check("lock_live_welcome",state.lock.welcomed and f.window.session~=nil,"welcome ends at real EMMA session")
        check("lock_live_xp",H.player:getXp():getXP(Perks.Electricity)>f.xpBefore,"native Electrical XP was applied")
        if state.lock.drawer and not state.lock.drawer.open then
            check("lock_live_stash_gated",state.lock.stash==nil,"no reward exists before releasing the drawer")
            send(f.window,"unlock drawer")
        end
        check("lock_live_stash",state.lock.stash and contents(state.lock.stash),"verified native rewards are in the actual discovered container")
        f.pc:getModData().LF_LockAcceptance=state.lock.stash
        shot(H,"welcome")
        local second=fresh(H,f,"word",39)
        check("lock_live_drawer_claim",second.lock.drawer~=nil,"documented dispatch program claims its adjacent real desk")
        if second.lock.drawer then
            f.drawer=SC.TerminalDrawers.container(second.lock.drawer)
            local ds=call(call(f.drawer,"getParent"),"getSquare")
            for _,d in ipairs({{0,1},{1,0},{0,-1},{-1,0}}) do
                local s=getCell():getGridSquare(ds:getX()+d[1],ds:getY()+d[2],ds:getZ())
                if s and SC.GameplayUtil.isSquareFree(s) and SC.GameplayUtil.distance(s,f.pc)<2.5 then H.player:teleportTo(s:getX()+.5,s:getY()+.5,s:getZ()) break end
            end
        end
        setPhase("lock_probe_accept_drawer",current) return
    elseif H.phase=="lock_probe_accept_drawer" then
        if current-H.phaseStartedAt<1500 then return end
        local inv=getPlayerLoot(0) inv:setVisible(true) inv:refreshBackpacks()
        local button,floor
        for _,b in ipairs(inv.backpacks) do
            if b.inventory==f.drawer then button=b end
            if call(b.inventory,"getType")=="floor" then floor=b.inventory end
        end
        check("lock_live_drawer_padlock",button and button.onclick==nil and button.onMouseUp==SC.TerminalDrawers.blockedPointer and button.textureOverride~=nil,"production Runtime refresh applies native lock icon and drag-in guard")
        if button and floor then
            inv:setNewContainer(floor) inv:selectContainer(button) inv:setNewContainer(f.drawer)
            check("lock_live_drawer_selection",inv.inventoryPane.inventory==floor,"production selection wrappers reject a locked plain desk")
        end
        shot(H,"interlock")
        f.window:close()
        setPhase("lock_probe_accept_interlock_picture",current) return
    elseif H.phase=="lock_probe_accept_interlock_picture" then
        if current-H.phaseStartedAt<1000 then return end
        shot(H,"interlock")
        local inventory=H.player:getInventory() inventory:AddItem("Base.Crowbar")
        f.forceBefore=f.window.system.lock.stash
        local context=ISContextMenu.get(0,0,0)
        SC.TerminalDrawers.context(context,H.player,{call(f.drawer,"getParent")})
        local chosen
        for _,o in ipairs(context.options or {}) do if o.name=="Force the drawer" then chosen=o break end end
        check("lock_live_force_option",chosen and chosen.onSelect~=nil,"real desk context exposes crowbar recovery")
        if not chosen then complete(H,f,current,result,setPhase) return end
        chosen.onSelect(chosen.target)
        setPhase("lock_probe_accept_force",current) return
    elseif H.phase=="lock_probe_accept_force" then
        local state=SC.Terminal.peekState(f.pc)
        if not state.lock.drawer.forced and current-H.phaseStartedAt<15000 then return end
        check("lock_live_crowbar",state.locked and state.lock.drawer.forced and contents(state.lock.stash),"native timed force releases physical rewards while PC stays locked")
        -- No second grant from a repeated force callback.
        local receipts=#state.lock.stash.items
        local again=SC.TerminalDrawers.open(H.player,f.pc,state,true)
        check("lock_live_force_once",not again and #state.lock.stash.items==receipts,"forcing cannot replay rewards")
        f.pc:getModData().LF_LockAcceptance=state.lock.stash
        assert(SC.Terminal.open(H.player,f.pc),"locked PC reopen after forcing failed") f.window=SC.Terminal.window f.window:flush()
        send(f.window,"other ways in") send(f.window,"yes") send(f.window,"run crack.exe")
        check("lock_live_bypass",f.window.system.lock.bypass and f.window.lockPage=="crack","confirmed alternatives remain usable on a locked computer")
        setPhase("lock_probe_accept_crack_picture",current) return
    elseif H.phase=="lock_probe_accept_crack_picture" then
        if current-H.phaseStartedAt<1200 then return end
        shot(H,"crack") send(f.window,SC.TerminalLockCrack.password(f.window.system))
        setPhase("lock_probe_accept_crack",current) return
    elseif H.phase=="lock_probe_accept_crack" then
        if f.window.payoff then return end
        check("lock_live_crack_early",not f.window.system.locked and f.window.system.xpAwarded,"early typed password completes the real unlock path")
        local skill=SC.ControlUtil.skill(H.player) local selected
        for seed=1,1000 do
            if seed%4~=0 and SC.TerminalLockCase.roll({seed=seed})>math.max(10,60-5*skill) then selected=seed break end
        end
        local state=fresh(H,f,"word",selected)
        send(f.window,"other ways in") send(f.window,"yes") send(f.window,"open the case")
        H.player:getInventory():AddItem("Base.ElectronicsScrap")
        H.player:getInventory():AddItem("Base.Screwdriver")
        setPhase("lock_probe_accept_case_picture",current) return
    elseif H.phase=="lock_probe_accept_case_picture" then
        if current-H.phaseStartedAt<1200 then return end
        shot(H,"case")
        local jumper
        for _,hit in ipairs(f.window.securityHits or {}) do if hit.value=="1" and hit.height then jumper=hit break end end
        check("lock_live_case_art_region",jumper~=nil,"click regions follow the fitted, tinted motherboard")
        if jumper then f.window:onMouseDown(jumper.x+jumper.width/2,jumper.y+jumper.height/2) else send(f.window,"1") end
        setPhase("lock_probe_accept_case",current) return
    elseif H.phase=="lock_probe_accept_case" then
        local state=SC.Terminal.peekState(f.pc)
        if state.locked and current-H.phaseStartedAt<15000 then return end
        check("lock_live_case_clean",not state.locked and state.lock.caseFinished and not state.lock.slip,"native hardware repair consumes components and preserves the owner archive")
        local selected
        for seed=1,1000 do
            if SC.TerminalLockCase.roll({seed=seed})<=math.max(10,60-5*SC.ControlUtil.skill(H.player)) then selected=seed break end
        end
        fresh(H,f,"word",selected)
        send(f.window,"other ways in") send(f.window,"yes")
        H.player:getInventory():AddItem("Base.ElectronicsScrap")
        f.slipBrand=f.window.system.brand f.window:close()
        -- No powered window is required: same public repair queue as context.
        local okay,why=SC.TerminalLockCase.queue(H.player,f.pc,false) assert(okay,why)
        setPhase("lock_probe_accept_slip",current) return
    elseif H.phase=="lock_probe_accept_slip" then
        local state=SC.Terminal.peekState(f.pc)
        if state.locked and current-H.phaseStartedAt<15000 then return end
        check("lock_live_case_slip",not state.locked and state.archive=="_factory" and state.lock.slip and state.xpAwarded
            and state.brand==f.slipBrand and not state.lock.drawer,"fixed seeded slip unlocks, wipes files, keeps branding and releases interlock")
        check("lock_live_case_burn",H.player:getBodyDamage():getBodyPart(BodyPartType.Hand_L):getBurnTime()>0,"native small hand burn applied")
        assert(SC.Terminal.open(H.player,f.pc),"factory-reset terminal reopen failed") f.window=SC.Terminal.window f.window:flush()
        check("lock_live_factory_welcome",f.window.session~=nil and state.lock.stash and #state.lock.stash.items==0,"slip offers clean local EMMA without recreating a stash")
        f.window:close()
        if not f.tower then result("FAIL","lock_tower_fixture","no native office tower found in bounded metadata catalogue") complete(H,f,current,result,setPhase) return end
        f.oldGod=H.player:isGodMod() H.player:setGodMod(true)
        f.oldGhost=H.player:isGhostMode() H.player:setGhostMode(true)
        H.player:teleportTo(f.tower:getX()+4,f.tower:getY()+4,0)
        setPhase("lock_probe_accept_tower_load",current) return
    elseif H.phase=="lock_probe_accept_tower_load" then
        if current-H.phaseStartedAt<8000 then return end
        local stand
        for z=1,math.min(4,f.tower:getMaxLevel()) do
            for dx=-18,18 do for dy=-18,18 do
                if not stand then
                    local tile=getCell():getGridSquare(math.floor(H.player:getX())+dx,math.floor(H.player:getY())+dy,z)
                    if tile and tile:getBuildingDef()==f.tower and tile:getRoom() and SC.GameplayUtil.isSquareFree(tile) then stand=tile end
                end
            end end
            if stand then break end
        end
        assert(stand,"no loaded upper-floor office standing square")
        H.player:teleportTo(stand:getX()+.5,stand:getY()+.5,stand:getZ()) f.towerStand=stand
        f.zombies={}
        for z=math.max(0,stand:getZ()-1),stand:getZ()+1 do
            for dx=-18,18 do for dy=-18,18 do
                if #f.zombies<200 and dx*dx+dy*dy>=100 and dx*dx+dy*dy<625 then
                    local tile=getCell():getGridSquare(stand:getX()+dx,stand:getY()+dy,z)
                    if tile and SC.GameplayUtil.isSafeSpawnSquare(tile) then
                        local list=addZombiesInOutfit(tile:getX(),tile:getY(),z,1,nil,0) local zombie=list and list:get(0)
                        if zombie then zombie:setTarget(nil) f.zombies[#f.zombies+1]=zombie end
                    end
                end
            end end
        end
        local threat=SC.TerminalWorld.nearestThreat(H.player,{},current)
        check("lock_tower_population",#f.zombies>=200,"native upper-floor office="..stand:getX()..","..stand:getY()..","..stand:getZ().." count="..#f.zombies)
        check("lock_tower_not_crying_wolf",SC.TerminalLamp.target(threat)<=.8 or threat.closingDistance~=nil,"stationary/non-targeting native threats do not drive fast flashes")
        f.towerSamples={} f.towerMemory={}
        setPhase("lock_probe_accept_tower_sensor",current) return
    elseif H.phase=="lock_probe_accept_tower_sensor" then
        local start=SCBridge.nowMsPrecise() SC.TerminalWorld.nearestThreat(H.player,f.towerMemory,current)
        f.towerSamples[#f.towerSamples+1]=SCBridge.nowMsPrecise()-start
        if #f.towerSamples<100 then return end
        table.sort(f.towerSamples) local p95=f.towerSamples[95]
        local list=getCell():getZombieList()
        check("lock_tower_p95",p95<=1,"native office tower / 200 fixture zombies / loaded="..list:size().." / p95Ms="..p95)
        -- The next fixture measures quiet companion speech, not combat.
        -- Remove the disposable world's ambient population as well as our 200.
        for i=list:size()-1,0,-1 do local zombie=list:get(i) zombie:removeFromWorld() zombie:removeFromSquare() end f.zombies={}
        local stand=f.towerStand local peer
        for _,d in ipairs({{1,0},{0,1},{-1,0},{0,-1}}) do
            local tile=getCell():getGridSquare(stand:getX()+d[1],stand:getY()+d[2],stand:getZ())
            if tile and SC.GameplayUtil.isSquareFree(tile) then peer=tile break end
        end
        assert(peer,"no native crew standing square")
        f.crewTicket=SC.Actor.beginSpawn(peer,{recruited=true,identity={forename="Ruth",surname="Fielding",gender="woman",outfit="Generic01"}})
        assert(f.crewTicket,"native helper spawn not accepted")
        setPhase("lock_probe_accept_crew_spawn",current) return
    elseif H.phase=="lock_probe_accept_crew_spawn" then
        local actor,why=SC.Actor.pollSpawn(f.crewTicket)
        if not actor then if why=="spawn_pending" and current-H.phaseStartedAt<15000 then return end error(tostring(why)) end
        f.actor=actor SC.Commands.issue(SC.Registry.idOf(actor),"stay",nil,H.player)
        actor:setPerkLevelDebug(Perks.Electricity,10)
        local tile=f.towerStand
        f.towerPC=IsoObject.new(tile,"appliances_com_01_72","Computer") tile:AddTileObject(f.towerPC)
        if not SC.Terminal.powered(f.towerPC) then
            local inv=H.player:getInventory()
            for _=1,3 do inv:AddItem("Base.ElectricWire") end for _=1,6 do inv:AddItem("Base.ElectronicsScrap") end
            local battery=inv:AddItem("Base.CarBattery1") SC.ControlUtil.setCharge(battery,.95)
            local okay,reason=SC.TerminalHardware.install(H.player,f.towerPC,"ups",battery) assert(okay,reason)
        end
        assert(SC.Terminal.open(H.player,f.towerPC),"native crew computer did not open") f.window=SC.Terminal.window f.window:flush()
        setPhase("lock_probe_accept_crew_hint",current) return
    elseif H.phase=="lock_probe_accept_crew_hint" then
        local helper=SC.TerminalLockCrew.helper(f.window)
        if (not helper or not SC.Banter.budgetAllows(current)) and current-H.phaseStartedAt<90000 then return end
        check("lock_live_crew_available",helper==f.actor,"real nearby recruited higher-skilled actor is available through Banter policy")
        if helper then
            SC.TerminalLockCrew.hint(f.window)
            check("lock_live_crew_speech",f.window.system.lock.crewHint and SC.Dialogue.has("terminal.lock.hint"),"registered hint was spoken before changing one puzzle candidate")
            check("lock_live_crew_not_redirected",SC.Commands.peek(f.actor).order=="stay" and SC.ActionSupervisor.current(f.actor)==nil,"hint starts no NPC task or movement")
        end
        local record=SC.Registry.byId(SC.Registry.idOf(f.actor)) local group=SC.Factions.list(false)[1]
        if group then
            local oldStanding,oldLifecycle=group.standing,group.lifecycle
            record.recruited=false record.factionId=group.id group.standing="Hostile" group.lifecycle="hostile"
            local threat=SC.TerminalWorld.nearestThreat(H.player,{},current)
            check("lock_live_hostile_person",threat.actor==f.actor,"real Factions policy feeds a native hostile LF actor to the sensor")
            group.standing="Neutral" group.lifecycle="active"
            threat=SC.TerminalWorld.nearestThreat(H.player,{},current)
            check("lock_live_friendly_person",threat.actor~=f.actor,"neutral native person is excluded")
            group.standing="Hostile" group.lifecycle="hostile" record.recruited=true
            threat=SC.TerminalWorld.nearestThreat(H.player,{},current)
            check("lock_live_recruited_person",threat.actor~=f.actor,"recruited companions never drive the warning")
            record.factionId=nil group.standing,group.lifecycle=oldStanding,oldLifecycle
        else result("SKIP","lock_live_hostile_person","no native faction available in this seed; no fake faction created") end
        local outside
        for dx=-20,20 do for dy=-20,20 do
            if not outside then
                local tile=getCell():getGridSquare(f.towerStand:getX()+dx,f.towerStand:getY()+dy,0)
                if tile and not tile:getRoom() and not tile:haveElectricity() and SC.GameplayUtil.isSafeSpawnSquare(tile) then outside=tile end
            end
        end end
        assert(outside,"no native unpowered square for physical case recovery")
        H.player:teleportTo(outside:getX()+.5,outside:getY()+.5,outside:getZ())
        f.unpoweredPC=IsoObject.new(outside,"appliances_com_01_72","Computer") outside:AddTileObject(f.unpoweredPC)
        local selected
        for seed=1,1000 do if SC.TerminalLockCase.roll({seed=seed})>60 then selected=seed break end end
        local state=SC.TerminalSystem.create(selected,"police",false,false,"unpowered-case-fixture")
        state.archive="dispatch_bell" state.lock.kind="word" state.lock.legacy=true state.lock.bypass=true
        f.unpoweredPC:getModData().movableData={LF_LarchOS=state}
        check("lock_live_unpowered_fixture",not SC.Terminal.powered(f.unpoweredPC),"physical recovery fixture has neither grid nor generator nor UPS power")
        H.player:getInventory():AddItem("Base.Screwdriver") H.player:getInventory():AddItem("Base.ElectronicsScrap")
        f.window:close()
        local okay,why=SC.TerminalLockCase.queue(H.player,f.unpoweredPC,false) assert(okay,why)
        setPhase("lock_probe_accept_unpowered_case",current) return
    elseif H.phase=="lock_probe_accept_unpowered_case" then
        local state=SC.Terminal.peekState(f.unpoweredPC)
        if state.locked and current-H.phaseStartedAt<20000 then return end
        check("lock_live_unpowered_case",not state.locked and state.lock.caseFinished and not state.lock.slip
            and not SC.Terminal.powered(f.unpoweredPC),"native screwdriver recovery completes without a powered terminal session")
        complete(H,f,current,result,setPhase) return
    end
end
return Probe
