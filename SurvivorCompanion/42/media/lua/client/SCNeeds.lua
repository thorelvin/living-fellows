-- SPDX-License-Identifier: MIT

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
if not SC.GameplayUtil and type(require) == "function" then pcall(require, "SCGameplayUtil") end

SC.Needs = SC.Needs or {}
local Needs = SC.Needs
local states = setmetatable({}, { __mode = "k" })

local function U()
    return SC.GameplayUtil
end

local function worldHour()
    if type(getGameTime) ~= "function" then return nil end
    local ok, clock = pcall(getGameTime)
    if not ok or clock == nil then return nil end
    local hour, read = U().call(clock, "getWorldAgeHours")
    hour = read and tonumber(hour) or nil
    return hour and hour >= 0 and hour == hour and hour or nil
end

local function hygieneRecord(actor)
    local registry = SC.Registry
    local record = registry and type(registry.byId) == "function"
        and registry.byId(U().idOf(actor)) or nil
    if not record then return nil end
    record.state = record.state or {}
    record.state.downtime = record.state.downtime or {}
    return record.state.downtime
end

local function nextPeeInterval(actor, hour)
    local seed = tostring(U().idOf(actor) or actor) .. ":pee:"
        .. tostring(math.floor(hour or 0))
    return 6 + math.abs(tonumber(U().stableHash(seed)) or 0) % 5
end

local function peeSchedule(actor, hour)
    local record = hygieneRecord(actor)
    if not record or not hour then return nil end
    if type(record.nextPeeHour) ~= "number" then
        record.nextPeeHour = hour + nextPeeInterval(actor, hour)
    end
    return record.nextPeeHour, record
end

local function customName(object)
    local sprite = select(1, U().call(object, "getSprite"))
    local properties = select(1, U().call(sprite, "getProperties"))
    local value = select(1, U().call(properties, "get", "CustomName"))
    return type(value) == "string" and string.lower(value) or ""
end

local function toiletTarget(actor, standing)
    local x, y, z = U().position(actor)
    if not x then return nil end
    for radius = 0, 8 do
        for dx = -radius, radius do
            for dy = -radius, radius do
                if math.max(math.abs(dx), math.abs(dy)) == radius then
                    local square = U().gridSquare(x + dx, y + dy, z)
                    local found
                    U().squareObjects(square, function(object)
                        if customName(object) == "toilet" then
                            local targets = SC.Navigation and SC.Navigation.interactionTargets
                                and SC.Navigation.interactionTargets(actor, object,
                                    { requireDirectAccess = true })
                            if standing and type(targets) == "table" then
                                -- A standing actor must approach the bowl from its
                                -- front. A valid tile beside or behind the toilet
                                -- is not an acceptable standing position.
                                local facing = select(1, U().call(object, "getFacing"))
                                local direction = string.upper(tostring(facing or ""))
                                    :match("([NESW])$")
                                local offsets = {
                                    N = { 0, -1 }, E = { 1, 0 },
                                    S = { 0, 1 }, W = { -1, 0 },
                                }
                                local offset = offsets[direction]
                                local ox, oy = U().position(square)
                                local front = offset and U().gridSquare(ox + offset[1],
                                    oy + offset[2], z) or nil
                                local aligned = {}
                                for _, target in ipairs(targets) do
                                    if front and U().sameSquare(target, front) then
                                        aligned[1] = target
                                        break
                                    end
                                end
                                targets = aligned
                            end
                            if type(targets) == "table" and #targets > 0 then
                                found = { object = object, targets = targets }
                                return false
                            end
                        end
                    end, 48)
                    if found then return found end
                end
            end
        end
    end
end

local function personality(actor)
    local record = SC.Registry and type(SC.Registry.byId) == "function"
        and SC.Registry.byId(U().idOf(actor)) or nil
    local state = record and record.state
    return state and state.personality and state.personality.profile or {}
end

local function peeStyle(actor, hour)
    local profile = personality(actor)
    local archetype = profile.archetype or "practical"
    local identity = tostring(U().idOf(actor) or actor)
    local preference = math.abs(tonumber(U().stableHash(identity .. ":toilet_style")) or 0) % 100
    local seatChance = ({ cautious = 62, caring = 38, practical = 22, brave = 12 })[archetype] or 28
    local sits = select(1, U().call(actor, "isFemale")) == true
        or preference < seatChance
    local roll = math.abs(tonumber(U().stableHash(identity .. ":pee_pose:"
        .. tostring(math.floor(hour or 0)))) or 0) % 100
    local style
    if archetype == "cautious" then
        style = roll < 70 and "pee_stand" or "pee_hip"
    elseif archetype == "brave" then
        style = roll < 7 and "pee_free" or roll < 72 and "pee_hip" or "pee_stand"
    else
        style = roll < 52 and "pee_stand" or "pee_hip"
    end
    return sits, style
end

