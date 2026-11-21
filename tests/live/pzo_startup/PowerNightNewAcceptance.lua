-- SPDX-License-Identifier: MIT
-- Continue the owned Power Night fixture through the stock new-survivor creator.
local SC=SurvivorCompanion
local s={phase='menu',checks=0}
local function write(name,text) local w=assert(getFileWriter(name,true,false));w:write(text);w:close() end
local function read(name) local r=getFileReader(name,false);if not r then return end;local v=r:readLine();r:close();return v end
local mode=read('pzo-power-night-mode.txt') or 'new-character'
local function saved() return ModData.getOrCreate('LF_PowerNightAcceptance') end
local function check(ok,why) s.checks=s.checks+1;assert(ok,'Power Night fresh survivor '..s.checks..': '..tostring(why)) end
local function phase(name) s.phase,s.at=name,getTimestampMs();write('pzo-power-night-progress.txt',name..'\n') end
local function finish(ok,why)
    if s.done then return end;s.done=true
    write('pzo-power-night-result.txt','result='..(ok and 'PASS' or 'FAIL')..'\nmode='..mode..'\nphase='..s.phase..'\nchecks='..s.checks..'\nreason='..tostring(why)..'\n')
end
local function quiet()
    local player=getSpecificPlayer(0);if not player then return end
    local zombies=getCell():getZombieList()
    for i=zombies:size()-1,0,-1 do local z=zombies:get(i)
        if (z:getX()-player:getX())^2+(z:getY()-player:getY())^2<80^2 then z:removeFromWorld();z:removeFromSquare() end
    end
