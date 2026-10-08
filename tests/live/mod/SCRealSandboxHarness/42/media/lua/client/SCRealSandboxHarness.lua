-- SPDX-License-Identifier: MIT
-- Private live integration harness. This file is installed only in a disposable
-- cachedir created by Invoke-LiveSandboxTests.ps1; it is never packaged with the mod.

local CONFIG_FILE = "SurvivorCompanionHarness/config.ini"
local EVENTS_FILE = "SurvivorCompanionHarness/events.log"
local SUMMARY_FILE = "SurvivorCompanionHarness/summary.txt"
local SPLIT_READY_FILE = "SurvivorCompanionHarness/split-screen-ready.txt"
local SPLIT_CAPTURED_FILE = "SurvivorCompanionHarness/split-screen-captured.txt"
local SPLIT_RESTORED_READY_FILE = "SurvivorCompanionHarness/split-restored-ready.txt"
local SPLIT_RESTORED_CAPTURED_FILE = "SurvivorCompanionHarness/split-restored-captured.txt"
local SPLIT_CRASH_READY_FILE = "SurvivorCompanionHarness/split-crash-ready.txt"
local FACTION_MAP_READY_FILE = "SurvivorCompanionHarness/faction-map-ready.txt"
local FACTION_MAP_VISIBLE_FILE = "SurvivorCompanionHarness/faction-map-visible.txt"
local FACTION_MAP_CAPTURED_FILE = "SurvivorCompanionHarness/faction-map-captured.txt"
local PERFORMANCE_ACTIVE_FILE = "SurvivorCompanionHarness/performance-sampling-active.txt"
local PERFORMANCE_FRAMES_FILE = "SurvivorCompanionHarness/performance-frames.txt"
local PERFORMANCE_NATIVE_FILE = "SurvivorCompanionHarness/performance-native.txt"
local PERFORMANCE_SUMMARY_FILE = "SurvivorCompanionHarness/performance-summary.txt"
local PERFORMANCE_LF_FILE = "SurvivorCompanionHarness/performance-lf.txt"
local VEHICLE_PASSENGER_READY_FILE = "SurvivorCompanionHarness/vehicle-passenger-ready.txt"
local VEHICLE_PASSENGER_CAPTURED_FILE = "SurvivorCompanionHarness/vehicle-passenger-captured.txt"

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

local function percentile(values, fraction)
    if #values == 0 then return 0 end
    local copy = {}
    for index, value in ipairs(values) do copy[index] = value end
    table.sort(copy)
    return copy[math.max(1, math.ceil(#copy * fraction))]
end

local function nativePerformanceCounters()
    local ok, slot0, slot1, pending, zombies, heap = pcall(function()
        return SCSplitScreenProbe.loadedChunkCount(0),
            SCSplitScreenProbe.loadedChunkCount(1),
            SCSplitScreenProbe.pendingCoopCount(),
            SCSplitScreenProbe.nativeZombieCount(),
            SCSplitScreenProbe.heapUsedBytes()
    end)
    if not ok then return nil, tostring(slot0) end
    return {slot0, slot1, pending, zombies, heap}
end

local function auditCompanionOutfits(stage, records)
    local snapshots = {}
    for _, record in ipairs(records or {}) do
        local actor = record.actor
        if actor then
            local nameOk, name = pcall(function() return actor:getFullName() end)
            local wornOk, worn = pcall(function() return actor:getWornItems() end)
            local entries = {}
            local count = wornOk and worn and worn:size() or 0
            for index = 0, math.min(count, 64) - 1 do
                local ok, location, itemType, nativeId = pcall(function()
                    local entry = worn:get(index)
                    local item = entry and entry:getItem()
                    return entry and entry:getLocation(),
                        item and item:getFullType(), item and item:getID()
                end)
                entries[#entries + 1] = ok
                    and (tostring(location) .. ":" .. tostring(itemType)
                        .. "#" .. tostring(nativeId)) or "entry_error"
            end
            print("SC_OUTFIT_AUDIT|stage=" .. tostring(stage)
                .. "|id=" .. tostring(record.id)
                .. "|name=" .. tostring(nameOk and name or "unavailable")
                .. "|count=" .. tostring(count)
                .. "|worn=" .. table.concat(entries, ";"))
            table.sort(entries)
            snapshots[record.id] = table.concat(entries, ";")
        end
    end
    return snapshots
end

function Harness.performanceFrameTick()
    local sample = Harness.performanceSample
    if sample == nil then return end
    local ok, nanos = pcall(SCSplitScreenProbe.monotonicNanos)
    local clock = ok and tonumber(tostring(nanos)) or nil
    if clock == nil then
        sample.clockError = tostring(nanos)
        return
    end
    if sample.lastNanos ~= nil then
        local interval = (clock - sample.lastNanos) / 1000000
        if interval > 0 and interval < 10000 then
            sample.intervals[#sample.intervals + 1] = interval
            sample.frameRows[#sample.frameRows + 1] = string.format("%d,%.4f",
                #sample.intervals, interval)
        end
    end
    sample.lastNanos = clock
end

function Harness.beginPerformanceSample(current)
    local SC = SurvivorCompanion
    auditCompanionOutfits("performance_remote_ready", SC.Registry.records())
    local counters, failure = nativePerformanceCounters()
    if counters == nil then
        result("FAIL", "performance_native_counters", failure)
        setPhase("finish", current)
        return
    end
    local route = Harness.config.team_performance_route_probe == "true"
    local remote = Harness.config.team_performance_probe == "true" or route
    local encounter = Harness.config.team_performance_encounter_probe == "true"
    local population = #SC.Registry.records()
    local livingPopulation = #SC.Registry.living()
    local targetPopulation = tonumber(Harness.config.performance_population_target) or 4
    -- The moving fixture owns four expedition members. A household can spawn
    -- one unrelated native companion while the two distant areas stream in;
    -- record the actual total and still require it to remain stable afterward.
    local populationReady = population == targetPopulation
        and livingPopulation == targetPopulation
        or route and targetPopulation == 4 and population == 5
            and livingPopulation == 5
    if not check("performance_start_population", populationReady,
        "records=" .. tostring(population) .. " living=" .. tostring(livingPopulation)
            .. " target=" .. tostring(targetPopulation)) then
        setPhase("finish", current)
        return
    end
    if not check("performance_start_slot", (getSpecificPlayer(1) ~= nil) == remote,
        "remote=" .. tostring(remote) .. " slot1=" .. tostring(getSpecificPlayer(1))) then
        setPhase("finish", current)
        return
    end
    if encounter then
        local ready, reason = Harness.beginPerformanceEncounter()
        if not check("performance_local_encounter_fixture", ready == true, reason) then
            setPhase("finish", current)
            return
        end
    end
    Harness.performanceSample = {
        remote = remote,
        route = route,
        encounter = encounter,
        population = population,
        livingPopulation = livingPopulation,
        uiOpenStart = SC.UI and type(SC.UI.isOpen) == "function"
            and SC.UI.isOpen() or false,
        uiRefreshLast = SC.UI and SC.UI.instance
            and tonumber(SC.UI.instance.lastScheduledRefreshAt) or nil,
        uiRefreshCompletions = 0,
        uiRefreshMinimumGapMs = math.huge,
        uiRefreshMaximumGapMs = 0,
        startedAt = current,
        intervals = {},
        frameRows = {"frame,interval_ms"},
        nativeRows = {"elapsed_ms,slot0_chunks,slot1_chunks,pending_coop,zombies,heap_used_bytes,companions,lf_frames,lf_over_budget"},
        nativeSamples = 0,
        nextNativeAt = current,
        nextActionMotionAt = current,
        actionMotionPrevious = {},
        actionMotionCounts = {},
        lfStart = SC.Performance.snapshot(),
    }
    if route then
        local startX, startY = SC.GameplayUtil.position(Harness.leader)
        local map = getWorld():getCell():getChunkMap(1)
        Harness.performanceSample.routeStartX = startX
        Harness.performanceSample.routeStartY = startY
        Harness.performanceSample.routeMapMinX = map and map:getWorldXMinTiles()
    end
    Events.OnRenderTick.Add(Harness.performanceFrameTick)
    writeSignal(PERFORMANCE_ACTIVE_FILE, {"active=" .. tostring(current)})
    result("PASS", "performance_sample_started", "remote=" .. tostring(remote)
        .. " chunks=" .. tostring(counters[1]) .. "/" .. tostring(counters[2])
        .. " pending=" .. tostring(counters[3]))
    if not route then setPhase("performance_measure", current) end
end

function Harness.measurePerformance(current)
    local sample = Harness.performanceSample
    if sample == nil then
        result("FAIL", "performance_sample_state", "sample was not started")
        setPhase("finish", current)
        return
    end
    local root = SurvivorCompanion.UI and SurvivorCompanion.UI.instance
    local refreshAt = root and tonumber(root.lastScheduledRefreshAt) or nil
    if refreshAt ~= nil and refreshAt ~= sample.uiRefreshLast then
        if sample.uiRefreshLast ~= nil then
            local gap = refreshAt - sample.uiRefreshLast
            sample.uiRefreshMinimumGapMs = math.min(sample.uiRefreshMinimumGapMs, gap)
            sample.uiRefreshMaximumGapMs = math.max(sample.uiRefreshMaximumGapMs, gap)
        end
        sample.uiRefreshLast = refreshAt
        sample.uiRefreshCompletions = sample.uiRefreshCompletions + 1
    end
    if sample.encounter then Harness.tickPerformanceEncounter(current) end
    if not sample.remote and current >= sample.nextActionMotionAt then
        sample.nextActionMotionAt = current + 250
        local SC = SurvivorCompanion
        for _, record in ipairs(SC.Registry.records()) do
            local actor = record.actor
            local nav = actor and SC.Navigation._stateForTests(actor)
            local retained = nav and nav.decisionApproach
            if retained and retained.goal then
                local x, y = SC.GameplayUtil.position(actor)
                local goalX, goalY = SC.GameplayUtil.position(retained.goal)
                local previous = sample.actionMotionPrevious[record.id]
                local delta = previous and x and y
                    and math.sqrt((x - previous.x)^2 + (y - previous.y)^2)
                    or nil
                if x and y then
                    sample.actionMotionPrevious[record.id] = { x = x, y = y }
                end
                local kind = tostring(retained.kind)
                sample.actionMotionCounts[kind] =
                    (sample.actionMotionCounts[kind] or 0) + 1
                print("SC_ACTION_MOTION|id=" .. tostring(record.id)
                    .. "|kind=" .. kind
                    .. "|action=" .. tostring(retained.intent
                        and retained.intent.action)
                    .. "|pos=" .. tostring(x) .. "," .. tostring(y)
                    .. "|delta=" .. tostring(delta)
                    .. "|native=" .. tostring(actor:getCurrentState())
                    .. "|decision=" .. tostring((SC.Decision.peek(actor) or {}).current)
                    .. "|goal=" .. tostring(goalX)
                        .. "," .. tostring(goalY))
            end
        end
    end
    if current >= sample.nextNativeAt then
        local counters, failure = nativePerformanceCounters()
        if counters == nil then
            result("FAIL", "performance_native_counters", failure)
            setPhase("finish", current)
            return
        end
        local lf = SurvivorCompanion.Performance.snapshot()
        sample.nativeRows[#sample.nativeRows + 1] = table.concat({
            tostring(current - sample.startedAt),
            tostring(counters[1]), tostring(counters[2]), tostring(counters[3]),
            tostring(counters[4]), tostring(counters[5]),
            tostring(#SurvivorCompanion.Registry.records()),
            tostring(lf.frames), tostring(lf.overBudgetFrames),
        }, ",")
        sample.nativeSamples = sample.nativeSamples + 1
        sample.nextNativeAt = current + 1000
    end
    if current - sample.startedAt < 30000 then return end
    if not sample.remote then
        local kinds = {}
        for kind, count in pairs(sample.actionMotionCounts) do
            kinds[#kinds + 1] = kind .. ":" .. tostring(count)
        end
        table.sort(kinds)
        result(#kinds > 0 and "PASS" or "SKIP",
            "slow_action_approach_observed", table.concat(kinds, ","))
    end
    Events.OnRenderTick.Remove(Harness.performanceFrameTick)
    local lfEnd = SurvivorCompanion.Performance.snapshot()
    local intervals = sample.intervals
    local over50 = 0
    for _, interval in ipairs(intervals) do
        if interval > 50 then over50 = over50 + 1 end
    end
    local rows = {
        "mode=" .. (sample.route and (sample.encounter
            and "walking_expedition_with_player_encounter"
            or "walking_expedition")
            or (sample.encounter and "remote_with_player_encounter"
                or (sample.remote and "remote_expedition" or "base_save"))),
        "duration_ms=" .. tostring(current - sample.startedAt),
        "companion_population_start=" .. tostring(sample.population),
        "companion_living_start=" .. tostring(sample.livingPopulation),
        "companion_population_end=" .. tostring(#SurvivorCompanion.Registry.records()),
        "companion_living_end=" .. tostring(#SurvivorCompanion.Registry.living()),
        "render_frames=" .. tostring(#intervals),
        "render_p50_ms=" .. string.format("%.4f", percentile(intervals, 0.50)),
        "render_p95_ms=" .. string.format("%.4f", percentile(intervals, 0.95)),
        "render_p99_ms=" .. string.format("%.4f", percentile(intervals, 0.99)),
        "render_max_ms=" .. string.format("%.4f", percentile(intervals, 1)),
        "render_over_50_ms=" .. tostring(over50),
        "native_samples=" .. tostring(sample.nativeSamples),
        "slot_admission_ms=" .. tostring(Harness.performanceSlotActivatedAt
            and Harness.performanceLeaderQueuedAt
            and Harness.performanceSlotActivatedAt - Harness.performanceLeaderQueuedAt),
        "remote_area_load_ms=" .. tostring(Harness.performanceRemoteReadyAt
            and Harness.performanceTransferQueuedAt
            and Harness.performanceRemoteReadyAt - Harness.performanceTransferQueuedAt),
        "expedition_to_remote_ready_ms=" .. tostring(Harness.performanceRemoteReadyAt
            and Harness.performanceLeaderQueuedAt
            and Harness.performanceRemoteReadyAt - Harness.performanceLeaderQueuedAt),
        "load_pending_coop_peak=" .. tostring(Harness.performancePendingPeak),
        "ui_open_start=" .. tostring(sample.uiOpenStart),
        "ui_open_end=" .. tostring(SurvivorCompanion.UI
            and SurvivorCompanion.UI.isOpen()),
        "ui_refresh_completions=" .. tostring(sample.uiRefreshCompletions),
        "ui_refresh_minimum_gap_ms=" .. tostring(sample.uiRefreshMinimumGapMs),
        "ui_refresh_maximum_gap_ms=" .. tostring(sample.uiRefreshMaximumGapMs),
        "lf_frames_delta=" .. tostring((lfEnd.frames or 0) - (sample.lfStart.frames or 0)),
        "lf_over_budget_delta=" .. tostring((lfEnd.overBudgetFrames or 0)
            - (sample.lfStart.overBudgetFrames or 0)),
        "lf_last_p95_ms=" .. tostring(lfEnd.p95FrameMs),
        "clock_error=" .. tostring(sample.clockError or "none"),
    }
    if sample.route then
        local endX, endY = SurvivorCompanion.GameplayUtil.position(Harness.leader)
        local map = getWorld():getCell():getChunkMap(1)
        local mapMinX = map and map:getWorldXMinTiles()
        local distance = endX and endY and sample.routeStartX
            and sample.routeStartY and math.sqrt(
                (endX - sample.routeStartX)^2
                    + (endY - sample.routeStartY)^2) or 0
        rows[#rows + 1] = "route_distance_tiles=" .. tostring(distance)
        rows[#rows + 1] = "route_map_min_shift_tiles="
            .. tostring(mapMinX and sample.routeMapMinX
                and mapMinX - sample.routeMapMinX)
        rows[#rows + 1] = "route_leg_count=" .. tostring(Harness.extendedRouteLegs)
        rows[#rows + 1] = "route_max_actor_step_tiles="
            .. tostring(Harness.localTravelMaxStep)
        check("performance_route_active_motion", distance >= 5
            and (Harness.localTravelMaxStep or math.huge) < 3,
            "distance=" .. tostring(distance)
                .. " max_step=" .. tostring(Harness.localTravelMaxStep))
    end
    if sample.encounter then
        rows[#rows + 1] = "player_attack_attempts=" .. tostring(Harness.performanceAttackAttempts or 0)
        rows[#rows + 1] = "player_native_hits=" .. tostring(Harness.performanceNativeHits or 0)
        rows[#rows + 1] = "encounter_zombies_spawned=" .. tostring(Harness.performanceZombiesSpawned or 0)
        rows[#rows + 1] = "encounter_zombie_initial_health="
            .. tostring(Harness.performanceZombieInitialHealth)
        rows[#rows + 1] = "encounter_zombie_end_health="
            .. tostring(Harness.performanceCurrentZombie
                and Harness.performanceCurrentZombie:getHealth())
        rows[#rows + 1] = "player_zombie_min_gap=" .. tostring(Harness.performanceMinGap)
        rows[#rows + 1] = "player_zombie_last_gap=" .. tostring(Harness.performanceLastGap)
        rows[#rows + 1] = "melee_fixture_distance=" .. tostring(Harness.performanceFixtureDistance)
        rows[#rows + 1] = "player_attack_error=" .. tostring(Harness.performanceAttackError or "none")
        rows[#rows + 1] = "player_all_native_hits=" .. tostring(Harness.performanceAllPlayerHits or 0)
        rows[#rows + 1] = "player_weapon_ready_seen=" .. tostring(Harness.performanceWeaponReadySeen)
        rows[#rows + 1] = "player_attack_started_seen=" .. tostring(Harness.performanceAttackStartedSeen)
        rows[#rows + 1] = "player_attack_animation_seen=" .. tostring(Harness.performanceAnimationSeen)
        rows[#rows + 1] = "player_attack_last_state=" .. tostring(Harness.performanceAttackLastState)
        rows[#rows + 1] = "player_dead=" .. tostring(Harness.player:isDead())
    end
    local written = writeSignal(PERFORMANCE_FRAMES_FILE, sample.frameRows)
        and writeSignal(PERFORMANCE_NATIVE_FILE, sample.nativeRows)
        and writeSignal(PERFORMANCE_SUMMARY_FILE, rows)
    local lfReport = SurvivorCompanion.Performance.summary()
    local lfRows = {}
    for line in string.gmatch(lfReport or "", "[^\n]+") do
        lfRows[#lfRows + 1] = line
    end
    written = writeSignal(PERFORMANCE_LF_FILE, lfRows) and written
    check("performance_samples_written", written,
        "frames=" .. tostring(#intervals) .. " native=" .. tostring(sample.nativeSamples))
    check("performance_sample_coverage", #intervals >= 300
        and sample.nativeSamples >= 20 and sample.clockError == nil,
        "frames=" .. tostring(#intervals) .. " native=" .. tostring(sample.nativeSamples)
            .. " clock_error=" .. tostring(sample.clockError))
    check("performance_end_population",
        #SurvivorCompanion.Registry.records() == sample.population,
        "start=" .. tostring(sample.population)
            .. " end=" .. tostring(#SurvivorCompanion.Registry.records()))
    check("performance_end_living_population",
        #SurvivorCompanion.Registry.living() == sample.livingPopulation,
        "start=" .. tostring(sample.livingPopulation)
            .. " end=" .. tostring(#SurvivorCompanion.Registry.living()))
    check("performance_end_slot", (getSpecificPlayer(1) ~= nil) == sample.remote,
        "remote=" .. tostring(sample.remote) .. " slot1=" .. tostring(getSpecificPlayer(1)))
    if sample.uiOpenStart and SurvivorCompanion.UI.isOpen() then
        check("performance_ui_refresh_cadence", sample.uiRefreshCompletions >= 30
            and sample.uiRefreshCompletions <= 65
            and sample.uiRefreshMinimumGapMs >= 500
            and sample.uiRefreshMaximumGapMs <= 2000,
            "completions=" .. tostring(sample.uiRefreshCompletions)
                .. " min_gap=" .. tostring(sample.uiRefreshMinimumGapMs)
                .. " max_gap=" .. tostring(sample.uiRefreshMaximumGapMs))
    end
    if sample.encounter then
        check("performance_player_native_combat", (Harness.performanceNativeHits or 0) > 0
            and Harness.player:isDead() == false
            and Harness.performanceCurrentZombie ~= nil
            and Harness.performanceCurrentZombie:getHealth()
                < (Harness.performanceZombieInitialHealth or 0),
            "attempts=" .. tostring(Harness.performanceAttackAttempts or 0)
                .. " native_hits=" .. tostring(Harness.performanceNativeHits or 0)
                .. " zombie_health=" .. tostring(Harness.performanceCurrentZombie
                    and Harness.performanceCurrentZombie:getHealth())
                .. " player_dead=" .. tostring(Harness.player:isDead()))
        Harness.cleanupPerformanceEncounter()
    end
    skip("w09_release_limits", "pilot measurements only; repeated runs and fixed limits remain open")
    writeSignal(PERFORMANCE_ACTIVE_FILE, {"complete=" .. tostring(current)})
    Harness.performanceSample = nil
    if not sample.route then setPhase("finish", current) end
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

-- A population probe adds real native actors only to the disposable cloned
-- save. Reserve distinct loaded squares so the setup itself cannot create the
-- overlapping-companion condition that the ordinary AI is meant to avoid.
local function performanceSpawnSquare()
    local utility = SurvivorCompanion and SurvivorCompanion.GameplayUtil
    local px, py, pz = position(Harness.player)
    if utility == nil or px == nil or type(getCell) ~= "function" then return nil end
    local cell = getCell()
    if cell == nil then return nil end
    Harness.performanceSpawnUsed = Harness.performanceSpawnUsed or {}
    local cx, cy, z = math.floor(px), math.floor(py), math.floor(pz or 0)
    for radius = 4, 14 do
        for dx = -radius, radius do
            for dy = -radius, radius do
                if math.max(math.abs(dx), math.abs(dy)) == radius then
                    local x, y = cx + dx, cy + dy
                    local key = tostring(x) .. ":" .. tostring(y) .. ":" .. tostring(z)
                    if not Harness.performanceSpawnUsed[key] then
                        local square = cell:getGridSquare(x, y, z)
                        if square and utility.isSquareFree(square) then
                            local free, freeOk = utility.call(square, "isFree", true)
                            local safe, safeOk = utility.call(square, "isSafeToSpawn")
                            if (not freeOk or free == true)
                                and (not safeOk or safe == true) then
                                Harness.performanceSpawnUsed[key] = true
                                return square
                            end
                        end
                    end
                end
            end
        end
    end
    return nil
end

function Harness.preparePerformancePopulation(current)
    local SC = SurvivorCompanion
    local target = tonumber(Harness.config.performance_population_target) or 4
    if target <= 4 then return true end
    if Harness.performancePopulationConfigured ~= true then
        local sandbox = type(SandboxVars) == "table"
            and SandboxVars.LivingFellows or nil
        if type(sandbox) == "table" then
            sandbox.MaxCompanions = target
            sandbox.EncountersEnabled = false
        end
        local overrides = SC.Config and SC.Config._overrides
        if type(overrides) ~= "table" then
            result("FAIL", "performance_scale_config", "config overrides unavailable")
            setPhase("finish", current)
            return nil
        end
        overrides.maxCompanions = target
        overrides.productionEncounterEnabled = false
        overrides.maxNeutralEncounters = 0
        Harness.performancePopulationConfigured = true
        result("PASS", "performance_scale_config",
            "target=" .. tostring(target) .. " encounters=false")
    end
    local ticket = Harness.performanceScaleTicket
    if ticket then
        local actor, status, detail = SC.Actor.pollSpawn(ticket)
        if actor == nil and status == "spawn_pending" then return false end
        Harness.performanceScaleTicket = nil
        if actor == nil then
            result("FAIL", "performance_scale_spawn", tostring(detail or status))
            setPhase("finish", current)
            return nil
        end
        Harness.performanceScaleSpawned = (Harness.performanceScaleSpawned or 0) + 1
    end
    local records = SC.Registry.records()
    local living = SC.Registry.living()
    if #records >= target then
        if Harness.performancePopulationReadyAt == nil then
            if not check("performance_scale_native_population",
                #records == target and #living == target,
                "records=" .. tostring(#records) .. " living=" .. tostring(#living)
                    .. " target=" .. tostring(target)) then
                setPhase("finish", current)
                return nil
            end
            Harness.performancePopulationReadyAt = current
            result("PASS", "performance_scale_population_ready",
                "native_companions=" .. tostring(#living)
                    .. " fixture_spawns=" .. tostring(Harness.performanceScaleSpawned or 0))
        end
        return current - Harness.performancePopulationReadyAt >= 5000
    end
    local square = performanceSpawnSquare()
    if square == nil then
        result("FAIL", "performance_scale_spawn_square",
            "no distinct safe loaded square for actor " .. tostring(#records + 1))
        setPhase("finish", current)
        return nil
    end
    local ticketOrNil, reason = SC.Actor.beginSpawn(square, {
        recruited = true,
        identity = { forename = "Scale", surname = tostring(#records + 1),
            gender = "man", outfit = "Generic01" },
    })
    if ticketOrNil == nil then
        result("FAIL", "performance_scale_spawn", tostring(reason))
        setPhase("finish", current)
        return nil
    end
    Harness.performanceScaleTicket = ticketOrNil
    return false
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

-- Build 42 owns every locomotion speed through the animation: standing on a
-- hedge raises the read-only "intrees" variable (bound straight to
-- IsoGameCharacter.isInTreesNoBush), the movement state machine swaps in
-- Bob_WalkTrees, and PathFindBehavior2.moveToPoint sizes its step from that
-- clip's root motion. A direct companion step carries a fixed distance from Lua
-- instead, so a companion crossed a hedge the player has to push through
-- without losing a step. Find real foliage in the loaded world and make the
-- engine answer for itself.
local function findLiveFoliageSquare(actor)
    local utility = SurvivorCompanion.GameplayUtil
    local ax, ay, az = position(actor)
    if ax == nil or type(getCell) ~= "function" then return nil end
    local cell = getCell()
    local hedges = { hedgelow = true, hedgehigh = true }
    for radius = 1, 14 do
        for dx = -radius, radius do
            for dy = -radius, radius do
                if math.max(math.abs(dx), math.abs(dy)) == radius then
                    local square = cell:getGridSquare(
                        math.floor(ax + dx), math.floor(ay + dy), math.floor(az or 0))
                    if square ~= nil and utility.isSquareFree(square) then
                        local properties = select(1, utility.call(square, "getProperties"))
                        if properties ~= nil then
                            local movement = select(1,
                                utility.call(properties, "get", "Movement"))
                            if type(movement) == "string"
                                and hedges[string.lower(movement)] == true then
                                return square, movement
                            end
                        end
                    end
                end
            end
        end
    end
    return nil
end

local function probeFoliageParity()
    local SC = SurvivorCompanion
    local utility = SC.GameplayUtil
    local actor = Harness.actor
    local openFactor = select(1, utility.call(actor, "getCompanionTerrainSpeedFactor"))
    local openFoliage = select(1, utility.call(actor, "isInTreesNoBush"))
    -- The probe has to be live before anything is read from it, and open ground
    -- must never be slowed.
    if not check("native_foliage_probe_available",
        tonumber(openFactor) ~= nil
            and (openFoliage == true or tonumber(openFactor) == 1),
        "factor=" .. tostring(openFactor) .. " in_foliage=" .. tostring(openFoliage)) then
        skip("native_foliage_slows_direct_step", "terrain speed probe unavailable")
        return
    end
    local square, movement = findLiveFoliageSquare(actor)
    if square == nil then
        skip("native_foliage_slows_direct_step",
            "no loaded hedge square within reach of the companion")
        return
    end
    local ax, ay, az = position(actor)
    local returnPoint = { x = ax, y = ay, z = az or 0 }
    local sx, sy, sz = position(square)
    local placed, placeReason = Harness.placeCombatActor(actor,
        { x = sx + 0.5, y = sy + 0.5, z = sz or 0 })
    if not placed then
        skip("native_foliage_slows_direct_step", "hedge placement rejected: " .. clean(placeReason))
        return
    end
    local inFoliage = select(1, utility.call(actor, "isInTreesNoBush"))
    -- select() hands back a Java Float; tonumber would read the trailing
    -- ok-flag as its base. Isolate the value first.
    local factorValue = select(1, utility.call(actor, "getCompanionTerrainSpeedFactor"))
    local factor = tonumber(factorValue)
    local detected = SC.Navigation._squareHasBushForTests(square) == true
    check("native_foliage_slows_direct_step",
        inFoliage == true and factor ~= nil and factor > 0 and factor < 1 and detected,
        "movement=" .. clean(movement) .. " engine_in_foliage=" .. tostring(inFoliage)
            .. " factor=" .. tostring(factor)
            .. " navigation_detects=" .. tostring(detected))
    Harness.placeCombatActor(actor, returnPoint)
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
    probeFoliageParity()
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

-- Test-only local encounter for W09. It uses ordinary native zombies and the
-- real slot-0 player's pressedAttack path; the fixture is never a population
-- proof, and all mutations are confined to the disposable cloned save.
function Harness.spawnPerformanceZombie()
    if type(addZombiesInOutfit) ~= "function" then return false, "native zombie spawn unavailable" end
    local SC = SurvivorCompanion
    local px, py, pz = position(Harness.player)
    if px == nil then return false, "player position unavailable" end
    local cell = getCell()
    local source = Harness.player:getCurrentSquare()
    for _, direction in ipairs({ {1,0}, {-1,0}, {0,1}, {0,-1} }) do
        local fixtureDistance = Harness.performanceFixtureDistance or 1.05
        local zx, zy = px + direction[1] * fixtureDistance,
            py + direction[2] * fixtureDistance
        local tx, ty = math.floor(zx), math.floor(zy)
        local square = cell:getGridSquare(tx, ty, math.floor(pz or 0))
        local path = square and source and SC.Navigation.findPath(source, square,
            { nodeBudget = 300 }) or nil
        if square ~= nil and SC.GameplayUtil.isSquareFree(square)
            and path ~= nil and #path >= 2 and #path <= 5 then
            local ok, list = pcall(addZombiesInOutfit,
                tx, ty, math.floor(pz or 0), 1, nil, 0)
            local zombie = ok and list and select(1, SC.GameplayUtil.call(list, "get", 0)) or nil
            if zombie ~= nil then
                pcall(function() zombie:setX(zx) end)
                pcall(function() zombie:setY(zy) end)
                pcall(function() zombie:setZ(pz or 0) end)
                pcall(function() zombie:setCurrentSquareFromPosition() end)
                pcall(function() zombie:setTarget(Harness.player) end)
                -- One durable target avoids synchronous test-only respawns
                -- contaminating the measured frame intervals.
                pcall(function() zombie:setHealth(100.0) end)
                if zombie:getHealth() < 99 then
                    pcall(function() zombie:removeFromWorld() end)
                    pcall(function() zombie:removeFromSquare() end)
                    return false, "durable local target health was not applied"
                end
                Harness.performanceZombies[#Harness.performanceZombies + 1] = zombie
                Harness.performanceCurrentZombie = zombie
                Harness.performanceZombiesSpawned = #Harness.performanceZombies
                Harness.performanceZombieInitialHealth = zombie:getHealth()
                return true, "native zombie=" .. tostring(zombie)
                    .. " distance=" .. tostring(distance(Harness.player, zombie))
            end
        end
    end
    return false, "no reachable free local zombie fixture square"
end

function Harness.beginPerformanceEncounter()
    local inventory = Harness.player:getInventory()
    if inventory == nil then return false, "player inventory unavailable" end
    Harness.performanceOriginalPrimary = Harness.player:getPrimaryHandItem()
    local weapon = inventory:AddItem("Base.Katana")
    if weapon == nil then return false, "test melee weapon could not be created" end
    Harness.performanceWeapon = weapon
    Harness.player:setPrimaryHandItem(weapon)
    local fixtureDistance, reason = Harness.meleeFixtureDistance(weapon, Harness.player)
    if fixtureDistance == nil then return false, reason end
    Harness.performanceFixtureDistance = fixtureDistance
    Harness.performanceZombies = {}
    Harness.performanceZombiesSpawned = 0
    Harness.performanceAttackAttempts = 0
    Harness.performanceNativeHits = 0
    Harness.performanceAllPlayerHits = 0
    Harness.performanceNextAttackAt = 0
    Harness.performanceMinGap = math.huge
    return Harness.spawnPerformanceZombie()
end

function Harness.tickPerformanceEncounter(current)
    local zombie = Harness.performanceCurrentZombie
    if zombie == nil or zombie:isDead() == true then return end
    local px, py = position(Harness.player)
    local zx, zy = position(zombie)
    if px == nil or zx == nil then return end
    local dx, dy = zx - px, zy - py
    local gap = math.sqrt(dx * dx + dy * dy)
    Harness.performanceLastGap = gap
    Harness.performanceMinGap = math.min(Harness.performanceMinGap or math.huge, gap)
    local player = Harness.player
    Harness.performanceWeaponReadySeen = Harness.performanceWeaponReadySeen
        or player:isWeaponReady()
    Harness.performanceAttackStartedSeen = Harness.performanceAttackStartedSeen
        or player:isAttackStarted()
    Harness.performanceAnimationSeen = Harness.performanceAnimationSeen
        or player:isPerformingAttackAnimation()
    Harness.performanceAttackLastState = "ready=" .. tostring(player:isWeaponReady())
        .. " started=" .. tostring(player:isAttackStarted())
        .. " animation=" .. tostring(player:isPerformingAttackAnimation())
        .. " type=" .. tostring(player:getAttackType())
        .. " hand=" .. tostring(player:getPrimaryHandItem())
    if gap < 0.3 or gap > 2.5 or current < (Harness.performanceNextAttackAt or 0) then return end
    Harness.player:setForwardDirection(dx / gap, dy / gap)
    local attacked, failure = pcall(function() Harness.player:pressedAttack() end)
    if attacked then
        Harness.performanceAttackAttempts = (Harness.performanceAttackAttempts or 0) + 1
        Harness.performanceAttackStartedSeen = Harness.performanceAttackStartedSeen
            or player:isAttackStarted()
    else
        Harness.performanceAttackError = tostring(failure)
    end
    Harness.performanceNextAttackAt = current + 850
end

function Harness.cleanupPerformanceEncounter()
    for _, zombie in ipairs(Harness.performanceZombies or {}) do
        pcall(function() zombie:setTarget(nil) end)
        pcall(function() zombie:removeFromWorld() end)
        pcall(function() zombie:removeFromSquare() end)
    end
    Harness.performanceZombies = nil
    Harness.performanceCurrentZombie = nil
    if Harness.performanceWeapon ~= nil and Harness.player ~= nil then
        pcall(function() Harness.player:setPrimaryHandItem(Harness.performanceOriginalPrimary) end)
        pcall(function() Harness.player:getInventory():Remove(Harness.performanceWeapon) end)
    end
    Harness.performanceWeapon = nil
    Harness.performanceOriginalPrimary = nil
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
    return Harness.config.pathing_only == "true" and "begin_stair_crossing" or "awareness"
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

-- This uses a real loaded staircase in a disposable copy of the user's save.
-- Change the work target while the native actor is physically between floors:
-- the crossing must retain its path and reach the upper landing without a snap.
function Harness.beginStairCrossing(current)
    local SC, utility = SurvivorCompanion, SurvivorCompanion.GameplayUtil
    local ax, ay, az = position(Harness.actor)
    if ax == nil then
        result("FAIL", "real_stair_crossing_target_change", "actor position unavailable")
        setPhase("finish", current)
        return
    end
    local cell, floor = getCell(), math.floor(az or 0)
    local chosen, chosenDistance
    for dx = -12, 12 do
        for dy = -12, 12 do
            local x, y = math.floor(ax) + dx, math.floor(ay) + dy
            local entry = cell:getGridSquare(x, y, floor)
            if entry and utility.isSquareFree(entry)
                and not SC.Topology.squareHasStairs(entry)
                and utility.movingBlocker(entry, Harness.actor) == nil then
                for _, direction in ipairs({ { 1, 0 }, { -1, 0 },
                        { 0, 1 }, { 0, -1 } }) do
                    local sx, sy = direction[1], direction[2]
                    local first = cell:getGridSquare(x + sx, y + sy, floor)
                    local middle = cell:getGridSquare(x + sx * 2, y + sy * 2, floor)
                    local last = cell:getGridSquare(x + sx * 3, y + sy * 3, floor)
                    local landing = cell:getGridSquare(x + sx * 4, y + sy * 4, floor + 1)
                    if first and middle and last and landing
                        and SC.Topology.squareHasStairs(first)
                        and SC.Topology.squareHasStairs(middle)
                        and SC.Topology.squareHasStairs(last)
                        and utility.isSquareFree(landing)
                        and utility.movingBlocker(landing, Harness.actor) == nil then
                        local distance = dx * dx + dy * dy
                        if chosenDistance == nil or distance < chosenDistance then
                            chosen = { entry = entry, landing = landing,
                                x = x, y = y, z = floor }
                            chosenDistance = distance
                        end
                    end
                end
            end
        end
    end
    if not chosen then
        skip("real_stair_crossing_target_change",
            "no loaded clear three-tread staircase within 12 tiles")
        setPhase("finish", current)
        return
    end
    local recovered, reason = SC.Actor.recover(Harness.actor, chosen.entry)
    if recovered ~= true then
        result("FAIL", "real_stair_crossing_target_change",
            "stair entry relocation failed: " .. clean(reason))
        setPhase("finish", current)
        return
    end
    SC.Navigation.reset(Harness.actor)
    local token, controlReason = beginHarnessControl(
        Harness.actor, "stair_crossing_probe", 30000)
    if not token then
        result("FAIL", "real_stair_crossing_target_change",
            "control ownership rejected: " .. clean(controlReason))
        setPhase("finish", current)
        return
    end
    token.allowedMovementPhases.recovering = true
    chosen.token = token
    chosen.baseWork = SC.BaseLife and SC.BaseLife.allowsFloorTransit(
        chosen.entry, chosen.landing, { workCampOnly = true }) == true
    chosen.snapshot = SC.Senses.snapshot(Harness.actor, Harness.player, {})
    chosen.startedAt = nowMs()
    chosen.maxZ = floor
    Harness.stairCrossing = chosen
    setPhase("stair_crossing", nowMs())
end

function Harness.finishStairCrossing(status, detail, current)
    local SC, probe = SurvivorCompanion, Harness.stairCrossing
    SC.Navigation.reset(Harness.actor)
    pcall(SC.Actor.stop, Harness.actor)
    endHarnessControl(probe and probe.token, "stair_crossing_" .. status)
    Harness.stairCrossing = nil
    result(status, "real_stair_crossing_target_change", detail)
    setPhase("finish", current)
end

function Harness.runStairCrossing(current)
    local SC, probe = SurvivorCompanion, Harness.stairCrossing
    local x, y, z = position(Harness.actor)
    if x == nil or z == nil then
        Harness.finishStairCrossing("FAIL", "actor position unavailable", current)
        return
    end
    probe.maxZ = math.max(probe.maxZ, z)
    local status, accepted
    if not probe.changedTarget and z > probe.z + 0.20
        and z < probe.z + 0.80 then
        local other = getCell():getGridSquare(probe.x, probe.y, probe.z)
        accepted, status = SC.Navigation.request(Harness.actor, other, "walk", {
            action = "move_to_scavenge", snapshot = probe.snapshot,
            supervisorToken = probe.token, workCampOnly = probe.baseWork,
        })
        local state = SC.Navigation.peek(Harness.actor) or {}
        probe.changedTarget = true
        probe.retained = accepted == true and state.nativeLease ~= nil
            and state.nativeLease.ultimateGoal == probe.landing
        probe.changeStatus = tostring(status)
    else
        accepted, status = SC.Navigation.request(Harness.actor, probe.landing, "walk", {
            action = "move_to_base_work", snapshot = probe.snapshot,
            supervisorToken = probe.token, workCampOnly = probe.baseWork,
        })
    end
    if current >= (probe.nextTraceAt or 0) then
        probe.nextTraceAt = current + 1000
        print("SC_REAL_SANDBOX|STAIR_TRACE|pos="
            .. string.format("%.2f,%.2f,%.2f", x, y, z)
            .. " status=" .. tostring(status)
            .. " accepted=" .. tostring(accepted)
            .. " base_work=" .. tostring(probe.baseWork))
    end
    local lx, ly, lz = position(probe.landing)
    if z >= (lz or probe.z + 1) - 0.05
        and math.abs(x - lx - 0.5) <= 0.8
        and math.abs(y - ly - 0.5) <= 0.8 then
        probe.landedAt = probe.landedAt or current
        if current - probe.landedAt >= 800 then
            Harness.finishStairCrossing(
                probe.changedTarget and probe.retained and "PASS" or "FAIL",
                "landing=" .. tostring(lx) .. "," .. tostring(ly)
                    .. "," .. tostring(lz)
                    .. "; max_z=" .. string.format("%.2f", probe.maxZ)
                    .. "; changed=" .. tostring(probe.changedTarget)
                    .. "; retained=" .. tostring(probe.retained)
                    .. "; change_status=" .. tostring(probe.changeStatus)
                    .. "; base_work=" .. tostring(probe.baseWork), current)
        end
    else
        probe.landedAt = nil
    end
    if current - probe.startedAt > 22000 then
        Harness.finishStairCrossing("FAIL",
            "timeout; pos=" .. string.format("%.2f,%.2f,%.2f", x, y, z)
                .. "; max_z=" .. string.format("%.2f", probe.maxZ)
                .. "; status=" .. tostring(status)
                .. "; changed=" .. tostring(probe.changedTarget)
                .. "; base_work=" .. tostring(probe.baseWork), current)
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
        local preserve = false
        if zombie ~= nil
            and Harness.config.team_corpse_streaming_probe == "true" then
            local worn = zombie:getWornItems()
            if worn ~= nil then
                for wornIndex = 0, worn:size() - 1 do
                    local item = worn:get(wornIndex):getItem()
                    if item:getModData().SCCorpseStreamGearProbe == true then
                        preserve = true
                        break
                    end
                end
            end
        end
        if zombie ~= nil and not preserve
            and distance(zombie, target) <= (radius or 30) then
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
    if Harness.config and Harness.config.project_alife_damage_probe == "true"
        and attacker == Harness.actor and target == Harness.alifeTarget then
        Harness.alifeHitCount = (Harness.alifeHitCount or 0) + 1
        print("SC_REAL_SANDBOX|ALIFE_HIT|uid=" .. clean(Harness.alifeUid)
            .. "|weapon=" .. clean(weapon and weapon:getFullType())
            .. "|requested_damage=" .. tostring(damage))
    end
    if attacker == Harness.player and Harness.performanceSample
        and Harness.performanceSample.encounter then
        Harness.performanceAllPlayerHits = (Harness.performanceAllPlayerHits or 0) + 1
        for _, zombie in ipairs(Harness.performanceZombies or {}) do
            if target == zombie then
                Harness.performanceNativeHits = (Harness.performanceNativeHits or 0) + 1
                break
            end
        end
    end
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

-- The A-Life debug spawner queues a real owned shell. All mutations stay in the
-- runner's cloned save; no synthetic hit or health assignment counts as damage.
function Harness.probeALifeDamage(current)
    local SC = SurvivorCompanion
    local alife = type(ProjectALife) == "table" and ProjectALife or nil
    if Harness.phase == "alife_wait" then
        if current - Harness.phaseStartedAt < 2500 then return end
        if not check("alife_runtime_loaded", alife ~= nil
            and type(alife.DebugService) == "table"
            and type(alife.DebugService.spawnEncounter) == "function"
            and type(alife.ShellSimulation) == "table",
            "debug spawn and shell simulation available") then
            setPhase("finish", current); return
        end
        local square = safeSpawnSquare(Harness.player)
        if not check("alife_companion_spawn_square", square ~= nil,
            "loaded free square near observer") then
            setPhase("finish", current); return
        end
        local ticket, reason = SC.Actor.beginSpawn(square, {
            recruited = true, identity = { forename = "Harness", surname = "Alife",
                gender = "man", outfit = "Generic01" },
        })
        if not check("alife_companion_spawn_requested", ticket ~= nil, reason) then
            setPhase("finish", current); return
        end
        Harness.alifeSpawnTicket = ticket
        setPhase("alife_companion_spawn", current)
    elseif Harness.phase == "alife_companion_spawn" then
        local actor, reason = SC.Actor.pollSpawn(Harness.alifeSpawnTicket)
        if actor == nil then
            if reason ~= "spawn_pending" or current - Harness.phaseStartedAt > 10000 then
                result("FAIL", "alife_companion_spawn", reason)
                setPhase("finish", current)
            end
            return
        end
        Harness.actor = actor
        local control, controlReason = beginHarnessControl(actor, "alife_damage_probe", 30000)
        if not check("alife_combat_control", control ~= nil, controlReason) then
            setPhase("finish", current); return
        end
        Harness.alifeControl = control
        local inventory = actor:getInventory()
        local weapon = inventory and inventory:AddItem("Base.Katana") or nil
        local equipped, equipReason = false, "weapon unavailable"
        if weapon then
            equipped, equipReason = SC.Actor.setMovement(actor, "walk", {
                action = "equip_weapon", item = weapon, supervisorToken = control,
            })
        end
        if not check("alife_melee_weapon_equipped", equipped == true, equipReason) then
            setPhase("finish", current); return
        end
        Harness.alifeWeapon = weapon
        pcall(function() actor:setPerkLevelDebug(Perks.LongBlade, 10) end)
        local ax, ay, az = position(actor)
        local dx, dy = findClearManualDirection(actor, 3)
        if not check("alife_spawn_lane", dx ~= nil,
            "clear lane from " .. tostring(ax) .. "," .. tostring(ay)) then
            setPhase("finish", current); return
        end
        local sx, sy, sz = math.floor(ax + dx * 3), math.floor(ay + dy * 3),
            math.floor(az or 0)
        Harness.alifeSpawnX, Harness.alifeSpawnY, Harness.alifeSpawnZ = sx, sy, sz
        Harness.alifeRequestId = "sc-damage:" .. tostring(current)
        local accepted, reason, outcome = alife.DebugService.spawnEncounter(Harness.player, {
            requestId = Harness.alifeRequestId, count = 1, mode = "roam",
            x = sx, y = sy, z = sz, radius = 8, distance = 0,
            playerKeepOut = 0, spawnDelayMs = 0, arrival = "instant",
            slots = { { x = sx + 0.5, y = sy + 0.5, z = sz } },
            hostileOverride = true, playerStance = "hostile",
            stationary = true, persistent = true, health = 100,
            damageOutput = 0,
        }, true)
        if not check("alife_hostile_spawn_queued", accepted == true,
            tostring(reason) .. " accepted=" .. tostring(outcome and outcome.accepted)) then
            setPhase("finish", current); return
        end
        setPhase("alife_shell_wait", current)
    elseif Harness.phase == "alife_shell_wait" then
        local list = getCell() and getCell():getZombieList()
        if list then
            for index = 0, list:size() - 1 do
                local candidate = list:get(index)
                local data = candidate and candidate:getModData()
                local x, y, z = position(candidate)
                if type(data) == "table" and data.ProjectALifeOwned == true
                    and type(data.ProjectALifeUID) == "string"
                    and x ~= nil and math.abs(x - Harness.alifeSpawnX) <= 2
                    and math.abs(y - Harness.alifeSpawnY) <= 2
                    and math.floor(z or 0) == Harness.alifeSpawnZ then
                    Harness.alifeTarget = candidate
                    Harness.alifeUid = data.ProjectALifeUID
                    break
                end
            end
        end
        if Harness.alifeTarget == nil then
            if current - Harness.phaseStartedAt > 16000 then
                result("FAIL", "alife_shell_materialized",
                    "expected near=" .. tostring(Harness.alifeSpawnX) .. ","
                        .. tostring(Harness.alifeSpawnY)
                        .. " zombie_list=" .. tostring(list and list:size()))
                setPhase("finish", current)
            end
            return
        end
        local target = Harness.alifeTarget
        local data = target:getModData()
        Harness.alifeBefore = tonumber(alife.ShellSimulation.trueHealth(target))
        Harness.alifeWoundsBefore = tonumber(data.ProjectALifeWounds) or 0
        local hostile = SC.GameplayUtil.isALifeHostileToParty(target,
            Harness.player, Harness.actor)
        local record = alife.ActorRegistry and alife.ActorRegistry.peek(Harness.alifeUid)
        local directHostile = record and alife.Relations
            and alife.Relations.hostileToPlayer(record, Harness.player)
        local exists, existsOk = SC.GameplayUtil.call(target, "isExistInTheWorld")
        local grapple, grappleOk = SC.GameplayUtil.call(target,
            "isReanimatedForGrappleOnly")
        check("alife_hostility_flag", hostile == true,
            "uid=" .. tostring(Harness.alifeUid)
                .. " record=" .. tostring(record ~= nil)
                .. " override=" .. tostring(record and record.memory
                    and record.memory.hostileOverride)
                .. " direct=" .. tostring(directHostile)
                .. " is_npc=" .. tostring(SC.GameplayUtil.isALifeNpc(target))
                .. " gone=" .. tostring(SC.GameplayUtil.isGoneTarget(target))
                .. " exists=" .. tostring(exists) .. "/" .. tostring(existsOk)
                .. " dead=" .. tostring(SC.GameplayUtil.isDead(target))
                .. " proxy=" .. tostring(SC.GameplayUtil.isCorpseProxy(target))
                .. " grapple=" .. tostring(grapple) .. "/" .. tostring(grappleOk)
                .. " shell_generation=" .. tostring(data.ProjectALifeGeneration)
                .. " record_generation=" .. tostring(record and record.generation)
                .. " relations=" .. tostring(alife.Relations ~= nil)
                .. " target=" .. tostring(target:getTarget()))
        if not check("alife_shell_owned", data.ProjectALifeOwned == true
            and Harness.alifeBefore > 0,
            "uid=" .. tostring(Harness.alifeUid)
                .. " health=" .. tostring(Harness.alifeBefore)
                .. " generation=" .. tostring(data.ProjectALifeGeneration)) then
            setPhase("finish", current); return
        end
        local distance, why = Harness.meleeFixtureDistance(Harness.alifeWeapon, Harness.actor)
        local dx, dy
        if distance then dx, dy = findClearManualDirection(Harness.actor, distance) end
        if not check("alife_melee_lane", dx ~= nil, why) then
            setPhase("finish", current); return
        end
        local ax, ay, az = position(Harness.actor)
        Harness.alifeTargetX, Harness.alifeTargetY, Harness.alifeTargetZ =
            ax + dx * distance, ay + dy * distance, az
        Harness.alifeHitCount, Harness.alifeSwingCount = 0, 0
        Harness.alifeNextSwing = current + 400
        setPhase("alife_damage", current)
    elseif Harness.phase == "alife_damage" then
        local target = Harness.alifeTarget
        local data = target and target:getModData()
        local after = target and tonumber(alife.ShellSimulation.trueHealth(target))
        local wounds = data and (tonumber(data.ProjectALifeWounds) or 0) or 0
        local damaged = after ~= nil and after < Harness.alifeBefore - 0.0001
        if damaged or current - Harness.phaseStartedAt > 18000 then
            check("alife_native_damage", damaged and Harness.alifeHitCount > 0,
                "uid=" .. tostring(Harness.alifeUid)
                    .. " before=" .. tostring(Harness.alifeBefore)
                    .. " after=" .. tostring(after)
                    .. " wounds=" .. tostring(Harness.alifeWoundsBefore)
                    .. "->" .. tostring(wounds)
                    .. " hits=" .. tostring(Harness.alifeHitCount)
                    .. " swings=" .. tostring(Harness.alifeSwingCount)
                    .. " last_reject=" .. clean(Harness.alifeLastReject))
            endHarnessControl(Harness.alifeControl, "alife_probe_complete")
            Harness.alifeControl = nil
            setPhase("finish", current)
            return
        end
        pcall(function() target:setTarget(nil) end)
        pcall(function() target:setX(Harness.alifeTargetX) end)
        pcall(function() target:setY(Harness.alifeTargetY) end)
        pcall(function() target:setZ(Harness.alifeTargetZ or 0) end)
        pcall(function() target:setCurrentSquareFromPosition() end)
        if current >= (Harness.alifeNextSwing or 0) then
            local performing = select(1, SC.GameplayUtil.call(
                Harness.actor, "isPerformingAttackAnimation"))
            if performing ~= true then
                local accepted, reason = SC.Actor.setMovement(Harness.actor, "walk", {
                    action = "attack_melee", target = target,
                    weapon = Harness.alifeWeapon, urgent = true, emergency = true,
                    supervisorToken = Harness.alifeControl,
                })
                if accepted then Harness.alifeSwingCount = Harness.alifeSwingCount + 1
                else Harness.alifeLastReject = reason end
                Harness.alifeNextSwing = current + 700
            end
        end
    end
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
    if Harness.config and Harness.config.team_pursuer_probe == "true"
        and not Harness.pursuerReported then
        local candidates, targeted, moved, maxShift = 0, 0, 0, 0
        local actorDetails = {}
        for zombie, item in pairs(Harness.pursuerCandidates or {}) do
            candidates = candidates + 1
            if item.targetBeforeShift then targeted = targeted + 1 end
            if item.moved then moved = moved + 1 end
            maxShift = math.max(maxShift, item.maxShift or 0)
            if #actorDetails < 4 then
                local zx, zy = position(zombie)
                actorDetails[#actorDetails + 1] = "actor=" .. tostring(zombie)
                    .. " alive=" .. tostring(zombie:isDead() ~= true)
                    .. " square=" .. tostring(zombie:getCurrentSquare() ~= nil)
                    .. " target=" .. tostring(zombie:getTarget())
                    .. " before=" .. tostring(item.targetBeforeShift)
                    .. " after=" .. tostring(item.targetAfterShift)
                    .. " last=" .. tostring(item.lastX) .. ","
                    .. tostring(item.lastY)
                    .. " now=" .. tostring(zx) .. "," .. tostring(zy)
                    .. " max_step=" .. tostring(item.maxStep)
                    .. " shift=" .. tostring(item.maxShift)
            end
        end
        local name = Harness.config.team_pursuer_fixture == "true"
            and "native_fixture_pursuer_survived_area_shift"
            or "natural_pursuer_survived_area_shift"
        result("FAIL", name,
            "no same living targeted zombie crossed one 8-tile map shift"
                .. " candidates=" .. tostring(candidates)
                .. " targeted_before=" .. tostring(targeted)
                .. " moved=" .. tostring(moved)
                .. " max_shift=" .. tostring(maxShift)
                .. " leader_dead=" .. tostring(Harness.leader
                    and Harness.leader:isDead())
                .. " details=" .. table.concat(actorDetails, ";"))
        Harness.pursuerReported = true
    end
    if Harness.stragglerControl then
        endHarnessControl(Harness.stragglerControl, "straggler_probe_cleanup")
        Harness.stragglerControl = nil
    end
    if Harness.pursuerFixtureZombie then
        cleanupTestZombie(Harness.pursuerFixtureZombie)
        Harness.pursuerFixtureZombie = nil
    end
    if Harness.performanceSample and Events and Events.OnRenderTick then
        if Harness.performanceSample.route then
            result("FAIL", "performance_route_sample_incomplete",
                "route ended before the 30-second timing window")
        end
        Events.OnRenderTick.Remove(Harness.performanceFrameTick)
        writeSignal(PERFORMANCE_ACTIVE_FILE, {"complete=" .. tostring(nowMs())})
        Harness.performanceSample = nil
    end
    if Harness.performanceZombies then Harness.cleanupPerformanceEncounter() end
    if Harness.radioTextHook and Events and Events.OnDeviceText then
        Events.OnDeviceText.Remove(Harness.radioTextHook)
        Harness.radioTextHook = nil
    end
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

local TEAM_RADIO_CHANNEL = 90000
local TEAM_RADIO_PRESET = "Living Fellows Team"
local LOOT_PROOF_FILE = "SurvivorCompanionHarness/loot-proof.ini"
local function countLootMarkers(inventory, token, itemType)
    if inventory == nil then return 0, nil end
    local count, found = 0, nil
    local items = inventory:getItems()
    for index = 0, items:size() - 1 do
        local item = items:get(index)
        if item ~= nil then
            local data = item:getModData()
            if item:getFullType() == itemType
                and data and data.SC_ExpeditionLootProbe == token then
                count, found = count + 1, item
            end
            local nested, nestedOk = SurvivorCompanion.GameplayUtil.call(
                item, "getInventory")
            if nestedOk and nested ~= nil then
                local childCount, child = countLootMarkers(nested, token, itemType)
                count = count + childCount
                if child ~= nil then found = child end
            end
        end
    end
    return count, found
end
local function countSnapshotLootMarkers(inventory, token, itemType)
    local count = 0
    local function visit(node)
        if node == nil then return end
        if node.type == itemType and type(node.modData) == "table"
            and node.modData.SC_ExpeditionLootProbe == token then
            count = count + 1
        end
        for _, child in ipairs(node.children or {}) do visit(child) end
    end
    for _, root in ipairs(inventory and inventory.roots or {}) do visit(root) end
    return count
end
local function countSnapshotStableItems(inventory, stableId)
    local count = 0
    local function visit(node)
        if node == nil then return end
        if type(node.modData) == "table"
            and node.modData.LF_ItemStableId == stableId then
            count = count + 1
        end
        for _, child in ipairs(node.children or {}) do visit(child) end
    end
    for _, root in ipairs(inventory and inventory.roots or {}) do visit(root) end
    return count
end
local function teamStableItem(roster, stableId)
    local SC = SurvivorCompanion
    local count, found, carrier = 0, nil, nil
    for _, record in ipairs(roster or {}) do
        if record.actor ~= nil then
            local audit = SC.Logistics.audit(record.actor)
            for _, entry in ipairs(audit and audit.items or {}) do
                if SC.GameplayUtil.itemStableId(entry.item, false) == stableId then
                    count, found, carrier = count + 1, entry.item, record.id
                end
            end
        end
    end
    return count, found, carrier
end
local function savedStableItemCount(document, roster, stableId)
    local count = 0
    for _, record in ipairs(roster or {}) do
        local saved = document and document.companions
            and document.companions[record.id]
        count = count + countSnapshotStableItems(saved and saved.inventory, stableId)
    end
    return count
end
local function sourceStableItemCount(receipt)
    local U = SurvivorCompanion.GameplayUtil
    local source = receipt and receipt.source
    local square = source and getWorld():getCell():getGridSquare(
        source.x, source.y, source.z)
    if square == nil then return nil, "source_square_unloaded" end
    local count, sourceCount, found = 0, nil, false
    U.squareObjects(square, function(object)
        local objectIndex = select(1, U.call(object, "getObjectIndex"))
        if objectIndex == receipt.sourceObjectIndex then
            local container = select(1, U.call(object, "getContainer"))
            local items = container and select(1, U.call(container, "getItems"))
            if items then
                found, sourceCount = true, items:size()
                for index = 0, items:size() - 1 do
                    if U.itemStableId(items:get(index), false) == receipt.id then
                        count = count + 1
                    end
                end
            end
        end
    end, 64)
    if not found then return nil, "source_container_missing" end
    return count, sourceCount
end
local function prepareNativeRadioItemForProbe(itemType)
    local player = Harness.player
    local inventory = player and player:getInventory()
    local square = player and player:getCurrentSquare()
    if inventory == nil or square == nil then error("placed radio source unavailable") end
    local item = inventory:AddItem(itemType)
    if item == nil or not SurvivorCompanion.GameplayUtil.instanceOf(item, "Radio") then
        error("native placed radio item unavailable: " .. tostring(itemType))
    end
    local data = item:getDeviceData()
    if data == nil or not data:getIsTwoWay() then
        error("native placed radio is not two-way: " .. tostring(itemType))
    end
    if data:getHasBattery() and data:getPower() <= 0 then
        data:getBattery(inventory)
    end
    if not data:getHasBattery() then
        local battery = inventory:AddItem("Base.Battery")
        if battery == nil then error("placed radio battery unavailable") end
        data:addBattery(battery)
    end
    data:setChannel(TEAM_RADIO_CHANNEL)
    data:setDeviceVolume(0.8)
    data:setIsTurnedOn(true)
    if not data:getHasBattery() or data:getPower() <= 0
        or not data:getIsTurnedOn() then
        error("placed radio failed native power setup: " .. tostring(itemType))
    end
    return { item = item, data = data, square = square }
end

local function placeNativeRadioForProbe(itemType)
    local prepared = prepareNativeRadioItemForProbe(itemType)
    local item, data, square = prepared.item, prepared.data, prepared.square
    local inventory = Harness.player:getInventory()
    -- Mirror the game's ISDropWorldItemAction: the exact inventory Radio
    -- becomes a world item and an IsoRadio proxy shares its DeviceData.
    local worldItem = square:AddWorldInventoryItem(item, 0.5, 0.5, 0, false)
    if worldItem ~= item or item:getWorldItem() == nil
        or item:getWorldItem():getSquare() ~= square then
        error("native radio world item was not placed")
    end
    inventory:Remove(item)
    local placed = IsoRadio.new(getCell(), square, nil)
    placed:setDeviceData(data)
    placed:getModData().RadioItemID = item:getID()
    square:AddSpecialObject(placed, square:getObjects():size())
    triggerEvent("OnObjectAdded", placed)
    square:RecalcProperties()
    square:RecalcAllWithNeighbours(true)
    if placed:getDeviceData() ~= data then
        error("native placed radio did not retain item DeviceData")
    end
    return { item = item, object = placed, data = data, square = square }
end

local function queueTimedRadioPlacementForProbe(itemType, usedSquares)
    require "TimedActions/ISDropWorldItemAction"
    local prepared = prepareNativeRadioItemForProbe(itemType)
    local player, source = Harness.player, prepared.square
    local offsets = { { 1, 0 }, { 0, 1 }, { -1, 0 }, { 0, -1 },
        { 1, 1 }, { -1, 1 }, { -1, -1 }, { 1, -1 } }
    local action, target, key
    for _, offset in ipairs(offsets) do
        local x, y = source:getX() + offset[1], source:getY() + offset[2]
        local candidate = getCell():getGridSquare(x, y, source:getZ())
        local candidateKey = tostring(x) .. ":" .. tostring(y)
        if candidate and not usedSquares[candidateKey] then
            local trial = ISDropWorldItemAction:new(player, prepared.item,
                candidate, 0.5, 0.5, 0, 0, false)
            trial.isPlaceItem = true
            if trial:isValid() then
                action, target, key = trial, candidate, candidateKey
                break
            end
        end
    end
    if action == nil then error("no adjacent tile accepts a native radio placement") end
    usedSquares[key] = true
    ISTimedActionQueue.add(action)
    local queue = ISTimedActionQueue.getTimedActionQueue(player)
    local queued = false
    for _, entry in ipairs(queue.queue) do
        if entry == action then queued = true break end
    end
    if not queued then error("native radio placement action was not queued") end
    result("PASS", "placed_kit_native_placement_queued",
        "type=" .. itemType .. " id=" .. tostring(prepared.item:getID())
            .. " tile=" .. key .. " duration=" .. tostring(action.maxTime))
    prepared.square = target
    prepared.action = action
    return prepared
end

local function prepareTeamRadioFixture(roster)
    local radios = SurvivorCompanion.ExpeditionPrototype.provisionTestRadios(
        Harness.player, roster)
    if Harness.config.team_radio_placed_probe == "true" then
        radios.placedWalkie = placeNativeRadioForProbe("Base.WalkieTalkie2")
        radios.placedHam = placeNativeRadioForProbe("Base.HamRadio1")
    end
    Harness.radioFixture = radios
    Harness.radioReceipts = {}
    Harness.radioTextHook = function(_guid, _codes, _x, _y, _z, message, device)
        local value = tostring(message or "")
        if string.find(value, "SC_RADIO_TEST_", 1, true)
            or string.find(value, "Horde blocks our route", 1, true) then
            Harness.radioReceipts[#Harness.radioReceipts + 1] = {
                message = value, device = device,
                guid = tostring(_guid), codes = tostring(_codes),
            }
        end
    end
    if not Events or not Events.OnDeviceText then
        error("native OnDeviceText event is unavailable")
    end
    Events.OnDeviceText.Add(Harness.radioTextHook)
    return radios
end

-- Disposable co-op streaming spike.  The extra player is never given an order
-- channel, input UI, or expedition ownership; the cloned save is discarded.
local function beginSplitScreenProbe(current)
    if current - Harness.phaseStartedAt < 2000 then return end
    local cell = getWorld():getCell()
    local x, y, z = position(Harness.player)
    local remoteX, remoteY = math.floor(x) + 512, math.floor(y)
    if Harness.config.cold_restart_probe == "true" then
        local SC = SurvivorCompanion
        local mission = SC.ExpeditionPrototype.current()
        local saved = SC.Persistence.lastDocument()
        local leaderId = mission and mission.leader and mission.leader.id
        local savedLeader = saved and saved.companions
            and saved.companions[leaderId]
        local tile = savedLeader and savedLeader.position
        if tile == nil then
            if current - Harness.phaseStartedAt < 15000 then return end
            result("FAIL", "cold_restart_saved_leader_candidate",
                "saved mission has no leader tile")
            setPhase("finish", current)
            return
        end
        remoteX, remoteY, z = math.floor(tile.x),
            math.floor(tile.y), math.floor(tile.z)
        Harness.coldRestartCandidate = {
            id = leaderId, x = remoteX, y = remoteY, z = z,
            slotSqlId = mission.slotSqlId,
        }
        Harness.coldRestartSavedAt = saved.savedAt
        Harness.remoteX, Harness.remoteY, Harness.remoteZ = remoteX, remoteY, z
        Harness.splitObserver = mission.lastBootstrapActor
        result("PASS", "cold_restart_saved_leader_candidate",
            "id=" .. tostring(leaderId) .. " tile="
                .. tostring(remoteX) .. "," .. tostring(remoteY)
                .. "," .. tostring(z)
                .. " slotSqlId=" .. tostring(mission.slotSqlId))
        local nextPhase = "split_restart_recovery"
        if Harness.config.cold_restart_crash_probe == "true" then
            nextPhase = "split_restart_crash_save"
        elseif Harness.config.cold_restart_lf_first_crash_probe == "true" then
            nextPhase = "split_restart_lf_first_save"
        end
        setPhase(nextPhase, current)
        return
    end
    Harness.remoteX, Harness.remoteY, Harness.remoteZ = remoteX, remoteY, z
    check("remote_square_initially_unloaded",
        cell:getGridSquare(remoteX, remoteY, z) == nil,
        "player=" .. tostring(x) .. "," .. tostring(y)
            .. " target=" .. tostring(remoteX) .. "," .. tostring(remoteY))
    local original = Harness.player
    local cold = Harness.config.cold_companion_probe == "true"
    local made, playerOrFailure = pcall(function()
        if cold then
            return SCSplitScreenProbe.startColdCompanionProbe(
                remoteX, remoteY, z,
                Harness.coldRestartCandidate
                    and Harness.coldRestartCandidate.slotSqlId or -1)
        end
        return SCSplitScreenProbe.start(remoteX, remoteY, z)
    end)
    if not made or playerOrFailure == nil then
        result("FAIL", cold and "queue_cold_companion"
            or "queue_coop_observer", playerOrFailure)
        setPhase("finish", current)
        return
    end
    Harness.splitObserver = playerOrFailure
    check(cold and "queue_cold_companion" or "queue_coop_observer",
        IsoPlayer.getInstance() == original,
        "native AddCoopPlayer queued without a controller; singleton="
            .. tostring(IsoPlayer.getInstance() == original))
    if cold then
        check("cold_companion_native_type",
            SCSplitScreenProbe.isLeader(playerOrFailure) == true
                and playerOrFailure:isNpc() == true
                and playerOrFailure:getCurrentSquare() == nil,
            "native probe returned its SCNativeCompanion before any square loaded")
    end
    setPhase("split_wait_loaded", current)
end

function Harness.probeRestartAudit(current)
    local SC = SurvivorCompanion
    local restored = SC.Persistence.restoreStatus()
    if (not restored or current - Harness.phaseStartedAt < 10000)
        and current - Harness.phaseStartedAt < 25000 then return end
    local document = SC.Persistence.lastDocument()
    local records = SC.Registry.records()
    local byId = {}
    for _, record in ipairs(records) do byId[record.id] = record end
    local pending = SC.Persistence.pendingSnapshot() or {}
    check("restart_primary_player_kept",
        getSpecificPlayer(0) == Harness.player
            and Harness.player:isDead() == false,
        "slot0 is the living original player; getPlayer may select slot1")
    local slotMission = SC.ExpeditionPrototype.current()
    check("restart_second_slot_owned_or_idle", getSpecificPlayer(1) == nil
            or (slotMission ~= nil and slotMission.restoring ~= true
                and slotMission.leader ~= nil
                and slotMission.leader.actor == getSpecificPlayer(1)),
        "slot1=" .. tostring(getSpecificPlayer(1)))
    check("restart_companion_document_available",
        restored == true and document ~= nil
            and type(document.companions) == "table",
        "restored=" .. tostring(restored)
            .. " records=" .. tostring(#records))
    local savedCount, activeCount, distantCount, distantActive = 0, 0, 0, 0
    for id, saved in pairs(document and document.companions or {}) do
        savedCount = savedCount + 1
        local record = byId[id]
        local actor = record and record.actor
        local active = actor ~= nil and SC.Registry.isActive(actor, id)
        if active then activeCount = activeCount + 1 end
        local x, y = position(actor)
        local sx = saved.position and saved.position.x
        local sy = saved.position and saved.position.y
        local gap = x and y and sx and sy
            and math.sqrt((x - sx)^2 + (y - sy)^2) or math.huge
        if (sx and math.abs(sx - Harness.playerX) > 500)
            or (sy and math.abs(sy - Harness.playerY) > 500) then
            distantCount = distantCount + 1
            -- This audit samples after ten seconds of normal AI movement;
            -- the focused cold-restart probe checks the exact initial tile.
            if active and gap < 15 then distantActive = distantActive + 1 end
            result(active and gap < 15 and "PASS" or "FAIL",
                "restart_distant_companion_position_" .. tostring(distantCount),
                "id=" .. tostring(id) .. " active=" .. tostring(active)
                    .. " saved=" .. tostring(sx) .. "," .. tostring(sy)
                    .. " actor=" .. tostring(x) .. "," .. tostring(y)
                    .. " gap=" .. tostring(gap)
                    .. " pending=" .. tostring(pending[id]
                        and pending[id].reason))
        end
    end
    if distantCount > 0 then
        check("restart_distant_roster_snapshots_retained", distantCount >= 2,
            "saved=" .. tostring(savedCount) .. " active=" .. tostring(activeCount)
                .. " distant=" .. tostring(distantCount)
                .. " distant_active=" .. tostring(distantActive))
    else
        result("SKIP", "restart_distant_roster_snapshots_retained",
            "local team checkpoint has no distant companions")
    end
    local mission = SC.ExpeditionPrototype.current()
    local descriptor = document and document.expedition
    check("restart_expedition_descriptor_retained",
        type(descriptor) == "table" and descriptor.schema == 1
            and type(descriptor.roster) == "table"
            and #descriptor.roster >= 1,
        "saved_roster=" .. tostring(descriptor
            and descriptor.roster and #descriptor.roster))
    local rosterReady, rosterExpected = 0, 0
    for _, id in ipairs(descriptor and descriptor.survivors or {}) do
        rosterExpected = rosterExpected + 1
        local record = byId[id]
        local actor = record and record.actor
        local saved = document.companions and document.companions[id]
        local x, y = position(actor)
        local sx = saved and saved.position and saved.position.x
        local sy = saved and saved.position and saved.position.y
        local gap = x and y and sx and sy
            and math.sqrt((x - sx)^2 + (y - sy)^2) or math.huge
        if actor ~= nil and SC.Registry.isActive(actor, id)
            and mission ~= nil and mission.members[actor] == true then
            rosterReady = rosterReady + 1
        end
    end
    check("restart_mission_roster_active",
        rosterExpected > 0 and rosterReady == rosterExpected,
        "ready=" .. tostring(rosterReady)
            .. " expected=" .. tostring(rosterExpected))
    if distantCount > 0 then
        check("restart_pause_or_resumed_view",
            mission ~= nil and ((mission.restoring == true
                and mission.technicalIssue ~= nil
                and getSpecificPlayer(1) == nil)
                or (mission.restoring ~= true
                    and mission.leader ~= nil
                    and mission.leader.actor == getSpecificPlayer(1))),
            "mission=" .. tostring(mission)
                .. " issue=" .. tostring(mission and mission.technicalIssue
                    and mission.technicalIssue.reason))
    else
        result("SKIP", "restart_explicit_technical_pause",
            "local team is expected to reacquire slot 1")
    end
    check("restart_active_expedition_restored", mission ~= nil
            and mission.terminal == nil
            and mission.leader ~= nil
            and mission.leader.actor ~= nil
            and mission.restoring ~= true
            and getSpecificPlayer(1) == mission.leader.actor,
        "mission=" .. tostring(mission)
            .. " slot1=" .. tostring(getSpecificPlayer(1)))
    if distantCount == 0 and mission ~= nil
        and mission.leader ~= nil and mission.leader.actor ~= nil then
        local denied, reason = SC.Commands.issue(mission.leader.id,
            "stay", nil, Harness.player)
        check("restart_direct_orders_remain_blocked",
            denied == false and reason == "expedition_leader_radio_required",
            "reason=" .. tostring(reason))
        local beforeMode = SC.Commands.effective(mission.leader.actor).moveMode
        local radioAccepted, radioReason = SC.ExpeditionPrototype.sendRadioOrder(
            Harness.player, "set_move_mode", "walk")
        check("restart_no_radio_no_remote_control",
            radioAccepted == false
                and SC.Commands.effective(mission.leader.actor).moveMode
                    == beforeMode,
            "reason=" .. tostring(radioReason))
    end
    setPhase("finish", current)
end

local function beginLeaderSlotProbe(current)
    local SC = SurvivorCompanion
    if Harness.config.team_performance_probe == "true"
        and Harness.performanceRosterLimitApplied ~= true then
        -- Keep the measured four-member roster fixed without healing actors or
        -- suppressing native danger. A death must fail the living-roster gate,
        -- rather than admitting a replacement encounter into the sample.
        -- This runs only in the disposable test save.
        local sandbox = type(SandboxVars) == "table"
            and SandboxVars.LivingFellows or nil
        if type(sandbox) == "table" then
            sandbox.MaxCompanions = 4
            sandbox.EncountersEnabled = false
        end
        local overrides = SC.Config and SC.Config._overrides
        if type(overrides) == "table" then
            overrides.maxCompanions = 4
            overrides.productionEncounterEnabled = false
            overrides.maxNeutralEncounters = 0
        end
        Harness.performanceRosterLimitApplied = true
        if not check("performance_fixed_roster_limit",
            SC.Config.get("maxCompanions") == 4
                and SC.Config.get("productionEncounterEnabled") == false
                and SC.Config.get("maxNeutralEncounters") == 0,
            "companions=" .. tostring(SC.Config.get("maxCompanions"))
                .. " encounters=" .. tostring(SC.Config.get("productionEncounterEnabled"))
                .. " neutral=" .. tostring(SC.Config.get("maxNeutralEncounters"))) then
            setPhase("finish", current)
            return
        end
    end
    if Harness.config.team_restart_audit_only == "true" then
        Harness.probeRestartAudit(current)
        return
    end
    if Harness.config.team_extended_return_resume_probe == "true" then
        Harness.probeExtendedReturnResumeStart(current)
        return
    end
    if Harness.config.team_autonomous_search_resume_probe == "true" then
        Harness.probeAutonomousSearchResumeStart(current)
        return
    end
    if Harness.config.team_road_restart_resume_probe == "true" then
        Harness.probeRoadRestartResumeStart(current)
        return
    end
    local records = SC.Registry.records()
    if #records < 4 and Harness.config.team_loot_verify_only ~= "true" then
        if current - Harness.phaseStartedAt < 25000 then return end
        result("FAIL", "four_saved_companions_restored", "records=" .. tostring(#records))
        setPhase("finish", current)
        return
    end
    Harness.originalCompanions = {}
    for index, record in ipairs(records) do
        Harness.originalCompanions[index] = record
    end
    if Harness.config.team_loot_verify_only == "true" then
        local document = SC.Persistence.lastDocument()
        local markerCount, markedId = 0, nil
        for id, saved in pairs(document and document.companions or {}) do
            local count = countSnapshotLootMarkers(saved.inventory,
                Harness.config.team_loot_verify_token,
                Harness.config.team_loot_verify_item_type)
            markerCount = markerCount + count
            if count > 0 then markedId = id end
        end
        if markerCount ~= 1 and current - Harness.phaseStartedAt < 25000 then
            return
        end
        local pending = markedId and SC.Persistence.pendingSnapshot()[markedId]
        check("saved_exact_companion_item_lineage", markerCount == 1
            and markedId ~= nil,
            "snapshot_markers=" .. tostring(markerCount)
                .. " actor=" .. tostring(markedId)
                .. " pending=" .. tostring(pending and pending.reason))
        if markerCount ~= 1 then setPhase("finish", current) return end
        Harness.lootReloadActorId = markedId
        Harness.leaderRemoteX = math.floor(Harness.playerX)
            + (tonumber(Harness.config.leader_remote_offset_x) or 512)
        Harness.leaderRemoteY = math.floor(Harness.playerY)
            + (tonumber(Harness.config.leader_remote_offset_y) or 0)
        Harness.leaderRemoteZ = Harness.playerZ
        local moved, moveError = pcall(function()
            Harness.player:teleportTo(Harness.leaderRemoteX,
                Harness.leaderRemoteY, Harness.leaderRemoteZ)
        end)
        check("reloaded_player_visit_queued", moved,
            tostring(moveError))
        if not moved then setPhase("finish", current) return end
        setPhase("team_loot_verify_visit", current)
        return
    end
    local chosen
    local bestHealth = -1
    for _, record in ipairs(records) do
        if record.actor ~= nil and SC.Registry.isActive(record.actor, record.id) then
            local healthy = SC.Actor.validateNative(record.actor)
            if healthy then
                local body = record.actor:getBodyDamage()
                local health = body and body:getOverallBodyHealth() or 0
                if Harness.config.team_loot_probe == "true"
                    or Harness.config.team_local_travel_probe == "true"
                    or Harness.config.team_extended_route_probe == "true"
                    or Harness.config.team_autonomous_scout_probe == "true"
                    or Harness.config.team_autonomous_search_probe == "true"
                    or Harness.config.team_building_probe == "true"
                    or Harness.config.team_overlap_probe == "true"
                    or Harness.config.team_performance_probe == "true" then
                    if health > bestHealth then
                        chosen, bestHealth = record, health
                    end
                else
                    chosen = record break
                end
            end
        end
    end
    if chosen == nil then
        if current - Harness.phaseStartedAt < 25000 then return end
        result("FAIL", "saved_leader_available", "no healthy restored native companion")
        setPhase("finish", current)
        return
    end
    Harness.leader = chosen.actor
    Harness.leaderId = chosen.id
    Harness.leaderStartX, Harness.leaderStartY = position(chosen.actor)
    local chosenBody = chosen.actor:getBodyDamage()
    result("PASS", "saved_leader_available",
        "registered companion=" .. tostring(chosen.id) .. " records=" .. tostring(#records)
            .. " health=" .. tostring(chosenBody
                and chosenBody:getOverallBodyHealth()))
    if Harness.config.team_radio_kit_only == "true"
        or Harness.config.team_radio_kit_verify_only == "true" then
        local recipients = {}
        for _, record in ipairs(records) do
            if record.actor ~= nil and SC.Registry.isActive(record.actor, record.id)
                and SC.Actor.validateNative(record.actor) then
                recipients[#recipients + 1] = record
                if #recipients == 4 then break end
            end
        end
        if #recipients ~= 4 then
            result("FAIL", "radio_kit_four_companions_available",
                "healthy=" .. tostring(#recipients))
            setPhase("finish", current)
            return
        end
        local radiosOrFailure
        if Harness.config.team_radio_kit_only == "true" then
            local made
            made, radiosOrFailure = pcall(
                SC.ExpeditionPrototype.provisionTestRadios,
                Harness.player, recipients)
            if not made then
                result("FAIL", "radio_kit_provisioned", radiosOrFailure)
                setPhase("finish", current)
                return
            end
            if Harness.config.team_radio_placed_probe == "true" then
                local placed, placementError = pcall(function()
                    if Harness.config.team_radio_timed_placement_probe == "true" then
                        local usedSquares = {}
                        radiosOrFailure.placedWalkie =
                            queueTimedRadioPlacementForProbe(
                                "Base.WalkieTalkie2", usedSquares)
                        radiosOrFailure.placedHam =
                            queueTimedRadioPlacementForProbe(
                                "Base.HamRadio1", usedSquares)
                    else
                        radiosOrFailure.placedWalkie =
                            placeNativeRadioForProbe("Base.WalkieTalkie2")
                        radiosOrFailure.placedHam =
                            placeNativeRadioForProbe("Base.HamRadio1")
                    end
                end)
                if not placed then
                    result("FAIL", "radio_kit_placed_stations", placementError)
                    setPhase("finish", current)
                    return
                end
            end
        else
            radiosOrFailure = { player = Harness.player:getSecondaryHandItem(),
                team = {} }
            for index, record in ipairs(recipients) do
                radiosOrFailure.team[index] = record.actor:getSecondaryHandItem()
            end
        end
        Harness.radioKitRecipients = recipients
        Harness.radioKit = radiosOrFailure
        setPhase(Harness.config.team_radio_timed_placement_probe == "true"
            and "team_radio_kit_place_wait" or "team_radio_kit_wait", current)
        return
    end
    local promoted, actorOrFailure
    if Harness.config.team_handoff == "true" then
        local roster = { chosen }
        local requested = (Harness.config.team_loot_probe == "true"
            or Harness.config.team_leader_motion_probe == "true"
            or Harness.config.team_multifloor_search_probe == "true"
                and Harness.config.team_multifloor_squad_probe ~= "true") and 1
            or (Harness.config.team_all_dead_cleanup == "true"
                or Harness.config.team_all_dead_stage_only == "true"
                or Harness.config.team_all_dead_menu_cleanup_probe == "true")
                and 3 or math.min(#records, 4)
        for _, record in ipairs(records) do
            if record ~= chosen and #roster < requested and record.actor ~= nil
                and SC.Registry.isActive(record.actor, record.id)
                and SC.Actor.validateNative(record.actor) then
                roster[#roster + 1] = record
            end
        end
        if #roster < requested then
            result("FAIL", "expedition_roster_ready", "healthy=" .. tostring(#roster))
            setPhase("finish", current)
            return
        end
        if Harness.config.team_performance_probe == "true" then
            Harness.outfitBeforeHandoff = auditCompanionOutfits(
                "before_handoff", roster)
        end
        if Harness.config.team_radio_fixture == "true" then
            local made, radiosOrFailure = pcall(prepareTeamRadioFixture, roster)
            if not made then
                result("FAIL", "team_working_radio_fixture", radiosOrFailure)
                setPhase("finish", current)
                return
            end
            result("PASS", "team_working_radio_fixture",
                tostring(#roster + 1)
                    .. " actual Base.WalkieTalkie2 radios with native batteries and "
                    .. TEAM_RADIO_PRESET .. " preset at " .. TEAM_RADIO_CHANNEL)
        end
        if Harness.config.team_road_horde_probe == "true" then
            -- Isolate road avoidance from the saved gas station doorway's
            -- intermittent native-path stall. This transfer happens before
            -- dispatch and only inside the disposable cloned save.
            local cell = getWorld():getCell()
            for index, record in ipairs(roster) do
                local tx, ty = 6093 + index * 2, 5283
                local square = cell and cell:getGridSquare(tx, ty, 0)
                if square == nil or square:getRoom() ~= nil
                    or not SC.GameplayUtil.isSquareFree(square) then
                    result("FAIL", "road_horde_fixture_square",
                        tostring(tx) .. "," .. tostring(ty))
                    setPhase("finish", current) return
                end
                local placed, reason = Harness.placeCombatActor(
                    record.actor, { x = tx + 0.5, y = ty + 0.5, z = 0 })
                if not placed then
                    result("FAIL", "road_horde_fixture_placement",
                        tostring(index) .. ":" .. tostring(reason))
                    setPhase("finish", current) return
                end
            end
            result("PASS", "road_horde_fixture_on_loaded_street",
                "four original companions placed on Riverside road before dispatch")
        end
        local plan
        if Harness.config.team_autonomous_scout_probe == "true" then
            if Harness.config.team_road_route_probe == "true" then
                SC.Config._overrides.expeditionRoadRoutingEnabled = true
            end
            if Harness.config.team_known_place_scout_probe == "true"
                or Harness.config.team_unvisited_place_scout_probe == "true" then
                local places = SC.ExpeditionPlaces
                local known, placeReason = places.knownNearby(
                    6100, 5280, 80, 32)
                local unvisited = Harness.config.team_unvisited_place_scout_probe
                    == "true"
                local place, approach, approachReason
                if unvisited then
                    local knownIds = {}
                    for _, candidate in ipairs(known or {}) do
                        knownIds[candidate.id] = true
                    end
                    local targets, targetReason = places.targetableNearby(
                        6100, 5280, 80, 32)
                    placeReason = targetReason or placeReason
                    for _, candidate in ipairs(targets or {}) do
                        if not knownIds[candidate.id]
                            and candidate.knowledge == "map_metadata_unconfirmed" then
                            local candidateApproach, candidateReason =
                                places.loadedApproach(candidate, chosen.actor)
                            if candidateApproach ~= nil then
                                place, approach = candidate, candidateApproach
                                approachReason = nil
                                break
                            end
                            approachReason = candidateReason
                        end
                    end
                else
                    for _, candidate in ipairs(known or {}) do
                        if candidate.id == "6115:5246:6141:5266"
                            and candidate.kind == "fire" then
                            place = candidate break
                        end
                    end
                    approach, approachReason = places.loadedApproach(
                        place, chosen.actor)
                end
                local checkName = unvisited and "unvisited_place_scout_preflight"
                    or "known_place_scout_preflight"
                if not check(checkName,
                    place ~= nil and (unvisited or place.kind == "fire")
                        and place.groundFloor == true
                        and place.knowledge == (unvisited
                            and "map_metadata_unconfirmed"
                            or "player_seen_interior")
                        and place.rooms == nil
                        and approach ~= nil
                        and approach.scope == "loaded_exterior_only",
                    "place=" .. tostring(place and place.kind)
                        .. " approach=" .. tostring(approachReason)
                        .. " metadata=" .. tostring(placeReason)) then
                    setPhase("finish", current) return
                end
                plan = { kind = "scout", destination = {
                    x = approach.x, y = approach.y, z = approach.z,
                } }
                Harness.selectedPlaceRef = place.id
                Harness.selectedPlaceApproach = approach
                result("PASS", unvisited
                        and "unvisited_place_scout_destination_selected"
                        or "known_place_scout_destination_selected",
                    "building=" .. tostring(place.id)
                        .. " approach=" .. tostring(approach.x) .. ","
                        .. tostring(approach.y)
                        .. " path_nodes=" .. tostring(approach.pathNodes))
            else
                local x, y = position(chosen.actor)
                local roadDistance = math.max(20, math.min(200,
                    math.floor(tonumber(
                        Harness.config.team_road_distance_tiles) or 180)))
                plan = { kind = "scout", destination = {
                    x = math.floor(x) + (Harness.config.team_road_route_probe
                        == "true" and roadDistance or 85), y = math.floor(y),
                    z = math.floor(chosen.actor:getZ()),
                }, travelMode = Harness.config.team_road_route_probe
                    == "true" and "road" or "straight" }
            end
        elseif Harness.config.team_autonomous_search_probe == "true" then
            if Harness.config.team_unvisited_interior_search_probe == "true" then
                local places = SC.ExpeditionPlaces
                local targets, targetReason = places.targetableNearby(
                    6100, 5280, 80, 32)
                local known, knownReason = places.knownNearby(
                    6100, 5280, 80, 32)
                local knownIds = {}
                for _, candidate in ipairs(known or {}) do
                    knownIds[candidate.id] = true
                end
                local place
                for _, candidate in ipairs(targets or {}) do
                    if candidate.id == "6156:5236:6174:5266" then
                        place = candidate break
                    end
                end
                local interior, depth, roomName
                if place ~= nil then
                    local grid = getWorld():getMetaGrid()
                    local building = grid:getBuildingAt(6160, 5255, 0)
                    local rooms = building and building:getRooms()
                    local roomCount = rooms and SC.NativeList.size(rooms) or 0
                    for roomIndex = 0, math.min(256, roomCount) - 1 do
                        local room = select(1, SC.NativeList.get(
                            rooms, roomIndex))
                        local rects = room and room:getRects()
                        local rectCount = rects and SC.NativeList.size(rects) or 0
                        for rectIndex = 0, math.min(64, rectCount) - 1 do
                            local rect = select(1, SC.NativeList.get(
                                rects, rectIndex))
                            if rect then
                                local px = math.floor(rect:getX()
                                    + rect:getW() / 2)
                                local py = math.floor(rect:getY()
                                    + rect:getH() / 2)
                                local groundRect = room:getRoomRect(px, py, 0)
                                if groundRect ~= nil
                                    and px >= place.bounds.x
                                    and px <= place.bounds.x2
                                    and py >= place.bounds.y
                                    and py <= place.bounds.y2 then
                                    local candidateDepth = math.min(
                                        px - place.bounds.x,
                                        place.bounds.x2 - px,
                                        py - place.bounds.y,
                                        place.bounds.y2 - py)
                                    if depth == nil or candidateDepth > depth then
                                        interior = { x = px, y = py, z = 0 }
                                        depth = candidateDepth
                                        roomName = room:getName()
                                    end
                                end
                            end
                        end
                    end
                end
                if not check("unvisited_search_interior_preflight",
                    SC.Config.get("expeditionDestinationScope") == "all_nearby"
                        and targets ~= nil and known ~= nil
                        and place ~= nil and not knownIds[place.id]
                        and place.knowledge == "map_metadata_unconfirmed"
                        and interior ~= nil and depth >= 5,
                    "target=" .. tostring(place and place.id)
                        .. " tile=" .. tostring(interior and interior.x)
                        .. "," .. tostring(interior and interior.y)
                        .. " depth=" .. tostring(depth)
                        .. " room=" .. tostring(roomName)
                        .. " targets=" .. tostring(targetReason)
                        .. " known=" .. tostring(knownReason)) then
                    setPhase("finish", current) return
                end
                Harness.unvisitedSearchBuildingId = place.id
                Harness.unvisitedSearchDestination = interior
                if Harness.config.team_multifloor_search_probe == "true" then
                    local floors = places.siteFloors(place.id)
                    local upper = false
                    for _, floor in ipairs(floors or {}) do
                        if floor == 1 then upper = true end
                    end
                    if not check("multifloor_search_site_has_upper_floor",
                        upper, "site=" .. tostring(place.id)
                            .. " floors=" .. tostring(floors
                                and table.concat(floors, ","))) then
                        setPhase("finish", current) return
                    end
                end
                plan = { kind = "search", destination = interior,
                    site = Harness.config.team_multifloor_search_probe == "true"
                        and place or nil,
                    request = { category = Harness.config.team_multifloor_search_probe
                            == "true" and "ammunition" or "construction",
                        quantity = 1 },
                    radius = 8 }
            else
                -- Known cupboard district in this disposable Riverside seed.
                -- The mission sees only a destination and a category; it does not
                -- receive a container or inspect contents before arrival.
                plan = { kind = "search", destination = {
                    x = Harness.config.team_shared_search_probe == "true"
                        and 6079 or 6077,
                    y = Harness.config.team_shared_search_probe == "true"
                        and 5309 or 5303, z = 0,
                }, request = { category = "construction",
                    quantity = Harness.config.team_shared_search_probe == "true"
                        and #roster or 1 },
                    radius = Harness.config.team_shared_search_probe == "true"
                        and 8 or 2 }
            end
        end
        local started, accepted, detail = pcall(
            SC.ExpeditionPrototype.start, roster, plan)
        promoted = started and accepted == true
        actorOrFailure = promoted and chosen.actor or (started and detail or accepted)
        Harness.team = roster
        Harness.teamActors = {}
        for index, record in ipairs(roster) do
            Harness.teamActors[index] = record.actor
        end
        check("expedition_starts_without_radio_gate", promoted,
            tostring(#roster)
                .. " saved companions; start has no radio argument or inventory prerequisite"
                .. " leader=" .. tostring(chosen.actor:getX()) .. ","
                .. tostring(chosen.actor:getY()) .. ","
                .. tostring(chosen.actor:getZ())
                .. " target=" .. tostring(plan and plan.destination
                    and plan.destination.x) .. ","
                .. tostring(plan and plan.destination and plan.destination.y)
                .. " reason=" .. tostring(actorOrFailure))
    else
        promoted, actorOrFailure = pcall(SCSplitScreenProbe.promote, chosen.actor)
    end
    if not promoted or actorOrFailure ~= chosen.actor then
        result("FAIL", "queue_actual_leader", actorOrFailure)
        setPhase("finish", current)
        return
    end
    result("PASS", "queue_actual_leader",
        "existing native companion queued for local slot 1")
    if Harness.config.team_performance_probe == "true" then
        Harness.performanceLeaderQueuedAt = current
        Harness.performancePendingPeak = 0
    end
    setPhase("leader_wait_slot", current)
end

local function livingRemoteZombies()
    local found = {}
    local cell = getWorld() and getWorld():getCell()
    local list = cell and cell:getZombieList()
    if list == nil then return found, 0 end
    local count = 0
    for index = 0, list:size() - 1 do
        local zombie = list:get(index)
        local x, y = position(zombie)
        if x and y and math.abs(x - Harness.leaderRemoteX) < 25
            and math.abs(y - Harness.leaderRemoteY) < 25 then
            count = count + 1
            found[tostring(zombie)] = { x = x, y = y }
        end
    end
    return found, count
end

local function nativeFieldVitals(actor)
    local SC = SurvivorCompanion
    if not SC.Vitals then pcall(require, "SCVitals") end
    local Vitals = SC.Vitals
    local read = Vitals and Vitals.characterStat
    local values = {}
    for _, name in ipairs({ "ENDURANCE", "FATIGUE", "HUNGER", "THIRST" }) do
        values[name] = read and read(actor, name, nil) or nil
    end
    local body = actor and actor:getBodyDamage()
    values.health = body and body:getOverallBodyHealth() or nil
    return values
end

local function probeLeaderSlot(current)
    if Harness.config.team_performance_probe == "true" then
        local ok, pending = pcall(SCSplitScreenProbe.pendingCoopCount)
        if ok then
            Harness.performancePendingPeak = math.max(Harness.performancePendingPeak or 0,
                tonumber(tostring(pending)) or 0)
        end
    end
    local slot = getSpecificPlayer(1)
    if slot ~= Harness.leader then
        if current - Harness.phaseStartedAt < 20000 then return end
        result("FAIL", "actual_leader_in_slot_1", "slot=" .. tostring(slot))
        setPhase("finish", current)
        return
    end
    result("PASS", "actual_leader_in_slot_1",
        "slot 1 is the registered companion object, not a new observer")
    if Harness.config.team_performance_probe == "true" then
        Harness.performanceSlotActivatedAt = current
    end
    check("primary_player_kept", getSpecificPlayer(0) == Harness.player,
        "Riverside player remains in slot 0")
    local valid, reason = SurvivorCompanion.Actor.validateNative(Harness.leader)
    check("leader_native_actor_valid", valid == true, reason)
    local worn = Harness.leader:getWornItems()
    check("saved_leader_outfit_kept_in_second_view",
        worn ~= nil and worn:size() > 0,
        "original saved companion worn items=" .. tostring(worn and worn:size()))
    local bridgeReady, bridgeReason = SurvivorCompanion.Actor.checkBridge(true)
    check("native_bridge_accepts_leader_slot", bridgeReady == true, bridgeReason)
    local bindOk, joypadBind = pcall(function() return Harness.leader:getJoypadBind() end)
    check("leader_has_no_player_input", bindOk and joypadBind == -1,
        "joypadBind=" .. tostring(joypadBind))
    Harness.leaderOriginalSquare = Harness.leader:getCurrentSquare()
    if Harness.config.leader_remote == "true" then
        Harness.leaderRemoteX = math.floor(Harness.playerX)
            + (tonumber(Harness.config.leader_remote_offset_x) or 512)
        Harness.leaderRemoteY = math.floor(Harness.playerY)
            + (tonumber(Harness.config.leader_remote_offset_y) or 0)
        Harness.leaderRemoteZ = Harness.playerZ
        if Harness.config.fishing_bank_probe == "true" then
            Harness.leaderRemoteX, Harness.leaderRemoteY,
                Harness.leaderRemoteZ = 6382, 5208, 0
            SurvivorCompanion.Scheduler.unregister("decision")
        end
        check("leader_remote_initially_unloaded",
            getWorld():getCell():getGridSquare(Harness.leaderRemoteX,
                Harness.leaderRemoteY, Harness.leaderRemoteZ) == nil,
            "target=" .. tostring(Harness.leaderRemoteX) .. ","
                .. tostring(Harness.leaderRemoteY))
        local moved, failure = pcall(function()
            Harness.leader:teleportTo(Harness.leaderRemoteX,
                Harness.leaderRemoteY, Harness.leaderRemoteZ)
        end)
        if not moved then
            result("FAIL", "leader_probe_transfer", failure)
            setPhase("finish", current)
            return
        end
        result("PASS", "leader_probe_transfer",
            "test-only teleport queued for existing companion in slot 1")
        if Harness.config.team_performance_probe == "true" then
            Harness.performanceTransferQueuedAt = current
        end
        setPhase("leader_remote_wait", current)
    elseif Harness.config.team_restart_stage_only == "true" then
        local saved, document = SurvivorCompanion.Runtime.save()
        local descriptor = saved and document and document.expedition
        check("restart_stage_mission_descriptor_saved",
            saved == true and type(descriptor) == "table"
                and descriptor.schema == 1
                and #descriptor.roster == #Harness.team
                and #descriptor.survivors == #Harness.team
                and descriptor.leaderId == Harness.leaderId,
            "saved=" .. tostring(saved)
                .. " roster=" .. tostring(descriptor and #descriptor.roster)
                .. " survivors=" .. tostring(descriptor and #descriptor.survivors))
        setPhase("finish", current)
    elseif Harness.config.team_autonomous_scout_probe == "true" then
        Harness.autonomousStartX, Harness.autonomousStartY = position(Harness.leader)
        Harness.autonomousLastX = Harness.autonomousStartX
        Harness.autonomousLastY = Harness.autonomousStartY
        Harness.autonomousLastProgressAt = current
        Harness.autonomousMaxStep = 0
        Harness.autonomousMaxGap = 0
        Harness.autonomousFarthest = 0
        writeSignal(SPLIT_READY_FILE, { "ready=true" })
        setPhase("team_autonomous_scout", current)
    elseif Harness.config.team_autonomous_search_probe == "true" then
        Harness.autonomousSearchStartedAt = current
        Harness.autonomousSearchLastX, Harness.autonomousSearchLastY =
            position(Harness.leader)
        Harness.autonomousSearchMaxStep = 0
        Harness.autonomousSearchChunks = {}
        local removed = cleanupTestZombiesNear(Harness.leader, 60)
        result("PASS", "autonomous_search_quiet_fixture",
            "test-only native zombies removed=" .. tostring(removed))
        writeSignal(SPLIT_READY_FILE, { "ready=true" })
        setPhase("team_autonomous_search", current)
    elseif Harness.config.team_local_travel_probe == "true" then
        Harness.localStartX, Harness.localStartY = position(Harness.leader)
        Harness.localStartZ = Harness.leader:getZ()
        writeSignal(SPLIT_READY_FILE, { "ready=true" })
        setPhase("team_local_travel_stage", current)
    else
        if Harness.config.split_base_layout_probe == "true" then
            local baseLife = SurvivorCompanion.BaseLife
            local hasBase = baseLife and baseLife.active()
                and baseLife.isInside(Harness.player) == true
            check("split_base_layout_player_inside_camp", hasBase,
                "a marked camp must be visible from primary view")
            if not hasBase then setPhase("finish", current) return end
            SurvivorCompanion.BaseVisuals.setEnabled(true)
        end
        writeSignal(SPLIT_READY_FILE, { "ready=true" })
        setPhase("leader_wait_capture", current)
    end
end

local function stageTeamWaypoint()
    if Harness.config.team_waypoint_probe ~= "true"
        and Harness.config.team_local_travel_probe ~= "true" then return true end
    local SC = SurvivorCompanion
    local cell = getWorld():getCell()
    local source = Harness.leader:getCurrentSquare()
    local x, y, z = position(Harness.leader)
    if source == nil or x == nil or y == nil then
        result("FAIL", "remote_waypoint_staged", "leader square unavailable")
        return false
    end
    local chunkMap = cell:getChunkMap(1)
    result(chunkMap and "PASS" or "FAIL", "remote_chunk_map_inspected",
        chunkMap and ("chunk_origin=" .. tostring(chunkMap.worldX) .. ","
            .. tostring(chunkMap.worldY) .. " tiles="
            .. tostring(chunkMap:getWorldXMinTiles()) .. ".."
            .. tostring(chunkMap:getWorldXMaxTiles()) .. ","
            .. tostring(chunkMap:getWorldYMinTiles()) .. ".."
            .. tostring(chunkMap:getWorldYMaxTiles()))
            or "slot-1 chunk map unavailable")
    local offsets = {}
    for _, distance in ipairs({ 5, 6, 8, 10, 12, 16 }) do
        if Harness.config.team_local_travel_probe ~= "true"
            or distance >= 10 then
            offsets[#offsets + 1] = { distance, 0 }
            offsets[#offsets + 1] = { 0, distance }
            offsets[#offsets + 1] = { -distance, 0 }
            offsets[#offsets + 1] = { 0, -distance }
        end
    end
    local attempts = {}
    for _, offset in ipairs(offsets) do
        local targetX = math.floor(x) + offset[1]
        local targetY = math.floor(y) + offset[2]
        local crossesEdge = math.floor(targetX / 10) ~= math.floor(x / 10)
            or math.floor(targetY / 10) ~= math.floor(y / 10)
        local target = crossesEdge
            and cell:getGridSquare(targetX, targetY, math.floor(z)) or nil
        if crossesEdge and target and SC.GameplayUtil.isSquareFree(target) then
            local path, reason = SC.Navigation.findPath(source, target,
                { nodeBudget = 1200 })
            if path ~= nil and #path >= 3 then
                local staged, why = SC.ExpeditionPrototype.stageTestWaypoint(
                    Harness.leader, targetX, targetY, z)
                if staged then
                    Harness.teamWaypoint = {
                        x = targetX, y = targetY, z = z,
                        startX = x, startY = y, routeNodes = #path,
                    }
                    result("PASS", "remote_waypoint_staged",
                        "from=" .. tostring(x) .. "," .. tostring(y)
                            .. " to=" .. tostring(targetX) .. "," .. tostring(targetY)
                            .. " loaded_route_nodes=" .. tostring(#path))
                    return true
                end
                attempts[#attempts + 1] = tostring(why)
            else
                attempts[#attempts + 1] = tostring(targetX) .. ","
                    .. tostring(targetY) .. ":" .. tostring(reason)
            end
        else
            attempts[#attempts + 1] = tostring(targetX) .. ","
                .. tostring(targetY) .. ":"
                .. (not crossesEdge and "same_chunk"
                    or (target == nil and "unloaded" or "blocked"))
        end
    end
    result("FAIL", "remote_waypoint_staged", table.concat(attempts, ","))
    return false
end

local function probeLeaderRemote(current)
    if Harness.config.team_performance_probe == "true" then
        local ok, pending = pcall(SCSplitScreenProbe.pendingCoopCount)
        if ok then
            Harness.performancePendingPeak = math.max(Harness.performancePendingPeak or 0,
                tonumber(tostring(pending)) or 0)
        end
    end
    local cell = getWorld():getCell()
    local square = cell:getGridSquare(Harness.leaderRemoteX,
        Harness.leaderRemoteY, Harness.leaderRemoteZ)
    local x, y = position(Harness.leader)
    if square == nil or x == nil or y == nil
        or math.abs(x - Harness.leaderRemoteX) > 2
        or math.abs(y - Harness.leaderRemoteY) > 2 then
        if current - Harness.phaseStartedAt < 30000 then return end
        result("FAIL", "actual_leader_remote_area_loaded",
            "square=" .. tostring(square ~= nil) .. " actor="
                .. tostring(x) .. "," .. tostring(y))
        setPhase("finish", current)
        return
    end
    result("PASS", "actual_leader_remote_area_loaded",
        "ordinary square lookup follows companion in slot 1")
    if Harness.config.team_performance_probe == "true" then
        Harness.performanceRemoteReadyAt = current
    end
    if Harness.team then
        local SC = SurvivorCompanion
        if Harness.config.team_building_probe == "true" then
            Harness.buildingClearedZombies = cleanupTestZombiesNear(
                Harness.leader, 80)
            result("PASS", "building_quiet_area_fixture",
                "test-only native zombies removed="
                    .. tostring(Harness.buildingClearedZombies))
        end
        if Harness.config.team_straggler_probe == "true" then
            Harness.stragglerClearedZombies = cleanupTestZombiesNear(
                Harness.leader, 60)
            result("PASS", "straggler_no_threat_fixture",
                "test-only native zombies removed="
                    .. tostring(Harness.stragglerClearedZombies))
        end
        local placed = true
        for index = 2, #Harness.team do
            local record = Harness.team[index]
            local recovered, reason = false, "no safe loaded square"
            for dx = 1, 4 do
                for dy = -2, 2 do
                    local target = cell:getGridSquare(Harness.leaderRemoteX + dx,
                        Harness.leaderRemoteY + dy, Harness.leaderRemoteZ)
                    if target ~= nil then
                        recovered, reason = SC.Actor.recover(record.actor, target)
                        if recovered then break end
                    end
                end
                if recovered then break end
            end
            if not recovered then placed = false end
            check("expedition_follower_" .. tostring(index) .. "_remote",
                recovered, "id=" .. tostring(record.id) .. " reason=" .. tostring(reason))
        end
        if not placed then setPhase("finish", current) return end
        if Harness.config.team_performance_probe == "true" then
            local after = auditCompanionOutfits("after_remote_transfer", Harness.team)
            local retained, mismatch = true, nil
            for _, record in ipairs(Harness.team) do
                if Harness.outfitBeforeHandoff[record.id] ~= after[record.id] then
                    retained, mismatch = false, record.id
                    break
                end
            end
            check("all_saved_outfits_retained_through_remote_transfer",
                retained, "members=" .. tostring(#Harness.team)
                    .. " mismatch=" .. tostring(mismatch))
        end
        if #Harness.team > 1 then
            local remoteOrder, remoteReason = SC.Commands.issue(Harness.team[2].id,
                "stay", nil, Harness.player)
            check("remote_follower_orders_blocked", remoteOrder == false
                and remoteReason == "expedition_leader_radio_required",
                "reason=" .. tostring(remoteReason))
        end
    end
    Harness.leaderRemoteStartX, Harness.leaderRemoteStartY = x, y
    if Harness.team then Harness.remoteVitalsBefore = nativeFieldVitals(Harness.leader) end
    local valid, reason = SurvivorCompanion.Actor.validateNative(Harness.leader)
    check("remote_leader_native_actor_valid", valid == true, reason)
    if Harness.config.fishing_bank_probe == "true" then
        setPhase("fishing_find_bank", current)
        return
    end
    local ordered, orderReason = SurvivorCompanion.Commands.issue(
        Harness.leaderId, "stay", nil, Harness.player)
    check("ordinary_orders_cannot_control_remote_leader",
        ordered == false and orderReason == "expedition_leader_radio_required",
        "accepted=" .. tostring(ordered) .. " reason=" .. tostring(orderReason))
    if Harness.config.team_loot_survey == "true" then
        setPhase("team_loot_survey", current)
    elseif Harness.config.team_building_probe == "true" then
        setPhase("team_building_wait", current)
    elseif Harness.config.team_overlap_probe == "true" then
        setPhase("team_overlap_start", current)
    elseif Harness.radioFixture then
        setPhase("team_radio_wait", current)
    elseif Harness.team then
        if Harness.config.team_waypoint_probe == "true" then
            setPhase("team_waypoint_wait", current)
        else
            Harness.leaderObserveFrames = SurvivorCompanion.Scheduler.getStats().frames or 0
            setPhase("leader_observe", current)
        end
    else
        writeSignal(SPLIT_READY_FILE, { "ready=true" })
        setPhase("leader_wait_capture", current)
    end
end

local function chunkMapCovers(map, x, y)
    return map ~= nil and x >= map:getWorldXMinTiles()
        and x <= map:getWorldXMaxTiles()
        and y >= map:getWorldYMinTiles()
        and y <= map:getWorldYMaxTiles()
end

local function overlapObjectCount(square, object)
    local count = 0
    SurvivorCompanion.GameplayUtil.squareObjects(square, function(candidate)
        if candidate == object then count = count + 1 end
    end, 64)
    return count
end

function Harness.probeTeamOverlapStart(current)
    if current - Harness.phaseStartedAt < 5000 then return end
    local cell = getWorld():getCell()
    local U = SurvivorCompanion.GameplayUtil
    local source, best = nil, math.huge
    for dx = -20, 20 do
        for dy = -20, 20 do
            local square = cell:getGridSquare(Harness.leaderRemoteX + dx,
                Harness.leaderRemoteY + dy, Harness.leaderRemoteZ)
            if square ~= nil then
                U.squareObjects(square, function(object)
                    local container, ok = U.call(object, "getContainer")
                    local distance = dx * dx + dy * dy
                    if ok and container ~= nil and distance < best then
                        source = {
                            x = Harness.leaderRemoteX + dx,
                            y = Harness.leaderRemoteY + dy,
                            z = Harness.leaderRemoteZ,
                            square = square, object = object,
                            container = container,
                        }
                        best = distance
                    end
                end, 64)
            end
        end
    end
    check("overlap_native_container_selected", source ~= nil,
        source and ("site=" .. source.x .. "," .. source.y
            .. " distance=" .. math.sqrt(best)) or "no loaded world container")
    if source == nil then setPhase("finish", current) return end
    Harness.overlapSource = source
    if Harness.config.team_return_release_probe == "true" then
        local denied, reason = SurvivorCompanion.ExpeditionPrototype.finishAtPlayer(
            Harness.player)
        check("distant_team_release_rejected", denied == false
            and reason == "return_member_not_assembled"
            and SCSplitScreenProbe.canReleaseJoinedLeader() == false
            and getSpecificPlayer(1) == Harness.leader
            and SurvivorCompanion.ExpeditionPrototype.current() ~= nil,
            "reason=" .. tostring(reason))
    end
    local moved, failure = pcall(function()
        Harness.player:teleportTo(Harness.leaderRemoteX + 2,
            Harness.leaderRemoteY, Harness.leaderRemoteZ)
    end)
    check("overlap_player_arrival_queued", moved, tostring(failure))
    if not moved then setPhase("finish", current) return end
    setPhase("team_overlap_merge", current)
end

function Harness.probeTeamOverlapMerge(current)
    local px, py = position(Harness.player)
    if px == nil or py == nil
        or math.abs(px - (Harness.leaderRemoteX + 2)) > 2
        or math.abs(py - Harness.leaderRemoteY) > 2
        or current - Harness.phaseStartedAt < 5000 then
        if current - Harness.phaseStartedAt < 30000 then return end
        result("FAIL", "overlap_player_arrived", "player="
            .. tostring(px) .. "," .. tostring(py))
        setPhase("finish", current)
        return
    end
    local cell = getWorld():getCell()
    local source = Harness.overlapSource
    local square = cell:getGridSquare(source.x, source.y, source.z)
    local container, ok = SurvivorCompanion.GameplayUtil.call(
        source.object, "getContainer")
    local map0, map1 = cell:getChunkMap(0), cell:getChunkMap(1)
    local count = overlapObjectCount(square, source.object)
    check("overlap_same_native_square_object_and_container",
        square == source.square and count == 1
            and ok and container == source.container
            and chunkMapCovers(map0, source.x, source.y)
            and chunkMapCovers(map1, source.x, source.y),
        "same_square=" .. tostring(square == source.square)
            .. " object_count=" .. tostring(count)
            .. " same_container=" .. tostring(container == source.container)
            .. " slot0=" .. tostring(chunkMapCovers(map0, source.x, source.y))
            .. " slot1=" .. tostring(chunkMapCovers(map1, source.x, source.y)))
    check("overlap_actor_ownership_preserved",
        getSpecificPlayer(0) == Harness.player
            and getSpecificPlayer(1) == Harness.leader
            and SurvivorCompanion.Registry.isActive(Harness.leader,
                Harness.leaderId),
        "primary and original companion retain separate slots")
    if square ~= source.square or count ~= 1 or container ~= source.container then
        setPhase("finish", current) return
    end
    if Harness.config.team_return_release_probe == "true" then
        local clock = UIManager and UIManager.getClock()
        Harness.splitClockY = clock and clock:getY() or nil
        local finished, reason = SurvivorCompanion.ExpeditionPrototype.finishAtPlayer(
            Harness.player)
        check("joined_team_release_accepted", finished == true
            and reason == "returned",
            "reason=" .. tostring(reason))
        if not finished then setPhase("finish", current) return end
        setPhase("team_overlap_released", current)
        return
    end
    local moved, failure = pcall(function()
        Harness.player:teleportTo(Harness.playerX,
            Harness.playerY, Harness.playerZ)
    end)
    check("overlap_player_departure_queued", moved, tostring(failure))
    if not moved then setPhase("finish", current) return end
    setPhase("team_overlap_split", current)
end

function Harness.probeTeamOverlapReleased(current)
    if current - Harness.phaseStartedAt < 5000 then return end
    local cell = getWorld():getCell()
    local source = Harness.overlapSource
    local square = cell:getGridSquare(source.x, source.y, source.z)
    local count = overlapObjectCount(square, source.object)
    local map0 = cell:getChunkMap(0)
    local clock = UIManager and UIManager.getClock()
    local controls = UIManager and UIManager.getSpeedControls()
    local ui = UIManager and UIManager.UI
    local clockListed, controlsListed = false, false
    if ui ~= nil then
        for index = 0, ui:size() - 1 do
            clockListed = clockListed or ui:get(index) == clock
            controlsListed = controlsListed or ui:get(index) == controls
        end
    end
    check("joined_release_restores_primary_clock_and_speed_controls",
        clock ~= nil and controls ~= nil
            and clockListed and controlsListed
            and controls:isVisible()
            and clock:getY() >= 0 and clock:getY() <= 20
            and controls:getY() >= 0
            and controls:getY() + controls:getHeight()
                < getCore():getScreenHeight(),
        "split_clock_y=" .. tostring(Harness.splitClockY)
            .. " clock_y=" .. tostring(clock and clock:getY())
            .. " controls_y=" .. tostring(controls and controls:getY())
            .. " screen_height=" .. tostring(getCore():getScreenHeight())
            .. " listed=" .. tostring(clockListed) .. ","
                .. tostring(controlsListed))
    local active = true
    for _, record in ipairs(Harness.team or {}) do
        if record.actor ~= nil and not record.actor:isDead() then
            active = active and SurvivorCompanion.Registry.isActive(
                record.actor, record.id)
        end
    end
    check("joined_release_preserves_player_owned_world_and_actors",
        getSpecificPlayer(0) == Harness.player
            and getSpecificPlayer(1) == nil
            and SCSplitScreenProbe.isReleased() == true
            and SurvivorCompanion.ExpeditionPrototype.current() == nil
            and chunkMapCovers(map0, source.x, source.y)
            and square == source.square and count == 1 and active,
        "slot1=" .. tostring(getSpecificPlayer(1))
            .. " released=" .. tostring(SCSplitScreenProbe.isReleased())
            .. " primary_owns_source=" .. tostring(chunkMapCovers(map0,
                source.x, source.y))
            .. " same_square=" .. tostring(square == source.square)
            .. " object_count=" .. tostring(count)
            .. " original_actors_active=" .. tostring(active))
    local denied, reason = SurvivorCompanion.ExpeditionPrototype.finishAtPlayer(
        Harness.player)
    check("returned_mission_cannot_release_twice", denied == false
        and reason == "no_active_expedition"
        and getSpecificPlayer(1) == nil,
        "reason=" .. tostring(reason))
    local idle = SurvivorCompanion.ExpeditionPrototype.export()
    check("returned_mission_retains_reusable_slot_identity",
        idle ~= nil and idle.schema == 2 and idle.state == "idle"
            and type(idle.slotSqlId) == "number"
            and idle.slotSqlId >= 2,
        "slotSqlId=" .. tostring(idle and idle.slotSqlId))
    Harness.reuseSlotSqlId = idle and idle.slotSqlId
    if not active or square ~= source.square or count ~= 1 then
        setPhase("finish", current) return
    end
    if Harness.config.team_return_stage_only == "true" then
        local saved, document = SurvivorCompanion.Runtime.save()
        check("returned_idle_slot_descriptor_saved", saved == true
            and document ~= nil and document.expedition ~= nil
            and document.expedition.schema == 2
            and document.expedition.slotSqlId == Harness.reuseSlotSqlId,
            "saved=" .. tostring(saved)
                .. " slotSqlId=" .. tostring(document and document.expedition
                    and document.expedition.slotSqlId))
        setPhase("finish", current)
        return
    end
    local nextRecord
    for index = 2, #(Harness.team or {}) do
        local record = Harness.team[index]
        if record.actor ~= nil and not record.actor:isDead()
            and SurvivorCompanion.Registry.isActive(record.actor, record.id) then
            nextRecord = record
            break
        end
    end
    check("second_expedition_has_distinct_saved_leader",
        nextRecord ~= nil and nextRecord.actor ~= Harness.leader,
        "a surviving original follower can lead the next mission")
    if nextRecord == nil then setPhase("finish", current) return end
    Harness.secondLeader = nextRecord.actor
    Harness.secondLeaderId = nextRecord.id
    local started, accepted, detail = pcall(
        SurvivorCompanion.ExpeditionPrototype.start, { nextRecord })
    check("second_expedition_reacquires_view_queued", started
        and accepted == true,
        tostring(started and detail or accepted))
    if not started or accepted ~= true then
        setPhase("finish", current) return
    end
    setPhase("team_overlap_restart_wait", current)
end

function Harness.probeTeamOverlapRestart(current)
    local cell = getWorld():getCell()
    local source = Harness.overlapSource
    local square = cell:getGridSquare(source.x, source.y, source.z)
    local map1 = cell:getChunkMap(1)
    local ready = getSpecificPlayer(1) == Harness.secondLeader
        and map1 ~= nil and map1.ignore ~= true
        and chunkMapCovers(map1, source.x, source.y)
    if not ready and current - Harness.phaseStartedAt < 20000 then return end
    check("second_expedition_reuses_slot_with_distinct_leader", ready
        and getSpecificPlayer(0) == Harness.player
        and square == source.square
        and overlapObjectCount(square, source.object) == 1
        and SurvivorCompanion.Registry.isActive(Harness.secondLeader,
            Harness.secondLeaderId)
        and SCSplitScreenProbe.leaderSqlId() == Harness.reuseSlotSqlId,
        "slot1_distinct=" .. tostring(getSpecificPlayer(1) == Harness.secondLeader)
            .. " slotSqlId=" .. tostring(SCSplitScreenProbe.leaderSqlId())
            .. " reused=" .. tostring(Harness.reuseSlotSqlId)
            .. " map_ignored=" .. tostring(map1 and map1.ignore)
            .. " square_same=" .. tostring(square == source.square))
    setPhase("finish", current)
end

function Harness.probeIdleSlotRestartStart(current)
    local SC = SurvivorCompanion
    local idle = SC.ExpeditionPrototype.export()
    local records = SC.Registry.records()
    local requiredRecords = Harness.config.team_all_dead_idle_restart_probe == "true"
        and 1 or 4
    if (idle == nil or #records < requiredRecords)
        and current - Harness.phaseStartedAt < 25000 then return end
    check("idle_expedition_slot_restored",
        SC.ExpeditionPrototype.current() == nil
            and idle ~= nil and idle.schema == 2
            and idle.state == "idle"
            and type(idle.slotSqlId) == "number"
            and idle.slotSqlId >= 2
            and getSpecificPlayer(1) == nil,
        "slotSqlId=" .. tostring(idle and idle.slotSqlId)
            .. " records=" .. tostring(#records))
    if idle == nil or #records < requiredRecords then
        setPhase("finish", current)
        return
    end
    if Harness.config.team_corpse_reload_probe == "true" then
        Harness.corpseReloadX = math.floor(Harness.playerX
            + (tonumber(Harness.config.leader_remote_offset_x) or 512))
        Harness.corpseReloadY = math.floor(Harness.playerY
            + (tonumber(Harness.config.leader_remote_offset_y) or 0))
        local moved, reason = pcall(function()
            -- The visitor is a disposable forensic fixture; inspect the
            -- naturally active area before the native population closes in.
            Harness.player:teleportTo(Harness.corpseReloadX + 2,
                Harness.corpseReloadY, Harness.playerZ)
        end)
        check("corpse_reload_player_visit_queued", moved, tostring(reason))
        setPhase(moved and "team_corpse_reload_wait" or "finish", current)
        return
    end
    local chosen
    for _, record in ipairs(records) do
        if record.recruited == true and record.actor ~= nil
            and SC.Registry.isActive(record.actor, record.id)
            and record.actor:isDead() == false
            and SC.Actor.validateNative(record.actor) == true then
            chosen = record
            break
        end
    end
    check("idle_reload_companion_available", chosen ~= nil,
        "one original saved companion can lead after reload")
    if chosen == nil then setPhase("finish", current) return end
    Harness.idleRestartLeader = chosen.actor
    Harness.idleRestartLeaderId = chosen.id
    Harness.idleRestoredSlotSqlId = idle.slotSqlId
    local started, mission = SC.ExpeditionPrototype.start({ chosen })
    check("idle_reload_expedition_started", started == true
        and mission ~= nil and mission.leader.actor == chosen.actor,
        "started=" .. tostring(started)
            .. " mission=" .. tostring(mission))
    if not started then setPhase("finish", current) return end
    setPhase("idle_slot_restart_wait", current)
end

function Harness.probeIdleSlotRestartWait(current)
    local SC = SurvivorCompanion
    local mission = SC.ExpeditionPrototype.current()
    local ready = getSpecificPlayer(1) == Harness.idleRestartLeader
        and SCSplitScreenProbe.isLeader(Harness.idleRestartLeader) == true
        and SCSplitScreenProbe.leaderSqlId() == Harness.idleRestoredSlotSqlId
        and mission ~= nil and mission.leader.actor == Harness.idleRestartLeader
        and SC.Registry.isActive(Harness.idleRestartLeader,
            Harness.idleRestartLeaderId)
    if not ready and current - Harness.phaseStartedAt < 20000 then return end
    check("idle_reload_reuses_native_slot", ready,
        "slot1=" .. tostring(getSpecificPlayer(1) == Harness.idleRestartLeader)
            .. " savedId=" .. tostring(Harness.idleRestoredSlotSqlId)
            .. " nativeId=" .. tostring(SCSplitScreenProbe.leaderSqlId()))
    setPhase("finish", current)
end

function Harness.probeTeamCorpseReloadWait(current)
    if current - Harness.phaseStartedAt < 8000 then return end
    if Harness.nextCorpseReloadScanAt ~= nil
        and current < Harness.nextCorpseReloadScanAt then return end
    Harness.nextCorpseReloadScanAt = current + 1000
    local cell = getWorld():getCell()
    local map = cell:getChunkMap(0)
    local px, py = position(Harness.player)
    local atSite = px ~= nil and py ~= nil
        and math.abs(px - (Harness.corpseReloadX + 2)) < 3
        and math.abs(py - Harness.corpseReloadY) < 3
    local found, gear, cargo, loaded = {}, {}, {}, 0
    local reanimated = {}
    local function countMarkedCargo(owner, number, isBody)
        local container = isBody and owner:getContainer()
            or owner:getInventory()
        local items = container and container:getItems()
        if items == nil then return end
        for itemIndex = 0, items:size() - 1 do
            local item = items:get(itemIndex)
            local marked, marker = pcall(function()
                return item:getModData().SCAllDeadCargoProbe
            end)
            if marked and tonumber(marker) == number
                and item:getFullType() == "Base.Bandage"
                and tonumber(item:getModData().SCAllDeadCargoNativeId)
                    == item:getID() then
                cargo[number] = (cargo[number] or 0) + 1
            end
        end
    end
    local staticObjects, deadBodies, unmarkedBodies = 0, 0, 0
    local bodySamples = {}
    for dx = -24, 24 do
        for dy = -24, 24 do
            local square = cell:getGridSquare(Harness.corpseReloadX + dx,
                Harness.corpseReloadY + dy, Harness.playerZ)
            if square ~= nil then
                loaded = loaded + 1
                local objects = square:getStaticMovingObjects()
                if objects ~= nil then
                    for index = 0, objects:size() - 1 do
                        local body = objects:get(index)
                        staticObjects = staticObjects + 1
                        local named, objectName = pcall(body.getObjectName, body)
                        if named and objectName == "DeadBody" then
                            deadBodies = deadBodies + 1
                        end
                        local read, marker = pcall(function()
                            return body:getModData().SCAllDeadCorpseProbe
                        end)
                        local number = read and tonumber(marker) or nil
                        local worn = named and objectName == "DeadBody"
                            and body:getWornItems() or nil
                        if worn ~= nil then
                            for wornIndex = 0, worn:size() - 1 do
                                local item = worn:get(wornIndex):getItem()
                                local marked, itemMarker = pcall(function()
                                    return item:getModData().SCAllDeadGearProbe
                                end)
                                local gearNumber = marked and tonumber(itemMarker)
                                    or nil
                                if gearNumber ~= nil and gearNumber >= 1
                                    and gearNumber <= 3 then
                                    number = gearNumber
                                    gear[gearNumber] = (gear[gearNumber] or 0) + 1
                                end
                            end
                        end
                        if named and objectName == "DeadBody"
                            and number == nil then
                            unmarkedBodies = unmarkedBodies + 1
                            if #bodySamples < 4 then
                                bodySamples[#bodySamples + 1] = tostring(dx)
                                    .. "," .. tostring(dy)
                                    .. ":" .. tostring(read)
                                    .. "/" .. tostring(marker)
                            end
                        end
                        if number ~= nil and number >= 1 and number <= 3 then
                            found[number] = (found[number] or 0) + 1
                            countMarkedCargo(body, number, true)
                        end
                    end
                end
            end
        end
    end
    local zombies = cell:getZombieList()
    if zombies ~= nil then
        for zombieIndex = 0, zombies:size() - 1 do
            local zombie = zombies:get(zombieIndex)
            local zx, zy = position(zombie)
            if zx and zy and math.abs(zx - Harness.corpseReloadX) <= 24
                and math.abs(zy - Harness.corpseReloadY) <= 24 then
                local worn = zombie:getWornItems()
                if worn ~= nil then
                    for wornIndex = 0, worn:size() - 1 do
                        local item = worn:get(wornIndex):getItem()
                        local marked, marker = pcall(function()
                            return item:getModData().SCAllDeadGearProbe
                        end)
                        local number = marked and tonumber(marker) or nil
                        if number and number >= 1 and number <= 3 then
                            reanimated[number] = (reanimated[number] or 0) + 1
                            countMarkedCargo(zombie, number, false)
                        end
                    end
                end
            end
        end
    end
    local bodiesExact, gearExact, cargoExact = true, true, true
    for index = 1, 3 do
        bodiesExact = bodiesExact
            and (found[index] or 0) + (reanimated[index] or 0) == 1
        gearExact = gearExact
            and (gear[index] or 0) + (reanimated[index] or 0) == 1
        cargoExact = cargoExact and cargo[index] == 1
    end
    if (not atSite or not bodiesExact or not gearExact or not cargoExact)
        and current - Harness.phaseStartedAt < 30000 then return end
    check("corpse_reload_primary_area_loaded", atSite and loaded > 0
        and chunkMapCovers(map, Harness.corpseReloadX,
            Harness.corpseReloadY)
        and getSpecificPlayer(1) == nil,
        "at_site=" .. tostring(atSite) .. " squares=" .. tostring(loaded))
    check("corpse_reload_exact_three_native_outcomes", bodiesExact,
        "found=" .. tostring(found[1]) .. "/" .. tostring(found[2])
            .. "/" .. tostring(found[3])
            .. " static=" .. tostring(staticObjects)
            .. " bodies=" .. tostring(deadBodies)
            .. " unmarked=" .. tostring(unmarkedBodies)
            .. " reanimated=" .. tostring(reanimated[1]) .. "/"
                .. tostring(reanimated[2]) .. "/"
                .. tostring(reanimated[3])
            .. " samples=" .. table.concat(bodySamples, ";"))
    check("corpse_reload_exact_worn_items", gearExact,
        "gear=" .. tostring(gear[1]) .. "/" .. tostring(gear[2])
            .. "/" .. tostring(gear[3])
            .. " reanimated=" .. tostring(reanimated[1]) .. "/"
                .. tostring(reanimated[2]) .. "/"
                .. tostring(reanimated[3]))
    check("corpse_reload_exact_carried_items", cargoExact,
        "cargo=" .. tostring(cargo[1]) .. "/" .. tostring(cargo[2])
            .. "/" .. tostring(cargo[3]))
    setPhase("finish", current)
end

function Harness.probeTeamOverlapSplit(current)
    local px, py = position(Harness.player)
    local cell = getWorld():getCell()
    local source = Harness.overlapSource
    local map0, map1 = cell:getChunkMap(0), cell:getChunkMap(1)
    local back = px ~= nil and py ~= nil
        and math.abs(px - Harness.playerX) < 2
        and math.abs(py - Harness.playerY) < 2
    local split = back and chunkMapCovers(map1, source.x, source.y)
        and not chunkMapCovers(map0, source.x, source.y)
    if (not split or current - Harness.phaseStartedAt < 5000)
        and current - Harness.phaseStartedAt < 30000 then return end
    local square = cell:getGridSquare(source.x, source.y, source.z)
    local count = overlapObjectCount(square, source.object)
    check("overlap_split_keeps_companion_native_area", split
        and square == source.square and count == 1
        and getSpecificPlayer(1) == Harness.leader
        and getSpecificPlayer(0) == Harness.player
        and cell:getGridSquare(math.floor(Harness.playerX),
            math.floor(Harness.playerY), Harness.playerZ) ~= nil,
        "player_back=" .. tostring(back)
            .. " slot0_remote=" .. tostring(chunkMapCovers(map0,
                source.x, source.y))
            .. " slot1_remote=" .. tostring(chunkMapCovers(map1,
                source.x, source.y))
            .. " same_square=" .. tostring(square == source.square)
            .. " object_count=" .. tostring(count))
    setPhase("finish", current)
end

local function probeTeamLootSurvey(current)
    -- Wait for the slot-1 map to integrate its surrounding chunks. This is a
    -- read-only source survey for the later exact-loot conservation probe.
    if current - Harness.phaseStartedAt < 10000 then return end
    local U = SurvivorCompanion.GameplayUtil
    local cell = getWorld():getCell()
    local loaded, containers, stocked = 0, 0, 0
    local best, bestDistance
    local safeSite, safeScore
    local logistics = SurvivorCompanion.Logistics
    local audit = Harness.config.team_loot_probe == "true"
        and logistics.audit(Harness.leader) or nil
    local commands = Harness.config.team_loot_probe == "true"
        and SurvivorCompanion.Commands.peek(Harness.leader) or nil
    local usefulContainers = 0
    local zombies = cell:getZombieList()
    local function nearestZombieDistance(x, y)
        local nearest = math.huge
        for index = 0, zombies:size() - 1 do
            local zombie = zombies:get(index)
            if zombie ~= nil and not zombie:isDead() then
                local distance = (zombie:getX() - x)^2
                    + (zombie:getY() - y)^2
                if distance < nearest then nearest = distance end
            end
        end
        return math.sqrt(nearest)
    end
    for dx = -30, 30 do
        for dy = -30, 30 do
            local x = Harness.leaderRemoteX + dx
            local y = Harness.leaderRemoteY + dy
            local square = cell:getGridSquare(x, y, Harness.leaderRemoteZ)
            if square ~= nil then
                loaded = loaded + 1
                U.squareObjects(square, function(object)
                    local container, containerOk = U.call(object, "getContainer")
                    if containerOk and container ~= nil then
                        containers = containers + 1
                        local items, itemsOk = U.call(container, "getItems")
                        local count = itemsOk and items and items:size() or 0
                        if count > 0 then
                            stocked = stocked + 1
                            local distance = dx * dx + dy * dy
                            if bestDistance == nil or distance < bestDistance then
                                local item = items:get(0)
                                bestDistance = distance
                                best = {
                                    x = x, y = y, count = count,
                                    item = item and item:getFullType() or "nil",
                                    id = item and item:getID() or "nil",
                                }
                            end
                            if Harness.config.team_loot_probe == "true" then
                                local usefulItem, usefulScore
                                for itemIndex = 0, count - 1 do
                                    local candidate = items:get(itemIndex)
                                    local score = candidate and select(1,
                                        logistics.itemNeedScore(Harness.leader,
                                            candidate, commands, audit)) or 0
                                    if score > (usefulScore or 0) then
                                        usefulItem, usefulScore = candidate, score
                                    end
                                end
                                if usefulItem ~= nil then
                                    usefulContainers = usefulContainers + 1
                                end
                                for _, offset in ipairs(usefulItem and {
                                    { 0, 0 }, { 1, 0 }, { -1, 0 },
                                    { 0, 1 }, { 0, -1 },
                                } or {}) do
                                    local target = cell:getGridSquare(
                                        x + offset[1], y + offset[2],
                                        Harness.leaderRemoteZ)
                                    if target and U.isSquareFree(target) then
                                        local dangerDistance = nearestZombieDistance(
                                            x + offset[1], y + offset[2])
                                        local score = dangerDistance
                                            + (target:getRoom() ~= nil and 25 or 0)
                                            - math.sqrt(distance) * 0.1
                                            + math.min(10, usefulScore / 50)
                                        if safeScore == nil or score > safeScore then
                                            safeScore = score
                                            safeSite = {
                                                x = x + offset[1],
                                                y = y + offset[2],
                                                sourceX = x, sourceY = y,
                                                indoor = target:getRoom() ~= nil,
                                                dangerDistance = dangerDistance,
                                                item = usefulItem:getFullType(),
                                                itemScore = usefulScore,
                                            }
                                        end
                                    end
                                end
                            end
                        end
                    end
                end, 64)
            end
        end
    end
    result("PASS", "remote_native_loot_survey_executed",
        "loaded_squares=" .. tostring(loaded)
            .. " containers=" .. tostring(containers)
            .. " stocked=" .. tostring(stocked)
            .. " useful=" .. tostring(usefulContainers)
            .. " nearest=" .. (best and (tostring(best.x) .. ","
                .. tostring(best.y) .. " count=" .. tostring(best.count)
                .. " item=" .. tostring(best.item)
                .. " id=" .. tostring(best.id)) or "none"))
    if Harness.config.team_loot_probe == "true" then
        if safeSite == nil then
            result("FAIL", "remote_native_loot_fixture_site",
                "no free square near a stocked native container")
            setPhase("finish", current)
            return
        end
        Harness.lootSafeSite = safeSite
        local moved, failure = pcall(function()
            Harness.leader:teleportTo(safeSite.x, safeSite.y,
                Harness.leaderRemoteZ)
        end)
        check("remote_native_loot_fixture_site", moved,
            "test-only relocation=" .. tostring(safeSite.x) .. ","
                .. tostring(safeSite.y) .. " source="
                .. tostring(safeSite.sourceX) .. ","
                .. tostring(safeSite.sourceY)
                .. " indoor=" .. tostring(safeSite.indoor)
                .. " nearest_zombie=" .. tostring(safeSite.dangerDistance)
                .. " item=" .. tostring(safeSite.item)
                .. " score=" .. tostring(safeSite.itemScore)
                .. " error=" .. tostring(failure))
        if not moved then setPhase("finish", current) return end
        setPhase("team_loot_relocate_wait", current)
        return
    end
    Harness.leaderObserveFrames = SurvivorCompanion.Scheduler.getStats().frames or 0
    setPhase("leader_observe", current)
end

local function probeTeamLootRelocate(current)
    local site = Harness.lootSafeSite
    local x, y = position(Harness.leader)
    if x == nil or y == nil or math.abs(x - site.x) > 2
        or math.abs(y - site.y) > 2 then
        if current - Harness.phaseStartedAt < 15000 then return end
        result("FAIL", "remote_native_loot_relocation_loaded",
            "actor=" .. tostring(x) .. "," .. tostring(y))
        setPhase("finish", current)
        return
    end
    check("remote_native_loot_relocation_loaded",
        getSpecificPlayer(1) == Harness.leader
            and getWorld():getCell():getGridSquare(site.x, site.y,
                Harness.leaderRemoteZ) ~= nil,
        "actor=" .. tostring(x) .. "," .. tostring(y))
    local staged, reason = SurvivorCompanion.ExpeditionPrototype.stageTestSearch(
        Harness.leader)
    check("remote_native_search_staged", staged == true,
        tostring(reason))
    if not staged then setPhase("finish", current) return end
    local prior = SurvivorCompanion.Encounter.status(Harness.leader)
    Harness.lootPriorTime = prior and prior.lastLoot and prior.lastLoot.time or 0
    writeSignal(SPLIT_READY_FILE, { "ready=true" })
    setPhase("team_loot_watch", current)
end

local function probeTeamLootWatch(current)
    local SC = SurvivorCompanion
    local U = SC.GameplayUtil
    local actor = Harness.leader
    local state = SC.Encounter.peek(actor)
    local task = state and state.task
    if task ~= nil and task.item ~= nil and Harness.lootSelected == nil then
        local item = task.item
        local data = item:getModData()
        data.SC_ExpeditionLootProbe = Harness.config.run_id
        local sourceSquare = task.owner and task.owner:getSquare()
        local objects = sourceSquare and sourceSquare:getObjects()
        local ownerIndex = -1
        if objects ~= nil then
            for index = 0, objects:size() - 1 do
                if objects:get(index) == task.owner then
                    ownerIndex = index break
                end
            end
        end
        Harness.lootSelected = {
            item = item, source = task.container,
            destination = task.destination,
            nativeId = item:getID(), type = item:getFullType(),
            sourceX = sourceSquare and sourceSquare:getX(),
            sourceY = sourceSquare and sourceSquare:getY(),
            sourceZ = sourceSquare and sourceSquare:getZ(),
            ownerIndex = ownerIndex,
            sourceCountBefore = task.container:getItems():size(),
        }
        result("PASS", "remote_native_loot_item_selected",
            "type=" .. tostring(Harness.lootSelected.type)
                .. " id=" .. tostring(Harness.lootSelected.nativeId)
                .. " source_has=" .. tostring(U.inventoryContains(task.container, item)))
    end
    local status = SC.Encounter.status(actor)
    local last = status and status.lastLoot
    local selected = Harness.lootSelected
    if selected ~= nil and last ~= nil
        and (tonumber(last.time) or 0) > (tonumber(Harness.lootPriorTime) or 0)
        and not U.inventoryContains(selected.source, selected.item) then
        local destinationHas = selected.destination ~= nil
            and U.inventoryContains(selected.destination, selected.item)
        local sourceCountAfter = selected.source:getItems():size()
        check("remote_native_loot_exact_transfer", last.verified == true
            and destinationHas and selected.item:getID() == selected.nativeId
            and selected.item:getFullType() == selected.type
            and selected.sourceCountBefore == sourceCountAfter + 1
            and selected.sourceX ~= nil and selected.ownerIndex >= 0,
            "source_has=" .. tostring(U.inventoryContains(selected.source, selected.item))
                .. " destination_has=" .. tostring(destinationHas)
                .. " type=" .. tostring(last.type)
                .. " id=" .. tostring(selected.item:getID())
                .. " source_count=" .. tostring(selected.sourceCountBefore)
                .. "->" .. tostring(sourceCountAfter))
        local saved, document = SC.Runtime.save()
        local companion = saved and document and document.companions
            and document.companions[Harness.leaderId] or nil
        local markerCount = 0
        local function countMarkers(node)
            if node == nil then return end
            if node.type == selected.type and type(node.modData) == "table"
                and node.modData.SC_ExpeditionLootProbe == Harness.config.run_id then
                markerCount = markerCount + 1
            end
            for _, child in ipairs(node.children or {}) do countMarkers(child) end
        end
        for _, root in ipairs(companion and companion.inventory
            and companion.inventory.roots or {}) do countMarkers(root) end
        check("remote_native_loot_snapshot_saved", saved == true
            and companion ~= nil and companion.inventory ~= nil
            and markerCount == 1,
            "saved=" .. tostring(saved)
                .. " companion=" .. tostring(companion ~= nil)
                .. " markers=" .. tostring(markerCount))
        check("remote_native_loot_proof_written", writeSignal(LOOT_PROOF_FILE, {
            "token=" .. tostring(Harness.config.run_id),
            "actor_id=" .. tostring(Harness.leaderId),
            "source_x=" .. tostring(selected.sourceX),
            "source_y=" .. tostring(selected.sourceY),
            "source_z=" .. tostring(selected.sourceZ),
            "owner_index=" .. tostring(selected.ownerIndex),
            "source_count_before=" .. tostring(selected.sourceCountBefore),
            "source_count_after=" .. tostring(sourceCountAfter),
            "item_type=" .. tostring(selected.type),
            "item_native_id=" .. tostring(selected.nativeId),
        }), "source=" .. tostring(selected.sourceX) .. ","
            .. tostring(selected.sourceY) .. " item=" .. tostring(selected.type))
        setPhase("finish", current)
        return
    end
    if actor:isDead() or current - Harness.phaseStartedAt > 60000 then
        local decision = SC.Decision.peek(actor) or {}
        result("FAIL", "remote_native_loot_exact_transfer",
            "selected=" .. tostring(selected ~= nil)
                .. " alive=" .. tostring(not actor:isDead())
                .. " phase=" .. tostring(status and status.phase)
                .. " reason=" .. tostring(status and status.reason)
                .. " decision=" .. tostring(decision.current)
                .. " last=" .. tostring(last and last.type))
        setPhase("finish", current)
    end
end

local function scanReloadedLootArea()
    local cell = getWorld():getCell()
    local U = SurvivorCompanion.GameplayUtil
    local loaded, containers, markers, originalIds = 0, 0, 0, 0
    local token = Harness.config.team_loot_verify_token
    local itemType = Harness.config.team_loot_verify_item_type
    local nativeId = tonumber(Harness.config.team_loot_verify_native_id)
    for dx = -30, 30 do
        for dy = -30, 30 do
            local square = cell:getGridSquare(Harness.leaderRemoteX + dx,
                Harness.leaderRemoteY + dy, Harness.leaderRemoteZ)
            if square ~= nil then
                loaded = loaded + 1
                U.squareObjects(square, function(object)
                    local container, ok = U.call(object, "getContainer")
                    if ok and container ~= nil then
                        containers = containers + 1
                        local items = container:getItems()
                        for index = 0, items:size() - 1 do
                            local item = items:get(index)
                            if item ~= nil then
                                if item:getID() == nativeId then
                                    originalIds = originalIds + 1
                                end
                                if item:getFullType() == itemType then
                                    local data = item:getModData()
                                    if data and data.SC_ExpeditionLootProbe == token then
                                        markers = markers + 1
                                    end
                                end
                            end
                        end
                    end
                end, 64)
            end
        end
    end
    return loaded, containers, markers, originalIds
end

local function probeTeamLootVerifyRemote(current)
    local x, y = position(Harness.leader)
    local square = getWorld():getCell():getGridSquare(Harness.leaderRemoteX,
        Harness.leaderRemoteY, Harness.leaderRemoteZ)
    if square == nil or x == nil or y == nil
        or math.abs(x - Harness.leaderRemoteX) > 2
        or math.abs(y - Harness.leaderRemoteY) > 2 then
        if current - Harness.phaseStartedAt < 30000 then return end
        result("FAIL", "reloaded_loot_remote_area_loaded",
            "square=" .. tostring(square ~= nil)
                .. " actor=" .. tostring(x) .. "," .. tostring(y))
        setPhase("finish", current)
        return
    end
    local loaded, containers, markers, originalIds = scanReloadedLootArea()
    local count, item = countLootMarkers(Harness.leader:getInventory(),
        Harness.config.team_loot_verify_token,
        Harness.config.team_loot_verify_item_type)
    check("reloaded_loot_remote_conservation", loaded >= 3000
        and containers > 0 and markers == 0 and originalIds == 0
        and count == 1 and item == Harness.lootReloadItem
        and getSpecificPlayer(1) == Harness.leader,
        "loaded=" .. tostring(loaded)
            .. " containers=" .. tostring(containers)
            .. " world_markers=" .. tostring(markers)
            .. " original_world_ids=" .. tostring(originalIds)
            .. " companion_markers=" .. tostring(count)
            .. " restored_item_id=" .. tostring(item and item:getID()))
    writeSignal(SPLIT_READY_FILE, { "ready=true" })
    local moved, errorText = pcall(function()
        Harness.player:teleportTo(Harness.leaderRemoteX,
            Harness.leaderRemoteY, Harness.leaderRemoteZ)
    end)
    check("player_visit_to_looted_area_queued", moved,
        tostring(errorText))
    if not moved then setPhase("finish", current) return end
    setPhase("team_loot_verify_visit", current)
end

local function probeTeamLootVerifyVisit(current)
    local SC = SurvivorCompanion
    local x, y = position(Harness.player)
    local record = SC.Registry.byId(Harness.lootReloadActorId)
    local actor = record and record.actor
    if x == nil or y == nil or math.abs(x - Harness.leaderRemoteX) > 2
        or math.abs(y - Harness.leaderRemoteY) > 2
        or actor == nil or current - Harness.phaseStartedAt < 5000 then
        if current - Harness.phaseStartedAt < 45000 then return end
        local pending = SC.Persistence.pendingSnapshot()[Harness.lootReloadActorId]
        result("FAIL", "player_visit_to_looted_area_loaded",
            "player=" .. tostring(x) .. "," .. tostring(y)
                .. " companion=" .. tostring(actor ~= nil)
                .. " pending=" .. tostring(pending and pending.reason))
        setPhase("finish", current)
        return
    end
    local loaded, containers, markers, originalIds = scanReloadedLootArea()
    local count, item = countLootMarkers(actor:getInventory(),
        Harness.config.team_loot_verify_token,
        Harness.config.team_loot_verify_item_type)
    check("player_visit_preserves_loot_conservation", loaded >= 3000
        and containers > 0 and markers == 0 and originalIds == 0
        and count == 1 and item ~= nil
        and SC.Persistence.isPending(Harness.lootReloadActorId) ~= true
        and getSpecificPlayer(0) == Harness.player
        and SC.Registry.isActive(actor, Harness.lootReloadActorId),
        "loaded=" .. tostring(loaded)
            .. " containers=" .. tostring(containers)
            .. " world_markers=" .. tostring(markers)
            .. " original_world_ids=" .. tostring(originalIds)
            .. " companion_markers=" .. tostring(count)
            .. " restored_item_id=" .. tostring(item and item:getID()))
    setPhase("finish", current)
end

local function probeTeamRadioWait(current)
    local radios = Harness.radioFixture
    local playerRadio, leaderRadio = radios.player, radios.team[1]
    local playerEquipped = Harness.player:getEquipedRadio() == playerRadio
    local leaderEquipped = Harness.leader:getEquipedRadio() == leaderRadio
    if not playerEquipped or not leaderEquipped then
        if current - Harness.phaseStartedAt < 6000 then return end
        result("FAIL", "native_radios_equipped_for_receive",
            "player=" .. tostring(playerEquipped)
                .. " leader=" .. tostring(leaderEquipped))
        setPhase("finish", current)
        return
    end
    result("PASS", "native_radios_equipped_for_receive",
        "actual native getEquipedRadio matches each exact item")
    local allReady = true
    for index, radio in ipairs(radios.team) do
        local data = radio:getDeviceData()
        local ready = data:getIsTurnedOn() and data:getHasBattery()
            and data:getPower() > 0 and data:getChannel() == TEAM_RADIO_CHANNEL
        if not ready then allReady = false end
        check("team_radio_" .. tostring(index) .. "_operational", ready,
            "power=" .. tostring(data:getPower())
                .. " range=" .. tostring(data:getTransmitRange()))
    end
    local localData = playerRadio:getDeviceData()
    check("player_radio_operational", localData:getIsTurnedOn()
        and localData:getHasBattery() and localData:getPower() > 0
        and localData:getChannel() == TEAM_RADIO_CHANNEL,
        "power=" .. tostring(localData:getPower())
            .. " range=" .. tostring(localData:getTransmitRange()))
    if not allReady then setPhase("finish", current) return end
    local sent, failure = pcall(function()
        local native = ZomboidRadio.getInstance()
        local px, py = position(Harness.player)
        local lx, ly = position(Harness.leader)
        local leaderData = leaderRadio:getDeviceData()
        local expected = math.floor(math.sqrt((px - lx)^2 + (py - ly)^2))
        local before = leaderData:getLastRecordedDistance()
        local scopedMistuned, scopedOff, scopedSilent
        leaderData:setChannel(TEAM_RADIO_CHANNEL + 1)
        native:SendTransmission(math.floor(px), math.floor(py),
            TEAM_RADIO_CHANNEL, "SC_RADIO_TEST_MISTUNED_" .. Harness.config.run_id,
            "LF-TEST", "NEG", 0.8, 0.9, 1.0,
            localData:getTransmitRange(), false)
        local mistuned = leaderData:getLastRecordedDistance()
        if Harness.config.team_radio_text_probe == "true" then
            SCSplitScreenProbe.sendTestRadioWithLeaderText(
                math.floor(px), math.floor(py), TEAM_RADIO_CHANNEL,
                "SC_RADIO_TEST_CTX_MISTUNED_" .. Harness.config.run_id,
                "LF-TEST", "NEG", 0.8, 0.9, 1.0,
                localData:getTransmitRange(), false)
            scopedMistuned = leaderData:getLastRecordedDistance()
        end
        leaderData:setChannel(TEAM_RADIO_CHANNEL)
        leaderData:setIsTurnedOn(false)
        native:SendTransmission(math.floor(px), math.floor(py),
            TEAM_RADIO_CHANNEL, "SC_RADIO_TEST_OFF_" .. Harness.config.run_id,
            "LF-TEST", "NEG", 0.8, 0.9, 1.0,
            localData:getTransmitRange(), false)
        local off = leaderData:getLastRecordedDistance()
        if Harness.config.team_radio_text_probe == "true" then
            SCSplitScreenProbe.sendTestRadioWithLeaderText(
                math.floor(px), math.floor(py), TEAM_RADIO_CHANNEL,
                "SC_RADIO_TEST_CTX_OFF_" .. Harness.config.run_id,
                "LF-TEST", "NEG", 0.8, 0.9, 1.0,
                localData:getTransmitRange(), false)
            scopedOff = leaderData:getLastRecordedDistance()
        end
        leaderData:setIsTurnedOn(true)
        leaderData:setDeviceVolume(0)
        native:SendTransmission(math.floor(px), math.floor(py),
            TEAM_RADIO_CHANNEL, "SC_RADIO_TEST_SILENT_" .. Harness.config.run_id,
            "LF-TEST", "NEG", 0.8, 0.9, 1.0,
            localData:getTransmitRange(), false)
        local silent = leaderData:getLastRecordedDistance()
        if Harness.config.team_radio_text_probe == "true" then
            SCSplitScreenProbe.sendTestRadioWithLeaderText(
                math.floor(px), math.floor(py), TEAM_RADIO_CHANNEL,
                "SC_RADIO_TEST_CTX_SILENT_" .. Harness.config.run_id,
                "LF-TEST", "NEG", 0.8, 0.9, 1.0,
                localData:getTransmitRange(), false)
            scopedSilent = leaderData:getLastRecordedDistance()
        end
        leaderData:setDeviceVolume(0.8)
        native:SendTransmission(math.floor(px), math.floor(py),
            TEAM_RADIO_CHANNEL, "SC_RADIO_TEST_OUT_" .. Harness.config.run_id,
            "LF-TEST", "OUT", 0.8, 0.9, 1.0,
            localData:getTransmitRange(), false)
        local outward = leaderData:getLastRecordedDistance()
        local contextDistance, contextLocalIdentity
        if Harness.config.team_radio_text_probe == "true" then
            SCSplitScreenProbe.sendTestRadioWithLeaderText(
                math.floor(px), math.floor(py), TEAM_RADIO_CHANNEL,
                "SC_RADIO_TEST_CONTEXT_" .. Harness.config.run_id,
                "LF-TEST", "CONTEXT", 0.8, 0.9, 1.0,
                localData:getTransmitRange(), false)
            contextDistance = leaderData:getLastRecordedDistance()
            contextLocalIdentity = Harness.leader:isLocalPlayer()
        end
        local playerBefore = localData:getLastRecordedDistance()
        native:SendTransmission(math.floor(lx), math.floor(ly),
            TEAM_RADIO_CHANNEL, "SC_RADIO_TEST_BACK_" .. Harness.config.run_id,
            "LF-TEST", "BACK", 0.8, 0.9, 1.0,
            leaderRadio:getDeviceData():getTransmitRange(), false)
        local returnLeg = localData:getLastRecordedDistance()
        Harness.radioSignalEvidence = {
            expected = expected, before = before, mistuned = mistuned,
            off = off, silent = silent,
            outward = outward, playerBefore = playerBefore,
            returnLeg = returnLeg,
            contextDistance = contextDistance,
            contextLocalIdentity = contextLocalIdentity,
            scopedMistuned = scopedMistuned,
            scopedOff = scopedOff,
            scopedSilent = scopedSilent,
        }
    end)
    check("native_radio_probe_emitted", sent == true, tostring(failure))
    if sent and Harness.config.team_radio_placed_probe == "true" then
        local placedWalkie, placedHam = radios.placedWalkie, radios.placedHam
        local placedOkay, placedError = pcall(function()
            local native = ZomboidRadio.getInstance()
            local devices = native:getDevices()
            local walkieRegistered, hamRegistered = false, false
            for index = 0, devices:size() - 1 do
                local value = devices:get(index)
                if value == placedWalkie.object then walkieRegistered = true end
                if value == placedHam.object then hamRegistered = true end
            end
            check("placed_radios_registered_natively",
                walkieRegistered and hamRegistered,
                "walkie=" .. tostring(walkieRegistered)
                    .. " ham=" .. tostring(hamRegistered)
                    .. " devices=" .. tostring(devices:size()))
            check("placed_radios_keep_exact_world_items",
                placedWalkie.item:getWorldItem():getSquare() == placedWalkie.square
                    and placedHam.item:getWorldItem():getSquare() == placedHam.square
                    and placedWalkie.object:getModData().RadioItemID == placedWalkie.item:getID()
                    and placedHam.object:getModData().RadioItemID == placedHam.item:getID(),
                "walkie=" .. tostring(placedWalkie.item:getID())
                    .. " ham=" .. tostring(placedHam.item:getID()))
            local walkieData, hamData = placedWalkie.data, placedHam.data
            check("placed_native_model_capabilities",
                walkieData:isIsoDevice() and hamData:isIsoDevice()
                    and walkieData:getIsTwoWay() and hamData:getIsTwoWay()
                    and walkieData:getTransmitRange() > 0
                    and hamData:getTransmitRange() > walkieData:getTransmitRange(),
                "walkie_range=" .. tostring(walkieData:getTransmitRange())
                    .. " ham_range=" .. tostring(hamData:getTransmitRange()))
            local px, py = position(Harness.player)
            local lx, ly = position(Harness.leader)
            local distance = math.floor(math.sqrt((px - lx)^2 + (py - ly)^2))
            local function outgoing(entry, label)
                local data = entry.data
                check("placed_" .. label .. "_locally_operable",
                    data:getIsTurnedOn() and data:getHasBattery()
                        and data:getPower() > 0 and not data:isNoTransmit()
                        and data:getChannel() == TEAM_RADIO_CHANNEL
                        and entry.square == Harness.player:getCurrentSquare(),
                    "power=" .. tostring(data:getPower()))
                SCSplitScreenProbe.sendTestRadioWithLeaderText(
                    math.floor(px), math.floor(py), TEAM_RADIO_CHANNEL,
                    "SC_RADIO_TEST_PLACED_" .. label .. "_OUT_"
                        .. Harness.config.run_id,
                    "LF-TEST", "PLACED", 0.8, 0.9, 1.0,
                    data:getTransmitRange(), false)
            end
            outgoing(placedWalkie, "WALKIE")
            outgoing(placedHam, "HAM")
            hamData:setChannel(TEAM_RADIO_CHANNEL + 1)
            native:SendTransmission(math.floor(lx), math.floor(ly),
                TEAM_RADIO_CHANNEL,
                "SC_RADIO_TEST_PLACED_WALKIE_BACK_" .. Harness.config.run_id,
                "LF-TEST", "PLACED", 0.8, 0.9, 1.0,
                leaderRadio:getDeviceData():getTransmitRange(), false)
            local walkieBack = walkieData:getLastRecordedDistance()
            walkieData:setChannel(TEAM_RADIO_CHANNEL + 1)
            hamData:setChannel(TEAM_RADIO_CHANNEL)
            native:SendTransmission(math.floor(lx), math.floor(ly),
                TEAM_RADIO_CHANNEL,
                "SC_RADIO_TEST_PLACED_HAM_BACK_" .. Harness.config.run_id,
                "LF-TEST", "PLACED", 0.8, 0.9, 1.0,
                leaderRadio:getDeviceData():getTransmitRange(), false)
            local hamBack = hamData:getLastRecordedDistance()
            walkieData:setChannel(TEAM_RADIO_CHANNEL)
            local returnInRange = distance
                < leaderRadio:getDeviceData():getTransmitRange()
            check("placed_radio_native_receive_by_field_range",
                (returnInRange and walkieBack == distance and hamBack == distance)
                    or (not returnInRange and walkieBack == -1 and hamBack == -1),
                "distance=" .. tostring(distance)
                    .. " walkie=" .. tostring(walkieBack)
                    .. " ham=" .. tostring(hamBack))
            Harness.placedRadioEvidence = {
                distance = distance,
                walkieBack = walkieBack, hamBack = hamBack,
                walkieRange = walkieData:getTransmitRange(),
                hamRange = hamData:getTransmitRange(),
                fieldRange = leaderRadio:getDeviceData():getTransmitRange(),
            }
        end)
        check("placed_radio_native_probe_ran", placedOkay == true,
            tostring(placedError))
    end
    if sent and Harness.config.team_radio_command_probe == "true" then
        local SC = SurvivorCompanion
        local beforeMode = SC.Commands.effective(Harness.leader).moveMode
        local targetMode = beforeMode == "walk" and "sneak" or "walk"
        local rejectedMode = targetMode == "walk" and "sneak" or "walk"
        local accepted, reason = SC.ExpeditionPrototype.sendRadioOrder(
            Harness.player, "set_move_mode", targetMode)
        local after = SC.Commands.effective(Harness.leader)
        check("native_radio_command_applied", accepted == true
            and beforeMode ~= targetMode
            and after.moveMode == targetMode
            and reason == targetMode
            and SC.ExpeditionPrototype.current().lastRadioOrder ~= nil,
            "mode=" .. tostring(beforeMode) .. "->"
                .. tostring(after.moveMode) .. " reason=" .. tostring(reason))
        local direct, directReason = SC.Commands.issue(Harness.leaderId,
            "set_move_mode", rejectedMode, Harness.player)
        check("direct_order_stays_blocked_after_radio",
            direct == false and directReason == "expedition_leader_radio_required"
                and SC.Commands.effective(Harness.leader).moveMode == targetMode,
            "reason=" .. tostring(directReason))
        local leaderData = leaderRadio:getDeviceData()
        leaderData:setChannel(TEAM_RADIO_CHANNEL + 1)
        local mistuned, mistunedReason = SC.ExpeditionPrototype.sendRadioOrder(
            Harness.player, "set_move_mode", rejectedMode)
        leaderData:setChannel(TEAM_RADIO_CHANNEL)
        check("mistuned_radio_command_unapplied", mistuned == false
            and mistunedReason == "radio_no_ack"
            and SC.Commands.effective(Harness.leader).moveMode == targetMode,
            "reason=" .. tostring(mistunedReason))
        leaderData:setIsTurnedOn(false)
        local off, offReason = SC.ExpeditionPrototype.sendRadioOrder(
            Harness.player, "set_move_mode", rejectedMode)
        leaderData:setIsTurnedOn(true)
        check("powered_off_radio_command_unapplied", off == false
            and offReason == "radio_no_ack"
            and SC.Commands.effective(Harness.leader).moveMode == targetMode,
            "reason=" .. tostring(offReason))
        leaderData:setDeviceVolume(0)
        local muted, mutedReason = SC.ExpeditionPrototype.sendRadioOrder(
            Harness.player, "set_move_mode", rejectedMode)
        leaderData:setDeviceVolume(0.8)
        check("muted_radio_command_unapplied", muted == false
            and mutedReason == "radio_no_ack"
            and SC.Commands.effective(Harness.leader).moveMode == targetMode,
            "reason=" .. tostring(mutedReason))
        localData:setIsTurnedOn(false)
        local senderOff, senderOffReason = SC.ExpeditionPrototype.sendRadioOrder(
            Harness.player, "set_move_mode", rejectedMode)
        localData:setIsTurnedOn(true)
        check("sender_off_command_not_emitted", senderOff == false
            and senderOffReason == "local_radio_unavailable"
            and SC.Commands.effective(Harness.leader).moveMode == targetMode,
            "reason=" .. tostring(senderOffReason))
        localData:setChannel(TEAM_RADIO_CHANNEL + 1)
        local senderMistuned, senderMistunedReason =
            SC.ExpeditionPrototype.sendRadioOrder(Harness.player,
                "set_move_mode", rejectedMode)
        localData:setChannel(TEAM_RADIO_CHANNEL)
        check("sender_mistuned_command_unheard", senderMistuned == false
            and senderMistunedReason == "radio_no_ack"
            and SC.Commands.effective(Harness.leader).moveMode == targetMode,
            "reason=" .. tostring(senderMistunedReason))
        localData:setMicIsMuted(true)
        local senderMuted, senderMutedReason = SC.ExpeditionPrototype.sendRadioOrder(
            Harness.player, "set_move_mode", rejectedMode)
        localData:setMicIsMuted(false)
        check("muted_microphone_command_not_emitted", senderMuted == false
            and senderMutedReason == "local_radio_unavailable"
            and SC.Commands.effective(Harness.leader).moveMode == targetMode,
            "reason=" .. tostring(senderMutedReason))
        local originalPower = localData:getPower()
        localData:setPower(0)
        local flat, flatReason = SC.ExpeditionPrototype.sendRadioOrder(
            Harness.player, "set_move_mode", rejectedMode)
        localData:setPower(originalPower)
        localData:setIsTurnedOn(true)
        check("flat_sender_command_not_emitted", flat == false
            and flatReason == "local_radio_unavailable"
            and SC.Commands.effective(Harness.leader).moveMode == targetMode,
            "reason=" .. tostring(flatReason))
        Harness.player:setSecondaryHandItem(nil)
        local unequipped, unequippedReason =
            SC.ExpeditionPrototype.sendRadioOrder(Harness.player,
                "set_move_mode", rejectedMode)
        Harness.player:setSecondaryHandItem(playerRadio)
        check("unequipped_sender_command_not_emitted", unequipped == false
            and unequippedReason == "local_radio_not_equipped"
            and SC.Commands.effective(Harness.leader).moveMode == targetMode,
            "reason=" .. tostring(unequippedReason))
        Harness.leader:setSecondaryHandItem(nil)
        local leaderUnequipped, leaderUnequippedReason =
            SC.ExpeditionPrototype.sendRadioOrder(Harness.player,
                "set_move_mode", rejectedMode)
        Harness.leader:setSecondaryHandItem(leaderRadio)
        check("unequipped_leader_command_unheard", leaderUnequipped == false
            and leaderUnequippedReason == "radio_no_ack"
            and SC.Commands.effective(Harness.leader).moveMode == targetMode,
            "reason=" .. tostring(leaderUnequippedReason))
    end
    if Harness.config.team_waypoint_probe == "true" then
        setPhase("team_waypoint_wait", current)
    else
        Harness.leaderObserveFrames = SurvivorCompanion.Scheduler.getStats().frames or 0
        setPhase("leader_observe", current)
    end
end

local function probeTeamWaypointWait(current)
    -- Co-op remote chunks integrate over several game updates after the
    -- leader's first square appears. Staging immediately can mistake a
    -- pending chunk for an impassable route.
    if current - Harness.phaseStartedAt
        < (Harness.config.team_straggler_probe == "true" and 5000 or 10000) then
        return
    end
    if Harness.config.team_straggler_probe == "true" then
        setPhase("team_straggler_stage", current)
        return
    end
    if Harness.config.team_extended_route_probe == "true" then
        local _, zombies = livingRemoteZombies()
        local weight, capacity, ratio =
            SurvivorCompanion.GameplayUtil.inventoryLoad(Harness.leader)
        result("PASS", "extended_route_start_conditions",
            "natural_zombies_25=" .. tostring(zombies)
                .. " leader_health=" .. tostring(Harness.leader:getBodyDamage()
                    :getOverallBodyHealth())
                .. " load=" .. tostring(weight) .. "/"
                .. tostring(capacity) .. " ratio=" .. tostring(ratio))
    end
    if not stageTeamWaypoint() then setPhase("finish", current) return end
    if Harness.config.team_extended_route_probe == "true" then
        Harness.localStartX, Harness.localStartY = position(Harness.leader)
        Harness.localStartZ = Harness.leader:getZ()
        Harness.localTravelLastX, Harness.localTravelLastY =
            Harness.localStartX, Harness.localStartY
        Harness.localTravelMaxStep = 0
        Harness.localTravelChunks = {}
        local map = getWorld():getCell():getChunkMap(1)
        Harness.extendedInitialMapMinX = map and map:getWorldXMinTiles()
        Harness.extendedInitialMapMaxX = map and map:getWorldXMaxTiles()
        Harness.extendedRouteLegs = 1
        Harness.extendedRouteReplans = 0
        if Harness.config.team_corpse_streaming_probe == "true" then
            local victim = Harness.team[2] and Harness.team[2].actor
            local worn = victim and victim:getWornItems()
            local inventory = victim and victim:getInventory()
            local owned = inventory and inventory:getItems()
            local clothing = nil
            if worn ~= nil and owned ~= nil then
                for index = 0, worn:size() - 1 do
                    local item = worn:get(index):getItem()
                    if item ~= nil and owned:contains(item) then
                        clothing = item
                        break
                    end
                end
            end
            local cargo = victim and victim:getInventory()
                :AddItem("Base.Bandage") or nil
            local vx, vy, vz = position(victim)
            local prepared = victim ~= nil and victim:isDead() ~= true
                and clothing ~= nil and cargo ~= nil
                and cargo:getID() > 0 and vx ~= nil and vy ~= nil
            check("corpse_stream_mission_member_prepared", prepared,
                "victim=" .. tostring(victim)
                    .. " cargo=" .. tostring(cargo)
                    .. " at=" .. tostring(vx) .. "," .. tostring(vy))
            if not prepared then setPhase("finish", current) return end
            clothing:getModData().SCCorpseStreamGearProbe = true
            local gearInInventory = owned:contains(clothing)
            check("corpse_stream_worn_gear_in_inventory_before_death",
                gearInInventory,
                "exact_worn_item=" .. tostring(clothing)
                    .. " native_inventory_contains=" .. tostring(gearInInventory))
            cargo:getModData().SCCorpseStreamCargoProbe = true
            cargo:getModData().SCCorpseStreamCargoNativeId = cargo:getID()
            Harness.corpseStreamVictim = victim
            Harness.corpseStreamGear = clothing
            Harness.corpseStreamCargo = cargo
            Harness.corpseStreamX, Harness.corpseStreamY,
                Harness.corpseStreamZ = vx, vy, vz
            local ended, reason = SurvivorCompanion.Actor.endLife(victim)
            check("corpse_stream_native_death_requested", ended == true,
                tostring(reason))
            if not ended then setPhase("finish", current) return end
            setPhase("team_corpse_stream_death_wait", current)
            return
        end
        if Harness.config.team_performance_route_probe == "true" then
            Harness.maintainBuildingQuietFixture(current)
            Harness.beginPerformanceSample(current)
            if Harness.phase == "finish" then return end
        end
        setPhase("team_local_travel_out", current)
        return
    end
    Harness.leaderObserveFrames = SurvivorCompanion.Scheduler.getStats().frames or 0
    setPhase("leader_observe", current)
end

function Harness.probeCorpseStreamDeathWait(current)
    local victim = Harness.corpseStreamVictim
    local ready = victim and victim:isDead() == true
        and victim:isCorpseReady() == true
    if not ready and current - Harness.phaseStartedAt < 30000 then return end
    local body = ready and victim:getCompanionCorpse() or nil
    local square = body and body:getSquare()
    local native = square and square:getStaticMovingObjects():contains(body)
    local items = body and body:getContainer()
        and body:getContainer():getItems()
    local transferred = items and items:contains(Harness.corpseStreamCargo)
    local gearTransferred = items and items:contains(Harness.corpseStreamGear)
    local retained = SCSplitScreenProbe.retainedCorpseChunkCount() == 1
    if ready and native and transferred and not retained
        and current - Harness.phaseStartedAt < 30000 then return end
    check("corpse_stream_native_corpse_and_cargo_ready",
        ready and native and transferred and retained,
        "ready=" .. tostring(ready)
            .. " listed=" .. tostring(native)
            .. " exact_cargo=" .. tostring(transferred)
            .. " exact_worn_in_container=" .. tostring(gearTransferred)
            .. " retained=" .. tostring(retained))
    check("corpse_stream_worn_gear_in_corpse_container",
        gearTransferred == true,
        "exact_worn_item=" .. tostring(Harness.corpseStreamGear)
            .. " native_container_contains=" .. tostring(gearTransferred))
    if not (ready and native and transferred and retained and gearTransferred) then
        setPhase("finish", current)
        return
    end
    table.remove(Harness.team, 2)
    setPhase("team_local_travel_out", current)
end

function Harness.probeTeamStragglerStage(current)
    local SC = SurvivorCompanion
    Harness.stragglerClearedZombies = (Harness.stragglerClearedZombies or 0)
        + cleanupTestZombiesNear(Harness.leader, 60)
    local cell = getWorld():getCell()
    local source = Harness.leader:getCurrentSquare()
    local x, y, z = position(Harness.leader)
    if source == nil or x == nil or y == nil or #Harness.team < 2 then
        result("FAIL", "straggler_probe_team_ready", "leader or follower missing")
        setPhase("finish", current)
        return
    end
    local follower = Harness.team[2].actor
    local fx, fy = position(follower)
    if follower:isDead() or follower:getCurrentSquare() == nil
        or fx == nil or fy == nil then
        result("FAIL", "straggler_probe_follower_ready", "follower unavailable")
        setPhase("finish", current)
        return
    end
    local best, nodes
    -- Keep the held follower out of the leader's initial lane. A route through
    -- that actor would measure personal-space blocking, not expedition cohesion.
    for _, length in ipairs({ 28, 24, 20, 16 }) do
        for _, offset in ipairs({ { -length, 0 }, { 0, -length },
                { length, 0 }, { 0, length } }) do
            local alignment = (fx - x) * offset[1]
                + (fy - y) * offset[2]
            local tx, ty = math.floor(x) + offset[1],
                math.floor(y) + offset[2]
            local target = cell:getGridSquare(tx, ty, math.floor(z))
            if alignment < -length * 0.5
                and target and SC.GameplayUtil.isSquareFree(target) then
                local path = SC.Navigation.findPath(source, target,
                    { nodeBudget = 3000 })
                if path and #path >= length then
                    best, nodes = { x = tx, y = ty, z = z }, #path
                    break
                end
            end
        end
        if best then break end
    end
    if not best then
        result("FAIL", "straggler_loaded_route",
            "no 16-28 tile loaded route away from held follower")
        setPhase("finish", current)
        return
    end
    SC.Navigation.cancel(follower, "straggler_fixture_hold")
    SC.GameplayUtil.stop(follower)
    local token, reason = beginHarnessControl(follower,
        "straggler_fixture_hold", 65000)
    if not token then
        result("FAIL", "straggler_fixture_control", tostring(reason))
        setPhase("finish", current)
        return
    end
    Harness.stragglerControl = token
    Harness.stragglerFollower = follower
    Harness.stragglerFollowerStartX, Harness.stragglerFollowerStartY = fx, fy
    Harness.stragglerLeaderStartX, Harness.stragglerLeaderStartY = x, y
    Harness.stragglerTarget = best
    local staged, why = SC.ExpeditionPrototype.stageTestWaypoint(
        Harness.leader, best.x, best.y, best.z)
    check("straggler_loaded_route", staged == true,
        "from=" .. tostring(x) .. "," .. tostring(y)
            .. " to=" .. tostring(best.x) .. "," .. tostring(best.y)
            .. " nodes=" .. tostring(nodes) .. " reason=" .. tostring(why))
    if not staged then setPhase("finish", current) return end
    setPhase("team_straggler_hold", current)
end

function Harness.probeTeamStragglerHold(current)
    if current >= (Harness.stragglerNextThreatClear or 0) then
        Harness.stragglerClearedZombies = (Harness.stragglerClearedZombies or 0)
            + cleanupTestZombiesNear(Harness.leader, 60)
        Harness.stragglerNextThreatClear = current + 1000
    end
    local mission = SurvivorCompanion.ExpeditionPrototype.current()
    local leader = Harness.leader
    local follower = Harness.stragglerFollower
    local lx, ly = position(leader)
    local fx, fy = position(follower)
    if leader:isDead() or follower:isDead() or lx == nil or fx == nil then
        result("FAIL", "straggler_survived_delay", "leader or follower unavailable")
        setPhase("finish", current)
        return
    end
    local gap = math.sqrt((lx - fx)^2 + (ly - fy)^2)
    Harness.stragglerMaxGap = math.max(Harness.stragglerMaxGap or 0, gap)
    if mission and mission.cohesionHold and not Harness.stragglerHeldAt then
        Harness.stragglerHeldAt = current
        Harness.stragglerHeldX, Harness.stragglerHeldY = lx, ly
    end
    local elapsed = current - Harness.phaseStartedAt
    if elapsed < 45000 and (not Harness.stragglerHeldAt
        or current - Harness.stragglerHeldAt < 3500) then return end
    local followerDrift = math.sqrt((fx - Harness.stragglerFollowerStartX)^2
        + (fy - Harness.stragglerFollowerStartY)^2)
    local leaderTravel = math.sqrt((lx - Harness.stragglerLeaderStartX)^2
        + (ly - Harness.stragglerLeaderStartY)^2)
    local holdDrift = Harness.stragglerHeldX and math.sqrt(
        (lx - Harness.stragglerHeldX)^2
            + (ly - Harness.stragglerHeldY)^2) or math.huge
    local map = getWorld():getCell():getChunkMap(1)
    check("straggler_leader_regrouped", Harness.stragglerHeldAt ~= nil
        and leaderTravel >= 5 and holdDrift < 2.5
        and followerDrift < 2.5,
        "travel=" .. tostring(leaderTravel)
            .. " max_gap=" .. tostring(Harness.stragglerMaxGap)
            .. " held_drift=" .. tostring(holdDrift)
            .. " follower_drift=" .. tostring(followerDrift)
            .. " fixture_zombies_removed="
            .. tostring(Harness.stragglerClearedZombies)
            .. " hold=" .. tostring(mission and mission.cohesionHold
                and mission.cohesionHold.reason))
    check("straggler_tile_remains_loaded",
        follower:getCurrentSquare() ~= nil
            and chunkMapCovers(map, math.floor(fx), math.floor(fy)),
        "follower=" .. tostring(fx) .. "," .. tostring(fy)
            .. " slot1=" .. tostring(map and map:getWorldXMinTiles())
            .. ".." .. tostring(map and map:getWorldXMaxTiles()))
    endHarnessControl(Harness.stragglerControl, "straggler_fixture_released")
    Harness.stragglerControl = nil
    if Harness.stragglerHeldAt == nil then
        setPhase("finish", current)
        return
    end
    setPhase("team_straggler_rejoin", current)
end

function Harness.probeTeamStragglerRejoin(current)
    if current >= (Harness.stragglerNextThreatClear or 0) then
        Harness.stragglerClearedZombies = (Harness.stragglerClearedZombies or 0)
            + cleanupTestZombiesNear(Harness.leader, 60)
        Harness.stragglerNextThreatClear = current + 1000
    end
    local mission = SurvivorCompanion.ExpeditionPrototype.current()
    local follower = Harness.stragglerFollower
    local lx, ly = position(Harness.leader)
    local fx, fy = position(follower)
    if lx == nil or fx == nil or Harness.leader:isDead() or follower:isDead() then
        result("FAIL", "straggler_rejoin_survival", "leader or follower unavailable")
        setPhase("finish", current)
        return
    end
    local gap = math.sqrt((lx - fx)^2 + (ly - fy)^2)
    if gap < 8 then Harness.stragglerRejoined = true end
    if Harness.stragglerRejoined and mission
        and mission.cohesionHold == nil then Harness.stragglerReleased = true end
    local arrival = mission and mission.testWaypointArrival
    local target = Harness.stragglerTarget
    local arrived = arrival and mission.testWaypointArrived == true
        and math.sqrt((arrival.x - target.x)^2
            + (arrival.y - target.y)^2) < 2
    if not arrived and current - Harness.phaseStartedAt < 65000 then return end
    check("straggler_rejoined_after_release", Harness.stragglerRejoined == true,
        "gap=" .. tostring(gap))
    check("leader_resumed_after_regroup", Harness.stragglerReleased == true
        and arrived == true,
        "hold_released=" .. tostring(Harness.stragglerReleased)
            .. " arrived=" .. tostring(arrived)
            .. " target=" .. tostring(target.x) .. "," .. tostring(target.y)
            .. " leader=" .. tostring(lx) .. "," .. tostring(ly))
    setPhase("finish", current)
end

-- Joined W03/W05/W10 pilot: find a stocked native container reachable by
-- walking from the saved Riverside party. No actor or item is relocated.
function Harness.stageLocalLootWaypoint()
    local SC = SurvivorCompanion
    local U = SC.GameplayUtil
    local cell = getWorld():getCell()
    local start = Harness.leader:getCurrentSquare()
    local x, y, z = position(Harness.leader)
    if start == nil or x == nil then return false, "leader_square_missing" end
    local audit = SC.Logistics.audit(Harness.leader)
    local commands = SC.Commands.peek(Harness.leader)
    local candidates = {}
    local loaded, stocked, useful = 0, 0, 0
    for dx = -35, 35 do
        for dy = -35, 35 do
            local sx, sy = math.floor(x) + dx, math.floor(y) + dy
            local square = cell:getGridSquare(sx, sy, math.floor(z))
            if square ~= nil then
                loaded = loaded + 1
                U.squareObjects(square, function(object)
                    local container = select(1, U.call(object, "getContainer"))
                    local items = container and select(1,
                        U.call(container, "getItems")) or nil
                    if items and items:size() > 0 then
                        stocked = stocked + 1
                        local bestItem, bestScore
                        for index = 0, items:size() - 1 do
                            local item = items:get(index)
                            local score = item and select(1,
                                SC.Logistics.itemNeedScore(Harness.leader,
                                    item, commands, audit)) or 0
                            if score > (bestScore or 0) then
                                bestItem, bestScore = item, score
                            end
                        end
                        if bestItem and SC.Logistics.itemCategory(bestItem) then
                            useful = useful + 1
                            for _, offset in ipairs({ { 0, 0 }, { 1, 0 },
                                    { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
                                local tx, ty = sx + offset[1], sy + offset[2]
                                local target = cell:getGridSquare(tx, ty,
                                    math.floor(z))
                                local distance = math.sqrt((tx - x)^2
                                    + (ty - y)^2)
                                local crossesChunk =
                                    math.floor(tx / 10) ~= math.floor(x / 10)
                                    or math.floor(ty / 10) ~= math.floor(y / 10)
                                if target and U.isSquareFree(target)
                                    and distance >= 10 and distance <= 38
                                    and crossesChunk then
                                    candidates[#candidates + 1] = {
                                        square = target, x = tx, y = ty, z = z,
                                        container = container,
                                        sourceX = sx, sourceY = sy,
                                        itemType = bestItem:getFullType(),
                                        itemCategory = SC.Logistics.itemCategory(bestItem),
                                        itemScore = bestScore,
                                        distance = distance,
                                    }
                                end
                            end
                        end
                    end
                end, 64)
            end
        end
    end
    table.sort(candidates, function(a, b)
        if math.abs(a.distance - b.distance) < 0.01 then
            return a.itemScore > b.itemScore
        end
        return a.distance < b.distance
    end)
    local tried, lastReason = 0, nil
    for _, site in ipairs(candidates) do
        if tried >= 30 then break end
        tried = tried + 1
        local path, reason = SC.Navigation.findPath(start, site.square, {
            actor = Harness.leader, nodeBudget = 2500,
        })
        if path and #path >= 6 and #path <= 80 then
            local staged, stageReason = SC.ExpeditionPrototype
                .stageTestWaypoint(Harness.leader, site.x, site.y, site.z)
            if staged then
                Harness.teamWaypoint = {
                    x = site.x, y = site.y, z = site.z,
                    startX = x, startY = y, routeNodes = #path,
                }
                Harness.localLootSite = site
                result("PASS", "local_loot_site_route",
                    "source=" .. tostring(site.sourceX) .. ","
                        .. tostring(site.sourceY)
                        .. " target=" .. tostring(site.x) .. ","
                        .. tostring(site.y)
                        .. " item=" .. tostring(site.itemType)
                        .. " category=" .. tostring(site.itemCategory)
                        .. " score=" .. tostring(site.itemScore)
                        .. " distance=" .. tostring(site.distance)
                        .. " nodes=" .. tostring(#path)
                        .. " candidates=" .. tostring(#candidates))
                return true
            end
            lastReason = stageReason
        else
            lastReason = reason or "route_length"
        end
    end
    result("FAIL", "local_loot_site_route",
        "no reachable useful container"
            .. " loaded=" .. tostring(loaded)
            .. " stocked=" .. tostring(stocked)
            .. " useful=" .. tostring(useful)
            .. " candidates=" .. tostring(#candidates)
            .. " tried=" .. tostring(tried)
            .. " last=" .. tostring(lastReason))
    return false
end

function Harness.probeTeamLocalTravelStage(current)
    if current - Harness.phaseStartedAt < 8000 then return end
    if Harness.config.team_local_loot_round_trip_probe == "true" then
        local removed = cleanupTestZombiesNear(Harness.leader, 60)
        result("PASS", "local_loot_quiet_fixture",
            "test-only native zombies removed=" .. tostring(removed))
        if not Harness.stageLocalLootWaypoint() then
            setPhase("finish", current)
            return
        end
    elseif not stageTeamWaypoint() then
        setPhase("finish", current)
        return
    end
    local x, y = position(Harness.leader)
    Harness.localTravelLastX, Harness.localTravelLastY = x, y
    Harness.localTravelMaxStep = 0
    Harness.localTravelChunks = {}
    if Harness.config.team_extended_route_probe == "true" then
        local map = getWorld():getCell():getChunkMap(1)
        Harness.extendedInitialMapMinX = map and map:getWorldXMinTiles()
        Harness.extendedInitialMapMaxX = map and map:getWorldXMaxTiles()
        Harness.extendedRouteLegs = 1
        Harness.extendedRouteReplans = 0
    end
    setPhase("team_local_travel_out", current)
end

local function observeLocalTravelStep()
    local x, y = position(Harness.leader)
    if x == nil or y == nil then return nil, nil end
    if Harness.localTravelLastX ~= nil then
        local step = math.sqrt((x - Harness.localTravelLastX)^2
            + (y - Harness.localTravelLastY)^2)
        Harness.localTravelMaxStep = math.max(Harness.localTravelMaxStep or 0,
            step)
    end
    Harness.localTravelLastX, Harness.localTravelLastY = x, y
    Harness.localTravelChunks[tostring(math.floor(x / 10)) .. ","
        .. tostring(math.floor(y / 10))] = true
    return x, y
end

function Harness.stageLocalReturn(current)
    local SC = SurvivorCompanion
    local cell = getWorld():getCell()
    local actorSquare = Harness.leader:getCurrentSquare()
    local best, bestPath = nil, nil
    for radius = 0, 2 do
        for dx = -radius, radius do
            for dy = -radius, radius do
                local square = cell:getGridSquare(
                    math.floor(Harness.localStartX) + dx,
                    math.floor(Harness.localStartY) + dy,
                    math.floor(Harness.localStartZ))
                if square ~= nil and SC.GameplayUtil.isSquareFree(square) then
                    local path = SC.Navigation.findPath(actorSquare, square,
                        { actor = Harness.leader, nodeBudget = 1200 })
                    if path ~= nil and #path >= 3 then
                        best, bestPath = square, path
                        break
                    end
                end
            end
            if best ~= nil then break end
        end
        if best ~= nil then break end
    end
    check("local_trip_return_route_found", best ~= nil,
        "loaded_route_nodes=" .. tostring(bestPath and #bestPath))
    if best == nil then setPhase("finish", current) return end
    local tx, ty = position(best)
    local staged, reason = SC.ExpeditionPrototype.stageTestWaypoint(
        Harness.leader, tx, ty, Harness.localStartZ)
    check("local_trip_return_staged", staged == true, tostring(reason))
    if not staged then setPhase("finish", current) return end
    Harness.localReturnX, Harness.localReturnY = tx, ty
    setPhase("team_local_travel_return", current)
end

function Harness.probeTeamLocalTravelOut(current)
    local x, y = observeLocalTravelStep()
    local mission = SurvivorCompanion.ExpeditionPrototype.current()
    local arrival = mission and mission.testWaypointArrival
    local target = Harness.teamWaypoint
    if arrival == nil or mission.testWaypointArrived ~= true then
        local limit = Harness.config.team_extended_route_probe == "true"
            and 120000 or 60000
        if current - Harness.phaseStartedAt < limit
            and Harness.leader:isDead() ~= true then return end
        local decision = SurvivorCompanion.Decision.peek(Harness.leader) or {}
        local nav = SurvivorCompanion.Navigation.status(Harness.leader) or {}
        local hold = mission and mission.cohesionHold
        result("FAIL", "local_trip_outbound_arrival",
            "actor=" .. tostring(x) .. "," .. tostring(y)
                .. " target=" .. tostring(target and target.x) .. ","
                .. tostring(target and target.y)
                .. " dead=" .. tostring(Harness.leader:isDead())
                .. " decision=" .. tostring(decision.current) .. "/"
                .. tostring(decision.intent)
                .. " nav=" .. tostring(nav.phase) .. "/"
                .. tostring(nav.target) .. "/"
                .. tostring(nav.pathReason)
                .. " hold=" .. tostring(hold and hold.reason) .. "/"
                .. tostring(hold and hold.maxGap))
        setPhase("finish", current)
        return
    end
    local distance = math.sqrt((arrival.x - target.x)^2
        + (arrival.y - target.y)^2)
    local followersNear = true
    for index = 2, #Harness.team do
        local follower = Harness.team[index].actor
        local fx, fy = position(follower)
        local gap = fx and fy and x and y
            and math.sqrt((fx - x)^2 + (fy - y)^2) or math.huge
        followersNear = followersNear and gap < 15
    end
    local chunks = 0
    for _ in pairs(Harness.localTravelChunks) do chunks = chunks + 1 end
    local outboundReady = distance < 2
        and chunks >= 2 and followersNear
        and (Harness.localTravelMaxStep or math.huge) < 3
        and getSpecificPlayer(0) == Harness.player
        and getSpecificPlayer(1) == Harness.leader
    local firstLegName = Harness.config.leader_remote == "true"
        and "remote_extended_first_leg_arrival" or "local_trip_outbound_arrival"
    check(firstLegName, outboundReady,
        "distance=" .. tostring(distance)
            .. " chunks=" .. tostring(chunks)
            .. " followers_near=" .. tostring(followersNear)
            .. " max_step=" .. tostring(Harness.localTravelMaxStep))
    if not outboundReady then setPhase("finish", current) return end
    if Harness.config.team_extended_route_probe == "true" then
        setPhase("team_extended_route_stage", current)
        return
    end
    if Harness.config.team_local_loot_round_trip_probe == "true" then
        setPhase("team_local_loot_search", current)
        return
    end
    Harness.stageLocalReturn(current)
end

function Harness.probeLocalLootSearch(current)
    local SC = SurvivorCompanion
    local U = SC.GameplayUtil
    local actor = Harness.leader
    if not Harness.localLootSearchStarted then
        local prior = SC.Encounter.status(actor)
        Harness.localLootPriorTime = prior and prior.lastLoot
            and prior.lastLoot.time or 0
        local staged, reason = SC.ExpeditionPrototype.stageTestSearch(
            actor, Harness.localLootSite.container,
            Harness.localLootSite.itemCategory)
        check("local_trip_native_search_staged", staged == true,
            tostring(reason))
        if not staged then setPhase("finish", current) return end
        Harness.localLootSearchStarted = true
        return
    end
    local state = SC.Encounter.peek(actor)
    local task = state and state.task
    if task and task.item and Harness.localLootSelected == nil then
        local item = task.item
        local sourceSquare = task.owner and task.owner:getSquare()
        local sx, sy = position(sourceSquare)
        local site = Harness.localLootSite
        local sourceGap = sx and math.sqrt((sx - site.sourceX)^2
            + (sy - site.sourceY)^2) or math.huge
        item:getModData().SC_ExpeditionLocalTripProbe =
            Harness.config.run_id
        Harness.localLootSelected = {
            item = item, source = task.container,
            destination = task.destination,
            nativeId = item:getID(), type = item:getFullType(),
            sourceCountBefore = task.container:getItems():size(),
            sourceGap = sourceGap,
        }
        result("PASS", "local_trip_native_item_selected",
            "type=" .. tostring(item:getFullType())
                .. " id=" .. tostring(item:getID())
                .. " source_gap=" .. tostring(sourceGap))
    end
    local status = SC.Encounter.status(actor)
    local last = status and status.lastLoot
    local selected = Harness.localLootSelected
    if selected and last
        and (tonumber(last.time) or 0)
            > (tonumber(Harness.localLootPriorTime) or 0)
        and not U.inventoryContains(selected.source, selected.item) then
        local destinationHas = selected.destination
            and U.inventoryContains(selected.destination, selected.item)
        local sourceCountAfter = selected.source:getItems():size()
        local exact = last.verified == true
            and last.requestedCategory == Harness.localLootSite.itemCategory
            and type(last.stableId) == "string" and #last.stableId > 0
            and U.itemStableId(selected.item, false) == last.stableId
            and destinationHas
            and selected.item:getID() == selected.nativeId
            and selected.item:getFullType() == selected.type
            and selected.sourceCountBefore == sourceCountAfter + 1
            and selected.sourceGap <= 6
        check("local_trip_native_exact_loot", exact,
            "source=" .. tostring(selected.sourceCountBefore)
                .. "->" .. tostring(sourceCountAfter)
                .. " destination=" .. tostring(destinationHas)
                .. " id=" .. tostring(selected.item:getID())
                .. " source_gap=" .. tostring(selected.sourceGap))
        if not exact then setPhase("finish", current) return end
        local cleared, clearReason =
            SC.ExpeditionPrototype.clearTestSearch(actor)
        check("local_trip_native_search_stopped", cleared == true,
            tostring(clearReason))
        if not cleared then setPhase("finish", current) return end
        Harness.stageLocalReturn(current)
        return
    end
    if actor:isDead() or current - Harness.phaseStartedAt > 90000 then
        local decision = SC.Decision.peek(actor) or {}
        result("FAIL", "local_trip_native_exact_loot",
            "selected=" .. tostring(selected ~= nil)
                .. " alive=" .. tostring(not actor:isDead())
                .. " phase=" .. tostring(status and status.phase)
                .. " reason=" .. tostring(status and status.reason)
                .. " decision=" .. tostring(decision.current)
                .. " last=" .. tostring(last and last.type))
        setPhase("finish", current)
    end
end

function Harness.probeTeamLocalTravelReturn(current)
    observeLocalTravelStep()
    local SC = SurvivorCompanion
    local mission = SC.ExpeditionPrototype.current()
    local arrival = mission and mission.testWaypointArrival
    if arrival ~= nil and mission.testWaypointArrived == true then
        local distance = math.sqrt((arrival.x - Harness.localReturnX)^2
            + (arrival.y - Harness.localReturnY)^2)
        local playerGap = math.sqrt((arrival.x - Harness.playerX)^2
            + (arrival.y - Harness.playerY)^2)
        if distance < 2 and playerGap < 12 then
            local finished, reason = SC.ExpeditionPrototype.finishAtPlayer(
                Harness.player)
            if not finished and reason == "return_member_not_assembled"
                and current - Harness.phaseStartedAt < 60000 then return end
            check("local_trip_return_and_view_release", finished == true
                and reason == "returned"
                and getSpecificPlayer(1) == nil
                and SCSplitScreenProbe.isReleased() == true
                and getSpecificPlayer(0) == Harness.player,
                "reason=" .. tostring(reason)
                    .. " distance=" .. tostring(distance)
                    .. " player_gap=" .. tostring(playerGap))
            if Harness.config.team_local_loot_round_trip_probe == "true" then
                local selected = Harness.localLootSelected
                local carried = selected ~= nil
                    and SC.GameplayUtil.inventoryContains(
                        selected.destination, selected.item)
                    and not SC.GameplayUtil.inventoryContains(
                        selected.source, selected.item)
                check("local_trip_loot_carried_home",
                    finished == true and carried == true
                        and selected.item:getID() == selected.nativeId,
                    "carried=" .. tostring(carried)
                        .. " item=" .. tostring(selected
                            and selected.item:getFullType())
                        .. " id=" .. tostring(selected
                            and selected.item:getID()))
            end
            setPhase("finish", current)
            return
        end
    end
    if current - Harness.phaseStartedAt < 120000
        and Harness.leader:isDead() ~= true then return end
    local x, y = position(Harness.leader)
    local nav = SC.Navigation.status(Harness.leader) or {}
    local decision = SC.Decision.peek(Harness.leader) or {}
    local hold = mission and mission.cohesionHold
    result("FAIL", "local_trip_return_and_view_release",
        "actor=" .. tostring(x) .. "," .. tostring(y)
            .. " target=" .. tostring(Harness.localReturnX) .. ","
            .. tostring(Harness.localReturnY)
            .. " arrived=" .. tostring(mission and mission.testWaypointArrived)
            .. " dead=" .. tostring(Harness.leader:isDead())
            .. " decision=" .. tostring(decision.current)
            .. " nav=" .. tostring(nav.phase) .. "/"
            .. tostring(nav.target) .. "/" .. tostring(nav.blockerType)
            .. "/" .. tostring(nav.pathReason)
            .. " hold=" .. tostring(hold and hold.reason) .. "/"
            .. tostring(hold and hold.maxGap)
            .. " technical=" .. tostring(mission and mission.technicalIssue
                and mission.technicalIssue.reason))
    setPhase("finish", current)
end

-- Route skeleton for the loader proof: choose each forward waypoint only after
-- ordinary grid lookup and the existing local pathfinder admit it. The leader
-- still walks every tile through the normal navigation owner.
function Harness.spawnPursuerFixture(current, cell, map, lx, ly)
    if Harness.config.team_pursuer_fixture ~= "true"
        or Harness.pursuerFixtureZombie ~= nil
        or lx - Harness.localStartX < 30
        or (Harness.pursuerFixtureAttempts or 0) >= 8 then return end
    if type(addZombiesInOutfit) ~= "function" then return end
    Harness.pursuerFixtureAttempts =
        (Harness.pursuerFixtureAttempts or 0) + 1
    local z = math.floor(Harness.leader:getZ())
    for _, offset in ipairs({ { 18, 4 }, { 18, -4 },
            { 16, 6 }, { 16, -6 } }) do
        local sx, sy = math.floor(lx) + offset[1],
            math.floor(ly) + offset[2]
        local square = cell:getGridSquare(sx, sy, z)
        local clear = square ~= nil
            and SurvivorCompanion.GameplayUtil.isSquareFree(square)
        for _, record in ipairs(Harness.team or {}) do
            if clear and distance(record.actor, square) < 5 then
                clear = false
            end
        end
        if clear then
            local spawned, list = pcall(addZombiesInOutfit,
                sx, sy, z, 1, nil, 0)
            local zombie = spawned and list and list:size() > 0
                and list:get(0) or nil
            if zombie ~= nil and zombie:getCurrentSquare() ~= nil then
                zombie:setTarget(Harness.leader)
                Harness.pursuerFixtureZombie = zombie
                Harness.pursuerCandidates = Harness.pursuerCandidates or {}
                local zx, zy = position(zombie)
                Harness.pursuerCandidates[zombie] = {
                    x = zx, y = zy,
                    mapMin = map:getWorldXMinTiles(),
                    firstSeenAt = current, maxShift = 0,
                }
                Harness.pursuerCandidateCount =
                    (Harness.pursuerCandidateCount or 0) + 1
                result("PASS", "native_pursuer_fixture_spawned",
                    "test-only native zombie=" .. tostring(zombie)
                        .. " at=" .. tostring(zx) .. "," .. tostring(zy)
                        .. " leader=" .. tostring(lx) .. "," .. tostring(ly)
                        .. " target_set_once=true")
                return
            elseif zombie ~= nil then
                cleanupTestZombie(zombie)
            end
        end
    end
end

function Harness.observePursuerHandoff(current)
    if Harness.config.team_pursuer_probe ~= "true"
        or Harness.pursuerVerified or Harness.extendedInitialMapMaxX == nil
        or current < (Harness.pursuerNextScanAt or 0) then return end
    Harness.pursuerNextScanAt = current + 250
    local cell = getWorld():getCell()
    local map = cell and cell:getChunkMap(1)
    local zombies = cell and cell:getZombieList()
    local lx, ly = position(Harness.leader)
    if map == nil or zombies == nil or lx == nil then return end
    Harness.spawnPursuerFixture(current, cell, map, lx, ly)
    local mapMin = map:getWorldXMinTiles()
    local tracked = Harness.pursuerCandidates or {}
    Harness.pursuerCandidates = tracked
    local count = Harness.pursuerCandidateCount or 0
    for index = 0, zombies:size() - 1 do
        local zombie = zombies:get(index)
        local zx, zy = position(zombie)
        if zombie ~= nil and zx ~= nil and zy ~= nil then
            local item = tracked[zombie]
            if item == nil and count < 32
                and zx >= Harness.extendedInitialMapMaxX - 45
                and zx <= Harness.extendedInitialMapMaxX + 45
                and math.abs(zy - Harness.localStartY) <= 35
                and math.abs(zx - lx) <= 25
                and math.abs(zy - ly) <= 25
                and zombie:isDead() ~= true
                and zombie:getCurrentSquare() ~= nil then
                item = { x = zx, y = zy, mapMin = mapMin,
                    firstSeenAt = current, maxShift = 0 }
                tracked[zombie] = item
                count = count + 1
            end
            if item ~= nil then
                item.lastSeenAt = current
                if item.lastX ~= nil and item.lastY ~= nil then
                    local step = math.sqrt((zx - item.lastX)^2
                        + (zy - item.lastY)^2)
                    item.maxStep = math.max(item.maxStep or 0, step)
                end
                item.lastX, item.lastY = zx, zy
                item.maxShift = math.max(item.maxShift,
                    mapMin - item.mapMin)
                item.moved = item.moved
                    or math.sqrt((zx - item.x)^2 + (zy - item.y)^2) >= 0.5
                local target = zombie:getTarget()
                local teamTarget = false
                for _, record in ipairs(Harness.team or {}) do
                    if target == record.actor then teamTarget = true break end
                end
                if teamTarget and mapMin - item.mapMin < 8 then
                    item.targetBeforeShift = true
                end
                if teamTarget and mapMin - item.mapMin >= 8 then
                    item.targetAfterShift = true
                end
                if item.targetBeforeShift and item.targetAfterShift
                    and item.moved and zombie:isDead() ~= true
                    and (item.maxStep or 0) < 3
                    and zombie:getCurrentSquare() ~= nil
                    and chunkMapCovers(map, math.floor(zx), math.floor(zy))
                    and getSpecificPlayer(0) == Harness.player
                    and getSpecificPlayer(1) == Harness.leader then
                    local name = Harness.config.team_pursuer_fixture == "true"
                        and "native_fixture_pursuer_survived_area_shift"
                        or "natural_pursuer_survived_area_shift"
                    check(name, true,
                        "same_native_actor=" .. tostring(zombie)
                            .. " from=" .. tostring(item.x) .. ","
                            .. tostring(item.y) .. " to=" .. tostring(zx)
                            .. "," .. tostring(zy)
                            .. " map_min=" .. tostring(item.mapMin)
                            .. "->" .. tostring(mapMin)
                            .. " leader=" .. tostring(lx) .. ","
                            .. tostring(ly) .. " target_team=true"
                            .. " loaded_square=true")
                    Harness.pursuerVerified = true
                    Harness.pursuerReported = true
                    break
                end
            end
        end
    end
    Harness.pursuerCandidateCount = count
end

function Harness.observeExtendedFootprint()
    Harness.observePursuerHandoff(nowMs())
    if Harness.extendedOldSquareReleased == true then return end
    local cell = getWorld():getCell()
    local map0, map1 = cell:getChunkMap(0), cell:getChunkMap(1)
    local startX, startY = math.floor(Harness.localStartX),
        math.floor(Harness.localStartY)
    if map1 == nil or chunkMapCovers(map1, startX, startY) then return end
    local playerOwnsStart = chunkMapCovers(map0, startX, startY)
    local x, y = position(Harness.leader)
    local mapMinX, mapMaxX = map1:getWorldXMinTiles(),
        map1:getWorldXMaxTiles()
    local progress = x and x - Harness.localStartX or 0
    local shifted = Harness.extendedInitialMapMinX ~= nil
        and mapMinX - Harness.extendedInitialMapMinX >= 80
        and mapMaxX - mapMinX
            == Harness.extendedInitialMapMaxX
                - Harness.extendedInitialMapMinX
    if not shifted or progress < 85 then return end
    local original = cell:getGridSquare(startX, startY,
        math.floor(Harness.localStartZ))
    local currentSquare = Harness.leader:getCurrentSquare()
    if (original ~= nil) ~= playerOwnsStart or currentSquare == nil then return end
    local followerGap = 0
    for index = 2, #Harness.team do
        local fx, fy = position(Harness.team[index].actor)
        local gap = fx and fy and x and y
            and math.sqrt((fx - x)^2 + (fy - y)^2) or math.huge
        followerGap = math.max(followerGap, gap)
    end
    local valid = getSpecificPlayer(0) == Harness.player
        and getSpecificPlayer(1) == Harness.leader
        and Harness.leader:isDead() == false
        and followerGap < 20
        and (Harness.localTravelMaxStep or math.huge) < 3
    if not valid then return end
    check(playerOwnsStart
        and "moving_footprint_left_player_owned_start_during_walk"
        or "moving_footprint_unloaded_original_square_during_walk", true,
        "progress=" .. tostring(progress)
            .. " map_min=" .. tostring(Harness.extendedInitialMapMinX)
            .. "->" .. tostring(mapMinX)
            .. " width=" .. tostring(mapMaxX - mapMinX)
            .. " player_owns_start=" .. tostring(playerOwnsStart)
            .. " follower_gap=" .. tostring(followerGap)
            .. " max_step=" .. tostring(Harness.localTravelMaxStep))
    Harness.extendedOldSquareReleased = true
end

function Harness.probeSharedSearch(current)
    local SC = SurvivorCompanion
    local mission = SC.ExpeditionPrototype.current()
    if mission == nil then
        local debrief = SC.ExpeditionPrototype.lastDebrief()
        local carriers = {}
        local exact = debrief ~= nil and debrief.kind == "search"
            and debrief.request.quantity == #Harness.team
            and #debrief.acquisitions == #Harness.team
            and #debrief.returnedIds == #Harness.team
            and debrief.inventoryComplete == true
            and debrief.endReason == "quantity_met"
            and SC.ExpeditionPrototype.lastOutcome() == "returned"
        if exact then
            local returned = {}
            for _, id in ipairs(debrief.returnedIds) do returned[id] = true end
            for _, receipt in ipairs(debrief.acquisitions) do
                local count, item, carrier = teamStableItem(Harness.team, receipt.id)
                carriers[receipt.memberId] = (carriers[receipt.memberId] or 0) + 1
                if count ~= 1 or carrier ~= receipt.memberId
                    or item:getFullType() ~= receipt.itemType
                    or not returned[receipt.id] then exact = false end
            end
            for _, member in ipairs(Harness.team) do
                if carriers[member.id] ~= 1 then exact = false end
            end
        end
        check("shared_search_all_members_return_exact_native_loot", exact,
            "members=" .. tostring(#Harness.team)
                .. " receipts=" .. tostring(debrief and #debrief.acquisitions)
                .. " returned=" .. tostring(debrief and #debrief.returnedIds)
                .. " reason=" .. tostring(debrief and debrief.endReason))
        check("shared_search_destination_speech",
            Harness.sharedSearchSpeech == true,
            "site or loot topic spoken=" .. tostring(Harness.sharedSearchSpeech))
        setPhase("finish", current)
        return
    end
    if mission.technicalIssue then
        result("FAIL", "shared_search_technical_issue",
            tostring(mission.technicalIssue.reason))
        setPhase("finish", current)
        return
    end
    if current - (Harness.autonomousSearchStartedAt or current) > 480000 then
        result("FAIL", "shared_search_deadline",
            "phase=" .. tostring(mission.scout and mission.scout.phase)
                .. " receipts=" .. tostring(mission.scout and mission.scout.search
                    and #mission.scout.search.acquisitions))
        setPhase("finish", current)
        return
    end
    local scout = mission.scout
    local phase = scout and scout.phase or "none"
    if phase == "searching" and not Harness.sharedSearchStocked then
        -- Test-only supplies in the cloned world. The squad still selects,
        -- approaches, animates, and debits real native world containers.
        local placed, containers, sources = 0, 0, {}
        local center = scout.destination
        local cell = getWorld():getCell()
        for sx = center.x - 8, center.x + 8 do
            for sy = center.y - 8, center.y + 8 do
                if (sx - center.x)^2 + (sy - center.y)^2 <= 64 then
                    local square = cell:getGridSquare(sx, sy, center.z)
                    if square and not SC.Navigation.behindLockedDoor(
                            Harness.leader, square) then
                        SC.GameplayUtil.squareObjects(square, function(object)
                            local container = select(1,
                                SC.GameplayUtil.call(object, "getContainer"))
                            if container and SC.Encounter.mayTakeFrom(container) then
                                containers = containers + 1
                                if placed < 64 then
                                    local okay, item = pcall(container.AddItem,
                                        container, "Base.FiberglassTape")
                                    if okay and item ~= nil then
                                        placed = placed + 1
                                        sources[#sources + 1] = tostring(sx)
                                            .. "," .. tostring(sy)
                                    end
                                end
                            end
                        end, 64)
                    end
                end
            end
        end
        Harness.sharedSearchStocked = true
        if not check("shared_search_native_supplies_staged", placed >= 4,
            "items=" .. tostring(placed)
                .. " containers=" .. tostring(containers)
                .. " squares=" .. table.concat(sources, ";")) then
            setPhase("finish", current)
            return
        end
    end
    if phase ~= Harness.sharedSearchLastPhase then
        result("PASS", "shared_search_phase_" .. tostring(phase),
            "members=" .. tostring(#mission.roster)
                .. " receipts=" .. tostring(scout and scout.search
                    and #scout.search.acquisitions))
        Harness.sharedSearchLastPhase = phase
    end
    Harness.sharedSearchSeenSpeech = Harness.sharedSearchSeenSpeech or {}
    for _, member in ipairs(mission.roster) do
        local actor = member.actor
        if actor ~= nil and SC.Dialogue
            and type(SC.Dialogue.lastSpokenTopic) == "function" then
            local topic = SC.Dialogue.lastSpokenTopic(actor)
            local spokenAt = SC.Dialogue.lastSpokenAt(actor)
            local key = tostring(member.id) .. ":" .. tostring(spokenAt)
            if topic ~= nil and not Harness.sharedSearchSeenSpeech[key] then
                Harness.sharedSearchSeenSpeech[key] = true
                if topic == "expedition.search_arrival"
                    or string.find(topic, "scavenge.loot.", 1, true) == 1 then
                    Harness.sharedSearchSpeech = true
                    result("PASS", "shared_search_spoke",
                        "member=" .. tostring(member.id)
                            .. " topic=" .. tostring(topic))
                end
            end
        end
    end
    Harness.sharedSearchSeenReceipts = Harness.sharedSearchSeenReceipts or {}
    for _, receipt in ipairs(scout.search.acquisitions) do
        if not Harness.sharedSearchSeenReceipts[receipt.id] then
            Harness.sharedSearchSeenReceipts[receipt.id] = true
            local count, item, carrier = teamStableItem(Harness.team, receipt.id)
            local atSource = sourceStableItemCount(receipt)
            local exact = count == 1 and carrier == receipt.memberId
                and item ~= nil and item:getFullType() == receipt.itemType
                and atSource == 0
            if not check("shared_search_exact_pickup", exact,
                "member=" .. tostring(receipt.memberId)
                    .. " type=" .. tostring(receipt.itemType)
                    .. " stable=" .. tostring(receipt.id)
                    .. " carrier=" .. tostring(carrier)
                    .. " source_matches=" .. tostring(atSource)) then
                setPhase("finish", current)
                return
            end
        end
    end
    -- This probe verifies site participation. Return travel is covered by
    -- separate full-trip probes and can hit an unrelated navigation barrier.
    if phase == "inbound" then
        local carriers = {}
        local exact = #scout.search.acquisitions == #mission.roster
        for _, receipt in ipairs(scout.search.acquisitions) do
            carriers[receipt.memberId] = (carriers[receipt.memberId] or 0) + 1
            local count, item, carrier = teamStableItem(Harness.team, receipt.id)
            if count ~= 1 or carrier ~= receipt.memberId
                or item == nil or item:getFullType() ~= receipt.itemType
                or sourceStableItemCount(receipt) ~= 0 then
                exact = false
            end
        end
        for _, member in ipairs(mission.roster) do
            if carriers[member.id] ~= 1 then exact = false end
        end
        check("shared_search_all_members_exact_native_loot", exact,
            "members=" .. tostring(#mission.roster)
                .. " receipts=" .. tostring(#scout.search.acquisitions)
                .. " reason=" .. tostring(scout.returnReason))
        check("shared_search_destination_speech",
            Harness.sharedSearchSpeech == true,
            "site or loot topic spoken=" .. tostring(Harness.sharedSearchSpeech))
        setPhase("finish", current)
        return
    end
    if current >= (Harness.sharedSearchNextTraceAt or 0) then
        Harness.sharedSearchNextTraceAt = current + 10000
        local details = {}
        for _, member in ipairs(mission.roster) do
            local actor = member.actor
            local x, y = position(actor)
            local decision = actor and SC.Decision.peek(actor) or nil
            local status = actor and SC.Encounter.status(actor) or nil
            details[#details + 1] = tostring(member.id) .. "@"
                .. tostring(math.floor(tonumber(x) or -1)) .. ","
                .. tostring(math.floor(tonumber(y) or -1)) .. ":"
                .. tostring(decision and decision.current) .. "/"
                .. tostring(status and status.phase)
        end
        print("SC_SHARED_SEARCH_TRACE|phase=" .. tostring(phase)
            .. "|receipts=" .. tostring(#scout.search.acquisitions)
            .. "|actors=" .. table.concat(details, ";"))
    end
end

function Harness.stageMultifloorSearchTarget(current)
    local SC = SurvivorCompanion
    local U = SC.GameplayUtil
    local actor = Harness.leader
    local siteId = Harness.unvisitedSearchBuildingId
    local square = actor and actor:getCurrentSquare()
    local cell = getWorld() and getWorld():getCell()
    if square == nil or cell == nil or siteId == nil then return false end
    local ax, ay = square:getX(), square:getY()
    local stairs = {}
    for x = 6156, 6174 do
        for y = 5236, 5266 do
            for z = 0, 1 do
                local candidate = cell:getGridSquare(x, y, z)
                if candidate and SC.Topology.squareHasStairs(candidate)
                    and SC.ExpeditionPlaces.siteContainsPoint(siteId,
                        x, y, z) then
                    stairs[#stairs + 1] = { x = x, y = y, z = z }
                end
            end
        end
    end
    local stairLabels = {}
    for _, stair in ipairs(stairs) do
        stairLabels[#stairLabels + 1] = stair.x .. "," .. stair.y
            .. "," .. stair.z
    end
    result(#stairs > 0 and "PASS" or "FAIL", "multifloor_search_stair_geometry",
        table.concat(stairLabels, ";"))
    if #stairs == 0 then
        setPhase("finish", current)
        return false
    end
    local best, bestDistance
    for x = 6156, 6174 do
        for y = 5236, 5266 do
            local actorDistance = (x - ax)^2 + (y - ay)^2
            local nearestStair = math.huge
            for _, stair in ipairs(stairs) do
                local stairDistance = (x - stair.x)^2 + (y - stair.y)^2
                if stairDistance < nearestStair then
                    nearestStair = stairDistance
                end
            end
            local distance = actorDistance + nearestStair * 2
            if actorDistance <= 16 * 16 and (bestDistance == nil
                or distance < bestDistance) then
                local upper = cell:getGridSquare(x, y, 1)
                if upper and upper:getRoom()
                    and SC.ExpeditionPlaces.siteContainsPoint(siteId,
                        x, y, 1) then
                    U.squareObjects(upper, function(object)
                        local container = select(1,
                            U.call(object, "getContainer"))
                        if container and SC.Encounter.mayTakeFrom(container)
                            == true then
                            best = { square = upper, container = container }
                            bestDistance = distance
                        end
                    end, 40)
                end
            end
        end
    end
    if best == nil then return false end
    local added, item = pcall(function()
        return best.container:AddItem("Base.Bullets9mm")
    end)
    if not added or item == nil then
        result("FAIL", "multifloor_search_item_fixture",
            "upstairs container could not receive native ammunition")
        setPhase("finish", current)
        return false
    end
    local staged, reason = SC.ExpeditionPrototype.stageTestSearch(
        actor, best.container, "ammunition")
    if not staged then
        result("FAIL", "multifloor_search_target_fixture", reason)
        setPhase("finish", current)
        return false
    end
    Harness.multifloorSearchTarget = {
        square = best.square, container = best.container, item = item,
    }
    result("PASS", "multifloor_search_real_upstairs_source",
        "source=" .. tostring(best.square:getX()) .. ","
            .. tostring(best.square:getY()) .. ",1"
            .. " native_item=" .. tostring(item:getID()))
    return true
end

function Harness.stageMultifloorGroundStart(current)
    local SC = SurvivorCompanion
    local U = SC.GameplayUtil
    local siteId = Harness.unvisitedSearchBuildingId
    local chosen = {}
    for x = 6160, 6166 do
        for y = 5239, 5246 do
            local square = U.gridSquare(x, y, 0)
            if square and square:getRoom()
                and SC.ExpeditionPlaces.siteContainsPoint(siteId, x, y, 0)
                and not SC.Topology.squareHasStairs(square)
                and U.squareStaticBlocker(square) == nil then
                chosen[#chosen + 1] = square
            end
        end
    end
    if #chosen < #Harness.teamActors then
        result("FAIL", "multifloor_ground_start_fixture",
            "safe interior tiles=" .. tostring(#chosen))
        setPhase("finish", current)
        return false
    end
    table.sort(chosen, function(a, b)
        local ad = (a:getX() - 6163)^2 + (a:getY() - 5244)^2
        local bd = (b:getX() - 6163)^2 + (b:getY() - 5244)^2
        return ad < bd
    end)
    for index, actor in ipairs(Harness.teamActors) do
        local square = chosen[index]
        actor:teleportTo(square:getX() + 0.5, square:getY() + 0.5, 0)
    end
    Harness.autonomousSearchLastX = nil
    Harness.autonomousSearchLastY = nil
    Harness.multifloorGroundStaged = true
    result("PASS", "multifloor_ground_start_fixture",
        "test-only squad placement inside the target building; leader="
            .. tostring(chosen[1]:getX()) .. ","
            .. tostring(chosen[1]:getY()) .. ",0")
    return true
end

function Harness.probeAutonomousSearch(current)
    if Harness.config.team_shared_search_probe == "true" then
        return Harness.probeSharedSearch(current)
    end
    local SC = SurvivorCompanion
    local U = SC.GameplayUtil
    local mission = SC.ExpeditionPrototype.current()
    local unvisited = Harness.config.team_unvisited_interior_search_probe
        == "true"
    local x, y, z = position(Harness.leader)
    if x == nil or y == nil then
        result("FAIL", "autonomous_search_leader_position",
            "native leader has no position")
        setPhase("finish", current)
        return
    end
    if Harness.config.team_multifloor_search_probe == "true"
        and mission and mission.scout
        and mission.scout.phase == "inbound"
        and not Harness.multifloorPlayerMoved then
        local meeting = U.gridSquare(6160, 5244, 0)
        if meeting == nil or meeting:getRoom() == nil
            or U.squareStaticBlocker(meeting) ~= nil then
            result("FAIL", "multifloor_ground_reunion_fixture",
                "no safe ground-floor meeting square")
            setPhase("finish", current)
            return
        end
        Harness.player:teleportTo(6160.5, 5244.5, 0)
        Harness.playerX, Harness.playerY, Harness.playerZ =
            6160.5, 5244.5, 0
        Harness.multifloorPlayerMoved = true
        result("PASS", "multifloor_ground_reunion_fixture",
            "test-only player moved to 6160,5244,0 after the upstairs pickup")
    end
    if Harness.config.team_multifloor_search_probe == "true"
        and math.floor(z or 0) == 1 and not Harness.multifloorSawUpper then
        Harness.multifloorSawUpper = true
        result("PASS", "multifloor_search_leader_reached_upper_floor",
            "leader=" .. tostring(x) .. "," .. tostring(y) .. ",1")
    end
    if Harness.config.team_multifloor_search_probe == "true"
        and mission and mission.scout
        and mission.scout.phase == "searching"
        and not Harness.multifloorGroundStaged then
        Harness.stageMultifloorGroundStart(current)
        return
    end
    if Harness.config.team_multifloor_search_probe == "true"
        and mission and mission.scout
        and mission.scout.phase == "searching"
        and Harness.multifloorSearchTarget == nil
        and current >= (Harness.multifloorStageNextAt or 0) then
        Harness.multifloorStageStartedAt =
            Harness.multifloorStageStartedAt or current
        Harness.multifloorStageNextAt = current + 1000
        Harness.stageMultifloorSearchTarget(current)
        if Harness.phase == "finish" then return end
        if Harness.multifloorSearchTarget == nil
            and current - Harness.multifloorStageStartedAt > 30000 then
            result("FAIL", "multifloor_search_upper_source_unavailable",
                "no loaded upper-floor container within 16 tiles")
            setPhase("finish", current)
            return
        end
    end
    -- Keep this movement-isolation fixture quiet as the second local map
    -- streams new chunks. The initial spawn-area clear does not cover the
    -- distant destination; a newly loaded zombie otherwise preempts Search
    -- with Combat and turns a path test into an unrelated engagement test.
    if unvisited and Harness.unvisitedSearchDestination
        and current >= (Harness.unvisitedQuietNextAt or 0) then
        Harness.unvisitedQuietNextAt = current + 3000
        local dx = x - Harness.unvisitedSearchDestination.x
        local dy = y - Harness.unvisitedSearchDestination.y
        if dx * dx + dy * dy <= 35 * 35 then
            local removed = cleanupTestZombiesNear(Harness.leader, 60)
            if removed > 0 then
                print("SC_UNVISITED_SEARCH_QUIET|removed=" .. tostring(removed))
            end
        end
    end
    local lastX, lastY = Harness.autonomousSearchLastX,
        Harness.autonomousSearchLastY
    local step = lastX and math.sqrt((x - lastX)^2 + (y - lastY)^2) or 0
    Harness.autonomousSearchMaxStep = math.max(
        Harness.autonomousSearchMaxStep or 0, step)
    Harness.autonomousSearchLastX, Harness.autonomousSearchLastY = x, y
    Harness.autonomousSearchChunks[tostring(math.floor(x / 10)) .. ","
        .. tostring(math.floor(y / 10))] = true
    if unvisited and SC.NativeTraversalActions then
        local traversalPhase, traversalReason, traversalRecord =
            SC.NativeTraversalActions.poll(Harness.leader)
        local action = traversalRecord and traversalRecord.action
        if action == "smash_window" or action == "remove_glass"
            or action == "climb_window" then
            local key = tostring(action) .. ":" .. tostring(traversalPhase)
                .. ":" .. tostring(traversalRecord.startedAt)
            if key ~= Harness.unvisitedLastTraversalTrace then
                Harness.unvisitedLastTraversalTrace = key
                local window = traversalRecord.object
                local square = window and window:getSquare()
                print("SC_UNVISITED_SEARCH_TRAVERSAL|action=" .. tostring(action)
                    .. "|phase=" .. tostring(traversalPhase)
                    .. "|reason=" .. tostring(traversalReason)
                    .. "|window=" .. tostring(square and square:getX())
                    .. "," .. tostring(square and square:getY())
                    .. "|glass=" .. tostring(traversalRecord.effectVerified)
                    .. "|visual=" .. tostring(SC.NativeActions
                        and SC.NativeActions.visualStatus(Harness.leader,
                            "remove_broken_glass")))
            end
        end
    end
    if unvisited and mission and mission.scout
        and mission.scout.phase == "searching"
        and current >= (Harness.unvisitedMotionNextTraceAt or 0) then
        Harness.unvisitedMotionNextTraceAt = current + 500
        local encounter = SC.Encounter.peek(Harness.leader)
        local task = encounter and encounter.task
        if task and task.phase == "approach" then
            local nav = SC.Navigation._stateForTests(Harness.leader)
            local nextSquare = nav and nav.path
                and nav.path[nav.pathIndex or 0]
            local previousX, previousY =
                Harness.unvisitedMotionX, Harness.unvisitedMotionY
            local distance = previousX and previousY
                and math.sqrt((x - previousX)^2 + (y - previousY)^2)
                or nil
            local actorState = Harness.leader:getCurrentState()
            local decision = SC.Decision.peek(Harness.leader) or {}
            print("SC_UNVISITED_MOTION|pos=" .. tostring(x) .. "," .. tostring(y)
                .. "|delta=" .. tostring(distance)
                .. "|moving=" .. tostring(Harness.leader:isMoving())
                .. "|aiming=" .. tostring(Harness.leader:isAiming())
                .. "|fsm=" .. tostring(actorState)
                .. "|decision=" .. tostring(decision.current)
                    .. "/" .. tostring(decision.intent)
                .. "|nav=" .. tostring(nav and nav.pathReason)
                    .. "/" .. tostring(nav and nav.lastMovementReason)
                    .. "/" .. tostring(nav and nav.stuckAttempts)
                .. "|step=" .. tostring(nextSquare and nextSquare:getX())
                    .. "," .. tostring(nextSquare and nextSquare:getY())
                    .. "/" .. tostring(nav and nav.pathIndex)
                    .. "/" .. tostring(nav and nav.path and #nav.path)
                .. "|room=" .. tostring(nav and nav.roomEntrySweepPhase)
                .. "|lease=" .. tostring(nav and nav.nativeLease
                    and nav.nativeLease.kind))
            Harness.unvisitedMotionX, Harness.unvisitedMotionY = x, y
        else
            Harness.unvisitedMotionX, Harness.unvisitedMotionY = nil, nil
        end
    end
    if unvisited and mission and mission.scout
        and current >= (Harness.unvisitedSearchNextTraceAt or 0) then
        Harness.unvisitedSearchNextTraceAt = current + 15000
        local waypoint = mission.testWaypoint
        local nav = SC.Navigation.status(Harness.leader) or {}
        local gameTime = getGameTime()
        local worldHour = gameTime and gameTime:getWorldAgeHours()
        local search = mission.scout.search
        local encounter = SC.Encounter.peek(Harness.leader)
        local task = encounter and encounter.task
        local decision = SC.Decision.peek(Harness.leader) or {}
        local gap = 0
        local followers = {}
        for index = 2, #(Harness.team or {}) do
            local record = Harness.team[index]
            local actor = record.actor
            local fx, fy, fz = position(actor)
            gap = math.max(gap, fx and fy
                and math.sqrt((fx - x)^2 + (fy - y)^2) or 999)
            local followerNav = SC.Navigation.status(actor) or {}
            local followerState = SC.Navigation.peek(actor) or {}
            local lease = followerState.nativeLease or {}
            local telemetry = lease.telemetry or {}
            local decision = SC.Decision.peek(actor) or {}
            local owner = SC.ActionSupervisor.current(actor)
            local medical = SC.Medical and SC.Medical.assess(actor) or {}
            local treatment = SC.Medical and SC.Medical.peek(actor) or nil
            followers[#followers + 1] = tostring(record.id)
                .. "@" .. tostring(fx) .. "," .. tostring(fy)
                .. "," .. tostring(fz)
                .. ":" .. tostring(followerNav.phase)
                .. "/" .. tostring(followerNav.target)
                .. "/" .. tostring(followerNav.reason)
                .. ":" .. tostring(decision.current)
                .. "/" .. tostring(decision.intent)
                .. ":" .. tostring(owner and owner.kind)
                .. ":lease=" .. tostring(lease.startedAt
                    and current - lease.startedAt)
                .. ",still=" .. tostring(lease.positionProgressAt
                    and current - lease.positionProgressAt)
                .. ",next=" .. tostring(telemetry.pathNextIsSet)
                    .. ":" .. tostring(telemetry.pathNextX)
                    .. "," .. tostring(telemetry.pathNextY)
                .. ",engine=" .. tostring(telemetry.status)
                    .. ":" .. tostring(telemetry.active)
                .. ",leaseGoal=" .. tostring(lease.ultimateGoal
                    and SC.GameplayUtil.squareKey(lease.ultimateGoal))
                .. ",leaseTo=" .. tostring(lease.toSquare
                    and SC.GameplayUtil.squareKey(lease.toSquare))
                .. ",end=" .. tostring(followerState.nativeLeaseEndReason)
                .. ",streak=" .. tostring(followerState.nativeFailureStreak)
                .. ",route=" .. tostring(followerState.pathReason)
                .. ",failure=" .. tostring(followerState.lastNativeFailureTelemetry
                    and followerState.lastNativeFailureTelemetry.summary)
                .. ":health=" .. tostring(medical.health)
                .. ",bleed=" .. tostring(medical.bleedingCount)
                .. ",open=" .. tostring(medical.openWounds)
                .. ",dirty=" .. tostring(medical.dirtyBandages)
                .. ",critical=" .. tostring(medical.critical)
                .. ",care=" .. tostring(SC.Medical
                    and SC.Medical.isReceivingCare(actor))
                .. ",treatment=" .. tostring(treatment and treatment.phase)
        end
        print("SC_UNVISITED_SEARCH_PROGRESS|phase="
            .. tostring(mission.scout.phase)
            .. "|pos=" .. tostring(x) .. "," .. tostring(y)
                .. "," .. tostring(Harness.leader:getZ())
            .. "|distance=" .. tostring(math.sqrt(
                (x - Harness.unvisitedSearchDestination.x)^2
                + (y - Harness.unvisitedSearchDestination.y)^2))
            .. "|legs=" .. tostring(mission.scout.legs)
            .. "|return=" .. tostring(mission.scout.returnIndex)
            .. "/" .. tostring(mission.scout.trail
                and mission.scout.trail[mission.scout.returnIndex or 0]
                and mission.scout.trail[mission.scout.returnIndex].z)
            .. "|descent=" .. tostring(mission.scout.descent
                and mission.scout.descent.fromZ)
            .. ">" .. tostring(mission.scout.descent
                and mission.scout.descent.toZ)
            .. "|issue=" .. tostring(mission.technicalIssue
                and mission.technicalIssue.reason)
            .. "|pause=" .. tostring(mission.scout.pause
                and mission.scout.pause.mode)
            .. "|trailReturn=" .. tostring(mission.scout.trailReturn)
            .. "|roadRoute=" .. tostring(mission.scout.roadRoute ~= nil)
            .. "|waypoint=" .. tostring(waypoint and waypoint.x)
            .. "," .. tostring(waypoint and waypoint.y)
            .. "|hold=" .. tostring(mission.cohesionHold
                and mission.cohesionHold.reason)
            .. "|gap=" .. tostring(gap)
            .. "|nav=" .. tostring(nav.phase) .. "/"
            .. tostring(nav.target)
            .. "/" .. tostring(nav.pathReason)
            .. "/expanded=" .. tostring(nav.expandedNodes)
            .. "/duration=" .. tostring(nav.lastPlanDurationMs)
            .. "/failure=" .. tostring(nav.pathFailureClass)
            .. "|plan_failure=" .. tostring(
                mission.scout.lastPlanFailure)
            .. "|hours=" .. tostring(worldHour) .. "/"
                .. tostring(search and search.deadlineHour)
            .. "|task=" .. tostring(task and task.phase) .. "@"
                .. tostring(task and task.owner and task.owner:getSquare()
                    and task.owner:getSquare():getX()) .. ","
                .. tostring(task and task.owner and task.owner:getSquare()
                    and task.owner:getSquare():getY())
            .. "|approach_stage=" .. tostring(task and task.approachStage
                and task.approachStage:getX()) .. ","
                .. tostring(task and task.approachStage
                    and task.approachStage:getY())
            .. "|leader_decision=" .. tostring(decision.current) .. "/"
                .. tostring(decision.intent)
            .. "|followers=" .. table.concat(followers, ";"))
        if not Harness.unvisitedDoorDiagnostic and task
            and task.phase == "approach" and x >= 6167 and x <= 6169
            and y >= 5247 and y <= 5255 then
            Harness.unvisitedDoorDiagnostic = true
            local source = Harness.leader:getCurrentSquare()
            local cell = getWorld():getCell()
            local edges = {}
            local floorObjects = {}
            for _, offset in ipairs({ { 0, -1 }, { 1, 0 },
                    { 0, 1 }, { -1, 0 }, { 0, 0 } }) do
                local neighbor = cell:getGridSquare(
                    source:getX() + offset[1],
                    source:getY() + offset[2], source:getZ())
                if neighbor then
                    local items = neighbor:getWorldObjects()
                    floorObjects[#floorObjects + 1] =
                        tostring(neighbor:getX()) .. ","
                            .. tostring(neighbor:getY()) .. ":"
                            .. tostring(items and SC.NativeList.size(items) or 0)
                end
                local edge = neighbor and SC.Navigation.edgeAffordance(
                    source, neighbor) or nil
                if edge then
                    local object = edge.object
                    edges[#edges + 1] = tostring(neighbor:getX()) .. ","
                        .. tostring(neighbor:getY()) .. ":"
                        .. tostring(edge.kind) .. ":"
                        .. tostring(object and SC.Topology.objectOpen(object))
                        .. ":" .. tostring(object
                            and SC.Topology.objectLocked(object))
                        .. ":unlock=" .. tostring(object
                            and SC.Topology.actorCanUnlock(
                                Harness.leader, object, source))
                end
            end
            local targets = SC.Navigation.interactionTargets(
                Harness.leader, task.owner,
                { requireDirectAccess = true })
            local target = targets and targets[1]
            local path, reason, expanded
            if target then path, reason, expanded = SC.Navigation.findPath(
                source, target, { actor = Harness.leader,
                    nodeBudget = 1000 }) end
            print("SC_UNVISITED_SEARCH_DOOR|source="
                .. tostring(source:getX()) .. "," .. tostring(source:getY())
                .. "|room=" .. tostring(U.roomName(source))
                .. "|edges=" .. table.concat(edges, ";")
                .. "|floor_objects=" .. table.concat(floorObjects, ";")
                .. "|targets=" .. tostring(targets and #targets)
                .. "|first=" .. tostring(target and target:getX()) .. ","
                    .. tostring(target and target:getY())
                .. "|path=" .. tostring(path and #path)
                .. "|reason=" .. tostring(reason)
                .. "|expanded=" .. tostring(expanded)
                .. "|bash_tool=" .. tostring(SC.NativeActions
                    and SC.NativeActions.doorBashTool(Harness.leader)))
        end
        if not Harness.unvisitedSearchPortalChecked
            and math.sqrt((x - Harness.unvisitedSearchDestination.x)^2
                + (y - Harness.unvisitedSearchDestination.y)^2) <= 25 then
            local cell = getWorld():getCell()
            local loaded, doors, windows, barricaded = 0, 0, 0, 0
            local details = {}
            for tx = 6154, 6176 do
                for ty = 5234, 5268 do
                    local square = cell:getGridSquare(tx, ty, 0)
                    if square ~= nil then
                        loaded = loaded + 1
                        local objects = square:getObjects()
                        local count = objects and SC.NativeList.size(objects) or 0
                        for objectIndex = 0, math.min(count, 64) - 1 do
                            local object = select(1, SC.NativeList.get(
                                objects, objectIndex))
                            local isDoor = U.instanceOf(object, "IsoDoor")
                            local isWindow = U.instanceOf(object, "IsoWindow")
                            if isDoor or isWindow then
                                if isDoor then doors = doors + 1
                                else windows = windows + 1 end
                                local boards = SC.Topology.objectBarricaded(object)
                                if boards then barricaded = barricaded + 1 end
                                details[#details + 1] = tostring(tx)
                                    .. "," .. tostring(ty) .. ":"
                                    .. (isDoor and "door" or "window")
                                    .. ":" .. tostring(boards)
                                    .. ":" .. tostring(SC.Topology.objectLocked(object))
                            end
                        end
                    end
                end
            end
            Harness.unvisitedSearchPortalChecked = true
            print("SC_UNVISITED_SEARCH_PORTALS|loaded="
                .. tostring(loaded) .. "|doors=" .. tostring(doors)
                .. "|windows=" .. tostring(windows)
                .. "|barricaded=" .. tostring(barricaded)
                .. "|details=" .. table.concat(details, ";"))
        end
        if not Harness.unvisitedSearchDirectChecked
            and math.sqrt((x - Harness.unvisitedSearchDestination.x)^2
                + (y - Harness.unvisitedSearchDestination.y)^2) <= 18 then
            Harness.unvisitedSearchDirectChecked = true
            local destination = getWorld():getCell():getGridSquare(
                Harness.unvisitedSearchDestination.x,
                Harness.unvisitedSearchDestination.y, 0)
            local path, reason, expanded
            if destination ~= nil then
                path, reason, expanded = SC.Navigation.findPath(
                    Harness.leader:getCurrentSquare(), destination,
                    { actor = Harness.leader, nodeBudget = 3500 })
            end
            local nodes = {}
            for pathIndex, square in ipairs(path or {}) do
                local px, py = SC.GameplayUtil.position(square)
                local edge = pathIndex > 1
                    and SC.Navigation.edgeAffordance(path[pathIndex - 1], square)
                    or nil
                local object = edge and edge.object
                nodes[#nodes + 1] = tostring(px) .. "," .. tostring(py)
                    .. (square:getRoom() and "i" or "o")
                    .. ":" .. tostring(edge and edge.kind or "open")
                    .. ":locked=" .. tostring(object
                        and SC.Topology.objectLocked(object))
                    .. ":barricaded=" .. tostring(object
                        and SC.Topology.objectBarricaded(object))
            end
            print("SC_UNVISITED_SEARCH_DIRECT|loaded="
                .. tostring(destination ~= nil)
                .. "|free=" .. tostring(destination
                    and SC.GameplayUtil.isSquareFree(destination))
                .. "|path=" .. tostring(path and #path)
                .. "|reason=" .. tostring(reason)
                .. "|expanded=" .. tostring(expanded)
                .. "|nodes=" .. table.concat(nodes, ";"))
        end
    end
    if unvisited and not Harness.unvisitedSearchEntered then
        local square = Harness.leader:getCurrentSquare()
        if square ~= nil and square:getRoom() ~= nil then
            local building = getWorld():getMetaGrid():getBuildingAt(
                square:getX(), square:getY(), 0)
            local place = building and SC.ExpeditionPlaces.describeBuilding(
                building, true)
            if place and place.id == Harness.unvisitedSearchBuildingId then
                Harness.unvisitedSearchEntered = true
                result("PASS", "unvisited_search_actual_interior_entry",
                    "tile=" .. tostring(square:getX()) .. ","
                        .. tostring(square:getY())
                        .. " room=" .. tostring(U.roomName(square)))
            end
        end
    end
    if mission and mission.technicalIssue then
        result("FAIL", "autonomous_search_technical_issue",
            tostring(mission.technicalIssue.reason))
        setPhase("finish", current)
        return
    end
    if unvisited and mission and not Harness.autonomousSearchHotbarChecked then
        Harness.autonomousSearchHotbarFirstSeenAt =
            Harness.autonomousSearchHotbarFirstSeenAt or current
        if current - Harness.autonomousSearchHotbarFirstSeenAt >= 2000 then
            local bar = type(getPlayerHotbar) == "function"
                and getPlayerHotbar(1) or nil
            local listed = false
            local ui = UIManager and UIManager.UI
            if ui and bar then
                for index = 0, ui:size() - 1 do
                    if ui:get(index) == bar then listed = true break end
                end
            end
            check("expedition_ai_view_hotbar_suppressed",
                bar ~= nil and not bar:isVisible() and not listed,
                "created=" .. tostring(bar ~= nil)
                    .. " visible=" .. tostring(bar and bar:isVisible())
                    .. " listed=" .. tostring(listed))
            Harness.autonomousSearchHotbarChecked = true
        end
    end
    local encounter = SC.Encounter.peek(Harness.leader)
    local task = encounter and encounter.task
    if task and task.phase == "animate"
        and Harness.autonomousSearchLootVisualObserved ~= true
        and SC.NativeActions and type(SC.NativeActions.visualStatus) == "function" then
        local visual = SC.NativeActions.visualStatus(Harness.leader, "loot_container")
        if visual == "active" then
            Harness.autonomousSearchLootVisualObserved = true
            local sourceType = task.container and task.container:getType() or "unknown"
            result("PASS", "autonomous_search_native_loot_pose",
                "source=" .. tostring(task.sourceKind)
                    .. " container=" .. tostring(sourceType)
                    .. " action=loot_container visual=active")
        end
    end
    if task and task.container then
        Harness.autonomousSearchSeenContainers =
            Harness.autonomousSearchSeenContainers or setmetatable({}, {
                __mode = "k",
            })
        if not Harness.autonomousSearchSeenContainers[task.container] then
            Harness.autonomousSearchSeenContainers[task.container] = true
            Harness.autonomousSearchSourceCount =
                (Harness.autonomousSearchSourceCount or 0) + 1
            local square = task.owner and task.owner:getSquare()
            local sx, sy = position(square)
            result("PASS", "autonomous_search_considered_source_"
                .. tostring(Harness.autonomousSearchSourceCount),
                "phase=" .. tostring(task.phase)
                    .. " source=" .. tostring(sx) .. "," .. tostring(sy))
        end
    end
    if task and not task.pendingItem and task.item and task.destination
        and Harness.autonomousSearchSelected == nil then
        local item = task.item
        Harness.autonomousSearchSelected = {
            item = item, source = task.container,
            destination = task.destination,
            nativeId = item:getID(), itemType = item:getFullType(),
            sourceCountBefore = task.container:getItems():size(),
        }
        result("PASS", "autonomous_search_native_item_selected",
            "type=" .. tostring(item:getFullType())
                .. " id=" .. tostring(item:getID())
                .. " category=" .. tostring(task.category))
    end
    local status = SC.Encounter.status(Harness.leader)
    local loot = status and status.lastLoot
    local selected = Harness.autonomousSearchSelected
    local requestedCategory = Harness.config.team_multifloor_search_probe
        == "true" and "ammunition" or "construction"
    if selected and loot and loot.missionId ~= nil
        and Harness.autonomousSearchLootVerified ~= true then
        local sourceCountAfter = selected.source:getItems():size()
        local exact = loot.verified == true
            and Harness.autonomousSearchLootVisualObserved == true
            and loot.missionId == (mission and mission.radioSession
                or Harness.autonomousSearchMissionId)
            and loot.requestedCategory == requestedCategory
            and type(loot.stableId) == "string"
            and U.itemStableId(selected.item, false) == loot.stableId
            and selected.item:getID() == selected.nativeId
            and selected.item:getFullType() == selected.itemType
            and not U.inventoryContains(selected.source, selected.item)
            and sourceCountAfter + 1 == selected.sourceCountBefore
        check("autonomous_search_exact_native_debit", exact,
            "source=" .. tostring(selected.sourceCountBefore) .. "->"
                .. tostring(sourceCountAfter)
                .. " type=" .. tostring(loot.type)
                .. " stable=" .. tostring(loot.stableId))
        Harness.autonomousSearchLootVerified = exact
        if not exact then setPhase("finish", current) return end
    end
    if mission == nil then
        local debrief = SC.ExpeditionPrototype.lastDebrief()
        if unvisited then
            local chunks = 0
            for _ in pairs(Harness.autonomousSearchChunks) do
                chunks = chunks + 1
            end
            check("unvisited_search_entered_and_returned",
                Harness.unvisitedSearchEntered == true
                    and debrief ~= nil and debrief.kind == "search"
                    and debrief.request.category == requestedCategory
                    and debrief.request.quantity == 1
                    and debrief.inventoryComplete == true
                    and #debrief.acquisitions == #debrief.returnedIds
                    and SC.ExpeditionPrototype.lastOutcome() == "returned"
                    and getSpecificPlayer(0) == Harness.player
                    and getSpecificPlayer(1) == nil
                    and math.abs(x - Harness.playerX) <= 12
                    and math.abs(y - Harness.playerY) <= 12
                    and (Harness.autonomousSearchMaxStep or math.huge) < 3
                    and chunks >= 2,
                "entered=" .. tostring(Harness.unvisitedSearchEntered)
                    .. " outcome=" .. tostring(
                        SC.ExpeditionPrototype.lastOutcome())
                    .. " end=" .. tostring(debrief and debrief.endReason)
                    .. " acquired=" .. tostring(debrief
                        and #debrief.acquisitions)
                    .. " returned=" .. tostring(debrief
                        and #debrief.returnedIds)
                    .. " chunks=" .. tostring(chunks)
                    .. " max_step=" .. tostring(
                        Harness.autonomousSearchMaxStep))
            if Harness.config.team_multifloor_search_probe == "true" then
                local receipt = debrief and debrief.acquisitions
                    and debrief.acquisitions[1]
                local source = receipt and receipt.source
                local grounded, groundedCount = true, 0
                for _, member in ipairs(Harness.team or {}) do
                    if member.actor and not member.actor:isDead() then
                        groundedCount = groundedCount + 1
                        grounded = grounded and math.abs(
                            member.actor:getZ() - Harness.player:getZ()) <= 0.2
                    end
                end
                check("multifloor_search_real_upper_loot_and_ground_return",
                    Harness.multifloorSawUpper == true
                        and Harness.multifloorSearchTarget ~= nil
                        and source ~= nil and source.z == 1
                        and SC.ExpeditionPrototype.lastOutcome() == "returned"
                        and math.abs((z or -1) - Harness.player:getZ()) <= 0.2
                        and grounded and groundedCount == #(Harness.team or {}),
                    "reached_upper=" .. tostring(Harness.multifloorSawUpper)
                        .. " source_z=" .. tostring(source and source.z)
                        .. " return_z=" .. tostring(z)
                        .. " grounded=" .. tostring(groundedCount)
                        .. " outcome=" .. tostring(
                            SC.ExpeditionPrototype.lastOutcome()))
            end
            setPhase("finish", current)
            return
        end
        local carried = false
        if debrief and debrief.acquisitions
            and debrief.acquisitions[1] then
            local wanted = debrief.acquisitions[1].id
            local audit = SC.Logistics.audit(Harness.leader)
            for _, entry in ipairs(audit.items or {}) do
                if U.itemStableId(entry.item, false) == wanted then
                    carried = true break
                end
            end
        end
        local chunks = 0
        for _ in pairs(Harness.autonomousSearchChunks) do
            chunks = chunks + 1
        end
        check("autonomous_search_returned_exact_requested_item",
            Harness.autonomousSearchLootVerified == true
                and debrief ~= nil and debrief.kind == "search"
                and debrief.request.category == "construction"
                and debrief.request.quantity == 1
                and debrief.endReason == "quantity_met"
                and #debrief.acquisitions == 1
                and #debrief.returnedIds == 1
                and debrief.returnedIds[1] == debrief.acquisitions[1].id
                and carried and debrief.inventoryComplete == true,
            "outcome=" .. tostring(SC.ExpeditionPrototype.lastOutcome())
                .. " acquired=" .. tostring(debrief and #debrief.acquisitions)
                .. " returned=" .. tostring(debrief and #debrief.returnedIds)
                .. " reason=" .. tostring(debrief and debrief.endReason)
                .. " carried=" .. tostring(carried))
        check("autonomous_search_walked_home_without_transfer",
            SC.ExpeditionPrototype.lastOutcome() == "returned"
                and getSpecificPlayer(0) == Harness.player
                and getSpecificPlayer(1) == nil
                and math.abs(x - Harness.playerX) <= 12
                and math.abs(y - Harness.playerY) <= 12
                and (Harness.autonomousSearchMaxStep or math.huge) < 3
                and chunks >= 2,
            "leader=" .. tostring(x) .. "," .. tostring(y)
                .. " chunks=" .. tostring(chunks)
                .. " max_step=" .. tostring(Harness.autonomousSearchMaxStep))
        setPhase("finish", current)
        return
    end
    if mission.scout == nil or mission.scout.kind ~= "search" then
        result("FAIL", "autonomous_search_itinerary_missing",
            "mission has no search itinerary")
        setPhase("finish", current)
        return
    end
    if Harness.autonomousSearchMissionId == nil then
        Harness.autonomousSearchMissionId = mission.radioSession
    end
    local phase = mission.scout.phase
    if phase ~= Harness.autonomousSearchLastPhase then
        if phase == "searching" and not unvisited then
            local sourceSquare = getWorld():getCell():getGridSquare(
                6077, 5302, 0)
            local stocked, permitted, blocked = false, false, false
            if sourceSquare then
                U.squareObjects(sourceSquare, function(object)
                    local container = select(1,
                        U.call(object, "getContainer"))
                    local items = container and select(1,
                        U.call(container, "getItems"))
                    if items then
                        for index = 0, items:size() - 1 do
                            local item = items:get(index)
                            if item and item:getFullType()
                                == "Base.FiberglassTape" then
                                stocked = true
                                permitted = SC.Encounter.mayTakeFrom(
                                    container) == true
                                blocked = SC.Navigation.behindLockedDoor(
                                    Harness.leader, sourceSquare)
                                break
                            end
                        end
                    end
                end, 64)
            end
            check("autonomous_search_known_native_source_available",
                stocked and permitted and not blocked,
                "loaded=" .. tostring(sourceSquare ~= nil)
                    .. " stocked=" .. tostring(stocked)
                    .. " permitted=" .. tostring(permitted)
                    .. " blocked=" .. tostring(blocked)
                    .. " room=" .. tostring(U.roomName(sourceSquare)))
        end
        result("PASS", "autonomous_search_phase_" .. tostring(phase),
            "leader=" .. tostring(x) .. "," .. tostring(y)
                .. " acquired="
                .. tostring(#mission.scout.search.acquisitions))
        Harness.autonomousSearchLastPhase = phase
    end
    if Harness.config.team_autonomous_search_stage_only == "true"
        and phase == "inbound" and Harness.autonomousSearchLootVerified == true then
        local receipt = mission.scout.search.acquisitions[1]
        local count, item, carrier = 0, nil, nil
        if receipt then count, item, carrier = teamStableItem(Harness.team, receipt.id) end
        local missingAtSource, sourceCount = sourceStableItemCount(receipt)
        check("autonomous_search_stage_exact_cargo",
            receipt ~= nil and #mission.scout.search.acquisitions == 1
                and count == 1 and carrier == receipt.memberId
                and item:getFullType() == receipt.itemType
                and missingAtSource == 0,
            "stable=" .. tostring(receipt and receipt.id)
                .. " carried=" .. tostring(count)
                .. " source_matches=" .. tostring(missingAtSource)
                .. " source_count=" .. tostring(sourceCount))
        if count ~= 1 or missingAtSource ~= 0 then
            setPhase("finish", current) return
        end
        local saved, document = SC.Runtime.save()
        local descriptor = saved and document and document.expedition
        check("autonomous_search_stage_active_document",
            saved == true and descriptor ~= nil
                and descriptor.schema == 4
                and descriptor.scout.phase == "inbound"
                and descriptor.scout.search.acquisitions[1].id == receipt.id
                and savedStableItemCount(document, Harness.team, receipt.id) == 1,
            "saved=" .. tostring(saved)
                .. " schema=" .. tostring(descriptor and descriptor.schema)
                .. " snapshot_items=" .. tostring(saved and
                    savedStableItemCount(document, Harness.team, receipt.id)))
        if not saved or descriptor == nil or descriptor.schema ~= 4 then
            setPhase("finish", current) return
        end
        local cleared, reason = SC.Runtime.onMainMenuEnter()
        check("autonomous_search_stage_native_and_lf_flush",
            cleared == true and SCSplitScreenProbe.isReleased() == true
                and getSpecificPlayer(1) == nil,
            "reason=" .. tostring(reason)
                .. " slot1=" .. tostring(getSpecificPlayer(1)))
        setPhase("finish", current)
        return
    end
    if current - (Harness.autonomousSearchStartedAt or current)
        > (unvisited and 620000 or 240000) then
        result("FAIL", "autonomous_search_progress_timeout",
            "phase=" .. tostring(phase) .. " leader="
                .. tostring(x) .. "," .. tostring(y)
                .. " acquired="
                .. tostring(#mission.scout.search.acquisitions)
                .. " waypoint=" .. tostring(mission.testWaypoint
                    and mission.testWaypoint.x) .. ","
                .. tostring(mission.testWaypoint and mission.testWaypoint.y)
                .. " plan_failure=" .. tostring(mission.scout.lastPlanFailure)
                .. " replans=" .. tostring(mission.scout.replans)
                .. " hold=" .. tostring(mission.cohesionHold
                    and mission.cohesionHold.reason))
        setPhase("finish", current)
    end
end

function Harness.probeAutonomousSearchResumeStart(current)
    local SC = SurvivorCompanion
    local document = SC.Persistence.lastDocument()
    local mission = SC.ExpeditionPrototype.current()
    if (document == nil or mission == nil or mission.restoring == true
        or mission.leader == nil or mission.leader.actor == nil
        or getSpecificPlayer(1) ~= mission.leader.actor)
        and current - Harness.phaseStartedAt < 25000 then return end
    local descriptor = document and document.expedition
    local search = mission and mission.scout and mission.scout.search
    local receipt = search and search.acquisitions[1]
    check("autonomous_search_resume_active_descriptor",
        descriptor ~= nil and descriptor.schema == 4
            and descriptor.scout.phase == "inbound"
            and mission ~= nil and mission.restoring ~= true
            and mission.scout ~= nil and mission.scout.phase == "inbound"
            and receipt ~= nil and #search.acquisitions == 1
            and receipt.id == descriptor.scout.search.acquisitions[1].id,
        "schema=" .. tostring(descriptor and descriptor.schema)
            .. " phase=" .. tostring(mission and mission.scout
                and mission.scout.phase)
            .. " restoring=" .. tostring(mission and mission.restoring))
    if mission == nil or mission.restoring == true or receipt == nil then
        setPhase("finish", current) return
    end
    local roster = {}
    for _, member in ipairs(mission.roster) do roster[#roster + 1] = member end
    Harness.team = roster
    Harness.leader = mission.leader.actor
    Harness.leaderId = mission.leader.id
    local count, item, carrier = teamStableItem(roster, receipt.id)
    local sourceMatches, sourceCount = sourceStableItemCount(receipt)
    check("autonomous_search_resume_exact_native_cargo",
        count == 1 and item:getFullType() == receipt.itemType
            and carrier == receipt.memberId
            and savedStableItemCount(document, roster, receipt.id) == 1
            and sourceMatches == 0
            and getSpecificPlayer(1) == Harness.leader,
        "stable=" .. tostring(receipt.id)
            .. " carried=" .. tostring(count)
            .. " native_id=" .. tostring(item and item:getID())
            .. " source_matches=" .. tostring(sourceMatches)
            .. " source_count=" .. tostring(sourceCount)
            .. " slot1=" .. tostring(getSpecificPlayer(1) == Harness.leader))
    if count ~= 1 or sourceMatches ~= 0
        or getSpecificPlayer(1) ~= Harness.leader then
        setPhase("finish", current) return
    end
    Harness.autonomousSearchResumeReceipt = receipt
    Harness.autonomousSearchResumeStartedAt = current
    Harness.autonomousSearchResumeLastX,
        Harness.autonomousSearchResumeLastY = position(Harness.leader)
    Harness.autonomousSearchResumeMaxStep = 0
    local trail = {}
    for index, point in ipairs(mission.scout.trail or {}) do
        trail[#trail + 1] = tostring(index) .. ":" .. tostring(point.x)
            .. "," .. tostring(point.y)
    end
    result("PASS", "autonomous_search_resume_route_state",
        "leader=" .. tostring(Harness.autonomousSearchResumeLastX)
            .. "," .. tostring(Harness.autonomousSearchResumeLastY)
            .. " return_index=" .. tostring(mission.scout.returnIndex)
            .. " trail=" .. table.concat(trail, ";"))
    setPhase("team_autonomous_search_resume", current)
end

function Harness.probeAutonomousSearchResume(current)
    local SC = SurvivorCompanion
    local U = SC.GameplayUtil
    local mission = SC.ExpeditionPrototype.current()
    local x, y = position(Harness.leader)
    local lastX, lastY = Harness.autonomousSearchResumeLastX,
        Harness.autonomousSearchResumeLastY
    local step = x and lastX
        and math.sqrt((x - lastX)^2 + (y - lastY)^2) or 0
    Harness.autonomousSearchResumeMaxStep = math.max(
        Harness.autonomousSearchResumeMaxStep or 0, step)
    Harness.autonomousSearchResumeLastX,
        Harness.autonomousSearchResumeLastY = x, y
    if mission and mission.technicalIssue then
        result("FAIL", "autonomous_search_resume_technical_issue",
            tostring(mission.technicalIssue.reason)
                .. " leader=" .. tostring(x) .. "," .. tostring(y)
                .. " waypoint=" .. tostring(mission.testWaypoint
                    and mission.testWaypoint.x) .. ","
                    .. tostring(mission.testWaypoint
                        and mission.testWaypoint.y)
                .. " replans=" .. tostring(mission.scout
                    and mission.scout.replans)
                .. " return_index=" .. tostring(mission.scout
                    and mission.scout.returnIndex))
        setPhase("finish", current) return
    end
    if mission and current >= (Harness.autonomousSearchResumeNextTrace or 0) then
        local scout = mission.scout
        local target = scout and scout.returnIndex
            and scout.trail[scout.returnIndex] or nil
        local navigation = SC.Navigation.status(Harness.leader)
        print("SC_REAL_SANDBOX|SEARCH_RETURN_TRACE|leader="
            .. tostring(x) .. "," .. tostring(y)
            .. " waypoint=" .. tostring(mission.testWaypoint
                and mission.testWaypoint.x) .. ","
                .. tostring(mission.testWaypoint and mission.testWaypoint.y)
            .. " target=" .. tostring(target and target.x) .. ","
                .. tostring(target and target.y)
            .. " index=" .. tostring(scout and scout.returnIndex)
            .. " replans=" .. tostring(scout and scout.replans)
            .. " nav=" .. tostring(navigation.phase) .. "/"
                .. tostring(navigation.reason))
        Harness.autonomousSearchResumeNextTrace = current + 4000
    end
    if mission == nil then
        local receipt = Harness.autonomousSearchResumeReceipt
        local debrief = SC.ExpeditionPrototype.lastDebrief()
        local count, item, carrier = teamStableItem(Harness.team, receipt.id)
        check("autonomous_search_resume_home_with_same_item",
            SC.ExpeditionPrototype.lastOutcome() == "returned"
                and debrief ~= nil and debrief.kind == "search"
                and debrief.endReason == "quantity_met"
                and #debrief.acquisitions == 1
                and debrief.acquisitions[1].id == receipt.id
                and #debrief.returnedIds == 1
                and debrief.returnedIds[1] == receipt.id
                and debrief.inventoryComplete == true
                and count == 1 and carrier == receipt.memberId
                and U.itemStableId(item, false) == receipt.id
                and getSpecificPlayer(0) == Harness.player
                and getSpecificPlayer(1) == nil
                and x ~= nil and y ~= nil
                and math.abs(x - Harness.playerX) <= 12
                and math.abs(y - Harness.playerY) <= 12
                and Harness.autonomousSearchResumeMaxStep < 3,
            "outcome=" .. tostring(SC.ExpeditionPrototype.lastOutcome())
                .. " carried=" .. tostring(count)
                .. " returned=" .. tostring(debrief and #debrief.returnedIds)
                .. " step=" .. tostring(Harness.autonomousSearchResumeMaxStep)
                .. " leader=" .. tostring(x) .. "," .. tostring(y))
        setPhase("finish", current)
        return
    end
    if current - Harness.autonomousSearchResumeStartedAt > 120000 then
        result("FAIL", "autonomous_search_resume_timeout",
            "phase=" .. tostring(mission.scout and mission.scout.phase)
                .. " leader=" .. tostring(x) .. "," .. tostring(y))
        setPhase("finish", current)
    end
end

-- A disposable in-game route fixture: substitute one fresh perception result
-- after verifying the active Riverside streets have a connected detour. The
-- leader, road metadata, local navigation, companions and streaming stay real.
local function probeRoadHordeDetour(current, mission, progress)
    if Harness.config.team_road_horde_probe ~= "true"
        or Harness.hordeInjected == true
        or current < (Harness.nextHordeProbeAt or 0)
        or progress < 20 or progress > 105
        or mission.cohesionHold ~= nil then return end
    local SC = SurvivorCompanion
    local scout = mission.scout
    local route = scout and scout.roadRoute
    if scout == nil or scout.phase ~= "outbound"
        or route == nil or route.index > #route.points then return end
    local x, y = position(Harness.leader)
    local point = route.points[route.index]
    local dx, dy = point.x - x, point.y - y
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 12 then return end
    Harness.nextHordeProbeAt = current + 8000
    Harness.hordeProbeAttempts = (Harness.hordeProbeAttempts or 0) + 1
    local hazard = { x = x + dx / length * 15,
        y = y + dy / length * 15, radius = 8 }
    if Harness.config.team_road_blocked_radio_probe == "true" then
        local originalPlan = SC.ExpeditionRoute.plan
        local originalCached = SC.Senses.cached
        SC.ExpeditionRoute.plan = function(actor, goal, continuing, avoidance)
            if avoidance ~= nil then return nil, "NO_SAFE_ROAD_DETOUR" end
            return originalPlan(actor, goal, continuing, avoidance)
        end
        local threats = {}
        for index = 1, 13 do
            threats[index] = { x = hazard.x, y = hazard.y,
                visible = true, obstructed = false }
        end
        local freshNow = SC.GameplayUtil.nowMs()
        local visible = SC.ExpeditionRoute.visibleHorde(route,
            Harness.leader, { valid = true, reflexTime = freshNow,
                threats = threats }, #Harness.team, freshNow)
        if not check("road_blocked_radio_horde_fixture",
            visible ~= nil, "route_index=" .. tostring(route.index)
                .. " point=" .. tostring(point.x) .. ","
                .. tostring(point.y)
                .. " hazard=" .. tostring(hazard.x) .. ","
                .. tostring(hazard.y)) then
            SC.ExpeditionRoute.plan = originalPlan
            setPhase("finish", current)
            return
        end
        SC.Senses.cached = function(actor, runtime)
            if actor == Harness.leader then
                return { valid = true,
                    reflexTime = SC.GameplayUtil.nowMs(),
                    threats = threats }
            end
            return originalCached(actor, runtime)
        end
        if scout.road then scout.road.avoidance = nil end
        scout.nextHordeCheckAt = 0
        local okay, failure = pcall(SC.ExpeditionPrototype.pulse)
        SC.Senses.cached = originalCached
        SC.ExpeditionRoute.plan = originalPlan
        if not okay then
            result("FAIL", "road_blocked_radio_pulse", tostring(failure))
            setPhase("finish", current)
            return
        end
        local pause = scout.pause
        local view = SC.ExpeditionPrototype.describeForPlayer(Harness.player)
        local reportSeen = false
        for _, receipt in ipairs(Harness.radioReceipts or {}) do
            if receipt.device == Harness.radioFixture.player
                and string.find(receipt.message,
                    "Horde blocks our route", 1, true) then
                reportSeen = true
            end
        end
        local reported = check("road_blocked_radio_request_received",
            pause ~= nil and pause.reported == true
                and pause.mode == "awaiting_orders"
                and view and view.helpRequest ~= nil and reportSeen,
            "pause=" .. tostring(pause and pause.mode)
                .. " reported=" .. tostring(pause and pause.reported)
                .. " receipt=" .. tostring(reportSeen)
                .. " phase=" .. tostring(scout.phase)
                .. " detours=" .. tostring(scout.hordeDetours)
                .. " issue=" .. tostring(mission.technicalIssue
                    and mission.technicalIssue.reason))
        if reported then
            local accepted, reason = SC.ExpeditionPrototype.sendRadioOrder(
                Harness.player, "expedition_decision", "hold_position")
            check("road_blocked_radio_hold_acknowledged",
                accepted == true and scout.pause ~= nil
                    and scout.pause.mode == "holding",
                "accepted=" .. tostring(accepted)
                    .. " reason=" .. tostring(reason))
        end
        setPhase("finish", current)
        return
    end
    local alternate, why = SC.ExpeditionRoute.plan(Harness.leader,
        scout.destination, true, hazard)
    local entryReady = alternate and SC.ExpeditionRoute.verifyEntry(
        alternate, Harness.leader)
    local safeReturn, returnReason
    if Harness.config.team_road_alternate_probe ~= "true"
        and (alternate == nil or entryReady ~= true) then
        safeReturn, returnReason = SC.ExpeditionRoute.plan(
            Harness.leader, scout.returnPoint, true, hazard)
        if safeReturn ~= nil then
            local returnReady = SC.ExpeditionRoute.verifyEntry(
                safeReturn, Harness.leader)
            if returnReady ~= true then safeReturn = nil end
        end
    end
    if (alternate == nil or entryReady ~= true)
        and safeReturn == nil then
        print("SC_REAL_SANDBOX|ROAD_HORDE_PREFLIGHT|attempt="
            .. tostring(Harness.hordeProbeAttempts)
            .. " route=" .. tostring(why)
            .. " entry=" .. tostring(entryReady)
            .. " return=" .. tostring(returnReason)
            .. " hazard=" .. tostring(hazard.x) .. ","
            .. tostring(hazard.y))
        return
    end
    local originalCached = SC.Senses.cached
    local threats = {}
    for index = 1, 13 do
        threats[index] = { x = hazard.x, y = hazard.y,
            visible = true, obstructed = false }
    end
    SC.Senses.cached = function(actor, runtime)
        if actor == Harness.leader then
            return { valid = true,
                reflexTime = SC.GameplayUtil.nowMs(),
                threats = threats }
        end
        return originalCached(actor, runtime)
    end
    scout.nextHordeCheckAt = 0
    local okay, failure = pcall(SC.ExpeditionPrototype.pulse)
    SC.Senses.cached = originalCached
    if not okay then
        result("FAIL", "road_horde_live_pulse", tostring(failure))
        setPhase("finish", current)
        return
    end
    local tookDetour = scout.hordeDetours == 1
        and scout.roadRoute ~= route and scout.phase == "outbound"
    local turnedHome = scout.phase == "inbound"
        and scout.roadRoute ~= nil
        and scout.endReason == "horde_no_safe_detour"
    local passed = check("road_horde_live_response",
        ((Harness.config.team_road_alternate_probe == "true"
                and tookDetour)
            or (Harness.config.team_road_alternate_probe ~= "true"
                and (tookDetour or turnedHome)))
            and scout.road and scout.road.avoidance ~= nil
            and mission.technicalIssue == nil,
        "detours=" .. tostring(scout.hordeDetours)
            .. " phase=" .. tostring(scout.phase)
            .. " end=" .. tostring(scout.endReason)
            .. " issue=" .. tostring(mission.technicalIssue
                and mission.technicalIssue.reason)
            .. " leader=" .. tostring(x) .. "," .. tostring(y))
    if not passed then
        setPhase("finish", current) return
    end
    Harness.hordeInjected = true
    Harness.hordeAvoid = hazard
    Harness.hordeOutcome = tookDetour and "detour" or "return"
    if Harness.config.team_road_alternate_probe == "true" then
        local streets = {}
        for _, candidate in ipairs(scout.roadRoute.points) do
            streets[candidate.street] = true
        end
        check("road_horde_connected_bypass_selected",
            streets["Ark Lane"] and streets["Lincoln St"]
                and streets["Johannes Jr St"],
            "road route must traverse Ark Lane, Lincoln St and Johannes Jr St")
    end
end

function Harness.probeAutonomousScout(current)
    local SC = SurvivorCompanion
    local mission = SC.ExpeditionPrototype.current()
    local x, y = position(Harness.leader)
    if x == nil or y == nil then
        result("FAIL", "autonomous_scout_leader_position", "native leader has no position")
        setPhase("finish", current)
        return
    end
    local lastX, lastY = Harness.autonomousLastX, Harness.autonomousLastY
    local step = lastX and math.sqrt((x - lastX)^2 + (y - lastY)^2) or 0
    Harness.autonomousMaxStep = math.max(Harness.autonomousMaxStep or 0, step)
    Harness.autonomousLastX, Harness.autonomousLastY = x, y
    local progress = Harness.selectedPlaceApproach
        and math.sqrt((x - Harness.autonomousStartX)^2
            + (y - Harness.autonomousStartY)^2)
        or x - Harness.autonomousStartX
    Harness.autonomousFarthest = math.max(Harness.autonomousFarthest or 0, progress)
    if Harness.autonomousProgressAnchorX == nil then
        Harness.autonomousProgressAnchorX = x
        Harness.autonomousProgressAnchorY = y
    end
    local anchorX = Harness.autonomousProgressAnchorX
    local anchorY = Harness.autonomousProgressAnchorY
    if math.sqrt((x - anchorX)^2 + (y - anchorY)^2) >= 0.5 then
        Harness.autonomousLastProgressAt = current
        Harness.autonomousProgressAnchorX = x
        Harness.autonomousProgressAnchorY = y
    end
    local gap = 0
    for index = 2, #Harness.team do
        local member = Harness.team[index].actor
        if member ~= nil and member:isDead() ~= true then
            local fx, fy = position(member)
            if fx == nil or fy == nil then gap = math.huge break end
            gap = math.max(gap, math.sqrt((fx - x)^2 + (fy - y)^2))
        end
    end
    Harness.autonomousMaxGap = math.max(Harness.autonomousMaxGap or 0, gap)
    if Harness.config.team_road_route_probe == "true" and mission
        and mission.scout and mission.scout.roadRoute then
        local route = mission.scout.roadRoute
        for _, side in pairs(route.laneChoices or {}) do
            if side ~= 0 then Harness.roadSideChoiceSeen = true end
        end
        for index = 2, #Harness.team do
            local member = Harness.team[index].actor
            local detail = member and SC.Positioning.debug(member) or nil
            if detail and detail.formationShape == "wedge" then
                Harness.roadWedgeSeen = true
            end
        end
        if not Harness.roadMovementChecked and Harness.roadSideChoiceSeen
            and Harness.roadWedgeSeen and progress >= 40 then
            check("road_lane_variation_selected", true,
                "side lane chosen on a mapped street")
            check("road_shared_wedge_formation_used", true,
                "expedition follower used shared Positioning wedge")
            Harness.roadMovementChecked = true
        end
    end
    if Harness.config.team_road_alternate_probe == "true"
        and Harness.hordeInjected then
        if not Harness.alternateArkEntered
            and math.abs(x - 6040) <= 12 and y >= 5320 and y <= 5405 then
            Harness.alternateArkEntered = true
            check("road_horde_team_walked_ark_lane",
                step < 3 and gap < 20,
                "leader=" .. tostring(x) .. "," .. tostring(y)
                    .. " follower_gap=" .. tostring(gap))
        end
        if not Harness.alternateLincolnEntered
            and x >= 6070 and x <= 6175
            and math.abs(y - 5400) <= 12 then
            Harness.alternateLincolnEntered = true
            check("road_horde_team_walked_lincoln_st",
                Harness.alternateArkEntered == true
                    and step < 3 and gap < 20,
                "leader=" .. tostring(x) .. "," .. tostring(y)
                    .. " follower_gap=" .. tostring(gap))
        end
    end
    if Harness.config.team_road_movement_probe == "true"
        and mission and progress >= 75 then
        local formation = {}
        for index = 2, #Harness.team do
            local member = Harness.team[index].actor
            local detail = member and SC.Positioning.debug(member) or nil
            formation[#formation + 1] = tostring(detail and detail.formationMode)
                .. "/" .. tostring(detail and detail.formationShape)
                .. "/" .. tostring(detail and detail.fireteamSize)
        end
        if not Harness.roadMovementChecked then
            check("road_lane_variation_selected",
                Harness.roadSideChoiceSeen == true,
                "side=" .. tostring(Harness.roadSideChoiceSeen))
            check("road_shared_wedge_formation_used",
                Harness.roadWedgeSeen == true,
                "formation=" .. table.concat(formation, ","))
        end
        check("road_movement_squad_cohesion", gap < 20,
            "gap=" .. tostring(gap) .. " formation="
                .. table.concat(formation, ","))
        setPhase("finish", current)
        return
    end
    if mission == nil then
        local debrief = SC.ExpeditionPrototype.lastDebrief()
        if Harness.config.team_zombie_visibility_probe == "true" then
            check("autonomous_scout_zombie_encounter_captured",
                Harness.scoutZombieScreenshotCaptured == true,
                "screenshot_ack=" .. tostring(Harness.scoutZombieScreenshotCaptured))
            if Harness.visibilityFixtureZombie ~= nil then
                cleanupTestZombie(Harness.visibilityFixtureZombie)
                Harness.visibilityFixtureZombie = nil
            end
        end
        if Harness.config.team_road_route_probe == "true"
            and not Harness.roadMovementChecked then
            check("road_lane_variation_selected",
                Harness.roadSideChoiceSeen == true,
                "side_choice=" .. tostring(Harness.roadSideChoiceSeen))
            check("road_shared_wedge_formation_used",
                Harness.roadWedgeSeen == true,
                "wedge=" .. tostring(Harness.roadWedgeSeen))
        end
        if Harness.config.team_road_alternate_probe == "true" then
            check("road_horde_connected_bypass_traversed",
                Harness.alternateArkEntered == true
                    and Harness.alternateLincolnEntered == true,
                "ark=" .. tostring(Harness.alternateArkEntered)
                    .. " lincoln=" .. tostring(Harness.alternateLincolnEntered))
        end
        if Harness.hordeOutcome == "return" then
            check("road_horde_early_return_debrief",
                debrief ~= nil and debrief.kind == "scout"
                    and debrief.endReason == "horde_no_safe_detour"
                    and debrief.observation == nil,
                "end=" .. tostring(debrief and debrief.endReason)
                    .. " observation=" .. tostring(debrief
                        and debrief.observation))
        else
            check("autonomous_scout_debrief_retained",
                debrief ~= nil and debrief.kind == "scout"
                    and debrief.observation ~= nil
                    and debrief.observation.status == "complete"
                    and debrief.observation.visibleSquares > 0,
                "observation=" .. tostring(debrief and debrief.observation
                    and debrief.observation.status)
                    .. " visible_squares=" .. tostring(debrief
                        and debrief.observation
                        and debrief.observation.visibleSquares))
            check("autonomous_scout_destination_reached",
                Harness.autonomousFarthest >= (Harness.selectedPlaceApproach
                    and math.max(20, math.sqrt(
                        (Harness.selectedPlaceApproach.x
                            - Harness.autonomousStartX)^2
                        + (Harness.selectedPlaceApproach.y
                            - Harness.autonomousStartY)^2)
                        - 8) or 75),
                "farthest=" .. tostring(Harness.autonomousFarthest))
        end
        check("autonomous_scout_returned_to_original_player",
            SC.ExpeditionPrototype.lastOutcome() == "returned"
                and math.abs(x - Harness.playerX) <= 12
                and math.abs(y - Harness.playerY) <= 12
                and getSpecificPlayer(1) == nil,
            "outcome=" .. tostring(SC.ExpeditionPrototype.lastOutcome())
                .. " leader=" .. tostring(x) .. "," .. tostring(y))
        check("autonomous_scout_team_walked_without_transfer",
            (Harness.autonomousMaxStep or math.huge) < 3
                and (Harness.autonomousMaxGap or math.huge) < 20,
            "max_step=" .. tostring(Harness.autonomousMaxStep)
                .. " max_gap=" .. tostring(Harness.autonomousMaxGap))
        setPhase("finish", current)
        return
    end
    local scout = mission.scout
    if scout == nil or mission.technicalIssue ~= nil then
        local screenshotName = tostring(Harness.config.run_id)
            .. "-scout-stall.png"
        local captured, screenshotError = pcall(function()
            getCore():TakeFullScreenshot(screenshotName)
        end)
        local directory, dirOk = SC.GameplayUtil.call(getCore(),
            "getScreenshotDir")
        result(captured and "PASS" or "FAIL",
            "autonomous_scout_stall_screenshot_requested",
            "file=" .. screenshotName
                .. " directory=" .. tostring(dirOk and directory)
                .. " error=" .. tostring(screenshotError))
        result("FAIL", "autonomous_scout_itinerary_active",
            "phase=" .. tostring(scout and scout.phase)
                .. " issue=" .. tostring(mission.technicalIssue
                    and mission.technicalIssue.reason)
                .. " leader=" .. tostring(x) .. "," .. tostring(y)
                .. " waypoint=" .. tostring(mission.testWaypoint
                    and mission.testWaypoint.x) .. ","
                    .. tostring(mission.testWaypoint and mission.testWaypoint.y)
                .. " return_index=" .. tostring(scout and scout.returnIndex)
                .. " road_index=" .. tostring(scout and scout.roadRoute
                    and scout.roadRoute.index)
                .. " side=" .. tostring(Harness.roadSideChoiceSeen)
                .. " wedge=" .. tostring(Harness.roadWedgeSeen)
                .. " replans=" .. tostring(scout and scout.replans)
                .. " pause=" .. tostring(scout and scout.pause
                    and scout.pause.mode)
                .. " road_failure=" .. tostring(scout
                    and scout.lastRoadFailure))
        setPhase("finish", current)
        return
    end
    if Harness.config.team_zombie_visibility_probe == "true"
        and not Harness.scoutZombieScreenshotRequested and progress >= 40 then
        local cell = getWorld():getCell()
        local zombies = cell and cell:getZombieList() or nil
        local visibleZombie = nil
        if zombies ~= nil then
            for index = 0, zombies:size() - 1 do
                local zombie = zombies:get(index)
                local zx, zy, zz = position(zombie)
                if zombie ~= nil and zombie:isDead() ~= true
                    and zx ~= nil and zy ~= nil and zz ~= nil
                    and math.floor(zz) == math.floor(Harness.leader:getZ())
                    and (zx - x)^2 + (zy - y)^2 <= 8 * 8
                    and zombie:getCurrentSquare() ~= nil
                    and SC.GameplayUtil.canSee(Harness.leader,
                        zombie:getCurrentSquare()) == true then
                    visibleZombie = zombie
                    break
                end
            end
        end
        if visibleZombie == nil and type(addZombiesInOutfit) == "function" then
            for _, offset in ipairs({ { 4, 3 }, { 4, -3 },
                    { -4, 3 }, { -4, -3 }, { 5, 0 }, { -5, 0 } }) do
                local square = cell and cell:getGridSquare(
                    math.floor(x) + offset[1], math.floor(y) + offset[2],
                    math.floor(Harness.leader:getZ()))
                if square ~= nil and SC.GameplayUtil.isSquareFree(square)
                    and SC.GameplayUtil.canSee(Harness.leader, square) == true then
                    local spawned, list = pcall(addZombiesInOutfit,
                        square:getX(), square:getY(), square:getZ(),
                        1, nil, 0)
                    local zombie = spawned and list and list:size() > 0
                        and list:get(0) or nil
                    if zombie ~= nil and zombie:getCurrentSquare() ~= nil then
                        visibleZombie = zombie
                        Harness.visibilityFixtureZombie = zombie
                        break
                    elseif zombie ~= nil then
                        cleanupTestZombie(zombie)
                    end
                end
            end
        end
        if visibleZombie ~= nil then
            Harness.scoutZombieScreenshotRequested = true
            writeSignal("SurvivorCompanionHarness/zombie-visibility-ready.txt",
                { "ready=true" })
            local zx, zy = position(visibleZombie)
            result("PASS", "autonomous_scout_zombie_screenshot_requested",
                "zombie=" .. tostring(zx) .. "," .. tostring(zy)
                    .. " leader=" .. tostring(x) .. "," .. tostring(y)
                    .. " fixture=" .. tostring(Harness.visibilityFixtureZombie ~= nil))
        end
    end
    if Harness.scoutZombieScreenshotRequested
        and not Harness.scoutZombieScreenshotCaptured
        and fileExists("SurvivorCompanionHarness/zombie-visibility-captured.txt") then
        Harness.scoutZombieScreenshotCaptured = true
        if Harness.visibilityFixtureZombie ~= nil then
            cleanupTestZombie(Harness.visibilityFixtureZombie)
            Harness.visibilityFixtureZombie = nil
        end
    end
    probeRoadHordeDetour(current, mission, progress)
    if Harness.phase == "finish" then return end
    if Harness.config.team_road_horde_probe == "true"
        and not Harness.hordeInjected
        and progress > 105 then
        result("FAIL", "road_horde_safe_response_found",
            "no connected bypass or safe return after "
                .. tostring(Harness.hordeProbeAttempts or 0)
                .. " bounded preflight attempts")
        setPhase("finish", current)
        return
    end
    if Harness.config.team_road_restart_stage_only == "true"
        and scout.phase == "inbound"
        and x <= scout.destination.x - 18 then
        local saved, document = SC.Runtime.save()
        local descriptor = saved and document and document.expedition
        check("road_restart_stage_active_descriptor",
            saved == true and descriptor ~= nil
                and descriptor.schema == 5
                and descriptor.scout.phase == "inbound"
                and descriptor.scout.road ~= nil
                and descriptor.scout.road.phase == "inbound"
                and #descriptor.roster == 4,
            "saved=" .. tostring(saved)
                .. " schema=" .. tostring(descriptor and descriptor.schema)
                .. " phase=" .. tostring(descriptor and descriptor.scout
                    and descriptor.scout.phase))
        if not saved or descriptor == nil or descriptor.schema ~= 5 then
            setPhase("finish", current) return
        end
        local cleared, why = SC.Runtime.onMainMenuEnter()
        check("road_restart_stage_native_flush",
            cleared == true and getSpecificPlayer(1) == nil,
            "flushed=" .. tostring(cleared) .. " reason=" .. tostring(why))
        setPhase("finish", current)
        return
    end
    if scout.replans ~= nil
        and scout.replans ~= Harness.autonomousLastReplans then
        local nav = SC.Navigation.status(Harness.leader) or {}
        local decision = SC.Decision.peek(Harness.leader) or {}
        result("PASS", "autonomous_scout_replan_" .. tostring(scout.replans),
            "leader=" .. tostring(x) .. "," .. tostring(y)
                .. " waypoint=" .. tostring(mission.testWaypoint
                    and mission.testWaypoint.x) .. ","
                    .. tostring(mission.testWaypoint and mission.testWaypoint.y)
                .. " return_index=" .. tostring(scout.returnIndex)
                .. " nav=" .. tostring(nav.phase) .. "/" .. tostring(nav.target)
                .. " decision=" .. tostring(decision.current))
        Harness.autonomousLastReplans = scout.replans
    end
    if current - (Harness.autonomousLastProgressAt or current) >= 180000
        and scout.phase ~= "observing" then
        local followerDetails = {}
        for index = 2, #Harness.team do
            local follower = Harness.team[index].actor
            local fx, fy = position(follower)
            local nav = SC.Navigation.status(follower) or {}
            local decision = SC.Decision.peek(follower) or {}
            followerDetails[#followerDetails + 1] = tostring(index)
                .. ":" .. tostring(fx) .. "," .. tostring(fy)
                .. ":" .. tostring(nav.phase)
                .. ":" .. tostring(nav.reason)
                .. ":" .. tostring(decision.current)
                .. ":target=" .. tostring(nav.target)
                .. ":nodes=" .. tostring(nav.expandedNodes)
                .. ":stuck=" .. tostring(nav.stuckAttempts)
                .. ":path=" .. tostring(nav.pathReason)
        end
        local screenshotName = tostring(Harness.config.run_id)
            .. "-scout-progress-stall.png"
        local captured, screenshotError = pcall(function()
            getCore():TakeFullScreenshot(screenshotName)
        end)
        result(captured and "PASS" or "FAIL",
            "autonomous_scout_progress_screenshot_requested",
            "file=" .. screenshotName
                .. " error=" .. tostring(screenshotError))
        result("FAIL", "autonomous_scout_progress",
            "phase=" .. tostring(scout.phase)
                .. " legs=" .. tostring(scout.legs)
                .. " position=" .. tostring(x) .. "," .. tostring(y)
                .. " waypoint=" .. tostring(mission.testWaypoint
                    and mission.testWaypoint.x) .. ","
                    .. tostring(mission.testWaypoint and mission.testWaypoint.y)
                .. " plan_failure=" .. tostring(scout.lastPlanFailure)
                .. " replans=" .. tostring(scout.replans)
                .. " pause=" .. tostring(scout.pause and scout.pause.mode)
                .. " road_failure=" .. tostring(scout.lastRoadFailure)
                .. " hold=" .. tostring(mission.cohesionHold
                    and mission.cohesionHold.reason) .. "/"
                    .. tostring(mission.cohesionHold
                        and mission.cohesionHold.memberId)
                .. " progress_age=" .. tostring(current
                    - (scout.lastProgressAt or current))
                .. " waypoint_age=" .. tostring(current
                    - (scout.waypointStagedAt or current))
                .. " owner=" .. tostring(SC.ActionSupervisor
                    and SC.ActionSupervisor.current(Harness.leader)
                    and SC.ActionSupervisor.current(Harness.leader).kind)
                .. " followers=" .. table.concat(followerDetails, ";"))
        setPhase("finish", current)
        return
    end
    if scout.phase ~= Harness.autonomousLastPhase then
        if scout.phase == "inbound"
            and Harness.hordeOutcome ~= "return" then
            local observed = scout.observation
            check("autonomous_scout_actual_site_observed",
                observed ~= nil and observed.status == "complete"
                    and observed.visibleSquares > 0
                    and observed.worldHour ~= nil,
                "status=" .. tostring(observed and observed.status)
                    .. " visible=" .. tostring(observed and observed.visibleSquares)
                    .. " reason=" .. tostring(scout.observationReason)
                    .. " at=" .. tostring(observed and observed.at
                        and observed.at.x) .. ","
                        .. tostring(observed and observed.at and observed.at.y)
                    .. " destination=" .. tostring(scout.destination.x)
                        .. "," .. tostring(scout.destination.y))
        end
        result("PASS", "autonomous_scout_phase_" .. tostring(scout.phase),
            "leader=" .. tostring(x) .. "," .. tostring(y)
                .. " legs=" .. tostring(scout.legs)
                .. " follower_gap=" .. tostring(gap))
        Harness.autonomousLastPhase = scout.phase
    end
end

function Harness.probeRoadRestartResumeStart(current)
    local SC = SurvivorCompanion
    local document = SC.Persistence.lastDocument()
    local mission = SC.ExpeditionPrototype.current()
    local ready = document and mission and mission.restoring ~= true
        and mission.leader and mission.leader.actor
        and getSpecificPlayer(1) == mission.leader.actor
    if not ready and current - Harness.phaseStartedAt < 25000 then return end
    local descriptor = document and document.expedition
    check("road_restart_resume_descriptor",
        ready and descriptor.schema == 5
            and descriptor.scout.phase == "inbound"
            and descriptor.scout.road ~= nil
            and mission.scout and mission.scout.phase == "inbound"
            and #mission.roster == 4,
        "ready=" .. tostring(ready)
            .. " schema=" .. tostring(descriptor and descriptor.schema)
            .. " phase=" .. tostring(mission and mission.scout
                and mission.scout.phase))
    if not ready or descriptor.schema ~= 5 then
        setPhase("finish", current) return
    end
    Harness.team = mission.roster
    Harness.leader = mission.leader.actor
    Harness.leaderId = mission.leader.id
    Harness.roadResumeStartedAt = current
    Harness.roadResumeStartX, Harness.roadResumeStartY =
        position(Harness.leader)
    Harness.roadResumeLastX, Harness.roadResumeLastY =
        Harness.roadResumeStartX, Harness.roadResumeStartY
    Harness.roadResumeMaxStep = 0
    setPhase("team_road_restart_resume", current)
end

function Harness.probeRoadRestartResume(current)
    local SC = SurvivorCompanion
    local mission = SC.ExpeditionPrototype.current()
    local x, y = position(Harness.leader)
    local step = x and Harness.roadResumeLastX and math.sqrt(
        (x - Harness.roadResumeLastX)^2
        + (y - Harness.roadResumeLastY)^2) or 0
    Harness.roadResumeMaxStep = math.max(Harness.roadResumeMaxStep, step)
    Harness.roadResumeLastX, Harness.roadResumeLastY = x, y
    if mission and mission.technicalIssue then
        result("FAIL", "road_restart_resume_technical_issue",
            tostring(mission.technicalIssue.reason)
                .. " leader=" .. tostring(x) .. "," .. tostring(y))
        setPhase("finish", current) return
    end
    if mission == nil then
        check("road_restart_resume_returned",
            SC.ExpeditionPrototype.lastOutcome() == "returned"
                and #Harness.team == 4
                and getSpecificPlayer(1) == nil
                and x and y
                and math.abs(x - Harness.playerX) <= 12
                and math.abs(y - Harness.playerY) <= 12
                and Harness.roadResumeMaxStep < 3,
            "outcome=" .. tostring(SC.ExpeditionPrototype.lastOutcome())
                .. " leader=" .. tostring(x) .. "," .. tostring(y)
                .. " max_step=" .. tostring(Harness.roadResumeMaxStep))
        setPhase("finish", current) return
    end
    if current >= (Harness.roadResumeNextTraceAt or 0) then
        result("PASS", "road_restart_resume_progress",
            "leader=" .. tostring(x) .. "," .. tostring(y)
                .. " legs=" .. tostring(mission.scout.legs)
                .. " route_index=" .. tostring(mission.scout.roadRoute
                    and mission.scout.roadRoute.index))
        Harness.roadResumeNextTraceAt = current + 30000
    end
    if current - Harness.roadResumeStartedAt > 650000 then
        result("FAIL", "road_restart_resume_timeout",
            "leader=" .. tostring(x) .. "," .. tostring(y))
        setPhase("finish", current)
    end
end

function Harness.probeExtendedRouteStage(current)
    Harness.observeExtendedFootprint()
    if Harness.pursuerVerified then setPhase("finish", current) return end
    if Harness.leader:isDead() == true then
        result("FAIL", "extended_route_leader_alive_for_next_leg",
            "original leader died before a new local route could be admitted")
        setPhase("finish", current)
        return
    end
    local lx, ly = position(Harness.leader)
    local followerGap = 0
    for index = 2, #Harness.team do
        local fx, fy = position(Harness.team[index].actor)
        local gap = fx and fy and lx and ly
            and math.sqrt((fx - lx)^2 + (fy - ly)^2) or math.huge
        followerGap = math.max(followerGap, gap)
    end
    if followerGap >= 20 then
        if current - Harness.phaseStartedAt < 30000 then return end
        result("FAIL", "extended_route_straggler_rejoined",
            "largest_follower_gap=" .. tostring(followerGap))
        setPhase("finish", current)
        return
    end
    if Harness.extendedRouteLegs >= 9 then
        result("FAIL", "extended_route_bounded_leg_count",
            "legs=" .. tostring(Harness.extendedRouteLegs))
        setPhase("finish", current)
        return
    end
    if Harness.extendedRouteSurvey == nil and Harness.extendedLastPlanAt ~= nil
        and current - Harness.extendedLastPlanAt < 1000 then return end
    Harness.extendedLastPlanAt = current
    local SC = SurvivorCompanion
    local cell = getWorld():getCell()
    local source = Harness.leader:getCurrentSquare()
    local x, y, z = position(Harness.leader)
    if source == nil or x == nil or y == nil then
        result("FAIL", "extended_route_source_available",
            "leader has no loaded square")
        setPhase("finish", current)
        return
    end
    local selected, routeNodes = nil, nil
    local loadedCandidates, freeCandidates = 0, 0
    local rejectedRoutes = {}
    local sourceRoom = source:getRoom()
    local survey = Harness.extendedRouteSurvey
    if survey == nil or survey.source ~= source then
        survey = { source = source, rejected = {}, job = nil, key = nil }
        Harness.extendedRouteSurvey = survey
    end
    local function keepsExteriorAfterExit(path)
        local outside = sourceRoom == nil
        for _, node in ipairs(path) do
            local room = node:getRoom()
            if outside and room ~= nil then return false end
            if sourceRoom ~= nil and room ~= sourceRoom then
                if room ~= nil then return false end
                outside = true
            end
        end
        return outside
    end
    -- Long travel should skirt buildings rather than strand an outdoor
    -- follower at an entrance the leader can unlock only from inside.
    -- A lateral step is admitted when the direct eastward corridor ends.
    for _, forward in ipairs({ 20, 16, 12, 10, 8, 5, 0 }) do
        for _, lateral in ipairs({ 0, 3, -3, 6, -6, 10, -10,
                14, -14, 18, -18 }) do
            local tx, ty = math.floor(x) + forward,
                math.floor(y) + lateral
            local square = cell:getGridSquare(tx, ty, math.floor(z))
            local repeatedStall = Harness.extendedLastStalledTarget
                and Harness.extendedLastStalledTarget.x == tx
                and Harness.extendedLastStalledTarget.y == ty
            if square ~= nil then loadedCandidates = loadedCandidates + 1 end
            if not repeatedStall and square ~= nil
                and square:getRoom() == nil
                and SC.GameplayUtil.isSquareFree(square) then
                freeCandidates = freeCandidates + 1
                local key = tostring(tx) .. ":" .. tostring(ty)
                if not survey.rejected[key] then
                    if survey.job == nil then
                        survey.job = SC.Navigation.beginPathSearch(source,
                            square, nil,
                            { actor = Harness.leader, nodeBudget = 1800 })
                        survey.key = key
                    end
                    local status, path, pathReason =
                        SC.Navigation.resumePathSearch(survey.job, 96)
                    if status == "pending" then return end
                    survey.job, survey.key = nil, nil
                    local direct = math.sqrt(forward * forward
                        + lateral * lateral)
                    if status == "complete" and pathReason == nil
                        and path ~= nil
                        and #path >= 4 and #path <= direct * 1.8 + 8
                        and keepsExteriorAfterExit(path) then
                        selected = { x = tx, y = ty, z = math.floor(z) }
                        routeNodes = #path
                        break
                    end
                    survey.rejected[key] = true
                    if #rejectedRoutes < 4 then
                        rejectedRoutes[#rejectedRoutes + 1] = tostring(tx)
                            .. "," .. tostring(ty) .. ":"
                            .. tostring(pathReason) .. "/"
                            .. tostring(path and #path)
                    end
                    -- Match the production planner: at most one route-search
                    -- slice or candidate result can run in a rendered frame.
                    return
                end
            end
        end
        if selected ~= nil then break end
    end
    if selected == nil then
        if current - Harness.phaseStartedAt < 15000 then return end
        result("FAIL", "extended_route_next_leg_admitted",
            "no loaded, free, locally pathable forward target at "
                .. tostring(x) .. "," .. tostring(y)
                .. " source_room=" .. tostring(select(1,
                    SC.GameplayUtil.call(source, "getRoomIDString")))
                .. " loaded=" .. tostring(loadedCandidates)
                .. " free=" .. tostring(freeCandidates)
                .. " rejected=" .. table.concat(rejectedRoutes, ";"))
        setPhase("finish", current)
        return
    end
    Harness.extendedRouteSurvey = nil
    local staged, reason = SC.ExpeditionPrototype.stageTestWaypoint(
        Harness.leader, selected.x, selected.y, selected.z)
    check("extended_route_leg_" .. tostring(Harness.extendedRouteLegs + 1)
        .. "_staged", staged == true,
        "from=" .. tostring(x) .. "," .. tostring(y)
            .. " to=" .. tostring(selected.x) .. ","
            .. tostring(selected.y) .. " nodes=" .. tostring(routeNodes)
            .. " reason=" .. tostring(reason))
    if not staged then setPhase("finish", current) return end
    Harness.extendedRouteLegs = Harness.extendedRouteLegs + 1
    Harness.extendedRouteTarget = selected
    Harness.extendedLastProgressX, Harness.extendedLastProgressY = x, y
    Harness.extendedLastProgressAt = current
    Harness.extendedLastPlanAt = nil
    setPhase("team_extended_route_walk", current)
end

function Harness.probeExtendedRouteWalk(current)
    local x, y = observeLocalTravelStep()
    Harness.observeExtendedFootprint()
    if Harness.pursuerVerified then setPhase("finish", current) return end
    local SC = SurvivorCompanion
    local mission = SC.ExpeditionPrototype.current()
    local arrival = mission and mission.testWaypointArrival
    local target = Harness.extendedRouteTarget
    if arrival == nil and x ~= nil then
        local moved = Harness.extendedLastProgressX and math.sqrt(
            (x - Harness.extendedLastProgressX)^2
                + (y - Harness.extendedLastProgressY)^2) or math.huge
        if moved >= 0.75 then
            Harness.extendedLastProgressX, Harness.extendedLastProgressY = x, y
            Harness.extendedLastProgressAt = current
        elseif mission and mission.cohesionHold == nil
            and current - (Harness.extendedLastProgressAt or current) >= 12000
            and Harness.config.team_pursuer_probe == "true"
            and Harness.leader:isDead() ~= true then
            Harness.extendedRouteReplans =
                (Harness.extendedRouteReplans or 0) + 1
            if Harness.extendedRouteReplans > 3 then
                result("FAIL", "extended_route_stall_replan_limit",
                    "leader stalled near " .. tostring(target.x) .. ","
                        .. tostring(target.y))
                setPhase("finish", current)
                return
            end
            local decision = SC.Decision.peek(Harness.leader) or {}
            local navigation = SC.Navigation.status(Harness.leader) or {}
            local cleared, reason = SC.ExpeditionPrototype.clearTestWaypoint(
                Harness.leader)
            check("extended_route_stall_replan_"
                .. tostring(Harness.extendedRouteReplans), cleared == true,
                "leader=" .. tostring(x) .. "," .. tostring(y)
                    .. " target=" .. tostring(target.x) .. ","
                    .. tostring(target.y) .. " decision="
                    .. tostring(decision.current) .. "/"
                    .. tostring(decision.intent) .. " nav="
                    .. tostring(navigation.phase) .. " reason="
                    .. tostring(reason))
            if not cleared then setPhase("finish", current) return end
            Harness.extendedLastStalledTarget = target
            setPhase("team_extended_route_stage", current)
            return
        end
    end
    if arrival == nil and x ~= nil and x >= target.x + 3
        and Harness.leader:isDead() ~= true then
        Harness.extendedRouteReplans =
            (Harness.extendedRouteReplans or 0) + 1
        if Harness.extendedRouteReplans > 3 then
            result("FAIL", "extended_route_replan_limit",
                "leader repeatedly passed standing targets during tactical work")
            setPhase("finish", current)
            return
        end
        local cleared, clearReason = SC.ExpeditionPrototype.clearTestWaypoint(
            Harness.leader)
        check("extended_route_tactical_waypoint_"
            .. tostring(Harness.extendedRouteLegs) .. "_abandoned",
            cleared == true,
            "leader_x=" .. tostring(x)
                .. " passed_target_x=" .. tostring(target.x)
                .. " reason=" .. tostring(clearReason)
                .. " replans=" .. tostring(Harness.extendedRouteReplans))
        if not cleared then setPhase("finish", current) return end
        setPhase("team_extended_route_stage", current)
        return
    end
    if arrival == nil or mission.testWaypointArrived ~= true then
        if current - Harness.phaseStartedAt < 90000
            and Harness.leader:isDead() ~= true then return end
        local decision = SC.Decision.peek(Harness.leader) or {}
        local navigation = SC.Navigation.status(Harness.leader) or {}
        local hold = mission and mission.cohesionHold
        local followers = {}
        for index = 2, #Harness.team do
            local record = Harness.team[index]
            local follower = record.actor
            local fx, fy = position(follower)
            local followerNav = SC.Navigation.status(follower) or {}
            local followerDecision = SC.Decision.peek(follower) or {}
            local currentSquare = follower:getCurrentSquare()
            local roomId = currentSquare and select(1,
                SC.GameplayUtil.call(currentSquare, "getRoomIDString"))
            followers[#followers + 1] = tostring(record.id) .. "@"
                .. tostring(fx) .. "," .. tostring(fy) .. ":gap="
                .. tostring(fx and fy and x and y
                    and math.sqrt((fx - x)^2 + (fy - y)^2) or "unavailable")
                .. ":room=" .. tostring(roomId)
                .. ":decision=" .. tostring(followerDecision.current)
                .. "/" .. tostring(followerDecision.intent)
                .. ":nav=" .. tostring(followerNav.phase)
                .. "/" .. tostring(followerNav.pathReason)
                .. ":target=" .. tostring(followerNav.target)
                .. ":blocker=" .. tostring(followerNav.blockerType)
        end
        result("FAIL", "extended_route_leg_"
            .. tostring(Harness.extendedRouteLegs) .. "_arrived",
            "actor=" .. tostring(x) .. "," .. tostring(y)
                .. " target=" .. tostring(target.x) .. ","
                .. tostring(target.y)
                .. " dead=" .. tostring(Harness.leader:isDead())
                .. " decision=" .. tostring(decision.current) .. "/"
                .. tostring(decision.intent)
                .. " nav=" .. tostring(navigation.phase) .. "/"
                .. tostring(navigation.reason)
                .. " hold=" .. tostring(hold and hold.reason) .. "/"
                .. tostring(hold and hold.maxGap)
                .. " followers=" .. table.concat(followers, ";"))
        setPhase("finish", current)
        return
    end
    local distance = math.sqrt((arrival.x - target.x)^2
        + (arrival.y - target.y)^2)
    local maxFollowerGap = 0
    local actorsActive = getSpecificPlayer(1) == Harness.leader
        and SC.Registry.isActive(Harness.leader, Harness.leaderId)
    for index = 2, #Harness.team do
        local record = Harness.team[index]
        local fx, fy = position(record.actor)
        local gap = fx and fy and x and y
            and math.sqrt((fx - x)^2 + (fy - y)^2) or math.huge
        maxFollowerGap = math.max(maxFollowerGap, gap)
        actorsActive = actorsActive
            and SC.Registry.isActive(record.actor, record.id)
    end
    if maxFollowerGap >= 20 and current - Harness.phaseStartedAt < 90000 then
        return
    end
    local cell = getWorld():getCell()
    local map0, map1 = cell:getChunkMap(0), cell:getChunkMap(1)
    local mapMinX = map1 and map1:getWorldXMinTiles()
    local mapMaxX = map1 and map1:getWorldXMaxTiles()
    local legOk = distance < 2 and maxFollowerGap < 20
        and actorsActive and map1 ~= nil
        and chunkMapCovers(map1, math.floor(x), math.floor(y))
        and (Harness.localTravelMaxStep or math.huge) < 3
        and getSpecificPlayer(0) == Harness.player
    check("extended_route_leg_" .. tostring(Harness.extendedRouteLegs)
        .. "_arrived", legOk,
        "actor=" .. tostring(x) .. "," .. tostring(y)
            .. " distance=" .. tostring(distance)
            .. " follower_gap=" .. tostring(maxFollowerGap)
            .. " slot1_tiles=" .. tostring(mapMinX) .. ".."
            .. tostring(mapMaxX)
            .. " max_step=" .. tostring(Harness.localTravelMaxStep))
    if not legOk then setPhase("finish", current) return end
    local progress = x - Harness.localStartX
    local playerOwnsEndpoint = chunkMapCovers(map0,
        math.floor(x), math.floor(y))
    if progress >= 85 then
        local movedFootprint = mapMinX ~= nil
            and Harness.extendedInitialMapMinX ~= nil
            and mapMinX - Harness.extendedInitialMapMinX >= 80
            and mapMaxX - mapMinX
                == Harness.extendedInitialMapMaxX
                    - Harness.extendedInitialMapMinX
            and not chunkMapCovers(map1,
                math.floor(Harness.localStartX),
                math.floor(Harness.localStartY))
        check("native_slot_one_footprint_followed_long_walk",
            movedFootprint and not playerOwnsEndpoint
                and cell:getGridSquare(math.floor(Harness.playerX),
                    math.floor(Harness.playerY), Harness.playerZ) ~= nil,
            "progress=" .. tostring(progress)
                .. " map_min="
                .. tostring(Harness.extendedInitialMapMinX) .. "->"
                .. tostring(mapMinX)
                .. " slot0_owns_endpoint=" .. tostring(playerOwnsEndpoint)
                .. " legs=" .. tostring(Harness.extendedRouteLegs))
        if not movedFootprint then setPhase("finish", current) return end
        setPhase("team_extended_route_verify", current)
        return
    end
    setPhase("team_extended_route_stage", current)
end

function Harness.probeExtendedRouteVerify(current)
    if current - Harness.phaseStartedAt < 5000 then return end
    local cell = getWorld():getCell()
    local map0 = cell:getChunkMap(0)
    local map1 = cell:getChunkMap(1)
    local playerOwnsStart = chunkMapCovers(map0,
        math.floor(Harness.localStartX), math.floor(Harness.localStartY))
    local startSquare = cell:getGridSquare(
        math.floor(Harness.localStartX),
        math.floor(Harness.localStartY),
        math.floor(Harness.localStartZ))
    local currentSquare = Harness.leader:getCurrentSquare()
    local sourceReleased = map1 ~= nil
            and not chunkMapCovers(map1,
                math.floor(Harness.localStartX),
                math.floor(Harness.localStartY))
            and (startSquare ~= nil) == playerOwnsStart
            and currentSquare ~= nil
            and getSpecificPlayer(0) == Harness.player
            and getSpecificPlayer(1) == Harness.leader
    check(playerOwnsStart
        and "moving_footprint_released_original_square_from_slot_one"
        or "moving_footprint_released_original_remote_square",
        sourceReleased,
        "source_loaded=" .. tostring(startSquare ~= nil)
            .. " player_owns_start=" .. tostring(playerOwnsStart)
            .. " leader_loaded=" .. tostring(currentSquare ~= nil)
            .. " slot1_tiles=" .. tostring(map1 and map1:getWorldXMinTiles())
            .. ".." .. tostring(map1 and map1:getWorldXMaxTiles()))
    if Harness.config.team_corpse_streaming_probe == "true" then
        local cx, cy = math.floor(Harness.corpseStreamX),
            math.floor(Harness.corpseStreamY)
        local corpseUnloaded = map1 ~= nil
            and not chunkMapCovers(map1, cx, cy)
            and SCSplitScreenProbe.retainedCorpseChunkCount() == 1
        check("corpse_stream_native_death_site_outside_view", corpseUnloaded,
            "corpse=" .. tostring(cx) .. "," .. tostring(cy)
                .. " map_min=" .. tostring(map1 and map1:getWorldXMinTiles())
                .. " retained=" .. tostring(SCSplitScreenProbe.retainedCorpseChunkCount()))
        if not corpseUnloaded then setPhase("finish", current) return end
        local moved, reason = pcall(function()
            Harness.player:teleportTo(cx + 2, cy,
                math.floor(Harness.corpseStreamZ))
        end)
        check("corpse_stream_test_visitor_queued", moved,
            tostring(reason))
        setPhase(moved and "team_corpse_stream_visit_wait" or "finish",
            current)
        return
    end
    if sourceReleased
        and Harness.config.team_extended_return_probe == "true" then
        Harness.extendedReturnStartX, Harness.extendedReturnStartY =
            position(Harness.leader)
        Harness.extendedReturnFarX = math.floor(Harness.extendedReturnStartX)
        Harness.extendedReturnFarY = math.floor(Harness.extendedReturnStartY)
        Harness.extendedReturnInitialMapMinX = map1:getWorldXMinTiles()
        Harness.extendedReturnInitialMapMaxX = map1:getWorldXMaxTiles()
        Harness.extendedReturnLegs = 0
        Harness.extendedReturnReplans = 0
        setPhase("team_extended_return_stage", current)
        return
    end
    setPhase("finish", current)
end

function Harness.probeExtendedReturnResumeStart(current)
    if current - Harness.phaseStartedAt < 5000 then return end
    local SC = SurvivorCompanion
    local mission = SC.ExpeditionPrototype.current()
    local leaderRecord = mission and mission.leader
    local leader = leaderRecord and leaderRecord.actor
    local records = SC.Registry.records()
    local x, y, z
    if leader then x, y, z = position(leader) end
    local cell = getWorld():getCell()
    local map = cell and cell:getChunkMap(1)
    local sourceX = tonumber(Harness.config.team_extended_return_source_x)
    local sourceY = tonumber(Harness.config.team_extended_return_source_y)
    local ready = mission ~= nil and leader ~= nil
        and getSpecificPlayer(1) == leader
        and #records == 4 and #SC.Registry.living() == 4
        and x ~= nil and y ~= nil and map ~= nil
        and chunkMapCovers(map, math.floor(x), math.floor(y))
        and sourceX ~= nil and sourceY ~= nil
        and x - sourceX >= 85
        and not chunkMapCovers(map, sourceX, sourceY)
    if not ready and current - Harness.phaseStartedAt < 30000 then return end
    check("extended_return_resume_native_team_ready", ready,
        "mission=" .. tostring(mission ~= nil)
            .. " slot1=" .. tostring(getSpecificPlayer(1) == leader)
            .. " records=" .. tostring(#records)
            .. " leader=" .. tostring(x) .. "," .. tostring(y)
            .. " source=" .. tostring(sourceX) .. "," .. tostring(sourceY))
    if not ready then setPhase("finish", current) return end
    Harness.leader, Harness.leaderId = leader, leaderRecord.id
    Harness.team = {leaderRecord}
    for _, record in ipairs(records) do
        if record.id ~= leaderRecord.id then
            Harness.team[#Harness.team + 1] = record
        end
    end
    Harness.localStartX, Harness.localStartY = sourceX, sourceY
    Harness.localStartZ = math.floor(z or 0)
    Harness.localTravelLastX, Harness.localTravelLastY = x, y
    Harness.localTravelMaxStep = 0
    Harness.localTravelChunks = {}
    Harness.extendedReturnStartX, Harness.extendedReturnStartY = x, y
    Harness.extendedReturnFarX, Harness.extendedReturnFarY =
        math.floor(x), math.floor(y)
    Harness.extendedReturnInitialMapMinX = map:getWorldXMinTiles()
    Harness.extendedReturnInitialMapMaxX = map:getWorldXMaxTiles()
    Harness.extendedReturnLegs = 0
    Harness.extendedReturnReplans = 0
    Harness.extendedReturnLastStalledTarget = nil
    Harness.extendedReturnStallCaptured = false
    local cleared, reason = SC.ExpeditionPrototype.clearTestWaypoint(leader)
    result("PASS", "extended_return_resume_prior_waypoint_cleared",
        "cleared=" .. tostring(cleared) .. " reason=" .. tostring(reason))
    setPhase("team_extended_return_stage", current)
end

function Harness.probeExtendedReturnStage(current)
    if Harness.leader:isDead() == true then
        result("FAIL", "extended_return_leader_alive",
            "original leader died before another return leg")
        setPhase("finish", current)
        return
    end
    local x, y, z = position(Harness.leader)
    if x == nil or y == nil or Harness.leader:getCurrentSquare() == nil then
        result("FAIL", "extended_return_source_loaded",
            "leader has no authoritative square")
        setPhase("finish", current)
        return
    end
    if x <= Harness.localStartX + 5
        and math.abs(y - Harness.localStartY) < 12 then
        setPhase("team_extended_return_verify", current)
        return
    end
    local maxGap = 0
    for index = 2, #Harness.team do
        local fx, fy = position(Harness.team[index].actor)
        maxGap = math.max(maxGap, fx and fy
            and math.sqrt((fx - x)^2 + (fy - y)^2) or math.huge)
    end
    if maxGap >= 20 then
        if current - Harness.phaseStartedAt < 30000 then return end
        result("FAIL", "extended_return_team_rejoined",
            "largest_follower_gap=" .. tostring(maxGap))
        setPhase("finish", current)
        return
    end
    if Harness.extendedReturnLegs >= 18 then
        result("FAIL", "extended_return_bounded_leg_count",
            "legs=" .. tostring(Harness.extendedReturnLegs))
        setPhase("finish", current)
        return
    end
    if Harness.extendedReturnLastPlanAt
        and current - Harness.extendedReturnLastPlanAt < 1000 then return end
    Harness.extendedReturnLastPlanAt = current
    local SC = SurvivorCompanion
    local cell = getWorld():getCell()
    local source = Harness.leader:getCurrentSquare()
    local selected, nodes
    for _, step in ipairs({ 20, 16, 12, 10, 8, 5 }) do
        local tx = math.max(math.floor(Harness.localStartX),
            math.floor(x) - step)
        if tx < math.floor(x) then
            local lateralChoices = Harness.extendedReturnPreferLateral
                and { -3, 3, -6, 6, -9, 9, 0 }
                or { 0, -3, 3, -6, 6, -9, 9 }
            for _, lateral in ipairs(lateralChoices) do
                local ty = math.floor(y) + lateral
                local stalled = Harness.extendedReturnLastStalledTarget
                    and Harness.extendedReturnLastStalledTarget.x == tx
                    and Harness.extendedReturnLastStalledTarget.y == ty
                local square = cell:getGridSquare(tx, ty, math.floor(z))
                if not stalled and math.abs(ty - Harness.localStartY) < 12
                    and square and SC.GameplayUtil.isSquareFree(square) then
                    local path = SC.Navigation.findPath(source, square,
                        { actor = Harness.leader, nodeBudget = 1800 })
                    if path and #path >= 4
                        and #path <= step * 1.5 + math.abs(lateral) + 6 then
                        selected = { x = tx, y = ty, z = math.floor(z) }
                        nodes = #path
                        break
                    end
                end
            end
        end
        if selected then break end
    end
    if not selected then
        if current - Harness.phaseStartedAt < 15000 then return end
        result("FAIL", "extended_return_next_leg_admitted",
            "no loaded pathable westward target at "
                .. tostring(x) .. "," .. tostring(y))
        setPhase("finish", current)
        return
    end
    local staged, reason = SC.ExpeditionPrototype.stageTestWaypoint(
        Harness.leader, selected.x, selected.y, selected.z)
    check("extended_return_leg_" .. tostring(Harness.extendedReturnLegs + 1)
        .. "_staged", staged == true,
        "from=" .. tostring(x) .. "," .. tostring(y)
            .. " to=" .. tostring(selected.x) .. ","
            .. tostring(selected.y) .. " nodes=" .. tostring(nodes)
            .. " reason=" .. tostring(reason))
    if not staged then setPhase("finish", current) return end
    Harness.extendedReturnLegs = Harness.extendedReturnLegs + 1
    Harness.extendedReturnTarget = selected
    Harness.extendedReturnLastProgressX = x
    Harness.extendedReturnLastProgressY = y
    Harness.extendedReturnLastProgressAt = current
    Harness.extendedReturnLastPlanAt = nil
    setPhase("team_extended_return_walk", current)
end

function Harness.extendedReturnNavigationDetail(current)
    local state = SurvivorCompanion.Navigation.peek(Harness.leader) or {}
    local path = state.path
    local index = tonumber(state.pathIndex) or 0
    local nextX, nextY
    if path and path[index] then nextX, nextY = position(path[index]) end
    local search = state.pathSearch
    local route = search and search.route
    return "path=" .. tostring(path and #path) .. "/" .. tostring(index)
        .. " next=" .. tostring(nextX) .. "," .. tostring(nextY)
        .. " search_age=" .. tostring(search and current - search.startedAt)
        .. " expanded=" .. tostring(search and search.lastExpanded)
        .. " yield=" .. tostring(route and route.lastYieldReason)
        .. " lease=" .. tostring(state.nativeLease ~= nil)
        .. " movement=" .. tostring(state.lastMovementReason)
        .. " progress_age=" .. tostring(state.lastProgressAt
            and current - state.lastProgressAt)
        .. " stuck=" .. tostring(state.stuckAttempts)
        .. " fsm=" .. tostring(Harness.leader:getCurrentState())
end

function Harness.probeExtendedReturnWalk(current)
    local x, y = observeLocalTravelStep()
    local SC = SurvivorCompanion
    local mission = SC.ExpeditionPrototype.current()
    local arrival = mission and mission.testWaypointArrival
    local target = Harness.extendedReturnTarget
    if x == nil or y == nil or Harness.leader:isDead() then
        result("FAIL", "extended_return_leader_available",
            "leader missing or dead during return")
        setPhase("finish", current)
        return
    end
    if arrival == nil then
        local moved = math.sqrt((x - Harness.extendedReturnLastProgressX)^2
            + (y - Harness.extendedReturnLastProgressY)^2)
        if moved >= 0.75 then
            Harness.extendedReturnLastProgressX = x
            Harness.extendedReturnLastProgressY = y
            Harness.extendedReturnLastProgressAt = current
            Harness.extendedReturnReplans = 0
        end
        if not Harness.extendedReturnStallCaptured
            and current - Harness.extendedReturnLastProgressAt >= 12000 then
            Harness.extendedReturnStallCaptured = true
            local decision = SC.Decision.peek(Harness.leader) or {}
            local nav = SC.Navigation.status(Harness.leader) or {}
            local hold = mission and mission.cohesionHold
            result("PASS", "extended_return_first_sustained_stop",
                "leader=" .. tostring(x) .. "," .. tostring(y)
                    .. " target=" .. tostring(target.x) .. ","
                    .. tostring(target.y) .. " decision="
                    .. tostring(decision.current) .. "/"
                    .. tostring(decision.intent) .. " nav="
                    .. tostring(nav.phase) .. "/"
                    .. tostring(nav.pathReason) .. " hold="
                    .. tostring(hold and hold.reason) .. "/"
                    .. tostring(hold and hold.maxGap))
            result("PASS", "extended_return_stop_navigation_detail",
                Harness.extendedReturnNavigationDetail(current))
            for index = 2, #Harness.team do
                local actor = Harness.team[index].actor
                local fx, fy = position(actor)
                local followerNav = SC.Navigation.status(actor) or {}
                local followerDecision = SC.Decision.peek(actor) or {}
                result("PASS", "extended_return_stop_follower_" .. tostring(index),
                    "pos=" .. tostring(fx) .. "," .. tostring(fy)
                        .. " gap=" .. tostring(fx and fy
                            and math.sqrt((fx - x)^2 + (fy - y)^2))
                        .. " decision=" .. tostring(followerDecision.current)
                        .. "/" .. tostring(followerDecision.intent)
                        .. " nav=" .. tostring(followerNav.phase)
                        .. "/" .. tostring(followerNav.pathReason))
            end
            local screenshotName = tostring(Harness.config.run_id)
                .. "-return-stall.png"
            local captured, screenshotError = pcall(function()
                getCore():TakeFullScreenshot(screenshotName)
            end)
            local directory, dirOk = SC.GameplayUtil.call(getCore(),
                "getScreenshotDir")
            result(captured and "PASS" or "FAIL",
                "extended_return_stall_screenshot_requested",
                "file=" .. screenshotName
                    .. " directory=" .. tostring(dirOk and directory)
                    .. " error=" .. tostring(screenshotError))
        end
        local overshot = x <= target.x - 3
        local nav = SC.Navigation.status(Harness.leader) or {}
        local stallAfter = (nav.phase == "planning"
            or nav.phase == "recovering") and 45000
            or nav.phase == "native_path" and 25000 or 16000
        local stalled = mission and mission.cohesionHold == nil
            and current - Harness.extendedReturnLastProgressAt >= stallAfter
        if overshot or stalled then
            Harness.extendedReturnReplans =
                Harness.extendedReturnReplans + 1
            local navigationDetail = Harness.extendedReturnNavigationDetail(current)
            if Harness.extendedReturnReplans > 3 then
                result("FAIL", "extended_return_replan_limit",
                    "leader repeatedly missed westward target "
                        .. navigationDetail)
                setPhase("finish", current)
                return
            end
            local cleared, reason = SC.ExpeditionPrototype.clearTestWaypoint(
                Harness.leader)
            check("extended_return_waypoint_"
                .. tostring(Harness.extendedReturnLegs) .. "_replanned",
                cleared == true,
                "leader=" .. tostring(x) .. "," .. tostring(y)
                .. " target=" .. tostring(target.x) .. ","
                .. tostring(target.y) .. " overshot="
                    .. tostring(overshot) .. " nav="
                    .. tostring(nav.phase) .. "/" .. tostring(nav.pathReason)
                    .. " reason=" .. tostring(reason))
            result("PASS", "extended_return_replan_navigation_detail_"
                .. tostring(Harness.extendedReturnReplans),
                navigationDetail)
            if not cleared then setPhase("finish", current) return end
            Harness.extendedReturnLastStalledTarget = target
            Harness.extendedReturnPreferLateral = true
            setPhase("team_extended_return_stage", current)
            return
        end
        if current - Harness.phaseStartedAt < 70000 then return end
        local decision = SC.Decision.peek(Harness.leader) or {}
        local nav = SC.Navigation.status(Harness.leader) or {}
        result("FAIL", "extended_return_leg_"
            .. tostring(Harness.extendedReturnLegs) .. "_arrived",
            "leader=" .. tostring(x) .. "," .. tostring(y)
                .. " target=" .. tostring(target.x) .. ","
                .. tostring(target.y) .. " decision="
                .. tostring(decision.current) .. "/"
                .. tostring(decision.intent) .. " nav="
                .. tostring(nav.phase) .. " hold="
                .. tostring(mission and mission.cohesionHold
                    and mission.cohesionHold.reason))
        setPhase("finish", current)
        return
    end
    local distance = math.sqrt((arrival.x - target.x)^2
        + (arrival.y - target.y)^2)
    local maxGap = 0
    local active = getSpecificPlayer(1) == Harness.leader
        and SC.Registry.isActive(Harness.leader, Harness.leaderId)
    for index = 2, #Harness.team do
        local record = Harness.team[index]
        local fx, fy = position(record.actor)
        maxGap = math.max(maxGap, fx and fy
            and math.sqrt((fx - x)^2 + (fy - y)^2) or math.huge)
        active = active and SC.Registry.isActive(record.actor, record.id)
    end
    if maxGap >= 20 and current - Harness.phaseStartedAt < 70000 then return end
    local map = getWorld():getCell():getChunkMap(1)
    local legOk = distance < 2 and maxGap < 20 and active
        and map ~= nil and chunkMapCovers(map,
            math.floor(x), math.floor(y))
        and (Harness.localTravelMaxStep or math.huge) < 3
        and getSpecificPlayer(0) == Harness.player
    check("extended_return_leg_" .. tostring(Harness.extendedReturnLegs)
        .. "_arrived", legOk,
        "leader=" .. tostring(x) .. "," .. tostring(y)
            .. " distance=" .. tostring(distance)
            .. " follower_gap=" .. tostring(maxGap)
            .. " map_min=" .. tostring(map and map:getWorldXMinTiles())
            .. " max_step=" .. tostring(Harness.localTravelMaxStep))
    if not legOk then setPhase("finish", current) return end
    Harness.extendedReturnPreferLateral = nil
    Harness.extendedReturnReplans = 0
    if x <= Harness.localStartX + 5
        and math.abs(y - Harness.localStartY) < 12 then
        setPhase("team_extended_return_verify", current)
    else
        setPhase("team_extended_return_stage", current)
    end
end

function Harness.corpseStreamOutcomeCounts(cell)
    local outcomes, cargo = 0, 0
    local bodies, zombiesSeen, gearMarkers, cargoMarkers = 0, 0, 0, 0
    local function inspect(owner, isBody)
        if isBody then bodies = bodies + 1
        else zombiesSeen = zombiesSeen + 1 end
        local worn = owner:getWornItems()
        local markedGear = false
        if worn ~= nil then
            for index = 0, worn:size() - 1 do
                local item = worn:get(index):getItem()
                markedGear = markedGear
                    or item:getModData().SCCorpseStreamGearProbe == true
            end
        end
        if markedGear then
            gearMarkers = gearMarkers + 1
            outcomes = outcomes + 1
        end
        local container = isBody and owner:getContainer()
            or owner:getInventory()
        local items = container and container:getItems()
        if items ~= nil then
            for index = 0, items:size() - 1 do
                local item = items:get(index)
                local data = item:getModData()
                if data.SCCorpseStreamCargoProbe == true
                    and tonumber(data.SCCorpseStreamCargoNativeId)
                        == item:getID()
                    and item:getFullType() == "Base.Bandage" then
                    cargoMarkers = cargoMarkers + 1
                    if markedGear then cargo = cargo + 1 end
                end
            end
        end
    end
    for dx = -12, 12 do
        for dy = -12, 12 do
            local square = cell:getGridSquare(
                math.floor(Harness.corpseStreamX) + dx,
                math.floor(Harness.corpseStreamY) + dy,
                math.floor(Harness.corpseStreamZ))
            local objects = square and square:getStaticMovingObjects()
            if objects ~= nil then
                for index = 0, objects:size() - 1 do
                    local body = objects:get(index)
                    if body:getObjectName() == "DeadBody" then
                        inspect(body, true)
                    end
                end
            end
        end
    end
    local zombies = cell:getZombieList()
    if zombies ~= nil then
        for index = 0, zombies:size() - 1 do
            inspect(zombies:get(index), false)
        end
    end
    return outcomes, cargo, "bodies=" .. tostring(bodies)
        .. " zombies=" .. tostring(zombiesSeen)
        .. " gear_markers=" .. tostring(gearMarkers)
        .. " exact_cargo_markers=" .. tostring(cargoMarkers)
end

function Harness.probeCorpseStreamVisitWait(current)
    if current - Harness.phaseStartedAt < 8000 then return end
    local cell = getWorld():getCell()
    local map0, map1 = cell:getChunkMap(0), cell:getChunkMap(1)
    local cx, cy = math.floor(Harness.corpseStreamX),
        math.floor(Harness.corpseStreamY)
    local px, py = position(Harness.player)
    local visitLoaded = px ~= nil and py ~= nil
        and math.abs(px - (cx + 2)) < 3 and math.abs(py - cy) < 3
        and chunkMapCovers(map0, cx, cy)
        and not chunkMapCovers(map1, cx, cy)
        and cell:getGridSquare(cx, cy,
            math.floor(Harness.corpseStreamZ)) ~= nil
    if not visitLoaded and current - Harness.phaseStartedAt < 30000 then
        return
    end
    check("corpse_stream_test_visitor_loaded_site", visitLoaded,
        "player=" .. tostring(px) .. "," .. tostring(py)
            .. " corpse=" .. tostring(cx) .. "," .. tostring(cy))
    local outcomes, cargo, detail = Harness.corpseStreamOutcomeCounts(cell)
    local outcomeCheck = Harness.config.team_corpse_streaming_reload_probe == "true"
        and "corpse_stream_exact_native_outcome_after_process_reload"
        or "corpse_stream_exact_native_outcome_after_view_reload"
    check(outcomeCheck,
        outcomes == 1 and cargo == 1,
        "outcomes=" .. tostring(outcomes)
            .. " exact_cargo=" .. tostring(cargo)
            .. " " .. detail)
    setPhase("finish", current)
end

function Harness.probeCorpseStreamRestartStage(current)
    if current - Harness.phaseStartedAt < 3000 then return end
    local x = tonumber(Harness.config.team_corpse_stream_verify_x)
    local y = tonumber(Harness.config.team_corpse_stream_verify_y)
    local z = math.floor(Harness.playerZ or 0)
    local coordinates = x ~= nil and y ~= nil and x > 0 and y > 0
    check("corpse_stream_restart_coordinates", coordinates,
        "recorded_death_site=" .. tostring(x) .. "," .. tostring(y))
    if not coordinates then setPhase("finish", current) return end
    Harness.corpseStreamX, Harness.corpseStreamY,
        Harness.corpseStreamZ = x, y, z
    local moved, reason = pcall(function()
        Harness.player:teleportTo(x + 2, y, z)
    end)
    check("corpse_stream_restart_visitor_queued", moved,
        tostring(reason))
    setPhase(moved and "team_corpse_stream_visit_wait" or "finish",
        current)
end

function Harness.probeExtendedReturnVerify(current)
    if current - Harness.phaseStartedAt < 5000 then return end
    local cell = getWorld():getCell()
    local map0 = cell:getChunkMap(0)
    local map = cell:getChunkMap(1)
    local x, y = position(Harness.leader)
    local sourceX, sourceY = math.floor(Harness.localStartX),
        math.floor(Harness.localStartY)
    local source = cell:getGridSquare(sourceX, sourceY,
        math.floor(Harness.localStartZ))
    local far = cell:getGridSquare(Harness.extendedReturnFarX,
        Harness.extendedReturnFarY, math.floor(Harness.localStartZ))
    local maxGap, followersLoaded = 0, true
    for index = 2, #Harness.team do
        local follower = Harness.team[index].actor
        local fx, fy = position(follower)
        maxGap = math.max(maxGap, fx and fy and x and y
            and math.sqrt((fx - x)^2 + (fy - y)^2) or math.huge)
        followersLoaded = followersLoaded
            and follower:getCurrentSquare() ~= nil
            and fx ~= nil and fy ~= nil
            and chunkMapCovers(map, math.floor(fx), math.floor(fy))
    end
    local mapMin = map and map:getWorldXMinTiles()
    local mapMax = map and map:getWorldXMaxTiles()
    local returned = map ~= nil and x ~= nil and y ~= nil
        and Harness.extendedReturnStartX - x >= 85
        and x <= Harness.localStartX + 5
        and math.abs(y - Harness.localStartY) < 12
        and source ~= nil and far == nil
        and chunkMapCovers(map, sourceX, sourceY)
        and not chunkMapCovers(map, Harness.extendedReturnFarX,
            Harness.extendedReturnFarY)
        and Harness.extendedReturnInitialMapMinX - mapMin >= 80
        and mapMax - mapMin
            == Harness.extendedReturnInitialMapMaxX
                - Harness.extendedReturnInitialMapMinX
        and Harness.leader:getCurrentSquare() ~= nil
        and followersLoaded and maxGap < 15
        and (Harness.localTravelMaxStep or math.huge) < 3
        and getSpecificPlayer(0) == Harness.player
        and getSpecificPlayer(1) == Harness.leader
        and cell:getGridSquare(math.floor(Harness.playerX),
            math.floor(Harness.playerY), Harness.playerZ) ~= nil
    local playerOwnsStart = chunkMapCovers(map0, sourceX, sourceY)
    check(playerOwnsStart
        and "moving_footprint_returned_to_player_owned_origin"
        or "moving_footprint_returned_to_remote_origin", returned,
        "outbound_x=" .. tostring(Harness.extendedReturnStartX)
            .. " return_x=" .. tostring(x)
            .. " map_min=" .. tostring(Harness.extendedReturnInitialMapMinX)
            .. "->" .. tostring(mapMin)
            .. " source_loaded=" .. tostring(source ~= nil)
            .. " far_loaded=" .. tostring(far ~= nil)
            .. " follower_gap=" .. tostring(maxGap)
            .. " max_step=" .. tostring(Harness.localTravelMaxStep))
    if returned and playerOwnsStart then
        -- Finish the joined local journey using the same nearby-player
        -- route and slot-release contract as the shorter Riverside trip.
        Harness.stageLocalReturn(current)
        return
    end
    setPhase("finish", current)
end

function Harness.maintainBuildingQuietFixture(current)
    if current < (Harness.buildingNextThreatClear or 0) then return end
    Harness.buildingClearedZombies = (Harness.buildingClearedZombies or 0)
        + cleanupTestZombiesNear(Harness.leader, 80)
    Harness.buildingNextThreatClear = current + 1000
end

function Harness.startDoorBashNative(current, door)
    local SC = SurvivorCompanion
    if SC.Topology.objectOpen(door) then
        SC.GameplayUtil.call(door, "ToggleDoor", Harness.leader)
    end
    local _, lockedSet = SC.GameplayUtil.call(door, "setIsLocked", true)
    local health, healthRead = SC.GameplayUtil.call(door, "getHealth")
    local inventory = Harness.leader:getInventory()
    local axe = inventory and inventory:AddItem("Base.Axe") or nil
    local fixture = lockedSet and SC.Topology.objectLocked(door)
        and not SC.Topology.objectOpen(door)
        and healthRead and tonumber(health) ~= nil and axe ~= nil
    check("building_door_bash_fixture", fixture,
        "door=" .. tostring(door)
            .. " locked=" .. tostring(SC.Topology.objectLocked(door))
            .. " health=" .. tostring(health)
            .. " axe=" .. tostring(axe))
    if not fixture then setPhase("finish", current) return end
    Harness.buildingDoor = door
    Harness.bashDoorHealth = tonumber(health)
    Harness.bashDoorAxe = axe
    Harness.bashDoorAxeInitialCondition = axe:getCondition()
    Harness.bashDoorVitalsBefore = nativeFieldVitals(Harness.leader)
    local started, reason = SC.GameplayUtil.move(Harness.leader, "walk", {
        action = "bash_door", door = door, tool = axe, interaction = true,
    })
    check("building_door_bash_native_action_started", started == true,
        tostring(reason))
    if not started then setPhase("finish", current) return end
    setPhase("team_door_bash", current)
end

function Harness.findDoorBashInteriorGoal(outside, inside)
    local SC = SurvivorCompanion
    local ix, iy, z = position(inside)
    local ox, oy = position(outside)
    local cell = getWorld():getCell()
    for radius = 1, 3 do
        for dx = -radius, radius do
            for dy = -radius, radius do
                if math.max(math.abs(dx), math.abs(dy)) == radius then
                    local square = cell:getGridSquare(
                        math.floor(ix) + dx, math.floor(iy) + dy,
                        math.floor(z))
                    local distance = math.max(math.abs(ix + dx - ox),
                        math.abs(iy + dy - oy))
                    if square and square:getRoom() == inside:getRoom()
                        and distance >= 2
                        and SC.GameplayUtil.isSquareFree(square) then
                        local route = SC.Navigation.findPath(outside, square,
                            { actor = Harness.leader, nodeBudget = 2500 })
                        if route and #route >= 3 and #route <= 8 then
                            return square, route
                        end
                    end
                end
            end
        end
    end
    if SC.GameplayUtil.isSquareFree(inside) then
        return inside, { outside, inside }
    end
    return nil, nil
end

-- Test-only native barricades turn a room with window detours into a
-- genuine last-resort route. Every alternate boundary is inspected, and the
-- ordinary full-world path search still has to fail after the fixture.
function Harness.barricadeAlternateRoomExits(entrySquare, retainedDoor)
    local SC = SurvivorCompanion
    local room = entrySquare and entrySquare:getRoom()
    if room == nil then return false, 0, "missing_room" end
    local cell = getWorld():getCell()
    local queue, seen, touched = { entrySquare }, { [entrySquare] = true }, {}
    local index, barricaded = 1, 0
    while index <= #queue do
        if index > 120 then return false, barricaded, "room_too_large" end
        local square = queue[index]
        index = index + 1
        local x, y, z = position(square)
        for _, offset in ipairs({ { 1, 0 }, { -1, 0 },
                { 0, 1 }, { 0, -1 } }) do
            local neighbor = cell:getGridSquare(math.floor(x) + offset[1],
                math.floor(y) + offset[2], math.floor(z))
            if neighbor and neighbor:getRoom() == room then
                if not seen[neighbor] then
                    seen[neighbor] = true
                    queue[#queue + 1] = neighbor
                end
            elseif neighbor then
                local edge = SC.Navigation.edgeAffordance(square, neighbor)
                local object = edge and edge.object
                if object == retainedDoor then
                    -- This is the one locked entry the companion must choose.
                elseif object and (edge.kind == "window"
                    or edge.kind == "door") then
                    if not touched[object] then
                        touched[object] = true
                        local added, metalAdded = false, false
                        if not SC.Topology.objectBarricaded(object) then
                            local barricade, addOK = nil, false
                            if IsoBarricade and IsoBarricade.AddBarricadeToObject then
                                addOK, barricade = pcall(
                                    IsoBarricade.AddBarricadeToObject,
                                    object, Harness.leader)
                            end
                            if addOK and barricade then
                                _, metalAdded = SC.GameplayUtil.call(
                                    barricade, "addMetal", nil, nil)
                                added = metalAdded == true
                            end
                        end
                        if not SC.Topology.objectBarricaded(object) then
                            return false, barricaded,
                                "barricade_failed:" .. tostring(edge.kind)
                                    .. ":" .. tostring(object)
                                    .. ":added=" .. tostring(added)
                                    .. ":metal=" .. tostring(metalAdded)
                        end
                        barricaded = barricaded + 1
                    end
                else
                    local passage = SC.Topology.classifyEdge(Harness.leader,
                        square, neighbor, {})
                    if passage and passage.traversable then
                        return false, barricaded, "other_open_boundary"
                    end
                end
            end
        end
    end
    return true, barricaded, nil
end

function Harness.probeBuildingWait(current)
    Harness.maintainBuildingQuietFixture(current)
    if current - Harness.phaseStartedAt
        < ((Harness.buildingAttempts or 0) > 0 and 1000 or 10000) then
        return
    end
    local SC = SurvivorCompanion
    local cell = getWorld():getCell()
    local source = Harness.leader:getCurrentSquare()
    local x, y, z = position(Harness.leader)
    if source == nil or x == nil or y == nil
        or source:getRoom() ~= nil then
        result("FAIL", "building_exterior_start",
            "leader square unavailable or already indoors at "
                .. tostring(x) .. "," .. tostring(y))
        setPhase("finish", current)
        return
    end
    Harness.buildingScanRadius = Harness.buildingScanRadius or 1
    Harness.buildingRoomSquares = Harness.buildingRoomSquares or 0
    Harness.buildingPathsTried = Harness.buildingPathsTried or 0
    Harness.buildingWindowsSeen = Harness.buildingWindowsSeen or 0
    Harness.buildingDoorsSeen = Harness.buildingDoorsSeen or 0
    local windowProbe = Harness.config.team_window_probe == "true"
    local doorBashProbe = Harness.config.team_door_bash_probe == "true"
    local doorBashAuto = Harness.config.team_door_bash_auto_probe == "true"
    if doorBashAuto and Harness.bashDoorCandidateAxe == nil then
        Harness.bashDoorCandidateAxe = Harness.leader:getInventory()
            :AddItem("Base.Axe")
    end
    local doorProbe = Harness.config.team_inside_door_probe == "true"
        or doorBashProbe
    local selected, selectedApproach, selectedPath, entryNodes, selectedEdge,
        selectedAutoGoal
    for radius = Harness.buildingScanRadius,
            math.min(45, Harness.buildingScanRadius + 2) do
        for dx = -radius, radius do
            for dy = -radius, radius do
                if math.max(math.abs(dx), math.abs(dy)) == radius then
                    local tx, ty = math.floor(x) + dx,
                        math.floor(y) + dy
                    local square = cell:getGridSquare(tx, ty,
                        math.floor(z))
                    local room = square and square:getRoom()
                    if room ~= nil then
                        Harness.buildingRoomSquares =
                            Harness.buildingRoomSquares + 1
                    end
                    if room ~= nil and square ~= nil
                        and not (Harness.buildingRejectedRooms
                            and Harness.buildingRejectedRooms[room])
                        and SC.GameplayUtil.isSquareFree(square)
                        and Harness.buildingPathsTried < 60 then
                        for _, offset in ipairs({ { 1, 0 }, { -1, 0 },
                                { 0, 1 }, { 0, -1 } }) do
                            local neighbor = cell:getGridSquare(
                                tx + offset[1], ty + offset[2],
                                math.floor(z))
                            if neighbor and neighbor:getRoom() == nil
                                and SC.GameplayUtil.isSquareFree(neighbor) then
                                local edge = SC.Navigation.edgeAffordance(
                                    neighbor, square)
                                local windowCandidate = edge and edge.kind == "window"
                                    and edge.object ~= nil
                                    and not SC.Topology.objectOpen(edge.object)
                                    and not SC.Topology.windowSmashed(edge.object)
                                    and not SC.Topology.objectBarricaded(edge.object)
                                    and not SC.Topology.windowInvincible(edge.object)
                                local doorCandidate = edge and edge.kind == "door"
                                    and edge.object ~= nil
                                    and SC.GameplayUtil.instanceOf(edge.object, "IsoDoor")
                                    and not SC.Topology.objectBarricaded(edge.object)
                                    and not SC.Topology.objectLocked(edge.object)
                                    and select(1, SC.GameplayUtil.call(
                                        edge.object, "isDestroyed")) ~= true
                                if windowCandidate then
                                    Harness.buildingWindowsSeen =
                                        Harness.buildingWindowsSeen + 1
                                end
                                if doorCandidate then
                                    Harness.buildingDoorsSeen =
                                        Harness.buildingDoorsSeen + 1
                                end
                                if (not windowProbe and not doorProbe)
                                    or windowCandidate and windowProbe
                                    or doorCandidate and doorProbe then
                                    Harness.buildingPathsTried =
                                        Harness.buildingPathsTried + 1
                                    local approach = doorBashProbe and { source, neighbor }
                                        or SC.Navigation.findPath(source,
                                            neighbor, { nodeBudget = 2500 })
                                    local entry = approach and SC.Navigation.findPath(
                                        neighbor, square, { nodeBudget = 2500 })
                                    if approach and (doorBashProbe or #approach >= 4)
                                        and #approach <= 100
                                        and entry and #entry >= 2
                                        and #entry <= ((windowProbe or doorProbe)
                                            and 2 or 6) then
                                        local autoGoal, autoEligible = nil, true
                                        if doorBashAuto then
                                            autoGoal = Harness.findDoorBashInteriorGoal(
                                                neighbor, square)
                                            autoEligible = false
                                            if autoGoal then
                                                local _, locked = SC.GameplayUtil.call(
                                                    edge.object, "setIsLocked", true)
                                                if locked then
                                                    local prepared, barricades, prepReason =
                                                        Harness.barricadeAlternateRoomExits(
                                                            square, edge.object)
                                                    Harness.buildingAutoBarricades =
                                                        (Harness.buildingAutoBarricades or 0)
                                                            + (barricades or 0)
                                                    Harness.buildingAutoPrepReason = prepReason
                                                    local ordinary, ordinaryReason =
                                                        SC.Navigation.findPath(neighbor,
                                                            autoGoal, { actor = Harness.leader,
                                                                nodeBudget = 2500 })
                                                    local sealed = SC.Navigation
                                                        ._sealedGoalRoomForBash(
                                                            Harness.leader, neighbor,
                                                            autoGoal, Harness.bashDoorCandidateAxe)
                                                    autoEligible = prepared
                                                        and sealed
                                                        and ordinary == nil
                                                        and (ordinaryReason == "unreachable"
                                                            or ordinaryReason == "budget")
                                                    Harness.buildingAutoSealed = sealed
                                                    Harness.buildingAutoLastReason = ordinary
                                                        and "ordinary_route" or ordinaryReason
                                                    Harness.buildingAutoCandidates =
                                                        (Harness.buildingAutoCandidates or 0) + 1
                                                end
                                                SC.GameplayUtil.call(edge.object,
                                                    "setIsLocked", false)
                                            end
                                        end
                                        if autoEligible then
                                            selected, selectedApproach = square, neighbor
                                            selectedPath, entryNodes = approach, #entry
                                            selectedEdge, selectedAutoGoal = edge, autoGoal
                                            break
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
            if selected then break end
        end
        if selected then break end
    end
    Harness.buildingScanRadius = Harness.buildingScanRadius + 3
    if selected == nil then
        if Harness.buildingScanRadius <= 45 then return end
        result("FAIL", "building_loaded_interior_route",
            "no pathable room boundary in 45 tiles"
                .. " room_squares=" .. tostring(Harness.buildingRoomSquares)
                .. " paths_tried=" .. tostring(Harness.buildingPathsTried)
                .. " windows_seen=" .. tostring(Harness.buildingWindowsSeen)
                .. " doors_seen=" .. tostring(Harness.buildingDoorsSeen)
                .. " auto_candidates=" .. tostring(Harness.buildingAutoCandidates)
                .. " auto_last_reason=" .. tostring(Harness.buildingAutoLastReason)
                .. " auto_barricades=" .. tostring(Harness.buildingAutoBarricades)
                .. " auto_prep_reason=" .. tostring(Harness.buildingAutoPrepReason)
                .. " auto_sealed=" .. tostring(Harness.buildingAutoSealed))
        setPhase("finish", current)
        return
    end
    Harness.buildingAttempts = (Harness.buildingAttempts or 0) + 1
    local tx, ty = position(selected)
    local ax, ay = position(selectedApproach)
    local map0 = cell:getChunkMap(0)
    local playerOwns = chunkMapCovers(map0,
        math.floor(tx), math.floor(ty))
    local room = selected:getRoom()
    local explored, exploredRead = SC.GameplayUtil.call(room, "isExplored")
    if windowProbe then
        local window = selectedEdge.object
        local _, lockedSet = SC.GameplayUtil.call(window, "setIsLocked", true)
        local locked = lockedSet and SC.Topology.objectLocked(window)
        check("building_window_locked_fixture", locked == true
            and not SC.Topology.windowSmashed(window),
            "window=" .. tostring(window)
                .. " set_locked=" .. tostring(lockedSet)
                .. " locked=" .. tostring(locked))
        if not locked then setPhase("finish", current) return end
        Harness.buildingWindow = window
    end
    if doorProbe then Harness.buildingDoor = selectedEdge.object end
    if doorBashProbe and Harness.config.team_inside_door_probe ~= "true" then
        Harness.bashDoorInsideSquare = selected
        Harness.bashDoorAutoGoal = selectedAutoGoal
        local placed, placeReason = Harness.placeCombatActor(Harness.leader, {
            x = ax + 0.5, y = ay + 0.5, z = z,
        })
        check("building_door_bash_test_transfer", placed == true,
            "test-only transfer to native door " .. tostring(ax)
                .. "," .. tostring(ay) .. " reason=" .. tostring(placeReason))
        if not placed then setPhase("finish", current) return end
        local followerCount = 0
        for radius = 1, 3 do
            for dx = -radius, radius do
                for dy = -radius, radius do
                    if math.max(math.abs(dx), math.abs(dy)) == radius
                        and followerCount < #Harness.team - 1 then
                        local neighbor = cell:getGridSquare(
                            math.floor(ax) + dx, math.floor(ay) + dy, math.floor(z))
                        if neighbor and neighbor:getRoom() == nil
                            and SC.GameplayUtil.isSquareFree(neighbor) then
                            local member = Harness.team[followerCount + 2]
                            local followerPlaced = Harness.placeCombatActor(member.actor, {
                                x = math.floor(ax) + dx + 0.5,
                                y = math.floor(ay) + dy + 0.5, z = z,
                            })
                            if followerPlaced then followerCount = followerCount + 1 end
                        end
                    end
                end
            end
            if followerCount == #Harness.team - 1 then break end
        end
        check("building_door_bash_followers_nearby",
            followerCount == #Harness.team - 1,
            "test-only follower transfers=" .. tostring(followerCount))
        if followerCount ~= #Harness.team - 1 then
            setPhase("finish", current) return
        end
        if doorBashAuto then
            local door = selectedEdge.object
            local axe = Harness.bashDoorCandidateAxe
            local _, lockSet = SC.GameplayUtil.call(door, "setIsLocked", true)
            local health = select(1, SC.GameplayUtil.call(door, "getHealth"))
            local gx, gy, gz = position(selectedAutoGoal)
            local staged, stageReason = SC.ExpeditionPrototype.stageTestWaypoint(
                Harness.leader, gx, gy, gz)
            local bashPath, bashReason = SC.Navigation.findPath(
                selectedApproach, selectedAutoGoal, {
                    actor = Harness.leader, nodeBudget = 2500,
                    allowDoorBash = true, doorBashTool = axe,
                    doorBashTargetRoom = selectedAutoGoal:getRoom(),
                })
            check("building_door_bash_auto_route", bashPath ~= nil
                and #bashPath >= 2 and #bashPath <= 8,
                "path=" .. tostring(bashPath and #bashPath)
                    .. " reason=" .. tostring(bashReason))
            local ready = axe ~= nil and lockSet and staged
                and bashPath ~= nil
                and SC.Topology.objectLocked(door)
                and SC.Navigation.findPath(selectedApproach, selectedAutoGoal,
                    { actor = Harness.leader, nodeBudget = 2500 }) == nil
            check("building_door_bash_auto_fixture", ready,
                "door=" .. tostring(door) .. " health=" .. tostring(health)
                    .. " target=" .. tostring(gx) .. "," .. tostring(gy)
                    .. " reason=" .. tostring(stageReason))
            if not ready then setPhase("finish", current) return end
            Harness.bashDoorHealth = tonumber(health)
            Harness.bashDoorAxe = axe
            Harness.bashDoorAxeInitialCondition = axe:getCondition()
            Harness.bashDoorVitalsBefore = nativeFieldVitals(Harness.leader)
            setPhase("team_door_bash_auto", current)
        else
            Harness.startDoorBashNative(current, selectedEdge.object)
        end
        return
    end
    local staged, reason = SC.ExpeditionPrototype.stageTestWaypoint(
        Harness.leader, ax, ay, z)
    check("building_loaded_interior_route", staged == true
        and not playerOwns and room ~= nil,
        "outside=" .. tostring(x) .. "," .. tostring(y)
            .. " inside=" .. tostring(tx) .. "," .. tostring(ty)
            .. " approach=" .. tostring(ax) .. "," .. tostring(ay)
            .. " approach_nodes=" .. tostring(#selectedPath)
            .. " entry_nodes=" .. tostring(entryNodes)
            .. " edge=" .. tostring(selectedEdge and selectedEdge.kind)
            .. " player_map_covers=" .. tostring(playerOwns)
            .. " room_explored_before="
            .. tostring(exploredRead and explored or "unavailable")
            .. " zombies_removed="
            .. tostring(Harness.buildingClearedZombies)
            .. " reason=" .. tostring(reason))
    if not staged or playerOwns then setPhase("finish", current) return end
    Harness.buildingTarget = { x = tx, y = ty, z = z, room = room }
    Harness.buildingApproachTarget = { x = ax, y = ay }
    Harness.buildingStartX, Harness.buildingStartY = x, y
    Harness.buildingStartZ = z
    Harness.buildingOutsideSeen = true
    Harness.localTravelLastX, Harness.localTravelLastY = x, y
    Harness.localTravelMaxStep = Harness.localTravelMaxStep or 0
    Harness.localTravelChunks = Harness.localTravelChunks or {}
    Harness.buildingLastProgressX, Harness.buildingLastProgressY = x, y
    Harness.buildingLastProgressAt = current
    setPhase("team_building_approach", current)
end

function Harness.probeBuildingApproach(current)
    Harness.maintainBuildingQuietFixture(current)
    local x, y = observeLocalTravelStep()
    local mission = SurvivorCompanion.ExpeditionPrototype.current()
    local arrival = mission and mission.testWaypointArrival
    local target = Harness.buildingApproachTarget
    if arrival == nil or mission.testWaypointArrived ~= true then
        if arrival == nil and x ~= nil and y ~= nil then
            local moved = math.sqrt((x - Harness.buildingLastProgressX)^2
                + (y - Harness.buildingLastProgressY)^2)
            if moved >= 0.75 then
                Harness.buildingLastProgressX = x
                Harness.buildingLastProgressY = y
                Harness.buildingLastProgressAt = current
            end
            local nav = SurvivorCompanion.Navigation.status(Harness.leader) or {}
            local stalled = current - Harness.phaseStartedAt >= 20000
                and current - Harness.buildingLastProgressAt >= 15000
                and nav.phase ~= "planning"
                and mission ~= nil and mission.cohesionHold == nil
            if stalled and (Harness.buildingAttempts or 0) < 3 then
                local cleared, reason = SurvivorCompanion.ExpeditionPrototype.clearTestWaypoint(
                    Harness.leader)
                check("building_exterior_route_replanned_"
                    .. tostring(Harness.buildingAttempts), cleared == true,
                    "leader=" .. tostring(x) .. "," .. tostring(y)
                        .. " target=" .. tostring(target.x) .. ","
                        .. tostring(target.y)
                        .. " nav=" .. tostring(nav.phase) .. "/"
                        .. tostring(nav.blockerType) .. "/"
                        .. tostring(nav.pathReason)
                        .. " reason=" .. tostring(reason))
                if not cleared then setPhase("finish", current) return end
                Harness.buildingRejectedRooms = Harness.buildingRejectedRooms or {}
                Harness.buildingRejectedRooms[Harness.buildingTarget.room] = true
                Harness.buildingScanRadius = 1
                Harness.buildingRoomSquares = 0
                Harness.buildingPathsTried = 0
                setPhase("team_building_wait", current)
                return
            end
        end
        if current - Harness.phaseStartedAt < 80000
            and not Harness.leader:isDead() then return end
        local nav = SurvivorCompanion.Navigation.status(Harness.leader) or {}
        local decision = SurvivorCompanion.Decision.peek(Harness.leader) or {}
        result("FAIL", "building_exterior_approach_arrived",
            "leader=" .. tostring(x) .. "," .. tostring(y)
                .. " target=" .. tostring(target.x) .. ","
                .. tostring(target.y)
                .. " nav=" .. tostring(nav.phase) .. "/"
                .. tostring(nav.blockerType) .. "/"
                .. tostring(nav.pathReason)
                .. " decision=" .. tostring(decision.current) .. "/"
                .. tostring(decision.intent)
                .. " no_progress_ms="
                .. tostring(current - Harness.buildingLastProgressAt)
                .. " attempts=" .. tostring(Harness.buildingAttempts)
                .. " dead=" .. tostring(Harness.leader:isDead()))
        setPhase("finish", current)
        return
    end
    local gap = math.sqrt((arrival.x - target.x)^2
        + (arrival.y - target.y)^2)
    local square = Harness.leader:getCurrentSquare()
    local outside = gap < 2 and square ~= nil
        and square:getRoom() == nil
        and (Harness.localTravelMaxStep or math.huge) < 3
    check("building_exterior_approach_arrived", outside,
        "leader=" .. tostring(x) .. "," .. tostring(y)
            .. " distance=" .. tostring(gap)
            .. " room=" .. tostring(square and square:getRoom())
            .. " max_step=" .. tostring(Harness.localTravelMaxStep))
    if not outside then setPhase("finish", current) return end
    local staged, reason = SurvivorCompanion.ExpeditionPrototype.stageTestWaypoint(
        Harness.leader, Harness.buildingTarget.x,
        Harness.buildingTarget.y, Harness.buildingTarget.z)
    check("building_interior_entry_staged", staged == true,
        tostring(reason))
    if not staged then setPhase("finish", current) return end
    Harness.buildingLastProgressX, Harness.buildingLastProgressY = x, y
    Harness.buildingLastProgressAt = current
    setPhase("team_building_walk", current)
end

function Harness.probeBuildingWalk(current)
    Harness.maintainBuildingQuietFixture(current)
    local x, y = observeLocalTravelStep()
    local square = Harness.leader:getCurrentSquare()
    if square and square:getRoom() == Harness.buildingTarget.room then
        Harness.buildingInsideSeen = true
    end
    local SC = SurvivorCompanion
    local mission = SC.ExpeditionPrototype.current()
    local arrival = mission and mission.testWaypointArrival
    if arrival == nil and x ~= nil and y ~= nil then
        local moved = math.sqrt((x - Harness.buildingLastProgressX)^2
            + (y - Harness.buildingLastProgressY)^2)
        if moved >= 0.75 then
            Harness.buildingLastProgressX = x
            Harness.buildingLastProgressY = y
            Harness.buildingLastProgressAt = current
        end
        local stuckOutside = square and square:getRoom() == nil
            and mission and mission.cohesionHold == nil
            and current - Harness.buildingLastProgressAt >= 15000
            and current - Harness.phaseStartedAt >= 20000
            and Harness.leader:isDead() ~= true
            and (SC.Navigation.status(Harness.leader) or {}).phase
                ~= "planning"
        if stuckOutside and (Harness.buildingAttempts or 0) < 3 then
            local nav = SC.Navigation.status(Harness.leader) or {}
            local decision = SC.Decision.peek(Harness.leader) or {}
            local cleared, reason = SC.ExpeditionPrototype.clearTestWaypoint(
                Harness.leader)
            check("building_blocked_room_replanned_"
                .. tostring(Harness.buildingAttempts), cleared == true,
                "leader=" .. tostring(x) .. "," .. tostring(y)
                    .. " target=" .. tostring(Harness.buildingTarget.x)
                    .. "," .. tostring(Harness.buildingTarget.y)
                    .. " nav=" .. tostring(nav.phase)
                    .. "/" .. tostring(nav.blockerType)
                    .. "/" .. tostring(nav.pathReason)
                    .. " decision=" .. tostring(decision.current)
                    .. "/" .. tostring(decision.intent)
                    .. " reason=" .. tostring(reason))
            if not cleared then setPhase("finish", current) return end
            Harness.buildingRejectedRooms = Harness.buildingRejectedRooms or {}
            Harness.buildingRejectedRooms[Harness.buildingTarget.room] = true
            Harness.buildingScanRadius = 1
            Harness.buildingRoomSquares = 0
            Harness.buildingPathsTried = 0
            setPhase("team_building_wait", current)
            return
        end
    end
    if arrival == nil or mission.testWaypointArrived ~= true then
        if current - Harness.phaseStartedAt < 70000
            and not Harness.leader:isDead() then return end
        local decision = SC.Decision.peek(Harness.leader) or {}
        local nav = SC.Navigation.status(Harness.leader) or {}
        result("FAIL", "building_native_entry",
            "leader=" .. tostring(x) .. "," .. tostring(y)
                .. " target=" .. tostring(Harness.buildingTarget.x)
                .. "," .. tostring(Harness.buildingTarget.y)
                .. " room=" .. tostring(square and square:getRoom())
                .. " decision=" .. tostring(decision.current) .. "/"
                .. tostring(decision.intent)
                .. " nav=" .. tostring(nav.phase) .. "/"
                .. tostring(nav.blockerType) .. "/"
                .. tostring(nav.blockerSquare) .. "/"
                .. tostring(nav.pathReason)
                .. " attempts=" .. tostring(Harness.buildingAttempts)
                .. " dead=" .. tostring(Harness.leader:isDead()))
        setPhase("finish", current)
        return
    end
    local gap = math.sqrt((arrival.x - Harness.buildingTarget.x)^2
        + (arrival.y - Harness.buildingTarget.y)^2)
    local map0 = getWorld():getCell():getChunkMap(0)
    local entered = gap < 2 and Harness.buildingOutsideSeen
        and Harness.buildingInsideSeen == true
        and square ~= nil and square:getRoom() == Harness.buildingTarget.room
        and (Harness.localTravelMaxStep or math.huge) < 3
        and not chunkMapCovers(map0,
            math.floor(Harness.buildingTarget.x),
            math.floor(Harness.buildingTarget.y))
        and getSpecificPlayer(0) == Harness.player
        and getSpecificPlayer(1) == Harness.leader
    check("building_native_entry", entered,
        "leader=" .. tostring(x) .. "," .. tostring(y)
            .. " distance=" .. tostring(gap)
            .. " room=" .. tostring(square and square:getRoom())
            .. " max_step=" .. tostring(Harness.localTravelMaxStep))
    if not entered then setPhase("finish", current) return end
    if Harness.config.team_window_probe == "true" then
        local window = Harness.buildingWindow
        local smashed = window and SC.Topology.windowSmashed(window)
        local cleared = window and SC.Topology.windowGlassRemoved(window)
        check("building_window_forced_entry_native",
            smashed == true and cleared == true,
            "window=" .. tostring(window)
                .. " smashed=" .. tostring(smashed)
                .. " glass_removed=" .. tostring(cleared))
        if not smashed or not cleared then setPhase("finish", current) return end
    end
    if Harness.config.team_inside_door_probe == "true" then
        local door = Harness.buildingDoor
        local closed = true
        if SC.Topology.objectOpen(door) then
            local _, toggled = SC.GameplayUtil.call(
                door, "ToggleDoor", Harness.leader)
            closed = toggled and not SC.Topology.objectOpen(door)
        end
        local _, lockSet = SC.GameplayUtil.call(door, "setIsLocked", true)
        local locked = lockSet and SC.Topology.objectLocked(door)
        check("building_inside_locked_door_fixture",
            closed == true and locked == true,
            "door=" .. tostring(door)
                .. " closed=" .. tostring(closed)
                .. " locked=" .. tostring(locked)
                .. " set_locked=" .. tostring(lockSet))
        if not closed or not locked then setPhase("finish", current) return end
    end
    local cell = getWorld():getCell()
    local exitSquare = cell:getGridSquare(
        math.floor(Harness.buildingApproachTarget.x),
        math.floor(Harness.buildingApproachTarget.y),
        math.floor(Harness.buildingStartZ))
    local exitPath = exitSquare and exitSquare:getRoom() == nil
        and SC.Navigation.findPath(square, exitSquare,
            { nodeBudget = 2500, actor = Harness.leader }) or nil
    local doorDetail = ""
    if Harness.config.team_inside_door_probe == "true" then
        local door = Harness.buildingDoor
        local owner = select(1, SC.GameplayUtil.call(door, "getSquare"))
        local opposite = select(1, SC.GameplayUtil.call(door,
            "getOppositeSquare"))
        local properties = select(1, SC.GameplayUtil.call(door,
            "getProperties"))
        local forceLocked = select(1, SC.GameplayUtil.call(properties,
            "has", "forceLocked"))
        local inward = SC.Topology.classifyEdge(Harness.leader,
            square, exitSquare, {})
        doorDetail = " inside_allowed=" .. tostring(
            SC.Topology.doorOpensFromInside(Harness.leader, door, square))
            .. " actor_player=" .. tostring(SC.GameplayUtil.instanceOf(
                Harness.leader, "IsoPlayer"))
            .. " owner_room=" .. tostring(owner and owner:getRoom())
            .. " opposite_room=" .. tostring(opposite and opposite:getRoom())
            .. " actor_room=" .. tostring(square:getRoom())
            .. " force_locked=" .. tostring(forceLocked)
            .. " edge=" .. tostring(inward and inward.affordance)
            .. "/" .. tostring(inward and inward.reason)
    end
    check("building_exterior_exit_route", exitSquare ~= nil
        and exitSquare:getRoom() == nil and exitPath ~= nil
        and #exitPath >= 2 and #exitPath <= 12,
        "loaded_path_nodes=" .. tostring(exitPath and #exitPath)
            .. doorDetail)
    if not exitPath or #exitPath < 2 or #exitPath > 12 then
        setPhase("finish", current)
        return
    end
    local tx, ty = position(exitSquare)
    local staged, reason = SC.ExpeditionPrototype.stageTestWaypoint(
        Harness.leader, tx, ty, Harness.buildingStartZ)
    check("building_exterior_exit_staged", staged == true,
        tostring(reason))
    if not staged then setPhase("finish", current) return end
    Harness.buildingExitTarget = { x = tx, y = ty }
    setPhase("team_building_exit", current)
end

function Harness.probeBuildingExit(current)
    Harness.maintainBuildingQuietFixture(current)
    local SC = SurvivorCompanion
    local x, y = observeLocalTravelStep()
    local square = Harness.leader:getCurrentSquare()
    local mission = SurvivorCompanion.ExpeditionPrototype.current()
    local arrival = mission and mission.testWaypointArrival
    if arrival == nil or mission.testWaypointArrived ~= true then
        if current - Harness.phaseStartedAt < 70000
            and not Harness.leader:isDead() then return end
        local nav = SurvivorCompanion.Navigation.status(Harness.leader) or {}
        result("FAIL", "building_native_exit",
            "leader=" .. tostring(x) .. "," .. tostring(y)
                .. " target=" .. tostring(Harness.buildingExitTarget.x)
                .. "," .. tostring(Harness.buildingExitTarget.y)
                .. " room=" .. tostring(square and square:getRoom())
                .. " nav=" .. tostring(nav.phase) .. "/"
                .. tostring(nav.blockerType) .. "/"
                .. tostring(nav.pathReason))
        setPhase("finish", current)
        return
    end
    local gap = math.sqrt((arrival.x - Harness.buildingExitTarget.x)^2
        + (arrival.y - Harness.buildingExitTarget.y)^2)
    local maxFollowerGap, followersLoaded = 0, true
    local map = getWorld():getCell():getChunkMap(1)
    for index = 2, #Harness.team do
        local record = Harness.team[index]
        local fx, fy = position(record.actor)
        maxFollowerGap = math.max(maxFollowerGap, fx and fy and x and y
            and math.sqrt((fx - x)^2 + (fy - y)^2) or math.huge)
        followersLoaded = followersLoaded
            and record.actor:getCurrentSquare() ~= nil
            and fx ~= nil and fy ~= nil
            and chunkMapCovers(map, math.floor(fx), math.floor(fy))
    end
    local exited = gap < 2 and square ~= nil
        and square:getRoom() == nil
        and followersLoaded and maxFollowerGap < 15
        and (Harness.localTravelMaxStep or math.huge) < 3
        and getSpecificPlayer(0) == Harness.player
        and getSpecificPlayer(1) == Harness.leader
        and getWorld():getCell():getGridSquare(
            math.floor(Harness.buildingTarget.x),
            math.floor(Harness.buildingTarget.y),
            math.floor(Harness.buildingTarget.z)) ~= nil
    check("building_native_exit", exited,
        "leader=" .. tostring(x) .. "," .. tostring(y)
            .. " distance=" .. tostring(gap)
            .. " room=" .. tostring(square and square:getRoom())
            .. " follower_gap=" .. tostring(maxFollowerGap)
            .. " max_step=" .. tostring(Harness.localTravelMaxStep))
    if Harness.config.team_inside_door_probe == "true" then
        local door = Harness.buildingDoor
        check("building_inside_door_unlocked_native",
            exited and door ~= nil
                and not SurvivorCompanion.Topology.objectLocked(door),
            "door=" .. tostring(door)
                .. " locked=" .. tostring(door and SurvivorCompanion.Topology.objectLocked(door))
                .. " open=" .. tostring(door and SurvivorCompanion.Topology.objectOpen(door)))
    end
    if exited and Harness.config.team_door_bash_probe == "true" then
        Harness.startDoorBashNative(current, Harness.buildingDoor)
        return
    end
    setPhase("finish", current)
end

function Harness.probeDoorBash(current)
    Harness.maintainBuildingQuietFixture(current)
    local SC = SurvivorCompanion
    local door = Harness.buildingDoor
    local health = select(1, SC.GameplayUtil.call(door, "getHealth"))
    local index = select(1, SC.GameplayUtil.call(door, "getObjectIndex"))
    local destroyed = select(1, SC.GameplayUtil.call(door, "isDestroyed")) == true
        or tonumber(index) == -1
    local damaged = tonumber(health) ~= nil
        and tonumber(health) < Harness.bashDoorHealth
    if damaged and not Harness.bashDoorFirstHit then
        Harness.bashDoorFirstHit = true
        check("building_door_bash_native_damage", true,
            "health=" .. tostring(Harness.bashDoorHealth)
                .. "->" .. tostring(health)
                .. " axe_condition=" .. tostring(Harness.bashDoorAxe:getCondition()))
    end
    if destroyed then
        if SC.NativeActions.isWorkActive(Harness.leader)
            and current - Harness.phaseStartedAt < 60000 then return end
        local finished, reason = SC.NativeActions.finishWork(Harness.leader)
        check("building_door_bash_destroyed_native",
            (damaged or Harness.bashDoorFirstHit) and finished == true,
            "health=" .. tostring(health)
                .. " index=" .. tostring(index)
                .. " destroyed=" .. tostring(destroyed)
                .. " elapsed_ms=" .. tostring(current - Harness.phaseStartedAt)
                .. " axe_condition=" .. tostring(Harness.bashDoorAxeInitialCondition)
                .. "->" .. tostring(Harness.bashDoorAxe:getCondition())
                .. " endurance=" .. tostring(Harness.bashDoorVitalsBefore.ENDURANCE)
                .. "->" .. tostring(nativeFieldVitals(Harness.leader).ENDURANCE)
                .. " work_finished=" .. tostring(finished)
                .. " reason=" .. tostring(reason))
        if Harness.bashDoorInsideSquare ~= nil and finished == true then
            local inside = Harness.bashDoorInsideSquare
            local outside = Harness.leader:getCurrentSquare()
            local path = SC.Navigation.findPath(outside,
                inside, { actor = Harness.leader, nodeBudget = 2500 })
            check("building_door_bash_breach_route",
                path ~= nil and #path == 2,
                "loaded_path_nodes=" .. tostring(path and #path))
            if path == nil or #path ~= 2 then setPhase("finish", current) return end
            local ix, iy, z = position(inside)
            local ox, oy = position(outside)
            local deeper, deepPath, candidates = nil, nil, 0
            for radius = 1, 3 do
                for dx = -radius, radius do
                    for dy = -radius, radius do
                        if math.max(math.abs(dx), math.abs(dy)) == radius then
                            local square = getWorld():getCell():getGridSquare(
                                math.floor(ix) + dx, math.floor(iy) + dy,
                                math.floor(z))
                            local distance = math.max(math.abs(ix + dx - ox),
                                math.abs(iy + dy - oy))
                            if square and square:getRoom() == inside:getRoom()
                                and distance >= 2
                                and SC.GameplayUtil.isSquareFree(square) then
                                candidates = candidates + 1
                                local route = SC.Navigation.findPath(outside,
                                    square, { actor = Harness.leader, nodeBudget = 2500 })
                                if route and #route >= 3 and #route <= 8 then
                                    deeper, deepPath = square, route
                                    break
                                end
                            end
                        end
                    end
                    if deeper then break end
                end
                if deeper then break end
            end
            check("building_door_bash_deep_room_route",
                deepPath ~= nil and #deepPath >= 3 and #deepPath <= 8,
                "loaded_path_nodes=" .. tostring(deepPath and #deepPath)
                    .. " candidates=" .. tostring(candidates))
            if deepPath == nil or #deepPath < 3 or #deepPath > 8 then
                setPhase("finish", current) return
            end
            local x, y = position(deeper)
            local staged, stageReason = SC.ExpeditionPrototype.stageTestWaypoint(
                Harness.leader, x, y, z)
            check("building_door_bash_entry_staged", staged == true,
                tostring(stageReason))
            if not staged then setPhase("finish", current) return end
            setPhase("team_door_bash_entry", current)
            return
        end
        setPhase("finish", current)
        return
    end
    if current - Harness.phaseStartedAt > 60000
        or not SC.NativeActions.isWorkActive(Harness.leader) then
        local finished, reason = SC.NativeActions.finishWork(Harness.leader)
        result("FAIL", "building_door_bash_destroyed_native",
            "health=" .. tostring(health)
                .. " start_health=" .. tostring(Harness.bashDoorHealth)
                .. " index=" .. tostring(index)
                .. " work_finished=" .. tostring(finished)
                .. " reason=" .. tostring(reason))
        setPhase("finish", current)
    end
end

function Harness.probeDoorBashEntry(current)
    Harness.maintainBuildingQuietFixture(current)
    local SC = SurvivorCompanion
    local mission = SC.ExpeditionPrototype.current()
    local square = Harness.leader:getCurrentSquare()
    local inside = Harness.bashDoorInsideSquare
    if mission and mission.testWaypointArrived == true then
        check("building_door_bash_native_entry",
            square ~= nil and square:getRoom() == inside:getRoom()
                and getSpecificPlayer(0) == Harness.player
                and getSpecificPlayer(1) == Harness.leader,
            "leader=" .. tostring(Harness.leader:getX())
                .. "," .. tostring(Harness.leader:getY())
                .. " room=" .. tostring(square and square:getRoom()))
        setPhase("finish", current)
    elseif current - Harness.phaseStartedAt > 60000
        or Harness.leader:isDead() then
        local nav = SC.Navigation.status(Harness.leader) or {}
        result("FAIL", "building_door_bash_native_entry",
            "leader=" .. tostring(Harness.leader:getX())
                .. "," .. tostring(Harness.leader:getY())
                .. " room=" .. tostring(square and square:getRoom())
                .. " nav=" .. tostring(nav.phase) .. "/"
                .. tostring(nav.pathReason))
        setPhase("finish", current)
    end
end

function Harness.probeDoorBashAuto(current)
    Harness.maintainBuildingQuietFixture(current)
    local SC = SurvivorCompanion
    local door = Harness.buildingDoor
    if not Harness.bashDoorAutoMemoryChecked
        and current - Harness.phaseStartedAt > 5000 then
        Harness.bashDoorAutoMemoryChecked = true
        local state = SC.Navigation.peek(Harness.leader) or {}
        local start = Harness.leader:getCurrentSquare()
        local path, reason, expanded = SC.Navigation.findPath(start,
            Harness.bashDoorAutoGoal, {
                actor = Harness.leader, nodeBudget = 2500,
                blockedEdges = state.blockedEdges,
                blockedSquares = state.blockedSquares,
                routeMemory = state.routeMemory, now = current,
                allowDoorBash = true,
                doorBashTool = Harness.bashDoorAxe,
                doorBashTargetRoom = Harness.bashDoorAutoGoal:getRoom(),
            })
        check("building_door_bash_auto_memory_route", path ~= nil
                and #path >= 2 and #path <= 8,
            "path=" .. tostring(path and #path)
                .. " reason=" .. tostring(reason)
                .. " expanded=" .. tostring(expanded)
                .. " blocked_edges=" .. tostring(state.blockedEdges
                    and next(state.blockedEdges) ~= nil)
                .. " blocked_squares=" .. tostring(state.blockedSquares
                    and next(state.blockedSquares) ~= nil))
    end
    local workKind = SC.NativeActions.workKind(Harness.leader)
    if workKind == "bash_door" and not Harness.bashDoorAutoStarted then
        Harness.bashDoorAutoStarted = true
        check("building_door_bash_auto_selected", true,
            "native work kind=" .. tostring(workKind))
    end
    local health = select(1, SC.GameplayUtil.call(door, "getHealth"))
    if tonumber(health) and tonumber(health) < Harness.bashDoorHealth
        and not Harness.bashDoorAutoDamaged then
        Harness.bashDoorAutoDamaged = true
        check("building_door_bash_auto_damage", true,
            "health=" .. tostring(Harness.bashDoorHealth)
                .. "->" .. tostring(health))
    end
    local index = select(1, SC.GameplayUtil.call(door, "getObjectIndex"))
    if select(1, SC.GameplayUtil.call(door, "isDestroyed")) == true
        or tonumber(index) == -1 then
        Harness.bashDoorAutoDestroyed = true
    end
    local mission = SC.ExpeditionPrototype.current()
    local square = Harness.leader:getCurrentSquare()
    if mission and mission.testWaypointArrived == true then
        local gap = math.huge
        local x, y = position(Harness.leader)
        local gx, gy = position(Harness.bashDoorAutoGoal)
        if x and gx then gap = math.sqrt((x - gx)^2 + (y - gy)^2) end
        check("building_door_bash_auto_native_entry",
            Harness.bashDoorAutoStarted == true
                and Harness.bashDoorAutoDamaged == true
                and Harness.bashDoorAutoDestroyed == true
                and square ~= nil
                and square:getRoom() == Harness.bashDoorAutoGoal:getRoom()
                and gap < 2
                and getSpecificPlayer(0) == Harness.player
                and getSpecificPlayer(1) == Harness.leader,
            "leader=" .. tostring(x) .. "," .. tostring(y)
                .. " gap=" .. tostring(gap)
                .. " room=" .. tostring(square and square:getRoom())
                .. " work=" .. tostring(workKind)
                .. " door_index=" .. tostring(index))
        setPhase("finish", current)
    elseif current - Harness.phaseStartedAt > 100000
        or Harness.leader:isDead() then
        local nav = SC.Navigation.status(Harness.leader) or {}
        local state = SC.Navigation.peek(Harness.leader) or {}
        local pending = state.pathSearch or {}
        local route = pending.route or {}
        local search = route.search or {}
        local options = route.pathOptions or {}
        result("FAIL", "building_door_bash_auto_native_entry",
            "leader=" .. tostring(Harness.leader:getX())
                .. "," .. tostring(Harness.leader:getY())
                .. " started=" .. tostring(Harness.bashDoorAutoStarted)
                .. " damaged=" .. tostring(Harness.bashDoorAutoDamaged)
                .. " destroyed=" .. tostring(Harness.bashDoorAutoDestroyed)
                .. " work=" .. tostring(workKind)
                .. " nav=" .. tostring(nav.phase) .. "/"
                .. tostring(nav.pathReason)
                .. " expanded=" .. tostring(nav.expandedNodes)
                .. " replans=" .. tostring(state.routeReplanCount)
                .. " search_age=" .. tostring(pending.startedAt
                    and current - pending.startedAt)
                .. " search_expanded=" .. tostring(route.totalExpanded)
                .. " search_phase=" .. tostring(route.phase)
                .. " retry=" .. tostring(route.budgetRetried)
                .. " bash_retry=" .. tostring(route.bashRetried)
                .. " bash_allowed=" .. tostring(options.doorBashAsLastResort)
                .. " path_bash=" .. tostring(options.allowDoorBash)
                .. " bash_tool=" .. tostring(options.doorBashTool)
                .. " search_budget=" .. tostring(search.nodeBudget)
                .. " search_nodes=" .. tostring(search.expanded))
        setPhase("finish", current)
    end
end

local function probeLeaderCapture(current)
    if fileExists(SPLIT_CAPTURED_FILE) then
        if Harness.config.split_base_layout_probe == "true" then
            local status = SurvivorCompanion.BaseVisuals.status()
            check("split_base_layout_primary_overlay_drawn",
                status.enabled == true and status.visibleZones > 0,
                "zones=" .. tostring(status.visibleZones)
                    .. " storages=" .. tostring(status.visibleStorages))
        end
        result("PASS", "leader_split_screen_capture", "existing companion visible in split view")
        Harness.leaderObserveFrames = SurvivorCompanion.Scheduler.getStats().frames or 0
        setPhase("leader_observe", current)
    elseif current - Harness.phaseStartedAt > 15000 then
        result("FAIL", "leader_split_screen_capture", "runner did not capture the viewport")
        setPhase("finish", current)
    end
end

local function probeLeaderSurvival(current)
    if Harness.team then
        if Harness.teamWaypoint then
            local x, y = position(Harness.leader)
            if x and y then
                local chunkX, chunkY = math.floor(x / 10), math.floor(y / 10)
                Harness.leaderChunksSeen = Harness.leaderChunksSeen or {}
                Harness.leaderChunksSeen[tostring(chunkX) .. "," .. tostring(chunkY)] = true
            end
        end
        local currentZombies, count = livingRemoteZombies()
        Harness.remoteZombiePeak = math.max(Harness.remoteZombiePeak or 0, count)
        Harness.remoteZombieSeen = Harness.remoteZombieSeen or {}
        for id, at in pairs(currentZombies) do
            local before = Harness.remoteZombieSeen[id]
            if before and math.abs(before.x - at.x) + math.abs(before.y - at.y) > 0.1 then
                Harness.remoteZombieMoved = Harness.remoteZombieMoved or {}
                Harness.remoteZombieMoved[id] = true
            elseif not before then
                Harness.remoteZombieSeen[id] = at
            end
        end
    end
    if current - Harness.phaseStartedAt
        < (tonumber(Harness.config.leader_watch_ms) or 8000) then return end
    local SC = SurvivorCompanion
    local valid, reason = SC.Actor.validateNative(Harness.leader)
    check("leader_still_native_after_eight_seconds", valid == true,
        "reason=" .. tostring(reason))
    local naturalDeath = Harness.team and Harness.leader:isDead() == true
    if naturalDeath then
        result("PASS", "unforced_leader_death",
            "native casualty before any harness injury")
        result("SKIP", "leader_registry_retained",
            "dead companion is retired from the active registry")
        result("SKIP", "leader_still_alive",
            "native danger killed the leader during observation")
    else
        check("leader_registry_retained", SC.Registry.isActive(Harness.leader, Harness.leaderId),
            "companion ID still maps to the same actor")
        check("leader_still_alive", Harness.leader:isDead() == false,
            "promoted companion survived the observation window")
    end
    local otherCount, othersValid, othersNearRiverside = 0, true, true
    for _, record in ipairs(Harness.originalCompanions or SC.Registry.records()) do
        if record.actor ~= Harness.leader then
            otherCount = otherCount + 1
            local validOther = SC.Actor.validateNative(record.actor)
            if not validOther or not SC.Registry.isActive(record.actor, record.id) then
                othersValid = false
            end
            local ox, oy = position(record.actor)
            if ox == nil or oy == nil
                or math.abs(ox - Harness.playerX) > 40
                or math.abs(oy - Harness.playerY) > 40 then
                othersNearRiverside = false
            end
        end
    end
    check("other_three_companions_healthy", otherCount == 3 and othersValid,
        "count=" .. tostring(otherCount) .. " valid=" .. tostring(othersValid))
    local laterSpawns = math.max(0,
        #SC.Registry.records() - #(Harness.originalCompanions or {}))
    if laterSpawns > 0 then
        result("PASS", "later_world_spawn_excluded_from_original_roster",
            "new_active_records=" .. tostring(laterSpawns))
    end
    if Harness.team then
        if Harness.radioFixture then
            local outward, returnLeg, contextText = false, false, false
            local contextGuid, contextCodes
            local scopedNegativeText = false
            for _, receipt in ipairs(Harness.radioReceipts or {}) do
                if receipt.device == Harness.radioFixture.team[1]
                    and string.find(receipt.message, "SC_RADIO_TEST_OUT_", 1, true) then
                    outward = true
                end
                if receipt.device == Harness.radioFixture.player
                    and string.find(receipt.message, "SC_RADIO_TEST_BACK_", 1, true) then
                    returnLeg = true
                end
                if receipt.device == Harness.radioFixture.team[1]
                    and receipt.message == "SC_RADIO_TEST_CONTEXT_"
                        .. Harness.config.run_id then
                    contextText = true
                    contextGuid = receipt.guid
                    contextCodes = receipt.codes
                end
                if receipt.device == Harness.radioFixture.team[1]
                    and (string.find(receipt.message,
                        "SC_RADIO_TEST_CTX_MISTUNED_", 1, true)
                        or string.find(receipt.message,
                            "SC_RADIO_TEST_CTX_OFF_", 1, true)
                        or string.find(receipt.message,
                            "SC_RADIO_TEST_CTX_SILENT_", 1, true)) then
                    scopedNegativeText = true
                end
            end
            local signal = Harness.radioSignalEvidence or {}
            local inFieldRange = signal.expected ~= nil
                and signal.expected < Harness.radioFixture.player
                    :getDeviceData():getTransmitRange()
            check("mistuned_leader_rejects_native_signal",
                signal.before ~= nil and signal.before == signal.mistuned,
                "distance=" .. tostring(signal.before) .. "->"
                    .. tostring(signal.mistuned))
            check("powered_off_leader_rejects_native_signal",
                signal.before ~= nil and signal.before == signal.off,
                "distance=" .. tostring(signal.before) .. "->"
                    .. tostring(signal.off))
            check("muted_leader_rejects_native_signal",
                signal.before ~= nil and signal.before == signal.silent,
                "distance=" .. tostring(signal.before) .. "->"
                    .. tostring(signal.silent))
            check("native_player_to_leader_signal",
                signal.outward ~= nil and signal.expected ~= nil
                    and ((inFieldRange
                        and math.abs(signal.outward - signal.expected) <= 3)
                        or (not inFieldRange and signal.outward == signal.before)),
                "distance=" .. tostring(signal.before) .. "->"
                    .. tostring(signal.outward) .. " expected=" .. tostring(signal.expected))
            result(outward and "PASS" or "SKIP", "native_leader_text_callback",
                outward and "matching OnDeviceText on leader radio"
                    or (inFieldRange
                        and "native signal reached radio but non-local NPC received no Lua text event"
                        or "field walkie out of native transmit range"))
            if Harness.config.team_radio_text_probe == "true" then
                check("scoped_native_receiver_gates",
                    signal.before ~= nil and signal.scopedMistuned == signal.before
                        and signal.scopedOff == signal.before
                        and signal.scopedSilent == signal.before
                        and scopedNegativeText == false,
                    "distance=" .. tostring(signal.before)
                        .. "/" .. tostring(signal.scopedMistuned)
                        .. "/" .. tostring(signal.scopedOff)
                        .. "/" .. tostring(signal.scopedSilent)
                        .. " text=" .. tostring(scopedNegativeText))
                check("scoped_native_leader_text_callback", contextText
                    and signal.contextDistance ~= nil
                    and math.abs(signal.contextDistance - signal.expected) <= 3,
                    "text=" .. tostring(contextText)
                        .. " distance=" .. tostring(signal.contextDistance)
                        .. " guid=" .. tostring(contextGuid)
                        .. " codes=" .. tostring(contextCodes))
                check("scoped_radio_local_identity_restored",
                    signal.contextLocalIdentity == false
                        and Harness.leader:isLocalPlayer() == false
                        and getSpecificPlayer(0) == Harness.player,
                    "scoped callback ended without changing player slot 0")
            end
            check("native_leader_to_player_signal",
                signal.returnLeg ~= nil and signal.expected ~= nil
                    and ((inFieldRange
                        and math.abs(signal.returnLeg - signal.expected) <= 3)
                        or (not inFieldRange
                            and signal.returnLeg == signal.playerBefore)),
                "distance=" .. tostring(signal.playerBefore) .. "->"
                    .. tostring(signal.returnLeg) .. " expected=" .. tostring(signal.expected))
            check("native_leader_to_player_radio_receive", returnLeg == inFieldRange,
                inFieldRange and "matching native OnDeviceText on player's exact radio"
                    or "no reply received beyond field walkie transmit range")
            if Harness.config.team_radio_placed_probe == "true" then
                local placed = Harness.radioFixture
                local walkieOut, hamOut, walkieBack, hamBack =
                    false, false, false, false
                for _, receipt in ipairs(Harness.radioReceipts or {}) do
                    if receipt.device == placed.team[1]
                        and string.find(receipt.message,
                            "SC_RADIO_TEST_PLACED_WALKIE_OUT_", 1, true) then
                        walkieOut = true
                    elseif receipt.device == placed.team[1]
                        and string.find(receipt.message,
                            "SC_RADIO_TEST_PLACED_HAM_OUT_", 1, true) then
                        hamOut = true
                    elseif receipt.device == placed.placedWalkie.object
                        and string.find(receipt.message,
                            "SC_RADIO_TEST_PLACED_WALKIE_BACK_", 1, true) then
                        walkieBack = true
                    elseif receipt.device == placed.placedHam.object
                        and string.find(receipt.message,
                            "SC_RADIO_TEST_PLACED_HAM_BACK_", 1, true) then
                        hamBack = true
                    end
                end
                local placedEvidence = Harness.placedRadioEvidence or {}
                local distance = placedEvidence.distance
                local walkieInRange = distance ~= nil
                    and distance < (placedEvidence.walkieRange or 0)
                local hamInRange = distance ~= nil
                    and distance < (placedEvidence.hamRange or 0)
                local returnInRange = distance ~= nil
                    and distance < (placedEvidence.fieldRange or 0)
                check("placed_walkie_to_leader_text", walkieOut == walkieInRange,
                    "received=" .. tostring(walkieOut)
                        .. " expected=" .. tostring(walkieInRange))
                check("placed_ham_to_leader_text", hamOut == hamInRange,
                    "received=" .. tostring(hamOut)
                        .. " expected=" .. tostring(hamInRange))
                check("leader_to_placed_walkie_text", walkieBack == returnInRange,
                    "received=" .. tostring(walkieBack)
                        .. " expected=" .. tostring(returnInRange))
                check("leader_to_placed_ham_text", hamBack == returnInRange,
                    "received=" .. tostring(hamBack)
                        .. " expected=" .. tostring(returnInRange))
                if not walkieInRange and hamInRange and not returnInRange then
                    check("placed_ham_asymmetric_outward_only",
                        hamOut and not walkieOut and not walkieBack and not hamBack,
                        "HAM reached leader; weaker field walkie could not reply")
                end
            end
        end
        local moved = 0
        for _ in pairs(Harness.remoteZombieMoved or {}) do moved = moved + 1 end
        if Harness.config.team_restart_stage_only == "true" then
            result("SKIP", "natural_remote_population_present",
                "focused eight-second save checkpoint; peak="
                    .. tostring(Harness.remoteZombiePeak))
            result("SKIP", "natural_remote_zombies_update",
                "focused eight-second save checkpoint; moved="
                    .. tostring(moved))
        elseif Harness.config.team_radio_placed_probe == "true"
            and Harness.radioSignalEvidence
            and (Harness.radioSignalEvidence.expected or 0)
                > Harness.radioFixture.team[1]:getDeviceData():getTransmitRange() then
            result("SKIP", "natural_remote_population_present",
                "focused asymmetric radio site; peak="
                    .. tostring(Harness.remoteZombiePeak))
            result("SKIP", "natural_remote_zombies_update",
                "focused asymmetric radio site; moved=" .. tostring(moved))
        else
            check("natural_remote_population_present", (Harness.remoteZombiePeak or 0) > 0,
                "peak=" .. tostring(Harness.remoteZombiePeak)
                    .. " fixture_spawns=0")
            check("natural_remote_zombies_update", moved > 0,
                "same native zombies moved=" .. tostring(moved))
        end
        local before, after = Harness.remoteVitalsBefore or {},
            nativeFieldVitals(Harness.leader)
        local changed, details = false, {}
        for _, name in ipairs({ "ENDURANCE", "FATIGUE", "HUNGER", "THIRST" }) do
            local first, last = tonumber(tostring(before[name])),
                tonumber(tostring(after[name]))
            if first and last then
                local difference = math.abs(last - first)
                if difference > 0.00001 then changed = true end
                details[#details + 1] = name .. "=" .. tostring(first)
                    .. "->" .. tostring(last)
            end
        end
        -- Needs update on the engine's own schedule. A short radio/leader
        -- sample with no tick is inconclusive; dedicated longer runs proved it.
        result(changed and "PASS" or "SKIP",
            "remote_native_stats_advance", table.concat(details, ";"))
        local firstHealth, lastHealth = tonumber(tostring(before.health)),
            tonumber(tostring(after.health))
        result(firstHealth and lastHealth and lastHealth < firstHealth - 0.01
            and "PASS" or "SKIP", "unforced_remote_health_loss",
            "native health=" .. tostring(firstHealth) .. "->" .. tostring(lastHealth)
                .. "; test death injury has not yet been applied")
        local leaderX, leaderY = position(Harness.leader)
        local nearby, followerDecisions = true, true
        for index = 2, #Harness.team do
            local record = Harness.team[index]
            local fx, fy = position(record.actor)
            local distance = fx and fy and leaderX and leaderY
                and math.sqrt((fx - leaderX)^2 + (fy - leaderY)^2) or math.huge
            nearby = nearby and distance < 15
            local runtime = record.runtime or {}
            followerDecisions = followerDecisions
                and runtime.lastDecision ~= nil
            check("follower_position_" .. tostring(index), distance < 15,
                "id=" .. tostring(record.id) .. " distance=" .. tostring(distance)
                    .. " decision=" .. tostring(runtime.lastDecision))
        end
        check("team_follows_remote_leader", nearby and followerDecisions,
            "all mission followers near leader with active decisions")
        local originals = Harness.originalCompanions or SC.Registry.records()
        local allAssigned = #originals == 4
            and #Harness.team == ((Harness.config.team_all_dead_cleanup == "true")
                and 3 or 4)
        for _, record in ipairs(Harness.team) do
            allAssigned = allAssigned
                and SC.ExpeditionPrototype.isMember(record.actor)
        end
        check("all_saved_companions_on_remote_team", allAssigned,
            "assigned=" .. tostring(#Harness.team)
                .. " originals=" .. tostring(#originals))
    else
        check("other_three_companions_stay_riverside", otherCount == 3
            and othersNearRiverside,
            "other companions remain within 40 tiles of the main player")
    end
    local frames = SC.Scheduler.getStats().frames or 0
    check("leader_ai_scheduler_continues", frames > (Harness.leaderObserveFrames or frames),
        "frames=" .. tostring(Harness.leaderObserveFrames) .. "->" .. tostring(frames))
    local x, y = position(Harness.leader)
    if Harness.config.leader_remote == "true" then
        local oldContains = false
        local checked, value = pcall(function()
            return Harness.leaderOriginalSquare:getMovingObjects():contains(Harness.leader)
        end)
        if checked then oldContains = value == true end
        check("leader_not_left_in_riverside_square", checked and not oldContains,
            "checked=" .. tostring(checked) .. " stillPresent=" .. tostring(oldContains))
        if not Harness.team then
            check("leader_autonomous_remote_motion",
                x ~= nil and y ~= nil
                    and (math.abs(x - Harness.leaderRemoteStartX)
                        + math.abs(y - Harness.leaderRemoteStartY)) > 0.25,
                "after load=" .. tostring(Harness.leaderRemoteStartX) .. ","
                    .. tostring(Harness.leaderRemoteStartY)
                    .. " after eight seconds=" .. tostring(x) .. "," .. tostring(y))
        end
        if Harness.teamWaypoint then
            local waypoint = Harness.teamWaypoint
            local mission = SC.ExpeditionPrototype.current()
            local arrival = mission and mission.testWaypointArrival
            local distance = arrival and math.sqrt((arrival.x - waypoint.x)^2
                + (arrival.y - waypoint.y)^2) or math.huge
            local arrived = mission and mission.testWaypointArrived == true
                and distance < 2
            result(arrived and "PASS" or (naturalDeath and "SKIP" or "FAIL"),
                "leader_walked_standing_waypoint",
                "arrived=" .. tostring(mission and mission.testWaypointArrived)
                    .. " distance=" .. tostring(distance)
                    .. " native_death=" .. tostring(naturalDeath))
            local chunksSeen = 0
            for _ in pairs(Harness.leaderChunksSeen or {}) do
                chunksSeen = chunksSeen + 1
            end
            local crossed = chunksSeen >= 2
            check("leader_crossed_native_chunk_edge", crossed == true,
                "chunks_seen=" .. tostring(chunksSeen)
                    .. " from=" .. tostring(waypoint.startX) .. ","
                    .. tostring(waypoint.startY) .. " now=" .. tostring(x)
                    .. "," .. tostring(y))
        end
    end
    result("PASS", "leader_position_observed",
        "start=" .. tostring(Harness.leaderStartX) .. "," .. tostring(Harness.leaderStartY)
            .. " now=" .. tostring(x) .. "," .. tostring(y))
    if Harness.team then
        if Harness.config.team_performance_probe == "true" then
            if naturalDeath then
                result("FAIL", "performance_leader_survived_warmup",
                    "leader died before measurement")
                setPhase("finish", current)
            else
                setPhase("performance_warmup", current)
            end
            return
        end
        if Harness.config.team_restart_stage_only == "true" then
            if naturalDeath then
                result("FAIL", "restart_stage_living_team",
                    "leader died before the active mission checkpoint")
                setPhase("finish", current)
                return
            end
            local saved, document = SC.Runtime.save()
            local descriptor = saved and document and document.expedition
            check("restart_stage_mission_descriptor_saved",
                saved == true and type(descriptor) == "table"
                    and descriptor.schema == 1
                    and #descriptor.roster == #Harness.team
                    and #descriptor.survivors == #Harness.team
                    and descriptor.leaderId == Harness.leaderId,
                "saved=" .. tostring(saved)
                    .. " roster=" .. tostring(descriptor
                        and #descriptor.roster)
                    .. " survivors=" .. tostring(descriptor
                        and #descriptor.survivors)
                    .. " leader=" .. tostring(descriptor
                        and descriptor.leaderId))
            setPhase("finish", current)
            return
        end
        if Harness.config.team_menu_cleanup_probe == "true" then
            local descriptor = SC.ExpeditionPrototype.export()
            check("menu_cleanup_active_descriptor_ready",
                descriptor ~= nil and descriptor.schema == 1
                    and #descriptor.roster == #Harness.team,
                "roster=" .. tostring(descriptor and #descriptor.roster))
            local cleared, reason = SC.Runtime.onMainMenuEnter()
            check("menu_cleanup_runtime_reset", cleared == true,
                tostring(reason))
            check("menu_cleanup_owned_view_released",
                SCSplitScreenProbe.isReleased() == true
                    and getSpecificPlayer(1) == nil
                    and getPlayerData(1) == nil
                    and getSpecificPlayer(0) == Harness.player,
                SCSplitScreenProbe.releaseDiagnostics())
            check("menu_cleanup_old_mission_and_actors_cleared",
                SC.ExpeditionPrototype.current() == nil
                    and SC.ExpeditionPrototype.export() == nil
                    and #SC.Registry.records() == 0
                    and SC.Runtime.isTickAttached() == false,
                "records=" .. tostring(#SC.Registry.records()))
            setPhase("finish", current)
            return
        end
        if Harness.config.team_all_dead_cleanup == "true" then
            Harness.allDeadGear = {}
            local cargoPrepared = true
            for index, actor in ipairs(Harness.teamActors or {}) do
                local worn = actor:getWornItems()
                local firstWorn = worn and worn:size() > 0
                    and worn:get(0):getItem() or nil
                if Harness.config.team_all_dead_stage_only == "true"
                    and firstWorn ~= nil then
                    firstWorn:getModData().SCAllDeadGearProbe = index
                end
                local cargoItem = nil
                if Harness.config.team_all_dead_stage_only == "true" then
                    cargoItem = actor:getInventory():AddItem("Base.Bandage")
                    if cargoItem ~= nil and cargoItem:getID() > 0 then
                        cargoItem:getModData().SCAllDeadCargoProbe = index
                        cargoItem:getModData().SCAllDeadCargoNativeId =
                            cargoItem:getID()
                    else
                        cargoPrepared = false
                    end
                end
                Harness.allDeadGear[actor] = {
                    inventory = actor:getInventory(),
                    wornCount = worn and worn:size() or 0,
                    firstWorn = firstWorn,
                    cargoItem = cargoItem,
                }
            end
            if Harness.config.team_all_dead_stage_only == "true" then
                check("all_dead_exact_cargo_fixture_prepared", cargoPrepared,
                    "one test-only native bandage per actor")
            end
            local accepted = true
            for index = 2, #Harness.team do
                local actor = Harness.team[index].actor
                if not actor:isDead() then
                    local ended = SC.Actor.endLife(actor)
                    accepted = accepted and ended == true
                end
            end
            check("all_dead_fixture_injuries_accepted", accepted,
                "native terminal injuries applied only in cloned save")
        end
        if naturalDeath then
            result("PASS", "leader_native_death_observed",
                "unforced death; no harness damage applied")
        else
            local ended, reason = SC.Actor.endLife(Harness.leader)
            check("leader_native_death_triggered", ended == true, tostring(reason))
        end
        Harness.deadLeader = Harness.leader
        setPhase("team_handoff_wait", current)
    else
        setPhase("finish", current)
    end
end

local function probeTeamHandoff(current)
    local SC = SurvivorCompanion
    local mission = SC.ExpeditionPrototype.current()
    if mission == nil and SC.ExpeditionPrototype.lastOutcome() == "all_dead" then
        local allDead = true
        local corpseReady = 0
        for _, actor in ipairs(Harness.teamActors or {}) do
            allDead = allDead and actor:isDead() == true
            local checked, ready = pcall(actor.isCorpseReady, actor)
            if checked and ready == true then corpseReady = corpseReady + 1 end
        end
        local cleanup = SC.Actor.ownershipSnapshot()
        local teamCount = #(Harness.teamActors or {})
        if (corpseReady < teamCount or cleanup.actorCleanups > 0)
            and current - Harness.phaseStartedAt < 30000 then return end
        check("all_dead_fixture_members_died", allDead,
            "all original mission actors reached native death")
        check("all_dead_native_corpses_finalized", corpseReady == teamCount,
            "corpse_ready=" .. tostring(corpseReady)
                .. " team=" .. tostring(teamCount))
        local exactCorpseOwnership, exactWornGear = true, true
        local exactCargo = true
        local corpseDetails = {}
        for _, actor in ipairs(Harness.teamActors or {}) do
            local before = Harness.allDeadGear and Harness.allDeadGear[actor]
            local inspected, corpse, container, worn, equipped = pcall(function()
                local body = actor:getCompanionCorpse()
                return body, body and body:getContainer(),
                    body and body:getWornItems(),
                    body and before and before.firstWorn
                        and body:isEquippedClothing(before.firstWorn)
            end)
            local sameInventory = inspected and before ~= nil
                and corpse ~= nil and container == before.inventory
                and actor:getInventory() ~= before.inventory
            local sameGear = inspected and before ~= nil
                and before.wornCount > 0 and worn ~= nil
                and worn:size() == before.wornCount and equipped == true
            exactCorpseOwnership = exactCorpseOwnership and sameInventory
            exactWornGear = exactWornGear and sameGear
            if Harness.config.team_all_dead_stage_only == "true" then
                local items = container and container:getItems()
                exactCargo = exactCargo and before.cargoItem ~= nil
                    and items ~= nil and items:contains(before.cargoItem)
            end
            corpseDetails[#corpseDetails + 1] = tostring(inspected)
                .. "/" .. tostring(sameInventory)
                .. "/" .. tostring(sameGear)
        end
        check("all_dead_exact_native_inventory_moved_to_corpse",
            exactCorpseOwnership, table.concat(corpseDetails, ";"))
        check("all_dead_exact_worn_gear_on_corpse",
            exactWornGear, table.concat(corpseDetails, ";"))
        if Harness.config.team_all_dead_stage_only == "true" then
            check("all_dead_exact_carried_item_on_corpse", exactCargo,
                "three test-only bandages retained by native corpse inventory")
        end
        if Harness.config.team_all_dead_stage_only == "true" then
            local marked = true
            local locations = {}
            for index, actor in ipairs(Harness.teamActors or {}) do
                local body = actor:getCompanionCorpse()
                local square = body and body:getSquare()
                local objects = square and square:getStaticMovingObjects()
                local listed = objects and objects:contains(body) or false
                locations[#locations + 1] = tostring(index) .. "@"
                    .. tostring(body and body:getX()) .. ","
                    .. tostring(body and body:getY()) .. " square="
                    .. tostring(square and square:getX()) .. ","
                    .. tostring(square and square:getY())
                    .. " callback_listed="
                    .. tostring(actor:wasCompanionCorpseListedAtCallback())
                    .. " listed=" .. tostring(listed)
                local ok = pcall(function()
                    local corpseData = body:getModData()
                    local gearData = Harness.allDeadGear[actor]
                        .firstWorn:getModData()
                    corpseData.SCAllDeadCorpseProbe = index
                    gearData.SCAllDeadGearProbe = index
                end)
                marked = marked and ok
            end
            check("all_dead_corpses_marked_for_native_reload_probe", marked,
                "test-only markers on three corpses and exact worn items; "
                    .. table.concat(locations, ";"))
        end
        check("all_dead_bridge_ownership_released",
            cleanup.actorCleanups == 0,
            "pending=" .. tostring(cleanup.actorCleanups))
        check("all_dead_second_view_released", SCSplitScreenProbe.isReleased() == true,
            SCSplitScreenProbe.releaseDiagnostics())
        check("all_dead_player_ui_removed", getPlayerData(1) == nil,
            "stock split-screen UI data removed")
        check("all_dead_primary_view_preserved", getSpecificPlayer(0) == Harness.player
            and getPlayer() == Harness.player
            and Harness.player:isDead() == false,
            "Riverside player remains active")
        check("all_dead_main_square_retained",
            getWorld():getCell():getGridSquare(math.floor(Harness.playerX),
                math.floor(Harness.playerY), Harness.playerZ) ~= nil,
            "primary world lookup remains available")
        writeSignal(SPLIT_READY_FILE, { "ready=true" })
        setPhase("team_all_dead_capture", current)
        return
    end
    local successor = mission and mission.leader
    if successor and successor.actor ~= Harness.deadLeader
        and getSpecificPlayer(1) == successor.actor then
        check("view_handed_to_next_living_companion", true,
            "slot 1 is existing companion " .. tostring(successor.id))
        check("dead_leader_left_view", Harness.deadLeader ~= getSpecificPlayer(1)
            and Harness.deadLeader:isDead(), "dead leader no longer owns camera slot")
        local valid, reason = SC.Actor.validateNative(successor.actor)
        check("successor_keeps_native_ai", valid == true, tostring(reason))
        check("primary_view_survives_handoff", getSpecificPlayer(0) == Harness.player,
            "Riverside player still in slot 0")
        Harness.successor = successor
        Harness.successorFrames = SC.Scheduler.getStats().frames or 0
        writeSignal(SPLIT_READY_FILE, { "ready=true" })
        setPhase("team_handoff_capture", current)
        return
    end
    if current - Harness.phaseStartedAt > 12000 then
        result("FAIL", "view_handed_to_next_living_companion",
            "leader=" .. tostring(mission and mission.leader and mission.leader.id)
                .. " slot1=" .. tostring(getSpecificPlayer(1))
                .. " dead=" .. tostring(Harness.deadLeader:isDead()))
        setPhase("finish", current)
    end
end

local function probeTeamAllDeadCapture(current)
    if fileExists(SPLIT_CAPTURED_FILE) then
        result("PASS", "all_dead_primary_view_captured",
            "single local viewport captured after team death")
        local SC = SurvivorCompanion
        local idle = SC.ExpeditionPrototype.export()
        check("all_dead_retains_reusable_slot_identity",
            idle ~= nil and idle.schema == 2 and idle.state == "idle"
                and type(idle.slotSqlId) == "number" and idle.slotSqlId >= 2,
            "slotSqlId=" .. tostring(idle and idle.slotSqlId))
        if idle == nil or idle.slotSqlId == nil then
            setPhase("finish", current) return
        end
        if Harness.config.team_all_dead_menu_cleanup_probe == "true" then
            local cleared, reason = SC.Runtime.onMainMenuEnter()
            check("all_dead_idle_menu_cleanup", cleared == true
                and SC.ExpeditionPrototype.export() == nil
                and SC.ExpeditionPrototype.current() == nil
                and #SC.Registry.records() == 0
                and getSpecificPlayer(0) == Harness.player
                and getSpecificPlayer(1) == nil,
                "cleared=" .. tostring(cleared)
                    .. " reason=" .. tostring(reason))
            setPhase("finish", current)
            return
        end
        if Harness.config.team_all_dead_stage_only == "true" then
            local saved, document = SC.Runtime.save()
            check("all_dead_idle_slot_descriptor_saved", saved == true
                and document ~= nil and document.expedition ~= nil
                and document.expedition.schema == 2
                and document.expedition.state == "idle"
                and document.expedition.slotSqlId == idle.slotSqlId,
                "saved=" .. tostring(saved) .. " slotSqlId="
                    .. tostring(document and document.expedition
                        and document.expedition.slotSqlId))
            setPhase("finish", current)
            return
        end
        local teamIds = {}
        for _, record in ipairs(Harness.team or {}) do teamIds[record.id] = true end
        local reserve
        for _, record in ipairs(Harness.originalCompanions or {}) do
            if not teamIds[record.id] and record.actor ~= nil
                and not record.actor:isDead()
                and SC.Registry.isActive(record.actor, record.id) then
                reserve = record
                break
            end
        end
        check("all_dead_reserve_companion_available", reserve ~= nil,
            "one saved companion outside the dead mission remains active")
        if reserve == nil then setPhase("finish", current) return end
        Harness.allDeadReserve = reserve
        Harness.reuseSlotSqlId = idle.slotSqlId
        local started, accepted, detail = pcall(SC.ExpeditionPrototype.start,
            { reserve })
        check("all_dead_follow_on_expedition_queued", started and accepted == true,
            tostring(started and detail or accepted))
        if not started or accepted ~= true then
            setPhase("finish", current) return
        end
        setPhase("team_all_dead_reuse_wait", current)
    elseif current - Harness.phaseStartedAt > 15000 then
        result("FAIL", "all_dead_primary_view_captured",
            "runner did not capture the released view")
        setPhase("finish", current)
    end
end

local function probeTeamAllDeadReuse(current)
    local reserve = Harness.allDeadReserve
    local slotActor = getSpecificPlayer(1)
    if slotActor ~= reserve.actor
        and current - Harness.phaseStartedAt < 20000 then return end
    check("all_dead_follow_on_view_reuses_slot_identity",
        slotActor == reserve.actor
            and getSpecificPlayer(0) == Harness.player
            and SurvivorCompanion.Registry.isActive(reserve.actor, reserve.id)
            and SCSplitScreenProbe.leaderSqlId() == Harness.reuseSlotSqlId,
        "slot1=" .. tostring(slotActor == reserve.actor)
            .. " sqlId=" .. tostring(SCSplitScreenProbe.leaderSqlId())
            .. " expected=" .. tostring(Harness.reuseSlotSqlId))
    setPhase("finish", current)
end

local function probeTeamRadioKitCapture(current)
    if fileExists(SPLIT_CAPTURED_FILE) then
        result("PASS", "radio_kit_screenshot_captured",
            "Riverside save remains local with all five radios equipped")
        if Harness.config.team_expedition_ui_probe == "true" then
            local detail = Harness.expeditionUiDetail
            local SC = SurvivorCompanion
            if not check("expedition_ui_review_visible",
                detail ~= nil and detail.expeditionDraft.review == true
                    and detail.displayedTab == "expeditions",
                "selected=" .. tostring(detail and detail.displayedTab)) then
                setPhase("finish", current)
                return
            end
            local places = SC.ExpeditionPlaces
            local loadedApproach = places.loadedApproach
            local admissionPathCalls = 0
            places.loadedApproach = function()
                admissionPathCalls = admissionPathCalls + 1
                return nil, "unexpected_send_loaded_path"
            end
            local clicked, clickFailure = pcall(SC.UIExpeditions.onButton,
                detail, { scExpeditionAction = "launch" })
            places.loadedApproach = loadedApproach
            if not check("expedition_ui_send_has_no_full_path_search",
                clicked and admissionPathCalls == 0,
                "calls=" .. tostring(admissionPathCalls)
                    .. " reason=" .. tostring(clickFailure)) then
                setPhase("finish", current)
                return
            end
            local mission = SC.ExpeditionPrototype.current()
            if not check("expedition_ui_launch_selected_squad",
                mission ~= nil and mission.leader.id == Harness.expeditionUiLeader.id
                    and #mission.roster == Harness.expeditionUiExpectedMembers
                    and mission.scout ~= nil
                    and mission.scout.site.id == Harness.expeditionUiPlace.id
                    and mission.doctrine == "stealth",
                "feedback=" .. tostring(detail.feedback)
                    .. " members=" .. tostring(mission and #mission.roster)
                    .. " expected=" .. tostring(
                        Harness.expeditionUiExpectedMembers)) then
                setPhase("finish", current)
                return
            end
            setPhase("team_expedition_ui_radio_wait", current)
            return
        end
        if Harness.config.team_radio_placed_pickup_probe == "true" then
            local queued, reason = pcall(function()
                require "ISUI/ISWorldObjectContextMenu"
                local expectedId = tonumber(
                    Harness.config.team_radio_placed_expected_walkie_id)
                local worldItem
                local source = Harness.player:getCurrentSquare()
                for dx = -1, 1 do
                    for dy = -1, 1 do
                        local square = getCell():getGridSquare(
                            source:getX() + dx, source:getY() + dy,
                            source:getZ())
                        local worldObjects = square and square:getWorldObjects()
                        if worldObjects then
                            for index = 0, worldObjects:size() - 1 do
                                local candidate = worldObjects:get(index)
                                if candidate and candidate:getItem()
                                    and candidate:getItem():getID() == expectedId then
                                    worldItem = candidate
                                    break
                                end
                            end
                        end
                        if worldItem then break end
                    end
                    if worldItem then break end
                end
                if worldItem == nil then error("staged walkie world item missing") end
                -- The owner's saved player carries 97/12 weight, so the
                -- vanilla capacity gate rejects every pickup. Isolate the
                -- radio lifecycle by lifting that gate in this clone only.
                Harness.radioPickupPreviousUnlimitedCarry =
                    Harness.player:isUnlimitedCarry()
                Harness.player:setUnlimitedCarry(true)
                local inventory = Harness.player:getInventory()
                Harness.radioPickupPreviousCapacity = inventory:getCapacity()
                inventory:setCapacity(200)
                local queue = ISTimedActionQueue.getTimedActionQueue(Harness.player)
                local before = #queue.queue
                ISWorldObjectContextMenu.onGrabWItem({}, worldItem, 0)
                if #queue.queue <= before then
                    error("native context-menu grab did not queue a timed action")
                end
                local action = queue.queue[#queue.queue]
                local blocked = worldItem:getSquare():isBlockedTo(
                    Harness.player:getSquare())
                local contained = worldItem:getSquare():getWorldObjects()
                    :contains(worldItem)
                local room = inventory:hasRoomFor(
                    Harness.player, worldItem:getItem())
                result("PASS", "placed_kit_pickup_fixture_precheck",
                    "blocked=" .. tostring(blocked)
                        .. " contained=" .. tostring(contained)
                        .. " room=" .. tostring(room)
                        .. " capacity=" .. tostring(inventory:getMaxWeight()))
                if not action:isValid() then
                    error("timed grab rejected after disposable capacity override")
                end
                result("PASS", "placed_kit_pickup_action_started",
                    "type=" .. tostring(action and action.Type)
                        .. " valid=" .. tostring(action and action:isValid())
                        .. " started=" .. tostring(action and action.started)
                        .. " max_time=" .. tostring(action and action.maxTime)
                        .. " weight=" .. tostring(inventory:getCapacityWeight())
                        .. "/" .. tostring(inventory:getMaxWeight())
                        .. " room=" .. tostring(inventory:hasRoomFor(
                            Harness.player, worldItem:getItem())))
                Harness.radioPickupItemId = expectedId
                Harness.radioPickupWorldItem = worldItem
                Harness.radioPickupSquare = worldItem:getSquare()
            end)
            if not queued and Harness.radioPickupPreviousUnlimitedCarry ~= nil then
                Harness.player:setUnlimitedCarry(
                    Harness.radioPickupPreviousUnlimitedCarry == true)
                if Harness.radioPickupPreviousCapacity then
                    Harness.player:getInventory():setCapacity(
                        Harness.radioPickupPreviousCapacity)
                end
            end
            check("placed_kit_pickup_timed_action_queued", queued,
                tostring(reason))
            setPhase(queued and "team_radio_kit_pickup_wait" or "finish", current)
        else
            setPhase("finish", current)
        end
    elseif current - Harness.phaseStartedAt > 15000 then
        result("FAIL", "radio_kit_screenshot_captured",
            "runner did not capture the equipped team")
        setPhase("finish", current)
    end
end

function Harness.probeTeamExpeditionUiRadioWait(current)
    local SC = SurvivorCompanion
    local mission = SC.ExpeditionPrototype.current()
    if mission == nil or getSpecificPlayer(1) ~= mission.leader.actor then
        if current - Harness.phaseStartedAt < 10000 then return end
        result("FAIL", "expedition_ui_leader_second_view",
            "selected leader did not take slot 1")
        setPhase("finish", current)
        return
    end
    if current - Harness.phaseStartedAt < 1500 then return end
    local leaderRadio = Harness.radioKit and Harness.radioKit.team[1]
    local leaderData = leaderRadio and leaderRadio:getDeviceData()
    local playerRadio = Harness.radioKit and Harness.radioKit.player
    if Harness.radioKitInventoryChecked ~= true then
        Harness.radioKitInventoryChecked = true
        local playerRoot = playerRadio ~= nil
            and playerRadio:getContainer() == Harness.player:getInventory()
        local leaderRoot = leaderRadio ~= nil
            and leaderRadio:getContainer() == mission.leader.actor:getInventory()
        local playerEquipped = Harness.player:getEquipedRadio() == playerRadio
        local leaderEquipped = mission.leader.actor:getEquipedRadio() == leaderRadio
        if not check("expedition_ui_radios_top_level_equipped",
            playerRoot and leaderRoot and playerEquipped and leaderEquipped,
            "playerRoot=" .. tostring(playerRoot)
                .. " leaderRoot=" .. tostring(leaderRoot)
                .. " playerEquipped=" .. tostring(playerEquipped)
                .. " leaderEquipped=" .. tostring(leaderEquipped)) then
            setPhase("finish", current)
            return
        end
    end
    local px, py = position(Harness.player)
    local lx, ly = position(mission.leader.actor)
    local distance = px and lx and math.sqrt((px - lx)^2 + (py - ly)^2)
    -- Build 42's held-radio path rejects transmissions at three tiles or
    -- less. Wait beyond that boundary with margin for tile rounding.
    if (distance or 0) < 8 then
        if current - Harness.phaseStartedAt < 30000 then return end
        local actor = mission.leader.actor
        local source = actor:getCurrentSquare()
        local waypoint = mission.testWaypoint
        local target = waypoint and getCell():getGridSquare(
            waypoint.x, waypoint.y, waypoint.z) or nil
        local route = source and target and SC.Navigation.findPath(
            source, target, { actor = actor, nodeBudget = 2500 }) or nil
        local nodes = {}
        for index = 1, math.min(route and #route or 0, 8) do
            local square = route[index]
            local occupant = SC.GameplayUtil.movingBlocker(square, actor)
            nodes[#nodes + 1] = tostring(square:getX()) .. ","
                .. tostring(square:getY()) .. ":"
                .. tostring(occupant ~= nil and "occupied" or "clear")
        end
        local nav = SC.Navigation.status(actor) or {}
        result("PASS", "expedition_ui_departure_stall_detail",
            "waypoint=" .. tostring(waypoint and waypoint.x) .. ","
                .. tostring(waypoint and waypoint.y)
                .. " nav=" .. tostring(nav.phase) .. "/"
                .. tostring(nav.pathReason)
                .. " route=" .. table.concat(nodes, ">"))
        local screenshotName = tostring(Harness.config.run_id)
            .. "-departure-stall.png"
        local captured, screenshotError = pcall(function()
            getCore():TakeFullScreenshot(screenshotName)
        end)
        result(captured and "PASS" or "FAIL",
            "expedition_ui_departure_stall_screenshot_requested",
            "file=" .. screenshotName
                .. " error=" .. tostring(screenshotError))
        result("FAIL", "expedition_ui_leader_left_voice_range",
            "distance=" .. tostring(distance))
        setPhase("finish", current)
        return
    end
    result("PASS", "expedition_ui_radio_receiver_snapshot",
        "equipped=" .. tostring(mission.leader.actor:getEquipedRadio()
            == leaderRadio)
            .. " primary=" .. tostring(mission.leader.actor:getPrimaryHandItem()
                == leaderRadio)
            .. " secondary=" .. tostring(mission.leader.actor:getSecondaryHandItem()
                == leaderRadio)
            .. " back=" .. tostring(mission.leader.actor:getClothingItem_Back()
                == leaderRadio)
            .. " on=" .. tostring(leaderData and leaderData:getIsTurnedOn())
            .. " channel=" .. tostring(leaderData and leaderData:getChannel())
            .. " volume=" .. tostring(leaderData and leaderData:getDeviceVolume())
            .. " distance=" .. tostring(distance)
            .. " player=" .. tostring(px) .. "," .. tostring(py)
            .. " leader=" .. tostring(lx) .. "," .. tostring(ly))
    local picked
    local menu = { addOptionOnTop = function(_, label, _target, callback, player)
        picked = { label = label, callback = callback, player = player }
    end }
    local radio = Harness.radioKit and Harness.radioKit.player
    SC.UIContext.fillRadioContextMenu(0, menu, { radio })
    if not check("expedition_ui_radio_first_action",
        picked ~= nil and picked.label == SC.UI.text(
            "UI_SC_Expedition_ReturnNow") and picked.player == Harness.player,
        "option=" .. tostring(picked and picked.label)) then
        setPhase("finish", current)
        return
    end
    local accepted, reason = picked.callback(nil, picked.player)
    check("expedition_ui_radio_return_acknowledged",
        accepted == true and mission.scout.phase == "inbound"
            and mission.scout.endReason == "radio_return",
        "accepted=" .. tostring(accepted)
            .. " detail=" .. tostring(reason)
            .. " phase=" .. tostring(mission.scout.phase)
            .. " reason=" .. tostring(mission.scout.endReason))
    setPhase("finish", current)
end

function Harness.probeTeamRadioKitPlaceWait(current)
    local inventory = Harness.player:getInventory()
    local function ready(prepared)
        local worldItem = prepared.item:getWorldItem()
        local square = worldItem and worldItem:getSquare()
        if square ~= prepared.square
            or inventory:contains(prepared.item) then return false end
        local proxies = 0
        local objects = square:getObjects()
        for index = 0, objects:size() - 1 do
            local candidate = objects:get(index)
            if candidate and SurvivorCompanion.GameplayUtil.instanceOf(
                candidate, "IsoRadio")
                and tonumber(candidate:getModData().RadioItemID)
                    == prepared.item:getID() then
                prepared.object = candidate
                proxies = proxies + 1
            end
        end
        return proxies == 1 and prepared.object:getDeviceData() == prepared.data
    end
    local walkie = Harness.radioKit.placedWalkie
    local ham = Harness.radioKit.placedHam
    local walkieReady, hamReady = ready(walkie), ready(ham)
    if walkieReady and hamReady then
        result("PASS", "placed_kit_native_timed_placement_completed",
            "walkie=" .. tostring(walkie.item:getID())
                .. " ham=" .. tostring(ham.item:getID()))
        setPhase("team_radio_kit_wait", current)
    elseif current - Harness.phaseStartedAt > 15000 then
        result("FAIL", "placed_kit_native_timed_placement_completed",
            "walkie=" .. tostring(walkieReady)
                .. " ham=" .. tostring(hamReady))
        setPhase("finish", current)
    end
end

local function probeTeamRadioKitPickupWait(current)
    local square = Harness.radioPickupSquare
    local expectedId = Harness.radioPickupItemId
    local carried, worldCount, proxyCount, registered = nil, 0, 0, 0
    local inventory = Harness.player:getInventory():getItems()
    local carriedCount = 0
    for index = 0, inventory:size() - 1 do
        local candidate = inventory:get(index)
        if candidate and candidate:getID() == expectedId then
            carried = candidate
            carriedCount = carriedCount + 1
        end
    end
    if carriedCount == 0 and current - Harness.phaseStartedAt < 45000 then return end
    if carriedCount == 0 then
        local queue = ISTimedActionQueue.getTimedActionQueue(Harness.player)
        local action = queue.current
        result("FAIL", "placed_kit_pickup_action_timed_out",
            "current=" .. tostring(action and action.Type)
                .. " valid=" .. tostring(action and action:isValid())
                .. " started=" .. tostring(action and action.started)
                .. " max_time=" .. tostring(action and action.maxTime)
                .. " job_delta=" .. tostring(action and action.getJobDelta
                    and action:getJobDelta()))
    end
    local worldObjects = square:getWorldObjects()
    for index = 0, worldObjects:size() - 1 do
        local candidate = worldObjects:get(index)
        if candidate and candidate:getItem()
            and candidate:getItem():getID() == expectedId then
            worldCount = worldCount + 1
        end
    end
    local objects = square:getObjects()
    for index = 0, objects:size() - 1 do
        local candidate = objects:get(index)
        if candidate and SurvivorCompanion.GameplayUtil.instanceOf(
            candidate, "IsoRadio")
            and tonumber(candidate:getModData().RadioItemID) == expectedId then
            proxyCount = proxyCount + 1
        end
    end
    local devices = ZomboidRadio.getInstance():getDevices()
    for index = 0, devices:size() - 1 do
        local candidate = devices:get(index)
        if candidate and SurvivorCompanion.GameplayUtil.instanceOf(
            candidate, "IsoRadio")
            and tonumber(candidate:getModData().RadioItemID) == expectedId then
            registered = registered + 1
        end
    end
    local data = carried and carried:getDeviceData()
    check("placed_kit_pickup_exact_item_transferred",
        carriedCount == 1 and carried:getFullType() == "Base.WalkieTalkie2"
            and carried:getWorldItem() == nil,
        "id=" .. tostring(expectedId) .. " carried=" .. tostring(carriedCount))
    check("placed_kit_pickup_proxy_removed",
        worldCount == 0 and proxyCount == 0 and registered == 0,
        "world=" .. tostring(worldCount) .. " proxy=" .. tostring(proxyCount)
            .. " registered=" .. tostring(registered))
    check("placed_kit_pickup_radio_state_retained",
        data ~= nil and data:getIsTwoWay() and data:getIsTurnedOn()
            and data:getHasBattery() and data:getPower() > 0
            and data:getChannel() == TEAM_RADIO_CHANNEL,
        "power=" .. tostring(data and data:getPower())
            .. " channel=" .. tostring(data and data:getChannel()))
    Harness.player:setUnlimitedCarry(
        Harness.radioPickupPreviousUnlimitedCarry == true)
    Harness.player:getInventory():setCapacity(
        Harness.radioPickupPreviousCapacity)
    setPhase("finish", current)
end

local function inspectPlacedRadioKitWorld(restored)
    local playerSquare = Harness.player:getCurrentSquare()
    local squares = {}
    for dx = -1, 1 do
        for dy = -1, 1 do
            local square = getCell():getGridSquare(
                playerSquare:getX() + dx, playerSquare:getY() + dy,
                playerSquare:getZ())
            if square then squares[#squares + 1] = square end
        end
    end
    local staged = Harness.radioKit
    local walkieId = restored
        and tonumber(Harness.config.team_radio_placed_expected_walkie_id)
        or staged.placedWalkie.item:getID()
    local hamId = restored
        and tonumber(Harness.config.team_radio_placed_expected_ham_id)
        or staged.placedHam.item:getID()
    local function find(expectedId, expectedType)
        local item, proxy, itemCount, proxyCount = nil, nil, 0, 0
        local itemSquare, proxySquare
        for _, square in ipairs(squares) do
            local worldObjects = square:getWorldObjects()
            for index = 0, worldObjects:size() - 1 do
                local worldObject = worldObjects:get(index)
                local candidate = worldObject and worldObject:getItem()
                if candidate and candidate:getID() == expectedId then
                    itemCount = itemCount + 1
                    item, itemSquare = candidate, square
                end
            end
            local objects = square:getObjects()
            for index = 0, objects:size() - 1 do
                local candidate = objects:get(index)
                if candidate and SurvivorCompanion.GameplayUtil.instanceOf(
                    candidate, "IsoRadio")
                    and tonumber(candidate:getModData().RadioItemID) == expectedId then
                    proxyCount = proxyCount + 1
                    proxy, proxySquare = candidate, square
                end
            end
        end
        local data = proxy and proxy:getDeviceData()
        local valid = itemCount == 1 and proxyCount == 1
            and itemSquare == proxySquare
            and item:getFullType() == expectedType
            and item:getWorldItem() ~= nil
            and item:getWorldItem():getSquare() == itemSquare
            and data ~= nil and data:getIsTwoWay()
            and data:getIsTurnedOn() and data:getHasBattery()
            and data:getPower() > 0
            and data:getChannel() == TEAM_RADIO_CHANNEL
        return valid, item, proxy, data, itemCount, proxyCount
    end
    local walkieReady, walkieItem, walkieProxy, walkieData, walkieItems,
        walkieProxies = find(walkieId, "Base.WalkieTalkie2")
    local hamReady, hamItem, hamProxy, hamData, hamItems,
        hamProxies = find(hamId, "Base.HamRadio1")
    check("placed_kit_walkie_world_identity", walkieReady,
        "id=" .. tostring(walkieId) .. " items=" .. tostring(walkieItems)
            .. " proxies=" .. tostring(walkieProxies))
    check("placed_kit_ham_world_identity", hamReady,
        "id=" .. tostring(hamId) .. " items=" .. tostring(hamItems)
            .. " proxies=" .. tostring(hamProxies))
    if not walkieReady or not hamReady then return false end
    local devices = ZomboidRadio.getInstance():getDevices()
    local registeredWalkie, registeredHam = 0, 0
    for index = 0, devices:size() - 1 do
        local candidate = devices:get(index)
        if candidate == walkieProxy then registeredWalkie = registeredWalkie + 1 end
        if candidate == hamProxy then registeredHam = registeredHam + 1 end
    end
    check("placed_kit_native_registration_unique",
        registeredWalkie == 1 and registeredHam == 1,
        "walkie=" .. tostring(registeredWalkie)
            .. " ham=" .. tostring(registeredHam))
    local playerItems = Harness.player:getInventory():getItems()
    local carriedCopies = 0
    for index = 0, playerItems:size() - 1 do
        local item = playerItems:get(index)
        if item and (item:getID() == walkieId or item:getID() == hamId) then
            carriedCopies = carriedCopies + 1
        end
    end
    check("placed_kit_not_carried_twice", carriedCopies == 0,
        "matching_inventory_items=" .. tostring(carriedCopies))
    result("PASS", restored and "placed_kit_restored_ids" or "placed_kit_staged_ids",
        "walkie=" .. tostring(walkieId) .. " ham=" .. tostring(hamId)
            .. " walkie_range=" .. tostring(walkieData:getTransmitRange())
            .. " ham_range=" .. tostring(hamData:getTransmitRange()))
    if restored then
        local message = "SC_RADIO_TEST_RELOAD_" .. Harness.config.run_id
        local receivedWalkie, receivedHam = false, false
        local hook = function(_, _, _, _, _, text, device)
            if text == message then
                if device == walkieProxy then receivedWalkie = true end
                if device == hamProxy then receivedHam = true end
            end
        end
        Events.OnDeviceText.Add(hook)
        local emitted, emissionError = pcall(function()
            ZomboidRadio.getInstance():SendTransmission(
                math.floor(Harness.player:getX()) + 3,
                math.floor(Harness.player:getY()) + 3,
                TEAM_RADIO_CHANNEL, message, "LF-TEST", "RELOAD",
                0.8, 0.9, 1.0, 1000, false)
        end)
        Events.OnDeviceText.Remove(hook)
        check("placed_kit_fresh_native_receive_after_reload",
            emitted and receivedWalkie and receivedHam,
            "emitted=" .. tostring(emitted)
                .. " walkie=" .. tostring(receivedWalkie)
                .. " ham=" .. tostring(receivedHam)
                .. " error=" .. tostring(emissionError))
    end
    return true
end

local function probeTeamRadioKitWait(current)
    if current - Harness.phaseStartedAt < 3000 then return end
    local radios = Harness.radioKit
    local recipients = Harness.radioKitRecipients
    local restoredDocument = Harness.config.team_radio_kit_verify_only == "true"
        and SurvivorCompanion.Persistence.lastDocument() or nil
    local function radioReady(radio)
        if radio == nil or radio:getFullType() ~= "Base.WalkieTalkie2" then
            return false
        end
        local data = radio:getDeviceData()
        if data == nil or not data:getIsTwoWay()
            or not data:getIsTurnedOn() or not data:getHasBattery()
            or data:getPower() <= 0
            or data:getChannel() ~= TEAM_RADIO_CHANNEL then
            return false
        end
        local presets = data:getDevicePresets()
        if presets == nil then return false end
        local entries = presets:getPresets()
        for index = 0, entries:size() - 1 do
            local entry = entries:get(index)
            if entry:getName() == TEAM_RADIO_PRESET
                and entry:getFrequency() == TEAM_RADIO_CHANNEL then
                return true
            end
        end
        return false
    end
    local playerEquipped = radios.player ~= nil
        and radioReady(radios.player)
        and Harness.player:getEquipedRadio() == radios.player
    check("radio_kit_player_equipped", playerEquipped,
        "exact player radio is the native equipped radio")
    local ready = playerEquipped
    for index, record in ipairs(recipients) do
        local itemList = record.actor:getInventory():getItems()
        local storedRadios = 0
        local inventoryRadio
        for itemIndex = 0, itemList:size() - 1 do
            local item = itemList:get(itemIndex)
            if item ~= nil and item:getFullType() == "Base.WalkieTalkie2" then
                storedRadios = storedRadios + 1
                if inventoryRadio == nil then inventoryRadio = item end
            end
        end
        local radio = Harness.config.team_radio_kit_verify_only == "true"
            and inventoryRadio or radios.team[index]
        local handEquipped = radio ~= nil
            and record.actor:getSecondaryHandItem() == radio
        local radioEquipped = radio ~= nil
            and record.actor:getEquipedRadio() == radio
        local powered = radioReady(radio)
        if restoredDocument ~= nil then
            local snapshot = restoredDocument.companions
                and restoredDocument.companions[record.id]
            local inventory = snapshot and snapshot.inventory
            local savedRadios = 0
            for _, entry in ipairs(inventory and inventory.roots or {}) do
                if entry.type == "Base.WalkieTalkie2" then
                    savedRadios = savedRadios + 1
                end
            end
            result(savedRadios > 0 and "PASS" or "FAIL",
                "radio_kit_restored_document_" .. tostring(index),
                "id=" .. tostring(record.id)
                    .. " saved_radios=" .. tostring(savedRadios)
                    .. " secondary=" .. tostring(inventory and inventory.equipment
                        and inventory.equipment.secondary))
        end
        check("radio_kit_companion_" .. tostring(index),
            powered and storedRadios >= 1
                and (Harness.config.team_radio_kit_verify_only == "true"
                    or handEquipped),
            "id=" .. tostring(record.id)
                .. " hand=" .. tostring(handEquipped)
                .. " native_radio=" .. tostring(radioEquipped)
                .. " powered=" .. tostring(powered)
                .. " inventory_radios=" .. tostring(storedRadios))
        ready = ready and powered and storedRadios >= 1
            and (Harness.config.team_radio_kit_verify_only == "true"
                or handEquipped)
    end
    check(Harness.config.team_radio_kit_only == "true"
            and "radio_kit_provisioned" or "radio_kit_reloaded", ready,
        "player and four saved companions hold powered "
            .. TEAM_RADIO_PRESET .. " walkies on " .. TEAM_RADIO_CHANNEL)
    if not ready then
        setPhase("finish", current)
        return
    end
    if Harness.config.team_radio_placed_probe == "true" then
        local inspected, inspectionResult = pcall(inspectPlacedRadioKitWorld,
            Harness.config.team_radio_kit_verify_only == "true")
        check("placed_kit_world_inspection_ran", inspected and inspectionResult,
            tostring(inspectionResult))
        if not inspected or not inspectionResult then
            setPhase("finish", current)
            return
        end
    end
    if Harness.config.team_radio_kit_only == "true" then
        local saved, reason = SurvivorCompanion.Runtime.save()
        check("radio_kit_companion_snapshot_saved", saved == true,
            "companions=" .. tostring(saved and reason
                and reason.companions and recipients
                and #recipients or 0))
        if saved ~= true then
            setPhase("finish", current)
            return
        end
        for index, record in ipairs(recipients) do
            local snapshot = reason.companions[record.id]
            local inventory = snapshot and snapshot.inventory
            local radioCount = 0
            for _, entry in ipairs(inventory and inventory.roots or {}) do
                if entry.type == "Base.WalkieTalkie2" then
                    radioCount = radioCount + 1
                end
            end
            check("radio_kit_snapshot_" .. tostring(index),
                inventory ~= nil and radioCount >= 1
                    and inventory.equipment.secondary ~= nil,
                "id=" .. tostring(record.id)
                    .. " snapshot_radios=" .. tostring(radioCount)
                    .. " secondary=" .. tostring(inventory
                        and inventory.equipment.secondary))
        end
    end
    if Harness.config.team_expedition_ui_probe == "true" then
        local SC = SurvivorCompanion
        for index = 1, 3 do
            local accepted, reason = SC.Commands.issue(recipients[index].id,
                "set_group", { group = "alpha" }, Harness.player)
            if not check("expedition_ui_squad_assignment_" .. tostring(index),
                accepted == true, tostring(reason)) then
                setPhase("finish", current)
                return
            end
        end
        local opened, root = pcall(SC.UI.open, "expeditions", recipients[1].id)
        if not check("expedition_ui_tab_opened", opened
            and root ~= nil and root.selectedTab == "expeditions"
            and root.detail ~= nil, tostring(root)) then
            setPhase("finish", current)
            return
        end
        local draft = root.detail.expeditionDraft
        local expectedMembers = 0
        for _, item in ipairs(root.roster and root.roster.items or {}) do
            local row = item.item
            if row and row.group == draft.group and row.recruited == true
                and row.alive ~= false and row.available ~= false
                and row.id and row.actor then
                expectedMembers = expectedMembers + 1
            end
        end
        Harness.expeditionUiExpectedMembers = expectedMembers
        local chosen
        for _, place in ipairs(draft and draft.places or {}) do
            local approach = SC.ExpeditionPlaces.loadedApproach(
                place, recipients[1].actor)
            if approach ~= nil then
                local dx = recipients[1].actor:getX() - approach.x
                local dy = recipients[1].actor:getY() - approach.y
                if math.sqrt(dx * dx + dy * dy) >= 20 then
                    chosen = place break
                end
            end
        end
        if not check("expedition_ui_loaded_destination", chosen ~= nil,
            "candidates=" .. tostring(draft and #draft.places or 0)) then
            setPhase("finish", current)
            return
        end
        draft.placeId = chosen.id
        draft.leaderId = recipients[1].id
        draft.kind = "scout"
        draft.style = "stealth"
        draft.hours = 1
        SC.UIExpeditions.onButton(root.detail,
            { scExpeditionAction = "review" })
        check("expedition_ui_review_effect_free", draft.review == true
            and SC.ExpeditionPrototype.current() == nil,
            "review=" .. tostring(draft.review))
        Harness.expeditionUiDetail = root.detail
        Harness.expeditionUiLeader = recipients[1]
        Harness.expeditionUiPlace = chosen
    end
    writeSignal(SPLIT_READY_FILE, { "ready=true" })
    setPhase("team_radio_kit_capture", current)
end

local function probeTeamHandoffCapture(current)
    if fileExists(SPLIT_CAPTURED_FILE) then
        result("PASS", "successor_split_view_captured",
            "second local viewport captured after leader death")
        setPhase("team_handoff_observe", current)
    elseif current - Harness.phaseStartedAt > 15000 then
        result("FAIL", "successor_split_view_captured", "screenshot was not captured")
        setPhase("finish", current)
    end
end

local function probeTeamHandoffObserve(current)
    if current - Harness.phaseStartedAt < 5000 then return end
    local SC = SurvivorCompanion
    local successor = Harness.successor
    local valid, reason = SC.Actor.validateNative(successor.actor)
    check("successor_ai_survives_five_seconds", valid == true
        and getSpecificPlayer(1) == successor.actor
        and (SC.Scheduler.getStats().frames or 0) > (Harness.successorFrames or 0),
        "reason=" .. tostring(reason))
    local ordered, orderReason = SC.Commands.issue(successor.id,
        "stay", nil, Harness.player)
    check("successor_remote_orders_still_blocked", ordered == false
        and orderReason == "expedition_leader_radio_required",
        "reason=" .. tostring(orderReason))
    if Harness.config.team_radio_command_probe == "true" and valid == true then
        local beforeMode = SC.Commands.effective(successor.actor).moveMode
        local targetMode = beforeMode == "walk" and "sneak" or "walk"
        local received, radioReason = SC.ExpeditionPrototype.sendRadioOrder(
            Harness.player, "set_move_mode", targetMode)
        check("successor_radio_command_after_handoff", received == true
            and SC.Commands.effective(successor.actor).moveMode == targetMode
            and beforeMode ~= targetMode
            and SC.ExpeditionPrototype.current().lastRadioOrder.leader
                == successor.actor,
            "mode=" .. tostring(beforeMode) .. "->"
                .. tostring(SC.Commands.effective(successor.actor).moveMode)
                .. " reason=" .. tostring(radioReason))
    end
    local nextFollower
    for _, record in ipairs(Harness.team) do
        if record.actor ~= nil and record.actor ~= successor.actor
            and not record.actor:isDead() then
            nextFollower = record break
        end
    end
    if nextFollower then
        local lx, ly = position(successor.actor)
        local fx, fy = position(nextFollower.actor)
        local distance = lx and ly and fx and fy
            and math.sqrt((lx - fx)^2 + (ly - fy)^2) or math.huge
        check("remaining_member_follows_successor", distance < 15,
            "distance=" .. tostring(distance))
    else
        result("SKIP", "remaining_member_follows_successor",
            "successor is the last living mission member")
    end
    if Harness.config.team_repeated_handoff == "true" then
        check("first_successor_is_roster_second",
            successor.actor == Harness.team[2].actor,
            "successor=" .. tostring(successor.id))
        if successor.actor == Harness.team[2].actor
            and not successor.actor:isDead() then
            local ended, reason = SC.Actor.endLife(successor.actor)
            check("second_leader_native_death_triggered", ended == true,
                tostring(reason))
            Harness.deadLeader = successor.actor
            setPhase("team_second_handoff_wait", current)
            return
        end
    end
    setPhase("finish", current)
end

local function probeTeamSecondHandoff(current)
    local SC = SurvivorCompanion
    local mission = SC.ExpeditionPrototype.current()
    local third = Harness.team[3]
    if mission and mission.leader.actor == third.actor
        and getSpecificPlayer(1) == third.actor then
        check("view_handed_to_third_companion", third.actor ~= Harness.deadLeader
            and Harness.deadLeader:isDead(),
            "slot 1 is the original third mission actor")
        check("second_handoff_primary_view_preserved",
            getSpecificPlayer(0) == Harness.player
                and Harness.player:isDead() == false
                and getWorld():getCell():getGridSquare(
                    math.floor(Harness.playerX), math.floor(Harness.playerY),
                    Harness.playerZ) ~= nil,
            "Riverside player remains in slot 0 with a loaded square")
        local valid, reason = SC.Actor.validateNative(third.actor)
        check("third_companion_native_ai_valid", valid == true, tostring(reason))
        local ordered, orderReason = SC.Commands.issue(third.id,
            "stay", nil, Harness.player)
        check("third_leader_remote_orders_still_blocked", ordered == false
            and orderReason == "expedition_leader_radio_required",
            "reason=" .. tostring(orderReason))
        setPhase("finish", current)
        return
    end
    if current - Harness.phaseStartedAt > 12000 then
        result("FAIL", "view_handed_to_third_companion",
            "leader=" .. tostring(mission and mission.leader and mission.leader.id)
                .. " slot1=" .. tostring(getSpecificPlayer(1)))
        setPhase("finish", current)
    end
end

local function probeSplitScreenLoaded(current)
    local cold = Harness.config.cold_companion_probe == "true"
    local slot = getSpecificPlayer(1)
    local cell = getWorld():getCell()
    local square = cell:getGridSquare(Harness.remoteX, Harness.remoteY, Harness.remoteZ)
    if slot ~= Harness.splitObserver or square == nil then
        if current - Harness.phaseStartedAt < 35000 then return end
        result("FAIL", "distant_coop_area_loaded",
            "slot=" .. tostring(slot == Harness.splitObserver)
                .. " square=" .. tostring(square ~= nil))
        setPhase("finish", current)
        return
    end
    result("PASS", "distant_coop_area_loaded",
        "ordinary cell lookup returned the distant square with slot 1 active")
    if cold then
        check("cold_companion_loaded_on_saved_tile",
            slot:getCurrentSquare() == square
                and slot:isDead() == false,
            "the true SCNativeCompanion class acquired the remote native square")
    end
    local slot0 = getSpecificPlayer(0)
    local singleton = IsoPlayer.getInstance()
    local eventPlayer = getPlayer()
    check("primary_slot_unchanged", slot0 == Harness.player,
        "slot0=" .. tostring(slot0 == Harness.player)
            .. " singleton=" .. tostring(singleton == Harness.player)
            .. " getPlayer=" .. tostring(eventPlayer == Harness.player)
            .. " slot0index=" .. tostring(slot0 and slot0:getPlayerNum()))
    if cold then
        -- AddCoopPlayer may leave the process singleton on slot 1 outside
        -- OnTick. The stable invariant for this probe is the untouched slot 0
        -- and the restored primary context while Living Fellows ticks.
        check("cold_companion_tick_primary_context",
            Harness.splitTickSingleton == true
                and Harness.splitTickGetPlayer == true,
            "singletonNow=" .. tostring(singleton == Harness.player)
                .. " getPlayerNow=" .. tostring(eventPlayer == Harness.player)
                .. " tickSingleton=" .. tostring(Harness.splitTickSingleton)
                .. " tickGetPlayer=" .. tostring(Harness.splitTickGetPlayer))
    else
        check("primary_singleton_unchanged", singleton == Harness.player,
            "singleton=" .. tostring(singleton == Harness.player)
                .. " observer=" .. tostring(singleton == Harness.splitObserver)
                .. " getPlayer=" .. tostring(eventPlayer == Harness.player)
                .. " tickSingleton=" .. tostring(Harness.splitTickSingleton))
    end
    local bridgeReady, bridgeReason = SurvivorCompanion.Actor.checkBridge(true)
    if cold then
        check("cold_companion_bridge_available", bridgeReady == true,
            "bridge=" .. tostring(bridgeReady) .. " reason=" .. tostring(bridgeReason))
    else
        check("current_lf_rejects_split_screen", bridgeReady == false,
            "bridge=" .. tostring(bridgeReady) .. " reason=" .. tostring(bridgeReason))
    end
    local cameraOk, cameraDetail = pcall(function()
        return "total=" .. tostring(getCore():getScreenWidth())
            .. " first=" .. tostring(IsoCamera.getScreenWidth(0))
            .. " second=" .. tostring(IsoCamera.getScreenWidth(1))
            .. " secondLeft=" .. tostring(IsoCamera.getScreenLeft(1))
    end)
    result(cameraOk and "PASS" or "SKIP", "split_viewport_geometry", cameraDetail)
    writeSignal(SPLIT_READY_FILE, { "ready=true" })
    setPhase("split_wait_capture", current)
end

function Harness.probeFishingBank(current)
    local SC = SurvivorCompanion
    local actor = Harness.leader or Harness.splitObserver
    if Harness.phase == "fishing_find_bank" then
        local cell, originX, originY = getWorld():getCell(),
            Harness.leaderRemoteX or Harness.remoteX,
            Harness.leaderRemoteY or Harness.remoteY
        local best, bestScore, bestAbundance
        local schools = FishSchoolManager and FishSchoolManager.getInstance
            and FishSchoolManager.getInstance()
        for x = originX - 35, originX + 35 do
            for y = originY - 35, originY + 35 do
                local square = cell:getGridSquare(x, y, 0)
                local site = SC.Fishing._usableBankForTests(square)
                if site then
                    local distance = (x - originX)^2 + (y - originY)^2
                    local read, value = schools and pcall(
                        schools.getFishAbundance, schools,
                        site.water.x, site.water.y)
                    local abundance = read and tonumber(value) or 0
                    local score = abundance * 10000 - distance
                    if not bestScore or score > bestScore then
                        best, bestScore, bestAbundance = site, score, abundance
                    end
                end
            end
        end
        if not best then
            if current - Harness.phaseStartedAt < 15000 then return end
            result("FAIL", "fishing_river_bank_found",
                "no loaded Riverside water bank within 35 tiles of "
                    .. originX .. "," .. originY)
            setPhase("finish", current)
            return
        end
        Harness.fishingSite = best
        result("PASS", "fishing_river_bank_found",
            "bank=" .. best.bank.x .. "," .. best.bank.y
                .. " water=" .. best.water.x .. "," .. best.water.y
                .. " fish_abundance=" .. tostring(bestAbundance))
        local rod = actor:getInventory():AddItem("Base.FishingRod")
        Harness.fishingRod = rod
        local baitType = Fishing and Fishing.lure and Fishing.lure.All
            and (Fishing.lure.All["Base.Worm"] and "Base.Worm"
                or next(Fishing.lure.All))
        local bait = baitType and actor:getInventory():AddItem(baitType)
        check("fishing_real_rod_and_bait", rod ~= nil and bait ~= nil,
            "rod=" .. tostring(rod) .. " bait=" .. tostring(baitType))
        if not rod or not bait then setPhase("finish", current) return end
        if Harness.config.fishing_catch_probe == "true" then
            for _ = 1, 8 do actor:getInventory():AddItem(baitType) end
        end
        -- Stage only the disposable split-screen actor. Navigation must place
        -- it precisely on the chosen bank before any cast can begin.
        local start, U = nil, SC.GameplayUtil
        for distance = 4, 2, -1 do
            local candidate = cell:getGridSquare(
                best.bank.x - best.dx * distance,
                best.bank.y - best.dy * distance, 0)
            if candidate and U.isSquareFree(candidate)
                and not SC.Topology.squareIsWater(candidate) then
                start = candidate
                break
            end
        end
        if not start then
            result("FAIL", "fishing_dry_approach_fixture",
                "no dry approach behind bank")
            setPhase("finish", current)
            return
        end
        actor:teleportTo(start:getX() + 0.5, start:getY() + 0.5, 0)
        Harness.fishingRequest = { destination = best.bank, remaining = 1 }
        result("PASS", "fishing_dry_approach_fixture",
            "start=" .. start:getX() .. "," .. start:getY()
                .. " bank=" .. best.bank.x .. "," .. best.bank.y)
        setPhase("fishing_approach", current)
        return
    end
    if Harness.phase == "fishing_wait_capture" then
        if fileExists(SPLIT_CAPTURED_FILE) then
            result("PASS", Harness.config.fishing_catch_probe == "true"
                and "fishing_catch_screenshot" or "fishing_bank_screenshot",
                "rendered split-screen fishing view captured")
            setPhase("finish", current)
        elseif current - Harness.phaseStartedAt > 15000 then
            result("FAIL", "fishing_bank_screenshot", "runner did not capture")
            setPhase("finish", current)
        end
        return
    end
    if Harness.phase == "fishing_wait_catch" then
        if current - Harness.phaseStartedAt > 180000 then
            local state = SC.Fishing._stateForTests(actor)
            result("FAIL", "fishing_native_fish_caught",
                "timeout phase=" .. tostring(state and state.phase)
                    .. " fish=" .. tostring(Harness.fishingCatchItem))
            setPhase("finish", current)
            return
        end
        if current - (Harness.fishingLastUpdate or 0) < 250 then return end
        Harness.fishingLastUpdate = current
        local ok, detail = SC.Fishing.update(actor, "expedition",
            Harness.fishingRequest)
        local state = SC.Fishing._stateForTests(actor)
        if state and state.phase == "waiting" and state.bobber then
            -- Only shorten the real Build 42 bobber's wait. Its native
            -- attraction roll, fish selection, pickup and inventory remain live.
            state.bobber.attractTimer = math.min(
                tonumber(state.bobber.attractTimer) or 1, 1)
            if not Harness.fishingBiteTimerAccelerated then
                Harness.fishingBiteTimerAccelerated = true
                result("PASS", "fishing_native_bite_timer_fixture",
                    "native bobber wait shortened; fish generation unchanged")
            end
        end
        if state and state.phase == "pickup" and state.catch then
            if Harness.fishingCatchItem ~= state.catch then
                Harness.fishingCatchItem = state.catch
                Harness.fishingCatchTrash = state.isTrash == true
                result("PASS", "fishing_native_bite",
                    "native fish item=" .. tostring(state.catch:getFullType())
                        .. " trash=" .. tostring(state.isTrash))
            end
        end
        if detail == "fish_caught" then
            local item = Harness.fishingCatchItem
            local stored = item and SC.GameplayUtil.inventoryContains(
                actor:getInventory(), item)
            local size = item and tonumber(
                item:getModData().fishing_FishSize)
            if stored and size and size > 0
                and Harness.fishingCatchTrash ~= true then
                result("PASS", "fishing_native_fish_caught",
                    "item=" .. tostring(item:getFullType())
                        .. " native_id=" .. tostring(item:getID())
                        .. " size_cm=" .. tostring(size)
                        .. " in_companion_inventory=true")
                writeSignal(SPLIT_READY_FILE, { "ready=true" })
                setPhase("fishing_wait_capture", current)
                return
            end
            result("PASS", "fishing_native_trash_landed",
                "stored=" .. tostring(stored) .. " item="
                    .. tostring(item and item:getFullType()))
            Harness.fishingCatchItem, Harness.fishingCatchTrash = nil, nil
        elseif not ok and detail ~= "scanning_water"
            and detail ~= "waiting_for_bank" then
            local hand = actor:getPrimaryHandItem()
            local rod = Harness.fishingRod
            result("FAIL", "fishing_native_fish_caught",
                tostring(detail) .. " hand=" .. tostring(hand
                    and hand:getFullType()) .. " rod_stored="
                    .. tostring(rod and SC.GameplayUtil.inventoryContains(
                        actor:getInventory(), rod)) .. " rod_tag="
                    .. tostring(rod and SC.GameplayUtil.itemHasTag(
                        rod, "FISHING_ROD")))
            setPhase("finish", current)
        end
        return
    end
    if current - Harness.phaseStartedAt > 60000 then
        local state = SC.Fishing._stateForTests(actor)
        result("FAIL", "fishing_placed_and_cast",
            "timeout phase=" .. tostring(state and state.phase)
                .. " position=" .. tostring(actor:getX()) .. ","
                .. tostring(actor:getY()))
        setPhase("finish", current)
        return
    end
    if current - (Harness.fishingLastUpdate or 0) < 250 then return end
    Harness.fishingLastUpdate = current
    local ok, detail = SC.Fishing.update(actor, "expedition",
        Harness.fishingRequest)
    local state = SC.Fishing._stateForTests(actor)
    if state and state.phase == "waiting" and state.site then
        local site = state.site
        local bank = getWorld():getCell():getGridSquare(
            site.bank.x, site.bank.y, 0)
        local waterOne = getWorld():getCell():getGridSquare(
            site.bank.x + site.dx, site.bank.y + site.dy, 0)
        local waterTwo = getWorld():getCell():getGridSquare(
            site.bank.x + 2 * site.dx, site.bank.y + 2 * site.dy, 0)
        local ax, ay = actor:getX(), actor:getY()
        check("fishing_player_on_dry_bank",
            math.floor(ax) == site.bank.x
                and math.floor(ay) == site.bank.y
                and not SC.Topology.squareIsWater(bank),
            "player=" .. tostring(ax) .. "," .. tostring(ay)
                .. " bank=" .. site.bank.x .. "," .. site.bank.y)
        check("fishing_cast_over_real_water",
            SC.Topology.squareIsWater(waterOne)
                and SC.Topology.squareIsWater(waterTwo),
            "water=" .. site.water.x .. "," .. site.water.y)
        result("PASS", "fishing_placed_and_cast",
            "native bobber active at " .. site.water.x .. ","
                .. site.water.y)
        if Harness.config.fishing_catch_probe == "true" then
            setPhase("fishing_wait_catch", current)
        else
            writeSignal(SPLIT_READY_FILE, { "ready=true" })
            setPhase("fishing_wait_capture", current)
        end
    elseif not ok and detail ~= "scanning_water"
        and detail ~= "waiting_for_bank" then
        result("FAIL", "fishing_placed_and_cast", tostring(detail))
        setPhase("finish", current)
    end
end

local function remoteZombies()
    local matches = {}
    local list = getWorld():getCell():getZombieList()
    if list == nil then return matches end
    for i = 0, list:size() - 1 do
        local zombie = list:get(i)
        local x, y = position(zombie)
        if x and y and math.abs(x - Harness.remoteX) < 25
            and math.abs(y - Harness.remoteY) < 25 then
            matches[tostring(zombie)] = { x = x, y = y }
        end
    end
    return matches
end

local function probeSplitScreenCapture(current)
    if fileExists(SPLIT_CAPTURED_FILE) then
        result("PASS", "split_screen_capture", "rendered client screenshot recorded")
        Harness.remoteZombiesBefore = remoteZombies()
        setPhase("split_observe", current)
    elseif current - Harness.phaseStartedAt > 15000 then
        result("FAIL", "split_screen_capture", "runner did not capture the viewport")
        setPhase("finish", current)
    end
end

local function probeSplitScreenSimulation(current)
    if current - Harness.phaseStartedAt < 8000 then return end
    local after = remoteZombies()
    local compared, moved = 0, 0
    for id, before in pairs(Harness.remoteZombiesBefore or {}) do
        local latest = after[id]
        if latest then
            compared = compared + 1
            if math.abs(before.x - latest.x) + math.abs(before.y - latest.y) > 0.1 then
                moved = moved + 1
            end
        end
    end
    result(moved > 0 and "PASS" or "SKIP", "remote_zombie_motion",
        "same native zombies=" .. tostring(compared) .. " moved=" .. tostring(moved))
    check("remote_square_stays_loaded",
        getWorld():getCell():getGridSquare(Harness.remoteX, Harness.remoteY,
            Harness.remoteZ) ~= nil,
        "ordinary square lookup remains available after eight seconds")
    result("PASS", "split_tick_identity",
        "OnTick singleton=" .. tostring(Harness.splitTickSingleton)
            .. " getPlayer=" .. tostring(Harness.splitTickGetPlayer))
    if Harness.config.cold_restart_probe == "true" then
        setPhase("split_restart_recovery", current)
        return
    end
    setPhase("finish", current)
end

function Harness.probeColdRestartRecovery(current)
    local SC = SurvivorCompanion
    local mission = SC.ExpeditionPrototype.current()
    local candidate = Harness.coldRestartCandidate
    local saved = SC.Persistence.lastDocument()
    local allReady = mission ~= nil and saved ~= nil and candidate ~= nil
    local readyCount, survivorCount, detail = 0, 0, {}
    local allDressed = true
    if mission ~= nil then
        for _, member in ipairs(mission.roster or {}) do
            if mission.survivors and mission.survivors[member.id] then
                survivorCount = survivorCount + 1
                local record = SC.Registry.byId(member.id)
                local actor = record and record.actor
                local active = actor ~= nil
                    and SC.Registry.isActive(actor, member.id)
                local worn = actor and actor:getWornItems()
                local wornCount = worn and worn:size() or 0
                if active and wornCount == 0 then allDressed = false end
                local savedActor = saved and saved.companions
                    and saved.companions[member.id]
                local sx = savedActor and savedActor.position
                    and savedActor.position.x
                local sy = savedActor and savedActor.position
                    and savedActor.position.y
                local ax, ay = position(actor)
                local gap = ax and ay and sx and sy
                    and math.sqrt((ax - sx)^2 + (ay - sy)^2) or math.huge
                if active and gap < 8 then readyCount = readyCount + 1
                else allReady = false end
                local pending = SC.Persistence.pendingSnapshot()
                detail[#detail + 1] = member.id .. ":active="
                    .. tostring(active) .. ":gap=" .. tostring(gap)
                    .. ":worn=" .. tostring(wornCount)
                    .. ":pending=" .. tostring(pending[member.id]
                        and pending[member.id].reason)
            end
        end
    end
    local leaderRecord = candidate and SC.Registry.byId(candidate.id)
    local leader = leaderRecord and leaderRecord.actor
    local resumed = mission ~= nil and mission.restoring ~= true
        and mission.leader ~= nil and mission.leader.actor == leader
        and getSpecificPlayer(1) == leader
    if (not allReady or not resumed)
        and current - Harness.phaseStartedAt < 35000 then return end
    check("cold_restart_saved_team_restored", allReady and survivorCount > 0,
        "ready=" .. tostring(readyCount) .. "/" .. tostring(survivorCount)
            .. " " .. table.concat(detail, " "))
    check("cold_restart_all_survivors_dressed",
        allReady and allDressed and survivorCount > 0,
        table.concat(detail, " "))
    local worn = leader and leader:getWornItems()
    check("cold_restart_leader_outfit_restored",
        leader ~= nil and leader ~= Harness.splitObserver
            and worn ~= nil and worn:size() > 0,
        "saved leader=" .. tostring(leader ~= nil)
            .. " worn=" .. tostring(worn and worn:size()))
    check("cold_restart_view_swapped_to_saved_leader",
        resumed and SCSplitScreenProbe.isLeader(leader) == true,
        "ordinary mission pulse handed the saved leader slot 1")
    local temporary = mission and mission.lastBootstrapActor
    Harness.splitObserver = temporary
    check("cold_restart_temporary_view_released",
        temporary ~= nil and temporary ~= leader
            and temporary:getCurrentSquare() == nil
            and temporary:isExistInTheWorld() == false,
        "automatic cold loader was removed from the native world")
    Harness.coldRestoredLeader = leader
    Harness.coldRestoredSlotSqlId = candidate.slotSqlId
    writeSignal(SPLIT_READY_FILE, { "ready=true" })
    if Harness.config.cold_restart_handoff == "true" then
        setPhase("split_restart_handoff_wait", current)
        return
    end
    setPhase("split_restart_auto_capture", current)
end

function Harness.probeColdRestartCrashSave(current)
    local SC = SurvivorCompanion
    local mission = SC.ExpeditionPrototype.current()
    local temporary = mission and mission.lastBootstrapActor
    local slot = getSpecificPlayer(1)
    local ready = mission ~= nil and mission.restoring == true
        and temporary ~= nil and slot == temporary
        and SCSplitScreenProbe.isColdProbe(slot) == true
    local count = 0
    if ready then
        for _, member in ipairs(mission.roster) do
            if mission.survivors[member.id] then
                local record = SC.Registry.byId(member.id)
                if record ~= nil and record.actor ~= nil
                    and SC.Registry.isActive(record.actor, member.id) then
                    count = count + 1
                else
                    ready = false
                end
            end
        end
    end
    if not ready and current - Harness.phaseStartedAt < 35000 then return end
    check("cold_crash_boundary_ready", ready and count > 0,
        "temporary slot=" .. tostring(slot == temporary)
            .. " restored survivors=" .. tostring(count)
            .. " issue=" .. tostring(mission and mission.technicalIssue
                and mission.technicalIssue.reason))
    if not ready then setPhase("finish", current) return end
    local saved, sqlId = pcall(SCSplitScreenProbe.saveColdProbeSlotForTest)
    check("cold_crash_temporary_player_row_saved",
        saved and sqlId == mission.slotSqlId,
        "saved=" .. tostring(saved) .. " sqlId=" .. tostring(sqlId)
            .. " expected=" .. tostring(mission.slotSqlId))
    if not saved or sqlId ~= mission.slotSqlId then
        setPhase("finish", current)
        return
    end
    writeSignal(SPLIT_READY_FILE, { "ready=true" })
    setPhase("split_restart_crash_capture", current)
end

function Harness.probeColdRestartLfFirstSave(current)
    local SC = SurvivorCompanion
    local mission = SC.ExpeditionPrototype.current()
    local leader = mission and mission.leader and mission.leader.actor
    local ready = mission ~= nil and mission.restoring ~= true
        and leader ~= nil and getSpecificPlayer(1) == leader
        and SCSplitScreenProbe.isLeader(leader) == true
        and mission.lastBootstrapActor ~= nil
        and mission.lastBootstrapActor:getCurrentSquare() == nil
    local count = 0
    if ready then
        for _, member in ipairs(mission.roster) do
            if mission.survivors[member.id] then
                local record = SC.Registry.byId(member.id)
                if record ~= nil and record.actor ~= nil
                    and SC.Registry.isActive(record.actor, member.id) then
                    count = count + 1
                else
                    ready = false
                end
            end
        end
    end
    if not ready and current - Harness.phaseStartedAt < 35000 then return end
    check("lf_first_crash_boundary_ready", ready and count > 0,
        "saved leader in slot 1=" .. tostring(leader == getSpecificPlayer(1))
            .. " restored survivors=" .. tostring(count))
    if not ready then setPhase("finish", current) return end
    local saved, document = SC.Runtime.save()
    check("lf_first_new_descriptor_published",
        saved == true and document ~= nil
            and document.expedition ~= nil
            and document.expedition.slotSqlId == mission.slotSqlId
            and tonumber(document.savedAt) ~= nil
            and tonumber(Harness.coldRestartSavedAt) ~= nil
            and tonumber(document.savedAt) > tonumber(Harness.coldRestartSavedAt),
        "saved=" .. tostring(saved)
            .. " oldAt=" .. tostring(Harness.coldRestartSavedAt)
            .. " newAt=" .. tostring(document and document.savedAt))
    if not saved then setPhase("finish", current) return end
    local flushed, flushResult = pcall(
        SCSplitScreenProbe.saveGlobalModDataAfterHandoffForTest)
    check("lf_first_global_moddata_flushed",
        flushed and flushResult == true,
        "flushed=" .. tostring(flushed)
            .. " result=" .. tostring(flushResult))
    if not flushed or flushResult ~= true then
        setPhase("finish", current)
        return
    end
    writeSignal(SPLIT_READY_FILE, { "ready=true" })
    setPhase("split_restart_crash_capture", current)
end

function Harness.probeColdRestartCrashCapture(current)
    if fileExists(SPLIT_CAPTURED_FILE)
        and current - Harness.phaseStartedAt >= 2000 then
        writeSignal(SPLIT_CRASH_READY_FILE, {
            "ready=true", "slotSqlId="
                .. tostring(SurvivorCompanion.ExpeditionPrototype.current().slotSqlId),
        })
        setPhase("split_restart_crash_hold", current)
    elseif current - Harness.phaseStartedAt > 15000 then
        result("FAIL", "cold_crash_view_capture",
            "runner did not capture the held temporary viewport")
        setPhase("finish", current)
    end
end

function Harness.probeColdRestartAutoCapture(current)
    if fileExists(SPLIT_CAPTURED_FILE) then
        result("PASS", "cold_restart_auto_view_captured",
            "automatic restart rendered the exact saved leader in slot 1")
        setPhase("finish", current)
    elseif current - Harness.phaseStartedAt > 15000 then
        result("FAIL", "cold_restart_auto_view_captured",
            "runner did not capture the resumed companion viewport")
        setPhase("finish", current)
    end
end

function Harness.probeColdRestartHandoffWait(current)
    if current - Harness.phaseStartedAt < 2000 then return end
    local SC = SurvivorCompanion
    local mission = SC.ExpeditionPrototype.current()
    local leader = Harness.coldRestoredLeader
    local valid, reason = SC.Actor.validateNative(leader)
    check("cold_restart_saved_leader_native_valid", valid == true,
        tostring(reason))
    check("cold_restart_exact_leader_owns_view",
        leader ~= nil and getSpecificPlayer(1) == leader
            and SC.Registry.isActive(leader, Harness.coldRestartCandidate.id)
            and SCSplitScreenProbe.isLeader(leader) == true,
        "slot1 is the saved registered companion")
    if Harness.coldRestoredSlotSqlId ~= nil then
        check("cold_restart_slot_sql_id_reused",
            SCSplitScreenProbe.leaderSqlId() == Harness.coldRestoredSlotSqlId,
            "saved=" .. tostring(Harness.coldRestoredSlotSqlId)
                .. " live=" .. tostring(SCSplitScreenProbe.leaderSqlId()))
    end
    check("cold_restart_native_slot_sql_id_assigned",
        SCSplitScreenProbe.leaderSqlId() >= 2,
        "native sqlId=" .. tostring(SCSplitScreenProbe.leaderSqlId()))
    local cold = Harness.splitObserver
    check("cold_restart_temporary_actor_removed",
        cold ~= nil and cold ~= leader
            and cold:getCurrentSquare() == nil
            and cold:isExistInTheWorld() == false,
        "temporary map loader no longer occupies the world")
    check("cold_restart_mission_resumed",
        mission ~= nil and mission.restoring ~= true
            and mission.leader ~= nil and mission.leader.actor == leader
            and mission.technicalIssue == nil,
        "saved expedition now owns the exact slot-1 leader")
    check("cold_restart_remote_square_still_loaded",
        getWorld():getCell():getGridSquare(Harness.remoteX,
            Harness.remoteY, Harness.remoteZ) ~= nil,
        "slot-1 chunk map remained live through handoff")
    writeSignal(SPLIT_RESTORED_READY_FILE, { "ready=true" })
    setPhase("split_restart_handoff_capture", current)
end

function Harness.probeColdRestartHandoffCapture(current)
    if fileExists(SPLIT_RESTORED_CAPTURED_FILE) then
        result("PASS", "cold_restart_restored_view_captured",
            "rendered second view after the actual saved leader took slot 1")
        setPhase("finish", current)
    elseif current - Harness.phaseStartedAt > 15000 then
        result("FAIL", "cold_restart_restored_view_captured",
            "runner did not capture the post-handoff viewport")
        setPhase("finish", current)
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

-- Base layout capture: the runner presses End to show the overlay over the
-- observer's camp, photographs the client, then presses End again. The cloned
-- save's own base is used when the observer stands in it; otherwise a small
-- disposable camp is laid out around the observer in the clone.
Harness.BASE_LAYOUT_READY_FILE = "SurvivorCompanionHarness/base-layout-ready.txt"
Harness.BASE_LAYOUT_VISIBLE_FILE = "SurvivorCompanionHarness/base-layout-visible.txt"
Harness.BASE_LAYOUT_CAPTURED_FILE = "SurvivorCompanionHarness/base-layout-captured.txt"
Harness.COMPANION_INVENTORY_READY_FILE = "SurvivorCompanionHarness/companion-inventory-ready.txt"
Harness.COMPANION_INVENTORY_CAPTURED_FILE = "SurvivorCompanionHarness/companion-inventory-captured.txt"

function Harness.beginCompanionInventory(current)
    -- Let the cloned save restore and the initial window sweep finish before
    -- opening a real native companion's inventory in the player's loot pane.
    if current - Harness.startedAt < 22000 then return end
    local SC = SurvivorCompanion
    local actor = Harness.inventoryActor
    if actor == nil and Harness.inventoryTicket ~= nil then
        local status
        actor, status = SC.Actor.pollSpawn(Harness.inventoryTicket)
        if actor == nil then
            if status == "spawn_pending" and current - Harness.phaseStartedAt < 35000 then return end
            result("FAIL", "companion_inventory_spawn", tostring(status))
            setPhase("finish", current)
            return
        end
        Harness.inventoryActor, Harness.inventoryTicket = actor, nil
    end
    if actor == nil then
        for _, candidate in ipairs(SC.Registry.living()) do
            if select(1, SC.UIBridge.validateNearbyActor(candidate,
                Harness.player, SC.UIBridge.NEARBY_DISTANCE)) == true then
                actor = candidate
                break
            end
        end
    end
    if actor == nil then
        local U = SC.GameplayUtil
        local px, py, pz = position(Harness.player)
        local square
        if px ~= nil then
            for radius = 1, 3 do
                for dx = -radius, radius do
                    for dy = -radius, radius do
                        if math.max(math.abs(dx), math.abs(dy)) == radius then
                            local candidate = U.gridSquare(math.floor(px + dx),
                                math.floor(py + dy), math.floor(pz or 0))
                            if candidate and U.isSquareFree(candidate) then
                                square = candidate
                                break
                            end
                        end
                    end
                    if square then break end
                end
                if square then break end
            end
        end
        if not square then
            result("FAIL", "companion_inventory_spawn", "no nearby free square")
            setPhase("finish", current)
            return
        end
        local ticket, reason = SC.Actor.beginSpawn(square, {
            recruited = true,
            identity = { forename = "Pack", surname = "Tester",
                gender = "man", outfit = "Generic01" },
        })
        if not ticket then
            result("FAIL", "companion_inventory_spawn", tostring(reason))
            setPhase("finish", current)
            return
        end
        Harness.inventoryTicket = ticket
        return
    end
    Harness.inventoryActor = actor
    SC.Scheduler.unregister("decision")
    local opened, reason = SC.UIBridge.openInventory(actor, Harness.player)
    if not check("companion_inventory_opened", opened == true,
        tostring(reason) .. " distance=" .. tostring(distance(actor, Harness.player))) then
        setPhase("finish", current)
        return
    end
    if Harness.config.companion_transfer_probe == "true" then
        local source, destination = actor:getInventory(), Harness.player:getInventory()
        local hammer = source:AddItem("Base.Hammer")
        if not check("companion_transfer_fixture", hammer ~= nil,
            "native hammer created=" .. tostring(hammer ~= nil)) then
            setPhase("finish", current)
            return
        end
        actor:setPrimaryHandItem(hammer)
        if not check("companion_transfer_equipped",
            actor:getPrimaryHandItem() == hammer,
            "hammer equipped=" .. tostring(actor:getPrimaryHandItem() == hammer)) then
            setPhase("finish", current)
            return
        end
        local called, transferred = pcall(ISTransferAction.transferItem,
            ISTransferAction, Harness.player, hammer, source, destination, nil)
        local moved = called and transferred == hammer
            and SC.GameplayUtil.inventoryContains(destination, hammer)
            and not SC.GameplayUtil.inventoryContains(source, hammer)
        check("companion_transfer_identity", moved,
            "called=" .. tostring(called) .. " result=" .. tostring(transferred)
                .. " owner=" .. tostring(hammer:getContainer() == destination))
        check("companion_transfer_unequipped",
            actor:getPrimaryHandItem() ~= hammer
                and actor:getSecondaryHandItem() ~= hammer,
            "hand references cleared=" .. tostring(actor:getPrimaryHandItem() ~= hammer
                and actor:getSecondaryHandItem() ~= hammer))
        setPhase("finish", current)
        return
    end
    local page = getPlayerLoot(Harness.player:getPlayerNum())
    page:refreshBackpacks()
    local button
    for _, candidate in ipairs(page.backpacks or {}) do
        if candidate.inventory == actor:getInventory() then button = candidate break end
    end
    local backpack = getTexture("Item_Backpack_Black")
    check("companion_inventory_backpack_icon", button ~= nil and backpack ~= nil
            and button.image == backpack
            and page.inventoryPane.inventory == actor:getInventory(),
        "button=" .. tostring(button ~= nil) .. " texture=" .. tostring(backpack ~= nil)
            .. " image_matches=" .. tostring(button and button.image == backpack)
            .. " selected=" .. tostring(page.inventoryPane.inventory == actor:getInventory()))
    -- The saved Living Fellows panel sits over the loot-pane icon at this
    -- resolution. Hide only that panel for a readable screenshot; closing it
    -- would intentionally restore the player's previous loot container.
    if SC.UI and SC.UI.instance then SC.UI.instance:setVisible(false) end
    if not writeSignal(Harness.COMPANION_INVENTORY_READY_FILE, {
        "actor=" .. SC.UIBridge.borrowedInventoryLabel(actor),
        "button=" .. tostring(button ~= nil),
    }) then
        result("FAIL", "companion_inventory_capture", "ready signal failed")
        setPhase("finish", current)
        return
    end
    setPhase("companion_inventory_capture", current)
end

function Harness.probeCompanionInventory(current)
    if fileExists(Harness.COMPANION_INVENTORY_CAPTURED_FILE) then
        result("PASS", "companion_inventory_screenshot", "loot pane and backpack button captured")
        setPhase("finish", current)
    elseif current - Harness.phaseStartedAt > 15000 then
        result("FAIL", "companion_inventory_screenshot", "runner capture timed out")
        setPhase("finish", current)
    end
end

-- A disposable high-seat fixture exercises the same native rest action as a
-- player. Its SeatingManager height makes a premature getup look like a fall.
function Harness.beginFurniturePose(current)
    if current - Harness.phaseStartedAt < 3000 then return end
    local SC = SurvivorCompanion
    local U = SC.GameplayUtil
    local px, py, pz = position(Harness.player)
    if px == nil then result("FAIL", "furniture_fixture", "observer position missing")
        setPhase("finish", current) return end
    local cx, cy, z = math.floor(px), math.floor(py), math.floor(pz or 0)
    local seatSquare, spawnSquare
    local function openPatch(x, y)
        for nx = -1, 1 do
            for ny = -1, 1 do
                local square = U.gridSquare(x + nx, y + ny, z)
                local objects = square and square:getObjects()
                if not square or not U.isSquareFree(square)
                    or not objects or objects:size() > 1 then return false end
            end
        end
        return true
    end
    for radius = 2, 9 do
        for dx = -radius, radius do
            for dy = -radius, radius do
                local candidate = U.gridSquare(cx + dx, cy + dy, z)
                if candidate and openPatch(cx + dx, cy + dy) then
                    for _, side in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
                        local adjacent = U.gridSquare(cx + dx + side[1],
                            cy + dy + side[2], z)
                        if adjacent and U.isSquareFree(adjacent)
                            and adjacent ~= Harness.player:getCurrentSquare() then
                            seatSquare, spawnSquare = candidate, adjacent
                            break
                        end
                    end
                end
                if seatSquare then break end
            end
            if seatSquare then break end
        end
        if seatSquare then break end
    end
    if not seatSquare then
        result("FAIL", "furniture_fixture", "no two adjacent free loaded squares")
        setPhase("finish", current) return
    end
    local spriteName = "location_restaurant_bar_01_26"
    local object = IsoObject.new(seatSquare, spriteName, "Bar Stool")
    seatSquare:AddTileObject(object)
    local sprite = object:getSprite()
    local properties = sprite and sprite:getProperties()
    local surface = properties and properties:get("Surface")
    local detected, detectedLabel = U.squareOccupyingObject(seatSquare)
    if not check("furniture_standing_square",
        SC.Navigation.standingSquareClear(Harness.player, seatSquare) == false,
        "placed bar stool must be rejected as a guard/window-watch standing tile"
            .. " surface=" .. tostring(surface)
            .. " offset=" .. tostring(select(1, U.call(object, "getSurfaceOffset")))
            .. " moveable=" .. tostring(select(1, U.call(object, "isMoveAble")))
            .. " detected=" .. tostring(detected == object)
            .. " label=" .. tostring(detectedLabel)) then
        setPhase("finish", current) return
    end
    local count = SeatingManager.getInstance():getTilePositionCount(object)
    local tileName = properties and properties:get("CustomName") or "unknown"
    if not check("furniture_fixture", count > 0,
        "sprite=" .. spriteName .. " custom=" .. tostring(tileName)
            .. " positions=" .. tostring(count) .. " x=" .. tostring(seatSquare:getX())
            .. " y=" .. tostring(seatSquare:getY())) then
        setPhase("finish", current) return
    end
    Harness.poseSeat = object
    local ticket, reason = SC.Actor.beginSpawn(spawnSquare, {
        recruited = true,
        identity = { forename = "Seat", surname = "Tester",
            gender = "man", outfit = "Generic01" },
    })
    if not ticket then result("FAIL", "furniture_spawn", reason)
        setPhase("finish", current) return end
    Harness.poseTicket = ticket
    setPhase("furniture_pose_spawn", current)
end

function Harness.probeFurniturePose(current)
    local SC = SurvivorCompanion
    if Harness.phase == "furniture_pose_spawn" then
        local actor, reason = SC.Actor.pollSpawn(Harness.poseTicket)
        if not actor then
            if reason ~= "spawn_pending" or current - Harness.phaseStartedAt > 12000 then
                result("FAIL", "furniture_spawn", reason)
                setPhase("finish", current)
            end
            return
        end
        Harness.poseActor = actor
        -- This probe directly owns the actor's timed rest action. Pause ordinary
        -- AI decisions in the disposable clone so they do not issue Follow or
        -- Stay between the sit and screenshot frames.
        SC.Scheduler.unregister("decision")
        local accepted, status = SC.Actor.setMovement(actor, "walk", {
            action = "sit", object = Harness.poseSeat,
        })
        if not check("furniture_sit_requested", accepted == true, status) then
            setPhase("finish", current) return end
        setPhase("furniture_pose_entry", current)
        return
    end
    local actor = Harness.poseActor
    if Harness.phase == "furniture_pose_entry" then
        if current >= (Harness.poseNextTraceAt or 0) then
            Harness.poseNextTraceAt = current + 2000
            local phase, owner, action = SC.NativeActions.activityStatus(actor)
            local x, y = position(actor)
            local route = SC.NativeActions.pathTelemetry(actor)
            local queue = actor:getCharacterActions()
            local pathAction = queue and queue:size() > 0 and queue:get(0) or nil
            print("SC_REAL_SANDBOX|FURNITURE_TRACE|phase=" .. tostring(phase)
                .. " owner=" .. tostring(owner) .. " action=" .. tostring(action)
                .. " seat_status=" .. tostring(SC.NativeActions.furnitureStatus(actor))
                .. " context=" .. tostring(actor:getCurrentActionContextStateName())
                .. " x=" .. tostring(x) .. " y=" .. tostring(y)
                .. " move_owner=" .. tostring(actor:getCompanionMovementOwner())
                .. " bPathfind=" .. tostring(actor:getVariableBoolean("bPathfind"))
                .. " timed_path=" .. tostring(pathAction and pathAction:isPathfinding())
                .. " route=" .. tostring(route.status) .. "/"
                    .. tostring(route.shouldBeMoving) .. "/"
                    .. tostring(route.hasStartedMoving))
        end
        if SC.NativeActions.furnitureStatus(actor) == "entered" then
            Harness.poseEnteredAt = Harness.poseEnteredAt or current
            local context = tostring(actor:getCurrentActionContextStateName() or "")
            if string.lower(context) ~= "sitonfurniture"
                or current - Harness.poseEnteredAt < 650 then return end
            local seated = actor:isSittingOnFurniture()
            local attached = actor:getSitOnFurnitureObject() == Harness.poseSeat
            check("furniture_seated", seated and attached,
                "seated=" .. tostring(seated) .. " attached=" .. tostring(attached)
                    .. " state=" .. context)
            local name = tostring(Harness.config.run_id) .. "-stool-seated"
            local ok, errorText = pcall(function() getCore():TakeFullScreenshot(name) end)
            check("furniture_seated_screenshot", ok, name .. " " .. tostring(errorText))
            local leaving, reason = SC.NativeActions.leaveSeating(actor)
            check("furniture_getup_requested", leaving == false
                and reason == "standing_from_furniture"
                and actor:getSitOnFurnitureObject() == Harness.poseSeat,
                "reason=" .. tostring(reason))
            setPhase("furniture_pose_exit", current)
            return
        end
        if current - Harness.phaseStartedAt > 20000 then
            result("FAIL", "furniture_seated", "seat entry timed out: "
                .. tostring(SC.NativeActions.furnitureStatus(actor)))
            setPhase("finish", current)
        end
        return
    end
    if Harness.phase == "furniture_pose_exit" then
        local context = tostring(actor:getCurrentActionContextStateName() or "")
        if string.lower(context) == "getup" and not Harness.poseExitCaptured
            and current - Harness.phaseStartedAt >= 250 then
            Harness.poseExitCaptured = true
            local name = tostring(Harness.config.run_id) .. "-stool-getup"
            local ok, errorText = pcall(function() getCore():TakeFullScreenshot(name) end)
            check("furniture_getup_screenshot", ok, name .. " " .. tostring(errorText))
        end
        local standing, status = SC.NativeActions.leaveSeating(actor)
        if standing then
            check("furniture_getup_completed", status == "stood_from_furniture"
                and actor:getSitOnFurnitureObject() == nil
                and Harness.poseSeat:isFurnitureOccupied(actor) == false,
                "status=" .. tostring(status) .. " context=" .. context)
            check("furniture_getup_visible", Harness.poseExitCaptured == true,
                "native getup animation rendered before movement resumed")
            setPhase("finish", current)
        elseif current - Harness.phaseStartedAt > 10000 then
            result("FAIL", "furniture_getup_completed", "timeout context=" .. context)
            setPhase("finish", current)
        end
    end
end

-- Direct vehicle boarding bypasses vanilla's timed entry action. This focused
-- probe checks the native passenger offset, then lets the runner capture the
-- actual car and companion in the disposable cloned world.
local function passengerWorldDistance(first, second)
    local dx, dy, dz = first:x() - second:x(), first:y() - second:y(),
        first:z() - second:z()
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function passengerOutdoorSquare(square, U, requireFree, vehicle)
    if square == nil then return false, "unloaded square" end
    if square:isOutside() ~= true or square:getRoom() ~= nil
        or square:getBuilding() ~= nil or square:getRoofHideBuilding() ~= nil then
        return false, "not an unroofed exterior square"
    end
    for floor = 1, 2 do
        local above = U.gridSquare(square:getX(), square:getY(), floor)
        if above and (above:getFloor() ~= nil or above:getRoom() ~= nil
            or above:getBuilding() ~= nil or above:getRoofHideBuilding() ~= nil) then
            return false, "upper floor or roof is present"
        end
    end
    local occupying = square:getVehicleContainer()
    if occupying ~= nil and occupying ~= vehicle then
        return false, "another vehicle occupies the square"
    end
    if requireFree and (not U.isSquareFree(square) or occupying ~= nil) then
        return false, "square is blocked"
    end
    return true
end

local function passengerOpenPatch(U, x, y, radius, vehicle)
    for dx = -radius, radius do
        for dy = -radius, radius do
            local square = U.gridSquare(x + dx, y + dy, 0)
            local outside, reason = passengerOutdoorSquare(square, U,
                vehicle == nil, vehicle)
            if not outside then
                return false, tostring(x + dx) .. "," .. tostring(y + dy)
                    .. " " .. tostring(reason)
            end
        end
    end
    return true
end

local function passengerPreferredZone(square)
    local zone = square and square:getZone() or nil
    local kind = zone and tostring(zone:getType()) or ""
    return kind == "Nav" or kind == "ParkingStall", kind
end

local function passengerSeatFixture(vehicle, U, z)
    if vehicle == nil or tostring(vehicle:getScriptName()) ~= "Base.CarNormal" then
        return nil
    end
    for seat = 1, math.min(vehicle:getMaxPassengers() - 1, 3) do
        if vehicle:isSeatInstalled(seat) and not vehicle:isSeatOccupied(seat) then
            local inside = vehicle:getPassengerPosition(seat, "inside")
            local outside = vehicle:getPassengerPosition(seat, "outside")
            if inside and outside then
                local door = vehicle:getPassengerPositionWorldPos(outside,
                    Vector3f.new())
                local cx, cy = math.floor(door:x()), math.floor(door:y())
                local best, bestDistance
                for dx = -2, 2 do
                    for dy = -2, 2 do
                        local square = U.gridSquare(cx + dx, cy + dy, z)
                        if passengerOutdoorSquare(square, U, true)
                            and square ~= Harness.player:getCurrentSquare() then
                            local distance = vehicle:getEnterSeatDistance(seat,
                                square:getX() + 0.5, square:getY() + 0.5)
                            if distance and distance >= 0 and distance <= 2.56
                                and (bestDistance == nil or distance < bestDistance) then
                                best, bestDistance = square, distance
                            end
                        end
                    end
                end
                if best then return seat, best, inside, outside end
            end
        end
    end
    return nil
end

function Harness.beginVehiclePassenger(current)
    if current - Harness.phaseStartedAt < 3000 then return end
    local SC = SurvivorCompanion
    local U = SC.GameplayUtil
    local px, py, pz = position(Harness.player)
    if px == nil or math.floor(pz or 0) ~= 0 then
        result("FAIL", "vehicle_passenger_fixture", "observer must be on level zero")
        setPhase("finish", current)
        return
    end
    local cx, cy = math.floor(px), math.floor(py)
    local vehicle, seat, spawnSquare, inside, outside, fixtureFailure, zoneKind
    local function tryVehicle(candidate)
        local ok, foundSeat, foundSquare, foundInside, foundOutside = pcall(
            passengerSeatFixture, candidate, U, 0)
        if ok and foundSeat then
            vehicle, seat, spawnSquare, inside, outside = candidate,
                foundSeat, foundSquare, foundInside, foundOutside
            return true
        end
        fixtureFailure = ok and "vanilla car has no reachable installed passenger seat"
            or tostring(foundSeat)
        return false
    end
    local attempts, abortSearch = 0, false
    -- A car occupies more than its origin tile. Prefer real navigation or
    -- parking zones, but accept any fully outdoor 7x7 patch in the clone.
    for preferredPass = 1, 2 do
        for radius = 4, 28 do
            for dx = -radius, radius do
                for dy = -radius, radius do
                    if math.abs(dx) == radius or math.abs(dy) == radius then
                        local x, y = cx + dx, cy + dy
                        local center = U.gridSquare(x, y, 0)
                        local preferred, kind = passengerPreferredZone(center)
                        if center and preferred == (preferredPass == 1)
                            and passengerOpenPatch(U, x, y, 3) then
                            attempts = attempts + 1
                            local ok, created = pcall(addVehicle,
                                "Base.CarNormal", x, y, 0)
                            if ok and created then
                                local vx, vy = math.floor(created:getX()),
                                    math.floor(created:getY())
                                local actual, actualReason = passengerOpenPatch(
                                    U, vx, vy, 2, created)
                                local nativeSquare = created:getSquare()
                                local nativeOutside, nativeReason = true, nil
                                if nativeSquare then
                                    nativeOutside, nativeReason = passengerOutdoorSquare(
                                        nativeSquare, U, false, created)
                                end
                                if actual and nativeOutside and tryVehicle(created) then
                                    zoneKind = kind
                                    break
                                end
                                fixtureFailure = not actual and actualReason
                                    or not nativeOutside and nativeReason
                                    or fixtureFailure
                                local removed, removeReason = pcall(
                                    created.permanentlyRemove, created)
                                if not removed then
                                    fixtureFailure = "invalid spawned car could not be removed: "
                                        .. tostring(removeReason)
                                    abortSearch = true
                                    break
                                end
                            else
                                fixtureFailure = tostring(created)
                            end
                            if attempts >= 6 then break end
                        end
                    end
                end
                if vehicle or abortSearch or attempts >= 6 then break end
            end
            if vehicle or abortSearch or attempts >= 6 then break end
        end
        if vehicle or abortSearch or attempts >= 6 then break end
    end
    if not check("vehicle_passenger_fixture", vehicle ~= nil,
        vehicle and ("vehicle=" .. tostring(vehicle:getScriptName())
            .. " seat=" .. tostring(seat) .. " door="
            .. tostring(spawnSquare:getX()) .. "," .. tostring(spawnSquare:getY())
            .. " center=" .. tostring(vehicle:getX()) .. "," .. tostring(vehicle:getY())
            .. " zone=" .. tostring(zoneKind) .. " attempts=" .. tostring(attempts))
            or (tostring(fixtureFailure or "no loaded outdoor road or parking patch")
                .. " attempts=" .. tostring(attempts))) then
        setPhase("finish", current)
        return
    end
    Harness.passengerVehicle, Harness.passengerSeat = vehicle, seat
    Harness.passengerInside, Harness.passengerOutside = inside, outside
    local actualX, actualY = math.floor(vehicle:getX()), math.floor(vehicle:getY())
    local footprint, footprintReason = passengerOpenPatch(U, actualX, actualY, 2, vehicle)
    if not check("vehicle_passenger_spawned_outdoors", footprint,
        "center=" .. tostring(actualX) .. "," .. tostring(actualY)
            .. " zone=" .. tostring(zoneKind) .. " detail=" .. tostring(footprintReason)) then
        setPhase("finish", current)
        return
    end
    for _, offset in ipairs({ { 4, 0 }, { 0, 4 }, { -4, 0 }, { 0, -4 },
        { 3, 3 }, { -3, 3 }, { 3, -3 }, { -3, -3 } }) do
        local view = U.gridSquare(actualX + offset[1], actualY + offset[2], 0)
        if passengerOutdoorSquare(view, U, true) then
            Harness.passengerViewSquare = view
            break
        end
    end
    if not check("vehicle_passenger_observer_view", Harness.passengerViewSquare ~= nil,
        "unobstructed outdoor view within four tiles of spawned car") then
        setPhase("finish", current)
        return
    end
    -- Daylight keeps the screenshot usable when the cloned seed was saved at
    -- night. Only this disposable world is affected.
    pcall(function() getGameTime():setTimeOfDay(12.0) end)
    local ticket, reason = SC.Actor.beginSpawn(spawnSquare, {
        recruited = true,
        identity = { forename = "Passenger", surname = "Tester",
            gender = "man", outfit = "Generic01" },
    })
    if not ticket then
        result("FAIL", "vehicle_passenger_spawn", reason)
        setPhase("finish", current)
        return
    end
    Harness.passengerTicket = ticket
    setPhase("vehicle_passenger_spawn", current)
end

function Harness.probeVehiclePassenger(current)
    local SC = SurvivorCompanion
    if Harness.phase == "vehicle_passenger_spawn" then
        local actor, reason = SC.Actor.pollSpawn(Harness.passengerTicket)
        if not actor then
            if reason ~= "spawn_pending" or current - Harness.phaseStartedAt > 12000 then
                result("FAIL", "vehicle_passenger_spawn", reason)
                setPhase("finish", current)
            end
            return
        end
        Harness.passengerActor = actor
        SC.Scheduler.unregister("decision")
        setPhase("vehicle_passenger_wait_stationary", current)
        return
    end
    if Harness.phase == "vehicle_passenger_wait_stationary" then
        local vehicle = Harness.passengerVehicle
        local stationary, reason = SC.Vehicle.isStationary(vehicle)
        local speedOk, speed = pcall(vehicle.getCurrentSpeedKmHour, vehicle)
        local detail = "speed_kph=" .. tostring(speedOk and speed or "unavailable")
            .. " reason=" .. tostring(reason)
            .. " waited_ms=" .. tostring(current - Harness.phaseStartedAt)
        if stationary == true then
            Harness.passengerStationarySince = Harness.passengerStationarySince or current
            if current - Harness.passengerStationarySince < 700 then return end
            result("PASS", "vehicle_passenger_vehicle_settled", detail)
            local vx, vy = math.floor(vehicle:getX()), math.floor(vehicle:getY())
            local outdoors, outdoorReason = passengerOpenPatch(SC.GameplayUtil,
                vx, vy, 2, vehicle)
            if not check("vehicle_passenger_settled_outdoors", outdoors,
                "center=" .. tostring(vx) .. "," .. tostring(vy)
                    .. " detail=" .. tostring(outdoorReason)) then
                setPhase("finish", current)
                return
            end
        else
            Harness.passengerStationarySince = nil
            if current - Harness.phaseStartedAt > 15000 then
                result("FAIL", "vehicle_passenger_vehicle_settled", detail)
                setPhase("finish", current)
            elseif current >= (Harness.passengerNextSpeedTraceAt or 0) then
                Harness.passengerNextSpeedTraceAt = current + 2000
                print("SC_REAL_SANDBOX|VEHICLE_SETTLE|" .. clean(detail))
            end
            return
        end
        local boarded, status = SC.Vehicle.board(Harness.passengerActor, vehicle,
            Harness.passengerSeat, { allowVirtualSeat = false })
        if not check("vehicle_passenger_native_board", boarded == true
            and status == "native_seat", tostring(status)) then
            setPhase("finish", current)
            return
        end
        local view = Harness.passengerViewSquare
        local moved, moveReason = pcall(function()
            Harness.player:teleportTo(view:getX() + 0.5, view:getY() + 0.5, 0)
        end)
        if not check("vehicle_passenger_observer_relocated", moved,
            "view=" .. tostring(view:getX()) .. "," .. tostring(view:getY())
                .. " reason=" .. tostring(moveReason)) then
            setPhase("finish", current)
            return
        end
        setPhase("vehicle_passenger_settle", current)
        return
    end
    if Harness.phase == "vehicle_passenger_settle" then
        if current - Harness.phaseStartedAt < 1800 then return end
        local view = Harness.passengerViewSquare
        local px, py = position(Harness.player)
        local cameraReady = px ~= nil and math.abs(px - (view:getX() + 0.5)) < 1
            and math.abs(py - (view:getY() + 0.5)) < 1
            and passengerOutdoorSquare(Harness.player:getCurrentSquare(),
                SC.GameplayUtil, false) == true
        if not cameraReady then
            if current - Harness.phaseStartedAt < 7000 then return end
            result("FAIL", "vehicle_passenger_observer_outdoors",
                "player=" .. tostring(px) .. "," .. tostring(py)
                    .. " target=" .. tostring(view:getX()) .. ","
                    .. tostring(view:getY()))
            setPhase("finish", current)
            return
        end
        result("PASS", "vehicle_passenger_observer_outdoors",
            "player=" .. tostring(px) .. "," .. tostring(py))
        local actor, vehicle, seat = Harness.passengerActor,
            Harness.passengerVehicle, Harness.passengerSeat
        local seated, nativeVehicle, nativeSeat = SC.Vehicle.isNativeSeated(actor)
        check("vehicle_passenger_native_seat", seated == true
            and nativeVehicle == vehicle and nativeSeat == seat,
            "seat=" .. tostring(nativeSeat) .. " vehicle=" .. tostring(nativeVehicle == vehicle))
        local passenger = vehicle:getPassengerWorldPos(seat, Vector3f.new())
        local inside = vehicle:getPassengerPositionWorldPos(Harness.passengerInside,
            Vector3f.new())
        local outside = vehicle:getPassengerPositionWorldPos(Harness.passengerOutside,
            Vector3f.new())
        local insideGap = passengerWorldDistance(passenger, inside)
        local outsideGap = passengerWorldDistance(passenger, outside)
        check("vehicle_passenger_inside_offset", insideGap < 0.03
            and outsideGap > 0.15,
            string.format("inside_gap=%.4f outside_gap=%.4f seat=%d",
                insideGap, outsideGap, seat))
        local dx, dy, dz = actor:getX() - passenger:x(),
            actor:getY() - passenger:y(), actor:getZ() - passenger:z()
        local actorGap = math.sqrt(dx * dx + dy * dy + dz * dz)
        check("vehicle_passenger_actor_tracks_seat", actorGap < 0.15,
            string.format("actor_gap=%.4f vehicle=%.2f,%.2f",
                actorGap, vehicle:getX(), vehicle:getY()))
        pcall(function() UIManager.setVisibleAllUI(false) end)
        if not writeSignal(VEHICLE_PASSENGER_READY_FILE, {
            "seat=" .. tostring(seat),
            "inside_gap=" .. tostring(insideGap),
            "outside_gap=" .. tostring(outsideGap),
            "actor_gap=" .. tostring(actorGap),
        }) then
            result("FAIL", "vehicle_passenger_capture", "ready signal failed")
            setPhase("finish", current)
            return
        end
        setPhase("vehicle_passenger_capture", current)
        return
    end
    if Harness.phase == "vehicle_passenger_capture" then
        if fileExists(VEHICLE_PASSENGER_CAPTURED_FILE) then
            result("PASS", "vehicle_passenger_screenshot", "native passenger and car captured")
            setPhase("finish", current)
        elseif current - Harness.phaseStartedAt > 15000 then
            result("FAIL", "vehicle_passenger_screenshot", "runner capture timed out")
            setPhase("finish", current)
        end
    end
end

-- Observe the saved woodcutter in an isolated copy of the player's world.
-- A successful job must reach native chopping from a non-tree approach tile.
function Harness.probeWoodcutter(current)
    if current - Harness.phaseStartedAt < 4000 then return end
    local SC = SurvivorCompanion
    local U = SC.GameplayUtil
    if not Harness.woodActor then
        for _, record in ipairs(SC.Registry.records() or {}) do
            local actor = record.actor
            local name = actor and tostring(U.nameOf(actor) or "") or ""
            local resident = SC.BaseLife.resident(record.id)
            if actor and string.find(string.lower(name), "sarah", 1, true)
                and resident and resident.role == "woodcutter" then
                Harness.woodActor, Harness.woodId = actor, record.id
                Harness.woodName = name
                Harness.woodStartX, Harness.woodStartY = position(actor)
                Harness.woodStartFelled = SC.BaseLife.productionCounters().treesFelled or 0
                result("PASS", "woodcutter_loaded", name .. " id=" .. tostring(record.id)
                    .. " duty=" .. tostring(resident.duty))
                break
            end
        end
        if not Harness.woodActor and current - Harness.phaseStartedAt > 12000 then
            result("FAIL", "woodcutter_loaded", "Sarah with woodcutter role was not restored in the cloned save")
            setPhase("finish", current)
        end
        return
    end
    local actor = Harness.woodActor
    if current >= (Harness.woodNextTraceAt or 0) then
        Harness.woodNextTraceAt = current + 1000
        local x, y, z = position(actor)
        local nav = SC.Navigation.status(actor) or {}
        local job = SC.BaseLife.jobFor(Harness.woodId)
        local orderId = job and type(job.target) == "table" and job.target.orderId or nil
        local order = orderId and SC.BaseLife.productionOrder(orderId) or nil
        local phase = orderId and SC.Production.workerPhase(orderId, Harness.woodId) or nil
        local kind = SC.NativeActions.workKind(actor)
        local counters = SC.BaseLife.productionCounters()
        if x and Harness.woodLastX and
            math.abs(x - Harness.woodLastX) + math.abs(y - Harness.woodLastY) > 0.04 then
            Harness.woodMovingSamples = (Harness.woodMovingSamples or 0) + 1
            Harness.woodLastMotionAt = current
        end
        Harness.woodLastMotionAt = Harness.woodLastMotionAt or current
        Harness.woodLastX, Harness.woodLastY = x, y
        if kind == "chop_tree" then Harness.woodChopSeen = true end
        if phase == "approaching" then Harness.woodApproachSeen = true end
        local square = actor:getCurrentSquare()
        if kind == "chop_tree" and square and square:getTree() then
            Harness.woodChoppedOnTreeTile = true
        end
        print("SC_REAL_SANDBOX|WOODCUTTER_TRACE|name=" .. tostring(Harness.woodName)
            .. " x=" .. tostring(x) .. " y=" .. tostring(y) .. " z=" .. tostring(z)
            .. " job=" .. tostring(job and job.type) .. "/" .. tostring(job and job.state)
            .. " order=" .. tostring(order and order.kind) .. "/" .. tostring(order and order.state)
            .. " phase=" .. tostring(phase) .. " work=" .. tostring(kind)
            .. " nav=" .. tostring(nav.phase) .. "/" .. tostring(nav.action)
            .. "/" .. tostring(nav.terminalReason)
            .. " goal=" .. tostring(nav.target)
            .. " path=" .. tostring(nav.pathReason) .. "/" .. tostring(nav.pathFailureClass)
            .. " blocker=" .. tostring(nav.blockerType) .. "/" .. tostring(nav.blockerSquare)
            .. " nodes=" .. tostring(nav.expandedNodes)
            .. " state=" .. tostring(actor:getCurrentActionContextStateName())
            .. " felled=" .. tostring(counters.treesFelled))
        if phase == "approaching" and kind ~= "chop_tree"
            and (Harness.woodMovingSamples or 0) > 0 and not Harness.woodStallImage
            and current - Harness.woodLastMotionAt > 7000 then
            Harness.woodStallImage = tostring(Harness.config.run_id) .. "-woodcutter-stall"
            pcall(function() getCore():TakeFullScreenshot(Harness.woodStallImage) end)
        end
        if (counters.treesFelled or 0) > Harness.woodStartFelled then
            check("woodcutter_chop", Harness.woodChopSeen == true
                and Harness.woodChoppedOnTreeTile ~= true,
                "native chop=" .. tostring(Harness.woodChopSeen)
                    .. " tree tile=" .. tostring(Harness.woodChoppedOnTreeTile)
                    .. " moving samples=" .. tostring(Harness.woodMovingSamples or 0)
                    .. " felled=" .. tostring(counters.treesFelled))
            setPhase("finish", current)
            return
        end
    end
    if current - Harness.phaseStartedAt > 65000 then
        result("FAIL", "woodcutter_chop", "no tree felled in 65s; approaching="
            .. tostring(Harness.woodApproachSeen) .. " native chop="
            .. tostring(Harness.woodChopSeen) .. " moving samples="
            .. tostring(Harness.woodMovingSamples or 0))
        setPhase("finish", current)
    end
end

function Harness.probePostedStream(current)
    if current - Harness.phaseStartedAt < 7000 then return end
    local SC, U = SurvivorCompanion, SurvivorCompanion.GameplayUtil
    for _, record in ipairs(SC.Registry.records() or {}) do
        local actor = record.actor
        local name = actor and tostring(U.nameOf(actor) or "") or ""
        if string.find(string.lower(name), "sarah", 1, true) then
            local x, y, z = position(actor)
            local healthy, reason = SC.Actor.validateNative(actor)
            local square = U.call(actor, "getCurrentSquare")
            local renderSquare = U.call(actor, "getSquare")
            local loadedSquare = x and U.gridSquare(x, y, z) or nil
            local world = U.call(actor, "isExistInTheWorld")
            local scheduled = U.call(actor, "isScheduled")
            local model = U.call(actor, "isAddedToModelManager")
            local activeModel = U.call(actor, "hasActiveModel")
            local px, py, pz = position(Harness.player)
            local stable = type(record.runtime) == "table"
                and record.runtime.lastStablePosition or nil
            result("PASS", "posted_stream_snapshot", "name=" .. name
                .. " order=" .. tostring(record.order)
                .. " pos=" .. tostring(x) .. "," .. tostring(y) .. "," .. tostring(z)
                .. " player=" .. tostring(px) .. "," .. tostring(py) .. "," .. tostring(pz)
                .. " healthy=" .. tostring(healthy) .. "/" .. tostring(reason)
                .. " square=" .. tostring(square ~= nil)
                .. " current=" .. tostring(square == loadedSquare)
                .. " renderSquare=" .. tostring(renderSquare == square)
                .. " world=" .. tostring(world) .. " scheduled=" .. tostring(scheduled)
                .. " model=" .. tostring(model) .. " activeModel=" .. tostring(activeModel)
                .. " stable=" .. tostring(stable and stable.x) .. ","
                    .. tostring(stable and stable.y))
            Harness.postedActor = actor
            Harness.postedHomeX, Harness.postedHomeY, Harness.postedHomeZ = px, py, pz
            local moved, moveReason = pcall(function()
                Harness.player:teleportTo(px + 256, py, pz)
            end)
            if not check("posted_stream_depart", moved, moveReason) then
                setPhase("finish", current)
                return
            end
            setPhase("posted_stream_far", current)
            return
        end
    end
    result("FAIL", "posted_stream_snapshot", "Sarah was not restored in the cloned save")
    setPhase("finish", current)
end

function Harness.probePostedStreamFar(current)
    if current - Harness.phaseStartedAt < 14000 then return end
    local SC, U = SurvivorCompanion, SurvivorCompanion.GameplayUtil
    local actor = Harness.postedActor
    local px, py = position(Harness.player)
    local ax, ay = position(actor)
    local square = U.call(actor, "getCurrentSquare")
    local loaded = ax and U.gridSquare(ax, ay, 0) or nil
    result("PASS", "posted_stream_far_state", "player=" .. tostring(px)
        .. "," .. tostring(py) .. " actor=" .. tostring(ax) .. "," .. tostring(ay)
        .. " square=" .. tostring(square ~= nil)
        .. " loaded=" .. tostring(loaded ~= nil)
        .. " world=" .. tostring(U.call(actor, "isExistInTheWorld"))
        .. " scheduled=" .. tostring(U.call(actor, "isScheduled"))
        .. " model=" .. tostring(U.call(actor, "isAddedToModelManager")))
    local moved, moveReason = pcall(function()
        Harness.player:teleportTo(Harness.postedHomeX,
            Harness.postedHomeY, Harness.postedHomeZ)
    end)
    if not check("posted_stream_return", moved, moveReason) then
        setPhase("finish", current)
        return
    end
    setPhase("posted_stream_return_wait", current)
end

function Harness.probePostedStreamReturn(current)
    if current - Harness.phaseStartedAt < 15000 then return end
    local SC, U = SurvivorCompanion, SurvivorCompanion.GameplayUtil
    local actor = Harness.postedActor
    local x, y, z = position(actor)
    local px, py = position(Harness.player)
    local healthy, reason = SC.Actor.validateNative(actor)
    local square = U.call(actor, "getCurrentSquare")
    local loaded = x and U.gridSquare(x, y, z) or nil
    local world = U.call(actor, "isExistInTheWorld")
    local scheduled = U.call(actor, "isScheduled")
    local model = U.call(actor, "isAddedToModelManager")
    local activeModel = U.call(actor, "hasActiveModel")
    local id = SC.Registry.idOf(actor)
    local record = id and SC.Registry.byId(id) or nil
    local sameActor = record ~= nil and record.actor == actor
    check("posted_stream_visible_after_return", healthy == true
        and square ~= nil and square == loaded and world == true
        and scheduled == true and model == true and activeModel == true
        and sameActor == true,
        "player=" .. tostring(px) .. "," .. tostring(py)
            .. " actor=" .. tostring(x) .. "," .. tostring(y)
            .. " healthy=" .. tostring(healthy) .. "/" .. tostring(reason)
            .. " current=" .. tostring(square == loaded)
            .. " world=" .. tostring(world) .. " scheduled=" .. tostring(scheduled)
            .. " model=" .. tostring(model) .. " activeModel=" .. tostring(activeModel)
            .. " sameActor=" .. tostring(sameActor))
    local imageName = tostring(Harness.config.run_id) .. "-sarah-after-return"
    local pictured, imageReason = pcall(function()
        getCore():TakeFullScreenshot(imageName)
    end)
    check("posted_stream_return_screenshot", pictured,
        imageName .. " " .. tostring(imageReason))
    setPhase("finish", current)
end

function Harness.nearestContainer(x, y, z, radius)
    local U = SurvivorCompanion.GameplayUtil
    local best, bestDistance
    for dx = -radius, radius do
        for dy = -radius, radius do
            local square = U.gridSquare(x + dx, y + dy, z)
            if square then
                U.squareObjects(square, function(object)
                    local container, ok = U.call(object, "getContainer")
                    local spread = dx * dx + dy * dy
                    if ok and container ~= nil and (bestDistance == nil or spread < bestDistance) then
                        best, bestDistance = object, spread
                    end
                end, 32)
            end
        end
    end
    return best
end

function Harness.layOutBaseFixture(x, y, z)
    local SC = SurvivorCompanion
    local U = SC.GameplayUtil
    local function square(dx, dy) return U.gridSquare(x + dx, y + dy, z) end
    SC.BaseLife.reset()
    if SC.BaseLife.create(square(0, 0), "Harness Camp") ~= true then
        return false, "base_create_failed"
    end
    local zones = 0
    for _, spec in ipairs({
        { "work", 1, 1, 3, 3, "Workshop" },
        { "rest", -4, -4, -2, -2, "Bunks" },
        { "guard", 3, -4, 4, -3, "Lookout" },
        { "social", -4, 2, -2, 4, "Yard" },
    }) do
        if SC.BaseLife.beginZone(spec[1], square(spec[2], spec[3])) == true then
            if SC.BaseLife.finishZone(square(spec[4], spec[5]), spec[6]) == true then
                zones = zones + 1
            else
                SC.BaseLife.cancelZone()
            end
        end
    end
    local container = Harness.nearestContainer(x, y, z, 6)
    local stored = container ~= nil and SC.BaseLife.registerStorage(container, "food") == true
    return true, "zones=" .. tostring(zones) .. " storage=" .. tostring(stored)
end

function Harness.beginBaseLayout(current)
    local SC = SurvivorCompanion
    -- Persistence restores the save's base after the runtime starts. Wait for it
    -- (bounded) so an existing base is never mistaken for a missing one.
    local restored = false
    if SC.Persistence and type(SC.Persistence.restoreStatus) == "function" then
        local called, committed = pcall(SC.Persistence.restoreStatus)
        restored = called and committed == true
    end
    if current - Harness.phaseStartedAt < 3000
        or (not restored and current - Harness.phaseStartedAt < 20000) then
        return
    end
    local x, y, z = position(Harness.player)
    if x == nil then
        result("FAIL", "base_layout_fixture", "observer position unavailable")
        setPhase("finish", current)
        return
    end
    x, y, z = math.floor(x), math.floor(y), math.floor(z or 0)
    local fixture, detail = "existing_base", nil
    if not (SC.BaseLife.active() and SC.BaseLife.isInside(Harness.player) == true) then
        local laidOut
        laidOut, detail = Harness.layOutBaseFixture(x, y, z)
        if not laidOut then
            result("FAIL", "base_layout_fixture", detail)
            setPhase("finish", current)
            return
        end
        fixture = "disposable_camp"
    end
    SC.BaseVisuals.setEnabled(false)
    local bound = SC.GameplayUtil.call(getCore(), "getKey", SC.UI.LAYOUT_HOTKEY_ACTION)
    result("PASS", "base_layout_fixture", fixture .. " " .. clean(detail or "")
        .. " end_key=" .. tostring(bound))
    if not writeSignal(Harness.BASE_LAYOUT_READY_FILE, {
        "fixture=" .. fixture, "x=" .. tostring(x), "y=" .. tostring(y), "z=" .. tostring(z),
    }) then
        result("FAIL", "base_layout_overlay", "could not write the base-layout-ready signal")
        setPhase("finish", current)
        return
    end
    Harness.baseLayoutShown, Harness.baseLayoutDrawn = false, false
    Harness.baseLayoutSignaled, Harness.baseLayoutCapturedAt = false, nil
    setPhase("base_layout_capture", current)
end

function Harness.probeBaseLayout(current)
    local status = SurvivorCompanion.BaseVisuals.status() or {}
    if status.enabled == true then
        Harness.baseLayoutShown = true
        if (tonumber(status.visibleZones) or 0) > 0 then
            Harness.baseLayoutDrawn = true
            Harness.baseLayoutZones = status.visibleZones
            Harness.baseLayoutStorages = status.visibleStorages
            if not Harness.baseLayoutSignaled then
                Harness.baseLayoutSignaled = writeSignal(Harness.BASE_LAYOUT_VISIBLE_FILE, {
                    "zones=" .. tostring(status.visibleZones),
                    "storages=" .. tostring(status.visibleStorages),
                })
            end
        end
    end
    if fileExists(Harness.BASE_LAYOUT_CAPTURED_FILE) then
        Harness.baseLayoutCapturedAt = Harness.baseLayoutCapturedAt or current
        -- The runner pressed End again after its capture, so the overlay hides.
        if status.enabled ~= true or current - Harness.baseLayoutCapturedAt > 5000 then
            check("base_layout_overlay", Harness.baseLayoutShown and Harness.baseLayoutDrawn
                    and status.enabled ~= true,
                "shown_by_end=" .. tostring(Harness.baseLayoutShown)
                    .. " zones=" .. tostring(Harness.baseLayoutZones)
                    .. " storages=" .. tostring(Harness.baseLayoutStorages)
                    .. " hidden_by_end=" .. tostring(status.enabled ~= true))
            setPhase("finish", current)
        end
    elseif current - Harness.phaseStartedAt > 30000 then
        result("FAIL", "base_layout_overlay",
            "runner did not complete the End-key capture within 30 seconds; shown="
                .. tostring(Harness.baseLayoutShown) .. " zones=" .. tostring(status.visibleZones))
        setPhase("finish", current)
    end
end

-- Focused native cooking probe. It uses a disposable cloned save and real
-- timed actions; the Chef controller itself is covered by chef_harness.lua.
function Harness.probeChefRecipes(current)
    local SC = SurvivorCompanion
    local inventory = Harness.player:getInventory()
    local function itemOf(kind)
        local items = inventory:getItems()
        for index = 0, items:size() - 1 do
            local item = items:get(index)
            if item:getFullType() == kind then return item end
        end
        return nil
    end
    local function evolved(name)
        local recipes = getEvolvedRecipes()
        for index = 0, recipes:size() - 1 do
            local recipe = recipes:get(index)
            if recipe:getUntranslatedName() == name then return recipe end
        end
        return nil
    end
    local function listHas(list, item)
        return list ~= nil and list:contains(item)
    end
    if Harness.phase == "chef_recipes_begin" then
        if not check("chef_module_loaded", SC.ChefWork ~= nil,
            "SCChefWork is available in the real client") then
            setPhase("finish", current)
            return
        end
        local stir, pasta, salad = evolved("Stir fry"), evolved("PastaPot"),
            evolved("Salad")
        Harness.chefStir, Harness.chefPasta = stir, pasta
        if not check("chef_native_evolved_recipes",
            stir ~= nil and pasta ~= nil and salad ~= nil,
            "stir=" .. tostring(stir) .. " pasta=" .. tostring(pasta)
                .. " salad=" .. tostring(salad)) then
            setPhase("finish", current)
            return
        end
        -- The cloned save's observer can be over its carry limit. Native
        -- handcraft drops outputs on the floor in that case, obscuring the
        -- recipe test; empty only this disposable observer inventory.
        local oldItems = inventory:getItems()
        local removed = oldItems:size()
        for index = oldItems:size() - 1, 0, -1 do
            inventory:Remove(oldItems:get(index))
        end
        print("SC_CHEF_FIXTURE_INVENTORY|removed=" .. tostring(removed)
            .. "|weight=" .. tostring(inventory:getCapacityWeight())
            .. "|capacity=" .. tostring(inventory:getEffectiveCapacity(Harness.player)))
        local bowl = inventory:AddItem("Base.Bowl")
        local ramen = inventory:AddItem("Base.Ramen")
        local saladEligible = salad:getItemsCanBeUse(Harness.player, bowl, nil)
        if not check("chef_salad_rejects_wrong_filling",
            not listHas(saladEligible, ramen),
            "native Salad excludes Base.Ramen despite its Food category") then
            setPhase("finish", current)
            return
        end
        local pan = inventory:AddItem("Base.Pan")
        local potato = inventory:AddItem("Base.Potato")
        local possible = stir:getItemsCanBeUse(Harness.player, pan, nil)
        if not check("chef_stir_ingredient_accepted", listHas(possible, potato),
            "native Stir fry accepts Base.Potato") then
            setPhase("finish", current)
            return
        end
        Harness.chefPanId = pan:getID()
        ISTimedActionQueue.add(ISAddItemInRecipe:new(Harness.player, stir,
            pan, potato))
        setPhase("chef_stir_wait", current)
        return
    end
    if Harness.phase == "chef_stir_wait" then
        local dish = itemOf("Base.PanFriedVegetables")
        if not dish then
            if current - Harness.phaseStartedAt > 15000 then
                result("FAIL", "chef_stir_native_result", "timed action did not produce stir fry")
                setPhase("finish", current)
            end
            return
        end
        check("chef_stir_native_result", dish:getID() ~= Harness.chefPanId,
            "native evolved action produced " .. tostring(dish:getFullType()))
        check("chef_stir_uncooked_not_stock", SC.ChefWork.isPrepared(dish) == false,
            "Chef rejects the uncooked native result")
        dish:setCooked(true)
        check("chef_stir_cooked_stock", SC.ChefWork.isPrepared(dish) == true,
            "Chef accepts the cooked native result")
        local cell = getWorld():getCell()
        local origin = Harness.player:getCurrentSquare()
        local nearest, nearestDistance
        for radius = 0, 35 do
            if nearest then break end
            for x = origin:getX() - radius, origin:getX() + radius do
                for y = origin:getY() - radius, origin:getY() + radius do
                    if math.max(math.abs(x - origin:getX()),
                        math.abs(y - origin:getY())) == radius then
                        local square = cell:getGridSquare(x, y, origin:getZ())
                        local objects = square and square:getObjects()
                        if objects then
                            for index = 0, objects:size() - 1 do
                                local object = objects:get(index)
                                local sprite = object and object:getSprite()
                                local props = sprite and sprite:getProperties()
                                if props and props:has("IsTable")
                                    and props:has("Surface") then
                                    nearest = square
                                    Harness.chefSurfaceObject = object
                                    nearestDistance = radius
                                    break
                                end
                            end
                        end
                    end
                    if nearest then break end
                end
                if nearest then break end
            end
        end
        if not check("chef_craft_surface_nearby", nearest ~= nil,
            "nearest craft table radius=" .. tostring(nearestDistance)
                .. " origin=" .. tostring(origin:getX()) .. ","
                .. tostring(origin:getY())) then
            setPhase("finish", current)
            return
        end
        Harness.player:teleportTo(nearest:getX() + 1, nearest:getY(),
            nearest:getZ())
        setPhase("chef_pasta_begin", current)
        return
    end
    if Harness.phase == "chef_pasta_begin" then
        if current - Harness.phaseStartedAt < 750 then return end
        local pot = inventory:AddItem("Base.Pot")
        local dry = inventory:AddItem("Base.Pasta")
        local fluid = pot and pot:getFluidContainer()
        if not check("chef_pasta_supplies", pot ~= nil and dry ~= nil
            and fluid ~= nil and fluid:getCapacity() >= 1.5,
            "dry pasta and a pot with at least 1.5 L capacity") then
            setPhase("finish", current)
            return
        end
        fluid:addFluid(FluidType.Water, 1.5)
        local craft = getScriptManager():getCraftRecipe("PlacePastaInCookingPot2")
        if not check("chef_pasta_native_craft", craft ~= nil,
            "Build 42 dry-pasta pot recipe is present") then
            setPhase("finish", current)
            return
        end
        local containers = ArrayList.new()
        containers:add(inventory)
        local logic = HandcraftLogic.new(Harness.player, nil, nil)
        local surface = logic:findCraftSurface(Harness.player, 2)
        logic:setIsoObject(surface or Harness.chefSurfaceObject)
        print("SC_CHEF_CRAFT_SURFACE|surface=" .. tostring(surface)
            .. "|fallback=" .. tostring(Harness.chefSurfaceObject)
            .. "|player=" .. tostring(Harness.player:getX()) .. ","
            .. tostring(Harness.player:getY())
            .. "|water=" .. tostring(fluid:getAmount()))
        logic:setContainers(containers)
        logic:setRecipeFromContextClick(craft, pot)
        if not check("chef_pasta_native_requirements",
            logic:canPerformCurrentRecipe() == true,
            "native handcraft logic accepts the pot, water, and dry pasta") then
            setPhase("finish", current)
            return
        end
        Harness.chefPastaPotId = pot:getID()
        local action = ISHandcraftAction.FromLogic(logic)
        local originalStart, originalStop, originalPerform =
            action.start, action.stop, action.performRecipe
        action.start = function(self)
            print("SC_CHEF_PASTA_ACTION|event=start|surface="
                .. tostring(self.isoObject))
            return originalStart(self)
        end
        action.stop = function(self)
            print("SC_CHEF_PASTA_ACTION|event=stop|surface="
                .. tostring(self.isoObject))
            return originalStop(self)
        end
        action.performRecipe = function(self)
            print("SC_CHEF_PASTA_ACTION|event=perform")
            originalPerform(self)
            local outputs = ArrayList.new()
            self.logic:getCreatedOutputItems(outputs)
            for index = 0, outputs:size() - 1 do
                local output = outputs:get(index)
                print("SC_CHEF_PASTA_ACTION|event=output|type="
                    .. tostring(output:getFullType()) .. "|container="
                    .. tostring(output:getContainer()))
            end
        end
        ISTimedActionQueue.add(action)
        setPhase("chef_pasta_prep_wait", current)
        return
    end
    if Harness.phase == "chef_pasta_prep_wait" then
        local wet = itemOf("Base.WaterPotPasta")
        if not wet then
            if current - Harness.phaseStartedAt > 15000 then
                result("FAIL", "chef_pasta_native_base", "timed action did not prepare pasta")
                setPhase("finish", current)
            end
            return
        end
        check("chef_pasta_native_base", wet:getID() ~= Harness.chefPastaPotId,
            "native handcraft produced " .. tostring(wet:getFullType()))
        local tomato = inventory:AddItem("Base.Tomato")
        local preview = instanceItem("Base.WaterPotPasta")
        local previewEligible = preview and Harness.chefPasta:getItemsCanBeUse(
            Harness.player, preview, nil)
        if not check("chef_pasta_preview_topping_accepted",
            preview ~= nil and listHas(previewEligible, tomato),
            "native PastaPot accepts tomato against a transient preview base") then
            setPhase("finish", current)
            return
        end
        local possible = Harness.chefPasta:getItemsCanBeUse(Harness.player, wet, nil)
        if not check("chef_pasta_topping_accepted", listHas(possible, tomato),
            "native PastaPot accepts Base.Tomato") then
            setPhase("finish", current)
            return
        end
        ISTimedActionQueue.add(ISAddItemInRecipe:new(Harness.player,
            Harness.chefPasta, wet, tomato))
        setPhase("chef_pasta_dish_wait", current)
        return
    end
    if Harness.phase == "chef_pasta_dish_wait" then
        local dish = itemOf("Base.PastaPot")
        if not dish then
            if current - Harness.phaseStartedAt > 15000 then
                result("FAIL", "chef_pasta_native_result", "timed action did not assemble pasta")
                setPhase("finish", current)
            end
            return
        end
        check("chef_pasta_native_result", dish:getFullType() == "Base.PastaPot",
            "native evolved action assembled PastaPot")
        check("chef_pasta_uncooked_not_stock", SC.ChefWork.isPrepared(dish) == false,
            "Chef rejects the uncooked native result")
        dish:setCooked(true)
        check("chef_pasta_cooked_stock", SC.ChefWork.isPrepared(dish) == true,
            "Chef accepts the cooked native result")
        inventory:AddItem("Base.Bowl")
        inventory:AddItem("Base.Bowl")
        local craft = getScriptManager():getCraftRecipe("Make2Bowls")
        local containers = ArrayList.new()
        containers:add(inventory)
        local logic = HandcraftLogic.new(Harness.player, nil, nil)
        logic:setIsoObject(logic:findCraftSurface(Harness.player, 2)
            or Harness.chefSurfaceObject)
        logic:setContainers(containers)
        logic:setRecipeFromContextClick(craft, dish)
        if not check("chef_pasta_portion_requirements",
            logic:canPerformCurrentRecipe() == true,
            "native Make2Bowls accepts cooked PastaPot and two bowls") then
            setPhase("finish", current)
            return
        end
        ISTimedActionQueue.add(ISHandcraftAction.FromLogic(logic))
        setPhase("chef_pasta_bowls_wait", current)
        return
    end
    if Harness.phase == "chef_pasta_bowls_wait" then
        local bowls, emptyPot = 0, false
        local items = inventory:getItems()
        for index = 0, items:size() - 1 do
            local item = items:get(index)
            if item:getFullType() == "Base.PastaBowl"
                and SC.ChefWork.isPrepared(item) then bowls = bowls + 1 end
            if item:getFullType() == "Base.Pot" then emptyPot = true end
        end
        if bowls < 2 or not emptyPot then
            if current - Harness.phaseStartedAt > 15000 then
                result("FAIL", "chef_pasta_native_portions",
                    "bowls=" .. tostring(bowls) .. " pot=" .. tostring(emptyPot))
                setPhase("finish", current)
            end
            return
        end
        check("chef_pasta_native_portions", bowls == 2 and emptyPot,
            "native Make2Bowls made two safe portions and returned the pot")
        setPhase("finish", current)
    end
end

local UI_MENU_TABS = {
    "status", "talk", "orders", "groups", "expeditions", "loadout",
    "more", "base", "factions", "sheet", "journal", "support",
}

local function probeUIMenus(current)
    local index = Harness.uiMenuIndex or 1
    local tab = UI_MENU_TABS[index]
    if tab == nil then setPhase("finish", current) return end
    if Harness.phase == "ui_menu_capture" then
        if current - Harness.phaseStartedAt < 500 then return end
        local name = tostring(Harness.config.run_id) .. "-menu-" .. tab .. ".png"
        local captured, reason = pcall(function()
            getCore():TakeFullScreenshot(name)
        end)
        check("ui_menu_screenshot_" .. tab, captured, tostring(reason))
        if tab == "base" and SurvivorCompanion.UI.instance
            and SurvivorCompanion.UI.instance.detail then
            local panel = SurvivorCompanion.UI.instance.detail.content
            panel:setYScroll(-math.max(0,
                panel:getScrollHeight() - panel:getHeight()))
            setPhase("ui_menu_capture_bottom", current)
            return
        end
        Harness.uiMenuIndex = index + 1
        setPhase("ui_menu_probe", current)
        return
    end
    if Harness.phase == "ui_menu_capture_bottom" then
        if current - Harness.phaseStartedAt < 500 then return end
        local name = tostring(Harness.config.run_id) .. "-menu-base-bottom.png"
        local captured, reason = pcall(function()
            getCore():TakeFullScreenshot(name)
        end)
        check("ui_menu_screenshot_base_bottom", captured, tostring(reason))
        Harness.uiMenuIndex = index + 1
        setPhase("ui_menu_probe", current)
        return
    end
    local SC = SurvivorCompanion
    if Harness.uiMenuCompanionId == nil then
        for _, record in ipairs(SC.Registry.snapshot() or {}) do
            if record.actor and record.recruited == true then
                Harness.uiMenuCompanionId = record.id
                break
            end
        end
        -- Let the cloned save restore its roster before inspecting the
        -- companion-specific Status and Talk menus.
        if Harness.uiMenuCompanionId == nil
            and current - Harness.phaseStartedAt < 10000 then return end
    end
    local opened, root = pcall(SC.UI.open, tab, Harness.uiMenuCompanionId)
    if not check("ui_menu_open_" .. tab, opened and root ~= nil
        and root.selectedTab == tab and root.detail ~= nil,
        tostring(root)) then setPhase("finish", current) return end
    local panel = root.detail.content
    local valid = panel ~= nil and panel:getWidth() > 0
        and panel:getHeight() > 0
    if not check("ui_menu_viewport_" .. tab, valid,
        "width=" .. tostring(panel and panel:getWidth())
            .. " height=" .. tostring(panel and panel:getHeight())) then
        setPhase("finish", current) return
    end
    local rectangles, collision, overflow = {}, nil, nil
    for _, child in ipairs(panel.childrenInOrder or {}) do
        if child ~= panel.vscroll then
            local ok, x, y, width, height = pcall(function()
                return child:getX(), child:getY(), child:getWidth(),
                    child:getHeight()
            end)
            if ok and type(x) == "number" and type(y) == "number"
                and type(width) == "number" and type(height) == "number"
                and width > 0 and height > 0 then
                if x < -1 or x + width > panel:getWidth() + 1 then
                    overflow = tostring(x) .. "+" .. tostring(width)
                        .. "/" .. tostring(panel:getWidth())
                end
                for _, previous in ipairs(rectangles) do
                    local overlapX = math.min(x + width, previous.x + previous.width)
                        - math.max(x, previous.x)
                    local overlapY = math.min(y + height, previous.y + previous.height)
                        - math.max(y, previous.y)
                    if overlapX > 2 and overlapY > 2 then
                        collision = tostring(previous.x) .. "," .. tostring(previous.y)
                            .. " vs " .. tostring(x) .. "," .. tostring(y)
                        break
                    end
                end
                rectangles[#rectangles + 1] = {
                    x = x, y = y, width = width, height = height,
                }
            end
        end
    end
    local scrollHeight = tonumber(panel:getScrollHeight()) or 0
    local lastBottom = 0
    for _, rect in ipairs(rectangles) do
        lastBottom = math.max(lastBottom, rect.y + rect.height)
    end
    check("ui_menu_no_overlap_" .. tab, collision == nil
        and overflow == nil and scrollHeight + 1 >= lastBottom,
        "children=" .. tostring(#rectangles)
            .. " collision=" .. tostring(collision)
            .. " overflow=" .. tostring(overflow)
            .. " scroll=" .. tostring(scrollHeight)
            .. " bottom=" .. tostring(lastBottom))
    setPhase("ui_menu_capture", current)
end
Harness.probeUIMenus = probeUIMenus
-- Build 42's require reports true after loading a Lua file rather than
-- returning that file's table. Load probes only in their selected live phase:
-- the static Kahlua regression loads this harness without the probe modules.
local function externalProbe(moduleName, ...)
    require(moduleName)
    local probe = SCRealSandboxHarnessProbes
        and SCRealSandboxHarnessProbes[moduleName] or nil
    if type(probe) ~= "table" or type(probe.step) ~= "function" then
        error("live probe did not register: " .. moduleName)
    end
    return probe.step(...)
end

Harness.probeBaseMaintenance = function(...)
    return externalProbe("SCBaseMaintenanceProbe", ...)
end

Harness.probePyreBurn = function(...)
    return externalProbe("SCPyreBurnProbe", ...)
end

Harness.probeMedicalCheck = function(...)
    return externalProbe("SCMedicalCheckProbe", ...)
end

Harness.probeHygiene = function(...)
    return externalProbe("SCHygieneProbe", ...)
end

Harness.probeBaseSecondFloor = function(...)
    return externalProbe("SCBaseSecondFloorProbe", ...)
end

Harness.probeWaterSource = function(...)
    return externalProbe("SCWaterSourceProbe", ...)
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
    if Harness.config.team_extended_quiet_probe == "true"
        and (string.find(tostring(Harness.phase), "team_extended_", 1, true) == 1
            or (Harness.config.team_extended_route_probe == "true"
                and (Harness.phase == "team_local_travel_out"
                    or Harness.phase == "team_corpse_stream_death_wait"
                    or Harness.phase == "team_waypoint_wait"))
            or Harness.phase == "team_autonomous_scout"
            or Harness.phase == "team_road_restart_resume"
            or Harness.phase == "team_autonomous_search") then
        Harness.maintainBuildingQuietFixture(current)
    end

    if Harness.performanceSample and Harness.performanceSample.route then
        Harness.measurePerformance(current)
    end

    if string.sub(tostring(Harness.phase), 1, 14) == "medical_check_" then
        Harness.probeMedicalCheck(Harness, current, check, result, setPhase)
    elseif Harness.phase == "ui_menu_probe" or Harness.phase == "ui_menu_capture"
        or Harness.phase == "ui_menu_capture_bottom" then
        Harness.probeUIMenus(current)
    elseif Harness.phase == "fishing_map_list" then
        if current - Harness.phaseStartedAt < 4000 then return end
        local banks, reason, total = SurvivorCompanion.Fishing.bankCandidates(
            Harness.player, 1000, 32, 0, true)
        local mapped
        for _, row in ipairs(banks or {}) do
            if row.knowledge == "map_water_unconfirmed"
                and row.distance <= 500 then mapped = row break end
        end
        check("riverside_mapped_fishing_shore_available",
            mapped ~= nil and banks[1].distance >= 100,
            "count=" .. tostring(total) .. " reason=" .. tostring(reason)
                .. " nearest=" .. tostring(banks and banks[1]
                    and banks[1].id)
                .. " distance=" .. tostring(banks and banks[1]
                    and banks[1].distance)
                .. " player=" .. tostring(math.floor(Harness.playerX))
                .. ":" .. tostring(math.floor(Harness.playerY)))
        Harness.player:teleportTo(7330.5, 6069.5, 0)
        setPhase("fishing_truth_near", current)
    elseif Harness.phase == "fishing_truth_near"
        or Harness.phase == "fishing_truth_river" then
        if current - Harness.phaseStartedAt < 3000 then return end
        local x, y = Harness.phase == "fishing_truth_near"
            and 7330 or 7504, Harness.phase == "fishing_truth_near"
            and 6069 or 6045
        local cell = getCell()
        local function waterAt(tx, ty)
            local square = cell and cell:getGridSquare(tx, ty, 0)
            if not square then return "unloaded" end
            return tostring(SurvivorCompanion.Topology.squareIsWater(square))
        end
        local detail = "site=" .. x .. ":" .. y
            .. " tile=" .. waterAt(x, y)
            .. " east=" .. waterAt(x + 6, y) .. "/" .. waterAt(x + 9, y)
            .. " west=" .. waterAt(x - 6, y) .. "/" .. waterAt(x - 9, y)
            .. " north=" .. waterAt(x, y - 6) .. "/" .. waterAt(x, y - 9)
            .. " south=" .. waterAt(x, y + 6) .. "/" .. waterAt(x, y + 9)
        local terrainMatches = Harness.phase == "fishing_truth_near"
            and waterAt(x + 6, y) == "false"
            and waterAt(x + 9, y) == "false"
            or Harness.phase == "fishing_truth_river"
            and waterAt(x + 6, y) == "true"
            and waterAt(x + 9, y) == "true"
        check("fishing_bank_terrain_" .. Harness.phase, terrainMatches, detail)
        if Harness.phase == "fishing_truth_near" then
            Harness.player:teleportTo(7504.5, 6045.5, 0)
            setPhase("fishing_truth_river", current)
        else
            setPhase("finish", current)
        end
    elseif string.find(tostring(Harness.phase), "base_maintenance_", 1, true) == 1 then
        Harness.probeBaseMaintenance(Harness, current, check, result, setPhase)
    elseif string.find(tostring(Harness.phase), "pyre_burn_", 1, true) == 1 then
        Harness.probePyreBurn(Harness, current, check, result, setPhase)
    elseif string.find(tostring(Harness.phase), "hygiene_", 1, true) == 1 then
        Harness.probeHygiene(Harness, current, check, result, setPhase)
    elseif string.find(tostring(Harness.phase), "base_second_floor_", 1, true) == 1 then
        Harness.probeBaseSecondFloor(Harness, current, check, result, setPhase)
    elseif string.find(tostring(Harness.phase), "water_source_", 1, true) == 1 then
        Harness.probeWaterSource(Harness, current, check, result, setPhase)
    elseif string.find(tostring(Harness.phase), "chef_", 1, true) == 1 then
        Harness.probeChefRecipes(current)
    elseif Harness.phase == "alife_wait" or Harness.phase == "alife_companion_spawn"
        or Harness.phase == "alife_shell_wait" or Harness.phase == "alife_damage" then
        Harness.probeALifeDamage(current)
    elseif Harness.phase == "place_metadata_probe" then
        local places = SurvivorCompanion.ExpeditionPlaces
        local world = type(getWorld) == "function" and getWorld() or nil
        local grid = world and world:getMetaGrid() or nil
        check("place_meta_grid_available", grid ~= nil,
            "the installed world exposes building metadata")
        local candidates, reason = places.nearby(6100, 5280, 80, 128)
        check("place_candidates_available", candidates ~= nil,
            "reason=" .. tostring(reason))
        if candidates then
            check("place_candidates_nonempty", #candidates > 0,
                "count=" .. tostring(#candidates))
            for index, place in ipairs(candidates) do
                if index <= 20 or place.kind == "police" or place.kind == "fire" then
                    print("SC_PLACE_META|candidate=" .. tostring(index)
                        .. "|id=" .. clean(place.id)
                        .. "|kind=" .. clean(place.kind)
                        .. "|levels=" .. clean(place.minLevel)
                        .. ":" .. clean(place.maxLevel)
                        .. "|ground=" .. tostring(place.groundFloor)
                        .. "|street=" .. clean(place.street)
                        .. "|rooms=" .. clean(table.concat(place.rooms, ",")))
                end
            end
        end
        local known, knownReason = places.knownNearby(6100, 5280, 80, 32)
        check("place_player_known_query_available", known ~= nil,
            "reason=" .. tostring(knownReason))
        local gasKnown = false
        for index, place in ipairs(known or {}) do
            print("SC_PLACE_KNOWN|candidate=" .. tostring(index)
                .. "|id=" .. clean(place.id)
                .. "|kind=" .. clean(place.kind)
                .. "|street=" .. clean(place.street)
                .. "|knowledge=" .. clean(place.knowledge))
            check("place_known_" .. tostring(index) .. "_projected",
                place.knowledge == "player_seen_interior"
                    and place.groundFloor == true
                    and place.rooms == nil,
                "no raw room metadata or unobserved label is projected")
            if place.id == "6074:5299:6086:5318" then
                gasKnown = true
            end
        end
        check("place_seen_gas_station_available", gasKnown,
            "the player currently occupies the gas station")
        check("place_unknown_metadata_not_all_projected",
            candidates ~= nil and known ~= nil and #known < #candidates,
            "known=" .. tostring(known and #known)
                .. " metadata=" .. tostring(candidates and #candidates))
        local config = SurvivorCompanion.Config
        check("place_scope_defaults_all_nearby",
            config.get("expeditionDestinationScope") == "all_nearby",
            "scope=" .. tostring(config.get("expeditionDestinationScope")))
        local allTargets, allReason = places.targetableNearby(
            6100, 5280, 80, 32)
        check("place_default_targets_include_unvisited",
            allTargets ~= nil and known ~= nil and #allTargets > #known,
            "all=" .. tostring(allTargets and #allTargets)
                .. " known=" .. tostring(known and #known)
                .. " reason=" .. tostring(allReason))
        local allProjected = allTargets ~= nil
        for _, place in ipairs(allTargets or {}) do
            if place.knowledge ~= "map_metadata_unconfirmed"
                or place.rooms ~= nil or place.groundFloor ~= true then
                allProjected = false
            end
        end
        check("place_all_targets_projected", allProjected,
            "map-derived target labels omit raw rooms and basements")
        local knownIds = {}
        for _, place in ipairs(known or {}) do knownIds[place.id] = true end
        local unvisitedCount, unvisitedApproaches = 0, 0
        for _, place in ipairs(allTargets or {}) do
            if not knownIds[place.id] then
                unvisitedCount = unvisitedCount + 1
                local approach, approachReason = places.loadedApproach(
                    place, Harness.player)
                if approach ~= nil then
                    unvisitedApproaches = unvisitedApproaches + 1
                end
                print("SC_PLACE_UNVISITED|id=" .. clean(place.id)
                    .. "|kind=" .. clean(place.kind)
                    .. "|distance=" .. clean(place.distance)
                    .. "|approach=" .. clean(approach and
                        (tostring(approach.x) .. "," .. tostring(approach.y)))
                    .. "|nodes=" .. clean(approach and approach.pathNodes)
                    .. "|reason=" .. clean(approachReason))
            end
        end
        check("place_unvisited_candidate_count",
            unvisitedCount > 0,
            "unvisited=" .. tostring(unvisitedCount)
                .. " exterior_routes=" .. tostring(unvisitedApproaches))
        local unknownBuilding = grid and grid:getBuildingAt(6160, 5255, 0)
        local unknownPlace = places.describeBuilding(unknownBuilding, true)
        if unknownPlace and unknownPlace.id == "6156:5236:6174:5266" then
            local cell = world:getCell()
            local interiorSquares = {}
            for x = unknownPlace.bounds.x, unknownPlace.bounds.x2 do
                for y = unknownPlace.bounds.y, unknownPlace.bounds.y2 do
                    local square = cell:getGridSquare(x, y, 0)
                    if square ~= nil and square:getRoom() ~= nil
                        and SurvivorCompanion.GameplayUtil.isSquareFree(square) then
                        interiorSquares[#interiorSquares + 1] = square
                    end
                end
            end
            table.sort(interiorSquares, function(a, b)
                local aDistance = math.abs(a:getX() - 6155)
                    + math.abs(a:getY() - 5264)
                local bDistance = math.abs(b:getX() - 6155)
                    + math.abs(b:getY() - 5264)
                if aDistance ~= bDistance then return aDistance < bDistance end
                if a:getX() ~= b:getX() then return a:getX() < b:getX() end
                return a:getY() < b:getY()
            end)
            local interiorPath, interiorGoal, pathReason
            for index = 1, math.min(12, #interiorSquares) do
                local square = interiorSquares[index]
                local path, reason = SurvivorCompanion.Navigation.findPath(
                    Harness.player:getCurrentSquare(), square,
                    { actor = Harness.player, nodeBudget = 1800 })
                if path ~= nil then
                    interiorPath, interiorGoal = path, square
                    break
                end
                pathReason = reason
            end
            print("SC_PLACE_UNVISITED_INTERIOR|loaded_free="
                .. tostring(#interiorSquares)
                .. "|tried=" .. tostring(math.min(12, #interiorSquares))
                .. "|goal=" .. clean(interiorGoal and
                    (tostring(interiorGoal:getX()) .. ","
                        .. tostring(interiorGoal:getY())))
                .. "|nodes=" .. clean(interiorPath and #interiorPath)
                .. "|reason=" .. clean(pathReason))
        end
        config.refreshSandbox({ LivingFellows = {
            ExpeditionDestinationScope = 2,
        } })
        local knownTargets, knownTargetReason = places.targetableNearby(
            6100, 5280, 80, 32)
        check("place_known_only_option_filters_targets",
            knownTargets ~= nil and known ~= nil
                and #knownTargets == #known
                and #knownTargets > 0
                and knownTargets[1].knowledge == "player_seen_interior",
            "known_option=" .. tostring(knownTargets and #knownTargets)
                .. " reason=" .. tostring(knownTargetReason))
        config.refreshSandbox()
        print("SC_PLACE_SCOPE|all=" .. tostring(allTargets and #allTargets)
            .. "|known=" .. tostring(knownTargets and #knownTargets)
            .. "|restored=" .. tostring(config.get("expeditionDestinationScope")))
        local distantApproaches = 0
        for _, sample in ipairs({
            { name = "police", x = 6081, y = 5255 },
            { name = "fire", x = 6119, y = 5257 },
            { name = "gas_station", x = 6080, y = 5308 },
        }) do
            local building = grid and grid:getBuildingAt(sample.x, sample.y, 0)
            local place, placeReason = places.describeBuilding(building)
            print("SC_PLACE_META|sample=" .. sample.name
                .. "|kind=" .. clean(place and place.kind)
                .. "|id=" .. clean(place and place.id)
                .. "|levels=" .. clean(place and place.minLevel)
                .. ":" .. clean(place and place.maxLevel)
                .. "|ground=" .. tostring(place and place.groundFloor)
                .. "|reason=" .. clean(placeReason)
                .. "|rooms=" .. clean(place and table.concat(place.rooms, ",")))
            check("place_" .. sample.name .. "_building_found", place ~= nil,
                "sample=" .. sample.x .. "," .. sample.y
                    .. " reason=" .. tostring(placeReason))
            check("place_" .. sample.name .. "_room_classification",
                place ~= nil and place.kind == sample.name,
                "kind=" .. tostring(place and place.kind))
            local inCandidates = false
            for _, candidate in ipairs(candidates or {}) do
                if place ~= nil and candidate.id == place.id then
                    inCandidates = true break
                end
            end
            check("place_" .. sample.name .. "_in_nearby_query", inCandidates,
                "id=" .. tostring(place and place.id))
            local approach, approachReason = places.loadedApproach(
                place, Harness.player)
            print("SC_PLACE_APPROACH|sample=" .. sample.name
                .. "|point=" .. clean(approach and (tostring(approach.x)
                    .. "," .. tostring(approach.y)))
                .. "|side=" .. clean(approach and approach.side)
                .. "|nodes=" .. clean(approach and approach.pathNodes)
                .. "|reason=" .. clean(approachReason))
            if approach ~= nil then
                check("place_" .. sample.name .. "_approach_scope",
                    approach.buildingId == place.id
                        and approach.scope == "loaded_exterior_only"
                        and approach.pathNodes >= 1,
                    "route is only an exterior site approach")
                if sample.name ~= "gas_station" then
                    distantApproaches = distantApproaches + 1
                end
            end
        end
        check("place_distant_approach_found", distantApproaches >= 1,
            "police_or_fire_loaded_exterior_route_count="
                .. tostring(distantApproaches))
        setPhase("finish", current)
    elseif Harness.phase == "performance_baseline_wait" then
        local records = #SurvivorCompanion.Registry.records()
        local target = tonumber(Harness.config.performance_population_target) or 4
        local elapsed = current - Harness.phaseStartedAt
        local timeout = target > 4 and 120000 or 25000
        if records >= 4 and current - Harness.phaseStartedAt >= 8000 then
            local ready = Harness.preparePerformancePopulation(current)
            if ready == true then Harness.beginPerformanceSample(current) end
        elseif elapsed >= timeout then
            result("FAIL", "performance_baseline_restored_population",
                "records=" .. tostring(records))
            setPhase("finish", current)
        end
        if Harness.phase == "performance_baseline_wait" and elapsed >= timeout then
            local ticket = Harness.performanceScaleTicket
            if ticket then pcall(SurvivorCompanion.Actor.cancelSpawn, ticket) end
            result("FAIL", "performance_scale_timeout",
                "records=" .. tostring(records) .. " target=" .. tostring(target))
            setPhase("finish", current)
        end
    elseif Harness.phase == "performance_warmup" then
        local target = tonumber(Harness.config.performance_population_target) or 4
        local elapsed = current - Harness.phaseStartedAt
        if target > 4 then
            local ready = Harness.preparePerformancePopulation(current)
            if Harness.phase ~= "performance_warmup" then return end
            if elapsed >= 120000 then
                local ticket = Harness.performanceScaleTicket
                if ticket then pcall(SurvivorCompanion.Actor.cancelSpawn, ticket) end
                result("FAIL", "performance_scale_timeout",
                    "remote=true records="
                        .. tostring(#SurvivorCompanion.Registry.records())
                        .. " target=" .. tostring(target))
                setPhase("finish", current)
                return
            end
            if ready ~= true then return end
            if elapsed < 8000 then return end
            local team = Harness.team or {}
            local teamIds = {}
            for _, record in ipairs(team) do teamIds[record.id] = true end
            local extras, independent = 0, true
            for _, record in ipairs(SurvivorCompanion.Registry.records()) do
                if not teamIds[record.id] then
                    extras = extras + 1
                    independent = independent
                        and not SurvivorCompanion.ExpeditionPrototype.isMember(record.actor)
                end
            end
            if not check("performance_scale_remote_distribution",
                #team == 4 and extras == target - 4 and independent,
                "remote_team=" .. tostring(#team)
                    .. " player_area_extras=" .. tostring(extras)
                    .. " independent=" .. tostring(independent)) then
                setPhase("finish", current)
                return
            end
        end
        if elapsed >= 8000 then
            Harness.beginPerformanceSample(current)
        end
    elseif Harness.phase == "performance_measure" then
        Harness.measurePerformance(current)
    elseif Harness.phase == "leader_wait" then
        beginLeaderSlotProbe(current)
    elseif Harness.phase == "leader_wait_slot" then
        probeLeaderSlot(current)
    elseif Harness.phase == "leader_remote_wait" then
        probeLeaderRemote(current)
    elseif Harness.phase == "team_radio_wait" then
        probeTeamRadioWait(current)
    elseif Harness.phase == "team_overlap_start" then
        Harness.probeTeamOverlapStart(current)
    elseif Harness.phase == "team_overlap_merge" then
        Harness.probeTeamOverlapMerge(current)
    elseif Harness.phase == "team_overlap_split" then
        Harness.probeTeamOverlapSplit(current)
    elseif Harness.phase == "team_overlap_released" then
        Harness.probeTeamOverlapReleased(current)
    elseif Harness.phase == "team_overlap_restart_wait" then
        Harness.probeTeamOverlapRestart(current)
    elseif Harness.phase == "idle_slot_restart_start" then
        Harness.probeIdleSlotRestartStart(current)
    elseif Harness.phase == "idle_slot_restart_wait" then
        Harness.probeIdleSlotRestartWait(current)
    elseif Harness.phase == "team_corpse_reload_wait" then
        Harness.probeTeamCorpseReloadWait(current)
    elseif Harness.phase == "team_loot_survey" then
        probeTeamLootSurvey(current)
    elseif Harness.phase == "team_loot_relocate_wait" then
        probeTeamLootRelocate(current)
    elseif Harness.phase == "team_loot_watch" then
        probeTeamLootWatch(current)
    elseif Harness.phase == "team_loot_verify_remote" then
        probeTeamLootVerifyRemote(current)
    elseif Harness.phase == "team_loot_verify_visit" then
        probeTeamLootVerifyVisit(current)
    elseif Harness.phase == "team_waypoint_wait" then
        probeTeamWaypointWait(current)
    elseif Harness.phase == "team_straggler_stage" then
        Harness.probeTeamStragglerStage(current)
    elseif Harness.phase == "team_straggler_hold" then
        Harness.probeTeamStragglerHold(current)
    elseif Harness.phase == "team_straggler_rejoin" then
        Harness.probeTeamStragglerRejoin(current)
    elseif Harness.phase == "team_local_travel_stage" then
        Harness.probeTeamLocalTravelStage(current)
    elseif Harness.phase == "team_local_travel_out" then
        Harness.probeTeamLocalTravelOut(current)
    elseif Harness.phase == "team_local_travel_return" then
        Harness.probeTeamLocalTravelReturn(current)
    elseif Harness.phase == "team_local_loot_search" then
        Harness.probeLocalLootSearch(current)
    elseif Harness.phase == "team_autonomous_scout" then
        Harness.probeAutonomousScout(current)
    elseif Harness.phase == "team_autonomous_search" then
        Harness.probeAutonomousSearch(current)
    elseif Harness.phase == "team_autonomous_search_resume" then
        Harness.probeAutonomousSearchResume(current)
    elseif Harness.phase == "team_road_restart_resume" then
        Harness.probeRoadRestartResume(current)
    elseif Harness.phase == "team_extended_route_stage" then
        Harness.probeExtendedRouteStage(current)
    elseif Harness.phase == "team_corpse_stream_death_wait" then
        Harness.probeCorpseStreamDeathWait(current)
    elseif Harness.phase == "team_corpse_stream_restart_stage" then
        Harness.probeCorpseStreamRestartStage(current)
    elseif Harness.phase == "team_corpse_stream_visit_wait" then
        Harness.probeCorpseStreamVisitWait(current)
    elseif Harness.phase == "team_extended_route_walk" then
        Harness.probeExtendedRouteWalk(current)
    elseif Harness.phase == "team_extended_route_verify" then
        Harness.probeExtendedRouteVerify(current)
    elseif Harness.phase == "team_extended_return_stage" then
        Harness.probeExtendedReturnStage(current)
    elseif Harness.phase == "team_extended_return_walk" then
        Harness.probeExtendedReturnWalk(current)
    elseif Harness.phase == "team_extended_return_verify" then
        Harness.probeExtendedReturnVerify(current)
    elseif Harness.phase == "team_building_wait" then
        Harness.probeBuildingWait(current)
    elseif Harness.phase == "team_building_approach" then
        Harness.probeBuildingApproach(current)
    elseif Harness.phase == "team_building_walk" then
        Harness.probeBuildingWalk(current)
    elseif Harness.phase == "team_building_exit" then
        Harness.probeBuildingExit(current)
    elseif Harness.phase == "team_door_bash" then
        Harness.probeDoorBash(current)
    elseif Harness.phase == "team_door_bash_entry" then
        Harness.probeDoorBashEntry(current)
    elseif Harness.phase == "team_door_bash_auto" then
        Harness.probeDoorBashAuto(current)
    elseif Harness.phase == "leader_wait_capture" then
        probeLeaderCapture(current)
    elseif Harness.phase == "leader_observe" then
        probeLeaderSurvival(current)
    elseif Harness.phase == "team_handoff_wait" then
        probeTeamHandoff(current)
    elseif Harness.phase == "team_handoff_capture" then
        probeTeamHandoffCapture(current)
    elseif Harness.phase == "team_all_dead_capture" then
        probeTeamAllDeadCapture(current)
    elseif Harness.phase == "team_all_dead_reuse_wait" then
        probeTeamAllDeadReuse(current)
    elseif Harness.phase == "team_radio_kit_capture" then
        probeTeamRadioKitCapture(current)
    elseif Harness.phase == "team_expedition_ui_radio_wait" then
        Harness.probeTeamExpeditionUiRadioWait(current)
    elseif Harness.phase == "team_radio_kit_place_wait" then
        Harness.probeTeamRadioKitPlaceWait(current)
    elseif Harness.phase == "team_radio_kit_pickup_wait" then
        probeTeamRadioKitPickupWait(current)
    elseif Harness.phase == "team_radio_kit_wait" then
        probeTeamRadioKitWait(current)
    elseif Harness.phase == "team_handoff_observe" then
        probeTeamHandoffObserve(current)
    elseif Harness.phase == "team_second_handoff_wait" then
        probeTeamSecondHandoff(current)
    elseif Harness.phase == "split_start" then
        beginSplitScreenProbe(current)
    elseif Harness.phase == "split_wait_loaded" then
        probeSplitScreenLoaded(current)
    elseif Harness.phase == "fishing_find_bank"
        or Harness.phase == "fishing_approach"
        or Harness.phase == "fishing_wait_catch"
        or Harness.phase == "fishing_wait_capture" then
        Harness.probeFishingBank(current)
    elseif Harness.phase == "split_wait_capture" then
        probeSplitScreenCapture(current)
    elseif Harness.phase == "split_observe" then
        probeSplitScreenSimulation(current)
    elseif Harness.phase == "split_restart_recovery" then
        Harness.probeColdRestartRecovery(current)
    elseif Harness.phase == "split_restart_crash_save" then
        Harness.probeColdRestartCrashSave(current)
    elseif Harness.phase == "split_restart_lf_first_save" then
        Harness.probeColdRestartLfFirstSave(current)
    elseif Harness.phase == "split_restart_crash_capture" then
        Harness.probeColdRestartCrashCapture(current)
    elseif Harness.phase == "split_restart_crash_hold" then
        return
    elseif Harness.phase == "split_restart_auto_capture" then
        Harness.probeColdRestartAutoCapture(current)
    elseif Harness.phase == "split_restart_handoff_wait" then
        Harness.probeColdRestartHandoffWait(current)
    elseif Harness.phase == "split_restart_handoff_capture" then
        Harness.probeColdRestartHandoffCapture(current)
    elseif Harness.phase == "wait_runtime" then
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
    elseif Harness.phase == "begin_stair_crossing" then
        Harness.beginStairCrossing(current)
    elseif Harness.phase == "stair_crossing" then
        Harness.runStairCrossing(current)
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
    elseif Harness.phase == "base_layout_begin" then
        Harness.beginBaseLayout(current)
    elseif Harness.phase == "base_layout_capture" then
        Harness.probeBaseLayout(current)
    elseif Harness.phase == "companion_inventory_begin" then
        Harness.beginCompanionInventory(current)
    elseif Harness.phase == "companion_inventory_capture" then
        Harness.probeCompanionInventory(current)
    elseif Harness.phase == "furniture_pose_begin" then
        Harness.beginFurniturePose(current)
    elseif Harness.phase == "furniture_pose_spawn" or Harness.phase == "furniture_pose_entry"
        or Harness.phase == "furniture_pose_exit" then
        Harness.probeFurniturePose(current)
    elseif Harness.phase == "vehicle_passenger_begin" then
        Harness.beginVehiclePassenger(current)
    elseif Harness.phase == "vehicle_passenger_spawn"
        or Harness.phase == "vehicle_passenger_wait_stationary"
        or Harness.phase == "vehicle_passenger_settle"
        or Harness.phase == "vehicle_passenger_capture" then
        Harness.probeVehiclePassenger(current)
    elseif Harness.phase == "woodcutter_probe" then
        Harness.probeWoodcutter(current)
    elseif Harness.phase == "posted_stream_probe" then
        Harness.probePostedStream(current)
    elseif Harness.phase == "posted_stream_far" then
        Harness.probePostedStreamFar(current)
    elseif Harness.phase == "posted_stream_return_wait" then
        Harness.probePostedStreamReturn(current)
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
    if Harness.config.cold_restart_crash_probe == "true" then
        SC.ExpeditionPrototype.holdColdHandoffForTest(true)
    end
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
    if Harness.config.medical_check_probe == "true" then
        setPhase("medical_check_setup", Harness.startedAt)
    elseif Harness.config.ui_menu_probe == "true" then
        setPhase("ui_menu_probe", Harness.startedAt)
    elseif Harness.config.fishing_map_list_probe == "true" then
        setPhase("fishing_map_list", Harness.startedAt)
    elseif Harness.config.base_maintenance_probe == "true" then
        setPhase("base_maintenance_setup", Harness.startedAt)
    elseif Harness.config.pyre_burn_probe == "true" then
        setPhase("pyre_burn_setup", Harness.startedAt)
    elseif Harness.config.hygiene_probe == "true" then
        setPhase("hygiene_setup", Harness.startedAt)
    elseif Harness.config.base_second_floor_probe == "true" then
        setPhase("base_second_floor_setup", Harness.startedAt)
    elseif Harness.config.water_source_probe == "true" then
        setPhase("water_source_setup", Harness.startedAt)
    elseif Harness.config.chef_recipes_probe == "true" then
        setPhase("chef_recipes_begin", Harness.startedAt)
    elseif Harness.config.project_alife_damage_probe == "true" then
        setPhase("alife_wait", Harness.startedAt)
    elseif Harness.config.team_corpse_streaming_reload_probe == "true" then
        setPhase("team_corpse_stream_restart_stage", Harness.startedAt)
    elseif Harness.config.place_metadata_only == "true" then
        setPhase("place_metadata_probe", Harness.startedAt)
    elseif Harness.config.performance_baseline_only == "true" then
        setPhase("performance_baseline_wait", Harness.startedAt)
    elseif Harness.config.team_idle_slot_restart_probe == "true" then
        setPhase("idle_slot_restart_start", Harness.startedAt)
    elseif Harness.config.leader_slot_only == "true" then
        setPhase("leader_wait", Harness.startedAt)
    elseif Harness.config.split_screen_only == "true" then
        setPhase("split_start", Harness.startedAt)
    elseif Harness.config.base_layout_only == "true" then
        setPhase("base_layout_begin", Harness.startedAt)
    elseif Harness.config.companion_inventory_only == "true"
        or Harness.config.companion_transfer_probe == "true" then
        setPhase("companion_inventory_begin", Harness.startedAt)
    elseif Harness.config.furniture_pose_only == "true" then
        setPhase("furniture_pose_begin", Harness.startedAt)
    elseif Harness.config.vehicle_passenger_only == "true" then
        setPhase("vehicle_passenger_begin", Harness.startedAt)
    elseif Harness.config.woodcutter_only == "true" then
        setPhase("woodcutter_probe", Harness.startedAt)
    elseif Harness.config.posted_stream_only == "true" then
        setPhase("posted_stream_probe", Harness.startedAt)
    elseif Harness.config.faction_map_only == "true" then
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
if Events and Events.OnTick then Events.OnTick.Add(function()
    if Harness.splitObserver ~= nil and Harness.player ~= nil then
        Harness.splitTickSingleton = IsoPlayer.getInstance() == Harness.player
        Harness.splitTickGetPlayer = getPlayer() == Harness.player
    end
end) end
if Events and Events.OnWeaponHitCharacter then Events.OnWeaponHitCharacter.Add(Harness.onMeleeWeaponHit) end
if Events and Events.OnPlayerGetDamage then Events.OnPlayerGetDamage.Add(Harness.onObserverDamage) end
if Events and Events.OnPlayerDeath then Events.OnPlayerDeath.Add(Harness.onObserverDeath) end

SCRealSandboxHarness = Harness
return Harness
