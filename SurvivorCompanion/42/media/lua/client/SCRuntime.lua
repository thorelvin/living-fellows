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
local decisionCursor = 1
local vitalsCursor = 1
local lastPlayerVehicle = nil
local originalSelectContainer = nil
local originalSetNewContainer = nil
local selectContainerWrapper = nil
local setNewContainerWrapper = nil
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

local function decisionTask(current)
    local record
    record, decisionCursor = nextRecord(decisionCursor)
    if record == nil or record.actor == nil
        or (type(record.runtime) == "table"
            and (record.runtime.inactive == true or record.runtime.dying == true)) then return end
    if not SC.Scheduler.dueFor(record.id, "decision", SC.Config.get("movementIntervalMs"), current) then
        return
    end
    local currentPlayer = player()
    if currentPlayer == nil or SC.Decision == nil or type(SC.Decision.update) ~= "function" then
        return
    end
    record.runtime = type(record.runtime) == "table" and record.runtime or {}
    local decisionStarted = nowMs()
    local guarded, ok, reason = SC.Diagnostics.guard("decision", record.id,
        SC.Decision.update, record.actor, currentPlayer, record.runtime)
    if SC.Performance and type(SC.Performance.record) == "function" then
        SC.Performance.record("decision", record.id, nowMs() - decisionStarted)
    end
    if not guarded then
        record.runtime.lastDecision = reason
        record.runtime.lastDecisionHandled = false
        return
    end
    record.runtime.lastDecision = reason
    record.runtime.lastDecisionHandled = ok == true
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
    end
end

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
    if not healthy then
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
    SC.Persistence.save(player())
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
        SC.Vehicle.restoreForVehicle(lastPlayerVehicle, currentPlayer)
    end
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
            saveTask, "background" },
    }
    for _, definition in ipairs(definitions) do
        local called, ok, reason = pcall(SC.Scheduler.register, definition[1],
            definition[2], definition[3], definition[4], { lane = definition[5] })
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

local function productionTick()
    SC.Scheduler.tick()
end

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
    selectContainerWrapper = function(self, button)
        local result = originalSelectContainer(self, button)
        if self ~= nil and self.onCharacter ~= true and button ~= nil
            and self.inventoryPane ~= nil and self.inventoryPane.inventory == button.inventory then
            markOpened(button.inventory)
        end
        return result
    end
    setNewContainerWrapper = function(self, inventory)
        local result = originalSetNewContainer(self, inventory)
        if self ~= nil and self.onCharacter ~= true and inventory ~= nil
            and self.inventoryPane ~= nil and self.inventoryPane.inventory == inventory then
            markOpened(inventory)
        end
        return result
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

