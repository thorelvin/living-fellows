-- SPDX-License-Identifier: MIT
-- Explicit choke orders only. No scans, hooks or work while nobody guards one.
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.GuardPost = SC.GuardPost or {}
local Post = SC.GuardPost
local directions = { { 0, -1 }, { -1, 0 }, { 0, 1 }, { 1, 0 } }
local slots = { { 0, 0 }, { 1, 0 }, { 2, 0 }, { 2, -1 }, { 2, 1 },
    { 3, 0 }, { 3, -1 }, { 3, 1 }, { 4, 0 }, { 4, -1 }, { 4, 1 },
    { 2, -2 }, { 2, 2 }, { 3, -2 }, { 3, 2 }, { 4, -2 }, { 4, 2 } }
-- A rear defender in a one-wide file cannot strike past the first guard.
-- Use a checked shoulder behind the landing when the room permits it.
local stairSlots = { { 0, 0 }, { 1, -1 }, { 1, 1 }, { 1, 0 }, { 2, 0 },
    { 2, -1 }, { 2, 1 }, { 3, 0 }, { 3, -1 }, { 3, 1 } }
local wideStairSlots = { { 0, -1 }, { 0, 1 }, { 1, 0 }, { 2, 0 },
    { 2, -1 }, { 2, 1 }, { 3, 0 }, { 3, -1 }, { 3, 1 } }
local setbackSlots = { { 1, 0 }, { 2, 0 }, { 1, -1 }, { 1, 1 }, { 3, 0 },
    { 2, -1 }, { 2, 1 }, { 3, -1 }, { 3, 1 } }
local function U() return SC.GameplayUtil end

function Post.copySide(side)
    if type(side) ~= "table" or type(side.x) ~= "number" or type(side.y) ~= "number"
        or math.abs(side.x) + math.abs(side.y) ~= 1
        or side.x ~= math.floor(side.x) or side.y ~= math.floor(side.y) then return nil end
    return { x = side.x, y = side.y }
end

local function usable(square)
    if not square or not U().isSquareFree(square) or SC.Topology.squareHasStairs(square) then return false end
    return select(1, U().call(square, "TreatAsSolidFloor")) == true
end

local function topPiece(square)
    local top = false
    if square then U().squareObjects(square, function(object)
        if select(1, U().call(object, "isStairsObject")) == true
            and tostring((U().call(object, "getType"))):find("stairsT", 1, true) == 1 then
            top = true; return false
        end
    end, 16) end
    return top
end

function Post.detect(actor, anchor, savedSide)
    local x, y, z = U().position(anchor)
    if x == nil or not SC.Topology then return nil end
    x, y, z = math.floor(x), math.floor(y), math.floor(z or 0)
    local square = U().gridSquare(x, y, z)
    if not usable(square) then return nil end
    if z > 0 then
        for _, d in ipairs(directions) do
            if topPiece(U().gridSquare(x + d[1], y + d[2], z - 1)) then
                return { kind = "stairs", x = x, y = y, z = z, dx = -d[1], dy = -d[2] }
            end
        end
    end
    for _, d in ipairs(directions) do
        local neighbour = U().gridSquare(x + d[1], y + d[2], z)
        local edge = neighbour and SC.Topology.classifyEdge(actor, square, neighbour, {})
        local object = edge and edge.object
        if object and (U().instanceOf(object, "IsoDoor")
            or select(1, U().call(object, "isDoor")) == true) then
            local north, known = U().call(object, "getNorth")
            local ox, oy, oz = U().position(U().squareOf(object))
            if known and type(north) == "boolean" and ox ~= nil then
                local side = Post.copySide(savedSide)
                local ax, ay = U().position(actor)
                if not side and ax ~= nil then
                    side = north and { x = 0, y = ay >= oy and 1 or -1 }
                        or { x = ax >= ox and 1 or -1, y = 0 }
                end
                if side and (north and side.x == 0 or not north and side.y == 0) then
                    local px, py = math.floor(ox), math.floor(oy)
                    if side.x < 0 then px = px - 1 end
                    if side.y < 0 then py = py - 1 end
                    if usable(U().gridSquare(px, py, math.floor(oz or z))) then
                        return { kind = "door", x = px, y = py, z = math.floor(oz or z),
                            dx = side.x, dy = side.y }
                    end
                end
            end
        end
    end
end

local function matches(actor, post)
    local data = U().modData(actor)
    local side = data and Post.copySide(data.SC_GuardSide)
    return data and data.SC_Recruited == true and data.SC_Order == "guard"
        and side and side.x == post.dx and side.y == post.dy
        and data.SC_AnchorX == post.x and data.SC_AnchorY == post.y and data.SC_AnchorZ == post.z
end

