-- SPDX-License-Identifier: MIT
-- Measurements in a disposable save. No production controller changes, no
-- zombie intervention, no position/angle/velocity writes during a trial.
local Probe = {}
local ROOT = "LivingFellowsHarness/"
local SCRIPTS = {"Base.CarNormal", "Base.Van", "Base.PickUpTruck"}
-- Selected from the installed 42.22.2 streets.xml; baseline uses the actual
-- planner geometry (including inferred T links), expanded by production Lua.
local FIXTURES = {
    {name="four_way", sx=7071,sy=8318, gx=7107,gy=8354, cx=7107,cy=8318},
    {name="t_junction", sx=6423,sy=5400, gx=6387,gy=5364, cx=6387,cy=5400},
    {name="angled", sx=6874.455844,sy=9977.544156, gx=6813,gy=10003, cx=6849,cy=10003},
    {name="curve_crossing", sx=5960,sy=5292, gx=5895,gy=5363, cx=5960,cy=5328},
}
local COLUMNS = {"trial","mode","script","ms","dt_ms","x","y","fx","fy","speed_kmh",
    "cruise_kmh","input","controller_angle","wheel_angle","clamp","skid","surface",
    "damage_sum","health","zombies_killed","multiplier","fps","state","along","remaining",
    "lateral","target_kmh","forward","brake","body_condition_sum","tyre_condition_min",
    "tyre_pressure_min","tyre_friction_min"}
local fieldsByObject={}
local function call(o,m,...)
    if not o then return nil end
    local ok,v=pcall(function(...) return o[m](o,...) end,...)
    if ok then return v end
end
local function number(v,default) return tonumber(tostring(v)) or default or 0 end
local function field(o,name)
    if not o then return nil end
    local ok,value=pcall(function()
        local cached=fieldsByObject[o]
        if cached and cached[name] then return getClassFieldVal(o,cached[name]) end
        for i=0,getNumClassFields(o)-1 do
            local f=getClassField(o,i)
            if f:getName()==name then
                fieldsByObject[o]=cached or {};fieldsByObject[o][name]=f
                return getClassFieldVal(o,f)
            end
        end
    end)
    if ok then return value end
end
local function vector(v)
    return {number(call(v,"x")),number(call(v,"y")),number(call(v,"z"))}
end
local function textVector(v)
    local values=vector(v)
    return table.concat(values,",")
end
local function line(file,value,append)
    local w=getFileWriter(ROOT..file,true,append==true)
    if not w then error("phase0 cannot write "..file) end
    w:writeln(value);w:close()
end
local function heading(car)
    local v=Vector3f.new()
    car:getForwardVector(v)
    return v:x(),v:z()
end
local function square(x,y)
    return LivingFellows.GameplayUtil.gridSquare(math.floor(x),math.floor(y),0)
end
local function free(x,y,ownCar)
    local s=square(x,y)
    return s and s:isOutside() and not s:getRoom() and not s:getBuilding()
        and not s:HasTree() and not s:isSolid() and not s:isSolidTrans()
        and s:TreatAsSolidFloor() and (s:getVehicleContainer()==nil or s:getVehicleContainer()==ownCar)
end
local function damage(car)
    local total=0
    for i=0,number(call(car,"getPartCount"))-1 do total=total+number(call(call(car,"getPartByIndex",i),"getCondition")) end
    return total
end
local function condition(car)
    local body,tyre,pressure,friction=0,100,1000,1000
    for i=0,car:getPartCount()-1 do
        local p=car:getPartByIndex(i);local id=p:getId()
        -- Vanilla Vehicles.Update wears these parts while driving, without a
        -- collision. Keep that wear visible; never repair it during a trial.
        local wear=id=="Engine" or id=="Battery" or id=="Muffler"
            or string.find(id,"Tire",1,true) or string.find(id,"Suspension",1,true)
            or string.find(id,"Brake",1,true)
        if not wear then body=body+p:getCondition() end
        if string.find(id,"Tire",1,true) then
            tyre=math.min(tyre,p:getCondition())
            pressure=math.min(pressure,p:getContainerContentAmount())
            friction=math.min(friction,p:getWheelFriction())
        end
    end
    return body,tyre,pressure,friction
end
local function parts(s,current)
    for i=0,s.car:getPartCount()-1 do
        local p=s.car:getPartByIndex(i)
        line("phase0-parts-tsv.txt",s.trial.."\t"..(current-s.trialAt).."\t"..p:getId()
            .."\t"..p:getCondition().."\t"..p:getContainerContentAmount()
            .."\t"..p:getWheelFriction(),true)
    end
