-- SPDX-License-Identifier: MIT

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
if not SC.GameplayUtil and type(require) == "function" then pcall(require, "SCGameplayUtil") end
if not SC.Topology and type(require) == "function" then pcall(require, "SCTopology") end
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

local function zombiePosture(zombie)
    if not isActiveZombie(zombie) then return "dead" end
    if truthyCall(zombie, "isCrawling")
        or truthyCall(zombie, "getVariableBoolean", "bCrawling") then
        return "crawler"
    end
    if truthyCall(zombie, "isOnFloor") or truthyCall(zombie, "isProne") then
        return "downed"
    end
    return "standing"
end

local function isAttacking(zombie)
    local U = util()
    if truthyCall(zombie, "isAttacking") then return true end
    if truthyCall(zombie, "isZombieAttacking") then return true end
    if truthyCall(zombie, "getVariableBoolean", "bAttack") then return true end
    local state, stateOk = U.call(zombie, "getCurrentState")
    if stateOk and state ~= nil
        and string.find(string.lower(tostring(state)), "attackstate", 1, true) then
        return true
    end
    return false
end

local function isTargeting(zombie, actor, player)
    local U = util()
    local target, ok = U.call(zombie, "getTarget")
    return ok and (target == actor or target == player)
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

local function squareIsOutdoor(square)
    if not square then return false end
    local room, ok = util().call(square, "getRoom")
    return ok and room == nil
end

local function threatRecord(actor, player, zombie, actorSquare)
    local U = util()
    local zombieSquare = U.squareOf(zombie)
    local distanceSq = U.distanceSq(actor, zombie)
    local visible = U.canSee(actor, zombie)
    -- isBlockedTo() only describes one adjacent edge and cannot establish LOS to
    -- a distant square. canSee() delegates actor sight to Build 42's character LOS,
    -- so an unconfirmed contact is obstructed by definition and must never enter
    -- the combat target list.
    local blocked = not visible
    local fenced = false
    if zombieSquare and distanceSq <= 12 then
        local hop, hopOk = U.call(actorSquare, "isHoppableTo", zombieSquare)
        fenced = hopOk and hop == true
    end
    local attacking = isAttacking(zombie)
    local targeting = isTargeting(zombie, actor, player)
    local posture = zombiePosture(zombie)
    local playerDistanceSq = player and U.distanceSq(player, zombie) or math.huge
    local score = 35 / (1 + math.sqrt(distanceSq))
    if attacking then score = score + 24 end
    if targeting and not attacking then score = score + 6 end
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
        targeting = targeting,
        attacking = attacking,
        posture = posture,
        grounded = posture == "crawler" or posture == "downed",
        -- Transitional compatibility for older combat/debug consumers.
        prone = posture ~= "standing",
        playerDistanceSq = playerDistanceSq,
        score = score,
    }
end

local function immediateThreat(record, immediateRadiusSq)
    if type(record) ~= "table" then return false end
    if (tonumber(record.distanceSq) or math.huge) <= immediateRadiusSq then return true end
    local cap = tonumber(util().config("perceptionAttackCommitRadius")) or 1.5
    return record.attacking == true
        and (tonumber(record.distanceSq) or math.huge) <= cap * cap
end

local function zombieAudible(actor, zombie, record)
    local U = util()
    local distanceSq = tonumber(record and record.distanceSq) or U.distanceSq(actor, zombie)
    local attacking = record and record.attacking == true
        or truthyCall(zombie, "isAttacking")
    local moving = truthyCall(zombie, "isMoving")
    local radius = attacking and (U.config("zombieHearingAttackingRadius") or 9)
        or moving and (U.config("zombieHearingMovingRadius") or 6)
        or (U.config("zombieHearingIdleRadius") or 2.25)
    return distanceSq <= radius * radius, attacking and 3 or moving and 2 or 1
end

local function heardDirection(dx, dy)
    local horizontal = math.abs(dx) >= 0.75 and (dx > 0 and "east" or "west") or nil
    local vertical = math.abs(dy) >= 0.75 and (dy > 0 and "south" or "north") or nil
    if horizontal and vertical then return vertical .. "_" .. horizontal end
    return horizontal or vertical or "nearby"
end

