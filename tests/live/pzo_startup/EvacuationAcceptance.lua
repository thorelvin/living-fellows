-- SPDX-License-Identifier: MIT
-- Native PZO acceptance for a disposable Rosewood save. Only the fixture player,
-- test vehicle and initial zombie are placed by the probe.
local SC = SurvivorCompanion
local state = { phase = "menu", buildings = {}, distance = 0 }

local function write(name, value)
    local writer = assert(getFileWriter(name, true, false))
    writer:write(value .. "\n")
    writer:close()
end

local function read(name)
    local reader = getFileReader(name, false)
    local value = reader and reader:readLine()
    if reader then reader:close() end
    return value
end

local function phase(name)
    state.phase, state.since = name, getTimestampMs()
    write("evacuation-progress.txt", name)
    print("SC_PZO_EVACUATION " .. name)
end

local function finish(result, reason)
    state.done = true
    write("evacuation-result.txt", "result=" .. result .. "\nmode=" .. state.mode
        .. "\nphase=" .. state.phase .. "\nreason=" .. tostring(reason)
        .. "\ndistance=" .. tostring(state.distance))
end

local function encounter()
    for _, group in ipairs(SC.Factions.list(true)) do
        if group.oddball and group.oddball.id == "evacuation" then return group end
    end
end

local function openRoomSide(site)
    local post = site.safeRoomDoor
    local ox, oy = post.x - (post.north and 0 or 1), post.y - (post.north and 1 or 0)
    if site.spawn.x ~= post.x or site.spawn.y ~= post.y then ox, oy = post.x, post.y end
    return { x = ox, y = oy, z = 0 }
end

local function doorFor(site)
    local point = site.safeRoomDoor
    local square = getCell():getGridSquare(point.x, point.y, point.z)
    return square and square:getObjects():get(point.objectIndex)
end

local function prepare(car)
    for index = 0, car:getPartCount() - 1 do
        local part = car:getPartByIndex(index)
        part:setCondition(100)
        local item = part:getInventoryItem()
        if item then item:setCondition(item:getConditionMax()) end
        if string.find(part:getId(), "Tire", 1, true) then
            part:setContainerContentAmount(part:getContainerCapacity())
        end
        local door = part:getDoor()
        if door then door:setLocked(false) end
    end
    car:updatePartStats()
    local tank = car:getPartById("GasTank")
    if tank then tank:setContainerContentAmount(tank:getContainerCapacity()) end
    local battery = car:getBattery()
    local item = battery and battery:getInventoryItem()
    if item then item:setCurrentUsesFloat(1) end
end

local function waitOutside(player, house, car)
    local entry = house.primaryEntry or house.anchor
    local best, clearance
    for dx = -7, 7 do
        for dy = -7, 7 do
            local square = getCell():getGridSquare(entry.x + dx, entry.y + dy, 0)
            if square and square:isOutside() and SC.GameplayUtil.isSafeSpawnSquare(square) then
                local distance = SC.GameplayUtil.distance(square, car)
                if not clearance or distance > clearance then best, clearance = square, distance end
            end
        end
    end
    assert(best, "no place to stay clear of the doorway")
    player:teleportTo(best:getX() + 0.5, best:getY() + 0.5, 0)
end

local function rewards(story)
    local wanted = {}
    for _, entry in ipairs(story.rewardItems) do wanted[entry.id] = true end
    local counts = {}
    for _, item in ipairs(SC.GameplayUtil.inventoryItemsDeep(state.player:getInventory(), 1000, 32)) do
        if wanted[SC.GameplayUtil.itemStableId(item, false)] then
            local kind = item:getFullType()
            counts[kind] = (counts[kind] or 0) + 1
        end
    end
    assert(counts["Base.Antibiotics"] == 2 and counts["Base.Bandage"] == 2, "exact reward missing")
end

local function findSite()
    local player = state.player
    for _ = 1, 20 do
        local index = state.scan or 0
        state.scan = index + 1
        if index > 420 then error("no native evacuation shelter around the seed") end
        local angle, radius = index * 2.399963229728653, 23 + (index * 17 % 31)
        local x = math.floor(player:getX() + math.cos(angle) * radius)
        local y = math.floor(player:getY() + math.sin(angle) * radius)
        local square = getCell():getGridSquare(x, y, 0)
        local building = square and square:getBuilding()
        if building and not state.buildings[building] then
            state.buildings[building] = true
            local house = SC.Factions.oddballHouseAt(square, player, false)
            local site = house and SC.OddballEvacuation.siteFor(house, player, false)
            if site then return site end
        end
    end
