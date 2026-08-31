-- SPDX-License-Identifier: MIT

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
if not SC.GameplayUtil and type(require) == "function" then pcall(require, "SCGameplayUtil") end
if not SC.Performance and type(require) == "function" then pcall(require, "SCPerformance") end

SC.Senses = SC.Senses or {}
local Senses = SC.Senses
local sounds = {}

local function util()
    return SC.GameplayUtil
end

local function truthyCall(value, methodName, ...)
    local U = util()
    local result, ok = U.call(value, methodName, ...)
    return ok and result == true
end

local function isActiveZombie(zombie)
    local U = util()
    if not U.isZombie(zombie) or U.isDead(zombie) then return false end
    return true
end

local function isStandingZombie(zombie)
    if not isActiveZombie(zombie) then return false end
    if truthyCall(zombie, "isOnFloor") or truthyCall(zombie, "isProne") then return false end
    return true
end

local function isAttacking(zombie, actor, player)
    local U = util()
    if truthyCall(zombie, "isAttacking") then return true end
    if truthyCall(zombie, "getVariableBoolean", "bAttack") then return true end
    local target, ok = U.call(zombie, "getTarget")
    return ok and (target == actor or target == player)
end

local function squareAt(originX, originY, originZ, dx, dy)
    return util().gridSquare(originX + dx, originY + dy, originZ)
end

