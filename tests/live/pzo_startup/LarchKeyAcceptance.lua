-- SPDX-License-Identifier: MIT
-- Production LARCH/KEY native acceptance in a disposable world. No gameplay APIs
-- are mocked. Native UI callbacks, real inventory items and real disk reloads.
require 'ISUI/ISContextMenu'
local SC,s=SurvivorCompanion,{phase='menu',checks=0,notes={'probe_revision=larch-key-production-native-stable-compact-r5'}}
local function write(name,value) local w=assert(getFileWriter(name,true,false));w:write(value);w:close() end
local function read(name) local r=getFileReader(name,false);if not r then return end;local v=r:readLine();r:close();return v end
local mode=read('pzo-larch-key-mode.txt') or 'acceptance'
local function check(v,why) s.checks=s.checks+1;assert(v,'LARCH/KEY '..s.checks..': '..why) end
local function note(v) s.notes[#s.notes+1]=v;print('SC_LARCH_ACCEPT '..v) end
local function phase(v) s.phase,s.at=v,getTimestampMs();write('pzo-larch-key-progress.txt',v..'\n') end
local function card() return SC.TerminalLockCard end
local function finish(ok,why)
    if s.done then return end;s.done=true
    if s.multiplier then getGameTime():setMultiplier(s.multiplier) end
    if s.originalSound then SC.Terminal.playFeedbackSound=s.originalSound end
    local q=ISTimedActionQueue.getTimedActionQueue(s.primary)
    local unchanged=q.current==s.queueCurrent and #q.queue==s.queueSize
    if not unchanged then ok,why=false,'primary timed-action queue changed' end
    write('pzo-larch-key-result.txt','result='..(ok and 'PASS' or 'FAIL')..'\nmode='..mode..'\nphase='..s.phase..'\nchecks='..s.checks
        ..'\nreason='..tostring(why)..'\nprimary_queue_untouched='..tostring(unchanged)..'\n'..table.concat(s.notes,'\n')..'\n')
end
local function send(w,text) w:setEntryText(text);w:submit();w:flush() end
local function context(item)
    local menu=ISContextMenu.get(0,250,250)
    triggerEvent('OnFillInventoryObjectContextMenu',0,menu,{item})
    local found
    for _,option in ipairs(menu.options or {}) do if option.name=='Swipe at the computer' then found=option end end
    menu:setVisible(false);return found
end
local function invoke(option)
    check(option and type(option.onSelect)=='function','real native context option has callback')
    option.onSelect(option.target,option.param1,option.param2,option.param3,option.param4,option.param5,option.param6,
        option.param7,option.param8,option.param9,option.param10)
end
local function custom(seed,service)
    local item=assert(instanceItem(card().ITEM));item:setName(service and 'LARCH/KEY Service Card' or 'Foreign Access Card');item:setCustomName(true)
    item:getModData().LF_LarchKey={seed=seed,service=service==true};s.primary:getInventory():AddItem(item);return item
end
local function locateItem(state)
    local origin=s.pc:getSquare();local wanted=tostring(state.lock.card.itemId)
    for dx=-6,6 do for dy=-6,6 do
        local square=getCell():getGridSquare(origin:getX()+dx,origin:getY()+dy,origin:getZ())
        if square then
            local objects=square:getObjects()
            for i=0,objects:size()-1 do local object=objects:get(i);local c=object:getContainer()
                if c then local items=c:getItems();for j=0,items:size()-1 do local item=items:get(j)
                    if item:getFullType()==card().ITEM and tostring(item:getID())==wanted then return item,c,nil end
                end end
            end
            local world=square:getWorldObjects()
            for i=0,world:size()-1 do local object=world:get(i);local item=object:getItem()
                if item and item:getFullType()==card().ITEM and tostring(item:getID())==wanted then return item,nil,object end
            end
        end
    end end
end
local function take(item,c,world)
    if c then c:Remove(item) end
    if world then world:removeFromWorld();world:removeFromSquare();item:setWorldItem(nil) end
    s.primary:getInventory():AddItem(item);check(SC.ControlUtil.owns(s.primary,item),'exact placed native card is now carried')
end
local function open(seed,saved)
    if SC.Terminal.window then SC.Terminal.window:close() end
    SC.TerminalDrawers.release(s.pc)
    local state=saved or SC.TerminalSystem.create(seed,'police',false,false,'larch-native:'..seed)
    if not saved then state.archive='dispatch_bell';state.lock={kind='card',settled=true,realItems=true,attempts={}};state.locked=true end
    local data=s.pc:getModData();data.movableData=data.movableData or {};data.movableData.LF_LarchOS=state
    check(SC.Terminal.open(s.primary,s.pc),'production native terminal opens')
    s.w=SC.Terminal.window;s.w:flush();check(s.w.system.lock.kind=='card','native normalization retains card kind')
    return s.w.system
end
local function knownCount(state)
    local n=0;for i=1,7 do if card().known(state,i) then n=n+1 end end;return n
end
local function answer(w)
    local pos=card().cursor(w);check(pos~=nil,'an open card gap is selected')
    return card().board(w.system).digits:sub(pos,pos),pos
end
local function wrong(w)
    local first=card().cursor(w)
    for offset=0,6 do local pos=(first-1+offset)%7+1
        if not card().known(w.system,pos) then
            local correct=card().board(w.system).digits:sub(pos,pos)
            for _,digit in ipairs(card().candidates(w.system,pos,SC.Terminal.electricalSkill(w.player))) do
                if digit~=correct and not (w.system.lock.card.tried[pos] or ''):find(digit,1,true) then
                    if pos~=first then send(w,'gap '..pos) end
                    return digit,pos
                end
            end
        end
    end
    error('native fixture exhausted untried candidates')
end
local function clickValue(w,value)
    for _,hit in ipairs(w.securityHits or {}) do
        if tostring(hit.value)==tostring(value) then
            w:onMouseDown(hit.x+hit.width/2,hit.y+(hit.height or w.rowHeight)/2);w:flush();return true
        end
    end
    return false
end
local function solveTyped(w)
    local guard=0
    while w.system.locked do guard=guard+1;check(guard<=7,'native digit solve is bounded');send(w,answer(w)) end
    check(card().complete(w.system),'actual typed card solve knows every digit')
end
local function nearbySetup()
    local square,pc
    for z=0,3 do local candidate=getCell():getGridSquare(12652,1984,z);local objects=candidate and candidate:getObjects()
        for i=0,(objects and objects:size() or 0)-1 do if SC.Terminal.isComputer(objects:get(i)) then pc,square=objects:get(i),candidate;break end end
        if pc then break end
    end
    check(pc~=nil,'same real map computer used by native preflight is loaded')
    note('native_map_computer='..square:getX()..','..square:getY()..','..square:getZ())
    s.pc=pc;local stand
    for _,d in ipairs({{1,0},{0,1},{-1,0},{0,-1},{1,1},{-1,-1}}) do
        local q=getCell():getGridSquare(square:getX()+d[1],square:getY()+d[2],square:getZ())
        if q and SC.GameplayUtil.isSquareFree(q) then stand=q;break end
    end
    check(stand~=nil,'actual terminal has a free adjacent standing tile')
    s.stand=stand;s.primary:teleportTo(stand:getX()+.5,stand:getY()+.5,stand:getZ())
    note('native_setup=pc:'..square:getX()..','..square:getY()..','..square:getZ()..'; stand:'..stand:getX()..','..stand:getY()..','..stand:getZ()
        ..'; present:'..tostring(SC.Terminal.present(pc))..'; near:'..tostring(SC.Terminal.near(s.primary,pc))
        ..'; realItems:'..tostring(SC.TerminalDrawers.enabled())..'; renderer:'..getCore():getScreenWidth()..'x'..getCore():getScreenHeight())
    check(SC.Terminal.present(pc) and SC.Terminal.near(s.primary,pc) and SC.TerminalDrawers.enabled(),'actual exact-floor placement/access setup is ready')
    if not SC.Terminal.powered(pc) then
        local inv=s.primary:getInventory();inv:AddItem('Base.Screwdriver')
        for _=1,3 do inv:AddItem('Base.ElectricWire') end
        for _=1,6 do inv:AddItem('Base.ElectronicsScrap') end
        local battery=assert(inv:AddItem('Base.CarBattery1'));SC.ControlUtil.setCharge(battery,.95)
        local ok,why=SC.TerminalHardware.install(s.primary,pc,'ups',battery);check(ok,'native UPS installation: '..tostring(why))
    end
    check(SC.Terminal.powered(pc),'actual terminal powered for production authorization checks')
end
local function physicalFallback()
    local original=SC.TerminalLockWheel.carried(s.primary)
    if original then original:getContainer():Remove(original);s.primary:getSquare():AddWorldInventoryItem(original,.5,.5,0) end
    local state=SC.TerminalSystem.create(651,'police',false,false,'larch-native:wheel-fallback');state.lock={kind='wheel'};state.locked=true
    SC.TerminalLockWheel.ensure(state,s.primary,s.pc)
    local placed
    local origin=s.pc:getSquare()
    for dx=-1,1 do for dy=-1,1 do local square=getCell():getGridSquare(origin:getX()+dx,origin:getY()+dy,origin:getZ())
        if square then local objects=square:getWorldObjects();for i=0,objects:size()-1 do local item=objects:get(i):getItem()
            if item and tostring(item:getID())==state.lock.manualItemId and item:getFullType()==SC.TerminalLockWheel.ITEM then placed=objects:get(i) end
        end end
    end end
    check(placed~=nil,'existing Wheel.ensure places real native manual through extracted shared helper')
    local item=instanceItem(card().ITEM);item:setName('Native Physical Helper Card');item:setCustomName(true)
    local world=SC.TerminalLockPhysical.place(item,s.pc)
    check(world and world:getSquare()==placed:getSquare() and item:getWorldStaticModel()=='Base.IDcard',
        'production shared helper places native card at same real-computer surface/floor location as manual')
    if original then local old=original:getWorldItem();old:removeFromWorld();old:removeFromSquare();original:setWorldItem(nil);s.primary:getInventory():AddItem(original) end
    note('native_shared_physical_card_and_wheel_helper=PASS; computer=map_native')
end
local function begin()
    s.primary:getXp():setXPToLevel(Perks.Electricity,0);s.primary:getXp():setPerkBoost(Perks.Electricity,0)
    s.primary:setPerkLevelDebug(Perks.Electricity,0)
    local state
    for seed=303,322 do state=open(seed);if not state.lock.card.absent then break end end
    check(state.lock.card.spawned and not state.lock.card.absent,'actual production placement makes one available owner card')
    local item,c,world=locateItem(state);check(item~=nil,'native production spawn receipt resolves exact item')
    check(item:getModData().LF_LarchKey.seed==state.seed,'physical owner card seed matches actual normalized computer')
    check(not c or not SC.TerminalDrawers.locked(c),'production placement excludes all native drawer interlocks')
    local claimed=state.lock.drawer and SC.TerminalDrawers.container(state.lock.drawer)
    check(claimed and SC.TerminalDrawers.locked(claimed) and c~=claimed,'computer claims native desk before card placement')
    local itemId=tostring(item:getID());s.owner,s.ownerContainer,s.ownerWorld=item,c,world;s.ownerId=itemId
    take(item,c,world)
    s.w:close();check(not context(item),'production inventory swipe row absent when terminal is closed')
    check(getText('IGUI_ItemCat_Quest')=='Quest','native English Quest inventory category translation resolves')
    local page=getPlayerInventory(0);page:setVisible(true);page.isCollapsed=false;page.collapseCounter=0;page:setPinned()
    page:setMaxDrawHeight(290);page:setX(150);page:setY(400);page:setWidth(550);page:setHeight(290);page:refreshBackpacks();page:bringToTop()
    getPlayerLoot(0):setVisible(false);phase('inventory-picture')
end
local function afterInventory()
    local item=s.owner;local itemId=s.ownerId
    getPlayerInventory(0):setVisible(false)
    check(SC.Terminal.open(s.primary,s.pc),'reopen production terminal');s.w=SC.Terminal.window;s.w:flush();local state=s.w.system
    check(state.lock.card.itemId==itemId,'reopening does not create a second owner card')
    local ownerOption=context(item)
    if not ownerOption then
        local active=SC.Terminal.cardWindowFor(s.primary)
        local hooked=SC.UIBridge.transferHookState()
        note('inventory_event_missing=true; card_window_same='..tostring(SC.Terminal.cardWindow==s.w)..'; active_window_same='..tostring(active==s.w)
            ..'; window_state='..tostring(s.w.state)..'; access='..tostring(s.w:hasCurrentAccess())..'; owned='..tostring(SC.ControlUtil.owns(s.primary,item))
            ..'; transfer_hook_active='..tostring(hooked))
        local menu=ISContextMenu.get(0,250,250);SC.UIBridge.fillInventoryContextMenu(0,menu,{item});local direct
        for _,option in ipairs(menu.options or {}) do if option.name=='Swipe at the computer' then direct=option end end
        menu:setVisible(false);note('inventory_direct_production_handler_builds_row='..tostring(direct~=nil))
        if direct then
            invoke(direct);check(state.lock.card.read=='owner' and state.lock.card.gapsShown==2,'direct native production owner callback reads exact card')
            note('native_direct_owner_swipe=PASS; registered_inventory_event=FAIL')
        end
        error('production registered inventory event omitted swipe row; direct-handler diagnostic recorded')
    end
    check(ownerOption~=nil,'production inventory swipe option appears for carried card at actual lock page')
    local foreign=custom(state.seed+999,false);local before=state.lock.card.mismatches
    invoke(context(foreign));check(state.lock.card.read=='none' and state.lock.card.mismatches==before,'inventory-clicked foreign card is rejected without cost')
    invoke(context(item));check(state.lock.card.read=='owner' and state.lock.card.gapsShown==2,'actual inventory callback swipes exact owner card to two gaps')
    note('native_owner_context_swipe=PASS; placed_item='..itemId..'; default_geometry='..s.w:columns()..'columns,'..s.w:visibleRows()..'rows')
    s.foreign=foreign;s.started=getTimestampMs();s.themes={'green','sand','aqua','purple'};s.theme=1;s.originalTheme=s.w.system.theme
    s.w.system.theme=s.themes[1];s.w.colors=SC.TerminalPresentation.colors(s.themes[1])
    getCore():TakeFullScreenshot('larch-key-native-default-1280.png');phase('default-shot')
end
local function ownerInput()
    local w=s.w;local digit,pos=answer(w)
    check(clickValue(w,digit),'actual rendered candidate mouse hit selects a digit')
    check(card().known(w.system,pos),'mouse candidate commits correct native position')
    solveTyped(w)
    note('scripted_owner_UI_solve_seconds='..((getTimestampMs()-s.started)/1000)..'; human_first_time_and_learned_timing=PLAYTEST')
    check(SC.TerminalLocks.ledger().beaten.card==true,'card self-unlock records new recovery-log kind')
    check(not context(s.owner),'inventory swipe row disappears on unlocked terminal')
    phase('encode-menu')
end
local function encode()
    local w=s.w
    if w.payoff then send(w,'');return end
    local index
    for i,option in ipairs(w:menuOptions()) do if option.label=='Encode service card' then index=i end end
    check(index~=nil and card().canEncode(w),'unlocked native menu offers service encoding')
    w.focusMode='menu';w:submit(index);w:flush()
    check(w.system.lock.card.encoded and s.owner:getModData().LF_LarchKey.service==true and s.owner:getName()=='LARCH/KEY Service Card',
        'actual unlocked menu callback commits encoded receipt and mutates exact carried native card')
    check(not card().canEncode(w),'service encoding cannot repeat')
    s.serviceId=tostring(s.owner:getID());note('native_owner_typing_encode_menu=PASS');physicalFallback()
    s.w:close();s.worldVisualKey=tostring(getTimestampMs());phase('world-visual')
end
local function afterWorldVisual()
    local state=open(401)
    send(s.w,'swipe card')
    check(state.lock.card.read=='service' and state.lock.card.gapsShown==1,'service card encoded on first computer works on another actual card lock')
    phase('service-picture')
end
local function failure()
    solveTyped(s.w)
    -- Store the exact service card in an ordinary bag while the next lock tests
    -- no-card recovery. Its actual native bag contents must survive disk reload.
    local inv=s.primary:getInventory();local bag=assert(inv:AddItem('Base.Bag_Schoolbag'))
    inv:Remove(s.owner);bag:getInventory():AddItem(s.owner)
    -- Native recursive inventory intentionally still sees it; put the bag into
    -- a nearby ordinary container for the no-card trial, then retrieve later.
    inv:Remove(bag);s.hold=assert(s.ownerContainer or SC.TerminalDrawers.container(s.w.system.lock.drawer));s.hold:AddItem(bag);s.bag=bag
    inv:Remove(s.foreign);s.hold:AddItem(s.foreign)
    s.primary:getXp():setXPToLevel(Perks.Electricity,0);s.primary:setPerkLevelDebug(Perks.Electricity,0)
    local parserState=open(411);local digits={}
    for pos=1,7 do if not card().known(parserState,pos) and #digits<2 then digits[#digits+1]=card().board(parserState).digits:sub(pos,pos) end end
    local beforeKnown=knownCount(parserState);send(s.w,table.concat(digits,' - '))
    check(knownCount(parserState)==beforeKnown+2,'actual native card parser accepts two digits with spaces and dash')
    solveTyped(s.w)
    s.primary:getXp():setXPToLevel(Perks.Electricity,0);s.primary:setPerkLevelDebug(Perks.Electricity,0)
    local state=open(409);s.failureState=state
    check(state.lock.card.read=='none' and state.lock.card.gapsShown==4,'unread log-only native page begins with four gaps at Electrical0')
    local vanilla=assert(inv:AddItem('Base.IDcard_Blank'));local before=state.lock.card.mismatches
    send(s.w,'swipe');check(state.lock.card.read=='none' and state.lock.card.mismatches==before,'vanilla ID stripe is rejected without mismatch')
    local digit,pos=answer(s.w);send(s.w,digit);local retained=state.lock.card.solved
    for _=1,2 do send(s.w,wrong(s.w)) end
    check(state.lock.card.hinted and state.lock.card.hintPos and knownCount(state)>4,'second wrong candidate triggers one real saved reader-log hint')
    local hintPos=state.lock.card.hintPos
    while not state.lock.card.lockedUntil do send(s.w,wrong(s.w)) end
    check(state.lock.bypass and state.lock.card.mismatches==5 and math.abs(state.lock.card.lockedUntil-SC.ControlUtil.hours()-1)<.01,
        'native last mismatch starts one-hour lockout with other ways in')
    check(state.lock.card.hintPos==hintPos and state.lock.card.solved~=retained,'hint is not repeated while later mismatches accumulate')
    local store=ModData.getOrCreate('LF_LarchKeyAcceptance')
    store.identity=state.identity;store.seed=state.seed;store.solved=state.lock.card.solved;store.hintPos=hintPos
    store.untilHours=state.lock.card.lockedUntil;store.serviceId=s.serviceId;store.serviceName=s.owner:getName()
    local q=s.hold;q:Remove(s.bag);inv:AddItem(s.bag)
    check(card().carried(s.primary,state)~=nil,'encoded service card remains discoverable recursively in native bag')
    note('native_production_owner_service_context_mouse_typing_encode_lockout_hint=PASS')
    phase('failure-picture')
end
local function helperStart()
    solveTyped(s.w)
    local origin=s.primary:getSquare();local square
    for radius=1,4 do if not square then for dx=-radius,radius do for dy=-radius,radius do
        local q=getCell():getGridSquare(origin:getX()+dx,origin:getY()+dy,origin:getZ())
        if q and SC.GameplayUtil.isClearActorSpawnSquare(q) and q:isFree(false) then square=q;break end
    end if square then break end end end end
    check(square~=nil,'constructor-safe native higher-skilled companion standing tile')
    s.ticket=assert(SC.Actor.beginSpawn(square,{recruited=true,identity={forename='Larch',surname='NativeHint',gender='woman',outfit='Generic01'}}))
    phase('helper-spawn')
end
local function reload()
    local saved=SC.Terminal.peekState(s.pc);local store=ModData.getOrCreate('LF_LarchKeyAcceptance')
    check(saved and saved.identity==store.identity and saved.lock.card,'actual native disk world retained final card state')
    local state=open(nil,saved);local c=state.lock.card
    check(c.solved==store.solved and c.hinted and c.hintPos==store.hintPos and c.lockedUntil==store.untilHours and c.mismatches==5,
        'native disk reload preserves solved digits, hint, mismatch count and exact lockout clock')
    local service=card().carried(s.primary,state)
    check(service and tostring(service:getID())==store.serviceId and service:getModData().LF_LarchKey.service==true
        and service:getName()==store.serviceName,'same exact encoded native service card survives inside bag across disk reload')
    send(s.w,'swipe')
    check(c.read=='service' and c.gapsShown==1,'service swipe remains legal and durable during native lockout')
    s.retainedSolved=c.solved;s.multiplier=getGameTime():getTrueMultiplier();getGameTime():setMultiplier(100)
    phase('lockout-expiry')
end
Events.OnInitGlobalModData.Add(function()
    if mode=='acceptance' then
        ModData.getOrCreate(SC.Identity.worldSaveKey).document={schema=SC.Identity.saveSchema,companions={},factionActors={}}
        ModData.getOrCreate('LF_LockLedger').drawers={}
        SandboxVars.LivingFellows=SandboxVars.LivingFellows or {};SandboxVars.LivingFellows.LockRealItems=true;SandboxVars.LivingFellows.ClassicLocksOnly=false
    end
end)
Events.OnMainMenuEnter.Add(function() MainScreen.continueLatestSave('Sandbox','PzoRestoreFixture') end)
local seen={}
Events.OnRenderTick.Add(function() local m=MainScreen and MainScreen.instance and MainScreen.instance.checkSavefileModal;if m and m.yes and not seen[m] then seen[m]=true;m:onClick(m.yes) end end)
Events.OnGameStart.Add(function()
    SC.Scheduler.unregister('decision');s.primary=assert(getSpecificPlayer(0));s.primary:setGodMod(true)
    local q=ISTimedActionQueue.getTimedActionQueue(s.primary);s.queueCurrent,s.queueSize=q.current,#q.queue
    if SC.UI then SC.UI.close() end
    local info=getPlayerInfoPanel(0);if info then info:setVisible(false) end
    s.originalSound=SC.Terminal.playFeedbackSound;s.sounds={}
    SC.Terminal.playFeedbackSound=function(name,...)
        local result=s.originalSound(name,...)
        if name=='LFCardSwipe' or name=='LFCardRead' then s.sounds[#s.sounds+1]={name=name,result=result} end
        return result
    end
    phase('load')
end)
Events.OnTick.Add(function()
    if s.done or s.phase=='menu' then return end
    local ok,why=pcall(function()
        if s.phase=='load' and getTimestampMs()-s.at>12000 then
            check(SCBridge and PZOEngine and card(),'actual official PZO and production card implementation loaded')
            s.primary:teleportTo(12653.5,1984.5,0);phase('site-load')
        elseif s.phase=='site-load' and getTimestampMs()-s.at>8000 then
            nearbySetup();phase('site-ready')
        elseif s.phase=='site-ready' and getTimestampMs()-s.at>2000 then
            if mode=='acceptance-reload' then reload() else begin() end
        elseif s.phase=='inventory-picture' and getTimestampMs()-s.at>1800 then
            getCore():TakeFullScreenshot('larch-key-native-inventory-quest.png');phase('inventory-shot')
        elseif s.phase=='inventory-shot' and getTimestampMs()-s.at>1000 then afterInventory()
        elseif s.phase=='default-shot' and getTimestampMs()-s.at>1000 then
            getCore():setResolutionAndFullScreen(1920,1080,false);phase('wide-ready')
        elseif s.phase=='wide-ready' and getTimestampMs()-s.at>2500 then
            s.w:refreshLayout();note('native_wide_geometry='..s.w:columns()..'columns,'..s.w:visibleRows()..'rows');phase('owner-picture')
        elseif s.phase=='owner-picture' and getTimestampMs()-s.at>1800 then
            check(s.w.lockArtDrawn and s.w.lockArtDrawn.LarchKeyTitle,'new small card/reader illustration draws through native CRT path')
            getCore():TakeFullScreenshot('larch-key-native-owner-'..s.themes[s.theme]..'.png')
            phase('owner-shot')
        elseif s.phase=='owner-shot' and getTimestampMs()-s.at>1000 then
            s.theme=s.theme+1
            if s.theme<=#s.themes then
                s.w.system.theme=s.themes[s.theme];s.w.colors=SC.TerminalPresentation.colors(s.themes[s.theme]);s.w.lockArtDrawn.LarchKeyTitle=nil;phase('owner-picture')
            else
                local swipe,blip=false,false
                for _,played in ipairs(s.sounds) do
                    check(played.result==true,'native sound-enabled UI event plays: '..played.name)
                    if played.name=='LFCardSwipe' then swipe=true elseif played.name=='LFCardRead' then blip=true end
                end
                check(swipe and blip and GameSounds.isKnownSound('LFCardSwipe') and GameSounds.isKnownSound('LFCardRead'),
                    'actual production swipes play original swipe and delayed good-read blip events')
                ownerInput()
            end
        elseif s.phase=='compact-picture' and getTimestampMs()-s.at>2500 then
            s.w:refreshLayout()
            check(not SC.TerminalLockCardUI.large(s.w),'actual compact native display uses text fallback')
            s.w.lockArtDrawn.LarchKeyTitle=nil;phase('compact-clean')
        elseif s.phase=='compact-clean' and getTimestampMs()-s.at>1200 then
            check(not s.w.lockArtDrawn.LarchKeyTitle,'optional small illustration drops on actual compact display')
            getCore():TakeFullScreenshot('larch-key-native-compact-workbench.png')
            phase('compact-shot')
        elseif s.phase=='compact-shot' and getTimestampMs()-s.at>1000 then
            getCore():setResolutionAndFullScreen(s.originalWidth,s.originalHeight,false);phase('restore-layout')
        elseif s.phase=='restore-layout' and getTimestampMs()-s.at>2500 then
            s.w:refreshLayout();s.w.system.theme=s.originalTheme;s.w.colors=SC.TerminalPresentation.colors(s.originalTheme);helperStart()
        elseif s.phase=='encode-menu' and getTimestampMs()-s.at>1000 then encode()
        elseif s.phase=='world-visual' then
            if not s.worldShot and getTimestampMs()-s.at>3500 then
                getCore():TakeFullScreenshot('larch-key-native-world-placement.png')
                write('pzo-larch-key-visual-ready.txt',s.worldVisualKey..'\n');s.worldShot=true
            end
            if read('pzo-larch-key-visual-continue.txt')==s.worldVisualKey or getTimestampMs()-s.at>45000 then
                note('world_visual_checkpoint_acknowledged='..tostring(read('pzo-larch-key-visual-continue.txt')==s.worldVisualKey));afterWorldVisual()
            end
        elseif s.phase=='service-picture' and getTimestampMs()-s.at>1800 then
            getCore():TakeFullScreenshot('larch-key-native-service-workbench.png');phase('service-shot')
        elseif s.phase=='service-shot' and getTimestampMs()-s.at>1000 then
            s.originalWidth,s.originalHeight=getCore():getScreenWidth(),getCore():getScreenHeight()
            getCore():setResolutionAndFullScreen(800,600,false);phase('compact-picture')
        elseif s.phase=='helper-spawn' then
            local actor,reason=SC.Actor.pollSpawn(s.ticket)
            if not actor then check(reason=='spawn_pending' and getTimestampMs()-s.at<15000,'native hint companion spawn: '..tostring(reason));return end
            s.helper=actor;actor:setPerkLevelDebug(Perks.Electricity,6)
            -- Seed 418's existing first-open reaction draw is >25, so no
            -- unrelated greeting consumes the real speech cooldown before Ask.
            local state=open(418);local digit,pos=answer(s.w);local before=knownCount(state)
            local hintValue
            for _,option in ipairs(SC.TerminalLockUI.footer(s.w)) do if option.label:find('Ask ',1,true)==1 then hintValue=option.value end end
            check(hintValue~=nil,'actual native card footer offers the nearby companion')
            send(s.w,hintValue)
            check(state.lock.crewHint and state.lock.crewClue and state.lock.crewClue.kind=='card'
                and state.lock.crewClue.value==digit and state.lock.crewClue.stage==pos and card().known(state,pos) and knownCount(state)==before+1,
                'actual higher-skilled native companion speaks and commits the selected stripe digit')
            check(SC.Dialogue.lastSpokenTopic(actor)=='terminal.lock.hint.card','native companion delivers registered card-specific dialogue')
            SC.Actor.remove(actor);s.helper=nil;failure()
        elseif s.phase=='failure-picture' and getTimestampMs()-s.at>1800 then
            getCore():TakeFullScreenshot('larch-key-native-locked-reader.png');phase('failure-shot')
        elseif s.phase=='failure-shot' and getTimestampMs()-s.at>1000 then
            s.w:close();save(false)
            finish(true,'native production controls passed and saved; disk reload required')
        elseif s.phase=='lockout-expiry' then
            check(getTimestampMs()-s.at<60000,'native game-hour lockout expiry remains bounded')
            card().update(s.w)
            if SC.ControlUtil.hours()>=ModData.getOrCreate('LF_LarchKeyAcceptance').untilHours then
                check(s.w.system.lock.card.lockedUntil==nil and s.w.system.lock.card.mismatches==0 and s.w.system.lock.card.solved==s.retainedSolved,
                    'actual native game-hour expiry resets only mismatches and preserves solved positions')
                getGameTime():setMultiplier(s.multiplier);solveTyped(s.w)
                note('real_native_save_reload_service_and_lockout_expiry=PASS; human_timing=PLAYTEST')
                finish(true,'production native acceptance and genuine disk reload passed')
            end
        end
    end)
    if not ok then finish(false,why) end
end)
