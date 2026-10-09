-- SPDX-License-Identifier: MIT
-- Focused native scene smoke test on a disposable save clone.
local Probe = {}
local READY = "SurvivorCompanionHarness/milli-ready.txt"
local CAPTURED = "SurvivorCompanionHarness/milli-captured.txt"
local TOYS = { Base_ToyBear = true, Base_ToyCar = true,
    Base_ToyPlane = true, Base_Yoyo = true, Base_Doll = true,
    Base_Spiffo = true, Base_FluffyfootBunny = true,
    Base_Plushabug = true, Base_CatToy = true }

local function call(object, method, ...)
    if not object then return nil end
    local ok, value = pcall(function(...)
        return object[method](object, ...)
    end, ...)
    return ok and value or nil
end

local function actorFor(SC, group)
    local member = group and SC.Factions.member(group.id, "member-1")
    local record = member and member.actorId and SC.Registry.byId(member.actorId)
    return record and record.actor or nil
end

local function nearRoom(SC, site)
    local origin = site and site.spawn
    if not origin then return nil end
    local room = call(SC.GameplayUtil.gridSquare(origin.x, origin.y,
        origin.z or 0), "getRoom")
    for radius = 1, 4 do
        for dy = -radius, radius do
            for dx = -radius, radius do
                if math.max(math.abs(dx), math.abs(dy)) == radius then
                    local tile = SC.GameplayUtil.gridSquare(
                        origin.x + dx, origin.y + dy, origin.z or 0)
                    if tile and call(tile, "getRoom") == room
                        and SC.GameplayUtil.isSafeSpawnSquare(tile)
                        and SC.GameplayUtil.isSquareFree(tile) then
                        return tile
                    end
                end
            end
        end
    end
    return nil
end

local function nearbyWaitingPost(SC, site)
    local origin = site and site.spawn
    if not origin then return nil end
    for radius = 13, 19 do
        for dy = -radius, radius do
            for dx = -radius, radius do
                if math.max(math.abs(dx), math.abs(dy)) == radius then
                    local tile = SC.GameplayUtil.gridSquare(
                        origin.x + dx, origin.y + dy, origin.z or 0)
                    if tile and call(tile, "getRoom") == nil
                        and SC.GameplayUtil.isSafeSpawnSquare(tile) then
                        return tile
                    end
                end
            end
        end
    end
    return nil
end

local function findHouse(SC, H)
    local x0 = math.floor(tonumber(H.config.milli_site_x) or 0)
    local y0 = math.floor(tonumber(H.config.milli_site_y) or 0)
    if x0 == 0 or y0 == 0 then
        local x, y = SC.GameplayUtil.position(H.player)
        x0, y0 = math.floor(x or 0), math.floor(y or 0)
    end
    local seen = H.milliBuildings or {}
    H.milliBuildings = seen
    local inspected = 0
    -- One tick scans at most 240 loaded squares and twelve buildings. The
    -- search finishes after a bounded 81x81 neighborhood around the observer.
    for _ = 1, 240 do
        local index = H.milliScanIndex or 0
        if index >= 81 * 81 then return nil, true end
        H.milliScanIndex = index + 1
        local x = x0 + index % 81 - 40
        local y = y0 + math.floor(index / 81) - 40
        local tile = SC.GameplayUtil.gridSquare(x, y, 0)
        local building = tile and call(tile, "getBuilding")
        if building and not seen[building] then
            seen[building] = true
            inspected = inspected + 1
            local house = SC.Factions.oddballHouseAt(tile, H.player, true)
            local site = house and SC.OddballMilli.siteFor(house,
                H.player, true)
            if site and site.room == "kidsbedroom" then
                return site, true
            end
            if inspected >= 12 then break end
        end
    end
    return nil, false
end

local function countSceneToys(SC, site)
    local found = {}
    for _, point in ipairs(site.toySpawns or {}) do
        local tile = SC.GameplayUtil.gridSquare(point.x, point.y,
            point.z or 0)
        local list = call(tile, "getWorldObjects")
        local size = list and SC.NativeList.size(list) or 0
        for index = 0, math.min(size, 64) - 1 do
            local object = SC.NativeList.get(list, index)
            local item = call(object, "getItem")
            local kind = SC.GameplayUtil.itemType(item)
            local key = kind and string.gsub(kind, "[%p]", "_")
            if key and TOYS[key] then found[object] = true end
        end
    end
    local count = 0
    for _ in pairs(found) do count = count + 1 end
    return count
end

local function restoreSpeech(H)
    if H.milliOriginalSay then
        SurvivorCompanion.GameplayUtil.say = H.milliOriginalSay
    end
    H.milliOriginalSay = nil
end

local function fail(H, result, setPhase, current, name, detail)
    restoreSpeech(H)
    result("FAIL", name, detail)
    setPhase("finish", current)
