-- SPDX-License-Identifier: MIT
-- Disposable farm: setup once, then observe ordinary decisions for game days.
local P={}
SCRealSandboxHarnessProbes=SCRealSandboxHarnessProbes or {}
SCRealSandboxHarnessProbes.SCFarmSoakProbe=P
local function v(o,m,...) local value=SurvivorCompanion.GameplayUtil.call(o,m,...) return value end
local function emit(kind,text) print("SC_FARM_SOAK|"..kind.."|"..tostring(text)) end
local function movePlayer(player,x,y)
    player:teleportTo(x,y,0)
end
local function shot(H,f,label)
    if f.shot then
        if label:find("blocked",1,true) then f.shot.label=label end
        return
    end
    for _=1,8 do if getCore():getZoom(0)<1.8 then getCore():doZoomScroll(0,1) end end
    f.shot={at=getTimestampMs()+1200,label=label}
end
local function zone(kind,x,y,x2,y2,name)
    local B=SurvivorCompanion.BaseLife
    assert(B.beginZone(kind,getSquare(x,y,0))) assert(B.finishZone(getSquare(x2,y2,0),name))
end
local function crate(x,y,kind)
    local sq=getSquare(x,y,0)
    local o=IsoThumpable.new(getCell(),sq,"carpentry_01_16",false,{})
    o:setIsContainer(true) o:setContainer(ItemContainer.new("crate",sq,o)) o:getContainer():setCapacity(100)
    o:getContainer():setExplored(true) -- Keep native loot generation out of the supplied test stock.
    sq:AddSpecialObject(o)
    assert(SurvivorCompanion.BaseLife.registerStorage(o,kind))
    return o:getContainer()
end
local function barrel(x,y,fluid,capacity,mark)
    local sq=getSquare(x,y,0)
    local name="carpentry_02_122"
    local o=IsoThumpable.new(getCell(),sq,name,false,{})
    local info=assert(SpriteConfigManager.getObjectInfoFromSprite(name))
    GameEntityFactory.CreateIsoObjectEntity(o,info:getScript():getParent(),true)
    sq:AddSpecialObject(o)
    local fc=o:getFluidContainer() fc:Empty() fc:setCapacity(capacity)
    if fluid then fc:addFluid(fluid,capacity) end
    if mark then assert(SurvivorCompanion.BaseLife.registerStorage(o,mark)) end
    return o
end
local function add(container,kind,count)
    local first
    for _=1,count do first=assert(container:AddItem(kind),"missing native item "..kind) end
    return first
end
local function fill(item)
    local fc=assert(item:getFluidContainer()) fc:Empty() fc:addFluid(Fluid.Water,fc:getCapacity())
