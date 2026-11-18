-- SPDX-License-Identifier: MIT
-- Diagnostic only: replay the expedition's original route at its retained stop.
-- Public driving controls keep every native obstacle and rear-clearance check.
-- The native follower chooses its own passing line. No route points are moved.
local Probe={}
local function body(car)
    local value=0
    for i=0,car:getPartCount()-1 do
        local part=car:getPartByIndex(i) local id=part:getId()
        if id~="Engine" and id~="Battery" and id~="Muffler" and not string.find(id,"Tire",1,true)
            and not string.find(id,"Suspension",1,true) and not string.find(id,"Brake",1,true) then value=value+part:getCondition() end
    end
    return value
end
local function photo(H,state,name,current,result)
    state.photos=state.photos or {}
    if state.photos[name] then return end
    state.photos[name]=current
    local filename=H.config.run_id.."-barricade-"..name..".png"
    local okay,why=pcall(function() getCore():TakeFullScreenshot(filename) end)
    result(okay and "PASS" or "FAIL","barricade_photo_"..name,filename.." "..tostring(why))
end
function Probe.step(H,SC,state,current,check,result,phase)
    local car,driver=state.vehicle,state.driver
    if state.done then
        if current-state.done>=5000 then phase("finish",current) end
        return
    end
    local function finish(okay,name,detail)
        photo(H,state,okay and "cleared" or "stopped",current,result)
        check(name,okay,detail)
        if driver then SC.Driving.hold(driver) end
        state.done=current
    end
    if not state.started then
        if not driver or car:getDriver()~=driver then return finish(false,"barricade_driver_retained","original driver left seat") end
        local watch=require("SCIntersectionTurnRecorder").observer(SC.GameplayUtil,{cx=7135,cy=8212})
        if not watch then
            for radius=4,24,2 do for dx=-radius,radius,2 do for dy=-radius,radius,2 do
                local tile=SC.GameplayUtil.gridSquare(7135+dx,8212+dy,1)
                if not watch and tile and tile:getFloor() and tile:TreatAsSolidFloor()
                    and not tile:isSolid() and not tile:isSolidTrans() and SC.GameplayUtil.isSquareFree(tile) then
                    watch={x=tile:getX(),y=tile:getY(),z=1}
                end
            end end end
        end
        if not watch then return finish(false,"barricade_observer_floor","no existing upstairs floor near roadwork") end
        H.player:teleportTo(watch.x+.5,watch.y+.5,watch.z)
        result("PASS","barricade_observer_floor","native floor "..watch.x..","..watch.y..","..watch.z.."; health unchanged")
        local started,why=SC.Driving.start(driver)
        if not started then return finish(false,"barricade_drive_start",tostring(why)) end
        state.route={
            {x=7038,y=8318,width=6},{x=7072.5,y=8318,width=6},{x=7107,y=8318,width=6},
            {x=7107,y=8282,width=6},{x=7107,y=8246,width=6},{x=7113.5,y=8233.5,width=6},
            {x=7119,y=8228,width=6},{x=7131,y=8221.5,width=6},{x=7135.5,y=8214.5,width=6},
            {x=7135.5,y=8209,width=6},{x=7135.5,y=8206,width=6},{x=7163,y=8206,width=6},
        }
        state.leg=#state.route
        local followed,reason=SC.Driving.followRoute(driver,state.route,30)
        if not followed then return finish(false,"barricade_route_start",tostring(reason)) end
        state.started=current state.body=body(car)
        state.health=driver:getBodyDamage():getOverallBodyHealth()
        result("PASS","barricade_diagnostic_route","original public expedition geometry, normal native passing selection and braking; no car pose or velocity writes")
        return
    end
    if car:getDriver()~=driver then return finish(false,"barricade_driver_retained","driver left seat") end
    local status=SC.Driving.status(driver) or {}
    if current>=(state.nextSample or 0) then
        state.nextSample=current+250
        local writer=getFileWriter("SurvivorCompanionHarness/barricade-drive-tsv.txt",true,state.sampled==true)
        if not writer then error("barricade trace writer unavailable") end
        if not state.sampled then writer:writeln("ms\tx\ty\tspeed\tmode\tobstacle\tbody\thealth\tfx\tfy\thit_x\thit_y\toffset\tlane_offset\tobserver_health\tblocked_x\tblocked_y\tleg") end
        local forward=car:getForwardVector(Vector3f.new())
        writer:writeln(table.concat({current-state.started,car:getX(),car:getY(),car:getCurrentSpeedKmHour(),
            tostring(status.mode),tostring(status.obstacleKind),body(car),driver:getBodyDamage():getOverallBodyHealth(),
            forward:x(),forward:z(),tostring(status.obstacleX),tostring(status.obstacleY),tostring(status.offset),
            tostring(status.laneOffset),H.player:getBodyDamage():getOverallBodyHealth(),
            tostring(status.blockedX),tostring(status.blockedY),state.leg},"\t"))
        writer:close() state.sampled=true
    end
    if car:getY()<8214 then photo(H,state,"approach",current,result) end
    if car:getY()<8209 then photo(H,state,"past-barriers",current,result) end
    H.player:faceLocation(car:getX(),car:getY())
    if status.mode=="arrived" and math.abs(car:getCurrentSpeedKmHour())<.6 then
        local intact=body(car)==state.body and driver:getBodyDamage():getOverallBodyHealth()>=state.health
        return finish(intact and car:getY()<8209,"barricade_shoulder_arrived",
            "position="..car:getX()..","..car:getY().." body_loss="..(state.body-body(car))
            .." health="..driver:getBodyDamage():getOverallBodyHealth())
    end
    if status.mode=="blocked" and math.abs(car:getCurrentSpeedKmHour())<.3 then
        state.stalled=state.stalled or current
        if current-state.stalled>15000 then return finish(false,"barricade_leg_blocked",
            "leg="..state.leg.." position="..car:getX()..","..car:getY().." kind="..tostring(status.obstacleKind)
            .." at="..tostring(status.blockedX)..","..tostring(status.blockedY)) end
    else state.stalled=nil end
    if current-state.started>100000 then return finish(false,"barricade_drive_deadline",
        "position="..car:getX()..","..car:getY().." mode="..tostring(status.mode).." obstacle="..tostring(status.obstacleKind)) end
end
return Probe
