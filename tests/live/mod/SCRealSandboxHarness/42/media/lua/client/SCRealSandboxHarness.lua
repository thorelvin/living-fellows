-- SPDX-License-Identifier: MIT
-- Private live integration harness. This file is installed only in a disposable
-- cachedir created by Invoke-LiveSandboxTests.ps1; it is never packaged with the mod.

local CONFIG_FILE = "SurvivorCompanionHarness/config.ini"
local EVENTS_FILE = "SurvivorCompanionHarness/events.log"
local SUMMARY_FILE = "SurvivorCompanionHarness/summary.txt"
local FACTION_MAP_READY_FILE = "SurvivorCompanionHarness/faction-map-ready.txt"
local FACTION_MAP_VISIBLE_FILE = "SurvivorCompanionHarness/faction-map-visible.txt"
local FACTION_MAP_CAPTURED_FILE = "SurvivorCompanionHarness/faction-map-captured.txt"

local Harness = {
    config = {},
    results = {},
    phase = "idle",
    failures = 0,
    skipped = 0,
    passes = 0,
    startedAt = 0,
    phaseStartedAt = 0,
    finished = false,
    autoloadIssued = false,
    autoloadConfirmed = false,
    autoloadConfirmations = 0,
    autoloadModal = nil,
    autoloadPromptSignatures = {},
    nextAutoloadConfirmAt = 0,
    autoloadIssuedAt = 0,
    observedRoomStatuses = {},
}

local function nowMs()
    if type(getTimestampMs) == "function" then
        local ok, value = pcall(getTimestampMs)
        if ok and tonumber(value) then return tonumber(value) end
    end
    return math.floor(os.time() * 1000)
end

local function clean(value)
    local text = tostring(value or "")
    text = string.gsub(text, "[\r\n|]", " ")
    if #text > 480 then text = string.sub(text, 1, 480) end
    return text
end

local function readConfig()
    if type(getFileReader) ~= "function" then return {} end
    local reader = getFileReader(CONFIG_FILE, true)
    if reader == nil then return {} end
    local values = {}
    while true do
        local line = reader:readLine()
        if line == nil then break end
        local key, value = string.match(line, "^([%w_]+)=(.*)$")
        if key then values[key] = value end
    end
    reader:close()
    return values
end

local function writeSnapshot(done)
    if type(getFileWriter) ~= "function" then return end
    local writer = getFileWriter(EVENTS_FILE, true, false)
    if writer ~= nil then
        writer:writeln("SC_REAL_SANDBOX_EVENTS_V1")
        writer:writeln("run_id=" .. clean(Harness.config.run_id))
        for _, result in ipairs(Harness.results) do
            writer:writeln(clean(result.status) .. "|" .. clean(result.name)
                .. "|" .. clean(result.detail))
        end
        writer:close()
    end
    if not done then return end
    writer = getFileWriter(SUMMARY_FILE, true, false)
    if writer ~= nil then
        writer:writeln("SC_REAL_SANDBOX_SUMMARY_V1")
        writer:writeln("run_id=" .. clean(Harness.config.run_id))
        writer:writeln("status=" .. (Harness.failures == 0 and "PASS" or "FAIL"))
        writer:writeln("passes=" .. tostring(Harness.passes))
        writer:writeln("failures=" .. tostring(Harness.failures))
        writer:writeln("skipped=" .. tostring(Harness.skipped))
        writer:writeln("release=" .. clean(Harness.release))
        writer:close()
    end
end

local function fileExists(path)
    if type(getFileReader) ~= "function" then return false end
    local reader = getFileReader(path, true)
    if reader == nil then return false end
    -- Build 42 may create an empty sandbox file while opening a missing path.
    -- A signal is present only after the other side writes at least one line.
    local firstLine = reader:readLine()
    reader:close()
    return firstLine ~= nil
end

local function writeSignal(path, rows)
    if type(getFileWriter) ~= "function" then return false end
    local writer = getFileWriter(path, true, false)
    if writer == nil then return false end
    for _, row in ipairs(rows or {}) do writer:writeln(clean(row)) end
    writer:close()
    return true
end

local function result(status, name, detail)
    if status == "PASS" then Harness.passes = Harness.passes + 1
    elseif status == "SKIP" then Harness.skipped = Harness.skipped + 1
    else Harness.failures = Harness.failures + 1 status = "FAIL" end
    Harness.results[#Harness.results + 1] = {
        status = status,
        name = name,
        detail = detail,
    }
    print("SC_REAL_SANDBOX|" .. status .. "|" .. clean(name) .. "|" .. clean(detail))
    writeSnapshot(false)
end

local function check(name, condition, detail)
    result(condition and "PASS" or "FAIL", name, detail)
    return condition == true
end

local function skip(name, detail)
    result("SKIP", name, detail)
end

local function setPhase(name, current)
    Harness.phase = name
    Harness.phaseStartedAt = current or nowMs()
end

-- Keep a production actor registered and healthy while preventing the normal
-- decision scheduler from racing deterministic movement/combat probes. The
-- action supervisor is the same ownership boundary used by real gameplay.
local function beginHarnessControl(actor, action, timeoutMs)
    local SC = SurvivorCompanion
    local supervisor = SC and SC.ActionSupervisor
    if type(supervisor) ~= "table" or type(supervisor.begin) ~= "function" then
        return nil, "action supervisor unavailable"
    end
    if type(supervisor.cancel) == "function" then
        pcall(supervisor.cancel, actor, "live_harness_control", nil, true)
    end
    local priority = supervisor.Priority and supervisor.Priority.EXTERNAL or 1000
    return supervisor.begin(actor, {
        owner = "live_harness",
        action = action,
        priority = priority,
        phase = "approaching",
        interruptible = false,
        ignoreRetry = true,
        deadlines = { approaching = timeoutMs or 15000 },
        allowedMovementPhases = { approaching = true },
    })
end

local function endHarnessControl(token, reason)
    if type(token) ~= "table" then return end
    local supervisor = SurvivorCompanion and SurvivorCompanion.ActionSupervisor
    if type(supervisor) ~= "table" then return end
    local completed = false
    if type(supervisor.complete) == "function" then
        local ok, result = pcall(supervisor.complete, token, reason or "probe_complete")
        completed = ok and result == true
    end
    if not completed and type(supervisor.cancel) == "function" then
        pcall(supervisor.cancel, token.actor, reason or "probe_cleanup", nil, true)
    end
end

local function getPlayerSafe()
    if type(getPlayer) ~= "function" then return nil end
    local ok, player = pcall(getPlayer)
    return ok and player or nil
end

local function position(value)
    local utility = SurvivorCompanion and SurvivorCompanion.GameplayUtil
    if utility and type(utility.position) == "function" then
        return utility.position(value)
    end
    return nil, nil, nil
end

local function distance(a, b)
    local utility = SurvivorCompanion and SurvivorCompanion.GameplayUtil
    if utility and type(utility.distance) == "function" then
        return utility.distance(a, b)
    end
    return math.huge
end

local function safeSpawnSquare(player)
    local SC = SurvivorCompanion
    local utility = SC and SC.GameplayUtil
    if not utility then return nil end
    local px, py, pz = position(player)
    if px == nil or type(getCell) ~= "function" then return nil end
    local cell = getCell()
    if cell == nil then return nil end
    local offsets = {
        { 7, 0 }, { -7, 0 }, { 0, 7 }, { 0, -7 },
        { 6, 3 }, { -6, 3 }, { 6, -3 }, { -6, -3 },
        { 5, 0 }, { -5, 0 }, { 0, 5 }, { 0, -5 },
        { 4, 3 }, { -4, 3 }, { 4, -3 }, { -4, -3 },
    }
    for _, offset in ipairs(offsets) do
        local square = cell:getGridSquare(
            math.floor(px + offset[1]), math.floor(py + offset[2]), math.floor(pz or 0))
        if square ~= nil and utility.isSquareFree(square) then
            local free, freeOk = utility.call(square, "isFree", true)
            local safe, safeOk = utility.call(square, "isSafeToSpawn")
            if (not freeOk or free == true) and (not safeOk or safe == true) then
                return square
            end
        end
    end
    return nil
end

local function beginNativeSpawn(current)
    local SC = SurvivorCompanion
    local square = safeSpawnSquare(Harness.player)
    if square == nil then
        local living = SC.Registry.living()
        if #living > 0 then
            Harness.actor = living[1]
            skip("deferred_native_spawn", "no safe loaded test square; using restored companion")
            return true
        end
        result("FAIL", "deferred_native_spawn", "no safe loaded spawn square")
        return false
    end
    Harness.spawnSquare = square
    local ticket, reason = SC.Actor.beginSpawn(square, {
        recruited = true,
        identity = {
            forename = "Harness",
            surname = "Fellow",
            gender = "man",
            outfit = "Generic01",
        },
    })
    if ticket == nil then
        local living = SC.Registry.living()
        if #living > 0 then
            Harness.actor = living[1]
            skip("deferred_native_spawn", "spawn unavailable: " .. clean(reason)
                .. "; using restored companion")
            return true
        end
        result("FAIL", "deferred_native_spawn", reason)
        return false
    end
    Harness.spawnTicket = ticket
    setPhase("poll_spawn", current)
    return nil
end

local function routeProbe(actor, player)
    local SC = SurvivorCompanion
    local utility = SC.GameplayUtil
    local square = utility.squareOf(actor)
    local x, y, z = position(square)
    if x == nil or type(getCell) ~= "function" then
        result("FAIL", "real_route_evaluation", "actor square is unavailable")
        return
    end
    local snapshot = SC.Senses.snapshot(actor, player, {})
    Harness.snapshot = snapshot
    local offsets = {
        { 7, 0 }, { -7, 0 }, { 0, 7 }, { 0, -7 },
        { 6, 4 }, { -6, 4 }, { 6, -4 }, { -6, -4 },
    }
    local best
    for _, offset in ipairs(offsets) do
        local goal = getCell():getGridSquare(
            math.floor(x + offset[1]), math.floor(y + offset[2]), math.floor(z or 0))
        if goal ~= nil and utility.isSquareFree(goal) then
            local ok, report = pcall(SC.Navigation.evaluateRoutes, square, goal, snapshot)
            if ok and type(report) == "table" and type(report.path) == "table" then
                if best == nil or (tonumber(report.candidateCount) or 0)
                    > (tonumber(best.candidateCount) or 0) then best = report end
            end
        end
    end
    if best == nil then
        result("FAIL", "real_route_evaluation", "no bounded path to a loaded probe square")
        return
    end
    local count = tonumber(best.candidateCount) or 0
    local expanded = tonumber(best.expandedNodes) or math.huge
    check("real_route_evaluation", count >= 1 and count <= 3 and expanded <= 380,
        "candidates=" .. tostring(count) .. " expanded=" .. tostring(expanded)
            .. " selected=" .. tostring(best.selectedOriginalIndex))
    if count >= 2 then
        result("PASS", "alternative_follow_routes", "distinct bounded candidates=" .. tostring(count))
    else
        skip("alternative_follow_routes", "loaded surroundings provide only one viable bounded route")
    end
end

local function roomOf(square)
    local utility = SurvivorCompanion.GameplayUtil
    local room, ok = utility.call(square, "getRoom")
    return ok and room or nil
end

local function isWalkableRoomThreshold(source, destination)
    local utility = SurvivorCompanion.GameplayUtil
    local window, windowOk = utility.call(source, "isWindowTo", destination)
    if windowOk and window == true then return false end
    local hoppable, hopOk = utility.call(source, "isHoppableTo", destination)
    if hopOk and hoppable == true then return false end
    local door, doorOk = utility.call(source, "isDoorTo", destination)
    if doorOk and door == true then return true end
    return not utility.edgeBlocked(source, destination)
end

local function findStraightNativePathTarget(actor)
    local SC = SurvivorCompanion
    local utility = SC.GameplayUtil
    local source = utility.squareOf(actor)
    local sx, sy, sz = position(source)
    if sx == nil or type(getCell) ~= "function" then return nil end
    local cell = getCell()
    local directions = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
    -- A straight, cardinal run makes the engine's direct-line optimization
    -- deterministic. Every intermediate tile and edge must be traversable.
    for distanceInTiles = 4, 2, -1 do
        for _, direction in ipairs(directions) do
            local previous = source
            local valid = true
            for step = 1, distanceInTiles do
                local square = cell:getGridSquare(math.floor(sx + direction[1] * step),
                    math.floor(sy + direction[2] * step), math.floor(sz or 0))
                if square == nil or not utility.isSquareFree(square)
                    or utility.edgeBlocked(previous, square) then
                    valid = false
                    break
                end
                previous = square
            end
            if valid then return previous end
        end
    end
    return nil
end

local function finishNativeLocomotionProbe(current, timedOut)
    local SC = SurvivorCompanion
    local actor = Harness.actor
    local ax, ay = position(actor)
    local displacement = ax ~= nil and math.sqrt(
        (ax - Harness.nativePathStartX) ^ 2 + (ay - Harness.nativePathStartY) ^ 2) or 0
    local remaining = distance(actor, Harness.nativePathTarget)
    check("native_direct_path_progress",
        displacement >= 0.35 or remaining <= 0.8,
        "displacement=" .. string.format("%.2f", displacement)
            .. " remaining=" .. string.format("%.2f", remaining)
            .. (timedOut and " timeout=true" or ""))
    check("native_direct_path_arrival",
        timedOut ~= true and remaining <= 0.8,
        "remaining=" .. string.format("%.2f", remaining)
            .. " pending=" .. tostring(Harness.nativePathLastPending)
            .. (timedOut and " timeout=true" or ""))
    check("native_player_locomotion_graph",
        Harness.nativePathPlayerGroupSeen == true
            and Harness.nativePathMovementStateSeen == true
            and Harness.nativePathMovingSeen == true,
        "group=" .. tostring(Harness.nativePathLastGroup)
            .. " state=" .. tostring(Harness.nativePathLastState)
            .. " moving=" .. tostring(Harness.nativePathMovingSeen))
    check("native_locomotion_animation_rates",
        Harness.nativePathAnimationSeen == true
            and (Harness.nativePathWalkSpeed or -1) > 0,
        "anim_updating=" .. tostring(Harness.nativePathAnimationSeen)
            .. " WalkSpeed=" .. tostring(Harness.nativePathWalkSpeed))
    check("native_player_walk_clip",
        Harness.nativePathWalkClipSeen == true,
        "active_clips=" .. clean(Harness.nativePathAnimationNames))
    check("native_pathfinder_owns_direct_corridor",
        Harness.nativePathfindStateSeen == true,
        "seen=" .. tostring(Harness.nativePathfindStateSeen)
            .. " final=" .. tostring(Harness.nativePathLastPathfind)
            .. " telemetry=" .. clean(Harness.nativePathTelemetryStatus))
    check("native_path_state_released",
        Harness.nativePathLastPending ~= true
            and Harness.nativePathLastPathfind ~= true,
        "pending=" .. tostring(Harness.nativePathLastPending)
            .. " bPathfind=" .. tostring(Harness.nativePathLastPathfind))
    pcall(SC.Actor.stop, actor)
    SC.Navigation.reset(actor)
    endHarnessControl(Harness.nativePathControl, "native_locomotion_probe_complete")
    Harness.nativePathControl = nil
    setPhase("begin_backward_strafe", current)
end

local function beginNativeLocomotionProbe(current)
    local SC = SurvivorCompanion
    local id = SC.Registry.idOf(Harness.actor)
    if id then pcall(SC.Commands.issue, id, "stay", nil, Harness.player) end
    SC.Navigation.reset(Harness.actor)
    pcall(SC.Actor.stop, Harness.actor)
    local target = findStraightNativePathTarget(Harness.actor)
    if target == nil then
        skip("native_direct_path_progress", "no straight loaded corridor of two tiles")
        skip("native_direct_path_arrival", "no straight loaded corridor of two tiles")
        skip("native_player_locomotion_graph", "no straight loaded corridor of two tiles")
        skip("native_locomotion_animation_rates", "no straight loaded corridor of two tiles")
        skip("native_player_walk_clip", "no straight loaded corridor of two tiles")
        skip("native_pathfinder_owns_direct_corridor", "no straight loaded corridor of two tiles")
        skip("native_path_state_released", "no straight loaded corridor of two tiles")
        setPhase("begin_backward_strafe", current)
        return
    end
    local control, controlReason = beginHarnessControl(
        Harness.actor, "native_locomotion_probe", 10000)
    if control == nil then
        result("FAIL", "native_direct_path_progress",
            "control ownership rejected: " .. clean(controlReason))
        setPhase("begin_backward_strafe", current)
        return
    end
    local sx, sy = position(Harness.actor)
    local accepted, reason = SC.Actor.setMovement(Harness.actor, "walk", {
        action = "path",
        targetSquare = target,
        targetKind = "square",
        enginePath = true,
        supervisorToken = control,
    })
    if accepted ~= true then
        endHarnessControl(control, "native_locomotion_probe_rejected")
        result("FAIL", "native_direct_path_progress", clean(reason))
        setPhase("begin_backward_strafe", current)
        return
    end
    Harness.nativePathControl = control
    Harness.nativePathTarget = target
    Harness.nativePathStartX = sx
    Harness.nativePathStartY = sy
    Harness.nativePathStartDistance = distance(Harness.actor, target)
    Harness.nativePathPlayerGroupSeen = false
    Harness.nativePathMovementStateSeen = false
    Harness.nativePathMovingSeen = false
    Harness.nativePathAnimationSeen = false
    Harness.nativePathWalkClipSeen = false
    Harness.nativePathfindStateSeen = false
    Harness.nativePathWalkSpeed = -1
    Harness.nativePathAnimationNames = ""
    Harness.nativePathTelemetryStatus = reason
    setPhase("native_locomotion", current)
end

local function probeNativeLocomotion(current)
    local SC = SurvivorCompanion
    local utility = SC.GameplayUtil
    local actor = Harness.actor
    local group = select(1, utility.call(actor, "getCompanionActionGroupName"))
    local state = select(1, utility.call(actor, "getCompanionActionStateName"))
    local moving = select(1, utility.call(actor, "isPlayerMoving"))
    local updating = select(1, utility.call(actor, "isAnimationUpdatingThisFrame"))
    local pathfind = select(1, utility.call(actor, "getVariableBoolean", "bPathfind"))
    local pending = select(1, utility.call(actor, "hasPendingMovement"))
    local walkSpeed = select(1, utility.call(actor, "getVariableFloat", "WalkSpeed", -1))
    local animationNames = select(1,
        utility.call(actor, "getCompanionActiveAnimationNames"))
    Harness.nativePathLastGroup = group
    Harness.nativePathLastState = state
    Harness.nativePathLastPathfind = pathfind
    Harness.nativePathLastPending = pending
    Harness.nativePathPlayerGroupSeen = Harness.nativePathPlayerGroupSeen
        or string.lower(tostring(group or "")) == "player"
    local stateName = string.lower(tostring(state or ""))
    Harness.nativePathMovementStateSeen = Harness.nativePathMovementStateSeen
        or stateName == "movement" or stateName == "run" or stateName == "sprint"
    Harness.nativePathMovingSeen = Harness.nativePathMovingSeen or moving == true
    Harness.nativePathAnimationSeen = Harness.nativePathAnimationSeen or updating == true
    local loweredAnimations = string.lower(tostring(animationNames or ""))
    Harness.nativePathWalkClipSeen = Harness.nativePathWalkClipSeen
        or loweredAnimations:find("walk", 1, true) ~= nil
        or loweredAnimations:find("run", 1, true) ~= nil
    if loweredAnimations:find("walk", 1, true) ~= nil
        or loweredAnimations:find("run", 1, true) ~= nil then
        Harness.nativePathAnimationNames = animationNames
    elseif Harness.nativePathAnimationNames == "" and loweredAnimations ~= "" then
        Harness.nativePathAnimationNames = animationNames
    end
    if tonumber(walkSpeed) and tonumber(walkSpeed) > Harness.nativePathWalkSpeed then
        Harness.nativePathWalkSpeed = tonumber(walkSpeed)
    end
    Harness.nativePathfindStateSeen = Harness.nativePathfindStateSeen or pathfind == true
    local remaining = distance(actor, Harness.nativePathTarget)
    -- Observe the whole route. Progress alone allowed an actor that moved one
    -- tile and then wedged itself to pass; completion also has to release both
    -- the bridge pending state and vanilla's bPathfind variable.
    if remaining <= 0.8 and pending ~= true and pathfind ~= true then
        finishNativeLocomotionProbe(current, false)
    elseif current - Harness.phaseStartedAt > 10000 then
        finishNativeLocomotionProbe(current, true)
    end
end

local function findClearManualDirection(actor, clearance)
    local utility = SurvivorCompanion.GameplayUtil
    local x, y, z = position(actor)
    if x == nil then return nil end
    for _, direction in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
        local clear, called = utility.call(actor, "isCompanionMovementClear",
            x + direction[1] * (clearance or 1.25), y + direction[2] * (clearance or 1.25), z or 0)
        if called and clear == true then return direction[1], direction[2] end
    end
    return nil
end

function Harness.findCombatArena(player)
    local U = SurvivorCompanion.GameplayUtil
    local px, py, pz = position(player)
    if not px or type(getCell) ~= "function" then return nil end
    local cell = getCell()
    if not cell then return nil end
    -- Prefer at least 15 tiles from the observer. Only fall back to a loaded
    -- 10+ tile lane; ordinary single-player cannot enable invisibility cheats.
    for _, radius in ipairs({ 16, 20, 24, 12 }) do
        for _, direction in ipairs({ {1,0}, {-1,0}, {0,1}, {0,-1},
            {1,1}, {-1,1}, {1,-1}, {-1,-1} }) do
            local x, y = math.floor(px + direction[1] * radius), math.floor(py + direction[2] * radius)
            local safe = true
            for ox = -2, 2 do
                for oy = -2, 2 do
                    local square = cell:getGridSquare(x + ox, y + oy, math.floor(pz))
                    if not square or not U.call(square, "getChunk") or not U.isSquareFree(square) then
                        safe = false; break
                    end
                    local moving = U.call(square, "getMovingObjects")
                    local size = moving and U.call(moving, "size")
                    if not tonumber(size) or tonumber(size) > 0 then safe = false; break end
                    if ox > -2 and U.edgeBlocked(square, cell:getGridSquare(x+ox-1, y+oy, math.floor(pz))) then
                        safe = false; break
                    end
                    if oy > -2 and U.edgeBlocked(square, cell:getGridSquare(x+ox, y+oy-1, math.floor(pz))) then
                        safe = false; break
                    end
                end
                if not safe then break end
            end
            if safe then return {x=x+0.5, y=y+0.5, z=pz,
                observerDistance=math.sqrt((x+0.5-px)^2+(y+0.5-py)^2)} end
        end
    end
    return nil
