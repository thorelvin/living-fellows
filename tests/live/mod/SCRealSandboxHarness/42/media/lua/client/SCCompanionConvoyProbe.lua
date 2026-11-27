-- SPDX-License-Identifier: MIT
-- Two native seat-zero companions. After dispatch, only public driving calls
-- supply a real leader route and its measured trail; no pose/velocity writes.
local Probe={}
local function call(object,name,...)
    if not object then return nil end
    local okay,value=pcall(function(...) return object[name](object,...) end,...)
    return okay and value or nil
end
local function distance(a,b) return math.sqrt((a:getX()-b:getX())^2+(a:getY()-b:getY())^2) end
local function body(car)
    local sum=0
    for i=0,car:getPartCount()-1 do
        local part=car:getPartByIndex(i) local id=part:getId()
        if id~="Engine" and id~="Battery" and id~="Muffler" and not string.find(id,"Tire",1,true)
            and not string.find(id,"Suspension",1,true) and not string.find(id,"Brake",1,true) then sum=sum+part:getCondition() end
    end
    return sum
end
local function prepare(car)
    for i=0,car:getPartCount()-1 do
        local part=car:getPartByIndex(i) part:setCondition(100)
        local item=part:getInventoryItem() if item then item:setCondition(item:getConditionMax()) end
        if string.find(part:getId(),"Tire",1,true) then part:setContainerContentAmount(part:getContainerCapacity()) end
    end
    car:updatePartStats()
    local tank=car:getPartById("GasTank") if tank then tank:setContainerContentAmount(tank:getContainerCapacity()) end
    local battery=car:getBattery() local item=battery and battery:getInventoryItem()
    if item then item:setCurrentUsesFloat(1) end
end
local function outside(U,car)
    local position=car:getPassengerPosition(0,"outside")
    local door=position and car:getPassengerPositionWorldPos(position,Vector3f.new())
    local best,bestDistance
    if door then for dx=-2,2 do for dy=-2,2 do
        local tile=U.gridSquare(math.floor(door:x())+dx,math.floor(door:y())+dy,0)
        if tile and U.isSquareFree(tile) then
            local d=car:getEnterSeatDistance(0,tile:getX()+.5,tile:getY()+.5)
            if d and d>=0 and d<=2.56 and (not bestDistance or d<bestDistance) then best,bestDistance=tile,d end
        end
    end end end
    return best
end
local function overlap(SC,a,b)
    local p,q=SC.ExpeditionCar.footprint(a),SC.ExpeditionCar.footprint(b)
    if not p or not q then return true end
    for _,poly in ipairs({p,q}) do for i=1,4 do
        local j=i%4+1 local ax=-(poly["y"..j]-poly["y"..i]) local ay=poly["x"..j]-poly["x"..i]
        local amin,amax,bmin,bmax=math.huge,-math.huge,math.huge,-math.huge
        for k=1,4 do
            local x=p["x"..k]*ax+p["y"..k]*ay local y=q["x"..k]*ax+q["y"..k]*ay
            amin,amax=math.min(amin,x),math.max(amax,x) bmin,bmax=math.min(bmin,y),math.max(bmax,y)
        end
        if amax<bmin or bmax<amin then return false end
    end end
    return true
end
local function write(text,append)
    local writer=getFileWriter("LivingFellowsHarness/companion-convoy-tsv.txt",true,append==true)
    if not writer then error("convoy trace unavailable") end
    writer:writeln(text) writer:close()
