-- SPDX-License-Identifier: MIT
-- A mounted part has one owner: the native item payload in movableData.
-- Runtime objects are projections, and are never added to another inventory.
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.TerminalHardware = SC.TerminalHardware or {}
local H = SC.TerminalHardware
H.KEY="LF_TerminalHardware"
local runtime=setmetatable({}, {__mode="k"})
local lastPulse=0
local survey
local function U() return SC.ControlUtil end
function H.state(object,create)
    local md=U().data(object)
    if type(md)~="table" then return nil end
    if not md.movableData and create then md.movableData={} end
    local portable=md.movableData
    if type(portable)~="table" then return nil end
    if not portable[H.KEY] and create then portable[H.KEY]={schema=1,generation=0,on=true} end
    local state=portable[H.KEY]
    if type(state)~="table" or state.schema~=1 then return nil end
    if type(state.generation)~="number" or state.generation<0 or state.generation~=math.floor(state.generation)
        or state.on~=nil and type(state.on)~="boolean" then return nil end
    for _,kind in ipairs({"radio","ups"}) do
        local part=state[kind]
        if part~=nil and (type(part)~="table" or type(part.blob)~="string" or #part.blob>524288
            or type(part.id)~="number" or part.id~=math.floor(part.id) or type(part.type)~="string"
            or type(part.weight)~="number" or part.weight<0 or part.weight>1000
            or part.charge~=nil and (type(part.charge)~="number" or part.charge<0 or part.charge>1 or part.charge~=part.charge)) then return nil end
    end
    runtime[object]=runtime[object] or {}
    return state
end
local function bridge(name,...)
    local fn=SCBridge and SCBridge[name]
    if not fn then return nil end
    local okay,value=pcall(fn,...)
    if okay then return value end
end
local function pack(item)
    local blob=bridge("packTerminalItem",item)
    if type(blob)~="string" or #blob>524288 then return nil end
    return {blob=blob,id=U().call(item,"getID"),type=U().call(item,"getFullType"),
        weight=tonumber(U().call(item,"getActualWeight")) or 0,charge=not U().kind(item,"Radio") and U().charge(item) or nil}
end
local function unpackPart(part)
    if type(part)~="table" or type(part.blob)~="string" then return nil end
    local item=bridge("unpackTerminalItem",part.blob)
    if not item or U().call(item,"getID")~=part.id or U().call(item,"getFullType")~=part.type then return nil end
    if type(part.charge)=="number" and part.charge>=0 and part.charge<=1 then U().setCharge(item,part.charge) end
    return item
end
H.capturePart, H.restorePart = pack, unpackPart
local function cached(object,kind)
    local state=H.state(object,false)
    local r=runtime[object]
    local part=state and state[kind]
    if not part then return nil end
    if r[kind] and r[kind].part==part then return r[kind].item end
    local item=unpackPart(part)
    if not item then return nil end
    r[kind]={part=part,item=item}
    return item
end
function H.flush(object)
    local state=H.state(object,false)
    local r=runtime[object]
    if not state or not r then return true end
    for _,kind in ipairs({"radio","ups"}) do
        local entry=r[kind]
        if entry and state[kind]==entry.part then
            local data=kind=="radio" and U().call(entry.item,"getDeviceData")
            local current
            if data then
                current={U().call(data,"getIsBatteryPowered"),U().call(data,"getHasBattery"),U().call(data,"getPower")}
                U().call(data,"setIsBatteryPowered",entry.part.batteryPowered)
                U().call(data,"setHasBattery",entry.part.hasBattery)
                U().call(data,"setPower",entry.part.batteryPower)
                if entry.part.originalVolume~=nil then U().call(data,"setDeviceVolume",entry.part.originalVolume) end
            end
            local saved=pack(entry.item)
            if data then
                U().call(data,"setIsBatteryPowered",current[1]) U().call(data,"setHasBattery",current[2]) U().call(data,"setPower",current[3])
                U().call(data,"setDeviceVolume",entry.part.monitorVolume or 0.3)
            end
            if not saved then return false,"Hardware could not be saved; moving is suspended." end
            entry.part.blob=saved.blob
        end
    end
    return true
end
function H.stop(object)
    local r=runtime[object]
    if r and r.receiver then U().call(r.receiver,"removeFromWorld") r.receiver=nil end
