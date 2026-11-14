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

function Post.atPosition(actor, state)
    local p = Post.point(state)
    local x, y, z = U().position(actor)
    return p and x ~= nil and math.floor(z or 0) == p.z
        and (x - p.x)^2 + (y - p.y)^2 <= (state.inset and 0.3 or state.post.kind == "stairs" and math.min(0.3, U().config("guardChokeHoldRadius") or 0.7) or U().config("guardChokeHoldRadius") or 0.7)^2
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

-- A covered stair entrance differs from an open indoor fight only while all
-- standing contacts remain on its approach side.
-- Keep the complete physical observation for routes, strikes and squad forecasts.
-- A zombie committed to another fit guard is not also this guard's personal
-- attacker until it reaches body contact. Reconsider on every combat update.
function Post.combatView(actor, player, state, snapshot)
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
    if state.post.kind == "stairs" and state.rank == 1 and not state.inset
        and U().distance(actor, point) <= 1.25
        and SC.Navigation.openSegment(actor, point.x, point.y, point.z) then
        local accepted, why = U().move(actor, "walk", { action = "return_to_guard",
            targetPosition = point, movementTarget = true, movementArrivalTolerance = 0.08,
            dx = point.x - select(1, U().position(actor)), dy = point.y - select(2, U().position(actor)),
            movementTargetTtlMs = 750 })
        return accepted, accepted and "guard_landing_align" or why
    end
    return SC.Navigation.request(actor, U().gridSquare(p.x, p.y, p.z), "walk", {
        action = "return_to_guard", snapshot = snapshot, arrivalDistance = state.post.kind == "stairs" and 0.25 or 0.65, requireSameSquare = true,
    })
end

function Post.observe(actor, runtime, plan, now)
    local state = runtime and runtime.guardPost
    if not state then return false end
    if plan and plan.mode == "disengage" then
        state.disengageSince = state.disengageSince or now
        local overwhelming = (tonumber(plan.forecast) or 0) >= (tonumber(plan.capacity) or math.huge) + 4
        if overwhelming or now - state.disengageSince >= (U().config("guardChokeDisengageMs") or 2500) then
            state.withdrawn = true
            for _, record in ipairs(SC.Registry.records()) do
                if record.actor and matches(record.actor, state.post) then
                    record.runtime = record.runtime or {}
                    local peer = Post.forActor(record.actor, record.runtime, nil, now)
                    if peer then peer.withdrawn = true end
                end
            end
        end
    else state.disengageSince = nil end
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
