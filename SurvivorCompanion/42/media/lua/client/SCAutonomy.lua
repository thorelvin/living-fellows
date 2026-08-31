-- SPDX-License-Identifier: MIT

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
if not SC.GameplayUtil and type(require) == "function" then pcall(require, "SCGameplayUtil") end
if not SC.Dialogue and type(require) == "function" then pcall(require, "SCDialogue") end
if not SC.LifeEvents and type(require) == "function" then pcall(require, "SCLifeEvents") end
if not SC.Community and type(require) == "function" then pcall(require, "SCCommunity") end

SC.Autonomy = SC.Autonomy or {}
local Autonomy = SC.Autonomy
local states = setmetatable({}, { __mode = "k" })
local observations = setmetatable({}, { __mode = "k" })
local recentEvents = {}

local supplyChoices = { "soon", "come_with_me", "not_now", "cannot_spare" }
local glassTypes = {
    ["base.beerempty"] = true,
}

local function U() return SC.GameplayUtil end

local function finite(value, fallback)
    value = tonumber(value)
    if value == nil or value ~= value or value == math.huge or value == -math.huge then
        return fallback or 0
    end
    return value
end

local function clamp(value, low, high)
    value = finite(value, low)
    if value < low then return low end
    if value > high then return high end
    return value
end

local function simNow()
    return SC.LifeEvents and SC.LifeEvents.now and SC.LifeEvents.now() or U().nowMs()
end

local function hours(value) return math.floor(finite(value, 0) * 3600000) end
local function minutes(value) return math.floor(finite(value, 0) * 60000) end

local function runtimeState(actor)
    local state = states[actor]
    if not state then
        state = { episode = nil, purposeful = nil }
        states[actor] = state
    end
    return state
end

local function commandState(actor)
    if SC.Commands and type(SC.Commands.peek) == "function" then
        local ok, state = pcall(SC.Commands.peek, actor)
        if ok and type(state) == "table" then return state end
    end
    return { recruited = false, stress = 12, morale = 55, personalityProfile = {} }
end