local function outdoorTarget(actor, player, overdue)
    local x, y, z = U().position(actor)
    if not x then return nil end
    local currentSquare = U().squareOf(actor)
    local room = currentSquare and select(1, U().call(currentSquare, "getRoom"))
    local playerDistance = player and U().distance(player, actor) or 6
    local alone = true
    U().squareMovingObjects(currentSquare, function(other)
        if other ~= actor then alone = false return false end
    end, 12)
    -- A companion already alone outdoors and a few steps from the group has
    -- found a safe enough break spot. Avoid an artificial detour for privacy.
    if currentSquare and room == nil and alone
        and (tonumber(playerDistance) or 0) >= 3 then return currentSquare end
    local best, bestScore
    for dx = -4, 4 do
        for dy = -4, 4 do
            local distance = math.max(math.abs(dx), math.abs(dy))
            if distance >= 2 or overdue then
                local square = U().gridSquare(x + dx, y + dy, z)
                local room = square and select(1, U().call(square, "getRoom"))
                local objects = square and select(1, U().call(square, "getMovingObjects"))
                local occupied = objects and select(1, U().call(objects, "size")) or 0
                if square and room == nil and U().isSquareFree(square)
                    and (tonumber(occupied) or 0) == 0 then
                    local playerDistance = player and U().distance(player, square) or 6
                    local hidden = player and not U().canSee(player, square)
                    local score = (hidden and 12 or 0)
                        + math.min(6, tonumber(playerDistance) or 0)
                        - distance * 2
                    if not bestScore or score > bestScore then
                        best, bestScore = square, score
                    end
                end
            end
        end
    end
    return best
end

local function sayPee(actor, topic)
    if SC.Dialogue and type(SC.Dialogue.say) == "function" then
        pcall(SC.Dialogue.say, actor, topic)
    end
end

local function peeAction(actor, task)
    local female = select(1, U().call(actor, "isFemale")) == true
    return female and "pee_squat" or task.style or "pee_stand"
end

-- Audio handles belong to this session, never to a saved companion record.
local peeSoundHandles = setmetatable({}, { __mode = "k" })

local function startPeeSound(actor)
    if peeSoundHandles[actor] ~= nil then return end
    local handle, played = U().call(actor, "playSound", "LFUrinate")
    if played and handle ~= nil and handle ~= 0 then
        peeSoundHandles[actor] = handle
    end
end

local function stopPeeSound(actor)
    local handle = peeSoundHandles[actor]
    if handle == nil then return end
    peeSoundHandles[actor] = nil
    U().call(actor, "stopOrTriggerSound", handle)
end

local function peeStartTopic(actor, task, hour)
    if task.toilet then return "hygiene.pee_toilet" end
    local square = task.square
    local context
    for dx = -1, 1 do
        for dy = -1, 1 do
            local x, y, z = U().position(square)
            local near = x and U().gridSquare(x + dx, y + dy, z) or nil
            U().squareObjects(near, function(object)
                local name = customName(object)
                if string.find(name, "gnome", 1, true) then context = "gnome" end
                if string.find(name, "hydrant", 1, true) then context = "hydrant" end
            end, 32)
            local bodies = near and select(1, U().call(near, "getDeadBodys"))
            local count = bodies and select(1, U().call(bodies, "size"))
            if (tonumber(count) or 0) > 0 then context = "corpse" end
        end
    end
    local seed = tostring(U().idOf(actor) or actor) .. ":pee_context:"
        .. tostring(math.floor(hour or 0))
    local roll = math.abs(tonumber(U().stableHash(seed)) or 0)
    if roll % 12 == 0 and select(1, U().call(actor, "isFemale")) ~= true then
        return "hygiene.pee_dirty"
    end
    if context and roll % 8 == 0 then
        local topics = {
            gnome = "hygiene.pee_gnome",
            hydrant = "hygiene.pee_hydrant",
            corpse = "hygiene.pee_corpse",
        }
        return topics[context]
    end
    return roll % 3 == 0 and "hygiene.pee_start" or "hygiene.pee_outdoor"
end

local function maybePeeReaction(actor, hour)
    if not SC.Registry or type(SC.Registry.records) ~= "function" then return end
    local seed = tostring(U().idOf(actor) or actor) .. ":pee_reaction:"
        .. tostring(math.floor(hour or 0))
    if math.abs(tonumber(U().stableHash(seed)) or 0) % 4 ~= 0 then return end
    for _, record in ipairs(SC.Registry.records()) do
        local other = record.actor
        if other and other ~= actor and U().isValidActor(other)
            and U().sameFloor(other, actor) and U().distance(other, actor) <= 5 then
            local name = tostring(U().nameOf(actor) or "friend")
            name = string.match(name, "^(%S+)") or "friend"
            local topic = select(1, U().call(actor, "isFemale")) ~= true
                and math.abs(tonumber(U().stableHash(seed .. ":tease")) or 0)
                    % 5 == 0 and "hygiene.pee_reaction_dirty"
                or "hygiene.pee_reaction"
            if SC.Dialogue and type(SC.Dialogue.say) == "function" then
                pcall(SC.Dialogue.say, other, topic, nil, { name })
            end
            return
        end
    end
end

