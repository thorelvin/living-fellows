-- SPDX-License-Identifier: MIT
-- An explicit internal callback. Only an active call survives a closed CRT.
SurvivorCompanion=SurvivorCompanion or {}
local SC=SurvivorCompanion local P={} SC.TerminalLockPhone=P
local active,caption
local function U() return SC.ControlUtil end
function P.code(state)
    local pick=SC.TerminalSystem.random(state.seed+941) pick(2147483646)
    return string.format("%06d",pick(1000000)-1)
end
function P.isPhone(object)
    local sprite=U().call(U().call(object,"getSprite"),"getName") or ""
    local facing=tonumber(sprite:match("^location_business_office_generic_02_(%d+)$"))
    local name=string.lower(tostring(U().property(object,"CustomName") or ""))
    return facing and facing>=0 and facing<24 or name=="telephone" or name=="phone"
end
function P.resolve(where)
    local cell=type(getCell)=="function" and getCell()
    local sq=where and U().call(cell,"getGridSquare",where.x,where.y,where.z)
    for _,object in ipairs(U().list(U().call(sq,"getObjects"),32)) do
        if P.isPhone(object) and (not where.sprite or U().call(U().call(object,"getSprite"),"getName")==where.sprite) then return object end
    end
end
function P.sameLine(pc,phone)
    local a,b=U().square(pc),U().square(phone)
    local building=U().call(a,"getBuildingDef")
    local az,bz=tonumber(U().call(a,"getZ")),tonumber(U().call(b,"getZ"))
    return building~=nil and building==U().call(b,"getBuildingDef") and az and bz and math.abs(az-bz)<=1 or false
end
function P.beginSearch(w)
    local lock=w.system.lock
    if lock.phone then return end
    local sq=U().square(w.object) local def=U().call(sq,"getBuildingDef")
    local x,y,z=U().position(w.object)
    if not def or not x then return P.noLine(w) end
    local x1=math.max(x-31,tonumber(U().call(def,"getX")) or x)
    local y1=math.max(y-31,tonumber(U().call(def,"getY")) or y)
    local x2=math.min(x+31,tonumber(U().call(def,"getX2")) or x)
    local y2=math.min(y+31,tonumber(U().call(def,"getY2")) or y)
    w.lockPhoneSearch={def=def,x=x1,y=y1,width=x2-x1+1,height=y2-y1+1,floors={z,z-1,z+1},cursor=0,scanned=0}
end
function P.noLine(w)
    w.lockPhoneSearch=nil w.system.lock.kind="word" w.system.lock.phone=nil
    SC.TerminalSystem.ensurePuzzle(w.system,SC.Terminal.electricalSkill(w.player))
    SC.TerminalLocks.markSeen(w.system)
    w.securityMessage="No internal telephone line found. Use password recovery."
end
function P.search(w)
    local f=w.lockPhoneSearch if not f then return end
    if not SC.Terminal.ownsState(w.object,w.system) or not SC.Terminal.near(w.player,w.object) then w.lockPhoneSearch=nil return end
    local cell=type(getCell)=="function" and getCell()
    local area=f.width*f.height
    for _=1,128 do
        if f.cursor>=area*3 or f.scanned>=4096 then P.noLine(w) return end
        local index=f.cursor f.cursor=index+1 f.scanned=f.scanned+1
        local floor=math.floor(index/area)+1 local at=index%area
        local sq=U().call(cell,"getGridSquare",f.x+at%f.width,f.y+math.floor(at/f.width),f.floors[floor])
        if sq and U().call(sq,"getBuildingDef")==f.def then
            for _,object in ipairs(U().list(U().call(sq,"getObjects"),32)) do
                if P.isPhone(object) then
                    local room=U().call(sq,"getRoom")
                    w.system.lock.phone={x=sq:getX(),y=sq:getY(),z=sq:getZ(),type="phone",
                        sprite=U().call(U().call(object,"getSprite"),"getName"),room=tostring(U().call(room,"getName") or "internal office"):sub(1,48)}
                    w.lockPhoneSearch=nil
                    SC.TerminalLocks.markSeen(w.system)
                    return
                end
            end
        end
    end
end
local function currentOS(call)
    local os=SC.Terminal.peekState(call.pc)
    return os and os.identity==call.identity and os.lock and os.lock.kind=="phone" and os.locked and os or nil
