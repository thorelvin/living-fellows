-- SPDX-License-Identifier: MIT
-- One explicit, acknowledged contact. No command is applied by a text hook.
LivingFellows = LivingFellows or {}
local SC = LivingFellows
local R = {}
SC.PickupRadio = R
local pending, sequence = nil, 0
local function U() return SC.GameplayUtil end
local function call(object, name, ...)
    if object == nil then return nil end
    return (U().call(object, name, ...))
end
local function endpoints() return SC.RadioEndpoints end
local function close(a,b)
    local x,y,z=U().position(a)
    local bx,by,bz=U().position(b)
    return x and bx and math.floor(z)==math.floor(bz) and (x-bx)^2+(y-by)^2<=100
end

function R.caller(player,source)
    local api=endpoints()
    if not api or not player or call(player,"isDead")==true then return nil,"radio_source_invalid" end
    if api.isEndpoint(source) then
        if source.kind=="camp_station" or source.owner~=player then return nil,"radio_source_invalid" end
        if not api.ready(source) then return nil,"radio_unavailable" end
        return source
    end
    local endpoint,reason=api.portable(player,source)
    if not endpoint or not api.ready(endpoint) then return nil,reason or "radio_unavailable" end
    return endpoint
end

function R.driver(actor)
    if not actor then return nil end
    local item=call(actor,"getEquipedRadio")
    if not item then return nil end
    return endpoints().portable(actor,item)
end

function R.stations(player,baseId)
    local result={}
    for _,object in ipairs(SC.TerminalHardware and SC.TerminalHardware.radioStations() or {}) do
        local endpoint=endpoints().campStation(player,object,baseId)
        if endpoint then result[#result+1]=endpoint end
    end
    table.sort(result,function(a,b)
        local ax,ay=endpoints().origin(a)
        local bx,by=endpoints().origin(b)
        if ax~=bx then return ax<bx end
        return ay<by
    end)
    return result
end

function R.onDeviceText(guid,codes,_x,_y,_z,text,device)
    local p=pending
    R.lastReception={guid=tostring(guid),codes=tostring(codes),text=tostring(text),exact=p and device==p.receiver}
    if not p or tostring(guid)~=p.guid or tostring(codes)~=p.codes
        or tostring(text)~=p.text or device~=p.receiver then return end
    if not endpoints().ready(p.endpoint) then return end
    p.received=true
end

local function transmit(source,target,text,guid,codes)
    if not endpoints().link(source,target) then return false,"pickup_no_radio_contact" end
    local x,y=endpoints().origin(source)
    local channel=call(source.data,"getChannel")
    local range=call(source.data,"getTransmitRange")
    local recipient=target.kind=="handheld" and SC.Actor.isCompanion(target.owner) and target.owner or nil
    local reception={guid=guid,codes=codes,text=text,receiver=target.receiver,endpoint=target}
    pending=reception
    local okay,accepted=SC.Call.static(SCBridge,"transmitPickupRadio",recipient,target.receiver,
        math.floor(x),math.floor(y),channel,text,guid,codes,math.floor(range))
    pending=nil
    R.lastAttempt={called=okay,accepted=accepted,received=reception.received,source=source.kind,target=target.kind}
    return okay and accepted==true and reception.received==true,"pickup_no_radio_contact"
end

function R.exchange(source,target,requestId,action)
    if pending then return false,"pickup_radio_busy" end
    if not Events or not Events.OnDeviceText then return false,"pickup_radio_unavailable" end
    sequence=sequence+1
    local guid="LF-PICKUP-"..tostring(sequence).."-"..tostring(U().nowMs())
    local codes="PICKUP-"..tostring(action)
    local phrases={request="Can you come pick us up?",update="Here is our new pickup point.",
        cancel="Cancel the pickup. Bring the car home.",status="How is the pickup going?",
        retry="You can try the journey again.",destination="Here is where we would like to go."}
    local text=phrases[action] or "Calling about our pickup."
    local hook=function(...) R.onDeviceText(...) end
    Events.OnDeviceText.Add(hook)
    local executed,delivered,reason=pcall(function()
        local sent,why=transmit(source,target,text,guid,codes)
        if not sent then return false,why end
        return transmit(target,source,"Pickup request received.",guid,"ACK-"..codes)
    end)
    Events.OnDeviceText.Remove(hook)
    pending=nil
    if not executed then return false,"pickup_radio_unavailable" end
    if not delivered then return false,reason end
    if not endpoints().link(source,target) then return false,"pickup_no_radio_contact" end
    return true,{requestId=requestId,action=action,sequence=sequence}
end

-- Delivery requires the actual native receiver callback, even for a one-way report.
function R.send(source,target,text,guid,codes)
    if pending or not Events or not Events.OnDeviceText then return false,"radio_busy" end
    local hook=function(...) R.onDeviceText(...) end
    Events.OnDeviceText.Add(hook)
    local called,delivered,reason=pcall(transmit,source,target,text,guid,codes)
    Events.OnDeviceText.Remove(hook);pending=nil
    return called and delivered==true,called and reason or "radio_unavailable"
end

function R.path(ctx,actor,source)
    local caller,reason=R.caller(ctx.player or getSpecificPlayer(0),source)
    if not caller then return nil,reason end
    local handset=R.driver(actor)
    if handset and endpoints().link(caller,handset) then return {caller,handset} end
    local inside=SC.BaseLife and SC.BaseLife.isInside(actor)
    for _,station in ipairs(ctx.stations or R.stations(ctx.player or getSpecificPlayer(0),ctx.camp.id)) do
        if endpoints().link(caller,station) then
            if inside then return {caller,station} end
            if handset and endpoints().link(station,handset) then return {caller,station,handset} end
        end
    end
    return nil,"pickup_no_radio_contact"
end

function R.deliver(ctx,actor,source,action,allowLocal)
    local human=ctx.player or getSpecificPlayer(0)
    if allowLocal and (call(human,"getVehicle")~=nil
        and call(human,"getVehicle")==call(actor,"getVehicle") or close(human,actor)) then
        return true,{requestId=ctx.requestId,action=action,localContact=true}
    end
    local path,reason=R.path(ctx,actor,source)
    if not path then return false,reason end
    for index=2,#path do
        local okay,why=R.exchange(path[index-1],path[index],ctx.requestId,action)
        if not okay then return false,why end
    end
    if #path==2 and path[2].kind=="camp_station" and not SC.BaseLife.isInside(actor)
        then return false,"pickup_no_radio_contact" end
    return true,{requestId=ctx.requestId,action=action,sequence=sequence}
end

function R.localContact(player,actor)
    return actor~=nil and (call(player,"getVehicle")~=nil
        and call(player,"getVehicle")==call(actor,"getVehicle") or close(player,actor))
end

function R.origin(source) return endpoints().origin(source) end
function R.reset() pending,sequence=nil,0 return true end
return R
