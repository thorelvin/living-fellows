-- SPDX-License-Identifier: MIT
-- Disposable observe-only telemetry. Never selects candidates or issues orders.
SCSoakAudit = {}
local Audit, state = SCSoakAudit, nil
local function packed(...) return { n = select("#", ...), ... } end
local function clean(value)
    local text = tostring(value)
    text = string.gsub(text, "[\r\n|]", " ")
    return string.sub(text, 1, 640)
end
local function emit(kind, text)
    print("SC_SOAK|" .. kind .. "|" .. text)
end
local function read(object, method, ...)
    if object == nil then return nil end
    local args = packed(...)
    local ok, value = pcall(function()
        local fn = object[method]
        if type(fn) ~= "function" then return nil end
        return fn(object, unpack(args, 1, args.n))
    end)
    if ok then return value end
    return nil
end
local function now(SC)
    return SC.GameplayUtil and SC.GameplayUtil.nowMs() or 0
end
local function actorId(SC, actor)
    local ok, id = pcall(SC.GameplayUtil.idOf, actor)
    return ok and clean(id) or "unknown"
end
local function age(current, started)
    return tonumber(started) and math.max(0, current - tonumber(started)) or nil
end
local function recordFailure(kind, reason)
    local key = kind .. ":" .. clean(reason)
    if state.failures[key] == nil then
        if state.failureKeys >= 32 then key = kind .. ":other" end
        if state.failures[key] == nil then state.failureKeys = state.failureKeys + 1 end
    end
    state.failures[key] = (state.failures[key] or 0) + 1
    if state.failures[key] <= 2 and state.failureLogs < 20 then
        state.failureLogs = state.failureLogs + 1
        emit("speech_rejected", "kind=" .. kind .. "|reason=" .. clean(reason))
    end
end

function Audit.start(SC)
    if state ~= nil then return end
    state = { startedAt = now(SC), speech = 0, metadata = 0,
        failures = {}, failureKeys = 0, failureLogs = 0, actors = {}, samples = 0,
        changeLogs = 0, perfSamples = 0 }
    if SC.FloorSort and type(SC.FloorSort.update) == "function" then
        state.floor, state.floorUpdate = SC.FloorSort, SC.FloorSort.update
        state.floorWrapper = function(actor, baseState, job, ...)
            local claim = job and job.target and job.target.floorCargo
            local itemId = claim and claim.itemId
            local result = packed(state.floorUpdate(actor, baseState, job, ...))
            if result[1] == true and (result[2] == "floor_item_stored"
                or result[2] == "floor_item_discarded") then
                emit("floor_transfer", "at=" .. now(SC) .. "|actor=" .. actorId(SC, actor)
                    .. "|job=" .. clean(job and job.id) .. "|item=" .. clean(itemId)
                    .. "|result=" .. clean(result[2]))
            end
            return unpack(result, 1, result.n)
        end
        state.floor.update = state.floorWrapper
    end
    local utility, dialogue = SC.GameplayUtil, SC.Dialogue
    if utility and type(utility.say) == "function" then
        state.utility, state.say = utility, utility.say
        state.sayWrapper = function(actor, line, ...)
            -- No pcall: preserve original errors as well as nil/trailing returns.
            local result = packed(state.say(actor, line, ...))
            if result[1] == true then
                state.speech = state.speech + 1
                if state.speech <= 512 then
                    emit("speech", "n=" .. state.speech .. "|at=" .. now(SC)
                        .. "|actor=" .. actorId(SC, actor) .. "|line=" .. clean(line))
                end
            else recordFailure("say", result[2]) end
            return unpack(result, 1, result.n)
        end
        utility.say = state.sayWrapper
    end
    if dialogue and type(dialogue.emitResolved) == "function" then
        state.dialogue, state.emitResolved = dialogue, dialogue.emitResolved
        state.emitWrapper = function(actor, topic, line, ...)
            local result = packed(state.emitResolved(actor, topic, line, ...))
            if result[1] == true then
                state.metadata = state.metadata + 1
                if state.metadata <= 512 then
                    local receipt = type(result[3]) == "table" and result[3] or {}
                    emit("dialogue_meta", "at=" .. now(SC) .. "|actor="
                        .. actorId(SC, actor) .. "|topic=" .. clean(topic)
                        .. "|channel=" .. clean(receipt.channel)
                        .. "|spokenAt=" .. clean(receipt.spokenAt)
                        .. "|displayUntil=" .. clean(receipt.displayUntil)
                        .. "|line=" .. clean(line))
                end
            else recordFailure("resolved", result[2]) end
            return unpack(result, 1, result.n)
        end
        dialogue.emitResolved = state.emitWrapper
    end
    emit("start", "at=" .. state.startedAt .. "|release="
        .. clean(SC.Identity and SC.Identity.release)
        .. "|speech=accepted_native_enqueue|metadata=not_additional_speech")
end

