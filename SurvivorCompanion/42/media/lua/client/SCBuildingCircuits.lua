-- SPDX-License-Identifier: MIT
-- LF circuit groups use fitted native relays and native generator services.
-- This module never changes a container type or fabricates refrigeration.
SurvivorCompanion=SurvivorCompanion or {}
local SC=SurvivorCompanion
SC.BuildingCircuits=SC.BuildingCircuits or {}
local C=SC.BuildingCircuits
function C.status()
    return "LF circuits control named lighting relays and generators. Grid power stays independent. Individual fridge switches are not available yet."
end
function C.list(computer)
    local panel=SC.BuildingControls.panel(computer,false)
    if not panel or panel.security.locked or not SC.BuildingControls.connected(computer,panel) then return {} end
    local groups={}
    for _,device in ipairs(SC.BuildingControls.list(computer)) do
        if device.kind=="light" or device.kind=="generator" then
            local name=device.kind=="generator" and "Generator supply" or device.group or "Building lighting"
            local id=(device.kind=="generator" and "supply:" or "lights:")..name
            local group=groups[id] or {id=id,label=name,on=true,devices={},kind=device.kind}
            groups[id]=group group.devices[#group.devices+1]=device.id
            local object=SC.BuildingControls.resolve(device)
            local active=device.kind=="generator" and SC.ControlUtil.call(object,"isActivated")==true
                or device.kind=="light" and SC.BuildingControls.status(device)=="On"
            group.on=group.on and active
        end
    end
    local rows={}
    for _,row in pairs(groups) do table.sort(row.devices) rows[#rows+1]=row end
    table.sort(rows,function(a,b) return a.id<b.id end)
    return rows
end
function C.prepare(computer,id,on,player)
    local selected
    for _,row in ipairs(C.list(computer)) do if row.id==id then selected=row break end end
    if not selected then return nil,"This circuit is unavailable." end
    local saved={id=id,on=on==true,members=table.concat(selected.devices,"|"),tickets={},kind=selected.kind}
    local verb=selected.kind=="generator" and (on and "start" or "stop") or on and "on" or "off"
    for _,device in ipairs(selected.devices) do
        local ticket,reason=SC.BuildingControls.prepare(computer,verb,device,player)
        if not ticket then return nil,reason end
        saved.tickets[#saved.tickets+1]=ticket
    end
    return saved,(on and "Enable " or "Disable ")..selected.label.." ("..#selected.devices.." devices)? "
        ..(selected.kind=="generator" and "Generators use native start/stop services; grid supply is unchanged. " or "").."[Y/N]"
end
function C.execute(computer,saved)
    local current
    for _,row in ipairs(C.list(computer)) do if row.id==saved.id then current=row break end end
    if not current or table.concat(current.devices,"|")~=saved.members then return false,"Circuit membership changed. Review it again." end
    local complete,reason=0
    for _,ticket in ipairs(saved.tickets) do
        local okay,why=SC.BuildingControls.execute(ticket)
        if okay then complete=complete+1 else reason=why end
    end
    return complete==#saved.tickets,complete.." of "..#saved.tickets..(saved.kind=="generator" and " generator service requests accepted." or " relays updated.")
        ..(reason and " "..tostring(reason) or "")
end
return C
