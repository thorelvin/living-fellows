-- SPDX-License-Identifier: MIT
-- Driving receipts are read-only; observation moves only after measurements end.
local Recorder = {}
local ROOT = "LivingFellowsHarness/"
local COLUMNS = {"ms","x","y","fx","fy","speed_kmh","mode","along","remaining",
    "lateral","offset","laneOffset","corners","cornersSharp","cornerFallbacks",
    "laneError","maxLaneError","activeCornerStart","activeCornerEnd","activeCornerAngle",
    "activeCornerArc","body_condition","health","zombies_killed","fps","multiplier",
    "obstacleKind","obstacleX","obstacleY","obstacleDistance","blockedAt","blockedX","blockedY"}
local function write(name,text,append)
    local out=getFileWriter(ROOT..name,true,append==true)
    if not out then error("cannot write turn receipt "..name) end
    out:writeln(text);out:close()
end
local function body(car)
    local total=0
    for i=0,car:getPartCount()-1 do
        local part=car:getPartByIndex(i)
        local id=part:getId()
        local wear=id=="Engine" or id=="Battery" or id=="Muffler"
            or string.find(id,"Tire",1,true) or string.find(id,"Suspension",1,true)
            or string.find(id,"Brake",1,true)
        if not wear then total=total+part:getCondition() end
    end
    return total
end
function Recorder.observer(U,road)
    -- Use an existing upstairs room. The observer keeps native health and
    -- visibility, while doors/stairs provide ordinary physical separation.
    for radius=6,24,2 do
        for dx=-radius,radius,2 do for dy=-radius,radius,2 do
            if math.max(math.abs(dx),math.abs(dy))==radius then
                local x,y=math.floor(road.cx+dx),math.floor(road.cy+dy)
                local tile=U.gridSquare(x,y,1)
                if tile and tile:getRoom() and tile:getFloor() and tile:TreatAsSolidFloor()
                    and not tile:isSolid() and not tile:isSolidTrans() and U.isSquareFree(tile) then
                    return {x=x,y=y,z=1}
                end
            end
        end end
    end
    return nil
end
function Recorder.photoObserver(H,SC,car,focus,result)
    -- Measurement has ended. Move only the observer so the final native PNG
    -- actually contains the cars, rather than an empty upstairs view.
    for _,offset in ipairs({{5,5},{-5,5},{5,-5},{-5,-5},{0,7},{7,0}}) do
        local tile=SC.GameplayUtil.gridSquare(math.floor(car:getX())+offset[1],math.floor(car:getY())+offset[2],0)
        if tile and tile:TreatAsSolidFloor() and not tile:isSolid() and not tile:isSolidTrans()
            and SC.GameplayUtil.isSquareFree(tile) then
            H.player:teleportTo(tile:getX()+.5,tile:getY()+.5,0)
            H.player:faceLocation(focus:getX(),focus:getY())
            result("PASS","native_photo_observer_only","measurement ended; observer moved beside actual retained cars; no car pose write")
            return true
        end
    end
    return false
