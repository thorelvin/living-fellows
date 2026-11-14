-- SPDX-License-Identifier: MIT
-- Only the three pieces of a connected, loaded staircase are observed.
local SC = SurvivorCompanion
SC.StairCombat = SC.StairCombat or {}
local Stair = SC.StairCombat
local directions = { { 0, 1 }, { 1, 0 }, { 0, -1 }, { -1, 0 } }
local function U() return SC.GameplayUtil end
local function piece(square, prefix)
    if not square or not SC.Topology.squareHasStairs(square) then return false end
    local found = false
    U().squareObjects(square, function(object)
        if select(1, U().call(object, "isStairsObject")) == true
            and tostring((U().call(object, "getType"))):find(prefix, 1, true) == 1 then
            found = true; return false
        end
    end, 16)
    return found
end

function Stair.column(actor, state, now)
    local ax, ay, az = U().position(actor)
    if ax == nil or math.floor(az or 0) < 1 then return nil end
    local x, y, z = math.floor(ax), math.floor(ay), math.floor(az)
    local data = U().modData(actor)
    if data and (data.SC_Order == "guard" or data.SC_Order == "stay")
        and data.SC_AnchorZ == z and type(data.SC_AnchorX) == "number"
        and type(data.SC_AnchorY) == "number"
        and (ax - data.SC_AnchorX)^2 + (ay - data.SC_AnchorY)^2 <= 36 then
        x, y = math.floor(data.SC_AnchorX), math.floor(data.SC_AnchorY)
    end
    local key = x .. ":" .. y .. ":" .. z
    if state.columnKey == key and now < (state.columnNextAt or 0) then return state.column end
    state.columnKey, state.columnNextAt, state.column = key, now + 500, nil
    for _, offset in ipairs({ { 0, 0 }, { 0, 1 }, { 1, 0 }, { 0, -1 }, { -1, 0 } }) do
        local lx, ly = x + offset[1], y + offset[2]
        local landing = U().gridSquare(lx, ly, z)
        if landing and select(1, U().call(landing, "TreatAsSolidFloor")) == true
            and not SC.Topology.squareHasStairs(landing) then
            for _, d in ipairs(directions) do
                if piece(U().gridSquare(lx + d[1], ly + d[2], z - 1), "stairsT")
                    and piece(U().gridSquare(lx + d[1] * 2, ly + d[2] * 2, z - 1), "stairsM")
                    and piece(U().gridSquare(lx + d[1] * 3, ly + d[2] * 3, z - 1), "stairsB") then
                    state.column = { x = lx, y = ly, z = z, dx = d[1], dy = d[2] }
                    return state.column
                end
            end
        end
    end
end

function Stair.onColumn(facts, column)
    if not column or not facts or not facts.x or facts.gone or not facts.zombie
        or math.floor(facts.z or 0) ~= column.z - 1 then return false end
    local x, y = math.floor(facts.x), math.floor(facts.y)
    for i = 1, 3 do
        if x == column.x + column.dx * i and y == column.y + column.dy * i then return true end
    end
    return false
end

-- A knocked-back climber may retain its target but abandon its native path.
-- Retry that existing pursuit only after an idle stall, never acquire a target
-- through the floor. Records come from this observed column, not a world scan.
local function maintainPursuit(actor, zombie, entry, column, now)
    local facts = SC.ZombieFacts.get(zombie)
    if facts.gone or not facts.zombie or facts.target ~= actor or facts.posture ~= "standing"
        or facts.z >= column.z or math.floor(facts.z) ~= column.z - 1
        or (facts.x - column.x - 0.5)^2 + (facts.y - column.y - 0.5)^2 > 25
        or U().isALifeHordeHeld(zombie)
        or select(1, U().call(zombie, "isUseless")) == true
        or select(1, U().call(zombie, "getCurrentStateName")) ~= "ZombieIdleState" then
        entry.idleSince = nil; return
    end
    entry.idleSince = entry.idleSince or now
    if now - entry.idleSince >= 1500 and now >= (entry.nextPathAt or 0) then
        entry.nextPathAt = now + 3000
        U().call(zombie, "pathToCharacter", actor)
    end