end
function H.install(player,object,kind,item)
    local level=kind=="radio" and 2 or 4
    if kind~="radio" and kind~="ups" then return false,"Unknown upgrade." end
    if not SC.Terminal.isComputer(object) or not U().present(object) or not U().near(player,object,3) then return false,"Stand beside the computer." end
    if U().skill(player)<level or not U().hasTool(player,"Base.Screwdriver") then return false,"Electrical "..level.." and a screwdriver are required." end
    if not U().owns(player,item) then return false,"The selected component changed owner." end
    local data=U().call(item,"getDeviceData")
    if kind=="radio" and (not U().kind(item,"Radio") or U().call(data,"getIsTwoWay")~=true or (tonumber(U().call(data,"getTransmitRange")) or 0)<=0) then
        return false,"Choose a working two-way walkie-talkie."
    end
    if kind=="ups" and (not tostring(U().call(item,"getFullType")):match("^Base%.CarBattery")
        or (U().charge(item) or 0)<=0) then return false,"Choose a charged car battery." end
    if (tonumber(U().call(item,"getCondition")) or 0)<=0 then return false,"That component is broken." end
    local state=H.state(object,true)
    if not state then return false,"Hardware record is unreadable." end
    if state[kind] then return false,"Remove the existing upgrade first." end
    local part=pack(item)
    if not part then return false,"The native bridge cannot preserve this exact component." end
    if data then
        part.batteryPowered=U().call(data,"getIsBatteryPowered")==true
        part.hasBattery=U().call(data,"getHasBattery")==true
        part.batteryPower=tonumber(U().call(data,"getPower")) or 0
        part.originalVolume=tonumber(U().call(data,"getDeviceVolume"))
        part.monitorVolume=0.3
    end
    local okay,reason=U().consume(player,{["Base.ElectricWire"]=1,["Base.ElectronicsScrap"]=kind=="ups" and 4 or 2})
    if not okay then return false,reason end
    local container=U().call(item,"getContainer")
    U().call(container,"Remove",item)
    if SC.GameplayUtil.containerContainsIdentity(container,item) then U().refund(reason) return false,"The component could not be transferred." end
    if U().call(player,"getPrimaryHandItem")==item then U().call(player,"setPrimaryHandItem",nil) end
    if U().call(player,"getSecondaryHandItem")==item then U().call(player,"setSecondaryHandItem",nil) end
    state[kind],state.generation,state.lastHours=part,state.generation+1,U().hours()
    runtime[object][kind]={part=part,item=item}
    state.on=true
    return true,kind=="radio" and "Walkie-talkie mounted. Expedition station ready." or "Battery backup installed."
end
function H.remove(player,object,kind)
    if not U().near(player,object,3) or not U().hasTool(player,"Base.Screwdriver") then return false,"Stand beside the PC with a screwdriver." end
    local state=H.state(object,false)
    local part=state and state[kind]
    if not part then return false,"That upgrade is not installed." end
    if not H.flush(object) then return false,"The component cannot be safely transferred." end
    local item=unpackPart(part)
    if not item then return false,"The saved component is unreadable. It has been preserved." end
    for _,candidate in ipairs(U().items(player)) do
        if U().call(candidate,"getID")==part.id then return false,"An item with this identity is already present. Transfer stopped." end
    end
    local inventory=U().inventory(player)
    if U().call(inventory,"hasRoomFor",player,item)~=true then return false,"Make room in your inventory first." end
    if kind=="radio" then H.stop(object) end
    -- Clear ownership before the native add; restore it if the add fails.
    state[kind]=nil
    U().call(inventory,"AddItem",item)
    if not SC.GameplayUtil.containerContainsIdentity(inventory,item) then state[kind]=part return false,"Transfer failed; the component remains mounted." end
    runtime[object][kind]=nil state.generation=state.generation+1
    return true,"The original component was removed intact."
end
function H.powered(object)
    local state=H.state(object,false)
    if not state then return U().nativePower(object) end
    if state.on==false then return false end
    if U().nativePower(object) then return true end
    local battery=cached(object,"ups")
    return battery~=nil and (U().charge(battery) or 0)>0 and (tonumber(U().call(battery,"getCondition")) or 0)>0
end
function H.receiver(object)
    local state=H.state(object,false)
    local item=cached(object,"radio")
    if not state or not item or not H.powered(object) then return nil end
    local r=runtime[object]
    if not r.receiver then r.receiver=bridge("createTerminalReceiver",item,object) end
    local data=U().call(item,"getDeviceData")
    if r.receiver and data then
        -- The station supply is separate from the original handset battery.
        -- flush restores the original battery fields during serialization.
        U().call(data,"setIsBatteryPowered",true) U().call(data,"setHasBattery",true)
        U().call(data,"setPower",1) U().call(data,"setIsTurnedOn",true)
        U().call(data,"setDeviceVolume",state.radio.monitorVolume or 0.3)
        U().call(r.receiver,"update")
        return r.receiver,data,item
    end
end
function H.describe(object)
    local state=H.state(object,false)
    if not state then return "Computer supply: "..(U().nativePower(object) and "building power" or "off") end
    local battery=cached(object,"ups")
    local charge=battery and U().charge(battery) or 0
    return "Supply: "..(U().nativePower(object) and "building power" or H.powered(object) and "battery backup" or "off")
        ..". Backup: "..math.floor(charge*100).."%. Radio: "..(state.radio and "mounted" or "not installed").."."