end

function Probe.step(H, current, check, result, setPhase)
    local SC = SurvivorCompanion
    if H.phase == "milli_prepare" then
        if current - H.phaseStartedAt < 1500 then return end
        local definition = SC.Oddballs and SC.Oddballs.definition
            and SC.Oddballs.definition("milli_tea_and_trouble")
        if not check("milli_definition_ready", definition ~= nil
            and SC.OddballMilli and type(SC.OddballMilli.siteFor)
                == "function", "native resident encounter registered") then
            setPhase("finish", current) return
        end
        H.milliDefinition = definition
        pcall(function() getGameTime():setTimeOfDay(12.0) end)
        if SC.Scheduler then SC.Scheduler.unregister("decision") end
        pcall(function() if SC.UI then SC.UI.close() end end)
        pcall(function() getPlayerInventory(0):setVisible(false) end)
        pcall(function() getPlayerLoot(0):setVisible(false) end)
        pcall(function()
            getCore():setAutoZoom(0, false)
            for _ = 1, 3 do getCore():doZoomScroll(0, -1) end
        end)
        local x = tonumber(H.config.milli_site_x) or 0
        local y = tonumber(H.config.milli_site_y) or 0
        if x > 0 and y > 0 then
            local moved = pcall(function()
                H.player:teleportTo(x + 0.5, y + 0.5, 0)
            end)
            if not check("milli_search_area_loaded", moved,
                "observer at " .. tostring(x) .. "," .. tostring(y)) then
                setPhase("finish", current) return
            end
        end
        pcall(function() H.player:setInvisible(true) end)
        setPhase("milli_find_room", current)
        return
    end

    if H.phase == "milli_find_room" then
        if current - H.phaseStartedAt < 2500 then return end
        local site, finished = findHouse(SC, H)
        if not site then
            if finished or current - H.phaseStartedAt > 35000 then
                fail(H, result, setPhase, current, "milli_real_kids_room",
                    "no eligible loaded big house with furnished kidsbedroom "
                    .. "within 40 tiles; scanned="
                    .. tostring(H.milliScanIndex or 0))
            end
            return
        end
        H.milliSite = site
        local waiting = nearbyWaitingPost(SC, site)
        if not check("milli_observer_can_wait_outside",
            waiting ~= nil, "kid room remains undisturbed for native pose") then
            setPhase("finish", current) return
        end
        local away = pcall(function()
            H.player:teleportTo(waiting:getX() + 0.5,
                waiting:getY() + 0.5, waiting:getZ())
        end)
        if not check("milli_observer_waiting_outside", away,
            "native resident spawns unseen") then
            setPhase("finish", current) return
        end
        local group, reason = SC.Factions.createOddballGroup(site,
            H.milliDefinition, true)
        if not check("milli_native_group_created", group ~= nil,
            tostring(reason)) then
            setPhase("finish", current) return
        end
        H.milliGroup = group
        setPhase("milli_native_spawn", current)
        return
    end

    if H.phase == "milli_native_spawn" then
        local group = H.milliGroup
        local actor = actorFor(SC, group)
        if not actor or group.oddball.toysPlaced ~= true
            or group.oddball.petsSpawned ~= true then
            if current - H.phaseStartedAt > 30000 then
                fail(H, result, setPhase, current, "milli_native_spawn",
                    "actor/toys/pets did not finish; actor="
                    .. tostring(actor ~= nil) .. " toys="
                    .. tostring(group.oddball.toysPlaced) .. " pets="
                    .. tostring(group.oddball.petsSpawned))
            end
            return
        end
        H.milliActor = actor
        local site = H.milliSite
        local square = call(actor, "getSquare")
        local expectedRoom = call(SC.GameplayUtil.gridSquare(site.spawn.x,
            site.spawn.y, site.spawn.z or 0), "getRoom")
        local actualRoom = call(square, "getRoom")
        local weapon = call(actor, "getPrimaryHandItem")
        local kind = SC.GameplayUtil.itemType(weapon)
        if not check("milli_real_kids_room",
            actualRoom ~= nil and actualRoom == expectedRoom
                and site.room == "kidsbedroom",
            "room=" .. tostring(call(actualRoom, "getName"))
                .. " site=" .. tostring(site.room)) then
            setPhase("finish", current) return
        end
        if not check("milli_native_kit_and_skills",
            (kind == "Base.HobbyHorse" or kind == "Base.SmashedBottle")
                and group.oddball.weapon == kind
                and group.oddball.skillsSeeded == true,
            "weapon=" .. tostring(kind) .. " skills="
                .. tostring(group.oddball.skillsSeeded)) then
            setPhase("finish", current) return
        end
        local first = SC.OddballAnimals.status(group, 1, H.player)
        local second = SC.OddballAnimals.status(group, 2, H.player)
        local dumpling = SC.OddballAnimals.find(group, 1)
        local bandit = SC.OddballAnimals.find(group, 2)
        if not check("milli_two_named_native_babies",
            first == "alive" and second == "alive"
                and call(dumpling, "getCustomName") == "Dumpling"
                and call(bandit, "getCustomName") == "Bandit"
                and tonumber(call(dumpling, "getAnimalID")) ~= nil
                and tonumber(call(bandit, "getAnimalID")) ~= nil,
            "rabbit=" .. tostring(first) .. "/"
                .. tostring(call(dumpling, "getCustomName"))
                .. " raccoon=" .. tostring(second) .. "/"
                .. tostring(call(bandit, "getCustomName"))) then
            setPhase("finish", current) return
        end
        local toys = countSceneToys(SC, site)
        if not check("milli_real_floor_toys",
            toys >= 5 and toys <= 8,
            "actual=" .. tostring(toys) .. " intended="
                .. tostring(group.oddball.toysCount)) then
            setPhase("finish", current) return
        end
        SC.OddballMilli.update(actor, H.player, nil,
            { mode = "milli_floor" }, group)
        setPhase("milli_floor_pose", current)
        return
    end

    if H.phase == "milli_floor_pose" then
        local actor, group = H.milliActor, H.milliGroup
        local sitting = call(actor, "isSitOnGround")
        if sitting ~= true and current - H.phaseStartedAt < 10000 then
            SC.OddballMilli.update(actor, H.player, nil,
                { mode = "milli_floor" }, group)
            return
        end
        if not check("milli_native_floor_sit", sitting == true,
            "EventSitOnGround reached native posture") then
            setPhase("finish", current) return
        end
        H.milliSpeech = {}
        H.milliOriginalSay = SC.GameplayUtil.say
        SC.GameplayUtil.say = function(speaker, line, ...)
            if speaker == actor then
                H.milliSpeech[#H.milliSpeech + 1] = tostring(line)
            end
            return H.milliOriginalSay(speaker, line, ...)
        end
        local post = nearRoom(SC, H.milliSite)
        local entered = post and pcall(function()
            H.player:teleportTo(post:getX() + 0.5,
                post:getY() + 0.5, post:getZ())
        end) or false
        if not check("milli_observer_enters_room", entered,
            "player approaches her and two babies") then
            restoreSpeech(H)
            setPhase("finish", current) return
        end
        setPhase("milli_startle", current)
        return
    end

    if H.phase == "milli_startle" then
        SC.Oddballs.pulseGroup(H.milliGroup, H.player, current)
        local stage = H.milliGroup.oddball
        local startled, invited = false, false
        for _, line in ipairs(H.milliSpeech or {}) do
            if line:find("Lord have mercy", 1, true) then startled = true end
            if line:find("You'll have tea", 1, true) then invited = true end
        end
        if (not startled or not invited) and current - H.phaseStartedAt < 9000 then
            return
        end
        restoreSpeech(H)
        if not check("milli_startle_then_tea_invite",
            stage.startled == true and startled and invited,
            "stage=" .. tostring(stage.stage) .. " lines="
                .. table.concat(H.milliSpeech or {}, " | ")) then
            setPhase("finish", current) return
        end
        local option = SC.OddballMilli.menuOptions(H.milliGroup, H.player)
        local tea = false
        for _, row in ipairs(option or {}) do
            if row.id == "have_tea" and row.enabled == true then
                tea = true
            end
        end
        if not check("milli_tea_action_available", tea,
            "native close-range menu is actionable") then
            setPhase("finish", current) return
        end
        if H.config.milli_screenshot ~= "true" then
            setPhase("finish", current) return
        end
        local signaled = H.milliSignals.write(READY, {
            "ready=true", "room=kidsbedroom",
            "petIds=" .. tostring(H.milliGroup.oddball.animals.slots[1].id)
                .. "," .. tostring(H.milliGroup.oddball.animals.slots[2].id),
        })
        if not check("milli_capture_ready", signaled,
            "native encounter ready for screenshot") then
            setPhase("finish", current) return
        end
        setPhase("milli_capture", current)
        return
    end

    if H.phase == "milli_capture" then
        if H.milliSignals.exists(CAPTURED) then
            result("PASS", "milli_live_capture",
                "native bedroom encounter captured")
            setPhase("finish", current)
        elseif current - H.phaseStartedAt > 15000 then
            fail(H, result, setPhase, current, "milli_live_capture",
                "runner did not capture the ready frame")
        end
    end
end

SCRealSandboxHarnessProbes = SCRealSandboxHarnessProbes or {}
SCRealSandboxHarnessProbes.SCMilliLiveProbe = Probe

return Probe
