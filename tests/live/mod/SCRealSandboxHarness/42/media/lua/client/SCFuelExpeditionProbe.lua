-- SPDX-License-Identifier: MIT
-- One public fuel expedition in a disposable seed clone. No native objects or
-- gameplay functions are replaced. The fixture supplies cans and, if needed,
-- a real disconnected generator at a real station after grid shutdown.
local P={}
local function clearFixtureZombies(U,x,y,radius)
    local zombies=getCell():getZombieList()
    local removed=0
    for i=zombies:size()-1,0,-1 do
        local z=zombies:get(i)
        if (z:getX()-x)^2+(z:getY()-y)^2<=radius*radius then
            z:removeFromWorld() z:removeFromSquare() zombies:remove(z) removed=removed+1
        end
    end
    return removed
end
local function call(o,m,...)
    local okay,value=pcall(function(...) return o[m](o,...) end,...)
    if okay then return value end
end
local function photo(H,label)
    pcall(function()
        for _=1,8 do if getCore():getZoom(0)<1.8 then getCore():doZoomScroll(0,1) end end
        getCore():TakeFullScreenshot(H.config.run_id.."-fuel-"..label..".png")
    end)
end
local function finish(H,current,setPhase)
    if H.fuelExpedition and H.fuelExpedition.originalShut then
        getSandboxOptions():set("ElecShutModifier",H.fuelExpedition.originalShut) getSandboxOptions():toLua()
    end
    setPhase("finish",current)
end
local function fail(H,current,result,setPhase,name,why)
    photo(H,"blocked-"..name)
    result("FAIL",name,tostring(why))
    finish(H,current,setPhase)
end
local function returned(H,f,current,check,setPhase,fuel,release)
    local SC=SurvivorCompanion
    if release then
        local okay=SC.ExpeditionPrototype.finishAtPlayer(H.player)
        if not okay then return end
    end
    if getSpecificPlayer(1)~=nil then return end
    check("fuel_live_tank_transfer",fuel.carFuelAdded>0,"native tank increase="..fuel.carFuelAdded.." L")
    check("fuel_live_pump_transfer",fuel.pumpLitres>0,"native pump collection="..fuel.pumpLitres.." L")
    check("fuel_live_stopped_engine",f.car:isEngineRunning()==false,"returned car engine is off")
    if f.generator then
        check("fuel_live_generator_restored",f.generator:isActivated()==f.wasRunning and f.generator:isConnected()==f.wasConnected,
            "running="..tostring(f.generator:isActivated())..";connected="..tostring(f.generator:isConnected()))
    else
        check("fuel_live_saved_generator_cleanup",fuel.cleaned==true and fuel.generator==nil,
            "saved return retains completed generator cleanup; native stop/disconnect recorded in the preceding trip")
    end
    check("fuel_live_solo_return",getSpecificPlayer(1)==nil,"normal expedition release restored the primary view")
    photo(H,"home")
    SC.UI.open("expeditions",f.crew.id)
    local detail=SC.UI.instance and SC.UI.instance.detail
    if detail and detail.expeditionDraft then detail.expeditionDraft.showReports=true detail:rebuild(false) end
    setPhase("fuel_expedition_deliver",current)
