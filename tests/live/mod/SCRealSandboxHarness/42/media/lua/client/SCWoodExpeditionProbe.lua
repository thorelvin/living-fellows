-- SPDX-License-Identifier: MIT
-- Disposable-save, ordinary public wood expedition. Existing companions,
-- forests, car and storage remain real production inputs. An explicit clone-only
-- equipment flag may stock one real axe and an empty worn bag when required.
-- A separate quiet-site flag clears nearby zombies only during site work.
local Probe = {}
local function call(object, method, ...)
    if not object then return nil end
    local indexed, fn = pcall(function() return object[method] end)
    if not indexed or type(fn) ~= "function" then return nil end
    local okay, value = pcall(fn, object, ...)
    if okay then return value end
end
local function count(rows)
    local value = 0
    for _ in pairs(type(rows) == "table" and rows or {}) do value = value + 1 end
    return value
end
local function position(actor)
    return tostring(call(actor, "getX")) .. "," .. tostring(call(actor, "getY")) .. "," .. tostring(call(actor, "getZ"))
end
local function healthy(actor)
    local body = call(actor, "getBodyDamage")
    return actor and call(actor, "isDead") == false and call(actor, "isBridgeHealthy") == true
        and (tonumber(call(body, "getOverallBodyHealth")) or 0) >= 95
        and call(body, "getNumPartsBleeding") == 0
end
local function key(point) return point.x .. ":" .. point.y .. ":" .. point.z end
local function screenshot(H, fixture, label)
    local name = tostring(H.config.run_id) .. "-wood-" .. fixture.mode .. "-" .. label .. ".png"
    local okay = pcall(function() getCore():TakeFullScreenshot(name) end)
    return okay, name .. "; queued; inspect resulting PNG"
end
local function point(object)
    local x, y, z = tonumber(call(object, "getX")), tonumber(call(object, "getY")), tonumber(call(object, "getZ"))
    if not x or not y or not z then return nil end
    local square = call(object, "getCurrentSquare") or call(object, "getSquare")
    local floor = tonumber(call(square, "getZ")) or math.floor(z)
    return { x = x, y = y, z = z, floor = floor, direction = tostring(call(object, "getDir")) }
end
local function samePoint(first, second)
    return first and second and first.floor == second.floor and math.abs(first.z - second.z) <= 0.05
        and first.direction == second.direction
        and math.abs(first.x - second.x) <= 0.05 and math.abs(first.y - second.y) <= 0.05
end
local function observeWitnessMovement(fixture)
    local baseline = fixture.visibility
    if not baseline then return end
    if not samePoint(baseline.primary, point(fixture.primary)) then baseline.primaryMoved = true end
    for _, row in ipairs(baseline.cars) do
        if not samePoint(row.before.point, point(row.vehicle)) or call(row.vehicle, "isEngineRunning") ~= false
            or math.abs(tonumber(call(row.vehicle, "getCurrentSpeedKmHour")) or 0) > 0.1 then row.moved = true end
    end
end
local function nativeSample(at)
    if not at or SCSplitScreenProbe == nil or type(SCSplitScreenProbe.debugPrimaryCutawaySample) ~= "function" then
        return "native_sample_unavailable"
    end
    local okay, detail = pcall(SCSplitScreenProbe.debugPrimaryCutawaySample,
        math.floor(at.x), math.floor(at.y), at.floor)
    return okay and tostring(detail) or "native_sample_failed:" .. tostring(detail)
end
local function squareFacts(square)
    return "square=" .. tostring(square) .. ";floor=" .. tostring(call(square, "getZ"))
        .. ";canSee0=" .. tostring(call(square, "getCanSee", 0))
        .. ";couldSee0=" .. tostring(call(square, "isCouldSee", 0))
        .. ";seen0=" .. tostring(call(square, "isSeen", 0))
end
local function visibilityFacts(object, vehicle)
    local at = point(object)
    local square = call(object, "getCurrentSquare") or call(object, "getSquare")
    local cell = type(getCell) == "function" and getCell() or nil
    local canonical = at and call(cell, "getGridSquare", math.floor(at.x), math.floor(at.y), at.floor)
    local alpha, target = tonumber(call(object, "getAlpha", 0)), tonumber(call(object, "getTargetAlpha", 0))
    local intersected
    if vehicle then intersected = call(object, "couldSeeIntersectedSquare", 0) end
    local visibleSquare = square ~= nil and canonical == square and call(square, "getCanSee", 0) == true
    if vehicle then visibleSquare = square ~= nil and call(square, "isSeen", 0) == true and intersected ~= false end
    return { point = at, square = square, canonical = canonical, alpha = alpha, target = target,
        visible = visibleSquare and alpha ~= nil and alpha > 0.05 and target ~= nil and target > 0.05
            and (vehicle or call(object, "getDoRender") ~= false),
        detail = "position=" .. position(object) .. ";dir=" .. tostring(at and at.direction)
            .. ";floor=" .. tostring(at and at.floor)
            .. ";alpha0=" .. tostring(alpha) .. ";targetAlpha0=" .. tostring(target)
            .. ";couldSeeIntersectedSquare0=" .. tostring(intersected)
            .. ";doRender=" .. tostring(call(object, "getDoRender"))
            .. ";current{" .. squareFacts(square) .. "};canonicalSame=" .. tostring(canonical ~= nil and square == canonical)
            .. ";canonical{" .. squareFacts(canonical) .. "};native{" .. nativeSample(at) .. "}" }
end
local function readableName(SC, member)
    if SC.Names and type(SC.Names.displayName) == "function" then
        local okay, name = pcall(SC.Names.displayName, member.actor)
        if okay and type(name) == "string" and name ~= "" then return name end
    end
    return tostring(call(member.actor, "getDisplayName") or member.id)
end
local function visibilityLine(label, detail)
    local line = "visibility:" .. label .. "|" .. detail
    print("SC_REAL_SANDBOX|WOOD_EXPEDITION|" .. line)
    local writer = type(getFileWriter) == "function"
        and getFileWriter("SurvivorCompanionHarness/wood-expedition.log", true, true)
    if writer then writer:writeln(line); writer:close() end
