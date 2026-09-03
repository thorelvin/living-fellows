-- SPDX-License-Identifier: MIT
-- Private live integration harness. This file is installed only in a disposable
-- cachedir created by Invoke-LiveSandboxTests.ps1; it is never packaged with the mod.

local CONFIG_FILE = "SurvivorCompanionHarness/config.ini"
local EVENTS_FILE = "SurvivorCompanionHarness/events.log"
local SUMMARY_FILE = "SurvivorCompanionHarness/summary.txt"

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
        setPhase("awareness", current)
        return
    end
    local id = SC.Registry.idOf(Harness.actor)
    if id then pcall(SC.Commands.issue, id, "stay", nil, Harness.player) end
    local recovered, reason = SC.Actor.recover(Harness.actor, source)
    if recovered ~= true then
        result("FAIL", "real_room_entry_sweep", "native relocation failed: " .. clean(reason))
        setPhase("awareness", current)
        return
    end
    SC.Navigation.reset(Harness.actor)
    local control, controlReason = beginHarnessControl(
        Harness.actor, "room_entry_probe", 12000)
    if control == nil then
        result("FAIL", "real_room_entry_sweep",
            "control ownership rejected: " .. clean(controlReason))
        setPhase("awareness", nowMs())
        return
    end
    Harness.roomSupervisorToken = control
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
        setPhase("awareness", current)
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
        setPhase("awareness", current)
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
        setPhase("awareness", current)
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
        "anim_updating=" .. clean(read("isAnimationUpdatingThisFrame")),
        -- Why a started attack may still fail to become a resolved swing: the
        -- actor's root state, hand-to-hand/floor intent, any native collision,
        -- and whether the intended target actually took damage.
        "state=" .. clean(read("getCurrentState")),
        "do_shove=" .. clean(read("isDoShove")),
        "aim_floor=" .. clean(read("isAimAtFloor")),
        "col_vehicle=" .. clean(read("isCollidedWithVehicle")),
        "col_door=" .. clean(read("isCollidedWithDoor")),
        "col_object=" .. clean(read("getCollidedObject")),
        "target_health=" .. clean(observed(utility.call(target, "getHealth"))),
        "target_dead=" .. clean(observed(utility.call(target, "isDead"))),
        "group_control=" .. clean(Harness.combatActionGroupControl or "none"),
    }, ",")
end

local function pinTestZombieAhead()
    local ax, ay, az = position(Harness.actor)
    local z = Harness.testZombie
    if ax == nil or z == nil then return end
    pcall(function() z:setTarget(nil) end)
    pcall(function() z:setX(ax + 1.0) end)
    pcall(function() z:setY(ay) end)
    pcall(function() z:setZ(az or 0) end)
    pcall(function() z:setCurrentSquareFromPosition() end)
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
                .. " z_attackedby=" .. tostring(select(1, SC.GameplayUtil.call(
                    Harness.testZombie, "getAttackedBy")) ~= nil))
        cleanupCombat(current)
        return
    end
    if current >= (Harness.combatNextAttemptAt or 0) then
        local performing = select(1, SC.GameplayUtil.call(
            Harness.actor, "isPerformingAttackAnimation"))
        if performing ~= true then
            pinTestZombieAhead()
            local accepted = SC.Actor.setMovement(Harness.actor, "walk", {
                action = "attack_melee", target = Harness.testZombie,
                weapon = Harness.combatWeapon, urgent = true, emergency = true,
                supervisorToken = Harness.combatSupervisorToken,
            })
            if accepted == true then
                Harness.combatSwingCount = (Harness.combatSwingCount or 0) + 1
            end
            Harness.combatNextAttemptAt = current + 700
        end
    end
end

local function probeNativeCombat(current)
    if current - Harness.phaseStartedAt < 300 then return end
    if current < (Harness.combatNextAttemptAt or 0) then return end
    Harness.combatNextAttemptAt = current + 125
    local SC = SurvivorCompanion
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
        Harness.combatAnimationObserved = false
        Harness.combatAttackType = tostring(typeValue)
        -- Read how many targets CombatManager found for this swing. Size 0 means
        -- calcValidTargets rejected the target (no valid target => AttackType.MISS);
        -- size > 0 means a target was found and any miss is a hit roll.
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
    if current - Harness.phaseStartedAt > 5000 then
        finishCombatProbe(current, false,
            "timed out after exact Build 42 attack preflight: " .. clean(reason))
    end
end