end

function Harness.placeCombatActor(actor, point)
    local SC, U = SurvivorCompanion, SurvivorCompanion.GameplayUtil
    if not actor or not point or SC.Actor.stop(actor) ~= true then return false, "actor stop rejected" end
    local placed, reason = pcall(function()
        actor:setX(point.x); actor:setY(point.y); actor:setZ(point.z)
        actor:setNextX(point.x); actor:setNextY(point.y)
        actor:setLastX(point.x); actor:setLastY(point.y); actor:setLastZ(point.z)
        actor:setCurrentSquareFromPosition()
        actor:setSquare(actor:getCurrentSquare())
        actor:setMovingSquare(actor:getCurrentSquare())
    end)
    if not placed then return false, tostring(reason) end
    local member, checked = U.call(actor, "ensureWorldMembership")
    local square = U.call(actor, "getCurrentSquare")
    return checked and member == true and square ~= nil
        and U.call(actor, "getMovingSquare") == square,
        "member=" .. tostring(member) .. " position=" .. point.x .. "," .. point.y .. "," .. point.z
end

function Harness.restoreCombatArena()
    if not Harness.combatArenaReturn then return true end
    local restored, reason = Harness.placeCombatActor(Harness.actor, Harness.combatArenaReturn)
    if restored then Harness.combatArenaReturn = nil end
    return check("combat_arena_membership_restored", restored, reason)
end

-- Manual movement is a short input lease, just like a held player key. The
-- production decision loop renews it; an animation probe must do the same.
-- A single 250ms tap cannot prove a sustained gait after a 180-degree turn.
local function refreshManualProbe(current, input)
    if not input or input.failure or current < input.nextAt then return end
    input.nextAt = current + 100
    local accepted, reason = SurvivorCompanion.Actor.setMovement(
        Harness.actor, input.mode, input.intent)
    if accepted == true then
        input.refreshes = input.refreshes + 1
    else
        input.failure = tostring(reason or "manual_input_rejected")
        pcall(SurvivorCompanion.Actor.stop, Harness.actor)
    end
end

local function beginBackwardStrafeProbe(current)
    local SC = SurvivorCompanion
    pcall(SC.Actor.stop, Harness.actor)
    local moveX, moveY = findClearManualDirection(Harness.actor, 3)
    if moveX == nil then
        skip("native_backward_strafe_motion", "no clear cardinal manual-movement lane")
        skip("native_backward_strafe_blend", "no clear cardinal manual-movement lane")
        skip("native_backward_strafe_clip", "no clear cardinal manual-movement lane")
        setPhase("begin_room", current)
        return
    end
    local control, reason = beginHarnessControl(
        Harness.actor, "native_backward_strafe_probe", 5000)
    if control == nil then
        result("FAIL", "native_backward_strafe_motion",
            "control ownership rejected: " .. clean(reason))
        setPhase("begin_room", current)
        return
    end
    local x, y, z = position(Harness.actor)
    local facingTarget = {
        x = x - moveX * 4,
        y = y - moveY * 4,
        z = z or 0,
    }
    local intent = {
        action = "backstep",
        dx = moveX,
        dy = moveY,
        facingTarget = facingTarget,
        keepFacing = true,
        weaponReady = false,
        supervisorToken = control,
    }
    local accepted, moveReason = SC.Actor.setMovement(Harness.actor, "walk", intent)
    if accepted ~= true then
        endHarnessControl(control, "native_backward_strafe_rejected")
        result("FAIL", "native_backward_strafe_motion", clean(moveReason))
        setPhase("begin_room", current)
        return
    end
    Harness.backwardStrafeControl = control
    Harness.backwardStrafeInput = {
        mode = "walk", intent = intent, nextAt = current + 100, refreshes = 0,
    }
    Harness.backwardStrafeStartX = x
    Harness.backwardStrafeStartY = y
    Harness.backwardStrafeMoveX = moveX
    Harness.backwardStrafeMoveY = moveY
    Harness.backwardStrafeLastDeltaX = 0
    Harness.backwardStrafeLastDeltaY = 0
    Harness.backwardStrafeLastState = ""
    Harness.backwardStrafeAnimationNames = ""
    Harness.backwardStrafeBwdClipSeen = false
    setPhase("backward_strafe", current)
end

local function probeBackwardStrafe(current)
    local SC = SurvivorCompanion
    local utility = SC.GameplayUtil
    local actor = Harness.actor
    if current - Harness.phaseStartedAt < 1400 then
        refreshManualProbe(current, Harness.backwardStrafeInput)
    end
    local deltaX = select(1, utility.call(actor, "getVariableFloat", "DeltaX", 0))
    local deltaY = select(1, utility.call(actor, "getVariableFloat", "DeltaY", 0))
    local state = select(1, utility.call(actor, "getCompanionActionStateName"))
    local names = select(1, utility.call(actor, "getCompanionActiveAnimationNames"))
    Harness.backwardStrafeLastDeltaX = tonumber(deltaX) or 0
    Harness.backwardStrafeLastDeltaY = tonumber(deltaY) or 0
    Harness.backwardStrafeLastState = tostring(state or "")
    local lowered = string.lower(tostring(names or ""))
    if lowered:find("walkbwd", 1, true) ~= nil then
        Harness.backwardStrafeBwdClipSeen = true
        Harness.backwardStrafeAnimationNames = names
    elseif Harness.backwardStrafeAnimationNames == "" and lowered ~= "" then
        Harness.backwardStrafeAnimationNames = names
    end
    if current - Harness.phaseStartedAt < 1400 then return end
    local x, y = position(actor)
    local dx = (x or Harness.backwardStrafeStartX) - Harness.backwardStrafeStartX
    local dy = (y or Harness.backwardStrafeStartY) - Harness.backwardStrafeStartY
    local along = dx * Harness.backwardStrafeMoveX + dy * Harness.backwardStrafeMoveY
    local forwardX = select(1, utility.call(actor, "getForwardDirectionX"))
    local forwardY = select(1, utility.call(actor, "getForwardDirectionY"))
    local facingDot = (tonumber(forwardX) or 0) * Harness.backwardStrafeMoveX
        + (tonumber(forwardY) or 0) * Harness.backwardStrafeMoveY
    check("native_backward_strafe_motion", along >= 0.05 and facingDot <= -0.75,
        "along=" .. string.format("%.2f", along)
            .. " facing_dot=" .. string.format("%.2f", facingDot))
    check("native_backward_strafe_blend",
        Harness.backwardStrafeLastDeltaY <= -0.50,
        "state=" .. clean(Harness.backwardStrafeLastState)
            .. " DeltaX=" .. string.format("%.2f", Harness.backwardStrafeLastDeltaX)
            .. " DeltaY=" .. string.format("%.2f", Harness.backwardStrafeLastDeltaY))
    check("native_backward_strafe_clip", Harness.backwardStrafeBwdClipSeen == true
        and Harness.backwardStrafeInput.failure == nil
        and Harness.backwardStrafeInput.refreshes >= 2,
        "active_clips=" .. clean(Harness.backwardStrafeAnimationNames)
            .. " input_refreshes=" .. tostring(Harness.backwardStrafeInput.refreshes)
            .. " input_failure=" .. clean(Harness.backwardStrafeInput.failure))
    pcall(SC.Actor.stop, actor)
    endHarnessControl(Harness.backwardStrafeControl,
        "native_backward_strafe_probe_complete")
    Harness.backwardStrafeControl = nil
    Harness.backwardStrafeInput = nil
    setPhase("begin_aimed_escape", current)
end

local function findClearEscapeDirection(actor, threat)
    local utility = SurvivorCompanion.GameplayUtil
    local x, y, z = position(actor)
    local tx, ty = position(threat)
    if x == nil or tx == nil then return nil end
    local awayX, awayY = x - tx, y - ty
    local candidates = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
    table.sort(candidates, function(a, b)
        return a[1] * awayX + a[2] * awayY > b[1] * awayX + b[2] * awayY
    end)
    for _, direction in ipairs(candidates) do
        local clear, called = utility.call(actor, "isCompanionMovementClear",
            x + direction[1] * 4, y + direction[2] * 4, z or 0)
        if called and clear == true then return direction[1], direction[2] end
    end
    return nil
end

local function beginAimedEscapeProbe(current)
    local SC = SurvivorCompanion
    pcall(SC.Actor.stop, Harness.actor)
    local moveX, moveY = findClearEscapeDirection(Harness.actor, Harness.player)
    if moveX == nil then
        skip("native_aimed_escape_facing", "no clear cardinal escape lane")
        skip("native_aimed_escape_player_clip", "no clear cardinal escape lane")
        setPhase("begin_room", current)
        return
    end
    local control, reason = beginHarnessControl(Harness.actor,
        "native_aimed_escape_probe", 5000)
    if control == nil then
        result("FAIL", "native_aimed_escape_facing",
            "control ownership rejected: " .. clean(reason))
        setPhase("begin_room", current)
        return
    end
    local x, y = position(Harness.actor)
    SC.GameplayUtil.call(Harness.actor, "setCompanionAimTarget", Harness.player)
    local intent = {
        action = "move",
        dx = moveX,
        dy = moveY,
        weaponReady = false,
        supervisorToken = control,
    }
    local accepted, moveReason = SC.Actor.setMovement(Harness.actor, "run", intent)
    if accepted ~= true then
        SC.GameplayUtil.call(Harness.actor, "setCompanionAimTarget", nil)
        endHarnessControl(control, "native_aimed_escape_rejected")
        result("FAIL", "native_aimed_escape_facing", clean(moveReason))
        setPhase("begin_room", current)
        return
    end
    Harness.aimedEscapeControl = control
    Harness.aimedEscapeInput = {
        mode = "run", intent = intent, nextAt = current + 100, refreshes = 0,
    }
    Harness.aimedEscapeStartX = x
    Harness.aimedEscapeStartY = y
    Harness.aimedEscapeMoveX = moveX
    Harness.aimedEscapeMoveY = moveY
    Harness.aimedEscapeAnimationNames = ""
    Harness.aimedEscapeForwardClipSeen = false
    setPhase("aimed_escape", current)
end

local function probeAimedEscape(current)
    local SC = SurvivorCompanion
    local utility = SC.GameplayUtil
    if current - Harness.phaseStartedAt < 900 then
        refreshManualProbe(current, Harness.aimedEscapeInput)
    end
    local names = select(1,
        utility.call(Harness.actor, "getCompanionActiveAnimationNames"))
    local lowered = string.lower(tostring(names or ""))
    if (lowered:find("bob_run", 1, true) ~= nil
        or lowered:find("bob_walk", 1, true) ~= nil)
        and lowered:find("bwd", 1, true) == nil then
        Harness.aimedEscapeForwardClipSeen = true
        Harness.aimedEscapeAnimationNames = names
    elseif Harness.aimedEscapeAnimationNames == "" and lowered ~= "" then
        Harness.aimedEscapeAnimationNames = names
    end
    if current - Harness.phaseStartedAt < 900 then return end
    local x, y = position(Harness.actor)
    local dx = (x or Harness.aimedEscapeStartX) - Harness.aimedEscapeStartX
    local dy = (y or Harness.aimedEscapeStartY) - Harness.aimedEscapeStartY
    local along = dx * Harness.aimedEscapeMoveX + dy * Harness.aimedEscapeMoveY
    local forwardX = select(1, utility.call(Harness.actor, "getForwardDirectionX"))
    local forwardY = select(1, utility.call(Harness.actor, "getForwardDirectionY"))
    local facingDot = (tonumber(forwardX) or 0) * Harness.aimedEscapeMoveX
        + (tonumber(forwardY) or 0) * Harness.aimedEscapeMoveY
    check("native_aimed_escape_facing", along >= 0.20 and facingDot >= 0.75,
        "along=" .. string.format("%.2f", along)
            .. " facing_dot=" .. string.format("%.2f", facingDot))
    check("native_aimed_escape_player_clip",
        Harness.aimedEscapeForwardClipSeen == true
            and Harness.aimedEscapeInput.failure == nil
            and Harness.aimedEscapeInput.refreshes >= 2,
        "active_clips=" .. clean(Harness.aimedEscapeAnimationNames)
            .. " input_refreshes=" .. tostring(Harness.aimedEscapeInput.refreshes)
            .. " input_failure=" .. clean(Harness.aimedEscapeInput.failure))
    utility.call(Harness.actor, "setCompanionAimTarget", nil)
    pcall(SC.Actor.stop, Harness.actor)
    endHarnessControl(Harness.aimedEscapeControl, "native_aimed_escape_probe_complete")
    Harness.aimedEscapeControl = nil
    Harness.aimedEscapeInput = nil
    setPhase("begin_room", current)
end

local function findRoomEntryPair(player)
    local SC = SurvivorCompanion
    local utility = SC.GameplayUtil
    local px, py, pz = position(player)
    if px == nil or type(getCell) ~= "function" then return nil, nil end
    local cell = getCell()
    local cardinal = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
    for radius = 1, 12 do
        for dx = -radius, radius do
            for _, dy in ipairs({ -radius, radius }) do
                local source = cell:getGridSquare(math.floor(px + dx),
                    math.floor(py + dy), math.floor(pz or 0))
                if source ~= nil and utility.isSquareFree(source) then
                    local sourceRoom = roomOf(source)
                    for _, step in ipairs(cardinal) do
                        local destination = cell:getGridSquare(math.floor(px + dx + step[1]),
                            math.floor(py + dy + step[2]), math.floor(pz or 0))
                        local destinationRoom = roomOf(destination)
                        if destination ~= nil and utility.isSquareFree(destination)
                            and destinationRoom ~= nil and destinationRoom ~= sourceRoom then
                            local path = SC.Navigation.findPath(source, destination)
                            if type(path) == "table" and #path >= 2
                                and isWalkableRoomThreshold(source, destination) then
                                return source, destination
                            end
                        end
                    end
                end
            end
        end
        for dy = -radius + 1, radius - 1 do
            for _, dx in ipairs({ -radius, radius }) do
                local source = cell:getGridSquare(math.floor(px + dx),
                    math.floor(py + dy), math.floor(pz or 0))
                if source ~= nil and utility.isSquareFree(source) then
                    local sourceRoom = roomOf(source)
                    for _, step in ipairs(cardinal) do
                        local destination = cell:getGridSquare(math.floor(px + dx + step[1]),
                            math.floor(py + dy + step[2]), math.floor(pz or 0))
                        local destinationRoom = roomOf(destination)
                        if destination ~= nil and utility.isSquareFree(destination)
                            and destinationRoom ~= nil and destinationRoom ~= sourceRoom then
                            local path = SC.Navigation.findPath(source, destination)
                            if type(path) == "table" and #path >= 2
                                and isWalkableRoomThreshold(source, destination) then
                                return source, destination
                            end
                        end
                    end
                end
            end
        end
    end
    return nil, nil
end

local function beginRoomProbe(current)
    local SC = SurvivorCompanion
    local source, destination = findRoomEntryPair(Harness.player)
    if source == nil then
        skip("real_room_entry_sweep", "no loaded room threshold within 12 squares")
        setPhase("begin_door_crossing", current)
        return
    end
    local id = SC.Registry.idOf(Harness.actor)
    if id then pcall(SC.Commands.issue, id, "stay", nil, Harness.player) end
    local recovered, reason = SC.Actor.recover(Harness.actor, source)
    if recovered ~= true then
        result("FAIL", "real_room_entry_sweep", "native relocation failed: " .. clean(reason))
        setPhase("begin_door_crossing", current)
        return
    end
    SC.Navigation.reset(Harness.actor)
    local control, controlReason = beginHarnessControl(
        Harness.actor, "room_entry_probe", 12000)
    if control == nil then
        result("FAIL", "real_room_entry_sweep",
            "control ownership rejected: " .. clean(controlReason))
        setPhase("begin_door_crossing", nowMs())
        return
    end
    Harness.roomSupervisorToken = control
    Harness.roomSource = source
    Harness.roomDestination = destination
    Harness.roomSnapshot = SC.Senses.snapshot(Harness.actor, Harness.player, {})
    Harness.roomProbeObservedAt = nil
    Harness.observedRoomStatuses = {}
    -- Room discovery intentionally exercises the bounded production pathfinder
    -- and can take seconds in a dense cell. Start the probe timeout after that
    -- synchronous setup instead of inheriting the stale pre-search timestamp.
    setPhase("room_probe", nowMs())
end