local function updatePee(actor, player, state, hour, due)
    local current = U().nowMs()
    local task = state.pee
    if task and task.phase == "seating" then
        local status = SC.NativeActions and SC.NativeActions.furnitureStatus(actor) or "none"
        local seated = select(1, U().call(actor, "isSittingOnFurniture")) == true
        if status == "entered" and seated then
            task.phase, task.seatedAt = "seated", current
            startPeeSound(actor)
            return true, "bathroom_break_seated"
        end
        if status == "failed" or status == "none"
            or current - (task.seatingAt or current) > 12000 then
            Needs.cancel(actor, "toilet_seat_failed")
            state.nextPeeRetryAt = current + 30000
            return false, "toilet_seat_failed"
        end
        return true, "taking_toilet_seat"
    end
    if task and task.phase == "seated" then
        if select(1, U().call(actor, "isSittingOnFurniture")) ~= true then
            Needs.cancel(actor, "toilet_seat_lost")
            return false, "toilet_seat_lost"
        end
        if current - task.seatedAt < 6000 then return true, "bathroom_break_seated" end
        task.phase = "standing"
    end
    if task and task.phase == "standing" then
        stopPeeSound(actor)
        local stood, reason = SC.NativeActions.leaveFurniture(actor)
        if not stood then return true, reason or "leaving_toilet" end
        local record = hygieneRecord(actor)
        if record then record.nextPeeHour = hour + nextPeeInterval(actor, hour) end
        state.pee = nil
        sayPee(actor, "hygiene.pee_done")
        return true, "bathroom_break_finished"
    end
    if task and task.phase == "animating" then
        local status = SC.NativeActions and SC.NativeActions.visualStatus(actor,
            peeAction(actor, task)) or "none"
        if status == "active" then return true, "bathroom_break" end
        if status == "completed" then
            stopPeeSound(actor)
            SC.NativeActions.clearVisual(actor)
            local record = hygieneRecord(actor)
            if record then record.nextPeeHour = hour + nextPeeInterval(actor, hour) end
            state.pee = nil
            sayPee(actor, "hygiene.pee_done")
            return true, "bathroom_break_finished"
        end
        stopPeeSound(actor)
        if SC.NativeActions then SC.NativeActions.cancelVisual(actor, "pee_interrupted") end
        state.pee = nil
        state.nextPeeRetryAt = current + 30000
        return false, "bathroom_break_interrupted"
    end
    if current < (state.nextPeeRetryAt or 0) then return false, "bathroom_retry" end
    -- The Base Watch leader holds the camp's second view and must stay
    -- indoors: four seconds outside hands the watch to someone else. It never
    -- takes the outdoor fallback, and without a usable toilet it skips this
    -- break and waits for the next one.
    local indoorsOnly = SC.BaseWatch and type(SC.BaseWatch.isLeader) == "function"
        and SC.BaseWatch.isLeader(actor) == true
    local function giveUp(reason)
        -- Needs.cancel also stops eating and drinking; only a break already
        -- under way has anything of its own to cancel.
        if state.pee then Needs.cancel(actor, reason) end
        if indoorsOnly then
            local record = hygieneRecord(actor)
            if record then record.nextPeeHour = hour + nextPeeInterval(actor, hour) end
            return false, "bathroom_watcher_stays_indoors"
        end
        state.nextPeeRetryAt = current + 30000
        return false, "bathroom_spot_unavailable"
    end
    if not task then
        local inBase = SC.BaseLife and SC.BaseLife.isInside(actor) == true
        local insideRoom = select(1, U().call(U().squareOf(actor), "getRoom")) ~= nil
        local sits, style = peeStyle(actor, hour)
        local toilet = inBase and insideRoom and toiletTarget(actor, not sits) or nil
        local spot = toilet == nil and not indoorsOnly
            and outdoorTarget(actor, player, hour - due >= 2) or nil
        if not toilet and not spot then return giveUp("bathroom_spot_unavailable") end
        local x, y = U().position(actor)
        task = { toilet = toilet, square = spot, startedAt = current,
            sits = sits, style = style,
            lastX = x, lastY = y, lastProgressAt = current }
        state.pee = task
        sayPee(actor, peeStartTopic(actor, task, hour))
        maybePeeReaction(actor, hour)
    end
    if current - task.startedAt > 45000 then
        Needs.cancel(actor, "bathroom_route_timeout")
        state.nextPeeRetryAt = current + 30000
        return false, "bathroom_route_timeout"
    end
    local x, y = U().position(actor)
    if x and task.lastX and (x - task.lastX)^2 + (y - task.lastY)^2 > 0.16 then
        task.lastX, task.lastY, task.lastProgressAt = x, y, current
    elseif current - (task.lastProgressAt or current) > 6000 then
        if task.toilet then
            task.toilet = nil
            task.square = not indoorsOnly and outdoorTarget(actor, player, true) or nil
            task.startedAt = current
            task.lastProgressAt = current
            if SC.Navigation then SC.Navigation.cancel(actor, "toilet_route_stalled") end
            if not task.square then return giveUp("bathroom_route_stalled") end
        else
            Needs.cancel(actor, "bathroom_route_stalled")
            state.nextPeeRetryAt = current + 30000
            return false, "bathroom_route_stalled"
        end
    end
    local arrived, status
    if task.toilet then
        arrived = task.sits
            and U().directInteractionAccess(actor, task.toilet.object) == true
            or not task.sits and U().sameSquare(actor, task.toilet.targets[1])
        if not arrived and SC.Navigation then
            local accepted
            accepted, status = SC.Navigation.requestAny(actor, task.toilet.targets,
                "walk", { action = "move_to_water_source",
                    object = task.toilet.object,
                    arrivalDistance = task.sits and 0.6 or 0.15,
                    requireSameSquare = not task.sits })
            if not accepted then status = nil end
        end
    else
        arrived = U().sameSquare(actor, task.square)
        if not arrived and SC.Navigation then
            local accepted
            accepted, status = SC.Navigation.request(actor, task.square, "walk",
                { action = "move_to_water_source", arrivalDistance = 0.5 })
            if not accepted then status = nil end
        end
    end
    if arrived ~= true then
        if task.toilet and status == "arrived" and task.sits then
            task.toilet = nil
            task.square = not indoorsOnly and outdoorTarget(actor, player, true) or nil
            task.startedAt = current
            task.lastProgressAt = current
            if task.square then return true, "bathroom_spot_changed" end
            return giveUp("toilet_seat_unreachable")
        end
        if status == nil then
            Needs.cancel(actor, "bathroom_route_failed")
            state.nextPeeRetryAt = current + 30000
            return false, "bathroom_route_failed"
        end
        return true, "approaching_bathroom_spot"
    end
    if task.toilet and task.sits then
        local accepted, reason = U().move(actor, "walk", {
            action = "sit", object = task.toilet.object,
        })
        if not accepted then
            Needs.cancel(actor, "toilet_seat_rejected")
            state.nextPeeRetryAt = current + 30000
            return false, reason or "toilet_seat_rejected"
        end
        task.phase, task.seatingAt = "seating", current
        return true, "taking_toilet_seat"
    end
    local action = peeAction(actor, task)
    local accepted, reason = U().move(actor, "walk", {
        action = action, object = task.toilet and task.toilet.object or nil,
        durationMs = 6000,
    })
    if not accepted then
        Needs.cancel(actor, "bathroom_animation_rejected")
        state.nextPeeRetryAt = current + 30000
        return false, reason or "bathroom_animation_rejected"
    end
    task.phase = "animating"
    -- Make the effect UI available when the action starts; the render-tick
    -- hook also retries if the interface is still initializing.
    if SC.HygieneEffects and type(SC.HygieneEffects.ensureOverlay) == "function" then
        pcall(SC.HygieneEffects.ensureOverlay)
    end
    startPeeSound(actor)
    return true, "bathroom_break"