end
local function geometry(car,s)
    local script=car:getScript()
    local scale=script:getModelScale()
    local body=script:getExtents()
    local maxSpeed=number(field(script,"maxSpeed"))
    if maxSpeed<=0 then error("phase0 cannot read script maxSpeed") end
    line("phase0-geometry-tsv.txt",tostring(car:getScriptName()).."\tbody\t"..textVector(body)
        .."\tscale\t"..scale.."\tmaxSpeed\t"..maxSpeed
        .."\tclampAtMax\t"..script:getSteeringClamp(maxSpeed),true)
    for i=0,script:getWheelCount()-1 do
        local w=script:getWheel(i)
        line("phase0-geometry-tsv.txt",tostring(car:getScriptName()).."\twheel\t"..i.."\t"
            ..tostring(w:getId()).."\tfront\t"..tostring(field(w,"front"))
            .."\toffset\t"..textVector(w:getOffset()),true)
    end
    s.geometry[car:getScriptName()]=true
end
local function provision(car)
    -- A controlled, roadworthy fixture before measurement. No repairs, fuel or
    -- stat changes after the trial begins. Retain native tyre friction/physics.
    for i=0,car:getPartCount()-1 do
        local part=car:getPartByIndex(i)
        part:setCondition(100)
        local item=part:getInventoryItem()
        if item then item:setCondition(item:getConditionMax()) end
        if string.find(part:getId(),"Tire",1,true) then
            part:setContainerContentAmount(part:getContainerCapacity())
        end
    end
    car:updatePartStats()
    local tank=car:getPartById("GasTank")
    if tank then tank:setContainerContentAmount(tank:getContainerCapacity()) end
    local battery=car:getBattery()
    if battery and battery:getInventoryItem() then battery:getInventoryItem():setCurrentUsesFloat(1) end
