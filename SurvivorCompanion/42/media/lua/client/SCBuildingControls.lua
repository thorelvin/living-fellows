-- SPDX-License-Identifier: MIT
-- Local building services. Discovery never loads a square; commands bind an
-- exact observed device and desired state, rather than replaying a toggle.
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.BuildingControls = SC.BuildingControls or {}
local B = SC.BuildingControls
local function U() return SC.ControlUtil end
local scans, live, tickets = {}, {}, setmetatable({}, {__mode="k"})
local lastPulse, serial = 0, 0
local siteCache=setmetatable({}, {__mode="k"})
local houseCache=setmetatable({}, {__mode="k"})
local deviceLists=setmetatable({}, {__mode="k"})
B.computers=setmetatable({}, {__mode="k"})
B.SCAN_BUDGET, B.MAX_DEVICES, B.HISTORY = 256, 64, 256
local fallback = {schema=1, panels={}}
local function store()
    local value = ModData and ModData.getOrCreate and ModData.getOrCreate("LF_BuildingControls") or fallback
    if value.schema == nil then value.schema, value.panels = 1, {} end
    if value.schema ~= 1 or type(value.panels) ~= "table" then return nil end
    return value
end
local function defOf(object)
    local square = U().square(object)
    return U().call(square, "getBuildingDef") or U().call(U().call(square, "getBuilding"), "getDef")
end
local function localDefinition(object)
    local direct=defOf(object)
    if direct then return direct end
    local x,y,z=U().position(object)
    if not x then return nil end
    local cached=siteCache[object]
    if cached and cached.x==x and cached.y==y and cached.z==z then return cached.def end
    for radius=1,6 do
        for dx=-radius,radius do for dy=-radius,radius do
            if math.abs(dx)==radius or math.abs(dy)==radius then
                local square=SC.GameplayUtil.gridSquare(x+dx,y+dy,z)
                local def=U().call(square,"getBuildingDef")
                if def then siteCache[object]={x=x,y=y,z=z,def=def} return def end
            end
        end end
    end
    siteCache[object]={x=x,y=y,z=z}
