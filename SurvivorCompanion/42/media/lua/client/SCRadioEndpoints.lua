-- SPDX-License-Identifier: MIT
SurvivorCompanion = SurvivorCompanion or {}
local SC=SurvivorCompanion
SC.RadioEndpoints=SC.RadioEndpoints or {}
local R=SC.RadioEndpoints
local issued=setmetatable({}, {__mode="k"})
function R.station(player,computer)
    if not SC.Terminal.near(player,computer) or not SC.Terminal.powered(computer) then return nil,"Station unavailable." end
    local state=SC.TerminalHardware.state(computer,false)
    local receiver,data,item=SC.TerminalHardware.receiver(computer)
    if not state or not receiver then return nil,"Mount a usable two-way radio first." end
    local source={kind="station",owner=player,computer=computer,receiver=receiver,data=data,item=item,generation=state.generation}
    issued[source]=true
    return source
end
function R.isEndpoint(source) return type(source)=="table" and issued[source]==true end
function R.validate(player,source)
    if not R.isEndpoint(source) or source.owner~=player or SC.ControlUtil.call(player,"isDead")==true then return false,"radio_source_invalid" end
    local state=SC.TerminalHardware.state(source.computer,false)
    if not SC.ControlUtil.present(source.computer) or not state or state.generation~=source.generation
        or not SC.TerminalHardware.powered(source.computer) then return false,"station_changed_or_unpowered" end
    local receiver,data,item=SC.TerminalHardware.receiver(source.computer)
    if receiver~=source.receiver or data~=source.data or item~=source.item then return false,"station_receiver_changed" end
    if SC.ControlUtil.call(data,"getIsTwoWay")~=true or SC.ControlUtil.call(data,"getIsTurnedOn")~=true
        or SC.ControlUtil.call(data,"getMicIsMuted")==true or SC.ControlUtil.call(data,"isNoTransmit")==true
        or (SC.ControlUtil.call(data,"getTransmitRange") or 0)<=0 then return false,"station_radio_unavailable" end
    return true,"radio_ready"
end
function R.origin(source)
    if R.isEndpoint(source) then return SC.ControlUtil.position(source.computer) end
end
function R.activeReceiver(player)
    local window=SC.Terminal and SC.Terminal.window
    if window and not window.closed and window.player==player and not window.system.locked
        and SC.Terminal.near(player,window.object) then return SC.TerminalHardware.receiver(window.object) end
end
function R.reset() issued=setmetatable({}, {__mode="k"}) end
return R
