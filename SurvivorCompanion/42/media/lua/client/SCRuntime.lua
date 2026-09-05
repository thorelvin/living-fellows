-- SPDX-License-Identifier: MIT

require "SCNamespace"
require "SCCall"
require "SCConfig"
require "SCDiagnostics"
require "SCRegistry"
require "SCScheduler"
require "SCPerformance"
require "SCActor"
require "SCPersistence"
require "SCVehicle"
require "SCSpawn"
require "SCFactions"
require "SCTrade"
require "SCFactionBehavior"
require "SCFactionContracts"
require "SCFactionWorld"
require "SCZombieTargeting"
require "SCZombieAttack"
require "SCBaseLife"
require "SCBaseWork"
require "SCInfectionCrisis"
require "SCLifeEvents"
require "SCCommunity"
require "SCAutonomy"
require "SCCommands"
require "SCFactionRecruitment"

local SC = SurvivorCompanion
SC.Runtime = SC.Runtime or {}

local runtime = SC.Runtime
local tickAttached = false
local tasksRegistered = false
local running = false
local lastStartReady = false
local lastStartReason = nil
local startupCommitted = false
local restoreCommitted = false
local startupFailureReason = "runtime has not started"
local teardownPending = false
local decisionCursor = 1
local criticalCursor = 1
local vitalsCursor = 1
local lastPlayerVehicle = nil
local vehicleRestoreDeadline = nil
local originalSelectContainer = nil
local originalSetNewContainer = nil
local selectContainerWrapper = nil
local setNewContainerWrapper = nil
local unpackReturns = table.unpack or unpack
local function packReturns(...) return { n = select("#", ...), ... } end
local lastDisabledNoticeAt = -math.huge
local lastDebugSpawnReportAt = -math.huge
local lastDebugSpawnReason = nil

local function nowMs()
    if type(getTimestampMs) == "function" then
        local ok, value = pcall(getTimestampMs)
        local numeric = ok and tonumber(value) or nil
        if numeric ~= nil then return numeric end
    end
    return math.floor(os.clock() * 1000)
end

local function player()
    if type(getPlayer) ~= "function" then return nil end
    local ok, value = pcall(getPlayer)
    return ok and value or nil
end

local function multiplayerActive()
    for _, callback in ipairs({ isClient, isServer }) do
        if type(callback) == "function" then
            local ok, value = pcall(callback)
            if ok and value == true then return true end
        end
    end
    return false
end

local function translated(key, fallback, ...)
    if type(getText) == "function" then
        local ok, value = pcall(getText, key, ...)
        if ok and type(value) == "string" and value ~= "" and value ~= key then return value end
    end
    return fallback
end

local function method(object, name)
    if object == nil then return nil end
    local ok, value = pcall(function() return object[name] end)
    return ok and type(value) == "function" and value or nil
end

local function invoke(object, name, ...)
    return SC.Call.method(object, name, ...)
end

local function notifyDisabled(reason)
    local current = nowMs()
    if current - lastDisabledNoticeAt < SC.Config.get("disabledNoticeCooldownMs") then return false end
    lastDisabledNoticeAt = current
    local message
    if multiplayerActive() then
        message = translated("UI_SC_RuntimeDisabled_Multiplayer",
            "Living Fellows: Companion supports single-player only.")
    else
        message = translated("UI_SC_RuntimeDisabled_Provider",
            "Companion spawning is unavailable: " .. tostring(reason), tostring(reason))
    end
    local currentPlayer = player()
    local shown = false
    if currentPlayer ~= nil then
        shown = invoke(currentPlayer, "setHaloNote", message, 255, 180, 80, 300)
        if not shown then shown = invoke(currentPlayer, "setHaloNote", message) end
    end
    if not shown then print("[SurvivorCompanion] " .. message) end
    return shown
end

local function nextRecord(cursor)
    local records = SC.Registry.records()
    if #records == 0 then return nil, 1 end
    if cursor > #records then cursor = 1 end
    local record = records[cursor]
    cursor = cursor + 1
    if cursor > #records then cursor = 1 end
    return record, cursor
end

local function commandState(record)
    if SC.Commands and type(SC.Commands.peek) == "function" then
        local ok, value = pcall(SC.Commands.peek, record.actor)
        if ok and type(value) == "table" then return value end
    end
    return { recruited = record.recruited == true }
end