end

local function stateFor(actor, runtime)
    local root = U().actorState(actor, runtime)
    root.needs = root.needs or {}
    states[actor] = root.needs
    return root.needs
end

local NEED_ORDER = { "thirst", "hunger", "fatigue" }
local SEVERITY_NAME = { "noted", "serious", "urgent" }

local function thresholds(kind)
    if kind == "hunger" then
        return U().config("needsHungerThreshold") or 0.55,
            U().config("needsHungerSerious") or 0.70,
            U().config("needsHungerEmergency") or 0.82
    end
    if kind == "thirst" then
        return U().config("needsThirstThreshold") or 0.48,
            U().config("needsThirstSerious") or 0.62,
            U().config("needsThirstEmergency") or 0.75
    end
    return U().config("needsFatigueThreshold") or 0.50,
        U().config("needsFatigueSerious") or 0.68,
        U().config("needsFatigueEmergency") or 0.82
end

local function severity(kind, value)
    local noted, serious, urgent = thresholds(kind)
    value = tonumber(value) or 0
    if value >= urgent then return 3 end
    if value >= serious then return 2 end
    if value >= noted then return 1 end
    return 0
end

local function unsafeForSpeech(runtime)
    local root = type(runtime) == "table" and runtime or {}
    local snapshot = type(root.senses) == "table" and root.senses.current or root.snapshot
    snapshot = type(snapshot) == "table" and snapshot or {}
    return (tonumber(snapshot.immediateCount) or 0) > 0
        or (tonumber(snapshot.pressure) or 0) >= 1.5
end

-- Needs narration is a state observer only. It never changes the native stat,
-- the action choice, or the relationship stress domain.
function Needs.narrate(actor, runtime, current, supplied)
    if actor == nil then return false, "needs_speech_invalid_actor" end
    local state = stateFor(actor, runtime)
    state.speech = type(state.speech) == "table" and state.speech
        or { levels = {}, pending = {}, lastAt = -math.huge }
    local speech = state.speech
    speech.levels = type(speech.levels) == "table" and speech.levels or {}
    speech.pending = type(speech.pending) == "table" and speech.pending or {}
    supplied = type(supplied) == "table" and supplied or {}
    local values = {
        hunger = supplied.hunger ~= nil and supplied.hunger
            or U().characterStatValue(actor, "HUNGER", state.hunger or 0),
        thirst = supplied.thirst ~= nil and supplied.thirst
            or U().characterStatValue(actor, "THIRST", state.thirst or 0),
        fatigue = supplied.fatigue ~= nil and supplied.fatigue
            or U().characterStatValue(actor, "FATIGUE", state.fatigue or 0),
    }
    for _, kind in ipairs(NEED_ORDER) do
        local level = severity(kind, values[kind])
        local previous = speech.levels[kind]
        if previous == nil then
            speech.levels[kind] = level
        else
            if level > previous and level > 0 then
                speech.pending[kind] = math.max(level,
                    tonumber(speech.pending[kind]) or 0)
            elseif level < previous then
                speech.pending[kind] = nil
            end
            speech.levels[kind] = level
        end
    end
    if unsafeForSpeech(runtime) then return false, "needs_speech_unsafe" end
    if not SC.Dialogue or type(SC.Dialogue.say) ~= "function" then
        return false, "needs_speech_dialogue_unavailable"
    end
    current = tonumber(current) or U().nowMs()
    if current - (tonumber(speech.lastAt) or -math.huge)
        < (U().config("needsSpeechActorCooldownMs") or 120000) then
        return false, "needs_speech_cooldown"
    end
    if type(SC.Dialogue.lastSpokenAt) == "function"
        and current - SC.Dialogue.lastSpokenAt(actor)
            < (U().config("needsSpeechQuietMs") or 15000) then
        return false, "needs_speech_quiet"
    end
    local selectedKind, selectedLevel
    for _, kind in ipairs(NEED_ORDER) do
        local pending = tonumber(speech.pending[kind]) or 0
        if pending > 0 and (selectedLevel == nil or pending > selectedLevel) then
            selectedKind, selectedLevel = kind, pending
        end
    end
    if not selectedKind then return false, "needs_speech_no_transition" end
    local topic = "need." .. selectedKind .. "." .. SEVERITY_NAME[selectedLevel]
    local spoken, line = SC.Dialogue.say(actor, topic, nil, nil, {
        recentLimit = 4,
        salt = tostring(current) .. ":" .. selectedKind .. ":" .. tostring(selectedLevel),
    })
    if spoken == true then
        speech.pending[selectedKind] = nil
        speech.lastAt = current
        return true, topic, line
    end
    return false, line or "needs_speech_rejected"
