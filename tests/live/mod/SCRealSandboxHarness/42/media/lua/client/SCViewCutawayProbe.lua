-- SPDX-License-Identifier: MIT
-- Private cloned-save GL probe. Never changes wall geometry or cutaway flags.
-- Observe preserves release A; B/C select the native candidate under test.
local Probe = {}

local function call(object, method, ...)
    if object == nil then return nil end
    local fn = object[method]
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, object, ...)
    if ok then return value end
end

local function point(actor)
    return { x = call(actor, "getX"), y = call(actor, "getY"), z = call(actor, "getZ") }
end

local function hasBit(flags, bit)
    return type(flags) == "number" and math.floor(flags / bit) % 2 == 1
end

local function preferRemote(current, candidate)
    if not current or candidate.z > current.z
        or candidate.z == 1 and current.z == 1 and candidate.gap > current.gap then
        return candidate
    end
    return current
end

local function releaseReceipt(fixture, mode, owner, leader, accepted, slotGone, nativeReleased, leaderAlive)
    return { generation = fixture.openGeneration, mode = mode, leader = leader, leaderAlive = leaderAlive,
        valid = fixture.mode == mode and owner == mode and fixture.leader ~= nil
            and leader ~= nil and leader == fixture.leader.actor
            and accepted == true and slotGone == true and nativeReleased == true and leaderAlive == true }
end

local function releaseTransition(fixture, phase, slot, nativeReleased, joining)
    if phase ~= "view_cutaway_join" and phase ~= "view_cutaway_remote"
        and phase ~= "view_cutaway_return" then return nil end
    local observed = fixture.releaseObserved
    if observed then
        if observed.valid and observed.generation == fixture.openGeneration
            and observed.mode == fixture.mode and observed.leader == fixture.leader.actor
            and slot == nil and nativeReleased == true then return "solo" end
        return "invalid_release"
    end
    if slot == nil and not (phase == "view_cutaway_join"
        and fixture.joinedAt == nil and joining == true) then return "missing_release" end
    return nil
end

local function updateCount(actor)
    local diagnostic = call(actor, "getCompanionPostUpdateDiagnostic")
    return tonumber(tostring(diagnostic):match("count=(%d+)")), diagnostic
end

local function healthy(actor, before)
    local count, diagnostic = updateCount(actor)
    local failure = call(actor, "getBridgeFailure")
    return actor ~= nil and call(actor, "isDead") == false
        and failure == "" and count ~= nil and before ~= nil and count > before,
        "count=" .. tostring(count) .. " before=" .. tostring(before)
            .. " failure=" .. tostring(failure) .. " update=" .. tostring(diagnostic)
end

local function snapshotSql(H, fixture)
    local read = SCSplitScreenProbe.debugPlayerSqlId
    if read == nil then return nil end
    local saved = { primary = read(H.player), companions = {},
        slot = SurvivorCompanion.ViewSession.slotSqlId() }
    for _, record in ipairs(fixture.records) do
        saved.companions[record.id] = read(record.actor)
    end
    return saved
end

local function sameSql(H, fixture)
    local saved, read = fixture.stockSql, SCSplitScreenProbe.debugPlayerSqlId
    if not saved or not read then return false, "SQL snapshot API unavailable" end
    if read(H.player) ~= saved.primary
        or SurvivorCompanion.ViewSession.slotSqlId() ~= saved.slot then
        return false, "primary or reusable companion slot SQL identity changed"
    end
    for _, record in ipairs(fixture.records) do
        if read(record.actor) ~= saved.companions[record.id] then
            return false, "retained companion SQL identity changed: " .. record.id
        end
    end
    return true, "primary and every retained companion SQL ID unchanged"
end

local function retainedIdentity(SC, fixture)
    for _, record in ipairs(fixture.records) do
        local current = SC.Registry.byId(record.id)
        if current == nil or current.actor ~= record.actor then
            return false, "retained actor identity lost: " .. record.id
                .. " expected=" .. tostring(record.actor)
                .. " current=" .. tostring(current and current.actor)
        end
    end
    return true, "every original native actor is still the exact registered identity"
end

local function place(actor, at)
    if not actor or not at then return false end
    local ok = pcall(function()
        actor:setX(at.x); actor:setY(at.y); actor:setZ(at.z)
        actor:setNextX(at.x); actor:setNextY(at.y)
        actor:setLastX(at.x); actor:setLastY(at.y); actor:setLastZ(at.z)
        actor:setCurrentSquareFromPosition()
        actor:setSquare(actor:getCurrentSquare())
        actor:setMovingSquare(actor:getCurrentSquare())
    end)
    return ok and call(actor, "getCurrentSquare") ~= nil
end

local function safeFloor(square)
    return square ~= nil and call(square, "isSolid") == false
        and call(square, "isSolidTrans") ~= true and call(square, "HasTree") ~= true
        and call(square, "getVehicleContainer") == nil
        and call(square, "TreatAsSolidFloor") == true and call(square, "hasFloor") == true
end

