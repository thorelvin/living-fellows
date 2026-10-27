-- Isolated native regression: stock beds, four facings, full get-up and a
-- standing actor with the saved-position/cleared-flags failure signature.
local run={step=0,next=0,index=1}
local function log(text)
    print("BED_EXIT|"..text)
    local w=getFileWriter("SurvivorCompanionHarness/bed-exit.log",true,true)
    if w then w:write(text.."\n") w:close() end
end
local function insideBed(actor)
    return actor:getX()>=run.x and actor:getX()<run.x+run.grid:getWidth()
        and actor:getY()>=run.y and actor:getY()<run.y+run.grid:getHeight()
end
local function inventory()
    local result={}
    for _,item in ipairs(SurvivorCompanion.GameplayUtil.inventoryItemsDeep(run.actor:getInventory(),512,12)) do result[item]=true end
    return result
end
local function verifyInventory()
    local current=inventory()
    for item in pairs(run.items) do assert(current[item],"bed exit lost an exact carried item") end
    for item in pairs(current) do assert(run.items[item],"bed exit added a carried item") end
    assert(SurvivorCompanion.Registry.byId(run.id).actor==run.actor,"bed exit replaced the native actor")
end
local function stockBeds()
    local found,usable={},{}
    local manager=SeatingManager.getInstance()
    for sheet=1,4 do for index=0,127 do
        local name="furniture_bedding_"..string.format("%02d",sheet).."_"..index
        local sprite=IsoSpriteManager.instance:getSprite(name)
        local grid=sprite and sprite:getSpriteGrid()
        if grid and grid:getWidth()*grid:getHeight()==2 then
            local facing=manager:getFacingDirection(sprite)
            local sample=IsoObject.new(getCell(),getSpecificPlayer(0):getCurrentSquare(),name)
            local positions=manager:getTilePositionCount(sample)
            if facing=="N" or facing=="S" or facing=="E" or facing=="W" then
                local group=tostring(sprite:getProperties():get("GroupName") or "")
                local value={grid=grid,sprite=sprite,facing=facing,group=group,positions=positions}
                if not found[facing] or group:lower():find("hospital",1,true) then found[facing]=value end
                if positions>0 and (not usable[facing] or group:lower():find("hospital",1,true)) then usable[facing]=value end
            end
        end
    end end
    local cases={}
    for _,facing in ipairs({"N","S","E","W"}) do
        local value=usable[facing] or found[facing]
        assert(value,"native bed missing: "..facing)
        cases[#cases+1]=value
    end
    return cases
end
local function placeBed()
    local SC=SurvivorCompanion
    local case=run.cases[run.index]
    run.grid=case.grid
    local origin=run.actor:getCurrentSquare()
    local best,distance
    for dx=-12,12 do for dy=-12,12 do
        local x,y,z=origin:getX()+dx,origin:getY()+dy,origin:getZ()
        local centre=getCell():getGridSquare(x,y,z)
        local room=centre and centre:getRoom()
        local clear=true
        -- Leave all sides usable, so a facing-specific stock entry post is
        -- never hidden inside the gym equipment or a wall in this fixture.
        for gx=-1,run.grid:getWidth() do for gy=-1,run.grid:getHeight() do
            local tile=getCell():getGridSquare(x+gx,y+gy,z)
            if not tile or tile:getRoom()~=room or not SC.GameplayUtil.isClearActorSpawnSquare(tile) then clear=false end
        end end
        local score=dx*dx+dy*dy
        if clear and (not best or score<distance) then best,distance={x=x,y=y,z=z},score end
    end end
    assert(best,"no clear floor for the native bed fixture")
    run.x,run.y,run.z=best.x,best.y,best.z
    -- Fixture setup only: put this same actor on a verified clear aisle. Beds
    -- need their facing-specific native entry posts, not just empty mattress
    -- squares. This can select clear outdoor floor if the house is cramped.
    assert(SC.Actor.recover(run.actor,getCell():getGridSquare(run.x-1,run.y,run.z)),
        "could not stage the same actor beside the clear test bed")
    run.objects={}
    for gx=0,run.grid:getWidth()-1 do for gy=0,run.grid:getHeight()-1 do
        local tile=getCell():getGridSquare(run.x+gx,run.y+gy,run.z)
        local sprite=run.grid:getSprite(gx,gy)
        local object=IsoObject.new(getCell(),tile,sprite:getName())
        tile:AddTileObject(object)
        run.objects[#run.objects+1]=object
        SC.GameplayUtil.invalidateSpatial(tile)
    end end
    log("CASE facing="..case.facing.." group="..case.group.." sprite="..case.sprite:getName()
        .." at="..run.x..":"..run.y..":"..run.z.." positions="..case.positions)
end
local function tick()
    local now=getTimestampMs()
    if now<run.next then return end
    local SC=SurvivorCompanion
    local player=getSpecificPlayer(0)
    if not SC or not SC.NativeActions or not SC.Registry or not player or not player:getCurrentSquare() then return end
    if run.step==0 then
        player:setGodMod(true) player:setGhostMode(true)
        if SC.UI and SC.UI.instance then SC.UI.instance:setVisible(false) end
        for _,record in ipairs(SC.Registry.snapshot()) do
            local actor=record.actor
            if actor and actor~=player and actor:getCurrentSquare() and actor:getCurrentSquare():getRoom()
                and SC.BaseLife.isInside(actor) and SC.Commands.peek(actor).recruited
                and not (SC.BaseWatch and SC.BaseWatch.isLeaderId(record.id)) then
                run.actor,run.id=actor,record.id break
            end
        end
        if not run.actor then run.next=now+1000 return end
        run.actor:setGodMod(true)
        SC.Downtime.cancel(run.actor,"bed_acceptance_setup")
        SC.Decision.cancelWork(run.actor,"bed_acceptance_setup")
        SC.ActionSupervisor.cancel(run.actor,"bed_acceptance_setup",nil,true)
        assert(SC.BaseLife.setDuty(run.id,false))
        assert(SC.Commands.issue(run.id,"stay",{},player))
        local decision=SC.Decision.update
        SC.Decision.update=function(actor,...)
            if actor==run.actor then return true,"bed_acceptance_manual" end
            return decision(actor,...)
        end
        run.items=inventory() run.cases=stockBeds()
        log("START native bed exit actor="..run.id)
        placeBed()
        run.step,run.next,run.deadline=run.cases[run.index].positions>0 and 1 or 3,now+1000,now+45000
    elseif run.step==1 then
        if not run.requested then
            local started,reason=SC.GameplayUtil.move(run.actor,"walk",{action="rest_bed",object=run.objects[1]})
            if started then run.requested=true log("ENTER "..tostring(reason)) end
        end
        if run.requested and SC.NativeActions.bedStatus(run.actor)=="entered" and run.actor:isOnBed() then
            assert(run.actor:getSitOnFurnitureObject(),"native bed reference missing before get-up")
            if run.index==2 then
                run.actor:setAsleep(true)
                SC.Downtime._sleepStateForTests(run.actor,{kind="rest_bed",object=run.objects[1],
                    actionAccepted=true,sleepStarted=true,commandSerial=SC.Commands.peek(run.actor).commandSerial})
                assert(SC.Downtime.cancel(run.actor,"native_acceptance_new_order"),"sleep cancellation failed")
                assert(not run.actor:isAsleep(),"cancellation left the companion asleep")
            end
            local left,reason=SC.NativeActions.leaveSeating(run.actor)
            assert(not left and reason=="standing_from_bed" and run.actor:isOnBed()
                and run.actor:getSitOnFurnitureObject(),"bed cleanup skipped native get-up")
            run.step,run.next,run.deadline=2,now+100,now+15000
        else assert(now<run.deadline,"bed entry did not settle") run.next=now+100 end
    elseif run.step==2 then
        if run.actor:getCurrentActionContextStateName():lower()=="getup" then run.sawGetup=true end
        local standing,reason=SC.NativeActions.leaveSeating(run.actor)
        if standing then
            assert(run.sawGetup,"native get-up animation was not observed")
            assert(not run.actor:isOnBed() and run.actor:isCollidable(),"bed exit did not restore normal collision")
            assert(not insideBed(run.actor),"native get-up left the physical body inside the bed")
            verifyInventory()
            log("PASS native get-up facing="..run.cases[run.index].facing.." reason="..tostring(reason))
            run.step,run.next=3,now+1500
        else assert(now<run.deadline,"bed get-up did not release: "..tostring(reason)) run.next=now+100 end
    elseif run.step==3 then
        -- Construct the reported post-restart signature without retaining any
        -- bed action: standing/idle flags but coordinates inside the mattress.
        local tile=run.objects[1]:getSquare()
        local old=run.actor:getCurrentSquare()
        old:getMovingObjects():remove(run.actor)
        run.actor:setX(tile:getX()+0.84) run.actor:setY(tile:getY()+0.72)
        run.actor:setLastX(run.actor:getX()) run.actor:setLastY(run.actor:getY())
        run.actor:setCurrent(tile) tile:getMovingObjects():add(run.actor)
        run.actor:setOnBed(false) run.actor:setSitOnFurnitureObject(nil)
        run.actor:setCollidable(false)
        SC.GameplayUtil.invalidateSpatial(run.actor)
        assert(SC.NativeActions.seatingStatus(run.actor)=="bed","saved bed-footprint overlap was not recognized")
        run.step,run.next,run.deadline=4,now+100,now+10000
    elseif run.step==4 then
        local ready,reason=SC.NativeActions.leaveSeating(run.actor)
        if ready then
            assert(not insideBed(run.actor) and run.actor:isCollidable(),"saved standing actor remains in the mattress")
            assert(math.floor(run.actor:getZ())==run.z,"bed recovery changed floors")
            assert(run.actor:getCurrentSquare():getRoom()==run.objects[1]:getSquare():getRoom(),"bed recovery crossed a room boundary")
            verifyInventory()
            log("PASS saved-standing recovery facing="..run.cases[run.index].facing.." collision=true actor-and-items=unchanged")
            for _,object in ipairs(run.objects) do
                local tile=object:getSquare() tile:RemoveTileObject(object)
                SC.GameplayUtil.invalidateSpatial(tile)
            end
            run.index=run.index+1 run.requested=nil run.sawGetup=nil
            if run.index>#run.cases then
                log("PASS native bed exit acceptance complete") run.step,run.next=99,now+1000000
            else
                placeBed()
                run.step,run.next,run.deadline=run.cases[run.index].positions>0 and 1 or 3,now+1500,now+45000
            end
        else assert(now<run.deadline,"saved bed recovery did not finish: "..tostring(reason)) run.next=now+100 end
    end
end
Events.OnTick.Add(function()
    local okay,reason=pcall(tick)
    if not okay then log("FAIL "..tostring(reason)) run.step,run.next=99,getTimestampMs()+1000000 end
end)
