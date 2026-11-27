-- SPDX-License-Identifier: MIT
-- Local footwork for a fit lone fighter on verified open ground. All movement
-- belongs to the companion; zombie detection, pursuit and collisions stay native.
LivingFellows = LivingFellows or {}
local SC = LivingFellows
SC.MeleeKiting = SC.MeleeKiting or {}
local Kiting = SC.MeleeKiting

local function openLane(actor, ax, ay, az, dx, dy)
    local U = SC.GameplayUtil
    -- Prove the whole broad lane for each proposed heading, not just the next
    -- micro-step. A native sideways vector is still subject to this proof.
    for _, side in ipairs({-0.8, 0, 0.8}) do
        local x, y = ax + dx * 3 - dy * side, ay + dy * 3 + dx * side
        if not SC.Navigation.openSegment(actor, x, y, az) then return false, "lane_blocked" end
        for depth = 1, 3 do
            local square = U.gridSquare(math.floor(ax + dx * depth - dy * side),
                math.floor(ay + dy * depth + dx * side), az)
            local room, roomOk = U.call(square, "getRoom")
            local tree, treeOk = U.call(square, "HasTree")
            local solid, solidOk = U.call(square, "TreatAsSolidFloor")
            if not square or not roomOk or room ~= nil or not treeOk or tree
                or not solidOk or not solid or SC.Combat.atStairs(square) then return false, "lane_terrain" end
        end
    end
    return true
end

