-- SPDX-License-Identifier: MIT
-- Installed sensors and explicitly authorized routines, never world-wide AI.
SurvivorCompanion=SurvivorCompanion or {}
local SC=SurvivorCompanion
SC.BuildingSecurity=SC.BuildingSecurity or {}
local S=SC.BuildingSecurity
local sounds={}
local powerStates=setmetatable({}, {__mode="k"})
local sensorCursor=0
local function U() return SC.ControlUtil end
local function B() return SC.BuildingControls end
local function definition(computer)
    local _,_,_,def=B().panel(computer,false)
    return def
end
function S.stop(panel)
    local sound=sounds[panel.id]
    if sound then
        U().call(sound.emitter,"stopSound",sound.handle)
        if getWorld then U().call(getWorld(),"returnOwnershipOfEmitter",sound.emitter) end
        sounds[panel.id]=nil
    end
    panel.sounding=nil
end
function S.sound(panel,computer,announcement)
    if not panel.speaker then return false,"Fit a siren / PA amplifier first." end
    if type(panel.speaker)=="table" then
        local source
        for candidate,owner in pairs(B().computers) do
            local md=U().data(candidate)
            local os=md and md.movableData and md.movableData.LF_LarchOS
            if owner==panel and os and os.identity==panel.speaker.computer and B().connected(candidate,panel) then source=candidate break end
        end
        if not source then return false,"The fitted PA computer is disconnected or unloaded." end
        computer=source
    end
    if not U().nativePower(computer) then return false,"The speaker needs building power." end
    S.stop(panel)
    local x,y,z=U().position(computer)
    local world=type(getWorld)=="function" and getWorld()
    local emitter=U().call(world,"getFreeEmitter",x+0.5,y+0.5,z)
    if not emitter then return false,"Native sound emitter unavailable." end
    U().call(world,"takeOwnershipOfEmitter",emitter)
    local handle=U().call(emitter,announcement and "playSound" or "playSoundLooped",announcement and "LFBuildingAnnouncement" or "LFBuildingSiren")
    if not handle or handle==0 then U().call(world,"returnOwnershipOfEmitter",emitter) return false,"Speaker sound unavailable." end
    local hours=U().hours()
    sounds[panel.id]={emitter=emitter,handle=handle,computer=computer,announcement=announcement,untilMs=announcement and U().now()+30000}
    panel.sounding={untilHour=not announcement and hours and hours+0.25,announcement=announcement==true}
    B().log(panel,announcement and "Evacuation announcement started." or "Security siren started.")
    return true,"Speaker active. Nearby infected can hear it."
end
function S.operate(panel,computer,action,player)
    local def=definition(computer)
    if action=="arm" or action=="disarm" then
        if def then U().call(def,"setAlarmed",action=="arm") end
        panel.armed=action=="arm"
        return true,panel.armed and "Security armed." or "Security disarmed."
    elseif action=="silence" then
        S.stop(panel)
        if def then
            if not SCBridge or not SCBridge.silenceControlBuildingAlarm then return false,"Installed siren stopped. Stock alarm control is unavailable." end
            local manager=type(getAmbientStreamManager)=="function" and getAmbientStreamManager() or nil
            local okay,count=pcall(SCBridge.silenceControlBuildingAlarm,def,manager)
            if not okay or count<0 then return false,"Installed siren stopped. Stock alarm reset is unavailable on this game build." end
        end
        return true,"This building's alarm was silenced."
    elseif action=="siren" or action=="announce" then return S.sound(panel,computer,action=="announce")
    elseif action=="install_speaker" then
        if U().skill(player)<3 or not U().hasTool(player,"Base.Screwdriver") then return false,"Electrical 3 and a screwdriver are required." end
        if panel.speaker then return true,"A speaker is already fitted." end
        local okay,reason=U().consume(player,{["Base.Amplifier"]=1,["Base.ElectricWire"]=1,["Base.ElectronicsScrap"]=2})
        if okay then panel.speaker={computer=B().computerId(computer)} end
        return okay,okay and "Siren / PA amplifier fitted." or reason
    elseif action:sub(1,8)=="routine_" then return S.routine(panel,computer,action:sub(9),player) end
    return false,"Unsupported security command."
