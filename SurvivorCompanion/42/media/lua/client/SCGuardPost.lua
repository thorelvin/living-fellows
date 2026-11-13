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
    local cursor = 1
    for rank, peer in ipairs(members) do
        local square
        repeat
            if not slots[cursor] then break end
            square = slotSquare(peer, post, slots[cursor]); cursor = cursor + 1
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

function Post.atPosition(actor, state)
    local p = state and state.position
    local x, y, z = U().position(actor)
    return p and x ~= nil and math.floor(z or 0) == p.z
        and (x - p.x - 0.5)^2 + (y - p.y - 0.5)^2 <= (U().config("guardChokeHoldRadius") or 0.7)^2
end

function Post.move(actor, state, snapshot)
    local p = state and state.position
    if not p then U().stop(actor) return true, "guard_choke_no_room" end
    if Post.atPosition(actor, state) then
        if not U().stop(actor) then return false, "tactical_stop_rejected" end
        local post = state.post
        local faced = U().move(actor, "walk", { action = "face_alert", stableFacing = true,
            targetPosition = { x = p.x + 0.5 - post.dx * 2, y = p.y + 0.5 - post.dy * 2, z = p.z } })
        return faced == true, "guard_choke_holding"
    end
    return SC.Navigation.request(actor, U().gridSquare(p.x, p.y, p.z), "walk", {
        action = "return_to_guard", snapshot = snapshot, arrivalDistance = 0.65, requireSameSquare = true,
    })
end

function Post.observe(actor, runtime, plan, now)
    local state = runtime and runtime.guardPost
    if not state then return false end
    if plan and plan.mode == "disengage" then
        state.disengageSince = state.disengageSince or now
        if now - state.disengageSince >= (U().config("guardChokeDisengageMs") or 2500) then
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