function Audit.sample(SC, actors, current, report)
    if state == nil then return end
    state.samples = state.samples + 1
    local utility = SC.GameplayUtil
    local time = type(getGameTime) == "function" and getGameTime() or nil
    local worldHours = read(time, "getWorldAgeHours")
    local base = SC.BaseLife and SC.BaseLife.active and SC.BaseLife.active()
    for index = 1, math.min(#actors, 32) do
        local entry = actors[index]
        local actor, id = entry.actor, tostring(entry.id)
        local downtime = SC.Downtime and SC.Downtime.peek(actor)
        local activity = downtime and downtime.active
        local nav = SC.Navigation and SC.Navigation.peek(actor)
        local retained = nav and (nav.decisionApproach or nav.scavengeSustain)
        -- current/summary/snapshot on ActionSupervisor invoke update(), so read
        -- existing token references instead of advancing a production action.
        local token = activity and activity.supervisorToken
            or nav and nav.nativeLease and nav.nativeLease.supervisorToken
            or retained and retained.intent and retained.intent.supervisorToken
        local signature = clean(activity and activity.kind) .. ":"
            .. clean(token and token.phase) .. ":" .. clean(read(actor, "isAsleep"))
        if read(actor, "isAsleep") == true and state.sleepScreenshot ~= true then
            state.sleepScreenshot = true
            pcall(function()
                local harness = rawget(_G, "SCRealSandboxHarness")
                local runId = harness and harness.config and harness.config.run_id or "SC-soak"
                getCore():TakeFullScreenshot(runId .. "-natural-sleep")
            end)
        end
        local previous = state.actors[id]
        if previous ~= signature then
            state.actors[id] = signature
            state.changeLogs = state.changeLogs + 1
            if state.changeLogs <= 512 then
                emit("activity_change", "at=" .. current .. "|actor=" .. clean(id)
                    .. "|worldHours=" .. clean(worldHours)
                    .. "|kind=" .. clean(activity and activity.kind)
                    .. "|phase=" .. clean(token and token.phase)
                    .. "|asleep=" .. clean(read(actor, "isAsleep"))
                    .. "|fatigue=" .. clean(utility.characterStatValue(actor, "FATIGUE", nil))
                    .. "|durationHours=" .. clean(activity and activity.gameDurationHours))
            end
        end
        if report then
            local saved = read(actor, "getModData")
            saved = type(saved) == "table" and saved or {}
            local resident = SC.BaseLife and type(SC.BaseLife.resident) == "function"
                and SC.BaseLife.resident(id) or nil
            local function stat(name)
                return utility.characterStatValue(actor, name, nil)
            end
            emit("actor", "at=" .. current .. "|actor=" .. clean(id)
                .. "|order=" .. clean(saved.SC_Order) .. "|serial=" .. clean(saved.SC_CommandSerial)
                .. "|duty=" .. clean(resident and resident.duty)
                .. "|role=" .. clean(resident and resident.role)
                .. "|fatigue=" .. clean(stat("FATIGUE"))
                .. "|hunger=" .. clean(stat("HUNGER")) .. "|thirst=" .. clean(stat("THIRST"))
                .. "|pain=" .. clean(stat("PAIN"))
                .. "|panic=" .. clean(stat("PANIC")) .. "|asleep=" .. clean(read(actor, "isAsleep"))
                .. "|kind=" .. clean(activity and activity.kind)
                .. "|approaching=" .. clean(activity and activity.approaching)
                .. "|start=" .. clean(activity and activity.startedAt)
                .. "|sleepStarted=" .. clean(activity and activity.sleepStarted)
                .. "|sleepStartHour=" .. clean(activity and activity.startedGameHour)
                .. "|durationMs=" .. clean(activity and activity.durationMs)
                .. "|durationHours=" .. clean(activity and activity.gameDurationHours)
                .. "|supervisor=" .. clean(token and token.owner) .. ":" .. clean(token and token.action)
                .. "|phase=" .. clean(token and token.phase)
                .. "|actionAge=" .. clean(token and age(current, token.startedAt))
                .. "|phaseAge=" .. clean(token and age(current, token.phaseAt)))
        end
    end
    if not report then return end
    emit("clock", "at=" .. current .. "|elapsed=" .. (current - state.startedAt)
        .. "|worldHours=" .. clean(worldHours) .. "|timeOfDay=" .. clean(read(time, "getTimeOfDay"))
        .. "|speech=" .. state.speech .. "|dialogueMetadata=" .. state.metadata)
    local performance = SC.Performance
    if performance and type(performance.snapshot) == "function" then
        local p = performance.snapshot()
        state.perfSamples = state.perfSamples + 1
        emit("perf", "at=" .. current .. "|frames=" .. clean(p.frames)
            .. "|load=" .. clean(p.loadLevel) .. "|p50=" .. clean(p.p50FrameMs)
            .. "|p95=" .. clean(p.p95FrameMs) .. "|max=" .. clean(p.maxFrameMs)
            .. "|over=" .. clean(p.overBudgetFrames) .. "|deferred=" .. clean(p.deferredFrames)
            .. "|tick95=" .. clean(p.wholeTick and p.wholeTick.p95Ms)
            .. "|tickMax=" .. clean(p.wholeTick and p.wholeTick.maxMs)
            .. "|pre95=" .. clean(p.preSchedulerTick and p.preSchedulerTick.p95Ms))
    end
end

function Audit.finish(SC)
    if state == nil then return end
    emit("finish", "elapsed=" .. (now(SC) - state.startedAt) .. "|samples=" .. state.samples
        .. "|speech=" .. state.speech .. "|dialogueMetadata=" .. state.metadata
        .. "|perfSamples=" .. state.perfSamples)
    for key, count in pairs(state.failures) do
        emit("rejections_total", "kind=" .. clean(key) .. "|count=" .. count)
    end
    if state.utility and state.utility.say == state.sayWrapper then state.utility.say = state.say end
    if state.dialogue and state.dialogue.emitResolved == state.emitWrapper then
        state.dialogue.emitResolved = state.emitResolved
    end
    if state.floor and state.floor.update == state.floorWrapper then state.floor.update = state.floorUpdate end
    state = nil
end

return Audit
