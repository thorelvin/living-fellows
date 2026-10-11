-- SPDX-License-Identifier: MIT
-- Disposable cloned-save probe for Mara Voss's real window/chair scene.
SCRealSandboxHarnessProbes = SCRealSandboxHarnessProbes or {}
local Probe = {}
SCRealSandboxHarnessProbes.SCOddballSmokerProbe = Probe

local ID = "window_smoker_mara_voss"

local function call(object, method, ...)
    if not object then return nil end
    local okay, value = pcall(function(...)
        return object[method](object, ...)
    end, ...)
    return okay and value or nil
end

local function squareAt(U, post)
    return post and U.gridSquare(post.x, post.y, post.z or 0) or nil
end

local function roomName(square)
    return string.lower(tostring(call(call(square, "getRoom"),
        "getName") or ""))
end

local function actorFor(SC, group)
    local member = group and group.members and group.members[1]
    local record = member and member.actorId and SC.Registry.byId(member.actorId)
    return record and record.actor and SC.GameplayUtil.isValidActor(record.actor)
        and record.actor or nil
end

local function objectAt(SC, post)
    local square = squareAt(SC.GameplayUtil, post)
    local objects = square and call(square, "getObjects")
    local index = post and tonumber(post.objectIndex)
    return objects and index and SC.NativeList.get(objects, index) or nil,
        square
end

local function inventoryHas(SC, actor, kind)
    local U = SC.GameplayUtil
    local inventory = U.inventory(actor)
    for _, item in ipairs(inventory and U.inventoryItemsDeep(inventory,
        180, 10) or {}) do
        if U.itemType(item) == kind then return true end
    end
    return false
end

local function move(player, square)
    return square ~= nil and pcall(function()
        player:teleportTo(square:getX() + 0.5, square:getY() + 0.5,
            square:getZ())
    end)
end

local function observerSquare(SC, site, actor)
    local U = SC.GameplayUtil
    local origin = squareAt(U, site.spawn)
    local room = call(origin, "getRoom")
    local ax, ay, az = U.position(actor)
    if not room or not ax then return nil end
    for radius = 1, 4 do
        for dy = -radius, radius do
            for dx = -radius, radius do
                if math.max(math.abs(dx), math.abs(dy)) == radius then
                    local square = U.gridSquare(math.floor(ax) + dx,
                        math.floor(ay) + dy, math.floor(az or 0))
                    if square and call(square, "getRoom") == room
                        and U.isClearActorSpawnSquare(square) then
                        return square
                    end
                end
            end
        end
    end
    return nil
end

local function outsideSquare(SC, site)
    local U = SC.GameplayUtil
    for radius = 12, 22 do
        for dy = -radius, radius do
            for dx = -radius, radius do
                if math.max(math.abs(dx), math.abs(dy)) == radius then
                    local square = U.gridSquare(site.spawn.x + dx,
                        site.spawn.y + dy, site.spawn.z or 0)
                    if square and call(square, "getRoom") == nil
                        and U.isSafeSpawnSquare(square) then
                        return square
                    end
                end
            end
        end
    end
    return nil
end