end

local function enumValue(name)
    if CharacterStat == nil then return nil end
    local ok, value = pcall(function() return CharacterStat[name] end)
    return ok and value or nil
end

local function setStat(actor, name, value)
    local stats, statsOk = U().call(actor, "getStats")
    local stat = enumValue(name)
    if not statsOk or not stats or stat == nil then return false end
    value = U().clamp(tonumber(value) or 0, 0, 1)
    local result, called = U().call(stats, "set", stat, value)
    if not called or result == false then return false end
    local after, afterOk = U().call(stats, "get", stat)
    return afterOk and type(after) == "number" and math.abs(after - value) <= 0.001
end

local function compensatePositiveDelta(actor, state, field, statName, currentValue)
    local previous = state[field]
    if type(previous) ~= "number" then
        state[field] = currentValue
        return currentValue
    end
    local delta = currentValue - previous
    local limit = U().config("needsNaturalDeltaLimit") or 1.0
    if delta > 0 and delta <= limit then
        local multiplier = U().clamp(U().config("needsRateMultiplier") or 0.5, 0, 1)
        local adjusted = previous + delta * multiplier
        if setStat(actor, statName, adjusted) then currentValue = adjusted end
    end
    -- Negative deltas are native food/drink effects and remain fully applied.
    state[field] = currentValue
    return currentValue
end

function Needs.updateRates(actor, runtime, current)
    if not actor then return false, "invalid_actor" end
    local state = stateFor(actor, runtime)
    current = current or U().nowMs()
    local sampleMs = U().config("needsRateSampleMs") or 1000
    if current < (state.nextRateSampleAt or 0) then return true, "needs_rate_deferred" end
    state.nextRateSampleAt = current + sampleMs
    local hunger = U().characterStatValue(actor, "HUNGER", 0)
    local thirst = U().characterStatValue(actor, "THIRST", 0)
    local fatigue = U().characterStatValue(actor, "FATIGUE", 0)
    hunger = compensatePositiveDelta(actor, state, "sampledHunger", "HUNGER", hunger)
    thirst = compensatePositiveDelta(actor, state, "sampledThirst", "THIRST", thirst)
    state.hunger, state.thirst, state.fatigue = hunger, thirst, fatigue
    Needs.narrate(actor, runtime, current, {
        hunger = hunger, thirst = thirst, fatigue = fatigue,
    })
    return true, "needs_rate_updated"
end

function Needs.assess(actor, runtime)
    local state = stateFor(actor, runtime)
    local active = false
    local actionFinished = false
    if SC.NativeActions and type(SC.NativeActions.needsStatus) == "function" then
        local ok, value, kind = pcall(SC.NativeActions.needsStatus, actor)
        active = ok and value == true
        if ok and value ~= true and kind ~= nil
            and type(SC.NativeActions.finishNeeds) == "function" then
            pcall(SC.NativeActions.finishNeeds, actor)
            actionFinished = true
        end
    end
    if actionFinished then state.nextRateSampleAt = 0 end
    local sampled = not actionFinished and state.nextRateSampleAt ~= nil
        and type(state.hunger) == "number" and type(state.thirst) == "number"
        and type(state.fatigue) == "number"
    local hunger, thirst, fatigue
    if sampled then
        hunger, thirst, fatigue = state.hunger, state.thirst, state.fatigue
    else
        hunger = U().characterStatValue(actor, "HUNGER", state.hunger or 0)
        thirst = U().characterStatValue(actor, "THIRST", state.thirst or 0)
        fatigue = U().characterStatValue(actor, "FATIGUE", state.fatigue or 0)
        state.hunger, state.thirst, state.fatigue = hunger, thirst, fatigue
    end
    local hour = worldHour()
    local peeDueAt = peeSchedule(actor, hour)
    local inVehicle = select(1, U().call(actor, "getVehicle")) ~= nil
    return {
        hunger = hunger,
        thirst = thirst,
        fatigue = fatigue,
        hungry = hunger >= (U().config("needsHungerThreshold") or 0.55),
        thirsty = thirst >= (U().config("needsThirstThreshold") or 0.48),
        emergency = hunger >= (U().config("needsHungerEmergency") or 0.82)
            or thirst >= (U().config("needsThirstEmergency") or 0.75),
        exhausted = fatigue >= (U().config("needsFatigueEmergency") or 0.82),
        active = active or state.pee ~= nil,
        peeDue = hour ~= nil and peeDueAt ~= nil and hour >= peeDueAt
            and not inVehicle,
        peeOverdue = hour ~= nil and peeDueAt ~= nil and hour >= peeDueAt + 2,
    }
