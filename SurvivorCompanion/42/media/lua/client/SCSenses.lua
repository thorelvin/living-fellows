-- SPDX-License-Identifier: MIT

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
if not SC.GameplayUtil and type(require) == "function" then pcall(require, "SCGameplayUtil") end
if not SC.Topology and type(require) == "function" then pcall(require, "SCTopology") end
if not SC.Performance and type(require) == "function" then pcall(require, "SCPerformance") end
if not SC.ThreatSet and type(require) == "function" then pcall(require, "SCThreatSet") end
if not SC.PerceptionScan and type(require) == "function" then pcall(require, "SCPerceptionScan") end

SC.Senses = SC.Senses or {}
local Senses = SC.Senses
local sounds = {}

local function util()
    return SC.GameplayUtil
end

local function threatSets()
    return SC.ThreatSet
end

local function scans()
    return SC.PerceptionScan
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

local function squareIsOutdoor(square)
    if not square then return false end
    local room, ok = util().call(square, "getRoom")
    return ok and room == nil
end

local function threatRecord(actor, player, zombie, actorSquare)
    local U = util()
    local zombieSquare = U.squareOf(zombie)
    local distanceSq = U.distanceSq(actor, zombie)
    local zombieX, zombieY, zombieZ = U.position(zombie)
    local visible = distanceSq <= (tonumber(U.config("perceptionRadius")) or 24) ^ 2
        and U.canSee(actor, zombie)
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
        x = zombieX, y = zombieY, z = zombieZ,
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
    return threatSets().isImmediate(record, immediateRadiusSq,
        util().config("perceptionAttackCommitRadius") or 1.5)
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