local function windowDiagnosis(SC, H, opening)
    local U = SC.GameplayUtil
    local function note(reason)
        H.smokerWindowReasons = H.smokerWindowReasons or {}
        H.smokerWindowReasons[reason] =
            (H.smokerWindowReasons[reason] or 0) + 1
    end
    if (opening.z or 0) ~= 0 then note("other_floor") return end
    local window, holder = objectAt(SC, opening)
    if not window or not U.instanceOf(window, "IsoWindow") then
        note("object_missing") return
    end
    for _, method in ipairs({ "isSmashed", "isBarricaded",
        "isLocked", "isPermaLocked" }) do
        if call(window, method) == true then note(method) return end
    end
    local north = call(window, "getNorth")
    if type(north) ~= "boolean" then note("orientation_missing") return end
    local opposite = U.gridSquare(opening.x - (north and 0 or 1),
        opening.y - (north and 1 or 0), opening.z or 0)
    local function roomAccepted(square)
        local name = roomName(square)
        return name == "livingroom" or name == "bedroom"
            or name == "diningroom"
    end
    local inside, outside
    if roomAccepted(holder) and opposite
        and call(opposite, "getRoom") == nil then
        inside, outside = holder, opposite
    elseif roomAccepted(opposite) and holder
        and call(holder, "getRoom") == nil then
        inside, outside = opposite, holder
    end
    if not inside then note("room_or_exterior") return end
    if not U.isClearActorSpawnSquare(inside) then
        note("inside_tile_blocked") return
    end
    local ix, iy, iz = U.position(inside)
    local ox, oy = U.position(outside)
    local outwardX, outwardY = ox - ix, oy - iy
    local approaches = { { -outwardX, -outwardY },
        { outwardY, -outwardX }, { -outwardY, outwardX } }
    for _, offset in ipairs(approaches) do
        local stand = U.gridSquare(ix + offset[1], iy + offset[2], iz or 0)
        if stand and U.isClearActorSpawnSquare(stand)
            and call(stand, "getRoom") == call(inside, "getRoom") then
            note("eligible")
            return
        end
    end
    note("no_spawn_approach")
end

