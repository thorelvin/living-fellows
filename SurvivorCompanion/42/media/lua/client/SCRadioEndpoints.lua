-- SPDX-License-Identifier: MIT
SurvivorCompanion = SurvivorCompanion or {}
local SC=SurvivorCompanion
SC.RadioEndpoints=SC.RadioEndpoints or {}
local R=SC.RadioEndpoints
local issued=setmetatable({}, {__mode="k"})
function R.station(player,computer)
    if SC.EmmaJump and SC.EmmaJump.active(player,computer) then return nil,"Borrowed power cannot run the station radio." end
    if not SC.Terminal.near(player,computer) or not (SC.Terminal.normalPowered or SC.Terminal.powered)(computer) then return nil,"Station unavailable." end
    local state=SC.TerminalHardware.state(computer,false)
    local receiver,data,item=SC.TerminalHardware.receiver(computer)
    if not state or not receiver then return nil,"Mount a usable two-way radio first." end
    local source={kind="station",owner=player,computer=computer,receiver=receiver,data=data,item=item,generation=state.generation}
    issued[source]=true
    return source
end
function R.isEndpoint(source) return type(source)=="table" and issued[source]==true end
-- Kahlua does not collect weak-key entries. Automatic reports release their
-- short-lived capabilities explicitly after the native receipt finishes.
function R.release(source) if type(source)=='table' then issued[source]=nil end end
function R.validate(player,source)
    if not R.isEndpoint(source) or source.owner~=player or SC.ControlUtil.call(player,"isDead")==true then return false,"radio_source_invalid" end
    if source.kind=="handheld" then
        local okay,reason=SC.TaxiBooking.checkRadio(player,source.item)
        if not okay then return false,reason end
        if SC.ControlUtil.call(player,"getEquipedRadio")~=source.item
            or SC.ControlUtil.call(source.item,"getDeviceData")~=source.data then return false,"radio_not_equipped" end
        return true,"radio_ready"
    end
    if source.kind=="camp_station" then
        local base=SC.BaseLife and SC.BaseLife.active()
        local os=SC.Terminal.peekState(source.computer)
        if not base or base.id~=source.baseId or not SC.BaseLife.isInside(source.computer)
            or not os or os.locked
            or SC.BaseLife.resolveObject(source.reference)~=source.computer then return false,"station_changed_or_unpowered" end
        if not (SC.Terminal.normalPowered or SC.Terminal.powered)(source.computer)
            then return false,"station_changed_or_unpowered" end
    end
    local state=SC.TerminalHardware.state(source.computer,false)
    if not SC.ControlUtil.present(source.computer) or not state or state.generation~=source.generation
        or not SC.TerminalHardware.powered(source.computer) then return false,"station_changed_or_unpowered" end
    local receiver,data,item=SC.TerminalHardware.receiver(source.computer)
    if receiver~=source.receiver or data~=source.data or item~=source.item then return false,"station_receiver_changed" end
    if SC.ControlUtil.call(data,"getIsTelevision")==true or SC.ControlUtil.call(data,"getIsTwoWay")~=true or SC.ControlUtil.call(data,"getIsTurnedOn")~=true
        or SC.ControlUtil.call(data,"getMicIsMuted")==true or SC.ControlUtil.call(data,"isNoTransmit")==true
        or (SC.ControlUtil.call(data,"getTransmitRange") or 0)<=0 then return false,"station_radio_unavailable" end
    return true,"radio_ready"
end
function R.origin(source)
    if R.isEndpoint(source) then return SC.ControlUtil.position(source.kind=="handheld" and source.owner or source.computer) end
end
function R.portable(player,item)
    if R.isEndpoint(item) then
        local okay,reason=R.validate(player,item)
        return okay and item or nil,reason
    end
    local okay,reason=SC.TaxiBooking.checkRadio(player,item)
    if not okay then return nil,reason end
    if SC.ControlUtil.call(player,"getEquipedRadio")~=item then return nil,"radio_not_equipped" end
    local source={kind="handheld",owner=player,item=item,receiver=item,
        data=SC.ControlUtil.call(item,"getDeviceData")}
    issued[source]=true
    return source
end
function R.campStation(player,computer,baseId)
    local base=SC.BaseLife and SC.BaseLife.active()
    if not base or base.id~=baseId or not SC.BaseLife.isInside(computer)
        or not SC.Terminal.isComputer(computer) then return nil,"station_unavailable" end
    local os=SC.Terminal.peekState(computer)
    if not os or os.locked then return nil,"station_unavailable" end
    local state=SC.TerminalHardware.state(computer,false)
    local receiver,data,item=SC.TerminalHardware.receiver(computer)
    local reference=SC.BaseLife.describeObject(computer,true)
    if not state or not receiver or not reference then return nil,"station_unavailable" end
    local source={kind="camp_station",owner=player,computer=computer,receiver=receiver,
        data=data,item=item,generation=state.generation,reference=reference,baseId=baseId}
    issued[source]=true
    local okay,reason=R.validate(player,source)
    return okay and source or nil,reason
end
function R.ready(source)
    if not R.isEndpoint(source) then return false,"radio_source_invalid" end
    local okay,reason=R.validate(source.owner,source)
    if not okay then return false,reason end
    if source.kind=="station" and not SC.Terminal.near(source.owner,source.computer)
        then return false,"station_unavailable" end
    local data=source.data
    local channel=tonumber(SC.ControlUtil.call(data,"getChannel"))
    if not channel or channel<1 or channel~=math.floor(channel)
        or (tonumber(SC.ControlUtil.call(data,"getDeviceVolume")) or 0)<=0
        or SC.ControlUtil.call(data,"isPlayingMedia")==true then return false,"radio_unavailable" end
    return true
end
function R.link(a,b)
    if not R.ready(a) or not R.ready(b) then return false end
    if SC.ControlUtil.call(a.data,"getChannel")~=SC.ControlUtil.call(b.data,"getChannel") then return false end
    local ax,ay=R.origin(a)
    local bx,by=R.origin(b)
    local first=tonumber(SC.ControlUtil.call(a.data,"getTransmitRange")) or 0
    local last=tonumber(SC.ControlUtil.call(b.data,"getTransmitRange")) or 0
    return ax~=nil and bx~=nil and (ax-bx)^2+(ay-by)^2<=(math.min(first,last)*.9)^2
end
function R.activeReceiver(player)
    local window=SC.Terminal and SC.Terminal.window
    if window and not window.closed and window.player==player and not window.system.locked
        and SC.Terminal.near(player,window.object) then return SC.TerminalHardware.receiver(window.object) end
end
function R.reset() issued=setmetatable({}, {__mode="k"}) end
return R