local function addOffset(offsets, seen, dx, dy, budget, band)
    if #offsets >= budget then return false end
    local key = tostring(dx) .. ":" .. tostring(dy)
    if seen[key] then return true end
    seen[key] = true
    offsets[#offsets + 1] = { x = dx, y = dy, d2 = dx * dx + dy * dy, band = band }
    return true
end

local function scanOffsets(radius, budget, phase)
    local offsets, seen = {}, {}
    local nearRadius = math.min(4, radius)
    for distance = 0, nearRadius do
        for dx = -distance, distance do
            for dy = -distance, distance do
                if math.max(math.abs(dx), math.abs(dy)) == distance then
                    if not addOffset(offsets, seen, dx, dy, budget, "near") then return offsets end
                end
            end
        end
    end

    -- Cardinal and diagonal rays keep distant approaches represented every scan.
    for distance = nearRadius + 1, radius do
        local rayPoints = { { distance, 0 }, { -distance, 0 }, { 0, distance }, { 0, -distance } }
        for _, point in ipairs(rayPoints) do
            if not addOffset(offsets, seen, point[1], point[2], budget, "ray") then return offsets end
        end
    end

    -- Rotate a deterministic outer sample. Nearby squares are complete; distant
    -- squares are covered over successive 2 Hz snapshots without an all-cell scan.
    for distance = nearRadius + 1, radius do
        for dx = -distance, distance do
            for dy = -distance, distance do
                if math.max(math.abs(dx), math.abs(dy)) == distance then
                    local selector = (dx * 31 + dy * 17 + distance * 13) % 8
                    if selector == phase then
                        if not addOffset(offsets, seen, dx, dy, budget, "outer") then return offsets end
                    end
                end
            end
        end
    end
    return offsets
end

local function edgeKind(originSquare, otherSquare)
    local U = util()
    local isWindow, windowOk = U.call(originSquare, "isWindowTo", otherSquare)
    if windowOk and isWindow then return "window" end
    local isDoor, doorOk = U.call(originSquare, "isDoorTo", otherSquare)
    if doorOk and isDoor then return "door" end
    local isHoppable, hopOk = U.call(originSquare, "isHoppableTo", otherSquare)
    if hopOk and isHoppable then return "fence" end
    if U.edgeBlocked(originSquare, otherSquare) then return "blocked" end
    return "open"
end

local function squareIsOutdoor(square)
    if not square then return false end
    local room, ok = util().call(square, "getRoom")
    return ok and room == nil
end

local function barrierObject(fromSquare, toSquare, kind)
    local U = util()
    local fx, fy = U.position(fromSquare)
    local tx, ty = U.position(toSquare)
    if not fx or not tx then return nil end
    local owner = fromSquare
    local north
    if ty < fy then north = true
    elseif ty > fy then owner, north = toSquare, true
    elseif tx < fx then north = false
    else owner, north = toSquare, false end
    if kind == "door" then
        local door, ok = U.call(owner, "getDoor", north)
        if ok then return door end
    elseif kind == "window" then
        local window, ok = U.call(owner, "getWindow", north)
        if ok then return window end
    end
    return nil
end

local function threatRecord(actor, player, zombie, actorSquare)
    local U = util()
    local zombieSquare = U.squareOf(zombie)
    local distanceSq = U.distanceSq(actor, zombie)
    local visible = U.canSee(actor, zombie)
    local blocked = zombieSquare and U.edgeBlocked(actorSquare, zombieSquare) or true
    local fenced = false
    if zombieSquare and distanceSq <= 12 then
        local hop, hopOk = U.call(actorSquare, "isHoppableTo", zombieSquare)
        fenced = hopOk and hop == true
    end
    local attacking = isAttacking(zombie, actor, player)
    local playerDistanceSq = player and U.distanceSq(player, zombie) or math.huge
    local score = 35 / (1 + math.sqrt(distanceSq))
    if attacking then score = score + 24 end
    if visible then score = score + 8 end
    if blocked then score = score - 5 end
    if fenced then score = score - 4 end
    if playerDistanceSq <= 6.25 then score = score + 14 end
    return {
        actor = zombie,
        square = zombieSquare,
        distanceSq = distanceSq,
        distance = math.sqrt(distanceSq),
        visible = visible,
        obstructed = blocked,
        fenced = fenced,
        attacking = attacking,
        playerDistanceSq = playerDistanceSq,
        score = score,
    }
end

local function pruneSounds(now)
    local U = util()
    local memory = U.config("soundMemoryMs") or 8000
    local write = 1
    for read = 1, #sounds do
        local sound = sounds[read]
        if sound and now - sound.time <= memory then
            sounds[write] = sound
            write = write + 1
        end
    end
    for index = #sounds, write, -1 do sounds[index] = nil end
end

function Senses.hear(source, x, y, z, radius, volume, kind)
    local U = util()
    if type(x) ~= "number" or type(y) ~= "number" then return false end
    local now = U.nowMs()
    pruneSounds(now)
    sounds[#sounds + 1] = {
        source = source,
        x = x,
        y = y,
        z = z or 0,
        radius = radius or 10,
        volume = volume or 1,
        kind = kind or "world",
        time = now,
    }
    local limit = U.config("soundLimit") or 16
    while #sounds > limit do table.remove(sounds, 1) end
    return true
end

local function relevantSounds(actor, runtimeSounds, now)
    local U = util()
    pruneSounds(now)
    local result = {}
    local limit = U.config("soundLimit") or 16
    local function consider(sound)
        if type(sound) ~= "table" or #result >= limit then return end
        local distanceSq = U.distanceSq(actor, sound)
        local radius = tonumber(sound.radius) or 10
        if distanceSq <= radius * radius then
            local copy = U.copyShallow(sound)
            copy.distanceSq = distanceSq
            copy.ageMs = now - (tonumber(sound.time) or now)
            result[#result + 1] = copy
        end
    end
    for _, sound in ipairs(sounds) do consider(sound) end
    if type(runtimeSounds) == "table" then
        local startIndex = math.max(1, #runtimeSounds - limit + 1)
        for index = startIndex, #runtimeSounds do consider(runtimeSounds[index]) end
    end
    table.sort(result, function(a, b)
        local av = (tonumber(a.volume) or 1) / (1 + a.distanceSq)
        local bv = (tonumber(b.volume) or 1) / (1 + b.distanceSq)
        return av > bv
    end)
    return result
end

local function collectAllies(actor)
    local U = util()
    local allies = {}
    local limit = U.config("perceptionAllyLimit") or 16
    for _, ally in ipairs(U.registryLiving(limit + 1)) do
        if ally ~= actor and U.isValidActor(ally) then
            allies[#allies + 1] = {
                actor = ally,
                id = U.idOf(ally),
                square = U.squareOf(ally),
                distanceSq = U.distanceSq(actor, ally),
                health = U.nativeHealth(ally),
            }
            if #allies >= limit then break end
        end
    end
    return allies
end

local function collectEscapeSquares(actor, threats)
    local U = util()
    local actorSquare = U.squareOf(actor)
    local x, y, z = U.position(actorSquare)
    if not x then return {}, {} end
    local candidates, exits = {}, {}
    local radius = U.config("escapeScanRadius") or 5
    local exitLimit = U.config("perceptionExitLimit") or 16
    local directions = {
        { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 },
        { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 },
    }
    for _, direction in ipairs(directions) do
        local previous = actorSquare
        for distance = 1, radius do
            local square = squareAt(x, y, z, direction[1] * distance, direction[2] * distance)
            if not square or not U.isSquareFree(square) then break end
            local kind = edgeKind(previous, square)
            if kind == "blocked" then break end
            if kind ~= "open" and #exits < exitLimit then
                exits[#exits + 1] = {
                    kind = kind,
                    square = square,
                    fromSquare = previous,
                    object = barrierObject(previous, square, kind),
                    distance = distance,
                }
            end
            local danger = 0
            local nearest = math.huge
            for _, threat in ipairs(threats) do
                local threatDistanceSq = U.distanceSq(square, threat.actor)
                if threatDistanceSq < nearest then nearest = threatDistanceSq end
                if threatDistanceSq <= 9 then danger = danger + 1 end
            end
            candidates[#candidates + 1] = {
                square = square,
                distance = distance,
                danger = danger,
                outdoors = squareIsOutdoor(square),
                nearestThreatSq = nearest,
                score = distance * 3 + math.min(nearest, 100) * 0.15 - danger * 20
                    + (squareIsOutdoor(square) and 12 or 0),
            }
            previous = square
            if kind == "window" then break end
        end
    end
    table.sort(candidates, function(a, b) return a.score > b.score end)
    while #candidates > exitLimit do table.remove(candidates) end
    return candidates, exits
end

local function directionalThreats(actor, threats, immediate)
    local U = util()
    local ax, ay, az = U.position(actor)
    local sectors = { north = 0, east = 0, south = 0, west = 0 }
    local closeCount, closeImmediateCount = 0, 0
    local closeRadius = U.config("combatCloseThreatRadius") or 4.5
    local closeRadiusSq = closeRadius * closeRadius
    if not ax then return sectors, 0, 0, 0 end
    for _, threat in ipairs(threats) do
        if (threat.distanceSq or math.huge) <= closeRadiusSq and threat.actor
            and U.sameFloor(actor, threat.actor) then
            local tx, ty = U.position(threat.actor)
            if tx then
                local dx, dy = tx - ax, ty - ay
                local sector
                if math.abs(dx) >= math.abs(dy) then sector = dx >= 0 and "east" or "west"
                else sector = dy >= 0 and "south" or "north" end
                sectors[sector] = sectors[sector] + 1
                closeCount = closeCount + 1
            end
        end
    end
    local occupied = 0
    for _, count in pairs(sectors) do if count > 0 then occupied = occupied + 1 end end
    for _, threat in ipairs(immediate or {}) do
        if (threat.distanceSq or math.huge) <= closeRadiusSq then closeImmediateCount = closeImmediateCount + 1 end
    end
    return sectors, occupied, closeCount, closeImmediateCount
end

local function playerCondition(player, threats)
    local U = util()
    if not player then return { available = false, danger = 0 } end
    local danger, immediate = 0, 0
    for _, threat in ipairs(threats) do
        local distanceSq = U.distanceSq(player, threat.actor)
        if distanceSq <= 36 then danger = danger + (threat.attacking and 2 or 1) end
        if distanceSq <= 4 then immediate = immediate + 1 end
    end
    return {
        available = U.isValidActor(player),
        actor = player,
        health = U.nativeHealth(player),
        danger = danger,
        immediateThreats = immediate,
        square = U.squareOf(player),
    }
end

local offsetCache = {}

local function cachedScanOffsets(radius, squareBudget, phase)
    local verticalBudget = math.min(24, math.floor(squareBudget * 0.12))
    local horizontalBudget = squareBudget - verticalBudget
    local key = tostring(radius) .. ":" .. tostring(squareBudget) .. ":" .. tostring(phase)
    local cached = offsetCache[key]
    if cached then return cached end
    local offsets = scanOffsets(radius, horizontalBudget, phase)
    for _, dz in ipairs({ -1, 1 }) do
        for dx = -2, 2 do
            for dy = -2, 2 do
                if #offsets >= squareBudget then break end
                if (dx + dy + phase) % 2 == 0 then
                    offsets[#offsets + 1] = {
                        x = dx, y = dy, z = dz, d2 = dx * dx + dy * dy,
                        band = "vertical",
                    }
                end
            end
            if #offsets >= squareBudget then break end
        end
        if #offsets >= squareBudget then break end
    end
    offsetCache[key] = offsets
    return offsets
end

local function newScanJob(state, actorSquare, originX, originY, originZ, radius, squareBudget)
    state.scanPhase = ((state.scanPhase or -1) + 1) % 8
    return {
        phase = state.scanPhase,
        originSquare = actorSquare,
        originX = originX,
        originY = originY,
        originZ = originZ,
        radius = radius,
        squareBudget = squareBudget,
        offsets = cachedScanOffsets(radius, squareBudget, state.scanPhase),
        index = 1,
        scannedSquares = 0,
        outerSampled = 0,
        threats = {},
        immediate = {},
        fenced = {},
        stealthThreats = {},
        seen = setmetatable({}, { __mode = "k" }),
    }
end

local function scanJobInvalid(job, originX, originY, originZ, radius, squareBudget)
    if type(job) ~= "table" or job.index > #(job.offsets or {}) then return true end
    if job.originZ ~= originZ or job.radius ~= radius or job.squareBudget ~= squareBudget then return true end
    local dx, dy = (originX or 0) - (job.originX or 0), (originY or 0) - (job.originY or 0)
    return dx * dx + dy * dy > 16
end

local function liveThreatLists(actor, player, actorSquare, job, threatLimit, immediateRadiusSq)
    local threats, immediate, fenced, stealth = {}, {}, {}, {}
    for _, prior in ipairs(job.stealthThreats or {}) do
        local zombie = prior.actor
        if #stealth >= threatLimit then break end
        if isActiveZombie(zombie) then
            local record = threatRecord(actor, player, zombie, actorSquare)
            record.prone = not isStandingZombie(zombie)
            stealth[#stealth + 1] = record
            if not record.prone and #threats < threatLimit then
                threats[#threats + 1] = record
                if record.attacking or record.distanceSq <= immediateRadiusSq then
                    immediate[#immediate + 1] = record
                end
                if record.fenced then fenced[#fenced + 1] = record end
            end
        end
    end
    return threats, immediate, fenced, stealth
end

function Senses.snapshot(actor, player, runtime)
    local U = util()
    if not U or not U.isValidActor(actor) then
        return {
            valid = false,
            threats = {}, immediateAttackers = {}, fencedThreats = {},
            sounds = {}, exits = {}, escapeSquares = {}, allies = {},
            player = { available = false, danger = 0 },
        }
    end

    local rootRuntime = U.actorState(actor, runtime)
    rootRuntime.senses = rootRuntime.senses or {}
    local state = rootRuntime.senses
    local now = U.nowMs()
    local startedAt = now
    local actorSquare = U.squareOf(actor)
    local originX, originY, originZ = U.position(actorSquare)
    local radius = U.config("perceptionRadius") or 18
    local squareBudget = U.config("perceptionSquareBudget") or 240
    local threatLimit = U.config("perceptionThreatLimit") or 32
    local immediateRadiusSq = (U.config("immediateThreatRadius") or 2.25) ^ 2

    local job = state.scanJob
    if scanJobInvalid(job, originX, originY, originZ, radius, squareBudget) then
        job = newScanJob(state, actorSquare, originX, originY, originZ, radius, squareBudget)
        state.scanJob = job
    end
    local requested = math.max(0, #job.offsets - job.index + 1)
    local granted = requested
    if SC.Performance and type(SC.Performance.claimUnits) == "function" then
        granted = SC.Performance.claimUnits("perception", requested, false)
    end
    local processed = 0
    local function inspectSquare(square, band)
        if square then
            job.scannedSquares = job.scannedSquares + 1
            if band == "outer" then job.outerSampled = job.outerSampled + 1 end
            local sx, sy, sz = U.position(square)
            local cacheKey = sx and (tostring(sx) .. ":" .. tostring(sy) .. ":" .. tostring(sz)) or nil
            local movingObjects = cacheKey and SC.Performance
                and type(SC.Performance.cacheGet) == "function"
                and SC.Performance.cacheGet("perception-square", cacheKey, now) or nil
            if movingObjects == nil then
                movingObjects = {}
                U.squareMovingObjects(square, function(movingObject)
                    movingObjects[#movingObjects + 1] = movingObject
                end, 12)
                if cacheKey and SC.Performance and type(SC.Performance.cachePut) == "function" then
                    SC.Performance.cachePut("perception-square", cacheKey, movingObjects,
                        U.config("performanceCacheTtlMs") or 250, now)
                end
            end
            for _, movingObject in ipairs(movingObjects) do
                if #job.stealthThreats >= threatLimit then return false end
                if not job.seen[movingObject] and isActiveZombie(movingObject) then
                    job.seen[movingObject] = true
                    local record = threatRecord(actor, player, movingObject, actorSquare)
                    record.prone = not isStandingZombie(movingObject)
                    if #job.stealthThreats < threatLimit then
                        job.stealthThreats[#job.stealthThreats + 1] = record
                    end
                    if not record.prone then
                        job.threats[#job.threats + 1] = record
                        if record.attacking or record.distanceSq <= immediateRadiusSq then
                            job.immediate[#job.immediate + 1] = record
                        end
                        if record.fenced then job.fenced[#job.fenced + 1] = record end
                    end
                end
            end
        end
    end

    while processed < granted and job.index <= #job.offsets
        and #job.stealthThreats < threatLimit do
        local offset = job.offsets[job.index]
        job.index = job.index + 1
        processed = processed + 1
        inspectSquare(U.gridSquare(job.originX + offset.x, job.originY + offset.y,
            job.originZ + (offset.z or 0)), offset.band)
    end

    local complete = job.index > #job.offsets or #job.stealthThreats >= threatLimit
    local threats, immediate, fenced, stealthThreats = liveThreatLists(
        actor, player, actorSquare, job, threatLimit, immediateRadiusSq)

    table.sort(threats, function(a, b)
        if a.score == b.score then return a.distanceSq < b.distanceSq end
        return a.score > b.score
    end)
    table.sort(stealthThreats, function(a, b)
        if a.distanceSq == b.distanceSq then return a.score > b.score end
        return a.distanceSq < b.distanceSq
    end)
    table.sort(immediate, function(a, b) return a.distanceSq < b.distanceSq end)

    local escapeSquares, exits
    if complete or state.escapeSquares == nil then
        escapeSquares, exits = collectEscapeSquares(actor, threats)
        state.escapeSquares, state.exits = escapeSquares, exits
    else
        escapeSquares, exits = state.escapeSquares or {}, state.exits or {}
    end
    local threatSectors, occupiedThreatSectors, closeThreatCount, closeImmediateCount =
        directionalThreats(actor, threats, immediate)
    local recentSounds = relevantSounds(actor, rootRuntime.sounds, now)
    local strongest = threats[1]
    if strongest then
        local tx, ty, tz = U.position(strongest.actor)
        state.lastKnownDanger = {
            actor = strongest.actor,
            x = tx, y = ty, z = tz,
            score = strongest.score,
            seenAt = now,
        }
    elseif state.lastKnownDanger and now - state.lastKnownDanger.seenAt > (U.config("lastKnownThreatMs") or 5000) then
        state.lastKnownDanger = nil
    end

    local actorRoom, actorRoomOk = U.call(actorSquare, "getRoom")
    local snapshot = {
        valid = true,
        time = now,
        actor = actor,
        origin = { x = originX, y = originY, z = originZ, square = actorSquare },
        radius = radius,
        scannedSquares = job.scannedSquares,
        outerSampled = job.outerSampled,
        scanComplete = complete,
        scanProgress = #job.offsets > 0 and math.min(1, (job.index - 1) / #job.offsets) or 1,
        threats = threats,
        stealthThreats = stealthThreats,
        immediateAttackers = immediate,
        fencedThreats = fenced,
        threatCount = #threats,
        immediateCount = #immediate,
        pressure = #immediate * 1.5 + math.max(0, #threats - #immediate) * 0.35,
        directionalPressure = closeImmediateCount * 1.8
            + math.max(0, closeThreatCount - closeImmediateCount) * 0.55
            + math.max(0, occupiedThreatSectors - 1) * 0.6,
        closeThreatCount = closeThreatCount,
        closeImmediateCount = closeImmediateCount,
        threatSectors = threatSectors,
        occupiedThreatSectors = occupiedThreatSectors,
        nearestThreat = threats[1],
        lastKnownDanger = state.lastKnownDanger,
        sounds = recentSounds,
        strongestSound = recentSounds[1],
        exits = exits,
        escapeSquares = escapeSquares,
        allies = state.allies and now - (state.alliesAt or 0) <= 250
            and state.allies or collectAllies(actor),
        -- Follow downtime is permitted only after the actor has actually
        -- entered a room. This field was consumed by decisions but was not
        -- previously populated, so outdoor and indoor idle were indistinct.
        indoors = actorRoomOk and actorRoom ~= nil,
    }
    snapshot.player = playerCondition(player, threats)
    snapshot.encircled = closeImmediateCount >= 3 or occupiedThreatSectors >= 3
        or (#escapeSquares == 0 and #threats >= 2)
    state.current = snapshot
    state.allies, state.alliesAt = snapshot.allies, now
    if complete then
        state.scanJob = nil
        state.lastCompleteAt = now
    elseif SC.Performance and type(SC.Performance.markYield) == "function" then
        SC.Performance.markYield("perception", U.idOf(actor), processed)
    end
    if SC.Performance and type(SC.Performance.record) == "function" then
        SC.Performance.record("perception", U.idOf(actor), U.nowMs() - startedAt, processed, false)
    end
    return snapshot
end

function Senses.cached(actor, runtime)
    local U = util()
    if not U or not actor then return nil end
    local rootRuntime = type(runtime) == "table" and runtime or U.peekActorState(actor)
    return rootRuntime and rootRuntime.senses and rootRuntime.senses.current or nil
end

function Senses.reset(actor)
    local U = util()
    if actor then
        local runtime = U and U.peekActorState(actor)
        if runtime then runtime.senses = nil end
    else
        sounds = {}
        offsetCache = {}
    end
end

return Senses
