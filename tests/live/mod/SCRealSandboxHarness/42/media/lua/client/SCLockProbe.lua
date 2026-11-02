-- SPDX-License-Identifier: MIT
-- Phase-zero bindings in a disposable native world, before lock mechanics.
-- Test-only hooks are restored before finishing; no authorization is replaced.
local Probe = {}
SCRealSandboxHarnessProbes = SCRealSandboxHarnessProbes or {}
SCRealSandboxHarnessProbes.SCLockProbe = Probe
local function call(o, m, ...) return SurvivorCompanion.ControlUtil.call(o, m, ...) end
local function log(s) print("SC_REAL_SANDBOX|LOCK_BINDING|" .. s) end
local function shot(H, name) getCore():TakeFullScreenshot(H.config.run_id .. "-locks-" .. name .. ".png") end
local function percentile(a, p) table.sort(a) return a[math.max(1, math.ceil(#a*p))] or 0 end
local function tags(o)
    local props = call(call(o, "getSprite"), "getProperties")
    return string.lower(tostring(call(props, "get", "GroupName") or "") .. " "
        .. tostring(call(props, "get", "CustomName") or ""))
end
local function ready(H, f)
    local SC = SurvivorCompanion
    local sq = f.pc:getSquare()
    for _,d in ipairs({{1,0},{0,1},{-1,0},{0,-1},{0,0}}) do
        local stand = getCell():getGridSquare(sq:getX()+d[1],sq:getY()+d[2],sq:getZ())
        if stand and SC.GameplayUtil.isSquareFree(stand) then
            H.player:teleportTo(stand:getX()+.5,stand:getY()+.5,stand:getZ()) break
        end
    end
    if not SC.Terminal.powered(f.pc) then
        local inv = H.player:getInventory()
        inv:AddItem("Base.Screwdriver")
        for _=1,3 do inv:AddItem("Base.ElectricWire") end
        for _=1,6 do inv:AddItem("Base.ElectronicsScrap") end
        local battery = inv:AddItem("Base.CarBattery1")
        SC.ControlUtil.setCharge(battery,.95)
        local okay, why = SC.TerminalHardware.install(H.player,f.pc,"ups",battery)
        assert(okay,why)
    end
    assert(SC.Terminal.open(H.player,f.pc),"native terminal access unavailable")
    f.window=SC.Terminal.window f.window:flush()
    -- A genuine, newly generated puzzle is not solved by this binding probe.
    f.originalLogoTexture=f.window.logoTexture
    f.originalLogo=f.window.drawHeaderLogo
    f.window.drawHeaderLogo=function(w)
        local l=w.layout
        local width=math.min(l.bodyWidth or (l.right-l.left),480)
        local started=getTimestampMs()
        local okay=SC.TerminalLockUI.art(w,"AccessGranted",{x=l.left,y=l.top+60,width=width,height=width/3})
        f.artMs=f.artMs+getTimestampMs()-started f.artCalls=f.artCalls+1
        if okay then f.artDrawn=true end
    end
end
local function inspect(H,f,check,result)
    local SC, player = SurvivorCompanion,H.player
    local x,y,z=f.pc:getX(),f.pc:getY(),f.pc:getZ()
    local desks={}
    for dx=-1,1 do for dy=-1,1 do
        local sq=getCell():getGridSquare(x+dx,y+dy,z)
        local objects=sq and sq:getObjects()
        for i=0,(objects and objects:size() or 0)-1 do
            local o=objects:get(i) local c=call(o,"getContainer") local kind=call(c,"getType")
            if c and (kind=="desk" or kind=="sidetable" or kind=="filingcabinet" or kind=="dresser") then
                desks[#desks+1]={object=o,container=c,adjacent=dx~=0 or dy~=0}
            end
        end
    end end
    f.desk=desks[1]
    check("locks_native_adjacent_desk",f.desk~=nil,"PC="..x..","..y..","..z.." desks="..#desks
        .." type="..tostring(f.desk and f.desk.container:getType()).." adjacent="..tostring(f.desk and f.desk.adjacent))
    if f.desk then
        local ds=f.desk.object:getSquare()
        for _,d in ipairs({{0,1},{1,0},{0,-1},{-1,0}}) do
            local stand=getCell():getGridSquare(ds:getX()+d[1],ds:getY()+d[2],ds:getZ())
            if stand and SC.GameplayUtil.isSquareFree(stand) and SC.GameplayUtil.distance(stand,f.pc)<2.5 then
                player:teleportTo(stand:getX()+.5,stand:getY()+.5,stand:getZ()) break
            end
        end
        local item=f.desk.container:AddItem("Base.Battery")
        check("locks_native_stash_add",item and item:getContainer()==f.desk.container,"native desk item="..tostring(item and item:getID()))
        local data=f.desk.object:getModData()
        data.LF_LockProbeItem=item and tostring(item:getID())
        f.stash=item
        local inv=getPlayerLoot(player:getPlayerNum())
        if inv then inv:refreshBackpacks() end
        f.loot=inv
        -- Inspect actual buttons, including their real native container types.
        for _,b in ipairs(inv and inv.backpacks or {}) do
            if b.inventory==f.desk.container then f.button=b break end
        end
        check("locks_native_drawer_button",f.button~=nil,"real desk button available="..tostring(f.button~=nil))
    end
    local manual=player:getInventory():AddItem("Base.ElectronicsMag1")
    local sq=f.desk and f.desk.object:getSquare() or f.pc:getSquare()
    if manual then
        player:getInventory():Remove(manual)
        local surface=call(f.desk and f.desk.object,"getSurfaceOffsetNoTable") or 0
        f.manual=sq:AddWorldInventoryItem(manual,.5,.5,surface/96)
    end
    check("locks_native_manual_surface",f.manual~=nil,"native world item; surface screenshot required")
    local water=player:getInventory():AddItem("Base.WaterBottle")
    local fluid=water and water:getFluidContainer()
    if fluid then fluid:Empty() fluid:addFluid(FluidType.Water,math.min(.5,fluid:getCapacity())) end
    check("locks_native_water",fluid and fluid:getAmount()>.1 and fluid:getPrimaryFluid()==Fluid.Water,
        "amount="..tostring(fluid and fluid:getAmount()).." primary="..tostring(fluid and fluid:getPrimaryFluid()))
    if water then player:getInventory():Remove(water) sq:AddWorldInventoryItem(water,.65,.5,0) f.water=water end
    -- Native XP supports setPerkBoost directly: no Java HashMap number casts.
    local xp=player:getXp() local perk=Perks.Electricity
    f.oldLevel=player:getPerkLevel(perk) f.oldBoost=xp:getPerkBoost(perk)
    player:setPerkLevelDebug(perk,0) xp:setPerkBoost(perk,0)
    local before=xp:getXP(perk) xp:AddXP(perk,15) local unboosted=xp:getXP(perk)-before
    xp:setPerkBoost(perk,3) before=xp:getXP(perk) xp:AddXP(perk,15) local boosted=xp:getXP(perk)-before
    check("locks_native_xp",unboosted>0 and boosted>unboosted,"15 base XP unboosted="..unboosted.." boosted="..boosted
        .." levelAfter="..player:getPerkLevel(perk))
    xp:setPerkBoost(perk,f.oldBoost) player:setPerkLevelDebug(perk,f.oldLevel)
    local body=player:getBodyDamage() local hand=body:getBodyPart(BodyPartType.Hand_L)
    f.hand=hand f.healthBefore=body:getOverallBodyHealth()
    hand:setBurnTime(.2) hand:AddDamage(1)
    log("minor burn duration="..hand:getBurnTime().." handHealth="..hand:getHealth()
        .." overallBefore="..f.healthBefore.." after="..body:getOverallBodyHealth())
    f.damageListener=function(actor,kind,amount)
        if actor==player then
            f.damageKinds[kind]=(f.damageKinds[kind] or 0)+1
            if kind=="WEAPONHIT" or kind=="BITE" or kind=="SCRATCH" or kind=="ZOMBIE" then
                f.hitEvent=kind
                if f.window and not f.window.closed then f.window:close() end
            end
        end
    end
    Events.OnPlayerGetDamage.Add(f.damageListener)
    if f.phone then
        local p=f.phone:getSquare()
        local emitter=getWorld():getFreeEmitter(p:getX()+.5,p:getY()+.5,p:getZ())
        f.phoneEmitter=emitter
        if GameSounds.isKnownSound("TelephoneRinging") then f.phoneSound=emitter:playSound("TelephoneRinging") end
        result(f.phoneSound and f.phoneSound~=0 and "PASS" or "FAIL","locks_phone_ring_binding",
            "native TelephoneRinging event="..tostring(GameSounds.isKnownSound("TelephoneRinging")).." handle="..tostring(f.phoneSound))
        check("locks_phone_location",SC.GameplayUtil.distance(f.pc,f.phone)<25,"real phone="..p:getX()..","..p:getY()..","..p:getZ().." "..tags(f.phone))
    else result("FAIL","locks_phone_location","no phone in scanned native building; do not assume census matches this site") end
end
local function cleanup(f)
    if not f then return end
    if f.damageListener then Events.OnPlayerGetDamage.Remove(f.damageListener) end
    if f.radioListener then Events.OnDeviceText.Remove(f.radioListener) end
    if f.window then f.window.drawHeaderLogo=f.originalLogo f.window:close() end
    if f.loot and f.originalSelect then
        f.loot.selectContainer=f.originalSelect f.loot.setNewContainer=f.originalSet
    end
    if f.button and f.oldButton then
        for _,key in ipairs({"onclick","onmousedown","onMouseUp","onMouseOver","onMouseOverOutside","textureOverride","tooltip"}) do
            f.button[key]=f.oldButton[key]
        end
    end
    if f.phoneEmitter then f.phoneEmitter:stopAll() end
    for _,z in ipairs(f.zombies) do if not z:isDead() then z:removeFromWorld() z:removeFromSquare() end end
end
function Probe.step(H,current,check,result,setPhase)
    local SC=SurvivorCompanion
    if H.phase:find("lock_probe_phase4_",1,true)==1 then
        require("SCLockPhase4Probe")
        return SCRealSandboxHarnessProbes.SCLockPhase4Probe.step(H,current,check,result,setPhase)
    end
    if H.phase:find("lock_probe_phase3_",1,true)==1 then
        require("SCLockPhase3Probe")
        return SCRealSandboxHarnessProbes.SCLockPhase3Probe.step(H,current,check,result,setPhase)
    end
    if H.phase:find("lock_probe_phase2_",1,true)==1 then
        require("SCLockPhase2Probe")
        return SCRealSandboxHarnessProbes.SCLockPhase2Probe.step(H,current,check,result,setPhase)
    end
    if H.phase:find("lock_probe_accept_",1,true)==1 then
        require("SCLockAcceptanceProbe")
        return SCRealSandboxHarnessProbes.SCLockAcceptanceProbe.step(H,current,check,result,setPhase)
    end
    if H.phase=="lock_probe_setup" then
        if current-H.phaseStartedAt<10000 then return end
        if H.config.lock_acceptance_probe=="true" or H.config.lock_phase2_probe=="true" or H.config.lock_phase3_probe=="true" or H.config.lock_phase4_probe=="true" then SandboxVars.LivingFellows.LockedComputerPercent=100 end
        require("SCTerminalLamp")
        H.lockProbe={zombies={},damageKinds={},artMs=0,artCalls=0,memory={},samples={}}
        if SC.UI then SC.UI.close() end
        for _,other in ipairs(SC.Registry.living()) do SC.Actor.remove(other) end
        -- Preserve every original item, but unload the overburdened seed actor.
        local inv=H.player:getInventory() local items=inv:getItems() local tile=H.player:getSquare()
        for i=items:size()-1,0,-1 do local item=items:get(i)
            local keep=H.config.lock_phase2_reload=="true" and item:getFullType()=="LivingFellows.LarchfieldManual"
            if not keep and not H.player:isEquipped(item) then inv:Remove(item) tile:AddWorldInventoryItem(item,.5,.5,0) end
        end
        H.lockProbe.catalogue={list=getWorld():getMetaGrid():getBuildings(),index=0}
        setPhase("lock_probe_catalogue",current) return
    end
    local f=H.lockProbe
    if H.phase=="lock_probe_catalogue" then
        local c=f.catalogue
        for _=1,256 do
            if c.index>=c.list:size() then break end
            local def=c.list:get(c.index) c.index=c.index+1
            local rooms=def:getRooms() local office,police=false,false
            for i=0,rooms:size()-1 do
                local name=string.lower(tostring(rooms:get(i):getName()))
                if name:find("police",1,true) or name:find("office",1,true) then office=true end
                if name:find("police",1,true) then police=true end
            end
            local d=(def:getX()-8140)^2+(def:getY()-11738)^2
            local towerDistance=(def:getX()-12700)^2+(def:getY()-2000)^2
            if office and def:getMaxLevel()>=4 and (def:getX2()-def:getX())*(def:getY2()-def:getY())<8000
                and (not c.towerDistance or towerDistance<c.towerDistance) then f.tower=def c.towerDistance=towerDistance end
            if police then d=d-100000000 end
            if office and (def:getX2()-def:getX())*(def:getY2()-def:getY())<4000 and (not c.best or d<c.best) then c.best=d f.def=def end
        end
        if c.index<c.list:size() then return end
        assert(f.def,"no real office metadata")
        H.player:teleportTo(f.def:getX()+3,f.def:getY()+3,0)
        setPhase("lock_probe_load",current) return
    elseif H.phase=="lock_probe_load" then
        if current-H.phaseStartedAt<7000 then return end
        f.cursor=0 f.width=f.def:getX2()-f.def:getX()+1 f.height=f.def:getY2()-f.def:getY()+1
        f.total=math.min(4096,f.width*f.height*(f.def:getMaxLevel()+1))
        setPhase("lock_probe_scan",current) return
    elseif H.phase=="lock_probe_scan" then
        for _=1,128 do
            if f.cursor>=f.total then break end
            local index=f.cursor f.cursor=index+1
            local x=f.def:getX()+index%f.width
            local y=f.def:getY()+math.floor(index/f.width)%f.height
            local z=math.floor(index/(f.width*f.height))
            local tile=getCell():getGridSquare(x,y,z) local objects=tile and tile:getObjects()
            for i=0,(objects and objects:size() or 0)-1 do
                local o=objects:get(i) local tag=tags(o)
                if SC.Terminal.isComputer(o) and not f.pc then f.pc=o end
                if (tag:find("telephone",1,true) or tag:find("phone",1,true)) and not f.phone then f.phone=o end
            end
        end
        if f.cursor<f.total then return end
        if not check("locks_native_computer",f.pc~=nil,"bounds="..f.def:getX()..","..f.def:getY().." scanned="..f.cursor) then
            cleanup(f) setPhase("finish",current) return
        end
        ready(H,f)
        if H.config.lock_acceptance_probe=="true" or H.config.lock_phase2_probe=="true" or H.config.lock_phase3_probe=="true" or H.config.lock_phase4_probe=="true" then
            f.window.drawHeaderLogo=f.originalLogo
            f.window.logoTexture=f.originalLogoTexture
            setPhase(H.config.lock_phase4_probe=="true" and "lock_probe_phase4_begin" or H.config.lock_phase3_probe=="true" and "lock_probe_phase3_begin" or H.config.lock_phase2_probe=="true" and "lock_probe_phase2_begin" or "lock_probe_accept_begin",current) return
        end
        inspect(H,f,check,result) f.theme=1
        setPhase("lock_probe_art",current) return
    elseif H.phase=="lock_probe_art" then
        local themes={"green","sand","aqua","purple"}
        if current-H.phaseStartedAt<2000 then return end
        shot(H,"art-"..themes[f.theme])
        check("locks_native_art_"..themes[f.theme],f.artDrawn==true,"native shader calls="..f.artCalls.." meanMs="..f.artMs/math.max(1,f.artCalls))
        f.theme=f.theme+1 f.artDrawn=false
        if f.theme<=#themes then
            f.window.system.theme=themes[f.theme]
            f.window.colors=SC.TerminalPresentation.colors(themes[f.theme])
            f.window:refreshLayout()
            setPhase("lock_probe_art",current) return
        end
        f.window.drawHeaderLogo=f.originalLogo f.window:close()
        setPhase("lock_probe_drawer",current) return
    elseif H.phase=="lock_probe_drawer" then
        if current-H.phaseStartedAt<1500 then return end
        local inv=f.loot
        if inv and f.desk then
            inv:setVisible(true) inv:refreshBackpacks()
            local floor
            for _,b in ipairs(inv.backpacks or {}) do
                if b.inventory==f.desk.container then f.button=b end
                if call(b.inventory,"getType")=="floor" then floor=b.inventory end
            end
            check("locks_native_drawer_button_loaded",f.button~=nil,"after native loot refresh at shared adjacent standing square")
            if f.button and floor then
                f.originalSelect,f.originalSet=inv.selectContainer,inv.setNewContainer
                -- Binding proof only. Phase 1 must chain in SCRuntime rather
                -- than installing a second global inventory-page wrapper.
                inv.selectContainer=function(page,b,...) if not f.drawerOpen and b.inventory==f.desk.container then return end
                    return f.originalSelect(page,b,...) end
                inv.setNewContainer=function(page,c,...) if not f.drawerOpen and c==f.desk.container then return end
                    return f.originalSet(page,c,...) end
                f.oldButton={}
                for _,key in ipairs({"onclick","onmousedown","onMouseUp","onMouseOver","onMouseOverOutside","textureOverride","tooltip"}) do
                    f.oldButton[key]=f.button[key] f.button[key]=nil
                end
                f.button.textureOverride=getTexture("media/ui/lock.png") f.button.tooltip="Locked by computer"
                inv:setNewContainer(floor)
                inv:selectContainer(f.button) inv:setNewContainer(f.desk.container)
                check("locks_native_drawer_guard",inv.inventoryPane.inventory==floor,"native plain desk refused click and automatic selection")
                shot(H,"drawer-locked")
                f.drawerOpen=true inv:selectContainer(f.button)
                check("locks_native_drawer_release",inv.inventoryPane.inventory==f.desk.container,"same real button selects the desk after release")
            end
        end
        if f.manual then
            local item=f.manual
            local world=item:getWorldItem()
            world:removeFromWorld() world:removeFromSquare() item:setWorldItem(nil)
            H.player:getInventory():AddItem(item)
            check("locks_native_manual_pickup",item:getContainer()==H.player:getInventory(),"same world item picked up with native ownership")
        end
        local inv=H.player:getInventory() f.radio=inv:AddItem("Base.RadioBlack")
        local data=call(f.radio,"getDeviceData")
        assert(data,"plain RadioBlack has no DeviceData")
        if not data:getHasBattery() then data:addBattery(inv:AddItem("Base.Battery")) end
        data:setPower(1) data:setChannel(96400) data:setIsTurnedOn(true)
        H.player:setPrimaryHandItem(f.radio)
        f.radioListener=function(guid,code,x,y,z,message,device)
            if tostring(message):find("LOCK PROBE",1,true) then f.received=true log("radio event="..tostring(message).." device="..tostring(device)) end
        end
        Events.OnDeviceText.Add(f.radioListener)
        setPhase("lock_probe_radio",current) return
    elseif H.phase=="lock_probe_radio" then
        if current-H.phaseStartedAt<2000 then return end
        if not f.sent then
            f.sent=current
            getZomboidRadio():SendTransmission(math.floor(H.player:getX())+2500,math.floor(H.player:getY()),96400,
                "LOCK PROBE LONG RANGE",nil,"LFLOCK",.8,1,.8,50000,false)
        end
        if not f.received and current-f.sent<10000 then return end
        check("locks_native_radio_2500",f.received==true,"plain RadioBlack tuned96.4; fixed source2500tiles; real OnDeviceText")
        Events.OnDeviceText.Remove(f.radioListener) f.radioListener=nil
        local x,y=math.floor(H.player:getX()),math.floor(H.player:getY())
        for dx=-12,12 do for dy=-12,12 do
            if #f.zombies<200 and dx*dx+dy*dy>=100 then
                local tile=getCell():getGridSquare(x+dx,y+dy,H.player:getZ())
                if tile and SC.GameplayUtil.isSquareFree(tile) then
                    local list=addZombiesInOutfit(x+dx,y+dy,H.player:getZ(),1,nil,0)
                    local z=list and list:get(0)
                    if z then f.zombies[#f.zombies+1]=z z:setTarget(nil) end
                end
            end
        end end
        setPhase("lock_probe_sensor",current) return
    elseif H.phase=="lock_probe_sensor" then
        local started=getTimestampMs()
        f.threat=SC.TerminalWorld.nearestThreat(H.player,f.memory,current)
        f.samples[#f.samples+1]=getTimestampMs()-started
        if #f.samples<100 then return end
        check("locks_sensor_population",#f.zombies>=200,"real spawned="..#f.zombies.." loaded="..getCell():getZombieList():size())
        check("locks_sensor_p95",percentile(f.samples,.95)<=1,"p50="..percentile(f.samples,.5).." p95="..percentile(f.samples,.95).." max="..f.samples[#f.samples])
        for _,z in ipairs(f.zombies) do z:removeFromWorld() z:removeFromSquare() end f.zombies={}
        log("damageKinds="..tostring(f.damageKinds.HEAVYLOAD).." HEAVYLOAD; native bindings run finished")
        f.damageKinds={}
        H.player:getStats():set(CharacterStat.HUNGER,.6)
        H.player:getStats():set(CharacterStat.THIRST,.6)
        assert(SC.Terminal.open(H.player,f.pc),"native terminal reopen failed")
        f.window=SC.Terminal.window f.window:flush() f.baseline=SC.TerminalLamp.health(H.player)
        f.idleHours=SC.ControlUtil.hours()
        setPhase("lock_probe_idle",current) return
    elseif H.phase=="lock_probe_idle" then
        local after=SC.TerminalLamp.health(H.player)
        if SC.TerminalLamp.hit(f.baseline,after,f.lastDamageKind) and not f.window.closed then f.window:close() end
        f.baseline=after
        if SC.ControlUtil.hours()-f.idleHours<1/6 then return end
        check("locks_native_noncontact_open",not f.window.closed,"ten game minutes hungry/thirsty plus minor hand burn")
        local player=H.player local best
        for _,d in ipairs({{1,0},{0,1},{-1,0},{0,-1}}) do
            local tile=getCell():getGridSquare(math.floor(player:getX())+d[1],math.floor(player:getY())+d[2],player:getZ())
            if tile and SC.GameplayUtil.isSquareFree(tile) then best=tile break end
        end
        assert(best,"no native contact-test standing square")
        local list=addZombiesInOutfit(best:getX(),best:getY(),best:getZ(),1,nil,0)
        f.attacker=list and list:get(0) assert(f.attacker,"native contact zombie missing")
        f.zombies={f.attacker} f.attacker:setTarget(player) f.attacker:spotted(player,true)
        setPhase("lock_probe_contact",current) return
    elseif H.phase=="lock_probe_contact" then
        local after=SC.TerminalLamp.health(H.player)
        if SC.TerminalLamp.hit(f.baseline,after,f.lastDamageKind) and not f.window.closed then f.window:close() end
        f.baseline=after
        if not f.window.closed and current-H.phaseStartedAt<45000 then return end
        check("locks_native_hit_closes",f.window.closed==true,"real target bite/scratch/contact; event="..tostring(f.hitEvent)
            .." bites="..after.bites.." scratches="..after.scratches.." health="..tostring(after.health))
        for kind,count in pairs(f.damageKinds) do log("damage type="..kind.." count="..count) end
        cleanup(f)
        result("SKIP","locks_remaining_phase_zero","reload, Louisville tower, crew, rival and force require further dedicated acceptance; not claimed complete")
        setPhase("finish",current) return
    end
end
return Probe