end

local function walkInventory(container, limit, callback, visited)
    if not container or limit.remaining <= 0 then return end
    visited = visited or setmetatable({}, { __mode = "k" })
    if visited[container] then return end
    visited[container] = true
    local items, itemsOk = U().call(container, "getItems")
    if not itemsOk and type(container) == "table" then items = container.items or container end
    U().each(items, limit.remaining, function(item)
        limit.remaining = limit.remaining - 1
        if callback(item) == false or limit.remaining <= 0 then return false end
        local nested, nestedOk = U().call(item, "getInventory")
        if nestedOk and nested then walkInventory(nested, limit, callback, visited) end
        return limit.remaining > 0
    end)
end

local function unsafeFood(item)
    local rotten, rottenOk = U().call(item, "isRotten")
    local burnt, burntOk = U().call(item, "isBurnt")
    local dangerous, dangerousOk = U().call(item, "isbDangerousUncooked")
    local cooked, cookedOk = U().call(item, "isCooked")
    local poison, poisonOk = U().call(item, "getPoisonPower")
    local script, scriptOk = U().call(item, "getScriptItem")
    local cantEat, cantEatOk = U().call(script, "isCantEat")
    if rottenOk and rotten then return true end
    if burntOk and burnt then return true end
    if dangerousOk and dangerous and (not cookedOk or cooked ~= true) then return true end
    if poisonOk and tonumber(poison) and tonumber(poison) > 0 then return true end
    if scriptOk and script and cantEatOk and cantEat then return true end
    return false
end

local function isSafeFood(item)
    if not U().instanceOf(item, "Food") and not U().hasMethod(item, "getHungerChange") then
        return false
    end
    local change, changeOk = U().call(item, "getHungerChange")
    return changeOk and type(change) == "number" and change < -0.001 and not unsafeFood(item)
end

local function fluidConstant(name)
    if Fluid == nil then return nil end
    local ok, value = pcall(function() return Fluid[name] end)
    return ok and value or nil
end

local function isSafeWaterItem(item)
    local fluid, fluidOk = U().call(item, "getFluidContainer")
    if not fluidOk or not fluid then return false end
    local empty, emptyOk = U().call(fluid, "isEmpty")
    if emptyOk and empty then return false end
    local canEmpty, canEmptyOk = U().call(fluid, "canPlayerEmpty")
    if canEmptyOk and canEmpty ~= true then return false end
    local capacity, capacityOk = U().call(fluid, "getCapacity")
    if capacityOk and tonumber(capacity) and tonumber(capacity) > 3 then return false end
    local poisonous, poisonousOk = U().call(fluid, "isPoisonous")
    local taintedStatus, taintedStatusOk = U().call(fluid, "isTainted")
    if poisonousOk and poisonous then return false end
    if taintedStatusOk and taintedStatus then return false end
    local tainted = fluidConstant("TaintedWater")
    local water = fluidConstant("Water")
    if tainted then
        local contains, containsOk = U().call(fluid, "contains", tainted)
        if containsOk and contains then return false end
    end
    local clean, cleanOk = U().call(fluid, "isFilledWithCleanWater")
    if cleanOk then return clean == true end
    local waterOnly, waterOnlyOk = U().call(fluid, "isWaterOnlySource")
    if waterOnlyOk then return waterOnly == true end
    if water then
        local contains, containsOk = U().call(fluid, "contains", water)
        if containsOk then return contains == true end
    end
    local source, sourceOk = U().call(item, "isWaterSource")
    return sourceOk and source == true
end

local function firstInventoryItem(actor, predicate)
    local best, bestScore
    walkInventory(U().inventory(actor), { remaining = 256 }, function(item)
        local ok, accepted = pcall(predicate, item)
        if ok and accepted then
            local score = 1
            if isSafeFood(item) then
                local change, changeOk = U().call(item, "getHungerChange")
                score = changeOk and math.abs(tonumber(change) or 0) or 0
            else
                local fluid, fluidOk = U().call(item, "getFluidContainer")
                local amount, amountOk
                if fluidOk and fluid then amount, amountOk = U().call(fluid, "getAmount") end
                score = amountOk and tonumber(amount) or 0
            end
            if not bestScore or score > bestScore then best, bestScore = item, score end
        end
        return true
    end)
    return best
end

local function nativeNeedsActive(actor, state)
    if not SC.NativeActions or type(SC.NativeActions.needsStatus) ~= "function" then return false end
    local active, kind = SC.NativeActions.needsStatus(actor)
    if active then return true, kind end
    if type(SC.NativeActions.finishNeeds) == "function" then
        SC.NativeActions.finishNeeds(actor)
        if kind ~= nil and state then state.nextRateSampleAt = 0 end
    end
    return false
end

local function eat(actor, item, hunger)
    local change, changeOk = U().call(item, "getHungerChange")
    local reduction = changeOk and math.abs(tonumber(change) or 0) or 0
    if reduction <= 0 then return false, "food_has_no_hunger_reduction" end
    local desired = math.max(0.1, hunger - 0.25)
    local percentage = U().clamp(desired / reduction, 0.25, 1)
    return U().move(actor, "walk", {
        action = "eat_food",
        item = item,
        percentage = percentage,
        transactional = true,
    })
end