end
Events.OnMainMenuEnter.Add(function() MainScreen.continueLatestSave('Sandbox','PzoRestoreFixture') end)
local seen={}
Events.OnRenderTick.Add(function()
    local modal=MainScreen and MainScreen.instance and MainScreen.instance.checkSavefileModal
    if modal and modal.yes and not seen[modal] then seen[modal]=true;modal:onClick(modal.yes) end
end)
Events.OnGameStart.Add(function() s.player=assert(getSpecificPlayer(0));setGameSpeed(1);s.began=getTimestampMs();phase('load') end)
local function step()
    if s.done or s.phase=='menu' then return end
    local now=getTimestampMs();assert(now-s.began<240000,'fresh-survivor native deadline')
    if now>=(s.quietAt or 0) then quiet();s.quietAt=now+1000 end
    if s.phase=='load' then
        if now-s.at<12000 then return end
        check(SCBridge and PZOEngine and SC.Identity.release=='0.27.49','official PZO production candidate')
        check(#SC.PowerNight.snapshot().library==saved().archiveCount,'world archive retained')
        if mode=='new-reload' then
            check(s.player:getDescriptor():getForename()=='ArchiveFresh','fresh survivor persisted through disk restart')
            check(s.player:getModData().LF_HandoverCompanionId==nil,'fresh identity never inherits retired companion ID')
            check(s.player:isKnownMediaLine(saved().freshGuid),'fresh survivor retains their own newly learned source line')
            check(SC.PowerNight.knowsLesson(s.player,saved().freshGuid),'durable archive learning follows fresh identity')
            check(not SC.PowerNight.topic(s.player),'fresh survivor inherits no old attendee conversation')
            finish(true,'new character, personal learning and world archive persist through native restart');return
        end
        check(s.player:getModData().LF_HandoverCompanionId==saved().learned,'previous native attendee is current primary')
        s.player:setGodMod(false);s.player:getBodyDamage():ReduceGeneralHealth(101);s.player:setHealth(0);phase('death')
    elseif s.phase=='death' then
        if not SC.Handover.isChoosing() then assert(now-s.at<20000,'new-survivor chooser pending');return end
        if now-s.at<3500 then return end
        local w=assert(SC.HandoverUI.open());check(w.newButton.enable~=false,'actual camp-spawn button enabled')
        w.newButton.onclick(w.newButton.target,w.newButton);phase('creator')
    elseif s.phase=='creator' then
        if now-s.at<500 then return end
        local creator=assert(CoopCharacterCreation.instance)
        creator.charCreationMain.forenameEntry:setText('ArchiveFresh');creator.charCreationMain.surnameEntry:setText('Viewer')
        creator:accept();phase('arrival')
    elseif s.phase=='arrival' then
        if SC.Handover.current() then assert(now-s.at<45000,tostring(SC.Handover.error()));return end
        s.player=assert(getSpecificPlayer(0));s.player:setGodMod(true)
        check(s.player:getDescriptor():getForename()=='ArchiveFresh','actual creator supplies fresh identity')
        check(SC.BaseLife.isInside(s.player),'fresh survivor really spawns in preserved camp')
        check(s.player:getModData().LF_HandoverCompanionId==nil,'fresh survivor has independent identity')
        SC.PowerNight.restoreKnowledge(s.player)
        for _,guid in ipairs(saved().lesson) do check(not s.player:isKnownMediaLine(guid),'old companion learning is not inherited') end
        check(not SC.PowerNight.topic(s.player),'old conversation topic is not inherited')
        local q=assert(getCell():getGridSquare(saved().x,saved().y+1,0))
        for i=0,q:getObjects():size()-1 do local object=q:getObjects():get(i)
            if instanceof(object,'IsoTelevision') then s.tv=object break end
        end
        check(s.tv~=nil,'same native receiver survived world saves')
        s.player:teleportTo(saved().x+.5,saved().y+.5,0);s.player:faceThisObject(s.tv)
        local options=getSandboxOptions();options:set('ElecShutModifier',100000);options:toLua();getWorld():setHydroPowerOn(true)
        local row=SC.PowerNightCatalog.resolve(SC.PowerNightCatalog.starters[1])
        for i=1,row.count do local line=SC.PowerNightCatalog.line(row,i)
            if line.codes:find('COO+',1,true) then s.index,s.line,s.row=i,line,row;break end
        end
        check(s.line~=nil,'native archive has a cooking lesson')
        getGameTime():setTimeOfDay(20)
        local h=getGameTime():getWorldAgeHours();local tod=getGameTime():getTimeOfDay()
        local world=ModData.getOrCreate(SC.PowerNight.KEY)
        world.night={day=math.floor((h-tod)/24+.00001),tv=s.row.id,radio=SC.PowerNightCatalog.starters[4]}
        s.tv:getDeviceData():setChannel(SC.PowerNight.snapshot().tv);s.tv:getDeviceData():setIsTurnedOn(true)
        s.before=s.player:getXp():getXP(Perks.Cooking);phase('watch')
    elseif s.phase=='watch' then
        -- Let the stock player's FOV/forward vector settle before the lesson
        -- is aired. Select a real clear side of this exact screen; do not
        -- override the receiver's native facing/visibility eligibility.
        getGameTime():setTimeOfDay(20)
        s.player:faceThisObject(s.tv)
        if now-s.at<1500 then return end
        if not s.tv:isFacing(s.player) or not SC.GameplayUtil.canSee(s.player,s.tv:getSquare()) then
            if not s.positions then
                s.positions={}
                for radius=1,3 do for dx=-radius,radius do for dy=-radius,radius do
                    if math.max(math.abs(dx),math.abs(dy))==radius then s.positions[#s.positions+1]={dx,dy} end
                end end end
            end
            local positions=s.positions
            s.position=(s.position or 0)+1
            assert(s.position<=#positions,'no native visible screen side in the receiver room')
            local p=positions[s.position];local q=getCell():getGridSquare(saved().x+p[1],saved().y+1+p[2],0)
            if q and q:getRoom()==s.tv:getSquare():getRoom() and q:isFree(false) then
                s.player:teleportTo(q:getX()+.5,q:getY()+.5,0);s.player:faceThisObject(s.tv)
            end
            s.at=now;return
        end
        check(s.tv:isFacing(s.player),'fresh survivor is physically facing the native screen')
        getGameTime():setTimeOfDay(20+(2+(s.index-.5)/s.row.count*56)/60)
        SC.PowerNight.reset()
        SC.PowerNight.pulse()
        check(s.player:isKnownMediaLine(s.line.guid),'fresh survivor learns original source GUID through actual receiver')
        check(s.player:getXp():getXP(Perks.Cooking)>s.before,'fresh survivor can learn an episode already learned by predecessor')
        local xp=s.player:getXp():getXP(Perks.Cooking)
        SC.PowerNight.reset();SC.PowerNight.pulse()
        check(s.player:getXp():getXP(Perks.Cooking)==xp,'same fresh survivor cannot farm repeated native reception')
        saved().freshGuid=s.line.guid
        setGameSpeed(0);save(false);phase('saved')
    elseif s.phase=='saved' and now-s.at>3500 then finish(true,'actual new-survivor Handover and independent archive learning saved') end
end
Events.OnRenderTick.Add(function() if s.done then return end;local okay,why=pcall(step);if not okay then finish(false,why) end end)
