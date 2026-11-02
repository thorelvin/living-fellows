-- SPDX-License-Identifier: MIT
-- A UI interlock over ordinary furniture. Rewards do not exist until release.
SurvivorCompanion=SurvivorCompanion or {}
local SC=SurvivorCompanion local D={} SC.TerminalDrawers=D
local allowed={desk=true,sidetable=true,filingcabinet=true,dresser=true}
local openIcons=setmetatable({},{__mode="k"})
local function U() return SC.ControlUtil end
local function ledger() return SC.TerminalLocks.ledger() end
function D.enabled()
    return not (SandboxVars and SandboxVars.LivingFellows and SandboxVars.LivingFellows.LockRealItems==false)
end
local function furniture(object,create)
    local data=U().data(object)
    if type(data)~="table" then return nil end
    if data.movableData==nil and create then data.movableData={} end
    return type(data.movableData)=="table" and data.movableData or nil
end
local function location(object,container)
    local x,y,z=U().position(object)
    return {x=x,y=y,z=z,type=U().call(container,"getType"),sprite=U().call(U().call(object,"getSprite"),"getName")}
end
local function same(a,b) return a and b and a.x==b.x and a.y==b.y and a.z==b.z and a.type==b.type end
local function square(where)
    return where and type(getCell)=="function" and U().call(getCell(),"getGridSquare",where.x,where.y,where.z)
end
function D.container(where)
    local tile=square(where) if not tile then return nil,"unloaded" end
    local objects=U().list(U().call(tile,"getObjects"),64)
    for _,object in ipairs(objects) do
        local c=U().call(object,"getContainer")
        if c and U().call(c,"getType")==where.type
            and (not where.sprite or U().call(U().call(object,"getSprite"),"getName")==where.sprite) then return c,object end
    end
    return nil,"missing"
end
function D.computer(claim)
    local tile=square(claim.pc) if not tile then return nil,nil,"unloaded" end
    for _,object in ipairs(U().list(U().call(tile,"getObjects"),64)) do
        if SC.Terminal.isComputer(object) then
            local state=SC.Terminal.peekState(object)
            if state and state.identity==claim.id then return object,state end
        end
    end
    return nil,nil,"missing"