local function slotSquare(actor, post, offset)
    local previous = U().gridSquare(post.x, post.y, post.z)
    for step = 1, offset[1] do
        local nextSquare = U().gridSquare(post.x + post.dx * step, post.y + post.dy * step, post.z)
        local edge = nextSquare and SC.Topology.classifyEdge(actor, previous, nextSquare, {})
        if not usable(nextSquare) or not edge or edge.traversable ~= true or edge.affordance ~= "open" then return nil end
        previous = nextSquare
    end
    local sign = offset[2] < 0 and -1 or 1
    for _ = 1, math.abs(offset[2]) do
        local x, y = U().position(previous)
        local nextSquare = U().gridSquare(x - post.dy * sign, y + post.dx * sign, post.z)
        local edge = nextSquare and SC.Topology.classifyEdge(actor, previous, nextSquare, {})
        if not usable(nextSquare) or not edge or edge.traversable ~= true or edge.affordance ~= "open" then return nil end
        previous = nextSquare
    end
    return previous
end

-- Two long melee weapons may hold both sides of a landing's incoming column.
local function wideLanding(actor, post, members)
    local wide = post.kind == "stairs" and #members >= 2 and slotSquare(actor, post, { 0, -1 })
        and slotSquare(actor, post, { 0, 1 })
    if wide then
        for rank = 1, 2 do
            local weapon = select(1, U().call(members[rank], "getPrimaryHandItem"))
            local _, reach = SC.Combat.meleeRange(members[rank], weapon)
            local condition = select(1, U().call(weapon, "getCondition"))
            if not weapon or select(1, U().call(weapon, "isRanged")) == true
                or (tonumber(condition) or 0) <= 0
                or (tonumber(reach) or 0) < 1.2 then wide = false; break end
        end
    end
    return wide and true or false
end