end
local function pen(f,name,x,y,w,h)
    local function fence(xx,yy,north,gate)
        local sq=getSquare(xx,yy,0)
        local o=IsoThumpable.new(getCell(),sq,gate and "fixtures_doors_01_1" or north and "fencing_01_1" or "fencing_01_2",north,{})
        if gate then
            o:setIsDoor(true) o:setLockedByKey(false)
            o:setClosedSprite(assert(getSprite("fixtures_doors_01_1")))
            o:setOpenSprite(assert(getSprite("fixtures_doors_01_3")))
        else o:setIsHoppable(true) o:setCanPassThrough(false) end
        sq:AddSpecialObject(o) sq:RecalcAllWithNeighbours(true)
        if gate then
            o:ToggleDoor(getSpecificPlayer(0)) assert(o:getSprite(),"native gate open sprite")
            o:ToggleDoor(getSpecificPlayer(0)) assert(o:getSprite(),"native gate closed sprite")
        end
    end
    for dx=0,w-1 do fence(x+dx,y,true,dx==math.floor(w/2)) fence(x+dx,y+h,true,false) end
    for dy=0,h-1 do fence(x,y+dy,false,false) fence(x+w,y+dy,false,false) end
    local z=DesignationZoneAnimal.new("LF soak "..name,x,y,0,x+w,y+h,true)
    assert(z:getFullZoneSize()>=(name=="cattle" and 80 or name=="sheep" and 40 or 12),"native pen space: "..name)
    local sq=getSquare(x+2,y+2,0)
    local trough=IsoFeedingTrough.new(sq,"location_farm_accesories_01_14",nil)
    trough:setNorth(false) trough:initWithDef() sq:AddSpecialObject(trough)
    trough:setMaxWater(40) trough:updateLuaObject() trough:checkContainer()
    trough:getFluidContainer():setCapacity(40) trough:getFluidContainer():Empty()
    trough:getFluidContainer():addFluid(Fluid.Water,2)
    local sys=SFeedingTroughSystem.instance
    local lua=sys:getLuaObjectAt(x+2,y+2,0) or sys:newLuaObjectOnSquare(sq)
    lua:initNew() lua:stateFromIsoObject(trough)
    local row={name=name,zone=z,trough=trough,x=x,y=y}
    local fsq=getSquare(x+2,y+4,0)
    row.feeder=IsoFeedingTrough.new(fsq,"location_farm_accesories_01_14",nil)
    row.feeder:setNorth(false) row.feeder:initWithDef() fsq:AddSpecialObject(row.feeder)
    row.feeder:updateLuaObject() row.feeder:checkContainer()
    local flua=sys:getLuaObjectAt(x+2,y+4,0) or sys:newLuaObjectOnSquare(fsq)
    flua:initNew() flua:stateFromIsoObject(row.feeder)
    f.pens[#f.pens+1]=row
    return row
end
local function animal(f,row,kind,breed,dx,dy)
    local definition=assert(AnimalDefinitions.getDef(kind),"native species "..kind)
    local b=assert(definition:getBreedByName(breed),"native breed "..breed)
    local a=assert(addAnimal(getCell(),row.x+dx,row.y+dy,0,kind,b,false))
    a:addToWorld() a:setWild(false) a:setDZone(row.zone) row.zone:addAnimal(a)
    a:setDebugStress(0)
    for _,r in ipairs(f.crew) do a:setDebugAcceptance(r.actor,100) end
    a:setDebugAcceptance(getSpecificPlayer(0),100)
    f.animals[#f.animals+1]=a
    return a
end
local function beds(x,y)
    local sprite=getSprite("camping_02_0") local grid=assert(sprite:getSpriteGrid())
    for i=0,2 do for gy=0,grid:getHeight()-1 do for gx=0,grid:getWidth()-1 do
        local sq=getSquare(x+i*3+gx,y+gy,0)
        sq:AddTileObject(IsoObject.new(sq,grid:getSprite(gx,gy):getName(),"Sleeping Bag"))
    end end end
    zone("rest",x-1,y-1,x+8,y+2,"Farm sleeping area")
end
local function clearSite(f)
    local x,y=f.x,f.y
    local cleared=0
    for xx=x,x+23 do for yy=y,y+25 do
        local sq=getSquare(xx,yy,0) local objects=sq:getObjects()
        local floor=sq:getFloor()
        for i=objects:size()-1,0,-1 do local o=objects:get(i)
            -- This disposable, grass-only site can contain map fences which
            -- squareOccupyingObject does not report. Clear the whole initial
            -- footprint before adding pens, not just its trees and bushes.
            if o~=floor then sq:RemoveTileObject(o) cleared=cleared+1 end
        end
        sq:RecalcAllWithNeighbours(true)
        assert(sq:getObjects():size()==1 and sq:getObjects():get(0)==floor,"clear native farm footprint")
    end end
    emit("SITE_CLEARED","non-floor objects="..cleared.."; no pre-existing fences inside pens")
end
local function setupFarm(H,f)
    local SC,B,U=SurvivorCompanion,SurvivorCompanion.BaseLife,SurvivorCompanion.GameplayUtil
    local x,y=f.x,f.y
    -- Initial fixture date only: carrot season, without disabling seasons or
    -- replenishing workers, stock or animals during the observation.
    getGameTime():setMonth(5) getGameTime():setDay(10)
    B.reset() assert(B.create(getSquare(x+10,y+10,0),"Three-day mixed farm"))
    local defaultArea=B.active().zones[1].id
    zone("area",x,y,x+23,y+25,"Mixed farm camp")
    assert(B.removeZone(defaultArea)) -- Replace the default radius, which also covers the nearby car park.
    assert(#B.active().zones==1,"one bounded farm camp")
    zone("rally",x+9,y+9,x+10,y+10,"Farm meeting point")
    beds(x+1,y+1)
    f.farming=crate(x+1,y+6,"farming") f.food=crate(x+2,y+6,"food")
    f.medical=crate(x+3,y+6,"medical") f.wool=crate(x+7,y+6,"crafting")
    f.cowMilk=barrel(x+4,y+6,nil,100,"milk") f.sheepMilk=barrel(x+5,y+6,nil,100,"milk")
    f.water=barrel(x+8,y+6,Fluid.Water,200)
    f.overflow=crate(x+7,y+7,"manure")
    f.compost=IsoCompost.new(getCell(),getSquare(x+6,y+7,0),"carpentry_02_117")
    getSquare(x+6,y+7,0):AddSpecialObject(f.compost) assert(B.registerStorage(f.compost,"manure"))
    for _,t in ipairs({"Base.Shovel","Base.SheepShears","Base.Bucket","Base.WateredCan"}) do
        for _=1,3 do local item=add(f.farming,t,1)
            if t=="Base.WateredCan" then
                local fc=item:getFluidContainer() fc:Empty() fc:addFluid(Fluid.Water,math.min(4,fc:getCapacity()))
            elseif t=="Base.Bucket" then item:getFluidContainer():Empty() end
        end
    end
    add(f.farming,"Base.AnimalFeedBag",3) add(f.farming,"Base.Mop",2) add(f.farming,"Base.Bleach",2)
    f.feed=crate(x+1,y+7,"farming") add(f.feed,"Base.AnimalFeedBag",9)
    add(f.food,"Base.Bread",24) add(f.food,"Base.TinnedBeans",24) add(f.food,"Base.TinOpener",3)
    for _=1,12 do fill(add(f.food,"Base.WaterBottle",1)) end
    add(f.medical,"Base.FirstAidKit_New",1) add(f.medical,"Base.Bandage",30) add(f.medical,"Base.Splint",3)
    for label,c in pairs({tools=f.farming,feed=f.feed,food=f.food,medical=f.medical}) do
        emit("CAPACITY",label.." load="..c:getCapacityWeight().." capacity="..c:getCapacity())
        assert(c:getCapacityWeight()<c:getCapacity()-15,"fixture return headroom: "..label)
    end
    f.pens={} f.animals={}
    local birds=pen(f,"chicken",x+1,y+11,8,7)
    local cows=pen(f,"cattle",x+12,y+13,11,12)
    local sheep=pen(f,"sheep",x+13,y+1,10,10)
    local hd=HutchDefinitions.hutchs.hutchhen
    f.hutch=IsoHutch.new(getSquare(birds.x+4,birds.y+3,0),false,hd.baseSprite,hd,nil)
    if f.hutch:isDoorClosed() then f.hutch:toggleDoor() end
    for i,kind in ipairs({"hen","hen","cockerel","chick"}) do
        local a=animal(f,birds,kind,"rhodeisland",2+i,5)
        if kind=="hen" then a:setAgeDebug(200) end
    end
    local cow=animal(f,cows,"cow","holstein",5,5)
    cow:setDebugStress(35) -- One eligible stressed animal; no stat writes after setup.
    f.sootheAnimal=cow
    animal(f,cows,"bull","holstein",7,7)
    local calf=cow:addBaby() assert(calf,"native calf") calf:setDZone(cows.zone) cows.zone:addAnimal(calf) f.animals[#f.animals+1]=calf
    local ewe=animal(f,sheep,"ewe","suffolk",5,5)
    animal(f,sheep,"ram","suffolk",7,7)
    local lamb=ewe:addBaby() assert(lamb,"native lamb") lamb:setDZone(sheep.zone) sheep.zone:addAnimal(lamb) f.animals[#f.animals+1]=lamb
    for _,a in ipairs({cow,ewe}) do
        local d=a:getData() d:setCanHaveMilk(true) d:setMaxMilkActual(d:getMaxMilk()) d:setMilkQuantity(d:getMaxMilkActual()*0.8)
    end
    for _,a in ipairs(f.animals) do
        if a:getAnimalType()=="ewe" or a:getAnimalType()=="ram" then
            a:setAgeDebug(240) a:getData():setWoolQuantity(a:getData():getMaxWool())
            assert(a:getData():getWoolQuantity()>0,"mature native fleece fixture")
        end
    end
    for _,row in ipairs(f.pens) do row.zone:check() end
    zone("farm",x+1,y+20,x+8,y+24,"Vegetable beds")
    f.plants={}
    for dx=2,6,2 do for dy=21,23,2 do
        local sq=getSquare(x+dx,y+dy,0) SFarmingSystem.instance:plow(sq)
        local p=assert(SFarmingSystem.instance:getLuaObjectOnSquare(sq))
        p:seed("Carrots",5) p.waterLvl=20 p:saveData() f.plants[#f.plants+1]=p
    end end
    for i,r in ipairs(f.crew) do
        SC.Downtime.cancel(r.actor,"farm_soak_setup") SC.Logistics.reset(r.actor) SC.Navigation.cancel(r.actor,"farm_soak_setup")
        assert(H.placeCombatActor(r.actor,{x=x+9.5,y=y+7+i,z=0}))
        SC.Commands.issue(r.id,"base_duty",nil,H.player) assert(B.assign(r.id,i==3 and "medic" or "farmer",true))
        r.actor:getStats():set(CharacterStat.HUNGER,0.1) r.actor:getStats():set(CharacterStat.THIRST,0.1)
        r.actor:getStats():set(CharacterStat.FATIGUE,0.1) r.actor:getStats():set(CharacterStat.ENDURANCE,1)
    end
    assert(B.setPolicy("workOutsideAtNight",true)) -- This is an outdoor camp; normal fatigue still requires sleep.
    movePlayer(H.player,x+10.5,y+10.5)
    if SC.UI.instance then SC.UI.instance:setVisible(false) end
    getPlayerInventory(0):setVisible(false) getPlayerLoot(0):setVisible(false)
    local zombies=getCell():getZombieList() local removed=0
    for i=zombies:size()-1,0,-1 do local z=zombies:get(i)
        if (z:getX()-x-12)^2+(z:getY()-y-12)^2<150^2 then z:removeFromWorld() z:removeFromSquare() removed=removed+1 end
    end
    for _,name in ipairs({"ZombieConfig.RespawnHours","ZombieConfig.RedistributeHours","ZombieConfig.PopulationMultiplier"}) do
        local option=getSandboxOptions():getOptionByName(name) if option then option:setValue(0) end
    end
    getGameTime():setTimeOfDay(8) getGameTime():setMinutesPerDay(120)
    f.startHour=getGameTime():getWorldAgeHours() f.untilHour=f.startHour+24*tonumber(H.config.farm_services_days)
    f.counts={} f.completed={} f.blocked={} f.minHealth=100 f.deaths=0 f.hour=-1 f.blockShots={}
    f.slept={} f.cropWatered={} f.hutchClosed=false f.hutchReopened=false
    f.complete= B.completeJob
    local candidate=SC.AnimalWork.candidate
    SC.AnimalWork.candidate=function(...)
        local target,reason,pending=candidate(...)
        if getTimestampMs()>=(f.auditLogAt or 0) then
            f.auditLogAt=getTimestampMs()+15000
            emit("AUDIT","animal="..tostring(target and target.operation).." reason="..tostring(reason).." pending="..tostring(pending))
            local farm=SC.FarmWork.summary()
            emit("AUDIT","plots="..tostring(farm.knownPlots).." scans="..tostring(farm.scans).." blocker="..tostring(farm.chickenBlocker))
        end
        return target,reason,pending
    end
    local diagnostic=U.diagnostic
    U.diagnostic=function(subsystem,actor,message)
        if subsystem=="navigation-blocker" then
            local reason=tostring(message):match("reason=([^ ]+)") or "unknown"
            local tag="navigation-"..reason
            if not f.blockShots[tag] then
                f.blockShots[tag]=true
                H.player:faceLocation(actor:getX(),actor:getY())
                shot(H,f,"blocked-"..tag:gsub("[^%w-]","-"))
            end
        end
        return diagnostic(subsystem,actor,message)
    end
    B.completeJob=function(id,...)
        local job=B.job(id) local op=job and job.target and job.target.operation or job and job.type or "unknown"
        local a,b=f.complete(id,...)
        if a and not f.completed[id] then f.completed[id]=true f.counts[op]=(f.counts[op] or 0)+1 emit("COMPLETE",id.." op="..op) end
        if a and op=="animal_soothe" then emit("SOOTHE_RESULT","id="..tostring(job.target.animalId)
            .." stress="..tostring(f.sootheAnimal:getStress()).." petting="..tostring(f.sootheAnimal:getVariableString("idleAction"))) end
        return a,b
    end
    SC.Decision.update=f.decision
    f.stage="run"
    emit("SETUP","x="..x.." y="..y.." animals="..#f.animals.." crew="..#f.crew.." plots="..#f.plants
        .." startHour="..f.startHour.." endHour="..f.untilHour.." zombiesCleared="..removed.." speed=5x; initial supplies only; quiet farm, paired troughs, validated native gates")
    shot(H,f,"farm-start")
end
local function sample(H,f,check)
    local SC,B=SurvivorCompanion,SurvivorCompanion.BaseLife
    local h=getGameTime():getWorldAgeHours()-f.startHour
    local storedMilk={CowMilk=0,SheepMilk=0}
    for _,object in ipairs({f.cowMilk,f.sheepMilk}) do
        local info=SC.FarmStorage.milkInfo(object)
        if info and storedMilk[info.fluid] then storedMilk[info.fluid]=storedMilk[info.fluid]+info.amount end
    end
    emit("HOUR",string.format("elapsed=%.2f hour=%.2f cowMilk=%.3f sheepMilk=%.3f compost=%.2f",h,getGameTime():getTimeOfDay(),
        storedMilk.CowMilk,storedMilk.SheepMilk,f.compost:getCompost()))
    for _,r in ipairs(f.crew) do
        local a=r.actor local s=a:getStats() local d=SC.Decision.peek(a) or {} local job=B.jobFor(r.id)
        emit("CREW",r.id.." hp="..a:getHealth().." hunger="..s:get(CharacterStat.HUNGER).." thirst="..s:get(CharacterStat.THIRST)
            .." fatigue="..s:get(CharacterStat.FATIGUE).." stamina="..s:get(CharacterStat.ENDURANCE).." activity="..tostring(d.current)
            .." intent="..tostring(d.intent).." job="..tostring(job and job.id).." op="..tostring(job and job.target and job.target.operation)
            .." load="..tostring(select(1,SC.GameplayUtil.carryLoad(a))).." limit="..tostring(select(2,SC.GameplayUtil.carryLoad(a)))
            .." pos="..a:getX()..","..a:getY())
        if a:isAsleep() or d.current=="sleep" or tostring(d.intent):find("sleeping_on_bed",1,true) then f.slept[r.id]=true end
        if a:isDead() and not f.blockShots[r.id] then check("farm_soak_crew_alive_"..r.id,false,"worker died") f.blockShots[r.id]=true shot(H,f,"blocked-worker-death") end
    end
    for _,a in ipairs(f.animals) do
        local data=a:getData() local health=a:getHealth() f.minHealth=math.min(f.minHealth,health)
        emit("ANIMAL",a:getAnimalType().." id="..a:getAnimalID().." hp="..health.." hunger="..a:getHunger().." thirst="..a:getThirst()
            .." stress="..a:getStress().." milk="..data:getMilkQuantity().." wool="..data:getWoolQuantity().." hutch="..tostring(a:getHutch()~=nil)
            .." pos="..a:getX()..","..a:getY()..","..a:getZ())
    end
    for _,j in ipairs(B.active().jobs) do if j.state=="blocked" then
        local why=j.blocker or j.reason or j.lastFailure or "unknown"
        local key=tostring(j.id)..":"..tostring(why)
        f.blocked[key]=(f.blocked[key] or 0)+1
        emit("BLOCK",j.id.." op="..tostring(j.target and j.target.operation).." reason="..tostring(why)
            .." animal="..tostring(j.target and (j.target.cowId or j.target.animalId)).." zone="..tostring(j.target and j.target.nativeZoneId))
        if not f.blockShots[key] then
            f.blockShots[key]=true
            if j.target and j.target.x then H.player:faceLocation(j.target.x+0.5,j.target.y+0.5) end
            shot(H,f,"blocked-"..j.id:gsub(":","-").."-"..tostring(why):gsub("[^%w-]","-"))
        end
    end end
    for i,p in ipairs(f.plants) do
        emit("CROP",i.." state="..tostring(p.state).." water="..tostring(p.waterLvl).." health="..tostring(p.health))
        if (p.waterLvl or 0)>25 then f.cropWatered[i]=true end
    end
    for _,row in ipairs(f.pens) do
        row.watered=row.watered or (tonumber(v(row.trough,"getWater")) or 0)>2.2
        row.fed=row.fed or (tonumber(v(row.feeder,"getCurrentFeedAmount")) or 0)>0
        emit("TROUGH",row.name.." water="..tostring(v(row.trough,"getWater")).." maxWater="..tostring(v(row.trough,"getMaxWater"))
            .." feed="..tostring(v(row.feeder,"getCurrentFeedAmount")).." maxFeed="..tostring(v(row.feeder,"getMaxFeed")))
    end
    emit("HUTCH","closed="..tostring(f.hutch:isDoorClosed()).." inside="..tostring(v(f.hutch:getAnimalInside(),"size")))
    if f.hutch:isDoorClosed() then f.hutchClosed=true
    elseif f.hutchClosed then f.hutchReopened=true end
    for label,container in pairs({food=f.food,wool=f.wool,manure=f.overflow,composter=f.compost:getContainer()}) do
        local counts={}
        for _,item in ipairs(SC.GameplayUtil.inventoryItems(container,256)) do
            local kind=SC.GameplayUtil.itemType(item) counts[kind]=(counts[kind] or 0)+1
        end
        for kind,count in pairs(counts) do emit("STOCK",label.." "..kind.."="..count) end
    end
    for _,item in ipairs(SC.GameplayUtil.inventoryItems(f.farming,64)) do
        if SC.GameplayUtil.itemType(item)=="Base.Bucket" then emit("BUCKET","storage amount="..tostring(v(v(item,"getFluidContainer"),"getAmount"))
            .." milkEligible="..tostring(SC.AnimalWork.milkContainer(item,"CowMilk"))) end
    end
    -- The stationary camera operator is supported by the harness. Workers and
    -- animals get no replenishment or stat writes after setup.
    H.player:getStats():set(CharacterStat.HUNGER,0.1) H.player:getStats():set(CharacterStat.THIRST,0.1)
    local day=math.floor(h/24)
    if day~=(f.day or -1) then f.day=day shot(H,f,"farm-day-"..day) end
    local tod=getGameTime():getTimeOfDay()
    if tod>=21 and tod<22 and f.night~=day then f.night=day shot(H,f,"farm-night-"..day) end
end
local function step(H,current,check,result,setPhase)
    local SC,U=SurvivorCompanion,SurvivorCompanion.GameplayUtil
    local f=H.farmSoak
    if not f then
        f={stage="load",at=current,crew={}} H.farmSoak=f
        f.decision=SC.Decision.update SC.Decision.update=function() return true,"farm_soak_setup" end
        local get=SC.Config.get
        local overrides={productionEncounterEnabled=false,factionEnabled=false,oddballsEnabled=false,
            animalWorkEnabled=1,animalCattleEnabled=1,animalSheepEnabled=1,animalMilkEnabled=1,animalSheepMilkEnabled=1,animalShearEnabled=1}
        SC.Config.get=function(section,key)
            local name=key and SC.Config._aliases[section] and SC.Config._aliases[section][key] or section
            if overrides[name]~=nil then return overrides[name] end return get(section,key)
        end
        for _,r in ipairs(SC.Registry.snapshot()) do if r.actor and r.recruited and not r.actor:isDead() then
            SC.BaseWork.cancel(r.actor,"farm_soak_setup") f.crew[#f.crew+1]=r
        end end
        movePlayer(H.player,8180.5,11772.5)
        emit("LOAD","requesting Rosewood grassy farm site; original save is untouched")
        return
    end
    if f.shot and current>=f.shot.at then getCore():TakeFullScreenshot(H.config.run_id.."-"..f.shot.label..".png") f.shot=nil end
    if f.stage=="failed" then
        if not f.shot then SC.Decision.update=f.decision setPhase("finish",current) end return
    end
    if f.stage=="load" then
        if current-f.at<5000 then return end
        f.candidates=f.candidates or {x=8144,y=11740,index=0,offset=0}
        local c=f.candidates local budget=128
        while budget>0 and c.index<64 do
            local x,y=c.x+(c.index%8)*6,c.y+math.floor(c.index/8)*6
            local xx,yy=x+c.offset%24,y+math.floor(c.offset/24)
            local sq=getSquare(xx,yy,0) budget=budget-1
            local sprite=sq and v(v(sq,"getFloor"),"getSprite") local name=sprite and v(sprite,"getName") or ""
            local obstacle=sq and U.squareOccupyingObject(sq)
            local vegetation=obstacle and (U.instanceOf(obstacle,"IsoTree")
                or tostring(v(v(obstacle,"getSprite"),"getName") or ""):find("vegetation_",1,true)==1)
            if not sq or not sq:isOutside() or obstacle and not vegetation
                or sq:isVehicleIntersecting() or not tostring(name):find("blends_natural",1,true) then c.index=c.index+1 c.offset=0
            else c.offset=c.offset+1 end
            if c.offset>=24*26 then f.x,f.y=x,y clearSite(f) f.stage="crew" emit("SITE",x..","..y) break end
        end
        if c.index>=64 then check("farm_soak_site",false,"no clear grassy 24x26 site") shot(H,f,"blocked-site") f.stage="failed" end
    elseif f.stage=="crew" then
        if #f.crew<3 then
            if not f.ticket then
                local square
                for dx=2,21 do for dy=2,23 do local sq=getSquare(f.x+dx,f.y+dy,0)
                    local occupied=U.sameSquare(H.player,sq)
                    for _,r in ipairs(f.crew) do if U.distance(r.actor,sq)<2 then occupied=true end end
                    if U.isClearActorSpawnSquare(sq) and not occupied then square=sq break end
                end if square then break end end
                assert(square,"no clear native worker spawn tile")
                local why
                f.ticket,why=SC.Actor.beginSpawn(square,{recruited=true,
                    identity=SC.Spawn.generateIdentity({allowFamous=false})})
                assert(f.ticket,tostring(why))
            end
            local a,why=SC.Actor.pollSpawn(f.ticket)
            if a then f.crew[#f.crew+1]=assert(SC.Registry.byId(U.idOf(a))) f.ticket=nil
            elseif why~="spawn_pending" then error("farm worker spawn: "..tostring(why)) end
            return
        end
        local okay,why=pcall(setupFarm,H,f)
        if not okay then check("farm_soak_setup",false,tostring(why)) emit("SETUP_ERROR",why) shot(H,f,"blocked-setup") f.stage="failed" end
    elseif f.stage=="run" then
        for _,r in ipairs(f.crew) do
            local kind=SC.NativeActions.workKind(r.actor)
            if kind=="farm_animal_soothe" and not f.sootheShot then
                f.sootheShot=true f.sootheSlowUntil=current+5000
                UIManager.getSpeedControls():SetCurrentGameSpeed(1) getGameTime():setMultiplier(1)
                emit("SOOTHE_START","worker="..r.id.." stress="..f.sootheAnimal:getStress())
                shot(H,f,"native-animal-soothing")
            end
            if kind=="farm_fill_water" then
                local load,limit=U.carryLoad(r.actor)
                f.maxFillExcess=math.max(f.maxFillExcess or 0,load-limit)
            end
        end
        local elapsed=getGameTime():getWorldAgeHours()-f.startHour
        if math.floor(elapsed)~=f.hour then f.hour=math.floor(elapsed) sample(H,f,check) end
        if current>(f.sootheSlowUntil or 0) and current-(f.speedAt or 0)>5000 then
            f.speedAt=current UIManager.getSpeedControls():SetCurrentGameSpeed(2) getGameTime():setMultiplier(5)
        end
        if getGameTime():getWorldAgeHours()>=f.untilHour then
            for op,count in pairs(f.counts) do emit("TOTAL",op.."="..count) end
            local all=true for _,a in ipairs(f.animals) do if a:isDead() then all=false end end
            check("farm_soak_animals_alive",all,"animals="..#f.animals.." minimum health="..f.minHealth)
            check("farm_soak_requested_days",elapsed>=24*tonumber(H.config.farm_services_days),"continuous game hours="..elapsed)
            check("farm_soak_fill_carry_limit",(f.maxFillExcess or 0)<0.02,"maximum excess during native water fill="..tostring(f.maxFillExcess))
            for _,row in ipairs(f.pens) do
                check("farm_soak_water_"..row.name,row.watered==true,"native water delivered")
                check("farm_soak_feed_"..row.name,row.fed==true,"native feed delivered")
            end
            local watered=0 for _ in pairs(f.cropWatered) do watered=watered+1 end
            check("farm_soak_crops_watered",watered==#f.plants,"watered="..watered.."/"..#f.plants)
            local milkTypes={}
            for _,object in ipairs({f.cowMilk,f.sheepMilk}) do
                local info=SC.FarmStorage.milkInfo(object)
                if info and info.amount>0 and info.fluid then milkTypes[info.fluid]=true end
            end
            check("farm_soak_milk_stored",milkTypes.CowMilk and milkTypes.SheepMilk,"both native milk types delivered")
            check("farm_soak_shearing",(f.counts.animal_shear or 0)>0,"native shearing completed")
            check("farm_soak_hutch_cycle",f.hutchClosed and f.hutchReopened,"closed safely and reopened")
            shot(H,f,"farm-final") f.stage="done"
            result("PASS","farm_soak_observed","continuous hours="..elapsed.."; inspect hourly welfare, blocks and job totals")
        end
    elseif f.stage=="done" and not f.shot then
        setPhase("finish",current)
    end
end
function P.step(H,current,check,result,setPhase)
    local okay,why=pcall(step,H,current,check,result,setPhase)
    if not okay then
        check("farm_soak_fixture",false,tostring(why)) emit("FIXTURE_ERROR",why)
        local f=H.farmSoak
        if f then shot(H,f,"blocked-fixture") f.stage="failed" else setPhase("finish",current) end
    end
end
function P.inspect(H,current,check,result,setPhase)
    local SC,U,B=SurvivorCompanion,SurvivorCompanion.GameplayUtil,SurvivorCompanion.BaseLife
    local f=H.farmInspect or {at=current,nextAt=current+6000,shots={}} H.farmInspect=f
    if current<f.nextAt then return end f.nextAt=current+15000
    local base=B.active()
    if not base then check("farm_inspection_saved_camp",false,"saved camp missing") setPhase("finish",current) return end
    emit("INSPECT","base="..tostring(base.name).." ageHours="..getGameTime():getWorldAgeHours())
    local farm=SC.FarmWork.summary()
    emit("AUDIT","plots="..tostring(farm.knownPlots).." blocker="..tostring(farm.chickenBlocker).." receipts="..tostring(farm.receipts))
    local function inventory(container,label)
        for _,item in ipairs(U.inventoryItemsDeep(container,128,6)) do
            local fc=v(item,"getFluidContainer")
            emit("ITEM",label.." type="..U.itemType(item).." id="..tostring(v(item,"getID")).." weight="..U.itemWeight(item)
                .." amount="..tostring(v(fc,"getAmount")).." capacity="..tostring(v(fc,"getCapacity"))
                .." milkEligible="..tostring(SC.AnimalWork.milkContainer(item,"CowMilk")))
        end
    end
    for _,s in ipairs(B.storageRows()) do
        emit("STORAGE",s.id.." category="..s.category.." withdraw="..tostring(B.withdrawable(s)).." deposits="..tostring(s.deposits))
        if s.category=="milk" then
            local fc=B.resolveFluidContainer(s)
            emit("FLUID",s.id.." amount="..tostring(v(fc,"getAmount")).." cow="..tostring(v(fc,"isPureFluid",Fluid.CowMilk))
                .." sheep="..tostring(v(fc,"isPureFluid",Fluid.SheepMilk)))
        else
            local c=B.resolveContainer(s) if c then inventory(c,s.id) end
        end
    end
    for _,r in ipairs(SC.Registry.snapshot()) do if r.actor and r.recruited then
        local d=SC.Decision.peek(r.actor) or {} local n=SC.Navigation.status(r.actor) or {}
        local load,limit=U.carryLoad(r.actor)
        emit("INSPECT_CREW",r.id.." role="..tostring(B.resident(r.id) and B.resident(r.id).role)
            .." intent="..tostring(d.intent).." nav="..tostring(n.lastMovementReason).." load="..tostring(load).."/"..tostring(limit))
        emit("INSPECT_OWNER",r.id.." fatigue="..r.actor:getStats():get(CharacterStat.FATIGUE)
            .." native="..tostring(SC.NativeActions.workKind(r.actor)).." kitBusy="..tostring(SC.MedicKit.busy(r.actor))
            .." primary="..U.itemType(v(r.actor,"getPrimaryHandItem")).." secondary="..U.itemType(v(r.actor,"getSecondaryHandItem")))
        inventory(r.actor:getInventory(),r.id)
    end end
    for _,j in ipairs(base.jobs) do
        emit("JOB",j.id.." state="..j.state.." op="..tostring(j.target and j.target.operation)
            .." blocker="..tostring(j.blocker).." owner="..tostring(j.reservedBy))
        if j.state=="blocked" and not f.shots[j.id] then
            f.shots[j.id]=true
            for _=1,8 do if getCore():getZoom(0)<1.8 then getCore():doZoomScroll(0,1) end end
            getCore():TakeFullScreenshot(H.config.run_id.."-inspect-blocked-"..j.id:gsub(":","-")..".png")
        end
    end
    for _,r in ipairs(B.farmReceipts(nil,false)) do
        emit("RECEIPT",r.id.." job="..r.jobId.." phase="..r.phase.." item="..r.itemType.." actor="..r.actorId.." source="..tostring(r.sourceStorageId))
    end
    local area
    for _,z in ipairs(base.zones) do if z.kind=="area" then area=z break end end
    if area then
        for _,offset in ipairs({{3,13},{3,15},{14,15},{14,17},{15,3},{15,5}}) do
            local sq=getSquare(area.x1+offset[1],area.y1+offset[2],0)
            U.squareObjects(sq,function(o) if U.instanceOf(o,"IsoFeedingTrough") then
                emit("TROUGH",sq:getX()..","..sq:getY().." water="..tostring(v(v(o,"getFluidContainer"),"getAmount"))
                    .." maxWater="..tostring(v(o,"getMaxWater")).." feed="..tostring(v(o,"getCurrentFeedAmount")).." maxFeed="..tostring(v(o,"getMaxFeed")))
            end end,16)
        end
    end
    if current-f.at>45000 then
        result("PASS","farm_soak_inspection","saved farm stock, loans, jobs and troughs logged at normal speed") setPhase("finish",current)
    end
end
return P