end
function P.step(H,current,check,result,setPhase)
    local SC=SurvivorCompanion
    local U=SC.GameplayUtil
    local f=H.fuelExpedition
    if H.phase=="fuel_expedition_setup" then
        local base=SC.BaseLife.active()
        if (not base or #SC.Registry.snapshot()==0) and current-H.phaseStartedAt<15000 then return end
        if not base then return fail(H,current,result,setPhase,"fuel_live_camp","seed has no camp") end
        local restored=SC.ExpeditionPrototype.current()
        if restored then
            if not restored.scout or not restored.scout.fuel then return fail(H,current,result,setPhase,"fuel_live_prior_trip","seed has another mission kind") end
            local fuel=restored.scout.fuel
            local car=SC.Vehicle.loadedBySqlId(restored.scout.vehicle.sqlId)
            local actor=restored.leader and restored.leader.actor
            if restored.restoring or not car or not actor or not actor:getCurrentSquare() then
                if current-H.phaseStartedAt<60000 then return end
                return fail(H,current,result,setPhase,"fuel_live_reload_ready","saved crew/car did not load")
            end
            local g=fuel.generator
            local generator=g and SC.BaseLife.resolveObject(g.target)
            if g and not generator and current-H.phaseStartedAt<60000 then return end
            f={resumed=true,tripId=fuel.tripId,crew=restored.leader,car=car,carId=restored.scout.vehicle.sqlId,
                generator=generator,wasRunning=g and g.wasRunning,wasConnected=g and g.wasConnected,
                nextTrace=0,seen={}}
            H.fuelExpedition=f
            clearFixtureZombies(U,actor:getX(),actor:getY(),80) SC.Senses.reset(actor)
            if SC.UI.instance then SC.UI.instance:setCollapsed(true) end
            check("fuel_live_reload_resume",fuel.pumpLitres>0 and fuel.carFuelAdded>0,
                "saved native progress: pumped="..fuel.pumpLitres..";car="..fuel.carFuelAdded..";receipts="..#fuel.acquisitions)
            photo(H,"reload-resumed") setPhase("fuel_expedition_work",current)
            return
        end
        local debrief=SC.ExpeditionPrototype.lastDebrief()
        local delivery=debrief and debrief.kind=="fuel" and debrief.integration
        if delivery then
            local member=delivery.members[1]
            local crew=member and SC.Registry.byId(member.id)
            local car=SC.Vehicle.loadedBySqlId(delivery.carId)
            if not crew or not crew.actor or not car then
                if current-H.phaseStartedAt<60000 then return end
                return fail(H,current,result,setPhase,"fuel_live_delivery_reload","saved crew/car did not load")
            end
            f={resumed=true,tripId=delivery.tripId,crew=crew,car=car,carId=delivery.carId,nextTrace=0,seen={}}
            H.fuelExpedition=f
            check("fuel_live_delivery_reload",delivery.fuelWork.endReason=="fuel_target_met",
                "resume actual returned cargo without creating or moving any fixture item")
            returned(H,f,current,check,setPhase,delivery.fuelWork,false)
            return
        end
        local crew
        for _,record in ipairs(SC.Registry.snapshot()) do
            if record.recruited and record.actor and not U.isDead(record.actor) and SC.BaseLife.withinWorkReach(record.actor) then crew=record break end
        end
        if not crew then return fail(H,current,result,setPhase,"fuel_live_crew","no loaded camp companion") end
        local storage,container
        for _,category in ipairs({"tools","general"}) do
            for _,row in ipairs(SC.BaseLife.storageRows(category,true)) do
                local c=SC.BaseLife.resolveContainer(row)
                if c and row.deposits~=false then storage,container=row,c break end
            end
            if storage then break end
        end
        if not storage then
            -- Reuse real camp furniture in this clone; do not require an old
            -- save to contain this new mission's supplies or marked shelf.
            local scan=H.fuelStorageScan or {index=0}
            H.fuelStorageScan=scan
            local x,y,z=U.position(crew.actor)
            for _=1,64 do
                if scan.index>=625 then break end
                local index=scan.index scan.index=index+1
                local tile=U.gridSquare(math.floor(x)-12+index%25,math.floor(y)-12+math.floor(index/25),math.floor(z))
                if tile and SC.BaseLife.isInside(tile) then
                    local objects=tile:getObjects()
                    for i=0,math.min(objects:size(),48)-1 do
                        local object=objects:get(i)
                        local c=call(object,"getContainer")
                        if c and c:getFreeCapacity(crew.actor)>25 then
                            local okay,row=SC.BaseLife.registerStorage(object,"tools")
                            if okay then storage,container=row,c H.fuelMarkedShelfId=row.id break end
                        end
                    end
                end
                if storage then break end
            end
            if not storage and scan.index<625 then return end
            if not storage then return fail(H,current,result,setPhase,"fuel_live_storage","no reachable camp shelf with 25 units of free space") end
        end
        local actor=crew.actor
        result("PASS","fuel_live_quiet_fixture","clone-only nearby zombies removed="..clearFixtureZombies(U,actor:getX(),actor:getY(),45))
        SC.Commands.issue(crew.id,"stay",{},H.player)
        SC.Downtime.cancel(actor,"fuel_live_fixture")
        SC.BaseWork.cancel(actor,"fuel_live_fixture")
        local bag=instanceItem("Base.Bag_BigHikingBag")
        if bag then
            local slot=bag:canBeEquipped()
            local old=call(actor,"getWornItem",slot)
            if old then actor:removeWornItem(old) end
            actor:getInventory():AddItem(bag) actor:setWornItem(slot,bag) actor:resetModelNextFrame()
        end
        local cans={}
        for index=1,2 do
            local item=instanceItem("Base.PetrolCan")
            if not item then return fail(H,current,result,setPhase,"fuel_live_can","native gas can unavailable") end
            item:getFluidContainer():adjustAmount(index==1 and 2 or 0)
            container:AddItem(item) item:syncItemFields()
            cans[#cans+1]={item=item,id=U.itemStableId(item,true),nativeId=item:getID()}
        end
        local x,y=U.position(actor)
        WorldMapVisited.getInstance():setKnownInSquares(math.max(0,x-5000),math.max(0,y-5000),math.min(30000,x+5000),math.min(30000,y+5000))
        getGameTime():setTimeOfDay(12)
        local car,best
        for _,vehicle in ipairs(SC.Vehicle.loadedVehicles()) do
            local d=U.distance(actor,vehicle)
            if SC.Vehicle.isStationary(vehicle) and d<40 and (not best or d<best)
                and call(vehicle,"getMaxPassengers") and vehicle:getMaxPassengers()>0 then car,best=vehicle,d end
        end
        if not car then
            local spot,fallback
            for radius=6,24 do
                for dx=-radius,radius do for dy=-radius,radius do
                    if math.max(math.abs(dx),math.abs(dy))==radius then
                        local tile=U.gridSquare(math.floor(base.core.x)+dx,math.floor(base.core.y)+dy,0)
                        if tile and tile:isOutside() and U.isSquareFree(tile) and SC.BaseLife.withinWorkReach(tile) then
                            local clear=true
                            for ax=-2,2 do for ay=-3,3 do
                                local around=U.gridSquare(tile:getX()+ax,tile:getY()+ay,0)
                                if not around or not U.isSquareFree(around) or not around:isOutside() then clear=false end
                            end end
                            if clear then
                                fallback=fallback or tile
                                local name=call(call(tile,"getFloor"),"getSpriteName") or call(call(call(tile,"getFloor"),"getSprite"),"getName") or ""
                                if name:find("blends_street_",1,true) then spot=tile break end
                            end
                        end
                    end
                end if spot then break end end
                if spot then break end
            end
            spot=spot or fallback
            if spot then
                local okay,vehicle=pcall(addVehicleDebug,"Base.CarNormal",IsoDirections.N,nil,spot)
                if okay and vehicle and vehicle:getSquare() then car=vehicle end
            end
        end
        if not car then return fail(H,current,result,setPhase,"fuel_live_car_fixture","no safe outdoor fixture space near camp") end
        car:setAlarmed(false)
        for i=0,car:getPartCount()-1 do local door=car:getPartByIndex(i):getDoor() if door then door:setLocked(false) end end
        local cx,cy=math.floor(car:getX()),math.floor(car:getY())
        local begun,why=SC.BaseLife.beginZone("parking",{x=cx-5,y=cy-5,z=0})
        local marked,zone
        if begun then marked,zone=SC.BaseLife.finishZone({x=cx+5,y=cy+5,z=0},"Fuel expedition test parking") end
        if not marked then return fail(H,current,result,setPhase,"fuel_live_parking_fixture",zone or why) end
        local key=car:createVehicleKey()
        if key then actor:getInventory():AddItem(key) end
        -- Use a physical outdoor supply crate for this pump/generator scenario;
        -- indoor porch/storage routing is covered separately by the project gate.
        local crateSquare
        for dx=-5,5 do for dy=-5,5 do
            local tile=U.gridSquare(cx+dx,cy+dy,0)
            if not crateSquare and math.abs(dx)+math.abs(dy)>=5 and tile and tile:isOutside()
                and U.isSquareFree(tile) and SC.BaseLife.isInside(tile) then crateSquare=tile end
        end end
        if crateSquare then
            local object=IsoThumpable.new(getCell(),crateSquare,"carpentry_01_16",false,{})
            object:setIsContainer(true) object:setContainer(ItemContainer.new("crate",crateSquare,object))
            object:getContainer():setCapacity(100) crateSquare:AddSpecialObject(object)
            local okay,row=SC.BaseLife.registerStorage(object,"tools")
            if okay then
                local target=object:getContainer()
                for _,receipt in ipairs(cans) do assert(U.transferItemVerified(container,target,receipt.item)) end
                storage,container=row,target
                if H.fuelMarkedShelfId then assert(SC.BaseLife.removeStorage(H.fuelMarkedShelfId)) H.fuelMarkedShelfId=nil end
            end
        end
        local boarding=SC.Vehicle.boardingSquare(actor,car,0,true)
        if not boarding then return fail(H,current,result,setPhase,"fuel_live_standing_fixture","no native driver-side standing square") end
        local bx,by,bz=U.position(boarding)
        actor:teleportTo(bx+0.5,by+0.5,bz)
        SC.Navigation.cancel(actor,"fuel_fixture_start") SC.NativeActions.stopDirect(actor)
        local standing
        for dx=-3,3 do for dy=-3,3 do
            local tile=U.gridSquare(bx+dx,by+dy,0)
            if not standing and math.abs(dx)+math.abs(dy)>=3 and tile and U.isSquareFree(tile) then standing=tile end
        end end
        if standing then H.player:teleportTo(standing:getX()+0.5,standing:getY()+0.5,0) end
        result("PASS","fuel_live_standing_fixture","crew and observer placed beside the parked car before dispatch; journey has no teleports")
        local tank=car:getPartById("GasTank")
        tank:setContainerContentAmount(tank:getContainerCapacity()*0.55)
        f={crew=crew,storage=storage,cans=cans,carId=car:getSqlId(),parkingId=zone.id,
            originalShut=getSandboxOptions():getElecShutModifier(),nextTrace=0,seen={}}
        H.fuelExpedition=f
        check("fuel_live_original_cans",#cans==2,"two real native cans, one with 2 L starter fuel; an empty worn bag is clone-only equipment")
        setPhase("fuel_expedition_plan",current)
        return
    end
    if H.phase=="fuel_expedition_plan" then
        local options={request={mode="count",quantity=2},turnHomeAfterHours=12,restockBaseDuty=false,doctrine="close_defense",
            vehicleSqlId=f.carId,parkingZoneId=f.parkingId}
        local preview,why=SC.ExpeditionPrototype.previewFuelCollection({f.crew},options)
        if not preview then
            if why=="fuel_station_scan_pending" and current-H.phaseStartedAt<90000 then return end
            return fail(H,current,result,setPhase,"fuel_live_preflight",why)
        end
        f.car=SC.Vehicle.loadedBySqlId(preview.carSqlId)
        if not f.car then return fail(H,current,result,setPhase,"fuel_live_car","reviewed car not loaded") end
        f.carId=preview.carSqlId
        f.tank=f.car:getPartById("GasTank")
        -- A partly filled real tank must still contain the production route's
        -- full round-trip reserve; do not waive native launch checks.
        f.tank:setContainerContentAmount(math.max(tonumber(preview.fuelRequired) or 1,f.tank:getContainerCapacity()*0.55))
        f.car:transmitPartModData(f.tank)
        options.vehicleSqlId=f.carId
        getSandboxOptions():set("ElecShutModifier",0) getSandboxOptions():toLua()
        local started,trip=SC.ExpeditionPrototype.startFuelCollection({f.crew},options)
        if not started then return fail(H,current,result,setPhase,"fuel_live_launch",trip) end
        f.trip=trip f.tripId=trip.radioSession
        check("fuel_live_public_launch",trip.scout.kind=="fuel","normal planner, native car and one crew member")
        photo(H,"departure")
        setPhase("fuel_expedition_work",current)
        return
    end
    if H.phase=="fuel_expedition_work" then
        local active=SC.ExpeditionPrototype.current()
        if not active then
            local debrief=SC.ExpeditionPrototype.lastDebrief()
            local delivery=debrief and debrief.kind=="fuel" and debrief.integration
            if delivery and delivery.tripId==f.tripId then
                returned(H,f,current,check,setPhase,delivery.fuelWork,false)
                return
            end
            return fail(H,current,result,setPhase,"fuel_live_trip_lost","trip vanished before return")
        end
        local fuel=active.scout.fuel
        local destination=active.scout.destination
        if (active.scout.phase=="fuel_working" or active.scout.phase=="driving_out" and U.distance(active.leader.actor,destination)<100)
            and current>=(f.nextArrivalClear or 0) then
            f.nextArrivalClear=current+2000
            clearFixtureZombies(U,destination.x,destination.y,80)
            SC.Senses.reset(active.leader.actor)
        end
        if (active.scout.phase=="fuel_working" or active.scout.vehicle.state=="unloading_site") and not f.clearedArrival then
            f.clearedArrival=true
            local at=active.scout.destination
            result("PASS","fuel_live_quiet_arrival","clone-only station zombies removed="..clearFixtureZombies(U,at.x,at.y,60))
            SC.Senses.reset(active.leader.actor)
        end
        if fuel.pump and not f.generator then
            local at=fuel.pump
            result("PASS","fuel_live_quiet_station","clone-only nearby zombies removed="..clearFixtureZombies(U,at.x,at.y,45))
            local square=U.gridSquare(at.x,at.y,at.z)
            local existing
            if square then
                for dy=-8,8 do for dx=-8,8 do
                    local tile=U.gridSquare(at.x+dx,at.y+dy,0)
                    local generator=tile and call(tile,"getGenerator")
                    if generator then existing=generator end
                end end
            end
            if existing then f.generator=existing f.wasRunning=existing:isActivated() f.wasConnected=existing:isConnected()
            else
                local spot
                for radius=2,5 do for dy=-radius,radius do for dx=-radius,radius do
                    local tile=U.gridSquare(at.x+dx,at.y+dy,0)
                    if not spot and tile and call(tile,"isOutside")==true and U.isSquareFree(tile) and not call(tile,"getGenerator") then spot=tile end
                end end end
                local item=spot and instanceItem("Base.Generator_Old")
                if item then item:setCondition(item:getConditionMax()) end
                local generator=item and IsoGenerator.new(item,getCell(),spot)
                if not generator then return fail(H,current,result,setPhase,"fuel_live_generator_fixture","no outdoor generator square") end
                generator:setConnected(false) generator:setFuel(0) generator:setActivated(false) generator:sync()
                f.generator,f.wasRunning,f.wasConnected=generator,false,false
            end
            check("fuel_live_existing_generator",f.generator~=nil,"a real generator is placed before service; original running="..tostring(f.wasRunning))
        end
        local operation=fuel.operation and fuel.operation.kind
        if fuel.siteFailure and not f.seen["site:"..fuel.siteFailure] then
            f.seen["site:"..fuel.siteFailure]=true
            photo(H,"blocked-site-"..tostring(fuel.siteIndex))
            result("PASS","fuel_live_station_fallback","site="..fuel.siteIndex..";reason="..fuel.siteFailure)
        end
        if not f.resumed and active.scout.phase=="fuel_working" and fuel.carFuelAdded>0 and fuel.pumpLitres>0
            and not SC.NativeActions.isWorkActive(active.leader.actor) then
            local saved,why=SC.Persistence.captureRecord(SC.Registry.byId(active.leader.id))
            check("fuel_live_exact_save",saved and saved.inventory and saved.inventory.preserveNativeIds==true,
                "active fuel receipts retain native inventory IDs: "..tostring(why))
            check("fuel_live_reload_checkpoint",true,"native pumping, generator service and first car transfer complete; full return/delivery acceptance follows reload")
            photo(H,"reload-checkpoint") finish(H,current,setPhase)
            return
        end
        if operation then
            f.seen[operation]=true
            if not f.seen["photo:"..operation] then
                f.seen["photo:"..operation]=true photo(H,operation)
            end
        end
        if current>=f.nextTrace then
            f.nextTrace=current+5000
            result("PASS","fuel_live_trace","phase="..tostring(active.scout.phase)..";stage="..tostring(fuel.stage)
                ..";reason="..tostring(fuel.blocker)..";operation="..tostring(operation)..";cans="..#fuel.acquisitions
                ..";pump="..tostring(fuel.pumpLitres)..";car="..tostring(fuel.carFuelAdded)
                ..";actor="..active.leader.actor:getX()..","..active.leader.actor:getY())
            local progress=active.scout.phase..":"..tostring(fuel.stage)..":"..tostring(operation)..":"..#fuel.acquisitions..":"..fuel.pumpLitres
            local px,py=active.leader.actor:getX(),active.leader.actor:getY()
            if progress~=f.lastProgress or not f.progressX or (px-f.progressX)^2+(py-f.progressY)^2>=4 then
                f.lastProgress,f.progressAt,f.progressX,f.progressY=progress,current,px,py
            end
            if current-(f.progressAt or current)>40000 and not f.seen["stall:"..progress] then
                f.seen["stall:"..progress]=true photo(H,"blocked-progress")
                result("PASS","fuel_live_stall_diagnostic","phase="..progress..";actor="..active.leader.actor:getX()..","..active.leader.actor:getY())
            end
            local reason=tostring(fuel.blocker or "")
            if (reason:find("missing",1,true) or reason:find("blocked",1,true) or reason:find("capacity",1,true)) and not f.seen[reason] then
                f.seen[reason]=true photo(H,"blocked")
            end
        end
        if active.scout.phase=="awaiting_player" then
            returned(H,f,current,check,setPhase,fuel,true)
            return
        end
        if current-H.phaseStartedAt>600000 then return fail(H,current,result,setPhase,"fuel_live_deadline",fuel.blocker or active.scout.phase) end
    elseif H.phase=="fuel_expedition_deliver" then
        local debrief=SC.ExpeditionPrototype.lastDebrief()
        local record=debrief and debrief.integration
        local summary=record and SC.ExpeditionIntegration.summary(record)
        if current>=f.nextTrace then
            f.nextTrace=current+5000
            local registered=SC.Registry.byId(f.crew.id)
            local actor=registered and registered.actor
            local command=actor and SC.Commands.peek(actor)
            result("PASS","fuel_live_delivery_trace","record="..tostring(record~=nil)..";pending="..tostring(summary and summary.pending)
                ..";valid="..tostring(record and SC.ExpeditionIntegration.valid(record))
                ..";wants="..tostring(record and actor and SC.ExpeditionFuel.deliveryWants(record,actor))
                ..";order="..tostring(command and command.order)..";serial="..tostring(command and command.commandSerial)
                ..";receiptSerial="..tostring(record and record.members[1].commandSerial)
                ..";reason="..tostring(summary and summary.items[1] and summary.items[1].reason))
        end
        if summary and summary.complete then
            f.deliveredAt=f.deliveredAt or current
            if current-f.deliveredAt<1000 then return end
            local returned=SC.Registry.byId(f.crew.id)
            local body=returned and returned.actor and returned.actor:getBodyDamage()
            check("fuel_live_healthy_crew",body and body:getHealth()>=95 and not returned.actor:isDead(),"returned health="..tostring(body and body:getHealth()))
            check("fuel_live_storage_delivery",summary.stored==2 and summary.filled==2 and math.abs(summary.storedLitres-20)<0.03,
                "two requested 10 L cans: stored="..summary.stored..";filled="..summary.filled..";litres="..summary.storedLitres)
            for _,row in ipairs(record.items) do
                local storage=row.storageId and SC.BaseLife.storage(row.storageId)
                local container=storage and SC.BaseLife.resolveContainer(storage)
                local found=false
                local items=container and container:getItems()
                for index=0,math.min(4096,items and items:size() or 0)-1 do
                    local item=items:get(index)
                    if U.itemStableId(item,false)==row.id and item:getID()==row.nativeId then found=true break end
                end
                check("fuel_live_exact_receipt",row.stored==true and found,"can="..row.id..";native="..row.nativeId..";storage="..tostring(row.storageId))
            end
            photo(H,"delivered")
            finish(H,current,setPhase)
        elseif current-H.phaseStartedAt>180000 then return fail(H,current,result,setPhase,"fuel_live_delivery_deadline",summary and summary.pending or "no receipt") end
    end
end
SCRealSandboxHarnessProbes=SCRealSandboxHarnessProbes or {}
SCRealSandboxHarnessProbes.SCFuelExpeditionProbe=P
return P
