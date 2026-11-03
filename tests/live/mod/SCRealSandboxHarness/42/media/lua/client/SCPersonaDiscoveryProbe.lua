-- SPDX-License-Identifier: MIT
-- Native Phase 2: forced entry, therapist, furniture move, deep-post discovery,
-- physical UPS, and a second-process reload/deletion checkpoint. Clone only.
SCRealSandboxHarnessProbes=SCRealSandboxHarnessProbes or {}
local Probe={} SCRealSandboxHarnessProbes.SCPersonaDiscoveryProbe=Probe
local function SC() return SurvivorCompanion end
local function call(o,m,...) return SC().ControlUtil.call(o,m,...) end
local function shot(H,name) getCore():TakeFullScreenshot(H.config.run_id.."-persona-discovery-"..name..".png") end
local function stand(player,pc)
    local sq=pc:getSquare()
    for _,d in ipairs({{1,0},{0,1},{-1,0},{0,-1}}) do
        local tile=getCell():getGridSquare(sq:getX()+d[1],sq:getY()+d[2],sq:getZ())
        if tile and SC().GameplayUtil.isSquareFree(tile) then player:teleportTo(tile:getX()+.5,tile:getY()+.5,tile:getZ()) return tile end
    end
end
local function typed(w,text)
    w:setEntryText("") for i=1,#text do w.entry.javaObject:putCharacter(text:byte(i)) end
end
local function inspectRows(w)
    for _,r in ipairs(w.rows) do if not r.discoveryLogged then
        print("SC_PERSONA_DISCOVERY|TEXT|"..r.text) r.discoveryLogged=true
    end end
end
local function open(H,pc)
    if SC().Terminal.window then SC().Terminal.window:close() end
    assert(SC().Terminal.open(H.player,pc)) return SC().Terminal.window
end
local function fixture(pc,id,seed)
    SC().TerminalDrawers.release(pc)
    local md=pc:getModData() md.movableData=md.movableData or {}
    local brand=SC().TerminalBrands.identify(pc)
    local s=SC().TerminalSystem.create(seed or 11,SC().TerminalWorld.computerKind(pc,brand),false,false,"persona-native:"..id,brand)
    s.brand=brand md.movableData.LF_LarchOS=s
    SC().Config.debugPersona=id return s
end
local function exactRewards(lock,check,prefix)
    local c=SC().TerminalDrawers.container(lock.drawer or lock.stash and lock.stash.location)
    if not check(prefix.."_container",c~=nil,"original native desk available") then return end
    for _,receipt in ipairs(lock.stash and lock.stash.items or {}) do
        local count=0 local items=c:getItems()
        for i=0,items:size()-1 do local item=items:get(i)
            if tostring(item:getID())==receipt.id and item:getFullType()==receipt.type then count=count+1 end
        end
        check(prefix.."_"..receipt.type,count==1,"exact native receipt present once: "..receipt.id)
    end
end
local function findPC(x,y,z,id)
    local sq=getCell():getGridSquare(x,y,z)
    for _,o in ipairs(SC().ControlUtil.list(call(sq,"getObjects"),64)) do
        local s=SC().Terminal.isComputer(o) and SC().Terminal.peekState(o)
        if s and (not id or s.identity==id) then return o end
    end
end
local function finish(H,f,current,setPhase)
    if SC().Terminal.window then SC().Terminal.window:close() end
    SC().Config.debugPersona=nil H.player:setGhostMode(f.ghost)
    H.player:setMaxWeightBase(f.maxWeight) setPhase("finish",current)