local function probeNativeCombatAnimation(current)
    local SC = SurvivorCompanion
    local performing, performingOk = SC.GameplayUtil.call(
        Harness.actor, "isPerformingAttackAnimation")
    local started, startedOk = SC.GameplayUtil.call(Harness.actor, "isAttackStarted")
    if performingOk and performing == true then
        Harness.combatAnimationObserved = true
    end
    if Harness.combatAnimationObserved == true and startedOk and started ~= true
        and (not performingOk or performing ~= true) then
        result("PASS", "direct_native_melee_attack",
            "adapter=" .. clean(Harness.combatLastReason)
                .. " attack_type=" .. clean(Harness.combatAttackType)
                .. " hit_targets=" .. tostring(Harness.combatHitListSize)
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

-- Verify a companion finishes a fallen zombie: knock a real zombie to the ground
-- and confirm the companion's floor finisher (stomp) actually lands damage and
-- kills it -- the native attack must resolve against a prone target, which the
-- stance filter otherwise skips for an ordinary standing swing.
local function endFinishGrounded(current, zombie)
    if zombie ~= nil then cleanupTestZombie(zombie) end
    Harness.finishZombie = nil
    -- Clear the floor-aim / downed-target residue the stomp leaves behind so the
    -- following standing melee phase starts from a clean, upright attack posture.
    pcall(function() Harness.actor:setAimAtFloor(false) end)
    pcall(function() Harness.actor.targetOnGround = nil end)
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
        local okSpawn, zs = pcall(addZombiesInOutfit,
            math.floor(ax) + 1, math.floor(ay), math.floor(az or 0), 1, nil, 0)
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
        if ax ~= nil then
            pcall(function() zombie:setX(ax + 1.0) end)
            pcall(function() zombie:setY(ay) end)
            pcall(function() zombie:setCurrentSquareFromPosition() end)
        end
        SC.GameplayUtil.call(Harness.actor, "setCompanionAimTarget", zombie)
        Harness.finishZombie = zombie
        Harness.finishStart = current
        Harness.finishNextAt = current + 700
        Harness.finishStomps = 0
        local hp0v = select(1, U.call(zombie, "getHealth"))
        Harness.finishHp0 = tonumber(hp0v)
        return
    end
    local zombie = Harness.finishZombie
    local hpValue = select(1, U.call(zombie, "getHealth"))
    local hp = tonumber(hpValue)
    local dead = select(1, U.call(zombie, "isDead")) == true
    local prone = select(1, U.call(zombie, "isProne")) == true
        or select(1, U.call(zombie, "isOnFloor")) == true
    local headHitsV = select(1, U.call(zombie, "getHitHeadWhileOnFloor"))
    local headHits = tonumber(headHitsV) or 0
    if dead or (Harness.finishHp0 and hp and hp < Harness.finishHp0 - 0.0001) then
        check("native_companion_finishes_grounded", true,
            "grounded zombie finished: hp " .. tostring(Harness.finishHp0) .. "->" .. tostring(hp)
                .. " dead=" .. tostring(dead) .. " was_prone=" .. tostring(prone)
                .. " head_hits=" .. tostring(headHits)
                .. " stomps=" .. tostring(Harness.finishStomps))
        endFinishGrounded(current, zombie); return
    end
    if current - Harness.finishStart > 12000 then
        check("native_companion_finishes_grounded", false,
            "grounded zombie not finished in 12s: prone=" .. tostring(prone)
                .. " hp=" .. tostring(hp) .. " head_hits=" .. tostring(headHits)
                .. " stomps=" .. tostring(Harness.finishStomps)
                .. " reject=" .. clean(Harness.finishLastReason or "none")
                .. " a_state=" .. clean(v(Harness.actor, "getCompanionActionStateName")))
        endFinishGrounded(current, zombie); return
    end
    -- Keep it grounded and pinned adjacent so the finisher has a clean target;
    -- getHeadSquare is companion-relative, so an adjacent downed zombie already
    -- puts the head within the finisher's stomp reach (no need to move the actor).
    pcall(function() zombie:knockDown(true) end)
    local ax, ay = position(Harness.actor)
    local distValue = select(1, U.call(Harness.actor, "DistTo", zombie))
    if ax ~= nil and (tonumber(distValue) or 9) > 1.5 then
        pcall(function() zombie:setX(ax + 1.0) end)
        pcall(function() zombie:setY(ay) end)
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
            else
                Harness.finishLastReason = reason
            end
            Harness.finishNextAt = current + 700
        end
    end
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
            local accepted = SC.Actor.setMovement(Harness.actor, "walk", {
                action = "attack_firearm", target = zombie, weapon = gun,
                urgent = true, emergency = true, supervisorToken = Harness.rangedControl })
            if accepted == true then Harness.rangedShots = (Harness.rangedShots or 0) + 1 end
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
        if type(addZombiesInOutfit) ~= "function" then
            skip("native_zombie_attacks_companion", "addZombiesInOutfit unavailable")
            setPhase("zombie_targeting", current); return
        end
        local ax, ay, az = position(Harness.actor)
        if ax == nil then
            skip("native_zombie_attacks_companion", "companion has no position")
            setPhase("zombie_targeting", current); return
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
        -- Ghost the local player so the pack does not wander off to player 0.
        Harness.zObservePlayerGhost = select(1, U.call(Harness.player, "isGhostMode")) == true
        pcall(function() Harness.player:setGhostMode(true) end)
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
    -- Drive the incoming-attack resolver each tick (the production runtime does
    -- this from the decision loop): a zombie landing a swing in reach writes a
    -- real BodyDamage wound to the companion.
    if SC.ZombieAttack and type(SC.ZombieAttack.resolve) == "function" then
        local rok, _, _, rd = pcall(SC.ZombieAttack.resolve, Harness.actor, current, zombies)
        if rok and type(rd) == "table" then
            Harness.zObservePile = math.max(Harness.zObservePile or 0, tonumber(rd.pile) or 0)
            Harness.zObserveAtk = math.max(Harness.zObserveAtk or 0, tonumber(rd.attackers) or 0)
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
        check("native_zombie_attacks_companion", true,
            "wounds=" .. tostring(wounds) .. " attackedBy=" .. tostring(attackedBy ~= nil)
                .. " engaged=" .. tostring(Harness.zObserveEngaged))
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
    -- Remove hit-chance: max the blade skills so an in-range, faced swing lands.
    pcall(function()
        if Perks ~= nil then
            for _, perk in ipairs({ Perks.LongBlade, Perks.Blade, Perks.Axe }) do
                if perk ~= nil then Harness.actor:setPerkLevelDebug(perk, 10) end
            end
        end
    end)
    -- Freeze the target one clean tile ahead so it stays in the swing band
    -- through the whole swing. A stationary probe actor cannot follow a wandering
    -- zombie, and per-frame teleporting fights the aim; stopping its movement is
    -- clean.
    do
        local ax, ay, az = position(Harness.actor)
        if ax ~= nil then
            pcall(function() zombie:setX(ax + 1.0) end)
            pcall(function() zombie:setY(ay) end)
            pcall(function() zombie:setZ(az or 0) end)
            pcall(function() zombie:setCurrentSquareFromPosition() end)
        end
        pcall(function() zombie:setTarget(nil) end)
        pcall(function() zombie:setPathing(false) end)
        pcall(function() zombie:setSpeedMod(0.0) end)
        pcall(function() zombie:setPath2(nil) end)
    end
    SC.GameplayUtil.call(Harness.actor, "setCompanionAimTarget", zombie)
    Harness.combatNextAttemptAt = current + 600
    setPhase("combat_attack", current)
end

local function beginFactionProbe(current)
    local SC = SurvivorCompanion
    check("debug_faction_tools_enabled", SC.Config.get("debugSpawnEnabled") == true,
        "isolated harness uses the private debug payload")
    local spawned, factionId = SC.Factions.debugSpawnHousehold(Harness.player, 2)
    if not spawned then
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
        if stalledFor > 20000 or elapsed > 45000 then
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
    if not progressed and current - Harness.phaseStartedAt < 20000 then return end
    if threatened and not progressed then
        skip("native_faction_barricade_work", "nearby zombies correctly preempted construction")
    else
        check("native_faction_barricade_work", progressed,
            "a real timed barricade job became active or completed")
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
    setPhase("faction_hostile", current)
end

local function probeFactionHostility(current)
    if current - Harness.phaseStartedAt < 4500 then return end
    local SC = SurvivorCompanion
    local engaged = false
    for _, record in ipairs(Harness.factionActors or {}) do
        local decision = SC.Decision.peek(record.actor) or {}
        local reason = tostring(record.runtime and record.runtime.lastDecision or "")
        if decision.current == "faction" or string.find(reason, "attack", 1, true)
            or string.find(reason, "territory", 1, true) then engaged = true end
    end
    check("native_human_targeting", engaged,
        "hostile residents selected the player through the native faction decision path")
    SC.Factions.forceStanding(Harness.factionId, "Wary")
    for _, record in ipairs(Harness.factionActors or {}) do pcall(SC.Actor.stop, record.actor) end
    setPhase("finish", current)
end

local function finish()
    if Harness.finished then return end
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
        total = list:size()
        for i = 0, total - 1 do
            local el = list:get(i)
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
        pcall(function() entry.element:removeFromUIManager() end)
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
            setPhase("begin_room", current)
        elseif currentDistance <= 4.5
            or currentDistance <= Harness.followInitialDistance - 0.75 then
            result("PASS", "real_follow_progress", "distance="
                .. string.format("%.2f->%.2f", Harness.followInitialDistance, currentDistance))
            setPhase("begin_room", current)
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
            setPhase("begin_room", current)
        end
    elseif Harness.phase == "begin_room" then
        beginRoomProbe(current)
    elseif Harness.phase == "room_probe" then
        runRoomProbe(current)
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
    elseif Harness.phase == "faction_fortify" then
        probeFactionFortification(current)
    elseif Harness.phase == "faction_hostile" then
        probeFactionHostility(current)
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
    setPhase("wait_runtime", Harness.startedAt)
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

SCRealSandboxHarness = Harness
return Harness
