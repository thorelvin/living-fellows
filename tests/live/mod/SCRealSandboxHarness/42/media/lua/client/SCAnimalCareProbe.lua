-- SPDX-License-Identifier: MIT
-- Disposable clone only. Real native objects, stock actions and unassisted birds.
local P = { nextAt = 0, phase = "waiting", samples = {} }
local function emit(text) print("SC_ANIMAL_ACCEPTANCE|" .. tostring(text)) end
local function call(object, method, ...)
    local result, okay = SurvivorCompanion.GameplayUtil.call(object, method, ...)
    if not okay then error("native call unavailable: " .. method) end
    return result
end
local function write(text)
    local writer = getFileWriter("SurvivorCompanionHarness/animal-care.txt", true, false)
    writer:write(text) writer:close()
end
local function screenshot(label)
    for _=1,8 do if getCore():getZoom(0)<1.8 then getCore():doZoomScroll(0,1) end end
    P.shotAt, P.shotLabel = getTimestampMs()+1500, label
end
local function crate(square, category)
    local object = IsoThumpable.new(getCell(), square, "carpentry_01_16", false, {})
    object:setIsContainer(true)
    object:setContainer(ItemContainer.new("crate", square, object))
    object:getContainer():setCapacity(50)
    square:AddSpecialObject(object)
    assert(SurvivorCompanion.BaseLife.registerStorage(object, category))
    return object
end
local function fence(x,y,north)
    local square=getSquare(x,y,0)
    local object=IsoThumpable.new(getCell(),square,north and "fencing_01_1" or "fencing_01_2",north,{})
    object:setIsHoppable(true) object:setCanPassThrough(false) object:setIsThumpable(false)
    square:AddSpecialObject(object) square:RecalcAllWithNeighbours(true)