end
function P.stop()
    if active and active.emitter then
        U().call(active.emitter,"stopAll")
        U().call(type(getWorld)=="function" and getWorld(),"returnOwnershipOfEmitter",active.emitter)
    end
    active=nil
end
function P.ringing() return active and active.ringing==true and active or nil end
function P.dial(w)
    if active then w.securityMessage="The internal line is already in use." return false end
    local lock=w.system.lock local phone=P.resolve(lock.phone) local hours=U().hours()
    if not phone or not hours or not P.sameLine(w.object,phone) then w.securityMessage="Internal line unavailable. Check the telephone or use another recovery method." return false end
    if lock.redialUntil and hours<lock.redialUntil then w.securityMessage="Redial available in "..math.ceil((lock.redialUntil-hours)*60).." game min." return false end
    if not SC.Terminal.ownsState(w.object,w.system) or not SC.Terminal.powered(w.object)
        or not SC.Terminal.near(w.player,w.object) or U().call(w.player,"isDead")==true then return false end
    lock.redialUntil=hours+(U().skill(w.player)>=3 and 5 or 10)/60
    local x,y,z=U().position(phone)
    active={pc=w.object,identity=w.system.identity,phone=phone,player=w.player,elapsed=0,cycle=-1,ringing=false,
        last=U().now(),x=x,y=y,z=z}
    w.securityMessage="Calling the building's internal extension. Outside telephone service remains disconnected."
    return true