local function collectRelationships(actor, player)
    local U = util()
    local allyCandidates, protectedCandidates = {}, {}
    local limit = U.config("perceptionAllyLimit") or 16
    -- Registry order is stable by id, not by relevance. Inspect the complete
    -- loaded roster before applying the small snapshot cap; otherwise a few
    -- unrelated NPCs can permanently hide a nearby party or faction member.
    local living = nil
    if SC.Registry and type(SC.Registry.living) == "function" then
        local ok, value = pcall(SC.Registry.living)
        if not ok then ok, value = pcall(SC.Registry.living, SC.Registry) end
        if ok and type(value) == "table" then living = value end
    end
    living = living or U.registryLiving(limit * 2 + 1)
    for _, candidate in ipairs(living) do
        if candidate ~= actor and U.isValidActor(candidate) then
            local relationship = "unknown"
            if SC.Factions and type(SC.Factions.relationshipBetween) == "function" then
                local ok, value = pcall(
                    SC.Factions.relationshipBetween, actor, candidate, player)
                if ok and type(value) == "string" then relationship = value end
            end
            local row = {
                actor = candidate,
                id = U.idOf(candidate),
                square = U.squareOf(candidate),
                distanceSq = U.distanceSq(actor, candidate),
                health = U.nativeHealth(candidate),
                relationship = relationship,
            }
            if relationship == "party_ally" or relationship == "faction_ally" then
                allyCandidates[#allyCandidates + 1] = row
                protectedCandidates[#protectedCandidates + 1] = row
            elseif relationship == "neutral" then
                protectedCandidates[#protectedCandidates + 1] = row
            end
        end
    end
    local function closestFirst(a, b)
        if a.distanceSq ~= b.distanceSq then return a.distanceSq < b.distanceSq end
        return tostring(a.id) < tostring(b.id)
    end
    table.sort(allyCandidates, closestFirst)
    table.sort(protectedCandidates, closestFirst)
    local allies, protected = {}, {}
    for index = 1, math.min(limit, #allyCandidates) do
        allies[index] = allyCandidates[index]
    end
    for index = 1, math.min(limit, #protectedCandidates) do
        protected[index] = protectedCandidates[index]
    end
    return allies, protected
end

Senses._collectRelationshipsForTests = collectRelationships

local function collectEscapeSquares(actor, threats, state, current, immediateCount, player)
    local U = util()
    local actorSquare = U.squareOf(actor)
    if actorSquare == nil or type(SC.Topology) ~= "table"
        or type(SC.Topology.reachableEscapeSquares) ~= "function" then
        return {}, {}, { processed = 0, originKey = nil, signature = "unavailable" }
    end
    state = type(state) == "table" and state or {}
    current = tonumber(current) or U.nowMs()
    local cohesionAnchor, currentCohesionDistance
    if player and U.isValidActor(player) and U.sameFloor(actor, player)
        and type(SC.Commands) == "table" and type(SC.Commands.peek) == "function" then
        local ok, commands = pcall(SC.Commands.peek, actor)
        local order = ok and type(commands) == "table" and commands.order or nil
        if commands and commands.recruited == true
            and (order == "follow" or order == "regroup" or order == "retreat") then
            cohesionAnchor = player
            currentCohesionDistance = U.distance(actor, player)
        end
    end
    local originKey = U.squareKey(actorSquare)
    local cache = state.escapeTopology
    -- Peaceful followers do not need a fresh 64-node combat escape flood-fill.
    -- Actual threats still trigger the immediate four-edge probe before deeper
    -- work is allowed to yield.
    if #(threats or {}) == 0 and (tonumber(immediateCount) or 0) <= 0 then
        -- A partial flood-fill is not a reusable topology snapshot. If calm
        -- cancels it, discard its partial result as well so a threat returning
        -- inside the cache TTL starts from verified immediate exits.
        if state.escapeSearch ~= nil or (cache and cache.complete ~= true) then
            state.escapeTopology = nil
        end
        state.escapeSearch = nil
        state.escapeImmediateCount = 0
        return {}, {}, { processed = 0, originKey = originKey, signature = "quiet_deferred",
            computedAt = current, deferred = true }
    end
    local ttl = tonumber(U.config("escapeTopologyCacheMs")) or 250
    local urgentInvalidation = (tonumber(immediateCount) or 0) > 0
        and (tonumber(state.escapeImmediateCount) or 0) <= 0
    local job = state.escapeSearch
    local expired = type(cache) ~= "table" or cache.complete ~= true
        or cache.originKey ~= originKey
        or current - (tonumber(cache.computedAt) or 0) >= ttl or urgentInvalidation
    if job or expired then
        -- Signature, retained-portal validation and new edge expansion share one
        -- read batch and one elapsed deadline. The four local signature edges
        -- are fixed urgent work; everything deeper is resumable.
        local started = U.nowMs()
        local deadline = started + (tonumber(U.config("escapeTopologySliceMs")) or 0.75)
        local meta
        SC.Topology.withReadBatch(function()
            local signature = type(SC.Topology.localSignature) == "function"
                and SC.Topology.localSignature(actor, actorSquare) or originKey
            local needsRefresh = type(cache) ~= "table" or cache.complete ~= true
                or cache.originKey ~= originKey or cache.signature ~= signature
                or current - (tonumber(cache.computedAt) or 0) >= ttl or urgentInvalidation
            if needsRefresh and (not job or job.originKey ~= originKey
                or job.signature ~= signature) then
                job = SC.Topology.newEscapeSearch(actor, actorSquare, {
                    radius = tonumber(U.config("escapeScanRadius")) or 5,
                    nodeBudget = tonumber(U.config("escapeScanNodeBudget")) or 64,
                    exitLimit = tonumber(U.config("perceptionExitLimit")) or 16,
                })
                job.signature = signature
                state.escapeSearch = job
            end
            if job then
                local raw, exits
                raw, exits, meta = SC.Topology.resumeEscapeSearch(job,
                    tonumber(U.config("escapeTopologyEdgesPerSlice")) or 24,
                    deadline)
                cache = {
                    raw = raw, exits = exits, originKey = originKey,
                    signature = signature,
                    processed = meta and meta.processed or 0, computedAt = current,
                    verification = meta.invalidated ~= true and job or nil,
                    complete = meta.complete == true and meta.invalidated ~= true,
                }
                if meta.invalidated then cache.computedAt = current - ttl end
                state.escapeTopology = cache
                if meta.complete then state.escapeSearch = nil end
            end
        end)
        if meta and SC.Performance and type(SC.Performance.record) == "function" then
            SC.Performance.record("perception.escape", U.idOf(actor), U.nowMs() - started,
                meta.used or 0, false)
            if not meta.complete then
                SC.Performance.markYield("perception.escape", U.idOf(actor), meta.used)
            end
        end
    end
    state.escapeImmediateCount = tonumber(immediateCount) or 0

    -- Geometry is cached briefly; live danger is never cached. A moving zombie
    -- therefore changes the preferred exit on every reflex pulse without paying
    -- for another flood-fill until the topology TTL or origin changes.
    local candidates = {}
    local threatPositions = {}
    for _, threat in ipairs(threats or {}) do
        local tx, ty, tz = tonumber(threat.x), tonumber(threat.y), tonumber(threat.z)
        if tx == nil then tx, ty, tz = U.position(threat.actor) end
        if tx ~= nil then
            threatPositions[#threatPositions + 1] = { x = tx, y = ty, z = tz or 0 }
        end
    end
    local destinationRadius = tonumber(U.config("combatRetreatDestinationThreatRadius")) or 5
    local destinationRadiusSq = destinationRadius * destinationRadius
    local corridorRadius = tonumber(U.config("combatRetreatCorridorThreatRadius")) or 4.5
    local corridorRadiusSq = corridorRadius * corridorRadius
    for _, raw in ipairs(cache.raw or {}) do
        local square = raw.square
        local sx, sy, sz = tonumber(raw.x), tonumber(raw.y), tonumber(raw.z)
        if sx == nil then sx, sy, sz = U.position(square) end
        local danger, corridorDanger, nearest = 0, 0, math.huge
        if sx ~= nil then
            for _, threat in ipairs(threatPositions) do
                local dx, dy, dz = sx - threat.x, sy - threat.y, (sz or 0) - threat.z
                local threatDistanceSq = dx * dx + dy * dy + dz * dz * 9
                if threatDistanceSq < nearest then nearest = threatDistanceSq end
                if threatDistanceSq <= destinationRadiusSq then danger = danger + 1 end

                -- An endpoint can look empty while its parent chain passes close
                -- enough to wake or collide with another zombie. Score the exact
                -- topology chain that validation will later approve, excluding
                -- only the unavoidable origin node beneath the companion.
                local node, corridorNearest, guard = raw, math.huge, 0
                while type(node) == "table" and guard < 16 do
                    if (tonumber(node.distance) or 0) > 0 then
                        local nx, ny, nz = tonumber(node.x), tonumber(node.y), tonumber(node.z)
                        if nx == nil then nx, ny, nz = U.position(node.square) end
                        if nx ~= nil then
                            local ndx, ndy = nx - threat.x, ny - threat.y
                            local ndz = (nz or 0) - threat.z
                            corridorNearest = math.min(corridorNearest,
                                ndx * ndx + ndy * ndy + ndz * ndz * 9)
                        end
                    end
                    node, guard = node.parent, guard + 1
                end
                if corridorNearest <= corridorRadiusSq then
                    corridorDanger = corridorDanger + 1
                end
            end
        end
        local cohesionDistance, cohesionScore, outsideCohesion = nil, 0, false
        if cohesionAnchor and sx ~= nil then
            local px, py, pz = U.position(cohesionAnchor)
            if px ~= nil and math.floor(pz or 0) == math.floor(sz or 0) then
                cohesionDistance = math.sqrt((sx - px) ^ 2 + (sy - py) ^ 2)
                local soft = tonumber(U.config("combatFollowRetreatSoftLeash")) or 10
                local hard = math.max(soft,
                    tonumber(U.config("combatFollowRetreatHardLeash")) or 14)
                local delta = (tonumber(currentCohesionDistance) or cohesionDistance)
                    - cohesionDistance
                cohesionScore = delta
                        * (tonumber(U.config("combatRetreatCohesionWeight")) or 8)
                    - math.max(0, cohesionDistance - soft)
                        * (tonumber(U.config("combatRetreatCohesionPenalty")) or 12)
                outsideCohesion = cohesionDistance > hard
                    and cohesionDistance >= (tonumber(currentCohesionDistance) or 0) - 0.25
            end
        end
        if raw.outdoors == nil then raw.outdoors = squareIsOutdoor(square) end
        candidates[#candidates + 1] = {
            square = square,
            topologyNode = raw,
            distance = raw.distance,
            traversalCost = raw.traversalCost,
            requiresNative = raw.requiresNative == true,
            danger = danger,
            corridorDanger = corridorDanger,
            outdoors = raw.outdoors,
            nearestThreatSq = nearest,
            cohesionDistance = cohesionDistance,
            outsideCohesion = outsideCohesion,
            score = (tonumber(raw.distance) or 0) * 3
                + math.min(nearest, 100) * 0.15 - danger * 20
                - corridorDanger
                    * (tonumber(U.config("combatRetreatCorridorDangerPenalty")) or 18)
                + cohesionScore - (outsideCohesion and 1000 or 0)
                + (raw.outdoors and 12 or 0)
                - math.max(0, (tonumber(raw.traversalCost) or 0)
                    - (tonumber(raw.distance) or 0)) * 0.5,
        }
    end
    table.sort(candidates, function(a, b) return a.score > b.score end)
    local limit = math.min(tonumber(U.config("perceptionExitLimit")) or 16,
        tonumber(U.config("escapeValidatedCandidateLimit")) or 4)
    local verified, attempts, rejected = {}, 0, false
    for _, candidate in ipairs(candidates) do
        if #verified >= limit or attempts >= limit then break end
        attempts = attempts + 1
        local valid = type(SC.Topology.validateEscapeNode) == "function"
            and SC.Topology.validateEscapeNode(actor, candidate.topologyNode, {})
        if valid == true then
            candidate.topologyNode = nil
            verified[#verified + 1] = candidate
        else
            rejected = true
        end
    end
    if rejected and #verified == 0 then
        cache.computedAt = current - ttl
        state.escapeTopology = cache
    end
    return verified, cache.exits or {}, {
        processed = cache.processed or 0,
        originKey = cache.originKey,
        signature = cache.signature,
        computedAt = cache.computedAt,
        candidateValidationAttempts = attempts,
    }
end

Senses._collectEscapeSquaresForTests = collectEscapeSquares

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

local function nextScanOffsets(state, radius, squareBudget)
    return scans().nextOffsets(state, radius, squareBudget)
end

Senses._nextScanOffsetsForTests = nextScanOffsets

local function newScanJob(state, actorSquare, originX, originY, originZ, radius, squareBudget)
    return scans().newJob(
        state, actorSquare, originX, originY, originZ, radius, squareBudget)
end

local function scanJobInvalid(job, originX, originY, originZ, radius, squareBudget)
    return scans().invalid(job, originX, originY, originZ, radius, squareBudget,
        util().config("perceptionScanRebaseDistance") or 2.0)
end

local function appendVisualCandidate(list, seen, actor, prior, discovered, urgent, priority)
    if actor == nil or seen[actor] then return end
    seen[actor] = true
    list[#list + 1] = {
        actor = actor,
        prior = prior,
        discovered = discovered == true,
        urgent = urgent == true,
        priority = priority == true,
    }
end

local function unpackVisualCandidate(value)
    if type(value) == "table" and value.visualCandidate == true then
        return value.actor, value.prior, value.discovered == true, value.urgent == true
    end
    if type(value) == "table" and value.actor ~= nil
        and (value.distanceSq ~= nil or value.visualValidatedAt ~= nil) then
        return value.actor, value, true, false
    end
    return value, nil, true, false
end

-- LOS checks are more expensive than candidate discovery. Keep a persistent
-- FIFO for deferred checks, reserve the current target and immediate contacts,
-- and append contacts checked this pulse behind the pending queue next pulse.
-- This makes a hard per-pulse budget fair instead of repeatedly validating the
-- same first N zombies in a crowded scene.
local function visualCandidateLists(state, currentSnapshot, discovered, combatTarget)
    local priority, ordinary = {}, {}
    local prioritySeen = setmetatable({}, { __mode = "k" })
    local ordinarySeen = setmetatable({}, { __mode = "k" })
    local priorByActor = setmetatable({}, { __mode = "k" })
    currentSnapshot = type(currentSnapshot) == "table" and currentSnapshot or {}

    local function remember(records)
        for _, record in ipairs(records or {}) do
            if record and record.actor then priorByActor[record.actor] = record end
        end
    end
    remember(currentSnapshot.threats)
    remember(currentSnapshot.stealthThreats)
    remember(currentSnapshot.immediateAttackers)

    -- The committed combat target is the one contact that must never wait for
    -- a crowded immediate list; Combat will independently prove LOS again
    -- before authorizing an action.
    if combatTarget ~= nil then
        appendVisualCandidate(priority, prioritySeen, combatTarget,
            priorByActor[combatTarget], false, false, true)
    end
    local deferredOrdinary = {}
    for _, entry in ipairs(state.visualValidationQueue or {}) do
        if entry.urgent == true
            or (entry.prior and immediateThreat(entry.prior,
                (util().config("immediateThreatRadius") or 2.25) ^ 2)) then
            appendVisualCandidate(priority, prioritySeen, entry.actor,
                priorByActor[entry.actor] or entry.prior,
                entry.discovered == true, true, true)
        else
            deferredOrdinary[#deferredOrdinary + 1] = entry
        end
    end
    -- Deferred urgent contacts lead the recycled immediate set. With more than
    -- the hard urgent cap this rotates the tail instead of starving contact 13.
    for _, record in ipairs(currentSnapshot.immediateAttackers or {}) do
        appendVisualCandidate(priority, prioritySeen, record.actor, record,
            false, true, true)
    end
    local nearest = currentSnapshot.nearestThreat
    if nearest and nearest.actor then
        appendVisualCandidate(priority, prioritySeen, nearest.actor, nearest,
            false, false, true)
    end

    local ordinaryDiscoveries = {}
    for _, value in ipairs(discovered or {}) do
        local actor, prior, wasDiscovered, urgent = unpackVisualCandidate(value)
        if urgent then
            appendVisualCandidate(priority, prioritySeen, actor,
                priorByActor[actor] or prior, wasDiscovered, true, true)
        else
            ordinaryDiscoveries[#ordinaryDiscoveries + 1] = {
                actor = actor, prior = prior, discovered = wasDiscovered,
            }
        end
    end

    local function appendOrdinary(actor, prior, wasDiscovered, urgent)
        if actor == nil or prioritySeen[actor] then return end
        local queueCap = math.max(16, math.min(128,
            math.floor(tonumber(util().config("perceptionVisualQueueHardCap")) or 64)))
        if #ordinary >= queueCap then return end
        appendVisualCandidate(ordinary, ordinarySeen, actor,
            priorByActor[actor] or prior, wasDiscovered, urgent, false)
    end
    -- Old deferred entries stay at the head. Contacts handled this pulse are
    -- re-appended from the current snapshot on the next one, behind this tail.
    for _, entry in ipairs(deferredOrdinary) do
        appendOrdinary(entry.actor, entry.prior,
            entry.discovered == true, entry.urgent == true)
    end
    for _, record in ipairs(currentSnapshot.stealthThreats or {}) do
        appendOrdinary(record.actor, record, false, false)
    end
    for _, record in ipairs(currentSnapshot.threats or {}) do
        appendOrdinary(record.actor, record, false, false)
    end
    for _, entry in ipairs(ordinaryDiscoveries) do
        appendOrdinary(entry.actor, entry.prior, entry.discovered, false)
    end
    return priority, ordinary
end

local function retainedVisualRecord(actor, prior, current, observerX, observerY, observerZ)
    local U = util()
    if type(prior) ~= "table" or prior.visible ~= true or prior.obstructed == true
        or not isActiveZombie(actor) then return nil end
    local validatedAt = tonumber(prior.visualValidatedAt)
    local retention = math.max(0,
        tonumber(U.config("perceptionVisualRetentionMs")) or 250)
    if validatedAt == nil or current - validatedAt > retention then return nil end
    local x, y, z = U.position(actor)
    if x == nil or math.floor(z or 0) ~= math.floor(observerZ or 0) then return nil end
    local dx, dy = x - observerX, y - observerY
    local distanceSq = dx * dx + dy * dy
    local radius = tonumber(U.config("perceptionRadius")) or 24
    if distanceSq > radius * radius then return nil end
    local record = U.copyShallow(prior)
    record.x, record.y, record.z = x, y, z
    record.square = U.squareOf(actor)
    record.distanceSq, record.distance = distanceSq, math.sqrt(distanceSq)
    record.visualDeferred, record.recentlyVisible = true, true
    return record
end

local function validateVisualCandidates(actor, player, actorSquare, state, currentSnapshot,
        discovered, threatLimit, immediateRadiusSq, current, combatTarget)
    local U = util()
    local set = threatSets().new(threatLimit, immediateRadiusSq,
        U.config("perceptionAttackCommitRadius") or 1.5)
    local heard, checks, urgentChecks, deferred = nil, 0, 0, 0
    local limit = math.max(4,
        math.floor(tonumber(U.config("perceptionVisualChecksPerSlice")) or 16))
    local urgentCap = math.max(4,
        math.floor(tonumber(U.config("perceptionImmediateVisualHardCap")) or 12))
    local deadline = U.nowMs() + (tonumber(U.config("perceptionVisualSliceMs")) or 1.0)
    local priority, ordinary = visualCandidateLists(
        state, currentSnapshot, discovered, combatTarget)
    local pending = {}
    local pendingCap = math.max(16, math.min(128,
        math.floor(tonumber(U.config("perceptionVisualQueueHardCap")) or 64)))
    local observerX, observerY, observerZ = U.position(actor)

    local function inspect(entry, forced)
        local zombie = entry.actor
        local urgent = entry.urgent == true
            or (entry.prior and immediateThreat(entry.prior, immediateRadiusSq))
        if (urgent and urgentChecks >= urgentCap)
            or (not forced and not urgent and (checks >= limit
                or (checks >= 4 and U.nowMs() >= deadline))) then
            if #pending < pendingCap then pending[#pending + 1] = entry end
            deferred = deferred + 1
            return
        end
        if not isActiveZombie(zombie) then return end
        checks = checks + 1
        if urgent then urgentChecks = urgentChecks + 1 end
        local record = threatRecord(actor, player, zombie, actorSquare)
        record.visualValidatedAt = current
        if record.visible and not record.obstructed then
            threatSets().add(set, record, entry.discovered)
        else
            local audible, activity = zombieAudible(actor, zombie, record)
            if audible then
                local candidate = heardThreatRecord(actor, zombie, record, current, activity)
                if not heard or candidate.strength > heard.strength then heard = candidate end
            end
        end
    end

    for _, entry in ipairs(priority) do inspect(entry, true) end
    for _, entry in ipairs(ordinary) do inspect(entry, false) end
    state.visualValidationQueue = #pending > 0 and pending or nil

    -- Keep only very recently proven contacts while their fair-queue turn is
    -- pending. The current target and melee contacts never rely on this grace;
    -- they are force-checked above. This avoids crowd-size flicker without
    -- turning old sightings into wall-penetrating omniscience.
    if observerX ~= nil then
        local retentionLimit = math.max(0, math.min(threatLimit,
            math.floor(tonumber(U.config("perceptionVisualRetentionLimit")) or 16)))
        for index = 1, math.min(#pending, retentionLimit) do
            local entry = pending[index]
            local retained = retainedVisualRecord(entry.actor, entry.prior, current,
                observerX, observerY, observerZ)
            if retained then threatSets().add(set, retained, false) end
        end
    end
    local result = threatSets().finish(set)
    result.visualChecks, result.visualDeferred = checks, deferred
    return result.threats, result.immediate, result.fenced, result.stealth,
        result.grounded, heard, result
end

local function liveThreatLists(actor, player, actorSquare, job, threatLimit,
        immediateRadiusSq, current, state, combatTarget)
    return validateVisualCandidates(actor, player, actorSquare, state,
        state.current, job.stealthThreats, threatLimit, immediateRadiusSq,
        current, combatTarget)
end

local function eachMovingObjectRotated(state, square, maximum, callback)
    local U = util()
    local objects, available = U.call(square, "getMovingObjects")
    if not available or objects == nil or not SC.NativeList then return 0 end
    local count = SC.NativeList.size(objects)
    if count <= 0 then return 0 end
    state.reflexObjectCursors = state.reflexObjectCursors
        or setmetatable({}, { __mode = "k" })
    local start = math.floor(tonumber(state.reflexObjectCursors[square]) or 0) % count
    local used = math.min(count, math.max(0, math.floor(tonumber(maximum) or count)))
    for offset = 0, used - 1 do
        local value, found = SC.NativeList.get(objects, (start + offset) % count)
        if found then callback(value) end
    end
    state.reflexObjectCursors[square] = (start + used) % count
    return used
end

function Senses.snapshot(actor, player, runtime)
    local U = util()
    if not U or not U.isValidActor(actor) then
        return {
            valid = false,
            threats = {}, immediateAttackers = {}, fencedThreats = {}, groundedThreats = {},
            heardThreats = {}, heardThreatCount = 0,
            sounds = {}, exits = {}, escapeSquares = {}, allies = {},
            protectedActors = {},
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
    local radius = U.config("perceptionRadius") or 24
    local squareBudget = U.config("perceptionSquareBudget") or 240
    local threatLimit = U.config("perceptionThreatLimit") or 32
    local immediateRadiusSq = (U.config("immediateThreatRadius") or 2.25) ^ 2

    local nativeCandidates, nativeMeta = scans().nativeCandidates(actor, state, radius,
        U.config("perceptionNativeCandidatesPerSlice") or 64,
        U.nowMs() + (tonumber(U.config("perceptionNativeSliceMs")) or 0.75))
    local job = state.scanJob
    local invalid, invalidReason, rebaseDistance = scanJobInvalid(
        job, originX, originY, originZ, radius, squareBudget)
    if nativeCandidates ~= nil then
        -- Native discovery needs no 240-square schedule allocation or rebasing;
        -- a moving observer keeps advancing the bounded native-list cursor.
        job = { offsets = {}, index = 1, scannedSquares = 0, outerSampled = 0,
            stealthThreats = {}, seen = {}, coverage = { native = true } }
    elseif invalid then
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
    if nativeCandidates == nil and SC.Performance and type(SC.Performance.claimUnits) == "function" then
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

    if nativeCandidates ~= nil then
        job.stealthThreats, job.seen = nativeCandidates,
            setmetatable({}, { __mode = "k" })
        processed = nativeMeta.processed or 0
        job.index = #job.offsets + 1
        state.nativeDiscovery = nativeMeta
    end
    while nativeCandidates == nil and processed < granted and job.index <= #job.offsets
        and #job.stealthThreats < threatLimit do
        local offset = job.offsets[job.index]
        job.index = job.index + 1
        processed = processed + 1
        inspectSquare(U.gridSquare(job.originX + offset.x, job.originY + offset.y,
            job.originZ + (offset.z or 0)), offset.band)
    end
    -- A saturated detail list ends this bounded job. Leaving its index parked
    -- would replay the same offsets forever and also freeze the coverage cursor.
    if #job.stealthThreats >= threatLimit then job.index = #job.offsets + 1 end

    local sliceComplete = job.index > #job.offsets or #job.stealthThreats >= threatLimit
    local threats, immediate, fenced, stealthThreats, groundedThreats, heard,
        threatMeta = liveThreatLists(
        actor, player, actorSquare, job, threatLimit, immediateRadiusSq, now,
        state, rootRuntime.combatTarget)
    local discoveryComplete = nativeMeta ~= nil
        and nativeMeta.complete == true and nativeMeta.freshComplete == true
        or nativeMeta == nil and sliceComplete
    local visualComplete = (tonumber(threatMeta.visualDeferred) or 0) == 0
        and state.visualValidationQueue == nil
    local complete = discoveryComplete and visualComplete
    local scanProgress
    if nativeMeta then
        local total = math.max(0, tonumber(nativeMeta.count) or 0)
        local pending = math.max(0, tonumber(nativeMeta.pending) or 0)
        scanProgress = total > 0 and math.max(0, math.min(1, 1 - pending / total))
            or (complete and 1 or 0)
    else
        scanProgress = #job.offsets > 0
            and math.min(1, (job.index - 1) / #job.offsets) or 1
    end

    local escapeSquares, exits, escapeMeta = collectEscapeSquares(
        actor, threats, state, now, #immediate, player)
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

    local relationshipsFresh = not state.allies
        or now - (state.alliesAt or 0) > 250
    local allies, protectedActors = state.allies, state.protectedActors
    if relationshipsFresh then
        allies, protectedActors = collectRelationships(actor, player)
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
        scanCoverage = job.coverage,
        scanComplete = complete,
        scanDiscoveryComplete = discoveryComplete,
        scanVisualComplete = visualComplete,
        scanProgress = scanProgress,
        scanRebaseCount = state.scanRebaseCount or 0,
        lastScanRebaseDistance = state.lastScanRebaseDistance,
        lastScanRebaseAt = state.lastScanRebaseAt,
        discoveryMode = nativeMeta and "native_cursor" or "grid_fallback",
        nativeDiscovery = nativeMeta,
        visualChecks = threatMeta.visualChecks or 0,
        visualDeferred = threatMeta.visualDeferred or 0,
        threats = threats,
        stealthThreats = stealthThreats,
        groundedThreats = groundedThreats,
        immediateAttackers = immediate,
        fencedThreats = fenced,
        threatCount = #threats,
        threatOverflow = threatMeta.threatOverflow,
        immediateCount = #immediate,
        immediateOverflow = threatMeta.immediateOverflow,
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
        allies = allies or {},
        protectedActors = protectedActors or {},
        -- Follow downtime is permitted only after the actor has actually
        -- entered a room. This field was consumed by decisions but was not
        -- previously populated, so outdoor and indoor idle were indistinct.
        indoors = actorRoomOk and actorRoom ~= nil,
    }
    snapshot.player = playerCondition(player, threats)
    snapshot.encircled = closeImmediateCount >= 3 or occupiedThreatSectors >= 3
        or (#escapeSquares == 0 and #threats >= 2)
    state.current = snapshot
    -- A full snapshot already performs the same bounded native discovery, LOS
    -- validation and escape refresh as the immediate pass. Satisfy this reflex
    -- interval here so Decision.update does not repeat all of that work in the
    -- same frame.
    state.nextReflexAt = now + math.max(25,
        tonumber(U.config("perceptionReflexIntervalMs")) or 100)
    state.allies, state.protectedActors, state.alliesAt =
        snapshot.allies, snapshot.protectedActors, now
    if complete then
        if nativeCandidates == nil then state.scanJob = nil end
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
    local discovered, discoveryMeta = scans().nativeCandidates(actor, state,
        U.config("perceptionRadius") or 24, U.config("perceptionNativeCandidatesPerSlice") or 64,
        U.nowMs() + (tonumber(U.config("perceptionNativeSliceMs")) or 0.75))
    if discoveryMeta then state.nativeDiscovery = discoveryMeta end
    local visualCandidates = {}
    local visualCandidateSeen = setmetatable({}, { __mode = "k" })
    local nearbyCandidateSeen = setmetatable({}, { __mode = "k" })
    local visualCandidateCap = math.max(16, math.min(96,
        math.floor(tonumber(U.config("perceptionReflexCandidateHardCap")) or 48)))
    local nearbyCandidateCap = math.max(8, math.min(48,
        math.floor(tonumber(U.config("perceptionReflexNearbyHardCap")) or 32)))
    local nearbyCandidates = 0
    for _, candidate in ipairs(discovered or {}) do
        if candidate and visualCandidateSeen[candidate] == nil
            and #visualCandidates < visualCandidateCap then
            visualCandidates[#visualCandidates + 1] = candidate
            visualCandidateSeen[candidate] = #visualCandidates
        end
    end

    local originX, originY = math.floor(ax), math.floor(ay)
    local reach = math.ceil(radius) + 1
    local squareOffsets = {}
    for dx = -reach, reach do
        for dy = -reach, reach do
            local sx, sy = originX + dx, originY + dy
            local nearestX = math.max(sx, math.min(ax, sx + 1))
            local nearestY = math.max(sy, math.min(ay, sy + 1))
            local boundsDx, boundsDy = nearestX - ax, nearestY - ay
            local boundsDistanceSq = boundsDx * boundsDx + boundsDy * boundsDy
            if boundsDistanceSq <= radiusSq then
                squareOffsets[#squareOffsets + 1] = {
                    x = sx, y = sy, distanceSq = boundsDistanceSq,
                }
            end
        end
    end
    table.sort(squareOffsets, function(left, right)
        if left.distanceSq == right.distanceSq then
            if left.x == right.x then return left.y < right.y end
            return left.x < right.x
        end
        return left.distanceSq < right.distanceSq
    end)
    local scanned, inspectedObjects = 0, 0
    local objectHardCap = math.max(32, math.min(256,
        math.floor(tonumber(U.config("perceptionReflexMovingObjectHardCap")) or 128)))
    local perSquareCap = math.max(8, math.min(96,
        math.floor(tonumber(U.config("perceptionReflexObjectsPerSquare")) or 48)))
    local squareCursor = math.max(1,
        math.floor(tonumber(state.reflexSquareCursor) or 1))
    if squareCursor > #squareOffsets then squareCursor = 1 end
    local visitedOffsets = 0
    while visitedOffsets < #squareOffsets and nearbyCandidates < nearbyCandidateCap
        and inspectedObjects < objectHardCap do
        local index = ((squareCursor + visitedOffsets - 1) % #squareOffsets) + 1
        local offset = squareOffsets[index]
        local square = U.gridSquare(offset.x, offset.y, az)
        visitedOffsets = visitedOffsets + 1
        if square then
            scanned = scanned + 1
            local allowance = math.min(perSquareCap, objectHardCap - inspectedObjects)
            local inspected = eachMovingObjectRotated(state, square, allowance, function(value)
                if nearbyCandidates >= nearbyCandidateCap
                    or nearbyCandidateSeen[value] ~= nil
                    or not isActiveZombie(value) then return end
                local vx, vy, vz = U.position(value)
                if vx ~= nil then
                    local dx, dy, dz = vx - ax, vy - ay, (vz or 0) - (az or 0)
                    if dx * dx + dy * dy + dz * dz * 9 <= radiusSq then
                        nearbyCandidateSeen[value] = true
                        nearbyCandidates = nearbyCandidates + 1
                        local urgent = {
                            visualCandidate = true,
                            actor = value,
                            discovered = true,
                            urgent = true,
                        }
                        local existing = visualCandidateSeen[value]
                        if existing ~= nil then
                            visualCandidates[existing] = urgent
                        elseif #visualCandidates < visualCandidateCap then
                            visualCandidates[#visualCandidates + 1] = urgent
                            visualCandidateSeen[value] = #visualCandidates
                        end
                    end
                end
            end)
            inspectedObjects = inspectedObjects + inspected
        end
    end
    if #squareOffsets > 0 then
        state.reflexSquareCursor = ((squareCursor + math.max(1, visitedOffsets) - 1)
            % #squareOffsets) + 1
    end

    local threats, immediate, fenced, stealthThreats, groundedThreats, heard,
        threatMeta = validateVisualCandidates(actor, player, actorSquare, state,
            snapshot, visualCandidates, threatLimit, immediateRadiusSq, now,
            rootRuntime.combatTarget)
    local visualChecks = threatMeta.visualChecks or 0
    local visualDeferred = threatMeta.visualDeferred or 0
    local added = threatMeta.added
    local visibleCount = threatMeta.visibleCount
    local immediateVisibleCount = threatMeta.immediateVisibleCount
    local escapeSquares, exits, escapeMeta = collectEscapeSquares(
        actor, threats, state, now, #immediate, player)
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
    snapshot.reflexVisualChecks = visualChecks
    snapshot.reflexVisualDeferred = visualDeferred
    snapshot.threats = threats
    snapshot.stealthThreats = stealthThreats
    snapshot.groundedThreats = groundedThreats
    snapshot.immediateAttackers = immediate
    snapshot.fencedThreats = fenced
    snapshot.threatCount = #threats
    snapshot.threatOverflow = threatMeta.threatOverflow
    snapshot.immediateCount = immediateVisibleCount
    snapshot.immediateOverflow = threatMeta.immediateOverflow
    snapshot.pressure = immediateVisibleCount * 1.5
        + math.max(0, math.min(threatLimit,
            visibleCount - immediateVisibleCount)) * 0.35
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
        scans().reset()
    end
end

return Senses