end
function Recorder.start(H,SC,test,current,route)
    test.turnReceipt={at=current,body=body(test.vehicle),health=test.actor:getBodyDamage():getOverallBodyHealth(),
        observerHealth=H.player:getBodyDamage():getOverallBodyHealth(),
        maxError=0,maxSpeed=0,cornerSeen=false,nextSample=0}
    write("turn-track-csv.txt",table.concat(COLUMNS,","))
    write("turn-route-tsv.txt","side\tbaseline\tgeometry")
    local points={}
    for _,point in ipairs(route.points) do
        points[#points+1]=tostring(point.x)..","..tostring(point.y)..","..tostring(point.width)
    end
    write("turn-route-tsv.txt",H.config.driving_turn_side.."\t"..H.config.driving_turn_baseline
        .."\t"..table.concat(points,";"),true)
end
function Recorder.sample(H,test,current,status)
    local receipt=test.turnReceipt
    if not receipt then return end
    local car=test.vehicle
    local speed=math.abs(car:getCurrentSpeedKmHour())
    local fallback=tonumber(status.cornerFallbacks) or 0
    if fallback>(receipt.lastFallback or 0) then
        receipt.lastFallback=fallback
        local lines={"actual pose="..car:getX()..","..car:getY()}
        for key,value in pairs(status) do lines[#lines+1]=tostring(key).."="..tostring(value) end
        local x,y=tonumber(status.obstacleX),tonumber(status.obstacleY)
        if x and y then for sx=x-2,x+2 do for sy=y-2,y+2 do
            local tile=LivingFellows.GameplayUtil.gridSquare(sx,sy,0)
            if tile then
                local props=tile:getProperties()
                lines[#lines+1]="cell="..sx..","..sy.." solid="..tostring(tile:isSolid())
                    .." trans="..tostring(tile:isSolidTrans()).." tree="..tostring(tile:HasTree())
                    .." stopCar="..tostring(props and props:has("StopCar"))
                local objects=tile:getObjects()
                for i=0,objects:size()-1 do
                    local sprite=objects:get(i):getSprite()
                    if sprite then lines[#lines+1]="sprite="..sx..","..sy.." "..tostring(sprite:getName()) end
                end
            end
        end end end
        write("turn-fallback-state.txt",table.concat(lines,"\n"),true)
        getCore():TakeFullScreenshot(tostring(H.config.run_id).."-turn-fallback-"..fallback..".png")
    end
    receipt.maxError=math.max(receipt.maxError,math.abs(tonumber(status.maxLaneError) or 0))
    if status.activeCornerArc==true then
        receipt.cornerSeen=true
        if (tonumber(status.along) or -1)>=(tonumber(status.activeCornerStart) or math.huge) then
            receipt.maxSpeed=math.max(receipt.maxSpeed,speed)
        end
    end
    if current<receipt.nextSample then return end
    receipt.nextSample=current+250
    local forward=car:getForwardVector(Vector3f.new())
    local row={ms=current-receipt.at,x=car:getX(),y=car:getY(),fx=forward:x(),fy=forward:z(),
        speed_kmh=car:getCurrentSpeedKmHour(),body_condition=body(car),
        health=test.actor:getBodyDamage():getOverallBodyHealth(),zombies_killed=status.zombiesKilled,
        fps=getAverageFPS(),multiplier=getGameTime():getMultiplier()}
    local values={}
    for _,column in ipairs(COLUMNS) do
        local value=row[column]
        if value==nil then value=status[column] end
        values[#values+1]=value==nil and "" or tostring(value)
    end
    write("turn-track-csv.txt",table.concat(values,","),true)
end
function Recorder.finish(H,test,current,status,check,result)
    local receipt=test.turnReceipt
    receipt.nextSample=0
    Recorder.sample(H,test,current,status)
    local loss=receipt.body-body(test.vehicle)
    local health=test.actor:getBodyDamage():getOverallBodyHealth()
    local kills=tonumber(status.zombiesKilled) or 0
    local contact="body_loss="..loss.." health="..health.." zombies_killed="..kills
    if H.config.driving_turn_baseline=="true" then
        -- The old version is an observation, including its defects. It does
        -- not have to meet the candidate's no-contact or lane/speed criteria.
        result("PASS","turn_baseline_contact_recorded",contact)
    else
        check("turn_no_collision",loss==0 and health>=receipt.health and kills==0,contact)
    end
    local observerHealth=H.player:getBodyDamage():getOverallBodyHealth()
    -- A saved observer can lose a fraction of health to its initial heavy load
    -- before standing still. Judge interruption during the drive, not exact 100.
    check("turn_observer_healthy",receipt.observerHealth>=99 and observerHealth>=receipt.observerHealth-.1
        and not H.player:isDead(),
        "before="..receipt.observerHealth.." after="..observerHealth)
    if H.config.driving_turn_baseline=="true" then
        result("PASS","turn_baseline_recorded","side="..H.config.driving_turn_side
            .." seconds="..((current-receipt.at)/1000))
    else
        check("turn_checked_arc",receipt.cornerSeen and (tonumber(status.corners) or 0)>=1
            and tonumber(status.cornersSharp)==0 and tonumber(status.cornerFallbacks)==0,
            "corners="..tostring(status.corners).." sharp="..tostring(status.cornersSharp)
                .." fallback="..tostring(status.cornerFallbacks))
        check("turn_lane_error",tonumber(status.maxLaneError)~=nil and receipt.maxError<=1.5,
            "maxLaneError="..receipt.maxError)
        check("turn_speed_held",receipt.cornerSeen and receipt.maxSpeed<=8,
            "maxCornerKmh="..receipt.maxSpeed.." limit=6+2")
    end
    result("PASS","turn_receipts_saved","side="..H.config.driving_turn_side
        .." seconds="..((current-receipt.at)/1000).." peak="..receipt.maxSpeed
        .." lane="..receipt.maxError.." files=turn-track-csv.txt,turn-route-tsv.txt")
    check("turn_photo_observer",Recorder.photoObserver(H,LivingFellows,test.vehicle,test.vehicle,result),
        "observation only, after final timed pose and health checks")
end
return Recorder
