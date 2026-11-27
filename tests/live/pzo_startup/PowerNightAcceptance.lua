-- SPDX-License-Identifier: MIT
-- Controlled native receivers/clock in a disposable save, actual LF actors/UI.
local SC=LivingFellows
local s={phase='menu',checks=0,crew={},notes={}}
local function write(name,text) local w=assert(getFileWriter(name,true,false));w:write(text);w:close() end
local function read(name) local r=getFileReader(name,false);if not r then return end;local v=r:readLine();r:close();return v end
local mode=read('pzo-power-night-mode.txt') or 'checkpoint'
local function saved() return ModData.getOrCreate('LF_PowerNightAcceptance') end
local function check(ok,why) s.checks=s.checks+1;assert(ok,'Power Night '..s.checks..': '..tostring(why)) end
local function phase(name) s.phase,s.at=name,getTimestampMs();write('pzo-power-night-progress.txt',name..'\n');print('POWER_NIGHT phase='..name) end
local function finish(ok,why)
    if s.done then return end;s.done=true
    write('pzo-power-night-result.txt','result='..(ok and 'PASS' or 'FAIL')..'\nmode='..mode..'\nphase='..s.phase..'\nchecks='..s.checks..'\nreason='..tostring(why)..'\n'..table.concat(s.notes,'\n')..'\n')
end
local function shot(tag) getCore():TakeFullScreenshot('power-night-'..mode..'-'..tag..'.png') end
local function square(x,y,z) return getCell():getGridSquare(x,y,z or 0) end
local function quiet()
    local zombies=getCell():getZombieList()
    for i=zombies:size()-1,0,-1 do local z=zombies:get(i)
        if (z:getX()-s.player:getX())^2+(z:getY()-s.player:getY())^2<80^2 then z:removeFromWorld();z:removeFromSquare() end
    end
end
local function grid(on)
    local options=getSandboxOptions();options:set('ElecShutModifier',on and 100000 or -1);options:toLua()
    getWorld():setHydroPowerOn(on)
end
local function placeTV(q)
    local object=IsoTelevision.new(getCell(),q,getSprite('appliances_television_01_0'))
    q:AddSpecialObject(object);q:RecalcAllWithNeighbours(true)
    local data=assert(object:getDeviceData());data:setIsTelevision(true);data:setIsBatteryPowered(false)
    data:setMinChannelRange(200);data:setMaxChannelRange(1000);data:setPower(1)
    data:setDeviceVolume(.5);data:setIsTurnedOn(true)
    return object
end
local function placeRadio(q)
    local item=assert(s.player:getInventory():AddItem('Base.WalkieTalkie2'))
    local data=item:getDeviceData();data:setHasBattery(true);data:setPower(1);data:setIsTurnedOn(true);data:setDeviceVolume(.5)
    q:AddWorldInventoryItem(item,.5,.5,0,false);s.player:getInventory():Remove(item)
    local object=IsoRadio.new(getCell(),q,nil);object:setDeviceData(data);object:getModData().RadioItemID=item:getID()
    q:AddSpecialObject(object);q:RecalcAllWithNeighbours(true)
    return object
end
local function healthy(actor)
    local stats=actor:getStats();stats:set(CharacterStat.HUNGER,.05);stats:set(CharacterStat.THIRST,.05)
    stats:set(CharacterStat.FATIGUE,.05);stats:set(CharacterStat.ENDURANCE,1)
end
local function findFloor()
    for radius=4,55 do for dx=-radius,radius do for dy=-radius,radius do
        if math.max(math.abs(dx),math.abs(dy))==radius then
            local q=square(7108+dx,8318+dy)
            if q and q:getRoom() then
                local okay=true
                for x=-1,1 do for y=-1,1 do local n=square(q:getX()+x,q:getY()+y)
                    if not n or n:getRoom()~=q:getRoom() or not n:isFree(false)
                        or SC.Topology.squareHasStairs(n) or not n:TreatAsSolidFloor() then okay=false end
                end end
                if okay then return q end
            end
        end
    end end end