local function observedZombieCandidates(runtime)
    runtime = type(runtime) == "table" and runtime or {}
    local snapshot = type(runtime.senses) == "table" and runtime.senses.current
        or runtime.snapshot
    local threats = type(snapshot) == "table" and snapshot.threats or nil
    local candidates = {}
    if type(threats) ~= "table" then return candidates end
    for _, threat in ipairs(threats) do
        local actor = type(threat) == "table" and threat.actor or threat
        if actor ~= nil then candidates[#candidates + 1] = actor end
    end
    return candidates
end

local function recoverySquare(currentPlayer)
    local utility = SC.GameplayUtil
    if not utility or not currentPlayer then return nil end
    local x, y, z = utility.position(currentPlayer)
    if not x then return nil end
    for radius = 2, 6 do
        for dx = -radius, radius do
            for dy = -radius, radius do
                if math.max(math.abs(dx), math.abs(dy)) == radius then
                    local square = utility.gridSquare(x + dx, y + dy, z)
                    if square and utility.isSquareFree(square) then return square end
                end
            end
        end
    end
    return nil
end

local function recordServiceable(record)
    if record == nil or record.actor == nil then return false end
    -- A valid string id is required: it keys the serviced set and every dueFor
    -- clock, so a malformed record is skipped rather than risking a nil-key write.
    if type(record.id) ~= "string" or record.id == "" then return false end
    local rt = record.runtime
    if type(rt) == "table" and (rt.inactive == true or rt.dying == true) then return false end
    return true
end

-- Cheap emergency probe used to route an actor into the critical decision lane.
-- A zombie grab is read live (always fresh, and the most time-critical case); the
-- rest come from the actor's last decision/senses pass. Once an actor senses a
-- threat it stays critical and keeps getting fast service until the danger clears,
-- while first detection of a brand-new threat still comes from the (now
-- multi-actor) ordinary round-robin below.
local function recordIsCritical(record)
    if SC.ZombieAttack and type(SC.ZombieAttack.isGrabbed) == "function"
        and SC.ZombieAttack.isGrabbed(record.actor) == true then
        return true
    end
    local rt = type(record.runtime) == "table" and record.runtime or nil
    if rt == nil then return false end
    if rt.downed == true or rt.needsRescue == true then return true end
    local snapshot = type(rt.senses) == "table" and rt.senses.current or rt.snapshot
    if type(snapshot) == "table" then
        if (tonumber(snapshot.immediateCount) or 0) >= 1 then return true end
        if (tonumber(snapshot.threatCount) or 0) >= 1 then return true end
        local playerState = snapshot.player
        if type(playerState) == "table" and (tonumber(playerState.danger) or 0) > 0 then
            return true
        end
    end
    return false
end

-- Service one companion for a decision beat: run its decision (or sustain a grab),
-- then resolve zombie targeting and the incoming attacks the engine will not write
-- to a non-local body. Assumes the caller has already verified the record is
-- serviceable and the local player is present.
local function serviceRecord(record, current, currentPlayer)
    record.runtime = type(record.runtime) == "table" and record.runtime or {}
    -- A companion pinned by a zombie grab cannot act until it is freed. Skip its
    -- decision (movement/combat) and cancel any in-flight action, but still fall
    -- through to the targeting/attack resolve below so the grab is sustained,
    -- rescued, or dragged down.
    if SC.ZombieAttack and type(SC.ZombieAttack.isGrabbed) == "function"
        and SC.ZombieAttack.isGrabbed(record.actor) == true then
        record.runtime.lastDecision = "grabbed_by_zombies"
        record.runtime.lastDecisionHandled = false
        pcall(SC.Actor.stop, record.actor)
    else
        local decisionStarted = nowMs()
        local guarded, ok, reason = SC.Diagnostics.guard("decision", record.id,
            SC.Decision.update, record.actor, currentPlayer, record.runtime)
        if SC.Performance and type(SC.Performance.record) == "function" then
            SC.Performance.record("decision", record.id, nowMs() - decisionStarted)
        end
        record.runtime.lastDecision = reason
        record.runtime.lastDecisionHandled = guarded and ok == true or false
    end
    if SC.ZombieTargeting and type(SC.ZombieTargeting.scan) == "function" then
        local targetingStarted = nowMs()
        local candidates = observedZombieCandidates(record.runtime)
        local targetingGuarded, scanned, scanReason, scanDetail = SC.Diagnostics.guard(
            "zombie-targeting", record.id, SC.ZombieTargeting.scan,
            record.actor, current, candidates)
        if SC.Performance and type(SC.Performance.record) == "function" then
            SC.Performance.record("zombie-targeting", record.id, nowMs() - targetingStarted)
        end
        if not targetingGuarded then
            record.runtime.lastZombieTargeting = scanned
        elseif scanned == true then
            record.runtime.lastZombieTargeting = scanReason
            record.runtime.zombieTargeting = scanDetail
        end
        -- Apply the wounds those attackers land: the engine resolves the swing
        -- but never writes the bite/scratch to a non-local companion's body.
        if SC.ZombieAttack and type(SC.ZombieAttack.resolve) == "function" then
            local attackStarted = nowMs()
            local attackGuarded, resolved, attackReason, attackDetail = SC.Diagnostics.guard(
                "zombie-attack", record.id, SC.ZombieAttack.resolve,
                record.actor, current, candidates)
            if SC.Performance and type(SC.Performance.record) == "function" then
                SC.Performance.record("zombie-attack", record.id, nowMs() - attackStarted)
            end
            if not attackGuarded then
                record.runtime.lastZombieAttack = resolved
            elseif resolved == true then
                record.runtime.lastZombieAttack = attackReason
                record.runtime.zombieAttack = attackDetail
            end
        end
    end
end

-- One decision callback services several actors instead of one, so reaction time
-- stops scaling with party size (review 2.1/2.2/2.3). It runs two passes within
-- the frame budget the scheduler hands it:
--   1. Critical lane -- every actor in an emergency (grab/threat/downed/rescue) is
--      serviced this callback at a tight interval, capped so a permanently
--      threatened actor can't starve the rest.
--   2. Ordinary round-robin -- multiple actors per callback (not one), each still
--      held to its own per-actor cadence so a single companion never thrashes.
-- The scheduler owns *when* an actor gets CPU; per-actor dueFor only enforces a
-- minimum cadence and is bypassed for the critical lane so an emergency is never
-- gated behind it.
local function decisionTask(current, budgetRemaining)
    local records = SC.Registry.records()
    local total = #records
    if total == 0 then return end
    local currentPlayer = player()
    if currentPlayer == nil or SC.Decision == nil or type(SC.Decision.update) ~= "function" then
        return
    end
    local startedAt = nowMs()
    local softBudget = tonumber(budgetRemaining)
    local function overBudget()
        return softBudget ~= nil and (nowMs() - startedAt) >= softBudget
    end
    local serviced = {}

    -- Critical lane, serviced from a rotating cursor (LF-03). Scanning from a fixed
    -- prefix every callback let a permanently-critical actor early in the id order
    -- consume the per-callback cap (or frame budget) and starve later critical
    -- actors forever. The cursor resumes where the previous callback stopped, so
    -- critical service rotates fairly across the whole set; each critical actor is
    -- reached within one rotation regardless of where the cap or budget cut off.
    local criticalCap = tonumber(SC.Config.get("decisionCriticalPerTick")) or 6
    local criticalInterval = tonumber(SC.Config.get("decisionCriticalIntervalMs")) or 50
    local criticalDone = 0
    local criticalScanned = 0
    while criticalDone < criticalCap and criticalScanned < total and not overBudget() do
        local record
        record, criticalCursor = nextRecord(criticalCursor)
        criticalScanned = criticalScanned + 1
        if recordServiceable(record) and recordIsCritical(record)
            and SC.Scheduler.dueFor(record.id, "decision-critical", criticalInterval, current) then
            serviceRecord(record, current, currentPlayer)
            serviced[record.id] = true
            criticalDone = criticalDone + 1
        end
    end

    local ordinaryCap = tonumber(SC.Config.get("decisionOrdinaryPerTick")) or 3
    local movementInterval = SC.Config.get("movementIntervalMs")
    local ordinaryDone = 0
    local scanned = 0
    while ordinaryDone < ordinaryCap and scanned < total and not overBudget() do
        local record
        record, decisionCursor = nextRecord(decisionCursor)
        scanned = scanned + 1
        if recordServiceable(record) and not serviced[record.id]
            and SC.Scheduler.dueFor(record.id, "decision", movementInterval, current) then
            serviceRecord(record, current, currentPlayer)
            serviced[record.id] = true
            ordinaryDone = ordinaryDone + 1
        end
    end
end
runtime._decisionTaskForTests = decisionTask
runtime._recordIsCriticalForTests = recordIsCritical

-- Decide whether an unhealthy native companion should be removed now or tolerated
-- for a bounded settling window. Native validity dips transiently (notably in the
-- frames after a teleport-recovery re-seats the actor), and removing on the first
-- failed check deleted a follower that would have recovered. Returns "defer" until
-- the failure persists past the grace window, then "remove". Pure aside from the
-- runtime.healthFailingSince bookkeeping so it can be unit-tested directly.
local function healthGateDecision(runtimeState, current, grace)
    grace = tonumber(grace) or 1500
    local firstFailAt = runtimeState.healthFailingSince
    if firstFailAt == nil then
        runtimeState.healthFailingSince = current
        return "defer"
    end
    if current - firstFailAt < grace then
        return "defer"
    end
    runtimeState.healthFailingSince = nil
    return "remove"
end
runtime._healthGateDecisionForTests = healthGateDecision

local function vitalsTask(current)
    local record
    record, vitalsCursor = nextRecord(vitalsCursor)
    if record == nil or record.actor == nil
        or (type(record.runtime) == "table" and record.runtime.inactive == true) then return end
    if not SC.Scheduler.dueFor(record.id, "vitals", 1000, current) then return end
    local deadOk, dead = invoke(record.actor, "isDead")
    if deadOk and dead == true then
        record.runtime = type(record.runtime) == "table" and record.runtime or {}
        record.runtime.dying = true
        if record.runtime.griefNotified ~= true and SC.Community
            and type(SC.Community.noteCompanionDeath) == "function" then
            local callOk, handled, griefReason = pcall(SC.Community.noteCompanionDeath, record)
            if callOk and (handled == true or griefReason == "not_recruited_death"
                or griefReason == "death_already_recorded") then
                record.runtime.griefNotified = true
            elseif not callOk then
                SC.Diagnostics.report("community-grief", record.id,
                    "companion death grief notification failed", handled)
            end
        end
        local retired, retireReason = SC.Actor.retireDead(record.actor)
        if retired and SC.Factions and type(SC.Factions.memberDied) == "function" then
            pcall(SC.Factions.memberDied, retireReason)
        end
        if not retired and retireReason ~= "death_pending" then
            SC.Diagnostics.report("actor-death", record.id,
                "permanent companion death finalization failed", retireReason)
        end
        return
    end
    local healthy, healthReason = SC.Actor.validateNative(record.actor)
    record.runtime = type(record.runtime) == "table" and record.runtime or {}
    local missingSquare = not healthy
        and tostring(healthReason) == "living native companion has no current world square"
    if missingSquare and SC.Vehicle ~= nil and type(SC.Vehicle.isNativeSeated) == "function"
        and SC.Vehicle.isNativeSeated(record.actor) == true then
        -- Vehicle passengers legitimately leave the square moving-object list.
        -- Pulling one back into the world beside a moving car can place them
        -- under the wheels, and also destroys the native seat transaction.
        healthy, healthReason, missingSquare = true, nil, false
        record.runtime.nativeSquareMissingAt = nil
        record.runtime.vehicleRecoveryDeferred = nil
    end
    if missingSquare then
        if record.runtime.nativeSquareMissingAt == nil then
            record.runtime.nativeSquareMissingAt = current
            return
        end
        if current - record.runtime.nativeSquareMissingAt < 1200 then return end
        local state = commandState(record)
        if SC.Factions and type(SC.Factions.isFactionRecord) == "function"
            and SC.Factions.isFactionRecord(record) then
            local handled, factionReason = SC.Factions.handleMissingSquare(record, player())
            if handled then
                record.runtime.nativeSquareMissingAt = nil
                return
            end
            SC.Diagnostics.report("faction", record.id,
                "faction actor missing-square recovery deferred", factionReason)
            return
        elseif state.recruited == true then
            local currentPlayer = player()
            -- Only a following companion catches up to the player. A posted
            -- companion (stay, guard, base duty, or working) must never be yanked
            -- across the map when the player walks out of range and its chunk
            -- unloads: keep its registry record intact and let it reload in place
            -- when the player returns to its area, exactly like the vehicle case.
            if state.order ~= "follow" and state.order ~= "regroup" then
                record.runtime.nativeSquareMissingAt = current
                record.runtime.postedRecoveryDeferred = true
                return
            end
            record.runtime.postedRecoveryDeferred = nil
            local playerVehicleOk, playerVehicle = invoke(currentPlayer, "getVehicle")
            if playerVehicleOk and playerVehicle ~= nil then
                -- A follower that missed boarding may unload while the player
                -- drives away. Keep its registry record intact and recover it
                -- only after the player exits instead of teleporting it into a
                -- moving vehicle's collision path.
                record.runtime.nativeSquareMissingAt = current
                record.runtime.vehicleRecoveryDeferred = true
                return
            end
            local square = recoverySquare(player())
            local recovered = square and SC.Actor.recover(record.actor, square)
            if recovered == true then
                healthy, healthReason = SC.Actor.validateNative(record.actor)
                if healthy then
                    record.runtime.nativeSquareMissingAt = nil
                    record.runtime.vehicleRecoveryDeferred = nil
                    print("[SurvivorCompanion][recovery] recruited companion rejoined the loaded world.")
                end
            end
        elseif SC.Spawn ~= nil and type(SC.Spawn.isDebugProtected) == "function"
            and SC.Spawn.isDebugProtected(record.actor) == true then
            local currentPlayer = player()
            local square, squareReason = SC.Spawn.chooseDebugSquare(currentPlayer)
            if square == nil then
                square = recoverySquare(currentPlayer)
                if square ~= nil then squareReason = "near-player recovery fallback" end
            end
            local recovered, recoverReason = square and SC.Actor.recover(record.actor, square)
            if recovered == true then
                healthy, healthReason = SC.Actor.validateNative(record.actor)
                if healthy then
                    record.runtime.nativeSquareMissingAt = nil
                    SC.Spawn.debugLog("recovered", record.actor, currentPlayer,
                        "unloaded_before_discovery:" .. tostring(squareReason or "debug_square"))
                end
            else
                SC.Diagnostics.report("debug-spawn", record.id,
                    "undiscovered debug companion retained while unloaded",
                    recoverReason or squareReason or "no recovery square")
                return
            end
        else
            local debugDescription = SC.Spawn ~= nil
                and type(SC.Spawn.debugDescription) == "function"
                and SC.Spawn.debugDescription(record.actor, player()) or nil
            local removed, removeReason = SC.Actor.remove(record.actor)
            if not removed then
                SC.Diagnostics.report("actor-provider", record.id,
                    "unloaded encounter cleanup failed", removeReason)
            else
                if debugDescription ~= nil then
                    print("[SurvivorCompanion][debug-spawn] event=removed " .. debugDescription
                        .. " reason=unloaded_after_discovery")
                else
                    print("[SurvivorCompanion][encounter] unloaded neutral companion retired.")
                end
            end
            return
        end
    elseif healthy then
        record.runtime.nativeSquareMissingAt = nil
    end
    if healthy then
        record.runtime.healthFailingSince = nil
    end
    if not healthy then
        -- A genuinely dead actor is already retired by the death path above; here
        -- native validity has merely dipped, which happens transiently (notably in
        -- the handful of frames after a teleport-recovery re-seats the actor on a
        -- fresh square). Removing on the first failed check deleted a follower that
        -- would have settled a moment later (playtest: "teleported to me, then a
        -- health-check despawned her, body never came back"). Tolerate a bounded
        -- window so only a persistently broken actor is torn down.
        -- Snapshot a recruited/faction companion on the first failed check, while
        -- it is still mostly intact, so a later retirement can recover it even if
        -- the native instance degrades further before the grace window elapses.
        local recruitState = commandState(record)
        local recoverable = recruitState.recruited == true
            or (SC.Factions and type(SC.Factions.isFactionRecord) == "function"
                and SC.Factions.isFactionRecord(record) == true)
        if recoverable and record.runtime.healthFailingSince == nil
            and SC.Persistence and type(SC.Persistence.captureRecord) == "function" then
            local okCapture, snapshot = pcall(SC.Persistence.captureRecord, record)
            if okCapture and type(snapshot) == "table" then
                record.runtime.lastStableSnapshot = snapshot
            end
        end
        local grace = (SC.Config and type(SC.Config.get) == "function"
            and tonumber(SC.Config.get("runtimeHealthGraceMs"))) or 1500
        if healthGateDecision(record.runtime, current, grace) ~= "remove" then
            return
        end
        -- Recoverable retirement (LF-01): a still-living recruit must never be
        -- silently deleted. Preserve it into the persistence recovery queue before
        -- native cleanup; if it cannot be preserved (no capture and no prior
        -- snapshot), keep it registered and retry rather than destroying it.
        if recoverable then
            local retained, retainReason = false, nil
            if SC.Persistence and type(SC.Persistence.retainForRecovery) == "function" then
                local okRetain, ok, reason = pcall(SC.Persistence.retainForRecovery, record)
                retained = okRetain and ok == true
                retainReason = okRetain and reason or ok
            end
            if not retained then
                SC.Diagnostics.report("actor-provider", record.id,
                    "recoverable retirement blocked; recruit kept to avoid permanent loss",
                    retainReason)
                record.runtime.healthFailingSince = nil
                return
            end
        end
        SC.Diagnostics.report("actor-provider", record.id,
            "native companion failed its runtime health gate", healthReason)
        local debugDescription = SC.Spawn ~= nil
            and type(SC.Spawn.debugDescription) == "function"
            and SC.Spawn.debugDescription(record.actor, player()) or nil
        local removed, removeReason = SC.Actor.remove(record.actor)
        if not removed then
            SC.Diagnostics.report("actor-provider", record.id,
                "unhealthy native companion cleanup failed", removeReason)
        elseif debugDescription ~= nil then
            print("[SurvivorCompanion][debug-spawn] event=removed " .. debugDescription
                .. " reason=native_health_gate:" .. tostring(healthReason):gsub("[\r\n]", " "))
        end
        return
    end
    local guarded, summary, reason = SC.Diagnostics.guard("vitals", record.id,
        SC.Vitals.summary, record.actor)
    if not guarded then return end
    if summary ~= nil then
        record.runtime.vitals = summary
    else
        SC.Diagnostics.report("vitals", record.id, "native vitals update failed", reason)
    end
end

local function restoreTask()
    SC.Persistence.restorePulse(player())
end

local function saveTask()
    local saved, reason = runtime.save()
    if saved ~= true then
        SC.Diagnostics.report("persistence", nil,
            "scheduled save reported failure", reason)
    end
    return saved, reason
end

local function spawnCompletionTask(current)
    if SC.Spawn == nil or type(SC.Spawn.pollPending) ~= "function" then return end
    local status, detail, source = SC.Spawn.pollPending()
    if status == "spawned" then
        lastDebugSpawnReportAt = current
        lastDebugSpawnReason = nil
        if source == "debug" and SC.Spawn.debugLog("spawned", detail, player(), "deferred") then
            return
        end
        print("[SurvivorCompanion][" .. tostring(source or "deferred-spawn")
            .. "] companion spawned")
    elseif status == "failed" then
        local reason = tostring(detail or "unknown spawn rejection")
        lastDebugSpawnReportAt = current
        lastDebugSpawnReason = reason
        print("[SurvivorCompanion][" .. tostring(source or "deferred-spawn")
            .. "] rejected: " .. reason)
    end
end

local function productionSpawnTask(current)
    SC.Spawn.productionPulse(player(), SC.State, current)
end

local function factionTask(current)
    if SC.Factions and type(SC.Factions.pulse) == "function" then
        SC.Factions.pulse(player(), current)
    end
end

local function uiTask()
    if SC.UI ~= nil and type(SC.UI.scheduledRefresh) == "function" then
        SC.UI.scheduledRefresh()
    end
end

local function baseMaintenanceTask(current)
    if SC.BaseWork ~= nil and type(SC.BaseWork.auditMaintenance) == "function" then
        SC.BaseWork.auditMaintenance(player(), current)
    end
end

local function infectionCrisisTask(current)
    if SC.InfectionCrisis ~= nil and type(SC.InfectionCrisis.pulse) == "function" then
        SC.InfectionCrisis.pulse(player(), current)
    end
end

local function communityTask(current)
    if SC.Autonomy ~= nil and type(SC.Autonomy.pulse) == "function" then
        SC.Autonomy.pulse(player(), current)
    end
end

local function vehicleTask()
    local currentPlayer = player()
    if currentPlayer == nil then return end
    if SC.Vehicle ~= nil and type(SC.Vehicle.restorePulse) == "function" then
        SC.Vehicle.restorePulse()
    end
    local ok, currentVehicle = invoke(currentPlayer, "getVehicle")
    if not ok then return end
    if lastPlayerVehicle ~= nil and currentVehicle == nil then
        -- Retry the just-exited vehicle's stranded passengers on later pulses within
        -- a bounded window, instead of consuming the exit after a single attempt: a
        -- missing exit square or a temporary spawn rejection is recoverable (LF-04).
        local _, remaining = SC.Vehicle.restoreForVehicle(lastPlayerVehicle, currentPlayer)
        if type(remaining) == "number" and remaining > 0 then
            local now = nowMs()
            if vehicleRestoreDeadline == nil then
                vehicleRestoreDeadline = now
                    + (tonumber(SC.Config.get("vehicleRestoreRetryWindowMs")) or 30000)
            end
            if now < vehicleRestoreDeadline then return end
        end
    end
    vehicleRestoreDeadline = nil
    lastPlayerVehicle = currentVehicle
end

local function registerTasks()
    SC.Scheduler.reset(true)
    local definitions = {
        { "decision", 1, 100, decisionTask, "critical" },
        { "vitals", 25, 80, vitalsTask, "critical" },
        { "vehicle", 250, 70, vehicleTask, "critical" },
        { "restore", 1000, 50, restoreTask, "high" },
        { "spawn-completion", 100, 32, spawnCompletionTask, "normal" },
        { "encounter-spawn", SC.Config.get("productionSpawnCheckIntervalMs"), 31,
            productionSpawnTask, "background" },
        { "factions", SC.Config.get("factionPulseIntervalMs"), 30, factionTask, "normal" },
        { "ui-refresh", 500, 20, uiTask, "background" },
        { "base-maintenance", SC.Config.get("baseAuditIntervalMs"), 19,
            baseMaintenanceTask, "background" },
        { "infection-crisis", SC.Config.get("infectionCrisisIntervalMs"), 18,
            infectionCrisisTask, "normal" },
        { "community", SC.Config.get("communityPulseIntervalMs"), 17,
            communityTask, "background" },
        { "persistence", SC.Config.get("persistenceIntervalMs"), 10,
            saveTask, "background", true },
    }
    for _, definition in ipairs(definitions) do
        local called, ok, reason = pcall(SC.Scheduler.register, definition[1],
            definition[2], definition[3], definition[4], {
                lane = definition[5], reportFailure = definition[6] == true,
            })
        if not called or ok ~= true then
            SC.Scheduler.reset(true)
            tasksRegistered = false
            return false, "scheduler task " .. definition[1] .. " failed: "
                .. tostring(called and reason or ok)
        end
    end
    tasksRegistered = true
    return true
end

-- Keep every live native companion in the cell's object list so Build 42's
-- MovingObjectUpdateScheduler simulates it every frame. A manually constructed
-- non-local actor is only placed in the cell's deferred add list by
-- addToWorld/movement, so a stationary companion otherwise falls out of the
-- scheduler and stops being updated (frozen animation, attacks that start but
-- never resolve a hit). This runs on the always-live player tick, so it can
-- re-register a companion even while that companion is not itself being ticked.
local function ensureCompanionsScheduled()
    local registry = SC.Registry
    if type(registry) ~= "table" or type(registry.living) ~= "function" then return end
    local ok, actors = pcall(registry.living)
    if not ok or type(actors) ~= "table" then return end
    local utility = SC.GameplayUtil
    if type(utility) ~= "table" or type(utility.call) ~= "function" then return end
    for _, actor in ipairs(actors) do
        if actor ~= nil then utility.call(actor, "ensureScheduled") end
    end
end

-- ensureScheduled is idempotent and cheap -- it re-adds a companion to the cell's
-- object Set only if it is missing, and membership then persists until a cell
-- transition or removal drops it. Re-verifying every single frame (review 2.6) is
-- almost always a no-op that still pays for a full roster scan. Run it instead as a
-- bounded integrity pulse, forced immediately whenever the roster size changes
-- (add/recover/removal) so a newly placed or re-seated actor is scheduled at once.
local scheduleRepairAt = -math.huge
local scheduleRepairKey = nil
local function scheduleRepairRosterKey()
    if type(SC.Registry) ~= "table" or type(SC.Registry.records) ~= "function" then return 0 end
    local ok, records = pcall(SC.Registry.records)
    if not ok or type(records) ~= "table" then return 0 end
    return #records
end

local function productionTick(current)
    local now = tonumber(current) or nowMs()
    local key = scheduleRepairRosterKey()
    if key ~= scheduleRepairKey
        or (now - scheduleRepairAt) >= SC.Config.get("scheduleRepairIntervalMs") then
        ensureCompanionsScheduled()
        scheduleRepairAt = now
        scheduleRepairKey = key
    end
    SC.Scheduler.tick()
end
runtime._productionTickForTests = productionTick

local function attachTick()
    if tickAttached then return true end
    if Events == nil or Events.OnTick == nil or type(Events.OnTick.Add) ~= "function" then
        return false, "OnTick event is unavailable"
    end
    local ok, reason = pcall(Events.OnTick.Add, productionTick)
    if not ok then return false, tostring(reason) end
    tickAttached = true
    return true
end

local function detachTick()
    if not tickAttached then return true end
    if Events == nil or Events.OnTick == nil or type(Events.OnTick.Remove) ~= "function" then
        return false, "OnTick removal is unavailable"
    end
    local ok, reason = pcall(Events.OnTick.Remove, productionTick)
    if not ok then return false, tostring(reason) end
    tickAttached = false
    return true
end

local function markOpened(container)
    if container == nil or SC.Encounter == nil then return end
    local callback = SC.Encounter.onPlayerContainerOpened
    if type(callback) ~= "function" then callback = SC.Encounter.markPlayerOpened end
    if type(callback) == "function" then
        local ok, reason = pcall(callback, container)
        if not ok then SC.Diagnostics.report("container-hook", nil, "container marker failed", reason) end
    end
    if SC.Factions and type(SC.Factions.observeContainerOpened) == "function" then
        local ok, reason = pcall(SC.Factions.observeContainerOpened, container, player())
        if not ok then SC.Diagnostics.report("factions", nil,
            "faction container observer failed", reason) end
    end
end

local function installContainerHook()
    if originalSelectContainer ~= nil and originalSetNewContainer ~= nil then return true end
    if type(ISInventoryPage) ~= "table" then
        return false, "inventory-page class is unavailable"
    end
    if type(ISInventoryPage.selectContainer) ~= "function"
        or type(ISInventoryPage.setNewContainer) ~= "function" then
        return false, "inventory-page methods are unavailable"
    end
    originalSelectContainer = ISInventoryPage.selectContainer
    originalSetNewContainer = ISInventoryPage.setNewContainer
    -- Forward every argument and every return value verbatim: a Build update or
    -- another mod may add parameters or return multiple values, so a fixed
    -- (self, button)/(self, inventory) single-return wrapper would silently drop
    -- them and corrupt the inventory/hotbar chain. We only read the first
    -- argument to emit our narrow "container opened" signal.
    selectContainerWrapper = function(self, ...)
        local button = ...
        local result = packReturns(originalSelectContainer(self, ...))
        if self ~= nil and self.onCharacter ~= true and button ~= nil
            and self.inventoryPane ~= nil and self.inventoryPane.inventory == button.inventory then
            markOpened(button.inventory)
        end
        return unpackReturns(result, 1, result.n)
    end
    setNewContainerWrapper = function(self, ...)
        local inventory = ...
        local result = packReturns(originalSetNewContainer(self, ...))
        if self ~= nil and self.onCharacter ~= true and inventory ~= nil
            and self.inventoryPane ~= nil and self.inventoryPane.inventory == inventory then
            markOpened(inventory)
        end
        return unpackReturns(result, 1, result.n)
    end
    local ok, reason = pcall(function()
        ISInventoryPage.selectContainer = selectContainerWrapper
        ISInventoryPage.setNewContainer = setNewContainerWrapper
    end)
    if not ok then
        pcall(function()
            ISInventoryPage.selectContainer = originalSelectContainer
            ISInventoryPage.setNewContainer = originalSetNewContainer
        end)
        originalSelectContainer, originalSetNewContainer = nil, nil
        selectContainerWrapper, setNewContainerWrapper = nil, nil
        return false, tostring(reason)
    end
    return true
end

local function preflightContainerHookRemoval()
    if originalSelectContainer == nil and originalSetNewContainer == nil then return true end
    if type(ISInventoryPage) ~= "table" then
        return false, "inventory-page class disappeared while wrappers are owned"
    end
    if originalSelectContainer ~= nil
        and not (ISInventoryPage.selectContainer == selectContainerWrapper) then
        return false, "selectContainer wrapper chain changed"
    end
    if originalSetNewContainer ~= nil
        and not (ISInventoryPage.setNewContainer == setNewContainerWrapper) then
        return false, "setNewContainer wrapper chain changed"
    end
    return true
end

local function removeContainerHook()
    local ready, preflightReason = preflightContainerHookRemoval()
    if not ready then
        SC.Diagnostics.report("container-hook", nil,
            "container hook removal deferred", preflightReason)
        return false, preflightReason
    end
    if originalSelectContainer == nil and originalSetNewContainer == nil then return true end

    local removedSelect, removedSetNew = false, false
    if originalSelectContainer ~= nil then
        local ok, reason = pcall(function()
            ISInventoryPage.selectContainer = originalSelectContainer
        end)
        if not ok then return false, "selectContainer removal failed: " .. tostring(reason) end
        removedSelect = true
    end
    if originalSetNewContainer ~= nil then
        local ok, reason = pcall(function()
            ISInventoryPage.setNewContainer = originalSetNewContainer
        end)
        if not ok then
            if removedSelect then
                pcall(function() ISInventoryPage.selectContainer = selectContainerWrapper end)
            end
            return false, "setNewContainer removal failed: " .. tostring(reason)
        end
        removedSetNew = true
    end

    if removedSelect then
        originalSelectContainer = nil
        selectContainerWrapper = nil
    end
    if removedSetNew then
        originalSetNewContainer = nil
        setNewContainerWrapper = nil
    end
    return true
end

local function preflightInfrastructureTeardown(shouldDetach)
    if tickAttached and shouldDetach ~= true then
        return false, "runtime tick must be detached before destructive reset"
    end
    if tickAttached and (Events == nil or Events.OnTick == nil
        or type(Events.OnTick.Remove) ~= "function") then
        return false, "OnTick removal is unavailable"
    end
    return preflightContainerHookRemoval()
end

local function removeInfrastructure(shouldDetach)
    local ready, reason = preflightInfrastructureTeardown(shouldDetach)
    if not ready then return false, reason end
    local detached = false
    if tickAttached then
        local tickOk, tickReason = detachTick()
        if not tickOk then return false, tickReason end
        detached = true
    end
    local containerOk, containerReason = removeContainerHook()
    if not containerOk then
        local rollbackOk, rollbackReason = true, nil
        if detached then rollbackOk, rollbackReason = attachTick() end
        return false, tostring(containerReason)
            .. (rollbackOk and "" or "; tick rollback failed: "
                .. tostring(rollbackReason))
    end
    return true
end

local function rollbackStartup(reason)
    local removed, removalReason = removeInfrastructure(true)
    if removed then
        local schedulerOk, schedulerReason = pcall(SC.Scheduler.reset, true)
        if schedulerOk then tasksRegistered = false
        else
            removed = false
            removalReason = "scheduler rollback failed: " .. tostring(schedulerReason)
        end
    end
    running = false
    startupCommitted = false
    restoreCommitted = false
    startupFailureReason = tostring(reason or "runtime startup failed")
    SC.State.active = false
    SC.State.disabledReason = startupFailureReason
    return false, startupFailureReason
        .. (removed and "" or "; infrastructure rollback incomplete: "
            .. tostring(removalReason))
end

function runtime.start()
    -- OnGameStart can be delivered more than once for the same loaded world.
    -- Once this runtime owns its scheduler and tick, startup is a read-only
    -- status query: tearing down here would dispose active native actors.
    if running and tickAttached and tasksRegistered then
        return lastStartReady, lastStartReason, true
    end
    if teardownPending then
        local resetOk, resetReason = runtime.reset(true)
        if not resetOk then return false, resetReason, false end
    end
    startupCommitted = false
    restoreCommitted = false
    startupFailureReason = "runtime startup is in progress"

    -- A prior interrupted startup may still own local infrastructure. Clear
    -- only those runtime-owned pieces; never dispose actors or persistence as
    -- part of a startup retry.
    if tickAttached or originalSelectContainer ~= nil
        or originalSetNewContainer ~= nil or tasksRegistered then
        local cleaned, cleanReason = removeInfrastructure(true)
        if not cleaned then
            startupFailureReason = "stale runtime infrastructure could not be removed: "
                .. tostring(cleanReason)
            SC.State.active = false
            SC.State.disabledReason = startupFailureReason
            return false, startupFailureReason, false
        end
        local schedulerOk, schedulerReason = pcall(SC.Scheduler.reset, true)
        if not schedulerOk then
            startupFailureReason = "stale scheduler state could not be reset: "
                .. tostring(schedulerReason)
            SC.State.active = false
            SC.State.disabledReason = startupFailureReason
            return false, startupFailureReason, false
        end
        tasksRegistered = false
    end

    local bridgeCalled, ready, reason = pcall(SC.Actor.checkBridge, true)
    if not bridgeCalled then
        startupFailureReason = "actor bridge check failed: " .. tostring(ready)
        SC.State.active = false
        SC.State.disabledReason = startupFailureReason
        return false, startupFailureReason, false
    end
    -- Do not publish active/started state until persistence import commits.
    SC.State.active = false
    SC.State.disabledReason = nil
    local tasksOk, tasksReason = registerTasks()
    if not tasksOk then
        local _, failure = rollbackStartup(tasksReason)
        return false, failure, false
    end
    local containerOk, containerReason = installContainerHook()
    if not containerOk then
        local _, failure = rollbackStartup(containerReason)
        return false, failure, false
    end
    local tickOk, tickReason = attachTick()
    if not tickOk then
        local _, failure = rollbackStartup(tickReason)
        return false, failure, false
    end
    -- Always import the document, even while the actor provider is unavailable.
    -- Pending records are then re-emitted by save(), so a fail-closed provider
    -- can never erase an existing companion save merely by loading the world.
    local restoreCalled, restored, restoreReason = pcall(SC.Persistence.restore, player())
    if not restoreCalled then
        restoreReason = restored
        restored = false
    end
    if not restored then
        SC.Diagnostics.report("persistence", nil, "restore initialization failed", restoreReason)
        local _, failure = rollbackStartup(restoreReason)
        return false, failure, false
    end
    restoreCommitted = true
    startupCommitted = true
    if not ready then
        SC.Diagnostics.report("actor-provider", nil, "companion actors disabled", reason)
        notifyDisabled(reason)
    end
    running = true
    lastStartReady = ready == true
    lastStartReason = reason
    startupFailureReason = nil
    SC.State.active = ready == true
    SC.State.disabledReason = ready and nil or reason
    return ready, reason, true
end

function runtime.save()
    if not startupCommitted or not restoreCommitted or not running then
        return false, "runtime save is blocked until startup and persistence restore commit: "
            .. tostring(startupFailureReason or "startup is incomplete")
    end
    if SC.Persistence ~= nil and type(SC.Persistence.restoreStatus) == "function" then
        local called, committed, restoreReason = pcall(SC.Persistence.restoreStatus)
        if not called or committed ~= true then
            return false, "runtime save is blocked because persistence restore is not committed: "
                .. tostring(called and restoreReason or committed)
        end
    end
    return SC.Persistence.save(player())
end

function runtime.reset(detach)
    local shouldDetach = detach ~= false
    local hadTick = tickAttached
    local hadContainer = originalSelectContainer ~= nil
        or originalSetNewContainer ~= nil
    local infrastructureOk, infrastructureReason = removeInfrastructure(shouldDetach)
    if not infrastructureOk then
        -- No destructive state mutation occurs unless both runtime-local hook
        -- removals passed their preflight and commit. A later retry can proceed
        -- once the foreign wrapper/event owner releases the chain.
        return false, tostring(infrastructureReason)
    end

    local function restoreInfrastructure()
        local failures = {}
        if hadContainer then
            local ok, reason = installContainerHook()
            if not ok then failures[#failures + 1] = tostring(reason) end
        end
        if hadTick then
            local ok, reason = attachTick()
            if not ok then failures[#failures + 1] = tostring(reason) end
        end
        return #failures == 0, table.concat(failures, "; ")
    end

    -- Cancel deferred restore tickets while retaining their records. The
    -- persistence module clears those records only after native teardown is
    -- verified, so a bridge failure cannot erase the last retry reference.
    if SC.Persistence ~= nil and type(SC.Persistence.prepareReset) == "function" then
        local called, prepared, prepareReason = pcall(SC.Persistence.prepareReset)
        if not called or prepared ~= true then
            local restored, rollbackReason = restoreInfrastructure()
            local detail = "persistence reset preflight failed: "
                .. tostring(called and prepareReason or prepared)
                .. (restored and "" or "; infrastructure rollback failed: "
                    .. tostring(rollbackReason))
            if not restored then
                SC.State.active = false
                SC.State.disabledReason = detail
                startupCommitted = false
                restoreCommitted = false
                startupFailureReason = detail
                running = false
            end
            return false, detail
        end
    end

    -- Native actor teardown is the reset transaction boundary. If Java still
    -- owns an actor, keep every Lua registry/diagnostic reference intact so a
    -- later retry can finish cleanup instead of orphaning the native object.
    if SC.Actor ~= nil and type(SC.Actor.disposeAll) == "function" then
        local ok, disposed, reason = pcall(SC.Actor.disposeAll)
        if not ok or disposed ~= true then
            local detail = tostring(reason or disposed)
            SC.Diagnostics.report("actor-provider", nil,
                "native companion teardown was incomplete", detail)
            SC.State.active = false
            SC.State.disabledReason = "native companion teardown: " .. detail
            startupCommitted = false
            restoreCommitted = false
            startupFailureReason = SC.State.disabledReason
            teardownPending = true
            running = false
            return false, SC.State.disabledReason
        end
    end

    if SC.Persistence ~= nil and type(SC.Persistence.reset) == "function" then
        local called, resetOk, resetReason = pcall(SC.Persistence.reset)
        if not called or resetOk ~= true then
            SC.State.active = false
            SC.State.disabledReason = "persistence reset failed after native teardown: "
                .. tostring(called and resetReason or resetOk)
            startupCommitted = false
            restoreCommitted = false
            startupFailureReason = SC.State.disabledReason
            teardownPending = true
            running = false
            return false, SC.State.disabledReason
        end
    end
    -- Local subsystem teardown is checked and best-effort. A reset that
    -- explicitly returns false is just as fatal as an exception. Continue
    -- through peer subsystems to release independent state, but preserve the
    -- registry, actor ledger and diagnostics until every gameplay subsystem
    -- has accepted cleanup; a later reset can then retry without hiding the
    -- old-world owner which refused to release.
    local resetFailures = {}
    local function resetModule(label, owner, callbackName, ...)
        if owner == nil or type(owner[callbackName]) ~= "function" then return true end
        local called, ok, reason = pcall(owner[callbackName], ...)
        if not called or ok == false then
            resetFailures[#resetFailures + 1] = label .. ": "
                .. tostring(called and (reason or ok) or ok)
            return false
        end
        return true
    end
    resetModule("factions", SC.Factions, "reset")
    resetModule("trade", SC.Trade, "reset")
    resetModule("faction behavior", SC.FactionBehavior, "reset")
    resetModule("faction contracts", SC.FactionContracts, "reset")
    resetModule("decision", SC.Decision, "resetAll")
    resetModule("ui", SC.UI, "reset")
    resetModule("base work", SC.BaseWork, "reset")
    resetModule("base life", SC.BaseLife, "reset")
    resetModule("infection crisis", SC.InfectionCrisis, "reset")
    resetModule("autonomy", SC.Autonomy, "reset")
    resetModule("dialogue", SC.Dialogue, "reset")
    resetModule("community", SC.Community, "reset")
    resetModule("life events", SC.LifeEvents, "reset")

    local schedulerReset = false
    if #resetFailures == 0 then
        schedulerReset = resetModule("scheduler", SC.Scheduler, "reset", true)
        resetModule("vehicle", SC.Vehicle, "reset")
        resetModule("spawn", SC.Spawn, "reset")
        -- Actor and registry ledgers are the final ownership boundary. Do not
        -- erase either after a scheduler/world adapter has rejected cleanup.
        if #resetFailures == 0 then
            resetModule("actor", SC.Actor, "reset")
        end
        if #resetFailures == 0 then
            resetModule("registry", SC.Registry, "reset")
        end
        -- Diagnostics is deliberately last. If any earlier cleanup rejects,
        -- retain the evidence and append the aggregate failure below.
        if #resetFailures == 0 then
            resetModule("diagnostics", SC.Diagnostics, "reset")
        end
    end
    if schedulerReset then tasksRegistered = false end
    if #resetFailures > 0 then
        local detail = "runtime subsystem reset was incomplete: "
            .. table.concat(resetFailures, "; ")
        pcall(SC.Diagnostics.report, "runtime", nil,
            "subsystem teardown was incomplete", detail)
        SC.State.active = false
        SC.State.disabledReason = detail
        running = false
        lastStartReady = false
        lastStartReason = detail
        startupCommitted = false
        restoreCommitted = false
        startupFailureReason = detail
        teardownPending = true
        return false, detail
    end
    SC.State.generation = (SC.State.generation or 0) + 1
    SC.State.active = false
    SC.State.disabledReason = nil
    tasksRegistered = false
    running = false
    lastStartReady = false
    lastStartReason = nil
    startupCommitted = false
    restoreCommitted = false
    startupFailureReason = "runtime has not started"
    teardownPending = false
    decisionCursor = 1
    vitalsCursor = 1
    lastPlayerVehicle = nil
    lastDebugSpawnReportAt = -math.huge
    lastDebugSpawnReason = nil
    return true
end

function runtime.onMainMenuEnter()
    local ok, reason = runtime.reset(true)
    if not ok then
        pcall(SC.Diagnostics.report, "runtime", nil,
            "main-menu teardown failed", reason)
    end
    return ok, reason
end

function runtime.isTickAttached()
    return tickAttached
end

function runtime.tasksRegistered()
    return tasksRegistered
end

function runtime.containerHookState()
    local page = type(ISInventoryPage) == "table" and ISInventoryPage or nil
    return {
        selectInstalled = originalSelectContainer ~= nil
            and page ~= nil and page.selectContainer == selectContainerWrapper,
        selectDeferred = originalSelectContainer ~= nil
            and (page == nil or page.selectContainer ~= selectContainerWrapper),
        setNewInstalled = originalSetNewContainer ~= nil
            and page ~= nil and page.setNewContainer == setNewContainerWrapper,
        setNewDeferred = originalSetNewContainer ~= nil
            and (page == nil or page.setNewContainer ~= setNewContainerWrapper),
    }
end

return runtime