end
function Probe.step(H,current,check,result,phase)
    local SC=LivingFellows local U=SC.GameplayUtil
    if H.config.companion_convoy_photo_only=="true" then
        if not H.savedConvoyPhoto then
            H.savedConvoyPhoto={at=current}
            SC.Scheduler.unregister("decision")
            H.player:teleportTo(7113.5,8304.5,0)
            return
        end
        local saved=H.savedConvoyPhoto
        if current-saved.at<10000 then return end
        local lead,follow=SC.Vehicle.loadedBySqlId(5),SC.Vehicle.loadedBySqlId(6)
        if (not lead or not follow) and current-saved.at<25000 then return end
        if not saved.checked then
            saved.checked=true
            local loaded=check("convoy_saved_photo_cars",lead~=nil and follow~=nil,"retained SQL 5/6; no car spawn or pose write")
            if not loaded then phase("finish",current) return end
            local a=math.sqrt((lead:getX()-7108.390625)^2+(lead:getY()-8290.4921875)^2)
            local b=math.sqrt((follow:getX()-7108.515625)^2+(follow:getY()-8299.875)^2)
            check("convoy_saved_photo_poses",a<.75 and b<.75 and math.abs(lead:getCurrentSpeedKmHour())<.6
                and math.abs(follow:getCurrentSpeedKmHour())<.6,"original run delta="..a..","..b.." gap="..distance(lead,follow))
            check("convoy_saved_photo_observer",require("SCIntersectionTurnRecorder").photoObserver(H,SC,follow,lead,result),
                "photograph only; movement acceptance remains the original completed run")
            saved.ready=current
        end
        if saved.ready and current-saved.ready>=1500 then phase("finish",current) end
        return
    end
    local f=H.companionConvoy
    local function fail(name,detail)
        result("FAIL","companion_convoy_"..name,tostring(detail))
        if f then for _,row in ipairs(f.rows or {}) do if row.actor then SC.Driving.hold(row.actor) end end end
        phase("finish",current)
    end
    if H.phase=="drive_setup" then
        if current-H.phaseStartedAt<3000 then return end
        if not check("companion_convoy_bridge",SC.Driving.available(),"public native driving API") then phase("finish",current) return end
        SC.Scheduler.unregister("decision")
        H.player:teleportTo(7078.5,8318.5,0)
        f={rows={},at=current,index=1,trail={}}
        H.companionConvoy=f phase("drive_companion_convoy_load",current) return
    end
    if not f then return fail("fixture","missing state") end
    if H.phase=="drive_companion_convoy_photo" then
        H.player:faceLocation(f.rows[1].car:getX(),f.rows[1].car:getY())
        if current-H.phaseStartedAt>=1200 then phase("finish",current) end
        return
    end
    if H.phase=="drive_companion_convoy_load" then
        if current-H.phaseStartedAt<10000 then return end
        local watch=require("SCIntersectionTurnRecorder").observer(U,{cx=7107,cy=8318})
        if not watch then return fail("observer","no native upstairs room") end
        H.player:teleportTo(watch.x+.5,watch.y+.5,watch.z)
        phase("drive_companion_convoy_cars",current) return
    end
    if H.phase=="drive_companion_convoy_cars" then
        if current-H.phaseStartedAt<5000 then return end
        for index,x in ipairs({7135,7154}) do
            local tile=U.gridSquare(x,8316,0)
            if not tile or not U.isSquareFree(tile) then return fail("car_floor",x.." "..(tile and "occupied" or "unloaded")) end
            local car=addVehicleDebug("Base.CarNormal",IsoDirections.W,nil,tile)
            if not car or not car:getSquare() then return fail("car_spawn",index) end
            prepare(car)
            local v=car:getForwardVector(Vector3f.new())
            if v:x()>-.7 then return fail("car_heading",v:x()) end
            f.rows[index]={car=car,startX=car:getX(),startY=car:getY()}
        end
        phase("drive_companion_convoy_board",current) return
    end
    if H.phase=="drive_companion_convoy_board" then
        if current-H.phaseStartedAt>45000 then return fail("boarding_deadline",f.index) end
        local row=f.rows[f.index]
        if not SC.Vehicle.isStationary(row.car) then return end
        if not row.ticket then
            local tile=outside(U,row.car) if not tile then return fail("door",f.index) end
            local why
            row.ticket,why=SC.Actor.beginSpawn(tile,{recruited=true,identity={forename=f.index==1 and "ConvoyLead" or "ConvoyFollow",
                surname="Tester",gender="woman",outfit="Generic01"}})
            if not row.ticket then return fail("spawn",why) end
            return
        end
        if not row.actor then
            local actor,why=SC.Actor.pollSpawn(row.ticket)
            if not actor then if why~="spawn_pending" then return fail("spawn",why) end return end
            row.actor=actor row.actorAt=current
            actor:getInventory():AddItem(row.car:createVehicleKey()) return
        end
        if current-row.actorAt<1200 then return end
        local prepared,why=SC.Vehicle.preflightDriver(row.actor,row.car)
        if not prepared then if why=="vehicle is moving" then return end return fail("preflight",why) end
        local okay,reason=SC.Driving.takeWheel(row.actor,row.car,{preflight=prepared})
        if not okay then return fail("seat",reason) end
        if not SC.Driving.start(row.actor) then return fail("wheel",f.index) end
        row.body=body(row.car)
        result("PASS","companion_convoy_driver_"..f.index,"native seat=0 sql="..row.car:getSqlId())
        f.index=f.index+1
        if f.index<=2 then return end
        local route,reason=SC.Driving.planRoute(f.rows[1].actor,{x=7107,y=8289,z=0})
        if not route or #route.points<3 then return fail("lead_route",reason) end
        local followed,why=SC.Driving.followRoute(f.rows[1].actor,route,20)
        if not followed then return fail("lead_follow",why) end
        local leader,follower=f.rows[1].car,f.rows[2].car
        f.trail={{x=follower:getX(),y=follower:getY(),width=0},{x=leader:getX(),y=leader:getY(),width=0}}
        f.nextTrail=0 f.nextSample=0 f.runningAt=current
        write("ms\tlead_x\tlead_y\tlead_speed\tfollow_x\tfollow_y\tfollow_speed\tgap\tlead_mode\tfollow_mode\tlead_corners\tfollow_corners")
        phase("drive_companion_convoy_run",current) return
    end
    if H.phase=="drive_companion_convoy_run" then
        local lead,follow=f.rows[1],f.rows[2]
        if current-f.runningAt>120000 then return fail("arrival_deadline",SC.Driving.status(follow.actor).state) end
        if lead.actor:getVehicle()~=lead.car or follow.actor:getVehicle()~=follow.car
            or lead.car:getDriver()~=lead.actor or follow.car:getDriver()~=follow.actor then return fail("seat_lost","native driver changed") end
        if current>=f.nextTrail then
            f.nextTrail=current+100
            local last=f.trail[#f.trail]
            if (lead.car:getX()-last.x)^2+(lead.car:getY()-last.y)^2>=.75^2 then
                f.trail[#f.trail+1]={x=lead.car:getX(),y=lead.car:getY(),width=0}
            end
            local okay,why=SC.Driving.followVehicle(follow.actor,lead.car,f.trail,25)
            if not okay then return fail("follow_vehicle",why) end
        end
        local a,b=SC.Driving.status(lead.actor) or {},SC.Driving.status(follow.actor) or {}
        if overlap(SC,lead.car,follow.car) then return fail("body_overlap","native vehicle polygons intersect") end
        for _,row in ipairs(f.rows) do
            local status=SC.Driving.status(row.actor) or {}
            if body(row.car)~=row.body or (tonumber(status.zombiesKilled) or 0)>0
                or row.actor:getBodyDamage():getOverallBodyHealth()<99.9 then return fail("contact","body, driver or zombie contact") end
        end
        local gap=distance(lead.car,follow.car)
        if current>=f.nextSample then
            f.nextSample=current+250
            write(table.concat({current-f.runningAt,lead.car:getX(),lead.car:getY(),lead.car:getCurrentSpeedKmHour(),
                follow.car:getX(),follow.car:getY(),follow.car:getCurrentSpeedKmHour(),gap,
                tostring(a.mode),tostring(b.mode),tostring(a.corners),tostring(b.corners)},"\t"),true)
        end
        if a.mode=="arrived" and math.abs(follow.car:getCurrentSpeedKmHour())<.6 and gap>=5 and gap<=12 then
            f.settledAt=f.settledAt or current
            if current-f.settledAt<1000 then return end
            local moved=math.sqrt((follow.car:getX()-follow.startX)^2+(follow.car:getY()-follow.startY)^2)
            local av,bv=lead.car:getForwardVector(Vector3f.new()),follow.car:getForwardVector(Vector3f.new())
            check("companion_convoy_completed",moved>=40 and av:z()<-.9 and bv:z()<-.9,
                "follower_moved="..moved.." gap="..gap.." trail_points="..#f.trail)
            check("companion_convoy_corner_scope",(tonumber(a.corners) or 0)>=1 and tonumber(b.corners)==0,
                "lead_arcs="..tostring(a.corners).." follower_raw="..tostring(b.corners))
            result("PASS","companion_convoy_contact_free","both native drivers retained, hulls separate, no body loss or zombie contact")
            SC.Driving.hold(lead.actor) SC.Driving.hold(follow.actor)
            check("companion_convoy_photo_observer",require("SCIntersectionTurnRecorder").photoObserver(H,SC,
                follow.car,lead.car,result),"measurement complete before observation-only move")
            phase("drive_companion_convoy_photo",current) return
        else f.settledAt=nil end
    end
end
return Probe
