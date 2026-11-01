-- SPDX-License-Identifier: MIT
-- Real window, indoor zombie, native car and autonomous door/seat transaction.
-- Fixture placement is confined to the disposable cloned world. Once spawned,
-- the companion moves exclusively through the ordinary decision/navigation code.
local Probe={}
local function call(object,name,...)
    if not object then return nil end
    local okay,value=pcall(function(...) return object[name](object,...) end,...)
    if okay then return value end
end
local function free(square,U)
    return square and call(square,"getChunk") and U.isSquareFree(square)
end
local function windowFixture(square,U)
    local objects=call(square,"getObjects")
    for index=0,math.min(tonumber(call(objects,"size")) or 0,32)-1 do
        local object=objects:get(index)
        if instanceof(object,"IsoWindow") and call(object,"IsOpen")==false
            and call(object,"isSmashed")==false then
            local north=call(object,"getNorth")
            local x,y=square:getX(),square:getY()
            local other=U.gridSquare(x-(north and 0 or 1),y-(north and 1 or 0),0)
            if other then
                local inside,outside
                if square:getRoom() and not other:getRoom() then inside,outside=square,other
                elseif other:getRoom() and not square:getRoom() then inside,outside=other,square end
                if inside and free(inside,U) then
                    local dx,dy=outside:getX()-inside:getX(),outside:getY()-inside:getY()
                    local spawn=U.gridSquare(outside:getX()+dx*2,outside:getY()+dy*2,0)
                    if free(spawn,U) and not spawn:getRoom() then
                        for _,depth in ipairs({7,9}) do
                            local center=U.gridSquare(outside:getX()+dx*depth,outside:getY()+dy*depth,0)
                            local clear=center~=nil
                            if clear then
                                for ax=-2,2 do for ay=-2,2 do
                                    local patch=U.gridSquare(center:getX()+ax,center:getY()+ay,0)
                                    if not free(patch,U) or patch:getRoom() then clear=false end
                                end end
                            end
                            if clear then return {window=object,inside=inside,outside=outside,
                                spawn=spawn,carSquare=center,dx=dx,dy=dy} end
                        end
                    end
                end
            end
        end
    end
end
local function finish(H,current,result,setPhase,okay,name,detail)
    result(okay and "PASS" or "FAIL",name,detail)
    local state=H.followerBoarding
    if state then
        if state.car then
            if call(H.player,"getVehicle")==state.car then call(state.car,"exit",H.player) end
            if state.actor and call(state.actor,"getVehicle")==state.car then call(state.car,"exit",state.actor) end
        end
        if state.actor then pcall(SurvivorCompanion.Actor.remove,state.actor) end
        if state.zombie then call(state.zombie,"removeFromWorld");call(state.zombie,"removeFromSquare") end
    end
    setPhase("finish",current)