end
function D.find(object)
    local x,y,z=U().position(object)
    if not x then return nil end
    local book=ledger() local taken={}
    for _,claim in pairs(book and book.drawers or {}) do taken[#taken+1]=claim.drawer end
    for _,offset in ipairs({{0,0},{0,-1},{1,0},{0,1},{-1,0},{-1,-1},{1,-1},{1,1},{-1,1}}) do
        local tile=square({x=x+offset[1],y=y+offset[2],z=z})
        for _,candidate in ipairs(U().list(U().call(tile,"getObjects"),64)) do
            local container=U().call(candidate,"getContainer")
            local data=furniture(candidate,false)
            if allowed[U().call(container,"getType")] and not (data and (data.LF_LarchDrawerOwner or data.LF_LarchDrawerBroken)) then
                local where=location(candidate,container) local free=true
                for _,other in ipairs(taken) do if same(where,other) then free=false break end end
                if free then return where end
            end
        end
    end
end
function D.claim(player,object,state)
    local book,lock=ledger(),state.lock
    if lock and not D.enabled() then lock.realItems=false D.release(object) return end
    if not book or not lock or lock.drawer or lock.drawerChecked or lock.slip or lock.realItems==false
        or lock.stash and lock.stash.committed then return end
    lock.drawerChecked=true
    if lock.kind~="persona" and SC.TerminalPayoff and SC.TerminalPayoff.wantsNote(state) then return end
    local count=0 for _ in pairs(book.drawers) do count=count+1 end
    if count>=32 then return end
    local where=D.find(object) if not where then return end
    local _,desk=D.container(where) local data=desk and furniture(desk,true)
    if data then data.LF_LarchDrawerOwner=state.identity end
    local x,y,z=U().position(object)
    lock.drawer=where
    book.drawers[state.identity]={id=state.identity,pc={x=x,y=y,z=z},drawer=where}
end
function D.release(object)
    local state=SC.Terminal.peekState(object) local book=ledger()
    if not state or not book then return end
    book.drawers[state.identity]=nil
    if type(state.lock)=="table" then
        local _,desk=D.container(state.lock.drawer)
        local data=type(desk)~="string" and desk and furniture(desk,false)
        if data and data.LF_LarchDrawerOwner==state.identity then data.LF_LarchDrawerOwner=nil end
        state.lock.drawer=nil
        state.lock.stash=state.lock.stash or {committed=true,items={}}
        state.lock.stash.committed=true
    end
end
function D.claimFor(container)
    if not D.enabled() then return nil end
    if not allowed[U().call(container,"getType")] then return nil end
    local book=ledger() if not book then return nil end
    local limit=0
    for id,claim in pairs(book.drawers) do
        limit=limit+1 if limit>32 then break end
        if type(claim)=="table" and type(claim.drawer)=="table" then
            local c=D.container(claim.drawer)
            if c==container then
                local object,state=D.computer(claim)
                local lock=state and type(state.lock)=="table" and state.lock
                if object and lock and lock.drawer and not lock.drawer.open and not lock.drawer.forced then
                    return claim,object,state
                end
            end
        end
    end
end
function D.locked(container) return container~=nil and D.claimFor(container)~=nil end
function D.snapshot()
    local blocked={} local book=ledger() local count=0
    for _,claim in pairs(book and book.drawers or {}) do
        count=count+1 if count>32 then break end
        local c=D.container(claim.drawer) local _,state=D.computer(claim)
        local lock=state and type(state.lock)=="table" and state.lock
        if c and lock and lock.drawer and not lock.drawer.open and not lock.drawer.forced then blocked[c]=true end
    end
    return blocked
end
function D.blockedPointer() return true end
function D.refresh(page,phase)
    if not page or page.onCharacter or tonumber(page.player)~=0 or phase~="buttonsAdded" then return end
    local book=ledger() if not book then return end
    if not D.enabled() then
        for id,claim in pairs(book.drawers) do
            local object=D.computer(claim)
            if object then D.release(object) else book.drawers[id]=nil end
        end
    end
    local limit=0
    local blocked={}
    for id,claim in pairs(book.drawers) do
        limit=limit+1 if limit>32 then break end
        local object,state,why=D.computer(claim) local container,missing=D.container(claim.drawer)
        if why=="missing" or missing=="missing" then
            if object then D.release(object) end
            local _,desk=D.container(claim.drawer)
            local data=type(desk)~="string" and desk and furniture(desk,false)
            if data and data.LF_LarchDrawerOwner==id then data.LF_LarchDrawerOwner=nil end
            book.drawers[id]=nil
        elseif container and state and type(state.lock)=="table" and state.lock.drawer
            and not state.lock.drawer.open and not state.lock.drawer.forced then
            blocked[container]=true
        end
    end
    local floor
    for _,b in ipairs(page.backpacks or {}) do if U().call(b.inventory,"getType")=="floor" then floor=b.inventory break end end
    for _,b in ipairs(page.backpacks or {}) do
        -- Resolve each physical claim once per refresh, not once per button.
        local locked=blocked[b.inventory]==true
        local old=b.lfDrawerBindings
        if old and old.inventory~=b.inventory then b.lfDrawerBindings=nil old=nil end
        if locked then
            if not old then
                old={} b.lfDrawerBindings=old
                old.inventory=b.inventory
                for _,key in ipairs({"onclick","onmousedown","onMouseUp","onmouseover","onmouseout","textureOverride","tooltip"}) do old[key]=b[key] end
            end
            -- nil would reveal ISButton's inherited onMouseUp method. Consume
            -- the drop explicitly, independent of future vanilla UI changes.
            b.onclick,b.onmousedown,b.onmouseover,b.onmouseout=nil,nil,nil,nil
            b.onMouseUp=D.blockedPointer
            b.textureOverride=type(getTexture)=="function" and getTexture("media/ui/lock.png") or nil
            b.tooltip="LOCKED: CONTROLLED BY THIS COMPUTER"
            if floor and page.inventoryPane and page.inventoryPane.inventory==b.inventory then page:setNewContainer(floor) end
        elseif old then
            for _,key in ipairs({"onclick","onmousedown","onMouseUp","onmouseover","onmouseout","textureOverride","tooltip"}) do b[key]=old[key] end
            b.lfDrawerBindings=nil
        end
        if not locked and openIcons[b.inventory] and type(getTexture)=="function" then b.textureOverride=getTexture("media/ui/lockOpen.png") end
    end
end
local function sound(object,name)
    local x,y,z=U().position(object)
    local emitter=type(getWorld)=="function" and U().call(getWorld(),"getFreeEmitter",x+.5,y+.5,z)
    if emitter then U().call(emitter,"playSound",name) end
end
function D.open(player,object,state,forced,granted)
    if not D.enabled() then D.release(object) return false,"Computer drawer rewards are disabled." end
    local where=state and type(state.lock)=="table" and state.lock.drawer
    if not where or where.open or where.forced or not SC.Terminal.ownsState(object,state)
        or not U().near(player,object,3) or U().call(player,"isDead")==true then return false,"The drawer is no longer available." end
    if not forced and state.locked and not (granted==true and state.lock.kind=="persona") then return false,"Unlock the computer first." end
    local container,desk=D.container(where)
    if not container then return false,"The original drawer is not available." end
    local x,y,z=U().position(object)
    if not x or math.abs(x-where.x)>1 or math.abs(y-where.y)>1 or z~=where.z then
        D.release(object) return false,"The computer is no longer connected to its original drawer."
    end
    if forced and not U().hasTool(player,"Base.Crowbar") then return false,"Bring a crowbar." end
    if forced then
        where.forced=true
        if state.lock.kind=="persona" and state.lock.persona then state.lock.persona.flags.forced=true end
        local data=furniture(desk,true) if data then data.LF_LarchDrawerBroken=true end
    else where.open=true end
    -- Commit before native fill/AddItem. Neither an exception nor reloading
    -- can turn uncertain physical items into a second reward.
    if U().call(container,"isExplored")~=true then
        if ItemPicker and ItemPicker.fillContainer then pcall(ItemPicker.fillContainer,container,player) end
        U().call(container,"setExplored",true)
    end
    if SC.TerminalPayoff then SC.TerminalPayoff.place(player,object,state,container,forced) end
    local book=ledger() if book then book.drawers[state.identity]=nil end
    openIcons[container]=true
    sound(desk,forced and "LFDrawerForce" or "LFDrawerClunk")
    if forced and type(addSound)=="function" then addSound(nil,where.x,where.y,where.z,25,80) end
    local message=forced and "Drawer interlock broken. The computer is still locked." or SC.TerminalPayoff.drawerMessage(state)
    if not forced and state.lock.stash and state.lock.stash.note then message=message.."\n"..state.lock.stash.note end
    return true,message
end
function D.context(context,player,objects)
    local targets={}
    for _,object in ipairs(U().list(objects,64)) do
        local container=U().call(object,"getContainer")
        if container then targets[#targets+1]=container end
    end
    for _,container in ipairs(targets) do
        local _,computer,state=D.claimFor(container)
        if computer and U().near(player,computer,3) and U().hasTool(player,"Base.Crowbar") then
            context:addOption("Force the drawer",player,function(actor)
                SC.TerminalServices.install(actor,computer,function()
                    local current=SC.Terminal.peekState(computer)
                    if not current or current.identity~=state.identity then return false,"The original computer is gone." end
                    return D.open(actor,computer,current,true)
                end,300)
            end)
            return true
        end
    end
    return false
end
return D