end
local function show(player,lines)
    if caption then caption:removeFromUIManager() caption=nil end
    if not ISPanel or not getCore then return end
    local core=getCore() local width=math.min(720,core:getScreenWidth()*.9)
    local rows={}
    for _,line in ipairs(lines) do for _,row in ipairs(SC.Terminal.wrap(line,math.max(20,math.floor((width-32)/10)))) do rows[#rows+1]=row end end
    local height=#rows*24+28
    local pane=ISPanel:new((core:getScreenWidth()-width)/2,math.max(10,math.min(core:getScreenHeight()*.60,core:getScreenHeight()-height-20)),width,height)
    pane:initialise() pane.rows=rows pane.remaining=16000 pane.last=U().now()
    pane.backgroundColor={r=.01,g=.025,b=.02,a=.94} pane.borderColor={r=.5,g=.75,b=.65,a=.8}
    pane.render=function(self)
        for i,line in ipairs(self.rows) do self:drawText(line,16,10+(i-1)*24,.78,.95,.86,1,UIFont.Code) end
    end
    pane.update=function(self)
        local now=U().now() local paused=type(isGamePaused)=="function" and isGamePaused()
        if not paused then self.remaining=self.remaining-math.max(0,math.min(250,now-self.last)) end self.last=now
        if self.remaining<=0 then self:removeFromUIManager() if caption==self then caption=nil end end
    end
    pane:addToUIManager() caption=pane
end
function P.answer(player,phone)
    local c=active local sq=U().square(phone) local from=U().square(player)
    if not c or c.cycle<0 or c.phone~=phone or not U().present(phone) or not U().near(player,phone,1.5)
        or from~=sq and U().call(from,"canReachTo",sq)~=true or U().call(player,"isDead")==true then return false end
    local os=currentOS(c)
    if not os or not P.sameLine(c.pc,phone) or not SC.Terminal.powered(c.pc) then P.stop() return false end
    os.lock.heard=true
    local code=P.code(os) local rows={"LARCH INTERNAL ATTENDANT: Account recovery.","Your recovery code is "..code..".","Repeating: "..code..". Return to the computer."}
    if os.seed%5==0 then
        local owner=SC.TerminalFiles.get(os.archive) local entry=owner and owner.entries[#owner.entries]
        if entry then table.insert(rows,2,"You have one saved message: "..entry.text:sub(1,152)) end
    end
    local x,y,z=c.x,c.y,c.z
    show(player,rows) P.stop()
    local emitter=U().call(type(getWorld)=="function" and getWorld(),"getFreeEmitter",x+.5,y+.5,z)
    U().call(emitter,"playSound","LFPhoneAnswer")
    return true
end
function P.context(index,context,objects,test)
    local c=P.ringing() if not c then return end
    local player=type(getSpecificPlayer)=="function" and getSpecificPlayer(index)
    if not player or not U().near(player,c.phone,1.5) then return end
    for _,object in ipairs(type(objects)=="table" and objects or {}) do
        if object==c.phone or U().square(object)==U().square(c.phone) then
            if test then return true end
            context:addOption("Answer the telephone",player,function(actor)
                if not P.ringing() or P.ringing().phone~=c.phone then return end
                SC.TerminalServices.install(actor,c.phone,function() return P.answer(actor,c.phone),"Internal call answered." end,30)
            end)
            return true
        end
    end
end
function P.pulse(now)
    if not active then return end
    local c=active now=now or U().now()
    local dt=math.max(0,math.min(250,now-c.last)) c.last=now
    if type(isGamePaused)=="function" and isGamePaused() then return end
    local os=currentOS(c)
    if not os or not U().present(c.phone) or not U().present(c.pc) or not P.sameLine(c.pc,c.phone)
        or not SC.Terminal.powered(c.pc) or U().call(c.player,"isDead")==true then P.stop() return end
    c.elapsed=c.elapsed+dt
    if c.elapsed>=60000 then P.stop() return end
    local cycle=math.floor(c.elapsed/6000) local ringing=c.elapsed%6000<2000
    if ringing and c.cycle~=cycle then
        c.cycle=cycle
        if not c.emitter then
            local world=type(getWorld)=="function" and getWorld()
            c.emitter=U().call(world,"getFreeEmitter",c.x+.5,c.y+.5,c.z)
            if c.emitter then U().call(world,"takeOwnershipOfEmitter",c.emitter) end
        end
        local handle=U().call(c.emitter,"playSound","LFPhoneRing")
        -- Muted/no-audio clients must still be able to answer the internal line.
        c.silent=not handle or handle==0
        if type(addSound)=="function" then addSound(nil,c.x,c.y,c.z,18,60) end
        local w=SC.Terminal.window if w and w.system.identity==c.identity and SC.TerminalLockCrew then SC.TerminalLockCrew.react(w,"phone",100) end
    elseif not ringing and c.ringing then U().call(c.emitter,"stopAll") end
    c.ringing=ringing
end
function P.lines(w)
    local lock=w.system.lock local at=lock.phone
    local rows={"LARCH/DIAL-BACK / INTERNAL RECOVERY"}
    if w.lockPhoneSearch then rows[#rows+1]="CHECKING LINE... "..w.lockPhoneSearch.scanned.."/4096 tiles" return rows end
    rows[#rows+1]="Outside service is dead. Internal line only."
    rows[#rows+1]=at and "EXT "..(100+w.system.seed%899).." / "..at.room.." / floor "..at.z or "Internal telephone unavailable."
    rows[#rows+1]="[1] Place call"
    rows[#rows+1]="Answer there; type the six-digit code here."
    if U().skill(w.player)>=3 then rows[#rows+1]="ELECTRICAL: REDIAL DELAY HALVED." end
    if lock.heard and lock.codeWrong then table.insert(rows,4,"ATTENDANT REPEATED: "..P.code(w.system)) end
    if w.securityMessage then rows[#rows+1]=w.securityMessage end
    return rows
end
function P.input(w,raw)
    local lower=raw:lower():match("^%s*(.-)%s*$") local lock=w.system.lock
    if lower=="1" or lower=="place call" then P.dial(w)
    elseif raw:match("^%d%d%d%d%d%d$") then
        if lock.heard and raw==P.code(w.system) then w.lockCodeVerified=true SC.TerminalLocks.finishUnlock(w,"phone") w.lockCodeVerified=nil
        else lock.codeWrong=true SC.TerminalLocks.record(w,raw,"wrong") w.securityMessage="Internal recovery code not accepted." end
    else w.securityMessage="Place the call, answer the telephone, then type six digits." end
    return true
end
function P.install()
    if P._context then return true end
    if not Events or not Events.OnFillWorldObjectContextMenu then return false,"phone_context_unavailable" end
    P._context=function(...) return P.context(...) end Events.OnFillWorldObjectContextMenu.Add(P._context) return true
end
function P.closeCaption() if caption then caption:removeFromUIManager() caption=nil end end
function P.reset() P.stop() P.closeCaption() end
function P.remove() if P._context then Events.OnFillWorldObjectContextMenu.Remove(P._context) end P._context=nil P.reset() end
function P.isInstalled() return P._context~=nil end
return P
