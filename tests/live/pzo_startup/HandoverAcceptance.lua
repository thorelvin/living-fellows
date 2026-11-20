-- SPDX-License-Identifier: MIT
-- Production events, actual UI callbacks and a genuine native disk restart.
local SC=SurvivorCompanion
local s={phase='menu',checks=0,notes={}}
local function write(k,v) local w=assert(getFileWriter(k,true,false));w:write(v);w:close() end
local function read(k) local r=getFileReader(k,false);if not r then return end;local v=r:readLine();r:close();return v end
local mode=read('pzo-handover-mode.txt') or 'acceptance'
local reload=mode=='acceptance-reload' or mode=='interrupt-reload' or mode=='vehicle-reload' or mode=='dormant-reload'
local dormant=mode=='dormant' or mode=='dormant-reload'
local interrupt=mode=='interrupt'
local vehicle=mode=='vehicle' or mode=='vehicle-reload'
local function store() return ModData.getOrCreate('LF_HandoverAcceptance') end
local function check(v,why) s.checks=s.checks+1;assert(v,'Handover acceptance '..s.checks..': '..tostring(why)) end
local function phase(v) s.phase,s.at=v,getTimestampMs();write('pzo-handover-progress.txt',v..'\n') end
local function finish(ok,why)
    if s.done then return end;s.done=true
    write('pzo-handover-result.txt','result='..(ok and 'PASS' or 'FAIL')..'\nmode='..mode..'\nphase='..s.phase..'\nchecks='..s.checks
        ..'\nreason='..tostring(why)..'\n'..table.concat(s.notes,'\n')..'\n')
end
local function spawnSquare()
    local q=getSpecificPlayer(0):getSquare()
    for radius=1,8 do for dx=-radius,radius do for dy=-radius,radius do
        local square=getCell():getGridSquare(q:getX()+dx,q:getY()+dy,q:getZ())
        if square and SC.GameplayUtil.isClearActorSpawnSquare(square) and square:isFree(false) then return square end
    end end end
end
local function click(button) check(button and button.enable~=false,'actual UI button is enabled');button.onclick(button.target,button) end
local function tagged(container,key)
    local n=0;local items=container:getItems()
    for i=0,items:size()-1 do local item=items:get(i)
        if item:getModData()[key] then n=n+1 end
        if instanceof(item,'InventoryContainer') then n=n+tagged(item:getInventory(),key) end
    end
    return n
end
local function corpseLoot()
    local saved=store();local count=0
    for dx=-3,3 do for dy=-3,3 do local square=getCell():getGridSquare(saved.deadX+dx,saved.deadY+dy,saved.deadZ)
        if square then local bodies=square:getDeadBodys()
            for i=0,bodies:size()-1 do local body=bodies:get(i)
                count=count+tagged(body:getContainer(),'LF_HandoverDeadGear')
                check(tagged(body:getContainer(),'LF_HandoverProof')==0,'companion gear was not copied into a corpse')
            end
        end
    end end
    return count