end
local therapist={"hello","Ann","i dont know","last week","not really","ok","ok","ok","my mother","ok","ok","ok","ok"}
local officer={"hello","Hicks","who is in command","i relieve you","no","sitrep"}
function Probe.step(H,current,check,result,setPhase)
    if H.config.camp_release_probe=="true" then
        require "SCCampReleaseProbe"
        return SCRealSandboxHarnessProbes.SCCampReleaseProbe.step(H,current,check,result,setPhase)
    end
    local S=SC() local f=H.personaDiscovery
    if H.phase=="persona_discovery_setup" then
        f={ghost=H.player:isGhostMode(),maxWeight=H.player:getMaxWeightBase(),index=1} H.personaDiscovery=f
        H.player:setGhostMode(true) H.player:setMaxWeightBase(1000)
        if S.UI then S.UI.close() end
        for _,actor in ipairs(S.Registry.living()) do S.Actor.remove(actor) end
        local zs=getCell():getZombieList()
        for i=zs:size()-1,0,-1 do local z=zs:get(i) z:removeFromWorld() z:removeFromSquare() end
        if H.config.persona_discovery_resume=="true" then
            f.checkpoint=ModData.get("LF_PersonaAcceptance")
            if not check("persona_resume_checkpoint",f.checkpoint and f.checkpoint.identity~=nil,"native saved checkpoint exists") then finish(H,f,current,setPhase) return end
            local cp=f.checkpoint H.player:teleportTo(cp.x+.5,cp.y+.5,cp.z)
            setPhase("persona_discovery_resume_load",current) return
        end
        getSandboxOptions():set("ElecShutModifier",2147483647) getSandboxOptions():toLua()
        f.scan={x=math.floor(H.player:getX())-32,y=math.floor(H.player:getY())-32,z=math.floor(H.player:getZ()),cursor=0}
        setPhase("persona_discovery_home_scan",current) return
    elseif H.phase=="persona_discovery_home_scan" then
        local s=f.scan
        for _=1,128 do
            if s.cursor>=65*65 then break end
            local n=s.cursor s.cursor=n+1 local sq=getCell():getGridSquare(s.x+n%65,s.y+math.floor(n/65),s.z)
            for _,o in ipairs(S.ControlUtil.list(call(sq,"getObjects"),64)) do
                if S.Terminal.isComputer(o) and S.TerminalDrawers.find(o) then f.homePC=o break end
            end
            if f.homePC then break end
        end
        if not f.homePC and s.cursor<65*65 then return end
        if not check("persona_home_pc",f.homePC~=nil,"real desktop with real free desk") then finish(H,f,current,setPhase) return end
        stand(H.player,f.homePC) fixture(f.homePC,"spiffy")
        f.window=open(H,f.homePC)
        check("persona_spiffy_debug",f.window.system.lock.persona.id=="spiffy","first of three debug personalities")
        setPhase("persona_discovery_force",current) return
    elseif H.phase=="persona_discovery_force" then
        if current-H.phaseStartedAt<1200 then return end
        local before=f.window.system.lock
        local c=S.TerminalDrawers.container(before.drawer) f.desk=select(2,S.TerminalDrawers.container(before.drawer))
        f.stockBefore=c:getItems():size() f.forcedExpected=S.TerminalPayoff.items(f.window.system,true)
        local tool=H.player:getInventory():AddItem("Base.Crowbar")
        check("persona_crowbar_owned",tool and tool:getContainer()==H.player:getInventory(),"native crowbar owned by observer")
        local forced,why=S.TerminalDrawers.open(H.player,f.homePC,f.window.system,true)
        if not check("persona_crowbar_result",forced==true
            and before.persona.flags.forced and before.drawer.forced and f.window.system.locked,
            "real forced-entry path: "..tostring(why)) then finish(H,f,current,setPhase) return end
        check("persona_crowbar_ordinary",#before.stash.items==#f.forcedExpected,"ordinary tier, no conversation bonus")
        for _,r in ipairs(before.stash.items) do check("persona_crowbar_no_suit_"..r.id,r.type~="Base.SpiffoSuit","crowbar cannot add manager uniform") end
        exactRewards(before,check,"persona_forced")
        f.window:close() S.TerminalDrawers.release(f.homePC)
        -- Reset this physical fixture between independent cases in the clone.
        -- The real game never repairs broken drawer markers automatically.
        f.desk:getModData().movableData.LF_LarchDrawerBroken=nil
        fixture(f.homePC,"ellis") f.window=open(H,f.homePC)
        H.player:getStats():set(CharacterStat.STRESS,.6) H.player:getStats():set(CharacterStat.UNHAPPINESS,50)
        check("persona_ellis_debug",f.window.system.lock.persona.id=="ellis" and f.window.system.theme=="aqua","therapist on native aqua CRT")
        f.road=therapist typed(f.window,f.road[1]) setPhase("persona_discovery_enter",current) return
    elseif H.phase=="persona_discovery_enter" then
        if current-H.phaseStartedAt<300 then return end
        f.window.entry.javaObject:onKeyEnter() setPhase("persona_discovery_reply",current) return
    elseif H.phase=="persona_discovery_reply" then
        local w=f.window
        if not w.closed and w.state~="idle" and current-H.phaseStartedAt<60000 then return end
        inspectRows(w)
        check("persona_"..f.window.system.lock.persona.id.."_reply_"..f.index,w.closed or w.state=="idle","native reply completes")
        if f.road==therapist and w.system.lock.persona.flags.drawer_done and w.system.lock.effects and w.system.lock.effects.reliefDay then
            setPhase("persona_discovery_therapy_done",current) return
        end
        f.index=f.index+1
        if f.index<=#f.road and not w.closed then typed(w,f.road[f.index]) setPhase("persona_discovery_enter",current) return end
        if f.road==therapist then setPhase("persona_discovery_therapy_done",current)
        else setPhase("persona_discovery_duty_done",current) end
        return
    elseif H.phase=="persona_discovery_therapy_done" then
        local w=f.window local lock=w.system.lock
        check("persona_therapy_grant",lock.persona.flags.drawer_done and lock.effects and lock.effects.reliefDay~=nil,"therapy releases drawer and applies real relief")
        check("persona_therapy_items",lock.stash and #lock.stash.items==3,"three prescribed real items")
        exactRewards(lock,check,"persona_therapy")
        check("persona_therapy_stats",H.player:getStats():get(CharacterStat.STRESS)<.45
            and H.player:getStats():get(CharacterStat.UNHAPPINESS)<35,"native stress and unhappiness reduced")
        local before=H.player:getStats():get(CharacterStat.STRESS)
        S.TerminalPersonaUI.effects(w,{relief=true},{hours=S.ControlUtil.hours()})
        check("persona_therapy_cooldown",H.player:getStats():get(CharacterStat.STRESS)==before,"same-day relief does not repeat")
        if not w.closed then w:close() end
        f.props=ISMoveableSpriteProps.new(f.homePC:getSprite()) f.sprite=f.homePC:getSprite():getName()
        f.oldHome={x=f.homePC:getX(),y=f.homePC:getY(),z=f.homePC:getZ()} f.originalIdentity=w.system.identity
        -- Use native pickup and exact-item placement. Rotation skips random
        -- destruction so this test measures metadata/ownership, not break odds.
        f.item=f.props:pickUpMoveableInternal(H.player,f.homePC:getSquare(),f.homePC,nil,f.sprite,true,true)
        check("persona_native_pickup",f.item and f.item:getContainer()==H.player:getInventory()
            and f.homePC:getObjectIndex()<0,"native furniture item owns the moved assembly")
        local moved=f.item and f.item:getModData().movableData.LF_LarchOS
        if not check("persona_move_memory",moved and moved.lock.persona.id=="ellis" and moved.lock.persona.name=="Ann"
            and not moved.lock.drawer and moved.lock.stash.committed,"pickup preserves personality and severs drawer") then finish(H,f,current,setPhase) return end
        f.scan={x=f.oldHome.x-8,y=f.oldHome.y-8,z=f.oldHome.z,cursor=0}
        setPhase("persona_discovery_place_scan",current) return
    elseif H.phase=="persona_discovery_place_scan" then
        local s=f.scan
        for _=1,16 do
            if s.cursor>=17*17 then break end
            local n=s.cursor s.cursor=n+1 local x,y=s.x+n%17,s.y+math.floor(n/17)
            local sq=getCell():getGridSquare(x,y,s.z)
            if sq and (x~=f.oldHome.x or y~=f.oldHome.y) and S.BaseLife.isInside(sq)
                and f.props:canPlaceMoveableInternal(H.player,sq,f.item) then f.destination=sq break end
        end
        if not f.destination and s.cursor<17*17 then return end
        if not check("persona_native_destination",f.destination~=nil,"different legal vanilla tabletop found") then finish(H,f,current,setPhase) return end
        f.props:placeMoveableInternal(H.player,f.destination,f.item,f.sprite)
        f.movedPC=findPC(f.destination:getX(),f.destination:getY(),f.destination:getZ(),f.originalIdentity)
        if not check("persona_native_placement",f.movedPC~=nil,"native placed object retains exact computer identity") then finish(H,f,current,setPhase) return end
        H.player:getInventory():Remove(f.item)
        check("persona_single_furniture_owner",f.item:getContainer()~=H.player:getInventory(),"exact furniture item removed only after confirmed native placement")
        stand(H.player,f.movedPC) f.window=open(H,f.movedPC)
        local facts=S.TerminalPersonaUI.facts(f.window,current,true)
        check("persona_move_live_facts",facts.moved and facts.drawer=="none","live facts see new coordinates and detached original drawer")
        check("persona_move_camp",facts.atCamp==true,"computer moved within real marked camp")
        typed(f.window,"hello") setPhase("persona_discovery_move_enter",current) return
    elseif H.phase=="persona_discovery_move_enter" then
        if current-H.phaseStartedAt<350 then return end
        f.window.entry.javaObject:onKeyEnter() setPhase("persona_discovery_move_reply",current) return
    elseif H.phase=="persona_discovery_move_reply" then
        if f.window.state~="idle" and current-H.phaseStartedAt<30000 then return end
        inspectRows(f.window)
        check("persona_move_return_line",f.window.system.lock.persona.flags.moved_seen,"supplied home-move line reached") shot(H,"ellis-home")
        f.window:close()
        getGameTime():setYear(1993) getGameTime():setMonth(7) getGameTime():setDay(0) getGameTime():setTimeOfDay(14.25)
        check("persona_august_date",S.TerminalPayoff.daysSinceOutbreak()==23,"actual native calendar is August 1")
        H.player:teleportTo(5544.5,12463.5,0) setPhase("persona_discovery_deep_load",current) return
    elseif H.phase=="persona_discovery_deep_load" then
        if current-H.phaseStartedAt<8000 then return end
        f.scan={x=5496,y=12415,z=-13,cursor=0}
        setPhase("persona_discovery_deep_scan",current) return
    elseif H.phase=="persona_discovery_deep_scan" then
        local s=f.scan
        for _=1,128 do
            if s.cursor>=96*96 then break end
            local n=s.cursor s.cursor=n+1 local sq=getCell():getGridSquare(s.x+n%96,s.y+math.floor(n/96),s.z)
            for _,o in ipairs(S.ControlUtil.list(call(sq,"getObjects"),64)) do
                if S.Terminal.isComputer(o) and S.TerminalDrawers.find(o) then f.deepPC=o break end
            end
            if f.deepPC then break end
        end
        if not f.deepPC and s.cursor<96*96 then return end
        if not check("persona_deep_real_pc",f.deepPC~=nil,"real floor -13 desktop with native free desk") then finish(H,f,current,setPhase) return end
        stand(H.player,f.deepPC) getSandboxOptions():set("ElecShutModifier",0) getSandboxOptions():toLua()
        setPhase("persona_discovery_ups",current) return
    elseif H.phase=="persona_discovery_ups" then
        if current-H.phaseStartedAt<1500 then return end
        check("persona_deep_unpowered",not S.Terminal.powered(f.deepPC),"grid shutoff leaves deep computer unpowered")
        for _,kind in ipairs({"Base.Screwdriver","Base.ElectricWire","Base.ElectronicsScrap","Base.ElectronicsScrap","Base.ElectronicsScrap","Base.ElectronicsScrap"}) do H.player:getInventory():AddItem(kind) end
        local battery=H.player:getInventory():AddItem("Base.CarBattery1") S.ControlUtil.setCharge(battery,1)
        local installed,why=S.TerminalHardware.install(H.player,f.deepPC,"ups",battery)
        if not check("persona_deep_physical_ups",installed==true,"native owned battery installation: "..tostring(why)) then finish(H,f,current,setPhase) return end
        check("persona_deep_ups_power",S.Terminal.powered(f.deepPC),"battery powers real deep PC without an indoor generator")
        S.Config.debugPersona=nil f.window=open(H,f.deepPC)
        check("persona_deep_natural_duty",f.window.system.lock.kind=="persona" and f.window.system.lock.persona.id=="duty",
            "natural deep guarantee; no debug override and actual August calendar")
        local facts=S.TerminalPersonaUI.facts(f.window,current,true)
        check("persona_deep_facts",facts.deep and facts.level==-13 and facts.days==23,"actual position/calendar reach supplied deep lines")
        f.road,f.index=officer,1 typed(f.window,officer[1]) setPhase("persona_discovery_enter",current) return
    elseif H.phase=="persona_discovery_duty_done" then
        local w=f.window local lock=w.system.lock
        check("persona_duty_handover",lock.persona.flags.relieved and lock.persona.flags.adjutant and lock.persona.flags.drawer_done,
            "real handover opens drawer and keeps officer as adjutant")
        check("persona_duty_items",lock.stash and #lock.stash.items==4,"four real military reward identities")
        exactRewards(lock,check,"persona_duty") shot(H,"duty-deep")
        if H.config.persona_discovery_stage=="true" then
            local cp=ModData.getOrCreate("LF_PersonaAcceptance")
            cp.x,cp.y,cp.z=f.deepPC:getX(),f.deepPC:getY(),f.deepPC:getZ()
            cp.identity,cp.spoken,cp.name=w.system.identity,lock.persona.spoken,lock.persona.name
            cp.noiseAt=lock.effects and lock.effects.noiseAt cp.drawer=lock.drawer cp.items=lock.stash.items
            cp.upsId=S.TerminalHardware.state(f.deepPC,false).ups.id cp.boots=S.TerminalLocks.ledger().persona.boots
            check("persona_reload_checkpoint",cp.upsId~=nil,"actual world/PC/item identities retained for a second client process")
            finish(H,f,current,setPhase) return
        end
        typed(w,"factory reset") setPhase("persona_discovery_delete_enter",current) return
    elseif H.phase=="persona_discovery_resume_load" then
        if current-H.phaseStartedAt<8000 then return end
        local cp=f.checkpoint f.deepPC=findPC(cp.x,cp.y,cp.z,cp.identity)
        if not check("persona_reload_pc",f.deepPC~=nil,"exact saved floor -13 computer loaded in a new process") then finish(H,f,current,setPhase) return end
        stand(H.player,f.deepPC)
        local s=S.Terminal.peekState(f.deepPC) local hw=S.TerminalHardware.state(f.deepPC,false)
        check("persona_reload_progress",s.lock.persona.id=="duty" and s.lock.persona.spoken==cp.spoken
            and s.lock.persona.name==cp.name and s.lock.persona.flags.adjutant and s.lock.persona.flags.drawer_done,"native save/reload preserves exact personality progress")
        check("persona_reload_hardware",hw and hw.ups and hw.ups.id==cp.upsId and S.Terminal.powered(f.deepPC),"exact mounted battery persists and powers saved machine")
        check("persona_reload_ledger",S.TerminalLocks.ledger().persona.boots==cp.boots and S.TerminalLocks.ledger().persona.met.duty,"world uniqueness ledger persists without a new roll")
        exactRewards(s.lock,check,"persona_reload_reward")
        f.window=open(H,f.deepPC)
        check("persona_reload_no_reissue",#f.window.system.lock.stash.items==#cp.items and f.window.system.lock.drawer.open,"reopening retains released drawer without reissuing loot")
        setPhase("persona_discovery_resume_visible",current) return
    elseif H.phase=="persona_discovery_resume_visible" then
        -- Opening and taking a screenshot in the same OnTick captures the
        -- previous world/debug frame. Allow the native UI to render first.
        if current-H.phaseStartedAt<1000 then return end
        if not check("persona_reload_visible",not f.window.closed and f.window:isVisible(),
            "reloaded terminal is visible before continuing dialogue") then finish(H,f,current,setPhase) return end
        typed(f.window,"sitrep") setPhase("persona_discovery_resume_submit",current) return
    elseif H.phase=="persona_discovery_resume_submit" then
        if current-H.phaseStartedAt<350 then return end
        f.window.entry.javaObject:onKeyEnter() setPhase("persona_discovery_resume_reply",current) return
    elseif H.phase=="persona_discovery_resume_reply" then
        if f.window.state~="idle" and current-H.phaseStartedAt<30000 then return end
        if not check("persona_reload_conversation",f.window.state=="idle"
            and f.window.system.lock.persona.spoken>f.checkpoint.spoken
            and f.window.system.lock.persona.flags.adjutant,
            "same saved officer answers a new report as adjutant") then finish(H,f,current,setPhase) return end
        inspectRows(f.window) setPhase("persona_discovery_resume_capture",current) return
    elseif H.phase=="persona_discovery_resume_capture" then
        if current-H.phaseStartedAt<1000 then return end
        shot(H,"duty-reloaded") typed(f.window,"factory reset") setPhase("persona_discovery_delete_enter",current) return
    elseif H.phase=="persona_discovery_delete_enter" then
        if current-H.phaseStartedAt<350 then return end
        f.window.entry.javaObject:onKeyEnter() setPhase("persona_discovery_delete_ask",current) return
    elseif H.phase=="persona_discovery_delete_ask" then
        if f.window.state~="idle" and current-H.phaseStartedAt<45000 then return end
        -- A first visit gets the machine's opening line before any command.
        -- Reloaded Duty is already met, so deletion immediately requests yes/no.
        typed(f.window,"yes") setPhase("persona_discovery_delete_yes",current) return
    elseif H.phase=="persona_discovery_delete_yes" then
        if current-H.phaseStartedAt<350 then return end
        f.window.entry.javaObject:onKeyEnter() setPhase("persona_discovery_deleted",current) return
    elseif H.phase=="persona_discovery_deleted" then
        if not f.window.closed and current-H.phaseStartedAt<60000 then return end
        local w=S.Terminal.window
        check("persona_deleted_factory",w and w.system.archive=="_factory" and not w.system.locked and w.system.lock==nil
            and not w.system.fresh,"dialogue deletion becomes permanent ordinary EMMA")
        check("persona_deleted_stays_met",S.TerminalLocks.ledger().persona.met.duty,"deleting software cannot spawn another officer")
        check("persona_deleted_keeps_ups",S.TerminalHardware.state(f.deepPC,false).ups~=nil,"factory reset preserves real mounted hardware")
        f.factory=w setPhase("persona_discovery_factory_render",current) return
    elseif H.phase=="persona_discovery_factory_render" then
        if current-H.phaseStartedAt<1000 then return end
        if f.factory.state~="idle" and current-H.phaseStartedAt<15000 then return end
        check("persona_deleted_visible",not f.factory.closed and f.factory:isVisible()
            and f.factory.state=="idle","ordinary EMMA finishes booting after deletion")
        local power=f.factory.world.power()
        local transcript={}
        for _,row in ipairs(f.factory.rows) do transcript[#transcript+1]=row.text end
        check("persona_backup_report",power.source=="battery" and power.charge>0
            and table.concat(transcript,"\n"):find("battery backup, charge ",1,true)~=nil,
            "ordinary EMMA names the actual mounted backup and live charge")
        local book=S.TerminalLocks.ledger().persona
        check("persona_followup_deferred",book.talked.duty and book.campReady.duty and not book.campMentions.duty,
            "real handover conversation queues a camp follow-up without consuming it outside camp")
        shot(H,"factory-after-reset")
        finish(H,f,current,setPhase)
    end
end