end
local function selectCrew(SC, size)
    local leader, others = nil, {}
    for _, record in ipairs(SC.Registry.records()) do
        local actor = record.actor
        local command = actor and SC.Commands.peek(actor)
        local name = actor and SC.GameplayUtil.nameOf(actor)
        if command and command.recruited and healthy(actor)
            and (size == 1 or SC.BaseLife.isInside(actor)) then
            local member = { id = record.id, actor = actor }
            if not leader and type(name) == "string" and string.find(string.lower(name), "scarlet", 1, true) then
                leader = member
            else others[#others + 1] = member end
        end
    end
    if not leader then return {} end
    table.sort(others, function(a, b) return a.id < b.id end)
    local crew = { leader }
    for index = 1, math.min(size - 1, #others) do crew[#crew + 1] = others[index] end
    return crew
end
local function snapshotVisibility(SC, fixture, primary)
    fixture.primary = primary
    fixture.visibility = { primary = point(primary), actors = {}, cars = {}, frames = 0 }
    local baseline, selected = fixture.visibility, {}
    for _, member in ipairs(fixture.crew) do
        baseline.actors[#baseline.actors + 1] = { id = member.id, actor = member.actor, group = "crew" }
        selected[member.id] = true
    end
    local home = {}
    for _, record in ipairs(SC.Registry.records()) do
        local command = record.actor and SC.Commands.peek(record.actor)
        if not selected[record.id] and command and command.recruited and SC.BaseLife.isInside(record.actor) then
            home[#home + 1] = { id = record.id, actor = record.actor, group = "home" }
        end
    end
    table.sort(home, function(a, b) return a.id < b.id end)
    for index = 1, math.min(8, #home) do baseline.actors[#baseline.actors + 1] = home[index] end
    -- Build42 exposes a Set here. Reuse the production adapter that converts
    -- that native collection to a bounded Lua array instead of indexing it.
    local vehicles, candidates = {}, {}
    if SC.Vehicle and type(SC.Vehicle.loadedVehicles) == "function" then
        local okay, loaded = pcall(SC.Vehicle.loadedVehicles)
        if okay and type(loaded) == "table" then vehicles = loaded end
    end
    local size = #vehicles
    -- Native loaded-vehicle inventory only; cap both inspected objects and retained witnesses.
    for index = 0, math.min(256, size) - 1 do
        local vehicle = vehicles[index + 1]
        local at = point(vehicle)
        local speed = tonumber(call(vehicle, "getCurrentSpeedKmHour"))
        local engine, removed = call(vehicle, "isEngineRunning"), call(vehicle, "isRemovedFromWorld")
        local reason, distance = "admitted", nil
        if not at then reason = "position_unavailable"
        elseif not baseline.primary then reason = "primary_position_unavailable"
        elseif at.floor ~= baseline.primary.floor then reason = "different_square_floor"
        elseif not speed then reason = "speed_unavailable"
        elseif math.abs(speed) > 0.1 then reason = "moving"
        elseif engine ~= false then reason = "engine_running_or_unavailable"
        elseif removed == true then reason = "removed"
        else
            distance = (at.x - baseline.primary.x)^2 + (at.y - baseline.primary.y)^2
            if distance > 60 * 60 then reason = "beyond60tiles" end
        end
        visibilityLine("vehicle-inventory", "index=" .. index .. "|sqlId=" .. tostring(call(vehicle, "getSqlId"))
            .. "|position=" .. position(vehicle) .. "|squareFloor=" .. tostring(at and at.floor)
            .. "|primaryFloor=" .. tostring(baseline.primary and baseline.primary.floor)
            .. "|speed=" .. tostring(speed) .. "|engine=" .. tostring(engine) .. "|reason=" .. reason
            .. "|alpha0=" .. tostring(call(vehicle, "getAlpha", 0))
            .. "|targetAlpha0=" .. tostring(call(vehicle, "getTargetAlpha", 0))
            .. "|" .. squareFacts(call(vehicle, "getCurrentSquare") or call(vehicle, "getSquare")))
        if reason == "admitted" then
            candidates[#candidates + 1] = { vehicle = vehicle, id = call(vehicle, "getSqlId"), distance = distance }
        end
    end
    table.sort(candidates, function(a, b)
        if a.distance ~= b.distance then return a.distance < b.distance end
        return tostring(a.id) < tostring(b.id)
    end)
    for index = 1, math.min(8, #candidates) do
        local row = candidates[index]
        row.before = visibilityFacts(row.vehicle, true)
        baseline.cars[#baseline.cars + 1] = row
    end
    baseline.vehicleInventorySize, baseline.vehicleInspected = size, math.min(256, size)
end
local function captureVisibility(SC, fixture, label)
    local baseline = fixture.visibility
    if not baseline then return end
    local restore = SC.ViewSession and type(SC.ViewSession.primaryRestoreDiagnostic) == "function"
        and SC.ViewSession.primaryRestoreDiagnostic() or {}
    local native = SCSplitScreenProbe and type(SCSplitScreenProbe.releaseDiagnostics) == "function"
        and select(2, pcall(SCSplitScreenProbe.releaseDiagnostics)) or "unavailable"
    visibilityLine(label, "kind=primary|frames=" .. baseline.frames .. "|owner="
        .. tostring(SC.ViewSession and SC.ViewSession.owner()) .. "|restore=" .. tostring(restore.status)
        .. ";pending=" .. tostring(restore.pending) .. ";reason=" .. tostring(restore.reason)
        .. "|nativeRelease=" .. tostring(native) .. "|" .. visibilityFacts(fixture.primary).detail)
    for _, member in ipairs(baseline.actors) do
        visibilityLine(label, "kind=actor|group=" .. member.group .. "|id=" .. member.id
            .. "|name=" .. readableName(SC, member) .. "|vehicle=" .. tostring(call(member.actor, "getVehicle"))
            .. "|" .. visibilityFacts(member.actor).detail)
    end
    for _, row in ipairs(baseline.cars) do
        visibilityLine(label, "kind=car|sqlId=" .. tostring(row.id) .. "|initialVisible=" .. tostring(row.before.visible)
            .. "|unmoved=" .. tostring(not row.moved and samePoint(row.before.point, point(row.vehicle)))
            .. "|primaryFixed=" .. tostring(not baseline.primaryMoved and samePoint(baseline.primary, point(fixture.primary)))
            .. "|" .. visibilityFacts(row.vehicle, true).detail)
    end
end
local function compareVisibleCars(fixture, result)
    local baseline, compared = fixture.visibility, 0
    for _, row in ipairs(baseline.cars) do
        local reason
        if not row.before.visible then reason = "not initially primary-visible"
        elseif baseline.primaryMoved or not samePoint(baseline.primary, point(fixture.primary)) then reason = "primary pose changed"
        elseif row.moved or not samePoint(row.before.point, point(row.vehicle)) then reason = "car moved"
        elseif call(row.vehicle, "isEngineRunning") ~= false then reason = "car engine state changed" end
        local name = "wood_probe_primary_car_visible_" .. tostring(row.id)
        if reason then result("SKIP", name, reason .. "; no forced visibility or repositioning")
        else
            compared = compared + 1
            local facts = visibilityFacts(row.vehicle, true)
            result(facts.visible and "PASS" or "FAIL", name,
                "initially primary-visible stationary car; unchanged primary pose and car; " .. facts.detail)
        end
    end
    if compared == 0 then result("SKIP", "wood_probe_primary_car_visibility_comparison",
        "no unchanged initially primary-visible car witness; inspect bounded before/after facts and PNGs") end
    return compared
end
local function visibilityNow(current)
    if type(getTimestampMs) == "function" then
        local okay, value = pcall(getTimestampMs)
        if okay and tonumber(value) then return tonumber(value) end
    end
    local utility = SurvivorCompanion and SurvivorCompanion.GameplayUtil
    if utility and type(utility.nowMs) == "function" then
        local okay, value = pcall(utility.nowMs)
        if okay and tonumber(value) then return tonumber(value) end
    end
    return tonumber(current)
end
local function observeSoloVisibility(H, fixture, result, current)
    local SC, baseline = SurvivorCompanion, fixture.visibility
    if not baseline or baseline.done or not fixture.dispatchedAt or SC.ExpeditionPrototype.current() ~= nil then return end
    local restore = SC.ViewSession and type(SC.ViewSession.primaryRestoreDiagnostic) == "function"
        and SC.ViewSession.primaryRestoreDiagnostic() or nil
    if getSpecificPlayer(1) ~= nil or SC.ViewSession.owner() ~= nil
        or (restore and (restore.pending or restore.status ~= "applied")) then
        baseline.frames, baseline.soloStartedAt = 0, nil
        return
    end
    if type(getPlayerScreenWidth) == "function" and getPlayerScreenWidth(0) ~= getCore():getScreenWidth() then
        baseline.frames, baseline.soloStartedAt = 0, nil
        return
    end
    local now = visibilityNow(current)
    if baseline.soloStartedAt == nil then baseline.soloStartedAt = now end
    baseline.frames = baseline.frames + 1
    if baseline.frames == 2 or baseline.frames == 12 then
        local label = "postsolo-frame" .. baseline.frames
        captureVisibility(SC, fixture, label)
        local okay, detail = screenshot(H, fixture, label)
        result(okay and "PASS" or "FAIL", "wood_probe_visibility_" .. label .. "_png", detail)
    end
    -- Native restoration queues asynchronous lighting work. Twelve frames at
    -- high refresh can elapse before that thread has consumed the request.
    if baseline.frames >= 12 and now and baseline.soloStartedAt and now - baseline.soloStartedAt >= 1500 then
        captureVisibility(SC, fixture, "postsolo-settled")
        local okay, detail = screenshot(H, fixture, "postsolo-settled")
        result(okay and "PASS" or "FAIL", "wood_probe_visibility_postsolo-settled_png",
            detail .. ";normalSoloMs=" .. (now - baseline.soloStartedAt) .. ";frames=" .. baseline.frames)
        compareVisibleCars(fixture, result)
        baseline.done = true
    end
end
local KITCHEN = { x = 12035.5, y = 6746.5, z = 0 }
local function kitchenRequested(H)
    return tonumber(H.config.wood_expedition_crew_size) == 3
end
local function kitchenPose(primary, kitchen)
    local at = point(primary)
    local room = call(call(primary, "getCurrentSquare"), "getRoom")
    return at and at.floor == 0 and math.abs(at.x - KITCHEN.x) <= 0.6
        and math.abs(at.y - KITCHEN.y) <= 0.6 and room ~= nil and room == kitchen.room
end
local function cleanupKitchen(fixture, failed)
    local kitchen = fixture.kitchen
    if not kitchen then return end
    kitchen.active = false
    local action = kitchen.action
    if not failed or not action or kitchen.pathComplete then return end
    -- Stop/remove this exact probe-owned action only; never clear the player's queue.
    if action.action ~= nil then call(action, "forceStop") end
    if kitchen.queue then call(kitchen.queue, "removeFromQueue", action) end
    kitchen.action = nil
end
local function captureKitchen(H, fixture, label, result)
    local kitchen = fixture.kitchen
    if not kitchen or not kitchen.wall then return end
    local wall, now = kitchen.wall, visibilityNow(fixture.latestStepAt) or 0
    local flags = call(wall.square, "getPlayerCutawayFlag", 0, now)
    local room = call(call(fixture.primary, "getCurrentSquare"), "getRoom")
    local detail = "kind=kitchen|frames=" .. tostring(kitchen.frames) .. "|wall="
        .. wall.x .. "," .. wall.y .. ",0|wallRoom=" .. tostring(wall.roomName)
        .. "|primaryRoom=" .. tostring(call(room, "getName")) .. ";identity=" .. tostring(room)
        .. "|flags=" .. tostring(flags) .. "|southHidden="
        .. tostring(type(flags) == "number" and math.floor(flags) % 2 == 1)
        .. "|wallVisibility{" .. squareFacts(wall.square) .. "}|native{"
        .. nativeSample({ x = wall.x, y = wall.y, z = 0, floor = 0 }) .. "}|adjacentKitchen{"
        .. nativeSample({ x = wall.x, y = wall.y - 1, z = 0, floor = 0 }) .. "}|primary{"
        .. visibilityFacts(fixture.primary).detail .. "}"
    visibilityLine(label, detail)
    local okay, png = screenshot(H, fixture, label)
    result(okay and "PASS" or "FAIL", "wood_probe_" .. label .. "_png", png)
    return flags
end
local function startKitchenRoute(H, fixture, current, result)
    local SC, probes = SurvivorCompanion, SCRealSandboxHarnessProbes
    local wallProbe = probes and probes.SCViewCutawayProbe
    if not wallProbe then
        pcall(require, "SCViewCutawayProbe")
        wallProbe = SCRealSandboxHarnessProbes and SCRealSandboxHarnessProbes.SCViewCutawayProbe
    end
    local wallTests = wallProbe and wallProbe._tests
    if not wallTests or type(wallTests.wallAt) ~= "function" then return false, "kitchen wall fixture helper unavailable" end
    local utility = SC.GameplayUtil
    local square = utility.gridSquare(math.floor(KITCHEN.x), math.floor(KITCHEN.y), 0)
    local room = call(square, "getRoom")
    local roomName = call(room, "getName")
    if type(roomName) ~= "string" or not string.find(string.lower(roomName), "kitchen", 1, true)
        or call(square, "TreatAsSolidFloor") ~= true or call(square, "hasFloor") ~= true then
        return false, "fixed kitchen point is unloaded or is not an actual kitchen: " .. tostring(roomName)
    end
    local candidates = {}
    for x = math.floor(KITCHEN.x) - 4, math.floor(KITCHEN.x) + 4 do
        for y = math.floor(KITCHEN.y) - 4, math.floor(KITCHEN.y) + 4 do
            local wall = wallTests.wallAt(utility, x, y, 1)
            local inside = wall and utility.gridSquare(x, y - 1, 0)
            if wall and string.find(string.lower(wall.roomName), "kitchen", 1, true)
                and call(inside, "getRoom") == room then candidates[#candidates + 1] = wall end
        end
    end
    local wall = wallTests.chooseWall(candidates, 1, true)
    if not wall then return false, "no verified south wall for the actual kitchen within81 anchors" end
    if ISPathFindAction == nil then pcall(require, "Vehicles/TimedActions/ISPathFindAction") end
    if ISPathFindAction == nil or type(ISPathFindAction.pathToLocationF) ~= "function"
        or ISTimedActionQueue == nil or type(ISTimedActionQueue.add) ~= "function" then
        return false, "ordinary player path action unavailable"
    end
    local okay, action = pcall(ISPathFindAction.pathToLocationF, ISPathFindAction,
        H.player, KITCHEN.x, KITCHEN.y, KITCHEN.z)
    if not okay or not action or type(action.setOnComplete) ~= "function" or type(action.setOnFail) ~= "function" then
        return false, "ordinary player path action construction failed: " .. tostring(action)
    end
    local kitchen = { active = true, action = action, room = room, wall = wall,
        frames = 0, startedAt = current, stage = "walking" }
    fixture.kitchen = kitchen
    if type(ISTimedActionQueue.getTimedActionQueue) == "function" then
        kitchen.queue = ISTimedActionQueue.getTimedActionQueue(H.player)
    end
    action:setOnComplete(function() if kitchen.active then kitchen.pathComplete = true end end)
    action:setOnFail(function() if kitchen.active then kitchen.pathFailed = true end end)
    captureKitchen(H, fixture, "kitchen-before-walk", result)
    local queued, failure = pcall(ISTimedActionQueue.add, action)
    if not queued then cleanupKitchen(fixture, true) return false, "player path queue rejected: " .. tostring(failure) end
    result("PASS", "wood_probe_kitchen_walk_queued", "ordinary native ISPathFindAction; target=12035.5,6746.5,0"
        .. ";actualRoom=" .. roomName .. ";southWall=" .. wall.x .. "," .. wall.y
        .. ";bounded81-anchor discovery; no teleport or wall/cache changes")
    return true
end
local function observeKitchen(H, fixture, result)
    local kitchen = fixture.kitchen
    if not kitchen or not kitchen.active or kitchen.stage ~= "observing" or kitchen.done then return end
    if not kitchenPose(fixture.primary, kitchen) then kitchen.poseLost = true return end
    local now = visibilityNow(fixture.latestStepAt)
    if not now then return end
    kitchen.frames = kitchen.frames + 1
    if kitchen.frames == 2 or kitchen.frames == 12 or kitchen.frames == 120 then
        captureKitchen(H, fixture, "kitchen-frame" .. kitchen.frames, result)
    end
    if kitchen.frames >= 120 and now - kitchen.arrivedAt >= 1500 then
        local flags = captureKitchen(H, fixture, "kitchen-settled", result)
        local hidden = type(flags) == "number" and math.floor(flags) % 2 == 1
        result(hidden and "PASS" or "FAIL", "wood_probe_kitchen_south_cutaway",
            "actual kitchen after natural expedition return and normal player walk;flags=" .. tostring(flags)
                .. ";frames=" .. kitchen.frames .. ";normalRoomMs=" .. (now - kitchen.arrivedAt))
        result("SKIP", "wood_probe_kitchen_pixels_require_review",
            "inspect kitchen-before-walk/frame2/frame12/frame120/settled PNGs; native flags alone do not prove rendered wall pixels")
        captureVisibility(SurvivorCompanion, fixture, "kitchen-settled-crew")
        kitchen.done = true
    end
end
local function tracePoint(at)
    if type(at) ~= "table" then return "nil" end
    return tostring(at.x) .. "," .. tostring(at.y) .. "," .. tostring(at.z)
end
local function traceNavigation(SC, actor, current)
    local nav, route, owner = {}, {}, {}
    if SC.Navigation and type(SC.Navigation.status) == "function" then
        local okay, value = pcall(SC.Navigation.status, actor)
        if okay and type(value) == "table" then nav = value end
    end
    if SC.Navigation and type(SC.Navigation.peek) == "function" then
        local okay, value = pcall(SC.Navigation.peek, actor)
        if okay and type(value) == "table" then route = value end
    end
    -- current()/snapshot() reconcile action deadlines. Read history instead so
    -- diagnostic sampling cannot advance or release an actor's action owner.
    if SC.ActionSupervisor and type(SC.ActionSupervisor.history) == "function" then
        local okay, value = pcall(SC.ActionSupervisor.history, actor, 1)
        if okay and type(value) == "table" and type(value[1]) == "table" then owner = value[1] end
    end
    local rows = { "fsm=" .. tostring(call(actor, "getCurrentStateName")),
        "vehicle=" .. tostring(call(actor, "getVehicle") ~= nil),
        "nav=" .. tostring(nav.phase), "navTarget=" .. tostring(nav.target),
        "navReason=" .. tostring(nav.pathReason), "moveReason=" .. tostring(nav.lastMovementReason),
        "stuck=" .. tostring(nav.stuckAttempts), "terminal=" .. tostring(nav.terminalReason),
        "blocker=" .. tostring(nav.blockerType) .. "@" .. tostring(nav.blockerSquare),
        "searchMs=" .. tostring(nav.pathSearchAgeMs), "expanded=" .. tostring(nav.expandedNodes),
        "motionAgeMs=" .. tostring(route.lastProgressAt and math.max(0, current - route.lastProgressAt)),
        "ownerLast=" .. tostring(owner.action) .. "/" .. tostring(owner.phase) .. "/" .. tostring(owner.event) }
    return table.concat(rows, ";")
end
local function trace(H, fixture, label)
    local SC = SurvivorCompanion
    local mission = SC.ExpeditionPrototype.current()
    local scout = mission and mission.scout
    local wood = scout and scout.wood
    local state = wood and SC.ExpeditionWood.status(wood) or {}
    local counts = wood and SC.ExpeditionWood.cargoCounts(wood, fixture.crew, nil,
        fixture.mode == "drive" and 46 or nil) or {}
    local current = tonumber(fixture.latestStepAt) or tonumber(fixture.startedAt) or 0
    local hold = mission and mission.cohesionHold
    local rows = { label, "elapsedMs=" .. math.max(0, current - fixture.startedAt),
        "mode=" .. fixture.mode, "phase=" .. tostring(scout and scout.phase or "idle"),
        "carState=" .. tostring(scout and scout.vehicle and scout.vehicle.state),
        "carLeg=" .. tostring(scout and scout.vehicle and scout.vehicle.leg),
        "carBlocker=" .. tostring(scout and scout.vehicle and scout.vehicle.blocker),
        "carFailure=" .. tostring(scout and scout.vehicle and scout.vehicle.lastFailure
            and scout.vehicle.lastFailure.reason),
        "site=" .. tostring(wood and wood.siteIndex),
        "target=" .. tostring(scout and scout.destination and scout.destination.x)
            .. "," .. tostring(scout and scout.destination and scout.destination.y),
        "preparation=" .. tostring(wood and wood.preparationReason),
        "doneReason=" .. tostring(state.reason), "collected=" .. tostring(state.collected),
        "carried=" .. tostring(counts.carried), "loaded=" .. tostring(counts.loaded),
        "groundSeen=" .. count(fixture.ground), "treeSeen=" .. count(fixture.trees),
        "quietSite=" .. tostring(H.config.wood_expedition_quiet_site == "true"),
        "quietRemoved=" .. tostring(fixture.quietRemoved or 0),
        "quietCalls=" .. tostring(fixture.quietCalls or 0),
        "engine=" .. tostring(call(fixture.car and fixture.car.vehicle, "isEngineRunning")),
        "waypoint=" .. tracePoint(mission and mission.testWaypoint),
        "waypointBest=" .. tostring(scout and scout.bestDistanceToWaypoint),
        "waypointAgeMs=" .. tostring(scout and scout.waypointStagedAt and current - scout.waypointStagedAt),
        "progressAgeMs=" .. tostring(scout and scout.lastProgressAt and current - scout.lastProgressAt),
        "replans=" .. tostring(scout and scout.replans),
        "hold=" .. tostring(hold and hold.reason) .. ":" .. tostring(hold and hold.memberId)
            .. ":" .. tostring(hold and hold.maxGap) }
    for _, member in ipairs(fixture.crew) do
        local worker = wood and wood.workers and wood.workers[member.id]
        rows[#rows + 1] = member.id .. "@" .. position(member.actor) .. ";worker=" .. tostring(worker and worker.phase)
            .. ";dead=" .. tostring(call(member.actor, "isDead"))
            .. ";health=" .. tostring(call(call(member.actor, "getBodyDamage"), "getOverallBodyHealth"))
            .. ";" .. traceNavigation(SC, member.actor, current)
    end
    local line = table.concat(rows, "|")
    print("SC_REAL_SANDBOX|WOOD_EXPEDITION|" .. line)
    local writer = type(getFileWriter) == "function"
        and getFileWriter("SurvivorCompanionHarness/wood-expedition.log", true, true)
    if writer then writer:writeln(line); writer:close() end
    if fixture.mode == "drive" and scout and scout.phase == "outbound"
        and scout.vehicle and scout.vehicle.state == "parked_at_site" then
        fixture.approachObservedAt = fixture.approachObservedAt or current
        local number = fixture.approachScreenshots or 0
        if number < 4 and current - fixture.approachObservedAt >= (number + 1) * 60000 then
            fixture.approachScreenshots = number + 1
            screenshot(H, fixture, "approach-minute" .. fixture.approachScreenshots)
        end
    end
end
local function fail(H, fixture, current, result, setPhase, name, detail)
    cleanupKitchen(fixture, true)
    if fixture.observer and Events and Events.OnPostRender then Events.OnPostRender.Remove(fixture.observer) fixture.observer = nil end
    trace(H, fixture, "failure:" .. name)
    screenshot(H, fixture, "failure")
    result("FAIL", name, detail)
    setPhase("finish", current)
end
local function carried(SC, fixture, nativeId)
    for _, member in ipairs(fixture.crew) do
        local entries = SC.LoggingWork.inventoryEntries(member.actor)
        for _, entry in ipairs(entries or {}) do
            if SC.GameplayUtil.itemStableId(entry.item, false) == nativeId
                and call(entry.item, "getContainer") == entry.source then return entry.item, "member", entry.source end
        end
    end
    local car = fixture.car and fixture.car.vehicle
    local part, trunk
    if car then part, trunk = SC.Vehicle.cargoPart(car) end
    local list = trunk and call(trunk, "getItems")
    if list then
        for index = 0, SC.GameplayUtil.listSize(list) - 1 do
            local item = SC.GameplayUtil.listGet(list, index)
            if SC.GameplayUtil.itemStableId(item, false) == nativeId
                and call(item, "getContainer") == trunk then return item, "trunk", trunk end
        end
    end
end
local function observe(SC, fixture, mission)
    local wood = mission.scout and mission.scout.wood
    if not wood then return end
    fixture.tripId = mission.radioSession
    fixture.latestWood = wood
    fixture.loans = fixture.loans or {}
    for memberId, loan in pairs(wood.loans or {}) do
        local storage = SC.BaseLife.storage(loan.storageId)
        local container = storage and SC.BaseLife.resolveContainer(storage)
        local member = SC.Registry.byId(memberId)
        local item, source
        if member and member.actor then item, source = SC.LoggingWork.findItem(member.actor, loan.itemId) end
        if item then
            local marker = SC.GameplayUtil.modData(item)
            marker = marker and marker.LF_ExpeditionWoodTool
            local previous = fixture.loans[loan.itemId]
            fixture.loans[loan.itemId] = { item = item, storageId = loan.storageId,
                borrowed = previous and previous.borrowed or marker and marker.id == loan.itemId and marker.memberId == memberId
                    and call(item, "getContainer") == source
                    and SC.GameplayUtil.inventoryContains(source, item) == true
                    and container and SC.GameplayUtil.inventoryContains(container, item) == false }
        end
    end
    for _, worker in pairs(wood.workers or {}) do
        local point = worker.point
        if point then
            local square = SC.GameplayUtil.gridSquare(point.x, point.y, point.z)
            local tree = square and SC.LoggingWork.tree(square)
            if tree and not fixture.trees[key(point)] then
                fixture.trees[key(point)] = { point = { x = point.x, y = point.y, z = point.z },
                    tree = tree, health = tonumber(call(tree, "getHealth")), square = square }
            end
        end
    end
    for _, row in ipairs(wood.pendingLogs or {}) do
        local found = SC.LoggingWork.groundLog(row.source, row.id)
        if found and SC.GameplayUtil.itemType(found.item) == "Base.Log"
            and SC.GameplayUtil.worldItemPresent(found.square, found.wrapper) == true then
            fixture.ground[row.id] = true
            fixture.objects[row.id] = found.item
        end
    end
    for _, receipt in ipairs(wood.acquisitions or {}) do
        fixture.receipts[receipt.id] = receipt
        local item, holder, source = carried(SC, fixture, receipt.id)
        if item then
            fixture.objects[receipt.id] = item
            fixture.carried[receipt.id] = true
            if holder == "trunk" then fixture.loaded[receipt.id] = true end
            if fixture.fixtureBag and source == call(fixture.fixtureBag, "getInventory") then
                local weight, maximum = SC.GameplayUtil.carryLoad(fixture.crew[1].actor)
                fixture.bagCargoVerified = type(weight) == "number" and type(maximum) == "number"
                    and weight <= maximum and call(item, "getContainer") == source
                    and SC.GameplayUtil.inventoryContains(source, item) == true
            end
            local marker = SC.GameplayUtil.modData(item)
            marker = marker and marker.LF_ExpeditionWood
            if marker and marker.tripId == fixture.tripId and marker.id == receipt.id then fixture.protected[receipt.id] = true end
        end
    end
    local x, y = call(fixture.crew[1].actor, "getX"), call(fixture.crew[1].actor, "getY")
    if x and y and (x - fixture.departure.x)^2 + (y - fixture.departure.y)^2 >= 64 then fixture.departed = true end
    if mission.scout.phase == "wood_working" then fixture.worked = true end
end
local function removeObserver(fixture)
    if fixture.observer and Events and Events.OnPostRender then Events.OnPostRender.Remove(fixture.observer) fixture.observer = nil end
end
local function maintainQuietSite(H, fixture, mission, current, result)
    if H.config.wood_expedition_quiet_site ~= "true" then return false end
    local scout = mission and mission.scout
    local carState = scout and scout.vehicle and scout.vehicle.state
    if not scout or not scout.wood or not (scout.phase == "wood_working"
        or carState == "parked_at_site" or carState == "unloading_site") then return false end
    if current < (fixture.nextQuietAt or 0) then return false end
    fixture.nextQuietAt = current + 1000
    if type(H.clearZombiesNear) ~= "function" then
        fixture.quietError = "existing Harness.clearZombiesNear helper unavailable"
        return false
    end
    local actor = fixture.crew[1] and fixture.crew[1].actor
    local okay, removed = pcall(H.clearZombiesNear, actor, 60)
    if not okay or type(removed) ~= "number" or removed < 0 then
        fixture.quietError = "site cleanup failed: " .. tostring(removed)
        return false
    end
    fixture.quietRemoved = (fixture.quietRemoved or 0) + removed
    fixture.quietCalls = (fixture.quietCalls or 0) + 1
    result("PASS", "wood_probe_quiet_site_cleanup", "explicit clone fixture;phase=" .. tostring(scout.phase)
        .. ";carState=" .. tostring(carState) .. ";radius=60;removed=" .. removed
        .. ";total_removed=" .. fixture.quietRemoved .. ";calls=" .. fixture.quietCalls)
    return true
end
local function startObserver(H, fixture, result)
    if not Events or not Events.OnPostRender or not Events.OnPostRender.Add then return end
    fixture.observer = function()
        local SC = SurvivorCompanion
        observeWitnessMovement(fixture)
        observeSoloVisibility(H, fixture, result, fixture.latestStepAt)
        observeKitchen(H, fixture, result)
        local mission = SC.ExpeditionPrototype.current()
        if not mission or not mission.scout or not mission.scout.wood then return end
        local current = SC.GameplayUtil.nowMs()
        if current < (fixture.nextEvidenceAt or 0) then return end
        fixture.nextEvidenceAt = current + 50
        maintainQuietSite(H, fixture, mission, current, result)
        observe(SC, fixture, mission)
    end
    Events.OnPostRender.Add(fixture.observer)
end
local function treeEffects(fixture)
    local felled = 0
    for _, row in pairs(fixture.trees) do
        if call(row.tree, "getObjectIndex") == -1 or call(row.square, "getTree") ~= row.tree then felled = felled + 1 end
    end
    return felled
end
local function storageOwned(SC, row, item)
    if not item or SC.GameplayUtil.itemType(item) ~= "Base.Log"
        or SC.GameplayUtil.itemStableId(item, false) ~= row.id then return false end
    local destination = row.destination
    if destination and destination.kind == "log_yard" then
        local square = SC.GameplayUtil.gridSquare(destination.x, destination.y, destination.z)
        local wrapper = call(item, "getWorldItem")
        return square and wrapper and call(item, "getContainer") == nil
            and call(wrapper, "getItem") == item and SC.GameplayUtil.worldItemPresent(square, wrapper) == true
    end
    local storage = SC.BaseLife.storage(row.storageId)
    local container = storage and SC.BaseLife.resolveContainer(storage)
    return container and call(item, "getContainer") == container
        and SC.GameplayUtil.inventoryContains(container, item) == true
end
local SUPPLY_CATEGORIES = { tools = 1, weapons = 2, construction = 3,
    crafting = 4, farming = 5, general = 6 }
local function availableAxe(SC, actor, storage, container, item)
    if call(item, "isBroken") ~= false or SC.ExpeditionWood.reserved(item) then return false end
    if not storage then
        local data = SC.GameplayUtil.modData(item) or {}
        return not data.LF_FieldBorrowedAxe and not data.LF_ProductionToolLoan
            and not data.LF_WorkTransport and not data.SC_ChefSupplyReceipt
    end
    return SUPPLY_CATEGORIES[storage.category] and SC.BaseLife.storage(storage.id) == storage
        and SC.BaseLife.withdrawable(storage) and SC.BaseLife.resolveContainer(storage) == container
        and SC.GameplayUtil.inventoryContains(container, item)
        and (not SC.WorkTransport.foreignProtected or not SC.WorkTransport.foreignProtected(item, actor))
        and (not SC.PersonalItems or not SC.PersonalItems.isProtected(item, actor, "camp_supply"))
        and SC.BaseLife.availableCountExact(storage, SC.GameplayUtil.itemType(item)) > 0
end
local function equipmentSurvey(SC, actor, result)
    local survey = { complete = true, usable = 0, supplies = {}, rows = {}, entries = {} }
    local entries, why = SC.LoggingWork.inventoryEntries(actor)
    if not entries then survey.complete = false end
    survey.entries = entries or {}
    for _, entry in ipairs(survey.entries) do
        if SC.GameplayUtil.itemHasTag(entry.item, "CHOP_TREE") then
            local usable = availableAxe(SC, actor, nil, entry.source, entry.item)
            if usable then survey.usable = survey.usable + 1 survey.heldAxe = entry.item end
            result("PASS", "wood_probe_actor_axe_survey", "type=" .. SC.GameplayUtil.itemType(entry.item)
                .. ";id=" .. tostring(SC.GameplayUtil.itemStableId(entry.item, false))
                .. ";broken=" .. tostring(call(entry.item, "isBroken")) .. ";usable=" .. tostring(usable))
        end
    end
    local inspected = 0
    for _, storage in ipairs(SC.BaseLife.storageRows(nil, false)) do
        local container = SC.BaseLife.resolveContainer(storage)
        local list = container and call(container, "getItems")
        local size = list and SC.GameplayUtil.listSize(list)
        local production = SUPPLY_CATEGORIES[storage.category] and SC.BaseLife.withdrawable(storage)
        local axes, usable = 0, 0
        if production and (not size or size + inspected > 8192) then survey.complete = false end
        if size and size + inspected <= 8192 then
            inspected = inspected + size
            for index = 0, size - 1 do
                local item = SC.GameplayUtil.listGet(list, index)
                if item and SC.GameplayUtil.itemHasTag(item, "CHOP_TREE") then
                    axes = axes + 1
                    if production and availableAxe(SC, actor, storage, container, item) then
                        usable, survey.usable = usable + 1, survey.usable + 1
                        if not survey.supplyAxe or (tonumber(call(item, "getTreeDamage")) or 0)
                            > (tonumber(call(survey.supplyAxe, "getTreeDamage")) or 0) then survey.supplyAxe = item end
                    end
                    result("PASS", "wood_probe_storage_axe_survey", "storage=" .. storage.id
                        .. ";type=" .. SC.GameplayUtil.itemType(item)
                        .. ";id=" .. tostring(SC.GameplayUtil.itemStableId(item, false))
                        .. ";broken=" .. tostring(call(item, "isBroken")))
                end
            end
        end
        survey.rows[#survey.rows + 1] = storage
        if SUPPLY_CATEGORIES[storage.category] and container and SC.BaseLife.withdrawable(storage)
            and SC.BaseLife.storageAcceptsDeposit(storage, container) == true then
            survey.supplies[#survey.supplies + 1] = { storage = storage, container = container }
        end
        result("PASS", "wood_probe_storage_equipment_survey", "storage=" .. storage.id
            .. ";category=" .. tostring(storage.category) .. ";loaded=" .. tostring(container ~= nil)
            .. ";withdrawals=" .. tostring(SC.BaseLife.withdrawable(storage))
            .. ";deposits=" .. tostring(storage.deposits ~= false) .. ";items=" .. tostring(size)
            .. ";axes=" .. axes .. ";usable=" .. usable)
    end
    table.sort(survey.supplies, function(a, b)
        local left, right = SUPPLY_CATEGORIES[a.storage.category], SUPPLY_CATEGORIES[b.storage.category]
        if left ~= right then return left < right end
        return tostring(a.storage.id) < tostring(b.storage.id)
    end)
    result("PASS", "wood_probe_equipment_survey", "complete=" .. tostring(survey.complete)
        .. ";usable_axes=" .. survey.usable .. ";items_inspected=" .. inspected
        .. ";inventory=" .. tostring(why) .. ";stock_targets=" .. #survey.supplies)
    return survey
end
local function freeCapacity(container, actor)
    local free = tonumber(call(container, "getFreeCapacity", actor))
    if free then return free end
    local capacity = tonumber(call(container, "getEffectiveCapacity", actor)) or tonumber(call(container, "getCapacity"))
    local weight = tonumber(call(container, "getCapacityWeight"))
    return capacity and weight and capacity - weight or nil
end
local function projectedCarry(SC, actor, axe, held)
    local weight, maximum = SC.GameplayUtil.carryLoad(actor)
    if type(weight) ~= "number" or type(maximum) ~= "number" then return false, "native carry load unavailable" end
    local extra = held and 0 or SC.GameplayUtil.itemWeight(axe)
    local root = SC.GameplayUtil.inventory(actor)
    local rootFree = freeCapacity(root, actor)
    if rootFree and rootFree >= 9 + extra and weight + extra + 9 <= maximum then return true, "root" end
    for _, entry in ipairs(SC.LoggingWork.inventoryEntries(actor) or {}) do
        local bag = call(entry.item, "getInventory")
        if bag and entry.source == root and call(actor, "isEquippedClothing", entry.item) == true then
            local free = freeCapacity(bag, actor)
            local reduction = tonumber(call(entry.item, "getWeightReduction")) or 0
            if free and free >= 9 and weight + extra + 9 * (1 - reduction / 100) <= maximum then
                return true, "equipped bag id=" .. tostring(SC.GameplayUtil.itemStableId(entry.item, false))
                    .. ";free=" .. free .. ";reduction=" .. reduction
            end
        end
    end
    return false, "weight=" .. weight .. ";maximum=" .. maximum .. ";axe_extra=" .. extra .. ";log=9"
end
local function stockEquipment(SC, H, fixture, survey, check, result)
    if H.config.wood_expedition_stock_equipment ~= "true" then return true end
    if not check("wood_probe_stock_survey_complete", survey.complete,
        "fixture refuses to mask unloaded or over-budget production inputs") then return false end
    local actor, axe = fixture.crew[1].actor, survey.heldAxe or survey.supplyAxe
    if survey.usable == 0 then
        local native = type(instanceItem) == "function" and instanceItem("Base.Axe")
        if not check("wood_probe_stock_native_axe", native ~= nil
            and SC.GameplayUtil.itemType(native) == "Base.Axe" and call(native, "isBroken") == false,
            "one real fixture axe; no logs, trees, actor or weapon-stat edits") then return false end
        local selected
        for _, target in ipairs(survey.supplies) do
            if SC.WorkTransport.hasRoom(target.container, actor, native) == true then selected = target break end
        end
        if not check("wood_probe_stock_permitted_camp_supplies", selected ~= nil,
            "existing camp supply container must permit deposits, withdrawals and actual axe capacity; Tools then Weapons, Construction, Crafting, Farming, General") then return false end
        SC.GameplayUtil.addItem(selected.container, native)
        if not check("wood_probe_stock_exact_axe_owner", call(native, "getContainer") == selected.container
            and SC.GameplayUtil.inventoryContains(selected.container, native) == true,
            "native axe physically placed into existing permitted camp supply; production must fetch it") then return false end
        fixture.fixtureAxe, fixture.fixtureAxeId, fixture.fixtureAxeStorage = native,
            SC.GameplayUtil.itemStableId(native, true), selected.storage
        axe = native
        result("PASS", "wood_probe_stock_axe_created", "type=Base.Axe;id=" .. tostring(fixture.fixtureAxeId)
            .. ";storage=" .. selected.storage.id .. ";category=" .. selected.storage.category .. ";original usable axes=0")
    else
        result("PASS", "wood_probe_stock_axe_not_needed", "usable real inputs=" .. survey.usable .. ";created=0")
    end
    local admitted, why = projectedCarry(SC, actor, axe, survey.heldAxe ~= nil)
    result("PASS", "wood_probe_projected_native_capacity", "admitted=" .. tostring(admitted) .. ";" .. tostring(why))
    if not admitted then
        local root = SC.GameplayUtil.inventory(actor)
        local native = type(instanceItem) == "function" and instanceItem("Base.Bag_BigHikingBag")
        if not check("wood_probe_stock_native_bag", native ~= nil and call(native, "getInventory") ~= nil,
            "one real empty native hiking bag only because axe plus one log exceeds existing transport") then return false end
        local location = call(native, "canBeEquipped")
        if not check("wood_probe_stock_bag_back_free", location ~= nil and call(actor, "getWornItem", location) == nil,
            "refuse replacing existing clothing or a saved worn bag") then return false end
        SC.GameplayUtil.addItem(root, native)
        call(actor, "setWornItem", location, native)
        if not check("wood_probe_stock_exact_bag_owner", call(native, "getContainer") == root
            and SC.GameplayUtil.inventoryContains(root, native) == true
            and call(actor, "isEquippedClothing", native) == true,
            "actual native bag is carried and worn; no capacity or strength edits") then return false end
        call(actor, "resetModelNextFrame")
        fixture.fixtureBag, fixture.fixtureBagId = native, SC.GameplayUtil.itemStableId(native, true)
        admitted, why = projectedCarry(SC, actor, axe, survey.heldAxe ~= nil)
        if not check("wood_probe_stock_actual_bag_capacity", admitted,
            "native weight, free capacity and reduction after real bag equip;" .. tostring(why)) then return false end
    end
    return true
end
local function setup(H, current, check, result, setPhase)
    local SC = SurvivorCompanion
    local crewSize = tonumber(H.config.wood_expedition_crew_size) or 1
    if not check("wood_probe_crew_size_option", crewSize == 1 or crewSize == 3,
        "requested crew=" .. tostring(crewSize)) then setPhase("finish", current) return end
    if (not SC.BaseLife.active() or #SC.Registry.records() < crewSize) and current - H.phaseStartedAt < 15000 then return end
    local fixture = { mode = H.config.wood_expedition_travel_mode or "walk", crew = {},
        trees = {}, ground = {}, objects = {}, receipts = {}, carried = {}, loaded = {}, protected = {}, loans = {},
        startedAt = current, nextTraceAt = current }
    H.woodExpedition = fixture
    fixture.quantity = fixture.mode == "drive" and 2 or 1
    if not check("wood_probe_available", SC.ExpeditionWood and SC.ExpeditionForests
        and type(SC.ExpeditionPrototype.startWoodCollection) == "function", "public production wood task") then setPhase("finish", current) return end
    if not check("wood_probe_no_prior_view", SC.ExpeditionPrototype.current() == nil
        and SC.BaseWatch.current() == nil and SC.ViewSession.owner() == nil and getSpecificPlayer(1) == nil,
        "refuse an existing session; never reset it") then setPhase("finish", current) return end
    fixture.crew = selectCrew(SC, crewSize)
    if not check("wood_probe_saved_scarlet", fixture.crew[1] ~= nil,
        "requires the saved healthy Scarlet; no companion placement, stat changes or respawn") then setPhase("finish", current) return end
    if not check("wood_probe_saved_crew", #fixture.crew == crewSize,
        "requested=" .. crewSize .. ";healthy recruited saved crew=" .. #fixture.crew
            .. ";three-person crew requires existing camp residents; no movement or AI overrides") then setPhase("finish", current) return end
    for _, car in ipairs(SC.ExpeditionCar.parkedCars()) do if car.sqlId == 46 then fixture.car = car break end end
    if fixture.mode == "drive" and not check("wood_probe_saved_car46", fixture.car ~= nil,
        "requires existing parked SQL46; no vehicle spawning or fuel edits") then setPhase("finish", current) return end
    local actor = fixture.crew[1].actor
    fixture.departure = { x = call(actor, "getX"), y = call(actor, "getY") }
    local entries = SC.LoggingWork.inventoryEntries(actor)
    local gear = {}
    for _, entry in ipairs(entries or {}) do
        if SC.GameplayUtil.itemHasTag(entry.item, "CHOP_TREE") then
            gear[#gear + 1] = SC.GameplayUtil.itemType(entry.item) .. ":" .. tostring(SC.GameplayUtil.itemStableId(entry.item, false))
        end
    end
    local weight, limit = SC.GameplayUtil.carryLoad(actor)
    result("PASS", "wood_probe_real_inputs", "Scarlet=" .. position(actor) .. ";axes=" .. table.concat(gear, ",")
        .. ";carry=" .. tostring(weight) .. "/" .. tostring(limit)
        .. ";saved permitted base supplies are fetched by production preparation; no staged gear")
    local survey = equipmentSurvey(SC, actor, result)
    if not stockEquipment(SC, H, fixture, survey, check, result) then setPhase("finish", current) return end
    result("PASS", "wood_probe_quiet_site_configuration", "enabled="
        .. tostring(H.config.wood_expedition_quiet_site == "true")
        .. ";existing helper only; radius=60; site work only; no crew, cargo, tree, health or stat changes")
    snapshotVisibility(SC, fixture, H.player)
    captureVisibility(SC, fixture, "before")
    local initiallyVisible = 0
    for _, row in ipairs(fixture.visibility.cars) do if row.before.visible then initiallyVisible = initiallyVisible + 1 end end
    result("PASS", "wood_probe_visibility_inventory", "native loaded cars=" .. fixture.visibility.vehicleInventorySize
        .. ";inspected=" .. fixture.visibility.vehicleInspected .. ";stationary nearby witnesses=" .. #fixture.visibility.cars
        .. ";initially primary-visible=" .. initiallyVisible .. ";crew=" .. #fixture.crew
        .. ";home witnesses=" .. (#fixture.visibility.actors - #fixture.crew))
    local beforePNG, beforeDetail = screenshot(H, fixture, "before")
    check("wood_probe_visibility_before_png", beforePNG, beforeDetail)
    if not check("wood_probe_visibility_baseline", initiallyVisible >= 1,
        "requires at least one actually primary-visible unchanged-car witness; all up to8 are retained; no camera or alpha changes") then
        setPhase("finish", current) return
    end
    startObserver(H, fixture, result)
    setPhase("wood_expedition_dispatch", current)
end
function Probe.step(H, current, check, result, setPhase)
    if H.phase == "wood_expedition_setup" then return setup(H, current, check, result, setPhase) end
    local SC, fixture = SurvivorCompanion, H.woodExpedition
    if not fixture then result("FAIL", "wood_probe_fixture_missing", H.phase) setPhase("finish", current) return end
    fixture.latestStepAt = current
    for _, member in ipairs(fixture.crew or {}) do
        if call(member.actor, "isDead") == true then
            return fail(H, fixture, current, result, setPhase, "wood_probe_crew_died",
                "saved crew member died at " .. position(member.actor)
                    .. "; storage cannot make this a successful healthy-crew trip")
        end
    end
    if fixture.quietError then return fail(H, fixture, current, result, setPhase,
        "wood_probe_quiet_site_helper", fixture.quietError) end
    local deadline = tonumber(H.config.wood_expedition_deadline_seconds) or 780
    if deadline < 120 or deadline > 1500 or deadline ~= math.floor(deadline) then deadline = 780 end
    if current - fixture.startedAt > deadline * 1000 then
        return fail(H, fixture, current, result, setPhase, "wood_probe_deadline",
            deadline .. "s ordinary dispatch/work/return/storage deadline; no manual rescue")
    end
    if H.phase == "wood_expedition_dispatch" then
        local car = fixture.car
        local started, reason = SC.ExpeditionPrototype.startWoodCollection(fixture.crew, {
            request = { mode = "count", quantity = fixture.quantity },
            travelMode = fixture.mode == "drive" and "drive" or "road",
            parkingZoneId = fixture.mode == "drive" and car.zone.id or nil,
            vehicleSqlId = fixture.mode == "drive" and car.sqlId or nil,
            turnHomeAfterHours = 4, doctrine = "stealth", restockBaseDuty = false,
        })
        if not started and (reason == "forest_scan_pending" or reason == "DATA_NOT_READY") then return end
        if not check("wood_probe_public_dispatch", started == true,
            "mode=" .. fixture.mode .. ";requested=" .. fixture.quantity .. ";reason=" .. tostring(reason)) then setPhase("finish", current) return end
        fixture.dispatchedAt = current
        trace(H, fixture, "dispatched")
        setPhase("wood_expedition_mission", current)
    elseif H.phase == "wood_expedition_mission" then
        local mission = SC.ExpeditionPrototype.current()
        if mission then
            maintainQuietSite(H, fixture, mission, current, result)
            observe(SC, fixture, mission)
            if current >= fixture.nextTraceAt then fixture.nextTraceAt = current + 1000 trace(H, fixture, "mission") end
            if fixture.worked and not fixture.workScreenshot then screenshot(H, fixture, "forest") fixture.workScreenshot = true end
            return
        end
        fixture.returnedAt = current
        trace(H, fixture, "natural_return")
        screenshot(H, fixture, "natural-return")
        if not check("wood_probe_natural_trip", fixture.departed and fixture.worked and count(fixture.receipts) == fixture.quantity,
            "actual departure=" .. tostring(fixture.departed) .. ";forest work=" .. tostring(fixture.worked)
                .. ";actual picked logs=" .. count(fixture.receipts) .. ";requested=" .. fixture.quantity) then
            setPhase("wood_expedition_visibility", current) return
        end
        check("wood_probe_native_tree_effect", treeEffects(fixture) >= 1, "observed mature native trees removed=" .. treeEffects(fixture))
        check("wood_probe_native_ground_output", count(fixture.ground) >= fixture.quantity,
            "actual raw Base.Log world IDs observed=" .. count(fixture.ground))
        for nativeId in pairs(fixture.receipts) do
            check("wood_probe_physical_carried_" .. nativeId, fixture.carried[nativeId] and fixture.protected[nativeId],
                "exact native log acquired in member inventory or owned trunk with trip marker")
            if fixture.mode == "drive" then check("wood_probe_physical_trunk_" .. nativeId, fixture.loaded[nativeId] == true,
                "same native ID physically observed in saved car46 trunk") end
        end
        setPhase("wood_expedition_storage", current)
    elseif H.phase == "wood_expedition_storage" then
        if fixture.visibility and not fixture.visibility.done then
            if current - fixture.returnedAt < 30000 then return end
            captureVisibility(SC, fixture, "postsolo-timeout")
            return fail(H, fixture, current, result, setPhase, "wood_probe_visibility_restore_deadline",
                "no12 normal primary render frames plus1500ms after restore within30s; native diagnostic and before/after facts retained")
        end
        local debrief = SC.ExpeditionPrototype.lastDebrief() or {}
        local integration = debrief.integration
        local stored = 0
        for _, row in ipairs(integration and integration.items or {}) do if row.stored then stored = stored + 1 end end
        if stored < fixture.quantity then
            if current >= fixture.nextTraceAt then fixture.nextTraceAt = current + 2000 trace(H, fixture, "storage_pending:" .. stored) end
            return
        end
        local toolsPending = integration and integration.woodWork and count(integration.woodWork.loans) or 0
        if toolsPending > 0 then
            if current >= fixture.nextTraceAt then fixture.nextTraceAt = current + 2000 trace(H, fixture, "tool_return_pending:" .. toolsPending) end
            return
        end
        local actualStored = 0
        for _, row in ipairs(integration.items) do
            local item = fixture.objects[row.id]
            local owned = row.stored and storageOwned(SC, row, item)
            if owned then actualStored = actualStored + 1 end
            check("wood_probe_exact_storage_" .. row.id, owned == true,
                "reported=" .. tostring(row.stored) .. ";storage=" .. tostring(row.storageId)
                    .. ";exact item=" .. tostring(item ~= nil) .. ";actual owner verified=" .. tostring(owned))
        end
        check("wood_probe_all_requested_stored", actualStored == fixture.quantity,
            "verified original raw log objects=" .. actualStored .. ";requested=" .. fixture.quantity)
        if fixture.fixtureAxe then
            local loan = fixture.loans[fixture.fixtureAxeId]
            local container = SC.BaseLife.resolveContainer(fixture.fixtureAxeStorage)
            local data = SC.GameplayUtil.modData(fixture.fixtureAxe)
            check("wood_probe_fixture_axe_production_withdrawal", loan and loan.borrowed,
                "same native stocked axe was physically withdrawn by production and registered as a source loan")
            check("wood_probe_fixture_axe_loan_return", container and call(fixture.fixtureAxe, "getContainer") == container
                and SC.GameplayUtil.inventoryContains(container, fixture.fixtureAxe) == true
                and data and data.LF_ExpeditionWoodTool == nil,
                "same native axe returned to original chosen camp supply container; loan marker cleared")
        end
        if fixture.fixtureBag then
            check("wood_probe_fixture_bag_physical_capacity", fixture.bagCargoVerified == true,
                "actual native log observed inside the worn fixture bag while native load stayed below Strength limit")
        end
        for index, member in ipairs(fixture.crew) do
            local record = SC.Registry.byId(member.id)
            check(index == 1 and "wood_probe_saved_actor_healthy" or "wood_probe_saved_actor_healthy_" .. member.id,
                record and record.actor == member.actor and healthy(member.actor),
                "same original " .. readableName(SC, member) .. " healthy at " .. position(member.actor))
        end
        check("wood_probe_engine_off", not fixture.car or call(fixture.car.vehicle, "isEngineRunning") == false,
            "saved car46 engine=" .. tostring(call(fixture.car and fixture.car.vehicle, "isEngineRunning")))
        check("wood_probe_solo_released", getSpecificPlayer(1) == nil and SC.ViewSession.owner() == nil,
            "ordinary expedition released its view")
        screenshot(H, fixture, "stored")
        result("PASS", "wood_probe_completed", fixture.mode .. ";requested=" .. fixture.quantity
            .. ";collected=" .. count(fixture.receipts) .. ";stored=" .. actualStored
            .. ";felled=" .. treeEffects(fixture) .. ";elapsedMs=" .. (current - fixture.dispatchedAt)
            .. ";quiet_site=" .. tostring(H.config.wood_expedition_quiet_site == "true")
            .. ";quiet_removed=" .. tostring(fixture.quietRemoved or 0))
        if kitchenRequested(H) and actualStored == fixture.quantity then
            local started, reason = startKitchenRoute(H, fixture, current, result)
            if not started then return fail(H, fixture, current, result, setPhase,
                "wood_probe_kitchen_route_fixture", reason) end
            setPhase("wood_expedition_kitchen_walk", current)
        else removeObserver(fixture) setPhase("finish", current) end
    elseif H.phase == "wood_expedition_kitchen_walk" then
        local kitchen = fixture.kitchen
        if not kitchen or kitchen.pathFailed then
            captureKitchen(H, fixture, "kitchen-path-failed", result)
            return fail(H, fixture, current, result, setPhase, "wood_probe_kitchen_native_path",
                "ordinary native player path failed; no relocation, retry or wall reset")
        end
        if current - kitchen.startedAt > 90000 then
            captureKitchen(H, fixture, "kitchen-path-timeout", result)
            return fail(H, fixture, current, result, setPhase, "wood_probe_kitchen_walk_deadline",
                "90s ordinary player path deadline; target12035.5,6746.5,0")
        end
        if kitchen.pathComplete then
            if not kitchenPose(fixture.primary, kitchen) then
                captureKitchen(H, fixture, "kitchen-arrival-mismatch", result)
                return fail(H, fixture, current, result, setPhase, "wood_probe_kitchen_actual_arrival",
                    "native completion callback did not leave the same player at the verified kitchen point")
            end
            kitchen.stage, kitchen.arrivedAt = "observing", current
            result("PASS", "wood_probe_kitchen_actual_arrival", "normal native path callback; same primary at " .. position(fixture.primary))
            setPhase("wood_expedition_kitchen_capture", current)
        end
    elseif H.phase == "wood_expedition_kitchen_capture" then
        local kitchen = fixture.kitchen
        if kitchen.poseLost or current - kitchen.arrivedAt > 30000 then
            captureKitchen(H, fixture, "kitchen-observation-interrupted", result)
            return fail(H, fixture, current, result, setPhase, "wood_probe_kitchen_observation",
                "left verified kitchen pose or did not render120frames plus1500ms within30s; no reposition or cache change")
        end
        if kitchen.done then
            cleanupKitchen(fixture, false)
            removeObserver(fixture)
            setPhase("finish", current)
        end
    elseif H.phase == "wood_expedition_visibility" then
        if fixture.visibility and fixture.visibility.done then removeObserver(fixture) setPhase("finish", current)
        elseif current - fixture.returnedAt >= 30000 then
            captureVisibility(SC, fixture, "postsolo-timeout")
            fail(H, fixture, current, result, setPhase, "wood_probe_visibility_restore_deadline",
                "unsuccessful ordinary trip still requires return-view diagnostics; no12 primary render frames plus1500ms within30s")
        end
    end
end
Probe._tests = { healthy = healthy, count = count, treeEffects = treeEffects, storageOwned = storageOwned,
    equipmentSurvey = equipmentSurvey, stockEquipment = stockEquipment, projectedCarry = projectedCarry,
    maintainQuietSite = maintainQuietSite, selectCrew = selectCrew, visibilityFacts = visibilityFacts,
    snapshotVisibility = snapshotVisibility, captureVisibility = captureVisibility,
    compareVisibleCars = compareVisibleCars, observeSoloVisibility = observeSoloVisibility,
    observeWitnessMovement = observeWitnessMovement, kitchenRequested = kitchenRequested,
    startKitchenRoute = startKitchenRoute, observeKitchen = observeKitchen, traceNavigation = traceNavigation,
    kitchenPose = kitchenPose, cleanupKitchen = cleanupKitchen }
SCRealSandboxHarnessProbes = SCRealSandboxHarnessProbes or {}
SCRealSandboxHarnessProbes.SCWoodExpeditionProbe = Probe
return Probe