function Kiting.context(actor, snapshot, target, weapon, readiness)
    if not target or not target.actor or target.obstructed == true
        or not weapon or weapon.ranged or weapon.equipped == false
        or (tonumber(weapon.conditionRatio) or 0) < 0.2 then return nil, "target_or_weapon" end
    local state = SC.Combat.peek(actor)
    local burst = state and state.kiteBurst
    local turningRun = burst and burst.target == target.actor
        and SC.GameplayUtil.nowMs() < burst.untilAt + 400
    if target.visible ~= true and not turningRun then return nil, "unseen" end
    if readiness.indoors or readiness.support ~= 0 then return nil, "indoors_or_support" end
    if readiness.health < 85 or readiness.woundPressure > 0.5 or readiness.pain > 1 then return nil, "injury" end
    if readiness.staminaCritical
        or readiness.endurance <= (readiness.enduranceReserve or 0.3) + 0.08
        or readiness.tired > 1 or readiness.heavyLoad > 1 then return nil, "fatigue" end
    if readiness.footing.tree or snapshot.encircled
        or (tonumber(readiness.close) or 0) > 5
        or (tonumber(snapshot.incomingCount) or 0) > 5
        or #(snapshot.escapeSquares or {}) == 0
        or snapshot.humanThreat ~= nil
        or snapshot.squadPlan and snapshot.squadPlan.mode == "disengage"
        or not SC.Navigation or type(SC.Navigation.openSegment) ~= "function"
        or type(SC.Navigation.combatVector) ~= "function" then return nil, "unsafe_ground_or_crowd" end
    local U = SC.GameplayUtil
    local floor = select(1, U.call(target.actor, "isOnFloor"))
    if target.posture == "crawler"
        or SC.Combat.atStairs(actor) or SC.Combat.atStairs(target.actor) then return nil, "posture_or_stairs" end
    local ax, ay, az = U.position(actor)
    local tx, ty = U.position(target.actor)
    if ax == nil or tx == nil or not U.sameFloor(actor, target.actor) then return nil, "position" end
    local fx, fy = tx - ax, ty - ay
    local distance = math.sqrt(fx * fx + fy * fy)
    if distance < 0.01 or distance > 6 then return nil, "distance" end
    fx, fy = fx / distance, fy / distance
    local second, secondArrival, nearest, count = math.huge, math.huge, distance, 0
    for index = 1, math.min(#(snapshot.threats or {}), 32) do
        local threat = snapshot.threats[index]
        if threat.actor and threat.visible ~= false and threat.obstructed ~= true
            and threat.posture ~= "downed" and U.sameFloor(actor, threat.actor)
            and not U.isDead(threat.actor) then
            local zx, zy = U.position(threat.actor)
            if zx ~= nil then
                local dx, dy = zx - ax, zy - ay
                local gap = math.sqrt(dx * dx + dy * dy)
                if gap <= 6 then
                    count = count + 1
                    -- A clear rear lane is not permission to ignore a flank.
                    if gap < 0.01 or (dx * fx + dy * fy) / gap < 0.2 then return nil, "flank" end
                    nearest = math.min(nearest, gap)
                    if threat.actor ~= target.actor then
                        second = math.min(second, gap)
                        local speed = math.max(0.75, tonumber(threat.closingSpeed) or 0,
                            tonumber(target.closingSpeed) or 0)
                        secondArrival = math.min(secondArrival, (gap - 0.8) / speed)
                    end
                end
            end
        end
    end
    if count > 5 then return nil, "crowd" end
    local dx, dy, steered = SC.Navigation.combatVector(actor, target.actor, "backstep", snapshot)
    if dx == nil or dy == nil then return nil, "backstep_blocked" end
    local spacing = SC.Combat.meleeSpacing(actor, weapon.item, target)
    local curveWanted = spacing and spacing.maximum - spacing.nativeMinimum < 0.5
        and (secondArrival <= 1.2 or burst and burst.curve and turningRun)
    local curveEscape = false
    if curveWanted then
        local sideX, sideY = SC.Navigation.combatVector(actor, target.actor, "kite", snapshot, 3)
        if sideX ~= nil and sideY ~= nil then
            local cx, cy = dx + sideX, dy + sideY
            local length = math.sqrt(cx * cx + cy * cy)
            if length > 0.1 then
                cx, cy = cx / length, cy / length
                local nativeClear = true
                if U.hasMethod(actor, "isCompanionMovementClear") then
                    nativeClear = select(1, U.call(actor, "isCompanionMovementClear",
                        ax + cx * 0.45, ay + cy * 0.45, az)) == true
                end
                -- Gain distance while changing the pursuit angle. A purely
                -- sideways turn at grabbing range would give that space away.
                if cx * fx + cy * fy < -0.45 and math.abs(cx * fy - cy * fx) > 0.35
                    and nativeClear and openLane(actor, ax, ay, az, cx, cy) then
                    dx, dy, steered, curveEscape = cx, cy, true, true
                end
            end
        end
    end
    local clear, reason = openLane(actor, ax, ay, az, dx, dy)
    if not clear then
        -- Do not back straight into the edge of a field forever. Ask the
        -- companion's ordinary steering for a sideways heading, then prove its
        -- full lane independently before allowing the same bounded footwork.
        local sideX, sideY = SC.Navigation.combatVector(actor, target.actor, "kite", snapshot, 3)
        if sideX == nil or sideY == nil then return nil, reason end
        local sideClear, sideReason = openLane(actor, ax, ay, az, sideX, sideY)
        if not sideClear then return nil, sideReason end
        dx, dy, steered = sideX, sideY, true
    end
    return { distance = distance, nearest = nearest, second = second,
        secondArrival = secondArrival, count = count, spacing = spacing,
        curveEscape = curveEscape,
        grounded = floor == true or target.posture == "downed",
        moveX = dx, moveY = dy, microSteered = steered == true, x = ax, y = ay }, "open"
end

-- Scoring is side-effect free. Only an accepted movement starts a burst.
function Kiting.action(actor, target, weapon, readiness, context, state, now)
    -- Risk can use this clear lane while target selection catches up. Only the
    -- nearest pursuer gets the counterattack/footwork offer for this pulse.
    if context.grounded or context.distance > context.nearest + 0.15 then return nil end
    local spacing = context.spacing or SC.Combat.meleeSpacing(actor, weapon.item, target)
    if not spacing then return nil end
    local distance, second = context.distance, context.second
    local burst = state.kiteBurst
    local running = burst and burst.target == target.actor and now < burst.untilAt
        and (context.x - burst.x)^2 + (context.y - burst.y)^2 < 2.8^2
        and distance < spacing.maximum + 1.6
    local closing = math.max(0, tonumber(target.closingSpeed) or 0)
    local band = math.max(0.08, spacing.maximum - spacing.nativeMinimum)
    local lead = closing >= 0.65 and math.min(0.32, closing * 0.42, band * 0.65) or 0
    if lead < 0.08 then lead = 0 end
    local strikeSafe = second > math.max(spacing.maximum + 0.55, distance + 0.4)
        -- A short stabbing tool cannot knock the next pursuer back. Leave
        -- enough arrival time to finish the native swing and recover first.
        and (band >= 0.5 or context.secondArrival > 1.2)
        and target.visible == true and target.bearing == "front"
        and target.attacking ~= true and distance >= spacing.nativeMinimum + 0.08
        and distance <= spacing.maximum + lead
    local controlOpening = not running and band < 0.5 and context.count > 1
        and context.secondArrival <= 1.2 and distance <= 1.15
        and now >= (state.kiteControlUntil or 0)
        and target.visible == true and target.bearing == "front"
    if controlOpening then
        -- A knife has little knockback. Use the normal defensive shove to
        -- break a cluster, then let native knockdown and finisher logic act.
        return { kind = "shove", score = 175, localKite = true, kiteControl = true }
    end
    if not running and strikeSafe then
        return { kind = "melee", score = 160, localKite = true,
            anticipatorySwing = distance > spacing.maximum,
            anticipatoryLead = lead, closingSpeed = closing }
    end
    if distance < spacing.nativeMinimum + 0.12 then
        return { kind = "shove", score = 170, localKite = true }
    end
    local crowded = context.curveEscape or second < spacing.maximum + 0.9
        or distance < spacing.defend + 0.2
    if running or not burst and crowded and distance >= 1.05
        and now >= (state.kiteRunCooldown or 0) then
        return { kind = "backstep", score = 160, localKite = true, kiteRun = true,
            kiteCurve = context.curveEscape == true,
            moveX = context.moveX, moveY = context.moveY,
            microSteered = context.microSteered }
    end
    if distance < spacing.desired or crowded then
        return { kind = "backstep", score = 160, localKite = true,
            moveX = context.moveX, moveY = context.moveY,
            microSteered = context.microSteered }
    end
    if distance > math.max(3.5, spacing.maximum + 1.8) then
        return { kind = "approach", score = 150, localKite = true,
            minimumDistance = spacing.maximum + 0.3 }
    end
    local waiting = state.kiteWait
    if waiting and waiting.target == target.actor and now - waiting.at >= 1200
        and closing < 0.25 and distance > spacing.maximum + 0.1
        and second > spacing.maximum + 0.55
        and target.visible == true and target.bearing == "front"
        and target.attacking ~= true then
        -- The pursuer stopped outside reach. Re-enter under guard instead of
        -- holding a permanent empty swing gap. Forward clearance and native
        -- recovery still belong to the ordinary approach execution gates.
        return { kind = "approach", score = 150, localKite = true,
            stalledApproach = true, minimumDistance = spacing.desired }
    end
    -- Let the pursuer enter this weapon's band. Walking away on every pulse
    -- matches its speed and permanently starves short blades of a swing.
    return { kind = "hold_range", score = 150, localKite = true }
end

function Kiting.accept(actor, target, action, state, now)
    if action.kiteControl then state.kiteControlUntil = now + 1600 end
    if action.kiteRun then
        if not state.kiteBurst or state.kiteBurst.target ~= target
            or now >= state.kiteBurst.untilAt then
            local x, y = SC.GameplayUtil.position(actor)
            state.kiteBurst = { target = target, x = x, y = y, untilAt = now + 1300,
                curve = action.kiteCurve == true }
        end
    elseif state.kiteBurst then
        state.kiteBurst = nil
        state.kiteRunCooldown = now + 650
    end
    if action.localKite and action.kind == "hold_range" and not action.recoveryReason then
        local gap = math.sqrt(SC.GameplayUtil.distanceSq(actor, target))
        local waiting = state.kiteWait
        if not waiting or waiting.target ~= target or gap < waiting.distance - 0.15 then
            state.kiteWait = { target = target, at = now, distance = gap }
        end
    else
        state.kiteWait = nil
    end
end

return Kiting
