-- SPDX-License-Identifier: MIT
-- Actual camp creator, cancellation, surviving crew and native radio rescue.
local SC=SurvivorCompanion
local s={phase='menu',checks=0,routeReasons={}}
local function write(k,v) local w=assert(getFileWriter(k,true,false));w:write(v);w:close() end
local rescuePulse=SC.HandoverRescue.pulse
SC.HandoverRescue.pulse=function(...)
    s.rescuePulses=(s.rescuePulses or 0)+1
    return rescuePulse(...)
end
local loadCandidate=SC.HandoverRescue.loadCandidate
SC.HandoverRescue.loadCandidate=function(...)
    local okay,why=loadCandidate(...)
    s.loadCalls,s.loadReason=(s.loadCalls or 0)+1,tostring(why)
    return okay,why
end
local nativeResult=SC.HandoverRescue.navigationResult
SC.HandoverRescue.navigationResult=function(actor,target,handled,reason)
    local row=ModData.getOrCreate(SC.Handover.KEY).crew[SC.Registry.idOf(actor)]
    local before=row and row.target
    local x,y,z=SC.GameplayUtil.position(actor)
    nativeResult(actor,target,handled,reason)
    local signature=tostring(handled)..':'..tostring(reason)..':'..tostring(row and row.lastShelterFailure)
    if signature~=s.routeSignature and #s.routeReasons<256 then
        s.routeSignature=signature
        s.routeReasons[#s.routeReasons+1]=getTimestampMs()..' handled='..tostring(handled)..' reason='..tostring(reason)
            ..' at='..tostring(x)..','..tostring(y)..','..tostring(z)
            ..' target='..tostring(before and before.buildingId)..' rejected='..tostring(row and row.target~=before)
            ..' failure='..tostring(row and row.lastShelterFailure)
        write('pzo-handover-reasons.txt',table.concat(s.routeReasons,'\n')..'\n')
    end
end
local function read(k) local r=getFileReader(k,false);if not r then return end;local v=r:readLine();r:close();return v end
local mode=read('pzo-handover-mode.txt') or 'new'
local seeking=mode=='rescue-seeking' or mode=='rescue-seeking-reload'
local reload=mode=='new-reload' or mode=='rescue-reload' or mode=='rescue-seeking-reload'
local rescue=mode:find('^rescue')~=nil
local function store() return ModData.getOrCreate('LF_HandoverNewAcceptance') end
local function check(v,why) s.checks=s.checks+1;assert(v,'New survivor '..s.checks..': '..tostring(why)) end
local function phase(v) s.phase,s.at=v,getTimestampMs();write('pzo-handover-progress.txt',v..'\n') end
local function finish(ok,why)
    if s.done then return end;s.done=true
    write('pzo-handover-result.txt','result='..(ok and 'PASS' or 'FAIL')..'\nrelease='..SC.Identity.release..'\nmode='..mode..'\nphase='..s.phase..'\nchecks='..s.checks..'\nreason='..tostring(why)..'\n')
end
local function click(b) check(b and b.enable~=false,'real UI button enabled');b.onclick(b.target,b) end
local function tagCount(container)
    local n=0;local items=container:getItems()
    for i=0,items:size()-1 do local item=items:get(i)
        if item:getModData().LF_HandoverCrewGear then n=n+1 end
        if instanceof(item,'InventoryContainer') then n=n+tagCount(item:getInventory()) end
    end
    return n
end
local function radio(actor)
    local inv=actor:getInventory();local item=assert(inv:AddItem('Base.WalkieTalkie2'))
    local data=item:getDeviceData()
    if data:getHasBattery() and data:getPower()<=0 then data:getBattery(inv) end
    if not data:getHasBattery() then data:addBattery(assert(inv:AddItem('Base.Battery'))) end
    data:setChannel(90000);data:setDeviceVolume(.8);data:setIsTurnedOn(true);actor:setSecondaryHandItem(item)
    return item
end
local function spawnSquare()
    local q=s.original:getSquare()
    for radius=1,8 do for dx=-radius,radius do for dy=-radius,radius do
        local square=getCell():getGridSquare(q:getX()+dx,q:getY()+dy,q:getZ())
        if square and SC.GameplayUtil.isClearActorSpawnSquare(square) and square:isFree(false) then return square end
    end end end
end
local function spawn()
    s.ticket=assert(SC.Actor.beginSpawn(assert(spawnSquare()),{recruited=true,identity={forename='Mara',surname='Camp',gender='woman',outfit='Generic01'}}))
    phase('spawn')
end
local function shelterDoors(place,locked)
    local count=0
    for x=place.bounds.x-1,place.bounds.x2+1 do for y=place.bounds.y-1,place.bounds.y2+1 do
        local square=getCell():getGridSquare(x,y,0)
        local objects=square and square:getObjects()
        for i=0,objects and objects:size()-1 or -1 do local object=objects:get(i)
            if instanceof(object,'IsoDoor') then
                if locked and object:IsOpen() then object:ToggleDoorSilent() end
                object:setLocked(locked);object:setLockedByKey(locked)
                if not locked and not object:IsOpen() then object:ToggleDoorSilent() end
                if locked then
                    check(object:isLocked() and not object:IsOpen(),'initial shelter entrance is physically locked and closed')
                    s.lockedDoors[#s.lockedDoors+1]=object
                end
                count=count+1
            end
        end
    end end
    return count
end
local function blockFirstShelter(row)
    if s.lockedDoors then return end
    SC.HandoverRescue.commands(s.actor,getSpecificPlayer(0),SC.Commands.peek(s.actor))
    check(row and row.target and row.phase=='seeking_shelter','normal rescue selected its first shelter')
    local first=assert(SC.ExpeditionPlaces.atPoint(row.target));s.firstShelter=first.id;s.lockedDoors={}
    check(shelterDoors(first,true)>0,'first selected shelter has a real locked door')
    local x,y=SC.GameplayUtil.position(s.actor)
    local places=assert(SC.ExpeditionPlaces.nearby(math.floor(x),math.floor(y),40,64,true))
    local alternatives=0
    for _,place in ipairs(places) do
        if place.id~=first.id and place.kind=='residence' and place.groundFloor
            and shelterDoors(place,false)>0 then alternatives=alternatives+1 end
    end
    check(alternatives>0,'a different nearby native residence has open entrances for fallback')
    store().firstShelter=first.id
end
Events.OnInitGlobalModData.Add(function()
    if not reload then ModData.getOrCreate(SC.Identity.worldSaveKey).document={schema=SC.Identity.saveSchema,companions={},factionActors={}} end
    if reload then
        local saved=store()
        local doc=ModData.getOrCreate(SC.Identity.worldSaveKey).document.companions[saved.id]
        s.persistedBonds=doc and doc.recruited and doc.personality.trust==saved.trust and doc.personality.bond==saved.bond
    end
end)
Events.OnMainMenuEnter.Add(function() MainScreen.continueLatestSave('Sandbox','PzoRestoreFixture') end)
local seen={}
Events.OnRenderTick.Add(function()
    local modal=MainScreen and MainScreen.instance and MainScreen.instance.checkSavefileModal
    if modal and modal.yes and not seen[modal] then seen[modal]=true;modal:onClick(modal.yes) end
end)
local function onGameStart()
    s.original=getSpecificPlayer(0)
    setGameSpeed(1)
    if seeking and reload then
        local saved=store();local row=ModData.getOrCreate(SC.Handover.KEY).crew[saved.id]
        check(row and row.phase=='seeking_shelter' and row.target.buildingId==saved.firstShelter,
            'native restart begins with the exact saved seeking shelter')
        check(row.target.pathNodes==saved.seekingNodes and row.shelterActiveMs==saved.seekingMs,
            'native restart preserves route length and consumed service budget')
        s.seekingRestored=true
        local q=getCell():getGridSquare(row.target.x,row.target.y,row.target.z)
        write('pzo-handover-seeking.txt','targetInitiallyLoaded='..tostring(q~=nil)..'\nphase='..row.phase
            ..'\npathNodes='..tostring(row.target.pathNodes)..'\nactiveMs='..tostring(row.shelterActiveMs)..'\n')
    end
    phase('load')
end
Events.OnGameStart.Add(function() local okay,why=pcall(onGameStart);if not okay then finish(false,why) end end)
Events.OnCreatePlayer.Add(function(index,player)
    if rescue and index==0 and SC.Handover.current() and SC.Handover.current().phase=='creating' then radio(player) end
end)
local function step()
    if s.done or s.phase=='menu' then return end
    local age=getTimestampMs()-s.at
    if s.phase=='load' and age>12000 then
        local saved=store();local player=getSpecificPlayer(0)
        if not s.checkedLoad then
        check(SCBridge and PZOEngine and SC.Handover,'actual production modules')
        if reload then
            check(player:getModData().LF_HandoverToken==saved.token and player:getDescriptor():getForename()=='Renewed','fresh character persists through native disk restart')
            check(tagCount(player:getInventory())==0,'fresh character never inherits companion equipment')
            check(SC.BaseLife.active().name=='Handover New Camp' and SC.BaseLife.isInside(player),'fresh survivor reopens at the original camp')
            check(s.persistedBonds,'exact saved recruitment and bonds survive native restart')
            check(not SC.Handover.retired(saved.id),'remaining companion was not consumed')
        end
        s.checkedLoad=true
        end
        if reload then
            if seeking then
                local record=SC.Registry.byId(saved.id)
                if not s.restoreAt or getTimestampMs()-s.restoreAt>=1000 then
                    s.restoreAt=getTimestampMs()
                    local pending=SC.Persistence.pendingSnapshot()[saved.id] or {}
                    local row=ModData.getOrCreate(SC.Handover.KEY).crew[saved.id]
                    local candidate=SC.Persistence.pendingBootstrap(saved.id)
                    write('pzo-handover-restore.txt','record='..tostring(record~=nil)..'\nowner='..tostring(SC.ViewSession.owner())
                        ..'\nsecondary='..tostring(getSpecificPlayer(1)~=nil)..'\nphase='..tostring(row and row.phase)
                        ..'\npending='..tostring(pending.status)..':'..tostring(pending.reason)
                        ..'\nloaderCandidate='..tostring(candidate~=nil)..'\nerror='..tostring(SC.Handover.error())
                        ..'\npulses='..tostring(s.rescuePulses)..'\nloadCalls='..tostring(s.loadCalls)..'\nloadReason='..tostring(s.loadReason)
                        ..'\npaused='..tostring(SC.Handover.isPaused())..'\nplayerDead='..tostring(SC.GameplayUtil.isDead(player))
                        ..'\nrenderHook='..tostring(SC.Handover._render~=nil)..'\n')
                end
                if not record then assert(age<45000,'saved seeking companion is still streaming');return end
                check(s.seekingRestored,'seeking row was verified before normal simulation resumed')
                s.actor,s.firstShelter,s.lockedDoors=record.actor,saved.firstShelter,{}
                local first=assert(SC.ExpeditionPlaces.atPoint(saved.seekingTarget))
                for x=first.bounds.x-1,first.bounds.x2+1 do for y=first.bounds.y-1,first.bounds.y2+1 do
                    local q=getCell():getGridSquare(x,y,0)
                    if q then for i=0,q:getObjects():size()-1 do local object=q:getObjects():get(i)
                        if instanceof(object,'IsoDoor') then
                            check(object:isLocked() and not object:IsOpen(),'saved failed-house door remains locked and shut')
                            s.lockedDoors[#s.lockedDoors+1]=object
                        end
                    end end
                end end
                check(#s.lockedDoors>0,'reloaded seeking case observes original native doors without changing them')
                phase('rescue');return
            end
            if rescue then
                check(saved.radioHelp and saved.radioShelter,'real radio and shelter outcomes survive restart')
                check(saved.rescueRetargeted and saved.firstShelter~=saved.finalShelter,
                    'verified locked-house reselection survives native disk restart')
                local rescueRow=ModData.getOrCreate(SC.Handover.KEY).crew[saved.id]
                check(rescueRow and rescueRow.phase=='sheltered'
                    and rescueRow.target.buildingId==saved.finalShelter
                    and rescueRow.rejectedShelters[saved.firstShelter],
                    'production rescue target and rejected building survive the native disk restart')
            end
            finish(true,'new survivor, camp, companions and native disk reload passed');return
        end
        check(SC.BaseLife.create(player:getSquare(),'Handover New Camp')==true,'camp established')
        if rescue then
            local list=getWorld():getMetaGrid():getBuildings();local best,target
            for i=0,list:size()-1 do local b=list:get(i);local distance=(b:getX()-player:getX())^2+(b:getY()-player:getY())^2
                if distance>300^2 and distance<550^2 then local rooms=b:getRooms();local house=false
                    for j=0,rooms:size()-1 do local name=string.lower(rooms:get(j):getName());if name=='bedroom' or name=='livingroom' then house=true end end
                    if house and (not best or distance<best) then best,target=distance,b end
                end
            end
            check(target~=nil,'real distant residential shelter fixture')
            player:teleportTo(target:getX()-5,target:getY()+3,0);phase('relocate')
        else spawn() end
    elseif s.phase=='relocate' and age>12000 then
        -- This isolated route/radio fixture needs a quiet, reproducible house.
        -- The unmodified first run also exercised real combat preemption.
        local zombies=getCell():getZombieList()
        for i=zombies:size()-1,0,-1 do local actor=zombies:get(i)
            actor:removeFromWorld();actor:removeFromSquare()
            if zombies:contains(actor) then zombies:remove(actor) end
        end
        spawn()
    elseif s.phase=='spawn' then
        local actor,why=SC.Actor.pollSpawn(s.ticket)
        if not actor then assert(why=='spawn_pending' and age<15000,tostring(why));return end
        s.actor=actor;local saved=store();saved.id=SC.Registry.idOf(actor)
        local record=SC.Registry.byId(saved.id);record.state.personality.trust,record.state.personality.bond=73,41
        actor:getModData().SC_Trust,actor:getModData().SC_Bond=73,41
        SC.Commands.reset(actor);check(SC.Commands.persist(actor)==true,'fixture initializes the real command-owned relationship state')
        local item=assert(actor:getInventory():AddItem('Base.Bandage'));item:getModData().LF_HandoverCrewGear=true
        if rescue then radio(actor) end
        s.original:getBodyDamage():ReduceGeneralHealth(101);s.original:setHealth(0);phase('death')
    elseif s.phase=='death' then
        if not SC.Handover.current() then assert(age<10000,'production death hook');return end
        if age<3500 then return end
        s.clock=getGameTime():getWorldAgeHours();s.window=assert(SC.HandoverUI.open());phase('choose')
    elseif s.phase=='choose' and age>750 then click(s.window.newButton);phase('creator-cancel')
    elseif s.phase=='creator-cancel' and age>500 then
        check(CoopCharacterCreation.instance~=nil,'camp button opens stock character creator')
        CoopCharacterCreation.instance:cancel()
        check(SC.Handover.isChoosing() and not SC.Handover.pendingReceipt(),'cancel returns to selection without consuming anyone')
        s.window=assert(SC.HandoverUI.open());click(s.window.newButton);phase('creator')
    elseif s.phase=='creator' and age>500 then
        local creator=assert(CoopCharacterCreation.instance)
        check(creator.charCreationProfession:isVisible() and not creator.mapSpawnSelect:isVisible(),'camp flow skips unrelated region selection')
        creator.charCreationMain.forenameEntry:setText('Renewed');creator.charCreationMain.surnameEntry:setText('Survivor')
        creator:accept();phase('arrival')
    elseif s.phase=='arrival' then
        if getTimestampMs()>=(s.diagAt or 0) then
            s.diagAt=getTimestampMs()+1000
            local current=SC.Handover.current();local receipt=SC.Handover.pendingReceipt();local player=getSpecificPlayer(0)
            local p=SC.Handover.basePoint();local sq=player and player:getCurrentSquare()
            write('pzo-handover-arrival.txt','phase='..tostring(current and current.phase)..'\nreceipt='..tostring(receipt and receipt.x)..','..tostring(receipt and receipt.y)
                ..'\nplayer='..tostring(player and player:getX())..','..tostring(player and player:getY())
                ..'\nsquare='..tostring(sq and sq:getX())..','..tostring(sq and sq:getY())..'\ninside='..tostring(sq and SC.BaseLife.isInside(sq))
                ..'\nbasePoint='..tostring(p and p.x)..','..tostring(p and p.y)..',unloaded='..tostring(p and p.unloaded)..'\n')
        end
        if SC.Handover.current() then assert(age<45000,'camp arrival pending: '..tostring(SC.Handover.error()));return end
        local player=getSpecificPlayer(0);local saved=store()
        check(player~=s.original and player:getDescriptor():getForename()=='Renewed','creator supplied the new identity')
        check(SC.BaseLife.isInside(player),'new survivor arrives inside the marked camp')
        check(not player:isNpc() and player:isLocalPlayer(),'new survivor is normal local player')
        check(tagCount(player:getInventory())==0,'no companion gear granted to fresh survivor')
        check(player:getBodyDamage():getBodyPart(BodyPartType.Hand_L):getCutTime()==0,'new body has fresh medical state')
        check(not SC.Handover.retired(saved.id),'existing recruit remains a companion')
        check((s.pausedDelta or 0)<.0002,'creator and transfer keep world time paused')
        saved.token=player:getModData().LF_HandoverToken
        if rescue then phase('rescue') else phase('settle') end
    elseif s.phase=='rescue' then
        local row=ModData.getOrCreate(SC.Handover.KEY).crew[store().id]
        blockFirstShelter(row)
        local report=SC.HandoverRescue.lastReport or {};local attempt=SC.PickupRadio.lastAttempt or {};local receive=SC.PickupRadio.lastReception or {}
        write('pzo-handover-radio.txt','source='..tostring(report.source)..',target='..tostring(report.target)..',reason='..tostring(report.reason)
            ..'\nattempt='..tostring(attempt.called)..','..tostring(attempt.accepted)..','..tostring(attempt.received)
            ..'\nreceiver='..tostring(receive.guid)..','..tostring(receive.codes)..','..tostring(receive.exact)
            ..'\ndelivered='..tostring(report.delivered)..'\n')
        if row then
            if row.helpReported then store().radioHelp=true end
            if row.shelterReported then store().radioShelter=true end
            write('pzo-handover-rescue.txt','phase='..tostring(row.phase)..'\nhelp='..tostring(row.helpReported)..'\nshelter='..tostring(row.shelterReported)..'\nx='..s.actor:getX()..'\ny='..s.actor:getY()..'\ntarget='..tostring(row.target and row.target.x)..','..tostring(row.target and row.target.y)
                ..'\nfirstBuilding='..tostring(s.firstShelter)..'\ncurrentBuilding='..tostring(row.target and row.target.buildingId)
                ..'\nfailures='..tostring(row.shelterFailures)..'\nlastFailure='..tostring(row.lastShelterFailure)..'\n')
        end
        if seeking and not reload then
            if age<5000 then return end
            check(row and row.phase=='seeking_shelter' and row.target.buildingId==s.firstShelter,
                'checkpoint is taken while the original shelter route is still seeking')
            local saved=store()
            saved.seekingTarget={x=row.target.x,y=row.target.y,z=row.target.z,buildingId=row.target.buildingId}
            saved.seekingNodes,saved.seekingMs=row.target.pathNodes,row.shelterActiveMs
            check(saved.seekingNodes and saved.seekingMs and saved.seekingMs>0,'seeking checkpoint contains live route metadata and consumed budget')
            phase('settle');return
        end
        if not store().radioHelp or not store().radioShelter then assert(age<120000,'native shelter/radio did not finish');return end
        check(true,'actual native receiver heard help and indoor arrival')
        check(row and row.phase=='sheltered','crew physically reached indoor shelter')
        check((row.shelterFailures or 0)>0 and row.rejectedShelters[s.firstShelter],
            'real failed first shelter was rejected by production rescue')
        check(row.target.buildingId and row.target.buildingId~=s.firstShelter,
            'indoor arrival uses a different residential building')
        for _,door in ipairs(s.lockedDoors) do
            check(door:isLocked() and not door:IsOpen(),'failed house doors remain locked and shut')
        end
        check(SC.Commands.peek(s.actor).order=='follow','reselection preserves the original standing Follow order')
        store().rescueRetargeted,store().finalShelter=true,row.target.buildingId
        phase('settle')
    elseif s.phase=='settle' and age>3500 then
        if seeking and not reload then
            setGameSpeed(0)
            local row=ModData.getOrCreate(SC.Handover.KEY).crew[store().id]
            check(row and row.phase=='seeking_shelter','checkpoint still seeks shelter at the actual save boundary')
            store().seekingNodes,store().seekingMs=row.target.pathNodes,row.shelterActiveMs
        end
        local saved=store();local record=SC.Registry.byId(saved.id)
        if not rescue then
            check(record and record.actor==s.actor,'original companion body remains')
            check(SC.Commands.peek(s.actor).order=='follow','standing Follow order stays intact')
            check(tagCount(s.actor:getInventory())==1,'companion keeps its own gear once')
            check(getSpecificPlayer(1)==nil,'rescue view releases after local reunion')
        end
        check(SC.Persistence.save(getSpecificPlayer(0))==true,'world saved with surviving roster')
        local doc=assert(ModData.getOrCreate(SC.Identity.worldSaveKey).document.companions[saved.id])
        check(doc.recruited and doc.personality.trust>=73 and doc.personality.bond>=41,'camp bonds remain intact during normal companion simulation')
        saved.trust,saved.bond=doc.personality.trust,doc.personality.bond
        save(false);phase('save')
    elseif s.phase=='save' and age>3000 then finish(true,'production camp creator and surviving crew verified; native restart next') end
end
Events.OnRenderTick.Add(function()
    if s.done then return end
    if s.clock and SC.Handover.isPaused() then s.pausedDelta=math.max(s.pausedDelta or 0,math.abs(getGameTime():getWorldAgeHours()-s.clock)) end
    local okay,why=pcall(step);if not okay then finish(false,why) end
end)
