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
    P.zone = DesignationZoneAnimal.new("LF chicken acceptance", x+1,y+1,0,x+9,y+9,true)
    P.zone:createSurroundingFence()
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
    P.food = crate(getSquare(x+6,y+2,0), "food")
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
    P.settings = { baseAlertEnabled=false, animalWorkEnabled=0 }
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
    SC.BaseLife.assign(P.record.id,"farmer",true)
    SC.Commands.issue(P.record.id,"base_duty",nil,player)
    P.startedAt, P.phase = getTimestampMs(), "baseline"
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
local function observe(H, current)
    local SC = SurvivorCompanion
    local inside = P.hutch:getAnimalInside():size()
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
    if P.phase == "baseline" then
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