local function removeContainerHook()
    local failures = {}
    if originalSelectContainer ~= nil then
        if type(ISInventoryPage) == "table"
            and ISInventoryPage.selectContainer == selectContainerWrapper then
            ISInventoryPage.selectContainer = originalSelectContainer
            originalSelectContainer = nil
            selectContainerWrapper = nil
        else
            SC.Diagnostics.report("container-hook", nil,
                "selectContainer hook removal deferred",
                "another wrapper currently owns the method chain")
            failures[#failures + 1] = "selectContainer wrapper chain changed"
        end
    end
    if originalSetNewContainer ~= nil then
        if type(ISInventoryPage) == "table"
            and ISInventoryPage.setNewContainer == setNewContainerWrapper then
            ISInventoryPage.setNewContainer = originalSetNewContainer
            originalSetNewContainer = nil
            setNewContainerWrapper = nil
        else
            SC.Diagnostics.report("container-hook", nil,
                "setNewContainer hook removal deferred",
                "another wrapper currently owns the method chain")
            failures[#failures + 1] = "setNewContainer wrapper chain changed"
        end
    end
    return #failures == 0, table.concat(failures, "; ")
end

function runtime.start()
    local resetOk, resetReason = runtime.reset(false)
    if resetOk == false then return false, resetReason, false end
    local bridgeCalled, ready, reason = pcall(SC.Actor.checkBridge, true)
    if not bridgeCalled then
        runtime.reset(true)
        return false, "actor bridge check failed: " .. tostring(ready), false
    end
    SC.State.active = ready == true
    SC.State.disabledReason = ready and nil or reason
    local tasksOk, tasksReason = registerTasks()
    if not tasksOk then
        runtime.reset(true)
        return false, tasksReason, false
    end
    local containerOk, containerReason = installContainerHook()
    if not containerOk then
        runtime.reset(true)
        return false, containerReason, false
    end
    local tickOk, tickReason = attachTick()
    if not tickOk then
        runtime.reset(true)
        return false, tickReason, false
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
        runtime.reset(true)
        return false, restoreReason, false
    end
    if not ready then
        SC.Diagnostics.report("actor-provider", nil, "companion actors disabled", reason)
        notifyDisabled(reason)
    end
    return ready, reason, true
end

function runtime.save()
    return SC.Persistence.save(player())
end

function runtime.reset(detach)
    local failures = {}
    if detach ~= false then
        local ok, reason = detachTick()
        if not ok then failures[#failures + 1] = tostring(reason) end
    end
    local containerOk, containerReason = removeContainerHook()
    if not containerOk then failures[#failures + 1] = tostring(containerReason) end
    if SC.ActionSupervisor ~= nil and type(SC.ActionSupervisor.reset) == "function" then
        pcall(SC.ActionSupervisor.reset, nil, "save_boundary")
    end
    if SC.Factions ~= nil and type(SC.Factions.reset) == "function" then pcall(SC.Factions.reset) end
    if SC.Trade ~= nil and type(SC.Trade.reset) == "function" then pcall(SC.Trade.reset) end
    if SC.FactionBehavior ~= nil and type(SC.FactionBehavior.reset) == "function" then
        pcall(SC.FactionBehavior.reset)
    end
    if SC.FactionContracts ~= nil then
        if type(SC.FactionContracts.reset) == "function" then
            pcall(SC.FactionContracts.reset)
        end
    end
    if SC.Actor ~= nil and type(SC.Actor.disposeAll) == "function" then
        local ok, disposed, reason = pcall(SC.Actor.disposeAll)
        if not ok or disposed ~= true then
            SC.Diagnostics.report("actor-provider", nil,
                "native companion teardown was incomplete", reason or disposed)
            failures[#failures + 1] = "native companion teardown: "
                .. tostring(reason or disposed)
        end
    end
    if SC.Decision ~= nil and type(SC.Decision.resetAll) == "function" then
        pcall(SC.Decision.resetAll)
    end
    if SC.UI ~= nil and type(SC.UI.reset) == "function" then pcall(SC.UI.reset) end
    if SC.BaseWork ~= nil and type(SC.BaseWork.reset) == "function" then pcall(SC.BaseWork.reset) end
    if SC.BaseLife ~= nil and type(SC.BaseLife.reset) == "function" then pcall(SC.BaseLife.reset) end
    if SC.InfectionCrisis ~= nil and type(SC.InfectionCrisis.reset) == "function" then
        pcall(SC.InfectionCrisis.reset)
    end
    if SC.Autonomy ~= nil and type(SC.Autonomy.reset) == "function" then pcall(SC.Autonomy.reset) end
    if SC.Dialogue ~= nil and type(SC.Dialogue.reset) == "function" then pcall(SC.Dialogue.reset) end
    if SC.Community ~= nil and type(SC.Community.reset) == "function" then pcall(SC.Community.reset) end
    if SC.LifeEvents ~= nil and type(SC.LifeEvents.reset) == "function" then pcall(SC.LifeEvents.reset) end
    SC.Scheduler.reset(true)
    SC.Persistence.reset()
    SC.Vehicle.reset()
    SC.Spawn.reset()
    SC.Registry.reset()
    SC.Actor.reset()
    SC.Diagnostics.reset()
    SC.State.generation = (SC.State.generation or 0) + 1
    SC.State.active = false
    SC.State.disabledReason = nil
    tasksRegistered = false
    decisionCursor = 1
    vitalsCursor = 1
    lastPlayerVehicle = nil
    lastDebugSpawnReportAt = -math.huge
    lastDebugSpawnReason = nil
    return #failures == 0, table.concat(failures, "; ")
end

function runtime.onMainMenuEnter()
    runtime.reset(true)
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
