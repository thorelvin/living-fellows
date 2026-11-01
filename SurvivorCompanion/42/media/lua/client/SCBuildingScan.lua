-- SPDX-License-Identifier: MIT
-- Explicit, interaction-time building surveys. This module never loads chunks,
-- operates equipment, or installs an event/background continuation of its own.
SurvivorCompanion=SurvivorCompanion or {}
local SC=SurvivorCompanion
local D={}
SC.BuildingScan=D
local function U() return SC.ControlUtil end
local function B() return SC.BuildingControls end
local scans,active,serial={},nil,0
local rowCache=setmetatable({}, {__mode="k"})
local function count(rows) local n=0 for _ in pairs(rows or {}) do n=n+1 end return n end
local function pointKey(x,y,z) return x..":"..y..":"..z end
local function paused() return type(isGamePaused)=="function" and isGamePaused()==true end
local function touch(scan) scan.revision=(scan.revision or 0)+1 scan.snapshot=nil end
local function copyRow(row,readonly,new)
    return {id=row.id,kind=row.kind,x=row.x,y=row.y,z=row.z,room=row.room,
        label=row.label,named=row.named==true,readonly=readonly==true,new=new==true}
end
local function rowOrder(a,b)
    local az,bz=tonumber(a.z) or -100,tonumber(b.z) or -100
    if az~=bz then return az<bz end
    if (a.room or "")~=(b.room or "") then return (a.room or "")<(b.room or "") end
    if a.kind~=b.kind then return a.kind<b.kind end
    return tostring(a.label or a.id)<tostring(b.label or b.id)