end

-- Separate forecast evidence. These actors never enter the attackable lists.
function Stair.incoming(actor, state, now)
    state.stairs = state.stairs or {}
    local memory = state.stairs
    if now < (memory.nextIncomingAt or 0) then return memory.incoming or {} end
    memory.nextIncomingAt = now + 250
    local column = Stair.column(actor, memory, now)
    local landing = column and U().gridSquare(column.x, column.y, column.z)
    if not landing or not U().canSee(actor, landing) then
        memory.progress, memory.incoming, memory.known = nil, nil, nil; return {}
    end
    local records, progress, seen, known, count = {}, {}, {}, {}, 0
    for zombie, entry in pairs(memory.known or {}) do
        if count < 24 and now - entry.seenAt <= 30000 then
            known[zombie], count = entry, count + 1
        end
    end
    for i = 1, 3 do
        local square = U().gridSquare(column.x + column.dx * i, column.y + column.dy * i, column.z - 1)
        local objects = select(1, U().call(square, "getMovingObjects"))
        local objectCount = objects and SC.NativeList.size(objects) or 0
        for index = 0, math.min(8, objectCount) - 1 do
            local zombie = SC.NativeList.get(objects, index)
            if zombie and not seen[zombie] then
                seen[zombie] = true
                local facts = SC.ZombieFacts.get(zombie)
                if Stair.onColumn(facts, column) then
                    if not known[zombie] and count < 24 then known[zombie], count = {}, count + 1 end
                    if known[zombie] then known[zombie].seenAt = now end
                end
                if Stair.onColumn(facts, column) and facts.posture == "standing" then
                    local prior = memory.progress and memory.progress[zombie]
                    local rising = prior and facts.z > prior.z + 0.005
                    local upAt = rising and now or prior and prior.upAt
                    progress[zombie] = { z = facts.z, upAt = upAt }
                    if upAt and now - upAt <= 1200 then
                        records[#records + 1] = { actor = zombie, x = facts.x, y = facts.y, z = facts.z,
                            column = column, observedAt = now, stairIncoming = true,
                            arrivingMs = math.max(300, (column.z - facts.z) * 8000) }
                    end
                end
            end
        end
    end
    for zombie, entry in pairs(known) do maintainPursuit(actor, zombie, entry, column, now) end
    memory.progress, memory.incoming, memory.known = progress, records, known
    return records
end

local function atLanding(target, column)
    if SC.Combat.atStairs(target) then return true end
    local x, y, z = U().position(target)
    return column and x and z >= column.z - 0.5 and z <= column.z + 0.1
        and (x - column.x - 0.5)^2 + (y - column.y - 0.5)^2 <= 1.6^2
end

function Stair.observe(actor, state, evidence, now)
    local target = evidence.target
    if not target or not SC.ZombieFacts.get(target).zombie then return end
    local healthBefore, healthAfter = tonumber(evidence.healthBefore), tonumber(evidence.healthAfter)
    if healthBefore and healthAfter and healthAfter < healthBefore - 0.001 then
        state.stairShoves = nil; return
    end
    if not atLanding(target, Stair.column(actor, state, now)) then return end
    if evidence.action == "shove" and evidence.result == "landed" then
        local old = state.stairShoves
        state.stairShoves = { target = target, count = old and old.target == target
            and now - old.at <= 20000 and old.count + 1 or 1, at = now }
    end
end

local function canOpenLanding(actor, runtime, snapshot, column, target)
    local seen, count = {}, 0
    local function consider(zombie)
        if not zombie or seen[zombie] then return end
        seen[zombie] = true
        local facts = SC.ZombieFacts.get(zombie)
        if facts.zombie and not facts.gone and (facts.posture ~= "downed" or facts.gettingUp)
            and (Stair.onColumn(facts, column) or atLanding(zombie, column)) then count = count + 1 end
    end
    consider(target)
    for index, threat in ipairs(snapshot.threats or {}) do
        if index > 24 then break end; consider(threat.actor)
    end
    for index, entry in ipairs(snapshot.stairIncoming or {}) do
        if index > 24 then break end; consider(entry.actor)
    end
    local stairs = runtime.senses and runtime.senses.stairs
    for zombie in pairs(stairs and stairs.known or {}) do consider(zombie) end
    return count <= 1