local function drinkItem(actor, item, thirst)
    local fluid, fluidOk = U().call(item, "getFluidContainer")
    local amount, amountOk
    if fluidOk and fluid then amount, amountOk = U().call(fluid, "getAmount") end
    local availableUses = amountOk and math.max(1, math.floor((tonumber(amount) or 0) / 0.12)) or 1
    local uses = math.min(availableUses, math.max(1, math.ceil(thirst * 10)))
    return U().move(actor, "walk", {
        action = "drink_item",
        item = item,
        uses = uses,
        transactional = true,
    })
end

local function validWaterSource(object)
    if not U().squareOf(object) then return false end
    local has, hasOk = U().call(object, "hasFluid")
    local amount, amountOk = U().call(object, "getFluidAmount")
    local tainted, taintedOk = U().call(object, "isTaintedWater")
    return hasOk and has == true and amountOk
        and (amount ~= nil and tonumber(tostring(amount)) or 0) > 0.05
        and (not taintedOk or tainted ~= true)
end

local function campFloorRoute(actor, destination)
    return SC.BaseLife and type(SC.BaseLife.allowsFloorTransit) == "function"
        and SC.BaseLife.allowsFloorTransit(actor, destination,
            { workCampOnly = true }) == true
end

local function findWaterSource(actor, state)
    local utility = U()
    local ax, ay, az = utility.position(actor)
    if not ax then return nil end
    local radius = math.max(1, math.min(18,
        math.floor(utility.config("needsWaterSourceRadius") or 12)))
    local budget = math.max(1, math.floor(utility.config("needsWaterSquareBudget") or 180))
    state.waterScanPhase = ((state.waterScanPhase or 0) + 1) % 4
    local currentFloor = math.floor(az)
    local current = utility.nowMs()
    local function scanFloor(floor, limit, crossFloor)
        local scanned = 0
        for distance = 0, radius do
            local found
            for dx = -distance, distance do
                for dy = -distance, distance do
                    if scanned >= limit then return nil end
                    local edge = math.max(math.abs(dx), math.abs(dy)) == distance
                    local sampled = distance <= 5
                        or ((dx * 17 + dy * 31) % 4) == state.waterScanPhase
                    if edge and sampled then
                        local square = utility.gridSquare(ax + dx, ay + dy, floor)
                        if square then
                            scanned = scanned + 1
                            utility.squareObjects(square, function(object)
                                local retryAt = state.waterRetryAt
                                    and state.waterRetryAt[object] or nil
                                if (not retryAt or current >= retryAt)
                                    and validWaterSource(object)
                                    and (not crossFloor
                                        or campFloorRoute(actor, square)) then
                                    found = object
                                    return false
                                end
                            end, 48)
                        end
                    end
                    if found then return found end
                end
            end
        end
        return nil
    end
    local source = scanFloor(currentFloor, budget, false)
    if source then return source end
    local base = SC.BaseLife and type(SC.BaseLife.active) == "function"
        and SC.BaseLife.active() or nil
    if not base or SC.BaseLife.isInside(actor) ~= true then return nil end
    local campFloors = {}
    for _, zone in ipairs(base.zones or {}) do
        if zone.kind == "area" and math.abs(zone.z - currentFloor) == 1 then
            campFloors[zone.z] = true
        end
    end
    for _, floor in ipairs({ currentFloor + 1, currentFloor - 1 }) do
        if campFloors[floor] then
            source = scanFloor(floor, math.max(60, math.floor(budget / 2)), true)
            if source then return source end
        end
    end
    return nil
end

local function drinkWorldSource(actor, source, snapshot, state)
    local _, _, actorZ = U().position(actor)
    local _, _, sourceZ = U().position(source)
    local crossFloor = actorZ ~= nil and sourceZ ~= nil
        and math.floor(actorZ) ~= math.floor(sourceZ)
    if crossFloor and not campFloorRoute(state.waterOriginSquare or actor, source) then
        return false, "water_source_floor_unreachable"
    end
    local atSource, targets, accessReason = U().directInteractionAccess(actor,
        source, { snapshot = snapshot })
    if not atSource then
        if accessReason == "no_interaction_targets" then
            return false, accessReason
        end
        if not SC.Navigation or type(SC.Navigation.requestAny) ~= "function" then
            return false, "water_source_navigation_unavailable"
        end
        return SC.Navigation.requestAny(actor, targets, "walk", {
            action = "move_to_water_source",
            object = source,
            snapshot = snapshot,
            arrivalDistance = 0.35,
            requireSameSquare = true,
            continuousApproach = true,
            workCampOnly = crossFloor,
        })
    end
    state.waterSource, state.waterOriginSquare = nil, nil
    return U().move(actor, "walk", {
        action = "drink_source",
        object = source,
        transactional = true,
    })
end

local function fetchFromCamp(actor, key, predicate, snapshot)
    if not SC.Encounter or type(SC.Encounter.takePlayerSupply) ~= "function" then
        return false, "camp_storage_unavailable"
    end
    local status, reason = SC.Encounter.takePlayerSupply(actor, key, predicate, {
        origin = actor,
        snapshot = snapshot,
        moveMode = "walk",
    })
    return status == "taken" or status == "in_progress", reason or status
end