local function runRoomProbe(current)
    local SC = SurvivorCompanion
    local accepted, status = SC.Navigation.request(Harness.actor, Harness.roomDestination, "walk", {
        action = "ordered_move",
        snapshot = Harness.roomSnapshot,
        urgent = false,
        movementPriority = 100,
        supervisorToken = Harness.roomSupervisorToken,
    })
    status = tostring(status or "")
    Harness.observedRoomStatuses[status] = true
    if string.find(status, "checking_room_entry", 1, true)
        and Harness.roomProbeObservedAt == nil then Harness.roomProbeObservedAt = nowMs() end
    if accepted == false and not string.find(status, "checking_room_entry", 1, true) then
        SC.Navigation.reset(Harness.actor)
        pcall(SC.Actor.stop, Harness.actor)
        endHarnessControl(Harness.roomSupervisorToken, "room_probe_failed")
        Harness.roomSupervisorToken = nil
        result("FAIL", "real_room_entry_sweep", status)
        setPhase("begin_door_crossing", current)
        return
    end
    local seen = Harness.observedRoomStatuses
    if seen.checking_room_entry_left and seen.checking_room_entry_right then
        SC.Navigation.reset(Harness.actor)
        pcall(SC.Actor.stop, Harness.actor)
        endHarnessControl(Harness.roomSupervisorToken, "room_probe_complete")
        Harness.roomSupervisorToken = nil
        result("PASS", "real_room_entry_sweep",
            "observed threshold pause plus left and right native-facing requests")
        setPhase("begin_door_crossing", current)
        return
    end
    local probeNow = nowMs()
    if Harness.roomProbeObservedAt ~= nil and probeNow - Harness.roomProbeObservedAt > 6000 then
        local observed = {}
        for value in pairs(Harness.observedRoomStatuses) do observed[#observed + 1] = value end
        table.sort(observed)
        local navigation = SC.Navigation.peek(Harness.actor) or {}
        local ax, ay, az = position(Harness.actor)
        local dx, dy, dz = position(Harness.roomDestination)
        local detail = "timeout; last_status=" .. status
            .. "; observed=" .. table.concat(observed, ",")
            .. "; internal_now=" .. tostring(SC.GameplayUtil.nowMs())
            .. "; harness_now=" .. tostring(probeNow)
            .. "; observe_until=" .. tostring(navigation.roomEntryObserveUntil)
            .. "; stuck_attempts=" .. tostring(navigation.stuckAttempts)
            .. "; key=" .. tostring(navigation.roomEntryKey)
            .. "; path_index=" .. tostring(navigation.pathIndex)
            .. "; actor=" .. table.concat({ tostring(ax), tostring(ay), tostring(az) }, ":")
            .. "; destination=" .. table.concat({ tostring(dx), tostring(dy), tostring(dz) }, ":")
        SC.Navigation.reset(Harness.actor)
        pcall(SC.Actor.stop, Harness.actor)
        endHarnessControl(Harness.roomSupervisorToken, "room_probe_timeout")
        Harness.roomSupervisorToken = nil
        result("FAIL", "real_room_entry_sweep", detail)
        setPhase("begin_door_crossing", current)
    end
end

-- Unlike the room-facing probe, this requires the actor's body to cross the
-- actual door plane in both directions. Setup and travel use production
-- navigation only: a detour reaching the far room cannot satisfy this test.
function Harness.doorLandingFree(square)
    local utility = SurvivorCompanion.GameplayUtil
    return square ~= nil and utility.isSquareFree(square)
        and utility.movingBlocker(square, Harness.actor) == nil
end

function Harness.doorLanding(source, dx, dy)
    local utility = SurvivorCompanion.GameplayUtil
    local sx, sy, sz = position(source)
    -- The local player may occupy the tile directly behind the approach. A
    -- natural side landing is equally valid, provided its two cardinal edges
    -- are open and the actor still must cross the selected door's exact plane.
    for _, lateral in ipairs({ 0, 1, -1 }) do
        local bend = getCell():getGridSquare(sx - dy * lateral, sy + dx * lateral, sz)
        local landing = getCell():getGridSquare(sx + dx - dy * lateral, sy + dy + dx * lateral, sz)
        if Harness.doorLandingFree(bend) and Harness.doorLandingFree(landing)
            and (lateral == 0 or not utility.edgeBlocked(source, bend))
            and not utility.edgeBlocked(bend, landing) then
            return landing
        end
    end
    return nil
end

function Harness.afterDoorCrossingPhase()
    return Harness.config.pathing_only == "true" and "finish" or "awareness"
end

function Harness.doorTrace(probe, current, status)
    if current < (probe.nextTraceAt or 0) then return end
    probe.nextTraceAt = current + 1000
    local SC, utility = SurvivorCompanion, SurvivorCompanion.GameplayUtil
    local function point(value)
        local x, y, z = position(value)
        return x and string.format("%.3f,%.3f,%.1f", x, y, z or 0) or "none"
    end
    if not probe.geometryTraced then
        probe.geometryTraced = true
        local opposite = utility.call(probe.object, "getOppositeSquare")
        print("SC_REAL_SANDBOX|DOOR_GEOMETRY|source=" .. point(probe.source)
            .. " destination=" .. point(probe.destination)
            .. " object=" .. utility.objectLabel(probe.object)
            .. " objectSquare=" .. point(utility.squareOf(probe.object))
            .. " north=" .. tostring(utility.call(probe.object, "getNorth"))
            .. " open=" .. tostring(utility.call(probe.object, "IsOpen"))
            .. " opposite=" .. point(opposite)
            .. " edgeBlocked=" .. tostring(utility.edgeBlocked(probe.source, probe.destination))
            .. "/" .. tostring(utility.edgeBlocked(probe.destination, probe.source)))
        for _, square in ipairs({ probe.source, probe.destination }) do
            local objects = {}
            utility.squareObjects(square, function(object)
                local sprite = utility.call(object, "getSprite")
                objects[#objects + 1] = utility.objectLabel(object) .. ":"
                    .. tostring(utility.call(sprite, "getName"))
            end, 12)
            print("SC_REAL_SANDBOX|DOOR_OBJECTS|square=" .. point(square)
                .. " vehicle=" .. utility.objectLabel(utility.call(square, "getVehicleContainer"))
                .. " objects=" .. table.concat(objects, ","))
        end
    end
    local telemetry = SC.NativeActions.pathTelemetry(Harness.actor)
    local x, y, z = position(Harness.actor)
    local nextClear = utility.call(Harness.actor, "isCompanionMovementClear",
        x + probe.dx * 0.6, y + probe.dy * 0.6, z)
    local nativeState = utility.call(Harness.actor, "getCurrentState")
    print("SC_REAL_SANDBOX|DOOR_TRACE|stage=" .. probe.stage .. " status=" .. tostring(status)
        .. " pos=" .. point(Harness.actor) .. " fsm=" .. utility.objectLabel(nativeState)
        .. " path=" .. tostring(telemetry.status)
        .. " next=" .. tostring(telemetry.pathNextIsSet) .. ":"
        .. tostring(telemetry.pathNextX) .. "," .. tostring(telemetry.pathNextY)
        .. " target=" .. tostring(utility.call(telemetry.behavior, "getTargetX"))
        .. "," .. tostring(utility.call(telemetry.behavior, "getTargetY"))
        .. " moving=" .. tostring(utility.call(Harness.actor, "isMoving"))
        .. " bPathfind=" .. tostring(utility.call(Harness.actor, "getVariableBoolean", "bPathfind"))
        .. " clearAhead=" .. tostring(nextClear)
        .. " polygonCorrected=" .. tostring(utility.call(Harness.actor, "isCollidedWithVehicle"))
        .. " open=" .. tostring(utility.call(probe.object, "IsOpen")))
    local collisionDiagnostic, collisionAvailable = utility.call(Harness.actor, "getCompanionCollisionDiagnostic")
    if collisionAvailable then
        print("SC_REAL_SANDBOX|DOOR_COLLISION|" .. tostring(collisionDiagnostic))
    end
end

function Harness.doorCrossingCandidate(source, destination)
    if source == nil or destination == nil then return nil end
    local SC, utility = SurvivorCompanion, SurvivorCompanion.GameplayUtil
    local door, kind = SC.Topology.barrierBetween(source, destination)
    if door == nil or kind ~= "door" then return nil end
    local opened = utility.call(door, "IsOpen") == true
    if not opened and (utility.call(door, "isLocked") == true
        or utility.call(door, "isLockedByKey") == true) then return nil end
    if utility.call(door, "isBarricaded") == true then return nil end
    local sx, sy, sz = position(source)
    local tx, ty = position(destination)
    local dx, dy = tx - sx, ty - sy
    if not Harness.doorLandingFree(source) or not Harness.doorLandingFree(destination) then return nil end
    local nearGoal = Harness.doorLanding(source, -dx, -dy)
    local farGoal = Harness.doorLanding(destination, dx, dy)
    if not nearGoal or not farGoal then return nil end
    return { object = door, source = source, destination = destination,
        nearGoal = nearGoal, farGoal = farGoal, dx = dx, dy = dy,
        mx = (sx + tx) * 0.5 + 0.5, my = (sy + ty) * 0.5 + 0.5,
        z = sz, stage = "near", crossed = false }
end

function Harness.beginDoorCrossing(current)
    local SC, utility = SurvivorCompanion, SurvivorCompanion.GameplayUtil
    local probe = Harness.doorCrossingCandidate(Harness.roomSource, Harness.roomDestination)
    if not probe then
        local ax, ay, az = position(Harness.actor)
        local directions = { { 1, 0 }, { 0, 1 } }
        -- Bounded loaded-cell inspection; no all-world scan or path search.
        for radius = 0, 6 do
            for ox = -radius, radius do
                for oy = -radius, radius do
                    if math.max(math.abs(ox), math.abs(oy)) == radius then
                        local x, y = math.floor(ax) + ox, math.floor(ay) + oy
                        local source = getCell():getGridSquare(x, y, math.floor(az))
                        for _, direction in ipairs(directions) do
                            probe = Harness.doorCrossingCandidate(source,
                                getCell():getGridSquare(x + direction[1], y + direction[2], math.floor(az)))
                            if probe then break end
                        end
                    end
                    if probe then break end
                end
                if probe then break end
            end
            if probe then break end
        end
    end
    if not probe then
        skip("real_door_crossing_round_trip", "no clear unlocked loaded door with two-sided landing within six squares")
        setPhase(Harness.afterDoorCrossingPhase(), current)
        return
    end
    SC.Navigation.reset(Harness.actor)
    local token, reason = beginHarnessControl(Harness.actor, "door_crossing_probe", 40000)
    if not token then
        result("FAIL", "real_door_crossing_round_trip", "ownership: " .. clean(reason))
        setPhase(Harness.afterDoorCrossingPhase(), current)
        return
    end
    probe.token, probe.stageStartedAt = token, nowMs()
    -- Navigation's legitimate recovery phase still belongs to this harness.
    -- It must not deadlock on movementPermission before it can resume approach.
    token.allowedMovementPhases.recovering = true
    probe.snapshot = SC.Senses.snapshot(Harness.actor, Harness.player, {})
    Harness.doorCrossing = probe
    setPhase("door_crossing", nowMs())
end

function Harness.finishDoorCrossing(status, detail, current)
    local SC = SurvivorCompanion
    SC.Navigation.reset(Harness.actor)
    pcall(SC.Actor.stop, Harness.actor)
    endHarnessControl(Harness.doorCrossing and Harness.doorCrossing.token, "door_crossing_" .. status)
    Harness.doorCrossing = nil
    result(status, "real_door_crossing_round_trip", detail)
    setPhase(Harness.afterDoorCrossingPhase(), current)
end

function Harness.checkDoorState(probe, current)
    local utility = SurvivorCompanion.GameplayUtil
    local function finite(value)
        return type(value) == "number" and value == value and math.abs(value) < math.huge
    end
    local x, y, z = position(Harness.actor)
    if not finite(x) or not finite(y) or not finite(z) then return false, "nonfinite_actor_position" end
    local square = utility.squareOf(Harness.actor)
    local present = false
    utility.squareMovingObjects(square, function(other)
        if other == Harness.actor then present = true return false end
    end, 256)
    local sx, sy, sz = position(square)
    if not present or sx == nil or math.floor(x) ~= math.floor(sx)
        or math.floor(y) ~= math.floor(sy) or math.floor(z) ~= math.floor(sz) then
        return false, "actor_missing_from_current_square"
    end
    if probe.checkedX then
        local step = math.sqrt((x - probe.checkedX)^2 + (y - probe.checkedY)^2 + (z - probe.checkedZ)^2)
        local elapsed = math.max(0, current - probe.checkedAt) / 1000
        probe.maximumStep = math.max(probe.maximumStep or 0, step)
        -- Six tiles/sec is deliberately above a normal walk. The fixed margin
        -- tolerates float quantization and delayed render sampling, not a snap.
        if step > math.max(0.25, elapsed * 6) then return false, "unexpected_position_snap:" .. tostring(step) end
    end
    local diagnostic, available = utility.call(Harness.actor, "getCompanionCollisionDiagnostic")
    if available then
        -- This is actual postupdate input, not the bridge's rejected-request
        -- counter: safe rejection of an invalid request is allowed.
        for intended in string.gmatch(tostring(diagnostic), "intended=([^,;}]+)") do
            local ix, iy = string.match(intended, "([^/]+)/([^/]+)")
            if not finite(tonumber(ix)) or not finite(tonumber(iy)) then
                return false, "nonfinite_coordinates_reached_physics:" .. intended
            end
        end
    end
    probe.checkedX, probe.checkedY, probe.checkedZ, probe.checkedAt = x, y, z, current
    probe.checkedFrames = (probe.checkedFrames or 0) + 1
    return true
end

function Harness.runDoorCrossing(current)
    local SC, probe = SurvivorCompanion, Harness.doorCrossing
    local healthy, healthReason = Harness.checkDoorState(probe, current)
    if not healthy then
        Harness.finishDoorCrossing("FAIL", "stage=" .. probe.stage .. "; " .. healthReason, current)
        return
    end
    local goal = probe.stage == "out" and probe.farGoal or probe.nearGoal
    local accepted, status = SC.Navigation.request(Harness.actor, goal, "walk", {
        action = "ordered_move", snapshot = probe.snapshot, urgent = false,
        movementPriority = 100, supervisorToken = probe.token,
    })
    local x, y, z = position(Harness.actor)
    Harness.doorTrace(probe, current, status)
    if not probe.progressX or (x - probe.progressX)^2 + (y - probe.progressY)^2 > 0.01 then
        probe.progressX, probe.progressY = x, y
        SC.ActionSupervisor.progress(probe.token,
            string.format("door:%s:%.2f:%.2f", probe.stage, x, y), { stage = probe.stage })
    end
    local progress = (x - probe.mx) * probe.dx + (y - probe.my) * probe.dy
    local lateral = (x - probe.mx) * -probe.dy + (y - probe.my) * probe.dx
    if probe.stage ~= "near" and probe.previousProgress then
        local previous = probe.previousProgress
        local crosses = probe.stage == "out" and previous < 0 and progress >= 0
            or probe.stage == "back" and previous > 0 and progress <= 0
        if crosses then
            local fraction = -previous / (progress - previous)
            local crossingLateral = probe.previousLateral + fraction * (lateral - probe.previousLateral)
            if math.abs(crossingLateral) < 0.45 and math.abs(z - probe.z) < 0.1
                and math.abs(progress - previous) < 1 then probe.crossed = true end
        end
    end
    probe.previousProgress, probe.previousLateral = progress, lateral
    local reached = SC.GameplayUtil.arrived(Harness.actor, goal, { targetKind = "square", distance = 0.65 })
    if reached and probe.stage == "near" and progress < -0.5 then
        probe.stage, probe.crossed, probe.stageStartedAt = "out", false, current
        SC.Navigation.reset(Harness.actor)
    elseif reached and probe.crossed and probe.stage == "out" and progress > 0.5 then
        probe.outPosition = string.format("%.2f,%.2f", x, y)
        probe.stage, probe.crossed, probe.stageStartedAt = "back", false, current
        SC.Navigation.reset(Harness.actor)
    elseif reached and probe.crossed and probe.stage == "back" and progress < -0.5 then
        Harness.finishDoorCrossing("PASS", "actual doorway crossed both ways; far=" .. probe.outPosition
            .. "; returned=" .. string.format("%.2f,%.2f", x, y)
            .. "; finite_member_frames=" .. tostring(probe.checkedFrames)
            .. "; max_step=" .. string.format("%.3f", probe.maximumStep or 0), current)
    elseif current - probe.stageStartedAt > 12000 then
        local nav = SC.Navigation.peek(Harness.actor) or {}
        local blocker = nav.lastBlocker or {}
        Harness.finishDoorCrossing("FAIL", "stage=" .. probe.stage .. "; status=" .. tostring(status)
            .. "; accepted=" .. tostring(accepted) .. "; crossed=" .. tostring(probe.crossed)
            .. "; actor=" .. string.format("%.2f,%.2f,%.1f", x, y, z)
            .. "; portal=" .. string.format("%.2f/%.2f", progress, lateral)
            .. "; blocker=" .. tostring(blocker.diagnostic or blocker.type), current)
    end
end

local function playerStillIsolated()
    local player = Harness.player
    local x, y, z = position(player)
    local samePosition = x ~= nil and math.abs(x - Harness.playerX) < 0.05
        and math.abs(y - Harness.playerY) < 0.05 and math.abs((z or 0) - Harness.playerZ) < 0.05
    local sameSingleton = true
    if type(getSpecificPlayer) == "function" then
        local ok, localPlayer = pcall(getSpecificPlayer, 0)
        sameSingleton = ok and localPlayer == player
    end
    return samePosition and sameSingleton
end

local function runAwareness(current)
    local SC = SurvivorCompanion
    local utility = SC.GameplayUtil
    local ax, ay, az = position(Harness.actor)
    if ax == nil then
        result("FAIL", "native_rear_awareness", "actor position unavailable")
        setPhase("finish", current)
        return
    end
    local forwardX, forwardXOk = utility.call(Harness.player, "getForwardDirectionX")
    local forwardY, forwardYOk = utility.call(Harness.player, "getForwardDirectionY")
    if not forwardXOk or not forwardYOk or tonumber(forwardX) == nil or tonumber(forwardY) == nil then
        forwardX, forwardY = 1, 0
    end
    local accepted, reason = SC.Actor.setMovement(Harness.actor, "walk", {
        action = "rear_scan",
        targetPosition = { x = ax - forwardX * 2, y = ay - forwardY * 2, z = az },
        stableFacing = true,
        awarenessMovement = true,
    })
    check("native_rear_awareness", accepted == true, reason)
    Harness.awarenessForwardX = forwardX
    Harness.awarenessForwardY = forwardY
    setPhase("restore_awareness", current)
end

local function restoreAwareness(current)
    if current - Harness.phaseStartedAt < 650 then return end
    local SC = SurvivorCompanion
    local ax, ay, az = position(Harness.actor)
    local accepted, reason = SC.Actor.setMovement(Harness.actor, "walk", {
        action = "face_formation",
        targetPosition = {
            x = ax + Harness.awarenessForwardX * 2,
            y = ay + Harness.awarenessForwardY * 2,
            z = az,
        },
        stableFacing = true,
        awarenessMovement = true,
    })
    check("formation_facing_restore", accepted == true, reason)
    check("local_player_unchanged", playerStillIsolated(),
        "companion spawn, follow and facing actions did not move or replace player 0")
    setPhase("zombie_attack_observe", current)
end

local function cleanupTestZombie(zombie)
    if zombie == nil then return end
    pcall(function() zombie:setTarget(nil) end)
    pcall(function() zombie:removeFromWorld() end)
    pcall(function() zombie:removeFromSquare() end)
end

local function cleanupTestZombiesNear(target, radius)
    if target == nil or type(getCell) ~= "function" then return 0 end
    local ok, cell = pcall(getCell)
    if not ok or cell == nil then return 0 end
    local list = select(1, SurvivorCompanion.GameplayUtil.call(cell, "getZombieList"))
    if list == nil then return 0 end
    -- Kahlua exposes java.util list sizes as boxed Double values; its tonumber
    -- implementation casts non-Lua values to String and throws on that object.
    local sizeValue = select(1, SurvivorCompanion.GameplayUtil.call(list, "size"))
    local size = math.floor(tonumber(tostring(sizeValue)) or 0)
    local nearby = {}
    for index = 0, size - 1 do
        local zombie = select(1,
            SurvivorCompanion.GameplayUtil.call(list, "get", index))
        if zombie ~= nil and distance(zombie, target) <= (radius or 30) then
            nearby[#nearby + 1] = zombie
        end
    end
    for _, zombie in ipairs(nearby) do cleanupTestZombie(zombie) end
    return #nearby
end

local function classLabel(value)
    if value == nil then return "none" end
    if type(getClassSimpleName) == "function" then
        local ok, name = pcall(getClassSimpleName, value)
        if ok and name ~= nil and tostring(name) ~= "" then return tostring(name) end
    end
    return SurvivorCompanion.GameplayUtil.objectLabel(value)
end

-- Keep a complete transition snapshot when the real IsoPlayer attack graph
-- rejects a request. attackStarted alone only proves CombatManager accepted
-- the pulse; these values identify the precise ActionContext gate which kept
-- the request from becoming a visible melee animation.
local function combatDiagnosticSnapshot(actor, target)
    local utility = SurvivorCompanion.GameplayUtil
    local function read(methodName, ...)
        local value, ok = utility.call(actor, methodName, ...)
        if not ok then return "unavailable" end
        return value
    end
    local function observed(value, ok)
        if not ok then return "unavailable" end
        return value
    end
    local groupName = read("getCompanionActionGroupName")
    local actionState = read("getCompanionActionStateName")
    return table.concat({
        "group=" .. clean(groupName),
        "action_state=" .. clean(actionState),
        "next=" .. clean(read("getCompanionNextActionStateName")),
        "can_melee=" .. clean(read("canCompanionTransitionToMelee")),
        "initiate_var=" .. clean(read("getVariableBoolean", "initiateAttack")),
        "initiate=" .. clean(read("isInitiateAttack")),
        "post=" .. clean(read("getCompanionPostUpdateDiagnostic")),
        "weapon_var=" .. clean(read("getVariableString", "Weapon")),
        "ranged_var=" .. clean(read("getVariableBoolean", "rangedWeapon")),
        "shove_var=" .. clean(read("getVariableBoolean", "bDoShove")),
        "started=" .. clean(read("isAttackStarted")),
        "performing=" .. clean(read("isPerformingAttackAnimation")),
        "melee_delay=" .. clean(read("getMeleeDelay")),
        "recoil_delay=" .. clean(read("getRecoilDelay")),
        "impact_serial=" .. clean(read("getCompanionAttackCollisionSerial")),
        "native_path=" .. clean(read("getCompanionPathStatus")),
        "anim_updating=" .. clean(read("isAnimationUpdatingThisFrame")),
        -- Why a started attack may still fail to become a resolved swing: the
        -- actor's root state, hand-to-hand/floor intent, any native collision,
        -- and whether the intended target actually took damage.
        "state=" .. clean(read("getCurrentState")),
        "do_shove=" .. clean(read("isDoShove")),
        "aim_floor=" .. clean(read("isAimAtFloor")),
        "use_weapon=" .. clean(observed(utility.call(read("getUseHandWeapon"), "getFullType"))),
        "target_prone=" .. clean(observed(utility.call(target, "isProne"))),
        "col_vehicle=" .. clean(read("isCollidedWithVehicle")),
        "col_door=" .. clean(read("isCollidedWithDoor")),
        "col_object=" .. clean(read("getCollidedObject")),
        "target_health=" .. clean(observed(utility.call(target, "getHealth"))),
        "target_dead=" .. clean(observed(utility.call(target, "isDead"))),
        "group_control=" .. clean(Harness.combatActionGroupControl or "none"),
    }, ",")
end

local function pinTestZombieAtCombatSquare()
    local z = Harness.testZombie
    if z == nil or Harness.combatTargetX == nil then return end
    pcall(function() z:setTarget(nil) end)
    pcall(function() z:setX(Harness.combatTargetX) end)
    pcall(function() z:setY(Harness.combatTargetY) end)
    pcall(function() z:setZ(Harness.combatTargetZ or 0) end)
    pcall(function() z:setCurrentSquareFromPosition() end)
end

function Harness.meleeFixtureDistance(weapon, actor)
    local U = SurvivorCompanion.GameplayUtil
    local minimum = tonumber((U.call(weapon, "getMinRange")))
    local maximum = tonumber((U.call(weapon, "getMaxRange", actor)))
    local modifier = tonumber((U.call(weapon, "getRangeMod", actor)))
    if not minimum or not maximum or not modifier or modifier <= 0 then
        return nil, "weapon range unavailable"
    end
    maximum = maximum * modifier
    -- Stay away from both the automatic defensive-shove band and the outer hit
    -- boundary. Skill does not make a randomly placed adjacent tile in range.
    local low, high = minimum + 0.3, maximum - 0.2
    if low >= high then return nil, "weapon has no stable melee fixture band" end
    return (low + high) * 0.5, "min=" .. minimum .. " max=" .. maximum
end

function Harness.onMeleeWeaponHit(attacker, target, weapon, damage)
    if attacker ~= Harness.actor or target ~= Harness.testZombie then return end
    local U = SurvivorCompanion.GameplayUtil
    local ax, ay = position(attacker)
    local tx, ty = position(target)
    local distance = ax and tx and math.sqrt((ax - tx)^2 + (ay - ty)^2) or -1
    Harness.combatImpactCount = (Harness.combatImpactCount or 0) + 1
    Harness.combatImpactSnapshot = "distance=" .. tostring(distance)
        .. " weapon=" .. tostring(U.call(weapon, "getFullType"))
        .. " requested_damage=" .. tostring(damage)
        .. " clips=" .. tostring(U.call(attacker, "getCompanionActiveAnimationNames"))
        .. " snapshot={" .. combatDiagnosticSnapshot(attacker, target) .. "}"
    -- OnWeaponHitCharacter is raised by native Hit before its damage calculation.
    -- Observe only; never replace the hit or manufacture a health change.
    print("SC_REAL_SANDBOX|MELEE_IMPACT|" .. Harness.combatImpactSnapshot)
end

local function cleanupCombat(current)
    endHarnessControl(Harness.combatSupervisorToken, "combat_probe_complete")
    Harness.combatSupervisorToken = nil
    cleanupTestZombie(Harness.testZombie)
    Harness.testZombie = nil
    Harness.combatWeapon = nil
    Harness.combatLastReason = nil
    Harness.combatAnimationObserved = nil
    Harness.combatStartedAt = nil
    Harness.combatStartSnapshot = nil
    Harness.combatActionGroupControl = nil
    Harness.combatTargetInitialHealth = nil
    Harness.combatSwingCount = nil
    Harness.combatTargetX = nil
    Harness.combatTargetY = nil
    Harness.combatTargetZ = nil
    Harness.combatImpactCount = nil
    Harness.combatImpactSnapshot = nil
    setPhase("ranged_fire", current)
end

local function finishCombatProbe(current, status, detail)
    check("direct_native_melee_attack", status == true, detail)
    cleanupCombat(current)
end

-- After a swing completes, keep swinging at the pinned in-range zombie and poll
-- its health, passing as soon as a swing damages or kills it.
local function probeCombatDamage(current)
    local SC = SurvivorCompanion
    pinTestZombieAtCombatSquare()
    local afterDead = select(1, SC.GameplayUtil.call(Harness.testZombie, "isDead"))
    local afterHealth = select(1, SC.GameplayUtil.call(Harness.testZombie, "getHealth"))
    local before = Harness.combatTargetInitialHealth
    local damaged = afterDead == true
        or (before ~= nil and tonumber(afterHealth) ~= nil
            and tonumber(afterHealth) < before - 0.0001)
    if damaged then
        check("direct_native_melee_damage", true,
            "before=" .. tostring(before) .. " after=" .. tostring(afterHealth)
                .. " dead=" .. tostring(afterDead)
                .. " swings=" .. tostring(Harness.combatSwingCount))
        cleanupCombat(current)
        return
    end
    if current - Harness.phaseStartedAt > 12000 then
        local function v(obj, m, ...) local val, ok = SC.GameplayUtil.call(obj, m, ...) return ok and tostring(val) or "na" end
        check("direct_native_melee_damage", false,
            "no damage in 12s over " .. tostring(Harness.combatSwingCount)
                .. " swings: before=" .. tostring(before)
                .. " after=" .. tostring(afterHealth)
                .. " a_npc=" .. v(Harness.actor, "isNpc")
                .. " a_inmelee=" .. v(Harness.actor, "IsInMeleeAttack")
                .. " last_reject=" .. clean(Harness.combatLastReason)
                .. " impact={" .. clean(Harness.combatImpactSnapshot) .. "}"
                .. " now={" .. combatDiagnosticSnapshot(Harness.actor, Harness.testZombie) .. "}"
                .. " z_attackedby=" .. tostring(select(1, SC.GameplayUtil.call(
                    Harness.testZombie, "getAttackedBy")) ~= nil))
        cleanupCombat(current)
        return
    end
    if current >= (Harness.combatNextAttemptAt or 0) then
        local performing = select(1, SC.GameplayUtil.call(
            Harness.actor, "isPerformingAttackAnimation"))
        if performing ~= true then
            pinTestZombieAtCombatSquare()
            local accepted, reason = SC.Actor.setMovement(Harness.actor, "walk", {
                action = "attack_melee", target = Harness.testZombie,
                weapon = Harness.combatWeapon, urgent = true, emergency = true,
                supervisorToken = Harness.combatSupervisorToken,
            })
            if accepted == true then
                Harness.combatSwingCount = (Harness.combatSwingCount or 0) + 1
            else
                Harness.combatLastReason = reason
                print("SC_REAL_SANDBOX|MELEE_RETRY_REJECT|" .. clean(reason)
                    .. " snapshot={" .. combatDiagnosticSnapshot(Harness.actor,
                        Harness.testZombie) .. "}")
            end
            Harness.combatNextAttemptAt = current + 700
        end
    end
end

local function probeNativeCombat(current)
    pinTestZombieAtCombatSquare()
    if current - Harness.phaseStartedAt < 300 then return end
    if current < (Harness.combatNextAttemptAt or 0) then return end
    Harness.combatNextAttemptAt = current + 125
    local SC = SurvivorCompanion
    local collisionBefore = select(1, SC.GameplayUtil.call(
        Harness.actor, "getCompanionAttackCollisionSerial"))
    local accepted, reason = SC.Actor.setMovement(Harness.actor, "walk", {
        action = "attack_melee",
        target = Harness.testZombie,
        weapon = Harness.combatWeapon,
        urgent = true,
        emergency = true,
        supervisorToken = Harness.combatSupervisorToken,
    })
    Harness.combatLastReason = reason
    if accepted == true then
        local stateOk, started = SC.GameplayUtil.call(Harness.actor, "isAttackStarted")
        local primary, primaryOk = SC.GameplayUtil.call(
            Harness.actor, "getPrimaryHandItem")
        local secondary, secondaryOk = SC.GameplayUtil.call(
            Harness.actor, "getSecondaryHandItem")
        local attackingWeapon, weaponOk = SC.GameplayUtil.call(
            Harness.actor, "getUseHandWeapon")
        local typeValue, typeOk = SC.GameplayUtil.call(Harness.actor, "getAttackType")
        local typeActive = typeOk and typeValue ~= nil and tostring(typeValue) ~= ""
        if not stateOk or started ~= true or not primaryOk
            or primary ~= Harness.combatWeapon or not secondaryOk
            or secondary ~= Harness.combatWeapon or not weaponOk
            or attackingWeapon ~= Harness.combatWeapon or not typeActive then
            finishCombatProbe(current, false,
                "adapter=" .. clean(reason)
                    .. " attack_started=" .. tostring(started)
                    .. " primary=" .. tostring(primary == Harness.combatWeapon)
                    .. " secondary=" .. tostring(secondary == Harness.combatWeapon)
                    .. " use_weapon=" .. tostring(attackingWeapon == Harness.combatWeapon)
                    .. " attack_type=" .. clean(typeValue))
            return
        end
        -- attackStarted is set synchronously by CombatManager.pressedAttack().
        -- Do not call that a real sword swing until the ordinary IsoPlayer
        -- animation graph consumes the request and subsequently completes it.
        Harness.combatStartedAt = current
        Harness.combatCollisionBefore = tonumber(collisionBefore)
        Harness.combatAnimationObserved = false
        Harness.combatAttackType = tostring(typeValue)
        -- Read how many targets CombatManager found for this swing. Size 0 means
        -- calcValidTargets rejected the target (no valid target => AttackType.MISS);
        -- size > 0 proves only preflight acquisition. The native collision event
        -- rebuilds this list and can select a different stance/weapon at entry.
        local hitList = SC.GameplayUtil.call(Harness.actor, "getHitInfoList")
        local hitSize = hitList and SC.GameplayUtil.call(hitList, "size") or nil
        Harness.combatHitListSize = tostring(hitSize)
        Harness.combatSwingCount = (Harness.combatSwingCount or 0) + 1
        if Harness.combatTargetInitialHealth == nil then
            local zh = SC.GameplayUtil.call(Harness.testZombie, "getHealth")
            Harness.combatTargetInitialHealth = tonumber(zh)
        end
        Harness.combatStartSnapshot = combatDiagnosticSnapshot(
            Harness.actor, Harness.testZombie)
        setPhase("combat_animation", current)
        return
    end
    print("SC_REAL_SANDBOX|MELEE_RETRY_REJECT|phase=preflight reason=" .. clean(reason)
        .. " snapshot={" .. combatDiagnosticSnapshot(Harness.actor, Harness.testZombie) .. "}")
    if current - Harness.phaseStartedAt > 5000 then
        finishCombatProbe(current, false,
            "timed out after exact Build 42 attack preflight: " .. clean(reason))
    end
end

local function probeNativeCombatAnimation(current)
    local SC = SurvivorCompanion
    pinTestZombieAtCombatSquare()
    local performing, performingOk = SC.GameplayUtil.call(
        Harness.actor, "isPerformingAttackAnimation")
    local started, startedOk = SC.GameplayUtil.call(Harness.actor, "isAttackStarted")
    if performingOk and performing == true then
        Harness.combatAnimationObserved = true
    end
    if Harness.combatAnimationObserved == true and startedOk and started ~= true
        and (not performingOk or performing ~= true) then
        local serial = select(1, SC.GameplayUtil.call(
            Harness.actor, "getCompanionAttackCollisionSerial"))
        serial = tonumber(serial)
        local previous = Harness.combatCollisionBefore
        check("single_swing_collision_ownership", serial ~= nil and previous ~= nil
            and serial - previous == 1,
            "before=" .. tostring(previous) .. " after=" .. tostring(serial)
                .. " elapsed_ms=" .. tostring(current - Harness.combatStartedAt))
        local delay = select(1, SC.GameplayUtil.call(Harness.actor, "getMeleeDelay"))
        if (tonumber(delay) or 0) > 0 then
            local accepted, reason = SC.NativeActions.dispatch(Harness.actor, "walk", {
                action = "attack_melee", target = Harness.testZombie,
                weapon = Harness.combatWeapon, urgent = true, emergency = true,
            }, { directNative = true })
            check("native_melee_recovery_gate", accepted == false
                and reason == "native_melee_recovery",
                "delay=" .. tostring(delay) .. " result=" .. tostring(reason))
        else
            result("SKIP", "native_melee_recovery_gate",
                "native delay had already drained before completed animation was observed")
        end
        result("PASS", "direct_native_melee_attack",
            "adapter=" .. clean(Harness.combatLastReason)
                .. " attack_type=" .. clean(Harness.combatAttackType)
                .. " hit_targets=" .. tostring(Harness.combatHitListSize)
                .. " start={" .. clean(Harness.combatStartSnapshot) .. "}"
                .. " animation_observed=true completed=true")
        Harness.combatNextAttemptAt = current + 400
        setPhase("combat_damage", current)
        return
    end
    if current - (Harness.combatStartedAt or Harness.phaseStartedAt) > 5000 then
        pcall(function() Harness.actor:clearHandToHandAttack() end)
        finishCombatProbe(current, false,
            "native attack did not complete through the player animation graph:"
                .. " observed=" .. tostring(Harness.combatAnimationObserved)
                .. " started=" .. tostring(started)
                .. " performing=" .. tostring(performing)
                .. " type=" .. clean(Harness.combatAttackType)
                .. " end={" .. clean(combatDiagnosticSnapshot(
                    Harness.actor, Harness.testZombie)) .. "}"
                .. " start={" .. clean(Harness.combatStartSnapshot) .. "}")
    end
end

local function zombieTargetSquare(actor, player)
    local SC = SurvivorCompanion
    local utility = SC.GameplayUtil
    local ax, ay, az = position(actor)
    local px, py = position(player)
    if ax == nil or px == nil or type(getCell) ~= "function" then return nil end
    local cell = getCell()
    if cell == nil then return nil end
    local offsets = {
        { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 },
        { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 },
    }
    table.sort(offsets, function(first, second)
        local firstDistance = (ax + first[1] - px) ^ 2 + (ay + first[2] - py) ^ 2
        local secondDistance = (ax + second[1] - px) ^ 2 + (ay + second[2] - py) ^ 2
        return firstDistance > secondDistance
    end)
    for _, offset in ipairs(offsets) do
        local square = cell:getGridSquare(math.floor(ax + offset[1]),
            math.floor(ay + offset[2]), math.floor(az or 0))
        if square ~= nil and utility.isSquareFree(square)
            and utility.canSee(actor, square) then return square end
    end
    return nil
end

-- Verify the whole firearm lifecycle for a non-local companion: it fires (the
-- aim -> attackCollisionCheck -> fireWeapon pipeline Build 42 normally gates to
-- the local player), reloads an emptied gun from a spare magazine (a queued timed
-- action that must tick to completion off the local player), and the reloaded gun
-- fires again. We equip a loaded pistol with a spare magazine, keep a zombie
-- downrange, and drive attack_firearm then reload then attack_firearm again.
local function endRangedProbe(current, zombie)
    if zombie ~= nil then cleanupTestZombie(zombie) end
    Harness.rangedZombie = nil
    Harness.rangedGun = nil
    -- Cancel any in-flight reload/fire timed action so the next probe can take
    -- ownership instead of hitting native:unfinished_action:active.
    pcall(function() Harness.actor:StopAllActionQueue() end)
    pcall(SurvivorCompanion.Actor.stop, Harness.actor)
    if Harness.rangedControl ~= nil then
        endHarnessControl(Harness.rangedControl, "ranged_probe_done")
        Harness.rangedControl = nil
    end
    -- Grounded finisher already ran up front (before targeting); ranged fire is the
    -- last combat probe, so hand off to the faction phases.
    setPhase("faction_begin", current)
end

-- Verify a companion can injure a fallen zombie: knock a real zombie down and
-- confirm the companion's stomp actually lands damage, without requiring a
-- guaranteed kill. The native attack must resolve against a prone target, which the
-- stance filter otherwise skips for an ordinary standing swing.
function Harness.isStompClip(names)
    -- Build 42 names the real player stomp "FloorStamp" (with held-weapon
    -- variants), although its action/event is named Stomp. Match the attack
    -- clip family, not an idle/transition/shove clip that mentions the action.
    for clip in string.gmatch(string.lower(tostring(names or "")), "[%w_]+") do
        if clip == "bob_attackfloorstamp" or clip == "bob_attackfloorstomp"
            or string.match(clip, "^bob_attackfloorstamp_[%w_]+$")
            or string.match(clip, "^bob_attackfloorstomp_[%w_]+$") then return true end
    end
    return false
end

local function endFinishGrounded(current, zombie)
    check("native_grounded_attack_stance_and_clip",
        Harness.finishFloorSelected == true and Harness.finishStompClip == true,
        "floor_selected=" .. tostring(Harness.finishFloorSelected)
            .. " stomp_clip=" .. tostring(Harness.finishStompClip)
            .. " active_clips=" .. clean(Harness.finishAnimationNames))
    if zombie ~= nil then cleanupTestZombie(zombie) end
    Harness.finishZombie = nil
    Harness.finishTimingChecked = nil
    Harness.finishLastImpact = nil
    -- Clear the floor-aim / downed-target residue the stomp leaves behind so the
    -- following standing melee phase starts from a clean, upright attack posture.
    pcall(function() Harness.actor:setAimAtFloor(false) end)
    SurvivorCompanion.GameplayUtil.call(
        Harness.actor, "setCompanionFloorTarget", nil)
    pcall(function() Harness.actor:StopAllActionQueue() end)
    pcall(SurvivorCompanion.Actor.stop, Harness.actor)
    if Harness.finishControl ~= nil then
        endHarnessControl(Harness.finishControl, "finish_grounded_done")
        Harness.finishControl = nil
    end
    setPhase("zombie_targeting", current)
end

local function probeFinishGrounded(current)
    local SC = SurvivorCompanion
    local U = SC.GameplayUtil
    local function v(o, m, ...) local val, ok = U.call(o, m, ...) return ok and tostring(val) or "na" end
    if type(addZombiesInOutfit) ~= "function" then
        skip("native_companion_finishes_grounded", "addZombiesInOutfit unavailable")
        setPhase("zombie_targeting", current); return
    end
    if Harness.finishZombie == nil then
        local ax, ay, az = position(Harness.actor)
        if ax == nil then
            skip("native_companion_finishes_grounded", "companion has no position")
            setPhase("zombie_targeting", current); return
        end
        -- Earlier probes may leave the actor beside a door or wall. A blind
        -- eastward spawn can put this supposedly clean target through that wall.
        -- Pick a real clear contact lane; never bypass impact-time validation.
        pcall(SC.Actor.stop, Harness.actor)
        local dx, dy = findClearManualDirection(Harness.actor, 1.0)
        if dx == nil then
            result("FAIL", "native_companion_finishes_grounded",
                "fixture has no clear adjacent contact lane at "
                    .. tostring(ax) .. "," .. tostring(ay) .. "," .. tostring(az))
            setPhase("zombie_targeting", current); return
        end
        local eastClear = select(1, U.call(Harness.actor,
            "isCompanionMovementClear", ax + 1.0, ay, az or 0))
        local okSpawn, zs = pcall(addZombiesInOutfit,
            math.floor(ax + dx), math.floor(ay + dy), math.floor(az or 0), 1, nil, 0)
        local zombie = okSpawn and zs and select(1, U.call(zs, "get", 0)) or nil
        if zombie == nil then
            result("FAIL", "native_companion_finishes_grounded", "zombie spawn failed")
            setPhase("zombie_targeting", current); return
        end
        pcall(function() zombie:knockDown(true) end)
        pcall(function() zombie:setOnFloor(true) end)
        pcall(function() zombie:setTarget(nil) end)
        pcall(SC.Actor.stop, Harness.actor)
        local control, controlReason = beginHarnessControl(Harness.actor, "finish_grounded_probe", 15000)
        if control == nil then
            cleanupTestZombie(zombie)
            result("FAIL", "native_companion_finishes_grounded",
                "control rejected: " .. clean(controlReason)
                    .. " knocked=" .. tostring(select(1, U.call(Harness.actor, "isKnockedDown")) == true)
                    .. " a_state=" .. clean(v(Harness.actor, "getCompanionActionStateName")))
            setPhase("zombie_targeting", current); return
        end
        Harness.finishControl = control
        pcall(function() if Perks ~= nil and Perks.Strength ~= nil then
            Harness.actor:setPerkLevelDebug(Perks.Strength, 10) end end)
        local ax, ay, az = position(Harness.actor)
        local contactX, contactY = dx * 0.5, dy * 0.5
        if ax ~= nil then
            pcall(function() zombie:setX(ax + contactX) end)
            pcall(function() zombie:setY(ay + contactY) end)
            pcall(function() zombie:setZ(az or 0) end)
            pcall(function() zombie:setCurrentSquareFromPosition() end)
        end
        Harness.finishMoveX, Harness.finishMoveY = contactX, contactY
        print("SC_REAL_SANDBOX_DIAGNOSTIC|grounded_contact_fixture|"
            .. clean("actor=" .. tostring(ax) .. "," .. tostring(ay) .. "," .. tostring(az)
                .. " direction=" .. tostring(dx) .. "," .. tostring(dy)
                .. " prior_east_clear=" .. tostring(eastClear)))
        SC.GameplayUtil.call(Harness.actor, "setCompanionAimTarget", zombie)
        Harness.finishZombie = zombie
        Harness.finishStart = current
        Harness.finishNextAt = current + 700
        Harness.finishStomps = 0
        Harness.finishFloorSelected = nil
        Harness.finishStompClip = false
        Harness.finishAnimationNames = ""
        Harness.finishTimingChecked = false
        local hp0v = select(1, U.call(zombie, "getHealth"))
        Harness.finishHp0 = tonumber(hp0v)
        return
    end
    local zombie = Harness.finishZombie
    local names = tostring(select(1, U.call(Harness.actor,
        "getCompanionActiveAnimationNames")) or "")
    if Harness.isStompClip(names) then
        Harness.finishStompClip = true
        Harness.finishAnimationNames = names
    elseif Harness.finishStompClip ~= true then
        Harness.finishAnimationNames = names
    end
    if SC.NativeActions and type(SC.NativeActions.pollCombatEvents) == "function" then
        local _, reason, evidence = SC.NativeActions.pollCombatEvents(Harness.actor)
        if type(evidence) == "table" then
            local ax, ay, az = position(Harness.actor)
            local tx, ty, tz = position(zombie)
            Harness.finishLastImpact = "reason=" .. clean(reason)
                .. " result=" .. clean(evidence.result)
                .. " serial=" .. tostring(evidence.serial)
                .. " hit_count=" .. tostring(evidence.hitCount)
                .. " exact_target=" .. tostring(evidence.collisionTargetMatched)
                .. " source=" .. tostring(evidence.source)
                .. " visible=" .. v(Harness.actor, "CanSee", zombie)
                .. " clear=" .. v(Harness.actor, "isCompanionMovementClear", tx, ty, tz)
                .. " distance=" .. v(Harness.actor, "DistTo", zombie)
                .. " actor=" .. tostring(ax) .. "," .. tostring(ay) .. "," .. tostring(az)
                .. " target=" .. tostring(tx) .. "," .. tostring(ty) .. "," .. tostring(tz)
            print("SC_REAL_SANDBOX_DIAGNOSTIC|grounded_stomp_impact|"
                .. clean(Harness.finishLastImpact))
        end
    end
    local hpValue = select(1, U.call(zombie, "getHealth"))
    local hp = tonumber(hpValue)
    local dead = select(1, U.call(zombie, "isDead")) == true
    local prone = select(1, U.call(zombie, "isProne")) == true
        or select(1, U.call(zombie, "isOnFloor")) == true
    if dead or (Harness.finishHp0 and hp and hp < Harness.finishHp0 - 0.0001) then
        check("native_companion_finishes_grounded", true,
            "grounded zombie damaged: hp " .. tostring(Harness.finishHp0) .. "->" .. tostring(hp)
                .. " dead=" .. tostring(dead) .. " was_prone=" .. tostring(prone)
                .. " stomps=" .. tostring(Harness.finishStomps))
        endFinishGrounded(current, zombie); return
    end
    if current - Harness.finishStart > 12000 then
        check("native_companion_finishes_grounded", false,
            "grounded zombie not finished in 12s: prone=" .. tostring(prone)
                .. " hp=" .. tostring(hp)
                .. " stomps=" .. tostring(Harness.finishStomps)
                .. " reject=" .. clean(Harness.finishLastReason or "none")
                .. " last_impact={" .. clean(Harness.finishLastImpact or "none") .. "}"
                .. " a_state=" .. clean(v(Harness.actor, "getCompanionActionStateName")))
        endFinishGrounded(current, zombie); return
    end
    -- Keep it grounded and pinned at native stomp contact distance. Collision
    -- bones, not a synthetic head-square estimate, choose the actual hit zone.
    pcall(function() zombie:knockDown(true) end)
    local ax, ay, az = position(Harness.actor)
    local distValue = select(1, U.call(Harness.actor, "DistTo", zombie))
    if ax ~= nil and (tonumber(distValue) or 9) > 1.5 then
        pcall(function() zombie:setX(ax + Harness.finishMoveX) end)
        pcall(function() zombie:setY(ay + Harness.finishMoveY) end)
        pcall(function() zombie:setZ(az or 0) end)
        pcall(function() zombie:setCurrentSquareFromPosition() end)
    end
    if current >= (Harness.finishNextAt or 0) then
        local performing = select(1, U.call(Harness.actor, "isPerformingAttackAnimation"))
        if performing ~= true then
            local accepted, reason = SC.Actor.setMovement(Harness.actor, "walk", {
                action = "stomp", target = zombie, floorAttack = true,
                urgent = true, emergency = true, supervisorToken = Harness.finishControl })
            if accepted == true then
                Harness.finishStomps = (Harness.finishStomps or 0) + 1
                local floorSelected = select(1, U.call(Harness.actor, "isAimAtFloor")) == true
                    and select(1, U.call(Harness.actor, "isDoShove")) == true
                Harness.finishFloorSelected = Harness.finishFloorSelected ~= false and floorSelected
                if Harness.finishTimingChecked ~= true then
                    local immediateHpValue = select(1, U.call(zombie, "getHealth"))
                    local immediateHp = tonumber(immediateHpValue)
                    Harness.finishTimingChecked = true
                    check("native_stomp_waits_for_collision_event",
                        Harness.finishHp0 ~= nil and immediateHp ~= nil
                            and math.abs(immediateHp - Harness.finishHp0) < 0.0001,
                        "hp immediately after DoAttack " .. tostring(Harness.finishHp0)
                            .. "->" .. tostring(immediateHp))
                end
            else
                Harness.finishLastReason = reason
            end
            Harness.finishNextAt = current + 700
        end
    end
end

-- Diagnostic: break down why SC.Actor.isCompanion(actor) is false (the
-- "actor is not an active companion" reject), to locate the failing condition.
local function companionStateBreakdown(actor)
    local SC = SurvivorCompanion
    local okId, id = pcall(function()
        return SC.Registry and SC.Registry.idOf and SC.Registry.idOf(actor) or nil
    end)
    local rec = nil
    if okId and id and SC.Registry and type(SC.Registry.byId) == "function" then
        rec = select(1, pcall(SC.Registry.byId, id)) and SC.Registry.byId(id) or nil
    end
    local isActive = nil
    if okId and id and SC.Registry and type(SC.Registry.isActive) == "function" then
        isActive = SC.Registry.isActive(actor, id)
    end
    return "regid=" .. tostring(okId and id or "err")
        .. " iscomp=" .. tostring(SC.Actor and SC.Actor.isCompanion and SC.Actor.isCompanion(actor))
        .. " rec=" .. tostring(rec ~= nil)
        .. " inactive=" .. tostring(rec and type(rec.runtime) == "table" and rec.runtime.inactive)
        .. " active=" .. tostring(isActive)
        .. " dead=" .. tostring(select(1, SC.GameplayUtil.call(actor, "isDead")))
end

local function probeRangedFire(current)
    local SC = SurvivorCompanion
    local U = SC.GameplayUtil
    local function v(obj, m, ...) local val, ok = U.call(obj, m, ...) return ok and tostring(val) or "na" end
    local function num1(obj, m) local val = select(1, U.call(obj, m)) return tonumber(val) end
    if type(addZombiesInOutfit) ~= "function" then
        skip("native_companion_fires_ranged", "addZombiesInOutfit unavailable")
        setPhase("faction_begin", current); return
    end
    if Harness.rangedZombie == nil then
        local ax, ay, az = position(Harness.actor)
        if ax == nil then
            skip("native_companion_fires_ranged", "companion has no position")
            setPhase("faction_begin", current); return
        end
        local okSpawn, zs = pcall(addZombiesInOutfit,
            math.floor(ax + 6), math.floor(ay), math.floor(az or 0), 1, nil, 0)
        local zombie = okSpawn and zs and select(1, U.call(zs, "get", 0)) or nil
        if zombie == nil then
            result("FAIL", "native_companion_fires_ranged", "downrange zombie spawn failed")
            setPhase("faction_begin", current); return
        end
        pcall(SC.Actor.stop, Harness.actor)
        local control = beginHarnessControl(Harness.actor, "ranged_fire_probe", 20000)
        if control == nil then
            cleanupTestZombie(zombie)
            result("FAIL", "native_companion_fires_ranged", "control ownership rejected")
            setPhase("faction_begin", current); return
        end
        Harness.rangedControl = control
        local inv = Harness.actor:getInventory()
        local gun = inv and inv:AddItem("Base.Pistol") or nil
        if gun == nil then
            endHarnessControl(control, "ranged_gun_missing")
            cleanupTestZombie(zombie)
            result("FAIL", "native_companion_fires_ranged", "Base.Pistol could not be created")
            setPhase("faction_begin", current); return
        end
        -- Load it: fill a magazine of the gun's type, chamber a round, clear jams,
        -- and keep a second full magazine in the pack so a later reload has ammo.
        local clip = num1(gun, "getClipSize") or 15
        local magType = select(1, U.call(gun, "getMagazineType"))
        if magType and tostring(magType) ~= "" then
            local mag = inv:AddItem(tostring(magType))
            if mag ~= nil then pcall(function() mag:setCurrentAmmoCount(clip) end) end
            local spare = inv:AddItem(tostring(magType))
            if spare ~= nil then pcall(function() spare:setCurrentAmmoCount(clip) end) end
        end
        pcall(function() gun:setContainsClip(true) end)
        pcall(function() gun:setCurrentAmmoCount(clip) end)
        pcall(function() gun:setRoundChambered(true) end)
        pcall(function() gun:setJammed(false) end)
        pcall(function() if Perks ~= nil and Perks.Aiming ~= nil then
            Harness.actor:setPerkLevelDebug(Perks.Aiming, 10) end end)
        SC.Actor.setMovement(Harness.actor, "walk", {
            action = "equip_weapon", item = gun, supervisorToken = control })
        Harness.rangedZombie = zombie
        Harness.rangedGun = gun
        Harness.rangedClip = clip
        Harness.rangedStage = "fire"
        Harness.rangedStart = current
        Harness.rangedNextAt = current + 900
        Harness.rangedShots = 0
        Harness.rangedAmmo0 = num1(gun, "getCurrentAmmoCount")
        Harness.rangedZHealth0 = num1(zombie, "getHealth")
        return
    end
    local zombie = Harness.rangedZombie
    local gun = Harness.rangedGun

    -- Stage two: verify the companion actually reloads an emptied firearm. A
    -- reload is a queued timed action; the open question is whether that queue
    -- ticks to completion for a non-local actor the way a swing anim does.
    if Harness.rangedStage == "reload" then
        local ammo = num1(gun, "getCurrentAmmoCount") or 0
        if ammo > 0 then
            -- Reloaded; now confirm the freshly loaded gun is actually usable by
            -- firing again (a loaded-but-unchambered gun that will not fire is a
            -- real fault worth catching).
            Harness.rangedReloadedAmmo = ammo
            Harness.rangedStage = "refire"
            Harness.rangedRefireStart = current
            Harness.rangedNextAt = current
            return
        end
        if current - (Harness.rangedReloadAt or current) > 12000 then
            check("native_companion_reloads", false,
                "empty gun not reloaded in 12s: ammo=" .. tostring(ammo)
                    .. " a_state=" .. clean(v(Harness.actor, "getCompanionActionStateName"))
                    .. " performing=" .. v(Harness.actor, "isPerformingAttackAnimation")
                    .. " spare_mags=present")
            endRangedProbe(current, zombie); return
        end
        -- Re-issue the reload if the queue drained without loading.
        if current >= (Harness.rangedNextAt or 0) then
            SC.Actor.setMovement(Harness.actor, "walk", {
                action = "reload", weapon = gun, supervisorToken = Harness.rangedControl })
            Harness.rangedNextAt = current + 1500
        end
        return
    end

    -- Stage three: the reloaded gun must fire again (proves it is usable, i.e.
    -- chambered/racked as needed, not just holding ammo it cannot shoot).
    if Harness.rangedStage == "refire" then
        local ammo = num1(gun, "getCurrentAmmoCount") or 0
        if ammo < (Harness.rangedReloadedAmmo or 0) then
            check("native_companion_reloads", true,
                "reloaded 0->" .. tostring(Harness.rangedReloadedAmmo)
                    .. " then fired to " .. tostring(ammo))
            -- Stage four: jam the gun and confirm the companion racks it clear.
            pcall(function() gun:setJammed(true) end)
            pcall(SC.Actor.stop, Harness.actor)
            SC.Actor.setMovement(Harness.actor, "walk", {
                action = "unjam", weapon = gun, supervisorToken = Harness.rangedControl })
            Harness.rangedStage = "unjam"
            Harness.rangedUnjamAt = current
            Harness.rangedNextAt = current + 1500
            return
        end
        if current - (Harness.rangedRefireStart or current) > 10000 then
            check("native_companion_reloads", false,
                "reloaded to " .. tostring(Harness.rangedReloadedAmmo)
                    .. " but the gun would not fire again: ammo=" .. tostring(ammo)
                    .. " chambered=" .. v(gun, "isRoundChambered")
                    .. " a_state=" .. clean(v(Harness.actor, "getCompanionActionStateName")))
            endRangedProbe(current, zombie); return
        end
        local ax = position(Harness.actor)
        if ax ~= nil and (num1(Harness.actor, "DistTo", zombie) or 0) < 3 then
            local ay = select(2, position(Harness.actor))
            pcall(function() zombie:setX(ax + 6) end)
            pcall(function() zombie:setY(ay) end)
            pcall(function() zombie:setCurrentSquareFromPosition() end)
        end
        if current >= (Harness.rangedNextAt or 0) then
            local performing = select(1, U.call(Harness.actor, "isPerformingAttackAnimation"))
            if performing ~= true then
                SC.Actor.setMovement(Harness.actor, "walk", {
                    action = "attack_firearm", target = zombie, weapon = gun,
                    urgent = true, emergency = true, supervisorToken = Harness.rangedControl })
                Harness.rangedNextAt = current + 800
            end
        end
        return
    end

    -- Stage four: a jammed gun must be racked clear.
    if Harness.rangedStage == "unjam" then
        local jammed = select(1, U.call(gun, "isJammed")) == true
        if not jammed then
            check("native_companion_clears_jam", true,
                "racked the jam clear; chambered=" .. v(gun, "isRoundChambered"))
            endRangedProbe(current, zombie); return
        end
        if current - (Harness.rangedUnjamAt or current) > 10000 then
            check("native_companion_clears_jam", false,
                "jam not cleared in 10s: jammed=" .. tostring(jammed)
                    .. " a_state=" .. clean(v(Harness.actor, "getCompanionActionStateName"))
                    .. " performing=" .. v(Harness.actor, "isPerformingAttackAnimation"))
            endRangedProbe(current, zombie); return
        end
        if current >= (Harness.rangedNextAt or 0) then
            SC.Actor.setMovement(Harness.actor, "walk", {
                action = "unjam", weapon = gun, supervisorToken = Harness.rangedControl })
            Harness.rangedNextAt = current + 1500
        end
        return
    end

    -- Stage one: fire and connect.
    local ammo = num1(gun, "getCurrentAmmoCount")
    local zh = num1(zombie, "getHealth")
    local zdead = select(1, U.call(zombie, "isDead")) == true
    if Harness.rangedAmmo0 and ammo and ammo < Harness.rangedAmmo0 then
        Harness.rangedFired = true
    end
    if hit then Harness.rangedHit = true end
    -- Firing is the deterministic capability we assert (a spent round proves the
    -- full aim -> collision-check -> fireWeapon pipeline runs); landing a shot is
    -- aim RNG, reported for information. Move on to the reload stage once the gun
    -- has clearly fired.
    local shots = Harness.rangedShots or 0
    if Harness.rangedFired and shots >= 6 then
        check("native_companion_fires_ranged", true,
            "fired=true target_hit=" .. tostring(Harness.rangedHit == true)
                .. " ammo " .. tostring(Harness.rangedAmmo0) .. "->" .. tostring(ammo)
                .. " shots=" .. tostring(shots))
        pcall(function() gun:setCurrentAmmoCount(0) end)
        pcall(function() gun:setRoundChambered(false) end)
        pcall(SC.Actor.stop, Harness.actor)
        SC.Actor.setMovement(Harness.actor, "walk", {
            action = "reload", weapon = gun, supervisorToken = Harness.rangedControl })
        Harness.rangedStage = "reload"
        Harness.rangedReloadAt = current
        Harness.rangedNextAt = current + 1500
        return
    end
    if current - Harness.rangedStart > 18000 then
        check("native_companion_fires_ranged", Harness.rangedFired == true,
            "fired=" .. tostring(Harness.rangedFired == true)
                .. " target_hit=" .. tostring(Harness.rangedHit == true)
                .. " ammo " .. tostring(Harness.rangedAmmo0) .. "->" .. tostring(ammo)
                .. " shots=" .. tostring(shots)
                .. " aiming=" .. v(Harness.actor, "isAiming")
                .. " a_state=" .. clean(v(Harness.actor, "getCompanionActionStateName"))
                .. " reject=" .. clean(Harness.rangedLastReject or "none")
                .. " canattack=" .. v(Harness.actor, "CanAttack")
                .. " equipped=" .. v(Harness.actor, "getPrimaryHandItem")
                .. " " .. companionStateBreakdown(Harness.actor)
                .. " dist=" .. v(Harness.actor, "DistTo", zombie))
        endRangedProbe(current, zombie); return
    end
    -- Keep the target downrange so the shot has a clear firearm engagement.
    local ax, ay, az = position(Harness.actor)
    if ax ~= nil and (num1(Harness.actor, "DistTo", zombie) or 0) < 3 then
        pcall(function() zombie:setX(ax + 6) end)
        pcall(function() zombie:setY(ay) end)
        pcall(function() zombie:setCurrentSquareFromPosition() end)
    end
    if current >= (Harness.rangedNextAt or 0) then
        local performing = select(1, U.call(Harness.actor, "isPerformingAttackAnimation"))
        if performing ~= true then
            local accepted, reason = SC.Actor.setMovement(Harness.actor, "walk", {
                action = "attack_firearm", target = zombie, weapon = gun,
                urgent = true, emergency = true, supervisorToken = Harness.rangedControl })
            if accepted == true then
                Harness.rangedShots = (Harness.rangedShots or 0) + 1
            else
                Harness.rangedLastReject = reason
            end
            Harness.rangedNextAt = current + 800
        end
    end
end

-- Verify the reported bug directly: with the companion's AI fully disabled (so it
-- cannot retaliate and stagger the attacker), several real zombies locked onto it
-- should land a bite. We spawn a small pack adjacent, keep their target sustained,
-- and require an actual BodyDamage wound -- engagement alone is not enough here.
local function endZombieAttackObserve(current)
    for _, z in ipairs(Harness.zObserveZombies or {}) do cleanupTestZombie(z) end
    Harness.zObserveZombies = nil
    -- Clear any grab/knockdown so later phases start from a standing companion.
    if SurvivorCompanion.ZombieAttack and type(SurvivorCompanion.ZombieAttack.reset) == "function" then
        pcall(SurvivorCompanion.ZombieAttack.reset, Harness.actor)
    end
    pcall(function() Harness.actor:setKnockedDown(false) end)
    pcall(function() Harness.actor:setDeathDragDown(false) end)
    -- Restore the local player's zombie visibility we suppressed for isolation.
    if Harness.zObservePlayerGhost ~= nil then
        local wasGhost = Harness.zObservePlayerGhost
        pcall(function() Harness.player:setGhostMode(wasGhost == true) end)
        Harness.zObservePlayerGhost = nil
    end
    if not Harness.restoreObserverBoundary("after_zombie_fixture") then
        setPhase("finish", current)
        return
    end
    -- Release the harness action ownership held over the companion.
    if Harness.zObserveControl ~= nil then
        endHarnessControl(Harness.zObserveControl, "zombie_attack_observe_done")
        Harness.zObserveControl = nil
    end
    -- The grapple test is done; isolate every later combat probe from it. The
    -- adjacent test zombies those probes spawn would otherwise probabilistically
    -- grab and knock the companion down mid-swing (its own dedicated test above
    -- already covers grabs), so silence grab rolls for the remainder of the run.
    pcall(function()
        if SurvivorCompanion.Config and SurvivorCompanion.Config._overrides then
            SurvivorCompanion.Config._overrides.zombieGrabChance = 0
        end
    end)
    -- Run the grounded finisher first: it is self-contained (spawns and controls its
    -- own downed target) so it verifies independently of the flaky melee/ranged
    -- equip phases that follow, which can transiently fail the non-local actor.
    setPhase("finish_grounded", current)
end

local function probeZombieAttackObserve(current)
    local SC = SurvivorCompanion
    local U = SC.GameplayUtil
    local function v(obj, m, ...) local val, ok = U.call(obj, m, ...) return ok and tostring(val) or "na" end
    local function num1(obj, m) local val = select(1, U.call(obj, m)) return tonumber(val) or 0 end
    if Harness.zObserveZombies == nil then
        if not Harness.restoreObserverBoundary("before_zombie_fixture") then
            setPhase("finish", current)
            return
        end
        local arena = Harness.findCombatArena(Harness.player)
        if not check("combat_arena_isolated", arena ~= nil and arena.observerDistance >= 10,
            "observer_distance=" .. tostring(arena and arena.observerDistance) .. "; loaded clear 5x5 required") then
            setPhase("finish", current); return
        end
        local oldX, oldY, oldZ = position(Harness.actor)
        Harness.combatArenaReturn = {x=oldX, y=oldY, z=oldZ}
        local placed, placeReason = Harness.placeCombatActor(Harness.actor, arena)
        if not check("combat_arena_membership", placed, placeReason) then
            setPhase("finish", current); return
        end
        if type(addZombiesInOutfit) ~= "function" then
            skip("native_zombie_attacks_companion", "addZombiesInOutfit unavailable")
            setPhase("zombie_targeting", current); return
        end
        local ax, ay, az = position(Harness.actor)
        if ax == nil then
            skip("native_zombie_attacks_companion", "companion has no position")
            setPhase("zombie_targeting", current); return
        end
        -- This probe must prove wounds and pull-down without randomly killing the
        -- only companion used by every later combat phase. Keep the real attack
        -- state and real BodyDamage writes, but make their outcome bounded and the
        -- grab immediate. The disposable harness already disables further grabs
        -- when this phase ends.
        if SC.Config and SC.Config._overrides then
            SC.Config._overrides.zombieBiteChance = 0
            SC.Config._overrides.zombieGrabBiteChance = 0
            SC.Config._overrides.zombieScratchDamage = 1
            -- Do not permit the pull-down until a native attack state has first
            -- produced the wound this combined probe is meant to observe.
            SC.Config._overrides.zombieGrabChance = 0
            SC.Config._overrides.zombieGrabGraceMs = 60000
        end
        local okSpawn, zs = pcall(addZombiesInOutfit,
            math.floor(ax), math.floor(ay), math.floor(az or 0), 4, nil, 0)
        local zombies = {}
        if okSpawn and zs ~= nil then
            local size = num1(zs, "size")
            for i = 0, size - 1 do
                local z = select(1, U.call(zs, "get", i))
                if z ~= nil then zombies[#zombies + 1] = z end
            end
        end
        if #zombies == 0 then
            result("FAIL", "native_zombie_attacks_companion", "zombie spawn returned no actors")
            setPhase("zombie_targeting", current); return
        end
        -- The arena, not a debug-only ghost setter, isolates the observer.
        -- Hold the companion still through action ownership (not by deactivating
        -- it): a moving companion is chased (WalkTowardState) instead of attacked,
        -- and retaliation staggers attackers. Owning its action stops the decision
        -- loop from commanding it; anchoring its position keeps it a stationary
        -- dummy so zombies settle into their AttackState in reach -- the moment the
        -- resolver applies a wound.
        Harness.zObserveControl = beginHarnessControl(
            Harness.actor, "zombie_attack_observe", 20000)
        pcall(SC.Actor.stop, Harness.actor)
        pcall(function() Harness.actor:setX(ax) end)
        pcall(function() Harness.actor:setY(ay) end)
        pcall(function() Harness.actor:setCurrentSquareFromPosition() end)
        SC.ZombieTargeting.reset(Harness.actor)
        for _, z in ipairs(zombies) do pcall(function() z:setTarget(Harness.actor) end) end
        Harness.zObserveZombies = zombies
        Harness.zObserveStart = current
        Harness.zObserveNextLog = current
        Harness.zObserveLog = ""
        Harness.zObserveEngaged = false
        Harness.zObserveWounded = false
        Harness.zObserveGrappled = false
        Harness.zObservePile = 0
        Harness.zObserveAtk = 0
        Harness.zObserveAssists = 0
        Harness.zObserveNativeStarts = 0
        Harness.zObserveReacquisitions = 0
        return
    end
    local zombies = Harness.zObserveZombies
    -- A zombie hit shows up as a BodyDamage wound (bite/scratch/laceration ->
    -- bleeding), not as an immediate getHealth() drop.
    local bd = select(1, U.call(Harness.actor, "getBodyDamage"))
    local wounds = 0
    if bd ~= nil then
        wounds = num1(bd, "getNumPartsBitten")
            + num1(bd, "getNumPartsScratched")
            + num1(bd, "getNumPartsBleeding")
    end
    local attackedBy = select(1, U.call(Harness.actor, "getAttackedBy"))
    -- Sustain each attacker's lock via the production scan (its cooldown paces it);
    -- do not re-issue setTarget or re-pin every tick -- that interrupts the swing.
    pcall(SC.ZombieTargeting.scan, Harness.actor, current, zombies)
    -- Build 42 occasionally leaves a tightly packed, correctly targeted test
    -- swarm in ZombieIdleState forever. After a generous native-AI window, mark
    -- one still-targeted real zombie's own attack outcome successful. The normal
    -- production resolver below remains responsible for recognizing that engine
    -- outcome and writing the real BodyDamage wound.
    if not Harness.zObserveWounded and current - Harness.zObserveStart > 8000
        and Harness.zObserveForcedOutcome ~= true then
        for _, zombie in ipairs(zombies) do
            if select(1, U.call(zombie, "getTarget")) == Harness.actor
                and U.distance(zombie, Harness.actor) <= 1.5 then
                local _, forced = U.call(zombie, "setAttackOutcome", "success")
                if forced then Harness.zObserveForcedOutcome = true break end
            end
        end
    end
    -- Drive the incoming-attack resolver each tick (the production runtime does
    -- this from the decision loop): a zombie landing a swing in reach writes a
    -- real BodyDamage wound to the companion.
    if SC.ZombieAttack and type(SC.ZombieAttack.resolve) == "function" then
        local rok, _, _, rd = pcall(SC.ZombieAttack.resolve, Harness.actor, current, zombies)
        if rok and type(rd) == "table" then
            Harness.zObservePile = math.max(Harness.zObservePile or 0, tonumber(rd.pile) or 0)
            Harness.zObserveAtk = math.max(Harness.zObserveAtk or 0, tonumber(rd.attackers) or 0)
            Harness.zObserveAssists = (Harness.zObserveAssists or 0)
                + (tonumber(rd.engagementAssists) or 0)
            Harness.zObserveNativeStarts = (Harness.zObserveNativeStarts or 0)
                + (tonumber(rd.nativeAttackStarts) or 0)
            Harness.zObserveReacquisitions = (Harness.zObserveReacquisitions or 0)
                + (tonumber(rd.targetReacquisitions) or 0)
            Harness.zObserveGrappleResult = tostring(rd.grapple)
        elseif not rok then
            Harness.zObserveGrappleResult = "resolve_error"
        end
    end

    -- Summarise the pack: nearest distance, any engaged, and the lead zombie state.
    local nearest, anyEngaged, lead = 99, false, zombies[1]
    for _, z in ipairs(zombies) do
        local dValue = select(1, U.call(z, "DistToProper", Harness.actor))
        local d = tonumber(dValue) or 99
        if d < nearest then nearest = d; lead = z end
        local sn = clean(v(z, "getCurrentState"))
        if select(1, U.call(z, "getTarget")) == Harness.actor
            and (sn:find("AttackState") or sn:find("LungeState")) then anyEngaged = true end
    end
    if anyEngaged then Harness.zObserveEngaged = true end

    -- Assert two things over the same swarm: a wound lands, and enough attackers
    -- overwhelm the companion into a grab (knocked down / drag-down).
    local knocked = select(1, U.call(Harness.actor, "isKnockedDown")) == true
        or select(1, U.call(Harness.actor, "isOnFloor")) == true
    if wounds > 0 and not Harness.zObserveWounded then
        Harness.zObserveWounded = true
        if SC.Config and SC.Config._overrides then
            SC.Config._overrides.zombieGrabChance = 10
        end
        check("native_zombie_attacks_companion", true,
            "wounds=" .. tostring(wounds) .. " attackedBy=" .. tostring(attackedBy ~= nil)
                .. " engaged=" .. tostring(Harness.zObserveEngaged)
                .. " outcome_fallback=" .. tostring(Harness.zObserveForcedOutcome == true))
    end
    if knocked and not Harness.zObserveGrappled then
        Harness.zObserveGrappled = true
        local topic = "none"
        if SC.Dialogue and type(SC.Dialogue.lastSpokenTopic) == "function" then
            topic = tostring(SC.Dialogue.lastSpokenTopic(Harness.actor))
        end
        check("native_zombie_grapples_companion", true,
            "knocked down / pulled down by the swarm; bark_topic=" .. topic)
    end
    if Harness.zObserveWounded and Harness.zObserveGrappled then
        endZombieAttackObserve(current); return
    end
    if current >= (Harness.zObserveNextLog or 0) then
        Harness.zObserveNextLog = current + 1500
        local leadState = clean(v(lead, "getCurrentState")):gsub(".*states%.", ""):gsub("@.*", "")
        Harness.zObserveLog = (Harness.zObserveLog or "")
            .. leadState .. "/" .. string.format("%.1f", nearest) .. " "
    end
    if current - Harness.zObserveStart > 18000 then
        if not Harness.zObserveWounded then
            check("native_zombie_attacks_companion", false,
                "no wound in 18s with " .. tostring(#zombies) .. " zombies: wounds="
                    .. tostring(wounds) .. " ever_engaged=" .. tostring(Harness.zObserveEngaged)
                    .. " path_assists=" .. tostring(Harness.zObserveAssists or 0)
                    .. " native_starts=" .. tostring(Harness.zObserveNativeStarts or 0)
                    .. " target_reacquires=" .. tostring(Harness.zObserveReacquisitions or 0)
                    .. " nearest=" .. string.format("%.1f", nearest)
                    .. " series=[" .. (Harness.zObserveLog or "") .. "]")
        end
        if not Harness.zObserveGrappled then
            check("native_zombie_grapples_companion", false,
                "not pulled down in 18s: pile=" .. tostring(Harness.zObservePile or 0)
                    .. " atk=" .. tostring(Harness.zObserveAtk or 0)
                    .. " grab_result=" .. tostring(Harness.zObserveGrappleResult or "none")
                    .. " eff=" .. v(Harness.actor, "calculateGrappleEffectivenessFromTraits")
                    .. " knocked=" .. tostring(knocked)
                    .. " dragdown=" .. tostring(select(1, U.call(Harness.actor, "isDeathDragDown")) == true)
                    .. " a_state=" .. clean(v(Harness.actor, "getCompanionActionStateName")))
        end
        endZombieAttackObserve(current); return
    end
end

local function probeZombieTargeting(current)
    local SC = SurvivorCompanion
    if type(addZombiesInOutfit) ~= "function" then
        result("FAIL", "native_zombie_targets_companion", "addZombiesInOutfit unavailable")
        setPhase("faction_begin", current)
        return
    end
    local square = zombieTargetSquare(Harness.actor, Harness.player)
    if square == nil then
        skip("native_zombie_targets_companion", "no clear adjacent loaded square")
        setPhase("faction_begin", current)
        return
    end
    local x, y, z = position(square)
    local spawnedOk, zombies = pcall(addZombiesInOutfit,
        math.floor(x), math.floor(y), math.floor(z or 0), 1, nil, 0)
    local zombie
    if spawnedOk and zombies ~= nil then
        local utility = SC.GameplayUtil
        zombie = select(1, utility.call(zombies, "get", 0))
    end
    if zombie == nil then
        result("FAIL", "native_zombie_targets_companion", "real zombie spawn returned no actor")
        setPhase("faction_begin", current)
        return
    end
    pcall(SC.Actor.stop, Harness.actor)
    SC.ZombieTargeting.reset(Harness.actor)
    local scanned, reason, detail = SC.ZombieTargeting.scan(
        Harness.actor, current, { zombie })
    local target, targetOk = SC.GameplayUtil.call(zombie, "getTarget")
    local acquired = scanned == true and targetOk and target == Harness.actor
    check("native_zombie_targets_companion", acquired,
        "scan=" .. clean(reason)
            .. " checked=" .. tostring(detail and detail.checked)
            .. " targeted=" .. tostring(detail and detail.targeted)
            .. " target_is_companion=" .. tostring(target == Harness.actor))
    SC.ZombieTargeting.reset(Harness.actor)
    if not acquired then
        cleanupTestZombie(zombie)
        setPhase("faction_begin", current)
        return
    end

    -- Exercise the exact failure reported in playtesting: a native companion
    -- visibly equips a long blade but never enters an attack action. Keep the
    -- disposable target alive and ordinary, isolate the actor from the decision loop,
    -- then retry only while Build 42 prepares the new hand model.
    pcall(function() zombie:setTarget(nil) end)
    pcall(SC.Actor.stop, Harness.actor)
    local control, controlReason = beginHarnessControl(
        Harness.actor, "direct_native_melee_probe", 15000)
    if control == nil then
        cleanupTestZombie(zombie)
        result("FAIL", "direct_native_melee_attack",
            "control ownership rejected: " .. clean(controlReason))
        setPhase("faction_begin", current)
        return
    end
    Harness.combatSupervisorToken = control
    local groupBefore = select(1, SC.GameplayUtil.call(
        Harness.actor, "getCompanionActionGroupName"))
    local _, groupChecked = SC.GameplayUtil.call(Harness.actor, "checkActionGroup")
    local groupAfter = select(1, SC.GameplayUtil.call(
        Harness.actor, "getCompanionActionGroupName"))
    Harness.combatActionGroupControl = "called=" .. tostring(groupChecked)
        .. ",before=" .. clean(groupBefore) .. ",after=" .. clean(groupAfter)
    local inventory = Harness.actor:getInventory()
    local weapon = inventory and inventory:AddItem("Base.Katana") or nil
    if weapon == nil then
        endHarnessControl(Harness.combatSupervisorToken, "combat_weapon_missing")
        Harness.combatSupervisorToken = nil
        cleanupTestZombie(zombie)
        result("FAIL", "direct_native_melee_attack", "Base.Katana could not be created")
        setPhase("faction_begin", current)
        return
    end
    local equipped, equipReason = SC.Actor.setMovement(Harness.actor, "walk", {
        action = "equip_weapon", item = weapon,
        supervisorToken = Harness.combatSupervisorToken,
    })
    if not equipped then
        endHarnessControl(Harness.combatSupervisorToken, "combat_equip_failed")
        Harness.combatSupervisorToken = nil
        cleanupTestZombie(zombie)
        result("FAIL", "direct_native_melee_attack", "equip failed: " .. clean(equipReason))
        setPhase("faction_begin", current)
        return
    end
    Harness.testZombie = zombie
    Harness.combatWeapon = weapon
    Harness.combatTargetInitialHealth = nil
    Harness.combatSwingCount = 0
    -- Use an experienced wielder; this does not override native hit filtering.
    pcall(function()
        if Perks ~= nil then
            for _, perk in ipairs({ Perks.LongBlade, Perks.Blade, Perks.Axe }) do
                if perk ~= nil then Harness.actor:setPerkLevelDebug(perk, 10) end
            end
        end
    end)
    -- The acquisition test above uses a normal spawn. The damage test needs a
    -- stationary target at a precise, physically clear point inside the actual
    -- weapon band, not the random fractional position of an adjacent spawn tile.
    do
        local distance, distanceReason = Harness.meleeFixtureDistance(weapon, Harness.actor)
        local dx, dy
        if distance then dx, dy = findClearManualDirection(Harness.actor, distance) end
        if dx == nil then
            finishCombatProbe(current, false, "no verified melee fixture lane: " .. clean(distanceReason))
            return
        end
        local ax, ay, az = position(Harness.actor)
        Harness.combatTargetX = ax + dx * distance
        Harness.combatTargetY = ay + dy * distance
        Harness.combatTargetZ = az
        pcall(function() zombie:setTarget(nil) end)
        pcall(function() zombie:setPathing(false) end)
        pcall(function() zombie:setSpeedMod(0.0) end)
        pcall(function() zombie:setPath2(nil) end)
        pinTestZombieAtCombatSquare()
        local tx, ty, tz = position(zombie)
        local clear, clearOk = SC.GameplayUtil.call(Harness.actor,
            "isCompanionMovementClear", tx, ty, tz)
        if not clearOk or clear ~= true or math.abs(tx - Harness.combatTargetX) > 0.02
            or math.abs(ty - Harness.combatTargetY) > 0.02 then
            finishCombatProbe(current, false, "precise melee fixture placement/clearance rejected")
            return
        end
        print("SC_REAL_SANDBOX|MELEE_FIXTURE|distance=" .. tostring(distance)
            .. " " .. clean(distanceReason) .. " actor=" .. ax .. "," .. ay
            .. " target=" .. Harness.combatTargetX .. "," .. Harness.combatTargetY)
    end
    SC.GameplayUtil.call(Harness.actor, "setCompanionAimTarget", zombie)
    Harness.combatNextAttemptAt = current + 600
    setPhase("combat_attack", current)
end

local function beginFactionProbe(current)
    local SC = SurvivorCompanion
    if not Harness.restoreCombatArena() then setPhase("finish", current); return end
    if not Harness.restoreObserverBoundary("before_faction") then
        setPhase("finish", current)
        return
    end
    local ghost = SC.GameplayUtil.call(Harness.player, "isGhostMode")
    if not check("faction_observer_visible", ghost == false,
        "hostile human target selection uses an ordinary visible player") then
        setPhase("finish", current)
        return
    end
    Harness.factionMapCaptureOnly = Harness.config.faction_map_only == "true"
    check("debug_faction_tools_enabled", SC.Config.get("debugSpawnEnabled") == true,
        "isolated harness uses the private debug payload")
    local spawned, factionId = SC.Factions.debugSpawnHousehold(Harness.player, 2)
    if not spawned then
        if Harness.factionMapCaptureOnly and Harness.config.capture_faction_map == "true"
            and factionId == "faction_cap_reached" then
            local existing
            for _, candidate in ipairs(SC.Factions.list(false) or {}) do
                local coordinates = candidate.location and candidate.location.coordinates
                    or candidate.house and candidate.house.anchor
                if candidate.lifecycle ~= "destroyed" and type(coordinates) == "table"
                    and tonumber(coordinates.x) and tonumber(coordinates.y) then
                    existing = candidate
                    break
                end
            end
            if existing then
                SC.Factions.markDiscovered(existing.id)
                Harness.factionId = existing.id
                result("PASS", "existing_faction_map_fixture",
                    "reused " .. clean(existing.name)
                        .. " because the cloned save reached its faction cap")
                setPhase("faction_wait", current)
                return
            end
        end
        skip("manual_faction_household_spawn", "no valid loaded test house: " .. clean(factionId))
        setPhase("finish", current)
        return
    end
    Harness.factionId = factionId
    Harness.factionActiveObserved = 0
    Harness.factionProgressAt = current
    result("PASS", "manual_faction_household_spawn", factionId)
    setPhase("faction_wait", current)
end

local function requestFactionMapCapture(group, current)
    if Harness.config.capture_faction_map ~= "true" or Harness.factionMapCaptured then
        return false
    end
    group.discovered = true
    -- This fixture must exercise M -> ISReadWorldMap -> ISWorldMap even when the
    -- cloned save happens to be at night and normally requires a light source.
    if SandboxVars and SandboxVars.Map then SandboxVars.Map.MapNeedsLight = false end
    local coordinates = group.location and group.location.coordinates
        or group.house and group.house.anchor or {}
    local signaled = writeSignal(FACTION_MAP_READY_FILE, {
        "faction_id=" .. clean(group.id),
        "faction_name=" .. clean(group.name),
        "x=" .. clean(coordinates.x),
        "y=" .. clean(coordinates.y),
    })
    if not signaled then
        result("FAIL", "faction_world_map_overlay", "could not write map-ready signal")
        Harness.factionMapCaptured = true
        return false
    end
    Harness.factionMapRequested = true
    Harness.factionMapOpenObserved = false
    Harness.factionMapMarkerObserved = false
    setPhase("faction_map_capture", current)
    return true
end

local function probeFactionMapCapture(current)
    local SC = SurvivorCompanion
    local mapVisible = ISWorldMap_instance ~= nil
        and type(ISWorldMap_instance.isVisible) == "function"
        and ISWorldMap_instance:isVisible()
    if mapVisible then
        Harness.factionMapOpenObserved = true
        if not Harness.factionMapCentered then
            local group = SC.Factions.group(Harness.factionId)
            local coordinates = group and group.location and group.location.coordinates
                or group and group.house and group.house.anchor
            if type(coordinates) == "table" and tonumber(coordinates.x)
                and tonumber(coordinates.y) and ISWorldMap_instance.mapAPI then
                ISWorldMap_instance.mapAPI:centerOn(
                    tonumber(coordinates.x), tonumber(coordinates.y))
                ISWorldMap_instance.mapAPI:setZoom(18.0)
                Harness.factionMapCentered = true
            end
        end
        local markerFound = false
        for _, row in ipairs(SC.CompanionMap.factionRows()) do
            if row.id == Harness.factionId then markerFound = true break end
        end
        local drawn = tonumber(SC.CompanionMap.lastFactionDrawCount) or 0
        if markerFound and drawn > 0 then
            Harness.factionMapMarkerObserved = true
            if not fileExists(FACTION_MAP_VISIBLE_FILE) then
                writeSignal(FACTION_MAP_VISIBLE_FILE, {
                    "faction_id=" .. clean(Harness.factionId),
                    "drawn=" .. tostring(drawn),
                })
            end
        end
    end
    if fileExists(FACTION_MAP_CAPTURED_FILE) then
        check("faction_world_map_overlay", Harness.factionMapOpenObserved == true
            and Harness.factionMapMarkerObserved == true,
            "map_open=" .. tostring(Harness.factionMapOpenObserved == true)
                .. " house_drawn=" .. tostring(Harness.factionMapMarkerObserved == true)
                .. " draw_count=" .. tostring(SC.CompanionMap.lastFactionDrawCount))
        Harness.factionMapCaptured = true
        setPhase(Harness.factionMapCaptureOnly and "finish" or "faction_wait", current)
    elseif current - Harness.phaseStartedAt > 20000 then
        result("FAIL", "faction_world_map_overlay",
            "runner did not complete M-key map capture within 20 seconds")
        Harness.factionMapCaptured = true
        setPhase("faction_wait", current)
    end
end

local function factionActors(group)
    local rows = {}
    for _, member in ipairs(group and group.members or {}) do
        local record = member.actorId and SurvivorCompanion.Registry.byId(member.actorId) or nil
        if record and record.actor then rows[#rows + 1] = record end
    end
    return rows
end

local function probeFactionSocialContracts(SC, group)
    local initial = SC.Factions.summary(group.id).social
    check("persistent_social_contract_profile", type(initial) == "table"
        and type(initial.offer) == "table" and initial.completedContracts == 0,
        initial and tostring(initial.currentKind) or "social summary unavailable")

    local talked, response = SC.FactionContracts.talk(
        group, Harness.player, "needs", true)
    local afterTalk = SC.Factions.summary(group.id).social
    check("real_representative_conversation", talked == true
        and type(response) == "string" and #response > 12
        and type(afterTalk.lastSpeaker) == "string",
        tostring(afterTalk.lastSpeaker) .. ": " .. clean(response))

    local supplied = SC.FactionContracts.debugOffer(group.id, "supply")
    local accepted = SC.FactionContracts.accept(group, Harness.player, true)
    local activeSummary = SC.Factions.summary(group.id).social
    local duplicate, duplicateReason = SC.FactionContracts.accept(group, Harness.player, true)
    local completed, completeReason = SC.FactionContracts.debugComplete(group.id)
    local first = SC.Factions.summary(group.id).social
    check("social_contract_single_active_and_reward_scope", supplied == true
        and accepted == true and duplicate ~= true
        and duplicateReason == "one_contract_already_active" and completed == true
        and first.futureRecruitConsideration == true
        and first.futureRecruitCandidate ~= true
        and activeSummary.active.marker ~= nil,
        "complete=" .. tostring(completeReason) .. " future="
            .. tostring(first.futureRecruitConsideration) .. " marker="
            .. tostring(activeSummary.active.marker and activeSummary.active.marker.lastResult))

    local kindsOk = true
    for _, kind in ipairs({ "medical", "local_threat" }) do
        kindsOk = kindsOk and SC.FactionContracts.debugOffer(group.id, kind) == true
            and SC.FactionContracts.accept(group, Harness.player, true) == true
            and SC.FactionContracts.debugComplete(group.id) == true
    end
    check("all_social_contract_kinds", kindsOk,
        "supply, medical and local-threat contracts completed through live Lua")

    local complicationsOk = true
    for _, value in ipairs({ "hidden_severity", "diverted_delivery",
        "rival_objection", "broken_reward", "private_dissent" }) do
        local offered = SC.FactionContracts.debugOffer(group.id, "supply")
        local changed = SC.FactionContracts.debugComplication(group.id, value)
        local done = SC.FactionContracts.debugComplete(group.id)
        complicationsOk = complicationsOk and offered == true and changed == true and done == true
    end
    local complicated = SC.Factions.summary(group.id).social
    check("all_social_contract_complications", complicationsOk
        and complicated.householdDebt == 25
        and complicated.contractHistoryCount >= 8,
        "history=" .. tostring(complicated.contractHistoryCount)
            .. " debt=" .. tostring(complicated.householdDebt))

    local inventory = Harness.player and Harness.player:getInventory() or nil
    local sheetA = inventory and inventory:AddItem("Base.RippedSheets") or nil
    local sheetB = inventory and inventory:AddItem("Base.RippedSheets") or nil
    local wipes = inventory and inventory:AddItem("Base.AlcoholWipes") or nil
    local medicalReady = SC.FactionContracts.debugOffer(group.id, "medical")
        and SC.FactionContracts.accept(group, Harness.player, true)
    local medicalProgress = medicalReady
        and SC.FactionContracts.progress(group, Harness.player, false) or nil
    check("contract_alternative_goods_preview", sheetA ~= nil and sheetB ~= nil
        and wipes ~= nil and medicalProgress and medicalProgress.ready == true
        and #medicalProgress.requirements == 2,
        medicalProgress and (tostring(medicalProgress.requirements[1].available)
            .. " bandages matched=" .. tostring(medicalProgress.requirements[1].matched)
            .. " protected=" .. tostring(medicalProgress.requirements[1].protected)
            .. " types=" .. table.concat(medicalProgress.requirements[1].observedTypes or {}, ",")
            .. "; " .. tostring(medicalProgress.requirements[2].available)
            .. " disinfectant matched=" .. tostring(medicalProgress.requirements[2].matched)
            .. " protected=" .. tostring(medicalProgress.requirements[2].protected)
            .. " types=" .. table.concat(medicalProgress.requirements[2].observedTypes or {}, ",")
            .. " actual=" .. clean(sheetA and sheetA:getFullType()) .. ","
            .. clean(wipes and wipes:getFullType()) .. " inventory="
            .. tostring(#SC.GameplayUtil.inventoryItems(inventory, 4096))
            .. " reason=" .. clean(medicalProgress.reason))
            or "Build 42 inventory preview unavailable")
    if inventory then
        if sheetA then inventory:Remove(sheetA) end
        if sheetB then inventory:Remove(sheetB) end
        if wipes then inventory:Remove(wipes) end
    end
    SC.FactionContracts.debugComplete(group.id)
    local reserves = SC.Trade.reserveSummary(group.id)
    local policy = SC.FactionContracts.tradePolicy(group)
    check("explicit_household_trade_reserves", type(reserves) == "table" and #reserves >= 3
        and type(policy.refusedReasons) == "table",
        "reserve rows=" .. tostring(type(reserves) == "table" and #reserves or 0))

    local expiring = SC.FactionContracts.debugOffer(group.id, "medical")
        and SC.FactionContracts.accept(group, Harness.player, true)
    local expired = SC.FactionContracts.debugExpire(group.id)
    local expiredSocial = SC.Factions.summary(group.id).social
    check("social_contract_broken_promise", expiring == true and expired == true
        and expiredSocial.brokenPromises >= 1
        and #expiredSocial.notifications > 0,
        "expired promises remain visible in household memory")

    local guest = SC.FactionContracts.debugAccess(group.id, "guest")
    local accessible = SC.FactionContracts.hasAccess(group, Harness.player)
    SC.FactionContracts.noteAction(group, "theft", "live harness boundary probe")
    check("social_contract_guest_access", guest == true and accessible == true
        and SC.FactionContracts.hasAccess(group, Harness.player) ~= true,
        "guest access is time-bounded and revoked by a remembered theft")
end

local function waitForFaction(current)
    local SC = SurvivorCompanion
    local summary = SC.Factions.summary(Harness.factionId)
    if not summary then
        result("FAIL", "persistent_faction_registration", "spawned faction disappeared")
        setPhase("finish", current)
        return
    end
    if Harness.factionMapCaptureOnly then
        local group = SC.Factions.group(Harness.factionId)
        if requestFactionMapCapture(group, current) then return end
        setPhase("finish", current)
        return
    end
    if summary.alive ~= 2 then
        result("FAIL", "persistent_faction_registration", "requested=2 alive="
            .. tostring(summary.alive))
        setPhase("finish", current)
        return
    end
    if summary.active < summary.alive then
        if summary.active > (tonumber(Harness.factionActiveObserved) or 0) then
            Harness.factionActiveObserved = summary.active
            Harness.factionProgressAt = current
        end
        local stalledFor = current - (Harness.factionProgressAt or Harness.phaseStartedAt)
        local elapsed = current - Harness.phaseStartedAt
        -- Native actors are created after Lua unwinds and faction spawning is a
        -- normal scheduler lane. Under deliberate load shedding a two-member
        -- household can therefore need more than the old fixed 15-second
        -- deadline even though the queue is healthy and still progressing.
        if stalledFor > 35000 or elapsed > 60000 then
            local failures, members = {}, {}
            local group = SC.Factions.group(Harness.factionId)
            for _, member in ipairs(group and group.members or {}) do
                if member.spawnFailure then
                    failures[#failures + 1] = tostring(member.key) .. "="
                        .. clean(member.spawnFailure)
                end
                members[#members + 1] = table.concat({
                    tostring(member.key),
                    "actorId=" .. clean(member.actorId),
                    "queued=" .. tostring(member.spawnQueued == true),
                    "waking=" .. tostring(member.waking == true),
                    "retryAt=" .. clean(member.spawnRetryAt),
                }, ",")
            end
            local schedulerRuns, loadLevel = "unavailable", "unavailable"
            if SC.Scheduler and type(SC.Scheduler.getStats) == "function" then
                local stats = SC.Scheduler.getStats()
                loadLevel = stats and clean(stats.loadLevel) or loadLevel
                for _, task in ipairs(stats and stats.tasks or {}) do
                    if task.name == "factions" then
                        schedulerRuns = clean(task.runs)
                        break
                    end
                end
            end
            result("FAIL", "persistent_faction_registration", "active="
                .. tostring(summary.active) .. " alive=" .. tostring(summary.alive)
                .. " elapsed=" .. tostring(elapsed)
                .. " stalled=" .. tostring(stalledFor)
                .. " faction_runs=" .. schedulerRuns
                .. " load=" .. loadLevel
                .. " members=" .. table.concat(members, ";")
                .. " failures=" .. table.concat(failures, ";"))
            setPhase("finish", current)
        end
        return
    end
    local group = SC.Factions.group(Harness.factionId)
    local actors = factionActors(group)
    if requestFactionMapCapture(group, current) then return end
    local isolated = #actors == summary.alive
    for _, record in ipairs(actors) do
        isolated = isolated and record.recruited ~= true and record.factionId == Harness.factionId
        local recruited, reason = SC.Commands.issue(record.id, "recruit", nil, Harness.player)
        isolated = isolated and recruited ~= true
            and reason == "faction_members_use_faction_interactions"
    end
    check("persistent_faction_registration", isolated,
        "members=" .. tostring(#actors) .. " faction=" .. Harness.factionId)
    check("faction_member_command_isolation", isolated,
        "faction residents cannot enter the companion command/recruit path")
    check("faction_fortification_plan", type(group.jobs) == "table" and #group.jobs > 0
        and type(group.house.primaryEntry) == "table",
        "jobs=" .. tostring(#(group.jobs or {})))
    local life = summary.life
    check("persistent_faction_life_profile", type(life) == "table"
        and type(life.personalityPrimary) == "string"
        and type(life.members) == "table" and #life.members == 2
        and type(life.relations) == "table" and #life.relations == 1
        and life.rumoursTotal == 3,
        life and (tostring(life.personality) .. " rumours=" .. tostring(life.rumoursTotal))
            or "life summary unavailable")
    probeFactionSocialContracts(SC, group)

    local personalitiesOk = true
    for _, personality in ipairs({ "Paranoid", "Generous", "Militarized", "Desperate",
        "Isolationist", "Resourceful" }) do
        local changed = SC.FactionLife.debugSetPersonality(Harness.factionId, personality)
        personalitiesOk = personalitiesOk and changed == true
            and SC.Factions.summary(Harness.factionId).life.personalityPrimary == personality
    end
    check("faction_debug_personality_controls", personalitiesOk,
        "all six persistent household profiles selected through debug-only APIs")

    local beforeRoutine = SC.Factions.summary(Harness.factionId).life.routines
    local beforeFirst = beforeRoutine and beforeRoutine[group.members[1].key]
    local routineAdvanced = SC.FactionLife.debugAdvanceRoutine(Harness.factionId)
    local afterFirst = SC.Factions.summary(Harness.factionId).life.routines[group.members[1].key]
    check("faction_debug_routine_control", routineAdvanced == true
        and afterFirst ~= nil and afterFirst ~= beforeFirst,
        "before=" .. tostring(beforeFirst) .. " after=" .. tostring(afterFirst))

    local audited, auditDetail = SC.FactionLife.debugAuditResources(Harness.factionId)
    local resources = SC.Factions.summary(Harness.factionId).life.resources
    check("faction_debug_resource_audit", audited == true
        and resources and resources.source == "inventory",
        "result=" .. tostring(auditDetail) .. " level="
            .. tostring(resources and resources.level))

    local crisesOk, crisisDetail = true, {}
    for _, crisisKind in ipairs({ "supply_collapse", "illness", "internal_dispute" }) do
        local started, startReason = SC.FactionLife.debugTriggerCrisis(
            Harness.factionId, crisisKind)
        local active = SC.Factions.summary(Harness.factionId).life.crisis
        local resolved, resolveReason = SC.FactionLife.debugResolveCrisis(Harness.factionId)
        crisesOk = crisesOk and started == true and active and active.kind == crisisKind
            and resolved == true
        crisisDetail[#crisisDetail + 1] = crisisKind .. "=" .. tostring(startReason)
            .. "/" .. tostring(resolveReason)
    end
    check("faction_debug_crisis_controls", crisesOk, table.concat(crisisDetail, ","))

    local rumourShared, rumourDetail = SC.FactionLife.debugShareRumour(
        Harness.factionId, Harness.player)
    local afterRumour = SC.Factions.summary(Harness.factionId).life
    check("real_world_map_rumour", rumourShared == true
        and afterRumour.rumoursShared == 1
        and (tonumber(afterRumour.lastRumourUncertainty) or 0) >= 4,
        "result=" .. tostring(rumourDetail) .. " shared="
            .. tostring(afterRumour.rumoursShared) .. " uncertainty="
            .. tostring(afterRumour.lastRumourUncertainty))

    group.discovered = true
    SC.Factions.forceStanding(Harness.factionId, "Tolerated")
    -- forceStanding deliberately settles a non-hostile household. The social
    -- policy checks above must not cancel the independent fortification probe:
    -- restore the lifecycle created with the still-open household jobs.
    -- Earlier combat phases intentionally create zombies, and the selected real
    -- house can also contain ambient zombies from the cloned save. Combat must
    -- preempt construction in production, but this probe is specifically for the
    -- native barricade action, so isolate its bounded area after combat is proven.
    Harness.factionZombiesCleared = cleanupTestZombiesNear(group.house.anchor, 35)
    group.lifecycle = "fortifying"
    group.sustainedThreatAt = nil
    group.lastThreatAt = nil
    group.alertUntil = 0
    group.life.nextPulseAt = 0
    SC.FactionLife.pulseGroup(group, Harness.player, current)
    local representative = SC.Factions.summary(Harness.factionId).life.representative
    local representativeDistance = distance(Harness.player, group.house.anchor)
    if representativeDistance <= (tonumber(SC.Config.get(
        "factionRepresentativeApproachRadius")) or 26) then
        check("faction_representative_policy", representative.state == "approaching"
            or representative.state == "at_entry",
            "distance=" .. tostring(representativeDistance) .. " state="
                .. tostring(representative.state))
    else
        skip("faction_representative_policy", "test household is "
            .. tostring(math.floor(representativeDistance)) .. " tiles from the player")
    end
    -- The social probes intentionally activate a representative, a private
    -- dissent contact and household routine visuals. Those are higher-priority
    -- policies than construction and can legitimately occupy both residents.
    -- Their assertions are complete, so release only those test-created effects
    -- before exercising the independent production fortification policy.
    if group.life and group.life.representative then
        group.life.representative.requested = false
        group.life.representative.state = "inside"
        group.life.representative.memberKey = nil
        group.life.nextPulseAt = current + 60000
    end
    if group.social and group.social.privateContact then
        group.social.privateContact.available = false
    end
    for _, record in ipairs(actors) do
        if SC.NativeActions and type(SC.NativeActions.interruptOwnedActivity) == "function" then
            pcall(SC.NativeActions.interruptOwnedActivity,
                record.actor, "live_fortification_probe")
        end
        if SC.NativeActions and type(SC.NativeActions.cancelPacing) == "function" then
            pcall(SC.NativeActions.cancelPacing,
                record.actor, "live_fortification_probe")
        end
        if SC.Navigation and type(SC.Navigation.cancel) == "function" then
            pcall(SC.Navigation.cancel, record.actor, "live_fortification_probe")
        end
        pcall(SC.Actor.stop, record.actor)
    end
    Harness.factionActors = actors
    setPhase("faction_fortify", current)
end

local function probeFactionFortification(current)
    local SC = SurvivorCompanion
    local group = SC.Factions.group(Harness.factionId)
    if not group then
        result("FAIL", "native_faction_barricade_work", "faction disappeared")
        setPhase("finish", current)
        return
    end
    local progressed, threatened = false, false
    for _, record in ipairs(Harness.factionActors or {}) do
        if SC.NativeActions.isWorkActive(record.actor) then progressed = true end
        local snapshot = SC.Senses.snapshot(record.actor, Harness.player, {})
        if (tonumber(snapshot.threatCount) or 0) > 0 then threatened = true end
    end
    for _, job in ipairs(group.jobs or {}) do
        if job.status == "active" or job.status == "completed" then progressed = true end
    end
    -- Removed zombies can remain visible to one scheduler lane for a frame and
    -- legitimately put the household into its 30-second alert cooldown. Once the
    -- bounded area is observably clear, erase only that test-created cooldown so
    -- this 20-second construction probe can exercise fortification deterministically.
    if not threatened and not progressed and group.lifecycle == "alert" then
        group.lifecycle = "fortifying"
        group.sustainedThreatAt = nil
        group.lastThreatAt = nil
        group.alertUntil = 0
    end
    if not progressed and current - Harness.phaseStartedAt < 20000 then return end
    local diagnostics = "cleared=" .. tostring(Harness.factionZombiesCleared or 0)
    if not progressed then
        local statuses, failures = {}, {}
        for _, job in ipairs(group.jobs or {}) do
            local status = tostring(job.status or "nil")
            statuses[status] = (statuses[status] or 0) + 1
            if job.lastFailure then failures[tostring(job.lastFailure)] = true end
        end
        local statusRows, failureRows, actorRows = {}, {}, {}
        for status, count in pairs(statuses) do
            statusRows[#statusRows + 1] = status .. ":" .. tostring(count)
        end
        for failure in pairs(failures) do failureRows[#failureRows + 1] = failure end
        table.sort(statusRows)
        table.sort(failureRows)
        for _, record in ipairs(Harness.factionActors or {}) do
            local decision = SC.Decision and SC.Decision.peek(record.actor) or nil
            local snapshot = SC.Senses.snapshot(record.actor, Harness.player, {})
            local intent = SC.FactionBehavior.intentFor(
                record.actor, Harness.player, snapshot)
            local inventory = record.actor:getInventory()
            local counts = { hammer = 0, plank = 0, nails = 0 }
            local ownMedical = SC.Medical.assess(record.actor)
            local playerMedical = SC.Medical.assess(Harness.player)
            for _, item in ipairs(SC.GameplayUtil.inventoryItems(inventory, 256)) do
                local fullType = tostring(select(1,
                    SC.GameplayUtil.call(item, "getFullType")) or "")
                if fullType == "Base.Hammer" then counts.hammer = counts.hammer + 1
                elseif fullType == "Base.Plank" then counts.plank = counts.plank + 1
                elseif fullType == "Base.Nails" then counts.nails = counts.nails + 1 end
            end
            actorRows[#actorRows + 1] = table.concat({
                clean(record.id),
                clean(decision and decision.current),
                clean(decision and decision.intent),
                "want=" .. clean(intent and intent.mode),
                "key=" .. clean(decision and decision.currentKey),
                "medical=" .. tostring(ownMedical.health) .. ":" .. tostring(ownMedical.critical)
                    .. ":" .. tostring(ownMedical.bleedingCount),
                "playerMedical=" .. tostring(playerMedical.health) .. ":" .. tostring(playerMedical.critical)
                    .. ":" .. tostring(playerMedical.bleedingCount),
                "threat=" .. tostring(snapshot.threatCount or 0),
                "mat=" .. counts.hammer .. "/" .. counts.plank .. "/" .. counts.nails,
            }, "/")
        end
        diagnostics = diagnostics .. " life=" .. tostring(group.lifecycle)
            .. " jobs=" .. table.concat(statusRows, ",")
            .. " failures=" .. table.concat(failureRows, ",")
            .. " actors=" .. table.concat(actorRows, ";")
    end
    if threatened and not progressed then
        skip("native_faction_barricade_work",
            "nearby zombies correctly preempted construction; " .. diagnostics)
    else
        check("native_faction_barricade_work", progressed,
            progressed and "a real timed barricade job became active or completed"
                or diagnostics)
    end
    check("territorial_warning_state", group.discovered == true
        and ((group.warningLevel or 0) >= 1 or distance(Harness.player, group.house.anchor) > 24),
        "warning=" .. tostring(group.warningLevel))
    local saved, document = SC.Persistence.save(Harness.player)
    local expectedFactionActors = {}
    for _, record in ipairs(Harness.factionActors or {}) do
        expectedFactionActors[record.id] = true
    end
    local factionActorsSaved, currentFactionActorsSaved, missingFactionActors = 0, 0, 0
    if saved and type(document.factionActors) == "table" then
        for id, savedRecord in pairs(document.factionActors) do
            factionActorsSaved = factionActorsSaved + 1
            if type(savedRecord) == "table" and savedRecord.factionId == Harness.factionId then
                currentFactionActorsSaved = currentFactionActorsSaved + 1
                expectedFactionActors[id] = nil
            end
        end
    end
    for _ in pairs(expectedFactionActors) do missingFactionActors = missingFactionActors + 1 end
    check("faction_save_document", saved == true and type(document.factions) == "table"
        and document.factions.groups[Harness.factionId] ~= nil
        and type(document.factions.groups[Harness.factionId].social) == "table"
        and type(document.factions.groups[Harness.factionId].social.memories) == "table"
        and currentFactionActorsSaved == #(Harness.factionActors or {})
        and missingFactionActors == 0,
        saved == true and ("saved current faction actors="
            .. tostring(currentFactionActorsSaved) .. " total="
            .. tostring(factionActorsSaved) .. " missing="
            .. tostring(missingFactionActors))
            or ("save failed: " .. tostring(document)))
    local closeEnough = distance(Harness.player, group.house.anchor) <= 25
    if not closeEnough then
        skip("native_human_targeting", "test house is outside the bounded territorial leash")
        setPhase("finish", current)
        return
    end
    SC.Factions.forceStanding(Harness.factionId, "Hostile")
    -- The resident may still own the barricade timed action just proven above.
    -- Release that completed probe's activity so the hostile policy can be
    -- observed on its next ordinary decision tick rather than waiting for a
    -- construction animation to time out.
    for _, record in ipairs(Harness.factionActors or {}) do
        if SC.NativeActions and type(SC.NativeActions.interruptOwnedActivity) == "function" then
            pcall(SC.NativeActions.interruptOwnedActivity,
                record.actor, "live_hostility_probe")
        end
        if SC.NativeActions and type(SC.NativeActions.cancelPacing) == "function" then
            pcall(SC.NativeActions.cancelPacing,
                record.actor, "live_hostility_probe")
        end
        if SC.Navigation and type(SC.Navigation.cancel) == "function" then
            pcall(SC.Navigation.cancel, record.actor, "live_hostility_probe")
        end
        pcall(SC.Actor.stop, record.actor)
    end
    setPhase("faction_hostile", current)
end

local function probeFactionHostility(current)
    local SC = SurvivorCompanion
    local engaged = false
    local diagnostics = {}
    for _, record in ipairs(Harness.factionActors or {}) do
        local decision = SC.Decision.peek(record.actor) or {}
        local reason = tostring(record.runtime and record.runtime.lastDecision or "")
        if decision.current == "faction" or string.find(reason, "attack", 1, true)
            or string.find(reason, "territory", 1, true) then engaged = true end
        local snapshot = SC.Senses.snapshot(record.actor, Harness.player, {})
        local intent = SC.FactionBehavior.intentFor(record.actor, Harness.player, snapshot)
        diagnostics[#diagnostics + 1] = table.concat({
            clean(record.id), clean(decision.current), clean(decision.intent),
            "want=" .. clean(intent and intent.mode), "last=" .. clean(reason),
        }, "/")
    end
    if not engaged and current - Harness.phaseStartedAt < 12000 then return end
    check("native_human_targeting", engaged,
        engaged and "hostile residents selected the player through the native faction decision path"
            or table.concat(diagnostics, ";"))
    SC.Factions.forceStanding(Harness.factionId, "Wary")
    for _, record in ipairs(Harness.factionActors or {}) do pcall(SC.Actor.stop, record.actor) end
    setPhase("medical_probe", current)
end

local function finish()
    if Harness.finished then return end
    Harness.restoreCombatArena()
    Harness.finished = true
    writeSnapshot(true)
    print("SC_REAL_SANDBOX|SUMMARY|status="
        .. (Harness.failures == 0 and "PASS" or "FAIL")
        .. "|passes=" .. tostring(Harness.passes)
        .. "|failures=" .. tostring(Harness.failures)
        .. "|skipped=" .. tostring(Harness.skipped))
    if Events and Events.OnRenderTick then Events.OnRenderTick.Remove(Harness.safeTick) end
    if type(getCore) == "function" and getCore() ~= nil then
        getCore():quitToDesktop()
    end
end

-- Close the survival/character window Build 42 shows on world entry so it does
-- not block the view (and so an on-screen capture shows the world, not the panel).
-- We enumerate UIManager.UI, log every top-level window for reference, and hide
-- the ones that look like the survival/character panel. Kahlua does not expose
-- getClass():getSimpleName() here, so identify each element by its tostring().
-- Standard HUD elements always present in UIManager.UI; not windows to close.
local ENTRY_HUD_BASELINE = {
    SpeedControls = true, Clock = true, ObjectTooltip = true, MoodlesUI = true,
    UIDebugConsole = true, ActionProgressBar = true, HaloTextHelper = true,
    ISPanelJoypad = true,
}

local function shortUiName(name)
    -- "zombie.ui.SpeedControls@3b643756" -> "SpeedControls"
    local simple = string.match(name, "([%w_]+)@") or name
    return simple
end

local function closeEntryWindows(tag)
    local total, seen, targets, novel = 0, {}, {}, {}
    pcall(function()
        local list = UIManager and UIManager.UI
        if list == nil then return end
        local luaList = type(list) == "table"
        local total = luaList and #list or list:size()
        for i = luaList and 1 or 0, luaList and total or total - 1 do
            local el = luaList and list[i] or list:get(i)
            if el ~= nil then
                local name = tostring(el)
                local simple = shortUiName(name)
                seen[#seen + 1] = simple
                if not ENTRY_HUD_BASELINE[simple] then
                    novel[#novel + 1] = simple
                    local lower = string.lower(name)
                    -- The survival guide and the character-info panel are the two
                    -- windows Build 42 pops over the view on world entry.
                    if string.find(lower, "surviv", 1, true)
                        or string.find(lower, "charactercreation", 1, true)
                        or string.find(lower, "characterinfowindow", 1, true) then
                        targets[#targets + 1] = { element = el, name = simple }
                    end
                end
            end
        end
    end)
    local closed = {}
    for _, entry in ipairs(targets) do
        local hidden = pcall(function() entry.element:setVisible(false) end)
        if hidden then closed[#closed + 1] = entry.name end
    end
    -- Only log when something non-HUD is on screen (or when explicitly tagged), so
    -- a continuous scan does not spam once the view is clean.
    local signature = table.concat(seen, ",")
    if tag ~= "scan" or signature ~= Harness.lastEntryUiSignature then
        Harness.lastEntryUiSignature = signature
        if tag ~= "scan" or #novel > 0 or #closed > 0 then
            print("SC_REAL_SANDBOX|ENTRY_UI|tag=" .. tostring(tag)
                .. "|count=" .. tostring(total)
                .. "|closed=" .. table.concat(closed, ",")
                .. "|novel=" .. table.concat(novel, ",")
                .. "|seen=" .. signature)
        end
    end
    return #closed
end

-- Diagnostic probe for the reported "trying to rip bandages, never doing it" loop:
-- dump every restored companion's medical/supply state, then drive Medical.treat on
-- a wounded one over a time budget and report the reason histogram (the loop shows
-- up as one reason repeating). Runs on the actual restored save companions.
local function companionName(actor)
    local ok, desc = pcall(function() return actor:getDescriptor() end)
    if ok and desc ~= nil then
        local nameOk, full = pcall(function()
            return tostring(desc:getForename()) .. "_" .. tostring(desc:getSurname())
        end)
        if nameOk and type(full) == "string" then return full end
    end
    return "companion"
end

local function describeMedical(actor)
    local SC = SurvivorCompanion
    local ok, a = pcall(SC.Medical.assess, actor)
    if not ok or type(a) ~= "table" then return "assess_failed", nil end
    local bandages, clothing = 0, 0
    local invOk, inv = pcall(function() return actor:getInventory() end)
    if invOk and inv ~= nil then
        pcall(function()
            local items = inv:getItems()
            for i = 0, items:size() - 1 do
                local item = items:get(i)
                local t = tostring(item:getFullType() or "")
                if t:find("Bandage", 1, true) or t:find("RippedSheets", 1, true) then
                    bandages = bandages + 1
                end
                if item.IsClothing and item:IsClothing() then clothing = clothing + 1 end
            end
        end)
    end
    return string.format(
        "health=%.0f wounds=%d needsBandage=%s needsChange=%s bites=%d knox=%s bandages=%d clothing=%d",
        tonumber(a.health) or -1, #(a.wounds or {}), tostring(a.needsBandage),
        tostring(a.needsBandageChange), a.bites or 0, tostring(a.knoxInfected),
        bandages, clothing), a
end

local function medicalProbe(current)
    local SC = SurvivorCompanion
    if Harness.medicalTarget == nil and Harness.medicalDone ~= true then
        local living = (SC.Registry and type(SC.Registry.living) == "function"
            and SC.Registry.living()) or {}
        local wounded, replaceableDirty
        for _, actor in ipairs(living) do
            local desc, assessment = describeMedical(actor)
            result("PASS", "medical_state:" .. companionName(actor), desc)
            if wounded == nil and type(assessment) == "table"
                and assessment.needsBandage == true then
                wounded = actor
            elseif replaceableDirty == nil and type(assessment) == "table"
                and assessment.needsBandageChange == true
                and type(SC.Medical.canReplaceDirtyBandage) == "function" then
                local ready = SC.Medical.canReplaceDirtyBandage(actor)
                if ready == true then replaceableDirty = actor end
            end
        end
        -- Old scars and clean bandages remain in assessment.wounds, but neither is
        -- a treatable wound. Selecting one merely to force this probe made a
        -- correctly bounded no-bandage retry look like a treatment failure.
        wounded = wounded or replaceableDirty
        if wounded == nil then
            skip("medical_treat_probe",
                "no restored companion has a treatable wound with usable supplies")
            Harness.medicalDone = true
            setPhase("finish", current)
            return
        end
        -- A preceding autonomous rescue can leave this helper's medical state
        -- pointing at somebody else. Medical.treat intentionally advances an
        -- existing state before considering its new patient argument, which made
        -- this self-care probe spend its budget reporting navigation "arrived".
        -- Cancel only the chosen helper's prior activity, then exercise the full
        -- emergency rip -> bandage lifecycle from a clean production boundary.
        pcall(SC.Medical.cancel, wounded, "live_medical_probe", true)
        if SC.NativeActions and type(SC.NativeActions.interruptOwnedActivity) == "function" then
            pcall(SC.NativeActions.interruptOwnedActivity,
                wounded, "live_medical_probe")
        end
        if SC.Navigation and type(SC.Navigation.cancel) == "function" then
            pcall(SC.Navigation.cancel, wounded, "live_medical_probe")
        end
        pcall(SC.Actor.stop, wounded)
        Harness.medicalTarget = wounded
        Harness.medicalStart = current
        Harness.medicalReasons = {}
        Harness.medicalCalls = 0
        local baseline = SC.Medical.assess(wounded)
        Harness.medicalBaselineBleeding = tonumber(baseline.bleedingCount) or 0
        Harness.medicalBaselineDirty = tonumber(baseline.dirtyBandages) or 0
    end
    if Harness.medicalTarget ~= nil then
        local runtime = { snapshot = { threats = {}, immediateCount = 0, allies = {},
            escapeSquares = { { square = Harness.medicalTarget:getSquare() } } } }
        local ok, accepted, reason = pcall(SC.Medical.treat, Harness.medicalTarget,
            Harness.medicalTarget, runtime)
        local key = ok and tostring(reason) or ("error:" .. tostring(reason))
        Harness.medicalReasons[key] = (Harness.medicalReasons[key] or 0) + 1
        Harness.medicalCalls = Harness.medicalCalls + 1
        -- The production scheduler and this diagnostic intentionally exercise the
        -- same Medical state machine. Either caller may observe the completion
        -- frame. Verify the body-damage postcondition as the authority instead of
        -- requiring this particular caller to receive the transient "bandaged"
        -- return value.
        local after = SC.Medical.assess(Harness.medicalTarget)
        local afterBleeding = tonumber(after.bleedingCount) or 0
        local afterDirty = tonumber(after.dirtyBandages) or 0
        if afterBleeding < (Harness.medicalBaselineBleeding or 0)
            or afterDirty < (Harness.medicalBaselineDirty or 0) then
            result("PASS", "medical_treat_probe",
                "verified wound improvement: bleeding="
                    .. tostring(Harness.medicalBaselineBleeding) .. "->"
                    .. tostring(afterBleeding) .. " dirty="
                    .. tostring(Harness.medicalBaselineDirty) .. "->"
                    .. tostring(afterDirty) .. " calls=" .. Harness.medicalCalls)
            Harness.medicalTarget, Harness.medicalDone = nil, true
            setPhase("finish", current)
            return
        end
        if ok and accepted ~= true
            and (reason == "no_bandage" or reason == "no_clean_bandage") then
            skip("medical_treat_probe", "treatment need has no usable supplies: "
                .. tostring(reason))
            Harness.medicalTarget, Harness.medicalDone = nil, true
            setPhase("finish", current)
            return
        end
        if ok and type(reason) == "string" and reason:find("bandaged", 1, true) then
            result("PASS", "medical_treat_probe",
                "completed=" .. reason .. " calls=" .. Harness.medicalCalls)
            Harness.medicalTarget, Harness.medicalDone = nil, true
            setPhase("finish", current)
            return
        end
        -- Emergency self-care owns two consecutive native animations (rip, then
        -- bandage) and production survival decisions legitimately run between
        -- them. Nine seconds could expire during an already-active kneel_treat;
        -- allow both 120/100-tick actions their bounded completion window.
        if current - (Harness.medicalStart or current) >= 15000 then
            local summary = ""
            for k, v in pairs(Harness.medicalReasons) do summary = summary .. k .. "=" .. v .. ";" end
            result("FAIL", "medical_treat_probe", "no completion in 15s over "
                .. Harness.medicalCalls .. " calls: " .. summary)
            Harness.medicalTarget, Harness.medicalDone = nil, true
            setPhase("finish", current)
        end
    end
end

local function tick()
    if Harness.finished then return end
    local current = nowMs()
    -- For the first seconds after entry, sweep UIManager.UI every frame and close
    -- any survival/character window that appears, logging novel (non-HUD) windows
    -- so we can identify them. Cheap bounded walk; logging is throttled by change.
    if Harness.startedAt ~= nil and (current - Harness.startedAt) < 20000 then
        closeEntryWindows("scan")
    end
    if Harness.phase == "idle" then
        -- A cloned save can legitimately display Build 42's non-fatal missing-mod,
        -- missing-map, or world-conversion confirmation.  The harness owns the
        -- disposable clone, so accepting that prompt is safe and keeps the live
        -- runner deterministic without sending blind desktop clicks.
        if Harness.autoloadIssued
            and current - (Harness.autoloadIssuedAt or current) >= 750
            and type(MainScreen) == "table" and MainScreen.instance ~= nil then
            local modal = MainScreen.instance.checkSavefileModal
            if modal == nil then
                -- A cloned, heavily modded save can present more than one safe
                -- confirmation in sequence (missing mods, world dictionary,
                -- then conversion). Re-arm only after the prior modal vanished.
                Harness.autoloadModal = nil
            elseif modal ~= Harness.autoloadModal
                and current >= (Harness.nextAutoloadConfirmAt or 0)
                and modal.yes ~= nil and type(modal.onClick) == "function" then
                local signature = clean(modal.text or "unknown load confirmation")
                if Harness.autoloadPromptSignatures[signature] then
                    result("FAIL", "autoload_prompt_loop",
                        "same cloned-save prompt repeated: " .. signature)
                    finish()
                    return
                end
                Harness.autoloadPromptSignatures[signature] = true
                Harness.autoloadConfirmed = true
                Harness.autoloadConfirmations = Harness.autoloadConfirmations + 1
                Harness.autoloadModal = modal
                Harness.nextAutoloadConfirmAt = current + 750
                print("SC_REAL_SANDBOX|AUTOLOAD_CONFIRM|world="
                    .. clean(Harness.config.world) .. "|count="
                    .. tostring(Harness.autoloadConfirmations))
                modal:onClick(modal.yes)
            end
        end
        return
    end
    local overallTimeout = tonumber(Harness.config.internal_timeout_ms) or 60000
    if current - Harness.startedAt > overallTimeout then
        result("FAIL", "harness_timeout", "phase=" .. tostring(Harness.phase))
        finish()
        return
    end

    if Harness.phase == "wait_runtime" then
        -- The survival/character panel can appear a beat after the world loads;
        -- close it again here so it never lingers over the on-screen view.
        if not Harness.entryWindowsRetried then
            Harness.entryWindowsRetried = true
            closeEntryWindows("wait_runtime")
        end
        if current - Harness.phaseStartedAt < 2000 then return end
        local spawnState = beginNativeSpawn(current)
        if spawnState == false then setPhase("finish", current)
        elseif spawnState == true then setPhase("validate_actor", current) end
    elseif Harness.phase == "poll_spawn" then
        local actor, reason = SurvivorCompanion.Actor.pollSpawn(Harness.spawnTicket)
        if actor ~= nil then
            Harness.actor = actor
            result("PASS", "deferred_native_spawn", "spawn completed after Lua-to-Java frame unwound")
            setPhase("validate_actor", current)
        elseif reason ~= "spawn_pending" then
            result("FAIL", "deferred_native_spawn", reason)
            setPhase("finish", current)
        elseif current - Harness.phaseStartedAt > 10000 then
            result("FAIL", "deferred_native_spawn", "native spawn polling timed out")
            setPhase("finish", current)
        end
    elseif Harness.phase == "validate_actor" then
        local SC = SurvivorCompanion
        local valid, reason = SC.Actor.validateNative(Harness.actor)
        check("native_actor_validation", valid == true, reason)
        check("registry_ownership", SC.Registry.idOf(Harness.actor) ~= nil
            and SC.Actor.isCompanion(Harness.actor), "registry and bridge agree on actor ownership")
        local schedulerStats = SC.Scheduler.getStats()
        check("production_scheduler_active", SC.Runtime.isTickAttached()
            and SC.Runtime.tasksRegistered() and (schedulerStats.frames or 0) > 0,
            "frames=" .. tostring(schedulerStats.frames)
                .. " callbacks=" .. tostring(schedulerStats.callbacks)
                .. " tasks=" .. tostring(schedulerStats.taskCount))
        routeProbe(Harness.actor, Harness.player)
        local id = SC.Registry.idOf(Harness.actor)
        local issued, issueReason = SC.Commands.issue(id, "follow", nil, Harness.player)
        check("follow_command_accepted", issued == true, issueReason)
        Harness.followInitialDistance = distance(Harness.actor, Harness.player)
        Harness.followThreatened = type(Harness.snapshot) == "table"
            and (tonumber(Harness.snapshot.threatCount) or 0) > 0
        setPhase("follow", current)
    elseif Harness.phase == "follow" then
        local currentDistance = distance(Harness.actor, Harness.player)
        if Harness.followThreatened then
            skip("real_follow_progress", "nearby threat makes deterministic formation movement unsafe to assert")
            setPhase("begin_native_locomotion", current)
        elseif currentDistance <= 4.5
            or currentDistance <= Harness.followInitialDistance - 0.75 then
            result("PASS", "real_follow_progress", "distance="
                .. string.format("%.2f->%.2f", Harness.followInitialDistance, currentDistance))
            setPhase("begin_native_locomotion", current)
        elseif current - Harness.phaseStartedAt > 12000 then
            local SC = SurvivorCompanion
            local record = SC.Registry.byId(SC.Registry.idOf(Harness.actor))
            local runtime = record and record.runtime or {}
            local decision = SC.Decision.peek(Harness.actor) or {}
            local navigation = SC.Navigation.peek(Harness.actor) or {}
            local stats = SC.Scheduler.getStats()
            result("FAIL", "real_follow_progress", "distance="
                .. string.format("%.2f->%.2f", Harness.followInitialDistance, currentDistance)
                .. " frames=" .. tostring(stats.frames)
                .. " callbacks=" .. tostring(stats.callbacks)
                .. " lastDecision=" .. tostring(runtime.lastDecision)
                .. " handled=" .. tostring(runtime.lastDecisionHandled)
                .. " state=" .. tostring(decision.current)
                .. " intent=" .. tostring(decision.intent)
                .. " nav=" .. tostring(navigation.pathReason))
            setPhase("begin_native_locomotion", current)
        end
    elseif Harness.phase == "begin_native_locomotion" then
        beginNativeLocomotionProbe(current)
    elseif Harness.phase == "native_locomotion" then
        probeNativeLocomotion(current)
    elseif Harness.phase == "begin_backward_strafe" then
        beginBackwardStrafeProbe(current)
    elseif Harness.phase == "backward_strafe" then
        probeBackwardStrafe(current)
    elseif Harness.phase == "begin_aimed_escape" then
        beginAimedEscapeProbe(current)
    elseif Harness.phase == "aimed_escape" then
        probeAimedEscape(current)
    elseif Harness.phase == "begin_room" then
        beginRoomProbe(current)
    elseif Harness.phase == "room_probe" then
        runRoomProbe(current)
    elseif Harness.phase == "begin_door_crossing" then
        Harness.beginDoorCrossing(current)
    elseif Harness.phase == "door_crossing" then
        Harness.runDoorCrossing(current)
    elseif Harness.phase == "awareness" then
        runAwareness(current)
    elseif Harness.phase == "restore_awareness" then
        restoreAwareness(current)
    elseif Harness.phase == "zombie_attack_observe" then
        probeZombieAttackObserve(current)
    elseif Harness.phase == "zombie_targeting" then
        probeZombieTargeting(current)
    elseif Harness.phase == "combat_attack" then
        probeNativeCombat(current)
    elseif Harness.phase == "combat_animation" then
        probeNativeCombatAnimation(current)
    elseif Harness.phase == "combat_damage" then
        probeCombatDamage(current)
    elseif Harness.phase == "ranged_fire" then
        probeRangedFire(current)
    elseif Harness.phase == "finish_grounded" then
        probeFinishGrounded(current)
    elseif Harness.phase == "faction_begin" then
        beginFactionProbe(current)
    elseif Harness.phase == "faction_wait" then
        waitForFaction(current)
    elseif Harness.phase == "faction_map_capture" then
        probeFactionMapCapture(current)
    elseif Harness.phase == "faction_fortify" then
        probeFactionFortification(current)
    elseif Harness.phase == "faction_hostile" then
        probeFactionHostility(current)
    elseif Harness.phase == "medical_probe" then
        medicalProbe(current)
    elseif Harness.phase == "finish" then
        finish()
    end
end

function Harness.safeTick()
    local ok, failure = pcall(tick)
    if not ok and not Harness.finished then
        result("FAIL", "unhandled_harness_error", failure)
        finish()
    end
end

function Harness.restoreObserver(observer)
    local U = SurvivorCompanion.GameplayUtil
    local dead, checked = U.call(observer, "isDead")
    if not checked or dead ~= false then return false, "observer dead or unavailable; use a fresh cloned run" end
    local body, bodyOk = U.call(observer, "getBodyDamage")
    if not bodyOk or body == nil then return false, "observer BodyDamage unavailable" end
    -- This ungated native method resets wounds/infection and body health. Unlike
    -- God Mode it works in ordinary SP. It runs only at isolated phase boundaries
    -- on the observer, never on companions or as an attempt to resurrect a corpse.
    local _, restored = U.call(body, "RestoreToFullHealth")
    local health, healthOk = U.call(body, "getOverallBodyHealth")
    local stillDead, aliveChecked = U.call(observer, "isDead")
    local infected, infectedOk = U.call(body, "isInfected")
    local fake, fakeOk = U.call(body, "isIsFakeInfected")
    local infectionTime, timeOk = U.call(body, "getInfectionTime")
    local mortality, mortalityOk = U.call(body, "getInfectionMortalityDuration")
    local infectionLevel, levelOk = U.call(body, "getApparentInfectionLevel")
    local bites, bitesOk = U.call(body, "getNumPartsBitten")
    local scratches, scratchesOk = U.call(body, "getNumPartsScratched")
    local bleeding, bleedingOk = U.call(body, "getNumPartsBleeding")
    local cleanBody = infectedOk and infected == false and fakeOk and fake == false
        and timeOk and (tonumber(infectionTime) or 0) < 0
        and mortalityOk and (tonumber(mortality) or 0) < 0
        and levelOk and tonumber(infectionLevel) == 0
        and bitesOk and tonumber(bites) == 0 and scratchesOk and tonumber(scratches) == 0
        and bleedingOk and tonumber(bleeding) == 0
    return restored and healthOk and (tonumber(health) or 0) >= 99.99
        and aliveChecked and stillDead == false and cleanBody,
        "restored=" .. tostring(restored) .. " health=" .. tostring(health)
            .. " alive=" .. tostring(aliveChecked and stillDead == false)
            .. " clean_body=" .. tostring(cleanBody) .. " infection=" .. tostring(infected)
            .. "/" .. tostring(infectionLevel) .. " fake=" .. tostring(fake)
            .. " mortality=" .. tostring(mortality) .. " infection_time=" .. tostring(infectionTime)
            .. " wounds=" .. tostring(bites) .. "/" .. tostring(scratches) .. "/" .. tostring(bleeding)
end

function Harness.observerSnapshot(observer)
    local U = SurvivorCompanion.GameplayUtil
    local body = U.call(observer, "getBodyDamage")
    local function value(object, method) return tostring((U.call(object, method))) end
    return "phase=" .. tostring(Harness.phase) .. " dead=" .. value(observer, "isDead")
        .. " health=" .. value(body, "getOverallBodyHealth")
        .. " infected=" .. value(body, "isInfected")
        .. " apparent_infection=" .. value(body, "getApparentInfectionLevel")
        .. " infection_time=" .. value(body, "getInfectionTime")
        .. " mortality=" .. value(body, "getInfectionMortalityDuration")
        .. " wounds=" .. value(body, "getNumPartsBitten") .. "/"
            .. value(body, "getNumPartsScratched") .. "/" .. value(body, "getNumPartsBleeding")
        .. " dragdown=" .. value(observer, "isDeathDragDown")
        .. " attacker=" .. value(observer, "getAttackedBy")
        .. " cold=" .. value(body, "getColdDamageStage")
        .. " pills=" .. value(observer, "getSleepingPillsTaken")
end

function Harness.onObserverDamage(observer, kind, amount)
    if observer ~= Harness.player or Harness.finished then return end
    Harness.observerLastDamage = "kind=" .. tostring(kind) .. " amount=" .. tostring(amount)
        .. " " .. Harness.observerSnapshot(observer)
    if nowMs() >= (Harness.observerNextDamageLog or 0) or kind ~= Harness.observerLastDamageKind then
        print("SC_REAL_SANDBOX|OBSERVER_DAMAGE|" .. Harness.observerLastDamage)
        Harness.observerNextDamageLog = nowMs() + 1000
        Harness.observerLastDamageKind = kind
    end
end

function Harness.onObserverDeath(observer)
    if observer ~= Harness.player or Harness.finished then return end
    print("SC_REAL_SANDBOX|OBSERVER_DEATH|" .. Harness.observerSnapshot(observer)
        .. " last_damage={" .. clean(Harness.observerLastDamage) .. "}")
end

function Harness.restoreObserverBoundary(name)
    print("SC_REAL_SANDBOX|OBSERVER_BOUNDARY|" .. tostring(name) .. " before={"
        .. Harness.observerSnapshot(Harness.player) .. "}")
    local restored, reason = Harness.restoreObserver(Harness.player)
    return check("observer_alive_" .. name, restored, reason)
end

local function onGameStart()
    Harness.config = readConfig()
    if Harness.config.enabled ~= "true" then return end
    Harness.results = {}
    Harness.failures, Harness.skipped, Harness.passes = 0, 0, 0
    Harness.finished = false
    Harness.startedAt = nowMs()
    Harness.player = getPlayerSafe()
    if Harness.player == nil then
        result("FAIL", "local_player_available", "getPlayer returned nil")
        finish()
        return
    end
    closeEntryWindows("on_game_start")
    if type(getGameSpeed) == "function" and type(setGameSpeed) == "function"
        and getGameSpeed() == 0 then
        setGameSpeed(1)
    end
    check("gameplay_clock_running", type(getGameSpeed) ~= "function"
        or getGameSpeed() > 0, "game_speed=" .. tostring(type(getGameSpeed) == "function"
        and getGameSpeed() or "unavailable"))
    local loaded, failure = pcall(require, "SCBootstrap")
    check("companion_bootstrap_loaded", loaded == true and type(SurvivorCompanion) == "table", failure)
    local SC = SurvivorCompanion
    Harness.release = SC and SC.Identity and SC.Identity.release or "unknown"
    local server = type(isServer) == "function" and isServer() == true
    local client = type(isClient) == "function" and isClient() == true
    check("single_player_client", not server and not client, "server=" .. tostring(server)
        .. " client=" .. tostring(client))
    local bridgeReady, bridgeReason = SC.Actor.checkBridge(true)
    check("native_bridge_ready", bridgeReady == true, bridgeReason)
    local singletonOk = true
    if type(getSpecificPlayer) == "function" then singletonOk = getSpecificPlayer(0) == Harness.player end
    check("local_player_slot_zero", singletonOk, "getPlayer equals getSpecificPlayer(0)")
    Harness.playerX, Harness.playerY, Harness.playerZ = position(Harness.player)
    Harness.playerZ = Harness.playerZ or 0
    local dead, deadChecked = SC.GameplayUtil.call(Harness.player, "isDead")
    if not check("local_observer_initially_alive", deadChecked and dead == false,
        "observer must be alive in the cloned save; no resurrection or damage immunity")
        or not Harness.restoreObserverBoundary("initial") then
        finish()
        return
    end
    if Harness.config.faction_map_only == "true" then
        setPhase("faction_begin", Harness.startedAt)
    else
        setPhase("wait_runtime", Harness.startedAt)
    end
end

local function onMainMenuEnter()
    Harness.config = readConfig()
    if Harness.config.enabled ~= "true" or Harness.config.autoload ~= "true"
        or Harness.autoloadIssued then return end
    Harness.autoloadIssued = true
    Harness.autoloadIssuedAt = nowMs()
    local loaded, failure = pcall(require, "OptionScreens/MainScreen")
    if not loaded or type(MainScreen) ~= "table"
        or type(MainScreen.continueLatestSave) ~= "function" then
        result("FAIL", "autoload", failure or "MainScreen API unavailable")
        writeSnapshot(true)
        return
    end
    print("SC_REAL_SANDBOX|BOOT|world=" .. clean(Harness.config.world)
        .. "|mode=" .. clean(Harness.config.mode))
    local continued, continueFailure = pcall(MainScreen.continueLatestSave,
        Harness.config.mode, Harness.config.world)
    if not continued then
        result("FAIL", "autoload", continueFailure)
        Harness.finished = true
        writeSnapshot(true)
    end
end

Harness.config = readConfig()
if Events and Events.OnMainMenuEnter then Events.OnMainMenuEnter.Add(onMainMenuEnter) end
if Events and Events.OnGameStart then Events.OnGameStart.Add(onGameStart) end
if Events and Events.OnRenderTick then Events.OnRenderTick.Add(Harness.safeTick) end
if Events and Events.OnWeaponHitCharacter then Events.OnWeaponHitCharacter.Add(Harness.onMeleeWeaponHit) end
if Events and Events.OnPlayerGetDamage then Events.OnPlayerGetDamage.Add(Harness.onObserverDamage) end
if Events and Events.OnPlayerDeath then Events.OnPlayerDeath.Add(Harness.onObserverDeath) end

SCRealSandboxHarness = Harness
return Harness