local function diagnosisSummary(H)
    local rows = {}
    for key, count in pairs(H.smokerWindowReasons or {}) do
        rows[#rows + 1] = tostring(key) .. "=" .. tostring(count)
    end
    table.sort(rows)
    return table.concat(rows, ",")
end

local function findSite(SC, H)
    local U = SC.GameplayUtil
    local x0 = tonumber(H.config.oddball_site_x) or 0
    local y0 = tonumber(H.config.oddball_site_y) or 0
    if x0 <= 0 or y0 <= 0 then
        local x, y = U.position(H.player)
        x0, y0 = math.floor(x or 0), math.floor(y or 0)
    end
    H.smokerVisited = H.smokerVisited or {}
    for _ = 1, 220 do
        local index = H.smokerScanIndex or 0
        if index >= 81 * 81 then return nil, true end
        H.smokerScanIndex = index + 1
        local x = x0 + index % 81 - 40
        local y = y0 + math.floor(index / 81) - 40
        local square = U.gridSquare(x, y, 0)
        local name = roomName(square)
        if square and (name == "livingroom" or name == "bedroom") then
            local building = call(square, "getBuilding")
            if building and not H.smokerVisited[building] then
                H.smokerVisited[building] = true
                H.smokerBuildingsSeen = (H.smokerBuildingsSeen or 0) + 1
                local house, rejected = SC.Factions.oddballHouseAt(square,
                    H.player, true)
                if not house then
                    H.smokerHouseRejected = (H.smokerHouseRejected or 0) + 1
                    H.smokerLastHouseReason = tostring(rejected)
                else
                    H.smokerHousesSeen = (H.smokerHousesSeen or 0) + 1
                    for _, opening in ipairs(house.openings or {}) do
                        if opening.kind == "window" then
                            H.smokerWindowsSeen = (H.smokerWindowsSeen or 0) + 1
                            windowDiagnosis(SC, H, opening)
                            if not H.smokerWindowExample then
                                local holder = squareAt(U, opening)
                                local object = objectAt(SC, opening)
                                local north = call(object, "getNorth")
                                local opposite = north ~= nil and U.gridSquare(
                                    opening.x - (north and 0 or 1),
                                    opening.y - (north and 1 or 0),
                                    opening.z or 0) or nil
                                H.smokerWindowExample = tostring(opening.x)
                                    .. "," .. tostring(opening.y)
                                    .. " holder=" .. roomName(holder)
                                    .. " opposite=" .. roomName(opposite)
                                    .. " north=" .. tostring(north)
                                    .. " object=" .. tostring(object)
                            end
                        end
                    end
                end
                local site = SC.Oddballs._siteForResidentForTests(square,
                    H.player, SC.Oddballs.definition(ID), name, true)
                if site then return site, true end
            end
        end
    end
    return nil, false
end

local function withSpeech(SC, action)
    local U, lines = SC.GameplayUtil, {}
    local original = U.say
    U.say = function(actor, line, ...)
        lines[#lines + 1] = tostring(line)
        return original(actor, line, ...)
    end
    local okay, accepted, reason = pcall(action)
    U.say = original
    return okay and accepted, okay and reason or tostring(accepted), lines
end

local function stop(H, result, setPhase, current, name, detail)
    result("FAIL", name, detail)
    setPhase("finish", current)
end

local function seatStateDetail(SC, H)
    local U, actor, chair = SC.GameplayUtil, H.smokerActor, H.smokerChair
    local x, y, z = U.position(actor)
    local post = H.smokerGroup and H.smokerGroup.oddball
        and H.smokerGroup.oddball.site.chair or {}
    local queue = type(ISTimedActionQueue) == "table"
        and type(ISTimedActionQueue.getTimedActionQueue) == "function"
        and ISTimedActionQueue.getTimedActionQueue(actor) or nil
    local nav = SC.Navigation and SC.Navigation.status(actor) or {}
    local arrived, targets, accessReason = U.directInteractionAccess(actor,
        chair)
    local manager
    pcall(function() manager = SeatingManager.getInstance() end)
    local nativePositions = {}
    if manager and type(Vector3f) == "table"
        and type(Vector3f.new) == "function" then
        for _, direction in ipairs({ "N", "S", "W", "E" }) do
            for _, side in ipairs({ "Front", "Left", "Right" }) do
                local vector = Vector3f.new()
                local okay, valid = pcall(function()
                    return manager:getAdjacentPosition(actor, chair,
                        direction, side, "sitonfurniture",
                        "SitOnFurniture" .. side, vector)
                end)
                if okay and valid == true then
                    nativePositions[#nativePositions + 1] = direction
                        .. side:sub(1, 1) .. "="
                        .. tostring(call(vector, "x")) .. ","
                        .. tostring(call(vector, "y"))
                end
            end
        end
    end
    return "actor=" .. tostring(x) .. "," .. tostring(y) .. ","
        .. tostring(z) .. " chair=" .. tostring(post.x) .. ","
        .. tostring(post.y) .. " queue=" .. tostring(queue and queue.current)
        .. "/" .. tostring(queue and queue.queue and #queue.queue)
        .. " furniture=" .. tostring(SC.NativeActions
            and SC.NativeActions.furnitureStatus(actor))
        .. " seatCount=" .. tostring(call(manager,
            "getTilePositionCount", chair))
        .. " nativePositions=" .. table.concat(nativePositions, ";")
        .. " owner=" .. tostring(call(actor, "getCompanionMovementOwner"))
        .. " access=" .. tostring(arrived) .. "/"
        .. tostring(targets and #targets) .. "/" .. tostring(accessReason)
        .. " nav=" .. tostring(nav.phase) .. "/"
        .. tostring(nav.action) .. "/" .. tostring(nav.reason)
end

function Probe.step(H, current, check, result, setPhase)
    local SC = SurvivorCompanion
    local U = SC.GameplayUtil
    if H.phase == "smoker_prepare" then
        if not check("smoker_definition_ready",
            SC.Oddballs.definition(ID) ~= nil
                and type(SC.Oddballs._siteForResidentForTests) == "function"
                and type(SC.OddballSmoker) == "table",
            "Mara Voss is a registered oddball resident") then
            setPhase("finish", current) return
        end
        require("SCOddballCoreyEarlProbe")
        local fixture = SCRealSandboxHarnessProbes.SCOddballCoreyEarlProbe
        local isolated, reason = fixture.clearExistingOddball(SC, ID)
        if not check("smoker_clone_scene_isolated", isolated,
            tostring(reason)) then
            setPhase("finish", current) return
        end
        pcall(function() H.player:setInvisible(true) end)
        if SC.Scheduler then SC.Scheduler.unregister("decision") end
        local x, y = tonumber(H.config.oddball_site_x) or 0,
            tonumber(H.config.oddball_site_y) or 0
        if x > 0 and y > 0 then
            local moved = pcall(function()
                H.player:teleportTo(x + 0.5, y + 0.5, 0)
            end)
            if not check("smoker_search_area_loaded", moved,
                tostring(x) .. "," .. tostring(y)) then
                setPhase("finish", current) return
            end
        end
        setPhase("smoker_find_site", current)
        return
    end

    if H.phase == "smoker_find_site" then
        if current < (H.smokerRetryAt or 0)
            or current - H.phaseStartedAt < 2000 then return end
        local site, complete = findSite(SC, H)
        if not site then
            if complete and current - H.phaseStartedAt < 50000 then
                H.smokerScanIndex = 0
                H.smokerVisited = {}
                H.smokerRetryAt = current + 2500
                return
            end
            if current - H.phaseStartedAt >= 50000 then
                stop(H, result, setPhase, current,
                    "smoker_real_window_site",
                    "no eligible exterior window in loaded living/bedroom"
                        .. "; buildings=" .. tostring(H.smokerBuildingsSeen or 0)
                        .. " accepted_houses=" .. tostring(H.smokerHousesSeen or 0)
                        .. " windows=" .. tostring(H.smokerWindowsSeen or 0)
                        .. " rejected=" .. tostring(H.smokerHouseRejected or 0)
                        .. " last_reason=" .. tostring(H.smokerLastHouseReason)
                        .. " example=" .. tostring(H.smokerWindowExample)
                        .. " reasons=" .. diagnosisSummary(H))
            end
            return
        end
        H.smokerSite = site
        local window = objectAt(SC, site.window)
        local inside = squareAt(U, site.chair)
        local outside = squareAt(U, site.lookOut)
        if not check("smoker_real_window_site", window ~= nil
                and inside ~= nil and outside ~= nil
                and call(inside, "getRoom") ~= nil
                and call(outside, "getRoom") == nil
                and math.abs(site.chair.x - site.window.x) <= 1
                and math.abs(site.chair.y - site.window.y) <= 1,
            "window=" .. tostring(site.window and site.window.x)
                .. "," .. tostring(site.window and site.window.y)
                .. " chair=" .. tostring(site.chair and site.chair.x)
                .. "," .. tostring(site.chair and site.chair.y)
                .. " lookout=" .. tostring(site.lookOut and site.lookOut.x)
                .. "," .. tostring(site.lookOut and site.lookOut.y)) then
            setPhase("finish", current) return
        end
        if not check("smoker_observer_waits_outside",
            move(H.player, outsideSquare(SC, site)),
            "native scene spawns without observer occupying its room") then
            setPhase("finish", current) return
        end
        local group, reason = SC.Factions.createOddballGroup(site,
            SC.Oddballs.definition(ID), true)
        if not check("smoker_group_created", group ~= nil,
            tostring(reason)) then
            setPhase("finish", current) return
        end
        H.smokerGroup = group
        setPhase("smoker_spawn", current)
        return
    end

    if H.phase == "smoker_spawn" then
        local actor = actorFor(SC, H.smokerGroup)
        if not actor then
            if current - H.phaseStartedAt > 30000 then
                stop(H, result, setPhase, current,
                    "smoker_native_actor_spawned", "actor spawn timed out")
            end
            return
        end
        H.smokerActor = actor
        local site = H.smokerGroup.oddball.site
        local chair = objectAt(SC, site.chair)
        local window = objectAt(SC, site.window)
        local hand = call(actor, "getPrimaryHandItem")
        H.smokerChair = chair
        if not check("smoker_scene_native_objects",
            chair ~= nil and window ~= nil
                and call(window, "IsOpen") == true,
            "chair=" .. tostring(chair)
                .. " window_open=" .. tostring(call(window, "IsOpen")))
            or not check("smoker_cleaver_initially_holstered",
                inventoryHas(SC, actor, "Base.MeatCleaver")
                    and hand == nil,
                "carried=" .. tostring(inventoryHas(SC, actor,
                    "Base.MeatCleaver")) .. " primary=" .. tostring(hand)) then
            setPhase("finish", current) return
        end
        setPhase("smoker_seating", current)
        return
    end

    if H.phase == "smoker_seating" then
        local actor, group = H.smokerActor, H.smokerGroup
        local elapsed = current - H.phaseStartedAt
        H.smokerNextTraceAt = H.smokerNextTraceAt or 5000
        if elapsed >= H.smokerNextTraceAt then
            result("PASS", "smoker_seating_trace_"
                .. tostring(H.smokerNextTraceAt / 1000) .. "s",
                seatStateDetail(SC, H))
            H.smokerNextTraceAt = H.smokerNextTraceAt + 10000
        end
        if current - (H.smokerLastUpdateAt or 0) >= 350 then
            H.smokerLastUpdateAt = current
            local intent = SC.Oddballs.intentFor(actor, H.player,
                { threats = {}, threatCount = 0 }, group)
            H.smokerLastIntent = intent and intent.mode
            if intent then
                local handled, reason = SC.Oddballs.update(actor,
                    H.player, nil, intent, group)
                H.smokerLastUpdate = tostring(handled) .. "/" .. tostring(reason)
            end
        end
        if H.smokerLastUpdate
            and string.find(H.smokerLastUpdate,
                "smoker_smoke_action_failed", 1, true) then
            stop(H, result, setPhase, current,
                "smoker_native_smoke_constructor",
                H.smokerLastUpdate .. " " .. seatStateDetail(SC, H))
            return
        end
        local seated = call(actor, "isSittingOnFurniture") == true
            and call(actor, "getSitOnFurnitureObject") == H.smokerChair
        local value = group.oddball
        if seated and (tonumber(value.smokeCount) or 0) >= 1 then
            if not check("smoker_native_seat_and_cigarette", true,
                "seated=" .. tostring(seated)
                    .. " native_smoke_count=" .. tostring(value.smokeCount)
                    .. " update=" .. tostring(H.smokerLastUpdate)) then
                setPhase("finish", current) return
            end
            local chairFacing
            local manager
            pcall(function() manager = SeatingManager.getInstance() end)
            chairFacing = call(manager, "getFacingDirection", H.smokerChair)
            local post, look = value.site.chair, value.site.lookOut
            local dx, dy = look.x - post.x, look.y - post.y
            local expected = math.abs(dx) >= math.abs(dy)
                and (dx >= 0 and "E" or "W")
                or (dy >= 0 and "S" or "N")
            if not check("smoker_chair_faces_open_window",
                tostring(chairFacing) == expected,
                "facing=" .. tostring(chairFacing)
                    .. " expected=" .. expected) then
                setPhase("finish", current) return
            end
            local square = observerSquare(SC, value.site, actor)
            H.smokerWasGreetedBeforeApproach = value.greeted == true
            if not check("smoker_observer_enters_room",
                move(H.player, square), "observer near Mara") then
                setPhase("finish", current) return
            end
            if H.config.oddball_scene_screenshot == "true" then
                local core = type(getCore) == "function" and getCore() or nil
                if core then
                    call(core, "setAutoZoom", 0, false)
                    for _ = 1, 5 do call(core, "doZoomScroll", 0, -1) end
                end
                setPhase("smoker_zoom", current)
            else
                setPhase("smoker_dialogue", current)
            end
            return
        end
        if current - H.phaseStartedAt > 45000 then
            stop(H, result, setPhase, current,
                "smoker_native_seat_and_cigarette",
                "seated=" .. tostring(seated)
                    .. " smoke_count=" .. tostring(value.smokeCount)
                    .. " intent=" .. tostring(H.smokerLastIntent)
                    .. " update=" .. tostring(H.smokerLastUpdate)
                    .. " " .. seatStateDetail(SC, H))
        end
        return
    end

    if H.phase == "smoker_zoom" then
        if current - H.phaseStartedAt < 2000 then return end
        local core = type(getCore) == "function" and getCore() or nil
        result("PASS", "smoker_closeup_camera_ready",
            "zoom=" .. tostring(call(core, "getZoom", 0)))
        H.encounterSignals.write(
            "SurvivorCompanionHarness/oddball-scene-ready.txt",
            { "ready=true", "kind=smoker" })
        setPhase("smoker_capture", current)
        return
    end

    if H.phase == "smoker_capture" then
        if H.encounterSignals.exists(
            "SurvivorCompanionHarness/oddball-scene-captured.txt") then
            result("PASS", "smoker_live_capture", "Mara seated at open window")
            setPhase("smoker_dialogue", current)
        elseif current - H.phaseStartedAt > 15000 then
            stop(H, result, setPhase, current, "smoker_live_capture",
                "runner did not capture the ready scene")
        end
        return
    end

    if H.phase == "smoker_dialogue" then
        local group = H.smokerGroup
        local greeted, greetingReason, greeting = withSpeech(SC,
            function() return SC.Oddballs.pulseGroup(group,
                H.player, current) end)
        if not check("smoker_philosophical_greeting",
            greeted == true and group.oddball.greeted == true
                and (#greeting >= 1
                    or H.smokerWasGreetedBeforeApproach == false),
            "reason=" .. tostring(greetingReason)
                .. " lines=" .. table.concat(greeting, " | ")
                .. " already_greeted="
                .. tostring(H.smokerWasGreetedBeforeApproach)
                .. " currently_greeted="
                .. tostring(group.oddball.greeted)) then
            setPhase("finish", current) return
        end
        local lines = {}
        local answers = { "ask_view", "ask_past", "ask_belief" }
        local allAccepted = true
        for _, action in ipairs(answers) do
            local accepted, reason, spoken = withSpeech(SC, function()
                return SC.Oddballs.storyAction(group.id, action, H.player)
            end)
            allAccepted = allAccepted and accepted == true and #spoken >= 1
            lines[#lines + 1] = action .. "=" .. tostring(reason)
                .. ":" .. table.concat(spoken, " | ")
        end
        if not check("smoker_three_conversations_open_trust",
            allAccepted and group.oddball.stage == "open"
                and group.standing == "Trusted",
            "stage=" .. tostring(group.oddball.stage)
                .. " standing=" .. tostring(group.standing)
                .. " " .. table.concat(lines, "; ")) then
            setPhase("finish", current) return
        end
        setPhase("smoker_attack", current)
        return
    end

    if H.phase == "smoker_attack" then
        local actor, group = H.smokerActor, H.smokerGroup
        local inventory = U.inventory(H.player)
        local weapon = inventory and call(inventory, "AddItem", "Base.Crowbar")
        local accepted, damage = pcall(function()
            return actor:Hit(weapon, H.player, 0.2, false, 1.0, false)
        end)
        if not check("smoker_native_player_hit_event",
            weapon ~= nil and accepted and type(damage) == "number"
                and damage > 0,
            "weapon=" .. tostring(weapon)
                .. " hit=" .. tostring(damage)) then
            setPhase("finish", current) return
        end
        local primary = call(actor, "getPrimaryHandItem")
        local armed = primary and U.itemType(primary) == "Base.MeatCleaver"
        if not check("smoker_draws_cleaver_when_attacked",
            armed and group.oddball.stage == "hostile"
                and group.standing == "Hostile",
            "primary=" .. tostring(primary and U.itemType(primary))
                .. " stage=" .. tostring(group.oddball.stage)
                .. " standing=" .. tostring(group.standing)
                .. " arm_failure=" .. tostring(group.oddball.armFailure)) then
            setPhase("finish", current) return
        end
        local intent = SC.Oddballs.intentFor(actor, H.player,
            { threats = {}, threatCount = 0 }, group)
        local target = SC.Factions.hostileTargetFor(actor, H.player)
        check("smoker_targets_player_after_hit",
            intent and intent.mode == "hostile"
                and target and target.actor == H.player,
            "intent=" .. tostring(intent and intent.mode)
                .. " target=" .. tostring(target and target.actor))
        setPhase("finish", current)
    end
end

return Probe
