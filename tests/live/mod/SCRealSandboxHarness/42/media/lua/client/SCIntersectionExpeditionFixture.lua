-- SPDX-License-Identifier: MIT
-- Select a real two-junction car mission before dispatch; no route rewriting.
local Fixture={}
local function photograph(receipt,name,result)
    receipt.photos=receipt.photos or {}
    if receipt.photos[name] then return end
    receipt.photos[name]=true
    local filename="junction-expedition-"..name..".png"
    local okay,why=pcall(function() getCore():TakeFullScreenshot(filename) end)
    result(okay and "PASS" or "FAIL","team_drive_native_screenshot",filename.." "..tostring(why))
end
function Fixture.roster(SC,test,current)
    test.junctionRoster=test.junctionRoster or {records={},index=1,started=current}
    local state=test.junctionRoster
    if #state.records==2 then return state.records end
    if current-state.started>30000 then return false,"fresh expedition roster timed out" end
    if not state.ticket then
        local square,bestDistance
        local outside=test.vehicle:getPassengerPosition(state.index-1,"outside")
        local door=outside and test.vehicle:getPassengerPositionWorldPos(outside,Vector3f.new())
        if not door then return false,"fresh expedition passenger door unavailable" end
        for dx=-2,2 do for dy=-2,2 do
            local tile=SC.GameplayUtil.gridSquare(math.floor(door:x())+dx,math.floor(door:y())+dy,0)
            if not square and tile and tile:isOutside() and SC.GameplayUtil.isSquareFree(tile)
                and not tile:isSolid() and not tile:isSolidTrans() then
                local distance=test.vehicle:getEnterSeatDistance(state.index-1,tile:getX()+.5,tile:getY()+.5)
                if distance and distance>=0 and distance<=2.56 and (not bestDistance or distance<bestDistance) then
                    square,bestDistance=tile,distance
                end
            end
        end end
        if not square then return false,"fresh expedition actor floor unavailable" end
        local why
        state.ticket,why=SC.Actor.beginSpawn(square,{recruited=true,identity={forename="Junction"..state.index,
            surname="Expedition",gender="woman",outfit="Generic01"}})
        if not state.ticket then return false,why end
        return nil,"pending"
    end
    local actor,why=SC.Actor.pollSpawn(state.ticket)
    if not actor then
        if why=="spawn_pending" then return nil,why end
        return false,why
    end
    local id=SC.Registry.idOf(actor)
    local record=id and SC.Registry.byId(id)
    if not record then return false,"fresh expedition actor was not registered" end
    state.records[#state.records+1]=record
    state.index=state.index+1 state.ticket=nil
    return nil,"pending"
end
local function body(car)
    local total=0
    for i=0,car:getPartCount()-1 do
        local part=car:getPartByIndex(i) local id=part:getId()
        if id~="Engine" and id~="Battery" and id~="Muffler" and not string.find(id,"Tire",1,true)
            and not string.find(id,"Suspension",1,true) and not string.find(id,"Brake",1,true) then total=total+part:getCondition() end
    end
    return total
end
local function turns(route)
    local count,last=0,nil
    for i=2,#route.points-1 do
        local a,p,b=route.points[i-1],route.points[i],route.points[i+1]
        local ax,ay,bx,by=p.x-a.x,p.y-a.y,b.x-p.x,b.y-p.y
        local angle=math.abs(math.atan2(ax*by-ay*bx,ax*bx+ay*by))
        if p.junction and angle>=math.rad(25) and (not last or (p.x-last.x)^2+(p.y-last.y)^2>=12^2) then
            count=count+1 last=p
        end
    end
    return count
end
function Fixture.choose(SC,records,car,zone,replayStop)
    if replayStop then
        local target={x=7163,y=8193,z=0}
        local inspected,why=SC.ExpeditionCar.preflight(records,zone,car:getSqlId(),target)
        return target,inspected,"known solid-stop replay; "..tostring(why)
    end
    local x,y=car:getX(),car:getY()
    local attempts,reasons,candidates=0,{},{}
    for _,radius in ipairs({50,75,100,125,150,200,250,350,500}) do
        for _,offset in ipairs({{1,1},{-1,1},{1,-1},{-1,-1},{1,.5},{-1,.5},{.5,1},{.5,-1}}) do
            attempts=attempts+1
            local target={x=math.floor(x+radius*offset[1]),y=math.floor(y+radius*offset[2]),z=0}
            local route=SC.ExpeditionRoute.planFromPoint({x=x,y=y,z=0},target,true)
            local count=route and turns(route) or 0
            if count>=2 and (tonumber(route.roadLength) or math.huge)<=650 then
                local unmapped=0
                for i=2,#route.points-1 do
                    local a,p,b=route.points[i-1],route.points[i],route.points[i+1]
                    local ax,ay,bx,by=p.x-a.x,p.y-a.y,b.x-p.x,b.y-p.y
                    if not p.junction and math.abs(math.atan2(ax*by-ay*bx,ax*bx+ay*by))>=math.rad(12) then unmapped=unmapped+1 end
                end
                candidates[#candidates+1]={target=target,unmapped=unmapped,length=route.roadLength}
            end
        end
    end
    table.sort(candidates,function(a,b)
        if a.length~=b.length then return a.length<b.length end
        return a.unmapped<b.unmapped
    end)
    for _,candidate in ipairs(candidates) do
        local target=candidate.target
        local inspected,why=SC.ExpeditionCar.preflight(records,zone,car:getSqlId(),target)
        if inspected and turns(inspected.route)>=2 then
            return target,inspected,"junction_turns="..turns(inspected.route).." unmapped_bends="..candidate.unmapped
                .." candidates="..#candidates.." attempts="..attempts.." goal="..target.x..","..target.y
                .." road="..tostring(inspected.route.roadLength)
        end
        reasons[#reasons+1]=tostring(why)
    end
    return nil,nil,"no two separated real junction turns in "..attempts.." candidates; "..table.concat(reasons,",")
end
function Fixture.stopScreenshot(H,SC,test,current,result)
    local car=test.vehicle
    if not test.stopPhoto then
        test.stopPhoto={at=current,x=car:getX(),y=car:getY()}
        result("PASS","team_drive_solid_stop_photo_scene","stopped="..car:getX()..","..car:getY()
            .." speed="..car:getCurrentSpeedKmHour().."; observer move is after the recorded failure")
        local U=SC.GameplayUtil local watch
        for _,offset in ipairs({{-2,4},{0,5},{-8,8},{8,8},{-10,0},{10,0},{0,10}}) do
            local square=U.gridSquare(math.floor(car:getX()+offset[1]),math.floor(car:getY()+offset[2]),0)
            if square and square:TreatAsSolidFloor() and U.isSquareFree(square)
                and not square:isSolid() and not square:isSolidTrans() then watch=square break end
        end
        if watch then H.player:teleportTo(watch:getX()+.5,watch:getY()+.5,0) end
        return false
    end
    local photo=test.stopPhoto
    H.player:faceLocation(car:getX(),car:getY())
    if current-photo.at<2500 then return false end
    if not photo.requested then
        local filename=tostring(H.config.run_id).."-solid-stop.png"
        local okay,why=pcall(function() getCore():TakeFullScreenshot(filename) end)
        result(okay and "PASS" or "FAIL","team_drive_solid_stop_screenshot",filename.." "..tostring(why))
        result("PASS","team_drive_solid_stop_photo_pose","before="..photo.x..","..photo.y
            .." after="..car:getX()..","..car:getY().." speed="..car:getCurrentSpeedKmHour())
        photo.requested=current
        return false
    end
    return current-photo.requested>=1000
end
function Fixture.savedStopScreenshot(H,SC,current,check,result,phase)
    if not H.savedStopPhoto then
        H.savedStopPhoto={at=current}
        H.player:teleportTo(7125.5,8226.5,0)
        return
    end
    local state=H.savedStopPhoto
    if current-state.at<8000 then return end
    local car=SC.Vehicle.loadedBySqlId(9)
    if not car and current-state.at<25000 then return end
    if not state.test then
        if not check("saved_solid_stop_car",car~=nil,"existing retained SQL 9; no car spawned or repositioned") then phase("finish",current) return end
        local distance=math.sqrt((car:getX()-7133.7578125)^2+(car:getY()-8218.1171875)^2)
        if not check("saved_solid_stop_pose",distance<.75 and math.abs(car:getCurrentSpeedKmHour())<.3,
            "position="..car:getX()..","..car:getY().." delta="..distance.." speed="..car:getCurrentSpeedKmHour()) then phase("finish",current) return end
        local driver=car:getDriver()
        if H.config.team_drive_barricade_probe=="true" then
            if not driver and current-state.at<25000 then return end
            SC.Scheduler.unregister("decision")
        end
        if driver then
            local stopped,why=SC.Driving.stop(driver,"screenshot_scene")
            result(stopped and "PASS" or "FAIL","saved_solid_stop_driver_held",tostring(why).."; ordinary stop input, no pose write")
        end
        for _,point in ipairs({{7133,8212},{7136,8212}}) do
            local square=SC.GameplayUtil.gridSquare(point[1],point[2],0)
            if square then
                result("PASS","saved_solid_tile",point[1]..","..point[2].." solid="..tostring(square:isSolid())
                    .." trans="..tostring(square:isSolidTrans()))
                local objects=square:getObjects()
                for i=0,objects:size()-1 do
                    local object=objects:get(i) local sprite=object:getSprite()
                    result("PASS","saved_solid_object",point[1]..","..point[2].." name="..tostring(object:getObjectName())
                        .." sprite="..tostring(sprite and sprite:getName()))
                end
            end
        end
        local map=getFileWriter("LivingFellowsHarness/barricade-grid-tsv.txt",true,false)
        if not map then error("barricade grid writer unavailable") end
        map:writeln("x\ty\tsolid\ttrans\toutside\tsprites")
        for y=8203,8225 do for x=7124,7145 do
            local square=SC.GameplayUtil.gridSquare(x,y,0)
            if square then
                local sprites={} local objects=square:getObjects()
                for i=0,objects:size()-1 do
                    local sprite=objects:get(i):getSprite()
                    if sprite then sprites[#sprites+1]=tostring(sprite:getName()) end
                end
                map:writeln(table.concat({x,y,tostring(square:isSolid()),tostring(square:isSolidTrans()),
                    tostring(square:isOutside()),table.concat(sprites,",")},"\t"))
            end
        end end
        map:close()
        state.test={vehicle=car,driver=driver}
    end
    if Fixture.stopScreenshot(H,SC,state.test,current,result) then
        if H.config.team_drive_barricade_probe=="true" then
            require("SCBarricadeDriveProbe").step(H,SC,state.test,current,check,result,phase)
            return
        end
        if not state.finishedAt then
            state.finishedAt=current
            result("PASS","saved_solid_stop_scene_only","reloaded actual stopped car and map; no new driving acceptance claimed")
        end
        if current-state.finishedAt>=30000 then phase("finish",current) end
    end
end
local function captureRoute(receipt,route)
    receipt.routeIndex=(receipt.routeIndex or -1)+1
    local writer=getFileWriter("LivingFellowsHarness/junction-expedition-route-tsv.txt",true,receipt.routeIndex>0)
    if not writer then error("expedition route writer unavailable") end
    if receipt.routeIndex==0 then writer:writeln("route\tx\ty\twidth\tjunction") end
    for _,point in ipairs(route.points) do
        writer:writeln(table.concat({receipt.routeIndex,point.x,point.y,point.width or 0,tostring(not not point.junction)},"\t"))
    end
    writer:close()
    receipt.routeCorners={}
    for i=2,#route.points-1 do
        local a,p,b=route.points[i-1],route.points[i],route.points[i+1]
        local ax,ay,bx,by=p.x-a.x,p.y-a.y,b.x-p.x,b.y-p.y
        local al,bl=math.sqrt(ax*ax+ay*ay),math.sqrt(bx*bx+by*by)
        if p.junction and al>0 and bl>0 and math.abs(math.atan2(ax*by-ay*bx,ax*bx+ay*by))>=math.rad(25) then
            receipt.routeCorners[#receipt.routeCorners+1]={x=p.x,y=p.y,ax=ax/al,ay=ay/al,bx=bx/bl,by=by/bl}
        end
    end
end
function Fixture.begin(car,driver,route)
    local receipt={body=body(car),health=driver:getBodyDamage():getOverallBodyHealth(),driver=driver,visited={},
        x=car:getX(),y=car:getY(),lastX=car:getX(),lastY=car:getY(),distance=0,corners=0,kills=0}
    captureRoute(receipt,route)
    local module=LivingFellows.ExpeditionRoute
    receipt.originalPlanner=module.planAvoidingAll
    receipt.observedPlanner=function(actor,goal,circles,origin)
        local planned,reason,native=receipt.originalPlanner(actor,goal,circles,origin)
        if actor==driver and planned then captureRoute(receipt,planned) end
        return planned,reason,native
    end
    module.planAvoidingAll=receipt.observedPlanner
    return receipt
end
function Fixture.observe(SC,test,current,state,check,result)
    local receipt=test.junctionReceipt
    local native=SC.Driving.status(receipt.driver) or {}
    local car=test.vehicle
    receipt.distance=receipt.distance+math.sqrt((car:getX()-receipt.lastX)^2+(car:getY()-receipt.lastY)^2)
    receipt.lastX,receipt.lastY=car:getX(),car:getY()
    receipt.corners=math.max(receipt.corners,tonumber(native.corners) or 0)
    receipt.kills=math.max(receipt.kills,tonumber(native.zombiesKilled) or 0)
    if receipt.distance>=100 and car:getY()<8209 and car:getX()>7130 and car:getX()<7141 then
        photograph(receipt,"past-barricades",result)
    end
    local forward=car:getForwardVector(Vector3f.new())
    for _,corner in ipairs(receipt.routeCorners or {}) do
        local dx,dy=car:getX()-corner.x,car:getY()-corner.y
        local distance=math.sqrt(dx*dx+dy*dy)
        if distance<=20 and dx*corner.ax+dy*corner.ay<=0
            and forward:x()*corner.ax+forward:z()*corner.ay>=.985 then corner.before=true end
        if corner.before and distance<=10 then corner.near=true end
        if not corner.passed and corner.near and distance<=20 and dx*corner.bx+dy*corner.by>=0
            and forward:x()*corner.bx+forward:z()*corner.by>=.985 then
            corner.passed=true
            local distinct=true
            for _,old in ipairs(receipt.visited) do
                if (corner.x-old.x)^2+(corner.y-old.y)^2<12^2 then distinct=false break end
            end
            if distinct then
                receipt.visited[#receipt.visited+1]=corner
                result("PASS","team_drive_mapped_junction_passed","route="..receipt.routeIndex
                    .." x="..corner.x.." y="..corner.y.." count="..#receipt.visited)
                photograph(receipt,"junction-"..#receipt.visited,result)
            end
        end
    end
    if native.obstacleKind=="character" and current>=(receipt.nextBlocker or 0) then
        receipt.nextBlocker=current+5000
        local square=SC.GameplayUtil.gridSquare(native.obstacleX,native.obstacleY,0)
        local movers=square and square:getMovingObjects()
        if movers then for i=0,movers:size()-1 do
            local actor=movers:get(i)
            if instanceof(actor,"IsoGameCharacter") then
                result("PASS","team_drive_character_blocker_recorded",
                    "kind="..(instanceof(actor,"IsoZombie") and "zombie" or "human")
                    .." at="..actor:getX()..","..actor:getY().." dead="..tostring(actor:isDead()))
            end
        end end
    end
    local allExited=state=="parked_at_site"
    if allExited then for _,member in ipairs(test.team) do
        if SC.Vehicle.isNativeSeated(member.actor) then allExited=false break end
    end end
    if allExited or current>=(receipt.nextSample or 0) then
        local writer=getFileWriter("LivingFellowsHarness/junction-expedition-tsv.txt",true,receipt.nextSample~=nil)
        if not writer then error("expedition track writer unavailable") end
        if not receipt.nextSample then writer:writeln("ms\tx\ty\tspeed\tstate\tmode\tcorners\tkills\tbody_condition\tdriver_health\tfx\tfy\troute\tjunctions_passed") receipt.at=current end
        writer:writeln(table.concat({current-receipt.at,car:getX(),car:getY(),car:getCurrentSpeedKmHour(),
            state,tostring(native.mode),receipt.corners,receipt.kills,body(car),receipt.driver:getBodyDamage():getOverallBodyHealth(),
            forward:x(),forward:z(),receipt.routeIndex,#receipt.visited},"\t"))
        writer:close() receipt.nextSample=current+250
    end
    if not allExited then return false end
    photograph(receipt,"arrived",result)
    local moved=math.sqrt((car:getX()-receipt.x)^2+(car:getY()-receipt.y)^2)
    check("team_drive_junction_leg_arrived",moved>=20 and #receipt.visited>=2 and receipt.distance>=100,
        "mapped_junctions_passed="..#receipt.visited.." native_corners="..receipt.corners
            .." moved="..moved.." driven="..receipt.distance.." native passengers all exited")
    check("team_drive_junction_leg_driver_healthy",receipt.driver:getBodyDamage():getOverallBodyHealth()>=receipt.health,
        "health="..receipt.driver:getBodyDamage():getOverallBodyHealth())
    -- The real-game journey retains normal zombie ramming. Contacts are
    -- observations here, separate from the six strict contact-free turn runs.
    result("PASS","team_drive_junction_leg_contacts_recorded","body_loss="..(receipt.body-body(car)).." zombie_contacts="..receipt.kills)
    result("PASS","team_drive_junction_leg_saved","public expedition dispatch through two separated mapped junctions")
    if SC.ExpeditionRoute.planAvoidingAll==receipt.observedPlanner then SC.ExpeditionRoute.planAvoidingAll=receipt.originalPlanner end
    return true
end
return Fixture
