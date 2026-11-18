-- SPDX-License-Identifier: MIT
-- Private native PZO fixture. Never included in the public mod payload.
local ID = 'sc-pzo-restore-02737'
local function read(name)
    local r=getFileReader(name,false); if not r then return nil end
    local parts={}; while true do local l=r:readLine(); if l==nil then break end; parts[#parts+1]=l end
    r:close(); return table.concat(parts,'\n')
end
local function write(name,text)
    local w=getFileWriter(name,true,false); assert(w,'fixture writer unavailable');w:write(text);w:close()
end
local mode=read('pzo-world-mode.txt') or 'waiting'
local text=read('pzo-input-record.txt')
local input=text and assert(loadstring(text))() or {
    id=ID,recruited=true,identity={forename='Morgan',surname='Reed',gender='female',outfit=''},
    position={x=0,y=0,z=0},speechColorKey='lavender',
    inventory={schema=2,complete=true,count=0,roots={},legacy=false,equipment={worn={},attached={}}},
    skills={{id='Axe',level=4,xp=812.5}},vitals={fatigue=0.47,endurance=0.63},order={mode='follow'},
}
local function same(a,b)
    if type(a)~=type(b) then return false end
    if type(a)~='table' then return a==b end
    for k,v in pairs(a) do if not same(v,b[k]) then return false end end
    for k in pairs(b) do if a[k]==nil then return false end end
    return true
end
local function encode(v,depth)
    depth=depth or 0;assert(depth<32,'fixture depth')
    if type(v)=='string' then return string.format('%q',v) end
    if type(v)=='number' or type(v)=='boolean' then return tostring(v) end
    assert(type(v)=='table','plain fixture values required')
    local parts={'{'};for k,x in pairs(v) do parts[#parts+1]='['..encode(k,depth+1)..']='..encode(x,depth+1)..',' end
    parts[#parts+1]='}';return table.concat(parts)
end
Events.OnInitGlobalModData.Add(function()
    local SC=SurvivorCompanion
    local store=ModData.getOrCreate(SC.Identity.worldSaveKey)
    if mode=='disk-restored' then
        assert(store.document and store.document.companions[ID], 'waiting record must load from native GlobalModData')
        assert(same(store.document.companions[ID],input), 'native disk save must retain the complete waiting record')
        print('SC_PZO_WORLD loaded exact native disk record id='..ID)
    else
        store.document={schema=SC.Identity.saveSchema,companions={[ID]=input},factionActors={}}
        print('SC_PZO_WORLD seeded exact id='..ID..' mode='..mode)
    end
end)
Events.OnMainMenuEnter.Add(function()
    write('pzo-startup-menu.txt','bridge='..tostring(SCBridge and SCBridge.getProtocol() or 'absent')..'\n')
    MainScreen.continueLatestSave('Sandbox','PzoRestoreFixture')
end)
local seenModals, modalCount = {}, 0
Events.OnRenderTick.Add(function()
    local modal=MainScreen and MainScreen.instance and MainScreen.instance.checkSavefileModal
    if modal and modal.yes and not seenModals[modal] and modalCount<5 then
        seenModals[modal]=true;modalCount=modalCount+1
        print('SC_PZO_WORLD confirming disposable save prompt '..tostring(modal.text))
        modal:onClick(modal.yes)
    end
end)
local started,done,last=0,false,0
local function finish(ok,message)
    done=true;local out='result='..(ok and 'PASS' or 'FAIL')..'\nmode='..mode..'\n'..message..'\n'
    print('SC_PZO_WORLD '..out);write('pzo-world-result.txt',out)
end
Events.OnGameStart.Add(function()
    started=getTimestampMs()
    if mode=='seed' then
        local primary=getSpecificPlayer(0)
        assert(primary and SurvivorCompanion.Registry.byId(ID)==nil,'clean primary fixture required')
        input.position={x=primary:getX()+2,y=primary:getY(),z=primary:getZ()}
        assert(SurvivorCompanion.Persistence.restore(primary),'fixture seed import failed')
    end
    print('SC_PZO_WORLD entered mode='..mode)
end)
Events.OnTick.Add(function()
    if done or started==0 then return end
    local now=getTimestampMs();if now-last<1000 then return end;last=now
    local SC=SurvivorCompanion; local P=SC.Persistence
    local record=SC.Registry.byId(ID)
    if mode=='waiting' then
        if now-started<170000 then return end
        local pending=P.pendingSnapshot()[ID]
        if record or not pending then finish(false,'expected waiting saved companion; active='..tostring(record~=nil));return end
        local ok,doc=P.save(getPlayer())
        local exact=ok and same(doc.companions[ID],input)
        local requested=P.requestScheduledSave(getPlayer())
        local status
        if requested then
            for index=1,1000 do status=P.pulse(); if status~='yielded' then break end end
        end
        local store=ModData.getOrCreate(SC.Identity.worldSaveKey)
        exact=exact and status=='complete' and same(store.document.companions[ID],input)
        if exact then
            write('pzo-retained-record.txt','return '..encode(store.document.companions[ID])..'\n')
            -- Stock game save, including the real GlobalModData binary. The
            -- next phase reloads this same disposable save without reseeding it.
            save(false)
        end
        finish(pending.status=='waiting_environment' and pending.attempts==0 and exact,
            'status='..tostring(pending.status)..'\nattempts='..tostring(pending.attempts)..'\nreason='..tostring(pending.reason)..'\nexact_record='..tostring(exact))
    elseif record and now-started>3000 then
        local native=record.actor;local healthy=SC.Actor.validateNative(native)
        if not healthy then finish(false,'native actor did not pass health validation');return end
        if mode=='seed' then
            local item=native:getInventory():AddItem('Base.Bandage')
            if not item then finish(false,'native test cargo creation failed');return end
            item:getModData().SC_PzoFixtureReceipt='pzo-cargo-02737'
            local saved,reason=P.captureRecord(record)
            if not saved then finish(false,'capture failed '..tostring(reason));return end
            saved.pzoFixtureOpaque={marker='preserve exact raw record'}
            write('pzo-captured-record.txt','return '..encode(saved)..'\n')
            finish(true,'native_id='..ID..'\nbridge='..SCBridge.getProtocol()..'\ncaptured_cargo=true')
        else
            local inv=native:getInventory():getItems();local cargo=0
            for index=0,inv:size()-1 do
                local item=inv:get(index)
                if item:getModData().SC_PzoFixtureReceipt=='pzo-cargo-02737' then cargo=cargo+1 end
            end
            finish(cargo==1 and P.pendingSnapshot()[ID]==nil,
                'native_id='..ID..'\nbridge='..SCBridge.getProtocol()..'\nmatching_cargo='..cargo)
        end
    elseif now-started>45000 then
        local pending=P.pendingSnapshot()[ID]
        finish(false,'restore deadline status='..tostring(pending and pending.status)..' reason='..tostring(pending and pending.reason))
    end
end)