end
local function sample(H,s,current,kind)
    if current<(s.sampleAt or 0) then return end
    local car=s.car
    local fx,fy=heading(car)
    local native={};SCBridge.driveStatus(s.actor,native)
    local floor=call(call(car,"getSquare"),"getFloor")
    local sprite=call(call(floor,"getSprite"),"getName")
    local controller=car:getController()
    -- CarController is deliberately not exposed to Lua. Debug reflection reads
    -- its native value; calling a missing Lua method opens the debug console.
    local angle=field(controller,"vehicleSteering")
    local command=s.mode=="baseline" and field(field(s.actor,"bridgeDriver"),"command") or nil
    local body,tyre,pressure,friction=condition(car)
    local totalCondition=damage(car)
    if totalCondition~=s.lastCondition then parts(s,current);s.lastCondition=totalCondition end
    local row={trial=s.trial,mode=kind,script=car:getScriptName(),ms=current-s.trialAt,
        dt_ms=s.lastSample and current-s.lastSample or 0,x=car:getX(),y=car:getY(),fx=fx,fy=fy,
        speed_kmh=car:getCurrentSpeedKmHour(),cruise_kmh=s.cruise,input=native.steering,
        controller_angle=angle,wheel_angle=call(car,"getMaxWheelSteering"),
        clamp=car:getScript():getSteeringClamp(math.abs(car:getCurrentSpeedKmHour())),
        skid=call(car,"getMinWheelSkid"),surface=sprite,damage_sum=totalCondition,
        body_condition_sum=body,tyre_condition_min=tyre,tyre_pressure_min=pressure,tyre_friction_min=friction,
        health=call(call(s.actor,"getBodyDamage"),"getOverallBodyHealth"),
        zombies_killed=native.zombiesKilled,multiplier=getGameTime():getMultiplier(),
        state=native.state,along=native.along,remaining=native.remaining,
        lateral=native.lateral,target_kmh=command and field(command,"targetKmh") or native.cruiseKmh,
        forward=native.forward,brake=native.brake}
    local fields={}
    for _,key in ipairs(COLUMNS) do
        local value=row[key]
        fields[#fields+1]=value==nil and "" or tostring(value)
    end
    line("phase0-tracks-csv.txt",table.concat(fields,","),true)
    s.lastSample=current;s.sampleAt=current+50
    if s.lastFx then
        local da=math.atan2(s.lastFx*fy-s.lastFy*fx,s.lastFx*fx+s.lastFy*fy)
        s.rotation=(s.rotation or 0)+da
    end
    s.lastFx,s.lastFy=fx,fy
    s.native=native
end
local function planFixtures(SC,s,result)
    for _,fixture in ipairs(FIXTURES) do
        local route,why,raw=SC.ExpeditionRoute.planFromPoint(
            {x=fixture.sx,y=fixture.sy,z=0},{x=fixture.gx,y=fixture.gy,z=0},true)
        if not route then return false,fixture.name..": "..tostring(why) end
        fixture.route=route
        line("phase0-routes-tsv.txt",fixture.name.."\t"..fixture.sx..","..fixture.sy.."\t"
            ..fixture.gx..","..fixture.gy.."\t"..tostring(raw.fingerprint).."\t"
            ..tostring(raw.inferredJunctions).."\t"..raw.geometry,true)
        result("PASS","phase0_fixture_"..fixture.name,raw.geometry)
    end
    return true
end
local function trialSpec(index)
    local within=(index-1)%12
    local inputs={1,-1,0.5,-0.5}
    local speeds={6,12,20}
    return SCRIPTS[math.floor((index-1)/12)+1],speeds[math.floor(within/4)+1],inputs[within%4+1]
end
local function arena(s)
    s.arenaCursor=(s.arenaCursor or 0)+1
    local n=s.arenaCursor-1
    if n>80 then return false,"no loaded open arena" end
    local x,y=6444+(n%9-4)*4,5461+(math.floor(n/9)-4)*4
    local U=LivingFellows.GameplayUtil
    for dx=-25,25 do for dy=-25,25 do
        if dx*dx+dy*dy<=625 then
            if not free(x+dx,y+dy) then return nil end
            local a,b=square(x+dx,y+dy),square(x+dx+1,y+dy)
            local c=square(x+dx,y+dy+1)
            if not b or not c or U.edgeBlocked(a,b) or U.edgeBlocked(a,c) then return nil end
        end
    end end
    s.arena={x=x+.5,y=y+.5}
    return true
end
local function clean(SC,s)
    if s.actor then
        SC.Driving.release(s.actor,"phase0_trial_complete")
        if call(s.actor,"getVehicle") then
            local exited=SC.Vehicle.exit(s.actor,s.car)
            if not exited then return false end
        end
        if SC.Actor.remove(s.actor)~=true then return false end
        s.actor=nil
    end
    if s.car then s.car:permanentlyRemove();s.car=nil end
    fieldsByObject={}
    s.ticket=nil;s.settledAt=nil;s.started=nil;s.lastSample=nil;s.sampleAt=nil
    s.rotation=0;s.lastFx=nil;s.lastFy=nil;s.flip=nil
    return true
end
function Probe.step(H,current,check,result,setPhase)
    local SC=LivingFellows
    H.phase0=H.phase0 or {geometry={},queue={},cursor=0,baseline=0,baselineCount=0}
    local s=H.phase0
    local function fail(name,why)
        result("FAIL","phase0_"..name,tostring(why))
        if s.actor then SC.Driving.hold(s.actor) end
        s.failed=true;setPhase("drive_phase0_cleanup",current)
    end
    if H.phase=="drive_setup" then
        if current-H.phaseStartedAt<3000 then return end
        line("phase0-tracks-csv.txt",table.concat(COLUMNS,","))
        line("phase0-geometry-tsv.txt","script\tkind\tvalues")
        line("phase0-routes-tsv.txt","kind\tstart\tgoal\tfingerprint\tinferred\tgeometry")
        line("phase0-trials-tsv.txt","trial\tstatus\tseconds\trotation\tdetail")
        line("phase0-parts-tsv.txt","trial\tms\tpart\tcondition\tcontent\twheel_friction")
        local selected=H.config.driving_calibration_cases or ""
        if selected=="" then for i=1,36 do s.queue[#s.queue+1]=i end
        elseif selected~="baseline" then
            for v in selected:gmatch("%d+") do
                local i=tonumber(v)
                if i<1 or i>36 then return fail("case","case outside 1..36") end
                s.queue[#s.queue+1]=i
            end
        end
        -- Only disable background LF arrivals in this disposable measurement.
        for key,_ in pairs({productionEncounterEnabled=true,firstMeetingEnabled=true,
            factionEnabled=true,oddballsEnabled=true,banditFactionEnabled=true}) do SC.Config._overrides[key]=false end
        SC.Scheduler.unregister("decision")
        local ok,why=planFixtures(SC,s,result)
        if not ok then return fail("fixtures",why) end
        H.player:teleportTo(6444.5,5461.5,0)
        getGameTime():setTimeOfDay(12)
        setPhase("drive_phase0_load_arena",current);return
    end
    if H.phase=="drive_phase0_load_arena" then
        if current-H.phaseStartedAt<10000 then return end
        local okay,why=arena(s)
        if okay==nil then return end
        if not okay then return fail("arena",why) end
        -- Use ordinary native asphalt floors on the already checked flat pad.
        -- This is fixture construction, completed before any car is measured.
        for dx=-25,25 do for dy=-25,25 do
            if dx*dx+dy*dy<=625 then
                local tile=square(s.arena.x+dx,s.arena.y+dy)
                tile:addFloor("blends_street_01_0")
                local name=tile:getFloor():getSprite():getName()
                if not string.find(name,"blends_street",1,true) then return fail("asphalt_floor",name) end
            end
        end end
        result("PASS","phase0_arena",s.arena.x..","..s.arena.y.." native asphalt pad radius=25; built before trials")
        setPhase("drive_phase0_next",current);return
    end
    if H.phase=="drive_phase0_next" then
        s.cursor=s.cursor+1
        if s.queue[s.cursor] then
            s.trial=s.queue[s.cursor]
            s.script,s.cruise,s.input=trialSpec(s.trial)
            s.mode="circle";s.spawn={x=s.arena.x,y=s.arena.y};s.dir=IsoDirections.E
            setPhase("drive_phase0_spawn",current)
        else
            s.baseline=s.baseline+1
            local fixture=FIXTURES[s.baseline]
            local selected=H.config.driving_calibration_baseline or ""
            while fixture and selected~="" and fixture.name~=selected do
                s.baseline=s.baseline+1;fixture=FIXTURES[s.baseline]
            end
            if not fixture then
                result("PASS","phase0_measurements_saved","circles="..#s.queue.." baseline="..s.baselineCount.."; analyze tracks before accepting model")
                setPhase("finish",current);return
            end
            s.baselineCount=s.baselineCount+1
            s.fixture=fixture;s.mode="baseline";s.trial=fixture.name
            s.script=SCRIPTS[1];s.cruise=30;s.input=0
            local p,q=fixture.route.points[1],fixture.route.points[2]
            local dx,dy=q.x-p.x,q.y-p.y;local length=math.sqrt(dx*dx+dy*dy)
            s.expectedFx,s.expectedFy=dx/length,dy/length
            local width=number(q.width);local offset=width>=6 and width/4 or 0
            s.spawn={x=p.x-s.expectedFy*offset,y=p.y+s.expectedFx*offset}
            -- Diagonal spawns use the native matching octant too.
            if math.abs(dx)>math.abs(dy)*2 then s.dir=dx>0 and IsoDirections.E or IsoDirections.W
            elseif math.abs(dy)>math.abs(dx)*2 then s.dir=dy>0 and IsoDirections.S or IsoDirections.N
            elseif dx>0 then s.dir=dy>0 and IsoDirections.SE or IsoDirections.NE
            else s.dir=dy>0 and IsoDirections.SW or IsoDirections.NW end
            -- Centre the native physics/streaming window over the WHOLE route,
            -- with the observer on the roadside. The curve fixture extends 65
            -- tiles beyond its first junction and hit the old +/-60 boundary.
            local minX,maxX,minY,maxY=fixture.sx,fixture.sx,fixture.sy,fixture.sy
            for _,point in ipairs(fixture.route.points) do
                minX=math.min(minX,point.x);maxX=math.max(maxX,point.x)
                minY=math.min(minY,point.y);maxY=math.max(maxY,point.y)
            end
            H.player:teleportTo((minX+maxX)/2+12,(minY+maxY)/2+12,0)
            setPhase("drive_phase0_load_baseline",current)
        end
        return
    end
    if H.phase=="drive_phase0_load_baseline" then
        if current-H.phaseStartedAt>=10000 then setPhase("drive_phase0_spawn",current) end
        return
    end
    if H.phase=="drive_phase0_spawn" then
        if current-H.phaseStartedAt<500 then return end
        if not free(s.spawn.x,s.spawn.y) then return fail("spawn_square",s.trial.." "..s.spawn.x..","..s.spawn.y) end
        s.car=addVehicleDebug(s.script,s.dir,nil,square(s.spawn.x,s.spawn.y))
        if not s.car or not s.car:getSquare() then return fail("car_spawn",s.script) end
        local fx,fy=heading(s.car)
        if s.mode=="baseline" and fx*s.expectedFx+fy*s.expectedFy<0.7 then
            s.car:permanentlyRemove();s.car=nil
            if s.flip then return fail("spawn_heading","opposite octant failed") end
            local opposite={[IsoDirections.E]=IsoDirections.W,[IsoDirections.W]=IsoDirections.E,
                [IsoDirections.N]=IsoDirections.S,[IsoDirections.S]=IsoDirections.N,
                [IsoDirections.SE]=IsoDirections.NW,[IsoDirections.NW]=IsoDirections.SE,
                [IsoDirections.SW]=IsoDirections.NE,[IsoDirections.NE]=IsoDirections.SW}
            s.dir=opposite[s.dir];s.flip=true;H.phaseStartedAt=current;return
        end
        provision(s.car)
        if s.mode=="circle" and s.car:isDoingOffroad() then return fail("asphalt_surface",s.trial) end
        if not s.geometry[s.script] then geometry(s.car,s) end
        setPhase("drive_phase0_spawn_driver",current);return
    end
    if H.phase=="drive_phase0_spawn_driver" then
        if not SC.Vehicle.isStationary(s.car) then
            s.settledAt=nil
            if current-H.phaseStartedAt>20000 then return fail("car_settled",s.trial) end
            return
        end
        s.settledAt=s.settledAt or current
        if current-s.settledAt<800 then return end
        if not s.ticket then
            local pos=s.car:getPassengerPosition(0,"outside")
            local door=pos and s.car:getPassengerPositionWorldPos(pos,Vector3f.new())
            local best,bestDist
            if door then for dx=-2,2 do for dy=-2,2 do
                local x,y=math.floor(door:x())+dx,math.floor(door:y())+dy
                local sq=square(x,y)
                if free(x,y) and SC.GameplayUtil.isSquareFree(sq) then
                    local dist=s.car:getEnterSeatDistance(0,x+.5,y+.5)
                    if dist and dist>=0 and dist<=2.56 and (not bestDist or dist<bestDist) then best,bestDist=sq,dist end
                end
            end end end
            if not best then return fail("driver_door",s.trial) end
            local ticket,why=SC.Actor.beginSpawn(best,{recruited=true,
                identity={forename="Calibration",surname="Driver",gender="woman",outfit="Generic01"}})
            if not ticket then return fail("driver_spawn",why) end
            s.ticket=ticket;return
        end
        if not s.actor then
            local actor,why=SC.Actor.pollSpawn(s.ticket)
            if not actor then
                if why~="spawn_pending" or current-H.phaseStartedAt>30000 then return fail("driver_spawn",why) end
                return
            end
            s.actor=actor;s.actorAt=current
            actor:getInventory():AddItem(s.car:createVehicleKey())
        end
        if current-s.actorAt<1200 then return end
        local prepared,why=SC.Vehicle.preflightDriver(s.actor,s.car)
        if not prepared then return fail("board_preflight",why) end
        local okay,reason=SC.Driving.takeWheel(s.actor,s.car,{preflight=prepared})
        if not okay then return fail("board",reason) end
        if not SC.Driving.start(s.actor) then return fail("drive_start",s.trial) end
        s.initialDamage=damage(s.car);s.initialBody=condition(s.car);s.trialAt=current;s.rotation=0
        s.lastCondition=nil
        s.inputAt=nil;s.sampleAt=nil;s.lastSample=nil;s.lastFx=nil;s.lastFy=nil
        if s.mode=="baseline" then
            local ok,why=SC.Driving.followRoute(s.actor,s.fixture.route,30)
            if not ok then return fail("follow",why) end
        -- The native driver starts the engine only for a positive speed request.
        -- Its minimum 3 km/h request keeps the wheel centred until the engine
        -- starts and the measured step is issued on the next probe pulse.
        else SC.Driving.cruise(s.actor,3,0,false) end
        result("PASS","phase0_trial_started",s.trial.." "..s.script.." "..s.mode.." input="..s.input.." cruise="..s.cruise)
        setPhase("drive_phase0_measure",current);return
    end
    if H.phase=="drive_phase0_measure" then
        sample(H,s,current,s.mode)
        if not SC.Driving.isDriver(s.actor) then return fail("driver_lost",s.trial) end
        if s.mode=="circle" then
            if s.native and number(s.native.zombiesKilled)>0 then return fail("zombie_contact",s.trial) end
            if condition(s.car)<s.initialBody then return fail("body_damage",s.trial) end
            if number(call(call(s.actor,"getBodyDamage"),"getOverallBodyHealth"))<100 then return fail("driver_hurt",s.trial) end
            if not s.inputAt and call(s.car,"isEngineRunning")==true then
                s.inputAt=current
                SC.Driving.cruise(s.actor,s.cruise,s.input,false)
                line("phase0-trials-tsv.txt",s.trial.."\tinput_step\t"..((current-s.trialAt)/1000).."\t0\t"..s.input,true)
            end
            local displacement=math.sqrt((s.car:getX()-s.arena.x)^2+(s.car:getY()-s.arena.y)^2)
            if displacement>22 then return fail("arena_boundary",s.trial.." displacement="..displacement) end
            local elapsed=s.inputAt and current-s.inputAt or 0
            -- Enough steady samples for a complete geometric circle fit.
            if elapsed>30000 and math.abs(s.rotation)>math.pi*3 or elapsed>60000 then
                if math.abs(s.rotation)<math.pi*2 then return fail("incomplete_circle",s.trial) end
                line("phase0-trials-tsv.txt",s.trial.."\tcomplete\t"..((current-s.trialAt)/1000).."\t"..s.rotation.."\t",true)
                -- Measure easing again at cruising speed, after the circle fit
                -- is complete. These rows carry mode=response, not circle.
                s.responseStage=1;s.responseAt=current
                SC.Driving.cruise(s.actor,s.cruise,s.input*0.6,false)
                line("phase0-trials-tsv.txt",s.trial.."\tresponse_step_down\t"..((current-s.trialAt)/1000)
                    .."\t0\t"..(s.input*0.6),true)
                setPhase("drive_phase0_response",current)
            elseif not s.inputAt and current-s.trialAt>20000 then return fail("engine_start",s.trial) end
        else
            local native=s.native or {}
            local d=math.sqrt((s.car:getX()-s.fixture.gx)^2+(s.car:getY()-s.fixture.gy)^2)
            if native.reason=="arrived" or native.state=="arrived" or
                (d<5 and math.abs(s.car:getCurrentSpeedKmHour())<1 and current-s.trialAt>10000) then
                line("phase0-trials-tsv.txt",s.trial.."\tcomplete\t"..((current-s.trialAt)/1000).."\t"..s.rotation.."\tdistance="..d,true)
                result("PASS","phase0_baseline_"..s.trial,"distance="..d.." state="..tostring(native.state).." reason="..tostring(native.reason)
                    .." native_zombie_contacts="..number(native.zombiesKilled).." damage_change="..(damage(s.car)-s.initialDamage))
                SC.Driving.hold(s.actor);setPhase("drive_phase0_cleanup",current)
            elseif current-s.trialAt>150000 then
                -- A blocked baseline is observed behaviour, never evidence of a
                -- clean turn. Retain its complete trace and inspect the others.
                line("phase0-trials-tsv.txt",s.trial.."\tblocked\t"..((current-s.trialAt)/1000).."\t"..s.rotation
                    .."\tdistance="..d.." state="..tostring(native.state).." reason="..tostring(native.reason),true)
                result("PASS","phase0_baseline_recorded_blocked_"..s.trial,"distance="..d.." state="..tostring(native.state).." reason="..tostring(native.reason))
                SC.Driving.hold(s.actor);setPhase("drive_phase0_cleanup",current)
            end
        end
        return
    end
    if H.phase=="drive_phase0_response" then
        sample(H,s,current,"response")
        if condition(s.car)<s.initialBody then return fail("response_body_damage",s.trial) end
        if s.native and number(s.native.zombiesKilled)>0 then return fail("response_zombie_contact",s.trial) end
        local d=math.sqrt((s.car:getX()-s.arena.x)^2+(s.car:getY()-s.arena.y)^2)
        if d>22 then return fail("response_boundary",s.trial) end
        if current-s.responseAt<2000 then return end
        if s.responseStage==1 then
            s.responseStage=2;s.responseAt=current
            SC.Driving.cruise(s.actor,s.cruise,s.input,false)
            line("phase0-trials-tsv.txt",s.trial.."\tresponse_step_up\t"..((current-s.trialAt)/1000)
                .."\t0\t"..s.input,true)
        else SC.Driving.hold(s.actor);setPhase("drive_phase0_cleanup",current) end
        return
    end
    if H.phase=="drive_phase0_cleanup" then
        if not clean(SC,s) then
            if current-H.phaseStartedAt>20000 then result("FAIL","phase0_cleanup_timeout",tostring(s.trial));setPhase("finish",current) end
            return
        end
        if s.failed then setPhase("finish",current) else setPhase("drive_phase0_next",current) end
    end
end
return Probe