end
function D.invalidate(panel) if panel then rowCache[panel]=nil end end
local function initialize(scan)
    if scan.floors then return end
    local b=scan.bounds
    scan.floors,scan.floorIndex,scan.feed,scan.seen={}, {}, {}, {}
    scan.previous,scan.oldFindTiles,scan.coveredFindTiles={}, {}, {}
    scan.panel.finds=type(scan.panel.finds)=="table" and scan.panel.finds or {}
    scan.deviceCount,scan.findCount=count(scan.panel.devices),count(scan.panel.finds)
    scan.processed,scan.outOfRange,scan.foundControls,scan.foundFinds,scan.newCount=0,0,0,0,0
    scan.revision,scan.carry=0,0
    scan.cell=type(getCell)=="function" and getCell() or nil
    local size=(b.x2-b.x+1)*(b.y2-b.y+1)
    scan.total=size*(b.z2-b.z+1)
    for z=b.z,b.z2 do
        local floor={z=z,total=size,done=0,outOfRange=0,found=0,extra=scan.definedMax~=nil and z>scan.definedMax}
        scan.floors[#scan.floors+1],scan.floorIndex[z]=floor,floor
    end
    for id in pairs(scan.panel.devices) do scan.previous[id]=true end
    for id,row in pairs(scan.panel.finds) do
        scan.previous[id]=true
        if row.x and row.y and row.z then scan.oldFindTiles[pointKey(row.x,row.y,row.z)]=true end
    end
end
local function record(scan,row,readonly)
    if not row or scan.seen[row.id] then return end
    scan.seen[row.id]=true
    D.invalidate(scan.panel)
    local new=not scan.previous[row.id]
    scan.feed[#scan.feed+1]=copyRow(row,readonly,new)
    if readonly then scan.foundFinds=scan.foundFinds+1 else scan.foundControls=scan.foundControls+1 end
    if new then scan.newCount=scan.newCount+1 end
    local floor=row.z and scan.floorIndex[row.z]
    if floor then floor.found=floor.found+1 end
    scan.lastFind={kind=row.kind,room=row.room,x=row.x,y=row.y,z=row.z,at=U().now()}
end
local function readOnly(object)
    if U().kind(object,"IsoTelevision") then return "tv" end
    if U().kind(object,"IsoRadio") then return "radio" end
    if SC.Terminal.isComputer(object) then return "computer" end
    if U().call(object,"getContainerByType","fridge") or U().call(object,"getContainerByType","freezer") then return "fridge" end
end
local function observeFind(scan,object)
    local kind=readOnly(object)
    if not kind then return end
    local allowed,owned=B().sameBuilding(scan.panel,object,kind)
    if not allowed then return end
    local x,y,z=U().position(object)
    if x==nil then return end
    local b=scan.siteBounds or scan.bounds
    -- Exterior controls retain their old reach; passive finds must not leak
    -- out of the building footprint into the six-tile survey padding.
    if not owned and scan.panel.id:sub(1,9)=="building:"
        and (x<b.x or x>b.x2 or y<b.y or y>b.y2) then return end
    local id=kind..":"..pointKey(x,y,z)
    local row=scan.panel.finds[id]
    if not row then
        if scan.findCount>=B().MAX_FINDS then scan.cappedFinds=true return end
        row={id=id,kind=kind,x=x,y=y,z=z,room=B().roomName(object)}
        scan.panel.finds[id]=row scan.findCount=scan.findCount+1
        D.invalidate(scan.panel)
    else row.room=B().roomName(object) end
    record(scan,row,true)
end
local function observeAlarm(scan)
    local id="alarm:"..scan.panel.id
    if U().call(scan.definition,"isAlarmed")~=true and not scan.panel.armed then return end
    local row=scan.panel.finds[id]
    if not row then
        if scan.findCount>=B().MAX_FINDS then scan.cappedFinds=true return end
        row={id=id,kind="alarm",room="Building",label="Building alarm"}
        scan.panel.finds[id]=row scan.findCount=scan.findCount+1 D.invalidate(scan.panel)
    end
    record(scan,row,true)
end
local function finish(scan)
    scan.done=true
    scan.status=(scan.cappedControls or scan.cappedFinds) and "limited"
        or scan.outOfRange>0 and "partial" or "complete"
    for id,row in pairs(scan.panel.finds) do
        local covered=row.kind=="alarm" or row.x and row.y and row.z
            and scan.coveredFindTiles[pointKey(row.x,row.y,row.z)]
        if not scan.seen[id] and covered then scan.panel.finds[id]=nil end
    end
    local floors={}
    for _,floor in ipairs(scan.floors) do
        if not floor.extra or floor.found>0 or floor.outOfRange>0 then
            floors[#floors+1]={z=floor.z,total=floor.total,done=floor.done,outOfRange=floor.outOfRange,found=floor.found}
        end
    end
    scan.panel.lastScan={at=U().hours() or 0,total=scan.total,outOfRange=scan.outOfRange,
        devices=scan.foundControls,finds=scan.foundFinds,floors=floors,
        cappedControls=scan.cappedControls==true,cappedFinds=scan.cappedFinds==true,status=scan.status}
    -- Mark before an ambiguous native callback, exactly like password XP.
    if scan.player and not scan.panel.scanXpAwarded and scan.processed>scan.outOfRange
        and U().near(scan.player,scan.computer,3) and SC.Terminal.powered(scan.computer)
        and U().call(scan.player,"isDead")~=true and B().connected(scan.computer,scan.panel) then
        scan.panel.scanXpAwarded=true
        local xp=U().call(scan.player,"getXp")
        if xp and Perks and Perks.Electricity then U().call(xp,"AddXP",Perks.Electricity,SC.TerminalSystem.XP) end
    end
    scan.resultPending=true
    D.invalidate(scan.panel) touch(scan)
    if active==scan then active=nil end
end
function D.step(scan,budget,remaining)
    initialize(scan)
    local b=scan.bounds
    local used=0
    for _=1,math.max(0,math.floor(tonumber(budget) or B().SCAN_BUDGET)) do
        if scan.done or scan.aborted or remaining and remaining()<=0 then break end
        local floor=scan.floorIndex[scan.z]
        local square=SC.GameplayUtil.gridSquare(scan.x,scan.y,scan.z)
        local chunk=U().call(scan.cell,"getChunkForGridSquare",scan.x,scan.y,scan.z)
        local inRange=chunk~=nil or square~=nil
        local key=pointKey(scan.x,scan.y,scan.z)
        if not inRange then floor.outOfRange=floor.outOfRange+1 scan.outOfRange=scan.outOfRange+1
        elseif scan.oldFindTiles[key] then scan.coveredFindTiles[key]=true end
        if square then
            for _,object in ipairs(U().list(U().call(square,"getObjects"),64)) do
                local row,controlled=B().observeDevice(scan.panel,object,scan)
                if controlled then record(scan,row,false) else observeFind(scan,object) end
            end
        end
        used=used+1 scan.processed=scan.processed+1 floor.done=floor.done+1
        scan.lastProbe={x=scan.x,y=scan.y,z=scan.z}
        scan.x=scan.x+1
        if scan.x>b.x2 then scan.x=b.x scan.y=scan.y+1 end
        if scan.y>b.y2 then scan.y=b.y scan.z=scan.z+1 end
        if scan.z>b.z2 then observeAlarm(scan) finish(scan) break end
    end
    if used>0 then touch(scan) end
    return used
end
local function usable(object,player)
    if not U().present(object) or not U().near(player,object,3)
        or U().call(player,"isDead")==true or not SC.Terminal.powered(object) then return nil,"Computer unavailable." end
    local panel,reason,bounds,definition=B().panel(object,false)
    if not panel then return nil,reason end
    if not B().connected(object,panel) then return nil,"Connect this computer at its current location first." end
    return panel,nil,bounds,definition
end
function D.start(object,player,restart)
    local panel,reason,bounds,definition=usable(object,player)
    if not panel then return false,reason end
    local prior=scans[panel.id]
    if active and (active~=prior or active.computer~=object) then return false,"Another computer is running discovery. Pause it first." end
    if prior and not prior.done and not prior.aborted and not restart then
        if active==prior and prior.computer~=object then return false,"This survey is active on another computer." end
        prior.computer,prior.player,prior.computerId=object,player,B().computerId(object)
        prior.status,prior.lastAt,prior.carry,prior.pauseReason="running",U().now(),0,nil
        active=prior touch(prior) return true,"Discovery resumed."
    end
    B().refreshSite(object)
    panel,reason,bounds,definition=B().panel(object,false)
    if not panel or not B().connected(object,panel) or not bounds then return false,reason or "Computer disconnected." end
    local minZ,maxZ=math.floor(tonumber(bounds.z) or 0),math.floor(tonumber(bounds.z2) or 0)
    local definedMax=maxZ
    if SC.BaseLife and SC.BaseLife.active() and SC.BaseLife.isInside(object) then
        local x,y,z=U().position(object)
        local chunk=U().call(type(getCell)=="function" and getCell() or nil,"getChunkForGridSquare",x,y,z)
        maxZ=math.max(maxZ,math.floor(tonumber(U().call(chunk,"getMaxLevel")) or maxZ))
    end
    if minZ< -32 or maxZ>31 or maxZ<minZ or bounds.x2<bounds.x or bounds.y2<bounds.y
        or bounds.x2-bounds.x>512 or bounds.y2-bounds.y>512 then return false,"Building survey bounds are unavailable." end
    serial=serial+1
    local b={x=bounds.x-6,y=bounds.y-6,x2=bounds.x2+6,y2=bounds.y2+6,z=minZ,z2=maxZ}
    local scan={panel=panel,computer=object,computerId=B().computerId(object),player=player,definition=definition,
        siteBounds=bounds,bounds=b,x=b.x,y=b.y,z=b.z,definedMax=definedMax,
        generation=serial,startedAt=U().now(),lastAt=U().now(),rate=64*(1+math.max(0,math.min(10,U().skill(player)))/10),status="running"}
    initialize(scan) scans[panel.id],active=scan,scan
    return true,"Building discovery started."
end
function D.pause(object,reason)
    if active and active.computer==object then
        active.status,active.pauseReason,active.lastAt,active.carry="paused",reason or "Terminal closed.",nil,0
        touch(active) active=nil return true
    end
    return false
end
function D.abort(object)
    local panel=B().panel(object,false)
    if not panel or not B().connected(object,panel) then return false,"Computer disconnected." end
    local scan=panel and scans[panel.id]
    if not scan or scan.done or scan.aborted then return false,"No survey is running." end
    if scan.computer~=object then return false,"Resume this survey here before aborting it." end
    scan.aborted,scan.done,scan.status,scan.carry=true,true,"aborted",0
    scan.x,scan.y,scan.z=nil,nil,nil
    touch(scan) if active==scan then active=nil end
    return true,"Discovery aborted. Found equipment has been kept."
end
function D.observeWindow(window,now)
    if not active then return end
    local current=SC.Terminal and SC.Terminal.window
    if window and current and window~=current then return end -- retired UI callback
    if not window or window.closed or window.state=="closing" or window.object~=active.computer then
        D.pause(active.computer,"Terminal closed.") return
    end
    if paused() then active.gamePaused=true active.lastAt=now active.carry=0
    elseif active.gamePaused then active.gamePaused=nil active.lastAt=now active.carry=0 end
end
function D.pulse(remaining)
    if not active then return false end
    local window=SC.Terminal and SC.Terminal.window
    local now=U().now()
    D.observeWindow(window,now)
    if not active or paused() or active.gamePaused then return false end
    local scan=active
    local panel,reason=usable(scan.computer,scan.player)
    if panel~=scan.panel or B().computerId(scan.computer)~=scan.computerId then D.pause(scan.computer,reason or "Connection changed.") return false end
    local elapsed=math.max(0,now-(scan.lastAt or now)) scan.lastAt=now
    local allowance=scan.carry+elapsed*scan.rate/1000
    local whole=math.floor(allowance)
    scan.carry=allowance-whole -- no banked stall, closed-window or exhausted-budget backlog
    D.step(scan,math.min(32,whole),remaining)
    return active~=nil
end
function D.state(object)
    local panel=B().panel(object,false)
    if not panel or not B().connected(object,panel) then return nil end
    local scan=panel and scans[panel.id]
    if not scan then return nil end
    if scan.snapshot then return scan.snapshot end
    local floors,hiddenEmptyTiles={},0
    for _,f in ipairs(scan.floors) do
        if not scan.done or not f.extra or f.found>0 or f.outOfRange>0 then
            floors[#floors+1]={z=f.z,total=f.total,done=f.done,outOfRange=f.outOfRange,found=f.found}
        else hiddenEmptyTiles=hiddenEmptyTiles+f.done
        end
    end
    local feed={} for i,row in ipairs(scan.feed) do feed[i]=row end
    local b=scan.bounds
    scan.snapshot={generation=scan.generation,status=scan.status,done=scan.done==true,aborted=scan.aborted==true,
        processed=scan.processed,total=scan.total,percent=scan.processed/math.max(1,scan.total)*100,
        controls=scan.foundControls,finds=scan.foundFinds,newCount=scan.newCount,revision=scan.revision,
        rate=scan.rate,outOfRange=scan.outOfRange,hiddenEmptyTiles=hiddenEmptyTiles,
        cappedControls=scan.cappedControls==true,cappedFinds=scan.cappedFinds==true,
        floors=floors,feed=feed,lastProbe=scan.lastProbe,lastFind=scan.lastFind,pauseReason=scan.pauseReason,
        bounds={x=b.x,y=b.y,x2=b.x2,y2=b.y2,z=b.z,z2=b.z2}}
    return scan.snapshot
end
function D.rows(object,feed)
    local panel=B().panel(object,false)
    if not panel or not B().connected(object,panel) then return {} end
    local scan=scans[panel.id]
    if feed and scan and not scan.done then return D.state(object).feed end
    if not rowCache[panel] then
        local rows={}
        for _,row in pairs(panel.devices) do rows[#rows+1]=copyRow(row,false) end
        for _,row in pairs(panel.finds or {}) do rows[#rows+1]=copyRow(row,true) end
        table.sort(rows,rowOrder) rowCache[panel]=rows
    end
    return rowCache[panel]
end
function D.takeResult(object)
    local panel=B().panel(object,false)
    if not panel or not B().connected(object,panel) then return nil end
    local scan=panel and scans[panel.id]
    if not scan or not scan.resultPending then return nil end
    scan.resultPending=false return D.state(object)
end
function D.reset() scans,active,serial={},nil,0 rowCache=setmetatable({}, {__mode="k"}) end
local controls=B()
controls.startScan,controls.abortScan,controls.scanState=D.start,D.abort,D.state
return D