end
Events.OnInitGlobalModData.Add(function()
    local world=ModData.getOrCreate(SC.Identity.worldSaveKey)
    if not reload and mode~='dormant' then world.document={schema=SC.Identity.saveSchema,companions={},factionActors={}}
    else
        local saved=store()
        -- Deliberately reintroduce a stale companion snapshot. The real restore
        -- transaction must exclude a permanent successor before creating actors.
        if saved.source and world.document then world.document.companions[saved.source.id]=saved.source end
    end
end)
Events.OnMainMenuEnter.Add(function() MainScreen.continueLatestSave('Sandbox','PzoRestoreFixture') end)
local seen={}
Events.OnRenderTick.Add(function()
    local modal=MainScreen and MainScreen.instance and MainScreen.instance.checkSavefileModal
    if modal and modal.yes and not seen[modal] then seen[modal]=true;modal:onClick(modal.yes) end
end)
Events.OnGameStart.Add(function()
    SC.Scheduler.unregister('decision');s.original=getSpecificPlayer(0);phase('load')
end)
local function step()
    if s.done or s.phase=='menu' then return end
    local age=getTimestampMs()-s.at
    if s.phase=='load' and age>12000 then
        check(SC.Identity.release=='0.27.46' and SCBridge.getProtocol()==SC.Identity.bridgeProtocol and PZOEngine,'final production source and official PZO')
        if reload then
            local saved=store();local player=getSpecificPlayer(0)
            check(player:getModData().LF_HandoverToken==saved.token,'same successor reopened from native player database')
            check(player:getDescriptor():getForename()=='Mara','identity persisted')
            check(tagged(player:getInventory(),'LF_HandoverProof')==1,'one exact equipment set after disk reload')
            check(player:getBodyDamage():getBodyPart(BodyPartType.Hand_L):getCutTime()>0,'wound remains after reopen')
            check(player:getPerkLevel(Perks.Doctor)==3 and player:getXp():getXP(Perks.Doctor)>=saved.xp,'native skills and fractional experience persist')
            if vehicle then check(player:getVehicle() and player:getVehicle():getSqlId()==saved.car and player:getVehicle():getSeat(player)==saved.seat,'same native vehicle and seat survive actual restart') end
            check(SC.Handover.retired(saved.id) and SC.Registry.byId(saved.id)==nil and not SC.Persistence.isPending(saved.id),'stale snapshot cannot restore the successor as an NPC')
            if mode=='interrupt-reload' then
                check(SC.Handover.current()==nil and SC.Handover.pendingReceipt()==nil,'interrupted ownership completed before play')
                check(SCBridge.handoverPlayerSaved(saved.token),'recovery reached a durable native player row')
                check(corpseLoot()==1,'original corpse gear survives forced interruption')
                check(SC.Handover.greeting()~=nil,'recovered successor receives their greeting')
            else check(SC.Handover.greeting()==nil,'consumed EMMA greeting does not repeat after disk reload') end
            check(SC.BaseLife.active() and SC.BaseLife.active().name=='Handover Test Camp','camp remains after death and disk reload')
            finish(true,'production takeover, durable ownership and actual stale-snapshot disk reload passed');return
        end
        if mode=='dormant' then
            local saved=store()
            check(SC.Registry.byId(saved.id)==nil and SC.Persistence.isPending(saved.id),'saved recruit starts genuinely unloaded after disk restart')
            check(SC.Persistence.pendingBootstrap(saved.id)~=nil,'normal persistence owns a valid cold bootstrap')
            saved.deadX,saved.deadY,saved.deadZ=math.floor(s.original:getX()),math.floor(s.original:getY()),math.floor(s.original:getZ())
            s.original:getBodyDamage():ReduceGeneralHealth(101);s.original:setHealth(0);phase('death');return
        end
        check(SC.BaseLife.create(s.original:getSquare(),'Handover Test Camp')==true,'camp established')
        local dead=assert(instanceItem('Base.Bandage'));dead:getModData().LF_HandoverDeadGear=true;s.original:getInventory():AddItem(dead)
        local saved=store();saved.deadX,saved.deadY,saved.deadZ=math.floor(s.original:getX()),math.floor(s.original:getY()),math.floor(s.original:getZ())
        s.ticket=assert(SC.Actor.beginSpawn(assert(spawnSquare()),{recruited=true,identity={forename='Mara',surname='Handover',gender='woman',outfit='Generic01'}}))
        phase('spawn')
    elseif s.phase=='spawn' then
        local actor,why=SC.Actor.pollSpawn(s.ticket)
        if not actor then assert(why=='spawn_pending' and age<15000,tostring(why));return end
        s.actor=actor
        local item=assert(instanceItem('Base.Bandage'));item:getModData().LF_HandoverProof=true;actor:getInventory():AddItem(item)
        actor:getBodyDamage():getBodyPart(BodyPartType.Hand_L):setCutTime(17)
        actor:setPerkLevelDebug(Perks.Doctor,3);actor:getXp():setXPToLevel(Perks.Doctor,3)
        actor:getXp():AddXP(Perks.Doctor,.375,true,false,false,false)
        local saved=store();saved.id=SC.Registry.idOf(actor);saved.item=tostring(item:getID());saved.x,saved.y=actor:getX(),actor:getY()
        saved.xp=actor:getXp():getXP(Perks.Doctor)
        if vehicle then
            local selected,best
            for _,car in ipairs(SC.Vehicle.loadedVehicles()) do
                local distance=(car:getX()-s.original:getX())^2+(car:getY()-s.original:getY())^2
                if car:getSqlId()>=0 and car:getMaxPassengers()>1 and car:getCharacter(1)==nil and (not best or distance<best) then selected,best=car,distance end
            end
            check(selected~=nil,'actual saved native car with a free passenger seat')
            actor:setX(selected:getX());actor:setY(selected:getY());actor:setZ(selected:getZ())
            selected:enter(1,actor);selected:setCharacterPosition(actor,1,'inside')
            selected:transmitCharacterPosition(1,'inside');selected:playPassengerAnim(1,'idle')
            check(actor:getVehicle()==selected and selected:getSeat(actor)==1,'source companion occupies the real passenger seat')
            saved.car,saved.seat=selected:getSqlId(),1;saved.x,saved.y=actor:getX(),actor:getY()
        end
        saved.source=assert(SC.Persistence.captureRecord(SC.Registry.byId(saved.id),nil,{preserveNativeIds=true}))
        if mode=='dormant-setup' then
            saved.fixtureToken='lf-handover-dormant-fixture-20261120-0001'
            s.original:getModData().LF_HandoverFixture=saved.fixtureToken
            s.original:teleportTo(math.floor(s.original:getX()+400),math.floor(s.original:getY()),0)
            SCBridge.requestHandoverPlayerSave();phase('prepare-cold');return
        end
        check(SC.Handover.begin(s.original)==false,'alive primary cannot enter Handover')
        s.original:getBodyDamage():ReduceGeneralHealth(101);s.original:setHealth(0);phase('death')
    elseif s.phase=='prepare-cold' and age>12000 then
        local saved=store()
        check(SCBridge.handoverPlayerSaved(saved.fixtureToken),'distant original primary row is durably saved before cold restart')
        save(false)
        ModData.getOrCreate(SC.Identity.worldSaveKey).document.companions[saved.id]=saved.source
        SCSplitScreenProbe.flushGlobalModDataForWorldExit()
        finish(true,'cold source and distant primary saved for actual disk restart')
    elseif s.phase=='death' then
        if not SC.Handover.current() then assert(age<15000,'death did not enter production Handover');return end
        if age<3500 then return end
        check(SC.Handover.isChoosing(),'native death event entered paused chooser')
        s.clock=getGameTime():getWorldAgeHours()
        local w=assert(SC.HandoverUI.open())
        check(#w.list.items>=1,'actual chooser lists living recruits')
        for index,item in ipairs(w.list.items) do if item.item.id==store().id then w.list.selected=index end end
        check(w.newButton.enable~=false and w.normalButton.enable~=false,'camp and ordinary respawn alternatives exist')
        s.window=w;phase('choose-visible')
    elseif s.phase=='choose-visible' and age>750 then
        getCore():TakeFullScreenshot('handover-choice.png')
        click(s.window.takeButton)
        if interrupt then
            local receipt=assert(SC.Handover.pendingReceipt())
            check(receipt.phase=='committing' and type(receipt.snapshot)=='string','durable receipt owns pending native admission')
            store().token=receipt.token
            -- Stop only the coordinator's loader poll; the outside runner now
            -- kills this fixture without saving or a clean menu exit.
            SC.Handover.pulse=function() end
            check(not SCBridge.handoverPlayerSaved(receipt.token),'new primary row is not yet committed at crash point')
            SCSplitScreenProbe.flushGlobalModDataForWorldExit()
            finish(true,'forced interruption armed after source retirement and before native admission')
        else phase('takeover') end
    elseif s.phase=='takeover' then
        if getTimestampMs()>=(s.diagAt or 0) then
            s.diagAt=getTimestampMs()+1000
            local current=SC.Handover.current();local pending=SC.Persistence.pendingSnapshot()[store().id]
            local slot=getSpecificPlayer(1);local sq=slot and slot:getCurrentSquare()
            write('pzo-handover-native-state.txt','phase='..tostring(current and current.phase)..'\nowner='..tostring(SC.ViewSession.owner())
                ..'\nslotSquare='..tostring(sq and sq:getX())..','..tostring(sq and sq:getY())
                ..'\nrecord='..tostring(SC.Registry.byId(store().id)~=nil)..'\npending='..tostring(pending and pending.status)..':'..tostring(pending and pending.reason)..'\n')
        end
        if SC.Handover.current() then assert(age<45000,'takeover pending: '..tostring(SC.Handover.error()));return end
        local saved=store();local player=getSpecificPlayer(0)
        check(player~=s.original and player~=s.actor and player:isLocalPlayer() and not player:isNpc(),'actual companion became a stock primary player')
        check(player:getDescriptor():getForename()=='Mara','companion identity kept')
        local item=player:getInventory():getItemFromType('Base.Bandage')
        check(item and tostring(item:getID())==saved.item,'exact item ID kept')
        check(tagged(player:getInventory(),'LF_HandoverProof')==1 and tagged(player:getInventory(),'LF_HandoverDeadGear')==0,'one companion kit and no dead-player gear')
        check(player:getBodyDamage():getBodyPart(BodyPartType.Hand_L):getCutTime()>0,'takeover did not heal')
        check(player:getPerkLevel(Perks.Doctor)==3 and math.abs(player:getXp():getXP(Perks.Doctor)-saved.xp)<.001,'native skill level and fractional XP kept exactly')
        if vehicle then check(player:getVehicle() and player:getVehicle():getSqlId()==saved.car and player:getVehicle():getSeat(player)==saved.seat,'stock player retained exact native passenger seat') end
        check(math.abs(player:getX()-saved.x)<1 and math.abs(player:getY()-saved.y)<1,'takeover stayed at companion location')
        check(SC.Registry.byId(saved.id)==nil and SC.Handover.retired(saved.id),'permanent companion retirement')
        saved.token=player:getModData().LF_HandoverToken
        check(SCBridge.handoverPlayerSaved(saved.token),'native commit proof completed before resumed play')
        check((s.pausedDelta or 0)<0.0002,'selection and transfer did not advance world time')
        if not dormant then check(corpseLoot()==1,'original player corpse retains its own gear exactly once') end
        check(SC.Handover.greeting()~=nil and SC.Handover.greeting()==nil,'EMMA recognizes new operator once')
        check(SC.Persistence.save(player)==true,'complete world saves with successor excluded')
        save(false);phase('settle-save')
    elseif s.phase=='settle-save' and age>3000 then finish(true,'production UI takeover and native commit passed; disk reload next') end
end
Events.OnRenderTick.Add(function()
    if s.done then return end
    if s.clock and SC.Handover.isPaused() then s.pausedDelta=math.max(s.pausedDelta or 0,math.abs(getGameTime():getWorldAgeHours()-s.clock)) end
    local okay,why=pcall(step);if not okay then finish(false,why) end
end)
