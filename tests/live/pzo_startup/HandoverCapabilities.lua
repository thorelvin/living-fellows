-- SPDX-License-Identifier: MIT
-- Disposable native lifecycle proof: real death, stock admission and disk reopen.
local SC=SurvivorCompanion
local s={phase='menu',checks=0,notes={}}
local function write(name,value) local w=assert(getFileWriter(name,true,false));w:write(value);w:close() end
local function read(name) local r=getFileReader(name,false);if not r then return end;local v=r:readLine();r:close();return v end
local mode=read('pzo-handover-mode.txt') or 'create'
local camp=mode=='camp-create' or mode=='camp-reload'
local remote=camp or mode=='remote-create' or mode=='remote-reload'
local reloading=camp and mode=='camp-reload' or mode=='reload' or mode=='remote-reload'
local function check(v,why) s.checks=s.checks+1;assert(v,'Handover '..s.checks..': '..tostring(why)) end
local function phase(v) s.phase,s.at=v,getTimestampMs();write('pzo-handover-progress.txt',v..'\n') end
local function note(v) s.notes[#s.notes+1]=v;print('SC_HANDOVER_PROOF '..v) end
local function finish(ok,why)
    if s.done then return end;s.done=true
    write('pzo-handover-result.txt','result='..(ok and 'PASS' or 'FAIL')..'\nmode='..mode..'\nphase='..s.phase
        ..'\nchecks='..s.checks..'\nreason='..tostring(why)..'\n'..table.concat(s.notes,'\n')..'\n')
end
local function verify(player,store)
    check(player and not player:isDead() and not player:isNpc() and player:isLocalPlayer(),'stock local player is alive and human controlled')
    check(not SCBridge.isCompanion(player) and player:getPlayerNum()==0,'successor is not an autonomous companion')
    check(player:getDescriptor():getForename()==(camp and 'New' or 'Handover'),'chosen identity preserved')
    check(player:getModData().LF_HandoverToken==store.token,'receipt token preserved')
    local item=player:getInventory():getItemFromType('Base.Bandage')
    if not camp then
        check(item and tostring(item:getID())==store.item,'exact inventory ID preserved')
        check(item:getModData().LF_HandoverProof==true,'item custom data preserved')
    else check(not item or item:getModData().LF_HandoverProof~=true,'fresh character receives no companion equipment') end
    check(math.abs(player:getX()-store.x)<1 and math.abs(player:getY()-store.y)<1,'current companion location preserved')
    local part=player:getBodyDamage():getBodyPart(BodyPartType.Hand_L)
    check(camp and part:getCutTime()==0 or not camp and part:getCutTime()>0,'new or inherited medical state is correct')
    if not camp then check(SC.Registry.byId(store.id)==nil,'companion representation absent') end
end
Events.OnInitGlobalModData.Add(function()
    if not reloading then ModData.getOrCreate(SC.Identity.worldSaveKey).document={schema=SC.Identity.saveSchema,companions={},factionActors={}} end
end)
Events.OnMainMenuEnter.Add(function() MainScreen.continueLatestSave('Sandbox','PzoRestoreFixture') end)
local seen={}
Events.OnRenderTick.Add(function()
    local modal=MainScreen and MainScreen.instance and MainScreen.instance.checkSavefileModal
    if modal and modal.yes and not seen[modal] then seen[modal]=true;modal:onClick(modal.yes) end
end)
Events.OnGameStart.Add(function()
    SC.Scheduler.unregister('decision');s.primary=assert(getSpecificPlayer(0));phase('load')
end)
local function step()
    if s.done or s.phase=='menu' then return end
    local age=getTimestampMs()-s.at
    if s.phase=='load' and age>12000 then
        check(SCBridge and PZOEngine and SC.Actor.checkBridge(true),'official PZO and production bridge')
        if reloading then
            local store=ModData.getOrCreate('LF_HandoverNativeProof');verify(s.primary,store)
            check(SCBridge.handoverPlayerSaved(store.token),'committed native primary row verified after reopen')
            if remote then
                local saved=ModData.getOrCreate(SC.Identity.worldSaveKey).document.companions[store.crewId]
                check(saved and math.abs(saved.position.x-store.crewX)<1 and math.abs(saved.position.y-store.crewY)<1,
                    'remote crew saved in its actual distant location across disk reopen')
            end
            finish(true,'real native disk reopen preserved the successor')
            return
        end
        local q=s.primary:getSquare();local spawn
        for r=1,8 do if not spawn then for dx=-r,r do for dy=-r,r do
            local c=getCell():getGridSquare(q:getX()+dx,q:getY()+dy,q:getZ())
            if c and SC.GameplayUtil.isClearActorSpawnSquare(c) and c:isFree(false) then spawn=c;break end
        end if spawn then break end end end end
        check(spawn~=nil,'loaded companion tile')
        s.ticket=assert(SC.Actor.beginSpawn(spawn,{recruited=true,identity={forename='Handover',surname='Proof',gender='woman',outfit='Generic01'}}))
        phase('spawn')
    elseif s.phase=='spawn' then
        local actor,why=SC.Actor.pollSpawn(s.ticket)
        if not actor then assert(why=='spawn_pending' and age<15000,tostring(why));return end
        s.actor=actor
        local item=assert(instanceItem('Base.Bandage'));item:getModData().LF_HandoverProof=true;actor:getInventory():AddItem(item)
        actor:getBodyDamage():getBodyPart(BodyPartType.Hand_L):setCutTime(17)
        local store=ModData.getOrCreate('LF_HandoverNativeProof')
        store.id=SC.Registry.idOf(actor);store.item=tostring(item:getID());store.x=actor:getX();store.y=actor:getY()
        store.token='lf-handover-native-proof-20261120-0001'
        s.snapshot=SCBridge.captureHandoverPlayer(actor)
        check(type(s.snapshot)=='string' and #s.snapshot>100,'complete native snapshot')
        s.successor=SCBridge.prepareHandoverPlayer(s.snapshot,store.token)
        check(getSpecificPlayer(0)==s.primary and IsoPlayer.getInstance()==s.primary,'preparation preserves primary ownership')
        check(s.successor~=actor and not s.successor:isNpc(),'prepared stock player')
        if remote then
            local q=s.primary:getSquare();local free
            for dx=-8,8 do if not free then for dy=-8,8 do
                local c=getCell():getGridSquare(q:getX()+dx,q:getY()+dy,q:getZ())
                if c and c~=actor:getSquare() and SC.GameplayUtil.isClearActorSpawnSquare(c) and c:isFree(false) then free=c;break end
            end end end
            s.ticket2=assert(SC.Actor.beginSpawn(assert(free,'crew tile'),{recruited=true,identity={forename='Stranded',surname='Crew',gender='man',outfit='Generic01'}}))
            phase('spawn-crew')
        else s.primary:getBodyDamage():ReduceGeneralHealth(101);s.primary:setHealth(0);phase('death') end
    elseif s.phase=='spawn-crew' then
        local actor,why=SC.Actor.pollSpawn(s.ticket2)
        if not actor then assert(why=='spawn_pending' and age<15000,tostring(why));return end
        s.crew=actor
        local store=ModData.getOrCreate('LF_HandoverNativeProof')
        store.crewId,store.crewX,store.crewY=SC.Registry.idOf(actor),actor:getX(),actor:getY()
        check(SC.ViewSession.claim('base_watch',actor)==true,'remote simulation owns a crew member before death')
        phase('crew-join')
    elseif s.phase=='crew-join' then
        if getSpecificPlayer(1)~=s.crew then assert(age<20000,'crew view join timed out');return end
        s.primary:getBodyDamage():ReduceGeneralHealth(101);s.primary:setHealth(0);phase('death')
    elseif s.phase=='death' and age>3500 then
        check(s.primary:isDead(),'native primary death')
        if not camp then check(SC.Actor.remove(s.actor)==true,'source retired without a corpse') end
        check(SC.Persistence.save(s.primary)==true,'companion removal captured')
        SCSplitScreenProbe.flushGlobalModDataForWorldExit()
        s.clock=getGameTime():getWorldAgeHours();setGameSpeed(0)
        if camp then
            local store=ModData.getOrCreate('LF_HandoverNativeProof');store.x=store.x+400
            CoopCharacterCreation:newPlayerMouse()
            local w=assert(CoopCharacterCreation.instance)
            w.mapSpawnSelect:useDefaultSpawnRegion()
            w.charCreationMain.forenameEntry:setText('New');w.charCreationMain.surnameEntry:setText('Arrival')
            local accept=w.accept1
            w.accept1=function(self)
                if not accept(self) then return false end
                getWorld():setLuaPosX(math.floor(store.x));getWorld():setLuaPosY(math.floor(store.y));getWorld():setLuaPosZ(0)
                return true
            end
            setGameSpeed(0);phase('camp-creator')
        else check(SCBridge.admitHandoverPlayer(s.successor)==true,'stock existing-character admission');phase('admit-paused') end
    elseif s.phase=='camp-creator' then
        setGameSpeed(0)
        if age<500 then return end
        CoopCharacterCreation.instance:accept();setGameSpeed(0);phase('admit-paused')
    elseif s.phase=='admit-paused' then
        local admitted=SCBridge.pollHandoverPlayerAdmission()
        if camp and admitted then s.successor=admitted;admitted:getModData().LF_HandoverToken=ModData.getOrCreate('LF_HandoverNativeProof').token end
        if getSpecificPlayer(0)~=s.successor then assert(age<20000,'stock admission did not progress while paused');return end
        verify(s.successor,ModData.getOrCreate('LF_HandoverNativeProof'))
        note('paused_admission_clock_delta='..tostring(getGameTime():getWorldAgeHours()-s.clock))
        check(math.abs(getGameTime():getWorldAgeHours()-s.clock)<0.0001,'world clock paused during admission')
        setGameSpeed(1)
        if remote then
            check(getSpecificPlayer(1)==s.crew and SCBridge.isCompanion(s.crew),'remote crew ownership survives primary replacement')
            local store=ModData.getOrCreate('LF_HandoverNativeProof')
            if not camp then store.x,store.y=store.x+400,store.y;s.successor:teleportTo(store.x,store.y,0) end
            phase('remote-stream')
        else SCBridge.requestHandoverPlayerSave();phase('save') end
    elseif s.phase=='remote-stream' and age>12000 then
        local store=ModData.getOrCreate('LF_HandoverNativeProof')
        check(getSpecificPlayer(0)==s.successor and getSpecificPlayer(1)==s.crew,'distant primary and crew remain in their owned slots')
        check(s.crew:getCurrentSquare()~=nil and not s.crew:isDead() and s.crew:isBridgeHealthy(),'old region crew stays loaded and healthy')
        check(math.abs(s.crew:getX()-store.crewX)<1 and math.abs(s.crew:getY()-store.crewY)<1,'crew was not teleported with successor')
        SCBridge.requestHandoverPlayerSave();phase('save')
    elseif s.phase=='save' and age>3000 then
        if not SCBridge.handoverPlayerSaved(ModData.getOrCreate('LF_HandoverNativeProof').token) then
            assert(age<30000,'native player row never committed');return
        end
        save(false);finish(true,'native death, paused stock admission and committed primary save; reopen next')
    end
end
Events.OnRenderTick.Add(function()
    if s.done then return end
    local ok,why=pcall(step);if not ok then finish(false,why) end
end)