end
function H.beforePickup(object)
    if not H.flush(object) then return false end
    H.stop(object)
    local state=H.state(object,false)
    if state then state.lastHours=nil end
    return true
end
function H.afterPickup(object,item,square)
    if U().present(object) then return end
    local state=H.state(object,false)
    if not state then return end
    local md=U().data(item)
    local portable=md and md.movableData and md.movableData[H.KEY]
    if portable then
        -- Vanilla copied the complete assembly into its one furniture item.
        H.stop(object) runtime[object]=nil
        return
    end
    -- A failed native furniture break test removes the PC but returns an
    -- unowned item with no movableData. Recover only the exact owned parts,
    -- using native world drops. Never retry an ambiguous native transfer.
    local recovery=ModData and ModData.getOrCreate and ModData.getOrCreate("LF_TerminalRecovery")
    for _,kind in ipairs({"radio","ups"}) do
        local part=state[kind]
        if part then
            local component=unpackPart(part)
            if component then
                state[kind]=nil
                local called,drop=pcall(function() return square:AddWorldInventoryItem(component,0.5,0.5,0) end)
                if not called or U().call(drop,"getItem")~=component then
                    -- Preserve evidence, not a second transferable owner.
                    if recovery then recovery[tostring(part.id)]={part=part,x=U().call(square,"getX"),y=U().call(square,"getY"),
                        z=U().call(square,"getZ"),reason="native drop unconfirmed; inspect before any recovery"} end
                    if SC.Diagnostics and SC.Diagnostics.report then SC.Diagnostics.report("terminal_hardware",nil,"Native break recovery unconfirmed for "..tostring(part.id)) end
                end
            end
        end
    end
    H.stop(object) runtime[object]=nil
end
function H.weight(object)
    local state=H.state(object,false) local total=0
    for _,kind in ipairs({"radio","ups"}) do if state and state[kind] then total=total+(state[kind].weight or 0) end end
    return total
end
function H.pulse()
    if not SC.ControlUtil then return end
    local now=U().now()
    if now-lastPulse<1000 and now>=lastPulse then return end
    lastPulse=now
    H.survey(now)
    for object,r in pairs(runtime) do
        if not U().present(object) then H.stop(object) runtime[object]=nil else
            local state=H.state(object,false)
            local hours=U().hours()
            if state then
                local active=state.on~=false and (state.radio~=nil or SC.Terminal.window and SC.Terminal.window.object==object)
                if active and not U().nativePower(object) and hours and state.lastHours then
                    local battery=cached(object,"ups")
                    if battery then
                        local fraction=math.max(0,(tonumber(U().call(battery,"getCondition")) or 0)/math.max(1,tonumber(U().call(battery,"getConditionMax")) or 100))
                        local delta=math.max(0,hours-state.lastHours)/(6*math.max(0.01,fraction))
                        U().setCharge(battery,math.max(0,(U().charge(battery) or 0)-delta))
                        state.ups.charge=U().charge(battery)
                    end
                end
                state.lastHours=hours
                if state.radio and H.powered(object) then H.receiver(object) else H.stop(object) end
                if not r.lastFlush or now-r.lastFlush>=10000 then H.flush(object) r.lastFlush=now end
            end
        end
    end
end
function H.reset()
    for object in pairs(runtime) do H.flush(object) H.stop(object) end
    runtime=setmetatable({}, {__mode="k"}) lastPulse=0 survey=nil
end
function H.save()
    for object in pairs(runtime) do
        local okay,reason=H.flush(object)
        if not okay then return false,reason end
    end
    return true
end
function H.observeSquare(square)
    if not SC.ControlUtil or not SC.Terminal then return end
    for _,object in ipairs(U().list(U().call(square,"getObjects"),64)) do
        if SC.Terminal.isComputer(object) then
            H.state(object,false)
            if SC.BuildingControls then SC.BuildingControls.register(object) end
        end
    end
end
function H.survey(now)
    local player=type(getSpecificPlayer)=="function" and getSpecificPlayer(0)
    local x,y,z=U().position(player)
    if not x then return end
    if not survey or math.abs(x-survey.cx)>8 or math.abs(y-survey.cy)>8 or z~=survey.cz
        or survey.done and now-survey.at>30000 then
        survey={cx=x,cy=y,cz=z,x=x-12,y=y-12,z=z,floors={z,z-1,z+1},plane=1,at=now}
    end
    for _=1,256 do
        if survey.done then break end
        local square=SC.GameplayUtil.gridSquare(survey.x,survey.y,survey.z)
        if square then H.observeSquare(square) end
        survey.x=survey.x+1
        if survey.x>survey.cx+12 then survey.x=survey.cx-12 survey.y=survey.y+1 end
        if survey.y>survey.cy+12 then
            survey.y=survey.cy-12 survey.plane=survey.plane+1 survey.z=survey.floors[survey.plane]
            if survey.z==nil then survey.done=true end
        end
    end
end
return H