end
local function site(object)
    local square=U().square(object)
    if not square then return nil end
    local cached=houseCache[object]
    if cached and cached.square==square then return cached.key,cached.bounds,cached.label,cached.def end
    local def = localDefinition(object)
    if def then
        local x, y = U().call(def,"getX"), U().call(def,"getY")
        local x2,y2 = U().call(def,"getX2"), U().call(def,"getY2")
        if x and y and x2 and y2 and x2-x < 512 and y2-y < 512 then
            local names = {}
            for _, room in ipairs(U().list(U().call(def,"getRooms"),256)) do
                names[#names+1] = tostring(U().call(room,"getName") or "")
            end
            local text = string.lower(table.concat(names," "))
            local profile = text:find("bank",1,true) and "Bank" or text:find("police",1,true) and "Police station"
                or (text:find("clinic",1,true) or text:find("medical",1,true) or text:find("pharmacy",1,true)) and "Clinic"
                or (text:find("warehouse",1,true) or text:find("factory",1,true)) and "Warehouse"
                or (text:find("grocery",1,true) or text:find("gigamart",1,true) or text:find("supermarket",1,true)) and "Supermarket"
                or "Building"
            local base=SC.BaseLife and SC.BaseLife.active()
            if profile=="Building" and base and SC.BaseLife.isInside(object) then profile="Camp" end
            local key="building:"..x..":"..y..":"..x2..":"..y2
            local bounds={x=x,y=y,x2=x2,y2=y2,z=U().call(def,"getMinLevel") or 0,z2=U().call(def,"getMaxLevel") or 0}
            houseCache[object]={square=square,key=key,bounds=bounds,label=profile,def=def}
            return key,bounds,profile,def
        end
    end
    local base = SC.BaseLife and SC.BaseLife.active()
    if base and SC.BaseLife.isInside(object) then
        local x,y,z = U().position(object)
        return "camp:"..tostring(base.id),{x=x-24,y=y-24,x2=x+24,y2=y+24,z=z,z2=z},"Camp"
    end
end
local function pcId(object)
    local data=U().data(object)
    local os=data and data.movableData and data.movableData.LF_LarchOS
    return os and os.identity
end
B.computerId=pcId
function B.panel(object, create)
    local key,bounds,label,def = site(object)
    local bucket=store()
    if not key or not bucket then return nil,"No local building service area is available." end
    local panel=bucket.panels[key]
    if not panel and create then
        local seed=1
        for i=1,#key do seed=(seed*31+key:byte(i))%2147483646 end
        local security=SC.TerminalSystem.create(seed,"office",false,false,"panel:"..key)
        security.locked = label ~= "Camp"
        panel={id=key,label=label,security=security,connections={},devices={},history={},routines={}}
        bucket.panels[key]=panel
    end
    if not panel then return nil,"Connect this computer to local building services first." end
    return panel,nil,bounds,def
end
function B.log(panel, text)
    panel.history=panel.history or {}
    panel.history[#panel.history+1]={at=U().hours() or 0,text=tostring(text):sub(1,240)}
    while #panel.history>B.HISTORY do table.remove(panel.history,1) end
end
function B.connected(object,panel)
    panel=panel or B.panel(object,false)
    local point=panel and panel.connections[pcId(object)]
    local x,y,z=U().position(object)
    return point ~= nil and point.x==x and point.y==y and point.z==z
end
function B.register(object)
    local panel=B.panel(object,false)
    if panel and B.connected(object,panel) then
        B.computers[object]=panel
        local scan=scans[panel.id]
        if not scan or scan.done and U().now()-(scan.at or 0)>=30000 then B.discover(object,true) end
    end
end
function B.connect(player,object)
    if not U().near(player,object,3) or not SC.Terminal.powered(object) then return false,"Computer unavailable." end
    if U().skill(player)<2 then return false,"Electrical 2 is required." end
    if not U().hasTool(player,"Base.Screwdriver") then return false,"A screwdriver is required." end
    -- Hardware may be installed before the computer has ever been opened.
    -- Initialize once; normalizing an already open OS would replace the live
    -- session table and invalidate its consent tickets.
    if not pcId(object) then
        local state,reason=SC.Terminal.computerState(player,object)
        if not state or not pcId(object) then return false,reason or "Computer identity is unavailable." end
    end
    local panel,reason=B.panel(object,true)
    if not panel then return false,reason end
    if B.connected(object,panel) then B.discover(object,true) return true,"Already connected. Equipment rescan queued." end
    local okay
    okay,reason=U().consume(player,{["Base.ElectricWire"]=1,["Base.ElectronicsScrap"]=2})
    if not okay then return false,reason end
    local x,y,z=U().position(object)
    panel.connections[pcId(object)]={x=x,y=y,z=z}
    for _,routine in pairs(panel.routines or {}) do
        if routine.computer==pcId(object) then routine.x,routine.y,routine.z,routine.suspended=x,y,z,nil end
    end
    B.computers[object]=panel
    B.log(panel,"Computer connected to local services.")
    B.discover(object,true)
    return true,"Connected. "..(panel.security.locked and "Building security requires authorization." or "Building services are ready.")
end
local function customLock(object)
    local md=U().data(object)
    return md and (md.CustomLock or md.BB_SecureAccess or md.SecureAccess)
        or U().call(object,"isLockedByPadlock")==true or (tonumber(U().call(object,"getLockedByCode")) or 0)>0
end
local function doorGroup(object)
    if IsoDoor and IsoDoor.getGarageDoorIndex then
        local okay,index=pcall(IsoDoor.getGarageDoorIndex,object)
        if okay and index and index>0 then
            local first=IsoDoor.getGarageDoorFirst(object)
            if first then return first,"shutter" end
        end
    end
    return object,"door"
end
local function classify(object)
    if U().kind(object,"IsoDoor") or U().kind(object,"IsoThumpable") and U().call(object,"isDoor")==true then
        if not customLock(object) then return doorGroup(object) end
    elseif U().kind(object,"IsoLightSwitch") then return object,"light"
    elseif U().kind(object,"IsoThumpable") and (tonumber(U().call(object,"getLightSourceRadius")) or 0)>0 then return object,"light"
    elseif U().kind(object,"IsoGenerator") then return object,"generator"
    elseif U().kind(object,"IsoThumpable") and U().call(object,"getContainer") and U().call(object,"isLockedByKey")~=nil then
        if not customLock(object) then return object,"cabinet" end
    end
end
local function observe(panel,object)
    local target,kind=classify(object)
    if not target then return end
    local owner=defOf(target)
    if not owner and (kind=="door" or kind=="shutter") then owner=U().call(U().call(target,"getOppositeSquare"),"getBuildingDef") end
    if owner and panel.id:sub(1,9)=="building:" then
        local ownerId="building:"..tostring(U().call(owner,"getX"))..":"..tostring(U().call(owner,"getY"))..":"
            ..tostring(U().call(owner,"getX2"))..":"..tostring(U().call(owner,"getY2"))
        if ownerId~=panel.id then return end
    end
    local x,y,z=U().position(target)
    local md=U().data(target)
    if not md or not x then return end
    local id=md.LF_ControlId
    if not id then
        serial=serial+1
        id="device:"..tostring(U().now())..":"..x..":"..y..":"..z..":"..serial
        md.LF_ControlId=id
    end
    local row=panel.devices[id]
    if not row then
        local count=0 for _ in pairs(panel.devices) do count=count+1 end
        if count>=B.MAX_DEVICES then return end
        local room=U().call(U().call(U().square(target),"getRoom"),"getName")
        local rooms={livingroom="Living room",bathroom="Bathroom",bedroom="Bedroom",kitchen="Kitchen",office="Office",garage="Garage",
            bank="Bank",bankoffice="Bank office",police="Police",policeoffice="Police office",policestorage="Police storage",warehouse="Warehouse"}
        local location=room and (rooms[room] or tostring(room):gsub("_"," "):gsub("^%l",string.upper)) or "Exterior"
        row={id=id,kind=kind,x=x,y=y,z=z,label=(kind=="shutter" and "Loading shutter" or kind=="door" and "Door"
            or kind=="light" and "Lighting" or kind=="cabinet" and "Secure cabinet" or "Generator").." - "..location.." ("..x..", "..y..", floor "..z..")"}
        panel.devices[id]=row
        deviceLists[panel]=nil
    end
    live[id]=target
end
function B.discover(object,restart)
    if restart then houseCache[object]=nil siteCache[object]=nil end
    local panel,reason,bounds=B.panel(object,false)
    if not panel then return false,reason end
    if not B.connected(object,panel) then return false,"Connect this computer at its current location first." end
    if restart or not scans[panel.id] then
        local expanded={x=bounds.x-6,y=bounds.y-6,x2=bounds.x2+6,y2=bounds.y2+6,z=bounds.z,z2=bounds.z2}
        scans[panel.id]={panel=panel,bounds=expanded,x=expanded.x,y=expanded.y,z=expanded.z,done=false,at=U().now()}
    end
    return true
end
function B.scanStep(scan,budget,remaining)
    local bounds=scan.bounds
    for _=1,budget or B.SCAN_BUDGET do
        if scan.done or remaining and remaining()<=0 then return end
        local square=SC.GameplayUtil.gridSquare(scan.x,scan.y,scan.z)
        if square then
            for _,object in ipairs(U().list(U().call(square,"getObjects"),64)) do observe(scan.panel,object) end
        end
        scan.x=scan.x+1
        if scan.x>bounds.x2 then scan.x=bounds.x scan.y=scan.y+1 end
        if scan.y>bounds.y2 then scan.y=bounds.y scan.z=scan.z+1 end
        if scan.z>bounds.z2 then scan.done=true return end
    end
end
function B.resolve(row)
    local object=live[row.id]
    if U().present(object) and U().data(object).LF_ControlId==row.id then return object end
    local square=SC.GameplayUtil.gridSquare(row.x,row.y,row.z)
    for _,candidate in ipairs(U().list(U().call(square,"getObjects"),64)) do
        local md=U().data(candidate)
        if md and md.LF_ControlId==row.id then live[row.id]=candidate return candidate end
    end
end
function B.status(row)
    local object=B.resolve(row)
    if not object then return "Unavailable" end
    if row.kind=="light" then
        local on=U().kind(object,"IsoLightSwitch") and U().call(object,"isActivated") or U().call(object,"isLightSourceOn")
        return on and "On" or "Off"
    end
    if row.kind=="generator" then
        local percent=(U().call(object,"getFuel") or 0)/math.max(1,U().call(object,"getMaxFuel") or 100)*100
        return (U().call(object,"isActivated") and "Running" or "Stopped").."; fuel "..math.floor(percent).."%; condition "..tostring(U().call(object,"getCondition") or 0).."%"
    end
    return (U().call(object,"IsOpen")==true or U().call(object,"isOpen")==true) and "Open"
        or (U().call(object,"isLocked")==true or U().call(object,"isLockedByKey")==true) and "Locked" or "Closed"
end
function B.list(object)
    local panel,reason=B.panel(object,false)
    if not panel then return {},reason end
    if not B.connected(object,panel) then return {},"Connect this computer at its current location first." end
    local rows=deviceLists[panel]
    if not rows then
        rows={}
        for _,row in pairs(panel.devices) do rows[#rows+1]=row end
        table.sort(rows,function(a,b) return a.label<b.label end)
        deviceLists[panel]=rows
    end
    return rows,scans[panel.id] and not scans[panel.id].done and "Discovering loaded equipment..." or nil
end
function B.security(object,word,skill)
    local panel,reason=B.panel(object,false)
    if not panel or not B.connected(object,panel) then return false,reason or "Computer disconnected." end
    local security=panel.security
    if not security.locked then return true,"Building access is already authorized." end
    SC.TerminalSystem.ensurePuzzle(security,skill or 0)
    local code,likeness=SC.TerminalSystem.act(security,word,U().hours())
    if code=="success" then B.log(panel,"Building access authorized.") end
    return code=="success",code,likeness
end
local function authorized(object,panel)
    return U().present(object) and SC.Terminal.powered(object) and B.connected(object,panel) and panel.security.locked~=true
end
function B.prepare(object,action,id,player)
    local panel,reason=B.panel(object,false)
    if not panel or not authorized(object,panel) then return nil,reason or "Connect and authorize building security first." end
    local row=id=="panel" and {id="panel",kind="panel",label=panel.label} or panel.devices[id]
    local target=row and (row.kind=="panel" and object or B.resolve(row))
    if not target then return nil,"That device is unavailable." end
    local allowed={door={open=true,close=true,lock=true,unlock=true},shutter={open=true,close=true,lock=true,unlock=true},
        cabinet={lock=true,unlock=true},light={on=true,off=true},generator={start=true,stop=true,repair=true,refuel=true},
        panel={arm=true,disarm=true,silence=true,siren=true,announce=true,install_speaker=true,routine_return=true,routine_night=true,routine_lockdown=true,routine_stop=true}}
    if not allowed[row.kind] or not allowed[row.kind][action] then return nil,"Unsupported device action." end
    local token={}
    tickets[token]={computer=object,panel=panel,target=target,row=row,action=action,player=player,
        at=U().now(),before=B.status(row)}
    return token,action:gsub("_"," ").." "..row.label.."? [Y/N]"
end
local function obstructed(object)
    if SCBridge and SCBridge.isControlDoorObstructed then
        local okay,value=pcall(SCBridge.isControlDoorObstructed,object)
        return not okay or value~=false
    end
    -- Missing native footprint support never permits closing on an occupant.
    return true
end
local function operate(panel,row,object,action,player)
    if row.kind=="panel" and SC.BuildingSecurity then return SC.BuildingSecurity.operate(panel,object,action,player) end
    if customLock(object) then return false,"This device has another security system." end
    if row.kind=="light" then
        if row.relay~=true and (panel.label=="Camp" or panel.label=="Building") then return false,"Fit a lighting relay first." end
        if U().kind(object,"IsoLightSwitch") then
            if not U().nativePower(object) or U().call(object,"canSwitchLight")~=true then return false,"Light has no usable power or bulb." end
            if B.status(row)==(action=="on" and "On" or "Off") then return true,"Lighting is already in that state." end
            U().call(object,"setActive",action=="on")
        else
            if U().call(object,"haveFuel")~=true then return false,"The floodlight needs its native battery or fuel." end
            if B.status(row)==(action=="on" and "On" or "Off") then return true,"Lighting is already in that state." end
            U().call(object,"toggleLightSource",action=="on")
            if IsoObjectChange and IsoObjectChange.LIGHT_SOURCE then U().call(object,"sendObjectChange",IsoObjectChange.LIGHT_SOURCE) end
        end
        return B.status(row)==(action=="on" and "On" or "Off"),"Lighting updated."
    elseif row.kind=="generator" then
        if action=="refuel" and SC.GeneratorRefuel then return SC.GeneratorRefuel.queue(object,true) end
        if SC.GeneratorServices then return SC.GeneratorServices.request(player,object,action,row) end
        return false,"Generator service unavailable."
    elseif row.kind=="door" or row.kind=="shutter" or row.kind=="cabinet" then
        if not U().nativePower(object) then return false,"The door controller needs building power." end
        if U().call(object,"isBarricaded")==true then return false,"The opening is barricaded." end
        if action=="lock" or action=="unlock" then
            if row.relay~=true and (panel.label=="Camp" or panel.label=="Building") then return false,"Fit a lock relay first." end
            if action=="lock" and B.status(row)=="Open" then return false,"Close the opening before locking it." end
            if SCBridge and SCBridge.setControlDoorLocked then
                local okay,result=pcall(SCBridge.setControlDoorLocked,object,action=="lock")
                return okay and result==true,"Lock updated."
            end
            return false,"Native lock control unavailable."
        end
        if action~="open" and action~="close" then return false,"Unsupported door request." end
        if row.kind=="cabinet" then return false,"This cabinet supports lock control only." end
        if row.motor~=true and (row.kind~="shutter" or panel.label=="Camp" or panel.label=="Building") then return false,"Fit a motor controller to open this door remotely. Unlocking remains available." end
        local opened=B.status(row)=="Open"
        if opened==(action=="open") then return true,"The opening is already in that state." end
        if action=="open" and B.status(row)=="Locked" then return false,"Unlock the opening first." end
        if obstructed(object) then return false,"Opening obstructed. Clear people and vehicles, then Retry." end
        if SCBridge and SCBridge.setControlDoorOpen then
            local okay,result=pcall(SCBridge.setControlDoorOpen,object,action=="open",player)
            if okay and result==true then
                -- Native grouped doors may replace their leaves; resolve by
                -- the group's footprint and reattach only this receipt's ID.
                local square=SC.GameplayUtil.gridSquare(row.x,row.y,row.z)
                for _,candidate in ipairs(U().list(U().call(square,"getObjects"),64)) do
                    local root,kind=classify(candidate)
                    if root and kind==row.kind then U().data(root).LF_ControlId=row.id live[row.id]=root break end
                end
                return B.status(row)==(action=="open" and "Open" or "Closed"),"Opening updated."
            end
        end
        return false,"Native door operation did not complete."
    end
    return false,"Unsupported equipment."
end
B.operate=operate
function B.execute(token)
    local request=tickets[token] tickets[token]=nil
    if not request then return false,"That request is no longer pending." end
    if U().now()-request.at<0 or U().now()-request.at>120000 then return false,"That request expired." end
    if not authorized(request.computer,request.panel) or request.row.kind~="panel" and (B.resolve(request.row)~=request.target
        or B.status(request.row)~=request.before) then return false,"Equipment, access or power changed. Ask again." end
    local okay,reason=operate(request.panel,request.row,request.target,request.action,request.player)
    B.log(request.panel,request.row.label..": "..request.action.." - "..(okay and "accepted" or U().error(reason)))
    return okay,reason
end
function B.install(player,object,id,kind)
    local panel=B.panel(object,false)
    local row=panel and panel.devices[id]
    local target=row and B.resolve(row)
    local skills={relay=3,motor=4,contact=3,motion=4}
    if not target or not B.connected(object,panel) or not U().near(player,target,3) then return false,"Stand beside the target equipment." end
    if not skills[kind] or U().skill(player)<skills[kind] or not U().hasTool(player,"Base.Screwdriver") then return false,"Electrical "..tostring(skills[kind]).." and a screwdriver are required." end
    if row[kind] then return true,"That controller is already installed." end
    local costs={["Base.ElectronicsScrap"]=kind=="motor" and 4 or 2,["Base.ElectricWire"]=1}
    if kind=="motion" then costs["Base.MotionSensor"]=1 end
    local okay,reason=U().consume(player,costs)
    if not okay then return false,reason end
    row[kind]=true
    B.log(panel,"Installed "..kind.." on "..row.label)
    return true,"Controller installed."
end
function B.rename(object,id,name)
    local panel=B.panel(object,false)
    if not panel or not B.connected(object,panel) or panel.security.locked then return false,"Authorize local services first." end
    local row=panel.devices[id]
    name=tostring(name or ""):gsub("[%c]",""):sub(1,64)
    if not row or name=="" then return false,"Choose a device and a readable name." end
    row.label=name deviceLists[panel]=nil return true,"Device renamed."
end
function B.disconnect(object,panel)
    panel=panel or B.panel(object,false)
    local id=pcId(object)
    if not panel or not id or not panel.connections[id] then return end
    panel.connections[id]=nil
    for _,routine in pairs(panel.routines or {}) do if routine.computer==id then routine.suspended=true end end
    B.computers[object]=nil
    B.log(panel,"Computer disconnected; its automatic routines are suspended.")
end
function B.group(object,id,name)
    local panel=B.panel(object,false)
    local row=panel and panel.devices[id]
    if not row or row.kind~="light" or panel.security.locked or not B.connected(object,panel) then return false,"Choose an authorized light." end
    name=tostring(name or ""):gsub("[%c]",""):sub(1,48)
    row.group=name~="" and name or nil
    return true,"Lighting group updated."
end
function B.authorizeKey(object,player)
    local panel,reason,_,def=B.panel(object,false)
    if not panel or not B.connected(object,panel) then return false,reason or "Connect local controls first." end
    local keyId=tonumber(U().call(def,"getKeyId"))
    if not keyId or keyId<=0 then return false,"This controller has no matching building key record. Use security recovery." end
    for _,item in ipairs(U().items(player)) do
        if U().kind(item,"Key") and U().call(item,"getKeyId")==keyId then
            panel.security.locked=false B.log(panel,"Access authorized with the building key.")
            return true,"Building key accepted."
        end
    end
    return false,"No matching building key is in your inventory."
end
function B.suspend(object)
    local panel=B.computers[object]
    if not panel and U().present(object) then panel=B.panel(object,false) end
    if panel and SC.BuildingSecurity then SC.BuildingSecurity.stop(panel) end
end
function B.pulse(remaining)
    if not SC.ControlUtil then return end
    local window=SC.Terminal and SC.Terminal.window
    if not window or window.closed then return false end
    if not U().present(window.object) then B.suspend(window.object) return false end
    local panel=B.panel(window.object,false)
    if not panel or not B.connected(window.object,panel) then return false end
    local now=U().now()
    B.register(window.object)
    local scan=scans[panel.id]
    if scan and not scan.done then B.scanStep(scan,16,remaining) end
    if now-lastPulse>=1000 or now<lastPulse then
        lastPulse=now
        if SC.BuildingSecurity then SC.BuildingSecurity.pulse(window.object) end
    end
    return scan~=nil and not scan.done
end
function B.reset()
    scans,live,tickets,lastPulse={}, {},setmetatable({}, {__mode="k"}),0
    B.computers=setmetatable({}, {__mode="k"})
    siteCache=setmetatable({}, {__mode="k"})
    houseCache=setmetatable({}, {__mode="k"}) deviceLists=setmetatable({}, {__mode="k"})
end
return B