-- Native references remain in the actor's existing runtime, never in its order.
function Post.forActor(actor, runtime, commands, now)
    local data = U().modData(actor)
    local side = data and Post.copySide(data.SC_GuardSide)
    if not data or data.SC_Order ~= "guard" or not side
        or commands and commands.temporaryStay == true then
        if runtime then runtime.guardPost = nil end
        return nil
    end
    runtime = runtime or U().actorState(actor)
    now = now or U().nowMs()
    local old = runtime.guardPost
    if old and old.insetUntil and now >= old.insetUntil then old.inset, old.insetUntil, old.refreshAt = nil, nil, 0 end
    local serial = tonumber(data.SC_CommandSerial) or 0
    local revision = SC.Registry.version and SC.Registry.version() or 0
    if old and old.serial == serial and old.revision == revision and now < old.refreshAt then return old end
    local post = Post.detect(actor, { x = data.SC_AnchorX, y = data.SC_AnchorY, z = data.SC_AnchorZ }, side)
    if not post then
        -- A removed door, unloaded landing or newly blocked post is not
        -- permission to start the ordinary five-metre patrol.
        local blocked = old and old.serial == serial and old or { serial = serial }
        blocked.post = { x = data.SC_AnchorX, y = data.SC_AnchorY, z = data.SC_AnchorZ,
            dx = side.x, dy = side.y, kind = "blocked" }
        blocked.position, blocked.refreshAt, blocked.revision = nil, now + 250, revision
        runtime.guardPost = blocked
        return blocked
    end
    local state = old and old.serial == serial and old or { serial = serial }
    state.post, state.revision, state.refreshAt = post, revision, now + 250
    state.position, state.rank = nil, nil
    local members = {}
    for _, peer in ipairs(SC.Registry.living()) do
        if matches(peer, post) then
            members[#members + 1] = peer
            if #members >= 16 then break end
        end
    end
    table.sort(members, function(a, b) return tostring(U().idOf(a)) < tostring(U().idOf(b)) end)
    local wide = wideLanding(actor, post, members)
    local cursor = 1
    for rank, peer in ipairs(members) do
        local square
        repeat
            local candidates = state.inset and setbackSlots or wide and wideStairSlots
                or post.kind == "stairs" and stairSlots or slots
            if not candidates[cursor] then break end
            square = slotSquare(peer, post, candidates[cursor]); cursor = cursor + 1
        until square
        if peer == actor then
            state.rank = rank
            if square then
                local px, py, pz = U().position(square)
                state.position = { x = px, y = py, z = pz }
            end
            break
        end
    end
    runtime.guardPost = state
    return state
end

-- A climber only becomes attackable near the landing lip. Leave weapon room
-- on that same square, away from the slope, instead of crowding the last step.
function Post.point(state)
    local p = state and state.position
    if not p then return nil end
    local inset = state.post and state.post.kind == "stairs" and state.rank == 1 and p.x == state.post.x and p.y == state.post.y
        and not state.inset and 0.35 or 0
    return { x = p.x + 0.5 + (state.post and state.post.dx or 0) * inset,
        y = p.y + 0.5 + (state.post and state.post.dy or 0) * inset, z = p.z }
end

-- The middle of the door opening, on the edge between the post square and the
-- approach side.
local function doorMouth(post)
    return post.x + 0.5 - post.dx * 0.5, post.y + 0.5 - post.dy * 0.5
end

-- Beyond the door edge, on the side the zombies come from.
function Post.beyondDoor(post, x, y)
    if not post or post.kind ~= "door" or x == nil then return false end
    local mx, my = doorMouth(post)
    return (x - mx) * post.dx + (y - my) * post.dy < -0.05
end

function Post.atPosition(actor, state)
    local p = Post.point(state)
    local x, y, z = U().position(actor)
    if not p or x == nil or math.floor(z or 0) ~= p.z then return false end
    local radius = state.inset and 0.3 or state.post.kind == "stairs"
        and math.min(0.3, U().config("guardChokeHoldRadius") or 0.7) or U().config("guardChokeHoldRadius") or 0.7
    if state.post.kind == "door" and state.rank == 1 then
        -- The front guard must stay in line with the opening. Off to one side,
        -- its swings cross the door jamb and land nowhere (0.27.16 live run),
        -- although it is still well inside the hold radius.
        local along = (x - p.x) * state.post.dx + (y - p.y) * state.post.dy
        local lateral = math.abs((x - p.x) * state.post.dy - (y - p.y) * state.post.dx)
        return lateral <= 0.3 and along >= -0.35 and along <= radius
    end
    return (x - p.x)^2 + (y - p.y)^2 <= radius^2
end

-- A failed stair exchange temporarily opens the landing for the climber.
-- Shift the whole line so the second guard does not occupy the first's retreat.
function Post.stairSetback(actor, post)
    for _, offset in ipairs(setbackSlots) do
        local square = slotSquare(actor, post, offset)
        if square then return square end
    end
end

function Post.stairInset(actor, runtime, depth, now)
    local own = Post.forActor(actor, runtime, nil, now)
    if not own or own.post.kind ~= "stairs" then return false end
    local changed, fits = {}, true
    for _, record in ipairs(SC.Registry.records()) do
        if record.actor and matches(record.actor, own.post) then
            record.runtime = record.runtime or {}
            local state = Post.forActor(record.actor, record.runtime, nil, now)
            changed[#changed + 1] = { actor = record.actor, runtime = record.runtime,
                inset = state.inset, untilAt = state.insetUntil }
            state.inset, state.insetUntil, state.refreshAt = depth, now + 15000, 0
            if not Post.forActor(record.actor, record.runtime, nil, now).position then fits = false end
        end
    end
    if not fits then
        for _, old in ipairs(changed) do
            local state = old.runtime.guardPost
            state.inset, state.insetUntil, state.refreshAt = old.inset, old.untilAt, 0
            Post.forActor(old.actor, old.runtime, nil, now)
        end
    end
    return fits
end

-- A door lets one zombie through at a time. The rest queue outside, where
-- they cannot reach the front guard or surround it, however close they stand.
-- Count the one in the opening (and a second only once it is in the opening
-- too); keep the full list for routes, strikes and the squad forecast. A
-- zombie staggered just through the opening is still the head of that queue;
-- only one well inside the room is a breach.
local DOOR_OPENING = 1.1

local function inOpening(post, x, y)
    local mx, my = doorMouth(post)
    return Post.beyondDoor(post, x, y) or (x - mx)^2 + (y - my)^2 <= DOOR_OPENING^2
end

local function doorView(actor, state, snapshot)
    if type(state.rank) ~= "number" or not Post.atPosition(actor, state) or not SC.CombatThreatModel then return snapshot end
    local ax, ay, az = U().position(actor)
    local mx, my = doorMouth(state.post)
    local personal, outside = {}, {}
    for index, threat in ipairs(snapshot.threats or {}) do
        -- Never reduce pressure on incomplete or unexpectedly large observations.
        if index > 32 then return snapshot end
        local facts = SC.ZombieFacts.get(threat.actor)
        if facts.zombie and not facts.gone and math.floor(facts.z) == math.floor(az)
            and inOpening(state.post, facts.x, facts.y) then
            outside[#outside + 1] = { threat = threat, d2 = (facts.x - mx)^2 + (facts.y - my)^2 }
        else personal[#personal + 1] = threat end
    end
    table.sort(outside, function(a, b) return a.d2 < b.d2 end)
    local queued, queuedCount = {}, 0
    for index, row in ipairs(outside) do
        if index == 1 or index == 2 and row.d2 <= 0.8^2 then personal[#personal + 1] = row.threat
        else queued[row.threat.actor], queuedCount = true, queuedCount + 1 end
    end
    if queuedCount == 0 then return snapshot end
    local reachable = SC.CombatThreatModel.reachable(personal, ax, ay, az)
        or { immediate = 0, close = 0, occupied = 0 }
    local view = {}
    for key, value in pairs(snapshot) do view[key] = value end
    view.doorQueuedThreats = queued
    view.reachableImmediateCount, view.immediateCount, view.closeImmediateCount =
        reachable.immediate, reachable.immediate, reachable.immediate
    view.reachableCloseCount, view.closeThreatCount = reachable.close, reachable.close
    view.reachableThreatSectors, view.occupiedThreatSectors = reachable.occupied, reachable.occupied
    view.localPressure = SC.CombatThreatModel.localPressure(reachable.immediate, reachable.close, reachable.immediate)
    view.directionalPressure = reachable.immediate * 1.8
        + math.max(0, reachable.close - reachable.immediate) * 0.55
        + math.max(0, reachable.occupied - 1) * 0.6
    -- A line queued through one opening cannot surround anyone.
    view.encircled = snapshot.encircled == true and reachable.surrounded == true
    return view
end

-- Holding a door with at most two zombies able to reach the front guard, all
-- of them in or beyond the opening, is a covered position like a stair top.
function Post.coveredDoor(actor, state, snapshot)
    if not state or state.withdrawn or not state.post or state.post.kind ~= "door"
        or not state.position or not Post.atPosition(actor, state) then return false end
    local ax, ay, az = U().position(actor)
    local count = 0
    for index, threat in ipairs(snapshot.threats or {}) do
        if index > 32 then return false end
        local facts = SC.ZombieFacts.get(threat.actor)
        if facts.zombie and not facts.gone and (facts.posture ~= "downed" or facts.gettingUp)
            and math.floor(facts.z) == math.floor(az) and threat.obstructed ~= true
            and (facts.x - ax)^2 + (facts.y - ay)^2 <= (U().config("combatCloseThreatRadius") or 4.5)^2 then
            if not inOpening(state.post, facts.x, facts.y) then return false end
            if not (snapshot.doorQueuedThreats and snapshot.doorQueuedThreats[threat.actor]) then
                count = count + 1
            end
        end
    end
    return count > 0 and count <= 2
end

-- A front guard pushed out of the door line steps back into it, even with a
-- zombie close by, as long as the spot is not in body contact with that zombie
-- and the step crosses no other one.
function Post.realign(actor, state, snapshot, target)
    if not state or state.withdrawn or not state.post or state.post.kind ~= "door"
        or state.rank ~= 1 or Post.atPosition(actor, state) then return nil end
    local p = Post.point(state)
    local ax, ay, az = U().position(actor)
    if not p or not ax or math.floor(az or 0) ~= p.z or U().distance(actor, p) > 1.25 then return nil end
    local tx, ty = U().position(target and target.actor)
    if tx and (p.x - tx)^2 + (p.y - ty)^2 < 0.6^2 then return nil end
    local dx, dy = p.x - ax, p.y - ay
    local len2 = dx * dx + dy * dy
    for index, threat in ipairs(snapshot.threats or {}) do
        if index > 32 then break end
        local ox, oy = U().position(threat.actor)
        if ox and threat.actor ~= (target and target.actor) and len2 > 0.0001 then
            local t = math.max(0, math.min(1, ((ox - ax) * dx + (oy - ay) * dy) / len2))
            if (ax + t * dx - ox)^2 + (ay + t * dy - oy)^2 < 0.6^2 then return nil end
        end
    end
    if not usable(U().gridSquare(state.position.x, state.position.y, p.z))
        or not SC.Navigation.openSegment(actor, p.x, p.y, p.z) then return nil end
    local accepted, reason = U().move(actor, "walk", { action = "return_to_guard",
        target = target and target.actor, keepFacing = target ~= nil, weaponReady = true,
        microSteered = true, movementTarget = true, targetPosition = p,
        dx = dx, dy = dy, movementArrivalTolerance = 0.08, movementTargetTtlMs = 500 })
    return accepted, accepted and "guard_door_realign" or reason
end

-- A covered stair entrance differs from an open indoor fight only while all
-- standing contacts remain on its approach side.
-- Keep the complete physical observation for routes, strikes and squad forecasts.
-- A zombie committed to another fit guard is not also this guard's personal
-- attacker until it reaches body contact. Reconsider on every combat update.
function Post.combatView(actor, player, state, snapshot)
    if state and not state.withdrawn and state.post and state.post.kind == "door" and state.position then
        return doorView(actor, state, snapshot)
    end
    if not state or state.withdrawn or state.post.kind ~= "stairs" or not state.position
        or not SC.CombatThreatModel or not Post.atPosition(actor, state) then return snapshot end
    local ax, ay, az = U().position(actor)
    local peers, peerCount = {}, 0
    for index, ally in ipairs(snapshot.allies or {}) do
        if index > 16 then break end
        local peer = ally.actor
        if peer and peer ~= actor and peer ~= player and U().isCompanion(peer)
            and U().isValidActor(peer) and U().nativeHealth(peer) >= 85
            and U().sameFloor(actor, peer) and matches(peer, state.post)
            and U().distance(actor, peer) <= 3 then peers[peer], peerCount = true, peerCount + 1 end
    end
    if peerCount == 0 then return snapshot end
    local personal, shared, sharedCount = {}, {}, 0
    for index, threat in ipairs(snapshot.threats or {}) do
        -- Never reduce pressure on incomplete or unexpectedly large observations.
        if index > 32 then return snapshot end
        local facts = SC.ZombieFacts.get(threat.actor)
        if facts.zombie and not facts.gone and peers[facts.target]
            and (facts.x - ax)^2 + (facts.y - ay)^2 > 0.9^2
            and U().distance(facts.target, threat.actor) < U().distance(actor, threat.actor) then
            shared[threat.actor], sharedCount = true, sharedCount + 1
        else personal[#personal + 1] = threat end
    end
    if sharedCount == 0 then return snapshot end
    local reachable = SC.CombatThreatModel.reachable(personal, ax, ay, az)
        or { immediate = 0, close = 0, occupied = 0 }
    local view = {}
    for key, value in pairs(snapshot) do view[key] = value end
    view.stairSharedThreats = shared
    view.reachableImmediateCount, view.immediateCount, view.closeImmediateCount =
        reachable.immediate, reachable.immediate, reachable.immediate
    view.reachableCloseCount, view.closeThreatCount = reachable.close, reachable.close
    view.reachableThreatSectors, view.occupiedThreatSectors = reachable.occupied, reachable.occupied
    view.localPressure = SC.CombatThreatModel.localPressure(reachable.immediate, reachable.close, reachable.immediate)
    view.directionalPressure = reachable.immediate * 1.8
        + math.max(0, reachable.close - reachable.immediate) * 0.55
        + math.max(0, reachable.occupied - 1) * 0.6
    -- Keep encirclement, the complete threat list and the already-built squad
    -- plan: sharing a contact never makes its physical position disappear.
    return view
end

function Post.coveredStair(actor, state, snapshot)
    if not state or state.withdrawn or state.post.kind ~= "stairs" or not state.position then return false end
    local ax, ay, az = U().position(actor)
    local p = state.position
    if not ax or math.floor(az or 0) ~= p.z
        or (ax - p.x - 0.5)^2 + (ay - p.y - 0.5)^2 > (U().config("guardChokeHoldRadius") or 0.7)^2 then return false end
    local count = 0
    for index, threat in ipairs(snapshot.threats or {}) do
        if index > 32 then return false end
        local facts = SC.ZombieFacts.get(threat.actor)
        if facts.zombie and not facts.gone and (facts.posture ~= "downed" or facts.gettingUp)
            and math.floor(facts.z) == math.floor(az) and threat.obstructed ~= true
            and (facts.x - ax)^2 + (facts.y - ay)^2 <= (U().config("combatCloseThreatRadius") or 4.5)^2 then
            -- The protected half of the landing must still be clear.
            if (facts.x - ax) * state.post.dx + (facts.y - ay) * state.post.dy > 0.1 then return false end
            if not (snapshot.stairSharedThreats and snapshot.stairSharedThreats[threat.actor]) then
                count = count + 1
            end
        end
    end
    return count > 0 and count <= 2
end

-- Fixed posts still need a little footwork when a zombie crowds the weapon.
-- Keep the endpoint inside the existing hold radius, with no chase or slope.
function Post.combatStep(actor, state, snapshot, target, action)
    local p = state.position
    local ax, ay, az = U().position(actor)
    if not p or not ax or math.floor(az or 0) ~= p.z or not U().sameFloor(actor, target.actor) then return nil end
    local radius = math.max(0.1, (state.inset and 0.3 or U().config("guardChokeHoldRadius") or 0.7) - 0.05)
    local cx, cy = p.x + 0.5, p.y + 0.5
    if (ax - cx)^2 + (ay - cy)^2 > (radius + 0.1)^2 then return nil end
    local dx, dy = action.moveX, action.moveY
    if not dx then dx, dy = SC.Navigation.combatVector(actor, target.actor, action.kind, snapshot) end
    if not dx or not dy then return nil end
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 0.001 then return nil end
    local x, y = ax + dx / length * 0.45, ay + dy / length * 0.45
    local offset = math.sqrt((x - cx)^2 + (y - cy)^2)
    if offset > radius then x, y = cx + (x - cx) / offset * radius, cy + (y - cy) / offset * radius end
    if (x - ax)^2 + (y - ay)^2 < 0.08^2
        or SC.Combat.atStairs({ x = x, y = y, z = p.z }) then return nil end
    local square = U().gridSquare(math.floor(x), math.floor(y), p.z)
    if not usable(square) or not SC.Navigation.openSegment(actor, x, y, p.z)
        or not SC.CombatSquad.safePosition(actor, target.actor, x, y, p.z, snapshot, U().nowMs()) then return nil end
    local accepted, reason = U().move(actor, "walk", { action = action.kind == "kite" and "lateral_kite"
        or action.kind == "approach" and "combat_approach" or "backstep",
        target = target.actor, awayFrom = target.actor, dx = x - ax, dy = y - ay,
        keepFacing = true, weaponReady = true, microSteered = true,
        movementTarget = true, targetPosition = { x = x, y = y, z = p.z },
        movementArrivalTolerance = 0.08, movementTargetTtlMs = 400 })
    return accepted, accepted and "guard_combat_step" or reason
end

function Post.move(actor, state, snapshot)
    local p = state and state.position
    if not p then U().stop(actor) return true, "guard_choke_no_room" end
    if Post.atPosition(actor, state) then
        if not U().stop(actor) then return false, "tactical_stop_rejected" end
        local post = state.post
        local warned = #(snapshot.stairIncoming or {}) > 0
        local faced = U().move(actor, "walk", { action = warned and "ready_weapon" or "face_alert", stableFacing = true,
            targetPosition = { x = post.x + 0.5 - post.dx * 2, y = post.y + 0.5 - post.dy * 2, z = p.z } })
        return faced == true, "guard_choke_holding"
    end
    local point = Post.point(state)
    if state.rank == 1 and (state.post.kind == "stairs" and not state.inset or state.post.kind == "door")
        and U().distance(actor, point) <= 1.25
        and SC.Navigation.openSegment(actor, point.x, point.y, point.z) then
        local accepted, why = U().move(actor, "walk", { action = "return_to_guard",
            targetPosition = point, movementTarget = true, movementArrivalTolerance = 0.08,
            dx = point.x - select(1, U().position(actor)), dy = point.y - select(2, U().position(actor)),
            movementTargetTtlMs = 750 })
        return accepted, accepted and "guard_landing_align" or why
    end
    return SC.Navigation.request(actor, U().gridSquare(p.x, p.y, p.z), state.auto and "jog" or "walk", {
        action = "return_to_guard", snapshot = snapshot, arrivalDistance = state.post.kind == "stairs" and 0.25 or 0.65, requireSameSquare = true,
    })
end

-- Automatic safe ground (0.27.24) ---------------------------------------------
-- While the group gives ground and the player stands within a few metres of a
-- doorway or the top of a staircase, the followers take that choke in front of
-- the player instead of backing off in the open. Only the player's own floor
-- is searched, only around the player, at most once a second, so companions
-- never lead the player anywhere and never go upstairs on their own.

local function ownsDoor(square)
    local owns = false
    if square then U().squareObjects(square, function(object)
        if U().instanceOf(object, "IsoDoor") or select(1, U().call(object, "isDoor")) == true then
            owns = true; return false
        end
    end, 16) end
    return owns
end

-- The post still shields the player: the player stays on its protected side
-- and close to it, every standing zombie near it is on the approach side (or
-- only just through the opening, within slack metres of it), and at least one
-- zombie is actually coming that way.
local function shields(post, plan, player, slack)
    local px, py, pz = U().position(player)
    if px == nil or math.floor(pz or 0) ~= post.z then return false end
    local keep = tonumber(U().config("combatSafeGroundKeepRadius")) or 5
    if (px - post.x - 0.5)^2 + (py - post.y - 0.5)^2 > keep * keep then return false end
    if post.kind == "door" and Post.beyondDoor(post, px, py) then return false end
    local coming = 0
    for index, threat in ipairs(plan.threats or {}) do
        if index > 64 then return false end
        if threat.stairIncoming then
            if post.kind == "stairs" then coming = coming + 1 end
        elseif threat.x and (threat.x - post.x - 0.5)^2 + (threat.y - post.y - 0.5)^2 <= 64 then
            if post.kind ~= "door" then return false end
            local mx, my = doorMouth(post)
            if not Post.beyondDoor(post, threat.x, threat.y)
                and (threat.x - mx)^2 + (threat.y - my)^2 > slack * slack then return false end
            coming = coming + 1
        end
    end
    return coming > 0
end

-- A route that passes a standing zombie on the near side of the choke is no
-- route to safe ground.
local function routeClear(member, post, plan)
    local tx, ty = post.x + 0.5, post.y + 0.5
    local dx, dy = tx - member.x, ty - member.y
    local len2 = dx * dx + dy * dy
    -- Already at the choke: the zombie in the opening is the fight, not a
    -- blocked route.
    if len2 <= 1.5 * 1.5 then return true end
    for index, threat in ipairs(plan.threats or {}) do
        if index > 64 then return false end
        if not threat.stairIncoming and threat.x
            and not (post.kind == "door" and inOpening(post, threat.x, threat.y)) then
            local t = math.max(0, math.min(1, ((threat.x - member.x) * dx + (threat.y - member.y) * dy) / len2))
            if (member.x + t * dx - threat.x)^2 + (member.y + t * dy - threat.y)^2 < 0.9^2 then return false end
        end
    end
    return true
end

-- Positions for the followers that can reach the post, with the same slot
-- pattern as "Guard here", never on the player's own square. Unlike a guard
-- order, the fight is already coming: the follower nearest the choke takes
-- the front, and that order holds for as long as the safe ground does.
local function claim(post, plan, player, since, order)
    local followers, distance = {}, {}
    for _, member in ipairs(plan.members or {}) do
        local data = U().modData(member.actor)
        if member.capable and type(data) == "table" and data.SC_Recruited == true
            and (data.SC_Order == "follow" or data.SC_Order == "regroup")
            and math.floor(member.z or 0) == post.z and routeClear(member, post, plan) then
            followers[#followers + 1] = member.actor
            distance[member.actor] = (member.x - post.x - 0.5)^2 + (member.y - post.y - 0.5)^2
        end
        if #followers >= 16 then break end
    end
    if #followers == 0 then return nil end
    local place = {}
    for index, actor in ipairs(order or {}) do place[actor] = index end
    table.sort(followers, function(a, b)
        local pa, pb = place[a], place[b]
        if pa and pb then return pa < pb end
        if pa or pb then return pa ~= nil end
        if distance[a] ~= distance[b] then return distance[a] < distance[b] end
        return tostring(U().idOf(a)) < tostring(U().idOf(b))
    end)
    local avoid = U().squareOf(player)
    local candidates = wideLanding(followers[1], post, followers) and wideStairSlots
        or post.kind == "stairs" and stairSlots or slots
    local seats, cursor, seated = setmetatable({}, { __mode = "k" }), 1, 0
    for rank, peer in ipairs(followers) do
        local square
        repeat
            if not candidates[cursor] then break end
            square = slotSquare(peer, post, candidates[cursor]); cursor = cursor + 1
            if square and square == avoid then square = nil end
        until square
        if not square then break end
        local x, y, z = U().position(square)
        seats[peer], seated = { rank = rank, x = x, y = y, z = z }, seated + 1
    end
    if seated == 0 then return nil end
    return { post = post, since = since, seats = seats, order = followers }
end

-- Called by the squad plan on each rebuild. Keeps the previous plan's safe
-- ground while it still shields the player; otherwise, when the group must
-- give ground, looks for one around the player.
function Post.autoPick(plan, previous, player, now)
    if type(plan) ~= "table" or not player or not U().isValidActor(player) then return nil end
    local prior = previous and previous.safeGround
    if prior and (plan.mode == "give_ground" or plan.mode == "engage")
        and shields(prior.post, plan, player, 2.0) then
        plan.safeGroundSearchAt = previous.safeGroundSearchAt
        return claim(prior.post, plan, player, prior.since, prior.order)
    end
    -- Giving ground comes too late at a door: the zombies queued outside do
    -- not count as arrivals until they are through it (0.27.24 live run). So
    -- a choke is also taken while the group is still engaging, as soon as
    -- there are at least as many zombies as fit fighters. shields() then
    -- requires every one of them to be coming through it.
    local outnumbered = plan.mode == "engage" and #(plan.threats or {}) >= math.max(1, tonumber(plan.capable) or 0)
    if plan.mode ~= "give_ground" and plan.wanted ~= "give_ground" and not outnumbered then return nil end
    local searchAt = previous and tonumber(previous.safeGroundSearchAt) or 0
    plan.safeGroundSearchAt = searchAt
    if now < searchAt then return nil end
    plan.safeGroundSearchAt = now + (tonumber(U().config("combatSafeGroundSearchMs")) or 1000)
    local px, py, pz = U().position(player)
    if px == nil then return nil end
    pz = math.floor(pz or 0)
    if pz ~= math.floor(plan.z or 0) then return nil end
    local radius = tonumber(U().config("combatSafeGroundRadius")) or 4
    local reach, bx, by = math.ceil(radius), math.floor(px), math.floor(py)
    local best, bestD2
    for dx = -reach, reach do for dy = -reach, reach do
        local x, y = bx + dx, by + dy
        local square = U().gridSquare(x, y, pz)
        local anchors = {}
        if square and ownsDoor(square) then anchors[1] = square end
        if pz > 0 and topPiece(U().gridSquare(x, y, pz - 1)) then
            for _, d in ipairs(directions) do anchors[#anchors + 1] = U().gridSquare(x + d[1], y + d[2], pz) end
        end
        for _, anchor in ipairs(anchors) do
            local post = anchor and Post.detect(player, anchor)
            if post and post.z == pz then
                local d2 = (post.x + 0.5 - px)^2 + (post.y + 0.5 - py)^2
                if d2 <= radius * radius and (bestD2 == nil or d2 < bestD2
                        or d2 == bestD2 and (post.x < best.x or post.x == best.x and post.y < best.y))
                    and shields(post, plan, player, DOOR_OPENING) then
                    best, bestD2 = post, d2
                end
            end
        end
    end end
    return best and claim(best, plan, player, now) or nil
end

-- The combat-side post for one follower, from its squad view.
function Post.autoForActor(actor, squadView, commands)
    local ground = type(squadView) == "table" and squadView.safeGround or nil
    local seat = ground and ground.seat
    if not seat or commands and commands.temporaryStay == true then return nil end
    return { auto = true, post = ground.post, rank = seat.rank, serial = ground.since,
        position = { x = seat.x, y = seat.y, z = seat.z } }
end

-- Zombies this door guard can see in or beyond the opening, within 10 m of
-- it. The squad forecast leaves out a queue standing a few metres outside
-- (it has no time to reach anyone yet), so twelve at a door looked like five
-- (0.27.24 live run): the guards held 15 s against a door they could not keep.
function Post.doorQueue(actor, runtime, state)
    if not state or not state.post or state.post.kind ~= "door" then return 0 end
    local snapshot = runtime and runtime.senses and runtime.senses.current
    local _, _, az = U().position(actor)
    local mx, my = doorMouth(state.post)
    local count = 0
    for index, threat in ipairs(type(snapshot) == "table" and snapshot.threats or {}) do
        if index > 64 then break end
        local x, y, z = tonumber(threat.x), tonumber(threat.y), tonumber(threat.z)
        if x and y and threat.visible ~= false and threat.posture ~= "downed"
            and (z == nil or az == nil or math.floor(z) == math.floor(az))
            and inOpening(state.post, x, y) and (x - mx)^2 + (y - my)^2 <= 100 then
            count = count + 1
        end
    end
    return count
end

function Post.observe(actor, runtime, plan, now)
    local state = runtime and runtime.guardPost
    if not state then return false end
    -- The squad's numerical capacity cannot promise coverage from a guard
    -- whose own combat pass keeps withdrawing. Preserve brief footwork, then
    -- release the shared choke through the same checked Retreat order.
    local combat = SC.Combat and SC.Combat.peek and SC.Combat.peek(actor)
    local risk = combat and combat.overrun
    local personalWithdrawal = combat and combat.retreating == true and risk and risk.overrun == true
    -- A queue at the door counts like arrivals: more than the guards hold plus
    -- the usual margin is a withdrawal, four more is an immediate one.
    local capacity = plan and tonumber(plan.capacity) or nil
    local queue = Post.doorQueue(actor, runtime, state)
    local margin = tonumber(U().config("combatSquadDisengageMargin")) or 2
    local squadWithdrawal = plan and plan.mode == "disengage"
        or capacity ~= nil and queue > capacity + margin
    -- The squad's judgement flickers while a crowd shuffles in and out of
    -- sight: a calm shorter than guardChokeCalmMs does not restart its count.
    -- A guard's own retreat is footwork and restarts as soon as it stops.
    if squadWithdrawal then state.squadSince, state.calmSince = state.squadSince or now, nil
    elseif state.squadSince then
        state.calmSince = state.calmSince or now
        if now - state.calmSince >= (U().config("guardChokeCalmMs") or 1000) then
            state.squadSince, state.calmSince = nil, nil
        end
    end
    if personalWithdrawal then state.disengageSince = state.disengageSince or now
    else state.disengageSince = nil end
    if squadWithdrawal or personalWithdrawal then
        local forecast = math.max(plan and tonumber(plan.forecast) or 0, queue)
        local overwhelming = squadWithdrawal and forecast >= (capacity or math.huge) + 4
            or personalWithdrawal and (risk.cause == "health" or risk.cause == "encircled")
        local held = math.max(state.squadSince and now - state.squadSince or 0,
            state.disengageSince and now - state.disengageSince or 0)
        if overwhelming or held >= (U().config("guardChokeDisengageMs") or 2500) then
            state.withdrawn = true
            for _, record in ipairs(SC.Registry.records()) do
                if record.actor and matches(record.actor, state.post) then
                    record.runtime = record.runtime or {}
                    local peer = Post.forActor(record.actor, record.runtime, nil, now)
                    if peer then peer.withdrawn = true end
                end
            end
        end
    end
    return state.withdrawn == true
end

function Post.release(actor, player, state)
    if not state or not state.withdrawn or not player or not U().isValidActor(player) then return false end
    -- The established Retreat order preserves personal emergencies, native
    -- swing ownership, collision checks and the player tether. It also explains
    -- the new order through the existing acknowledgement/call-out path.
    return SC.Commands.issue(U().idOf(actor), "retreat", nil, player)
end

return Post
