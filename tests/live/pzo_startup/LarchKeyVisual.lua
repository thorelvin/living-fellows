-- SPDX-License-Identifier: MIT
-- Visual-only follow-up against the durable Phase 0 world and exact native items.
local SC,s=SurvivorCompanion,{phase='menu',checks=0,notes={'probe_revision=phase0-visible-native-inventory-r1'}}
local function write(name,value) local w=assert(getFileWriter(name,true,false));w:write(value);w:close() end
local function check(v,why) s.checks=s.checks+1;assert(v,why) end
local function phase(v) s.phase,s.at=v,getTimestampMs() end
local function finish(ok,why)
    if s.done then return end;s.done=true
    local q=ISTimedActionQueue.getTimedActionQueue(s.primary);local unchanged=q.current==s.queueCurrent and #q.queue==s.queueSize
    local text='result='..(ok and unchanged and 'PASS' or 'FAIL')..'\nmode=visual\nchecks='..s.checks..'\nreason='..tostring(why)
        ..'\nprimary_queue_untouched='..tostring(unchanged)..'\n'..table.concat(s.notes,'\n')..'\n'
    write('pzo-larch-key-result.txt',text)
end
local function visible(page,x,y,width,height)
    page:setVisible(true);page.isCollapsed=false;page.collapseCounter=0;page:setPinned();page:setMaxDrawHeight(height)
    page:setX(x);page:setY(y);page:setWidth(width);page:setHeight(height)
    page:bringToTop()
end
Events.OnMainMenuEnter.Add(function() MainScreen.continueLatestSave('Sandbox','PzoRestoreFixture') end)
local seen={}
Events.OnRenderTick.Add(function() local m=MainScreen and MainScreen.instance and MainScreen.instance.checkSavefileModal;if m and m.yes and not seen[m] then seen[m]=true;m:onClick(m.yes) end end)
Events.OnGameStart.Add(function()
    SC.Scheduler.unregister('decision');s.primary=assert(getSpecificPlayer(0));s.primary:setGodMod(true)
    local q=ISTimedActionQueue.getTimedActionQueue(s.primary);s.queueCurrent,s.queueSize=q.current,#q.queue
    if SC.UI then SC.UI.close() end
    local info=getPlayerInfoPanel(0);if info then info:setVisible(false) end
    phase('load')
end)
Events.OnTick.Add(function()
    if s.done or s.phase=='menu' then return end
    local ok,why=pcall(function()
        if s.phase=='load' and getTimestampMs()-s.at>12000 then
            local store=ModData.getOrCreate('LF_LarchKeyNativeProbe');s.drawer,s.desk=SC.TerminalDrawers.container(store.drawer)
            check(s.drawer and s.drawer:isExplored(),'retained native drawer and generated loot loaded')
            local sq=s.desk:getSquare();local stand
            for _,d in ipairs({{0,1},{1,0},{0,-1},{-1,0},{1,1},{-1,-1}}) do
                local q=getCell():getGridSquare(sq:getX()+d[1],sq:getY()+d[2],sq:getZ())
                if q and SC.GameplayUtil.isSquareFree(q) then stand=q;break end
            end
            check(stand~=nil,'free adjacent visual standing square')
            s.primary:teleportTo(stand:getX()+.5,stand:getY()+.5,stand:getZ());phase('camera')
        elseif s.phase=='camera' and getTimestampMs()-s.at>8000 then
            local a,b=getPlayerInventory(0),getPlayerLoot(0);a:refreshBackpacks();b:refreshBackpacks()
            visible(a,150,400,500,290);visible(b,660,400,500,290);b:setNewContainer(s.drawer)
            local items=s.drawer:getItems();local card
            for i=0,items:size()-1 do local x=items:get(i);if x:getFullType()=='LFLarchProbe.LarchKeyCard' then card=x end end
            check(card and card:getName()=='Access Card (H. Morrow)' and card:getTex()~=nil,'native named IDcard with normal loot is in displayed drawer')
            s.notes[#s.notes+1]='drawer_card='..card:getName()..'; drawer_items='..items:size()..'; native_icon='..card:getTex():getName()
            phase('picture')
        elseif s.phase=='picture' and getTimestampMs()-s.at>3000 then
            local b=getPlayerLoot(0);check(b.inventoryPane.inventory==s.drawer and not b.isCollapsed,'native loot page actively displays correct expanded drawer')
            getCore():TakeFullScreenshot('larch-key-phase0-visible-inventory.png');phase('finish')
        elseif s.phase=='finish' and getTimestampMs()-s.at>1500 then finish(true,'actual native inventory screenshot captured') end
    end)
    if not ok then finish(false,why) end
end)
