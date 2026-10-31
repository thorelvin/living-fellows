-- SPDX-License-Identifier: MIT
-- Terminal presentation delegates effects to checked building/hardware/radio
-- services. Menu entries never hold permission to toggle arbitrary objects.
require "SCExpeditionMap"
SurvivorCompanion=SurvivorCompanion or {}
local SC=SurvivorCompanion
SC.TerminalServices=SC.TerminalServices or {}
local S=SC.TerminalServices
local function U() return SC.ControlUtil end
local function B() return SC.BuildingControls end
local function option(label,action,value) return {label=label,serviceAction=action,serviceValue=value} end
local function page(window,name)
    window.menuPage,window.menuSelection,window.servicePage=name,1,0
    window.serviceMenuPage=0
    if name~="building_security" then window.serviceSecurity=nil end
    window:setFocusMode("menu")
end
local function show(window,lines)
    window:setFocusMode("chat")
    window:startReply({lines=type(lines)=="table" and lines or {tostring(lines)},thinkMs=0})
end
local function candidates(window,kind)
    local rows={}
    for _,item in ipairs(U().items(window.player)) do
        local data=U().call(item,"getDeviceData")
        if kind=="radio" and U().kind(item,"Radio") and U().call(data,"getIsTwoWay")==true
            or kind~="radio" and tostring(U().call(item,"getFullType")):match("^Base%.CarBattery") then
            rows[#rows+1]=item
        end
    end
    return rows
end
local function paged(window,rows,make,back)
    local result={}
    for _,row in ipairs(rows) do result[#result+1]=make(row) end
    result[#result+1]=option("Back","page",back)
    return result
end
local function crew(window)
    local rows={}
    for _,actor in ipairs(SC.Registry and SC.Registry.living() or {}) do
        local id=SC.Registry.idOf(actor)
        local record=SC.Registry.byId(id)
        local described=SC.Commands and SC.Commands.describe(id,window.player)
        if record and described and described.recruited and described.alive~=false and described.available~=false then rows[#rows+1]=record end
    end
    table.sort(rows,function(a,b) return tostring(a.name or a.id)<tostring(b.name or b.id) end)
    return rows
end
function S.menu(window)
    local p=window.menuPage
    if p=="home_services" then
        local result={option("Building services","page","services"),option("Computer upgrades","page","hardware"),
            option("Expedition station","page","station"),option("Back to EMMA","page",nil)}
        local hardware=SC.TerminalHardware.state(window.object,false)
        if SC.GridControl and SC.GridControl.visible() and SC.TerminalGridUI then
            table.insert(result,1,{label="LARCH/GRID power control",gridAction="open"})
        end
        if hardware and hardware.radio and SC.TerminalRadioUI then
            table.insert(result,1,{label="LARCH/WAVE radio desk",radioAction="open"})
        end
        if #result>5 then
            return {result[1],result[2],result[3],option("More services","page","home_services_more"),
                option("Back to EMMA","page",nil)}
        end
        return result
    elseif p=="home_services_more" then
        return {option("Computer upgrades","page","hardware"),option("Expedition station","page","station"),
            option("Back to services","page","home_services")}
    elseif p=="services" then
        return {option("Connect local controls (Electrical 2)","propose",{operation="connect"}),
            option("Authorize building security","security"),option("Equipment","page","equipment"),
            option("Alarms and speakers","page","security_panel"),option("Security history","history"),
            option("Automatic routines","page","routines"),option("Power circuits","page","circuits"),
            option("Lighting groups","page","light_groups"),option("Back to EMMA","page",nil)}
    elseif p=="building_security" then
        local security=window.serviceSecurity
        local result={}
        if security and security.puzzle then
            for _,word in ipairs(security.puzzle.words) do
                if not security.puzzle.removed[word] then
                    local likeness=security.puzzle.guessed[word]
                    result[#result+1]=option(word..(likeness~=nil and " ("..likeness.."/6)" or ""),"security_guess",word)
                end
            end
            for index,token in ipairs(SC.TerminalSystem.brackets(security)) do
                if not security.puzzle.used[index] then result[#result+1]=option(token,"security_guess",token) end
            end
        end
        result[#result+1]=option("Use building key","security_guess","key")
        result[#result+1]=option("Back","page","services")
        return result
    elseif p=="equipment" then
        local rows=B().list(window.object)
        local result=paged(window,rows,function(row) return option(row.label..": "..B().status(row),"device",row.id) end,"services")
        table.insert(result,1,option("Rescan loaded equipment","rescan"))
        return result
    elseif p=="device" then
        local panel=B().panel(window.object,false)
        local row=panel and panel.devices[window.serviceDevice]
        if not row then return {option("Back","page","equipment")} end
        local result={}
        local actions=row.kind=="light" and {"on","off"} or row.kind=="generator" and {"start","stop","repair","refuel"}
            or row.kind=="cabinet" and {"unlock","lock"} or {"open","close","unlock","lock"}
        for _,action in ipairs(actions) do result[#result+1]=option(action:gsub("^%l",string.upper),"propose",{operation="device",verb=action,id=row.id}) end
        if row.kind=="generator" then
            result[#result+1]=option("Fit remote-start battery (Electrical 4)","choose","starter")
            result[#result+1]=option("Remove starter battery","propose",{operation="remove_starter",id=row.id})
        elseif row.kind=="cabinet" then result[#result+1]=option("Fit lock relay","propose",{operation="fit",kind="relay",id=row.id})
        elseif row.kind=="light" then
            result[#result+1]=option("Fit lighting relay","propose",{operation="fit",kind="relay",id=row.id})
            result[#result+1]=option("Fit motion sensor","propose",{operation="fit",kind="motion",id=row.id})
        elseif row.kind=="door" or row.kind=="shutter" then
            result[#result+1]=option("Fit lock relay","propose",{operation="fit",kind="relay",id=row.id})
            result[#result+1]=option("Fit motor controller","propose",{operation="fit",kind="motor",id=row.id})
            result[#result+1]=option("Fit door contact","propose",{operation="fit",kind="contact",id=row.id})
            result[#result+1]=option("Use as return garage","propose",{operation="garage",id=row.id})
        end
        result[#result+1]=option("Back","page","equipment")
        return result
    elseif p=="light_groups" then
        local groups,seen={"All lights"},{["All lights"]=true}
        for _,row in ipairs(B().list(window.object)) do if row.kind=="light" and row.group and not seen[row.group] then groups[#groups+1]=row.group seen[row.group]=true end end
        return paged(window,groups,function(name) return option(name,"light_group",name) end,"services")
    elseif p=="light_group" then
        return {option("Turn group on","propose",{operation="light_group",group=window.serviceGroup,on=true}),
            option("Turn group off","propose",{operation="light_group",group=window.serviceGroup,on=false}),option("Back","page","light_groups")}
    elseif p=="hardware" then
        if SC.GridControl and SC.GridControl.pinned(window.object) then
            return {option("Supply and radio status","hardware_status"),option("Back to EMMA","page",nil)}
        end
        return {option("Mount walkie-talkie (Electrical 2)","choose","radio"),option("Install battery backup (Electrical 4)","choose","ups"),
            option("Remove mounted radio","propose",{operation="remove",kind="radio"}),option("Remove backup battery","propose",{operation="remove",kind="ups"}),
            option("Supply and radio status","hardware_status"),option("Back to EMMA","page",nil)}
    elseif p=="components" then
        return paged(window,candidates(window,window.componentKind),function(item)
            local condition=math.floor((tonumber(U().call(item,"getCondition")) or 0)/math.max(1,tonumber(U().call(item,"getConditionMax")) or 100)*100)
            local data=U().call(item,"getDeviceData")
            local charge=data and tonumber(U().call(data,"getPower")) or U().charge(item)
            local detail="condition "..condition.."%"..(charge and "; battery "..math.floor(charge*100).."%" or "")
            return option(tostring(U().call(item,"getDisplayName") or U().call(item,"getFullType")).." ("..detail..")",
                "propose",{operation=window.componentKind=="starter" and "starter" or "mount",kind=window.componentKind,item=item,id=window.serviceDevice})
        end,window.componentKind=="starter" and "device" or "hardware")
    elseif p=="security_panel" then
        local result={}
        for _,action in ipairs({"arm","disarm","silence","siren","announce","install_speaker"}) do
            result[#result+1]=option(action:gsub("_"," "):gsub("^%l",string.upper),"propose",{operation="device",id="panel",verb=action})
        end
        result[#result+1]=option("Back","page","services") return result
    elseif p=="routines" then
        local result={option("Routine status","routine_status")}
        for _,kind in ipairs({"return","night","lockdown","stop"}) do
            result[#result+1]=option(kind=="stop" and "Disable routines" or "Enable "..kind.." routine","propose",{operation="device",id="panel",verb="routine_"..kind})
        end
        result[#result+1]=option("Back","page","services") return result
    elseif p=="circuits" then
        local rows=SC.BuildingCircuits.list(window.object)
        return paged(window,rows,function(row) return option(tostring(row.label)..": "..(row.on and "On" or "Off"),"propose",{operation="circuit",id=row.id,on=not row.on}) end,"services")
    elseif p=="station" then
        return {option("Plan expedition","page","expedition_plan"),option("Request progress report","propose",{operation="radio",command="progress_report",payload="status"}),
            option("Recall expedition","propose",{operation="radio",command="return_now",payload="now"}),option("Route decisions","page","radio_decisions"),
            option("Radio channel / status","radio_status"),option("Book Marcus taxi","propose",{operation="taxi",verb="book"}),
            option("Taxi status","taxi_status"),option("Cancel taxi booking","propose",{operation="taxi",verb="cancel"}),option("Back to EMMA","page",nil)}
    elseif p=="radio_decisions" then
        return {option("Hold position","propose",{operation="radio",command="expedition_decision",payload="hold_position"}),
            option("Try another route","propose",{operation="radio",command="expedition_decision",payload="push_on"}),
            option("Return home","propose",{operation="radio",command="expedition_decision",payload="return"}),
            option("Walk","propose",{operation="radio",command="set_move_mode",payload="walk"}),
            option("Sneak","propose",{operation="radio",command="set_move_mode",payload="sneak"}),option("Back","page","station")}
    elseif p=="expedition_plan" then
        local draft=window.stationDraft or {kind="wood",travelMode="road",quantity=12,category="food",hours=4,crew={}}
        window.stationDraft=draft
        return {option("Mission: "..draft.kind,"cycle","kind"),
            option("Choose destination on map","map_pick"),
            option(draft.mapTarget and ("Destination: "..draft.mapTarget.label) or "Destination","places"),
            option("Travel: "..(draft.travelMode=="drive" and "Drive" or "Walk"),"cycle","travelMode"),
            option("Crew and leader","page","station_crew"),option("Requested: "..tostring(draft.quantity),"cycle","quantity"),
            option("Supplies: "..draft.category,"cycle","category"),
            option("Return after "..draft.hours.." game hours","cycle","hours"),option("Review mission","review"),option("Back","page","station")}
    elseif p=="station_crew" then
        return paged(window,crew(window),function(record)
            local chosen=false for _,id in ipairs(window.stationDraft.crew) do if id==record.id then chosen=true end end
            return option((chosen and "Selected: " or "Add: ")..tostring(record.name or SC.GameplayUtil.nameOf(record.actor)),"crew",record.id)
        end,"expedition_plan")
    elseif p=="station_places" then
        local result=paged(window,window.stationPlaces or {},function(row) return option(row.label,"place",row.id) end,"expedition_plan")
        if (window.stationPlacePage or 1)>1 then table.insert(result,#result,option("Previous locations","places_more",-1)) end
        if (window.stationPlacePage or 1)*32<(window.stationPlacesTotal or 0) then table.insert(result,#result,option("More locations","places_more",1)) end
        return result
    elseif p=="station_review" then return {option("Launch reviewed expedition","propose",{operation="launch"}),option("Back to plan","page","expedition_plan")} end
end
local function rowsForDraft(window)
    local result={}
    for _,id in ipairs(window.stationDraft and window.stationDraft.crew or {}) do
        local record=SC.Registry.byId(id)
        local state=SC.Commands.describe(id,window.player)
        if not record or not record.actor or not state or not state.recruited or state.available==false or state.alive==false
            or U().call(record.actor,"isDead")==true then return nil,"Crew changed; review again." end
        result[#result+1]=record
    end
    if #result<1 or #result>4 then return nil,"Choose one to four companions. The first selected companion leads." end
    return result
end
local function tripOptions(draft)
    return {mapTarget=draft.mapTarget,turnHomeAfterHours=draft.hours,doctrine="close_defense",travelMode=draft.travelMode,restockBaseDuty=true,
        request=draft.kind=="wood" and (draft.quantity=="full" and {mode="full"} or {mode="count",quantity=draft.quantity})
            or (draft.kind=="search" or draft.kind=="fish") and {category=draft.kind=="fish" and "fish" or draft.category,quantity=draft.quantity} or nil}
end
function S.review(window)
    local camp=SC.BaseLife and SC.BaseLife.active()
    if not camp or not SC.BaseLife.isInside(window.object) then return false,"Plan and launch expeditions from a camp computer." end
    local endpoint,radioReason=SC.RadioEndpoints.station(window.player,window.object)
    if not endpoint then return false,radioReason end
    local records,reason=rowsForDraft(window)
    if not records then return false,reason end
    local draft=window.stationDraft local expedition=SC.ExpeditionPrototype
    if not expedition or expedition.current() then return false,"Finish the current expedition first." end
    local preview
    if draft.mapTarget then
        local target
        target,reason=SC.ExpeditionTargets.validate(draft.mapTarget,
            SC.ExpeditionTargets.context(records[1].actor,draft.travelMode))
        if not target or target.kind~=draft.kind then return false,SC.ExpeditionMap.reason(reason or "map_target_changed") end
        preview,reason=expedition.previewMapTarget(records,target,tripOptions(draft))
    elseif draft.kind=="wood" then preview,reason=expedition.previewWoodCollection(records,tripOptions(draft))
    else
        if not draft.placeId then return false,"Choose a destination first." end
        local x,y=SC.GameplayUtil.position(records[1].actor)
        if x==nil or y==nil then return false,"The selected leader is not currently loaded. Review again when they are nearby." end
        local place
        if draft.kind=="fish" then place,reason=SC.Fishing.bankById(records[1].actor,draft.placeId,SC.Config.get("expeditionFishingRadius") or 1000)
        else place,reason=SC.ExpeditionPlaces.targetableById(math.floor(x),math.floor(y),SC.Config.get("expeditionDestinationRadius") or 200,draft.placeId) end
        if not place then return false,U().error(reason or "Destination unavailable.") end
        local fn=draft.kind=="fish" and expedition.previewAtFishingBank or expedition.previewAtPlace
        if draft.travelMode=="drive" then preview,reason=expedition.previewDrive(records,place,draft.kind=="fish")
        else preview,reason=fn(records[1],place,draft.travelMode) end
    end
    if not preview then return false,U().error(reason) end
    window.stationReviewed={kind=draft.kind,travelMode=draft.travelMode,quantity=draft.quantity,category=draft.category,hours=draft.hours,placeId=draft.placeId,crew=table.concat(draft.crew,"|")}
    window.stationReviewed.mapFingerprint=SC.ExpeditionTargets and SC.ExpeditionTargets.fingerprint(draft.mapTarget) or "none"
    window.stationReviewed.carSqlId=preview.carSqlId
    local lines={"Mission: "..draft.kind.."; "..(draft.travelMode=="drive" and "driving" or "walking").."; target "..tostring(draft.quantity)..".",
        "Crew: "..#records..". Leader: "..tostring(records[1].name or SC.GameplayUtil.nameOf(records[1].actor)),"Return limit: "..draft.hours.." game hours. Close-defence combat policy; restock and resume camp duty."}
    if draft.mapTarget then lines[#lines+1]="Destination: "..draft.mapTarget.label..". Travel counts toward the turn-home time; equipment preparation pauses departure." end
    if draft.kind=="wood" then lines[#lines+1]="Raw logs only. One trip; full load is limited to 256 verified log receipts. Storage delivery remains required." end
    if preview.carSqlId then lines[#lines+1]="Car: "..tostring(preview.carName)..". Fuel "..tostring(preview.fuel).."; planned reserve "..tostring(preview.fuelRequired).."." end
    return true,lines
end
function S.prepare(window,proposal)
    local request=proposal.request
    if type(request)~="table" then return nil,"Request unavailable." end
    local saved={}
    for _,key in ipairs({"operation","kind","item","id","verb","on","command","payload","group"}) do saved[key]=request[key] end
    if saved.operation=="circuit" then
        local circuit,prompt=SC.BuildingCircuits.prepare(window.object,saved.id,saved.on,window.player)
        if not circuit then return nil,prompt end
        saved.circuit=circuit return saved,prompt
    end
    if saved.operation=="light_group" then
        saved.devices={}
        local names={}
        for _,row in ipairs(B().list(window.object)) do
            if row.kind=="light" and (saved.group=="All lights" or row.group==saved.group) then
                local ticket,reason=B().prepare(window.object,saved.on and "on" or "off",row.id,window.player)
                if not ticket then return nil,reason end
                saved.devices[#saved.devices+1]=ticket names[#names+1]=row.label
            end
        end
        if #saved.devices==0 then return nil,"This group has no connected lights." end
        return saved,"Switch "..table.concat(names,", ")..(saved.on and " on" or " off").."? [Y/N]"
    end
    if saved.operation=="device" then
        local ticket,prompt=B().prepare(window.object,saved.verb,saved.id,window.player)
        if not ticket then return nil,prompt end
        saved.deviceTicket=ticket
        if saved.verb and saved.verb:sub(1,8)=="routine_" then
            local panel=B().panel(window.object,false) local names={}
            for _,row in pairs(panel.devices) do names[#names+1]=row.label end
            table.sort(names)
            prompt="Authorize "..saved.verb:gsub("_"," ").." for: "..table.concat(names,", ").."? Door obstructions pause steps. [Y/N]"
        end
        return saved,prompt
    end
    if saved.operation=="radio" or saved.operation=="taxi" or saved.operation=="launch" then
        local endpoint,reason=SC.RadioEndpoints.station(window.player,window.object)
        if not endpoint then return nil,reason end
        saved.endpoint=endpoint
        if saved.operation=="radio" then
            local trip=SC.ExpeditionPrototype and SC.ExpeditionPrototype.current()
            if not trip then return nil,"No active expedition." end
            saved.missionId=trip.radioSession
        elseif saved.operation=="taxi" then
            local booking=SC.TaxiBooking.current()
            saved.bookingGeneration=booking and booking.generation
        end
    end
    if saved.operation=="radio" then
        local trip=SC.ExpeditionPrototype.current()
        local who=trip.leader.name or "the expedition leader"
        local instruction=saved.command=="progress_report" and "Request a fresh report from "..who
            or saved.command=="return_now" and "Recall "..who.." and the expedition now"
            or "Radio "..who..": "..tostring(saved.payload):gsub("_"," ")
        return saved,instruction.."? The station and crew must exchange native radio transmissions. [Y/N]"
    elseif saved.operation=="taxi" then
        local x,y,z=U().position(window.object)
        return saved,saved.verb=="book" and "Book Marcus at this station ("..x..", "..y..", floor "..z..")? [Y/N]" or "Cancel the current Marcus booking? [Y/N]"
    elseif saved.operation=="connect" then
        return saved,"Connect this PC to local controls? Electrical 2, screwdriver, 1 wire and 2 scrap; stand beside the PC. [Y/N]"
    elseif saved.operation=="launch" then
        return saved,"Launch the reviewed "..tostring(window.stationDraft and window.stationDraft.kind).." expedition with the selected crew and route? [Y/N]"
    elseif saved.operation=="mount" then
        return saved,saved.kind=="radio" and "Mount this exact two-way radio? Electrical 2, screwdriver, 1 wire and 2 scrap. [Y/N]"
            or "Install this exact car battery as the PC backup? Electrical 4, screwdriver, 1 wire and 4 scrap. [Y/N]"
    end
    return saved,(saved.operation=="launch" and "Launch this reviewed mission" or saved.operation:gsub("_"," ").." "..tostring(saved.kind or saved.verb or "")).."? [Y/N]"
end

SCComputerInstallAction=ISBaseTimedAction:derive("SCComputerInstallAction")
local function installationAccess(player,object)
    local from,to=U().square(player),U().square(object)
    if not from or not to then return false end
    if from==to then return true end
    if (U().kind(object,"IsoDoor") or U().call(object,"isDoor")==true)
        and U().call(object,"getOppositeSquare")==from then return true end
    return U().call(from,"canReachTo",to)==true
end
function SCComputerInstallAction:isValid()
    return not self.done and U().call(self.character,"isDead")~=true and U().present(self.object) and U().near(self.character,self.object,3)
        and installationAccess(self.character,self.object)
end
function SCComputerInstallAction:start()
    self:setActionAnim("Loot") self.character:SetVariable("LootPosition","Mid") self.character:faceThisObject(self.object)
end
function SCComputerInstallAction:update() self.character:faceThisObject(self.object) end
function SCComputerInstallAction:complete()
    if not self:isValid() then return false end
    self.done=true
    local called,okay,reason=pcall(self.effect)
    self.result=called and okay==true
    self.lastReason=called and reason or tostring(okay)
    if not self.result then
        print("[SurvivorCompanion][computer-install] failed: "..tostring(self.lastReason))
    end
    U().call(self.character,"Say",called and U().error(reason or (okay and "Installation completed." or "Installation failed.")) or "Installation stopped; inspect the equipment.")
    return self.result
end
function SCComputerInstallAction:perform()
    if not self.done then self:complete() end
    ISBaseTimedAction.perform(self)
end
function S.install(player,object,effect)
    if not U().near(player,object,3) or not installationAccess(player,object) then
        if not luautils or not luautils.walkAdj or not luautils.walkAdj(player,U().square(object)) then return false,"Cannot reach the equipment." end
    end
    if not ISTimedActionQueue or not ISTimedActionQueue.add then return false,"Native installation actions unavailable." end
    local action=ISBaseTimedAction.new(SCComputerInstallAction,player)
    action.object,action.effect,action.maxTime=object,effect,180
    action.stopOnWalk,action.stopOnRun=true,true
    ISTimedActionQueue.add(action)
    return true,"Installation queued. Components are checked and consumed at completion.",action
end
function S.execute(window,request)
    local pc,player=window.object,window.player
    local operation=request.operation
    if operation=="device" then
        if request.verb=="install_speaker" then return S.install(player,pc,function() return B().execute(request.deviceTicket) end) end
        return B().execute(request.deviceTicket)
    elseif operation=="light_group" then
        local completed,failures=0,{}
        for _,ticket in ipairs(request.devices) do
            local okay,reason=B().execute(ticket)
            if okay then completed=completed+1 else failures[#failures+1]=U().error(reason) end
        end
        return #failures==0,completed.." of "..#request.devices.." lights updated."..(#failures>0 and " "..failures[1] or "")
    elseif operation=="connect" then return S.install(player,pc,function() return B().connect(player,pc) end)
    elseif operation=="mount" then return S.install(player,pc,function() return SC.TerminalHardware.install(player,pc,request.kind,request.item) end)
    elseif operation=="remove" then return S.install(player,pc,function() return SC.TerminalHardware.remove(player,pc,request.kind) end)
    elseif operation=="fit" or operation=="starter" or operation=="remove_starter" then
        local panel=B().panel(pc,false) local row=panel and panel.devices[request.id]
        local target=row and B().resolve(row)
        if not target then return false,"Target changed." end
        return S.install(player,target,function()
            if not B().connected(pc,panel) then return false,"Computer disconnected." end
            if operation=="starter" then return SC.GeneratorServices.fit(player,target,row,request.item) end
            if operation=="remove_starter" then return SC.GeneratorServices.removeStarter(player,target,row) end
            return B().install(player,pc,row.id,request.kind)
        end)
    elseif operation=="garage" then
        local panel=B().panel(pc,false) local row=panel and panel.devices[request.id]
        if not panel or panel.security.locked or not B().connected(pc,panel) or not row or row.kind~="shutter" then return false,"Choose an authorized loading shutter." end
        panel.returnGarageId=row.id return true,"Return garage assigned: "..row.label
    elseif operation=="radio" then
        local trip=SC.ExpeditionPrototype.current()
        if not trip or trip.radioSession~=request.missionId then return false,"The expedition changed. Ask again." end
        local okay,reason=SC.ExpeditionPrototype.sendRadioOrder(player,request.command,request.payload,request.endpoint)
        if okay and SC.TerminalRadio then SC.TerminalRadio.transmitted(window.object) end
        if okay and request.command=="progress_report" then
            local report=trip.lastProgressReport
            if report then
                if SC.TerminalRadio then SC.TerminalRadio.acknowledged(window.object,trip.radioSession,report) end
                local counts=report.kind=="scout" and "Scouting" or tostring(report.collected).." collected of "..tostring(report.requested).." requested"
                if report.carried then counts=counts.."; "..report.carried.." carried; "..tostring(report.stored or 0).." stored" end
                return true,"Radio report: "..counts.."; "..tostring(report.phase or "working")..". Last heard at "..tostring(report.at or U().hours()).." game hours."
            end
        end
        return okay,reason
    elseif operation=="taxi" then
        if request.verb=="book" then
            local okay,reason=SC.TaxiService.request(player,request.endpoint)
            if okay and reason~="already_booked" then U().call(U().call(player,"getEmitter"),"playSound","LFTaxiRadioCall") end
            return okay,reason
        end
        local booking=SC.TaxiBooking.current()
        if not booking or booking.generation~=request.bookingGeneration then return false,"The taxi booking changed. Ask again." end
        return SC.TaxiService.cancel(player,request.endpoint)
    elseif operation=="circuit" then
        local panel=B().panel(pc,false)
        if not panel or panel.security.locked or not B().connected(pc,panel) then return false,"Authorize building controls first." end
        return SC.BuildingCircuits.execute(pc,request.circuit)
    elseif operation=="launch" then
        local sourceOkay,sourceReason=SC.RadioEndpoints.validate(player,request.endpoint)
        if not sourceOkay then return false,sourceReason end
        local old=window.stationReviewed local draft=window.stationDraft
        if not old or not draft or old.crew~=table.concat(draft.crew,"|") then return false,"Review the selected crew first." end
        local targetFingerprint=SC.ExpeditionTargets and SC.ExpeditionTargets.fingerprint(draft.mapTarget) or "none"
        if targetFingerprint~=(old.mapFingerprint or "none") then return false,"Destination changed. Review this mission again." end
        for _,key in ipairs({"kind","travelMode","quantity","category","hours","placeId"}) do if old[key]~=draft[key] then return false,"Mission changed. Review it again." end end
        local okay,reason=S.review(window)
        if not okay then return false,reason end
        if window.stationReviewed.carSqlId~=old.carSqlId then window.stationReviewed=nil return false,"The available car changed. Review this mission again." end
        local records=rowsForDraft(window) local options=tripOptions(draft)
        options.vehicleSqlId=old.carSqlId
        window.stationReviewed=nil
        local accepted,result
        if draft.kind=="wood" then accepted,result=SC.ExpeditionPrototype.startWoodCollection(records,options)
        elseif draft.kind=="fish" then accepted,result=SC.ExpeditionPrototype.startAtFishingBank(records,draft.placeId,options)
        else accepted,result=SC.ExpeditionPrototype.startAtPlace(records,draft.placeId,draft.kind,options) end
        return accepted,accepted and "Expedition launched. Use the station to request progress or recall the crew." or result
    end
    return false,"Unsupported request."
end
local function propose(window,request)
    window:cancelRequest()
    local ticket,prompt=SC.TerminalActions.prepare(window,{kind="control",request=request})
    window.requestTicket=ticket show(window,prompt)
end
local function security(window,word)
    local panel,reason=B().panel(window.object,false)
    if not panel or not B().connected(window.object,panel) then show(window,reason or "Connect this computer first.") return end
    if not panel.security.locked then show(window,"Building access is authorized.") page(window,"services") return end
    SC.TerminalSystem.ensurePuzzle(panel.security,U().skill(window.player))
    local lines={}
    if word then
        if string.lower(word)=="key" then
            local okay,message=B().authorizeKey(window.object,window.player)
            show(window,message) if okay then page(window,"services") end return
        end
        local okay,code,likeness=B().security(window.object,word,U().skill(window.player))
        if okay then
            if not panel.security.xpAwarded then panel.security.xpAwarded=true U().call(U().call(window.player,"getXp"),"AddXP",Perks.Electricity,SC.TerminalSystem.XP) end
            show(window,"Building security authorized.") page(window,"services") return
        end
        lines[#lines+1]=code=="wrong" and string.upper(word)..": "..likeness.."/6 positions match." or U().error(code)
    end
    window.menuPage="building_security"
    window.serviceSecurity=panel.security
    local p=panel.security.puzzle
    lines[#lines+1]="BUILDING ACCESS - attempts "..p.tries.."/"..p.maximum..". Type a word, bracket group, or KEY. Back leaves recovery."
    for _,row in ipairs(SC.TerminalSystem.board(panel.security,48)) do lines[#lines+1]=row.text end
    window:setFocusMode("chat") show(window,lines)
end
function S.input(window,raw,chosen)
    if window.system.locked then return false end
    local text=string.lower(raw):match("^%s*(.-)%s*$")
    if window.menuPage=="building_security" then
        if text=="back" or text=="menu" or chosen and chosen.serviceAction=="page" then page(window,"services")
        elseif chosen and chosen.serviceAction=="menu_next" then window.serviceMenuPage=(window.serviceMenuPage or 0)+1
        elseif chosen and chosen.serviceAction=="menu_previous" then window.serviceMenuPage=math.max(0,(window.serviceMenuPage or 0)-1)
        else security(window,chosen and chosen.serviceValue or raw) end
        return true
    end
    local action,value=chosen and chosen.serviceAction,chosen and chosen.serviceValue
    if not action then
        local names={ ["building services"]="services",["building controls"]="services",["hardware"]="hardware",["expedition station"]="station" }
        if names[text] then page(window,names[text]) show(window,names[text]=="hardware" and SC.TerminalHardware.describe(window.object) or "Local services ready. Choose a numbered menu item.") window:setFocusMode("menu") return true end
        if text=="hack building" then security(window) return true end
        local named={ ["call marcus"]={operation="taxi",verb="book"},["book marcus"]={operation="taxi",verb="book"},
            ["recall expedition"]={operation="radio",command="return_now",payload="now"},
            ["expedition report"]={operation="radio",command="progress_report",payload="status"},
            ["silence alarm"]={operation="device",id="panel",verb="silence"},["sound alarm"]={operation="device",id="panel",verb="siren"},
            ["arm alarms"]={operation="device",id="panel",verb="arm"},["disarm alarms"]={operation="device",id="panel",verb="disarm"}}
        if named[text] then propose(window,named[text]) return true end
        local channel=text:match("^channel%s+(%d+)$")
        if channel then
            local endpoint,reason=SC.RadioEndpoints.station(window.player,window.object)
            local number=tonumber(channel)
            if endpoint and number>=U().call(endpoint.data,"getMinChannelRange") and number<=U().call(endpoint.data,"getMaxChannelRange") then
                U().call(endpoint.data,"setChannel",number) SC.TerminalHardware.flush(window.object) show(window,"Channel set to "..number..".")
            else show(window,reason or "Frequency outside the radio's tuning range.") end
            return true
        end
        if window.menuPage=="device" and text:sub(1,5)=="name " then local okay,reason=B().rename(window.object,window.serviceDevice,raw:sub(6)) show(window,reason) return true end
        if window.menuPage=="device" and text:sub(1,6)=="group " then local okay,reason=B().group(window.object,window.serviceDevice,raw:sub(7)) show(window,reason) return true end
        local verb,name=text:match("^(open)%s+(.+)$")
        if not verb then verb,name=text:match("^(close)%s+(.+)$") end
        if not verb then verb,name=text:match("^(unlock)%s+(.+)$") end
        if not verb then verb,name=text:match("^(lock)%s+(.+)$") end
        if not verb then verb,name=text:match("^turn%s+(on)%s+(.+)$") end
        if not verb then verb,name=text:match("^turn%s+(off)%s+(.+)$") end
        if not verb then verb,name=text:match("^(start)%s+(.+)$") end
        if not verb then verb,name=text:match("^(stop)%s+(.+)$") end
        if not verb then verb,name=text:match("^(repair)%s+(.+)$") end
        if verb then
            local matches={} for _,row in ipairs(B().list(window.object)) do if string.lower(row.label):find(name,1,true) then matches[#matches+1]=row end end
            if #matches==1 then propose(window,{operation="device",id=matches[1].id,verb=verb}) else show(window,#matches==0 and "No matching connected device." or "Several devices match. Choose one from Equipment.") end
            return true
        end
        return false
    end
    if action=="page" then page(window,value)
        if value=="equipment" then B().discover(window.object,true) local _,reason=B().list(window.object) show(window,reason or "Choose equipment. On its page, type name followed by a readable label to rename it.")
        elseif value=="circuits" then show(window,SC.BuildingCircuits.status()) end
        window:setFocusMode("menu")
    elseif action=="menu_next" or action=="menu_previous" then window.serviceMenuPage=math.max(0,(window.serviceMenuPage or 0)+(action=="menu_next" and 1 or -1))
    elseif action=="next" or action=="previous" then window.servicePage=math.max(0,(window.servicePage or 0)+(action=="next" and 1 or -1))
    elseif action=="device" then window.serviceDevice=value page(window,"device")
    elseif action=="light_group" then window.serviceGroup=value page(window,"light_group")
    elseif action=="choose" then window.componentKind=value page(window,"components")
    elseif action=="propose" then propose(window,value)
    elseif action=="security" then security(window)
    elseif action=="history" then
        local panel=B().panel(window.object,false) local lines={"Local security history:"}
        if panel and B().connected(window.object,panel) and not panel.security.locked then
            for i=math.max(1,#panel.history-31),#panel.history do local row=panel.history[i] lines[#lines+1]=string.format("%.2f: %s",row.at,row.text) end
        else lines[#lines+1]="Authorize building access first." end
        show(window,lines)
    elseif action=="hardware_status" then show(window,SC.TerminalHardware.describe(window.object))
    elseif action=="rescan" then local okay,reason=B().discover(window.object,true) show(window,okay and "Equipment rescan queued. Discovery reads loaded tiles in bounded slices." or reason)
    elseif action=="routine_status" then
        local panel=B().panel(window.object,false) local lines={}
        for kind,routine in pairs(panel and panel.routines or {}) do
            lines[#lines+1]=kind..": "..(routine.suspended and "suspended - reconnect the authorizing computer" or routine.blocker or routine.phase or "enabled")
        end
        table.sort(lines) show(window,#lines>0 and lines or {"No automatic routines are enabled."})
    elseif action=="radio_status" then
        local endpoint,reason=SC.RadioEndpoints.station(window.player,window.object)
        if endpoint then show(window,"Channel "..U().call(endpoint.data,"getChannel").."; native range "..U().call(endpoint.data,"getTransmitRange").." tiles. Type channel followed by a frequency to retune. Remote replies require acknowledgement.") else show(window,reason) end
    elseif action=="taxi_status" then
        local endpoint,reason=SC.RadioEndpoints.station(window.player,window.object)
        if not endpoint then show(window,reason) else local okay,status=SC.TaxiBooking.status(window.player,endpoint) show(window,U().error(status)) end
    elseif action=="crew" then
        local found for i,id in ipairs(window.stationDraft.crew) do if id==value then table.remove(window.stationDraft.crew,i) found=true break end end
        if not found then if #window.stationDraft.crew>=4 then show(window,"Choose at most four companions.") else window.stationDraft.crew[#window.stationDraft.crew+1]=value end end
        window.stationReviewed=nil
    elseif action=="cycle" then
        local sets={kind={"wood","search","scout","fish"},travelMode={"road","drive"},quantity={1,2,4,8,12,24,"full"},category={"useful","food","water","medicine","tools","construction","ammunition","clothing"},hours={1,2,4,8,12,24}}
        local list=sets[value] local draft=window.stationDraft local index=1
        if value=="quantity" and draft.kind~="wood" then list={1,2,4,8} end
        for i,row in ipairs(list) do if row==draft[value] then index=i%#list+1 break end end
        draft[value]=list[index] window.stationReviewed=nil
        if value=="kind" then
            draft.placeId=nil
            if draft.mapTarget and (draft.mapTarget.kind=="scout" or draft.mapTarget.kind=="search")
                and (draft.kind=="scout" or draft.kind=="search") then
                draft.mapTarget.kind=draft.kind
                draft.placeId=draft.mapTarget.id
            end
            if draft.kind~="wood" and (draft.quantity=="full" or draft.quantity>8) then draft.quantity=4 end
        end
    elseif action=="map_pick" then
        local draft=window.stationDraft
        local function context()
            local records=rowsForDraft(window)
            return SC.ExpeditionTargets.context(records and records[1] and records[1].actor,draft.travelMode)
        end
        local opened,why=SC.ExpeditionMap.begin(window,draft,context,function(target)
            draft.mapTarget=SC.ExpeditionTargets.copy(target)
            draft.placeId=target.id
            window.stationReviewed=nil
            local okay,lines=S.review(window)
            page(window,okay and "station_review" or "expedition_plan")
            show(window,okay and lines or SC.ExpeditionMap.reason(lines))
        end,function() window:setFocusMode("menu") end,function()
            local terminal=SC.Terminal
            local good=not window.closed and window.stationDraft==draft and terminal
                and terminal.window==window and terminal.present(window.object)
                and terminal.near(window.player,window.object) and terminal.powered(window.object)
            if not good and not window.closed then window:close() end
            return good
        end)
        if not opened then show(window,SC.ExpeditionMap.reason(why)) end
    elseif action=="places" or action=="places_more" then
        window.stationPlacePage=action=="places" and 1 or math.max(1,(window.stationPlacePage or 1)+(tonumber(value) or 1))
        if window.stationDraft.kind=="wood" then
            window.stationDraft.mapTarget=nil window.stationDraft.placeId=nil window.stationReviewed=nil
            show(window,"Automatic woodland discovery selected. Woodland is selected during review.")
        else
            local records,reason=rowsForDraft(window)
            if not records then show(window,reason) else
                local fn=window.stationDraft.kind=="fish" and SC.ExpeditionPrototype.fishingBankCandidates or SC.ExpeditionPrototype.placeCandidates
                local rows,why,total=fn(records[1].id,window.stationPlacePage,false)
                window.stationPlaces,window.stationPlacesTotal=rows or {},total or 0
                if rows then page(window,"station_places") else show(window,U().error(why)) end
            end
        end
    elseif action=="place" then
        window.stationDraft.mapTarget=nil
        window.stationDraft.placeId=value window.stationReviewed=nil page(window,"expedition_plan")
    elseif action=="review" then
        local okay,lines=S.review(window) show(window,lines)
        if okay then page(window,"station_review") window:setFocusMode("chat") end
    end
    return true
end
-- Page every service menu by its measured row budget. The same mechanism
-- covers equipment, hardware choices and commands, without shrinking text.
local rawMenu=S.menu
function S.menu(window)
    local options=rawMenu(window)
    if not options or #options<2 or not window.layout then return options end
    local back=options[#options]
    local isBack=back.serviceAction=="page" and back.label:sub(1,4)=="Back"
    local side=window:sidebarWidth()
    local width=side>0 and side-window.layout.pad*1.5 or window.layout.right-window.layout.left
    local columns=math.max(8,math.floor(width/window.charWidth))
    local gap=math.max(4,math.floor(window.layout.pad/2))
    local function cost(row)
        return math.min(2,#SC.Terminal.wrap("[1] "..row.label,columns))*window.rowHeight+gap
    end
    local available=window:viewBottom()-window:viewTop()
    local total=0 for _,row in ipairs(options) do total=total+cost(row) end
    if total<=available and #options<=9 then return options end
    local groups,index={},1
    local count=#options-(isBack and 1 or 0)
    while index<=count do
        local previous=#groups>0
        local navigation=(isBack and cost(back) or 0)+(previous and window.rowHeight+gap or 0)
        local remaining=0 for i=index,count do remaining=remaining+cost(options[i]) end
        local last=remaining<=available-navigation and count-index+1<=9-(isBack and 1 or 0)-(previous and 1 or 0)
        local limit=available-navigation-(last and 0 or window.rowHeight+gap)
        local group,used={},0
        repeat
            local height=cost(options[index])
            if #group>0 and (used+height>limit or #group>=6) then break end
            group[#group+1]=options[index] used=used+height index=index+1
        until index>count
        groups[#groups+1]=group
    end
    local index=math.max(1,math.min(#groups,(window.serviceMenuPage or 0)+1))
    window.serviceMenuPage=index-1
    local result={}
    for _,row in ipairs(groups[index] or {}) do result[#result+1]=row end
    if index>1 then result[#result+1]=option("Previous","menu_previous") end
    if index<#groups then result[#result+1]=option("More","menu_next") end
    if isBack then result[#result+1]=option("Back","page",back.serviceValue) end
    return result
end
function S.context(context,player,computer)
    if SC.GridControl and SC.GridControl.pinned(computer) then return end
    if not U().near(player,computer,3) then return end
    if not U().hasTool(player,"Base.Screwdriver") then return end
    local offered=0
    local hardware=SC.TerminalHardware.state(computer,false)
    for _,kind in ipairs({"radio","ups"}) do
        local level=kind=="radio" and 2 or 4
        if hardware and hardware[kind] then
            local selectedKind=kind
            context:addOption("Computer: remove "..(kind=="radio" and "mounted radio" or "backup battery"),player,
                function(actor) S.install(actor,computer,function() return SC.TerminalHardware.remove(actor,computer,selectedKind) end) end)
        elseif U().skill(player)>=level then
            for _,item in ipairs(candidates({player=player},kind)) do
                if offered>=12 then break end
                local selectedKind,selectedItem=kind,item
                context:addOption("Computer: install "..(kind=="radio" and "walkie-talkie" or "battery backup").." - "..tostring(U().call(item,"getDisplayName")),player,
                    function(actor) S.install(actor,computer,function() return SC.TerminalHardware.install(actor,computer,selectedKind,selectedItem) end) end)
                offered=offered+1
            end
        end
    end
end
return S
