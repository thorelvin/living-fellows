-- SPDX-License-Identifier: MIT
-- Disposable clone: real world storage, native fluid/items and a stocked medic.
local P={}
SCRealSandboxHarnessProbes=SCRealSandboxHarnessProbes or {}
SCRealSandboxHarnessProbes.SCFarmServicesProbe=P
local function photo(H,label)
    local f=H.farmServices
    local focus=f and (f.sootheAnimal or f.actor)
    if focus then H.player:faceLocation(focus:getX(),focus:getY()) end
    H.farmServicesShot={label=label,at=getTimestampMs()+1800,zoomAt=0}
end
local function finish(H,current,setPhase)
    if H.farmServices and H.farmServices.decision then SurvivorCompanion.Decision.update=H.farmServices.decision end
    setPhase("finish",current)
end
local function block(H,current,check,setPhase,label,reason)
    photo(H,"blocked-"..label)
    H.farmServicesBlock={label=label,reason=reason}
end
local function placePlayer(player,x,y,z)
    player:teleportTo(x,y,z)
end
local function crate(square,category)
    local o=IsoThumpable.new(getCell(),square,"carpentry_01_16",false,{})
    o:setIsContainer(true) o:setContainer(ItemContainer.new("crate",square,o)) o:getContainer():setCapacity(50)
    o:getContainer():setExplored(true)
    square:AddSpecialObject(o)
    local okay,row=SurvivorCompanion.BaseLife.registerStorage(o,category) assert(okay,tostring(row))
    return o,row
end
local function barrel(square,capacity)
    local sprite="carpentry_02_122"
    local o=IsoThumpable.new(getCell(),square,sprite,false,{})
    local info=assert(SpriteConfigManager.getObjectInfoFromSprite(sprite),"native barrel sprite config missing")
    GameEntityFactory.CreateIsoObjectEntity(o,info:getScript():getParent(),true)
    square:AddSpecialObject(o)
    o:getFluidContainer():Empty() o:getFluidContainer():setCapacity(capacity)
    local okay,row=SurvivorCompanion.BaseLife.registerStorage(o,"milk") assert(okay,tostring(row))
    return o,row
end
local function feeder(square,water)
    local o=IsoFeedingTrough.new(square,"location_farm_accesories_01_14",nil)
    o:setNorth(false) o:initWithDef() square:AddSpecialObject(o) o:checkContainer()
    if o:getContainer() then o:getContainer():setExplored(true) end
    if water then local fc=assert(o:getFluidContainer()) fc:Empty() fc:addFluid(Fluid.Water,fc:getCapacity()) end
    local sys=SFeedingTroughSystem.instance
    local row=sys:getLuaObjectAt(square:getX(),square:getY(),0) or sys:newLuaObjectOnSquare(square)
    row:initNew() row:stateFromIsoObject(o)
    return o
end
local function enqueue(f,target)
    local okay,job=SurvivorCompanion.BaseLife.enqueueJob({type="farm",priority=1,target=target})
    assert(okay and type(job)=="table",tostring(job))
    job.reservedBy=f.id job.state="active"
    return job