end
local function spawn()
    local n=#s.crew+1
    s.ticket=assert(SC.Actor.beginSpawn(assert(square(s.x+1,s.y-(n-1),0)),
        {recruited=true,identity={forename=n==1 and 'Mara' or 'Jon',surname='PowerNight',gender=n==1 and 'woman' or 'man',outfit='Generic01'}}))
    phase('spawn')
end
local function worldObjects()
    local list=getZomboidRadio():getDevices();local n=0
    for i=0,list:size()-1 do if list:get(i)==s.tv then n=n+1 end end
    check(n==1,'native TV is registered once with radio world')
end
local function targetProgramme()
    local state=ModData.getOrCreate(SC.PowerNight.KEY)
    local h=getGameTime():getWorldAgeHours();local tod=getGameTime():getTimeOfDay()
    state.night={day=math.floor((h-tod)/24+.00001),tv=SC.PowerNightCatalog.starters[1],radio=SC.PowerNightCatalog.starters[4]}
end
local function tickClock(minute)
    getGameTime():setTimeOfDay(20+minute/60)
    if s.tv then s.tv:getDeviceData():setIsTurnedOn(true) end
    if s.radio then s.radio:getDeviceData():setIsTurnedOn(true) end
    SC.PowerNight.pulse()
end
Events.OnInitGlobalModData.Add(function()
    if mode=='checkpoint' then ModData.getOrCreate(SC.Identity.worldSaveKey).document={schema=SC.Identity.saveSchema,companions={},factionActors={}} end
end)
Events.OnDeviceText.Add(function(guid,codes,x,y,z,text,object)
    if codes==SC.PowerNight.MARKER then
        if object==s.tv then s.tvLines=(s.tvLines or 0)+1 end
        if object==s.radio then s.radioLines=(s.radioLines or 0)+1 end
    end
end)
Events.OnMainMenuEnter.Add(function() MainScreen.continueLatestSave('Sandbox','PzoRestoreFixture') end)
local seen={}
Events.OnRenderTick.Add(function()
    local modal=MainScreen and MainScreen.instance and MainScreen.instance.checkSavefileModal
    if modal and modal.yes and not seen[modal] then seen[modal]=true;modal:onClick(modal.yes) end
end)
Events.OnGameStart.Add(function()
    s.player=assert(getSpecificPlayer(0));s.player:setGodMod(true);setGameSpeed(1)
    if mode=='checkpoint' then s.player:teleportTo(7108.5,8318.5,0) end
    s.began=getTimestampMs();phase('load')
    local original=SC.TVWatching.candidate
    SC.TVWatching.candidate=function(actor,state,now,hooks,desired)
        local row=original(actor,state,now,hooks,desired)
        if s.phase=='gather' and desired==nil then
            print('POWER_NIGHT candidate actor='..tostring(SC.Registry.idOf(actor))..';kind='..tostring(row and row.kind)
                ..';score='..tostring(row and row.score)..';archive='..tostring(row and row.powerNight)
                ..';object='..tostring(row and row.object==s.tv)..';receiver='..tostring(row and row.receiver==s.tv))
        end
        return row
    end
end)
local function step()
    if s.done or s.phase=='menu' then return end
    local now=getTimestampMs();assert(now-s.began<540000,'native mode exceeded deadline')
    if now>=(s.quietAt or 0) then quiet();s.quietAt=now+1000 end
    if s.phase=='load' then
        if now-s.at<12000 then return end
        check(SCBridge and PZOEngine and SC.Identity.release=='0.27.49','official PZO and production candidate')
        if mode~='checkpoint' then phase('restore');return end
        grid(true);getGameTime():setTimeOfDay(19.9)
        local q=findFloor()
        if not q then shot('floor-survey');error('indoor receiver fixture floor; player='..s.player:getX()..','..s.player:getY()..','..s.player:getZ()) end
        s.x,s.y=q:getX(),q:getY()
        s.player:teleportTo(s.x+.5,s.y+.5,0);healthy(s.player)
        SC.BaseLife.reset();SC.Logistics.reset();check(SC.BaseLife.create(q,'Native Power Night camp'),'native camp created')
        SC.BaseLife.active().settings.autoMaintenance=false;SC.BaseLife.active().settings.routines=true
        SC.BaseLife.active().settings.defense='role_based'
        s.pc=IsoObject.new(q,'appliances_com_01_72','Computer');q:AddTileObject(s.pc)
        local os=assert(SC.Terminal.computerState(s.player,s.pc));os.locked=false
        s.tv=placeTV(assert(square(s.x,s.y+1)))
        s.tapeTV=placeTV(assert(square(s.x-1,s.y+1)))
        s.radio=placeRadio(assert(square(s.x-1,s.y)))
        check(SC.Terminal.open(s.player,s.pc),'actual EMMA terminal opens')
        saved().x,saved().y=s.x,s.y;saved().crew={}
        phase('terminal')
    elseif s.phase=='terminal' then
        if now-s.at<10000 then return end
        local w=assert(SC.Terminal.window)
        if w.state~='idle' then assert(now-s.at<120000,'terminal greeting did not settle');return end
        check(SC.PowerNight.snapshot().discovered,'real unlocked EMMA access discovers archive')
        check(SC.TerminalServices.input(w,'power night'),'public terminal service opens archive status')
        local menu=SC.TerminalServices.menu(w);check(#menu>=2,'actual terminal Power Night menu renders')
        s.window=w
        phase('terminal-visible')
    elseif s.phase=='terminal-visible' then
        if s.window.state~='idle' then assert(now-s.at<120000,'archive status did not settle');return end
        if not s.visibleAt then s.window:setFocusMode('menu');s.visibleAt=now;return end
        if now-s.visibleAt<1000 then return end
        shot('terminal');s.window:close()
        local snap=SC.PowerNight.snapshot();check(#snap.library==6 and snap.tv and snap.radio,'native starter media and dedicated channels')
        s.tv:getDeviceData():setChannel(snap.tv);s.tapeTV:getDeviceData():setChannel(203);s.radio:getDeviceData():setChannel(snap.radio)
        local original=getZomboidRadio():getRecordedMedia():getMediaData(SC.PowerNightCatalog.starters[2])
        local tape=assert(s.player:getInventory():AddItem('Base.VHS_Retail'));tape:setRecordedMediaData(original)
        s.tapeTV:getDeviceData():setMediaType(1);s.tapeTV:getDeviceData():addMediaItem(tape);s.player:getInventory():Remove(tape)
        s.tapeTV:getDeviceData():StartPlayMedia();check(s.tapeTV:getDeviceData():isPlayingMedia(),'another TV really plays its physical tape')
        local source=getZomboidRadio():getRecordedMedia():getMediaData('dedd4e83-6e3b-4f4f-9c9b-72a5ed08969d')
        local found=assert(s.player:getInventory():AddItem('Base.VHS_Retail'));found:setRecordedMediaData(source)
        local id=SC.GameplayUtil.itemStableId(found,true)
        check(SC.PowerNight.copy(s.player,s.pc,found),'real carried VHS copied into archive')
        check(SC.GameplayUtil.itemStableId(found,false)==id and SC.ControlUtil.owns(s.player,found),'same physical recording remains carried')
        check(not SC.PowerNight.copy(s.player,s.pc,found),'native duplicate recording rejected')
        saved().tape=id
        s.pc:getSquare():RemoveTileObject(s.pc)
        square(s.x,s.y):RecalcAllWithNeighbours(true)
        -- This case proves shared standing viewpoints. Chair approaches have
        -- separate native coverage; remove only seating from this clone room.
        local room=s.tv:getSquare():getRoom()
        for dx=-12,12 do for dy=-12,12 do local q=square(s.x+dx,s.y+dy)
            if q and q:getRoom()==room then for i=q:getObjects():size()-1,0,-1 do local object=q:getObjects():get(i)
                if SeatingManager.getInstance():getTilePositionCount(object)>0 then q:RemoveTileObject(object) end
            end;q:RecalcAllWithNeighbours(true) end
        end end
        check(SC.PowerNight.snapshot().discovered,'county archive remains discovered after local computer is removed')
        worldObjects();spawn()
    elseif s.phase=='spawn' then
        local actor,why=SC.Actor.pollSpawn(s.ticket)
        if not actor then assert(why=='spawn_pending' and now-s.at<15000,tostring(why));return end
        local id=assert(SC.Registry.idOf(actor));local record=assert(SC.Registry.byId(id));s.crew[#s.crew+1]=record;saved().crew[#s.crew]=id
        actor:teleportTo(s.x+1.5,s.y-(#s.crew-1)+.5,0)
        check(SC.BaseLife.assign(id,'generalist',true),'native camp resident assigned')
        check(SC.Commands.issue(id,'base_duty',{},s.player),'normal camp order accepted for available camp viewer')
        check(SC.Commands.issue(id,'set_scavenge',{enabled=false},s.player),'player disables optional scavenging for the evening')
        local bag=assert(actor:getInventory():AddItem('Base.Bag_BigHikingBag'));actor:setClothingItem_Back(bag)
        actor:getInventory():AddItem('Base.WaterBottle');actor:getInventory():AddItem('Base.CannedCornOpen')
        healthy(actor)
        if #s.crew<2 then spawn();return end
        targetProgramme();tickClock(0);s.lastClock=now;s.minute=0
        local rows={'tvArchive='..tostring(SC.PowerNight.isArchive(s.tv))..';on='..tostring(s.tv:getDeviceData():getIsTurnedOn())
            ..';playing='..tostring(s.tv:getDeviceData():isPlayingMedia())..';noTransmit='..tostring(s.tv:getDeviceData():isNoTransmit())
            ..';receipts='..tostring(s.tvLines)..'/'..tostring(s.radioLines)}
        for _,r in ipairs(s.crew) do local candidate=SC.PowerNight.candidate(r.actor,{kind='tv_watch',object=s.tv,score=24})
            rows[#rows+1]=r.id..';square='..r.actor:getSquare():getX()..','..r.actor:getSquare():getY()
                ..';archiveCandidate='..tostring(candidate and candidate.powerNight)..';roomMatch='..tostring(r.actor:getSquare():getRoom()==s.tv:getSquare():getRoom())
        end
        write('pzo-power-night-initial.txt',table.concat(rows,'\n'))
        s.player:faceThisObject(s.tv)
        saved().playerXP=s.player:getXp():getXP(Perks.Cooking)
        phase('gather')
    elseif s.phase=='gather' then
        -- Hold the introduction while actual actors settle. Only the show
        -- stage advances measured game minutes and earns attendance/lessons.
        getGameTime():setTimeOfDay(20)
        local ready=0
        for _,r in ipairs(s.crew) do
            local active=SC.Downtime.peek(r.actor);active=active and active.active
            if active and active.kind=='tv_watch' and active.startedAt then ready=ready+1
            else local decision=SC.Decision.peek(r.actor);r.pnReason=decision and decision.intent or 'warming_up' end
        end
        if now>=(s.traceAt or 0) then
            s.traceAt=now+1000
            local rows={'grid='..tostring(SC.PowerNight.gridOn())..';active='..tostring(SC.PowerNight.active()),
                'tv='..tostring(SC.TVWatching.isOn(s.tv))..';channel='..s.tv:getDeviceData():getChannel()..';power='..s.tv:getDeviceData():getPower()
                    ..';room='..tostring(s.tv:getSquare():getRoom())..';canPower='..tostring(s.tv:getDeviceData():canBePoweredHere())}
            for _,r in ipairs(s.crew) do local a=SC.Downtime.peek(r.actor);a=a and a.active
                local canWatch,watchReason=SC.Downtime.canPerform(r.actor,'tv_watch')
                rows[#rows+1]=r.id..'@'..r.actor:getX()..','..r.actor:getY()..';room='..tostring(r.actor:getSquare():getRoom())
                    ..';base='..tostring(SC.BaseLife.isInside(r.actor))..';join='..tostring(SC.PowerNight.mayJoin(r.actor))
                    ..';kind='..tostring(a and a.kind)..';started='..tostring(a and a.startedAt)..';reason='..tostring(r.pnReason)
                    ..';score='..tostring(a and a.score)..';for='..tostring(a and a.fact and a.fact.seatingFor)..';night='..tostring(a and a.powerNight)
                    ..';canWatch='..tostring(canWatch)..'/'..tostring(watchReason)..';canSee='..tostring(SC.GameplayUtil.canSee(r.actor,s.tv:getSquare()))
                    ..';squareSee='..tostring(SC.GameplayUtil.canSee(r.actor:getSquare(),s.tv:getSquare()))
                    ..';rawLos='..tostring(LosUtil.lineClear(getCell(),math.floor(r.actor:getX()),math.floor(r.actor:getY()),0,s.x,s.y+1,0,false))
                    ..';frontLos='..tostring(LosUtil.lineClear(getCell(),math.floor(r.actor:getX()),math.floor(r.actor:getY()),0,s.x,s.y,0,false))
                    ..';tvFacing='..tostring(s.tv:isFacing(r.actor))
            end
            write('pzo-power-night-state.txt',table.concat(rows,'\n'))
        end
        if ready<2 then if now-s.at>=45000 then shot('gather-failed');error('two native companions did not reach TV') end;return end
        check(ready==2,'two native companions share the TV through normal downtime')
        saved().viewOwner=SC.ViewSession.owner();saved().xp={}
        for _,r in ipairs(s.crew) do saved().xp[r.id]=r.actor:getXp():getXP(Perks.Cooking) end
        s.minute=2;s.lastClock=now;phase('show')
    elseif s.phase=='show' and now-s.lastClock>=750 then
        s.minute=s.minute+1;s.lastClock=now
        if s.minute==13 then
            local r=s.crew[2];SC.Downtime.cancel(r.actor,'native guard control');SC.Commands.issue(r.id,'guard',{},s.player)
            saved().guardXP=r.actor:getXp():getXP(Perks.Cooking)
        end
        tickClock(s.minute)
        if s.minute==10 then shot('companions') end
        if s.minute>=42 then
            local one=s.crew[1]
            s.notes={'programme='..tostring(SC.PowerNight.snapshot().night and SC.PowerNight.snapshot().night.tv),
                'topic='..tostring(SC.PowerNight.topic(one.actor) and SC.PowerNight.topic(one.actor).title),
                'xpBefore='..tostring(saved().xp[one.id])..';xpAfter='..one.actor:getXp():getXP(Perks.Cooking)
                    ..';level='..one.actor:getPerkLevel(Perks.Cooking)..';cutoff='..tostring(SandboxVars.LevelForMediaXPCutoff)}
            check((s.tvLines or 0)>1 and (s.radioLines or 0)>1,'actual native TV and radio reception acknowledged')
            check(SC.PowerNight.topic(one.actor)~=nil,'native attended programme creates later Talk topic')
            check(SC.PowerNight.topic(s.crew[2].actor)==nil,'guard leaving early earns no attendance reward')
            check(s.crew[2].actor:getXp():getXP(Perks.Cooking)==saved().guardXP,'guard gains no later broadcast XP')
            check(one.actor:getXp():getXP(Perks.Cooking)>saved().xp[one.id],'native companion learned original cooking lesson')
            check(SC.PowerNight.talk(one.actor):find('Cook',1,true)~=nil,'native later conversation names actual programme')
            check(SC.ViewSession.owner()==saved().viewOwner,'gathering acquires no companion viewport')
            grid(false);check(not SC.PowerNight.active(),'native blackout stops county transmitter')
            SC.PowerNight.pulse();grid(true);tickClock(50);check(SC.PowerNight.active(),'native restored supply rejoins slot')
            saved().lesson={}
            local row=SC.PowerNightCatalog.resolve(SC.PowerNightCatalog.starters[1])
            for i=1,row.count do local line=SC.PowerNightCatalog.line(row,i)
                if line.codes~='' and one.actor:isKnownMediaLine(line.guid) then saved().lesson[#saved().lesson+1]=line.guid end
            end
            check(#saved().lesson>0,'native original lesson GUID recorded')
            saved().learned=one.id;saved().learnedXP=one.actor:getXp():getXP(Perks.Cooking)
            saved().archiveCount=#SC.PowerNight.snapshot().library
            setGameSpeed(0);check(SC.Persistence.save(s.player),'native companions persisted');save(false);phase('saved')
        end
    elseif s.phase=='restore' then
        if mode=='stored-reload' then
            check(s.player:getModData().LF_HandoverCompanionId==saved().learned,'same attendee is primary after Handover and disk reload')
            check(#SC.PowerNight.snapshot().library==saved().archiveCount,'world archive survives takeover restart')
            for _,guid in ipairs(saved().lesson) do check(s.player:isKnownMediaLine(guid),'taken-over survivor retains native learning') end
            finish(true,'Power Night archive and survivor learning survive actual Handover and final disk restart');return
        end
        local record=SC.Registry.byId(saved().learned)
        if not record then assert(now-s.at<45000,'native attendee restore pending');return end
        check(#SC.PowerNight.snapshot().library==saved().archiveCount,'archive survives native disk restart')
        check(record.actor:getXp():getXP(Perks.Cooking)==saved().learnedXP,'native learned XP survives disk restart')
        SC.PowerNight.restoreKnowledge(record.actor)
        for _,guid in ipairs(saved().lesson) do check(record.actor:isKnownMediaLine(guid),'original lesson knowledge survives native restore') end
        s.player:setGodMod(false);s.player:getBodyDamage():ReduceGeneralHealth(101);s.player:setHealth(0);phase('death')
    elseif s.phase=='death' then
        if not SC.Handover.isChoosing() then assert(now-s.at<20000,'production Handover chooser pending');return end
        if now-s.at<3500 then return end
        local w=assert(SC.HandoverUI.open())
        for index,item in ipairs(w.list.items) do if item.item.id==saved().learned then w.list.selected=index end end
        check(w.takeButton.enable~=false,'actual Handover take-over button enabled')
        w.takeButton.onclick(w.takeButton.target,w.takeButton);phase('takeover')
    elseif s.phase=='takeover' then
        if SC.Handover.current() then assert(now-s.at<45000,tostring(SC.Handover.error()));return end
        s.player=assert(getSpecificPlayer(0))
        check(s.player:getModData().LF_HandoverCompanionId==saved().learned,'actual companion takeover succeeds')
        for _,guid in ipairs(saved().lesson) do check(s.player:isKnownMediaLine(guid),'native Handover preserves learned lesson GUID') end
        setGameSpeed(0);save(false);phase('saved')
    elseif s.phase=='saved' and now-s.at>3500 then
        finish(true,mode=='checkpoint' and 'native broadcast, gathering, guard interruption, learning and mood checkpoint saved' or 'native Handover checkpoint saved')
    end
end
Events.OnRenderTick.Add(function() if s.done then return end;local okay,why=pcall(step);if not okay then finish(false,why) end end)