-- An auditory contact deliberately contains no zombie actor or exact square.
-- Hearing may inform dialogue and caution, but it must not become an omniscient
-- combat target or a path request to the other side of a wall.
local function heardThreatRecord(actor, zombie, record, current, activity)
    local ax, ay, az = util().position(actor)
    local zx, zy, zz = util().position(zombie)
    local dx, dy = (zx or ax or 0) - (ax or 0), (zy or ay or 0) - (ay or 0)
    local distance = math.sqrt(math.max(0, tonumber(record.distanceSq) or 0))
    return {
        kind = "zombie",
        heardAt = current,
        direction = heardDirection(dx, dy),
        distanceBand = distance <= 2.5 and "very_close" or distance <= 6 and "near" or "distant",
        floor = math.floor(tonumber(zz or az) or 0),
        activity = activity,
        strength = activity * 10 / (1 + distance),
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

local function collectEscapeSquares(actor, threats, state, current, immediateCount)
    local U = util()
    local actorSquare = U.squareOf(actor)
    if actorSquare == nil or type(SC.Topology) ~= "table"
        or type(SC.Topology.reachableEscapeSquares) ~= "function" then
        return {}, {}, { processed = 0, originKey = nil, signature = "unavailable" }
    end
    state = type(state) == "table" and state or {}
    current = tonumber(current) or U.nowMs()
    local originKey = U.squareKey(actorSquare)
    local signature = type(SC.Topology.localSignature) == "function"
        and SC.Topology.localSignature(actor, actorSquare) or originKey
    local cache = state.escapeTopology
    local ttl = tonumber(U.config("escapeTopologyCacheMs")) or 250
    local urgentInvalidation = (tonumber(immediateCount) or 0) > 0
        and (tonumber(state.escapeImmediateCount) or 0) <= 0
    if type(cache) ~= "table" or cache.originKey ~= originKey
        or cache.signature ~= signature or current - (tonumber(cache.computedAt) or 0) >= ttl
        or urgentInvalidation then
        local raw, exits, meta = SC.Topology.reachableEscapeSquares(actor, actorSquare, {
            radius = tonumber(U.config("escapeScanRadius")) or 5,
            nodeBudget = tonumber(U.config("escapeScanNodeBudget")) or 64,
            exitLimit = tonumber(U.config("perceptionExitLimit")) or 16,
        })
        cache = {
            raw = raw, exits = exits, originKey = originKey,
            signature = meta and meta.signature or signature,
            processed = meta and meta.processed or 0, computedAt = current,
        }
        state.escapeTopology = cache
    end
    state.escapeImmediateCount = tonumber(immediateCount) or 0

    -- Geometry is cached briefly; live danger is never cached. A moving zombie
    -- therefore changes the preferred exit on every reflex pulse without paying
    -- for another flood-fill until the topology TTL or origin changes.
    local candidates = {}
    for _, raw in ipairs(cache.raw or {}) do
        local square = raw.square
        local danger, nearest = 0, math.huge
        for _, threat in ipairs(threats or {}) do
            local threatDistanceSq = U.distanceSq(square, threat.actor)
            if threatDistanceSq < nearest then nearest = threatDistanceSq end
            if threatDistanceSq <= 9 then danger = danger + 1 end
        end
        candidates[#candidates + 1] = {
            square = square,
            distance = raw.distance,
            traversalCost = raw.traversalCost,
            requiresNative = raw.requiresNative == true,
            danger = danger,
            outdoors = squareIsOutdoor(square),
            nearestThreatSq = nearest,
            score = (tonumber(raw.distance) or 0) * 3
                + math.min(nearest, 100) * 0.15 - danger * 20
                + (squareIsOutdoor(square) and 12 or 0)
                - math.max(0, (tonumber(raw.traversalCost) or 0)
                    - (tonumber(raw.distance) or 0)) * 0.5,
        }
    end
    table.sort(candidates, function(a, b) return a.score > b.score end)
    local limit = tonumber(U.config("perceptionExitLimit")) or 16
    while #candidates > limit do table.remove(candidates) end
    return candidates, cache.exits or {}, {
        processed = cache.processed or 0,
        originKey = cache.originKey,
        signature = cache.signature,
        computedAt = cache.computedAt,
    }
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
    if type(job) ~= "table" or job.index > #(job.offsets or {}) then
        return true, "complete", 0
    end
    if job.originZ ~= originZ then return true, "floor", 0 end
    if job.radius ~= radius or job.squareBudget ~= squareBudget then
        return true, "configuration", 0
    end
    local dx, dy = (originX or 0) - (job.originX or 0), (originY or 0) - (job.originY or 0)
    local distanceSq = dx * dx + dy * dy
    local threshold = math.max(0.25,
        tonumber(util().config("perceptionScanRebaseDistance")) or 2.0)
    if distanceSq >= threshold * threshold then
        return true, "movement", math.sqrt(distanceSq)
    end
    return false, nil, math.sqrt(distanceSq)
end

local function liveThreatLists(actor, player, actorSquare, job, threatLimit, immediateRadiusSq, current)
    local threats, immediate, fenced, stealth, grounded = {}, {}, {}, {}, {}
    local heard
    for _, prior in ipairs(job.stealthThreats or {}) do
        local zombie = prior.actor
        if #stealth >= threatLimit then break end
        if isActiveZombie(zombie) then
            local record = threatRecord(actor, player, zombie, actorSquare)
            if record.visible and not record.obstructed then
                stealth[#stealth + 1] = record
                if #threats < threatLimit then
                    threats[#threats + 1] = record
                    if record.grounded then grounded[#grounded + 1] = record end
                    if immediateThreat(record, immediateRadiusSq) then
                        immediate[#immediate + 1] = record
                    end
                    if record.fenced then fenced[#fenced + 1] = record end
                end
            else
                local audible, activity = zombieAudible(actor, zombie, record)
                if audible then
                    local candidate = heardThreatRecord(actor, zombie, record, current, activity)
                    if not heard or candidate.strength > heard.strength then heard = candidate end
                end
            end
        end
    end
    return threats, immediate, fenced, stealth, grounded, heard
end

function Senses.snapshot(actor, player, runtime)
    local U = util()
    if not U or not U.isValidActor(actor) then
        return {
            valid = false,
            threats = {}, immediateAttackers = {}, fencedThreats = {}, groundedThreats = {},
            heardThreats = {}, heardThreatCount = 0,
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
    local invalid, invalidReason, rebaseDistance = scanJobInvalid(
        job, originX, originY, originZ, radius, squareBudget)
    if invalid then
        if invalidReason == "movement" then
            state.scanRebaseCount = (state.scanRebaseCount or 0) + 1
            state.lastScanRebaseDistance = rebaseDistance
            state.lastScanRebaseAt = now
        end
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
                    local audible = zombieAudible(actor, movingObject, record)
                    -- Keep only contacts the companion could actually perceive.
                    -- A silent zombie hidden in another room is reconsidered on a
                    -- later scan, but does not consume the current threat budget.
                    if (record.visible or audible) and #job.stealthThreats < threatLimit then
                        job.stealthThreats[#job.stealthThreats + 1] = record
                    end
                    if record.visible and not record.obstructed then
                        job.threats[#job.threats + 1] = record
                        if immediateThreat(record, immediateRadiusSq) then
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
    local threats, immediate, fenced, stealthThreats, groundedThreats, heard = liveThreatLists(
        actor, player, actorSquare, job, threatLimit, immediateRadiusSq, now)

    table.sort(threats, function(a, b)
        if a.score == b.score then return a.distanceSq < b.distanceSq end
        return a.score > b.score
    end)
    table.sort(stealthThreats, function(a, b)
        if a.distanceSq == b.distanceSq then return a.score > b.score end
        return a.distanceSq < b.distanceSq
    end)
    table.sort(immediate, function(a, b) return a.distanceSq < b.distanceSq end)

    local escapeSquares, exits, escapeMeta = collectEscapeSquares(
        actor, threats, state, now, #immediate)
    local threatSectors, occupiedThreatSectors, closeThreatCount, closeImmediateCount =
        directionalThreats(actor, threats, immediate)
    local recentSounds = relevantSounds(actor, rootRuntime.sounds, now)
    local strongest = threats[1]
    if strongest then
        local tx, ty, tz = U.position(strongest.actor)
        -- Store the observed square, not the live actor. Otherwise a zombie that
        -- walks behind a wall drags its "last seen" marker along in real time.
        state.lastKnownDanger = {
            x = tx, y = ty, z = tz,
            square = strongest.square,
            score = strongest.score,
            seenAt = now,
            visible = true,
            obstructed = false,
        }
    elseif state.lastKnownDanger and now - state.lastKnownDanger.seenAt > (U.config("lastKnownThreatMs") or 5000) then
        state.lastKnownDanger = nil
    end
    if heard then
        state.lastHeardDanger = heard
    elseif state.lastHeardDanger
        and now - (tonumber(state.lastHeardDanger.heardAt) or 0)
            > (U.config("heardThreatMemoryMs") or 5000) then
        state.lastHeardDanger = nil
    end
    local heardThreats = {}
    if state.lastHeardDanger then
        local remembered = U.copyShallow(state.lastHeardDanger)
        remembered.ageMs = now - (tonumber(remembered.heardAt) or now)
        heardThreats[1] = remembered
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
        scanRebaseCount = state.scanRebaseCount or 0,
        lastScanRebaseDistance = state.lastScanRebaseDistance,
        lastScanRebaseAt = state.lastScanRebaseAt,
        threats = threats,
        stealthThreats = stealthThreats,
        groundedThreats = groundedThreats,
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
        heardThreats = heardThreats,
        heardThreatCount = #heardThreats,
        lastHeardDanger = heardThreats[1],
        sounds = recentSounds,
        strongestSound = recentSounds[1],
        exits = exits,
        escapeSquares = escapeSquares,
        escapeOriginKey = escapeMeta.originKey,
        escapeTopologySignature = escapeMeta.signature,
        escapeComputedAt = escapeMeta.computedAt,
        escapeProcessedNodes = escapeMeta.processed,
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

-- The broad perception scan is deliberately sliced and cached, but a zombie can
-- enter melee range while that scan is still walking its outer frontier. This
-- bounded reflex pass revalidates known contacts and inspects only squares whose
-- bounds overlap the immediate radius. It never promotes an audible contact into
-- an actor target, preserving the wall/LOS contract.
function Senses.refreshImmediate(actor, player, snapshot, runtime)
    local U = util()
    if not U or not U.isValidActor(actor) or type(snapshot) ~= "table" then
        return snapshot
    end
    -- Negative counts are an explicit synthetic/no-candidate sentinel used by
    -- diagnostic callers; do not replace that contract with a world scan.
    if tonumber(snapshot.threatCount) and tonumber(snapshot.threatCount) < 0 then
        return snapshot
    end
    -- Untimestamped tables are caller-owned synthetic assessments. Production
    -- snapshots always carry a scan/reflex clock; preserving this distinction
    -- keeps tests, tools and scripted encounters deterministic.
    if tonumber(snapshot.time) == nil and tonumber(snapshot.reflexTime) == nil then
        return snapshot
    end
    local rootRuntime = U.actorState(actor, runtime)
    rootRuntime.senses = rootRuntime.senses or {}
    local state = rootRuntime.senses
    local now = U.nowMs()
    if now < (state.nextReflexAt or 0) and state.current then return state.current end
    if state.lastHeardDanger == nil and type(snapshot.lastHeardDanger) == "table" then
        state.lastHeardDanger = U.copyShallow(snapshot.lastHeardDanger)
    end
    if state.lastKnownDanger == nil and type(snapshot.lastKnownDanger) == "table" then
        state.lastKnownDanger = U.copyShallow(snapshot.lastKnownDanger)
    end
    state.nextReflexAt = now + math.max(25,
        tonumber(U.config("perceptionReflexIntervalMs")) or 100)
    local startedAt = now
    local actorSquare = U.squareOf(actor)
    local ax, ay, az = U.position(actor)
    if ax == nil or not actorSquare then return snapshot end
    local radius = math.max(0.5, tonumber(U.config("perceptionReflexRadius")) or 2.25)
    local radiusSq = radius * radius
    local immediateRadiusSq = (U.config("immediateThreatRadius") or 2.25) ^ 2
    local threatLimit = U.config("perceptionThreatLimit") or 32
    local threats, immediate, fenced, stealthThreats, groundedThreats = {}, {}, {}, {}, {}
    local seen = setmetatable({}, { __mode = "k" })
    local heard
    local added = 0

    local function consider(zombie, discovered)
        if seen[zombie] or not isActiveZombie(zombie) then return end
        seen[zombie] = true
        local record = threatRecord(actor, player, zombie, actorSquare)
        if record.visible and not record.obstructed then
            if #stealthThreats < threatLimit then
                stealthThreats[#stealthThreats + 1] = record
            end
            if #threats < threatLimit then
                threats[#threats + 1] = record
                if record.grounded then groundedThreats[#groundedThreats + 1] = record end
                if immediateThreat(record, immediateRadiusSq) then
                    immediate[#immediate + 1] = record
                end
                if record.fenced then fenced[#fenced + 1] = record end
                if discovered then added = added + 1 end
            end
        else
            local audible, activity = zombieAudible(actor, zombie, record)
            if audible then
                local candidate = heardThreatRecord(actor, zombie, record, now, activity)
                if not heard or candidate.strength > heard.strength then heard = candidate end
            end
        end
    end

    for _, prior in ipairs(snapshot.stealthThreats or {}) do consider(prior.actor, false) end
    for _, prior in ipairs(snapshot.threats or {}) do consider(prior.actor, false) end

    local originX, originY = math.floor(ax), math.floor(ay)
    local reach = math.ceil(radius) + 1
    local scanned = 0
    for dx = -reach, reach do
        for dy = -reach, reach do
            local sx, sy = originX + dx, originY + dy
            local nearestX = math.max(sx, math.min(ax, sx + 1))
            local nearestY = math.max(sy, math.min(ay, sy + 1))
            local boundsDx, boundsDy = nearestX - ax, nearestY - ay
            if boundsDx * boundsDx + boundsDy * boundsDy <= radiusSq then
                local square = U.gridSquare(sx, sy, az)
                if square then
                    scanned = scanned + 1
                    U.squareMovingObjects(square, function(value)
                        if U.distanceSq(actor, value) <= radiusSq then
                            consider(value, true)
                        end
                    end, threatLimit)
                end
            end
        end
    end

    table.sort(threats, function(a, b)
        if a.score == b.score then return a.distanceSq < b.distanceSq end
        return a.score > b.score
    end)
    table.sort(stealthThreats, function(a, b)
        if a.distanceSq == b.distanceSq then return a.score > b.score end
        return a.distanceSq < b.distanceSq
    end)
    table.sort(immediate, function(a, b) return a.distanceSq < b.distanceSq end)
    local escapeSquares, exits, escapeMeta = collectEscapeSquares(
        actor, threats, state, now, #immediate)
    local sectors, occupied, closeCount, closeImmediate =
        directionalThreats(actor, threats, immediate)
    local strongest = threats[1]
    if strongest then
        local tx, ty, tz = U.position(strongest.actor)
        state.lastKnownDanger = {
            x = tx, y = ty, z = tz, square = strongest.square,
            score = strongest.score, seenAt = now,
            visible = true, obstructed = false,
        }
    elseif state.lastKnownDanger
        and now - (tonumber(state.lastKnownDanger.seenAt) or 0)
            > (U.config("lastKnownThreatMs") or 5000) then
        state.lastKnownDanger = nil
    end
    if heard then
        state.lastHeardDanger = heard
    elseif state.lastHeardDanger
        and now - (tonumber(state.lastHeardDanger.heardAt) or 0)
            > (U.config("heardThreatMemoryMs") or 5000) then
        state.lastHeardDanger = nil
    end
    local heardThreats = {}
    if state.lastHeardDanger then
        local remembered = U.copyShallow(state.lastHeardDanger)
        remembered.ageMs = now - (tonumber(remembered.heardAt) or now)
        heardThreats[1] = remembered
    end

    snapshot.reflexTime = now
    snapshot.reflexScannedSquares = scanned
    snapshot.reflexAddedThreats = added
    snapshot.threats = threats
    snapshot.stealthThreats = stealthThreats
    snapshot.groundedThreats = groundedThreats
    snapshot.immediateAttackers = immediate
    snapshot.fencedThreats = fenced
    snapshot.threatCount = #threats
    snapshot.immediateCount = #immediate
    snapshot.pressure = #immediate * 1.5 + math.max(0, #threats - #immediate) * 0.35
    snapshot.directionalPressure = closeImmediate * 1.8
        + math.max(0, closeCount - closeImmediate) * 0.55
        + math.max(0, occupied - 1) * 0.6
    snapshot.closeThreatCount = closeCount
    snapshot.closeImmediateCount = closeImmediate
    snapshot.threatSectors = sectors
    snapshot.occupiedThreatSectors = occupied
    snapshot.nearestThreat = threats[1]
    snapshot.escapeSquares = escapeSquares
    snapshot.exits = exits
    snapshot.escapeOriginKey = escapeMeta.originKey
    snapshot.escapeTopologySignature = escapeMeta.signature
    snapshot.escapeComputedAt = escapeMeta.computedAt
    snapshot.escapeProcessedNodes = escapeMeta.processed
    snapshot.lastKnownDanger = state.lastKnownDanger
    snapshot.heardThreats = heardThreats
    snapshot.heardThreatCount = #heardThreats
    snapshot.lastHeardDanger = heardThreats[1]
    snapshot.player = playerCondition(player, threats)
    snapshot.encircled = closeImmediate >= 3 or occupied >= 3
        or (#(snapshot.escapeSquares or {}) == 0 and #threats >= 2)
    state.current = snapshot
    state.reflexCount = (state.reflexCount or 0) + 1
    state.reflexAddedThreats = (state.reflexAddedThreats or 0) + added
    if SC.Performance and type(SC.Performance.record) == "function" then
        SC.Performance.record("perception.reflex", U.idOf(actor),
            U.nowMs() - startedAt, scanned, false)
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