end
local function setup(H,current)
    local SC,U=SurvivorCompanion,SurvivorCompanion.GameplayUtil
    local record
    for _,r in ipairs(SC.Registry.snapshot()) do if r.actor and r.recruited and not U.isDead(r.actor) then record=r break end end
    if not record then return nil end
    local px,py=math.floor(H.player:getX()),math.floor(H.player:getY())
    local site
    for dx=-18,18,6 do for dy=-18,18,6 do
        local okay=true
        for x=px+dx,px+dx+7 do for y=py+dy,py+dy+7 do
            local s=getSquare(x,y,0)
            if not s or not s:isOutside() or not U.isSquareFree(s) or U.squareOccupyingObject(s)
                or s:isVehicleIntersecting() then okay=false break end
        end if not okay then break end end
        if okay then site={x=px+dx,y=py+dy} break end
    end if site then break end end
    assert(site,"no loaded clear outdoor 8x8 site")
    local x,y=site.x,site.y
    if not SC.BaseLife.active() then assert(SC.BaseLife.create(getSquare(x+3,y+3,0),"Farm services acceptance")) end
    assert(SC.BaseLife.beginZone("area",getSquare(x,y,0)))
    assert(SC.BaseLife.finishZone(getSquare(x+7,y+7,0),"Farm services acceptance"))
    local actor=record.actor
    SC.Downtime.cancel(actor,"farm_services_probe") SC.BaseWork.cancel(actor,"farm_services_probe")
    SC.Logistics.reset(actor) SC.Navigation.cancel(actor,"farm_services_probe")
    SC.Commands.issue(record.id,"stay",getSquare(x+3,y+3,0),H.player)
    assert(SC.BaseLife.assign(record.id,"farmer",true))
    assert(H.placeCombatActor(actor,{x=x+3.5,y=y+3.5,z=0}))
    placePlayer(H.player,x+0.5,y+0.5,0)
    getGameTime():setTimeOfDay(12)
    actor:getStats():set(CharacterStat.FATIGUE,0.1) actor:getStats():set(CharacterStat.ENDURANCE,1)
    local f={actor=actor,id=record.id,x=x,y=y,stage="milk",at=current,lastAt=0}
    f.source,f.sourceRow=crate(getSquare(x+1,y+2,0),"farming")
    f.food=crate(getSquare(x+1,y+1,0),"fresh_food")
    f.a=barrel(getSquare(x+3,y+2,0),0.75) f.b=barrel(getSquare(x+4,y+2,0),3)
    f.comp=IsoCompost.new(getCell(),getSquare(x+5,y+2,0),"carpentry_02_117")
    getSquare(x+5,y+2,0):AddSpecialObject(f.comp) f.comp:setCompost(100)
    assert(SC.BaseLife.registerStorage(f.comp,"manure"))
    f.overflow=crate(getSquare(x+6,y+2,0),"manure")
    f.medical=crate(getSquare(x+2,y+2,0),"medical")
    f.kit=f.medical:getContainer():AddItem("Base.FirstAidKit_New")
    for _=1,9 do f.medical:getContainer():AddItem("Base.Bandage") end
    f.splint=f.medical:getContainer():AddItem("Base.Splint")
    f.bucket=actor:getInventory():AddItem("Base.Bucket")
    f.bucket:getFluidContainer():Empty() f.bucket:getFluidContainer():addFluid(Fluid.CowMilk,2)
    f.milkJob=enqueue(f,{animal=true,operation="animal_milk",nativeZoneId="99999",cowId=1,
        deviceKey="animal:acceptance-milk",x=x+3,y=y+3,z=0})
    local receipt=assert(SC.FarmWork.animalSupport.receipt(actor,f.milkJob,"borrowed",f.bucket,f.sourceRow))
    assert(SC.BaseLife.updateFarmReceipt(receipt.id,{milk={version=1,cowId=1,zoneId="99999",day=0,
        fluid="CowMilk",before=0,after=2,litres=2,lost=0},kind="output",phase="carried",destinationCategory="fresh_food"}))
    f.receipt=receipt f.milkJob.target.milkReceiptId=receipt.id
    f.state={outputs={{item=f.bucket,receiptId=receipt.id,category="fresh_food",milk=true}}}
    f.decision=SC.Decision.update SC.Decision.update=function() return true,"farm_services_fixture_owned" end
    if SC.UI.instance then SC.UI.instance:setVisible(false) end
    getPlayerInventory(0):setVisible(false) getPlayerLoot(0):setVisible(false)
    return f