local function recruitedActors()
    local result = {}
    for _, actor in ipairs(U().registryLiving(U().config("maxCompanions") or 8)) do
        local state = commandState(actor)
        if state.recruited == true and not U().isDead(actor) then result[#result + 1] = actor end
    end
    return result
end

local function threatCount(snapshot)
    return finite(type(snapshot) == "table" and (snapshot.threatCount or snapshot.immediateCount), 0)
end

local function inRoom(actor)
    local square = U().squareOf(actor)
    local room, ok = U().call(square, "getRoom")
    return ok and room ~= nil
end

local function atBase(actor)
    return SC.BaseLife and type(SC.BaseLife.active) == "function" and SC.BaseLife.active() ~= nil
        and type(SC.BaseLife.isInside) == "function" and SC.BaseLife.isInside(actor) == true
end

local function safeContext(actor, snapshot)
    if threatCount(snapshot) > 0 or U().nativeHealth(actor) < 70 then return false end
    return atBase(actor) or inRoom(actor)
end

local function nearbyParticipants(actor, radius)
    local result = { U().idOf(actor) }
    for _, other in ipairs(recruitedActors()) do
        if other ~= actor and U().sameFloor(actor, other) and U().distance(actor, other) <= radius then
            result[#result + 1] = U().idOf(other)
        end
    end
    return result
end

local function emit(kind, fields)
    if SC.LifeEvents and type(SC.LifeEvents.emit) == "function" then
        if kind == "shared_escape" and type(fields) == "table"
            and type(fields.participants) == "table" then
            local ids = {}
            for _, id in ipairs(fields.participants) do ids[#ids + 1] = tostring(id) end
            table.sort(ids)
            local key = kind .. ":" .. table.concat(ids, "|")
            local current = U().nowMs()
            if current - finite(recentEvents[key], -math.huge) < 3000 then return nil end
            recentEvents[key] = current
            local count, oldestKey, oldestAt = 0, nil, math.huge
            for candidateKey, at in pairs(recentEvents) do
                count = count + 1
                if finite(at, 0) < oldestAt then oldestKey, oldestAt = candidateKey, finite(at, 0) end
            end
            if count > 64 and oldestKey then recentEvents[oldestKey] = nil end
        end
        return SC.LifeEvents.emit(kind, fields)
    end
end

local function persist(actor)
    if SC.Commands and type(SC.Commands.persist) == "function" then
        pcall(SC.Commands.persist, actor)
    end
end

local function dialogueLine(actor, topic, arguments, fallback, options)
    options = type(options) == "table" and options or {}
    options.fallback = fallback
    options.state = options.state or commandState(actor)
    if SC.Dialogue and type(SC.Dialogue.choose) == "function" then
        local line = SC.Dialogue.choose(actor, topic, nil, arguments, options)
        if type(line) == "string" and line ~= "" then return line end
    end
    local result = tostring(fallback or "")
    for index, argument in ipairs(arguments or {}) do
        result = string.gsub(result, "%%" .. tostring(index), function() return tostring(argument) end)
    end
    return result
end

local function sayDialogue(actor, topic, arguments, fallback, options)
    return U().say(actor, dialogueLine(actor, topic, arguments, fallback, options))
end

local function closestCompanion(actor, maximumDistance, requireMemory)
    local id = U().idOf(actor)
    local best, bestScore
    for _, other in ipairs(recruitedActors()) do
        if other ~= actor and U().sameFloor(actor, other) then
            local distance = U().distance(actor, other)
            local relation = SC.Community.relation(id, U().idOf(other), false)
            local memory = SC.Community.latestSharedMemory(id, U().idOf(other))
            if distance <= maximumDistance and (not requireMemory or memory ~= nil) then
                local score = finite(relation and relation.tension, 0) * 2 - distance
                if bestScore == nil or score > bestScore then
                    best, bestScore = other, score
                end
            end
        end
    end
    return best
end

local function observeSharedEvents(actor, snapshot)
    local current = U().nowMs()
    local runtime = observations[actor]
    local health = U().nativeHealth(actor)
    local danger = threatCount(snapshot)
    if not runtime then
        observations[actor] = { health = health, danger = danger, sampledAt = current }
        return
    end
    if health < runtime.health - 5 then
        emit("witnessed_injury", {
            sourceId = U().idOf(actor), participants = nearbyParticipants(actor, 10),
            severity = runtime.health - health,
        })
    end
    if runtime.danger > 0 and danger == 0 then
        emit("shared_escape", {
            sourceId = U().idOf(actor), participants = nearbyParticipants(actor, 12),
        })
    end
    runtime.health, runtime.danger, runtime.sampledAt = health, danger, current
end

function Autonomy.observe(actor, player, rootRuntime, snapshot, state)
    if not actor or type(state) ~= "table" or state.recruited ~= true then return false end
    observeSharedEvents(actor, snapshot)
    local decision = type(rootRuntime) == "table" and rootRuntime.decision or nil
    local downtime = SC.Downtime and type(SC.Downtime.peek) == "function" and SC.Downtime.peek(actor) or nil
    local idle = threatCount(snapshot) == 0
        and (decision == nil or decision.current == nil or decision.current == "downtime"
            or decision.current == "idle")
        and not (type(downtime) == "table" and downtime.active ~= nil)
    local changed, reason = SC.Community.updateMind(actor, state, snapshot, { idle = idle })
    if changed then persist(actor) end
    return changed, reason
end

local function majorEligible(actor, state, snapshot)
    local mind = SC.Community.mindFor(actor, state)
    if not mind or not safeContext(actor, snapshot) then return false end
    local current = simNow()
    return state.stress >= (U().config("mindMajorStress") or 82)
        and mind.criticalSince > 0
        and current - mind.criticalSince >= minutes(U().config("mindCriticalGameMinutes") or 30)
        and current >= finite(mind.nextMajorAt, 0)
        and SC.Community.groupMajorReady(current)
end

local function griefEligible(actor, snapshot)
    if not safeContext(actor, snapshot) then return nil end
    local grief = SC.Community.activeGrief(actor)
    if grief and grief.reactionPending == true
        and simNow() >= finite(grief.nextReactionAt, 0) then return grief end
    return nil
end

local function hasLowSupplies(actor)
    local inventory = U().inventory(actor)
    local bandages, food, water = 0, 0, 0
    for _, item in ipairs(U().inventoryItems(inventory, 128)) do
        local lowered = string.lower(U().itemType(item))
        if string.find(lowered, "bandage", 1, true) or string.find(lowered, "rippedsheet", 1, true) then
            bandages = bandages + 1
        end
        local hunger, hungerOk = U().call(item, "getHungerChange")
        if hungerOk and finite(hunger, 0) < 0 then food = food + 1 end
        local fluid, fluidOk = U().call(item, "getFluidContainer")
        if fluidOk and fluid ~= nil then
            local amount, amountOk = U().call(fluid, "getAmount")
            if not amountOk then amount, amountOk = U().call(fluid, "getFluidAmount") end
            if amountOk and finite(amount, 0) > 0 then water = water + 1 end
        end
    end
    return bandages == 0 or food == 0 or water == 0
end

local function shouldRequestSupply(actor, mind)
    local current = simNow()
    if mind.pendingRequest ~= nil
        or current < finite(mind.lastSupplyRequestAt, 0)
            + hours(U().config("mindSupplyRequestCooldownGameHours") or 24) then return false end
    local age = current - SC.Community.lastSupplyRunAt()
    return mind.boredom >= 45 and (age >= hours(U().config("mindSupplyRunAgeGameHours") or 48)
        or hasLowSupplies(actor))
end

function Autonomy.intentFor(actor, player, snapshot, commands)
    if not actor or type(commands) ~= "table" or commands.recruited ~= true then return nil end
    if player and U().sameFloor(actor, player)
        and U().distance(actor, player) > (U().config("mindDetailedRadius") or 40) then
        return nil
    end
    local runtime = runtimeState(actor)
    if runtime.episode then return { kind = "mental_episode", priority = 90, active = true } end
    local reservation = SC.Community.reservationFor(actor)
    if reservation and reservation.ownerId ~= U().idOf(actor) then
        return { kind = "social_participant", priority = 88, ownerId = reservation.ownerId }
    end
    local grief = griefEligible(actor, snapshot)
    if grief then return { kind = "grief_response", priority = 82, grief = grief } end
    if majorEligible(actor, commands, snapshot) then
        return { kind = "mental_episode", priority = 78, response = SC.Community.mindFor(actor).stressResponse }
    end
    if safeContext(actor, snapshot) and SC.Community.joyReady(actor, commands) then
        return { kind = "joy_response", priority = 61 }
    end
    local mind = SC.Community.mindFor(actor, commands)
    if safeContext(actor, snapshot)
        and finite(commands.stress, 0) >= (U().config("mindMinorStress") or 55)
        and simNow() >= finite(mind.nextMinorAt, 0) then
        return { kind = "purposeful_idle", priority = 56, purpose = "minor_stress" }
    end
    if threatCount(snapshot) == 0 and shouldRequestSupply(actor, mind) then
        return { kind = "purposeful_idle", priority = 54, purpose = "supply_request" }
    end
    if threatCount(snapshot) == 0 and mind.boredom >= 45 and simNow() >= mind.nextPurposeAt then
        return { kind = "purposeful_idle", priority = 36, purpose = "restless_route" }
    end
    return nil
end

local function wallSpot(actor)
    local ax, ay, az = U().position(actor)
    if not ax then return nil end
    local best, bestScore
    local cardinal = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
    for radius = 1, 5 do
        for dx = -radius, radius do
            for dy = -radius, radius do
                if math.max(math.abs(dx), math.abs(dy)) == radius then
                    local square = U().gridSquare(math.floor(ax + dx), math.floor(ay + dy), math.floor(az))
                    if square and U().isSquareFree(square) then
                        local room, roomOk = U().call(square, "getRoom")
                        if roomOk and room ~= nil then
                            local besideWall = false
                            for _, step in ipairs(cardinal) do
                                local neighbor = U().gridSquare(math.floor(ax + dx + step[1]),
                                    math.floor(ay + dy + step[2]), math.floor(az))
                                local solid, solidOk = U().call(neighbor, "isSolid")
                                if neighbor == nil or (solidOk and solid == true)
                                    or (neighbor and U().edgeBlocked(square, neighbor)) then
                                    besideWall = true break
                                end
                            end
                            if besideWall then
                                local score = U().distance(actor, square)
                                if bestScore == nil or score < bestScore then best, bestScore = square, score end
                            end
                        end
                    end
                end
            end
        end
    end
    return best
end

local function emptyGlassBottle(actor)
    for _, item in ipairs(U().inventoryItems(U().inventory(actor), 128)) do
        local lowered = string.lower(U().itemType(item))
        if glassTypes[lowered] then return item end
        if U().itemHasTag(item, "glass") then
            local fluid, fluidOk = U().call(item, "getFluidContainer")
            if fluidOk and fluid ~= nil then
                local amount, amountOk = U().call(fluid, "getAmount")
                if not amountOk then amount, amountOk = U().call(fluid, "getFluidAmount") end
                if amountOk and finite(amount, 1) <= 0 then return item end
            end
        end
    end
    return nil
end

local function safeFurniture(actor)
    local ax, ay, az = U().position(actor)
    if not ax then return nil end
    local terms = { "chair", "sofa", "couch", "table", "desk", "stool", "bench" }
    for radius = 0, 4 do
        for dx = -radius, radius do
            for dy = -radius, radius do
                if radius == 0 or math.max(math.abs(dx), math.abs(dy)) == radius then
                    local square = U().gridSquare(math.floor(ax + dx), math.floor(ay + dy), math.floor(az))
                    local found
                    U().squareObjects(square, function(object)
                        if found or U().instanceOf(object, "IsoDoor") or U().instanceOf(object, "IsoWindow")
                            or U().instanceOf(object, "IsoCurtain") then return end
                        local container, containerOk = U().call(object, "getContainer")
                        if containerOk and container ~= nil then return end
                        local sprite, spriteOk = U().call(object, "getSprite")
                        local name, nameOk = U().call(sprite, "getName")
                        local lowered = nameOk and string.lower(tostring(name)) or ""
                        for _, term in ipairs(terms) do
                            if string.find(lowered, term, 1, true) then
                                found = { object = object, square = square }
                                break
                            end
                        end
                    end, 32)
                    if found then return found end
                end
            end
        end
    end
    return nil
end

local function quietSpot(actor)
    if SC.BaseLife and type(SC.BaseLife.zoneCenter) == "function" then
        local center = SC.BaseLife.zoneCenter("rest")
        if center and U().loadedSquare(center) then return U().loadedSquare(center) end
    end
    return wallSpot(actor)
end

local function buildRestlessRoute(actor)
    local ax, ay, az = U().position(actor)
    if not ax then return {} end
    local radius = U().config("mindRestlessRouteRadius") or 6
    local candidates = {}
    for dx = -radius, radius do
        for dy = -radius, radius do
            if math.max(math.abs(dx), math.abs(dy)) >= 3 then
                local square = U().gridSquare(math.floor(ax + dx), math.floor(ay + dy), math.floor(az))
                if square and U().isSquareFree(square) then
                    local room, roomOk = U().call(square, "getRoom")
                    candidates[#candidates + 1] = {
                        square = square,
                        score = (roomOk and room ~= nil and 20 or 0)
                            + (U().stableHash(U().squareKey(square) .. ":purpose") % 100),
                    }
                end
            end
        end
    end
    table.sort(candidates, function(left, right) return left.score > right.score end)
    local route = {}
    for _, candidate in ipairs(candidates) do
        local separated = true
        for _, selected in ipairs(route) do
            if U().distance(selected, candidate.square) < 3 then separated = false break end
        end
        if separated then route[#route + 1] = candidate.square end
        if #route >= (U().config("mindRestlessRoutePoints") or 4) then break end
    end
    return route
end

local function cancelVisual(actor)
    if SC.NativeActions and type(SC.NativeActions.cancelVisual) == "function" then
        SC.NativeActions.cancelVisual(actor, "autonomy_episode_ended")
    elseif SC.NativeActions and type(SC.NativeActions.clearVisual) == "function" then
        SC.NativeActions.clearVisual(actor)
    end
end

local function finishEpisode(actor, runtime, reason, kind, completed)
    local id = U().idOf(actor)
    local mind = SC.Community.mindFor(actor)
    completed = completed ~= false
    if kind == "mourning" then
        if mind then
            mind.activeEpisode = nil
            if completed then
                SC.Community.addThought(actor, {
                    key = "grief_pause:" .. tostring(runtime.episode
                        and runtime.episode.subjectId or simNow()),
                    kind = "mourning", text = "Taking a moment to remember them helped me breathe.",
                    stress = -4, morale = 1, at = simNow(), expiresAt = simNow() + hours(12),
                })
            end
        end
        if runtime.episode then
            SC.Community.finishGriefReaction(actor, runtime.episode.subjectId)
        end
    elseif mind and completed then
        mind.boredom = clamp(mind.boredom - 35, 0, 100)
        SC.Community.addThought(actor, {
            key = "catharsis:" .. tostring(simNow()), kind = "catharsis",
            text = "Letting it out took some of the pressure off.", stress = -14, morale = 2,
            at = simNow(), expiresAt = simNow() + hours(12),
        })
    end
    if kind ~= "mourning" then SC.Community.finishMajor(actor) end
    SC.Community.release(id)
    cancelVisual(actor)
    if kind == "restless_break" then runtime.purposeful = nil end
    runtime.episode = nil
    if kind ~= "mourning" then
        emit("breakdown_finished", { sourceId = id, participants = { id },
            episode = kind or "unknown", completed = completed })
    end
    persist(actor)
    if completed and SC.NativeActions and type(SC.NativeActions.noteResult) == "function" then
        SC.NativeActions.noteResult(actor, "autonomy_" .. tostring(kind or "episode"),
            "completed", { kind = "long", lookChancePercent = kind == "shutdown" and 15 or 35 })
    end
    return true, reason or "episode_finished"
end

local function interruptEpisode(actor, runtime, reason)
    if not runtime.episode then return false, "no_episode" end
    if runtime.episode.kind == "shutdown" or runtime.episode.kind == "mourning" then
        U().move(actor, "walk", { action = "stand_ground", reason = "shutdown_interrupted" })
    end
    U().stop(actor)
    return finishEpisode(actor, runtime, reason or "episode_interrupted",
        runtime.episode.kind, false)
end

local function startMajor(actor, state)
    local mind = SC.Community.mindFor(actor, state)
    local id = U().idOf(actor)
    local response = mind.stressResponse
    local kind, target, item, object, square
    if response == "confronter" then
        target = closestCompanion(actor, U().config("mindSocialRadius") or 10, true)
        local pair = target and SC.Community.relation(id, U().idOf(target), false) or nil
        if target and finite(pair and pair.tension, 0) >= 65 then kind = "argument" end
    elseif response == "venter" then
        item, square = emptyGlassBottle(actor), wallSpot(actor)
        if item and square then kind = "bottle_smash" else kind = "vent" end
    elseif response == "restless" then
        local furniture = safeFurniture(actor)
        if furniture then kind, object, square = "furniture_hit", furniture.object, furniture.square
        else kind = "restless_break" end
    elseif response == "withdrawer" then
        kind, square = "withdraw", quietSpot(actor)
    elseif response == "shutdown" then
        kind, square = "shutdown", quietSpot(actor)
    end
    if not kind then
        item, square = emptyGlassBottle(actor), wallSpot(actor)
        if item and square then kind = "bottle_smash" else kind = "vent" end
    end
    local participants = { id }
    if target then participants[#participants + 1] = U().idOf(target) end
    local reserved = SC.Community.reserve(id, participants,
        U().nowMs() + (U().config("mindEpisodeActionTimeoutMs") or 12000) * 3)
    if not reserved then return false, "episode_participant_reserved" end
    SC.Community.beginMajor(actor, kind)
    local episode = {
        kind = kind, response = response, stage = "begin", startedAt = U().nowMs(),
        nextAt = U().nowMs(), target = target, item = item, object = object, square = square,
        initialHealth = U().nativeHealth(actor),
        targetInitialHealth = target and U().nativeHealth(target) or nil,
    }
    runtimeState(actor).episode = episode
    persist(actor)
    return true, "episode_started"
end

local function startMourning(actor, grief)
    if type(grief) ~= "table" or type(grief.subjectId) ~= "string" then
        return false, "grief_unavailable"
    end
    local id = U().idOf(actor)
    local reserved = SC.Community.reserve(id, { id },
        U().nowMs() + (U().config("mindEpisodeActionTimeoutMs") or 12000) * 4)
    if not reserved then return false, "grief_actor_reserved" end
    local state = commandState(actor)
    local compassion = finite(state.personalityProfile and state.personalityProfile.compassion, 50)
    local sit = grief.witnessed == true or finite(grief.currentIntensity, grief.intensity) >= 52
        or compassion >= 65
    local mind = SC.Community.mindFor(actor, state)
    mind.activeEpisode = "mourning"
    runtimeState(actor).episode = {
        kind = "mourning", stage = "begin", startedAt = U().nowMs(),
        subjectId = grief.subjectId, subjectName = grief.subjectName or "Someone from our group",
        intensity = finite(grief.currentIntensity, grief.intensity),
        witnessed = grief.witnessed == true, sit = sit, square = quietSpot(actor),
    }
    persist(actor)
    return true, "mourning_started"
end

local function visualCompleted(actor)
    if not SC.NativeActions or type(SC.NativeActions.visualStatus) ~= "function" then
        return U().nowMs() >= (runtimeState(actor).episode.nextAt or math.huge), "fallback_elapsed"
    end
    local status = SC.NativeActions.visualStatus(actor)
    if status == "active" then return false, status end
    return status == "completed", status
end

local function addBrokenGlass(actor, episode)
    local inventory = U().inventory(actor)
    if not inventory or not episode.item or not U().inventoryContains(inventory, episode.item) then return false end
    if not U().consumeItem(inventory, episode.item) then return false end
    local worldItem, added = U().call(episode.square, "AddWorldInventoryItem", "Base.BrokenGlass",
        0.5, 0.5, 0, false)
    if not added or worldItem == nil then
        U().addItem(inventory, episode.item)
        return false
    end
    U().call(episode.square, "playSound", "BreakGlassItem")
    local x, y, z = U().position(episode.square)
    if x and type(addSound) == "function" then pcall(addSound, actor, x, y, z, 12, 15) end
    return true
end

local function updateBottle(actor, runtime, episode)
    if episode.stage == "begin" or episode.stage == "approach" then
        if not episode.square then return finishEpisode(actor, runtime, "no_safe_wall", episode.kind, false) end
        if U().distance(actor, episode.square) > 1.35 then
            episode.stage = "approach"
            if SC.Navigation and type(SC.Navigation.request) == "function" then
                local accepted, reason = SC.Navigation.request(actor, episode.square, "walk", {
                    action = "purposeful_idle", reason = "find_private_wall", targetSquare = episode.square,
                })
                return accepted == true, reason or "approaching_wall"
            end
            return finishEpisode(actor, runtime, "wall_unreachable", episode.kind, false)
        end
        local accepted = U().move(actor, "walk", {
            action = "stress_bottle_smash", item = episode.item,
            targetSquare = episode.square, reason = "stress_outburst",
        })
        if accepted ~= true then return finishEpisode(actor, runtime,
            "bottle_action_rejected", episode.kind, false) end
        episode.stage, episode.nextAt = "visual", U().nowMs() + 5000
        return true, "smashing_bottle"
    end
    local completed, status = visualCompleted(actor)
    if status == "active" and U().nowMs() < episode.nextAt + 8000 then return true, "smashing_bottle" end
    if completed and addBrokenGlass(actor, episode) then
        emit("bottle_smashed", { sourceId = U().idOf(actor), participants = nearbyParticipants(actor, 8) })
    end
    return finishEpisode(actor, runtime, completed and "bottle_smashed" or "bottle_interrupted",
        episode.kind, completed)
end

local function updateFurniture(actor, runtime, episode)
    if episode.stage == "begin" or episode.stage == "approach" then
        if not episode.square or not episode.object then
            episode.kind, episode.stage = "vent", "begin"
            return true, "furniture_fallback_to_vent"
        end
        if U().distance(actor, episode.square) > 1.35 then
            episode.stage = "approach"
            if SC.Navigation and type(SC.Navigation.request) == "function" then
                local accepted, reason = SC.Navigation.request(actor, episode.square, "walk", {
                    action = "purposeful_idle", reason = "confront_safe_furniture",
                    targetSquare = episode.square,
                })
                return accepted == true, reason or "approaching_furniture"
            end
        end
        local accepted = U().move(actor, "walk", {
            action = "stress_furniture_hit", object = episode.object,
            targetSquare = episode.square, reason = "bounded_furniture_outburst",
        })
        if accepted ~= true then
            episode.kind, episode.stage = "vent", "begin"
            return true, "furniture_action_fallback"
        end
        episode.stage, episode.nextAt = "visual", U().nowMs() + 5000
        return true, "hitting_furniture"
    end
    local completed, status = visualCompleted(actor)
    if status == "active" and U().nowMs() < episode.nextAt + 8000 then return true, "hitting_furniture" end
    if completed then
        local x, y, z = U().position(episode.square)
        if x and type(addSound) == "function" then pcall(addSound, actor, x, y, z, 7, 8) end
        emit("furniture_hit", { sourceId = U().idOf(actor), participants = nearbyParticipants(actor, 8) })
    end
    return finishEpisode(actor, runtime, completed and "furniture_hit" or "furniture_interrupted",
        episode.kind, completed)
end

local function updateVent(actor, runtime, episode)
    if episode.stage == "begin" then
        sayDialogue(actor, "stress.vent", nil,
            "Damn it. I need a minute before I say something worse.")
        if SC.Relationship and type(SC.Relationship.playEmote) == "function" then
            pcall(SC.Relationship.playEmote, actor, "insult")
        end
        episode.stage, episode.nextAt = "venting", U().nowMs() + 3500
        return true, "venting"
    end
    if U().nowMs() < episode.nextAt then return true, "venting" end
    return finishEpisode(actor, runtime, "verbal_catharsis", episode.kind)
end

local function argumentSafe(actor, target, snapshot)
    return target and not U().isDead(target) and threatCount(snapshot) == 0
        and U().nativeHealth(actor) >= 90 and U().nativeHealth(target) >= 90
        and U().distance(actor, target) <= (U().config("mindSocialRadius") or 10) + 2
end

local function updateArgument(actor, runtime, episode, snapshot)
    local target = episode.target
    if not argumentSafe(actor, target, snapshot) then
        return finishEpisode(actor, runtime, "argument_safety_interrupt", episode.kind, false)
    end
    if episode.stage == "begin" or episode.stage == "approach" then
        local preferred = U().config("conversationPreferredDistance") or 1.65
        if U().distance(actor, target) > preferred + 0.6 then
            episode.stage = "approach"
            if SC.Navigation and type(SC.Navigation.request) == "function" then
                local accepted, reason = SC.Navigation.request(actor, U().squareOf(target), "walk", {
                    action = "approach_interaction", reason = "address_shared_memory",
                    targetSquare = U().squareOf(target),
                })
                return accepted == true, reason or "approaching_argument"
            end
        end
        U().move(actor, "walk", { action = "face_conversation", target = target })
        U().move(target, "walk", { action = "face_conversation", target = actor })
        sayDialogue(actor, "stress.argument.open", nil,
            "We need to talk about the last run. You took a risk with all of us.")
        episode.stage, episode.nextAt = "reply", U().nowMs() + 2600
        return true, "argument_opened"
    elseif episode.stage == "reply" then
        if U().nowMs() < episode.nextAt then return true, "argument_waiting_reply" end
        sayDialogue(target, "stress.argument.reply", nil,
            "We made the best call we had. Shouting will not change it.")
        local relation = SC.Community.relation(U().idOf(actor), U().idOf(target), true)
        local profile = commandState(actor).personalityProfile or {}
        local escalate = finite(relation.tension, 0) >= 75 and finite(profile.compassion, 50) < 70
        episode.stage = escalate and "shove" or "resolve"
        episode.nextAt = U().nowMs() + 2200
        emit("argument", {
            sourceId = U().idOf(actor), targetId = U().idOf(target),
            participants = { U().idOf(actor), U().idOf(target) },
        })
        return true, escalate and "argument_escalating" or "argument_resolving"
    elseif episode.stage == "shove" then
        if U().nowMs() < episode.nextAt then return true, "argument_escalating" end
        local accepted = U().move(actor, "walk", { action = "shove", target = target,
            socialFight = true, reason = "bounded_social_fight" })
        episode.stage, episode.nextAt = "fight_check", U().nowMs() + 2400
        episode.attackAccepted = accepted == true
        return true, accepted and "social_shove" or "social_shove_rejected"
    elseif episode.stage == "fight_check" then
        if U().nowMs() < episode.nextAt then return true, "social_fight_check" end
        local injury = U().nativeHealth(actor) < episode.initialHealth
            or U().nativeHealth(target) < episode.targetInitialHealth
        if episode.attackAccepted then
            emit("social_fight", {
                sourceId = U().idOf(actor), targetId = U().idOf(target),
                participants = { U().idOf(actor), U().idOf(target) }, injury = injury,
            })
        end
        return finishEpisode(actor, runtime, injury and "fight_stopped_on_injury" or "fight_bounded",
            episode.kind, not injury)
    end
    if U().nowMs() < episode.nextAt then return true, "argument_resolving" end
    return finishEpisode(actor, runtime, "argument_ended", episode.kind)
end

local function updateWithdraw(actor, runtime, episode)
    if episode.stage == "begin" then
        sayDialogue(actor, "stress.withdraw", nil, "I need to be alone for a while.")
        episode.stage = "approach"
    end
    if episode.square and U().distance(actor, episode.square) > 1.1 then
        if SC.Navigation and type(SC.Navigation.request) == "function" then
            local accepted, reason = SC.Navigation.request(actor, episode.square, "walk", {
                action = "purposeful_idle", reason = "seek_quiet_after_stress",
                targetSquare = episode.square,
            })
            return accepted == true, reason or "withdrawing"
        end
    end
    if not episode.nextAt or episode.nextAt <= episode.startedAt then
        episode.nextAt = U().nowMs() + 4500
        U().stop(actor)
    end
    if U().nowMs() < episode.nextAt then return true, "taking_space" end
    return finishEpisode(actor, runtime, "withdrew_safely", episode.kind)
end

local function updateRestlessBreak(actor, runtime, episode)
    runtime.purposeful = runtime.purposeful or {
        route = buildRestlessRoute(actor), index = 1, dwellUntil = 0,
        reason = "impatient_stress_walk",
    }
    local handled, reason = Autonomy.updatePurposeful(actor, runtime, true)
    if not runtime.purposeful then return finishEpisode(actor, runtime, "restless_catharsis", episode.kind) end
    return handled, reason
end

local function updateShutdown(actor, runtime, episode)
    if episode.stage == "begin" then
        sayDialogue(actor, "stress.shutdown", nil,
            "I cannot do this right now. Please leave me alone.")
        episode.stage = "approach"
    end
    if episode.stage == "approach" then
        if not episode.square then
            episode.kind, episode.stage = "withdraw", "begin"
            return true, "shutdown_fallback_to_withdraw"
        end
        if U().distance(actor, episode.square) > 1.05 then
            if SC.Navigation and type(SC.Navigation.request) == "function" then
                local accepted, reason = SC.Navigation.request(actor, episode.square, "walk", {
                    action = "purposeful_idle", reason = "find_quiet_room_to_shutdown",
                    targetSquare = episode.square,
                })
                return accepted == true, reason or "seeking_quiet_room"
            end
            episode.kind, episode.stage = "withdraw", "begin"
            return true, "shutdown_navigation_fallback"
        end
        U().stop(actor)
        local accepted, reason = U().move(actor, "walk", {
            action = "sit_ground", reason = "depressive_shutdown",
        })
        if accepted ~= true then return false, reason or "ground_sit_rejected" end
        episode.stage = "sitting_down"
        episode.seatDeadline = U().nowMs() + (U().config("mindEpisodeActionTimeoutMs") or 12000)
        return true, "sitting_down"
    end
    if episode.stage == "sitting_down" then
        local seated, ok = U().call(actor, "isSitOnGround")
        if ok and seated == true then
            episode.stage = "shutdown"
            episode.recoverAt = simNow() + hours(U().config("mindShutdownGameHours") or 4)
            return true, "shutdown_resting"
        end
        if U().nowMs() >= finite(episode.seatDeadline, 0) then
            episode.kind, episode.stage = "withdraw", "begin"
            return true, "shutdown_seat_fallback"
        end
        return true, "sitting_down"
    end
    if episode.stage == "shutdown" and simNow() < finite(episode.recoverAt, 0) then
        local seated, ok = U().call(actor, "isSitOnGround")
        if not ok or seated ~= true then
            episode.stage = "approach"
            return true, "resuming_shutdown_pose"
        end
        return true, "shutdown_resting"
    end
    local stood, reason = U().move(actor, "walk", {
        action = "stand_ground", reason = "shutdown_recovery",
    })
    if stood ~= true then return false, reason or "shutdown_stand_rejected" end
    local seated, ok = U().call(actor, "isSitOnGround")
    if ok and seated == true then return true, "standing_up" end
    return finishEpisode(actor, runtime, "shutdown_recovered", episode.kind)
end

local function updateMourning(actor, runtime, episode)
    if episode.stage == "begin" then
        sayDialogue(actor, "grief.mourn",
            { episode.subjectName or "Someone from our group" }, "%1 is gone. I need a minute.",
            { salt = episode.subjectId })
        if SC.Relationship and type(SC.Relationship.playEmote) == "function" then
            pcall(SC.Relationship.playEmote, actor, "undecided")
        end
        episode.stage = "approach"
        return true, "grief_acknowledged"
    end
    if episode.stage == "approach" then
        if episode.square and U().distance(actor, episode.square) > 1.05 then
            if SC.Navigation and type(SC.Navigation.request) == "function" then
                local accepted, reason = SC.Navigation.request(actor, episode.square, "walk", {
                    action = "purposeful_idle", reason = "seek_quiet_place_to_mourn",
                    targetSquare = episode.square,
                })
                return accepted == true, reason or "seeking_quiet_place_to_mourn"
            end
        end
        U().stop(actor)
        if episode.sit == true then
            local accepted = U().move(actor, "walk", {
                action = "sit_ground", reason = "mourning_companion",
            })
            if accepted == true then
                episode.stage = "sitting_down"
                episode.seatDeadline = U().nowMs()
                    + (U().config("mindEpisodeActionTimeoutMs") or 12000)
                return true, "mourning_sitting_down"
            end
        end
        episode.stage = "mourning"
        episode.recoverAt = simNow() + minutes(U().config("griefPauseGameMinutes") or 25)
        return true, "mourning_quietly"
    end
    if episode.stage == "sitting_down" then
        local seated, ok = U().call(actor, "isSitOnGround")
        if ok and seated == true then
            episode.stage = "mourning"
            episode.recoverAt = simNow() + minutes(U().config("griefPauseGameMinutes") or 25)
            return true, "mourning_quietly"
        end
        if U().nowMs() >= finite(episode.seatDeadline, 0) then
            episode.stage = "mourning"
            episode.sit = false
            episode.recoverAt = simNow() + minutes(U().config("griefPauseGameMinutes") or 25)
            return true, "mourning_standing_fallback"
        end
        return true, "mourning_sitting_down"
    end
    if episode.stage == "mourning" and simNow() < finite(episode.recoverAt, 0) then
        if episode.sit == true then
            local seated, ok = U().call(actor, "isSitOnGround")
            if not ok or seated ~= true then episode.sit = false end
        end
        if episode.sit ~= true then U().stop(actor) end
        return true, "mourning_quietly"
    end
    if episode.sit == true then
        local stood, reason = U().move(actor, "walk", {
            action = "stand_ground", reason = "mourning_recovery",
        })
        if stood ~= true then return false, reason or "mourning_stand_rejected" end
        local seated, ok = U().call(actor, "isSitOnGround")
        if ok and seated == true then return true, "mourning_standing_up" end
    end
    return finishEpisode(actor, runtime, "mourning_completed", episode.kind)
end

local function updateEpisode(actor, player, rootRuntime)
    local runtime = runtimeState(actor)
    local episode = runtime.episode
    if not episode then return false, "no_active_episode" end
    local snapshot = rootRuntime and (rootRuntime.snapshot
        or rootRuntime.senses and rootRuntime.senses.current) or {}
    if threatCount(snapshot) > 0 or U().nativeHealth(actor) < 70 then
        return interruptEpisode(actor, runtime, "survival_interrupt")
    end
    if episode.kind ~= "shutdown" and episode.kind ~= "mourning"
        and U().nowMs() - episode.startedAt > (U().config("mindEpisodeActionTimeoutMs") or 12000) * 4 then
        return interruptEpisode(actor, runtime, "episode_timeout")
    end
    if episode.kind == "bottle_smash" then return updateBottle(actor, runtime, episode)
    elseif episode.kind == "furniture_hit" then return updateFurniture(actor, runtime, episode)
    elseif episode.kind == "argument" then return updateArgument(actor, runtime, episode, snapshot)
    elseif episode.kind == "withdraw" then return updateWithdraw(actor, runtime, episode)
    elseif episode.kind == "shutdown" then return updateShutdown(actor, runtime, episode)
    elseif episode.kind == "mourning" then return updateMourning(actor, runtime, episode)
    elseif episode.kind == "restless_break" then return updateRestlessBreak(actor, runtime, episode)
    end
    return updateVent(actor, runtime, episode)
end

function Autonomy.interrupt(actor, reason)
    if not actor then return false, "invalid_actor" end
    local runtime = states[actor]
    if not runtime then return false, "no_episode" end
    return interruptEpisode(actor, runtime, reason or "external_interrupt")
end

function Autonomy.offerSupport(actorOrId)
    local actor = type(actorOrId) == "string" and U().resolveActor(actorOrId) or actorOrId
    if not actor then return false, "companion_unavailable" end
    local episode = runtimeState(actor).episode
    if not episode or episode.kind ~= "shutdown" then return false, "not_in_shutdown" end
    episode.recoverAt = math.min(finite(episode.recoverAt, math.huge),
        simNow() + minutes(U().config("mindShutdownSupportGameMinutes") or 15))
    SC.Community.addThought(actor, {
        key = "support_during_shutdown:" .. tostring(simNow()), kind = "received_support",
        text = "Someone stayed and helped when everything felt hopeless.",
        stress = -8, morale = 7, at = simNow(), expiresAt = simNow() + hours(24),
    })
    persist(actor)
    return true, "shutdown_recovery_shortened"
end

function Autonomy.updatePurposeful(actor, runtime, breakdown)
    local purpose = runtime.purposeful
    if not purpose or type(purpose.route) ~= "table" or #purpose.route == 0 then
        runtime.purposeful = nil
        return false, "no_purposeful_route"
    end
    local target = purpose.route[purpose.index]
    if not target then
        runtime.purposeful = nil
        local mind = SC.Community.mindFor(actor)
        if mind then
            mind.boredom = clamp(mind.boredom - (breakdown and 20 or 35), 0, 100)
            mind.nextPurposeAt = simNow() + hours(U().config("mindPurposeCooldownGameHours") or 2)
        end
        persist(actor)
        return true, "purposeful_route_completed"
    end
    if U().distance(actor, target) > 0.9 then
        if SC.Navigation and type(SC.Navigation.request) == "function" then
            local accepted, reason = SC.Navigation.request(actor, target, "walk", {
                action = "purposeful_idle", reason = purpose.reason,
                targetSquare = target, purposeful = true,
            })
            return accepted == true, reason or "purposeful_walking"
        end
        runtime.purposeful = nil
        return false, "purposeful_navigation_unavailable"
    end
    if purpose.dwellUntil <= 0 then
        purpose.dwellUntil = U().nowMs() + 1500
        local ax, ay, az = U().position(actor)
        U().move(actor, "walk", {
            action = "rear_scan",
            targetPosition = { x = ax + ((purpose.index % 2 == 0) and -2 or 2),
                y = ay + ((purpose.index % 3 == 0) and 2 or -2), z = az },
            reason = "purposeful_observation",
        })
        return true, "purposeful_observation"
    end
    if U().nowMs() < purpose.dwellUntil then return true, "purposeful_dwell" end
    purpose.index, purpose.dwellUntil = purpose.index + 1, 0
    return true, "purposeful_next_point"
end

local function askSupplyRun(actor)
    local request = SC.Community.createSupplyRequest(actor, supplyChoices)
    if not request then return false, "request_creation_failed" end
    request.text = dialogueLine(actor, "supply.question", nil, request.text)
    U().say(actor, request.text)
    if SC.Relationship and type(SC.Relationship.playEmote) == "function" then
        pcall(SC.Relationship.playEmote, actor, "shrug")
    end
    persist(actor)
    return true, "supply_run_requested"
end

local function acknowledgeStress(actor)
    local mind = SC.Community.mindFor(actor)
    if not mind then return false, "mind_unavailable" end
    sayDialogue(actor, "stress.minor." .. tostring(mind.stressResponse), nil,
        "I need a moment to get my head straight.")
    if SC.Relationship and type(SC.Relationship.playEmote) == "function" then
        pcall(SC.Relationship.playEmote, actor,
            mind.stressResponse == "confronter" and "ceasefire" or "undecided")
    end
    mind.nextMinorAt = simNow() + hours(U().config("mindMinorCooldownGameHours") or 6)
    persist(actor)
    return true, "minor_stress_acknowledged"
end

local function updateJoy(actor)
    local inspiration = SC.Community.beginJoy(actor)
    if not inspiration then return false, "joy_not_ready" end
    sayDialogue(actor, "joy." .. tostring(inspiration.kind), nil,
        "For once, I feel ready for whatever comes next.")
    if SC.Relationship and type(SC.Relationship.playEmote) == "function" then
        pcall(SC.Relationship.playEmote, actor, inspiration.kind == "focused" and "signalok" or "thumbsup")
    end
    if inspiration.kind == "rallying" or inspiration.kind == "caretaker" then
        local participants = nearbyParticipants(actor, 8)
        emit("joy_shared", { sourceId = U().idOf(actor), participants = participants,
            response = inspiration.kind })
    end
    persist(actor)
    return true, "joy_response_started"
end

local function updateParticipant(actor, detail)
    local owner = U().resolveActor(detail.ownerId)
    if not owner or U().isDead(owner) then
        SC.Community.release(detail.ownerId)
        U().stop(actor)
        return false, "social_owner_unavailable"
    end
    local accepted = U().move(actor, "walk", { action = "face_conversation", target = owner,
        reason = "social_participant" })
    return accepted == true, accepted and "holding_social_position" or "social_facing_rejected"
end

function Autonomy.update(actor, player, rootRuntime, detail)
    detail = type(detail) == "table" and detail or {}
    if detail.kind == "social_participant" then return updateParticipant(actor, detail) end
    if detail.kind == "joy_response" then return updateJoy(actor) end
    if detail.kind == "grief_response" then
        local runtime = runtimeState(actor)
        if not runtime.episode then
            local started, reason = startMourning(actor, detail.grief)
            if not started then return false, reason end
        end
        return updateEpisode(actor, player, rootRuntime)
    end
    if detail.kind == "purposeful_idle" then
        if detail.purpose == "supply_request" then return askSupplyRun(actor) end
        if detail.purpose == "minor_stress" then return acknowledgeStress(actor) end
        local runtime = runtimeState(actor)
        if not runtime.purposeful then
            runtime.purposeful = { route = buildRestlessRoute(actor), index = 1,
                dwellUntil = 0, reason = "impatient_bored_walk" }
        end
        return Autonomy.updatePurposeful(actor, runtime, false)
    end
    local runtime = runtimeState(actor)
    if not runtime.episode then
        local started, reason = startMajor(actor, commandState(actor))
        if not started then return false, reason end
    end
    return updateEpisode(actor, player, rootRuntime)
end

function Autonomy.requestFor(actorOrId)
    local summary = SC.Community.summary(actorOrId)
    return summary and summary.pendingRequest or nil
end

function Autonomy.respond(actorOrId, choice, player)
    local actor = type(actorOrId) == "string" and U().resolveActor(actorOrId) or actorOrId
    if not actor then return false, "companion_unavailable" end
    local mind = SC.Community.mindFor(actor)
    local request = mind and mind.pendingRequest or nil
    if not request or request.kind ~= "supply_run" then return false, "request_unavailable" end
    local allowed = false
    for _, value in ipairs(supplyChoices) do if value == choice then allowed = true break end end
    if not allowed then return false, "invalid_response" end
    local state = commandState(actor)
    local response
    if choice == "soon" then
        SC.Community.addExpectation(actor, "supply_run",
            simNow() + hours(U().config("mindSupplyPromiseGameHours") or 24))
        state.trust = clamp(finite(state.trust, 0) + 1, 0, 100)
        response = dialogueLine(actor, "supply.answer.soon", nil,
            "All right. I will hold you to that.", { state = state })
    elseif choice == "come_with_me" then
        SC.Community.addExpectation(actor, "supply_run",
            simNow() + hours(U().config("mindSupplyPromiseGameHours") or 24))
        if SC.Commands and type(SC.Commands.issue) == "function" then
            pcall(SC.Commands.issue, U().idOf(actor), "follow", nil, player)
        end
        state.trust = clamp(finite(state.trust, 0) + 2, 0, 100)
        response = dialogueLine(actor, "supply.answer.join", nil,
            "Good. I will get my gear ready.", { state = state })
    elseif choice == "not_now" then
        SC.Community.addThought(actor, { key = "supply_refused:" .. tostring(simNow()),
            kind = "request_refused", text = "The supply run was refused for now.",
            stress = 4, morale = -2, at = simNow(), expiresAt = simNow() + hours(12) })
        response = dialogueLine(actor, "supply.answer.later", nil,
            "Fine. But we cannot keep putting it off.", { state = state })
    else
        local practical = finite(state.personalityProfile and state.personalityProfile.practicality, 50)
        SC.Community.addThought(actor, { key = "supply_explained:" .. tostring(simNow()),
            kind = "request_explained", text = "There was a reason we could not spare a run.",
            stress = practical >= 60 and 1 or 3, morale = -1,
            at = simNow(), expiresAt = simNow() + hours(8) })
        response = dialogueLine(actor, "supply.answer.cannot", nil,
            practical >= 60 and "I understand. We make do with what we have."
                or "I understand the reason. I still do not like it.", { state = state })
    end
    SC.Community.clearRequest(actor)
    U().say(actor, response)
    persist(actor)
    return true, "response_recorded"
end

function Autonomy.workDuration(actor, baseDuration)
    local mind = SC.Community.mindFor(actor)
    if mind and mind.inspiration and mind.inspiration.kind == "focused"
        and simNow() < finite(mind.inspiration.untilAt, 0) then
        return math.max(500, math.floor(finite(baseDuration, 0) * 0.85))
    end
    return baseDuration
end

function Autonomy.decisionBonus(actor, kind)
    local mind = SC.Community.mindFor(actor)
    local inspiration = mind and mind.inspiration or nil
    if not inspiration or simNow() >= finite(inspiration.untilAt, 0) then return 0 end
    if inspiration.kind == "caretaker" and kind == "medical" then return 8 end
    if inspiration.kind == "organizer" and (kind == "logistics" or kind == "base_work") then return 7 end
    if inspiration.kind == "bold" and (kind == "encounter" or kind == "scavenge") then return 5 end
    if inspiration.kind == "focused" and (kind == "downtime" or kind == "base_work") then return 5 end
    return 0
end

local function runParticipants(player)
    local participants = {}
    for _, actor in ipairs(recruitedActors()) do
        if U().sameFloor(actor, player) and U().distance(actor, player) <= 14 then
            participants[#participants + 1] = U().idOf(actor)
        end
    end
    return participants
end

function Autonomy.pulse(player)
    SC.Community.processEvents(32)
    if not player or not SC.BaseLife or type(SC.BaseLife.active) ~= "function"
        or SC.BaseLife.active() == nil then return true, "community_events_processed" end
    local current = simNow()
    local inside = SC.BaseLife.isInside(player) == true
    local previous = SC.Community.playerAtBase()
    if previous == nil then
        SC.Community.setPlayerAtBase(inside)
        return true, "supply_run_state_initialized"
    end
    local run = SC.Community.activeRun()
    if previous and not inside and run == nil then
        local participants = runParticipants(player)
        local health = {}
        for _, id in ipairs(participants) do
            local actor = U().resolveActor(id)
            health[id] = actor and U().nativeHealth(actor) or 100
        end
        SC.Community.setActiveRun({ startedAt = current, participants = participants, health = health })
    elseif run and not inside then
        local known = {}
        for _, id in ipairs(run.participants or {}) do known[id] = true end
        for _, id in ipairs(runParticipants(player)) do
            if not known[id] then
                run.participants[#run.participants + 1] = id
                local actor = U().resolveActor(id)
                run.health[id] = actor and U().nativeHealth(actor) or 100
            end
        end
    elseif run and inside then
        if current - finite(run.startedAt, current) >= minutes(30) then
            local rough = false
            for _, id in ipairs(run.participants or {}) do
                local actor = U().resolveActor(id)
                if actor and U().nativeHealth(actor) < finite(run.health and run.health[id], 100) - 5 then
                    rough = true break
                end
            end
            emit(rough and "supply_run_rough" or "supply_run_completed", {
                sourceId = "player:local", participants = run.participants,
                duration = current - run.startedAt,
            })
            SC.Community.setLastSupplyRunAt(current)
        end
        SC.Community.setActiveRun(nil)
    end
    SC.Community.setPlayerAtBase(inside)
    return true, "community_pulse"
end

function Autonomy.summary(actorOrId)
    return SC.Community.summary(actorOrId)
end

function Autonomy.debugSet(actorOrId, fields)
    return SC.Community.debugSet(actorOrId, fields)
end

function Autonomy.reset(actor)
    if actor then
        local runtime = states[actor]
        if runtime and runtime.episode then interruptEpisode(actor, runtime, "reset") end
        states[actor], observations[actor] = nil, nil
    else
        states = setmetatable({}, { __mode = "k" })
        observations = setmetatable({}, { __mode = "k" })
        recentEvents = {}
    end
end

return Autonomy