end
local function setup(H)
    local SC, U, player = SurvivorCompanion, SurvivorCompanion.GameplayUtil, H.player
    local records = SC.Registry.records()
    if #records == 0 then return false end
    P.record = records[1]
    for _, record in ipairs(records) do SC.BaseLife.setDuty(record.id, false) end
    local base=SC.BaseLife.active()
    local ids={}
    for _, job in ipairs(base and base.jobs or {}) do ids[#ids+1]=job.id end
    for _, id in ipairs(ids) do
        local okay, why=SC.BaseLife.cancelJob(id)
        if not okay then emit("EXISTING_JOB retained="..id.." reason="..tostring(why)) end
    end
    local px, py = math.floor(player:getX()), math.floor(player:getY())
    P.search = (P.search or 0) + 1
    local x, y = px - 24 + (P.search % 7) * 8, py - 24 + math.floor(P.search / 7) * 8
    if P.search > 48 then error("no clear loaded outdoor pen site") end
    for xx = x, x + 9 do for yy = y, y + 9 do
        local square = getSquare(xx, yy, 0)
        if not square or not square:isOutside() or not U.isSquareFree(square)
            or U.squareOccupyingObject(square) or square:isVehicleIntersecting() then return false end
    end end
    if not SC.BaseLife.active() then assert(SC.BaseLife.create(getSquare(x+4,y+4,0), "Chicken acceptance")) end
    assert(SC.BaseLife.beginZone("area", getSquare(x,y,0)))
    assert(SC.BaseLife.finishZone(getSquare(x+9,y+9,0), "Chicken acceptance"))
    assert(SC.BaseLife.setPolicy("autoMaintenance",false))
    if not SC.BaseLife.zoneCenter("rally") then
        assert(SC.BaseLife.beginZone("rally",getSquare(x+5,y+7,0)))
        assert(SC.BaseLife.finishZone(getSquare(x+5,y+7,0),"Animal acceptance rally"))
    end
    if H.config.animal_night_probe=="true" then
        local zones=SC.BaseLife.active().zones
        -- This isolated fixture's Farmer lives inside the fenced pen. Keep
        -- its new camp area/rally, rather than routing to the source house
        -- through a deliberately closed animal fence.
        for index=#zones,1,-1 do
            local zone=zones[index]
            if zone.kind=="area" and (zone.x1~=x or zone.y1~=y) then table.remove(zones,index) end
        end
        for _,zone in ipairs(zones) do
            if zone.kind=="rally" then
                zone.x1,zone.x2,zone.y1,zone.y2,zone.z=x+5,x+5,y+7,y+7,0
            end
        end
        SC.BaseLife.noteWorkOwnershipMutation()
    end
    P.zone = DesignationZoneAnimal.new("LF chicken acceptance", x+1,y+1,0,x+9,y+9,true)
    if H.config.animal_night_probe=="true" then
        for i=1,8 do
            fence(x+i,y+1,true)
            fence(x+i,y+9,true)
            fence(x+1,y+i,false) fence(x+9,y+i,false)
        end
    end
    local def = HutchDefinitions.hutchs.hutchhen
    P.hutch = IsoHutch.new(getSquare(x+3,y+4,0),false,def.baseSprite,def,nil)
    P.trough = IsoFeedingTrough.new(getSquare(x+6,y+5,0),"location_farm_accesories_01_14",nil)
    P.trough:setNorth(false) P.trough:initWithDef()
    getSquare(x+6,y+5,0):AddSpecialObject(P.trough)
    P.trough:setMaxWater(2) P.trough:setMaxFeed(10) P.trough:updateLuaObject()
    P.trough:getFluidContainer():setCapacity(2)
    local troughSystem = SFeedingTroughSystem.instance
    local troughLua = troughSystem:getLuaObjectAt(x+6,y+5,0)
    if not troughLua then
        troughLua = troughSystem:newLuaObjectOnSquare(getSquare(x+6,y+5,0))
        troughLua:initNew()
    end
    troughLua:stateFromIsoObject(P.trough)
    assert(troughLua:getIsoObject()==P.trough, "trough server registration")
    P.feeder=IsoFeedingTrough.new(getSquare(x+6,y+6,0),"location_farm_accesories_01_14",nil)
    P.feeder:setNorth(false) P.feeder:initWithDef()
    getSquare(x+6,y+6,0):AddSpecialObject(P.feeder)
    P.feeder:setMaxFeed(10) P.feeder:updateLuaObject()
    P.feeder:checkContainer()
    P.feed = crate(getSquare(x+6,y+3,0), "farming")
    P.food = crate(getSquare(x+6,y+2,0), "fresh_food")
    for _=1,12 do P.food:getContainer():AddItem("Base.Bread") end
    P.feedItem = P.feed:getContainer():AddItem("Base.AnimalFeedBag")
    P.mop=P.feed:getContainer():AddItem("Base.Mop")
    P.cleaner=P.feed:getContainer():AddItem("Base.Bleach")
    local water = P.feed:getContainer():AddItem("Base.WateredCan")
    P.water = water
    water:getFluidContainer():Empty()
    water:getFluidContainer():addFluid(Fluid.Water, water:getFluidContainer():getCapacity())
    P.birds = {}
    for i, kind in ipairs({ "hen", "hen", "cockerel" }) do
        local definition = AnimalDefinitions.getDef(kind)
        local breed = definition:getBreedByName("rhodeisland")
        assert(breed, "chicken breed missing")
        local bird = addAnimal(getCell(),x+3+i*0.5,y+6,0,kind,breed,false)
        bird:addToWorld() bird:setWild(false) bird:setDZone(P.zone) P.zone:addAnimal(bird)
        P.birds[#P.birds+1] = bird
    end
    P.hutch:getNestBox(0):addEgg(P.birds[1]:createEgg())
    P.egg = P.hutch:getNestBox(0):getEgg(0)
    if P.egg then P.egg:setFertilized(false) P.eggId = P.egg:getID() end
    P.zone:check()
    local zombies = getCell():getZombieList()
    local cleared = 0
    for index=zombies:size()-1,0,-1 do
        local zombie=zombies:get(index)
        if (zombie:getX()-(x+5))^2+(zombie:getY()-(y+5))^2 < 40^2 then
            zombie:removeFromWorld() zombie:removeFromSquare() cleared=cleared+1
        end
    end
    P.settings = { baseAlertEnabled=false, animalWorkEnabled=0,
        productionEncounterEnabled=false, factionEnabled=false, oddballsEnabled=false }
    local originalGet=SC.Config.get
    SC.Config.get=function(section,key)
        local flat=key and SC.Config._aliases[section] and SC.Config._aliases[section][key] or section
        if P.settings[flat]~=nil then return P.settings[flat] end
        return originalGet(section,key)
    end
    SC.BaseAlert.reset()
    emit("QUIET_FIXTURE zombies_removed="..cleared.." alert_disabled_in_clone=true")
    P.stand = {x=x+5.5,y=y+5.5,z=0}
    assert(H.placeCombatActor(P.record.actor, { x=x+5.5,y=y+5.5,z=0 }))
    player:setX(x+5.5) player:setY(y+7.5) player:setZ(0)
    player:setCurrentSquareFromPosition()
    player:setSquare(player:getCurrentSquare()) player:setMovingSquare(player:getCurrentSquare())
    getGameTime():setTimeOfDay(10)
    local audit = SC.FarmWork.audit
    SC.FarmWork.audit = function(...)
        local start = SC.Performance.preciseNowMs()
        local a,b,c = audit(...)
        emit("AUDIT queued="..tostring(a).." detail="..tostring(b))
        local samples = P.samples[P.phase] or {}
        P.samples[P.phase] = samples
        if #samples < 256 then samples[#samples+1] = SC.Performance.preciseNowMs()-start end
        return a,b,c
    end
    local startAnimal = SC.NativeActions.startAnimal
    SC.NativeActions.startAnimal = function(actor,intent)
        local result,reason=startAnimal(actor,intent)
        if result then
            P.lastAction=ISTimedActionQueue.getTimedActionQueue(actor).current
            emit("NATIVE_START op="..intent.operation.." duration="..tostring(P.lastAction.maxTime))
        end
        return result,reason
    end
    if H.config.animal_night_probe=="true" then
        local roostReady=SC.AnimalWork.roostReady
        SC.AnimalWork.roostReady=function(row,strict)
            local ready,reason=roostReady(row,strict)
            local current=getTimestampMs()
            if not P.nextRoostLog or current>=P.nextRoostLog then
                P.nextRoostLog=current+10000
                emit("ROOST_CHECK ready="..tostring(ready).." strict="..tostring(strict)
                    .." reason="..tostring(reason).." census="..tostring(row and #row.animals)
                    .." config="..tostring(SC.GameplayUtil.config("animalCloseEnabled")))
            end
            return ready,reason
        end
    end
    SC.BaseLife.assign(P.record.id,"farmer",true)
    SC.Commands.issue(P.record.id,"base_duty",nil,player)
    P.startedAt, P.phase = getTimestampMs(), "baseline"
    if H.config.animal_night_probe=="true" then
        if P.hutch:isDoorClosed() then P.hutch:toggleDoor() end -- Initial fixture state only.
        P.hutch:setHutchDirt(0) P.hutch:setNestBoxDirt(0)
        P.settings.animalWorkEnabled,P.settings.animalCloseEnabled=1,1
        P.trough:getFluidContainer():addFluid(Fluid.Water,1.8)
        P.feed:getContainer():Remove(P.feedItem)
        P.feeder:getContainer():AddItem(P.feedItem)
        -- Three natural calendar cycles; no forced hutch entry, door toggles,
        -- bird relocation or needs resets during observation.
        getGameTime():setMinutesPerDay(4)
        getGameTime():setTimeOfDay(19.8)
        P.cycles,P.phase,P.nightAt=0,"night",getTimestampMs()
        emit("NIGHT_SETUP cycles=3 minutes_per_day=4 physical_fence=true")
    end
    screenshot("setup")
    emit("SETUP pen="..x..","..y.." worker="..P.record.id.." scheduler=normal")
    return true
end
local function startRoost(H,current)
    local SC=SurvivorCompanion
    P.settings.animalWorkEnabled=0
    SC.BaseLife.setDuty(P.record.id,false)
    SC.Commands.issue(P.record.id,"stay",nil,H.player)
    if P.hutch:isDoorClosed() then P.hutch:toggleDoor() end
    getGameTime():setMinutesPerDay(2)
    getGameTime():setTimeOfDay(19.8)
    P.phase,P.roostAt="roost",current
end
local function shelteredCount()
    local count=P.hutch:getAnimalInside():size()
    for index=0,P.hutch:getMaxNestBox() do
        if P.hutch:getAnimalInNestBox(index) then count=count+1 end
    end
    return count
end
local function observe(H, current)
    local SC = SurvivorCompanion
    local inside = shelteredCount()
    local hour = getGameTime():getTimeOfDay()
    local text = "phase="..P.phase.." hour="..hour.." inside="..inside
        .." water="..P.trough:getWater().." feed="..P.feeder:getCurrentFeedAmount()
        .." closed="..tostring(P.hutch:isDoorClosed())
        .." actor="..tostring(SC.NativeActions.workKind(P.record.actor))
        .." decision="..tostring((SC.Decision.peek(P.record.actor) or {}).intent)
        .." donor="..P.water:getFluidContainer():getAmount()
        .." actionTimer="..tostring(P.lastAction and P.lastAction.timer)
        .." actionLastTimer="..tostring(P.lastAction and P.lastAction.lastTimer)
        .." multiplier="..getGameTime():getMultiplier()
    emit(text)
    if P.phase=="night" then
        SC.FarmWork.audit(SC.BaseLife.active())
        if not P.nextBirdAt or current>=P.nextBirdAt then
            P.nextBirdAt=current+10000
            for _,bird in ipairs(P.birds) do
                emit("BIRD id="..bird:getAnimalID().." health="..bird:getHealth()
                    .." hunger="..bird:getHunger().." thirst="..bird:getThirst()
                    .." pos="..bird:getX()..","..bird:getY()
                    .." hutch="..tostring(bird:getHutch()==P.hutch))
                if bird:getHealth()<=0 then error("bird died during night acceptance") end
            end
        end
        local closed=P.hutch:isDoorClosed()
        if not closed and hour>=21 and hour<24 and not P.closedBlockShot then
            P.closedBlockShot=true screenshot("night-close-pending")
        end
        if P.closedThisNight and closed and hour>=9 and hour<20 and not P.openBlockShot then
            P.openBlockShot=true screenshot("dawn-open-pending")
        end
        if closed then
            if inside~=#P.birds then error("hutch closed with a bird outside") end
            if not P.closedThisNight then
                P.closedThisNight=true
                emit("NIGHT_CLOSED cycle="..(P.cycles+1).." inside="..inside)
                screenshot("night-"..(P.cycles+1).."-closed")
            end
        elseif P.closedThisNight and hour>=7 and hour<20 and inside==0 then
            P.cycles=P.cycles+1 P.closedThisNight=false
            P.closedBlockShot,P.openBlockShot=nil,nil
            emit("NIGHT_CYCLE_PASS cycles="..P.cycles.." native_exit=true")
            screenshot("night-"..P.cycles.."-open")
            if P.cycles>=3 then
                P.phase="passed"
                write("PASS night_cycles=3 exact_birds="..#P.birds.." healthy=true")
                P.finishAfterShot=true
            end
        end
        if current-P.nightAt>1200000 then error("night acceptance deadline cycles="..P.cycles) end
    elseif P.phase == "baseline" then
        if current-P.startedAt >= 15000 then
            assert(H.placeCombatActor(P.record.actor,P.stand))
            P.settings.animalWorkEnabled = 1
            P.startedAt, P.phase = current,"care"
            local map=P.hutch:getAnimalInside()
            local values=call(map,"values")
            local _, iteratorOkay=SC.GameplayUtil.call(values,"iterator")
            emit("API streamed="..tostring(P.zone:isFullyStreamed())
                .." iterator="..tostring(iteratorOkay)
                .." zones="..DesignationZoneAnimal.getAllZones():size()
                .." geometry="..P.zone:getX()..","..P.zone:getY()..","..P.zone:getW()..","..P.zone:getH()
                .." hutches="..P.zone:getHutchs():size().." troughs="..P.zone:getTroughs():size()
                .." animalType="..P.birds[1]:getAnimalType()
                .." animalAge="..P.birds[1]:getAge()
                .." female="..tostring(P.birds[1]:getData():isFemale()))
        end
    elseif P.phase == "care" then
        -- Accelerate only the audit cadence in this disposable action test.
        -- The normal BaseWork controller still owns every claim and action.
        SC.FarmWork.audit(SC.BaseLife.active())
        for _,job in ipairs(SC.BaseLife.active().jobs) do
            if job.target and job.target.animal and job.state=="blocked" then
                if not P.firstBlockAt then
                    P.firstBlockAt=current
                    emit("BLOCK job="..job.id.." reason="..tostring(job.blocker))
                    screenshot("job-block")
                end
            end
        end
        if P.firstBlockAt and current-P.firstBlockAt>=10000 then
            P.care=false
            startRoost(H,current)
            return
        end
        local exactEgg=false
        for _,storage in ipairs(SC.BaseLife.foodDepositRows(P.egg)) do
            local container=SC.BaseLife.resolveContainer(storage)
            if container and SC.BaseLife.storageAcceptsDeposit(storage,container)
                and container:contains(P.egg) and P.egg:getContainer()==container then
                exactEgg,P.eggStorage=true,storage.id break
            end
        end
        local feedContainer=P.feeder:getContainer()
        local exactFeed=feedContainer and feedContainer:contains(P.feedItem)
            and P.feedItem:getContainer()==feedContainer
        if P.trough:getWater() >= 1.799 and P.feeder:getCurrentFeedAmount() >= 8.999
            and exactFeed and exactEgg then
            P.care = true
            P.settings.animalCleanEnabled=1
            P.hutch:setHutchDirt(30) P.hutch:setNestBoxDirt(30)
            P.phase,P.cleanAt="clean",current
            screenshot("care-passed")
            emit("CARE_PASS egg="..P.eggId.." exact=true storage="..P.eggStorage
                .." feed="..P.feedItem:getID().." exact_feed=true donor="..P.water:getFluidContainer():getAmount())
            for _, label in ipairs({"baseline","care"}) do
                local samples=P.samples[label] or {} table.sort(samples)
                emit("TIMING "..label.." samples="..#samples
                    .." median="..tostring(samples[math.max(1,math.ceil(#samples*0.5))])
                    .." p95="..tostring(samples[math.max(1,math.ceil(#samples*0.95))])
                    .." max="..tostring(samples[#samples]))
            end
        elseif current-P.startedAt>180000 then
            P.care = false
            emit("BLOCK care deadline "..tostring(SC.FarmWork.summary().lastBlocker))
            write("BLOCK "..text)
            screenshot("care-block")
            startRoost(H,current)
        end
    elseif P.phase == "clean" then
        SC.FarmWork.audit(SC.BaseLife.active())
        for _,job in ipairs(SC.BaseLife.active().jobs) do
            if job.target and job.target.animal and job.state=="blocked" and not P.cleanBlockAt then
                P.cleanBlockAt=current
                emit("BLOCK clean job="..job.id.." reason="..tostring(job.blocker))
                screenshot("clean-job-block")
            end
        end
        local inventory=P.feed:getContainer()
        if P.hutch:getHutchDirt()==0 and P.hutch:getNestBoxDirt()==0
            and inventory:contains(P.mop) and P.mop:getContainer()==inventory
            and inventory:contains(P.cleaner) and P.cleaner:getContainer()==inventory then
            P.clean=true emit("CLEAN_PASS exact_tools_returned=true")
            startRoost(H,current)
        elseif current-P.cleanAt>180000 or P.cleanBlockAt and current-P.cleanBlockAt>10000 then
            emit("BLOCK cleaning deadline") screenshot("clean-block")
            startRoost(H,current)
        end
    elseif P.phase == "roost" then
        if inside >= #P.birds then P.entered = true end
        if P.entered and hour >= 7 and hour < 20 and inside == 0 then
            P.phase = "passed"
            write((P.care and P.clean and "PASS" or "BLOCK care_or_clean")
                .." unassisted_roost=true unassisted_exit=true egg="..P.eggId)
            emit("ROOST_PASS unaided=true")
            screenshot("roost-passed")
            P.finishAfterShot = true
        elseif current-P.roostAt>180000 then
            write("BLOCK roost entered="..tostring(P.entered).." "..text)
            emit("BLOCK roost deadline") P.phase = "blocked"
            screenshot("roost-block")
        end
    end
end
local function tick()
    local H = SCRealSandboxHarness
    if not H or H.config.animal_care_probe ~= "true" or H.finished then return end
    local current = getTimestampMs()
    if current < P.nextAt then return end
    P.nextAt = current + 1000
    if P.shotAt and current >= P.shotAt then
        local name = H.config.run_id .. "-animal-" .. P.shotLabel .. ".png"
        P.shotAt = nil
        getCore():TakeFullScreenshot(name)
        emit("SCREENSHOT "..name)
        if P.finishAfterShot then H.phase = "finish" end
    end
    local okay, reason = pcall(function()
        if P.phase == "waiting" then
            if H.player and SurvivorCompanion.BaseLife and H.phase ~= "idle" then setup(H) end
        elseif P.phase ~= "blocked" and P.phase ~= "passed" then observe(H,current) end
    end)
    if not okay then
        P.phase = "blocked" emit("BLOCK "..tostring(reason)) write("BLOCK "..tostring(reason))
        screenshot("fixture-block")
    end
end
if Events and Events.OnTick then Events.OnTick.Add(tick) end