end
function P.step(H,current,check,result,setPhase)
    if H.config.farm_services_inspect=="true" then
        require "SCFarmSoakProbe"
        return SCRealSandboxHarnessProbes.SCFarmSoakProbe.inspect(H,current,check,result,setPhase)
    end
    if (tonumber(H.config.farm_services_days) or 0)>0 then
        require "SCFarmSoakProbe"
        return SCRealSandboxHarnessProbes.SCFarmSoakProbe.step(H,current,check,result,setPhase)
    end
    local SC=SurvivorCompanion
    local U,B=SC.GameplayUtil,SC.BaseLife
    if H.farmServicesShot then
        local now=getTimestampMs()
        if now<H.farmServicesShot.at then
            if now>=H.farmServicesShot.zoomAt then
                H.farmServicesShot.zoomAt=now+300
                local zoom=getCore():getZoom(0)
                if zoom>1.6 then getCore():doZoomScroll(0,-1)
                elseif zoom<1.25 then getCore():doZoomScroll(0,1) end
            end
            return
        end
        getCore():TakeFullScreenshot(H.config.run_id.."-farm-services-"..H.farmServicesShot.label..".png")
        H.farmServicesShot=nil
        if H.farmServicesBlock then
            check(H.farmServicesBlock.label,false,tostring(H.farmServicesBlock.reason))
            finish(H,current,setPhase) return
        end
    end
    local f=H.farmServices
    if f and f.finished then finish(H,current,setPhase) return end
    if not f then
        local okay,value=pcall(setup,H,current)
        if not okay then return block(H,current,check,setPhase,"farm_services_setup",value) end
        if not value then return end
        H.farmServices=value check("farm_services_setup",true,"native barrels, composter, crates and empty kit in a disposable clone")
        setPhase("farm_services_work",current) return
    end
    if current-f.lastAt<150 then return end f.lastAt=current
    if current-(f.traceAt or 0)>5000 then
        f.traceAt=current
        local work=f.state and f.state.milkPour
        print("SC_FARM_SERVICES_STATE|stage="..f.stage.."|reason="..tostring(f.reason)
            .."|bucket="..tostring(f.bucket:getFluidContainer():getAmount())
            .."|barrels="..tostring(f.a:getFluidContainer():getAmount())..","..tostring(f.b:getFluidContainer():getAmount())
            .."|native="..tostring(SC.NativeActions.workKind(f.actor)).."/"..tostring(SC.NativeActions.isWorkActive(f.actor))
            .."|guard="..tostring(work and work.validation))
    end
    if current-f.at>120000 then return block(H,current,check,setPhase,"farm_services_"..f.stage,f.reason) end
    -- This probe owns the decision lane, so retain its ordinary native pacing.
    if SC.NativeActions.pacingStatus(f.actor) then return end
    if f.stage=="milk" then
        local handled,why=SC.AnimalWork.deliverMilk(f.actor,{},f.milkJob,f.state) f.reason=why
        if f.lastMilkReason~=why then
            f.lastMilkReason=why
            local target=SC.FarmStorage.milkDestination(f.actor,f.bucket,f.milkJob,f.state.milkExcluded)
            local excluded={} for id in pairs(f.state.milkExcluded or {}) do excluded[#excluded+1]=id end
            print("SC_FARM_SERVICES_MILK|reason="..tostring(why).."|destination="..tostring(target and target.id)
                .."|excluded="..table.concat(excluded,",").."|position="..f.actor:getX()..","..f.actor:getY())
        end
        if handled==false then return block(H,current,check,setPhase,"milk_delivery",why) end
        if f.state.outputs then return end
        check("milk_two_barrels",math.abs(f.a:getFluidContainer():getAmount()-0.75)<0.005
            and math.abs(f.b:getFluidContainer():getAmount()-1.25)<0.005,"partial barrel followed by a second native pour; two litres conserved")
        check("milk_empty_bucket",f.bucket:getFluidContainer():getAmount()<0.0001,"the original container is empty")
        photo(H,"milk-delivered") f.stage="milk_return" f.at=current
    elseif f.stage=="milk_return" then
        local okay,why=SC.FarmWork.animalSupport.settle(f.actor,{},f.state) f.reason=why
        if not okay then return end
        check("milk_bucket_returned",f.source:getContainer():contains(f.bucket),"exact borrowed bucket returned to Farming storage")
        B.completeJob(f.milkJob.id,f.id,"acceptance_milk")
        f.zone=DesignationZoneAnimal.new("Farm services hens",f.x,f.y+4,0,f.x+7,f.y+7,true)
        local breed=AnimalDefinitions.getDef("hen"):getBreedByName("rhodeisland")
        f.hen=addAnimal(getCell(),f.x+5.5,f.y+6.5,0,"hen",breed,false)
        f.hen:addToWorld() f.hen:setWild(false) f.hen:setDZone(f.zone) f.zone:addAnimal(f.hen) f.zone:check()
        f.waterTrough=feeder(getSquare(f.x,f.y+6,0),true)
        f.feedTrough=feeder(getSquare(f.x,f.y+4,0),false)
        f.feedBags={}
        for i=1,3 do f.feedBags[i]=assert(f.source:getContainer():AddItem("Base.AnimalFeedBag")) end
        f.zone:check() f.stage="feed_find" f.at=current
    elseif f.stage=="feed_find" then
        local target,why=SC.AnimalWork.candidate(B.active(),16) f.reason=why
        if target and target.operation=="animal_feed" then
            f.job=enqueue(f,target) f.state={} f.stage="feed_work" f.at=current
        end
    elseif f.stage=="feed_work" then
        local handled,why=SC.AnimalWork.update(f.actor,{},f.job,{snapshot={immediateCount=0,pressure=0,zombies={}}},f.state)
        f.reason=why
        if handled==false then return block(H,current,check,setPhase,"native_feed",why) end
        if f.job.state~="completed" then return end
        local amount,maximum=f.feedTrough:getCurrentFeedAmount(),f.feedTrough:getMaxFeed()
        check("feed_native_package_limit",maximum==25 and amount>19.9 and amount<=maximum,
            "whole bags finish below the 90% mark without overfilling: "..amount.."/"..maximum)
        local stored,delivered=0,0
        for _,bag in ipairs(f.feedBags) do
            if f.source:getContainer():contains(bag) then stored=stored+1 end
            if f.feedTrough:getContainer():contains(bag) then delivered=delivered+1 end
        end
        check("feed_exact_bags",stored==1 and delivered==2,"two original bags delivered; spare original bag remains at source")
        photo(H,"native-feed-trough")
        f.dungSquare=getSquare(f.x+3,f.y+5,0)
        f.dung=f.dungSquare:AddWorldInventoryItem("Base.Dung_Chicken",0.5,0.5,0)
        f.tool=f.actor:getInventory():AddItem("Base.Shovel")
        f.stage="manure_find" f.at=current
    elseif f.stage=="manure_find" or f.stage=="overflow_find" then
        local target,why=SC.AnimalWork.candidate(B.active(),16) f.reason=why
        local wanted=f.stage=="manure_find" and "animal_manure" or "animal_manure_move"
        if target and target.operation==wanted then
            f.job=enqueue(f,target) f.state={}
            f.stage=wanted=="animal_manure" and "manure_work" or "overflow_work" f.at=current
        end
    elseif f.stage=="manure_work" or f.stage=="overflow_work" then
        local handled,why=SC.AnimalWork.update(f.actor,{},f.job,{snapshot={immediateCount=0,pressure=0,zombies={}}},f.state)
        f.reason=why
        if handled==false then return block(H,current,check,setPhase,f.stage,why) end
        if f.job.state~="completed" then return end
        if f.stage=="manure_work" then
            check("manure_overflow",f.overflow:getContainer():contains(f.dung) and not f.comp:getContainer():contains(f.dung),
                "full composter uses the marked overflow crate; exact native dung identity")
            check("manure_ground_clear",not f.dungSquare:checkHaveDung(),"native collection cleared the tile")
            photo(H,"manure-overflow") f.comp:setCompost(20) f.stage="overflow_find"
        else
            check("manure_recovered",f.comp:getContainer():contains(f.dung) and not f.overflow:getContainer():contains(f.dung),
                "stored overflow moved one-way into the composter")
            photo(H,"manure-composter") assert(B.assign(f.id,"medic",true)) f.stage="medic"
        end
        f.at=current
    elseif f.stage=="medic" then
        local audit=SC.Logistics.audit(f.actor)
        if SC.MedicKit.needsWork(f.actor,audit) then
            local handled,why=SC.MedicKit.step(f.actor,audit) f.reason=why
            if handled==false and why~="medic_kit_ready" then return block(H,current,check,setPhase,"medic_stock",why) end
            return
        end
        local facts=SC.MedicKit.view(f.actor,audit)
        check("medic_kit_stock",facts.kit==f.kit and facts.kitDressings==9 and facts.splints>=1,
            "one original first-aid kit fetched and stocked; nine clean dressings and one splint")
        check("medic_kit_retained",SC.MedicKit.retained(f.actor,f.kit),"kit retained by logistics without disabling treatment")
        photo(H,"medic-stocked")
        local x,y,z=f.actor:getX(),f.actor:getY(),f.actor:getZ()
        placePlayer(H.player,x+0.5,y+0.5,z)
        f.part=H.player:getBodyDamage():getBodyPart(BodyPartType.ForeArm_L)
        f.part:setScratched(true,true) f.part:setBleedingTime(10)
        f.beforeKit=f.kit:getInventory():getItems():size()
        f.stage="treat" f.at=current
    elseif f.stage=="treat" then
        local handled,why=SC.Medical.treat(f.actor,H.player,{snapshot={immediateCount=0,pressure=0,zombies={}}}) f.reason=why
        if f.part:bandaged() and f.part:getBleedingTime()<=0 then
            check("medic_real_treatment",true,"real player wound bandaged and bleeding stopped")
            check("medic_kit_consumed",f.kit:getInventory():getItems():size()==f.beforeKit-1,
                "actual dressing consumed from the nested kit, not the player inventory")
            check("farm_services_alive",not f.actor:isDead(),"worker remains alive")
            photo(H,"treatment")
            assert(B.assign(f.id,"farmer",true))
            f.hen:setDebugStress(35) f.hen:setDebugAcceptance(f.actor,100)
            f.sootheAnimal=f.hen
            f.sootheBefore=f.hen:getStress() f.sootheHand=f.actor:getPrimaryHandItem()
            f.stage="soothe_find" f.at=current
        elseif not handled and why~="approaching_patient" then return block(H,current,check,setPhase,"medic_treatment",why) end
    elseif f.stage=="soothe_find" then
        local target,why=SC.AnimalWork.candidate(B.active(),16) f.reason=why
        if target and target.operation=="animal_soothe" and target.animalId==f.sootheAnimal:getAnimalID() then
            f.job=enqueue(f,target) f.state={} f.stage="soothe_work" f.at=current
            check("animal_soothe_admitted_"..f.sootheAnimal:getAnimalType(),true,"ordinary managed-pen census selected the stressed animal")
        end
    elseif f.stage=="soothe_work" then
        local handled,why=SC.AnimalWork.update(f.actor,{},f.job,{snapshot={immediateCount=0,pressure=0,zombies={}}},f.state)
        f.reason=why
        if handled==false then return block(H,current,check,setPhase,"animal_soothing",why) end
        if SC.NativeActions.workKind(f.actor)=="farm_animal_soothe" and not f.sootheShot then
            f.sootheShot=true photo(H,"native-animal-soothing-"..f.sootheAnimal:getAnimalType())
        end
        if f.job.state=="completed" then
            local kind=f.sootheAnimal:getAnimalType()
            check("animal_soothe_native_"..kind,f.state.soothe and f.state.soothe.applied==true
                and f.sootheAnimal:getStress()<f.sootheBefore,"native pet effect: stress "..f.sootheBefore.." -> "..f.sootheAnimal:getStress())
            check("animal_soothe_release_"..kind,not f.actor:getVariableBoolean("petanimal")
                and f.sootheAnimal:getVariableString("idleAction")~="petting"
                and f.actor:getPrimaryHandItem()==f.sootheHand,"native pose, movement hold and prior hand equipment released")
            photo(H,"animal-soothed-"..kind)
            if kind=="hen" then
                -- A separate cattle-only zone exercises grazer discovery;
                -- keeping it separate prevents a hen from masking that path.
                f.cowZone=DesignationZoneAnimal.new("Farm services cow",f.x+4,f.y,0,f.x+7,f.y+3,true)
                local breed=AnimalDefinitions.getDef("cow"):getBreedByName("holstein")
                f.sootheAnimal=addAnimal(getCell(),f.x+5.5,f.y+0.5,0,"cow",breed,false)
                f.sootheAnimal:addToWorld() f.sootheAnimal:setWild(false)
                f.sootheAnimal:setDZone(f.cowZone) f.cowZone:addAnimal(f.sootheAnimal) f.cowZone:check()
                f.sootheAnimal:setDebugStress(35) f.sootheAnimal:setDebugAcceptance(f.actor,100)
                f.sootheBefore=f.sootheAnimal:getStress() f.sootheHand=f.actor:getPrimaryHandItem()
                f.sootheShot=false f.state={} f.stage="soothe_find" f.at=current
                return
            end
            result("PASS","farm_services_complete","native milk, manure, overflow recovery, stocked-kit treatment and animal soothing")
            f.finished=true
        end
    end
end
return P