end

Events.OnInitGlobalModData.Add(function()
    if read("evacuation-mode.txt") == "boarding" then
        ModData.getOrCreate(SC.Identity.worldSaveKey).document = {
            schema = SC.Identity.saveSchema, companions = {}, factionActors = {},
        }
    end
end)
Events.OnMainMenuEnter.Add(function() MainScreen.continueLatestSave("Sandbox", "PzoRestoreFixture") end)
local seen = {}
Events.OnRenderTick.Add(function()
    local modal = MainScreen and MainScreen.instance and MainScreen.instance.checkSavefileModal
    if modal and modal.yes and not seen[modal] then seen[modal] = true; modal:onClick(modal.yes) end
end)
Events.OnGameStart.Add(function()
    state.player = assert(getSpecificPlayer(0))
    state.mode = read("evacuation-mode.txt") or "boarding"
    local pulse = SC.OddballEvacuationVehicle.pulse
    SC.OddballEvacuationVehicle.pulse = function(group, player, current)
        local status, why = pulse(group, player, current)
        if why ~= state.vehicleReason then
            state.vehicleReason = why
            local function at(index)
                local actor = SC.OddballKit.recordActor(group, index)
                local x, y = SC.GameplayUtil.position(actor)
                return x and string.format("%.2f,%.2f", x, y) or "absent"
            end
            print("SC_PZO_EVACUATION vehicle=" .. tostring(why) .. " Joy=" .. at(1) .. " Brock=" .. at(2))
        end
        if state.mode == "departure" and status == "departed" then
            state.removalCommitted = true
            return "pending", "fixture_deletion_checkpoint"
        end
        return status, why
    end
    phase("load")
end)