end
function S.routine(panel,computer,kind,player)
    if kind=="stop" then panel.routines={} return true,"Automatic routines disabled." end
    if kind~="return" and kind~="night" and kind~="lockdown" then return false,"Unknown routine." end
    if kind=="return" and not panel.returnGarageId then return false,"Choose the return garage from an equipment page first." end
    local lights,doors={},{}
    for id,row in pairs(panel.devices) do
        if row.kind=="light" then lights[#lights+1]=id end
        if row.kind=="door" or row.kind=="shutter" then doors[#doors+1]=id end
    end
    table.sort(lights) table.sort(doors)
    local x,y,z=U().position(computer)
    panel.routines[kind]={computer=B().computerId(computer),x=x,y=y,z=z,
        lights=lights,doors=doors,phase="ready",garage=panel.returnGarageId}
    B().log(panel,"Authorized routine: "..kind.." ("..#lights.." lights, "..#doors.." openings).")
    return true,"Routine enabled for the listed equipment. Obstructions pause door operations."
end
local function apply(panel,id,action,player)
    local row=panel.devices[id] local object=row and B().resolve(row)
    if not object then return false,"Equipment unavailable." end
    return B().operate(panel,row,object,action,player)
end
local function routineTick(panel,computer,kind,routine)
    local x,y,z=U().position(computer)
    local os=U().data(computer).movableData.LF_LarchOS
    if routine.suspended or routine.x~=x or routine.y~=y or routine.z~=z or not os or os.identity~=routine.computer then return end
    local player=type(getSpecificPlayer)=="function" and getSpecificPlayer(0)
    if kind=="night" then
        local hour=U().call(type(getGameTime)=="function" and getGameTime(),"getHour")
        if not hour then return end
        local desired=hour>=20 or hour<6
        routine.blocker=nil
        for _,id in ipairs(routine.lights) do
            local okay,reason=apply(panel,id,desired and "on" or "off",player)
            if not okay then routine.blocker=reason end
        end
    elseif kind=="lockdown" and routine.phase~="done" then
        local finished=true
        for _,id in ipairs(routine.doors) do
            local row=panel.devices[id]
            if row and B().status(row)=="Open" then
                local okay,reason=apply(panel,id,"close",player)
                if not okay then finished=false routine.blocker=reason end
            end
            if row and B().status(row)~="Open" then
                local okay,reason=apply(panel,id,"lock",player)
                if not okay then finished=false routine.blocker=reason end
            end
        end
        for _,id in ipairs(routine.lights) do
            local okay,reason=apply(panel,id,"on",player)
            if not okay then finished=false routine.blocker=reason end
        end
        if finished then routine.phase="done" panel.armed=true local def=definition(computer) if def then U().call(def,"setAlarmed",true) end end
    elseif kind=="return" then
        local trip=SC.ExpeditionPrototype and SC.ExpeditionPrototype.current()
        local garage=panel.devices[routine.garage]
        local door=garage and B().resolve(garage)
        if not door then routine.blocker="Return garage unavailable." return end
        if trip and trip.scout and trip.scout.phase=="inbound" and trip.leader and U().near(trip.leader.actor,door,20) then
            local tripId=trip.radioSession
            if routine.lastTrip~=tripId then
                for _,id in ipairs(routine.lights) do apply(panel,id,"on",player) end
                if B().status(garage)=="Locked" then apply(panel,routine.garage,"unlock",player) end
                local okay,reason=apply(panel,routine.garage,"open",player)
                if okay then
                    routine.lastTrip=tripId routine.phase="awaiting_clearance" routine.crew={}
                    for _,member in ipairs(trip.roster or {}) do routine.crew[#routine.crew+1]=member.id end
                    routine.vehicleId=trip.scout.vehicle and trip.scout.vehicle.sqlId
                else routine.blocker=reason end
            end
        elseif routine.phase=="awaiting_clearance" then
            local clear=true
            for _,id in ipairs(routine.crew or {}) do
                local member=SC.Registry.byId(id)
                if not member or not member.actor or U().call(member.actor,"isDead")~=true and SC.BaseLife.isInside(member.actor)~=true then clear=false end
            end
            if routine.vehicleId then
                local vehicle=SC.Vehicle and SC.Vehicle.loadedBySqlId(routine.vehicleId)
                local garageDef=definition(door) or U().call(U().call(door,"getOppositeSquare"),"getBuildingDef")
                local carDef=vehicle and U().call(U().square(vehicle),"getBuildingDef")
                if not vehicle or not garageDef or carDef~=garageDef or U().call(vehicle,"isEngineRunning")==true
                    or math.abs(tonumber(U().call(vehicle,"getCurrentSpeedKmHour")) or 0)>0.2 then
                    clear=false routine.blocker="Waiting for the returned car to be stopped inside the garage with its engine off."
                end
            end
            if clear then
                local okay,reason=apply(panel,routine.garage,"close",player)
                if okay then routine.phase="ready" routine.crew=nil else routine.blocker=reason end
            end
        end
    end
end
local function motion(row,object)
    if not LosUtil or not LosUtil.lineClear then return nil end
    local x,y,z=U().position(object)
    for dx=-2,2 do for dy=-2,2 do
        local square=SC.GameplayUtil.gridSquare(x+dx,y+dy,z)
        if square and #U().list(U().call(square,"getMovingObjects"),1)>0 then
            local okay,result=pcall(LosUtil.lineClear,getCell(),x,y,z,x+dx,y+dy,z,false)
            if okay and tostring(result):find("Clear",1,true) then return true end
        end
    end end
    return false
end
function S.pulse()
    local candidates={}
    for computer,panel in pairs(B().computers) do
        if not U().present(computer) or not B().connected(computer,panel) then
            if sounds[panel.id] and sounds[panel.id].computer==computer then S.stop(panel) end
            B().computers[computer]=nil powerStates[computer]=nil
        else
            local powered=SC.Terminal.powered(computer)
            local source=not powered and "off" or U().nativePower(computer) and "building power" or "battery backup"
            if powerStates[computer] and powerStates[computer]~=source then B().log(panel,"Computer supply: "..source..".") end
            powerStates[computer]=source
            if powered and not panel.security.locked then
                -- One sensor pass per panel even when two computers share it.
                local old=candidates[panel.id]
                local identity=B().computerId(computer)
                if not old or identity<old.identity then candidates[panel.id]={panel=panel,computer=computer,identity=identity} end
                for kind,routine in pairs(panel.routines or {}) do routineTick(panel,computer,kind,routine) end
            end
            local sound=sounds[panel.id]
            if sound and sound.computer==computer then
                local hours=U().hours()
                if not powered or not U().nativePower(computer) or not panel.sounding or sound.untilMs and U().now()>=sound.untilMs
                    or hours and panel.sounding.untilHour and hours>=panel.sounding.untilHour then S.stop(panel)
                else
                    U().call(sound.emitter,"tick")
                    local x,y,z=U().position(computer)
                    if type(addSound)=="function" then addSound(nil,x,y,z,sound.announcement and 60 or 200,100) end
                end
            end
        end
    end
    local work={}
    for _,entry in pairs(candidates) do
        for _,row in pairs(entry.panel.devices) do
            if row.contact or row.motion then work[#work+1]={panel=entry.panel,computer=entry.computer,row=row} end
        end
    end
    table.sort(work,function(a,b) return a.panel.id==b.panel.id and a.row.id<b.row.id or a.panel.id<b.panel.id end)
    local budget=256
    for _=1,#work do
        local nextIndex=sensorCursor%#work+1
        local entry=work[nextIndex] local row=entry.row
        local cost=row.motion and 26 or 1
        if cost>budget then break end
        budget=budget-cost sensorCursor=nextIndex
        local object=B().resolve(row)
        if object then
            local value=B().status(row)
            if row.contact and row.lastContact and row.lastContact~=value then
                B().log(entry.panel,row.label..": "..value)
                if entry.panel.armed and value=="Open" then S.sound(entry.panel,entry.computer,false) end
            end
            if row.contact then row.lastContact=value end
            if row.motion then
                local detected=motion(row,object)
                if detected==true and row.lastMotion~=true then
                    B().log(entry.panel,"Motion at "..row.label)
                    if entry.panel.armed then S.sound(entry.panel,entry.computer,false) end
                end
                row.lastMotion=detected
            end
        end
    end
end
function S.reset()
    for id,sound in pairs(sounds) do
        U().call(sound.emitter,"stopSound",sound.handle)
        if getWorld then U().call(getWorld(),"returnOwnershipOfEmitter",sound.emitter) end
        sounds[id]=nil
    end
    powerStates=setmetatable({}, {__mode="k"}) sensorCursor=0
end
return S
