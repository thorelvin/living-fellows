-- SPDX-License-Identifier: MIT
-- Real native input, dialogue, physical drawer and reload in a disposable save.
SCRealSandboxHarnessProbes=SCRealSandboxHarnessProbes or {}
local Probe={} SCRealSandboxHarnessProbes.SCPersonaPlayProbe=Probe
local function call(o,m,...) return SurvivorCompanion.ControlUtil.call(o,m,...) end
local function shot(H,name) getCore():TakeFullScreenshot(H.config.run_id.."-persona-play-"..name..".png") end
local function typeText(w,text)
    w:setEntryText("")
    for i=1,#text do w.entry.javaObject:putCharacter(text:byte(i)) end
end
local road={"hello","Thor","my burger had no pickle","no","no","can i speak to a manager","yes",
    "every guest is a friend","open the drawer","thanks","no"}
local function logRows(w)
    for _,row in ipairs(w.rows) do
        if not row.personaLogged then print("SC_PERSONA_PLAY|TEXT|"..row.text) row.personaLogged=true end
    end
end
function Probe.step(H,current,check,result,setPhase)
    local SC=SurvivorCompanion local f=H.personaPlay
    if H.phase=="persona_play_setup" then
        f={electricity=getSandboxOptions():getElecShutModifier(),ghost=H.player:isGhostMode(),index=1,
            maxWeight=H.player:getMaxWeightBase()}
        H.personaPlay=f H.player:setGhostMode(true)
        H.player:setMaxWeightBase(1000) -- retain every seed item without unrelated heavy-load damage
        if SC.UI then SC.UI.close() end
        for _,actor in ipairs(SC.Registry.living()) do SC.Actor.remove(actor) end
        local zombies=getCell():getZombieList()
        for i=zombies:size()-1,0,-1 do local z=zombies:get(i) z:removeFromWorld() z:removeFromSquare() end
        getSandboxOptions():set("ElecShutModifier",2147483647) getSandboxOptions():toLua()
        f.scan={x=math.floor(H.player:getX())-32,y=math.floor(H.player:getY())-32,z=math.floor(H.player:getZ()),cursor=0}
        setPhase("persona_play_scan",current) return
    elseif H.phase=="persona_play_scan" then
        local s=f.scan
        for _=1,128 do
            if s.cursor>=65*65 then break end
            local n=s.cursor s.cursor=n+1
            local sq=getCell():getGridSquare(s.x+n%65,s.y+math.floor(n/65),s.z)
            for _,o in ipairs(SC.ControlUtil.list(call(sq,"getObjects"),64)) do
                if SC.Terminal.isComputer(o) and SC.TerminalDrawers.find(o) then f.pc=o break end
            end
            if f.pc then break end
        end
        if not f.pc and s.cursor<65*65 then return end
        if not check("persona_play_desktop",f.pc~=nil,"real loaded desktop with free native drawer") then setPhase("finish",current) return end
        local sq=f.pc:getSquare()
        for _,d in ipairs({{1,0},{0,1},{-1,0},{0,-1}}) do
            local at=getCell():getGridSquare(sq:getX()+d[1],sq:getY()+d[2],sq:getZ())
            if at and SC.GameplayUtil.isSquareFree(at) then H.player:teleportTo(at:getX()+.5,at:getY()+.5,at:getZ()) break end
        end
        local data=f.pc:getModData() data.movableData=data.movableData or {}
        data.movableData.LF_LarchOS=nil -- only the cloned fixture; never the seed
        SC.Config.debugPersona="spiffy"
        f.ordinary=SC.TerminalLocks.ledger().opened
        setPhase("persona_play_use",current) return
    elseif H.phase=="persona_play_use" then
        if current-H.phaseStartedAt<1200 then return end
        check("persona_play_use",SC.Terminal.use(H.player,f.pc)==true,"real Loot timed action opens terminal")
        setPhase("persona_play_open",current) return
    elseif H.phase=="persona_play_open" then
        local w=SC.Terminal.window
        if not w and current-H.phaseStartedAt<12000 then return end
        if not check("persona_play_open",w and SC.TerminalPersonaUI.active(w),"debug first boot creates SPIFFY") then setPhase("finish",current) return end
        f.window=w
        check("persona_play_blank",w.state=="idle" and #w.rows==0 and #w.queue==0 and not w.bootSoundStarted,"only cursor, no BIOS or sound")
        check("persona_play_focus",w.entry.javaObject:isFocused() and w.entry:getX()==-10000 and not w.closeButton:isVisible(),"real native field focused off screen; close hidden")
        check("persona_play_claim",w.system.lock.drawer~=nil and SC.TerminalDrawers.locked(SC.TerminalDrawers.container(w.system.lock.drawer)),"real desk interlocked")
        check("persona_play_ledger",SC.TerminalLocks.ledger().opened==f.ordinary,"ordinary lock Director not counted")
        setPhase("persona_play_blank",current) return
    elseif H.phase=="persona_play_blank" then
        if current-H.phaseStartedAt<700 then return end
        -- A newly opened UI is not painted until the next native frame.
        if not SC.TerminalPersonaUI.prompt(f.window,current):find("_",1,true) then return end
        shot(H,"blank") typeText(f.window,"123")
        setPhase("persona_play_digits",current) return
    elseif H.phase=="persona_play_digits" then
        if current-H.phaseStartedAt<500 then return end
        local w=f.window
        check("persona_play_digits",w.entry.javaObject:getInternalText()=="123" and #w.rows==0 and w.lockPage==nil,"digits remain typed until Enter")
        w.entry.javaObject:onOtherKey(Keyboard.KEY_TAB)
        check("persona_play_tab",w.focusMode=="chat","native Tab leaves chat focused")
        shot(H,"typed-digits") w:setEntryText("")
        setPhase("persona_play_idle_wait",current) return
    elseif H.phase=="persona_play_idle_wait" then
        local w=f.window
        if not w.personaSession.idleFirst and current-H.phaseStartedAt<50000 then return end
        if w.state~="idle" then return end
        check("persona_play_idle_first",w.personaSession.idleFirst and current-H.phaseStartedAt>=43000,
            "unattended open screen speaks once after about 45 seconds")
        f.idleRows=#w.rows setPhase("persona_play_idle_once",current) return
    elseif H.phase=="persona_play_idle_once" then
        if current-H.phaseStartedAt<2500 then return end
        check("persona_play_idle_once",#f.window.rows==f.idleRows and f.window.state=="idle","watch does not repeat first-contact prompt")
        typeText(f.window,road[f.index]) setPhase("persona_play_enter",current) return
    elseif H.phase=="persona_play_enter" then
        if current-H.phaseStartedAt<400 then return end
        f.window.entry.javaObject:onKeyEnter()
        check("persona_play_enter_"..f.index,f.window.state=="thinking" or f.window.state=="typing","native Enter dispatched line "..f.index)
        setPhase("persona_play_reply",current) return
    elseif H.phase=="persona_play_reply" then
        local w=f.window
        if w.state~="idle" and current-H.phaseStartedAt<45000 then return end
        check("persona_play_reply_"..f.index,w.state=="idle","real typewriter completed line "..f.index)
        logRows(w)
        if f.index==2 or f.index==8 then shot(H,"conversation-"..f.index) end
        f.index=f.index+1
        if f.index<=#road then typeText(w,road[f.index]) setPhase("persona_play_enter",current) return end
        local lock=w.system.lock
        check("persona_play_hired",lock.persona.flags.hired and lock.persona.flags.drawer_done,"manager oath completed in real window")
        local container=SC.TerminalDrawers.container(lock.drawer)
        check("persona_play_physical_reward",lock.drawer.open and not SC.TerminalDrawers.locked(container)
            and lock.stash and lock.stash.committed and #lock.stash.items==4,"native drawer opened and all four unique reward IDs recorded")
        for _,receipt in ipairs(lock.stash and lock.stash.items or {}) do
            local found=false local items=container:getItems()
            for i=0,items:size()-1 do local item=items:get(i)
                if tostring(item:getID())==receipt.id and item:getFullType()==receipt.type then found=true end
            end
            check("persona_play_item_"..receipt.type,found,"exact native identity still in physical desk")
        end
        f.count=container:getItems():size() f.session=w.personaSession
        w.entry.javaObject:onOtherKey(Keyboard.KEY_ESCAPE)
        check("persona_play_escape",SC.Terminal.window==nil,"native Esc closes with hidden X")
        SC.Terminal.open(H.player,f.pc) f.window=SC.Terminal.window
        check("persona_play_reload",f.window.personaSession~=f.session and f.window.system.lock.persona.flags.hired
            and f.window.system.lock.persona.flags.drawer_done and container:getItems():size()==f.count,"normalized reopen keeps progress and exact items; no duplicate reward")
        f.originalNoise=SC.TerminalPersonaUI.noise
        SC.TerminalPersonaUI.noise=function(object)
            local id,emitter=f.originalNoise(object)
            f.audioId=id f.audioPlaying=id and call(emitter,"isPlaying",id)==true
            return id,emitter
        end
        typeText(f.window,"its my birthday") setPhase("persona_play_birthday_enter",current) return
    elseif H.phase=="persona_play_birthday_enter" then
        if current-H.phaseStartedAt<400 then return end
        f.window.entry.javaObject:onKeyEnter() setPhase("persona_play_birthday",current) return
    elseif H.phase=="persona_play_birthday" then
        local w=f.window
        if w.state~="idle" and current-H.phaseStartedAt<45000 then return end
        logRows(w)
        check("persona_play_jingle",w.system.lock.effects and w.system.lock.effects.noiseAt~=nil,"birthday requested real LFSpiffyJingle and world sound")
        check("persona_play_audio",type(f.audioId)=="number" and f.audioId>0 and f.audioPlaying,
            "native FMOD voice playing="..tostring(f.audioPlaying).." id="..tostring(f.audioId))
        SC.TerminalPersonaUI.noise=f.originalNoise
        shot(H,"birthday") f.noiseAt=w.system.lock.effects and w.system.lock.effects.noiseAt
        SC.TerminalPersonaUI.effects(w,{noise=true},{hours=f.noiseAt})
        check("persona_play_noise_cooldown",w.system.lock.effects.noiseAt==f.noiseAt,"same-hour noise receipt retained")
        w.personaEnding="shutdown"
        -- This seed has a running home generator. Use the actual computer's
        -- power switch so UPS/generator supply cannot mask the interruption.
        f.hardware=SC.TerminalHardware.state(f.pc,true) f.hardwareOn=f.hardware.on f.hardware.on=false
        getSandboxOptions():set("ElecShutModifier",0) getSandboxOptions():toLua()
        setPhase("persona_play_powercut",current) return
    elseif H.phase=="persona_play_powercut" then
        if current-H.phaseStartedAt<650 then return end
        local w=f.window
        check("persona_play_powercut",w.state=="closing" and w.system.locked and w.system.lock.persona.flags.power_cut
            and w.personaEnding==nil,"power loss cancels shutdown and prints supplied mid-sentence line")
        shot(H,"power-cut") w:close()
        f.hardware.on=f.hardwareOn
        getSandboxOptions():set("ElecShutModifier",2147483647) getSandboxOptions():toLua()
        SC.Terminal.open(H.player,f.pc) f.window=SC.Terminal.window
        check("persona_play_power_return",f.window.system.lock.persona.flags.power_cut,"interrupted machine memory survives reopening")
        -- Real factory path must release a still-shut claim before wiping lock.
        local s=f.window.system local lock=s.lock
        SC.TerminalDrawers.release(f.pc)
        lock.stash=nil lock.drawerChecked=false
        SC.TerminalDrawers.claim(H.player,f.pc,s)
        f.claimed=lock.drawer and SC.TerminalDrawers.container(lock.drawer)
        f.window.personaEnding="shutdown" SC.TerminalPersonaUI.finished(f.window)
        local normal=SC.Terminal.window
        check("persona_play_factory",normal and normal.system.archive=="_factory" and not normal.system.locked
            and normal.system.lock==nil,"permanent deletion reopens normal factory EMMA")
        check("persona_play_factory_release",f.claimed and not SC.TerminalDrawers.locked(f.claimed),"factory reset does not orphan desk interlock")
        if normal then normal:close() end
        getSandboxOptions():set("ElecShutModifier",f.electricity) getSandboxOptions():toLua()
        H.player:setGhostMode(f.ghost) H.player:setMaxWeightBase(f.maxWeight)
        SC.Config.debugPersona=nil setPhase("finish",current)
    end
end