local function step()
    local now = getTimestampMs()
    local player = state.player
    if state.phase == "load" then
        if now - state.since < 10000 then return end
        assert(PZOEngine and SCBridge and SC.OddballEvacuation.available(), "native evacuation capability unavailable")
        if state.mode == "boarding" then phase("find-site")
        else phase("resume") end
    elseif state.phase == "find-site" then
        local site = findSite()
        if not site then return end
        state.door = assert(doorFor(site))
        state.health = state.door:getHealth()
        state.group = assert(SC.Factions.createOddballGroup(site, SC.Oddballs.definition("evacuation"), true))
        local outside = openRoomSide(site)
        state.zombie = assert(createZombie(outside.x + 0.5, outside.y + 0.5, 0, nil, 0, IsoDirections.S))
        print("SC_PZO_EVACUATION site=" .. site.house.id .. " door=" .. site.safeRoomDoor.x .. "," .. site.safeRoomDoor.y)
        phase("initial-spawn")
    elseif state.phase == "initial-spawn" then
        local group = state.group
        local joy, brock = SC.OddballKit.livingActor(group, 1), SC.OddballKit.livingActor(group, 2)
        if not joy or not brock or not group.oddball.injurySeeded or not group.oddball.rewardItems then return end
        assert(group.oddball.sceneSecured and not getCell():getZombieList():contains(state.zombie), "pre-spawn clear did not remove the fixture zombie")
        assert(state.door:isLocked() and state.door:getHealth() > state.health, "safe room lacks its native lock or protection")
        assert(joy:getPrimaryHandItem():getFullType() == "Base.Crowbar", "Joy lacks her crowbar")
        assert(brock:getBodyDamage():getBodyPart(BodyPartType.LowerLeg_L):getFractureTime() > 0, "Brock's native leg is healthy")
        local outside = openRoomSide(group.oddball.site)
        player:teleportTo(outside.x + 0.5, outside.y + 0.5, 0)
        phase("approach")
    elseif state.phase == "approach" then
        local story = state.group.oddball
        if story.stage ~= "awaiting_car" then return end
        assert(not state.door:isLocked() and state.door:getHealth() == state.health, "approach did not release the door")
        if not state.door:IsOpen() then state.door:ToggleDoor(player) end
        phase("find-road")
    elseif state.phase == "find-road" then
        local anchor = state.group.house.primaryEntry or state.group.house.anchor
        local road, reason, search = SC.TaxiService.findRoadsideStop(anchor, state.roadSearch, function(point)
            return SC.GameplayUtil.distance(point, anchor) < 24
        end)
        state.roadSearch = search
        if not road then assert(search, reason); return end
        local square = assert(getCell():getGridSquare(math.floor(road.x), math.floor(road.y), 0))
        state.car = assert(addVehicleDebug("Base.CarNormal", IsoDirections.W, nil, square))
        print("SC_PZO_EVACUATION car=" .. road.x .. "," .. road.y)
        prepare(state.car)
        local trunk = assert(state.car:getPartById("TruckBed"):getItemContainer())
        local cargo = assert(trunk:AddItem("Base.Hammer"))
        cargo:getModData().SC_EvacuationFixture = "donated_cargo"
        state.car:setHotwired(true)
        state.car:tryStartEngine(true)
        phase("idle-car")
    elseif state.phase == "idle-car" then
        local group = state.group
        if not state.car:isEngineRunning() then return end
        local choice = SC.OddballEvacuation.menuOptions(group, player, SC.OddballKit.livingActor(group, 1))[1]
        if not choice then return end
        assert(choice.payload == state.car:getSqlId(), "detected a different car")
        assert(SC.Oddballs.storyAction(group.id, choice.id, player, choice.payload))
        rewards(group.oddball)
        write("evacuation-car.txt", tostring(choice.payload))
        waitOutside(player, group.house, state.car)
        phase("boarding")
    elseif state.phase == "boarding" then
        local brock = SC.OddballKit.livingActor(state.group, 2)
        local story = state.group.oddball
        if not brock or state.car:getSeat(brock) ~= story.vehicle.seat then return end
        assert(SC.Persistence.save(player))
        save(false)
        -- Keep this precise boarding checkpoint through the native disk flush.
        local original = SC.OddballEvacuation.pulse
        SC.OddballEvacuation.pulse = function(group, ...)
            if group == state.group then return true, "fixture_boarding_checkpoint" end
            return original(group, ...)
        end
        phase("boarding-save")
    elseif state.phase == "boarding-save" then
        if now - state.since >= 7000 then finish("PASS", "saved_after_native_passenger_boarding") end
    elseif state.phase == "resume" then
        local group = encounter()
        if not group then return end
        local story = group.oddball
        local id = assert(tonumber(read("evacuation-car.txt")))
        rewards(story)
        assert(story.vehicle.sqlId == id, "cold reload changed the donated car")
        if state.mode == "verify" then
            assert(story.stage == "evacuated" and group.lifecycle == "destroyed", "cold reload restored the departed group")
            assert(not SC.Vehicle.loadedBySqlId(id) and SCSplitScreenProbe.vehicleRetirementStatus(story.vehicle.retirement) == "absent", "donated car survived disk reload")
            finish("PASS", "permanent_car_cargo_and_actor_retirement")
        else
            state.group = group
            phase(state.mode == "retiring" and "retiring" or "departure")
        end
    elseif state.phase == "departure" then
        local story = state.group.oddball
        local value = story.vehicle
        local car = SC.Vehicle.loadedBySqlId(value.sqlId)
        if car then
            state.distance = math.max(state.distance, SC.GameplayUtil.distance(car, value.origin))
            local joy, brock = SC.OddballKit.livingActor(state.group, 1), SC.OddballKit.livingActor(state.group, 2)
            if joy and brock and car:getDriver() == joy and car:getSeat(brock) == value.seat
                and state.distance > 2 then state.bothDriving = true end
        end
        if state.removalCommitted then
            assert(state.bothDriving and state.distance >= 30, "departure lacks actual two-person travel")
            assert(story.stage == "retiring" and not car and value.removed, "deletion checkpoint incomplete")
            finish("PASS", "reloaded_boarded_drove_and_committed_car_removal")
        end
    elseif state.phase == "retiring" then
        local story = state.group.oddball
        if story.stage == "evacuated" then
            local value = story.vehicle
            assert(state.group.lifecycle == "destroyed" and value.removed
                and not SC.Vehicle.loadedBySqlId(value.sqlId), "retirement incomplete")
            rewards(story)
            assert(SC.Persistence.save(player))
            save(false)
            phase("departure-save")
        end
    elseif state.phase == "departure-save" then
        if now - state.since >= 7000 then finish("PASS", "reloaded_and_retired_after_committed_removal") end
    end
    assert(now - state.since < 125000, "timeout in " .. state.phase)
end

Events.OnTick.Add(function()
    if state.done or state.phase == "menu" then return end
    local okay, reason = pcall(step)
    if not okay then finish("FAIL", reason) end
end)
