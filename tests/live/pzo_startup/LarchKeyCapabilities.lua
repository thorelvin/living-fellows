-- SPDX-License-Identifier: MIT
-- Test-only Phase 0. Uses native objects in a disposable clone, then a real disk reload.
require 'ISUI/ISContextMenu'
local SC,s=SurvivorCompanion,{phase='menu',checks=0,notes={'probe_revision=phase0-primitives-first-native-art-diagnostic-r6'}}
local ITEM='LFLarchProbe.LarchKeyCard'
local function write(name,value) local w=assert(getFileWriter(name,true,false));w:write(value);w:close() end
local function read(name) local r=getFileReader(name,false);if not r then return end;local x=r:readLine();r:close();return x end
local mode=read('pzo-larch-key-mode.txt') or 'create'
local function check(value,why) s.checks=s.checks+1;assert(value,'LarchKey '..s.checks..': '..why) end
local function note(value) s.notes[#s.notes+1]=value;print('SC_LARCH_PHASE0 '..value) end
local function phase(value) s.phase,s.at=value,getTimestampMs();write('pzo-larch-key-progress.txt',value..'\n') end
local function finish(ok,why)
    if s.done then return end;s.done=true
    local q=s.primary and ISTimedActionQueue.getTimedActionQueue(s.primary)
    local untouched=q and q.current==s.queueCurrent and #q.queue==s.queueSize
    if not untouched then ok,why=false,'primary queue changed' end
    local out='result='..(ok and 'PASS' or 'FAIL')..'\nmode='..mode..'\nphase='..s.phase..'\nchecks='..s.checks
        ..'\nreason='..tostring(why)..'\nprimary_queue_untouched='..tostring(untouched)..'\n'..table.concat(s.notes,'\n')..'\n'
    write('pzo-larch-key-result.txt',out);print('SC_LARCH_KEY '..out)
end
local function where(c)
    local p=c:getParent();local q=p:getSquare()
    return {x=q:getX(),y=q:getY(),z=q:getZ(),type=c:getType(),sprite=p:getSprite():getName()}
end
local function nativeCards(container,result)
    result=result or {}
    local items=container:getItems()
    for i=0,items:size()-1 do local item=items:get(i)
        if item:getFullType()==ITEM then result[#result+1]=item end
        if instanceof(item,'InventoryContainer') then nativeCards(item:getInventory(),result) end
    end
    return result
end
local function transfer(item,from,to)
    from:Remove(item);to:AddItem(item)
    check(item:getContainer()==to and not from:contains(item) and to:contains(item),'same exact native card transferred')
end
local function card(container,tag,name,custom)
    local item=assert(instanceItem(ITEM))
    item:setName(name)
    if custom then item:setCustomName(true) end
    item:getModData().LF_LarchKey={seed=41931,service=false,probe=tag}
    check(item:getName()==name,'native setName visible immediately')
    container:AddItem(item)
    check(container:contains(item) and item:getContainer()==container and item:getModData().LF_LarchKey.probe==tag and item:getName()==name,
        'native AddItem(existing prepared card) preserves exact instance, name and modData')
    return item
end
local function locate()
    local origin=s.primary:getSquare();local cell=getCell();local computers,drawers={},{}
    for dx=-70,70 do for dy=-70,70 do for z=0,1 do
        local square=cell:getGridSquare(origin:getX()+dx,origin:getY()+dy,z)
        if square then local objects=square:getObjects()
            for i=0,objects:size()-1 do local object=objects:get(i)
                if SC.Terminal.isComputer(object) then computers[#computers+1]=object end
                local c=object:getContainer();local allowed={desk=true,sidetable=true,filingcabinet=true,dresser=true,counter=true}
                if c and allowed[c:getType()] then drawers[#drawers+1]=c end
            end
        end
    end end end
    note('loaded_computers='..#computers..'; loaded_furniture='..#drawers..'; primary='..origin:getX()..','..origin:getY())
    note('drawer_enabled='..tostring(SC.TerminalDrawers.enabled()))
    local explored=0;for _,c in ipairs(drawers) do if c:isExplored() then explored=explored+1 end end
    note('natural_furniture_explored='..explored..'; unexplored='..(#drawers-explored))
    for _,pc in ipairs(computers) do local sq=pc:getSquare();local room=sq:getRoom()
        if room and SC.TerminalDrawers.find(pc) then
            for _,c in ipairs(drawers) do local cs=c:getParent():getSquare()
                if cs:getRoom()==room and cs:getZ()==sq:getZ() and math.abs(cs:getX()-sq:getX())<=6 and math.abs(cs:getY()-sq:getY())<=6
                    and not c:isExplored() and c:getType()~='counter' then
                    -- Claim the real computer's native desk first, using the existing interlock.
                    local state=assert(SC.Terminal.computerState(s.primary,pc));state.locked=true
                    state.lock={kind='word',drawerChecked=false}
                    if SC.TerminalPayoff.wantsNote(state) then
                        for archive,row in pairs(SC.TerminalLockStashes) do if row.drawer then state.archive=archive;break end end
                    end
                    SC.TerminalDrawers.claim(s.primary,pc,state)
                    local claimed=state.lock.drawer and SC.TerminalDrawers.container(state.lock.drawer)
                    if claimed and SC.TerminalDrawers.locked(claimed) then
                        for _,other in ipairs(drawers) do local osq=other:getParent():getSquare()
                            if other~=claimed and not other:isExplored() and osq:getRoom()==room and osq:getZ()==sq:getZ()
                                and math.abs(osq:getX()-sq:getX())<=6 and math.abs(osq:getY()-sq:getY())<=6
                                and not SC.TerminalDrawers.locked(other) then return pc,state,claimed,other end
                        end
                    end
                end
            end
        end
    end
    -- If the retained save has already explored the site's drawers, construct
    -- fresh native furniture using an actual desk's vanilla sprite. Existing
    -- map furniture and its loot are never reset or relabelled.
    for _,pc in ipairs(computers) do local psq=pc:getSquare();local room=psq:getRoom()
        local state=assert(SC.Terminal.computerState(s.primary,pc));state.locked=true
        state.lock={kind='word',realItems=true,drawerChecked=false}
        if SC.TerminalPayoff.wantsNote(state) then for archive,row in pairs(SC.TerminalLockStashes) do if row.drawer then state.archive=archive;break end end end
        SC.TerminalDrawers.claim(s.primary,pc,state)
        local claimed=state.lock.drawer and SC.TerminalDrawers.container(state.lock.drawer)
        note('interlock_probe='..psq:getX()..','..psq:getY()..'; claimed='..tostring(claimed~=nil)..'; checked='..tostring(state.lock.drawerChecked)..'; wantsNote='..tostring(SC.TerminalPayoff.wantsNote(state)))
        if room and claimed and SC.TerminalDrawers.locked(claimed) then
            local sprite=claimed:getParent():getSprite():getName()
            for dx=-6,6 do for dy=-6,6 do local q=getCell():getGridSquare(psq:getX()+dx,psq:getY()+dy,psq:getZ())
                if q and q:getRoom()==room and q:isFree(false) then
                    local object=IsoObject.new(q,sprite);q:AddTileObject(object)
                    local fresh=ItemContainer.new('desk',q,object);object:setContainer(fresh)
                    note('native_ItemContainer_constructor='..tostring(fresh~=nil)..'; initial_explored='..tostring(fresh and fresh:isExplored()))
                    check(fresh~=nil and not fresh:isExplored(),'fresh constructed vanilla desk has real native unexplored container')
                    note('placement_fixture_furniture=constructed_native; sprite='..sprite..'; map_computer=true; map_claimed_drawer=true')
                    return pc,state,claimed,fresh
                end
            end end
        end
    end
end
local function relocate()
    local list=getWorld():getMetaGrid():getBuildings();local best,chosen
    for index=0,list:size()-1 do local def=list:get(index);local rooms=def:getRooms();local office,police=false,false
        for i=0,rooms:size()-1 do local name=string.lower(tostring(rooms:get(i):getName()))
            if name:find('police',1,true) or name:find('office',1,true) then office=true end
            if name:find('police',1,true) then police=true end
        end
        local distance=(def:getX()-12700)^2+(def:getY()-2000)^2
        if office and (def:getX2()-def:getX())*(def:getY2()-def:getY())<4000 and (not best or distance<best) then best,chosen=distance,def end
    end
    check(chosen~=nil,'real police/office metadata available for furniture capability fixture')
    s.primary:teleportTo(chosen:getX()+3,chosen:getY()+3,0)
    note('native_fixture_building='..chosen:getX()..','..chosen:getY())
    phase('relocate')
end
local function prototypePlacement(pc,claimed,drawer)
    -- Same constraints as the planned card sweep. This is a capability prototype,
    -- not the future production placement implementation.
    check(drawer~=claimed and SC.TerminalDrawers.locked(claimed) and not SC.TerminalDrawers.locked(drawer),'placement follows native drawer claim and excludes interlock')
    local before=drawer:getItems():size();check(not drawer:isExplored(),'real untouched drawer starts unexplored')
    ItemPicker.fillContainer(drawer,s.primary);drawer:setExplored(true)
    local loot=drawer:getItems():size();check(loot>before,'native ItemPicker adds ordinary drawer loot before card')
    local item=card(drawer,'drawer','Access Card (H. Morrow)',true)
    check(drawer:contains(item) and drawer:getItems():size()==loot+1,'card coexists with normal native drawer loot')
    note('drawer='..drawer:getType()..'; ordinary_loot='..loot..'; claimed_desk_excluded=true; coordinates='..drawer:getParent():getSquare():getX()..','..drawer:getParent():getSquare():getY())
    return item,loot
end
local function fallback(pc)
    local tile=pc:getSquare();local surface=0;local objects=tile:getObjects()
    for i=0,objects:size()-1 do local object=objects:get(i);if object~=pc then surface=math.max(surface,tonumber(object:getSurfaceOffsetNoTable()) or 0) end end
    if surface<=0 then tile=nil;local sq=pc:getSquare()
        for _,d in ipairs({{0,1},{1,0},{0,-1},{-1,0},{1,1},{-1,1},{1,-1},{-1,-1}}) do
            local q=getCell():getGridSquare(sq:getX()+d[1],sq:getY()+d[2],sq:getZ())
            if q and q:TreatAsSolidFloor() and SC.GameplayUtil.isSquareFree(q) then tile=q;break end
        end
    end
    check(tile~=nil,'manual-equivalent native fallback has a place')
    local item=instanceItem(ITEM);item:setName('LARCH/KEY Surface Probe');item:setCustomName(true)
    item:getModData().LF_LarchKey={seed=41931,service=false,probe='floor'}
    tile:AddWorldInventoryItem(item,.5,.5,surface/96)
    local world=item:getWorldItem();check(world and world:getSquare()==tile,'IDcard native world model placed by manual fallback')
    local vanilla=instanceItem('Base.IDcard_Blank')
    note('fallback_surface='..surface..'; card_model='..tostring(item:getWorldStaticModel())..'; vanilla_model='..tostring(vanilla:getWorldStaticModel())
        ..'; card_texture='..tostring(item:getTex())..'; vanilla_texture='..tostring(vanilla:getTex()))
    s.floorCard,s.vanillaCard=item,vanilla
    return item
end
local function contextProbe(item)
    local context=ISContextMenu.get(0,300,220)
    local native=SC.UIBridge.fillInventoryContextMenu
    local function prototype(index,menu,entries)
        native(index,menu,entries)
        if s.mockOpen and entries[1]==item then menu:addOption('Swipe at the computer',item,function(value) s.contextRead=value end) end
    end
    -- Calls the real registered event path with the existing bridge replaced
    -- temporarily by its native capability prototype, then restores it.
    Events.OnFillInventoryObjectContextMenu.Remove(native);Events.OnFillInventoryObjectContextMenu.Add(prototype)
    local function event() triggerEvent('OnFillInventoryObjectContextMenu',0,context,{item}) end
    s.mockOpen=false;event();local before=#context.options
    s.mockOpen=true;event();local option=context.options[#context.options]
    check(#context.options==before+1 and option.name=='Swipe at the computer','native inventory event can add gated card context row through bridge path')
    option.onSelect(option.target)
    check(s.contextRead==item,'native inventory context callback receives exact card')
    Events.OnFillInventoryObjectContextMenu.Remove(prototype);Events.OnFillInventoryObjectContextMenu.Add(native)
    context:setVisible(false)
    note('inventory_hook_feasibility=PASS; prototype_only=true; production_visibility_swipe_and_timing=DEFERRED')
end
local function create()
    local inventory=s.primary:getInventory()
    local simple=card(inventory,'name-only','Name Only (H. Morrow)',false)
    local custom=card(inventory,'custom','Custom Name (H. Morrow)',true)
    local bag=assert(inventory:AddItem('Base.Bag_Schoolbag'));bag:setName('LARCH/KEY Probe Bag');bag:setCustomName(true)
    local bag2=assert(inventory:AddItem('Base.Bag_Schoolbag'));bag2:setName('LARCH/KEY Second Bag');bag2:setCustomName(true)
    transfer(custom,inventory,bag:getInventory());transfer(custom,bag:getInventory(),bag2:getInventory())
    check(custom:getModData().LF_LarchKey.seed==41931 and custom:getModData().LF_LarchKey.service==false,'modData survives bag-to-bag transfer')
    transfer(custom,bag2:getInventory(),inventory)
    inventory:Remove(custom);s.primary:getSquare():AddWorldInventoryItem(custom,.5,.5,0)
    local world=assert(custom:getWorldItem());check(custom:getModData().LF_LarchKey.probe=='custom','modData survives native floor drop')
    world:removeFromWorld();world:removeFromSquare();custom:setWorldItem(nil);inventory:AddItem(custom)
    check(inventory:contains(custom) and custom:getModData().LF_LarchKey.seed==41931,'exact native floor pickup retains modData')
    transfer(custom,inventory,bag:getInventory())
    note('prepared_card_AddItem_bag_floor_primitives=PASS')
    local pc,state,claimed,drawer=locate();check(pc and drawer,'real loaded computer has an interlocked desk and separate unexplored drawer in same room')
    s.pc,s.drawer=pc,drawer
    local drawerCard,loot=prototypePlacement(pc,claimed,drawer)
    local floorCard=fallback(pc)
    contextProbe(simple)
    local store=ModData.getOrCreate('LF_LarchKeyNativeProbe')
    store.drawer=where(drawer);store.claimed=where(claimed);store.floor={x=floorCard:getWorldItem():getSquare():getX(),y=floorCard:getWorldItem():getSquare():getY(),z=floorCard:getWorldItem():getSquare():getZ()}
    store.ordinaryLoot=loot;store.cardId=tostring(drawerCard:getID());store.nameOnly= simple:isCustomName()
    note('setName_only_custom_flag='..tostring(simple:isCustomName())..'; explicit_custom_flag='..tostring(custom:isCustomName()))
    s.primary:setX(drawer:getParent():getSquare():getX()+.5);s.primary:setY(drawer:getParent():getSquare():getY()+.5)
    s.primary:setZ(drawer:getParent():getSquare():getZ())
    local playerPage=getPlayerInventory(0);playerPage:setVisible(true);playerPage:refreshBackpacks()
    local lootPage=getPlayerLoot(0);lootPage:setNewContainer(drawer);lootPage:setVisible(true)
    phase('screenshot')
end
local function reload()
    local inventory=s.primary:getInventory();local cards=nativeCards(inventory);local found={}
    for _,item in ipairs(cards) do local data=item:getModData().LF_LarchKey;check(data and data.seed==41931 and data.service==false,'inventory modData survived actual disk reload');found[data.probe]=item end
    check(found['name-only'] and found.custom,'both native names persisted as exact items after disk reload')
    note('name_only_reloaded='..found['name-only']:getName()..'; custom_reloaded='..found.custom:getName())
    check(found.custom:getName()=='Custom Name (H. Morrow)','explicit custom name survives native disk reload in bag')
    local customRequired=found['name-only']:getName()~='Name Only (H. Morrow)'
    note('custom_name_required='..tostring(customRequired))
    local store=ModData.getOrCreate('LF_LarchKeyNativeProbe');local drawer=assert(SC.TerminalDrawers.container(store.drawer))
    local drawerCards=nativeCards(drawer);check(#drawerCards==1 and tostring(drawerCards[1]:getID())==store.cardId,'one exact card survives in real drawer across native disk reload')
    check(drawer:isExplored() and drawer:getItems():size()==store.ordinaryLoot+1,'normal generated drawer loot and explored state survive disk reload')
    local data=drawerCards[1]:getModData().LF_LarchKey;check(data.seed==41931 and data.probe=='drawer','drawer card modData survives disk reload')
    local floor=getCell():getGridSquare(store.floor.x,store.floor.y,store.floor.z);local count=0
    local objects=floor:getWorldObjects();for i=0,objects:size()-1 do local item=objects:get(i):getItem();if item and item:getFullType()==ITEM and item:getModData().LF_LarchKey.probe=='floor' then count=count+1 end end
    check(count==1,'native IDcard world fallback survives real disk reload')
    note('real_disk_save_reload=PASS; bag_floor_modData=PASS; drawer_normal_loot=PASS; fallback_model=PASS')
    finish(true,'native Phase 0 primitives verified; production inventory option and timing deferred until build')
end
Events.OnInitGlobalModData.Add(function() if mode=='create' then
    ModData.getOrCreate(SC.Identity.worldSaveKey).document={schema=SC.Identity.saveSchema,companions={},factionActors={}}
    SandboxVars.LivingFellows=SandboxVars.LivingFellows or {};SandboxVars.LivingFellows.LockRealItems=true
    local ledger=ModData.getOrCreate('LF_LockLedger');ledger.drawers={}
end end)
Events.OnMainMenuEnter.Add(function() MainScreen.continueLatestSave('Sandbox','PzoRestoreFixture') end)
local seen={}
Events.OnRenderTick.Add(function() local modal=MainScreen and MainScreen.instance and MainScreen.instance.checkSavefileModal;if modal and modal.yes and not seen[modal] then seen[modal]=true;modal:onClick(modal.yes) end end)
Events.OnGameStart.Add(function()
    SC.Scheduler.unregister('decision');s.primary=assert(getSpecificPlayer(0));local q=ISTimedActionQueue.getTimedActionQueue(s.primary)
    s.primary:setGodMod(true)
    s.queueCurrent,s.queueSize=q.current,#q.queue;phase('load')
end)
Events.OnTick.Add(function()
    if s.done or s.phase=='menu' then return end
    local ok,why=pcall(function()
        if s.phase=='load' and getTimestampMs()-s.at>12000 then
            check(SCBridge and PZOEngine,'actual official PZO and production LF bridge loaded')
            if mode=='create' then relocate() else reload() end
        elseif s.phase=='relocate' and getTimestampMs()-s.at>10000 then create()
        elseif s.phase=='screenshot' and getTimestampMs()-s.at>2500 then
            local item,vanilla=s.floorCard,s.vanillaCard
            note('settled_card_model='..tostring(item:getWorldStaticModel())..'; settled_card_texture='..tostring(item:getTex()))
            check(item:getWorldStaticModel()==vanilla:getWorldStaticModel() and item:getWorldStaticModel()~=nil and item:getTex()~=nil,
                'vanilla IDcard model and inventory texture resolve for base normal item after native asset uploads')
            getCore():TakeFullScreenshot('larch-key-phase0-drawer.png');phase('save')
        elseif s.phase=='save' and getTimestampMs()-s.at>1500 then
            save(false);note('native_save_false_completed=true');finish(true,'created native cards and ordinary loot; disk reload required')
        end
    end)
    if not ok then finish(false,why) end
end)