end

function Stair.recovery(actor, runtime, snapshot, now)
    local state = SC.Combat and SC.Combat.peek(actor)
    if not state then return nil end
    runtime.stairCombat = runtime.stairCombat or {}
    local memory = runtime.stairCombat
    local data = U().modData(actor) or {}
    local serial = tonumber(data.SC_CommandSerial) or 0
    if not data.SC_Recruited or (data.SC_Order ~= "guard" and data.SC_Order ~= "stay"
        and data.SC_Order ~= "follow" and data.SC_Order ~= "regroup")
        or select(1, U().call(actor, "getVehicle")) ~= nil then
        memory.recovery, state.stairShoves = nil, nil; return nil
    end
    local recovery = memory.recovery
    if recovery and recovery.serial ~= serial then
        memory.recovery, state.stairShoves = nil, nil; return nil
    end
    if recovery then
        if now >= recovery.expires or (U().isGoneTarget(recovery.target)
            and #(snapshot.stairIncoming or {}) == 0 and #(snapshot.threats or {}) == 0) then
            memory.recovery = nil
            return nil
        end
        return recovery
    end
    local shoves = state.stairShoves
    local stuck = state.noEffectTarget and (tonumber(state.noEffectCollisions) or 0) >= 2
        and atLanding(state.noEffectTarget, Stair.column(actor, memory, now))
    local target = shoves and shoves.count >= 2 and now - shoves.at <= 20000 and shoves.target
        or stuck and state.noEffectTarget
    if not target or U().isGoneTarget(target) or not SC.ZombieFacts.get(target).zombie then return nil end
    local column = Stair.column(actor, memory, now)
    if not column then return nil end
    if not canOpenLanding(actor, runtime, snapshot, column, target) then return nil end
    local goal = SC.GuardPost.stairSetback(actor, {
        x = column.x, y = column.y, z = column.z, dx = -column.dx, dy = -column.dy,
    })
    if not goal then return nil end
    if runtime.guardPost and runtime.guardPost.post.kind == "stairs" then
        if not SC.GuardPost.stairInset(actor, runtime, 1, now) then return nil end
        local p = runtime.guardPost.position
        goal = U().gridSquare(p.x, p.y, p.z)
    end
    memory.recovery = { target = target, column = column, goal = goal, startedAt = now,
        expires = now + 15000, serial = serial }
    U().diagnostic("stair-reset", actor, "opening landing after repeated shoves or ineffective hits")
    state.stairShoves, state.noEffectCollisions = nil, 0
    return memory.recovery
end

-- The whole guard line must clear its old positions, including a peer that
-- did not make the shove. Combat destinations are centres, not grid corners.
function Stair.resetGoal(actor, runtime, snapshot, now)
    local recovery = Stair.recovery(actor, runtime, snapshot or {}, now)
    local post = runtime.guardPost
    local data = U().modData(actor) or {}
    local goal
    if post and post.serial == (tonumber(data.SC_CommandSerial) or 0)
        and post.insetUntil and now < post.insetUntil then
        goal = post.position
    else goal = recovery and recovery.goal end
    if not goal then return nil end
    local x, y, z = U().position(goal)
    return { x = x + 0.5, y = y + 0.5, z = z }
end

function Stair.hold(actor, runtime, snapshot, now)
    now = now or U().nowMs()
    local goal = Stair.resetGoal(actor, runtime, snapshot, now)
    if not goal then return nil end
    if runtime.guardPost then return SC.GuardPost.move(actor, runtime.guardPost, snapshot) end
    local recovery = runtime.stairCombat.recovery
    if U().distance(actor, goal) <= 0.3 then
        U().stop(actor)
        return U().move(actor, "walk", { action = "face_alert", stableFacing = true,
            targetPosition = recovery.column }), "stair_landing_wait"
    end
    return SC.Navigation.request(actor, recovery.goal, "walk", {
        action = "return_to_guard", snapshot = snapshot, arrivalDistance = 0.25, requireSameSquare = true,
    })
end

return Stair
