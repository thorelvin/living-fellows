-- SPDX-License-Identifier: MIT
-- One explicit radio contact; native reception completes it. No polling task.
SurvivorCompanion=SurvivorCompanion or {}
local SC=SurvivorCompanion
SC.GridRadio=SC.GridRadio or {}
local R=SC.GridRadio
local pending,receipt,serial=nil,nil,0
local function U() return SC.ControlUtil end
local function data(item) return U().call(item,"getDeviceData") end
local function usable(device,transmit)
    return device and U().call(device,"getIsTelevision")~=true
        and U().call(device,"getIsTurnedOn")==true and U().call(device,"getHasBattery")==true
        and (tonumber(U().call(device,"getPower")) or 0)>0 and U().call(device,"isPlayingMedia")~=true
        and U().call(device,"isNoTransmit")~=true
        and (not transmit or U().call(device,"getIsTwoWay")==true
            and U().call(device,"getMicIsMuted")~=true and (tonumber(U().call(device,"getTransmitRange")) or 0)>0)
end
local function owns(player,item)
    return player and item and U().owns(player,item)
        and U().call(player,"getEquipedRadio")==item
        and (U().call(player,"getPrimaryHandItem")==item or U().call(player,"getSecondaryHandItem")==item
            or U().call(player,"getClothingItem_Back")==item)
end
function R.onDeviceText(guid,code,x,y,z,message,device)
    local p=pending
    if not p then return end
    if U().now()>p.expires then pending=nil return end
    if tostring(guid)~=p.guid or tostring(code)~=p.code
        or tostring(message)~=p.text
        or U().call(p.player,"isDead")==true
        or not owns(p.player,p.handset) or not usable(data(p.handset),false)
        or U().call(data(p.handset),"getChannel")~=p.channel then return end
    if device then
        if device~=p.handset or not (tonumber(x)==p.x and tonumber(y)==p.y
            or tonumber(x)==-1 and tonumber(y)==-1) then return end
    elseif tonumber(x)~=p.x or tonumber(y)~=p.y then return end
    receipt={player=p.player,guid=p.guid,text=p.text}
    pending=nil
    U().call(p.player,"setHaloNote",p.text)
end
function R.lastReport(player)
    return receipt and receipt.player==player and receipt.text or nil
end
function R.request(player,handset)
    if type(getSpecificPlayer)~="function" or getSpecificPlayer(0)~=player
        or U().call(player,"isDead")==true or not owns(player,handset) or not usable(data(handset),true) then
        return false,"Equip a powered two-way walkie-talkie with an open microphone."
    end
    local receiverData=data(handset)
    local channel=U().call(receiverData,"getChannel")
    local px,py=SC.GameplayUtil.position(player)
    if not px or not py then return false,"Radio position unavailable." end
    local selected,senderData,distance
    for _,object in ipairs(SC.TerminalHardware.radioStations()) do
        if SC.BaseLife and SC.BaseLife.isInside(object) and SC.ControlUtil.present(object) then
            local md=U().data(object)
            local os=md and md.movableData and SC.TerminalSystem.normalize(md.movableData.LF_LarchOS)
            if os and not os.locked then
                local receiver,stationData=SC.TerminalHardware.receiver(object)
                local x,y=U().position(object)
                if x and y then
                    local range=math.floor(math.sqrt((math.floor(px)-x)^2+(math.floor(py)-y)^2))
                    local tx=tonumber(U().call(stationData,"getTransmitRange")) or 0
                    local rx=tonumber(U().call(receiverData,"getTransmitRange")) or 0
                    if receiver and usable(stationData,true) and U().call(stationData,"getChannel")==channel
                        and range>3 and range<tx and range<rx and range<=math.min(tx,rx)*0.9
                        and (not distance or range<distance) then
                        selected,senderData,distance=object,stationData,range
                    end
                end
            end
        end
    end
    if not selected then return false,"No powered base computer answers on this channel within clear two-way range." end
    local api=type(getZomboidRadio)=="function" and getZomboidRadio()
    if not api then return false,"Native radio unavailable." end
    local snapshot=SC.GridControl.snapshot(selected)
    if not snapshot.visible then return false,snapshot.reason end
    local text="EMMA: grid "..(snapshot.on and "on" or "off").."; "..snapshot.online.." substations online; heat "..math.floor(snapshot.heat).."%."
    local work=snapshot.crack
    if not work then
        for _,site in ipairs(snapshot.sites or {}) do
            if site.crack then work={label=site.label,percent=site.crack.doneHours/site.crack.requiredHours*100} break end
        end
    end
    if work then text=text.." "..work.label.." crack "..string.format("%.1f",work.percent).."%." end
    local x,y=U().position(selected)
    serial=serial+1
    local guid="LF_GRID_"..tostring(U().now()).."_"..serial
    local code="LF_GRID_REPORT"
    pending={player=player,handset=handset,x=x,y=y,text=text,guid=guid,code=code,channel=channel,expires=U().now()+15000}
    local okay,reason=pcall(function()
        api:SendTransmission(math.floor(px),math.floor(py),channel,"EMMA, grid report.",guid.."_REQ","LF_GRID_REQUEST",.7,.9,.85,
            math.floor(U().call(receiverData,"getTransmitRange")),false)
        api:SendTransmission(x,y,channel,text,guid,code,.7,.9,.85,
            math.floor(U().call(senderData,"getTransmitRange")),false)
    end)
    if not okay then pending=nil return false,"Radio transmission failed: "..tostring(reason) end
    return true,receipt and receipt.player==player and receipt.guid==guid and receipt.text or "Grid report requested. Waiting for EMMA's radio reply."
end
function R.install()
    if not R._deviceTextHook and Events and Events.OnDeviceText and type(Events.OnDeviceText.Add)=="function" then
        R._deviceTextHook=function(...) if SC.GridRadio then SC.GridRadio.onDeviceText(...) end end
        Events.OnDeviceText.Add(R._deviceTextHook)
    end
end
function R.reset() pending,receipt,serial=nil,nil,0 end
R.install()
return R