end
function Probe.step(H,current,check,result,setPhase)
    local SC,U=SurvivorCompanion,SurvivorCompanion.GameplayUtil
    local state=H.followerBoarding
    local function done(okay,name,detail) return finish(H,current,result,setPhase,okay,name,detail) end
    if H.phase=="follower_car_ai_setup" then
        if #SC.Registry.records()==0 and current-H.phaseStartedAt<10000 then return end
        for _,actor in ipairs(SC.Registry.living()) do pcall(SC.Actor.remove,actor) end
        state={x=math.floor(H.player:getX()),y=math.floor(H.player:getY()),scan=0,started=current}
        H.followerBoarding=state
        setPhase("follower_car_ai_survey",current);return
    end
    if not state then return done(false,"follower_board_fixture","missing state") end
    if current-state.started>150000 then return done(false,"follower_board_deadline",H.phase) end
    if H.phase=="follower_car_ai_survey" then
        for _=1,32 do
            local index=state.scan;state.scan=index+1
            if index>=41*41 then return done(false,"follower_board_window","no closed window beside an open car patch") end
            local square=U.gridSquare(state.x+index%41-20,state.y+math.floor(index/41)-20,0)
            local fixture=square and windowFixture(square,U)
            if fixture then
                state.fixture=fixture
                H.clearZombiesNear(fixture.carSquare,24)
                local okay,car=pcall(addVehicleDebug,"Base.CarNormal",IsoDirections.E,nil,fixture.carSquare)
                if not okay or not car then return done(false,"follower_board_car",tostring(car)) end
                state.car=car;car:setAlarmed(false)
                for part=0,car:getPartCount()-1 do
                    local door=car:getPartByIndex(part):getDoor()
                    if door then door:setLocked(false) end
                end
                local observer=U.gridSquare(fixture.carSquare:getX()+fixture.dx*3,
                    fixture.carSquare:getY()+fixture.dy*3,0)
                if not free(observer,U) then return done(false,"follower_board_observer","no safe observer square") end
                H.player:teleportTo(observer:getX()+.5,observer:getY()+.5,0)
                local ticket,why=SC.Actor.beginSpawn(fixture.spawn,{recruited=true,
                    identity={forename="Boarding",surname="Follower",gender="woman",outfit="Generic01"}})
                if not ticket then return done(false,"follower_board_spawn",tostring(why)) end
                state.ticket=ticket
                result("PASS","follower_board_fixture","window="..U.squareKey(fixture.inside)
                    .." companion="..U.squareKey(fixture.spawn).." car="..U.squareKey(fixture.carSquare))
                setPhase("follower_car_ai_spawn",current);return
            end
        end
        return
    elseif H.phase=="follower_car_ai_spawn" then
        local actor,why=SC.Actor.pollSpawn(state.ticket)
        if not actor then
            if why~="spawn_pending" or current-H.phaseStartedAt>12000 then return done(false,"follower_board_spawn",tostring(why)) end
            return
        end
        state.actor=actor
        local item=actor:getInventory():AddItem("Base.Crowbar")
        actor:setPrimaryHandItem(item)
        local id=SC.Registry.idOf(actor)
        SC.Commands.issue(id,"follow",nil,H.player)
        SC.Commands.issue(id,"set_combat_doctrine",{doctrine="weapons_free"},H.player)
        SC.Commands.issue(id,"set_ride_with_player",{enabled=true},H.player)
        actor:faceLocationF(state.fixture.inside:getX()+.5,state.fixture.inside:getY()+.5)
        local square=state.fixture.inside
        local zombies=addZombiesInOutfit(square:getX(),square:getY(),0,1,nil,0)
        state.zombie=zombies and zombies:get(0)
        if not state.zombie then return done(false,"follower_board_zombie","native spawn failed") end
        setPhase("follower_car_ai_engage",current);return
    elseif H.phase=="follower_car_ai_engage" then
        local combat=SC.Combat.peek(state.actor)
        if combat and combat.target==state.zombie then
            if not call(call(state.zombie,"getCurrentSquare"),"getRoom") then
                return done(false,"follower_board_indoor_target","zombie left room before the initial lock was observed")
            end
            result("PASS","follower_board_target_lock","real perception acquired the indoor zombie")
            if state.car:enter(0,H.player)~=true then return done(false,"follower_board_player_entry","native entry failed") end
            state.boardAt=current;state.startDistance=U.distance(state.actor,state.car)
            state.nextTrace=current;state.ran=false
            setPhase("follower_car_ai_board",current);return
        end
        if current-H.phaseStartedAt>15000 then
            local runtime=SC.GameplayUtil.peekActorState(state.actor) or {}
            return done(false,"follower_board_target_lock","combat="..tostring(combat and combat.lastAction)
                .." decision="..tostring(runtime.decision and runtime.decision.intent))
        end
    elseif H.phase=="follower_car_ai_board" then
        state.ran=state.ran or call(state.actor,"isRunning")==true
        local combat=SC.Combat.peek(state.actor)
        if current>=state.nextTrace then
            state.nextTrace=current+1000
            local decision=SC.Decision.peek(state.actor) or {}
            print("SC_FOLLOWER_BOARD|elapsed="..(current-state.boardAt).." intent="..tostring(decision.intent)
                .." kind="..tostring(decision.currentKey).." target="..tostring(combat and combat.target)
                .." distance="..U.distance(state.actor,state.car).." running="..tostring(call(state.actor,"isRunning")))
        end
        if call(state.actor,"getVehicle")==state.car then
            local seated,car,seat=SC.Vehicle.isNativeSeated(state.actor)
            local indoors=call(call(state.zombie,"getCurrentSquare"),"getRoom")~=nil
            check("follower_board_ran",state.ran,"native running observed on the physical approach")
            check("follower_board_target_released",not combat or combat.target~=state.zombie,"indoor target no longer owns the follower")
            check("follower_board_zombie_still_indoor",indoors and call(state.zombie,"isDead")==false,"no need to kill the confined zombie before departure")
            if not check("follower_board_native_seat",seated==true and car==state.car and seat>0,
                "seat="..tostring(seat).." elapsed_ms="..(current-state.boardAt).." start_distance="..state.startDistance) then
                return done(false,"follower_board_native_seat","native seat proof failed")
            end
            state.seatedAt=current
            setPhase("follower_car_ai_seated",current);return
        end
        if current-state.boardAt>45000 then return done(false,"follower_board_native_seat","boarding exceeded45s") end
    elseif H.phase=="follower_car_ai_seated" then
        if call(state.actor,"getVehicle")~=state.car or call(H.player,"getVehicle")~=state.car then
            return done(false,"follower_board_stays_seated","occupant left during the10s settled observation")
        end
        if current-state.seatedAt>=10000 then
            pcall(function() getCore():TakeFullScreenshot(tostring(H.config.run_id).."-follower-boarded.png") end)
            return done(true,"follower_board_stays_seated","10s native update/render after passenger boarding")
        end
    end
end
SCRealSandboxHarnessProbes=SCRealSandboxHarnessProbes or {}
SCRealSandboxHarnessProbes.SCFollowerBoardingProbe=Probe
return Probe