function Needs.update(actor, player, runtime)
    if not U().isValidActor(actor) then return false, "invalid_actor" end
    local state = stateFor(actor, runtime)
    local hour = worldHour()
    local peeDueAt = peeSchedule(actor, hour)
    local root = U().actorState(actor, runtime)
    local snapshot = root.senses and root.senses.current or root.snapshot or {}
    if state.pee then
        if (snapshot.immediateCount or 0) > 0
            or (snapshot.pressure or 0) >= 1.5
            or select(1, U().call(actor, "getVehicle")) ~= nil then
            Needs.cancel(actor, "bathroom_break_unsafe")
            return false, "needs_unsafe"
        end
        if hour then return updatePee(actor, player, state, hour, peeDueAt or hour) end
        Needs.cancel(actor, "bathroom_clock_unavailable")
        return false, "bathroom_clock_unavailable"
    end
    local active, kind = nativeNeedsActive(actor, state)
    if active then return true, kind == "eat" and "eating" or "drinking" end
    if (snapshot.immediateCount or 0) > 0 or (snapshot.pressure or 0) >= 1.5 then
        return false, "needs_unsafe"
    end
    local assessment = Needs.assess(actor, runtime)
    local function consumable(predicate)
        return function(item)
            if SC.PersonalItems and SC.PersonalItems.isProtected(
                item, actor, "needs_consume") then return false end
            return predicate(item)
        end
    end

    -- Thirst comes first, but no water must never stop a companion eating.
    -- Returning here left one that was thirsty and hungry starving beside its
    -- own food whenever no clean water (or no reachable sink) was in range.
    local thirstReason
    if assessment.thirsty then
        local safeWater = consumable(isSafeWaterItem)
        local water = firstInventoryItem(actor, safeWater)
        -- At camp a nearby tap or well saves carried drinking water. A bottle
        -- remains the immediate choice when the source is farther away.
        local source = state.waterSource
        if source and not validWaterSource(source) then
            source, state.waterSource, state.waterOriginSquare = nil, nil, nil
        end
        local current = U().nowMs()
        if not source and current >= (state.nextWaterSearchAt or 0) then
            source = findWaterSource(actor, state)
            state.waterSource = source
            state.waterOriginSquare = source and U().squareOf(actor) or nil
            state.nextWaterSearchAt = current + 3000
        end
        local nearbyCampSource = source and SC.BaseLife
            and SC.BaseLife.isInside(actor) == true
            and U().sameFloor(actor, source)
            and U().distance(actor, source) <= 6
        if water and not nearbyCampSource then
            return drinkItem(actor, water, assessment.thirst)
        end
        if source then
            local accepted, reason = drinkWorldSource(actor, source, snapshot, state)
            if accepted == true then return true, reason end
            thirstReason = reason or "water_source_unreachable"
            state.waterRetryAt = state.waterRetryAt or setmetatable({}, { __mode = "k" })
            state.waterRetryAt[source] = current + 15000
            state.waterSource, state.waterOriginSquare = nil, nil
            state.nextWaterSearchAt = 0
            if water then return drinkItem(actor, water, assessment.thirst) end
            local fetched, fetchReason = fetchFromCamp(actor,
                "needs_water", safeWater, snapshot)
            if fetched then return true, fetchReason end
        else
            local fetched, fetchReason = fetchFromCamp(actor, "needs_water", safeWater, snapshot)
            if fetched then return true, fetchReason end
            thirstReason = "clean_water_unavailable"
        end
    end

    if assessment.hungry then
        local safeFood = consumable(isSafeFood)
        local food = firstInventoryItem(actor, safeFood)
        if food then return eat(actor, food, assessment.hunger) end
        local fetched, fetchReason = fetchFromCamp(actor, "needs_food", safeFood, snapshot)
        if fetched then return true, fetchReason end
        return false, thirstReason or "safe_food_unavailable"
    end
    if hour and peeDueAt and hour >= peeDueAt
        and select(1, U().call(actor, "getVehicle")) == nil then
        return updatePee(actor, player, state, hour, peeDueAt)
    end
    return false, thirstReason or "needs_satisfied"
end

function Needs.cancel(actor, reason)
    if actor then stopPeeSound(actor) end
    local state = actor and states[actor]
    if state and state.pee then
        if (state.pee.phase == "seating" or state.pee.phase == "seated"
            or state.pee.phase == "standing") and SC.NativeActions
            and type(SC.NativeActions.leaveSeating) == "function" then
            SC.NativeActions.leaveSeating(actor)
        end
        if SC.NativeActions and type(SC.NativeActions.cancelVisual) == "function" then
            local cancelled, cancelReason = SC.NativeActions.cancelVisual(actor,
                reason or "bathroom_break_cancelled")
            if cancelled ~= true then return false, cancelReason end
        end
        if SC.Navigation and type(SC.Navigation.cancel) == "function" then
            pcall(SC.Navigation.cancel, actor, reason or "bathroom_break_cancelled")
        end
        state.pee = nil
    end
    if SC.Encounter and type(SC.Encounter.cancelPlayerSupply) == "function" then
        SC.Encounter.cancelPlayerSupply(actor)
    end
    if SC.NativeActions and type(SC.NativeActions.cancelNeeds) == "function" then
        return SC.NativeActions.cancelNeeds(actor, reason)
    end
    return true, reason or "needs_cancelled"
end

function Needs.peek(actor)
    return actor and states[actor] or nil
end

function Needs.reset(actor)
    if actor then
        Needs.cancel(actor, "needs_reset")
        states[actor] = nil
        local runtime = U().peekActorState(actor)
        if runtime then runtime.needs = nil end
    else
        for candidate in pairs(states) do Needs.cancel(candidate, "needs_reset") end
        states = setmetatable({}, { __mode = "k" })
    end
    return true
end

return Needs