local function bodySnapshot(actor)
    local body, wounds = call(actor, "getBodyDamage"), {}
    local parts = call(body, "getBodyParts")
    local deep = 0
    for index = 0, math.min(tonumber(call(parts, "size")) or 0, 32) - 1 do
        local part = call(parts, "get", index)
        local bleeding, wounded = call(part, "bleeding"), call(part, "deepWounded")
        if wounded == true then deep = deep + 1 end
        if bleeding == true or wounded == true then
            wounds[#wounds + 1] = tostring(call(part, "getType")) .. ":"
                .. tostring(bleeding) .. "/" .. tostring(wounded)
        end
    end
    return { health = call(body, "getOverallBodyHealth"), bleeding = call(body, "getNumPartsBleeding"),
        deep = deep, alive = call(actor, "isDead") == false, z = call(actor, "getZ"),
        wounds = table.concat(wounds, ",") }
end

local function bodyDetail(snapshot)
    return "z=" .. tostring(snapshot.z) .. ";health=" .. tostring(snapshot.health)
        .. ";bleeding=" .. tostring(snapshot.bleeding) .. ";deep=" .. snapshot.deep
        .. ";alive=" .. tostring(snapshot.alive) .. ";wounds=" .. snapshot.wounds
end

local function excursionSafe(before, after, target)
    return before ~= nil and before.alive and after.alive
        and type(after.z) == "number" and math.abs(after.z - target.z) < 0.05
        and type(before.health) == "number" and type(after.health) == "number"
        and after.health + 0.05 >= before.health
        and type(before.bleeding) == "number" and type(after.bleeding) == "number"
        and after.bleeding <= before.bleeding and after.deep <= before.deep
end

-- A visible south face is the north edge of its southern owner square; an
-- east face is the west edge of its eastern owner. Require an actual room
-- immediately behind each wall. Counters against that edge do not change its
-- room ownership; choose a free observation pose separately, in the SAME room.
local function standablePose(U, x, y, bit, room, indoors)
    local best, bestGap
    for depth = 1, indoors and 4 or 3 do
        for _, side in ipairs({ 0, -1, 1, -2, 2 }) do
            local direction = indoors and -1 or 1
            local px = x + (bit == 2 and direction * depth or side)
            local py = y + (bit == 1 and direction * depth or side)
            local square = U.gridSquare(px, py, 0)
            local gap = depth * depth + side * side
            if safeFloor(square) and call(square, "getRoom") == room
                and (bestGap == nil or gap < bestGap) then
                best, bestGap = { x = px + 0.5, y = py + 0.5, z = 0 }, gap
            end
        end
    end
    return best
end

local function wallAt(U, x, y, bit)
    local square = U.gridSquare(x, y, 0)
    local flag = IsoFlagType and (bit == 1 and IsoFlagType.cutN or IsoFlagType.cutW)
    if not square or not flag
        or call(call(square, "getProperties"), "has", flag) ~= true then return nil end
    local inside = U.gridSquare(x - (bit == 2 and 1 or 0),
        y - (bit == 1 and 1 or 0), 0)
    local room = call(inside, "getRoom")
    if room == nil or call(inside, "TreatAsSolidFloor") ~= true
        or call(inside, "hasFloor") ~= true or call(square, "getDoorTo", inside) ~= nil then return nil end
    local insidePose = standablePose(U, x, y, bit, room, true)
    local outsidePose = standablePose(U, x, y, bit, nil, false)
    if not insidePose or not outsidePose then return nil end
    return { x = x, y = y, z = 0, bit = bit, square = square,
        name = bit == 1 and "south" or "east", roomName = tostring(call(room, "getName")),
        windowSection = call(square, "getWindowTo", inside) ~= nil,
        inside = insidePose, outside = outsidePose }
end

local function chooseWall(candidates, bit, requireKitchen)
    local kitchenOpaque, kitchenWindow, otherOpaque, otherWindow
    for _, wall in ipairs(candidates) do
        if wall.bit == bit then
            local kitchen = string.find(string.lower(wall.roomName), "kitchen", 1, true) ~= nil
            if kitchen and wall.windowSection then kitchenWindow = kitchenWindow or wall
            elseif kitchen then kitchenOpaque = kitchenOpaque or wall
            elseif wall.windowSection then otherWindow = otherWindow or wall
            else otherOpaque = otherOpaque or wall end
        end
    end
    return kitchenOpaque or kitchenWindow or (not requireKitchen and (otherOpaque or otherWindow) or nil)
end

local function capture(H, fixture, label, screenshot)
    local rows = {}
    for _, wall in ipairs(fixture.walls or {}) do
        local flags = call(wall.square, "getPlayerCutawayFlag", 0,
            type(getTimestampMs) == "function" and getTimestampMs() or 0)
        local ok, native = pcall(SCSplitScreenProbe.debugPrimaryCutawaySample,
            wall.x, wall.y, wall.z)
        rows[#rows + 1] = wall.name .. "=" .. tostring(flags)
            .. ";" .. tostring(ok and native or "native_sample_failed")
    end
    local detail = table.concat(rows, " // ")
    print("SC_REAL_SANDBOX|VIEW_CUTAWAY|" .. label .. "|render="
        .. fixture.frames .. "|" .. detail)
    -- Keep full bounded native diagnostics in a separate journal: the ordinary
    -- harness result formatter intentionally clips individual details.
    local writer = type(getFileWriter) == "function"
        and getFileWriter("SurvivorCompanionHarness/view-cutaway.log", true, true) or nil
    if writer then
        writer:writeln(label .. "|render=" .. fixture.frames .. "|" .. detail)
        writer:close()
    end
    if screenshot then
        local name = tostring(H.config.run_id) .. "-view-cutaway-" .. label .. ".png"
        local taken, why = pcall(function() getCore():TakeFullScreenshot(name) end)
        return taken, name .. " queued; file/pixels require review; " .. tostring(why)
    end
    return true, detail
end

local function cleanup(fixture)
    local SC = SurvivorCompanion
    if fixture.postRender and Events.OnPostRender then
        Events.OnPostRender.Remove(fixture.postRender)
    end
    if fixture.stockPoll and Events.OnPostRender then
        Events.OnPostRender.Remove(fixture.stockPoll)
    end
    if fixture.originalDecision then SC.Decision.update = fixture.originalDecision end
    if fixture.originalReleased then SC.ViewSession.released = fixture.originalReleased end
    Probe.active = nil
end

local function finish(H, fixture, check, result, setPhase, current)
    cleanup(fixture)
    if not fixture.stockDone then
        result("SKIP", "view_cutaway_stock_actor_comparator", "custom stock-actor teardown not completed")
    end
    result("SKIP", "view_cutaway_pixel_review_required",
        "native flags are automatic evidence; inspect baseline and post-close PNGs before visual acceptance")
    setPhase("finish", current)
end

local function startRoute(H, fixture, baseline)
    fixture.route, fixture.routeIndex = {}, 1
    for _, wall in ipairs(fixture.walls) do
        for _, side in ipairs({ "outside", "inside", "outside" }) do
            fixture.route[#fixture.route + 1] = { wall = wall, side = side }
        end
    end
    fixture.baselineRoute = baseline
    fixture.poseStarted = nil
end

local function stepRoute(H, fixture, check, result, setPhase, current)
    local leg = fixture.route[fixture.routeIndex]
    if not leg then return true end
    if not fixture.poseStarted then
        if not check("view_cutaway_place_" .. leg.wall.name .. "_" .. leg.side,
            place(H.player, leg.wall[leg.side]), "loaded fixed wall position") then return false, "failed" end
        fixture.poseStarted, fixture.poseAt = fixture.frames, current
        return false
    end
    if fixture.frames - fixture.poseStarted < 60 or current - fixture.poseAt < 1000 then return false end
    local wall = leg.wall
    local flags = call(wall.square, "getPlayerCutawayFlag", 0, getTimestampMs())
    local hidden = hasBit(flags, wall.bit)
    local label = (fixture.baselineRoute and "baseline" or fixture.mode .. "_" .. fixture.cycle)
        .. "_" .. wall.name .. "_" .. leg.side .. "_" .. fixture.routeIndex
    local took, detail = capture(H, fixture, label, true)
    check("view_cutaway_capture_" .. label, took, detail)
    if fixture.baselineRoute then
        wall.baseline = wall.baseline or {}
        wall.baseline[#wall.baseline + 1] = hidden
    else
        check("view_cutaway_matches_baseline_" .. label,
            hidden == (leg.side == "inside"), "flags=" .. tostring(flags)
                .. " bit=" .. wall.bit .. " hidden=" .. tostring(hidden))
    end
    fixture.routeIndex, fixture.poseStarted = fixture.routeIndex + 1, nil
    return false
end

local function setup(H, SC, check, result, setPhase, current)
    local records, base = SC.Registry.records(), SC.BaseLife.active()
    if (not base or #records == 0) and current - H.phaseStartedAt < 15000 then return end
    if not check("view_cutaway_ready", base ~= nil and #records >= 1
        and getSpecificPlayer(1) == nil and SC.ViewSession.owner() == nil,
        "fresh solo cloned-save world required") then setPhase("finish", current) return end
    local mode = H.config.view_cutaway_restore_mode or "observe"
    local ok, selected = pcall(SCSplitScreenProbe.debugSetPrimaryViewRestoreMode, mode)
    if not check("view_cutaway_restore_mode", ok and selected == true,
        "mode=" .. mode .. "; native debug mode requires -debug") then setPhase("finish", current) return end
    local fixture = { frames = 0, cycle = 1, mode = "base_watch", walls = {},
        home = point(H.player), base = base, records = {}, candidates = {},
        cycles = math.max(1, math.min(3, tonumber(H.config.view_cutaway_cycles) or 3)),
        scanIndex = 0, scanRadius = 64, restoreMode = mode, leaders = {}, recordById = {}, rooms = {} }
    local world = type(getWorld) == "function" and getWorld() or nil
    local map = call(call(world, "getCell"), "getChunkMap", 0)
    fixture.primaryBounds = { minX = call(map, "getWorldXMinTiles"),
        minY = call(map, "getWorldYMinTiles"), maxX = call(map, "getWorldXMaxTiles"),
        maxY = call(map, "getWorldYMaxTiles") }
    for _, record in ipairs(records) do
        if record.actor and call(record.actor, "isDead") == false then
            -- Runtime retirement mutates Registry records in place. Keep the
            -- original native object so a lost actor cannot turn into nil SQL
            -- sentinels or make the next lifecycle operate on a replacement.
            local original = { id = record.id, actor = record.actor }
            fixture.records[#fixture.records + 1] = original
            fixture.recordById[record.id] = original
        end
    end
    local candidates = SC.BaseWatch.candidates()
    for _, candidate in ipairs(candidates or {}) do
        local at = point(candidate.actor)
        local gap = (at.x - fixture.home.x)^2 + (at.y - fixture.home.y)^2
        local job = SC.BaseLife.jobFor and SC.BaseLife.jobFor(candidate.id)
        if gap <= 144 and (not job or not SC.BaseLife.outdoorJob(job)) then
            fixture.leaders[#fixture.leaders + 1] = {
                record = fixture.recordById[candidate.id], home = at }
        end
    end
    fixture.leader = fixture.leaders[1] and fixture.leaders[1].record
    if not check("view_cutaway_living_leaders", #fixture.leaders >= 2,
        "at least two indoor camp residents within twelve tiles; found=" .. #fixture.leaders) then
        setPhase("finish", current) return
    end
    fixture.postRender = function()
        fixture.frames = fixture.frames + 1
        if not fixture.soloSampling or not fixture.closedAt then return end
        local elapsed = fixture.frames - fixture.closedAt
        for _, frame in ipairs({ 1, 2, 3, 60, 300 }) do
            if elapsed == frame then
                local suffix = fixture.mode .. "_" .. fixture.cycle .. "_" .. frame
                fixture.sampled[frame] = true
                local retained, reason = retainedIdentity(SC, fixture)
                if not retained then
                    fixture.identityLost = true
                    if not fixture.identityReported then
                        fixture.identityReported = true
                        check("view_cutaway_retained_actor_identity_" .. suffix, false, reason)
                    end
                end
                capture(H, fixture, "solo_" .. suffix, frame == 2 or frame == 300)
                check("view_cutaway_solo_owner_" .. suffix,
                    getSpecificPlayer(0) == H.player and getSpecificPlayer(1) == nil
                        and IsoPlayer.getInstance() == H.player and SCSplitScreenProbe.isReleased() == true,
                    SCSplitScreenProbe.releaseDiagnostics())
                if frame == 2 then
                    local wall = fixture.holdWall
                    local flags = call(wall.square, "getPlayerCutawayFlag", 0, getTimestampMs())
                    check("view_cutaway_hidden_without_moving_frame_two_" .. suffix,
                        hasBit(flags, wall.bit), "flags=" .. tostring(flags) .. " bit=" .. wall.bit)
                end
                if fixture.mode == "stock_custom" and frame >= 2 then
                    local identities, detail = sameSql(H, fixture)
                    check("view_cutaway_CUSTOM_stock_sql_" .. suffix, identities, detail)
                    check("view_cutaway_CUSTOM_stock_actor_removed_" .. suffix,
                        call(fixture.stockActor, "isExistInTheWorld") == false
                            and SC.ViewSession.owner() == nil,
                        "removed only tracked stock actor; ViewSession never owned the comparator")
                    if frame == 300 then
                        check("view_cutaway_CUSTOM_stock_restore_polled_" .. suffix,
                            fixture.stockRestoreStatus == "applied",
                            "status=" .. tostring(fixture.stockRestoreStatus))
                    end
                end
                if frame >= 60 then
                    for _, record in ipairs(fixture.records) do
                        local good, detail = healthy(record.actor, fixture.beforeCounts[record.id])
                        check("view_cutaway_living_updates_" .. suffix .. "_" .. record.id, good, detail)
                    end
                end
            end
        end
    end
    if not check("view_cutaway_post_render_event", Events.OnPostRender ~= nil,
        "completed GL frames, not just tick calls, are required") then setPhase("finish", current) return end
    Events.OnPostRender.Add(fixture.postRender)
    fixture.originalDecision = SC.Decision.update
    SC.Decision.update = function(actor, ...)
        for _, record in ipairs(fixture.records) do
            if actor == record.actor then return true, "view_cutaway_fixture_hold" end
        end
        return fixture.originalDecision(actor, ...)
    end
    fixture.originalReleased = SC.ViewSession.released
    SC.ViewSession.released = function(mode, ...)
        local owner = SC.ViewSession.owner()
        local session = mode == "base_watch" and SC.BaseWatch.current()
            or mode == "expedition" and SC.ExpeditionPrototype.current() or nil
        local releasingLeader = session and (session.leaderActor
            or session.leader and session.leader.actor) or nil
        fixture.beforeCounts = {}
        for _, record in ipairs(fixture.records) do fixture.beforeCounts[record.id] = updateCount(record.actor) end
        capture(H, fixture, "native_close_" .. fixture.mode .. "_" .. fixture.cycle)
        local accepted, why = fixture.originalReleased(mode, ...)
        capture(H, fixture, "lua_ui_close_" .. fixture.mode .. "_" .. fixture.cycle)
        fixture.releaseObserved = releaseReceipt(fixture, mode, owner, releasingLeader,
            accepted, getSpecificPlayer(1) == nil, SCSplitScreenProbe.isReleased(),
            call(releasingLeader, "isDead") == false)
        fixture.closedAt = fixture.frames
        fixture.soloSampling = fixture.releaseObserved.valid
        return accepted, why
    end
    Probe.active, H.viewCutaway = fixture, fixture
    pcall(function() getGameTime():setTimeOfDay(12.0) end)
    result("PASS", "view_cutaway_actor_fixture", "leader=" .. fixture.leader.id
        .. " retained_actors=" .. #fixture.records .. " restore=" .. mode)
    setPhase("view_cutaway_discover", current)
end

local function discover(H, fixture, SC, check, result, setPhase, current)
    local U, radius = SC.GameplayUtil, fixture.scanRadius
    local width = radius * 2 + 1
    for _ = 1, 100 do
        if fixture.scanIndex >= width * width then break end
        local index = fixture.scanIndex
        fixture.scanIndex = index + 1
        local x = math.floor(fixture.home.x) + index % width - radius
        local y = math.floor(fixture.home.y) + math.floor(index / width) - radius
        local bounds = fixture.primaryBounds
        local primaryOwns = bounds.minX and bounds.minY and bounds.maxX and bounds.maxY
            and x >= bounds.minX and x <= bounds.maxX and y >= bounds.minY and y <= bounds.maxY
        for _, z in ipairs({ 0, 1 }) do
            local remote = U.gridSquare(x, y, z)
            local room = call(remote, "getRoom")
            if room ~= nil then
                local info = fixture.rooms[room]
                if not info then
                    info = { name = tostring(call(room, "getName")), z = z,
                        minX = x, maxX = x, minY = y, maxY = y,
                        gap = (x - fixture.home.x)^2 + (y - fixture.home.y)^2 }
                    fixture.rooms[room] = info
                end
                info.minX, info.maxX = math.min(info.minX, x), math.max(info.maxX, x)
                info.minY, info.maxY = math.min(info.minY, y), math.max(info.maxY, y)
            end
            local oldFallbackArea = math.abs(x - fixture.home.x) <= 28
                and math.abs(y - fixture.home.y) <= 28
            if primaryOwns and (z == 1 or oldFallbackArea)
                and safeFloor(remote) and room ~= nil
                and (x - fixture.home.x)^2 + (y - fixture.home.y)^2 >= 64 then
                local at = { x = x + 0.5, y = y + 0.5, z = z,
                    gap = (x + 0.5 - fixture.home.x)^2 + (y + 0.5 - fixture.home.y)^2 }
                fixture.remote = preferRemote(fixture.remote, at)
            end
        end
        for _, bit in ipairs({ 1, 2 }) do
            local wall = wallAt(U, x, y, bit)
            if wall and SC.BaseLife.isInside(wall.inside) == true then
                wall.gap = (wall.inside.x - fixture.home.x)^2 + (wall.inside.y - fixture.home.y)^2
                fixture.candidates[#fixture.candidates + 1] = wall
            end
        end
    end
    if fixture.scanIndex < width * width then return end
    table.sort(fixture.candidates, function(a, b)
        if a.gap ~= b.gap then return a.gap < b.gap end
        if a.x ~= b.x then return a.x < b.x end
        return a.y < b.y
    end)
    local rooms = {}
    for _, room in pairs(fixture.rooms) do rooms[#rooms + 1] = room end
    table.sort(rooms, function(a, b) return a.gap < b.gap end)
    for index = 1, math.min(#rooms, 64) do
        local room = rooms[index]
        print("SC_REAL_SANDBOX|VIEW_ROOM|name=" .. room.name .. ";z=" .. room.z
            .. ";loadedBounds=" .. room.minX .. "," .. room.minY .. ":" .. room.maxX .. "," .. room.maxY)
    end
    for _, bit in ipairs({ 1, 2 }) do
        local chosen = chooseWall(fixture.candidates, bit, bit == 1)
        if chosen then fixture.walls[#fixture.walls + 1] = chosen end
    end
    if not check("view_cutaway_fixed_kitchen_south_wall", #fixture.walls == 2
        and fixture.walls[1].bit == 1 and string.find(string.lower(fixture.walls[1].roomName), "kitchen", 1, true) ~= nil
        and fixture.remote ~= nil,
        "require native room name kitchen; candidates=" .. #fixture.candidates
            .. " rooms=" .. #rooms .. " remote_room=" .. tostring(fixture.remote ~= nil)) then
        cleanup(fixture); setPhase("finish", current) return
    end
    result(fixture.remote.z == 1 and "PASS" or "SKIP", "view_cutaway_upper_floor_fixture",
        "remote=" .. fixture.remote.x .. "," .. fixture.remote.y .. "," .. fixture.remote.z
            .. " distance=" .. string.format("%.1f", math.sqrt(fixture.remote.gap))
            .. (fixture.remote.z == 1 and "; farthest loaded upper room within primary map"
                or "; no loaded upper room in radius64; same-floor fallback only"))
    for _, wall in ipairs(fixture.walls) do
        result("PASS", "view_cutaway_wall_" .. wall.name,
            "room=" .. wall.roomName .. " section=" .. (wall.windowSection and "window_wall" or "opaque_wall")
                .. " owner=" .. wall.x .. "," .. wall.y .. ",0 bit=" .. wall.bit
                .. " inside=" .. wall.inside.x .. "," .. wall.inside.y
                .. " outside=" .. wall.outside.x .. "," .. wall.outside.y)
    end
    startRoute(H, fixture, true)
    setPhase("view_cutaway_baseline", current)
end

-- Opt-in fast lifecycle control. It never stages actors or holds Decision;
-- use one ordinary resident and the public BaseWatch join/close operations.
local function quickHelpers()
    local probes = SCRealSandboxHarnessProbes
    local wood = probes and probes.SCWoodExpeditionProbe
    if not wood then
        pcall(require, "SCWoodExpeditionProbe")
        wood = SCRealSandboxHarnessProbes and SCRealSandboxHarnessProbes.SCWoodExpeditionProbe
    end
    return wood and wood._tests
end
local function quickNative(at)
    if not at or SCSplitScreenProbe == nil or type(SCSplitScreenProbe.debugPrimaryCutawaySample) ~= "function" then
        return "sample=unavailable"
    end
    local okay, detail = pcall(SCSplitScreenProbe.debugPrimaryCutawaySample,
        math.floor(at.x), math.floor(at.y), math.floor(at.z))
    return okay and tostring(detail) or "sample=failed:" .. tostring(detail)
end
local function quickOwnFact(value)
    return { counter = tonumber(value:match("visibilityNativeCounter0=(%-?%d+)")),
        rawCounter = tonumber(value:match("lightingRawCounter0=(%-?%d+)")),
        canSee = value:match("visibilityRawCanSee=([a-z]+)") == "true",
        couldSee = value:match("visibilityRawCouldSee=([a-z]+)") == "true", detail = value }
end
local function quickCapture(H, fixture, label, png)
    local primary = point(H.player)
    local room = call(call(H.player, "getCurrentSquare"), "getRoom")
    local own = quickNative(primary)
    local detail = label .. "|phase=" .. tostring(H.phase) .. "|frames=" .. fixture.frames
        .. "|primary=" .. tostring(primary.x) .. "," .. tostring(primary.y) .. "," .. tostring(primary.z)
        .. "|room=" .. tostring(call(room, "getName")) .. "|own{" .. own .. "}|kitchen{"
        .. quickNative({ x = 12035, y = 6746, z = 0 }) .. "}|adjacentKitchen{"
        .. quickNative(fixture.adjacentKitchen) .. "}"
    print("SC_REAL_SANDBOX|VIEW_QUICK|" .. detail)
    local writer = type(getFileWriter) == "function"
        and getFileWriter("SurvivorCompanionHarness/view-cutaway-quick.log", true, true)
    if writer then writer:writeln(detail); writer:close() end
    if png then
        pcall(function() getCore():TakeFullScreenshot(tostring(H.config.run_id)
            .. "-view-quick-" .. label .. ".png") end)
        if fixture.helpers then fixture.helpers.captureVisibility(SurvivorCompanion, fixture, "quick-" .. label) end
    end
    return quickOwnFact(own)
end
local function quickCarPose(primary, walk)
    local at = point(primary)
    return at.x and at.y and math.floor(at.z or -1) == 0 and math.abs(at.x - walk.target.x) <= 0.6
        and math.abs(at.y - walk.target.y) <= 0.6 and call(call(primary, "getCurrentSquare"), "getRoom") == nil
end
local function quickStartCarWalk(H, fixture, current, result)
    local U, target = SurvivorCompanion.GameplayUtil, nil
    for _, offset in ipairs({ { 0, 0 }, { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 },
            { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 } }) do
        local x, y = 12035 + offset[1], 6753 + offset[2]
        local square = U.gridSquare(x, y, 0)
        if safeFloor(square) and call(square, "getRoom") == nil then target = { x = x + 0.5, y = y + 0.5, z = 0 } break end
    end
    if not target then return false, "no verified standable outdoor point in9 squares near12035.5,6753.5" end
    local okay, action = pcall(ISPathFindAction.pathToLocationF, ISPathFindAction,
        H.player, target.x, target.y, target.z)
    if not okay or not action then return false, "ordinary outdoor path construction failed" end
    local walk = { active = true, action = action, target = target, stage = "walking", startedAt = current, frames = 0 }
    fixture.carWalk = walk
    if type(ISTimedActionQueue.getTimedActionQueue) == "function" then walk.queue = ISTimedActionQueue.getTimedActionQueue(H.player) end
    action:setOnComplete(function() if walk.active then walk.pathComplete = true end end)
    action:setOnFail(function() if walk.active then walk.pathFailed = true end end)
    quickCapture(H, fixture, "car-before-walk", true)
    local queued, failure = pcall(ISTimedActionQueue.add, action)
    if not queued then return false, tostring(failure) end
    result("PASS", "view_quick_car_walk_queued", "normal native path to verified outdoor point="
        .. target.x .. "," .. target.y .. ",0; no camera, visibility or parked-car changes")
    return true
end
local function quickObserveCar(H, fixture, result, now)
    local walk = fixture.carWalk
    if not walk or not walk.active or walk.stage ~= "observing" or walk.done then return end
    if not quickCarPose(H.player, walk) then walk.poseLost = true return end
    walk.frames = walk.frames + 1
    if walk.frames == 2 or walk.frames == 12 or walk.frames == 120 then
        quickCapture(H, fixture, "car-frame" .. walk.frames, true)
    end
    if walk.frames >= 120 and now - walk.arrivedAt >= 1500 then
        local after = quickCapture(H, fixture, "car-settled", true)
        result(after.canSee and after.couldSee and "PASS" or "FAIL", "view_quick_primary_own_visibility_at_car",
            "normal player walk back outdoors; own raw can/couldSee=" .. tostring(after.canSee) .. "/" .. tostring(after.couldSee))
        local progressed = after.counter and fixture.afterKitchen.counter and after.counter > fixture.afterKitchen.counter
        result(progressed and "PASS" or "FAIL", "view_quick_primary_counter_at_car",
            "Java counter kitchen/outdoor=" .. tostring(fixture.afterKitchen.counter) .. "/" .. tostring(after.counter)
                .. ";raw=" .. tostring(fixture.afterKitchen.rawCounter) .. "/" .. tostring(after.rawCounter))
        walk.done = true
    end
end
local function quickCleanupCar(fixture, failed)
    local walk = fixture.carWalk
    if not walk then return end
    walk.active = false
    if failed and walk.action and not walk.pathComplete then
        if walk.action.action then call(walk.action, "forceStop") end
        if walk.queue then call(walk.queue, "removeFromQueue", walk.action) end
    end
end
local function quickCleanup(fixture, failed)
    local SC = SurvivorCompanion
    if fixture.postRender and Events and Events.OnPostRender then Events.OnPostRender.Remove(fixture.postRender) end
    if fixture.helpers then fixture.helpers.cleanupKitchen(fixture, failed) end
    quickCleanupCar(fixture, failed)
    local watch = SC.BaseWatch.current()
    if failed and watch and watch.leaderActor == fixture.leader.actor then
        pcall(SC.BaseWatch.cancelBeforeDeparture)
    end
    fixture.active = false
    Probe.active = nil
end
local function quickFail(H, fixture, current, result, setPhase, name, detail)
    quickCapture(H, fixture, "failed-" .. name, true)
    quickCleanup(fixture, true)
    result("FAIL", name, detail)
    setPhase("finish", current)
end
local function quickSetup(H, current, check, result, setPhase)
    local SC, helpers = SurvivorCompanion, quickHelpers()
    if (not SC.BaseLife.active() or #SC.Registry.records() == 0) and current - H.phaseStartedAt < 15000 then return end
    if not check("view_quick_helpers", helpers ~= nil, "existing physical kitchen route/visibility helpers") then setPhase("finish", current) return end
    if not check("view_quick_no_prior_session", SC.BaseWatch.current() == nil
        and SC.ExpeditionPrototype.current() == nil and SC.ViewSession.owner() == nil and getSpecificPlayer(1) == nil,
        "fresh solo world; never reset another view") then setPhase("finish", current) return end
    local leader
    for _, candidate in ipairs(SC.BaseWatch.candidates() or {}) do
        if candidate.actor and helpers.healthy(candidate.actor) and SC.BaseLife.isInside(candidate.actor) then
            leader = { id = candidate.id, actor = candidate.actor }
            break
        end
    end
    if leader == nil and current - H.phaseStartedAt < 90000 then return end
    if not check("view_quick_real_resident", leader ~= nil,
        "requires one actually healthy public BaseWatch candidate at camp; no placement, health or AI changes") then setPhase("finish", current) return end
    local home = point(H.player)
    local room = call(SC.GameplayUtil.gridSquare(12035, 6746, 0), "getRoom")
    local roomName, adjacent = call(room, "getName"), nil
    if type(roomName) == "string" and string.find(string.lower(roomName), "kitchen", 1, true) then
        for _, offset in ipairs({ { 0, -1 }, { 1, 0 }, { -1, 0 }, { 0, 1 } }) do
            local x, y = 12035 + offset[1], 6746 + offset[2]
            if call(SC.GameplayUtil.gridSquare(x, y, 0), "getRoom") == room then adjacent = { x = x, y = y, z = 0 } break end
        end
    end
    if not check("view_quick_two_positions", home.x and home.y and home.z == 0
        and (home.x - 12035.5)^2 + (home.y - 6746.5)^2 >= 1 and adjacent ~= nil,
        "initial primary point must differ from verified kitchen by>=1tile; same-room adjacent square required") then setPhase("finish", current) return end
    local mode = H.config.view_cutaway_restore_mode or "B"
    local selected, accepted = pcall(SCSplitScreenProbe.debugSetPrimaryViewRestoreMode, mode)
    if not check("view_quick_restore_mode", selected and accepted == true, "mode=" .. mode) then setPhase("finish", current) return end
    local fixture = { quick = true, active = true, mode = "quick-base-watch", primary = H.player,
        leader = leader, crew = { leader }, helpers = helpers, home = home, adjacentKitchen = adjacent,
        frames = 0, startedAt = current, baselineAt = current, baselineFrame = 0, latestStepAt = current }
    H.viewCutaway, Probe.active = fixture, fixture
    helpers.snapshotVisibility(SC, fixture, H.player)
    fixture.before = quickCapture(H, fixture, "before-watch", true)
    fixture.postRender = function()
        if not fixture.active then return end
        fixture.frames = fixture.frames + 1
        local now = type(getTimestampMs) == "function" and getTimestampMs() or fixture.latestStepAt
        helpers.observeWitnessMovement(fixture)
        if fixture.closedAt then helpers.observeSoloVisibility(H, fixture, result, now) end
        helpers.observeKitchen(H, fixture, result)
        quickObserveCar(H, fixture, result, now)
        if now >= (fixture.nextStateSampleAt or 0) then
            fixture.nextStateSampleAt = now + 1000
            quickCapture(H, fixture, "state-" .. tostring(H.phase), false)
        end
    end
    Events.OnPostRender.Add(fixture.postRender)
    setPhase("view_cutaway_quick_baseline", current)
end
local function quickTryWatch(H, fixture, current, result, setPhase)
    if fixture.watchAccepted then return true end
    if current - fixture.watchStartAt >= 90000 then
        quickFail(H, fixture, current, result, setPhase, "view_quick_available_resident_deadline",
            "90s waiting for ordinary public watch eligibility;last=" .. tostring(fixture.lastStartReason)
                .. ";no resident job or position changed")
        return false
    end
    if current < (fixture.nextWatchAttemptAt or 0) then return false end
    fixture.nextWatchAttemptAt = current + 1000
    local SC, candidates = SurvivorCompanion, SurvivorCompanion.BaseWatch.candidates() or {}
    local count = #candidates
    local offset = fixture.watchCandidateOffset or 0
    local attempted = 0
    for index = 1, math.min(count, 8) do
        local candidate = candidates[(offset + index - 1) % count + 1]
        if candidate.actor and fixture.helpers.healthy(candidate.actor) and SC.BaseLife.isInside(candidate.actor) then
            attempted = attempted + 1
            local started, reason = SC.BaseWatch.start(candidate.id)
            if started then
                fixture.leader = { id = candidate.id, actor = candidate.actor }
                fixture.crew = { fixture.leader }
                local found = false
                for _, member in ipairs(fixture.visibility and fixture.visibility.actors or {}) do
                    member.group = member.id == candidate.id and "crew" or "home"
                    if member.id == candidate.id then found = true end
                end
                if fixture.visibility and not found then
                    fixture.visibility.actors[#fixture.visibility.actors + 1] = {
                        id = candidate.id, actor = candidate.actor, group = "crew" }
                end
                fixture.watchAccepted = true
                fixture.dispatchedAt, fixture.openAt = current, current
                result("PASS", "view_quick_public_watch_start", "exact eligible saved resident=" .. candidate.id
                    .. ";waitMs=" .. (current - fixture.watchStartAt) .. ";normal public start; no work cancellation")
                setPhase("view_cutaway_quick_join", current)
                return true
            end
            fixture.lastStartReason = reason
            if reason ~= "leader_finishing_outdoor_work" and reason ~= "base_watch_leader_unavailable" then
                quickFail(H, fixture, current, result, setPhase, "view_quick_public_watch_start", tostring(reason))
                return false
            end
        end
    end
    fixture.watchCandidateOffset = count > 0 and (offset + math.min(count, 8)) % count or 0
    if attempted == 0 then fixture.lastStartReason = "waiting_for_healthy_indoor_resident" end
    quickCapture(H, fixture, "watch-start-wait-" .. tostring(fixture.lastStartReason), false)
    return false
end
local function quickStep(H, current, check, result, setPhase)
    if H.phase == "view_cutaway_setup" then return quickSetup(H, current, check, result, setPhase) end
    local SC, fixture = SurvivorCompanion, H.viewCutaway
    if not fixture or not fixture.quick then result("FAIL", "view_quick_fixture", "missing quick fixture") setPhase("finish", current) return end
    fixture.latestStepAt = current
    if current - fixture.startedAt > 180000 then return quickFail(H, fixture, current, result, setPhase,
        "view_quick_deadline", "180s total bound; no view reset, actor relocation or native state forcing") end
    if H.phase == "view_cutaway_quick_baseline" then
        if current - fixture.baselineAt < 1500 or fixture.frames < 12 then return end
        local before = quickCapture(H, fixture, "before-watch-settled", true)
        if not check("view_quick_baseline_primary_visibility", before.canSee and before.couldSee
            and before.counter ~= nil and fixture.before.counter ~= nil and before.counter > fixture.before.counter,
            "primary own raw can/couldSee=true and native cached counter progresses before opening view") then
            return quickFail(H, fixture, current, result, setPhase, "view_quick_invalid_baseline", before.detail)
        end
        fixture.before = before
        fixture.watchStartAt = current
        setPhase("view_cutaway_quick_start", current)
        quickTryWatch(H, fixture, current, result, setPhase)
    elseif H.phase == "view_cutaway_quick_start" then
        quickTryWatch(H, fixture, current, result, setPhase)
    elseif H.phase == "view_cutaway_quick_join" then
        if getSpecificPlayer(1) == fixture.leader.actor then
            fixture.joinedAt, fixture.joinedFrame = fixture.joinedAt or current, fixture.joinedFrame or fixture.frames
            if current - fixture.joinedAt >= 1500 and fixture.frames - fixture.joinedFrame >= 12 then
                quickCapture(H, fixture, "watch-joined", true)
                setPhase("view_cutaway_quick_close", current)
            end
        elseif current - fixture.openAt > 30000 then return quickFail(H, fixture, current, result, setPhase,
            "view_quick_join_deadline", "public BaseWatch did not join within30s") end
    elseif H.phase == "view_cutaway_quick_close" then
        local closed, reason = SC.BaseWatch.cancelBeforeDeparture()
        if not closed then
            if current - H.phaseStartedAt > 30000 then return quickFail(H, fixture, current, result, setPhase,
                "view_quick_public_watch_close", tostring(reason)) end
            return
        end
        fixture.closedAt = current
        fixture.afterClose = quickCapture(H, fixture, "watch-closed", true)
        setPhase("view_cutaway_quick_solo", current)
    elseif H.phase == "view_cutaway_quick_solo" then
        if not fixture.visibility.done then
            if current - fixture.closedAt > 30000 then return quickFail(H, fixture, current, result, setPhase,
                "view_quick_primary_restore", "solo restore did not settle within30s") end
            return
        end
        quickCapture(H, fixture, "solo-restored", true)
        local started, reason = fixture.helpers.startKitchenRoute(H, fixture, current, result)
        if not started then return quickFail(H, fixture, current, result, setPhase, "view_quick_kitchen_route", tostring(reason)) end
        setPhase("view_cutaway_quick_kitchen_walk", current)
    elseif H.phase == "view_cutaway_quick_kitchen_walk" then
        local kitchen = fixture.kitchen
        if kitchen.pathFailed or current - kitchen.startedAt > 90000 then return quickFail(H, fixture, current, result, setPhase,
            "view_quick_kitchen_walk", "ordinary native player path failed or exceeded90s") end
        if kitchen.pathComplete then
            if not fixture.helpers.kitchenPose(H.player, kitchen) then return quickFail(H, fixture, current, result, setPhase,
                "view_quick_kitchen_pose", "native callback did not leave the same primary at the verified kitchen point") end
            kitchen.stage, kitchen.arrivedAt = "observing", current
            setPhase("view_cutaway_quick_kitchen_capture", current)
        end
    elseif H.phase == "view_cutaway_quick_kitchen_capture" then
        local kitchen = fixture.kitchen
        if kitchen.poseLost or current - kitchen.arrivedAt > 30000 then return quickFail(H, fixture, current, result, setPhase,
            "view_quick_kitchen_observation", "actual pose lost or120frames+1500ms not completed within30s") end
        if not kitchen.done then return end
        local after = quickCapture(H, fixture, "kitchen-after-watch", true)
        check("view_quick_primary_own_visibility_after_walk", after.canSee and after.couldSee,
            "same native primary0 moved normally to distinct verified kitchen; own raw can/couldSee must remaintrue")
        check("view_quick_primary_counter_after_walk", after.counter and fixture.afterClose.counter
            and after.counter > fixture.afterClose.counter,
            "Java published counter before/after ordinary walk=" .. tostring(fixture.afterClose.counter) .. "/" .. tostring(after.counter)
                .. ";native raw before/after=" .. tostring(fixture.afterClose.rawCounter) .. "/" .. tostring(after.rawCounter))
        fixture.afterKitchen = after
        fixture.helpers.cleanupKitchen(fixture, false)
        local started, reason = quickStartCarWalk(H, fixture, current, result)
        if not started then return quickFail(H, fixture, current, result, setPhase, "view_quick_car_route", reason) end
        setPhase("view_cutaway_quick_car_walk", current)
    elseif H.phase == "view_cutaway_quick_car_walk" then
        local walk = fixture.carWalk
        if walk.pathFailed or current - walk.startedAt > 90000 then return quickFail(H, fixture, current, result, setPhase,
            "view_quick_car_walk", "ordinary native outdoor path failed or exceeded90s") end
        if walk.pathComplete then
            if not quickCarPose(H.player, walk) then return quickFail(H, fixture, current, result, setPhase,
                "view_quick_car_pose", "native completion did not reach the verified outdoor target") end
            walk.stage, walk.arrivedAt = "observing", current
            setPhase("view_cutaway_quick_car_capture", current)
        end
    elseif H.phase == "view_cutaway_quick_car_capture" then
        local walk = fixture.carWalk
        if walk.poseLost or current - walk.arrivedAt > 30000 then return quickFail(H, fixture, current, result, setPhase,
            "view_quick_car_observation", "outdoor pose lost or120frames+1500ms not completed within30s") end
        if not walk.done then return end
        quickCleanup(fixture, false)
        result("SKIP", "view_quick_pixel_review", "inspect quick before/join/closed/kitchen/car PNGs; failed flags/counters remain reported")
        setPhase("finish", current)
    end
end

function Probe.step(H, current, check, result, setPhase)
    if H.config.view_cutaway_quick_watch == "true" then return quickStep(H, current, check, result, setPhase) end
    local SC = SurvivorCompanion
    if H.phase == "view_cutaway_setup" then return setup(H, SC, check, result, setPhase, current) end
    local fixture = H.viewCutaway
    if not fixture then result("FAIL", "view_cutaway_fixture_lost", H.phase); setPhase("finish", current) return end
    if current - H.phaseStartedAt > 45000 then
        result("FAIL", "view_cutaway_phase_timeout", H.phase)
        cleanup(fixture); setPhase("finish", current) return
    end
    local transition = releaseTransition(fixture, H.phase, getSpecificPlayer(1),
        SCSplitScreenProbe.isReleased(), fixture.leader ~= nil
            and SCSplitScreenProbe.isLeader(fixture.leader.actor) == true)
    if transition == "solo" then
        check("view_cutaway_observed_normal_close_" .. fixture.mode .. "_" .. fixture.cycle,
            true, "exact owned leader released normally during " .. H.phase .. "; no second finish request")
        setPhase("view_cutaway_solo", current)
        return
    elseif transition ~= nil then
        result("FAIL", "view_cutaway_" .. transition,
            "phase=" .. H.phase .. "; vanished slot is valid only with matching ViewSession release receipt")
        cleanup(fixture); setPhase("finish", current) return
    end
    if H.phase == "view_cutaway_discover" then
        return discover(H, fixture, SC, check, result, setPhase, current)
    elseif H.phase == "view_cutaway_baseline" or H.phase == "view_cutaway_walk" then
        local done, failure = stepRoute(H, fixture, check, result, setPhase, current)
        if failure then cleanup(fixture); setPhase("finish", current) return end
        if not done then return end
        if fixture.baselineRoute then
            local valid = true
            for _, wall in ipairs(fixture.walls) do
                valid = check("view_cutaway_baseline_toggle_" .. wall.name,
                    wall.baseline[1] == false and wall.baseline[2] == true
                        and wall.baseline[3] == false,
                    "outside/inside/outside=" .. tostring(wall.baseline[1]) .. "/"
                        .. tostring(wall.baseline[2]) .. "/" .. tostring(wall.baseline[3])) and valid
            end
            if not valid then cleanup(fixture); setPhase("finish", current) return end
            fixture.stockIndex = 1
            setPhase("view_cutaway_stock_open", current)
            return
        elseif fixture.mode == "stock_custom" then
            if fixture.stockIndex < #fixture.walls then
                fixture.stockIndex = fixture.stockIndex + 1
                setPhase("view_cutaway_stock_open", current)
                return
            end
            fixture.stockDone = true
            result("PASS", "view_cutaway_CUSTOM_stock_actor_comparator",
                "plain IsoPlayer stock AddCoopPlayer joins; explicit custom teardown, not a stock leave API")
            fixture.mode, fixture.cycle = "base_watch", 1
        elseif fixture.mode == "base_watch" then fixture.mode = "expedition"
        else fixture.mode, fixture.cycle = "base_watch", fixture.cycle + 1 end
        if fixture.cycle > fixture.cycles then return finish(H, fixture, check, result, setPhase, current) end
        setPhase("view_cutaway_open", current)
    elseif H.phase == "view_cutaway_stock_open" then
        fixture.soloSampling = false
        fixture.mode, fixture.cycle = "stock_custom", fixture.stockIndex
        fixture.holdWall = fixture.walls[1]
        if not check("view_cutaway_CUSTOM_stock_api", SCSplitScreenProbe.debugReleaseStockObserver ~= nil
            and SCSplitScreenProbe.debugPlayerSqlId ~= nil, "exact tracked debug-only native teardown and SQL reader") then
            cleanup(fixture); setPhase("finish", current) return
        end
        if not check("view_cutaway_CUSTOM_stock_pose", place(H.player, fixture.holdWall.inside),
            "same fixed baseline wall pose") then cleanup(fixture); setPhase("finish", current) return end
        fixture.openAt, fixture.openFrame = current, fixture.frames
        setPhase("view_cutaway_stock_settle", current)
    elseif H.phase == "view_cutaway_stock_settle" then
        if fixture.frames - fixture.openFrame < 60 or current - fixture.openAt < 1000 then return end
        local wall = fixture.holdWall
        if not check("view_cutaway_CUSTOM_stock_pre_join_hidden_" .. fixture.stockIndex,
            hasBit(call(wall.square, "getPlayerCutawayFlag", 0, getTimestampMs()), wall.bit),
            "human holds this pose until frame300 after close") then cleanup(fixture); setPhase("finish", current) return end
        fixture.stockSql = snapshotSql(H, fixture)
        fixture.stockOrigin = fixture.leaders[1].home
        local made, actor = pcall(SCSplitScreenProbe.start, math.floor(fixture.stockOrigin.x),
            math.floor(fixture.stockOrigin.y), math.floor(fixture.stockOrigin.z))
        if not check("view_cutaway_CUSTOM_stock_join_" .. fixture.stockIndex,
            made and actor ~= nil and SC.ViewSession.owner() == nil,
            "plain native IsoPlayer + actual AddCoopPlayer; no ViewSession claim") then
            cleanup(fixture); setPhase("finish", current) return
        end
        fixture.stockActor, fixture.joinedAt = actor, nil
        capture(H, fixture, "CUSTOM_stock_promote_" .. fixture.stockIndex)
        setPhase("view_cutaway_stock_join", current)
    elseif H.phase == "view_cutaway_stock_join" then
        if getSpecificPlayer(1) ~= fixture.stockActor then return end
        fixture.joinedAt = fixture.joinedAt or fixture.frames
        if fixture.frames - fixture.joinedAt < 60 then return end
        capture(H, fixture, "CUSTOM_stock_joined_" .. fixture.stockIndex, true)
        fixture.excursionBefore = bodySnapshot(fixture.stockActor)
        result("PASS", "view_cutaway_CUSTOM_stock_health_before", bodyDetail(fixture.excursionBefore))
        if not check("view_cutaway_CUSTOM_stock_other_room", place(fixture.stockActor, fixture.remote),
            "same room/floor excursion as companion") then cleanup(fixture); setPhase("finish", current) return end
        fixture.remoteAt = fixture.frames
        setPhase("view_cutaway_stock_remote", current)
    elseif H.phase == "view_cutaway_stock_remote" then
        if fixture.frames - fixture.remoteAt < 90 then return end
        local after = bodySnapshot(fixture.stockActor)
        if not check("view_cutaway_CUSTOM_stock_floor_health_after",
            excursionSafe(fixture.excursionBefore, after, fixture.remote), bodyDetail(after)
                .. ";targetZ=" .. fixture.remote.z) then cleanup(fixture); setPhase("finish", current) return end
        capture(H, fixture, "CUSTOM_stock_other_room_" .. fixture.stockIndex, true)
        if not check("view_cutaway_CUSTOM_stock_return", place(fixture.stockActor, fixture.stockOrigin),
            "return into primary-owned loaded area") then cleanup(fixture); setPhase("finish", current) return end
        fixture.returnAt = fixture.frames
        setPhase("view_cutaway_stock_close", current)
    elseif H.phase == "view_cutaway_stock_close" then
        if fixture.frames - fixture.returnAt < 60 then return end
        fixture.beforeCounts = {}
        for _, record in ipairs(fixture.records) do fixture.beforeCounts[record.id] = updateCount(record.actor) end
        fixture.sampled, fixture.stockRestoreStatus = {}, nil
        destroyPlayerData(fixture.stockActor)
        local called, released = pcall(SCSplitScreenProbe.debugReleaseStockObserver, fixture.stockActor)
        if not check("view_cutaway_CUSTOM_stock_close_" .. fixture.stockIndex,
            called and released == true and getSpecificPlayer(1) == nil,
            "custom stock-actor removal + only slot1 map release") then cleanup(fixture); setPhase("finish", current) return end
        capture(H, fixture, "CUSTOM_stock_native_close_" .. fixture.stockIndex)
        local clock = UIManager.getClock()
        if clock then clock:setY(10) end
        UIManager.resize()
        capture(H, fixture, "CUSTOM_stock_ui_close_" .. fixture.stockIndex)
        fixture.closedAt, fixture.soloSampling = fixture.frames, true
        -- A stock observer never belongs to ViewSession. Use a separate probe
        -- callback, registered after the sample callback just like the normal
        -- post-release ViewSession hook, and remove it on terminal state.
        fixture.stockPoll = function()
            local status = SCSplitScreenProbe.pollPrimaryViewRestore()
            fixture.stockRestoreStatus = status
            if status == "applied" or status == "cancelled" or status == "failed" then
                Events.OnPostRender.Remove(fixture.stockPoll)
                fixture.stockPoll = nil
            end
        end
        Events.OnPostRender.Add(fixture.stockPoll)
        setPhase("view_cutaway_solo", current)
    elseif H.phase == "view_cutaway_open" then
        fixture.soloSampling = false
        fixture.openGeneration = (fixture.openGeneration or 0) + 1
        fixture.releaseObserved, fixture.closedAt, fixture.joinedAt = nil, nil, nil
        fixture.holdWall = fixture.walls[1]
        place(H.player, fixture.holdWall.inside)
        local candidate = fixture.leaders[(fixture.cycle - 1) % #fixture.leaders + 1]
        fixture.leader, fixture.leaderHome = candidate.record, candidate.home
        fixture.openAt, fixture.openFrame = current, fixture.frames
        setPhase("view_cutaway_open_settle", current)
    elseif H.phase == "view_cutaway_open_settle" then
        if fixture.frames - fixture.openFrame < 60 or current - fixture.openAt < 1000 then return end
        local wall = fixture.holdWall
        if not check("view_cutaway_pre_promote_pose_" .. fixture.mode .. "_" .. fixture.cycle,
            hasBit(call(wall.square, "getPlayerCutawayFlag", 0, getTimestampMs()), wall.bit),
            "primary will hold the baseline hidden-wall pose through join/close/frame300") then
            cleanup(fixture); setPhase("finish", current) return
        end
        local actor = fixture.leader.actor
        pcall(SC.BaseWork.cancel, actor, "view_cutaway_fixture")
        pcall(SC.Downtime.cancel, actor, "view_cutaway_fixture")
        if not check("view_cutaway_leader_near_primary", H.placeCombatActor(actor,
            fixture.leaderHome), "original indoor camp tile within twelve tiles of primary") then
            cleanup(fixture); setPhase("finish", current) return
        end
        local accepted, why
        if fixture.mode == "base_watch" then
            SC.Commands.issue(fixture.leader.id, "base_duty", nil, H.player)
            accepted, why = SC.BaseWatch.start(fixture.leader.id)
        else accepted, why = SC.ExpeditionPrototype.start({ fixture.leader }) end
        if not check("view_cutaway_open_" .. fixture.mode .. "_" .. fixture.cycle,
            accepted == true, tostring(why)) then cleanup(fixture); setPhase("finish", current) return end
        fixture.joinedAt, fixture.closedAt, fixture.sampled = nil, nil, {}
        capture(H, fixture, "promote_" .. fixture.mode .. "_" .. fixture.cycle)
        setPhase("view_cutaway_join", current)
    elseif H.phase == "view_cutaway_join" then
        if getSpecificPlayer(1) ~= fixture.leader.actor then return end
        fixture.joinedAt = fixture.joinedAt or fixture.frames
        if fixture.frames - fixture.joinedAt < 60 then return end
        capture(H, fixture, "joined_" .. fixture.mode .. "_" .. fixture.cycle, true)
        fixture.excursionBefore = bodySnapshot(fixture.leader.actor)
        result("PASS", "view_cutaway_health_before_" .. fixture.mode .. "_" .. fixture.cycle,
            bodyDetail(fixture.excursionBefore))
        if not check("view_cutaway_other_room_" .. fixture.mode .. "_" .. fixture.cycle,
            H.placeCombatActor(fixture.leader.actor, fixture.remote),
            "remote=" .. fixture.remote.x .. "," .. fixture.remote.y .. "," .. fixture.remote.z) then
            cleanup(fixture); setPhase("finish", current) return
        end
        fixture.remoteAt = fixture.frames
        setPhase("view_cutaway_remote", current)
    elseif H.phase == "view_cutaway_remote" then
        if fixture.frames - fixture.remoteAt < 90 then return end
        local after = bodySnapshot(fixture.leader.actor)
        if not check("view_cutaway_floor_health_after_" .. fixture.mode .. "_" .. fixture.cycle,
            excursionSafe(fixture.excursionBefore, after, fixture.remote), bodyDetail(after)
                .. ";targetZ=" .. fixture.remote.z) then cleanup(fixture); setPhase("finish", current) return end
        capture(H, fixture, "joined_other_room_" .. fixture.mode .. "_" .. fixture.cycle, true)
        if not check("view_cutaway_return_leader_" .. fixture.mode .. "_" .. fixture.cycle,
            H.placeCombatActor(fixture.leader.actor, fixture.leaderHome), "same retained actor returns before guarded close") then
            cleanup(fixture); setPhase("finish", current) return
        end
        fixture.returnAt = fixture.frames
        setPhase("view_cutaway_return", current)
    elseif H.phase == "view_cutaway_return" then
        if fixture.frames - fixture.returnAt < 60 then return end
        local returned = bodySnapshot(fixture.leader.actor)
        if not check("view_cutaway_health_return_" .. fixture.mode .. "_" .. fixture.cycle,
            excursionSafe(fixture.excursionBefore, returned, fixture.leaderHome), bodyDetail(returned)) then
            cleanup(fixture); setPhase("finish", current) return
        end
        fixture.beforeCounts = {}
        for _, record in ipairs(fixture.records) do fixture.beforeCounts[record.id] = updateCount(record.actor) end
        local accepted, why
        if fixture.mode == "base_watch" then accepted, why = SC.BaseWatch.cancelBeforeDeparture()
        else accepted, why = SC.ExpeditionPrototype.finishAtPlayer(H.player) end
        if not check("view_cutaway_close_" .. fixture.mode .. "_" .. fixture.cycle,
            accepted == true and getSpecificPlayer(1) == nil, tostring(why)) then
            cleanup(fixture); setPhase("finish", current) return
        end
        fixture.closedAt = fixture.closedAt or fixture.frames
        setPhase("view_cutaway_solo", current)
    elseif H.phase == "view_cutaway_solo" then
        local elapsed = fixture.frames - fixture.closedAt
        if elapsed >= 300 then
            fixture.soloSampling = false
            if fixture.identityLost then
                result("FAIL", "view_cutaway_fixture_invalidated",
                    "runtime retired/replaced an original actor; stop before further stock or companion cycles")
                cleanup(fixture)
                setPhase("finish", current)
                return
            end
            startRoute(H, fixture, false)
            setPhase("view_cutaway_walk", current)
        end
    end
end

Probe._tests = { hasBit = hasBit, healthy = healthy, wallAt = wallAt,
    place = place, snapshotSql = snapshotSql, sameSql = sameSql,
    retainedIdentity = retainedIdentity, capture = capture, preferRemote = preferRemote,
    releaseReceipt = releaseReceipt, releaseTransition = releaseTransition,
    safeFloor = safeFloor, excursionSafe = excursionSafe, chooseWall = chooseWall,
    quickOwnFact = quickOwnFact, quickStep = quickStep, quickTryWatch = quickTryWatch }
SCRealSandboxHarnessProbes = SCRealSandboxHarnessProbes or {}
SCRealSandboxHarnessProbes.SCViewCutawayProbe = Probe
return Probe
